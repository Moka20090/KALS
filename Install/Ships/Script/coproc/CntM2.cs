// the mode 2 hold pass of the 2EO contingency in C#, a line-for-line port of lib/lib_ascent_cnt.ks's
// asc_cnt_m2 (the thrust's elevation that holds HDOT under the altitude cap; the cut law's best end over
// ASC_CNT_LAW_ENDS). ~1.7-1.9k opcodes a pass in kOS (its 14-end loop), the one contingency pass over ~1k; the rest of
// the contingency (MAN, ROLL, HOLD's other modes, YAWBACK, PPD1 / PPD2, CUT: ~400-700 a pass) stays kOS's. kOS
// semantics: SIN / ARCSIN / ARCTAN2 in degrees, ARCTAN2's arguments through Z (kOS's ScalarValue.Create makes a -0 an
// int 0), ^ = Math.Pow, MIN / MAX = Math.Min / Max, vectors through KSP's Vector3d (VDOT = Dot, VCRS = Cross, :MAG =
// magnitude), the same operation order. Pure: the result goes back to kOS, which writes cn. C# 5.
using System;

namespace KalsCoproc
{
    public class CntM2In
    {
        public Vector3d rr, vv, ix, iy, iz;
        public Vector3d[] eps;
        public double acc, abo, law_x;
        public double MU, R, THETA_MODE2, CANT, M2_EGATE, M2_EFIX, M2_HCAP, M2_EMIN, M2_HT, M2_HDMIN, M2_KH, M2_K, LAW_VIPK, LAW_HO;
        public bool M2_FLAT, LAW;
        public double[] LAW_K;
    }

    public class CntM2Out
    {
        public double e2, th2, law_k, law_x, law_d, law_rel;
        public bool wrote, ret;
    }

    public static class CntM2
    {
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        static double Z(double x) { return x == 0 ? 0.0 : x; }
        static double Atan2(double y, double x) { return Math.Atan2(Z(y), Z(x)) * 180.0 / Math.PI; }

        public static CntM2Out Pass(CntM2In c)
        {
            var o = new CntM2Out();
            Vector3d rr = c.rr, vv = c.vv, ix = c.ix, iy = c.iy, iz = c.iz;
            double hdot = Vector3d.Dot(ix, vv);
            double rm = rr.magnitude;
            double h = rm - c.R;
            double gacc = c.MU / Math.Pow(rm, 2) - (Vector3d.Dot(vv, vv) - hdot * hdot) / rm;
            double acc = c.acc;
            double emax = c.THETA_MODE2 - c.CANT;
            double el = emax;
            if (c.M2_FLAT && acc * Sin(emax) <= gacc && c.abo * Sin(emax) < c.M2_EGATE * gacc)
                el = c.M2_EFIX;
            if (c.M2_HCAP > 0 && hdot > 0 && h + hdot * hdot / (2 * Math.Max(gacc, 0.5)) > c.M2_HCAP)
            {
                el = c.M2_EMIN;
            }
            else if (acc * Sin(emax) > gacc)
            {
                double ht = c.M2_HT;
                if (c.M2_HCAP > 0)
                    ht = Math.Max(c.M2_HDMIN, Math.Min(c.M2_HT, c.M2_HT - c.M2_KH * (h - c.M2_HCAP)));
                double s = (gacc + c.M2_K * (ht - hdot)) / Math.Max(acc, 0.000001);
                el = Asin(Math.Max(Sin(c.M2_EMIN), Math.Min(Sin(emax), s)));
            }
            o.e2 = el;
            o.th2 = el + c.CANT;
            o.law_k = -1;
            o.law_x = c.law_x;
            if (!c.LAW || c.eps.Length == 0) { o.ret = false; return o; }
            o.wrote = true;
            double[] k = c.LAW_K;
            double vi = Math.Min(vv.magnitude, c.LAW_VIPK);
            double g0 = k[0] + k[1] * vi + k[2] * vi * vi + k[3] * h / 1000 + k[4] * hdot;
            int i = 0;
            foreach (Vector3d ps in c.eps)
            {
                double rel = Atan2(Vector3d.Dot(ps, iy), Vector3d.Dot(ps, iz));
                double d = Atan2(Vector3d.Cross(rr, ps).magnitude, Vector3d.Dot(rr, ps)) * c.R / 57295.779513082323;
                double x = d - (g0 + k[5] * Math.Abs(rel) + k[6] * rel * rel);
                if (o.law_k < 0 || x < o.law_x)
                {
                    o.law_k = i;
                    o.law_x = x;
                    o.law_d = d;
                    o.law_rel = rel;
                }
                i = i + 1;
            }
            o.ret = o.law_x <= c.LAW_HO;
            return o;
        }
    }
}
