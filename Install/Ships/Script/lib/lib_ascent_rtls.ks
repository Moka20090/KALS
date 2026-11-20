// lib_ascent_rtls.ks -- the powered RTLS of ops1q.ks (FSSR STS 83-0002-34 4.6: MM 601 init, fuel dissipation,
// flyback, powered pitchdown; 4.8.5's RTLS cutoff), the offline sim's RTLS guidance in kOS; PEG's RTLS mode is
// lib_ascent_peg.ks's (p["RTLS"]). The site is the launch site's own runway (ASC_RTLS_SITE: ops1q's pick,
// lib_ascent_gui's asc_site_set: the SLF from KSC, Vandenberg from SLC-6); the I-loads ASC_RTLS_* are this vehicle's
// (lib_ascent_iload.ks).
// Vectors are inertial (lib_ascent_peg's frame), angles in deg. The state rl (asc["rl"]):
//   "mode"  "fd" fuel dissipation, "turn" the pitcharound, "fb" flyback, "fc" the fine countdown, "ppd" the pitchdown,
//           "m5" FSSR 4.9.7 mode 5 after a second SSME out (asc_rtls_m5)
//   "cmd"   LIST(kind, u): "fix" / "ppd" hold u, "peg" PEG's steering; "slew" asc_rtls_slew's LIST(t0, u0, u1, the
//           peak rate deg/s, t1, the angle deg) or empty
// A deviation (the offline sim is 3-DOF): the attitude's top is u x n, n = az x up at the selection (heads down at the
// start, turning with the thrust through the vertical, heads up on the flyback); the pitchdown puts the nose (not the
// thrust) at ALPHA_PPD by the measured thrust axis (rl["toff"], deg, set by ops1q); the first slew starts from the
// attitude flown at the selection (the offline sim's from the separation attitude: it resets PEG before the slew is set).
@LAZYGLOBAL OFF.

// u0 turned by ang deg toward u1 on their great circle (u0, u1 unit)
FUNCTION asc_rot_toward {
  PARAMETER u0, u1, ang.
  LOCAL c IS MAX(-1, MIN(1, VDOT(u0, u1))).
  LOCAL th IS ARCCOS(c).
  IF th < 1e-7 { RETURN u1. }
  LOCAL w IS (u1 - c * u0):NORMALIZED.
  LOCAL a IS MIN(ang, th).
  RETURN COS(a) * u0 + SIN(a) * w.
}

// the earth rate x r (m/s): the relative velocity is v less this
FUNCTION asc_rtls_wxr {
  PARAMETER rl, rr.
  RETURN VCRS(V(0, 0, rl["w"] * CONSTANT:DEGTORAD), rr).
}

// the PPD's start attitude in use (deg above V_rel): THETA_PPD0, or THETA_PPD0_3ENG for an RTLS begun on 3 SSMEs (the
// 3-engine PPD; asc_rtls_init sets it)
GLOBAL asc_rtls_th0 IS ASC_RTLS_THETA_PPD0.
// the time to PPA (fuel dissipation): the filter gain on the rate MF falls, pass to pass
GLOBAL ASC_RTLS_PPA_FILT IS 0.3.
// THE PPA WAIT: in an RTLS the time to PPA jumps around early on (to ~T+2:30), so the page shows it once the predicted
// PPA MET (t + the time to PPA) has drifted at most ASC_RTLS_PPA_DRIFT s/s pass to pass for ASC_RTLS_PPA_HOLD s; a drift
// over ASC_RTLS_PPA_JUMP hides it again (the test starts over). Measured on flown RTLSs: shown at T+2:43 / 2:58, 11 / 6 s
// early on the PPA and converging. ASC_RTLS_PPA_WAIT FALSE: shown at once.
GLOBAL ASC_RTLS_PPA_WAIT IS TRUE.
GLOBAL ASC_RTLS_PPA_DRIFT IS 0.5.   // s/s
GLOBAL ASC_RTLS_PPA_HOLD IS 10.     // s
GLOBAL ASC_RTLS_PPA_JUMP IS 2.      // s/s
// the PPA wait: the settle test on the time to PPA (rl["tpa"], this pass at t): rl["tpa_on"] for the page
FUNCTION asc_rtls_ppa_settle {
  PARAMETER rl, t.
  IF NOT ASC_RTLS_PPA_WAIT { SET rl["tpa_on"] TO TRUE. RETURN. }
  IF rl["tpa"] < 0 {
    SET rl["tpa_on"] TO FALSE. SET rl["pa_ok"] TO -1. SET rl["pa_p"] TO -1.
    RETURN.
  }
  LOCAL pa IS t + rl["tpa"].
  IF rl["pa_p"] >= 0 AND t > rl["pa_t"] + 0.1 {
    LOCAL dr IS ABS(pa - rl["pa_p"]) / (t - rl["pa_t"]).
    IF rl["tpa_on"] {
      IF dr > ASC_RTLS_PPA_JUMP { SET rl["tpa_on"] TO FALSE. SET rl["pa_ok"] TO -1. }
    } ELSE IF dr <= ASC_RTLS_PPA_DRIFT {
      IF rl["pa_ok"] < 0 { SET rl["pa_ok"] TO rl["pa_t"]. }
      IF t - rl["pa_ok"] >= ASC_RTLS_PPA_HOLD { SET rl["tpa_on"] TO TRUE. }
    } ELSE {
      SET rl["pa_ok"] TO -1.
    }
  }
  SET rl["pa_p"] TO pa.
  SET rl["pa_t"] TO t.
}

// the pitchdown's planned length (s): the slew (asc_rtls_slew's trapezoid at PPD_RATE) from asc_rtls_th0 to the ET
// separation attitude, and T_SETTLE
FUNCTION asc_rtls_dt_pitch {
  LOCAL th IS asc_rtls_th0 - (ASC_RTLS_ALPHA_PPD - ASC_RTLS_THRUST_OFF).
  RETURN asc_rtls_slew(0, 0, 0, th, ASC_RTLS_PPD_RATE)[4] + ASC_RTLS_T_SETTLE.
}

// THE C# PPD PREDICTION. asc_rtls_ppd_predict is ~53k opcodes in one call (asc_rtls_init at the RTLS selection: ~5
// physics ticks at IPU 10000); with ASC_RT_CS on and the KAL/S addon's RTPPD (coproc/RtlsPpd.cs, a line-for-line port)
// the addon flies it and kOS's own loop (asc_rtls_ppd_predict_k) does not run. Any addon
// error (an "error ..." string; nothing was touched) turns it off for the flight and kOS flies that call and the rest.
// Without the addon (or an older KalsCoproc.dll) kOS flies it. The rest of the RTLS and of the 2EO contingency stays
// kOS's (under ~1k opcodes a pass).
IF NOT (DEFINED ASC_RT_CS) { GLOBAL ASC_RT_CS IS TRUE. }
GLOBAL ASC_RT_CS_ON IS 0.               // the addon looked at: 0 not yet, 1 set up, -1 not there
GLOBAL ASC_RT_CS_AD IS 0.               // ADDONS:KALS once set up
GLOBAL ASC_RT_CS_ERR IS "".
GLOBAL ASC_RT_CS_N IS 0.                // the calls C# flew

FUNCTION asc_rt_cs_setup {
  SET ASC_RT_CS_ON TO -1.
  LOCAL why IS "".
  IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
  ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
  ELSE IF NOT ADDONS:KALS:HASSUFFIX("RTPPD") { SET why TO "the KAL/S addon has no RTLS PPD (an older KalsCoproc.dll)". }
  IF why = "" {
    SET ASC_RT_CS_AD TO ADDONS:KALS.
    SET ASC_RT_CS_ON TO 1.
    RETURN.
  }
  SET ASC_RT_CS_ERR TO why.
}

// The pitchdown in the vertical plane (point mass, central gravity and the centripetal term, no drag), the thrust from
// THETA_PPD0 above V_rel down to ALPHA_PPD - THRUST_OFF on the slew's trapezoid (PPD_RATE, DTHETA_RATE), at KMIN for
// dt_pitch: LIST(dV m/s, dgam deg, dx m).
// v0 m/s, gam0 deg, h0 m, m0 t, f kN, md t/s. C# (RTPPD) or kOS (asc_rtls_ppd_predict_k)
FUNCTION asc_rtls_ppd_predict {
  PARAMETER v0, gam0, h0, m0, f, md.
  IF ASC_RT_CS {
    IF ASC_RT_CS_ON = 0 { asc_rt_cs_setup(). }
    IF ASC_RT_CS_ON > 0 {
      LOCAL cr IS ASC_RT_CS_AD:RTPPD(LIST(v0, gam0, h0, m0, f, md, asc_rtls_th0, ASC_RTLS_ALPHA_PPD, ASC_RTLS_THRUST_OFF,
        asc_rtls_dt_pitch(), ASC_RTLS_PPD_RATE, ASC_R, ASC_MU, CONSTANT:DEGTORAD, CONSTANT:RADTODEG, ASC_RTLS_DTHETA_RATE)).
      IF cr:ISTYPE("List") {
        SET ASC_RT_CS_N TO ASC_RT_CS_N + 1.
        RETURN cr.
      }
      SET ASC_RT_CS_ERR TO cr.
      SET ASC_RT_CS TO FALSE.
    }
  }
  RETURN asc_rtls_ppd_predict_k(v0, gam0, h0, m0, f, md).
}

// kOS's own pitchdown prediction (asc_rtls_ppd_predict's body; the C# PPD's twin)
FUNCTION asc_rtls_ppd_predict_k {
  PARAMETER v0, gam0, h0, m0, f, md.
  LOCAL vel IS v0.
  LOCAL gm IS gam0 * CONSTANT:DEGTORAD.
  LOCAL hh IS h0.
  LOCAL xx IS 0.
  LOCAL ms IS m0.
  LOCAL th IS asc_rtls_th0.
  LOCAL th_end IS ASC_RTLS_ALPHA_PPD - ASC_RTLS_THRUST_OFF.
  LOCAL sp IS asc_rtls_slew(0, 0, 0, asc_rtls_th0 - th_end, ASC_RTLS_PPD_RATE).
  LOCAL tt IS asc_rtls_dt_pitch().
  LOCAL t IS 0.
  UNTIL t >= tt - 1e-9 {
    LOCAL dh IS MIN(0.02, tt - t).
    LOCAL rad IS ASC_R + hh.
    LOCAL gg IS ASC_MU / (rad * rad).
    LOCAL ac IS f / ms.
    LOCAL gd IS gm * CONSTANT:RADTODEG.
    LOCAL v1 IS vel + (ac * COS(th) - gg * SIN(gd)) * dh.
    LOCAL g1 IS gm + (ac * SIN(th) - (gg - vel * vel / rad) * COS(gd)) / vel * dh.
    SET hh TO hh + vel * SIN(gd) * dh.
    SET xx TO xx + vel * COS(gd) * dh * ASC_R / rad.
    SET vel TO v1.
    SET gm TO g1.
    SET ms TO ms - md * dh.
    SET th TO asc_rtls_th0 - asc_rtls_slew_at(sp, t + dh)[0].
    SET t TO t + dh.
  }
  RETURN LIST(vel - v0, gm * CONSTANT:RADTODEG - gam0, xx).
}

// PEG's PPD range-velocity line (the MECO line moved back by the predicted pitchdown, at V0 750 m/s, the range linear in
// V): LIST(a0, a1) for VDMAG = a0 + a1 RTHETA
FUNCTION asc_rtls_ppd_line {
  PARAMETER m0, f, md.
  LOCAL v0 IS 750.
  LOCAL am IS ASC_RTLS_A_MECO.
  LOCAL pr IS asc_rtls_ppd_predict(v0, ASC_RTLS_GAMD, ASC_RTLS_H_PPD, m0, f, md).
  LOCAL dt IS asc_rtls_dt_pitch().
  LOCAL gm IS (ASC_RTLS_GAMD + pr[1]) * CONSTANT:DEGTORAD.
  LOCAL k IS 1 + am[1] * dt.
  RETURN LIST((am[0] - am[1] * (pr[2] - v0 * dt) - am[2] * gm - pr[0]) / k, am[1] / k).
}

// The SSMEs' mass flow at full KSP throttle (t/s)
FUNCTION asc_rtls_mdot {
  PARAMETER engs.
  LOCAL m IS 0.
  FOR en IN engs { SET m TO m + en:MAXMASSFLOW. }
  RETURN m.
}

// The burnout mass MBO (t): the core at MECO (the OMS dump still to come taken off: ops1q's asc_oms_left, at most what
// the OMS tanks hold) + the ET reserve + the pitchdown's propellant (KMIN for dt_pitch + DT_PPD_MARGIN). LIST(MBO,
// m_ppd, md_kmin).
FUNCTION asc_rtls_mass {
  PARAMETER asc.
  LOCAL mcore IS SHIP:MASS - asc_burnable(asc["ssme"]) - asc_oms_left().
  LOCAL mk IS ASC_KMIN / 100 * ASC_PL_TO_KSP * asc_rtls_mdot(asc["ssme"]).
  LOCAL mp IS mk * (asc_rtls_dt_pitch() + ASC_RTLS_DT_PPD_MARGIN).
  RETURN LIST(mcore + ASC_ET_RESERVE_FRAC * asc["et_full"] + mp, mp, mk).
}

// ---- the thrust direction: the command, followed at a rate (the slew)
FUNCTION asc_rtls_cmd_dir {
  PARAMETER rl, p, t, hold.
  LOCAL c IS rl["cmd"].
  IF c:LENGTH = 0 { RETURN asc_peg_dir(p, t, hold). }
  IF c[0] = "peg" { RETURN (p["lamc"] + (t - p["tlamc"]) * p["lamdc"]):NORMALIZED. }
  RETURN c[1].
}

FUNCTION asc_rtls_dir {
  PARAMETER rl, p, t, hold.
  LOCAL s IS rl["slew"].
  IF s:LENGTH > 0 { IF t < s[4] - 1e-9 { RETURN asc_rot_toward(s[1], s[2], asc_rtls_slew_at(s, t)[0]). } }
  RETURN asc_rtls_cmd_dir(rl, p, t, hold).
}

// a slew of th deg from u0 to u1 from t: accelerating at ASC_RTLS_DTHETA_RATE to the rate w deg/s (less when th is too
// short to reach it), then braking at the same to stop on u1 (the profile DT_TURN counts): LIST(t0, u0, u1, the peak
// rate, t1, th)
FUNCTION asc_rtls_slew {
  PARAMETER t, u0, u1, th, w.
  LOCAL wp IS MIN(w, SQRT(th * ASC_RTLS_DTHETA_RATE)).
  RETURN LIST(t, u0, u1, wp, t + th / wp + wp / ASC_RTLS_DTHETA_RATE, th).
}

// the slew s at t: LIST(the angle turned deg, its rate deg/s, its acceleration deg/s2)
FUNCTION asc_rtls_slew_at {
  PARAMETER s, t.
  LOCAL a IS ASC_RTLS_DTHETA_RATE.
  LOCAL ta IS s[3] / a.
  LOCAL tt IS t - s[0].
  LOCAL tl IS s[4] - t.
  IF tt <= 0 { RETURN LIST(0, 0, 0). }
  IF tl <= 0 { RETURN LIST(s[5], 0, 0). }
  IF tt < ta { RETURN LIST(0.5 * a * tt * tt, a * tt, a). }
  IF tl < ta { RETURN LIST(s[5] - 0.5 * a * tl * tl, a * tl, -a). }
  RETURN LIST(0.5 * a * ta * ta + s[3] * (tt - ta), s[3], 0).
}

// a new command at t, slewed to at rate deg/s from the present direction (taken at once within SLEW_MIN). The same
// command re-sent while its slew runs (its kind, its target within SLEW_MIN of the slew's: the pitchdown's every
// DT_FCD; PEG's within RETGT_MAX: the pitcharound's every pass) moves the slew's target and keeps its start and peak
// rate: the slew goes on rather than starting again from rest
FUNCTION asc_rtls_set_cmd {
  PARAMETER rl, p, t, hold, cmd, rate.
  LOCAL un IS asc_rtls_dir(rl, p, t, hold).
  LOCAL s IS rl["slew"].
  LOCAL same IS FALSE.
  IF s:LENGTH > 0 AND rl["cmd"]:LENGTH > 0 { SET same TO t < s[4] - 1e-9 AND rl["cmd"][0] = cmd[0]. }
  SET rl["cmd"] TO cmd.
  LOCAL u1 IS asc_rtls_cmd_dir(rl, p, t, hold).
  LOCAL tol IS ASC_RTLS_SLEW_MIN.
  IF cmd[0] = "peg" { SET tol TO ASC_RTLS_RETGT_MAX. }
  IF same AND VANG(s[2], u1) <= tol {
    LOCAL ths IS MAX(VANG(s[1], u1), s[3] * s[3] / ASC_RTLS_DTHETA_RATE).
    SET s[2] TO u1.
    SET s[4] TO s[0] + ths / s[3] + s[3] / ASC_RTLS_DTHETA_RATE.
    SET s[5] TO ths.
    RETURN.
  }
  LOCAL th IS VANG(un, u1).
  IF th <= ASC_RTLS_SLEW_MIN { SET rl["slew"] TO LIST(). RETURN. }
  SET rl["slew"] TO asc_rtls_slew(t, un, u1, th, rate).
}

// the flyback's first thrust direction: THETA_FB from the downrange horizon, in the selection's vertical plane
FUNCTION asc_rtls_u_fb {
  PARAMETER rl.
  RETURN (COS(ASC_RTLS_THETA_FB) * rl["az"] + SIN(ASC_RTLS_THETA_FB) * rl["up0"]):NORMALIZED.
}

// ---- 4.6.2 RTLS INIT at MET t on the sample (rr, vv): the fuel dissipation attitude (4.6.6), the OMS dump (two
// levels by the speed), the mass target, the PPD line, PEG's SMODE 5 parameters; returns the state rl
FUNCTION asc_rtls_init {
  PARAMETER asc, t, rr, vv.
  LOCAL g IS asc["g"].
  LOCAL p IS g["peg"].
  LOCAL fr IS asc["fr"].
  LOCAL un IS asc_peg_dir(p, t, g["hold"]).
  LOCAL rl IS LEXICON("mode", "fd", "cmd", LIST(), "slew", LIST(), "w", fr["w"], "toff", ASC_RTLS_THRUST_OFF,
    "t_sel", t, "TP_hold", -1, "ppd_ready_t", -1, "tgo_co", -1, "gam_prev", -99, "next_fc", -1, "t_fc_prev", -1,
    "dv_fc", V(0, 0, 0), "MF", 0, "KDPY", 0, "THETA", 0, "VGO_CO", 0, "mf_t", -1, "mf_rt", 0, "tpa", -1,
    "pa_p", -1, "pa_t", -1, "pa_ok", -1, "tpa_on", FALSE).   // the settle test
  LOCAL n IS asc["ssme"]:LENGTH.
  SET rl["neng"] TO n.                    // not "N": one key with "n" below (kOS keys ignore case)
  SET rl["neng0"] TO n.                   // the SSMEs at the selection (asc_rtls_2eo rewrites "neng")
  SET asc_rtls_th0 TO ASC_RTLS_THETA_PPD0.
  IF n >= 3 {
    SET g["K_CMD"] TO MAX(ROUND(2 * ASC_KMAX / 3), ASC_KMIN).
    SET asc_rtls_th0 TO ASC_RTLS_THETA_PPD0_3ENG.   // the 3-engine PPD: the PPD line + MBO (fitted offline)
  } ELSE {
    SET g["K_CMD"] TO ASC_KMAX.
  }
  // PEG's K = the throttle flown (K_2ENG = KMAX; the 3-engine K 70 = round(2 KMAX / 3) at 104.5): a PEG planning at
  // another throttle (104.5 % against the abort's KMAX 109) did not converge
  LOCAL k IS g["K_CMD"].
  LOCAL vrel IS vv - asc_rtls_wxr(rl, rr).
  LOCAL uv IS rr:NORMALIZED.
  LOCAL hz IS (vrel - VDOT(vrel, uv) * uv):NORMALIZED.
  SET rl["az"] TO hz.
  SET rl["up0"] TO uv.
  SET rl["n"] TO VCRS(hz, uv):NORMALIZED.
  LOCAL vfd IS vrel:MAG.
  LOCAL hfd IS VDOT(uv, vrel).
  SET rl["V_FD"] TO vfd.
  LOCAL th IS ASC_RTLS_THETA_2 + ASC_RTLS_THETA_3 * vfd.
  IF vfd < ASC_RTLS_V_SWTCH { SET th TO ASC_RTLS_THETA_0 + ASC_RTLS_THETA_1 * vfd + ASC_RTLS_THETA_4 * hfd. }
  SET rl["THETA_C"] TO asc_mid(ASC_RTLS_THETA_MIN, th, ASC_RTLS_THETA_MAX).
  SET rl["u_fd"] TO (COS(rl["THETA_C"]) * hz + SIN(rl["THETA_C"]) * uv):NORMALIZED.
  // the OMS dump: all DUMP_T_LO t when the RTLS starts slow, else DUMP_T; from OMS_DELAY s on
  SET asc["oms_dump"] TO ASC_RTLS_DUMP_T.
  IF vfd < ASC_RTLS_V_DUMP_SW { SET asc["oms_dump"] TO ASC_RTLS_DUMP_T_LO. }
  IF asc["oms_dump"] > 0 AND asc["oms_st"] = 0 { SET asc["oms_t0"] TO t + ASC_TAL_OMS_DELAY. SET asc["oms_st"] TO 1. }
  LOCAL mt IS asc_rtls_mass(asc).
  LOCAL isp IS 0.
  IF n > 0 { SET isp TO asc["ssme"][0]:VISP. }
  LOCAL fk IS mt[2] * isp * CONSTANT:G0.
  LOCAL line IS asc_rtls_ppd_line(mt[0], fk, mt[2]).
  SET rl["line"] TO line.
  SET rl["F_kmin"] TO fk.
  LOCAL st IS ASC_RTLS_SITE.
  LOCAL rm IS ASC_R + st["alt"].
  LOCAL ef IS rm * V(COS(st["lat"]) * COS(st["lng"]), COS(st["lat"]) * SIN(st["lng"]), SIN(st["lat"])).
  SET rl["ef"] TO ef.
  SET p["RTLS"] TO LEXICON("ef", ef, "w", fr["w"], "A", line, "RTMAG", ef:MAG,
    "iy_save", VCRS(asc_rotz(ef, fr["w"] * t), rr):NORMALIZED, "K", k, "K_CMD", g["K_CMD"], "STHROT", FALSE,
    "MBO", mt[0], "KMIN", ASC_KMIN, "KMAX", ASC_KMAX, "DELK_MAX", ASC_RTLS_DELK_MAX, "KMISS", ASC_RTLS_KMISS,
    "RNG_TURN_PRED", ASC_RTLS_RNG_TURN_PRED, "MDOT", g["K_CMD"] / 100 * ASC_PL_TO_KSP * asc_rtls_mdot(asc["ssme"]),
    "RTHETA", 0, "close", FALSE, "VGOD", 0, "ERR", 0).
  SET p["TAL"] TO LEXICON().
  SET p["RDMAG"] TO ASC_R + ASC_RTLS_H_PPD.
  SET p["GAMD"] TO ASC_RTLS_GAMD.
  SET p["MASS_MIN"] TO 0.
  SET p["S_INIT"] TO TRUE.
  SET p["S_GDRDY"] TO FALSE.
  SET p["SCONV"] TO FALSE.
  SET g["S_MECO"] TO FALSE.
  SET rl["DT_TURN"] TO VANG(rl["u_fd"], asc_rtls_u_fb(rl)) / ASC_RTLS_DTHETA_LIM + ASC_RTLS_DTHETA_LIM / ASC_RTLS_DTHETA_RATE.
  SET rl["cmd"] TO LIST("fix", rl["u_fd"]).
  SET rl["sep_hold"] TO FALSE.
  LOCAL th0 IS VANG(un, rl["u_fd"]).
  IF t - g["t_sep"] < ASC_DTGD {
    // selected in stage 1: the SRB sep's hold first, as the nominal's and a TAL's (asc_peg_dir: the sep's direction
    // until PEG's first good pass), then the slew to the fuel dissipation attitude (asc_rtls_cycle)
    SET rl["cmd"] TO LIST("fix", un).
    SET rl["sep_hold"] TO TRUE.
  } ELSE IF th0 > ASC_RTLS_SLEW_MIN {
    SET rl["slew"] TO asc_rtls_slew(t, un, rl["u_fd"], th0, ASC_RTLS_DTHETA_LIM).
  }
  SET g["k_pass"] TO CEILING((t - g["t_sep"]) / ASC_DTGD - 1e-9).
  SET g["next_pass"] TO g["t_sep"] + g["k_pass"] * ASC_DTGD.
  RETURN rl.
}

// Is an RTLS task due at MET t? (a pass in fd / turn / fb, the pitchdown's start, a cutoff cycle in the pitchdown)
FUNCTION asc_rtls_due {
  PARAMETER rl, g, t.
  LOCAL md IS rl["mode"].
  IF md = "fc" { RETURN t >= rl["TP_hold"] - 0.08 - 1e-9. }
  IF md = "ppd" { RETURN g["T_MECO"] < 0 AND t >= rl["next_fc"] - 1e-9. }
  RETURN t >= g["next_pass"] - 1e-9.
}

// The due tasks on a sample at MET t (rr, vv; M t, VEX m/s, FMAX kN as asc_s2_tasks). Returns TRUE after a PEG pass.
FUNCTION asc_rtls_tasks {
  PARAMETER asc, rl, t, rr, vv, ms, vex, fmax.
  LOCAL g IS asc["g"].
  asc_s2_sense(g, t, rr, vv).
  LOCAL md IS rl["mode"].
  IF md = "fc" { asc_rtls_ppd_start(asc, rl, t, rr, vv). RETURN FALSE. }
  IF md = "ppd" {
    asc_rtls_co(asc, rl, t, rr, vv, FALSE).
    SET rl["next_fc"] TO t + ASC_RTLS_DT_FCD.
    RETURN FALSE.
  }
  IF md = "m5" {
    asc_rtls_m5(asc, rl, t, rr, vv, ms, fmax).
    SET g["k_pass"] TO g["k_pass"] + 1.
    SET g["next_pass"] TO g["t_sep"] + g["k_pass"] * ASC_DTGD.
    RETURN FALSE.
  }
  asc_rtls_cycle(asc, rl, t, rr, vv, ms, vex, fmax).
  SET g["k_pass"] TO g["k_pass"] + 1.
  SET g["next_pass"] TO g["t_sep"] + g["k_pass"] * ASC_DTGD.
  RETURN TRUE.
}

// A pass (4.6.3 / 4.6.4): G-LIM, the mass target, PEG (in fd and turn ahead by DT_TURN on the predicted position, its
// thrust acceleration at its throttle K), then the phase logic: the turnaround when the fuel is dissipated (MF <= MBO)
// and the thrust turns the right way, the pitcharound's end, the flyback's throttle, the fine countdown at TGO_PPD.
FUNCTION asc_rtls_cycle {
  PARAMETER asc, rl, t, rr, vv, ms, vex, fmax.
  IF asc_gdl() { RETURN. }                 // SW 02 ASCENT holds the RTLS pass too (lib_ascent_s2's asc_gdl)
  LOCAL g IS asc["g"].
  LOCAL p IS g["peg"].
  LOCAL pr IS p["RTLS"].
  LOCAL dvs IS g["dv"] - g["dv_pass"].
  LOCAL dtgd IS 0.
  IF g["t_pass_prev"] >= 0 { SET dtgd TO t - g["t_pass_prev"]. }
  SET g["dv_pass"] TO g["dv"].
  SET g["t_pass_prev"] TO t.
  LOCAL atave IS 0.
  IF dtgd > 0 { SET atave TO dvs:MAG / dtgd. }
  asc_glim(g, t, atave, dtgd).
  SET pr["MBO"] TO asc_rtls_mass(asc)[0].
  LOCAL atr IS ASC_FT_FACTOR * (g["K_CMD"] / 100 * ASC_PL_TO_KSP * fmax) / ms.
  SET pr["K_CMD"] TO g["K_CMD"].
  SET pr["MDOT"] TO g["K_CMD"] / 100 * ASC_PL_TO_KSP * asc_rtls_mdot(asc["ssme"]).
  LOCAL md IS rl["mode"].
  IF md = "turn" { SET rl["DT_TURN"] TO MAX(0, rl["DT_TURN"] - ASC_DTGD). }
  LOCAL dt IS 0.
  IF md = "fd" OR md = "turn" {
    SET dt TO rl["DT_TURN"].
    asc_peg_cycle(p, t + dt, rr + dt * vv, vv, dvs, ms, vex, vex * atr / (vex - dt * atr) * pr["K"] / g["K_CMD"]).
  } ELSE {
    asc_peg_cycle(p, t, rr, vv, dvs, ms, vex, atr * pr["K"] / g["K_CMD"]).
  }
  SET g["dvs_last"] TO dvs. SET g["M_last"] TO ms. SET g["VEX_last"] TO vex. SET g["ATR_last"] TO atr.
  IF pr["close"] { SET p["S_INIT"] TO TRUE. SET p["SCONV"] TO FALSE. }        // too close for a solution: reinit
  IF md = "fd" AND rl["sep_hold"] AND (p["S_GDRDY"] OR t - g["t_sep"] >= ASC_RTLS_SEP_HOLD_MAX) {
    SET rl["sep_hold"] TO FALSE.            // the sep's hold over: on to the fuel dissipation attitude
    asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("fix", rl["u_fd"]), ASC_RTLS_DTHETA_LIM).
  }
  IF md = "fd" {
    IF p["SCONV"] AND NOT pr["close"] AND p:HASKEY("lam") {
      LOCAL mf IS ms * CONSTANT:E ^ (-(p["vgo"]:MAG + atr * dt) / vex) - ASC_RTLS_M_BIAS.
      LOCAL uf IS (p["lam"] + (t + dt - p["TLAM"]) * p["lamd"]):NORMALIZED.
      LOCAL ud IS asc_rtls_dir(rl, p, t, g["hold"]).
      IF dvs:MAG > 0 { SET ud TO dvs:NORMALIZED. }
      LOCAL theta IS VANG(ud, uf).
      SET rl["DT_TURN"] TO theta / ASC_RTLS_DTHETA_LIM + ASC_RTLS_DTHETA_LIM / ASC_RTLS_DTHETA_RATE.
      LOCAL lamc IS asc_rtls_cmd_dir(rl, p, t, g["hold"]).
      LOCAL iyt IS VCRS(p["lam"], p["ix"]):NORMALIZED.
      LOCAL kdelta IS MAX(0, 1 - (pr["K"] / g["K_CMD"]) ^ 2).
      LOCAL ufz IS VCRS(lamc, iyt):NORMALIZED.
      LOCAL sg IS 1.
      IF VDOT(uf, VCRS(p["ix"], iyt)) < 0 { SET sg TO -1. }
      LOCAL kdpy IS -1.
      IF VDOT(uf, ufz) > SQRT(kdelta) OR sg * theta > 90 { SET kdpy TO 1. }
      // the time to PPA for the page (in place of TGO during fuel dissipation), (MF - MBO) over the rate MF falls (pass
      // to pass, filtered; the first pass: the mass flow's share)
      LOCAL rt IS pr["MDOT"] * mf / ms.
      IF rl["mf_t"] >= 0 AND t > rl["mf_t"] + 0.1 { SET rt TO (rl["MF"] - mf) / (t - rl["mf_t"]). }
      IF rl["mf_rt"] <= 0 { SET rl["mf_rt"] TO MAX(0, rt). }
      ELSE { SET rl["mf_rt"] TO rl["mf_rt"] + ASC_RTLS_PPA_FILT * (rt - rl["mf_rt"]). }
      SET rl["mf_t"] TO t.
      SET rl["tpa"] TO -1.
      IF rl["mf_rt"] > 0 { SET rl["tpa"] TO MAX(0, (mf - pr["MBO"]) / rl["mf_rt"]). }
      asc_rtls_ppa_settle(rl, t).   // shown once it settles
      SET rl["MF"] TO mf. SET rl["KDPY"] TO kdpy. SET rl["THETA"] TO theta.
      IF kdpy > 0 AND mf <= pr["MBO"] {
        SET rl["mode"] TO "turn".
        SET pr["STHROT"] TO TRUE.
        // the pitcharound: onto PEG's command when PEG is ready (one slew, no restart), else the first flyback
        // direction until it is
        IF p["S_GDRDY"] { asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("peg"), ASC_RTLS_DTHETA_LIM). }
        ELSE { asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("fix", asc_rtls_u_fb(rl)), ASC_RTLS_DTHETA_LIM). }
      }
    }
  } ELSE IF md = "turn" {
    LOCAL onpeg IS FALSE.
    IF rl["cmd"]:LENGTH > 0 { IF rl["cmd"][0] = "peg" { SET onpeg TO TRUE. } }
    IF p["SCONV"] AND p["S_GDRDY"] {   // every pass: the slew's target follows PEG's command (asc_rtls_set_cmd)
      asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("peg"), ASC_RTLS_DTHETA_LIM).
      SET onpeg TO TRUE.
    }
    IF rl["DT_TURN"] <= 0 {
      SET rl["mode"] TO "fb".
      IF NOT onpeg { asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("peg"), ASC_RTLS_DTHETA_LIM). }
    }
  } ELSE IF md = "fb" {
    LOCAL onpeg IS FALSE.
    IF rl["cmd"]:LENGTH > 0 { IF rl["cmd"][0] = "peg" { SET onpeg TO TRUE. } }
    IF NOT onpeg OR p["S_GDRDY"] { asc_rtls_set_cmd(rl, p, t, g["hold"], LIST("peg"), ASC_RTLS_DTHETA_LIM). }
    // after an SSME lost since the RTLS began, K_CMD follows PEG's (rate-limited) K converged or not: PEG may stay
    // unconverged for passes (measured: 20, K_CMD held at 71 % for 42 s while PEG's K rose to 104.6 and the sink grew
    // -316 -> -382 m/s). A deviation (the offline sim gates on SCONV).
    LOCAL keo IS asc["ssme"]:LENGTH < rl["neng0"].
    IF (p["SCONV"] OR keo) AND ABS(g["K_CMD"] - pr["K"]) > ASC_RTLS_DK_ROUND AND NOT g["glim_on"] {
      SET g["K_CMD"] TO asc_mid(ASC_KMIN, ROUND(pr["K"]), ASC_KMAX).
    }
    IF p["TGO"] <= ASC_RTLS_TGO_PPD AND p["S_GDRDY"] {
      SET rl["mode"] TO "fc".
      SET g["S_MECO"] TO TRUE.
      SET rl["TP_hold"] TO p["TP"].
    }
  }
}

// the pitchdown's thrust direction: the nose at ALPHA_PPD from V_rel in its vertical plane (the thrust toff deg below)
FUNCTION asc_rtls_ppd_target {
  PARAMETER rl, rr, vv.
  LOCAL vh IS (vv - asc_rtls_wxr(rl, rr)):NORMALIZED.
  LOCAL uv IS rr:NORMALIZED.
  LOCAL nu IS (uv - VDOT(uv, vh) * vh):NORMALIZED.
  LOCAL d IS ASC_RTLS_ALPHA_PPD - rl["toff"].
  RETURN (COS(d) * vh + SIN(d) * nu):NORMALIZED.
}

// 4.6.5: the pitchdown at the fine countdown's TP: KMIN (with two SSMEs or three), the slew to the ET separation
// attitude at PPD_RATE, MECO not before its end + T_SETTLE; the cutoff cycle from here
FUNCTION asc_rtls_ppd_start {
  PARAMETER asc, rl, t, rr, vv.
  LOCAL g IS asc["g"].
  SET rl["mode"] TO "ppd".
  SET g["K_CMD"] TO ASC_KMAX.
  IF asc["ssme"]:LENGTH >= 2 { SET g["K_CMD"] TO ASC_KMIN. }
  asc_rtls_set_cmd(rl, g["peg"], t, g["hold"], LIST("ppd", asc_rtls_ppd_target(rl, rr, vv)), ASC_RTLS_PPD_RATE).
  LOCAL te IS t.
  IF rl["slew"]:LENGTH > 0 { SET te TO rl["slew"][4]. }
  SET rl["ppd_ready_t"] TO te + ASC_RTLS_T_SETTLE.
  SET rl["dv_fc"] TO g["dv"].
  SET rl["t_fc_prev"] TO t.
  SET rl["next_fc"] TO t + ASC_RTLS_DT_FCD.
  asc_rtls_co(asc, rl, t, rr, vv, TRUE).
}

// The MECO line at MET t on (rr, vv), the site taken tg s ahead: LIST(VR m/s, gam rad, RTHETA m, V_line m/s), V_line =
// A5 + A6 RTHETA - A7 gam (4.8.5; RTHETA = the site's distance from the point over it at its radius)
FUNCTION asc_rtls_vline {
  PARAMETER rl, t, rr, vv, tg.
  LOCAL vrel IS vv - asc_rtls_wxr(rl, rr).
  LOCAL vr IS vrel:MAG.
  LOCAL gam IS ARCSIN(MAX(-1, MIN(1, VDOT(rr:NORMALIZED, vrel) / vr))) * CONSTANT:DEGTORAD.
  LOCAL rt IS asc_rotz(rl["ef"], rl["w"] * (t + tg)).
  LOCAL rth IS (rt:MAG * rr:NORMALIZED - rt):MAG.
  LOCAL am IS ASC_RTLS_A_MECO.
  RETURN LIST(vr, gam, rth, am[0] + am[1] * rth - am[2] * gam).
}

// 4.8.5 in MM 601 (every DT_FCD s): the speed to go to the MECO line (V = A5 + A6 RTHETA - A7 gam, the range to the site
// at MECO), its rate, TGO; T_MECO below MECO_INIT_TGO (not before ppd_ready_t); the pitchdown's attitude until then
FUNCTION asc_rtls_co {
  PARAMETER asc, rl, t, rr, vv, first.
  LOCAL g IS asc["g"].
  LOCAL vl IS asc_rtls_vline(rl, t, rr, vv, MAX(0, rl["tgo_co"])).
  LOCAL vrel IS vv - asc_rtls_wxr(rl, rr).
  LOCAL vr IS vl[0].
  LOCAL gam IS vl[1].
  LOCAL have IS FALSE.
  LOCAL atf IS 0.
  LOCAL gd IS 0.
  IF NOT first {
    LOCAL dvs IS g["dv"] - rl["dv_fc"].
    LOCAL dtg IS t - rl["t_fc_prev"].
    SET rl["dv_fc"] TO g["dv"].
    SET rl["t_fc_prev"] TO t.
    IF dtg > 0 {
      SET atf TO VDOT(vrel, dvs) / (vr * dtg).
      SET have TO TRUE.
      IF rl["gam_prev"] > -90 { SET gd TO MIN(0, (gam - rl["gam_prev"]) / dtg). }
    }
  }
  SET rl["gam_prev"] TO gam.
  LOCAL am IS ASC_RTLS_A_MECO.
  LOCAL vgo IS vl[3] - vr.
  SET rl["VGO_CO"] TO vgo.
  SET rl["RTHETA_CO"] TO vl[2].
  IF have {
    LOCAL vgd IS atf + am[1] * vr + am[2] * gd.
    IF vgd >= ASC_FT {
      SET rl["tgo_co"] TO vgo / vgd.
      IF rl["tgo_co"] < ASC_RTLS_MECO_INIT_TGO { SET g["T_MECO"] TO MAX(t + MAX(0, rl["tgo_co"]), rl["ppd_ready_t"]). }
    }
  }
  IF g["T_MECO"] < 0 {
    asc_rtls_set_cmd(rl, g["peg"], t, g["hold"], LIST("ppd", asc_rtls_ppd_target(rl, rr, vv)), ASC_RTLS_PPD_RATE).
  }
}

// FSSR 4.9.7 MODE 5 (RED), the single-engine RTLS completion, every pass after a second SSME out on the flyback
// (ops1q's asc_rtls_2eo): wings level, in the plane toward the site; TGO = MIN(the MECO line's (heading home only: VGO
// over the thrust along V_rel + A6 VR), the ET over its low level at the flow); the thrust's vertical share MIN(AX / AT,
// SIN(ASC_RTLS_M5_TH)), AX = g - VH^2 / r + (ASC_RTLS_M5_HDT - H-dot) / MAX(TGO, 10 s), the rest toward the site,
// slewed at ASC_RTLS_M5_RATE; the pitchdown (asc_rtls_ppd_start) when TGO is within its planned length and a pass;
// MECO by the line (asc_rtls_co) or at the ET's low level (ops1q's "res"). A deviation from the FSSR: the I-loads, no
// K_CONT_THROT, no yaw cant.
FUNCTION asc_rtls_m5 {
  PARAMETER asc, rl, t, rr, vv, ms, fmax.
  LOCAL g IS asc["g"].
  LOCAL vrel IS vv - asc_rtls_wxr(rl, rr).
  LOCAL uv IS rr:NORMALIZED.
  LOCAL hd IS VDOT(uv, vrel).
  LOCAL rt IS asc_rotz(rl["ef"], rl["w"] * t).
  LOCAL toh IS VXCL(uv, rt - rr):NORMALIZED.
  LOCAL atr IS ASC_FT_FACTOR * (g["K_CMD"] / 100 * ASC_PL_TO_KSP * fmax) / ms.
  LOCAL mf IS g["K_CMD"] / 100 * ASC_PL_TO_KSP * asc_rtls_mdot(asc["ssme"]).
  LOCAL tge IS MAX(0, asc_burnable(asc["ssme"]) - ASC_ET_RESERVE_FRAC * asc["et_full"]) / MAX(mf, 1e-6).
  LOCAL tgl IS 1e9.
  IF VDOT(vrel, toh) > 0 {
    LOCAL vl IS asc_rtls_vline(rl, t, rr, vv, 0).
    LOCAL vgo IS vl[3] - vl[0].
    LOCAL vgd IS atr * VDOT(asc_rtls_dir(rl, g["peg"], t, g["hold"]), vrel:NORMALIZED) + ASC_RTLS_A_MECO[1] * vl[0].
    IF vgo <= 0 { SET tgl TO 0. }
    ELSE IF vgd > 0.3 { SET tgl TO vgo / vgd. }
  }
  LOCAL tgo IS MIN(tgl, tge).
  SET rl["m5_tgo"] TO tgo.
  LOCAL vhi IS VXCL(uv, vv):MAG.
  IF hd < 0 {                              // the emergency sep when one SSME cannot stop the sink in time
    LOCAL es IS asc_rtls_es_test(rr, vrel, hd, atr, vhi).
    IF es[0] { asc_rtls_esep(asc, rl, t, hd, es[1], es[2]). RETURN. }
  }
  IF asc["log"] <> "" { LOG "#m5," + t + "," + hd + "," + VDOT(vrel, toh) + "," + tgl + "," + tge + "," + atr TO asc["log"]. }
  IF tgo <= asc_rtls_dt_pitch() + ASC_DTGD {
    SET rl["m5_by"] TO CHOOSE "LINE" IF tgl <= tge ELSE "LOW LEVEL".
    asc_rtls_ppd_start(asc, rl, t, rr, vv).
  } ELSE {
    LOCAL ax IS ASC_MU / VDOT(rr, rr) - vhi * vhi / rr:MAG + (ASC_RTLS_M5_HDT - hd) / MAX(tgo, 10).
    LOCAL s5 IS SIN(ASC_RTLS_M5_TH).
    LOCAL ix IS MAX(-s5, MIN(s5, ax / MAX(atr, 1e-6))).
    LOCAL u5 IS (ix * uv + SQRT(1 - ix * ix) * toh):NORMALIZED.
    asc_rtls_set_cmd(rl, g["peg"], t, g["hold"], LIST("fix", u5), ASC_RTLS_M5_RATE).
  }
}

// THE EMERGENCY SEP in mode 5: with high sink rates one SSME cannot stop the sink in time (measured: SSME L out at
// 290 s, C at 333 s on the flyback at H-dot -338 m/s, 58 km: mode 5 put the thrust 70 deg up, a_up ~ -0.9 m/s2, the
// mated stack fell tail first (alpha ~150 deg) and was lost near 31 km, q ~8 psf). SCOM 6.7's fast seps: high sink rates
// leave no time for the PPD and a mated coast; the sep at any attitude while q is low (attitude independent; the
// high-alpha seps before 2 psf; the rate fast sep starts at ~0.7 psf). Every mode-5 pass while sinking: LIST(due, q
// predicted, the altitude where the sink stops): due when q ASC_RTLS_ES_DT s ahead (the air's pressure ratio, the speed
// grown by a free fall) reaches ASC_RTLS_ES_Q and the sink, with the thrust ASC_RTLS_M5_TH up at today's acceleration,
// does not stop above ASC_RTLS_ES_H. On that flight it fires at 358.5 s (49.3 km, q 0.47 psf, H-dot -333); on 46 mode-5
// flights offline (13 land) never, nor with a 50 km floor. A deviation (the FSSR's early-sep test predicts q at
// REG1_MNVR_TIME against QBAR_REG1; its I-loads are not published).
FUNCTION asc_rtls_es_test {
  PARAMETER rr, vrel, hd, atr, vhi.
  LOCAL h IS SHIP:ALTITUDE.
  LOCAL p1 IS BODY:ATM:ALTITUDEPRESSURE(h).
  IF p1 <= 0 { RETURN LIST(FALSE, 0, h). }
  LOCAL h2 IS MAX(0, h + hd * ASC_RTLS_ES_DT).
  LOCAL vr2 IS MAX(VDOT(vrel, vrel), 1).
  LOCAL qp IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000 * BODY:ATM:ALTITUDEPRESSURE(h2) / p1
    * (vr2 + 2 * CONSTANT:G0 * (h - h2)) / vr2.
  LOCAL aup IS atr * SIN(ASC_RTLS_M5_TH) - (ASC_MU / VDOT(rr, rr) - vhi * vhi / rr:MAG).
  LOCAL harr IS -1e9.
  IF aup > 0.1 { SET harr TO h - hd * hd / (2 * aup). }
  RETURN LIST(qp >= ASC_RTLS_ES_Q AND harr < ASC_RTLS_ES_H, qp, harr).
}

// the emergency sep: MECO now (ops1q's asc_stage2 sees why "esep"), the ET sep ASC_RTLS_ES_TSEP s later
// (ops1q's asc_etsep), the attitude held, then the RTLS hand-off as before (OPS 6's reach test: the GRTLS or the bailout)
FUNCTION asc_rtls_esep {
  PARAMETER asc, rl, t, hd, qp, harr.
  LOCAL qn IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000.
  LOCAL al IS VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE).
  SET rl["esep"] TO t.
  SET asc["why"] TO "esep".
  IF asc["log"] <> "" { LOG "#esep," + t + "," + SHIP:ALTITUDE + "," + hd + "," + qn + "," + qp + "," + harr + "," + al TO asc["log"]. }
  asc_event(asc, "RTLS 2EO " + asc_col_word("RED") + ": EMERGENCY SEP  Q " + ROUND(qn / 47.880259, 1) + " PSF  ALPHA "
    + ROUND(al)).
}

// the PEG log's RTLS line after a pass / a cutoff cycle
FUNCTION asc_rtls_line {
  PARAMETER asc, rl, t.
  LOCAL g IS asc["g"].
  LOCAL pr IS g["peg"]["RTLS"].
  RETURN "#rtls," + t + "," + rl["mode"] + "," + g["K_CMD"] + "," + pr["K"] + "," + pr["RTHETA"] + ","
    + g["peg"]["VDMAG"] + "," + pr["VGOD"] + "," + pr["ERR"] + "," + pr["MBO"] + "," + rl["DT_TURN"] + "," + rl["MF"]
    + "," + rl["KDPY"] + "," + rl["VGO_CO"] + "," + rl["tgo_co"] + "," + g["T_MECO"].
}
