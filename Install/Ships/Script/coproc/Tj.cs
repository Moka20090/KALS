// lib/traj_display.ks's per-update math (the ENTRY TRAJ page: trajUpdate and everything under it --
// trajPanelFor, trajPx, trajAlphaScale / trajDragScale, trajStripPx, tjFlow, tjCol, tjLR, tjTrim, tjSigned, tjPad, tjClock)
// in C#, line for line with kOS's semantics (MIN / MAX, ROUND = Math.Round, FLOOR, MOD = %, numbers to text by kOS.Safe's
// own ScalarValue ToString, string '=' / '<>' and lexicon keys case-insensitive).
// THE STATE STAYS KOS'S: tjCycle, tjPanel, tjTrail, tjBoxTrail, tjTrailT, tjTrailDirty, tjRowsPlaced, tjTLtxt, tjBRtxt are
// read from kOS at each call and written back (TjEnv) only after the whole call succeeded, so kOS's own code can take over
// at any update. THE WIDGETS STAY KOS'S: every widget write kOS's trajUpdate would make comes back as an op (widget, code,
// value), in the kOS code's order (TJ_CS_SKIP: the ops that would set a property to the value C# set last are dropped).
// THE GAME READS STAY KOS'S (the hook: TIME:SECONDS, the box's TJ_BANK_RANGE call, uiDispOn): no Unity object touched here.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class TjRef<T> : IEqualityComparer<T> where T : class
    {
        public bool Equals(T a, T b) { return ReferenceEquals(a, b); }
        public int GetHashCode(T o) { return System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(o); }
    }

    // the kOS side: globals by name and list elements; writes captured (Commit applies them);
    // reads see the captured writes first
    public class TjEnv
    {
        readonly kOS.Safe.Execution.ICpu cpu;
        public Dictionary<string, Structure> Gw = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<ListValue, Dictionary<int, Structure>> Lw = new Dictionary<ListValue, Dictionary<int, Structure>>(new TjRef<ListValue>());
        public TjEnv(kOS.Safe.Execution.ICpu c) { cpu = c; }
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
            if (i < 0 || i >= l.Count) throw new Exception("list index " + i + " out of range");
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
    public static class Tjm
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
        public static string Num(double x) { return ScalarValue.Create(x).ToString(); }
        // lib/traj_display tjUBank's text: u with two decimals, " | ", the bank in a 2-character field
        public static string UBank(double u, double b)
        {
            double r = Math.Round(Math.Abs(u), 2);
            string s = Num(r);
            int p = s.IndexOf('.');
            if (p < 0) s += ".00"; else if (s.Length - p == 2) s += "0";
            if (u < 0 && r > 0) s = "-" + s;
            if (b < -1E8) return s;
            string bs = Num(Math.Round(Math.Abs(b)));
            if (bs.Length < 2) bs = " " + bs;
            return s + " | " + bs;
        }
        public static ScalarValue N(double x) { return ScalarValue.Create(x); }
        public static ListValue Ls(Structure s) { var l = s as ListValue; if (l == null) throw new Exception("not a LIST"); return l; }
        public static Lexicon Lx(Structure s) { var l = s as Lexicon; if (l == null) throw new Exception("not a LEXICON"); return l; }
    }

    public class TjCalc
    {
        public const int OP_TEXT = 0, OP_IMAGE = 1, OP_MH = 4, OP_MV = 5, OP_BG = 7;
        public TjEnv E;
        public List<Structure> Ops = new List<Structure>();
        // TJ_CS_SKIP: the last value C# set on each (widget, property), and this call's pending ones (committed with the call)
        public readonly Dictionary<Structure, Dictionary<int, Structure>> Last = new Dictionary<Structure, Dictionary<int, Structure>>(new TjRef<Structure>());
        public readonly Dictionary<Structure, Dictionary<int, Structure>> Pend = new Dictionary<Structure, Dictionary<int, Structure>>(new TjRef<Structure>());
        public int NSkip = 0, NOps = 0;
        bool skip;

        // per call: kOS's constants and the page's widgets (read, never retyped)
        double TJ_FIT_IN;
        double TJ_BUG_W, TJ_BUG_OFF_X, TJ_BUG_OFF_Y, TJ_IMG_DY, TJ_FLOW_PX, TJ_V_SCALE, TJ_BOX_W, TJ_TRAIL_S, TJ_TRAIL_N, TJ_TRAIL_W,
            TJ_TRAIL_V_LO, TJ_TRAIL_V_HI, TJ_TRAIL_V_N, TJ_DOT_W, EPR_GUID_DRAG_INIT, TJ_ARR_H, TJ_ARR_TIPF, TJ_TRI_H, TJ_TRI_TIPF, TJ_ARR_W, TJ_TRI_W, tjS, TJ_BR_DY, TJ_TL_DY, TJ_CLK_DY;
        double tjBugI, tjBoxI, tjAArrI, tjATriI, tjDArrI, tjDTriI, tjInitI, tjClkI;
        bool TJ_BUG_ON;
        Structure TJ_EMPTY, TJ_BUG_IMG, TJ_BOX_IMG, TJ_TRAIL_IMG, TJ_DOT_IMG, TJ_AARR_IMG, TJ_ATRI_IMG, TJ_DARR_IMG, TJ_DTRI_IMG;
        string TJ_GREEN, TJ_YELLOW;
        Lexicon TJ_D;
        ListValue TJ_P, tjTrailM, tjDotM, tjTrailI, tjDotI, tjTL, tjTLidx, tjBR, tjBRidx, tjTLtxt, tjBRtxt;
        Structure tjBox, tjBugM, tjBoxM, tjAArr, tjATri, tjDArr, tjDTri, tjInitM, tjTitle, tjClk;

        public TjCalc(TjEnv e) { E = e; }

        double GD(string n) { return Tjm.D(E.Raw(n)); }
        static Structure K(Lexicon x, string k) { return x[new StringValue(k)]; }
        static bool Has(Lexicon x, string k) { return x.ContainsKey(new StringValue(k)); }
        static double LD(ListValue l, int i) { return Tjm.D(l[i]); }

        public void Load()
        {
            TJ_FIT_IN = GD("TJ_FIT_IN");
            TJ_BUG_W = GD("TJ_BUG_W"); TJ_BUG_OFF_X = GD("TJ_BUG_OFF_X"); TJ_BUG_OFF_Y = GD("TJ_BUG_OFF_Y"); TJ_IMG_DY = GD("TJ_IMG_DY");
            TJ_FLOW_PX = GD("TJ_FLOW_PX"); TJ_V_SCALE = GD("TJ_V_SCALE"); TJ_BOX_W = GD("TJ_BOX_W"); TJ_TRAIL_S = GD("TJ_TRAIL_S");
            TJ_TRAIL_N = GD("TJ_TRAIL_N"); TJ_TRAIL_W = GD("TJ_TRAIL_W"); TJ_DOT_W = GD("TJ_DOT_W");
            TJ_TRAIL_V_LO = GD("TJ_TRAIL_V_LO"); TJ_TRAIL_V_HI = GD("TJ_TRAIL_V_HI"); TJ_TRAIL_V_N = GD("TJ_TRAIL_V_N");
            EPR_GUID_DRAG_INIT = GD("EPR_GUID_DRAG_INIT"); TJ_ARR_H = GD("TJ_ARR_H"); TJ_ARR_TIPF = GD("TJ_ARR_TIPF");
            TJ_TRI_H = GD("TJ_TRI_H"); TJ_TRI_TIPF = GD("TJ_TRI_TIPF"); TJ_ARR_W = GD("TJ_ARR_W"); TJ_TRI_W = GD("TJ_TRI_W");
            tjS = GD("tjS"); TJ_BR_DY = GD("TJ_BR_DY"); TJ_TL_DY = GD("TJ_TL_DY"); TJ_CLK_DY = GD("TJ_CLK_DY");
            tjBugI = GD("tjBugI"); tjBoxI = GD("tjBoxI"); tjAArrI = GD("tjAArrI"); tjATriI = GD("tjATriI"); tjDArrI = GD("tjDArrI");
            tjDTriI = GD("tjDTriI"); tjInitI = GD("tjInitI"); tjClkI = GD("tjClkI");
            TJ_BUG_ON = Tjm.B(E.Raw("TJ_BUG_ON"));
            TJ_EMPTY = E.Raw("TJ_EMPTY"); TJ_BUG_IMG = E.Raw("TJ_BUG_IMG"); TJ_BOX_IMG = E.Raw("TJ_BOX_IMG");
            TJ_TRAIL_IMG = E.Raw("TJ_TRAIL_IMG"); TJ_DOT_IMG = E.Raw("TJ_DOT_IMG"); TJ_AARR_IMG = E.Raw("TJ_AARR_IMG");
            TJ_ATRI_IMG = E.Raw("TJ_ATRI_IMG"); TJ_DARR_IMG = E.Raw("TJ_DARR_IMG"); TJ_DTRI_IMG = E.Raw("TJ_DTRI_IMG");
            TJ_GREEN = Tjm.T(E.Raw("TJ_GREEN")); TJ_YELLOW = Tjm.T(E.Raw("TJ_YELLOW"));
            TJ_D = Tjm.Lx(E.Raw("TJ_D")); TJ_P = Tjm.Ls(E.Raw("TJ_P"));
            tjTrailM = Tjm.Ls(E.Raw("tjTrailM")); tjDotM = Tjm.Ls(E.Raw("tjDotM")); tjTrailI = Tjm.Ls(E.Raw("tjTrailI"));
            tjDotI = Tjm.Ls(E.Raw("tjDotI")); tjTL = Tjm.Ls(E.Raw("tjTL")); tjTLidx = Tjm.Ls(E.Raw("tjTLidx"));
            tjBR = Tjm.Ls(E.Raw("tjBR")); tjBRidx = Tjm.Ls(E.Raw("tjBRidx"));
            tjTLtxt = Tjm.Ls(E.Raw("tjTLtxt")); tjBRtxt = Tjm.Ls(E.Raw("tjBRtxt"));
            tjBox = E.Raw("tjBox"); tjBugM = E.Raw("tjBugM"); tjBoxM = E.Raw("tjBoxM"); tjAArr = E.Raw("tjAArr");
            tjATri = E.Raw("tjATri"); tjDArr = E.Raw("tjDArr"); tjDTri = E.Raw("tjDTri"); tjInitM = E.Raw("tjInitM");
            tjTitle = E.Raw("tjTitle"); tjClk = E.Raw("tjClk");
            skip = Tjm.B(E.Raw("TJ_CS_SKIP"));
        }

        // traj_display's trajTrailStep: the velocity step (0 .. TJ_TRAIL_V_N) of vrel on a velocity-keyed panel p
        double TrailStep(ListValue p, double vrel)
        {
            double k = Math.Floor((LD(p, 1) - vrel) / ((LD(p, 1) - LD(p, 2)) / TJ_TRAIL_V_N)) + 1;
            if (k < 0) return 0;
            if (k > TJ_TRAIL_V_N) return TJ_TRAIL_V_N;
            return k;
        }

        // TJSETUP: everything a draw reads is there (a missing name throws here, once, and kOS keeps drawing)
        public void Setup()
        {
            Load();
            E.Raw("tjCycle"); E.Raw("tjPanel"); E.Raw("tjTrail"); E.Raw("tjBoxTrail"); E.Raw("tjTrailT"); E.Raw("tjTrailDirty");
            E.Raw("tjRowsPlaced"); E.Raw("tjCsKos"); E.Raw("tjFlashN"); E.Raw("tjRtT");
            foreach (var k in new[] { "field_px", "strip_a", "strip_d", "tl_rows", "tl_right", "br_rows", "br_right" }) K(TJ_D, k);
            if (TJ_P.Count < 1) throw new Exception("TJ_P is empty");
            if (tjTrailM.Count < (int)TJ_TRAIL_N || tjDotM.Count < (int)TJ_TRAIL_N) throw new Exception("the crumb slots are short");
            if (tjTL.Count < 5 || tjBR.Count < 9 || tjTLtxt.Count < 5 || tjBRtxt.Count < 9) throw new Exception("the readout rows are short");
        }

        void Op(Structure w, int code, Structure v)
        {
            NOps++;
            if (skip)
            {
                Dictionary<int, Structure> d; Structure o;
                if (Pend.TryGetValue(w, out d) && d.TryGetValue(code, out o)) { if (Same(o, v)) { NSkip++; return; } }
                else if (Last.TryGetValue(w, out d) && d.TryGetValue(code, out o)) { if (Same(o, v)) { NSkip++; return; } }
                if (!Pend.TryGetValue(w, out d)) { d = new Dictionary<int, Structure>(); Pend[w] = d; }
                d[code] = v;
            }
            Ops.Add(w); Ops.Add(ScalarValue.Create(code)); Ops.Add(v);
        }
        static bool Same(Structure a, Structure b)
        {
            if (a is ScalarValue && b is ScalarValue) return ((ScalarValue)a).GetDoubleValue() == ((ScalarValue)b).GetDoubleValue();
            if (a is StringValue && b is StringValue) return string.Equals(a.ToString(), b.ToString(), StringComparison.Ordinal);
            return false;
        }
        public void CommitLast()
        {
            foreach (var kv in Pend)
            {
                Dictionary<int, Structure> d;
                if (!Last.TryGetValue(kv.Key, out d)) { d = new Dictionary<int, Structure>(); Last[kv.Key] = d; }
                foreach (var kv2 in kv.Value) d[kv2.Key] = kv2.Value;
            }
            Pend.Clear();
        }

        // ---- the geometry (traj_display.ks)
        Structure PanelFor(double vrel)
        {
            Structure best = TJ_P[0];
            foreach (var ps in TJ_P)
            {
                var p = Tjm.Ls(ps);
                if (vrel <= LD(p, 1) && vrel >= LD(p, 2)) return ps;
                if (vrel > LD(p, 1)) best = ps;
            }
            if (vrel > LD(Tjm.Ls(TJ_P[0]), 1)) return TJ_P[0];
            return TJ_P[TJ_P.Count - 1];
        }
        double[] Px(ListValue p, double rngKm, double vrel)
        {
            var fx = Tjm.Ls(K(TJ_D, "field_px"));
            double xn = (rngKm - LD(p, 3)) / Math.Max(0.001, LD(p, 4) - LD(p, 3));
            // the band sits v_pad_px inside the field's top and bottom (traj_display's tjVPad; 0 without the line)
            double pd = 0;
            var pk = new StringValue("v_pad_px");
            if (TJ_D.ContainsKey(pk)) pd = Tjm.D(TJ_D[pk]);
            double fh = LD(fx, 3);
            double yn = (pd + (LD(p, 1) - vrel) / Math.Max(0.001, LD(p, 1) - LD(p, 2)) * (fh - 2 * pd)) / Math.Max(0.001, fh);
            if (xn < 0) xn = 0;
            if (xn > 1) xn = 1;
            if (yn < 0) yn = 0;
            if (yn > 1) yn = 1;
            return new[] { LD(fx, 0) + xn * LD(fx, 2), (LD(fx, 1) + yn * LD(fx, 3)) * TJ_V_SCALE };
        }
        double StripPx(double val, double lo, double hi, double topPx, double botPx)
        {
            double f = (val - lo) / Math.Max(0.001, hi - lo);
            if (f < 0) f = 0;
            if (f > 1) f = 1;
            return (botPx - f * (botPx - topPx)) * TJ_V_SCALE;
        }
        double Flow(double idx) { return idx * TJ_FLOW_PX; }
        // traj_display tjFits (a square sprite w px wide centred on p wholly inside the field less TJ_FIT_IN)
        bool Fits(double[] p, double w, double fx0, double fx1, double fx2, double fx3)
        {
            return p[0] - w / 2 >= fx0 + TJ_FIT_IN && p[0] + w / 2 <= fx0 + fx2 - TJ_FIT_IN
                && p[1] - w / 2 >= fx1 + TJ_FIT_IN && p[1] + w / 2 <= fx1 + fx3 - TJ_FIT_IN;
        }
        static string Col(string txt, string col) { return "<color=" + col + ">" + txt + "</color>"; }
        static string LR(double b) { return (b >= 0 ? "L" : "R") + Tjm.Num(Math.Round(Math.Abs(b))); }
        static string Trim(double flap, double elev)
        {
            string t = flap <= 0 ? "U" : "D";
            t = t + Tjm.Num(Math.Round(Math.Abs(flap), 2));
            if (Math.Abs(elev) > 0.01) t = t + ("+" + Tjm.Num(Math.Round(Math.Abs(elev), 2)));
            return t;
        }
        static string Signed(double x) { return (x >= 0 ? "+" : "") + Tjm.Num(Math.Round(x, 1)); }
        // the MACH readout (X.XX; ENTRY TRAJ shows Mach, not V), kOS's tjMach: M^2 = 2q / (1.4 p), p the static pressure at altKm (GetPressure, kPa: what ALTITUDEPRESSURE reads)
        static string Mach(double qbar, double altKm)
        {
            Vessel v = FlightGlobals.ActiveVessel;
            double ps = v != null && v.mainBody != null ? v.mainBody.GetPressure(altKm * 1000) : 0;
            double m = ps > 1E-7 ? Math.Sqrt(Math.Max(2 * qbar / (1.4 * ps), 0)) : 0;
            long c = (long)Math.Round(m * 100);
            return (c / 100) + "." + (c % 100).ToString("00");
        }
        static string Pad(double n, double w)
        {
            string t = "" + Tjm.Num(Math.Round(n));
            while (!(t.Length >= w)) t = "0" + t;
            return t;
        }
        static string Clock(double t)
        {
            double d = Math.Floor(t / 86400);
            double h = Math.Floor((t % 86400) / 3600);
            double mi = Math.Floor((t % 3600) / 60);
            double sc = Math.Floor(t % 60);
            return Pad(d, 3) + "/" + Pad(h, 2) + ":" + Pad(mi, 2) + ":" + Pad(sc, 2);
        }
        static StringValue S(string s) { return new StringValue(s); }

        // one draw: inp = LIST(args (trajUpdate's 22 parameters, a LIST), now (TIME:SECONDS), bxr (the box's range, m:
        // TJ_BANK_RANGE:CALL(ABS(rollref) + corr, vrel) when TJ_BUG_ON, else 0), uiDispOn(), count (1 = a guidance cycle:
        // tjCycle steps, as trajUpdate; 0 = a redraw between cycles: tjCycle and with it the flash phase stay))
        public void Draw(ListValue inp)
        {
            Ops.Clear(); Pend.Clear();
            Load();
            if (Tjm.B(E.Raw("tjCsKos"))) { Last.Clear(); E.S("tjCsKos", BooleanValue.False); }   // kOS drew since: forget
            var a = Tjm.Ls(inp[0]);
            if (a.Count != 22 && a.Count != 23) throw new Exception("the draw has " + a.Count + " arguments, not 22 or 23");
            Structure nowS = inp[1];
            double now = Tjm.D(nowS);
            double bxr = Tjm.D(inp[2]);
            bool uiOn = Tjm.B(inp[3]);
            bool count = Tjm.B(inp[4]);
            Structure vrelS = a[0];
            double vrel = Tjm.D(a[0]), rngM = Tjm.D(a[1]), dref = Tjm.D(a[2]), dact = Tjm.D(a[3]), aCmd = Tjm.D(a[4]),
                aAct = Tjm.D(a[5]), rollref = Tjm.D(a[6]), bankCmd = Tjm.D(a[7]), bankAct = Tjm.D(a[8]), corr = Tjm.D(a[9]),
                azErr = Tjm.D(a[10]), deadband = Tjm.D(a[11]), qbar = Tjm.D(a[12]), altKm = Tjm.D(a[13]), hdot = Tjm.D(a[14]),
                hddot = Tjm.D(a[15]), nz = Tjm.D(a[16]), famU = Tjm.D(a[17]), famRev = Tjm.D(a[18]), met = Tjm.D(a[19]),
                famRev2 = Tjm.D(a[20]), rollShow = Tjm.D(a[21]), famBank = a.Count > 22 ? Tjm.D(a[22]) : -1E9;

            Structure cycS = E.G("tjCycle");
            double tjCycle = Tjm.D(cycS);
            if (count)
            {
                tjCycle = tjCycle + 1;
                E.S("tjCycle", (cycS is ScalarIntValue && Math.Abs(tjCycle) < int.MaxValue) ? (Structure)ScalarValue.Create((int)tjCycle) : Tjm.N(tjCycle));
            }
            // the flashes at 5 Hz: the flash phase steps at every draw (traj_display's tjFlashN)
            Structure flS = E.G("tjFlashN");
            // while the C# draws live (traj_display's tjFlashClk) the TJ_DT_CS grid's slot at the draw
            // the grid on the draw's real time (traj_display's tjRtT, uiRt), not `now` (game time)
            double tjFlashN = Tjm.B(E.Raw("tjFlashClk")) ? Math.Floor((Tjm.D(E.Raw("tjRtT")) + 0.005) / GD("TJ_DT_CS")) : Tjm.D(flS) + 1;
            E.S("tjFlashN", (flS is ScalarIntValue && Math.Abs(tjFlashN) < int.MaxValue) ? (Structure)ScalarValue.Create((int)tjFlashN) : Tjm.N(tjFlashN));

            // ---- panel handover
            Structure pS = PanelFor(vrel);
            var p = Tjm.Ls(pS);
            var tjPanel = Tjm.Ls(E.G("tjPanel"));
            ListValue tjTrail = Tjm.Ls(E.G("tjTrail")), tjBoxTrail = Tjm.Ls(E.G("tjBoxTrail"));
            double tjTrailT = Tjm.D(E.G("tjTrailT"));
            bool tjTrailDirty = Tjm.B(E.G("tjTrailDirty"));
            if (LD(p, 0) != LD(tjPanel, 0))
            {
                tjPanel = p; E.S("tjPanel", pS);
                Op(tjBox, OP_BG, p[6]);
                tjTrail = new ListValue(); E.S("tjTrail", tjTrail);
                tjBoxTrail = new ListValue(); E.S("tjBoxTrail", tjBoxTrail);
                tjTrailT = now; E.S("tjTrailT", nowS);
                foreach (var m in tjTrailM) Op(m, OP_IMAGE, TJ_EMPTY);
                foreach (var m in tjDotM) Op(m, OP_IMAGE, TJ_EMPTY);
                tjTrailDirty = true;
            }

            double rngKm = rngM / 1000;
            var fx = Tjm.Ls(K(TJ_D, "field_px"));
            double fx0 = LD(fx, 0), fx1 = LD(fx, 1), fx2 = LD(fx, 2), fx3 = LD(fx, 3);

            // ---- is the orbiter bug drawable where it belongs?
            // the nose carries the position and the sprite trails right; every side from the sprite's own box,
            // TJ_FIT_IN inside (traj_display's)
            double padL = TJ_FIT_IN - TJ_BUG_OFF_X;
            double padX = TJ_BUG_W + TJ_BUG_OFF_X + TJ_FIT_IN;
            double padT = TJ_FIT_IN - TJ_BUG_OFF_Y;
            double padB = TJ_BUG_W * (25.0 / 38.0) + TJ_BUG_OFF_Y + TJ_FIT_IN;
            var bp = Px(p, rngKm, vrel);
            bool offscale = false;
            if (rngKm < LD(p, 3) || rngKm > LD(p, 4)) offscale = true;
            if (vrel > LD(p, 1) || vrel < LD(p, 2)) offscale = true;
            if (bp[0] < fx0 + padL || bp[0] > fx0 + fx2 - padX) offscale = true;
            if (bp[1] < fx1 + padT || bp[1] > fx1 + fx3 - padB) offscale = true;

            // ---- flashing
            bool lit = (tjFlashN % 2) == 0;
            bool reversing = famRev > 0.5;
            bool showBug = true;
            if (offscale || reversing) showBug = lit;
            if (!TJ_BUG_ON) showBug = false;

            // ---- bug
            double bx = Math.Max(fx0 + padL, Math.Min(fx0 + fx2 - padX, bp[0]));
            double by = Math.Max(fx1 + padT, Math.Min(fx1 + fx3 - padB, bp[1]));
            Op(tjBugM, OP_IMAGE, showBug ? TJ_BUG_IMG : TJ_EMPTY);
            Op(tjBugM, OP_MH, Tjm.N(bx + TJ_BUG_OFF_X));
            Op(tjBugM, OP_MV, Tjm.N(by + TJ_BUG_OFF_Y - TJ_IMG_DY - Flow(tjBugI)));

            // ---- box: the bank guidance WANTS (bxr: the hook's TJ_BANK_RANGE:CALL(rrMag + corr, vrel), 0 with the bug off)
            if (!TJ_BUG_ON) bxr = 0;
            if (bxr > 0 && showBug && by - TJ_BOX_W / 2 >= fx1 + TJ_FIT_IN && by + TJ_BOX_W / 2 <= fx1 + fx3 - TJ_FIT_IN)
            {
                var pxb = Px(p, bxr / 1000, vrel);
                Op(tjBoxM, OP_IMAGE, TJ_BOX_IMG);
                Op(tjBoxM, OP_MH, Tjm.N(Math.Max(fx0 + TJ_BOX_W / 2 + TJ_FIT_IN, Math.Min(fx0 + fx2 - TJ_BOX_W / 2 - TJ_FIT_IN,
                    pxb[0])) - TJ_BOX_W / 2));
                Op(tjBoxM, OP_MV, Tjm.N(by - TJ_BOX_W / 2 - TJ_IMG_DY - Flow(tjBoxI)));
            }
            else
            {
                Op(tjBoxM, OP_IMAGE, TJ_EMPTY);
            }

            // ---- crumbs
            // panels TJ_TRAIL_V_LO .. HI drop by velocity (a crumb when vrel is in a later step than the last
            // crumb's stored vrel; none = step 0), the others by time (traj_display's trailDue)
            bool trailDue;
            if (LD(p, 0) >= TJ_TRAIL_V_LO && LD(p, 0) <= TJ_TRAIL_V_HI)
            {
                double lastStep = tjTrail.Count > 0 ? TrailStep(p, LD(Tjm.Ls(tjTrail[tjTrail.Count - 1]), 1)) : 0;
                trailDue = TrailStep(p, vrel) > lastStep;
            }
            else trailDue = now - tjTrailT >= TJ_TRAIL_S;
            if (trailDue && !offscale && TJ_BUG_ON)
            {
                tjTrailT = now; E.S("tjTrailT", nowS);
                tjTrailDirty = true;
                var nt = new ListValue();
                foreach (var x in tjTrail) nt.Add(x);
                nt.Add(new ListValue(new Structure[] { Tjm.N(rngKm), vrelS }));
                if (nt.Count > TJ_TRAIL_N) nt.RemoveAt(0);
                tjTrail = nt; E.S("tjTrail", nt);
                if (bxr > 0)
                {
                    var nb = new ListValue();
                    foreach (var x in tjBoxTrail) nb.Add(x);
                    nb.Add(new ListValue(new Structure[] { Tjm.N(bxr / 1000), vrelS }));
                    if (nb.Count > TJ_TRAIL_N) nb.RemoveAt(0);
                    tjBoxTrail = nb; E.S("tjBoxTrail", nb);
                }
            }
            if (tjTrailDirty)
            {
                tjTrailDirty = false;
                for (int k = 0; k < TJ_TRAIL_N; k++)
                {
                    if (k < tjTrail.Count)
                    {
                        var c = Tjm.Ls(tjTrail[k]);
                        var tp = Px(p, LD(c, 0), LD(c, 1));
                        if (Fits(tp, TJ_TRAIL_W, fx0, fx1, fx2, fx3))
                        {
                            Op(tjTrailM[k], OP_IMAGE, TJ_TRAIL_IMG);
                            Op(tjTrailM[k], OP_MH, Tjm.N(tp[0] - TJ_TRAIL_W / 2));
                            Op(tjTrailM[k], OP_MV, Tjm.N(tp[1] - TJ_TRAIL_W / 2 - TJ_IMG_DY - Flow(LD(tjTrailI, k))));
                        }
                        else Op(tjTrailM[k], OP_IMAGE, TJ_EMPTY);
                    }
                    else Op(tjTrailM[k], OP_IMAGE, TJ_EMPTY);
                    if (k < tjBoxTrail.Count && Fits(Px(p, LD(Tjm.Ls(tjBoxTrail[k]), 0), LD(Tjm.Ls(tjBoxTrail[k]), 1)), TJ_DOT_W, fx0, fx1, fx2, fx3))
                    {
                        var c = Tjm.Ls(tjBoxTrail[k]);
                        var dp = Px(p, LD(c, 0), LD(c, 1));
                        Op(tjDotM[k], OP_IMAGE, TJ_DOT_IMG);
                        Op(tjDotM[k], OP_MH, Tjm.N(dp[0] - TJ_DOT_W / 2));
                        Op(tjDotM[k], OP_MV, Tjm.N(dp[1] - TJ_DOT_W / 2 - TJ_IMG_DY - Flow(LD(tjDotI, k))));
                    }
                    else Op(tjDotM[k], OP_IMAGE, TJ_EMPTY);
                }
            }
            E.S("tjTrailDirty", tjTrailDirty ? BooleanValue.True : BooleanValue.False);

            // ---- strip markers
            var sa = Tjm.Ls(K(TJ_D, "strip_a"));
            var sd = Tjm.Ls(K(TJ_D, "strip_d"));
            double sTop = LD(sa, 1);
            double sBot = LD(sa, 2);
            double aLo = LD(p, 7), aHi = LD(p, 8);
            double dLo = LD(p, 9), dHi = LD(p, 10);
            bool aArrOff = (aCmd < aLo || aCmd > aHi);
            bool aTriOff = (aAct < aLo || aAct > aHi);
            bool preGuid = dref <= 0;
            double dRefShown = dref;
            if (preGuid) dRefShown = EPR_GUID_DRAG_INIT * 3.28084;
            bool dArrOff = (dRefShown < dLo || dRefShown > dHi);
            bool dTriOff = (dact < dLo || dact > dHi);
            bool aArrLit = (!aArrOff) || lit;
            bool aTriLit = (!aTriOff) || lit;
            bool dArrLit = (!dArrOff) || lit;
            bool dTriLit = (!dTriOff) || lit;
            double aArrY = StripPx(aCmd, aLo, aHi, sTop, sBot);
            double aTriY = StripPx(aAct, aLo, aHi, sTop, sBot);
            double dArrY = StripPx(dRefShown, dLo, dHi, sTop, sBot);
            double dTriY = StripPx(dact, dLo, dHi, sTop, sBot);
            double aX = LD(sa, 0);
            double dX = LD(sd, 0);
            Op(tjAArr, OP_IMAGE, aArrLit ? TJ_AARR_IMG : TJ_EMPTY);
            Op(tjATri, OP_IMAGE, aTriLit ? TJ_ATRI_IMG : TJ_EMPTY);
            Op(tjDArr, OP_IMAGE, dArrLit ? TJ_DARR_IMG : TJ_EMPTY);
            Op(tjDTri, OP_IMAGE, dTriLit ? TJ_DTRI_IMG : TJ_EMPTY);
            double arrH = TJ_ARR_H * TJ_ARR_TIPF;
            double triH = TJ_TRI_H * TJ_TRI_TIPF;
            Op(tjAArr, OP_MH, Tjm.N(aX - TJ_ARR_W)); Op(tjAArr, OP_MV, Tjm.N(aArrY - arrH - TJ_IMG_DY - Flow(tjAArrI)));
            Op(tjATri, OP_MH, Tjm.N(aX - TJ_TRI_W)); Op(tjATri, OP_MV, Tjm.N(aTriY - triH - TJ_IMG_DY - Flow(tjATriI)));
            Op(tjDArr, OP_MH, Tjm.N(aX + (dX - aX))); Op(tjDArr, OP_MV, Tjm.N(dArrY - arrH - TJ_IMG_DY - Flow(tjDArrI)));
            Op(tjDTri, OP_MH, Tjm.N(dX)); Op(tjDTri, OP_MV, Tjm.N(dTriY - triH - TJ_IMG_DY - Flow(tjDTriI)));
            if (preGuid && dArrLit)
            {
                Op(tjInitM, OP_TEXT, S(Col("INIT", TJ_YELLOW)));
                Op(tjInitM, OP_MH, Tjm.N(dX + TJ_ARR_W + 4 * tjS));
                Op(tjInitM, OP_MV, Tjm.N(dArrY - TJ_BR_DY + 6.6 - Flow(tjInitI)));
            }
            else
            {
                Op(tjInitM, OP_TEXT, S(""));
            }

            // ---- readouts
            bool rowsPlaced = Tjm.B(E.G("tjRowsPlaced"));
            var tlr = Tjm.Ls(K(TJ_D, "tl_rows"));
            double tlx = Tjm.D(K(TJ_D, "tl_right")) - 120;
            var tlv = new[] { Math.Round(famU, 2), Math.Round(dRefShown, 1), Math.Round(qbar * 20.885434), Math.Round(azErr, 1),
                Math.Round(deadband, 1) };
            for (int k = 0; k < 5; k++)
            {
                string tx = k == 0 ? Tjm.UBank(famU, famBank) : "" + Tjm.Num(tlv[k]);   // "0.73 | 60"
                if (!Tjm.SEq(tx, Tjm.T(E.L(tjTLtxt, k))) || !rowsPlaced)
                {
                    E.LS(tjTLtxt, k, S(tx));
                    Op(tjTL[k], OP_TEXT, S(Col(tx, TJ_GREEN)));
                }
                if (!rowsPlaced)
                {
                    Op(tjTL[k], OP_MH, Tjm.N(tlx));
                    Op(tjTL[k], OP_MV, Tjm.N(LD(tlr, k) * TJ_V_SCALE - TJ_TL_DY - Flow(LD(tjTLidx, k))));
                }
            }
            var brr = Tjm.Ls(K(TJ_D, "br_rows"));
            double brx = Tjm.D(K(TJ_D, "br_right")) - 120;
            var brv = new[] { Signed(corr), LR(rollShow > 1E8 ? rollref : rollShow), LR(bankCmd), LR(bankAct),
                Mach(qbar, altKm), "" + Tjm.Num(Math.Round(altKm * 3.28084, 1)),
                "" + Tjm.Num(Math.Round(hdot * 3.28084)), Trim(hddot, famRev2), Tjm.Num(Math.Round(nz, 2)) + " G" };
            for (int k = 0; k < 9; k++)
            {
                string tx = "" + brv[k];
                if (!Tjm.SEq(tx, Tjm.T(E.L(tjBRtxt, k))) || !rowsPlaced)
                {
                    E.LS(tjBRtxt, k, S(tx));
                    Op(tjBR[k], OP_TEXT, S(Col(tx, TJ_GREEN)));
                }
                if (!rowsPlaced)
                {
                    Op(tjBR[k], OP_MH, Tjm.N(brx));
                    Op(tjBR[k], OP_MV, Tjm.N(LD(brr, k) * TJ_V_SCALE - TJ_BR_DY - Flow(LD(tjBRidx, k))));
                }
            }
            E.S("tjRowsPlaced", BooleanValue.True);
            string tt = "<b>ENTRY TRAJ</b>";   // the window's title without the panel's number (the page keeps it)
            Op(tjTitle, OP_TEXT, S(uiOn ? tt : Col(tt, TJ_GREEN)));
            if (Has(TJ_D, "clock_px"))
            {
                var cp = Tjm.Ls(K(TJ_D, "clock_px"));
                Op(tjClk, OP_TEXT, S(Col(Clock(met), TJ_GREEN)));
                Op(tjClk, OP_MH, Tjm.N(LD(cp, 0) - 190));
                Op(tjClk, OP_MV, Tjm.N(LD(cp, 1) * TJ_V_SCALE - TJ_CLK_DY - Flow(tjClkI)));
            }
        }
    }

    // the family lookups the page's box and the TAL's bug use (traj_display's tjFamBank / tjGenBank / tjTalRange call them):
    // entry_predict's eprTrajBankRange + eprFamAt over EPR_FAM, lib_tal's talGenBankRange + talGenAt over TAL_GEN and
    // talTrajRange, line for line. eprFamAt's EPR_FAM_HINT is not used or written: kOS's hinted scan finds the first i >= 1
    // with vs[i] <= vr whatever the hint (the samples fall: eprFamStoreMember keeps the falling part), as the scan here does.
    public class TjFam
    {
        readonly TjEnv E;
        ListValue fam, gen;
        public TjFam(TjEnv e) { E = e; }
        public void LoadFam() { fam = Tjm.Ls(E.Raw("EPR_FAM")); }
        public void LoadGen() { gen = Tjm.Ls(E.Raw("TAL_GEN")); }
        static double LD(ListValue l, int i) { return Tjm.D(l[i]); }

        public double FamAt(int mi, double vr, int col)
        {
            var m = Tjm.Ls(fam[mi]);
            var vs = Tjm.Ls(m[1]);
            var cs = Tjm.Ls(m[col]);
            int n = vs.Count;
            if (n == 0) return 0;
            if (vr >= LD(vs, 0)) return LD(cs, 0);
            if (vr <= LD(vs, n - 1)) return LD(cs, n - 1);
            int i = 1;
            while (!(LD(vs, i) <= vr)) i++;
            double f = (LD(vs, i - 1) - vr) / Math.Max(LD(vs, i - 1) - LD(vs, i), 0.000000001);
            return LD(cs, i - 1) + (LD(cs, i) - LD(cs, i - 1)) * f;
        }
        double FamBank(int i) { return LD(Tjm.Ls(fam[i]), 0); }

        // eprTrajBankRange
        public double TrajBankRange(double bank, double vr)
        {
            int n = fam.Count;
            if (n < 2) return 0;
            if (bank <= FamBank(0)) return FamAt(0, vr, 4);
            if (bank >= FamBank(n - 1)) return FamAt(n - 1, vr, 4);
            int i = 1;
            while (!(i >= n))
            {
                if (bank <= FamBank(i))
                {
                    double b0 = FamBank(i - 1);
                    double b1 = FamBank(i);
                    double f = (bank - b0) / Math.Max(b1 - b0, 0.000001);
                    double r0 = FamAt(i - 1, vr, 4);
                    double r1 = FamAt(i, vr, 4);
                    return r0 + (r1 - r0) * f;
                }
                i = i + 1;
            }
            return FamAt(n - 1, vr, 4);
        }

        // talGenAt
        public double GenAt(int mi, double vr)
        {
            var g = Tjm.Ls(gen[mi]);
            var vs = Tjm.Ls(g[1]);
            var rs = Tjm.Ls(g[2]);
            int nv = vs.Count;
            if (vr >= LD(vs, 0)) return LD(rs, 0);
            if (vr <= LD(vs, nv - 1)) return LD(rs, nv - 1);
            double lo = 0;
            double hi = nv - 1;
            while (!(hi - lo <= 1))
            {
                double mid = Math.Floor((lo + hi) / 2);
                if (LD(vs, (int)mid) > vr) lo = mid; else hi = mid;
            }
            double fr = (LD(vs, (int)lo) - vr) / (LD(vs, (int)lo) - LD(vs, (int)hi));
            return LD(rs, (int)lo) + (LD(rs, (int)hi) - LD(rs, (int)lo)) * fr;
        }
        double GenBank(int i) { return LD(Tjm.Ls(gen[i]), 0); }

        // talGenBankRange
        public double GenBankRange(double bank, double vr)
        {
            int ng = gen.Count;
            if (ng < 2) return 0;
            if (bank <= GenBank(0)) return GenAt(0, vr);
            if (bank >= GenBank(ng - 1)) return GenAt(ng - 1, vr);
            int i = 1;
            while (!(i >= ng))
            {
                if (bank <= GenBank(i))
                {
                    double r1 = GenAt(i, vr);
                    if (bank == GenBank(i)) return r1;
                    double b0 = GenBank(i - 1);
                    double fr = (bank - b0) / Math.Max(GenBank(i) - b0, 0.000001);
                    double r0 = GenAt(i - 1, vr);
                    return r0 + (r1 - r0) * fr;
                }
                i = i + 1;
            }
            return GenAt(ng - 1, vr);
        }

        // talTrajRange
        public double TalTrajRange(double vr, double rng)
        {
            int nf = fam.Count;
            if (nf < 2 || gen.Count < 2) return rng;
            double gapMin = Tjm.D(E.Raw("TAL_GEN_GAP_MIN"));
            double ra = FamAt(0, vr, 4);
            if (rng >= ra)
            {
                double ga = GenBankRange(FamBank(0), vr);
                double gb = GenBankRange(FamBank(1), vr);
                return ga + (rng - ra) * (ga - gb) / Math.Max(ra - FamAt(1, vr, 4), gapMin);
            }
            double rz = FamAt(nf - 1, vr, 4);
            if (rng <= rz)
            {
                double gz = GenBankRange(FamBank(nf - 1), vr);
                double gy = GenBankRange(FamBank(nf - 2), vr);
                return gz - (rz - rng) * (gy - gz) / Math.Max(FamAt(nf - 2, vr, 4) - rz, gapMin);
            }
            int i = 1;
            while (!(i >= nf))
            {
                double ri = FamAt(i, vr, 4);
                if (ri <= rng)
                {
                    double rp = FamAt(i - 1, vr, 4);
                    double span = rp - ri;
                    double fr = 0;
                    if (Math.Abs(span) > 0.000000001) fr = (rp - rng) / span;
                    double gp = GenBankRange(FamBank(i - 1), vr);
                    return gp + (GenBankRange(FamBank(i), vr) - gp) * fr;
                }
                i = i + 1;
            }
            return GenBankRange(FamBank(nf - 1), vr);
        }
    }
}
