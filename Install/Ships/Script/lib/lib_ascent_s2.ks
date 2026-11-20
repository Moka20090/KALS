// lib_ascent_s2.ks -- the second stage of ops1q.ks around PEG (lib_ascent_peg.ks): the pass schedule, G-LIM (FSSR
// 4.8.3), the fine count and the cutoff (4.8.5, MPS GUID C/O), ported from an offline UPFG model's class
// Guidance; the vehicle's side (the SSMEs, the burnable ET load). Vectors are inertial (lib_ascent_peg's frame).
@LAZYGLOBAL OFF.

// Gravity with J2 (upfg.py's grav): the sensed velocity change is the inertial one less this, as an IMU senses it.
FUNCTION asc_grav {
  PARAMETER rr.
  LOCAL r2 IS rr:SQRMAGNITUDE.
  LOCAL rm IS SQRT(r2).
  LOCAL gm IS -ASC_MU / (r2 * rm).
  LOCAL k IS -1.5 * ASC_J2 * ASC_MU * ASC_R_J2 * ASC_R_J2 / (r2 * r2 * rm).
  LOCAL zz IS 5 * rr:Z * rr:Z / r2.
  RETURN V(gm * rr:X + k * rr:X * (1 - zz), gm * rr:Y + k * rr:Y * (1 - zz), gm * rr:Z + k * rr:Z * (3 - zz)).
}

// A new second stage at MET t_sep (the SRB separation) on the sample (rr, vv); hold = the direction flown until PEG's
// first good pass (stage 1's zero-alpha direction at the separation, held inertially).
FUNCTION asc_s2_new {
  PARAMETER peg, t_sep, rr, vv, hold.
  RETURN LEXICON("peg", peg, "hold", hold, "K_CMD", ASC_KMAX, "glim_on", FALSE, "AD", ASC_AD_INIT, "SUM_DA", 0,
    "T_KCMD", 0, "S_MECO", FALSE, "S_KCO", FALSE, "t_fc", -1, "T_MECO", -1, "TGO_FC", -1, "t_sep", t_sep,
    "k_pass", 0, "next_pass", t_sep, "j_fc", 0, "next_fc", -1, "t_pass_prev", -1, "t_fc_prev", -1,
    "dv", V(0, 0, 0), "dv_pass", V(0, 0, 0), "dv_fc", V(0, 0, 0),
    "t_prev", t_sep, "r_prev", rr, "v_prev", vv, "g_prev", asc_grav(rr),
    "dvs_last", V(0, 0, 0), "M_last", 0, "VEX_last", 0, "ATR_last", 0).
}

// The sensed velocity change, summed: each sample adds the inertial change less the trapezoid of gravity.
FUNCTION asc_s2_sense {
  PARAMETER g, t, rr, vv.
  IF t <= g["t_prev"] { RETURN. }
  LOCAL gr IS asc_grav(rr).
  SET g["dv"] TO g["dv"] + (vv - g["v_prev"]) - 0.5 * (t - g["t_prev"]) * (gr + g["g_prev"]).
  SET g["t_prev"] TO t. SET g["r_prev"] TO rr. SET g["v_prev"] TO vv. SET g["g_prev"] TO gr.
}

// G-LIM: the PI loop on the measured acceleration; K_CMD (PL %) at most every TLAG s, between KMIN and KMAX.
FUNCTION asc_glim {
  PARAMETER g, t, AT_AVE, dtgd.
  IF AT_AVE < ASC_ALIM_1 {
    SET g["AD"] TO ASC_AD_INIT. SET g["SUM_DA"] TO 0. SET g["glim_on"] TO FALSE.
    RETURN.
  }
  IF AT_AVE > ASC_ALIM_2 OR g["glim_on"] {
    SET g["glim_on"] TO TRUE.
    LOCAL DA IS AT_AVE - ASC_AL.
    SET g["SUM_DA"] TO g["SUM_DA"] + DA * dtgd.
    SET g["AD"] TO g["AD"] - (DA * ASC_K_PROP + g["SUM_DA"] * ASC_K_INT) * dtgd.
    IF t - g["T_KCMD"] > ASC_TLAG {
      LOCAL k IS asc_mid(ASC_KMIN, FLOOR(g["K_CMD"] * g["AD"] / AT_AVE + 0.5), ASC_KMAX).
      IF k <> g["K_CMD"] { SET g["T_KCMD"] TO t. }
      SET g["K_CMD"] TO k.
    }
  }
}

// SW 02 GUIDANCE LOST in the ascent: TRUE while the ACTIVE list holds it (O(1) with no failure). The flown guidance
// passes (asc_s2_pass, asc_rtls_cycle) return at once: no G-LIM, no PEG cycle, the last command stays; the C# DAP releases to CSS
// DAP_GD_LOST_S later (ops1q asc_sw1 = flfxSwAutoLost). The ARD's trace jobs call asc_peg_cycle on their own copy and are not held.
FUNCTION asc_gdl {
  IF DEFINED FLFX_SWPROG { RETURN flfxSwGuid("ASCENT"). }
  RETURN FALSE.
}
// A guidance pass: G-LIM before PEG (until the cutoff throttle); PEG until TGO <= TGO_FCD, where the fine count takes
// over (Event 31). M t, VEX m/s, FMAX kN: the SSMEs' thrust at full KSP throttle at the current pressure.
FUNCTION asc_s2_pass {
  PARAMETER g, t, rr, vv, M, VEX, FMAX.
  IF asc_gdl() { RETURN. }                 // SW 02 ASCENT holds the pass (dv_pass / t_pass_prev stay: the first pass after a RESTART SW takes the whole interval)
  LOCAL dvs IS g["dv"] - g["dv_pass"].
  LOCAL dtgd IS 0.
  IF g["t_pass_prev"] >= 0 { SET dtgd TO t - g["t_pass_prev"]. }
  SET g["dv_pass"] TO g["dv"].
  SET g["t_pass_prev"] TO t.
  LOCAL AT_AVE IS 0.
  IF dtgd > 0 { SET AT_AVE TO dvs:MAG / dtgd. }
  IF NOT g["S_KCO"] { asc_glim(g, t, AT_AVE, dtgd). }
  IF NOT g["S_MECO"] AND VEX > 0 AND FMAX > 0 {
    LOCAL ATR IS ASC_FT_FACTOR * (g["K_CMD"] / 100 * ASC_PL_TO_KSP * FMAX) / M.
    asc_peg_cycle(g["peg"], t, rr, vv, dvs, M, VEX, ATR).
    SET g["dvs_last"] TO dvs. SET g["M_last"] TO M. SET g["VEX_last"] TO VEX. SET g["ATR_last"] TO ATR.
    IF g["peg"]["TGO"] <= ASC_TGO_FCD {
      SET g["S_MECO"] TO TRUE. SET g["t_fc"] TO t. SET g["j_fc"] TO 1. SET g["next_fc"] TO t + ASC_DT_FCD.
      SET g["dv_fc"] TO g["dv"]. SET g["t_fc_prev"] TO t.
    }
  }
}

// The fine count: the cutoff throttle KMIN when the speed to go fits the ramp and DT_MIN_K s at KMIN; T_MECO once TGO
// on the speed (with gravity along the path) is under STG2_MECO_INIT_TGO.
FUNCTION asc_fine {
  PARAMETER g, t, rr, vv.
  LOCAL dvs IS g["dv"] - g["dv_fc"].
  LOCAL dtg IS t - g["t_fc_prev"].
  SET g["dv_fc"] TO g["dv"].
  SET g["t_fc_prev"] TO t.
  LOCAL VMAG IS vv:MAG.
  LOCAL AT_FCD IS VDOT(vv, dvs) / (VMAG * dtg).
  LOCAL K_CO IS ASC_KMIN.
  LOCAL DV_RAMP IS (g["K_CMD"] + K_CO) * ABS(g["K_CMD"] - K_CO) * AT_FCD / (2 * g["K_CMD"] * ASC_KDOT).
  LOCAL DV_MIN_K IS AT_FCD * ASC_DT_MIN_K * K_CO / g["K_CMD"].
  LOCAL VGO_FCD IS g["peg"]["VDMAG"] - VMAG.
  IF VGO_FCD < AT_FCD * ASC_DT_FCD + DV_RAMP + DV_MIN_K { SET g["K_CMD"] TO K_CO. SET g["S_KCO"] TO TRUE. }
  LOCAL G_V IS -g["peg"]["mu"] * VDOT(rr, vv) / (rr:MAG ^ 3 * VMAG).
  LOCAL TGO IS VGO_FCD / (AT_FCD + G_V) - ASC_DT_TAILOFF.
  SET g["TGO_FC"] TO TGO.
  IF TGO < ASC_STG2_MECO_INIT_TGO { SET g["T_MECO"] TO t + MAX(0, TGO). }
}

// Is a pass or a fine count due at MET t? (Then sample, and run asc_s2_tasks on the sample.)
FUNCTION asc_s2_due {
  PARAMETER g, t.
  IF NOT (g["S_MECO"] AND g["S_KCO"]) AND t >= g["next_pass"] - 1e-9 { RETURN TRUE. }
  RETURN g["S_MECO"] AND g["T_MECO"] < 0 AND t >= g["next_fc"] - 1e-9.
}

// The due tasks on a sample at MET t: a pass every DTGD s from t_sep, a fine count every DT_FCD s from Event 31.
FUNCTION asc_s2_tasks {
  PARAMETER g, t, rr, vv, M, VEX, FMAX.
  asc_s2_sense(g, t, rr, vv).
  IF NOT (g["S_MECO"] AND g["S_KCO"]) AND t >= g["next_pass"] - 1e-9 {
    asc_s2_pass(g, t, rr, vv, M, VEX, FMAX).
    SET g["k_pass"] TO g["k_pass"] + 1.
    SET g["next_pass"] TO g["t_sep"] + g["k_pass"] * ASC_DTGD.
  }
  IF g["S_MECO"] AND g["T_MECO"] < 0 AND t >= g["next_fc"] - 1e-9 {
    asc_fine(g, t, rr, vv).
    SET g["j_fc"] TO g["j_fc"] + 1.
    SET g["next_fc"] TO g["t_fc"] + g["j_fc"] * ASC_DT_FCD.
  }
}

// ---- the vehicle
// the lit liquid engines (the SSMEs): no throttle lock
FUNCTION asc_liquids {
  LOCAL es IS LIST().
  LOCAL out IS LIST().
  LIST ENGINES IN es.
  FOR en IN es { IF en:IGNITION AND NOT en:THROTTLELOCK { out:ADD(en). } }
  RETURN out.
}

// The propellant mass (t) the engines can still burn: their mixture's units in the scarcer propellant times the
// mixture's mass per unit (the amounts the engines reach, by KSP's crossfeed: the ET's LH2 and LOX).
FUNCTION asc_burnable {
  PARAMETER engs.
  IF engs:LENGTH = 0 { RETURN 0. }
  LOCAL n IS -1.
  LOCAL mm IS 0.
  FOR cr IN engs[0]:CONSUMEDRESOURCES:VALUES {
    IF cr:RATIO > 0 {
      LOCAL k IS cr:AMOUNT / cr:RATIO.
      IF n < 0 OR k < n { SET n TO k. }
      SET mm TO mm + cr:RATIO * cr:DENSITY.
    }
  }
  RETURN MAX(n, 0) * mm.
}

// LIST(FMAX kN, VEX m/s): the engines' thrust at full KSP throttle at the current pressure, and their exhaust speed
// (the thrust-weighted Isp times g0).
FUNCTION asc_thrust {
  PARAMETER engs.
  LOCAL f IS 0.
  LOCAL fi IS 0.
  FOR en IN engs {
    LOCAL a IS en:AVAILABLETHRUST.
    SET f TO f + a.
    IF en:ISP > 0 { SET fi TO fi + a / en:ISP. }
  }
  IF fi <= 0 { RETURN LIST(f, 0). }
  RETURN LIST(f, CONSTANT:G0 * f / fi).
}

// every engine of the list out (a flame-out ends the burn)
FUNCTION asc_all_out {
  PARAMETER engs.
  FOR en IN engs { IF NOT en:FLAMEOUT { RETURN FALSE. } }
  RETURN TRUE.
}

// every engine of the list dead: flamed out or not lit (shut down by hand: IGNITION false, FLAMEOUT false); the SSMEs'
// MECO "out" (asc_all_out stays for the OMS engines, which are not lit before their burn)
FUNCTION asc_all_dead {
  PARAMETER engs.
  FOR en IN engs { IF en:IGNITION AND NOT en:FLAMEOUT { RETURN FALSE. } }
  RETURN TRUE.
}

// THE q x ALPHA LIMIT (ops1q's asc_qa_limit steers by it, the HUD's cue shows it): alpha is the angle of the unit
// wind w to the nose in the pitch plane of the attitude d (|deg|, 0 .. 180; yaw off that plane does not count), as the
// cue reads it.
FUNCTION asc_qa_alpha {
  PARAMETER d, w.
  RETURN ARCTAN2(ABS(VDOT(w, d:TOPVECTOR)), VDOT(w, d:FOREVECTOR)).
}

// the HUD's lag for the cue's DEMANDED pointer (ops1q ascHudQa, ASC_HUD_SM_TAU as the diamond's): the first-order
// lag of the last value prev (< 0: none yet) to cur after dt s. No lag without a previous value, with tau <= 0 or after a
// gap above 1 s (the cue was hidden / the loop stalled); the same tick (dt <= 0) keeps prev. A value between prev and cur,
// so a demanded value at or under the limit stays at or under it
FUNCTION asc_qa_lag {
  PARAMETER prev, dt, tau, cur.
  IF prev < 0 OR tau <= 0 OR dt > 1 { RETURN cur. }
  IF dt <= 0 { RETURN prev. }
  RETURN prev + (1 - CONSTANT:E ^ (-dt / tau)) * (cur - prev).
}

// the limit's turn for d at q kPa and lim kPa deg: LIST(alpha, the most alpha lim / q, d's nose turned to it) when
// alpha is above lim / q, else LIST() (also for q <= 0, a wind nearly along d's pitch axis, or lim / q at 180 deg or
// more: below lim / 180 kPa nothing is limited). The new nose lies in d's pitch plane at lim / q from the wind's part in
// that plane, on the nose's side of it: ROTATEFROMTO(d's nose, it) turns d about its own pitch axis (the roll and the
// pitch axis kept) and its alpha is then lim / q exactly
FUNCTION asc_qa_fix {
  PARAMETER d, w, qk, lim.
  IF qk <= 0 { RETURN LIST(). }
  LOCAL am IS lim / qk.
  LOCAL al IS asc_qa_alpha(d, w).
  IF al <= am { RETURN LIST(). }
  LOCAL sv IS d:STARVECTOR.
  LOCAL wp IS w - VDOT(w, sv) * sv.
  IF wp:MAG < 0.01 { RETURN LIST(). }
  SET wp TO wp:NORMALIZED.
  LOCAL f IS d:FOREVECTOR.
  LOCAL n IS f - VDOT(f, wp) * wp.
  IF n:MAG < 0.000001 { SET n TO d:TOPVECTOR - VDOT(d:TOPVECTOR, wp) * wp. }   // the nose straight down-wind
  SET n TO n:NORMALIZED.
  RETURN LIST(al, am, COS(am) * wp + SIN(am) * n).
}
