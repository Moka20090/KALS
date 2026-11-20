// THE ABORT ONCE AROUND SOLVE in the KAL/S coprocessor,
// a line-for-line port of lib/lib_aoa.ks's aoaSolve (aoaPeriApo, aoaFpaNom, aoaFpaAt, aoaKepFpa, aoaDvtForFpa, aoaStep,
// aoaEphem, aoaStateAt, aoaBearing, aoaAzErr, aoaHpJ2, aoaDmid, aoaEval, aoaBurnEI, aoaAtIg, aoaBisect, aoaSolveIg, the radial
// fallback aoaRadialOut / aoaDvtForFpaR / aoaBurnEIR / aoaAtIgR / aoaRadialAt / aoaSolveRadial) and of the entry_predict.ks
// functions it calls (eprOmegaCross, eprJ2Accel, eprJ2Grav, eprJ2Step, eprJ2ToEI, eprKepState, eprKepToEI, eprToGeoRaw,
// eprEastNorth, eprGcDist, eprDestGeo). kOS semantics: trig in degrees as kOS.Safe computes it (SIN(d) = Math.Sin(d * pi /
// 180), ARCSIN(x) = Math.Asin(x) * 180 / pi, ARCTAN2 the same), ^ = Math.Pow (CONSTANT:E ^ x = Math.Pow(E, x)), MOD = %,
// vectors as KSP's Vector3d (kOS's Vector: VDOT / VCRS / :MAG / :NORMALIZED), the same order of operations. Every constant
// (the EPR_* and AOA_* globals, CONSTANT:E / :RADTODEG / :DEGTORAD) comes from kOS at each solve (AoaC, all required):
// nothing is retyped here. THREADS: the ignition grid of each angle and the bisections of its brackets, and the radial
// fallback's ignitions, are independent: they run on AoaPool's workers and are reduced afterwards in kOS's own order, so the
// result is the sequential one. The worker touches no Unity / kOS object.
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;

namespace KalsCoproc
{
    // the constants: kOS's globals by their own names (AoaC.Set fills every field from kOS's values; all required)
    public class AoaC
    {
        public double CE, RADTODEG, DEGTORAD;                  // CONSTANT:E, :RADTODEG, :DEGTORAD
        public double EPR_R, EPR_MU, EPR_ATM, EPR_WMAG, EPR_J2, EPR_R_J2, EPR_NSIGN, EPR_ROT_SIGN;
        public bool EPR_J2_ON;
        public Vec3 EPR_WAXIS, EPR_NAXIS, EPR_GEO_X, EPR_GEO_Y;
        public double AOA_FAC, AOA_FPA_SLOPE, AOA_FPA_ICPT, AOA_FPA_MARGIN, AOA_FPA_STEP, AOA_FPA_KMAX, AOA_FPA_TOL;
        public double[] AOA_XT_MAX;
        public double AOA_T_LEAD, AOA_DT, AOA_T_HI_PAD, AOA_T_MAX, AOA_F_TOL, AOA_F_OFF;
        public double AOA_DVR_STEP, AOA_DVR_ITERS, AOA_DVR_MAX, AOA_DVR_FTOL, AOA_FTP_M;
        public double[] AOA_SUR_C, AOA_SUR_D;
        public double AOA_SUR_HP0, AOA_SUR_HA0, AOA_SUR_HAS, AOA_SUR_V0, AOA_SUR_VS;
        public double[] AOA_SUR_BOX;
        public double AOA_ARC_MAX, AOA_HPJ2_KMAX;
        public double[] AOA_XT_T0, AOA_XT_T1, AOA_XT_EPS, AOA_XT_C;
        public double AOA_RAMP_G0, AOA_RAMP_G1, AOA_RAMP_G2;   // G2: the ramp's perigee-height term

        // the names kOS must hand over (aoaCsConsts builds exactly these)
        public static List<string> Names()
        {
            var l = new List<string>();
            foreach (var f in typeof(AoaC).GetFields(BindingFlags.Public | BindingFlags.Instance)) l.Add(f.Name);
            return l;
        }

        // get(name) -> double / bool / Vec3 / double[] (the bridge converts kOS's values; a missing one throws there)
        public static AoaC From(Func<string, Type, object> get)
        {
            var c = new AoaC();
            foreach (var f in typeof(AoaC).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                object o = get(f.Name, f.FieldType);
                if (o == null) throw new KeyNotFoundException("constant " + f.Name + " missing");
                if (f.FieldType == typeof(double)) Fin(f.Name, (double)o);
                if (f.FieldType == typeof(double[])) foreach (var d in (double[])o) Fin(f.Name, d);
                if (f.FieldType == typeof(Vec3)) { var v = (Vec3)o; Fin(f.Name, v.X); Fin(f.Name, v.Y); Fin(f.Name, v.Z); }
                f.SetValue(c, o);
            }
            if (c.AOA_XT_MAX.Length < 2 || c.AOA_XT_T0.Length < 2 || c.AOA_XT_T1.Length < 2 || c.AOA_XT_EPS.Length < 2
                || c.AOA_XT_C.Length < 2 || c.AOA_SUR_C.Length < 11 || c.AOA_SUR_D.Length < 7 || c.AOA_SUR_BOX.Length < 6)
                throw new ArgumentException("a constant list is too short");
            if (c.AOA_DT <= 0) throw new ArgumentException("AOA_DT <= 0");
            return c;
        }

        static void Fin(string k, double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("constant " + k + " is not finite");
        }
    }

    // one ignition (aoaEval's LEXICON, + aoaAtIgR's dvr / dv, + aoaSolve's fpaTarget / fpaUsed)
    public class AoaX
    {
        public double t, dvt, tc, f, az, xt, dAim, dmid, lat, lng, aimLat, aimLng, hp, ha, fpa, xp, xa, xm, xo, arc, hpj2, vrel;
        public bool ramp;
        public bool hasR; public double dvr, dv;
        public bool hasFpa; public double fpaTarget, fpaUsed;

        // the keys in kOS's order (aoaEval's LEXICON, then x:ADD's)
        public List<KeyValuePair<string, object>> Pairs()
        {
            var l = new List<KeyValuePair<string, object>>();
            Action<string, object> a = (k, v) => l.Add(new KeyValuePair<string, object>(k, v));
            a("t", t); a("dvt", dvt); a("tc", tc); a("f", f); a("az", az); a("xt", xt); a("dAim", dAim); a("dmid", dmid);
            a("lat", lat); a("lng", lng); a("aimLat", aimLat); a("aimLng", aimLng); a("hp", hp); a("ha", ha); a("fpa", fpa);
            a("xp", xp); a("xa", xa); a("xm", xm); a("xo", xo); a("ramp", ramp); a("arc", arc); a("hpj2", hpj2); a("vrel", vrel);
            if (hasR) { a("dvr", dvr); a("dv", dv); }
            if (hasFpa) { a("fpaTarget", fpaTarget); a("fpaUsed", fpaUsed); }
            return l;
        }
    }

    // a coast state LIST(r, v) and an interface LIST(r, v, elapsed)
    public struct AoaSt { public Vec3 r, v; public double t; public AoaSt(Vec3 r_, Vec3 v_, double t_) { r = r_; v = v_; t = t_; } }

    // the solve's input (aoaSolve's parameters + what kOS reads around it)
    public class AoaIn
    {
        public AoaC c;
        public Vec3 rv, vv;
        public double tGeo, slat, slng, dvMax;
        public bool radial;          // DEFINED OMS_PLAN_DVR AND OMS_PLAN_DVR (aoaSolve's radOn)
        public double spent;         // aoaSpent() at the call (the radial grid's start and its tMin)
        public int threads;          // 0 = MIN(4, CPUs - 1)
    }

    // the result: x (or none) + what kOS's aoaSolve leaves in its globals
    public class AoaRes
    {
        public AoaX x;               // null = 0
        public int whyk;             // 0 found; 1 NOT IN ORBIT; 2 no time for OMS-2 (tHi); 3 no OMS-2 (gam0, the radial flag)
        public int xtOnly = -1;      // AOA_XT_ONLY at the end (-1: aoaSolve left it unchanged)
        public double tHi, gam0;
        public int evals, evalsR;    // aoaAtIg / aoaAtIgR calls (kOS's count, for the log)
        public double ms;
        public int threads;
    }

    // a fixed set of workers for one solve: For(n, body) runs body(0..n-1) on them and the caller, and returns when all are done
    public class AoaPool : IDisposable
    {
        class Batch { public Action<int> B; public int N, Next, Done; public Exception Err; }
        readonly object lk = new object();
        readonly List<Thread> th = new List<Thread>();
        Batch cur; bool quit;

        public AoaPool(int n)
        {
            for (int i = 1; i < n; i++)
            {
                var t = new Thread(Worker);
                t.IsBackground = true;
                t.Priority = ThreadPriority.BelowNormal;
                th.Add(t);
                t.Start();
            }
        }

        void Worker()
        {
            Batch seen = null;
            while (true)
            {
                Batch b;
                lock (lk)
                {
                    while ((b = cur) == seen && !quit) Monitor.Wait(lk);
                    if (quit) return;
                    seen = b;
                }
                Work(b);
            }
        }

        void Work(Batch b)
        {
            while (true)
            {
                int i = Interlocked.Increment(ref b.Next) - 1;
                if (i >= b.N) return;
                try { b.B(i); }
                catch (Exception ex) { lock (lk) { if (b.Err == null) b.Err = ex; } }
                if (Interlocked.Increment(ref b.Done) == b.N) lock (lk) { Monitor.PulseAll(lk); }
            }
        }

        public void For(int n, Action<int> body)
        {
            if (n <= 0) return;
            var b = new Batch { B = body, N = n };
            if (th.Count > 0) lock (lk) { cur = b; Monitor.PulseAll(lk); }
            Work(b);
            lock (lk) { while (b.Done < b.N) Monitor.Wait(lk); }
            if (b.Err != null) throw new Exception("worker: " + b.Err.GetType().Name + ": " + b.Err.Message, b.Err);
        }

        public void Dispose() { lock (lk) { quit = true; Monitor.PulseAll(lk); } }
    }

    public class Aoa
    {
        readonly AoaC C;
        readonly AoaPool P;
        int xtOnly;                  // AOA_XT_ONLY
        int nEval, nEvalR;
        double spent;

        public Aoa(AoaC c, AoaPool pool) { C = c; P = pool; }

        // ---- kOS's built-ins (kOS.Safe's own forms: t62/peg, t62/pad)
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }
        static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        // Vector3d.normalized: each component / the magnitude (cs/VecProbe.cs: bit for bit on 200000 random vectors; KSP's
        // Vector3d keeps 1e-20 vectors, zeroes only a zero magnitude: every vector normalized here is >= 1e-3 long)
        static Vec3 Nrm(Vec3 a)
        {
            double m = a.Mag;
            if (m > 0) return new Vec3(a.X / m, a.Y / m, a.Z / m);
            return Vec3.Zero;
        }
        static double Dot(Vec3 a, Vec3 b) { return Vec3.Dot(a, b); }
        static Vec3 Cross(Vec3 a, Vec3 b) { return Vec3.Cross(a, b); }

        // ================================================================ entry_predict.ks
        Vec3 OmegaCross(Vec3 rv) { return Cross(C.EPR_WAXIS * C.EPR_WMAG, rv); }

        Vec3 J2Accel(Vec3 rv, double rmag)
        {
            double z = Dot(rv, C.EPR_WAXIS);
            double k = -1.5 * C.EPR_J2 * C.EPR_MU * C.EPR_R_J2 * C.EPR_R_J2 / Math.Pow(rmag, 5);
            double zz = 5.0 * z * z / (rmag * rmag);
            return (rv * (1.0 - zz) + C.EPR_WAXIS * (2.0 * z)) * k;
        }

        Vec3 J2Grav(Vec3 rv)
        {
            double rmag = rv.Mag;
            return rv * (-C.EPR_MU / (rmag * rmag * rmag)) + J2Accel(rv, rmag);
        }

        AoaSt J2Step(Vec3 rv, Vec3 vv, double h)
        {
            Vec3 a1 = J2Grav(rv);
            Vec3 r2 = rv + vv * (h / 2); Vec3 v2 = vv + a1 * (h / 2);
            Vec3 a2 = J2Grav(r2);
            Vec3 r3 = rv + v2 * (h / 2); Vec3 v3 = vv + a2 * (h / 2);
            Vec3 a3 = J2Grav(r3);
            Vec3 r4 = rv + v3 * h; Vec3 v4 = vv + a3 * h;
            Vec3 a4 = J2Grav(r4);
            return new AoaSt(rv + (vv + v2 * 2 + v3 * 2 + v4) * (h / 6), vv + (a1 + a2 * 2 + a3 * 2 + a4) * (h / 6), 0);
        }

        AoaSt J2ToEI(Vec3 rv, Vec3 vv)
        {
            double tgt = C.EPR_R + C.EPR_ATM;
            double t = 0;
            double h = 30;
            while (!(t > 20000))
            {
                AoaSt st = J2Step(rv, vv, h);
                if (st.r.Mag <= tgt)
                {
                    double lo = 0; double hi = h;
                    for (int k = 0; k < 20; k++)
                    {
                        double mid = 0.5 * (lo + hi);
                        if (J2Step(rv, vv, mid).r.Mag > tgt) lo = mid; else hi = mid;
                    }
                    AoaSt fin = J2Step(rv, vv, hi);
                    return new AoaSt(fin.r, fin.v, t + hi);
                }
                rv = st.r; vv = st.v; t = t + h;
            }
            return new AoaSt(rv, vv, -1);
        }

        AoaSt KepState(Vec3 rv, Vec3 vv, double dt)
        {
            double r0m = rv.Mag;
            double v0m = vv.Mag;
            double sma = 1 / (2 / r0m - v0m * v0m / C.EPR_MU);
            if (sma <= 0) return new AoaSt(rv, vv, 0);
            double sig0 = Dot(rv, vv) / Math.Sqrt(C.EPR_MU);
            double ecosE = 1 - r0m / sma;
            double esinE = sig0 / Math.Sqrt(sma);
            double e0R = Atan2(esinE, ecosE) * C.DEGTORAD;
            double ecc = Math.Sqrt(ecosE * ecosE + esinE * esinE);
            double n = Math.Sqrt(C.EPR_MU / (sma * sma * sma));
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
            double gg = dt - Math.Sqrt(sma * sma * sma / C.EPR_MU) * (deaR - Sin(deaD));
            Vec3 rNew = rv * ff + vv * gg;
            double rNm = rNew.Mag;
            double fd = 0 - Math.Sqrt(C.EPR_MU * sma) / (rNm * r0m) * Sin(deaD);
            double gd = 1 - sma / rNm * (1 - Cos(deaD));
            return new AoaSt(rNew, rv * fd + vv * gd, 0);
        }

        public AoaSt KepToEI(Vec3 rv, Vec3 vv)
        {
            if (C.EPR_J2_ON) return J2ToEI(rv, vv);
            double tgt = C.EPR_R + C.EPR_ATM;
            if (rv.Mag <= tgt) return new AoaSt(rv, vv, 0);
            double lo = 0;
            double hi = 10;
            double guard = 0;
            while (!(KepState(rv, vv, hi).r.Mag <= tgt || guard > 20))
            {
                hi = hi * 2;
                guard = guard + 1;
            }
            if (KepState(rv, vv, hi).r.Mag > tgt) return new AoaSt(rv, vv, -1);
            int k = 0;
            while (!(k >= 34))
            {
                k = k + 1;
                double mid = 0.5 * (lo + hi);
                if (KepState(rv, vv, mid).r.Mag > tgt) lo = mid; else hi = mid;
            }
            AoaSt st = KepState(rv, vv, hi);
            return new AoaSt(st.r, st.v, hi);
        }

        // eprToGeoRaw: LIST(lat, lng, alt)
        double[] ToGeoRaw(Vec3 rv, double tRot)
        {
            double rmag = rv.Mag;
            double lat = Asin(Max(-1, Min(1, Dot(Nrm(rv), C.EPR_NAXIS))));
            Vec3 eq = rv - C.EPR_NAXIS * Dot(rv, C.EPR_NAXIS);
            double lng = 0;
            if (eq.Mag > 1)
            {
                Vec3 e0 = C.EPR_GEO_X;
                Vec3 e1 = C.EPR_GEO_Y;
                lng = Atan2(Dot(eq, e1), Dot(eq, e0)) - C.EPR_ROT_SIGN * C.EPR_WMAG * tRot * C.RADTODEG;
            }
            while (!(lng <= 180)) lng = lng - 360;
            while (!(lng > -180)) lng = lng + 360;
            return new double[] { lat, lng, rmag - C.EPR_R };
        }

        double GcDist(double lat1, double lng1, double lat2, double lng2)
        {
            double h = Math.Pow(Sin((lat2 - lat1) / 2), 2)
                       + Cos(lat1) * Cos(lat2) * Math.Pow(Sin((lng2 - lng1) / 2), 2);
            return 2 * C.EPR_R * Asin(Min(1, Math.Sqrt(Max(h, 0)))) * C.DEGTORAD;
        }

        double[] DestGeo(double lat1, double lng1, double brngD, double distM)
        {
            double arcDeg = distM / C.EPR_R * C.RADTODEG;
            double lat2 = Asin(Max(-1, Min(1,
                Sin(lat1) * Cos(arcDeg) + Cos(lat1) * Sin(arcDeg) * Cos(brngD))));
            double lng2 = lng1 + Atan2(Sin(brngD) * Sin(arcDeg) * Cos(lat1),
                                       Cos(arcDeg) - Sin(lat1) * Sin(lat2));
            while (!(lng2 <= 180)) lng2 = lng2 - 360;
            while (!(lng2 > -180)) lng2 = lng2 + 360;
            return new double[] { lat2, lng2 };
        }

        Vec3[] EastNorth(Vec3 rv)
        {
            Vec3 upv = Nrm(rv);
            Vec3 eastv = OmegaCross(rv);
            if (eastv.Mag < 0.001) return new Vec3[] { Vec3.Zero, Vec3.Zero };
            eastv = Nrm(eastv);
            return new Vec3[] { eastv, Cross(upv, eastv) * C.EPR_NSIGN };
        }

        // ================================================================ lib_aoa.ks
        double FpaNom(double altM) { return C.AOA_FPA_SLOPE * altM + C.AOA_FPA_ICPT - C.AOA_FPA_MARGIN; }

        double[] PeriApo(Vec3 rv, Vec3 vv)
        {
            double a = 1 / (2 / rv.Mag - vv.SqrMag / C.EPR_MU);
            if (a <= 0) return null;
            double hh = Cross(rv, vv).SqrMag;
            double ecc = Math.Sqrt(Max(0, 1 - hh / (C.EPR_MU * a)));
            return new double[] { a * (1 - ecc), a * (1 + ecc) };
        }

        double FpaAt(Vec3 rv, Vec3 vv)
        {
            Vec3 vrelv = vv - OmegaCross(rv);
            double vvert = Dot(vrelv, Nrm(rv));
            return Atan2(vvert, Math.Sqrt(Max(vrelv.SqrMag - vvert * vvert, 0)));
        }

        double KepFpa(Vec3 rv, Vec3 vv)
        {
            double rEi = C.EPR_R + C.EPR_ATM;
            Vec3 hv = Cross(rv, vv);
            double p = hv.SqrMag / C.EPR_MU;
            Vec3 ev = Cross(vv, hv) * (1 / C.EPR_MU) - Nrm(rv);
            double ecc = ev.Mag;
            if (ecc < 0.000000001) return 999;
            if (p / (1 + ecc) >= rEi) return 999;
            if (ecc < 1) { if (p / (1 - ecc) <= rEi) return 999; }
            double cnu = Max(-1, Min(1, (p / rEi - 1) / ecc));
            double snu = -Math.Sqrt(1 - cnu * cnu);
            Vec3 pv = ev * (1 / ecc);
            Vec3 qv = Nrm(Cross(hv, pv));
            return FpaAt((pv * cnu + qv * snu) * rEi, (qv * (ecc + cnu) - pv * snu) * Math.Sqrt(C.EPR_MU / p));
        }

        double DvtForFpa(Vec3 rv, Vec3 vv, double gam)
        {
            double lo = -400;
            double hi = 400;
            Vec3 u = Nrm(vv);
            if (KepFpa(rv, vv + u * lo) > gam) return 9999;
            for (int k = 0; k < 16; k++)
            {
                double mid = 0.5 * (lo + hi);
                if (KepFpa(rv, vv + u * mid) > gam) hi = mid; else lo = mid;
            }
            return lo;
        }

        AoaSt Step(Vec3 rv, Vec3 vv, double h)
        {
            if (C.EPR_J2_ON) return J2Step(rv, vv, h);
            return KepState(rv, vv, h);
        }

        public List<AoaSt> Ephem(Vec3 rv, Vec3 vv, double n)
        {
            var eph = new List<AoaSt> { new AoaSt(rv, vv, 0) };
            double rEi = C.EPR_R + C.EPR_ATM;
            for (int k = 0; !(k >= n); k++)
            {
                AoaSt st = Step(rv, vv, C.AOA_DT);
                if (st.r.Mag <= rEi) break;
                rv = st.r;
                vv = st.v;
                eph.Add(st);
            }
            return eph;
        }

        AoaSt StateAt(List<AoaSt> eph, double t)
        {
            double k = Min(Math.Floor(t / C.AOA_DT), eph.Count - 1);
            double dt = t - k * C.AOA_DT;
            if (dt <= 0) return eph[(int)k];
            return Step(eph[(int)k].r, eph[(int)k].v, dt);
        }

        static double Mod(double a, double b) { return a % b; }

        double Bearing(double lat1, double lng1, double lat2, double lng2)
        {
            double dl = lng2 - lng1;
            return Mod(Atan2(Sin(dl) * Cos(lat2), Cos(lat1) * Sin(lat2) - Sin(lat1) * Cos(lat2) * Cos(dl)) + 360, 360);
        }

        double AzErr(Vec3 rv, Vec3 vv, double tRot, double tgtLat, double tgtLng)
        {
            Vec3 vrelv = vv - OmegaCross(rv);
            Vec3 upv = Nrm(rv);
            Vec3 hz = vrelv - upv * Dot(vrelv, upv);
            if (hz.Mag < 1) return 0;
            Vec3 eq = rv - C.EPR_WAXIS * Dot(rv, C.EPR_WAXIS);
            if (eq.Mag < 1) return 0;
            Vec3[] en = EastNorth(rv);
            if (en[0].Mag < 0.5) return 0;
            double[] g = ToGeoRaw(rv, tRot);
            double hdg = Atan2(Dot(hz, en[0]), Dot(hz, en[1]));
            double dl = tgtLng - g[1];
            double brg = Atan2(Sin(dl) * Cos(tgtLat), Cos(g[0]) * Sin(tgtLat) - Sin(g[0]) * Cos(tgtLat) * Cos(dl));
            double e = hdg - brg;
            while (!(e <= 180)) e = e - 360;
            while (!(e > -180)) e = e + 360;
            return e;
        }

        double HpJ2(Vec3 rv, Vec3 vv)
        {
            double r0 = rv.Mag;
            AoaSt st = Step(rv, vv, C.AOA_DT);
            double r1 = st.r.Mag;
            if (r1 >= r0) return r0 - C.EPR_R;
            for (int k = 1; !(k >= C.AOA_HPJ2_KMAX); k++)
            {
                st = Step(st.r, st.v, C.AOA_DT);
                double r2 = st.r.Mag;
                if (r2 >= r1)
                {
                    double den = r0 - 2 * r1 + r2;
                    if (den <= 0) return r1 - C.EPR_R;
                    return r1 - Math.Pow(r2 - r0, 2) / (8 * den) - C.EPR_R;
                }
                r0 = r1;
                r1 = r2;
            }
            return r1 - C.EPR_R;
        }

        // LIST(the middle, the skim, h_pJ2, v_rel) or null
        double[] Dmid(Vec3 rv, Vec3 vv)
        {
            double[] pa = PeriApo(rv, vv);
            if (pa == null) return null;
            double haKm = (pa[1] - C.EPR_R) / 1000;
            double vrel = (vv - OmegaCross(rv)).Mag;
            double[] bx = C.AOA_SUR_BOX;
            if (haKm < bx[2] || haKm > bx[3] || vrel < bx[4] || vrel > bx[5]) return null;
            double hpj = HpJ2(rv, vv);
            double hpKm = hpj / 1000;
            if (hpKm < bx[0] || hpKm > bx[1]) return null;
            double x = hpKm - C.AOA_SUR_HP0;
            double y = (haKm - C.AOA_SUR_HA0) / C.AOA_SUR_HAS;
            double z = (vrel - C.AOA_SUR_V0) / C.AOA_SUR_VS;
            double[] c = C.AOA_SUR_C;
            double[] d = C.AOA_SUR_D;
            double arc = Math.Pow(C.CE, c[0] + x * (c[1] + x * (c[2] + x * c[3])) + y * (c[4] + x * (c[5] + x * c[6]) + y * c[7])
                                        + z * (c[8] + x * c[9] + y * c[10]));
            if (arc > C.AOA_ARC_MAX) return null;
            return new double[] { 1000 * (arc + d[0] + x * (d[1] + x * d[3]) + y * d[2] + z * (d[4] + x * d[5] + y * d[6])), 1000 * arc, hpj,
                                  vrel };
        }

        AoaX Eval(AoaSt ei, double t, double dvt, double tGeo, double[] s, bool rmp)
        {
            if (ei.t <= 0) return null;
            double[] pa = PeriApo(ei.r, ei.v);
            if (pa == null) return null;
            double[] dmv = Dmid(ei.r, ei.v);
            if (dmv == null) return null;
            int m = rmp ? 1 : 0;
            double dm = dmv[0];
            if (rmp) dm = dm + 1000 * (C.AOA_RAMP_G0 + C.AOA_RAMP_G1 * (dmv[3] - C.AOA_SUR_V0) / C.AOA_SUR_VS
                                       + C.AOA_RAMP_G2 * (dmv[2] / 1000 - C.AOA_SUR_HP0));   // + the h_pJ2 term
            double tRot = tGeo + t + ei.t;
            double[] geo = ToGeoRaw(ei.r, tRot);
            double[] aim = DestGeo(s[0], s[1], Bearing(s[0], s[1], geo[0], geo[1]), C.AOA_FTP_M);
            double dAim = GcDist(geo[0], geo[1], aim[0], aim[1]);
            double dSite = GcDist(geo[0], geo[1], s[0], s[1]);
            double az = AzErr(ei.r, ei.v, tRot, s[0], s[1]);
            double xt = C.EPR_R * Asin(Max(-1, Min(1, Sin(dSite / C.EPR_R * C.RADTODEG) * Sin(az)))) * C.DEGTORAD;
            double azA = AzErr(ei.r, ei.v, tRot, aim[0], aim[1]);
            double xp = -C.EPR_R * Asin(Max(-1, Min(1, Sin(dAim / C.EPR_R * C.RADTODEG) * Sin(azA)))) * C.DEGTORAD;
            double tA = tRot + C.AOA_XT_T0[m] + C.AOA_XT_T1[m] * (dm / 1000 - 3500);
            Vec3 fw = Nrm(Cross(Cross(ei.r, ei.v), ei.r));
            double[] g1 = ToGeoRaw(ei.r, tA);
            double[] g2 = ToGeoRaw(ei.r * Cos(10) + fw * (ei.r.Mag * Sin(10)), tA);
            double rel = Bearing(g1[0], g1[1], aim[0], aim[1]) - Bearing(g1[0], g1[1], g2[0], g2[1]);
            double dA1 = GcDist(g1[0], g1[1], aim[0], aim[1]);
            double xa = C.EPR_R * Asin(Max(-1, Min(1, Sin(dA1 / C.EPR_R * C.RADTODEG) * Sin(rel)))) * C.DEGTORAD;
            double xm = (1 - C.AOA_XT_EPS[m]) * xa + C.AOA_XT_EPS[m] * xp;
            var x = new AoaX();
            x.t = t; x.dvt = dvt; x.tc = ei.t; x.f = dAim - dm; x.az = az; x.xt = xt; x.dAim = dAim; x.dmid = dm;
            x.lat = geo[0]; x.lng = geo[1]; x.aimLat = aim[0]; x.aimLng = aim[1]; x.hp = pa[0] - C.EPR_R;
            x.ha = pa[1] - C.EPR_R; x.fpa = FpaAt(ei.r, ei.v); x.xp = xp; x.xa = xa; x.xm = xm;
            x.xo = Math.Abs(xm - C.AOA_XT_C[m]); x.ramp = rmp; x.arc = dmv[1]; x.hpj2 = dmv[2]; x.vrel = dmv[3];
            return x;
        }

        // LIST(dvt, ei) or null (dvt is returned in bd)
        bool BurnEI(AoaSt st, double gam, out double dvt, out AoaSt ei)
        {
            dvt = DvtForFpa(st.r, st.v, gam);
            ei = default(AoaSt);
            if (dvt == 9999) return false;
            ei = KepToEI(st.r, st.v + Nrm(st.v) * dvt);
            if (ei.t > 0)
            {
                double miss = FpaAt(ei.r, ei.v) - gam;
                if (Math.Abs(miss) > C.AOA_FPA_TOL)
                {
                    double dvt2 = DvtForFpa(st.r, st.v, gam - miss);
                    if (dvt2 != 9999)
                    {
                        dvt = dvt2;
                        ei = KepToEI(st.r, st.v + Nrm(st.v) * dvt);
                    }
                }
            }
            return true;
        }

        AoaX AtIg(List<AoaSt> eph, double t, double tGeo, double[] s, double gam, bool rmp)
        {
            Interlocked.Increment(ref nEval);
            double dvt; AoaSt ei;
            if (!BurnEI(StateAt(eph, t), gam, out dvt, out ei)) return null;
            AoaX x = Eval(ei, t, dvt, tGeo, s, rmp);
            if (x == null) return null;
            if (Math.Abs(x.az) >= 90) return null;
            return x;
        }

        AoaX Bisect(List<AoaSt> eph, double tGeo, double[] s, double gam, double ta, AoaX xa, double tb, AoaX xb, bool rmp)
        {
            for (int i = 0; i < 11; i++)
            {
                double mid = 0.5 * (ta + tb);
                AoaX x = AtIg(eph, mid, tGeo, s, gam, rmp);
                if (x == null) break;
                if ((x.f > 0) == (xa.f > 0))
                {
                    ta = mid;
                    xa = x;
                }
                else
                {
                    tb = mid;
                    xb = x;
                }
            }
            if (Math.Abs(xa.f) <= Math.Abs(xb.f)) return xa;
            return xb;
        }

        // the grid every AOA_DT s: its points (in parallel), its brackets' bisections (in parallel), then kOS's scan in order
        AoaX SolveIg(List<AoaSt> eph, double tGeo, double[] s, double gam, double dvMax, double tHi, bool rmp)
        {
            int m = rmp ? 1 : 0;
            double k1 = Min(Math.Floor(tHi / C.AOA_DT), eph.Count - 1);
            double k0 = Math.Ceiling(C.AOA_T_LEAD / C.AOA_DT);
            int n = k1 >= k0 ? (int)(k1 - k0) + 1 : 0;
            var xs = new AoaX[n];
            P.For(n, i => { xs[i] = AtIg(eph, (k0 + i) * C.AOA_DT, tGeo, s, gam, rmp); });
            var bis = new AoaX[n];
            var br = new List<int>();
            for (int i = 1; i < n; i++)
                if (xs[i - 1] != null && xs[i] != null && xs[i - 1].f * xs[i].f <= 0) br.Add(i);
            P.For(br.Count, j =>
            {
                int i = br[j];
                bis[i] = Bisect(eph, tGeo, s, gam, (k0 + i - 1) * C.AOA_DT, xs[i - 1], (k0 + i) * C.AOA_DT, xs[i], rmp);
            });
            AoaX best = null;
            AoaX xNear = null;
            AoaX xa = null;
            for (int i = 0; i < n; i++)
            {
                AoaX xb = xs[i];
                if (xb != null)
                {
                    if (Math.Abs(xb.f) <= C.AOA_F_OFF && Math.Abs(xb.dvt) <= dvMax)
                    {
                        if (xb.xo > C.AOA_XT_MAX[m]) xtOnly = xtOnly + 1;
                        else if (xNear == null) xNear = xb;
                        else if (Math.Abs(xb.f) < Math.Abs(xNear.f)) xNear = xb;
                    }
                }
                if (xa != null && xb != null)
                {
                    if (xa.f * xb.f <= 0)
                    {
                        AoaX x = bis[i];
                        if (Math.Abs(x.f) < C.AOA_F_TOL && Math.Abs(x.dvt) <= dvMax)
                        {
                            if (x.xo > C.AOA_XT_MAX[m]) xtOnly = xtOnly + 1;
                            else if (best == null) best = x;
                            else if (Math.Abs(x.dvt) < Math.Abs(best.dvt)) best = x;
                        }
                    }
                }
                xa = xb;
            }
            if (best == null) return xNear;
            return best;
        }

        // ---- the radial fallback
        Vec3 RadialOut(Vec3 rv, Vec3 vv)
        {
            Vec3 u = Nrm(vv);
            return Nrm(rv - u * Dot(rv, u));
        }

        double DvtForFpaR(Vec3 rv, Vec3 vv, double gam, double dvr)
        {
            double lo = -400;
            double hi = 400;
            Vec3 u = Nrm(vv);
            Vec3 w = vv + RadialOut(rv, vv) * dvr;
            if (KepFpa(rv, w + u * lo) > gam) return 9999;
            for (int k = 0; k < 16; k++)
            {
                double mid = 0.5 * (lo + hi);
                if (KepFpa(rv, w + u * mid) > gam) hi = mid; else lo = mid;
            }
            return lo;
        }

        bool BurnEIR(AoaSt st, double gam, double dvr, out double dvt, out AoaSt ei)
        {
            Vec3 u = Nrm(st.v);
            Vec3 w = st.v + RadialOut(st.r, st.v) * dvr;
            dvt = DvtForFpaR(st.r, st.v, gam, dvr);
            ei = default(AoaSt);
            if (dvt == 9999) return false;
            ei = KepToEI(st.r, w + u * dvt);
            if (ei.t > 0)
            {
                double miss = FpaAt(ei.r, ei.v) - gam;
                if (Math.Abs(miss) > C.AOA_FPA_TOL)
                {
                    double dvt2 = DvtForFpaR(st.r, st.v, gam - miss, dvr);
                    if (dvt2 != 9999)
                    {
                        dvt = dvt2;
                        ei = KepToEI(st.r, w + u * dvt);
                    }
                }
            }
            return true;
        }

        AoaX AtIgR(List<AoaSt> eph, double t, double tGeo, double[] s, double gam, double dvr, bool rmp)
        {
            Interlocked.Increment(ref nEvalR);
            double dvt; AoaSt ei;
            if (!BurnEIR(StateAt(eph, t), gam, dvr, out dvt, out ei)) return null;
            AoaX x = Eval(ei, t, dvt, tGeo, s, rmp);
            if (x == null) return null;
            if (Math.Abs(x.az) >= 90) return null;
            x.hasR = true;
            x.dvr = dvr;
            x.dv = Math.Sqrt(Math.Pow(dvt, 2) + Math.Pow(dvr, 2));
            return x;
        }

        AoaX RadialAt(List<AoaSt> eph, double t, double tGeo, double[] s, double gam, bool rmp)
        {
            AoaX x0 = AtIgR(eph, t, tGeo, s, gam, 0, rmp);
            if (x0 == null) return null;
            double d0 = 0;
            double f0 = x0.f;
            double d1 = f0 > 0 ? C.AOA_DVR_STEP : -C.AOA_DVR_STEP;
            AoaX x1 = AtIgR(eph, t, tGeo, s, gam, d1, rmp);
            if (x1 == null) return x0;
            AoaX best = Math.Abs(x1.f) < Math.Abs(f0) ? x1 : x0;
            for (int i = 0; !(i >= C.AOA_DVR_ITERS); i++)
            {
                double f1 = x1.f;
                if (Math.Abs(f1) < C.AOA_DVR_FTOL || f1 == f0) break;
                double d2 = Max(-C.AOA_DVR_MAX, Min(C.AOA_DVR_MAX, d1 - f1 * (d1 - d0) / (f1 - f0)));
                AoaX x2 = AtIgR(eph, t, tGeo, s, gam, d2, rmp);
                if (x2 == null) break;
                d0 = d1;
                f0 = f1;
                d1 = d2;
                x1 = x2;
                if (Math.Abs(x2.f) < Math.Abs(best.f)) best = x2;
            }
            return best;
        }

        AoaX SolveRadial(List<AoaSt> eph, double tGeo, double[] s, double gam, double dvMax, double tHi, bool rmp)
        {
            int m = rmp ? 1 : 0;
            double k1 = Min(Math.Floor(tHi / C.AOA_DT), eph.Count - 1);
            double k0 = Math.Ceiling((C.AOA_T_LEAD + spent) / C.AOA_DT);
            int n = k1 >= k0 ? (int)(k1 - k0) + 1 : 0;
            var xs = new AoaX[n];
            P.For(n, i => { xs[i] = RadialAt(eph, (k0 + i) * C.AOA_DT, tGeo, s, gam, rmp); });
            var cands = new List<AoaX>();
            for (int i = 0; i < n; i++)
            {
                AoaX x = xs[i];
                if (x != null)
                {
                    if (Math.Abs(x.f) < C.AOA_F_TOL && x.dv <= dvMax)
                    {
                        if (x.xo > C.AOA_XT_MAX[m]) xtOnly = xtOnly + 1;
                        else cands.Add(x);
                    }
                }
            }
            double tMin = C.AOA_T_LEAD + spent;
            AoaX best = null;
            foreach (AoaX xc in cands)
            {
                if (xc.t >= tMin)
                {
                    if (best == null) best = xc;
                    else if (xc.dv < best.dv) best = xc;
                }
            }
            return best;
        }

        // ================================================================ THE SOLVE (aoaSolve)
        public AoaRes Solve(AoaIn inp)
        {
            var res = new AoaRes();
            spent = inp.spent;
            Vec3 rv = inp.rv, vv = inp.vv;
            double tGeo = inp.tGeo, dvMax = inp.dvMax;
            double[] s = new double[] { inp.slat, inp.slng };
            try
            {
                double[] pa = PeriApo(rv, vv);
                if (pa == null)
                {
                    res.whyk = 1;                                  // AOA_WHY "NOT IN ORBIT"
                    return res;
                }
                double gam0 = C.AOA_FAC * FpaNom(pa[1] - C.EPR_R);
                res.gam0 = gam0;
                double tHi = C.AOA_T_MAX;
                if (pa[0] < C.EPR_R + C.EPR_ATM)
                {
                    AoaSt nat = KepToEI(rv, vv);
                    if (nat.t >= 0) tHi = nat.t - C.AOA_T_HI_PAD;
                }
                res.tHi = tHi;
                if (tHi < C.AOA_T_LEAD + C.AOA_DT)
                {
                    res.whyk = 2;                                  // AOA_WHY "EI IN .. S: NO TIME FOR OMS-2"
                    return res;
                }
                List<AoaSt> eph = Ephem(rv, vv, Math.Ceiling(tHi / C.AOA_DT));
                xtOnly = 0;
                foreach (bool rmp in new bool[] { false, true })
                {
                    if (!rmp || xtOnly > 0)
                    {
                        for (int k = 0; !(k > C.AOA_FPA_KMAX); k++)
                        {
                            double gam = gam0 - C.AOA_FPA_STEP * k;
                            AoaX x = SolveIg(eph, tGeo, s, gam, dvMax, tHi, rmp);
                            if (x != null)
                            {
                                x.hasFpa = true; x.fpaTarget = gam0; x.fpaUsed = gam;
                                res.x = x; res.xtOnly = xtOnly;
                                return res;
                            }
                        }
                    }
                }
                if (inp.radial)
                {
                    int xtTan = xtOnly;
                    xtOnly = 0;
                    foreach (bool rmpR in new bool[] { false, true })
                    {
                        if (!rmpR || xtOnly > 0)
                        {
                            AoaX xr = SolveRadial(eph, tGeo, s, gam0, dvMax, tHi, rmpR);
                            if (xr != null)
                            {
                                xr.hasFpa = true; xr.fpaTarget = gam0; xr.fpaUsed = gam0;
                                res.x = xr; res.xtOnly = xtOnly;
                                return res;
                            }
                        }
                    }
                    xtOnly = xtOnly + xtTan;
                }
                res.whyk = 3;                                      // AOA_WHY "NO OMS-2 WITHIN .."
                res.xtOnly = xtOnly;
                return res;
            }
            finally
            {
                res.evals = nEval;
                res.evalsR = nEvalR;
            }
        }
    }

    // one solve: the input checked on the caller's thread, the solve on the worker threads
    public class AoaJob
    {
        public readonly AoaIn inp;
        public int threads;
        public AoaRes res;

        public AoaJob(AoaIn i)
        {
            inp = i;
            if (inp.c == null) throw new ArgumentException("no constants");
            foreach (double d in new double[] { inp.rv.X, inp.rv.Y, inp.rv.Z, inp.vv.X, inp.vv.Y, inp.vv.Z, inp.tGeo, inp.slat, inp.slng,
                                                inp.dvMax, inp.spent })
                if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("an input is not finite");
            threads = Math.Max(1, Math.Min(4, Environment.ProcessorCount - 1));
            if (inp.threads >= 1) threads = Math.Min(16, inp.threads);
        }

        public static volatile bool TestFail;        // the offline checks only: the solve's thread throws (the fallback test)

        public void Run()
        {
            if (TestFail) throw new InvalidOperationException("test failure on the solve's thread");
            var sw = System.Diagnostics.Stopwatch.StartNew();
            using (var pool = new AoaPool(threads))
            {
                res = new Aoa(inp.c, pool).Solve(inp);
            }
            res.ms = sw.Elapsed.TotalMilliseconds;
            res.threads = threads;
        }
    }
}
