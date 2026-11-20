// ONE ENTRY GUIDANCE CYCLE in C# -- a line-for-line port of lib/entry_predict.ks's eprGuidStep (the deorbit
// entry, ops3q) and lib/lib_tal.ks's talGuidStep (the TAL entry, ops6q: eprGuidStep's copy + talAoA, the H-dot gate,
// the V4n overbank clamp and the Nz limiter talNzStep / talNzAt) with every function they call: eprOmegaCross, eprRho /
// eprLogInterp, eprMachFrom, eprPrMult / eprPrRef / eprHermite, eprCdaEntry / eprCda / eprPolar / eprBracket / eprHermAt
// / eprCdFix / eprSbFrac, eprAoA / eprAoANom / eprAoARamp, talAoA, eprAzError / eprToGeoLive / eprToGeoRaw /
// eprEastNorth, eprFamRngTo / eprGcDist, eprFamExcess / eprFamAddPrep, eprFamInvert / eprFamAt / eprFamRef / eprFamRoll,
// eprFamServo, eprAmBand, eprAmSlopeK, eprAzDeadband, eprMinBank, eprBankSlew, eprBankWithFlare.
// kOS semantics (as t62/dap, t62/fam): trig in degrees (Math.Sin(d * PI / 180); ARCSIN / ARCTAN2 = Math.X * 180 / PI,
// ARCTAN2's arguments through Z: kOS's ScalarValue.Create makes a -0 an int 0), ^ = Math.Pow (CONSTANT:E ^ x =
// Math.Pow(E, x)), LN = Math.Log, MIN / MAX = Math.Min / Max, FLOOR = Math.Floor, vectors through KSP's Vector3d as
// kOS.dll's Vector (VDOT, VCRS, :MAG, :NORMALIZED, + - * /), the same order of operations.
// THE STATE STAYS kOS's: Load reads every global the cycle reads (constants, tables, state) from kOS at each call; the
// cycle runs on these C# copies; Commit writes back every global the cycle SET (finite-checked first): an exception
// leaves kOS untouched. The game reads stay kOS's: TIME:SECONDS and the pressure eprPres(altm) come in the input list.
// Tables are cached per kOS list object (+ its length), the family EPR_FAM per list object + member objects + lengths
// (members are only ever ADDed to it: entry_predict.ks / lib_fam.ks).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public interface IEgEnv
    {
        Structure Get(string name);
        void Set(string name, Structure v);
        Vector3d Vec(Structure s);
    }

    public static class EgIn     // the input list, in this order (the staged entry_predict.ks's eprGsCsIn)
    {
        public const int TAL = 0, RV = 1, VV = 2, TLAT = 3, TLNG = 4, TROT = 5, DT = 6, DMEAS = 7, AOA = 8, FDN = 9, NOW = 10,
            PS = 11, N = 12;
    }

    public class EgCache
    {
        public readonly Dictionary<string, object[]> Tabs = new Dictionary<string, object[]>(StringComparer.OrdinalIgnoreCase);
        public object FamRef;
        public object[] FamMem;
        public int[] FamLen;
        public double[][][] Fam;
    }

    public class EntryGuid
    {
        // CONSTANT:E / :DEGTORAD / :RADTODEG (EGSETUP)
        public double CE, DEGTORAD, RADTODEG;

        // ---- read every call: constants ----
        double FAM_UTOP, AM_DDMIN, AM_G, AM_LIM, AM_V_FULL, AM_V_FULL_FAM, AM_V_ZERO, AM_V_ZERO_FAM, AOA_HIGH, AOA_HIGH_SPEED, AOA_LOW,
            AOA_LOW_SPEED, AOA_RAMP_HI, AOA_RAMP_LO, AOA_RAMP_V_HI, AOA_RAMP_V_LO, ATM, AZ_FIRST, AZ_LATE, AZ_MACH_HI, AZ_MACH_LO,
            AZ_SUBS, BANK_FLARE_MAX, BANK_FLARE_SLOPE, BANK_FLARE_SPEED, BANK_MAX, BANK_MAX_ABORT, BANK_MIN, BANK_STOP_SPEED,
            BANK_TAEM_LIMIT, BANK_TAEM_SPEED, FAM_EXT_V, FAM_SRV_BANK, FAM_SRV_DMAX, FAM_SRV_K, FAM_SRV_V0, FAM_SRV_V1, G0, GAMMA,
            GS_DT_MAX, GS_REV_TOL, GS_TAU, GUID_DRAG_INIT, HAC_LAT, HAC_LNG, HDOT_MAX, K_BANK_HDOT, K_HDOT, K_LIFT, K_PAR, MASS_K, TRIM_FD, TRIM_FL, FLAP_X, FLAP_KF,
            MIN_BANK_DELAZ_K, MIN_BANK_HI_HIGH, MIN_BANK_HI_LOW, MIN_BANK_LOW, MIN_BANK_MACH, NSIGN, ORG_LAT, ORG_LNG, PAR_SHIFT,
            PAR_W_CTL, PAR_W_FUS, PAR_W_WING, PREENTRY_BANK, PR_SHARE, R, ROLL_ACCEL_LIMIT, ROLL_RATE_LIMIT, ROT_SIGN, SB_V,
            SB_V_FULL, TAEM_VEL, TRK_MAX, WMAG, AM_DW, K3_HDOT, KH_MIN, KH_MAX,
            TAL_A0, TAL_NZ_DA, TAL_NZ_ITER, TAL_NZ_LEAD, TAL_NZ_RATE, TAL_NZ_SET, TAL_VALPD1, TAL_VALPD2,
            TAL_RHG_RSTAR, TAL_RHG_BLA, TAL_RHG_BLB, TAL_HAC_TLAT, TAL_HAC_TLNG, TAL_HAC_HDG, TAL_HAC_XC, TAL_HAC_RF, HAC_YSGN,
            TG_R1, TG_R2, TG_PSHA_MAX,
            SAT_AM_MAX, SAT_AM_U0, SAT_AM_U1, SAT_AM_V_FULL, SAT_AM_V_ZERO, SAT_AM_TAU, SAT_AM_RATE, SAT_AM_ACC;
        bool AM_ON, AM_SYNC, AOA_RAMP_ON, FAM_ADD, FAM_OK, FAM_READY, HAC_ON, SB_ON, USE_MIN_BANK, TAL_HDOT_GATE, TAL_V4N_ON,
            TAL_RHG_ON, BANK_TAEM_REF, K3_LATE_POS, SAT_AM_ON, SAT_AM_DREF;
        Vector3d GEO_X, GEO_Y, NAXIS, WAXIS;
        double[][] AM_SLOPE_K, CD_FIX, AERO_FIX, FLAP_TAB, CTL_PAR_A, CTL_PAR_M, FUS_PAR_A, FUS_PAR_M, LIFT_CURVE, LIFT_MACH, PSEUDORE, RHO, SB_FRAC,
            WING_PAR_A, WING_PAR_M;
        double[][][] FAM;          // per member: [0] = { bank }, [1] vs, [2] drag, [3] sink, [4] range, [5] bank flown

        // ---- read every call: state (written back when SET) ----
        double GS_DT, GS_TLAST, GS_AZ, GS_GLAT, GS_GLNG, GS_RNG, GS_TROT, GS_U_ST, GS_U, GS_DREF, GS_DNOW, GS_DMEAS, GS_DERR,
            GS_ACMD, GS_DEQ, AM_ASUM, AM_AN, AM_FDN, AM_AFD, AM_HOLD, GS_DERRF, GS_ACMDF, GS_CORR, GS_ROLLREF, GS_SIGN, GS_REV, GS_BANK, GS_RATE,
            HINT_RHO, PR_REF, FAM_EEXT, FAM_UT, TAL_VEH_VI, TAL_VEH_T, TAL_NZ_EL, TAL_NZ_QPREV, TAL_NZ_A, TAL_NZ_CAP,
            TAL_NZ_NOW, TAL_NZ_N, SAT_AM_UX, SAT_AM_B, SAT_AM_BF, SAT_AM_BR;
        bool GS_STARTED, GS_PAST, GS_REVERSING, FAM_ADD_PREP, FAM_EXTD;
        string GS_SAT;
        List<double> HINT;         // EPR_FAM_HINT's values
        public ListValue HintList; // the kOS list they came from
        bool hintNew;              // eprFamAddPrep replaced the list (SET EPR_FAM_HINT TO hs)
        public int HintN0;         // its length as read

        // ---- the writes: the names SET this call, in order ----
        public List<string> Dirty = new List<string>();
        HashSet<string> dirtySet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        bool tal;
        double now, now2, ps;      // TIME:SECONDS (now2: talGuidStep's second read, = now in flight), the pressure

        // ================================================================== kOS semantics
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180); }
        static double Tan(double d) { return Math.Tan(d * Math.PI / 180); }
        static double Asin(double x) { return Math.Asin(x) * 180 / Math.PI; }
        static double Z(double x) { return x == 0 ? 0.0 : x; }
        static double Atan2(double y, double x) { return Math.Atan2(Z(y), Z(x)) * 180 / Math.PI; }
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        static double Abs(double a) { return Math.Abs(a); }
        static double Sqrt(double a) { return Math.Sqrt(a); }
        static double Vdot(Vector3d a, Vector3d b) { return Vector3d.Dot(a, b); }

        public static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue();
            throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
        }
        public static bool Bool(Structure s)
        {
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            throw new InvalidCastException("not a boolean: " + (s == null ? "null" : s.GetType().Name));
        }
        static double Fin(double x, string n)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("non-finite " + n);
            return x;
        }
        void W(string n) { if (dirtySet.Add(n)) Dirty.Add(n); }

        // ================================================================== Load / Commit
        static double[][] ReadTab(ListValue l)
        {
            var t = new double[l.Count][];
            for (int i = 0; i < l.Count; i++)
            {
                var row = (ListValue)l[i];
                t[i] = new double[row.Count];
                for (int j = 0; j < row.Count; j++) t[i][j] = Num(row[j]);
            }
            return t;
        }
        static double[][] Tab(IEgEnv e, EgCache c, string name)
        {
            var l = e.Get(name) as ListValue;
            if (l == null) throw new InvalidCastException(name + " is not a list");
            object[] hit;
            if (c.Tabs.TryGetValue(name, out hit) && ReferenceEquals(hit[0], l) && (int)hit[1] == l.Count) return (double[][])hit[2];
            var t = ReadTab(l);
            c.Tabs[name] = new object[] { l, l.Count, t };
            return t;
        }
        static double[] Col(ListValue l)
        {
            var a = new double[l.Count];
            for (int i = 0; i < l.Count; i++) a[i] = Num(l[i]);
            return a;
        }
        static double[][][] Family(IEgEnv e, EgCache c)
        {
            var f = e.Get("EPR_FAM") as ListValue;
            if (f == null) throw new InvalidCastException("EPR_FAM is not a list");
            int n = f.Count;
            bool same = ReferenceEquals(c.FamRef, f) && c.FamMem != null && c.FamMem.Length == n;
            if (same)
            {
                for (int m = 0; m < n && same; m++)
                {
                    var mem = f[m] as ListValue;
                    if (!ReferenceEquals(mem, c.FamMem[m]) || mem.Count != c.FamLen[m] || ((ListValue)mem[1]).Count != c.Fam[m][1].Length) same = false;
                }
            }
            if (same) return c.Fam;
            var fam = new double[n][][];
            var mems = new object[n];
            var lens = new int[n];
            for (int m = 0; m < n; m++)
            {
                var mem = (ListValue)f[m];
                mems[m] = mem;
                lens[m] = mem.Count;
                int nc = Math.Min(mem.Count, 6);
                fam[m] = new double[6][];
                fam[m][0] = new double[] { Num(mem[0]) };
                for (int k = 1; k < nc; k++) fam[m][k] = Col((ListValue)mem[k]);
            }
            c.FamRef = f; c.FamMem = mems; c.FamLen = lens; c.Fam = fam;
            return fam;
        }

        public void Load(IEgEnv e, EgCache c, bool isTal)
        {
            tal = isTal;
            Func<string, double> N = n => Num(e.Get(n));
            Func<string, bool> B = n => Bool(e.Get(n));
            FAM_UTOP = N("EPR_FAM_UTOP"); AM_DDMIN = N("EPR_AM_DDMIN"); AM_G = N("EPR_AM_G"); AM_LIM = N("EPR_AM_LIM"); AM_V_FULL = N("EPR_AM_V_FULL");
            AM_V_FULL_FAM = N("EPR_AM_V_FULL_FAM"); AM_V_ZERO = N("EPR_AM_V_ZERO"); AM_V_ZERO_FAM = N("EPR_AM_V_ZERO_FAM");
            AOA_HIGH = N("EPR_AOA_HIGH"); AOA_HIGH_SPEED = N("EPR_AOA_HIGH_SPEED"); AOA_LOW = N("EPR_AOA_LOW");
            AOA_LOW_SPEED = N("EPR_AOA_LOW_SPEED"); AOA_RAMP_HI = N("EPR_AOA_RAMP_HI"); AOA_RAMP_LO = N("EPR_AOA_RAMP_LO");
            AOA_RAMP_V_HI = N("EPR_AOA_RAMP_V_HI"); AOA_RAMP_V_LO = N("EPR_AOA_RAMP_V_LO"); ATM = N("EPR_ATM");
            AZ_FIRST = N("EPR_AZ_FIRST"); AZ_LATE = N("EPR_AZ_LATE"); AZ_MACH_HI = N("EPR_AZ_MACH_HI"); AZ_MACH_LO = N("EPR_AZ_MACH_LO");
            AZ_SUBS = N("EPR_AZ_SUBS"); BANK_FLARE_MAX = N("EPR_BANK_FLARE_MAX"); BANK_FLARE_SLOPE = N("EPR_BANK_FLARE_SLOPE");
            BANK_FLARE_SPEED = N("EPR_BANK_FLARE_SPEED"); BANK_MAX = N("EPR_BANK_MAX"); BANK_MAX_ABORT = N("EPR_BANK_MAX_ABORT");
            BANK_MIN = N("EPR_BANK_MIN"); BANK_STOP_SPEED = N("EPR_BANK_STOP_SPEED"); BANK_TAEM_LIMIT = N("EPR_BANK_TAEM_LIMIT");
            BANK_TAEM_SPEED = N("EPR_BANK_TAEM_SPEED"); FAM_EXT_V = N("EPR_FAM_EXT_V"); FAM_SRV_BANK = N("EPR_FAM_SRV_BANK");
            FAM_SRV_DMAX = N("EPR_FAM_SRV_DMAX"); FAM_SRV_K = N("EPR_FAM_SRV_K"); FAM_SRV_V0 = N("EPR_FAM_SRV_V0");
            FAM_SRV_V1 = N("EPR_FAM_SRV_V1"); G0 = N("EPR_G0"); GAMMA = N("EPR_GAMMA"); GS_DT_MAX = N("EPR_GS_DT_MAX");
            GS_REV_TOL = N("EPR_GS_REV_TOL"); GUID_DRAG_INIT = N("EPR_GUID_DRAG_INIT"); HAC_LAT = N("EPR_HAC_LAT");
            HAC_LNG = N("EPR_HAC_LNG"); HDOT_MAX = N("EPR_HDOT_MAX"); GS_TAU = N("EPR_GS_TAU"); K_BANK_HDOT = N("EPR_K_BANK_HDOT"); K_HDOT = N("EPR_K_HDOT");
            K_LIFT = N("EPR_K_LIFT"); K_PAR = N("EPR_K_PAR"); MASS_K = N("EPR_MASS_K"); TRIM_FD = N("EPR_TRIM_FD"); TRIM_FL = N("EPR_TRIM_FL"); FLAP_X = N("EPR_FLAP_X"); FLAP_KF = N("EPR_FLAP_KF"); MIN_BANK_DELAZ_K = N("EPR_MIN_BANK_DELAZ_K");
            MIN_BANK_HI_HIGH = N("EPR_MIN_BANK_HI_HIGH"); MIN_BANK_HI_LOW = N("EPR_MIN_BANK_HI_LOW");
            MIN_BANK_LOW = N("EPR_MIN_BANK_LOW"); MIN_BANK_MACH = N("EPR_MIN_BANK_MACH"); NSIGN = N("EPR_NSIGN");
            ORG_LAT = N("EPR_ORG_LAT"); ORG_LNG = N("EPR_ORG_LNG"); PAR_SHIFT = N("EPR_PAR_SHIFT"); PAR_W_CTL = N("EPR_PAR_W_CTL");
            PAR_W_FUS = N("EPR_PAR_W_FUS"); PAR_W_WING = N("EPR_PAR_W_WING"); PREENTRY_BANK = N("EPR_PREENTRY_BANK");
            PR_SHARE = N("EPR_PR_SHARE"); R = N("EPR_R"); ROLL_ACCEL_LIMIT = N("EPR_ROLL_ACCEL_LIMIT");
            ROLL_RATE_LIMIT = N("EPR_ROLL_RATE_LIMIT"); ROT_SIGN = N("EPR_ROT_SIGN"); SB_V = N("EPR_SB_V"); SB_V_FULL = N("EPR_SB_V_FULL");
            TAEM_VEL = N("EPR_TAEM_VEL"); TRK_MAX = N("EPR_TRK_MAX"); WMAG = N("EPR_WMAG");
            AM_DW = N("EPR_AM_DW"); K3_HDOT = N("EPR_K3_HDOT"); KH_MIN = N("EPR_KH_MIN"); KH_MAX = N("EPR_KH_MAX");
            BANK_TAEM_REF = B("EPR_BANK_TAEM_REF"); K3_LATE_POS = B("EPR_K3_LATE_POS");
            SAT_AM_ON = B("EPR_SAT_AM_ON"); SAT_AM_DREF = B("EPR_SAT_AM_DREF");
            SAT_AM_MAX = N("EPR_SAT_AM_MAX"); SAT_AM_U0 = N("EPR_SAT_AM_U0"); SAT_AM_U1 = N("EPR_SAT_AM_U1");
            SAT_AM_V_FULL = N("EPR_SAT_AM_V_FULL"); SAT_AM_V_ZERO = N("EPR_SAT_AM_V_ZERO"); SAT_AM_TAU = N("EPR_SAT_AM_TAU");
            SAT_AM_RATE = N("EPR_SAT_AM_RATE"); SAT_AM_ACC = N("EPR_SAT_AM_ACC");
            AM_ON = B("EPR_AM_ON"); AM_SYNC = B("EPR_AM_SYNC"); AOA_RAMP_ON = B("EPR_AOA_RAMP_ON"); FAM_ADD = B("EPR_FAM_ADD");
            FAM_OK = B("EPR_FAM_OK"); FAM_READY = B("EPR_FAM_READY"); HAC_ON = B("EPR_HAC_ON"); SB_ON = B("EPR_SB_ON");
            USE_MIN_BANK = B("EPR_USE_MIN_BANK");
            GEO_X = e.Vec(e.Get("EPR_GEO_X")); GEO_Y = e.Vec(e.Get("EPR_GEO_Y")); NAXIS = e.Vec(e.Get("EPR_NAXIS"));
            WAXIS = e.Vec(e.Get("EPR_WAXIS"));
            AM_SLOPE_K = Tab(e, c, "EPR_AM_SLOPE_K"); CD_FIX = Tab(e, c, "EPR_CD_FIX"); AERO_FIX = Tab(e, c, "EPR_AERO_FIX"); FLAP_TAB = Tab(e, c, "EPR_FLAP_TAB"); CTL_PAR_A = Tab(e, c, "EPR_CTL_PAR_A");
            CTL_PAR_M = Tab(e, c, "EPR_CTL_PAR_M"); FUS_PAR_A = Tab(e, c, "EPR_FUS_PAR_A"); FUS_PAR_M = Tab(e, c, "EPR_FUS_PAR_M");
            LIFT_CURVE = Tab(e, c, "EPR_LIFT_CURVE"); LIFT_MACH = Tab(e, c, "EPR_LIFT_MACH"); PSEUDORE = Tab(e, c, "EPR_PSEUDORE");
            RHO = Tab(e, c, "EPR_RHO"); SB_FRAC = Tab(e, c, "EPR_SB_FRAC"); WING_PAR_A = Tab(e, c, "EPR_WING_PAR_A");
            WING_PAR_M = Tab(e, c, "EPR_WING_PAR_M");
            FAM = Family(e, c);
            // the state
            GS_DT = N("EPR_GS_DT"); GS_TLAST = N("EPR_GS_TLAST"); GS_AZ = N("EPR_GS_AZ"); GS_GLAT = N("EPR_GS_GLAT");
            GS_GLNG = N("EPR_GS_GLNG"); GS_RNG = N("EPR_GS_RNG"); GS_TROT = N("EPR_GS_TROT"); GS_U_ST = N("EPR_GS_U_ST");
            GS_U = N("EPR_GS_U"); GS_DREF = N("EPR_GS_DREF"); GS_DNOW = N("EPR_GS_DNOW"); GS_DMEAS = N("EPR_GS_DMEAS");
            GS_DERR = N("EPR_GS_DERR"); GS_ACMD = N("EPR_GS_ACMD"); GS_DEQ = N("EPR_GS_DEQ"); AM_ASUM = N("EPR_AM_ASUM");
            AM_AN = N("EPR_AM_AN"); AM_FDN = N("EPR_AM_FDN"); AM_AFD = N("EPR_AM_AFD"); AM_HOLD = N("EPR_AM_HOLD");
            GS_DERRF = N("EPR_GS_DERRF"); GS_ACMDF = N("EPR_GS_ACMDF"); GS_CORR = N("EPR_GS_CORR"); GS_ROLLREF = N("EPR_GS_ROLLREF"); GS_SIGN = N("EPR_GS_SIGN"); GS_REV = N("EPR_GS_REV");
            GS_BANK = N("EPR_GS_BANK"); GS_RATE = N("EPR_GS_RATE"); HINT_RHO = N("EPR_HINT_RHO"); PR_REF = N("EPR_PR_REF");
            FAM_EEXT = N("EPR_FAM_EEXT"); FAM_UT = N("EPR_FAM_UT");
            SAT_AM_UX = N("EPR_SAT_AM_UX"); SAT_AM_B = N("EPR_SAT_AM_B"); SAT_AM_BF = N("EPR_SAT_AM_BF"); SAT_AM_BR = N("EPR_SAT_AM_BR");
            GS_STARTED = B("EPR_GS_STARTED"); GS_PAST = B("EPR_GS_PAST"); GS_REVERSING = B("EPR_GS_REVERSING");
            FAM_ADD_PREP = B("EPR_FAM_ADD_PREP"); FAM_EXTD = B("EPR_FAM_EXTD");
            GS_SAT = e.Get("EPR_GS_SAT").ToString();
            HintList = e.Get("EPR_FAM_HINT") as ListValue;
            if (HintList == null) throw new InvalidCastException("EPR_FAM_HINT is not a list");
            HINT = new List<double>(HintList.Count);
            for (int i = 0; i < HintList.Count; i++) HINT.Add(Num(HintList[i]));
            HintN0 = HINT.Count;
            hintNew = false;
            // TAL: read always (lib_tal is loaded with entry_predict in ops6q); for a deorbit entry only when the switch is a TAL's
            if (tal)
            {
                TAL_A0 = N("TAL_A0"); TAL_NZ_DA = N("TAL_NZ_DA"); TAL_NZ_ITER = N("TAL_NZ_ITER"); TAL_NZ_LEAD = N("TAL_NZ_LEAD");
                TAL_NZ_RATE = N("TAL_NZ_RATE"); TAL_NZ_SET = N("TAL_NZ_SET"); TAL_VALPD1 = N("TAL_VALPD1"); TAL_VALPD2 = N("TAL_VALPD2");
                TAL_HDOT_GATE = B("TAL_HDOT_GATE"); TAL_V4N_ON = B("TAL_V4N_ON");
                // the TAL's range to go through the HAC (lib_tal talRngTo / talHacPath)
                TAL_RHG_ON = B("TAL_RHG_ON");
                if (TAL_RHG_ON)
                {
                    TAL_RHG_RSTAR = N("TAL_RHG_RSTAR"); TAL_RHG_BLA = N("TAL_RHG_BLA"); TAL_RHG_BLB = N("TAL_RHG_BLB");
                    TAL_HAC_TLAT = N("TAL_HAC_TLAT"); TAL_HAC_TLNG = N("TAL_HAC_TLNG"); TAL_HAC_HDG = N("TAL_HAC_HDG");
                    TAL_HAC_XC = N("TAL_HAC_XC"); TAL_HAC_RF = N("TAL_HAC_RF"); HAC_YSGN = N("EPR_HAC_YSGN");
                    TG_R1 = N("TG_R1"); TG_R2 = N("TG_R2"); TG_PSHA_MAX = N("TG_PSHA_MAX");
                }
                TAL_VEH_VI = N("TAL_VEH_VI"); TAL_VEH_T = N("TAL_VEH_T"); TAL_NZ_EL = N("TAL_NZ_EL"); TAL_NZ_QPREV = N("TAL_NZ_QPREV");
                TAL_NZ_A = N("TAL_NZ_A"); TAL_NZ_CAP = N("TAL_NZ_CAP"); TAL_NZ_NOW = N("TAL_NZ_NOW"); TAL_NZ_N = N("TAL_NZ_N");
            }
        }

        public Structure Out(string n)     // a written global's value as kOS holds it (ScalarValue.Create: an int when whole)
        {
            switch (n.ToUpperInvariant())
            {
                case "EPR_GS_DT": return S(GS_DT, n);
                case "EPR_GS_TLAST": return S(GS_TLAST, n);
                case "EPR_GS_STARTED": return new BooleanValue(GS_STARTED);
                case "EPR_GS_AZ": return S(GS_AZ, n);
                case "EPR_GS_PAST": return new BooleanValue(GS_PAST);
                case "EPR_GS_GLAT": return S(GS_GLAT, n);
                case "EPR_GS_GLNG": return S(GS_GLNG, n);
                case "EPR_GS_RNG": return S(GS_RNG, n);
                case "EPR_GS_TROT": return S(GS_TROT, n);
                case "EPR_GS_U_ST": return S(GS_U_ST, n);
                case "EPR_GS_U": return S(GS_U, n);
                case "EPR_GS_SAT": return new StringValue(GS_SAT);
                case "EPR_GS_DREF": return S(GS_DREF, n);
                case "EPR_GS_DNOW": return S(GS_DNOW, n);
                case "EPR_GS_DMEAS": return S(GS_DMEAS, n);
                case "EPR_GS_DERR": return S(GS_DERR, n);
                case "EPR_GS_ACMD": return S(GS_ACMD, n);
                case "EPR_GS_DEQ": return S(GS_DEQ, n);
                case "EPR_AM_ASUM": return S(AM_ASUM, n);
                case "EPR_AM_AN": return S(AM_AN, n);
                case "EPR_AM_FDN": return S(AM_FDN, n);
                case "EPR_AM_AFD": return S(AM_AFD, n);
                case "EPR_AM_HOLD": return S(AM_HOLD, n);
                case "EPR_GS_DERRF": return S(GS_DERRF, n);
                case "EPR_GS_ACMDF": return S(GS_ACMDF, n);
                case "EPR_GS_CORR": return S(GS_CORR, n);
                case "EPR_GS_ROLLREF": return S(GS_ROLLREF, n);
                case "EPR_GS_SIGN": return S(GS_SIGN, n);
                case "EPR_GS_REV": return S(GS_REV, n);
                case "EPR_GS_REVERSING": return new BooleanValue(GS_REVERSING);
                case "EPR_GS_BANK": return S(GS_BANK, n);
                case "EPR_GS_RATE": return S(GS_RATE, n);
                case "EPR_HINT_RHO": return S(HINT_RHO, n);
                case "EPR_PR_REF": return S(PR_REF, n);
                case "EPR_FAM_ADD_PREP": return new BooleanValue(FAM_ADD_PREP);
                case "EPR_FAM_EEXT": return S(FAM_EEXT, n);
                case "EPR_FAM_UT": return S(FAM_UT, n);
                case "EPR_FAM_EXTD": return new BooleanValue(FAM_EXTD);
                case "TAL_VEH_VI": return S(TAL_VEH_VI, n);
                case "TAL_VEH_T": return S(TAL_VEH_T, n);
                case "TAL_NZ_EL": return S(TAL_NZ_EL, n);
                case "TAL_NZ_QPREV": return S(TAL_NZ_QPREV, n);
                case "TAL_NZ_A": return S(TAL_NZ_A, n);
                case "TAL_NZ_CAP": return S(TAL_NZ_CAP, n);
                case "TAL_NZ_NOW": return S(TAL_NZ_NOW, n);
                case "TAL_NZ_N": return S(TAL_NZ_N, n);
                case "EPR_SAT_AM_UX": return S(SAT_AM_UX, n);
                case "EPR_SAT_AM_B": return S(SAT_AM_B, n);
                case "EPR_SAT_AM_BF": return S(SAT_AM_BF, n);
                case "EPR_SAT_AM_BR": return S(SAT_AM_BR, n);
            }
            throw new ArgumentException("not a written global: " + n);
        }
        static Structure S(double x, string n) { return ScalarValue.Create(Fin(x, n)); }

        // every value first (a non-finite one throws here, before any write), then the writes
        public void Commit(IEgEnv e)
        {
            var vals = new List<Structure>(Dirty.Count);
            foreach (var n in Dirty) vals.Add(Out(n));
            for (int i = 0; i < Dirty.Count; i++) e.Set(Dirty[i], vals[i]);
            if (hintNew)
            {
                var l = new ListValue();
                foreach (var h in HINT) l.Add(ScalarValue.Create(h));
                e.Set("EPR_FAM_HINT", l);
            }
            else
            {
                for (int i = 0; i < HINT.Count; i++)
                {
                    if (i < HintN0) { if (Num(HintList[i]) != HINT[i]) HintList[i] = ScalarValue.Create(HINT[i]); }
                    else HintList.Add(ScalarValue.Create(HINT[i]));
                }
            }
        }

        // ================================================================== the aero / air model
        double LogInterpE(double[][] tab, double x, double hint, out double iout)
        {
            int n = tab.Length;
            if (x <= tab[0][0]) { iout = 0; return tab[0][1]; }
            if (x >= tab[n - 1][0]) { iout = n - 2; return 0; }
            double i = Max(0, Min(hint, n - 2));
            while (!(i <= 0 || tab[(int)i][0] <= x)) i = i - 1;
            while (!(i >= n - 2 || tab[(int)i + 1][0] >= x)) i = i + 1;
            double a0 = tab[(int)i][0]; double a1 = tab[(int)i + 1][0];
            double y0 = tab[(int)i][1]; double y1 = tab[(int)i + 1][1];
            iout = i;
            if (y0 <= 0 || y1 <= 0) return 0;
            double f = (x - a0) / (a1 - a0);
            return Math.Pow(CE, Math.Log(y0) + f * (Math.Log(y1) - Math.Log(y0)));
        }
        double Rho(double altm)
        {
            double i;
            double r = LogInterpE(RHO, altm, HINT_RHO, out i);
            HINT_RHO = i; W("EPR_HINT_RHO");
            return r;
        }
        double MachFrom(double altm, double vrel, double rh)
        {
            double p = ps;        // kOS: eprPres(altm), read by the hook at the same altm
            if (p <= 0 || rh <= 0) return 0;
            return vrel / Sqrt(GAMMA * p / rh);
        }
        static double Hermite(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            for (int i = 1; i < n; i++)
            {
                if (keys[i][0] >= x)
                {
                    double x0 = keys[i - 1][0]; double y0 = keys[i - 1][1];
                    double x1 = keys[i][0]; double y1 = keys[i][1];
                    double sp = x1 - x0;
                    double t = (x - x0) / sp;
                    double m0 = keys[i - 1][3] * sp;
                    double m1 = keys[i][2] * sp;
                    double t2 = t * t; double t3 = t2 * t;
                    return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                           + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
                }
            }
            return keys[n - 1][1];
        }
        double PrRef()
        {
            if (PR_REF < 0) { PR_REF = Hermite(PSEUDORE, 1); W("EPR_PR_REF"); }
            return PR_REF;
        }
        double PrMult(double rhov)
        {
            double pr = Hermite(PSEUDORE, rhov) / PrRef();
            if (pr <= 1) return pr;
            return 1 + PR_SHARE * (pr - 1);
        }
        double AoA(double vrel)
        {
            if (AOA_RAMP_ON) return Min(AoANom(vrel), AoARamp(vrel));
            return AoANom(vrel);
        }
        double AoARamp(double vrel)
        {
            if (vrel < AOA_HIGH_SPEED)              // eprAoARamp's line under EPR_AOA_HIGH_SPEED
            {
                double fl = (vrel - AOA_LOW_SPEED) / (AOA_HIGH_SPEED - AOA_LOW_SPEED);
                return AOA_LOW + (AOA_RAMP_LO - AOA_LOW) * Max(0, Min(1, fl));
            }
            if (vrel >= AOA_RAMP_V_HI) return AOA_RAMP_HI;
            if (vrel <= AOA_RAMP_V_LO) return AOA_RAMP_LO;
            return AOA_RAMP_LO + (AOA_RAMP_HI - AOA_RAMP_LO) * (vrel - AOA_RAMP_V_LO) / (AOA_RAMP_V_HI - AOA_RAMP_V_LO);
        }
        double AoANom(double vrel)
        {
            if (vrel >= AOA_HIGH_SPEED) return AOA_HIGH;
            double span = AOA_HIGH_SPEED - AOA_LOW_SPEED;
            if (span <= 0) return AOA_LOW;
            double fr = (vrel - AOA_LOW_SPEED) / span;
            if (fr < 0) fr = 0;
            if (fr > 1) fr = 1;
            return AOA_LOW + (AOA_HIGH - AOA_LOW) * fr;
        }
        static int Bracket(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return 0;
            if (x >= keys[n - 1][0]) return n;
            for (int i = 1; i < n; i++) if (keys[i][0] >= x) return i;
            return n;
        }
        static double HermAt(double[][] keys, double x, double id)
        {
            if (id <= 0) return keys[0][1];
            int n = keys.Length;
            if (id >= n) return keys[n - 1][1];
            int i = (int)id;
            double x0 = keys[i - 1][0]; double y0 = keys[i - 1][1];
            double x1 = keys[i][0]; double y1 = keys[i][1];
            double sp = x1 - x0;
            double t = (x - x0) / sp;
            double m0 = keys[i - 1][3] * sp;
            double m1 = keys[i][2] * sp;
            double t2 = t * t; double t3 = t2 * t;
            return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                   + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
        }
        double[] Polar(double aoa, double mach)
        {
            double a = Max(0, Min(89, aoa));
            double s = Sin(Max(0, Min(90, aoa)));
            double ia = Bracket(LIFT_CURVE, s);
            double im = Bracket(LIFT_MACH, mach);
            double ip = Max(0, ia - PAR_SHIFT);
            double cl = K_LIFT * HermAt(LIFT_CURVE, s, ia) * HermAt(LIFT_MACH, mach, im);
            double pa = K_PAR * (
                PAR_W_WING * HermAt(WING_PAR_A, s, ip) * HermAt(WING_PAR_M, mach, im) +
                PAR_W_FUS * HermAt(FUS_PAR_A, s, ip) * HermAt(FUS_PAR_M, mach, im) +
                PAR_W_CTL * HermAt(CTL_PAR_A, s, ip) * HermAt(CTL_PAR_M, mach, im));
            return new double[] { cl * MASS_K * TRIM_FL, (cl * Tan(a) + pa) * MASS_K * TRIM_FD };   // x the mass and trim factors
        }
        double Cda(double aoa, double mach) { return Polar(aoa, mach)[1]; }
        double SbFrac(double mach, double spd)
        {
            if (!SB_ON || spd >= SB_V) return 0;
            double ramp = Min(1, (SB_V - spd) / (SB_V - SB_V_FULL));
            var t = SB_FRAC;
            double fr = t[t.Length - 1][1];
            if (mach <= t[0][0])
            {
                fr = t[0][1];
            }
            else if (mach < t[t.Length - 1][0])
            {
                for (int i = 1; i < t.Length; i++)
                {
                    if (mach <= t[i][0])
                    {
                        fr = t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]);
                        break;
                    }
                }
            }
            return fr * ramp;
        }
        double CdFix(double mach)
        {
            var t = CD_FIX;
            int n = t.Length;
            if (mach <= t[0][0]) return t[0][1];
            if (mach >= t[n - 1][0]) return t[n - 1][1];
            int i = (int)Min(Math.Floor((mach - t[0][0]) / (t[1][0] - t[0][0])), n - 2);
            return t[i][1] + (t[i + 1][1] - t[i][1]) * (mach - t[i][0]) / (t[i + 1][0] - t[i][0]);
        }
        // THE BODY FLAP'S DRAG TERM (kOS eprFlapTerm / python entry_flap_term): ln factor at this Mach for the tracked flap x; 0 with no flap (x <= -90)
        static double FlapTerm(double x, double kf, double[][] tab, double mach)
        {
            if (x <= -90.0 || tab == null) return 0.0;
            int n = tab.Length;
            double w = tab[n - 1][1], f = tab[n - 1][2];
            if (mach <= tab[0][0]) { w = tab[0][1]; f = tab[0][2]; }
            else if (mach < tab[n - 1][0])
            {
                for (int i = 1; i < n; i++)
                    if (mach <= tab[i][0])
                    {
                        double u = (mach - tab[i - 1][0]) / (tab[i][0] - tab[i - 1][0]);
                        w = tab[i - 1][1] + (tab[i][1] - tab[i - 1][1]) * u;
                        f = tab[i - 1][2] + (tab[i][2] - tab[i - 1][2]) * u;
                        break;
                    }
            }
            return kf * w * (x - f);
        }
        double[] AeroFix(double aoa, double mach)   // (drag, lift) factors of the entry's polar = kOS eprAeroFix
        {
            double[] lo = AERO_FIX[0], hi = AERO_FIX[1];
            double w = Math.Min(1, Math.Max(0, (mach - lo[0]) / (hi[0] - lo[0])));
            double da = Math.Max(aoa - 40, 0);
            double ft = 0;
            if (FLAP_X > -90) ft = FlapTerm(FLAP_X, FLAP_KF, FLAP_TAB, mach);
            return new double[] { Math.Pow(Math.E, lo[1] + (hi[1] - lo[1]) * w + (lo[2] + (hi[2] - lo[2]) * w) * da + ft),
                                  Math.Pow(Math.E, lo[3] + (hi[3] - lo[3]) * w + (lo[4] + (hi[4] - lo[4]) * w) * da) };
        }
        double CdaEntry(double aoa, double mach, double spd)
        {
            return Cda(aoa, mach) * (1 + CdFix(mach)) * AeroFix(aoa, mach)[0] * (1 + SbFrac(mach, spd));
        }
        Vector3d OmegaCross(Vector3d rv) { return Vector3d.Cross(WAXIS * WMAG, rv); }

        // talAoA (lib_tal.ks)
        double TalAoA(double vr, double vi)
        {
            if (vi < 0 || vr >= vi) return TAL_A0;
            double v10 = vi - TAL_VALPD1;
            if (vr < v10) return AoA(vr);
            double v11 = vi - TAL_VALPD2;
            double alp3 = AoA(v10);
            double adt3 = 0;
            if (v10 > AOA_LOW_SPEED && v10 < AOA_HIGH_SPEED)
            {
                adt3 = (AOA_HIGH - AOA_LOW) / (AOA_HIGH_SPEED - AOA_LOW_SPEED);
            }
            double dl1 = vi - v10;
            double dl2 = vi - v11;
            double dl3 = v11 - v10;
            double c211 = 0 - (alp3 - TAL_A0 + adt3 * (dl3 + 0.5 * dl2)) / (dl3 * dl1);
            if (vr < v11)
            {
                double x1 = vr - v10;
                return alp3 + adt3 * x1 + c211 * x1 * x1;
            }
            double c212 = 0 - (adt3 + 2 * c211 * dl3) / (2 * dl2);
            double x2 = vr - vi;
            return TAL_A0 + c212 * x2 * x2;
        }

        // ================================================================== geodesy and the lateral logic
        double[] ToGeoRaw(Vector3d rv, double tRot)
        {
            double rmag = rv.magnitude;
            double lat = Asin(Max(-1, Min(1, Vdot(rv.normalized, NAXIS))));
            Vector3d eq = rv - NAXIS * Vdot(rv, NAXIS);
            double lng = 0;
            if (eq.magnitude > 1)
            {
                Vector3d e0 = GEO_X;
                Vector3d e1 = GEO_Y;
                lng = Atan2(Vdot(eq, e1), Vdot(eq, e0)) - ROT_SIGN * WMAG * tRot * RADTODEG;
            }
            while (!(lng <= 180)) lng = lng - 360;
            while (!(lng > -180)) lng = lng + 360;
            return new double[] { lat, lng, rmag - R };
        }
        double[] ToGeoLive(Vector3d rv) { return ToGeoRaw(rv, 0); }
        Vector3d[] EastNorth(Vector3d rv)
        {
            Vector3d upv = rv.normalized;
            Vector3d eastv = OmegaCross(rv);
            if (eastv.magnitude < 0.001) return new Vector3d[] { new Vector3d(0, 0, 0), new Vector3d(0, 0, 0) };
            eastv = eastv.normalized;
            return new Vector3d[] { eastv, Vector3d.Cross(upv, eastv) * NSIGN };
        }
        double GcDist(double lat1, double lng1, double lat2, double lng2)
        {
            double h = Math.Pow(Sin((lat2 - lat1) / 2), 2)
                       + Cos(lat1) * Cos(lat2) * Math.Pow(Sin((lng2 - lng1) / 2), 2);
            return 2 * R * Asin(Min(1, Sqrt(Max(h, 0)))) * DEGTORAD;
        }
        double AzError(Vector3d rv, Vector3d vv, double tRot, double tgtLat, double tgtLng)
        {
            Vector3d vrelv = vv - OmegaCross(rv);
            Vector3d upv = rv.normalized;
            Vector3d hz = vrelv - upv * Vdot(vrelv, upv);
            if (hz.magnitude < 1) return 0;
            double[] g = ToGeoLive(rv);
            Vector3d eq = rv - WAXIS * Vdot(rv, WAXIS);
            if (eq.magnitude < 1) return 0;
            Vector3d[] en = EastNorth(rv);
            Vector3d east = en[0];
            Vector3d nrth = en[1];
            if (east.magnitude < 0.5) return 0;
            double hdg = Atan2(Vdot(hz, east), Vdot(hz, nrth));
            double dl = tgtLng - g[1];
            double brg = Atan2(Sin(dl) * Cos(tgtLat),
                               Cos(g[0]) * Sin(tgtLat) - Sin(g[0]) * Cos(tgtLat) * Cos(dl));
            double e = -(brg - hdg);
            while (!(e <= 180)) e = e - 360;
            while (!(e > -180)) e = e + 360;
            return e;
        }
        double MinBank(double mach, double delazDeg)
        {
            if (!USE_MIN_BANK) return 0;
            if (mach > MIN_BANK_MACH)
            {
                double need = MIN_BANK_DELAZ_K * Abs(delazDeg);
                if (need <= MIN_BANK_HI_LOW) return MIN_BANK_HI_LOW;
                return MIN_BANK_HI_HIGH;
            }
            return MIN_BANK_LOW;
        }
        double AzDeadband(double mach, bool first)
        {
            if (first) return AZ_FIRST;
            if (mach >= AZ_MACH_HI) return AZ_SUBS;
            if (mach <= AZ_MACH_LO) return AZ_LATE;
            double f = (mach - AZ_MACH_LO) / (AZ_MACH_HI - AZ_MACH_LO);
            return AZ_LATE + (AZ_SUBS - AZ_LATE) * f;
        }
        // entry_predict.ks eprLagD / eprLagA: the drag sample's step through a first-order lag of GS_TAU s (0 = none)
        double LagD(double x, double dtc)
        {
            GS_DERRF = (GS_DERRF < -1e8 || GS_TAU <= 0) ? x : GS_DERRF + (x - GS_DERRF) * dtc / (GS_TAU + dtc); W("EPR_GS_DERRF");
            return GS_DERRF;
        }
        double LagA(double x, double dtc)
        {
            GS_ACMDF = (GS_ACMDF < 0 || GS_TAU <= 0) ? x : GS_ACMDF + (x - GS_ACMDF) * dtc / (GS_TAU + dtc); W("EPR_GS_ACMDF");
            return GS_ACMDF;
        }

        double[] BankSlew(double cur, double tgt, double rate, double dt)
        {
            double err = tgt - cur;
            double dtc = Max(dt, 0.001);
            double want = err / dtc;
            if (want > ROLL_RATE_LIMIT) want = ROLL_RATE_LIMIT;
            if (want < 0 - ROLL_RATE_LIMIT) want = 0 - ROLL_RATE_LIMIT;
            double vmax = Sqrt(2 * ROLL_ACCEL_LIMIT * Abs(err));
            if (want > vmax) want = vmax;
            if (want < 0 - vmax) want = 0 - vmax;
            double hi = rate + ROLL_ACCEL_LIMIT * dt;
            double lo = rate - ROLL_ACCEL_LIMIT * dt;
            if (want > hi) want = hi;
            if (want < lo) want = lo;
            return new double[] { cur + want * dt, want };
        }
        double BankWithFlare(double bankDeg, double vr, bool taemRamp = true)   // taemRamp false: the flare and the stop only
        {
            double b = Abs(bankDeg);
            if (BANK_FLARE_SPEED > 0 && vr <= BANK_FLARE_SPEED && b > BANK_FLARE_MAX)
            {
                b = BANK_FLARE_MAX + (b - BANK_FLARE_MAX) * BANK_FLARE_SLOPE;
            }
            if (taemRamp && BANK_TAEM_SPEED > 0 && vr < BANK_TAEM_SPEED)
            {
                double span = BANK_TAEM_SPEED - TAEM_VEL;
                double w = 1;
                if (span > 0) w = (BANK_TAEM_SPEED - vr) / span;
                w = Max(0, Min(1, w));
                b = b * (1 - w * (1 - BANK_TAEM_LIMIT / BANK_MAX));
            }
            if (vr <= BANK_STOP_SPEED) b = 0;
            return b;
        }

        // ================================================================== the family
        double FamAt(int mi, double vr, int col)
        {
            double[] vs = FAM[mi][1];
            double[] cs = FAM[mi][col];
            int n = vs.Length;
            if (n == 0) return 0;
            if (vr >= vs[0]) return cs[0];
            if (vr <= vs[n - 1]) return cs[n - 1];
            while (!(HINT.Count > mi)) HINT.Add(1);
            int i = (int)Max(1, Min(n - 1, HINT[mi]));
            if (vs[i] <= vr)
            {
                while (!(i <= 1 || vs[i - 1] > vr)) i = i - 1;
            }
            else
            {
                while (!(vs[i] <= vr)) i = i + 1;
            }
            HINT[mi] = i;
            double f = (vs[i - 1] - vr) / Max(vs[i - 1] - vs[i], 0.000000001);
            return cs[i - 1] + (cs[i] - cs[i - 1]) * f;
        }
        double FamRef(double vr, double u, int col)
        {
            double uu = Max(0, Min(FAM_UTOP, u));
            double x = uu * (FAM.Length - 1);
            double i = Min(Math.Floor(x), FAM.Length - 2);
            double f = x - i;
            return FamAt((int)i, vr, col) * (1 - f) + FamAt((int)i + 1, vr, col) * f;
        }
        double FamRoll(double vr, double u) { return FamRef(vr, u, 5); }
        object[] FamInvert(double vr, double rngToGo)
        {
            int n = FAM.Length;
            double r0 = FamAt(0, vr, 4);
            if (rngToGo >= r0) return new object[] { 0.0, "low" };
            double rn = FamAt(n - 1, vr, 4);
            if (rngToGo <= rn) return new object[] { 1.0, "high" };
            int i = 1;
            while (!(i >= n))
            {
                double ri = FamAt(i, vr, 4);
                if (ri <= rngToGo)
                {
                    double rp = FamAt(i - 1, vr, 4);
                    double span = rp - ri;
                    double f = 0;
                    if (Abs(span) > 0.000000001) f = (rp - rngToGo) / span;
                    return new object[] { (i - 1 + f) / (n - 1), "" };
                }
                i = i + 1;
            }
            return new object[] { 1.0, "high" };
        }
        void FamAddPrep()
        {
            FAM_EEXT = 0; W("EPR_FAM_EEXT");
            FAM_UT = -1; W("EPR_FAM_UT");
            FAM_EXTD = false; W("EPR_FAM_EXTD");
            int n = FAM.Length;
            if (n < 2) return;
            FAM_ADD_PREP = true; W("EPR_FAM_ADD_PREP");
            int h = (int)Math.Floor(n / 2.0);
            double[] vsm = FAM[h][1];
            if (vsm.Length > 0)
            {
                if (vsm[vsm.Length - 1] < 0.5 * (TAEM_VEL + FAM_EXT_V)) { FAM_EXTD = true; W("EPR_FAM_EXTD"); }
            }
            if (FAM_EXTD)
            {
                var hs = new List<double>(HINT);
                var ex = new List<double>();
                int mi = 0;
                while (!(mi >= n))
                {
                    ex.Add(FamAt(mi, TAEM_VEL, 4));
                    mi = mi + 1;
                }
                HINT = hs; hintNew = true;
                if (n % 2 == 1) FAM_EEXT = ex[h]; else FAM_EEXT = 0.5 * (ex[h - 1] + ex[h]);
                W("EPR_FAM_EEXT");
            }
            double ut = -1;
            int i = 0;
            while (!(i >= n - 1))
            {
                double b0 = FAM[i][0][0];
                double b1 = FAM[i + 1][0][0];
                if (b1 <= b0) return;
                if (ut < 0 && b0 <= FAM_SRV_BANK && FAM_SRV_BANK <= b1)
                {
                    ut = (i + (FAM_SRV_BANK - b0) / (b1 - b0)) / (n - 1);
                }
                i = i + 1;
            }
            FAM_UT = ut; W("EPR_FAM_UT");
        }
        double FamExcess()
        {
            if (!FAM_ADD) return 0;
            if (!FAM_ADD_PREP) FamAddPrep();
            return FAM_EEXT;
        }
        double FamRngTo(double glat, double glng, double tgtLat, double tgtLng)
        {
            if (FAM_ADD && HAC_ON)
            {
                return GcDist(glat, glng, ORG_LAT, ORG_LNG) - GcDist(tgtLat, tgtLng, ORG_LAT, ORG_LNG);
            }
            return GcDist(glat, glng, tgtLat, tgtLng);
        }
        // lib_tal's talHacPath (TAEM's HAC path from a ground position) and talRngTo (the TAL's range to go), as kOS
        double TalHacPath(double glat, double glng)
        {
            double d = GcDist(TAL_HAC_TLAT, TAL_HAC_TLNG, glat, glng);
            double dl = glng - TAL_HAC_TLNG;
            double brg = Atan2(Sin(dl) * Cos(glat), Cos(TAL_HAC_TLAT) * Sin(glat) - Sin(TAL_HAC_TLAT) * Cos(glat) * Cos(dl));
            double rel = brg - TAL_HAC_HDG;
            double x = d * Cos(rel);
            double y = d * Sin(rel);
            double ys = HAC_YSGN;
            double rf = TAL_HAC_RF;
            double xcir = TAL_HAC_XC - x;
            double ycir = ys * rf - y;
            double rcir = Sqrt(xcir * xcir + ycir * ycir);
            double signy = 1;
            if (y < 0) signy = -1;
            double pp = 0;
            double rtan = 0;
            for (int k = 0; k < 2; k++)
            {
                double rturn = rf + TG_R1 * pp + TG_R2 * pp * pp;
                rtan = 0;
                if (rcir > rturn) rtan = Sqrt(rcir * rcir - rturn * rturn);
                double pst = Atan2(ycir, xcir) - ys * Atan2(rturn, rtan);
                while (!(pst <= 180)) pst = pst - 360;
                while (!(pst > -180)) pst = pst + 360;
                double pshan = 0 - pst * ys;
                bool acq = pp > 0 && pp <= 30;
                if (((!acq) && (pshan < -1 || ys != signy)) || (pp > 90 && pshan < pp - 180)) pshan = pshan + 360;
                pp = Max(0, Min(TG_PSHA_MAX, pshan));
            }
            return (rf * pp + 0.5 * TG_R1 * pp * pp + (1.0 / 3.0) * TG_R2 * Math.Pow(pp, 3)) * (Math.PI / 180) - TAL_HAC_XC + rtan;
        }
        double TalRngTo(double glat, double glng, double tgtLat, double tgtLng)
        {
            double rgc = FamRngTo(glat, glng, tgtLat, tgtLng);
            if ((!TAL_RHG_ON) || (!FAM_ADD) || (!HAC_ON) || TAL_HAC_RF <= 0 || rgc >= TAL_RHG_BLB) return rgc;
            double rh = TalHacPath(glat, glng) - TAL_RHG_RSTAR;
            double w = 1;
            if (rgc > TAL_RHG_BLA) w = (TAL_RHG_BLB - rgc) / (TAL_RHG_BLB - TAL_RHG_BLA);
            return rgc + w * (rh - rgc);
        }
        double FamServo(double u, double vr)
        {
            if ((!FAM_ADD) || FAM_UT < 0) return u;
            double fv = 0;
            if (vr >= FAM_SRV_V1) fv = 1;
            else if (vr > FAM_SRV_V0) fv = (vr - FAM_SRV_V0) / (FAM_SRV_V1 - FAM_SRV_V0);
            return Max(0, Min(FAM_UTOP, u + Max(0 - FAM_SRV_DMAX, Min(FAM_SRV_DMAX, FAM_SRV_K * fv * (u - FAM_UT)))));
        }
        double AmBand(double vr)
        {
            double vf = AM_V_FULL;
            double vz = AM_V_ZERO;
            if (FAM_ADD) { vf = AM_V_FULL_FAM; vz = AM_V_ZERO_FAM; }
            return AM_LIM * Max(0, Min(1, (vr - vz) / (vf - vz)));
        }
        // entry_predict.ks eprFamInvertX / eprSatAmTarget / eprSatAmStep: the saturation alpha bias
        double FamInvertX(double vr, double rngToGo, double u)
        {
            int n = FAM.Length;
            double rn = FamAt(n - 1, vr, 4);
            if (rngToGo <= rn)
            {
                double sp = FamAt(n - 2, vr, 4) - rn;
                double f = 0;
                if (sp > 0.000000001) f = (rn - rngToGo) / sp;
                return 1 + f / (n - 1);
            }
            double r0 = FamAt(0, vr, 4);
            if (rngToGo >= r0)
            {
                double sp = r0 - FamAt(1, vr, 4);
                double f = 0;
                if (sp > 0.000000001) f = (rngToGo - r0) / sp;
                return 0 - f / (n - 1);
            }
            return u;
        }
        double SatAmTarget(double ux, double vr)
        {
            double x = (ux - SAT_AM_U0) / (SAT_AM_U1 - SAT_AM_U0);
            double sm = 0;
            if (x >= 1) sm = 1; else if (x > 0) sm = x * x * (3 - 2 * x);
            double fv = Max(0, Min(1, (vr - SAT_AM_V_ZERO) / (SAT_AM_V_FULL - SAT_AM_V_ZERO)));
            return SAT_AM_MAX * sm * fv;
        }
        double SatAmStep(double tgt, double dtc)
        {
            SAT_AM_BF = SAT_AM_BF + (tgt - SAT_AM_BF) * dtc / (SAT_AM_TAU + dtc); W("EPR_SAT_AM_BF");
            double want = (SAT_AM_BF - SAT_AM_B) / dtc;
            double rt = Max(SAT_AM_BR - SAT_AM_ACC * dtc, Min(SAT_AM_BR + SAT_AM_ACC * dtc, want));
            SAT_AM_BR = Max(0 - SAT_AM_RATE, Min(SAT_AM_RATE, rt)); W("EPR_SAT_AM_BR");
            SAT_AM_B = SAT_AM_B + SAT_AM_BR * dtc; W("EPR_SAT_AM_B");
            return SAT_AM_B;
        }
        double AmSlopeK(double mach)
        {
            var t = AM_SLOPE_K;
            if (mach <= t[0][0]) return t[0][1];
            for (int i = 1; i < t.Length; i++)
            {
                if (mach <= t[i][0]) return t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]);
            }
            return t[t.Length - 1][1];
        }

        // ================================================================== lib_tal's Nz limiter
        double TalNzAt(double a, double mach, double dk, double ks, double c0)
        {
            double[] p = Polar(a, mach);
            return dk * (1 + ks * (p[1] - c0) / c0) * Sqrt(p[0] * p[0] + p[1] * p[1]) / p[1] / G0;
        }
        void TalNzStep(double dm, double aRef, double sched, double mach, double el, double qa)
        {
            double kq = 1;
            if (TAL_NZ_QPREV > 0 && qa > 0) kq = 1 + Max(0, qa - TAL_NZ_QPREV) / Max(el, 0.5) * TAL_NZ_LEAD / qa;
            TAL_NZ_QPREV = qa; W("TAL_NZ_QPREV");
            double ks = AmSlopeK(mach);
            double[] p = Polar(aRef, mach);
            double c0 = p[1];
            double dk = dm * kq;
            TAL_NZ_NOW = dk * Sqrt(p[0] * p[0] + p[1] * p[1]) / c0 / G0; W("TAL_NZ_NOW");
            double lo = sched - TAL_NZ_DA;
            double hi = sched + AM_LIM;
            if (TalNzAt(hi, mach, dk, ks, c0) <= TAL_NZ_SET) { TAL_NZ_A = hi; W("TAL_NZ_A"); return; }
            if (TalNzAt(lo, mach, dk, ks, c0) >= TAL_NZ_SET) { TAL_NZ_A = lo; W("TAL_NZ_A"); return; }
            for (double k = 0; !(k >= TAL_NZ_ITER); k = k + 1)
            {
                double mid = 0.5 * (lo + hi);
                if (TalNzAt(mid, mach, dk, ks, c0) > TAL_NZ_SET) hi = mid; else lo = mid;
            }
            TAL_NZ_A = 0.5 * (lo + hi); W("TAL_NZ_A");
        }

        // ================================================================== THE CYCLE: eprGuidStep / talGuidStep
        // inp: EgIn's list as doubles + vectors; nowT / nowT2: TIME:SECONDS (the second = talGuidStep's TAL_VEH_T read)
        public double Run(Vector3d rv, Vector3d vv, double tgtLat, double tgtLng, double tRot, double dt, double dMeas,
                          double aoaNow, double fdN, double nowT, double nowT2, double pres)
        {
            now = nowT; now2 = nowT2; ps = pres;
            double dtc = dt;
            if (dtc < 0)
            {
                double tn = now;
                if (GS_TLAST < 0) dtc = 0.05; else dtc = tn - GS_TLAST;
                GS_TLAST = tn; W("EPR_GS_TLAST");
                if (dtc > GS_DT_MAX) dtc = GS_DT_MAX;
                if (dtc < 0.001) dtc = 0.001;
            }
            GS_DT = dtc; W("EPR_GS_DT");
            if (tal) { TAL_NZ_EL = TAL_NZ_EL + dtc; W("TAL_NZ_EL"); }
            double altm = rv.magnitude - R;
            Vector3d vrelv = vv - OmegaCross(rv);
            double vr = vrelv.magnitude;
            double rho = 0;
            if (altm < ATM) rho = Rho(altm);
            double mach = 0;
            double dNow = 0;
            if (rho > 0 && vr > 1)
            {
                mach = MachFrom(altm, vr, rho);
                double pr = PrMult(rho * vr);
                double a0 = tal ? TalAoA(vr, (GS_STARTED ? TAL_VEH_VI : -1)) : AoA(vr);
                dNow = CdaEntry(a0, mach, vr) * 0.5 * rho * vr * vr * pr;
            }
            if (dNow >= GUID_DRAG_INIT)
            {
                if (tal && !GS_STARTED)
                {
                    TAL_VEH_VI = vr; W("TAL_VEH_VI");
                    TAL_VEH_T = now2; W("TAL_VEH_T");
                }
                GS_STARTED = true; W("EPR_GS_STARTED");
            }
            bool famAddHac = FAM_ADD && HAC_ON;
            if (famAddHac) GS_AZ = AzError(rv, vv, tRot, HAC_LAT, HAC_LNG);
            else GS_AZ = AzError(rv, vv, tRot, tgtLat, tgtLng);
            W("EPR_GS_AZ");

            double mag = PREENTRY_BANK;
            if (GS_STARTED && FAM_READY && FAM_OK)
            {
                double[] gi = ToGeoLive(rv);
                double rng = tal ? TalRngTo(gi[0], gi[1], tgtLat, tgtLng) : FamRngTo(gi[0], gi[1], tgtLat, tgtLng);
                GS_PAST = (Abs(GS_AZ) > 90); W("EPR_GS_PAST");
                if (GS_PAST && !famAddHac) rng = -rng;
                rng = rng + FamExcess();
                GS_GLAT = gi[0]; W("EPR_GS_GLAT");
                GS_GLNG = gi[1]; W("EPR_GS_GLNG");
                GS_RNG = rng; W("EPR_GS_RNG");
                GS_TROT = tRot; W("EPR_GS_TROT");
                object[] inv = FamInvert(vr, rng);
                if (!tal && SAT_AM_ON) { SAT_AM_UX = FamInvertX(vr, rng, (double)inv[0]); W("EPR_SAT_AM_UX"); }
                GS_U_ST = (double)inv[0]; W("EPR_GS_U_ST");
                GS_U = FamServo((double)inv[0], vr); W("EPR_GS_U");
                GS_SAT = (string)inv[1]; W("EPR_GS_SAT");
                GS_DREF = FamRef(vr, GS_U, 2); W("EPR_GS_DREF");
                GS_DNOW = dNow; W("EPR_GS_DNOW");
                if (dMeas >= 0)
                {
                    GS_DMEAS = dMeas; W("EPR_GS_DMEAS");
                    GS_DERR = dMeas - GS_DREF; W("EPR_GS_DERR");
                }
                else
                {
                    GS_DMEAS = -1; W("EPR_GS_DMEAS");
                    GS_DERR = dNow - GS_DREF; W("EPR_GS_DERR");
                }
                GS_ACMD = -1; W("EPR_GS_ACMD");
                GS_DEQ = GS_DERR + GS_DREF; W("EPR_GS_DEQ");
                if (AM_ON && aoaNow > 0 && dMeas > 0)
                {
                    double sched = tal ? TalAoA(vr, TAL_VEH_VI) : AoA(vr);
                    double aTop = sched + SAT_AM_MAX;         // the one total cap (not the TAL)
                    if (!tal && SAT_AM_ON)                     // the schedule up by the bias, the reference drag with it
                    {
                        double sb = SatAmStep(SatAmTarget(SAT_AM_UX, vr), dtc);
                        if (sb != 0)
                        {
                            if (SAT_AM_DREF) { GS_DREF = GS_DREF * Cda(sched + sb, mach) / Cda(sched, mach); W("EPR_GS_DREF"); }
                            sched = sched + sb;
                        }
                    }
                    double band = AmBand(vr);
                    double aRef = aoaNow;
                    bool fresh = true;
                    if (AM_SYNC && fdN >= 0)
                    {
                        if (fdN != AM_FDN)
                        {
                            if (AM_AN > 0) AM_AFD = AM_ASUM / AM_AN; else AM_AFD = aoaNow;
                            W("EPR_AM_AFD");
                            AM_ASUM = 0; W("EPR_AM_ASUM");
                            AM_AN = 0; W("EPR_AM_AN");
                            AM_FDN = fdN; W("EPR_AM_FDN");
                        }
                        else if (AM_HOLD > 0)
                        {
                            fresh = false;
                        }
                        AM_ASUM = AM_ASUM + aoaNow; W("EPR_AM_ASUM");
                        AM_AN = AM_AN + 1; W("EPR_AM_AN");
                        if (AM_AFD > 0) aRef = AM_AFD;
                    }
                    double cdn = Cda(aRef, mach);
                    GS_DEQ = tal ? dMeas * Cda(sched, mach) / cdn : dMeas * Math.Pow(Cda(sched, mach) / cdn, AM_DW); W("EPR_GS_DEQ");   // at a weight (not the TAL)
                    GS_DERR = GS_DEQ - GS_DREF; W("EPR_GS_DERR");
                    if (fresh)
                    {
                        double dela = 0;
                        if (Abs(dMeas - GS_DREF) >= AM_DDMIN * GS_DREF)
                        {
                            double slope = (Cda(aRef + 0.5, mach) - Cda(aRef - 0.5, mach)) * AmSlopeK(mach);
                            if (slope > 0)
                            {
                                dela = Max(0 - AM_LIM, Min(AM_LIM, AM_G * cdn * (GS_DREF / dMeas - 1) / slope));
                            }
                        }
                        AM_HOLD = aRef + dela; W("EPR_AM_HOLD");
                    }
                    double ac = Max(sched - band, Min(sched + band, AM_HOLD));
                    if (!tal && SAT_AM_ON) ac = Min(aTop, ac);  // the vernier clipped inside the total cap
                    GS_ACMD = LagA(ac, dtc); W("EPR_GS_ACMD");
                    if (tal && TAL_V4N_ON)
                    {
                        if (fresh) { TalNzStep(dMeas, aRef, sched, mach, TAL_NZ_EL, 0.5 * rho * vr * vr); TAL_NZ_EL = 0; W("TAL_NZ_EL"); }
                        if (TAL_NZ_A > 0)
                        {
                            TAL_NZ_CAP = (TAL_NZ_CAP < 0 ? TAL_NZ_A : Min(TAL_NZ_A, TAL_NZ_CAP + TAL_NZ_RATE * dtc)); W("TAL_NZ_CAP");
                            if (TAL_NZ_CAP < GS_ACMD) { GS_ACMD = TAL_NZ_CAP; W("EPR_GS_ACMD"); TAL_NZ_N = TAL_NZ_N + 1; W("TAL_NZ_N"); }
                        }
                    }
                }
                double hdotNow = Vdot(vrelv, rv.normalized);
                double derrF = LagD(GS_DERR, dtc);                         // the drag sample's step smoothed (LagD)
                bool late = !tal && K3_LATE_POS && BANK_TAEM_SPEED > 0 && vr < BANK_TAEM_SPEED;   // the late-position K3 term (not the TAL)
                double dK3 = late ? Max(0, derrF) : derrF;
                double khEff = tal ? K_HDOT : Max(KH_MIN, Min(KH_MAX, K_HDOT + K3_HDOT * dK3));   // C16's drag bias (not the TAL)
                double bias = Max(0 - HDOT_MAX, Min(HDOT_MAX, khEff * derrF));
                double hdotDes = FamRef(vr, GS_U, 3) + bias;
                GS_CORR = Max(0 - TRK_MAX, Min(TRK_MAX, K_BANK_HDOT * (hdotNow - hdotDes))); W("EPR_GS_CORR");
                if (tal && TAL_HDOT_GATE && GS_CORR < 0) { if (K_HDOT * derrF < 0 - HDOT_MAX) { GS_CORR = 0; W("EPR_GS_CORR"); } }
                GS_ROLLREF = FamRoll(vr, GS_U); W("EPR_GS_ROLLREF");
                double top = tal ? (TAL_V4N_ON ? BANK_MAX_ABORT : BANK_MAX) : BANK_MAX;
                // the reference through the TAEM ramp, the correction on top (FAM_ADD's column is
                // the bank before the ramp)
                double rrf = (!tal && BANK_TAEM_REF && FAM_ADD) ? BankWithFlare(GS_ROLLREF, vr) : GS_ROLLREF;
                mag = Max(BANK_MIN, Min(top, rrf + GS_CORR));
            }
            else
            {
                GS_ROLLREF = 0; W("EPR_GS_ROLLREF");
                GS_DREF = 0; W("EPR_GS_DREF");
                GS_DERR = 0; W("EPR_GS_DERR");
                GS_ACMD = -1; W("EPR_GS_ACMD");
                GS_DEQ = 0; W("EPR_GS_DEQ");
            }

            if (GS_SIGN == 0)
            {
                GS_SIGN = GS_AZ >= 0 ? 1 : -1; W("EPR_GS_SIGN");
            }
            bool isFirst = false;
            if (GS_REV == 0) isFirst = true;
            double db = AzDeadband(mach, isFirst);
            double ns = GS_SIGN;
            if (GS_AZ > db) ns = 1;
            else if (GS_AZ < 0 - db) ns = -1;
            if (ns != GS_SIGN)
            {
                GS_REV = GS_REV + 1; W("EPR_GS_REV");
                GS_SIGN = ns; W("EPR_GS_SIGN");
                GS_REVERSING = true; W("EPR_GS_REVERSING");
            }
            double want = GS_SIGN * mag;
            if (USE_MIN_BANK && GS_STARTED && GS_SIGN * GS_AZ > 0 && dNow >= GUID_DRAG_INIT)
            {
                double fl = MinBank(mach, GS_AZ);
                if (Abs(want) < fl) want = GS_SIGN * fl;
            }
            if (vr <= BANK_STOP_SPEED) want = 0;

            double[] sl = BankSlew(GS_BANK, want, GS_RATE, dtc);
            GS_BANK = sl[0]; W("EPR_GS_BANK");
            if (GS_REVERSING && Abs(sl[0] - want) <= GS_REV_TOL)
            {
                GS_REVERSING = false; W("EPR_GS_REVERSING");
            }
            GS_RATE = sl[1]; W("EPR_GS_RATE");
            double sg = 1;
            if (GS_BANK < 0) sg = -1;
            return sg * BankWithFlare(GS_BANK, vr, tal || !BANK_TAEM_REF);   // the ramp is in the reference
        }
    }
}
