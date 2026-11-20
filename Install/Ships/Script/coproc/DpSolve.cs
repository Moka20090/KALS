// deorbit_plan.ks's burn solve (dpSolveBurn and everything under it: dpGeoErr, dpDvForFpa, dpFpaForDv, dpFpa,
// dpInterface / dpInterfaceKep, dpStateAt / dpStateAtKep / dpFgAt, dpMissAt, dpCoarseAt / dpCoarseDent, dpBackset,
// dpTraceRow, dpIntStart / dpIntEnd; lib_kepler's kepElements / kepEphAt) and the plan check's entry prediction (dpArcAt),
// line for line, kOS semantics (DpCore.cs). What kOS does around the math stays in kOS and is REPLAYED from what this job
// records: the page's calls (progPlanVals / progPlanStep: "ev"), the trace file's writes (dpWriteTrace: "wr", the rows'
// numbers: "rows"; the texts are built in kOS from the numbers), the globals (DpG: "g").
// THREADS: the scan of step 2 (every probe of one pass is independent: dpGeoErr touches only the gate counters, which are
// summed in kOS's order afterwards; the J2 ephemeris is extended over the whole window before the probes start) runs on up to
// N worker threads (below-normal priority); step 1, the bisection and the entries are sequential, as in kOS.
using System;
using System.Collections.Generic;
using System.Threading;

namespace KalsCoproc
{
    // the parking orbit's elements (kepElements' lexicon: the fields the solve reads)
    public class DpEl
    {
        public double sma, ecc, n, ea0R, rm0, period;
        public Vec3 r0, v0;
        public DpEph eph;
        public DpEl() { }
        public DpEl(KLex k)
        {
            sma = k.D("sma"); ecc = k.D("ecc"); n = k.D("n"); ea0R = k.D("ea0R"); rm0 = k.D("rm0"); period = k.D("period");
            r0 = k.V("r0"); v0 = k.V("v0");
        }
    }

    public class DpSolver
    {
        public readonly DpC C;
        public readonly DpG G;
        public readonly DpEntry E;
        public int Threads = 1;
        // what kOS replays
        public readonly List<object> Ev = new List<object>();      // LIST("v", dv) | LIST("s", n, missKm)
        public readonly List<object> Rows = new List<object>();    // the trace rows' numbers
        public readonly List<object> Wr = new List<object>();      // the trace file's writes
        public long Probes;                                        // dpGeoErr calls (for the timing table)

        public DpSolver(DpC c, DpG g) { C = c; G = g; E = new DpEntry(c, g); }

        // ---- lib_kepler kepElements (null = 0)
        public DpEl KepElements(Vec3 rv, Vec3 vv)
        {
            double rm = rv.Mag;
            double vm = vv.Mag;
            if (rm < 1 || vm < 0.000001) return null;
            Vec3 h = Vec3.Cross(rv, vv);
            if (h.Mag < 0.000001) return null;
            double energy = 0.5 * vm * vm - C.EPR_MU / rm;
            if (energy >= 0) return null;
            double sma = 0 - C.EPR_MU / (2 * energy);
            double ecc = Math.Sqrt(Math.Max(0, 1 - h.Mag * h.Mag / (C.EPR_MU * sma)));
            double caD = (1 - rm / sma) / Math.Max(ecc, 0.000000000001);
            double eaR = DpM.Acos(Math.Max(-1, Math.Min(1, caD))) * C.C_DEGTORAD;
            if (Vec3.Dot(rv, vv) < 0) eaR = 0 - eaR;
            var el = new DpEl();
            el.sma = sma; el.ecc = ecc;
            el.n = Math.Sqrt(C.EPR_MU / Math.Pow(sma, 3));
            el.ea0R = eaR; el.r0 = rv; el.v0 = vv; el.rm0 = rm;
            el.period = 2 * C.C_PI * Math.Sqrt(Math.Pow(sma, 3) / C.EPR_MU);
            return el;
        }

        // ---- the state on the parking orbit
        bool StateAt(DpEl el, double t, out Vec3 r, out Vec3 v)
        {
            if (C.EPR_J2_ON && t >= 0) { el.eph.At(t, out r, out v); return true; }
            return StateAtKep(el, t, out r, out v);
        }

        bool StateAtKep(DpEl el, double t, out Vec3 r, out Vec3 v)
        {
            double ecc = el.ecc;
            double m0R = el.ea0R - ecc * DpM.Sin(el.ea0R * C.C_RADTODEG);
            double mR = m0R + el.n * t;
            double eaR = mR;
            if (ecc >= 0.8) eaR = C.C_PI;
            int i = 0;
            while (!(i >= 30))
            {
                i = i + 1;
                double eaD = eaR * C.C_RADTODEG;
                double f = eaR - ecc * DpM.Sin(eaD) - mR;
                double fp = 1 - ecc * DpM.Cos(eaD);
                if (Math.Abs(fp) < 0.00000000000001) break;
                double d = f / fp;
                eaR = eaR - d;
                if (Math.Abs(d) < 0.0000000000001) break;
            }
            FgAt(el, eaR, t, out r, out v);
            return true;
        }

        void FgAt(DpEl el, double eaR, double t, out Vec3 r, out Vec3 v)
        {
            double sma = el.sma;
            double deaR = eaR - el.ea0R;
            double deaD = deaR * C.C_RADTODEG;
            double ff = 1 - sma / el.rm0 * (1 - DpM.Cos(deaD));
            double gg = t + (DpM.Sin(deaD) - deaR) / el.n;
            Vec3 rv = el.r0 * ff + el.v0 * gg;
            double rm = rv.Mag;
            double fd = 0 - Math.Sqrt(C.EPR_MU * sma) / (el.rm0 * rm) * DpM.Sin(deaD);
            double gd = 1 - sma / rm * (1 - DpM.Cos(deaD));
            r = rv;
            v = el.r0 * fd + el.v0 * gd;
        }

        // ---- the interface: LIST(r, v, t) or 0 (false)
        bool Interface(Vec3 rv, Vec3 vv, out Vec3 ro, out Vec3 vo, out double to)
        {
            if (C.EPR_J2_ON)
            {
                if (!InterfaceKep(rv, vv, out ro, out vo, out to)) return false;
                E.J2ToEI(rv, vv, out ro, out vo, out to);
                if (to < 0) return false;
                return true;
            }
            return InterfaceKep(rv, vv, out ro, out vo, out to);
        }

        bool InterfaceKep(Vec3 rv, Vec3 vv, out Vec3 ro, out Vec3 vo, out double to)
        {
            ro = Vec3.Zero; vo = Vec3.Zero; to = 0;
            DpEl el = KepElements(rv, vv);
            if (el == null) return false;
            double sma = el.sma;
            double ecc = el.ecc;
            double rEi = C.EPR_R + C.EPR_ATM;
            if (sma * (1 - ecc) > rEi) return false;
            if (sma * (1 + ecc) < rEi) return false;
            double ce = (1 - rEi / sma) / Math.Max(ecc, 0.000000000001);
            double eaiR = DpM.Acos(Math.Max(-1, Math.Min(1, ce))) * C.C_DEGTORAD;
            double m0R = el.ea0R - ecc * DpM.Sin(el.ea0R * C.C_RADTODEG);
            double period = el.period;
            double bestT = -1;
            double bestE = 0;
            for (int s = 0; s < 2; s++)
            {
                double sgn = s == 0 ? -1 : 1;
                double candR = sgn * eaiR;
                double miR = candR - ecc * DpM.Sin(candR * C.C_RADTODEG);
                double dt = (miR - m0R) / el.n;
                while (!(dt >= 0)) dt = dt + period;
                if (bestT < 0 || dt < bestT)
                {
                    bestT = dt;
                    bestE = candR;
                }
            }
            if (bestT < 0) return false;
            StateAtKep(el, bestT, out ro, out vo);
            to = bestT;
            return true;
        }

        double Fpa(Vec3 rv, Vec3 vv)
        {
            Vec3 vrelv = vv - E.OmegaCross(rv);
            if (vrelv.Mag < 1) return 0;
            Vec3 upv = DpM.Nrm(rv);
            double vvert = Vec3.Dot(vrelv, upv);
            double vhoriz = Math.Sqrt(Math.Max(vrelv.Mag * vrelv.Mag - vvert * vvert, 0));
            return DpM.Atan2(vvert, vhoriz);
        }

        double FpaForDv(Vec3 rb, Vec3 vb, double dv)
        {
            Vec3 vv = vb - DpM.Nrm(vb) * dv;
            Vec3 r, v; double t;
            if (!InterfaceKep(rb, vv, out r, out v, out t)) return 999;
            return Fpa(r, v);
        }

        double DvForFpa(Vec3 rb, Vec3 vb, double fpaTarget)
        {
            double lo = 20;
            double hi = 400;
            double fLo = FpaForDv(rb, vb, lo);
            double loBad = -1;
            int tries = 0;
            while (!(!(fLo == 999) || lo >= hi || tries >= 60))
            {
                loBad = lo;
                lo = lo + 5;
                fLo = FpaForDv(rb, vb, lo);
                tries = tries + 1;
            }
            if (fLo == 999) return 0;
            if (loBad > 0)
            {
                double a = loBad;
                double b = lo;
                int i = 0;
                while (!(i >= 24))
                {
                    i = i + 1;
                    double m = 0.5 * (a + b);
                    if (FpaForDv(rb, vb, m) == 999) a = m; else b = m;
                }
                lo = b;
                fLo = FpaForDv(rb, vb, lo);
                if (fLo == 999) return 0;
            }
            double fHi = FpaForDv(rb, vb, hi);
            if (fHi == 999) return 0;
            if (!(fHi <= fpaTarget && fpaTarget <= fLo)) return 0;
            int j = 0;
            while (!(j >= 60))
            {
                j = j + 1;
                double mid = 0.5 * (lo + hi);
                double fm = FpaForDv(rb, vb, mid);
                if (fm == 999) return 0;
                if (Math.Abs(fm - fpaTarget) <= C.DP_FPA_TOL) return mid;
                if (fm > fpaTarget) lo = mid; else hi = mid;
            }
            return 0.5 * (lo + hi);
        }

        // ---- dpIntStart / dpIntEnd
        void IntStart(Vec3 rei, Vec3 vei, double tRot, double bank, double aimLat, double aimLng)
        {
            G.EPR_LAT_ON = C.EPR_PRED_LATERAL;
            E.IntStart(rei, vei, bank);
            if (G.EPR_LAT_ON)
            {
                G.DP_TGT_SAVE = new List<object> { G.EPR_TGT_LAT, G.EPR_TGT_LNG };
                G.EPR_TGT_LAT = aimLat;
                G.EPR_TGT_LNG = aimLng;
                G.EPR_LAT_TROT = tRot;
                G.EPR_LAT_SIGN = 0;
                G.EPR_LAT_REV = 0;
                G.EPR_LAT_CMD = 0;
                G.EPR_LAT_RATE = 0;
            }
        }

        void IntEnd()
        {
            if (G.EPR_LAT_ON)
            {
                var s = (List<object>)G.DP_TGT_SAVE;
                G.EPR_TGT_LAT = KLex.Num(s[0], "DP_TGT_SAVE");
                G.EPR_TGT_LNG = KLex.Num(s[1], "DP_TGT_SAVE");
            }
            G.EPR_LAT_ON = false;
        }

        void IntRunGuarded()
        {
            int guard = 0;
            while (!(E.IntRun(C.DP_INT_BUDGET) || guard > 40)) guard = guard + 1;
        }

        static KLex Last(double tBurn, double dv, Vec3 rei, Vec3 vei, double tRot, double miss, double tCoast)
        {
            var l = new KLex();
            l["tBurn"] = tBurn; l["dv"] = dv; l["rei"] = rei; l["vei"] = vei; l["tRot"] = tRot; l["miss"] = miss; l["tCoast"] = tCoast;
            return l;
        }

        // ---- one probe: dpMissAt / dpCoarseAt
        double MissAt(DpEl el, double tBurn, double aimLat, double aimLng)
        {
            Vec3 br, bv;
            StateAt(el, tBurn, out br, out bv);
            double dv = DvForFpa(br, bv, G.DP_FPA);
            Ev.Add(new List<object> { "v", dv });
            if (dv == 0) return 999999;
            Vec3 vAfter = bv - DpM.Nrm(bv) * dv;
            Vec3 gr, gv; double gt;
            if (!Interface(br, vAfter, out gr, out gv, out gt)) return 999999;
            double tRot = tBurn + gt;
            G.EPR_T0 = tRot;
            IntStart(gr, gv, tRot, C.DP_BANK, aimLat, aimLng);
            IntRunGuarded();
            IntEnd();
            if (!G.EPR_IOK)
            {
                G.EPR_T0 = 0;
                return 999999;
            }
            double miss = E.MissPath(gr, aimLat, aimLng);
            G.EPR_T0 = 0;
            G.DP_LAST = Last(tBurn, dv, gr, gv, tRot, miss, gt);
            return miss;
        }

        double CoarseDent(DpEl el)
        {
            double h = (el.sma - C.BODY_RADIUS) / 1000;
            var t = C.DP_COARSE_DENT;
            if (h <= t[0][0]) return t[0][1] * 1000;
            for (int i = 1; !(i >= t.Length); i = i + 1)
            {
                if (h <= t[i][0])
                    return (t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (h - t[i - 1][0]) / (t[i][0] - t[i - 1][0])) * 1000;
            }
            return t[t.Length - 1][1] * 1000;
        }

        double CoarseAt(DpEl el, double tBurn, double aimLat, double aimLng, double pathL)
        {
            Vec3 br, bv;
            StateAt(el, tBurn, out br, out bv);
            double dv = DvForFpa(br, bv, G.DP_FPA);
            Ev.Add(new List<object> { "v", dv });
            if (dv == 0) return 999999;
            Vec3 vAfter = bv - DpM.Nrm(bv) * dv;
            Vec3 gr, gv; double gt;
            if (!Interface(br, vAfter, out gr, out gv, out gt)) return 999999;
            double tRot = tBurn + gt;
            double[] g0 = E.ToGeo(gr, tRot);
            G.EPR_MP_LAT = g0[0];
            G.EPR_MP_LNG = g0[1];
            G.EPR_MP_TROT = tRot;
            G.EPR_MP_GC = E.GcDist(g0[0], g0[1], aimLat, aimLng);
            G.EPR_IARC = pathL;
            double miss = pathL - G.EPR_MP_GC;
            G.DP_LAST = Last(tBurn, dv, gr, gv, tRot, miss, gt);
            return miss;
        }

        // ---- dpGeoErr: the value, and which gate rejected it (0 none, 1 the leg, 2 the side); reads only the constants and
        // the state's DP_FPA / DP_BACK_M (thread safe once the ephemeris reaches tBurn)
        struct Geo { public double f; public int gate; }

        Geo GeoErrRaw(DpEl el, double tBurn, double aimLat, double aimLng, double pathL, double thrLat, double thrLng,
                      double tCross, double perS)
        {
            Geo r; r.gate = 0; r.f = 999999;
            Vec3 br, bv;
            StateAt(el, tBurn, out br, out bv);
            double dv = DvForFpa(br, bv, G.DP_FPA);
            if (dv == 0) return r;
            Vec3 vAfter = bv - DpM.Nrm(bv) * dv;
            Vec3 gr, gv; double gt;
            if (!Interface(br, vAfter, out gr, out gv, out gt)) return r;
            double tRot = tBurn + gt;
            if (tCross > 0 && !(tRot > tCross - C.DP_LEG_LO * perS && tRot <= tCross + C.DP_LEG_HI * perS))
            {
                r.gate = 1;
                return r;
            }
            double[] gp = E.ToGeo(gr, tRot);
            if (Math.Abs(Backset(gp, aimLat, aimLng, thrLat, thrLng) - G.DP_BACK_M) > C.DP_SIDE_TOL_M)
            {
                r.gate = 2;
                return r;
            }
            r.f = pathL - E.GcDist(gp[0], gp[1], aimLat, aimLng);
            return r;
        }

        double GeoErr(DpEl el, double tBurn, double aimLat, double aimLng, double pathL, double thrLat, double thrLng,
                      double tCross, double perS)
        {
            Probes++;
            Geo r = GeoErrRaw(el, tBurn, aimLat, aimLng, pathL, thrLat, thrLng, tCross, perS);
            Count(r.gate);
            return r.f;
        }

        void Count(int gate)
        {
            if (gate == 1) G.DP_NGATE_LEG = G.DP_NGATE_LEG + 1;
            else if (gate == 2) G.DP_NGATE_SIDE = G.DP_NGATE_SIDE + 1;
        }

        double Backset(double[] gp, double aimLat, double aimLng, double thrLat, double thrLng)
        {
            return E.GcDist(gp[0], gp[1], thrLat, thrLng) - E.GcDist(gp[0], gp[1], aimLat, aimLng);
        }

        // dpTraceRow's numbers: LIST(st, tb, missKm, pathKm, LIST(the why's numbers), ei_lat, ei_lng, ei_trot, ei_gc_km,
        // term_lat, term_lng, backset_km)
        void Row(object st, object tb, object missKm, object pathKm, List<object> why, double thrLat, double thrLng)
        {
            Rows.Add(new List<object> { st, tb, missKm, pathKm, why,
                G.EPR_MP_LAT, G.EPR_MP_LNG, G.EPR_MP_TROT, G.EPR_MP_GC / 1000,
                G.EPR_SOL_LAT, G.EPR_SOL_LNG,
                (E.GcDist(G.EPR_MP_LAT, G.EPR_MP_LNG, thrLat, thrLng) - G.EPR_MP_GC) / 1000 });
        }

        // a dpWriteTrace: the rows so far, the why's code and numbers (the gate counters at the write)
        void Write(string code, params object[] p)
        {
            var l = new List<object> { Rows.Count, code, G.DP_NGATE_LEG, G.DP_NGATE_SIDE };
            l.AddRange(p);
            Wr.Add(l);
        }

        public double tMinOut, tMaxOut, periodOut;

        // ---- dpSolveBurn: the out lexicon or null (kOS's 0)
        public KLex SolveBurn(DpEl el, double aimLat, double aimLng, double tSeed, double thrLat, double thrLng)
        {
            G.DP_NGATE_LEG = 0;
            G.DP_NGATE_SIDE = 0;
            double period = el.period;
            double tMinD = C.DP_SCAN_STEP;
            double tMax = 1.5 * period;
            if (tSeed > 0)
            {
                tMinD = Math.Max(C.DP_SCAN_STEP, tSeed - 0.5 * period - 1500);
                tMax = tSeed;
            }
            tMinOut = tMinD; tMaxOut = tMax; periodOut = period;
            if (C.EPR_J2_ON) el.eph.Reach(tMax);    // the ephemeris over the whole window (the probes read it)

            // ---- STEP 1
            double tProbe = -1;
            double tp = tMinD;
            while (!(tp > tMax || tProbe > 0))
            {
                if (GeoErr(el, tp, aimLat, aimLng, 0, thrLat, thrLng, tSeed, period) < 999998) tProbe = tp;
                tp = tp + C.DP_GEO_STEP;
            }
            if (tProbe < 0) { Write("noprobe"); return null; }
            double m0 = 0;
            if (G.DP_COARSE_ON) m0 = CoarseAt(el, tProbe, aimLat, aimLng, CoarseDent(el));
            else m0 = MissAt(el, tProbe, aimLat, aimLng);
            if (m0 > 999998) { Write("probenone", tProbe); return null; }
            double pathL = G.EPR_IARC;
            Row(1, tProbe, m0 / 1000, pathL / 1000, new List<object>(), thrLat, thrLng);
            Ev.Add(new List<object> { "s", 1, m0 / 1000 });

            // ---- STEPS 2-4
            KLex outL = null;
            double mFinal = 0;
            double tSol = 0;
            int nInt = G.DP_COARSE_ON ? 0 : 1;
            int pIt = 0;
            while (!(pIt >= C.DP_PATH_ITERS))
            {
                pIt = pIt + 1;
                // STEP 2: the scan (the probes in parallel, the brackets in kOS's order)
                var ts = new List<double>();
                double t2 = tMinD;
                while (!(t2 > tMax)) { ts.Add(t2); t2 = t2 + C.DP_GEO_STEP; }
                Geo[] fv = Scan(el, ts, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period);
                var brackets = new List<double[]>();
                double prevT = -1;
                double prevF = 0;
                for (int q = 0; q < ts.Count; q++)
                {
                    Count(fv[q].gate);
                    double f = fv[q].f;
                    if (f > 999998) prevT = -1;
                    else
                    {
                        if (prevT >= 0 && prevF * f < 0) brackets.Add(new double[] { prevT, ts[q] });
                        prevT = ts[q]; prevF = f;
                    }
                }
                Row(2, 0, 0, brackets.Count, new List<object> { pIt, pathL, brackets.Count, G.DP_NGATE_LEG, G.DP_NGATE_SIDE }, thrLat, thrLng);
                Ev.Add(new List<object> { "s", 2, 0 });
                if (brackets.Count == 0)
                {
                    Write("nocross");
                    if (outL != null) break;
                    return null;
                }
                // STEP 3
                double[] chosen = brackets[brackets.Count - 1];
                int bi = 0;
                while (!(bi >= brackets.Count))
                {
                    if (brackets[bi][0] >= C.DP_MIN_LEAD_S) { chosen = brackets[bi]; break; }
                    bi = bi + 1;
                }
                double lo = chosen[0];
                double hi = chosen[1];
                double fLo = GeoErr(el, lo, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period);
                int bj = 0;
                while (!(bj >= 24))
                {
                    bj = bj + 1;
                    double mid = 0.5 * (lo + hi);
                    double fm = GeoErr(el, mid, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period);
                    if (fm > 999998) break;
                    if (fm * fLo > 0) { lo = mid; fLo = fm; } else hi = mid;
                }
                tSol = 0.5 * (lo + hi);
                Row(3, tSol, 0, 0, new List<object> { pIt }, thrLat, thrLng);
                Ev.Add(new List<object> { "s", 3, 0 });
                // STEP 4
                double mTry = 0;
                if (G.DP_COARSE_ON) mTry = CoarseAt(el, tSol, aimLat, aimLng, pathL);
                else mTry = MissAt(el, tSol, aimLat, aimLng);
                if (mTry > 999998)
                {
                    if (outL != null) break;
                    Write("verifynone");
                    return null;
                }
                mFinal = mTry;
                outL = Copy((KLex)G.DP_LAST);
                if (!G.DP_COARSE_ON) nInt = nInt + 1;
                Row(4, tSol, mFinal / 1000, G.EPR_IARC / 1000, new List<object> { pIt, G.EPR_IARC, pathL }, thrLat, thrLng);
                Ev.Add(new List<object> { "s", 4, mFinal / 1000 });
                if (Math.Abs(mFinal) <= C.DP_TOL_KM * 1000) break;
                if (Math.Abs(G.EPR_IARC - pathL) < 500) break;
                pathL = G.EPR_IARC;
            }
            if (outL == null) { Write("nosol", pIt); return null; }
            Write("residual", mFinal, pIt, nInt);
            outL["probes"] = nInt;
            outL["iters"] = pIt;
            outL["converged"] = Math.Abs(mFinal / 1000) <= C.DP_TOL_KM;
            outL["grad"] = 0;
            double[] gEi = E.ToGeo(outL.V("rei"), outL.D("tRot"));
            double bkM = Backset(gEi, aimLat, aimLng, thrLat, thrLng);
            outL["backsetKm"] = bkM / 1000;
            outL["sideOk"] = Math.Abs(bkM - G.DP_BACK_M) <= C.DP_SIDE_TOL_M;
            return outL;
        }

        static KLex Copy(KLex a)
        {
            var b = new KLex();
            foreach (var k in a.Keys) b[k] = a[k];
            return b;
        }

        // the probes of one scan, on up to Threads workers (each probe only reads el, the constants and DP_FPA / DP_BACK_M)
        Geo[] Scan(DpEl el, List<double> ts, double aimLat, double aimLng, double pathL, double thrLat, double thrLng,
                   double tCross, double perS)
        {
            var res = new Geo[ts.Count];
            Probes += ts.Count;
            int nt = Math.Max(1, Math.Min(Threads, ts.Count / 8));
            if (nt <= 1)
            {
                for (int q = 0; q < ts.Count; q++) res[q] = GeoErrRaw(el, ts[q], aimLat, aimLng, pathL, thrLat, thrLng, tCross, perS);
                return res;
            }
            int next = -1;
            Exception err = null;
            var th = new Thread[nt];
            for (int w = 0; w < nt; w++)
            {
                th[w] = new Thread(() =>
                {
                    try
                    {
                        while (true)
                        {
                            int q = Interlocked.Increment(ref next);
                            if (q >= ts.Count) return;
                            res[q] = GeoErrRaw(el, ts[q], aimLat, aimLng, pathL, thrLat, thrLng, tCross, perS);
                        }
                    }
                    catch (Exception ex) { lock (res) { if (err == null) err = ex; } }
                });
                th[w].IsBackground = true;
                th[w].Priority = ThreadPriority.BelowNormal;
                th[w].Start();
            }
            foreach (var t in th) t.Join();
            if (err != null) throw new Exception("scan worker: " + err.Message, err);
            return res;
        }

        // ---- dpArcAt (the plan check's prediction): the arc, or -1
        public double ArcAt(Vec3 rei, Vec3 vei, double tRot, double bank, double aimLat, double aimLng)
        {
            IntStart(rei, vei, tRot, bank, aimLat, aimLng);
            IntRunGuarded();
            IntEnd();
            if (!G.EPR_IOK) return -1;
            return G.EPR_IARC;
        }
    }

    // ONE JOB (DPSOLVE or DPARC): the input copied on the main thread (KLex), run on a worker thread
    public class DpJob
    {
        public KLex inp; public string kind; public int threads = 1;
        public KLex res; public string err = "";
        public double ms = -1; public long probes;
        public Func<double, double> pres;

        public DpJob(KLex i, string k, Func<double, double> altPres)
        {
            inp = i; kind = k; pres = altPres;
            // the scan's workers: the input's "threads", 0 = MIN(4, CPUs - 1)
            int n = inp.Has("threads") ? inp.I("threads") : 0;
            threads = n > 0 ? Math.Min(8, n) : Math.Max(1, Math.Min(4, Environment.ProcessorCount - 1));
        }

        public void Run()
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var c = new DpC(inp.L("c"));
            c.AltPres = pres;
            var g = new DpG(inp.L("g"));
            var s = new DpSolver(c, g);
            s.Threads = threads;
            var r = new KLex();
            if (kind == "solve")
            {
                var el = new DpEl(inp.L("el"));
                el.eph = new DpEph(s.E, el.r0, el.v0);
                KLex o = s.SolveBurn(el, inp.D("aimLat"), inp.D("aimLng"), inp.D("tSeed"), inp.D("thrLat"), inp.D("thrLng"));
                r["ok"] = o != null;
                r["out"] = o == null ? (object)new KLex() : o;
                r["rows"] = s.Rows;
                r["wr"] = s.Wr;
                r["ev"] = s.Ev;
                r["tmin"] = s.tMinOut; r["tmax"] = s.tMaxOut; r["period"] = s.periodOut;
            }
            else if (kind == "arc")
            {
                double a = s.ArcAt(inp.V("rei"), inp.V("vei"), inp.D("tRot"), inp.D("bank"), inp.D("aimLat"), inp.D("aimLng"));
                r["arc"] = a;
            }
            else throw new ArgumentException("unknown job " + kind);
            var gd = DpFill.Dump(g);
            if (gd["DP_LAST"] == null || gd["DP_LAST"] is int || gd["DP_LAST"] is double) gd["DP_LAST"] = 0;
            r["g"] = gd;
            probes = s.Probes;
            sw.Stop();
            ms = sw.Elapsed.TotalMilliseconds;
            r["ms"] = ms;
            r["threads"] = threads;
            res = r;
        }
    }
}
