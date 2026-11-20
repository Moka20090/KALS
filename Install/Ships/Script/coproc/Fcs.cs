// the C# coprocessor's pitch loop, a line-for-line port of lib/fcs_pitch.ks (Nz -> alpha: the table + the trim, the
// limits, the slew; TAEM's on tg, A/L's on fc). kOS semantics kept, as Taemg.cs / Alg.cs: the state is kOS-style
// lexicons (Lex), FLOOR = Math.Floor, MIDVAL = taemg_midval, LIST(alpha, sat) returns as (alpha, out sat). The constants
// are NOT typed here: the constructor reads the generated kOS file lib/taemg_const.ks (TG_*). fcs_pitch.ks's memo of the
// lift's Mach factor (fcsLmMach / fcsLmVal) is this object's own (a cache: the same value either way). Checked against
// fcs_vectors.txt by FcsCheck.cs. Compiles with the .NET Framework's csc (C# 5).
using System;
using System.Collections.Generic;
using System.Reflection;

namespace KalsCoproc
{
    public class Fcs
    {
        static double MIN(double a, double b) { return Math.Min(a, b); }
        static double MAX(double a, double b) { return Math.Max(a, b); }
        static double FLOOR(double a) { return Math.Floor(a); }
        static double MIDVAL(double a, double b, double c) { return Taemg.taemg_midval(a, b, c); }

        // ---------------------------------------------------------------- the constants (taemg_const.ks)
#pragma warning disable 0649
        public double TG_NZL_L_LO, TG_NZL_L_HI, TG_NZL_L_STEP, TG_NZL_TAB_N, TG_AOA_SOLVE_LO, TG_AOA_SOLVE_HI, TG_GO,
            TG_P_K_LIFT_V7, TG_ALPULCM1, TG_ALPULC1, TG_ALPULC2, TG_ALPULC3, TG_ALPULC4, TG_ALPULC5, TG_ALPULC6, TG_ALPLLCM1,
            TG_ALPLLCM2, TG_ALPLLC1, TG_ALPLLC2, TG_ALPLLC3, TG_ALPLLC4, TG_ALPLLC5, TG_ALPLLC6, TG_ALPLLC7, TG_ALPLLC8,
            TG_ALPHA_LIM_MAX, TG_NZL_KI, TG_NZL_Q_REF, TG_NZL_Q_MIN, TG_NZL_TRIM_MAX, TG_DTG, TG_NZL_ALPHA_RATE;
        public double[] TG_NZL_ALPHA_OF_L;
        public double[][] TG_P_LIFT_MACH;
#pragma warning restore 0649

        public Fcs(Dictionary<string, object> c)
        {
            foreach (FieldInfo f in typeof(Fcs).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (!f.Name.StartsWith("TG_")) continue;
                if (!c.ContainsKey(f.Name)) throw new KeyNotFoundException("constant " + f.Name + " not in the files");
                object v = c[f.Name];
                if (f.FieldType == typeof(double)) f.SetValue(this, Lex.Num(v));
                else if (f.FieldType == typeof(double[])) f.SetValue(this, Arr(v));
                else if (f.FieldType == typeof(double[][]))
                {
                    var l = (List<object>)v; var a = new double[l.Count][];
                    for (int i = 0; i < l.Count; i++) a[i] = Arr(l[i]);
                    f.SetValue(this, a);
                }
            }
        }

        static double[] Arr(object v)
        {
            var l = (List<object>)v; var a = new double[l.Count];
            for (int i = 0; i < l.Count; i++) a[i] = Lex.Num(l[i]);
            return a;
        }

        // ---------------------------------------------------------------- the table
        public static double fcs_hermite(double[][] keys, double x)   // the Hermite value at x: keys (x, y, in, out)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            for (int i = 1; i < n; i++)
            {
                if (keys[i][0] >= x)
                {
                    double x0 = keys[i - 1][0]; double y0 = keys[i - 1][1]; double o0 = keys[i - 1][3];
                    double x1 = keys[i][0]; double y1 = keys[i][1]; double i1 = keys[i][2];
                    double span = x1 - x0;
                    double t = (x - x0) / span;
                    double m0 = o0 * span;
                    double m1 = i1 * span;
                    double t2 = t * t;
                    double t3 = t2 * t;
                    return ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                            + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1);
                }
            }
            return keys[n - 1][1];
        }

        public double fcs_alpha_of_lift(double l, out int sat)   // alpha for a given lift -> (alpha, sat)
        {
            if (l <= TG_NZL_L_LO) { sat = -1; return TG_AOA_SOLVE_LO; }
            if (l >= TG_NZL_L_HI) { sat = 1; return TG_AOA_SOLVE_HI; }
            double x = (l - TG_NZL_L_LO) / TG_NZL_L_STEP;
            double i = MIN(FLOOR(x), TG_NZL_TAB_N - 2);
            double f = x - i;
            int ii = (int)i;
            sat = 0;
            return TG_NZL_ALPHA_OF_L[ii] + f * (TG_NZL_ALPHA_OF_L[ii + 1] - TG_NZL_ALPHA_OF_L[ii]);
        }

        // the lift's Mach factor, memoised (fcs_pitch.ks's fcsLmMach / fcsLmVal)
        double fcsLmMach = -99999;
        double fcsLmVal = 0;
        public double fcs_lift_mach(double mach)
        {
            if (mach != fcsLmMach)
            {
                fcsLmVal = fcs_hermite(TG_P_LIFT_MACH, mach);
                fcsLmMach = mach;
            }
            return fcsLmVal;
        }

        public double fcs_alpha_ff(double nz, double qb, double mach, out int sat)   // the table alpha -> (alpha, sat)
        {
            if (qb <= 0.0) { sat = -1; return TG_AOA_SOLVE_LO; }
            return fcs_alpha_of_lift(nz * TG_GO / (qb * TG_P_K_LIFT_V7 * fcs_lift_mach(mach)), out sat);
        }

        public double fcs_alpha_ff(double nz, double qb, double mach) { int s; return fcs_alpha_ff(nz, qb, mach, out s); }

        public void fcs_alpha_limits(double mach, double qbar, double qbref, out double ll, out double ul)
        {
            ul = 0;
            ll = 0;
            if (mach < TG_ALPULCM1) ul = MIDVAL(TG_ALPULC1 * mach + TG_ALPULC2, TG_ALPULC3, TG_ALPULC4);
            else ul = MIDVAL(TG_ALPULC5 * mach + TG_ALPULC6, TG_ALPULC3, TG_ALPULC4);
            if (mach < TG_ALPLLCM1) ll = MIDVAL(TG_ALPLLC1 * mach + TG_ALPLLC2, TG_ALPLLC7, TG_ALPLLC8);
            else if (mach < TG_ALPLLCM2) ll = MIDVAL(TG_ALPLLC3 * mach + TG_ALPLLC4, TG_ALPLLC7, TG_ALPLLC8);
            else ll = MIDVAL(TG_ALPLLC5 * mach + TG_ALPLLC6, TG_ALPLLC7, TG_ALPLLC8);
            double shift = MAX(fcs_alpha_ff(1.0, qbar, mach) - fcs_alpha_ff(1.0, MAX(qbref, 1.0), mach), 0.0);
            ul = MIN(ul + shift, TG_ALPHA_LIM_MAX);
        }

        // ---------------------------------------------------------------- TAEM's loop (on tg)
        public double fcs_alpha_cmd(Lex tg, Lex st)    // the alpha command: the table value plus the trim, limited
        {
            int sat;
            double ff = fcs_alpha_ff(tg.N("nz_total"), st.N("qbar"), st.N("mach"), out sat);
            double ll, ul;
            fcs_alpha_limits(st.N("mach"), st.N("qbar"), tg.N("qbref"), out ll, out ul);
            double raw = ff + tg.N("nzl_trim");
            double cmd = raw;
            if (raw > ul) { cmd = ul; sat = 1; }
            else if (raw < ll) { cmd = ll; sat = -1; }
            tg["alpha_ff"] = ff;
            tg["alpha_lim_hi"] = ul;
            tg["nz_sat"] = sat;
            return cmd;
        }

        public void fcs_trim_update(Lex tg, double nz_meas, double qbar)   // the Nz-error integrator (every FD window)
        {
            double err = tg.N("nz_total") - nz_meas;
            tg["nz_meas"] = nz_meas;
            tg["nz_err"] = err;
            if ((tg.N("nz_sat") > 0 && err > 0.0) || (tg.N("nz_sat") < 0 && err < 0.0)) return;
            double k = TG_NZL_KI * TG_NZL_Q_REF / MAX(qbar, TG_NZL_Q_MIN);
            tg["nzl_trim"] = MIDVAL(tg.N("nzl_trim") + k * err * TG_DTG, -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX);
        }

        public double fcs_alpha_slew(Lex tg, double cmd, double dt, double rlim)   // rlim deg/s; -1 = TG_NZL_ALPHA_RATE
        {
            if (TG_NZL_ALPHA_RATE > 0.0 && tg.Has("alpha_rl"))
            {
                double prev = tg.N("alpha_rl");
                double lim = (rlim >= 0 ? rlim : TG_NZL_ALPHA_RATE) * dt;
                if (cmd > prev + lim) { cmd = prev + lim; tg["alpha_rl_bind"] = 1; }
                else if (cmd < prev - lim) { cmd = prev - lim; tg["alpha_rl_bind"] = -1; }
            }
            tg["alpha_rl"] = cmd;
            return cmd;
        }

        public void fcs_window_end(Lex tg, double nz_meas, double qbar)   // the rate limit's binding sign -> anti-windup
        {
            if (tg.N("alpha_rl_bind") != 0 && tg.N("nz_sat") == 0) tg["nz_sat"] = tg["alpha_rl_bind"];
            fcs_trim_update(tg, nz_meas, qbar);
        }

        public void fcs_trim_seed(Lex tg, double a_ent, double nz0, double qbar, double mach)
        {
            tg["nzl_trim"] = MIDVAL(a_ent - fcs_alpha_ff(nz0, qbar, mach), -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX);
            tg["alpha_rl"] = a_ent;
        }

        // ---------------------------------------------------------------- A/L's loop (on fc)
        public double fcs_al_alpha(Lex fc, double nz_total, double qbar, double mach, double dt, double rlim, double amax)
        {
            int sat;
            double ff = fcs_alpha_ff(nz_total, qbar, mach, out sat);
            double ll, ul;
            fcs_alpha_limits(mach, qbar, qbar, out ll, out ul);
            double ahi = MIN(ul, amax);
            double raw = ff + fc.N("trim");
            double cmd = raw;
            if (raw > ahi) { cmd = ahi; sat = 1; }
            else if (raw < ll) { cmd = ll; sat = -1; }
            fc["nz_sat"] = sat;
            fc["alpha_ff"] = ff;
            double rl = (rlim >= 0 ? rlim : TG_NZL_ALPHA_RATE) * dt;
            if (cmd > fc.N("alpha_rl") + rl) { cmd = fc.N("alpha_rl") + rl; fc["rl_bind"] = 1; }
            else if (cmd < fc.N("alpha_rl") - rl) { cmd = fc.N("alpha_rl") - rl; fc["rl_bind"] = -1; }
            fc["alpha_rl"] = cmd;
            return cmd;
        }

        public void fcs_al_trim(Lex fc, double nz_cmd, double nz_meas, double qbar, double dt)   // every A/L FD window
        {
            if (fc.N("rl_bind") != 0 && fc.N("nz_sat") == 0) fc["nz_sat"] = fc["rl_bind"];
            double err = nz_cmd - nz_meas;
            fc["nz_err"] = err;
            if ((fc.N("nz_sat") > 0 && err > 0.0) || (fc.N("nz_sat") < 0 && err < 0.0)) return;
            double k = TG_NZL_KI * TG_NZL_Q_REF / MAX(qbar, TG_NZL_Q_MIN);
            fc["trim"] = MAX(-TG_NZL_TRIM_MAX, MIN(TG_NZL_TRIM_MAX, fc.N("trim") + k * err * dt));
        }
    }
}
