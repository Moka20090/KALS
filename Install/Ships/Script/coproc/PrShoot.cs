// PEG 8 -- THE PRINCIPIA-PLAN GUIDANCE'S SHOT (pure: no Unity, no kOS, no Principia; PrShootKos.cs puts it on a thread and on
// ADDONS:KALS:PEG8SOLVE). The design: the AIM POINT is the next planned burn's ignition (else half an
// orbit after this burn); the MATCH is Principia's planned POSITION there: a Lambert-style shot through our n-body coast (PrProp: the body's point mass +
// J2 + the Moon / Sun, fixed-step RK4), the unknown the velocity at the burn's cut (3 x 3), the velocity at the aim point follows.
//   INPUT  t0, r0, v0     the state now (UT, body-relative, kOS's raw axes: no handedness enters)
//          tc             the impulse UT (>= t0): before ignition the burn's centre, in the burn t0 itself
//          dvg            the guess: the PLANNED dV as an inertial vector at tc (the start of the Newton iteration, and the "PEG 7 would miss by" reference)
//          the aim        EITHER ar (a position) + at (UT)                  -- Principia's own planned position at the next burn's ignition
//                         OR pr / pv at pt (the plan's state AFTER the burn, UT pt) + at (UT, 0 = half an osculating period after pt):
//                            the aim point is the n-body coast of that plan state to at
//   WHAT IS SOLVED  v' such that the n-body coast of (rc, v') from tc to at meets the aim position: Newton on the 3-vector v' with a forward-difference
//                   Jacobian (delta 0.05 m/s) and a damped least-squares step ((J'J + W^2 I)^-1 J' f, W = 100 m per m/s at most): at a transfer angle of
//                   180 deg (the half-orbit aim on the plan's own conic, or a next burn half an orbit on) the shot cannot see the plane, and the damped
//                   step keeps the guess's out-of-plane velocity instead of chasing a few metres with m/s. A solution more than max(3 m/s, 10 %) from
//                   the planned dV is refused (the trust region): PEG 8 flies the plan's burn corrected for its execution, not another burn.
//   OUTPUT rc, vc (the state at tc before the burn, on the n-body coast), vreq (v'), dv (v' - vc, the VGO), aimr, aimt, miss0 (m: the coast of
//          (rc, vc + dvg) = the planned dV flown as an impulse, from the aim), missCut (m: the coast of (rc, vc) = the burn cut NOW), resid (m: the shot's own
//          residual), iters.
using System;
using System.Diagnostics;

namespace KalsCoproc
{
    public sealed class ShootJob
    {
        // ---- input
        public double Mu, J2, Rj2, T0, Tc, At, Pt, HMax = 20, Tol = 0.5;
        public double[] Pole = { 0, 0, 1 }, R0 = new double[3], V0 = new double[3], Dvg = new double[3], Ar, Pr, Pv;
        public NbBodies Bodies;
        // ---- output
        public string Err = "";
        public double[] Rc = new double[3], Vc = new double[3], Vreq = new double[3], Dv = new double[3], AimR = new double[3];
        public double AimT, Miss0, MissCut, Resid, Ms;
        public int Iters;
        public long Evals;
        public bool HaveMiss;                            // MissCut / Miss0 are set (also when the shot itself then failed)

        PrProp P;
        double H;

        static double Dot(double[] a, double[] b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
        static double Nrm(double[] a) { return Math.Sqrt(Dot(a, a)); }
        static double[] Add(double[] a, double[] b) { return new[] { a[0] + b[0], a[1] + b[1], a[2] + b[2] }; }
        static double[] Sub(double[] a, double[] b) { return new[] { a[0] - b[0], a[1] - b[1], a[2] - b[2] }; }
        static double[] C(double[] a) { return (double[])a.Clone(); }

        // the osculating period of (r, v) under the point mass, 0 when not bound (the half-orbit aim's length)
        public static double Period(double mu, double[] r, double[] v)
        {
            double rm = Nrm(r), e = Dot(v, v) / 2 - mu / rm;
            if (e >= -1e-9) return 0;
            double a = -mu / (2 * e);
            return 2 * Math.PI * Math.Sqrt(a * a * a / mu);
        }
        // the aim's UT as the job will use it (so the caller samples the third bodies far enough); 0 = no aim can be built
        public static double AimTime(double mu, double at, double pt, double[] pr, double[] pv)
        {
            if (at > 0) return at;
            if (pr == null || pv == null) return 0;
            double per = Period(mu, pr, pv);
            return per > 0 ? pt + per / 2 : 0;
        }

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

        // the coast of (r, v) from t to t1, a copy (the step: a flow of at most H s)
        double[] Coast(double t, double[] r, double[] v, double t1, out double[] vOut)
        {
            double[] rr = C(r), vv = C(v);
            if (Math.Abs(t1 - t) > 1e-9) P.Flow(t, rr, vv, t1, H * 1.001);
            vOut = vv;
            return rr;
        }

        // the shot's miss vector (position at the aim less the aim) for the velocity v at tc
        double[] Miss(double[] v)
        {
            double[] vo;
            double[] r = Coast(Tc, Rc, v, AimT, out vo);
            return Sub(r, AimR);
        }

        // solve the 3 x 3 system (A + lam I) x = b by Cramer's rule
        static double[] Solve3(double[,] A, double[] b)
        {
            double d = A[0, 0] * (A[1, 1] * A[2, 2] - A[1, 2] * A[2, 1]) - A[0, 1] * (A[1, 0] * A[2, 2] - A[1, 2] * A[2, 0]) + A[0, 2] * (A[1, 0] * A[2, 1] - A[1, 1] * A[2, 0]);
            if (Math.Abs(d) < 1e-300) return null;
            double[] x = new double[3];
            for (int c = 0; c < 3; c++)
            {
                double[,] M = (double[,])A.Clone();
                for (int r = 0; r < 3; r++) M[r, c] = b[r];
                x[c] = (M[0, 0] * (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]) - M[0, 1] * (M[1, 0] * M[2, 2] - M[1, 2] * M[2, 0]) + M[0, 2] * (M[1, 0] * M[2, 1] - M[1, 1] * M[2, 0])) / d;
            }
            return x;
        }

        public bool Run()
        {
            var sw = Stopwatch.StartNew();
            try { return Run0(); }
            catch (Exception e) { Err = "SHOT " + e.GetType().Name + ": " + e.Message; return false; }
            finally { Ms = sw.Elapsed.TotalMilliseconds; if (P != null) Evals = P.Evals; }
        }

        bool Run0()
        {
            if (!(Tc >= T0 - 1e-6)) { Err = "TIG BEFORE NOW"; return false; }
            AimT = AimTime(Mu, At, Pt, Pr, Pv);
            if (!(AimT > 0)) { Err = "NO AIM POINT"; return false; }
            if (!(AimT > Tc + 60)) { Err = "AIM TOO CLOSE"; return false; }
            if (AimT - T0 > 3 * 86400) { Err = "AIM MORE THAN 3 DAYS AHEAD"; return false; }
            H = Math.Max(5, Math.Min(HMax, (AimT - T0) / 200));
            Build();
            // the state at tc on the n-body coast
            double[] vo;
            Rc = Coast(T0, R0, V0, Tc, out vo); Vc = vo;
            // the aim position
            if (Ar != null) AimR = C(Ar);
            else
            {
                if (Pr == null || Pv == null) { Err = "NO AIM POINT"; return false; }
                if (!(AimT > Pt)) { Err = "AIM BEFORE THE PLAN STATE"; return false; }
                AimR = Coast(Pt, Pr, Pv, AimT, out vo);
            }
            // the references: the planned dV as an impulse, the burn cut now
            MissCut = Nrm(Miss(Vc));
            double[] v = Add(Vc, Dvg);
            Miss0 = Nrm(Miss(v));
            HaveMiss = true;
            // Newton with the damped least-squares step
            double[] f = Miss(v);
            double fn = Nrm(f);
            int it = 0;
            bool stalled = false;
            const double del = 0.05;
            while (fn > Tol && it < 14)
            {
                double[,] J = new double[3, 3];
                for (int c = 0; c < 3; c++)
                {
                    double[] vp = C(v); vp[c] += del;
                    double[] fp = Miss(vp);
                    for (int r = 0; r < 3; r++) J[r, c] = (fp[r] - f[r]) / del;
                }
                double[,] A = new double[3, 3];
                double[] g = new double[3];
                for (int i = 0; i < 3; i++)
                {
                    for (int j = 0; j < 3; j++) { double s = 0; for (int k = 0; k < 3; k++) s += J[k, i] * J[k, j]; A[i, j] = s; }
                    double q = 0; for (int k = 0; k < 3; k++) q += J[k, i] * f[k];
                    g[i] = -q;
                }
                // the damping: minimise |f|^2 + W^2 |step|^2, W = how many metres at the aim one m/s of velocity is worth (the Jacobian's columns are m per m/s):
                // a direction the shot barely sees (the plane of a 180 deg aim, J'J eigenvalues under W^2) takes almost no step, the well seen ones are solved
                double W = Math.Max(3, Math.Min(100, 0.05 * (AimT - Tc)));
                double lam = W * W;
                for (int i = 0; i < 3; i++) A[i, i] += lam;
                double[] dvs = Solve3(A, g);
                if (dvs == null || double.IsNaN(dvs[0] + dvs[1] + dvs[2])) { Err = "SHOT SINGULAR"; return false; }
                double sn = Nrm(dvs);
                if (sn > 200) for (int i = 0; i < 3; i++) dvs[i] *= 200 / sn;
                // a step that makes it worse is halved (the Jacobian is a linearisation)
                double[] vn = null, fnv = null; double fnn = 0; double lm = 1;
                for (int h = 0; h < 6; h++)
                {
                    vn = new[] { v[0] + dvs[0] * lm, v[1] + dvs[1] * lm, v[2] + dvs[2] * lm };
                    fnv = Miss(vn); fnn = Nrm(fnv);
                    if (fnn < fn) break;
                    lm *= 0.5;
                }
                if (!(fnn < fn)) { stalled = true; break; }
                bool slow = fnn > 0.9 * fn;
                v = vn; f = fnv; fn = fnn; it++;
                if (sn * lm < 1e-3 || slow) { stalled = true; break; }   // no velocity left to move: the rest of the miss is not the velocity's to fix (a 180 deg shot's plane)
            }
            if (it >= 14 && fn > Tol) stalled = true;           // The iteration cap with the miss still falling slowly is the same stall (the part of the miss the velocity cannot fix, e.g. the plane miss of a 180 deg aim: a damped step shrinks it by ~0.89 a step, which the 0.9 test above lets through); the 20000 m test and the trust region below judge it
            Iters = it; Resid = fn;
            Vreq = v; Dv = Sub(v, Vc);
            if (fn > Tol * 10 && !(stalled && fn < 20000)) { Err = "NO CONVERGENCE (" + Math.Round(fn) + " M)"; return false; }
            // the trust region: PEG 8 steers a burn that is the plan's, corrected for the burn's own execution (a TIG a second late, a velocity a metre off);
            // a shot that asks for a different burn (a stale plan, an aim the shot cannot reach without a large dV) is not PEG 8's to fly
            double far = Nrm(Sub(v, Add(Vc, Dvg)));
            if (far > Math.Max(3, 0.1 * Nrm(Dvg))) { Err = "SOLUTION " + Math.Round(far, 1) + " M/S FROM THE PLAN"; return false; }
            return true;
        }
    }
}
