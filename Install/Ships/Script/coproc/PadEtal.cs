// THE STAGE-1 PREDICTOR and E TAL, line for line lib/lib_ascent_etl.ks (ard_herm, ard_air, ard_lin, ard_s1_att,
// ard_s1_f, ard_s1_rk4, ard_s1_vrel, ard_s1_new, ard_s1_step; ard_et_s1, ard_et_new, ard_et_sep, ard_et_job, ard_et_try,
// ard_et_first, ard_et_tof, ard_et_site, ard_et_unit) and lib_ascent_s1.ks's asc_vref / asc_tab. The TAL flights are Fts.cs's
// FtsJob (ard_new / ard_unit / ard_margin) with E TAL's step and floor. Unit counts as kOS's (E["n"]).
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    // the vehicle (ard_s1_new's vh)
    public class S1Veh { public double mc, sdry, ssmd, knom, kabt, dpsi; public bool south; }

    public class S1Pred
    {
        public PadC C; public S1Veh vh;
        public double t; public Vec3 r, v; public double sf, et;   // y = LIST(rr, vv, sf, et)
        public bool po; public double tc, teo, dt; public int i, n; public bool done;

        public S1Pred Copy() { return (S1Pred)MemberwiseClone(); }

        // p0[5] of a state in flight (ard_et_s1: past the tower clear), a kOS Boolean
        public static bool PoOf(object o) { if (o is bool) return (bool)o; throw new InvalidCastException("p0[5] is not a boolean"); }

        // ard_s1_new
        public S1Pred(PadC c, double t0, Vec3 rr, Vec3 vv, double sf0, double et0, bool po0, double tc0, double teo0, double dt0, S1Veh v0)
        {
            C = c; t = t0; r = rr; v = vv; sf = sf0; et = et0; po = po0; tc = tc0; teo = teo0; dt = dt0; i = 0; n = 0; done = false; vh = v0;
        }

        // ard_herm: KSP's FloatCurve on keys (t, v, in, out), clamped
        public static double Herm(double[][] k, double x)
        {
            if (x <= k[0][0]) return k[0][1];
            if (x >= k[k.Length - 1][0]) return k[k.Length - 1][1];
            int ii = 0;
            while (!(x < k[ii + 1][0])) ii = ii + 1;
            double[] a = k[ii], b = k[ii + 1];
            double d = b[0] - a[0];
            double s = (x - a[0]) / d;
            double s2 = s * s;
            double s3 = s2 * s;
            return (2 * s3 - 3 * s2 + 1) * a[1] + (s3 - 2 * s2 + s) * d * a[3] + (3 * s2 - 2 * s3) * b[1] + (s3 - s2) * d * b[2];
        }

        // ard_air: LIST(p, rho, a)
        double[] Air(double hgt)
        {
            double[] T = C.S1P_ATM;
            double nn = T.Length / 3.0;
            if (hgt >= (nn - 1) * 500) return new double[] { 0, 0, T[T.Length - 1] };
            double x = Math.Max(hgt, 0) / 500;
            int ii = (int)Math.Min(Math.Floor(x), nn - 2);
            double f = x - ii;
            double p0 = T[3 * ii], p1 = T[3 * ii + 3], r0 = T[3 * ii + 1], r1 = T[3 * ii + 4];
            double p = p0 + f * (p1 - p0);
            if (p0 > 0 && p1 > 0) p = p0 * Math.Pow(p1 / p0, f);
            double rq = r0 + f * (r1 - r0);
            if (r0 > 0 && r1 > 0) rq = r0 * Math.Pow(r1 / r0, f);
            return new double[] { p, rq, T[3 * ii + 2] + f * (T[3 * ii + 5] - T[3 * ii + 2]) };
        }

        // ard_lin: A.interp on (x, y) pairs, clamped
        public static double Lin(double[] tb, double x)
        {
            if (x <= tb[0]) return tb[1];
            for (int ii = 2; ii < tb.Length; ii += 2)
                if (x <= tb[ii]) return tb[ii - 1] + (x - tb[ii - 2]) / (tb[ii] - tb[ii - 2]) * (tb[ii + 1] - tb[ii - 1]);
            return tb[tb.Length - 1];
        }

        // asc_vref, asc_tab (lib_ascent_s1.ks)
        double Vref(double vrel, double hgt) { return vrel * C.SSSL / (C.SSSL - C.DSSA * Math.Min(Math.Max(hgt, 0), C.ALTSS)); }
        static double Tab(double[] P, double[] Y, int ii, double x)
        {
            double y0 = KM.Tan(Y[ii] / 4);
            double y1 = KM.Tan(Y[ii + 1] / 4);
            return 4 * KM.Atan(y0 + (y1 - y0) / (P[ii + 1] - P[ii]) * (x - P[ii]));
        }

        // ard_s1_att
        Vec3 Att(double tt, Vec3 rh, double vrel, double hgt)
        {
            if (!po) return rh;
            double x = Vref(vrel, hgt);
            int ii = i;
            while (!(ii >= C.PPOLY.Length - 2 || x < C.PPOLY[ii + 1])) ii = ii + 1;
            double th = Tab(C.PPOLY, C.THET, ii, x);
            double ps = Tab(C.PPOLY, C.PSI, ii, x) + vh.dpsi;
            if (vh.south) ps = 180 - ps;
            if (tt >= C.T_CNS_PITCH_RATE && tc != -99) th = 4 * KM.Atan(tc + 0.25 * C.THETC_DOT_NOM_RAD * (tt - C.T_CNS_PITCH_RATE));
            Vec3 e = new Vec3(-rh.Y, rh.X, 0).Normalized;
            Vec3 d = KM.Cos(ps) * Vec3.Cross(rh, e) + KM.Sin(ps) * e;
            return KM.Cos(th) * d + KM.Sin(th) * rh;
        }

        // ard_s1_f: (dr, dv, dsf, det)
        void F(double tt, Vec3 rr, Vec3 vv, double sff, double ett, bool eo, out Vec3 dr, out Vec3 dv, out double dsf, out double det)
        {
            double rm = rr.Mag;
            Vec3 rh = new Vec3(rr.X / rm, rr.Y / rm, rr.Z / rm);
            double hgt = rm - C.R;
            Vec3 wv = new Vec3(vv.X + C.ARD_W * rr.Y, vv.Y - C.ARD_W * rr.X, vv.Z);
            double vrel = wv.Mag;
            double[] ai = Air(hgt);
            double patm = ai[0] * C.S1P_ATM_PER_PA;
            double m = vh.mc + ett + C.S1P_NSRB * (vh.sdry + Math.Max(sff, 0));
            Vec3 u = Att(tt, rh, vrel, hgt);
            double md1 = 0;
            if (sff > 0) md1 = C.S1P_SRB_MD * Herm(C.S1P_SRB_C, sff / C.S1P_SRB_CAP);
            double fs = C.S1P_NSRB * md1 * Herm(C.S1P_SRB_I, patm) * 9.80665;
            double k = vh.knom;
            if (eo) k = vh.kabt;
            else
            {
                for (int qq = 0; qq < Math.Min(C.QPOLY.Length, 4); qq++)
                    if (vrel >= C.QPOLY[qq]) k = C.THROT[qq];
            }
            double mds = k / 100 * C.PL_TO_KSP * vh.ssmd;
            if (eo) mds = mds * 2 / 3;
            Vec3 a = (fs + mds * Herm(C.S1P_SS_I, patm) * 9.80665) / m * u + KM.Grav(C, rr);
            if (ai[1] > 0 && vrel > 1e-6)
                a = a - 0.5 * ai[1] * vrel * C.S1P_AREF * Lin(C.S1P_CDM, vrel / ai[2]) / 1000 / m * wv;
            dr = vv; dv = a; dsf = -md1; det = -mds;
        }

        // ard_s1_rk4 from (tt, y)
        void Rk4(double tt, Vec3 r0, Vec3 v0, double sf0, double et0, double h, bool eo, out Vec3 r1, out Vec3 v1, out double sf1, out double et1)
        {
            Vec3 a1r, a1v, a2r, a2v, a3r, a3v, a4r, a4v; double a1s, a1e, a2s, a2e, a3s, a3e, a4s, a4e;
            F(tt, r0, v0, sf0, et0, eo, out a1r, out a1v, out a1s, out a1e);
            F(tt + h / 2, r0 + h / 2 * a1r, v0 + h / 2 * a1v, sf0 + h / 2 * a1s, et0 + h / 2 * a1e, eo, out a2r, out a2v, out a2s, out a2e);
            F(tt + h / 2, r0 + h / 2 * a2r, v0 + h / 2 * a2v, sf0 + h / 2 * a2s, et0 + h / 2 * a2e, eo, out a3r, out a3v, out a3s, out a3e);
            F(tt + h, r0 + h * a3r, v0 + h * a3v, sf0 + h * a3s, et0 + h * a3e, eo, out a4r, out a4v, out a4s, out a4e);
            r1 = r0 + h / 6 * (a1r + 2 * a2r + 2 * a3r + a4r);
            v1 = v0 + h / 6 * (a1v + 2 * a2v + 2 * a3v + a4v);
            sf1 = sf0 + h / 6 * (a1s + 2 * a2s + 2 * a3s + a4s);
            et1 = et0 + h / 6 * (a1e + 2 * a2e + 2 * a3e + a4e);
        }

        double Vrel(Vec3 rr, Vec3 vv) { return new Vec3(vv.X + C.ARD_W * rr.Y, vv.Y - C.ARD_W * rr.X, vv.Z).Mag; }

        // ard_s1_step: one RK4 step; TRUE once at the separation
        public bool Step()
        {
            if (done) return true;
            double tt = t;
            bool eo = teo >= 0 && tt >= teo - 1e-9;
            double h = dt;
            if (teo >= 0 && tt + 1e-9 < teo && teo < tt + h - 1e-9) h = teo - tt;
            if (tt + 1e-9 < C.T_CNS_PITCH_RATE && C.T_CNS_PITCH_RATE < tt + h - 1e-9) h = C.T_CNS_PITCH_RATE - tt;
            Vec3 r1, v1; double sf1, et1;
            Rk4(tt, r, v, sf, et, h, eo, out r1, out v1, out sf1, out et1);
            if (sf1 <= 0)
            {
                double lo = 0, flo = sf, hi = h, fhi = sf1, hm = h;
                Vec3 rm = r1, vm = v1; double sm = sf1, em = et1;
                for (int qq = 0; qq < 30; qq++)
                {
                    hm = hi - fhi * (hi - lo) / (fhi - flo);
                    Rk4(tt, r, v, sf, et, hm, eo, out rm, out vm, out sm, out em);
                    if (Math.Abs(sm) < 1e-7) break;
                    if (sm > 0) { lo = hm; flo = sm; } else { hi = hm; fhi = sm; }
                }
                t = tt + hm; r = rm; v = vm; sf = 0; et = em;
                n = n + 1;
                done = true;
                return true;
            }
            if (!po)
            {
                double w0 = Vrel(r, v), w1 = Vrel(r1, v1);
                if (w1 >= C.PPOLY[1])
                {
                    double hc = h;
                    if (w1 > w0) hc = h * (C.PPOLY[1] - w0) / (w1 - w0);
                    Rk4(tt, r, v, sf, et, hc, eo, out r1, out v1, out sf1, out et1);
                    h = hc;
                    po = true;
                }
            }
            tt = tt + h;
            t = tt; r = r1; v = v1; sf = sf1; et = et1;
            n = n + 1;
            if (po)
            {
                double x = Vref(Vrel(r1, v1), r1.Mag - C.R);
                while (!(i >= C.PPOLY.Length - 2 || x < C.PPOLY[i + 1])) i = i + 1;
                if (tc == -99 && tt >= C.T_CNS_PITCH_RATE - 1e-9) tc = KM.Tan(Tab(C.PPOLY, C.THET, i, x) / 4);
            }
            return false;
        }

        // ard_et_sep: the separation + B: (t, rr, vv, et)
        public void Sep(out double ts, out Vec3 rs, out Vec3 vs, out double es)
        {
            Vec3 ru = r.Normalized;
            Vec3 hh = Vec3.Cross(r, v).Normalized;
            Vec3 dn = Vec3.Cross(hh, ru);
            double[] B = C.S1P_B;
            ts = t + B[0];
            rs = r + B[1] * ru + B[2] * dn + B[3] * hh;
            vs = v + B[4] * ru + B[5] * dn + B[6] * hh;
            es = et + B[7];
        }
    }

    // E TAL (ard_et_*): per site the earliest SSME-out time whose TAL clears ETAL_HF at MECO; E["n"] units
    public class Etal
    {
        PadC C;
        double[] p0r; Vec3 p0rr, p0vv;              // p0 = LIST(t, rr, vv, sf, et)
        bool p0po = false; double p0tc = -99;       // a state in flight's p0[5], p0[6] (ard_et_s1)
        S1Veh vh; double snMc, snRes, f1, vex; Vec3 iy;
        public List<string> ks = new List<string>(); Dictionary<string, TalSite> tls = new Dictionary<string, TalSite>();
        public int si = 0, bs = 0, dir = 0, n = 0;
        public double lo = 0, hi, mlo = 0, mhi = 0, tf = 0, etal = -1, vi = -1, sv = -1, st = -1, dd = 0;
        public string ph = "nom"; public bool done = false;
        public List<double> vt = new List<double>();
        public List<string> tbKeys = new List<string>(); public Dictionary<string, double> tb = new Dictionary<string, double>();
        public List<double[]> trials = new List<double[]>();   // (site index, tf, margin) of each TAL flown (the log's)
        List<S1Pred> snap = new List<S1Pred>();
        S1Pred s1; FtsJob job;

        // ard_et_new(p0, vh, sn, tls, iy) + E["sv"]
        public Etal(PadC c, KLex e)
        {
            C = c;
            var p0 = e.A("p0");
            p0r = new double[] { KLex.Num(p0[0], "p0"), KLex.Num(p0[3], "p0"), KLex.Num(p0[4], "p0") };
            p0rr = (Vec3)p0[1]; p0vv = (Vec3)p0[2];
            if (p0.Count > 6) { p0po = S1Pred.PoOf(p0[5]); p0tc = KLex.Num(p0[6], "p0"); }
            var v = e.L("vh");
            vh = new S1Veh { mc = v.D("mc"), sdry = v.D("sdry"), ssmd = v.D("ssmd"), knom = v.D("knom"), kabt = v.D("kabt"),
                dpsi = v.D("dpsi"), south = v.B("south") };
            var sn = e.L("sn");
            snMc = sn.D("mc"); snRes = sn.D("res"); f1 = sn.L("m").D("f1"); vex = sn.L("m").D("vex");
            var tl = e.L("tls");
            foreach (var k in tl.Keys) { ks.Add(k); tls[k] = PadC.Site(tl.L(k)); }
            iy = e.V("iy");
            hi = C.ETAL_HI;
            sv = e.D("sv");
            s1 = S1(-1);
        }

        S1Pred S1(double teo) { return new S1Pred(C, p0r[0], p0rr, p0vv, p0r[1], p0r[2], p0po, p0tc, teo, 2, vh); }

        // ard_et_job: PEG cold, the steering along the horizontal speed
        FtsJob Job(string k, double ts, Vec3 rr, Vec3 vv, double ett)
        {
            Vec3 ru = rr.Normalized;
            Vec3 hz = (vv - Vec3.Dot(vv, ru) * ru).Normalized;
            var j = new FtsJob(C.F, "TAL", tls[k], 2, C.KMAX_ABORT, ts, rr, vv, ett, snMc, snRes, iy, hz, Vec3.Zero, ts,
                new double[] { ts + C.TAL_OMS_DELAY, ts + C.TAL_OMS_DELAY + C.TAL_DUMP / C.ARD_MDO }, f1, vex);
            j.ts = -1;
            j.hfloor = C.ETAL_HF;
            j.hstep = C.ETAL_DT;
            return j;
        }

        void Try(double tfn)
        {
            tf = tfn;
            int k = -1;
            for (int ii = 0; ii < snap.Count; ii++) if (snap[ii].t <= tfn + 1e-9 && !snap[ii].done) k = ii;
            if (k < 0) s1 = S1(tfn);
            else { s1 = snap[k].Copy(); s1.teo = tfn; }
            ph = "s1";
        }

        void First()
        {
            lo = 0; hi = C.ETAL_HI; st = -1;
            if (C.ETAL_SEED_ON)
            {
                foreach (var k in tbKeys) if (tb[k] < C.ARD_NEVER && (st < 0 || tb[k] < st)) st = tb[k];
                if (st < 0 && sv > 0) st = Tof(vt, sv);
            }
            if (st > 0 && st < C.ETAL_HI) { bs = 3; dd = C.ETAL_SEED_DT; Try(st); }
            else { bs = 0; Try(0); }
        }

        static double Tof(List<double> vt, double vi)
        {
            for (int ii = 2; ii < vt.Count; ii += 2)
                if (vt[ii + 1] >= vi && vt[ii - 1] < vi) return vt[ii - 2] + (vi - vt[ii - 1]) / (vt[ii + 1] - vt[ii - 1]) * (vt[ii] - vt[ii - 2]);
            return -1;
        }

        void Site(double t)
        {
            string key = ks[si];
            if (!tb.ContainsKey(key)) tbKeys.Add(key);
            tb[key] = t;
            si = si + 1;
            if (si < ks.Count) { First(); return; }
            double best = C.ARD_NEVER;
            foreach (var k in ks) best = Math.Min(best, tb[k]);
            etal = best;
            vi = C.ARD_NEVER;
            if (best < C.ARD_NEVER)
            {
                vi = vt[1];
                for (int ii = 2; ii < vt.Count; ii += 2)
                {
                    if (best <= vt[ii]) { vi = vt[ii - 1] + (best - vt[ii - 2]) / (vt[ii] - vt[ii - 2]) * (vt[ii + 1] - vt[ii - 1]); break; }
                    vi = vt[ii + 1];
                }
            }
            done = true;
        }

        // ard_et_unit
        public bool Unit()
        {
            if (done) return true;
            n = n + 1;
            if (ph == "nom")
            {
                S1Pred j = s1;
                if (vt.Count == 0) { vt.Add(j.t); vt.Add(j.v.Mag); snap.Add(j.Copy()); }
                bool fin = j.Step();
                vt.Add(j.t); vt.Add(j.v.Mag);
                snap.Add(j.Copy());
                if (fin) First();
                return false;
            }
            if (ph == "s1")
            {
                if (s1.Step())
                {
                    double ts, ett; Vec3 rr, vv;
                    s1.Sep(out ts, out rr, out vv, out ett);
                    job = Job(ks[si], ts, rr, vv, ett);
                    ph = "fts";
                }
                return false;
            }
            if (!job.Unit()) return false;
            double m = job.Margin();
            trials.Add(new double[] { si, tf, m });
            if (bs >= 3)
            {
                if (bs == 3)
                {
                    dir = m >= 0 ? -1 : 1;
                    bs = 4;
                }
                else if ((m >= 0) != (dir < 0))
                {
                    if (m >= 0) { hi = tf; mhi = m; } else { lo = tf; mlo = m; }
                    bs = 2;
                    if (hi - lo > C.ETAL_TOL) { Try(0.5 * (lo + hi)); return false; }
                    Site(lo + (hi - lo) * (-mlo) / (mhi - mlo));
                    return done;
                }
                if (m >= 0) { hi = tf; mhi = m; } else { lo = tf; mlo = m; }
                if (dir < 0 && tf <= 0) { Site(0); return done; }
                if (dir > 0 && tf >= C.ETAL_HI) { Site(C.ARD_NEVER); return done; }
                double tn = tf + dir * dd;
                dd = 2 * dd;
                Try(Math.Max(0, Math.Min(C.ETAL_HI, tn)));
                return false;
            }
            if (bs == 0)
            {
                if (m >= 0) { Site(lo); return done; }
                mlo = m;
                bs = 1;
                Try(hi);
                return false;
            }
            if (bs == 1)
            {
                if (m < 0) { Site(C.ARD_NEVER); return done; }
                mhi = m;
                bs = 2;
            }
            else if (m >= 0) { hi = tf; mhi = m; }
            else { lo = tf; mlo = m; }
            if (hi - lo > C.ETAL_TOL) { Try(0.5 * (lo + hi)); return false; }
            Site(lo + (hi - lo) * (-mlo) / (mhi - mlo));
            return done;
        }

        public void Run() { while (!Unit()) { } }

        // the result lexicon (the keys kOS's ej gets back)
        public KLex Result()
        {
            var r = new KLex();
            r["done"] = done; r["etal"] = etal; r["vi"] = vi; r["n"] = n; r["si"] = si; r["ph"] = ph; r["tf"] = tf; r["st"] = st;
            r["bs"] = bs; r["dd"] = dd; r["dir"] = dir; r["lo"] = lo; r["hi"] = hi; r["mlo"] = mlo; r["mhi"] = mhi;
            var t = new KLex(); foreach (var k in tbKeys) t[k] = tb[k]; r["tb"] = t;
            var l = new List<object>(); foreach (var x in vt) l.Add(x); r["vt"] = l;
            var tr = new List<object>();
            foreach (var x in trials) tr.Add(new List<object> { ks[(int)x[0]], x[1], x[2] });
            r["trials"] = tr;
            return r;
        }
    }
}
