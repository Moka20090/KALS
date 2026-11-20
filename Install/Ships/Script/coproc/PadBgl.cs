// THE BLUE / GREEN SWEEP, line for line lib/lib_ascent_bgl.ks (bgl_gc, bgl_dest, bgl_wrap, bgl_ground, bgl_x, bgl_yix,
// bgl_mt, bgl_mix, bgl_ray, bgl_at_rel, bgl_span, bgl_margin, bgl_early_x, bgl_point, bgl_unit, bgl_edge, bgl_windows) and
// lib_ascent_cnt.ks's asc_cnt_sel, over the ARD's path. Units as kOS's (bg["u"]).
// C# only, PadC.BGL_HOLD: a MODE SEL 2 point and a late MODE SEL 1 one (asc_cnt_m1to2) scored at the MECO of
// the mode-2 hold flown from it (CntHold.Fly), each lit SSME, the best, ASC_BGL_PUSH2; the kOS sweep keeps the table.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    public class Bgl
    {
        PadC C; List<FtsPt> pts; ArdSnap sn;
        public List<double[]> gp = new List<double[]>();      // LIST(VI, lat, lng, heading, x)
        public List<int> md = new List<int>();
        public List<object[]> best = new List<object[]>();    // LIST(margin, site, yaw, early)
        public int u;
        public List<object> cont0 = new List<object>(); public List<object> yaw = new List<object>(), early = new List<object>(), mdl = new List<object>();

        public Bgl(PadC c, List<FtsPt> p) { C = c; pts = p; }
        public Bgl(PadC c, List<FtsPt> p, ArdSnap s) { C = c; pts = p; sn = s; }

        double[] Gc(double la1, double lo1, double la2, double lo2)
        {
            double h = Math.Pow(KM.Sin((la2 - la1) / 2), 2) + KM.Cos(la1) * KM.Cos(la2) * Math.Pow(KM.Sin((lo2 - lo1) / 2), 2);
            double b = KM.Atan2(KM.Sin(lo2 - lo1) * KM.Cos(la2), KM.Cos(la1) * KM.Sin(la2) - KM.Sin(la1) * KM.Cos(la2) * KM.Cos(lo2 - lo1));
            return new double[] { 2 * C.BGL_RKM * KM.Asin(Math.Min(1, Math.Sqrt(h))) / C.BGL_RAD, KM.Mod(b + 360, 360) };
        }

        double[] Dest(double la, double lo, double brg, double d)
        {
            double th = d / C.BGL_RKM * C.BGL_RAD;
            double la2 = KM.Asin(Math.Min(1, Math.Max(-1, KM.Sin(la) * KM.Cos(th) + KM.Cos(la) * KM.Sin(th) * KM.Cos(brg))));
            double lo2 = lo + KM.Atan2(KM.Sin(brg) * KM.Sin(th) * KM.Cos(la), KM.Cos(th) - KM.Sin(la) * KM.Sin(la2));
            return new double[] { la2, lo2, KM.Mod(Gc(la2, lo2, la, lo)[1] + 180, 360) };
        }

        static double Wrap(double a) { return KM.Mod(KM.Mod(a + 180, 360) + 360, 360) - 180; }

        double[] Ground(double t, Vec3 rr, Vec3 vv)
        {
            double w = C.ARD_W;
            double li = KM.Atan2(rr.Y, rr.X);
            double la = KM.Asin(rr.Z / rr.Mag);
            Vec3 vr = new Vec3(vv.X + w * rr.Y, vv.Y - w * rr.X, vv.Z);
            Vec3 ev = new Vec3(-KM.Sin(li), KM.Cos(li), 0);
            Vec3 nv = new Vec3(-KM.Sin(la) * KM.Cos(li), -KM.Sin(la) * KM.Sin(li), KM.Cos(la));
            return new double[] { vv.Mag, la, li - w * C.BGL_RAD * t, KM.Mod(KM.Atan2(Vec3.Dot(vr, ev), Vec3.Dot(vr, nv)) + 360, 360), 0 };
        }

        double X(Vec3 rr, Vec3 vv, double vi)
        {
            double h = rr.Mag / 1000 - C.BGL_RKM;
            if (C.BGL_MXK == 1) return h;
            if (C.BGL_MXK == 2)
            {
                double a = 1 / (2 / rr.Mag - vv.SqrMag / C.BGL_MU);
                double e = Math.Sqrt(Math.Max(0, 1 - Vec3.Cross(rr, vv).SqrMag / (C.BGL_MU * a)));
                return a * (1 + e) / 1000 - C.BGL_RKM;
            }
            double[] hb = C.BGL_HB_N;
            double f = Math.Min(Math.Max((vi - C.BGL_HB0) / C.BGL_HB1, 0), hb.Length - 1.000001);
            int i = (int)Math.Floor(f);
            return h - (hb[i] + (f - i) * (hb[i + 1] - hb[i]));
        }

        static int Yix(double y) { if (y == -2) return 3; if (y == 2) return 4; return (int)(y + 1); }

        double[] Mt(double y, double vi2, double xx)
        {
            double[] G = C.BGL_MG;
            double[] tb = C.BGL_MT[Yix(y)];
            double fv = Math.Min(Math.Max((vi2 - G[0]) / G[1], 0), G[2] - 1.000001);
            double fx = Math.Min(Math.Max((xx - G[3]) / G[4], 0), G[5] - 1.000001);
            double i = Math.Floor(fv), j = Math.Floor(fx);
            fv = fv - i;
            fx = fx - j;
            int a = (int)KM.Round((i * G[5] + j) * 4);
            int b = (int)KM.Round(a + G[5] * 4);
            var o = new double[4];
            for (int k = 0; k <= 3; k++)
                o[k] = (1 - fv) * ((1 - fx) * tb[a + k] + fx * tb[a + 4 + k]) + fv * ((1 - fx) * tb[b + k] + fx * tb[b + 4 + k]);
            return o;
        }

        double[] Mix(double[] sa, double[] sb, double f, double push)
        {
            if (sa != null && sb != null)
            {
                if (C.BGL_OUTER) return new double[] { Math.Min(sa[0], sb[0]), Math.Max(sa[1], sb[1]) };
                return new double[] { sa[0] + f * (sb[0] - sa[0]), sa[1] + f * (sb[1] - sa[1]) };
            }
            if (sa != null && f <= push) return sa;
            if (sb != null && 1 - f <= push) return sb;
            return null;
        }

        static double N(object o) { return KLex.Num(o, "bgl"); }
        static List<object> Lst(object o) { return (List<object>)o; }

        static double[] Ray(List<object> tp, int k)
        {
            if (N(Lst(tp[1])[k]) < 0) return null;
            return new double[] { N(Lst(tp[1])[k]), N(Lst(tp[2])[k]) };
        }

        double[] AtRel(List<object> tp, double rel)
        {
            double[] rl = C.BGL_REL;
            int n = rl.Length;
            if (rel < rl[0] || rel > rl[n - 1]) return null;
            int i = 0;
            while (!(i >= n - 1 || rl[i + 1] > rel)) i = i + 1;
            if (i >= n - 1) return Ray(tp, n - 1);
            return Mix(Ray(tp, i), Ray(tp, i + 1), (rel - rl[i]) / (rl[i + 1] - rl[i]), C.BGL_RELPUSH);
        }

        double[] Span(int br, double vi, double rel)
        {
            var tl = Lst(C.BGL_FP[br]);
            int n = tl.Count;
            if (vi <= N(Lst(tl[0])[0])) return AtRel(Lst(tl[0]), rel);
            if (vi >= N(Lst(tl[n - 1])[0])) return AtRel(Lst(tl[n - 1]), rel);
            int i = 0;
            while (!(N(Lst(tl[i + 1])[0]) > vi)) i = i + 1;
            double v0 = N(Lst(tl[i])[0]), v1 = N(Lst(tl[i + 1])[0]);
            return Mix(AtRel(Lst(tl[i]), rel), AtRel(Lst(tl[i + 1]), rel), (vi - v0) / (v1 - v0), C.BGL_VIPUSH);
        }

        double Margin(int br, double vi, double rel, double d, double push)
        {
            double[] sp = Span(br, vi, rel);
            if (sp == null) return C.BGL_NONE;
            return Math.Min(d - sp[0] + push, sp[1] + push - d);
        }

        double EarlyX(double la, double lo, double th12, List<object> st, double dco)
        {
            double[] gd = Gc(la, lo, N(st[1]), N(st[2]));
            double a13 = gd[0] / C.BGL_RKM * C.BGL_RAD;
            double ac = dco / C.BGL_RKM * C.BGL_RAD;
            double dth = gd[1] - th12;
            double xt = KM.Asin(Math.Max(-1, Math.Min(1, KM.Sin(a13) * KM.Sin(dth))));
            if (Math.Abs(xt) > ac) return -1;
            double atk = KM.Acos(Math.Max(-1, Math.Min(1, KM.Cos(a13) / KM.Cos(xt))));
            if (KM.Cos(dth) < 0) atk = -atk;
            double wk = KM.Acos(Math.Max(-1, Math.Min(1, KM.Cos(ac) / KM.Cos(xt))));
            if (atk + wk < 0) return -1;
            return Math.Max(0, atk - wk) / C.BGL_RAD * C.BGL_RKM;
        }

        object[] Point(double la, double lo, double hd, double vi2, double y, int mdd, double[] mt, double push)
        {                                        // mt: LIST(s km, beta deg, dpsi deg, MECO VI m/s) (bgl_mt's, or the hold's)
            double th12 = hd + mt[1];
            double[] mp = Dest(la, lo, th12, mt[0]);
            double hm = mp[2] + mt[2];
            int br = 0;
            if (Math.Abs(y) == 2) br = 2; else if (y != 0) br = 1;
            object[] bst = new object[] { C.BGL_NONE, "NONE", false };
            foreach (var so in C.BGL_SITES)
            {
                var st = Lst(so);
                double[] gd = Gc(mp[0], mp[1], N(st[1]), N(st[2]));
                double mg = Margin(br, mt[3], Wrap(gd[1] - hm), gd[0], push);
                bool ea = false;
                if (mdd == 2)
                {
                    double x = EarlyX(la, lo, th12, st, C.CNT_DCO);
                    if (x >= 0 && x < mt[0])
                    {
                        double f = 0;
                        if (mt[0] > 0) f = x / mt[0];
                        double[] ep = Dest(la, lo, th12, x);
                        double[] eg = Gc(ep[0], ep[1], N(st[1]), N(st[2]));
                        double em = Margin(br, vi2 + f * (mt[3] - vi2), Wrap(eg[1] - (ep[2] + f * mt[2])), eg[0], push);
                        if (em > mg) { mg = em; ea = true; }
                    }
                }
                if (mg > (double)bst[0]) bst = new object[] { mg, (string)st[0], ea };
            }
            return bst;
        }

        // The hold's MECO from point k with the SSME lit (0 L, 1 R, 2 C), the roll's way rs, as bgl_mt's LIST,
        // null without a C/O
        public double[] HoldMt(int k, int lit, int rs)
        {
            var p = pts[k];
            Vec3 u0 = (p.lamc + (p.t - p.tlamc) * p.lamdc).Normalized;
            string why;
            double[] m = CntHold.Fly(C, C.HOLD, lit, rs, p.t, p.r, p.v, p.et, sn.mc - p.om, sn.res, sn.f1, sn.vex, p.om, u0, out why);
            if (m == null) return null;
            double[] g2 = gp[k];
            double[] gm = Ground(m[0], new Vec3(m[1], m[2], m[3]), new Vec3(m[4], m[5], m[6]));
            double[] sb = Gc(g2[1], g2[2], gm[1], gm[2]);
            double fb = KM.Mod(Gc(gm[1], gm[2], g2[1], g2[2])[1] + 180, 360);
            return new double[] { sb[0], Wrap(sb[1] - g2[3]), Wrap(gm[3] - fb), gm[0] };
        }

        int Sel(Vec3 rr, Vec3 vv)
        {
            if (Vec3.Dot(rr.Normalized, vv) > C.CNT_HDOT_MODE1) return 1;
            if (vv.Mag > C.CNT_VI_MIN_DROOP) return 0;
            return 2;
        }

        // the whole sweep (bgl_start + bgl_unit until over + bgl_windows)
        public void Run()
        {
            int nY = C.BGL_YAWS.Length;
            for (int k = 0; k < pts.Count; k++)
            {
                int iy = 0;
                while (true)
                {
                    u = u + 1;
                    if (iy == 0)
                    {
                        var p = pts[k];
                        double[] g = Ground(p.t, p.r, p.v);
                        g[4] = X(p.r, p.v, g[0]);
                        gp.Add(g);
                        int m0 = Sel(p.r, p.v);
                        if (m0 == 0 && g[0] < C.BGL_V2) m0 = 1;
                        md.Add(m0);
                        best.Add(new object[] { C.BGL_NONE, "NONE", 0.0, false });
                    }
                    int mdd = md[k];
                    // The hold predicted (MODE SEL 2, or a late MODE SEL 1 = mode 2 + the hold): yaw 0 only
                    bool hold = C.BGL_HOLD && sn != null && (mdd == 2 || (mdd == 1 && C.CNT_LATE_M2 && gp[k][0] >= C.CNT_LATE_M2_VI));
                    if (hold) mdd = 2;
                    double y = C.BGL_YAWS[iy];
                    if (mdd != 0 && (mdd == 1 || y == 0))
                    {
                        double[] g = gp[k];
                        object[] pb = null;
                        if (hold)
                            for (int c6 = 0; c6 < 6; c6++)   // each lit SSME, each way of the roll to heads up: the best
                            {
                                double[] mh = HoldMt(k, c6 / 2, c6 % 2 == 0 ? 1 : -1);
                                if (mh == null) continue;
                                object[] q = Point(g[1], g[2], g[3], g[0], y, mdd, mh, C.BGL_PUSH2);
                                if (pb == null || (double)q[0] > (double)pb[0]) pb = q;
                            }
                        if (pb == null) pb = Point(g[1], g[2], g[3], g[0], y, mdd, Mt(y, g[0], g[4]), C.BGL_PUSH);
                        object[] bb = best[k];
                        double bar = (double)bb[0];
                        if (Math.Abs(y) == 2 && Math.Abs((double)bb[2]) != 2 && (double)bb[0] >= 0) bar = (double)bb[0] + C.BGL_Y20_PREF;
                        if ((double)pb[0] > bar) best[k] = new object[] { pb[0], pb[1], y, pb[2] };
                    }
                    iy = iy + 1;
                    while (!(iy >= nY || mdd == 1)) iy = iy + 1;
                    if (iy < nY) continue;
                    break;
                }
            }
            Windows();
        }

        double Edge(int ka, int kb)
        {
            int n = best.Count;
            if (ka < 0) return gp[0][0];
            if (kb >= n) return gp[n - 1][0] + 1;
            double va = gp[ka][0], vb = gp[kb][0], ma = (double)best[ka][0], mb = (double)best[kb][0];
            if (((ma >= 0 && mb < 0) || (ma < 0 && mb >= 0)) && ma > C.BGL_NONE && mb > C.BGL_NONE) return va + ma / (ma - mb) * (vb - va);
            return 0.5 * (va + vb);
        }

        static bool Same(object a, object b)
        {
            if (a is string) return string.Equals((string)a, (string)b, StringComparison.OrdinalIgnoreCase);
            if (a is bool) return (bool)a == (bool)b;
            return (double)a == (double)b;
        }

        void Windows()
        {
            int n = best.Count, k = 0;
            while (!(k >= n))
            {
                if ((double)best[k][0] >= 0)
                {
                    int j = k;
                    while (!(j + 1 >= n || (double)best[j + 1][0] < 0 || !Same(best[j + 1][1], best[k][1]) || !Same(best[j + 1][2], best[k][2])
                        || !Same(best[j + 1][3], best[k][3]) || md[j + 1] != md[k])) j = j + 1;
                    cont0.Add(Edge(k - 1, k));
                    cont0.Add(Edge(j, j + 1));
                    cont0.Add(best[k][1]);
                    yaw.Add(best[k][2]);
                    early.Add(best[k][3]);
                    mdl.Add(md[k]);
                    k = j + 1;
                }
                else k = k + 1;
            }
        }

        public KLex Result()
        {
            var r = new KLex();
            var g = new List<object>(); foreach (var x in gp) g.Add(new List<object> { x[0], x[1], x[2], x[3], x[4] }); r["gp"] = g;
            var m = new List<object>(); foreach (var x in md) m.Add(x); r["md"] = m;
            var b = new List<object>();
            foreach (var x in best) b.Add(new List<object> { x[0], x[1], x[2] is double ? (object)(int)(double)x[2] : x[2], x[3] });
            r["best"] = b;
            r["u"] = u; r["cont0"] = cont0;
            var yl = new List<object>(); foreach (var x in yaw) yl.Add((int)(double)x); r["yaw"] = yl;
            r["early"] = early; r["mdl"] = mdl;
            return r;
        }
    }
}
