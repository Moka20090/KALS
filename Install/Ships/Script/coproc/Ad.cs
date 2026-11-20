// lib_ascdisp.ks's per-update math (the ascent pages ASCENT / LAUNCH / TAL / RTLS TRAJ 1 and 2, RTLS TRAJ 2,
// OMS/MPS: adState's math, adTraj1, adTraj2, adTrajR2, adEng, adCommon and everything under them) in C#, line for line
// with kOS's semantics (trig in degrees, ROUND = Math.Round, MOD = %, MIN / MAX, FLOOR, vectors through KSP's Vector3d as
// kOS's Vector does, numbers to text by kOS.Safe's own ScalarValue ToString, string '=' / list CONTAINS / INDEXOF / lexicon
// keys case-insensitive, a string's CONTAINS / FIND / REPLACE ordinal).
// THE STATE STAYS KOS'S: every global (adBg, adHist, adFrzNL, adFrzL, adFrzNM, adFrzM, adTmS) and every widget slot's
// bookkeeping (sl[2..16]) is read from kOS at each call and written back (AdEnv) only after the whole call succeeded, so
// kOS's own code can take over at any update. THE WIDGETS STAY KOS'S: every widget write the kOS code would make comes
// back as an op (widget, code, value), in the kOS code's order. THE GAME READS STAY KOS'S (the hook's adCsIn, with the
// other libraries' calls: asc_abr_site, asc_burnable, asc_rtls_vline ...): this file touches no Unity object, no widget.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    // reference identity for kOS collections used as keys
    public class AdRef<T> : IEqualityComparer<T> where T : class
    {
        public bool Equals(T a, T b) { return ReferenceEquals(a, b); }
        public int GetHashCode(T o) { return System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(o); }
    }

    // the kOS side: globals by name, list elements, lexicon entries; writes captured (Commit applies them);
    // reads see the captured writes first
    public class AdEnv
    {
        readonly kOS.Safe.Execution.ICpu cpu;
        public Dictionary<string, Structure> Gw = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<ListValue, Dictionary<int, Structure>> Lw = new Dictionary<ListValue, Dictionary<int, Structure>>(new AdRef<ListValue>());
        public Dictionary<Lexicon, Dictionary<string, Structure>> Xw = new Dictionary<Lexicon, Dictionary<string, Structure>>(new AdRef<Lexicon>());
        public AdEnv(kOS.Safe.Execution.ICpu c) { cpu = c; }
        public void Clear() { Gw.Clear(); Lw.Clear(); Xw.Clear(); }
        public Structure Raw(string n) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + n, false)); }
        public Structure G(string n) { Structure v; if (Gw.TryGetValue(n, out v)) return v; return Raw(n); }
        public void S(string n, Structure v) { Gw[n] = v; }
        public Structure L(ListValue l, int i)
        {
            Dictionary<int, Structure> d; Structure v;
            if (Lw.TryGetValue(l, out d) && d.TryGetValue(i, out v)) return v;
            return l[i];
        }
        public void LS(ListValue l, int i, Structure v)
        {
            Dictionary<int, Structure> d;
            if (!Lw.TryGetValue(l, out d)) { d = new Dictionary<int, Structure>(); Lw[l] = d; }
            d[i] = v;
        }
        public bool XHas(Lexicon x, string k)
        {
            Dictionary<string, Structure> d;
            if (Xw.TryGetValue(x, out d) && d.ContainsKey(k)) return true;
            return x.ContainsKey(new StringValue(k));
        }
        public Structure X(Lexicon x, string k)
        {
            Dictionary<string, Structure> d; Structure v;
            if (Xw.TryGetValue(x, out d) && d.TryGetValue(k, out v)) return v;
            return x[new StringValue(k)];
        }
        public void XS(Lexicon x, string k, Structure v)
        {
            Dictionary<string, Structure> d;
            if (!Xw.TryGetValue(x, out d)) { d = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase); Xw[x] = d; }
            d[k] = v;
        }
        public void Commit()
        {
            foreach (var kv in Lw) foreach (var kv2 in kv.Value) kv.Key[kv2.Key] = kv2.Value;
            foreach (var kv in Xw) foreach (var kv2 in kv.Value) kv.Key[new StringValue(kv2.Key)] = kv2.Value;
            foreach (var kv in Gw) cpu.SetGlobal("$" + kv.Key, kv.Value);
            Clear();
        }
    }

    // kOS's math and text, as kOS.Safe does it
    public static class Adm
    {
        public static double D(Structure s)
        {
            var sc = s as ScalarValue;
            if (sc == null) throw new Exception("not a number: " + (s == null ? "null" : s.GetType().Name));
            double d = sc.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new Exception("not finite");
            return d;
        }
        public static bool B(Structure s)
        {
            if (s is BooleanValue) return ((BooleanValue)s).Value;
            if (s is ScalarValue) return ((ScalarValue)s).GetDoubleValue() != 0;
            throw new Exception("not a boolean: " + (s == null ? "null" : s.GetType().Name));
        }
        public static string T(Structure s) { if (s == null) throw new Exception("null text"); return s.ToString(); }
        public static bool SEq(string a, string b) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
        public static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        public static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        public static double Round(double x) { return Math.Round(x); }
        public static double Round(double x, int n) { return Math.Round(x, n); }
        public static double Mod(double a, double b) { return a % b; }
        public static string Num(double x) { return ScalarValue.Create(x).ToString(); }
        public static ScalarValue N(double x) { return ScalarValue.Create(x); }
        public static bool LContains(List<string> l, string s) { foreach (var x in l) if (SEq(x, s)) return true; return false; }
        public static int LIndexOf(string[] l, string s) { for (int i = 0; i < l.Length; i++) if (SEq(l[i], s)) return i; return -1; }
    }

    // adState's values (lib_ascdisp's st lexicon)
    public class AdSt
    {
        public double met, vrel, vi, h, hdot, vh, fsrb, fsrb_pk, g, keas, vreld, vid, hdd, vhd;
        public string ph;
        public bool s1, after, hasVl;
        public double[] vl;
    }

    public class AdCalc
    {
        public const int OP_TEXT = 0, OP_IMAGE = 1, OP_WIDTH = 2, OP_HEIGHT = 3, OP_MH = 4, OP_MV = 5, OP_ALIGN = 6, OP_BG = 7;
        public AdEnv E;
        readonly Func<Structure, Vector3d> vin;
        public List<Structure> Ops = new List<Structure>();

        // per call: kOS's constants and tables (read, never retyped)
        double AD_FIT_IN;
        double AD_FT, AD_NM, AD_RHO0, AD_KT, AD_HIST_S, AD_ET_SEP_S, AD_IMG_DY, AD_TXT_DY, AD_FLOW_PX, AD_ROW_DY, AD_HDR_DY,
            AD_DRP_X, AD_TICK_CW, AD_ENG_BAR_HW, AD_ENG_BAR_YB, AD_TM_DRIFT, AD_TM_HOLD, AD_TM_JUMP, AD_DT;
        double ASC_PL_TO_KSP, ASC_VDMAG, ASC_ROLL_RATE, ASC_MECO_H, ASC_GAMD, ASC_R;
        double[] ASC_RTLS_A_MECO;
        bool AD_TICK_FRZ_1EO, AD_TM_WAIT;
        string AD_DIR, AD_YELLOW, AD_RED, AD_DIM, adFill, adFillDim, adBlank;
        Structure adFillS, adFillDimS, adBlankS, adBox, adCycS;
        double adCyc;
        Lexicon adGeo, adBnd, adSpr, adS, adOut, adFrzM, adTmS, AD_TICK_LAB, AD_TICK_1EO;
        ListValue adFrzL;
        List<string> AD_TICKS, AD_TICKS_1EO;
        Lexicon asc;
        ListValue inp;
        string[] site = new string[4];

        public AdCalc(AdEnv e, Func<Structure, Vector3d> vi) { E = e; vin = vi; }

        double GD(string n) { return Adm.D(E.Raw(n)); }
        static List<string> SList(Structure s)
        {
            var l = s as ListValue; if (l == null) throw new Exception("not a LIST");
            var r = new List<string>(); foreach (var x in l) r.Add(Adm.T(x)); return r;
        }
        static Lexicon Lx(Structure s) { var l = s as Lexicon; if (l == null) throw new Exception("not a LEXICON"); return l; }
        static ListValue Ls(Structure s) { var l = s as ListValue; if (l == null) throw new Exception("not a LIST"); return l; }
        static Structure K(Lexicon x, string k) { return x[new StringValue(k)]; }
        static bool Has(Lexicon x, string k) { return x.ContainsKey(new StringValue(k)); }
        double[] Geo(string k)
        {
            var l = Ls(K(adGeo, k));
            var r = new double[l.Count]; for (int i = 0; i < l.Count; i++) r[i] = Adm.D(l[i]); return r;
        }
        ListValue Slot(string n) { return Ls(K(adS, n)); }

        public void Load()
        {
            AD_FT = GD("AD_FT"); AD_NM = GD("AD_NM"); AD_RHO0 = GD("AD_RHO0"); AD_KT = GD("AD_KT"); AD_HIST_S = GD("AD_HIST_S");
            AD_ET_SEP_S = GD("AD_ET_SEP_S"); AD_IMG_DY = GD("AD_IMG_DY"); AD_TXT_DY = GD("AD_TXT_DY"); AD_FLOW_PX = GD("AD_FLOW_PX"); AD_FIT_IN = GD("AD_FIT_IN");
            AD_ROW_DY = GD("AD_ROW_DY"); AD_HDR_DY = GD("AD_HDR_DY"); AD_DRP_X = GD("AD_DRP_X"); AD_TICK_CW = GD("AD_TICK_CW");
            AD_ENG_BAR_HW = GD("AD_ENG_BAR_HW"); AD_ENG_BAR_YB = GD("AD_ENG_BAR_YB"); AD_TM_DRIFT = GD("AD_TM_DRIFT");
            AD_TM_HOLD = GD("AD_TM_HOLD"); AD_TM_JUMP = GD("AD_TM_JUMP"); AD_DT = GD("AD_DT");
            AD_TICK_FRZ_1EO = Adm.B(E.Raw("AD_TICK_FRZ_1EO")); AD_TM_WAIT = Adm.B(E.Raw("AD_TM_WAIT"));
            AD_DIR = Adm.T(E.Raw("AD_DIR")); AD_YELLOW = Adm.T(E.Raw("AD_YELLOW")); AD_RED = Adm.T(E.Raw("AD_RED")); AD_DIM = Adm.T(E.Raw("AD_DIM"));
            ASC_PL_TO_KSP = GD("ASC_PL_TO_KSP"); ASC_VDMAG = GD("ASC_VDMAG"); ASC_ROLL_RATE = GD("ASC_ROLL_RATE");
            ASC_MECO_H = GD("ASC_MECO_H"); ASC_GAMD = GD("ASC_GAMD"); ASC_R = GD("ASC_R");
            var am = Ls(E.Raw("ASC_RTLS_A_MECO")); ASC_RTLS_A_MECO = new double[am.Count];
            for (int i = 0; i < am.Count; i++) ASC_RTLS_A_MECO[i] = Adm.D(am[i]);
            adFillS = E.Raw("adFill"); adFill = Adm.T(adFillS);
            adFillDimS = E.Raw("adFillDim"); adFillDim = Adm.T(adFillDimS);
            adBlankS = E.Raw("adBlank"); adBlank = Adm.T(adBlankS);
            adBox = E.Raw("adBox");
            adGeo = Lx(E.Raw("adGeo")); adBnd = Lx(E.Raw("adBnd")); adSpr = Lx(E.Raw("adSpr")); adS = Lx(E.Raw("adS"));
            adOut = Lx(E.Raw("adOut")); adFrzM = Lx(E.Raw("adFrzM")); adTmS = Lx(E.Raw("adTmS")); adFrzL = Ls(E.Raw("adFrzL"));
            AD_TICK_LAB = Lx(E.Raw("AD_TICK_LAB")); AD_TICK_1EO = Lx(E.Raw("AD_TICK_1EO"));
            AD_TICKS = SList(E.Raw("AD_TICKS")); AD_TICKS_1EO = SList(E.Raw("AD_TICKS_1EO"));
            adCycS = E.Raw("adCyc"); adCyc = Adm.D(adCycS);
        }

        // ADSETUP: everything a draw reads is there (a missing name throws here, once, and kOS keeps drawing)
        public void Setup()
        {
            Load();
            foreach (var k in new[] { "clock_px", "abt_px", "msg_px", "bar1_px", "bar2_px", "t1_field_px", "t2_field_px", "t1_keas_px",
                "t2_dhd_px", "t2_g_px", "r2_bar_px", "r2_field_px", "pred_r2", "r2_g_px", "r2_lr_px", "t1_rpy_px", "t2_rpy_px",
                "t2_hdot_px", "t1_col_px", "t2_col_px", "t1_lr_px", "t2_lr_px", "eng_bar_px", "eng_ssme_x", "eng_srb_x",
                "eng_val_px", "eng_list_px", "barlab_px", "hdnom", "pred_s", "pclo" }) Geo(k);
            foreach (var p in new[] { "", "e" })
            {
                Slot(p + "met"); Slot(p + "warn");
                for (int i = 0; i < 3; i++) { Slot(p + "ab" + i); Slot(p + "m" + i); }
            }
            foreach (var k in new[] { "bar", "veh", "p1", "p2", "ptr1", "ptr2", "c0", "c8", "r0", "r2", "hdot", "lr0", "lr2", "dr0",
                "dr1", "tk7", "tl7", "b0", "b4", "v0", "v4", "s0", "s4", "l0", "l6" }) Slot(k);
            Ls(E.Raw("adAll")); Ls(E.Raw("adAllE")); Ls(E.Raw("adHist")); Ls(E.Raw("adMsgs"));
        }

        void Op(Structure w, int code, Structure v) { Ops.Add(w); Ops.Add(ScalarValue.Create(code)); Ops.Add(v); }

        // ---- the slots
        void SlotOn(ListValue sl)
        {
            E.LS(sl, 6, adCycS);
            if (!Adm.B(E.L(sl, 5)))
            {
                if (Adm.SEq(Adm.T(E.L(sl, 15)), "B")) Op(sl[0], OP_BG, E.L(sl, 16));
                E.LS(sl, 5, BooleanValue.True);
            }
        }
        void SlotOff(ListValue sl)
        {
            if (Adm.B(E.L(sl, 5)))
            {
                string kd = Adm.T(E.L(sl, 15));
                if (Adm.SEq(kd, "T")) Op(sl[0], OP_TEXT, new StringValue(""));
                else if (Adm.SEq(kd, "I")) Op(sl[0], OP_IMAGE, adBlankS);
                else Op(sl[0], OP_BG, adBlankS);
                E.LS(sl, 2, new StringValue(""));
                E.LS(sl, 5, BooleanValue.False);
            }
        }
        void Put(ListValue sl, string nm, double x, double y)
        {
            if (x == Adm.D(E.L(sl, 11)) && y == Adm.D(E.L(sl, 12)) && Adm.SEq(nm, Adm.T(E.L(sl, 2))) && nm != "") { SlotOn(sl); return; }
            if (nm == "" || !Has(adSpr, nm)) { SlotOff(sl); return; }
            var sp = Ls(K(adSpr, nm));
            if (!Adm.SEq(Adm.T(E.L(sl, 2)), nm))
            {
                Op(sl[0], OP_IMAGE, sp[0]);
                Op(sl[0], OP_WIDTH, sp[1]);
                Op(sl[0], OP_HEIGHT, sp[2]);
                E.LS(sl, 2, new StringValue(nm));
            }
            double xx = Adm.Round(x - Adm.D(sp[3]));
            double yy = Adm.Round(y - Adm.D(sp[4]));
            if (xx != Adm.D(E.L(sl, 3)) || yy != Adm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Adm.N(Math.Max(0, xx)));
                Op(sl[0], OP_MV, Adm.N(Math.Max(0, yy - AD_IMG_DY - Adm.D(sl[1]) * AD_FLOW_PX)));
                E.LS(sl, 3, Adm.N(xx)); E.LS(sl, 4, Adm.N(yy));
            }
            E.LS(sl, 11, Adm.N(x)); E.LS(sl, 12, Adm.N(y));
            SlotOn(sl);
        }
        void Text(ListValue sl, string s, double x, double y, double align)
        {
            if (s == "") { SlotOff(sl); return; }
            if (x == Adm.D(E.L(sl, 11)) && y == Adm.D(E.L(sl, 12)) && align == Adm.D(E.L(sl, 13)) && Adm.SEq(s, Adm.T(E.L(sl, 2))))
            { SlotOn(sl); return; }
            if (!Adm.SEq(Adm.T(E.L(sl, 2)), s))
            {   // in <b> unless the slot is in the page face (lib_ascdisp adTxtSlot's bd, sl[17])
                Op(sl[0], OP_TEXT, new StringValue(Adm.B(E.L(sl, 17)) ? "<b>" + s + "</b>" : s)); E.LS(sl, 2, new StringValue(s));
            }
            double fw = Adm.D(E.L(sl, 14));
            double w = fw;
            double xx = Adm.Round(x);
            string al = "LEFT";
            if (align == 1) { w = Math.Max(1, Math.Min(fw, xx)); xx = xx - w; al = "RIGHT"; }
            else if (align == 2) { w = Math.Max(2, Math.Min(fw, 2 * xx)); xx = Adm.Round(x - w / 2); al = "CENTER"; }
            if (!Adm.SEq(Adm.T(E.L(sl, 7)), al)) { Op(sl[0], OP_ALIGN, new StringValue(al)); E.LS(sl, 7, new StringValue(al)); }
            if (Adm.D(E.L(sl, 8)) != w) { Op(sl[0], OP_WIDTH, Adm.N(w)); E.LS(sl, 8, Adm.N(w)); }
            double yy = Adm.Round(y - Adm.D(E.L(sl, 9)) * 0.7 - AD_TXT_DY + Adm.D(E.L(sl, 10)));
            if (xx != Adm.D(E.L(sl, 3)) || yy != Adm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Adm.N(Math.Max(0, xx)));
                Op(sl[0], OP_MV, Adm.N(Math.Max(0, yy - Adm.D(sl[1]) * AD_FLOW_PX)));
                E.LS(sl, 3, Adm.N(xx)); E.LS(sl, 4, Adm.N(yy));
            }
            E.LS(sl, 11, Adm.N(x)); E.LS(sl, 12, Adm.N(y)); E.LS(sl, 13, Adm.N(align));
            SlotOn(sl);
        }
        void Bar(ListValue sl, double x0, double y0, double x1, double y1)
        {
            double w = Adm.Round(x1 - x0);
            double h = Adm.Round(y1 - y0);
            if (w < 1 || h < 1) { SlotOff(sl); return; }
            if (Adm.D(E.L(sl, 8)) != w) { Op(sl[0], OP_WIDTH, Adm.N(w)); E.LS(sl, 8, Adm.N(w)); }
            if (Adm.D(E.L(sl, 9)) != h) { Op(sl[0], OP_HEIGHT, Adm.N(h)); E.LS(sl, 9, Adm.N(h)); }
            double xx = Adm.Round(x0);
            double yy = Adm.Round(y0);
            if (xx != Adm.D(E.L(sl, 3)) || yy != Adm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Adm.N(Math.Max(0, xx)));
                Op(sl[0], OP_MV, Adm.N(Math.Max(0, yy - Adm.D(sl[1]) * AD_FLOW_PX)));
                E.LS(sl, 3, Adm.N(xx)); E.LS(sl, 4, Adm.N(yy));
            }
            SlotOn(sl);
        }
        void BarFill(ListValue sl, Structure f)
        {
            if (Adm.SEq(Adm.T(E.L(sl, 16)), Adm.T(f))) return;
            E.LS(sl, 16, f);
            if (Adm.B(E.L(sl, 5))) Op(sl[0], OP_BG, f);
        }
        void Sweep(ListValue lst)
        {
            foreach (var o in lst)
            {
                var sl = (ListValue)o;
                if (Adm.B(E.L(sl, 5))) { if (Adm.D(E.L(sl, 6)) != adCyc) SlotOff(sl); }
            }
        }
        void SetBg(string nm)
        {
            string f = AD_DIR + nm + ".png";
            if (!Adm.SEq(f, Adm.T(E.G("adBg")))) { Op(adBox, OP_BG, new StringValue(f)); E.S("adBg", new StringValue(f)); }
        }

        // ---- formats
        static string Mmss(double t)
        {
            double a = Math.Floor(Math.Max(t, 0));
            double ss = Adm.Mod(a, 60);
            return Adm.Num(Math.Floor(a / 60)) + ":" + (ss < 10 ? "0" : "") + Adm.Num(ss);
        }
        static string Fx(double x, int nd)
        {
            string s = Adm.Num(Adm.Round(x, nd));
            if (nd > 0)
            {
                if (s.IndexOf(".", StringComparison.Ordinal) < 0) s = s + ".";
                while (!(s.Length - s.IndexOf(".", StringComparison.Ordinal) > nd)) s = s + "0";
            }
            return s;
        }
        static string Sgn(double x) { double n = Adm.Round(x); return (n >= 0 ? "+" : "") + Adm.Num(n); }
        string Pl(double pl) { return Adm.Num(Math.Floor(Math.Min(pl, 100 / ASC_PL_TO_KSP) + 0.05)); }
        static string Pad0(double v, int n) { return Adm.Num(v).PadLeft(n).Replace(" ", "0"); }
        static string Clock(double t)
        {
            double a = Math.Floor(Math.Max(t, 0));
            double d = Math.Floor(a / 86400);
            double hh = Math.Floor(Adm.Mod(a, 86400) / 3600);
            double mm = Math.Floor(Adm.Mod(a, 3600) / 60);
            double ss = Adm.Mod(a, 60);
            return Pad0(d, 3) + "/" + Pad0(hh, 2) + ":" + Pad0(mm, 2) + ":" + Pad0(ss, 2);
        }

        // ---- the geometry
        static double ScaleY(double[] g, double val)
        {
            double f = (Math.Min(Math.Max(val, g[3]), g[4]) - g[3]) / (g[4] - g[3]);
            return g[1] + f * (g[2] - g[1]);
        }
        double[] Field(int k, double x, double y, bool clamp) { return FieldG(Geo("t" + k + "_field_px"), x, y, clamp); }
        static double[] FieldG(double[] g, double x, double y, bool clamp)
        {
            double fx = (x - g[4]) / (g[5] - g[4]);
            double fy = (y - g[6]) / (g[7] - g[6]);
            if (clamp) { fx = Math.Min(Math.Max(fx, 0), 1); fy = Math.Min(Math.Max(fy, 0), 1); }
            else if (fx < 0 || fx > 1 || fy < 0 || fy > 1) return null;
            return new[] { g[0] + g[2] * fx, g[1] + g[3] * (1 - fy) };
        }
        // lib_ascdisp adFits / adHold (the sprite nm at p, where Put draws it, wholly inside the field g less
        // AD_FIT_IN; p moved the least that keeps it so)
        bool Fits(string nm, double[] p, double[] g)
        {
            if (!Has(adSpr, nm)) return false;
            var sp = Ls(K(adSpr, nm));
            double l = Adm.Round(p[0] - Adm.D(sp[3]));
            double t = Adm.Round(p[1] - Adm.D(sp[4]));
            return l >= g[0] + AD_FIT_IN && l + Adm.D(sp[1]) <= g[0] + g[2] - AD_FIT_IN && t >= g[1] + AD_FIT_IN
                && t + Adm.D(sp[2]) <= g[1] + g[3] - AD_FIT_IN;
        }
        double[] Hold(string nm, double[] p, double[] g)
        {
            if (!Has(adSpr, nm)) return p;
            var sp = Ls(K(adSpr, nm));
            double w = Adm.D(sp[1]), h = Adm.D(sp[2]), ax = Adm.D(sp[3]), ay = Adm.D(sp[4]);
            return new[] { Math.Max(g[0] + ax + AD_FIT_IN, Math.Min(g[0] + g[2] - w + ax - AD_FIT_IN, p[0])),
                           Math.Max(g[1] + ay + AD_FIT_IN, Math.Min(g[1] + g[3] - h + ay - AD_FIT_IN, p[1])) };
        }
        static double BarX(double[] g, double vi) { return g[0] + (Math.Min(Math.Max(vi, g[3]), g[4]) - g[3]) / (g[4] - g[3]) * (g[1] - g[0]); }
        static double Interp(double[] pr, double x)
        {
            if (x <= pr[0]) return pr[1];
            for (int i = 2; i < pr.Length; i += 2)
                if (x <= pr[i]) return pr[i - 1] + (x - pr[i - 2]) / (pr[i] - pr[i - 2]) * (pr[i + 1] - pr[i - 1]);
            return pr[pr.Length - 1];
        }

        // ---- the abort modes
        double Bk(string k)
        {
            if (Has(asc, "abr"))
            {
                var b = Lx(K(Lx(K(asc, "abr")), "b"));
                if (Has(b, k)) return Adm.D(K(b, k)) / AD_FT;
            }
            return Adm.D(K(adBnd, k));
        }
        string Cont(int n)
        {
            if (!Has(asc, "abr")) return "CONT";
            if (Adm.SEq(site[n], "NONE")) return "BLUE";
            return "GREEN";
        }
        string[] Modes(double vi)
        {
            string one = "PRESS";
            if (vi < Bk("PRESS"))
            {
                one = "";
                if (vi >= Bk("ATO")) one = "ATO ";
                if (vi >= Bk("E_TAL")) one = one + "TAL ";
                if (vi < Bk("NEG_RTN")) one = one + "RTLS";
                one = one.Trim();
                if (one == "") one = Cont(1);
            }
            if (Has(asc, "eo1_ln"))
            {
                string e1 = Adm.T(K(asc, "eo1_ln"));
                if (e1 != "") one = e1;
                string ab = Adm.T(K(asc, "abort"));
                if (ab != "" && !Adm.SEq(ab, "CONT")) one = ab;
            }
            string two = "PRESS";
            if (vi < Bk("PRESS_2EO"))
            {
                two = "";
                if (vi >= Bk("ATO_2EO")) two = "ATO ";
                if (vi >= Bk("TAL_2EO")) two = two + "TAL";
                two = two.Trim();
                if (two == "") two = Cont(2);
            }
            string three = Cont(3);
            if (Has(asc, "eo3_ln")) { string e3 = Adm.T(K(asc, "eo3_ln")); if (e3 != "") three = e3; }
            return new[] { one, two, three };
        }
        double Co()
        {
            if (Adm.B(K(asc, "s2_on"))) return Adm.D(K(Lx(K(Lx(K(asc, "g")), "peg")), "VDMAG")) / AD_FT;
            return ASC_VDMAG / AD_FT;
        }
        int TickLv(string k) { return Adm.LContains(AD_TICKS_1EO, k) ? 1 : 2; }
        double FrzLv() { return Math.Min(2, Math.Max(0, adOut.Count - 1)); }
        double FrzLvTk() { if (AD_TICK_FRZ_1EO) return Math.Min(2, adOut.Count); return FrzLv(); }
        bool TickRel(string k)
        {
            string sel = "";
            if (Has(asc, "abort")) sel = Adm.T(K(asc, "abort"));
            if (Adm.LContains(AD_TICKS_1EO, k))
            {
                if (Has(AD_TICK_1EO, sel)) return Adm.SEq(k, Adm.T(K(AD_TICK_1EO, sel)));
                return true;
            }
            if (sel == "") return true;
            if (Adm.SEq(sel, "ATO") || Adm.SEq(sel, "AOA")) return !Adm.SEq(k, "PRESS_2EO");
            if (Adm.SEq(sel, "TAL")) return Adm.SEq(k, "TAL_2EO");
            return false;
        }
        static string Rel2(string sel, string tx)
        {
            var ws = tx.Split(new[] { " " }, StringSplitOptions.None);
            bool op = Adm.LIndexOf(ws, "PRESS") >= 0 || Adm.LIndexOf(ws, "ATO") >= 0 || Adm.LIndexOf(ws, "TAL") >= 0;
            if (!op) return tx;
            if (Adm.SEq(sel, "TAL")) return "TAL";
            if (Adm.SEq(sel, "ATO") || Adm.SEq(sel, "AOA"))
            {
                var o = new List<string>();
                foreach (var w in ws)
                {
                    string w2 = Adm.SEq(w, "PRESS") ? "ATO" : w;
                    if (!Adm.LContains(o, w2)) o.Add(w2);
                }
                return string.Join(" ", o.ToArray());
            }
            return tx;
        }

        void Ticks(double[] g, double co)
        {
            var bl = Geo("barlab_px");
            var tv = new List<double>(); var tl = new List<string>(); var th = new List<double>(); var td = new List<bool>();
            double fz = FrzLvTk();
            double nm = Adm.D(E.G("adFrzNM"));
            while (!(nm >= fz))
            {
                nm = nm + 1;
                E.S("adFrzNM", Adm.N(nm));
                foreach (var k in AD_TICKS) if (TickLv(k) == nm && TickRel(k)) E.XS(adFrzM, k, Adm.N(Bk(k)));
            }
            foreach (var k in AD_TICKS)
            {
                double vk = -1;
                bool dim = TickLv(k) <= nm;
                if (dim) { if (E.XHas(adFrzM, k) && (TickRel(k) || !AD_TICK_FRZ_1EO)) vk = Adm.D(E.X(adFrzM, k)); }
                else if (TickRel(k)) vk = Bk(k);
                if (vk >= g[3] && vk <= g[4]) { tv.Add(vk); tl.Add(Adm.T(K(AD_TICK_LAB, k))); th.Add(bl[3]); td.Add(dim); }
            }
            if (co >= g[3] && co <= g[4]) { tv.Add(co); tl.Add("CO"); th.Add(bl[4]); td.Add(false); }
            for (int i = 1; i < tv.Count; i++)
                for (int j = i; j >= 1; j--)
                    if (tv[j - 1] > tv[j])
                    {
                        double a = tv[j]; tv[j] = tv[j - 1]; tv[j - 1] = a;
                        string b = tl[j]; tl[j] = tl[j - 1]; tl[j - 1] = b;
                        double c = th[j]; th[j] = th[j - 1]; th[j - 1] = c;
                        bool d = td[j]; td[j] = td[j - 1]; td[j - 1] = d;
                    }
            var last = new double[] { -999, -999, -999 };
            for (int i = 0; i < Math.Min(tv.Count, 8); i++)
            {
                double x = BarX(g, tv[i]);
                BarFill(Slot("tk" + i), td[i] ? adFillDimS : adFillS);
                Bar(Slot("tk" + i), x - 0.5, g[2] - th[i], x + 0.5, g[2] + th[i]);
                double w = tl[i].Length * AD_TICK_CW;
                int rw = 2;
                for (int j = 2; j >= 0; j--) if (x - w / 2 > last[j] + bl[5]) rw = j;
                last[rw] = x + w / 2;
                Text(Slot("tl" + i), td[i] ? "<color=" + AD_DIM + ">" + tl[i] + "</color>" : tl[i], x, bl[rw], 2);
            }
        }

        // ---- adState's math on the hook's reads (adCsIn)
        AdSt State()
        {
            var st = new AdSt();
            double now = Adm.D(inp[0]);
            double met = 0;
            if (Adm.D(K(asc, "t_lo")) >= 0) met = now - Adm.D(K(asc, "t_lo"));
            string ph = Adm.T(K(asc, "phase"));
            st.met = met; st.ph = ph;
            st.s1 = Adm.SEq(ph, "PAD") || Adm.SEq(ph, "STAGE1");
            st.after = Adm.D(K(asc, "t_meco")) >= 0;
            st.vrel = Adm.D(inp[1]); st.vi = Adm.D(inp[2]); st.h = Adm.D(inp[3]); st.hdot = Adm.D(inp[4]);
            st.vh = 0;
            st.hasVl = Adm.B(inp[12]);
            if (st.hasVl)
            {
                st.vh = Adm.D(inp[13]);
                var vl = Ls(inp[14]); st.vl = new double[vl.Count];
                for (int i = 0; i < vl.Count; i++) st.vl[i] = Adm.D(vl[i]);
            }
            double fs = Adm.D(inp[9]), pk = Adm.D(inp[10]), fl = Adm.D(inp[11]);
            st.fsrb = fs; st.fsrb_pk = pk;
            st.g = (fs + fl) / (Adm.D(inp[5]) * Adm.D(inp[7]));
            st.keas = Math.Sqrt(2 * Adm.D(inp[6]) * Adm.D(inp[8]) * 1000 / AD_RHO0) / AD_KT;
            var h0 = Ls(E.G("adHist"));
            var hist = new ListValue();
            foreach (var o in h0) hist.Add(o);
            var smp = new ListValue();
            smp.Add(inp[0]); smp.Add(inp[1]); smp.Add(inp[2]); smp.Add(inp[3]); smp.Add(inp[4]);
            smp.Add(st.hasVl ? inp[13] : (Structure)ScalarValue.Create(0));
            hist.Add(smp);
            while (!(hist.Count <= 1 || now - Adm.D(((ListValue)hist[0])[0]) <= AD_HIST_S)) hist.RemoveAt(0);
            E.S("adHist", hist);
            var o0 = (ListValue)hist[0];
            double dt = now - Adm.D(o0[0]);
            st.vreld = 0; st.vid = 0; st.hdd = 0; st.vhd = 0;
            if (dt >= 1 && met > 0)
            {
                st.vreld = (st.vrel - Adm.D(o0[1])) / dt;
                st.vhd = (st.vh - Adm.D(o0[5])) / dt;
                st.vid = (st.vi - Adm.D(o0[2])) / dt;
                st.hdd = (st.hdot - Adm.D(o0[4])) / dt;
            }
            return st;
        }
        double[] Pred(AdSt st, double x0, double xd, double dt)
        {
            double x = x0 + xd * dt;
            double h = st.h + st.hdot * dt + 0.5 * st.hdd * dt * dt;
            return new[] { x / AD_FT, h / AD_FT / 1000 };
        }
        string Guid(AdSt st)
        {
            if (st.after)
            {
                string why = Adm.T(K(asc, "why"));
                if (Adm.SEq(why, "res")) return "MECO LOW LVL";
                if (Adm.SEq(why, "out")) return "MECO ENG OUT";
                return "MECO CUT";
            }
            if (Adm.SEq(st.ph, "PAD"))
            {
                if (Has(asc, "cd_txt")) { string cd = Adm.T(K(asc, "cd_txt")); if (cd != "") return cd; }
                return "READY";
            }
            if (!Adm.B(K(asc, "s2_on"))) return "OPEN LOOP";
            var g = Lx(K(asc, "g"));
            var p = Lx(K(g, "peg"));
            if (Adm.B(K(g, "S_MECO")))
            {
                if (Adm.D(K(g, "T_MECO")) >= 0) return "MECO SET";
                return "FINE COUNT";
            }
            return Adm.B(K(p, "SCONV")) ? "CONV" : "<color=" + AD_YELLOW + ">UNCONV " + Adm.T(K(p, "unconv")) + "</color>";
        }
        double Tgo(AdSt st)
        {
            if (st.after || !Adm.B(K(asc, "s2_on"))) return -1;
            var g = Lx(K(asc, "g"));
            if (Adm.B(K(g, "S_MECO")))
            {
                if (Adm.D(K(g, "T_MECO")) >= 0) return Math.Max(0, Adm.D(K(g, "T_MECO")) - st.met);
                if (Adm.D(K(g, "TGO_FC")) >= 0) return Adm.D(K(g, "TGO_FC"));
            }
            return Adm.D(K(Lx(K(g, "peg")), "TGO"));
        }
        string Roll(AdSt st)
        {
            if (Adm.SEq(st.ph, "PAD")) return "";
            if (st.s1)
            {
                if (!Adm.B(K(Lx(K(asc, "s1")), "clear")) || Adm.B(K(asc, "slew"))) return "ROLL PGM";
                return "HEADS DOWN";
            }
            if (Adm.D(K(asc, "t_roll")) < 0) return "HEADS DOWN";
            if (ASC_ROLL_RATE * (st.met - Adm.D(K(asc, "t_roll"))) < 180) return "ROLLING";
            return "HEADS UP";
        }
        internal static double[] RpyErr(Vector3d ff, Vector3d ft, Vector3d fs, Vector3d tf, Vector3d tt)
        {
            double a = Vector3d.Dot(tf, ft);
            double b = Vector3d.Dot(tf, fs);
            double c = Vector3d.Dot(tf, ff);
            double m = Math.Sqrt(a * a + b * b);
            double ang = Adm.Atan2(m, c);
            if (m < 0.000001 || c < -0.999999) return new[] { Adm.Atan2(Vector3d.Dot(tt, fs), Vector3d.Dot(tt, ft)), ang, 0 };
            Vector3d k = Vector3d.Cross(ff, tf);
            Vector3d tp = ft * c + Vector3d.Cross(k, ft) + k * (Vector3d.Dot(k, ft) / (1 + c));
            Vector3d sp = fs * c + Vector3d.Cross(k, fs) + k * (Vector3d.Dot(k, fs) / (1 + c));
            return new[] { Adm.Atan2(Vector3d.Dot(tt, sp), Vector3d.Dot(tt, tp)), ang * a / m, ang * b / m };
        }
        void Rpy(string key)
        {
            var g = Geo(key);
            double[] er = { 0, 0, 0 };
            if (Adm.B(inp[18])) er = RpyErr(vin(inp[15]), vin(inp[16]), vin(inp[17]), vin(inp[19]), vin(inp[20]));
            string[] ng = { "L", "D", "L" };
            string[] ps = { "R", "U", "R" };
            for (int i = 0; i <= 2; i++)
            {
                double ae = er[i];
                double n = Adm.Round(Math.Abs(ae));
                string s = " 00";
                if (n > 0) s = (ae >= 0 ? ps[i] : ng[i]) + (n < 10 ? "0" : "") + Adm.Num(Math.Min(n, 99));
                Text(Slot("r" + i), s, g[0], g[1 + i], 0);
            }
        }
        void Col(string key, string pre, string[] vals)
        {
            var g = Geo(key);
            for (int i = 0; i < vals.Length; i++) Text(Slot(pre + i), vals[i], g[0], g[1 + i], 1);
        }
        string Hilite(string s, string w)
        {
            var ws = s.Split(new[] { " " }, StringSplitOptions.None);
            int k = Adm.LIndexOf(ws, w);
            if (k < 0) return s;
            ws[k] = "<color=" + AD_YELLOW + ">" + ws[k] + "</color>";
            return string.Join(" ", ws);
        }
        string[] Lines(string[] md)
        {
            var lns = new[] { md[0], md[1], md[2] };
            if (Has(asc, "rl2_ln"))
            {
                string r2 = Adm.T(K(asc, "rl2_ln"));
                if (r2 != "" && Lx(K(asc, "rl")).Count > 0) lns[1] = r2;
            }
            bool two = false;
            if (Has(asc, "eo2_ln")) { string e2 = Adm.T(K(asc, "eo2_ln")); if (e2 != "") { lns[1] = e2; two = true; } }
            string sel = "";
            bool cnt = false;
            if (Has(asc, "abort"))
            {
                string ab = Adm.T(K(asc, "abort"));
                if (Adm.SEq(ab, "CONT")) cnt = true; else if (ab != "") sel = ab;
            }
            if (!two && !Adm.SEq(sel, "RTLS")) lns[1] = Rel2(sel, lns[1]);
            for (int i = 0; i <= 1; i++)
            {
                string w = sel;
                if (i == 1 && (cnt || (two && Adm.SEq(sel, "RTLS")))) w = lns[1];
                if (w != "" && (i == 0 || two)) lns[i] = Hilite(lns[i], w);
            }
            if (adOut.Count >= 3 && lns[2] != "") lns[2] = "<color=" + AD_YELLOW + ">" + lns[2] + "</color>";
            double fz = FrzLv();
            double nl = Adm.D(E.G("adFrzNL"));
            while (!(nl >= fz))
            {
                int ix = (int)nl;
                E.LS(adFrzL, ix, new StringValue(lns[ix].Replace("<color=" + AD_YELLOW + ">", "").Replace("</color>", "")));
                nl = nl + 1;
                E.S("adFrzNL", Adm.N(nl));
            }
            for (int i = 0; i < nl; i++)
            {
                string fl = Adm.T(E.L(adFrzL, i));
                lns[i] = fl == "" ? "" : "<color=" + AD_DIM + ">" + fl + "</color>";
            }
            return lns;
        }
        string Mode(string[] allowed)
        {
            if (Has(asc, "abort"))
            {
                string ab = Adm.T(K(asc, "abort"));
                foreach (var a in allowed) if (Adm.SEq(a, ab)) return ab.ToLower();
            }
            return "ascent";
        }

        // ---- the pages
        void Common(AdSt st, string pre)
        {
            var ck = Geo("clock_px");
            Text(Slot(pre + "met"), Clock(st.met), ck[0], ck[1] - AD_HDR_DY, 1);
            var ab = Geo("abt_px");
            if (!st.after)
            {
                var md = Lines(Modes(st.vi / AD_FT));
                for (int i = 0; i <= 2; i++) Text(Slot(pre + "ab" + i), md[i], ab[1], ab[2 + i], 0);
            }
            var mp = Geo("msg_px");
            int r0 = 0;
            string warn = Adm.T(E.Raw("adWarn"));
            if (warn != "") { Text(Slot(pre + "warn"), warn, mp[0], mp[1], 0); r0 = 1; }
            var msgs = Ls(E.Raw("adMsgs"));
            for (int i = 0; !(i + r0 > 2 || i >= msgs.Count); i++)
                Text(Slot(pre + "m" + (i + r0)), Adm.T(msgs[i]), mp[0], mp[1 + i + r0], 0);
        }

        void Traj1(AdSt st)
        {
            if (Adm.SEq(st.ph, "PAD")) SetBg("t1_launch"); else SetBg("t1_" + Mode(new[] { "RTLS", "TAL" }));
            var bg = Geo("bar1_px");
            Put(Slot("bar"), "bartri", BarX(bg, st.vi / AD_FT), bg[2]);
            if (!Adm.SEq(st.ph, "PAD")) Ticks(bg, -1);   // no marks before liftoff: at the pad they would be the nominal mass's for any payload
            var k = Geo("t1_keas_px");
            Put(Slot("ptr1"), "ewtri", k[0], ScaleY(k, st.keas));
            Rpy("t1_rpy_px");
            var p = Hold("veh", Field(1, st.vrel / AD_FT, st.h / AD_FT / 1000, true), Geo("t1_field_px"));
            Put(Slot("veh"), "veh", p[0], p[1]);
            if (st.met > 0)
            {
                var pr = Pred(st, st.vrel, st.vreld, Geo("pred_s")[0]);
                var pt = Field(1, pr[0], pr[1], false);
                if (pt != null && Fits("pred", pt, Geo("t1_field_px"))) Put(Slot("p1"), "pred", pt[0], pt[1]);
            }
            string pc = "";
            if (st.fsrb > 0 && st.fsrb < Geo("pclo")[0] * st.fsrb_pk) pc = "PC<" + Adm.Num(Geo("pclo")[1]);
            Col("t1_lr_px", "lr", new[] { Pl(Adm.D(K(asc, "kcmd"))), pc });
            Col("t1_col_px", "c", new[] { Fx(st.h / 1000, 1) + "K", Adm.Num(Adm.Round(st.vrel)), Sgn(st.hdot), Guid(st), Roll(st) });
        }

        void Traj2(AdSt st, ListValue tj)
        {
            SetBg("t2_" + Mode(new[] { "TAL", "ATO", "AOA" }));
            double vi = st.vi / AD_FT;
            var bg = Geo("bar2_px");
            Put(Slot("bar"), "bartri", BarX(bg, vi), bg[2]);
            Ticks(bg, Co());
            var k = Geo("t2_dhd_px");
            Put(Slot("ptr1"), "ewtri", k[0], ScaleY(k, st.hdot / AD_FT - Interp(Geo("hdnom"), vi)));
            var hp = Geo("t2_hdot_px");
            Text(Slot("hdot"), Sgn(st.hdot), hp[0], hp[1], 1);
            Rpy("t2_rpy_px");
            var p = Hold("veh", Field(2, vi, st.h / AD_FT / 1000, true), Geo("t2_field_px"));
            Put(Slot("veh"), "veh", p[0], p[1]);
            if (!st.after)
            {
                var ps = Geo("pred_s");
                for (int i = 1; i <= 2; i++)
                {
                    var pr = Pred(st, st.vi, st.vid, ps[i]);
                    var pt = Field(2, pr[0], pr[1], false);
                    if (pt != null && Fits("pred", pt, Geo("t2_field_px"))) Put(Slot("p" + i), "pred", pt[0], pt[1]);
                }
            }
            var gk = Geo("t2_g_px");
            Put(Slot("ptr2"), "ewtri", gk[0], ScaleY(gk, st.g));
            double tgo = Tgo(st);
            string pp = "";
            if (!st.after && Adm.D(K(asc, "et_full")) > 0) pp = Adm.Num(Adm.Round(100 * Adm.D(tj[3]) / Adm.D(K(asc, "et_full"))));
            string tm = "";
            if (st.after) tm = Mmss(Adm.D(K(asc, "t_meco"))); else if (tgo >= 0) tm = Mmss(st.met + tgo);
            Col("t2_lr_px", "lr", new[] { Pl(Adm.D(K(asc, "kcmd"))), pp, tm });
            bool drs = Has(asc, "drp") && !st.after;
            if (drs && Lx(K(asc, "cn")).Count > 0) drs = !Adm.B(K(Lx(K(asc, "cn")), "on"));
            if (drs)
            {
                var dr = Lx(K(asc, "drp"));
                if (Adm.B(K(dr, "ok")))
                {
                    var lr = Geo("t2_lr_px");
                    string dw = "DROOP";
                    string dn = Adm.Num(Adm.Round(Adm.D(K(dr, "PRED")) / 1000)) + "K";
                    if (Adm.B(K(dr, "S_CDROOP")))
                    {
                        dw = "<color=" + AD_YELLOW + ">" + dw + "</color>";
                        dn = "<color=" + AD_YELLOW + ">" + dn + "</color>";
                    }
                    Text(Slot("dr0"), dw, AD_DRP_X, 2 * lr[1] - lr[2], 0);
                    Text(Slot("dr1"), dn, lr[0], 2 * lr[1] - lr[2], 1);
                }
            }
            string ts = "";
            if (st.after) ts = "0:00"; else if (tgo >= 0) ts = Mmss(tgo);
            string ha = "", hpe = "";
            if (st.after) { ha = Adm.Num(Adm.Round(Adm.D(tj[0]) / 1000)) + "K"; hpe = Adm.Num(Adm.Round(Adm.D(tj[1]) / 1000)) + "K"; }
            double hm = ASC_MECO_H;
            double gm = ASC_GAMD;
            if (Adm.B(K(asc, "s2_on")))
            {
                var peg = Lx(K(Lx(K(asc, "g")), "peg"));
                hm = Adm.D(K(peg, "RDMAG")) - ASC_R; gm = Adm.D(K(peg, "GAMD"));
            }
            Col("t2_col_px", "c", new[] { ts, Guid(st), Roll(st), Adm.Num(Adm.Round(st.vi)), Fx(st.h / 1000, 1) + "K",
                Fx(hm / 1000, 1) + "K", Fx(gm, 2), ha, hpe });
        }

        bool TmSettle(string md, double t, double mc)
        {
            if (!AD_TM_WAIT) return mc >= 0;
            if (Adm.SEq(md, "fd") || Adm.SEq(md, "turn") || mc < 0)
            {
                E.XS(adTmS, "on", BooleanValue.False); E.XS(adTmS, "ok", Adm.N(-1)); E.XS(adTmS, "p", Adm.N(-1));
                return false;
            }
            if (Adm.D(E.X(adTmS, "p")) < 0) { E.XS(adTmS, "p", Adm.N(mc)); E.XS(adTmS, "t", Adm.N(t)); return Adm.B(E.X(adTmS, "on")); }
            if (t < Adm.D(E.X(adTmS, "t")) + 0.05) return Adm.B(E.X(adTmS, "on"));
            double dm = Math.Abs(mc - Adm.D(E.X(adTmS, "p")));
            if (Adm.B(E.X(adTmS, "on")))
            {
                if (dm > AD_TM_JUMP) { E.XS(adTmS, "on", BooleanValue.False); E.XS(adTmS, "ok", Adm.N(-1)); }
            }
            else if (dm / (t - Adm.D(E.X(adTmS, "t"))) <= AD_TM_DRIFT)
            {
                if (Adm.D(E.X(adTmS, "ok")) < 0) E.XS(adTmS, "ok", E.X(adTmS, "t"));
                if (t - Adm.D(E.X(adTmS, "ok")) >= AD_TM_HOLD) E.XS(adTmS, "on", BooleanValue.True);
            }
            else
            {
                E.XS(adTmS, "ok", Adm.N(-1));
            }
            E.XS(adTmS, "p", Adm.N(mc));
            E.XS(adTmS, "t", Adm.N(t));
            return Adm.B(E.X(adTmS, "on"));
        }

        static readonly Dictionary<string, string> RNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
            { "fd", "DISSIP" }, { "turn", "PPA" }, { "fb", "FLYBACK" }, { "fc", "FLYBACK" }, { "ppd", "PPD" }, { "m5", "5" } };

        void TrajR2(AdSt st, ListValue tj)
        {
            SetBg("r2_rtls");
            var rl = Lx(K(asc, "rl"));
            var g = Lx(K(asc, "g"));
            var vl = st.vl;
            double vh = st.vh / AD_FT;
            if (vh < 0)
            {
                var bg = Geo("r2_bar_px");
                Put(Slot("bar"), "bartri", BarX(bg, (vl[0] - vl[3]) / ASC_RTLS_A_MECO[1] / AD_NM), bg[2]);
            }
            Rpy("t2_rpy_px");
            var fg = Geo("r2_field_px");
            var p = Hold("veh", FieldG(fg, vh, st.h / AD_FT / 1000, true), fg);
            Put(Slot("veh"), "veh", p[0], p[1]);
            if (!st.after)
            {
                var ps = Geo("pred_r2");
                for (int i = 0; i <= 1; i++)
                {
                    var pr = Pred(st, st.vh, st.vhd, ps[i]);
                    var pt = FieldG(fg, pr[0], pr[1], false);
                    if (pt != null && Fits("pred", pt, fg)) Put(Slot("p" + (i + 1)), "pred", pt[0], pt[1]);
                }
            }
            var gk = Geo("r2_g_px");
            Put(Slot("ptr2"), "ewtri", gk[0], ScaleY(gk, st.g));
            string md = Adm.T(K(rl, "mode"));
            double tgo = -1;
            double dtp = Adm.D(tj[4]);
            if (!st.after)
            {
                double pegTgo = Adm.D(K(Lx(K(g, "peg")), "TGO"));
                if (Adm.SEq(md, "fd") || Adm.SEq(md, "turn")) tgo = Adm.D(K(rl, "DT_TURN")) + pegTgo + dtp;
                else if (Adm.SEq(md, "fb")) tgo = pegTgo + dtp;
                else if (Adm.SEq(md, "fc")) tgo = Math.Max(0, Adm.D(K(rl, "TP_hold")) - st.met) + dtp;
                else if (Adm.SEq(md, "m5")) tgo = Math.Max(0, Adm.D(K(rl, "m5_tgo")));
                else if (Adm.D(K(g, "T_MECO")) >= 0) tgo = Math.Max(0, Adm.D(K(g, "T_MECO")) - st.met);
                else if (Adm.D(K(rl, "tgo_co")) >= 0) tgo = Adm.D(K(rl, "tgo_co"));
            }
            string pp = "";
            if (!st.after && Adm.D(K(asc, "et_full")) > 0) pp = Adm.Num(Adm.Round(100 * Adm.D(tj[3]) / Adm.D(K(asc, "et_full"))));
            string tm = "";
            if (st.after) tm = Mmss(Adm.D(K(asc, "t_meco")));
            else if (TmSettle(md, st.met, tgo >= 0 ? st.met + tgo : -1)) tm = Mmss(st.met + tgo);
            Col("r2_lr_px", "lr", new[] { Pl(Adm.D(K(asc, "kcmd"))), pp, tm });
            string ts = "";
            if (st.after) ts = "0:00";
            else if (Adm.SEq(md, "fd"))
            {
                if (Has(rl, "tpa_on")) { if (Adm.B(K(rl, "tpa_on")) && Adm.D(K(rl, "tpa")) >= 0) ts = "PPA " + Mmss(Adm.D(K(rl, "tpa"))); }
            }
            else if (tgo >= 0) ts = Mmss(tgo);
            string mw = "MECO";
            if (!st.after) { string nm; if (RNames.TryGetValue(md, out nm)) mw = nm; else mw = md.ToUpper(); }
            Vector3d vs = vin(tj[2]);
            Vector3d ff = vin(inp[15]), ft = vin(inp[16]), fsv = vin(inp[17]);
            double al = 0, be = 0;
            if (vs.magnitude > 1)
            {
                al = Adm.Atan2(-Vector3d.Dot(vs, ft), Vector3d.Dot(vs, ff));
                be = Adm.Asin(Math.Max(-1, Math.Min(1, Vector3d.Dot(vs.normalized, fsv))));
            }
            Col("t2_col_px", "c", new[] { ts, Guid(st), mw, Adm.Num(Adm.Round(vl[0])), Fx(st.h / 1000, 1) + "K", Sgn(st.hdot),
                Adm.Num(Adm.Round(al)), Adm.Num(Adm.Round(be)), Adm.Num(Adm.Round(vl[2] / 1000)) + "K" });
        }

        void Eng(AdSt st, ListValue en)
        {
            var b = Geo("eng_bar_px");
            var vy = Geo("eng_val_px");
            double hw = AD_ENG_BAR_HW;
            double yb = AD_ENG_BAR_YB;
            var xs = Geo("eng_ssme_x");
            string[] ks = { "L", "C", "R" };
            for (int i = 0; i <= 2; i++)
            {
                double x = xs[i];
                double pl = 0;
                string s = "READY";
                var e = Ls(en[i]);
                if (Adm.B(e[0]))
                {
                    if (Has(adOut, ks[i])) s = "<color=" + AD_RED + ">OUT</color>";
                    else if (st.after) s = "SHDN";
                    else if (!Adm.B(e[1]) && Adm.SEq(st.ph, "PAD")) s = "READY";   // same rule as lib_ascdisp.ks
                    else if (!Adm.B(e[1]) || Adm.B(e[2])) s = "<color=" + AD_RED + ">OUT</color>";
                    else
                    {
                        s = "ON";
                        if (Adm.D(e[3]) > 0) pl = Adm.D(e[4]) / Adm.D(e[3]) * 100 / ASC_PL_TO_KSP;
                    }
                }
                if (pl >= b[3]) Bar(Slot("b" + i), x - hw, b[0] + (Math.Min(pl, b[4]) - b[3]) / (b[4] - b[3]) * (b[1] - b[0]), x + hw, yb);
                if (s == "ON") Text(Slot("v" + i), Pl(pl), x, vy[0], 2);
                Text(Slot("s" + i), s, x, vy[1], 2);
            }
            var sx = Geo("eng_srb_x");
            for (int i = 0; i <= 1; i++)
            {
                double x = sx[i];
                string s = "SEP";
                if (st.s1)
                {
                    s = Adm.SEq(st.ph, "PAD") ? "READY" : "BURN";
                    var e = Ls(en[3 + i]);
                    if (Adm.B(e[0]))
                    {
                        double pk = Adm.D(e[1]);
                        double thr = Adm.D(e[2]);
                        if (pk > 0 && thr > 0)
                        {
                            double f = thr / pk;
                            Bar(Slot("b" + (3 + i)), x - hw, b[0] + f * (b[1] - b[0]), x + hw, yb);
                            Text(Slot("v" + (3 + i)), Adm.Num(Adm.Round(100 * f)), x, vy[0], 2);
                        }
                    }
                }
                Text(Slot("s" + (3 + i)), s, x, vy[1], 2);
            }
            string lo = "", lh = "";
            if (Ls(K(asc, "ssme")).Count > 0 && !(st.after && st.met >= Adm.D(K(asc, "t_meco")) + AD_ET_SEP_S))
            {
                var cr = Ls(en[5]);
                for (int i = 0; i + 2 < cr.Count; i += 3)
                {
                    double cap = Adm.D(cr[i + 2]);
                    if (cap > 0)
                    {
                        if (Adm.T(cr[i]).Contains("Ox")) lo = Fx(100 * Adm.D(cr[i + 1]) / cap, 1);
                        else lh = Fx(100 * Adm.D(cr[i + 1]) / cap, 1);
                    }
                }
            }
            string om = "";
            var lf = Ls(en[6]);
            for (int i = 0; i + 1 < lf.Count; i += 2)
            {
                double cap = Adm.D(lf[i + 1]);
                if (cap > 0) om = Fx(100 * Adm.D(lf[i]) / cap, 1);
            }
            string gb = Adm.B(en[7]) ? "LOCKED" : "FREE";
            var lg = Geo("eng_list_px");
            string[] vals = { lo, lh, om, om, "", Adm.B(K(asc, "fc")) ? "ON" : "OFF", gb };
            for (int i = 0; i <= 6; i++) if (i != 4) Text(Slot("l" + i), vals[i], lg[0], lg[1 + i], 1);
        }

        // ADDRAW: one update of the page whose turn it is (adTick's body after its clock and adCyc)
        public void Draw(Lexicon a, ListValue reads)
        {
            Ops.Clear();
            asc = a; inp = reads;
            Load();
            for (int n = 1; n <= 3; n++) site[n] = Adm.T(inp[20 + n]);
            var st = State();
            var pg = Ls(inp[24]);
            if (Adm.Mod(adCyc, 2) == 0)
            {
                Eng(st, pg);
                Common(st, "e");
                Sweep(Ls(E.Raw("adAllE")));
            }
            else
            {
                if (st.s1) Traj1(st);
                else if (st.hasVl) TrajR2(st, pg);
                else Traj2(st, pg);
                Common(st, "");
                Sweep(Ls(E.Raw("adAll")));
            }
        }
    }
}
