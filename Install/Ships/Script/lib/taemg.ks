@LAZYGLOBAL OFF.
// ============================================================================
//  TAEMG.KS  --  THE TAEM GUIDANCE (FSSR G4.9)
// ============================================================================
//  A library; it loads taemg_const.ks. The state is three LEXICONs:
//      tg  -- the guidance state (taemg_init builds it),   st -- the vehicle state the caller builds each cycle,
//      g   -- the geometry from taemg_gtp (stored in tg["g"]).
//  Constants: TG_<name>, written into taemg_const.ks by gen_taemg.py and never typed here.
//  Units: metric inside (m, m/s, Pa, deg).
//  Not implemented: the switched-off options TG_FADE_ALL_TRANS and ZOOM_DPSAC_PATH, and the simulation-only
//  CSS_PILOT_MODEL.
//  kOS differences handled: MIDVAL has no NaN (kOS refuses NaN / infinity on its stack); trig is in degrees (TG_D2R =
//  pi/180 converts radians); MOD is never used on a signed angle (taemg_norm180 loops).
//  The Sol reference: the JNSQ reference lowered to Sol's density altitude (TG_DALT_DH), the Sol atmosphere from
//  lib_solq_atm.ks (solq_atm.density at the nominal latitude / day).
//  The caller owns: the runway frame (st's x, y, h, psd, xdot, ydot, gam, costh), the air data
//  (mach, qbar, surfv, vh, hdot, acc_drag), the pitch loop that flies tg["nz_total"], the bank that flies
//  tg["phic_at"] (tg sign: see taemg_bank_to_ship), the speedbrake that flies tg["dsbc"] (orbiter degrees; hinge
//  = 2 x each rudder panel's deploy angle). Tested offline by taem_selftest.ks.
// ============================================================================

RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/taemg_const.ksm" IF O6_KSM_GO ELSE "0:/lib/taemg_const.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/taemg_const.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_solq_atm.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_solq_atm.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_solq_atm.ks").

// the active runway's aim point and what derives from it (set by taemg_set_aim)
GLOBAL TG_X_AIM IS TG_X_AIM_NOM.
GLOBAL TG_XALI_X IS TG_X_AIM - TG_HALI / TG_TGGS.
GLOBAL TG_R2MAX IS 130000.0 * TG_FT + (TG_X_AIM_BASE - TG_X_AIM).
GLOBAL tgDsbMax IS TG_DSBMAX.              // deg: the subsonic speedbrake's upper limit above DSBSUP; starts at TG_DSBMAX (98.6),
                                           //   lib_land's ldSbCap sets it in flight

FUNCTION taemg_set_aim {                    // sets the aim point and what derives from it for the named runway; sfx: the
    PARAMETER nm, sfx IS 0.0.               //   short-field shift (m) of a runway not in TG_SHORT_FIELD_AIM_FT (lib_land's
    LOCAL sf IS sfx.                        //   ldAimLaw: A/L's slope law, as alg_aim_shift and the HUD's x_ogs take it)
    IF TG_SHORT_FIELD_AIM_FT:HASKEY(nm) { SET sf TO TG_SHORT_FIELD_AIM_FT[nm] * TG_FT. }
    SET TG_X_AIM TO TG_X_AIM_NOM - sf.
    SET TG_XALI_X TO TG_X_AIM - TG_HALI / TG_TGGS.
    SET TG_R2MAX TO 130000.0 * TG_FT + (TG_X_AIM_BASE - TG_X_AIM).
}

// ---------------------------------------------------------------- helpers
FUNCTION taemg_midval {                     // the middle of three (kOS has no NaN)
    PARAMETER a, b, c.
    RETURN MAX(MIN(a, b), MIN(MAX(a, b), c)).
}

FUNCTION taemg_bind_of {                    // -1 if x is below the band lo..hi, 1 above, 0 inside (lo, hi in any order)
    PARAMETER x, lo, hi.
    LOCAL blo IS MIN(lo, hi).
    LOCAL bhi IS MAX(lo, hi).
    IF x < blo { RETURN -1. }
    IF x > bhi { RETURN 1. }
    RETURN 0.
}

FUNCTION taemg_norm180 {                    // wraps an angle into +-180 deg (a loop, never MOD)
    PARAMETER x.
    UNTIL x <= 180.0 { SET x TO x - 360.0. }
    UNTIL x > -180.0 { SET x TO x + 360.0. }
    RETURN x.
}

// ---------------------------------------------------------------- the reference profile
FUNCTION taemg_href_jnsq {                  // href on the JNSQ reference
    PARAMETER drpred.
    IF drpred <= 0.0 { RETURN TG_HALI + TG_TGGS * drpred. }
    IF drpred >= TG_PBRC { RETURN TG_PBHC + TG_PBGC * (drpred - TG_PBRC). }
    RETURN TG_HALI + (TG_TGGS + (TG_CUBIC_C3 + drpred * TG_CUBIC_C4) * drpred) * drpred.
}

FUNCTION taemg_dhdrrf_jnsq {                // dhdrrf on the JNSQ reference
    PARAMETER drpred.
    IF drpred <= 0.0 { RETURN TG_TGGS. }
    IF drpred >= TG_PBRC { RETURN TG_PBGC. }
    RETURN taemg_midval(TG_TGGS + drpred * (2.0 * TG_CUBIC_C3 + 3.0 * TG_CUBIC_C4 * drpred), TG_PBGC, TG_TGGS).
}

FUNCTION taemg_dalt_dh {                    // the Sol density-altitude offset and its slope
    PARAMETER h.
    LOCAL n IS TG_DALT_DH:LENGTH.
    IF h <= 0.0 { RETURN LIST(TG_DALT_DH[0], 0.0). }
    IF h >= TG_DALT_STEP * (n - 1) { RETURN LIST(TG_DALT_DH[n - 1], 0.0). }
    LOCAL k IS FLOOR(h / TG_DALT_STEP).
    LOCAL f IS (h - TG_DALT_STEP * k) / TG_DALT_STEP.
    RETURN LIST(TG_DALT_DH[k] + (TG_DALT_DH[k + 1] - TG_DALT_DH[k]) * f,
                (TG_DALT_DH[k + 1] - TG_DALT_DH[k]) / TG_DALT_STEP).
}

FUNCTION taemg_href {                       // href on the Sol reference
    PARAMETER drpred.
    LOCAL h IS taemg_href_jnsq(drpred).
    IF NOT TG_IS_SOLQ { RETURN h. }
    RETURN h - taemg_dalt_dh(h)[0].
}

FUNCTION taemg_dhdrrf {                     // dhdrrf on the Sol reference
    PARAMETER drpred.
    IF NOT TG_IS_SOLQ { RETURN taemg_dhdrrf_jnsq(drpred). }
    RETURN taemg_dhdrrf_jnsq(drpred) * (1.0 - taemg_dalt_dh(taemg_href_jnsq(drpred))[1]).
}

FUNCTION taemg_qbref {                      // the reference dynamic pressure (Pa) at the range drpred (m)
    PARAMETER drpred.
    IF drpred >= TG_PBRCQ { RETURN taemg_midval(TG_QBRLL + TG_QBC1 * (drpred - TG_PBRCQ), TG_QBRLL, TG_QBRML). }
    RETURN taemg_midval(TG_QBRUL + TG_QBC2 * drpred, TG_QBRLL, TG_QBRUL).
}

FUNCTION taemg_en_of {                      // the nominal energy altitude at a range
    PARAMETER drpred.
    LOCAL h IS taemg_href(drpred).
    LOCAL rho IS sqa_density(h).
    IF rho <= 0.0 { RETURN h + TG_EN_KIN_MAX. }
    RETURN h + MIN(taemg_qbref(drpred) / (rho * TG_GO), TG_EN_KIN_MAX).
}

FUNCTION taemg_en_slope {                   // the slope of taemg_en_of at drpred: a central difference over +-200 m
    PARAMETER drpred.
    RETURN (taemg_en_of(drpred + 200.0) - taemg_en_of(drpred - 200.0)) / (2.0 * 200.0).
}

FUNCTION taemg_xhac_of {                    // the HAC's x, where the glideslope is at the HAC height (NEP or MEP)
    PARAMETER nep.
    LOCAL h IS CHOOSE TG_H_HAC_NEP IF nep ELSE TG_H_HAC_MEP.
    RETURN TG_X_AIM - h / TG_TGGS.
}

FUNCTION taemg_drpred_of {                  // the range to the A/L interface from rpred, the range to x = 0
    PARAMETER rpred.
    RETURN rpred + TG_XALI_X.
}

FUNCTION taemg_rturn_of {                   // the spiral HAC's radius (m) with psha deg of turn to go
    PARAMETER psha, rf, r2.
    RETURN rf + TG_R1 * psha + r2 * psha * psha.
}

FUNCTION taemg_rpred2_of {                  // the range (m) around the HAC (psha deg) and on to x = 0
    PARAMETER psha, rf, xhac, r2.
    LOCAL arc IS (rf * psha + 0.5 * TG_R1 * psha * psha + (1.0 / 3.0) * r2 * psha ^ 3).
    RETURN arc * TG_D2R - xhac.
}

// ---------------------------------------------------------------- GTP: the geometry
FUNCTION taemg_gtp {
    PARAMETER st, ysgn, iphase, rf, psha_prev, nep, r2, seed IS TRUE.
    LOCAL xhac IS taemg_xhac_of(nep).
    LOCAL x IS st["x"].
    LOCAL y IS st["y"].
    LOCAL xcir IS xhac - x.
    LOCAL signy IS CHOOSE 1.0 IF y >= 0 ELSE -1.0.
    IF iphase = 3 AND xcir < TG_DR4 {
        LOCAL rpred0 IS SQRT(x * x + y * y).
        RETURN LEXICON("rpred", rpred0, "dpsac", 0.0, "psha", 0.0, "rturn", rf, "rcir", 0.0, "xcir", xcir,
                       "ycir", 0.0, "rtan", 0.0, "rpred2", rpred0, "xhac", xhac).
    }
    LOCAL ycir IS ysgn * rf - y.
    LOCAL rcir IS SQRT(xcir * xcir + ycir * ycir).
    LOCAL rturn IS taemg_rturn_of(psha_prev, rf, r2).
    LOCAL rtan IS CHOOSE SQRT(rcir * rcir - rturn * rturn) IF rcir > rturn ELSE 0.0.
    LOCAL pst IS ARCTAN2(ycir, xcir) - ysgn * ARCTAN2(rturn, rtan).
    SET pst TO taemg_norm180(pst).
    LOCAL dpsac IS taemg_norm180(pst - st["psd"]).
    LOCAL pshan IS -pst * ysgn.
    LOCAL at_tangency IS (psha_prev > 0.0) AND (psha_prev <= TG_PSHA3).
    // the overhead's wrap needs a fresh start or a turn past TG_PSHA_UNWRAP_MIN: a straight-in's small turn that
    // crosses the centreline or goes past tangency is that turn done, not a full circle
    LOCAL wrap_ok IS seed OR psha_prev > TG_PSHA_UNWRAP_MIN.
    IF ((NOT at_tangency) AND wrap_ok AND (pshan < -1.0 OR ysgn <> signy)) OR (psha_prev > TG_PSHA_UNWRAP_MIN AND pshan < psha_prev - 180.0) {
        SET pshan TO pshan + 360.0.
    }
    LOCAL psha IS taemg_midval(pshan, 0.0, TG_PSHA_MAX).
    SET rturn TO taemg_rturn_of(psha, rf, r2).
    LOCAL rpred2 IS taemg_rpred2_of(psha, rf, xhac, r2).
    IF iphase < 2 {
        LOCAL mach IS st["mach"].
        LOCAL phavg IS taemg_midval(TG_PHAVGC - TG_PHAVGS * mach, TG_PHAVGLL, TG_PHAVGUL).
        LOCAL rtac IS st["vh"] * st["surfv"] / (TG_GO * TAN(phavg)).
        LOCAL arcac IS rtac * ABS(dpsac * TG_D2R).
        LOCAL a IS rtac * (1.0 - COS(dpsac)).
        LOCAL b IS rtan - rtac * ABS(SIN(dpsac)).
        LOCAL rc IS SQRT(a * a + b * b).
        IF rc > rtan { SET rc TO rtan. }      // G4.204's Eq 4.4 clamp (the RTLS GTP), not G4.9's (as the offline sim)
        SET rtan TO arcac + rc.
    }
    RETURN LEXICON("rpred", rpred2 + rtan, "rpred2", rpred2, "rtan", rtan, "dpsac", dpsac, "psha", psha, "rturn", rturn,
                   "rcir", rcir, "xcir", xcir, "ycir", ycir, "xhac", xhac, "pst", pst).
}

// ---------------------------------------------------------------- the bank limits
FUNCTION taemg_philim_of {
    PARAMETER mach, phase_lim.
    RETURN MIN(MAX(TG_PHILMSUP + TG_PHILS * (mach - TG_PHIM), TG_PHILMSUP), phase_lim).
}

FUNCTION taemg_philim_cap {                 // the bank limit by Mach (HDG with TG_HDG_CSS_OVERBANK: tg["philim"] uncut)
    PARAMETER tg, st.
    LOCAL philimit IS taemg_philim_of(st["mach"], tg["philim"]).
    IF TG_HDG_CSS_OVERBANK AND tg["iphase"] = TG_IPH_HDG { SET philimit TO tg["philim"]. }
    RETURN philimit.
}

FUNCTION taemg_fig317_saving {              // the energy (m) the mep / strt downmode saves at psha deg (FSSR Fig 3-17)
    PARAMETER psha, which.
    LOCAL nmi IS 0.
    IF which = "mep" {
        LOCAL x0 IS TG_FIG317_MEP[0][0]. LOCAL y0 IS TG_FIG317_MEP[0][1].
        LOCAL x1 IS TG_FIG317_MEP[1][0]. LOCAL y1 IS TG_FIG317_MEP[1][1].
        LOCAL ps IS taemg_midval(psha, MIN(x0, x1), MAX(x0, x1)).
        SET nmi TO y0 + (y1 - y0) * (x0 - ps) / (x0 - x1).
    } ELSE {
        LOCAL t IS TG_FIG317_STRT.
        LOCAL n IS t:LENGTH.
        IF psha <= t[0][0] { SET nmi TO t[0][1]. }
        ELSE IF psha >= t[n - 1][0] { SET nmi TO t[n - 1][1]. }
        ELSE {
            SET nmi TO t[n - 1][1].
            FROM { LOCAL i IS 0. } UNTIL i >= n - 1 STEP { SET i TO i + 1. } DO {
                IF (psha >= t[i][0]) AND (psha <= t[i + 1][0]) {
                    SET nmi TO (t[i][1] + (t[i + 1][1] - t[i][1]) * (psha - t[i][0]) / (t[i + 1][0] - t[i][0])).
                    BREAK.
                }
            }
        }
    }
    RETURN MAX(nmi, 0.0) * TG_NMI * TG_GEOM_SCALE * TG_EN_SLOPE_FAR.
}

// ---------------------------------------------------------------- TGINIT
FUNCTION taemg_init {                       // builds the guidance state tg
    PARAMETER st, ysgn, rf IS TG_RFMX, psha0 IS 0.0, phic0 IS 0.0, phic_rate0 IS 0.0.
    LOCAL qb IS 0.0.
    IF st:HASKEY("qbar") { SET qb TO st["qbar"]. }
    RETURN LEXICON(
        "iphase", TG_IPH_ACQ, "tg_end", FALSE, "itran", FALSE,
        "ysgn", ysgn, "ysturn", 0.0, "rf", rf, "r2", TG_R2,
        "philim", TG_PHILM1, "philimit", TG_PHILM1, "phic", 0.0, "phic_at", phic0, "isr", 0,
        "phic_dem", phic0, "phic_rate", phic_rate0,
        "css", "", "css_why", "",
        "nzc", 0.0, "dsbc", TG_DSBSUP, "dsbi", 0.0,
        "qbarf", qb, "qbard", 0.0, "qbd", 0.0,
        "psha_prev", psha0, "first", TRUE,
        "eow", 0.0, "en", 0.0, "en_of_dr", 0.0, "es", 0.0, "esturn", 0.0,
        "est_live", 0.0,
        "emep", 0.0, "emax", 0.0,
        "emin", 0.0, "est", 0.0, "eowerror", 0.0, "deowerr", 0.0,
        "sturn_peak", -1e9, "had_sturn", FALSE,  // the S-turn's peak EOW error (the lead's bound), one flown
        "emoh", 0.0, "ohalrt", FALSE,
        "bind_en", 0, "bind_qb", 0, "bind_rate", 0, "bind_cmd", 0,
        "nz_roll_clamped", 0,
        "alpha_lim_hi", TG_ALPHA_LIM_MAX,
        "en_xed", 0,
        "href", 0.0, "herror", 0.0, "hdref", 0.0, "qbref", 0.0,
        "philim_mach", TG_PHILMSUP, "rerrc", 0.0, "rerrc_valid", FALSE,
        "hac_fallback", FALSE,
        "qberr", 0.0, "drpred", 0.0, "rpred", 0.0, "mep", FALSE,
        "alpha_prev", TG_SB_AOA_FALLBACK,
        "nzl_trim", 0.0, "nz_err", 0.0,
        "alpha_rl_bind", 0,
        "nep", TRUE, "strt", FALSE, "dm_why", "", "dm_msg", "",
        "dm_crew", "",                          // the crew's press, "strt" | "mep" (lib_land from the DAP window; taemg_crew_act)
        "emep_ref", 0.0,
        "dm_rej", "", "drpred_strt", 0.0,
        "rwy_sw", FALSE,                        // the crew's runway switch in effect (a toggle)
        "rwy_strt0", FALSE,                     // strt before the switch (the switch back restores it)
        "dm_msg0", "",                          // dm_msg before MEP (each MEP take saves it; NEP restores it)
        "eowerr_mep", 0.0, "eowerr_strt", 0.0,
        "en_mep", 0.0, "en_strt", 0.0,
        "mep_avail", FALSE, "strt_avail", FALSE,
        "dpsha_mep", 0.0, "dpsha_strt", 0.0, "t_to_hac", 0.0,
        "mep_cyc", 0, "ohalrt_cyc", 0, "below_emep_run", 0,
        "ohalrt_run", 0, "probe_valid", FALSE, "ndm", 0,
        "mep_ever", FALSE,
        "sb_extrap", "").
}

// ---------------------------------------------------------------- TGCOMP
FUNCTION taemg_comp {
    PARAMETER tg, st, g.
    LOCAL dr IS taemg_drpred_of(g["rpred"]).
    SET tg["drpred"] TO dr.
    LOCAL eow IS st["h"] + st["surfv"] ^ 2 / (2.0 * TG_GO).
    SET tg["eow"] TO eow.
    LOCAL sh IS taemg_midval(TG_EN_SLOPE_FAR * (g["rpred2"] - TG_R2MAX), 0.0, TG_ESHFMX).
    SET tg["en_shift"] TO sh.
    LOCAL en0 IS taemg_en_of(dr).           // kept for VERT SIT's energy box (lib_taemdisp: not computed again)
    SET tg["en_of_dr"] TO en0.
    LOCAL en IS en0 - sh.
    SET tg["en"] TO en.
    SET tg["es"] TO en + TG_STURN_DELTA.
    SET tg["esturn"] TO en + TG_STURN_DELTA.
    IF tg["probe_valid"] { SET tg["emep"] TO tg["en_mep"]. }
    ELSE { SET tg["emep"] TO en - TG_EMEP_GAP_M. }
    SET tg["emep_ref"] TO en - taemg_fig317_saving(g["psha"], "mep").
    SET tg["emax"] TO en + TG_EMAX_DELTA.
    SET tg["emin"] TO en - TG_EMIN_DELTA.
    IF tg["probe_valid"] { SET tg["emoh"] TO tg["en_strt"]. }
    ELSE { SET tg["emoh"] TO tg["emep"] - (TG_EMOH_C1 + TG_EMOH_C2 * dr). }
    SET tg["emoh_ref"] TO en - taemg_fig317_saving(g["psha"], "strt").
    SET tg["mep_avail"] TO tg["emep"] < en.
    SET tg["strt_avail"] TO tg["emoh"] < en.
    LOCAL err_prev IS tg["eowerror"].
    SET tg["eowerror"] TO eow - en.
    IF tg["first"] {
        SET tg["deowerr"] TO 0.0.
        SET tg["first"] TO FALSE.
    } ELSE {
        SET tg["deowerr"] TO (tg["eowerror"] - err_prev) / TG_DTG.
    }
    SET tg["est_live"] TO MAX(en - TG_EST_T * tg["deowerr"], en).
    SET tg["est"] TO en + MAX(TG_STURN_DELTA - TG_EST_BAND, 0.0).
    // The S-turn exit lead (a deviation from the FSSR's fixed line): inside the S-turn the exit leads by the energy
    // the reversal will still burn, bounded inside the band.
    // the bound scales with the S-turn's peak excess, TG_EST_LEAD_MAX to TG_EST_LEAD_CAP
    IF tg["iphase"] = TG_IPH_STURN {
        SET tg["sturn_peak"] TO MAX(tg["sturn_peak"], tg["eowerror"]).
        LOCAL lead_max IS taemg_midval(TG_EST_LEAD_K * (tg["sturn_peak"] - TG_STURN_DELTA), TG_EST_LEAD_MAX, TG_EST_LEAD_CAP).
        SET tg["est"] TO tg["est"] + MIN(MAX(-tg["deowerr"] * TG_EST_LEAD_T, 0.0), lead_max).
    }
    SET tg["href"] TO taemg_href(dr).
    SET tg["herror"] TO tg["href"] - st["h"].
    SET tg["hdref"] TO -st["vh"] * taemg_dhdrrf(dr).
    SET tg["qbref"] TO taemg_qbref(dr).
    IF tg["iphase"] = TG_IPH_HDG AND g["psha"] > TG_PSRF {
        LOCAL hrefoh IS tg["href"] - taemg_midval(TG_DHOH1 * (dr - TG_DHOH2), 0.0, TG_DHOH3).
        LOCAL drf IS TG_DRFK * (hrefoh - st["h"]) / (g["psha"] * TG_D2R).
        LOCAL rflim IS ABS(st["vh"]) * TG_DTG / MAX(g["psha"] * TG_D2R, 1e-9).
        SET tg["rf"] TO taemg_midval(tg["rf"] + taemg_midval(drf, -rflim, rflim), TG_RFMN, TG_RFMX).
        LOCAL dr2 IS TG_DR2K * (tg["href"] - st["h"]) / ((g["psha"] * TG_D2R) * g["psha"] * g["psha"]).
        LOCAL darc IS MAX((g["psha"] ^ 3 / 3.0) * TG_D2R, g["psha"] ^ 2).
        LOCAL lim IS ABS(st["vh"]) * TG_DTG / MAX(darc, 1e-9).
        SET tg["r2"] TO taemg_midval(tg["r2"] + taemg_midval(dr2, -lim, lim), TG_R2, TG_R2MX).
    }
    LOCAL qbard IS taemg_midval(TG_CQG * (st["qbar"] - tg["qbarf"]), -TG_QBARDL, TG_QBARDL).
    SET tg["qbarf"] TO tg["qbarf"] + qbard * TG_DTG.
    SET tg["qbard"] TO qbard.
    SET tg["qbd"] TO TG_QBD_CDEQD * tg["qbd"] + TG_QBD_CQDG * qbard.     // the reference's QBD
    SET tg["qberr"] TO tg["qbref"] - tg["qbarf"].
}

// ---------------------------------------------------------------- the downmodes (the probe, the automatic choice)
FUNCTION taemg_probe {
    PARAMETER tg, st, g.
    LOCAL eow IS tg["eow"].
    LOCAL gm IS taemg_gtp(st, tg["ysgn"], tg["iphase"], tg["rf"], tg["psha_prev"], FALSE, tg["r2"], tg["first"]).
    SET tg["en_mep"] TO taemg_en_of(taemg_drpred_of(gm["rpred"])).
    SET tg["eowerr_mep"] TO eow - tg["en_mep"].
    SET tg["dpsha_mep"] TO gm["psha"] - g["psha"].
    LOCAL ys IS -tg["ysgn"].
    LOCAL gs1 IS taemg_gtp(st, ys, tg["iphase"], tg["rf"], 0.0, tg["nep"], tg["r2"]).
    LOCAL gs IS taemg_gtp(st, ys, tg["iphase"], tg["rf"], gs1["psha"], tg["nep"], tg["r2"]).
    SET tg["en_strt"] TO taemg_en_of(taemg_drpred_of(gs["rpred"])).
    SET tg["eowerr_strt"] TO eow - tg["en_strt"].
    SET tg["dpsha_strt"] TO gs["psha"] - g["psha"].
    SET tg["drpred_strt"] TO taemg_drpred_of(gs["rpred"]).
    SET tg["t_to_hac"] TO g["rtan"] / MAX(st["vh"], 1.0).
    SET tg["probe_valid"] TO TRUE.
}

FUNCTION taemg_dm_accept {                  // may downmode which (mep / strt) be taken now? If not, rej gets the reason
    PARAMETER tg, which, rej.
    IF which = "mep" AND NOT TG_DM_MEP_SELECTABLE { rej:ADD(which + ":not-selectable"). RETURN FALSE. }
    IF TG_DOWNMODE_POLICY = "alert" { RETURN TRUE. }
    IF NOT tg["probe_valid"] { rej:ADD(which + ":stale"). RETURN FALSE. }
    LOCAL runc IS CHOOSE tg["ohalrt_run"] IF which = "strt" ELSE tg["below_emep_run"].
    IF runc < TG_DM_PERSIST_CYC { rej:ADD(which + ":persist"). RETURN FALSE. }
    LOCAL after IS CHOOSE tg["eowerr_strt"] IF which = "strt" ELSE tg["eowerr_mep"].
    IF after - tg["eowerror"] <= TG_DM_GAIN_MIN { rej:ADD(which + ":gain"). RETURN FALSE. }
    IF which <> "strt" AND after < TG_DM_AFTER_MIN { rej:ADD(which + ":insufficient"). RETURN FALSE. }
    IF which <> "strt" AND after > TG_DM_AFTER_MAX { rej:ADD(which + ":overshoot"). RETURN FALSE. }
    LOCAL tmin IS CHOOSE TG_DM_T_HAC_STRT IF which = "strt" ELSE TG_DM_T_HAC_MEP.
    IF tg["t_to_hac"] < tmin { rej:ADD(which + ":timing"). RETURN FALSE. }
    IF which = "strt" AND tg["drpred_strt"] < TG_RMINST + TG_DM_STRT_STURN_MARGIN { rej:ADD(which + ":no-sturn-room"). RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION taemg_dm_why {                     // the reason text 'strt h<h> psha<psha>': whole numbers, rounded half to even
    PARAMETER tag, h, psha.
    RETURN tag + " h" + ROUND(h) + " psha" + ROUND(psha).
}

// THE CREW'S PRESS (tg["dm_crew"]: the DAP window's OTT STRT / OTT MEP, in their own row): taken on this cycle with the
// forced branch's changes, or refused with the reason in dm_rej. Each press TOGGLES (SPEC 50 ITEM 6 OVHD / STRT and
// ITEM 7 NEP / MEP), so every OTT change (STRT, MEP, RWY) is reversible: STRT again = back to the overhead (the HAC to
// the other side, PSHA reset), MEP again = back to NEP (dm_msg back to dm_msg0). The crew's STRT is taken under MEP
// too (the closed ladder does not refuse it); the straight-in needs strt_avail, MEP mep_avail (VERT SIT's EMOH arrow /
// MEP mark); TG_DM_MEP_SELECTABLE gates the policy's MEP only. = the offline sim's crew_act.
FUNCTION taemg_crew_act {
    PARAMETER tg, st, g.
    LOCAL req IS tg["dm_crew"].
    SET tg["dm_crew"] TO "".
    IF req = "strt" {
        IF tg["strt"] {                    // back to the overhead (ITEM 6 is a toggle)
            SET tg["strt"] TO FALSE.
            SET tg["ysgn"] TO -tg["ysgn"].
            SET tg["psha_prev"] TO 0.0.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("crew:ovhd", st["h"], g["psha"]).
            SET tg["dm_msg"] TO "".
            SET tg["dm_rej"] TO "".
        }
        ELSE IF tg["iphase"] <> TG_IPH_ACQ AND tg["iphase"] <> TG_IPH_STURN { SET tg["dm_rej"] TO "crew-strt:phase". }   // the S-turn too
        ELSE IF NOT tg["strt_avail"] { SET tg["dm_rej"] TO "crew-strt:unavail". }
        ELSE {
            SET tg["strt"] TO TRUE.
            SET tg["ysgn"] TO -tg["ysgn"].
            SET tg["psha_prev"] TO 0.0.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("crew:strt", st["h"], g["psha"]).
            SET tg["dm_msg"] TO TG_DM_MSG_STRT.
            SET tg["dm_rej"] TO "".
        }
    } ELSE IF req = "mep" {
        IF NOT tg["nep"] {                      // back to NEP (ITEM 7 is a toggle)
            SET tg["nep"] TO TRUE.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("crew:nep", st["h"], g["psha"]).
            SET tg["dm_msg"] TO tg["dm_msg0"].
            SET tg["dm_rej"] TO "".
        }
        ELSE IF tg["iphase"] <> TG_IPH_ACQ AND tg["iphase"] <> TG_IPH_STURN { SET tg["dm_rej"] TO "crew-mep:phase". }    // the S-turn too
        ELSE IF NOT tg["mep_avail"] { SET tg["dm_rej"] TO "crew-mep:unavail". }
        ELSE {
            SET tg["nep"] TO FALSE.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("crew:mep", st["h"], g["psha"]).
            SET tg["dm_msg0"] TO tg["dm_msg"].
            SET tg["dm_msg"] TO TG_DM_MSG_MEP.
            SET tg["dm_rej"] TO "".
        }
    } ELSE {
        SET tg["dm_rej"] TO "crew:unknown".
    }
}

// THE CREW'S RUNWAY SWITCH (the DAP window's SW RWY): one press = the other end of the runway, before the HAC, no
// message, the approach (strt) kept; a second press switches back, the approach before it restored. With the
// straight-in it saves more energy.
// lib_land redesignates the runway first (the frame, the aim: NAV's
// part) and re-takes st in the new frame, then taemg_rwy_switch, before the cycle: TGINIT on a redesignation runs
// "before any other TAEM guidance function" (FSSR 4.6.2.3, "whenever RW_ID != RW_IDO"); TGXHAC Eq 2.6 resets PSHA on a
// "runway change". Never through taemg_crew_act: it runs only inside the cycle's acquisition branch, and after a frame
// switch the cycle can leave that phase first (the press dropped, the old HAC side flown in the new frame).
// = the offline sim's rwy_switch_rej / rwy_switch.
FUNCTION taemg_rwy_rej {                    // "" to take the switch now, else why not (hasAlt: another end)
    PARAMETER tg, hasAlt.
    IF NOT tg["nep"] { RETURN "crew-rwy:ladder-closed". }
    // any switch in the S-turn too (an undo there as well)
    IF tg["iphase"] <> TG_IPH_ACQ AND tg["iphase"] <> TG_IPH_STURN { RETURN "crew-rwy:phase". }
    IF NOT hasAlt { RETURN "crew-rwy:none". }
    RETURN "".
}

FUNCTION taemg_rwy_switch {                 // the switch's guidance part: st in the NEW runway's frame, nm its name
    PARAMETER tg, st, nm.
    SET tg["dm_why"] TO taemg_dm_why("crew:rwy " + nm, st["h"], tg["psha_prev"]).   // the old HAC turn to go
    // the runway only: the approach (strt) kept; a second press switches back
    SET tg["rwy_sw"] TO NOT tg["rwy_sw"].
    LOCAL same IS CHOOSE 1.0 IF st["y"] >= 0.0 ELSE -1.0.      // the HAC on the vehicle's side
    SET tg["ysgn"] TO CHOOSE same IF tg["strt"] ELSE -same.     // = the straight-in; the overhead: the other side
    SET tg["psha_prev"] TO 0.0.
    SET tg["first"] TO TRUE.
    SET tg["dm_rej"] TO "".
    SET tg["dm_crew"] TO "".
}

FUNCTION taemg_dm_act {                     // the downmode ladder: straight-in first, then MEP; refusals in tg["dm_rej"]
    PARAMETER tg, st, g.
    IF tg["dm_crew"] <> "" { taemg_crew_act(tg, st, g). RETURN. }    // the crew's press first, whatever the policy
    IF TG_DOWNMODE_POLICY = "off" { SET tg["dm_rej"] TO "". RETURN. }  // dm_rej = this cycle's refusals (a crew one too)
    IF NOT tg["nep"] { SET tg["dm_rej"] TO "ladder-closed". RETURN. }
    IF TG_DOWNMODE_POLICY = "force_mep" OR TG_DOWNMODE_POLICY = "force_strt" OR TG_DOWNMODE_POLICY = "force_both" {
        IF tg["ndm"] * TG_DTG < TG_DM_FORCE_T { RETURN. }
        IF TG_DOWNMODE_POLICY = "force_both" {
            IF NOT tg["strt"] {
                SET tg["strt"] TO TRUE.
                SET tg["ysgn"] TO -tg["ysgn"].
                SET tg["psha_prev"] TO 0.0.
                SET tg["first"] TO TRUE.
                SET tg["dm_why"] TO taemg_dm_why("FORCEboth:strt", st["h"], g["psha"]).
                SET tg["dm_msg"] TO TG_DM_MSG_STRT.
            } ELSE IF tg["nep"] {
                SET tg["nep"] TO FALSE.
                SET tg["first"] TO TRUE.
                SET tg["dm_why"] TO taemg_dm_why("FORCEboth:mep", st["h"], g["psha"]).
                SET tg["dm_msg0"] TO tg["dm_msg"].
                SET tg["dm_msg"] TO TG_DM_MSG_MEP.
            }
            RETURN.
        }
        IF TG_DOWNMODE_POLICY = "force_strt" {
            IF tg["strt"] { RETURN. }
            SET tg["strt"] TO TRUE.
            SET tg["ysgn"] TO -tg["ysgn"].
            SET tg["psha_prev"] TO 0.0.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("FORCEstrt", st["h"], g["psha"]).
            SET tg["dm_msg"] TO TG_DM_MSG_STRT.
        } ELSE {
            SET tg["nep"] TO FALSE.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("FORCEmep", st["h"], g["psha"]).
            SET tg["dm_msg0"] TO tg["dm_msg"].
            SET tg["dm_msg"] TO TG_DM_MSG_MEP.
        }
        RETURN.
    }
    LOCAL rej IS LIST().
    SET tg["dm_rej"] TO "".
    IF tg["ohalrt_run"] <= 0 AND tg["below_emep_run"] <= 0 { SET tg["dm_rej"] TO "no-alert". RETURN. }
    IF tg["strt"] { rej:ADD("strt:already"). }
    ELSE IF NOT tg["ohalrt"] {
        IF tg["eow"] >= tg["emoh"] { rej:ADD("strt:energy"). }
        ELSE IF NOT tg["strt_avail"] { rej:ADD("strt:unavail"). }
        ELSE IF g["psha"] <= TG_PSOHAL { rej:ADD("strt:psha"). }
        ELSE { rej:ADD("strt:rpred"). }
    }
    IF (NOT tg["strt"]) AND tg["ohalrt"] {
        IF taemg_dm_accept(tg, "strt", rej) {
            SET tg["strt"] TO TRUE.
            SET tg["ysgn"] TO -tg["ysgn"].
            SET tg["psha_prev"] TO 0.0.
            SET tg["first"] TO TRUE.
            SET tg["dm_why"] TO taemg_dm_why("strt", st["h"], g["psha"]).
            SET tg["dm_msg"] TO TG_DM_MSG_STRT.
            RETURN.
        }
    }
    IF NOT tg["strt"] { rej:ADD("mep:no-strt"). }
    ELSE IF taemg_dm_accept(tg, "mep", rej) {
        SET tg["nep"] TO FALSE.
        SET tg["first"] TO TRUE.
        SET tg["dm_why"] TO taemg_dm_why("mep", st["h"], g["psha"]).
        SET tg["dm_msg0"] TO tg["dm_msg"].
        SET tg["dm_msg"] TO TG_DM_MSG_MEP.
        SET tg["dm_rej"] TO rej:JOIN(" ").
        RETURN.
    }
    SET tg["dm_rej"] TO rej:JOIN(" ").
}

// ---------------------------------------------------------------- TGTRAN
FUNCTION taemg_tran {
    PARAMETER tg, st, g.
    SET tg["itran"] TO FALSE.
    IF tg["iphase"] = TG_IPH_STURN { SET tg["had_sturn"] TO TRUE. }   // the re-arm lockout's memory
    IF tg["iphase"] <> TG_IPH_ACQ {
        SET tg["mep"] TO FALSE.
        SET tg["ohalrt"] TO FALSE.
        SET tg["dm_rej"] TO "".
        // ...and a press: taemg_crew_act's window is the same phase (dropped, never deferred); the S-turn branch
        // takes one there (an undo) or refuses it
        IF tg["iphase"] <> TG_IPH_STURN { SET tg["dm_crew"] TO "". }
    }
    SET tg["probe_valid"] TO FALSE.
    SET tg["ndm"] TO tg["ndm"] + 1.
    IF tg["tg_end"] { RETURN. }
    IF tg["iphase"] = TG_IPH_STURN OR tg["iphase"] = TG_IPH_ACQ OR tg["iphase"] = TG_IPH_HDG { taemg_probe(tg, st, g). }
    IF tg["iphase"] = TG_IPH_PREFINAL {
        LOCAL gates IS (st["h"] <= TG_HALI
                        AND ABS(tg["herror"]) < st["h"] * TG_DEL_H1 - TG_DEL_H2
                        AND ABS(st["y"]) < st["h"] * TG_Y_RANGE1 - TG_Y_RANGE2
                        AND ABS(st["gam"] - TG_GS_STEEP_DEG) < st["h"] * TG_GAMMA_COEF1 - TG_GAMMA_COEF2
                        AND ABS(tg["qberr"]) < TG_QB_ERROR2).
        IF gates OR st["h"] < TG_H_REF1 {
            SET tg["tg_end"] TO TRUE.
            SET tg["itran"] TO TRUE.
            SET tg["why_end"] TO CHOOSE "gates" IF gates ELSE "forced h<H_REF1".
        }
        RETURN.
    }
    IF (tg["iphase"] = TG_IPH_HDG AND g["rpred"] < -taemg_xhac_of(tg["nep"]) + TG_DR3 AND ABS(g["psha"]) < TG_PSHA3)
            OR st["h"] < TG_HMIN3 {
        SET tg["iphase"] TO TG_IPH_PREFINAL.
        SET tg["itran"] TO TRUE.
        SET tg["philim"] TO TG_PHILM3.
        SET tg["phic"] TO tg["phic_at"].
        SET tg["isr"] TO CEILING(TG_RFTC / TG_DTG).
        RETURN.
    }
    IF tg["iphase"] = TG_IPH_STURN {
        // the crew's press here: an undo, or a forward OTT STRT / OTT MEP as in the acquisition phase
        // (taemg_crew_act; no press: nothing changes)
        IF tg["dm_crew"] <> "" { taemg_crew_act(tg, st, g). }
        IF tg["eow"] <= tg["est"] {
            SET tg["iphase"] TO TG_IPH_ACQ.
            SET tg["itran"] TO TRUE.
            SET tg["philim"] TO TG_PHILM1.
        }
        RETURN.
    }
    IF tg["iphase"] = TG_IPH_ACQ {
        IF tg["drpred"] > TG_RMINST AND g["psha"] < TG_PSSTRN AND tg["eow"] > tg["en"] + TG_STURN_DELTA
                AND NOT (tg["had_sturn"] AND tg["deowerr"] < 0.0) {   // no re-arm while the energy still falls
            SET tg["iphase"] TO TG_IPH_STURN.
            SET tg["itran"] TO TRUE.
            SET tg["philim"] TO TG_PHILM0.
            SET tg["ysturn"] TO -tg["ysgn"].
            IF tg["ysturn"] * taemg_norm180(st["psd"]) < 0.0 AND g["psha"] < 90.0 { SET tg["ysturn"] TO -tg["ysturn"]. }
            RETURN.
        }
        SET tg["mep"] TO (tg["eow"] < tg["emep"] AND tg["nep"] AND tg["mep_avail"]).
        IF tg["mep"] {
            SET tg["mep_ever"] TO TRUE.
            SET tg["mep_cyc"] TO tg["mep_cyc"] + 1.
            SET tg["below_emep_run"] TO tg["below_emep_run"] + 1.
        } ELSE {
            SET tg["below_emep_run"] TO 0.
        }
        SET tg["ohalrt"] TO (tg["eow"] < tg["emoh"] AND tg["strt_avail"] AND g["psha"] > TG_PSOHAL AND g["rpred"] > TG_RMOH).
        IF tg["ohalrt"] {
            SET tg["ohalrt_cyc"] TO tg["ohalrt_cyc"] + 1.
            SET tg["ohalrt_run"] TO tg["ohalrt_run"] + 1.
        } ELSE {
            SET tg["ohalrt_run"] TO 0.
        }
        taemg_dm_act(tg, st, g).
        IF g["rcir"] < TG_P2TRNC1 * g["rturn"] {
            SET tg["iphase"] TO TG_IPH_HDG.
            SET tg["itran"] TO TRUE.
            SET tg["philim"] TO TG_PHILM2.
        }
        RETURN.
    }
}

// ---------------------------------------------------------------- TGNZC: the normal-acceleration command
FUNCTION taemg_zoom_active {                // whether the zoom is active -> LIST(active, why)
    PARAMETER tg, st, nz_cmd.
    IF NOT tg:HASKEY("g") { RETURN LIST(FALSE, "no geometry"). }
    IF tg["iphase"] = TG_IPH_STURN { RETURN LIST(FALSE, "s-turn"). }   // no ZOOM in the S-turn (it bleeds energy; a zoom spends it)
    LOCAL g IS tg["g"].
    LOCAL zoom_on IS FALSE.
    IF tg:HASKEY("zoom") { SET zoom_on TO tg["zoom"] <> 0. }
    LOCAL mach_min IS CHOOSE TG_ZOOM_MACH_MIN IF zoom_on ELSE TG_ZOOM_MACH_MIN + TG_ZOOM_MACH_BAND.
    IF st["mach"] <= mach_min {
        RETURN LIST(FALSE, "mach").
    }
    IF tg["eow"] - tg["en"] <= TG_ZOOM_ENERGY_M { RETURN LIST(FALSE, "energy"). }
    LOCAL phi IS MAX(taemg_philim_cap(tg, st), 1e-3).
    LOCAL r_level IS st["surfv"] ^ 2 / (TG_GO * TAN(phi)).
    LOCAL r_need IS taemg_rturn_of(g["psha"], tg["rf"], tg["r2"]).
    LOCAL r_have IS r_level.                // CSS_PILOT_MODEL's lift radius is simulation-only: not implemented
    IF r_have < TG_ZOOM_TURN_RATIO * r_need { RETURN LIST(FALSE, "turn ok"). }
    LOCAL qmin IS CHOOSE TG_ZOOM_QBAR_MIN IF zoom_on ELSE TG_ZOOM_QBAR_MIN + TG_ZOOM_QBAR_BAND.
    IF st["qbar"] < qmin { RETURN LIST(FALSE, "qbar"). }
    IF ABS(g["dpsac"]) < TG_ZOOM_DPSAC_GATE { RETURN LIST(FALSE, "dpsac"). }   // a turn still to make (ZOOM_DPSAC_GATE)
    RETURN LIST(TRUE, "").
}

FUNCTION taemg_nzc {                        // the Nz command, through the energy, qbar, zoom, rate and command limits
    PARAMETER tg, st.
    LOCAL gdh IS taemg_midval(TG_GDHUL - (TG_GDHUL - TG_GDHLL) * MIN(st["h"] / MAX(TG_GDH_H_REF, 1.0), 1.0), TG_GDHLL, TG_GDHUL).
    LOCAL hderr IS tg["hdref"] - st["hdot"].
    LOCAL hderrc IS hderr + gdh * TG_HDREQG * tg["herror"].
    LOCAL nz IS hderrc * gdh * TG_DNZCG.
    LOCAL nz_before IS nz.
    LOCAL enlo IS 0.
    LOCAL enhi IS 0.
    IF tg["iphase"] <= TG_IPH_HDG {
        SET enlo TO TG_GE_LL * (tg["emin"] - tg["eow"]).
        SET enhi TO TG_GE_UL * (tg["emax"] - tg["eow"]).
        // the sink rate past the deadband (the offline sim's EN_HD_DB), one-sided (the port's eownzul / eownzll form)
        SET enhi TO enhi + gdh * TG_DNZCG * MAX(hderr - TG_EN_HD_DB, 0.0).
        IF TG_EN_HD_FLOOR {                 // the floor side (the offline sim's EN_HD_FLOOR), off
            SET enlo TO enlo + gdh * TG_DNZCG * MIN(hderr + TG_EN_HD_DB, 0.0).
        }
        IF enlo > enhi {
            SET tg["en_xed"] TO 1.
            SET nz TO MAX(nz, enlo).
        } ELSE {
            SET tg["en_xed"] TO 0.
            SET nz TO taemg_midval(nz, enlo, enhi).
        }
    } ELSE {
        SET tg["en_xed"] TO 0.
    }
    IF tg["iphase"] > TG_IPH_HDG { SET tg["bind_en"] TO 0. }
    ELSE IF tg["en_xed"] <> 0 { SET tg["bind_en"] TO CHOOSE -1 IF nz_before < enlo ELSE 0. }
    ELSE { SET tg["bind_en"] TO taemg_bind_of(nz_before, enlo, enhi). }
    LOCAL qb_nz IS TG_GQB * (tg["qbarf"] - tg["qbref"]) + TG_GQBD * tg["qbd"].     // + G4.9's rate term
    SET nz_before TO nz.
    SET nz TO taemg_midval(nz, qb_nz - TG_NZ_QB_BAND, qb_nz + TG_NZ_QB_BAND).
    SET tg["bind_qb"] TO taemg_bind_of(nz_before, qb_nz - TG_NZ_QB_BAND, qb_nz + TG_NZ_QB_BAND).
    SET nz_before TO nz.
    LOCAL za IS taemg_zoom_active(tg, st, nz).
    SET tg["zoom"] TO CHOOSE 1 IF za[0] ELSE 0.
    SET tg["zoom_why"] TO za[1].
    IF za[0] {
        LOCAL frac IS 1.0.
        IF TG_ZOOM_TAPER_M > 0.0 { SET frac TO taemg_midval((tg["eowerror"] - TG_ZOOM_ENERGY_M) / TG_ZOOM_TAPER_M, 0.0, 1.0). }
        SET nz TO MAX(nz, nz + frac * (TG_ZOOM_NZ - nz)).
        SET tg["zoom_frac"] TO frac.
    } ELSE {
        SET tg["zoom_frac"] TO 0.0.
    }
    SET tg["bind_zoom"] TO CHOOSE -1 IF nz > nz_before ELSE 0.
    LOCAL dnzcd_raw IS (nz - tg["nzc"]) * TG_CQG.
    LOCAL dnzcd IS taemg_midval(dnzcd_raw, -TG_DNZCDL, TG_DNZCDL).
    SET tg["bind_rate"] TO taemg_bind_of(dnzcd_raw, -TG_DNZCDL, TG_DNZCDL).
    LOCAL nzc_raw IS tg["nzc"] + dnzcd * TG_DTG.
    SET tg["nzc"] TO taemg_midval(nzc_raw, -TG_NZ_CMD_LIM, TG_NZ_CMD_LIM).
    SET tg["bind_cmd"] TO taemg_bind_of(nzc_raw, -TG_NZ_CMD_LIM, TG_NZ_CMD_LIM).
    SET tg["gdh"] TO gdh.
    RETURN tg["nzc"].
}

// ---------------------------------------------------------------- TGSBC: the speedbrake command
FUNCTION taemg_sbc {
    PARAMETER tg, st.
    LOCAL dsbcll IS taemg_midval(TG_DSBSUP + TG_DSBLLS * (st["mach"] - TG_DSBCM), 0.0, TG_DSBSUP).
    LOCAL dsbcul IS MAX(TG_DSBSUP, tgDsbMax).   // the upper limit: tgDsbMax is TG_DSBMAX, or lib_land's ldSbCap in flight
    LOCAL blend IS 0.0.
    LOCAL dsbc IS 0.0.
    IF st["mach"] > TG_DSBCM {
        SET dsbc TO TG_DSBSUP.
    } ELSE IF tg["iphase"] = TG_IPH_STURN {
        SET dsbc TO TG_DSBLIM.
    } ELSE {
        LOCAL dsbe IS TG_GSBE * tg["qberr"].
        IF TG_SB_BLEND_ON { SET blend TO taemg_midval(TG_HGAINSB * (st["h"] - TG_HBLEND), 0.0, 1.0). }
        LOCAL accd IS 0.0.
        IF st:HASKEY("acc_drag") { SET accd TO st["acc_drag"]. }
        LOCAL edteri IS st["surfv"] * (taemg_en_slope(tg["drpred"]) - accd / TG_GO).
        IF NOT tg:HASKEY("edtero") { SET tg["edtero"] TO edteri. }
        SET tg["edtero"] TO (1.0 - TG_EDSMGAN) * tg["edtero"] + TG_EDSMGAN * edteri.
        LOCAL e_leg IS TG_EOWSBG * (tg["eow"] - tg["en"]) + TG_EDOTSBG * tg["edtero"].
        LOCAL raw IS 0.
        IF blend > 0.0 { SET raw TO TG_DSBNOM + blend * e_leg - (1.0 - blend) * (dsbe + tg["dsbi"]). }
        ELSE { SET raw TO TG_DSBNOM - dsbe - tg["dsbi"]. }
        IF (raw > dsbcll) AND (raw < dsbcul) {
            SET tg["dsbi"] TO taemg_midval(tg["dsbi"] + TG_GSBI * tg["qberr"] * TG_DTG, -TG_DSBIL, TG_DSBIL).
        }
        IF blend > 0.0 { SET dsbc TO (TG_DSBNOM + blend * e_leg - (1.0 - blend) * (dsbe + tg["dsbi"])). }
        ELSE { SET dsbc TO TG_DSBNOM - dsbe - tg["dsbi"]. }
    }
    SET tg["sb_blend"] TO blend.
    LOCAL step_lim IS TG_DSBDTG * TG_DTG.
    SET dsbc TO tg["dsbc"] + taemg_midval(dsbc - tg["dsbc"], -step_lim, step_lim).
    SET tg["dsbc"] TO taemg_midval(dsbc, dsbcll, dsbcul).
    RETURN tg["dsbc"].
}

// ---------------------------------------------------------------- TGPHIC: the bank command
FUNCTION taemg_phic {
    PARAMETER tg, st, g.
    LOCAL philimit IS taemg_philim_cap(tg, st).
    SET tg["philim_mach"] TO philimit.
    LOCAL phi0 IS tg["phic"].
    SET tg["hac_fallback"] TO FALSE.
    SET tg["rerrc"] TO g["rcir"] - g["rturn"].
    SET tg["rerrc_valid"] TO (tg["iphase"] = TG_IPH_HDG).
    IF tg["iphase"] = TG_IPH_STURN {
        SET tg["phic"] TO tg["ysturn"] * philimit.
    } ELSE IF tg["iphase"] = TG_IPH_ACQ {
        SET tg["phic"] TO TG_GPHI * g["dpsac"].
    } ELSE IF tg["iphase"] = TG_IPH_HDG {
        LOCAL rerrc IS tg["rerrc"].
        IF rerrc > TG_RERRLM {
            SET tg["hac_fallback"] TO TRUE.
            SET philimit TO MIN(philimit, TG_PHILM1).
            SET tg["phic"] TO TG_GPHI * g["dpsac"].
        } ELSE {
            LOCAL rdot IS -(g["xcir"] * st["xdot"] + g["ycir"] * st["ydot"]) / g["rcir"].
            LOCAL phip2c IS ((st["vh"] ^ 2 - rdot ^ 2) * TG_RTD / (TG_GO * MAX(g["rturn"], 1.0))).
            SET phip2c TO phip2c * (TG_PHI2C1 - TG_PHI2C2 * phip2c).
            LOCAL rdotrf IS (-st["vh"] * (TG_R1 + 2.0 * tg["r2"] * g["psha"]) * TG_RTD / MAX(g["rturn"], 1.0)).
            SET tg["phic"] TO tg["ysgn"] * MAX(phip2c + TG_GR * rerrc + TG_GRDOT * (rdot - rdotrf), 0.0).
        }
    } ELSE IF tg["iphase"] = TG_IPH_PREFINAL {
        LOCAL yerrc IS -TG_GY * taemg_midval(st["y"], -TG_YERRLM, TG_YERRLM).
        SET tg["phic"] TO yerrc - TG_GYDOT * st["ydot"].
        IF tg["isr"] > 0 {
            SET tg["phic"] TO phi0 + (tg["phic"] - phi0) / tg["isr"].
            SET tg["isr"] TO tg["isr"] - 1.
        }
        SET tg["philim"] TO taemg_midval(TG_PHILM3, TG_PHILM4, TG_PHILR1 * ABS(tg["phic"]) + TG_PHILR2).
    }
    LOCAL arg IS st["costh"] / MAX(TG_NZ_ROLL_MAX - tg["nzc"], 1e-3).
    SET tg["nz_roll_clamped"] TO CHOOSE 1 IF ABS(arg) > 1.0 ELSE 0.
    LOCAL phinzlim IS ARCCOS(MAX(-1.0, MIN(1.0, arg))).
    SET philimit TO MIN(philimit, phinzlim).
    SET tg["philimit"] TO philimit.
    SET tg["phic_at"] TO taemg_midval(tg["phic"], -philimit, philimit).
    IF tg["iphase"] = TG_IPH_STURN AND TG_STN_NZ_SCHED {     // the S-turn as a brake: the bank that holds
        LOCAL vz IS st["costh"] + tg["nzc"] * COS(philimit).  //   the normal law's vertical lift at the scheduled load
        LOCAL c IS MAX(MIN(vz / taemg_stn_nz(tg), 1.0), COS(TG_STN_PHI_MAX)).
        SET tg["phic_at"] TO tg["ysturn"] * ARCCOS(c).
    }
    RETURN tg["phic_at"].
}

FUNCTION taemg_stn_nz {                     // the S-turn's total load, g: 1 at EST, TG_STN_NZ_MAX at TG_STN_NZ_DE above
    PARAMETER tg.
    RETURN 1.0 + (TG_STN_NZ_MAX - 1.0) * taemg_midval((tg["eow"] - tg["est"]) / TG_STN_NZ_DE, 0.0, 1.0).
}

FUNCTION taemg_bank_to_ship {               // G4.9's sign: + = a RIGHT turn, toward +y
    PARAMETER phic_at.                      //   -> the ship's bank (+ = LEFT: entrySteer's
    RETURN -phic_at.                        //   ANGLEAXIS about the velocity; css_dap: + = LEFT)
}

FUNCTION taemg_ship_to_bank {               // the inverse of taemg_bank_to_ship
    PARAMETER bank.
    RETURN -bank.
}

FUNCTION taemg_nz_total {                   // what the pitch loop flies: tg["nz_total"]
    PARAMETER tg, st.
    LOCAL cosphi IS MAX(MAX(COS(tg["phic_at"]), 0.20), COS(tg["philimit"])).     // no hold beyond the limit
    LOCAL nz_total IS taemg_midval(st["costh"] / cosphi + tg["nzc"], -TG_NZ_TOTAL_LIM, TG_NZ_TOTAL_LIM).
    IF tg["iphase"] = TG_IPH_STURN AND TG_STN_NZ_SCHED {     // the S-turn's scheduled load (taemg_phic's bank)
        SET nz_total TO taemg_midval(taemg_stn_nz(tg), -TG_NZ_TOTAL_LIM, TG_NZ_TOTAL_LIM).
    }
    SET tg["nz_total"] TO nz_total.
    RETURN nz_total.
}

FUNCTION taemg_bank_slew {                  // slews the bank -> LIST(slewed bank, rate)
    PARAMETER cur, tgt, rate, dt, rate_lim, accel_lim.
    LOCAL err IS tgt - cur.
    LOCAL want IS err / MAX(dt, 0.001).
    SET want TO MAX(-rate_lim, MIN(rate_lim, want)).
    LOCAL vmax IS SQRT(2.0 * accel_lim * ABS(err)).
    SET want TO MAX(-vmax, MIN(vmax, want)).
    SET want TO MAX(rate - accel_lim * dt, MIN(rate + accel_lim * dt, want)).
    RETURN LIST(cur + want * dt, want).
}

// The guidance stays within CSS's rate limits (TG_CSS_RATE_LIMITS): the AUTO DAP and the guidance obey the same
// limits as CSS. Below: the stick's full-deflection rates by Mach, from the generated TG_CSS_*; lib_dap's CSS gearing
// flies the same numbers.
FUNCTION taemg_css_lin {                    // linear in Mach: sch = LIST(Mach lo, at lo, Mach hi, at hi)
    PARAMETER x, sch.
    IF x <= sch[0] { RETURN sch[1]. }
    IF x >= sch[2] { RETURN sch[3]. }
    RETURN sch[1] + (sch[3] - sch[1]) * (x - sch[0]) / (sch[2] - sch[0]).
}
FUNCTION taemg_css_pitch {                  // pitch rate at full stick, deg/s
    PARAMETER mach.
    LOCAL x IS TG_CSS_RHC_FULL - TG_CSS_P_DB.
    RETURN MIN(TG_CSS_DEMAX, (TG_CSS_KDEMLIN + TG_CSS_PKQ * x) * x) * taemg_css_lin(mach, TG_CSS_P_GAIN).
}
FUNCTION taemg_css_roll {                   // roll rate at full stick, deg/s
    PARAMETER mach.
    LOCAL x IS TG_CSS_RHC_FULL - TG_CSS_R_DB.
    LOCAL shp IS MIN(taemg_css_lin(mach, TG_CSS_R_DMAX),
                     (taemg_css_lin(mach, TG_CSS_R_KL) + taemg_css_lin(mach, TG_CSS_R_KP) * x) * x).
    RETURN shp * taemg_css_lin(mach, TG_CSS_R_GAIN).
}
FUNCTION taemg_roll_lim {                   // the roll limits -> LIST(rate deg/s, accel deg/s2)
    PARAMETER mach.
    IF NOT TG_CSS_RATE_LIMITS { RETURN LIST(TG_ROLL_RATE, TG_ROLL_ACCEL). }
    LOCAL rt IS MIN(TG_ROLL_RATE, taemg_css_roll(mach)).
    RETURN LIST(rt, TG_ROLL_ACCEL * rt / TG_ROLL_RATE).
}
FUNCTION taemg_alpha_rate {                 // the alpha command's rate limit, deg/s
    PARAMETER mach.
    IF NOT TG_CSS_RATE_LIMITS { RETURN TG_NZL_ALPHA_RATE. }
    RETURN MIN(TG_NZL_ALPHA_RATE, taemg_css_pitch(mach)).
}

// ---------------------------------------------------------------- one guidance pass
FUNCTION taemg_cycle {                      // one guidance pass -> LIST(phic_at, dsbc, g)
    PARAMETER tg, st.
    LOCAL g IS taemg_gtp(st, tg["ysgn"], tg["iphase"], tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"], tg["first"]).
    SET tg["psha_prev"] TO g["psha"].
    SET tg["g"] TO g.
    taemg_comp(tg, st, g).
    taemg_tran(tg, st, g).
    taemg_nzc(tg, st).
    taemg_sbc(tg, st).
    LOCAL phic_prev IS tg["phic_at"].
    taemg_phic(tg, st, g).
    SET tg["phic_dem"] TO tg["phic_at"].
    IF TG_ROLL_SLEW {
        LOCAL rlm IS taemg_roll_lim(st["mach"]).      // CSS's roll rate at this Mach (TG_CSS_RATE_LIMITS)
        LOCAL sl IS taemg_bank_slew(phic_prev, tg["phic_dem"], tg["phic_rate"], TG_DTG, rlm[0], rlm[1]).
        SET tg["phic_at"] TO sl[0].
        SET tg["phic_rate"] TO sl[1].
    } ELSE {
        SET tg["phic_rate"] TO (tg["phic_at"] - phic_prev) / TG_DTG.
    }
    taemg_nz_total(tg, st).
    RETURN LIST(tg["phic_at"], tg["dsbc"], g).
}
