// lib/lib_dap.ks's dapTick in C#, off the kOS CPU, line for line (the kOS line numbers of lib_dap.ks at c02f30ff are
// in the comments), with kOS's semantics (checked by IL on kOS.Safe.dll / kOS.dll):
//   - every number a double; SIN / COS / TAN(d) = Math.X(d * PI / 180); ARCSIN / ARCTAN2 = Math.X(...) * 180 / PI;
//     MOD(a, b) = a % b; ROUND(x[, n]) = Math.Round(x, n); MIN / MAX = Math.Min / Max; FLOOR / CEILING = Math.X;
//   - kOS never holds a -0 (ScalarValue.Create makes every whole value an int), so ARCTAN2's arguments drop the sign of
//     a zero (Atan2d) and a number shown in a string is printed as kOS prints it (KStr);
//   - vectors through KSP's Vector3d as kOS's Vector does (VDOT / VCRS / VXCL / VANG / :NORMALIZED / :MAG / + / - / *).
// THE STATE IS kOS's: every global dapTick reads is read from kOS at the tick's start (IDapEnv.Get), and the ones it
// writes are written back at the end, only when changed (Commit). So the kOS globals are always the DAP's exact state:
// the kOS dapTick can take over at any tick (the fallback), and every other reader (lib_land, the HUD, dapStop) sees
// what it saw before. Nothing is written before the end: an exception leaves kOS untouched.
// THE GAME I/O STAYS kOS's: the tick's reads come in as one list (DapIn), the writes go out as the seven surface angles
// (the setAng memo decided here, the HASFIELD / SETFIELD and dLast's entry kOS's) and a list of rare actions (locks,
// SAS, BRAKES, the brake sliders, the buttons, the label, the event log, the csv flush).
using System;
using System.Collections.Generic;
using System.Globalization;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    // the kOS side of a tick: its globals (live, or a dry run's capture) and its vectors
    public interface IDapEnv
    {
        Structure Get(string name);
        void Set(string name, Structure v);
        Vector3d Vec(Structure s);
        Structure MakeVec(Vector3d v);
        void LexSet(Structure lex, string key, Structure v);
        void ListAdd(Structure list, Structure v);
    }

    public static class DapIn       // the reads kOS passes, in this order (the staged lib_dap.ks's dapCsTick)
    {
        public const int W = 0, FV = 1, SV = 2, TV = 3, VS = 4, UP = 5, NORTH = 6, PS = 7, DYNP = 8, ALTI = 9, AGL = 10,
            AIRSPEED = 11, GSPEED = 12, STATUS = 13, THR = 14, TIME = 15, SAS = 16, BRAKES = 17, GIMBAL = 18, RUD0 = 19,
            RUD1 = 20, ELVLOCK = 21, RWY = 22, N = 23;
    }

    public static class DapAct      // the rare actions' codes (kOS's dapCsAct)
    {
        public const int LOCK = 1, SASOFF = 2, BRAKES = 3, GMBUNLOCK = 4, BTNTEXT = 5, BTNPRESSED = 6, RUDDEPLOY = 7,
            BRK = 8, LABEL = 9, LOGTXT = 10, PRINTAT = 11, FLUSH = 12;
    }

    public partial class Dap
    {
        public const double NOWRITE = -1E9;
        public Func<string> ftCols;     // on the mains: SockFarTrim's terms as the csv's last seven columns (log only)
        public const string FT_NONE = ",,,,,,,";        // the seven columns empty (off the mains, no SockFarTrim)
        const double PI = 3.1415926535897931;
        const double RADTODEG = 57.295779513082323;     // CONSTANT:RADTODEG
        const double ATMTOKPA = 101.325;                // CONSTANT:ATMTOKPA

        // ------------------------------------------------------------ kOS's arithmetic
        static double Sin(double d) { return Math.Sin(d * PI / 180); }
        static double Cos(double d) { return Math.Cos(d * PI / 180); }
        static double Tan(double d) { return Math.Tan(d * PI / 180); }
        static double Asin(double x) { return Math.Asin(x) * 180 / PI; }
        static double Z(double x) { return x == 0 ? 0.0 : x; }
        static double Atan2d(double y, double x) { return Math.Atan2(Z(y), Z(x)) * 180 / PI; }
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        static double Abs(double a) { return Math.Abs(a); }
        static double Sqrt(double a) { return Math.Sqrt(a); }
        static double Mod(double a, double b) { return a % b; }
        static double Floor(double a) { return Math.Floor(a); }
        static double Ceiling(double a) { return Math.Ceiling(a); }
        static double Round(double a) { return Math.Round(a, 0); }
        static double Round(double a, int n) { return Math.Round(a, n); }
        static double Vdot(Vector3d a, Vector3d b) { return Vector3d.Dot(a, b); }
        static Vector3d Vcrs(Vector3d a, Vector3d b) { return Vector3d.Cross(a, b); }
        static Vector3d Vxcl(Vector3d a, Vector3d b) { return Vector3d.Exclude(a, b); }
        static double Vang(Vector3d a, Vector3d b) { return Vector3d.Angle(a, b); }
        static Vector3d Mul(Vector3d a, double d) { return new Vector3d(a.x * d, a.y * d, a.z * d); }

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
        static string KStr(bool b) { return b ? "True" : "False"; }

        double swGdT0 = -1;     // The game time the SW 02 guidance bit was first seen (-1: not seen)
        // kOS flfxSwAutoLost for the entry / TAEM / A/L DAP: SW 01 ENTRY at once; SW 02 (ENTRY, TAEM or A/L) after SW_GD_LOST_S
        bool SwDapLost(double now)
        {
            if ((SW_MASK & SwGate.SW01_ENTRY) != 0) { return true; }
            if ((SW_MASK & SwGate.SW02_PHASES_DAP) == 0) { swGdT0 = -1; return false; }
            if (swGdT0 < 0) { swGdT0 = now; }
            return now - swGdT0 >= SW_GD_LOST_S;
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
        static bool Chg(double a, double b) { return a != b && !(double.IsNaN(a) && double.IsNaN(b)); }
        static double Fin(double x, string n)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("non-finite " + n);
            return x;
        }

        // a table (LIST of LIST(x, y)) / a schedule (LIST of 4), converted once per list object (the kOS list itself is
        // the key: a SET to a new list converts again)
        readonly Dictionary<Structure, double[][]> tabCache = new Dictionary<Structure, double[][]>();
        readonly Dictionary<Structure, double[]> schCache = new Dictionary<Structure, double[]>();
        double[][] Tab(Structure s)
        {
            double[][] t;
            if (tabCache.TryGetValue(s, out t)) return t;
            var l = (ListValue)s;
            t = new double[l.Count][];
            for (int i = 0; i < l.Count; i++)
            {
                var r = (ListValue)l[i];
                t[i] = new double[r.Count];
                for (int j = 0; j < r.Count; j++) t[i][j] = Num(r[j]);
            }
            tabCache[s] = t;
            return t;
        }
        double[] Sch(Structure s)
        {
            double[] t;
            if (schCache.TryGetValue(s, out t)) return t;
            var l = (ListValue)s;
            t = new double[l.Count];
            for (int j = 0; j < l.Count; j++) t[j] = Num(l[j]);
            schCache[s] = t;
            return t;
        }

        // ------------------------------------------------------------ the tick's I/O
        IDapEnv env;
        ListValue acts;
        double[] ang = new double[7];
        bool dLastCleared;
        Dictionary<string, double> bkSet = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        List<string> bkOrder = new List<string>();
        string rowAdd;
        bool sasNow, brakesNow;
        double tNow;
        Vector3d upV, northV, vsV, thrPos, farPos;
        bool havePos;
        // the AUTO roll-rate command of the tick before and that tick's dLoop (lib_dap dPcPrev, dPcN: the C#'s own, as kbS)
        double dPcPrev, dPcN = -9;

        void Act(int code, params object[] args)
        {
            var a = new ListValue();
            a.Add(ScalarValue.Create(code));
            foreach (var x in args)
            {
                if (x is string) a.Add(new StringValue((string)x));
                else if (x is bool) a.Add(new BooleanValue((bool)x));
                else if (x is int) a.Add(ScalarValue.Create((int)x));
                else a.Add(ScalarValue.Create((double)x));
            }
            acts.Add(a);
        }

        // ------------------------------------------------------------ helpers (l.484-705, 977-982)
        // the keyboard mode (lib_dap kbAxis, KB_*): one axis's 0 / 1 key input built like a stick; the raw input back while
        // the axis reads as a stick. Its per-axis state is the C#'s own (kOS's dKb belongs to the kOS tick): [0] on (1 / 0),
        // [1] the output, [2] the last raw input, [3] the last time, [4] the full-throw steps, [5] the in-between s, [6] the
        // press's start, [7] the press's sign.
        readonly double[][] kbS = { new double[8], new double[8], new double[8] };
        static readonly string[] KB_AXN = { "PITCH", "ROLL", "YAW" };
        double kbAxis(int i, double raw)
        {
            if (KB_MODE == 0) { return raw; }
            double[] s = kbS[i];
            double tn = tNow;
            double dt = 0;
            if (s[3] > 0) { dt = Max(0, Min(0.2, tn - s[3])); }
            s[3] = tn;
            double a = Abs(raw);
            bool atStop = a < 0.0001 || Abs(a - 1) < 0.0001;
            if (atStop && Abs(raw - s[2]) > 0.9) { s[4] = s[4] + 1; s[5] = 0; }
            if (!atStop) { s[5] = s[5] + dt; }
            s[2] = raw;
            if (KB_MODE == 1)
            {
                if (s[0] == 0 && s[4] >= KB_STEPS)
                {
                    s[0] = 1;
                    s[5] = 0;
                    addMsg(KB_AXN[i] + " KEYBOARD: a held key builds to " + KStr(Round(100 * KB_FULL)) + " % in " + KStr(KB_RISE) + " s, a tap nudges");
                }
                if (s[0] != 0 && s[5] > KB_STICK_T)
                {
                    s[0] = 0;
                    s[4] = 0;
                    s[7] = 0;
                    s[1] = 0;
                    addMsg(KB_AXN[i] + " STICK: the raw input");
                }
                if (s[0] == 0)
                {
                    s[5] = Min(s[5], KB_STICK_T);
                    return raw;
                }
            }
            double sg = 0;
            if (a >= 0.5) { sg = raw > 0 ? 1 : -1; }
            if (sg != 0)
            {
                if (sg != s[7])
                {
                    s[6] = tn;
                    s[7] = sg;
                    s[1] = sg * KB_MIN;
                }
                else
                {
                    s[1] = sg * Min(KB_FULL, Abs(s[1]) + (KB_FULL - KB_MIN) / KB_RISE * dt);
                }
            }
            else if (s[7] == 0 || tn - s[6] >= KB_TAP)
            {
                s[7] = 0;
                s[1] = 0;
            }
            return s[1];
        }

        void addMsg(string s)        // l.679
        {
            if (dMsg == "") { dMsg = s; } else { dMsg = dMsg + "; " + s; }
        }
        double linM(double x, double xLo, double vLo, double xHi, double vHi)   // l.491
        {
            if (x <= xLo) { return vLo; }
            if (x >= xHi) { return vHi; }
            return vLo + (vHi - vLo) * (x - xLo) / (xHi - xLo);
        }
        double linS(double x, double[] sch) { return linM(x, sch[0], sch[1], sch[2], sch[3]); }   // l.497
        double rudCloseTo(double db, double c)    // l.504
        {
            return Max(0 - RUD_CLOSE_LIM, rudFinv(rudFt(db) - 2 * rudFt(c)));
        }
        double rudCloseLim(double db)             // l.508
        {
            if (db != dRclDb || RUD_CLOSE_LIM != dRclLim)
            {
                dRclV = rudFinv((rudFt(db) - rudFt(0 - RUD_CLOSE_LIM)) / 2);
                dRclDb = db;
                dRclLim = RUD_CLOSE_LIM;
            }
            return dRclV;
        }
        double rudFt(double d)                    // l.519
        {
            var T = RUD_F_TAB;
            int n = T.Length - 1;
            if (d <= T[0][0]) { return T[0][1]; }
            if (!(d <= T[n][0])) { return T[n][1]; }
            double i = Max(1, Min(n, Ceiling((d - T[0][0]) / (T[1][0] - T[0][0]))));
            while (!(d <= T[(int)i][0])) { i = i + 1; }
            while (!(i <= 1)) { if (d > T[(int)i - 1][0]) { break; } i = i - 1; }
            int k = (int)i;
            return T[k - 1][1] + (T[k][1] - T[k - 1][1]) * (d - T[k - 1][0])
                / (T[k][0] - T[k - 1][0]);
        }
        double rudFinv(double f)                  // l.530
        {
            var T = RUD_FINV_TAB;
            int n = T.Length;
            if (f <= T[0][0]) { return T[0][1]; }
            if (!(f <= T[n - 1][0])) { return T[n - 1][1]; }
            double lo = 1;
            double hi = n - 1;
            while (!(lo >= hi))
            {
                double mid = Floor((lo + hi) / 2);
                if (f <= T[(int)mid][0]) { hi = mid; } else { lo = mid + 1; }
            }
            int l = (int)lo;
            return T[l - 1][1] + (T[l][1] - T[l - 1][1]) * (f - T[l - 1][0])
                / (T[l][0] - T[l - 1][0]);
        }
        double rudFq(double d)                    // l.544
        {
            var T = RUD_F_TAB;
            double x = (Min(56, Max(-12, d)) + 12) / 2;
            double i = Min(33, Floor(x));
            int k = (int)i;
            return T[k][1] + (T[k + 1][1] - T[k][1]) * (x - i);
        }
        double rudFs(double d)                    // l.550
        {
            var T = RUD_F_TAB;
            int k = (int)Min(33, Floor((Min(56, Max(-12, d)) + 12) / 2));
            return (T[k + 1][1] - T[k][1]) / 2;
        }
        double rudSplitTo(double db, double c)    // l.558
        {
            double tgt = 2 * rudFq(c);
            double hmin = 2 * db - RUD_OPEN_MAX;
            if (rudFq(RUD_OPEN_MAX) - rudFq(hmin) <= tgt)
            {
                return Max(0 - RUD_CLOSE_LIM, rudFinv(rudFq(RUD_OPEN_MAX) - tgt));
            }
            double h = Max(hmin, rudCloseTo(db, c));
            for (double k = 0; !(k >= 3); k = k + 1)
            {
                double ho = Min(RUD_OPEN_MAX, 2 * db - h);
                double s = rudFs(h) + (ho < RUD_OPEN_MAX ? rudFs(ho) : 0);
                if (s > 0.000001) { h = Max(hmin, Min(db, h + (rudFq(ho) - rudFq(h) - tgt) / s)); }
            }
            return Max(0 - RUD_CLOSE_LIM, Min(db, h));
        }
        double tabLook(double[][] tb, double x)   // l.573
        {
            if (x <= tb[0][0]) { return tb[0][1]; }
            int i = 1;
            while (!(i >= tb.Length))
            {
                if (x <= tb[i][0])
                {
                    return tb[i - 1][1] + (tb[i][1] - tb[i - 1][1]) * (x - tb[i - 1][0]) / (tb[i][0] - tb[i - 1][0]);
                }
                i = i + 1;
            }
            return tb[tb.Length - 1][1];
        }
        double clampV(double x, double lim) { return Max(-lim, Min(lim, x)); }   // l.586
        double dapMach(double ps0, double dynp)   // l.591 (ps0 = ALTITUDEPRESSURE(ALTITUDE), dynp = DYNAMICPRESSURE)
        {
            double ps = ps0 * ATMTOKPA * 1000;
            if (ps < 0.0001) { return 0; }
            double qd = dynp * ATMTOKPA * 1000;
            return Sqrt(Max(2 * qd / (1.4 * ps), 0));
        }
        double dapBank(Vector3d vd, Vector3d tv)  // l.598
        {
            if (vd.magnitude < 1) { return 0; }
            vd = vd.normalized;
            Vector3d upP = Vxcl(vd, upV);
            Vector3d topP = Vxcl(vd, tv);
            if (upP.magnitude < 0.001 || topP.magnitude < 0.001) { return 0; }
            upP = upP.normalized;
            topP = topP.normalized;
            double sgn = 1;
            if (Vdot(Vcrs(upP, topP), vd) < 0) { sgn = -1; }
            return sgn * Vang(upP, topP);
        }
        double shapeP(double g, double M)         // l.613
        {
            double x = Abs(g) * RHC_FULL - P_DB;
            if (x <= 0) { return 0; }
            double s = Min(DEMAX, (KDEMLIN + PKQ * x) * x) * linS(M, TG_CSS_P_GAIN);
            if (g < 0) { return -s; }
            return s;
        }
        double shapeR(double g, double M)         // l.622
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
        // lib_dap cssRx: CSS's roll added to shapeR's, CSS_RMAX at full stick (AUTO keeps shapeR)
        double cssRx(double g, double M)
        {
            double x = Min(1, (Abs(g) * RHC_FULL - R_DB) / (RHC_FULL - R_DB));
            if (x <= 0) { return 0; }
            double e = Max(0, CSS_RMAX - shapeR(1, M)) * x * x * x;
            if (g < 0) { return -e; }
            return e;
        }
        // setAng (l.634): the memo here; kOS writes (HASFIELD, SETFIELD, dLast[k]) -- slot = 0..3 E0..E3, 4 F, 5 R0, 6 R1
        void setAng(int slot, string k, double a)
        {
            if (!dLastCleared)
            {
                var lx = (Lexicon)dLast;
                Structure v;
                if (lx.TryGetValue(new StringValue(k), out v) && Abs(Num(v) - a) < 0.01) { return; }
            }
            ang[slot] = a;
        }
        void lockAxis(string fld, bool lockIt) { Act(DapAct.LOCK, fld, lockIt); }    // l.644 (kOS's)
        Structure BkRow(double i) { return ((ListValue)((ListValue)dBk)[(int)i]); }
        double BkCraft(double i) { return Num(((ListValue)BkRow(i))[2]); }
        bool bkHas(string k, out double v)
        {
            if (bkSet.TryGetValue(k, out v)) return true;
            Structure s;
            if (((Lexicon)dBkLast).TryGetValue(new StringValue(k), out s)) { v = Num(s); return true; }
            return false;
        }
        void setBrk(double i, string k, double pct)   // l.650
        {
            if (i < 0) { return; }
            pct = Max(0, pct);
            double last;
            if (bkHas(k, out last) && Abs(last - pct) < 0.01) { return; }
            Act(DapAct.BRK, (int)i, pct);
            if (!bkSet.ContainsKey(k)) bkOrder.Add(k);
            bkSet[k] = pct;
        }
        double pwm5(double bv)                    // l.658
        {
            double lo = Floor(bv / YB_STEP) * YB_STEP;
            if (Mod(dLoop, YB_PWM) < Round((bv - lo) / YB_STEP * YB_PWM)) { return lo + YB_STEP; }
            return lo;
        }
        double brkBase(double i) { return DAP_BRK_BASE >= 0 ? DAP_BRK_BASE : BkCraft(i); }   // l.664
        void brkBack()                            // l.668
        {
            if (dBkL >= 0) { setBrk(dBkL, "L", BkCraft(dBkL)); }
            if (dBkR >= 0) { setBrk(dBkR, "R", BkCraft(dBkR)); }
            if (dBkN >= 0) { setBrk(dBkN, "N", BkCraft(dBkN)); }
        }
        string brkNow(double i, string k)         // l.673 (the log's text)
        {
            double v;
            if (bkSet.TryGetValue(k, out v)) return KStr(v);
            Structure s;
            if (((Lexicon)dBkLast).TryGetValue(new StringValue(k), out s)) return s.ToString();
            if (i >= 0) { return ((ListValue)BkRow(i))[2].ToString(); }
            return "-1";
        }
        double hdgNow(Vector3d fwd)               // l.683
        {
            Vector3d nv = northV;
            return Mod(Atan2d(Vdot(fwd, Vcrs(upV, nv)), Vdot(fwd, nv)) + 360, 360);
        }
        void clGeom(Vector3d fwd)                 // l.690 (thr / far: the runway's POSITIONs, read by kOS)
        {
            Vector3d uv = upV;
            Vector3d hv = Vxcl(uv, farPos - thrPos).normalized;
            Vector3d rv = Vcrs(uv, hv).normalized;
            dClY = Vdot(-thrPos, rv);
            dClYd = Vdot(vsV, rv);
            Vector3d fh = Vxcl(uv, fwd);
            dClDpsi = Atan2d(Vdot(fh, rv), Vdot(fh, hv));
        }
        void dapGdBank(out double b, out double r)   // l.978
        {
            double f = (tNow - dGdBankT) / Max(dGdBankDt, 0.02);
            if (f >= DAP_RAMP_HOLD) { b = dGdBank1; r = 0; return; }
            b = dGdBank0 + (dGdBank1 - dGdBank0) * Min(1, Max(0, f));
            r = (dGdBank1 - dGdBank0) / Max(dGdBankDt, 0.02);
        }
        string hdRwyName()                        // lib_hud.ks hdRwyName
        {
            if (hdRwyIx < 0) { return "none"; }
            var r = (ListValue)((ListValue)hdRwys)[(int)hdRwyIx];
            string s = r[1].ToString();
            if (Bool(r[11])) { s = s + " (ELS)"; }
            return s;
        }
        static bool IsScalar(Structure s) { return s is ScalarValue; }   // :ISTYPE("Scalar")

        // ------------------------------------------------------------ ONE TICK (l.1249-1848)
        // dry: the globals are read but every write goes to the env (a dry env captures them); the actions are built
        // either way. Returns LIST(E0, E1, E2, E3, F, R0, R1 (NOWRITE: no write), LIST(actions)).
        public ListValue Tick(IDapEnv e, ListValue inp)
        {
            if (inp.Count != DapIn.N) throw new ArgumentException("DAPTICK wants " + DapIn.N + " reads, got " + inp.Count);
            env = e;
            acts = new ListValue();
            for (int i = 0; i < 7; i++) ang[i] = NOWRITE;
            dLastCleared = false;
            bkSet.Clear(); bkOrder.Clear();
            rowAdd = null;
            Load(e);
            Body(inp);
            CheckFinite();
            // commit: the globals, then the collections (dLast replaced, dBkLast's entries, the csv row)
            Commit(e);
            if (dLastCleared) e.Set("dLast", new Lexicon());
            foreach (var k in bkOrder) e.LexSet(dBkLast, k, ScalarValue.Create(bkSet[k]));
            if (rowAdd != null) e.ListAdd(dRows, new StringValue(rowAdd));
            var o = new ListValue();
            for (int i = 0; i < 7; i++) o.Add(ScalarValue.Create(ang[i]));
            o.Add(acts);
            return o;
        }

        void Body(ListValue inp)
        {
            // ---- measure (everything first)
            Vector3d w = Mul(env.Vec(inp[DapIn.W]), RADTODEG);
            Vector3d fv = env.Vec(inp[DapIn.FV]);
            Vector3d sv = env.Vec(inp[DapIn.SV]);
            Vector3d tv = env.Vec(inp[DapIn.TV]);
            upV = env.Vec(inp[DapIn.UP]);
            northV = env.Vec(inp[DapIn.NORTH]);
            tNow = Num(inp[DapIn.TIME]);
            sasNow = Bool(inp[DapIn.SAS]);
            brakesNow = Bool(inp[DapIn.BRAKES]);
            bool landed = string.Equals(inp[DapIn.STATUS].ToString(), "LANDED", StringComparison.OrdinalIgnoreCase);
            double qu = -Vdot(w, sv);
            double pk = Vdot(w, fv);
            double rk = Vdot(w, tv);
            Vector3d vs = env.Vec(inp[DapIn.VS]);
            vsV = vs;
            double vm = Max(vs.magnitude, 1);
            double aoa = 0;
            double beta = 0;
            if (vs.magnitude > 1)
            {
                aoa = Atan2d(-Vdot(vs, tv), Vdot(vs, fv));
                beta = Asin(Max(-1, Min(1, Vdot(vs.normalized, sv))));
                Vector3d vh = vs.normalized;
                double tn = tNow;
                if (dVhT > 0 && tn - dVhT > 0.001)
                {
                    double pq = 57.2958 * Vdot(vh - dVhPrev, tv) / ((tn - dVhT) * Max(Cos(aoa), 0.3));
                    dPathQ = dPathQ + (pq - dPathQ) * Min(1, (tn - dVhT) / PATH_TAU);
                }
                Vector3d nb = Vxcl(vh, tv);
                if (nb.magnitude > 0.001) { dNzM = vm * dPathQ / 57.2958 / 9.80665 + Vdot(upV, nb.normalized); }
                dVhPrev = vh;
                dVhT = tn;
            }
            double mach = dapMach(Num(inp[DapIn.PS]), Num(inp[DapIn.DYNP]));
            double qk = Num(inp[DapIn.DYNP]) * ATMTOKPA;
            double qkc = Max(qk, QB_MIN);
            double phi = dapBank(vs, tv);
            double th = 90 - Vang(upV, fv);
            double agl = Num(inp[DapIn.AGL]);
            double gp = 0;
            double gr = 0;
            double gy = 0;
            Structure gmb = inp[DapIn.GIMBAL];
            // lib_dap's dapCsIn sends 0 here when dGmbLive() is false (the gimbal engine lost / removed): a Scalar,
            // not a gimbal -- every touch of it is guarded like kOS's own (gp / gr / gy stay 0, no lock check)
            bool gmbOk = dGmbHave && !IsScalar(gmb);
            if (gmbOk)
            {
                gp = Num(gmb.GetSuffix("PITCHANGLE").Value);
                gr = Num(gmb.GetSuffix("ROLLANGLE").Value);
                gy = Num(gmb.GetSuffix("YAWANGLE").Value);
            }
            // the gimbal reads the vessel's yaw = the pilot's + the addon's trim; less the trim = the pilot's
            // (the yaw handed to the addon's handler can read 2.0 with a stick, so not that): the addon's reading of
            // this gimbal less its own trim, each physics frame, guarded (an impossible yaw reads 0). The gimbal works
            // for every input device.
            if (dYjAct) { gy = KalsAddon.YjPilotYaw; }
            var rw = inp[DapIn.RWY] as ListValue;
            havePos = rw != null;
            if (havePos) { thrPos = env.Vec(rw[0]); farPos = env.Vec(rw[1]); }

            // ---- the action groups' locks (l.1295)
            if (Mod(dLoop, 25) == 0)
            {
                if (gmbOk && Bool(gmb.GetSuffix("LOCK").Value))
                {
                    Act(DapAct.GMBUNLOCK);
                    dRelock = dRelock + 1;
                }
                // lib_dap's dapCsIn sends 0 (not a LIST) here when dElvLive() is false (the elevon module gone: a hard
                // touchdown breaks the part / the vessel is rebuilt) -- kOS's own block is inside IF dElvLive(), so no lock
                // test then; the old (ListValue) cast threw 'Specified cast is not valid' and the DAP fell back to kOS
                var lk = inp[DapIn.ELVLOCK] as ListValue;
                if (((ListValue)dElv).Count > 0 && lk != null)
                {
                    bool ip = Bool(lk[0]);
                    bool ir = Bool(lk[1]);
                    if (DAP_AUTO_GUID)
                    {
                        if (!ip || !ir)
                        {
                            lockAxis("pitch", true);
                            lockAxis("roll", true);
                            lockAxis("yaw", dYawLk);
                            dRelockN = dRelockN + 1;
                            addMsg("surfaces unlocked (AG9 / ABORT): locked again -- END hands you the raw surfaces");
                        }
                    }
                    else if ((dCssP && !ip) || (dCssR && !ir))
                    {
                        addMsg("surfaces unlocked (AG9 / ABORT): BOTH AXES TO AUTO");
                        Act(DapAct.BTNPRESSED, "P", false);
                        Act(DapAct.BTNPRESSED, "R", false);
                        dReqP = false;
                        dReqR = false;
                    }
                    else if (dGmbHave && ((!dCssP && ip) || (!dCssR && ir)))
                    {
                        addMsg("surfaces locked (AG10): BOTH AXES TO CSS");
                        Act(DapAct.BTNPRESSED, "P", true);
                        Act(DapAct.BTNPRESSED, "R", true);
                        dReqP = true;
                        dReqR = true;
                    }
                }
            }

            // The kOS refusal of AUTO (flfxSwAutoLost): both axes to CSS while SW 01 ENTRY, or SW 02 has held past the hold
            // The twin of lib_dap.ks's block: the forced CSS leaves the buttons as a click does (pressed, the CSS text); a crew click
            // on AUTO (ONTOGGLE: dReqX FALSE) is pressed back on the next tick. Pressed only when the want was not CSS yet (no kOS cost otherwise).
            if (SwDapLost(tNow))
            {
                if (!dReqP || !dReqR) { addMsg("AUTO DAP LOST (SW 01 / SW 02): BOTH AXES TO CSS"); }
                if (DAP_AUTO_GUID && !dReqP) { Act(DapAct.BTNPRESSED, "P", true); Act(DapAct.BTNTEXT, "P", "PITCH  CSS"); }
                if (DAP_AUTO_GUID && !dReqR) { Act(DapAct.BTNPRESSED, "R", true); Act(DapAct.BTNTEXT, "R", "ROLL/YAW  CSS"); }
                dReqP = true; dReqR = true;
            }
            else if ((SW_MASK & SwGate.SW02_ALPHA) != 0)   // The pitch axis only
            {
                if (!dReqP) { addMsg("ALPHA LOOP LOST (SW 02): PITCH TO CSS"); if (DAP_AUTO_GUID) { Act(DapAct.BTNPRESSED, "P", true); Act(DapAct.BTNTEXT, "P", "PITCH  CSS"); } }
                dReqP = true;
            }

            // ---- mode changes (bumpless) (l.1328)
            if (dReqP != dCssP && DAP_AUTO_GUID)
            {
                dCssP = dReqP;
                dQturnF = 0;
                if (dCssP && Abs(gp) * RHC_FULL > P_DB)
                {
                    addMsg("PITCH CSS -- stick / trim reads " + KStr(Round(gp, 2)) + ": centre it, Alt+X zeroes KSP trim");
                }
                else
                {
                    addMsg(dCssP ? "PITCH CSS (the stick)" : "PITCH AUTO (the guidance)");
                }
                Act(DapAct.BTNTEXT, "P", dCssP ? "PITCH  CSS" : "PITCH  AUTO");
            }
            if (dReqP != dCssP)
            {
                dCssP = dReqP;
                lockAxis("pitch", dCssP);
                if (dCssP)
                {
                    dElev = clampV(dElev - ELV_STICK * STICK_P_SIGN * gp, ELV_LIM);
                    if (dHaveFlap) { dFlapAng = clampV(dFlapAng - FLAP_STICK * STICK_P_SIGN * gp, FLAP_LIM); }
                    dTrimE = -(dElev - tabLook(SBX_TAB, mach) * dSbBase);
                    dQturnF = 0;
                    if (Abs(gp) * RHC_FULL > P_DB)
                    {
                        addMsg("PITCH CSS -- stick / trim " + KStr(Round(gp, 2)) + " taken over as trim: NOW Alt+X (trim = a rate command)");
                    }
                    else
                    {
                        addMsg("PITCH CSS");
                    }
                }
                else
                {
                    dElev = clampV(-dTrimE + tabLook(SBX_TAB, mach) * dSbBase, ELV_LIM);
                    addMsg("PITCH AUTO (the trim stays on the elevons)");
                }
                Act(DapAct.BTNTEXT, "P", dCssP ? "PITCH  CSS" : "PITCH  AUTO");
            }
            if (dReqR != dCssR && DAP_AUTO_GUID)
            {
                dCssR = dReqR;
                if (dCssR && Abs(gr) * RHC_FULL > R_DB)
                {
                    addMsg("ROLL/YAW CSS -- stick / trim reads " + KStr(Round(gr, 2)) + ": centre it, Alt+X zeroes KSP trim");
                }
                else
                {
                    addMsg(dCssR ? "ROLL/YAW CSS (the stick)" : "ROLL/YAW AUTO (the guidance)");
                }
                Act(DapAct.BTNTEXT, "R", dCssR ? "ROLL/YAW  CSS" : "ROLL/YAW  AUTO");
            }
            if (dReqR != dCssR)
            {
                dCssR = dReqR;
                lockAxis("roll", dCssR);
                if (RUD_ON) { lockAxis("yaw", dCssR && !dGnd); }
                if (!dCssR)
                {
                    dAil = 0;
                    dRudC = 0;
                }
                if (dCssR && Abs(gr) * RHC_FULL > R_DB)
                {
                    addMsg("ROLL/YAW CSS -- stick / trim reads " + KStr(Round(gr, 2)) + ": centre it, Alt+X zeroes KSP trim");
                }
                else
                {
                    addMsg(dCssR ? "ROLL/YAW CSS" : "ROLL/YAW AUTO");
                }
                Act(DapAct.BTNTEXT, "R", dCssR ? "ROLL/YAW  CSS" : "ROLL/YAW  AUTO");
            }
            if ((dCssP || dCssR || DAP_AUTO_GUID) && sasNow)
            {
                Act(DapAct.SASOFF);
                sasNow = false;
                dSasOff = dSasOff + 1;
                addMsg("SAS switched OFF: in CSS the gimbal must read the stick alone");
            }

            // the keyboard mode (kbAxis): a key's 0 / 1 builds like a stick from here on (the takeovers above keep the raw
            // input: in AUTO KSP deflects the surfaces by it)
            gp = kbAxis(0, gp);
            gr = kbAxis(1, gr);
            gy = kbAxis(2, gy);

            // ---- the speedbrake (l.1389)
            if (dRudHave)
            {
                bool dep0 = Bool(inp[DapIn.RUD0]);
                bool dep1 = Bool(inp[DapIn.RUD1]);
                if (!dep0 || !dep1)
                {
                    if (dSbAuto)
                    {
                        dSbAuto = false;
                        if (DAP_AUTO_GUID && !IsScalar(dBtnSb)) { Act(DapAct.BTNPRESSED, "Sb", false); Act(DapAct.BTNTEXT, "Sb", "SPDBK CSS"); }
                        addMsg("SPDBK CSS (AG3)");
                    }
                    if (!dSbLever)
                    {
                        if (dSbTarget > 1) { dSbTarget = 0; } else { dSbTarget = dSbOpen; }
                    }
                    if (!dep0) Act(DapAct.RUDDEPLOY, 0);
                    if (!dep1) Act(DapAct.RUDDEPLOY, 1);
                    dSbFlips = dSbFlips + 1;
                    dLastCleared = true;
                    addMsg(dSbLever ? "speedbrake: on the throttle lever"
                        : ("speedbrake " + (dSbTarget > 0 ? "OPENING" : "CLOSING")));
                }
            }
            // ---- THE LEVER (l.1411)
            dThrPilot = Num(inp[DapIn.THR]);
            if (!dSbLever && ((dLevLive && !dSbAuto) || Abs(dThrPilot - dThr0) > SB_LEVER_ARM))
            {
                dSbLever = true;
                addMsg("SPDBK LEVER ARMED: kOS reads the throttle (" + KStr(Round(100 * dThrPilot)) + " %); in CSS it is the brake");
            }
            if (dSbLever && !dSbAuto)
            {
                dSbTarget = RUD_HALF_LIM * (1 - Max(0, Min(1, dThrPilot)));
                if (mach > SB_SUPER_MACH) { dSbTarget = Min(dSbTarget, SB_SUPER_MAX); }
            }
            if (dSbAuto && dGdOn)
            {
                dSbTarget = Max(0, Min(RUD_HALF_LIM, dGdSb));
                if (mach > SB_SUPER_MACH) { dSbTarget = Min(dSbTarget, SB_SUPER_MAX); }
                if (!RUD_CURVE_PATCH && dSbTarget > SB_CLOSE_MAX && dSbTarget < SB_SPLIT_MIN)
                {
                    double mid = (SB_CLOSE_MAX + SB_SPLIT_MIN) / 2;
                    if (dSbBase >= mid) { mid = mid - 0.5; } else { mid = mid + 0.5; }
                    dSbTarget = dSbTarget >= mid ? SB_SPLIT_MIN : SB_CLOSE_MAX;
                }
            }
            dSbBase = dSbBase + clampV(dSbTarget - dSbBase, SB_RATE * DT);
            if (dRudFail != 0) { dSbTarget = 0; dSbBase = 0; }      // No speedbrake with a rudder half failed (lib_dap.ks)
            double sbx = tabLook(SBX_TAB, mach) * dSbBase;

            // ---- THE GROUND (l.1437)
            bool gdC = DAP_AUTO_GUID && dGdOn;
            bool hudOk = dHud && tNow - sHftT <= DAP_HUD_STALE_S;   // A frozen sHft is no height
            bool onGnd = landed;
            if (hudOk) { onGnd = sHft < GND_H_FT; }
            if (gdC) { onGnd = dGdWow; }
            if (onGnd && !dGnd)
            {
                dGnd = true;
                if (RUD_ON && dCssR && !DAP_AUTO_GUID) { lockAxis("yaw", false); }
                if (!dSbAuto && !dSbLever) { dSbTarget = RUD_HALF_LIM; }
                addMsg("MAIN GEAR: pitch ground mode (trim held, stick x" + KStr(GND_STICK) + ", up-elevon -" + KStr(GND_ELV_UP)
                    + "), speedbrake to " + KStr(RUD_HALF_LIM) + " a side");
                dGndTh = Min(th, GND_HOLD_MAX);          // the attitude AUTO holds until the derotation
                if (DAP_AUTO_GUID && !dCssP && dGdOn) { addMsg("PITCH HOLD: theta " + KStr(Round(dGndTh, 1)) + " until the derotation"); }
            }
            else if (dGnd && !dWong && !gdC && hudOk && sHft > GND_OFF_FT)
            {
                dGnd = false;
                if (RUD_ON && dCssR && !DAP_AUTO_GUID) { lockAxis("yaw", true); }
                addMsg("AIRBORNE again (> " + KStr(GND_OFF_FT) + " ft): the pitch ground mode off");
            }
            // THE CONTACT MODE (l.1459)
            if (gdC && !dGnd)
            {
                bool ctcNow = landed || (hudOk && sHft < GND_H_FT) || dGdHm < GND_H_FT * 0.3048;   // + the host's height
                if (ctcNow && !dCtc)
                {
                    dCtc = true;
                    dCtcElev = dElev;
                    addMsg("CONTACT: the flare law held until the touchdown latch (attitude hold, elevator no more nose-up than "
                        + KStr(Round(dElev, 1)) + ")");
                }
                else if (dCtc && (hudOk ? sHft > CTC_OFF_FT : dGdHm > CTC_OFF_FT * 0.3048) && !landed)
                {
                    dCtc = false;
                    addMsg("BOUNCE past " + KStr(CTC_OFF_FT) + " ft: the flare law back");
                }
            }
            if (dGnd) { dCtc = false; }
            if (dGnd && !dWong && (gdC ? dGdWong : (dHud && hdWong)))
            {
                dWong = true;
                dWongT = tNow;
                addMsg("NOSE GEAR: pitch load relief (elevons " + KStr(LR_ELEV) + " deg TED)");
            }

            // ---- THE AUTOMATIC DEROTATION (l.1479): guided, the ROLLOUT button governs it whatever PITCH is
            if (dGnd && !dWong && DAP_AUTO_GUID)
            {
                if (!dDerot && dClReq && dGdDerot > 0)
                {
                    dDerot = true;
                    addMsg("DEROTATION AUTO (ROLLOUT AUTO): " + KStr(Round(dGdDerot, 2)) + " deg/s (the guidance)");
                }
                else if (!dDerot && !dClReq && STICK_P_SIGN * gp < 0 - DR_TRIG)
                {
                    dDerot = true;
                    addMsg("DEROTATION CSS (ROLLOUT CSS): the crew's push, then " + KStr(Round(dGdDerot > 0 ? dGdDerot
                        : DR_RATE_SEMI, 2)) + " deg/s (the pitch stick is ignored until the nose gear)");
                }
            }
            else if (dGnd && !dWong && dCssP)
            {
                if (!dDerot && STICK_P_SIGN * gp < 0 - DR_TRIG)
                {
                    dDerot = true;
                    addMsg("DEROTATION: automatic, " + KStr(DR_RATE) + " deg/s (the pitch stick is ignored until the nose gear)");
                }
            }
            else
            {
                dDerot = false;
            }
            double drRate = DR_RATE;
            double drAcc = DR_ACC;
            if (DAP_AUTO_GUID) { drRate = dGdDerot > 0 ? dGdDerot : DR_RATE_SEMI; drAcc = DR_ACC_AUTO; }
            if (dDerot) { dDrQ = Max(0 - drRate, dDrQ - drAcc * DT); } else { dDrQ = 0; }

            // ---- THE AUTO ROLLOUT (l.1499)
            bool clRwy = dGdRwyOk || (dHud && hdRwyIx >= 0);
            if (clRwy && (dGnd || Mod(dLoop, 5) == 0))
            {
                if (!havePos) throw new InvalidOperationException("the runway's positions are missing");
                clGeom(fv);
            }
            dClAct = dClReq && dGnd && (dCssR || DAP_AUTO_GUID) && dBkHave && clRwy;
            if (dClAct)
            {
                if (Abs(gy) > CL_HOT) { dClHotT = dClHotT + DT; } else { dClHotT = 0; }
                if (dClHotT > CL_HOT_T)
                {
                    dClReq = false;
                    Act(DapAct.BTNPRESSED, "Cl", false);
                    dClAct = false;
                    addMsg("ROLLOUT CSS: the yaw stick took it");
                }
            }
            else
            {
                dClHotT = 0;
            }
            if (dClAct)
            {
                dClPsiC = clampV(0 - CL_KY * dClY, CL_PSI_MAX);
                double ce = dClPsiC - dClDpsi;
                dClUb = CL_KP * ce - CL_KD * rk;
                dClUr = CL_KPR * ce - CL_KDR * rk;
            }
            else
            {
                dClUb = 0;
                dClUr = 0;
            }
            if (DAP_AUTO_GUID)
            {
                bool yl = dClAct || !dGnd;
                if (yl != dYawLk)
                {
                    lockAxis("yaw", yl);
                    dYawLk = yl;
                }
            }
            if (dClAct != dClPrev)
            {
                if (!DAP_AUTO_GUID) { lockAxis("yaw", dClAct || (RUD_ON && dCssR && !dGnd)); }
                if (dClAct) { addMsg("ROLLOUT AUTO: the centreline of " + hdRwyName()); }
                dClPrev = dClAct;
            }

            // ---- PITCH (l.1536)
            double qc = 0;
            double qe = 0;
            double fSup = Max(0, Min(1, (mach - DAP_SUP_MACH + 0.1) / 0.2));
            double tphi = clampV(Tan(clampV(phi, 89)), 1);
            double qturn = 57.2958 * 9.81 / vm * Sin(phi) * tphi * Cos(th);
            if (dGnd) { qturn = 0; }
            dQturnF = dQturnF + (qturn - dQturnF) * DT / QTURN_TAU;
            if ((dCssP || DAP_AUTO_GUID) && dWong)
            {
                dElev = dElev + clampV(LR_ELEV - dElev, LR_RATE * DT);
                dDrI = 0;
                dChuteLiftT = 0;
            }
            else if (dCssP || DAP_AUTO_GUID)
            {
                double gs = 1;
                if (dGnd) { gs = GND_STICK; }
                bool autoP = false;
                // AUTO on the mains before the derotation: the latch's attitude held (GND_HOLD_*)
                bool gndHold = dGnd && !dWong && !dDerot && !dCssP && DAP_AUTO_GUID && dGdOn;
                if (dDerot) { qc = dDrQ; }
                else if (dCssP) { qc = gs * STICK_P_SIGN * shapeP(gp, mach); }
                else if (gndHold) { qc = clampV(GND_HOLD_K * Min(1, DAP_WARP_KT / (LOOP_P * DT)) * (dGndTh - th), GND_HOLD_QMAX); }
                else if (dGnd || dCtc || !dGdOn) { qc = 0; }
                else
                {
                    double gam = 90 - Vang(upV, vs);
                    double qpath = DAP_QPATH_MEAS ? dPathQ : 57.2958 * 9.81 / vm * (dGdNz - Cos(gam) * Cos(phi));
                    double acn = dGdAlpha;
                    double acd = dGdAlphaDot;
                    if (DAP_AC_RAMP && dGdAlphaT >= 0)
                    {
                        if (dGdAlphaT != dAcT) { dAc0 = dAcNow; dAcT = dGdAlphaT; }
                        double fu = (tNow - dAcT) / Max(dGdAlphaDt, 0.02);
                        acn = dAc0 + (dGdAlpha - dAc0) * Min(1, fu);
                        acd = fu < DAP_RAMP_HOLD ? (dGdAlpha - dAc0) / Max(dGdAlphaDt, 0.02) : 0;
                    }
                    double ffTau = DAP_FF_TAU_SUP * fSup + DAP_FF_TAU_SUB * (1 - fSup);   // the subsonic floor
                    if (ffTau > DT) { dAcdF = dAcdF + (acd - dAcdF) * DT / ffTau; acd = dAcdF; }
                    else { dAcdF = acd; }
                    dAcNow = acn;
                    autoP = true;
                    qc = clampV((KA_ALPHA + (KA_ALPHA_SUP - KA_ALPHA) * fSup) * (acn - aoa) + acd, shapeP(1, mach)) + qpath;
                }
                if (!autoP)
                {
                    dAcNow = aoa;                // the ramp restarts at the vehicle, not the record
                    dAcdF = 0;
                    dAc0 = aoa;
                    dAcT = dGdAlphaT;
                }
                dQa = qc;
                qe = qc + (dCssP ? dQturnF : 0) - qu;
                double gdq = (LOOP_P + (LOOP_P_SUP - LOOP_P) * fSup) * Sqrt(Q_REF) / (tabLook(MD_TAB, mach) * Q_REF) / Sqrt(qkc);
                gdq = gdq * Min(1, DAP_WARP_KT / Max(1E-6, (LOOP_P + (LOOP_P_SUP - LOOP_P) * fSup) * Sqrt(qkc / Q_REF) * DT));
                double gtre = linM(mach, 3.0, 1.5, 3.5, 1.0);
                double uNU = gdq * qe + dTrimE;
                double elvLim = ELV_LIM - Abs(dAil);
                if (dGnd && !dWong) { elvLim = ELV_LIM; }
                bool satUp = -uNU + sbx <= -elvLim;
                bool satDn = -uNU + sbx >= elvLim;
                if (((!dGnd && !dCtc) || gndHold) && !((satUp && qe > 0) || (satDn && qe < 0)))   // the hold integrates
                {
                    dTrimE = dTrimE + gtre * gdq * qe * DT;
                }
                double elvUp = elvLim;
                if (dGnd) { elvUp = Min(elvLim, GND_ELV_UP); }
                double elvNd = -(gdq * qe + dTrimE) + sbx;
                if (dGnd && !dWong && dDerot)
                {
                    double dri = DR_KI * (qu - qc) * DT;
                    if (dri < 0 || elvNd + dDrI < elvLim) { dDrI = Max(0, Min(ELV_LIM, dDrI + dri)); }
                }
                else { dDrI = 0; }
                dElev = Max(0 - elvUp, Min(elvLim, elvNd + dDrI));
                if (dGnd && !dWong && qu > CHUTE_GUARD_Q && dElev >= elvLim - 0.5)
                {
                    dChuteLiftT = dChuteLiftT + DT;
                    if (dChuteLiftT >= CHUTE_GUARD_T && !dChuteCutReq)
                    {
                        dChuteCutReq = true;
                        addMsg("CHUTE GUARD: the nose rises " + KStr(Round(qu, 1)) + " deg/s on the mains at full nose-down elevator -- cut it");
                    }
                }
                else { dChuteLiftT = 0; }
                if (dCtc && !dCssP) { dElev = Max(dElev, Min(dCtcElev, elvLim)); }
                if (dHaveFlap && !dGnd && !dCtc)
                {
                    double etrim = -dTrimE + sbx;
                    if (Abs(etrim) > FLAP_DB)
                    {
                        dFlapAng = clampV(dFlapAng + clampV(FLAP_K * etrim, FLAP_RATE) * DT, FLAP_LIM);
                    }
                }
                else if (dHaveFlap && dGnd)
                {
                    double fTed = GND_FLAP_TED + (GND_FLAP_TED_MAX - GND_FLAP_TED) * Min(1, dDrI / DR_FLAP_I);
                    double fTgt = (!dWong && th < GND_FLAP_THETA) ? fTed : 0;
                    dFlapAng = clampV(dFlapAng + clampV(fTgt - dFlapAng, GND_FLAP_RATE * DT), FLAP_LIM);
                }
            }

            // ---- ROLL / YAW (l.1636)
            double pc = 0;
            double pe = 0;
            double agLost = 0;                // the aileron the FAR roll guard holds off (+ = LEFT), to the jets
            double pcFf = 0;                  // the aileron's feed-forward of the AUTO roll acceleration in warp (0 at 1x)
            if ((dCssR || DAP_AUTO_GUID) && dGnd)
            {
                double lbk = 1;
                if (dWong) { lbk = Max(0, 1 - (tNow - dWongT) / LB_FADE); }
                pc = -LB_K * phi;
                pe = pc - pk;
                double gda = LOOP_R / tabLook(LD_TAB, mach) / qkc * Min(1, DAP_WARP_KT / (LOOP_R * DT));   // the warp cap
                double room = Max(!dWong ? 0 : AIL_ROOM_MIN, Min(AIL_LIM, ELV_LIM - Abs(dElev)));
                dAil = clampV(lbk * gda * pe + dTrimA, room);
                dElev = clampV(dElev, ELV_LIM - Abs(dAil));
                dRudC = 0;
                if (dClAct && RUD_CURVE_PATCH && dSbBase > SB_RUD_MAX)
                {
                    dRudC = clampV(CL_RUD_CLOSE_K * dClUr, rudCloseLim(dSbBase));
                }
                else if (dClAct && dSbBase >= SB_SPLIT_MIN)
                {
                    dRudC = clampV(dClUr, Max(0, RUD_HINGE_MAX - dSbBase));
                }
                dBetaC = 0;
            }
            else if (dCssR || DAP_AUTO_GUID)
            {
                if (dCssR)
                {
                    pc = STICK_R_SIGN * (shapeR(gr, mach) + cssRx(gr, mach));
                }
                else
                {
                    double gb0, gb1;
                    dapGdBank(out gb0, out gb1);
                    dPa = gb0;
                    // in warp the bank loop takes the roll loop's warp factor, its rate limit stays CSS's, the aileron
                    // gets the commanded roll acceleration fed forward (lib_dap.ks)
                    double rwf = Min(1, DAP_WARP_KT_R / (LOOP_R * DT));
                    pc = clampV(KA_PHI * rwf * (gb0 - phi) + gb1, shapeR(1, mach));
                    if (dPcN == dLoop - 1)
                    {
                        pcFf = Min(1, 4 * (1 - rwf)) * (pc - dPcPrev) / DT * Cos(aoa) / (tabLook(LD_TAB, mach) * qkc);   // 0 at 1x
                    }
                    dPcPrev = pc;
                    dPcN = dLoop;
                }
                double pturn = -57.2958 * 9.81 / vm * clampV(Tan(clampV(phi, 89)), 1.73) * Sin(th);
                pe = pc * Cos(aoa) - (pk - pturn);
                double gda = LOOP_R / tabLook(LD_TAB, mach) / qkc * Min(1, DAP_WARP_KT_R / (LOOP_R * DT));   // the warp cap
                if (mach > 1.25 && mach < 3.55)
                {
                    dTrimA = clampV(dTrimA + GTRA * gda * pe * DT, 3);
                }
                double room = Max(AIL_ROOM_MIN, Min(AIL_LIM, ELV_LIM - Abs(dElev)));
                dAil = clampV(gda * pe + dTrimA + pcFf, room);
                if (YJ_ON && mach > YJ_MACH)     // the FAR high-alpha roll guard (lib_dap.ks AG_LOC_TAB)
                {
                    double agA = clampV(dAil, Max(0, tabLook(AG_LOC_TAB, mach) - aoa - dElev));
                    agLost = dAil - agA;
                    dAil = agA;
                }
                dElev = clampV(dElev, ELV_LIM - Abs(dAil));
                if (RUD_ON && mach < RUD_MACH && !dGnd && (RUD_CURVE_PATCH || dSbBase <= SB_CLOSE_MAX
                                                           || dSbBase >= SB_SPLIT_MIN))
                {
                    double rturn = -57.2958 * 9.81 / vm * Sin(phi) * Cos(th);
                    double rc = -pc * Sin(aoa) + rturn;
                    if (YAW_PK > 0.5) { rc = -(pk - pturn) * Tan(clampV(aoa, 45)) + rturn; }   // the measured roll's
                    bool rOpen = dSbBase >= SB_SPLIT_MIN && !RUD_CURVE_PATCH && RUD_LIN < 0.5;
                    bool rClose = dSbBase > SB_RUD_MAX && !rOpen && RUD_LIN < 0.5;   // FAR = RUD_LIM
                    double rgk = rOpen ? RUD_OPEN_K : ((rClose && !RUD_CURVE_PATCH) ? tabLook(RUD_CLOSE_K_TAB, dSbBase) : 1);
                    double rlim = rOpen ? Max(0, RUD_HINGE_MAX - dSbBase) : (rClose ? (RUD_CURVE_PATCH ? rudCloseLim(dSbBase)
                        : dSbBase + RUD_CLOSE_LIM) : RUD_LIM);
                    double gdr = rgk * tabLook(KDRC_TAB, mach) / qkc;
                    dBetaC = 0;
                    if (dCssR && Abs(gy) > YB_DB) { dBetaC = -PED_BETA * clampV(gy, 1); }
                    dRudC = clampV(gdr * (rc - rk) + rgk * tabLook(KBETA_TAB, mach) * (beta - dBetaC), rlim);
                    if (YJ_ON && mach < YJ_RUD_MACH) { dRudC = 0; }      // under FAR the jets fly the yaw alone
                }
                else
                {
                    dRudC = 0;
                    dBetaC = 0;
                }
            }

            // ---- THE YAW JETS (lib_dap.ks)
            if (YJ_ON && (mach > YJ_MACH || dRudFail != 0) && !dGnd && (dCssR || DAP_AUTO_GUID))     // A failed rudder half: the jets to touchdown
            {
                double rcj = -pc * Sin(aoa) - 57.2958 * 9.81 / vm * Sin(phi) * Cos(th);
                if (YAW_PK > 0.5)     // the measured roll's (less the turn's roll rate, as the roll loop's pturn)
                {
                    rcj = -(pk + 57.2958 * 9.81 / vm * clampV(Tan(clampV(phi, 89)), 1.73) * Sin(th)) * Tan(clampV(aoa, 45))
                          - 57.2958 * 9.81 / vm * Sin(phi) * Cos(th);
                }
                dYawJ = clampV((YJ_KR * (rcj - rk) + YJ_KB * (beta - dBetaC) + YJ_KA * dAil
                               - AG_KJ * agLost) * Min(1, DAP_WARP_KT / (YJ_KR * YJ_ACC * DT)), 1);
                dYjAct = true;
            }
            else
            {
                dYawJ = 0;
                dYjAct = false;
            }

            // ---- THE GROUND YAW (l.1700)
            double ybWant = 0;
            if (dBkHave && (dCssR || DAP_AUTO_GUID) && dGnd) { ybWant = (dWong || DAP_BRK_FROM_WOW) ? 2 : 1; }
            if (ybWant != dYb)
            {
                if (dYb == 1 && brakesNow) { Act(DapAct.BRAKES, false); brakesNow = false; }
                if (ybWant == 0)
                {
                    brkBack();
                }
                else if (ybWant == 1)
                {
                    setBrk(dBkN, "N", 0);
                    addMsg("GROUND YAW: the yaw stick brakes the mains " + KStr(Round(YB_BASE / Max(1, BRK_TORQUE_K), 1)) + " +- "
                           + KStr(Round(YB_SPAN / Max(1, BRK_TORQUE_K), 1)) + " % (the DAP's brakes)");
                }
                else
                {
                    if (dBkN >= 0) { setBrk(dBkN, "N", dWong ? Min(NOSE_BRK_MAX, brkBase(dBkN)) : 0); }
                    dBkSfT = dWong ? -1 : 0;
                    if (!dWong)
                    {
                        addMsg("SHORT FIELD: the brakes from the main gear (the mains to " + KStr(Min(YB_MAX, brkBase(dBkR)))
                               + " % in about " + KStr(Round((Min(YB_MAX, brkBase(dBkR)) - YB_BASE / Max(1, BRK_TORQUE_K)) / BRK_SF_RAMP, 1))
                               + " s; the nose gear unbraked until it touches)");
                    }
                    if (DAP_AUTO_GUID)
                    {
                        addMsg("the brakes: the host's while ROLLOUT is AUTO (sliders " + KStr(Min(YB_MAX, brkBase(dBkR)))
                               + " %, the nose " + (dBkN >= 0 ? KStr(Min(NOSE_BRK_MAX, brkBase(dBkN))) : "-")
                               + " %, the centreline lowers the far main up to " + KStr(Round(YB_AUTO_SPAN / Max(1, BRK_TORQUE_K), 1))
                               + " %); yours (B) in a CSS rollout");
                    }
                    else
                    {
                        addMsg("the brakes are yours (B); the yaw stick lowers the far main up to "
                               + KStr(Round(2 * YB_SPAN / Max(1, BRK_TORQUE_K), 1)) + " %");
                    }
                }
                dYb = ybWant;
            }
            dYbU = 0;
            if (dYb > 0)
            {
                double bk = Max(1, BRK_TORQUE_K);
                double ybLim = (dYb == 1 ? YB_SPAN : (dClAct ? YB_AUTO_SPAN : 2 * YB_SPAN)) / bk;
                if (dClAct)
                {
                    dYbU = clampV(dClUb / bk, ybLim);
                }
                else if (Abs(gy) > YB_DB)
                {
                    dYbU = ybLim * clampV(gy, 1);
                }
                if (dYb == 1)
                {
                    if (!brakesNow) { Act(DapAct.BRAKES, true); brakesNow = true; }
                    setBrk(dBkR, "R", pwm5(YB_BASE / bk + dYbU));
                    setBrk(dBkL, "L", pwm5(YB_BASE / bk - dYbU));
                }
                else
                {
                    double bcap = 100;
                    if (dBkSfT >= 0)
                    {
                        dBkSfT = dBkSfT + DT;
                        if (qu < 0 - Max(BRK_SF_QMIN, BRK_SF_QK * Abs(dDrQ)) && dElev <= 0.5 - Min(ELV_LIM, GND_ELV_UP))
                        {
                            if (dBkSfBack == 0)
                            {
                                addMsg("SHORT FIELD: the brakes back off -- the nose falls " + KStr(Round(0 - qu, 1))
                                       + " deg/s at full nose-up elevator");
                            }
                            dBkSfBack = dBkSfBack + 1;
                            dBkSfT = 0;
                        }
                        bcap = YB_BASE / bk + BRK_SF_RAMP * dBkSfT;
                        if (dWong)
                        {
                            if (dBkN >= 0) { setBrk(dBkN, "N", Min(NOSE_BRK_MAX, brkBase(dBkN))); }
                            dBkSfT = -1;
                        }
                    }
                    setBrk(dBkR, "R", pwm5(Min(bcap, Min(YB_MAX, brkBase(dBkR)) - Max(0, 0 - dYbU))));
                    setBrk(dBkL, "L", pwm5(Min(bcap, Min(YB_MAX, brkBase(dBkL)) - Max(0, dYbU))));
                }
            }

            // ---- the surfaces (l.1767)
            var elv = (ListValue)dElv;
            for (int i = 0; i < elv.Count; i++)
            {
                var ev = (ListValue)elv[i];
                setAng(i, ev[2].ToString(), clampV(dElev + Num(ev[1]) * dAil, ELV_LIM));
            }
            if (dHaveFlap) { setAng(4, "F", dFlapAng); }
            if (dRudHave)
            {
                bool rLin = RUD_LIN > 0.5 && !dGnd;      // FAR in flight = the shut mapping
                if (dRudFail != 0)      // The good half = the rudder alone (the frozen half's write is refused by kOS's dapCsAng)
                {
                    double dr1 = clampV(RUD_ONE_K * dRudC, RUD_ONE_LIM);
                    if (dRudFail != 1) { setAng(5, "R0", RUD_SIGN * dr1); }
                    if (dRudFail != 2) { setAng(6, "R1", -RUD_SIGN * dr1); }
                }
                else if (RUD_CURVE_PATCH && dSbBase > SB_RUD_MAX && !rLin)
                {
                    double hc = dSbBase;
                    if (dRudC != 0)
                    {
                        hc = RUD_SPLIT ? rudSplitTo(dSbBase, Abs(dRudC)) : rudCloseTo(dSbBase, Abs(dRudC));
                    }
                    double ho = RUD_SPLIT ? Min(RUD_OPEN_MAX, 2 * dSbBase - hc) : dSbBase;
                    setAng(5, "R0", dRudC > 0 ? hc : ho);
                    setAng(6, "R1", dRudC < 0 ? hc : ho);
                }
                else if (dSbBase >= SB_SPLIT_MIN && !rLin)
                {
                    double dr = clampV(dRudC, Max(0, RUD_HINGE_MAX - dSbBase));
                    setAng(5, "R0", dSbBase + Max(0, dr));
                    setAng(6, "R1", dSbBase + Max(0, -dr));
                }
                else if (dSbBase > SB_RUD_MAX && !rLin)
                {
                    double dr = clampV(dRudC, dSbBase + RUD_CLOSE_LIM);
                    setAng(5, "R0", dSbBase - Max(0, dr));
                    setAng(6, "R1", dSbBase - Max(0, -dr));
                }
                else
                {
                    double rroom = Max(0, RUD_HALF_LIM - dSbBase);
                    double dr = clampV(dRudC, rroom);
                    setAng(5, "R0", dSbBase + RUD_SIGN * dr);
                    setAng(6, "R1", dSbBase - RUD_SIGN * dr);
                }
            }

            // ---- log, display (l.1801)
            if (SOCK_LOG && Mod(dLoop, D_LOG_EVERY) == 0)
            {
                string[] r = {
                    KStr(Round(tNow, 3)), KStr(Round(mach, 4)), KStr(Round(qk, 3)), KStr(Round(Num(inp[DapIn.ALTI]), 1)), KStr(Round(agl, 1)),
                    KStr(Round(Num(inp[DapIn.AIRSPEED]), 2)), KStr(Round(aoa, 3)), KStr(Round(beta, 3)), KStr(Round(phi, 2)), KStr(Round(th, 3)), KStr(Round(pk, 4)),
                    KStr(Round(qu, 4)), KStr(Round(rk, 4)), KStr(Round(gp, 3)), KStr(Round(gr, 3)), KStr(Round(gy, 3)), dCssP ? "1" : "0",
                    dCssR ? "1" : "0", "0", KStr(Round(qc, 3)), KStr(Round(dQturnF, 3)), KStr(Round(qe, 3)),
                    KStr(Round(dTrimE, 3)), KStr(Round(dElev, 3)), KStr(Round(pc, 3)), KStr(Round(pe, 3)), KStr(Round(dAil, 3)), KStr(Round(dTrimA, 3)),
                    KStr(Round(dRudC, 3)), KStr(Round(dFlapAng, 2)), KStr(Round(dSbBase, 2)), KStr(Round(dSbTarget, 1)), sasNow ? "1" : "0",
                    KStr(Round(sHft, 1)), hdWow ? "1" : "0", hdWong ? "1" : "0", KStr(Round(dBetaC, 2)), KStr(dYb),
                    KStr(Round(dYbU, 2)), brkNow(dBkL, "L"), brkNow(dBkR, "R"), brkNow(dBkN, "N"), brakesNow ? "1" : "0",
                    KStr(Round(hdgNow(fv), 2)), dClAct ? "1" : "0", KStr(Round(dClY, 2)), KStr(Round(dClYd, 2)), KStr(Round(dClDpsi, 3)),
                    KStr(Round(dClPsiC, 2)), KStr(Round(dClUb, 2)), KStr(Round(dClUr, 2)), dDerot ? "1" : "0", KStr(Round(dDrQ, 3)),
                    DAP_AUTO_GUID ? "1" : "0", KStr(Round(dGdAlpha, 3)), KStr(Round(dGdNz, 4)), KStr(Round(dPa, 3)), KStr(Round(dGdSb, 2)),
                    dSbAuto ? "1" : "0", KStr(Round(dQa, 3)), KStr(Round(dAcNow, 3)), KStr(Round(dPathQ, 3)), dCtc ? "1" : "0",
                    KStr(Round(dDrI, 2)), KStr(Round(dThrPilot, 3)), dSbLever ? "1" : "0", KStr(Round(dYawJ, 3)) };
                rowAdd = string.Join(",", r) + (hdWow && ftCols != null ? ftCols() : FT_NONE);
                if (((ListValue)dRows).Count + 1 >= D_FLUSH)
                {
                    Act(DapAct.FLUSH);
                }
            }
            dLoop = dLoop + 1;
            if (Mod(dLoop, 25) == 0)
            {
                double keas = Sqrt(2 * qk * 1000 / 1.225) / 0.514444;
                Act(DapAct.LABEL, "M " + KStr(Round(mach, 2)) + "  " + KStr(Round(keas)) + " KEAS  " + KStr(Round(agl * 3.28084)) + " ft");
                if (!DAP_AUTO_GUID)
                {
                    Act(DapAct.PRINTAT, "M " + KStr(Round(mach, 2)) + "  q " + KStr(Round(qk * 20.885)) + " psf  " + KStr(Round(keas)) + " KEAS  AGL "
                        + KStr(Round(agl * 3.28084)) + " ft  alpha " + KStr(Round(aoa, 1)) + "  beta " + KStr(Round(beta, 1)) + "          ", 22);
                    Act(DapAct.PRINTAT, "PITCH " + (dCssP ? "CSS " : "AUTO") + "  cmd " + KStr(Round(qc + dQturnF, 2)) + "  rate "
                        + KStr(Round(qu, 2)) + " deg/s  elev " + KStr(Round(dElev, 1)) + "  flap " + KStr(Round(dFlapAng, 1)) + "          ", 23);
                    Act(DapAct.PRINTAT, "ROLL  " + (dCssR ? "CSS " : "AUTO") + "  cmd " + KStr(Round(-pc, 1)) + "  rate " + KStr(Round(-pk, 1))
                        + " deg/s (+ right)  ail " + KStr(Round(dAil, 1)) + "  bank " + KStr(Round(-phi, 1)) + "          ", 24);
                    Act(DapAct.PRINTAT, "SB " + KStr(Round(dSbBase, 1)) + " a side (" + (dSbTarget > 0 ? "open" : "shut") + ")  rudder "
                        + KStr(Round(dRudC, 1)) + "  stick p " + KStr(Round(gp, 2)) + " r " + KStr(Round(gr, 2)) + " y " + KStr(Round(gy, 2))
                        + "          ", 25);
                    Act(DapAct.PRINTAT, "YAW  beta " + KStr(Round(beta, 1)) + " asked " + KStr(Round(dBetaC, 1)) + "  brakes L/R " + brkNow(dBkL, "L") + "/"
                        + brkNow(dBkR, "R") + (dYb == 1 ? " (DAP)" : (dYb == 2 ? " (yours)" : ""))
                        + "          ", 27);
                    Act(DapAct.PRINTAT, "ROLLOUT " + (dClReq ? "AUTO" : "CSS ") + (dClAct ? " (on)" : "") + "  y "
                        + KStr(Round(dClY, 1)) + " m  hdg err " + KStr(Round(dClDpsi, 2)) + "  asked " + KStr(Round(dClPsiC, 1))
                        + (dDerot ? "  DEROT" : "") + "          ", 28);
                }
                if (dMsg != "")
                {
                    if (!DAP_AUTO_GUID) { Act(DapAct.PRINTAT, dMsg + "                                        ", 26); }
                    if (SOCK_LOG) { Act(DapAct.LOGTXT, "  t " + KStr(Round(tNow - D_T, 1)) + " M " + KStr(Round(mach, 2)) + ": " + dMsg); }
                    dMsg = "";
                }
            }
            if (dReqEnd || (landed && Num(inp[DapIn.GSPEED]) < 1)) { dDone = true; }
        }
    }
}
