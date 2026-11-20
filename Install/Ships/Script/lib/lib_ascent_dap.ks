// lib_ascent_dap.ks  --  the ascent DAP: this vehicle's own stage-2 attitude control after an SSME failure, in place of
// kOS's cooked steering (which oscillated on two SSMEs). Built offline first (the stack as a rigid body, KSP's gimbal
// law from ModuleGimbal's IL): it holds every engine-out case there, where kOS's steering's stand-in tumbles with the
// centre SSME out.
// Each physics tick (a trigger): the body rates from the frame's turn since the last tick; the attitude error to the
// target ascDap["tgt"] (ops1q's asc_dir); the wanted rates wd = ka e (|wd| at most ASC_DAP_WMAX); the wanted angular
// accelerations ad = kr (wd - w) + ASC_DAP_KI * the integral of (wd - w); the torque td = I-hat ad; the inputs
// u = B-hat^-1 (td - tau0-hat) -> SHIP:CONTROL:PITCH / ROLL / YAW (kOS hands them to KSP unchanged: FlightControl.
// PushNewSetting). B-hat = KSP's gimbal law (ModuleGimbal.FixedUpdate) linearized with the live geometry: each running
// SSME's position from the control part and from the CoM, its thrust axis, thrust and range, its pitch / roll / yaw
// switches; tau0-hat = the SSMEs' torque at zero input (the trim, fed forward). Saturated: pitch and yaw kept, the roll
// clipped. With one SSME the RCS rolls (its torque along -input, as KSP's ModuleRCS: B-hat's roll column
// -ASC_DAP_RCS) and the roll attitude is free (rate damping only): one engine cannot roll the stack without yawing it.
// Per axis kr = 2 zeta wn, ka = wn / (2 zeta). I-hat (t m^2; Ixx, Iyy, Izz, Iyz): the vessel's own inertia tensor from
// ADDONS:KALS:ASCIHAT (summed from its rigid bodies, as the C# DAP's) when ascDap["ihk"] (ops1q: the addon has it); the
// polynomials in its mass, fitted to the "Columbia Late" stage-2 model (offline; Ixy, Ixz ~0), without it or where its
// guard refuses the tensor. ascDap["ihs"]: which flies ("live" / "fallback,<why>").
// Frames: the body x = SHIP:FACING:STARVECTOR (pitch), y = :FOREVECTOR (roll), z = -:TOPVECTOR (yaw) = KSP's control
// frame; the vectors in kOS's raw frame from the CoM (VCRS = Unity's cross: the same component formulas as the gimbal
// law and the physics).
// Use: ascDapStart(the SSME list, one SSME?) (again at a second failure), each main-loop pass SET ascDap["tgt"] TO asc_dir.,
// ascDapStop() (the raw controls neutral; the caller locks its steering again). ascDap["wff"]: the target's own rate (raw,
// rad/s; ops1q: an RTLS slew's), fed forward: added to the wanted rates; ascDap["eff"]:
// the reference moved back by its ramp's lag (raw, rad), taken off the attitude error; ascDap["aff"]: the ramp's
// deceleration (raw, rad/s2), added to the wanted angular accelerations.
// Names: the globals are asc* (ascDap, ascDapStart / ascDapStop / ascDapTick / ascDapModel / ascDapPoly): OPS 6's
// lib_dap.ks also defines dapTick and dapStop, and after a TAL ops1q runs ops6q in its own program context, where kOS
// keeps the first definition (landRun would run this DAP's tick).
// ops1q feeds the roll to heads up's rate forward too (ascDap["wff"] / "eff" / "aff", as an RTLS slew's), and the
// wanted rates are clipped as a vector (their direction kept: the turn stays about the error's axis); clipped axis by
// axis, the DAP chased the roll at 2 deg/s about the nose, the thrust up to 19-23 deg off PEG's direction.
@LAZYGLOBAL OFF.

GLOBAL ASC_DAP_WN IS 1.0.                   // rad/s, each axis
GLOBAL ASC_DAP_ZETA IS 0.8.
GLOBAL ASC_DAP_WMAX IS 2.0.                 // deg/s
GLOBAL ASC_DAP_KI IS 0.3.                   // 1/s^2 on the integral of the rate error
GLOBAL ASC_DAP_RCS IS 20.                   // kN m per unit roll input with one SSME (the RCS)
GLOBAL ASC_DAP_BDT IS 0.2.                  // s between B-hat updates
GLOBAL ASC_DAP_WMAX_ROLL1 IS 5.0.           // deg/s: the roll's own clip with "roll1" (one SSME: the RCS)
// I-hat (t m^2) = c2 m^2 + c1 m + c0, m = SHIP:MASS (t; 38.6 .. 229 t)
GLOBAL ASC_DAP_IXX IS LIST(-0.112969, 127.962, -597.469).
GLOBAL ASC_DAP_IYY IS LIST(-0.0124637, 8.38094, 64.6738).
GLOBAL ASC_DAP_IZZ IS LIST(-0.100505, 123.226, -664.802).
GLOBAL ASC_DAP_IYZ IS LIST(0.0353931, -13.4486, -246.658).
// ops1q's C# DAP (ADDONS:KALS:ASCDAP) in stage 1: wn 2 (offline: the roll program's nose within 0.6 deg; wn 1
// lags it), I-hat fitted to "Challenger Late"'s stage-1 stack (the SRBs and the ET burning; 223.5 .. 512 t, 1 %); the
// target older than ASC_DAP_CS_TMAX s lets it go
GLOBAL ASC_DAP_S1_WN IS 2.0.
GLOBAL ASC_DAP_S1_IXX IS LIST(-0.0201722, 110.67, 203.946).
GLOBAL ASC_DAP_S1_IYY IS LIST(-0.00296685, 15.9702, -1585.72).
GLOBAL ASC_DAP_S1_IZZ IS LIST(-0.0230307, 125.159, -2786.32).
GLOBAL ASC_DAP_S1_IYZ IS LIST(-0.00395591, 3.97758, -1983.36).
GLOBAL ASC_DAP_CS_TMAX IS 10.

GLOBAL ascDap IS LEXICON("on", FALSE, "tgt", SHIP:FACING, "n", 0, "wff", V(0, 0, 0), "eff", V(0, 0, 0), "aff", V(0, 0, 0),
  "roll1", FALSE, "css", FALSE, "fbw", FALSE, "ihk", FALSE, "ihs", "").

FUNCTION ascDapPoly {
  PARAMETER c, m.
  RETURN (c[0] * m + c[1]) * m + c[2].
}

FUNCTION ascDapStart {
  PARAMETER engs, one.
  SET ascDap["engs"] TO engs.
  SET ascDap["one"] TO one.
  LOCAL fc IS SHIP:FACING.
  SET ascDap["ex"] TO fc:STARVECTOR.
  SET ascDap["ey"] TO fc:FOREVECTOR.
  SET ascDap["ez"] TO -fc:TOPVECTOR.
  SET ascDap["t"] TO TIME:SECONDS.
  SET ascDap["iw"] TO V(0, 0, 0).
  SET ascDap["u"] TO V(0, 0, 0).
  SET ascDap["e"] TO V(0, 0, 0).
  SET ascDap["w"] TO V(0, 0, 0).
  SET ascDap["sat"] TO 0.
  ascDapModel(ascDap["ex"], ascDap["ey"], ascDap["ez"]).
  SET ascDap["tb"] TO TIME:SECONDS + ASC_DAP_BDT.
  IF NOT ascDap["on"] {
    SET ascDap["on"] TO TRUE.
    WHEN TRUE THEN {
      IF NOT ascDap["on"] { RETURN FALSE. }
      ascDapTick().
      RETURN TRUE.
    }
  }
}

FUNCTION ascDapStop {
  SET ascDap["on"] TO FALSE.
  SET ascDap["roll1"] TO FALSE.
  SET ascDap["css"] TO FALSE.
  IF ascDap["fbw"] {                         // the ascent's CSS flew this DAP through FBW3
    SET ascDap["fbw"] TO FALSE.
    ADDONS:KALS:FBWOFF().
  }
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
}

// B-hat (its columns, body: the torque in kN m per unit pitch / roll / yaw input), its inverse's rows, tau0-hat, I-hat
FUNCTION ascDapModel {
  PARAMETER ex, ey, ez.
  LOCAL cp IS SHIP:CONTROLPART:POSITION.
  LOCAL comy IS -VDOT(cp, ey).
  LOCAL c0 IS V(0, 0, 0).
  LOCAL c1 IS V(0, 0, 0).
  LOCAL c2 IS V(0, 0, 0).
  LOCAL t0 IS V(0, 0, 0).
  LOCAL n IS 0.
  FOR en IN ascDap["engs"] {
    LOCAL th IS en:THRUST.
    IF th > 0.1 AND en:HASGIMBAL {
      SET n TO n + 1.
      LOCAL p IS en:POSITION.
      LOCAL pc IS p - cp.
      LOCAL px IS VDOT(pc, ex).
      LOCAL pz IS VDOT(pc, ez).
      LOCAL f IS en:FACING:FOREVECTOR.
      LOCAL g IS en:GIMBAL.
      LOCAL rg IS 0.
      IF NOT g:LOCK { SET rg TO g:RANGE * g:LIMIT / 100 * CONSTANT:DEGTORAD. }
      LOCAL e1 IS (ex - f * VDOT(ex, f)):NORMALIZED.
      LOCAL e2 IS VCRS(f, e1).
      LOCAL sg IS 1.
      IF VDOT(pc, ey) > comy { SET sg TO -1. }
      // the law's a per unit input (control frame -> raw): pitch and yaw flipped forward of the CoM; the roll's terms
      // by the side of the control part's axis the gimbal is on (beyond 0.1 m)
      LOCAL ap IS V(0, 0, 0).
      IF g:PITCH { SET ap TO ex * sg. }
      LOCAL ay IS V(0, 0, 0).
      IF g:YAW { SET ay TO ez * sg. }
      LOCAL ar IS V(0, 0, 0).
      IF g:ROLL {
        SET ar TO ey.
        IF px > 0.1 { SET ar TO ar + ex. } ELSE IF px < -0.1 { SET ar TO ar - ex. }
        IF pz > 0.1 { SET ar TO ar + ez. } ELSE IF pz < -0.1 { SET ar TO ar - ez. }
      }
      // the nozzle's turn = range * (a's part across the thrust axis); the torque = p x (thrust * (turn x f))
      SET c0 TO c0 + VCRS(p, VCRS((e1 * VDOT(ap, e1) + e2 * VDOT(ap, e2)) * rg, f)) * th.
      SET c1 TO c1 + VCRS(p, VCRS((e1 * VDOT(ar, e1) + e2 * VDOT(ar, e2)) * rg, f)) * th.
      SET c2 TO c2 + VCRS(p, VCRS((e1 * VDOT(ay, e1) + e2 * VDOT(ay, e2)) * rg, f)) * th.
      SET t0 TO t0 + VCRS(p, f) * th.
    }
  }
  SET ascDap["n"] TO n.
  LOCAL b0 IS V(VDOT(c0, ex), VDOT(c0, ey), VDOT(c0, ez)).
  LOCAL b1 IS V(VDOT(c1, ex), VDOT(c1, ey), VDOT(c1, ez)).
  LOCAL b2 IS V(VDOT(c2, ex), VDOT(c2, ey), VDOT(c2, ez)).
  IF ascDap["one"] { SET b1 TO b1 + V(0, -ASC_DAP_RCS, 0). }
  LOCAL det IS VDOT(b0, VCRS(b1, b2)).
  IF ABS(det) < 1 { RETURN. }               // no SSME running: the last model kept
  SET ascDap["B"] TO LIST(b0, b1, b2).
  SET ascDap["r0"] TO VCRS(b1, b2) / det.
  SET ascDap["r1"] TO VCRS(b2, b0) / det.
  SET ascDap["r2"] TO VCRS(b0, b1) / det.
  SET ascDap["t0"] TO V(VDOT(t0, ex), VDOT(t0, ey), VDOT(t0, ez)).
  LOCAL m IS SHIP:MASS.
  LOCAL ihp IS LIST(ascDapPoly(ASC_DAP_IXX, m), ascDapPoly(ASC_DAP_IYY, m), ascDapPoly(ASC_DAP_IZZ, m), ascDapPoly(ASC_DAP_IYZ, m)).
  IF ascDap["ihk"] {
    LOCAL ihr IS ADDONS:KALS:ASCIHAT(ihp).
    IF ihr[4] = "" {
      SET ihp TO LIST(ihr[0], ihr[1], ihr[2], ihr[3]).
      SET ascDap["ihs"] TO "live".
    } ELSE {
      SET ascDap["ihs"] TO "fallback," + ihr[4].
    }
  } ELSE {
    SET ascDap["ihs"] TO "fallback,no ASCIHAT".
  }
  SET ascDap["I"] TO ihp.
}

FUNCTION ascDapTick {
  LOCAL t IS TIME:SECONDS.
  LOCAL dt IS t - ascDap["t"].
  IF dt <= 0 { RETURN. }
  LOCAL fc IS SHIP:FACING.
  LOCAL ex IS fc:STARVECTOR.
  LOCAL ey IS fc:FOREVECTOR.
  LOCAL ez IS -fc:TOPVECTOR.
  // the body rates: the frame's turn since the last tick (rad/s)
  LOCAL ph IS (VCRS(ascDap["ex"], ex) + VCRS(ascDap["ey"], ey) + VCRS(ascDap["ez"], ez)) * (0.5 / dt).
  SET ascDap["ex"] TO ex.
  SET ascDap["ey"] TO ey.
  SET ascDap["ez"] TO ez.
  SET ascDap["t"] TO t.
  LOCAL w IS V(VDOT(ph, ex), VDOT(ph, ey), VDOT(ph, ez)).
  // the attitude error (rad: the sine of the angle along the axis); one SSME: the pointing error only (the roll free)
  // unless "roll1" (the 2EO contingency's roll heads up on the RCS): then the roll's error too, from the full error
  LOCAL tg IS ascDap["tgt"].
  LOCAL er IS VCRS(ey, tg:FOREVECTOR).
  LOCAL erf IS (VCRS(ex, tg:STARVECTOR) + er + VCRS(ez, -tg:TOPVECTOR)) * 0.5.
  IF NOT ascDap["one"] { SET er TO erf. }
  SET er TO er - ascDap["eff"].
  LOCAL ea IS V(VDOT(er, ex), VDOT(er, ey), VDOT(er, ez)).
  IF ascDap["one"] AND ascDap["roll1"] { SET ea TO V(ea:X, VDOT(erf, ey), ea:Z). }
  IF t >= ascDap["tb"] {
    ascDapModel(ex, ey, ez).
    SET ascDap["tb"] TO t + ASC_DAP_BDT.
  }
  LOCAL kr IS 2 * ASC_DAP_ZETA * ASC_DAP_WN.
  LOCAL ka IS ASC_DAP_WN / (2 * ASC_DAP_ZETA).
  LOCAL wm IS ASC_DAP_WMAX * CONSTANT:DEGTORAD.
  LOCAL wdy IS 0.
  IF NOT ascDap["one"] { SET wdy TO ka * ea:Y. }
  LOCAL wd IS V(ka * ea:X, wdy, ka * ea:Z).
  IF wd:MAG > wm { SET wd TO wd * (wm / wd:MAG). }     // clipped as a vector (the turn about the error's axis)
  IF ascDap["one"] AND ascDap["roll1"] {             // the RCS's roll on its own clip (pitch and yaw as above)
    LOCAL w1 IS ASC_DAP_WMAX_ROLL1 * CONSTANT:DEGTORAD.
    SET wd TO wd + V(0, MIN(MAX(ka * ea:Y, -w1), w1), 0).
  }
  // the target's own rate fed forward (one SSME: the roll free)
  LOCAL wf IS ascDap["wff"].
  LOCAL wfy IS 0.
  IF NOT ascDap["one"] { SET wfy TO VDOT(wf, ey). }
  SET wd TO wd + V(VDOT(wf, ex), wfy, VDOT(wf, ez)).
  IF ascDap["css"] { SET wd TO ascCssWd(ex, ey, ez, wd, w, dt). }   // the CSS axes' rates (lib_ascent_css)
  LOCAL ew IS wd - w.
  LOCAL ad IS ew * kr + ascDap["iw"] * ASC_DAP_KI.
  LOCAL af IS ascDap["aff"].
  LOCAL afy IS 0.
  IF NOT ascDap["one"] { SET afy TO VDOT(af, ey). }
  LOCAL afv IS V(VDOT(af, ex), afy, VDOT(af, ez)).
  IF ascDap["css"] { SET afv TO ascCssMask(afv). }       // the target's acceleration only in the AUTO axes
  SET ad TO ad + afv.
  IF ascDap["css"] {                                     // the stick axes' own (lib_ascent_css), the integral held there
    SET ad TO ascCssAd(ad, ascDap["iw"] * ASC_DAP_KI).
    SET ew TO ascCssIw(ew).
  }
  LOCAL ih IS ascDap["I"].
  LOCAL td IS V(ih[0] * ad:X, ih[1] * ad:Y + ih[3] * ad:Z, ih[3] * ad:Y + ih[2] * ad:Z).
  LOCAL rhs IS td - ascDap["t0"].
  LOCAL u IS V(VDOT(ascDap["r0"], rhs), VDOT(ascDap["r1"], rhs), VDOT(ascDap["r2"], rhs)).
  IF MAX(ABS(u:X), MAX(ABS(u:Y), ABS(u:Z))) > 1 {
    // saturated: the roll clipped, pitch and yaw solved with it (and scaled together into -1..1)
    LOCAL bm IS ascDap["B"].
    LOCAL ur IS MAX(-1, MIN(1, u:Y)).
    LOCAL a0 IS rhs:X - bm[1]:X * ur.
    LOCAL a2 IS rhs:Z - bm[1]:Z * ur.
    LOCAL d2 IS bm[0]:X * bm[2]:Z - bm[2]:X * bm[0]:Z.
    LOCAL upi IS 0.
    LOCAL uy IS 0.
    IF ABS(d2) > 1 {
      SET upi TO (a0 * bm[2]:Z - bm[2]:X * a2) / d2.
      SET uy TO (bm[0]:X * a2 - a0 * bm[0]:Z) / d2.
    }
    LOCAL mx IS MAX(ABS(upi), ABS(uy)).
    IF mx > 1 {
      SET upi TO upi / mx.
      SET uy TO uy / mx.
    }
    SET u TO V(upi, ur, uy).
    SET ascDap["sat"] TO ascDap["sat"] + 1.
  } ELSE {
    SET ascDap["iw"] TO ascDap["iw"] + ew * dt.     // no wind-up while saturated
  }
  SET ascDap["u"] TO u.
  SET ascDap["e"] TO ea.
  SET ascDap["w"] TO w.
  IF ascDap["fbw"] {                         // through the FBW handler (it reads the stick)
    ADDONS:KALS:FBW3(u:X, u:Y, u:Z).
  } ELSE {
    SET SHIP:CONTROL:PITCH TO u:X.
    SET SHIP:CONTROL:ROLL TO u:Y.
    SET SHIP:CONTROL:YAW TO u:Z.
  }
}
