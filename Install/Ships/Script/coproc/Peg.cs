// The C#
// coprocessor's PEG, a line-for-line port of lib/lib_ascent_peg.ks's asc_peg_cycle and its helpers (asc_coast, asc_abc,
// asc_peg_tgt, asc_tal_vel), the nominal and TAL targets (the RTLS's SMODE 5 is not ported yet). kOS semantics kept: SIN /
// COS / ARCCOS in degrees, the vectors in ops1q's inertial frame, VCRS the plain cross product. Compiles with the .NET
// Framework's csc (C# 5).
using System;

namespace KalsCoproc
{
    public struct Vec3
    {
        public double X, Y, Z;
        public Vec3(double x, double y, double z) { X = x; Y = y; Z = z; }
        public static readonly Vec3 Zero = new Vec3(0, 0, 0);
        public static Vec3 operator +(Vec3 a, Vec3 b) { return new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static Vec3 operator -(Vec3 a, Vec3 b) { return new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static Vec3 operator -(Vec3 a) { return new Vec3(-a.X, -a.Y, -a.Z); }
        public static Vec3 operator *(double s, Vec3 a) { return new Vec3(s * a.X, s * a.Y, s * a.Z); }
        public static Vec3 operator *(Vec3 a, double s) { return new Vec3(s * a.X, s * a.Y, s * a.Z); }
        public double Mag { get { return Math.Sqrt(X * X + Y * Y + Z * Z); } }
        public double SqrMag { get { return X * X + Y * Y + Z * Z; } }
        public Vec3 Normalized { get { double m = Mag; return m > 0 ? new Vec3(X / m, Y / m, Z / m) : Zero; } }
        public static double Dot(Vec3 a, Vec3 b) { return a.X * b.X + a.Y * b.Y + a.Z * b.Z; }
        public static Vec3 Cross(Vec3 a, Vec3 b)
        {
            return new Vec3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X);
        }
    }

    public static class K
    {
        public const double D2R = Math.PI / 180.0;
        // kOS's own conversions, measured bit for bit in kOS's VM (peg/vmt/Trig.cs): SIN / COS(deg) = Math.Sin(deg * pi / 180),
        // ARCCOS(x) = Math.Acos(x) * 180 / pi (left to right), E ^ x = Math.Pow(Math.E, x) -- not Math.Exp. The 1-ulp differences of
        // the old forms are amplified to 1e-10 in rbias / vmiss (differences of large vectors).
        public static double Sin(double deg) { return Math.Sin(deg * Math.PI / 180.0); }
        public static double Cos(double deg) { return Math.Cos(deg * Math.PI / 180.0); }
        public static double Acos(double x) { return Math.Acos(x) * 180.0 / Math.PI; }
        public static double Mid(double a, double b, double c) { return Math.Max(Math.Min(a, b), Math.Min(Math.Max(a, b), c)); }
    }

    // the TAL site (asc_peg_tal's tl): ef the site at liftoff (inertial, m), w the body's rotation (deg/s), the I-loads
    public class TalSite
    {
        public Vec3 Ef; public double W; public double[] A = new double[4];
        public double VMIN, VMAX, CRMAX, RDMAG, GAMD;
        public bool Hold, HasIyef; public Vec3 Iyef;   // ops1q's hidden (delayed) TAL: tl:HASKEY("hold") / tl["iyef"]
    }

    // PEG's RTLS (asc_rtls_vel / asc_rtls_correct's p["RTLS"])
    public class RtlsData
    {
        public Vec3 Ef, iy_save; public double W, RTMAG, K, K_CMD, MBO, KMIN, KMAX, DELK_MAX, KMISS, RNG_TURN_PRED, MDOT;
        public double[] A = new double[2]; public bool STHROT, close; public double RTHETA, VGOD, ERR, ERR_C;
    }

    public class Peg
    {
        public static double RTLS_PHIDOT_MAX = 0.05;
        public RtlsData Rtls;                         // null: not an RTLS
        // the I-loads (lib_ascent_iload's ASC_*; the replay sets them from the flight's values)
        public static double DTMAX = 1.0e+20, DTMIN = 2.0, NSEG = 10, AL = 29.108400000000003, ETB = 5.0, KMISS = 0.01,
            RHOMAG = 1.0, PHIDOT_MAX = 0.035, EPSTGO = 0.04, DTRD = 40.0;

        public double RDMAG, GAMD, VDMAG, MASS_MIN, Mu;
        public Vec3 IYD;
        public bool S_INIT = true, S_GDRDY = false, SCONV = false, low_tw = false, SALT = true, SPLANE = true;
        public bool upd = false, tp_ok = false, mass_ok = false, first = false;
        public int N = 2, KPHASE = 1, npass = 0, unconv = 0;
        public double[] TB = new double[3], TGOA = new double[3], TAU = new double[3], VEXA = new double[3],
            LA = new double[3], SA = new double[3], QA = new double[3];
        public Vec3 lamc, lamdc, vgo, lam, lamd, rbias, omega, rgrav, iy, rp, vp, rd, vd, ix, vmiss, rthrust, vthrust;
        public Vec3 rnow, vnow;
        public double tlamc, TGO = 1, PHI, TPRIME, TPREV, TGOP, TP = double.NaN, LAMDMAG, TLAM, tnow, Mnow, VEXnow, ATRnow;
        public double S, L, J, Q, JOL, QPRIME;
        public TalSite Tal;                           // null: the nominal target
        public double tal_rth, tal_cr, tal_tca;

        public Peg(double rdmag, double gamd, double vdmag, Vec3 iyd, double mass_min, double mu)
        {
            RDMAG = rdmag; GAMD = gamd; VDMAG = vdmag; IYD = iyd; MASS_MIN = mass_min; Mu = mu;
        }

        public void SetTal(TalSite tl) { Tal = tl; RDMAG = tl.RDMAG; GAMD = tl.GAMD; }

        // asc_coast: the central-gravity coast over tc s
        public static void Coast(ref Vec3 rr, ref Vec3 vv, double tc, double mu)
        {
            if (tc <= 0) return;
            double h = K.Mid(DTMAX, DTMIN, tc / NSEG);
            double tt = 0;
            while (!(tt >= tc - 1e-9))
            {
                double hh = Math.Min(h, tc - tt);
                Vec3 k1v = (-mu / Math.Pow(rr.Mag, 3)) * rr;
                Vec3 p2 = rr + (0.5 * hh) * vv;
                Vec3 k2r = vv + (0.5 * hh) * k1v;
                Vec3 k2v = (-mu / Math.Pow(p2.Mag, 3)) * p2;
                Vec3 p3 = rr + (0.5 * hh) * k2r;
                Vec3 k3r = vv + (0.5 * hh) * k2v;
                Vec3 k3v = (-mu / Math.Pow(p3.Mag, 3)) * p3;
                Vec3 p4 = rr + hh * k3r;
                Vec3 k4r = vv + hh * k3v;
                Vec3 k4v = (-mu / Math.Pow(p4.Mag, 3)) * p4;
                rr = rr + (hh / 6) * (vv + 2 * k2r + 2 * k3r + k4r);
                vv = vv + (hh / 6) * (k1v + 2 * k2v + 2 * k3v + k4v);
                tt = tt + hh;
            }
        }

        static double[] Abc(double TBv, double TI, double TF, double LAv, double SAv, double QAv, double JOL)
        {
            double C = 60 * (0.5 * TBv * TBv * LAv + 3 * TI * SAv - 3 * (QAv - SAv * JOL)) / Math.Pow(TBv, 5);
            double B = 12 * (0.5 * TBv * LAv - SAv) / Math.Pow(TBv, 3) - C * (TF + TI);
            return new double[] { LAv / TBv - 0.5 * B * (TF + TI) - C * (TBv * TBv / 3 + TI * TF), B, C };
        }

        static Vec3 RotZ(Vec3 u, double th)
        {
            return new Vec3(K.Cos(th) * u.X - K.Sin(th) * u.Y, K.Sin(th) * u.X + K.Cos(th) * u.Y, u.Z);
        }

        void TalVel()
        {
            TalSite tl = Tal;
            double tpp = double.IsNaN(TP) ? tnow + TGO : TP;
            Vec3 rt = RotZ(tl.Ef, tl.W * tpp);
            double rth = tl.Ef.Mag * K.Acos(Math.Max(-1, Math.Min(1, Vec3.Dot(ix, rt.Normalized)))) * K.D2R;
            double[] ca = tl.A;
            VDMAG = K.Mid(tl.VMIN, ca[0] + rth * (ca[1] + rth * (ca[2] + rth * ca[3])), tl.VMAX);
            if (tl.Hold)                          // the twin of asc_tal_vel's hold branch: the speed above, the plane held on the surface
            {
                SPLANE = true;                    // iyef: the great circle of the surface velocity when the hold began (liftoff axes), turned with the body
                iy = IYD;
                if (tl.HasIyef) iy = RotZ(tl.Iyef, tl.W * tpp);
                return;                           // (kOS's RETURN: tal_rth / tal_cr / tal_tca are not set this pass)
            }
            SPLANE = false;
            double tca = rth / VDMAG;
            Vec3 ra = RotZ(tl.Ef, tl.W * (tpp + tca));
            Vec3 iyl = Vec3.Cross(vnow, rnow).Normalized;
            double cr = Vec3.Dot(ra, iyl);
            if (Math.Abs(cr) > tl.CRMAX)
            {
                iyl = Vec3.Cross(vp, rp).Normalized;
                if (cr >= 0) ra = ra - tl.CRMAX * iyl; else ra = ra + tl.CRMAX * iyl;
                iyl = Vec3.Cross(ra, rp).Normalized;
            }
            iy = iyl;
            tal_rth = rth; tal_cr = cr; tal_tca = tca;
        }

        void RtlsVel()
        {
            RtlsData rl = Rtls;
            double tpp = double.IsNaN(TP) ? tnow + TGO : TP;
            Vec3 rt = RotZ(rl.Ef, rl.W * tpp);
            Vec3 iyl = Vec3.Cross(rt, rp).Normalized;
            if (rl.iy_save.Mag == 0) rl.iy_save = iyl;
            double sv = Vec3.Dot(iyl, rl.iy_save);
            double sgn = sv > 0 ? 1 : sv < 0 ? -1 : 0;
            double rth = sgn * (rl.RTMAG * ix - rt).Mag;
            VDMAG = rl.A[0] + rl.A[1] * rth;
            Vec3 vdl = VDMAG * (K.Sin(GAMD) * ix + K.Cos(GAMD) * Vec3.Cross(ix, iyl).Normalized);
            vd = vdl + Vec3.Cross(new Vec3(0, 0, rl.W * K.D2R), rd);
            iy = Vec3.Cross(vd, rd).Normalized;
            rl.RTHETA = rth;
            rl.close = rth < rl.RNG_TURN_PRED;
        }

        void RtlsCorrect()
        {
            RtlsData rl = Rtls;
            Vec3 izl = Vec3.Cross(ix, iy);
            vmiss = vp - vd;
            double ms = Mnow, VEX = VEXnow;
            double VGOD = VEX * Math.Log(Math.Max(ms, rl.MBO * 1.000001) / rl.MBO);
            rl.VGOD = VGOD;
            if (first)
            {
                double gg = Mu / rnow.SqrMag;
                double md = rl.MDOT * rl.K / rl.K_CMD;
                double VGOR = Math.Max(Math.Min(gg * (ms - rl.MBO) / md - Vec3.Dot(vnow, ix), VGOD), -VGOD);
                vgo = VGOR * ix + Math.Sqrt(Math.Max(0, VGOD * VGOD - VGOR * VGOR)) * izl;
                return;
            }
            Vec3 vm = vmiss;
            double VM0 = Vec3.Dot(vm, ix), VM1 = Vec3.Dot(vm, iy), VM2 = Vec3.Dot(vm, izl);
            double LG0 = Vec3.Dot(lam, ix), LG1 = Vec3.Dot(lam, iy), LG2 = Vec3.Dot(lam, izl);
            double VGOMAG = vgo.Mag;
            double ATRF = Math.Min(AL, ATRnow * Math.Pow(Math.E, VGOMAG / VEX));
            double VGRAVX = Vec3.Dot(vp - vnow - vthrust, ix);
            double TGOl = TGO;
            double B1 = 1 + rl.A[1] * (0.5 * TGOl + Vec3.Dot(vnow + 0.5 * vgo, izl) * LG2 / ATRF);
            double B2 = 1 + VGRAVX * LG0 / (ATRF * TGOl);
            double B3 = 1 + VDMAG * TGOl / (2 * Math.Max(rl.RTHETA, 1));
            if (Math.Abs(LG0) < 1e-3 || Math.Abs(VGRAVX) < 1e-6) { vgo = vgo - vm; rl.ERR = VGOMAG - VGOD; return; }
            double KP = rl.K, Kk = KP;
            double B4 = Kk / (VGRAVX * LG0);
            double B5 = B4 * LG0 * VM0 + B4 * LG1 * B2 / B3 * VM1 + B4 * LG2 / B1 * VM2;
            if (rl.STHROT)
            {
                double dk = B5 - B4 * B2 * (VGOMAG - VGOD);
                if (dk < 0) dk = -Math.Min(rl.DELK_MAX, -dk); else dk = Math.Min(rl.DELK_MAX, dk);
                Kk = K.Mid(rl.KMIN, KP + dk, rl.KMAX);
            }
            double ERR = (B5 - (Kk - KP)) / (B4 * B2);
            double dg0 = -((-LG1 / B3 / LG0) * VM1 + (-LG2 / B1 / LG0) * VM2 + ERR / LG0);
            vgo = vgo + dg0 * ix - (VM1 / B3) * iy - (VM2 / B1) * izl;
            rl.K = Kk; rl.ERR = VGOMAG - VGOD; rl.ERR_C = ERR;
        }

        void Tgt(bool cnt)
        {
            bool rtl = Rtls != null;
            if (rtl) SPLANE = false;
            if (SPLANE) rd = rp - Vec3.Dot(rp, iy) * iy; else rd = rp;
            ix = rd.Normalized;
            if (SALT) rd = RDMAG * ix;
            double km = KMISS;
            if (rtl) { RtlsVel(); RtlsCorrect(); km = Rtls.KMISS; }
            else
            {
                if (Tal != null) TalVel();
                vd = VDMAG * (K.Sin(GAMD) * ix + K.Cos(GAMD) * Vec3.Cross(ix, iy).Normalized);
                if (!SPLANE) iy = Vec3.Cross(vd, rd).Normalized;
                vmiss = vp - vd;
                vgo = vgo - RHOMAG * vmiss;
            }
            if (vmiss.Mag > km * vgo.Mag) SCONV = false;
            if (cnt) { if (SCONV) unconv = 0; else unconv = unconv + 1; }
        }

        // asc_peg_cycle: one pass at MET t
        public void Cycle(double t, Vec3 rr, Vec3 vv, Vec3 dvs, double M, double VEX, double ATR)
        {
            npass = npass + 1;
            upd = false; tp_ok = false; mass_ok = false;
            tnow = t; rnow = rr; vnow = vv; Mnow = M; VEXnow = VEX; ATRnow = ATR; first = S_INIT;
            bool firstp = S_INIT;
            double rmag = rr.Mag;
            int Kp = KPHASE;
            if (firstp)
            {
                KPHASE = 1; rbias = Vec3.Zero; PHI = 0; TPRIME = t; TGO = 1;
                omega = Vec3.Zero; rgrav = (-0.5 * Mu / Math.Pow(rmag, 3)) * rr; S_INIT = false;
                TPREV = 0; SALT = true; SPLANE = true; iy = IYD;
                VEXA[0] = VEX; VEXA[1] = VEX; VEXA[2] = VEX;
                rp = rr; vp = vv; vgo = Vec3.Zero;
                Tgt(false);
            }
            else
            {
                vgo = vgo - dvs;
                if (TB[Kp] - (t - TPRIME) <= 0 && Kp < N) { TB[Kp] = 0; TGOA[Kp] = 0; KPHASE = Kp + 1; }
                TPRIME = t;
            }
            double VGOMAG = vgo.Mag;
            Kp = KPHASE;
            TAU[Kp] = VEX / ATR;
            VEXA[Kp] = VEX;
            double LREM = VGOMAG;
            int ip = Kp < N ? 1 : 2;
            double TB1 = TAU[ip] - VEX / AL;
            double LA1 = 0;
            if (TB1 <= ETB) { TB1 = 0; LA1 = 0; KPHASE = N; TGOA[1] = 0; }
            else LA1 = -VEX * Math.Log(1 - TB1 / TAU[ip]);
            if (TB1 > ETB && KPHASE == N) { KPHASE = 1; TAU[1] = TAU[2]; }
            double LA2 = 0, TB2 = 0;
            if (LREM <= LA1) { LA1 = LREM; TB1 = TAU[ip] * (1 - Math.Pow(Math.E, -LA1 / VEX)); }
            else { LA2 = LREM - LA1; TB2 = LA2 / AL; }
            TB[1] = TB1; LA[1] = LA1; TB[2] = TB2; LA[2] = LA2;
            double acs = 0;
            for (int i = KPHASE; i <= N; i++) { acs = acs + TB[i]; TGOA[i] = acs; }
            TGOP = TGO;
            TGO = TGOA[N];
            TP = t + TGO;
            double Lq = 0, Jq = 0, Sq = 0, QQ = 0;
            for (int i = KPHASE; i <= N; i++)
            {
                double TGOB = i != 1 ? TGOA[i - 1] : 0;
                double TBi = TB[i], LAi = LA[i], SAv, QAv;
                if (i < N) { SAv = -LAi * (TAU[i] - TBi) + VEXA[i] * TBi; QAv = SAv * (TAU[i] + TGOB) - 0.5 * VEXA[i] * TBi * TBi; }
                else { SAv = 0.5 * LAi * TBi; QAv = SAv * (TGOB + TBi / 3); }
                SA[i] = SAv; QA[i] = QAv;
                Sq = Sq + (SAv + Lq * TBi); QQ = QQ + (QAv + Jq * TBi); Lq = Lq + LAi; Jq = Jq + (LAi * TGOA[i] - SAv);
            }
            if (Lq <= 0 || VGOMAG <= 0) return;
            double JOLv = Jq / Lq;
            double QPR = QQ - Sq * JOLv;
            double TLAMv = t + JOLv;
            S = Sq; L = Lq; J = Jq; Q = QQ; JOL = JOLv; QPRIME = QPR;
            Vec3 laml = (1 / VGOMAG) * vgo;
            rgrav = Math.Pow(TGO / TGOP, 2) * rgrav;
            Vec3 rgo = rd - (rr + TGO * vv + rgrav) + rbias;
            Vec3 ixl = ix, iyl = iy;
            Vec3 rgop = Vec3.Zero;
            if (!(SALT && SPLANE)) rgop = QPR * Vec3.Cross(omega, laml) + Sq * laml;
            double RGOX = SALT ? Vec3.Dot(rgo, ixl) : Vec3.Dot(rgop, ixl);
            double RGOY = SPLANE ? Vec3.Dot(rgo, iyl) : Vec3.Dot(rgop, iyl);
            Vec3 rgoxy = RGOX * ixl + RGOY * iyl;
            Vec3 izl = Vec3.Cross(ixl, iyl);
            double lamz = Vec3.Dot(laml, izl);   // The divisor is 0 when the thrust direction is exactly radial: floor it (the kOS twin's rule)
            if (Math.Abs(lamz) < 1e-12) lamz = lamz < 0 ? -1e-12 : 1e-12;
            double RGOZ = (Sq - Vec3.Dot(laml, rgoxy)) / lamz;
            rgo = rgoxy + RGOZ * izl;
            Vec3 lamdl = (1 / QPR) * (rgo - Sq * laml);
            double LMAG = lamdl.Mag;
            double lx2 = Math.Pow(Vec3.Dot(laml, ixl), 2);
            double EL_LIMIT = 1e30;
            if (lx2 > 1e-24) EL_LIMIT = Math.Sqrt(Math.Max(0, 1 / lx2 - 1)) / JOLv;
            double phdm = PHIDOT_MAX;
            if (Rtls != null) { phdm = RTLS_PHIDOT_MAX; EL_LIMIT = phdm; }
            double DTA_LIMIT = (0.5 + PHI) / JOLv;
            SCONV = !(LMAG > phdm || LMAG > DTA_LIMIT);
            low_tw = LMAG > EL_LIMIT;
            double LAMDMAX = Math.Min(phdm, Math.Min(DTA_LIMIT, EL_LIMIT));
            if (LMAG > LAMDMAX) { lamdl = (LAMDMAX / LMAG) * lamdl; LMAG = LAMDMAX; rgo = Sq * laml + QPR * lamdl; }
            PHI = JOLv * LMAG;
            lam = laml; lamd = lamdl; LAMDMAG = LMAG; TLAM = TLAMv;
            mass_ok = M * Math.Pow(Math.E, -VGOMAG / VEX) > MASS_MIN;
            tp_ok = Math.Abs(TP - TPREV) < EPSTGO * TGO;
            upd = tp_ok && mass_ok;
            if (upd) { lamc = laml; lamdc = lamdl; tlamc = TLAMv; S_GDRDY = true; }
            TPREV = TP;
            Vec3 rth = Vec3.Zero, vth = Vec3.Zero;
            double TI = -JOLv;
            double IFI = Math.Sqrt(1 + LMAG * LMAG * TI * TI);
            int JJ = LA[N] != 0 ? N : N - 1;
            for (int i = KPHASE; i <= JJ; i++)
            {
                double TBi = TB[i], LAi = LA[i], SAv = SA[i], QAv = QA[i];
                double TF = TI + TBi;
                double IFF = Math.Sqrt(1 + LMAG * LMAG * TF * TF);
                rth = rth + TBi * vth;
                if (LMAG * TBi < 0.090)
                {
                    double gf = 1 / Math.Sqrt(1 + LMAG * LMAG * Math.Abs(TF * TF + TI * TF + TI * TI) / 3);
                    rth = rth + gf * (SAv * laml + (QAv - SAv * JOLv) * lamdl);
                    vth = vth + gf * (LAi * laml + (LAi * TGOA[i] - SAv - LAi * JOLv) * lamdl);
                }
                else
                {
                    double[] abc = i != N ? Abc(TBi, TI, TF, LAi, SAv, QAv, JOLv) : new double[] { AL, 0, 0 };
                    double[] Yl = new double[6];
                    Yl[1] = Math.Log(Math.Abs((TF * LMAG + IFF) / (TI * LMAG + IFI))) / LMAG;
                    Yl[2] = (TF * TF - TI * TI) / (IFI + IFF);
                    double[] Mx = new double[4];
                    for (int xk = 1; xk <= 3; xk++)
                    {
                        Yl[xk + 2] = (IFF * Math.Pow(TF, xk) - IFI * Math.Pow(TI, xk) - xk * Yl[xk]) / ((xk + 1) * LMAG * LMAG);
                        Mx[xk] = abc[0] * Yl[xk] + abc[1] * Yl[xk + 1] + abc[2] * Yl[xk + 2];
                    }
                    rth = rth + (TF * Mx[1] - Mx[2]) * laml + (TF * Mx[2] - Mx[3]) * lamdl;
                    vth = vth + Mx[1] * laml + Mx[2] * lamdl;
                }
                TI = TF;
                IFI = IFF;
            }
            rbias = rgo - rth;
            double TGOv = TGO;
            Vec3 r_init = rr - 0.1 * rth - (TGOv / 30) * vth;
            Vec3 v_init = vv + (1.2 / TGOv) * rth - 0.1 * vth;
            Vec3 cr = r_init, cv = v_init;
            Coast(ref cr, ref cv, TGOv, Mu);
            rgrav = cr - r_init - TGOv * v_init;
            rp = rr + TGOv * vv + rgrav + rth;
            vp = vv + (cv - v_init) + vth;
            rthrust = rth; vthrust = vth;
            Tgt(true);
            if ((SALT || SPLANE) && ((SCONV && TGOv < DTRD) || (TGOv < DTRD - 6 && !firstp)))
            {
                omega = Vec3.Cross(laml, lamdl); SALT = false; SPLANE = false;
            }
        }

        public Vec3 Dir(double t, Vec3 hold)
        {
            if (!S_GDRDY) return hold;
            return (lamc + (t - tlamc) * lamdc).Normalized;
        }
    }
}
