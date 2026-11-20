// ============================================================================
//  LIB_GUIDE.KS  --  reference profile, drag tracker, guidance state
// ============================================================================
//  Loaded by ops3q (RUNONCEPATH); no top-level action.
//  Feedforward plus a small correction: the entry predictor's bank solve finds the bank that
//  reaches the target, a reference drag profile is built at that bank, and the tracker nulls the
//  measured drag against it between regenerations. Drag rather than altitude, because drag
//  answers a bank change within seconds, while altitude lags through an integration.

RUNONCEPATH("0:/lib/entry_predict.ks").

// EPR_BANK_STOP_SPEED, EPR_ROLL_RATE_LIMIT and EPR_ROLL_ACCEL_LIMIT are defined once, in
// entry_predict.ks, so the prediction and the vehicle share them.

// --- the reference grid ----------------------------------------------------
//  A fixed velocity grid, indexed by arithmetic rather than searched. It starts where drag
//  reaches 2 ft/s^2 (where the orbiter began closed-loop drag control) and ends at
//  EPR_BANK_STOP_SPEED, the AoA transition, where drag drops too steeply to interpolate across.
//  If the transition moves, move the cut with it.
GLOBAL GRD_STEP_NOM IS 50.      // m/s per grid point, nominal
GLOBAL GRD_STEP IS 50.          // m/s per grid point in use (grdBuild widens it to stay within GRD_MAX)
GLOBAL GRD_DRAG_ON IS 0.6096.   // m/s^2 (2 ft/s^2): the tracker turns on at this drag...
GLOBAL GRD_DRAG_OFF IS 0.50.    // ...and off below this (hysteresis against measurement noise)
GLOBAL GRD_MAX IS 80.           // the grid's maximum number of points

GLOBAL GRD_HAVE IS FALSE.
GLOBAL GRD_VHI IS 0.
GLOBAL GRD_VLO IS 0.
GLOBAL GRD_N IS 0.
GLOBAL GRD_DRAG IS LIST().
GLOBAL GRD_SINK IS LIST().
GLOBAL GRD_ALT IS LIST().
GLOBAL GRD_AGE IS 0.            // UT the grid was built

// Build the grid from an integrated profile, given as parallel lists of speed, drag, sink and
// altitude.
FUNCTION grdBuild {
    PARAMETER vs, ds, ss, alts.
    SET GRD_HAVE TO FALSE.
    IF vs:LENGTH < 4 { RETURN FALSE. }
    // the first sample at or past the drag gate, and the last above the bank-stop speed
    LOCAL i0 IS -1.
    LOCAL i1 IS -1.
    FROM { LOCAL k IS 0. } UNTIL k >= vs:LENGTH STEP { SET k TO k + 1. } DO {
        IF i0 < 0 AND ds[k] >= GRD_DRAG_ON AND vs[k] > EPR_BANK_STOP_SPEED { SET i0 TO k. }
        IF vs[k] > EPR_BANK_STOP_SPEED { SET i1 TO k. }
    }
    IF i0 < 0 OR i1 <= i0 + 2 { RETURN FALSE. }
    SET GRD_VHI TO vs[i0].
    SET GRD_VLO TO vs[i1].
    // widen the step rather than truncate the list: grdDragAt indexes by (GRD_VHI - v) / GRD_STEP
    SET GRD_STEP TO GRD_STEP_NOM.
    LOCAL n IS FLOOR((GRD_VHI - GRD_VLO) / GRD_STEP) + 2.
    UNTIL n <= GRD_MAX {
        SET GRD_STEP TO GRD_STEP * 2.
        SET n TO FLOOR((GRD_VHI - GRD_VLO) / GRD_STEP) + 2.
    }
    IF n < 3 { RETURN FALSE. }
    SET GRD_N TO n.
    SET GRD_DRAG TO LIST().
    SET GRD_SINK TO LIST().
    SET GRD_ALT TO LIST().
    FROM { LOCAL j IS 0. } UNTIL j >= n STEP { SET j TO j + 1. } DO {
        LOCAL vq IS GRD_VHI - j * GRD_STEP.
        LOCAL got IS grdSample(vs, ds, ss, alts, i0, i1, vq).
        GRD_DRAG:ADD(got[0]).
        GRD_SINK:ADD(got[1]).
        GRD_ALT:ADD(got[2]).
    }
    // the last entry is the profile's true end, not an interpolation past it
    SET GRD_DRAG[n - 1] TO ds[i1].
    SET GRD_SINK[n - 1] TO ss[i1].
    SET GRD_ALT[n - 1] TO alts[i1].
    SET GRD_AGE TO TIME:SECONDS.
    SET GRD_HAVE TO TRUE.
    RETURN TRUE.
}

// Linear interpolation into the raw samples, for the build only. Speed falls along the profile.
FUNCTION grdSample {
    PARAMETER vs, ds, ss, alts, i0, i1, vq.
    IF vq >= vs[i0] { RETURN LIST(ds[i0], ss[i0], alts[i0]). }
    IF vq <= vs[i1] { RETURN LIST(ds[i1], ss[i1], alts[i1]). }
    FROM { LOCAL k IS i0 + 1. } UNTIL k > i1 STEP { SET k TO k + 1. } DO {
        IF vs[k] <= vq {
            LOCAL span IS vs[k - 1] - vs[k].
            LOCAL f IS 0.
            IF ABS(span) > 0.000000001 { SET f TO (vs[k - 1] - vq) / span. }
            RETURN LIST(ds[k - 1] * (1 - f) + ds[k] * f,
                        ss[k - 1] * (1 - f) + ss[k] * f,
                        alts[k - 1] * (1 - f) + alts[k] * f).
        }
    }
    RETURN LIST(ds[i1], ss[i1], alts[i1]).
}

// The reference drag at a speed, by direct index; clamped at both ends, never extrapolated.
FUNCTION grdDragAt {
    PARAMETER vrel.
    IF NOT GRD_HAVE { RETURN -1. }
    LOCAL i IS (GRD_VHI - vrel) / GRD_STEP.
    IF i <= 0 { RETURN GRD_DRAG[0]. }
    LOCAL i0 IS FLOOR(i).
    IF i0 >= GRD_N - 1 { RETURN GRD_DRAG[GRD_N - 1]. }
    LOCAL f IS i - i0.
    IF f < 0 { SET f TO 0. }
    IF f > 1 { SET f TO 1. }
    RETURN GRD_DRAG[i0] * (1 - f) + GRD_DRAG[i0 + 1] * f.
}

// The reference sink rate at a speed, as grdDragAt.
FUNCTION grdSinkAt {
    PARAMETER vrel.
    IF NOT GRD_HAVE { RETURN 0. }
    LOCAL i IS (GRD_VHI - vrel) / GRD_STEP.
    IF i <= 0 { RETURN GRD_SINK[0]. }
    LOCAL i0 IS FLOOR(i).
    IF i0 >= GRD_N - 1 { RETURN GRD_SINK[GRD_N - 1]. }
    LOCAL f IS i - i0.
    IF f < 0 { SET f TO 0. }
    IF f > 1 { SET f TO 1. }
    RETURN GRD_SINK[i0] * (1 - f) + GRD_SINK[i0 + 1] * f.
}


// --- the tracker -----------------------------------------------------------
GLOBAL TRK_K_DRAG IS 2.         // deg of bank per m/s^2 of drag error
GLOBAL TRK_TAPER IS 200.        // m/s above the grid's lower end over which the correction fades out:
                                //   the reference is weakest at its last point
GLOBAL TRK_MAX IS 25.           // deg: the largest correction, so a bad reference cannot command a
                                //   large bank change on its own
GLOBAL TRK_ON IS FALSE.         // the gate's state, held across ticks for the hysteresis
GLOBAL TRK_ERR IS 0.            // the last drag error (logged)
GLOBAL TRK_CORR IS 0.           // the last correction (logged)

// The correction to add to the feedforward bank. More bank lowers the path into denser air and
// drag rises, so drag above the reference means too much bank: the correction is negative.
FUNCTION trkCorrection {
    PARAMETER vrel, dragMeas.
    // an explicit gate with hysteresis, so no correction is made from a reference that does not
    // yet cover the vehicle's speed
    IF TRK_ON {
        IF dragMeas < GRD_DRAG_OFF { SET TRK_ON TO FALSE. }
    } ELSE {
        IF dragMeas >= GRD_DRAG_ON { SET TRK_ON TO TRUE. }
    }
    IF NOT TRK_ON OR NOT GRD_HAVE {
        SET TRK_ERR TO 0.
        SET TRK_CORR TO 0.
        RETURN 0.
    }
    IF vrel > GRD_VHI OR vrel < GRD_VLO {
        SET TRK_ERR TO 0.
        SET TRK_CORR TO 0.
        RETURN 0.
    }
    // fade the correction out near the grid's lower end (TRK_TAPER)
    LOCAL taper IS 1.
    IF TRK_TAPER > 0 {
        SET taper TO (vrel - GRD_VLO) / TRK_TAPER.
        IF taper < 0 { SET taper TO 0. }
        IF taper > 1 { SET taper TO 1. }
    }
    LOCAL ref IS grdDragAt(vrel).
    IF ref < 0 {
        SET TRK_ERR TO 0.
        SET TRK_CORR TO 0.
        RETURN 0.
    }
    SET TRK_ERR TO dragMeas - ref.
    // the taper before the clamp, so the correction fades smoothly instead of hitting the limit
    LOCAL c IS 0 - TRK_K_DRAG * TRK_ERR * taper.
    IF c > TRK_MAX { SET c TO TRK_MAX. }
    IF c < 0 - TRK_MAX { SET c TO 0 - TRK_MAX. }
    SET TRK_CORR TO c.
    RETURN c.
}

// --- guidance state --------------------------------------------------------
//  The bank's side (reversals), its deadband and its rate limit. Separate from the tracker: the
//  lateral logic runs from the interface, the tracker only once drag is measurable.
GLOBAL GD_SIGN IS 1.
GLOBAL GD_BANK IS 0.            // the last commanded bank, deg, signed
GLOBAL GD_RATE IS 0.            // the last commanded roll rate, deg/s (the slew is acceleration-limited)
GLOBAL GD_REVERSALS IS 0.
GLOBAL GD_AZ IS 0.              // the last azimuth error (logged)
GLOBAL GD_DB IS 0.              // the last deadband (logged)
GLOBAL GD_T IS 0.

FUNCTION gdReset {
    SET GD_SIGN TO 1.
    SET GD_BANK TO 0.
    SET GD_RATE TO 0.
    SET GD_REVERSALS TO 0.
    SET GD_T TO TIME:SECONDS.
}

// One guidance step. `magnitude` is the unsigned bank (the feedforward plus the tracker's
// correction); this picks the side and slews the bank toward it.
FUNCTION gdStep {
    PARAMETER magnitude, azErr, deadband.
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS now - GD_T.
    SET GD_T TO now.
    IF dt <= 0 OR dt > 5 { SET dt TO 0.2. }
    SET GD_AZ TO azErr.
    SET GD_DB TO deadband.
    // reverse when the azimuth error passes the deadband on the side opposite the bank. The
    // deadband follows the 2.14.1 schedule (eprAzDeadband): wide early, tight late, since each
    // reversal costs RCS propellant.
    IF azErr * GD_SIGN < 0 - deadband {
        SET GD_SIGN TO 0 - GD_SIGN.
        SET GD_REVERSALS TO GD_REVERSALS + 1.
    }
    LOCAL want IS GD_SIGN * ABS(magnitude).
    // the rate and acceleration limits the vehicle is held to, as the prediction model's bank slew,
    // in three clamps: the rate limit; the braking bound SQRT(2 a |err|), the fastest rate that
    // still stops at the target (without it the command overshoots and hunts); the acceleration
    // limit
    LOCAL err IS want - GD_BANK.
    LOCAL wantRate IS err / dt.
    IF wantRate > EPR_ROLL_RATE_LIMIT { SET wantRate TO EPR_ROLL_RATE_LIMIT. }
    IF wantRate < 0 - EPR_ROLL_RATE_LIMIT { SET wantRate TO 0 - EPR_ROLL_RATE_LIMIT. }
    LOCAL vmax IS SQRT(2 * EPR_ROLL_ACCEL_LIMIT * ABS(err)).
    IF wantRate > vmax { SET wantRate TO vmax. }
    IF wantRate < 0 - vmax { SET wantRate TO 0 - vmax. }
    LOCAL aStep IS EPR_ROLL_ACCEL_LIMIT * dt.
    IF wantRate > GD_RATE + aStep { SET wantRate TO GD_RATE + aStep. }
    IF wantRate < GD_RATE - aStep { SET wantRate TO GD_RATE - aStep. }
    SET GD_RATE TO wantRate.
    SET GD_BANK TO GD_BANK + wantRate * dt.
    RETURN GD_BANK.
}
