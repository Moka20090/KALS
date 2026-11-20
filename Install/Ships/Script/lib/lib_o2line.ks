// lib_o2line.ks -- the OMS THRUST LINE for the burn guidance (ops2q's PEG burns, shuttle_exec's plan / node burns).
// What every OMS burn steers is the engines' ACTUAL thrust, not the body axis: the part's FACING:FOREVECTOR (all kOS offers)
// leaves out the gimbal, and the gimbal trims the thrust through the c.g. (the loadout's c.g. moves it by up to ~1.4 deg), so a
// burn that holds the body axis on the burn vector thrusts off it by the trim. ADDONS:KALS:OMSLINE (KalsAddon.OmsLine.cs) gives
// the true line: the thrust they give now ("meas"), or before any thrust each engine's thrust through the c.g. within the
// gimbal's range ("trim"). This library asks it, filters it for the steering, and turns the control point so that the LINE lies
// on the burn direction (o2lAim: the control point's fore turned by the turn line -> burn direction; roll stays free, as for
// any bare steering vector). The crew's frame (SHIP:FACING, the attitudes shown, MNVR EXEC's rows) is untouched: only the
// vector handed to LOCK STEERING changes.
// WITHOUT the addon's OMSLINE (an older DLL, none) or with O2L_TRIM_ON FALSE every call says "not ok" and the callers fly their
// own line (the engines' part axes), the law as it was. Pure: the kOS VM runs it (tests/o2line_selftest.ks, whose O2L_FAKE_ON
// stands in for the addon).

GLOBAL O2L_TRIM_ON IS TRUE.                  // FALSE = every burn on the part axes, as before (the one-line rollback)
GLOBAL O2L_LINE_TAU IS 2.                    // s: o2lLag's time constant (no longer on the steering's path o2lSteer)
GLOBAL O2L_PRED_DEG IS 1.                    // deg: trim and measured lines further apart than this are logged
GLOBAL O2L_FAKE_ON IS FALSE.                 // the VM tests: o2lFake (a delegate (uids, mode) -> the addon's LIST) answers
GLOBAL O2L_FAKE IS 0.

// does the addon (or its stand-in) answer OMSLINE, and is the line wanted
FUNCTION o2lHave {
    IF NOT O2L_TRIM_ON { RETURN FALSE. }
    IF O2L_FAKE_ON { RETURN TRUE. }
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("OMSLINE").
}
FUNCTION o2lBit { PARAMETER n, k. RETURN MOD(FLOOR(n / 2 ^ k), 2) = 1. }
// the engines' UIDs (the addon matches them to the parts)
FUNCTION o2lUids {
    PARAMETER ens.
    LOCAL u IS LIST().
    FOR en IN ens { u:ADD(en:UID). }
    RETURN u.
}
// the line of the engines uids in mode ("meas" / "trim" / "auto"): LEXICON ok (a usable line), f (the force, kN, in the frame
// of SHIP:FACING's vectors), src (1 measured, 2 trim, 0 none), flags (the addon's: 4 clamped, 8 a UID missing, 16 a gimbal
// locked), n (engines), t (their thrust, kN), tq (the torque about the c.g., kN m)
FUNCTION o2lGet {
    PARAMETER uids, mode.
    LOCAL out IS LEXICON("ok", FALSE, "f", V(0, 0, 0), "src", 0, "flags", 0, "n", 0, "t", 0, "tq", V(0, 0, 0)).
    IF uids:LENGTH = 0 OR NOT o2lHave() { RETURN out. }
    LOCAL rs IS LIST().
    IF O2L_FAKE_ON { SET rs TO O2L_FAKE:CALL(uids, mode). }
    ELSE { SET rs TO ADDONS:KALS:OMSLINE(uids, mode). }
    IF rs:LENGTH < 9 { RETURN out. }
    LOCAL fl IS ROUND(rs[6]).
    SET out["flags"] TO fl.
    SET out["n"] TO ROUND(rs[7]).
    SET out["t"] TO rs[8].
    SET out["tq"] TO V(rs[3], rs[4], rs[5]).
    IF o2lBit(fl, 5) { RETURN out. }                       // no data
    LOCAL f IS V(rs[0], rs[1], rs[2]).
    IF f:MAG < 0.01 { RETURN out. }
    SET out["f"] TO f.
    SET out["src"] TO CHOOSE 1 IF o2lBit(fl, 0) ELSE 2.
    SET out["ok"] TO TRUE.
    RETURN out.
}

// rotate x by the rotation that takes the direction a onto the direction b (Rodrigues; the same turn as lib_o2peg's o2pRot, here
// so shuttle_exec needs no other library)
FUNCTION o2lRot {
    PARAMETER x, a, b.
    LOCAL au IS a:NORMALIZED. LOCAL bu IS b:NORMALIZED.
    LOCAL k IS VCRS(au, bu).
    LOCAL s IS k:MAG.
    LOCAL c IS VDOT(au, bu).
    IF s < 1E-9 { RETURN x. }
    SET k TO k / s.
    RETURN x * c + VCRS(k, x) * s + k * (VDOT(k, x) * (1 - c)).
}
// the vector for LOCK STEERING: fore (the control point's fore axis now) turned so that the thrust line lies on u
FUNCTION o2lAim {
    PARAMETER u, line, fore.
    RETURN o2lRot(fore, line, u):NORMALIZED.
}

// the steering's view of the line: a unit vector lagged by O2L_LINE_TAU. State LEXICON ("f" unit, "on" seeded)
FUNCTION o2lNew { RETURN LEXICON("f", V(0, 0, 0), "on", FALSE). }
FUNCTION o2lSeed {                           // start the lag on this line (the trim before the ignition: no step at the first thrust)
    PARAMETER st, line.
    IF line:MAG < 1E-9 { RETURN. }
    SET st["f"] TO line:NORMALIZED.
    SET st["on"] TO TRUE.
}
FUNCTION o2lLag {                            // one step of dt s toward line; returns the lagged unit line
    PARAMETER st, line, dt.
    IF line:MAG < 1E-9 { RETURN st["f"]. }
    IF NOT st["on"] { o2lSeed(st, line). RETURN st["f"]. }
    LOCAL k IS 1 - CONSTANT:E ^ (-MAX(dt, 0) / MAX(O2L_LINE_TAU, 0.001)).
    SET st["f"] TO (st["f"] + (line:NORMALIZED - st["f"]) * k):NORMALIZED.
    RETURN st["f"].
}
// the angle (deg) between two lines
FUNCTION o2lAng {
    PARAMETER a, b.
    LOCAL c IS VDOT(a:NORMALIZED, b:NORMALIZED).
    RETURN ARCCOS(MAX(-1, MIN(1, c))).
}
// a line's pitch below the fore axis and its yaw to the star side, deg, in the control point's axes (the burn log's columns)
FUNCTION o2lPY {
    PARAMETER line, fore, star, top.
    LOCAL u IS line:NORMALIZED.
    RETURN LIST(ARCTAN2(-VDOT(u, top), VDOT(u, fore)), ARCTAN2(VDOT(u, star), VDOT(u, fore))).
}

// THE LINE THE STEERING LAYS ON THE BURN DIRECTION = the addon's TRIM (each engine's thrust through the c.g. now, within
// its gimbal's range, from the engines' NEUTRAL axes): fixed to the body (the orbiter's turn turns it at once) and free of the
// gimbal's own control deflection. Neither may reach the steering's line: The old law steered the MEASURED line lagged 2 s in the inertial
// frame, the controller closed its loop through that lag and every gimbal kick moved its own target; every OMS burn of 11-08
// wobbled (6 s) and ran away near the cut. The measured line stays for the sensed dV (o2lSense) and the PRED-MEAS log.
// fb = the caller's line without the addon (the engines' part axes): the old law.
FUNCTION o2lSteer {
    PARAMETER uids, fb.
    RETURN o2lLine(uids, "trim", fb).
}
// the line to steer by: the addon's (mode "meas" / "trim" / "auto") when it answers, else fb (the caller's own line: the engines'
// part axes by their thrust, the law as it was)
FUNCTION o2lLine {
    PARAMETER uids, mode, fb.
    LOCAL rs IS o2lGet(uids, mode).
    IF rs["ok"] { RETURN rs["f"]. }
    RETURN fb.
}
// the thrust the engines gave (kN, a vector in the frame of SHIP:FACING's) for the sensed dV: the addon's measured force when
// it answers, else fb (the part axes by their thrust)
FUNCTION o2lSense {
    PARAMETER uids, fb.
    LOCAL rs IS o2lGet(uids, "meas").
    IF rs["ok"] { RETURN rs["f"]. }
    RETURN fb.
}
