// lib_ascent_css.ks  --  CSS in the ascent (OPS 1), the GRTLS's way: selectable on the pad, flown from liftoff through
// MECO and the hand-off (below); the buttons on the left of TRAJ's two rows. PITCH and ROLL/YAW each AUTO or CSS
// (lib_ascdisp's toggles, pressed = CSS). In CSS the stick out of its detent commands a body rate; back in the detent
// the attitude it left is held; the guidance (the stage-1 tables, PEG) keeps running and the pages' errors keep showing
// its target. The stick is ADDONS:KALS:FBWPILOT (the gimbal readback), the commands go through ADDONS:KALS:FBW3 (the
// handler runs after AFBW and kOS: nothing else writes the axes), as lib_grdap.
// A STICK AXIS (the stick out of its detent, or back in it before the hold catches) servos to the stick's rate the
// same way in both laws (ascCssSh): a reference rate runs to the stick's at most ASC_CSS_AF of the axis's modelled
// authority (ASC_CSS_TF's tail onto it), its acceleration is fed forward through the input, and the rate loop
// (ASC_CSS_TC) closes on the model's response (the reference through the gimbals' lag ASC_CSS_TG), so the lag makes no
// overshoot; the integrator (the trim) is held while the axis flies the stick. In stage 2 the roll / yaw stick axes
// turn about the SSMEs' thrust axis (ascCssCoup), as the guidance's heads-up roll does. The modelled authority is FBWAUTH x
// ascCss["ks"] per axis: ASC_CSS_AUTH_KS with the ET on, the free orbiter's ASC_CSS_AUTH_KSO from ETCLR. AUTO pitch under
// ROLL/YAW CSS keeps the vehicle's own roll: its error is the stick's roll axis's pointing error alone, so the guidance's
// roll moves no pitch. Back in the detent the reference brakes
// the same way onto the hold frame's own turn (ascCssFm: the nose stops in the frame, in stage 1 on the airflow, not
// against the stars), and the hold catches once the axis's rate in that frame is damped. Roll in the detent while
// yawing holds the roll from the vertical (ascCssHyRate). The holds and the AUTO axes fly as below.
// Two laws, by what flies when CSS is asked for:
//   Law A (lib_ascent_dap off: stage 1, a nominal stage 2, flown by the C# ascent DAP (ops1q asc["csd"]) or, without
//     it, by kOS's cooked steering): this library's own per-axis rate loops (lib_grdap's P + I on FBWAUTH), the
//     steering unlocked and the C# DAP let go (FBW3 has the axes; ops1q's asc_csd_want is false under Law A); the
//     integrators start at the last command (FBWCTRL), so the switch is bumpless. Both axes back to AUTO: this law
//     flies back to the guidance's attitude (at most ASC_CSS_WAUTO deg/s) and, once within ASC_CSS_RET_DEG, hands it
//     to the C# DAP (ops1q arms it again) or the steering.
//   Law B (lib_ascent_dap flies: an SSME out, the RTLS, the contingency): that DAP's mixer flies on, its CSS axes'
//     wanted rates from the stick or the hold (ascCssWd; the stick's roll / yaw about the thrust axis and across it, as
//     Law A's), its output through FBW3 instead of the raw controls.
// CSS flies on through MECO, the ET SEP and the hand-off's hold (Law A once the EO DAP stops at MECO), in the stage-2
// frame; ops1q waits until the crew has aligned with the hand-off's attitude before OPS 6 starts (asc_ho_css_ok) and
// hands the axes on (ASC_HO css_p / css_r).
// The split-S: Law A from its loft in stage 1 through its sep and sequence (S1CSEP / S1CSEQ, the stage-1 frame and
// rates), there with both axes AUTO too (the sequence's DAP on the RCS and the surfaces, no return to kOS's steering:
// the crew's CSS axes from the stick, the AUTO axes on the sequence's attitude), CSS again in OPS 6's SPLITS.
// The OMS (AJ10) gimbals are unlocked at ASC_CSS_OMS_LIM % while CSS flies: the stick's readback with one SSME left.
// A deviation (the real Shuttle's numbers not found): the rate limits, the detent, the shaping are this vehicle's.
// Names: asc-prefixed copies of lib_dap's / lib_grdap's helpers (ops6q loads those later in the same program context,
// where kOS keeps the first definition).
@LAZYGLOBAL OFF.

GLOBAL ASC_CSS_ALLOW IS TRUE.        // FALSE: no CSS in the ascent (the buttons grey)
GLOBAL ASC_CSS_RHC IS 19.5.          // deg: the RHC at a full input (lib_dap RHC_FULL)
GLOBAL ASC_CSS_DB IS 1.2.            // deg: the detent (lib_dap's 1.15 pitch / 1.25 roll)
GLOBAL ASC_CSS_EXP IS 1.5.           // the rate's shape past the detent
GLOBAL ASC_CSS_EXP2P IS 2.5.         // stage 2's pitch: softer near the centre
GLOBAL ASC_CSS_QMAX1 IS 10.           // deg/s: pitch and yaw at a full stick, stage 1 (the dynamic pressure)
GLOBAL ASC_CSS_QMAX IS 15.            // deg/s: pitch and yaw, stage 2
GLOBAL ASC_CSS_YMAX1 IS 10 / 3.       // deg/s: yaw, stage 1 (a third of pitch)
GLOBAL ASC_CSS_YMAX IS 5.            // deg/s: yaw, stage 2
GLOBAL ASC_CSS_CAP_W IS 0.3.         // deg/s: a hold is caught once its axis turns slower than this in its frame...
GLOBAL ASC_CSS_CAP_T IS 2.           // s: ...or this long after the stick came back (the rate damped first)
GLOBAL ASC_CSS_HY_ON IS 1.           // 1: roll in the detent while yawing holds the roll from the vertical (0: off)
GLOBAL ASC_CSS_HY_W IS 2.            // deg/s: that hold catches once the roll turns slower than this
GLOBAL ASC_CSS_HY_VMIN IS 10.        // deg: not with the nose within this of the vertical (no roll from it there)
GLOBAL ASC_CSS_RMAX IS 25.            // deg/s: roll (ASC_ROLL_RATE's)
GLOBAL ASC_CSS_KA IS 0.625.          // 1/s: the hold's attitude gain (lib_ascent_dap's wn / (2 zeta))
GLOBAL ASC_CSS_WAUTO IS 2.           // deg/s: the hold's and the return's rates at most (ASC_DAP_WMAX)
GLOBAL ASC_CSS_RET_DEG IS 1.         // deg: the return hands the steering back within this...
GLOBAL ASC_CSS_RET_W IS 0.3.         // deg/s: ...and this of the target's rate
GLOBAL ASC_CSS_RET_T IS 30.          // s: or after this
GLOBAL ASC_CSS_T IS 0.5.             // s: Law A's rate loops' time constant
GLOBAL ASC_CSS_LO_T IS 2.          // s: a Law A start this early in the flight starts untrimmed
GLOBAL ASC_CSS_TI IS 1.5.            // s: their integral time (GRD_TI)
GLOBAL ASC_CSS_IMAX IS 0.8.          // the integral's limit (the trim: the SRBs' and the SSMEs' offsets)
GLOBAL ASC_CSS_AMIN IS 0.5.          // deg/s2: the authority's floor
GLOBAL ASC_CSS_AUTH_K IS 1.0.        // FBWAUTH's share taken
GLOBAL ASC_CSS_AUTH_KS IS 0.5.       // FBWAUTH's share a stick axis's model takes (flown: 0.4-0.8 of it reached)
// the free orbiter's (ETCLR, HOPREP, OMS2PLAN): pitch, roll, yaw (flown on the RCS: 2.07 / 0.28-0.68 / 1.74-1.95 x FBWAUTH)
GLOBAL ASC_CSS_AUTH_KSO IS LIST(2.0, 0.5, 1.7).
GLOBAL ASC_CSS_TC IS 0.25.           // s: a stick axis's rate loop
GLOBAL ASC_CSS_AF IS 0.6.            // a stick axis's reference: its acceleration at most, x the modelled authority
GLOBAL ASC_CSS_TF IS 0.15.           // s: the reference's tail onto the stick's rate
GLOBAL ASC_CSS_TG IS 0.1.            // s: the gimbals' lag in the model (KSP's gimbal response speed 10)
GLOBAL ASC_CSS_AUTH_N IS 5.          // ticks between the authority's reads
GLOBAL ASC_CSS_KIB IS 2.5.           // 1/s2: Law B's trim integral while a CSS axis flies the stick (ASC_DAP_KI's 0.3 elsewhere); 0: frozen as before
GLOBAL ASC_CSS_IWMAX IS 0.8.         // rad/s: that integral's limit (x ASC_DAP_KI = the trim acceleration at most)
GLOBAL ASC_CSS_WARP_KT IS 0.15.      // gain x tick at most (GRD_WARP_KT: physics warp)
GLOBAL ASC_CSS_FF_TAU IS 0.5.        // s: the guidance target's rate, filtered (fed forward in Law A's AUTO axes)
GLOBAL ASC_CSS_OMS_LIM IS 1.         // %: the OMS gimbals' limit while CSS flies
GLOBAL ASC_CSS_LOG_EVERY IS 2.       // ticks between csv rows (25 Hz)
GLOBAL ASC_CSS_FLUSH IS 25.          // rows between writes
// Law A's roll / yaw (ascCssCoup, each pass): in stage 2 the stick's roll turns about the SSMEs' thrust axis (ops1q's
// asc["tbe"], the axis the guidance's heads-up roll turns about) and its yaw about the axis across it in the nose-top
// plane, so a roll input alone keeps the thrust on its heading (no rudder); elsewhere both about the nose (stage 1:
// the thrust within 2 deg of it). The roll and yaw commands then take out the actuators' cross-coupling (on this stack
// a yaw command rolls and a roll command yaws): nry the roll acceleration per unit yaw command over the roll's per unit
// roll command, nyr the yaw acceleration per unit roll command over the yaw's per unit yaw command (the roll in the
// LEFT sense), fitted on the CSS flights' body accelerations (the command through a first-order lag): stage 1 (the SRBs
// on) one pair; stage 2 linear in the mass between two fits, flat outside; past MECO none (the RCS)
GLOBAL ASC_CSS_TB_ON IS 1.           // 1: stage 2's stick roll / yaw about the thrust axis (0: the nose)
GLOBAL ASC_CSS_DC_ON IS 1.           // 1: the cross-coupling taken out (0: off)
GLOBAL ASC_CSS_DC_RY1 IS 0.08.       // stage 1: nry
GLOBAL ASC_CSS_DC_YR1 IS -0.80.      //   nyr
GLOBAL ASC_CSS_DC_M0 IS 103.3.       // t: stage 2's lighter fit's mass
GLOBAL ASC_CSS_DC_RY0 IS 0.54.       //   nry
GLOBAL ASC_CSS_DC_YR0 IS -0.35.      //   nyr
GLOBAL ASC_CSS_DC_M2 IS 135.6.       // t: its heavier fit's mass
GLOBAL ASC_CSS_DC_RY2 IS 1.05.       //   nry
GLOBAL ASC_CSS_DC_YR2 IS -0.27.      //   nyr
// the keyboard mode (lib_dap's KB_* values): a key's 0 / 1 builds like a stick
GLOBAL ASC_CSS_KB_MODE IS 1.
GLOBAL ASC_CSS_KB_FULL IS 1.0.
GLOBAL ASC_CSS_KB_RISE IS 0.5.
GLOBAL ASC_CSS_KB_MIN IS 0.5.
GLOBAL ASC_CSS_KB_TAP IS 0.25.
GLOBAL ASC_CSS_KB_STEPS IS 1.
GLOBAL ASC_CSS_KB_STICK_T IS 0.5.

// the state, fresh at every load (a stopped run's must not fly on)
GLOBAL ascCss IS LEXICON("on", FALSE, "law", "", "cp", FALSE, "cr", FALSE, "hpOn", FALSE, "hrOn", FALSE,
  "hp", SHIP:FACING, "hr", SHIP:FACING, "i", LIST(0, 0, 0), "t", 0, "n", 0, "auth", LIST(0, 0, 0), "ret", FALSE,
  "rt0", 0, "tgt", SHIP:FACING, "tgp", SHIP:FACING, "tgt_t", -1, "wf", V(0, 0, 0), "stk", LIST(0, 0, 0),
  "oms", LIST(), "s1", TRUE, "u", LIST(0, 0, 0), "csv", "", "buf", "", "bufn", 0, "log_t", 0,
  "asc", LEXICON(), "kb", LIST(LIST(FALSE, 0, 0, 0, 0, 0, 0, 0), LIST(FALSE, 0, 0, 0, 0, 0, 0, 0), LIST(FALSE, 0, 0, 0, 0, 0, 0, 0)),
  "sh", LIST(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), "lbA", V(0, 0, 0), "lbOn", LIST(FALSE, FALSE, FALSE),
  "fmw", V(0, 0, 0), "fmd", SHIP:FACING, "fmT", 0, "fmk", -1, "fmOn", FALSE,
  "hy", SHIP:FACING, "hyOn", FALSE, "hyw", V(0, 0, 0), "hyd", SHIP:FACING, "hyT", 0, "tb", LIST(1, 0), "dc", LIST(0, 0),
  "tb3", V(0, 0, 1), "ks", LIST(ASC_CSS_AUTH_KS, ASC_CSS_AUTH_KS, ASC_CSS_AUTH_KS)).

FUNCTION ascCssAvail {
  IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
  RETURN ADDONS:KALS:HASSUFFIX("FBW3").
}

FUNCTION ascCssClip {
  PARAMETER x, m.
  RETURN MAX(-m, MIN(m, x)).
}

// the rotation from the frame (fv, tv, sv) to D (rad: the sine along the axis; the VCRS / ANGULARVEL sense)
FUNCTION ascCssErr {
  PARAMETER fv, tv, sv, d.
  RETURN (VCRS(fv, d:FOREVECTOR) + VCRS(tv, d:TOPVECTOR) + VCRS(sv, d:STARVECTOR)) * 0.5.
}

// a stick input (-1..1) to a rate (deg/s): 0 in the detent, max at a full stick, ex its shape
FUNCTION ascCssShape {
  PARAMETER g, mx, ex.
  LOCAL x IS ABS(g) * ASC_CSS_RHC - ASC_CSS_DB.
  IF x <= 0 { RETURN 0. }
  LOCAL s IS mx * MIN(1, x / (ASC_CSS_RHC - ASC_CSS_DB)) ^ ex.
  IF g < 0 { RETURN -s. }
  RETURN s.
}

// the keyboard mode (lib_dap kbAxis, its own state): a key's 0 / 1 builds like a stick; the raw input for a stick
// A TRUE ATTITUDE HOLD: a hold keeps the attitude it caught relative to a moving frame (stage 1: the velocity vector,
// holding alpha, phi and beta; stage 2: the surface, holding the angle above the horizon and the roll, and the
// sideslip for yaw), its target rebuilt from the frame each tick:
//   1 (stage 1): the surface velocity's, LOOKDIRUP(Vsurf, UP): alpha, beta and the bank about the velocity (phi);
//   2 (stage 2): the local horizon along the inertial velocity's track, LOOKDIRUP(VXCL(UP, Vorb), UP): the nose's
//     angle above the horizon, the roll from the vertical and the heading off the track (the sideslip: the velocity
//     is near level);
//   0: inertial, in stage 1 while the flight path is steeper than ASC_CSS_GAM_MAX or the speed under ASC_CSS_V_MIN
//     (the bank about the velocity has no meaning near the vertical).
// A change of frame (0 -> 1, SRB SEP's 1 -> 2) re-bases the hold on the target it had, so nothing jumps. The frame's
// turn (the gravity turn's), filtered as ascCssTgt's, is fed forward in the held axes.
GLOBAL ASC_CSS_GAM_MAX IS 80.          // deg
GLOBAL ASC_CSS_V_MIN IS 100.           // m/s

FUNCTION ascCssFrame {
  PARAMETER k.
  IF k = 1 { RETURN LOOKDIRUP(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR). }
  IF k = 2 { RETURN LOOKDIRUP(VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:ORBIT), SHIP:UP:VECTOR). }
  RETURN R(0, 0, 0).
}

FUNCTION ascCssKind {
  IF NOT ascCss["s1"] { RETURN 2. }
  LOCAL vs IS SHIP:VELOCITY:SURFACE.
  IF vs:MAG < ASC_CSS_V_MIN OR VANG(vs, SHIP:UP:VECTOR) < 90 - ASC_CSS_GAM_MAX { RETURN 0. }
  RETURN 1.
}

FUNCTION ascCssCapOk {                  // the stick back in the detent: the hold's catch once the rate is damped
  PARAMETER k, wa.
  IF NOT ascCss:HASKEY(k) { SET ascCss[k] TO -1. }
  IF ascCss[k] < 0 { SET ascCss[k] TO TIME:SECONDS. }
  RETURN wa < ASC_CSS_CAP_W OR TIME:SECONDS - ascCss[k] > ASC_CSS_CAP_T.
}

FUNCTION ascCssCatch {                  // a hold caught (h "hp" / "hr"): the facing in its frame
  PARAMETER h.
  LOCAL k IS ascCssKind().
  SET ascCss[h] TO ascCssFrame(k):INVERSE * SHIP:FACING.
  SET ascCss[h + "k"] TO k.
  SET ascCss[h + "t"] TO 0.
  SET ascCss[h + "w"] TO ascCss["fmw"].      // the frame's turn, already learned (ascCssFm)
}

FUNCTION ascCssHeld {                   // a hold's target now; its frame's turn (deg/s, VCRS sense) to ascCss[h + "w"]
  PARAMETER h.
  LOCAL k IS ascCssKind().
  IF k <> ascCss[h + "k"] {
    LOCAL d0 IS ascCssFrame(ascCss[h + "k"]) * ascCss[h].
    SET ascCss[h] TO ascCssFrame(k):INVERSE * d0.
    SET ascCss[h + "k"] TO k.
  }
  LOCAL d IS ascCssFrame(k) * ascCss[h].
  LOCAL t IS TIME:SECONDS.
  IF ascCss[h + "t"] > 0 AND t > ascCss[h + "t"] {
    LOCAL dt IS t - ascCss[h + "t"].
    LOCAL p IS ascCss[h + "d"].
    LOCAL raw IS ascCssErr(p:FOREVECTOR, p:TOPVECTOR, p:STARVECTOR, d) * (57.2958 / dt).
    IF raw:MAG < 20 { SET ascCss[h + "w"] TO ascCss[h + "w"] + (raw - ascCss[h + "w"]) * MIN(1, dt / ASC_CSS_FF_TAU). }
  }
  IF t > ascCss[h + "t"] {
    SET ascCss[h + "d"] TO d.
    SET ascCss[h + "t"] TO t.
  }
  RETURN d.
}

FUNCTION ascCssFf {                     // a hold's frame turn along ax (deg/s), 0 while the stick flies the axis
  PARAMETER h, ax.
  IF NOT ascCss[h + "On"] { RETURN 0. }
  RETURN VDOT(ascCss[h + "w"], ax).
}

// THE HOLD FRAME'S TURN, learned every tick (deg/s, VCRS sense, filtered as a hold's): an axis back in the detent and
// not yet caught follows it, the catch tests the rates less it, and a hold caught starts with it fed forward
FUNCTION ascCssFm {
  LOCAL k IS ascCssKind().
  LOCAL d IS ascCssFrame(k).
  LOCAL t IS TIME:SECONDS.
  IF k = ascCss["fmk"] AND ascCss["fmT"] > 0 AND t > ascCss["fmT"] {
    LOCAL dt IS t - ascCss["fmT"].
    LOCAL p IS ascCss["fmd"].
    LOCAL raw IS ascCssErr(p:FOREVECTOR, p:TOPVECTOR, p:STARVECTOR, d) * (57.2958 / dt).
    IF raw:MAG < 20 { SET ascCss["fmw"] TO ascCss["fmw"] + (raw - ascCss["fmw"]) * MIN(1, dt / ASC_CSS_FF_TAU). }
  }
  IF t > ascCss["fmT"] {
    SET ascCss["fmd"] TO d.
    SET ascCss["fmT"] TO t.
    SET ascCss["fmk"] TO k.
  }
  RETURN ascCss["fmw"].
}

// THE ROLL HOLD WHILE YAWING (roll in the detent, yaw out of it): the roll from the vertical about the nose, kept as
// caught, so a yaw keeps the vehicle heads down (or at whatever roll it had)
FUNCTION ascCssHyCatch {
  LOCAL f IS SHIP:FACING.
  SET ascCss["hy"] TO LOOKDIRUP(f:FOREVECTOR, SHIP:UP:VECTOR):INVERSE * f.
  SET ascCss["hyT"] TO 0.
  SET ascCss["hyw"] TO V(0, 0, 0).
  SET ascCss["hyOn"] TO TRUE.
}

FUNCTION ascCssHyRate {                 // its roll rate (deg/s, LEFT): back onto the held roll, the roll the yaw turns fed forward
  PARAMETER kcw.
  LOCAL f IS SHIP:FACING.
  IF VANG(f:FOREVECTOR, SHIP:UP:VECTOR) < ASC_CSS_HY_VMIN { RETURN 0. }
  LOCAL d IS LOOKDIRUP(f:FOREVECTOR, SHIP:UP:VECTOR) * ascCss["hy"].
  LOCAL t IS TIME:SECONDS.
  IF ascCss["hyT"] > 0 AND t > ascCss["hyT"] {
    LOCAL dt IS t - ascCss["hyT"].
    LOCAL p IS ascCss["hyd"].
    LOCAL raw IS ascCssErr(p:FOREVECTOR, p:TOPVECTOR, p:STARVECTOR, d) * (57.2958 / dt).
    IF raw:MAG < 20 { SET ascCss["hyw"] TO ascCss["hyw"] + (raw - ascCss["hyw"]) * MIN(1, dt / ASC_CSS_FF_TAU). }
  }
  IF t > ascCss["hyT"] {
    SET ascCss["hyd"] TO d.
    SET ascCss["hyT"] TO t.
  }
  LOCAL e IS ascCssErr(f:FOREVECTOR, f:TOPVECTOR, f:STARVECTOR, d).
  RETURN ascCssClip(VDOT(e, f:FOREVECTOR) * 57.2958 * ASC_CSS_KA * kcw, ASC_CSS_WAUTO) + VDOT(ascCss["hyw"], f:FOREVECTOR).
}

// the stick axes' rate targets for ascCssSh (deg/s: nose up, LEFT, nose right): the stick's; an axis back in the
// detent and not yet caught, the hold frame's turn (ascCssFm); roll in the detent while yawing, its hold's
FUNCTION ascCssTg {
  PARAMETER stk, kcw.
  LOCAL f IS SHIP:FACING.
  LOCAL fw IS ascCss["fmw"].
  LOCAL tq IS stk[0].
  IF tq = 0 { SET tq TO VDOT(fw, f:STARVECTOR * -1). }
  LOCAL tp IS 0 - stk[1].
  LOCAL tr IS stk[2].
  IF stk[1] = 0 AND stk[2] = 0 {
    SET tp TO VDOT(fw, f:FOREVECTOR).
    SET tr TO VDOT(fw, f:TOPVECTOR).
  } ELSE IF stk[1] = 0 AND ascCss["hyOn"] {
    SET tp TO ascCssHyRate(kcw).
  }
  RETURN LIST(tq, tp, tr).
}

FUNCTION ascCssKb {
  PARAMETER i, raw.
  IF ASC_CSS_KB_MODE = 0 { RETURN raw. }
  LOCAL s IS ascCss["kb"][i].
  LOCAL tn IS TIME:SECONDS.
  LOCAL dt IS 0.
  IF s[3] > 0 { SET dt TO MAX(0, MIN(0.2, tn - s[3])). }
  SET s[3] TO tn.
  LOCAL a IS ABS(raw).
  LOCAL atStop IS a < 0.0001 OR ABS(a - 1) < 0.0001.
  IF atStop AND ABS(raw - s[2]) > 0.9 { SET s[4] TO s[4] + 1. SET s[5] TO 0. }
  IF NOT atStop { SET s[5] TO s[5] + dt. }
  SET s[2] TO raw.
  IF ASC_CSS_KB_MODE = 1 {
    IF NOT s[0] AND s[4] >= ASC_CSS_KB_STEPS { SET s[0] TO TRUE. SET s[5] TO 0. }
    IF s[0] AND s[5] > ASC_CSS_KB_STICK_T { SET s[0] TO FALSE. SET s[4] TO 0. SET s[7] TO 0. SET s[1] TO 0. }
    IF NOT s[0] {
      SET s[5] TO MIN(s[5], ASC_CSS_KB_STICK_T).
      RETURN raw.
    }
  }
  LOCAL sg IS 0.
  IF a >= 0.5 { SET sg TO CHOOSE 1 IF raw > 0 ELSE -1. }
  IF sg <> 0 {
    IF sg <> s[7] {
      SET s[6] TO tn.
      SET s[7] TO sg.
      SET s[1] TO sg * ASC_CSS_KB_MIN.
    } ELSE {
      SET s[1] TO sg * MIN(ASC_CSS_KB_FULL, ABS(s[1]) + (ASC_CSS_KB_FULL - ASC_CSS_KB_MIN) / ASC_CSS_KB_RISE * dt).
    }
  } ELSE IF s[7] = 0 OR tn - s[6] >= ASC_CSS_KB_TAP {
    SET s[7] TO 0.
    SET s[1] TO 0.
  }
  RETURN s[1].
}

// the stick's rates (deg/s: + = nose up, RIGHT roll, nose right) in the CSS axes (0 in an AUTO axis); each axis's
// hold taken once as the stick comes back into the detent (ROLL/YAW: both in it)
FUNCTION ascCssStick {
  LOCAL raw IS ADDONS:KALS:FBWPILOT().
  LOCAL qm IS CHOOSE ASC_CSS_QMAX1 IF ascCss["s1"] ELSE ASC_CSS_QMAX.
  LOCAL ym IS CHOOSE ASC_CSS_YMAX1 IF ascCss["s1"] ELSE ASC_CSS_YMAX.
  LOCAL w IS SHIP:ANGULARVEL * 57.2958.   // deg/s
  LOCAL f IS SHIP:FACING.
  LOCAL wl IS w - ascCssFm().              // the rates in the hold's frame
  LOCAL sq IS 0.
  LOCAL sr IS 0.
  LOCAL sy IS 0.
  LOCAL gp IS ascCssKb(0, raw[0]).
  LOCAL gr IS ascCssKb(1, raw[1]).
  LOCAL gy IS ascCssKb(2, raw[2]).
  IF ascCss["cp"] {
    SET sq TO ascCssShape(gp, qm, CHOOSE ASC_CSS_EXP IF ascCss["s1"] ELSE ASC_CSS_EXP2P).
    IF sq <> 0 { SET ascCss["hpOn"] TO FALSE. SET ascCss["hpT"] TO -1. }
    ELSE IF NOT ascCss["hpOn"] AND ascCssCapOk("hpT", ABS(VDOT(wl, f:STARVECTOR))) {
      SET ascCss["hpOn"] TO TRUE.
      ascCssCatch("hp").
    }
  }
  IF ascCss["cr"] {
    SET sr TO ascCssShape(gr, ASC_CSS_RMAX, ASC_CSS_EXP).
    SET sy TO ascCssShape(gy, ym, ASC_CSS_EXP).
    IF sr <> 0 OR sy <> 0 {
      SET ascCss["hrOn"] TO FALSE.
      SET ascCss["hrT"] TO -1.
      IF sr <> 0 OR ASC_CSS_HY_ON = 0 { SET ascCss["hyOn"] TO FALSE. }
      ELSE IF NOT ascCss["hyOn"] AND ABS(VDOT(w, f:FOREVECTOR)) < ASC_CSS_HY_W { ascCssHyCatch(). }
    } ELSE {
      SET ascCss["hyOn"] TO FALSE.
      IF NOT ascCss["hrOn"] AND ascCssCapOk("hrT", MAX(ABS(VDOT(wl, f:FOREVECTOR)), ABS(VDOT(wl, f:TOPVECTOR)))) {
        SET ascCss["hrOn"] TO TRUE.
        ascCssCatch("hr").
      }
    }
  }
  SET ascCss["stk"] TO LIST(sq, sr, sy).
  RETURN ascCss["stk"].
}

// one axis's command: P + I, clamped to +-1, the integral frozen at the clamp (lib_grdap grdPI)
FUNCTION ascCssPI {
  PARAMETER i, er, kc, dt.
  LOCAL ii IS ascCss["i"].
  LOCAL uu IS er * kc + ii[i].
  IF NOT (ABS(uu) >= 1 AND uu * er > 0) { SET ii[i] TO ascCssClip(ii[i] + er * kc * dt / ASC_CSS_TI, ASC_CSS_IMAX). }
  RETURN ascCssClip(er * kc + ii[i], 1).
}

// a stick axis's command: the feed-forward and the rate loop (x), the integral (the trim) running on the rate error er
// (ascCssPI's clamp), so the hold starts with the trim the stick flew with
FUNCTION ascCssPS {
  PARAMETER i, x, er, kc, dt.
  LOCAL ii IS ascCss["i"].
  LOCAL uu IS x + ii[i].
  IF NOT (ABS(uu) >= 1 AND uu * er > 0) { SET ii[i] TO ascCssClip(ii[i] + er * kc * dt / ASC_CSS_TI, ASC_CSS_IMAX). }
  RETURN ascCssClip(x + ii[i], 1).
}

// a stick axis j's reference (deg/s; tg the stick's rate, wn the rate now, am the modelled authority deg/s2 per unit
// input): ascCss["sh"][5j ..] = on, the reference, the model's rate, its lagged acceleration, the last acceleration; the
// reference's acceleration out
FUNCTION ascCssSh {
  PARAMETER j, tg, wn, am, dt.
  LOCAL s IS ascCss["sh"].
  LOCAL b IS 5 * j.
  IF s[b] = 0 {
    SET s[b] TO 1.
    SET s[b + 1] TO wn.
    SET s[b + 2] TO wn.
    SET s[b + 3] TO 0.
    SET s[b + 4] TO 0.
  }
  LOCAL ar IS ascCssClip((tg - s[b + 1]) / ASC_CSS_TF, ASC_CSS_AF * am).
  SET s[b + 1] TO s[b + 1] + ar * dt.
  SET s[b + 3] TO s[b + 3] + (s[b + 4] - s[b + 3]) * MIN(1, dt / ASC_CSS_TG).
  SET s[b + 4] TO ar.
  SET s[b + 2] TO s[b + 2] + s[b + 3] * dt.
  RETURN ar.
}

FUNCTION ascCssShOff {                  // axis j not a stick axis: its reference starts again from the rate next time
  PARAMETER j.
  IF ascCss["sh"][5 * j] <> 0 { SET ascCss["sh"][5 * j] TO 0. }
}

FUNCTION ascCssShReset {                // a new law: every reference off
  SET ascCss["sh"] TO LIST(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0).
  SET ascCss["lbOn"] TO LIST(FALSE, FALSE, FALSE).
}

// the OMS gimbals: unlocked at ASC_CSS_OMS_LIM % while CSS flies (the stick's readback), as they were after
FUNCTION ascCssOms {
  PARAMETER on.
  IF on {
    IF ascCss["oms"]:LENGTH > 0 { RETURN. }
    FOR eng IN SHIP:ENGINES {
      IF eng:HASMODULE("ModuleGimbal") AND (eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering")
                                            OR eng:TITLE:CONTAINS("Viking")) {
        LOCAL m IS eng:GETMODULE("ModuleGimbal").
        LOCAL lim0 IS -1.
        IF m:HASFIELD("gimbal limit") { SET lim0 TO m:GETFIELD("gimbal limit"). m:SETFIELD("gimbal limit", ASC_CSS_OMS_LIM). }
        ascCss["oms"]:ADD(LIST(eng, m, eng:GIMBAL:LOCK, lim0)).
        SET eng:GIMBAL:LOCK TO FALSE.
      }
    }
  } ELSE {
    FOR o IN ascCss["oms"] {
      IF o[3] >= 0 AND o[1]:HASFIELD("gimbal limit") { o[1]:SETFIELD("gimbal limit", o[3]). }
      SET o[0]:GIMBAL:LOCK TO o[2].
    }
    SET ascCss["oms"] TO LIST().
  }
}

// each main-loop pass: the guidance's target and its rate (deg/s, world, filtered)
FUNCTION ascCssTgt {
  PARAMETER d.
  LOCAL t IS TIME:SECONDS.
  IF ascCss["tgt_t"] > 0 AND t > ascCss["tgt_t"] {
    LOCAL dt IS t - ascCss["tgt_t"].
    LOCAL p IS ascCss["tgp"].
    LOCAL raw IS ascCssErr(p:FOREVECTOR, p:TOPVECTOR, p:STARVECTOR, d) * (57.2958 / dt).
    IF raw:MAG < 20 { SET ascCss["wf"] TO ascCss["wf"] + (raw - ascCss["wf"]) * MIN(1, dt / ASC_CSS_FF_TAU). }
  }
  SET ascCss["tgp"] TO d.
  SET ascCss["tgt"] TO d.
  SET ascCss["tgt_t"] TO t.
}

// each pass (ascCssMode): Law A's stick roll / yaw axes (ascCss["tb"]: the thrust axis's cosine and sine from the nose
// in the nose-top plane, + toward the top; 1 / 0 the nose), the axis itself (ascCss["tb3"]: body star, top, fore; Law B's
// stick roll axis and the current roll's), the stick axes' share of FBWAUTH (ascCss["ks"]: pitch, roll, yaw) and the
// cross-coupling taken out (ascCss["dc"]: nry, nyr)
FUNCTION ascCssCoup {
  PARAMETER asc, ph.
  LOCAL tb IS V(0, 0, 1).
  IF ASC_CSS_TB_ON = 1 AND ph = "STAGE2" AND asc:HASKEY("tbe") { SET tb TO asc["tbe"]. }
  LOCAL tbN IS SQRT(tb:Y * tb:Y + tb:Z * tb:Z).
  SET ascCss["tb"] TO LIST(tb:Z / tbN, tb:Y / tbN).
  SET ascCss["tb3"] TO tb:NORMALIZED.
  IF ph = "ETCLR" OR ph = "HOPREP" OR ph = "OMS2PLAN" { SET ascCss["ks"] TO ASC_CSS_AUTH_KSO. }
  ELSE { SET ascCss["ks"] TO LIST(ASC_CSS_AUTH_KS, ASC_CSS_AUTH_KS, ASC_CSS_AUTH_KS). }
  LOCAL dcL IS LIST(0, 0).
  IF ASC_CSS_DC_ON = 1 AND (ph = "PAD" OR ph = "STAGE1") { SET dcL TO LIST(ASC_CSS_DC_RY1, ASC_CSS_DC_YR1). }
  ELSE IF ASC_CSS_DC_ON = 1 AND (ph = "SRBSEP" OR ph = "STAGE2") {
    LOCAL dcF IS MIN(1, MAX(0, (SHIP:MASS - ASC_CSS_DC_M0) / (ASC_CSS_DC_M2 - ASC_CSS_DC_M0))).
    SET dcL TO LIST(ASC_CSS_DC_RY0 + (ASC_CSS_DC_RY2 - ASC_CSS_DC_RY0) * dcF, ASC_CSS_DC_YR0 + (ASC_CSS_DC_YR2 - ASC_CSS_DC_YR0) * dcF).
  }
  SET ascCss["dc"] TO dcL.
}

// the arbiter, each main-loop pass: the buttons' wishes (wp, wr) -> the axes, the law, the start, the return; RETURNS
// LIST(ok, cp, cr): ok FALSE greys the buttons (and AUTO is forced)
FUNCTION ascCssMode {
  PARAMETER asc, wp, wr.
  SET ascCss["asc"] TO asc.
  LOCAL ph IS asc["phase"].
  LOCAL ok IS ASC_CSS_ALLOW AND asc["pg"] AND (ph = "PAD" OR ph = "STAGE1" OR ph = "SRBSEP" OR ph = "S1CSEP"
    OR ph = "S1CSEQ" OR ph = "STAGE2" OR ph = "MECO" OR ph = "ETSEP" OR ph = "ETCLR" OR ph = "HOPREP"
    OR ph = "OMS2PLAN")   // on past MECO
    AND (asc["s1c"]:LENGTH = 0 OR ph = "STAGE1" OR ph = "S1CSEP" OR ph = "S1CSEQ")   // the split-S: to its sequence's end
    AND ascCssAvail().
  // the loop's last pass runs here with the phase DONE; CSS stays as it is for ops1q's end (its css_c for OPS 6, then
  // ascCssStop END), so it carries into OPS 6
  IF ph = "DONE" { RETURN LIST(TRUE, ascCss["cp"], ascCss["cr"]). }
  IF NOT ok { SET wp TO FALSE. SET wr TO FALSE. }
  IF DEFINED FLFX_SWPROG {              // SW 01 AUTO DAP LOST (ASCENT): both axes CSS (the stick flies them)
    IF flfxSwAutoLost("ASCENT", "ASCENT") { SET wp TO TRUE. SET wr TO TRUE. }     // Or SW 02 ASCENT held DAP_GD_LOST_S
  }
  // past MECO the stage-2 frame; the split-S's sep and sequence keep stage 1's (the airflow's, its rates)
  SET ascCss["s1"] TO ph = "PAD" OR ph = "STAGE1" OR ph = "SRBSEP" OR ph = "S1CSEP" OR ph = "S1CSEQ".
  ascCssCoup(asc, ph).
  IF wp <> ascCss["cp"] {
    SET ascCss["cp"] TO wp.
    SET ascCss["hpOn"] TO FALSE.
    asc_note(asc, "CSS PITCH " + (CHOOSE "CSS" IF wp ELSE "AUTO")).
  }
  IF wr <> ascCss["cr"] {
    SET ascCss["cr"] TO wr.
    SET ascCss["hrOn"] TO FALSE.
    SET ascCss["hyOn"] TO FALSE.
    asc_note(asc, "CSS ROLL/YAW " + (CHOOSE "CSS" IF wr ELSE "AUTO")).
  }
  // the split-S's sep and sequence: Law A flies them with both axes AUTO too (no return to kOS's steering)
  LOCAL sqOn IS asc["s1c"]:LENGTH > 0 AND (ph = "S1CSEP" OR ph = "S1CSEQ").
  LOCAL want IS wp OR wr OR sqOn.
  IF NOT ok {
    IF ascCss["on"] { ascCssStop(asc, "OFF (" + ph + ")"). }
    RETURN LIST(FALSE, FALSE, FALSE).
  }
  IF ph = "PAD" { RETURN LIST(TRUE, wp, wr). }   // selectable before launch: flown from liftoff
  IF want AND NOT ascCss["on"] { ascCssStart(asc). }
  IF NOT ascCss["on"] { RETURN LIST(TRUE, wp, wr). }
  SET ascCss["ret"] TO NOT want.
  IF want { SET ascCss["rt0"] TO TIME:SECONDS. }
  // the law follows what flies: lib_ascent_dap (an SSME out, the RTLS) or kOS's steering
  IF ascDap["on"] AND ascCss["law"] <> "B" {
    SET ascCss["law"] TO "B".                // Law A's trigger ends on its next tick
    ascCssShReset().
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.     // a raw value left would read as the stick
    SET ascDap["fbw"] TO TRUE.
    SET ascDap["css"] TO TRUE.
    asc_note(asc, "CSS LAW B (THE EO DAP)").
  } ELSE IF NOT ascDap["on"] AND ascCss["law"] <> "A" {
    ascCssStartA(asc).
  }
  IF ascCss["law"] = "B" AND NOT want {      // Law B: the DAP flies back itself (ASC_DAP_WMAX), raw again
    ascCssStop(asc, "AUTO").
  }
  IF asc["log"] <> "" AND TIME:SECONDS >= ascCss["log_t"] {
    SET ascCss["log_t"] TO TIME:SECONDS + 1.
    LOG "#css," + asc_met_of(asc) + "," + ascCss["law"] + "," + ascCss["cp"] + "," + ascCss["cr"] + "," + ascCss["hpOn"] + ","
      + ascCss["hrOn"] + "," + ROUND(ascCss["stk"][0], 2) + "," + ROUND(ascCss["stk"][1], 2) + "," + ROUND(ascCss["stk"][2], 2)
      + "," + ROUND(ascCss["u"][0], 3) + "," + ROUND(ascCss["u"][1], 3) + "," + ROUND(ascCss["u"][2], 3) + ","
      + ROUND(ascCss["i"][0], 3) + "," + ROUND(ascCss["i"][1], 3) + "," + ROUND(ascCss["i"][2], 3) TO asc["log"].
    LOG "#cssdc," + asc_met_of(asc) + "," + ROUND(ascCss["tb"][0], 4) + "," + ROUND(ascCss["tb"][1], 4) + ","
      + ROUND(ascCss["dc"][0], 3) + "," + ROUND(ascCss["dc"][1], 3) + "," + ROUND(SHIP:MASS, 2) TO asc["log"].
  }
  RETURN LIST(TRUE, ascCss["cp"], ascCss["cr"]).
}

FUNCTION ascCssStart {
  PARAMETER asc.
  SET ascCss["on"] TO TRUE.
  SET ascCss["law"] TO "".
  SET ascCss["ret"] TO FALSE.
  SET ascCss["rt0"] TO TIME:SECONDS.
  ascCssShReset().
  ascCssOms(TRUE).
  SET ascCss["csv"] TO "".
  IF asc["log"] <> "" {
    IF NOT EXISTS("0:/logs") { CREATEDIR("0:/logs"). }
    LOCAL tg IS "" + ROUND(TIME:SECONDS, 0).
    LOCAL n IS 2.
    UNTIL NOT EXISTS("0:/logs/asccss_" + tg + ".csv") { SET tg TO ROUND(TIME:SECONDS, 0) + "_" + n. SET n TO n + 1. }
    SET ascCss["csv"] TO "0:/logs/asccss_" + tg + ".csv".
    LOG "t,met,law,q_kpa,css_p,css_r,hold_p,hold_r,stk_p,stk_r,stk_y,qc,pc,rc,q,p,r,e_p,e_r,e_y,u_p,u_r,u_y,i_p,i_r,i_y,"
      + "auth_p,auth_r,auth_y,ret" TO ascCss["csv"].
  }
  SET ascCss["buf"] TO "".
  SET ascCss["bufn"] TO 0.
  asc_note(asc, "CSS ON" + (CHOOSE ": LOG " + ascCss["csv"] IF ascCss["csv"] <> "" ELSE "")).
}

// Law A: the steering off, this library's loops on (bumpless: the integrators at the steering's last command)
FUNCTION ascCssStartA {
  PARAMETER asc.
  LOCK STEERING TO SHIP:FACING.   // the lock known to this file, so the UNLOCK below compiles to the release
  UNLOCK STEERING.
  IF DEFINED STEER_UNLOCKS { FOR u IN STEER_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } } }   // live runs' locks (STEER_UNLOCKS)
  SET asc["relock"] TO FALSE.
  LOCAL c0 IS LIST(0, 0, 0).
  IF ADDONS:KALS:HASSUFFIX("FBWCTRL") { SET c0 TO ADDONS:KALS:FBWCTRL(). }
  // from a pad selection the steering never flew (the pad's gimbals locked: its output wound up to -1 pitch), and at
  // the split-S's sep the last command is the stack's trim, not the free orbiter's: the loops start untrimmed
  IF asc_met_of(asc) < ASC_CSS_LO_T OR (asc["s1c"]:LENGTH > 0 AND asc["phase"] <> "STAGE1") { SET c0 TO LIST(0, 0, 0). }
  SET ascCss["i"] TO LIST(ascCssClip(c0[0], ASC_CSS_IMAX), ascCssClip(c0[1], ASC_CSS_IMAX), ascCssClip(c0[2], ASC_CSS_IMAX)).
  SET ascCss["auth"] TO ADDONS:KALS:FBWAUTH().
  SET ascCss["t"] TO TIME:SECONDS.
  SET ascCss["n"] TO 0.
  ascCssShReset().
  SET ascCss["law"] TO "A".
  asc_note(asc, "CSS LAW A: TRIM " + ROUND(c0[0], 2) + " / " + ROUND(c0[1], 2) + " / " + ROUND(c0[2], 2) + ", AUTH "
    + ROUND(ascCss["auth"][0], 1) + " / " + ROUND(ascCss["auth"][1], 1) + " / " + ROUND(ascCss["auth"][2], 1) + " DEG/S2").
  WHEN TRUE THEN {
    IF ascCss["law"] <> "A" { RETURN FALSE. }
    ascCssTickA().
    RETURN ascCss["law"] = "A".
  }
}

// every axis back: FBWOFF, the OMS gimbals as before; after Law A the C# ascent DAP (ops1q arms it again) or kOS's
// steering (relock), after Law B the DAP's raw output
FUNCTION ascCssStop {
  PARAMETER asc, why.
  IF NOT ascCss["on"] { RETURN. }
  LOCAL lw IS ascCss["law"].
  SET ascCss["on"] TO FALSE.
  SET ascCss["law"] TO "".
  SET ascCss["cp"] TO FALSE.
  SET ascCss["cr"] TO FALSE.
  SET ascCss["ret"] TO FALSE.
  SET ascDap["css"] TO FALSE.
  SET ascDap["fbw"] TO FALSE.
  LOCAL ok IS ADDONS:KALS:FBWOFF().
  ascCssOms(FALSE).
  IF NOT ascDap["on"] {
    STEERINGMANAGER:RESETPIDS().
    SET asc["relock"] TO TRUE.
  }
  IF ascCss["csv"] <> "" AND ascCss["buf"] <> "" { LOG ascCss["buf"] TO ascCss["csv"]. }
  SET ascCss["buf"] TO "".
  SET ascCss["bufn"] TO 0.
  asc_note(asc, "CSS OFF (" + why + (CHOOSE ", LAW " + lw IF lw <> "" ELSE "") + ")").
}

// THE C# LAW A. With ASC_CSS_CS on and the KAL/S addon carrying ASCCSSTICK, each Law A tick's math is
// ADDONS:KALS:ASCCSSTICK (coproc/AscCss.cs, a line-for-line port of ascCssTickAK below): kOS reads the vessel (ascCsIn:
// the time, the facing, the rates, the velocities, UP, the stick, FBWAUTH when due, the MET and the dynamic pressure on
// a csv row), the addon reads and writes ascCss itself (the state stays this lexicon, exact), kOS hands the commands to
// FBW3 and applies the rare actions (the return's ascCssStop and the row after it, the csv's LOG). On any addon failure
// (an older KalsCoproc.dll without ASCCSSTICK, a tick's error: nothing written) ASC_CSS_CS turns off for the rest of the
// program with an event line (ASC_CSS_CS_ERR says why) and ascCssTickAK flies that tick and the rest.
// SET ASC_CSS_CS TO FALSE. before the run = kOS only.
IF NOT (DEFINED ASC_CSS_CS) { GLOBAL ASC_CSS_CS IS TRUE. }
GLOBAL ASC_CSS_CS_ERR IS "".
GLOBAL ASC_CSS_CS_N IS 0.              // the ticks the addon flew
GLOBAL ascCsOk IS -1.                  // -1 not looked at yet, 1 the addon's ASCCSSTICK is there, 0 off

FUNCTION ascCsOff {                    // the C# Law A off for the program: kOS's ascCssTickAK from here
  PARAMETER why.
  SET ASC_CSS_CS_ERR TO why.
  SET ASC_CSS_CS TO FALSE.
  SET ascCsOk TO 0.
  asc_note(ascCss["asc"], "CSS LAW A: KOS FLIES THE TICKS (THE C# TICK OFF: " + why + ")").
}

FUNCTION ascCsSetup {                  // once, at the first tick: the addon and its ASCCSSTICK
  LOCAL why IS "".
  IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
  ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
  ELSE IF NOT ADDONS:KALS:HASSUFFIX("ASCCSSTICK") { SET why TO "the KAL/S addon has no ASCCSSTICK (an older KalsCoproc.dll)". }
  IF why <> "" { ascCsOff(why). RETURN. }
  SET ascCsOk TO 1.
  asc_note(ascCss["asc"], "CSS LAW A: THE C# COPROCESSOR FLIES THE TICKS").
}

FUNCTION ascCsIn {                     // the tick's reads, in coproc/AscCss.cs AscIn's order
  LOCAL nn IS ascCss["n"] + 1.         // the tick's n (AscCss.cs counts it)
  LOCAL au IS 0.
  IF MOD(nn, ASC_CSS_AUTH_N) = 0 { SET au TO ADDONS:KALS:FBWAUTH(). }
  LOCAL rw IS ascCss["csv"] <> "" AND MOD(nn, ASC_CSS_LOG_EVERY) = 0.
  RETURN LIST(TIME:SECONDS, SHIP:FACING, SHIP:ANGULARVEL, SHIP:VELOCITY:SURFACE, SHIP:VELOCITY:ORBIT, SHIP:UP:VECTOR,
    ADDONS:KALS:FBWPILOT(), au, CHOOSE asc_met_of(ascCss["asc"]) IF rw ELSE 0, CHOOSE SHIP:DYNAMICPRESSURE IF rw ELSE 0).
}

FUNCTION ascCsAct {                    // the rare actions: the return's stop, the row after it, the csv's LOG
  PARAMETER co.
  IF MOD(co[3], 2) = 1 { ascCssStop(ascCss["asc"], co[4]). }
  IF MOD(FLOOR(co[3] / 2), 2) = 1 { ascCssRow(co[5], co[6], co[7], co[8], co[9], co[10], co[11], co[12], co[13], co[14]). }
  IF co[3] >= 4 { LOG co[15] TO ascCss["csv"]. }
}

FUNCTION ascCsTick {                   // TRUE: the addon flew this tick (ascCss written, kOS applies the I/O)
  LOCAL co IS ADDONS:KALS:ASCCSSTICK(ascCsIn()).
  IF co:ISTYPE("String") { ascCsOff("ASCCSSTICK: " + co). RETURN FALSE. }
  SET ASC_CSS_CS_N TO ASC_CSS_CS_N + 1.
  ADDONS:KALS:FBW3(co[0], co[1], co[2]).
  IF co[3] > 0 { ascCsAct(co). }
  RETURN TRUE.
}

// LAW A: ONE PHYSICS TICK: the C# tick's (ASC_CSS_CS), else kOS's ascCssTickAK
FUNCTION ascCssTickA {
  IF ASC_CSS_CS {
    IF ascCsOk < 0 { ascCsSetup(). }
    IF ASC_CSS_CS { IF ascCsTick() { RETURN. } }
  }
  ascCssTickAK().
}

// LAW A: ONE PHYSICS TICK in kOS (the C# tick: coproc/AscCss.cs)
FUNCTION ascCssTickAK {
  LOCAL t IS TIME:SECONDS.
  LOCAL dt IS MAX(t - ascCss["t"], 0.001).
  SET ascCss["t"] TO t.
  SET ascCss["n"] TO ascCss["n"] + 1.
  LOCAL fv IS SHIP:FACING:FOREVECTOR.
  LOCAL tv IS SHIP:FACING:TOPVECTOR.
  LOCAL sv IS SHIP:FACING:STARVECTOR.
  LOCAL kp IS sv * -1.                                  // the nose-up axis
  LOCAL w IS SHIP:ANGULARVEL * 57.2958.                 // deg/s: . kp nose up, . fv LEFT roll, . tv nose right
  IF MOD(ascCss["n"], ASC_CSS_AUTH_N) = 0 { SET ascCss["auth"] TO ADDONS:KALS:FBWAUTH(). }
  LOCAL stk IS ascCssStick().
  LOCAL eA IS ascCssErr(fv, tv, sv, ascCss["tgt"]).
  LOCAL eP IS eA.
  LOCAL eR IS eA.
  IF ascCss["cp"] AND ascCss["hpOn"] { SET eP TO ascCssErr(fv, tv, sv, ascCssHeld("hp")). }
  IF ascCss["cr"] AND ascCss["hrOn"] { SET eR TO ascCssErr(fv, tv, sv, ascCssHeld("hr")). }
  // AUTO pitch under ROLL/YAW CSS: the current roll (the turn taking the stick's roll axis onto the guidance's), on its
  // own clip and with the guidance's rate less its roll about that axis fed forward
  LOCAL pcr IS ascCss["cr"] AND NOT ascCss["cp"].
  LOCAL tg3 IS V(0, 0, 0).
  IF pcr {
    LOCAL b IS ascCss["tb3"].
    LOCAL d IS ascCss["tgt"].
    SET tg3 TO d:STARVECTOR * b:X + d:TOPVECTOR * b:Y + d:FOREVECTOR * b:Z.
    SET eP TO VCRS(sv * b:X + tv * b:Y + fv * b:Z, tg3).
  }
  LOCAL kcw IS MIN(1, ASC_CSS_WARP_KT * ASC_CSS_T / dt).
  LOCAL kch IS MIN(1, ASC_CSS_WARP_KT * ASC_CSS_TC / dt).   // a CSS axis's: the stick loop's gain, its warp cap alike
  LOCAL sht IS ascCssTg(stk, kcw).
  LOCAL om IS (kp * (CHOOSE 0 IF pcr ELSE VDOT(eP, kp)) * (CHOOSE kch IF ascCss["cp"] ELSE kcw)
    + (fv * VDOT(eR, fv) + tv * VDOT(eR, tv)) * (CHOOSE kch IF ascCss["cr"] ELSE kcw)) * (57.2958 * ASC_CSS_KA).
  IF om:MAG > ASC_CSS_WAUTO { SET om TO om * (ASC_CSS_WAUTO / om:MAG). }
  LOCAL wf IS ascCss["wf"].                             // the guidance's own rate, in the AUTO axes
  LOCAL qc IS VDOT(om, kp) + (CHOOSE ascCssFf("hp", kp) IF ascCss["cp"] ELSE VDOT(wf, kp)).
  IF pcr { SET qc TO ascCssClip(VDOT(eP, kp) * 57.2958 * ASC_CSS_KA * kcw, ASC_CSS_WAUTO) + VDOT(wf - tg3 * VDOT(wf, tg3), kp). }
  LOCAL pc IS VDOT(om, fv) + (CHOOSE ascCssFf("hr", fv) IF ascCss["cr"] ELSE VDOT(wf, fv)).   // + = LEFT
  LOCAL rc IS VDOT(om, tv) + (CHOOSE ascCssFf("hr", tv) IF ascCss["cr"] ELSE VDOT(wf, tv)).   // + = nose right
  IF ascCss["cp"] AND stk[0] <> 0 { SET qc TO stk[0]. }
  IF ascCss["cp"] AND stk[0] = 0 AND NOT ascCss["hpOn"] { SET qc TO 0. }   // damped before the catch
  IF ascCss["cr"] AND stk[1] = 0 AND stk[2] = 0 AND NOT ascCss["hrOn"] { SET pc TO 0. SET rc TO 0. }
  IF ascCss["cr"] AND (stk[1] <> 0 OR stk[2] <> 0) {
    SET pc TO 0 - stk[1].
    SET rc TO stk[2].
  }
  LOCAL wq IS VDOT(w, kp).
  LOCAL wp IS VDOT(w, fv).
  LOCAL wr IS VDOT(w, tv).
  LOCAL au IS ascCss["auth"].
  // the stick axes (ascCssSh; the roll's in the LEFT sense, as pc); the csv's commands are the model's rates there
  LOCAL shP IS ascCss["cp"] AND (stk[0] <> 0 OR NOT ascCss["hpOn"]).
  LOCAL shR IS ascCss["cr"] AND (stk[1] <> 0 OR stk[2] <> 0 OR NOT ascCss["hrOn"]).
  LOCAL cmdP IS 0.
  LOCAL cmdR IS 0.
  LOCAL cmdY IS 0.
  IF shP {
    LOCAL am IS MAX(au[0] * ascCss["ks"][0], ASC_CSS_AMIN).
    LOCAL ar IS ascCssSh(0, sht[0], wq, am, dt).
    SET qc TO ascCss["sh"][2].
    SET cmdP TO ascCssPS(0, (ar + (qc - wq) * kcw / ASC_CSS_TC) / am, (qc - wq) / (ASC_CSS_TC * am), kch, dt).
  } ELSE IF ascCss["cp"] {                              // the hold: the stick loop's gain (no step at the catch)
    ascCssShOff(0).
    SET cmdP TO ascCssPI(0, (qc - wq) / (ASC_CSS_TC * MAX(au[0] * ascCss["ks"][0], ASC_CSS_AMIN)), kch, dt).
  } ELSE {
    ascCssShOff(0).
    SET cmdP TO ascCssPI(0, (qc - wq) / (ASC_CSS_T * MAX(au[0] * ASC_CSS_AUTH_K, ASC_CSS_AMIN)), kcw, dt).
  }
  IF shR {
    // the references in the stick's axes (ascCss["tb"]: the roll about the thrust axis, the yaw across it; the nose's
    // own frame when it is 1 / 0), their rates and accelerations back in the body's for the loops
    LOCAL am IS MAX(au[1] * ascCss["ks"][1], ASC_CSS_AMIN).
    LOCAL ay IS MAX(au[2] * ascCss["ks"][2], ASC_CSS_AMIN).
    LOCAL tbC IS ascCss["tb"][0].
    LOCAL tbS IS ascCss["tb"][1].
    LOCAL tpT IS sht[1].
    LOCAL trT IS sht[2].
    IF stk[1] = 0 AND stk[2] = 0 {                      // the frame's turn (ascCssTg) put on the stick's axes
      SET tpT TO sht[1] * tbC + sht[2] * tbS.
      SET trT TO sht[2] * tbC - sht[1] * tbS.
    }
    LOCAL amT IS MIN(am / tbC, ay / MAX(ABS(tbS), 0.000001)).
    LOCAL ayT IS MIN(ay / tbC, am / MAX(ABS(tbS), 0.000001)).
    LOCAL ar IS ascCssSh(1, tpT, wp * tbC + wr * tbS, amT, dt).
    LOCAL ary IS ascCssSh(2, trT, wr * tbC - wp * tbS, ayT, dt).
    LOCAL pcT IS ascCss["sh"][7].
    LOCAL rcT IS ascCss["sh"][12].
    SET pc TO tbC * pcT - tbS * rcT.
    SET rc TO tbS * pcT + tbC * rcT.
    LOCAL arB IS tbC * ar - tbS * ary.
    LOCAL aryB IS tbS * ar + tbC * ary.
    SET cmdR TO ascCssPS(1, 0 - (arB + (pc - wp) * kcw / ASC_CSS_TC) / am, 0 - (pc - wp) / (ASC_CSS_TC * am), kch, dt).   // ctrl + = RIGHT
    SET cmdY TO ascCssPS(2, (aryB + (rc - wr) * kcw / ASC_CSS_TC) / ay, (rc - wr) / (ASC_CSS_TC * ay), kch, dt).
  } ELSE IF ascCss["cr"] {                              // the hold: the stick loop's gain
    ascCssShOff(1).
    ascCssShOff(2).
    SET cmdR TO ascCssPI(1, -(pc - wp) / (ASC_CSS_TC * MAX(au[1] * ascCss["ks"][1], ASC_CSS_AMIN)), kch, dt).   // ctrl + = RIGHT
    SET cmdY TO ascCssPI(2, (rc - wr) / (ASC_CSS_TC * MAX(au[2] * ascCss["ks"][2], ASC_CSS_AMIN)), kch, dt).
  } ELSE {
    ascCssShOff(1).
    ascCssShOff(2).
    SET cmdR TO ascCssPI(1, -(pc - wp) / (ASC_CSS_T * MAX(au[1] * ASC_CSS_AUTH_K, ASC_CSS_AMIN)), kcw, dt).   // ctrl + = RIGHT
    SET cmdY TO ascCssPI(2, (rc - wr) / (ASC_CSS_T * MAX(au[2] * ASC_CSS_AUTH_K, ASC_CSS_AMIN)), kcw, dt).
  }
  // the cross-coupling taken out (ascCss["dc"]): the commands that give the loops' roll (LEFT) and yaw accelerations
  LOCAL dcRY IS ascCss["dc"][0].
  LOCAL dcYR IS ascCss["dc"][1].
  IF dcRY <> 0 OR dcYR <> 0 {
    LOCAL dcD IS 1 - dcRY * dcYR.
    LOCAL dcX IS (0 - cmdR - dcRY * cmdY) / dcD.
    LOCAL dcU IS (cmdY + dcYR * cmdR) / dcD.
    SET cmdR TO ascCssClip(0 - dcX, 1).
    SET cmdY TO ascCssClip(dcU, 1).
  }
  SET ascCss["u"] TO LIST(cmdP, cmdR, cmdY).
  ADDONS:KALS:FBW3(cmdP, cmdR, cmdY).
  // the return: both axes AUTO, back on the guidance's attitude -> kOS's steering (the main loop locks it)
  IF ascCss["ret"] {
    LOCAL ed IS eA:MAG * 57.2958.
    LOCAL wd IS (w - wf):MAG.
    IF (ed < ASC_CSS_RET_DEG AND wd < ASC_CSS_RET_W) OR t - ascCss["rt0"] > ASC_CSS_RET_T {
      ascCssStop(ascCss["asc"], "AUTO: " + ROUND(ed, 2) + " DEG, " + ROUND(wd, 2) + " DEG/S").
    }
  }
  IF ascCss["csv"] <> "" AND MOD(ascCss["n"], ASC_CSS_LOG_EVERY) = 0 {
    ascCssRow(t, qc, pc, rc, wq, wp, wr, VDOT(eP, kp) * 57.2958, VDOT(eR, fv) * 57.2958, VDOT(eR, tv) * 57.2958).
  }
}

// LAW B (lib_ascent_dap's tick, its frame: x STAR, y FORE, z -TOP; the rates in the VCRS sense, rad/s): the CSS axes'
// wanted rates from the stick or the hold; w the body rates, dt the tick. A stick axis (ascCssSh, the stick's sense:
// nose up / RIGHT / nose right = -x / -y / -z, the authority from the DAP's B-hat and I-hat) also sets its wanted
// acceleration (ascCss["lbA"], rad/s2) and flag (ascCss["lbOn"]) for ascCssAd / ascCssIw. The roll / yaw stick turns
// about the thrust axis (ascCss["tb3"], its sideways lean too) and across it (-TOP's part off it); with PITCH AUTO the
// roll's own pitch part goes on the pitch. AUTO pitch under ROLL/YAW CSS: the current roll, as Law A's
FUNCTION ascCssWd {
  PARAMETER ex, ey, ez, wd, w, dt.
  LOCAL stk IS ascCssStick().
  LOCAL sht IS ascCssTg(stk, 1).
  LOCAL d2r IS CONSTANT:DEGTORAD.
  LOCAL r2d IS CONSTANT:RADTODEG.
  LOCAL ka IS ASC_DAP_WN / (2 * ASC_DAP_ZETA).
  LOCAL wm IS ASC_CSS_WAUTO * d2r.
  LOCAL x IS wd:X.
  LOCAL y IS wd:Y.
  LOCAL z IS wd:Z.
  LOCAL bm IS ascDap["B"].
  LOCAL ih IS ascDap["I"].
  LOCAL la IS V(0, 0, 0).
  LOCAL lo IS LIST(FALSE, FALSE, FALSE).
  LOCAL b IS ascCss["tb3"].
  LOCAL bB IS V(b:X, b:Z, 0 - b:Y).                  // the thrust axis in this frame
  IF ascCss["cr"] AND NOT ascCss["cp"] {
    LOCAL tg IS ascDap["tgt"].
    LOCAL tgb IS tg:STARVECTOR * b:X + tg:TOPVECTOR * b:Y + tg:FOREVECTOR * b:Z.
    LOCAL wf IS ascDap["wff"].
    SET x TO ascCssClip(ka * VDOT(VCRS(ex * b:X - ez * b:Y + ey * b:Z, tgb) - ascDap["eff"], ex), wm) + VDOT(wf - tgb * VDOT(wf, tgb), ex).
  }
  IF ascCss["cp"] {
    IF stk[0] <> 0 OR NOT ascCss["hpOn"] {
      LOCAL wn IS 0 - w:X * r2d.
      LOCAL ar IS ascCssSh(0, sht[0], wn, ABS(bm[0]:X) / ih[0] * r2d, dt).
      LOCAL wq IS ascCss["sh"][2].
      SET x TO 0 - wq * d2r.
      SET la TO V(0 - (ar + (wq - wn) / ASC_CSS_TC) * d2r, 0, 0).
      SET lo[0] TO TRUE.
    } ELSE {
      ascCssShOff(0).
      SET x TO ascCssClip(ka * VDOT(ascCssErr(ey, -ez, ex, ascCssHeld("hp")), ex), wm) + ascCssFf("hp", ex) * d2r.
    }
  }
  IF ascCss["cr"] {
    IF stk[1] <> 0 OR stk[2] <> 0 OR NOT ascCss["hrOn"] {
      LOCAL aY IS (V(0, 0, 1) - bB * bB:Z):NORMALIZED.
      LOCAL tp IS 0 - sht[1].
      LOCAL tr IS sht[2].
      IF stk[1] = 0 AND stk[2] = 0 {                  // the frame's turn put on the stick's axes
        LOCAL fw IS ascCss["fmw"].
        LOCAL fwB IS V(VDOT(fw, ex), VDOT(fw, ey), VDOT(fw, ez)).
        SET tp TO 0 - VDOT(fwB, bB).
        SET tr TO 0 - VDOT(fwB, aY).
      }
      LOCAL amR IS ABS(bm[1]:Y) / ih[1] * r2d.        // the roll's and the yaw's authority
      LOCAL amW IS ABS(bm[2]:Z) / ih[2] * r2d.
      LOCAL wn IS 0 - VDOT(w, bB) * r2d.
      LOCAL ar IS ascCssSh(1, tp, wn, MIN(amR / MAX(ABS(bB:Y), 0.000001), amW / MAX(ABS(bB:Z), 0.000001)), dt).
      LOCAL wp IS ascCss["sh"][7].
      LOCAL wny IS 0 - VDOT(w, aY) * r2d.
      LOCAL ary IS ascCssSh(2, tr, wny, MIN(amW / MAX(ABS(aY:Z), 0.000001), amR / MAX(ABS(aY:Y), 0.000001)), dt).
      LOCAL wy IS ascCss["sh"][12].
      LOCAL lbW IS (bB * wp + aY * wy) * (0 - d2r).
      LOCAL lbC IS (bB * (ar + (wp - wn) / ASC_CSS_TC) + aY * (ary + (wy - wny) / ASC_CSS_TC)) * (0 - d2r).
      SET y TO lbW:Y.
      SET z TO lbW:Z.
      IF NOT ascCss["cp"] { SET x TO x + lbW:X. }
      SET la TO V(la:X, lbC:Y, lbC:Z).
      SET lo[1] TO TRUE.
      SET lo[2] TO TRUE.
    } ELSE IF ascCss["hrOn"] {
      LOCAL e IS ascCssErr(ey, -ez, ex, ascCssHeld("hr")).
      LOCAL wr1 IS CHOOSE ASC_DAP_WMAX_ROLL1 * d2r IF ascDap["one"] ELSE wm.
      ascCssShOff(1).
      ascCssShOff(2).
      SET y TO ascCssClip(ka * VDOT(e, ey), wr1) + ascCssFf("hr", ey) * d2r.
      SET z TO ascCssClip(ka * VDOT(e, ez), wm) + ascCssFf("hr", ez) * d2r.
    }
  }
  SET ascCss["lbA"] TO la.
  SET ascCss["lbOn"] TO lo.
  IF ascCss["csv"] <> "" {
    SET ascCss["n"] TO ascCss["n"] + 1.
    IF MOD(ascCss["n"], ASC_CSS_LOG_EVERY) = 0 {
      LOCAL r2d IS CONSTANT:RADTODEG.
      LOCAL w IS ascDap["w"].
      LOCAL e IS ascDap["e"].
      ascCssRow(TIME:SECONDS, -x * r2d, y * r2d, -z * r2d, -w:X * r2d, w:Y * r2d, -w:Z * r2d, -e:X * r2d, e:Y * r2d, -e:Z * r2d).
    }
  }
  RETURN V(x, y, z).
}

// Law B: the target's accelerations fed forward only in the AUTO axes
FUNCTION ascCssMask {
  PARAMETER a.
  RETURN V(CHOOSE 0 IF ascCss["cp"] ELSE a:X, CHOOSE 0 IF ascCss["cr"] ELSE a:Y, CHOOSE 0 IF ascCss["cr"] ELSE a:Z).
}

// Law B: the stick axes' wanted accelerations (ascCssWd's, plus the integral's ai) in place of the DAP's
FUNCTION ascCssAd {
  PARAMETER ad, ai.
  LOCAL lo IS ascCss["lbOn"].
  LOCAL la IS ascCss["lbA"].
  RETURN V(CHOOSE la:X + ai:X IF lo[0] ELSE ad:X, CHOOSE la:Y + ai:Y IF lo[1] ELSE ad:Y, CHOOSE la:Z + ai:Z IF lo[2] ELSE ad:Z).
}

// Law B: the integral in the stick axes. It was HELD there (the rate error never reached ascDap["iw"]), so a steady
// disturbance (the aero / thrust nose-up moment the model t0 does not carry: ~5 deg/s2 at MET 85-110 of an RTLS, 2 at 135)
// left the stick axis a steady rate error of d x ASC_CSS_TC and the crew pushed the stick for it, with the hold caught on a
// trim of 0. Now the rate error runs the integral in a stick axis too, ASC_CSS_KIB / ASC_DAP_KI times faster (the same
// iw, so the trim carries into the hold without a step: ai = iw x ASC_DAP_KI everywhere), limited at ASC_CSS_IWMAX
// (ascCssIw1: no more in the direction it already sits at the limit)
FUNCTION ascCssIw1 {
  PARAMETER e, i, f.
  IF ABS(i) >= ASC_CSS_IWMAX AND e * i > 0 { RETURN 0. }
  RETURN e * f.
}

FUNCTION ascCssIw {
  PARAMETER ew.
  LOCAL lo IS ascCss["lbOn"].
  LOCAL iw IS ascDap["iw"].
  LOCAL f IS 0.
  IF ASC_DAP_KI > 0 { SET f TO ASC_CSS_KIB / ASC_DAP_KI. }
  RETURN V(CHOOSE ascCssIw1(ew:X, iw:X, f) IF lo[0] ELSE ew:X, CHOOSE ascCssIw1(ew:Y, iw:Y, f) IF lo[1] ELSE ew:Y,
    CHOOSE ascCssIw1(ew:Z, iw:Z, f) IF lo[2] ELSE ew:Z).
}

FUNCTION ascCssRow {
  PARAMETER t, qc, pc, rc, wq, wp, wr, ep, er, ey.
  LOCAL st IS ascCss["stk"].
  LOCAL u IS ascCss["u"].
  IF ascCss["law"] = "B" { SET u TO LIST(ascDap["u"]:X, ascDap["u"]:Y, ascDap["u"]:Z). }
  LOCAL ii IS ascCss["i"].
  IF ascCss["law"] = "B" {               // Law B's trim: the DAP's integral x ASC_DAP_KI, deg/s2 (ascCss["i"] is Law A's)
    LOCAL iwb IS ascDap["iw"] * (ASC_DAP_KI * CONSTANT:RADTODEG).
    SET ii TO LIST(0 - iwb:X, iwb:Y, 0 - iwb:Z).
  }
  LOCAL au IS ascCss["auth"].
  SET ascCss["buf"] TO ascCss["buf"] + (CHOOSE "" IF ascCss["bufn"] = 0 ELSE CHAR(10)) + ROUND(t, 2) + "," + ROUND(asc_met_of(ascCss["asc"]), 2)
    + "," + ascCss["law"] + "," + ROUND(SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA, 2) + "," + (CHOOSE 1 IF ascCss["cp"] ELSE 0)
    + "," + (CHOOSE 1 IF ascCss["cr"] ELSE 0) + "," + (CHOOSE 1 IF ascCss["hpOn"] ELSE 0) + "," + (CHOOSE 1 IF ascCss["hrOn"] ELSE 0)
    + "," + ROUND(st[0], 3) + "," + ROUND(st[1], 3) + "," + ROUND(st[2], 3) + "," + ROUND(qc, 3) + "," + ROUND(pc, 3) + ","
    + ROUND(rc, 3) + "," + ROUND(wq, 3) + "," + ROUND(wp, 3) + "," + ROUND(wr, 3) + "," + ROUND(ep, 3) + "," + ROUND(er, 3) + ","
    + ROUND(ey, 3) + "," + ROUND(u[0], 4) + "," + ROUND(u[1], 4) + "," + ROUND(u[2], 4) + "," + ROUND(ii[0], 4) + ","
    + ROUND(ii[1], 4) + "," + ROUND(ii[2], 4) + "," + ROUND(au[0], 2) + "," + ROUND(au[1], 2) + "," + ROUND(au[2], 2) + ","
    + (CHOOSE 1 IF ascCss["ret"] ELSE 0).
  SET ascCss["bufn"] TO ascCss["bufn"] + 1.
  IF ascCss["bufn"] >= ASC_CSS_FLUSH {
    LOG ascCss["buf"] TO ascCss["csv"].
    SET ascCss["buf"] TO "".
    SET ascCss["bufn"] TO 0.
  }
}
