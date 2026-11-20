// lib_o2dap.ks -- ops2q's ON-ORBIT DAP. Pure: vectors in, the
// jets' command out (no vessel), so the kOS VM flies it (tests/o2dap_selftest.ks, a rigid body).
// coproc/O2Dap.cs is o2dTick's 1:1 C# twin (checked call by call on the selftest): with KalsCoproc's O2DAPSET ops2q's
// DAP flies in the fly-by-wire handler every physics tick (KalsAddon.O2Dap.cs); this file stays the reference and the fallback.
// AUTO: the computer flies the HOLD and the MNVRs. HOLD INRTL (the attitude fixed in inertial space), LVLH (fixed against
// the local vertical and the orbit, turning at orbital rate), TRACK (a body axis kept on a line of sight: the Earth's
// centre, the Sun) or FREE (free drift: no jet). MNVR turns to a target attitude about one axis (the eigenaxis) at RATE,
// then holds it in the HOLD's frame (INRTL / LVLH; from TRACK or FREE the hold becomes INRTL). STOP holds the attitude
// it has (a MNVR or a track stopped; FREE stopped = INRTL).
// CSS (the real orbiter's MAN mode, the pilot's stick): out of the detent the stick commands a rate, its deflection x
// RATE on each axis (pitch, roll, yaw), relative to the HOLD's frame; in the detent the jets brake the rate to
// nothing (the three axes as one, the rate loop's own time constant; within O2D_BRK of rest) and the attitude it stops
// at is held, not the one it was released on: no coast-back, no overshoot (FREE: no jet). In AUTO the stick out of the detent downmodes to CSS (the real orbiter's).
// going to CSS (the page's pick or the stick's downmode)
// while the hold is TRACK makes the hold LVLH on the attitude CSS leaves it at; TRACK picked in CSS puts the DAP in AUTO.
// DB (deg) and RATE (deg/s) are the crew's: fine vs coarse.
// The reference is kept as the orbiter's FORE and TOP in the frame's basis (lib_arm's ARM-STAB way: INRTL from
// SOLARPRIMEVECTOR made square to the body's spin axis, both turn with KSP's frame below the inverse-rotation altitude;
// LVLH from the position and the orbital velocity). The frame's own turn rate (LVLH ~0.067 deg/s, INRTL's in a rotating
// KSP frame) is taken from the basis's change each tick, filtered, and fed forward; TRACK's line of sight's turn too.
// The law: past 2 x DB of total error (and through a MNVR) the eigenaxis rate, the rate back = O2D_RMIN + O2D_K x the
// error past DB, at most RATE; inside it per axis (the real DAP's phase plane): no rate inside DB, past it the same
// rate back on that axis; no jet within O2D_RDB of the rate wanted; the jets' command = the rate error / (O2D_TAU x the
// axis's authority, deg/s2 a full command: KalsCoproc's FBWAUTH), capped so the turn's acceleration stays <= O2D_ACC
// (the eigenaxis and CSS: the deadband on the rate error's size and the caps scaling all three, so the turn's axis holds).
// Signs as the DAP's (lib_arm larHold*): + pitch nose up, + roll right, + yaw nose right; a turn vector in VCRS sense
// (dv/dt = VCRS(w, v), as SHIP:ANGULARVEL) is pitch -w.star, roll -w.fore, yaw +w.top.
// The host's geometry g = LIST(pB the position from the body's centre, vO the orbital velocity, the prime vector, the
// body's spin axis); the orbiter's axes s, t, f are its control point's (SHIP:FACING's STAR / TOP / FORE).

GLOBAL O2D_D2R IS CONSTANT:PI / 180.
GLOBAL O2D_DB0 IS 1.0.                       // deg: the attitude deadband at the start (the page's DB)
GLOBAL O2D_RATE0 IS 0.5.                     // deg/s: the MNVR / CSS rate at the start (the page's RATE)
GLOBAL O2D_K IS 0.15.                        // deg/s per deg: the rate back per degree past the deadband...
GLOBAL O2D_RMIN IS 0.04.                     // deg/s: ...plus this (> the rate deadband, so the jets fire past DB)
GLOBAL O2D_RDB IS 0.02.                      // deg/s: no jet within this of the rate wanted
GLOBAL O2D_TAU IS 1.5.                       // s: the rate loop's time constant
GLOBAL O2D_ACC IS 2.                         // deg/s2: the largest angular acceleration commanded
GLOBAL O2D_WF IS 1.                          // s: the frame's (and the track's) own turn rate filtered over this
GLOBAL O2D_EIG IS 2.                         // x DB: past this total error the eigenaxis law (as a MNVR)
GLOBAL O2D_DET IS 0.05.                      // the stick's detent (each axis, -1..1)
GLOBAL O2D_BRK IS 0.03.                      // deg/s: the stick released: the rate is braked to within this, then the attitude is held
GLOBAL O2D_TINY IS 1E-9.
GLOBAL O2D_UIMAX IS 0.4.                     // deg/s2: the hold's integral trim never exceeds this per axis
GLOBAL O2D_SEEDGT IS 2.0.                   // s after a seeded trim in which the sign guard watches the pitch error
GLOBAL O2D_SEEDGTH IS 0.05.                  // deg: the seed is dropped when the pitch error grew this much in the seed's direction (the seed pushes the wrong way)
GLOBAL O2D_KIFLOOR IS 0.02.                  // deg: the integral sees the error past this floor (past the deadband, so it stopped at the deadband's edge: the 0.3-0.5 deg held offset of every burn)

FUNCTION o2dNew {                            // the DAP's state: AUTO, FREE until the host holds an attitude
    PARAMETER db IS O2D_DB0, rate IS O2D_RATE0.
    RETURN LEXICON("mode", "AUTO", "hold", "FREE", "rf", "INRTL", "act", "FREE", "ref", LIST(V(0, 0, 1), V(0, 1, 0)),
        "bp", LIST(), "wf", V(0, 0, 0), "wt", V(0, 0, 0), "tk", FALSE, "ax", V(0, 0, 1), "db", db, "rate", rate,
        "msg", "", "e", V(0, 0, 0), "w", V(0, 0, 0), "u", V(0, 0, 0), "ea", 0,
        "k", O2D_K, "tau", O2D_TAU, "ki", 0, "ui", V(0, 0, 0),
        "seedt", 0, "seedsg", 1, "seede0", 0, "seeds", FALSE, "seeddrop", 0, "uis", 0, "uisN", 0).     // The seeded trim's guard (uis / uisN: the seed ops2q sends the C# DAP and its counter)      // The hold's gains and integral (ki 0 = none; ops2q sets them for the burn)
}

// The burn's pitch trim SEEDED at the ignition (a physically signed value the host computed: half the trim the last burn learned), ui.x = sdv (at most O2D_UIMAX). For O2D_SEEDGT s
// o2dTick watches the pitch error: grown past O2D_SEEDGTH from its first value IN THE SEED'S DIRECTION (a positive seed pushes the error negative), the seed was the wrong sign: ui.x -> 0, st["seeddrop"] 1,
// and the law flies as unseeded. MNVR / FREE / ki 0 clear it (o2dTick zeroes ui there).
FUNCTION o2dSeed {
    PARAMETER st, sdv.
    LOCAL x IS MAX(-O2D_UIMAX, MIN(O2D_UIMAX, sdv)).
    SET st["ui"] TO V(x, st["ui"]:Y, st["ui"]:Z).
    SET st["seedt"] TO CHOOSE O2D_SEEDGT IF x <> 0 ELSE 0.
    SET st["seedsg"] TO CHOOSE 1 IF x > 0 ELSE -1.
    SET st["seeds"] TO FALSE.
    SET st["seeddrop"] TO 0.
}

// ---- the geometry
FUNCTION o2dBasis {                          // the frame's basis LIST(e1, e2, e3), unit and square (lib_arm larHoldBasis)
    PARAMETER md, g.
    LOCAL pB IS g[0]. LOCAL vO IS g[1].
    IF md = "LVLH" {
        LOCAL eu IS pB:NORMALIZED.
        LOCAL en IS VCRS(pB, vO):NORMALIZED.
        RETURN LIST(eu, VCRS(en, eu), en).
    }
    LOCAL sp IS g[3].
    LOCAL ez IS CHOOSE sp:NORMALIZED IF sp:MAG > O2D_TINY ELSE VCRS(pB, vO):NORMALIZED.
    LOCAL ex IS (g[2] - ez * VDOT(g[2], ez)):NORMALIZED.
    RETURN LIST(ex, VCRS(ez, ex), ez).
}
FUNCTION o2dIn { PARAMETER b, x. RETURN V(VDOT(x, b[0]), VDOT(x, b[1]), VDOT(x, b[2])). }
FUNCTION o2dOut { PARAMETER b, c. RETURN b[0] * c:X + b[1] * c:Y + b[2] * c:Z. }
FUNCTION o2dTurn {                           // x turned by the turn vector qv (rad: the axis, its size the angle; VCRS sense)
    PARAMETER x, qv.
    LOCAL a IS qv:MAG.
    IF a < O2D_TINY { RETURN x. }
    LOCAL k IS qv / a.
    LOCAL ad IS a / O2D_D2R.
    RETURN x * COS(ad) + VCRS(k, x) * SIN(ad) + k * (VDOT(k, x) * (1 - COS(ad))).
}
FUNCTION o2dRotAB {                          // the least turn vector (rad, VCRS sense) taking a's direction onto b's
    PARAMETER a, b.
    LOCAL au IS a:NORMALIZED. LOCAL bu IS b:NORMALIZED.
    LOCAL k IS VCRS(au, bu).
    LOCAL sn IS k:MAG.
    LOCAL cs IS VDOT(au, bu).
    IF sn < O2D_TINY {
        IF cs > 0 { RETURN V(0, 0, 0). }
        LOCAL pp IS VCRS(au, V(1, 0, 0)).    // opposite: half a turn about any square axis
        IF pp:MAG < 0.1 { SET pp TO VCRS(au, V(0, 1, 0)). }
        RETURN pp:NORMALIZED * CONSTANT:PI.
    }
    RETURN k / sn * (ARCTAN2(sn, cs) * O2D_D2R).
}
// the turn vector (rad, VCRS sense) that takes the frame (f, t) to (fR, tR), exact at any angle: half the sum of
// e x e' over the three axes = sin(angle) x the axis (lib_arm larAttErr), the angle's cosine from the trace
FUNCTION o2dRotV {
    PARAMETER f, t, fR, tR.
    LOCAL n IS VCRS(t, f). LOCAL nR IS VCRS(tR, fR).
    LOCAL sv IS 0.5 * (VCRS(f, fR) + VCRS(t, tR) + VCRS(n, nR)).
    LOCAL cs IS (VDOT(f, fR) + VDOT(t, tR) + VDOT(n, nR) - 1) / 2.
    LOCAL sn IS sv:MAG.
    IF sn < 1E-7 {
        IF cs > 0 { RETURN sv. }
        LOCAL k IS f + fR.                   // half a turn: the axis is what an axis and its turned self share
        IF k:MAG < 0.1 { SET k TO t + tR. }
        IF k:MAG < 0.1 { SET k TO n + nR. }
        RETURN k:NORMALIZED * CONSTANT:PI.
    }
    RETURN sv / sn * (ARCTAN2(sn, cs) * O2D_D2R).
}
FUNCTION o2dPry {                            // a turn vector as the DAP's V(pitch, roll, yaw) on the axes s, t, f
    PARAMETER w, s, t, f.
    RETURN V(-VDOT(w, s), -VDOT(w, f), VDOT(w, t)).
}

// ---- the attitude in LVLH as the page shows it: LIST(roll, pitch, yaw) deg of the axes (fore, star, top) in the frame
// fr = LIST(X forward, Y right of the motion, Z down) (lib_o2orb o2Lvlh): pitch the nose above the horizontal, yaw the
// nose right of X, roll the wings' bank (the star wing down = + roll)
FUNCTION o2dRpy {
    PARAMETER fo, st, tp, fr.
    LOCAL pt IS ARCSIN(MAX(-1, MIN(1, -VDOT(fo, fr[2])))).
    LOCAL yw IS ARCTAN2(VDOT(fo, fr[1]), VDOT(fo, fr[0])).
    LOCAL rl IS ARCTAN2(VDOT(st, fr[2]), VDOT(-tp, fr[2])).
    RETURN LIST(rl, pt, yw).
}
FUNCTION o2dFromRpy {                        // o2dRpy's inverse: LIST(fore, top) for roll, pitch, yaw (deg) in fr
    PARAMETER rl, pt, yw, fr.
    LOCAL fo IS fr[0] * (COS(pt) * COS(yw)) + fr[1] * (COS(pt) * SIN(yw)) - fr[2] * SIN(pt).
    LOCAL b0 IS fr[2] - fo * VDOT(fo, fr[2]).   // the belly at roll 0: down, square to the nose
    IF b0:MAG < 1E-6 { SET b0 TO (fr[0] * COS(yw) + fr[1] * SIN(yw)) * (CHOOSE 1 IF pt > 0 ELSE -1). }
    SET b0 TO b0:NORMALIZED.
    LOCAL s0 IS VCRS(-b0, fo).               // the star wing at roll 0 (VCRS(top, fore) = star)
    LOCAL bl IS b0 * COS(rl) - s0 * SIN(rl).
    RETURN LIST(fo, -bl).
}
// ---- The burn's roll, TV ROLL (the real OMS / DEORB MNVR's item): the orbiter's roll about the THRUST LINE l, measured
// from the local vertical (dn: down, toward the Earth's centre), the top's component square to the line against the
// belly's: 0 = heads up (the top away from the Earth), 180 = heads down (the top toward it); + roll = the star wing down
// (o2dRpy / o2dFromRpy's sense: o2dFromRpy's belly at roll 0 and its star wing, here about the line instead of the nose).
FUNCTION o2dTvRoll {                         // deg 0 .. 360 (-1: the line is along the vertical, or the top along the line: no roll)
    PARAMETER l, t, dn.
    LOCAL u IS l:NORMALIZED.
    LOCAL b0 IS dn - u * VDOT(dn, u).
    LOCAL tp IS t - u * VDOT(t, u).
    IF b0:MAG < 1E-3 OR tp:MAG < 1E-3 { RETURN -1. }
    SET b0 TO b0:NORMALIZED.
    SET tp TO tp:NORMALIZED.
    LOCAL s0 IS VCRS(-b0, u).                // the star wing at roll 0
    LOCAL rl IS ARCTAN2(VDOT(tp, s0), -VDOT(tp, b0)).
    RETURN rl - 360 * FLOOR(rl / 360).
}
// the burn attitude LIST(fore, top): the attitude (f0, t0) (the orbiter's now, the line l read in it) turned by the least
// turn that puts the thrust line l on the aim u (the aim of today's o2pAim), then rolled about u until the roll is rl (TV ROLL,
// deg) from the down dn. A line along the vertical: no roll to set, the least turn alone.
FUNCTION o2dTvAtt {
    PARAMETER f0, t0, l, u, dn, rl.
    LOCAL q1 IS o2dRotAB(l, u).
    LOCAL f1 IS o2dTurn(f0, q1).
    LOCAL t1 IS o2dTurn(t0, q1).
    LOCAL uu IS u:NORMALIZED.
    LOCAL b0 IS dn - uu * VDOT(dn, uu).
    LOCAL tp IS t1 - uu * VDOT(t1, uu).
    IF b0:MAG < 1E-3 OR tp:MAG < 1E-3 { RETURN LIST(f1, t1). }
    SET b0 TO b0:NORMALIZED.
    SET tp TO tp:NORMALIZED.
    LOCAL s0 IS VCRS(-b0, uu).
    LOCAL tT IS -(b0 * COS(rl) - s0 * SIN(rl)).      // the top's component square to the line, rolled rl
    LOCAL a IS ARCTAN2(VDOT(VCRS(tp, tT), uu), VDOT(tp, tT)).
    LOCAL w IS uu * (a * O2D_D2R).
    RETURN LIST(o2dTurn(f1, w), o2dTurn(t1, w)).
}
FUNCTION o2dWrap { PARAMETER x. RETURN x - 360 * FLOOR((x + 180) / 360). }   // to -180 .. 180

// the control point's axes (cf, ct) taken where the root's (rf, rt) go to (fT, tT): one rigid body
FUNCTION o2dMap {
    PARAMETER fT, tT, rf, rt, cf, ct.
    LOCAL qv IS o2dRotV(rf, rt, fT, tT).
    RETURN LIST(o2dTurn(cf, qv), o2dTurn(ct, qv)).
}

// ---- the crew's actions (f, t the orbiter's axes now, g the geometry now)
FUNCTION o2dRefSet {                         // the reference = (f, t), in the frame rf's basis now
    PARAMETER st, f, t, g.
    LOCAL b IS o2dBasis(st["rf"], g).
    SET st["ref"] TO LIST(o2dIn(b, f), o2dIn(b, t)).
}
FUNCTION o2dFrame {                          // the reference's frame: a new one restarts its rate
    PARAMETER st, rf.
    IF rf <> st["rf"] { SET st["rf"] TO rf. SET st["bp"] TO LIST(). SET st["wf"] TO V(0, 0, 0). }
    SET st["wt"] TO V(0, 0, 0).
}
FUNCTION o2dHold {                           // HOLD md (INRTL / LVLH / FREE) on the attitude now
    PARAMETER st, md, f, t, g.
    SET st["hold"] TO md.
    o2dFrame(st, CHOOSE md IF md = "LVLH" ELSE "INRTL").
    o2dRefSet(st, f, t, g).
    SET st["act"] TO CHOOSE "FREE" IF md = "FREE" ELSE "HOLD".
}
FUNCTION o2dTrack {                          // HOLD TRACK: the body axis ax (V(star, top, fore) components) on a line of sight
    PARAMETER st, ax, f, t, g, rr IS LIST().   // rr: the reference o2dTrackRef built (omicron), else the attitude now (f, t)
    SET st["hold"] TO "TRACK".
    IF st["mode"] = "CSS" { SET st["mode"] TO "AUTO". SET st["msg"] TO "TRACK: DAP TO AUTO". }   // CSS and TRACK never both
    o2dFrame(st, "INRTL").
    SET st["ax"] TO ax:NORMALIZED.
    SET st["tk"] TO FALSE.
    IF rr:LENGTH = 2 { o2dRefSet(st, rr[0], rr[1], g). } ELSE { o2dRefSet(st, f, t, g). }
    SET st["act"] TO "TRK".
}
// OMICRON: the attitude (fore, top; world vectors) with the body axis ax on the line of sight los and the roll about
// it fully defined: the second body axis p2 (square to ax; both V(star, top, fore) components) lies om deg (the VCRS sense
// about los) from the zero direction upv (the orbital velocity for the Earth: -Z to the Earth with p2 = +X is the nose
// forward; the body's spin axis for the Sun), taken square to los. TRACK's reference starts there, so the track's TGT is
// defined in all three axes (the real UNIV PTG's omicron, default 0); the DAP's least turn then keeps that roll.
FUNCTION o2dTrackRef {
    PARAMETER ax, p2, los, upv, om.
    LOCAL a IS ax:NORMALIZED.
    LOCAL p IS (p2 - a * VDOT(p2, a)):NORMALIZED.
    LOCAL l IS los:NORMALIZED.
    LOCAL u IS upv - l * VDOT(upv, l).
    IF u:MAG < 0.01 * MAX(upv:MAG, O2D_TINY) { SET u TO VCRS(l, V(0, 0, 1)). IF u:MAG < 0.1 { SET u TO VCRS(l, V(0, 1, 0)). } }
    SET u TO o2dTurn(u:NORMALIZED, l * (om * O2D_D2R)).
    LOCAL ba IS VCRS(a, p).
    LOCAL wa IS VCRS(l, u).                  // a body vector c goes to l (c.a) + u (c.p) + wa (c.ba): fore c = Z, top c = Y
    RETURN LIST(l * a:Z + u * p:Z + wa * ba:Z, l * a:Y + u * p:Y + wa * ba:Y).
}
FUNCTION o2dMnvr {                           // MNVR to the attitude (fT, tT), then hold it (INRTL / LVLH)
    PARAMETER st, fT, tT, g.
    IF st["hold"] = "TRACK" OR st["hold"] = "FREE" { SET st["hold"] TO "INRTL". }
    o2dFrame(st, st["hold"]).
    o2dRefSet(st, fT, tT, g).
    SET st["act"] TO "MNVR".
}
FUNCTION o2dStop {                           // STOP: hold the attitude now (a track or free drift stopped = INRTL)
    PARAMETER st, f, t, g.
    IF st["hold"] = "TRACK" OR st["hold"] = "FREE" { SET st["hold"] TO "INRTL". }
    o2dFrame(st, st["hold"]).
    o2dRefSet(st, f, t, g).
    SET st["act"] TO "HOLD".
}
FUNCTION o2dMode {                           // AUTO / CSS; a MNVR stops at the change (the attitude now held)
    PARAMETER st, md, f, t, g.
    IF md = st["mode"] { RETURN. }
    SET st["mode"] TO md.
    IF md = "CSS" AND st["hold"] = "TRACK" { o2dHold(st, "LVLH", f, t, g). }   // CSS and TRACK never both: LVLH where CSS leaves it
    IF st["act"] = "MNVR" { o2dRefSet(st, f, t, g). SET st["act"] TO "HOLD". }
}

// ---- one axis: the jets' command (-1..1) for the rate error dw (deg/s), the authority au (deg/s2 a full command)
FUNCTION o2dJet {
    PARAMETER dw, au, tau IS O2D_TAU.
    IF ABS(dw) <= O2D_RDB OR au <= O2D_TINY { RETURN 0. }
    LOCAL um IS MIN(1, O2D_ACC / au).
    RETURN MAX(-um, MIN(um, (dw - O2D_RDB * (CHOOSE 1 IF dw > 0 ELSE -1)) / (tau * au))).
}
FUNCTION o2dJetV {                           // the three axes as one (the eigenaxis, CSS): the rate deadband on the rate
    PARAMETER dw, au, tau IS O2D_TAU.                        // error's size, the caps scaling the whole command (the turn's axis kept)
    LOCAL m IS dw:MAG.
    IF m <= O2D_RDB { RETURN V(0, 0, 0). }
    LOCAL dr IS dw * (1 - O2D_RDB / m).
    LOCAL u IS V(o2dJetU(dr:X, au:X, tau), o2dJetU(dr:Y, au:Y, tau), o2dJetU(dr:Z, au:Z, tau)).
    LOCAL k IS MAX(o2dJetK(u:X, au:X), MAX(o2dJetK(u:Y, au:Y), o2dJetK(u:Z, au:Z))).
    IF k > 1 { RETURN u / k. }
    RETURN u.
}
FUNCTION o2dJetU { PARAMETER d, au, tau IS O2D_TAU. IF au <= O2D_TINY { RETURN 0. } RETURN d / (tau * au). }
FUNCTION o2dJetK { PARAMETER u, au. IF au <= O2D_TINY { RETURN 0. } RETURN ABS(u) / MIN(1, O2D_ACC / au). }
FUNCTION o2dBack {                           // the rate back (deg/s, signed) on an error e (deg) past the deadband db
    PARAMETER e, db, rmax, k IS O2D_K.
    IF ABS(e) <= db { RETURN 0. }
    RETURN MIN(rmax, O2D_RMIN + k * (ABS(e) - db)) * (CHOOSE 1 IF e > 0 ELSE -1).
}
// The hold's INTEGRAL TRIM (a constant torque the P law cannot remove: the OMS thrust line off the c.g. pitched the burn
// 1.7 deg for 30 s). Per axis, in acceleration space (deg/s2, so it does not depend on the
// authority): ui += ki x (the error past O2D_KIFLOOR; past DB) x dt, at most O2D_UIMAX; no step when that axis's command is at its cap and the error
// pushes the same way (anti-windup); the trim ui/au is added to the command, capped as the law's. Only in a steady HOLD in AUTO
// (o2dTick zeroes ui in every other act / mode, and when ki is 0).
FUNCTION o2dTrim {
    PARAMETER st, e, u, au, dt.
    LOCAL ea IS LIST(e:X, e:Y, e:Z).
    LOCAL ua IS LIST(u:X, u:Y, u:Z).
    LOCAL aa IS LIST(au:X, au:Y, au:Z).
    LOCAL ia IS LIST(st["ui"]:X, st["ui"]:Y, st["ui"]:Z).
    LOCAL db IS st["db"].
    FOR i IN RANGE(3) {
        IF aa[i] <= O2D_TINY { SET ia[i] TO 0. }
        ELSE {
            LOCAL um IS MIN(1, O2D_ACC / aa[i]).
            LOCAL ed IS 0.
            IF ABS(ea[i]) > O2D_KIFLOOR { SET ed TO (ABS(ea[i]) - O2D_KIFLOOR) * (CHOOSE 1 IF ea[i] > 0 ELSE -1). }     // The full error, inside the deadband too
            LOCAL sat IS ABS(ua[i]) >= um - 1E-9 AND ed * ua[i] > 0.
            IF NOT sat AND dt > 0 { SET ia[i] TO MAX(-O2D_UIMAX, MIN(O2D_UIMAX, ia[i] + st["ki"] * ed * dt)). }
            SET ua[i] TO MAX(-um, MIN(um, ua[i] + ia[i] / aa[i])).
        }
    }
    SET st["ui"] TO V(ia[0], ia[1], ia[2]).
    RETURN V(ua[0], ua[1], ua[2]).
}

// ---- one tick: the geometry g, the orbiter's axes s, t, f, its turn rate w (rad/s, VCRS sense), the authority au
// V(pitch, roll, yaw) deg/s2, dt s, the stick V(pitch, roll, yaw) -1..1 (V(0, 0, 0) when the stick is the page's),
// the line of sight los (TRACK; V(0, 0, 0) none) -> the jets V(pitch, roll, yaw) -1..1. Leaves in st: act, e (the
// error V(p, r, y) deg), ea (its angle), w (the rate relative to the reference V(p, r, y) deg/s), u, msg (an event).
FUNCTION o2dTick {
    PARAMETER st, g, s, t, f, w, au, dt, stick, los.
    LOCAL out IS MAX(ABS(stick:X), MAX(ABS(stick:Y), ABS(stick:Z))) > O2D_DET.
    LOCAL dn IS FALSE.
    IF out AND st["mode"] = "AUTO" { SET st["mode"] TO "CSS". SET st["msg"] TO "RHC OUT OF DETENT: CSS". SET dn TO TRUE. }
    IF st["mode"] = "CSS" AND st["hold"] = "TRACK" {   // CSS and TRACK never both: the hold becomes LVLH on the attitude now
        o2dHold(st, "LVLH", f, t, g).
        IF NOT dn { SET st["msg"] TO "". }   // The CSS: TRACK OFF, HOLD LVLH texts are deleted (the twin of O2Dap.cs)
    }
    LOCAL b IS o2dBasis(st["rf"], g).
    IF dt > 0 AND st["bp"]:LENGTH = 3 {
        LOCAL bp IS st["bp"].
        SET st["wf"] TO st["wf"] + (o2dRotV(bp[0], bp[1], b[0], b[1]) / dt - st["wf"]) * MIN(1, dt / O2D_WF).
    }
    SET st["bp"] TO b.
    LOCAL wr IS st["wf"].
    LOCAL u IS V(0, 0, 0).
    IF st["mode"] = "CSS" AND out {          // the rate command; the reference follows (held where released)
        SET st["ref"] TO LIST(o2dIn(b, f), o2dIn(b, t)).
        SET st["act"] TO "RATE".
        LOCAL wl IS o2dPry(w - wr, s, t, f) / O2D_D2R.
        LOCAL wc IS stick * st["rate"].
        SET u TO o2dJetV(wc - wl, au, st["tau"]).
        SET st["ui"] TO V(0, 0, 0).
        SET st["e"] TO V(0, 0, 0). SET st["ea"] TO 0. SET st["w"] TO wl. SET st["u"] TO u.
        RETURN u.
    }
    IF st["act"] = "RATE" {
        IF st["hold"] = "FREE" OR st["hold"] = "TRACK" { SET st["act"] TO CHOOSE "FREE" IF st["hold"] = "FREE" ELSE "TRK". }
        ELSE {                               // the stick released: the rate braked to nothing, the attitude it stops at held
            LOCAL wb IS o2dPry(w - wr, s, t, f) / O2D_D2R.
            SET st["ref"] TO LIST(o2dIn(b, f), o2dIn(b, t)).
            IF wb:MAG > O2D_BRK {
                SET u TO o2dJetV(-wb, au, st["tau"]).
                SET st["ui"] TO V(0, 0, 0).
                SET st["e"] TO V(0, 0, 0). SET st["ea"] TO 0. SET st["w"] TO wb. SET st["u"] TO u.
                RETURN u.
            }
            SET st["act"] TO "HOLD".
        }
    }
    IF st["hold"] = "FREE" {
        SET st["act"] TO "FREE".
        SET st["ui"] TO V(0, 0, 0).
        SET st["e"] TO V(0, 0, 0). SET st["ea"] TO 0. SET st["w"] TO o2dPry(w - wr, s, t, f) / O2D_D2R. SET st["u"] TO u.
        RETURN u.
    }
    LOCAL fR IS o2dOut(b, st["ref"][0]).
    LOCAL tR IS o2dOut(b, st["ref"][1]).
    IF st["hold"] = "TRACK" AND los:MAG > O2D_TINY {   // the reference turned (least) to put its axis on the line of sight
        LOCAL ax IS st["ax"].
        LOCAL aR IS VCRS(tR, fR) * ax:X + tR * ax:Y + fR * ax:Z.
        LOCAL qv IS o2dRotAB(aR, los).
        SET fR TO o2dTurn(fR, qv).
        SET tR TO o2dTurn(tR, qv).
        SET st["ref"] TO LIST(o2dIn(b, fR), o2dIn(b, tR)).
        IF dt > 0 AND st["tk"] { SET st["wt"] TO st["wt"] + (qv / dt - st["wt"]) * MIN(1, dt / O2D_WF). }
        SET st["tk"] TO TRUE.                // the first turn is the acquisition, not a rate
        SET wr TO wr + st["wt"].
    }
    LOCAL ev IS o2dRotV(f, t, fR, tR).
    LOCAL ea IS ev:MAG / O2D_D2R.
    LOCAL e IS o2dPry(ev, s, t, f) / O2D_D2R.
    LOCAL wl IS o2dPry(w - wr, s, t, f) / O2D_D2R.
    LOCAL db IS st["db"].
    LOCAL wasMnvr IS st["act"] = "MNVR".      // A tick that starts in a MNVR has no trim (it clears, even when the MNVR completes in it)
    IF st["act"] = "MNVR" AND ea <= db { SET st["act"] TO "HOLD". SET st["msg"] TO "MNVR COMPLETE". }
    LOCAL wc IS V(0, 0, 0).
    IF st["act"] = "MNVR" OR ea > O2D_EIG * db {      // the eigenaxis: one turn at the rate, the three axes as one
        SET u TO o2dJetV(e * (ABS(o2dBack(ea, db, st["rate"], st["k"])) / MAX(ea, O2D_TINY)) - wl, au, st["tau"]).
    } ELSE {                                 // the phase plane, each axis
        LOCAL wc IS V(o2dBack(e:X, db, st["rate"], st["k"]), o2dBack(e:Y, db, st["rate"], st["k"]), o2dBack(e:Z, db, st["rate"], st["k"])).
        SET u TO V(o2dJet(wc:X - wl:X, au:X, st["tau"]), o2dJet(wc:Y - wl:Y, au:Y, st["tau"]), o2dJet(wc:Z - wl:Z, au:Z, st["tau"])).
    }
    IF st["ki"] > 0 AND NOT wasMnvr AND st["act"] = "HOLD" AND st["mode"] = "AUTO" {
        IF st["seedt"] > 0 {                 // The seed's sign guard
            IF NOT st["seeds"] { SET st["seede0"] TO e:X. SET st["seeds"] TO TRUE. }
            IF (e:X - st["seede0"]) * st["seedsg"] < -O2D_SEEDGTH {
                SET st["ui"] TO V(0, st["ui"]:Y, st["ui"]:Z). SET st["seedt"] TO 0. SET st["seeddrop"] TO 1.
            } ELSE { SET st["seedt"] TO st["seedt"] - dt. }
        }
        SET u TO o2dTrim(st, e, u, au, dt).
    }
    ELSE { SET st["ui"] TO V(0, 0, 0). SET st["seedt"] TO 0. }
    SET st["e"] TO e. SET st["ea"] TO ea. SET st["w"] TO wl. SET st["u"] TO u.
    RETURN u.
}
