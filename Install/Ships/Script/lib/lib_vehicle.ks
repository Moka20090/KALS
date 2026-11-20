// ============================================================================
//  LIB_VEHICLE.KS  --  trim, the applied-control readout, and measured aero
// ============================================================================
//  Loaded with RUNONCEPATH by the entry executive (ops3q); no top-level action. Loads entry_predict.ks; no file I/O.
//  Not guidance: what the vehicle does with a bank command, plus the measurements the trim uses.
//  Applied control is read from the OMS gimbal limited to 1 % (0.05 deg of its 5 deg travel): it gives no useful
//  torque and adds none to the steering manager's loop. It is the only route in kOS: SHIP:CONTROL reads 0 under
//  cooked steering, PILOTPITCH is the player's stick, the autopilot trim suffixes do nothing, and
//  STEERINGMANAGER:PITCHPID outputs a rate (rad/s), not a deflection. Gimbal:PITCHANGLE is a normalised deflection.
//  Pitch trim: integrates the body flap to null that reading, spilling symmetrically to the elevons when the flap
//  saturates. Aero: the orbital velocity's finite difference minus gravity; no accelerometer part is needed.

RUNONCEPATH("0:/lib/entry_predict.ks").
RUNONCEPATH("0:/lib/lib_far.ks").   // FAR's control surfaces when FAR is installed

// Limit x to lo..hi. A local copy, so this library needs no shared helper file.
FUNCTION vehClamp { PARAMETER x, lo, hi. RETURN MAX(lo, MIN(hi, x)). }

GLOBAL HAS_ACCELEROMETER IS FALSE.  // TRUE: the aero functions read SENSORS:ACC (needs an accelerometer part; see accFitted)
GLOBAL ACC_SCALE         IS 1.0.    // scale on the measured acceleration; 1.0 = no correction (kOS issue #1827 does not apply)
// master switch for the pitch trim (body flap)
GLOBAL PTRIM_ON IS TRUE.
GLOBAL PTRIM_SIGN IS -1.       // -1: a positive gimbal reading drives the flap negative (the sign that nulls it)
GLOBAL PTRIM_GAIN IS 2.        // deg of flap per unit of gmb_pitch per second.
GLOBAL PTRIM_RATE IS 0.5.      // deg/s ceiling; catches transients, should not normally bind
GLOBAL PTRIM_MAX IS 19.5.      // deg, flap angle limit (of the flap's 20 deg authority)
GLOBAL PTRIM_UP IS PTRIM_MAX.  // deg, the flap's trailing-edge-up (nose-up, negative) limit; PFIX_UP with the pitch fix on
GLOBAL PTRIM_DN IS PTRIM_MAX.  // deg, the flap's trailing-edge-down (nose-down, positive) limit; PFIX_UP with the pitch fix on
GLOBAL PTRIM_DB IS 0.02.       // deadband on the gimbal reading: below it the trim does not move
GLOBAL PTRIM_QMIN IS 100.      // Pa dynamic pressure: below it the flap has no effect and the trim waits
GLOBAL PTRIM_HOLD IS -999.     // deg: > -900 holds the flap at this angle (ops3q's aero test flap steps) while the elevon
                               //   spill keeps nulling the gimbal reading; -999 = off
// THE PITCH FIX (stock only): SOCK RealAero's SockPitchFix adds the stock orbiter's hypersonic nose-up correction while
// its module field "Pitch fix" (pitchFix in Patches/9_pitch_fix.cfg, default true) is TRUE; "Pitch fix scale" is its share
// of the full table (default 1). The module reads both at each entry's start, this at the program's start (GETFIELD on the
// part module). With it on, the flap's limit is PFIX_UP both ways (the orbiter's own up
// limit; the orbiter's down limit is 22.5, held to the up one here), the rest spills to the elevons as at PTRIM_MAX. On only with the module
// aboard (none under FAR, or before the DLL that carries it is installed): everything as before.
GLOBAL PFIX_ON IS FALSE.
GLOBAL PFIX_SCALE IS 1.
GLOBAL PFIX_UP IS 11.7.        // deg
FUNCTION pfixRead {
    SET PFIX_ON TO FALSE.
    SET PFIX_SCALE TO 1.
    LOCAL pfM IS SHIP:MODULESNAMED("SockPitchFix").
    IF pfM:LENGTH > 0 AND pfM[0]:HASFIELD("Pitch fix") {
        SET PFIX_ON TO pfM[0]:GETFIELD("Pitch fix") = TRUE.
        IF pfM[0]:HASFIELD("Pitch fix scale") { SET PFIX_SCALE TO MAX(0, MIN(2, pfM[0]:GETFIELD("Pitch fix scale"))). }
    }
    SET PTRIM_UP TO CHOOSE PFIX_UP IF PFIX_ON ELSE PTRIM_MAX.
    SET PTRIM_DN TO CHOOSE PFIX_UP IF PFIX_ON ELSE PTRIM_MAX.
}
pfixRead().
FUNCTION pfixLine {                    // the start-up line: the switch's state
    IF PFIX_ON { RETURN "Pitch fix ON: " + ROUND(PFIX_SCALE, 2) + " x table, flap limit " + PFIX_UP + " up and down". }
    RETURN "Pitch fix off".
}
// pitch trim state: flap angle (deg), time of the last update (UT s), TRUE once the flap is deployed, status text
GLOBAL PTRIM_ANG IS 0.
GLOBAL PTRIM_T IS 0.
GLOBAL PTRIM_ACTIVE IS FALSE.
GLOBAL PTRIM_STATE IS "off".
// master switch for the elevon trim (the spill from the flap)
GLOBAL ETRIM_ON IS TRUE.
GLOBAL ETRIM_SIGN IS -1.       // sign of the elevon step against the gimbal reading; unverified
GLOBAL ETRIM_MAX IS 15.        // deg, elevon trim limit; the elevon limiter is 25 deg, so 15 leaves 40 % for roll
                               //   Roll authority is paid for during bank reversals: if bank_err grows there, this is why.
                               //   At a 6 deg cap both trim surfaces saturate in the hypersonic phase (AoA 40 deg, no reserve).
                               //   A dry orbiter (TAL, contingency dumped to empty) needs 12-14.5 deg at Mach 10-6.
GLOBAL ETRIM_SPILL IS 0.5.     // deg of flap headroom below PTRIM_MAX before spilling starts
GLOBAL ETRIM_RATE IS 0.6.      // deg/s, spill and wind-back rate; faster than the flap's PTRIM_RATE, but the elevons
                               //   move only once the flap is at its ceiling, and wind back while both demands ease
// elevon trim state: angle (deg) and the last angle written to the elevons (-999 = none yet)
GLOBAL ETRIM_ANG IS 0.
GLOBAL ETRIM_APPLIED IS -999.
GLOBAL FLAP_BIAS IS -999.
// part handles set by gmbInit (the OMS engine whose gimbal is read) and surfInit (body flap, elevons); *_HAVE = found
GLOBAL GMB_ENG IS 0.
GLOBAL GMB_HAVE IS FALSE.
GLOBAL GMB_MOD IS 0.            // The gimbal's module, registered (modReg), so gmbLive can see a lost engine; 0 = not registered
GLOBAL FLAP_HAVE IS FALSE.
GLOBAL ELEV_HAVE IS FALSE.
GLOBAL FLAP_MOD IS 0.
GLOBAL ELEV_MOD IS 0.
GLOBAL ELEV_MODS IS LIST().
GLOBAL FD_MIN_DT IS 1.0.        // s of averaging per sample
// fdSample state: previous orbital velocity, position (body centre to vessel) and time; FD_HAVE = a sample is stored
GLOBAL FD_PV IS V(0, 0, 0).
GLOBAL FD_PR IS V(0, 0, 0).
GLOBAL FD_PT IS 0.
GLOBAL FD_PB IS V(0, 0, 0).     // LATLNG(0,0) (a point on the body) as a vector from the body's centre at the previous sample
GLOBAL FD_FK IS 0.              // the raw frame's turn over the last window as a fraction of the body's (1: it turns with it)
GLOBAL FD_HAVE IS FALSE.
// latest window, m/s^2: FD_DRAG (opposes the surface-relative velocity), FD_LIFT (perpendicular magnitude), FD_MAG (total);
// FD_DT its length (s), FD_N windows counted, FD_JUMP implausible jumps counted, FD_LAST the previous FD_MAG
GLOBAL FD_DRAG IS 0.
GLOBAL FD_LIFT IS 0.
GLOBAL FD_MAG IS 0.
GLOBAL FD_DT IS 0.
GLOBAL FD_N IS 0.
GLOBAL FD_JUMP IS 0.
GLOBAL FD_LAST IS 0.
// the RCS jets' push taken out of each window (the addon's RCSDV: their summed velocity change, every physics tick):
// FD_RCS_ON FALSE leaves it in; FD_RCS_HAVE -1 not looked for yet, 0 no addon, 1 read; FD_PRC the sum at the previous
// sample; FD_RCSA the last window's RCS acceleration along the drag axis (m/s^2, + = it read as drag)
GLOBAL FD_RCS_ON IS TRUE.
GLOBAL FD_RCS_HAVE IS -1.
GLOBAL FD_PRC IS V(0, 0, 0).
GLOBAL FD_RCSA IS 0.

// Non-gravitational acceleration, m/s^2: SENSORS:ACC minus gravity at the vessel (zero vector unless HAS_ACCELEROMETER).
FUNCTION aeroVec {
    IF NOT HAS_ACCELEROMETER { RETURN V(0, 0, 0). }
    LOCAL rvec IS -SHIP:BODY:POSITION.                 // body centre -> vessel
    LOCAL gmag IS SHIP:BODY:MU / rvec:SQRMAGNITUDE.
    LOCAL gvec IS -rvec:NORMALIZED * gmag.             // gravity, pointing down
    RETURN (SHIP:SENSORS:ACC - gvec) * ACC_SCALE.
}

// Aerodynamic acceleration in an orthonormal local frame, m/s^2:
//   e_up   local vertical (away from the body)
//   e_h    horizontal component of the surface velocity, normalised (downrange)
//   e_s    e_up cross e_h, completing the triad (lateral)
// Returns LIST(a_up, a_h, a_s). Unlike aeroAccel's drag / lift pair, it needs no cos(bank) projection of the
// perpendicular force (part of which is lateral), so the vertical and lateral equations of motion close exactly.
FUNCTION aeroFrame {
    IF NOT HAS_ACCELEROMETER { RETURN LIST(0, 0, 0). }
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    IF vs:MAG < 5 { RETURN LIST(0, 0, 0). }
    LOCAL eUp IS SHIP:UP:VECTOR:NORMALIZED.
    LOCAL hz  IS VXCL(eUp, vs).
    IF hz:MAG < 0.5 { RETURN LIST(0, 0, 0). }
    LOCAL eH  IS hz:NORMALIZED.
    LOCAL eS  IS VCRS(eUp, eH):NORMALIZED.
    LOCAL a   IS aeroVec().
    RETURN LIST(VDOT(a, eUp), VDOT(a, eH), VDOT(a, eS)).
}

// Aerodynamic acceleration resolved about the surface-velocity vector, m/s^2.
// [0] = drag (opposing velocity, positive), [1] = lift (perpendicular magnitude).
FUNCTION aeroAccel {
    IF NOT HAS_ACCELEROMETER { RETURN LIST(0, 0). }
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    IF vs:MAG < 5 { RETURN LIST(0, 0). }
    LOCAL vh IS vs:NORMALIZED.
    LOCAL a  IS aeroVec().
    RETURN LIST(-VDOT(a, vh), VXCL(vh, a):MAG).
}

// TRUE if the vessel carries an accelerometer part (found by title, or as a ModuleEnviroSensor of type ACC).
FUNCTION accFitted {
    FOR p IN SHIP:PARTS {
        IF p:TITLE:CONTAINS("ccelerometer") OR p:NAME:CONTAINS("ccelerometer") { RETURN TRUE. }
        IF p:HASMODULE("ModuleEnviroSensor") {
            LOCAL m IS p:GETMODULE("ModuleEnviroSensor").
            IF m:HASFIELD("sensor type") {
                IF m:GETFIELD("sensor type"):TOSTRING:CONTAINS("ACC") { RETURN TRUE. }
            }
        }
    }
    RETURN FALSE.
}

// The RCS jets' summed velocity change so far (world axes, m/s), V(0,0,0) without the addon or with FD_RCS_ON FALSE.
FUNCTION fdRcsDv {
    IF NOT FD_RCS_ON { RETURN V(0, 0, 0). }
    IF FD_RCS_HAVE < 0 {
        SET FD_RCS_HAVE TO 0.
        IF ADDONS:KALS:AVAILABLE { IF ADDONS:KALS:HASSUFFIX("RCSDV") { SET FD_RCS_HAVE TO 1. } }
    }
    IF FD_RCS_HAVE = 0 { RETURN V(0, 0, 0). }
    LOCAL l IS ADDONS:KALS:RCSDV.
    RETURN V(l[0], l[1], l[2]).
}

// Finite-difference aero: the change in orbital velocity over each window of FD_MIN_DT s or more, minus gravity and the
// RCS jets' push (fdRcsDv), sets FD_DRAG, FD_LIFT and FD_MAG (m/s^2). Safe to call every loop: it returns until a window
// has passed.
FUNCTION fdSample {
    LOCAL now IS TIME:SECONDS.
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    LOCAL bp IS LATLNG(0, 0):ALTITUDEPOSITION(0) - SHIP:BODY:POSITION.
    IF NOT FD_HAVE {
        SET FD_PV TO vv. SET FD_PR TO rv. SET FD_PB TO bp. SET FD_PT TO now. SET FD_HAVE TO TRUE.
        SET FD_PRC TO fdRcsDv().
        RETURN.
    }
    LOCAL dt IS now - FD_PT.
    IF dt < FD_MIN_DT { RETURN. }
    // Below KSP's inverse-rotation altitude the raw frame turns with the body (angular velocity w), so the previous
    // sample's vectors sit in axes that have turned by w dt; differenced as they stand they add -w x v_orb (~0.53 m/s2,
    // mostly perpendicular to v), a floor in FD_LIFT. The turn is read from LATLNG(0,0), a point on the body at b from
    // its centre: it holds still in a frame that turns with the body and moves by w x b dt in one that does not
    // (SOLARPRIMEVECTOR does not turn with this frame). So FD_FK = 1 - (its move . w x b) / (dt |w x b|^2) is the
    // frame's turn as a fraction of the body's, and the previous vectors enter the current axes as X - FD_FK dt (w x X).
    LOCAL wb IS eprOmegaCross(FD_PB).
    SET FD_FK TO 1 - VDOT(bp - FD_PB, wb) / (dt * MAX(wb:SQRMAGNITUDE, 1e-9)).
    LOCAL kdt IS dt * MIN(MAX(FD_FK, 0), 1).
    LOCAL pv IS FD_PV - kdt * eprOmegaCross(FD_PV).
    LOCAL pr IS FD_PR - kdt * eprOmegaCross(FD_PR).
    LOCAL atot IS (vv - pv) / dt.
    // gravity at the window's midpoint, not either end: over 1 s at entry speeds the endpoints differ enough to matter
    LOCAL rmid IS (rv + pr) * 0.5.
    LOCAL gmid IS -rmid:NORMALIZED * (SHIP:BODY:MU / rmid:SQRMAGNITUDE).
    // J2 where the body has it (Sol: Principia's): up to ~0.04 m/s2, which is not aero
    IF EPR_J2_ON { SET gmid TO gmid + eprJ2Accel(rmid, rmid:MAG). }
    LOCAL rc IS fdRcsDv().
    LOCAL arcs IS (rc - FD_PRC) / dt.
    SET FD_PRC TO rc.
    LOCAL aero IS atot - gmid - arcs.
    // decompose against the surface-relative velocity at the midpoint
    LOCAL vmid IS (vv + pv) * 0.5.
    LOCAL vrelm IS vmid - eprOmegaCross(rmid).
    IF vrelm:MAG > 1 {
        LOCAL vh IS vrelm:NORMALIZED.
        SET FD_DRAG TO -VDOT(aero, vh).
        SET FD_RCSA TO -VDOT(arcs, vh).
        SET FD_LIFT TO (aero - vh * VDOT(aero, vh)):MAG.
        SET FD_MAG TO aero:MAG.
        SET FD_DT TO dt.
        SET FD_N TO FD_N + 1.
        // an implausible jump between windows is almost certainly an RCS pulse, not aero
        IF FD_LAST > 0 AND ABS(FD_MAG - FD_LAST) > 0.5 + 0.5 * FD_LAST {
            SET FD_JUMP TO FD_JUMP + 1.
        }
        SET FD_LAST TO FD_MAG.
    }
    SET FD_PV TO vv. SET FD_PR TO rv. SET FD_PB TO bp. SET FD_PT TO now.
}

// Find the body flap and the elevons (ModuleControlSurface, or FAR's FARControllableSurface: SURF_MN, on parts titled Body Flap / Elevon): sets FLAP_MOD, ELEV_MOD, ELEV_MODS.
FUNCTION surfInit {
    surfListMark("veh").
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE(SURF_MN) {
            IF p:TITLE:CONTAINS("Body Flap") AND NOT FLAP_HAVE {
                SET FLAP_MOD TO modReg(p:GETMODULE(SURF_MN)).
                SET FLAP_HAVE TO TRUE.
            }
            IF p:TITLE:CONTAINS("Elevon") {
                ELEV_MODS:ADD(modReg(p:GETMODULE(SURF_MN))).
                IF NOT ELEV_HAVE {
                    SET ELEV_MOD TO modReg(p:GETMODULE(SURF_MN)).
                    SET ELEV_HAVE TO TRUE.
                }
            }
        }
    }
}

// The elevons and the body flap, found again from SHIP once after a splashdown's rebuild (surfListRefind)
FUNCTION vehRefind {
    IF NOT surfListRefind("veh") { RETURN. }
    ELEV_MODS:CLEAR().
    SET FLAP_HAVE TO FALSE.
    SET ELEV_HAVE TO FALSE.
    surfInit().
}

// Find the OMS engine with a gimbal (title contains Manoeuvring, Maneuvering or Viking): sets GMB_ENG and GMB_HAVE.
FUNCTION gmbInit {
    FOR eng IN SHIP:ENGINES {
        IF NOT GMB_HAVE AND eng:HASMODULE("ModuleGimbal") {
            IF eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering")
               OR eng:TITLE:CONTAINS("Viking") {
                SET GMB_ENG TO eng.
                SET GMB_HAVE TO TRUE.
                SET GMB_MOD TO modReg(eng:GETMODULE("ModuleGimbal")).
            }
        }
    }
}

// The OMS gimbal engine (GMB_ENG) is a part that a breakup / ditching can remove: every touch of it goes through gmbLive
// (modLive on the gimbal's registered module: the vessel generation + the live part UIDs), like dGmbLive in lib_dap.
FUNCTION gmbLive {
    IF NOT GMB_HAVE { RETURN FALSE. }
    IF GMB_MOD:ISTYPE("Scalar") { RETURN TRUE. }      // never registered: no touch rule of modLive (a fresh gimbal is on the ship)
    RETURN modLive(GMB_MOD).
}

// Set every elevon's deploy angle to ang (deg); writes only when it changed by 0.005 deg or more.
FUNCTION etrimSet {
    PARAMETER ang.
    vehRefind().
    // skip the write when nothing changed: two SETFIELD calls per elevon are costly in the instruction-bound entry loop
    IF ABS(ang - ETRIM_APPLIED) < 0.005 { RETURN. }
    SET ETRIM_APPLIED TO ang.
    FOR em IN ELEV_MODS {
        IF FAR_ON { surfSetAng(em, ang). } ELSE IF modLive(em) AND NOT surfFrozen(em) {
            em:SETFIELD("deploy", TRUE).
            em:SETFIELD("deploy angle", ang).
        }
    }
}

// One step of the pitch trim: integrates the flap angle (PTRIM_ANG) to null the gimbal's pitch reading and, near the
// flap's limit, spills the demand to the elevons (ETRIM_ANG). Sets PTRIM_STATE.
FUNCTION ptrimUpdate {
    vehRefind().
    IF NOT PTRIM_ON OR NOT GMB_HAVE OR NOT FLAP_HAVE { RETURN. }
    IF NOT gmbLive() { RETURN. }               // Not after the OMS engine is lost (a breakup / ditching)
    LOCAL qq IS SHIP:DYNAMICPRESSURE * 101325.
    LOCAL now IS TIME:SECONDS.
    IF qq < PTRIM_QMIN {
        SET PTRIM_T TO now.
        SET PTRIM_STATE TO "wait q".
        RETURN.
    }
    LOCAL dt IS now - PTRIM_T.
    SET PTRIM_T TO now.
    IF dt <= 0 OR dt > 5 { RETURN. }          // first call, or a warp gap

    LOCAL err IS GMB_ENG:GIMBAL:PITCHANGLE.
    IF NOT PTRIM_ACTIVE {
        SET PTRIM_ACTIVE TO TRUE.
        surfDeploy(FLAP_MOD).
    }
    IF PTRIM_HOLD > -900 {
        SET PTRIM_ANG TO vehClamp(PTRIM_HOLD, 0 - PTRIM_UP, PTRIM_DN).
        IF FAR_ON { surfSetAng(FLAP_MOD, PTRIM_ANG). } ELSE IF modLive(FLAP_MOD) AND NOT surfFrozen(FLAP_MOD) { FLAP_MOD:SETFIELD("deploy angle", PTRIM_ANG). }
    }

    // No sign guard: PTRIM_SIGN = -1 is the sign that nulls the reading, and a guard could only break it. If a rigging
    // change reverses the convention, the log shows trim_ang running to its limit while gmb_pitch grows the same way.

    IF ABS(err) < PTRIM_DB {
        SET PTRIM_STATE TO "deadbnd".
        RETURN.
    }

    IF PTRIM_HOLD > -900 {
        SET PTRIM_STATE TO "test".
    } ELSE {
        LOCAL step IS PTRIM_SIGN * PTRIM_GAIN * err * dt.
        SET step TO vehClamp(step, 0 - PTRIM_RATE * dt, PTRIM_RATE * dt).
        SET PTRIM_ANG TO vehClamp(PTRIM_ANG + step, 0 - PTRIM_UP, PTRIM_DN).
        IF FAR_ON { surfSetAng(FLAP_MOD, PTRIM_ANG). } ELSE IF modLive(FLAP_MOD) AND NOT surfFrozen(FLAP_MOD) { FLAP_MOD:SETFIELD("deploy angle", PTRIM_ANG). }
        SET PTRIM_STATE TO "trim".
    }

    // Spill to the elevons once the flap is within ETRIM_SPILL of its ceiling (or held by PTRIM_HOLD); below that they
    // are wound back toward neutral, because deflected elevons would keep costing roll authority after the pitch demand eases.
    IF ETRIM_ON AND ELEV_MODS:LENGTH > 0 {
        IF PTRIM_ANG >= PTRIM_DN - ETRIM_SPILL OR PTRIM_ANG <= ETRIM_SPILL - PTRIM_UP OR PTRIM_HOLD > -900 {
            LOCAL es IS ETRIM_SIGN * PTRIM_GAIN * err * dt.
            SET es TO vehClamp(es, 0 - ETRIM_RATE * dt, ETRIM_RATE * dt).
            SET ETRIM_ANG TO vehClamp(ETRIM_ANG + es, 0 - ETRIM_MAX, ETRIM_MAX).
            SET PTRIM_STATE TO "flap+elev".
            IF ABS(ETRIM_ANG) >= ETRIM_MAX - 0.05 { SET PTRIM_STATE TO "BOTH AT LIMIT". }
        } ELSE IF ABS(ETRIM_ANG) > 0.01 {
            LOCAL back IS ETRIM_RATE * dt.
            IF ETRIM_ANG > 0 { SET ETRIM_ANG TO MAX(0, ETRIM_ANG - back). }
            ELSE { SET ETRIM_ANG TO MIN(0, ETRIM_ANG + back). }
            SET PTRIM_STATE TO "elev back".
        }
        etrimSet(ETRIM_ANG).
    } ELSE IF PTRIM_ANG >= PTRIM_DN - 0.05 OR PTRIM_ANG <= 0.05 - PTRIM_UP {
        SET PTRIM_STATE TO "AT LIMIT".
    }
}

