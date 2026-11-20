// ============================================================================
//  ASCENT_LOG.KS  --  log an ascent for the offline ascent sim
// ============================================================================
//      RUN ascent_log.                  log only: fly the ascent by hand or with anything that is not a kOS program
//      RUN ascent_log("prog.ks").       log AND run that kOS program in the same context (the craft has one CPU)
//      RUNPATH("0:/ascent_log.ks", "prog.ks", TRUE).   from inside that program (ops1q.ks): set up the
//                                       logger and return; its rows by the trigger while the program runs, which
//                                       awaits LG_DONE at its end itself
//  It commands nothing. WRITES 0:/logs/ascent_<n>.csv (a row every LG_STEP s; every LG_STEP_PAD s on the pad
//  before any thrust) and 0:/logs/ascent_<n>.txt (the vessel, its engines and propellant at the start, then the
//  events by MET: status, stage, part count, SRB and SSME start / stop). It stops LG_END_S after the SSMEs stop
//  (or at MET LG_MAX_MET); CTRL+C keeps everything but the last second.
//  FRAME: N / E / U = the local north / east / up at the vessel (east = VCRS(UP, NORTH), kOS's own idiom).
//  THE ACCELERATION IS MEASURED LIKE THE ENTRY'S, by deriving the velocity: lib/lib_vehicle.ks fdSample's method,
//  unchanged -- the orbital velocity's finite difference over LG_FD_DT (the entry's FD_MIN_DT 1.0 s), the raw frame's
//  turn with the body taken out (measured on a body-fixed point: the frame turns with the body below KSP's
//  inverse-rotation altitude), the analytic gravity at the window's MIDPOINT removed (+ Principia's J2 on Sol's Earth,
//  as lib/entry_predict.ks flies it). What is left is the specific non-gravitational force over the window, (thrust +
//  aero) / mass: the offline sim subtracts the logged thrust to get the aero force. On the pad it must read 1 g
//  straight up (the ground's push).
// ============================================================================
@LAZYGLOBAL OFF.
PARAMETER lgProg IS "", lgBg IS FALSE.     // lgBg: set up and return (the program's own start)

GLOBAL LG_STEP IS 0.1.          // s between rows once anything thrusts
GLOBAL LG_STEP_PAD IS 0.5.      // s between rows on the pad before any thrust
GLOBAL LG_FD_DT IS 1.0.         // s, the finite-difference window (lib_vehicle.ks FD_MIN_DT)
GLOBAL LG_END_S IS 30.          // s after the SSMEs stop
GLOBAL LG_MAX_MET IS 1500.      // s, the stop in any case
GLOBAL LG_FLUSH IS 10.          // rows per write

// the body (lib/entry_predict.ks's constants: EPR_WMAG, EPR_WAXIS, EPR_J2, EPR_R_J2, EPR_J2_ON)
GLOBAL LG_WMAG IS 2 * CONSTANT:PI / SHIP:BODY:ROTATIONPERIOD.
GLOBAL LG_WAXIS IS SHIP:BODY:ANGULARVEL:NORMALIZED.   // its sign is not north; omega x r is right either way
GLOBAL LG_J2 IS 0.0010826358191967033.
GLOBAL LG_R_J2 IS 1594534.075.
GLOBAL LG_J2_ON IS SHIP:BODY:NAME = "Earth".

GLOBAL LG_ROWS IS LIST().
GLOBAL LG_FDQ IS LIST().        // the samples of the last window: LIST(ut, r, v, body point)
GLOBAL LG_ENG_S IS LIST().      // SRBs (PC.4Seg.RSRM)
GLOBAL LG_ENG_M IS LIST().      // SSMEs (rmm.cotopaxi)
GLOBAL LG_ENG_O IS LIST().      // OMS (benjee10.AJ10.v2)
GLOBAL LG_ENG_X IS LIST().      // the rest (the SRB noses' separation motors)
GLOBAL LG_NPARTS IS -1.
GLOBAL LG_PSTAT IS "".
GLOBAL LG_PSTAGE IS -1.
GLOBAL LG_SRB_ON IS FALSE.
GLOBAL LG_SSME_ON IS FALSE.
GLOBAL LG_SSME_RAN IS FALSE.
GLOBAL LG_SSME_OFF_T IS 0.
GLOBAL LG_NROW IS 0.
GLOBAL LG_DONE IS FALSE.
GLOBAL LG_SHOW IS lgProg = "".  // the terminal line only when no program owns the screen
GLOBAL LG_SHOWN IS 0.

LOCAL lgN IS ROUND(TIME:SECONDS).
UNTIL NOT EXISTS("0:/logs/ascent_" + lgN + ".csv") { SET lgN TO lgN + 1. }
GLOBAL LG_CSV IS "0:/logs/ascent_" + lgN + ".csv".
GLOBAL LG_TXT IS "0:/logs/ascent_" + lgN + ".txt".
GLOBAL LG_HEAD IS "ut,met,stat,stg,lat,lng,alt,agl,v_n,v_e,v_u,v_orb,mass,thr_srb,thr_ssme,avl_ssme,thr_oms,thr_oth,"
    + "thr_pilot,q_pa,p_pa,f_n,f_e,f_u,t_n,t_e,t_u,fd_dt,fd_n,fd_e,fd_u,fd_fwd,fd_drag,fd_fk,"
    + "solid,lh2,ox,lf,ap,pe,g1_p,g1_y,g2_p,g2_y,g3_p,g3_y,mono".
// g<k>_p / g<k>_y = the k-th SSME's gimbal deflection now (deg; kOS GIMBAL:PITCHANGLE / YAWANGLE), the SSMEs in
// LG_ENG_M's order (the .txt's "engine SSME" lines); blank for an engine without a gimbal or not there. Appended last:
// readers go by the header's names. mono = the RCS propellant (MonoPropellant, units; 0.004 t each) in the ship now, the
// last column: a log without it is the older format (sim/rcsprop.py reads both).

FUNCTION lgGimbals {                        // "p1,y1,p2,y2,p3,y3" of LG_ENG_M's first three (blank: none)
    LOCAL g IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k > 2 STEP { SET k TO k + 1. } DO {
        IF k < LG_ENG_M:LENGTH AND LG_ENG_M[k]:HASGIMBAL {
            LOCAL gm IS LG_ENG_M[k]:GIMBAL.
            g:ADD(ROUND(gm:PITCHANGLE, 3)). g:ADD(ROUND(gm:YAWANGLE, 3)).
        } ELSE { g:ADD(""). g:ADD(""). }
    }
    RETURN g:JOIN(",").
}

FUNCTION lgEngines {
    LG_ENG_S:CLEAR(). LG_ENG_M:CLEAR(). LG_ENG_O:CLEAR(). LG_ENG_X:CLEAR().
    LOCAL engs IS LIST().
    LIST ENGINES IN engs.
    FOR en IN engs {
        IF en:NAME = "PC.4Seg.RSRM" { LG_ENG_S:ADD(en). }
        ELSE IF en:NAME = "rmm.cotopaxi" { LG_ENG_M:ADD(en). }
        ELSE IF en:NAME = "benjee10.AJ10.v2" { LG_ENG_O:ADD(en). }
        ELSE { LG_ENG_X:ADD(en). }
    }
    SET LG_NPARTS TO SHIP:PARTS:LENGTH.
}

FUNCTION lgThrust {
    PARAMETER engs.
    LOCAL s IS 0.
    FOR en IN engs { SET s TO s + en:THRUST. }
    RETURN s.
}

FUNCTION lgEvent {
    PARAMETER msg.
    LOG "  MET " + ROUND(MISSIONTIME, 2) + "  UT " + ROUND(TIME:SECONDS, 2) + "  " + msg TO LG_TXT.
}

FUNCTION lgJ2 {                 // lib/entry_predict.ks eprJ2Accel, the same formula
    PARAMETER rv.
    LOCAL rmag IS rv:MAG.
    LOCAL z IS VDOT(rv, LG_WAXIS).
    LOCAL k IS -1.5 * LG_J2 * SHIP:BODY:MU * LG_R_J2 * LG_R_J2 / (rmag ^ 5).
    LOCAL zz IS 5.0 * z * z / (rmag * rmag).
    RETURN (rv * (1.0 - zz) + LG_WAXIS * (2.0 * z)) * k.
}

FUNCTION lgFlush {
    IF LG_ROWS:LENGTH > 0 {
        LOG LG_ROWS:JOIN(CHAR(10)) TO LG_CSV.
        LG_ROWS:CLEAR().
    }
}

FUNCTION lgTick {
    // the raw state first, all in this tick
    LOCAL now IS TIME:SECONDS.
    LOCAL met IS MISSIONTIME.
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL nv IS SHIP:NORTH:VECTOR.
    LOCAL ev IS VCRS(upv, nv).
    LOCAL vsrf IS SHIP:VELOCITY:SURFACE.
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL bp IS LATLNG(0, 0):ALTITUDEPOSITION(0) - SHIP:BODY:POSITION.
    LOCAL fv IS SHIP:FACING:FOREVECTOR.
    LOCAL tv IS SHIP:FACING:TOPVECTOR.
    LOCAL stat IS SHIP:STATUS.
    LOCAL stg IS STAGE:NUMBER.
    IF SHIP:PARTS:LENGTH <> LG_NPARTS {
        lgEvent("parts " + LG_NPARTS + " -> " + SHIP:PARTS:LENGTH).
        lgEngines().
    }
    LOCAL thrS IS lgThrust(LG_ENG_S).
    LOCAL thrM IS lgThrust(LG_ENG_M).
    LOCAL thrO IS lgThrust(LG_ENG_O).
    LOCAL thrX IS lgThrust(LG_ENG_X).
    LOCAL avlM IS 0.
    FOR en IN LG_ENG_M { SET avlM TO avlM + en:AVAILABLETHRUST. }
    LOCAL solid IS 0. LOCAL lh2 IS 0. LOCAL ox IS 0. LOCAL lf IS 0. LOCAL mono IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "SolidFuel" { SET solid TO res:AMOUNT. }
        ELSE IF res:NAME = "LqdHydrogen" { SET lh2 TO res:AMOUNT. }
        ELSE IF res:NAME = "Oxidizer" { SET ox TO res:AMOUNT. }
        ELSE IF res:NAME = "LiquidFuel" { SET lf TO res:AMOUNT. }
        ELSE IF res:NAME = "MonoPropellant" { SET mono TO res:AMOUNT. }
    }

    // the finite difference over the last LG_FD_DT (lib_vehicle.ks fdSample, sliding)
    LG_FDQ:ADD(LIST(now, rv, vv, bp)).
    UNTIL LG_FDQ:LENGTH < 3 OR now - LG_FDQ[1][0] < LG_FD_DT { LG_FDQ:REMOVE(0). }
    LOCAL s0 IS LG_FDQ[0].
    LOCAL dt IS now - s0[0].
    LOCAL fdv IS LIST(0, 0, 0, 0, 0, 0, 0).   // dt, N, E, U, along the nose, along -v_rel, the frame's turn
    IF dt >= 0.5 * LG_FD_DT {
        LOCAL wv IS LG_WAXIS * LG_WMAG.
        LOCAL wb IS VCRS(wv, s0[3]).
        LOCAL fk IS 1 - VDOT(bp - s0[3], wb) / (dt * MAX(wb:SQRMAGNITUDE, 1e-9)).
        LOCAL kdt IS dt * MIN(MAX(fk, 0), 1).
        LOCAL pv IS s0[2] - kdt * VCRS(wv, s0[2]).
        LOCAL pr IS s0[1] - kdt * VCRS(wv, s0[1]).
        LOCAL atot IS (vv - pv) / dt.
        LOCAL rmid IS (rv + pr) * 0.5.
        LOCAL gmid IS -rmid:NORMALIZED * (SHIP:BODY:MU / rmid:SQRMAGNITUDE).
        IF LG_J2_ON { SET gmid TO gmid + lgJ2(rmid). }
        LOCAL sfv IS atot - gmid.
        LOCAL vrel IS (vv + pv) * 0.5 - VCRS(wv, rmid).
        LOCAL along IS 0.
        IF vrel:MAG > 1 { SET along TO -VDOT(sfv, vrel:NORMALIZED). }
        SET fdv TO LIST(dt, VDOT(sfv, nv), VDOT(sfv, ev), VDOT(sfv, upv), VDOT(sfv, fv), along, fk).
    }

    // events
    IF stat <> LG_PSTAT { lgEvent("status " + stat). SET LG_PSTAT TO stat. }
    IF stg <> LG_PSTAGE { lgEvent("stage " + stg). SET LG_PSTAGE TO stg. }
    IF (thrS > 1) <> LG_SRB_ON {
        SET LG_SRB_ON TO thrS > 1.
        lgEvent(CHOOSE "SRB thrust on" IF LG_SRB_ON ELSE "SRB thrust off").
    }
    IF (thrM > 1) <> LG_SSME_ON {
        SET LG_SSME_ON TO thrM > 1.
        lgEvent(CHOOSE "SSME thrust on" IF LG_SSME_ON ELSE "SSME thrust off").
        IF NOT LG_SSME_ON { SET LG_SSME_OFF_T TO now. }
    }
    IF thrM > 100 { SET LG_SSME_RAN TO TRUE. }

    LOCAL sc IS 9.
    IF stat = "PRELAUNCH" { SET sc TO 0. }
    ELSE IF stat = "FLYING" { SET sc TO 1. }
    ELSE IF stat = "SUB_ORBITAL" { SET sc TO 2. }
    ELSE IF stat = "ORBITING" { SET sc TO 3. }

    LG_ROWS:ADD(LIST(ROUND(now, 3), ROUND(met, 3), sc, stg,
        ROUND(SHIP:LATITUDE, 6), ROUND(SHIP:LONGITUDE, 6), ROUND(SHIP:ALTITUDE, 2), ROUND(ALT:RADAR, 2),
        ROUND(VDOT(vsrf, nv), 3), ROUND(VDOT(vsrf, ev), 3), ROUND(VDOT(vsrf, upv), 3), ROUND(vv:MAG, 3),
        ROUND(SHIP:MASS, 4), ROUND(thrS, 2), ROUND(thrM, 2), ROUND(avlM, 2), ROUND(thrO, 3), ROUND(thrX, 3),
        ROUND(SHIP:CONTROL:PILOTMAINTHROTTLE, 4),
        ROUND(SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000, 2),
        ROUND(SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE) * CONSTANT:ATMTOKPA * 1000, 2),
        ROUND(VDOT(fv, nv), 5), ROUND(VDOT(fv, ev), 5), ROUND(VDOT(fv, upv), 5),
        ROUND(VDOT(tv, nv), 5), ROUND(VDOT(tv, ev), 5), ROUND(VDOT(tv, upv), 5),
        ROUND(fdv[0], 3), ROUND(fdv[1], 4), ROUND(fdv[2], 4), ROUND(fdv[3], 4), ROUND(fdv[4], 4),
        ROUND(fdv[5], 4), ROUND(fdv[6], 4),
        ROUND(solid, 2), ROUND(lh2, 1), ROUND(ox, 2), ROUND(lf, 2),
        ROUND(SHIP:APOAPSIS, 1), ROUND(SHIP:PERIAPSIS, 1)):JOIN(",") + "," + lgGimbals() + "," + ROUND(mono, 3)).
    SET LG_NROW TO LG_NROW + 1.

    IF (LG_SSME_RAN AND NOT LG_SSME_ON AND now - LG_SSME_OFF_T >= LG_END_S) OR met > LG_MAX_MET {
        SET LG_DONE TO TRUE.
        lgEvent("logger stops (" + LG_NROW + " rows)").
    }
    IF LG_ROWS:LENGTH >= LG_FLUSH OR LG_DONE { lgFlush(). }
    IF LG_SHOW AND now - LG_SHOWN >= 1 {
        PRINT "ascent_log  MET " + ROUND(met) + "  rows " + LG_NROW + "  " + LG_CSV + "          " AT (0, 0).
        SET LG_SHOWN TO now.
    }
    IF stat = "PRELAUNCH" AND thrS + thrM + thrO < 1 { RETURN LG_STEP_PAD. }
    RETURN LG_STEP.
}

// ---- the setup file ----
lgEngines().
LOG "ascent_log v1 (ASCENT, A2-4): " + SHIP:NAME + "  UT " + ROUND(TIME:SECONDS, 2) + "  MET " + ROUND(MISSIONTIME, 2)
    TO LG_TXT.
LOG "kOS " + CORE:VERSION + "  IPU " + CONFIG:IPU + "  body " + SHIP:BODY:NAME + "  J2 " + LG_J2_ON
    + "  program " + (CHOOSE lgProg IF lgProg <> "" ELSE "none (log only)") TO LG_TXT.
LOG "start: lat " + ROUND(SHIP:LATITUDE, 6) + "  lng " + ROUND(SHIP:LONGITUDE, 6) + "  alt " + ROUND(SHIP:ALTITUDE, 2)
    + "  agl " + ROUND(ALT:RADAR, 2) + "  mass " + ROUND(SHIP:MASS, 4) + "  parts " + SHIP:PARTS:LENGTH
    + "  status " + SHIP:STATUS + "  stage " + STAGE:NUMBER TO LG_TXT.
FOR en IN LG_ENG_S { LOG "engine SRB   " + en:NAME + " | " + en:TITLE + " | stage " + en:STAGE + " | limiter " + en:THRUSTLIMIT TO LG_TXT. }
FOR en IN LG_ENG_M { LOG "engine SSME  " + en:NAME + " | " + en:TITLE + " | stage " + en:STAGE + " | limiter " + en:THRUSTLIMIT TO LG_TXT. }
FOR en IN LG_ENG_O { LOG "engine OMS   " + en:NAME + " | " + en:TITLE + " | stage " + en:STAGE + " | limiter " + en:THRUSTLIMIT TO LG_TXT. }
FOR en IN LG_ENG_X { LOG "engine other " + en:NAME + " | " + en:TITLE + " | stage " + en:STAGE + " | limiter " + en:THRUSTLIMIT TO LG_TXT. }
FOR res IN SHIP:RESOURCES { LOG "resource " + res:NAME + " " + ROUND(res:AMOUNT, 3) + " / " + ROUND(res:CAPACITY, 3) TO LG_TXT. }
LOG "csv: " + LG_CSV + "  columns: " + LG_HEAD TO LG_TXT.
LOG "units: s, deg, m, m/s, t, kN, Pa, units of resource (mono = the RCS propellant); f_* / t_* = the nose / top unit vectors in N E U; fd_* = m/s2" TO LG_TXT.
IF lgProg <> "" AND CONFIG:IPU < 2000 {
    LOG "WARNING: IPU " + CONFIG:IPU + " < 2000: the logger's rows take time from " + lgProg TO LG_TXT.
}
LOG "EVENTS:" TO LG_TXT.
LOG LG_HEAD TO LG_CSV.

// the lines only when no program owns the screen (LG_SHOW: RUN ascent_log. alone; not under ops1q), as the status
// line
IF LG_SHOW {
    CLEARSCREEN. PRINT " ".                 // row 0 is the status line
    PRINT "ascent_log: writing " + LG_CSV + " and " + LG_TXT.
    PRINT "ascent_log: stops " + LG_END_S + " s after the SSMEs stop; CTRL+C stops it now.".
}

GLOBAL LG_NEXT IS TIME:SECONDS.
WHEN TIME:SECONDS >= LG_NEXT THEN {
    SET LG_NEXT TO LG_NEXT + lgTick().
    IF LG_NEXT < TIME:SECONDS { SET LG_NEXT TO TIME:SECONDS. }
    RETURN NOT LG_DONE.
}

IF NOT lgBg {
    IF lgProg <> "" { RUNPATH("0:/" + lgProg). }
    WAIT UNTIL LG_DONE.
    IF LG_SHOW { PRINT "ascent_log: done, " + LG_NROW + " rows in " + LG_CSV. }
}
