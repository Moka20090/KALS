// lib_ascent_ard.ks -- THE ONBOARD ARD (the abort region determinator): ALL of the boundaries calculated from the
// current state, so after a 1EO the 2EO TAL / ATO / PRESS boundaries stay accurate (and the 1EO state locks to the
// abort selected). A 2EO's MECO may be above 67 km, never below it.
// THE FAST-TIME SIM (the offline sim's FTS mirrors it, validated against full flights): from
// a state, e SSMEs at a throttle K, the mode's own PEG (PRESS: the nominal target; ATO: ASC_ATO_VDMAG; TAL: PEGTAL to
// a site) re-solved every ASC_ARD_DT s from the flown steering, FSSR 4.3.4's droop (subtasks 1-3, lib_ascent_cnt's)
// with one SSME, the OMS dump on its schedule, RK4 with J2 (asc_grav) and drag (the air table below), to the cutoff
// ("cut"), the ET's reserve ("res"), a fall below ASC_ARD_H_LOW ("low"), ASC_ARD_T_MAX s ("time") or a stop time
// ("stop"). Vessel-free: ops1q hands it the state. ONE UNIT of work = one PEG cycle (the start) or one step and its
// pass, so the work spreads over ops1q's main-loop passes. The verdict = ard_margin: >= 0 = the abort
// works (TAL / ATO: the trough and MECO at or above ASC_DRP_MIN_ALT, 67 km).
@LAZYGLOBAL OFF.

GLOBAL ASC_ARD_ON IS TRUE.
// THE C# COPROCESSOR. With ASC_ARD_CS on and the KAL/S addon installed (GameData/KALS_Coproc: ADDONS:KALS), a level's or
// the rank's abort flight (ard_lv_job) is flown by the addon on a worker thread, off KSP's main thread: its first unit
// starts it (ADDONS:KALS:FTS with ard_new's lexicon, the job's own step and floor added), the next units only ask :DONE,
// and ard_margin reads the addon's margin. The port (coproc/Fts.cs) matches this file's flights to ~1e-11 in kOS's VM.
// Kept in kOS: the path (its trace), the bracket's states, the PEG-estimate starts, NEG RTN, E TAL.
// FALSE, or no addon: this file's flights. An addon failure (a handle back with WHY "error") turns it off for the rest
// of the flight and that flight is flown here, so a search never loses a result (ASC_ARD_CS_ERR says why). ON by default.
GLOBAL ASC_ARD_CS IS TRUE.
GLOBAL ASC_ARD_CS_ERR IS "".
GLOBAL ASC_ARD_DT IS 8.0.                 // s: the step = the hypothetical PEG's pass interval (validated offline at 8)
GLOBAL ASC_ARD_H_LOW IS 40000.0.          // m: descending below it the flight is lost
GLOBAL ASC_ARD_T_MAX IS 1500.0.           // s: the longest fast-time flight
GLOBAL ASC_ARD_TAL_VGO_TOL IS 150.0.      // m/s: a TAL at the ET's reserve this short still reaches (PROVISIONAL)
GLOBAL ASC_ARD_EU IS 2.718281828459045.   // e (no CONSTANT here: the offline VM's)
GLOBAL ASC_ARD_FOMS IS ASC_OMS_F.         // kN along the thrust line (the OMS's efficiency taken as 1)
GLOBAL ASC_ARD_MDO IS ASC_OMS_F / (ASC_OMS_ISP * 9.80665).   // t/s: the OMS dump's flow
// the air (ascent_sim.air: solq_atm at the SLF, the daily and annual mean) every 1 km from ASC_ARD_AIR_H0: ln(rho kg/m3)
// and the speed of sound (m/s), log-linear / linear between (vs ascent_sim.air: rho within 0.15 % to 75 km, the
// speed of sound within 0.18 m/s, the drag within 0.0047 m/s2 at 2500 m/s on 150 t to 80 km); no air from ASC_ARD_ATM_TOP
GLOBAL ASC_ARD_AIR_H0 IS 20000.0.
GLOBAL ASC_ARD_ATM_TOP IS 80000.0.
GLOBAL ASC_ARD_LNRHO IS LIST(-3.0617833, -3.25845993, -3.4522202, -3.64640435, -3.83987853, -4.03002068, -4.21909676, -4.40571539, -4.58872986, -4.76979522, -4.95208645, -5.13103235, -5.30694733, -5.48277876, -5.65635704, -5.8261949, -5.99405974, -6.15847962, -6.31850252, -6.47607916, -6.63354896, -6.78254358, -6.92942103, -7.07599529, -7.22367016, -7.36386044, -7.5039132, -7.64573062, -7.79260264, -7.94040305, -8.08846133, -8.2400073, -8.3956377, -8.55047549, -8.70721347, -8.87052216, -9.03418089, -9.19853953, -9.36957689, -9.54290416, -9.71591959, -9.89487759, -10.0760578, -10.2562839, -10.4425315, -10.6308187, -10.8180029, -11.0113995, -11.2043543, -11.3964785, -11.5971054, -11.7972681, -11.9977016, -12.2056122, -12.4097619, -12.6163847, -12.8296187, -13.0380554, -13.2811271, -14.2205341, -39.2441016).
GLOBAL ASC_ARD_AS IS LIST(296.297648, 297.889623, 299.473134, 301.176052, 303.105152, 305.022053, 306.903869, 308.623118, 310.332843, 312.0332, 313.955925, 315.925549, 317.88297, 319.83924, 321.805973, 323.760758, 325.703812, 327.02455, 328.075161, 329.122419, 330.166354, 329.64659, 329.006256, 328.364673, 327.506597, 325.172287, 322.821098, 320.452659, 318.12871, 315.867948, 313.590889, 311.297172, 309.055171, 306.802807, 304.533785, 302.398062, 300.367513, 298.323144, 296.407556, 294.762258, 293.107725, 291.498506, 290.057397, 288.609091, 287.207402, 285.972258, 284.731756, 283.478439, 282.204216, 280.924214, 279.872318, 279.061661, 278.248643, 277.58966, 276.992193, 276.393437, 276.248917, 276.11409, 276.03161, 276.093725, 276.155826).
// ascent_sim CD_M: (Mach, CD) pairs on A_REF[2]
GLOBAL ASC_ARD_CDM IS LIST(0, 0.35, 0.6, 0.36, 0.8, 0.4, 0.95, 0.55, 1.1, 0.72, 1.25, 0.75, 1.5, 0.68, 2, 0.56, 3, 0.43, 4, 0.37, 6, 0.33, 10, 0.3).
GLOBAL ASC_ARD_AREF IS 42.0.   // m2: the stack in stage 2 (ascent_sim A_REF[2])
GLOBAL ASC_ARD_OMS_DV IS 550.429671.   // m/s: the OMS on board for the ATO (ato.OMS_DV: 4.2 t, Isp 316, 25.808 t)
GLOBAL ASC_ARD_W IS 0.00014584230746387985.   // rad/s: the planet's rotation (2 pi / 43082.0481137527 s); ops1q
//                                                 sets it from asc["fr"]["w"]

// a fast-time flight. a = LEXICON("md" "PRESS" / "ATO" / "TAL", "tl" the TAL site's asc_tal_lex (TAL), "e" SSMEs,
// "K" PL %, "t", "r", "v" (the PEG frame), "et" t of ET propellant, "mc" t: the mass = mc - om + et (om the OMS used
// from here, 0 at the start), "res" t: the ET's reserve, "iy", "steer" LIST(lamc, lamdc, tlamc), "o" the OMS dump
// LIST(on, off) or LIST(), "m" LEXICON("f1" kN per SSME at full KSP throttle, "vex" m/s), "tr" trace, "ts" the stop
// time (-1: none))
FUNCTION ard_new {
  PARAMETER a.
  LOCAL vd IS ASC_VDMAG.
  IF a["md"] = "ATO" { SET vd TO ASC_ATO_VDMAG. }
  LOCAL p IS asc_peg_new(ASC_R + ASC_MECO_H, ASC_GAMD, vd, a["iy"], a["mc"], ASC_MU).
  IF a["md"] = "TAL" { asc_peg_tal(p, a["tl"]). }
  SET p["lamc"] TO a["steer"][0].
  SET p["lamdc"] TO a["steer"][1].
  SET p["tlamc"] TO a["steer"][2].
  SET p["S_GDRDY"] TO TRUE.
  LOCAL D IS LEXICON("T1NEW", 0, "S_MIN_ALT", FALSE, "S_DRP_EARLY", FALSE, "S_CDROOP", FALSE,
    "THR_ATT", ASC_DRP_THRESH_ATT, "cmd", V(0, 0, 0), "cmd_on", FALSE, "t_on", -1, "t_prev", -1).
  // NB kOS lexicon keys ignore case: "K" (the throttle) and a "k" would be one key
  LOCAL j IS LEXICON("md", a["md"], "e", a["e"], "K", a["K"], "mc", a["mc"], "res", a["res"], "m", a["m"],
    "tr", a["tr"], "ts", a["ts"], "o", a["o"]:COPY, "t", a["t"], "t0", a["t"], "r", a["r"], "v", a["v"],
    "et", a["et"], "om", 0, "p", p, "D", D, "kc", 0, "st", 0, "keep", LIST(), "down", FALSE, "hmin", 1E12,
    "why", "", "pts", LIST(), "n", 0).
  // no thrust (no SSME, no throttle, no engine data): no flight (0 / 0 would make PEG's TGO NaN and asc_coast's
  // loop endless)
  IF a["e"] < 1 OR a["K"] <= 0 OR a["m"]["f1"] <= 0 OR a["m"]["vex"] <= 0 { SET j["st"] TO 2. SET j["why"] TO "bad". }
  RETURN j.
}

// the OMS dump on at t
FUNCTION ard_on {
  PARAMETER j, t.
  LOCAL o IS j["o"].
  IF o:LENGTH = 0 { RETURN FALSE. }
  RETURN o[0] - 0.000000001 <= t AND t < o[1] - 0.000000001.
}

// LIST(F kN the SSMEs', md t/s, Ft kN, mdt t/s with the OMS while on) at the mass M: e SSMEs at K, G-limited at AL
FUNCTION ard_thr {
  PARAMETER j, M, oon.
  LOCAL F IS j["K"] / 100 * ASC_PL_TO_KSP * j["m"]["f1"] * j["e"].
  IF F / M > ASC_AL { SET F TO ASC_AL * M. }
  LOCAL md IS F / j["m"]["vex"].
  IF oon { RETURN LIST(F, md, F + ASC_ARD_FOMS, md + ASC_ARD_MDO). }
  RETURN LIST(F, md, F, md).
}

// Cd at a Mach number (ascent_sim's CD_M, clamped at its ends)
FUNCTION ard_cd {
  PARAMETER mach.
  LOCAL c IS ASC_ARD_CDM.
  IF mach <= c[0] { RETURN c[1]. }
  FROM { LOCAL i IS 2. } UNTIL i >= c:LENGTH STEP { SET i TO i + 2. } DO {
    IF mach <= c[i] { RETURN c[i - 1] + (c[i + 1] - c[i - 1]) * (mach - c[i - 2]) / (c[i] - c[i - 2]). }
  }
  RETURN c[c:LENGTH - 1].
}

// the stage-2 drag, m/s2: q A_REF Cd(Mach) / M on the wind of the turning planet (about the frame's z)
FUNCTION ard_drag {
  PARAMETER rr, vv, M.
  LOCAL h IS rr:MAG - ASC_R.
  IF h >= ASC_ARD_ATM_TOP { RETURN V(0, 0, 0). }
  LOCAL lr IS ASC_ARD_LNRHO[0].
  LOCAL sa IS ASC_ARD_AS[0].
  LOCAL x IS (h - ASC_ARD_AIR_H0) / 1000.
  IF x > 0 {
    LOCAL i IS MIN(FLOOR(x), ASC_ARD_LNRHO:LENGTH - 2).
    LOCAL f IS x - i.
    SET lr TO ASC_ARD_LNRHO[i] + f * (ASC_ARD_LNRHO[i + 1] - ASC_ARD_LNRHO[i]).
    SET sa TO ASC_ARD_AS[i] + f * (ASC_ARD_AS[i + 1] - ASC_ARD_AS[i]).
  }
  LOCAL w IS V(vv:X + ASC_ARD_W * rr:Y, vv:Y - ASC_ARD_W * rr:X, vv:Z).
  LOCAL vr IS w:MAG.
  IF vr < 0.000001 { RETURN V(0, 0, 0). }
  RETURN (-0.5 * ASC_ARD_EU ^ lr * vr * ASC_ARD_AREF * ard_cd(vr / sa) / 1000 / M) * w.
}

// the derivative: LIST(r', v', et', om', the sensed acceleration)
FUNCTION ard_f {
  PARAMETER j, tt, rr, vv, et, om, oon, cmd, lam, lamd, TL.
  LOCAL Mm IS j["mc"] - om + et.
  LOCAL uu IS cmd.
  IF cmd:MAG = 0 { SET uu TO (lam + (tt - TL) * lamd):NORMALIZED. }
  LOCAL a IS MIN(j["K"] / 100 * ASC_PL_TO_KSP * j["m"]["f1"] * j["e"] / Mm, ASC_AL).
  LOCAL md IS a * Mm / j["m"]["vex"].
  LOCAL dom IS 0.
  IF oon { SET a TO a + ASC_ARD_FOMS / Mm. SET dom TO ASC_ARD_MDO. }
  LOCAL acc IS a * uu + ard_drag(rr, vv, Mm).
  RETURN LIST(vv, asc_grav(rr) + acc, -md, dom, acc).
}

// one PEG cycle at the job's state (dvs: the sensed dV since the last)
FUNCTION ard_cyc {
  PARAMETER j, dvs.
  LOCAL M IS j["mc"] - j["om"] + j["et"].
  LOCAL th IS ard_thr(j, M, ard_on(j, j["t"])).
  asc_peg_cycle(j["p"], j["t"], j["r"], j["v"], dvs, M, th[2] / th[3], ASC_FT_FACTOR * th[2] / M).
}

// a trace point (the path's): the state, the steering, IYD, the dump's schedule
FUNCTION ard_pt {
  PARAMETER j.
  IF NOT j["tr"] { RETURN. }
  LOCAL p IS j["p"].
  j["pts"]:ADD(LEXICON("t", j["t"], "r", j["r"], "v", j["v"], "et", j["et"], "om", j["om"],
    "steer", LIST(p["lamc"], p["lamdc"], p["tlamc"]), "iy", p["IYD"], "o", j["o"]:COPY)).
}

// ONE UNIT: the start's next PEG cycle, or one step and its pass (an RTLS test: one cycle). TRUE when it is over.
FUNCTION ard_unit {
  PARAMETER j.
  SET j["n"] TO j["n"] + 1.
  IF j:HASKEY("csa") { RETURN ard_cs_unit(j). }   // the coprocessor's flight
  IF j["md"] = "RTLS" { ard_rt_unit(j). }
  ELSE IF j["st"] = 0 { ard_init(j). }
  ELSE IF j["st"] = 1 { ard_step(j). }
  RETURN j["st"] = 2.
}

// ---- NEG RTN, calculated like the other boundaries: the RTLS's own turnaround test at a fixed state (the offline
// sim's fixed test: within 0.8 s of the
// full RTLS flights' last good SSME out on 12 of 13 dispersions, 1.6 s early on the 13th). At path point P: the SSME
// out and the RTLS (ne SSMEs at the abort throttle; asc_rtls_init's MBO with its dump to come, its PPD line), PEG's
// SMODE 5 cycled on P's state with the turn measured from the fuel dissipation attitude and DT_TURN iterated to its
// fixed point, until MF holds (ASC_ARD_RT_TOL) or ASC_ARD_RT_NMAX cycles; ONE UNIT = one cycle. Past the negative
// return when MF + M_BIAS < MBO (the turnaround test without its bias against a late turn: ard_margin). sn: the
// snapshot ("rs" the RTLS site in the PEG frame, as asc_rtls_init's ef); cc caches the PPD line by MBO (its prediction,
// ~52k opcodes, runs first in units of ASC_ARD_RT_NPPD steps, asc_rtls_ppd_line's arithmetic; MBO holds in a flight).
GLOBAL ASC_ARD_RT_TOL IS 0.002.           // t: MF held
GLOBAL ASC_ARD_RT_NMAX IS 12.             // cycles at most (10-11 seen)
GLOBAL ASC_ARD_RT_NPPD IS 50.             // the PPD prediction's 0.02 s steps a unit (~120 opcodes each)
FUNCTION ard_rt_new {
  PARAMETER sn, ne, P, cc.
  LOCAL K IS ASC_KMAX_ABORT.
  LOCAL mc IS sn["mc"] - P["om"].
  LOCAL M IS mc + P["et"].
  LOCAL rr IS P["r"].
  LOCAL t IS P["t"].
  LOCAL wd IS ASC_ARD_W * 57.29577951308232.
  LOCAL vrel IS P["v"] - VCRS(V(0, 0, ASC_ARD_W), rr).
  LOCAL uv IS rr:NORMALIZED.
  LOCAL hz IS (vrel - VDOT(vrel, uv) * uv):NORMALIZED.
  LOCAL vfd IS vrel:MAG.
  LOCAL th IS ASC_RTLS_THETA_2 + ASC_RTLS_THETA_3 * vfd.
  IF vfd < ASC_RTLS_V_SWTCH { SET th TO ASC_RTLS_THETA_0 + ASC_RTLS_THETA_1 * vfd + ASC_RTLS_THETA_4 * VDOT(uv, vrel). }
  SET th TO asc_mid(ASC_RTLS_THETA_MIN, th, ASC_RTLS_THETA_MAX).
  LOCAL ufd IS (COS(th) * hz + SIN(th) * uv):NORMALIZED.
  LOCAL ufb IS (COS(ASC_RTLS_THETA_FB) * hz + SIN(ASC_RTLS_THETA_FB) * uv):NORMALIZED.
  LOCAL dump IS ASC_RTLS_DUMP_T.
  IF vfd < ASC_RTLS_V_DUMP_SW { SET dump TO ASC_RTLS_DUMP_T_LO. }
  LOCAL vex IS sn["m"]["vex"].
  LOCAL md1 IS sn["m"]["f1"] / vex.
  LOCAL mk IS ASC_KMIN / 100 * ASC_PL_TO_KSP * md1 * ne.
  LOCAL mbo IS mc - dump + sn["res"] + mk * (asc_rtls_dt_pitch() + ASC_RTLS_DT_PPD_MARGIN).
  LOCAL st IS 1.
  LOCAL line IS LIST(0, 0).
  LOCAL lp IS LEXICON().
  IF cc:HASKEY("mbo") AND ABS(cc["mbo"] - mbo) <= 0.000001 { SET line TO cc["line"]. }
  ELSE {                                  // asc_rtls_ppd_predict's start (v0 750 m/s, GAMD, H_PPD, MBO, KMIN)
    SET st TO 0.
    SET lp TO LEXICON("vel", 750, "gm", ASC_RTLS_GAMD * 0.017453292519943295, "hh", ASC_RTLS_H_PPD, "xx", 0, "ms", mbo,
      "th", asc_rtls_th0, "tt", 0, "f", mk * vex, "md", mk).
  }
  LOCAL ef IS sn["rs"].
  LOCAL pg IS asc_peg_new(ASC_R + ASC_MECO_H, ASC_GAMD, ASC_VDMAG, P["iy"], mc, ASC_MU).
  SET pg["RTLS"] TO LEXICON("ef", ef, "w", wd, "A", line, "RTMAG", ef:MAG,
    "iy_save", VCRS(asc_rotz(ef, wd * t), rr):NORMALIZED, "K", K, "K_CMD", K, "STHROT", FALSE, "MBO", mbo,
    "KMIN", ASC_KMIN, "KMAX", K, "DELK_MAX", ASC_RTLS_DELK_MAX, "KMISS", ASC_RTLS_KMISS,
    "RNG_TURN_PRED", ASC_RTLS_RNG_TURN_PRED, "MDOT", K / 100 * ASC_PL_TO_KSP * md1 * ne, "RTHETA", 0, "close", FALSE,
    "VGOD", 0, "ERR", 0).
  SET pg["TAL"] TO LEXICON().
  SET pg["RDMAG"] TO ASC_R + ASC_RTLS_H_PPD.
  SET pg["GAMD"] TO ASC_RTLS_GAMD.
  SET pg["MASS_MIN"] TO 0.
  SET pg["S_INIT"] TO TRUE.
  SET pg["S_GDRDY"] TO FALSE.
  SET pg["SCONV"] TO FALSE.
  RETURN LEXICON("md", "RTLS", "p", pg, "t", t, "r", rr, "v", P["v"], "M", M, "vex", vex,
    "atr", ASC_FT_FACTOR * (K / 100 * ASC_PL_TO_KSP * sn["m"]["f1"] * ne) / M,
    "dt", VANG(ufd, ufb) / ASC_RTLS_DTHETA_LIM + ASC_RTLS_DTHETA_LIM / ASC_RTLS_DTHETA_RATE, "ufd", ufd,
    "MF", 0, "MBO", mbo, "ok", FALSE, "nc", 0, "st", st, "lp", lp, "cc", cc, "why", "", "n", 0).
}

// one cycle (the RTLS cycle in fast time on a fixed state: PEG ahead by DT_TURN, then MF and the new DT_TURN)
FUNCTION ard_rt_unit {
  PARAMETER j.
  LOCAL p IS j["p"].
  IF j["st"] = 0 {                        // the PPD line first (cached for the next tests)
    IF ard_rt_lp_step(j["lp"]) {
      SET j["cc"]["mbo"] TO j["MBO"].
      SET j["cc"]["line"] TO ard_rt_lp_line(j["lp"]).
      SET p["RTLS"]["A"] TO j["cc"]["line"].
      SET j["st"] TO 1.
    }
    RETURN.
  }
  LOCAL dt IS j["dt"].
  LOCAL vex IS j["vex"].
  LOCAL atr IS j["atr"].
  asc_peg_cycle(p, j["t"] + dt, j["r"] + dt * j["v"], j["v"], V(0, 0, 0), j["M"], vex, vex * atr / (vex - dt * atr)).
  SET j["nc"] TO j["nc"] + 1.
  IF p["RTLS"]["close"] {                 // too close for a solution: PEG starts again
    SET p["S_INIT"] TO TRUE.
    SET p["SCONV"] TO FALSE.
  } ELSE IF p["SCONV"] AND p:HASKEY("lam") {
    LOCAL mf IS j["M"] * ASC_ARD_EU ^ (-(p["vgo"]:MAG + atr * dt) / vex) - ASC_RTLS_M_BIAS.
    LOCAL uf IS (p["lam"] + (j["t"] + dt - p["TLAM"]) * p["lamd"]):NORMALIZED.
    SET j["dt"] TO VANG(j["ufd"], uf) / ASC_RTLS_DTHETA_LIM + ASC_RTLS_DTHETA_LIM / ASC_RTLS_DTHETA_RATE.
    LOCAL done IS j["ok"] AND ABS(mf - j["MF"]) < ASC_ARD_RT_TOL.
    SET j["MF"] TO mf.
    SET j["ok"] TO TRUE.
    IF done { SET j["st"] TO 2. SET j["why"] TO "conv". RETURN. }
  }
  IF j["nc"] >= ASC_ARD_RT_NMAX { SET j["st"] TO 2. SET j["why"] TO "nmax". }
}

// asc_rtls_ppd_predict's loop from lp's state, ASC_ARD_RT_NPPD steps at most (the same arithmetic). TRUE when done.
FUNCTION ard_rt_lp_step {
  PARAMETER lp.
  LOCAL tend IS asc_rtls_dt_pitch().
  LOCAL th_end IS ASC_RTLS_ALPHA_PPD - ASC_RTLS_THRUST_OFF.
  LOCAL sp IS asc_rtls_slew(0, 0, 0, asc_rtls_th0 - th_end, ASC_RTLS_PPD_RATE).
  LOCAL vel IS lp["vel"].
  LOCAL gm IS lp["gm"].
  LOCAL hh IS lp["hh"].
  LOCAL xx IS lp["xx"].
  LOCAL ms IS lp["ms"].
  LOCAL th IS lp["th"].
  LOCAL t IS lp["tt"].
  LOCAL f IS lp["f"].
  LOCAL md IS lp["md"].
  LOCAL k IS 0.
  UNTIL t >= tend - 1e-9 OR k >= ASC_ARD_RT_NPPD {
    LOCAL dh IS MIN(0.02, tend - t).
    LOCAL rad IS ASC_R + hh.
    LOCAL gg IS ASC_MU / (rad * rad).
    LOCAL ac IS f / ms.
    LOCAL gd IS gm * 57.295779513082323.
    LOCAL v1 IS vel + (ac * COS(th) - gg * SIN(gd)) * dh.
    LOCAL g1 IS gm + (ac * SIN(th) - (gg - vel * vel / rad) * COS(gd)) / vel * dh.
    SET hh TO hh + vel * SIN(gd) * dh.
    SET xx TO xx + vel * COS(gd) * dh * ASC_R / rad.
    SET vel TO v1.
    SET gm TO g1.
    SET ms TO ms - md * dh.
    SET th TO asc_rtls_th0 - asc_rtls_slew_at(sp, t + dh)[0].
    SET t TO t + dh.
    SET k TO k + 1.
  }
  SET lp["vel"] TO vel.
  SET lp["gm"] TO gm.
  SET lp["hh"] TO hh.
  SET lp["xx"] TO xx.
  SET lp["ms"] TO ms.
  SET lp["th"] TO th.
  SET lp["tt"] TO t.
  RETURN t >= tend - 1e-9.
}

// asc_rtls_ppd_line's line from the finished prediction lp: LIST(a0, a1)
FUNCTION ard_rt_lp_line {
  PARAMETER lp.
  LOCAL v0 IS 750.
  LOCAL am IS ASC_RTLS_A_MECO.
  LOCAL pr IS LIST(lp["vel"] - v0, lp["gm"] * 57.295779513082323 - ASC_RTLS_GAMD, lp["xx"]).
  LOCAL dt IS asc_rtls_dt_pitch().
  LOCAL gm IS (ASC_RTLS_GAMD + pr[1]) * 0.017453292519943295.
  LOCAL k IS 1 + am[1] * dt.
  RETURN LIST((am[0] - am[1] * (pr[2] - v0 * dt) - am[2] * gm - pr[0]) / k, am[1] / k).
}

// the start (PEG's first passes): PEG cycles at the fixed state, up to 8 (from the 2nd until converged), the
// flown steering kept; then the I-load update once (converged and M e^(-VGO / VEX) > MASS_MIN); droop (e = 1); a trace point
FUNCTION ard_init {
  PARAMETER j.
  LOCAL p IS j["p"].
  IF j["kc"] = 0 {
    SET j["keep"] TO LIST(p["lamc"], p["lamdc"], p["tlamc"]).
    SET p["S_INIT"] TO TRUE.
  }
  ard_cyc(j, V(0, 0, 0)).
  SET j["kc"] TO j["kc"] + 1.
  IF j["kc"] < 8 AND NOT (j["kc"] >= 2 AND p["SCONV"]) { RETURN. }
  SET p["lamc"] TO j["keep"][0].
  SET p["lamdc"] TO j["keep"][1].
  SET p["tlamc"] TO j["keep"][2].
  LOCAL M IS j["mc"] - j["om"] + j["et"].
  LOCAL th IS ard_thr(j, M, ard_on(j, j["t"])).
  IF p["SCONV"] AND M * ASC_ARD_EU ^ (-p["vgo"]:MAG / (th[2] / th[3])) > p["MASS_MIN"] {
    SET p["lamc"] TO p["lam"].
    SET p["lamdc"] TO p["lamd"].
    SET p["tlamc"] TO p["TLAM"].
  }
  IF j["e"] = 1 { ard_droop(j, ard_on(j, j["t"])). }
  ard_pt(j).
  SET j["st"] TO 1.
}

// one step: the dump off at TGO OMS_TGO_OFF; the step to the cutoff, the ET's reserve, the dump's
// on / off or the stop; RK4; the stops; else PEG's pass, droop (e = 1), a trace point
FUNCTION ard_step {
  PARAMETER j.
  LOCAL p IS j["p"].
  LOCAL t IS j["t"].
  LOCAL o IS j["o"].
  LOCAL oon IS ard_on(j, t).
  IF oon AND p["TGO"] < ASC_TAL_OMS_TGO_OFF { SET o[1] TO t. SET oon TO FALSE. }
  LOCAL lam IS p["lamc"].
  LOCAL lamd IS p["lamdc"].
  LOCAL TL IS p["tlamc"].
  LOCAL cmd IS V(0, 0, 0).
  IF j["D"]["cmd_on"] { SET cmd TO j["D"]["cmd"]. }
  LOCAL rr IS j["r"].
  LOCAL vv IS j["v"].
  LOCAL et IS j["et"].
  LOCAL om IS j["om"].
  LOCAL th IS ard_thr(j, j["mc"] - om + et, oon).
  LOCAL h IS ASC_ARD_DT.
  IF j:HASKEY("dt") { SET h TO j["dt"]. }         // the job's own step when it has one (E TAL: ASC_ETAL_DT)
  IF j["ts"] >= 0 { SET h TO MIN(h, j["ts"] - t). }
  LOCAL cut IS p["TGO"] <= h.
  IF cut { SET h TO MAX(p["TGO"], 0). }
  LOCAL tr IS (et - j["res"]) / th[1].
  LOCAL res IS tr <= h.
  IF res { SET h TO MAX(tr, 0). SET cut TO FALSE. }
  IF o:LENGTH > 0 {
    FOR x IN LIST(o[0], o[1]) {
      IF t + 0.000001 < x AND x < t + h - 0.000001 { SET h TO x - t. SET cut TO FALSE. SET res TO FALSE. }
    }
  }
  LOCAL dvs IS V(0, 0, 0).
  IF h > 0 {
    LOCAL h2 IS h / 2.
    LOCAL k1 IS ard_f(j, t, rr, vv, et, om, oon, cmd, lam, lamd, TL).
    LOCAL k2 IS ard_f(j, t + h2, rr + h2 * k1[0], vv + h2 * k1[1], et + h2 * k1[2], om + h2 * k1[3], oon, cmd, lam,
      lamd, TL).
    LOCAL k3 IS ard_f(j, t + h2, rr + h2 * k2[0], vv + h2 * k2[1], et + h2 * k2[2], om + h2 * k2[3], oon, cmd, lam,
      lamd, TL).
    LOCAL k4 IS ard_f(j, t + h, rr + h * k3[0], vv + h * k3[1], et + h * k3[2], om + h * k3[3], oon, cmd, lam, lamd, TL).
    LOCAL h6 IS h / 6.
    SET rr TO rr + h6 * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]).
    SET vv TO vv + h6 * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]).
    SET et TO et + h6 * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]).
    SET om TO om + h6 * (k1[3] + 2 * k2[3] + 2 * k3[3] + k4[3]).
    SET dvs TO h6 * (k1[4] + 2 * k2[4] + 2 * k3[4] + k4[4]).
  }
  SET t TO t + h.
  SET j["t"] TO t.
  SET j["r"] TO rr.
  SET j["v"] TO vv.
  SET j["et"] TO et.
  SET j["om"] TO om.
  LOCAL ah IS rr:MAG - ASC_R.
  IF VDOT(rr, vv) < 0 { SET j["down"] TO TRUE. }
  IF j["down"] { SET j["hmin"] TO MIN(j["hmin"], ah). }
  IF cut { SET j["why"] TO "cut". }
  ELSE IF res OR et <= j["res"] + 0.000000001 { SET j["why"] TO "res". }
  ELSE IF j["down"] AND ah < ASC_ARD_H_LOW { SET j["why"] TO "low". }
  ELSE IF t - j["t0"] > ASC_ARD_T_MAX { SET j["why"] TO "time". }
  ELSE IF j["ts"] >= 0 AND t >= j["ts"] - 0.000000001 {
    ard_cyc(j, dvs).
    ard_pt(j).
    SET j["why"] TO "stop".
  }
  IF j["why"] <> "" { SET j["st"] TO 2. RETURN. }
  ard_cyc(j, dvs).
  IF j["e"] = 1 { ard_droop(j, ard_on(j, t)). }
  ard_pt(j).
}

// FSSR 4.3.4 subtasks 1-3 for the fast-time flight (lib_ascent_cnt's asc_drp_pass): the predicted
// minimum altitude at the droop attitude; the task steers at THR_ATT while it would fall below MIN_DROOP_ALT
FUNCTION ard_droop {
  PARAMETER j, oon.
  LOCAL D IS j["D"].
  LOCAL p IS j["p"].
  LOCAL t IS j["t"].
  LOCAL dtgd IS ASC_DTGD.
  IF D["t_prev"] >= 0 { SET dtgd TO t - D["t_prev"]. }
  SET D["t_prev"] TO t.
  IF D["S_MIN_ALT"] { SET D["cmd_on"] TO FALSE. RETURN. }
  LOCAL HMIN IS ASC_DRP_MIN_ALT.
  LOCAL rr IS j["r"].
  LOCAL vv IS j["v"].
  LOCAL M IS j["mc"] - j["om"] + j["et"].
  LOCAL RINIT IS rr:MAG.
  LOCAL IR IS rr:NORMALIZED.
  LOCAL IY IS VCRS(p["lamc"], IR):NORMALIZED.
  LOCAL IZ IS VCRS(IR, IY).
  LOCAL PEG_CMD IS (p["lamc"] + (t - p["tlamc"]) * p["lamdc"]):NORMALIZED.
  LOCAL PEG_ATT IS 90 - ARCCOS(MAX(-1, MIN(1, VDOT(PEG_CMD, IR)))).
  LOCAL VX IS VDOT(vv, IR).
  LOCAL VY IS VDOT(vv, IY).
  LOCAL VZ IS VDOT(vv, IZ).
  LOCAL GE IS ASC_MU / RINIT ^ 2.
  LOCAL GACC IS GE - (VY ^ 2 + VZ ^ 2) / RINIT.
  LOCAL TNEW IS D["T1NEW"] - dtgd.
  LOCAL th IS ard_thr(j, M, oon).
  LOCAL TV_MAX IS th[2].
  LOCAL MDT IS th[3].
  IF NOT D["S_CDROOP"] { SET D["THR_ATT"] TO ASC_DRP_THRESH_ATT. }
  ELSE IF oon AND TNEW > 0 {                 // the OMS dump's share of the thrust until it stops
    LOCAL fon IS MIN(1, (j["o"][1] - t) / TNEW).
    SET TV_MAX TO th[2] * fon + th[0] * (1 - fon).
    SET MDT TO TV_MAX / (th[2] / th[3] * fon + j["m"]["vex"] * (1 - fon)).
  }
  LOCAL TMMAX IS (M - (j["mc"] - j["om"] + j["res"])) / MDT.
  LOCAL pr IS asc_drp_pred(M, TV_MAX * SIN(D["THR_ATT"]), TV_MAX * COS(D["THR_ATT"]), GACC, MDT, VY, TMMAX, VX, VZ,
    RINIT, TNEW, GE, RINIT - ASC_R).
  LOCAL ROUT IS pr[0].
  IF pr[2] {
    SET D["T1NEW"] TO pr[1].
    LOCAL S_ATT_CMD IS ROUT < HMIN AND pr[3].
    LOCAL S_PEG_OK IS (NOT p["low_tw"]) AND p["SCONV"] AND PEG_ATT < D["THR_ATT"].
    SET D["S_MIN_ALT"] TO D["S_CDROOP"] AND (D["T1NEW"] <= 0
      OR (S_PEG_OK AND ROUT > HMIN + ASC_DRP_ALT_PEG_LOSS * D["T1NEW"])).
    SET D["S_CDROOP"] TO (NOT D["S_MIN_ALT"]) AND (S_ATT_CMD OR D["S_CDROOP"])
      AND (j["e"] < ASC_DRP_NSSME OR (j["e"] < 3 AND ASC_DRP_ENA)).
  } ELSE {
    SET D["S_CDROOP"] TO FALSE.
  }
  IF D["S_CDROOP"] {
    IF D["t_on"] < 0 { SET D["t_on"] TO t. }
    IF ROUT < HMIN { SET D["THR_ATT"] TO D["THR_ATT"] + ASC_DRP_ATT_INCR. }
    ELSE IF ROUT > HMIN + ASC_DRP_ALT_DBND * ASC_DRP_ATT_INCR * 3.141592653589793 / 180 {
      SET D["THR_ATT"] TO D["THR_ATT"] - ASC_DRP_ATT_INCR.
    }
    SET D["THR_ATT"] TO MAX(ASC_DRP_THR_MIN, MIN(D["THR_ATT"], ASC_DRP_THR_MAX)).
    IF NOT D["S_DRP_EARLY"] {
      SET D["THR_ATT"] TO ASC_DRP_THR_MAX.
      IF ROUT > HMIN {
        SET D["S_DRP_EARLY"] TO TRUE.
        SET D["THR_ATT"] TO ASC_DRP_THR_MIN.
      }
    }
    IF D["S_DRP_EARLY"] {
      SET D["cmd"] TO (SIN(D["THR_ATT"]) * IR + COS(D["THR_ATT"]) * IZ):NORMALIZED.
      SET D["cmd_on"] TO TRUE.
    }
  } ELSE {
    SET D["cmd_on"] TO FALSE.
  }
}

// the ATO's OMS need (ato.two_burn at ATO_H, ATO_H + the deorbit's keep), m/s: OMS-1 at the cutoff (horizontal,
// impulsive) raises the apogee to ATO_H if lower, OMS-2 at the apogee circularizes there
FUNCTION ard_ato_need {
  PARAMETER rr, vv.
  LOCAL mu IS ASC_MU.
  LOCAL rm IS rr:MAG.
  LOCAL hv IS VCRS(rr, vv):MAG.
  LOCAL en IS VDOT(vv, vv) / 2 - mu / rm.
  LOCAL ra IS 1E30.
  LOCAL rp IS hv * hv / mu / 2.
  IF en < 0 {
    LOCAL sa IS -mu / (2 * en).
    LOCAL ec IS SQRT(MAX(0, 1 - hv * hv / (mu * sa))).
    SET ra TO sa * (1 + ec).
    SET rp TO sa * (1 - ec).
  }
  LOCAL rat IS ASC_R + ASC_ATO_H.
  LOCAL dv1 IS 0.
  IF ra < rat {
    LOCAL vh IS hv / rm.
    LOCAL vh1 IS vh.
    IF rm <= rat { SET vh1 TO SQRT(mu * (2 / rm - 2 / (rat + rm))). }
    SET dv1 TO MAX(0, vh1 - vh).
    SET ra TO rat.
    SET rp TO MIN(rm, rat).
  }
  LOCAL r2 IS MIN(rat, ra).
  LOCAL dv2 IS ABS(SQRT(mu * (2 / ra - 2 / (ra + r2))) - SQRT(mu * (2 / ra - 2 / (ra + rp)))).
  RETURN dv1 + dv2 + ASC_ATO_DV_DEORBIT.
}

// the margin of a finished flight, m/s-like, >= 0 = it works: PRESS the dV left at the cutoff (- PEG's
// VGO at the reserve); TAL that + TAL_VGO_TOL; ATO the OMS dV left after its two burns; TAL / ATO also the floor (MECO
// and the trough over MIN_DROOP_ALT, 10 m per m/s). RTLS (t, >= 0 = PAST the negative return): MBO - (MF + M_BIAS); no
// solution counts as not past
FUNCTION ard_margin {
  PARAMETER j.
  IF j:HASKEY("csm") { RETURN j["csm"]. }   // the coprocessor's
  IF j["md"] = "RTLS" {
    IF NOT j["ok"] { RETURN -1. }
    RETURN j["MBO"] - j["MF"] - ASC_RTLS_M_BIAS.
  }
  LOCAL M IS j["mc"] - j["om"] + j["et"].
  LOCAL left IS j["et"] - j["res"].
  LOCAL dv IS -j["p"]["vgo"]:MAG.
  IF j["why"] = "cut" {
    SET dv TO 0.
    IF left > 0 AND left < M { SET dv TO j["m"]["vex"] * LN(M / (M - left)). }
  }
  IF j["md"] = "PRESS" { RETURN dv. }
  LOCAL hf IS ASC_DRP_MIN_ALT.                   // MECO's floor: the job's own when it has one (E TAL: ASC_ETAL_HF)
  IF j:HASKEY("hf") { SET hf TO j["hf"]. }
  LOCAL fl IS (j["r"]:MAG - ASC_R - hf) / 10.
  IF j["down"] { SET fl TO MIN(fl, (j["hmin"] - ASC_DRP_MIN_ALT) / 10). }
  IF j["md"] = "TAL" { RETURN MIN(dv + ASC_ARD_TAL_VGO_TOL, fl). }
  LOCAL odv IS ASC_ARD_OMS_DV.                   // the OMS measured with the payload (the launch box) when known
  IF ASC_OMS_DV_NOW > 0 { SET odv TO ASC_OMS_DV_NOW. }
  RETURN MIN(odv - ard_ato_need(j["r"], j["v"]), fl).
}

// ---- THE SEARCH (the offline sim's boundaries mirror it: within 2 s of the full flights'
// truth). From a snapshot (ops1q's, after a PEG pass): THE PATH AHEAD = the flown guidance fast (the selected mode on
// the running SSMEs at the flown throttle, the dump on its schedule; a point after each ASC_ARD_DT s pass); then per
// level (an abort on e SSMEs: ard_levels) its margin at path points: from the guess (the last boundary's MET, else the
// tables' VI) forward to the first rise through zero, or back to it; ASC_ARD_NBIS bisections in the bracket (the state
// at the middle by the path's guidance, then the abort from there); the boundary (MET, VI) interpolated. A margin >= 0
// at the path's start = passed ("open": latched there); none rising = "never" (ASC_ARD_NEVER). Each unit = one of the
// flights' units (ard_unit), so the work spreads over ops1q's main-loop passes. Vessel-free: ops1q hands it the state.
// THE SEARCH'S SPEED-UPS: the levels' abort flights step ASC_ARD_JDT s on 2-3 SSMEs, ASC_ARD_JDT1 on one (the path and
// the bracket's middles ASC_ARD_DT); ASC_ARD_NBIS bisections (ASC_ARD_NBIS_NEAR for a bracket within ASC_ARD_NEAR s of
// now); each seek starts before the level's last VI (+ the pad's mass shift the snapshot carries), not its MET; a TAL
// never reached flies only last time's best point between full rescans; the soonest boundary first (ard_lv_k0s,
// ard_lv_next)
GLOBAL ASC_ARD_NBIS IS 2.                 // bisections in the 8 s bracket (to 2 s; 3 = the offline sim's)
GLOBAL ASC_ARD_NBIS_NEAR IS 3.            // bisections (to 1 s) for a bracket starting within ASC_ARD_NEAR s of now
GLOBAL ASC_ARD_NEAR IS 30.0.              // s
GLOBAL ASC_ARD_JDT IS 16.0.               // s, the levels' abort flights' step on 2-3 SSMEs (ASC_ARD_DT = the full-resolution step)
GLOBAL ASC_ARD_JDT1 IS 4.0.               // s, on 1 SSME (at 12-16 s a 2EO TAL after a 1EO moved 6 s and its sites
//                                           swapped order against the offline truth). 4, not 8: 8 s steps make the
//                                           TAL mark flicker near the 67 km floor (monotone in 0 of 8 cases; 4 s:
//                                           8 of 8)
GLOBAL ASC_ARD_NEVER_Q IS 2.              // a TAL never reached: refreshes flying only last time's best point
//                                           between its full rescans (0 = a full rescan each refresh)
GLOBAL ASC_ARD_NEVER IS 100000.           // m/s: a boundary off the scale (never reached, or not the selection's)
GLOBAL ASC_ARD_ROOM IS 7000.              // opcodes: a further unit in a pass only with this many left in the tick (a
//                                           unit: 3600-4950 a start's PEG cycle, 5700-7780 a step; kOS's VM)
GLOBAL ASC_ARD_MAXU IS 2.                 // units a main-loop pass at most (the first always: the search never starves)
GLOBAL ASC_ARD_TGO_OFF IS 15.0.           // s: no search this close to MECO (PEG's TGO)
GLOBAL ASC_ARD_2EO_STAG IS TRUE.          // a staggered 2nd failure flies the 2EO line once the ARD refreshed on 2 SSMEs
// THE PEG-ESTIMATE SEEK (ASC_ARD_COARSE): ATO, PRESS_2EO and ATO_2EO (this one on 3 SSMEs only) seek on PEG's own
// estimate at each path point instead of a flown abort: the job's start only (its PEG converged, 2-8 units, not the
// flight), est = VEX ln(M / (M - left)) - |VGO| against the level's bias B, adaptive jumps, the boundary interpolated
// between the last short and the first good point (no bisection). Not converged or no bracket: the flown seek from
// there. FALSE: the flown search only. B (fitted offline): ATO / ATO_2EO derived, -VEX ln(1 + res / (mc - om)) (the
// reserve the flown margin keeps); PRESS_2EO 0. The marks then move ASC_ARD_PE_TB s later (ATO +0.9, PRESS_2EO +1.6,
// ATO_2EO +1.2: inside the allowed 5 s late or 0.5 s early on the offline and the VM's cases)
GLOBAL ASC_ARD_COARSE IS TRUE.
GLOBAL ASC_ARD_PE_SD IS LEXICON("ATO", 4, "PRESS", 2, "PRESS_2EO", 4, "ATO_2EO", 8).   // m/s a path point: the jump scale
GLOBAL ASC_ARD_PE_B IS LEXICON("PRESS_2EO", 0).   // m/s: the fixed biases (ATO / ATO_2EO derived). PRESS stays FLOWN:
//                                           its estimate's error spreads 8 s (the VM, 14 cases: -4.9 .. +3.0 s), wider than
//                                           the window; the in-flight learning (to come) may take it
GLOBAL ASC_ARD_PE_TB IS LEXICON("ATO", 0.9, "PRESS_2EO", 1.6, "ATO_2EO", 1.2).   // s: the mark's shift (ATO_2EO: the
//                                           VM's 30 cases ran -1.1 .. +0.8 s against the flown search)
GLOBAL ASC_ARD_PE_IT IS 12.               // seek steps at most

// the search's state: the phase (0 waits for a snapshot, 1 the path, 2 the levels, 3 off), the snapshot (the path's
// flight), the path's job and points, the levels and the one in hand, the job in hand and what it is ("m" the margin
// at path point kk, "sa" the state in the bracket's middle, "mb" the margin there), the seek (its start k0, direction,
// the rescan from 0, the margins found), the bracket (Pa / Pb, their margins, the bisections done, the middle Pm); the
// SSMEs and the selection it runs for, refreshed once on 2 SSMEs (ok2), the refreshes, the snapshot's MET, the units,
// the tables' VIs (the seeds), the finished levels' log lines. NB kOS lexicon keys ignore case: none may differ by case
FUNCTION ard_srch_new {
  RETURN LEXICON("ph", 3, "sn", LEXICON(), "pj", LEXICON(), "pts", LIST(), "lv", LIST(), "li", 0, "fj", LEXICON(),
    "fk", "", "kk", 0, "k0", 0, "dir", 0, "rescan", FALSE, "ms", LEXICON(), "Pa", LEXICON(), "Pb", LEXICON(), "ma", 0,
    "mb", 0, "nb", 0, "Pm", LEXICON(), "nrun", 0, "sel", "", "site", "", "ok2", FALSE, "nref", 0, "t_ref", -1, "u", 0,
    "seed", LEXICON(), "msg", LIST(), "rtl", LEXICON(), "vd_lv", LIST(), "vd_k", 0, "vd_j", LEXICON(),
    "vd_P", LEXICON(), "vd_ln", "", "vd_st", "", "tls", LEXICON(), "rk", LEXICON(), "rk_l", LIST(), "rk_k", 0,
    "rk_j", LEXICON(), "rk_t", -1,    // the sites' targets; the rank (site: LIST(margin, MET, SSMEs)) and its work
    "dn", LIST(), "k0s", LEXICON(), "q1", FALSE, "nbm", ASC_ARD_NBIS,   // the levels done this refresh, their
    "pe", LEXICON(), "plo", -1, "phi", -1, "pit", 0, "pb", 0).   // seek starts (key: LIST(k0, quick)), the level in
}                                         // hand's quick check, its NBIS; the PEG-estimate seek's estimates (k: LIST(est, converged)),
//                                           the bracket's ends, the steps, B

// a level: its key, the pages' (asc["abr"]["b"]), the abort's SSMEs, mode, TAL site and target (asc_tal_lex); the
// boundary (tb MET s, vb VI m/s; -1 none yet), latched (passed), the note ("" / "open" / "never"), the searches done;
// a "never"'s best margin's VI in its last full scan (bv, -1 none) and its quick checks since (nq)
FUNCTION ard_lv_new {
  PARAMETER key, dk, ne, md, site, tl.
  RETURN LEXICON("key", key, "dk", dk, "e", ne, "md", md, "site", site, "tl", tl, "tb", -1, "vb", -1, "lat", FALSE,
    "note", "", "nc", 0, "bv", -1, "nq", 0).
}

// the levels for nrun SSMEs and the selection (sel "" / "ATO" / "TAL" to site): on 3 with none selected the 1EO ones
// (ATO, PRESS, NEG RTN on 2), then the 2EO ones on 1: TAL at each site (a TAL selected: its site), ATO (not with a TAL), PRESS
// (none selected); a level kept keeps its boundary and latch. tls: each site's target (asc_tal_lex)
FUNCTION ard_levels {
  PARAMETER S, nrun, sel, site, tls.
  LOCAL L IS LIST().
  IF nrun >= 3 AND sel = "" {
    L:ADD(ard_lv_new("ATO", "ATO", 2, "ATO", "", LEXICON())).
    L:ADD(ard_lv_new("PRESS", "PRESS", 2, "PRESS", "", LEXICON())).
    L:ADD(ard_lv_new("NEG_RTN", "NEG_RTN", 2, "RTLS", "", LEXICON())).   // past it once its margin >= 0
  }
  IF nrun >= 2 {
    FOR st IN ASC_TAL_SITES {             // NB not "s": kOS names ignore case, and S is the state
      IF tls:HASKEY(st) AND (sel <> "TAL" OR st = site) {
        L:ADD(ard_lv_new("TAL_2EO_" + st, "TAL_2EO", 1, "TAL", st, tls[st])).
      }
    }
    IF sel <> "TAL" { L:ADD(ard_lv_new("ATO_2EO", "ATO_2EO", 1, "ATO", "", LEXICON())). }
    IF sel = "" { L:ADD(ard_lv_new("PRESS_2EO", "PRESS_2EO", 1, "PRESS", "", LEXICON())). }
  }
  FOR x IN L {
    FOR y IN S["lv"] {
      IF y["key"] = x["key"] {
        SET x["tb"] TO y["tb"].
        SET x["vb"] TO y["vb"].
        SET x["lat"] TO y["lat"].
        SET x["note"] TO y["note"].
        SET x["nc"] TO y["nc"].
        SET x["bv"] TO y["bv"].
        SET x["nq"] TO y["nq"].
      }
    }
  }
  RETURN L.
}

// a new start (stage 2's, an SSME out, a selection): the levels for nrun SSMEs and the selection, the jobs dropped, the
// next snapshot awaited; off (the boundaries kept, ok2 too) below 2 SSMEs, in an RTLS or the contingency
FUNCTION ard_srch_reset {
  PARAMETER S, nrun, sel, site, tls.
  SET S["pj"] TO LEXICON().
  SET S["fj"] TO LEXICON().
  SET S["tls"] TO tls.                     // the rank's sites
  IF nrun < 2 OR sel = "RTLS" OR sel = "CONT" OR NOT ASC_ARD_ON { SET S["ph"] TO 3. RETURN. }
  SET S["lv"] TO ard_levels(S, nrun, sel, site, tls).
  FOR x IN S["lv"] { SET x["nq"] TO ASC_ARD_NEVER_Q. }   // a new path: a never-reached TAL rescans fully
  SET S["nrun"] TO nrun.
  SET S["sel"] TO sel.
  SET S["site"] TO site.
  SET S["ok2"] TO FALSE.
  SET S["ph"] TO 0.
}

// a refresh from the snapshot a (ard_new's: the selected mode on the running SSMEs at the flown throttle; its trace
// and stop set here) with the tables' VIs (seed, m/s)
FUNCTION ard_srch_go {
  PARAMETER S, a, seed.
  SET a["tr"] TO TRUE.
  SET a["ts"] TO -1.
  SET S["sn"] TO a.
  SET S["seed"] TO seed.
  IF ard_cs_on() { ard_cs_setup(). }        // the C# coprocessor
  SET S["pj"] TO ard_new(a).
  SET S["t_ref"] TO a["t"].
  SET S["ph"] TO 1.
}

// ONE UNIT of the search: the path's (ph 1), else the level's job (its start, or one of its units, and its result)
FUNCTION ard_srch_unit {
  PARAMETER S.
  SET S["u"] TO S["u"] + 1.
  IF S["ph"] = 5 { ard_rk_unit(S). RETURN. }   // the site rank
  IF S["ph"] = 1 {
    IF ard_unit(S["pj"]) {
      SET S["pts"] TO S["pj"]["pts"].
      SET S["pj"] TO LEXICON().
      IF S["pts"]:LENGTH < 2 { SET S["ph"] TO 0. RETURN. }   // no path (no thrust): the next snapshot
      SET S["ph"] TO 2.
      SET S["li"] TO -1.
      SET S["dn"] TO LIST().
      SET S["fk"] TO "k0".                  // the levels' seek starts next, a unit of their own
    }
    RETURN.
  }
  IF S["ph"] <> 2 { RETURN. }
  IF S["fk"] = "k0" { ard_lv_k0s(S). ard_lv_next(S). RETURN. }   // the seek starts, then the soonest level
  LOCAL lv IS S["lv"][S["li"]].
  IF S["fj"]:LENGTH = 0 {
    IF S["fk"] = "sa" { SET S["fj"] TO ard_sa_job(S, S["Pa"], 0.5 * (S["Pa"]["t"] + S["Pb"]["t"])). }
    ELSE {
      IF S["fk"] = "mb" { SET S["fj"] TO ard_lv_job(S, lv, S["Pm"]). }
      ELSE { SET S["fj"] TO ard_lv_job(S, lv, S["pts"][S["kk"]]). }
      IF lv["md"] <> "RTLS" { SET S["fj"]["dt"] TO CHOOSE ASC_ARD_JDT IF lv["e"] >= 2 ELSE ASC_ARD_JDT1. }   // the level's own step
    }
    RETURN.
  }
  IF S["fk"] = "pe" {                       // the PEG-estimate seek: the job's start only, then its estimate
    ard_unit(S["fj"]).
    LOCAL jp IS S["fj"].
    IF jp["st"] = 0 { RETURN. }
    SET S["fj"] TO LEXICON().
    LOCAL cv IS jp["st"] = 1 AND jp["p"]["SCONV"].
    LOCAL est IS -1E9.
    IF cv {
      LOCAL M IS jp["mc"] - jp["om"] + jp["et"].
      LOCAL left IS jp["et"] - jp["res"].
      LOCAL dva IS 0.
      IF left > 0 AND left < M { SET dva TO jp["m"]["vex"] * LN(M / (M - left)). }
      SET est TO dva - jp["p"]["vgo"]:MAG.
    }
    SET S["pe"][S["kk"]] TO LIST(est, cv).
    ard_pe_next(S).
    RETURN.
  }
  IF NOT ard_unit(S["fj"]) { RETURN. }
  LOCAL j IS S["fj"].
  SET S["fj"] TO LEXICON().
  IF S["fk"] = "sa" {                       // the middle (ard2.state_at): the last point, its OMS from the path's start
    LOCAL pm IS j["pts"][j["pts"]:LENGTH - 1]:COPY.
    SET pm["om"] TO pm["om"] + S["Pa"]["om"].
    SET S["Pm"] TO pm.
    SET S["fk"] TO "mb".
    RETURN.
  }
  LOCAL m IS ard_margin(j).
  IF S["fk"] = "mb" {
    SET S["nb"] TO S["nb"] + 1.
    IF m < 0 { SET S["Pa"] TO S["Pm"]. SET S["ma"] TO m. } ELSE { SET S["Pb"] TO S["Pm"]. SET S["mb"] TO m. }
    ard_bis_next(S).
    RETURN.
  }
  SET S["ms"][S["kk"]] TO m.
  ard_seek(S, m).
}

// the level's abort from path point P (ard2.margins): its e SSMEs at the abort throttle from P's state and steering;
// the dump P carries, else a TAL's own TAL_OMS_DELAY s after P
FUNCTION ard_lv_job {
  PARAMETER S, lv, P.
  IF lv["md"] = "RTLS" { RETURN ard_rt_new(S["sn"], lv["e"], P, S["rtl"]). }   // NEG RTN: the turnaround test
  LOCAL sn IS S["sn"].
  LOCAL o IS P["o"].
  IF o:LENGTH = 0 AND lv["md"] = "TAL" AND ASC_TAL_DUMP > 0 {
    SET o TO LIST(P["t"] + ASC_TAL_OMS_DELAY, P["t"] + ASC_TAL_OMS_DELAY + ASC_TAL_DUMP / ASC_ARD_MDO).
  }
  LOCAL a IS LEXICON("md", lv["md"], "tl", lv["tl"], "e", lv["e"], "K", ASC_KMAX_ABORT, "t", P["t"], "r", P["r"],
    "v", P["v"], "et", P["et"], "mc", sn["mc"] - P["om"], "res", sn["res"], "iy", P["iy"], "steer", P["steer"],
    "o", o, "m", sn["m"], "tr", FALSE, "ts", -1).
  LOCAL j IS ard_new(a).
  // the coprocessor flies it (not a PEG-estimate start: that one reads the job's PEG after its start)
  IF j["st"] = 0 AND ard_cs_on() AND (S["ph"] = 5 OR S["fk"] <> "pe") { SET j["csa"] TO a. }
  RETURN j.
}

// ---- the coprocessor's side (the block above ASC_ARD_CS)
FUNCTION ard_cs_on {                      // the switch on and the addon installed
  IF NOT ASC_ARD_CS { RETURN FALSE. }
  IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
  RETURN ADDONS:KALS:AVAILABLE.
}

FUNCTION ard_cs_setup {                   // every ASC_* the flights read, at each refresh (ASC_OMS_DV_NOW can change)
  ADDONS:KALS:SETUP(LEXICON("ASC_R", ASC_R, "ASC_MECO_H", ASC_MECO_H, "ASC_GAMD", ASC_GAMD, "ASC_VDMAG", ASC_VDMAG,
    "ASC_ATO_VDMAG", ASC_ATO_VDMAG, "ASC_MU", ASC_MU, "ASC_J2", ASC_J2, "ASC_R_J2", ASC_R_J2, "ASC_PL_TO_KSP", ASC_PL_TO_KSP,
    "ASC_FT_FACTOR", ASC_FT_FACTOR, "ASC_AL", ASC_AL, "ASC_TAL_OMS_TGO_OFF", ASC_TAL_OMS_TGO_OFF, "ASC_ARD_DT", ASC_ARD_DT,
    "ASC_ARD_H_LOW", ASC_ARD_H_LOW, "ASC_ARD_T_MAX", ASC_ARD_T_MAX, "ASC_ARD_TAL_VGO_TOL", ASC_ARD_TAL_VGO_TOL,
    "ASC_ARD_FOMS", ASC_ARD_FOMS, "ASC_ARD_MDO", ASC_ARD_MDO, "ASC_ARD_AIR_H0", ASC_ARD_AIR_H0,
    "ASC_ARD_ATM_TOP", ASC_ARD_ATM_TOP, "ASC_ARD_AREF", ASC_ARD_AREF, "ASC_ARD_OMS_DV", ASC_ARD_OMS_DV,
    "ASC_ARD_W", ASC_ARD_W, "ASC_DRP_MIN_ALT", ASC_DRP_MIN_ALT, "ASC_ATO_H", ASC_ATO_H,
    "ASC_ATO_DV_DEORBIT", ASC_ATO_DV_DEORBIT, "ASC_OMS_DV_NOW", ASC_OMS_DV_NOW, "ASC_DTMAX", ASC_DTMAX,
    "ASC_DTMIN", ASC_DTMIN, "ASC_NSEG", ASC_NSEG, "ASC_ETB", ASC_ETB, "ASC_KMISS", ASC_KMISS, "ASC_RHOMAG", ASC_RHOMAG,
    "ASC_PHIDOT_MAX", ASC_PHIDOT_MAX, "ASC_EPSTGO", ASC_EPSTGO, "ASC_DTRD", ASC_DTRD,
    "ASC_DRP_THR_MAX", ASC_DRP_THR_MAX, "ASC_DRP_THR_MIN", ASC_DRP_THR_MIN, "ASC_DRP_THRESH_ATT", ASC_DRP_THRESH_ATT,
    "ASC_DRP_ATT_INCR", ASC_DRP_ATT_INCR, "ASC_DRP_ALT_DBND", ASC_DRP_ALT_DBND, "ASC_DRP_ALT_PEG_LOSS", ASC_DRP_ALT_PEG_LOSS,
    "ASC_DRP_VMISS", ASC_DRP_VMISS, "ASC_DRP_PASS_MAX", ASC_DRP_PASS_MAX, "ASC_DRP_NSSME", ASC_DRP_NSSME,
    "ASC_DRP_ENA", CHOOSE 1 IF ASC_DRP_ENA ELSE 0, "ASC_DTGD", ASC_DTGD,
    "ASC_ARD_LNRHO", ASC_ARD_LNRHO, "ASC_ARD_AS", ASC_ARD_AS, "ASC_ARD_CDM", ASC_ARD_CDM)).
}

FUNCTION ard_cs_unit {                    // one unit of a coprocessor flight: start it, then ask; TRUE when it is over
  PARAMETER j.
  IF NOT j:HASKEY("cs") {
    LOCAL a IS j["csa"].
    IF j:HASKEY("dt") { SET a["dt"] TO j["dt"]. }   // the level's own step (JDT / JDT1), set after ard_lv_job
    IF j:HASKEY("hf") { SET a["hf"] TO j["hf"]. }
    SET j["cs"] TO ADDONS:KALS:FTS(a).
    RETURN FALSE.
  }
  LOCAL h IS j["cs"].
  IF NOT h:DONE { RETURN FALSE. }
  IF h:WHY = "error" {                      // the addon failed: off for this flight, the job flown here from its start
    SET ASC_ARD_CS_ERR TO h:ERROR.
    SET ASC_ARD_CS TO FALSE.
    j:REMOVE("cs").
    j:REMOVE("csa").
    RETURN FALSE.
  }
  SET j["why"] TO h:WHY.
  SET j["t"] TO h:T.
  SET j["r"] TO h:R.
  SET j["v"] TO h:V.
  SET j["et"] TO h:ET.
  SET j["om"] TO h:OM.
  SET j["csm"] TO h:MARGIN.
  SET j["st"] TO 2.
  RETURN TRUE.
}

// the path's state at tm from its point P (ard2.state_at): the path's flight from P, stopped at tm
FUNCTION ard_sa_job {
  PARAMETER S, P, tm.
  LOCAL sn IS S["sn"].
  RETURN ard_new(LEXICON("md", sn["md"], "tl", sn["tl"], "e", sn["e"], "K", sn["K"], "t", P["t"], "r", P["r"],
    "v", P["v"], "et", P["et"], "mc", sn["mc"] - P["om"], "res", sn["res"], "iy", P["iy"], "steer", P["steer"],
    "o", P["o"], "m", sn["m"], "tr", TRUE, "ts", tm)).
}

// ONE UNIT at the path's end, each level's seek start this refresh (k0s: key -> LIST(k0, quick)): the path
// point before the level's last boundary VI (+ the pad's mass shift the snapshot carries: sh, the pages' shift),
// else before the tables' VI (the seed), else the path's last but one; a TAL never reached: the point nearest its best
// VI of the last full scan (quick: that point only) while its quick checks since < ASC_ARD_NEVER_Q, else the last but one
FUNCTION ard_lv_k0s {
  PARAMETER S.
  LOCAL P IS S["pts"].
  LOCAL n IS P:LENGTH.
  LOCAL pv IS LIST().
  FOR pq IN P { pv:ADD(pq["v"]:MAG). }
  LOCAL sh IS LEXICON().
  IF S["sn"]:HASKEY("sh") { SET sh TO S["sn"]["sh"]. }
  SET S["k0s"] TO LEXICON().
  FOR lv IN S["lv"] {
    LOCAL k0 IS n - 2.
    LOCAL qk IS FALSE.
    LOCAL vs IS -1.
    IF lv["note"] = "never" {
      IF lv["md"] = "TAL" AND lv["bv"] >= 0 AND lv["nq"] < ASC_ARD_NEVER_Q {
        SET qk TO TRUE.
        SET k0 TO 0.
        FROM { LOCAL k IS 1. } UNTIL k >= n STEP { SET k TO k + 1. } DO {
          IF ABS(pv[k] - lv["bv"]) < ABS(pv[k0] - lv["bv"]) { SET k0 TO k. }
        }
      }
    } ELSE IF lv["vb"] >= 0 AND lv["vb"] < ASC_ARD_NEVER / 2 {
      SET vs TO lv["vb"].
      IF sh:HASKEY(lv["dk"]) { SET vs TO vs + sh[lv["dk"]]. }
    } ELSE IF S["seed"]:HASKEY(lv["dk"]) {
      SET vs TO S["seed"][lv["dk"]].
    }
    IF vs >= 0 {
      SET k0 TO n - 1.
      FROM { LOCAL k IS 0. } UNTIL k >= n STEP { SET k TO k + 1. } DO { IF pv[k] >= vs { SET k0 TO k - 1. BREAK. } }
      SET k0 TO MAX(0, MIN(k0, n - 2)).
    }
    SET S["k0s"][lv["key"]] TO LIST(k0, qk).
  }
}

// the next level (the soonest -- the least seek start of this refresh's levels not latched nor done, the list's
// order on a tie) and its seek; none left: the refresh is done (ok2 on 2 SSMEs), the rank, else the next snapshot
FUNCTION ard_lv_next {
  PARAMETER S.
  LOCAL L IS S["lv"].
  LOCAL bi IS -1.
  LOCAL bk IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= L:LENGTH STEP { SET i TO i + 1. } DO {
    LOCAL x IS L[i].
    IF NOT x["lat"] AND NOT S["dn"]:CONTAINS(x["key"]) AND S["k0s"]:HASKEY(x["key"]) {
      IF bi < 0 OR S["k0s"][x["key"]][0] < bk { SET bi TO i. SET bk TO S["k0s"][x["key"]][0]. }
    }
  }
  IF bi < 0 {
    SET S["li"] TO L:LENGTH.
    SET S["nref"] TO S["nref"] + 1.
    IF S["nrun"] = 2 { SET S["ok2"] TO TRUE. }
    IF ASC_ARD_RANK_ON AND S["tls"]:LENGTH > 0 AND S["pts"]:LENGTH > 0 { ard_rk_go(S). RETURN. }   // the site rank
    SET S["ph"] TO 0.
    RETURN.
  }
  SET S["li"] TO bi.
  S["dn"]:ADD(L[bi]["key"]).
  SET S["k0"] TO bk.
  SET S["kk"] TO bk.
  SET S["dir"] TO 0.
  SET S["rescan"] TO FALSE.
  SET S["q1"] TO S["k0s"][L[bi]["key"]][1].
  SET S["ms"] TO LEXICON().
  SET S["fk"] TO "m".
  LOCAL ky IS L[bi]["key"].                 // the PEG-estimate seek where it holds
  IF ASC_ARD_COARSE AND NOT S["q1"] AND (ASC_ARD_PE_B:HASKEY(ky) OR ky = "ATO" OR (ky = "ATO_2EO" AND S["nrun"] = 3)) {
    SET S["pe"] TO LEXICON().
    SET S["plo"] TO -1.
    SET S["phi"] TO -1.
    SET S["pit"] TO 0.
    IF ASC_ARD_PE_B:HASKEY(ky) { SET S["pb"] TO ASC_ARD_PE_B[ky]. }
    ELSE {
      LOCAL sn IS S["sn"].
      SET S["pb"] TO 0 - sn["m"]["vex"] * LN(1 + sn["res"] / (sn["mc"] - S["pts"][bk]["om"])).
    }
    SET S["fk"] TO "pe".
  }
}

// the seek after margin m at path point kk (ard2.crossing from a guess): a negative start forward to the first rise, a
// positive one back to the fall before it; "open" at the path's start, "never" at its end (a TAL once more from the
// start when the seek began later: its margin can close again near MECO, so a late start can miss the rise; PRESS and
// ATO margins only rise along the path); the margins found are kept, so a rescan re-flies none
FUNCTION ard_seek {
  PARAMETER S, m.
  LOCAL lv IS S["lv"][S["li"]].
  LOCAL n IS S["pts"]:LENGTH.
  UNTIL FALSE {
    LOCAL kk IS S["kk"].
    IF S["dir"] = 0 AND S["q1"] AND m < 0 { ard_lv_never(S, lv). RETURN. }   // the quick check still short
    IF S["dir"] = 0 { IF m < 0 { SET S["dir"] TO 1. } ELSE { SET S["dir"] TO -1. } }
    IF S["dir"] > 0 {
      IF m >= 0 {
        IF kk = 0 { ard_lv_open(S, lv). RETURN. }
        ard_bis_start(S, kk - 1, kk).
        RETURN.
      }
      IF kk >= n - 1 {
        IF S["k0"] > 0 AND NOT S["rescan"] AND lv["md"] = "TAL" {
          SET S["rescan"] TO TRUE.
          SET S["kk"] TO 0.
          SET S["dir"] TO 0.
        } ELSE {
          ard_lv_never(S, lv).
          RETURN.
        }
      } ELSE {
        SET S["kk"] TO kk + 1.
      }
    } ELSE {
      IF m < 0 { ard_bis_start(S, kk, kk + 1). RETURN. }
      IF kk = 0 { ard_lv_open(S, lv). RETURN. }
      SET S["kk"] TO kk - 1.
    }
    IF NOT S["ms"]:HASKEY(S["kk"]) { SET S["fk"] TO "m". RETURN. }
    SET m TO S["ms"][S["kk"]].
  }
}

// the PEG-estimate seek's next point (one estimate a call): short or not converged ->
// forward, by up to 4 points when the estimate is far short; good -> back the same way; once bracketed, halve to
// neighbours; then the boundary interpolated between them + the level's shift. "open" at the path's start, "never" at
// its end; no converged bracket after ASC_ARD_PE_IT steps: today's flown seek from the bracket's start
FUNCTION ard_pe_next {
  PARAMETER S.
  LOCAL lv IS S["lv"][S["li"]].
  LOCAL n IS S["pts"]:LENGTH.
  LOCAL B IS S["pb"].
  LOCAL sd IS ASC_ARD_PE_SD[lv["key"]].
  LOCAL k IS S["kk"].
  UNTIL S["pit"] >= ASC_ARD_PE_IT {
    IF NOT S["pe"]:HASKEY(k) { SET S["kk"] TO k. RETURN. }   // the next estimate: a job of its own
    LOCAL pev IS S["pe"][k][0].
    LOCAL cv IS S["pe"][k][1].
    IF NOT cv OR pev < B {
      SET S["plo"] TO k.
      IF k >= n - 1 { ard_lv_never(S, lv). RETURN. }
      LOCAL jj IS 1.
      IF cv { SET jj TO MAX(1, MIN(4, ROUND((B - pev) / (sd * 8)))). }
      SET k TO MIN(n - 1, k + jj).
    } ELSE {
      SET S["phi"] TO k.
      IF k = 0 { ard_lv_open(S, lv). RETURN. }
      SET k TO MAX(0, k - MAX(1, MIN(4, ROUND((pev - B) / (sd * 8))))).
    }
    SET S["pit"] TO S["pit"] + 1.
    IF S["plo"] >= 0 AND S["phi"] >= 0 {
      IF S["phi"] - S["plo"] = 1 { BREAK. }
      SET k TO FLOOR((S["plo"] + S["phi"]) / 2).
    }
  }
  LOCAL lo IS S["plo"].
  LOCAL hi IS S["phi"].
  IF lo < 0 OR hi < 0 OR hi - lo <> 1 OR NOT S["pe"][lo][1] {   // today's flown seek from here
    SET S["kk"] TO CHOOSE hi - 1 IF hi > 0 ELSE MAX(0, lo).
    SET S["dir"] TO 0.
    SET S["ms"] TO LEXICON().
    SET S["fk"] TO "m".
    RETURN.
  }
  LOCAL Pa IS S["pts"][lo].
  LOCAL Pb IS S["pts"][hi].
  LOCAL f IS (B - S["pe"][lo][0]) / (S["pe"][hi][0] - S["pe"][lo][0]).
  LOCAL sh IS 0.
  IF ASC_ARD_PE_TB:HASKEY(lv["key"]) { SET sh TO ASC_ARD_PE_TB[lv["key"]] / (Pb["t"] - Pa["t"]). }
  SET lv["tb"] TO Pa["t"] + (f + sh) * (Pb["t"] - Pa["t"]).
  SET lv["vb"] TO Pa["v"]:MAG + (f + sh) * (Pb["v"]:MAG - Pa["v"]:MAG).
  SET S["k0"] TO lo.
  ard_lv_end(S, lv, "").
}

// the bracket between path points ka (margin < 0) and kb (>= 0), then its bisections
FUNCTION ard_bis_start {
  PARAMETER S, ka, kb.
  SET S["Pa"] TO S["pts"][ka].
  SET S["Pb"] TO S["pts"][kb].
  SET S["ma"] TO S["ms"][ka].
  SET S["mb"] TO S["ms"][kb].
  SET S["nb"] TO 0.
  SET S["nbm"] TO CHOOSE ASC_ARD_NBIS_NEAR IF S["Pa"]["t"] - S["pts"][0]["t"] < ASC_ARD_NEAR ELSE ASC_ARD_NBIS.   // the bracket's bisections: more near now
  ard_bis_next(S).
}

// the next bisection (its middle's state first), else the boundary interpolated in the bracket (ard2.boundaries)
FUNCTION ard_bis_next {
  PARAMETER S.
  LOCAL lv IS S["lv"][S["li"]].
  IF S["nb"] < S["nbm"] AND lv["md"] <> "RTLS" { SET S["fk"] TO "sa". RETURN. }   // NEG RTN: linear in t (-0.64 t/s)
  LOCAL f IS S["ma"] / (S["ma"] - S["mb"]).
  SET lv["tb"] TO S["Pa"]["t"] + f * (S["Pb"]["t"] - S["Pa"]["t"]).
  SET lv["vb"] TO S["Pa"]["v"]:MAG + f * (S["Pb"]["v"]:MAG - S["Pa"]["v"]:MAG).
  ard_lv_end(S, lv, "").
}

FUNCTION ard_lv_open {                    // passed at the path's start: latched there
  PARAMETER S, lv.
  SET lv["tb"] TO S["pts"][0]["t"].
  SET lv["vb"] TO S["pts"][0]["v"]:MAG.
  SET lv["lat"] TO TRUE.
  ard_lv_end(S, lv, "open").
}

FUNCTION ard_lv_never {                   // no rise along the path: off the scale (the guess from the tables again)
  PARAMETER S, lv.
  SET lv["tb"] TO -1.
  SET lv["vb"] TO ASC_ARD_NEVER.
  IF S["q1"] { SET lv["nq"] TO lv["nq"] + 1. }   // a quick check; a full scan: its best margin's VI
  ELSE IF S["ms"]:LENGTH > 0 {
    LOCAL kb IS 0.
    LOCAL mx IS -1E30.
    FOR k IN S["ms"]:KEYS { IF S["ms"][k] > mx { SET mx TO S["ms"][k]. SET kb TO k. } }
    SET lv["bv"] TO S["pts"][kb]["v"]:MAG.
    SET lv["nq"] TO 0.
  }
  ard_lv_end(S, lv, "never").
}

FUNCTION ard_lv_end {                     // a level done: its note, its log line, the next level
  PARAMETER S, lv, nt.
  SET lv["note"] TO nt.
  SET lv["nc"] TO lv["nc"] + 1.
  S["msg"]:ADD(lv["key"] + "," + lv["tb"] + "," + lv["vb"] + "," + nt + "," + S["k0"] + "," + S["pts"]:LENGTH + ","
    + S["u"]).
  ard_lv_next(S).
}

// the boundaries into b (asc["abr"]["b"], m/s) at MET met: each level computed at its pages' key (TAL_2EO: the
// earliest site), a 2EO key with no level (not the selection's) off the scale; a level latched once met passes its
// boundary
// THE VI LATCH: a level is latched once the VI (vi, m/s) reaches its boundary VI, not once the MET reaches its
// predicted MET, so a craft slower than the I-loads has no pad boundary marked passed before a search in flight checked
// it (a faster one latches at its own VI). ASC_ARD_LATCH_VI FALSE or no vi given = the MET latch.
GLOBAL ASC_ARD_LATCH_VI IS TRUE.
FUNCTION ard_apply_b {
  PARAMETER S, b, met, vi IS -1.
  LOCAL byv IS ASC_ARD_LATCH_VI AND vi >= 0.
  IF S["lv"]:LENGTH = 0 { RETURN. }
  LOCAL tal IS -1.
  LOCAL has IS LIST().
  FOR x IN S["lv"] {
    IF byv { IF NOT x["lat"] AND x["vb"] >= 0 AND vi >= x["vb"] { SET x["lat"] TO TRUE. } }
    ELSE IF NOT x["lat"] AND x["tb"] >= 0 AND met >= x["tb"] { SET x["lat"] TO TRUE. }
    has:ADD(x["dk"]).
    IF x["vb"] >= 0 {
      IF x["dk"] = "TAL_2EO" { IF tal < 0 OR x["vb"] < tal { SET tal TO x["vb"]. } }
      ELSE { SET b[x["dk"]] TO x["vb"]. }
    }
  }
  IF tal >= 0 { SET b["TAL_2EO"] TO tal. }
  FOR k IN LIST("TAL_2EO", "ATO_2EO", "PRESS_2EO") { IF NOT has:CONTAINS(k) { SET b[k] TO ASC_ARD_NEVER. } }
}

// THE VERDICT (phase 4; the search's own phases stay off below 2 SSMEs): when a second SSME fails before the search
// has regenerated the boundaries after the first, the droop + OMS dump fly until this verdict says what to do: the 2EO
// levels the selection allows (ard_levels' rule on 2 SSMEs), best first -- PRESS, ATO, then TAL at each site in the
// site list's
// order -- each flown ONCE on its e SSMEs at the abort throttle from the state P (the search's margin at one point, no
// seek: ard_lv_job, ard_unit, ard_margin); the first with a margin >= 0 is the verdict (vd_ln its mode "PRESS" / "ATO"
// / "TAL", vd_st a TAL's site), none = "NONE". a: the snapshot on the SSME left (ard_lv_job takes its mc, res and m)
FUNCTION ard_vd_go {
  PARAMETER S, a, P, sel, site, tls.
  SET S["pj"] TO LEXICON().
  SET S["fj"] TO LEXICON().
  SET S["sn"] TO a.
  LOCAL L IS ard_levels(S, 2, sel, site, tls).
  LOCAL vl IS LIST().
  FOR dk IN LIST("PRESS_2EO", "ATO_2EO", "TAL_2EO") { FOR x IN L { IF x["dk"] = dk { vl:ADD(x). } } }
  SET S["vd_lv"] TO vl.
  SET S["vd_P"] TO P.
  SET S["vd_k"] TO 0.
  SET S["vd_j"] TO LEXICON().
  SET S["vd_ln"] TO "".
  SET S["vd_st"] TO "".
  SET S["ph"] TO 4.
}

// ONE UNIT of the verdict: the level's job (its start, or one of its units, and its margin)
FUNCTION ard_vd_unit {
  PARAMETER S.
  IF S["ph"] <> 4 { RETURN. }
  SET S["u"] TO S["u"] + 1.
  IF S["vd_k"] >= S["vd_lv"]:LENGTH { ard_vd_end(S, "NONE", ""). RETURN. }
  LOCAL lv IS S["vd_lv"][S["vd_k"]].
  IF S["vd_j"]:LENGTH = 0 { SET S["vd_j"] TO ard_lv_job(S, lv, S["vd_P"]). RETURN. }
  IF NOT ard_unit(S["vd_j"]) { RETURN. }
  LOCAL m IS ard_margin(S["vd_j"]).
  SET S["vd_j"] TO LEXICON().
  S["msg"]:ADD("VD," + lv["key"] + "," + m + "," + S["u"]).
  IF m >= 0 { ard_vd_end(S, lv["md"], lv["site"]). RETURN. }
  SET S["vd_k"] TO S["vd_k"] + 1.
}

FUNCTION ard_vd_end {                    // the verdict in: its line and site, the phase off
  PARAMETER S, lw, st.
  SET S["vd_ln"] TO lw.
  SET S["vd_st"] TO st.
  SET S["vd_j"] TO LEXICON().
  SET S["ph"] TO 3.
  S["msg"]:ADD("VD END," + lw + "," + st + "," + S["u"]).
}

// The TAL sites: only those in reach are listed (a short site is hidden), the least-dV one first, the crossrange as
// the backup; the TAL site can be switched after the abort is called.
// THE SITE RANK (phase 5), after a refresh's levels: each TAL site (S["tls"]) flown ONCE as a TAL on MIN(nrun, 2)
// SSMEs (on three: a first SSME out now, the case a TAL is called for) at the abort throttle from the snapshot's state
// (the path's first point; ard_lv_job, ard_unit, ard_margin: the most ET left at MECO = the least dV, >= 0 = reached);
// S["rk"][site] = LIST(the margin m/s, the snapshot's MET, the SSMEs), kept across a reset; then the next snapshot.
// ASC_ARD_RANK_ON FALSE: no rank (ops1q's lists then use the marks and the crossrange)
GLOBAL ASC_ARD_RANK_ON IS TRUE.

FUNCTION ard_rk_go {
  PARAMETER S.
  LOCAL ne IS MIN(S["nrun"], 2).
  LOCAL L IS LIST().
  FOR st IN S["tls"]:KEYS { L:ADD(ard_lv_new("TAL_RK_" + st, "TAL_RK", ne, "TAL", st, S["tls"][st])). }
  SET S["rk_l"] TO L.
  SET S["rk_k"] TO 0.
  SET S["rk_j"] TO LEXICON().
  SET S["ph"] TO 5.
}

// ONE UNIT of the rank: the site's job (its start, or one of its units, and its margin); all done: the next snapshot
FUNCTION ard_rk_unit {
  PARAMETER S.
  IF S["rk_k"] >= S["rk_l"]:LENGTH {
    SET S["rk_t"] TO S["t_ref"].
    S["msg"]:ADD("RK END," + S["u"]).
    SET S["ph"] TO 0.
    RETURN.
  }
  LOCAL lv IS S["rk_l"][S["rk_k"]].
  IF S["rk_j"]:LENGTH = 0 { SET S["rk_j"] TO ard_lv_job(S, lv, S["pts"][0]). RETURN. }
  IF NOT ard_unit(S["rk_j"]) { RETURN. }
  LOCAL m IS ard_margin(S["rk_j"]).
  SET S["rk_j"] TO LEXICON().
  SET S["rk"][lv["site"]] TO LIST(m, S["t_ref"], lv["e"]).
  S["msg"]:ADD("RK," + lv["site"] + "," + ROUND(m, 1) + "," + lv["e"] + "," + S["u"]).
  SET S["rk_k"] TO S["rk_k"] + 1.
}

// the levels as a log line: key:tb:vb:note:latched each
FUNCTION ard_srch_line {
  PARAMETER S.
  LOCAL txt IS "".
  FOR x IN S["lv"] {
    SET txt TO txt + "," + x["key"] + ":" + ROUND(x["tb"], 2) + ":" + ROUND(x["vb"], 1) + ":" + x["note"] + ":" + x["lat"].
  }
  RETURN txt.
}
