// lib/lib_grdap.ks's grdTick -- the GRTLS / ECAL / OPS 3 entry DAP's physics tick -- in C#, line for line (the kOS
// line numbers of lib_grdap.ks at d961315 in the comments), as Dap.cs ports lib_dap's dapTick, with kOS's semantics:
//   - every number a double; ARCSIN / ARCTAN2 = Math.X(...) * 180 / PI; MOD(a, b) = a % b; ROUND(x, n) = Math.Round(x, n);
//     MIN / MAX = Math.Min / Max; kOS never holds a -0 (ScalarValue.Create makes every whole value an int), so ARCTAN2's
//     arguments drop the sign of a zero (Atan2d) and a number in a string prints as kOS prints it (KStr);
//   - vectors through KSP's Vector3d as kOS's Vector does (VDOT / VCRS / VXCL / :NORMALIZED / :MAG / + / - / * scalar);
//   - ANGLEAXIS(deg, v) * u exactly as kOS.dll does it (IL-read: Direction.AngleAxis = UnityEngine
//     Quaternion.AngleAxis((float)deg, (Vector3)v); Direction * Vector = Rotation * (Vector3)(Vector3d)u -> new Vector(
//     the Vector3)): the env's AngleAxisMul (the addon passes Unity's own call, the offline VM a managed twin).
// THE STATE IS kOS's: every global grdTick reads is read from kOS at the tick's start (IGrdEnv.Get) and the ones it writes
// go back at the end (Commit; the lists grdRpA / grdRpB / grdI element by element, in place, as kOS's SET rp[k] does).
// Nothing is written before the end: an exception leaves kOS untouched, and kOS's grdTickK can fly any tick.
// THE GAME I/O STAYS kOS's (the staged lib_grdap.ks grdCsIn / grdCsTick): the reads come in as one list (GrdIn: the
// facing, the velocity, the rates, UP, the pressures, FBWPILOT's raw stick, FBWAUTH when due (after grdOmsGmb), the
// guidance's alpha and bank, ssLift in SPLITS phase 8, GR["iphase"] on a log row); out come the three commands (kOS
// hands them to ADDONS:KALS:FBW3), an action code (1 PITCH's button text, 2 ROLL/YAW's, 4 a csv flush, 8 the keyboard
// mode's messages), the text to LOG and the messages (kOS passes each to lib_dap's addMsg, in order).
// THE KEYBOARD MODE (lib_dap's kbAxis) runs here on the raw stick, its state kOS's dKb read at the start and written
// element by element at the end, so kOS's kbAxis (grdTickK, lib_dap's DAP) continues from the same state.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    // the kOS side of a tick: its globals (live, or a dry run's capture), its vectors and kOS's ANGLEAXIS product
    public interface IGrdEnv
    {
        Structure Get(string name);
        void Set(string name, Structure v);
        void ListSet(string name, Structure list, int i, Structure v);     // SET name[i] TO v (in place)
        Vector3d Vec(Structure s);
        Structure MakeVec(Vector3d v);
        Vector3d AngleAxisMul(double deg, Vector3d axis, Vector3d u);      // ANGLEAXIS(deg, axis) * u
    }

    public static class GrdIn       // the reads kOS passes, in this order (the staged lib_grdap.ks grdCsIn)
    {
        public const int TIME = 0, FV = 1, TV = 2, SV = 3, VS = 4, W = 5, UP = 6, PS = 7, DYNP = 8, STK = 9, AUTH = 10,
            AC = 11, BK = 12, SSL = 13, PH = 14, VO = 15, GV = 16, N = 17;   // STK: FBWPILOT's LIST(p, r, y), raw
    }

    public class Grd
    {
        const double PI = 3.1415926535897931;
        const double ATMTOKPA = 101.325;                // CONSTANT:ATMTOKPA

        // ------------------------------------------------------------ kOS's arithmetic (as Dap.cs)
        static double Asin(double x) { return Math.Asin(x) * 180 / PI; }
        static double Z(double x) { return x == 0 ? 0.0 : x; }
        static double Atan2d(double y, double x) { return Math.Atan2(Z(y), Z(x)) * 180 / PI; }
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        static double Abs(double a) { return Math.Abs(a); }
        static double Sqrt(double a) { return Math.Sqrt(a); }
        static double Mod(double a, double b) { return a % b; }
        static double Round(double a, int n) { return Math.Round(a, n); }
        static double Vdot(Vector3d a, Vector3d b) { return Vector3d.Dot(a, b); }
        static Vector3d Vcrs(Vector3d a, Vector3d b) { return Vector3d.Cross(a, b); }
        static Vector3d Vxcl(Vector3d a, Vector3d b) { return Vector3d.Exclude(a, b); }
        static Vector3d Mul(Vector3d a, double d) { return new Vector3d(a.x * d, a.y * d, a.z * d); }
        static Vector3d Div(Vector3d a, double d) { return new Vector3d(a.x / d, a.y / d, a.z / d); }   // kOS's v / s

        // a number as kOS shows it in a string: ScalarValue.Create (an int when whole and in range) then its ToString
        public static string KStr(double d)
        {
            if (d > -2147483648.0 && d < 2147483647.0 && !double.IsNaN(d))
            {
                int i = Convert.ToInt32(d);
                if (d == (double)i) return i.ToString();
            }
            return d.ToString();
        }
        static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue();
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value ? 1 : 0;
            throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
        }
        static bool Bool(Structure s)
        {
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue() != 0;
            throw new InvalidCastException("not a boolean: " + (s == null ? "null" : s.GetType().Name));
        }
        static double Fin(double x, string n)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("non-finite " + n);
            return x;
        }
        static Vector3d FinV(Vector3d v, string n) { Fin(v.x, n); Fin(v.y, n); Fin(v.z, n); return v; }

        // a schedule / table list converted once per list object (a SET to a new list converts again)
        readonly Dictionary<Structure, double[]> schCache = new Dictionary<Structure, double[]>();
        double[] Sch(Structure s)
        {
            double[] t;
            if (schCache.TryGetValue(s, out t)) return t;
            var l = (ListValue)s;
            t = new double[l.Count];
            for (int j = 0; j < l.Count; j++) t[j] = Num(l[j]);
            if (schCache.Count > 64) schCache.Clear();
            schCache[s] = t;
            return t;
        }

        // ------------------------------------------------------------ the globals (read at the start, written at the end)
        public const string KB = "dKb";                // lib_dap's keyboard-mode state: 3 lists of 8, written element by element
        public static readonly string[] KB_AX = { "dKb[0]", "dKb[1]", "dKb[2]" };

        // constants (lib_grdap's GRD_*, lib_dap's)
        double GRD_T_P, GRD_T_R, GRD_T_Y, GRD_A_MIN, GRD_KA, GRD_KPHI, GRD_KB, GRD_QLIM, GRD_PLIM, GRD_AUTH_N, GRD_LOG_EVERY,
            GRD_FLUSH, GRD_TI, GRD_I_MAX, GRD_AUTH_K, GRD_AUTH_Q0, GRD_AUTH_Q1, GRD_ENT_TAU, GRD_YJA, GRD_WARP_KT, GRD_WARP_KY, GRD_AUTH_KR,
            GRD_AREF_TM, GRD_AREF_FF, GRD_AREF_FZ,
            DAP_RAMP_HOLD, PATH_TAU, STICK_P_SIGN, STICK_R_SIGN, RHC_FULL, P_DB, R_DB, KDEMLIN, PKQ, DEMAX, CSS_RMAX,
            GRD_R_DB, GRD_CAP_W, GRD_CAP_T, KB_MODE, KB_FULL, KB_RISE, KB_MIN, KB_TAP, KB_STEPS, KB_STICK_T;
        double[] GRD_YJR_Q, GRD_YJR_V, GRD_YJR_EM, GRD_YJR_EV, GRD_YJR_EB, TG_CSS_P_GAIN, TG_CSS_R_KL, TG_CSS_R_KP, TG_CSS_R_DMAX, TG_CSS_R_GAIN;
        // the state
        bool GRD_YJR_E_ENT;
        bool grdSs, dReqP, dReqR, grdCssP, grdCssR, grdHoldP, grdHoldR, grdBfOn, grdEnt, grdAmOn;
        // The kOS refusal of AUTO (flfxSwAutoLost("ENTRY", "ENTRY")) for the C# entry DAP: SW 01 ENTRY at once, SW 02 ENTRY after SW_GD_LOST_S
        // (lib_flfx's FLFX_SWMASK, as Dap.cs's SwDapLost); SW 02 ALPHA MOD = the pitch axis only. o_dReqP / o_dReqR = kOS's values at the load.
        int SW_MASK;
        double SW_GD_LOST_S, swGdT0 = -1;
        bool o_dReqP, o_dReqR;
        double grdT, grdN, grdAk, grdAkR, grdYjr, grdAHold, grdBHold, grdCapT0, grdCapQT0, grdBf, grdNzM, grdBufN, grdAm;
        bool o_grdCssP, o_grdCssR, o_grdHoldP, o_grdHoldR, o_grdBfOn, o_grdAmOn;
        double o_grdAk, o_grdAkR, o_grdYjr, o_grdAHold, o_grdBHold, o_grdCapT0, o_grdCapQT0, o_grdBf, o_grdNzM, o_grdBufN, o_grdAm;
        Vector3d grdVoP, grdVhP, grdPath;
        Structure grdAuth, grdAuthNew, grdI, grdCsvS;
        double[] grdAuthD = new double[3];
        double[] grdIv = new double[3];
        bool[] grdIw = new bool[3];
        string grdCsv, grdBuf, o_grdBuf;
        // a ramp's list (grdRpA / grdRpB): LIST(from, to, published at, the interval); rp[1] keeps kOS's object (SET rp[1] TO nv)
        class Ramp
        {
            public string name;
            public Structure list, r1s;
            public double r0, r1, r2, r3;
            public bool w;                  // written (SET rp[3], rp[0], rp[1], rp[2]: all four, in kOS's order)
        }
        readonly Ramp rpA = new Ramp { name = "grdRpA" }, rpB = new Ramp { name = "grdRpB" };
        // the keyboard mode (lib_dap's dKb, per axis): [0] on, [1] the output, [2] the last raw input, [3] the last time,
        // [4] the full-throw steps, [5] the in-between s, [6] the press's start, [7] the press's sign; kbV the values
        // ([0] as 1 / 0), kbW the elements written, kbO the kOS object a write keeps (the raw input, the time)
        Structure kbAxn;
        readonly Structure[] kbL = new Structure[3];
        readonly double[][] kbV = { new double[8], new double[8], new double[8] };
        readonly bool[][] kbW = { new bool[8], new bool[8], new bool[8] };
        readonly Structure[][] kbO = { new Structure[8], new Structure[8], new Structure[8] };
        ListValue kbMsg;

        double G(IGrdEnv e, string n) { return Num(e.Get(n)); }
        bool B(IGrdEnv e, string n) { return Bool(e.Get(n)); }
        void LoadRamp(IGrdEnv e, Ramp r)
        {
            r.list = e.Get(r.name);
            var l = (ListValue)r.list;
            r.r0 = Num(l[0]); r.r1s = l[1]; r.r1 = Num(l[1]); r.r2 = Num(l[2]); r.r3 = Num(l[3]);
            r.w = false;
        }

        void Load(IGrdEnv e)
        {
            GRD_T_P = G(e, "GRD_T_P"); GRD_T_R = G(e, "GRD_T_R"); GRD_T_Y = G(e, "GRD_T_Y"); GRD_A_MIN = G(e, "GRD_A_MIN");
            GRD_KA = G(e, "GRD_KA"); GRD_KPHI = G(e, "GRD_KPHI"); GRD_KB = G(e, "GRD_KB"); GRD_QLIM = G(e, "GRD_QLIM");
            GRD_PLIM = G(e, "GRD_PLIM"); GRD_AUTH_N = G(e, "GRD_AUTH_N"); GRD_LOG_EVERY = G(e, "GRD_LOG_EVERY");
            GRD_FLUSH = G(e, "GRD_FLUSH"); GRD_TI = G(e, "GRD_TI"); GRD_I_MAX = G(e, "GRD_I_MAX"); GRD_AUTH_K = G(e, "GRD_AUTH_K");
            GRD_AUTH_Q0 = G(e, "GRD_AUTH_Q0"); GRD_AUTH_Q1 = G(e, "GRD_AUTH_Q1"); GRD_ENT_TAU = G(e, "GRD_ENT_TAU");
            GRD_YJA = G(e, "GRD_YJA"); GRD_WARP_KT = G(e, "GRD_WARP_KT"); GRD_WARP_KY = G(e, "GRD_WARP_KY"); GRD_AUTH_KR = G(e, "GRD_AUTH_KR");
            GRD_AREF_TM = G(e, "GRD_AREF_TM"); GRD_AREF_FF = G(e, "GRD_AREF_FF"); GRD_AREF_FZ = G(e, "GRD_AREF_FZ");
            GRD_YJR_Q = Sch(e.Get("GRD_YJR_Q")); GRD_YJR_V = Sch(e.Get("GRD_YJR_V"));
            GRD_YJR_EM = Sch(e.Get("GRD_YJR_EM")); GRD_YJR_EV = Sch(e.Get("GRD_YJR_EV")); GRD_YJR_EB = Sch(e.Get("GRD_YJR_EB"));
            GRD_YJR_E_ENT = B(e, "GRD_YJR_E_ENT");
            DAP_RAMP_HOLD = G(e, "DAP_RAMP_HOLD"); PATH_TAU = G(e, "PATH_TAU");
            STICK_P_SIGN = G(e, "STICK_P_SIGN"); STICK_R_SIGN = G(e, "STICK_R_SIGN"); RHC_FULL = G(e, "RHC_FULL");
            P_DB = G(e, "P_DB"); R_DB = G(e, "R_DB"); KDEMLIN = G(e, "KDEMLIN"); PKQ = G(e, "PKQ"); DEMAX = G(e, "DEMAX");
            CSS_RMAX = G(e, "CSS_RMAX");
            GRD_R_DB = G(e, "GRD_R_DB"); GRD_CAP_W = G(e, "GRD_CAP_W"); GRD_CAP_T = G(e, "GRD_CAP_T");
            KB_MODE = G(e, "KB_MODE"); KB_FULL = G(e, "KB_FULL"); KB_RISE = G(e, "KB_RISE"); KB_MIN = G(e, "KB_MIN");
            KB_TAP = G(e, "KB_TAP"); KB_STEPS = G(e, "KB_STEPS"); KB_STICK_T = G(e, "KB_STICK_T"); kbAxn = e.Get("KB_AXN");
            TG_CSS_P_GAIN = Sch(e.Get("TG_CSS_P_GAIN")); TG_CSS_R_KL = Sch(e.Get("TG_CSS_R_KL"));
            TG_CSS_R_KP = Sch(e.Get("TG_CSS_R_KP")); TG_CSS_R_DMAX = Sch(e.Get("TG_CSS_R_DMAX"));
            TG_CSS_R_GAIN = Sch(e.Get("TG_CSS_R_GAIN"));

            grdSs = B(e, "grdSs"); o_dReqP = dReqP = B(e, "dReqP"); o_dReqR = dReqR = B(e, "dReqR");
            SW_MASK = SwGate.Read(n => e.Get(n));                           // The SW 01 / SW 02 bits (0 = none, or an older script)
            SW_GD_LOST_S = SwGate.GdLostS(n => e.Get(n));
            grdT = G(e, "grdT"); grdN = G(e, "grdN");
            grdVoP = e.Vec(e.Get("grdVoP")); grdVhP = e.Vec(e.Get("grdVhP")); grdPath = e.Vec(e.Get("grdPath"));
            grdAuth = e.Get("grdAuth"); grdAuthNew = null;
            var al = (ListValue)grdAuth;
            for (int i = 0; i < 3; i++) grdAuthD[i] = Num(al[i]);
            o_grdAk = grdAk = G(e, "grdAk"); o_grdAkR = grdAkR = G(e, "grdAkR"); o_grdYjr = grdYjr = G(e, "grdYjr");
            o_grdCssP = grdCssP = B(e, "grdCssP"); o_grdCssR = grdCssR = B(e, "grdCssR");
            o_grdHoldP = grdHoldP = B(e, "grdHoldP"); o_grdHoldR = grdHoldR = B(e, "grdHoldR");
            o_grdAHold = grdAHold = G(e, "grdAHold"); o_grdBHold = grdBHold = G(e, "grdBHold");
            o_grdCapT0 = grdCapT0 = G(e, "grdCapT0"); o_grdCapQT0 = grdCapQT0 = G(e, "grdCapQT0");
            LoadRamp(e, rpA); LoadRamp(e, rpB);
            o_grdBf = grdBf = G(e, "grdBf"); o_grdBfOn = grdBfOn = B(e, "grdBfOn");
            o_grdAm = grdAm = G(e, "grdAm"); o_grdAmOn = grdAmOn = B(e, "grdAmOn"); grdEnt = B(e, "grdEnt");
            grdI = e.Get("grdI");
            var il = (ListValue)grdI;
            for (int i = 0; i < 3; i++) { grdIv[i] = Num(il[i]); grdIw[i] = false; }
            o_grdNzM = grdNzM = G(e, "grdNzM");
            grdCsvS = e.Get("grdCsv"); grdCsv = grdCsvS.ToString();
            o_grdBuf = grdBuf = e.Get("grdBuf").ToString();
            o_grdBufN = grdBufN = G(e, "grdBufN");
            var kl = (ListValue)e.Get(KB);
            for (int i = 0; i < 3; i++)
            {
                kbL[i] = kl[i];
                var l = (ListValue)kbL[i];
                for (int k = 0; k < 8; k++) { kbV[i][k] = Num(l[k]); kbW[i][k] = false; kbO[i][k] = null; }
            }
            kbMsg = new ListValue();
        }

        // ------------------------------------------------------------ lib_dap's helpers (as Dap.cs; lib_dap.ks l.671-875)
        double linM(double x, double xLo, double vLo, double xHi, double vHi)
        {
            if (x <= xLo) { return vLo; }
            if (x >= xHi) { return vHi; }
            return vLo + (vHi - vLo) * (x - xLo) / (xHi - xLo);
        }
        double linS(double x, double[] sch) { return linM(x, sch[0], sch[1], sch[2], sch[3]); }
        double clampV(double x, double lim) { return Max(-lim, Min(lim, x)); }
        double dapMach(double ps0, double dynp)   // ps0 = ALTITUDEPRESSURE(ALTITUDE), dynp = DYNAMICPRESSURE
        {
            double ps = ps0 * ATMTOKPA * 1000;
            if (ps < 0.0001) { return 0; }
            double qd = dynp * ATMTOKPA * 1000;
            return Sqrt(Max(2 * qd / (1.4 * ps), 0));
        }
        double shapeP(double g, double M)
        {
            double x = Abs(g) * RHC_FULL - P_DB;
            if (x <= 0) { return 0; }
            double s = Min(DEMAX, (KDEMLIN + PKQ * x) * x) * linS(M, TG_CSS_P_GAIN);
            if (g < 0) { return -s; }
            return s;
        }
        double shapeR(double g, double M)
        {
            double x = Abs(g) * RHC_FULL - R_DB;
            if (x <= 0) { return 0; }
            double kl = linS(M, TG_CSS_R_KL);
            double kp = linS(M, TG_CSS_R_KP);
            double dmax = linS(M, TG_CSS_R_DMAX);
            double s = Min(dmax, (kl + kp * x) * x) * linS(M, TG_CSS_R_GAIN);
            if (g < 0) { return -s; }
            return s;
        }
        double grdStkR(double g)                  // lib_grdap's: the roll stick past GRD_R_DB onto lib_dap's detent
        {
            double x = Abs(g) * RHC_FULL;
            if (x <= GRD_R_DB) { return 0; }
            double y = (R_DB + (x - GRD_R_DB) * (RHC_FULL - R_DB) / (RHC_FULL - GRD_R_DB)) / RHC_FULL;
            if (g < 0) { return -y; }
            return y;
        }
        double cssRx(double g, double M)
        {
            double x = Min(1, (Abs(g) * RHC_FULL - R_DB) / (RHC_FULL - R_DB));
            if (x <= 0) { return 0; }
            double e = Max(0, CSS_RMAX - shapeR(1, M)) * x * x * x;
            if (g < 0) { return -e; }
            return e;
        }

        // lib_dap's kbAxis: one axis through the keyboard mode (KB_*); the raw input back while the axis reads as a stick.
        // tn is the tick's TIME:SECONDS (GrdIn.TIME, kOS's first read of the tick; kOS's kbAxis reads TIME:SECONDS itself, the
        // same value unless the tick straddles a physics frame). addMsg's text goes to kbMsg for kOS's addMsg.
        void kbSet(int i, int k, double v) { kbV[i][k] = v; kbW[i][k] = true; kbO[i][k] = null; }
        void kbSetO(int i, int k, double v, Structure o) { kbV[i][k] = v; kbW[i][k] = true; kbO[i][k] = o; }
        void addMsg(string s) { kbMsg.Add(new StringValue(s)); }
        double kbAxis(int i, Structure rawS, Structure tS)
        {
            double raw = Num(rawS);
            if (KB_MODE == 0) { return raw; }
            double[] s = kbV[i];
            double tn = Num(tS);
            double dt = 0;
            if (s[3] > 0) { dt = Max(0, Min(0.2, tn - s[3])); }
            kbSetO(i, 3, tn, tS);
            double a = Abs(raw);
            bool atStop = a < 0.0001 || Abs(a - 1) < 0.0001;
            if (atStop && Abs(raw - s[2]) > 0.9) { kbSet(i, 4, s[4] + 1); kbSet(i, 5, 0); }
            if (!atStop) { kbSet(i, 5, s[5] + dt); }
            kbSetO(i, 2, raw, rawS);
            if (KB_MODE == 1)
            {
                if (s[0] == 0 && s[4] >= KB_STEPS)
                {
                    kbSet(i, 0, 1);
                    kbSet(i, 5, 0);
                    addMsg(((ListValue)kbAxn)[i].ToString() + " KEYBOARD: a held key builds to " + KStr(Math.Round(100 * KB_FULL)) + " % in " + KStr(KB_RISE) + " s, a tap nudges");
                }
                if (s[0] != 0 && s[5] > KB_STICK_T)
                {
                    kbSet(i, 0, 0);
                    kbSet(i, 4, 0);
                    kbSet(i, 7, 0);
                    kbSet(i, 1, 0);
                    addMsg(((ListValue)kbAxn)[i].ToString() + " STICK: the raw input");
                }
                if (s[0] == 0)
                {
                    kbSet(i, 5, Min(s[5], KB_STICK_T));
                    return raw;
                }
            }
            double sg = 0;
            if (a >= 0.5) { sg = raw > 0 ? 1 : -1; }
            if (sg != 0)
            {
                if (sg != s[7])
                {
                    kbSetO(i, 6, tn, tS);
                    kbSet(i, 7, sg);
                    kbSet(i, 1, sg * KB_MIN);
                }
                else
                {
                    kbSet(i, 1, sg * Min(KB_FULL, Abs(s[1]) + (KB_FULL - KB_MIN) / KB_RISE * dt));
                }
            }
            else if (s[7] == 0 || tn - s[6] >= KB_TAP)
            {
                kbSet(i, 7, 0);
                kbSet(i, 1, 0);
            }
            return s[1];
        }

        // ------------------------------------------------------------ lib_grdap's helpers
        // l.163 grdRamp: a published value ramped over its publication interval, the rate held to DAP_RAMP_HOLD intervals
        void grdRamp(Ramp rp, Structure nvS, double t, out double v, out double rate)
        {
            double nv = Num(nvS);
            if (nv != rp.r1)
            {
                double f0 = (t - rp.r2) / rp.r3;
                double x0 = rp.r0 + (rp.r1 - rp.r0) * Min(1, Max(0, f0));
                rp.r3 = Min(0.5, Max(0.04, t - rp.r2));
                rp.r0 = x0;
                rp.r1 = nv; rp.r1s = nvS;
                rp.r2 = t;
                rp.w = true;
            }
            double f = (t - rp.r2) / rp.r3;
            if (f >= DAP_RAMP_HOLD) { v = rp.r1; rate = 0; return; }
            v = rp.r0 + (rp.r1 - rp.r0) * Min(1, Max(0, f));
            rate = (rp.r1 - rp.r0) / rp.r3;
        }
        // l.178 grdBankNow: the bank about the velocity, + = LEFT
        double grdBankNow(Vector3d vh, Vector3d tv)
        {
            Vector3d upP = Vxcl(vh, upV);
            Vector3d topP = Vxcl(vh, tv);
            if (upP.magnitude < 0.01 || topP.magnitude < 0.01) { return 0; }
            return Atan2d(Vdot(vh, Vcrs(upP, topP)), Vdot(upP, topP));
        }
        // grdSsRoll: SPLITS phase 8, the roll about the velocity from slP (ssLift's, across the velocity) to the top, + = LEFT
        double grdSsRoll(Vector3d vh, Vector3d tv, Vector3d slP)
        {
            Vector3d topP = Vxcl(vh, tv);
            if (slP.magnitude < 0.01 || topP.magnitude < 0.01) { return 0; }
            return Atan2d(Vdot(vh, Vcrs(slP, topP)), Vdot(slP, topP));
        }
        // l.437 grdPI: one axis's command: the P + the integral, clamped; the integral frozen against the clamp
        double grdPI(int i, double er, double kc, double dtt, bool frz = false)
        {
            double uu = er * kc + grdIv[i];
            if (!frz && !(Abs(uu) >= 1 && uu * er > 0)) { grdIv[i] = clampV(grdIv[i] + er * kc * dtt / GRD_TI, GRD_I_MAX); grdIw[i] = true; }
            return clampV(er * kc + grdIv[i], 1);
        }
        // l.445 grdYjrAt: the yaw jets' roll as a share of the aileron's at the q now; in the FAR entry (and the FAR
        // GRTLS unless GRD_YJR_E_ENT) blended to GRD_YJR_EV by Mach
        double grdYjrAt(double mach)
        {
            double qk = dynpNow * ATMTOKPA;
            int n = GRD_YJR_Q.Length;
            double v = GRD_YJR_V[n - 1];
            if (qk <= GRD_YJR_Q[0]) { v = GRD_YJR_V[0]; }
            else
            {
                for (int i = 1; i < n; i++)
                {
                    if (qk < GRD_YJR_Q[i])
                    {
                        v = GRD_YJR_V[i - 1] + (GRD_YJR_V[i] - GRD_YJR_V[i - 1]) * (qk - GRD_YJR_Q[i - 1]) / (GRD_YJR_Q[i] - GRD_YJR_Q[i - 1]);
                        break;
                    }
                }
            }
            if ((grdEnt || !GRD_YJR_E_ENT) && GRD_YJR_EM.Length > 0)
            {
                double w = Math.Max(0, Math.Min(1, (mach - GRD_YJR_EB[0]) / (GRD_YJR_EB[1] - GRD_YJR_EB[0])));
                v += (grdLinAt(GRD_YJR_EM, GRD_YJR_EV, mach) - v) * w;
            }
            return v;
        }
        // grdLinAt: v on x (its knots, rising) at m: linear, held past the ends
        static double grdLinAt(double[] x, double[] v, double m)
        {
            if (m <= x[0]) return v[0];
            for (int i = 1; i < x.Length; i++)
                if (m <= x[i]) return v[i - 1] + (v[i] - v[i - 1]) * (m - x[i - 1]) / (x[i] - x[i - 1]);
            return v[x.Length - 1];
        }
        // l.459 grdAuthK: FBWAUTH's share the vehicle has
        double grdAuthK(double kk)
        {
            double qk = dynpNow * ATMTOKPA;
            return 1 - (1 - kk) * Max(0, Min(1, (qk - GRD_AUTH_Q0) / (GRD_AUTH_Q1 - GRD_AUTH_Q0)));
        }

        // ------------------------------------------------------------ ONE TICK (lib_grdap.ks l.305-433)
        Vector3d upV;
        double dynpNow;
        double cmdPo, cmdRo, cmdYo;
        int act;
        string flush;
        double wc0, wc1, wc2;

        // Returns LIST(cmdP, cmdR, cmdY (for FBW3), the action code (1 PITCH text, 2 ROLL/YAW text, 4 LOG, 8 messages, 16 / 32: press the
        // PITCH / ROLL/YAW button for a forced CSS), the text
        // to LOG, the keyboard mode's messages (a LIST of strings, kOS's addMsg each in order)).
        public ListValue Tick(IGrdEnv e, ListValue inp)
        {
            if (inp.Count != GrdIn.N) throw new ArgumentException("GRDTICK wants " + GrdIn.N + " reads, got " + inp.Count);
            Load(e);
            act = 0;
            flush = "";
            Body(e, inp);
            CheckFinite();
            Commit(e);
            var o = new ListValue();
            o.Add(ScalarValue.Create(cmdPo));
            o.Add(ScalarValue.Create(cmdRo));
            o.Add(ScalarValue.Create(cmdYo));
            o.Add(ScalarValue.Create(act));
            o.Add(new StringValue(flush));
            o.Add(kbMsg);
            return o;
        }

        bool SwEntryLost(double now)                                        // flfxSwAutoLost("ENTRY", "ENTRY")
        {
            if ((SW_MASK & SwGate.SW01_ENTRY) != 0) { return true; }
            if ((SW_MASK & SwGate.SW02_ENTRY) == 0) { swGdT0 = -1; return false; }
            if (swGdT0 < 0) { swGdT0 = now; }
            return now - swGdT0 >= SW_GD_LOST_S;
        }

        void Body(IGrdEnv env, ListValue inp)
        {
            Structure tS = inp[GrdIn.TIME];
            double t = Num(tS);                                             // l.306
            double dtt = Max(t - grdT, 0.001);
            grdT = t;
            grdN = grdN + 1;
            Vector3d fv = env.Vec(inp[GrdIn.FV]);
            Vector3d tv = env.Vec(inp[GrdIn.TV]);
            Vector3d sv = env.Vec(inp[GrdIn.SV]);
            Vector3d kp = Mul(sv, -1);                                      // l.313: the nose-up axis
            Vector3d vs = env.Vec(inp[GrdIn.VS]);
            Vector3d vh = vs.magnitude > 1 ? vs.normalized : fv;
            double aoa = Atan2d(-Vdot(vh, tv), Vdot(vh, fv));
            double beta = Asin(Max(-1, Min(1, Vdot(vh, sv))));
            Vector3d w = Mul(env.Vec(inp[GrdIn.W]), 57.2958);              // l.318
            if (grdVhP.magnitude > 0.5)
            {
                Vector3d pr = Mul(Vcrs(grdVhP, vh), 57.2958 / dtt);
                if (pr.magnitude < 30) { grdPath = grdPath + Mul(pr - grdPath, Min(1, dtt / PATH_TAU)); }
            }
            grdVhP = vh;
            Vector3d vo = env.Vec(inp[GrdIn.VO]);                          // the HUD's Nz: the sensed acceleration along the top
            if (grdVoP.magnitude > 0.5)
            {
                double nz = Vdot(Div(vo - grdVoP, dtt) - env.Vec(inp[GrdIn.GV]), tv) / 9.80665;
                if (Math.Abs(nz) < 10) { grdNzM = grdNzM + (nz - grdNzM) * Min(1, dtt / PATH_TAU); }
            }
            grdVoP = vo;
            upV = env.Vec(inp[GrdIn.UP]);
            dynpNow = Num(inp[GrdIn.DYNP]);
            double mach = dapMach(Num(inp[GrdIn.PS]), dynpNow);           // l.324
            if (Mod(grdN, GRD_AUTH_N) == 0)                                 // l.325 (grdOmsGmb: kOS's, before FBWAUTH)
            {
                var au = inp[GrdIn.AUTH] as ListValue;
                if (au == null) throw new ArgumentException("GRDTICK: no FBWAUTH on an authority tick (grdN " + KStr(grdN) + ")");
                grdAuthNew = au;
                for (int i = 0; i < 3; i++) grdAuthD[i] = Num(au[i]);
                grdAk = grdAuthK(GRD_AUTH_K);
                grdAkR = grdAuthK(GRD_AUTH_KR);
                grdYjr = grdYjrAt(mach);
            }
            var sk = inp[GrdIn.STK] as ListValue;                          // l.332: the pilot's p, r, y, the keyboard mode
            if (sk == null || sk.Count < 3) throw new ArgumentException("GRDTICK: no FBWPILOT list");
            double stk0 = kbAxis(0, sk[0], tS);
            double stk1 = kbAxis(1, sk[1], tS);
            double stk2 = kbAxis(2, sk[2], tS);
            if (kbMsg.Count > 0) { act |= 8; }
            // The twin of lib_grdap's grdTickK block (l.566) for the C# path, which skipped it:
            // the AUTO axes stay CSS while SW 01 ENTRY holds (or SW 02 ENTRY past SW_GD_LOST_S); the want is written back to kOS (Commit), and act
            // 16 / 32 press the PITCH / ROLL/YAW button when its want was not CSS yet (a crew click on AUTO is pressed back on the next tick).
            bool swLost = SwEntryLost(t);
            if (swLost)
            {
                if (!dReqP) { act |= 16; }
                if (!dReqR) { act |= 32; }
                dReqP = true; dReqR = true;
            }
            else if ((SW_MASK & SwGate.SW02_ALPHA) != 0)                     // SW 02 ALPHA MOD: the pitch axis only
            {
                if (!dReqP) { act |= 16; }
                dReqP = true;
            }
            if (dReqP != grdCssP)                                           // l.335
            {
                grdCssP = dReqP;
                grdHoldP = false;
                grdCapQT0 = -1;
                act |= 1;
            }
            if (dReqR != grdCssR)
            {
                grdCssR = dReqR;
                grdHoldR = false;
                grdCapT0 = -1;
                act |= 2;
            }
            double ra0, ra1, rb0, rb1;                                      // l.346
            grdRamp(rpA, inp[GrdIn.AC], t, out ra0, out ra1);
            grdRamp(rpB, inp[GrdIn.BK], t, out rb0, out rb1);
            double qs = 0;
            double ps = 0;
            if (grdCssP)                                                    // l.350
            {
                qs = STICK_P_SIGN * shapeP(stk0, mach);
                if (qs != 0) { grdHoldP = false; grdCapQT0 = -1; }
                else if (!grdHoldP)
                {
                    if (grdCapQT0 < 0) { grdCapQT0 = t; }
                    grdAHold = aoa;
                    if (Abs(Vdot(w - grdPath, kp)) < GRD_CAP_W || t - grdCapQT0 > GRD_CAP_T) { grdHoldP = true; grdCapQT0 = -1; }
                }
            }
            Vector3d slP = new Vector3d(0, 0, 0);                          // SPLITS phase 8: ssLift across the velocity
            if (grdSs)
            {
                var sl = inp[GrdIn.SSL];
                if (sl is ScalarValue) throw new ArgumentException("GRDTICK: no ssLift in SPLITS phase 8");
                slP = Vxcl(vh, env.Vec(sl));
            }
            if (grdCssR)
            {
                double gr = grdStkR(stk1);
                ps = STICK_R_SIGN * shapeR(gr, mach);
                if (ps != 0) { ps = ps + STICK_R_SIGN * cssRx(gr, mach); }
                if (ps != 0) { grdHoldR = false; grdCapT0 = -1; }
                else if (!grdHoldR)
                {
                    if (grdCapT0 < 0) { grdCapT0 = t; }
                    grdBHold = grdSs ? grdSsRoll(vh, tv, slP) : grdBankNow(vh, tv);
                    if (Abs(Vdot(w, vh)) < GRD_CAP_W || t - grdCapT0 > GRD_CAP_T) { grdHoldR = true; grdCapT0 = -1; }
                }
            }
            double ac = (grdCssP && qs == 0) ? grdAHold : ra0;             // l.361
            double acd = grdCssP ? 0 : ra1;
            bool frzP = false;
            if (grdEnt && GRD_AREF_TM > 0 && !grdCssP)                   // the entry's alpha reference model
            {
                if (!grdAmOn) { grdAm = ac; grdAmOn = true; }
                double pf = clampV(acd, GRD_AREF_FF);
                double da = ac - grdAm;
                double ka = Min(1, dtt / GRD_AREF_TM);
                grdAm = grdAm + pf * dtt + da * ka;
                acd = pf + (da - da * ka) / GRD_AREF_TM;
                frzP = Abs(acd - pf) > GRD_AREF_FZ;
                ac = grdAm;
            }
            else { grdAmOn = false; }
            Vector3d lt = new Vector3d(0, 0, 0);
            double bkc = rb0;
            double bkd = rb1;
            if (!grdSs && GRD_ENT_TAU > 0)                                  // l.366
            {
                if (!grdBfOn) { grdBf = bkc; grdBfOn = true; }
                double db = Mod(bkc - grdBf + 540, 360) - 180;
                grdBf = grdBf + db * Min(1, dtt / GRD_ENT_TAU);
                bkd = (db - db * Min(1, dtt / GRD_ENT_TAU)) / GRD_ENT_TAU;
                bkc = grdBf;
            }
            if (grdCssR)
            {
                bkc = grdBHold;
                bkd = 0;
                grdBfOn = false;
            }
            if (grdSs && !grdCssR)                                          // l.378
            {
                lt = slP;
            }
            else if (grdSs)                                                 // CSS in phase 8: the held roll from ssLift
            {
                if (slP.magnitude > 0.01) { lt = env.AngleAxisMul(bkc, vh, slP.normalized); }
            }
            else
            {
                Vector3d upP = Vxcl(vh, upV);
                if (upP.magnitude > 0.01) { lt = env.AngleAxisMul(bkc, vh, upP.normalized); }
            }
            Vector3d topP = Vxcl(vh, tv);                                   // l.384
            double eps = 0;
            if (lt.magnitude > 0.01 && topP.magnitude > 0.01) { eps = Atan2d(Vdot(vh, Vcrs(topP, lt)), Vdot(topP, lt)); }
            double kc = Min(1, GRD_WARP_KY * GRD_T_P / dtt);               // the yaw's warp cap
            double kcw = Min(1, GRD_WARP_KT * GRD_T_P / dtt);
            double qa = clampV(GRD_KA * kcw * (ac - aoa) + acd, GRD_QLIM);
            double rv = clampV(GRD_KPHI * kcw * eps + bkd, GRD_PLIM);
            if (grdCssR && ps != 0) { rv = ps; }
            Vector3d om = Mul(kp, qa) + Mul(vh, rv) + Mul(tv, GRD_KB * kcw * beta) + grdPath;   // l.392
            double qc = Vdot(om, kp);
            if (grdCssP && qs != 0) { qc = qs; }
            double pc = Vdot(om, fv);
            double rc = Vdot(om, tv);
            double wq = Vdot(w, kp);
            double wp = Vdot(w, fv);
            double wr = Vdot(w, tv);
            wc0 = 0 - pc; wc1 = qc; wc2 = rc;                              // l.400 grdWc
            double cmdP = grdPI(0, (qc - wq) / (GRD_T_P * Max(grdAuthD[0] * grdAk, GRD_A_MIN)), kcw, dtt, frzP);
            double cmdR = grdPI(1, -(pc - wp) / (GRD_T_R * Max(grdAuthD[1] * grdAkR, GRD_A_MIN)), kcw, dtt);
            double auY = Max(grdAuthD[2] * grdAk, GRD_A_MIN);
            auY = Max(auY, GRD_YJA);
            double cmdY = grdPI(2, (rc - wr) / (GRD_T_Y * auY), kc, dtt);
            if (!grdSs) { cmdR = clampV(cmdR + grdYjr * cmdY, 1); }        // l.406
            cmdPo = cmdP; cmdRo = cmdR; cmdYo = cmdY;                      // l.411 grdU, l.412 FBW3 (kOS's)
            if (grdCsv != "" && Mod(grdN, GRD_LOG_EVERY) == 0)            // l.413
            {
                Structure ph = inp[GrdIn.PH];
                grdBuf = grdBuf + (grdBufN == 0 ? "" : "\n") + KStr(Round(t, 2)) + "," + KStr(Round(mach, 3)) + ","
                    + KStr(Round(dynpNow * ATMTOKPA, 3)) + "," + ph.ToString() + "," + (grdSs ? "1" : "0") + ","
                    + (grdCssP ? "1" : "0") + "," + (grdCssR ? "1" : "0") + "," + (grdHoldP ? "1" : "0") + ","
                    + (grdHoldR ? "1" : "0") + "," + KStr(Round(aoa, 3)) + "," + KStr(Round(ac, 3)) + "," + KStr(Round(acd, 3)) + ","
                    + KStr(Round(beta, 3)) + "," + KStr(Round(grdBankNow(vh, tv), 2)) + "," + KStr(Round(bkc, 2)) + "," + KStr(Round(bkd, 3)) + ","
                    + KStr(Round(eps, 3)) + "," + KStr(Round(qc, 3)) + "," + KStr(Round(pc, 3)) + "," + KStr(Round(rc, 3)) + "," + KStr(Round(wq, 3)) + ","
                    + KStr(Round(wp, 3)) + "," + KStr(Round(wr, 3)) + "," + KStr(Round(cmdP, 4)) + "," + KStr(Round(cmdR, 4)) + "," + KStr(Round(cmdY, 4)) + ","
                    + KStr(Round(grdAuthD[0], 3)) + "," + KStr(Round(grdAuthD[1], 3)) + "," + KStr(Round(grdAuthD[2], 3)) + "," + KStr(Round(stk0, 3))
                    + "," + KStr(Round(stk1, 3)) + "," + KStr(Round(stk2, 3)) + "," + KStr(Round(grdPath.magnitude, 3)) + "," + KStr(Round(grdIv[0], 4))
                    + "," + KStr(Round(grdIv[1], 4)) + "," + KStr(Round(grdIv[2], 4)) + "," + KStr(Round(grdAk, 3)) + "," + KStr(Round(grdNzM, 3));
                grdBufN = grdBufN + 1;
                if (grdBufN >= GRD_FLUSH)                                   // l.427: LOG grdBuf TO grdCsv (kOS's)
                {
                    flush = grdBuf;
                    act |= 4;
                    grdBuf = "";
                    grdBufN = 0;
                }
            }
        }

        void CheckFinite()
        {
            Fin(grdT, "grdT"); Fin(grdN, "grdN"); FinV(grdVoP, "grdVoP"); FinV(grdVhP, "grdVhP"); FinV(grdPath, "grdPath");
            Fin(grdAk, "grdAk"); Fin(grdAkR, "grdAkR"); Fin(grdYjr, "grdYjr"); Fin(grdAHold, "grdAHold"); Fin(grdBHold, "grdBHold"); Fin(grdCapT0, "grdCapT0"); Fin(grdCapQT0, "grdCapQT0");
            Fin(rpA.r0, "grdRpA"); Fin(rpA.r2, "grdRpA"); Fin(rpA.r3, "grdRpA"); Fin(rpB.r0, "grdRpB"); Fin(rpB.r2, "grdRpB"); Fin(rpB.r3, "grdRpB");
            Fin(grdBf, "grdBf"); Fin(grdIv[0], "grdI"); Fin(grdIv[1], "grdI"); Fin(grdIv[2], "grdI");
            Fin(wc0, "grdWc"); Fin(wc1, "grdWc"); Fin(wc2, "grdWc"); Fin(grdNzM, "grdNzM");
            Fin(cmdPo, "cmdP"); Fin(cmdRo, "cmdR"); Fin(cmdYo, "cmdY");
            for (int i = 0; i < 3; i++) for (int k = 1; k < 8; k++) if (kbW[i][k]) Fin(kbV[i][k], "dKb");
        }

        static bool Chg(double a, double b) { return a != b && !(double.IsNaN(a) && double.IsNaN(b)); }
        static ListValue L3(double a, double b, double c)
        {
            var l = new ListValue();
            l.Add(ScalarValue.Create(a)); l.Add(ScalarValue.Create(b)); l.Add(ScalarValue.Create(c));
            return l;
        }
        void CommitRamp(IGrdEnv e, Ramp r)
        {
            if (!r.w) return;
            e.ListSet(r.name, r.list, 3, ScalarValue.Create(r.r3));
            e.ListSet(r.name, r.list, 0, ScalarValue.Create(r.r0));
            e.ListSet(r.name, r.list, 1, r.r1s);
            e.ListSet(r.name, r.list, 2, ScalarValue.Create(r.r2));
        }
        void Commit(IGrdEnv e)
        {
            e.Set("grdT", ScalarValue.Create(grdT));
            e.Set("grdN", ScalarValue.Create(grdN));
            e.Set("grdVoP", e.MakeVec(grdVoP));
            e.Set("grdVhP", e.MakeVec(grdVhP));
            e.Set("grdPath", e.MakeVec(grdPath));
            if (grdAuthNew != null) e.Set("grdAuth", grdAuthNew);
            if (Chg(grdAk, o_grdAk)) e.Set("grdAk", ScalarValue.Create(grdAk));
            if (Chg(grdAkR, o_grdAkR)) e.Set("grdAkR", ScalarValue.Create(grdAkR));
            if (Chg(grdYjr, o_grdYjr)) e.Set("grdYjr", ScalarValue.Create(grdYjr));
            if (dReqP != o_dReqP) e.Set("dReqP", new BooleanValue(dReqP));      // The SW's forced CSS want (as kOS's SET dReqP TO TRUE)
            if (dReqR != o_dReqR) e.Set("dReqR", new BooleanValue(dReqR));
            if (grdCssP != o_grdCssP) e.Set("grdCssP", new BooleanValue(grdCssP));
            if (grdCssR != o_grdCssR) e.Set("grdCssR", new BooleanValue(grdCssR));
            if (grdHoldP != o_grdHoldP) e.Set("grdHoldP", new BooleanValue(grdHoldP));
            if (grdHoldR != o_grdHoldR) e.Set("grdHoldR", new BooleanValue(grdHoldR));
            if (Chg(grdAHold, o_grdAHold)) e.Set("grdAHold", ScalarValue.Create(grdAHold));
            if (Chg(grdBHold, o_grdBHold)) e.Set("grdBHold", ScalarValue.Create(grdBHold));
            if (Chg(grdCapT0, o_grdCapT0)) e.Set("grdCapT0", ScalarValue.Create(grdCapT0));
            if (Chg(grdCapQT0, o_grdCapQT0)) e.Set("grdCapQT0", ScalarValue.Create(grdCapQT0));
            CommitRamp(e, rpA);
            CommitRamp(e, rpB);
            if (Chg(grdBf, o_grdBf)) e.Set("grdBf", ScalarValue.Create(grdBf));
            if (grdBfOn != o_grdBfOn) e.Set("grdBfOn", new BooleanValue(grdBfOn));
            if (Chg(grdAm, o_grdAm)) e.Set("grdAm", ScalarValue.Create(grdAm));
            if (grdAmOn != o_grdAmOn) e.Set("grdAmOn", new BooleanValue(grdAmOn));
            for (int i = 0; i < 3; i++) if (grdIw[i]) e.ListSet("grdI", grdI, i, ScalarValue.Create(grdIv[i]));
            e.Set("grdWc", L3(wc0, wc1, wc2));
            if (Chg(grdNzM, o_grdNzM)) e.Set("grdNzM", ScalarValue.Create(grdNzM));
            e.Set("grdU", L3(cmdPo, cmdRo, cmdYo));
            if (!string.Equals(grdBuf, o_grdBuf, StringComparison.Ordinal)) e.Set("grdBuf", new StringValue(grdBuf));
            if (Chg(grdBufN, o_grdBufN)) e.Set("grdBufN", ScalarValue.Create(grdBufN));
            for (int i = 0; i < 3; i++)                                     // dKb, in place (kOS's SET s[k])
                for (int k = 0; k < 8; k++)
                {
                    if (!kbW[i][k]) continue;
                    Structure v = kbO[i][k] ?? (k == 0 ? (Structure)new BooleanValue(kbV[i][k] != 0) : ScalarValue.Create(kbV[i][k]));
                    e.ListSet(KB_AX[i], kbL[i], k, v);
                }
        }
    }
}
