// The OMS thrust line: the maths of KalsAddon.OmsLine.cs, with no Unity or kOS type (double[3] vectors) so an offline
// harness can run it against a numpy reference (tests/oms_line_ref.py).
// The line of one engine is its thrust vector after the gimbal's deflection. Two sources, one result type:
//   MEASURED  the engine's live thrust direction (its thrust transforms) times the thrust it gave;
//   TRIM      before any thrust, the deflection that puts the thrust line through the c.g.: the direction from the gimbal
//             pivot to the c.g. (the sign that agrees with the neutral axis), as the rotation from the neutral axis, its
//             components about the gimbal's two axes (lx pitch, ly yaw) clamped to the gimbal's range; the part about the
//             neutral axis itself (twist) is dropped, as the gimbal has no such axis.
// A line is the sum of the engines' F = T x direction (kN) with the torque about the c.g. of the same forces.
using System;

namespace KalsCoproc
{
    public static class OmsLineCore
    {
        public static double Dot(double[] a, double[] b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
        public static double[] Cross(double[] a, double[] b)
        {
            return new double[] { a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
        }
        public static double[] Sub(double[] a, double[] b) { return new double[] { a[0] - b[0], a[1] - b[1], a[2] - b[2] }; }
        public static double[] Scale(double[] a, double k) { return new double[] { a[0] * k, a[1] * k, a[2] * k }; }
        public static double[] Add(double[] a, double[] b) { return new double[] { a[0] + b[0], a[1] + b[1], a[2] + b[2] }; }
        public static double Mag(double[] a) { return Math.Sqrt(Dot(a, a)); }
        public static double[] Unit(double[] a)
        {
            double m = Mag(a);
            return m > 1e-12 ? Scale(a, 1.0 / m) : new double[] { 0, 0, 0 };
        }

        // v turned about the rotation vector rv (axis x angle, radians): Rodrigues
        public static double[] Rot(double[] v, double[] rv)
        {
            double th = Mag(rv);
            if (th < 1e-12) return new double[] { v[0], v[1], v[2] };
            double[] k = Scale(rv, 1.0 / th);
            double c = Math.Cos(th), s = Math.Sin(th);
            return Add(Add(Scale(v, c), Scale(Cross(k, v), s)), Scale(k, Dot(k, v) * (1 - c)));
        }

        // the thrust direction (unit) of an engine whose gimbal pivots at pivot, neutral thrust axis n (unit), pitch / yaw
        // axes lx / ly (unit, about which the gimbal turns the thrust), when it is trimmed through the c.g. cg; rx / ry the
        // range (radians, each way). clamped is set when either component hit its range.
        public static double[] TrimDir(double[] pivot, double[] n, double[] lx, double[] ly, double[] cg, double rx, double ry, out bool clamped)
        {
            clamped = false;
            double[] d = Unit(Sub(cg, pivot));
            if (Mag(d) < 0.5) return n;
            if (Dot(d, n) < 0) d = Scale(d, -1);
            double[] k = Cross(n, d);
            double s = Mag(k);
            if (s < 1e-12) return n;
            double ang = Math.Atan2(s, Dot(n, d));
            double[] rv = Scale(k, ang / s);
            double ax = Dot(rv, lx), ay = Dot(rv, ly);
            double cx = Math.Max(-rx, Math.Min(rx, ax)), cy = Math.Max(-ry, Math.Min(ry, ay));
            if (cx != ax || cy != ay) clamped = true;
            return Unit(Rot(n, Add(Scale(lx, cx), Scale(ly, cy))));
        }

        // the sum of forces F_i = T_i x dir_i at the pivots p_i about the c.g.: out[0..2] the force, out[3..5] the torque
        public static double[] Sum(double[][] p, double[][] dir, double[] t, double[] cg)
        {
            double[] f = new double[3], q = new double[3];
            for (int i = 0; i < p.Length; i++)
            {
                double[] fi = Scale(dir[i], t[i]);
                f = Add(f, fi);
                q = Add(q, Cross(Sub(p[i], cg), fi));
            }
            return new double[] { f[0], f[1], f[2], q[0], q[1], q[2] };
        }
    }
}
