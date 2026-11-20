// lib_taemdisp.ks's per-draw math (the TAEM pages VERT SIT / HORIZ SIT, MM 603, and the GRTLS's MM 602:
// tdTick's body with tdVs, tdHs, tdMsgRow, tdSweep, and tdGrTick's with tdGrPre and the MM 602 items, everything under
// them) in C#, line for line with kOS's semantics (trig in degrees, ROUND = Math.Round, MOD = %, MIN / MAX, FLOOR, ABS,
// SQRT, ^ = Math.Pow, numbers to text by kOS.Safe's own ScalarValue ToString, string '=' / '<>' and lexicon keys
// case-insensitive, :TRIM / :SUBSTRING / :LENGTH as kOS's StringValue).
// THE STATE STAYS KOS'S: every global the draw touches (tdFlash, tdCyc, tdLastPh, tdLastMsg, tdPrev, tdRate, tdZoomLatch,
// tdBgV, tdBgH, tdLog, tdLogDrawn, tdGrPh, tdGrPsha) and every widget slot's bookkeeping (sl[2..13]) is read from kOS at
// each call and written back (TdEnv) only after the whole call succeeded, so kOS's own code can take over at any draw.
// THE WIDGETS STAY KOS'S: every widget write the kOS code would make comes back as an op (widget, code, value), in the
// kOS code's order. THE GAME READS STAY KOS'S (the hook's tdCsIn: TIME, lib_land's ldDmShow / ldRwy, lib_vehicle's
// trims, lib_grtls's SS_ON / SS_NZ / GR_GRNZC1, and taemg_gtp for tdGrPre's range: the guidance's code): this file
// touches no Unity object and no widget. The small taemg geometry the pages call (taemg_drpred_of, taemg_rturn_of,
// taemg_xhac_of, taemg_norm180) is ported here on kOS's TG_* values, read each call (nothing retyped).
// THE 10 Hz DRAW: cyc = the draw of a new guidance cycle (the flash steps,
// the turn rate is measured, tdPrev is set); cyc FALSE = a redraw between two cycles (the vehicle now, the cycle's tg).
// Everything that can move between cycles does: the flash steps at every draw (FlashStep; the flashes at 5 Hz), VERT SIT's range / energies and HORIZ SIT's GSI / RANGE moved on
// between the cycles (EnNow, tdEnS) -- lib_taemdisp's tdFlashStep / tdEnNow.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class TdRef<T> : IEqualityComparer<T> where T : class
    {
        public bool Equals(T a, T b) { return ReferenceEquals(a, b); }
        public int GetHashCode(T o) { return System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(o); }
    }

    // the kOS side: globals by name, list elements; writes captured (Commit applies them);
    // reads see the captured writes first
    public class TdEnv
    {
        readonly kOS.Safe.Execution.ICpu cpu;
        public Dictionary<string, Structure> Gw = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<ListValue, Dictionary<int, Structure>> Lw = new Dictionary<ListValue, Dictionary<int, Structure>>(new TdRef<ListValue>());
        public TdEnv(kOS.Safe.Execution.ICpu c) { cpu = c; }
        public void Clear() { Gw.Clear(); Lw.Clear(); }
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
        public void Commit()
        {
            foreach (var kv in Lw) foreach (var kv2 in kv.Value) kv.Key[kv2.Key] = kv2.Value;
            foreach (var kv in Gw) cpu.SetGlobal("$" + kv.Key, kv.Value);
            Clear();
        }
    }

    // kOS's math and text, as kOS.Safe does it
    public static class Tdm
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
        public static double Sin(double x) { return Math.Sin(x * Math.PI / 180.0); }
        public static double Cos(double x) { return Math.Cos(x * Math.PI / 180.0); }
        public static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        public static double Round(double x) { return Math.Round(x); }
        public static double Round(double x, int n) { return Math.Round(x, n); }
        public static double Mod(double a, double b) { return a % b; }
        public static string Num(double x) { return ScalarValue.Create(x).ToString(); }
        public static ScalarValue N(double x) { return ScalarValue.Create(x); }
    }

    // a TAEM state as tdTick reads it: kOS's tg lexicon, or tdGrTick's copy (gr["tg"]:COPY with its five keys set)
    public class TdTg
    {
        readonly Lexicon b;
        readonly Dictionary<string, Structure> o = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase);
        public TdTg(Lexicon lx) { b = lx; }
        public void Set(string k, Structure v) { o[k] = v; }
        public bool Has(string k) { return o.ContainsKey(k) || b.ContainsKey(new StringValue(k)); }
        public Structure this[string k]
        {
            get
            {
                Structure v; if (o.TryGetValue(k, out v)) return v;
                var key = new StringValue(k);
                if (!b.ContainsKey(key)) throw new Exception("tg has no key " + k);
                return b[key];
            }
        }
        public double N(string k) { return Tdm.D(this[k]); }
        public bool B(string k) { return Tdm.B(this[k]); }
        public string S(string k) { return Tdm.T(this[k]); }
    }

    public class TdCalc
    {
        public const int OP_TEXT = 0, OP_IMAGE = 1, OP_WIDTH = 2, OP_HEIGHT = 3, OP_MH = 4, OP_MV = 5, OP_ALIGN = 6, OP_BG = 7;
        public TdEnv E;
        public List<Structure> Ops = new List<Structure>();

        // per call: kOS's constants and tables (read, never retyped)
        double TD_FIT_IN;
        double TD_OFF_X, TD_OFF_Y, TD_IMG_DY, TD_TXT_DY, TD_FLOW_PX, TD_TXT_W, TD_HAC_RMIN, TD_HAC_RMAX, TD_FT, TD_NM, TD_PSF, TD_SB_PCT,
            TD_BAR_SHOW_S, TD_BAR_MOVE_S, TD_TTH_BLEND_S, TD_TTH_RK, TG_GO, TD_HS_TTH_Z3, TD_HACD_L, TD_HACD_NO, TD_HACD_N,
            TD_HS_OUT, TD_HS_ZMIN, tdSbCap, tdSbCapM;
        // the switch, the vehicle's place, the runway dashes
        bool TD_TRKUP;
        double TD_TU_BY, TD_TU_IN, TD_CLD_P, TD_CLD_N, TD_RWD_L, TD_RWS_L, TD_RW_N, TD_RW_STK, TD_RW_DEF;
        double rwyLen;                          // the hook's [21]: ldRwy's length (m)
        double[] tuG = new double[7];           // tdTuG: vehicle x, y (km), cos, sin of the track, the bug's page x, y, px per km
        string TD_DIR, TD_GR_DIR, TD_GR_HS_BLUE;
        double TG_IPH_STURN, TG_IPH_ACQ, TG_RMINST, TG_PSSTRN, TG_STURN_DELTA, TG_DM_T_HAC_MEP, TG_DM_T_HAC_STRT, TG_RMOH,
            TG_XALI_X, TG_R1, TG_X_AIM, TG_H_HAC_NEP, TG_H_HAC_MEP, TG_TGGS, TG_P2TRNC1;
        Lexicon tdGeo, tdSpr, tdGr, tdSV, tdSH, tdGS;
        ListValue tdAll, tdLogSl;
        Structure tdBoxV, tdBoxH;
        double tdMm, tdT0, tdMet0;
        // the draw's state (kOS's globals; written through E.S)
        bool tdFlash;
        bool lvT = true, lvB = true;            // The windows whose GPC lives (inp[23] TOP = VERT SIT, inp[24] BOT = HORIZ SIT): a dead / frozen one is not drawn and not swept (as lib_taemdisp tdTickK / tdGrPre)
        bool gdl;                               // SW 02 GUIDANCE LOST for the phase flown (inp[22]): the guidance-fed marks, box, bar and readouts blank as lib_taemdisp tdTickK does
        double tdCyc;
        Structure tdCycS;
        ListValue tdLog;
        // the hook's reads
        double now;
        bool cyc;
        bool hasDm, hasRwy;
        Structure dmS, rwyS;
        static readonly string[] Phs = { "S-TURN", "ACQ", "HDG", "PRFNL" };

        public TdCalc(TdEnv e) { E = e; }

        double GD(string n) { return Tdm.D(E.Raw(n)); }
        string GS(string n) { return Tdm.T(E.Raw(n)); }
        static Lexicon Lx(Structure s) { var l = s as Lexicon; if (l == null) throw new Exception("not a LEXICON"); return l; }
        static ListValue Ls(Structure s) { var l = s as ListValue; if (l == null) throw new Exception("not a LIST"); return l; }
        static Structure K(Lexicon x, string k)
        {
            var key = new StringValue(k);
            if (!x.ContainsKey(key)) throw new Exception("no key " + k);
            return x[key];
        }
        static bool Has(Lexicon x, string k) { return x.ContainsKey(new StringValue(k)); }
        static double KN(Lexicon x, string k) { return Tdm.D(K(x, k)); }
        double[] Geo(string k)
        {
            var l = Ls(K(tdGeo, k));
            var r = new double[l.Count]; for (int i = 0; i < l.Count; i++) r[i] = Tdm.D(l[i]); return r;
        }
        double[] GrT(string k)
        {
            var l = Ls(K(tdGr, k));
            var r = new double[l.Count]; for (int i = 0; i < l.Count; i++) r[i] = Tdm.D(l[i]); return r;
        }
        ListValue SV(string n) { return Ls(K(tdSV, n)); }
        ListValue SH(string n) { return Ls(K(tdSH, n)); }
        ListValue SG(string n) { return Ls(K(tdGS, n)); }

        public void Load()
        {
            TD_OFF_X = GD("TD_OFF_X"); TD_OFF_Y = GD("TD_OFF_Y"); TD_IMG_DY = GD("TD_IMG_DY"); TD_TXT_DY = GD("TD_TXT_DY");
            TD_FIT_IN = GD("TD_FIT_IN"); tdSbCap = GD("tdSbCap"); tdSbCapM = GD("tdSbCapM");
            TD_FLOW_PX = GD("TD_FLOW_PX"); TD_TXT_W = GD("TD_TXT_W"); TD_HAC_RMIN = GD("TD_HAC_RMIN"); TD_HAC_RMAX = GD("TD_HAC_RMAX");
            TD_FT = GD("TD_FT"); TD_NM = GD("TD_NM"); TD_PSF = GD("TD_PSF"); TD_SB_PCT = GD("TD_SB_PCT"); TD_BAR_SHOW_S = GD("TD_BAR_SHOW_S");
            TD_BAR_MOVE_S = GD("TD_BAR_MOVE_S"); TD_TTH_BLEND_S = GD("TD_TTH_BLEND_S"); TD_TTH_RK = GD("TD_TTH_RK");
            TG_GO = GD("TG_GO"); TD_HS_TTH_Z3 = GD("TD_HS_TTH_Z3");
            TD_HACD_L = GD("TD_HACD_L"); TD_HACD_NO = GD("TD_HACD_NO"); TD_HACD_N = GD("TD_HACD_N");
            TD_HS_OUT = GD("TD_HS_OUT"); TD_HS_ZMIN = GD("TD_HS_ZMIN");
            TD_TRKUP = Tdm.B(E.Raw("TD_TRKUP")); TD_TU_BY = GD("TD_TU_BY"); TD_TU_IN = GD("TD_TU_IN"); TD_CLD_P = GD("TD_CLD_P");
            TD_CLD_N = GD("TD_CLD_N"); TD_RWD_L = GD("TD_RWD_L"); TD_RWS_L = GD("TD_RWS_L"); TD_RW_N = GD("TD_RW_N");
            TD_RW_STK = GD("TD_RW_STK"); TD_RW_DEF = GD("TD_RW_DEF");
            TD_DIR = GS("TD_DIR"); TD_GR_DIR = GS("TD_GR_DIR"); TD_GR_HS_BLUE = GS("TD_GR_HS_BLUE");
            TG_IPH_STURN = GD("TG_IPH_STURN"); TG_IPH_ACQ = GD("TG_IPH_ACQ"); TG_RMINST = GD("TG_RMINST"); TG_PSSTRN = GD("TG_PSSTRN");
            TG_STURN_DELTA = GD("TG_STURN_DELTA"); TG_DM_T_HAC_MEP = GD("TG_DM_T_HAC_MEP"); TG_DM_T_HAC_STRT = GD("TG_DM_T_HAC_STRT");
            TG_RMOH = GD("TG_RMOH"); TG_XALI_X = GD("TG_XALI_X"); TG_R1 = GD("TG_R1"); TG_X_AIM = GD("TG_X_AIM");
            TG_H_HAC_NEP = GD("TG_H_HAC_NEP"); TG_H_HAC_MEP = GD("TG_H_HAC_MEP"); TG_TGGS = GD("TG_TGGS"); TG_P2TRNC1 = GD("TG_P2TRNC1");
            tdGeo = Lx(E.Raw("tdGeo")); tdSpr = Lx(E.Raw("tdSpr")); tdGr = Lx(E.Raw("tdGr"));
            tdSV = Lx(E.Raw("tdSV")); tdSH = Lx(E.Raw("tdSH")); tdGS = Lx(E.Raw("tdGS"));
            tdAll = Ls(E.Raw("tdAll")); tdLogSl = Ls(E.Raw("tdLogSl"));
            tdBoxV = E.Raw("tdBoxV"); tdBoxH = E.Raw("tdBoxH");
            tdMm = GD("tdMm"); tdT0 = GD("tdT0"); tdMet0 = GD("tdMet0");
            tdFlash = Tdm.B(E.Raw("tdFlash"));
            tdCycS = E.Raw("tdCyc"); tdCyc = Tdm.D(tdCycS);
            tdLog = Ls(E.Raw("tdLog"));
        }

        // TDSETUP: everything a draw reads is there (a missing name throws here, once, and kOS keeps drawing)
        public void Setup()
        {
            Load();
            foreach (var k in new[] { "msg_row_px", "clock_px", "vs_field_px", "vs1_km", "vs2_km", "vs0_km", "hs-1_km", "hs0_km", "hs_field_px", "vs_readout_px",
                "vs_strip_px", "vs_switch_km", "vs_label_px", "hs_zoom_in", "hs1_km", "hs2_km", "hs3_km", "hs_bar_px", "hs_gsi_px",
                "hs_readout_px", "log_px" }) Geo(k);
            foreach (var k in new[] { "am_box_px", "am_mach", "am_alpha", "am_qlim" }) GrT(k);
            foreach (var k in new[] { "met", "bug", "ebox", "ewtri", "ewarr", "mep", "stn", "albox", "r0", "r6", "ph", "zm", "al", "stnl",
                "mepl", "trml" }) SV(k);
            foreach (var k in new[] { "met", "bug", "hac", "p1", "p2", "p3", "bar", "gsi", "r0", "r5", "ph", "zm", "al", "b0", "b1", "b2",
                "log0", "log12" }) SH(k);
            SH("hd" + Tdm.Num(TD_HACD_N - 1));
            SH("cl0"); SH("cl" + Tdm.Num(TD_CLD_N - 1)); SH("rw0"); SH("rw" + Tdm.Num(TD_RW_N - 1));
            foreach (var k in new[] { "am", "nzv", "nzi", "bail", "ecal" }) SG(k);
            foreach (var k in new[] { "pred", "ewtri", "ebox", "stn", "mep", "ewarr", "bartri", "gsi", "grblank", "vsbug_p00", "hacd_00",
                "cld_00", "rwd_00", "rws_00", "hsbug_000" })
                if (!Has(tdSpr, k)) throw new Exception("no sprite " + k);
            Lx(E.Raw("tdPrev")); Lx(E.Raw("tdTh")); Lx(E.Raw("tdEnS"));
            E.Raw("tdRate"); E.Raw("tdRtT"); E.Raw("tdZoomLatch"); E.Raw("tdBgV"); E.Raw("tdBgH"); E.Raw("tdLogDrawn"); E.Raw("tdLastPh");
            E.Raw("tdLastMsg"); E.Raw("tdGrPh"); E.Raw("tdGrPsha"); E.Raw("tdHdKey"); E.Raw("tdHdUsed");
        }

        void Op(Structure w, int code, Structure v) { Ops.Add(w); Ops.Add(ScalarValue.Create(code)); Ops.Add(v); }

        // ---- the slots (tdImgSlot / tdTxtSlot's 14 fields: widget, flow index, content, x, y, SHOWN, cycle, align, width,
        //      font (0 = an image), the row's own px lower, the last call's x, y, align)
        void SlotOn(ListValue sl)
        {
            E.LS(sl, 6, tdCycS);
            if (!Tdm.B(E.L(sl, 5)))
            {
                if (Tdm.D(E.L(sl, 9)) == 0)
                {
                    string c = Tdm.T(E.L(sl, 2));
                    if (!Tdm.SEq(c, "")) Op(sl[0], OP_IMAGE, Ls(K(tdSpr, c))[0]);
                }
                else Op(sl[0], OP_TEXT, new StringValue(Bd(sl, Tdm.T(E.L(sl, 2)))));
                E.LS(sl, 5, BooleanValue.True);
            }
        }
        void SlotOff(ListValue sl)
        {
            if (Tdm.B(E.L(sl, 5)))
            {
                if (Tdm.D(E.L(sl, 9)) == 0) Op(sl[0], OP_IMAGE, new StringValue(TD_GR_DIR + "grblank.png"));
                else Op(sl[0], OP_TEXT, new StringValue(" "));
                E.LS(sl, 5, BooleanValue.False);
            }
        }
        void Put(ListValue sl, string nm, double x, double y)
        {
            if (x == Tdm.D(E.L(sl, 11)) && y == Tdm.D(E.L(sl, 12)) && Tdm.SEq(nm, Tdm.T(E.L(sl, 2))) && !Tdm.SEq(nm, ""))
            { SlotOn(sl); return; }
            if (Tdm.SEq(nm, "") || !Has(tdSpr, nm)) { SlotOff(sl); return; }
            var sp = Ls(K(tdSpr, nm));
            if (!Tdm.SEq(Tdm.T(E.L(sl, 2)), nm))
            {
                Op(sl[0], OP_IMAGE, sp[0]);
                Op(sl[0], OP_WIDTH, sp[1]);
                Op(sl[0], OP_HEIGHT, sp[2]);
                E.LS(sl, 2, new StringValue(nm));
            }
            double xx = Tdm.Round(x - Tdm.D(sp[3]));
            double yy = Tdm.Round(y - Tdm.D(sp[4]));
            if (xx != Tdm.D(E.L(sl, 3)))        // only the margin that moved
            {
                Op(sl[0], OP_MH, Tdm.N(Math.Max(0, xx + TD_OFF_X)));
                E.LS(sl, 3, Tdm.N(xx));
            }
            if (yy != Tdm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MV, Tdm.N(Math.Max(0, yy + TD_OFF_Y - TD_IMG_DY - Tdm.D(sl[1]) * TD_FLOW_PX)));
                E.LS(sl, 4, Tdm.N(yy));
            }
            E.LS(sl, 11, Tdm.N(x)); E.LS(sl, 12, Tdm.N(y));
            SlotOn(sl);
        }
        // a text slot's string: in <b> unless the slot is in the page face (lib_taemdisp tdTxtSlot's bd, sl[14])
        string Bd(ListValue sl, string s) { return Tdm.B(E.L(sl, 14)) ? "<b>" + s + "</b>" : s; }
        void Text(ListValue sl, string s, double x, double y, double align)
        {
            if (Tdm.SEq(s, "")) { SlotOff(sl); return; }
            if (x == Tdm.D(E.L(sl, 11)) && y == Tdm.D(E.L(sl, 12)) && align == Tdm.D(E.L(sl, 13)) && Tdm.SEq(s, Tdm.T(E.L(sl, 2))))
            { SlotOn(sl); return; }
            if (!Tdm.SEq(Tdm.T(E.L(sl, 2)), s)) { Op(sl[0], OP_TEXT, new StringValue(Bd(sl, s))); E.LS(sl, 2, new StringValue(s)); }
            double w = TD_TXT_W;
            double xx = Tdm.Round(x);
            string al = "LEFT";
            if (align == 1) { w = Math.Max(1, Math.Min(TD_TXT_W, xx)); xx = xx - w; al = "RIGHT"; }
            else if (align == 2) { w = Math.Max(2, Math.Min(TD_TXT_W, 2 * xx)); xx = Tdm.Round(x - w / 2); al = "CENTER"; }
            if (!Tdm.SEq(Tdm.T(E.L(sl, 7)), al)) { Op(sl[0], OP_ALIGN, new StringValue(al)); E.LS(sl, 7, new StringValue(al)); }
            if (Tdm.D(E.L(sl, 8)) != w) { Op(sl[0], OP_WIDTH, Tdm.N(w)); E.LS(sl, 8, Tdm.N(w)); }
            double yy = Tdm.Round(y - Tdm.D(E.L(sl, 9)) * 0.7);
            if (xx != Tdm.D(E.L(sl, 3)) || yy != Tdm.D(E.L(sl, 4)))
            {
                Op(sl[0], OP_MH, Tdm.N(Math.Max(0, xx + TD_OFF_X)));
                Op(sl[0], OP_MV, Tdm.N(Math.Max(0, Tdm.Round(yy + TD_OFF_Y - TD_TXT_DY + Tdm.D(E.L(sl, 10)) - Tdm.D(sl[1]) * TD_FLOW_PX))));
                E.LS(sl, 3, Tdm.N(xx)); E.LS(sl, 4, Tdm.N(yy));
            }
            E.LS(sl, 11, Tdm.N(x)); E.LS(sl, 12, Tdm.N(y)); E.LS(sl, 13, Tdm.N(align));
            SlotOn(sl);
        }
        void Sweep()
        {
            foreach (var o in tdAll)
            {
                var sl = Ls(o);
                if (Tdm.B(E.L(sl, 5))) { if (Tdm.D(E.L(sl, 6)) != tdCyc) SlotOff(sl); }
            }
        }
        // lib_taemdisp tdSweepW: the live windows' slots only (a frozen / dead one keeps what it shows); tdAll when both live
        void SweepW()
        {
            if (lvT && lvB) { Sweep(); return; }
            if (lvT) foreach (var v in tdSV.Values) { var sl = Ls(v); if (Tdm.B(E.L(sl, 5)) && Tdm.D(E.L(sl, 6)) != tdCyc) SlotOff(sl); }
            if (lvB) foreach (var v in tdSH.Values) { var sl = Ls(v); if (Tdm.B(E.L(sl, 5)) && Tdm.D(E.L(sl, 6)) != tdCyc) SlotOff(sl); }
        }
        void BgV(string bg)
        {
            if (!Tdm.SEq(bg, Tdm.T(E.G("tdBgV")))) { var v = new StringValue(bg); Op(tdBoxV, OP_BG, v); E.S("tdBgV", v); }
        }
        void BgH(string bg)
        {
            if (!Tdm.SEq(bg, Tdm.T(E.G("tdBgH")))) { var v = new StringValue(bg); Op(tdBoxH, OP_BG, v); E.S("tdBgH", v); }
        }
        void SetFlash(bool f) { tdFlash = f; E.S("tdFlash", f ? BooleanValue.True : BooleanValue.False); }
        // lib_taemdisp's tdFlashStep: the flash steps at every draw
        // even 5 Hz flashing: while the C# draws live (lib_taemdisp's tdFlashClk) the TD_DT_CS
        // grid slot's parity at the draw (tdFlashStep); on the draw's real time (tdRtT, uiRt), not `now`
        void FlashStep()
        {
            if (Tdm.B(E.Raw("tdFlashClk"))) SetFlash(Tdm.Mod(Math.Floor((Tdm.D(E.Raw("tdRtT")) + 0.005) / GD("TD_DT_CS")), 2) == 0);
            else SetFlash(!tdFlash);
        }
        // lib_taemdisp's tdEnNow: { drpred, en, en_of_dr - href, eow, href } now
        double[] EnNow(TdTg tg, Lexicon st)
        {
            var s = Lx(E.G("tdEnS"));
            bool has = Has(s, "t");
            if (cyc)
            {
                double d = tg.N("drpred"), en = tg.N("en"), eh = tg.N("en_of_dr") - tg.N("href"), hr = tg.N("href");
                double s0 = 0, s1 = 0, s2 = 0;
                if (has)
                {
                    double dd = d - KN(s, "d");
                    if (Math.Abs(dd) > 1 && now - KN(s, "t") < 5)
                    {
                        s0 = Math.Max(-2, Math.Min(2, (en - KN(s, "en")) / dd));
                        s1 = Math.Max(-2, Math.Min(2, (eh - KN(s, "eh")) / dd));
                        s2 = Math.Max(-2, Math.Min(2, (hr - KN(s, "hr")) / dd));
                    }
                }
                var n = new Lexicon();
                n[new StringValue("t")] = Tdm.N(now);
                n[new StringValue("d")] = Tdm.N(d);
                n[new StringValue("en")] = Tdm.N(en);
                n[new StringValue("eh")] = Tdm.N(eh);
                n[new StringValue("hr")] = Tdm.N(hr);
                n[new StringValue("sen")] = Tdm.N(s0);
                n[new StringValue("seh")] = Tdm.N(s1);
                n[new StringValue("shr")] = Tdm.N(s2);
                E.S("tdEnS", n);
                return new[] { d, en, eh, tg.N("eow"), hr };
            }
            if (!has || now - KN(s, "t") > 5)
                return new[] { tg.N("drpred"), tg.N("en"), tg.N("en_of_dr") - tg.N("href"), tg.N("eow"), tg.N("href") };
            double dm = 0 - KN(st, "vh") * Math.Max(0, Math.Min(2, now - KN(s, "t")));
            double ew = KN(st, "h") + Math.Pow(KN(st, "surfv"), 2) / (2 * TG_GO);
            if (tg.Has("ecompk")) ew += tg.N("ecompk") * ew * KN(st, "hdot");   // the GRTLS's ECAL phugoid term
            return new[] { KN(s, "d") + dm, KN(s, "en") + KN(s, "sen") * dm, KN(s, "eh") + KN(s, "seh") * dm,
                ew, KN(s, "hr") + KN(s, "shr") * dm };
        }
        void CycUp() { tdCyc = tdCyc + 1; tdCycS = Tdm.N(tdCyc); E.S("tdCyc", tdCycS); }
        // the HAC bar's time at the estimate's own rate, the cycle's step blended out (lib_taemdisp tdTthNow)
        double TthNow(double est)
        {
            var th = Lx(E.G("tdTh"));
            bool has = Has(th, "t");
            if (!has || (cyc && now > KN(th, "t") + 0.05))
            {
                double rate = 1, off = 0;
                if (has && now - KN(th, "t") < 10)
                {
                    double dt = now - KN(th, "t");
                    rate = KN(th, "rate") + TD_TTH_RK * (Math.Max(-0.5, Math.Min(1.5, (KN(th, "est") - est) / dt)) - KN(th, "rate"));
                    off = TthAt(th, dt) - est;
                    if (Math.Abs(off) >= 30) off = 0;
                }
                th = new Lexicon();
                th[new StringValue("t")] = Tdm.N(now);
                th[new StringValue("est")] = Tdm.N(est);
                th[new StringValue("rate")] = Tdm.N(rate);
                th[new StringValue("off")] = Tdm.N(off);
                E.S("tdTh", th);
            }
            return TthAt(th, now - KN(th, "t"));
        }
        double TthAt(Lexicon th, double el)
        {
            return KN(th, "est") - KN(th, "rate") * el + KN(th, "off") * Math.Max(0, 1 - el / TD_TTH_BLEND_S);
        }

        void SetPrev(Structure psd)
        {
            var p = new Lexicon();
            p[new StringValue("psd")] = psd;
            p[new StringValue("t")] = Tdm.N(now);
            E.S("tdPrev", p);
        }

        // ---- taemg's geometry (taemg.ks, the same expressions)
        double Norm180(double x) { while (!(x <= 180.0)) x = x - 360.0; while (!(x > -180.0)) x = x + 360.0; return x; }
        double XhacOf(bool nep) { double h = nep ? TG_H_HAC_NEP : TG_H_HAC_MEP; return TG_X_AIM - h / TG_TGGS; }
        double DrpredOf(double rpred) { return rpred + TG_XALI_X; }
        double RturnOf(double psha, double rf, double r2) { return rf + TG_R1 * psha + r2 * psha * psha; }

        // ---- lib_taemdisp's helpers
        void LogEvent(string s)
        {
            double met = now - tdT0;
            double mm = Math.Floor(met / 60);
            double ss = Math.Floor(Tdm.Mod(met, 60));
            string e = (mm < 10 ? "0" : "") + Tdm.Num(mm) + ":" + (ss < 10 ? "0" : "") + Tdm.Num(ss) + " " + s.Substring(0, Math.Min(s.Length, 22));
            var nl = new ListValue();
            nl.Add(new StringValue(e));
            foreach (var o in tdLog) nl.Add(o);
            tdLog = nl;
            E.S("tdLog", nl);
        }
        double[] KmPx(double k, double xkm, double ykm)
        {
            var f = Geo("vs_field_px");
            var a = Geo("vs" + Tdm.Num(k) + "_km");
            double fx = (xkm - a[0]) / (a[1] - a[0]);
            double fy = (ykm - a[2]) / (a[3] - a[2]);
            return new[] { f[0] + f[2] * fx, f[1] + f[3] * (1 - fy) };
        }
        bool InVs(double k, double xkm, double ykm)
        {
            var a = Geo("vs" + Tdm.Num(k) + "_km");
            return xkm >= a[0] && xkm <= a[1] && ykm >= a[2] && ykm <= a[3];
        }
        // lib_taemdisp tdFits (the sprite nm at (x, y), where Put draws it, wholly inside b less TD_FIT_IN)
        bool Fits(string nm, double x, double y, double[] b)
        {
            if (!Has(tdSpr, nm)) return false;
            var sp = Ls(K(tdSpr, nm));
            double l = Tdm.Round(x - Tdm.D(sp[3]));
            double t = Tdm.Round(y - Tdm.D(sp[4]));
            return l >= b[0] + TD_FIT_IN && l + Tdm.D(sp[1]) <= b[0] + b[2] - TD_FIT_IN && t >= b[1] + TD_FIT_IN
                && t + Tdm.D(sp[2]) <= b[1] + b[3] - TD_FIT_IN;
        }
        bool VsBugLeft(string nm, double x)
        {
            if (!Has(tdSpr, nm)) return false;
            var sp = Ls(K(tdSpr, nm));
            return x - Tdm.D(sp[3]) + Tdm.D(sp[1]) < Geo("vs_readout_px")[0];
        }
        // left of the labels and, on the GRTLS pages (MM 602), clear of the alpha / Mach box (lib_taemdisp tdVsShow)
        bool VsShow(string nm, double x, double y)
        {
            if (!Fits(nm, x, y, Geo("vs_field_px"))) return false;
            if (!VsBugLeft(nm, x)) return false;
            if (tdMm != 602 || !Has(tdGr, "am_box_px")) return true;
            var sp = Ls(K(tdSpr, nm));
            var b = GrT("am_box_px");
            double l = x - Tdm.D(sp[3]), t = y - Tdm.D(sp[4]);
            return !(l < b[0] + b[2] && l + Tdm.D(sp[1]) > b[0] && t < b[1] + b[3] && t + Tdm.D(sp[2]) > b[1]);
        }
        double EwY(double val)
        {
            var s = Geo("vs_strip_px");
            double f = Math.Max(0, Math.Min(1, (val - s[3]) / (s[4] - s[3])));
            return s[2] + (s[1] - s[2]) * f;
        }
        static string BugName(double gi)
        {
            return "vsbug_" + (gi < 0 ? "m" : "p") + (Math.Abs(gi) < 10 ? "0" : "") + Tdm.Num(Math.Abs(gi));
        }
        static string HsBugName(double hdg)
        {
            return "hsbug_" + (hdg < 10 ? "00" : (hdg < 100 ? "0" : "")) + Tdm.Num(hdg);
        }
        string Clock()
        {
            double a = Math.Floor(Math.Max(0, now - tdMet0));
            return Tdm.Num(Math.Floor(a / 86400)).PadLeft(3, '0') + "/" + Tdm.Num(Math.Floor(Tdm.Mod(a, 86400) / 3600)).PadLeft(2, '0') + ":"
                + Tdm.Num(Math.Floor(Tdm.Mod(a, 3600) / 60)).PadLeft(2, '0') + ":" + Tdm.Num(Tdm.Mod(a, 60)).PadLeft(2, '0');
        }
        void LogRows()
        {
            int nlg = Math.Min(13, tdLog.Count);
            if (tdLog.Count != Tdm.D(E.G("tdLogDrawn")))
            {
                var lg = Geo("log_px");
                for (int j = 0; j < nlg; j++) Text(Ls(tdLogSl[j]), Tdm.T(tdLog[j]), lg[0], lg[1] + j * lg[2], 0);
                E.S("tdLogDrawn", Tdm.N(tdLog.Count));
            }
            else
            {
                for (int j = 0; j < nlg; j++) SlotOn(Ls(tdLogSl[j]));
            }
        }
        string TrimTxt(ListValue inp)
        {
            if (!Tdm.B(inp[10])) return "";
            double pt = Tdm.D(inp[11]);
            string t = (pt <= 0 ? "U" : "D") + Tdm.Num(Tdm.Round(Math.Abs(pt), 1));
            if (Tdm.B(inp[12]) && Math.Abs(Tdm.D(inp[13])) > 0.05)
            {
                double et = Tdm.D(inp[13]);
                string es = "+" + Tdm.Num(Tdm.Round(Math.Abs(et), 1));
                if (t.Length + es.Length > 8) es = "+" + Tdm.Num(Tdm.Round(Math.Abs(et)));
                t = t + es;
            }
            return t;
        }
        string RwyName()
        {
            if (!hasRwy) throw new Exception("ldRwy has no name");
            return Tdm.T(rwyS);
        }

        // ---- tdMsgRow
        void MsgRow(Func<string, ListValue> sl, TdTg tg, string msg)
        {
            var mr = Geo("msg_row_px");
            Text(sl("ph"), tg.Has("ph_word") ? tg.S("ph_word") : Phs[(int)tg.N("iphase")], mr[0], mr[3], 0);
            if (tg.Has("zoom") && tg.N("zoom") != 0) Text(sl("zm"), "ZOOM", mr[1], mr[3], 0);
            Text(sl("al"), msg, mr[2], mr[3], 2);
            var ck = Geo("clock_px");
            Text(sl("met"), Clock(), ck[0], ck[1], 1);
        }

        // ---- tdTick's body (after its tdOn / tdPg test)
        void Tick(TdTg tg, Lexicon st, ListValue inp)
        {
            FlashStep();
            var g = Lx(tg["g"]);
            double iph = tg.N("iphase");
            if (iph != Tdm.D(E.G("tdLastPh"))) { LogEvent(Phs[(int)iph]); E.S("tdLastPh", tg["iphase"]); }
            string msg = "";
            if (!Tdm.SEq(tg.S("dm_msg"), "")) msg = tg.S("dm_msg").Trim();
            if (!Tdm.SEq(msg, Tdm.T(E.G("tdLastMsg")))) { if (!Tdm.SEq(msg, "")) LogEvent(msg); E.S("tdLastMsg", new StringValue(msg)); }
            string dmShown = "";
            if (hasDm) dmShown = Tdm.T(dmS);
            msg = "";
            if (!Tdm.SEq(dmShown, "")) msg = dmShown.Trim();
            CycUp();
            var e = EnNow(tg, st);
            if (lvT) Vs(tg, st, g, inp, e);
            if (lvB) Hs(tg, st, g, e);
            if (lvT) MsgRow(SV, tg, msg);
            if (lvB) MsgRow(SH, tg, msg);
            SweepW();
            if (cyc) SetPrev(K(st, "psd"));
        }

        // ---- tdVsK (the GRTLS's wider VERT SIT 0)
        double VsK(double d, double h)
        {
            if (d / 1000 < Geo("vs_switch_km")[0]) return 2;
            var a = Geo("vs1_km");
            if (tdMm == 602 && (d / 1000 > a[1] || h / 1000 > a[3])) return 0;
            return 1;
        }

        // ---- tdVs
        void Vs(TdTg tg, Lexicon st, Lexicon g, ListValue inp, double[] e)
        {
            double d = e[0];
            double k = VsK(d, KN(st, "h"));
            string bgv = tdMm == 602 ? TD_GR_DIR + "vsit" + Tdm.Num(k) + "_602.png" : TD_DIR + "vsit" + Tdm.Num(k) + ".png";
            BgV(bgv);
            double gam = Tdm.Atan2(KN(st, "hdot"), Math.Max(KN(st, "surfv"), 1));
            double gi = Math.Max(-40, Math.Min(14, 2 * Tdm.Round(gam / 2)));
            var bp = KmPx(k, d / 1000, KN(st, "h") / 1000);
            string bn = BugName(gi);
            if (VsShow(bn, bp[0], bp[1])) Put(SV("bug"), bn, bp[0], bp[1]);
            double hb = (e[3] - e[2]) / 1000;
            var ep = KmPx(k, d / 1000, hb);
            if (InVs(k, d / 1000, hb) && VsShow("ebox", ep[0], ep[1])) Put(SV("ebox"), "ebox", ep[0], ep[1]);   // The energy box is EOW: it stays under SW 02
            double sx = Geo("vs_strip_px")[0];
            var lab = Geo("vs_label_px");
            double iph = tg.N("iphase");
            if (!(iph == TG_IPH_STURN && !tdFlash)) Put(SV("ewtri"), "ewtri", sx, EwY(e[3] - e[1]));   // EOW stays under SW 02
            if (iph == TG_IPH_STURN || (iph == TG_IPH_ACQ && d > TG_RMINST && KN(g, "psha") < TG_PSSTRN))
            {
                double ys = EwY(TG_STURN_DELTA);
                Put(SV("stn"), "stn", sx, ys);
                Text(SV("stnl"), "STN", lab[0], ys, 0);
            }
            if (tg.B("mep_avail") && iph == TG_IPH_ACQ && tg.N("t_to_hac") >= TG_DM_T_HAC_MEP)
            {
                double ym = EwY(tg.N("emep") - tg.N("en"));
                Put(SV("mep"), "mep", sx, ym);
                double yl = ym;
                foreach (double ysn in new[] { EwY(0), EwY(TG_STURN_DELTA) })
                {
                    if (Math.Abs(yl - ysn) < lab[3]) yl = ym < ysn ? ysn - lab[3] : ysn + lab[3];
                }
                Text(SV("mepl"), "MEP", lab[0], yl, 0);
            }
            if (tg.B("strt_avail") && iph == TG_IPH_ACQ && d > DrpredOf(TG_RMOH) && tg.N("t_to_hac") >= TG_DM_T_HAC_STRT)
                Put(SV("ewarr"), "ewarr", sx, EwY(tg.N("emoh") - tg.N("en")));
            var rd = Geo("vs_readout_px");
            double sbA = Tdm.D(inp[9]);                                   // tdSbA (TAEM) or sbSet (the GRTLS): as flown
            double sbCmd = tg.N("dsbc");                                  // the command as the DAP flies it: capped above Mach 1.5
            if (sbA >= 0 && KN(st, "mach") > tdSbCapM) sbCmd = Math.Min(sbCmd, tdSbCap);
            string[] vals = { Tdm.Num(Tdm.Round(TD_SB_PCT * (sbA >= 0 ? sbA : tg.N("dsbc")))), Tdm.Num(Tdm.Round(TD_SB_PCT * sbCmd)),
                Tdm.Num(Tdm.Round(tg.Has("nz_meas") ? tg.N("nz_meas") : tg.N("nz_total"), 2)), Tdm.Num(Tdm.Round(tg.N("nz_total"), 2)),
                Tdm.Num(Tdm.Round(tg.N("qbarf") / TD_PSF)),
                tdMm == 602 ? TrimTxt(inp) : Tdm.Num(Tdm.Round(tg.N("qbref") / TD_PSF)), Tdm.Num(Tdm.Round(KN(st, "mach"), 2)) };
            // lib_taemdisp's rule: the guidance's commands blank under SW 02: rows 1 (sb command), 3 (Nz command), 5 (trim / QREF), 0 when it is the command
            for (int i = 0; i < 7; i++) Text(SV("r" + i), gdl && (i == 1 || i == 3 || (i == 0 && sbA < 0)) ? "----" : vals[i], rd[1], rd[2 + i], 1);
            if (tdMm == 602) Text(SV("trml"), "TRIM", rd[0], rd[7], 0);
        }

        // ---- tdHsOut: zoom z, or the tightest wider one whose window holds the vehicle (x, y km) inside TD_HS_OUT x its
        //      half-width; TD_HS_ZMIN at the most
        double HsOut(double z, double x, double y)
        {
            while (z > TD_HS_ZMIN)
            {
                var zz = Geo("hs" + Tdm.Num(z) + "_km");
                double lim = TD_HS_OUT * zz[2];
                if (Math.Abs(x - zz[0]) <= lim && Math.Abs(y - zz[1]) <= lim) return z;
                z = z - 1;
            }
            return TD_HS_ZMIN;
        }
        // ---- tdHsPin: the sprite nm at page px (x, y) held wholly inside the field b
        double[] HsPin(string nm, double x, double y, double[] b)
        {
            if (!Has(tdSpr, nm)) return new[] { x, y };
            var sp = Ls(K(tdSpr, nm));
            double e = TD_FIT_IN + 1;
            return new[] { Math.Max(b[0] + e + Tdm.D(sp[3]), Math.Min(b[0] + b[2] - e - Tdm.D(sp[1]) + Tdm.D(sp[3]), x)),
                Math.Max(b[1] + e + Tdm.D(sp[4]), Math.Min(b[1] + b[3] - e - Tdm.D(sp[2]) + Tdm.D(sp[4]), y)) };
        }

        // ---- tdHacArc (the HAC circle as tangent dashes, each shown when wholly inside the field f)
        void HacArc(double cx, double cy, double rpx, double[] f)
        {
            string ky = Tdm.Num(Tdm.Round(cx)) + " " + Tdm.Num(Tdm.Round(cy)) + " " + Tdm.Num(Tdm.Round(rpx));
            if (Tdm.SEq(ky, Tdm.T(E.G("tdHdKey"))))
            {
                double used = Tdm.D(E.G("tdHdUsed"));
                for (int i = 0; i < used; i++) SlotOn(SH("hd" + i));
                return;
            }
            E.S("tdHdKey", new StringValue(ky));
            double n = Math.Min(TD_HACD_N, Math.Max(8, Math.Ceiling(2 * Math.PI * rpx / TD_HACD_L)));
            int j = 0;
            for (int k = 0; k < n; k++)
            {
                double th = 360 * k / n;        // from the page's up, clockwise: the tangent lies th from +x toward +y (down)
                double o = Tdm.Mod(Tdm.Round(th * TD_HACD_NO / 180), TD_HACD_NO);
                string nm = "hacd_" + (o < 10 ? "0" : "") + Tdm.Num(o);
                double x = cx + rpx * Tdm.Sin(th), y = cy - rpx * Tdm.Cos(th);
                if (Fits(nm, x, y, f)) { Put(SH("hd" + j), nm, x, y); j++; }
            }
            E.S("tdHdUsed", Tdm.N(j));
        }

        // ---- the track-up world (lib_taemdisp tdTuHead .. tdTuRwy; the same expressions in the same order)
        void TuHead(double xk, double yk, double psd)
        {
            tuG = new[] { xk, yk, Tdm.Cos(psd), Tdm.Sin(psd), 0, 0, 1 };
        }
        void TuPlace(double bx, double by, double ppk) { tuG[4] = bx; tuG[5] = by; tuG[6] = ppk; }
        double[] TuRel(double xk, double yk)
        {
            double dx = xk - tuG[0];
            double dy = yk - tuG[1];
            return new[] { dx * tuG[2] + dy * tuG[3], dy * tuG[2] - dx * tuG[3] };
        }
        double[] TuPg(double xk, double yk)
        {
            var rl = TuRel(xk, yk);
            return new[] { tuG[4] + rl[1] * tuG[6], tuG[5] - rl[0] * tuG[6] };
        }
        bool TuHolds(double z, double frac, double[][] pts)
        {
            double hw = Geo("hs" + Tdm.Num(z) + "_km")[2];
            foreach (var p in pts)
                if (p[0] > 2 * hw * TD_TU_BY * frac || p[0] < -2 * hw * (1 - TD_TU_BY) * frac || Math.Abs(p[1]) > hw * frac) return false;
            return true;
        }
        double[] TuAim(double iph, double hx, double hy)
        {
            if (iph == 3) return TuRel(0, 0);
            return TuRel(hx, hy);
        }
        double[][] TuPts(double iph, double rkm, double hx, double hy)
        {
            if (iph == 3) return new[] { TuRel(0, 0) };
            var c = TuRel(hx, hy);
            return new[] { new[] { c[0] + rkm, c[1] }, new[] { c[0] - rkm, c[1] }, new[] { c[0], c[1] + rkm }, new[] { c[0], c[1] - rkm } };
        }
        double TuOut(double z, double[] a)
        {
            while (!(z <= TD_HS_ZMIN))
            {
                if (TuHolds(z, TD_HS_OUT, new[] { a })) return z;
                z = z - 1;
            }
            return TD_HS_ZMIN;
        }
        double TuRlen() { return rwyLen; }                  // kOS passes tdTuRlen() (ldRwy's length, else TD_RW_DEF)
        string TuName(string fam, double ang)
        {
            double o = Tdm.Mod(Tdm.Round(Tdm.Mod(Tdm.Mod(ang, 180) + 180, 180) * TD_HACD_NO / 180), TD_HACD_NO);
            return fam + (o < 10 ? "0" : "") + Tdm.Num(o);
        }
        void TuRwy(double[] f, double rlen)
        {
            double ppk = tuG[6];
            double ux = -tuG[3];
            double uy = -tuG[2];
            double ang = Tdm.Atan2(uy, ux);
            var t0 = TuPg(0, 0);
            double lpx = rlen / 1000 * ppk;
            double h = TD_RW_STK / 2;
            double ls = lpx + TD_RW_STK;
            double dl = TD_RWD_L;
            string fam = "rwd_";
            if (ls < dl) { dl = TD_RWS_L; fam = "rws_"; }
            string nm = TuName(fam, ang);
            double n = Math.Min(TD_RW_N, Math.Max(1, Math.Ceiling(ls / dl)));
            for (int i = 0; i < n; i++)
            {
                double c = ls / 2 - h;
                if (ls > dl) c = Math.Min(ls - dl / 2, i * dl + dl / 2) - h;
                double px = t0[0] + ux * c;
                double py = t0[1] + uy * c;
                if (Fits(nm, px, py, f)) Put(SH("rw" + Tdm.Num(i)), nm, px, py);
            }
            string cnm = TuName("cld_", ang);
            // one digital line (lib_taemdisp tdTuRwy's)
            var csp = Has(tdSpr, cnm) ? Ls(K(tdSpr, cnm)) : null;
            double csx = csp == null ? 0 : Tdm.D(csp[3]);
            double csy = csp == null ? 0 : Tdm.D(csp[4]);
            double cx0 = Tdm.Round(t0[0] - csx) + csx;
            double cy0 = Tdm.Round(t0[1] - csy) + csy;
            bool cxm = Math.Abs(ux) >= Math.Abs(uy);
            double bx = tuG[4];
            double by = tuG[5];
            double rr = Math.Pow(Math.Max(bx - f[0], f[0] + f[2] - bx), 2) + Math.Pow(Math.Max(by - f[1], f[1] + f[3] - by), 2);
            double yy = Math.Pow(tuG[1] * ppk, 2);
            if (rr > yy)
            {
                double hh = Math.Sqrt(rr - yy);
                double s0 = tuG[0] * ppk;
                double k1 = Math.Floor((s0 + hh) / TD_CLD_P);
                for (double k = Math.Ceiling((s0 - hh) / TD_CLD_P); !(k > k1); k = k + 1)
                {
                    double s = k * TD_CLD_P;
                    if (s < -h || s > lpx + h)
                    {
                        double dx, dy;
                        if (cxm) { dx = Tdm.Round(s * ux); dy = Tdm.Round(dx * uy / ux); }
                        else { dy = Tdm.Round(s * uy); dx = Tdm.Round(dy * ux / uy); }
                        double px = cx0 + dx;
                        double py = cy0 + dy;
                        if (Fits(cnm, px, py, f)) Put(SH("cl" + Tdm.Num(Tdm.Mod(Tdm.Mod(k, TD_CLD_N) + TD_CLD_N, TD_CLD_N))), cnm, px, py);
                    }
                }
            }
        }

        // ---- tdHs
        void Hs(TdTg tg, Lexicon st, Lexicon g, double[] e)
        {
            double x = KN(st, "x") / 1000;
            double y = KN(st, "y") / 1000;
            double rkm = RturnOf(KN(g, "psha"), tg.N("rf"), tg.N("r2")) / 1000;
            double hx = XhacOf(tg.B("nep")) / 1000;
            double hy = tg.N("ysgn") * tg.N("rf") / 1000;
            double zin = Geo("hs_zoom_in")[0];
            double zoom = -1;                   // none yet (the GRTLS's widest is 0)
            double iph = tg.N("iphase");
            bool tu = TD_TRKUP;
            if (tu)                             // track up: the vehicle is fixed on the page, so the AIM decides
            {
                TuHead(x, y, KN(st, "psd"));
                var tpts = TuPts(iph, rkm, hx, hy);
                foreach (double z in new double[] { 3, 2, 1 }) if (zoom < 0 && TuHolds(z, TD_TU_IN, tpts)) zoom = z;
            }
            else
            foreach (double z in new double[] { 3, 2, 1 })
            {
                var zz0 = Geo("hs" + Tdm.Num(z) + "_km");
                double lim = zin * zz0[2];
                bool ok = x >= zz0[0] - lim && x <= zz0[0] + lim && y >= zz0[1] - lim && y <= zz0[1] + lim;
                if (iph != 3 && ok)
                    ok = hx - rkm >= zz0[0] - lim && hx + rkm <= zz0[0] + lim && hy - rkm >= zz0[1] - lim && hy + rkm <= zz0[1] + lim;
                if (ok && zoom < 0) zoom = z;
            }
            if (zoom < 0) zoom = tdMm == 602 ? 0 : 1;
            if (tg.B("probe_valid") && (iph == TG_IPH_STURN || iph == TG_IPH_ACQ) && tg.N("t_to_hac") <= TD_HS_TTH_Z3)
                zoom = 3;                       // the 1 NM page from 20 s to the HAC (lib_taemdisp tdHs)
            zoom = Math.Max(zoom, Tdm.D(E.G("tdZoomLatch")));
            zoom = tu ? TuOut(zoom, TuAim(iph, hx, hy)) : HsOut(zoom, x, y);   // a zoom that would leave the vehicle (track up: the aim) off the page steps out (the latch with it)
            E.S("tdZoomLatch", Tdm.N(zoom));
            BgH(TD_DIR + "hsit" + Tdm.Num(zoom) + (tu ? "t" : "") + ".png");
            var zz = Geo("hs" + Tdm.Num(zoom) + "_km");
            var f = Geo("hs_field_px");
            double ppk = f[2] / (2 * zz[2]);
            if (tu) TuPlace(f[0] + f[2] / 2, f[1] + TD_TU_BY * f[3], ppk);
            double px = f[0] + f[2] / 2 + (y - zz[1]) * ppk;
            double py = f[1] + f[3] / 2 - (x - zz[0]) * ppk;
            double psd = KN(st, "psd");
            double hdg = Tdm.Mod(Tdm.Round(psd / 5) * 5 + 360, 360);
            var pp = HsPin(HsBugName(hdg), px, py, f);   // past the widest zoom, held at the edge
            string hbn = HsBugName(hdg);
            if (tu) { hbn = "hsbug_000"; pp = new[] { tuG[4], tuG[5] }; }   // track up: the nose up, fixed
            if (Fits(hbn, pp[0], pp[1], f)) Put(SH("bug"), hbn, pp[0], pp[1]);
            double rate;
            if (cyc)
            {
                rate = 0;
                var prev = Lx(E.G("tdPrev"));
                if (Has(prev, "t") && now > KN(prev, "t")) rate = Norm180(psd - KN(prev, "psd")) / (now - KN(prev, "t"));
                E.S("tdRate", Tdm.N(rate));
            }
            else rate = Tdm.D(E.G("tdRate"));
            double vh = KN(st, "vh");
            int i = 1;
            double sx0 = KN(st, "x"), sy0 = KN(st, "y");
            foreach (double tt in new double[] { 20, 40, 60 })
            {
                double xx = sx0; double yy = sy0; double hh = psd;
                double dh = rate * tt / 20;
                for (int n = 0; n < 20; n++)
                {
                    hh = hh + dh;
                    xx = xx + vh * Tdm.Cos(hh) * tt / 20;
                    yy = yy + vh * Tdm.Sin(hh) * tt / 20;
                }
                double qx = f[0] + f[2] / 2 + (yy / 1000 - zz[1]) * ppk;
                double qy = f[1] + f[3] / 2 - (xx / 1000 - zz[0]) * ppk;
                if (tu) { var qp = TuPg(xx / 1000, yy / 1000); qx = qp[0]; qy = qp[1]; }
                if (Fits("pred", qx, qy, f)) Put(SH("p" + i), "pred", qx, qy);
                i = i + 1;
            }
            if (iph != 3)
            {
                double rt = rkm * ppk;          // px
                double rp = Math.Max(TD_HAC_RMIN, 2 * Tdm.Round(rt / 2));
                string hcn = "hac_" + (rp < 100 ? "0" : "") + Tdm.Num(rp);
                double hcx = f[0] + f[2] / 2 + (hy - zz[1]) * ppk, hcy = f[1] + f[3] / 2 - (hx - zz[0]) * ppk;
                if (tu) { var hp = TuPg(hx, hy); hcx = hp[0]; hcy = hp[1]; }
                // the whole circle when its sprite is wholly inside the field, else the arc that crosses the field in dashes
                if (rp <= TD_HAC_RMAX && Fits(hcn, hcx, hcy, f))
                {
                    Put(SH("hac"), hcn, hcx, hcy);
                    E.S("tdHdKey", new StringValue(""));
                }
                else HacArc(hcx, hcy, rt, f);
            }
            else E.S("tdHdKey", new StringValue(""));
            if (tu) TuRwy(f, TuRlen());        // the runway on the turned world
            var bar = Geo("hs_bar_px");
            double side = tg.N("ysgn") > 0 ? 1 : -1;
            double fb = -1;
            // The HAC geometry (the bar, its labels, the readout rows) stays under SW 02: only the commands blank (VERT SIT)
            if (iph == 1 && tg.N("t_to_hac") > 0)
            {
                double rt = RturnOf(KN(g, "psha"), tg.N("rf"), tg.N("r2"));
                // a redraw counts down from the cycle; at the estimate's own rate (lib_taemdisp the same)
                double tth = Math.Max(0, TthNow(tg.N("t_to_hac")) - Math.Sqrt(Math.Pow(TG_P2TRNC1, 2) - 1) * rt / Math.Max(vh, 1));
                if (tth <= TD_BAR_SHOW_S)
                {
                    double f0 = side > 0 ? 1 : 0;
                    fb = f0 + (1 - 2 * f0) * Math.Min(tth, TD_BAR_MOVE_S) / TD_BAR_MOVE_S;
                    if (!(tth > TD_BAR_MOVE_S && !tdFlash)) Put(SH("bar"), "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]);
                    Text(SH("b0"), "0", bar[0] + (bar[1] - bar[0]) * f0, bar[2] - bar[3], 2);
                    Text(SH("b1"), "5", bar[0] + (bar[1] - bar[0]) * 0.5, bar[2] - bar[3], 2);
                    Text(SH("b2"), "10", bar[0] + (bar[1] - bar[0]) * (1 - f0), bar[2] - bar[3], 2);
                }
            }
            else if (iph == 2)
            {
                fb = 0.5 - 0.5 * side * Math.Max(-1, Math.Min(1, tg.N("rerrc") / (5000 * TD_FT)));
                Put(SH("bar"), "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]);
                Text(SH("b0"), "5K", bar[0] - bar[4], bar[2], 1);
                Text(SH("b2"), "5K", bar[1] + bar[4], bar[2], 0);
            }
            else if (iph == 3)
            {
                fb = 0.5 + 0.5 * Math.Max(-1, Math.Min(1, KN(st, "y") / (2500 * TD_FT)));
                Put(SH("bar"), "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]);
                Text(SH("b0"), "2.5K", bar[0] - bar[4], bar[2], 1);
                Text(SH("b2"), "2.5K", bar[1] + bar[4], bar[2], 0);
            }
            var gs = Geo("hs_gsi_px");
            double her = cyc ? tg.N("herror") : e[4] - KN(st, "h");
            double fg = 0.5 + 0.5 * Math.Max(-1, Math.Min(1, her / (gs[3] * TD_FT)));
            Put(SH("gsi"), "gsi", gs[0], gs[2] + (gs[1] - gs[2]) * fg);
            var rd = Geo("hs_readout_px");
            string[] vals = { RwyName(), (side > 0 ? "R " : "L ") + (tg.B("strt") ? "STRT" : "OVHD"), tg.B("nep") ? "NEP" : "MEP",
                Tdm.Num(Tdm.Round(KN(g, "psha"))), Tdm.Num(Tdm.Round(e[0] / TD_NM, 1)),
                iph == 1 ? Tdm.Num(Tdm.Round(KN(g, "dpsac"))) : "" };
            for (int j = 0; j < 6; j++) Text(SH("r" + j), vals[j], rd[1], rd[2 + j], 1);
            LogRows();
        }

        // ---- the MM 602 items
        double GrLine(string key, double m)
        {
            var p = GrT(key);
            int n = (int)Math.Floor(p.Length / 2.0);
            if (m <= p[0]) return p[1];
            if (m >= p[2 * n - 2]) return p[2 * n - 1];
            int i = 1;
            while (!(i >= n - 1 || p[2 * i] >= m)) i = i + 1;
            double m0 = p[2 * i - 2];
            double a0 = p[2 * i - 1];
            return a0 + (p[2 * i + 1] - a0) * (m - m0) / Math.Max(p[2 * i] - m0, 0.000001);
        }
        double[] GrAmPx(double m, double a)
        {
            var b = GrT("am_box_px");
            var sm = GrT("am_mach");
            var sa = GrT("am_alpha");
            double fx = Math.Max(0, Math.Min(1, (m - sm[0]) / (sm[1] - sm[0])));
            double fy = Math.Max(0, Math.Min(1, (a - sa[0]) / (sa[1] - sa[0])));
            var sp = Ls(K(tdSpr, "vsbug_p00"));     // held with its bug wholly inside the box
            double w = Tdm.D(sp[1]), h = Tdm.D(sp[2]), ax = Tdm.D(sp[3]), ay = Tdm.D(sp[4]);
            return new[] { Math.Max(b[0] + ax + TD_FIT_IN, Math.Min(b[0] + b[2] - w + ax - TD_FIT_IN, b[0] + b[2] * fx)),
                           Math.Max(b[1] + ay + TD_FIT_IN, Math.Min(b[1] + b[3] - h + ay - TD_FIT_IN, b[1] + b[3] * (1 - fy))) };
        }
        static string GrPhw(double ph)
        {
            if (ph == 6) return "ALPHA REC";
            if (ph == 5) return "NZ HOLD";
            if (ph == 7) return "BAILOUT";
            if (ph == 8) return "SPLIT-S";
            return "ALPHA TRAN";
        }
        string GrTgtNz(Lexicon gr, ListValue inp)
        {
            if (Tdm.B(inp[14])) return Tdm.Num(Tdm.Round(Tdm.D(inp[15]), 2));
            if (KN(gr, "iphase") == 6 && KN(gr, "dgrnzt") <= 0) return "";
            return Tdm.Num(Tdm.Round(Tdm.D(inp[16]) + KN(gr, "dgrnz") + 1.0, 2));
        }

        // ---- tdGrTick's body (after its tdOn / tdPg test)
        void GrTick(Lexicon gr, Lexicon st, ListValue inp)
        {
            double ph = KN(gr, "iphase");
            string phw = GrPhw(ph);
            if (ph != Tdm.D(E.G("tdGrPh"))) { LogEvent(phw); E.S("tdGrPh", K(gr, "iphase")); }
            double snNz = Tdm.D(inp[6]), snMach = Tdm.D(inp[7]), am = Tdm.D(inp[8]);
            Structure sbS = inp[9];
            // TAEM's page from the boot (lib_grtls's GR["tgon"], its gtp GR["gpd"])
            if (KN(gr, "tgon") == 1 && KN(gr, "cont") != 2 && (ph == 4 || ph == 5 || ph == 6))
            {
                var tgd = new TdTg(Lx(K(gr, "tg")));
                tgd.Set("g", K(gr, "gpd"));
                tgd.Set("nz_total", Tdm.N(Tdm.D(inp[16]) + KN(gr, "dgrnz") + 1.0));
                tgd.Set("nz_meas", inp[6]);
                tgd.Set("dsbc", sbS);
                tgd.Set("ph_word", new StringValue(phw));
                E.S("tdLastPh", tgd["iphase"]);
                Tick(tgd, st, inp);
            }
            else GrPre(gr, st, inp, phw);
            if (!lvT) return;                            // The alpha bug, the NZ readout, BAILOUT / ECAL are VERT SIT's: its GPC is out
            var p = GrAmPx(snMach, am);
            if (am < GrLine("am_qlim", snMach) && !tdFlash) Put(SG("am"), "grblank", p[0], p[1]);
            else Put(SG("am"), "vsbug_p00", p[0], p[1]);
            var rd = Geo("vs_readout_px");
            Text(SG("nzv"), " ", rd[1], rd[4], 1);       // the value: TAEM's readout, normal intensity
            Text(SG("nzi"), (ph == 5 || ph == 8) ? "NZ" : " ", rd[1] + 10, rd[4], 0);
            if (KN(gr, "cont") != 0)
            {
                double rb = rd[8] + rd[4] - rd[3];
                Text(SG("bail"), ph == 7 ? "BAILOUT" : " ", rd[0], rb, 0);
                Text(SG("ecal"), KN(gr, "cont") == 1 ? "ECAL/BDA ENA" : "ECAL/BDA INH", rd[0], rb + rd[3] - rd[2], 0);
            }
        }

        // ---- tdGrPre (phases 6 / 5 / 7 / 8: both pages without TAEM guidance)
        void GrPre(Lexicon gr, Lexicon st, ListValue inp, string phw)
        {
            FlashStep();
            CycUp();
            bool isBlue = KN(gr, "cont") == 2;
            double d = 0;
            double k = 1;
            if (!isBlue)
            {
                if (!Tdm.B(inp[17])) throw new Exception("no taemg_gtp result");
                E.S("tdGrPsha", inp[18]);
                d = DrpredOf(Tdm.D(inp[19]));
                k = d / 1000 < Geo("vs_switch_km")[0] ? 2 : 1;
            }
            if (lvT) {
            BgV(TD_GR_DIR + "vsit" + Tdm.Num(k) + "_602.png");
            var a = Geo("vs" + Tdm.Num(k) + "_km");
            double dk = d / 1000;
            double hk = KN(st, "h") / 1000;
            if (!isBlue && dk >= a[0] && dk <= a[1] && hk >= a[2] && hk <= a[3])
            {
                double gi = Math.Max(-40, Math.Min(14, 2 * Tdm.Round(Tdm.Atan2(KN(st, "hdot"), Math.Max(KN(st, "surfv"), 1)) / 2)));
                var bp = KmPx(k, dk, hk);
                string bn = BugName(gi);
                if (VsShow(bn, bp[0], bp[1])) Put(SV("bug"), bn, bp[0], bp[1]);
            }
            if (tdFlash && !isBlue) Put(SV("ewtri"), "ewtri", Geo("vs_strip_px")[0], EwY(-1E9));
            var rd = Geo("vs_readout_px");
            double snNz = Tdm.D(inp[6]);
            string nzs = Tdm.Num(Tdm.Round(snNz, 2));
            double sb = Tdm.D(inp[9]);
            string[] vals = { Tdm.Num(Tdm.Round(TD_SB_PCT * sb)), Tdm.Num(Tdm.Round(TD_SB_PCT * sb)), nzs, GrTgtNz(gr, inp), Tdm.Num(Tdm.Round(KN(st, "qbar") / TD_PSF)),
                TrimTxt(inp), Tdm.Num(Tdm.Round(KN(st, "mach"), 2)) };
            for (int i = 0; i < 7; i++) Text(SV("r" + i), vals[i], rd[1], rd[2 + i], 1);
            Text(SV("trml"), "TRIM", rd[0], rd[7], 0);
            }
            if (lvB) {
            // the tightest zoom from 1 out that holds the vehicle (HsOut; the latch is TAEM's), past the widest the symbol
            // held at the edge (lib_taemdisp tdGrTick)
            double x = 0, y = 0, zm = 1;
            bool tu = TD_TRKUP && !isBlue;     // the runway on the turned world (a BLUE has none: the bug upright)
            if (!isBlue)
            {
                x = KN(st, "x") / 1000;
                y = KN(st, "y") / 1000;
                if (tu) { TuHead(x, y, KN(st, "psd")); zm = TuOut(1, TuRel(0, 0)); }
                else zm = HsOut(1, x, y);
            }
            BgH(isBlue ? TD_GR_DIR + TD_GR_HS_BLUE : TD_DIR + "hsit" + Tdm.Num(zm) + (tu ? "t" : "") + ".png");
            var zz = Geo("hs" + Tdm.Num(zm) + "_km");
            var f = Geo("hs_field_px");
            double ppk = f[2] / (2 * zz[2]);
            if (isBlue) { x = zz[0]; y = zz[1]; }
            double hdg = Tdm.Mod(Tdm.Round(KN(st, "psd") / 5) * 5 + 360, 360);
            var hbp = HsPin(HsBugName(hdg), f[0] + f[2] / 2 + (y - zz[1]) * ppk, f[1] + f[3] / 2 - (x - zz[0]) * ppk, f);
            string hbn = HsBugName(hdg);
            if (TD_TRKUP)                       // track up: the nose up, fixed (a BLUE: at the field's centre)
            {
                hbn = "hsbug_000";
                if (tu) { TuPlace(f[0] + f[2] / 2, f[1] + TD_TU_BY * f[3], ppk); hbp = new[] { tuG[4], tuG[5] }; }
                else hbp = new[] { f[0] + f[2] / 2, f[1] + f[3] / 2 };
            }
            if (Fits(hbn, hbp[0], hbp[1], f)) Put(SH("bug"), hbn, hbp[0], hbp[1]);
            if (tu) TuRwy(f, TuRlen());
            var rh = Geo("hs_readout_px");
            if (!isBlue)
            {
                Text(SH("r0"), RwyName(), rh[1], rh[2], 1);
                Text(SH("r4"), Tdm.Num(Tdm.Round(d / TD_NM, 1)), rh[1], rh[6], 1);
            }
            LogRows();
            }
            var mr = Geo("msg_row_px");
            var ck = Geo("clock_px");
            string clk = Clock();
            if (lvT) { Text(SV("ph"), phw, mr[0], mr[3], 0); Text(SV("met"), clk, ck[0], ck[1], 1); }
            if (lvB) { Text(SH("ph"), phw, mr[0], mr[3], 0); Text(SH("met"), clk, ck[0], ck[1], 1); }
            SweepW();
            if (cyc) SetPrev(K(st, "psd"));
        }

        // TDDRAW: one draw. kind 0 = tdTick (a = tg, b = st), 1 = tdGrTick (a = gr, b = st). inp = the hook's reads:
        // [0] kind, [1] TIME:SECONDS, [2] cyc, [3] ldDmShow defined, [4] ldDmShow, [5] ldRwy has a name, [6] sn["nz"],
        // [7] sn["mach"], [8] am, [9] sbSet (kind 0: tdSbA), [10] PTRIM_ANG defined, [11] PTRIM_ANG, [12] ETRIM_ANG defined, [13] ETRIM_ANG,
        // [14] SS_ON, [15] SS_NZ, [16] GR_GRNZC1, [17] a taemg_gtp result (tdGrPre's), [18] its psha, [19] its rpred,
        // [20] ldRwy["name"]
        public void Draw(Lexicon a, Lexicon b, ListValue inp)
        {
            Ops.Clear();
            Load();
            int kind = (int)Tdm.D(inp[0]);
            now = Tdm.D(inp[1]);
            cyc = Tdm.B(inp[2]);
            hasDm = Tdm.B(inp[3]); dmS = inp[4];
            hasRwy = Tdm.B(inp[5]); rwyS = inp[20];
            rwyLen = Tdm.D(inp[21]);
            gdl = inp.Count > 22 && Tdm.B(inp[22]);
            lvT = inp.Count <= 23 || Tdm.B(inp[23]);
            lvB = inp.Count <= 24 || Tdm.B(inp[24]);
            if (kind == 0) Tick(new TdTg(a), b, inp);
            else GrTick(a, b, inp);
        }
    }
}
