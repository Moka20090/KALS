// ops2q's page draw in C# (moved here from kOS for speed).
// lib_o2ui o2Render (+ o2RowStr, o2TimeShow) and lib_o2disp o2DispPage's title / rows, o2DispGrid's cell texts, the cells'
// and the STEP box's visibility and the STEP text, the same writes in the same cases (o2Set: a widget's text written only on a
// change, compared as kOS's = does, ignoring case; the entries of kOS's own o2Last written too, so a kOS draw after a C# one
// stays consistent). kOS keeps: the nav and grid lights (o2Lit), the grid's widths (on a width change), the sprites / view,
// the page builders. None of it throws into kOS:
//   O2SETUP(LEXICON(title, rows, cells, boxes, stepbox, stepl, c, last, nrows)) -> "" / "error ..."
//   O2DRAW(pg, LEXICON(title, cur, typ, buf, mode, wide, step)) -> "" / "error ..." (kOS then draws itself)
//   O2ERROR, O2N (draws), O2MS (the mean ms a draw).
//   O2VSETUP(LEXICON(spr, wh, dir, cx, cy, r, n, epx, altx)) -> "" / "error ...";  O2VIEW(el, pl, LEXICON(rb, dt, hi)) -> the
//   new o2SprHi / -1 (phase 2: ops2q.ks o2qView whole); O2VERROR, O2VN, O2VMS.
// The orbit view's line: the orbit and the planned path are each ONE anti-aliased RGBA image (the
//   page green / yellow, the plan dashed) rendered here and written to <archive>/logs/o2ov_o_<n>.png / o2ov_p_<n>.png (a new <n> per render), shown by one sprite
//   slot each; every drawn thing (the line, A / P, AN / DN, the orbiter, the TIG tick) comes from ONE LATCHED copy of the conic,
//   re-latched (and the images re-rendered) only when the live orbit has moved the drawn geometry by more than O2V_TOL px (or the
//   scale / the plan changes), at most every O2V_MINDT s: so the markers sit on the line and step only when it does.
//   O2VSETUP's optional keys: line (TRUE default: the images; FALSE the dots), ldir ("logs/", relative to the archive);
//   O2VIEW's optional key t (the clock, s, for the re-latch spacing; none = the wall clock); O2VLN (images rendered), O2VLMS,
//   O2VLERROR (why the images are off, "" when on).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public class OdHost
    {
        Structure title, stepBox, stepL;
        readonly List<Structure[]> rows = new List<Structure[]>();
        readonly List<Structure> cells = new List<Structure>(), boxes = new List<Structure>();
        readonly Dictionary<string, string> col = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        Lexicon last;
        int nRows;
        bool ready;
        public string Error = "";
        public int N = 0;
        double ms = 0; int msN = 0;

        static readonly string[] GridType = { "7", "8", "9", "-", "CANCEL", "", "4", "5", "6", ".", "BKSP", "", "1", "2", "3", "0", "ENT", "CUT OFF" };
        static readonly string[] GridRhc = { "Q  −", "W  ↑", "E  +", "INPUT PAGE", "INPUT RHC", "", "A  ←", "SPACE  ENT", "D  →",
            "AG4  TYPE", "CANCEL", "", "STEP x10", "S  ↓", "STEP /10", "CUT OFF", "", "" };
        static readonly string[] GridPage = { "−", "↑", "+", "INPUT PAGE", "INPUT RHC", "", "←", "ENT", "→",
            "TYPE", "CANCEL", "", "STEP x10", "↓", "STEP /10", "CUT OFF", "", "" };

        static Structure G(Lexicon l, string k) { return l[new StringValue(k)]; }
        static string S(Structure v) { return v == null ? "" : v.ToString(); }
        static double D(Structure v) { return ((ScalarValue)v).GetDoubleValue(); }
        static bool B(Structure v) { return ((BooleanValue)v).Value; }
        static List<Structure> L(Structure v) { var o = new List<Structure>(); foreach (var x in (ListValue)v) o.Add(x); return o; }

        public StringValue Setup(Lexicon a)
        {
            try
            {
                title = G(a, "title"); stepBox = G(a, "stepbox"); stepL = G(a, "stepl"); last = (Lexicon)G(a, "last");
                nRows = (int)D(G(a, "nrows"));
                rows.Clear(); foreach (var r in L(G(a, "rows"))) rows.Add(L(r).ToArray());
                cells.Clear(); cells.AddRange(L(G(a, "cells")));
                boxes.Clear(); boxes.AddRange(L(G(a, "boxes")));
                col.Clear(); foreach (var kv in (Lexicon)G(a, "c")) col[S(kv.Key)] = S(kv.Value);
                if (rows.Count < nRows || cells.Count < 18 || boxes.Count < 18) throw new Exception("widgets missing");
                ready = true; Error = ""; return new StringValue("");
            }
            catch (Exception ex) { ready = false; Error = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + Error); }
        }

        // ---- o2Set / visibility
        void Set(string key, Structure w, string txt)
        {
            var k = new StringValue(key);
            if (last.ContainsKey(k) && string.Equals(S(last[k]), txt, StringComparison.OrdinalIgnoreCase)) return;
            last[k] = new StringValue(txt);
            w.SetSuffix("TEXT", new StringValue(txt));
        }
        static bool Vis(Structure w) { return B(w.GetSuffix("VISIBLE").Value); }
        static void Show(Structure w, bool on) { if (Vis(w) != on) w.SetSuffix("VISIBLE", on ? BooleanValue.True : BooleanValue.False); }

        // ---- o2Render
        class Seg { public double Col; public string Txt, Cls; }
        string RowStr(List<Seg> l, int c0, int c1, out int reached)
        {
            var s = new StringBuilder();
            int n = c0;
            foreach (var sg in l)
            {
                string t = sg.Txt;
                int c = (int)sg.Col;
                if (c < n) { int cut = n - c; t = cut >= t.Length ? "" : t.Substring(cut, t.Length - cut); c = n; }
                if (c + t.Length > c1) t = c >= c1 ? "" : t.Substring(0, c1 - c);
                if (t != "")
                {
                    if (c > n) s.Append(' ', c - n);
                    if (string.Equals(sg.Cls, "L", StringComparison.OrdinalIgnoreCase)) s.Append(t);
                    else s.Append("<color=").Append(col[sg.Cls]).Append('>').Append(t).Append("</color>");
                    n = c + t.Length;
                }
            }
            reached = n;
            return s.ToString();
        }
        static string TimeShow(string b)
        {
            string d = b.PadLeft(9).Replace(' ', '0');
            return d.Substring(0, 3) + "/" + d.Substring(3, 2) + ":" + d.Substring(5, 2) + ":" + d.Substring(7, 2);
        }
        static string NbSp(string s)
        {
            int n = 0;
            while (n < s.Length && s[s.Length - 1 - n] == ' ') n++;
            if (n == 0) return s;
            return s.Substring(0, s.Length - n) + new string(' ', n);
        }

        static string AllNb(string s) { return s.Replace(' ', ' '); }
        // the drop-down cell's background (lib_o2disp o2DdBg: written on a change, kOS's o2Last key "b<row>") and its
        // two outline bars (o2DdEdges)
        void DdBg(int i, Structure w, string bg)
        {
            string nm = "cur";
            if (bg == "k") nm = "ddk"; else if (bg == "kt") nm = "ddkt"; else if (bg == "kb") nm = "ddkb"; else if (bg == "tb") nm = "ddtb";
            var k = new StringValue("b" + i);
            if (last.ContainsKey(k) && string.Equals(S(last[k]), nm, StringComparison.OrdinalIgnoreCase)) return;
            last[k] = new StringValue(nm);
            w.GetSuffix("STYLE").Value.SetSuffix("BG", new StringValue("o2_bg/" + nm + ".png"));
        }
        static void DdEdges(Structure[] w, bool on)
        {
            if (w.Length < 5) return;
            if (Vis(w[3]) != on) { Show(w[3], on); Show(w[4], on); }
        }

        public StringValue Draw(Lexicon pg, Lexicon st)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (!ready) throw new Exception("O2SETUP not done");
                // the rows' segments, each row's sorted by column (insertion after the equal ones, as o2Render)
                var byRow = new List<List<Seg>>();
                for (int i = 0; i < nRows; i++) byRow.Add(new List<Seg>());
                foreach (var x in (ListValue)G(pg, "seg"))
                {
                    var sl = (ListValue)x;
                    double r = D(sl[0]);
                    if (r >= 0 && r < nRows)
                    {
                        var sg = new Seg { Col = D(sl[1]), Txt = S(sl[2]), Cls = S(sl[3]) };
                        var l = byRow[(int)r];
                        int k = 0;
                        while (k < l.Count && !(l[k].Col > sg.Col)) k++;
                        l.Insert(k, sg);
                    }
                }
                var txt = new string[nRows];
                int dummy;
                for (int i = 0; i < nRows; i++) txt[i] = RowStr(byRow[i], 0, 999, out dummy);
                int curRow = -1; string curT = "", pre = "", post = "";
                var f = (Lexicon)G(st, "cur");
                // an open drop-down list (lib_o2ui o2DdLayout, the same cells): its rows replace the cursor box
                var ddRows = new Dictionary<int, string[]>();      // row -> text, bg, pre, post
                var ddk = new StringValue("dd");
                if (st.ContainsKey(ddk))
                {
                    var dd = (Lexicon)st[ddk];
                    if (dd.Count > 0)
                    {
                        int icol = (int)D(G(dd, "col")), iw = (int)D(G(dd, "w"));
                        foreach (var x in (ListValue)G(dd, "cells"))
                        {
                            var cl = (ListValue)x;
                            int rw = (int)D(cl[0]);
                            if (rw < 0 || rw >= nRows) continue;
                            var l2 = byRow[rw];
                            int vis2, dm2;
                            string p2 = RowStr(l2, 0, icol, out vis2);
                            if (vis2 < icol) p2 = p2 + new string(' ', icol - vis2);
                            ddRows[rw] = new[] { S(cl[1]), S(cl[2]), p2, RowStr(l2, icol + iw, 999, out dm2) };
                        }
                    }
                }
                if (f.Count > 0 && ddRows.Count == 0)
                {
                    string t = S(G(f, "txt"));
                    if (B(G(st, "typ")))
                    {
                        string b = S(G(st, "buf"));
                        if (string.Equals(S(G(f, "kind")), "T", StringComparison.OrdinalIgnoreCase)) b = TimeShow(b);
                        t = b.PadLeft(Math.Max(t.Length, b.Length + 1));
                    }
                    curRow = (int)D(G(f, "row")); int c = (int)D(G(f, "col"));
                    curT = t;
                    var l = byRow[curRow];
                    post = RowStr(l, c + t.Length, 999, out dummy);
                    int vis;
                    pre = RowStr(l, 0, c, out vis);
                    if (vis < c) pre = pre + new string(' ', c - vis);
                }
                // o2DispPage: the title, the rows
                Set("title", title, "<b>" + S(G(st, "title")) + "</b>");
                for (int i = 0; i < nRows; i++)
                {
                    var w = rows[i];
                    string[] dr;
                    if (ddRows.TryGetValue(i, out dr))
                    {
                        Set("a" + i, w[0], NbSp(dr[2]));
                        Set("c" + i, w[1], AllNb(dr[0]));
                        Set("d" + i, w[2], dr[3]);
                        DdBg(i, w[1], dr[1]);
                        Show(w[1], true);
                        DdEdges(w, true);
                    }
                    else if (i == curRow)
                    {
                        Set("a" + i, w[0], NbSp(pre));
                        Set("c" + i, w[1], curT);
                        Set("d" + i, w[2], post);
                        DdBg(i, w[1], "a");
                        Show(w[1], true);
                        DdEdges(w, false);
                    }
                    else
                    {
                        Show(w[1], false);
                        Set("a" + i, w[0], txt[i]);
                        Set("d" + i, w[2], "");
                        DdEdges(w, false);
                    }
                }
                // o2DispGrid: the texts, the cells' and the STEP box's visibility, the STEP text
                string mode = S(G(st, "mode"));
                bool ty = string.Equals(mode, "TYPE", StringComparison.OrdinalIgnoreCase);
                string[] gt = ty ? GridType : string.Equals(mode, "RHC", StringComparison.OrdinalIgnoreCase) ? GridRhc : GridPage;
                // the PDRS page has its CUT OFF slot split: cell 15 = EE CAM, cell 16 = STOP (shown)
                bool split = !ty && st.ContainsKey(new StringValue("split")) && B(G(st, "split"));
                if (split) { gt = (string[])gt.Clone(); gt[15] = "EE CAM"; gt[16] = "STOP"; }
                for (int i = 0; i < 18; i++)
                {
                    int cc = i % 6;
                    // the TYPE keypad has CUT OFF in the sixth column (cell 17); the other modes have 5 columns and
                    // CUT OFF as the widened cell 15, cell 16 under it hidden. ARM / EXEC (cells 5, 11) are page items
                    bool show = ty ? (cc < 5 || i == 17) : (cc < 5 && (i != 16 || split));
                    if (show) Set("g" + i, cells[i], gt[i]);
                    Show(boxes[i], show);
                }
                Show(stepBox, !ty);
                Set("step", stepL, S(G(st, "step")));
                ms += sw.Elapsed.TotalMilliseconds; msN++; N++;
                return new StringValue("");
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + Error); }
        }
        public string Ms() { return msN == 0 ? "-" : (ms / msN).ToString("F4") + " ms/call over " + msN; }

        // ==== ops2q's orbit view (ops2q.ks o2qView whole, lib_o2orb's view math, lib_o2disp's sprite slots)
        // The lines are recomputed every call (kOS's o2qVw 1 s cache is kOS's alone); the slots (o2Spr's LISTs: label, name,
        // x, y, on, flow) are read and written in place exactly as o2SprPut / o2SprTxt / o2SprOff / o2SprFrom do, so kOS can
        // draw the view itself at any call. Trig in degrees, ROUND = Math.Round (half to even), MOD = %, numbers to text by
        // ScalarValue's own ToString, string '=' and STARTSWITH ignoring case (kOS's).
        ListValue spr; Lexicon sprWH; string dir = "";
        double vCx, vCy, vR, vEpx, vAltx; int vN; bool vReady;
        const double O2V_TOL = 0.5, O2V_MINDT = 0.5;   // the re-latch threshold (px) and the least spacing (s)
        bool lineOn; string ovDir = "", ovRel = "logs/"; int ovS;   // the images: on, the folder, the side (px)
        public string LError = ""; public int LN = 0; double lms = 0;
        Conic latEl, latPl, latAp; bool latHas; int latRe; double latSc, latT, latApT;   // the latch (latAp: the A / P diamonds')
        readonly HashSet<string> ovForce = new HashSet<string>();         // image slots whose IMAGE must be set again (new file)
        System.Reflection.FieldInfo texCacheF, texF;
        // every rendered image gets a NEW file name (o2ov_o_<n>.png): kOS's texture cache (Widget.GetTexture) compares the cached
        // entry's FileInfo.LastWriteTime with a fresh one, and Mono reads a FileInfo's time lazily, at that first compare, AFTER the file
        // changed: the cached entry then "matches" and the old texture comes back, so a file rewritten under one name showed stale
        // (every other renewal at best). A new name is a cache miss: always a fresh load.
        static int ovSeqS = Environment.TickCount & 0x3FFFFFFF;           // process-wide, so a later script run never reuses a cached name
        readonly Dictionary<string, string> ovCur = new Dictionary<string, string>();     // slot -> the newest file written (relative)
        readonly Dictionary<string, string> ovShown = new Dictionary<string, string>();   // slot -> the file its label was set to
        public string VError = ""; public int VNn = 0; double vms = 0; int vmsN = 0;

        public StringValue VSetup(Lexicon a)
        {
            try
            {
                spr = (ListValue)G(a, "spr"); sprWH = (Lexicon)G(a, "wh"); dir = S(G(a, "dir"));
                vCx = D(G(a, "cx")); vCy = D(G(a, "cy")); vR = D(G(a, "r")); vN = (int)D(G(a, "n"));
                vEpx = D(G(a, "epx")); vAltx = D(G(a, "altx"));
                DropAllImg();                                  // the last setup's images (a re-RUN, the view set up again)
                latEl = null; latPl = null; ovForce.Clear(); ovCur.Clear(); ovShown.Clear(); glbKey = "";
                lineOn = !(a.ContainsKey(new StringValue("line")) && !B(G(a, "line")));
                LError = "";
                if (a.ContainsKey(new StringValue("ldir"))) ovRel = S(G(a, "ldir"));
                ovS = 2 * (int)Math.Ceiling(vR) + 16;
                if (lineOn)
                {
                    try
                    {
                        ovDir = Path.Combine(SafeHouse.ArchiveFolder, ovRel); Directory.CreateDirectory(ovDir);
                        foreach (var f in Directory.GetFiles(ovDir, "o2ov_*.png*")) { try { File.Delete(f); } catch (Exception) { } }   // the last run's images
                    }
                    catch (Exception ex) { lineOn = false; LError = "folder: " + ex.GetType().Name + ": " + ex.Message; }
                }
                else LError = "line off by the setup";
                vReady = true; VError = ""; return new StringValue("");
            }
            catch (Exception ex) { vReady = false; VError = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + VError); }
        }

        struct V3 { public double X, Y, Z; }
        static V3 Vc(Structure v) { return new V3 { X = D(v.GetSuffix("X").Value), Y = D(v.GetSuffix("Y").Value), Z = D(v.GetSuffix("Z").Value) }; }
        static double Dot(V3 a, V3 b) { return a.X * b.X + a.Y * b.Y + a.Z * b.Z; }
        static double Mag(V3 a) { return Math.Sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z); }
        static double Sin(double x) { return Math.Sin(x * Math.PI / 180.0); }
        static double Cos(double x) { return Math.Cos(x * Math.PI / 180.0); }
        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static string KStr(double x) { return ScalarValue.Create(x).ToString(); }
        class Conic { public double e, p, ra, rp, argp, ta, n; public double cra = double.NaN, crp = double.NaN; public V3 px, qx, e1, e2; }   // cra / crp = the apsides the caption shows when the plan has an n-body measure (else ra / rp)
        static Conic Cn(Lexicon l)
        {
            var c = new Conic { e = D(G(l, "e")), p = D(G(l, "p")), ra = D(G(l, "ra")), rp = D(G(l, "rp")), argp = D(G(l, "argp")),
                ta = D(G(l, "ta")), n = D(G(l, "n")), px = Vc(G(l, "px")), qx = Vc(G(l, "qx")), e1 = Vc(G(l, "e1")), e2 = Vc(G(l, "e2")) };
            if (l.ContainsKey(new StringValue("cra")) && l.ContainsKey(new StringValue("crp"))) { c.cra = D(G(l, "cra")); c.crp = D(G(l, "crp")); }
            return c;
        }
        static V3 AtTA(Conic c, double nu)                // o2AtTA(el, nu)[0]
        {
            double rm = c.p / (1 + c.e * Cos(nu));
            double cn = Cos(nu), sn = Sin(nu);
            return new V3 { X = (c.px.X * cn + c.qx.X * sn) * rm, Y = (c.px.Y * cn + c.qx.Y * sn) * rm, Z = (c.px.Z * cn + c.qx.Z * sn) * rm };
        }
        double ViewR(double rm, double rb) { return rb + vAltx * (rm - rb); }
        double[] ViewXY(Conic fr, V3 r, double rb, double sc)
        {
            double rd = ViewR(Mag(r), rb) * sc / Mag(r);
            return new[] { Dot(r, fr.e1) * rd, -Dot(r, fr.e2) * rd };
        }
        double[] ViewTA(Conic c, double nu, double rb, double sc) { return ViewXY(c, AtTA(c, nu), rb, sc); }
        List<double[]> ViewPath(Conic c, double rb, double sc, int n, Conic fr)
        {
            var o = new List<double[]>();
            for (int i = 0; i < n; i++)
            {
                double nu = (double)(360 * i) / n;
                V3 rr = AtTA(c, nu);
                if (Mag(rr) > rb && c.p / (1 + c.e * Cos(nu)) > 0) o.Add(ViewXY(fr, rr, rb, sc));
            }
            return o;
        }
        static double MofTA(double e, double nu)
        {
            double ea = 2 * Atan2(Math.Sqrt(1 - e) * Sin(nu / 2), Math.Sqrt(1 + e) * Cos(nu / 2));
            double m = ea * Math.PI / 180 - e * Sin(ea);
            if (m < 0) m = m + 2 * Math.PI;
            return m;
        }
        static double TAofM(double e, double m)
        {
            double ea = m;
            if (e > 0.8) ea = Math.PI;
            for (int i = 0; i < 30; i++)
            {
                double f = ea - e * Sin(ea * 180 / Math.PI) - m;
                double d = f / (1 - e * Cos(ea * 180 / Math.PI));
                ea = ea - d;
                if (Math.Abs(d) < 1E-12) break;
            }
            double ed = ea * 180 / Math.PI;
            return (2 * Atan2(Math.Sqrt(1 + e) * Sin(ed / 2), Math.Sqrt(1 - e) * Cos(ed / 2)) + 720) % 360;
        }
        static double TAafter(Conic c, double nu0, double dt)
        {
            double m = MofTA(c.e, nu0) + c.n * dt;
            m = m - 2 * Math.PI * Math.Floor(m / (2 * Math.PI));
            return TAofM(c.e, m);
        }
        static string Fx(double x, int d)                 // lib_o2ui o2Fx
        {
            double m = Math.Pow(10, d);
            double a = Math.Round(Math.Abs(x) * m);
            double ip = Math.Floor(a / m);
            string s = KStr(ip);
            if (d > 0) s = s + "." + KStr(a - ip * m).PadLeft(d).Replace(" ", "0");
            if (x < 0 && a > 0) s = "-" + s;
            return s;
        }
        static string F(double x, int w, int d) { return Fx(x, d).PadLeft(w); }

        // ---- the slots
        int hi;
        static bool Eq(Structure a, string b) { return string.Equals(S(a), b, StringComparison.OrdinalIgnoreCase); }
        double[] WH(string nm)
        {
            var k = new StringValue(nm);
            if (sprWH.ContainsKey(k)) { var l = (ListValue)sprWH[k]; return new[] { D(l[0]), D(l[1]) }; }
            if (nm.StartsWith("earth_", StringComparison.OrdinalIgnoreCase))
            {
                double rp; string t = nm.Substring(6, nm.Length - 6);
                if (!double.TryParse(t, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out rp)) rp = 40;
                return new[] { 2 * rp + 4, 2 * rp + 4 };
            }
            if (nm == "ov_g") return new double[] { GLB_S, GLB_S };      // DEORB TGT's globe path
            if (nm.StartsWith("ov_", StringComparison.Ordinal)) return new double[] { ovS, ovS };
            return new[] { 2.0, 2.0 };
        }
        void Put(int k, string nm, double x, double y)
        {
            if (k >= spr.Count) return;
            var sl = (ListValue)spr[k];
            var wh = WH(nm);
            double xx = Math.Floor(x - wh[0] / 2 + 0.5);
            double yy = Math.Floor(y - wh[1] / 2 + 0.5);
            bool force = ovForce.Remove(nm);                 // a new image file under the same name
            if (!force && Eq(sl[1], nm) && D(sl[2]) == xx && D(sl[3]) == yy && B(sl[4])) return;
            var lb = sl[0];
            if (force || !Eq(sl[1], nm))
            {
                lb.SetSuffix("TEXT", new StringValue(""));
                if (nm.StartsWith("ov_", StringComparison.Ordinal)) SetOvImage(lb, nm);
                else lb.SetSuffix("IMAGE", new StringValue(dir + nm + ".png"));
                Sty(lb).SetSuffix("WIDTH", ScalarValue.Create(wh[0])); Sty(lb).SetSuffix("HEIGHT", ScalarValue.Create(wh[1]));
                sl[1] = new StringValue(nm);
            }
            Mrg(lb).SetSuffix("H", ScalarValue.Create(Math.Max(0, xx)));
            Mrg(lb).SetSuffix("V", ScalarValue.Create(Math.Max(0, yy - D(sl[5]))));
            sl[2] = ScalarValue.Create(xx); sl[3] = ScalarValue.Create(yy); sl[4] = BooleanValue.True;
            if (k >= hi) hi = k + 1;
        }
        void Txt(int k, string txt, double x, double y, string hex, double w)
        {
            if (k >= spr.Count) return;
            var sl = (ListValue)spr[k];
            string key = "@" + hex + txt;
            double xx = Math.Floor(x - w / 2 + 0.5);
            double yy = Math.Floor(y - 9 + 0.5);
            if (Eq(sl[1], key) && D(sl[2]) == xx && D(sl[3]) == yy && B(sl[4])) return;
            var lb = sl[0];
            if (!Eq(sl[1], key))
            {
                // a text key starts with "@" (no letter), as kOS's o2SprTxt: a slot that held an image ("tri" / "tick") blanks it
                if (!S(sl[1]).StartsWith("@", StringComparison.Ordinal)) lb.SetSuffix("IMAGE", new StringValue(dir + "blank.png"));
                Sty(lb).SetSuffix("RICHTEXT", BooleanValue.True);
                Sty(lb).SetSuffix("ALIGN", new StringValue("CENTER"));
                lb.SetSuffix("TEXT", new StringValue("<color=" + hex + ">" + txt + "</color>"));
                Sty(lb).SetSuffix("WIDTH", ScalarValue.Create(w)); Sty(lb).SetSuffix("HEIGHT", ScalarValue.Create(18));
                sl[1] = new StringValue(key);
            }
            Mrg(lb).SetSuffix("H", ScalarValue.Create(Math.Max(0, xx)));
            Mrg(lb).SetSuffix("V", ScalarValue.Create(Math.Max(0, yy - D(sl[5]))));
            sl[2] = ScalarValue.Create(xx); sl[3] = ScalarValue.Create(yy); sl[4] = BooleanValue.True;
            if (k >= hi) hi = k + 1;
        }
        void Off(int k)
        {
            var sl = (ListValue)spr[k];
            if (!B(sl[4])) return;
            var lb = sl[0];
            lb.SetSuffix("TEXT", new StringValue(""));
            lb.SetSuffix("IMAGE", new StringValue(dir + "blank.png"));
            Sty(lb).SetSuffix("WIDTH", ScalarValue.Create(2)); Sty(lb).SetSuffix("HEIGHT", ScalarValue.Create(2));
            Mrg(lb).SetSuffix("H", ScalarValue.Create(0)); Mrg(lb).SetSuffix("V", ScalarValue.Create(0));
            sl[1] = new StringValue(""); sl[4] = BooleanValue.False;
        }
        void From(int k)
        {
            int h = Math.Min(hi, spr.Count);
            for (int i = k; i < h; i++) if (B(((ListValue)spr[i])[4])) Off(i);
            if (k < hi) hi = Math.Max(k, 0);
        }
        static Structure Sty(Structure w) { return w.GetSuffix("STYLE").Value; }
        static Structure Mrg(Structure w) { return Sty(w).GetSuffix("MARGIN").Value; }

        // ==== the latch, the line images
        // The drawn radius (px) of conic c at the view angle th (deg from e1, as ViewXY's x / -y: x = R cos th, y = -R sin th)
        double VRad(Conic c, double th, double rb, double sc) { return ViewR(c.p / (1 + c.e * Cos(th - c.argp)), rb) * sc; }
        // how far (px) the live orbit b has moved the drawn orbit a (the latched one): the radius at every 15 deg of the view
        // angle (AN / DN are th 0 / 180) and, when A / P are drawn from this orbit, their points
        double Drift(Conic a, Conic b, double rb, double sc)
        {
            double m = 0;
            for (int i = 0; i < 24; i++)
            {
                double th = 15.0 * i;
                if (1 + a.e * Cos(th - a.argp) <= 1E-9 || 1 + b.e * Cos(th - b.argp) <= 1E-9) continue;
                m = Math.Max(m, Math.Abs(VRad(a, th, rb, sc) - VRad(b, th, rb, sc)));
            }
            return m;
        }
        // the A / P diamonds have a latch of their own (an argp that wanders on a near-circular orbit moves them and not the
        // line: no new image for that): how far b has moved a's apsides (1E9 when they appear / go)
        double ApDrift(Conic a, Conic b, double rb, double sc)
        {
            if ((a.e > 0.0005) != (b.e > 0.0005)) return 1E9;
            double m = 0;
            if (a.e > 0.0005)
                for (int k = 0; k < 2; k++)
                {
                    double ta = a.argp + 180 * k, tb = b.argp + 180 * k;
                    double ra = VRad(a, ta, rb, sc), rbb = VRad(b, tb, rb, sc);
                    double dx = ra * Cos(ta) - rbb * Cos(tb), dy = ra * Sin(ta) - rbb * Sin(tb);
                    m = Math.Max(m, Math.Sqrt(dx * dx + dy * dy));
                }
            return m;
        }
        // the planned path's move: the same 24 true anomalies, projected in the latched frame fr
        double PlDrift(Conic a, Conic b, Conic fr, double rb, double sc)
        {
            double m = 0;
            for (int i = 0; i < 24; i++)
            {
                double nu = 15.0 * i;
                if (1 + a.e * Cos(nu) <= 1E-9 || 1 + b.e * Cos(nu) <= 1E-9) continue;
                var pa = ViewXY(fr, AtTA(a, nu), rb, sc); var pb = ViewXY(fr, AtTA(b, nu), rb, sc);
                m = Math.Max(m, Math.Sqrt((pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1])));
            }
            return m;
        }
        static double Norm360(double x) { x = x % 360; return x < 0 ? x + 360 : x; }

        // ---- the line image: conic c seen in the frame of fr, anti-aliased (1.5 px wide), dashed or solid, straight-alpha RGBA
        const double HW = 0.75, DASH_ON = 7, DASH_OFF = 4;
        void Cover(float[] al, int S, double x0, double y0, double x1, double y1)
        {
            int i0 = Math.Max(0, (int)Math.Floor(Math.Min(x0, x1) - HW - 1)), i1 = Math.Min(S - 1, (int)Math.Ceiling(Math.Max(x0, x1) + HW + 1));
            int j0 = Math.Max(0, (int)Math.Floor(Math.Min(y0, y1) - HW - 1)), j1 = Math.Min(S - 1, (int)Math.Ceiling(Math.Max(y0, y1) + HW + 1));
            double dx = x1 - x0, dy = y1 - y0, l2 = dx * dx + dy * dy;
            for (int j = j0; j <= j1; j++)
                for (int i = i0; i <= i1; i++)
                {
                    double px = i + 0.5, py = j + 0.5;
                    double t = l2 > 0 ? ((px - x0) * dx + (py - y0) * dy) / l2 : 0;
                    t = t < 0 ? 0 : (t > 1 ? 1 : t);
                    double ex = px - (x0 + t * dx), ey = py - (y0 + t * dy);
                    double cov = HW + 0.5 - Math.Sqrt(ex * ex + ey * ey);
                    if (cov <= 0) continue;
                    if (cov > 1) cov = 1;
                    if (cov > al[j * S + i]) al[j * S + i] = (float)cov;
                }
        }
        void LineSeg(float[] al, int S, double x0, double y0, double x1, double y1, bool dash, ref double acc)
        {
            double dx = x1 - x0, dy = y1 - y0, len = Math.Sqrt(dx * dx + dy * dy);
            if (len < 1E-9) return;
            if (len > 4 * S) { acc += len; return; }
            if (!dash) { Cover(al, S, x0, y0, x1, y1); return; }
            double pos = 0;
            while (pos < len)
            {
                double ph = (acc + pos) % (DASH_ON + DASH_OFF);
                bool on = ph < DASH_ON;
                double step = Math.Min(len - pos, (on ? DASH_ON : DASH_ON + DASH_OFF) - ph);
                if (step < 1E-6) step = 1E-6;
                if (on) Cover(al, S, x0 + dx * pos / len, y0 + dy * pos / len, x0 + dx * (pos + step) / len, y0 + dy * (pos + step) / len);
                pos += step;
            }
            acc += len;
        }
        byte[] Raster(Conic c, Conic fr, double rb, double sc, bool dash, byte cr, byte cg, byte cb)
        {
            int S = ovS; double half = S / 2.0;
            var al = new float[S * S];
            bool have = false; double x0 = 0, y0 = 0, acc = 0;
            for (int i = 0; i <= 1440; i++)
            {
                double nu = i * 0.25;
                V3 rr = AtTA(c, nu);
                if (!(Mag(rr) > rb && c.p / (1 + c.e * Cos(nu)) > 0)) { have = false; continue; }
                var xy = ViewXY(fr, rr, rb, sc);
                double x1 = xy[0] + half, y1 = xy[1] + half;
                if (have) LineSeg(al, S, x0, y0, x1, y1, dash, ref acc);
                x0 = x1; y0 = y1; have = true;
            }
            var o = new byte[S * S * 4];
            for (int i = 0; i < S * S; i++) { o[4 * i] = cr; o[4 * i + 1] = cg; o[4 * i + 2] = cb; o[4 * i + 3] = (byte)(al[i] * 255 + 0.5f); }
            return o;
        }
        void WriteImg(string file, byte[] rgba)
        {
            int side = (int)Math.Round(Math.Sqrt(rgba.Length / 4.0));     // the orbit view's images are ovS square, the globe's GLB_S
            byte[] png = TjPng.EncodeRgba(rgba, side, side);
            string path = Path.Combine(ovDir, file), tmp = path + ".tmp";
            File.WriteAllBytes(tmp, png);
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
        // a NEW file for slot nm (never reused); the newest one a slot has not shown yet is replaced and deleted
        void NewImg(string nm, byte[] rgba)
        {
            string old; ovCur.TryGetValue(nm, out old);
            string file = "o2" + nm + "_" + (++ovSeqS) + ".png";
            WriteImg(file, rgba);
            ovCur[nm] = ovRel + file;
            string shown; ovShown.TryGetValue(nm, out shown);
            if (old != null && old != shown) DropImg(old);     // written, never shown: just a file
        }
        // a replaced image: its texture out of kOS's cache (the entry too, or the cache only grows) and destroyed, the file deleted.
        // kOS keys the cache by the path string the script gave (rel, as SetOvImage passes it), not the full path: the
        // lookup by the full path never matched, so every replaced image's texture lived on for the rest of the KSP session.
        // Both keys are tried (the full one for a kOS that would key by it).
        void DropImg(string rel)
        {
            string full = null;
            try { full = Path.GetFullPath(Path.Combine(SafeHouse.ArchiveFolder, rel)); } catch (Exception) { }
            try
            {
                var d = TexDict();
                if (d != null)
                    foreach (string key in new[] { rel, full })
                    {
                        if (key == null || !d.Contains(key)) continue;
                        var t = CachedTex(key);
                        d.Remove(key);
                        if (t != null) { UnityEngine.Object.Destroy(t); TexDropped++; }
                    }
            }
            catch (Exception) { }
            try { if (full != null && File.Exists(full)) File.Delete(full); } catch (Exception) { }
        }
        public static int TexDropped;                      // textures destroyed so far (PerfWatch logs it)
        // every image this view holds (shown or only written) dropped, before a setup forgets them
        void DropAllImg()
        {
            var seen = new HashSet<string>();
            foreach (var v in ovShown.Values) if (v != null && seen.Add(v)) DropImg(v);
            foreach (var v in ovCur.Values) if (v != null && seen.Add(v)) DropImg(v);
        }
        void Relatch(Conic el, Conic pl, bool hasPl, double rb, double sc, int re, double now)
        {
            latEl = el; latPl = pl; latHas = hasPl; latRe = re; latSc = sc; latT = now;
            if (!lineOn) return;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                NewImg("ov_o", Raster(el, el, rb, sc, false, 60, 224, 60));                      // the sprites' dot_g / dot_y colours
                if (hasPl) NewImg("ov_p", Raster(pl, el, rb, sc, true, 240, 216, 64));
                ovForce.Add("ov_o"); if (hasPl) ovForce.Add("ov_p");
                LN++;
            }
            catch (Exception ex) { lineOn = false; ovForce.Clear(); LError = ex.GetType().Name + ": " + ex.Message; }
            lms += sw.Elapsed.TotalMilliseconds;
        }
        public string LMs() { return LN == 0 ? "-" : (lms / LN).ToString("F3") + " ms/relatch over " + LN; }

        // kOS caches a loaded image by the path string it was given (Widget.textureCache, static: never emptied) and keeps it for
        // ever: a replaced image's texture is read out of that cache (reflection), the entry removed and the texture destroyed
        // (a failure only leaks)
        System.Collections.IDictionary TexDict()
        {
            if (texCacheF == null)
            {
                Type wt = null;
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) { wt = asm.GetType("kOS.Suffixed.Widget.Widget", false); if (wt != null) break; }
                if (wt == null) return null;
                texCacheF = wt.GetField("textureCache", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public);
                if (texCacheF == null) return null;
            }
            return texCacheF.GetValue(null) as System.Collections.IDictionary;
        }
        UnityEngine.Texture2D CachedTex(string full)
        {
            var d = TexDict();
            if (d == null || !d.Contains(full)) return null;
            object e = d[full];
            if (texF == null) texF = e.GetType().GetField("texture", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public);
            return texF == null ? null : texF.GetValue(e) as UnityEngine.Texture2D;
        }
        void SetOvImage(Structure lb, string nm)
        {
            string rel; if (!ovCur.TryGetValue(nm, out rel)) throw new Exception("no image for " + nm);
            string old; ovShown.TryGetValue(nm, out old);
            lb.SetSuffix("IMAGE", new StringValue(rel));
            ovShown[nm] = rel;
            if (old != null && old != rel) DropImg(old);       // the label has the new one: the old texture and file go
        }

        // O2VIEW(el, pl, st): st = LEXICON(rb, dt (the TIG / burn UT - now; <= 0 none), hi (o2SprHi), t (optional: the clock, s), bg (optional: s the orbiter bug is past el's anomaly))
        // -> the new o2SprHi, or -1 (VError says why; kOS then draws the view itself and takes every slot as possibly on).
        public ScalarValue View(Lexicon elL, Lexicon plL, Lexicon st)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (!vReady) throw new Exception("O2VSETUP not done");
                Conic el = Cn(elL);
                bool hasPl = plL.Count > 0;
                Conic pl = hasPl ? Cn(plL) : null;
                double rb = D(G(st, "rb")), dt = D(G(st, "dt"));
                hi = (int)D(G(st, "hi"));
                double now = st.ContainsKey(new StringValue("t")) ? D(G(st, "t")) : Environment.TickCount / 1000.0;
                // the scale, the Earth (o2qView's cache block, every call here)
                double big = rb;
                big = Math.Max(big, ViewR(Math.Min(el.ra, rb * 3), rb));
                if (hasPl) big = Math.Max(big, ViewR(Math.Min(pl.ra, rb * 3), rb));
                double sc = vR / big;
                double reD = Math.Round(Math.Min(vEpx, rb * sc));
                int re = (int)reD;
                sc = reD / rb;
                // everything below is drawn from the latched orbit (L, P, lsc, lre), not the live one
                bool force = latEl == null || hasPl != latHas || re != latRe;
                if (!force)
                {
                    bool drift = Drift(latEl, el, rb, sc) > O2V_TOL || (hasPl && PlDrift(latPl, pl, latEl, rb, sc) > O2V_TOL);
                    force = drift && (now - latT >= O2V_MINDT || now < latT);
                }
                if (force) { Relatch(el, pl, hasPl, rb, sc, re, now); latAp = el; latApT = now; }
                else if (!hasPl && (ApDrift(latAp, el, rb, sc) > O2V_TOL && (now - latApT >= O2V_MINDT || now < latApT))) { latAp = el; latApT = now; }
                Conic L = latEl, P = latPl; bool hp = latHas;
                double lsc = latSc; int lre = latRe;
                double cx = vCx, cy = vCy;
                int k = 0;
                Put(k, "earth_" + KStr(Math.Max(30, Math.Min(80, lre))), cx, cy); k++;
                if (lineOn)
                {
                    Put(k, "ov_o", cx, cy); k++;
                    if (hp) { Put(k, "ov_p", cx, cy); k++; }
                }
                else
                {
                    ovForce.Clear();
                    var pP = ViewPath(L, rb, lsc, vN, L);
                    foreach (var p in pP) { Put(k, "dot_g", cx + p[0], cy + p[1]); k++; }
                    if (hp)
                    {
                        int i = 0;
                        foreach (var p in ViewPath(P, rb, lsc, vN, L)) { if (i % 3 != 2) { Put(k, "dot_y", cx + p[0], cy + p[1]); k++; } i++; }
                    }
                }
                Conic mk = hp ? P : latAp;
                if (mk.e > 0.0005)
                {
                    var pa = ViewXY(L, AtTA(mk, 180), rb, lsc);
                    var pp = ViewXY(L, AtTA(mk, 0), rb, lsc);
                    Put(k, "dia", cx + pa[0], cy + pa[1]); k++;
                    Put(k, "dia", cx + pp[0], cy + pp[1]); k++;
                    Txt(k, "A", cx + pa[0] * 1.13, cy + pa[1] * 1.13, "#c4ffc4", 30); k++;
                    Txt(k, "P", cx + pp[0] * 1.13, cy + pp[1] * 1.13, "#c4ffc4", 30); k++;
                }
                var pn = ViewTA(L, Norm360(360 - L.argp), rb, lsc);
                var pd = ViewTA(L, Norm360(540 - L.argp), rb, lsc);
                Put(k, "node", cx + pn[0], cy + pn[1]); k++;
                Put(k, "node", cx + pd[0], cy + pd[1]); k++;
                Txt(k, "AN", cx + pn[0] - 18, cy + pn[1], "#c4ffc4", 30); k++;
                Txt(k, "DN", cx + pd[0] + 18, cy + pd[1], "#c4ffc4", 30); k++;
                if (dt > 0)
                {   // the live true anomaly's place on the latched line: the same angle from the node line, not from the live periapsis
                    var pt = ViewTA(L, Norm360(el.argp + TAafter(el, el.ta, dt) - L.argp), rb, lsc);
                    Put(k, "tick", cx + pt[0], cy + pt[1]); k++;
                    Txt(k, "TIG", cx + pt[0] * 1.18, cy + pt[1] * 1.18, "#c4ffc4", 40); k++;
                }
                double bg = st.ContainsKey(new StringValue("bg")) ? D(G(st, "bg")) : 0;   // the bug's offset (s): FPLN STATE's burn end
                var po = ViewTA(L, Norm360(el.argp + (bg > 0 && el.n > 0 ? TAafter(el, el.ta, bg) : el.ta) - L.argp), rb, lsc);
                Put(k, "tri", cx + po[0], cy + po[1]); k++;
                string cap = "A <color=#a6f8a6>" + F((el.ra - rb) / 1000, 5, 1) + "</color>   P <color=#a6f8a6>"
                    + F((el.rp - rb) / 1000, 5, 1) + "</color> km";
                if (hasPl)
                {
                    cap = "NOW  " + cap;
                    double plA = double.IsNaN(pl.cra) ? pl.ra : pl.cra, plP = double.IsNaN(pl.crp) ? pl.rp : pl.crp;   // One measure with BRN PLN's AFTER line
                    Txt(k, "<color=#f0d840>PLAN</color> A <color=#a6f8a6>" + F((plA - rb) / 1000, 5, 1)
                        + "</color>  P <color=#a6f8a6>" + F((plP - rb) / 1000, 5, 1) + "</color> km", cx, CapY(cy, vR, 1), "#3ce03c", 270);
                    k++;
                }
                Txt(k, cap, cx, CapY(cy, vR, 0), "#3ce03c", 270); k++;
                From(k);
                if (!lineOn || !hp) { string pS; if (ovShown.TryGetValue("ov_p", out pS)) { ovShown.Remove("ov_p"); ovCur.Remove("ov_p"); DropImg(pS); } }
                vms += sw.Elapsed.TotalMilliseconds; vmsN++; VNn++;
                return ScalarValue.Create(hi);
            }
            catch (Exception ex) { VError = ex.GetType().Name + ": " + ex.Message; return ScalarValue.Create(-1); }
        }
        // the apsides caption's lines sit under the view's lowest sprite (lib_o2orb.ks o2ViewReachY / o2ViewCapY, the same arithmetic):
        // the TIG label at 1.18 r in an 18 px box reaches cy + 1.18 r + 9; the first line's centre 15 px under that, the next 16 px under it
        static double CapY(double cy, double r, int ln) { return Math.Floor(cy + r * 1.18 + 9) + 15 + 16 * ln; }
        public string VMs() { return vmsN == 0 ? "-" : (vms / vmsN).ToString("F4") + " ms/call over " + vmsN; }

        // ==== DEORB TGT's globe (ops2q.ks o2qGlbCs, lib_o2dorb.ks o2dbItems / o2dbGeom). The ground track is ONE anti-aliased
        // image in the slot "ov_g" (2.6 px wide: the part before the interface #a6f8a6, after it #c4ffc4), written under a NEW
        // file name on a change only; the background, EI's X + label, periapsis's ring + label and the site are o2dbItems'
        // sprites and texts, put and written as o2SprPut / o2SprTxt do. Without this suffix (an older DLL) or on an error kOS draws
        // the globe itself, the path as dots (lib_o2dorb.ks o2dbGfx).
        bool gReady; string glbKey = ""; public string GError = ""; public int GN = 0; double gms = 0; int gmsN = 0;
        const int GLB_S = 2 * 158 + 16;
        const double GLB_HW = 1.3;
        public StringValue GSetup(Lexicon a)
        {
            try
            {
                spr = (ListValue)G(a, "spr"); sprWH = (Lexicon)G(a, "wh"); dir = S(G(a, "dir"));
                if (a.ContainsKey(new StringValue("ldir"))) ovRel = S(G(a, "ldir"));
                if (ovDir == "")
                {
                    ovDir = Path.Combine(SafeHouse.ArchiveFolder, ovRel); Directory.CreateDirectory(ovDir);
                    foreach (var f in Directory.GetFiles(ovDir, "o2ov_g_*.png*")) { try { File.Delete(f); } catch (Exception) { } }   // the last run's
                }
                {                                              // the last globe image (shown or only written) dropped first
                    string gS, gC; ovShown.TryGetValue("ov_g", out gS); ovCur.TryGetValue("ov_g", out gC);
                    if (gS != null) DropImg(gS);
                    if (gC != null && gC != gS) DropImg(gC);
                }
                glbKey = ""; ovCur.Remove("ov_g"); ovShown.Remove("ov_g");
                gReady = true; GError = ""; return new StringValue("");
            }
            catch (Exception ex) { gReady = false; GError = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + GError); }
        }
        void GCover(float[] al, int S, double x0, double y0, double x1, double y1)     // Cover with the globe's width
        {
            int i0 = Math.Max(0, (int)Math.Floor(Math.Min(x0, x1) - GLB_HW - 1)), i1 = Math.Min(S - 1, (int)Math.Ceiling(Math.Max(x0, x1) + GLB_HW + 1));
            int j0 = Math.Max(0, (int)Math.Floor(Math.Min(y0, y1) - GLB_HW - 1)), j1 = Math.Min(S - 1, (int)Math.Ceiling(Math.Max(y0, y1) + GLB_HW + 1));
            double dx = x1 - x0, dy = y1 - y0, l2 = dx * dx + dy * dy;
            for (int j = j0; j <= j1; j++)
                for (int i = i0; i <= i1; i++)
                {
                    double px = i + 0.5, py = j + 0.5;
                    double t = l2 > 0 ? ((px - x0) * dx + (py - y0) * dy) / l2 : 0;
                    t = t < 0 ? 0 : (t > 1 ? 1 : t);
                    double ex = px - (x0 + t * dx), ey = py - (y0 + t * dy);
                    double cov = GLB_HW + 0.5 - Math.Sqrt(ex * ex + ey * ey);
                    if (cov <= 0) continue;
                    if (cov > 1) cov = 1;
                    if (cov > al[j * S + i]) al[j * S + i] = (float)cov;
                }
        }
        // pts = LIST(LIST(dx, dy, seg)) (px from the globe's centre, seg 0 before the interface, 1 after): the polyline, two colours
        byte[] GRaster(ListValue pts)
        {
            int S = GLB_S; double half = S / 2.0;
            var a1 = new float[S * S]; var a2 = new float[S * S];
            double x0 = 0, y0 = 0; bool have = false;
            for (int i = 0; i < pts.Count; i++)
            {
                var p = (ListValue)pts[i];
                double x1 = D(p[0]) + half, y1 = D(p[1]) + half; int sg = (int)D(p[2]);
                if (have) GCover(sg == 0 ? a1 : a2, S, x0, y0, x1, y1);
                x0 = x1; y0 = y1; have = true;
            }
            var o = new byte[S * S * 4];
            for (int i = 0; i < S * S; i++)
            {
                float c1 = a1[i], c2 = a2[i], al = Math.Max(c1, c2);
                if (al <= 0) continue;
                if (c2 >= c1) { o[4 * i] = 0xc4; o[4 * i + 1] = 0xff; o[4 * i + 2] = 0xc4; } else { o[4 * i] = 0xa6; o[4 * i + 1] = 0xf8; o[4 * i + 2] = 0xa6; }
                o[4 * i + 3] = (byte)(al * 255 + 0.5f);
            }
            return o;
        }
        // O2GLB(items, pts, LEXICON(hi, cx, cy)): items = o2dbItems without the dots (the first is the background), pts = the path
        // (empty when not solved) -> the new o2SprHi, or -1 (GError says why; kOS then draws the globe itself and takes every slot as on).
        public ScalarValue Glb(ListValue items, ListValue pts, Lexicon st)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (!gReady) throw new Exception("O2GSETUP not done");
                hi = (int)D(G(st, "hi"));
                double cx = D(G(st, "cx")), cy = D(G(st, "cy"));
                bool path = pts.Count > 1;
                if (path)
                {
                    double sum = 0;
                    for (int i = 0; i < pts.Count; i++) { var p = (ListValue)pts[i]; sum = sum * 1.000003 + D(p[0]) * 3 + D(p[1]) * 7 + D(p[2]) * 11; }
                    string key = pts.Count + "/" + sum.ToString("R", System.Globalization.CultureInfo.InvariantCulture);
                    if (key != glbKey || !ovCur.ContainsKey("ov_g"))
                    {
                        NewImg("ov_g", GRaster(pts)); ovForce.Add("ov_g"); glbKey = key; GN++;
                    }
                }
                int k = 0; bool bg = false;
                for (int ii = 0; ii < items.Count; ii++)
                {
                    var it = (ListValue)items[ii];
                    if (S(it[0]) == "s") Put(k, S(it[1]), D(it[2]), D(it[3]));
                    else Txt(k, S(it[1]), D(it[2]), D(it[3]), S(it[4]), D(it[5]));
                    k++;
                    if (!bg) { bg = true; if (path) { Put(k, "ov_g", cx, cy); k++; } }      // the path over the background, under the markers
                }
                From(k);
                if (!path)
                {
                    string pS; if (ovShown.TryGetValue("ov_g", out pS)) { ovShown.Remove("ov_g"); ovCur.Remove("ov_g"); DropImg(pS); }
                    glbKey = ""; ovForce.Remove("ov_g");
                }
                gms += sw.Elapsed.TotalMilliseconds; gmsN++;
                return ScalarValue.Create(hi);
            }
            catch (Exception ex) { GError = ex.GetType().Name + ": " + ex.Message; return ScalarValue.Create(-1); }
        }
        public string GMs() { return gmsN == 0 ? "-" : (gms / gmsN).ToString("F4") + " ms/call over " + gmsN + ", " + GN + " images"; }
    }

    public static class OdReg
    {
        public static OdHost Register(Action<string, ISuffix> add)
        {
            var h = new OdHost();
            add("O2SETUP", new OneArgsSuffix<StringValue, Lexicon>(a => h.Setup(a)));
            add("O2DRAW", new TwoArgsSuffix<StringValue, Lexicon, Lexicon>((a, b) => h.Draw(a, b)));
            add("O2ERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("O2N", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("O2MS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            add("O2VSETUP", new OneArgsSuffix<StringValue, Lexicon>(a => h.VSetup(a)));
            add("O2VIEW", new ThreeArgsSuffix<ScalarValue, Lexicon, Lexicon, Lexicon>((a, b, c) => h.View(a, b, c)));
            add("O2VERROR", new Suffix<StringValue>(() => new StringValue(h.VError)));
            add("O2VN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.VNn)));
            add("O2VMS", new Suffix<StringValue>(() => new StringValue(h.VMs())));
            add("O2VLN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.LN)));
            add("O2VLMS", new Suffix<StringValue>(() => new StringValue(h.LMs())));
            add("O2VLERROR", new Suffix<StringValue>(() => new StringValue(h.LError)));
            add("O2GSETUP", new OneArgsSuffix<StringValue, Lexicon>(a => h.GSetup(a)));        // DEORB TGT's globe (ops2q.ks o2qGlbCs)
            add("O2GLB", new ThreeArgsSuffix<ScalarValue, ListValue, ListValue, Lexicon>((a, b, c) => h.Glb(a, b, c)));
            add("O2GERROR", new Suffix<StringValue>(() => new StringValue(h.GError)));
            add("O2GMS", new Suffix<StringValue>(() => new StringValue(h.GMs())));
            var mh = new O2MnvrHost();                                                          // The MNVR page build (O2Mnvr.cs; ops2q.ks o2qMnvrBuild: kOS builds when it is missing / fails)
            add("O2MNVR", new OneArgsSuffix<Structure, Lexicon>(a => mh.Build(a)));
            add("O2MNVRERROR", new Suffix<StringValue>(() => new StringValue(mh.Error)));
            add("O2MNVRN", new Suffix<ScalarValue>(() => ScalarValue.Create(mh.N)));
            add("O2MNVRMS", new Suffix<StringValue>(() => new StringValue(mh.Ms())));
            var oh = new O2OrbitHost();                                                         // page 2: the ORBIT / PTG page build (O2Orbit.cs; ops2q.ks o2qOrbitBuild: kOS builds when it is missing / fails)
            add("O2ORBIT", new OneArgsSuffix<Structure, Lexicon>(a => oh.Build(a)));
            add("O2ORBITERROR", new Suffix<StringValue>(() => new StringValue(oh.Error)));
            add("O2ORBITN", new Suffix<ScalarValue>(() => ScalarValue.Create(oh.N)));
            add("O2ORBITMS", new Suffix<StringValue>(() => new StringValue(oh.Ms())));
            add("O2CUT", new Suffix<StringValue>(() => new StringValue("T563")));   // this DLL draws the grid with CUT OFF as cell 15 (lib_o2disp o2CsOk: kOS draws when it is missing)
            add("O2PDRS", new Suffix<StringValue>(() => new StringValue("T602")));   // this DLL draws the split pad (EE CAM + STOP) of the PDRS page (lib_o2disp o2CsOk: kOS draws it when this is missing)
            add("O2DD", new Suffix<StringValue>(() => new StringValue("T550")));   // this DLL draws the drop-down list (ops2q.ks o2qDraw: kOS draws an open list when it is missing)
            return h;
        }
    }
}
