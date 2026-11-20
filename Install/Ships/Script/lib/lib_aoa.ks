// ============================================================================================================
//  lib_aoa.ks  --  THE ABORT ONCE AROUND (AOA): PRESS TO ORBIT OR COME BACK, AND THE AOA'S OMS-2
// ============================================================================================================
//  One ATO abort button; the choice to press to orbit or come back is a window, in the displays' look, after OMS-1.
//  The run path: ops1q (an engine fails, abort ATO, plans OMS-1) -> shuttle_exec (flies OMS-1, asks AOA / ATO, plans
//  the AOA's OMS-2; ops1q plans it when OMS-1 is skipped) -> shuttle_exec again (flies OMS-2) -> fam_build -> ops3q,
//  which knows it flies an AOA: the pre-entry bank AOA_PRE_BANK (the plan inside 90 % of its crossrange) and, when
//  the plan needs it, the alpha ramp. The interface angle is shallower than the planner's nominal (AOA_FAC).
//  THE CALLS: shuttle_exec after flying a plan tagged "ATO OMS-1", and ops1q when OMS-1 is skipped:
//    aoaAsk(info) -> "ATO" (PRESS TO ORBIT) | "AOA" (COME BACK): the window in lib_guistyle's look, blocking until
//        CONFIRM. info = LEXICON("dv_ato", the ATO's OMS-2 m/s, "dv_keep", the deorbit's reserve m/s, "dv_oms", the OMS
//        on board m/s; optional: "dv_onorb" the on-orbit allowance, "dv_emerg" the emergency margin in dv_keep m/s:
//        the ATO STATUS line). The AOA's own numbers come from a dry run of the plan below, kept for aoaPlanOms2.
//    aoaPlanOms2() -> TRUE (written) | FALSE (no plan; the terminal says why). From the ship's actual orbit: the AOA's
//        OMS-2 into 0:/oms2_plan.txt through lib_oms_plan's omsPlanWrite (tagged "AOA OMS-2") + the runway, the aim, the
//        interface angle and ops3q's fallback bank, and the flag 1:/abort_mode.txt "AOA SLF" ("AOA SLF RAMP" when the
//        plan needs the 30 deg alpha ramp; fam_build and ops3q read it: the plan file, EPR_PREENTRY_BANK AOA_PRE_BANK,
//        EPR_AOA_RAMP_ON for RAMP; "AOA VBG" from Vandenberg, aoaSolveNow plans to the launch site).
//  Needs lib_guistyle.ks (aoaAsk) and lib_oms_plan.ks (omsPlanWrite, omsDvOnBoard) loaded by the caller (both callers
//  load them). entry_predict.ks is loaded INSIDE aoaSolveNow, not here: ops1q loads this file at its start, and an
//  entry_predict.ks run from there would hold its globals from the launch on into a later RUNPATH ops6q (whose
//  RUNONCEPATH of it then runs nothing: in kOS the first definition wins).
//  THE PLAN (aoaSolve; an offline python twin takes the same steps): the offline AOA solver with the entry family
//  replaced by a fitted reach. OMS-2 = an in-plane impulse dvt (> 0 prograde) at t_ig. For each t_ig on a grid every
//  AOA_DT s from AOA_T_LEAD after the solve to AOA_T_HI_PAD before the orbit's own interface (the coast's ephemeris:
//  aoaStep, J2 on Sol), dvt is bisected (-400..+400 m/s, 16 steps) for the surface-relative interface angle AOA_FAC x
//  the deorbit planner's nominal at the orbit's apoapsis (Kepler's closed form, as deorbit_plan's dv-for-angle
//  search); the interface itself is coasted (eprKepToEI: J2 on Sol, as the deorbit planner's geometry: at a 1.1 deg
//  entry a 1 km height error moves the crossing ~50 km). f = the distance from the interface point to the aim (the FTP
//  AOA_FTP_M short of the site's centre on the great circle from the interface point: ops6q's TAL aim, python's
//  tal.aim_for) minus the middle of the entry family's reach at the pre-entry bank (aoaDmid, fitted on python's
//  families at inclinations 36-90 deg; no candidate whose predicted skim is longer than AOA_ARC_MAX: off the skip
//  edge). Every sign change of f is bisected 11 times; among the ends with |f| < AOA_F_TOL, the crossrange inside its
//  gate (aoaEval's xo <= AOA_XT_MAX: the aim's cross-track in the frame the entry arrives in) and |dvt| <= the OMS on
//  board - AOA_OMS_RESERVE, the least |dvt| wins. None: the grid point nearest the middle with |f| <= AOA_F_OFF and the
//  same limits (the aim ~30-70 % into the reach). Neither: the angle steeper by AOA_FPA_STEP, up to AOA_FPA_KMAX times
//  (steeper only). Still none, and a candidate lost to the crossrange alone (AOA_XT_ONLY): the same ladder again with
//  the 30 deg alpha ramp, its longer reach and its wider gate (the ramp for high crossrange only); its plan's flag then
//  says RAMP. Still none, and the executor flies a radial part (OMS_PLAN_DVR): THE RADIAL FALLBACK (AOA_DVR_STEP).
//  DEVIATIONS FROM THE ORBITER: the orbiter's AOA OMS-2 was PEG 4 to pre-mission targets (the steep or the shallow
//  AOA, by the OMS propellant left) for a site chosen before flight; this one is solved on board after OMS-1, at
//  AOA_FAC x the planner's nominal angle (shallower than the nominal), to KSC first (the orbiter's AOA sites were
//  Edwards, White Sands and KSC). The window replaces the flight rules' ATO / AOA call. The orbiter's OMS-2 had the
//  radial part PEG 4 gave it; this one is prograde only, radial only when that finds none.
//  THE SOLVE IN C#: aoaSolve hands the solve to the KAL/S coprocessor (ADDONS:KALS:AOASOLVE, coproc/Aoa.cs: aoaSolveKos
//  and the entry_predict.ks functions it calls, line for line, the ignition grid, its brackets' bisections and the
//  radial fallback's ignitions on worker threads) when AOA_CS (TRUE), and solves in kOS (aoaSolveKos) on ANY failure:
//  no addon, an older dll without AOASOLVE, a bad input, an error on its thread, no result in AOA_CS_TMAX s, a radial
//  plan too soon after the solve's end. AOA_CS_SAY says which ran; only the kOS fallback's line (why the C# failed) is printed.
// ============================================================================================================
@LAZYGLOBAL OFF.

GLOBAL AOA_FAC IS 0.75.                    // the interface angle, x the planner's nominal
GLOBAL AOA_FPA_SLOPE IS -0.000009445687.   // deg per m of the apoapsis  \
GLOBAL AOA_FPA_ICPT IS 0.6554.             // deg                          > the nominal = deorbit_plan.ks dpFpaForOrbit
GLOBAL AOA_FPA_MARGIN IS 0.75.             // deg                         /  (DP_FPA_*; sync_check pairs those, not these)
GLOBAL AOA_FPA_STEP IS 0.05.               // deg: the fallback's step, steeper
GLOBAL AOA_FPA_KMAX IS 8.                  // the fallback's steps (0.4 deg in all)
GLOBAL AOA_FPA_TOL IS 0.01.               // deg: the coasted angle's miss corrected once above this (aoaBurnEI)
GLOBAL AOA_PRE_BANK IS 90.                 // deg: the pre-entry bank (the reach is fitted at it; fam_build + ops3q fly it)
GLOBAL AOA_FB_BANK IS 45.                  // deg: the plan's "bank" = ops3q's fallback hold only (its NOMINAL_BANK): no
                                           //   constant bank was solved for, the family guides
GLOBAL AOA_XT_MAX IS LIST(359000, 515000). // m: the crossrange gate, nominal: 90 % of the footprint's
                                           //   nearest edge in aoaEval's frame over 36 runs at inc 36-90; ramp:
                                           //   90 % of the Mach 12 ramp's nearest edge over 23 runs (572 km); set
                                           //   per site from AOA_XT_RAMP_SITE by aoaSolveNow
GLOBAL AOA_XT_RAMP_SITE IS LEXICON("SLF", 515000, "VBG", 610000).   // m: the ramp gate per site (VBG's own footprint
                                           //   edges are 587-609 km, so all five VBG inclinations plan on the
                                           //   first revolution; KSC's reach only 572-584)
GLOBAL AOA_OMS_RESERVE IS 50.              // m/s left in the OMS after OMS-2 (the emergency margin,
                                           //   = lib_ascent_iload's ASC_OMS_EMERG)
GLOBAL AOA_T_LEAD IS 300.                  // s: OMS-2's centre at least this long after the solve (shuttle_exec's lead + the crew's RUN)
GLOBAL AOA_T_REUSE IS 200.                 // s: aoaPlanOms2 keeps aoaAsk's dry run while its burn is at least this far ahead
GLOBAL AOA_DT IS 30.                       // s: the ignition grid and the coast's RK4 step (eprKepToEI's J2 coast)
GLOBAL AOA_T_HI_PAD IS 60.                 // s: the last ignition this long before the orbit's own interface
GLOBAL AOA_T_MAX IS 3000.                  // s: the grid's end when the orbit has no interface
GLOBAL AOA_F_TOL IS 25000.                 // m: |f| accepted at a bracket's end
GLOBAL AOA_F_OFF IS 300000.                // m: |f| taken off the middle when no bracket centres the aim (~30-70 % in)
// THE RADIAL FALLBACK: when both ladders found nothing, OMS-2 = dvt along the prograde + dvr along the radial (+ out:
// in the plane, perpendicular to the prograde = KSP's node RADIALOUT), at the angle gam0 only. Per ignition: the point
// at dvr 0, the probe AOA_DVR_STEP toward the aim (radial in when the aim lies short of the reach's middle), then the
// secant on f(dvr), at most AOA_DVR_ITERS steps, |dvr| <= AOA_DVR_MAX, stopping below AOA_DVR_FTOL; the ladders' gates,
// the least |dv|; the nominal reach, then the ramp's when the nominal's gate alone turned candidates away. Only when
// the executor flies a radial part (OMS_PLAN_DVR, lib_oms_plan). In the offline model a case with no prograde-only AOA
// plans KSC by the ramp with dvt -21.1 + dvr -23.5 = 31.6 m/s, crossrange 444 of 465 km, flown 2.6-6.3 km from the
// aim (the radial part pulls it 26-48 km in).
// Its ignitions start AOA_T_LEAD after the solve's END (aoaSpent, AOA_T0_SOLVE), not its start: it runs after both
// ladders failed, which takes minutes of game time (in kOS's VM at IPU 10000: 158 s, then 43 s for the fallback), and
// the earliest root (+360 s) would reach the window ~160 s ahead, under AOA_T_REUSE and inside shuttle_exec's 300 s
// align lead (that case's plan is then ~+510 s, 46.4 m/s: DVX -18.4, DVZ +42.6).
GLOBAL AOA_DVR_STEP IS 20.                 // m/s: the probe
GLOBAL AOA_DVR_ITERS IS 4.                 // the secant's steps after the probe
GLOBAL AOA_DVR_MAX IS 200.                 // m/s: the secant's clamp
GLOBAL AOA_DVR_FTOL IS 1000.               // m: the secant stops below this |f|
GLOBAL AOA_T0_SOLVE IS -1.                 // s (UT): aoaSolveNow's epoch while it solves (aoaSpent); -1 = not timed (the tests)
                                           //   (exactly -1: a test's epoch may be negative, as kosrun's clock sits near 0)
// THE AIM: 52 km = ops6q TAL_AIM_KM, closer than FTP_BACK_KM's 59,856.64 m: in the offline model from a flown
// interface (drag x 1.0 / 1.1 / 0.9) TAEM's start energy at SLF33 goes from +0.2..+0.6 km to +2.7..+4.9 km.
GLOBAL AOA_FTP_M IS 52000.                 // m: the aim this far short of the site (ops6q TAL_AIM_KM, tal.aim_for)
RUNONCEPATH("0:/lib/lib_cape.ks").          // the SLF where the Katniss Cape is (capeSlfMid)
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
GLOBAL AOA_SITES IS LEXICON(               // the site's centre (lat, lng: ops6q's SLF), its runway end, the other end
    "SLF", LIST(capeSlfMid()[0], capeSlfMid()[1], "SLF33", "SLF15"),   // the moved or the published Cape
    "VBG", LIST(34.736902, -120.5842495, "VBG32", "VBG14")).   // Vandenberg (ops6q's TAL_SITES "VBG": the KK
                                           //   runway's midpoint, VBG32 its prime end)
GLOBAL AOA_SITE IS "SLF".                  // KSC first
// THE REACH SURROGATE: the skim km = exp(c . [1, x, x^2, x^3, y, x y, x^2 y,
// y^2, z, x z, y z]) and the middle of the entry family's reach from the interface point, km = the skim + d . [1, x,
// y, x^2, z, x z, y z]; x = h_pJ2 - AOA_SUR_HP0, y = (h_a - AOA_SUR_HA0) / AOA_SUR_HAS, z = (v_rel - AOA_SUR_V0) /
// AOA_SUR_VS. h_pJ2 (km) = the lowest height of the interface state's vacuum coast under J2 (aoaHpJ2; J2 puts it
// -1.3 .. +1.8 km off the osculating perigee by latitude), h_a (km) = its osculating apogee, v_rel (m/s) = its speed
// over the air (the inclination's term: at 60 deg the same orbit meets the air ~90 m/s faster and reaches ~550 km
// further). Fitted on python's families at AOA_PRE_BANK on the drag-fixed model (the offline fit:
// the planner's own candidates from its decision states turned to inc 36.3 / 50 / 60 / 75 / 90 + a sweep, 2175
// points, rms 34 km); used only inside its fitted box AOA_SUR_BOX (h_pJ2 lo, hi km, h_a lo, hi km, v_rel lo, hi m/s)
// and for a skim no longer than AOA_ARC_MAX km (near the skip edge the reach climbs 250-900 km per km of h_pJ2).
GLOBAL AOA_SUR_C IS LIST(7.832423089822044, 0.13048469225469045, 0.009593678967589359, 0.00038177538013178065,
                         0.04721762539251752, 0.020710781431486094, 0.0009824444652965444, 0.005420531530404805,
                         0.013951221948457325, 0.0012055374793049447, -0.0024952256792196365).
GLOBAL AOA_SUR_D IS LIST(1322.5957900046599, -95.34429705543357, 14.689524252286642, -4.936765284526315,
                         -38.637621061459384, -9.1045524417129, 3.8254251822480407).
GLOBAL AOA_SUR_HP0 IS 71.
GLOBAL AOA_SUR_HA0 IS 130.
GLOBAL AOA_SUR_HAS IS 10.
GLOBAL AOA_SUR_V0 IS 3700.
GLOBAL AOA_SUR_VS IS 50.
GLOBAL AOA_SUR_BOX IS LIST(62, 69, 84, 200, 3656, 3960).   // v_rel to 3960 for VBG at 98-104 deg
                                           //   (3926 / 3951; the surrogate there +45 / +55 km, the in-box trend)
GLOBAL AOA_ARC_MAX IS 2200.                // km: the skim guard (the reach's slope there ~230-300 km per km)
GLOBAL AOA_HPJ2_KMAX IS 100.               // aoaHpJ2's steps at most (python's 3000 s)
// THE CROSSRANGE IN THE FRAME THE ENTRY ARRIVES IN (fitted on 36 runs at inc 36-90): the Earth turns under
// the entry for ~T s from the interface to TAEM, so the footprint is centred on the interface's INERTIAL plane traced
// over the Earth at the interface's time + T, T = AOA_XT_T0 + AOA_XT_T1 (d - 3500) s (d = the reach's middle, km; rms
// 11-12 s). aoaEval measures the aim's cross-track (+ right) there (xa) and on the interface's ground track (xp),
// blends them xm = (1 - AOA_XT_EPS) xa + AOA_XT_EPS xp and gates xo = |xm - AOA_XT_C| <= AOA_XT_MAX. Each a LIST(the
// nominal, the ramp). The ramp's: fitted on 23 runs flown with the Mach 12 ramp, aimed on the short side.
GLOBAL AOA_XT_T0 IS LIST(1172.4, 1160.3).  // s
GLOBAL AOA_XT_T1 IS LIST(0.24, 0.2705).    // s per km
GLOBAL AOA_XT_EPS IS LIST(0.110, 0.069).
GLOBAL AOA_XT_C IS LIST(18900, 20400).     // m
// The 30 deg alpha ramp's aim (the Mach 12 ramp, 3750 -> 3450 m/s, and the line from 2000 m/s), on the short side:
// the guidance family flies the most crossrange with the site 73 % of the way from its long end to its short end, so
// the ramp aims d = short + 0.27 (long - short), = the surrogate's middle + AOA_RAMP_G0 + AOA_RAMP_G1 z + AOA_RAMP_G2 x
// km (z, x as aoaDmid; rms 16 km, leave-one-out 20 km over 18 states; v_rel alone left 42).
GLOBAL AOA_RAMP_G0 IS 140.1.
GLOBAL AOA_RAMP_G1 IS -34.18.
GLOBAL AOA_RAMP_G2 IS 20.05.
GLOBAL AOA_PLAN_FILE IS "0:/oms2_plan.txt".   // the OMS-2 plan
GLOBAL AOA_FLAG_FILE IS "1:/abort_mode.txt".  // the AOA's flag (ops1q deletes it at liftoff)
GLOBAL AOA_LOG_FILE IS "0:/logs/aoa_plan.txt".
GLOBAL AOA_SOL IS 0.                       // the last solve (aoaSolveNow): a LEXICON, or 0
GLOBAL AOA_WHY IS "".                      // why the last solve found nothing
GLOBAL AOA_XT_ONLY IS 0.                   // candidates the last solve lost to the crossrange gate alone (aoaSolveIg)
GLOBAL AOA_PROG_ON IS FALSE.               // TRUE while aoaAsk's progress label (AOA_PROG) is up
GLOBAL AOA_PROG IS 0.
// THE SOLVE IN C# (see the header)
GLOBAL AOA_CS IS TRUE.                     // the solve in the KAL/S addon (kOS's own on any failure)
GLOBAL AOA_CS_THREADS IS 0.                // the C#'s threads (0: the addon's choice, MIN(4, CPUs - 1))
GLOBAL AOA_CS_TMAX IS 30.                  // s: no C# result by then: kOS solves
GLOBAL AOA_CS_SPENT_PAD IS 1.              // s: the C#'s solve ends this soon after its start (the radial grid's start: aoaSpent)
GLOBAL AOA_CS_SAY IS "".                   // which solve ran last: "AOA SOLVE IN C#: .." / "AOA SOLVE: KOS (why)"

// The deorbit planner's nominal interface angle (deg) for an orbit at altM (deorbit_plan.ks dpFpaForOrbit).
FUNCTION aoaFpaNom {
    PARAMETER altM.
    RETURN AOA_FPA_SLOPE * altM + AOA_FPA_ICPT - AOA_FPA_MARGIN.
}

// The osculating vacuum orbit of (rv, vv): LIST(the perigee radius, the apogee radius) m; 0 when not elliptic.
FUNCTION aoaPeriApo {
    PARAMETER rv, vv.
    LOCAL a IS 1 / (2 / rv:MAG - vv:SQRMAGNITUDE / EPR_MU).
    IF a <= 0 { RETURN 0. }
    LOCAL hh IS VCRS(rv, vv):SQRMAGNITUDE.
    LOCAL ecc IS SQRT(MAX(0, 1 - hh / (EPR_MU * a))).
    RETURN LIST(a * (1 - ecc), a * (1 + ecc)).
}

// The surface-relative flight-path angle (deg, < 0 descending) of a state (deorbit_plan.ks dpFpa).
FUNCTION aoaFpaAt {
    PARAMETER rv, vv.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL vvert IS VDOT(vrelv, rv:NORMALIZED).
    RETURN ARCTAN2(vvert, SQRT(MAX(vrelv:SQRMAGNITUDE - vvert * vvert, 0))).
}

// The interface angle (deg) of the orbit through (rv, vv): Kepler's closed form at r = R + EPR_ATM on the descending
// branch (the position and the velocity there follow from the orbit; no time is needed); 999 = no interface.
FUNCTION aoaKepFpa {
    PARAMETER rv, vv.
    LOCAL rEi IS EPR_R + EPR_ATM.
    LOCAL hv IS VCRS(rv, vv).
    LOCAL p IS hv:SQRMAGNITUDE / EPR_MU.
    LOCAL ev IS VCRS(vv, hv) * (1 / EPR_MU) - rv:NORMALIZED.
    LOCAL ecc IS ev:MAG.
    IF ecc < 0.000000001 { RETURN 999. }
    IF p / (1 + ecc) >= rEi { RETURN 999. }                 // the perigee outside the interface
    IF ecc < 1 { IF p / (1 - ecc) <= rEi { RETURN 999. } }  // the apogee inside it
    LOCAL cnu IS MAX(-1, MIN(1, (p / rEi - 1) / ecc)).
    LOCAL snu IS -SQRT(1 - cnu * cnu).                      // descending: the true anomaly's sine < 0
    LOCAL pv IS ev * (1 / ecc).
    LOCAL qv IS VCRS(hv, pv):NORMALIZED.
    RETURN aoaFpaAt((pv * cnu + qv * snu) * rEi, (qv * (ecc + cnu) - pv * snu) * SQRT(EPR_MU / p)).
}

// The along-track impulse dvt (m/s, > 0 prograde) for the interface angle gam (-400..+400 m/s,
// 16 bisections, the steeper end returned; more prograde = shallower, no interface = too shallow); 9999 = none.
FUNCTION aoaDvtForFpa {
    PARAMETER rv, vv, gam.
    LOCAL lo IS -400.
    LOCAL hi IS 400.
    LOCAL u IS vv:NORMALIZED.
    IF aoaKepFpa(rv, vv + u * lo) > gam { RETURN 9999. }    // 999 (none) is > gam too
    FROM { LOCAL k IS 0. } UNTIL k >= 16 STEP { SET k TO k + 1. } DO {
        LOCAL mid IS 0.5 * (lo + hi).
        IF aoaKepFpa(rv, vv + u * mid) > gam { SET hi TO mid. } ELSE { SET lo TO mid. }
    }
    RETURN lo.
}

// One coast step of h s: RK4 under J2 on Sol (eprJ2Step, as eprKepToEI's coast), the conic elsewhere (eprKepState).
FUNCTION aoaStep {
    PARAMETER rv, vv, h.
    IF EPR_J2_ON { RETURN eprJ2Step(rv, vv, h). }
    RETURN eprKepState(rv, vv, h).
}

// The coast's ephemeris: the state every AOA_DT s from the epoch, n steps (fewer if it reaches the interface).
FUNCTION aoaEphem {
    PARAMETER rv, vv, n.
    LOCAL eph IS LIST(LIST(rv, vv)).
    LOCAL rEi IS EPR_R + EPR_ATM.
    FROM { LOCAL k IS 0. } UNTIL k >= n STEP { SET k TO k + 1. } DO {
        LOCAL st IS aoaStep(rv, vv, AOA_DT).
        IF st[0]:MAG <= rEi { BREAK. }
        SET rv TO st[0].
        SET vv TO st[1].
        eph:ADD(st).
    }
    RETURN eph.
}

// The state t s after the epoch (inside the ephemeris): its sample at or before t, then one RK4 step to t.
FUNCTION aoaStateAt {
    PARAMETER eph, t.
    LOCAL k IS MIN(FLOOR(t / AOA_DT), eph:LENGTH - 1).
    LOCAL dt IS t - k * AOA_DT.
    IF dt <= 0 { RETURN eph[k]. }
    RETURN aoaStep(eph[k][0], eph[k][1], dt).
}

// The great circle's bearing (deg, 0..360) from point 1 to point 2 (deorbit_sim.bearing_deg).
FUNCTION aoaBearing {
    PARAMETER lat1, lng1, lat2, lng2.
    LOCAL dl IS lng2 - lng1.
    RETURN MOD(ARCTAN2(SIN(dl) * COS(lat2), COS(lat1) * SIN(lat2) - SIN(lat1) * COS(lat2) * COS(dl)) + 360, 360).
}

// The azimuth error (deg: the heading minus the bearing to the target, as eprAzError and python's azimuth_error) of a
// PREDICTED state, its position's longitude rotated by tRot s after EPR_GEO_T0 (eprAzError reads the live position).
FUNCTION aoaAzErr {
    PARAMETER rv, vv, tRot, tgtLat, tgtLng.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL upv IS rv:NORMALIZED.
    LOCAL hz IS vrelv - upv * VDOT(vrelv, upv).
    IF hz:MAG < 1 { RETURN 0. }
    LOCAL eq IS rv - EPR_WAXIS * VDOT(rv, EPR_WAXIS).
    IF eq:MAG < 1 { RETURN 0. }
    LOCAL en IS eprEastNorth(rv).
    IF en[0]:MAG < 0.5 { RETURN 0. }
    LOCAL g IS eprToGeoInertial(rv, tRot).
    LOCAL hdg IS ARCTAN2(VDOT(hz, en[0]), VDOT(hz, en[1])).
    LOCAL dl IS tgtLng - g[1].
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(tgtLat), COS(g[0]) * SIN(tgtLat) - SIN(g[0]) * COS(tgtLat) * COS(dl)).
    LOCAL e IS hdg - brg.
    UNTIL e <= 180 { SET e TO e - 360. }
    UNTIL e > -180 { SET e TO e + 360. }
    RETURN e.
}

// The lowest height (m) of the vacuum coast from (rv, vv) under J2: aoaStep every AOA_DT s until the radius stops
// falling, then the vertex of the parabola through the last three radii.
FUNCTION aoaHpJ2 {
    PARAMETER rv, vv.
    LOCAL r0 IS rv:MAG.
    LOCAL st IS aoaStep(rv, vv, AOA_DT).
    LOCAL r1 IS st[0]:MAG.
    IF r1 >= r0 { RETURN r0 - EPR_R. }
    FROM { LOCAL k IS 1. } UNTIL k >= AOA_HPJ2_KMAX STEP { SET k TO k + 1. } DO {
        SET st TO aoaStep(st[0], st[1], AOA_DT).
        LOCAL r2 IS st[0]:MAG.
        IF r2 >= r1 {
            LOCAL den IS r0 - 2 * r1 + r2.
            IF den <= 0 { RETURN r1 - EPR_R. }
            RETURN r1 - (r2 - r0) ^ 2 / (8 * den) - EPR_R.
        }
        SET r0 TO r1.
        SET r1 TO r2.
    }
    RETURN r1 - EPR_R.
}

// The reach from the interface state (rv, vv) (the surrogate above): LIST(the middle m, the skim m, h_pJ2 m, v_rel
// m/s), or 0 outside its fitted box or past the skim guard.
FUNCTION aoaDmid {
    PARAMETER rv, vv.
    LOCAL pa IS aoaPeriApo(rv, vv).
    IF pa = 0 { RETURN 0. }
    LOCAL haKm IS (pa[1] - EPR_R) / 1000.
    LOCAL vrel IS (vv - eprOmegaCross(rv)):MAG.
    LOCAL bx IS AOA_SUR_BOX.
    IF haKm < bx[2] OR haKm > bx[3] OR vrel < bx[4] OR vrel > bx[5] { RETURN 0. }
    LOCAL hpj IS aoaHpJ2(rv, vv).
    LOCAL hpKm IS hpj / 1000.
    IF hpKm < bx[0] OR hpKm > bx[1] { RETURN 0. }
    LOCAL x IS hpKm - AOA_SUR_HP0.
    LOCAL y IS (haKm - AOA_SUR_HA0) / AOA_SUR_HAS.
    LOCAL z IS (vrel - AOA_SUR_V0) / AOA_SUR_VS.
    LOCAL c IS AOA_SUR_C.
    LOCAL d IS AOA_SUR_D.
    LOCAL arc IS CONSTANT:E ^ (c[0] + x * (c[1] + x * (c[2] + x * c[3])) + y * (c[4] + x * (c[5] + x * c[6]) + y * c[7])
                               + z * (c[8] + x * c[9] + y * c[10])).
    IF arc > AOA_ARC_MAX { RETURN 0. }
    RETURN LIST(1000 * (arc + d[0] + x * (d[1] + x * d[3]) + y * d[2] + z * (d[4] + x * d[5] + y * d[6])), 1000 * arc, hpj,
                vrel).
}

// One ignition: the burn dvt at t (s after the epoch) and the interface ei it gives (aoaBurnEI); s = an AOA_SITES
// row; tGeo = the epoch's time after EPR_GEO_T0; rmp = with the 30 deg alpha ramp (its reach, T, blend and centre).
// A LEXICON, or 0 (no interface, off the fitted box, past the skim guard). xt = the site's cross-track (+ left) on the
// interface's ground track (the log's old measure); the gate reads xo (above AOA_XT_T0).
FUNCTION aoaEval {
    PARAMETER ei, t, dvt, tGeo, s, rmp.
    IF ei[2] <= 0 { RETURN 0. }
    LOCAL pa IS aoaPeriApo(ei[0], ei[1]).
    IF pa = 0 { RETURN 0. }
    LOCAL dmv IS aoaDmid(ei[0], ei[1]).
    IF dmv = 0 { RETURN 0. }
    LOCAL m IS CHOOSE 1 IF rmp ELSE 0.
    LOCAL dm IS dmv[0].
    IF rmp { SET dm TO dm + 1000 * (AOA_RAMP_G0 + AOA_RAMP_G1 * (dmv[3] - AOA_SUR_V0) / AOA_SUR_VS
                                    + AOA_RAMP_G2 * (dmv[2] / 1000 - AOA_SUR_HP0)). }
    LOCAL tRot IS tGeo + t + ei[2].
    LOCAL geo IS eprToGeoInertial(ei[0], tRot).
    LOCAL aim IS eprDestGeo(s[0], s[1], aoaBearing(s[0], s[1], geo[0], geo[1]), AOA_FTP_M).
    LOCAL dAim IS eprGcDist(geo[0], geo[1], aim[0], aim[1]).
    LOCAL dSite IS eprGcDist(geo[0], geo[1], s[0], s[1]).
    LOCAL az IS aoaAzErr(ei[0], ei[1], tRot, s[0], s[1]).
    LOCAL xt IS EPR_R * ARCSIN(MAX(-1, MIN(1, SIN(dSite / EPR_R * CONSTANT:RADTODEG) * SIN(az)))) * CONSTANT:DEGTORAD.
    LOCAL azA IS aoaAzErr(ei[0], ei[1], tRot, aim[0], aim[1]).
    LOCAL xp IS -EPR_R * ARCSIN(MAX(-1, MIN(1, SIN(dAim / EPR_R * CONSTANT:RADTODEG) * SIN(azA)))) * CONSTANT:DEGTORAD.
    LOCAL tA IS tRot + AOA_XT_T0[m] + AOA_XT_T1[m] * (dm / 1000 - 3500).
    LOCAL fw IS VCRS(VCRS(ei[0], ei[1]), ei[0]):NORMALIZED.
    LOCAL g1 IS eprToGeoInertial(ei[0], tA).
    LOCAL g2 IS eprToGeoInertial(ei[0] * COS(10) + fw * (ei[0]:MAG * SIN(10)), tA).
    LOCAL rel IS aoaBearing(g1[0], g1[1], aim[0], aim[1]) - aoaBearing(g1[0], g1[1], g2[0], g2[1]).
    LOCAL dA1 IS eprGcDist(g1[0], g1[1], aim[0], aim[1]).
    LOCAL xa IS EPR_R * ARCSIN(MAX(-1, MIN(1, SIN(dA1 / EPR_R * CONSTANT:RADTODEG) * SIN(rel)))) * CONSTANT:DEGTORAD.
    LOCAL xm IS (1 - AOA_XT_EPS[m]) * xa + AOA_XT_EPS[m] * xp.
    RETURN LEXICON("t", t, "dvt", dvt, "tc", ei[2], "f", dAim - dm, "az", az, "xt", xt, "dAim", dAim, "dmid", dm,
                   "lat", geo[0], "lng", geo[1], "aimLat", aim[0], "aimLng", aim[1], "hp", pa[0] - EPR_R,
                   "ha", pa[1] - EPR_R, "fpa", aoaFpaAt(ei[0], ei[1]), "xp", xp, "xa", xa, "xm", xm,
                   "xo", ABS(xm - AOA_XT_C[m]), "ramp", rmp, "arc", dmv[1], "hpj2", dmv[2], "vrel", dmv[3]).
}

// OMS-2's dvt for the interface angle gam from the state st (LIST(r, v)) and the interface it gives: dvt by Kepler's
// closed form, the interface coasted (eprKepToEI: J2 on Sol), and when the coasted angle misses gam by more than
// AOA_FPA_TOL (J2: up to ~0.1 deg steeper on a long coast) ONE correction, the target moved by the miss, so the
// entry flies the angle asked for. LIST(dvt, ei), or 0 with no dvt.
FUNCTION aoaBurnEI {
    PARAMETER st, gam.
    LOCAL dvt IS aoaDvtForFpa(st[0], st[1], gam).
    IF dvt = 9999 { RETURN 0. }
    LOCAL ei IS eprKepToEI(st[0], st[1] + st[1]:NORMALIZED * dvt).
    IF ei[2] > 0 {
        LOCAL miss IS aoaFpaAt(ei[0], ei[1]) - gam.
        IF ABS(miss) > AOA_FPA_TOL {
            LOCAL dvt2 IS aoaDvtForFpa(st[0], st[1], gam - miss).
            IF dvt2 <> 9999 {
                SET dvt TO dvt2.
                SET ei TO eprKepToEI(st[0], st[1] + st[1]:NORMALIZED * dvt).
            }
        }
    }
    RETURN LIST(dvt, ei).
}

// The ignition at t for the angle gam (rmp as aoaEval): 0 with no dvt, no interface or the site behind
// (|az| >= 90).
FUNCTION aoaAtIg {
    PARAMETER eph, t, tGeo, s, gam, rmp.
    LOCAL be IS aoaBurnEI(aoaStateAt(eph, t), gam).
    IF be = 0 { RETURN 0. }
    LOCAL x IS aoaEval(be[1], t, be[0], tGeo, s, rmp).
    IF x = 0 { RETURN 0. }
    IF ABS(x["az"]) >= 90 { RETURN 0. }
    RETURN x.
}

// A bracket of f (xa at ta, xb at tb) bisected 11 times (rmp as aoaEval): the end with the smaller |f|.
FUNCTION aoaBisect {
    PARAMETER eph, tGeo, s, gam, ta, xa, tb, xb, rmp.
    FROM { LOCAL i IS 0. } UNTIL i >= 11 STEP { SET i TO i + 1. } DO {
        LOCAL mid IS 0.5 * (ta + tb).
        LOCAL x IS aoaAtIg(eph, mid, tGeo, s, gam, rmp).
        IF x = 0 { BREAK. }
        IF (x["f"] > 0) = (xa["f"] > 0) {
            SET ta TO mid.
            SET xa TO x.
        } ELSE {
            SET tb TO mid.
            SET xb TO x.
        }
    }
    IF ABS(xa["f"]) <= ABS(xb["f"]) { RETURN xa. }
    RETURN xb.
}

// The grid every AOA_DT s from AOA_T_LEAD to tHi at the angle gam (rmp as aoaEval), every bracket of f bisected: the
// least |dvt| among the ends at the reach's middle (|f| < AOA_F_TOL), the crossrange gate (xo <= AOA_XT_MAX) and the
// OMS (dvMax m/s). With none, the grid point nearest the middle with |f| <= AOA_F_OFF and the same limits (an EO at
// 145 s: every ignition puts KSC 107-808 km past the middle, never across
// it); 0 with neither. AOA_XT_ONLY counts the candidates the gate alone turned away.
FUNCTION aoaSolveIg {
    PARAMETER eph, tGeo, s, gam, dvMax, tHi, rmp.
    LOCAL m IS CHOOSE 1 IF rmp ELSE 0.
    LOCAL k1 IS MIN(FLOOR(tHi / AOA_DT), eph:LENGTH - 1).
    LOCAL best IS 0.
    LOCAL xNear IS 0.
    LOCAL xa IS 0.
    LOCAL ta IS 0.
    FROM { LOCAL k IS CEILING(AOA_T_LEAD / AOA_DT). } UNTIL k > k1 STEP { SET k TO k + 1. } DO {
        LOCAL tb IS k * AOA_DT.
        LOCAL xb IS aoaAtIg(eph, tb, tGeo, s, gam, rmp).
        IF AOA_PROG_ON { SET AOA_PROG:TEXT TO aoaProgTxt(tb, xb, "dvt", gam, rmp, FALSE). }
        IF NOT (xb = 0) {
            IF ABS(xb["f"]) <= AOA_F_OFF AND ABS(xb["dvt"]) <= dvMax {
                IF xb["xo"] > AOA_XT_MAX[m] {
                    SET AOA_XT_ONLY TO AOA_XT_ONLY + 1.
                } ELSE IF xNear = 0 {
                    SET xNear TO xb.
                } ELSE IF ABS(xb["f"]) < ABS(xNear["f"]) {
                    SET xNear TO xb.
                }
            }
        }
        IF NOT (xa = 0) AND NOT (xb = 0) {
            IF xa["f"] * xb["f"] <= 0 {
                LOCAL x IS aoaBisect(eph, tGeo, s, gam, ta, xa, tb, xb, rmp).
                IF ABS(x["f"]) < AOA_F_TOL AND ABS(x["dvt"]) <= dvMax {
                    IF x["xo"] > AOA_XT_MAX[m] {
                        SET AOA_XT_ONLY TO AOA_XT_ONLY + 1.
                    } ELSE IF best = 0 {
                        SET best TO x.
                    } ELSE IF ABS(x["dvt"]) < ABS(best["dvt"]) {
                        SET best TO x.
                    }
                }
            }
        }
        SET xa TO xb.
        SET ta TO tb.
    }
    IF best = 0 { RETURN xNear. }
    RETURN best.
}

// THE RADIAL FALLBACK (see AOA_DVR_STEP). The radial unit vector at (rv, vv): r's part perpendicular to the prograde (in
// the plane, away from the body: KSP's node RADIALOUT).
FUNCTION aoaRadialOut {
    PARAMETER rv, vv.
    LOCAL u IS vv:NORMALIZED.
    RETURN (rv - u * VDOT(rv, u)):NORMALIZED.
}

// aoaDvtForFpa from vv + dvr x the radial (the same bisection along vv's prograde); 9999 = none.
FUNCTION aoaDvtForFpaR {
    PARAMETER rv, vv, gam, dvr.
    LOCAL lo IS -400.
    LOCAL hi IS 400.
    LOCAL u IS vv:NORMALIZED.
    LOCAL w IS vv + aoaRadialOut(rv, vv) * dvr.
    IF aoaKepFpa(rv, w + u * lo) > gam { RETURN 9999. }
    FROM { LOCAL k IS 0. } UNTIL k >= 16 STEP { SET k TO k + 1. } DO {
        LOCAL mid IS 0.5 * (lo + hi).
        IF aoaKepFpa(rv, w + u * mid) > gam { SET hi TO mid. } ELSE { SET lo TO mid. }
    }
    RETURN lo.
}

// aoaBurnEI with the radial part dvr (the same one correction of the coasted angle): LIST(dvt, ei), or 0.
FUNCTION aoaBurnEIR {
    PARAMETER st, gam, dvr.
    LOCAL u IS st[1]:NORMALIZED.
    LOCAL w IS st[1] + aoaRadialOut(st[0], st[1]) * dvr.
    LOCAL dvt IS aoaDvtForFpaR(st[0], st[1], gam, dvr).
    IF dvt = 9999 { RETURN 0. }
    LOCAL ei IS eprKepToEI(st[0], w + u * dvt).
    IF ei[2] > 0 {
        LOCAL miss IS aoaFpaAt(ei[0], ei[1]) - gam.
        IF ABS(miss) > AOA_FPA_TOL {
            LOCAL dvt2 IS aoaDvtForFpaR(st[0], st[1], gam - miss, dvr).
            IF dvt2 <> 9999 {
                SET dvt TO dvt2.
                SET ei TO eprKepToEI(st[0], w + u * dvt).
            }
        }
    }
    RETURN LIST(dvt, ei).
}

// The ignition at t with the radial part dvr (aoaAtIg's limits): aoaEval's LEXICON + "dvr" and "dv" (the burn's
// magnitude, m/s), or 0.
FUNCTION aoaAtIgR {
    PARAMETER eph, t, tGeo, s, gam, dvr, rmp.
    LOCAL be IS aoaBurnEIR(aoaStateAt(eph, t), gam, dvr).
    IF be = 0 { RETURN 0. }
    LOCAL x IS aoaEval(be[1], t, be[0], tGeo, s, rmp).
    IF x = 0 { RETURN 0. }
    IF ABS(x["az"]) >= 90 { RETURN 0. }
    x:ADD("dvr", dvr).
    x:ADD("dv", SQRT(be[0] ^ 2 + dvr ^ 2)).
    RETURN x.
}

// One ignition's radial root: the point at dvr 0, the probe AOA_DVR_STEP toward the aim, then the secant on f(dvr)
// (AOA_DVR_ITERS steps at most, |dvr| <= AOA_DVR_MAX, stopping below AOA_DVR_FTOL): the point with the least |f|, or 0.
FUNCTION aoaRadialAt {
    PARAMETER eph, t, tGeo, s, gam, rmp.
    LOCAL x0 IS aoaAtIgR(eph, t, tGeo, s, gam, 0, rmp).
    IF x0 = 0 { RETURN 0. }
    LOCAL d0 IS 0.
    LOCAL f0 IS x0["f"].
    LOCAL d1 IS CHOOSE AOA_DVR_STEP IF f0 > 0 ELSE -AOA_DVR_STEP.
    LOCAL x1 IS aoaAtIgR(eph, t, tGeo, s, gam, d1, rmp).
    IF x1 = 0 { RETURN x0. }
    LOCAL best IS CHOOSE x1 IF ABS(x1["f"]) < ABS(f0) ELSE x0.
    FROM { LOCAL i IS 0. } UNTIL i >= AOA_DVR_ITERS STEP { SET i TO i + 1. } DO {
        LOCAL f1 IS x1["f"].
        IF ABS(f1) < AOA_DVR_FTOL OR f1 = f0 { BREAK. }
        LOCAL d2 IS MAX(-AOA_DVR_MAX, MIN(AOA_DVR_MAX, d1 - f1 * (d1 - d0) / (f1 - f0))).
        LOCAL x2 IS aoaAtIgR(eph, t, tGeo, s, gam, d2, rmp).
        IF x2 = 0 { BREAK. }
        SET d0 TO d1.
        SET f0 TO f1.
        SET d1 TO d2.
        SET x1 TO x2.
        IF ABS(x2["f"]) < ABS(best["f"]) { SET best TO x2. }
    }
    RETURN best.
}

// the kOS search's progress line ("OMS-2 <MET> DV <dv> FPA <angle> ALPHARAMP" / "... RADIAL")
// for the ignition t s after the solve's epoch just tried: its MET of TIG (ddd/hh:mm:ss; "+t S" when the solve is not
// timed), the candidate's dv x[k] (m/s; -- where it has none), the angle and the ladder.
FUNCTION aoaProgTxt {
    PARAMETER t, x, k, gam, rmp, rad.
    LOCAL dv IS "--".
    IF NOT (x = 0) { SET dv TO "" + ROUND(ABS(x[k])). }
    LOCAL met IS "+" + t + " S".
    IF AOA_T0_SOLVE <> -1 { SET met TO aoaMet(MISSIONTIME + AOA_T0_SOLVE + t - TIME:SECONDS). }
    RETURN "OMS-2 " + met + " DV " + dv + " FPA " + ROUND(gam, 2) + (CHOOSE " ALPHARAMP" IF rmp ELSE "")
           + (CHOOSE " RADIAL" IF rad ELSE "").
}
FUNCTION aoaMet {                           // ddd/hh:mm:ss of t s (>= 0), shuttle_exec's exMET
    PARAMETER t.
    LOCAL s IS ROUND(MAX(t, 0)).
    LOCAL d IS "" + FLOOR(s / 86400).
    RETURN d:PADLEFT(3):REPLACE(" ", "0") + "/" + aoaP2(FLOOR(MOD(s, 86400) / 3600)) + ":" + aoaP2(FLOOR(MOD(s, 3600) / 60))
           + ":" + aoaP2(MOD(s, 60)).
}
FUNCTION aoaP2 {
    PARAMETER n.
    RETURN (CHOOSE "0" IF n < 10 ELSE "") + n.
}

// The game time (s) the solve from the ship has used so far (AOA_T0_SOLVE, set by aoaSolveNow), 0 when not timed.
FUNCTION aoaSpent {
    IF AOA_T0_SOLVE = -1 { RETURN 0. }
    RETURN TIME:SECONDS - AOA_T0_SOLVE.
}

// The radial fallback's grid every AOA_DT s from AOA_T_LEAD after the game time the solve has used (aoaSpent) to tHi at
// the angle gam (rmp as aoaEval): each ignition's root (aoaRadialAt); among the roots with |f| < AOA_F_TOL, the crossrange
// gate and |dv| <= dvMax, those still AOA_T_LEAD after the solve's end, the least |dv|, or 0. AOA_XT_ONLY counts the roots
// the gate alone turned away.
FUNCTION aoaSolveRadial {
    PARAMETER eph, tGeo, s, gam, dvMax, tHi, rmp.
    LOCAL m IS CHOOSE 1 IF rmp ELSE 0.
    LOCAL k1 IS MIN(FLOOR(tHi / AOA_DT), eph:LENGTH - 1).
    LOCAL cands IS LIST().
    FROM { LOCAL k IS CEILING((AOA_T_LEAD + aoaSpent()) / AOA_DT). } UNTIL k > k1 STEP { SET k TO k + 1. } DO {
        LOCAL t IS k * AOA_DT.
        LOCAL x IS aoaRadialAt(eph, t, tGeo, s, gam, rmp).
        IF AOA_PROG_ON { SET AOA_PROG:TEXT TO aoaProgTxt(t, x, "dv", gam, rmp, TRUE). }
        IF NOT (x = 0) {
            IF ABS(x["f"]) < AOA_F_TOL AND x["dv"] <= dvMax {
                IF x["xo"] > AOA_XT_MAX[m] {
                    SET AOA_XT_ONLY TO AOA_XT_ONLY + 1.
                } ELSE {
                    cands:ADD(x).
                }
            }
        }
    }
    LOCAL tMin IS AOA_T_LEAD + aoaSpent().
    LOCAL best IS 0.
    FOR xc IN cands {
        IF xc["t"] >= tMin {
            IF best = 0 {
                SET best TO xc.
            } ELSE IF xc["dv"] < best["dv"] {
                SET best TO xc.
            }
        }
    }
    RETURN best.
}

// A solve's radial part (m/s, + out), 0 for a prograde-only one.
FUNCTION aoaDvR {
    PARAMETER x.
    IF x:HASKEY("dvr") { RETURN x["dvr"]. }
    RETURN 0.
}

// A solve's burn magnitude (m/s).
FUNCTION aoaDvMag {
    PARAMETER x.
    IF aoaDvR(x) = 0 { RETURN ABS(x["dvt"]). }
    RETURN x["dv"].
}

// A whole number with its sign ("+24", "-21", "0").
FUNCTION aoaSgn {
    PARAMETER val.
    RETURN (CHOOSE "+" IF ROUND(val) > 0 ELSE "") + ROUND(val).
}

// The burn for the window: "21 M/S RETRO" (prograde only, as before); with the radial part "32 M/S TOTAL" (its parts on
// their own row).
FUNCTION aoaDvText {
    PARAMETER x.
    IF aoaDvR(x) = 0 { RETURN ROUND(ABS(x["dvt"])) + " M/S " + (CHOOSE "PRO" IF x["dvt"] >= 0 ELSE "RETRO"). }
    RETURN ROUND(x["dv"]) + " M/S TOTAL".
}

// The burn for the terminal: "21 RETRO" (as before); with the radial part "32 (DVX -21 DVZ +24)", the orbiter's LVLH
// parts (X along the track, Z down: radial in = +Z).
FUNCTION aoaDvLine {
    PARAMETER x.
    IF aoaDvR(x) = 0 { RETURN ROUND(ABS(x["dvt"])) + " " + (CHOOSE "PRO" IF x["dvt"] >= 0 ELSE "RETRO"). }
    RETURN ROUND(x["dv"]) + " (DVX " + aoaSgn(x["dvt"]) + " DVZ " + aoaSgn(-x["dvr"]) + ")".
}

// THE SOLVE IN kOS (aoaSolve below hands it to the KAL/S addon first) from the state (rv, vv) at the epoch
// (tGeo s after EPR_GEO_T0) to the site s, dvMax m/s for OMS-2: the best ignition (aoaEval's LEXICON + "fpaTarget",
// "fpaUsed"), or 0 and AOA_WHY. The nominal ladder first; the ramp's only when the nominal found nothing and its gate alone
// turned candidates away (the ramp for high crossrange only).
FUNCTION aoaSolveKos {
    PARAMETER rv, vv, tGeo, s, dvMax.
    LOCAL pa IS aoaPeriApo(rv, vv).
    IF pa = 0 {
        SET AOA_WHY TO "NOT IN ORBIT".
        RETURN 0.
    }
    LOCAL gam0 IS AOA_FAC * aoaFpaNom(pa[1] - EPR_R).
    LOCAL tHi IS AOA_T_MAX.
    IF pa[0] < EPR_R + EPR_ATM {
        LOCAL nat IS eprKepToEI(rv, vv).
        IF nat[2] >= 0 { SET tHi TO nat[2] - AOA_T_HI_PAD. }
    }
    IF tHi < AOA_T_LEAD + AOA_DT {
        SET AOA_WHY TO "EI IN " + ROUND(tHi + AOA_T_HI_PAD) + " S: NO TIME FOR OMS-2".
        RETURN 0.
    }
    LOCAL eph IS aoaEphem(rv, vv, CEILING(tHi / AOA_DT)).
    SET AOA_XT_ONLY TO 0.
    FOR rmp IN LIST(FALSE, TRUE) {
        IF NOT rmp OR AOA_XT_ONLY > 0 {
            FROM { LOCAL k IS 0. } UNTIL k > AOA_FPA_KMAX STEP { SET k TO k + 1. } DO {
                LOCAL gam IS gam0 - AOA_FPA_STEP * k.
                LOCAL x IS aoaSolveIg(eph, tGeo, s, gam, dvMax, tHi, rmp).
                IF NOT (x = 0) {
                    x:ADD("fpaTarget", gam0).
                    x:ADD("fpaUsed", gam).
                    RETURN x.
                }
            }
        }
    }
    // THE RADIAL FALLBACK (AOA_DVR_STEP): only when the executor flies a radial part (OMS_PLAN_DVR).
    LOCAL radTxt IS "".
    LOCAL radOn IS FALSE.
    IF DEFINED OMS_PLAN_DVR { SET radOn TO OMS_PLAN_DVR. }
    IF radOn {
        SET radTxt TO "  RADIAL".
        LOCAL xtTan IS AOA_XT_ONLY.
        SET AOA_XT_ONLY TO 0.
        FOR rmpR IN LIST(FALSE, TRUE) {
            IF NOT rmpR OR AOA_XT_ONLY > 0 {
                LOCAL xr IS aoaSolveRadial(eph, tGeo, s, gam0, dvMax, tHi, rmpR).
                IF NOT (xr = 0) {
                    xr:ADD("fpaTarget", gam0).
                    xr:ADD("fpaUsed", gam0).
                    RETURN xr.
                }
            }
        }
        SET AOA_XT_ONLY TO AOA_XT_ONLY + xtTan.
    }
    SET AOA_WHY TO "NO OMS-2 WITHIN " + ROUND(AOA_F_OFF / 1000) + "K OF MID-REACH  FPA " + ROUND(gam0, 2) + " TO "
                   + ROUND(gam0 - AOA_FPA_STEP * AOA_FPA_KMAX, 2) + "  CROSSRANGE <= " + ROUND(AOA_XT_MAX[0] / 1000)
                   + (CHOOSE ("K, RAMP " + ROUND(AOA_XT_MAX[1] / 1000) + "K") IF AOA_XT_ONLY > 0 ELSE "K") + "  DV <= "
                   + ROUND(dvMax) + radTxt.
    RETURN 0.
}

// THE SOLVE (aoaSolveKos's parameters and result): the KAL/S addon's when AOA_CS, kOS's on any failure.
// AOA_CS_SAY says which ran (printed only for the kOS fallback).
FUNCTION aoaSolve {
    PARAMETER rv, vv, tGeo, s, dvMax.
    IF NOT AOA_CS { RETURN aoaSolveKos(rv, vv, tGeo, s, dvMax). }
    LOCAL cr IS aoaCsRun(rv, vv, tGeo, s, dvMax).
    IF cr[0] <> "" {
        aoaCsSay("AOA SOLVE: KOS (" + cr[0] + ")").
        RETURN aoaSolveKos(rv, vv, tGeo, s, dvMax).
    }
    LOCAL res IS cr[1].
    // kept in AOA_CS_SAY, not printed (not shown on screen)
    SET AOA_CS_SAY TO "AOA SOLVE IN C#: " + ROUND(cr[2]) + " MS, " + cr[3] + " THREADS".
    IF res["xtOnly"] >= 0 { SET AOA_XT_ONLY TO res["xtOnly"]. }
    IF NOT res["found"] {
        SET AOA_WHY TO aoaCsWhy(res, dvMax, AOA_XT_ONLY).
        RETURN 0.
    }
    RETURN res["x"].
}

// The C#'s solve: LIST("", its result, ms, threads) or LIST(why kOS solves, 0, 0, 0). Polls the handle (WAIT 0: both
// callers, aoaAsk and aoaPlanOms2, run in the main line).
FUNCTION aoaCsRun {
    PARAMETER rv, vv, tGeo, s, dvMax.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN LIST("no KAL/S addon", 0, 0, 0). }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN LIST("KAL/S not available", 0, 0, 0). }
    IF NOT ADDONS:KALS:HASSUFFIX("AOASOLVE") { RETURN LIST("the KAL/S dll has no AOASOLVE", 0, 0, 0). }
    LOCAL h IS ADDONS:KALS:AOASOLVE(aoaCsIn(rv, vv, tGeo, s, dvMax)).
    LOCAL t0 IS TIME:SECONDS.
    UNTIL h:DONE {
        IF TIME:SECONDS - t0 > AOA_CS_TMAX { RETURN LIST("no result in " + AOA_CS_TMAX + " s", 0, 0, 0). }
        WAIT 0.
    }
    IF NOT h:OK { RETURN LIST("AOASOLVE: " + h:ERROR, 0, 0, 0). }
    LOCAL res IS h:RESULT.
    IF NOT res:HASKEY("found") { RETURN LIST("AOASOLVE: no result", 0, 0, 0). }
    IF res["found"] {
        // aoaSolveRadial's rule, now that the solve has ended: the radial plan's ignition AOA_T_LEAD after the solve's end
        IF res["x"]:HASKEY("dvr") AND res["x"]["t"] < AOA_T_LEAD + aoaSpent() { RETURN LIST("radial plan too soon", 0, 0, 0). }
    }
    RETURN LIST("", res, h:MS, h:THREADS).
}

// The C#'s input: the solve's arguments, the constants, the radial flag (aoaSolveKos's radOn) and the time the solve has
// used (aoaSpent; in a timed solve + AOA_CS_SPENT_PAD, the C#'s own: its radial grid starts after the solve's end).
FUNCTION aoaCsIn {
    PARAMETER rv, vv, tGeo, s, dvMax.
    LOCAL radOn IS FALSE.
    IF DEFINED OMS_PLAN_DVR { SET radOn TO OMS_PLAN_DVR. }
    LOCAL sp IS 0.
    IF AOA_T0_SOLVE <> -1 { SET sp TO aoaSpent() + AOA_CS_SPENT_PAD. }
    RETURN LEXICON("c", aoaCsConsts(), "rv", rv, "vv", vv, "tGeo", tGeo, "slat", s[0], "slng", s[1], "dvMax", dvMax,
                   "radial", radOn, "spent", sp, "threads", AOA_CS_THREADS).
}

// Every constant the C# reads, by its kOS name (coproc/Aoa.cs AoaC: all required).
FUNCTION aoaCsConsts {
    RETURN LEXICON("CE", CONSTANT:E, "RADTODEG", CONSTANT:RADTODEG, "DEGTORAD", CONSTANT:DEGTORAD,
        "EPR_R", EPR_R, "EPR_MU", EPR_MU, "EPR_ATM", EPR_ATM, "EPR_WMAG", EPR_WMAG,
        "EPR_J2", EPR_J2, "EPR_R_J2", EPR_R_J2, "EPR_NSIGN", EPR_NSIGN, "EPR_ROT_SIGN", EPR_ROT_SIGN,
        "EPR_J2_ON", EPR_J2_ON, "EPR_WAXIS", EPR_WAXIS, "EPR_NAXIS", EPR_NAXIS, "EPR_GEO_X", EPR_GEO_X,
        "EPR_GEO_Y", EPR_GEO_Y, "AOA_FAC", AOA_FAC, "AOA_FPA_SLOPE", AOA_FPA_SLOPE, "AOA_FPA_ICPT", AOA_FPA_ICPT,
        "AOA_FPA_MARGIN", AOA_FPA_MARGIN, "AOA_FPA_STEP", AOA_FPA_STEP, "AOA_FPA_KMAX", AOA_FPA_KMAX, "AOA_FPA_TOL", AOA_FPA_TOL,
        "AOA_XT_MAX", AOA_XT_MAX, "AOA_T_LEAD", AOA_T_LEAD, "AOA_DT", AOA_DT, "AOA_T_HI_PAD", AOA_T_HI_PAD,
        "AOA_T_MAX", AOA_T_MAX, "AOA_F_TOL", AOA_F_TOL, "AOA_F_OFF", AOA_F_OFF, "AOA_DVR_STEP", AOA_DVR_STEP,
        "AOA_DVR_ITERS", AOA_DVR_ITERS, "AOA_DVR_MAX", AOA_DVR_MAX, "AOA_DVR_FTOL", AOA_DVR_FTOL, "AOA_FTP_M", AOA_FTP_M,
        "AOA_SUR_C", AOA_SUR_C, "AOA_SUR_D", AOA_SUR_D, "AOA_SUR_HP0", AOA_SUR_HP0, "AOA_SUR_HA0", AOA_SUR_HA0,
        "AOA_SUR_HAS", AOA_SUR_HAS, "AOA_SUR_V0", AOA_SUR_V0, "AOA_SUR_VS", AOA_SUR_VS, "AOA_SUR_BOX", AOA_SUR_BOX,
        "AOA_ARC_MAX", AOA_ARC_MAX, "AOA_HPJ2_KMAX", AOA_HPJ2_KMAX, "AOA_XT_T0", AOA_XT_T0, "AOA_XT_T1", AOA_XT_T1,
        "AOA_XT_EPS", AOA_XT_EPS, "AOA_XT_C", AOA_XT_C, "AOA_RAMP_G0", AOA_RAMP_G0, "AOA_RAMP_G1", AOA_RAMP_G1,
        "AOA_RAMP_G2", AOA_RAMP_G2).
}

// AOA_WHY for the C#'s result (aoaSolveKos's texts; xt = AOA_XT_ONLY after the solve); "" when it found a plan.
FUNCTION aoaCsWhy {
    PARAMETER res, dvMax, xt.
    LOCAL k IS res["whyk"].
    IF k = 1 { RETURN "NOT IN ORBIT". }
    IF k = 2 { RETURN "EI IN " + ROUND(res["tHi"] + AOA_T_HI_PAD) + " S: NO TIME FOR OMS-2". }
    IF k = 3 {
        LOCAL gam0 IS res["gam0"].
        LOCAL radTxt IS "".
        IF DEFINED OMS_PLAN_DVR { IF OMS_PLAN_DVR { SET radTxt TO "  RADIAL". } }
        RETURN "NO OMS-2 WITHIN " + ROUND(AOA_F_OFF / 1000) + "K OF MID-REACH  FPA " + ROUND(gam0, 2) + " TO "
               + ROUND(gam0 - AOA_FPA_STEP * AOA_FPA_KMAX, 2) + "  CROSSRANGE <= " + ROUND(AOA_XT_MAX[0] / 1000)
               + (CHOOSE ("K, RAMP " + ROUND(AOA_XT_MAX[1] / 1000) + "K") IF xt > 0 ELSE "K") + "  DV <= "
               + ROUND(dvMax) + radTxt.
    }
    RETURN "".
}

// The kOS fallback's line (AOA_CS_SAY, why the C# failed), on the terminal.
FUNCTION aoaCsSay {
    PARAMETER txt.
    SET AOA_CS_SAY TO txt.
    kmSay(txt, "C").
}

// The solve from the ship now: the predictor loaded HERE (see the header), the geodesy stamped, the state read in one
// physics tick; to AOA_SITE with the OMS on board less AOA_OMS_RESERVE. Kept in AOA_SOL with "t0", "ut" (OMS-2's
// centre), "rwy" and "site".
FUNCTION aoaSolveNow {
    RUNONCEPATH("0:/lib/entry_predict.ks").
    eprInitGeo().
    LOCAL t0 IS 0.
    LOCAL rv IS V(0, 0, 0).
    LOCAL vv IS V(0, 0, 0).
    UNTIL FALSE {
        SET t0 TO TIME:SECONDS.
        SET rv TO -SHIP:BODY:POSITION.
        SET vv TO SHIP:VELOCITY:ORBIT.
        IF TIME:SECONDS = t0 { BREAK. }
    }
    RETURN aoaSolveFrom(rv, vv, t0, omsDvOnBoard() - AOA_OMS_RESERVE).
}

// aoaSolveNow's solve from the state (rv, vv) at UT t0 (a predicted one too: the ATO / AOA page solves the orbit after
// OMS-1 before it is flown), dvMax m/s for OMS-2: the body of aoaSolveNow, unchanged (aoaSolveNow now calls it).
// eprInitGeo's datum must be stamped (aoaSolveNow does it first).
FUNCTION aoaSolveFrom {
    PARAMETER rv, vv, t0, dvMax.
    IF (DEFINED ASC_RTLS_SITE) { IF AOA_SITES:HASKEY(ASC_RTLS_SITE["name"]) { SET AOA_SITE TO ASC_RTLS_SITE["name"]. } }
    LOCAL s IS AOA_SITES[AOA_SITE].          // the launch site's (ops1q's ASC_RTLS_SITE: SLF from KSC, VBG from SLC-6)
    IF AOA_XT_RAMP_SITE:HASKEY(AOA_SITE) { SET AOA_XT_MAX[1] TO AOA_XT_RAMP_SITE[AOA_SITE]. }   // its ramp gate
    SET AOA_T0_SOLVE TO MIN(t0, TIME:SECONDS).   // aoaSpent: the radial fallback's ignitions after the solve's end (a predicted state's t0 is ahead: its spent time counts from now)
    LOCAL x IS aoaSolve(rv, vv, t0 - EPR_GEO_T0, s, dvMax).
    SET AOA_T0_SOLVE TO -1.
    SET AOA_SOL TO x.
    IF x = 0 { RETURN 0. }
    x:ADD("t0", t0).
    x:ADD("ut", t0 + x["t"]).
    x:ADD("rwy", s[2]).
    x:ADD("site", AOA_SITE).
    RETURN x.
}

// m:ss of s seconds (>= 0).
FUNCTION aoaMmss {
    PARAMETER s.
    LOCAL ss IS FLOOR(MAX(s, 0)).
    LOCAL m IS FLOOR(ss / 60).
    SET ss TO ss - 60 * m.
    RETURN m + ":" + (CHOOSE "0" IF ss < 10 ELSE "") + ss.
}

// PRESS TO ORBIT ("ATO") or COME BACK ("AOA"): the window, blocking until CONFIRM. The AOA's
// numbers from a dry run (aoaSolveNow, kept for aoaPlanOms2). Pre-selected: PRESS TO ORBIT when it leaves the
// deorbit's reserve or there is no AOA, else COME BACK; COME BACK cannot be selected without an AOA solution.
// aoaAsk's readouts: rows of LABEL: VALUE cells, the label columns fixed (as lib_ascent_gui's label widths).
GLOBAL AOA_KV_W IS LIST(140, 120, 130, 120).  // px: two pairs a row
GLOBAL AOA_KV_W1 IS LIST(140, 370).           // px: one pair with a wide value
FUNCTION aoaKv {
    PARAMETER parent, widths.
    LOCAL rw IS uiRow(parent, widths).
    RETURN rw["cells"].
}

// Fills pair i of a readout row: "LABEL:" and the value (hex "" = the body colour).
FUNCTION aoaKvSet {
    PARAMETER cells, i, lbl, val, hex.
    SET cells[2 * i]:TEXT TO lbl + ":".
    SET cells[2 * i + 1]:TEXT TO CHOOSE val IF hex = "" ELSE uiColor(val, hex).
}

// A console message (outside ops3q's start-up log every message has banners
// of = signs): the title centred in = signs over the terminal's 50 columns (as deorbit_plan's PLAN COMPLETE,
// fam_build's Build Complete), then each line wrapped at 50 on its spaces.
GLOBAL AOA_EQ IS "==================================================".
FUNCTION aoaSay {
    PARAMETER ttl, lines.
    IF KM_QUIET {                                // the terminal stays blank: ONE line to the log and the window's MSG line
        LOCAL one IS ttl.
        FOR l IN lines { SET one TO one + ": " + l. }
        kmSay(one, "C").
        RETURN.
    }
    LOCAL n IS MAX(0, 50 - ttl:LENGTH).
    PRINT AOA_EQ:SUBSTRING(0, FLOOR(n / 2)) + ttl + AOA_EQ:SUBSTRING(0, n - FLOOR(n / 2)).
    FOR one IN lines {
        LOCAL t IS one.
        UNTIL t:LENGTH <= 50 {
            LOCAL k IS 50.
            UNTIL k <= 0 OR t:SUBSTRING(k, 1) = " " { SET k TO k - 1. }
            IF k <= 0 { SET k TO 50. }
            PRINT t:SUBSTRING(0, k).
            SET t TO t:SUBSTRING(k, t:LENGTH - k):TRIM.
        }
        PRINT t.
    }
}

FUNCTION aoaAsk {
    PARAMETER info.
    // the window's look (uiBox, uiSection, ...): ops1q loads lib_guistyle, shuttle_exec does not (without it:
    // "Undefined Variable Name 'uibox'" after OMS-1)
    RUNONCEPATH("0:/lib/lib_guistyle.ks").
    LOCAL dvAto IS 0.
    LOCAL dvKeep IS 0.
    IF info:HASKEY("dv_ato") { SET dvAto TO info["dv_ato"]. }
    IF info:HASKEY("dv_keep") { SET dvKeep TO info["dv_keep"]. }
    // the OMS on board as the planner measures it (omsDvOnBoard), so both options and the plan use one number (the
    // caller's measure can read ~0 m/s where the planner's own allows a 42 m/s OMS-2)
    LOCAL dvOms IS omsDvOnBoard().
    LOCAL notes IS LIST().
    IF info:HASKEY("dv_oms") {
        IF ABS(info["dv_oms"] - dvOms) > 1 {
            notes:ADD("OMS DV " + ROUND(dvOms)).
        }
    }
    LOCAL g IS uiBox("ATO / AOA", 560, 60, 120, "SELECT ABORT").
    LOCAL secA IS uiSection(g, "ATO").
    LOCAL ra IS aoaKv(secA, AOA_KV_W).
    LOCAL rb IS aoaKv(secA, AOA_KV_W).
    LOCAL remA IS dvOms - dvAto.
    aoaKvSet(ra, 0, "OMS-2 DV", ROUND(dvAto) + " M/S PRO", "").
    aoaKvSet(ra, 1, "DEORBIT DV", ROUND(dvKeep) + " M/S", "").
    aoaKvSet(rb, 0, "OMS REMAINING", ROUND(remA) + " M/S", CHOOSE UI_WARN IF remA < dvKeep ELSE "").
    // the OMS left after the ATO's OMS-2 against the deorbit + the
    // emergency margin (dv_keep) and the on-orbit allowance
    IF info:HASKEY("dv_onorb") {
        LOCAL rc IS aoaKv(secA, AOA_KV_W1).
        LOCAL onb IS info["dv_onorb"].
        LOCAL em IS 0.
        IF info:HASKEY("dv_emerg") { SET em TO info["dv_emerg"]. }
        LOCAL kt IS "DEORBIT " + ROUND(dvKeep - em) + " + RES " + ROUND(em).
        IF remA >= dvKeep + onb { aoaKvSet(rc, 0, "ATO STATUS", "CONTINUE MISSION: ORBIT " + ROUND(onb) + " KEPT", ""). }
        ELSE IF remA >= dvKeep { aoaKvSet(rc, 0, "ATO STATUS", "EARLY RETURN: " + kt + " KEPT, NOT ORBIT " + ROUND(onb), UI_ACCENT). }
        ELSE { aoaKvSet(rc, 0, "ATO STATUS", "SHORT OF " + kt + ": AOA", UI_WARN). }
    }
    LOCAL secB IS uiSection(g, "AOA").
    LOCAL r1 IS aoaKv(secB, AOA_KV_W).
    LOCAL r2 IS aoaKv(secB, AOA_KV_W).
    LOCAL r3 IS aoaKv(secB, AOA_KV_W).
    LOCAL r5 IS aoaKv(secB, AOA_KV_W).
    LOCAL r4w IS uiRow(secB, AOA_KV_W1).
    LOCAL r4 IS r4w["cells"].
    // OMS-2's time to go: ONE pair "OMS-2 IN:  m:ss" centred across the box, shown in r4's place once there is a solution
    LOCAL rTig IS uiText(secB).
    SET rTig:STYLE:ALIGN TO "CENTER".
    SET rTig:STYLE:HSTRETCH TO TRUE.
    rTig:HIDE().
    SET r4[1]:STYLE:WORDWRAP TO TRUE.
    aoaKvSet(r4, 0, "SOLVING", "", "").
    g:ADDSPACING(UI_GAP).
    LOCAL rowC IS g:ADDHLAYOUT().
    LOCAL bAto IS uiChoice(rowC, "ATO").
    LOCAL bAoa IS uiChoice(rowC, "AOA").
    LOCAL sel IS uiNote(g, "").
    LOCAL rowA IS g:ADDHLAYOUT().
    LOCAL bOk IS uiPrimary(rowA, "CONFIRM").
    g:SHOW().
    SET AOA_PROG TO r4[1].
    SET AOA_PROG_ON TO TRUE.
    LOCAL x IS aoaSolveNow().
    SET AOA_PROG_ON TO FALSE.
    IF x = 0 {
        aoaKvSet(r1, 0, "AOA", "NO SOLUTION", UI_WARN).
        aoaKvSet(r4, 0, "WHY", AOA_WHY, "").
        notes:ADD("NO AOA: " + AOA_WHY).
    } ELSE {
        LOCAL remB IS dvOms - aoaDvMag(x).
        r4w["row"]:HIDE().
        rTig:SHOW().
        aoaKvSet(r1, 0, "OMS-2 DV", aoaDvText(x), "").
        aoaKvSet(r1, 1, "FPA", ROUND(x["fpa"], 2) + " DEG", "").
        aoaKvSet(r2, 0, "OMS REMAINING", ROUND(remB) + " M/S", CHOOSE UI_WARN IF remB < AOA_OMS_RESERVE - 1 ELSE "").
        aoaKvSet(r2, 1, "PRE-BANK", AOA_PRE_BANK + " DEG", "").
        aoaKvSet(r3, 0, "CROSSRANGE", ROUND(ABS(x["xm"]) / 1000) + " KM", "").
        aoaKvSet(r3, 1, "RUNWAY", x["rwy"], "").
        aoaKvSet(r5, 0, "ALPHA RAMP", CHOOSE "ON" IF x["ramp"] ELSE "OFF", "").
        IF aoaDvR(x) <> 0 { aoaKvSet(r5, 1, "DVX / DVZ", aoaSgn(x["dvt"]) + " / " + aoaSgn(-x["dvr"]) + " M/S", ""). }
    }
    LOCAL md IS "AOA".
    IF x = 0 { SET md TO "ATO". }
    IF dvOms - dvAto >= dvKeep { SET md TO "ATO". }
    LOCAL shown IS "".
    LOCAL done IS FALSE.
    UNTIL done {
        IF bAto:TAKEPRESS { SET md TO "ATO". }
        IF bAoa:TAKEPRESS {
            IF x = 0 { SET shown TO "". } ELSE { SET md TO "AOA". }
        }
        IF bOk:TAKEPRESS { SET done TO TRUE. }
        IF md <> shown {
            SET shown TO md.
            uiChoiceShow(bAto, "ATO", md = "ATO").
            uiChoiceShow(bAoa, "AOA", md = "AOA").
            IF x = 0 {
                SET sel:TEXT TO uiColor("NO AOA SOLUTION: ATO ONLY", UI_WARN).
            } ELSE {
                SET sel:TEXT TO "SELECTED: " + md.
            }
        }
        IF NOT (x = 0) {
            LOCAL tg IS x["ut"] - TIME:SECONDS.
            LOCAL tgs IS aoaMmss(tg) + (CHOOSE "" IF tg >= AOA_T_REUSE ELSE "  (CONFIRM RE-SOLVES)").
            SET rTig:TEXT TO "OMS-2 IN:  " + tgs.
        }
        WAIT 0.2.
    }
    g:DISPOSE().
    aoaSay(md + " SELECTED", notes).
    RETURN md.
}

// One line per plan in AOA_LOG_FILE (SOCK_LOG: lib_logsw's switch, when loaded).
FUNCTION aoaLogSol {
    PARAMETER x.
    LOCAL logOn IS TRUE.
    IF DEFINED SOCK_LOG { SET logOn TO SOCK_LOG. }
    IF NOT logOn { RETURN. }
    LOCAL txt IS "AOA UT " + ROUND(TIME:SECONDS, 1) + " t0 " + ROUND(x["t0"], 3) + " ut " + ROUND(x["ut"], 3) + " dvt "
        + ROUND(x["dvt"], 3) + " fpa " + ROUND(x["fpa"], 4) + " target " + ROUND(x["fpaTarget"], 4) + " used "
        + ROUND(x["fpaUsed"], 4) + " f " + ROUND(x["f"]) + " dmid " + ROUND(x["dmid"]) + " xt " + ROUND(x["xt"]) + " az "
        + ROUND(x["az"], 3) + " hp " + ROUND(x["hp"]) + " ha " + ROUND(x["ha"]) + " tc " + ROUND(x["tc"], 1) + " ei "
        + ROUND(x["lat"], 4) + " " + ROUND(x["lng"], 4) + " aim " + ROUND(x["aimLat"], 5) + " " + ROUND(x["aimLng"], 5)
        + " rwy " + x["rwy"] + " xm " + ROUND(x["xm"]) + " xa " + ROUND(x["xa"]) + " xp " + ROUND(x["xp"]) + " xo "
        + ROUND(x["xo"]) + " ramp " + x["ramp"] + " arc " + ROUND(x["arc"]) + " hpj2 " + ROUND(x["hpj2"]) + " vrel "
        + ROUND(x["vrel"], 1).
    IF aoaDvR(x) <> 0 { SET txt TO txt + " dvr " + ROUND(x["dvr"], 3) + " dv " + ROUND(x["dv"], 3). }
    LOG txt TO AOA_LOG_FILE.
}

// THE AOA's OMS-2 PLAN: aoaAsk's dry run while its burn is AOA_T_REUSE s or more ahead, else a new
// solve; the plan file through omsPlanWrite + the runway, the aim, the angle and the fallback bank (lib_plan's
// planRead: the last duplicate key wins), then the flag. TRUE written / FALSE (the terminal says why).
FUNCTION aoaPlanOms2 {
    LOCAL x IS AOA_SOL.
    IF NOT (x = 0) {
        IF x["ut"] - TIME:SECONDS < AOA_T_REUSE { SET x TO 0. }
    }
    IF x = 0 {
        aoaSay("AOA SOLVING OMS-2", LIST()).
        SET x TO aoaSolveNow().
    }
    IF x = 0 {
        aoaSay("AOA NO OMS-2 PLAN", LIST(AOA_WHY)).
        RETURN FALSE.
    }
    LOCAL f IS AOA_PLAN_FILE.
    omsPlanWrite(f, TIME:SECONDS, x["ut"], ABS(x["dvt"]), CHOOSE 1 IF x["dvt"] >= 0 ELSE -1, "AOA OMS-2").
    LOG "runway " + x["rwy"] TO f.
    LOG "aim_lat " + ROUND(x["aimLat"], 6) TO f.
    LOG "aim_lng " + ROUND(x["aimLng"], 6) TO f.
    LOG "org_lat " + ROUND(AOA_SITES[x["site"]][0], 6) TO f.   // the point the aim is built from (ops3q's HAC)
    LOG "org_lng " + ROUND(AOA_SITES[x["site"]][1], 6) TO f.
    LOG "fpa " + ROUND(x["fpa"], 4) TO f.
    LOG "bank " + AOA_FB_BANK TO f.
    IF aoaDvR(x) <> 0 { LOG "dvr " + ROUND(x["dvr"], 4) TO f. }  // the radial part, + out (the executor flies it)
    IF EXISTS(AOA_FLAG_FILE) { DELETEPATH(AOA_FLAG_FILE). }
    LOG "AOA " + x["site"] + (CHOOSE " RAMP" IF x["ramp"] ELSE "") TO AOA_FLAG_FILE.
    aoaLogSol(x).
    LOCAL l1 IS "DV " + aoaDvLine(x) + "  AT T+"
                + aoaMmss(MISSIONTIME + x["ut"] - TIME:SECONDS) + "  FPA " + ROUND(x["fpa"], 2).
    LOCAL l2 IS "RUNWAY " + x["rwy"] + "  CROSSRANGE " + ROUND(ABS(x["xm"]) / 1000) + "K  PRE-BANK " + AOA_PRE_BANK
                + (CHOOSE "  ALPHA RAMP" IF x["ramp"] ELSE "").
    aoaSay("AOA OMS-2 PLANNED", LIST(l1, l2)).
    RETURN TRUE.
}
