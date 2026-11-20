// OUR OWN FLIGHT PLANS ON N-BODY PROPAGATION -- the pure solver behind ops2q's BRN PLN SOLVE (no Unity, no kOS, no Principia;
// PrNbKos.cs puts it on a thread and on ADDONS:KALS:NBSOLVE). The automatic re-solve on every change stays ops2q's own fast Kepler
// solve; SOLVE then asks for this one, which flies the real coast (PrProp: the main body's point mass + J2 about its pole + the Moon /
// Sun from KSP's bodies, fixed-step RK4; a probe measured it 0.18 km from Principia's own propagation over 5652 s where the
// Kepler conic is 19.8 km off) and measures the burn's target on that coast. Vectors are double[3] in kOS's raw axes (what kOS calls
// SHIP:POSITION - BODY:POSITION); handedness only enters through "lh" (lib_o2orb's O2_LH: the same arithmetic cross product).
//   INPUT  t0, r0, v0       the state the plan starts from (the live orbit now, or a burn's state after it), UT / body-relative
//          ut               the Kepler solve's burn point (UT); WHEN 0 APO / 1 PERI / 2 AN / 3 DN re-find it on the n-body coast
//          type, when, rt (m, radius), inc (deg), dvl (LVLH dv), nodv (the Kepler solve found nothing to do: stay at 0)
//   WHAT IS SOLVED (every extreme is of |r| over ONE osculating period from the burn point, the burn point included, so it reduces to the
//   Kepler conic's ra / rp when the force is a point mass; the extremum itself by a cubic Hermite on r and r-dot between steps):
//          CIRC   the horizontal speed that makes the radius vary least over the next period (golden section; the radial speed 0, the plane kept)
//          HA/HP  the prograde dv that puts the max / min radius at rt (bisection, the Kepler bracket)
//          PLANE  lib_o2orb's o2Plane at the n-body state (J2 leaves the inclination alone; the node's time is what moves)
//          DV     the typed LVLH dv in the LVLH frame of the n-body state
using System;
using System.Diagnostics;

namespace KalsCoproc
{
    public sealed class NbBodies
    {
        public double[] Mu = new double[0];
        public double T0, Step = 600;
        public double[][][] Pos = new double[0][][];     // [body][k] = body-relative position at T0 + k * Step
    }

    public sealed class NbJob
    {
        // ---- input
        public double Mu, J2, Rj2, T0, Ut, Rt, IncT, HMax = 10;
        public double[] Pole = { 0, 0, 1 }, R0 = new double[3], V0 = new double[3], Dvl = new double[3];
        public int Type, When;
        public bool Lh = true, NoDv;
        public NbBodies Bodies;
        // ---- output
        public string Err = "";
        public double OutUt;
        public int Ev;                                   // 1 = the burn point was re-found on the n-body coast
        public double[] OutR = new double[3], OutV = new double[3], OutDv = new double[3];
        public double Ra, Rp, Per, K;
        public double Ms;
        public long Evals;
        public int Cut;                                  // an extreme-search count (tests)

        PrProp P;

        static double Dot(double[] a, double[] b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
        static double Nrm(double[] a) { return Math.Sqrt(Dot(a, a)); }
        static double[] Cross(double[] a, double[] b) { return new[] { a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] }; }
        static double[] Add(double[] a, double[] b) { return new[] { a[0] + b[0], a[1] + b[1], a[2] + b[2] }; }
        static double[] Sub(double[] a, double[] b) { return new[] { a[0] - b[0], a[1] - b[1], a[2] - b[2] }; }
        static double[] Mul(double[] a, double k) { return new[] { a[0] * k, a[1] * k, a[2] * k }; }
        static double[] Unit(double[] a) { double n = Nrm(a); return n < 1e-12 ? new double[3] : Mul(a, 1 / n); }
        static double[] C(double[] a) { return (double[])a.Clone(); }

        // ---- the coast
        void Build()
        {
            P = new PrProp { Mu = Mu, J2 = J2, Rj2 = Rj2, Pole = Pole };
            if (Bodies != null && Bodies.Mu.Length > 0)
            {
                P.BodyMu = Bodies.Mu;
                NbBodies b = Bodies;
                P.BodyPos = (t, i) =>
                {
                    double[][] p = b.Pos[i];
                    if (p.Length == 1) return p[0];
                    double x = (t - b.T0) / b.Step;
                    int k = (int)Math.Floor(x);
                    if (k < 0) k = 0;
                    if (k > p.Length - 2) k = p.Length - 2;
                    double f = x - k;
                    return new[] { p[k][0] + (p[k + 1][0] - p[k][0]) * f, p[k][1] + (p[k + 1][1] - p[k][1]) * f, p[k][2] + (p[k + 1][2] - p[k][2]) * f };
                };
            }
        }

        // r, v (copies are the caller's business) from t to t1, in place
        void To(double t, double[] r, double[] v, double t1)
        {
            if (Math.Abs(t1 - t) < 1e-9) return;
            P.Flow(t, r, v, t1, HMax * 1.001);
        }

        double Period(double[] r, double[] v)            // the osculating period, 0 when not bound
        {
            double rm = Nrm(r), e = Dot(v, v) / 2 - Mu / rm;
            if (e >= -1e-9) return 0;
            double a = -Mu / (2 * e);
            return 2 * Math.PI * Math.Sqrt(a * a * a / Mu);
        }

        // max and min of |r| over [t, t + tw] from the state (r0, v0) at t (not changed)
        void Extremes(double t, double[] r0, double[] v0, double tw, out double rmax, out double rmin)
        {
            double[] r = C(r0), v = C(v0);
            int n = Math.Max(16, (int)Math.Ceiling(tw / HMax));
            double h = tw / n, tc = t;
            double rp = Nrm(r), dp = Dot(r, v) / rp;
            rmax = rp; rmin = rp;
            Cut++;
            for (int i = 0; i < n; i++)
            {
                P.Flow(tc, r, v, tc + h, h * 1.001);
                tc += h;
                double rn = Nrm(r), dn = Dot(r, v) / rn;
                if (rn > rmax) rmax = rn;
                if (rn < rmin) rmin = rn;
                if (dp * dn < 0)                           // the radius turned inside this step: the cubic Hermite's extremum
                {
                    double lo = 0, hi = 1, a = h * dp, b = h * dn;
                    double sLo = Math.Sign(dp);
                    for (int it = 0; it < 40; it++)
                    {
                        double m = 0.5 * (lo + hi);
                        double d = (6 * m * m - 6 * m) * rp + (3 * m * m - 4 * m + 1) * a + (-6 * m * m + 6 * m) * rn + (3 * m * m - 2 * m) * b;
                        if (Math.Sign(d) == sLo) lo = m; else hi = m;
                    }
                    double tt = 0.5 * (lo + hi), t2 = tt * tt, t3 = t2 * tt;
                    double val = (2 * t3 - 3 * t2 + 1) * rp + (t3 - 2 * t2 + tt) * a + (-2 * t3 + 3 * t2) * rn + (t3 - t2) * b;
                    if (val > rmax) rmax = val;
                    if (val < rmin) rmin = val;
                }
                rp = rn; dp = dn;
            }
        }

        // after a velocity change: the extremes over the next osculating period; false when the new orbit is not bound
        bool After(double t, double[] r, double[] v, out double rmax, out double rmin, out double per)
        {
            per = Period(r, v);
            rmax = 1e30; rmin = -1e30;
            if (per <= 0) return false;
            Extremes(t, r, v, per, out rmax, out rmin);
            return true;
        }

        // the burn point on the n-body coast: the event of WHEN nearest to the Kepler time ut, within half an osculating period
        // both ways; false (Ev stays 0) when there is none to find (an orbit with no apsis / no node line)
        double Refine(double ut)
        {
            double[] r = C(R0), v = C(V0);
            To(T0, r, v, ut);
            double per = Period(r, v);
            if (per <= 0) return ut;
            double rm = Nrm(r);
            double[] hv = Cross(r, v);
            double ecc = Nrm(Sub(Mul(Cross(v, hv), 1 / Mu), Mul(r, 1 / rm)));
            if (When <= 1 && ecc < 0.005) return ut;     // a near circle has no apsis worth the name: the Kepler time stands
            if (When >= 2 && Math.Abs(Dot(hv, Pole)) / Nrm(hv) > 0.9995) return ut;   // an equatorial orbit has no node line
            double ta = Math.Max(T0 + 1, ut - per / 2), tb = ut + per / 2;
            double[] rs = C(R0), vs = C(V0);
            To(T0, rs, vs, ta);
            double step = 5;
            double best = double.NaN, bestAbs = 1e30;
            double tc = ta;
            double fp = Fev(rs, vs);
            while (tc < tb - 1e-9)
            {
                double h = Math.Min(step, tb - tc);
                double[] rn = C(rs), vn = C(vs);
                To(tc, rn, vn, tc + h);
                double fn = Fev(rn, vn);
                if (Cross2(fp, fn))
                {
                    double lo = 0, hi = h;
                    for (int it = 0; it < 40 && hi - lo > 1e-4; it++)
                    {
                        double m = 0.5 * (lo + hi);
                        double[] rm2 = C(rs), vm2 = C(vs);
                        To(tc, rm2, vm2, tc + m);
                        double fm = Fev(rm2, vm2);
                        if (Cross2(fp, fm)) hi = m; else lo = m;
                    }
                    double te = tc + 0.5 * (lo + hi);
                    if (Math.Abs(te - ut) < bestAbs) { bestAbs = Math.Abs(te - ut); best = te; }
                }
                tc += h; rs = rn; vs = vn; fp = fn;
            }
            if (double.IsNaN(best)) return ut;
            Ev = 1;
            return best;
        }
        double Fev(double[] r, double[] v) { return When <= 1 ? Dot(r, v) : Dot(r, Pole); }
        bool Cross2(double a, double b)                  // the sign change of the right direction: APO r-dot + to -, PERI - to +, AN z - to +, DN z + to -
        {
            bool rise = (When == 1 || When == 2);
            return rise ? (a < 0 && b >= 0) : (a > 0 && b <= 0);
        }

        public bool Run()
        {
            var sw = Stopwatch.StartNew();
            try { return Run0(); }
            catch (Exception e) { Err = "N-BODY " + e.GetType().Name + ": " + e.Message; return false; }
            finally { Ms = sw.Elapsed.TotalMilliseconds; if (P != null) Evals = P.Evals; }
        }

        bool Run0()
        {
            Build();
            if (!(Ut > T0 + 30)) { Err = "TIG TOO CLOSE"; return false; }
            if (Ut - T0 > 3 * 86400) { Err = "TIG MORE THAN 3 DAYS AHEAD"; return false; }
            double ut = Ut;
            Ev = 0;
            if (When >= 0 && When <= 3) { ut = Refine(Ut); if (ut < T0 + 30) { Err = "TIG TOO CLOSE"; return false; } }
            double[] r = C(R0), v = C(V0);
            To(T0, r, v, ut);
            OutUt = ut; OutR = C(r); OutV = C(v);
            double rm = Nrm(r);
            double[] uu = Mul(r, 1 / rm);
            double vr = Dot(v, uu);
            double[] vh = Sub(v, Mul(uu, vr));
            double[] x = Unit(vh);                       // LVLH x: the horizontal motion
            double[] dv = new double[3];
            double rmax, rmin, per;
            if (Type == 4)                               // DV: the typed LVLH dv in the frame of this state
            {
                double[] hf = Unit(Cross(r, v));
                double[] y = Lh ? hf : Mul(hf, -1), z = Mul(uu, -1);
                dv = Add(Add(Mul(x, Dvl[0]), Mul(y, Dvl[1])), Mul(z, Dvl[2]));
            }
            else if (Type == 3)                          // PLANE: o2Plane
            {
                if (!NoDv)
                {
                    double[] nth = Unit(Sub(Pole, Mul(uu, Dot(Pole, uu))));
                    double[] est = Unit(Lh ? Cross(uu, Pole) : Cross(Pole, uu));
                    double sg = Dot(vh, nth) >= 0 ? 1 : -1;
                    double ci = Math.Cos(IncT * Math.PI / 180), si = Math.Sin(IncT * Math.PI / 180);
                    double[] vn = Add(Mul(Add(Mul(est, ci), Mul(nth, sg * si)), Nrm(vh)), Mul(uu, vr));
                    dv = Sub(vn, v);
                }
            }
            else if (Type == 0)                          // CIRC: the speed along x that varies the radius least
            {
                double vc = Math.Sqrt(Mu / rm);
                double lo = vc * 0.985, hi = vc * 1.015, g = (Math.Sqrt(5) - 1) / 2;
                double c = hi - g * (hi - lo), d = lo + g * (hi - lo);
                double fc = Spread(ut, r, x, c), fd = Spread(ut, r, x, d);
                for (int i = 0; i < 48 && hi - lo > 2e-4; i++)
                {
                    if (fc < fd) { hi = d; d = c; fd = fc; c = hi - g * (hi - lo); fc = Spread(ut, r, x, c); }
                    else { lo = c; c = d; fc = fd; d = lo + g * (hi - lo); fd = Spread(ut, r, x, d); }
                }
                double s = 0.5 * (lo + hi);
                K = s;
                dv = Sub(Mul(x, s), v);
            }
            else                                         // HA / HP: bisection on the prograde dv
            {
                bool ha = Type == 1;
                double[] u = Unit(v);
                double f0 = Apsis(ut, r, v, u, 0, ha);
                if (Math.Abs(f0 - Rt) < 5 || NoDv) { /* nothing to do: the target is where the orbit already is (T558) */ }
                else
                {
                    double vm = Nrm(v), lo = -vm * 0.5, hi = vm * 0.4;
                    if (Apsis(ut, r, v, u, lo, ha) > Rt || Apsis(ut, r, v, u, hi, ha) < Rt) { Err = "TARGET NOT REACHABLE FROM THIS POINT"; return false; }
                    for (int i = 0; i < 60; i++)
                    {
                        double md = 0.5 * (lo + hi);
                        if (Apsis(ut, r, v, u, md, ha) < Rt) lo = md; else hi = md;
                        if (hi - lo < 1e-4) break;
                    }
                    K = 0.5 * (lo + hi);
                    dv = Mul(u, K);
                }
            }
            OutDv = dv;
            double[] va = Add(v, dv);
            if (!After(ut, r, va, out rmax, out rmin, out per)) { Err = "NOT BOUND AFTER THE BURN"; return false; }
            Ra = rmax; Rp = rmin; Per = per;
            return true;
        }

        double Apsis(double t, double[] r, double[] v, double[] u, double k, bool ha)
        {
            double rmax, rmin, per;
            if (!After(t, r, Add(v, Mul(u, k)), out rmax, out rmin, out per)) return 1e30;
            return ha ? rmax : rmin;
        }

        double Spread(double t, double[] r, double[] x, double s)
        {
            double rmax, rmin, per;
            if (!After(t, r, Mul(x, s), out rmax, out rmin, out per)) return 1e30;
            return rmax - rmin;
        }
    }
}
