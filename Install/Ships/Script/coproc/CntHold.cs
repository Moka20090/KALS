// THE MODE-2 HOLD PREDICTOR (PadBgl's MECO for a MODE SEL 2 point and a late MODE SEL 1 one;
// C# ONLY, the kOS sweep keeps ASC_BGL_MT): from a path point's state (the second SSME out there) the 2EO contingency
// flown to its C/O as lib_ascent_cnt flies it -- mode 2 heads up in its hold (asc_cnt_m2: the HDOT hold, the cap, the
// flat thrust, the cut law over ASC_CNT_LAW_ENDS and its yaw toward the best end), the natural pass (EAS > EAS_PD, HDOT
// < 0) or the law's cut -> PPD2 -> the C/O at QMECO_HIGH; the SSME left at ASC_KMAX_ABORT, the OMS dumped to dry
// from the failure (asc_oms_empty / asc_oms_now), MECO at the ET's reserve at the latest -- on a point mass (J2, the
// ARD's drag) with THE STAGE-2 ATTITUDE (sim/ascent/fly.py Stage2.direction: the thrust axis estimate put on the
// command, the nose slewing at most min(EO_WMAX, S2_WQ / q), the top rolling at most ASC_DAP_WMAX_ROLL1 about the nose,
// the thrust on the stack's own axis by the lit SSME (fly.py s2_axis's fits)): the 180 deg roll to heads up with the
// axis ~10 deg below the nose swings the thrust up to 12 deg off the command for ~20 s; without it the hold ran 6-20
// m/s fast and its law cut early. The repo sim's twin (hold2.py, simp=1 vac=1): vs the full
// sim (fly.py + cnt.Cnt) over 44 failure families (both out; the first SSME out at 20 .. 230 s pressing or as the TAL
// to ZZA / MRN; bases 36.25 and 51.6) the MECO within 2 km at p90 (max 5) in MODE SEL 2 and late MODE SEL 1, VI p90
// +5 m/s; the yaw-0 table it replaces: p90 48 km, max 300.
// lit: the SSME left (0 L, 1 R, 2 C): its axis differs (up to 15 km / 25 m/s at MECO); rs: the roll's way (+1 / -1):
// the roll to heads up starts ~180 deg off, its way set by the axis estimate's yaw (the first SSME out's), and with the
// axis off the nose the two ways part (up to 36 km, one 51.6 law cut 257); PadBgl scores each lit and way, the best.
// Units as the ARD's (m, m/s, t, kN, s; angles in degrees as kOS's); the frame the ARD's (z = the spin axis).
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    public static class CntHold
    {
        // ---- the stage-2 attitude model (sim/ascent/fly.py, measured on the stage-2 logs; keep in step with it)
        const double TB_PRIOR = 12.0, TB_Q_OFF = 4.0, TB_Q_ON = 1.0, QA_LIM = 40.0, EO_WMAX = 2.0, S2_WQ = 3.2, ROLL_W1 = 5.0;
        const double AXIS_P0 = 15.1, AXIS_P1 = 10.9, GP_K0 = -1.7722e-02, GP_K1 = -1.0147e-02, OMS_COS_DEG = 11.8;
        static readonly double[][] GP = {                        // the trim gimbal's cubic in m / 100 t: L lit, R lit, C lit
            new double[] { 1.67716, -4.82957, 4.58470, -1.89206 }, new double[] { -3.15632, 5.47937, -2.65722, -0.20572 },
            new double[] { 0.39212, -1.46671, 1.86480, -1.09519 } };
        static readonly double[][] AY = {                        // the axis' yaw on the gimbal: L, R, C
            new double[] { -0.537, 5.324 }, new double[] { 1.562, -3.084 }, new double[] { 0.104, 0.266 } };

        static double Sin(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180.0); }
        static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        static double Acos(double x) { return Math.Acos(x) * 180.0 / Math.PI; }
        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static double Clamp(double x, double a, double b) { return Math.Max(a, Math.Min(b, x)); }
        static Vec3 Unit(Vec3 a) { return a.Normalized; }
        static Vec3 RotZ(Vec3 u, double th) { double c = Cos(th), s = Sin(th); return new Vec3(c * u.X - s * u.Y, s * u.X + c * u.Y, u.Z); }

        class St                                                 // the contingency's state (asc_cnt_new's keys it uses)
        {
            public string ph = "hold"; public double t0, t_ppd, t_cut = -1, th2, e2 = -1, acc, abo, law_x, law_rel; public int law_k = -1;
            public Vec3 u0, tgt, xb, nb, ix, iz; public Vec3[] eps = new Vec3[0];
            public Vec3 actN, actT; public double actt; public bool act;   // the DAP's nose / top at the last step
            public int rs;                                       // the roll's way at its start (+1 / -1)
        }

        // ---- PadC's constants (lib_ascent_cnt's I-loads through lib_ascent_padcs: ASC_BGL_HOLD_K's order)
        public class K
        {
            public double THETA_MODE2, CANT, SLEW, EAS_PD, PITCH_ACC, HIGH_SEP_RATE, QMECO_HIGH, M2_HT, M2_K, M2_EMIN, M2_HCAP, M2_KH,
                M2_HDMIN, M2_PSI, M2_EFIX, M2_EGATE, LAW_HO, LAW_VIPK, OMS_USE, DT, OMS_F, DUMP_DELAY, T_MAX,
                LAW_REL;                                         // THE REL GATE (deg; 0 = none; a[25] when kOS sends it)
            public bool M2_FLAT, LAW;
            public double[] LAW_K; public Vec3[] ENDS;           // Earth-fixed at R (lat / lng of each end)
            public K(double[] a, double[] lawk, List<object> ends, double R)
            {
                THETA_MODE2 = a[0]; CANT = a[1]; SLEW = a[2]; EAS_PD = a[3]; PITCH_ACC = a[4]; HIGH_SEP_RATE = a[5]; QMECO_HIGH = a[6];
                M2_HT = a[7]; M2_K = a[8]; M2_EMIN = a[9]; M2_HCAP = a[10]; M2_KH = a[11]; M2_HDMIN = a[12]; M2_PSI = a[13];
                M2_FLAT = a[14] != 0; M2_EFIX = a[15]; M2_EGATE = a[16]; LAW = a[17] != 0; LAW_HO = a[18]; LAW_VIPK = a[19];
                OMS_USE = a[20]; DT = a[21]; OMS_F = a[22]; DUMP_DELAY = a[23]; T_MAX = a[24];
                LAW_REL = a.Length > 25 ? a[25] : 0.0;
                LAW_K = lawk;
                ENDS = new Vec3[ends.Count];
                for (int i = 0; i < ends.Count; i++)
                {
                    var e = (List<object>)ends[i];
                    double la = KLex.Num(e[1], "end"), lo = KLex.Num(e[2], "end");
                    ENDS[i] = new Vec3(R * Cos(la) * Cos(lo), R * Cos(la) * Sin(lo), R * Sin(la));
                }
            }
        }

        // ---- the air (the ARD's: ln rho / the speed of sound by km from ARD_AIR_H0, Cd by Mach) and gravity (J2)
        static void Air(FtsConsts F, double h, out double rho, out double sa)
        {
            rho = 0; sa = F.AS[0];
            if (h >= F.ARD_ATM_TOP) return;
            double lr = F.LNRHO[0];
            double x = (h - F.ARD_AIR_H0) / 1000;
            if (x > 0)
            {
                int i = (int)Math.Min(Math.Floor(x), F.LNRHO.Length - 2);
                double f = x - i;
                lr = F.LNRHO[i] + f * (F.LNRHO[i + 1] - F.LNRHO[i]);
                sa = F.AS[i] + f * (F.AS[i + 1] - F.AS[i]);
            }
            rho = Math.Exp(lr);
        }

        static double Cd(FtsConsts F, double mach)
        {
            double[] c = F.CDM;
            if (mach <= c[0]) return c[1];
            for (int i = 2; i < c.Length; i += 2)
                if (mach <= c[i]) return c[i - 1] + (c[i + 1] - c[i - 1]) * (mach - c[i - 2]) / (c[i] - c[i - 2]);
            return c[c.Length - 1];
        }

        static Vec3 Grav(FtsConsts F, Vec3 rr)
        {
            double r2 = Vec3.Dot(rr, rr), rm = Math.Sqrt(r2);
            double gm = -F.MU / (r2 * rm);
            double k = -1.5 * F.J2 * F.MU * F.R_J2 * F.R_J2 / (r2 * r2 * rm);
            double zz = 5 * rr.Z * rr.Z / r2;
            return new Vec3(gm * rr.X + k * rr.X * (1 - zz), gm * rr.Y + k * rr.Y * (1 - zz), gm * rr.Z + k * rr.Z * (3 - zz));
        }

        static Vec3 Vrel(FtsConsts F, Vec3 rr, Vec3 vv) { return new Vec3(vv.X + F.ARD_W * rr.Y, vv.Y - F.ARD_W * rr.X, vv.Z); }

        // ---- lib_ascent_cnt's functions (mode 2 only)
        static Vec3 Upn(Vec3 u, Vec3 ix, Vec3 iz)
        {
            double d = Vec3.Dot(ix, u);
            if (Math.Abs(d) > 0.9995) return -iz;
            return Unit(ix - d * u);
        }

        static Vec3 Gc(Vec3 u0, Vec3 u1, double amax)
        {
            double cs = Clamp(Vec3.Dot(u0, u1), -1, 1);
            double ang = Acos(cs);
            if (ang <= amax || ang < 0.0000000573) return u1;
            Vec3 w = Unit(u1 - cs * u0);
            return Cos(amax) * u0 + Sin(amax) * w;
        }

        static double PpdAng(K k, St cn, double t)
        {
            double tau = t - cn.t_ppd, wr = Math.Abs(k.HIGH_SEP_RATE), t1 = wr / k.PITCH_ACC;
            if (tau < t1) return 0.5 * k.PITCH_ACC * tau * tau;
            return 0.5 * k.PITCH_ACC * t1 * t1 + wr * (tau - t1);
        }

        static Vec3 Dir(K k, St cn, double t)
        {
            if (cn.ph == "ppd2" || cn.ph == "cut")
            {
                double tt = cn.ph == "cut" ? cn.t_cut : t;
                double ang = PpdAng(k, cn, tt);
                Vec3 xb = Cos(ang) * cn.xb - Sin(ang) * cn.nb, nb = Sin(ang) * cn.xb + Cos(ang) * cn.nb;
                return Unit(Cos(k.CANT) * xb - Sin(k.CANT) * nb);
            }
            return Gc(cn.u0, cn.tgt, k.SLEW * (t - cn.t0));
        }

        static void Rsep(K k, St cn, double t, Vec3 ix, Vec3 iz)
        {
            Vec3 u = Dir(k, cn, t);                              // cnt_bx in the hold
            Vec3 xb0 = Unit(Cos(k.CANT) * u + Sin(k.CANT) * Upn(u, ix, iz));
            cn.ph = "ppd2"; cn.t_ppd = t; cn.xb = xb0; cn.nb = Upn(xb0, ix, iz);
        }

        static bool M2(K k, St cn, Vec3 rr, Vec3 vv, Vec3 ix, Vec3 iy, Vec3 iz, double MU, double R)
        {
            double hdot = Vec3.Dot(ix, vv), rm = rr.Mag, h = rm - R;
            double gacc = MU / (rm * rm) - (Vec3.Dot(vv, vv) - hdot * hdot) / rm;
            double acc = cn.acc, emax = k.THETA_MODE2 - k.CANT, el = emax;
            if (k.M2_FLAT && acc * Sin(emax) <= gacc && cn.abo * Sin(emax) < k.M2_EGATE * gacc) el = k.M2_EFIX;
            if (k.M2_HCAP > 0 && hdot > 0 && h + hdot * hdot / (2 * Math.Max(gacc, 0.5)) > k.M2_HCAP) el = k.M2_EMIN;
            else if (acc * Sin(emax) > gacc)
            {
                double ht = k.M2_HT;
                if (k.M2_HCAP > 0) ht = Math.Max(k.M2_HDMIN, Math.Min(k.M2_HT, k.M2_HT - k.M2_KH * (h - k.M2_HCAP)));
                double s = (gacc + k.M2_K * (ht - hdot)) / Math.Max(acc, 0.000001);
                el = Asin(Math.Max(Sin(k.M2_EMIN), Math.Min(Sin(emax), s)));
            }
            cn.e2 = el; cn.th2 = el + k.CANT; cn.law_k = -1;
            if (!k.LAW || cn.eps.Length == 0) return false;
            double[] c = k.LAW_K;
            double vi = Math.Min(vv.Mag, k.LAW_VIPK);
            double g0 = c[0] + c[1] * vi + c[2] * vi * vi + c[3] * h / 1000 + c[4] * hdot;
            for (int i = 0; i < cn.eps.Length; i++)
            {
                Vec3 ps = cn.eps[i];
                double rel = Atan2(Vec3.Dot(ps, iy), Vec3.Dot(ps, iz));
                if (k.LAW_REL > 0 && Math.Abs(rel) > k.LAW_REL) continue;   // THE REL GATE (lib_ascent_cnt)
                double d = Atan2(Vec3.Cross(rr, ps).Mag, Vec3.Dot(rr, ps)) * R / 57295.779513082323;
                double x = d - (g0 + c[5] * Math.Abs(rel) + c[6] * rel * rel);
                if (cn.law_k < 0 || x < cn.law_x) { cn.law_k = i; cn.law_x = x; cn.law_rel = rel; }
            }
            if (cn.law_k < 0) return false;                     // no end within the gate
            return cn.law_x <= k.LAW_HO;
        }

        // asc_cnt_cycle, mode 2 heads up (no roll, no early C/O, no load gate: the uphill contingency)
        static void Cycle(K k, FtsConsts F, St cn, double t, Vec3 rr, Vec3 vv)
        {
            Vec3 wv = Vrel(F, rr, vv);
            Vec3 ix = Unit(rr), iy = Unit(Vec3.Cross(wv, ix)), iz = Vec3.Cross(ix, iy);
            cn.ix = ix; cn.iz = iz;
            double hdot = Vec3.Dot(ix, vv);
            bool m2 = cn.ph == "hold";
            if (m2 && M2(k, cn, rr, vv, ix, iy, iz, F.MU, F.R)) Rsep(k, cn, t, ix, iz);
            double rho, sa;
            Air(F, rr.Mag - F.R, out rho, out sa);
            double qq = 0.5 * rho * Vec3.Dot(wv, wv);
            double eas = Math.Sqrt(Math.Max(2 * qq / 1.225, 0)) / 0.514444;
            Vec3 un = Dir(k, cn, t);
            double th = cn.th2, ca = k.CANT;
            Vec3 uhu = Sin(th - ca) * ix + Cos(th - ca) * iz;
            if (cn.ph == "hold")
            {
                cn.u0 = un; cn.t0 = t; cn.tgt = uhu;
                if (eas > k.EAS_PD && hdot < 0) Rsep(k, cn, t, ix, iz);
            }
            if (m2 && cn.ph == "hold" && k.M2_PSI > 0 && cn.law_k >= 0)
            {
                double ps = Clamp(cn.law_rel, -k.M2_PSI, k.M2_PSI), el = cn.th2 - ca;
                cn.tgt = Sin(el) * ix + Cos(el) * (Cos(ps) * iz + Sin(ps) * iy);
            }
            if (cn.ph == "ppd2")
            {
                double rt = Math.Min(Math.Abs(k.HIGH_SEP_RATE), k.PITCH_ACC * (t - cn.t_ppd));
                if (rt >= Math.Abs(k.QMECO_HIGH) - 0.000000001) { cn.ph = "cut"; cn.t_cut = t; }
            }
        }

        // ---- the attitude (fly.py Stage2.direction with the contingency's rl): the thrust's direction at t
        static void RotMin(Vec3 a, Vec3 b, ref Vec3 v0, ref Vec3 v1, ref Vec3 v2)
        {
            Vec3 kk = Vec3.Cross(a, b);
            double sn = kk.Mag, cs = Vec3.Dot(a, b);
            if (sn < 1e-12) return;
            kk = (1.0 / sn) * kk;
            v0 = cs * v0 + sn * Vec3.Cross(kk, v0) + Vec3.Dot(kk, v0) * (1.0 - cs) * kk;
            v1 = cs * v1 + sn * Vec3.Cross(kk, v1) + Vec3.Dot(kk, v1) * (1.0 - cs) * kk;
            v2 = cs * v2 + sn * Vec3.Cross(kk, v2) + Vec3.Dot(kk, v2) * (1.0 - cs) * kk;
        }

        static Vec3 Slew(Vec3 a, Vec3 b, double ang)
        {
            double c = Clamp(Vec3.Dot(a, b), -1, 1), th = Math.Acos(c);
            if (th <= ang || th < 1e-9) return b;
            Vec3 p = Unit(b - c * a);
            return Math.Cos(ang) * a + Math.Sin(ang) * p;
        }

        static void QaLimit(ref Vec3 d, ref Vec3 top, Vec3 wv, double vr, double qk)
        {
            if (qk <= 0 || vr < 1) return;
            double am = QA_LIM / qk;
            if (am >= 180) return;
            Vec3 w = (1.0 / vr) * wv;
            double al = Atan2(Math.Abs(Vec3.Dot(w, top)), Vec3.Dot(w, d));
            if (al <= am) return;
            Vec3 sv = Unit(Vec3.Cross(top, d));
            Vec3 wp = w - Vec3.Dot(w, sv) * sv;
            if (wp.Mag < 0.01) return;
            wp = Unit(wp);
            Vec3 n = d - Vec3.Dot(d, wp) * wp;
            n = n.Mag > 1e-6 ? Unit(n) : Unit(top - Vec3.Dot(top, wp) * wp);
            double a = am * Math.PI / 180.0;
            Vec3 nd = Math.Cos(a) * wp + Math.Sin(a) * n;
            Vec3 c = Unit(Vec3.Cross(sv, nd));
            d = nd; top = Vec3.Dot(c, top) > 0 ? c : -c;
        }

        static readonly Vec3 TB = new Vec3(Math.Cos(TB_PRIOR * Math.PI / 180), -Math.Sin(TB_PRIOR * Math.PI / 180), 0);

        static Vec3 Att(K k, FtsConsts F, St cn, int lit, double t, Vec3 rr, Vec3 vv, double T, double m, bool commit)
        {
            Vec3 u = Dir(k, cn, t);
            Vec3 top = Unit(Upn(u, cn.ix, cn.iz));               // cnt_top heads up
            Vec3 wv = Vrel(F, rr, vv);
            double vr = wv.Mag, rho, sa;
            Air(F, rr.Mag - F.R, out rho, out sa);
            double qk = 0.5 * rho * vr * vr / 1000.0;
            double tbc = Clamp((TB_Q_OFF - qk) / (TB_Q_OFF - TB_Q_ON), 0, 1);
            Vec3 side = -Vec3.Cross(u, top);
            Vec3 e = Unit((1.0 - tbc) * new Vec3(1, 0, 0) + tbc * TB);
            Vec3 tbe = e.X * u + e.Y * top + e.Z * side;
            Vec3 nose = u;
            RotMin(tbe, u, ref nose, ref top, ref side);
            QaLimit(ref nose, ref top, wv, vr, qk);
            if (cn.act)
            {
                double wm = Math.Min(EO_WMAX, S2_WQ / Math.Max(qk, 1e-6));
                nose = Slew(cn.actN, nose, wm * Math.PI / 180.0 * Math.Max(0, t - cn.actt));
                top = Unit(top - Vec3.Dot(top, nose) * nose);
                Vec3 p0 = cn.actT - Vec3.Dot(cn.actT, nose) * nose;
                if (p0.Mag > 1e-9)
                {
                    p0 = Unit(p0);
                    double ang = Math.Atan2(Vec3.Dot(Vec3.Cross(p0, top), nose), Vec3.Dot(p0, top));
                    if (Math.Abs(ang) > 179.0 * Math.PI / 180.0) ang = cn.rs * Math.Abs(ang);   // ~180 off: the way given
                    double lim = ROLL_W1 * Math.PI / 180.0 * Math.Max(0, t - cn.actt);
                    if (Math.Abs(ang) > lim)
                    {
                        double a1 = ang < 0 ? -lim : lim;
                        top = Math.Cos(a1) * p0 + Math.Sin(a1) * Vec3.Cross(nose, p0);
                    }
                }
            }
            side = -Unit(Vec3.Cross(nose, top));
            if (commit) { cn.act = true; cn.actt = t; cn.actN = nose; cn.actT = top; }
            double x = 0;
            if (vr > 1) { Vec3 w = (1.0 / vr) * wv; x = -Atan2(-Vec3.Dot(w, top), Vec3.Dot(w, nose)); }
            double[] c = GP[lit];                                // s2_axis
            double uu = m / 100.0;
            double gp = ((c[0] * uu + c[1]) * uu + c[2]) * uu + c[3];
            if (T > 1.0) gp += (GP_K0 + GP_K1 * x) * qk * 1000.0 / T;
            gp = Clamp(gp, -1, 1);
            double ap = AXIS_P0 + AXIS_P1 * gp, ay = AY[lit][0] + AY[lit][1] * gp;
            Vec3 ut = Unit(Cos(ap) * nose - Sin(ap) * top);
            return Unit(Cos(ay) * ut + Sin(ay) * side);
        }

        // ---- the flight: the state at the C/O (t, r, v) or null (no C/O within T_MAX)
        // t, r, v, et: the point; mc t: the stack less the ET's propellant there (the ARD's mc - om); res t: the ET's
        // reserve; f1 kN, vex m/s: one SSME (the ARD's); om t: the OMS dumped on the path to the point; u0: PEG's steer there
        public static double[] Fly(PadC C, K k, int lit, int rs, double t, Vec3 r, Vec3 v, double et, double mc, double res,
            double f1, double vex, double om, Vec3 u0, out string why)
        {
            FtsConsts F = C.F;
            why = "tmax";
            double t2 = t;
            double F1 = C.KMAX_ABORT / 100 * C.PL_TO_KSP * f1;
            double mdo = C.ARD_MDO;
            double left = Math.Max(0, k.OMS_USE - om);
            double o0 = t2 + k.DUMP_DELAY, o1 = o0 + left / mdo;  // asc_oms_empty: the dump to dry from the failure
            var cn = new St { u0 = u0, tgt = u0, t0 = t2, th2 = k.THETA_MODE2, rs = rs < 0 ? -1 : 1 };
            Vec3 rh = Unit(r);                                   // the DAP heads down on PEG's steer, the axis prior on it
            Vec3 top0 = Unit(-rh + Vec3.Dot(rh, u0) * u0), side0 = -Vec3.Cross(u0, top0), n0 = u0;
            RotMin(TB.X * u0 + TB.Y * top0 + TB.Z * side0, u0, ref n0, ref top0, ref side0);
            cn.act = true; cn.actt = t2; cn.actN = n0; cn.actT = top0;
            double omd = 0;                                      // t dumped since the failure
            Func<double, double, double> mass = (tt, e) => mc + e - omd;
            // the pass (asc_cnt_pass: asc_cnt_m2in + the cycle)
            Action<double, Vec3, Vec3, double, double> pass = (tt, rr, vv, e, od) =>
            {
                if (cn.ph == "hold")
                {
                    double M = mc + e - od;
                    double f = Math.Min(F1, F.AL * M);
                    if (o0 - 1e-9 <= tt && tt < o1 - 1e-9) f += k.OMS_F;
                    cn.acc = f / M;
                    cn.abo = f / Math.Max(0.05 * M, M - Math.Max(0, e - res));
                    double w = F.ARD_W * 180.0 / Math.PI * tt;
                    var ps = new Vec3[k.ENDS.Length];
                    for (int i = 0; i < ps.Length; i++) ps[i] = RotZ(k.ENDS[i], w);
                    cn.eps = ps;
                }
                Cycle(k, F, cn, tt, rr, vv);
            };
            double cosO = Cos(OMS_COS_DEG);
            // y' (r, v, et, omd)
            Vec3 dR = Vec3.Zero, dV = Vec3.Zero; double dE = 0, dO = 0;
            Action<double, Vec3, Vec3, double, double, bool> D = (tt, rr, vv, e, od, oon) =>
            {
                double M = mc + e - od;
                double f = Math.Min(F1, F.AL * M);
                double md = f / vex;
                double a = f / M;
                Vec3 u = Att(k, F, cn, lit, tt, rr, vv, f, M, false);
                dO = 0;
                if (oon) { a += k.OMS_F * cosO / M; dO = mdo; }
                Vec3 wv = Vrel(F, rr, vv);
                double vr = wv.Mag, rho, sa;
                Air(F, rr.Mag - F.R, out rho, out sa);
                Vec3 dg = Vec3.Zero;
                if (rho > 0 && vr > 1e-6) dg = (-0.5 * rho * vr * F.ARD_AREF * Cd(F, vr / sa) / 1000 / M) * wv;
                dR = vv; dV = Grav(F, rr) + a * u + dg; dE = -md;
            };
            pass(t, r, v, et, omd);
            double tn = t2 + F.DTGD;
            while (t < t2 + k.T_MAX)
            {
                double tc = cn.t_cut >= 0 ? cn.t_cut : 1e9;
                double h = Math.Min(k.DT, Math.Min(tn - t, tc - t));
                foreach (double x in new double[] { o0, o1 })
                    if (t + 1e-6 < x && x < t + h - 1e-6) h = x - t;
                double tr = (et - res) / (F1 / vex);
                bool rsv = tr <= h;
                if (rsv) h = Math.Max(tr, 0);
                if (h > 1e-9)
                {
                    bool oon = o0 - 1e-9 <= t && t < o1 - 1e-9;
                    Att(k, F, cn, lit, t, r, v, 0, mass(t, et), true);   // Stage2.tick: the DAP's nose / top at the step's start
                    double h2 = h / 2;
                    D(t, r, v, et, omd, oon); Vec3 a1r = dR, a1v = dV; double a1e = dE, a1o = dO;
                    D(t + h2, r + h2 * a1r, v + h2 * a1v, et + h2 * a1e, omd + h2 * a1o, oon); Vec3 a2r = dR, a2v = dV; double a2e = dE, a2o = dO;
                    D(t + h2, r + h2 * a2r, v + h2 * a2v, et + h2 * a2e, omd + h2 * a2o, oon); Vec3 a3r = dR, a3v = dV; double a3e = dE, a3o = dO;
                    D(t + h, r + h * a3r, v + h * a3v, et + h * a3e, omd + h * a3o, oon); Vec3 a4r = dR, a4v = dV; double a4e = dE, a4o = dO;
                    double h6 = h / 6;
                    r = r + h6 * (a1r + 2 * a2r + 2 * a3r + a4r);
                    v = v + h6 * (a1v + 2 * a2v + 2 * a3v + a4v);
                    et = et + h6 * (a1e + 2 * a2e + 2 * a3e + a4e);
                    omd = omd + h6 * (a1o + 2 * a2o + 2 * a3o + a4o);
                    t = t + h;
                }
                if (t >= tc - 1e-9) { why = "cut"; return new double[] { t, r.X, r.Y, r.Z, v.X, v.Y, v.Z }; }
                if (rsv || et <= res + 1e-9) { why = "res"; return new double[] { t, r.X, r.Y, r.Z, v.X, v.Y, v.Z }; }
                if (t >= tn - 1e-9) { pass(t, r, v, et, omd); tn += F.DTGD; }
            }
            return null;
        }
    }
}
