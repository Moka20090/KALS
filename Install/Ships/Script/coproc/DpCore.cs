// THE
// DEORBIT PLANNER'S SOLVE in the KAL/S coprocessor. This file: the constants (DpC: every kOS global the solve reads, handed by
// kOS at each job, all required), the kOS globals the solve reads AND writes (DpG: copied in, written back), kOS's math (DpM),
// and the entry prediction (DpEntry: lib/entry_predict.ks's eprIntStart / eprIntRun / eprAccel / eprLatBank / eprMissPath and
// their helpers, line for line, as the deorbit planner flies them: EPR_FAM_ACTIVE and EPR_TRACE_ON FALSE). kOS semantics:
// SIN / COS / TAN(deg) = Math.Sin(deg * pi / 180), ARCSIN / ARCCOS / ARCTAN2 = Math.A..(x) * 180 / pi, ^ = Math.Pow
// (CONSTANT:E ^ x = Math.Pow(E, x)), :NORMALIZED = Vector3d.normalized (zero at or below 1e-5), VXCL = Vector3d.Exclude, the
// same order of operations. Compiles with the .NET Framework's csc (C# 5).
using System;
using System.Collections.Generic;
using System.Reflection;

namespace KalsCoproc
{
    public static class DpM
    {
        public static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        public static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }
        public static double Tan(double d) { return Math.Tan(d * Math.PI / 180.0); }
        public static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        public static double Acos(double x) { return Math.Acos(x) * 180.0 / Math.PI; }
        public static double Atan(double x) { return Math.Atan(x) * 180.0 / Math.PI; }
        public static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        public static Vec3 Div(Vec3 a, double s) { return new Vec3(a.X / s, a.Y / s, a.Z / s); }
        // :NORMALIZED = Vector3d.normalized: this / magnitude above 1e-5, else zero
        public static Vec3 Nrm(Vec3 a) { double m = a.Mag; return m > 1E-05 ? Div(a, m) : Vec3.Zero; }
        // VXCL(a, b) = Vector3d.Exclude(a, b) = b - Project(b, a)
        public static Vec3 Vxcl(Vec3 a, Vec3 b)
        {
            double num = Vec3.Dot(a, a);
            Vec3 proj = num < 1.4012984643248171E-45 ? Vec3.Zero : Div(a * Vec3.Dot(b, a), num);
            return b - proj;
        }
    }

    // fills public fields from a KLex by their (kOS) names; every field required
    public static class DpFill
    {
        public static void Fill(object target, KLex src, string what)
        {
            foreach (var f in target.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (f.IsNotSerialized) continue;
                if (!src.Has(f.Name)) throw new ArgumentException(what + ": " + f.Name + " missing");
                object v = src[f.Name];
                Type t = f.FieldType;
                if (t == typeof(double)) f.SetValue(target, KLex.Num(v, f.Name));
                else if (t == typeof(int))
                {
                    double d = KLex.Num(v, f.Name);
                    if (d != Math.Floor(d) || Math.Abs(d) > int.MaxValue) throw new ArgumentException(what + ": " + f.Name + " is not an integer");
                    f.SetValue(target, (int)d);
                }
                else if (t == typeof(bool)) { if (!(v is bool)) throw new InvalidCastException(f.Name + " is not a boolean"); f.SetValue(target, v); }
                else if (t == typeof(string)) { if (!(v is string)) throw new InvalidCastException(f.Name + " is not a string"); f.SetValue(target, v); }
                else if (t == typeof(Vec3)) { if (!(v is Vec3)) throw new InvalidCastException(f.Name + " is not a vector"); f.SetValue(target, v); }
                else if (t == typeof(double[][]))
                {
                    var l = v as List<object>;
                    if (l == null || l.Count == 0) throw new InvalidCastException(f.Name + " is not a table");
                    var a = new double[l.Count][];
                    for (int i = 0; i < l.Count; i++)
                    {
                        var r = l[i] as List<object>;
                        if (r == null) throw new InvalidCastException(f.Name + " row " + i + " is not a list");
                        a[i] = KLex.Dbl(r, f.Name);
                    }
                    f.SetValue(target, a);
                }
                else if (t == typeof(object)) f.SetValue(target, v);
                else throw new ArgumentException(what + ": " + f.Name + " has an unsupported type");
            }
        }

        // the fields back as a KLex (ints stay ints)
        public static KLex Dump(object src)
        {
            var k = new KLex();
            foreach (var f in src.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (f.IsNotSerialized) continue;
                k[f.Name] = f.GetValue(src);
            }
            return k;
        }
    }

    // THE CONSTANTS: kOS's globals by name (lib_dpcs.ks dpcs_consts builds the lexicon at each job)
    public class DpC
    {
        public double EPR_R, EPR_MU, EPR_ATM, EPR_WMAG, EPR_NSIGN, EPR_ROT_SIGN, EPR_J2, EPR_R_J2, EPR_TAEM_VEL, EPR_TAEM_ALT,
            EPR_GAMMA, EPR_MASS_K, EPR_TRIM_FD, EPR_TRIM_FL, EPR_FLAP_X, EPR_FLAP_KF;
        public Vec3 EPR_WAXIS, EPR_NAXIS, EPR_GEO_X, EPR_GEO_Y;
        public bool EPR_J2_ON, EPR_PRED_LATERAL, EPR_FAM_ACTIVE, EPR_TRACE_ON, EPR_AOA_RAMP_ON, EPR_SB_ON, EPR_USE_MIN_BANK;
        public double EPR_PAR_W_WING, EPR_PAR_W_FUS, EPR_PAR_W_CTL, EPR_K_LIFT, EPR_K_PAR, EPR_PAR_SHIFT, EPR_PR_SHARE;
        public double[][] EPR_RHO, EPR_LIFT_CURVE, EPR_LIFT_MACH, EPR_WING_PAR_A, EPR_WING_PAR_M, EPR_FUS_PAR_A, EPR_FUS_PAR_M,
            EPR_CTL_PAR_A, EPR_CTL_PAR_M, EPR_PSEUDORE, EPR_SB_FRAC, EPR_CD_FIX, EPR_AERO_FIX, EPR_FLAP_TAB;
        public double EPR_AOA_HIGH, EPR_AOA_LOW, EPR_AOA_HIGH_SPEED, EPR_AOA_LOW_SPEED, EPR_AOA_RAMP_V_HI, EPR_AOA_RAMP_V_LO,
            EPR_AOA_RAMP_HI, EPR_AOA_RAMP_LO, EPR_SB_V, EPR_SB_V_FULL, EPR_IDT, EPR_GUID_DRAG_INIT;
        public double EPR_BANK_FLARE_SPEED, EPR_BANK_FLARE_MAX, EPR_BANK_FLARE_SLOPE, EPR_BANK_TAEM_SPEED, EPR_BANK_TAEM_LIMIT,
            EPR_BANK_MAX, EPR_BANK_STOP_SPEED, EPR_BANK_MIN;
        public double EPR_MIN_BANK_HI_LOW, EPR_MIN_BANK_HI_HIGH, EPR_MIN_BANK_LOW, EPR_MIN_BANK_MACH, EPR_MIN_BANK_DELAZ_K;
        public double EPR_AZ_FIRST, EPR_AZ_SUBS, EPR_AZ_LATE, EPR_AZ_MACH_HI, EPR_AZ_MACH_LO, EPR_ROLL_RATE_LIMIT, EPR_ROLL_ACCEL_LIMIT;
        public double KEP_EPH_DT;
        public double DP_FPA_TOL, DP_SCAN_STEP, DP_GEO_STEP, DP_PATH_ITERS, DP_TOL_KM, DP_LEG_LO, DP_LEG_HI, DP_SIDE_TOL_M,
            DP_MIN_LEAD_S, DP_INT_BUDGET, DP_BANK;
        public double[][] DP_COARSE_DENT;
        public double C_PI, C_DEGTORAD, C_RADTODEG, C_E, C_ATMTOKPA, BODY_RADIUS;
        // SHIP:BODY:ATM:ALTITUDEPRESSURE(h) (kOS: CelestialBody.GetPressure(h) * KpaToAtm), set by the host
        [NonSerialized] public Func<double, double> AltPres;

        public DpC(KLex c)
        {
            DpFill.Fill(this, c, "DP const");
            if (EPR_FAM_ACTIVE) throw new ArgumentException("EPR_FAM_ACTIVE is TRUE (a family build is running)");
            if (EPR_TRACE_ON) throw new ArgumentException("EPR_TRACE_ON is TRUE (the prediction trace is not ported)");
            if (EPR_IDT <= 0 || KEP_EPH_DT <= 0 || DP_GEO_STEP <= 0) throw new ArgumentException("a step is not positive");
            foreach (var r in DP_COARSE_DENT) if (r.Length < 2) throw new ArgumentException("DP_COARSE_DENT row");
        }
    }

    // THE STATE: the kOS globals the solve reads and writes, copied in at the job's start and written back at its end
    public class DpG
    {
        public double DP_FPA, DP_BACK_M; public bool DP_COARSE_ON;
        public int DP_NGATE_LEG, DP_NGATE_SIDE;
        public object DP_LAST, DP_TGT_SAVE;
        public double EPR_T0, EPR_TGT_LAT, EPR_TGT_LNG, EPR_HINT_RHO, EPR_PR_REF;
        public int EPR_STEPS;
        public Vec3 EPR_IR, EPR_IV, EPR_PR, EPR_PV;
        public double EPR_IT, EPR_IARC, EPR_IBK, EPR_PT, EPR_PA, EPR_PVR, EPR_PARC, EPR_FAM_BANK_NOW;
        public bool EPR_IOK, EPR_IDONE, EPR_HAVEPREV, EPR_LAT_ON;
        public double EPR_LAT_TROT, EPR_LAT_CMD, EPR_LAT_RATE;
        public int EPR_LAT_SIGN, EPR_LAT_REV;
        public double EPR_TERM_ALT, EPR_TERM_VEL; public string EPR_TERM_WHY;
        public double EPR_MP_LAT, EPR_MP_LNG, EPR_MP_TROT, EPR_MP_GC, EPR_SOL_LAT, EPR_SOL_LNG;

        public DpG(KLex g) { DpFill.Fill(this, g, "DP state"); }
    }

    // THE J2 EPHEMERIS of the parking orbit (lib_kepler kepEphReach / kepEphAt): RK4 samples every KEP_EPH_DT s from the
    // elements' epoch. Reach() before any parallel use; At() then only reads.
    public class DpEph
    {
        readonly DpEntry E;
        public readonly List<Vec3> R = new List<Vec3>(), V = new List<Vec3>();
        public DpEph(DpEntry e, Vec3 r0, Vec3 v0) { E = e; R.Add(r0); V.Add(v0); }
        public void Reach(double t)
        {
            double dt = E.C.KEP_EPH_DT;
            while (!((R.Count - 1) * dt > t))
            {
                Vec3 nr, nv;
                E.J2Step(R[R.Count - 1], V[V.Count - 1], dt, out nr, out nv);
                R.Add(nr); V.Add(nv);
            }
        }
        public void At(double t, out Vec3 pos, out Vec3 vel)
        {
            Reach(t);
            double DT = E.C.KEP_EPH_DT;
            double i = Math.Floor(t / DT);
            double u = (t - i * DT) / DT;
            double u2 = u * u;
            double u3 = u2 * u;
            int k = (int)i;
            pos = R[k] * (2 * u3 - 3 * u2 + 1) + V[k] * (DT * (u3 - 2 * u2 + u))
                  + R[k + 1] * (3 * u2 - 2 * u3) + V[k + 1] * (DT * (u3 - u2));
            vel = DpM.Div(R[k] * (6 * u2 - 6 * u) + V[k] * (DT * (3 * u2 - 4 * u + 1))
                          + R[k + 1] * (6 * u - 6 * u2) + V[k + 1] * (DT * (3 * u2 - 2 * u)), DT);
        }
    }

    // THE ENTRY PREDICTION and the geodesy (entry_predict.ks), on one DpG (the kOS globals). One instance per thread of work:
    // the vacuum parts (J2Step, ToGeo, GcDist, OmegaCross) read only the constants; the integrator writes G.
    public class DpEntry
    {
        public readonly DpC C;
        public DpG G;
        public DpEntry(DpC c, DpG g) { C = c; G = g; }

        // ---- the vacuum and the geodesy
        public Vec3 OmegaCross(Vec3 rv) { return Vec3.Cross(C.EPR_WAXIS * C.EPR_WMAG, rv); }

        public Vec3 J2Accel(Vec3 rv, double rmag)
        {
            double z = Vec3.Dot(rv, C.EPR_WAXIS);
            double k = -1.5 * C.EPR_J2 * C.EPR_MU * C.EPR_R_J2 * C.EPR_R_J2 / Math.Pow(rmag, 5);
            double zz = 5.0 * z * z / (rmag * rmag);
            return (rv * (1.0 - zz) + C.EPR_WAXIS * (2.0 * z)) * k;
        }

        public Vec3 J2Grav(Vec3 rv)
        {
            double rmag = rv.Mag;
            return rv * (-C.EPR_MU / (rmag * rmag * rmag)) + J2Accel(rv, rmag);
        }

        public void J2Step(Vec3 rv, Vec3 vv, double h, out Vec3 rn, out Vec3 vn)
        {
            Vec3 a1 = J2Grav(rv);
            Vec3 r2 = rv + vv * (h / 2); Vec3 v2 = vv + a1 * (h / 2);
            Vec3 a2 = J2Grav(r2);
            Vec3 r3 = rv + v2 * (h / 2); Vec3 v3 = vv + a2 * (h / 2);
            Vec3 a3 = J2Grav(r3);
            Vec3 r4 = rv + v3 * h; Vec3 v4 = vv + a3 * h;
            Vec3 a4 = J2Grav(r4);
            rn = rv + (vv + v2 * 2 + v3 * 2 + v4) * (h / 6);
            vn = vv + (a1 + a2 * 2 + a3 * 2 + a4) * (h / 6);
        }

        // eprJ2ToEI: the coast to the interface under J2 (RK4 at 30 s, the crossing by bisection); t = -1: never descends
        public void J2ToEI(Vec3 rv, Vec3 vv, out Vec3 ro, out Vec3 vo, out double to)
        {
            double tgt = C.EPR_R + C.EPR_ATM;
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
                    to = t + hi;
                    return;
                }
                rv = sr; vv = sv; t = t + h;
            }
            ro = rv; vo = vv; to = -1;
        }

        // eprToGeoRaw: LIST(lat, lng, alt)
        public double[] ToGeo(Vec3 rv, double tRot)
        {
            double rmag = rv.Mag;
            double lat = DpM.Asin(Math.Max(-1, Math.Min(1, Vec3.Dot(DpM.Nrm(rv), C.EPR_NAXIS))));
            Vec3 eq = rv - C.EPR_NAXIS * Vec3.Dot(rv, C.EPR_NAXIS);
            double lng = 0;
            if (eq.Mag > 1)
            {
                Vec3 e0 = C.EPR_GEO_X;
                Vec3 e1 = C.EPR_GEO_Y;
                lng = DpM.Atan2(Vec3.Dot(eq, e1), Vec3.Dot(eq, e0))
                      - C.EPR_ROT_SIGN * C.EPR_WMAG * tRot * C.C_RADTODEG;
            }
            while (!(lng <= 180)) lng = lng - 360;
            while (!(lng > -180)) lng = lng + 360;
            return new double[] { lat, lng, rmag - C.EPR_R };
        }

        public double GcDist(double lat1, double lng1, double lat2, double lng2)
        {
            double h = Math.Pow(DpM.Sin((lat2 - lat1) / 2), 2)
                       + DpM.Cos(lat1) * DpM.Cos(lat2) * Math.Pow(DpM.Sin((lng2 - lng1) / 2), 2);
            return 2 * C.EPR_R * DpM.Asin(Math.Min(1, Math.Sqrt(Math.Max(h, 0)))) * C.C_DEGTORAD;
        }

        // eprEastNorth: false = the zero pair
        public bool EastNorth(Vec3 rv, out Vec3 east, out Vec3 north)
        {
            Vec3 upv = DpM.Nrm(rv);
            Vec3 eastv = OmegaCross(rv);
            if (eastv.Mag < 0.001) { east = Vec3.Zero; north = Vec3.Zero; return false; }
            eastv = DpM.Nrm(eastv);
            east = eastv;
            north = Vec3.Cross(upv, eastv) * C.EPR_NSIGN;
            return true;
        }

        public double AzErrorAt(Vec3 rv, Vec3 vv, double tRot, double tgtLat, double tgtLng)
        {
            Vec3 vrelv = vv - OmegaCross(rv);
            Vec3 upv = DpM.Nrm(rv);
            Vec3 hz = vrelv - upv * Vec3.Dot(vrelv, upv);
            if (hz.Mag < 1) return 0;
            double[] g = ToGeo(rv, tRot);
            Vec3 eq = rv - C.EPR_WAXIS * Vec3.Dot(rv, C.EPR_WAXIS);
            if (eq.Mag < 1) return 0;
            Vec3 e0, e1;
            EastNorth(rv, out e0, out e1);
            if (e0.Mag < 0.5) return 0;
            double hdg = DpM.Atan2(Vec3.Dot(hz, e0), Vec3.Dot(hz, e1));
            double dl = tgtLng - g[1];
            double brg = DpM.Atan2(DpM.Sin(dl) * DpM.Cos(tgtLat), DpM.Cos(g[0]) * DpM.Sin(tgtLat) - DpM.Sin(g[0]) * DpM.Cos(tgtLat) * DpM.Cos(dl));
            double e = -(brg - hdg);
            while (!(e <= 180)) e = e - 360;
            while (!(e > -180)) e = e + 360;
            return e;
        }

        // ---- the air
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
            return Math.Pow(C.C_E, Math.Log(y0) + f * (Math.Log(y1) - Math.Log(y0)));
        }

        public double Rho(double altm)
        {
            double i;
            double r = LogInterp(C.EPR_RHO, altm, G.EPR_HINT_RHO, out i);
            G.EPR_HINT_RHO = i;
            return r;
        }

        double Pres(double altm)
        {
            if (altm >= C.EPR_ATM) return 0;
            return C.AltPres(Math.Max(altm, 0)) * C.C_ATMTOKPA * 1000;
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
            if (G.EPR_PR_REF < 0) G.EPR_PR_REF = Hermite(C.EPR_PSEUDORE, 1);
            return G.EPR_PR_REF;
        }

        double PrMult(double rhov)
        {
            double pr = Hermite(C.EPR_PSEUDORE, rhov) / PrRef();
            if (pr <= 1) return pr;
            return 1 + C.EPR_PR_SHARE * (pr - 1);
        }

        double MachFrom(double altm, double vrel, double rh)
        {
            double ps = Pres(altm);
            if (ps <= 0 || rh <= 0) return 0;
            return vrel / Math.Sqrt(C.EPR_GAMMA * ps / rh);
        }

        // ---- alpha and the aero
        double AoA(double vrel)
        {
            if (C.EPR_AOA_RAMP_ON) return Math.Min(AoANom(vrel), AoARamp(vrel));
            return AoANom(vrel);
        }
        double AoARamp(double vrel)
        {
            if (vrel < C.EPR_AOA_HIGH_SPEED)        // eprAoARamp's line under EPR_AOA_HIGH_SPEED
            {
                double fl = (vrel - C.EPR_AOA_LOW_SPEED) / (C.EPR_AOA_HIGH_SPEED - C.EPR_AOA_LOW_SPEED);
                return C.EPR_AOA_LOW + (C.EPR_AOA_RAMP_LO - C.EPR_AOA_LOW) * Math.Max(0, Math.Min(1, fl));
            }
            if (vrel >= C.EPR_AOA_RAMP_V_HI) return C.EPR_AOA_RAMP_HI;
            if (vrel <= C.EPR_AOA_RAMP_V_LO) return C.EPR_AOA_RAMP_LO;
            return C.EPR_AOA_RAMP_LO + (C.EPR_AOA_RAMP_HI - C.EPR_AOA_RAMP_LO) * (vrel - C.EPR_AOA_RAMP_V_LO) / (C.EPR_AOA_RAMP_V_HI - C.EPR_AOA_RAMP_V_LO);
        }
        double AoANom(double vrel)
        {
            if (vrel >= C.EPR_AOA_HIGH_SPEED) return C.EPR_AOA_HIGH;
            double span = C.EPR_AOA_HIGH_SPEED - C.EPR_AOA_LOW_SPEED;
            if (span <= 0) return C.EPR_AOA_LOW;
            double fr = (vrel - C.EPR_AOA_LOW_SPEED) / span;
            if (fr < 0) fr = 0;
            if (fr > 1) fr = 1;
            return C.EPR_AOA_LOW + (C.EPR_AOA_HIGH - C.EPR_AOA_LOW) * fr;
        }

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
            double s = DpM.Sin(Math.Max(0, Math.Min(90, aoa)));
            double ia = Bracket(C.EPR_LIFT_CURVE, s);
            double im = Bracket(C.EPR_LIFT_MACH, mach);
            double ip = Math.Max(0, ia - C.EPR_PAR_SHIFT);
            double cl = C.EPR_K_LIFT * HermAt(C.EPR_LIFT_CURVE, s, ia) * HermAt(C.EPR_LIFT_MACH, mach, im);
            double pa = C.EPR_K_PAR * (
                C.EPR_PAR_W_WING * HermAt(C.EPR_WING_PAR_A, s, ip) * HermAt(C.EPR_WING_PAR_M, mach, im) +
                C.EPR_PAR_W_FUS * HermAt(C.EPR_FUS_PAR_A, s, ip) * HermAt(C.EPR_FUS_PAR_M, mach, im) +
                C.EPR_PAR_W_CTL * HermAt(C.EPR_CTL_PAR_A, s, ip) * HermAt(C.EPR_CTL_PAR_M, mach, im));
            cla = cl * C.EPR_MASS_K * C.EPR_TRIM_FL;
            cda = (cl * DpM.Tan(a) + pa) * C.EPR_MASS_K * C.EPR_TRIM_FD;
        }
        double Cda(double aoa, double mach) { double l, d; Polar(aoa, mach, out l, out d); return d; }
        double SbFrac(double mach, double spd)
        {
            if (!C.EPR_SB_ON || spd >= C.EPR_SB_V) return 0;
            double ramp = Math.Min(1, (C.EPR_SB_V - spd) / (C.EPR_SB_V - C.EPR_SB_V_FULL));
            var t = C.EPR_SB_FRAC;
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
            var t = C.EPR_CD_FIX;
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
            double[] lo = C.EPR_AERO_FIX[0], hi = C.EPR_AERO_FIX[1];
            double w = Math.Min(1, Math.Max(0, (mach - lo[0]) / (hi[0] - lo[0])));
            double da = Math.Max(aoa - 40, 0);
            double ft = 0;
            if (C.EPR_FLAP_X > -90) ft = FlapTerm(C.EPR_FLAP_X, C.EPR_FLAP_KF, C.EPR_FLAP_TAB, mach);
            return new double[] { Math.Pow(Math.E, lo[1] + (hi[1] - lo[1]) * w + (lo[2] + (hi[2] - lo[2]) * w) * da + ft),
                                  Math.Pow(Math.E, lo[3] + (hi[3] - lo[3]) * w + (lo[4] + (hi[4] - lo[4]) * w) * da) };
        }
        double CdaEntry(double aoa, double mach, double spd) { return Cda(aoa, mach) * (1 + CdFix(mach)) * AeroFix(aoa, mach)[0] * (1 + SbFrac(mach, spd)); }

        Vec3 Accel(Vec3 rv, Vec3 vv, double bankDeg)
        {
            double rmag = rv.Mag;
            Vec3 g = rv * (-C.EPR_MU / (rmag * rmag * rmag));
            if (C.EPR_J2_ON) g = g + J2Accel(rv, rmag);
            Vec3 vrelv = vv - OmegaCross(rv);
            double vr = vrelv.Mag;
            double altm = rmag - C.EPR_R;
            if (vr < 1 || altm >= C.EPR_ATM) return g;
            double rho = Rho(altm);
            if (rho <= 0) return g;
            double qdyn = 0.5 * rho * vr * vr;
            Vec3 vh = DpM.Div(vrelv, vr);
            double mach = MachFrom(altm, vr, rho);
            double aoa = AoA(vr);
            double pr = PrMult(rho * vr);
            double cla, cda;
            Polar(aoa, mach, out cla, out cda);
            double[] fix = AeroFix(aoa, mach);
            Vec3 aDrag = vh * (-cda * (1 + CdFix(mach)) * fix[0] * (1 + SbFrac(mach, vr)) * qdyn * pr);
            Vec3 upv = DpM.Div(rv, rmag);
            Vec3 upp = upv - vh * Vec3.Dot(upv, vh);
            if (upp.Mag < 0.000001) return g + aDrag;
            upp = DpM.Nrm(upp);
            Vec3 sd = Vec3.Cross(vh, upp);
            double b = bankDeg;
            Vec3 ldir = upp * DpM.Cos(b) + sd * DpM.Sin(b);
            return g + aDrag + ldir * (cla * fix[1] * qdyn);
        }

        // ---- the lateral logic (eprLatBank and its helpers)
        double MinBank(double mach, double delazDeg)
        {
            if (!C.EPR_USE_MIN_BANK) return 0;
            if (mach > C.EPR_MIN_BANK_MACH)
            {
                double need = C.EPR_MIN_BANK_DELAZ_K * Math.Abs(delazDeg);
                if (need <= C.EPR_MIN_BANK_HI_LOW) return C.EPR_MIN_BANK_HI_LOW;
                return C.EPR_MIN_BANK_HI_HIGH;
            }
            return C.EPR_MIN_BANK_LOW;
        }

        double AzDeadband(double mach, bool first)
        {
            if (first) return C.EPR_AZ_FIRST;
            if (mach >= C.EPR_AZ_MACH_HI) return C.EPR_AZ_SUBS;
            if (mach <= C.EPR_AZ_MACH_LO) return C.EPR_AZ_LATE;
            double f = (mach - C.EPR_AZ_MACH_LO) / (C.EPR_AZ_MACH_HI - C.EPR_AZ_MACH_LO);
            return C.EPR_AZ_LATE + (C.EPR_AZ_SUBS - C.EPR_AZ_LATE) * f;
        }

        void BankSlew(double cur, double tgt, double rate, double dt, out double bank, out double rateOut)
        {
            double err = tgt - cur;
            double dtc = Math.Max(dt, 0.001);
            double want = err / dtc;
            if (want > C.EPR_ROLL_RATE_LIMIT) want = C.EPR_ROLL_RATE_LIMIT;
            if (want < 0 - C.EPR_ROLL_RATE_LIMIT) want = 0 - C.EPR_ROLL_RATE_LIMIT;
            double vmax = Math.Sqrt(2 * C.EPR_ROLL_ACCEL_LIMIT * Math.Abs(err));
            if (want > vmax) want = vmax;
            if (want < 0 - vmax) want = 0 - vmax;
            double hi = rate + C.EPR_ROLL_ACCEL_LIMIT * dt;
            double lo = rate - C.EPR_ROLL_ACCEL_LIMIT * dt;
            if (want > hi) want = hi;
            if (want < lo) want = lo;
            bank = cur + want * dt;
            rateOut = want;
        }

        double BankWithFlare(double bankDeg, double vr)
        {
            double b = Math.Abs(bankDeg);
            if (C.EPR_BANK_FLARE_SPEED > 0 && vr <= C.EPR_BANK_FLARE_SPEED && b > C.EPR_BANK_FLARE_MAX)
                b = C.EPR_BANK_FLARE_MAX + (b - C.EPR_BANK_FLARE_MAX) * C.EPR_BANK_FLARE_SLOPE;
            if (C.EPR_BANK_TAEM_SPEED > 0 && vr < C.EPR_BANK_TAEM_SPEED)
            {
                double span = C.EPR_BANK_TAEM_SPEED - C.EPR_TAEM_VEL;
                double w = 1;
                if (span > 0) w = (C.EPR_BANK_TAEM_SPEED - vr) / span;
                w = Math.Max(0, Math.Min(1, w));
                b = b * (1 - w * (1 - C.EPR_BANK_TAEM_LIMIT / C.EPR_BANK_MAX));
            }
            if (vr <= C.EPR_BANK_STOP_SPEED) b = 0;
            return b;
        }

        double LatBank(double bankDeg, Vec3 rv, Vec3 vv, double t)
        {
            double altm = rv.Mag - C.EPR_R;
            double vrel = (vv - OmegaCross(rv)).Mag;
            double az = AzErrorAt(rv, vv, G.EPR_LAT_TROT + t, G.EPR_TGT_LAT, G.EPR_TGT_LNG);
            if (G.EPR_LAT_SIGN == 0) G.EPR_LAT_SIGN = az >= 0 ? 1 : -1;
            double rho = Rho(altm);
            double mach = MachFrom(altm, vrel, rho);
            double db = AzDeadband(mach, G.EPR_LAT_REV == 0);
            int ns = G.EPR_LAT_SIGN;
            if (az > db) ns = 1; else if (az < -db) ns = -1;
            if (ns != G.EPR_LAT_SIGN)
            {
                G.EPR_LAT_REV = G.EPR_LAT_REV + 1;
                G.EPR_LAT_SIGN = ns;
            }
            double want = G.EPR_LAT_SIGN * bankDeg;
            if (C.EPR_USE_MIN_BANK && G.EPR_LAT_SIGN * az > 0 && rho > 0 && vrel > 1)
            {
                double pr = PrMult(rho * vrel);
                if (CdaEntry(AoA(vrel), mach, vrel) * 0.5 * rho * vrel * vrel * pr >= C.EPR_GUID_DRAG_INIT)
                {
                    double fl = MinBank(mach, az);
                    if (Math.Abs(want) < fl) want = G.EPR_LAT_SIGN * fl;
                }
            }
            double sg = want >= 0 ? 1 : -1;
            want = sg * BankWithFlare(want, vrel);
            if (vrel <= C.EPR_BANK_STOP_SPEED) want = 0;
            double nb, nr;
            BankSlew(G.EPR_LAT_CMD, want, G.EPR_LAT_RATE, C.EPR_IDT, out nb, out nr);
            G.EPR_LAT_CMD = nb;
            G.EPR_LAT_RATE = nr;
            return G.EPR_LAT_CMD;
        }

        // ---- the integrator (eprIntStart / eprIntRun with EPR_FAM_ACTIVE and EPR_TRACE_ON FALSE)
        public void IntStart(Vec3 rv, Vec3 vv, double bankDeg)
        {
            G.EPR_IR = rv; G.EPR_IV = vv; G.EPR_IT = 0; G.EPR_IARC = 0;
            G.EPR_IBK = bankDeg; G.EPR_IOK = false; G.EPR_IDONE = false;
            G.EPR_HAVEPREV = false;
            // eprLatReset (when EPR_LAT_ON): the guidance's lateral state; the planner overwrites all four at once (dpIntStart)
        }

        public bool IntRun(double budget)
        {
            double k = 0;
            double vstop = C.EPR_TAEM_VEL;
            while (!(k >= budget))
            {
                double rmag = G.EPR_IR.Mag;
                double altm = rmag - C.EPR_R;
                double vr = (G.EPR_IV - OmegaCross(G.EPR_IR)).Mag;
                if (altm <= C.EPR_TAEM_ALT || (altm < C.EPR_ATM && vr <= vstop))
                {
                    if (G.EPR_HAVEPREV)
                    {
                        double fr = 1;
                        if (altm <= C.EPR_TAEM_ALT && G.EPR_PA > C.EPR_TAEM_ALT)
                            fr = (G.EPR_PA - C.EPR_TAEM_ALT) / Math.Max(G.EPR_PA - altm, 0.000000001);
                        else if (G.EPR_PVR > vstop)
                            fr = (G.EPR_PVR - vstop) / Math.Max(G.EPR_PVR - vr, 0.000000001);
                        fr = Math.Max(0, Math.Min(1, fr));
                        G.EPR_IR = G.EPR_PR + (G.EPR_IR - G.EPR_PR) * fr;
                        G.EPR_IV = G.EPR_PV + (G.EPR_IV - G.EPR_PV) * fr;
                        G.EPR_IT = G.EPR_PT + (G.EPR_IT - G.EPR_PT) * fr;
                        altm = G.EPR_IR.Mag - C.EPR_R;
                        vr = (G.EPR_IV - OmegaCross(G.EPR_IR)).Mag;
                    }
                    G.EPR_TERM_ALT = altm;
                    G.EPR_TERM_VEL = vr;
                    if (altm <= C.EPR_TAEM_ALT + 1) G.EPR_TERM_WHY = "taemalt";
                    else G.EPR_TERM_WHY = "taemvel";
                    G.EPR_IOK = true; G.EPR_IDONE = true; return true;
                }
                if (altm < 0 || G.EPR_IT > 2500)
                {
                    G.EPR_TERM_ALT = altm;
                    G.EPR_TERM_VEL = vr;
                    if (altm < 0) G.EPR_TERM_WHY = "ground"; else G.EPR_TERM_WHY = "timeout";
                    G.EPR_IOK = false; G.EPR_IDONE = true; return true;
                }
                G.EPR_PR = G.EPR_IR; G.EPR_PV = G.EPR_IV; G.EPR_PT = G.EPR_IT;
                G.EPR_PA = altm; G.EPR_PVR = vr; G.EPR_HAVEPREV = true;
                G.EPR_PARC = G.EPR_IARC;
                double bnk = G.EPR_IBK;
                if (G.EPR_LAT_ON) bnk = LatBank(G.EPR_IBK, G.EPR_IR, G.EPR_IV, G.EPR_IT);
                Vec3 a1 = Accel(G.EPR_IR, G.EPR_IV, bnk);
                Vec3 rm = G.EPR_IR + G.EPR_IV * (0.5 * C.EPR_IDT);
                Vec3 vm = G.EPR_IV + a1 * (0.5 * C.EPR_IDT);
                Vec3 a2 = Accel(rm, vm, bnk);
                G.EPR_FAM_BANK_NOW = bnk;
                Vec3 arcVrel = G.EPR_IV - OmegaCross(G.EPR_IR);
                double arcVh = DpM.Vxcl(DpM.Nrm(G.EPR_IR), arcVrel).Mag;
                G.EPR_IARC = G.EPR_IARC + arcVh * C.EPR_IDT * (C.EPR_R / G.EPR_IR.Mag);
                G.EPR_IR = G.EPR_IR + vm * C.EPR_IDT;
                G.EPR_IV = G.EPR_IV + a2 * C.EPR_IDT;
                G.EPR_IT = G.EPR_IT + C.EPR_IDT;
                k = k + 1;
                G.EPR_STEPS = G.EPR_STEPS + 1;
            }
            return false;
        }

        // eprMissPath: the along-path miss (the arc flown less the interface's range to the aim)
        public double MissPath(Vec3 r0, double tgtLat, double tgtLng)
        {
            double[] g = ToGeo(G.EPR_IR, G.EPR_T0 + G.EPR_IT);
            G.EPR_SOL_LAT = g[0];
            G.EPR_SOL_LNG = g[1];
            double[] g0 = ToGeo(r0, G.EPR_T0);
            G.EPR_MP_LAT = g0[0];
            G.EPR_MP_LNG = g0[1];
            G.EPR_MP_TROT = G.EPR_T0;
            G.EPR_MP_GC = GcDist(g0[0], g0[1], tgtLat, tgtLng);
            return G.EPR_IARC - G.EPR_MP_GC;
        }
    }
}
