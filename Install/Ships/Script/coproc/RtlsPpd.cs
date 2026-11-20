// The RTLS selection's
// pitchdown prediction in C#, a line-for-line port of lib/lib_ascent_rtls.ks's asc_rtls_ppd_predict (FSSR 4.6.2 RTLS
// INIT's PPD line: the pitchdown flown ahead in the vertical plane, point mass, central gravity and the centripetal term,
// no drag, at 0.02 s steps). In kOS it is ~53k opcodes in ONE call (asc_rtls_init at the RTLS selection: ~5 physics
// ticks at IPU 10000); everything else of the RTLS and of the 2EO contingency is under ~1k opcodes a pass and stays kOS's
// (t62/rtls/report_body.html). kOS semantics kept: SIN / COS in degrees (x * pi / 180), MIN / MAX as Math.Min / Max, the
// same operation order (left to right). Pure: no state, nothing written. C# 5.
using System;

namespace KalsCoproc
{
    public static class RtlsPpd
    {
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }

        // the inputs, in the staged lib_ascent_rtls.ks's order (asc_rtls_ppd_predict's dispatcher)
        public const int V0 = 0, GAM0 = 1, H0 = 2, M0 = 3, F = 4, MD = 5, TH0 = 6, ALPHA = 7, TOFF = 8, TT = 9, RATE = 10,
            R = 11, MU = 12, D2R = 13, R2D = 14, ACC = 15, N = 16;
        public static long MaxSteps = 50000000;     // a guard (kOS would loop on as long; NaN / inf inputs are refused first)

        // lib_ascent_rtls's asc_rtls_slew from t 0: the peak rate wp and the end t1 of a slew of th deg at w deg/s, a deg/s2
        public static void Slew(double th, double w, double a, out double wp, out double t1)
        {
            wp = Math.Min(w, Math.Sqrt(th * a));
            t1 = 0 + th / wp + wp / a;
        }

        // asc_rtls_slew_at's angle turned (deg) at t into that slew (started at 0)
        public static double SlewAt(double wp, double t1, double th, double a, double t)
        {
            double ta = wp / a;
            double tt = t - 0;
            double tl = t1 - t;
            if (tt <= 0) return 0;
            if (tl <= 0) return th;
            if (tt < ta) return 0.5 * a * tt * tt;
            if (tl < ta) return th - 0.5 * a * tl * tl;
            return 0.5 * a * ta * ta + wp * (tt - ta);
        }

        // asc_rtls_ppd_predict: LIST(dV m/s, dgam deg, dx m)
        public static double[] Predict(double[] a)
        {
            double v0 = a[V0], gam0 = a[GAM0], h0 = a[H0], m0 = a[M0], f = a[F], md = a[MD];
            double DEGTORAD = a[D2R], RADTODEG = a[R2D], ASC_R = a[R], ASC_MU = a[MU], PPD_RATE = a[RATE];
            double vel = v0;
            double gm = gam0 * DEGTORAD;
            double hh = h0;
            double xx = 0;
            double ms = m0;
            double th = a[TH0];
            double th_end = a[ALPHA] - a[TOFF];
            double sw, s1, sth = a[TH0] - th_end;
            Slew(sth, PPD_RATE, a[ACC], out sw, out s1);
            double tt = a[TT];
            double t = 0;
            long n = 0;
            while (!(t >= tt - 1e-9))
            {
                if (++n > MaxSteps) throw new InvalidOperationException("RTPPD: over " + MaxSteps + " steps (tt " + tt + ")");
                double dh = Math.Min(0.02, tt - t);
                double rad = ASC_R + hh;
                double gg = ASC_MU / (rad * rad);
                double ac = f / ms;
                double gd = gm * RADTODEG;
                double v1 = vel + (ac * Cos(th) - gg * Sin(gd)) * dh;
                double g1 = gm + (ac * Sin(th) - (gg - vel * vel / rad) * Cos(gd)) / vel * dh;
                hh = hh + vel * Sin(gd) * dh;
                xx = xx + vel * Cos(gd) * dh * ASC_R / rad;
                vel = v1;
                gm = g1;
                ms = ms - md * dh;
                th = a[TH0] - SlewAt(sw, s1, sth, a[ACC], t + dh);
                t = t + dh;
            }
            return new double[] { vel - v0, gm * RADTODEG - gam0, xx };
        }
    }
}
