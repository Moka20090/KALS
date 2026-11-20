// PrProp: the pure body-centred RK4 coast (moved out of Pr.cs so the n-body solve (PrNb.cs) and its offline tests build without Unity / Principia).
using System;

namespace KalsCoproc
{
    // A body-centred coast: the main body's point mass + J2 about Pole + third bodies (positions relative to the main body,
    // world axes, from BodyPos(t, k)), fixed-step RK4. Pure (no Unity, no Principia): the probe times it against
    // Principia's own propagation, F1's shooting will use it. Vectors are double[3].
    public sealed class PrProp
    {
        public double Mu, J2, Rj2;
        public double[] Pole = { 0, 0, 1 };
        public double[] BodyMu = new double[0];
        public Func<double, int, double[]> BodyPos;
        public long Evals;

        public void Accel(double t, double[] r, double[] a)
        {
            Evals++;
            double r2 = r[0] * r[0] + r[1] * r[1] + r[2] * r[2], rm = Math.Sqrt(r2), r3 = r2 * rm;
            for (int i = 0; i < 3; i++) a[i] = -Mu * r[i] / r3;
            if (J2 != 0)
            {
                double z = r[0] * Pole[0] + r[1] * Pole[1] + r[2] * Pole[2];
                double k = -1.5 * J2 * Mu * Rj2 * Rj2 / (r2 * r3), s = 1 - 5 * z * z / r2;
                for (int i = 0; i < 3; i++) a[i] += k * (s * r[i] + 2 * z * Pole[i]);
            }
            for (int b = 0; b < BodyMu.Length; b++)
            {
                double[] d = BodyPos(t, b);
                double ex = d[0] - r[0], ey = d[1] - r[1], ez = d[2] - r[2];
                double e2 = ex * ex + ey * ey + ez * ez, e3 = e2 * Math.Sqrt(e2);
                double d2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2], d3 = d2 * Math.Sqrt(d2);
                a[0] += BodyMu[b] * (ex / e3 - d[0] / d3);
                a[1] += BodyMu[b] * (ey / e3 - d[1] / d3);
                a[2] += BodyMu[b] * (ez / e3 - d[2] / d3);
            }
        }

        // r, v at t0 -> r, v at t1 (in place), steps of at most hMax s (the last one shortened); t1 may be < t0.
        public void Flow(double t0, double[] r, double[] v, double t1, double hMax)
        {
            int n = Math.Max(1, (int)Math.Ceiling(Math.Abs(t1 - t0) / hMax));
            double h = (t1 - t0) / n, t = t0;
            double[] k1v = new double[3], k2v = new double[3], k3v = new double[3], k4v = new double[3];
            double[] rr = new double[3], k1r = new double[3], k2r = new double[3], k3r = new double[3], k4r = new double[3];
            for (int s = 0; s < n; s++)
            {
                Accel(t, r, k1v);
                for (int i = 0; i < 3; i++) { k1r[i] = v[i]; rr[i] = r[i] + 0.5 * h * k1r[i]; }
                for (int i = 0; i < 3; i++) k2r[i] = v[i] + 0.5 * h * k1v[i];
                Accel(t + 0.5 * h, rr, k2v);
                for (int i = 0; i < 3; i++) { rr[i] = r[i] + 0.5 * h * k2r[i]; k3r[i] = v[i] + 0.5 * h * k2v[i]; }
                Accel(t + 0.5 * h, rr, k3v);
                for (int i = 0; i < 3; i++) { rr[i] = r[i] + h * k3r[i]; k4r[i] = v[i] + h * k3v[i]; }
                Accel(t + h, rr, k4v);
                for (int i = 0; i < 3; i++)
                {
                    r[i] += h / 6 * (k1r[i] + 2 * k2r[i] + 2 * k3r[i] + k4r[i]);
                    v[i] += h / 6 * (k1v[i] + 2 * k2v[i] + 2 * k3v[i] + k4v[i]);
                }
                t += h;
            }
        }
    }
}
