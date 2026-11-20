// The C# coprocessor's A/L guidance, a line-for-line port of lib/alg.ks's per-cycle guidance (FSSR G4.10; the setup and the HUD cues stay kOS). kOS semantics
// kept, as Taemg.cs: the state is kOS-style lexicons (ag, nav: Lex, case-insensitive keys), SIN / COS / TAN / ARCSIN /
// ARCTAN in degrees, LN = natural log, '^' = Math.Pow, the same order of operations. The constants are NOT typed here:
// the constructor reads the generated kOS file lib/alg_const.ks (AL_*) and the one TG_* alg.ks read (TG_NZ_TOTAL_LIM)
// from lib/taemg_const.ks. ag["ret_log"] (the retract log, a kOS LIST no script reads) is not touched here: each entry alg_speedbrake would
// :ADD goes to RetAdds and the bridge (AlgKos) appends them to kOS's list. Checked against alg_vectors.txt by AlgCheck.cs.
// Compiles with the .NET Framework's csc (C# 5).
using System;
using System.Collections.Generic;
using System.Reflection;

namespace KalsCoproc
{
    public class Alg
    {
        // ---------------------------------------------------------------- kOS's built-ins (degrees)
        static double SIN(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double COS(double d) { return Math.Cos(d * Math.PI / 180.0); }
        static double TAN(double d) { return Math.Tan(d * Math.PI / 180.0); }
        static double ARCSIN(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        static double ARCTAN(double x) { return Math.Atan(x) * 180.0 / Math.PI; }
        static double MIN(double a, double b) { return Math.Min(a, b); }
        static double MAX(double a, double b) { return Math.Max(a, b); }
        static double ABS(double a) { return Math.Abs(a); }
        static double SQRT(double a) { return Math.Sqrt(a); }
        static double LN(double a) { return Math.Log(a); }
        static double POW(double a, double b) { return Math.Pow(a, b); }

        // ---------------------------------------------------------------- the constants (alg_const.ks; one of taemg_const.ks)
#pragma warning disable 0649
        public double AL_A_INT, AL_DEG_PER_RAD, AL_DSBC_WW, AL_DT, AL_DT_LAG_NZ, AL_E, AL_FF_SB_H, AL_FF_SB_LIM, AL_FF_SB_OPEN, AL_FF_SB_V, AL_GAMMA_CAPTURE, AL_GAMMA_REF_2, AL_GO, AL_H_CLOOP, AL_H_DECAY,
            AL_H_ERROR_CAPTURE, AL_H_ERROR_MAX, AL_H_FF, AL_H_FLARE, AL_H_INTMX, AL_H_MIN, AL_H_NO_ACC, AL_H_TD1_DOT,
            AL_H_TD2_DOT, AL_H_WL, AL_K_DH, AL_K_DR_DH, AL_K_FLR, AL_K_HDOT_FF, AL_K_HDOT_FSGS, AL_K_HDOT_SGS,
            AL_K_HINT1, AL_K_H_FSGS, AL_K_H_SGS, AL_K_IFLR, AL_K_INT_FSGS, AL_K_SB, AL_K_SBI,
            AL_K_SB_DR, AL_K_Y1, AL_K_YDOT, AL_LAGE_A_13, AL_LAGE_A_14, AL_LAGE_A_3, AL_LAGE_A_40, AL_LAGE_A_VWF, AL_NZC_LIM,
            AL_N_FADER, AL_PHI_M1, AL_PHI_M2, AL_PHI_M3, AL_PSI_CAP, AL_RCO_EAS_DC,
            AL_RCO_H_ARM, AL_RCO_H_GEAR, AL_SB_MAX, AL_SB_MAX_GROUND, AL_SB_MAX_RET, AL_SB_REF, AL_S_DH, AL_S_DR_DH, AL_S_DR_SB, AL_S_DR_VEL, AL_S_DR_WIND, AL_TAU_GAMMA,
            AL_TAU_TD, AL_TAU_TD1, AL_TAU_TD2, AL_TQ_LAT, AL_T_Q, AL_V_LIMIT, AL_X_AIM_PT,
            AL_Y_CAP, AL_Y_INLIM, AL_Y_LIMIT, AL_KT, AL_FSGS_C4_FADE,
            AL_ORB_MASS, AL_TDV_H_OFF, AL_TDV_K, AL_TDV_KI, AL_TD_KEAS_TARGET, AL_TD_KEAS_TARGET_SF, AL_TD_KEAS_FLOOR_SF,
            AL_SB_SENSE_KNEE, AL_SB_SENSE_K, AL_SB_OGS_0;
        public bool AL_FF_SB_RETRACT, AL_RCO_ENABLE,
            AL_RETRACT_SB_TERM, AL_TDV_ON;
        public double[] AL_A_DR_WT, AL_B_DR_WT, AL_GAMMA_REF_1, AL_H_SBR_TABLE, AL_SB_MAX_TD, AL_SIGMA,
            AL_S_SB_DR, AL_V_REF, AL_X_ZERO, AL_TDV_H, AL_TDV_DV, AL_TDV_DV_SF, AL_SB_OGS_WT_MR, AL_SB_OGS_WT,
            AL_SB_SENSE_F_MR, AL_SB_SENSE_F;
        public double[][] AL_H_K, AL_K_R_TAB, AL_R_FLARE, AL_X_EXP_T, AL_X_K, AL_X_TAN;
        public double TG_NZ_TOTAL_LIM;
#pragma warning restore 0649

        // the entries alg_speedbrake :ADDs to ag["ret_log"] (the caller clears it before a pass, the bridge appends them)
        public List<Lex> RetAdds = new List<Lex>();

        // Setup: every AL_* field (and the two TG_*) from the parsed constant files (a field missing in them is an error)
        public Alg(Dictionary<string, object> c)
        {
            foreach (FieldInfo f in typeof(Alg).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (!(f.Name.StartsWith("AL_") || f.Name.StartsWith("TG_"))) continue;
                if (!c.ContainsKey(f.Name)) throw new KeyNotFoundException("constant " + f.Name + " not in the files");
                object v = c[f.Name];
                if (f.FieldType == typeof(double)) f.SetValue(this, Lex.Num(v));
                else if (f.FieldType == typeof(bool)) f.SetValue(this, (bool)v);
                else if (f.FieldType == typeof(double[])) f.SetValue(this, Arr(v));
                else if (f.FieldType == typeof(double[][]))
                {
                    var l = (List<object>)v; var a = new double[l.Count][];
                    for (int i = 0; i < l.Count; i++) a[i] = Arr(l[i]);
                    f.SetValue(this, a);
                }
                else if (f.FieldType == typeof(Lex)) f.SetValue(this, (Lex)v);
            }
        }

        static double[] Arr(object v)
        {
            var l = (List<object>)v; var a = new double[l.Count];
            for (int i = 0; i < l.Count; i++) a[i] = Lex.Num(l[i]);
            return a;
        }

        static int I(double x) { return (int)x; }       // a table index (igs - 1, sb_mode - 1: whole numbers)

        // ---------------------------------------------------------------- helpers
        public static double alg_slimit(double x, double a)
        {
            if (x < -a) return -a;
            if (x > a) return a;
            return x;
        }

        public static double alg_alimit(double x, double a, double b)    // x limited to a..b
        {
            if (x < a) return a;
            if (x > b) return b;
            return x;
        }

        public static double alg_lag(double y_prev, double ef, double x)  // lag step, with ef = exp(-a DT) precomputed
        {
            return ef * y_prev + (1.0 - ef) * x;
        }

        public static double alg_asind(double x)                         // asin, in degrees
        {
            return ARCSIN(MAX(-1.0, MIN(1.0, x)));
        }

        public double alg_k_r_of(double qbar)          // K_R at qbar (Pa): AL_K_R_TAB, linear between rows, held at the ends
        {
            double[][] tab = AL_K_R_TAB;
            int n = tab.Length;
            if (qbar <= tab[0][0]) return tab[0][1];
            if (qbar >= tab[n - 1][0]) return tab[n - 1][1];
            for (int i = 1; i < n; i++)
            {
                if (qbar <= tab[i][0])
                {
                    double q0 = tab[i - 1][0]; double k0 = tab[i - 1][1];
                    double q1 = tab[i][0]; double k1 = tab[i][1];
                    return k0 + (k1 - k0) * (qbar - q0) / (q1 - q0);
                }
            }
            return tab[n - 1][1];
        }

        // ---------------------------------------------------------------- the pitch channel
        public void alg_pitch_trajectory(Lex ag, Lex nav)
        {
            int i = I(ag.N("igs")) - 1;
            int j = I(ag.N("igi")) - 1;
            ag["v_t_filt"] = alg_lag(ag.N("v_t_filt"), AL_LAGE_A_13, nav.N("tas"));
            ag["v_wind_x"] = nav.N("v_g") - ag.N("v_t_filt") * COS(ARCSIN(MAX(-1.0, MIN(1.0, nav.N("h_dot") / MAX(ag.N("v_t_filt"), 1.0)))));
            double dx = nav.N("x") - AL_X_AIM_PT;
            ag["r_gnd_ap"] = SQRT(dx * dx + nav.N("y") * nav.N("y"));
            double pm = ag.N("p_mode");
            bool steep = pm == 1 || pm == 2 || (pm == 3 && ag.N("f_mode") < 2);
            if (steep)
            {
                double psi_cor = 0.0;
                if (ABS(dx) > 1e-9) psi_cor = ARCTAN(nav.N("y") / dx);
                double x_zero_cor = (AL_X_ZERO[j] + AL_X_AIM_PT) * COS(psi_cor);
                ag["h_ref"] = (x_zero_cor - ag.N("r_gnd_ap")) * TAN(AL_GAMMA_REF_1[i]);
                ag["gamma_ref"] = AL_GAMMA_REF_1[i];
            }
            else
            {
                ag["h_ref"] = -ag.N("r_gnd_ap") * TAN(AL_GAMMA_REF_2);
                ag["gamma_ref"] = AL_GAMMA_REF_2;
            }
            if (ag.N("p_mode") == 3 && ag.N("f_mode") > 1)
            {
                ag["gamma_error"] = ag.N("gamma_ref") - nav.N("gamma");
            }
            else
            {
                ag["h_error"] = ag.N("h_ref") - nav.N("h");
                ag["gamma_error"] = ag.N("gamma_ref") - nav.N("gamma");
                ag["h_dot_error"] = nav.N("v_i") * SIN(ag.N("gamma_ref")) - nav.N("h_dot");
            }
            if (AL_RCO_ENABLE)
            {
                if (nav.N("h") < AL_RCO_H_ARM) ag["rco_lg_arm"] = true;
                if (nav.N("h") < AL_RCO_H_GEAR) ag["rco_lg_deploy"] = true;
                if (ag.B("wowlon") && nav.N("eas") < AL_RCO_EAS_DC)
                {
                    ag["rco_dc_arm"] = true;
                    ag["rco_dc_deploy"] = true;
                }
            }
        }

        public void alg_trajectory_capture(Lex ag, Lex nav)   // p_mode 1: the glideslope law until captured, then p_mode 2
        {
            if (ABS(ag.N("gamma_error")) < AL_GAMMA_CAPTURE) ag["tq_n"] = ag.N("tq_n") + 1; else ag["tq_n"] = 0;
            if ((ABS(ag.N("gamma_error")) < AL_GAMMA_CAPTURE && ABS(ag.N("h_error")) < AL_H_ERROR_CAPTURE)
                    || ag.N("tq_n") * AL_DT > AL_T_Q + 1e-9)
            {
                ag["p_mode"] = 2;
            }
            alg_steep_gs(ag, nav, true);
        }

        public void alg_steep_gs(Lex ag, Lex nav, bool via_tc)   // the steep glideslope's Nz; below AL_H_FLARE the flare
        {
            if (ag.N("p_mode") == 2 && !via_tc && !ag.B("sgs_init"))
            {
                ag["k_hint"] = AL_K_HINT1;
                ag["k_c1g"] = AL_K_HDOT_SGS;
                ag["k_c2h"] = AL_K_H_SGS;
                ag["sgs_init"] = true;
            }
            if (nav.N("h") < AL_H_FLARE) ag["p_mode"] = 3;
            ag["nz_c1"] = ag.N("k_c1g") * ag.N("h_dot_error");
            ag["nz_c2h"] = ag.N("k_c2h") * alg_slimit(ag.N("h_error"), AL_H_ERROR_MAX);
            double nz_c2i_dot = ag.N("k_hint") * alg_slimit(ag.N("h_error"), AL_H_INTMX);
            ag["nz_c2i"] = ag.N("nz_c2i") + nz_c2i_dot * AL_DT;
            if (!ag.B("autop")) ag["nz_c2i"] = 0.0;
            ag["nz_c2"] = ag.N("nz_c2h") + ag.N("nz_c2i");
            ag["nz_c"] = ag.N("nz_c1") + ag.N("nz_c2");
        }

        public void alg_circle(Lex ag, double x, double v_g, int i, int j)   // the closed-loop flare circle
        {
            if (x < AL_X_TAN[i][j])
            {
                ag["h_ref_t"] = (-AL_X_ZERO[j] - x) * TAN(-AL_GAMMA_REF_1[i]);
                ag["h_ref_t_dot"] = v_g * TAN(AL_GAMMA_REF_1[i]);
                return;
            }
            double dxk = x - AL_X_K[i][j];
            if (POW(AL_R_FLARE[i][j], 2) - dxk * dxk <= 0.0)        // past the circle's far end: the shallow glide slope
            {
                ag["h_ref_t"] = -ag.N("r_gnd_ap") * TAN(AL_GAMMA_REF_2);
                ag["h_ref_t_dot"] = v_g * TAN(AL_GAMMA_REF_2);
                return;
            }
            ag["h_ref_t"] = AL_H_K[i][j] - SQRT(MAX(POW(AL_R_FLARE[i][j], 2) - dxk * dxk, 0.0));
            ag["h_ref_t_dot"] = -v_g * dxk / (ag.N("h_ref_t") - AL_H_K[i][j]);
        }

        public void alg_fsgs(Lex ag, Lex nav)          // the flare onto the shallow glide slope
        {
            int i = I(ag.N("igs")) - 1;
            int j = I(ag.N("igi")) - 1;
            double x = nav.N("x");
            double h = nav.N("h");
            double h_dot = nav.N("h_dot");
            double v_g = nav.N("v_g");
            if (!ag.B("fsgs_init"))
            {
                ag["nz_c2i"] = 0.0;
                ag["gamma_c3"] = 0.0;
                ag["f_mode"] = 1;
                ag["retract_bf"] = true;
                ag["gamma_air_sync"] = alg_asind(h_dot / MAX(ag.N("v_t_filt"), 1.0));
                ag["nz_c3_lag"] = 0.0;
                ag["c4_fade"] = 0.0;
                ag["fsgs_init"] = true;
            }
            if (ag.N("f_mode") == 2)
            {
                if (x > AL_X_EXP_T[i][j]) ag["f_mode"] = 3;
                else alg_circle(ag, x, v_g, i, j);
            }
            ag["h_final_flare"] = AL_TAU_TD * (AL_H_TD2_DOT - h_dot) + AL_H_NO_ACC;
            if (ag.N("f_mode") == 3 && h < AL_H_FF && h < ag.N("h_final_flare")) ag["p_mode"] = 4;
            if (h < AL_H_MIN) ag["p_mode"] = 4;
            if (ag.N("f_mode") == 3)
            {
                double h_errorx = AL_H_DECAY * POW(AL_E, (AL_X_EXP_T[i][j] - x) / AL_SIGMA[i]);
                ag["h_ref_t"] = ag.N("h_ref") + h_errorx;
                ag["h_ref_t_dot"] = v_g * (TAN(AL_GAMMA_REF_2) - h_errorx / AL_SIGMA[i]);
            }
            if (ag.N("f_mode") == 1)
            {
                if (h < AL_H_CLOOP)
                {
                    ag["f_mode"] = 2;
                    alg_circle(ag, x, v_g, i, j);
                }
                else
                {
                    ag["nz_c4"] = 0.0;
                }
            }
            if (ag.N("f_mode") != 1)
            {
                ag["h_error"] = ag.N("h_ref_t") - h;
                ag["h_dot_error"] = ag.N("h_ref_t_dot") - h_dot;
                ag["nz_c2h"] = AL_K_H_FSGS * ag.N("h_error");
                ag["nz_c2i"] = ag.N("nz_c2i") + AL_K_INT_FSGS * ag.N("nz_c2h") * AL_DT;
                if (!ag.B("autop")) ag["nz_c2i"] = 0.0;
                ag["nz_c4"] = ag.N("nz_c2h") + AL_K_HDOT_FSGS * ag.N("h_dot_error") + ag.N("nz_c2i");
                if (AL_FSGS_C4_FADE > 0.0)                // faded in from the closed loop's start
                {
                    ag["c4_fade"] = MIN(1.0, ag.N("c4_fade") + AL_DT / AL_FSGS_C4_FADE);
                    ag["nz_c4"] = ag.N("nz_c4") * ag.N("c4_fade");
                }
            }
            double nzc_max = POW(nav.N("v_i"), 2) / AL_R_FLARE[i][j];
            double gamma_dot_max = AL_DEG_PER_RAD * nzc_max / MAX(ag.N("v_t_filt"), 1.0);
            ag["gamma_c3_dot"] = alg_slimit((AL_GAMMA_REF_2 - ag.N("gamma_air_sync") - ag.N("gamma_c3")) / AL_TAU_GAMMA, gamma_dot_max);
            ag["gamma_c3"] = ag.N("gamma_c3") + ag.N("gamma_c3_dot") * AL_DT;
            ag["nz_c3_lag"] = alg_lag(ag.N("nz_c3_lag"), AL_LAGE_A_40, ag.N("v_t_filt") * ag.N("gamma_c3_dot") / (AL_DEG_PER_RAD * AL_GO));
            ag["nz_c3"] = ag["nz_c3_lag"];
            ag["nz_c"] = ag.N("nz_c3") + ag.N("nz_c4");
        }

        public void alg_final_flare(Lex ag, Lex nav)   // the final flare: Nz toward the touchdown sink rate, until WOW
        {
            double h = nav.N("h");
            double h_dot = nav.N("h_dot");
            if (!ag.B("ff_init"))
            {
                ag["h_ref_dot"] = h_dot;
                ag["h_dot_c3"] = h_dot;
                ag["nz_c1i_int"] = 0.0;
                ag["h_dot_syn"] = ag.N("nz_c") / AL_K_HDOT_FF;
                ag["ff_init"] = true;
            }
            if (ag.B("wowlon")) return;
            double h_ddot_c3 = (AL_H_TD1_DOT + ag.N("h_dot_syn") - ag.N("h_dot_c3")) / AL_TAU_TD1;
            ag["h_dot_c3"] = ag.N("h_dot_c3") + h_ddot_c3 * AL_DT;
            ag["nz_c3"] = AL_K_FLR * h_ddot_c3;
            double h_d = MAX(h - AL_H_NO_ACC, 0.0);
            double h_ref_uf_dot = AL_H_TD2_DOT - h_d / AL_TAU_TD2;
            ag["h_ref_dot"] = alg_lag(ag.N("h_ref_dot"), AL_LAGE_A_3, h_ref_uf_dot);
            ag["nz_c1h"] = AL_K_HDOT_FF * (ag.N("h_ref_dot") - h_dot);
            ag["nz_c1i_int"] = ag.N("nz_c1i_int") + ag.N("nz_c1h") * AL_DT;
            ag["nz_c1i"] = AL_K_IFLR * ag.N("nz_c1i_int");
            ag["nz_c1"] = ag.N("nz_c1h") + ag.N("nz_c1i");
            ag["nz_c"] = ag.N("nz_c1") + ag.N("nz_c3");
        }

        public void alg_nz_compensate(Lex ag)          // nzc: nz_c with a lead of AL_DT_LAG_NZ s, limited to +-AL_NZC_LIM
        {
            if (!ag.Has("nz_cp")) ag["nz_cp"] = ag["nz_c"];
            double nz_comp = ag.N("nz_c") + AL_DT_LAG_NZ * (ag.N("nz_c") - ag.N("nz_cp")) / AL_DT;
            ag["nzc"] = alg_slimit(nz_comp, AL_NZC_LIM);
            if (ag.Has("nzf_n") && ag.N("nzf_n") > 0)  // the pitch fader (alg_init), from TAEM's NZC onto A/L's
            {
                if (!ag.Has("nzf_b")) ag["nzf_b"] = (ag.N("nzf_at") - ag.N("nzc")) / ag.N("nzf_n");
                ag["nzc"] = alg_slimit(ag.N("nzc") + ag.N("nzf_b") * ag.N("nzf_n"), AL_NZC_LIM);
                ag["nzf_n"] = ag.N("nzf_n") - 1;
            }
            ag["nz_cp"] = ag["nz_c"];
        }

        // ---------------------------------------------------------------- the speedbrake (the retract)
        // what the retract's OGS-brake term reads (al_sim al_sb_knee / al_sb_sense; kOS alg_sb_knee / alg_sb_sense)
        double alg_sb_knee(double h)
        {
            return h <= AL_SB_SENSE_KNEE ? h : AL_SB_SENSE_KNEE + AL_SB_SENSE_K * (h - AL_SB_SENSE_KNEE);
        }
        double alg_sb_sense(double ogs, double mass)
        {
            if (mass <= AL_ORB_MASS) return alg_sb_knee(ogs);
            double mr = mass / AL_ORB_MASS;
            double[] xs = AL_SB_OGS_WT_MR, ys = AL_SB_OGS_WT;
            double e = ys[ys.Length - 1];
            for (int k = 0; k < xs.Length - 1; k++)
                if (mr < xs[k + 1]) { e = ys[k] + (ys[k + 1] - ys[k]) * (mr - xs[k]) / (xs[k + 1] - xs[k]); break; }
            double[] fx = AL_SB_SENSE_F_MR, fy = AL_SB_SENSE_F;      // the gain by WEIGHT / ORB_MASS
            double f = fy[fy.Length - 1];
            for (int k = 0; k < fx.Length - 1; k++)
                if (mr < fx[k + 1]) { f = fy[k] + (fy[k + 1] - fy[k]) * (mr - fx[k]) / (fx[k + 1] - fx[k]); break; }
            return AL_SB_OGS_0 + f * (alg_sb_knee(ogs) - alg_sb_knee(AL_SB_OGS_0 + e));
        }

        public void alg_speedbrake(Lex ag, Lex nav)
        {
            int i = I(ag.N("igs")) - 1;
            double h = nav.N("h");
            if (!ag.B("sbc_init"))
            {
                ag["eas_filt"] = nav["eas"];
                ag["v_wind_filt"] = ag["v_wind_x"];
                ag["delta_sbi"] = 0.0;
                ag["delta_ti"] = 0.0001;
                ag["v_wind_int"] = 0.0;
                ag["hud_sb_retract"] = false;
                ag["sb_lim"] = AL_SB_MAX;
                ag["dsbc_al"] = AL_SB_REF;
                ag["sb_mode"] = 1;
                ag["v_err_filt"] = nav.N("eas") - AL_V_REF[i];
                ag["dr_ci_xo"] = ag.N("igi") == 2 ? (AL_X_ZERO[0] - AL_X_ZERO[1]) : 0.0;
                ag["dr_srw"] = ag["k_dr_srw"];
                ag["dr_wt"] = 0.0;
                ag["dr_v_error"] = 0.0;
                ag["tdv_i"] = 0.0;
                ag["tdv_e"] = 0.0;
                ag["dsbc_ret"] = AL_SB_REF;
                ag["sbc_init"] = true;
            }
            if (!ag.B("wowlon"))
            {
                ag["eas_filt"] = alg_lag(ag.N("eas_filt"), AL_LAGE_A_14, nav.N("eas"));
                ag["v_wind_filt"] = alg_lag(ag.N("v_wind_filt"), AL_LAGE_A_VWF, ag.N("v_wind_x"));
            }
            if (ag.N("sb_mode") == 1)
            {
                ag["v_error"] = ag.N("eas_filt") - AL_V_REF[i];
                ag["v_err_filt"] = alg_lag(ag.N("v_err_filt"), AL_LAGE_A_VWF, ag.N("v_error"));
                double delta_sbe = AL_K_SB * ag.N("v_error");
                double del_int = AL_K_SBI * alg_slimit(ag.N("v_error"), AL_V_LIMIT);
                if (ag.N("dsbc_al") >= AL_SB_MAX || ag.N("dsbc_al") <= 0.0 || ag.N("p_mode") == 1) del_int = 0.0;
                ag["delta_sbi"] = ag.N("delta_sbi") + del_int * AL_DT;
                ag["dsbc_al"] = delta_sbe + ag.N("delta_sbi") + AL_SB_REF;
                ag["delta_sbe"] = delta_sbe;
            }
            bool retract = false;
            if (h < AL_H_SBR_TABLE[0] && ag.N("sb_mode") == 1)
            {
                ag["dsbc_ogs"] = ag["dsbc_al"];
                ag["hud_sb_retract"] = true;
                ag["dr_wt"] = AL_A_DR_WT[i] + AL_B_DR_WT[i] * LN(ag.N("mass")) + ag.N("dr_wt_hv");
                ag["dr_v_error"] = AL_S_DR_VEL * ag.N("v_err_filt");
                ag["sb_lim"] = AL_SB_MAX_RET;
                retract = true;
            }
            if (h >= AL_H_SBR_TABLE[1] && ag.N("sb_mode") == 2)
            {
                ag["v_wind_int"] = ag.N("v_wind_int") + ag.N("v_wind_filt") * AL_DT;
                ag["delta_ti"] = ag.N("delta_ti") + AL_DT;
            }
            if (h < AL_H_SBR_TABLE[1] && ag.N("sb_mode") == 2)
            {
                ag["v_wind_filt"] = ag.N("v_wind_int") / ag.N("delta_ti");
                ag["sb_lim"] = ag.N("i_short_rw") == 0 ? AL_SB_MAX_TD[0] : AL_SB_MAX_TD[1];
                retract = true;
            }
            if (retract)
            {
                double d_h = AL_S_DH * POW(ag.N("eas_filt") / MAX(ag.N("v_t_filt"), 1.0), 2) + AL_K_DH - AL_H_SBR_TABLE[I(ag.N("sb_mode")) - 1];
                double dr_dh = AL_S_DR_DH * d_h + AL_K_DR_DH;
                double dr_wind = AL_S_DR_WIND * ag.N("v_wind_filt");
                ag["dr_total"] = (ag.N("dr_wt") + ag.N("dr_v_error") + dr_dh + dr_wind + ag.N("dr_ci_xo") + ag.N("dr_srw"));
                if (AL_RETRACT_SB_TERM) ag["dr_total"] = ag.N("dr_total") + AL_S_DR_SB * (alg_sb_sense(ag.N("dsbc_ogs"), ag.N("mass")) - AL_SB_REF);
                ag["d_h"] = d_h;
                ag["dsbc_al"] = alg_alimit(AL_S_SB_DR[i] * ag.N("dr_total") + AL_K_SB_DR, 0.0, ag.N("sb_lim"));
                ag["dsbc_ret"] = ag["dsbc_al"];         // TDV's base
                var rl = new Lex();
                rl["h"] = h; rl["sb_mode"] = ag["sb_mode"]; rl["dsbc"] = ag["dsbc_al"]; rl["dr_total"] = ag["dr_total"];
                rl["d_h"] = d_h; rl["x"] = nav["x"];
                RetAdds.Add(rl);
                ag["sb_mode"] = ag.N("sb_mode") + 1;
            }
            // the final-flare brake (AL_FF_SB_RETRACT; a deviation from G4.10, nominal runways only)
            if (AL_FF_SB_RETRACT && ag.N("p_mode") == 4 && !ag.B("wowlon") && ag.N("i_short_rw") == 0)
            {
                if (h < AL_FF_SB_H) ag["dsbc_al"] = MIN(ag.N("dsbc_al"), AL_FF_SB_LIM);
                else if (ag.N("eas_filt") > AL_FF_SB_V) ag["dsbc_al"] = MIN(MAX(ag.N("dsbc_al"), AL_FF_SB_OPEN), ag.N("sb_lim"));
            }
            // the touchdown speed (al_sim's TDV): from the 3000 ft retract to AL_TDV_H_OFF, the retract's setting plus a PI correction
            // on the predicted touchdown EAS against the weight-scaled target (short-runway option: AL_TD_KEAS_TARGET_SF,
            // floored at AL_TD_KEAS_FLOOR_SF)
            if (AL_TDV_ON && !ag.B("wowlon") && ag.N("sb_mode") >= 2 && h >= AL_TDV_H_OFF)
            {
                bool sf = ag.N("i_short_rw") != 0;
                double v_tgt = (sf ? AL_TD_KEAS_TARGET_SF : AL_TD_KEAS_TARGET) * AL_KT * SQRT(ag.N("mass") / AL_ORB_MASS);
                if (sf) v_tgt = Math.Max(v_tgt, AL_TD_KEAS_FLOOR_SF * AL_KT);
                double e = nav.N("eas") - alg_tdv_dv(h, sf) - v_tgt;
                ag["tdv_e"] = e;
                double u = ag.N("dsbc_ret") + AL_TDV_K * e + ag.N("tdv_i");
                if (!((u >= ag.N("sb_lim") && e > 0.0) || (u <= 0.0 && e < 0.0)))
                    ag["tdv_i"] = ag.N("tdv_i") + AL_TDV_KI * e * AL_DT;
                ag["dsbc_al"] = alg_alimit(ag.N("dsbc_ret") + AL_TDV_K * e + ag.N("tdv_i"), 0.0, ag.N("sb_lim"));
            }
            if (ag.B("wowlon")) ag["dsbc_al"] = AL_DSBC_WW;
            ag["dsbc_al"] = alg_alimit(ag.N("dsbc_al"), 0.0, ag.B("wowlon") ? AL_SB_MAX_GROUND : AL_SB_MAX);
        }

        // m/s, the EAS lost from the guidance's height h (m) to the touchdown (alg_tdv_dv)
        double alg_tdv_dv(double h, bool sf)
        {
            double[] tab = sf ? AL_TDV_DV_SF : AL_TDV_DV;
            if (h >= AL_TDV_H[0]) return tab[0];
            for (int k = 0; k < AL_TDV_H.Length - 1; k++)
                if (h >= AL_TDV_H[k + 1])
                    return tab[k + 1] + (tab[k] - tab[k + 1]) * (h - AL_TDV_H[k + 1]) / (AL_TDV_H[k] - AL_TDV_H[k + 1]);
            return tab[tab.Length - 1] * MAX(h, 0.0) / AL_TDV_H[AL_TDV_H.Length - 1];
        }

        // ---------------------------------------------------------------- the lateral channel
        public void alg_roll(Lex ag, Lex nav)
        {
            if (ag.N("lat_mode") == 1)
            {
                bool psi_ok = ABS(nav.N("psi_gnd")) < AL_PSI_CAP;
                if (psi_ok) ag["psi_n"] = ag.N("psi_n") + 1; else ag["psi_n"] = 0;
                if ((psi_ok && ABS(nav.N("y")) < AL_Y_CAP) || ag.N("psi_n") * AL_DT > AL_TQ_LAT + 1e-9) ag["lat_mode"] = 2;
            }
            if (ag.B("autory")) ag["phi_max"] = nav.N("h") > AL_H_WL ? AL_PHI_M1 : AL_PHI_M2;
            else ag["phi_max"] = AL_PHI_M3;
            double y_error = alg_slimit(nav.N("y"), AL_Y_LIMIT);
            double y_int_dot = alg_slimit(y_error, AL_Y_INLIM);
            double phi_cmd = -AL_K_Y1 * (y_error + AL_K_YDOT * nav.N("y_dot"));
            ag["y_int"] = ag.N("y_int") + y_int_dot * AL_DT;
            if (!ag.B("autory") || ag.N("lat_mode") == 1) ag["y_int"] = 0.0;
            double phi_fi = phi_cmd - AL_A_INT * ag.N("y_int");
            if (ag.N("n") > 0 && ag.N("n") == AL_N_FADER) ag["bias"] = (ag.N("phic_ul") - phi_fi) / AL_N_FADER;
            if (ag.N("n") > 0)
            {
                ag["n"] = ag.N("n") - 1;
                ag["phic_ul"] = phi_fi + ag.N("n") * ag.N("bias");
            }
            else
            {
                ag["phic_ul"] = phi_fi;
            }
            ag["phic_al"] = alg_slimit(ag.N("phic_ul"), ag.N("phi_max"));
        }

        public void alg_touchdown_rollout(Lex ag, Lex nav)   // the flat turn's heading-rate command (touchdown rollout)
        {
            ag["rc"] = alg_k_r_of(nav.N("qbar")) * ag.N("phic_al");
            ag["phic_al"] = 0.0;
        }

        // ---------------------------------------------------------------- one A/L pass (every AL_DT)
        public void alg_cycle(Lex ag, Lex nav)
        {
            ag["wowlon"] = nav.B("wowlon");
            ag["flatturn"] = nav.B("flatturn");
            alg_pitch_trajectory(ag, nav);
            if (!ag.B("wowlon") || ag.N("p_mode") == 4)
            {
                double pm = ag.N("p_mode");
                if (pm == 1) alg_trajectory_capture(ag, nav);
                else if (pm == 2) alg_steep_gs(ag, nav, false);
                else if (pm == 3) alg_fsgs(ag, nav);
                else if (pm == 4) alg_final_flare(ag, nav);
            }
            alg_nz_compensate(ag);
            alg_speedbrake(ag, nav);
            alg_roll(ag, nav);
            if (ag.B("flatturn")) alg_touchdown_rollout(ag, nav);
            ag["ncyc"] = ag.N("ncyc") + 1;
        }

        public double alg_nz_total(double nzc, double gamma, double bank_tg)   // what the pitch loop flies
        {
            double cosphi = MAX(COS(bank_tg), 0.20);
            return MAX(-TG_NZ_TOTAL_LIM, MIN(TG_NZ_TOTAL_LIM, COS(gamma) / cosphi + nzc));
        }

    }
}
