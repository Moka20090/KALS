// lib_ascent_peg.ks -- the second stage guidance of ops1q.ks: UPFG (FSSR 4.8.1, PEG A-1 .. A-22), ported from the
// offline sim's PEG (coast, abc_fit, PEG), and the inertial frame it flies in; the TAL target (subtask 15a, the offline
// sim's TAL PEG) and the RTLS mode (SMODE 5: subtasks 14, 17, 18, 19, the offline sim's RTLS PEG).
// THE FRAME: every vector given to or returned by asc_iyd, asc_coast and asc_peg_* is in ops1q's inertial frame, not
// kOS's raw one: right-handed, from the body's centre, z = the north pole, x = the prime meridian at liftoff (the
// offline sim's frame). In it VCRS is the right-handed cross product, as offline. asc_to_i and asc_to_raw convert.
@LAZYGLOBAL OFF.

// THE C# PEG. With ASC_PEG_CS on and the KAL/S addon installed with its PEG part (GameData/KALS_Coproc:
// ADDONS:KALS:PEGCYCLE), every pass of asc_peg_cycle (the flight's, the abort searches' PEG-estimate starts, the RTLS's)
// is flown by the addon's port of this file's code (coproc/Peg.cs through the bridge coproc/PegKos.cs): ~0.09 ms a pass
// instead of ~2.6 ms of kOS, one SYNCHRONOUS call, the lexicon p updated in place (the same lists, the same nested
// lexicons: the displays, the logs and the steering read it unchanged). Checked bit for bit against this file's own code
// run in kOS's VM (558 passes: nominal, TAL, RTLS). Never throws: an addon failure (a PEGCYCLE error string, p then
// untouched) turns it off for the rest of the flight and kOS (asc_peg_cycle_k, the code below) flies that pass and the
// rest (ASC_PEG_CS_ERR says why).
// FALSE / no addon / an older dll: this file's kOS PEG. (A kOS-VM test harness has no ADDONS: it defines GLOBAL
// ASC_PEG_CS IS FALSE before it loads this file.)
IF NOT (DEFINED ASC_PEG_CS) { GLOBAL ASC_PEG_CS IS TRUE. }
GLOBAL ASC_PEG_CS_ERR IS "".
GLOBAL ASC_PEG_CS_ON IS 0.               // the addon's availability, looked at once: 0 not yet, 1 set up, -1 not there
GLOBAL ASC_PEG_CS_HOLD IS FALSE.         // the addon flies the hidden TAL's hold (it has PEGHOLD); else those passes are kOS's
GLOBAL ASC_PEG_CS_AD IS 0.               // ADDONS:KALS once set up (cached: the dispatch runs inside the abort searches' loops)
GLOBAL ASC_PEG_CS_N IS 0.                // the passes the addon flew

// ---- the inertial frame. kOS's raw axes turn with the body below the inverse-rotation altitude and SOLARPRIMEVECTOR
// does not turn with them (lib_vehicle's fdSample), so the axes are rebuilt at each sample from three body-fixed
// points (lng 0 and lng 90 E on the equator, the north pole: no cross product, so no handedness) turned back by the
// body's rotation since t0 (the liftoff UT).
FUNCTION asc_frame_new {
  PARAMETER t0.
  RETURN LEXICON("t0", t0, "w", 360 / BODY:ROTATIONPERIOD).
}

// LIST(X, Y, Z): the inertial axes as raw unit vectors at UT ut. Sample within one physics tick (after a WAIT 0).
FUNCTION asc_frame_axes {
  PARAMETER fr, ut.
  LOCAL c0 IS BODY:POSITION.
  LOCAL e0 IS (LATLNG(0, 0):ALTITUDEPOSITION(0) - c0):NORMALIZED.
  LOCAL e9 IS (LATLNG(0, 90):ALTITUDEPOSITION(0) - c0):NORMALIZED.
  LOCAL th IS fr["w"] * (ut - fr["t0"]).
  RETURN LIST(e0 * COS(th) - e9 * SIN(th), e0 * SIN(th) + e9 * COS(th),
    (LATLNG(90, 0):ALTITUDEPOSITION(0) - c0):NORMALIZED).
}

// A raw vector's inertial components, and back.
FUNCTION asc_to_i {
  PARAMETER ax, u.
  RETURN V(VDOT(u, ax[0]), VDOT(u, ax[1]), VDOT(u, ax[2])).
}

FUNCTION asc_to_raw {
  PARAMETER ax, u.
  RETURN ax[0] * u:X + ax[1] * u:Y + ax[2] * u:Z.
}

// LIST(the axes, r, v) at UT ut: the position from the body's centre and the inertial velocity, both inertial.
FUNCTION asc_sample {
  PARAMETER fr, ut.
  LOCAL ax IS asc_frame_axes(fr, ut).
  RETURN LIST(ax, asc_to_i(ax, -BODY:POSITION), asc_to_i(ax, SHIP:VELOCITY:ORBIT)).
}

// ---- the target plane: PEG's IYD, minus the orbit's unit angular momentum. The plane holds the pad at liftoff (rp,
// inertial) on its northbound pass (southbound: ASC_LAUNCH_DIR -1) at inclination inc (a2's target_plane), turned east about the pole by dlng (a2's
// rotz). V(0, 0, 0) when there is no northbound pass (inc below the pad's latitude).
FUNCTION asc_iyd {
  PARAMETER rp, inc, dlng.
  LOCAL rh IS rp:NORMALIZED.
  LOCAL lam IS ARCTAN2(rh:Y, rh:X).
  LOCAL x IS -COS(inc) * TAN(ARCSIN(rh:Z)) / SIN(inc).
  LOCAL n IS V(0, 0, 0).
  IF ABS(x) <= 1 {
    FOR sgn IN LIST(1, -1) {
      LOCAL al IS lam + sgn * ARCCOS(x).
      LOCAL nn IS V(SIN(inc) * COS(al), SIN(inc) * SIN(al), COS(inc)).
      IF n:MAG = 0 AND VCRS(nn, rh):Z * ASC_LAUNCH_DIR > 0 { SET n TO nn. }
    }
  }
  RETURN -V(n:X * COS(dlng) - n:Y * SIN(dlng), n:X * SIN(dlng) + n:Y * COS(dlng), n:Z).
}

// ---- PEG's arithmetic
// the middle value of three (the FSSR's MIDVAL)
FUNCTION asc_mid {
  PARAMETER a, b, c.
  RETURN MAX(MIN(a, b), MIN(MAX(a, b), c)).
}

// The central-gravity coast over tc s (A-10's gravity terms): RK4 on the point mass at MIDVAL(DTMAX, DTMIN, tc / NSEG)
// steps, the last one cut to land on tc. LIST(r, v).
FUNCTION asc_coast {
  PARAMETER rr, vv, tc, mu.
  IF tc <= 0 { RETURN LIST(rr, vv). }
  LOCAL h IS asc_mid(ASC_DTMAX, ASC_DTMIN, tc / ASC_NSEG).
  LOCAL tt IS 0.
  UNTIL tt >= tc - 1e-9 {
    LOCAL hh IS MIN(h, tc - tt).
    LOCAL k1v IS -mu / rr:MAG ^ 3 * rr.
    LOCAL p2 IS rr + 0.5 * hh * vv.
    LOCAL k2r IS vv + 0.5 * hh * k1v.
    LOCAL k2v IS -mu / p2:MAG ^ 3 * p2.
    LOCAL p3 IS rr + 0.5 * hh * k2r.
    LOCAL k3r IS vv + 0.5 * hh * k2v.
    LOCAL k3v IS -mu / p3:MAG ^ 3 * p3.
    LOCAL p4 IS rr + hh * k3r.
    LOCAL k4r IS vv + hh * k3v.
    LOCAL k4v IS -mu / p4:MAG ^ 3 * p4.
    SET rr TO rr + hh / 6 * (vv + 2 * k2r + 2 * k3r + k4r).
    SET vv TO vv + hh / 6 * (k1v + 2 * k2v + 2 * k3v + k4v).
    SET tt TO tt + hh.
  }
  RETURN LIST(rr, vv).
}

// A-10's fit A + B t + C t^2 of the thrust acceleration over a constant-thrust phase: LIST(A, B, C).
FUNCTION asc_abc {
  PARAMETER TB, TI, TF, LA, SA, QA, JOL.
  LOCAL C IS 60 * (0.5 * TB * TB * LA + 3 * TI * SA - 3 * (QA - SA * JOL)) / TB ^ 5.
  LOCAL B IS 12 * (0.5 * TB * LA - SA) / TB ^ 3 - C * (TF + TI).
  RETURN LIST(LA / TB - 0.5 * B * (TF + TI) - C * (TB * TB / 3 + TI * TF), B, C).
}

// ---- PEG
// A new state: the MECO target (rdmag m, gamd deg, vdmag m/s), iyd (asc_iyd), mass_min (A-9's floor, in the mass
// units the passes give), mu. The phases are 1 (constant thrust) and 2 (the acceleration limit); index 0 is unused.
FUNCTION asc_peg_new {
  PARAMETER rdmag, gamd, vdmag, iyd, mass_min, mu.
  RETURN LEXICON("RDMAG", rdmag, "GAMD", gamd, "VDMAG", vdmag, "IYD", iyd, "MASS_MIN", mass_min, "mu", mu,
    "S_INIT", TRUE, "S_GDRDY", FALSE, "SCONV", FALSE, "N", 2, "TB", LIST(0, 0, 0), "TGOA", LIST(0, 0, 0),
    "TAU", LIST(0, 0, 0), "VEXA", LIST(0, 0, 0), "LA", LIST(0, 0, 0), "SA", LIST(0, 0, 0), "QA", LIST(0, 0, 0),
    "lamc", V(0, 0, 0), "lamdc", V(0, 0, 0), "tlamc", 0, "npass", 0, "unconv", 0, "low_tw", FALSE,
    "KPHASE", 1, "TGO", 1, "PHI", 0, "SALT", TRUE, "SPLANE", TRUE, "vgo", V(0, 0, 0),
    "upd", FALSE, "tp_ok", FALSE, "mass_ok", FALSE, "TAL", LEXICON(), "tnow", 0, "rnow", V(0, 0, 0),
    "vnow", V(0, 0, 0), "RTLS", LEXICON(), "Mnow", 0, "VEXnow", 0, "ATRnow", 0, "first", FALSE).
}

// ---- TAL (FSSR 4.8.1 subtask 15a): the site's target from the next pass on. tl = LEXICON("ef", the
// site at liftoff (inertial, m), "w", the body's rotation (deg/s), and the site's I-loads (lib_ascent_iload's ASC_TAL):
// "A", "VMIN", "VMAX", "CRMAX", "RDMAG", "GAMD").
FUNCTION asc_peg_tal {
  PARAMETER p, tl.
  SET p["TAL"] TO tl.
  SET p["RDMAG"] TO tl["RDMAG"].
  SET p["GAMD"] TO tl["GAMD"].
}

// u turned by th deg about the pole (a2's rotz)
FUNCTION asc_rotz {
  PARAMETER u, th.
  RETURN V(COS(th) * u:X - SIN(th) * u:Y, SIN(th) * u:X + COS(th) * u:Y, u:Z).
}

// The TAL velocity target, before A-15 (asc_peg_tgt): the cutoff speed from the range RTHETA to the site at TP (the
// I-loads' cubic between VMIN and VMAX); the plane the present orbit's while the site at the arrival (TP + RTHETA /
// VDMAG) lies within CRMAX of it, else the plane through the predicted cutoff and a point CRMAX short of the site.
FUNCTION asc_tal_vel {
  PARAMETER p.
  LOCAL tl IS p["TAL"].
  LOCAL ef IS tl["ef"].
  LOCAL tpp IS p["tnow"] + p["TGO"].
  IF p:HASKEY("TP") { SET tpp TO p["TP"]. }
  LOCAL rt IS asc_rotz(ef, tl["w"] * tpp).
  LOCAL rth IS ef:MAG * ARCCOS(MAX(-1, MIN(1, VDOT(p["ix"], rt:NORMALIZED)))) * CONSTANT:DEGTORAD.
  LOCAL ca IS tl["A"].
  SET p["VDMAG"] TO asc_mid(tl["VMIN"], ca[0] + rth * (ca[1] + rth * (ca[2] + rth * ca[3])), tl["VMAX"]).
  IF tl:HASKEY("hold") {                  // ops1q's hidden TAL (asc_dtal_hide): the speed above, the plane held on the surface
    SET p["SPLANE"] TO TRUE.             // iyef: the great circle of the surface velocity when the hold began (liftoff axes), turned with the body
    SET p["iy"] TO p["IYD"].
    IF tl:HASKEY("iyef") { SET p["iy"] TO asc_rotz(tl["iyef"], tl["w"] * tpp). }
    RETURN.
  }
  SET p["SPLANE"] TO FALSE.
  LOCAL tca IS rth / p["VDMAG"].
  LOCAL ra IS asc_rotz(ef, tl["w"] * (tpp + tca)).
  LOCAL iy IS VCRS(p["vnow"], p["rnow"]):NORMALIZED.
  LOCAL cr IS VDOT(ra, iy).
  IF ABS(cr) > tl["CRMAX"] {
    SET iy TO VCRS(p["vp"], p["rp"]):NORMALIZED.
    IF cr >= 0 { SET ra TO ra - tl["CRMAX"] * iy. } ELSE { SET ra TO ra + tl["CRMAX"] * iy. }
    SET iy TO VCRS(ra, p["rp"]):NORMALIZED.
  }
  SET p["iy"] TO iy.
  SET p["tal_rth"] TO rth.
  SET p["tal_cr"] TO cr.
  SET p["tal_tca"] TO tca.
}

// ---- RTLS (SMODE 5): p["RTLS"] = LEXICON("ef", the site at liftoff, "w" deg/s, "A", LIST(a0, a1)
// the PPD line, "RTMAG", |ef|, "iy_save", the first plane, "K", PEG's throttle (PL %), "K_CMD", the commanded one,
// "STHROT", the throttle loop on, "MBO", the burnout mass (t), "MDOT" (t/s at K_CMD), "KMIN", "KMAX", "DELK_MAX",
// "KMISS", "RNG_TURN_PRED") from the guidance (lib_ascent_rtls.ks); PEG writes "RTHETA", "close", "VGOD", "ERR", "ERR_C".
// Subtasks 14 + 17: the plane through the site at TP (the HAC correction omitted), RTHETA signed against the first
// plane, VDMAG on the PPD line, VD inertial (the earth rate x RD added), the plane from VD.
FUNCTION asc_rtls_vel {
  PARAMETER p.
  LOCAL rl IS p["RTLS"].
  LOCAL tpp IS p["tnow"] + p["TGO"].
  IF p:HASKEY("TP") { SET tpp TO p["TP"]. }
  LOCAL rt IS asc_rotz(rl["ef"], rl["w"] * tpp).
  LOCAL ix IS p["ix"].
  LOCAL iy IS VCRS(rt, p["rp"]):NORMALIZED.
  IF rl["iy_save"]:MAG = 0 { SET rl["iy_save"] TO iy. }
  LOCAL sv IS VDOT(iy, rl["iy_save"]).
  LOCAL sgn IS 0.
  IF sv > 0 { SET sgn TO 1. } ELSE IF sv < 0 { SET sgn TO -1. }
  LOCAL rth IS sgn * (rl["RTMAG"] * ix - rt):MAG.
  SET p["VDMAG"] TO rl["A"][0] + rl["A"][1] * rth.
  LOCAL vd IS p["VDMAG"] * (SIN(p["GAMD"]) * ix + COS(p["GAMD"]) * VCRS(ix, iy):NORMALIZED).
  SET p["vd"] TO vd + VCRS(V(0, 0, rl["w"] * CONSTANT:DEGTORAD), p["rd"]).
  SET p["iy"] TO VCRS(p["vd"], p["rd"]):NORMALIZED.
  SET rl["RTHETA"] TO rth.
  SET rl["close"] TO rth < rl["RNG_TURN_PRED"].
}

// Subtasks 18 + 19: VGO's correction through the RHO matrix, with PEG's throttle K (STHROT: K moves at most DELK_MAX a
// pass so that VGO meets VGOD, the burn to MBO); on the first pass the SMODE 5 estimate of VGO instead.
FUNCTION asc_rtls_correct {
  PARAMETER p.
  LOCAL rl IS p["RTLS"].
  LOCAL ix IS p["ix"].
  LOCAL iy IS p["iy"].
  LOCAL iz IS VCRS(ix, iy).
  SET p["vmiss"] TO p["vp"] - p["vd"].
  LOCAL ms IS p["Mnow"].
  LOCAL VEX IS p["VEXnow"].
  LOCAL VGOD IS VEX * LN(MAX(ms, rl["MBO"] * 1.000001) / rl["MBO"]).
  SET rl["VGOD"] TO VGOD.
  IF p["first"] {
    LOCAL gg IS p["mu"] / p["rnow"]:SQRMAGNITUDE.
    LOCAL md IS rl["MDOT"] * rl["K"] / rl["K_CMD"].
    LOCAL VGOR IS MAX(MIN(gg * (ms - rl["MBO"]) / md - VDOT(p["vnow"], ix), VGOD), -VGOD).
    SET p["vgo"] TO VGOR * ix + SQRT(MAX(0, VGOD * VGOD - VGOR * VGOR)) * iz.
    RETURN.
  }
  LOCAL vm IS p["vmiss"].
  LOCAL VM0 IS VDOT(vm, ix).
  LOCAL VM1 IS VDOT(vm, iy).
  LOCAL VM2 IS VDOT(vm, iz).
  LOCAL lam IS p["lam"].
  LOCAL LG0 IS VDOT(lam, ix).
  LOCAL LG1 IS VDOT(lam, iy).
  LOCAL LG2 IS VDOT(lam, iz).
  LOCAL VGOMAG IS p["vgo"]:MAG.
  LOCAL ATRF IS MIN(ASC_AL, p["ATRnow"] * CONSTANT:E ^ (VGOMAG / VEX)).
  LOCAL VGRAVX IS VDOT(p["vp"] - p["vnow"] - p["vthrust"], ix).
  LOCAL TGO IS p["TGO"].
  LOCAL B1 IS 1 + rl["A"][1] * (0.5 * TGO + VDOT(p["vnow"] + 0.5 * p["vgo"], iz) * LG2 / ATRF).
  LOCAL B2 IS 1 + VGRAVX * LG0 / (ATRF * TGO).
  LOCAL B3 IS 1 + p["VDMAG"] * TGO / (2 * MAX(rl["RTHETA"], 1)).
  IF ABS(LG0) < 1e-3 OR ABS(VGRAVX) < 1e-6 {
    // the degenerate geometry: the plain correction (a deviation)
    SET p["vgo"] TO p["vgo"] - vm.
    SET rl["ERR"] TO VGOMAG - VGOD.
    RETURN.
  }
  LOCAL KP IS rl["K"].
  LOCAL K IS KP.
  LOCAL B4 IS K / (VGRAVX * LG0).
  LOCAL B5 IS B4 * LG0 * VM0 + B4 * LG1 * B2 / B3 * VM1 + B4 * LG2 / B1 * VM2.
  IF rl["STHROT"] {
    LOCAL dk IS B5 - B4 * B2 * (VGOMAG - VGOD).
    IF dk < 0 { SET dk TO -MIN(rl["DELK_MAX"], -dk). } ELSE { SET dk TO MIN(rl["DELK_MAX"], dk). }
    SET K TO asc_mid(rl["KMIN"], KP + dk, rl["KMAX"]).
  }
  LOCAL ERR IS (B5 - (K - KP)) / (B4 * B2).
  LOCAL dg0 IS -((-LG1 / B3 / LG0) * VM1 + (-LG2 / B1 / LG0) * VM2 + ERR / LG0).
  SET p["vgo"] TO p["vgo"] + dg0 * ix - (VM1 / B3) * iy - (VM2 / B1) * iz.
  SET rl["K"] TO K.
  SET rl["ERR"] TO VGOMAG - VGOD.
  SET rl["ERR_C"] TO ERR.
}

// A-11, A-12, A-15, A-19, A-20: the desired position and velocity from the predicted ones (in the plane; the radius
// while SALT), the velocity miss and VGO's correction, the convergence test (cnt: count the unconverged passes).
FUNCTION asc_peg_tgt {
  PARAMETER p, cnt.
  LOCAL rtl IS p["RTLS"]:LENGTH > 0.
  IF rtl { SET p["SPLANE"] TO FALSE. }                    // "The plane constraint is not required for RTLS"
  IF p["SPLANE"] { SET p["rd"] TO p["rp"] - VDOT(p["rp"], p["iy"]) * p["iy"]. } ELSE { SET p["rd"] TO p["rp"]. }
  LOCAL ix IS p["rd"]:NORMALIZED.
  SET p["ix"] TO ix.
  IF p["SALT"] { SET p["rd"] TO p["RDMAG"] * ix. }
  LOCAL km IS ASC_KMISS.
  IF rtl {
    asc_rtls_vel(p).
    asc_rtls_correct(p).
    SET km TO p["RTLS"]["KMISS"].
  } ELSE {
    IF p["TAL"]:LENGTH > 0 { asc_tal_vel(p). }
    SET p["vd"] TO p["VDMAG"] * (SIN(p["GAMD"]) * ix + COS(p["GAMD"]) * VCRS(ix, p["iy"]):NORMALIZED).
    IF NOT p["SPLANE"] { SET p["iy"] TO VCRS(p["vd"], p["rd"]):NORMALIZED. }
    SET p["vmiss"] TO p["vp"] - p["vd"].
    SET p["vgo"] TO p["vgo"] - ASC_RHOMAG * p["vmiss"].
  }
  IF p["vmiss"]:MAG > km * p["vgo"]:MAG { SET p["SCONV"] TO FALSE. }
  IF cnt { IF p["SCONV"] { SET p["unconv"] TO 0. } ELSE { SET p["unconv"] TO p["unconv"] + 1. } }
}

// ---- the C# PEG's side. The addon is looked at once (the I-loads go over with PEGSETUP); a pass is the addon's, or kOS's.
FUNCTION asc_peg_cs_setup {
  SET ASC_PEG_CS_ON TO -1.
  LOCAL why IS "".
  IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
  ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
  ELSE IF NOT ADDONS:KALS:HASSUFFIX("PEGCYCLE") { SET why TO "the KAL/S addon has no PEG (an older KalsCoproc.dll)". }
  ELSE IF NOT ADDONS:KALS:PEGSETUP(LEXICON("ASC_DTMAX", ASC_DTMAX, "ASC_DTMIN", ASC_DTMIN, "ASC_NSEG", ASC_NSEG,
      "ASC_AL", ASC_AL, "ASC_ETB", ASC_ETB, "ASC_KMISS", ASC_KMISS, "ASC_RHOMAG", ASC_RHOMAG,
      "ASC_PHIDOT_MAX", ASC_PHIDOT_MAX, "ASC_RTLS_PHIDOT_MAX", ASC_RTLS_PHIDOT_MAX, "ASC_EPSTGO", ASC_EPSTGO,
      "ASC_DTRD", ASC_DTRD)) { SET why TO "PEGSETUP: " + ADDONS:KALS:PEGERROR. }
  IF why = "" {
    SET ASC_PEG_CS_AD TO ADDONS:KALS.
    SET ASC_PEG_CS_HOLD TO ADDONS:KALS:HASSUFFIX("PEGHOLD").
    SET ASC_PEG_CS_ON TO 1.
    RETURN.
  }
  SET ASC_PEG_CS_ERR TO why.
}

// One pass at MET t (the arguments: asc_peg_cycle_k's): the addon's when ASC_PEG_CS is on and it is there, else kOS's.
FUNCTION asc_peg_cycle {
  PARAMETER p, t, rr, vv, dvs, M, VEX, ATR.
  // an older addon's PEG does not know the hidden TAL's plane (the "hold" TAL): those passes are kOS's (not with PEGHOLD)
  IF ASC_PEG_CS AND (ASC_PEG_CS_HOLD OR NOT p["TAL"]:HASKEY("hold")) {
    IF ASC_PEG_CS_ON = 0 { asc_peg_cs_setup(). }
    IF ASC_PEG_CS_ON > 0 {
      LOCAL pa IS LIST(t, rr, vv, dvs, M, VEX, ATR).
      LOCAL cse IS ASC_PEG_CS_AD:PEGCYCLE(p, pa).
      IF cse = "" {
        SET ASC_PEG_CS_N TO ASC_PEG_CS_N + 1.
        RETURN.
      }
      SET ASC_PEG_CS_ERR TO cse.           // p untouched: kOS flies this pass and the rest
      SET ASC_PEG_CS TO FALSE.
    }
  }
  asc_peg_cycle_k(p, t, rr, vv, dvs, M, VEX, ATR).
}

// The kOS pass (the C# PEG's twin) at MET t: rr, vv the inertial state, dvs the sensed velocity change since the last pass, M the mass, VEX
// the exhaust speed, ATR the thrust acceleration. The result stays in p: TGO, vgo, lam, lamd; the steering's lamc,
// lamdc and tlamc when the pass passes A-9's tests.
FUNCTION asc_peg_cycle_k {
  PARAMETER p, t, rr, vv, dvs, M, VEX, ATR.
  SET p["npass"] TO p["npass"] + 1.
  SET p["upd"] TO FALSE. SET p["tp_ok"] TO FALSE. SET p["mass_ok"] TO FALSE.
  SET p["tnow"] TO t. SET p["rnow"] TO rr. SET p["vnow"] TO vv.
  SET p["Mnow"] TO M. SET p["VEXnow"] TO VEX. SET p["ATRnow"] TO ATR. SET p["first"] TO p["S_INIT"].
  LOCAL first IS p["S_INIT"].
  LOCAL rmag IS rr:MAG.
  LOCAL TBl IS p["TB"]. LOCAL TGOAl IS p["TGOA"]. LOCAL TAUl IS p["TAU"].
  LOCAL LAl IS p["LA"]. LOCAL SAl IS p["SA"]. LOCAL QAl IS p["QA"].
  LOCAL N IS p["N"].
  LOCAL K IS p["KPHASE"].
  IF first {
    // D-1, D-2, D-5: the first pass
    SET p["KPHASE"] TO 1. SET p["rbias"] TO V(0, 0, 0). SET p["PHI"] TO 0. SET p["TPRIME"] TO t. SET p["TGO"] TO 1.
    SET p["omega"] TO V(0, 0, 0). SET p["rgrav"] TO -0.5 * p["mu"] / rmag ^ 3 * rr. SET p["S_INIT"] TO FALSE.
    SET p["TPREV"] TO 0. SET p["SALT"] TO TRUE. SET p["SPLANE"] TO TRUE. SET p["iy"] TO p["IYD"].
    SET p["VEXA"] TO LIST(VEX, VEX, VEX).
    SET p["rp"] TO rr. SET p["vp"] TO vv. SET p["vgo"] TO V(0, 0, 0).
    asc_peg_tgt(p, FALSE).
  } ELSE {
    // A-3: the sensed velocity off VGO; the phase steps on when its burn time has run out
    SET p["vgo"] TO p["vgo"] - dvs.
    IF TBl[K] - (t - p["TPRIME"]) <= 0 AND K < N { SET TBl[K] TO 0. SET TGOAl[K] TO 0. SET p["KPHASE"] TO K + 1. }
    SET p["TPRIME"] TO t.
  }
  LOCAL VEXAl IS p["VEXA"].
  // A-4: the burn times (the constant-thrust phase to the acceleration limit, then the limited phase) and TGO
  LOCAL VGOMAG IS p["vgo"]:MAG.
  SET K TO p["KPHASE"].
  SET TAUl[K] TO VEX / ATR.
  SET VEXAl[K] TO VEX.
  LOCAL LREM IS VGOMAG.
  LOCAL ip IS 2.
  IF K < N { SET ip TO 1. }
  LOCAL TB1 IS TAUl[ip] - VEX / ASC_AL.
  LOCAL LA1 IS 0.
  IF TB1 <= ASC_ETB {
    SET TB1 TO 0. SET LA1 TO 0. SET p["KPHASE"] TO N. SET TGOAl[1] TO 0.
  } ELSE {
    SET LA1 TO -VEX * LN(1 - TB1 / TAUl[ip]).
  }
  IF TB1 > ASC_ETB AND p["KPHASE"] = N { SET p["KPHASE"] TO 1. SET TAUl[1] TO TAUl[2]. }
  LOCAL LA2 IS 0.
  LOCAL TB2 IS 0.
  IF LREM <= LA1 {
    SET LA1 TO LREM. SET TB1 TO TAUl[ip] * (1 - CONSTANT:E ^ (-LA1 / VEX)).
  } ELSE {
    SET LA2 TO LREM - LA1. SET TB2 TO LA2 / ASC_AL.
  }
  SET TBl[1] TO TB1. SET LAl[1] TO LA1. SET TBl[2] TO TB2. SET LAl[2] TO LA2.
  LOCAL acs IS 0.
  FROM { LOCAL i IS p["KPHASE"]. } UNTIL i > N STEP { SET i TO i + 1. } DO {
    SET acs TO acs + TBl[i]. SET TGOAl[i] TO acs.
  }
  SET p["TGOP"] TO p["TGO"].
  SET p["TGO"] TO TGOAl[N].
  SET p["TP"] TO t + p["TGO"].
  // A-5: the thrust integrals
  LOCAL L IS 0. LOCAL J IS 0. LOCAL S IS 0. LOCAL QQ IS 0.
  FROM { LOCAL i IS p["KPHASE"]. } UNTIL i > N STEP { SET i TO i + 1. } DO {
    LOCAL TGOB IS 0.
    IF i <> 1 { SET TGOB TO TGOAl[i - 1]. }
    LOCAL TBi IS TBl[i]. LOCAL LAi IS LAl[i].
    LOCAL SA IS 0. LOCAL QA IS 0.
    IF i < N {
      SET SA TO -LAi * (TAUl[i] - TBi) + VEXAl[i] * TBi.
      SET QA TO SA * (TAUl[i] + TGOB) - 0.5 * VEXAl[i] * TBi * TBi.
    } ELSE {
      SET SA TO 0.5 * LAi * TBi.
      SET QA TO SA * (TGOB + TBi / 3).
    }
    SET SAl[i] TO SA. SET QAl[i] TO QA.
    SET S TO S + (SA + L * TBi). SET QQ TO QQ + (QA + J * TBi). SET L TO L + LAi. SET J TO J + (LAi * TGOAl[i] - SA).
  }
  IF L <= 0 OR VGOMAG <= 0 { RETURN. }
  LOCAL JOL IS J / L.
  LOCAL QPRIME IS QQ - S * JOL.
  LOCAL TLAM IS t + JOL.
  SET p["S"] TO S. SET p["L"] TO L. SET p["J"] TO J. SET p["Q"] TO QQ. SET p["JOL"] TO JOL. SET p["QPRIME"] TO QPRIME.
  // A-6, A-7: the thrust direction, the gravity and bias terms, the position to go
  LOCAL lam IS (1 / VGOMAG) * p["vgo"].
  SET p["rgrav"] TO (p["TGO"] / p["TGOP"]) ^ 2 * p["rgrav"].
  LOCAL rgo IS p["rd"] - (rr + p["TGO"] * vv + p["rgrav"]) + p["rbias"].
  LOCAL ix IS p["ix"].
  LOCAL iy IS p["iy"].
  LOCAL rgop IS V(0, 0, 0).
  IF NOT (p["SALT"] AND p["SPLANE"]) { SET rgop TO QPRIME * VCRS(p["omega"], lam) + S * lam. }
  LOCAL RGOX IS VDOT(rgop, ix).
  IF p["SALT"] { SET RGOX TO VDOT(rgo, ix). }
  LOCAL RGOY IS VDOT(rgop, iy).
  IF p["SPLANE"] { SET RGOY TO VDOT(rgo, iy). }
  LOCAL rgoxy IS RGOX * ix + RGOY * iy.
  LOCAL iz IS VCRS(ix, iy).
  LOCAL lamz IS VDOT(lam, iz).   // The divisor is 0 when the thrust direction is exactly radial (the RTLS first-pass VGO estimate): floor it, never crash the program
  IF ABS(lamz) < 1e-12 { IF lamz < 0 { SET lamz TO -1e-12. } ELSE { SET lamz TO 1e-12. } }
  LOCAL RGOZ IS (S - VDOT(lam, rgoxy)) / lamz.
  SET rgo TO rgoxy + RGOZ * iz.
  // A-8: the turning rate and its limits (the convergence and low thrust tests)
  LOCAL lamd IS (1 / QPRIME) * (rgo - S * lam).
  LOCAL LAMDMAG IS lamd:MAG.
  LOCAL lx2 IS VDOT(lam, ix) ^ 2.
  LOCAL EL_LIMIT IS 1e30.
  IF lx2 > 1e-24 { SET EL_LIMIT TO SQRT(MAX(0, 1 / lx2 - 1)) / JOL. }
  // the RTLS's own turning-rate limit: the FSSR's 2 deg/s ends the convergence before the turnaround on this lighter
  // vehicle
  LOCAL phdm IS ASC_PHIDOT_MAX.
  IF p["RTLS"]:LENGTH > 0 {
    SET phdm TO ASC_RTLS_PHIDOT_MAX.
    SET EL_LIMIT TO phdm.   // SMODE 5 thrusts retrograde: no elevation limit
  }
  LOCAL DTA_LIMIT IS (0.5 + p["PHI"]) / JOL.
  SET p["SCONV"] TO NOT (LAMDMAG > phdm OR LAMDMAG > DTA_LIMIT).
  SET p["low_tw"] TO LAMDMAG > EL_LIMIT.
  LOCAL LAMDMAX IS MIN(phdm, MIN(DTA_LIMIT, EL_LIMIT)).
  IF LAMDMAG > LAMDMAX {
    SET lamd TO (LAMDMAX / LAMDMAG) * lamd. SET LAMDMAG TO LAMDMAX. SET rgo TO S * lam + QPRIME * lamd.
  }
  SET p["PHI"] TO JOL * LAMDMAG.
  SET p["lam"] TO lam. SET p["lamd"] TO lamd. SET p["LAMDMAG"] TO LAMDMAG. SET p["TLAM"] TO TLAM.
  // A-9: the steering update when TP holds and the mass lasts
  SET p["mass_ok"] TO M * CONSTANT:E ^ (-VGOMAG / VEX) > p["MASS_MIN"].
  SET p["tp_ok"] TO ABS(p["TP"] - p["TPREV"]) < ASC_EPSTGO * p["TGO"].
  SET p["upd"] TO p["tp_ok"] AND p["mass_ok"].
  IF p["upd"] { SET p["lamc"] TO lam. SET p["lamdc"] TO lamd. SET p["tlamc"] TO TLAM. SET p["S_GDRDY"] TO TRUE. }
  SET p["TPREV"] TO p["TP"].
  // A-10: the thrust's position and velocity, phase by phase
  LOCAL rth IS V(0, 0, 0).
  LOCAL vth IS V(0, 0, 0).
  LOCAL TI IS -JOL.
  LOCAL IFI IS SQRT(1 + LAMDMAG * LAMDMAG * TI * TI).
  LOCAL JJ IS N - 1.
  IF LAl[N] <> 0 { SET JJ TO N. }
  FROM { LOCAL i IS p["KPHASE"]. } UNTIL i > JJ STEP { SET i TO i + 1. } DO {
    LOCAL TBi IS TBl[i]. LOCAL LAi IS LAl[i]. LOCAL SA IS SAl[i]. LOCAL QA IS QAl[i].
    LOCAL TF IS TI + TBi.
    LOCAL IFF IS SQRT(1 + LAMDMAG * LAMDMAG * TF * TF).
    SET rth TO rth + TBi * vth.
    IF LAMDMAG * TBi < 0.090 {
      LOCAL gf IS 1 / SQRT(1 + LAMDMAG * LAMDMAG * ABS(TF * TF + TI * TF + TI * TI) / 3).
      SET rth TO rth + gf * (SA * lam + (QA - SA * JOL) * lamd).
      SET vth TO vth + gf * (LAi * lam + (LAi * TGOAl[i] - SA - LAi * JOL) * lamd).
    } ELSE {
      LOCAL abc IS LIST(ASC_AL, 0, 0).
      IF i <> N { SET abc TO asc_abc(TBi, TI, TF, LAi, SA, QA, JOL). }
      LOCAL Yl IS LIST(0, LN(ABS((TF * LAMDMAG + IFF) / (TI * LAMDMAG + IFI))) / LAMDMAG,
        (TF * TF - TI * TI) / (IFI + IFF), 0, 0, 0).
      LOCAL Mx IS LIST(0, 0, 0, 0).
      FOR xk IN LIST(1, 2, 3) {
        SET Yl[xk + 2] TO (IFF * TF ^ xk - IFI * TI ^ xk - xk * Yl[xk]) / ((xk + 1) * LAMDMAG * LAMDMAG).
        SET Mx[xk] TO abc[0] * Yl[xk] + abc[1] * Yl[xk + 1] + abc[2] * Yl[xk + 2].
      }
      SET rth TO rth + (TF * Mx[1] - Mx[2]) * lam + (TF * Mx[2] - Mx[3]) * lamd.
      SET vth TO vth + Mx[1] * lam + Mx[2] * lamd.
    }
    SET TI TO TF.
    SET IFI TO IFF.
  }
  // A-10 .. A-20: the bias, the gravity coast, the predicted state, the new target and VGO
  SET p["rbias"] TO rgo - rth.
  LOCAL TGO IS p["TGO"].
  LOCAL r_init IS rr - 0.1 * rth - (TGO / 30) * vth.
  LOCAL v_init IS vv + (1.2 / TGO) * rth - 0.1 * vth.
  LOCAL cf IS asc_coast(r_init, v_init, TGO, p["mu"]).
  SET p["rgrav"] TO cf[0] - r_init - TGO * v_init.
  SET p["rp"] TO rr + TGO * vv + p["rgrav"] + rth.
  SET p["vp"] TO vv + (cf[1] - v_init) + vth.
  SET p["rthrust"] TO rth.
  SET p["vthrust"] TO vth.
  asc_peg_tgt(p, TRUE).
  // A-22: the radius and the plane released at DTRD (sooner once converged inside it); omega = lam x lamd from here
  IF (p["SALT"] OR p["SPLANE"]) AND ((p["SCONV"] AND TGO < ASC_DTRD) OR (TGO < ASC_DTRD - 6 AND NOT first)) {
    SET p["omega"] TO VCRS(lam, lamd). SET p["SALT"] TO FALSE. SET p["SPLANE"] TO FALSE.
  }
}

// The thrust direction at MET t (the steering): lamc turning at lamdc from tlamc; hold until the first good pass.
FUNCTION asc_peg_dir {
  PARAMETER p, t, hold.
  IF NOT p["S_GDRDY"] { RETURN hold. }
  RETURN (p["lamc"] + (t - p["tlamc"]) * p["lamdc"]):NORMALIZED.
}

// ---- THE REPLAY HOOK: the target line, the CSV header and one line per pass, the inputs in full and the outputs
// the offline replay compares (opc: the pass's cost in opcodes, measured by the caller with asc_opc_mark / since).
FUNCTION asc_peg_init {
  PARAMETER p.
  RETURN "#peg," + p["RDMAG"] + "," + p["GAMD"] + "," + p["VDMAG"] + asc_csv_v(p["IYD"]) + "," + p["MASS_MIN"] + ","
    + p["mu"].
}

FUNCTION asc_peg_head {
  RETURN "pass,t,rx,ry,rz,vx,vy,vz,dvx,dvy,dvz,M,VEX,ATR,TGO,vgox,vgoy,vgoz,lamcx,lamcy,lamcz,lamdcx,lamdcy,lamdcz,"
    + "tlamc,conv,KPHASE,SALT,ready,upd,unconv,opc".
}

FUNCTION asc_csv_v {
  PARAMETER u.
  RETURN "," + u:X + "," + u:Y + "," + u:Z.
}

FUNCTION asc_csv_b {
  PARAMETER b.
  IF b { RETURN ",1". }
  RETURN ",0".
}

FUNCTION asc_peg_line {
  PARAMETER p, t, rr, vv, dvs, M, VEX, ATR, opc.
  RETURN "" + p["npass"] + "," + t + asc_csv_v(rr) + asc_csv_v(vv) + asc_csv_v(dvs) + "," + M + "," + VEX + "," + ATR
    + "," + p["TGO"] + asc_csv_v(p["vgo"]) + asc_csv_v(p["lamc"]) + asc_csv_v(p["lamdc"]) + "," + p["tlamc"]
    + asc_csv_b(p["SCONV"]) + "," + p["KPHASE"] + asc_csv_b(p["SALT"]) + asc_csv_b(p["S_GDRDY"])
    + asc_csv_b(p["upd"]) + "," + p["unconv"] + "," + opc.
}

// The opcode cost of a stretch of code: mark before, since after (the ticks crossed at CONFIG:IPU each, 0.02 s apart).
FUNCTION asc_opc_mark {
  RETURN LIST(TIME:SECONDS, OPCODESLEFT).
}

FUNCTION asc_opc_since {
  PARAMETER mk.
  RETURN mk[1] - OPCODESLEFT + ROUND((TIME:SECONDS - mk[0]) / 0.02) * CONFIG:IPU.
}
