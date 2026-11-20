// lib_ascent_padcs.ks -- THE PAD SEARCH IN THE KAL/S COPROCESSOR.
// E TAL (lib_ascent_etl), the ARD's pad search (lib_ascent_ard: the stage-1 predictor, the path, every level, the rank) and
// the BLUE / GREEN sweep (lib_ascent_bgl) as ONE addon job, ADDONS:KALS:PADSEARCH (coproc/Pad*.cs, line for line these
// libraries, on worker threads: E TAL || the path, then the levels, the rank sites and the sweep in parallel); kOS polls its
// DONE and writes the results into the very structures its own searches leave (asc["etl"], asc["ard"], asc["bgl"], the
// globals the sweep sets, the log lines), so the pages, the logs, the pad cache and the in-flight refreshes read them as
// before. Checked against these libraries' own code in kOS's VM (the dev tools). Vessel-free: ops1q hands
// the states; ops1q's asc_pad_cs_go / asc_pad_cs_work use these.
@LAZYGLOBAL OFF.

// every constant the C# reads (its PadC: kOS stays the one source; the runtime ones too: the target box, the SSMEs, the
// planet's rotation, ASC_BGL_V2), at each search
FUNCTION padcs_consts {
  RETURN LEXICON("ASC_R", ASC_R, "ASC_MECO_H", ASC_MECO_H, "ASC_GAMD", ASC_GAMD, "ASC_VDMAG", ASC_VDMAG,
    "ASC_ATO_VDMAG", ASC_ATO_VDMAG, "ASC_MU", ASC_MU, "ASC_J2", ASC_J2, "ASC_R_J2", ASC_R_J2,
    "ASC_PL_TO_KSP", ASC_PL_TO_KSP, "ASC_FT_FACTOR", ASC_FT_FACTOR, "ASC_AL", ASC_AL,
    "ASC_TAL_OMS_TGO_OFF", ASC_TAL_OMS_TGO_OFF, "ASC_ARD_DT", ASC_ARD_DT, "ASC_ARD_H_LOW", ASC_ARD_H_LOW,
    "ASC_ARD_T_MAX", ASC_ARD_T_MAX, "ASC_ARD_TAL_VGO_TOL", ASC_ARD_TAL_VGO_TOL, "ASC_ARD_FOMS", ASC_ARD_FOMS,
    "ASC_ARD_MDO", ASC_ARD_MDO, "ASC_ARD_AIR_H0", ASC_ARD_AIR_H0, "ASC_ARD_ATM_TOP", ASC_ARD_ATM_TOP,
    "ASC_ARD_AREF", ASC_ARD_AREF, "ASC_ARD_OMS_DV", ASC_ARD_OMS_DV, "ASC_ARD_W", ASC_ARD_W,
    "ASC_DRP_MIN_ALT", ASC_DRP_MIN_ALT, "ASC_ATO_H", ASC_ATO_H, "ASC_ATO_DV_DEORBIT", ASC_ATO_DV_DEORBIT,
    "ASC_OMS_DV_NOW", ASC_OMS_DV_NOW, "ASC_DRP_THR_MAX", ASC_DRP_THR_MAX, "ASC_DRP_THR_MIN", ASC_DRP_THR_MIN,
    "ASC_DRP_THRESH_ATT", ASC_DRP_THRESH_ATT, "ASC_DRP_ATT_INCR", ASC_DRP_ATT_INCR,
    "ASC_DRP_ALT_DBND", ASC_DRP_ALT_DBND, "ASC_DRP_ALT_PEG_LOSS", ASC_DRP_ALT_PEG_LOSS, "ASC_DRP_VMISS", ASC_DRP_VMISS,
    "ASC_DRP_PASS_MAX", ASC_DRP_PASS_MAX, "ASC_DRP_NSSME", ASC_DRP_NSSME, "ASC_DRP_ENA", ASC_DRP_ENA,
    "ASC_DTGD", ASC_DTGD, "ASC_KMAX_ABORT", ASC_KMAX_ABORT, "ASC_RTLS_THETA_0", ASC_RTLS_THETA_0,
    "ASC_RTLS_THETA_1", ASC_RTLS_THETA_1, "ASC_RTLS_THETA_2", ASC_RTLS_THETA_2, "ASC_RTLS_THETA_3", ASC_RTLS_THETA_3,
    "ASC_RTLS_THETA_4", ASC_RTLS_THETA_4, "ASC_RTLS_THETA_MIN", ASC_RTLS_THETA_MIN,
    "ASC_RTLS_THETA_MAX", ASC_RTLS_THETA_MAX, "ASC_RTLS_V_SWTCH", ASC_RTLS_V_SWTCH,
    "ASC_RTLS_THETA_FB", ASC_RTLS_THETA_FB, "ASC_RTLS_DUMP_T", ASC_RTLS_DUMP_T,
    "ASC_RTLS_DUMP_T_LO", ASC_RTLS_DUMP_T_LO, "ASC_RTLS_V_DUMP_SW", ASC_RTLS_V_DUMP_SW, "ASC_KMIN", ASC_KMIN,
    "ASC_RTLS_DT_PPD_MARGIN", ASC_RTLS_DT_PPD_MARGIN, "ASC_RTLS_GAMD", ASC_RTLS_GAMD, "ASC_RTLS_H_PPD", ASC_RTLS_H_PPD,
    "ASC_RTLS_DELK_MAX", ASC_RTLS_DELK_MAX, "ASC_RTLS_KMISS", ASC_RTLS_KMISS,
    "ASC_RTLS_RNG_TURN_PRED", ASC_RTLS_RNG_TURN_PRED, "ASC_RTLS_DTHETA_LIM", ASC_RTLS_DTHETA_LIM,
    "ASC_RTLS_DTHETA_RATE", ASC_RTLS_DTHETA_RATE, "ASC_RTLS_M_BIAS", ASC_RTLS_M_BIAS,
    "ASC_RTLS_ALPHA_PPD", ASC_RTLS_ALPHA_PPD, "ASC_RTLS_THRUST_OFF", ASC_RTLS_THRUST_OFF,
    "ASC_RTLS_PPD_RATE", ASC_RTLS_PPD_RATE, "ASC_RTLS_T_SETTLE", ASC_RTLS_T_SETTLE,
    "ASC_RTLS_THETA_PPD0", ASC_RTLS_THETA_PPD0, "ASC_RTLS_PHIDOT_MAX", ASC_RTLS_PHIDOT_MAX,
    "ASC_ARD_RT_TOL", ASC_ARD_RT_TOL, "ASC_ARD_RT_NMAX", ASC_ARD_RT_NMAX, "ASC_ARD_RT_NPPD", ASC_ARD_RT_NPPD,
    "ASC_ARD_LNRHO", ASC_ARD_LNRHO, "ASC_ARD_AS", ASC_ARD_AS, "ASC_ARD_CDM", ASC_ARD_CDM,
    "ASC_RTLS_A_MECO", ASC_RTLS_A_MECO, "ASC_DTMAX", ASC_DTMAX, "ASC_DTMIN", ASC_DTMIN, "ASC_NSEG", ASC_NSEG,
    "ASC_ETB", ASC_ETB, "ASC_KMISS", ASC_KMISS, "ASC_RHOMAG", ASC_RHOMAG, "ASC_PHIDOT_MAX", ASC_PHIDOT_MAX,
    "ASC_EPSTGO", ASC_EPSTGO, "ASC_DTRD", ASC_DTRD, "asc_rtls_th0", asc_rtls_th0, "ASC_ARD_NEVER", ASC_ARD_NEVER,
    "ASC_TAL_OMS_DELAY", ASC_TAL_OMS_DELAY, "ASC_TAL_DUMP", ASC_TAL_DUMP, "ASC_TAL_SITES", ASC_TAL_SITES,
    "ASC_S1P_SRB_C", ASC_S1P_SRB_C, "ASC_S1P_SRB_I", ASC_S1P_SRB_I, "ASC_S1P_SS_I", ASC_S1P_SS_I,
    "ASC_S1P_SRB_MD", ASC_S1P_SRB_MD, "ASC_S1P_SRB_CAP", ASC_S1P_SRB_CAP, "ASC_S1P_NSRB", ASC_S1P_NSRB,
    "ASC_S1P_AREF", ASC_S1P_AREF, "ASC_S1P_ATM_PER_PA", ASC_S1P_ATM_PER_PA, "ASC_S1P_CDM", ASC_S1P_CDM,
    "ASC_S1P_ATM", ASC_S1P_ATM, "ASC_S1P_B", ASC_S1P_B, "ASC_PPOLY", ASC_PPOLY, "ASC_THET", ASC_THET,
    "ASC_PSI", ASC_PSI, "ASC_QPOLY", ASC_QPOLY, "ASC_THROT", ASC_THROT, "ASC_T_CNS_PITCH_RATE", ASC_T_CNS_PITCH_RATE,
    "ASC_THETC_DOT_NOM_RAD", ASC_THETC_DOT_NOM_RAD, "ASC_SSSL", ASC_SSSL, "ASC_DSSA", ASC_DSSA, "ASC_ALTSS", ASC_ALTSS,
    "ASC_ETAL_HF", ASC_ETAL_HF, "ASC_ETAL_HI", ASC_ETAL_HI, "ASC_ETAL_TOL", ASC_ETAL_TOL,
    "ASC_ETAL_SEED_ON", ASC_ETAL_SEED_ON, "ASC_ETAL_SEED_DT", ASC_ETAL_SEED_DT, "ASC_ETAL_DT", ASC_ETAL_DT,
    "ASC_ARD_NBIS", ASC_ARD_NBIS, "ASC_ARD_NBIS_NEAR", ASC_ARD_NBIS_NEAR, "ASC_ARD_NEAR", ASC_ARD_NEAR,
    "ASC_ARD_JDT", ASC_ARD_JDT, "ASC_ARD_JDT1", ASC_ARD_JDT1, "ASC_ARD_NEVER_Q", ASC_ARD_NEVER_Q,
    "ASC_ARD_PE_IT", ASC_ARD_PE_IT, "ASC_ARD_COARSE", ASC_ARD_COARSE, "ASC_ARD_RANK_ON", ASC_ARD_RANK_ON,
    "ASC_ARD_PE_SD", ASC_ARD_PE_SD, "ASC_ARD_PE_B", ASC_ARD_PE_B, "ASC_ARD_PE_TB", ASC_ARD_PE_TB,
    "ASC_BGL_SITES", ASC_BGL_SITES, "ASC_BGL_FP", ASC_BGL_FP, "ASC_BGL_REL", ASC_BGL_REL, "ASC_BGL_HB", ASC_BGL_HB,
    "ASC_BGL_MG", ASC_BGL_MG, "ASC_BGL_MT", ASC_BGL_MT, "ASC_BGL_YAWS", ASC_BGL_YAWS, "ASC_BGL_MXK", ASC_BGL_MXK,
    "ASC_BGL_MU", ASC_BGL_MU, "ASC_BGL_PUSH", ASC_BGL_PUSH, "ASC_BGL_RELPUSH", ASC_BGL_RELPUSH,
    "ASC_BGL_VIPUSH", ASC_BGL_VIPUSH, "ASC_BGL_OUTER", ASC_BGL_OUTER, "ASC_BGL_RKM", ASC_BGL_RKM,
    "ASC_BGL_RAD", ASC_BGL_RAD, "ASC_BGL_NONE", ASC_BGL_NONE, "ASC_BGL_Y20_PREF", ASC_BGL_Y20_PREF,
    "ASC_BGL_V2", ASC_BGL_V2, "ASC_CNT_DCO", ASC_CNT_DCO, "ASC_CNT_HDOT_MODE1", ASC_CNT_HDOT_MODE1,
    "ASC_CNT_VI_MIN_DROOP", ASC_CNT_VI_MIN_DROOP,
    // The mode-2 hold predictor's (C#'s CntHold.K, this order)
    "ASC_BGL_HOLD", ASC_BGL_HOLD AND ASC_CNT_M2H, "ASC_BGL_PUSH2", ASC_BGL_PUSH2,
    "ASC_BGL_HOLD_K", LIST(ASC_CNT_THETA_MODE2, ASC_CNT_CANT, ASC_CNT_SLEW, ASC_CNT_EAS_PD, ASC_CNT_PITCH_ACC,
      ASC_CNT_HIGH_SEP_RATE, ASC_CNT_QMECO_HIGH, ASC_CNT_M2_HT, ASC_CNT_M2_K, ASC_CNT_M2_EMIN, ASC_CNT_M2_HCAP,
      ASC_CNT_M2_KH, ASC_CNT_M2_HDMIN, ASC_CNT_M2_PSI, ASC_CNT_M2_FLAT, ASC_CNT_M2_EFIX, ASC_CNT_M2_EGATE, ASC_CNT_LAW,
      ASC_CNT_LAW_HO, ASC_CNT_LAW_VIPK, ASC_BGL_HOLD_OMS, ASC_BGL_HOLD_DT, ASC_OMS_F, ASC_CNT_DUMP_DELAY, ASC_BGL_HOLD_TMAX,
      ASC_CNT_LAW_REL),   // [25] THE REL GATE (an older KalsCoproc.dll reads [0..24] only: no gate)
    "ASC_CNT_LAW_K", ASC_CNT_LAW_K, "ASC_CNT_LAW_ENDS", ASC_CNT_LAW_ENDS, "ASC_CNT_LATE_M2", ASC_CNT_LATE_M2,
    "ASC_CNT_LATE_M2_VI", ASC_CNT_LATE_M2_VI).
}

// "" when the addon can run the pad search, else why not
FUNCTION padcs_why {
  IF NOT ADDONS:HASSUFFIX("KALS") { RETURN "no KAL/S addon". }
  IF NOT ADDONS:KALS:AVAILABLE { RETURN "KAL/S not available". }
  IF NOT ADDONS:KALS:HASSUFFIX("PADSEARCH") { RETURN "the KAL/S dll has no PADSEARCH". }
  RETURN "".
}

// E TAL's inputs (ard_et_new's, from the search kOS just made: asc_etl_new)
FUNCTION padcs_in_etl {
  PARAMETER ej.
  RETURN LEXICON("p0", ej["p0"], "vh", ej["vh"], "sn", ej["sn"], "tls", ej["tls"], "iy", ej["iy"], "sv", ej["sv"]).
}

// the ARD's inputs: the pad state p0 and vehicle vh (ard_et_s1's), the snapshot a without its state (the C# flies stage 1
// to the separation first), the seeds, the sites, the search's levels / counts / PPD cache S0 (after ard_srch_reset)
FUNCTION padcs_in_ard {
  PARAMETER S0, p0, vh, a, seed.
  RETURN LEXICON("p0", p0, "vh", vh, "a", a, "seed", seed, "tls", S0["tls"], "lv", S0["lv"], "nrun", S0["nrun"],
    "u", S0["u"], "nref", S0["nref"], "ok2", S0["ok2"], "rtl", S0["rtl"]).
}

// E TAL's result into its search ej (the keys ard_et_unit leaves; its nominal snapshots and last job stay out)
FUNCTION padcs_apply_etl {
  PARAMETER ej, cr.
  FOR k IN cr:KEYS { IF k <> "trials" { SET ej[k] TO cr[k]. } }
}

// the ARD's result into S, after ard_srch_reset and ard_srch_go with the snapshot a (the separation's state): what
// ard_srch_unit's path, levels and rank leave, the log lines (S["msg"]) as ard_lv_end / ard_rk_unit write them
FUNCTION padcs_apply_ard {
  PARAMETER S, cr.
  SET S["pj"] TO LEXICON().
  SET S["fj"] TO LEXICON().
  SET S["pts"] TO cr["pts"].
  SET S["u"] TO cr["u"].
  IF cr["nopath"] { SET S["ph"] TO 0. RETURN. }
  FOR x IN S["lv"] {
    FOR y IN cr["lv"] {
      IF y["key"] = x["key"] {
        FOR k IN LIST("tb", "vb", "lat", "note", "nc", "bv", "nq") { SET x[k] TO y[k]. }
      }
    }
  }
  FOR ev IN cr["ev"] {
    IF ev[0] = "L" { S["msg"]:ADD(ev[1] + "," + ev[2] + "," + ev[3] + "," + ev[4] + "," + ev[5] + "," + ev[6] + "," + ev[7]). }
    ELSE IF ev[0] = "RK" { S["msg"]:ADD("RK," + ev[1] + "," + ROUND(ev[2], 1) + "," + ev[3] + "," + ev[4]). }
    ELSE { S["msg"]:ADD("RK END," + ev[1]). }
  }
  SET S["k0s"] TO cr["k0s"].
  SET S["dn"] TO cr["dn"].
  IF cr["rtl"]:HASKEY("mbo") { SET S["rtl"] TO cr["rtl"]. }
  SET S["li"] TO S["lv"]:LENGTH.
  SET S["nref"] TO cr["nref"].
  SET S["ok2"] TO cr["ok2"].
  IF cr["rank"] {
    LOCAL L IS LIST().
    LOCAL ne IS MIN(S["nrun"], 2).
    FOR st IN S["tls"]:KEYS { L:ADD(ard_lv_new("TAL_RK_" + st, "TAL_RK", ne, "TAL", st, S["tls"][st])). }
    SET S["rk_l"] TO L.
    SET S["rk_k"] TO L:LENGTH.
    SET S["rk_j"] TO LEXICON().
    FOR st IN cr["rk"]:KEYS { SET S["rk"][st] TO cr["rk"][st]. }
    SET S["rk_t"] TO S["t_ref"].
  }
  SET S["ph"] TO 0.
}

// the sweep's result into bg (bgl_start + bgl_unit's to its end) and the globals bgl_windows sets
FUNCTION padcs_apply_bgl {
  PARAMETER bg, pts, tref, cr.
  SET bg["pts"] TO pts.
  SET bg["t_ref"] TO tref.
  SET bg["k"] TO pts:LENGTH.
  SET bg["iy"] TO 0.
  SET bg["gp"] TO cr["gp"].
  SET bg["md"] TO cr["md"].
  SET bg["best"] TO cr["best"].
  SET bg["u"] TO bg["u"] + cr["u"].
  SET bg["ph"] TO 0.
  SET bg["nsw"] TO bg["nsw"] + 1.
  SET bg["live"] TO TRUE.
  SET bg["skip"] TO 0.
  SET ASC_ABR_CONT[0] TO cr["cont0"].
  SET ASC_BGL_YAW TO cr["yaw"].
  SET ASC_BGL_EARLY TO cr["early"].
  SET ASC_BGL_MD TO cr["mdl"].
}
