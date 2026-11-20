// lib_ascent_s1.ks -- the first stage of ops1q.ks: FSSR 4.2.3 (BST GUID TSK) and 4.2.4 (BST THROT TSK), as the offline
// sim's stage 1. The I-loads are lib_ascent_iload.ks (ASC_*). Pitch is above the local horizontal and
// the heading is from north (kOS's HEADING), not the FSSR's inertial boost frame; no wind, engine-out, adaptive or
// load-relief parts (KSP has no wind and deterministic SRBs).
@LAZYGLOBAL OFF.

// VREL_AERO_REF: the relative speed scaled by the I-loaded speed of sound, which is held at its ALTSS value above ALTSS.
FUNCTION asc_vref {
  PARAMETER vrel, hgt.
  RETURN vrel * ASC_SSSL / (ASC_SSSL - ASC_DSSA * MIN(MAX(hgt, 0), ASC_ALTSS)).
}

// The table index climbs while x >= P(i + 1), up to the last segment (the FSSR's I <= 29); it never comes down.
FUNCTION asc_seg {
  PARAMETER P, i, x.
  UNTIL i >= P:LENGTH - 2 OR x < P[i + 1] { SET i TO i + 1. }
  RETURN i.
}

// The segment interpolation in tangent quarter angles (Y in deg at the breakpoints P); past the last breakpoint the last
// segment extrapolates, as in the FSSR.
FUNCTION asc_tab {
  PARAMETER P, Y, i, x.
  LOCAL y0 IS TAN(Y[i] / 4).
  LOCAL y1 IS TAN(Y[i + 1] / 4).
  RETURN 4 * ARCTAN(y0 + (y1 - y0) / (P[i + 1] - P[i]) * (x - P[i])).
}

// A new first-stage state: past the tower clear, the table index, the pitch tangent at T_CNS (-99 = not yet), the
// throttle step index and the throttle command (PL %).
FUNCTION asc_s1_new {
  RETURN LEXICON("clear", FALSE, "i", 0, "thetc_cns", -99, "j", 0, "k_cmd", ASC_K_STAGE1).
}

// One pass: LIST(pitch, heading, roll) in deg, or an empty LIST() during the vertical rise (the pad attitude holds).
FUNCTION asc_s1_att {
  PARAMETER s1, met, vrel, hgt.
  IF NOT s1["clear"] {
    IF vrel < ASC_PPOLY[1] { RETURN LIST(). }
    SET s1["clear"] TO TRUE.
  }
  LOCAL x IS asc_vref(vrel, hgt).
  SET s1["i"] TO asc_seg(ASC_PPOLY, s1["i"], x).
  LOCAL i IS s1["i"].
  LOCAL th IS asc_tab(ASC_PPOLY, ASC_THET, i, x).
  LOCAL ps IS asc_tab(ASC_PPOLY, ASC_PSI, i, x).
  // the tail-off: from T_CNS_PITCH_RATE the pitch tangent runs at a constant rate from the table's value there
  IF met >= ASC_T_CNS_PITCH_RATE {
    IF s1["thetc_cns"] = -99 { SET s1["thetc_cns"] TO TAN(th / 4). }
    SET th TO 4 * ARCTAN(s1["thetc_cns"] + 0.25 * ASC_THETC_DOT_NOM_RAD * (met - ASC_T_CNS_PITCH_RATE)).
  }
  // the roll on the first 15 breakpoints, held at PHI15 past them
  LOCAL ph IS ASC_PHI[ASC_PHI:LENGTH - 1].
  IF i < ASC_PHI:LENGTH - 1 { SET ph TO asc_tab(ASC_PPOLY, ASC_PHI, i, x). }
  // the launch-target box (lib_ascent_gui): the table turned by ASC_HDG_DELTA, mirrored for a southbound launch
  SET ps TO ps + ASC_HDG_DELTA.
  IF ASC_LAUNCH_DIR < 0 { SET ps TO 180 - ps. }
  RETURN LIST(th, ps, ph).
}

// The boost throttle (4.2.4): K_CMD (PL %) steps to THROT(J) when V_rel >= QPOLY(J), at most four steps.
FUNCTION asc_s1_thr {
  PARAMETER s1, vrel.
  LOCAL n IS MIN(ASC_QPOLY:LENGTH, 4).
  UNTIL s1["j"] >= n {
    IF vrel < ASC_QPOLY[s1["j"]] { BREAK. }
    SET s1["k_cmd"] TO ASC_THROT[s1["j"]].
    SET s1["j"] TO s1["j"] + 1.
  }
  RETURN s1["k_cmd"].
}

// The SRBs: the engines whose throttle is locked (solid motors).
FUNCTION asc_srbs {
  LOCAL es IS LIST().
  LOCAL out IS LIST().
  LIST ENGINES IN es.
  FOR en IN es { IF en:THROTTLELOCK { out:ADD(en). } }
  RETURN out.
}

// The SRB separation's time backup (MET s): the separation is commanded here if the burnout cue never comes (no SRB
// lit, or one that never flames out). The real Shuttle's cue is both SRBs' chamber pressure under 50 psi, with a
// time backup no later than MET 2:20, about 13 % past its nominal separation (~2:04). Ours: the nominal separation at
// MET 80.0 s x 1.13.
GLOBAL ASC_SRB_SEP_BKUP IS 90.

// The SRB burnout: every SRB has flamed out.
FUNCTION asc_srb_out {
  PARAMETER srbs.
  IF srbs:LENGTH = 0 { RETURN FALSE. }
  FOR en IN srbs { IF NOT en:FLAMEOUT { RETURN FALSE. } }
  RETURN TRUE.
}

// ---- THE SPLIT-S's LAWS (ops1q.ks's header has the sequence they fly). NOT FSSR: the split-S was an uncertified
// abort; the loft is the 1987 scheme's (Sponaugle & Fernandes, AIAA 87-2398: the stack lofted to the SRB burnout, then
// the orbiter off the SRBs + ET as a whole). The laws are the offline sim's loft steering (checked against it in kOS's
// VM); the I-loads here, ops1q's settings over them (asc_s1c_cfg's copy).
GLOBAL ASC_S1C_TH IS 90.         // deg: the loft's pitch cap (the offline sim's TH)
GLOBAL ASC_S1C_AMAX IS 15.       // deg: the loft's alpha, heads down (AMAX; 0 = the table's pitch, no loft)
GLOBAL ASC_S1C_QA IS 0.          // kPa deg: the loft's q-alpha cap (QA; 0 = none, the offline sim's 1e5)
GLOBAL ASC_S1C_TRAMP IS 5.       // s: the loft blended in from the failure (T_RAMP)
GLOBAL ASC_S1C_TA0 IS 74.        // MET s: from here (or the failure, if later) the nose turns onto the relative wind
GLOBAL ASC_S1C_TA1 IS 78.        // MET s: on it from here to the sep (alpha and sideslip 0); the OMS dump paused here
GLOBAL ASC_S1C_OMS_DLY IS 5.     // s: the OMS dump from the failure + this, to TA1
GLOBAL ASC_S1C_WAIT IS 5.        // s: the crew's window after a 2EO for a BAILOUT (then the split-S
                                 // by default; the split-S flies meanwhile); 0 = none
GLOBAL ASC_S1C_BAIL_MET IS 56.   // MET s: a 2EO armed at or after this defaults to BAILOUT (the split-S
                                 // cannot reach the SLF, lands to 68 s stock, 60 s FAR,
                                 // about 4 s less for the sim's 1 km EOW-EN optimism against the flown case); the
                                 // crew's window still offers SPLITS; with no window it bails at once; 0 = never
GLOBAL ASC_S1C_ALPHA IS 38.      // deg: the sequence's alpha after the sep (OPS 6's split-S alpha:
                                 // lib_grtls SS_ALPHA)
GLOBAL ASC_S1C_NZ IS 2.5.        // g: its Nz limit (alpha 45 at the sep's q would pull 4-13 g, offline)
GLOBAL ASC_S1C_NZ_BAND IS 0.15.  // g: within this below the limit alpha is held, not raised
GLOBAL ASC_S1C_HOLD IS 0.        // s: alpha held 0 after the sep (0: up from the sep; measured with 1 s the orbiter
                                 // recontacted the ET: the decoupler's kick turned the nose onto it during the hold)
GLOBAL ASC_S1C_RATE IS 5.        // deg/s: alpha up (and down over the Nz limit)
GLOBAL ASC_S1C_OMS_EPS IS 17.84. // deg: the OMS thrust line below the nose axis (every launch craft, measured)
GLOBAL ASC_S1C_UP_MORE IS 5.     // s: the up RCS after the OMS is on
GLOBAL ASC_S1C_UP_T IS 78.       // MET s: the up RCS on from here, before the sep; < 0 = at the sep
GLOBAL ASC_S1C_A0 IS 3.          // deg: the alpha command at the sep, then up at RATE (measured: from 0
                                 // the steering waited ~0.5 s while the free orbiter pitched 4 deg toward the ET)
GLOBAL ASC_S1C_TS IS 0.5.        // s: the pitch steering's response time (STEERINGMANAGER:PITCHTS) from the sep to
                                 // DONE (kOS's default 2 s); <= 0 = left as it is
GLOBAL ASC_S1C_SEQ_MAX IS 20.    // s: the sequence's end at the latest (the OMS line not reached)
GLOBAL ASC_S1C_SAT IS 0.95.      // the guard: the SRBs' pitch gimbal at this fraction of its range ...
GLOBAL ASC_S1C_SAT_T IS 0.5.     // s: ... this long ...
GLOBAL ASC_S1C_BACK IS 2.        // deg/s: ... lowers the loft's alpha at this rate while it stays there

// the I-loads as one LEXICON (ops1q copies it at the arming, the settings before the run over it)
FUNCTION asc_s1c_cfg {
  RETURN LEXICON("th", ASC_S1C_TH, "amax", ASC_S1C_AMAX, "qa", ASC_S1C_QA, "tramp", ASC_S1C_TRAMP, "ta0", ASC_S1C_TA0,
    "ta1", ASC_S1C_TA1, "oms_dly", ASC_S1C_OMS_DLY, "alpha", ASC_S1C_ALPHA, "nz", ASC_S1C_NZ, "nz_band",
    ASC_S1C_NZ_BAND, "hold", ASC_S1C_HOLD, "rate", ASC_S1C_RATE, "eps", ASC_S1C_OMS_EPS, "up_more", ASC_S1C_UP_MORE,
    "seq_max", ASC_S1C_SEQ_MAX, "sat", ASC_S1C_SAT, "sat_t", ASC_S1C_SAT_T, "back", ASC_S1C_BACK, "t_eo", 0,
    "up_t", ASC_S1C_UP_T, "a0", ASC_S1C_A0, "ts", ASC_S1C_TS, "wait", ASC_S1C_WAIT, "bail", ASC_S1C_BAIL_MET).
}

// The loft's pitch (deg above the horizon): the table's th_tab raised to MIN(TH, gam + MIN(AMAX, QA / qk)) (gam the path
// angle on the relative wind, qk kPa), never below the table's, blended in over TRAMP s from the failure (c["t_eo"])
FUNCTION asc_s1c_pitch {
  PARAMETER th_tab, gam, qk, met, c.
  IF c["amax"] <= 0 { RETURN th_tab. }
  LOCAL al IS c["amax"].
  IF c["qa"] > 0 AND qk > 0.001 { SET al TO MIN(al, c["qa"] / qk). }
  LOCAL thl IS MAX(th_tab, MIN(c["th"], gam + al)).
  LOCAL w IS 1.
  IF c["tramp"] > 0 { SET w TO MIN(1, MAX(0, (met - c["t_eo"]) / c["tramp"])). }
  RETURN (1 - w) * th_tab + w * thl.
}

// The nose's turn onto the relative wind: 0 before MAX(TA0, the failure), then up to 1 at TA1 (the offline sim's 1 - z)
FUNCTION asc_s1c_wind {
  PARAMETER met, c.
  LOCAL ta0 IS MAX(c["ta0"], c["t_eo"]).
  IF met < ta0 { RETURN 0. }
  IF c["ta1"] <= ta0 { RETURN 1. }
  RETURN MIN(1, (met - ta0) / (c["ta1"] - ta0)).
}

// The sequence's alpha command (deg) after the sep: a the last one, ts s since the sep, dt the tick, nz the Nz (g): A0
// for HOLD s (asc_s1c_sep starts it at A0), then up at RATE deg/s to ALPHA, held within NZ_BAND below the Nz limit,
// down at RATE over it
FUNCTION asc_s1c_acmd {
  PARAMETER a, ts, dt, nz, c.
  IF ts < c["hold"] { RETURN c["a0"]. }
  IF nz > c["nz"] { RETURN MAX(0, a - c["rate"] * dt). }
  IF nz > c["nz"] - c["nz_band"] { RETURN a. }
  RETURN MIN(c["alpha"], a + c["rate"] * dt).
}
