// THE ENTRY REFERENCE FAMILY BUILD in C#, a line-for-line port of lib/entry_predict.ks's build path
// (eprFamStart's coast: eprKepToEI / eprKepState / eprJ2ToEI / eprJ2Step / eprJ2Grav; per member eprFamBeginMember,
// eprIntStart, eprIntRun, eprFamBankAt, eprBankWithFlare, eprAccel, eprJ2Accel, eprTraceSample, eprFamStoreMember; the aero
// eprPolar / eprBracket / eprHermAt / eprHermite / eprCdFix / eprSbFrac / eprCdaEntry / eprPrMult / eprPrRef; the air
// eprRho / eprLogInterp / eprPres / eprMachFrom; eprAoA / eprAoARamp / eprAoANom) and of lib/lib_tal.ks's TAL copies
// (talAoA, talAccel, talFamBankAt, talTraceSample, talIntRun: FamConsts.TAL). kOS semantics: trig in degrees as kOS's
// (Math.Sin(deg * pi / 180), Math.Atan2(..) * 180 / pi), ^ = Math.Pow (CONSTANT:E ^ x is Math.Pow(E, x)), the vector
// arithmetic of KSP's Vector3d (VXCL = Vector3d.Exclude), the same order of operations. Every constant comes from the kOS
// globals at the start (FamConsts.Set, all required): nothing is retyped here.
// THREADS: FamJob.Start runs the coast synchronously (EPR_FAM_TCOAST is wanted at once), then queues ONE WORK ITEM PER
// MEMBER (each its own state, its own density hint): the worker touches no Unity / kOS object (the pressure is
// PresTab's table, taken on the main thread; GetPressure from the workers raced its AnimationCurve's cache).
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;

namespace KalsCoproc
{
    public class FamConsts
    {
        public double R, MU, ATM, WMAG, J2, R_J2, TAEM_VEL, TAEM_ALT, GAMMA, MASS_K, TRIM_FD, TRIM_FL, FLAP_X, FLAP_KF;
        public Vec3 WAXIS;
        public bool J2_ON;
        public double PAR_W_WING, PAR_W_FUS, PAR_W_CTL, K_LIFT, K_PAR, PAR_SHIFT, PR_SHARE;
        public double[][] RHO, LIFT_CURVE, LIFT_MACH, WING_PAR_A, WING_PAR_M, FUS_PAR_A, FUS_PAR_M, CTL_PAR_A, CTL_PAR_M,
            PSEUDORE, SB_FRAC, CD_FIX, AERO_FIX, FLAP_TAB;
        public double AOA_HIGH, AOA_LOW, AOA_HIGH_SPEED, AOA_LOW_SPEED, AOA_RAMP_V_HI, AOA_RAMP_V_LO, AOA_RAMP_HI, AOA_RAMP_LO;
        public bool AOA_RAMP_ON, SB_ON, FAM_ADD, FAM_KEPLER;
        public double SB_V, SB_V_FULL, IDT, FAM_EXT_V, FAM_FINE_V, TRACE_EVERY, TRACE_MAX, GUID_DRAG_INIT, PREENTRY_BANK;
        public double NZ_ARREST_TOP, NZ_ARREST_ALT, NZ_ARREST_KNEE, NZ_ARREST_SLOPE;
        public double BANK_FLARE_SPEED, BANK_FLARE_MAX, BANK_FLARE_SLOPE, BANK_TAEM_SPEED, BANK_TAEM_LIMIT, BANK_MAX, BANK_STOP_SPEED;
        public double[] FAM_BANKS, FAM_ORDER;
        public double HINT_RHO, FAM_BANK_NOW;          // the kOS globals' values at the start (the members' first state)
        public double CE, ATMTOKPA, DEGTORAD, RADTODEG; // CONSTANT:E, :ATMTOKPA, :DEGTORAD, :RADTODEG
        // TAL (lib_tal.ks): TAL_A0, TAL_VALPD1, TAL_VALPD2 when TAL
        [NonSerialized] public bool TAL;
        [NonSerialized] public double TAL_A0, TAL_VALPD1, TAL_VALPD2;
        // ALTITUDEPRESSURE(h): the pressure in atm (kOS: CelestialBody.GetPressure(h) * KpaToAtm)
        [NonSerialized] public Func<double, double> AltPres;
        [NonSerialized] public double PR_REF = -1;

        HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        static FieldInfo Field(string k)
        {
            var f = typeof(FamConsts).GetField(k.ToUpperInvariant(), BindingFlags.Public | BindingFlags.Instance);
            if (f == null || f.IsNotSerialized) return null;
            return f;
        }

        // a value by its kOS name without "EPR_": double, bool, Vec3, double[] or double[][] as the field wants
        public void Set(string key, object v)
        {
            var f = Field(key);
            if (f == null) throw new ArgumentException("FAM: unknown constant " + key);
            if (f.FieldType == typeof(double)) { double d = Convert.ToDouble(v); Finite(key, d); f.SetValue(this, d); }
            else if (f.FieldType == typeof(bool)) f.SetValue(this, (bool)v);
            else if (f.FieldType == typeof(Vec3)) f.SetValue(this, (Vec3)v);
            else if (f.FieldType == typeof(double[])) f.SetValue(this, (double[])v);
            else if (f.FieldType == typeof(double[][])) f.SetValue(this, (double[][])v);
            else throw new ArgumentException("FAM: " + key);
            seen.Add(key);
        }

        static void Finite(string k, double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("FAM: " + k + " is not finite");
        }

        public static IEnumerable<string> Names()
        {
            foreach (var f in typeof(FamConsts).GetFields(BindingFlags.Public | BindingFlags.Instance))
                if (!f.IsNotSerialized) yield return f.Name;
        }

        public void Check()
        {
            foreach (var n in Names()) if (!seen.Contains(n)) throw new ArgumentException("FAM: constant " + n + " missing");
            if (AltPres == null) throw new ArgumentException("FAM: no pressure");
            if (FAM_BANKS.Length != FAM_ORDER.Length || FAM_BANKS.Length == 0) throw new ArgumentException("FAM: banks / order");
            foreach (var o in FAM_ORDER) if (o < 0 || o >= FAM_BANKS.Length || o != Math.Floor(o)) throw new ArgumentException("FAM: order");
            if (IDT <= 0) throw new ArgumentException("FAM: IDT");
        }

        // sqa_curve (lib_solq_atm.ks): the pressure curve's own evaluation, for the offline checks
        public static double SqaCurve(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            double lo = 0, hi = n - 1;
            while (!(hi - lo <= 1))
            {
                double mid = Math.Floor((lo + hi) / 2);
                if (keys[(int)mid][0] <= x) lo = mid; else hi = mid;
            }
            double t1 = keys[(int)lo][0], v1 = keys[(int)lo][1], m1 = keys[(int)lo][3];
            double t2 = keys[(int)hi][0], v2 = keys[(int)hi][1], m2 = keys[(int)hi][2];
            double dt = t2 - t1;
            double t = (x - t1) / dt;
            double tt = t * t;
            double ttt = tt * t;
            return ((2 * ttt - 3 * tt + 1) * v1 + (ttt - 2 * tt + t) * dt * m1
                    + (-2 * ttt + 3 * tt) * v2 + (ttt - tt) * dt * m2);
        }
    }

    // one member: the kOS globals the build keeps (EPR_IR, EPR_IV, ...) as this member's own fields
    public class FamMember
    {
        readonly FamConsts c;
        public int Index;                 // position in the build order (EPR_FAM_I)
        public double MEMBER_BANK;
        // eprIntRun's state
        public Vec3 IR, IV, PR, PV;
        public double IT, IBK, PT, PA, PVR, PARC, IARC, FAM_ARC, BANK_NOW, BANK_PRE, TRACE_K, HINT_RHO, TAL_FAM_VI = -1;
        public bool IOK, IDONE, HAVEPREV, STARTED;
        public double TERM_ALT, TERM_VEL; public string TERM_WHY = "none";
        public long Steps;
        // the trace (EPR_TR_*)
        public List<double> TR_V = new List<double>(), TR_D = new List<double>(), TR_S = new List<double>(),
            TR_A = new List<double>(), TR_ARC = new List<double>(), TR_BK = new List<double>();
        // the stored member (eprFamStoreMember): vs, ds, ss, rg, bk, alts
        public double[] VS, DS, SS, RG, BK, ALTS;
        public volatile bool Done;
        public string Error = "";
        public double Ms;

        public FamMember(FamConsts cc, int index) { c = cc; Index = index; HINT_RHO = cc.HINT_RHO; BANK_NOW = cc.FAM_BANK_NOW; }

        // ---- kOS's built-ins
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }
        static double Tan(double d) { return Math.Tan(d * Math.PI / 180.0); }
        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static Vec3 Div(Vec3 a, double s) { return new Vec3(a.X / s, a.Y / s, a.Z / s); }
        static Vec3 Vxcl(Vec3 a, Vec3 b)          // Vector3d.Exclude(a, b) = b - Project(b, a)
        {
            double num = Vec3.Dot(a, a);
            Vec3 proj = num < 1.4012984643248171E-45 ? Vec3.Zero : Div(a * Vec3.Dot(b, a), num);
            return b - proj;
        }

        // ---- interpolation
        double LogInterp(double[][] tab, double x, double hint, out double iout)
        {
            int n = tab.Length;
            if (x <= tab[0][0]) { iout = 0; return tab[0][1]; }
            if (x >= tab[n - 1][0]) { iout = n - 2; return 0; }
            double i = Math.Max(0, Math.Min(hint, n - 2));
            while (!(i <= 0 || tab[(int)i][0] <= x)) i = i - 1;
            while (!(i >= n - 2 || tab[(int)i + 1][0] >= x)) i = i + 1;
            double a0 = tab[(int)i][0], a1 = tab[(int)i + 1][0];
            double y0 = tab[(int)i][1], y1 = tab[(int)i + 1][1];
            iout = i;
            if (y0 <= 0 || y1 <= 0) return 0;
            double f = (x - a0) / (a1 - a0);
            return Math.Pow(c.CE, Math.Log(y0) + f * (Math.Log(y1) - Math.Log(y0)));
        }

        double Rho(double altm)
        {
            double i;
            double r = LogInterp(c.RHO, altm, HINT_RHO, out i);
            HINT_RHO = i;
            return r;
        }

        double Pres(double altm)
        {
            if (altm >= c.ATM) return 0;
            return c.AltPres(Math.Max(altm, 0)) * c.ATMTOKPA * 1000;
        }

        public static double Hermite(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            for (int i = 1; i < n; i++)
            {
                if (keys[i][0] >= x)
                {
                    double x0 = keys[i - 1][0], y0 = keys[i - 1][1];
                    double x1 = keys[i][0], y1 = keys[i][1];
                    double sp = x1 - x0;
                    double t = (x - x0) / sp;
                    double m0 = keys[i - 1][3] * sp;
                    double m1 = keys[i][2] * sp;
                    double t2 = t * t, t3 = t2 * t;
                    return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                           + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
                }
            }
            return keys[n - 1][1];
        }

        double PrRef()
        {
            if (c.PR_REF < 0) c.PR_REF = Hermite(c.PSEUDORE, 1);     // a constant: every thread writes the same value
            return c.PR_REF;
        }

        double PrMult(double rhov)
        {
            double pr = Hermite(c.PSEUDORE, rhov) / PrRef();
            if (pr <= 1) return pr;
            return 1 + c.PR_SHARE * (pr - 1);
        }

        double MachFrom(double altm, double vrel, double rh)
        {
            double ps = Pres(altm);
            if (ps <= 0 || rh <= 0) return 0;
            return vrel / Math.Sqrt(c.GAMMA * ps / rh);
        }

        // ---- alpha
        double AoA(double vrel)
        {
            if (c.AOA_RAMP_ON) return Math.Min(AoANom(vrel), AoARamp(vrel));
            return AoANom(vrel);
        }
        double AoARamp(double vrel)
        {
            if (vrel < c.AOA_HIGH_SPEED)            // eprAoARamp's line under EPR_AOA_HIGH_SPEED
            {
                double fl = (vrel - c.AOA_LOW_SPEED) / (c.AOA_HIGH_SPEED - c.AOA_LOW_SPEED);
                return c.AOA_LOW + (c.AOA_RAMP_LO - c.AOA_LOW) * Math.Max(0, Math.Min(1, fl));
            }
            if (vrel >= c.AOA_RAMP_V_HI) return c.AOA_RAMP_HI;
            if (vrel <= c.AOA_RAMP_V_LO) return c.AOA_RAMP_LO;
            return c.AOA_RAMP_LO + (c.AOA_RAMP_HI - c.AOA_RAMP_LO) * (vrel - c.AOA_RAMP_V_LO) / (c.AOA_RAMP_V_HI - c.AOA_RAMP_V_LO);
        }
        double AoANom(double vrel)
        {
            if (vrel >= c.AOA_HIGH_SPEED) return c.AOA_HIGH;
            double span = c.AOA_HIGH_SPEED - c.AOA_LOW_SPEED;
            if (span <= 0) return c.AOA_LOW;
            double fr = (vrel - c.AOA_LOW_SPEED) / span;
            if (fr < 0) fr = 0;
            if (fr > 1) fr = 1;
            return c.AOA_LOW + (c.AOA_HIGH - c.AOA_LOW) * fr;
        }
        // lib_tal.ks talAoA: the TAL alpha at vr for an entry that initiated at vi (vi < 0: not yet)
        double TalAoA(double vr, double vi)
        {
            if (vi < 0 || vr >= vi) return c.TAL_A0;
            double v10 = vi - c.TAL_VALPD1;
            if (vr < v10) return AoA(vr);
            double v11 = vi - c.TAL_VALPD2;
            double alp3 = AoA(v10);
            double adt3 = 0;
            if (v10 > c.AOA_LOW_SPEED && v10 < c.AOA_HIGH_SPEED)
                adt3 = (c.AOA_HIGH - c.AOA_LOW) / (c.AOA_HIGH_SPEED - c.AOA_LOW_SPEED);
            double dl1 = vi - v10;
            double dl2 = vi - v11;
            double dl3 = v11 - v10;
            double c211 = 0 - (alp3 - c.TAL_A0 + adt3 * (dl3 + 0.5 * dl2)) / (dl3 * dl1);
            if (vr < v11)
            {
                double x1 = vr - v10;
                return alp3 + adt3 * x1 + c211 * x1 * x1;
            }
            double c212 = 0 - (adt3 + 2 * c211 * dl3) / (2 * dl2);
            double x2 = vr - vi;
            return c.TAL_A0 + c212 * x2 * x2;
        }
        // the member's alpha in the integration and the trace: eprAoA, or (TAL) talAoA on the member's latch
        double MemberAoA(double vr) { return c.TAL ? TalAoA(vr, STARTED ? TAL_FAM_VI : -1) : AoA(vr); }

        // ---- aero
        static int Bracket(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return 0;
            if (x >= keys[n - 1][0]) return n;
            for (int i = 1; i < n; i++) if (keys[i][0] >= x) return i;
            return n;
        }
        static double HermAt(double[][] keys, double x, double i)
        {
            if (i <= 0) return keys[0][1];
            int n = keys.Length;
            if (i >= n) return keys[n - 1][1];
            int k = (int)i;
            double x0 = keys[k - 1][0], y0 = keys[k - 1][1];
            double x1 = keys[k][0], y1 = keys[k][1];
            double sp = x1 - x0;
            double t = (x - x0) / sp;
            double m0 = keys[k - 1][3] * sp;
            double m1 = keys[k][2] * sp;
            double t2 = t * t, t3 = t2 * t;
            return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                   + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
        }
        void Polar(double aoa, double mach, out double cla, out double cda)
        {
            double a = Math.Max(0, Math.Min(89, aoa));
            double s = Sin(Math.Max(0, Math.Min(90, aoa)));
            double ia = Bracket(c.LIFT_CURVE, s);
            double im = Bracket(c.LIFT_MACH, mach);
            double ip = Math.Max(0, ia - c.PAR_SHIFT);
            double cl = c.K_LIFT * HermAt(c.LIFT_CURVE, s, ia) * HermAt(c.LIFT_MACH, mach, im);
            double pa = c.K_PAR * (
                c.PAR_W_WING * HermAt(c.WING_PAR_A, s, ip) * HermAt(c.WING_PAR_M, mach, im) +
                c.PAR_W_FUS * HermAt(c.FUS_PAR_A, s, ip) * HermAt(c.FUS_PAR_M, mach, im) +
                c.PAR_W_CTL * HermAt(c.CTL_PAR_A, s, ip) * HermAt(c.CTL_PAR_M, mach, im));
            cla = cl * c.MASS_K * c.TRIM_FL;
            cda = (cl * Tan(a) + pa) * c.MASS_K * c.TRIM_FD;
        }
        double Cda(double aoa, double mach) { double l, d; Polar(aoa, mach, out l, out d); return d; }
        double SbFrac(double mach, double spd)
        {
            if (!c.SB_ON || spd >= c.SB_V) return 0;
            double ramp = Math.Min(1, (c.SB_V - spd) / (c.SB_V - c.SB_V_FULL));
            var t = c.SB_FRAC;
            double fr = t[t.Length - 1][1];
            if (mach <= t[0][0]) fr = t[0][1];
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
            var t = c.CD_FIX;
            int n = t.Length;
            if (mach <= t[0][0]) return t[0][1];
            if (mach >= t[n - 1][0]) return t[n - 1][1];
            int i = (int)Math.Min(Math.Floor((mach - t[0][0]) / (t[1][0] - t[0][0])), n - 2);
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
            double[] lo = c.AERO_FIX[0], hi = c.AERO_FIX[1];
            double w = Math.Min(1, Math.Max(0, (mach - lo[0]) / (hi[0] - lo[0])));
            double da = Math.Max(aoa - 40, 0);
            double ft = 0;
            if (c.FLAP_X > -90) ft = FlapTerm(c.FLAP_X, c.FLAP_KF, c.FLAP_TAB, mach);
            return new double[] { Math.Pow(Math.E, lo[1] + (hi[1] - lo[1]) * w + (lo[2] + (hi[2] - lo[2]) * w) * da + ft),
                                  Math.Pow(Math.E, lo[3] + (hi[3] - lo[3]) * w + (lo[4] + (hi[4] - lo[4]) * w) * da) };
        }
        double CdaEntry(double aoa, double mach, double spd) { return Cda(aoa, mach) * (1 + CdFix(mach)) * AeroFix(aoa, mach)[0] * (1 + SbFrac(mach, spd)); }

        Vec3 OmegaCross(Vec3 rv) { return Vec3.Cross(c.WAXIS * c.WMAG, rv); }

        Vec3 J2Accel(Vec3 rv, double rmag)
        {
            double z = Vec3.Dot(rv, c.WAXIS);
            double k = -1.5 * c.J2 * c.MU * c.R_J2 * c.R_J2 / Math.Pow(rmag, 5);
            double zz = 5.0 * z * z / (rmag * rmag);
            return (rv * (1.0 - zz) + c.WAXIS * (2.0 * z)) * k;
        }

        // eprAccel (TAL: talAccel, the member's alpha)
        Vec3 Accel(Vec3 rv, Vec3 vv, double bankDeg)
        {
            double rmag = rv.Mag;
            Vec3 g = rv * (-c.MU / (rmag * rmag * rmag));
            if (c.J2_ON) g = g + J2Accel(rv, rmag);
            Vec3 vrelv = vv - OmegaCross(rv);
            double vr = vrelv.Mag;
            double altm = rmag - c.R;
            if (vr < 1 || altm >= c.ATM) return g;
            double rho = Rho(altm);
            if (rho <= 0) return g;
            double qdyn = 0.5 * rho * vr * vr;
            Vec3 vh = Div(vrelv, vr);
            double mach = MachFrom(altm, vr, rho);
            double aoa = MemberAoA(vr);
            double pr = PrMult(rho * vr);
            double cla, cda;
            Polar(aoa, mach, out cla, out cda);
            double[] fix = AeroFix(aoa, mach);
            Vec3 aDrag = vh * (-cda * (1 + CdFix(mach)) * fix[0] * (1 + SbFrac(mach, vr)) * qdyn * pr);
            Vec3 upv = Div(rv, rmag);
            Vec3 upp = upv - vh * Vec3.Dot(upv, vh);
            if (upp.Mag < 0.000001) return g + aDrag;
            upp = upp.Normalized;
            Vec3 sd = Vec3.Cross(vh, upp);
            double b = bankDeg;
            Vec3 ldir = upp * Cos(b) + sd * Sin(b);
            return g + aDrag + ldir * (cla * fix[1] * qdyn);
        }

        // eprFamBankAt (TAL: talFamBankAt)
        double FamBankAt(double altm, double vr)
        {
            if (!STARTED && altm < c.ATM && vr > 1)
            {
                double rho = Rho(altm);
                if (rho > 0)
                {
                    double pr = PrMult(rho * vr);
                    double aoa = c.TAL ? TalAoA(vr, -1) : AoA(vr);
                    if (CdaEntry(aoa, MachFrom(altm, vr, rho), vr) * 0.5 * rho * vr * vr * pr >= c.GUID_DRAG_INIT)
                    {
                        STARTED = true;
                        if (c.TAL) TAL_FAM_VI = vr;
                    }
                }
            }
            if (!STARTED) { BANK_PRE = c.PREENTRY_BANK; return c.PREENTRY_BANK; }
            double b = MEMBER_BANK;
            if (altm < c.NZ_ARREST_TOP && b > c.NZ_ARREST_KNEE)
            {
                double w = 1;
                if (altm > c.NZ_ARREST_ALT) w = (c.NZ_ARREST_TOP - altm) / (c.NZ_ARREST_TOP - c.NZ_ARREST_ALT);
                b = c.NZ_ARREST_KNEE + (b - c.NZ_ARREST_KNEE) * (1 - w * (1 - c.NZ_ARREST_SLOPE));
            }
            BANK_PRE = b;
            return BankWithFlare(b, vr);
        }

        double BankWithFlare(double bankDeg, double vr)
        {
            double b = Math.Abs(bankDeg);
            if (c.BANK_FLARE_SPEED > 0 && vr <= c.BANK_FLARE_SPEED && b > c.BANK_FLARE_MAX)
                b = c.BANK_FLARE_MAX + (b - c.BANK_FLARE_MAX) * c.BANK_FLARE_SLOPE;
            if (c.BANK_TAEM_SPEED > 0 && vr < c.BANK_TAEM_SPEED)
            {
                double span = c.BANK_TAEM_SPEED - c.TAEM_VEL;
                double w = 1;
                if (span > 0) w = (c.BANK_TAEM_SPEED - vr) / span;
                w = Math.Max(0, Math.Min(1, w));
                b = b * (1 - w * (1 - c.BANK_TAEM_LIMIT / c.BANK_MAX));
            }
            if (vr <= c.BANK_STOP_SPEED) b = 0;
            return b;
        }

        // eprTraceSample (nominal = TRUE) / talTraceSample (TAL and not nominal: the member's alpha)
        void TraceSample(Vec3 rv, Vec3 vv, bool nominal)
        {
            if (TR_V.Count >= c.TRACE_MAX) return;
            double rmag = rv.Mag;
            double altm = rmag - c.R;
            Vec3 vrelv = vv - OmegaCross(rv);
            double vr = vrelv.Mag;
            if (vr < 1 || altm >= c.ATM) return;
            double rho = Rho(altm);
            if (rho <= 0) return;
            double qdyn = 0.5 * rho * vr * vr;
            double pr = PrMult(rho * vr);
            double aoa = (c.TAL && !nominal) ? TalAoA(vr, STARTED ? TAL_FAM_VI : -1) : AoA(vr);
            double drag = CdaEntry(aoa, MachFrom(altm, vr, rho), vr) * qdyn * pr;
            TR_V.Add(vr);
            TR_D.Add(drag);
            TR_S.Add(Vec3.Dot(vrelv, Div(rv, rmag)));
            TR_A.Add(altm);
            TR_ARC.Add(FAM_ARC);
            TR_BK.Add(BANK_NOW);
        }

        // eprFamBeginMember + eprIntStart (EPR_FAM_ACTIVE and EPR_TRACE_ON TRUE, EPR_LAT_ON FALSE in a build)
        public void Begin(Vec3 r0, Vec3 v0)
        {
            MEMBER_BANK = c.FAM_BANKS[(int)c.FAM_ORDER[Index]];
            STARTED = false;
            FAM_ARC = 0;
            TR_V.Clear(); TR_D.Clear(); TR_S.Clear(); TR_A.Clear(); TR_ARC.Clear(); TR_BK.Clear(); TRACE_K = 0;
            IR = r0; IV = v0; IT = 0; IARC = 0;
            IBK = MEMBER_BANK; IOK = false; IDONE = false;
            HAVEPREV = false;
        }

        // eprIntRun (TAL: talIntRun) to the end: the kOS budget only decides where a call returns, the state is the same
        public void IntRun()
        {
            bool famAdd = c.FAM_ADD;                   // EPR_FAM_ACTIVE AND EPR_FAM_ADD
            double vstop = c.TAEM_VEL;
            if (famAdd) vstop = c.FAM_EXT_V;
            while (true)
            {
                double rmag = IR.Mag;
                double altm = rmag - c.R;
                double vr = (IV - OmegaCross(IR)).Mag;
                if (altm <= c.TAEM_ALT || (altm < c.ATM && vr <= vstop))
                {
                    if (HAVEPREV)
                    {
                        double fr = 1;
                        if (altm <= c.TAEM_ALT && PA > c.TAEM_ALT)
                            fr = (PA - c.TAEM_ALT) / Math.Max(PA - altm, 0.000000001);
                        else if (PVR > vstop)
                            fr = (PVR - vstop) / Math.Max(PVR - vr, 0.000000001);
                        fr = Math.Max(0, Math.Min(1, fr));
                        IR = PR + (IR - PR) * fr;
                        IV = PV + (IV - PV) * fr;
                        IT = PT + (IT - PT) * fr;
                        altm = IR.Mag - c.R;
                        vr = (IV - OmegaCross(IR)).Mag;
                        if (famAdd) FAM_ARC = PARC + (IARC - PARC) * fr;
                    }
                    if (famAdd)                         // EPR_TRACE_ON: TRUE in a build. eprTraceSample in talIntRun too
                    {
                        if (TR_V.Count == 0) TraceSample(IR, IV, true);
                        else if (TR_V[TR_V.Count - 1] > vr) TraceSample(IR, IV, true);
                    }
                    TERM_ALT = altm;
                    TERM_VEL = vr;
                    if (altm <= c.TAEM_ALT + 1) TERM_WHY = "taemalt"; else TERM_WHY = "taemvel";
                    IOK = true; IDONE = true; return;
                }
                if (altm < 0 || IT > 2500)
                {
                    TERM_ALT = altm;
                    TERM_VEL = vr;
                    if (altm < 0) TERM_WHY = "ground"; else TERM_WHY = "timeout";
                    IOK = false; IDONE = true; return;
                }
                PR = IR; PV = IV; PT = IT;
                PA = altm; PVR = vr; HAVEPREV = true;
                PARC = IARC;
                double bnk = FamBankAt(altm, vr);    // EPR_FAM_ACTIVE
                Vec3 a1 = Accel(IR, IV, bnk);
                Vec3 rm = IR + IV * (0.5 * c.IDT);
                Vec3 vm = IV + a1 * (0.5 * c.IDT);
                Vec3 a2 = Accel(rm, vm, bnk);
                BANK_NOW = bnk;
                if (famAdd) BANK_NOW = BANK_PRE;
                Vec3 arcVrel = IV - OmegaCross(IR);
                double arcVh = Vxcl(IR.Normalized, arcVrel).Mag;
                IARC = IARC + arcVh * c.IDT * (c.R / IR.Mag);
                FAM_ARC = IARC;
                IR = IR + vm * c.IDT;
                IV = IV + a2 * c.IDT;
                IT = IT + c.IDT;
                TRACE_K = TRACE_K + 1;
                if (famAdd && vr < c.FAM_FINE_V) TRACE_K = c.TRACE_EVERY;
                if (TRACE_K >= c.TRACE_EVERY)
                {
                    TRACE_K = 0;
                    TraceSample(IR, IV, false);
                }
                Steps = Steps + 1;
            }
        }

        // eprFamStoreMember
        public void Store()
        {
            var vs = new List<double>(); var ds = new List<double>(); var ss = new List<double>();
            var rg = new List<double>(); var bk = new List<double>(); var alts = new List<double>();
            int n = TR_V.Count;
            double arcEnd = FAM_ARC;
            for (int i = 0; i < n; i++)
            {
                if (TR_D[i] >= c.GUID_DRAG_INIT)
                {
                    vs.Add(TR_V[i]); ds.Add(TR_D[i]); ss.Add(TR_S[i]);
                    rg.Add(arcEnd - TR_ARC[i]); bk.Add(TR_BK[i]); alts.Add(TR_A[i]);
                }
            }
            VS = vs.ToArray(); DS = ds.ToArray(); SS = ss.ToArray(); RG = rg.ToArray(); BK = bk.ToArray(); ALTS = alts.ToArray();
        }

        public void Run(Vec3 r0, Vec3 v0)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                Begin(r0, v0);
                IntRun();
                Store();
                foreach (var a in new[] { VS, DS, SS, RG, BK, ALTS })
                    foreach (var x in a) if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("member " + Index + ": not finite");
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; }
            Ms = sw.Elapsed.TotalMilliseconds;
            Done = true;
        }
    }

    // the build: the coast (synchronous), then a worker per member
    public class FamJob
    {
        public readonly FamConsts C;
        public Vec3 R0, V0;
        public double TCOAST;
        public FamMember[] M;
        public double CoastMs;
        readonly System.Diagnostics.Stopwatch sw = new System.Diagnostics.Stopwatch();
        double wallMs = -1;
        int left;

        public FamJob(FamConsts c) { C = c; }

        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }

        // ---- eprKepState: f-and-g through the eccentric anomaly
        void KepState(Vec3 rv, Vec3 vv, double dt, out Vec3 ro, out Vec3 vo)
        {
            double r0m = rv.Mag;
            double v0m = vv.Mag;
            double sma = 1 / (2 / r0m - v0m * v0m / C.MU);
            if (sma <= 0) { ro = rv; vo = vv; return; }
            double sig0 = Vec3.Dot(rv, vv) / Math.Sqrt(C.MU);
            double ecosE = 1 - r0m / sma;
            double esinE = sig0 / Math.Sqrt(sma);
            double e0R = Atan2(esinE, ecosE) * C.DEGTORAD;
            double ecc = Math.Sqrt(ecosE * ecosE + esinE * esinE);
            double n = Math.Sqrt(C.MU / (sma * sma * sma));
            double mR = e0R - esinE + n * dt;
            double eaR = mR;
            int i = 0;
            while (!(i >= 20))
            {
                i = i + 1;
                double eaD = eaR * C.RADTODEG;
                double fv = eaR - ecc * Sin(eaD) - mR;
                double fp = 1 - ecc * Cos(eaD);
                if (Math.Abs(fp) < 0.00000000000001) break;
                double d = fv / fp;
                eaR = eaR - d;
                if (Math.Abs(d) < 0.0000000000001) break;
            }
            double deaR = eaR - e0R;
            double deaD = deaR * C.RADTODEG;
            double ff = 1 - sma / r0m * (1 - Cos(deaD));
            double gg = dt - Math.Sqrt(sma * sma * sma / C.MU) * (deaR - Sin(deaD));
            Vec3 rNew = rv * ff + vv * gg;
            double rNm = rNew.Mag;
            double fd = 0 - Math.Sqrt(C.MU * sma) / (rNm * r0m) * Sin(deaD);
            double gd = 1 - sma / rNm * (1 - Cos(deaD));
            ro = rNew; vo = rv * fd + vv * gd;
        }

        Vec3 J2Accel(Vec3 rv, double rmag)
        {
            double z = Vec3.Dot(rv, C.WAXIS);
            double k = -1.5 * C.J2 * C.MU * C.R_J2 * C.R_J2 / Math.Pow(rmag, 5);
            double zz = 5.0 * z * z / (rmag * rmag);
            return (rv * (1.0 - zz) + C.WAXIS * (2.0 * z)) * k;
        }
        Vec3 J2Grav(Vec3 rv)
        {
            double rmag = rv.Mag;
            return rv * (-C.MU / (rmag * rmag * rmag)) + J2Accel(rv, rmag);
        }
        void J2Step(Vec3 rv, Vec3 vv, double h, out Vec3 ro, out Vec3 vo)
        {
            Vec3 a1 = J2Grav(rv);
            Vec3 r2 = rv + vv * (h / 2); Vec3 v2 = vv + a1 * (h / 2);
            Vec3 a2 = J2Grav(r2);
            Vec3 r3 = rv + v2 * (h / 2); Vec3 v3 = vv + a2 * (h / 2);
            Vec3 a3 = J2Grav(r3);
            Vec3 r4 = rv + v3 * h; Vec3 v4 = vv + a3 * h;
            Vec3 a4 = J2Grav(r4);
            ro = rv + (vv + v2 * 2 + v3 * 2 + v4) * (h / 6);
            vo = vv + (a1 + a2 * 2 + a3 * 2 + a4) * (h / 6);
        }
        double J2ToEI(Vec3 rv, Vec3 vv, out Vec3 ro, out Vec3 vo)
        {
            double tgt = C.R + C.ATM;
            double t = 0;
            double h = 30;
            while (!(t > 20000))
            {
                Vec3 sr, sv;
                J2Step(rv, vv, h, out sr, out sv);
                if (sr.Mag <= tgt)
                {
                    double lo = 0, hi = h;
                    for (int k = 0; k < 20; k++)
                    {
                        double mid = 0.5 * (lo + hi);
                        Vec3 mr, mv;
                        J2Step(rv, vv, mid, out mr, out mv);
                        if (mr.Mag > tgt) lo = mid; else hi = mid;
                    }
                    J2Step(rv, vv, hi, out ro, out vo);
                    return t + hi;
                }
                rv = sr; vv = sv; t = t + h;
            }
            ro = rv; vo = vv;
            return -1;
        }
        // eprKepToEI -> the elapsed time (-1: never descends; ro / vo the start then)
        double KepToEI(Vec3 rv, Vec3 vv, out Vec3 ro, out Vec3 vo)
        {
            if (C.J2_ON) return J2ToEI(rv, vv, out ro, out vo);
            double tgt = C.R + C.ATM;
            ro = rv; vo = vv;
            if (rv.Mag <= tgt) return 0;
            double lo = 0, hi = 10;
            int guard = 0;
            Vec3 kr, kv;
            while (true)
            {
                KepState(rv, vv, hi, out kr, out kv);
                if (kr.Mag <= tgt || guard > 20) break;
                hi = hi * 2;
                guard = guard + 1;
            }
            KepState(rv, vv, hi, out kr, out kv);
            if (kr.Mag > tgt) return -1;
            int kk = 0;
            while (!(kk >= 34))
            {
                kk = kk + 1;
                double mid = 0.5 * (lo + hi);
                KepState(rv, vv, mid, out kr, out kv);
                if (kr.Mag > tgt) lo = mid; else hi = mid;
            }
            KepState(rv, vv, hi, out ro, out vo);
            return hi;
        }

        // eprFamStart's coast (EPR_FAM_R0 / V0 / TCOAST), then the members; threaded = FALSE runs them here, one by one
        public void Start(Vec3 rv, Vec3 vv, bool threaded)
        {
            C.Check();
            var cw = System.Diagnostics.Stopwatch.StartNew();
            TCOAST = 0;
            if (C.FAM_KEPLER && rv.Mag > C.R + C.ATM)
            {
                Vec3 er, ev;
                double et = KepToEI(rv, vv, out er, out ev);
                if (et >= 0) { R0 = er; V0 = ev; TCOAST = et; }
                else { R0 = rv; V0 = vv; }
            }
            else { R0 = rv; V0 = vv; }
            CoastMs = cw.Elapsed.TotalMilliseconds;
            foreach (var d in new[] { R0.X, R0.Y, R0.Z, V0.X, V0.Y, V0.Z, TCOAST })
                if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("FAM: the coast is not finite");
            int n = C.FAM_BANKS.Length;
            M = new FamMember[n];
            for (int i = 0; i < n; i++) M[i] = new FamMember(C, i);
            left = n;
            sw.Start();
            Vec3 r0 = R0, v0 = V0;
            for (int i = 0; i < n; i++)
            {
                var m = M[i];
                if (threaded) ThreadPool.QueueUserWorkItem(_ => { m.Run(r0, v0); Finished(); });
                else { m.Run(r0, v0); Finished(); }
            }
        }

        void Finished()
        {
            if (Interlocked.Decrement(ref left) == 0) { wallMs = sw.Elapsed.TotalMilliseconds; }
        }

        public bool Done { get { if (M == null) return false; foreach (var m in M) if (!m.Done) return false; return true; } }
        public string Error { get { if (M == null) return ""; foreach (var m in M) if (m.Done && m.Error != "") return m.Error; return ""; } }
        // members done in build order, from the first (a partial family keeps the build order's bracketing)
        public int Prefix { get { int k = 0; if (M == null) return 0; while (k < M.Length && M[k].Done && M[k].Error == "") k++; return k; } }
        public double WallMs { get { return Thread.VolatileRead(ref wallMs); } }
    }
}
