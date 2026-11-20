// the C# coprocessor's fast-time sim, a line-for-line port of lib/lib_ascent_ard.ks's ard_new, ard_on, ard_thr,
// ard_cd, ard_drag, ard_f, ard_cyc, ard_init, ard_step, ard_margin, ard_ato_need and lib_ascent_s2.ks's asc_grav, for
// flights on 2-3 SSMEs (the droop of a 1-SSME flight, ard_droop / asc_drp_pred, is not ported yet: e = 1 is refused).
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    // every ASC_* value the sim reads (the replay fills it from the kOS VM's own values)
    public class FtsConsts
    {
        public double R, MECO_H, GAMD, VDMAG, ATO_VDMAG, MU, J2, R_J2, PL_TO_KSP, FT_FACTOR, AL, TAL_OMS_TGO_OFF,
            ARD_DT, ARD_H_LOW, ARD_T_MAX, ARD_TAL_VGO_TOL, ARD_FOMS, ARD_MDO, ARD_AIR_H0, ARD_ATM_TOP, ARD_AREF,
            ARD_OMS_DV, ARD_W, DRP_MIN_ALT, ATO_H, ATO_DV_DEORBIT, OMS_DV_NOW,
            DRP_THR_MAX, DRP_THR_MIN, DRP_THRESH_ATT, DRP_ATT_INCR, DRP_ALT_DBND, DRP_ALT_PEG_LOSS, DRP_VMISS, DRP_PASS_MAX,
            DRP_NSSME, DRP_ENA, DTGD,
            KMAX_ABORT, RTLS_THETA_0, RTLS_THETA_1, RTLS_THETA_2, RTLS_THETA_3, RTLS_THETA_4, RTLS_THETA_MIN, RTLS_THETA_MAX,
            RTLS_V_SWTCH, RTLS_THETA_FB, RTLS_DUMP_T, RTLS_DUMP_T_LO, RTLS_V_DUMP_SW, KMIN, RTLS_DT_PPD_MARGIN, RTLS_GAMD,
            RTLS_H_PPD, RTLS_DELK_MAX, RTLS_KMISS, RTLS_RNG_TURN_PRED, RTLS_DTHETA_LIM, RTLS_DTHETA_RATE, RTLS_M_BIAS,
            RTLS_ALPHA_PPD, RTLS_THRUST_OFF, RTLS_PPD_RATE, RTLS_T_SETTLE, RTLS_THETA_PPD0, RTLS_PHIDOT_MAX, ARD_RT_TOL,
            ARD_RT_NMAX, ARD_RT_NPPD;
        public double[] RTLS_A_MECO;
        public double[] LNRHO, AS, CDM;
        public const double EU = 2.718281828459045;
    }

    // a trace point (ard_pt's lexicon: the state, the steering, IYD, the dump's schedule)
    public class FtsPt
    {
        public double t, et, om, tlamc; public Vec3 r, v, lamc, lamdc, iy; public double[] o;
        public FtsPt Copy() { var q = (FtsPt)MemberwiseClone(); return q; }
    }

    public class FtsJob
    {
        public bool tr; public List<FtsPt> pts = new List<FtsPt>();   // the trace (ard_new's "tr" / "pts")
        void Pt()
        {
            if (!tr) return;
            pts.Add(new FtsPt { t = t, r = r, v = v, et = et, om = om, lamc = p.lamc, lamdc = p.lamdc, tlamc = p.tlamc, iy = p.IYD,
                o = o.ToArray() });
        }
        public FtsConsts C;
        public string md; public int e; public double K, mc, res, f1, vex, ts = -1;
        public double hstep = -1, hfloor = double.NaN;   // the job's own step (j["dt"]) and MECO floor (j["hf"]), when given
        public double t, t0, et, om; public Vec3 r, v;
        public List<double> o = new List<double>();     // the OMS dump (on, off) or empty
        public Peg p;
        public int kc, st, n;
        public bool down; public double hmin = 1E12; public string why = "";
        Vec3 keepLamc, keepLamdc; double keepTlamc;
        bool cmdOn = false; Vec3 cmd = Vec3.Zero;          // the droop's command (e = 1)
        double T1NEW = 0, THR_ATT = double.NaN, t_on = -1, t_prev = -1; bool S_MIN_ALT, S_DRP_EARLY, S_CDROOP;

        // ard_new
        public FtsJob(FtsConsts c, string mode, TalSite tl, int ne, double Kp, double tt, Vec3 rr, Vec3 vv, double ett,
            double mcore, double reserve, Vec3 iy, Vec3 lamc, Vec3 lamdc, double tlamc, double[] dump, double f1kn, double vexm)
        {
            C = c; md = mode; e = ne; K = Kp; t = tt; t0 = tt; r = rr; v = vv; et = ett; mc = mcore; res = reserve; f1 = f1kn; vex = vexm;
            if (dump != null) { o.Add(dump[0]); o.Add(dump[1]); }
            double vd = mode == "ATO" ? C.ATO_VDMAG : C.VDMAG;
            p = new Peg(C.R + C.MECO_H, C.GAMD, vd, iy, mcore, C.MU);
            if (mode == "TAL") p.SetTal(tl);
            p.lamc = lamc; p.lamdc = lamdc; p.tlamc = tlamc; p.S_GDRDY = true;
            if (e < 1 || K <= 0 || f1 <= 0 || vex <= 0) { st = 2; why = "bad"; }
            THR_ATT = C.DRP_THRESH_ATT;
        }

        public bool On(double tt) { if (o.Count == 0) return false; return o[0] - 0.000000001 <= tt && tt < o[1] - 0.000000001; }

        // LIST(F kN, md t/s, Ft kN, mdt t/s)
        double[] Thr(double M, bool oon)
        {
            double F = K / 100 * C.PL_TO_KSP * f1 * e;
            if (F / M > C.AL) F = C.AL * M;
            double mdd = F / vex;
            if (oon) return new double[] { F, mdd, F + C.ARD_FOMS, mdd + C.ARD_MDO };
            return new double[] { F, mdd, F, mdd };
        }

        double Cd(double mach)
        {
            double[] c = C.CDM;
            if (mach <= c[0]) return c[1];
            for (int i = 2; i < c.Length; i += 2)
                if (mach <= c[i]) return c[i - 1] + (c[i + 1] - c[i - 1]) * (mach - c[i - 2]) / (c[i] - c[i - 2]);
            return c[c.Length - 1];
        }

        Vec3 Drag(Vec3 rr, Vec3 vv, double M)
        {
            double h = rr.Mag - C.R;
            if (h >= C.ARD_ATM_TOP) return Vec3.Zero;
            double lr = C.LNRHO[0], sa = C.AS[0];
            double x = (h - C.ARD_AIR_H0) / 1000;
            if (x > 0)
            {
                int i = (int)Math.Min(Math.Floor(x), C.LNRHO.Length - 2);
                double f = x - i;
                lr = C.LNRHO[i] + f * (C.LNRHO[i + 1] - C.LNRHO[i]);
                sa = C.AS[i] + f * (C.AS[i + 1] - C.AS[i]);
            }
            Vec3 w = new Vec3(vv.X + C.ARD_W * rr.Y, vv.Y - C.ARD_W * rr.X, vv.Z);
            double vr = w.Mag;
            if (vr < 0.000001) return Vec3.Zero;
            return (-0.5 * Math.Pow(FtsConsts.EU, lr) * vr * C.ARD_AREF * Cd(vr / sa) / 1000 / M) * w;
        }

        Vec3 Grav(Vec3 rr)
        {
            double r2 = Vec3.Dot(rr, rr), rm = Math.Sqrt(r2);
            double gm = -C.MU / (r2 * rm);
            double k = -1.5 * C.J2 * C.MU * C.R_J2 * C.R_J2 / (r2 * r2 * rm);
            double zz = 5 * rr.Z * rr.Z / r2;
            return new Vec3(gm * rr.X + k * rr.X * (1 - zz), gm * rr.Y + k * rr.Y * (1 - zz), gm * rr.Z + k * rr.Z * (3 - zz));
        }

        // ard_f: (r', v', et', om', the sensed acceleration)
        void F(double tt, Vec3 rr, Vec3 vv, double ett, double omm, bool oon, Vec3 lam, Vec3 lamd, double TL,
            out Vec3 dr, out Vec3 dv, out double det, out double dom, out Vec3 acc)
        {
            double Mm = mc - omm + ett;
            Vec3 uu = cmd;
            if (!cmdOn || cmd.Mag == 0) uu = (lam + (tt - TL) * lamd).Normalized;
            double a = Math.Min(K / 100 * C.PL_TO_KSP * f1 * e / Mm, C.AL);
            double mdd = a * Mm / vex;
            dom = 0;
            if (oon) { a = a + C.ARD_FOMS / Mm; dom = C.ARD_MDO; }
            acc = a * uu + Drag(rr, vv, Mm);
            dr = vv; dv = Grav(rr) + acc; det = -mdd;
        }

        void Cyc(Vec3 dvs)
        {
            double M = mc - om + et;
            double[] th = Thr(M, On(t));
            p.Cycle(t, r, v, dvs, M, th[2] / th[3], C.FT_FACTOR * th[2] / M);
        }

        void Init()
        {
            if (kc == 0) { keepLamc = p.lamc; keepLamdc = p.lamdc; keepTlamc = p.tlamc; p.S_INIT = true; }
            Cyc(Vec3.Zero);
            kc = kc + 1;
            if (kc < 8 && !(kc >= 2 && p.SCONV)) return;
            p.lamc = keepLamc; p.lamdc = keepLamdc; p.tlamc = keepTlamc;
            double M = mc - om + et;
            double[] th = Thr(M, On(t));
            if (p.SCONV && M * Math.Pow(FtsConsts.EU, -p.vgo.Mag / (th[2] / th[3])) > p.MASS_MIN)
            {
                p.lamc = p.lam; p.lamdc = p.lamd; p.tlamc = p.TLAM;
            }
            if (e == 1) Droop(On(t));
            Pt();
            st = 1;
        }

        void Step()
        {
            bool oon = On(t);
            if (oon && p.TGO < C.TAL_OMS_TGO_OFF) { o[1] = t; oon = false; }
            Vec3 lam = p.lamc, lamd = p.lamdc; double TL = p.tlamc;
            Vec3 rr = r, vv = v; double ett = et, omm = om;
            double[] th = Thr(mc - omm + ett, oon);
            double h = C.ARD_DT;
            if (hstep > 0) h = hstep;
            if (ts >= 0) h = Math.Min(h, ts - t);
            bool cut = p.TGO <= h;
            if (cut) h = Math.Max(p.TGO, 0);
            double tr = (ett - res) / th[1];
            bool rs = tr <= h;
            if (rs) { h = Math.Max(tr, 0); cut = false; }
            if (o.Count > 0)
            {
                foreach (double x in new double[] { o[0], o[1] })
                    if (t + 0.000001 < x && x < t + h - 0.000001) { h = x - t; cut = false; rs = false; }
            }
            Vec3 dvs = Vec3.Zero;
            if (h > 0)
            {
                double h2 = h / 2;
                Vec3 a1r, a1v, a1a, a2r, a2v, a2a, a3r, a3v, a3a, a4r, a4v, a4a; double a1e, a1o, a2e, a2o, a3e, a3o, a4e, a4o;
                F(t, rr, vv, ett, omm, oon, lam, lamd, TL, out a1r, out a1v, out a1e, out a1o, out a1a);
                F(t + h2, rr + h2 * a1r, vv + h2 * a1v, ett + h2 * a1e, omm + h2 * a1o, oon, lam, lamd, TL, out a2r, out a2v, out a2e, out a2o, out a2a);
                F(t + h2, rr + h2 * a2r, vv + h2 * a2v, ett + h2 * a2e, omm + h2 * a2o, oon, lam, lamd, TL, out a3r, out a3v, out a3e, out a3o, out a3a);
                F(t + h, rr + h * a3r, vv + h * a3v, ett + h * a3e, omm + h * a3o, oon, lam, lamd, TL, out a4r, out a4v, out a4e, out a4o, out a4a);
                double h6 = h / 6;
                rr = rr + h6 * (a1r + 2 * a2r + 2 * a3r + a4r);
                vv = vv + h6 * (a1v + 2 * a2v + 2 * a3v + a4v);
                ett = ett + h6 * (a1e + 2 * a2e + 2 * a3e + a4e);
                omm = omm + h6 * (a1o + 2 * a2o + 2 * a3o + a4o);
                dvs = h6 * (a1a + 2 * a2a + 2 * a3a + a4a);
            }
            t = t + h; r = rr; v = vv; et = ett; om = omm;
            double ah = rr.Mag - C.R;
            if (Vec3.Dot(rr, vv) < 0) down = true;
            if (down) hmin = Math.Min(hmin, ah);
            if (cut) why = "cut";
            else if (rs || et <= res + 0.000000001) why = "res";
            else if (down && ah < C.ARD_H_LOW) why = "low";
            else if (t - t0 > C.ARD_T_MAX) why = "time";
            else if (ts >= 0 && t >= ts - 0.000000001) { Cyc(dvs); Pt(); why = "stop"; }
            if (why != "") { st = 2; return; }
            Cyc(dvs);
            if (e == 1) Droop(On(t));
            Pt();
        }


        // asc_drp_pred (lib_ascent_cnt.ks): LIST(ROUT, TNEW, found, in range)
        double[] Pred(double M, double TV_VERT, double TV_HORIZ, double GACC, double MDT, double VGDIY, double TMMAX,
            double VGDIX, double VGDIZ, double RINIT, double TNEW, double GE, double ALT_GD, out bool found, out bool inr)
        {
            found = false; inr = true;
            if (GACC <= 0) { found = true; inr = false; return new double[] { ALT_GD, 0 }; }
            double TMMIN = Math.Max(0, Math.Min((M - TV_VERT / GACC) / MDT, TMMAX - 10));
            double XK1 = GACC - 2 * VGDIZ * TV_HORIZ / (RINIT * MDT) - 2 * TV_HORIZ * TV_HORIZ / (RINIT * MDT * MDT);
            double XK3 = TV_HORIZ * TV_HORIZ * M / (RINIT * Math.Pow(MDT, 3));
            double XK2 = 2 * VGDIZ * TV_HORIZ * M / (RINIT * MDT * MDT) + 2 * XK3;
            double XK4 = (XK2 + XK3) / 2;
            double TVAL = 1, LNV = 0;
            for (int i = 0; i < C.DRP_PASS_MAX; i++)
            {
                TNEW = Math.Max(TMMIN, Math.Min(TNEW, TMMAX));
                TVAL = 1 - MDT * TNEW / M;
                LNV = Math.Log(TVAL);
                double VGRAV = XK1 * TNEW - TVAL * LNV * (XK2 - XK3 * LNV);
                double VOUT = VGDIX - (TV_VERT / MDT) * LNV - VGRAV;
                if (Math.Abs(VOUT) <= C.DRP_VMISS) { found = true; break; }
                double q = VGDIZ - (TV_HORIZ / MDT) * LNV;
                double AGRAV = GE - q * q / RINIT - VGDIY * VGDIY / RINIT;
                double VDT = TV_VERT / (M * TVAL) - AGRAV;
                double TNEXT = TNEW - VOUT / VDT;
                if (TNEW == TMMIN && TNEXT < TMMIN) { inr = false; found = true; break; }
                if (TNEW == TMMAX && TNEXT > TMMAX) { found = true; break; }
                TNEW = TNEXT;
            }
            if (!found) return new double[] { -1E12, TNEW };
            TVAL = 1 - MDT * TNEW / M;
            LNV = Math.Log(TVAL);
            double XK5 = TNEW - MDT * TNEW * TNEW / (2 * M) - M / (2 * MDT);
            double RGRAV = LNV * LNV * XK3 * XK5 - 2 * LNV * XK4 * XK5 + XK4 * TNEW + (TNEW * TNEW / 2) * (XK1 - MDT * XK4 / M);
            return new double[] { ALT_GD + VGDIX * TNEW + TV_VERT * TNEW / MDT + (M / MDT - TNEW) * (TV_VERT / MDT) * LNV - RGRAV, TNEW };
        }

        // ard_droop: FSSR 4.3.4 subtasks 1-3 for the fast-time flight
        void Droop(bool oon)
        {
            double dtgd = C.DTGD;
            if (t_prev >= 0) dtgd = t - t_prev;
            t_prev = t;
            if (S_MIN_ALT) { cmdOn = false; return; }
            double HMIN = C.DRP_MIN_ALT;
            double M = mc - om + et;
            double RINIT = r.Mag;
            Vec3 IR = r.Normalized;
            Vec3 IY = Vec3.Cross(p.lamc, IR).Normalized;
            Vec3 IZ = Vec3.Cross(IR, IY);
            Vec3 PEG_CMD = (p.lamc + (t - p.tlamc) * p.lamdc).Normalized;
            double PEG_ATT = 90 - KalsCoproc.K.Acos(Math.Max(-1, Math.Min(1, Vec3.Dot(PEG_CMD, IR))));
            double VX = Vec3.Dot(v, IR), VY = Vec3.Dot(v, IY), VZ = Vec3.Dot(v, IZ);
            double GE = C.MU / (RINIT * RINIT);
            double GACC = GE - (VY * VY + VZ * VZ) / RINIT;
            double TNEW = T1NEW - dtgd;
            double[] th = Thr(M, oon);
            double TV_MAX = th[2], MDT = th[3];
            if (!S_CDROOP) THR_ATT = C.DRP_THRESH_ATT;
            else if (oon && TNEW > 0)
            {
                double fon = Math.Min(1, (o[1] - t) / TNEW);
                TV_MAX = th[2] * fon + th[0] * (1 - fon);
                MDT = TV_MAX / (th[2] / th[3] * fon + vex * (1 - fon));
            }
            double TMMAX = (M - (mc - om + res)) / MDT;
            bool found, inr;
            double[] pr = Pred(M, TV_MAX * KalsCoproc.K.Sin(THR_ATT), TV_MAX * KalsCoproc.K.Cos(THR_ATT), GACC, MDT, VY, TMMAX, VX, VZ, RINIT, TNEW, GE,
                RINIT - C.R, out found, out inr);
            double ROUT = pr[0];
            if (found)
            {
                T1NEW = pr[1];
                bool S_ATT_CMD = ROUT < HMIN && inr;
                bool S_PEG_OK = !p.low_tw && p.SCONV && PEG_ATT < THR_ATT;
                S_MIN_ALT = S_CDROOP && (T1NEW <= 0 || (S_PEG_OK && ROUT > HMIN + C.DRP_ALT_PEG_LOSS * T1NEW));
                S_CDROOP = !S_MIN_ALT && (S_ATT_CMD || S_CDROOP) && (e < C.DRP_NSSME || (e < 3 && C.DRP_ENA != 0));
            }
            else S_CDROOP = false;
            if (S_CDROOP)
            {
                if (t_on < 0) t_on = t;
                if (ROUT < HMIN) THR_ATT = THR_ATT + C.DRP_ATT_INCR;
                else if (ROUT > HMIN + C.DRP_ALT_DBND * C.DRP_ATT_INCR * 3.141592653589793 / 180) THR_ATT = THR_ATT - C.DRP_ATT_INCR;
                THR_ATT = Math.Max(C.DRP_THR_MIN, Math.Min(THR_ATT, C.DRP_THR_MAX));
                if (!S_DRP_EARLY)
                {
                    THR_ATT = C.DRP_THR_MAX;
                    if (ROUT > HMIN) { S_DRP_EARLY = true; THR_ATT = C.DRP_THR_MIN; }
                }
                if (S_DRP_EARLY) { cmd = (KalsCoproc.K.Sin(THR_ATT) * IR + KalsCoproc.K.Cos(THR_ATT) * IZ).Normalized; cmdOn = true; }
            }
            else cmdOn = false;
        }

        // ard_unit: TRUE when the flight is over
        public bool Unit()
        {
            n = n + 1;
            if (st == 0) Init(); else if (st == 1) Step();
            return st == 2;
        }

        double AtoNeed(Vec3 rr, Vec3 vv)
        {
            double mu = C.MU, rm = rr.Mag, hv = Vec3.Cross(rr, vv).Mag, en = Vec3.Dot(vv, vv) / 2 - mu / rm;
            double ra = 1E30, rp = hv * hv / mu / 2;
            if (en < 0) { double sa = -mu / (2 * en); double ec = Math.Sqrt(Math.Max(0, 1 - hv * hv / (mu * sa))); ra = sa * (1 + ec); rp = sa * (1 - ec); }
            double rat = C.R + C.ATO_H, dv1 = 0;
            if (ra < rat)
            {
                double vh = hv / rm, vh1 = vh;
                if (rm <= rat) vh1 = Math.Sqrt(mu * (2 / rm - 2 / (rat + rm)));
                dv1 = Math.Max(0, vh1 - vh); ra = rat; rp = Math.Min(rm, rat);
            }
            double r2 = Math.Min(rat, ra);
            double dv2 = Math.Abs(Math.Sqrt(mu * (2 / ra - 2 / (ra + r2))) - Math.Sqrt(mu * (2 / ra - 2 / (ra + rp))));
            return dv1 + dv2 + C.ATO_DV_DEORBIT;
        }

        public double Margin()
        {
            double M = mc - om + et, left = et - res, dv = -p.vgo.Mag;
            if (why == "cut") { dv = 0; if (left > 0 && left < M) dv = vex * Math.Log(M / (M - left)); }
            if (md == "PRESS") return dv;
            double hf = double.IsNaN(hfloor) ? C.DRP_MIN_ALT : hfloor;
            double fl = (r.Mag - C.R - hf) / 10;
            if (down) fl = Math.Min(fl, (hmin - C.DRP_MIN_ALT) / 10);
            if (md == "TAL") return Math.Min(dv + C.ARD_TAL_VGO_TOL, fl);
            double odv = C.ARD_OMS_DV;
            if (C.OMS_DV_NOW > 0) odv = C.OMS_DV_NOW;
            return Math.Min(odv - AtoNeed(r, v), fl);
        }
    }

    // NEG RTN (lib_ascent_ard.ks ard_rt_new / ard_rt_unit / ard_rt_lp_step / ard_rt_lp_line): the RTLS's turnaround test
    // at a fixed state; margin = MBO - (MF + M_BIAS), >= 0 = past the negative return, -1 without a solution
    public class RtJob
    {
        FtsConsts C; public Peg p; public double t, M, vex, atr, dt, MF, MBO; public Vec3 r, v, ufd;
        public bool ok; public int nc, st, n; public string why = "";
        double vel, gm, hh, xx, ms, th, tt, f, md;     // the PPD prediction's state (lp)
        public double[] line = new double[2];

        // kOS's VANG = KSP's Vector3d.Angle (its IL): acos(min(max(dot of the normalized, -1), 1)) * 57.29577951308232
        // (acos * 180 / pi, t57's stand-in, differs by an ulp in ~25 % of cases)
        static double Vang(Vec3 a, Vec3 b) { return Math.Acos(Math.Min(Math.Max(Vec3.Dot(a.Normalized, b.Normalized), -1), 1)) * 57.29577951308232; }
        double DtPitch()
        {
            double wp, t1;
            RtlsPpd.Slew(C.RTLS_THETA_PPD0 - (C.RTLS_ALPHA_PPD - C.RTLS_THRUST_OFF), C.RTLS_PPD_RATE, C.RTLS_DTHETA_RATE, out wp, out t1);
            return t1 + C.RTLS_T_SETTLE;
        }

        // sn: mc, res, f1, vex, rs (the RTLS site, inertial at liftoff); P: t, r, v, et, om, iy; cached: a PPD line for this MBO
        public RtJob(FtsConsts c, double sn_mc, double sn_res, double f1, double vexm, Vec3 rs, int ne, double Pt, Vec3 Pr,
            Vec3 Pv, double Pet, double Pom, Vec3 Piy, double[] cachedLine, double cachedMbo)
        {
            C = c;
            double K = C.KMAX_ABORT;
            double mc = sn_mc - Pom;
            M = mc + Pet; r = Pr; v = Pv; t = Pt;
            double wd = C.ARD_W * 57.29577951308232;
            Vec3 vrel = Pv - Vec3.Cross(new Vec3(0, 0, C.ARD_W), Pr);
            Vec3 uv = Pr.Normalized;
            Vec3 hz = (vrel - Vec3.Dot(vrel, uv) * uv).Normalized;
            double vfd = vrel.Mag;
            double thd = C.RTLS_THETA_2 + C.RTLS_THETA_3 * vfd;
            if (vfd < C.RTLS_V_SWTCH) thd = C.RTLS_THETA_0 + C.RTLS_THETA_1 * vfd + C.RTLS_THETA_4 * Vec3.Dot(uv, vrel);
            thd = KalsCoproc.K.Mid(C.RTLS_THETA_MIN, thd, C.RTLS_THETA_MAX);
            ufd = (KalsCoproc.K.Cos(thd) * hz + KalsCoproc.K.Sin(thd) * uv).Normalized;
            Vec3 ufb = (KalsCoproc.K.Cos(C.RTLS_THETA_FB) * hz + KalsCoproc.K.Sin(C.RTLS_THETA_FB) * uv).Normalized;
            double dump = vfd < C.RTLS_V_DUMP_SW ? C.RTLS_DUMP_T_LO : C.RTLS_DUMP_T;
            vex = vexm;
            double md1 = f1 / vex;
            double mk = C.KMIN / 100 * C.PL_TO_KSP * md1 * ne;
            MBO = mc - dump + sn_res + mk * (DtPitch() + C.RTLS_DT_PPD_MARGIN);
            st = 1;
            if (cachedLine != null && Math.Abs(cachedMbo - MBO) <= 0.000001) line = cachedLine;
            else { st = 0; vel = 750; gm = C.RTLS_GAMD * 0.017453292519943295; hh = C.RTLS_H_PPD; xx = 0; ms = MBO; th = C.RTLS_THETA_PPD0; tt = 0; f = mk * vex; md = mk; }
            p = new Peg(C.R + C.MECO_H, C.GAMD, C.VDMAG, Piy, mc, C.MU);
            p.Rtls = new RtlsData { Ef = rs, W = wd, A = line, RTMAG = rs.Mag, iy_save = Vec3.Cross(RotZ(rs, wd * Pt), Pr).Normalized,
                K = K, K_CMD = K, STHROT = false, MBO = MBO, KMIN = C.KMIN, KMAX = K, DELK_MAX = C.RTLS_DELK_MAX, KMISS = C.RTLS_KMISS,
                RNG_TURN_PRED = C.RTLS_RNG_TURN_PRED, MDOT = K / 100 * C.PL_TO_KSP * md1 * ne };
            p.RDMAG = C.R + C.RTLS_H_PPD; p.GAMD = C.RTLS_GAMD; p.MASS_MIN = 0; p.S_INIT = true; p.S_GDRDY = false; p.SCONV = false;
            atr = C.FT_FACTOR * (K / 100 * C.PL_TO_KSP * f1 * ne) / M;
            dt = Vang(ufd, ufb) / C.RTLS_DTHETA_LIM + C.RTLS_DTHETA_LIM / C.RTLS_DTHETA_RATE;
        }

        static Vec3 RotZ(Vec3 u, double th)
        {
            return new Vec3(KalsCoproc.K.Cos(th) * u.X - KalsCoproc.K.Sin(th) * u.Y, KalsCoproc.K.Sin(th) * u.X + KalsCoproc.K.Cos(th) * u.Y, u.Z);
        }

        bool LpStep()
        {
            double tend = DtPitch();
            double th_end = C.RTLS_ALPHA_PPD - C.RTLS_THRUST_OFF;
            double sw, s1, sth = C.RTLS_THETA_PPD0 - th_end;
            RtlsPpd.Slew(sth, C.RTLS_PPD_RATE, C.RTLS_DTHETA_RATE, out sw, out s1);
            int k = 0;
            while (!(tt >= tend - 1e-9 || k >= C.ARD_RT_NPPD))
            {
                double dh = Math.Min(0.02, tend - tt);
                double rad = C.R + hh;
                double gg = C.MU / (rad * rad);
                double ac = f / ms;
                double gd = gm * 57.295779513082323;
                double v1 = vel + (ac * KalsCoproc.K.Cos(th) - gg * KalsCoproc.K.Sin(gd)) * dh;
                double g1 = gm + (ac * KalsCoproc.K.Sin(th) - (gg - vel * vel / rad) * KalsCoproc.K.Cos(gd)) / vel * dh;
                hh = hh + vel * KalsCoproc.K.Sin(gd) * dh;
                xx = xx + vel * KalsCoproc.K.Cos(gd) * dh * C.R / rad;
                vel = v1; gm = g1; ms = ms - md * dh;
                th = C.RTLS_THETA_PPD0 - RtlsPpd.SlewAt(sw, s1, sth, C.RTLS_DTHETA_RATE, tt + dh);
                tt = tt + dh; k = k + 1;
            }
            return tt >= tend - 1e-9;
        }

        double[] LpLine()
        {
            double v0 = 750; double[] am = C.RTLS_A_MECO;
            double pr0 = vel - v0, pr1 = gm * 57.295779513082323 - C.RTLS_GAMD, pr2 = xx;
            double dtp = DtPitch();
            double g = (C.RTLS_GAMD + pr1) * 0.017453292519943295;
            double k = 1 + am[1] * dtp;
            return new double[] { (am[0] - am[1] * (pr2 - v0 * dtp) - am[2] * g - pr0) / k, am[1] / k };
        }

        public bool Unit()
        {
            n = n + 1;
            if (st == 0)
            {
                if (LpStep()) { line = LpLine(); p.Rtls.A = line; st = 1; }
                return false;
            }
            if (st == 2) return true;
            p.Cycle(t + dt, r + dt * v, v, Vec3.Zero, M, vex, vex * atr / (vex - dt * atr));
            nc = nc + 1;
            if (p.Rtls.close) { p.S_INIT = true; p.SCONV = false; }
            else if (p.SCONV && p.npass > 0 && p.LAMDMAG >= 0 && !double.IsNaN(p.TLAM) && p.lam.Mag > 0)
            {
                double mf = M * Math.Pow(FtsConsts.EU, -(p.vgo.Mag + atr * dt) / vex) - C.RTLS_M_BIAS;
                Vec3 uf = (p.lam + (t + dt - p.TLAM) * p.lamd).Normalized;
                dt = Vang(ufd, uf) / C.RTLS_DTHETA_LIM + C.RTLS_DTHETA_LIM / C.RTLS_DTHETA_RATE;
                bool done = ok && Math.Abs(mf - MF) < C.ARD_RT_TOL;
                MF = mf; ok = true;
                if (done) { st = 2; why = "conv"; return true; }
            }
            if (nc >= C.ARD_RT_NMAX) { st = 2; why = "nmax"; }
            return st == 2;
        }

        public double Margin() { if (!ok) return -1; return MBO - MF - C.RTLS_M_BIAS; }
    }
}
