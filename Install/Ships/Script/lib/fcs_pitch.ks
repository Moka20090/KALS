@LAZYGLOBAL OFF.
// ============================================================================
//  FCS_PITCH.KS  --  THE PITCH LOOP: Nz -> ALPHA (TABLE + TRIM)
// ============================================================================
//  The guidance commands Nz (TAEM tg["nz_total"], A/L alg_nz_total); the flight side turns it into an attitude (the
//  guidance does not invert the aero model). Every update:
//      alpha_cmd = alpha_ff(nz_total, qbar, Mach) + TRIM, held inside alpha_limits(..., table=True)
//      alpha_cmd slewed at NZL_ALPHA_RATE (3 deg/s; CSS's pitch rate where lower -- the caller passes the limit,
//              taemg_alpha_rate(M))
//  Every FD window:
//      TRIM += KI * Q_REF / max(q, Q_MIN) * (nz_cmd - nz_meas) * dt, clamped +-10, skipped when the command is
//              saturated in the error's direction
//  alpha_ff is the 200-point table NZL_ALPHA_OF_L in normalised lift (Sol: built WITH the (0, 0) lift key), generated
//  with every constant into taemg_const.ks (TG_<name>; TG_P_<name> = entry_predict's). fcs_alpha_cmd / fcs_trim_update /
//  fcs_alpha_slew / fcs_window_end work on tg (TAEM), fcs_al_alpha / fcs_al_trim on fc (A/L). THE CALLER measures Nz by
//  finite difference (FD_LIFT, no part) and steers (LOCK STEERING) to the slewed alpha; at the TAEM switch it seeds the
//  trim (fcs_trim_seed) and alpha_rl with the entry's alpha COMMAND.
// ============================================================================

RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/taemg_const.ksm" IF O6_KSM_GO ELSE "0:/lib/taemg_const.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/taemg_const.ks").

FUNCTION fcs_hermite {                      // the Hermite value at x: keys LIST(x, y, in, out), linear search
    PARAMETER keys, x.
    LOCAL n IS keys:LENGTH.
    IF x <= keys[0][0] { RETURN keys[0][1]. }
    IF x >= keys[n - 1][0] { RETURN keys[n - 1][1]. }
    FROM { LOCAL i IS 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        IF keys[i][0] >= x {
            LOCAL x0 IS keys[i - 1][0]. LOCAL y0 IS keys[i - 1][1]. LOCAL o0 IS keys[i - 1][3].
            LOCAL x1 IS keys[i][0]. LOCAL y1 IS keys[i][1]. LOCAL i1 IS keys[i][2].
            LOCAL span IS x1 - x0.
            LOCAL t IS (x - x0) / span.
            LOCAL m0 IS o0 * span.
            LOCAL m1 IS i1 * span.
            LOCAL t2 IS t * t.
            LOCAL t3 IS t2 * t.
            RETURN ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                    + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1).
        }
    }
    RETURN keys[n - 1][1].
}

FUNCTION fcs_alpha_of_lift {                // alpha for a given lift -> LIST(alpha, sat)
    PARAMETER l.
    IF l <= TG_NZL_L_LO { RETURN LIST(TG_AOA_SOLVE_LO, -1). }
    IF l >= TG_NZL_L_HI { RETURN LIST(TG_AOA_SOLVE_HI, 1). }
    LOCAL x IS (l - TG_NZL_L_LO) / TG_NZL_L_STEP.
    LOCAL i IS MIN(FLOOR(x), TG_NZL_TAB_N - 2).
    LOCAL f IS x - i.
    RETURN LIST(TG_NZL_ALPHA_OF_L[i] + f * (TG_NZL_ALPHA_OF_L[i + 1] - TG_NZL_ALPHA_OF_L[i]), 0).
}

// the lift's Mach factor, memoised: a pitch step needs it three times at one Mach (alpha_ff and alpha_limits' two),
// so one hermite serves all three
GLOBAL fcsLmMach IS -99999.
GLOBAL fcsLmVal IS 0.
FUNCTION fcs_lift_mach {
    PARAMETER mach.
    IF mach <> fcsLmMach {
        SET fcsLmVal TO fcs_hermite(TG_P_LIFT_MACH, mach).
        SET fcsLmMach TO mach.
    }
    RETURN fcsLmVal.
}

FUNCTION fcs_alpha_ff {                     // the table alpha for a given Nz, qbar and Mach -> LIST(alpha, sat)
    PARAMETER nz, qb, mach.                 // (qb: Q is a kOS function)
    IF qb <= 0.0 { RETURN LIST(TG_AOA_SOLVE_LO, -1). }
    RETURN fcs_alpha_of_lift(nz * TG_GO / (qb * TG_P_K_LIFT_V7 * fcs_lift_mach(mach))).
}

FUNCTION fcs_alpha_limits {                 // the lower and upper alpha limits (table form) -> LIST(ll, ul)
    PARAMETER mach, qbar, qbref.
    LOCAL ul IS 0.
    LOCAL ll IS 0.
    IF mach < TG_ALPULCM1 { SET ul TO taemg_midval(TG_ALPULC1 * mach + TG_ALPULC2, TG_ALPULC3, TG_ALPULC4). }
    ELSE { SET ul TO taemg_midval(TG_ALPULC5 * mach + TG_ALPULC6, TG_ALPULC3, TG_ALPULC4). }
    IF mach < TG_ALPLLCM1 { SET ll TO taemg_midval(TG_ALPLLC1 * mach + TG_ALPLLC2, TG_ALPLLC7, TG_ALPLLC8). }
    ELSE IF mach < TG_ALPLLCM2 { SET ll TO taemg_midval(TG_ALPLLC3 * mach + TG_ALPLLC4, TG_ALPLLC7, TG_ALPLLC8). }
    ELSE { SET ll TO taemg_midval(TG_ALPLLC5 * mach + TG_ALPLLC6, TG_ALPLLC7, TG_ALPLLC8). }
    LOCAL shift IS MAX(fcs_alpha_ff(1.0, qbar, mach)[0] - fcs_alpha_ff(1.0, MAX(qbref, 1.0), mach)[0], 0.0).
    RETURN LIST(ll, MIN(ul + shift, TG_ALPHA_LIM_MAX)).
}

// ---------------------------------------------------------------- TAEM's loop (on tg)
FUNCTION fcs_alpha_cmd {                    // the alpha command: the table value plus the trim, limited
    PARAMETER tg, st.
    LOCAL fs IS fcs_alpha_ff(tg["nz_total"], st["qbar"], st["mach"]).
    LOCAL ff IS fs[0].
    LOCAL sat IS fs[1].
    LOCAL lim IS fcs_alpha_limits(st["mach"], st["qbar"], tg["qbref"]).
    LOCAL raw IS ff + tg["nzl_trim"].
    LOCAL cmd IS raw.
    IF raw > lim[1] { SET cmd TO lim[1]. SET sat TO 1. }
    ELSE IF raw < lim[0] { SET cmd TO lim[0]. SET sat TO -1. }
    SET tg["alpha_ff"] TO ff.
    SET tg["alpha_lim_hi"] TO lim[1].
    SET tg["nz_sat"] TO sat.
    RETURN cmd.
}

FUNCTION fcs_trim_update {                  // the Nz-error integrator for TRIM (every FD window)
    PARAMETER tg, nz_meas, qbar.
    LOCAL err IS tg["nz_total"] - nz_meas.
    SET tg["nz_meas"] TO nz_meas.
    SET tg["nz_err"] TO err.
    IF (tg["nz_sat"] > 0 AND err > 0.0) OR (tg["nz_sat"] < 0 AND err < 0.0) { RETURN. }
    LOCAL k IS TG_NZL_KI * TG_NZL_Q_REF / MAX(qbar, TG_NZL_Q_MIN).
    SET tg["nzl_trim"] TO taemg_midval(tg["nzl_trim"] + k * err * TG_DTG, -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX).
}

FUNCTION fcs_alpha_slew {                   // the alpha command slewed at NZL_ALPHA_RATE
    PARAMETER tg, cmd, dt, rlim IS -1.      // rlim: deg/s (taemg_alpha_rate(M)); -1 = TG_NZL_ALPHA_RATE
    IF TG_NZL_ALPHA_RATE > 0.0 AND tg:HASKEY("alpha_rl") {
        LOCAL prev IS tg["alpha_rl"].
        LOCAL lim IS (CHOOSE rlim IF rlim >= 0 ELSE TG_NZL_ALPHA_RATE) * dt.
        IF cmd > prev + lim { SET cmd TO prev + lim. SET tg["alpha_rl_bind"] TO 1. }
        ELSE IF cmd < prev - lim { SET cmd TO prev - lim. SET tg["alpha_rl_bind"] TO -1. }
    }
    SET tg["alpha_rl"] TO cmd.
    RETURN cmd.
}

FUNCTION fcs_window_end {                   // end of an FD window: the rate limit's binding sign feeds the anti-windup
    PARAMETER tg, nz_meas, qbar.
    IF tg["alpha_rl_bind"] <> 0 AND tg["nz_sat"] = 0 { SET tg["nz_sat"] TO tg["alpha_rl_bind"]. }
    fcs_trim_update(tg, nz_meas, qbar).
}

FUNCTION fcs_trim_seed {                    // at the TAEM switch, TRIM0 = the entry's alpha command
    PARAMETER tg, a_ent, nz0, qbar, mach.   //   - alpha_ff(the measured Nz); alpha_rl = that command
    SET tg["nzl_trim"] TO taemg_midval(a_ent - fcs_alpha_ff(nz0, qbar, mach)[0], -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX).
    SET tg["alpha_rl"] TO a_ent.
}

// ---------------------------------------------------------------- A/L's loop (on fc)
FUNCTION fcs_al_alpha {                     // the A/L alpha command (alpha_limits with qbref = qbar)
    PARAMETER fc, nz_total, qbar, mach, dt, rlim IS -1, amax IS 999.   // rlim as fcs_alpha_slew's; amax the tail's
                                                                        //   clearance: AL_THETA_TD_MAX - gamma (lib_land)
    LOCAL fs IS fcs_alpha_ff(nz_total, qbar, mach).
    LOCAL ff IS fs[0].
    LOCAL sat IS fs[1].
    LOCAL lim IS fcs_alpha_limits(mach, qbar, qbar).
    LOCAL ahi IS MIN(lim[1], amax).
    LOCAL raw IS ff + fc["trim"].
    LOCAL cmd IS raw.
    IF raw > ahi { SET cmd TO ahi. SET sat TO 1. }
    ELSE IF raw < lim[0] { SET cmd TO lim[0]. SET sat TO -1. }
    SET fc["nz_sat"] TO sat.
    SET fc["alpha_ff"] TO ff.
    LOCAL rl IS (CHOOSE rlim IF rlim >= 0 ELSE TG_NZL_ALPHA_RATE) * dt.
    IF cmd > fc["alpha_rl"] + rl { SET cmd TO fc["alpha_rl"] + rl. SET fc["rl_bind"] TO 1. }
    ELSE IF cmd < fc["alpha_rl"] - rl { SET cmd TO fc["alpha_rl"] - rl. SET fc["rl_bind"] TO -1. }
    SET fc["alpha_rl"] TO cmd.
    RETURN cmd.
}

FUNCTION fcs_al_trim {                      // the A/L trim integrator (once per finite-difference window, dt = LD_AL_FD_WIN)
    PARAMETER fc, nz_cmd, nz_meas, qbar, dt.
    IF fc["rl_bind"] <> 0 AND fc["nz_sat"] = 0 { SET fc["nz_sat"] TO fc["rl_bind"]. }
    LOCAL err IS nz_cmd - nz_meas.
    SET fc["nz_err"] TO err.
    IF (fc["nz_sat"] > 0 AND err > 0.0) OR (fc["nz_sat"] < 0 AND err < 0.0) { RETURN. }
    LOCAL k IS TG_NZL_KI * TG_NZL_Q_REF / MAX(qbar, TG_NZL_Q_MIN).
    SET fc["trim"] TO MAX(-TG_NZL_TRIM_MAX, MIN(TG_NZL_TRIM_MAX, fc["trim"] + k * err * dt)).
}
