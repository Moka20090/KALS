@LAZYGLOBAL OFF.
// ============================================================================
//  ALG.KS  --  THE APPROACH-AND-LANDING GUIDANCE (FSSR G4.10)
// ============================================================================
//  A library: it loads alg_const.ks and needs taemg.ks (alg_aim_shift reads the TAEM aim point, TG_X_AIM_NOM - TG_X_AIM).
//  The state is two LEXICONs:
//      ag  -- the A/L guidance state (alg_init builds it),   nav -- the navigation state the caller builds each
//             A/L cycle (AL_DT, 0.16 s) in the GUIDANCE frame (x along the runway from the threshold, shifted by the
//             short-field aim shift; h and h_dot above the runway PLANE -- alg_rwy_plane / alg_rwy_plane_slope).
//  Constants: AL_<name>, written into alg_const.ks by gen_taemg.py (`alconst`), with the exp(-a DT) factors of alg_lag
//  precomputed there (AL_LAGE_<a>); exp(y) = AL_E ^ y. igi = 1; igs = 2 above AL_WT_GS1 on a runway of AL_IGS2_RWY_MIN or more (the heavyweight set, al_sim
//  HEAVY_SET), so the (I) tables are indexed by ag["igs"] - 1. Set 2 differs from set 1 only in the speedbrake's weight
//  term (al_sim HEAVY_OGS off), so the HUD cue helpers below read set 1's flare (index 0): the same numbers. If HEAVY_OGS
//  is ever turned on they (and coproc/Alg.cs's copies) must index by igs.
//  The caller owns: nav (air data, the runway frame, the main-gear height), the pitch loop flying ag["nzc"] (as TAEM's
//  nz_total: alg_nz_total), the bank flying ag["phic_al"] (G4.9 sign: taemg_bank_to_ship), the speedbrake flying
//  ag["dsbc_al"] (orbiter degrees = the hinge, 2 x each rudder panel), the gear (ag["rco_lg_deploy"]), the chute
//  (ag["rco_dc_deploy"]), and on the ground the derotation / brakes / steering (see the ground functions at the end).
//  Tested offline by al_selftest.ks.
// ============================================================================

RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/alg_const.ksm" IF O6_KSM_GO ELSE "0:/lib/alg_const.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/alg_const.ks").

// ---------------------------------------------------------------- helpers
FUNCTION alg_slimit {
    PARAMETER x, a.
    IF x < -a { RETURN -a. }
    IF x > a { RETURN a. }
    RETURN x.
}

FUNCTION alg_alimit {                       // x limited to a..b
    PARAMETER x, a, b.
    IF x < a { RETURN a. }
    IF x > b { RETURN b. }
    RETURN x.
}

FUNCTION alg_lag {                          // lag step, with ef = exp(-a DT) precomputed (AL_LAGE_*)
    PARAMETER y_prev, ef, x.
    RETURN ef * y_prev + (1.0 - ef) * x.
}

FUNCTION alg_asind {                        // asin, in degrees
    PARAMETER x.
    RETURN ARCSIN(MAX(-1.0, MIN(1.0, x))).
}

FUNCTION alg_k_r_of {                       // K_R at qbar (Pa): AL_K_R_TAB, linear between rows, held at the ends
    PARAMETER qbar.
    LOCAL tab IS AL_K_R_TAB.
    LOCAL n IS tab:LENGTH.
    IF qbar <= tab[0][0] { RETURN tab[0][1]. }
    IF qbar >= tab[n - 1][0] { RETURN tab[n - 1][1]. }
    FROM { LOCAL i IS 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        IF qbar <= tab[i][0] {
            LOCAL q0 IS tab[i - 1][0]. LOCAL k0 IS tab[i - 1][1].
            LOCAL q1 IS tab[i][0]. LOCAL k1 IS tab[i][1].
            RETURN k0 + (k1 - k0) * (qbar - q0) / (q1 - q0).
        }
    }
    RETURN tab[n - 1][1].
}

// ---------------------------------------------------------------- the runway: the aim shift, the guide plane
FUNCTION alg_sf_law {                       // returns LIST(aim shift m, K_DR_SRW m, B_DR_SF m)
    PARAMETER slope.
    LOCAL s0 IS AL_SF_FIT[0][0]. LOCAL a0 IS AL_SF_FIT[0][1]. LOCAL k0 IS AL_SF_FIT[0][2]. LOCAL b0 IS AL_SF_FIT[0][3].
    LOCAL s1 IS AL_SF_FIT[1][0]. LOCAL a1 IS AL_SF_FIT[1][1]. LOCAL k1 IS AL_SF_FIT[1][2]. LOCAL b1 IS AL_SF_FIT[1][3].
    LOCAL f IS (slope - s0) / (s1 - s0).
    RETURN LIST((a0 + f * (a1 - a0)) * AL_FT, k0 + f * (k1 - k0), b0 + f * (b1 - b0)).
}

FUNCTION alg_rwy_s {                        // the runway's slope along the landing direction
    PARAMETER elev, far_elev, rwy_len.
    IF rwy_len <= 0.0 { RETURN 0.0. }
    RETURN (far_elev - elev) / rwy_len.
}

FUNCTION alg_aim_shift {                    // the aim shift, m (reads TG_X_AIM: call it after taemg_set_aim for the runway)
    PARAMETER rwy_len, slope.
    LOCAL sf IS TG_X_AIM_NOM - TG_X_AIM.
    IF sf > 0.0 { RETURN sf. }
    IF rwy_len < AL_SF_LEN_MAX { RETURN alg_sf_law(slope)[0]. }
    RETURN 0.0.
}

FUNCTION alg_k_dr_srw_sf {                  // the short-field K_DR_SRW alg_init uses (its runway's, else the slope law's),
    PARAMETER rwy_name, slope, vmass.       //   with the light side below AL_W_DR_SF (al_sim)
    LOCAL kdr IS 0.0.
    LOCAL bdr IS 0.0.
    IF AL_K_DR_SRW_RW:HASKEY(rwy_name) {
        SET kdr TO AL_K_DR_SRW_RW[rwy_name].
        IF AL_B_DR_SF_RW:HASKEY(rwy_name) { SET bdr TO AL_B_DR_SF_RW[rwy_name]. }
    } ELSE {
        LOCAL law IS alg_sf_law(slope).
        SET kdr TO law[1].
        SET bdr TO law[2].
    }
    IF vmass < AL_W_DR_SF { RETURN kdr + bdr * LN(vmass / AL_W_DR_SF). }
    RETURN kdr.
}

FUNCTION alg_rwy_plane {                    // the guide plane's height at runway x (m, relative to the threshold)
    PARAMETER x, elev, far_elev, rwy_len.
    IF rwy_len <= 0.0 { RETURN 0.0. }
    LOCAL bl IS AL_GUIDE_PLANE_BLEND.
    IF x >= 0.0 { RETURN (far_elev - elev) * x / rwy_len. }
    LOCAL s_ IS alg_rwy_s(elev, far_elev, rwy_len).
    IF x >= -bl { RETURN s_ * (x + x * x / (2.0 * bl)). }
    RETURN -0.5 * s_ * bl.
}

FUNCTION alg_rwy_plane_slope {              // the guide plane's slope
    PARAMETER x, elev, far_elev, rwy_len.
    LOCAL s_ IS alg_rwy_s(elev, far_elev, rwy_len).
    LOCAL bl IS AL_GUIDE_PLANE_BLEND.
    IF x >= 0.0 { RETURN s_. }
    IF x >= -bl { RETURN s_ * (1.0 + x / bl). }
    RETURN 0.0.
}

// ---------------------------------------------------------------- AL_INIT
FUNCTION alg_init {                         // builds ag (nav in the guidance frame; sf = alg_aim_shift)
    PARAMETER nav, phic_at, vmass IS AL_VEHICLE_MASS, autop IS TRUE, autory IS TRUE, sf IS 0.0, k_dr_srw_sf IS 0.0,
        nzc_at IS -99999,                  // TAEM's last NZC for the pitch fader (-99999: none, no fade)
        rw_len IS 1E9.                     // m, the runway's length: set 2 from AL_IGS2_RWY_MIN, set 1's heavy side
                                           //   from AL_DR_HV_RWY_MIN
    LOCAL ag IS LEXICON(
        "mass", vmass,
        "v_t_filt", nav["tas"], "retract_bf", AL_INIT_RET_BF, "p_mode", AL_P_MODE_INITIAL,
        "igs", CHOOSE 2 IF vmass > AL_WT_GS1 AND rw_len >= AL_IGS2_RWY_MIN ELSE 1, "igi", CHOOSE 2 IF AL_GI_CHANGE ELSE 1,
        "f_mode", 0,
        "autop", autop, "autory", autory,
        "k_hint", 0.0, "k_c1g", AL_K_HDOT_TC, "k_c2h", AL_K_H_TC, "nz_c2i", 0.0, "sgs_init", FALSE, "tq_n", 0,
        "fsgs_init", FALSE, "ff_init", FALSE, "nz_c", 0.0, "nzc", 0.0, "c4_fade", 0.0,
        "nz_c1", 0.0, "nz_c2", 0.0, "nz_c2h", 0.0, "nz_c3", 0.0, "nz_c4", 0.0, "nz_c1h", 0.0, "nz_c1i", 0.0, "nz_c1i_int", 0.0,
        "h_ref", 0.0, "gamma_ref", AL_GAMMA_REF_1[0], "h_error", 0.0, "gamma_error", 0.0, "h_dot_error", 0.0, "r_gnd_ap", 0.0,
        "gamma_c3", 0.0, "gamma_c3_dot", 0.0, "gamma_air_sync", 0.0,
        "h_ref_dot", 0.0, "h_dot_c3", 0.0, "h_dot_syn", 0.0, "h_final_flare", 0.0, "v_wind_x", 0.0,
        "sbc_init", FALSE, "dsbc_al", AL_SB_REF, "sb_mode", 1, "hud_sb_retract", FALSE, "hud_ogs_merged", FALSE,
        "v_error", 0.0, "dr_total", 0.0,
        "y_int", 0.0, "phic_ul", phic_at, "n", AL_N_FADER, "rc", 0.0, "lat_mode", 1, "psi_n", 0, "bias", 0.0,
        "phic_al", phic_at,
        "phi_max", AL_PHI_M1,
        "rco_lg_arm", FALSE, "rco_lg_deploy", FALSE, "rco_dc_arm", FALSE, "rco_dc_deploy", FALSE,
        "wowlon", FALSE, "flatturn", FALSE, "ncyc", 0,
        "ret_log", LIST()).
    // the pitch fader (a deviation; al_sim NZ_FADER): NZC leaves TAEM's last command and reaches A/L's own over
    // AL_NZ_FADER cycles. nzf_b is set on the first compensation (absent until then, as the python's None).
    // set 1's heavy-side weight term (al_sim dr_wt_hv): 0 at and below the model mass, in set 2, on a short runway
    SET ag["dr_wt_hv"] TO CHOOSE AL_B_DR_HV * LN(vmass / AL_ORB_MASS)
        IF ag["igs"] = 1 AND vmass > AL_ORB_MASS AND rw_len >= AL_DR_HV_RWY_MIN ELSE 0.
    IF nzc_at > -9999 { SET ag["nzf_at"] TO nzc_at. SET ag["nzf_n"] TO AL_NZ_FADER. }
    ELSE { SET ag["nzf_n"] TO 0. }
    IF sf > 0.0 {
        SET ag["i_short_rw"] TO AL_SF_I_SHORT_RW.
        SET ag["k_dr_srw"] TO k_dr_srw_sf.
    } ELSE {
        SET ag["i_short_rw"] TO AL_I_SHORT_RW.
        IF AL_I_SHORT_RW = 1 OR AL_I_SHORT_RW = 2 { SET ag["k_dr_srw"] TO AL_K_DR_SRW[AL_I_SHORT_RW - 1]. }
        ELSE { SET ag["k_dr_srw"] TO 0.0. }
    }
    RETURN ag.
}

// ---------------------------------------------------------------- the pitch channel
FUNCTION alg_pitch_trajectory {
    PARAMETER ag, nav.
    LOCAL i IS ag["igs"] - 1.
    LOCAL j IS ag["igi"] - 1.
    SET ag["v_t_filt"] TO alg_lag(ag["v_t_filt"], AL_LAGE_A_13, nav["tas"]).
    SET ag["v_wind_x"] TO nav["v_g"] - ag["v_t_filt"] * COS(ARCSIN(MAX(-1.0, MIN(1.0, nav["h_dot"] / MAX(ag["v_t_filt"], 1.0))))).
    LOCAL dx IS nav["x"] - AL_X_AIM_PT.
    SET ag["r_gnd_ap"] TO SQRT(dx * dx + nav["y"] * nav["y"]).
    LOCAL steep IS ag["p_mode"] = 1 OR ag["p_mode"] = 2 OR (ag["p_mode"] = 3 AND ag["f_mode"] < 2).
    IF steep {
        LOCAL psi_cor IS 0.0.
        IF ABS(dx) > 1e-9 { SET psi_cor TO ARCTAN(nav["y"] / dx). }
        LOCAL x_zero_cor IS (AL_X_ZERO[j] + AL_X_AIM_PT) * COS(psi_cor).
        SET ag["h_ref"] TO (x_zero_cor - ag["r_gnd_ap"]) * TAN(AL_GAMMA_REF_1[i]).
        SET ag["gamma_ref"] TO AL_GAMMA_REF_1[i].
    } ELSE {
        SET ag["h_ref"] TO -ag["r_gnd_ap"] * TAN(AL_GAMMA_REF_2).
        SET ag["gamma_ref"] TO AL_GAMMA_REF_2.
    }
    IF ag["p_mode"] = 3 AND ag["f_mode"] > 1 {
        SET ag["gamma_error"] TO ag["gamma_ref"] - nav["gamma"].
    } ELSE {
        SET ag["h_error"] TO ag["h_ref"] - nav["h"].
        SET ag["gamma_error"] TO ag["gamma_ref"] - nav["gamma"].
        SET ag["h_dot_error"] TO nav["v_i"] * SIN(ag["gamma_ref"]) - nav["h_dot"].
    }
    IF AL_RCO_ENABLE {                      // rco_lg_arm and rco_dc_arm are set, never read: the deploy flags act
        IF nav["h"] < AL_RCO_H_ARM { SET ag["rco_lg_arm"] TO TRUE. }
        IF nav["h"] < AL_RCO_H_GEAR { SET ag["rco_lg_deploy"] TO TRUE. }
        IF ag["wowlon"] AND nav["eas"] < AL_RCO_EAS_DC {
            SET ag["rco_dc_arm"] TO TRUE.
            SET ag["rco_dc_deploy"] TO TRUE.
        }
    }
}

FUNCTION alg_trajectory_capture {           // p_mode 1: the glideslope law until captured (or AL_T_Q s), then p_mode 2
    PARAMETER ag, nav.
    IF ABS(ag["gamma_error"]) < AL_GAMMA_CAPTURE { SET ag["tq_n"] TO ag["tq_n"] + 1. } ELSE { SET ag["tq_n"] TO 0. }
    IF (ABS(ag["gamma_error"]) < AL_GAMMA_CAPTURE AND ABS(ag["h_error"]) < AL_H_ERROR_CAPTURE)
            OR ag["tq_n"] * AL_DT > AL_T_Q + 1e-9 {
        SET ag["p_mode"] TO 2.
    }
    alg_steep_gs(ag, nav, TRUE).
}

FUNCTION alg_steep_gs {                     // the steep glideslope's Nz; below AL_H_FLARE on to the flare (p_mode 3)
    PARAMETER ag, nav, via_tc IS FALSE.
    IF ag["p_mode"] = 2 AND NOT via_tc AND NOT ag["sgs_init"] {
        SET ag["k_hint"] TO AL_K_HINT1.
        SET ag["k_c1g"] TO AL_K_HDOT_SGS.
        SET ag["k_c2h"] TO AL_K_H_SGS.
        SET ag["sgs_init"] TO TRUE.
    }
    IF nav["h"] < AL_H_FLARE { SET ag["p_mode"] TO 3. }
    SET ag["nz_c1"] TO ag["k_c1g"] * ag["h_dot_error"].
    SET ag["nz_c2h"] TO ag["k_c2h"] * alg_slimit(ag["h_error"], AL_H_ERROR_MAX).
    LOCAL nz_c2i_dot IS ag["k_hint"] * alg_slimit(ag["h_error"], AL_H_INTMX).
    SET ag["nz_c2i"] TO ag["nz_c2i"] + nz_c2i_dot * AL_DT.
    IF NOT ag["autop"] { SET ag["nz_c2i"] TO 0.0. }
    SET ag["nz_c2"] TO ag["nz_c2h"] + ag["nz_c2i"].
    SET ag["nz_c"] TO ag["nz_c1"] + ag["nz_c2"].
}

FUNCTION alg_circle {                       // the closed-loop flare circle (used by alg_fsgs)
    PARAMETER ag, x, v_g, i, j.
    IF x < AL_X_TAN[i][j] {
        SET ag["h_ref_t"] TO (-AL_X_ZERO[j] - x) * TAN(-AL_GAMMA_REF_1[i]).
        SET ag["h_ref_t_dot"] TO v_g * TAN(AL_GAMMA_REF_1[i]).
        RETURN.
    }
    LOCAL dxk IS x - AL_X_K[i][j].
    IF AL_R_FLARE[i][j] ^ 2 - dxk * dxk <= 0.0 {    // past the circle's far end: sqrt 0, a divide by zero
        SET ag["h_ref_t"] TO -ag["r_gnd_ap"] * TAN(AL_GAMMA_REF_2).    // so the shallow glide slope itself, as al_sim
        SET ag["h_ref_t_dot"] TO v_g * TAN(AL_GAMMA_REF_2).
        RETURN.
    }
    SET ag["h_ref_t"] TO AL_H_K[i][j] - SQRT(MAX(AL_R_FLARE[i][j] ^ 2 - dxk * dxk, 0.0)).
    SET ag["h_ref_t_dot"] TO -v_g * dxk / (ag["h_ref_t"] - AL_H_K[i][j]).
}

FUNCTION alg_fsgs {                         // the flare onto the shallow glide slope
    PARAMETER ag, nav.
    LOCAL i IS ag["igs"] - 1.
    LOCAL j IS ag["igi"] - 1.
    LOCAL x IS nav["x"].
    LOCAL h IS nav["h"].
    LOCAL h_dot IS nav["h_dot"].
    LOCAL v_g IS nav["v_g"].
    IF NOT ag["fsgs_init"] {
        SET ag["nz_c2i"] TO 0.0.
        SET ag["gamma_c3"] TO 0.0.
        SET ag["f_mode"] TO 1.
        SET ag["retract_bf"] TO TRUE.
        SET ag["gamma_air_sync"] TO alg_asind(h_dot / MAX(ag["v_t_filt"], 1.0)).
        SET ag["nz_c3_lag"] TO 0.0.
        SET ag["c4_fade"] TO 0.0.
        SET ag["fsgs_init"] TO TRUE.
    }
    IF ag["f_mode"] = 2 {
        IF x > AL_X_EXP_T[i][j] { SET ag["f_mode"] TO 3. }
        ELSE { alg_circle(ag, x, v_g, i, j). }
    }
    SET ag["h_final_flare"] TO AL_TAU_TD * (AL_H_TD2_DOT - h_dot) + AL_H_NO_ACC.
    IF ag["f_mode"] = 3 AND h < AL_H_FF AND h < ag["h_final_flare"] { SET ag["p_mode"] TO 4. }
    IF h < AL_H_MIN { SET ag["p_mode"] TO 4. }
    IF ag["f_mode"] = 3 {
        LOCAL h_errorx IS AL_H_DECAY * AL_E ^ ((AL_X_EXP_T[i][j] - x) / AL_SIGMA[i]).
        SET ag["h_ref_t"] TO ag["h_ref"] + h_errorx.
        SET ag["h_ref_t_dot"] TO v_g * (TAN(AL_GAMMA_REF_2) - h_errorx / AL_SIGMA[i]).
    }
    IF ag["f_mode"] = 1 {
        IF h < AL_H_CLOOP {
            SET ag["f_mode"] TO 2.
            alg_circle(ag, x, v_g, i, j).
        } ELSE {
            SET ag["nz_c4"] TO 0.0.
        }
    }
    IF ag["f_mode"] <> 1 {
        SET ag["h_error"] TO ag["h_ref_t"] - h.
        SET ag["h_dot_error"] TO ag["h_ref_t_dot"] - h_dot.
        SET ag["nz_c2h"] TO AL_K_H_FSGS * ag["h_error"].
        SET ag["nz_c2i"] TO ag["nz_c2i"] + AL_K_INT_FSGS * ag["nz_c2h"] * AL_DT.
        IF NOT ag["autop"] { SET ag["nz_c2i"] TO 0.0. }
        SET ag["nz_c4"] TO ag["nz_c2h"] + AL_K_HDOT_FSGS * ag["h_dot_error"] + ag["nz_c2i"].
        IF AL_FSGS_C4_FADE > 0 {                          // faded in from the closed loop's start
            SET ag["c4_fade"] TO MIN(1, ag["c4_fade"] + AL_DT / AL_FSGS_C4_FADE).
            SET ag["nz_c4"] TO ag["nz_c4"] * ag["c4_fade"].
        }
    }
    LOCAL nzc_max IS nav["v_i"] ^ 2 / AL_R_FLARE[i][j].
    LOCAL gamma_dot_max IS AL_DEG_PER_RAD * nzc_max / MAX(ag["v_t_filt"], 1.0).
    SET ag["gamma_c3_dot"] TO alg_slimit((AL_GAMMA_REF_2 - ag["gamma_air_sync"] - ag["gamma_c3"]) / AL_TAU_GAMMA, gamma_dot_max).
    SET ag["gamma_c3"] TO ag["gamma_c3"] + ag["gamma_c3_dot"] * AL_DT.
    SET ag["nz_c3_lag"] TO alg_lag(ag["nz_c3_lag"], AL_LAGE_A_40, ag["v_t_filt"] * ag["gamma_c3_dot"] / (AL_DEG_PER_RAD * AL_GO)).
    SET ag["nz_c3"] TO ag["nz_c3_lag"].
    SET ag["nz_c"] TO ag["nz_c3"] + ag["nz_c4"].
}

FUNCTION alg_final_flare {                  // the final flare: Nz toward the touchdown sink rate, until weight on wheels
    PARAMETER ag, nav.
    LOCAL h IS nav["h"].
    LOCAL h_dot IS nav["h_dot"].
    IF NOT ag["ff_init"] {
        SET ag["h_ref_dot"] TO h_dot.
        SET ag["h_dot_c3"] TO h_dot.
        SET ag["nz_c1i_int"] TO 0.0.
        SET ag["h_dot_syn"] TO ag["nz_c"] / AL_K_HDOT_FF.
        SET ag["ff_init"] TO TRUE.
    }
    IF ag["wowlon"] { RETURN. }
    LOCAL h_ddot_c3 IS (AL_H_TD1_DOT + ag["h_dot_syn"] - ag["h_dot_c3"]) / AL_TAU_TD1.
    SET ag["h_dot_c3"] TO ag["h_dot_c3"] + h_ddot_c3 * AL_DT.
    SET ag["nz_c3"] TO AL_K_FLR * h_ddot_c3.
    LOCAL h_d IS MAX(h - AL_H_NO_ACC, 0.0).
    LOCAL h_ref_uf_dot IS AL_H_TD2_DOT - h_d / AL_TAU_TD2.
    SET ag["h_ref_dot"] TO alg_lag(ag["h_ref_dot"], AL_LAGE_A_3, h_ref_uf_dot).
    SET ag["nz_c1h"] TO AL_K_HDOT_FF * (ag["h_ref_dot"] - h_dot).
    SET ag["nz_c1i_int"] TO ag["nz_c1i_int"] + ag["nz_c1h"] * AL_DT.
    SET ag["nz_c1i"] TO AL_K_IFLR * ag["nz_c1i_int"].
    SET ag["nz_c1"] TO ag["nz_c1h"] + ag["nz_c1i"].
    SET ag["nz_c"] TO ag["nz_c1"] + ag["nz_c3"].
}

FUNCTION alg_nz_compensate {                // nzc: nz_c with a lead of AL_DT_LAG_NZ s, limited to +-AL_NZC_LIM
    PARAMETER ag.
    IF NOT ag:HASKEY("nz_cp") { SET ag["nz_cp"] TO ag["nz_c"]. }
    LOCAL nz_comp IS ag["nz_c"] + AL_DT_LAG_NZ * (ag["nz_c"] - ag["nz_cp"]) / AL_DT.
    SET ag["nzc"] TO alg_slimit(nz_comp, AL_NZC_LIM).
    IF ag:HASKEY("nzf_n") AND ag["nzf_n"] > 0 {   // the pitch fader (alg_init), from TAEM's NZC onto A/L's
        IF NOT ag:HASKEY("nzf_b") { SET ag["nzf_b"] TO (ag["nzf_at"] - ag["nzc"]) / ag["nzf_n"]. }
        SET ag["nzc"] TO alg_slimit(ag["nzc"] + ag["nzf_b"] * ag["nzf_n"], AL_NZC_LIM).
        SET ag["nzf_n"] TO ag["nzf_n"] - 1.
    }
    SET ag["nz_cp"] TO ag["nz_c"].
}

// ---------------------------------------------------------------- the speedbrake (the retract)
FUNCTION alg_sb_knee {                      // an OGS brake reading in degrees of drag below the knee (al_sim al_sb_knee)
    PARAMETER h.
    IF h <= AL_SB_SENSE_KNEE { RETURN h. }
    RETURN AL_SB_SENSE_KNEE + AL_SB_SENSE_K * (h - AL_SB_SENSE_KNEE).
}
FUNCTION alg_sb_sense {                     // what the retract's OGS-brake term reads (al_sim al_sb_sense): the
    PARAMETER sbo, vm.                    //   weight's own brake taken off above the model mass, the knee, the gain
    IF vm <= AL_ORB_MASS { RETURN alg_sb_knee(sbo). }
    LOCAL mr IS vm / AL_ORB_MASS.
    LOCAL xs IS AL_SB_OGS_WT_MR.
    LOCAL ys IS AL_SB_OGS_WT.
    LOCAL ew IS ys[ys:LENGTH - 1].
    FROM { LOCAL k IS 0. } UNTIL k >= xs:LENGTH - 1 STEP { SET k TO k + 1. } DO {
        IF mr < xs[k + 1] {
            SET ew TO ys[k] + (ys[k + 1] - ys[k]) * (mr - xs[k]) / (xs[k + 1] - xs[k]).
            BREAK.
        }
    }
    LOCAL fx IS AL_SB_SENSE_F_MR.          // the gain by WEIGHT / ORB_MASS, held past the ends
    LOCAL fy IS AL_SB_SENSE_F.
    LOCAL fg IS fy[fy:LENGTH - 1].
    FROM { LOCAL k IS 0. } UNTIL k >= fx:LENGTH - 1 STEP { SET k TO k + 1. } DO {
        IF mr < fx[k + 1] {
            SET fg TO fy[k] + (fy[k + 1] - fy[k]) * (mr - fx[k]) / (fx[k + 1] - fx[k]).
            BREAK.
        }
    }
    RETURN AL_SB_OGS_0 + fg * (alg_sb_knee(sbo) - alg_sb_knee(AL_SB_OGS_0 + ew)).
}
FUNCTION alg_speedbrake {                   // the A/L speedbrake command ag["dsbc_al"] (the retract)
    PARAMETER ag, nav.
    LOCAL i IS ag["igs"] - 1.
    LOCAL j IS ag["igi"] - 1.
    LOCAL h IS nav["h"].
    IF NOT ag["sbc_init"] {
        SET ag["eas_filt"] TO nav["eas"].
        SET ag["v_wind_filt"] TO ag["v_wind_x"].
        SET ag["delta_sbi"] TO 0.0.
        SET ag["delta_ti"] TO 0.0001.
        SET ag["v_wind_int"] TO 0.0.
        SET ag["hud_sb_retract"] TO FALSE.
        SET ag["sb_lim"] TO AL_SB_MAX.
        SET ag["dsbc_al"] TO AL_SB_REF.
        SET ag["sb_mode"] TO 1.
        SET ag["v_err_filt"] TO nav["eas"] - AL_V_REF[i].
        SET ag["dr_ci_xo"] TO CHOOSE (AL_X_ZERO[0] - AL_X_ZERO[1]) IF ag["igi"] = 2 ELSE 0.0.
        SET ag["dr_srw"] TO ag["k_dr_srw"].
        SET ag["dr_wt"] TO 0.0.
        SET ag["dr_v_error"] TO 0.0.
        SET ag["tdv_i"] TO 0.0.
        SET ag["tdv_e"] TO 0.0.
        SET ag["dsbc_ret"] TO AL_SB_REF.
        SET ag["sbc_init"] TO TRUE.
    }
    IF NOT ag["wowlon"] {
        SET ag["eas_filt"] TO alg_lag(ag["eas_filt"], AL_LAGE_A_14, nav["eas"]).
        SET ag["v_wind_filt"] TO alg_lag(ag["v_wind_filt"], AL_LAGE_A_VWF, ag["v_wind_x"]).
    }
    IF ag["sb_mode"] = 1 {
        SET ag["v_error"] TO ag["eas_filt"] - AL_V_REF[i].
        SET ag["v_err_filt"] TO alg_lag(ag["v_err_filt"], AL_LAGE_A_VWF, ag["v_error"]).
        LOCAL delta_sbe IS AL_K_SB * ag["v_error"].
        LOCAL del_int IS AL_K_SBI * alg_slimit(ag["v_error"], AL_V_LIMIT).
        IF ag["dsbc_al"] >= AL_SB_MAX OR ag["dsbc_al"] <= 0.0 OR ag["p_mode"] = 1 { SET del_int TO 0.0. }
        SET ag["delta_sbi"] TO ag["delta_sbi"] + del_int * AL_DT.
        SET ag["dsbc_al"] TO delta_sbe + ag["delta_sbi"] + AL_SB_REF.
        SET ag["delta_sbe"] TO delta_sbe.
    }
    LOCAL retract IS FALSE.
    IF h < AL_H_SBR_TABLE[0] AND ag["sb_mode"] = 1 {
        SET ag["dsbc_ogs"] TO ag["dsbc_al"].
        SET ag["hud_sb_retract"] TO TRUE.
        SET ag["dr_wt"] TO AL_A_DR_WT[i] + AL_B_DR_WT[i] * LN(ag["mass"]) + ag["dr_wt_hv"].
        SET ag["dr_v_error"] TO AL_S_DR_VEL * ag["v_err_filt"].
        SET ag["sb_lim"] TO AL_SB_MAX_RET.
        SET retract TO TRUE.
    }
    IF h >= AL_H_SBR_TABLE[1] AND ag["sb_mode"] = 2 {
        SET ag["v_wind_int"] TO ag["v_wind_int"] + ag["v_wind_filt"] * AL_DT.
        SET ag["delta_ti"] TO ag["delta_ti"] + AL_DT.
    }
    IF h < AL_H_SBR_TABLE[1] AND ag["sb_mode"] = 2 {
        SET ag["v_wind_filt"] TO ag["v_wind_int"] / ag["delta_ti"].
        SET ag["sb_lim"] TO CHOOSE AL_SB_MAX_TD[0] IF ag["i_short_rw"] = 0 ELSE AL_SB_MAX_TD[1].
        SET retract TO TRUE.
    }
    IF retract {
        LOCAL d_h IS AL_S_DH * (ag["eas_filt"] / MAX(ag["v_t_filt"], 1.0)) ^ 2 + AL_K_DH - AL_H_SBR_TABLE[ag["sb_mode"] - 1].
        LOCAL dr_dh IS AL_S_DR_DH * d_h + AL_K_DR_DH.
        LOCAL dr_wind IS AL_S_DR_WIND * ag["v_wind_filt"].
        SET ag["dr_total"] TO (ag["dr_wt"] + ag["dr_v_error"] + dr_dh + dr_wind + ag["dr_ci_xo"] + ag["dr_srw"]).
        IF AL_RETRACT_SB_TERM { SET ag["dr_total"] TO ag["dr_total"] + AL_S_DR_SB * (alg_sb_sense(ag["dsbc_ogs"], ag["mass"]) - AL_SB_REF). }
        SET ag["d_h"] TO d_h.
        SET ag["dsbc_al"] TO alg_alimit(AL_S_SB_DR[i] * ag["dr_total"] + AL_K_SB_DR, 0.0, ag["sb_lim"]).
        SET ag["dsbc_ret"] TO ag["dsbc_al"].    // TDV's base
        ag["ret_log"]:ADD(LEXICON("h", h, "sb_mode", ag["sb_mode"], "dsbc", ag["dsbc_al"], "dr_total", ag["dr_total"],
                                  "d_h", d_h, "x", nav["x"])).
        SET ag["sb_mode"] TO ag["sb_mode"] + 1.
    }
    // the final-flare brake (AL_FF_SB_RETRACT; a deviation from G4.10, nominal runways only): shut below AL_FF_SB_H,
    // at least AL_FF_SB_OPEN above it while the filtered EAS is over AL_FF_SB_V
    IF AL_FF_SB_RETRACT AND ag["p_mode"] = 4 AND NOT ag["wowlon"] AND ag["i_short_rw"] = 0 {
        IF h < AL_FF_SB_H { SET ag["dsbc_al"] TO MIN(ag["dsbc_al"], AL_FF_SB_LIM). }
        ELSE IF ag["eas_filt"] > AL_FF_SB_V { SET ag["dsbc_al"] TO MIN(MAX(ag["dsbc_al"], AL_FF_SB_OPEN), ag["sb_lim"]). }
    }
    // THE TOUCHDOWN-SPEED BRAKE (a deviation, al_sim's TDV: landing speed and sink rate before the touchdown point):
    // from the 3000 ft retract to AL_TDV_H_OFF the brake is the retract's setting plus a PI correction on the predicted
    // touchdown EAS (EAS - AL_TDV_DV(h)) against the weight-scaled target (AL_TD_KEAS_TARGET; AL_TD_KEAS_TARGET_SF on a
    // short-runway option, floored at AL_TD_KEAS_FLOOR_SF); after the final-flare brake above
    IF AL_TDV_ON AND NOT ag["wowlon"] AND ag["sb_mode"] >= 2 AND h >= AL_TDV_H_OFF {
        LOCAL sf IS ag["i_short_rw"] <> 0.
        LOCAL v_tgt IS (CHOOSE AL_TD_KEAS_TARGET_SF IF sf ELSE AL_TD_KEAS_TARGET) * AL_KT * SQRT(ag["mass"] / AL_ORB_MASS).
        IF sf { SET v_tgt TO MAX(v_tgt, AL_TD_KEAS_FLOOR_SF * AL_KT). }
        LOCAL e IS nav["eas"] - alg_tdv_dv(h, sf) - v_tgt.
        SET ag["tdv_e"] TO e.
        LOCAL u IS ag["dsbc_ret"] + AL_TDV_K * e + ag["tdv_i"].
        IF NOT ((u >= ag["sb_lim"] AND e > 0.0) OR (u <= 0.0 AND e < 0.0)) {
            SET ag["tdv_i"] TO ag["tdv_i"] + AL_TDV_KI * e * AL_DT.
        }
        SET ag["dsbc_al"] TO alg_alimit(ag["dsbc_ret"] + AL_TDV_K * e + ag["tdv_i"], 0.0, ag["sb_lim"]).
    }
    IF ag["wowlon"] { SET ag["dsbc_al"] TO AL_DSBC_WW. }
    SET ag["dsbc_al"] TO alg_alimit(ag["dsbc_al"], 0.0, CHOOSE AL_SB_MAX_GROUND IF ag["wowlon"] ELSE AL_SB_MAX).
}

FUNCTION alg_tdv_dv {                       // m/s, the EAS lost from the guidance's height h (m) to the touchdown
    PARAMETER h, sf.
    LOCAL tab IS CHOOSE AL_TDV_DV_SF IF sf ELSE AL_TDV_DV.
    IF h >= AL_TDV_H[0] { RETURN tab[0]. }
    LOCAL k IS 0.
    UNTIL k >= AL_TDV_H:LENGTH - 1 {
        IF h >= AL_TDV_H[k + 1] {
            RETURN tab[k + 1] + (tab[k] - tab[k + 1]) * (h - AL_TDV_H[k + 1]) / (AL_TDV_H[k] - AL_TDV_H[k + 1]).
        }
        SET k TO k + 1.
    }
    RETURN tab[tab:LENGTH - 1] * MAX(h, 0.0) / AL_TDV_H[AL_TDV_H:LENGTH - 1].
}

// ---------------------------------------------------------------- the lateral channel
FUNCTION alg_roll {                         // the lateral channel's roll command
    PARAMETER ag, nav.
    IF ag["lat_mode"] = 1 {
        LOCAL psi_ok IS ABS(nav["psi_gnd"]) < AL_PSI_CAP.
        IF psi_ok { SET ag["psi_n"] TO ag["psi_n"] + 1. } ELSE { SET ag["psi_n"] TO 0. }
        IF (psi_ok AND ABS(nav["y"]) < AL_Y_CAP) OR ag["psi_n"] * AL_DT > AL_TQ_LAT + 1e-9 { SET ag["lat_mode"] TO 2. }
    }
    IF ag["autory"] { SET ag["phi_max"] TO CHOOSE AL_PHI_M1 IF nav["h"] > AL_H_WL ELSE AL_PHI_M2. }
    ELSE { SET ag["phi_max"] TO AL_PHI_M3. }
    LOCAL y_error IS alg_slimit(nav["y"], AL_Y_LIMIT).
    LOCAL y_int_dot IS alg_slimit(y_error, AL_Y_INLIM).
    LOCAL phi_cmd IS -AL_K_Y1 * (y_error + AL_K_YDOT * nav["y_dot"]).
    SET ag["y_int"] TO ag["y_int"] + y_int_dot * AL_DT.
    IF NOT ag["autory"] OR ag["lat_mode"] = 1 { SET ag["y_int"] TO 0.0. }
    LOCAL phi_fi IS phi_cmd - AL_A_INT * ag["y_int"].
    IF ag["n"] > 0 AND ag["n"] = AL_N_FADER { SET ag["bias"] TO (ag["phic_ul"] - phi_fi) / AL_N_FADER. }
    IF ag["n"] > 0 {
        SET ag["n"] TO ag["n"] - 1.
        SET ag["phic_ul"] TO phi_fi + ag["n"] * ag["bias"].
    } ELSE {
        SET ag["phic_ul"] TO phi_fi.
    }
    SET ag["phic_al"] TO alg_slimit(ag["phic_ul"], ag["phi_max"]).
}

FUNCTION alg_touchdown_rollout {            // the flat turn's heading-rate command (touchdown rollout)
    PARAMETER ag, nav.
    SET ag["rc"] TO alg_k_r_of(nav["qbar"]) * ag["phic_al"].
    SET ag["phic_al"] TO 0.0.
}

// ---------------------------------------------------------------- one A/L pass (every AL_DT)
FUNCTION alg_cycle {
    PARAMETER ag, nav.
    SET ag["wowlon"] TO nav["wowlon"].
    SET ag["flatturn"] TO nav["flatturn"].
    alg_pitch_trajectory(ag, nav).
    IF NOT ag["wowlon"] OR ag["p_mode"] = 4 {
        LOCAL pm IS ag["p_mode"].
        IF pm = 1 { alg_trajectory_capture(ag, nav). }
        ELSE IF pm = 2 { alg_steep_gs(ag, nav). }
        ELSE IF pm = 3 { alg_fsgs(ag, nav). }
        ELSE IF pm = 4 { alg_final_flare(ag, nav). }
    }
    alg_nz_compensate(ag).
    alg_speedbrake(ag, nav).
    alg_roll(ag, nav).
    IF ag["flatturn"] { alg_touchdown_rollout(ag, nav). }
    SET ag["ncyc"] TO ag["ncyc"] + 1.
}

FUNCTION alg_mode_text {                    // the HUD's A/L mode word
    PARAMETER ag.
    IF ag["wowlon"] { RETURN "". }
    LOCAL pm IS ag["p_mode"].
    IF pm = 1 { RETURN "CAPT". }
    IF pm = 2 { RETURN "OGS". }
    IF pm = 3 { RETURN "FLARE". }
    IF pm = 4 { RETURN "FNLFL". }
    RETURN "".
}

FUNCTION alg_nz_total {                     // what the pitch loop flies (1 g + nzc, banked)
    PARAMETER nzc, gamma, bank_tg.
    LOCAL cosphi IS MAX(COS(bank_tg), 0.20).
    RETURN MAX(-TG_NZ_TOTAL_LIM, MIN(TG_NZ_TOTAL_LIM, COS(gamma) / cosphi + nzc)).
}

// ---------------------------------------------------------------- the HUD's A/L cues
FUNCTION alg_flare_ref_gamma {              // the preflare reference's slope at x (deg; -999 = none)
    PARAMETER x.
    IF x >= AL_X_EXP {
        LOCAL s_ IS -TAN(-AL_GAMMA_REF_2) - AL_H_DECAY / AL_SIGMA[0] * AL_E ^ ((AL_X_EXP - x) / AL_SIGMA[0]).
        RETURN ARCTAN(s_).
    }
    LOCAL dxk IS x - AL_X_K[0][0].
    LOCAL w2 IS AL_R_FLARE[0][0] ^ 2 - dxk * dxk.
    IF w2 <= 0.0 { RETURN -999. }
    RETURN ARCTAN(dxk / SQRT(w2)).
}

FUNCTION alg_tri_lead {                     // how far ahead the preflare triangles read the reference
    PARAMETER ag, nav.
    IF ag["p_mode"] < 3 { RETURN AL_FLARE_CUE_LEAD. }
    RETURN AL_FLARE_CUE_LEAD * MIN(MAX((nav["h"] - AL_H_CLOOP) / (AL_H_FLARE - AL_H_CLOOP), 0.0), 1.0).
}

FUNCTION alg_tri_gam {                      // the preflare triangles' gamma (-999 = no triangles)
    PARAMETER ag, nav, in_air.
    IF NOT in_air OR NOT (ag["p_mode"] = 2 OR ag["p_mode"] = 3) { RETURN -999. }
    LOCAL g_ IS alg_flare_ref_gamma(nav["x"] + alg_tri_lead(ag, nav)).
    IF g_ = -999 OR g_ < AL_FLARE_TRI_GAM_MIN { RETURN -999. }
    RETURN g_.
}

FUNCTION alg_ogs_cue_gam {                  // the OGS cue's gamma (-999 = no OGS cue); latches the merge
    PARAMETER ag, in_air, tri.
    IF NOT in_air OR NOT (ag["p_mode"] = 1 OR ag["p_mode"] = 2 OR ag["p_mode"] = 3) OR ag["hud_ogs_merged"] { RETURN -999. }
    LOCAL ref IS AL_GAMMA_REF_1[ag["igs"] - 1].
    IF tri <> -999 AND tri >= ref {
        SET ag["hud_ogs_merged"] TO TRUE.
        RETURN -999.
    }
    IF ag["p_mode"] = 3 AND tri = -999 { RETURN -999. }
    RETURN ref.
}

// ---------------------------------------------------------------- on the ground
FUNCTION alg_derot_rate {                   // the derotation: hold, then nose down at 185 KEAS (short field: at WOW)
    PARAMETER eas, short_field.             //   -> the pitch-down rate command, deg/s (0 = hold the attitude)
    IF short_field { RETURN AL_SF_DEROT_RATE. }
    IF eas <= AL_DEROT_EAS { RETURN AL_DEROT_RATE. }
    RETURN 0.0.
}

FUNCTION alg_brake_need {                   // the brakes: past midfield below 140 kt to the 1000 ft-short stop
    PARAMETER vg, x, rwy_len, wong, short_field.  //   -> the total deceleration wanted, m/s2 (-1 = no braking yet)
    IF NOT wong { RETURN -1. }
    IF NOT (short_field OR NOT AL_BRAKE_MIDFIELD OR (vg < AL_BRAKE_GS AND x >= 0.5 * rwy_len)) { RETURN -1. }
    IF short_field OR AL_BRAKE_MAX_EFFORT { RETURN 99. }
    LOCAL room IS rwy_len - AL_BRAKE_MARGIN - x.
    IF room <= 1.0 { RETURN 99. }
    RETURN vg * vg / (2.0 * room).
}

FUNCTION alg_chute_jettison {               // the chute comes off at 60 KGS
    PARAMETER vg.
    RETURN vg < AL_CHUTE_JETT_GS.
}
