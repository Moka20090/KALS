// THE ENTRY PAGE'S C# TWIN, so the whole page can run at 10 Hz: lib_entdisp.ks's
// per-draw math (the entry page, HORIZ SIT in entry: edTick's body, edTickK) in C#, line for line with kOS's semantics
// (Td.cs's Tdm: trig in degrees, ROUND = Math.Round, MOD = %, numbers to text by kOS.Safe's own ScalarValue ToString,
// string '=' case-insensitive).
// THE STATE STAYS KOS'S: every slot's bookkeeping (sl[2..12]) and the globals edRgKey / edDbA are read from kOS at each call
// and written back (TdEnv) only after the whole call succeeded, so kOS's own code can take over at any draw.
// THE WIDGETS STAY KOS'S: every widget write the kOS code would make comes back as an op (widget, code, value), in the kOS
// code's order (codes 0 TEXT, 1 IMAGE, 2 WIDTH, 3 HEIGHT, 4 MARGIN:H, 5 MARGIN:V, 6 ALIGN).
// THE GAME READS STAY KOS'S (lib_entdisp's edCsIn: TIME, the position, the track, the attitude angles, the rates, the
// drag / lift, the guidance's bank / alpha, the DAP's rate command, the flash phase, the HAC, the runway); the great
// circles (lib_land's ldGreatCircle) and the predictor's family lookups (edFamPrep / edFamD on EPR_FAM) are ported here.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class EdCalc
    {
        public const int OP_TEXT = 0, OP_IMAGE = 1, OP_WIDTH = 2, OP_HEIGHT = 3, OP_MH = 4, OP_MV = 5, OP_ALIGN = 6;
        public TdEnv E;
        public List<Structure> Ops = new List<Structure>();
        static readonly double R2D = 180.0 / Math.PI;

        double ED_IMG_DY, ED_TXT_DY, ED_VT, ED_PRED_STEPS, ED_ALT_N, TG_D2R;
        double ED_FIT_IN;
        double ED_LB_CW, ED_MERGE_PX, ED_MERGE_N, ED_RG_DA, ED_RG_TRY;     // the map's label placer
        ListValue ED_LB_RW, ED_LB_AL;
        double[] lbDb = { 0, 0, 0 };                                       // the DB lines (kOS's edLbDb)
        readonly List<double[]> lbOb = new List<double[]>();             // the boxes taken this draw (kOS's edLbOb)
        double ED_LB_HYS;
        double ED_PRED_AOA_MIN, ED_PRED_TURN;                              // the predictor's alpha floor, turn cap
        ListValue edPr;                                                    // kOS's edPrTab (edPrBuild)
        Lexicon lbOld = new Lexicon(), lbNw = new Lexicon();               // kOS's edLbOld / edLbNw
        Lexicon edGeo, edSpr, edS, edTmB;
        ListValue edRgB, edRg, edAl;
        Structure edBlank;
        double bodyR;

        public EdCalc(TdEnv e) { E = e; }

        double GD(string n) { return Tdm.D(E.Raw(n)); }
        static Lexicon Lx(Structure s) { var l = s as Lexicon; if (l == null) throw new Exception("not a LEXICON"); return l; }
        static ListValue Ls(Structure s) { var l = s as ListValue; if (l == null) throw new Exception("not a LIST"); return l; }
        static Structure K(Lexicon x, string k)
        {
            var key = new StringValue(k);
            if (!x.ContainsKey(key)) throw new Exception("no key " + k);
            return x[key];
        }
        static bool Has(Lexicon x, string k) { return x.ContainsKey(new StringValue(k)); }
        double[] Geo(string k)
        {
            var l = Ls(K(edGeo, k));
            var r = new double[l.Count]; for (int i = 0; i < l.Count; i++) r[i] = Tdm.D(l[i]); return r;
        }
        ListValue S(string n) { return Ls(K(edS, n)); }
        static double Tan(double x) { return Math.Tan(x * Math.PI / 180.0); }
        static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        static StringValue Str(string s) { return new StringValue(s); }

        public void Load()
        {
            ED_IMG_DY = GD("ED_IMG_DY"); ED_TXT_DY = GD("ED_TXT_DY"); ED_VT = GD("ED_VT"); ED_PRED_STEPS = GD("ED_PRED_STEPS");
            ED_ALT_N = GD("ED_ALT_N"); TG_D2R = GD("TG_D2R");
            ED_LB_HYS = GD("ED_LB_HYS");
            ED_PRED_AOA_MIN = GD("ED_PRED_AOA_MIN"); ED_PRED_TURN = GD("ED_PRED_TURN");
            edPr = Ls(E.Raw("edPrTab"));
            ED_FIT_IN = GD("ED_FIT_IN");
            ED_LB_CW = GD("ED_LB_CW"); ED_MERGE_PX = GD("ED_MERGE_PX"); ED_MERGE_N = GD("ED_MERGE_N");
            ED_RG_DA = GD("ED_RG_DA"); ED_RG_TRY = GD("ED_RG_TRY");
            ED_LB_RW = Ls(E.Raw("ED_LB_RW")); ED_LB_AL = Ls(E.Raw("ED_LB_AL"));
            edGeo = Lx(E.Raw("edGeo")); edSpr = Lx(E.Raw("edSpr")); edS = Lx(E.Raw("edS")); edTmB = Lx(E.Raw("edTmB"));
            edRgB = Ls(E.Raw("edRgB")); edRg = Ls(E.Raw("edRg")); edAl = Ls(E.Raw("edAl"));
            edBlank = E.Raw("edBlank");
        }

        // EDSETUP: everything a draw reads is there (a missing name throws here, once, and kOS keeps drawing)
        public void Setup()
        {
            Load();
            foreach (var k in new[] { "field", "veh", "ahead", "zoom_in", "ring_n", "ring_f", "taem", "db", "pred", "met", "trk",
                "zoomlab", "lval", "adi", "bar_rp", "bar_rq", "bar_rr", "bar_eb", "bar_ea", "bar_ey" }) Geo(k);
            foreach (var k in new[] { "bug", "pred", "alt", "hacx", "tri", "arr", "triv", "arrv" })   // triv, arrv
                if (!Has(edSpr, k)) throw new Exception("no sprite " + k);
            foreach (var k in new[] { "rwy", "hac", "db0", "db1", "p1", "bug", "met", "trk", "aR", "gY", "l0", "l5", "lr1", "lr2",
                "ltm", "ldb", "lrw", "zm", "trp", "crp", "teb", "tea", "tey" }) S(k);
            if (edRg.Count != 3 || edRgB.Count != 2) throw new Exception("the rings' slots");
            E.Raw("edRgKey"); Ls(E.Raw("edDbA")); Ls(E.Raw("edNear"));
            Lx(E.Raw("edLbMem")); E.Raw("edLbZm");
            if (edPr.Count != 0 && edPr.Count != 9) throw new Exception("edPrTab");
        }

        void Op(Structure w, int code, Structure v) { Ops.Add(w); Ops.Add(ScalarValue.Create(code)); Ops.Add(v); }

        // ---- the slots (edSlot's 15 fields: widget, flow px, content, x, y, ON, align, width, font size, own px lower,
        //      the last call's x, y, align, full width, kind "T" / "I")
        void Off(ListValue sl)
        {
            if (Tdm.B(E.L(sl, 5)))
            {
                if (Tdm.SEq(Tdm.T(E.L(sl, 14)), "T")) Op(sl[0], OP_TEXT, Str("")); else Op(sl[0], OP_IMAGE, edBlank);
                E.LS(sl, 2, Str(""));
                E.LS(sl, 5, BooleanValue.False);
            }
        }
        void Put(ListValue sl, string nm, double x, double y)
        {
            if (Tdm.SEq(nm, Tdm.T(E.L(sl, 2))) && x == Tdm.D(E.L(sl, 10)) && y == Tdm.D(E.L(sl, 11))) return;
            if (!Has(edSpr, nm)) { Off(sl); return; }
            var sp = Ls(K(edSpr, nm));
            if (!Tdm.SEq(Tdm.T(E.L(sl, 2)), nm))
            {
                Op(sl[0], OP_IMAGE, sp[0]);
                Op(sl[0], OP_WIDTH, sp[1]);
                Op(sl[0], OP_HEIGHT, sp[2]);
                E.LS(sl, 2, Str(nm));
            }
            double xx = Math.Floor(x - Tdm.D(sp[3]) + 0.5);
            double yy = Math.Floor(y - Tdm.D(sp[4]) + 0.5);
            if (xx != Tdm.D(E.L(sl, 3)) || yy != Tdm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Tdm.N(Math.Max(0, xx)));
                Op(sl[0], OP_MV, Tdm.N(Math.Max(0, Math.Floor(yy - ED_IMG_DY - Tdm.D(E.L(sl, 1)) + 0.5))));
                E.LS(sl, 3, Tdm.N(xx)); E.LS(sl, 4, Tdm.N(yy));
            }
            E.LS(sl, 10, Tdm.N(x)); E.LS(sl, 11, Tdm.N(y));
            E.LS(sl, 5, BooleanValue.True);
        }
        bool PutIn(ListValue sl, string nm, double x, double y)
        {
            var sp = Ls(K(edSpr, nm));
            var f = Geo("field");
            double w = Tdm.D(sp[1]), h = Tdm.D(sp[2]), ax = Tdm.D(sp[3]), ay = Tdm.D(sp[4]);
            if (x - ax < ED_FIT_IN || x - ax + w > f[2] - ED_FIT_IN || y - ay < ED_FIT_IN || y - ay + h > f[2] - ED_FIT_IN)
            { Off(sl); return false; }
            Put(sl, nm, f[0] + x, f[1] + y);
            return true;
        }
        // lib_entdisp's edLbBox / edLbOne / edLbPut (the map's label placer)
        double[] LbBox(string s, double fz, double x, double y, double al)
        {
            double w = s.Length * ED_LB_CW * fz;
            double x0 = x - 1;
            if (al == 1) x0 = x - w - 1; else if (al == 2) x0 = x - w / 2 - 1;
            return new[] { x0, x0 + w + 2, y - 0.6 * fz - 1, y + 0.5 * fz + 1 };
        }
        bool LbOne(ListValue sl, string s, double x, double y, double al, double[] f)
        {
            var b = LbBox(s, Tdm.D(E.L(sl, 8)), x, y, al);
            if (b[0] < 2 || b[1] > f[2] - 2 || b[2] < 2 || b[3] > f[2] - 2) return false;
            var bf = b;                             // holding its spot, tested ED_LB_HYS smaller
            if (lbHold) b = new[] { b[0] + ED_LB_HYS, b[1] - ED_LB_HYS, b[2] + ED_LB_HYS, b[3] - ED_LB_HYS };
            if (b[2] < lbDb[1])
            {
                double ya = (lbDb[1] - b[2]) * lbDb[2];
                double yb = Math.Max(0, lbDb[1] - b[3]) * lbDb[2];
                if (lbDb[0] + yb < b[1] + 1.5 && lbDb[0] + ya > b[0] - 1.5) return false;
                if (lbDb[0] - ya < b[1] + 1.5 && lbDb[0] - yb > b[0] - 1.5) return false;
            }
            foreach (var o in lbOb)
                if ((o.Length < 5 || !lbHold) && b[0] < o[1] && b[1] > o[0] && b[2] < o[3] && b[3] > o[2]) return false;
            lbOb.Add(bf);
            Text(sl, s, f[0] + x, f[1] + y, al);
            return true;
        }
        // the labels asked for this draw (kOS's edLbRq): slot, text, spots (x, y, align, id), key
        readonly List<ListValue> rqSl = new List<ListValue>(); readonly List<string> rqS = new List<string>();
        readonly List<List<double[]>> rqC = new List<List<double[]>>(); readonly List<string> rqK = new List<string>();
        bool lbHold;                                                       // kOS's edLbHold
        void LbPut(ListValue sl, string s, double x, double y, ListValue cs, string ky)
        {
            var ab = new List<double[]>();
            for (int i = 0; i < cs.Count; i++)
            {
                var c = Ls(cs[i]);
                ab.Add(new[] { x + Tdm.D(c[0]), y + Tdm.D(c[1]), Tdm.D(c[2]), i });
            }
            LbAdd(sl, s, ab, ky);
        }
        void LbAdd(ListValue sl, string s, List<double[]> cs, string ky) { rqSl.Add(sl); rqS.Add(s); rqC.Add(cs); rqK.Add(ky); }
        // each at its last draw's spot if still clear (the soft boxes not counted), then the rest at the first
        // clear of their spots in their order; none: off
        void LbRun(double[] f)
        {
            var dn = new List<bool>();
            lbHold = true;
            for (int i = 0; i < rqSl.Count; i++)
            {
                bool ok = false;
                var k = Str(rqK[i]);
                if (lbOld.ContainsKey(k))
                {
                    double m = Tdm.D(lbOld[k]);
                    foreach (var c in rqC[i]) if (!ok && c[3] == m) ok = LbOne(rqSl[i], rqS[i], c[0], c[1], c[2], f);
                    if (ok) lbNw[k] = ScalarValue.Create((int)m);
                }
                dn.Add(ok);
            }
            lbHold = false;
            for (int i = 0; i < rqSl.Count; i++)
            {
                if (dn[i]) continue;
                bool ok = false;
                foreach (var c in rqC[i])
                    if (!ok && LbOne(rqSl[i], rqS[i], c[0], c[1], c[2], f)) { ok = true; lbNw[Str(rqK[i])] = ScalarValue.Create((int)c[3]); }
                if (!ok) Off(rqSl[i]);
            }
        }
        void Text(ListValue sl, string s, double x, double y, double align)
        {
            if (Tdm.SEq(s, "")) { Off(sl); return; }
            if (Tdm.SEq(s, Tdm.T(E.L(sl, 2))) && x == Tdm.D(E.L(sl, 10)) && y == Tdm.D(E.L(sl, 11)) && align == Tdm.D(E.L(sl, 12))) return;
            if (!Tdm.SEq(Tdm.T(E.L(sl, 2)), s)) { Op(sl[0], OP_TEXT, Str(s)); E.LS(sl, 2, Str(s)); }
            double fw = Tdm.D(E.L(sl, 13));
            double w = fw;
            double xx = Math.Floor(x + 0.5);
            string al = "LEFT";
            if (align == 1) { w = Math.Max(1, Math.Min(fw, xx)); xx = xx - w; al = "RIGHT"; }
            else if (align == 2) { w = Math.Max(2, Math.Min(fw, 2 * xx)); xx = Math.Floor(x - w / 2 + 0.5); al = "CENTER"; }
            if (!Tdm.SEq(Tdm.T(E.L(sl, 6)), al)) { Op(sl[0], OP_ALIGN, Str(al)); E.LS(sl, 6, Str(al)); }
            if (Tdm.D(E.L(sl, 7)) != w) { Op(sl[0], OP_WIDTH, Tdm.N(w)); E.LS(sl, 7, Tdm.N(w)); }
            double yy = Math.Floor(y - Tdm.D(E.L(sl, 8)) * 0.7 - ED_TXT_DY + Tdm.D(E.L(sl, 9)) + 0.5);
            if (xx != Tdm.D(E.L(sl, 3)) || yy != Tdm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Tdm.N(Math.Max(0, xx)));
                Op(sl[0], OP_MV, Tdm.N(Math.Max(0, yy - Tdm.D(E.L(sl, 1)))));
                E.LS(sl, 3, Tdm.N(xx)); E.LS(sl, 4, Tdm.N(yy));
            }
            E.LS(sl, 10, Tdm.N(x)); E.LS(sl, 11, Tdm.N(y)); E.LS(sl, 12, Tdm.N(align));
            E.LS(sl, 5, BooleanValue.True);
        }
        void Bar(ListValue sl, string nm, string key, double val)
        {
            var b = Geo("bar_" + key);
            double f = 0.5 + 0.5 * Math.Max(-1, Math.Min(1, val / b[4]));   // the - end, the + end, the scale
            Put(sl, b[0] == b[2] ? nm + "v" : nm, b[0] + (b[2] - b[0]) * f, b[1] + (b[3] - b[1]) * f);
        }

        // ---- the text helpers (edF1, edLR, edS1, edP3, edP2)
        static string F1(double x) { string s = Tdm.Num(Tdm.Round(x, 1)); if (!s.Contains(".")) s = s + ".0"; return s; }
        static string LR(double x, string a, string b)
        {
            double rx = Tdm.Round(x, 1);
            if (rx == 0) return "0.0";
            return (rx > 0 ? a : b) + F1(Math.Abs(rx));
        }
        static string S1(double x) { double rx = Tdm.Round(x, 1); return (rx >= 0 ? "+" : "") + F1(rx); }
        static string P3(double x) { string s = Tdm.Num(Tdm.Mod(Tdm.Round(x) + 720, 360)); while (s.Length < 3) s = "0" + s; return s; }
        static string P2(double n) { return (n < 10 ? "0" : "") + Tdm.Num(n); }

        // ---- lib_land's ldGreatCircle -> { dist m, bearing deg 0-360 }
        double[] Gc(double lat1, double lon1, double lat2, double lon2)
        {
            double dl = lon2 - lon1;
            double a = Math.Pow(Tdm.Sin((lat2 - lat1) / 2.0), 2) + Tdm.Cos(lat1) * Tdm.Cos(lat2) * Math.Pow(Tdm.Sin(dl / 2.0), 2);
            double dist = 2.0 * bodyR * Asin(Math.Min(1.0, Math.Sqrt(a))) * TG_D2R;
            double brg = Tdm.Atan2(Tdm.Sin(dl) * Tdm.Cos(lat2), Tdm.Cos(lat1) * Tdm.Sin(lat2) - Tdm.Sin(lat1) * Tdm.Cos(lat2) * Tdm.Cos(dl));
            if (brg < 0) brg = brg + 360.0;
            return new[] { dist, brg };
        }

        // ---- the predictor (edFamPrep / edFamD / edPredPath)
        class Fam { public ListValue[] V = new ListValue[2], C = new ListValue[2]; public double G; public int[] K = new int[2]; }
        Fam FamPrep(double v0, bool famDef)
        {
            if (!famDef) return null;
            if (!Tdm.B(E.Raw("EPR_FAM_OK"))) return null;
            var fam = Ls(E.Raw("EPR_FAM"));
            if (fam.Count < 2) return null;
            double uu = Math.Max(0, Math.Min(GD("EPR_FAM_UTOP"), GD("EPR_GS_U")));
            double x = uu * (fam.Count - 1);
            int i = (int)Math.Min(Math.Floor(x), fam.Count - 2);
            var fm = new Fam();
            fm.G = x - i;
            for (int m = 0; m <= 1; m++)
            {
                var mem = Ls(fam[i + m]);
                var vs = Ls(mem[1]);
                fm.V[m] = vs; fm.C[m] = Ls(mem[2]);
                if (vs.Count < 2) return null;
                int lo = 1, hi = vs.Count - 1;
                while (!(lo >= hi))
                {
                    int md = (int)Math.Floor((lo + hi) / 2.0);
                    if (Tdm.D(vs[md]) <= v0) hi = md; else lo = md + 1;
                }
                fm.K[m] = lo;
            }
            return fm;
        }
        static double FamD(Fam fm, double vr)
        {
            var d = new double[2];
            for (int m = 0; m <= 1; m++)
            {
                var vs = fm.V[m]; var cs = fm.C[m];
                int n = vs.Count;
                if (vr >= Tdm.D(vs[0])) d[m] = Tdm.D(cs[0]);
                else if (vr <= Tdm.D(vs[n - 1])) d[m] = Tdm.D(cs[n - 1]);
                else
                {
                    int k = Math.Max(1, fm.K[m]);
                    while (!(Tdm.D(vs[k]) <= vr)) k = k + 1;
                    fm.K[m] = k;
                    d[m] = Tdm.D(cs[k - 1]) + (Tdm.D(cs[k]) - Tdm.D(cs[k - 1])) * (Tdm.D(vs[k - 1]) - vr)
                        / Math.Max(Tdm.D(vs[k - 1]) - Tdm.D(vs[k]), 0.000000001);
                }
            }
            return d[0] * (1 - fm.G) + d[1] * fm.G;
        }
        // the predictor's turn (edPrAt / edPrRamp / edPrK)
        static double PrAt(ListValue l, double x0, double dx, double x)
        {
            int n = l.Count;
            double i = Math.Max(0, Math.Min(n - 1, (x - x0) / dx));
            int k = (int)Math.Min(n - 2, Math.Floor(i));
            return Tdm.D(l[k]) + (Tdm.D(l[k + 1]) - Tdm.D(l[k])) * (i - k);
        }
        double PrRamp(double v)
        {
            if (edPr.Count == 0) return 1;
            double r1 = Tdm.D(edPr[6]);
            if (r1 > 0 && v < r1)
            {
                double sp = r1 - Tdm.D(edPr[7]);
                double w = 1;
                if (sp > 0) w = (r1 - v) / sp;
                w = Math.Max(0, Math.Min(1, w));
                return 1 - w * (1 - Tdm.D(edPr[8]));
            }
            return 1;
        }
        double PrK(double v, double ld, double bk, double ao, double l0, double r0)
        {
            if (edPr.Count == 0) return ld * Tdm.Sin(0 - bk);
            double a = Math.Max(ED_PRED_AOA_MIN, PrAt(Ls(edPr[2]), Tdm.D(edPr[0]), Tdm.D(edPr[1]), v) + ao);
            return ld * PrAt(Ls(edPr[5]), Tdm.D(edPr[3]), Tdm.D(edPr[4]), a) / l0 * Tdm.Sin(0 - bk * PrRamp(v) / r0);
        }
        List<double>[] PredPath(double v0, double d0, double ld, double bk, double al, double sm, bool famDef)
        {
            double ao = 0, l0 = 1, r0 = 1;
            if (edPr.Count > 0)
            {
                ao = al - PrAt(Ls(edPr[2]), Tdm.D(edPr[0]), Tdm.D(edPr[1]), v0);
                l0 = PrAt(Ls(edPr[5]), Tdm.D(edPr[3]), Tdm.D(edPr[4]), Math.Max(ED_PRED_AOA_MIN, al));
                r0 = PrRamp(v0);
            }
            var fm = FamPrep(v0, famDef);
            double sc = 1;
            if (fm != null)
            {
                double dr0 = FamD(fm, v0);
                if (dr0 > 0.05) sc = d0 / dr0; else fm = null;
            }
            double dv = (v0 - ED_VT) / ED_PRED_STEPS;
            var tt = new List<double> { 0 }; var xs = new List<double> { 0 }; var ys = new List<double> { 0 };
            double t = 0, s = 0, x = 0, y = 0, vv = v0;
            double ps = 0;                          // the heading at vv
            double ta = -1;                         // the time the turn reaches ED_PRED_TURN (a step's start); -1: never
            for (int j = 0; !(j >= ED_PRED_STEPS || s >= sm); j++)
            {
                double vm = vv - dv / 2;
                double dm = d0;
                if (fm != null) dm = Math.Max(0.05, sc * FamD(fm, vm));
                double dt = dv / dm;
                double kk = PrK(vm, ld, bk, ao, l0, r0);
                double pm = Math.Max(0 - ED_PRED_TURN, Math.Min(ED_PRED_TURN, ps + kk * Math.Log(vv / vm) * R2D));
                if (ta < 0 && Math.Abs(pm) >= ED_PRED_TURN) ta = t;
                double ds = vm * dt;
                if (s + ds > sm) { double g = (sm - s) / ds; dt = dt * g; ds = ds * g; }   // end on sm
                x = x + ds * Tdm.Sin(pm);
                y = y + ds * Tdm.Cos(pm);
                s = s + ds;
                t = t + dt;
                ps = ps + kk * Math.Log(vv / (vv - dv)) * R2D;
                vv = vv - dv;
                tt.Add(t); xs.Add(x); ys.Add(y);
            }
            return new[] { tt, xs, ys, new List<double> { ta } };
        }

        // EDDRAW: one draw (edTickK's body after edTick's clock, edCyc and edSiteNear). inp = lib_entdisp's edCsIn:
        // [0] TIME, [1] daz, [2] db, [3] rgo, [4] lat, [5] lng, [6] the body's radius, [7] RWY_THRESH lat, [8] lng, [9] trk,
        // [10] spd, [11] bk, [12] FD_DRAG, [13] FD_LIFT, [14] MISSIONTIME, [15] alf, [16] be, [17] au, [18] gb, [19] ga,
        // [20..22] the rates, [23] the DAP's rate command (a LIST, or 0), [24] edLit(), [25] the HAC on, [26] its lat,
        // [27] lng, [28] EPR_HAC_YSGN, [29] RWY_HEADING, [30] RWY_NAME, [31] EPR_FAM_OK defined, [32] pre-entry
        public void Draw(ListValue inp)
        {
            Ops.Clear();
            Load();
            double daz = Tdm.D(inp[1]), db = Tdm.D(inp[2]), rgo = Tdm.D(inp[3]);
            double lat = Tdm.D(inp[4]), lng = Tdm.D(inp[5]);
            bodyR = Tdm.D(inp[6]);
            double thrLat = Tdm.D(inp[7]), thrLng = Tdm.D(inp[8]), trk = Tdm.D(inp[9]), spd = Tdm.D(inp[10]), bk = Tdm.D(inp[11]);
            double fdDrag = Tdm.D(inp[12]), fdLift = Tdm.D(inp[13]), mt = Tdm.D(inp[14]);
            double alf = Tdm.D(inp[15]), be = Tdm.D(inp[16]), au = Tdm.D(inp[17]), gb = Tdm.D(inp[18]), ga = Tdm.D(inp[19]);
            var wr = new[] { Tdm.D(inp[20]), Tdm.D(inp[21]), Tdm.D(inp[22]) };
            var wcL = inp[23] as ListValue;
            bool lit = Tdm.B(inp[24]), hon = Tdm.B(inp[25]);
            double hacYsgn = Tdm.D(inp[28]), rwyHdg = Tdm.D(inp[29]);
            string rwyName = Tdm.T(inp[30]);
            bool famDef = Tdm.B(inp[31]);
            bool preEnt = Tdm.B(inp[32]);           // pre-entry: no predictor
            bool gdl = inp.Count > 33 && Tdm.B(inp[33]);              // SW 02 GUIDANCE LOST (ENTRY): the guidance's bank / alpha rows "----", the fly-to bars off

            var f = Geo("field");
            double fs = f[2];
            double vx = Geo("veh")[0], vy = Geo("veh")[1], ah = Geo("ahead")[0];
            // the zoom: the tightest step with the site inside ZOOM_IN of it
            var gc = Gc(lat, lng, thrLat, thrLng);
            double rnm = gc[0] / 1852;
            var zs = Geo("zooms");                  // entry_bg.txt's steps, the widest first
            double zm = zs[0];
            foreach (double z in zs) if (rnm <= Geo("zoom_in")[0] * z) zm = z;
            double ppn = ah / zm;
            double a = gc[1] - trk;
            double sx = vx + rnm * ppn * Tdm.Sin(a);
            double sy = vy - rnm * ppn * Tdm.Cos(a);
            // the rings about the site (their labels with the map's other labels, below)
            double rsx = Tdm.Round(sx), rsy = Tdm.Round(sy);
            string ky = Tdm.Num(rsx) + " " + Tdm.Num(rsy) + " " + Tdm.Num(zm);
            if (!Tdm.SEq(ky, Tdm.T(E.G("edRgKey"))))
            {
                E.S("edRgKey", Str(ky));
                for (int g = 0; g < 3; g++)
                {
                    var bb = g == 2 ? Ls(K(edTmB, Tdm.Num(zm))) : Ls(edRgB[g]);
                    string pre = g == 2 ? "tm" + Tdm.Num(zm) + "_" : "rg" + Tdm.Num(g + 1) + "_";
                    var rs = Ls(edRg[g]);
                    for (int k = 0; k < bb.Count; k++)
                    {
                        var b = Ls(bb[k]);
                        var sl = Ls(rs[k]);
                        if (rsx + Tdm.D(b[0]) >= 1.5 && rsx + Tdm.D(b[1]) <= fs - 1.5 && rsy + Tdm.D(b[2]) >= 1.5 && rsy + Tdm.D(b[3]) <= fs - 1.5)
                            Put(sl, pre + P2(k), f[0] + rsx, f[1] + rsy);
                        else Off(sl);
                    }
                }
            }
            // the boxes the labels keep clear of: the bug's, then each symbol's as it is placed
            lbOb.Clear();
            lbOb.Add(new[] { vx - 10, vx + 10, vy - 10, vy + 10 });
            // the deadband: overbright while the site is outside it, flashing in ENTRY TRAJ's phase
            var dbg = Geo("db");
            double dj = Tdm.Round(Math.Max(0, Math.Min(dbg[1], db)) / dbg[0]);
            string dc = Math.Abs(daz) > db ? "o" : "m";
            string dn = Tdm.Num(dj * 5);
            while (dn.Length < 3) dn = "0" + dn;
            if (dc == "m") E.S("edDbA", new ListValue());
            else
            {
                var l = new ListValue();
                l.Add(Str("dbl" + dn + dc)); l.Add(Str("dbr" + dn + dc)); l.Add(Tdm.N(f[0] + vx)); l.Add(Tdm.N(f[1] + vy));
                E.S("edDbA", l);
            }
            if (dc == "m" || lit)
            {
                Put(S("db0"), "dbl" + dn + dc, f[0] + vx, f[1] + vy);
                Put(S("db1"), "dbr" + dn + dc, f[0] + vx, f[1] + vy);
            }
            else { Off(S("db0")); Off(S("db1")); }
            // the target's runway and its name. lib_entdisp's, on the page's map (the bearing out less the
            // track, plus the heading off the great circle's arrival stretched across the radial by c / sin c)
            var gbk = Gc(thrLat, thrLng, lat, lng);
            double gcc = gc[0] / bodyR, gph = rwyHdg - gbk[1] - 180;
            double rh = Tdm.Mod(Tdm.Round((gc[1] - trk + Tdm.Atan2(gcc / Math.Max(Tdm.Sin(gcc / TG_D2R), 0.01) * Tdm.Sin(gph),
                Tdm.Cos(gph))) / 10) * 10 + 1440, 360);
            bool rwOk = PutIn(S("rwy"), "rwy" + P3(rh), rsx, rsy);   // on the rings' whole px
            if (rwOk) lbOb.Add(new[] { rsx - 6, rsx + 6, rsy - 6, rsy + 6 });
            // the HAC centre (250 / 100 NM steps)
            if (hon && zm <= 250)
            {
                var hg = Gc(lat, lng, Tdm.D(inp[26]), Tdm.D(inp[27]));
                double ha = hg[1] - trk;
                double hx = rsx + Tdm.Round(vx + hg[0] / 1852 * ppn * Tdm.Sin(ha) - sx);
                double hy = rsy + Tdm.Round(vy - hg[0] / 1852 * ppn * Tdm.Cos(ha) - sy);
                if (PutIn(S("hac"), "hacx", hx, hy)) lbOb.Add(new[] { hx - 5, hx + 5, hy - 5, hy + 5 });
            }
            else Off(S("hac"));
            // the alternates (edNear: kOS's edSiteNear, before the call). one within ED_MERGE_PX of one shown
            // before joins that one's label, its own off
            var near = Ls(E.Raw("edNear"));
            var apX = new List<double>(); var apY = new List<double>(); var apN = new List<double>();
            var apS = new List<ListValue>(); var apT = new List<string>(); var apK = new List<string>();
            for (int i = 0; i < ED_ALT_N; i++)
            {
                var al = Ls(edAl[i]);
                bool ok = false;
                if (i < near.Count)
                {
                    var it = Ls(near[i]);
                    var ag = Gc(lat, lng, Tdm.D(it[1]), Tdm.D(it[2]));
                    double aa = ag[1] - trk;
                    double x = rsx + Tdm.Round(vx + ag[0] / 1852 * ppn * Tdm.Sin(aa) - sx);
                    double y = rsy + Tdm.Round(vy - ag[0] / 1852 * ppn * Tdm.Cos(aa) - sy);
                    if (x >= 6 && x <= fs - 6 && y >= 6 && y <= fs - 6)
                        ok = PutIn(Ls(al[0]), "alt", x, y);
                    if (ok)
                    {
                        lbOb.Add(new[] { x - 4, x + 4, y - 4, y + 4 });
                        string nm0 = Tdm.T(it[0]);
                        string nm = nm0.Substring(0, Math.Min(3, nm0.Length));
                        int j = -1;
                        for (int k = 0; k < apX.Count && j < 0; k++)
                        {
                            double ddx = apX[k] - x, ddy = apY[k] - y;
                            if (apN[k] < ED_MERGE_N && ddx * ddx + ddy * ddy <= ED_MERGE_PX * ED_MERGE_PX) j = k;
                        }
                        if (j >= 0) { apT[j] = apT[j] + "/" + nm; apN[j] = apN[j] + 1; Off(Ls(al[1])); }
                        else { apX.Add(x); apY.Add(y); apS.Add(Ls(al[1])); apT.Add(nm); apN.Add(1); apK.Add(nm); }
                    }
                }
                if (!ok) { Off(Ls(al[0])); Off(Ls(al[1])); }
            }
            // the predictor
            var pg = Geo("pred");
            double pn = pg[0];
            double np = 0;
            if (fdDrag > 0.3 && spd > ED_VT + 10 && !preEnt)
            {
                var pt = PredPath(spd, fdDrag, fdLift / fdDrag, bk, alf, pg[1] * fs / ppn * 1852, famDef);
                var tt = pt[0];
                double tl = tt[tt.Count - 1];
                double ta = pt[3][0];
                double ka = pn;                     // the dots even in time to tk, the rest on the path's end
                double tk = tl;
                if (ta > 0 && ta < tl && pn > 1) { ka = pn - 1; tk = ta; }   // the last but one on the turn's cap
                int j = 1;
                for (int i = 1; !(i > pn); i++)
                {
                    double ti = Math.Min(tl, i <= ka ? tk * i / ka : tl);
                    var sl = S("p" + i);
                    if (ti <= tl)
                    {
                        while (!(tt[j] >= ti)) j = j + 1;
                        double g = (ti - tt[j - 1]) / Math.Max(tt[j] - tt[j - 1], 0.001);
                        double x = vx + (pt[1][j - 1] + (pt[1][j] - pt[1][j - 1]) * g) / 1852 * ppn;
                        double y = vy - (pt[2][j - 1] + (pt[2][j] - pt[2][j - 1]) * g) / 1852 * ppn;
                        if (x >= 6 && x <= fs - 6 && y >= 6 && y <= fs - 6)
                        {
                            if (PutIn(sl, "pred", x, y)) lbOb.Add(new[] { x - 4, x + 4, y - 4, y + 4, 1 });   // soft
                        }
                        else Off(sl);
                    }
                    else Off(sl);
                    np = i;
                }
            }
            for (int i = (int)np + 1; !(i > pn); i++) Off(S("p" + i));
            // the labels in priority (after the predictor: its dots are boxes too, the DB lines a line test): the
            // runway name, the alternates', the rings' (sliding along the ring), the DB's
            lbDb = new[] { vx, vy, Tan(dj * dbg[0]) };
            lbOld = zm == Tdm.D(E.G("edLbZm")) ? Lx(E.G("edLbMem")) : new Lexicon();
            lbNw = new Lexicon();
            rqSl.Clear(); rqS.Clear(); rqC.Clear(); rqK.Clear();
            if (rwOk) LbPut(S("lrw"), rwyName, rsx, rsy, ED_LB_RW, "rw"); else Off(S("lrw"));
            for (int i = 0; i < apX.Count; i++) LbPut(apS[i], apT[i], apX[i], apY[i], ED_LB_AL, "a" + apK[i]);
            ListValue[] ls = { S("lr1"), S("lr2"), S("ltm") };
            string[] lt = { Tdm.Num(Tdm.Round(Geo("ring_f")[0] * zm)), Tdm.Num(Tdm.Round(Geo("ring_f")[1] * zm)), "TAEM" };
            double[] rr = { Geo("ring_f")[0] * ah, Geo("ring_f")[1] * ah, Geo("taem")[0] * ppn };
            for (int g = 0; g < 3; g++)
            {
                var rs = Ls(edRg[g]);
                int n = (g == 2 ? Ls(K(edTmB, Tdm.Num(zm))) : Ls(edRgB[g])).Count;
                var cs = new List<double[]>();      // the spots beside a piece shown, id the try j
                for (int j = 0; j < ED_RG_TRY && n > 0; j++)
                {
                    double am = 240 + ED_RG_DA * (j % 2 == 0 ? j / 2 : -(j + 1) / 2);
                    int k = (int)Math.Min(n - 1, Math.Floor(Tdm.Mod(am, 360) * n / 360));
                    if (Tdm.B(E.L(Ls(rs[k]), 5)))
                    {
                        double ca = Tdm.Cos(am);
                        double la = 2;
                        if (ca < -0.3) la = 1; else if (ca > 0.3) la = 0;
                        cs.Add(new[] { rsx + (rr[g] + 8) * ca, rsy - (rr[g] + 8) * Tdm.Sin(am), la, j });
                    }
                }
                LbAdd(ls[g], lt[g], cs, "r" + Tdm.Num(g));
            }
            double tb = Tan(db);
            string dbs = "DB " + F1(db);
            LbAdd(S("ldb"), dbs, new List<double[]> { new[] { vx + 70 * tb + 6, vy - 70, 0, 0 },
                new[] { vx - 70 * tb - 6, vy - 70, 1, 1 }, new[] { vx + 100 * tb + 6, vy - 100, 0, 2 } }, "db");
            LbRun(f);                               // the labels placed together
            E.S("edLbMem", lbNw);
            E.S("edLbZm", Tdm.N(zm));
            Put(S("bug"), "bug", f[0] + vx, f[1] + vy);
            // the texts
            double dd = Math.Floor(mt / 86400);
            string ds = Tdm.Num(dd);
            while (ds.Length < 3) ds = "0" + ds;
            var m0 = Geo("met");
            Text(S("met"), ds + "/" + P2(Math.Floor(Tdm.Mod(mt, 86400) / 3600)) + ":" + P2(Math.Floor(Tdm.Mod(mt, 3600) / 60)) + ":"
                + P2(Math.Floor(Tdm.Mod(mt, 60))), m0[0], m0[1], 2);
            Text(S("trk"), "TRK " + P3(trk), Geo("trk")[0], Geo("trk")[1], 2);
            Text(S("zm"), Tdm.Num(zm) + " NM", Geo("zoomlab")[0], Geo("zoomlab")[1], 0);
            var lv = Geo("lval");
            string hs = "";
            if (hon) hs = (hacYsgn < 0 ? "L" : "R") + " OVHD";
            string[] rows = { rwyName, hs, Tdm.Num(Tdm.Round(rgo / 1852)), Tdm.Num(Tdm.Round(Math.Abs(rnm * Tdm.Sin(a)))), S1(daz), P3(trk) };
            for (int i = 0; i < 6; i++) Text(S("l" + i), rows[i], lv[0], lv[1] + i * lv[2], 1);
            var ad = Geo("adi");
            string[] av = { LR(bk, "L", "R"), LR(au, "U", "D"), LR(be, "L", "R"), gdl ? "----" : LR(gb, "L", "R"), gdl ? "----" : LR(ga, "U", "D"), LR(0, "L", "R") };
            string[] ak = { "aR", "aP", "aY", "gR", "gP", "gY" };
            for (int i = 0; i < 6; i++) Text(S(ak[i]), av[i], ad[0] + Tdm.Mod(i, 3) * ad[1], i < 3 ? ad[2] : ad[3], 1);
            // the bars
            string[] rk = { "rp", "rq", "rr" };
            for (int i = 0; i < 3; i++)
            {
                Bar(S("t" + rk[i]), "tri", rk[i], wr[i]);
                if (wcL != null) Bar(S("c" + rk[i]), "arr", rk[i], Tdm.D(wcL[i])); else Off(S("c" + rk[i]));
            }
            if (gdl) { Off(S("teb")); Off(S("tea")); }
            else
            {
                Bar(S("teb"), "tri", "eb", bk - gb);   // fly-to
                Bar(S("tea"), "tri", "ea", ga - alf);
            }
            Bar(S("tey"), "tri", "ey", be);
        }
    }
}
