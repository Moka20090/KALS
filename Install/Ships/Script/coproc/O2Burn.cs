// ops2q's o2qBurnTick per-tick work in C# -- the PEG 7 sensed-dV count, the steering direction, the throttle /
// taper, the cut, the thrust-lost and time guards, the scalar axis check, and the aim-freeze decision. PURE: double[3]
// vectors, no Unity or kOS type, so an offline harness runs it against ops2q.ks's own o2qBurnTick in the kOS VM (tests/o2burn_offline).
// NOTHING CALLS IT YET (ops2q.ks is untouched).
// Every number below is lib_o2peg.ks's (o2pSense / o2pDir / o2pAlong / o2pTaper / o2pThr / o2pEnd) or ops2q.ks o2qBurnTick's, in the same
// order of the same double operations, so the two agree bit for bit; the constants come from kOS at Arm (the kOS globals stay the one place
// to tune them, a C# copy would drift).
// WHAT STAYS IN kOS (the game, the decisions, the text): reading the engines (their thrust / axes / available thrust, the OMS RM), the trim
// line (o2lSteer), the early aim bias (o2qFfo), the DAP aim (o2qAimTv), the log lines and rows, the EXEC / CUT OFF flow, PEG 4's and PEG 8's
// re-solve of VGO (they hand it back with SetVgo between Sense and Decide).
using System;

namespace KalsCoproc
{
    public class O2Burn
    {
        // ---- the constants (kOS's: lib_o2peg O2P_*, ops2q O2Q_*; Arm takes them)
        public double Cut = 0.01, TaperS = 0.25, TaperDtK = 12, DtmDecay = 0.97, HoldDv = 1, HoldTgo = 1.5, GuardK = 1.5, GuardS = 5, AxisMin = 0.9;
        public double AimFreezeV = 3, FrzMeasV = 4.5, FrzMeasMax = 4;
        public bool FrzMeas = true, Ffo = true;
        public int LogTicks = 5;

        // ---- pg (lib_o2peg's lexicon)
        public double[] Vgo = new double[3], Sens = new double[3], Hdir = new double[3];
        public double Tot, Tprev = -1, Dtm, T0 = -1, Tguard, Aav;
        public bool Hold, HasGuard;             // HasGuard = pg:HASKEY("tguard") (= HASKEY("aav"): o2pEnd sets both together)
        public double Tb;                       // o2qB["tb"]: the planned burn's length
        // ---- o2qB's burn flags
        public double BurnT0;                   // o2qB["t0"]: the ignition
        public bool Scalar, Chk, Frz, TaplLogged, Pchk;
        public int N;
        public bool Armed;

        // ---- the bits of Decide's event word
        public const int E_TAPER = 1, E_PCHK = 2, E_FREEZE = 4, E_FRZM = 8, E_FFO = 16, E_AIM = 32, E_ROW = 64, E_END = 128;

        // ---- the last Sense's context (Decide reads it)
        double[] fv = new double[3], av = new double[3], fore = new double[3];
        double ms;
        // ---- Decide's results
        public string Why = "";
        public double Thr, Along, Tpr, AAv, FrzAlong, AngOl, AngTl;
        public double[] Tl = new double[3], AimDir = new double[3], DirF = new double[3];
        public int Events;

        // ---- vector helpers (lib_o2orb o2Unit: |x| < 1e-12 -> 0; kOS :NORMALIZED (Vector3d.normalized): |x| <= 1e-5 -> 0)
        static double Dot(double[] a, double[] b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
        static double Mag(double[] a) { return Math.Sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); }
        static double[] Unit(double[] a)
        {
            double m = Mag(a);
            if (m < 1E-12) return new double[] { 0, 0, 0 };
            return new double[] { a[0] / m, a[1] / m, a[2] / m };
        }
        static double[] Nrm(double[] a)         // kOS :NORMALIZED
        {
            double m = Mag(a);
            if (!(m > 1E-5)) return new double[] { 0, 0, 0 };
            return new double[] { a[0] / m, a[1] / m, a[2] / m };
        }
        static double[] Cp(double[] a) { return new double[] { a[0], a[1], a[2] }; }
        // lib_o2line o2lAng: the angle (deg) between two lines
        public static double Ang(double[] a, double[] b)
        {
            double c = Dot(Nrm(a), Nrm(b));
            c = Math.Max(-1, Math.Min(1, c));
            return Math.Acos(c) * (180.0 / Math.PI);
        }

        // a new burn at the ignition: o2pNew's / o2pRefresh's vgo and tot, nothing sensed
        public void Arm(double[] vgo, double tot, double tb, double burnT0)
        {
            Vgo = Cp(vgo); Tot = tot; Tb = tb; BurnT0 = burnT0;
            Sens = new double[3]; Hdir = new double[3];
            Tprev = -1; Dtm = 0; T0 = -1; Tguard = 0; Aav = 0; Hold = false; HasGuard = false;
            Scalar = false; Chk = false; Frz = false; TaplLogged = false; Pchk = false; N = 0;
            Why = ""; Thr = 0; Events = 0; Armed = true;
        }

        // ---- lib_o2peg ----
        // o2pSense: the engines' acceleration a (inertial) read at t; the first sample starts the count
        void SenseA(double[] a, double t)
        {
            if (Tprev >= 0)
            {
                double dt = t - Tprev;
                double[] d = new double[] { a[0] * dt, a[1] * dt, a[2] * dt };
                Dtm = Math.Max(dt, Dtm * DtmDecay);
                Vgo = new double[] { Vgo[0] - d[0], Vgo[1] - d[1], Vgo[2] - d[2] };
                Sens = new double[] { Sens[0] + d[0], Sens[1] + d[1], Sens[2] + d[2] };
            }
            else T0 = t;
            Tprev = t;
        }
        // o2pDir: along VGO, held once VGO is under max(HoldDv, HoldTgo x aav)
        public double[] Dir()
        {
            if (Hold) return Hdir;
            double[] g = Vgo;
            double lim = HoldDv;
            if (HasGuard) lim = Math.Max(lim, HoldTgo * Aav);
            if (Mag(g) <= lim && Tprev >= 0)
            {
                Hold = true;
                Hdir = Unit(g);
                return Hdir;
            }
            return Unit(g);
        }
        public double AlongNow() { return Dot(Vgo, Dir()); }
        public double LastAlong;                // the last o2pAlong the tick evaluated (Decide's Along result: no extra Dir() call, it can set the hold)
        double Al() { LastAlong = AlongNow(); return LastAlong; }
        // o2pTaper
        public double Taper() { return Math.Max(TaperS, TaperDtK * Dtm); }
        // o2pThr
        public double ThrFor(double along, double aMax, double tap)
        {
            if (along < Cut) return 0;
            return Math.Min(1, along / Math.Max(aMax * tap, 0.001));
        }
        // o2pEnd: "" / CUT / THRUST / GUARD
        string End(double t, double aAvail)
        {
            if (T0 < 0) return "";
            double al = Al();
            if (al < Cut) return "CUT";
            if (t - T0 > 2 && aAvail < 0.001) return "THRUST";
            if (!HasGuard)
            {
                Tguard = T0 + GuardK * Tb + GuardS;
                Aav = aAvail;
                HasGuard = true;
            }
            else if (aAvail > 0.001 && aAvail < 0.9 * Aav)
            {
                Tguard = Math.Max(Tguard, t + GuardK * al / aAvail + GuardS);
                Aav = aAvail;
            }
            if (t > Tguard) return "GUARD";
            return "";
        }

        // ---- the tick: Sense (the count), [kOS: PEG 4 / 8 re-solve -> SetVgo], Decide (the end, the throttle, the aim).
        // in: [0] now, [1..3] the engines' axes force sum fv (kN), [4] fs (their scalar thrust), [5..7] av (the available thrust along them, after the RM),
        //     [8..10] SHIP:FACING:FOREVECTOR, [11] SHIP:AVAILABLETHRUST, [12] SHIP:MASS, [13] ol ok (0/1), [14..16] ol f (the measured line, kN),
        //     [17..19] the trim line o2lSteer gave (the fallback pa when the addon is not there), [20] engines left, [21] the crew's cut (0/1),
        //     [22] guidance lost (0/1)
        public const int IN_N = 23;
        double now;
        bool olOk, gdl, cutreq;
        double[] olF = new double[3], trim = new double[3];
        double fs, shipAvail;
        int engLen;

        void Load(double[] x)
        {
            now = x[0];
            fv = new double[] { x[1], x[2], x[3] }; fs = x[4];
            av = new double[] { x[5], x[6], x[7] };
            fore = new double[] { x[8], x[9], x[10] }; shipAvail = x[11]; ms = x[12];
            olOk = x[13] != 0; olF = new double[] { x[14], x[15], x[16] };
            trim = new double[] { x[17], x[18], x[19] };
            engLen = (int)Math.Round(x[20]); cutreq = x[21] != 0; gdl = x[22] != 0;
        }

        // the count. Returns 1 when the scalar axis check just fired (the ratio in ScalarRatio), else 0
        public double ScalarRatio;
        public int Sense(double[] x)
        {
            Load(x);
            int ev = 0;
            if (olOk) fv = Cp(olF);                                         // the measured line replaces the axes' sum
            if (!Chk && now - BurnT0 > 1)
            {
                Chk = true;
                if (fs > 0 && Mag(fv) < AxisMin * fs) { Scalar = true; ScalarRatio = Mag(fv) / fs; ev = 1; }
            }
            if (Scalar)
            {
                fv = new double[] { fore[0] * fs, fore[1] * fs, fore[2] * fs };
                av = new double[] { fore[0] * shipAvail, fore[1] * shipAvail, fore[2] * shipAvail };
            }
            SenseA(new double[] { fv[0] / ms, fv[1] / ms, fv[2] / ms }, now);
            return ev;
        }

        // kOS's PEG 4 / PEG 8 hands VGO back (o2p4Cycle / o2p8Shot set pg["vgo"])
        public void SetVgo(double[] v) { Vgo = Cp(v); }

        // the decisions of the tick (o2qBurnTick from `LOCAL aAv` on), on the context the Sense call loaded
        public void Decide()
        {
            Events = 0;
            AAv = Mag(av) / ms;
            string why = End(now, AAv);
            if (engLen == 0) why = "OMS";
            if (why == "" && cutreq) why = "CREW";
            double thr = 0;
            Tpr = 0;
            if (why == "")
            {
                Tpr = Taper();
                thr = ThrFor(Al(), AAv, Tpr);
                if (Tpr > TaperS + 0.001 && !TaplLogged) { TaplLogged = true; Events |= E_TAPER; }
                if (thr == 0) why = "CUT";
            }
            // the steering line tl: the engines' force (the count's), else the available, else the fore; with the addon's trim when not scalar
            double[] tl = fv;
            if (Mag(tl) < 0.01) tl = av;
            if (Mag(tl) < 0.01) tl = fore;
            if (!Scalar) tl = trim;                                         // o2lSteer(uids, pa): the trim line, or its fallback pa (kOS gave it)
            Tl = Cp(tl);
            if (olOk && !Pchk && now - BurnT0 > 2) { Pchk = true; Events |= E_PCHK; }
            if (Ffo && !gdl && !Scalar && !Frz) Events |= E_FFO;
            double frzV = AimFreezeV;
            bool frzM = false;
            if (FrzMeas && olOk && !gdl && !Scalar && !Frz)
            {
                if (Ang(olF, Dir()) <= FrzMeasMax) { frzM = true; frzV = FrzMeasV; }
            }
            if (!Frz && Al() < frzV)
            {
                Frz = true;
                Events |= E_FREEZE;
                FrzAlong = LastAlong;
                DirF = Cp(Dir());
                if (frzM) { Events |= E_FRZM; AngOl = Ang(olF, DirF); }
                AngTl = Ang(Tl, DirF);
            }
            if (!Frz && !gdl) { Events |= E_AIM; AimDir = Cp(Dir()); }
            N++;
            if (why != "") { Events |= E_END; thr = 0; }
            else if (LogTicks > 0 && N % LogTicks == 0) Events |= E_ROW;
            Why = why; Thr = thr; Along = LastAlong;
        }
    }
}
