// ============================================================================
//  DEORBIT_PLAN.KS  --  plan the deorbit burn and write the plan file
// ============================================================================
//  Run it in orbit, well before the burn:
//      RUN DEORBIT_PLAN.
//  The landing site, the runway end and the planning mode (FULL or COARSE) are picked on ops2q's DEORB TGT page: RUN
//  DEORBIT_PLAN. opens ops2q there (its SOLVE runs this file's planner); SET DP_SELECT TO FALSE. before it plans here
//  with no page, from DP_SITE (the runway AUTO, FULL). The planner then chooses the runway, the aim point, the entry angle at
//  the 80 km interface and the burn (time and dv; a pure retrograde burn, no maneuver node), and writes them
//  to the plan file (planWrite, lib_plan.ks). Next run SHUTTLE_EXEC, which flies the burn from that file,
//  then FAM_BUILD and OPS3Q for the entry. They are separate processes with no shared script state, so the entry
//  reads the planner's choices (runway, aim point, entry angle) from the file.
//  Reads hud/hud_runways.txt. Writes the plan file, logs/plan_<UT>_log.txt and logs/deorbit_solve.csv.
//  The progress page and the log show each step. A burn solve takes from about 5 s to over a minute, depending on scene load.
//  Method: the burn time comes from orbit geometry with no entry integration; the entry is integrated
//  about twice per solve (see GEOMETRIC BURN-TIME SOLVE).

RUNONCEPATH("0:/lib/lib_progreset.ks").  IF NOT (DEFINED DP_NO_RUN) { progReset(). } ELSE IF NOT DP_NO_RUN { progReset(). }   // No hook of an earlier program outlives it (lib_progreset); NOT when loaded as a library (DP_NO_RUN TRUE: ops2q / ops3q load it for a solve): progReset would wipe the host's handlers, sinks and hooks
SET CONFIG:IPU TO 10000.                          // the patched kOS's IPU ceiling; set before the libraries load
SET TERMINAL:WIDTH TO 50.                         // kOS's default; the banners are laid out on 50 columns
RUNONCEPATH("0:/lib/entry_predict.ks").
eprMassTrack().                                   // the entry prediction at this vehicle's mass (the burn's propellant still aboard)
RUNONCEPATH("0:/lib/lib_kepler.ks").
RUNONCEPATH("0:/lib/lib_plan.ks").
RUNONCEPATH("0:/lib/prog_display.ks").
RUNONCEPATH("0:/lib/lib_guistyle.ks").   // the GUI look (prog_display's window loads it too)
RUNONCEPATH("0:/lib/lib_logsw.ks").      // SOCK_LOG: the logs on or off (0:/logging.txt)
RUNONCEPATH("0:/lib/lib_dpcs.ks").       // the solve on the KAL/S coprocessor (DP_CS)
RUNONCEPATH("0:/lib/lib_cape.ks").       // the SLF where the Katniss Cape is (capeLine)

// --- what to aim for -------------------------------------------------------
// ---- ENTRY ANGLE: SCHEDULED, NOT CONSTANT --------------------------------------------------
// A constant -1.0 deg skips off this airframe: in equilibrium glide the drag on a given trajectory falls as L/D rises, so
// a shallow entry loses too little speed on its first pass and climbs back out before it captures. The entry angle is
// therefore scheduled from the orbit altitude: the skip boundary (the shallowest angle that still captures, wings level)
// is linear in the circular orbit altitude, and the plan flies DP_FPA_MARGIN steeper than it. The orbiter schedules
// gamma against velocity (C1/V + C2); that does not fit here, because the interface is at 80 km and the orbit is what
// changes. 2.19 gives the same reason: a faster entry needs a steeper flight path angle at EI.
GLOBAL DP_FPA_SLOPE  IS -0.000009445687.  // deg per metre of orbit altitude
GLOBAL DP_FPA_ICPT   IS 0.6554.           // deg
GLOBAL DP_FPA_MARGIN IS 0.75.             // deg steeper than the skip boundary; larger = more propellant and less crossrange

// Scheduled entry flight path angle (deg) for a circular orbit at altitude altM (m).
FUNCTION dpFpaForOrbit {
    PARAMETER altM.
    RETURN DP_FPA_SLOPE * altM + DP_FPA_ICPT - DP_FPA_MARGIN.
}

GLOBAL DP_PROG IS FALSE.        // TRUE once the progress page is up
GLOBAL DP_RUN_T0 IS 0.          // TIME:SECONDS when the run's page opened (dpRun): the T readout, the log's clock
GLOBAL DP_COAST_S IS 0.         // s from the burn to the interface on this orbit (dpCoastTime): the pass lines
GLOBAL DP_NSOLVE IS 0.          // burn solves so far this run: the FULL list's # column
GLOBAL DP_FPA IS -1.0.          // deg: the entry angle, set at run time from dpFpaForOrbit(); this value is a placeholder
GLOBAL DP_RUNWAY IS "auto".     // "auto" | one end of DP_SITE ("SLF15", "SLF33", ...): offers only that end (no box)
// The planner offers the two ends of one site, read from hud/hud_runways.txt (the table lib_hud draws), each with
// its landing heading and its short-field aim shift for the FTP law. The site is kept across runs:
// SET DP_SITE TO "EAFB". then RUN DEORBIT_PLAN.
IF NOT (DEFINED DP_SITE) { GLOBAL DP_SITE IS "SLF". }   // "SLF" | "EAFB" | "VBG" (an ELS plans too, contingency only)
GLOBAL DP_RWY_FILE IS "0:/hud/hud_runways.txt".
GLOBAL DP_BOX_TURN IS 270.      // deg: THE RUNWAY BOX: a plan whose HAC turn (360 - the
                                // approach angle) reaches this is re-made for the other end (kept if that one fails)
// The two ends' turns sum to 540 (360 - theta and 180 + theta), so past 270 the other end turns less: AUTO flies the
// lower HAC turn.
GLOBAL DP_TURN_WARN IS 315.     // deg: the selection box flags a turn from here (the GO CSS alert's: the workbook's over-bank)
GLOBAL DP_REV_MAX_TRIES IS 4.   // passes one run may try: the nearest, then one per NEXT PASS
GLOBAL DP_AZ_MAX IS 45.         // deg: the plan check's interface azimuth error to the aim
GLOBAL DP_EI_TO_PASS_S IS 850.  // s from the interface to the pass; DP_SEED_LEAD_S is derived from it
GLOBAL DP_GEO_PE_NOM IS 40000.  // m: the periapsis dpCoastTime assumes
GLOBAL DP_GEO_EI_ALT IS 80000.  // m: the interface altitude dpCoastTime ends at
GLOBAL DP_BACK_M IS KEP_FTP_RANGE_NM * KEP_NM_M.   // m: THIS aim's distance from its threshold (the FTP law's range),
                                // the side gate's target; the planner sets it per candidate
GLOBAL DP_FTP_ALIGN IS TRUE.    // TRUE = the arrival-aligned FTP; FALSE = the ground-track placement
GLOBAL DP_FTP_ARRIVAL_K IS 2.74. // the entry's overbank on the interface azimuth offset
GLOBAL DP_TURN_LOSS_MAX IS 0.045. // the plan check's turn loss, a fraction of the interface range
GLOBAL DP_PLAN_ALLOW_S IS 300.  // s of planning allowed for in DP_SEED_LEAD_S (a margin: the aligned solve, the plan
                                // checks and a runway-box re-plan all run before the plan is written)
GLOBAL DP_PLAN_T0 IS 0.         // the plan epoch (TIME:SECONDS), for the chain's own lead check
IF NOT (DEFINED DP_SELECT) { GLOBAL DP_SELECT IS TRUE. }   // TRUE (a RUN): hand over to ops2q's DEORB TGT page, where the site, runway and
                                // mode are picked and SOLVE plans (SET DP_SELECT TO FALSE. first to plan straight from DP_SITE here)
                                // AUTO in the box (DP_RUNWAY "auto") = the crossrange choice of end + the runway box
                                //   (DP_BOX_TURN): the end with the lower HAC turn.

GLOBAL DP_BANK IS 60.           // deg at the interface: the entry predictions' constant bank (one integration, not a bank solve)

// --- solver tuning ---------------------------------------------------------
GLOBAL DP_TOL_KM IS 8.          // km: accepted residual; not tighter: the nested solvers' floor is 0.3-7.4 km
                                //   The entry guidance closes the loop, so the residual only has to start the entry unsaturated.
GLOBAL DP_ITERS IS 12.   // UNUSED (see DP_PATH_ITERS for the solve's iterations)
GLOBAL DP_GRAD_NOM IS 3.095.    // km of miss per second of burn time (130 km); UNUSED: the geometric solve needs no gradient
GLOBAL DP_GRAD_MIN IS 1.5.      // UNUSED (as DP_GRAD_NOM): bounds on a refined gradient -- a wrapped
GLOBAL DP_GRAD_MAX IS 8.        //   miss or a saturated probe produces a nonsense slope
GLOBAL DP_SCAN_STEP IS 25.      // s, for the fallback scan
GLOBAL DP_FPA_TOL IS 0.0005.    // deg: not looser (0.005 steps dv by 0.09 m/s between adjacent burn times, ~7 km of miss: no convergence)
GLOBAL DP_PATH_ITERS IS 4.      // passes that may re-measure the entry path length and re-bisect on it
                                //   The geometric solve assumes the entry arc is the same wherever the interface sits. That holds
                                //   around an equatorial orbit, not a polar one: the arc is measured against the rotating ground
                                //   and a polar entry crosses every latitude. So the path length is solved for: bisect, integrate,
                                //   and re-bisect on the arc actually flown. Each extra pass costs one integration; the scan and
                                //   the bisection cost none.
// The leg gate (dpGeoErr) accepts a burn only if its interface falls inside this window around the seed, the pass time
// dpPlanChain picked (on every orbit, equatorial too): DP_LEG_LO before it, DP_LEG_HI after it, as fractions of the
// orbital period. The interface sits one entry
// path length back from the aim (2269-2369 km of ground track, ~644 s, 0.226 of a period). A range-only scan returns five
// candidates, at -0.226 (right), -0.726 and +0.274 (the opposite leg), -1.226 and +0.774 (the right leg, one rev out); the
// window (-0.5, +0.10] admits only the first, so it pins the rev as well as the leg. The 0.226 is for a circular orbit and
// moves on an eccentric one. Re-derive the window if the entry angle schedule or the entry path length changes.
GLOBAL DP_LEG_LO IS 0.5.        // fraction of the orbital period before the seeded crossing
GLOBAL DP_LEG_HI IS 0.10.       // fraction of the orbital period after it
// How many candidates each gate rejected in the last solve (the leg gate, the side gate). They are globals because dpGeoErr
// returns one number; they tell "the aim is unreachable" from "every candidate was on the wrong leg or side" (opposite problems).
GLOBAL DP_NGATE_LEG IS 0.       // the leg gate
GLOBAL DP_NGATE_SIDE IS 0.      // the side gate
GLOBAL DP_SIDE_TOL_M IS 25000.  // m: tolerance of the backset test (see dpGeoErr): a SIDE test, not a precision test
                                //   The handover point must sit one FTP backset short of the threshold, measured from the interface;
                                //   a burn solved for the wrong pass puts the aim the same distance on the OTHER side, so pass and fail
                                //   are twice the backset apart. Not a tuned number: the identity drifts only 0.5-1.5 km at 300 km of
                                //   crossrange, and anything from 10 to 60 km behaves identically.
GLOBAL DP_INT_BUDGET IS 400.    // RK2 steps per tick while predicting (the entry loop uses 25; nothing else competes here)


// ---------------------------------------------------------------------------
//  Analytic state propagation, position AND velocity
// ---------------------------------------------------------------------------
//  kepAt gives position only. This returns position and velocity from the f and g functions and their derivatives,
//  which need no inclination, node or argument of periapsis because the state vector carries them.
FUNCTION dpStateAt {                        // the PARKING orbit's state (el = the vehicle's elements)
    PARAMETER el, t.
    IF EPR_J2_ON AND t >= 0 {               // Sol: the J2 ephemeris (lib_kepler kepEphAt), as kepAt
        LOCAL ep IS kepEphAt(el, t).
        RETURN LIST(ep[0], ep[1], t).
    }
    RETURN dpStateAtKep(el, t).
}

// The closed-form Kepler state: for a POST-BURN orbit, whose elements differ on every call -- dpStateAt's J2 branch would
// build (and throw away) an ephemeris for each of them.
FUNCTION dpStateAtKep {
    PARAMETER el, t.
    LOCAL ecc IS el["ecc"].
    LOCAL sma IS el["sma"].
    LOCAL m0R IS el["ea0R"] - ecc * SIN(el["ea0R"] * CONSTANT:RADTODEG).
    LOCAL mR IS m0R + el["n"] * t.
    LOCAL eaR IS mR.
    IF ecc >= 0.8 { SET eaR TO CONSTANT:PI. }
    LOCAL i IS 0.
    UNTIL i >= 30 {
        SET i TO i + 1.
        LOCAL eaD IS eaR * CONSTANT:RADTODEG.
        LOCAL f IS eaR - ecc * SIN(eaD) - mR.
        LOCAL fp IS 1 - ecc * COS(eaD).
        IF ABS(fp) < 0.00000000000001 { BREAK. }
        LOCAL d IS f / fp.
        SET eaR TO eaR - d.
        IF ABS(d) < 0.0000000000001 { BREAK. }
    }
    RETURN dpFgAt(el, eaR, t).
}

// f and g series for a given eccentric anomaly. Split out so the interface solve can reuse it
// without re-solving Kepler's equation for a time it already knows the anomaly for.
FUNCTION dpFgAt {
    PARAMETER el, eaR, t.
    LOCAL sma IS el["sma"].
    LOCAL deaR IS eaR - el["ea0R"].
    LOCAL deaD IS deaR * CONSTANT:RADTODEG.
    LOCAL ff IS 1 - sma / el["rm0"] * (1 - COS(deaD)).
    LOCAL gg IS t + (SIN(deaD) - deaR) / el["n"].
    LOCAL rv IS el["r0"] * ff + el["v0"] * gg.
    LOCAL rm IS rv:MAG.
    LOCAL fd IS 0 - SQRT(EPR_MU * sma) / (el["rm0"] * rm) * SIN(deaD).
    LOCAL gd IS 1 - sma / rm * (1 - COS(deaD)).
    RETURN LIST(rv, el["r0"] * fd + el["v0"] * gd, t).
}

// Time and state at r = R + ATM (the interface), solved rather than stepped. Returns LIST(r, v, t), or 0 if the orbit
// never reaches the interface.
// The dv-for-FPA search (dpFpaForDv, ~20-30 interfaces per probe) uses the closed form, dpInterfaceKep: a J2 coast on every
// dv probe would run the vehicle's electric charge flat before the first step finishes. The geometry probes (dpGeoErr) and
// the verify (dpMissAt) coast under J2 here, one coast per probe and only after the closed form says there is an interface.
// The geometry cannot be Kepler: with a Kepler geometry and a J2 verify the solve stalls, because at the ~1.2 deg entry angle
// a ~1 km J2 height difference moves the interface crossing ~50x that along track. So the dv comes from the closed-form
// angle, and the J2 coast flies an angle a few hundredths of a degree away from it.
FUNCTION dpInterface {
    PARAMETER rv, vv.
    IF EPR_J2_ON {                          // Sol: the coast under J2 (eprJ2ToEI, RK4 at 30 s)
        IF dpInterfaceKep(rv, vv) = 0 { RETURN 0. }
        LOCAL got IS eprJ2ToEI(rv, vv).
        IF got[2] < 0 { RETURN 0. }
        RETURN got.
    }
    RETURN dpInterfaceKep(rv, vv).
}

FUNCTION dpInterfaceKep {                   // the closed-form interface (Kepler), LIST(r, v, t) or 0
    PARAMETER rv, vv.
    LOCAL el IS kepElements(rv, vv).
    IF el = 0 { RETURN 0. }
    LOCAL sma IS el["sma"].
    LOCAL ecc IS el["ecc"].
    LOCAL rEi IS EPR_R + EPR_ATM.
    IF sma * (1 - ecc) > rEi { RETURN 0. }      // periapsis outside the interface
    IF sma * (1 + ecc) < rEi { RETURN 0. }      // apoapsis inside it
    // r = a(1 - e cos E) inverted for E. ARCCOS is in DEGREES; convert before Kepler.
    LOCAL ce IS (1 - rEi / sma) / MAX(ecc, 0.000000000001).
    LOCAL eaiR IS ARCCOS(MAX(-1, MIN(1, ce))) * CONSTANT:DEGTORAD.
    LOCAL m0R IS el["ea0R"] - ecc * SIN(el["ea0R"] * CONSTANT:RADTODEG).
    LOCAL period IS el["period"].
    // two solutions, +/-E. Take whichever gives the SOONEST positive time ahead: the descending branch is the one wanted,
    // and the other is a full orbit away.
    LOCAL bestT IS -1.
    LOCAL bestE IS 0.
    FOR sgn IN LIST(-1, 1) {
        LOCAL candR IS sgn * eaiR.
        LOCAL miR IS candR - ecc * SIN(candR * CONSTANT:RADTODEG).
        LOCAL dt IS (miR - m0R) / el["n"].
        UNTIL dt >= 0 { SET dt TO dt + period. }
        IF bestT < 0 OR dt < bestT {
            SET bestT TO dt.
            SET bestE TO candR.
        }
    }
    IF bestT < 0 { RETURN 0. }
    // RE-SOLVE for the time; do NOT pass bestE into dpFgAt. ARCCOS returns an anomaly in -pi..pi, but the anomaly consistent
    // with bestT can be a full 2*pi away. The f function (COS) is 2*pi-periodic and does not care; g has a linear -dea term
    // and would be off by 2*pi/n, one orbital period.
    RETURN dpStateAtKep(el, bestT).
}

// Flight path angle, degrees, negative descending. SURFACE-RELATIVE, not inertial: the entry condition that governs heating
// and the guidance's authority is the angle relative to the air. ATAN2 of the vertical component over the horizontal
// magnitude, not ARCSIN against the full speed.
FUNCTION dpFpa {
    PARAMETER rv, vv.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    IF vrelv:MAG < 1 { RETURN 0. }
    LOCAL upv IS rv:NORMALIZED.
    LOCAL vvert IS VDOT(vrelv, upv).
    LOCAL vhoriz IS SQRT(MAX(vrelv:MAG * vrelv:MAG - vvert * vvert, 0)).
    RETURN ARCTAN2(vvert, vhoriz).
}

// ---------------------------------------------------------------------------
//  dv for a target entry angle
// ---------------------------------------------------------------------------
//  The burn state is computed once and passed in, not recomputed inside every bisection step.
FUNCTION dpDvForFpa {
    PARAMETER rb, vb, fpaTarget.
    LOCAL lo IS 20.
    LOCAL hi IS 400.
    LOCAL fLo IS dpFpaForDv(rb, vb, lo).
    LOCAL loBad IS -1.
    LOCAL tries IS 0.
    UNTIL NOT (fLo = 999) OR lo >= hi OR tries >= 60 {
        SET loBad TO lo.
        SET lo TO lo + 5.
        SET fLo TO dpFpaForDv(rb, vb, lo).
        SET tries TO tries + 1.
    }
    IF fLo = 999 { RETURN 0. }
    // Bisect the reach boundary (the minimum dv that reaches the interface): stepping up in 5 m/s skips the shallow angles.
    IF loBad > 0 {
        LOCAL a IS loBad.
        LOCAL b IS lo.
        LOCAL i IS 0.
        UNTIL i >= 24 {
            SET i TO i + 1.
            LOCAL m IS 0.5 * (a + b).
            IF dpFpaForDv(rb, vb, m) = 999 { SET a TO m. } ELSE { SET b TO m. }
        }
        SET lo TO b.
        SET fLo TO dpFpaForDv(rb, vb, lo).
        IF fLo = 999 { RETURN 0. }
    }
    LOCAL fHi IS dpFpaForDv(rb, vb, hi).
    IF fHi = 999 { RETURN 0. }
    IF NOT (fHi <= fpaTarget AND fpaTarget <= fLo) { RETURN 0. }
    LOCAL i IS 0.
    UNTIL i >= 60 {
        SET i TO i + 1.
        LOCAL mid IS 0.5 * (lo + hi).
        LOCAL fm IS dpFpaForDv(rb, vb, mid).
        IF fm = 999 { RETURN 0. }
        IF ABS(fm - fpaTarget) <= DP_FPA_TOL { RETURN mid. }
        IF fm > fpaTarget { SET lo TO mid. } ELSE { SET hi TO mid. }
    }
    RETURN 0.5 * (lo + hi).
}

// The entry flight path angle (deg) for a burn of a given dv. 999 is the sentinel for "no interface": a real flight path
// angle is never positive here, so it cannot collide with a valid answer.
FUNCTION dpFpaForDv {
    PARAMETER rb, vb, dv.
    LOCAL vv IS vb - vb:NORMALIZED * dv.
    LOCAL got IS dpInterfaceKep(rb, vv).    // the closed form: this runs ~20-30 times per probe (see dpInterface)
    IF got = 0 { RETURN 999. }
    RETURN dpFpa(got[0], got[1]).
}

// ---------------------------------------------------------------------------
//  One probe: burn time -> along-track miss at a constant bank
// ---------------------------------------------------------------------------
GLOBAL DP_LAST IS 0.

FUNCTION dpMissAt {
    PARAMETER el, tBurn, aimLat, aimLng.
    LOCAL bs IS dpStateAt(el, tBurn).
    LOCAL dv IS dpDvForFpa(bs[0], bs[1], DP_FPA).
    // dv falls out of the bracket well before TIG closes; publish it at once rather than at the end.
    IF DP_PROG { progPlanVals(PG_UNSET, dv, PG_UNSET). }
    IF dv = 0 { RETURN 999999. }
    LOCAL vAfter IS bs[1] - bs[1]:NORMALIZED * dv.
    LOCAL got IS dpInterface(bs[0], vAfter).
    IF got = 0 { RETURN 999999. }
    LOCAL tRot IS tBurn + got[2].
    // The rotation epoch is a global: eprMissTo takes only (tgtLat, tgtLng) and reads the state from the integrator's
    // globals, using EPR_T0 + EPR_IT as the rotation time. eprSolveStart sets EPR_T0 to 0, which is right for a live vehicle
    // solving at the current time, and wrong here: the planner predicts from a future interface (t_burn + the coast ahead),
    // and leaving it at 0 makes the aim's ground position stale by that much (over 400 km at ~1800 s and 233 m/s of surface
    // rotation). Set it explicitly.
    SET EPR_T0 TO tRot.
    dpIntStart(got[0], got[1], tRot, DP_BANK, aimLat, aimLng).   // Sol: the entry's lateral logic, from a fresh state
    LOCAL guard IS 0.
    UNTIL eprIntRun(DP_INT_BUDGET) OR guard > 40 { SET guard TO guard + 1. }
    dpIntEnd().
    IF NOT EPR_IOK {
        SET EPR_T0 TO 0.
        RETURN 999999.
    }
    // eprMissPath, not eprMissTo: the planner predicts a constant-bank entry, which ends ~300 km to one side of the aim.
    // eprMissTo would score that crossrange, so every burn time would look ~300 km bad and no search could converge. The
    // flown entry reverses its bank and nulls that lateral offset; the planner places the DOWNRANGE only. See eprMissPath
    // in entry_predict.ks.
    LOCAL miss IS eprMissPath(got[0], aimLat, aimLng).
    SET EPR_T0 TO 0.               // restore, so a later live solve is not poisoned by this one
    SET DP_LAST TO LEXICON("tBurn", tBurn, "dv", dv, "rei", got[0], "vei", got[1],
                           "tRot", tRot, "miss", miss, "tCoast", got[2]).
    RETURN miss.
}

// ---- GEOMETRIC BURN-TIME SOLVE ---------------------------------------------------------------
//  The burn time is a geometry problem, not an integral to search. The entry angle schedule fixes the interface speed and
//  flight path angle, so every interface is essentially identical and only WHERE it sits changes. One entry integration
//  gives the path length L; the burn time is then "when is the interface L away from the aim".
//      1. ONE entry integration -> L
//      2. scan burn phase, with no entry integration, for range(interface, aim) = L
//      3. bisect the chosen bracket, still with no entry integration
//      4. ONE entry integration to verify the residual
//  Two entry integrations in all; more only when the path length has to be re-measured (DP_PATH_ITERS). The path length is
//  nearly constant around an equatorial orbit but not around a polar one (about 5 percent, 120 km): the arc is measured
//  against the rotating ground, which moves 233 m/s at the equator and not at the poles. Against a DP_TOL_KM of 8, one
//  measurement can never converge on a polar orbit, so the path length is solved for (step 1 probes where the gates accept).
//  No gradient search is safe on this residual: over one period it is a sawtooth with two real sign changes, because
//  the interface passes the aim once per orbit, so two burn times reach it.
// THE COARSE DEORBIT: faster and less precise, for an entry guidance that absorbs the difference. OFF by default (the full
// planner is the default); the selection box sets it per run. ON: the burn solve does no entry simulation. The entry is
// assumed to fly a stored distance D_ENT from the interface (DP_COARSE_DENT: typical distances of full plans, by the
// parking orbit's mean altitude, sma - R), and the same solve places the interface D_ENT from the aim.
GLOBAL DP_COARSE_ON IS FALSE.
GLOBAL DP_COARSE_DENT IS LIST(LIST(150, 2740.0), LIST(200, 2607.9), LIST(250, 2375.4), LIST(300, 2210.6)).  // (parking altitude km, D_ENT km)

FUNCTION dpCoarseDent {                     // D_ENT (m) for the parking orbit el, by its mean altitude (sma - R)
    PARAMETER el.
    LOCAL h IS (el["sma"] - BODY:RADIUS) / 1000.
    LOCAL t IS DP_COARSE_DENT.
    IF h <= t[0][0] { RETURN t[0][1] * 1000. }
    FROM { LOCAL i IS 1. } UNTIL i >= t:LENGTH STEP { SET i TO i + 1. } DO {
        IF h <= t[i][0] {
            RETURN (t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (h - t[i - 1][0]) / (t[i][0] - t[i - 1][0])) * 1000.
        }
    }
    RETURN t[t:LENGTH - 1][1] * 1000.
}

FUNCTION dpCoarseAt {                      // dpMissAt with no entry integration: the entry is assumed to fly pathL
    PARAMETER el, tBurn, aimLat, aimLng, pathL.
    LOCAL bs IS dpStateAt(el, tBurn).
    LOCAL dv IS dpDvForFpa(bs[0], bs[1], DP_FPA).
    IF DP_PROG { progPlanVals(PG_UNSET, dv, PG_UNSET). }
    IF dv = 0 { RETURN 999999. }
    LOCAL vAfter IS bs[1] - bs[1]:NORMALIZED * dv.
    LOCAL got IS dpInterface(bs[0], vAfter).
    IF got = 0 { RETURN 999999. }
    LOCAL tRot IS tBurn + got[2].
    LOCAL g0 IS eprToGeoInertial(got[0], tRot).    // the interface on the ground at its own time, as eprMissPath
    SET EPR_MP_LAT TO g0[0].
    SET EPR_MP_LNG TO g0[1].
    SET EPR_MP_TROT TO tRot.
    SET EPR_MP_GC TO eprGcDist(g0[0], g0[1], aimLat, aimLng).
    SET EPR_IARC TO pathL.                          // what the solve's trace and its path test read
    LOCAL miss IS pathL - EPR_MP_GC.
    SET DP_LAST TO LEXICON("tBurn", tBurn, "dv", dv, "rei", got[0], "vei", got[1],
                           "tRot", tRot, "miss", miss, "tCoast", got[2]).
    RETURN miss.
}

// THE SOLVE ON THE KAL/S COPROCESSOR (lib_dpcs.ks). DP_CS (TRUE) = the C# solve, the same arithmetic as dpSolveBurnKos bit
// for bit; kOS's page, trace file and globals are then replayed from its result. On ANY failure kOS solves itself
// (dpSolveBurnKos) and does for the rest of the run: the log says "DEORBIT SOLVE: KOS (<why>)".
FUNCTION dpSolveBurn {
    PARAMETER el, aimLat, aimLng, tSeed, thrLat, thrLng.
    IF NOT DP_CS { RETURN dpSolveBurnKos(el, aimLat, aimLng, tSeed, thrLat, thrLng). }
    LOCAL jr IS dpcs_run("solve", dpcs_in_solve(el, aimLat, aimLng, tSeed, thrLat, thrLng)).
    IF jr:ISTYPE("String") {
        dpcs_kos(jr).
        RETURN dpSolveBurnKos(el, aimLat, aimLng, tSeed, thrLat, thrLng).
    }
    // the C# solve's line: in the page's log file only, not on the screen
    IF pgLogFile:LENGTH > 0 {
        LOG ("" + ROUND(TIME:SECONDS - pgLogT0) + " S"):PADLEFT(6) + "  DEORBIT SOLVE IN C#: " + ROUND(jr["ms"], 1) + " MS, "
            + jr["threads"] + " THREAD(S)" TO pgLogFile.
    }
    RETURN dpcs_apply_solve(jr, tSeed).
}

// The geometric burn-time solve (the steps listed above) for the parking orbit el and the aim. tSeed seeds the scan;
// thrLat / thrLng is the runway threshold. kOS's own (dpSolveBurn above hands it to the C# first).
FUNCTION dpSolveBurnKos {
    PARAMETER el, aimLat, aimLng, tSeed, thrLat, thrLng.
    // The page advances only between steps (dpRun opens it): dpSolveBurn does not yield, so nothing repaints mid-step.
    SET DP_NGATE_LEG TO 0.
    SET DP_NGATE_SIDE TO 0.
    // No flag gates this page: a kOS global outlives the script that set it, and progInit reports its own refusals.
    // One progress window per planner run, opened by dpRun (progInit builds a GUI on every call and rescales PG_FONT in
    // place, which compounds). Each solve starts the bar again; its line in the list is dpSolveRow's. The entry angle is a
    // target the planner holds before it bisects, so it is shown at once.
    IF DP_PROG {
        progPlanSolve().
        progPlanVals(DP_FPA, PG_UNSET, PG_UNSET).
    }
    LOCAL period IS el["period"].
    LOCAL tMin IS DP_SCAN_STEP.
    LOCAL tMax IS 1.5 * period.
    IF tSeed > 0 {                    // always: every caller seeds with a pass time (the 1.5-period window is unused)
        // The scan window is the leg, not +/- 1.2 periods (which holds five range crossings). The interface has to arrive on
        // the half-period leading into the crossing, so the burn sits one coast before that: 1500 s of slack on the low end covers
        // the coast (~770 s). dpGeoErr rejects anything outside the leg anyway, so a wide window costs a few free probes,
        // and a narrow one would miss the answer.
        SET tMin TO MAX(DP_SCAN_STEP, tSeed - 0.5 * period - 1500).
        SET tMax TO tSeed.
    }
    LOCAL trace IS LIST().

    // ---- STEP 1: one integration for the path length --------------------------------------
    //  Probe where the gates accept, not just anywhere an interface exists: a probe on the wrong side of the field measures a
    //  path length the solution never flies (see DP_PATH_ITERS). Finding an acceptable burn time first costs no entry
    //  integration (dpGeoErr), and it guarantees that the one integration here is spent on the right geometry.
    //  pathL is passed as 0 because only the sentinel matters: the returned range is ignored.
    LOCAL tProbe IS -1.
    LOCAL tp IS tMin.
    UNTIL tp > tMax OR tProbe > 0 {
        IF dpGeoErr(el, tp, aimLat, aimLng, 0, thrLat, thrLng, tSeed, period) < 999998 {
            SET tProbe TO tp.
        }
        SET tp TO tp + DP_GEO_STEP.
    }
    IF tProbe < 0 {
        dpWriteTrace(trace, tMin, tMax, tSeed, period,
                     "no burn time on this leg reaches the interface on the correct side -- "
                     + DP_NGATE_LEG + " gated on the leg, " + DP_NGATE_SIDE + " on the aim side").
        RETURN 0.
    }
    LOCAL m0 IS 0.
    IF DP_COARSE_ON { SET m0 TO dpCoarseAt(el, tProbe, aimLat, aimLng, dpCoarseDent(el)). }
    ELSE { SET m0 TO dpMissAt(el, tProbe, aimLat, aimLng). }
    IF m0 > 999998 {
        dpWriteTrace(trace, tMin, tMax, tSeed, period,
                     "the gated probe at " + ROUND(tProbe, 1) + " s found no interface").
        RETURN 0.
    }
    LOCAL pathL IS EPR_IARC.
    trace:ADD(dpTraceRow(1, tProbe, m0 / 1000, pathL / 1000, (CHOOSE "step 1: path length from the coarse table" IF DP_COARSE_ON ELSE "step 1: path length"), thrLat, thrLng)).
    // The trace rows ARE the solve steps, so the display advances with them.
    IF DP_PROG { progPlanStep(1, m0 / 1000, TIME:SECONDS - DP_RUN_T0). }

    // ==========================================================================================
    //  STEPS 2-4, ITERATED ON THE PATH LENGTH
    // ==========================================================================================
    //  Scan, bisect, integrate -- and if the arc actually flown disagrees with the one the scan was given, do it again on the
    //  flown value (see DP_PATH_ITERS). Only the integration costs anything.
    LOCAL out IS 0.
    LOCAL mFinal IS 0.
    LOCAL tSol IS 0.
    LOCAL nInt IS (CHOOSE 0 IF DP_COARSE_ON ELSE 1).   // entry integrations: none in the coarse mode
    LOCAL pIt IS 0.
    UNTIL pIt >= DP_PATH_ITERS {
        SET pIt TO pIt + 1.

    // ---- STEP 2: scan for range(interface, aim) = pathL, with no entry integration ---------
    //  dpGeoErr does no entry integration, so ~70 probes cost less than one entry.
    LOCAL brackets IS LIST().
    LOCAL prevT IS -1.
    LOCAL prevF IS 0.
    LOCAL ts IS tMin.
    UNTIL ts > tMax {
        LOCAL fv IS dpGeoErr(el, ts, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period).
        IF fv > 999998 {
            SET prevT TO -1.
        } ELSE {
            IF prevT >= 0 AND prevF * fv < 0 { brackets:ADD(LIST(prevT, ts)). }
            SET prevT TO ts. SET prevF TO fv.
        }
        SET ts TO ts + DP_GEO_STEP.
    }
    trace:ADD(dpTraceRow(2, 0, 0, brackets:LENGTH,
                         "step 2 pass " + pIt + ": kepler scan on path " + ROUND(pathL / 1000, 2)
                         + " km, " + brackets:LENGTH + " bracket(s), gated "
                         + DP_NGATE_LEG + " leg / " + DP_NGATE_SIDE + " side",
                         thrLat, thrLng)).
    IF DP_PROG { progPlanStep(2, 0, TIME:SECONDS - DP_RUN_T0). }
    IF brackets:LENGTH = 0 {
        // An empty bracket list has two different causes, told apart by the gate counters: no candidate at the right range,
        // or candidates that were all on the wrong leg or the wrong side of the field.
        dpWriteTrace(trace, tMin, tMax, tSeed, period,
                     "no crossing found -- " + DP_NGATE_LEG + " candidates gated on the leg, "
                     + DP_NGATE_SIDE + " on the aim side; "
                     + (CHOOSE "the aim is unreachable from any phase on this pass"
                        IF DP_NGATE_LEG + DP_NGATE_SIDE = 0
                        ELSE "the pass geometry and the aim disagree")).
        // A failed later pass must not discard the solution of a previous pass: re-solving on a corrected path length can land
        // on a length no bracket matches, which stops the iteration but keeps the solution already produced.
        IF NOT (out = 0) { BREAK. }
        RETURN 0.
    }

    // ---- STEP 3: pick the EARLIEST bracket that still clears the lead-time gate ------------
    //  Both crossings are valid solutions. Taking the LATER one wastes up to a full orbit of
    //  waiting; taking the earliest blindly can land inside DP_MIN_LEAD_S and be rejected by the
    //  gate downstream, which is a wasted plan either way.
    LOCAL chosen IS brackets[brackets:LENGTH - 1].
    LOCAL bi IS 0.
    UNTIL bi >= brackets:LENGTH {
        IF brackets[bi][0] >= DP_MIN_LEAD_S {
            SET chosen TO brackets[bi].
            BREAK.
        }
        SET bi TO bi + 1.
    }
    LOCAL lo IS chosen[0].
    LOCAL hi IS chosen[1].
    LOCAL fLo IS dpGeoErr(el, lo, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period).
    LOCAL bj IS 0.
    UNTIL bj >= 24 {
        SET bj TO bj + 1.
        LOCAL mid IS 0.5 * (lo + hi).
        LOCAL fm IS dpGeoErr(el, mid, aimLat, aimLng, pathL, thrLat, thrLng, tSeed, period).
        IF fm > 999998 { BREAK. }
        IF fm * fLo > 0 { SET lo TO mid. SET fLo TO fm. } ELSE { SET hi TO mid. }
    }
    SET tSol TO 0.5 * (lo + hi).
    trace:ADD(dpTraceRow(3, tSol, 0, 0, "step 3 pass " + pIt + ": bisected geometry",
                         thrLat, thrLng)).
    IF DP_PROG { progPlanStep(3, 0, TIME:SECONDS - DP_RUN_T0). }

    // ---- STEP 4: one integration to verify -------------------------------------------------
    //  Into a temporary first, so mFinal and out only hold values from a pass that completed (breaking out on a failed later
    //  pass would otherwise leave the sentinel 999999 in mFinal).
    LOCAL mTry IS 0.
    IF DP_COARSE_ON { SET mTry TO dpCoarseAt(el, tSol, aimLat, aimLng, pathL). }
    ELSE { SET mTry TO dpMissAt(el, tSol, aimLat, aimLng). }
    IF mTry > 999998 {
        IF NOT (out = 0) { BREAK. }
        dpWriteTrace(trace, tMin, tMax, tSeed, period, "verify probe found no interface").
        RETURN 0.
    }
    SET mFinal TO mTry.
    SET out TO DP_LAST:COPY.
    IF NOT DP_COARSE_ON { SET nInt TO nInt + 1. }
    trace:ADD(dpTraceRow(4, tSol, mFinal / 1000, EPR_IARC / 1000,
                         "step 4 pass " + pIt + ": verify, flew " + ROUND(EPR_IARC / 1000, 2)
                         + " km against " + ROUND(pathL / 1000, 2) + " assumed",
                         thrLat, thrLng)).
    IF DP_PROG { progPlanStep(4, mFinal / 1000, TIME:SECONDS - DP_RUN_T0). }

    // ---- CONVERGED, OR RE-SOLVE ON THE ARC ACTUALLY FLOWN ---------------------------------
    //  The residual is the disagreement between the path length the scan was given and the one the entry flew, so feeding the
    //  flown value back converges on the length the entry really flies. Successive solutions share a geometry, so the second measurement is
    //  usually already right.
    IF ABS(mFinal) <= DP_TOL_KM * 1000 { BREAK. }
    IF ABS(EPR_IARC - pathL) < 500 { BREAK. }   // path settled but the miss did not: no more to win
    SET pathL TO EPR_IARC.
    }

    IF out = 0 {
        dpWriteTrace(trace, tMin, tMax, tSeed, period, "no solution after " + pIt + " pass(es)").
        RETURN 0.
    }
    dpWriteTrace(trace, tMin, tMax, tSeed, period,
                 "residual " + ROUND(mFinal / 1000, 2) + " km after " + pIt + " pass(es), "
                 + nInt + " integration(s)").
    out:ADD("probes", nInt).
    out:ADD("iters", pIt).
    out:ADD("converged", ABS(mFinal / 1000) <= DP_TOL_KM).
    out:ADD("grad", 0).
    // ---- THE SIDE ASSERT, ON THE INTEGRATED SOLUTION -------------------------------------
    //  dpGeoErr already enforced this on every candidate, so it holds by construction. It is re-stated on the answer that is
    //  written because neither the residual gate nor the lead-time gate can see a wrong-side aim. Cheap, and it fails loudly.
    LOCAL gEi IS eprToGeoInertial(out["rei"], out["tRot"]).
    LOCAL bkM IS dpBackset(gEi, aimLat, aimLng, thrLat, thrLng).
    out:ADD("backsetKm", bkM / 1000).
    out:ADD("sideOk", ABS(bkM - DP_BACK_M) <= DP_SIDE_TOL_M).
    RETURN out.
}

// One trace row (twelve fields), built here so that every row reads the same four EPR_MP_* values.
// term_lat / term_lng are where the entry ENDED: the one number that shows at a glance a plan that misses by a long way
// (eprMissPath publishes it as EPR_SOL_LAT / LNG on every probe).
FUNCTION dpTraceRow {
    PARAMETER st, tb, missKm, pathKm, why, thrLat, thrLng.
    RETURN LIST(st, tb, missKm, pathKm, why,
                EPR_MP_LAT, EPR_MP_LNG, EPR_MP_TROT, EPR_MP_GC / 1000,
                EPR_SOL_LAT, EPR_SOL_LNG,
                (eprGcDist(EPR_MP_LAT, EPR_MP_LNG, thrLat, thrLng) - EPR_MP_GC) / 1000).
}

// Ground-range error between the interface and the aim, positive when the interface is CLOSER to the aim than the entry can
// fly, i.e. the burn is too late. No entry integration here: the scan and the bisection call it ~90 times.
// A range match is not a solution. The points at range L from the aim form a circle, and the aim sits one FTP length back
// along one particular pass's ground track, so only burns that approach down THAT pass can use THAT aim. A range-only
// check scores a burn solved for the wrong pass as converged, so two gates reject it:
//   THE BACKSET TEST (all orbits). The handover point is built one FTP backset short of the threshold, back along the
//   track, so on any approach that can use it, it lies between the interface and the runway:
//        gc(interface, threshold) - gc(interface, aim)  ==  +KEP_FTP_RANGE_NM * KEP_NM_M     (DP_BACK_M)
//   A correct burn reads +83.34 km and a wrong-pass burn about minus that (-82.79), at an FTP range of 45 nm. The expected
//   backset scales with the range (59.86 km at 32.32 nm), so this is a sign test: DP_SIDE_TOL_M separates the two cases
//   with room.
//   THE LEG GATE. The pass dpPlanChain picked is the single authority on WHICH pass, because it is the only thing that
//   has checked crossrange. The interface must arrive on the half-period leading into that pass time (tCross, the
//   seed; the DP_LEG_LO / DP_LEG_HI window), on every orbit: every caller passes a pass time, so tCross > 0 and the gate
//   always runs (tCross <= 0 would turn it off and leave the backset test on its own).
FUNCTION dpGeoErr {
    PARAMETER el, tBurn, aimLat, aimLng, pathL, thrLat, thrLng, tCross, perS.
    LOCAL bs IS dpStateAt(el, tBurn).
    LOCAL dv IS dpDvForFpa(bs[0], bs[1], DP_FPA).
    IF dv = 0 { RETURN 999999. }
    LOCAL vAfter IS bs[1] - bs[1]:NORMALIZED * dv.
    LOCAL got IS dpInterface(bs[0], vAfter).   // J2 on Sol, as the verify (see dpInterface)
    IF got = 0 { RETURN 999999. }
    LOCAL tRot IS tBurn + got[2].
    IF tCross > 0 AND NOT (tRot > tCross - DP_LEG_LO * perS
                           AND tRot <= tCross + DP_LEG_HI * perS) {
        SET DP_NGATE_LEG TO DP_NGATE_LEG + 1.
        RETURN 999999.
    }
    LOCAL gp IS eprToGeoInertial(got[0], tRot).            // interface: propagated
    IF ABS(dpBackset(gp, aimLat, aimLng, thrLat, thrLng) - DP_BACK_M) > DP_SIDE_TOL_M {
        SET DP_NGATE_SIDE TO DP_NGATE_SIDE + 1.
        RETURN 999999.
    }
    RETURN pathL - eprGcDist(gp[0], gp[1], aimLat, aimLng).
}

// How far SHORT of the threshold the handover point sits, measured from the interface: one FTP backset when the aim is on
// the approach side, minus one when it is beyond the field. The same number is the scan's gate, the final assert and a
// plan-file field.
FUNCTION dpBackset {
    PARAMETER gp, aimLat, aimLng, thrLat, thrLng.
    RETURN eprGcDist(gp[0], gp[1], thrLat, thrLng) - eprGcDist(gp[0], gp[1], aimLat, aimLng).
}

// The per-probe record (DP_TRACE_FILE): four rows, the ones that show a bad path length, a scan that found no bracket, or a
// verify probe that disagrees with the geometry.
FUNCTION dpWriteTrace {
    // `why`, not `note`: `note` is a kOS builtin (the voice/sound one), and a parameter that hides it is a parse error.
    PARAMETER trace, tMin, tMax, tSeed, period, why.
    IF NOT SOCK_LOG { RETURN. }   // the logs off (lib_logsw)
    IF EXISTS(DP_TRACE_FILE) { DELETEPATH(DP_TRACE_FILE). }
    // Columns: backset_km is the one to read first: gc(interface, threshold) - gc(interface, aim), about +83.34 km at an FTP
    // range of 45 nm (one FTP backset short of the runway). A negative value means the burn was solved for a different pass
    // than the aim was built for. term_lat / term_lng say where the entry actually ended. ei_lat / ei_lng / ei_trot /
    // ei_gc_km are eprMissPath's own geolocation of the interface it scored: the same physical point as the flight log's first
    // row, so a difference means the planner mislocated a position it placed correctly.
    LOG "step,t_burn_s,miss_km,path_km,ei_lat,ei_lng,ei_trot,ei_gc_km,term_lat,term_lng,"
        + "backset_km,note" TO DP_TRACE_FILE.
    LOG "# tMin " + ROUND(tMin, 1) + "  tMax " + ROUND(tMax, 1) + "  tSeed " + ROUND(tSeed, 1)
        + "  period " + ROUND(period, 1) + "  geo step " + DP_GEO_STEP
        + "  DP_TOL_KM " + DP_TOL_KM
        + "  leg " + DP_LEG_LO + "/" + DP_LEG_HI
        + "  side tol " + ROUND(DP_SIDE_TOL_M / 1000, 1) + " km"
        + "  gated " + DP_NGATE_LEG + " leg / " + DP_NGATE_SIDE + " side"
        + "  -- " + why TO DP_TRACE_FILE.
    FOR row IN trace {
        LOG row[0] + "," + ROUND(row[1], 2) + "," + ROUND(row[2], 3) + ","
            + ROUND(row[3], 2) + "," + ROUND(row[5], 6) + "," + ROUND(row[6], 6) + ","
            + ROUND(row[7], 1) + "," + ROUND(row[8], 2) + "," + ROUND(row[9], 6) + ","
            + ROUND(row[10], 6) + "," + ROUND(row[11], 2) + "," + row[4] TO DP_TRACE_FILE.
    }
}

// The plan file is written by planWrite in lib_plan.ks, which also holds the reader: both halves of the format live in one file.

// ---- THE SITE TABLE --------------------------------------------------------------------------------------------------
// The site's ends from hud/hud_runways.txt (written offline): LIST(LIST(name, lat, lng, landing heading, aim shift m),
// ...) in the file's order (sorted; a crossrange tie goes to the first), and the latitude the rev search crosses = the ends'
// mean (the pair's midpoint). The aim shift is the short-field move of the OGS aim point, -2286 - x_ogs (VBG14 426.72 m,
// VBG32 548.64 m; 0 on the long runways). Returns LIST(ends, lat) or 0.
FUNCTION dpSiteTable {
    PARAMETER site.
    IF NOT EXISTS(DP_RWY_FILE) { RETURN 0. }
    LOCAL ends IS LIST().
    LOCAL latSum IS 0.
    FOR lin IN OPEN(DP_RWY_FILE):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL w IS capeLine(lin:REPLACE(CHAR(13), "")):SPLIT(" ").     // the Cape's SLF rows
        IF w:LENGTH >= 15 {
            IF w[0] = "R" AND w[1] = site {
                LOCAL la IS w[3]:TONUMBER(0).
                ends:ADD(LIST(w[2], la, w[4]:TONUMBER(0), w[5]:TONUMBER(0), -2286 - w[12]:TONUMBER(-2286))).
                SET latSum TO latSum + la.
            }
        }
    }
    IF ends:LENGTH = 0 { RETURN 0. }
    RETURN LIST(ends, latSum / ends:LENGTH).
}

// The end called name from ths (dpSiteTable's rows); the first end when none has that name.
FUNCTION dpThreshold {
    PARAMETER ths, name.
    FOR th IN ths { IF th[0] = name { RETURN th. } }
    RETURN ths[0].
}

// The coast, s, from the burn (at the orbit's altitude) to the interface on the nominal deorbit ellipse (periapsis
// DP_GEO_PE_NOM), by Kepler's equation from the interface's true anomaly. DP_SEED_LEAD_S is derived from it.
FUNCTION dpCoastTime {
    PARAMETER altM.
    LOCAL ra IS EPR_R + altM.
    LOCAL rp IS EPR_R + DP_GEO_PE_NOM.
    LOCAL sma IS 0.5 * (ra + rp).
    LOCAL ecc IS (ra - rp) / (ra + rp).
    LOCAL rei IS EPR_R + DP_GEO_EI_ALT.
    IF ecc <= 0.000001 OR rei >= ra { RETURN 600. }
    LOCAL th IS ARCCOS(MAX(-1, MIN(1, ((sma * (1 - ecc ^ 2) / rei) - 1) / ecc))).
    LOCAL ed IS 2 * ARCTAN(SQRT((1 - ecc) / (1 + ecc)) * TAN(th / 2)).
    LOCAL m IS ed * CONSTANT:DEGTORAD - ecc * SIN(ed).
    RETURN (CONSTANT:PI - m) / SQRT(EPR_MU / sma ^ 3).
}

// On Sol, every prediction from a planned interface flies the entry's lateral logic (eprLatBank: the bank's sign by the
// azimuth error, reversals at the deadband, the minimum bank, the slew) from a fresh state (no sign yet, no reversals, bank
// and rate 0) toward the aim, with the rotation epoch at the interface. A constant one-sided bank would fly a turn the entry
// never flies. dpIntEnd drops it and restores the guidance's target.
// the guidance's target (lat, lng), saved while a prediction runs
GLOBAL DP_TGT_SAVE IS LIST(0, 0).
// Start a prediction from the interface state (rei, vei) at the given bank; on Sol it flies the lateral logic toward the aim.
FUNCTION dpIntStart {
    PARAMETER rei, vei, tRot, bank, aimLat, aimLng.
    SET EPR_LAT_ON TO EPR_PRED_LATERAL.
    eprIntStart(rei, vei, bank).
    IF EPR_LAT_ON {
        SET DP_TGT_SAVE TO LIST(EPR_TGT_LAT, EPR_TGT_LNG).
        SET EPR_TGT_LAT TO aimLat.
        SET EPR_TGT_LNG TO aimLng.
        SET EPR_LAT_TROT TO tRot.
        SET EPR_LAT_SIGN TO 0.
        SET EPR_LAT_REV TO 0.
        SET EPR_LAT_CMD TO 0.
        SET EPR_LAT_RATE TO 0.
    }
}

// End a prediction: drop the lateral logic and restore the guidance's target.
FUNCTION dpIntEnd {
    IF EPR_LAT_ON {
        SET EPR_TGT_LAT TO DP_TGT_SAVE[0].
        SET EPR_TGT_LNG TO DP_TGT_SAVE[1].
    }
    SET EPR_LAT_ON TO FALSE.
}

// One prediction from the plan's interface to TAEM at a constant bank (with the lateral logic on Sol; elsewhere the plain
// constant bank): the ground arc flown, m, or -1 when it never reaches TAEM. The end state stays in EPR_IR / EPR_IV / EPR_IT.
// The plan check's prediction on the KAL/S coprocessor (lib_dpcs.ks), as dpSolveBurn's: kOS's own (dpArcAtKos) on any failure
FUNCTION dpArcAt {
    PARAMETER sol, bank, aimLat, aimLng.
    IF NOT DP_CS { RETURN dpArcAtKos(sol, bank, aimLat, aimLng). }
    LOCAL jr IS dpcs_run("arc", dpcs_in_arc(sol, bank, aimLat, aimLng)).
    IF jr:ISTYPE("String") {
        dpcs_kos(jr).
        RETURN dpArcAtKos(sol, bank, aimLat, aimLng).
    }
    dpcs_apply_g(jr["g"]).
    RETURN jr["arc"].
}

FUNCTION dpArcAtKos {
    PARAMETER sol, bank, aimLat, aimLng.
    dpIntStart(sol["rei"], sol["vei"], sol["tRot"], bank, aimLat, aimLng).
    LOCAL guard IS 0.
    UNTIL eprIntRun(DP_INT_BUDGET) OR guard > 40 { SET guard TO guard + 1. }
    dpIntEnd().
    IF NOT EPR_IOK { RETURN -1. }
    RETURN EPR_IARC.
}

// THE PLAN CHECK: "" = flyable, else the reason; each verdict goes to the log under tag ("pass 1, aligned"), a rejection
// with its numbers.
//   - the side gate: the aim on the approach side of the threshold (the burn was solved for this pass);
//   - the interface azimuth error to the aim within DP_AZ_MAX (the side gate and this catch different failures);
//   - THE REACH: the interface range to the aim between the arcs flown at EPR_BANK_MAX (short) and EPR_BANK_MIN (long);
//   - THE TURN LOSS (Sol): flown at the preentry bank DP_BANK, the aim's along-track distance at TAEM
//     (gc(end, aim) cos(the azimuth error there)) must stay within DP_TURN_LOSS_MAX of the interface range.
// FULL: three entry predictions, about as much as one burn-solve pass. COARSE: no predictions, only the side and the heading
// checks; the entry guidance absorbs the coarse table's error.
FUNCTION dpFlyable {
    PARAMETER sol, aimLat, aimLng, tag IS "THE PLAN".
    IF NOT sol["sideOk"] {
        progLog(tag + ": REJECTED, WRONG SIDE: THE AIM IS BEYOND THE RUNWAY FOR THIS PASS", PG_YELLOW).
        RETURN "plan_side".
    }
    LOCAL az IS eprAzErrorAt(sol["rei"], sol["vei"], sol["tRot"], aimLat, aimLng).
    IF ABS(az) > DP_AZ_MAX {
        progLog(tag + ": REJECTED, HEADING: " + ROUND(ABS(az)) + " DEG OFF THE AIM, LIMIT " + DP_AZ_MAX + " DEG", PG_YELLOW).
        RETURN "plan_azimuth_" + ROUND(ABS(az)).
    }
    IF DP_COARSE_ON {
        progLog(tag + ": SIDE AND HEADING OK (" + ROUND(ABS(az), 1) + " DEG OFF THE AIM)").
        RETURN "".
    }
    LOCAL gEi IS eprToGeoInertial(sol["rei"], sol["tRot"]).
    LOCAL rng IS eprGcDist(gEi[0], gEi[1], aimLat, aimLng).
    progLog(tag + ": CHECKING REACH (2 ENTRIES) ...", PG_GREEN, FALSE).
    LOCAL longM IS dpArcAt(sol, EPR_BANK_MIN, aimLat, aimLng).
    LOCAL shortM IS dpArcAt(sol, EPR_BANK_MAX, aimLat, aimLng).
    IF longM < 0 OR shortM < 0 {
        progLogSet(tag + ": REJECTED, AN ENTRY PREDICTION FAILED (REACH)", PG_YELLOW).
        RETURN "plan_nosolution".
    }
    IF rng > longM {
        progLogSet(tag + ": REJECTED, BEYOND REACH: " + ROUND(rng / 1000) + " KM, LONGEST " + ROUND(longM / 1000) + " KM",
                   PG_YELLOW).
        RETURN "plan_beyond_reach".
    }
    IF rng < shortM {
        progLogSet(tag + ": REJECTED, INSIDE REACH: " + ROUND(rng / 1000) + " KM, SHORTEST " + ROUND(shortM / 1000) + " KM",
                   PG_YELLOW).
        RETURN "plan_inside_reach".
    }
    progLogSet(tag + ": RANGE " + ROUND(rng / 1000) + " KM, REACH " + ROUND(shortM / 1000) + " TO " + ROUND(longM / 1000)
               + " KM: OK").
    IF EPR_PRED_LATERAL {
        progLog(tag + ": CHECKING TURN LOSS (1 ENTRY) ...", PG_GREEN, FALSE).
        IF dpArcAt(sol, DP_BANK, aimLat, aimLng) < 0 {
            progLogSet(tag + ": REJECTED, AN ENTRY PREDICTION FAILED (TURN LOSS)", PG_YELLOW).
            RETURN "plan_lateral_nosolution".
        }
        LOCAL te IS sol["tRot"] + EPR_IT.
        LOCAL gEnd IS eprToGeoInertial(EPR_IR, te).
        LOCAL azE IS eprAzErrorAt(EPR_IR, EPR_IV, te, aimLat, aimLng).
        LOCAL shortE IS eprGcDist(gEnd[0], gEnd[1], aimLat, aimLng) * COS(azE).
        IF shortE > DP_TURN_LOSS_MAX * rng {
            progLogSet(tag + ": REJECTED, TURN LOSS: " + ROUND(shortE / 1000) + " KM, LIMIT "
                       + ROUND(DP_TURN_LOSS_MAX * rng / 1000) + " KM", PG_YELLOW).
            RETURN "plan_turn_loss_" + ROUND(shortE / 1000).
        }
        progLogSet(tag + ": TURN LOSS " + ROUND(shortE / 1000, 1) + " KM, LIMIT " + ROUND(DP_TURN_LOSS_MAX * rng / 1000)
                   + " KM: OK").
    }
    RETURN "".
}

// THE ARRIVAL-ALIGNED FTP BEARING: the great circle from the interface to the aim, continued through it, plus
// DP_FTP_ARRIVAL_K times the interface azimuth offset (the bearing to the aim minus the track, right +): where the entry
// actually arrives. Computed, no entry flight.
FUNCTION dpArrivalBearing {
    PARAMETER sol, aimLat, aimLng.
    LOCAL gEi IS eprToGeoInertial(sol["rei"], sol["tRot"]).
    LOCAL gcFinal IS kepBearing(aimLat, aimLng, gEi[0], gEi[1]) + 180.
    LOCAL azOff IS 0 - eprAzErrorAt(sol["rei"], sol["vei"], sol["tRot"], aimLat, aimLng).
    RETURN MOD(gcFinal + DP_FTP_ARRIVAL_K * azOff + 3600, 360).
}

// ---- THE SELECTION BOX ------------------------------------------------------------------------------------------------
// One end's next pass, as dpPlanChain finds it but WITHOUT the burn solve: the rev search for this end alone, the closest
// approach to its FTP, the track bearing there -> the predicted HAC turn (360 - the approach angle, the runway box's number,
// on the TRACK FTP: the arrival-aligned FTP moves it a few deg) and the crossrange. LEXICON(tPass, turn, crossKm) or 0.
FUNCTION dpPassPreview {
    PARAMETER el, tilt, th, siteLat, rv, vv, prev IS 0.   // T1020: prev = the earlier pass's LEXICON(tRev, tPass) (the planner's own resume state, dpPlanChain's st), 0 = the nearest pass
    LOCAL period IS el["period"].
    LOCAL tRevOut IS -1.
    LOCAL w0 IS 0.
    LOCAL w1 IS 0.
    LOCAL tb0 IS 0.
    IF tilt <= KEP_INC_TOL {
        LOCAL tSyn IS 0.
        IF VDOT(vv - eprOmegaCross(rv), eprEastNorth(rv)[0]) >= 0 { SET tSyn TO 2 * CONSTANT:PI / ABS(el["n"] - EPR_WMAG). }
        ELSE { SET tSyn TO 2 * CONSTANT:PI / (el["n"] + EPR_WMAG). }
        SET w0 TO DP_SEED_LEAD_S.
        SET w1 TO DP_SEED_LEAD_S + tSyn.
        IF prev:ISTYPE("Lexicon") { SET w0 TO prev["tPass"] + 0.5 * tSyn. SET w1 TO prev["tPass"] + 1.5 * tSyn. }   // as dpPlanChain's next pass
        SET tb0 TO w0.
    } ELSE {
        LOCAL aimScan IS siteLat.
        IF ABS(siteLat) > tilt - KEP_APEX_MARGIN {
            SET aimScan TO MAX(0, tilt - KEP_APEX_MARGIN).
            IF siteLat < 0 { SET aimScan TO 0 - aimScan. }
        }
        LOCAL rev IS 0.
        IF prev:ISTYPE("Lexicon") { SET rev TO kepFindRev(el, LIST(th), aimScan, DP_SEED_LEAD_S, prev["tRev"] + KEP_SCAN_STEP). }   // as dpPlanChain's next crossing
        ELSE { SET rev TO kepFindRev(el, LIST(th), aimScan, DP_SEED_LEAD_S). }
        IF rev = 0 { RETURN 0. }
        SET tRevOut TO rev["t"].
        SET w0 TO MAX(0, rev["t"] - 0.5 * period).
        SET w1 TO rev["t"] + 0.5 * period.
        SET tb0 TO rev["t"].
    }
    LOCAL ftp0 IS kepBuildFtp(th[1], th[2], kepTrackBearing(el, tb0), th[3], th[4]).
    LOCAL tPass IS kepPassTime(el, w0, w1, ftp0[0], ftp0[1]).
    LOCAL brng IS kepTrackBearing(el, tPass).
    LOCAL ftp IS kepBuildFtp(th[1], th[2], brng, th[3], th[4]).
    SET tPass TO kepPassTime(el, MAX(0, tPass - 2 * KEP_SCAN_STEP), tPass + 2 * KEP_SCAN_STEP, ftp[0], ftp[1]).
    LOCAL spP IS kepSubPoint(el, tPass).
    RETURN LEXICON("tPass", tPass, "turn", 360 - ABS(kepNorm180(brng - th[3])), "tRev", tRevOut,
                   "crossKm", kepCrossTrack(ftp[0], ftp[1], spP[0], spP[1], brng) / 1000).
}

// THE PLAN CHAIN: which end, the pass, the FTP, the burn -- ONE pass per call (dpRun stops when the pass fails and tries the
// next one only on NEXT PASS). st = where the search resumes: LEXICON("tRev", the last crossing or -1, "tPass", the last
// pass or -1, "n", the passes tried so far). ths = the ends offered (dpSiteTable's rows); siteLat = the latitude the rev
// search crosses. Inclined: the rev search picks the crossing and the end (smallest crossrange); the pass is the closest
// approach to that end's FTP within half a period of the crossing (kepPassTime), the FTP is rebuilt on the track bearing AT
// the pass and the pass refined +-2 steps; the burn is seeded from the pass (the interface falls ~850 s before it, inside
// the leg gate). Equatorial: the J2 rule -- the end landing closest to the direction of travel (90 prograde / 270
// retrograde) -- and a pass every synodic period. A pass before DP_SEED_LEAD_S is too soon to fly and is no candidate: the
// search moves on to the next one. Each step, check and rejection goes to the log, each burn solve to the page's list.
// Returns a LEXICON: "ok" = a plan the check accepts (converged or not: dpRun decides), "why" = this pass's reason,
// "n" = its number, "next" = the state NEXT PASS resumes from (0: no later pass), "row" = the list line of the plan taken.
FUNCTION dpPlanChain {
    PARAMETER el, tilt, ths, siteLat, rv, vv, st.
    LOCAL out IS LEXICON("ok", FALSE, "why", "", "runway", ths[0][0], "crossKm", 0, "accepted", TRUE,
                         "tPass", 0, "aimLat", 0, "aimLng", 0, "brng", 0, "theta", 0, "ftpNm", 0,
                         "thrLat", ths[0][1], "thrLng", ths[0][2], "backM", DP_BACK_M, "sol", 0, "align", "",
                         "n", st["n"] + 1, "next", 0, "row", -1).
    LOCAL period IS el["period"].
    LOCAL tRev IS -1.
    LOCAL tSyn IS 0.
    LOCAL aimScan IS siteLat.
    LOCAL tPass IS st["tPass"].
    IF tilt <= KEP_INC_TOL {
        // the direction of travel from the calibrated east vector (kOS is left-handed: no cross product here)
        LOCAL pro IS VDOT(vv - eprOmegaCross(rv), eprEastNorth(rv)[0]) >= 0.
        LOCAL want IS 270.
        IF pro { SET want TO 90. }
        LOCAL bestE IS 1000.
        FOR th IN ths {
            IF ABS(kepNorm180(th[3] - want)) < bestE {
                SET bestE TO ABS(kepNorm180(th[3] - want)).
                SET out["runway"] TO th[0].
            }
        }
        IF pro { SET tSyn TO 2 * CONSTANT:PI / ABS(el["n"] - EPR_WMAG). }
        ELSE { SET tSyn TO 2 * CONSTANT:PI / (el["n"] + EPR_WMAG). }
    } ELSE {
        // THE APEX SCAN (Sol): a site beyond the orbit's reach is scanned KEP_APEX_MARGIN inside the maximum latitude; the
        // crossrange is still measured to the FTP, and the pass time finds the true closest approach
        IF ABS(siteLat) > tilt - KEP_APEX_MARGIN {
            SET aimScan TO MAX(0, tilt - KEP_APEX_MARGIN).
            IF siteLat < 0 { SET aimScan TO 0 - aimScan. }
        }
        LOCAL rev IS 0.
        IF st["tRev"] < 0 { SET rev TO kepFindRev(el, ths, aimScan, DP_SEED_LEAD_S). }
        ELSE { SET rev TO kepFindRev(el, ths, aimScan, DP_SEED_LEAD_S, st["tRev"] + KEP_SCAN_STEP). }
        IF rev = 0 {
            SET out["why"] TO "find_rev".
            progLog("NO PASS FOUND: GROUND TRACK DOES NOT CROSS " + ROUND(aimScan, 1) + " DEG IN "
                    + (KEP_MAX_ORBITS * KEP_MAX_BATCHES) + " REVS", PG_YELLOW).
            RETURN out.
        }
        SET out["runway"] TO rev["runway"].
        SET out["accepted"] TO rev["accepted"].
        SET tRev TO rev["t"].
    }
    LOCAL th IS 0.
    LOCAL ftp IS 0.
    LOCAL brng IS 0.
    LOCAL xk IS 0.
    LOCAL skips IS 0.
    UNTIL FALSE {
        SET th TO dpThreshold(ths, out["runway"]).
        LOCAL w0 IS 0.
        LOCAL w1 IS tSyn.
        IF tRev > 0 {
            SET w0 TO MAX(0, tRev - 0.5 * period).
            SET w1 TO tRev + 0.5 * period.
        } ELSE IF tPass >= 0 {
            SET w0 TO tPass + 0.5 * tSyn.
            SET w1 TO tPass + 1.5 * tSyn.
        }
        LOCAL tb0 IS w0.
        IF tRev > 0 { SET tb0 TO tRev. }
        LOCAL ftp0 IS kepBuildFtp(th[1], th[2], kepTrackBearing(el, tb0), th[3], th[4]).
        SET tPass TO kepPassTime(el, w0, w1, ftp0[0], ftp0[1]).
        SET brng TO kepTrackBearing(el, tPass).
        SET ftp TO kepBuildFtp(th[1], th[2], brng, th[3], th[4]).
        SET tPass TO kepPassTime(el, MAX(0, tPass - 2 * KEP_SCAN_STEP), tPass + 2 * KEP_SCAN_STEP, ftp[0], ftp[1]).
        LOCAL spP IS kepSubPoint(el, tPass).
        SET xk TO kepCrossTrack(ftp[0], ftp[1], spP[0], spP[1], brng) / 1000.
        IF tPass >= DP_SEED_LEAD_S OR skips >= 2 { BREAK. }
        SET skips TO skips + 1.
        progLog("PASS IN " + ROUND(dpAhead(tPass) / 60) + " REJECTED: TOO SOON").
        IF tRev > 0 {
            LOCAL nxt IS kepFindRev(el, ths, aimScan, DP_SEED_LEAD_S, tRev + KEP_SCAN_STEP).
            IF nxt = 0 {
                SET out["why"] TO "find_rev".
                progLog("NO LATER PASS FOUND IN " + (KEP_MAX_ORBITS * KEP_MAX_BATCHES) + " REVS", PG_YELLOW).
                RETURN out.
            }
            SET out["runway"] TO nxt["runway"].
            SET out["accepted"] TO nxt["accepted"].
            SET tRev TO nxt["t"].
        }
    }
    SET out["next"] TO LEXICON("tRev", tRev, "tPass", tPass, "n", out["n"]).
    LOCAL tag IS "PASS " + out["n"].
    IF tPass < DP_SEED_LEAD_S {
        SET out["why"] TO "pass_too_soon".
        progLog(tag + ": REJECTED, TOO SOON: PASS " + ROUND(dpAhead(tPass) / 60) + " MIN AHEAD", PG_YELLOW).
        RETURN out.
    }
    progLog(tag + ": RUNWAY " + th[0] + ", BURN " + ROUND((dpAhead(tPass) - DP_COAST_S - DP_EI_TO_PASS_S) / 60)
            + " MIN AHEAD, CROSSRANGE " + ROUND(xk) + " KM" + (CHOOSE "" IF out["accepted"]
            ELSE (" (BEYOND " + ROUND(KEP_CROSS_OK_KM) + " KM LIMIT)")),
            (CHOOSE PG_GREEN IF out["accepted"] ELSE PG_YELLOW)).
    SET DP_BACK_M TO eprGcDist(th[1], th[2], ftp[0], ftp[1]).
    LOCAL rT IS dpSolveRow(el, ftp, tPass, th, out["n"], "TRACK", xk).
    LOCAL sol IS rT[0].
    LOCAL row IS rT[1].
    LOCAL fb IS brng.                   // the bearing the FTP is built on: the track, or the aligned one
    LOCAL why IS "burn_solve".
    LOCAL align IS "track".
    IF NOT (sol = 0) {
        SET why TO "unchecked".
        // THE ARRIVAL-ALIGNED FTP: the FTP re-built on the bearing the entry arrives on, re-solved from the same seed, taken
        // only if that plan passes the check
        IF DP_FTP_ALIGN {
            LOCAL beta IS dpArrivalBearing(sol, ftp[0], ftp[1]).
            LOCAL ftpA IS kepBuildFtp(th[1], th[2], beta, th[3], th[4]).
            LOCAL backTrack IS DP_BACK_M.
            SET DP_BACK_M TO eprGcDist(th[1], th[2], ftpA[0], ftpA[1]).
            LOCAL rA IS dpSolveRow(el, ftpA, tPass, th, out["n"], "ALIGNED", xk).
            LOCAL solA IS rA[0].
            IF solA = 0 {
                SET align TO "track (aligned plan unsolved)".
            } ELSE {
                LOCAL whyA IS dpFlyable(solA, ftpA[0], ftpA[1], tag + ", ALIGNED").
                IF whyA = "" {
                    SET sol TO solA.
                    SET ftp TO ftpA.
                    SET fb TO beta.
                    SET why TO "".
                    SET align TO "aligned".
                    SET row TO rA[1].
                    progRowSet(row, 4, "OK").
                } ELSE {
                    SET align TO "track (aligned plan " + whyA + ")".
                    progRowSet(rA[1], 4, dpShort(whyA), PG_YELLOW).
                }
            }
            IF NOT (why = "") {
                SET DP_BACK_M TO backTrack.
                progLog(tag + ": USING TRACK PLAN").
            }
        }
        IF NOT (why = "") {
            SET why TO dpFlyable(sol, ftp[0], ftp[1], tag + ", TRACK").
            IF why = "" { progRowSet(row, 4, "OK"). }
            ELSE { progRowSet(row, 4, dpShort(why), PG_YELLOW). }
        }
        // the lead that is left (the plan checks and the aligned solve take real time): too little = this pass fails
        IF why = "" AND dpAhead(sol["tBurn"]) < DP_MIN_LEAD_S {
            SET why TO "burn_too_soon".
            progLog(tag + ": REJECTED, BURN IS " + ROUND(dpAhead(sol["tBurn"])) + " S AHEAD, NEEDS "
                    + ROUND(DP_MIN_LEAD_S) + " S", PG_YELLOW).
            progRowSet(row, 4, "TOO SOON", PG_YELLOW).
        }
    }
    IF why = "" {
        SET out["ok"] TO TRUE.
        SET out["runway"] TO th[0].
        SET out["tPass"] TO tPass.
        SET out["aimLat"] TO ftp[0].
        SET out["aimLng"] TO ftp[1].
        SET out["brng"] TO fb.
        SET out["theta"] TO ABS(kepNorm180(fb - th[3])).
        SET out["ftpNm"] TO kepFtpRangeNm(fb, th[3], th[4]).
        SET out["crossKm"] TO xk.
        SET out["thrLat"] TO th[1].
        SET out["thrLng"] TO th[2].
        SET out["backM"] TO DP_BACK_M.
        SET out["sol"] TO sol.
        SET out["align"] TO align.
        SET out["row"] TO row.
    } ELSE {
        SET out["why"] TO why.
    }
    RETURN out.
}

// One burn solve with its line in the page's list: FULL = # / PASS / PLAN / MISS km /
// RESULT, the misses filled in by dpSolveBurn's steps; COARSE = PASS / PLAN / BURN IN / CROSS / RESULT. Its result goes to
// the log. Returns LIST(the solution or 0, the list line).
FUNCTION dpSolveRow {
    PARAMETER el, ftp, tPass, th, pn, plan, xk.
    SET DP_NSOLVE TO DP_NSOLVE + 1.
    LOCAL row IS -1.
    IF DP_COARSE_ON { SET row TO progRowAdd(LIST("" + pn, plan, "", "" + ROUND(xk) + " KM", "SOLVING")). }
    ELSE { SET row TO progRowAdd(LIST("" + DP_NSOLVE, "" + pn, plan, "", "SOLVING")). }
    LOCAL sol IS dpSolveBurn(el, ftp[0], ftp[1], tPass, th[1], th[2]).
    LOCAL tag IS "PASS " + pn + ", " + plan:TOUPPER.
    IF sol = 0 {
        progRowSet(row, 4, "NO SOLUTION", PG_YELLOW).
        progLog(tag + ": REJECTED, NO BURN SOLUTION", PG_YELLOW).
    } ELSE {
        progRowSet(row, 4, "SOLVED").
        IF DP_COARSE_ON {
            progRowSet(row, 2, "" + ROUND(dpAhead(sol["tBurn"]) / 60) + " MIN").
            progLog(tag + ": BURN SOLVED, MISS " + ROUND(sol["miss"] / 1000, 1) + " KM (COARSE, NO ENTRIES)").
        } ELSE {
            progLog(tag + ": BURN SOLVED, MISS " + ROUND(sol["miss"] / 1000, 1) + " KM (" + sol["iters"] + " ITERATION"
                    + (CHOOSE "" IF sol["iters"] = 1 ELSE "S") + ", " + sol["probes"] + " ENTRIES)").
        }
    }
    RETURN LIST(sol, row).
}

FUNCTION dpShort {                          // a check's reason, short, for the list's RESULT column
    PARAMETER why.
    IF why:STARTSWITH("plan_azimuth") { RETURN "HEADING". }
    IF why:STARTSWITH("plan_turn_loss") { RETURN "TURN LOSS". }
    IF why:CONTAINS("nosolution") { RETURN "PRED. FAILED". }
    IF why = "plan_side" { RETURN "SIDE". }
    IF why = "plan_beyond_reach" { RETURN "BEYOND REACH". }
    IF why = "plan_inside_reach" { RETURN "INSIDE REACH". }
    RETURN why:TOUPPER.
}

FUNCTION dpAhead {                          // s from the present to t, a time counted from the plan epoch DP_PLAN_T0
    PARAMETER t.
    RETURN t - (TIME:SECONDS - DP_PLAN_T0).
}

// ---- THE RUN: the page with the log under it, ONE pass at a time -- the nearest first; when it fails the planner
// STOPS with the reason in the log and tries the next pass only on NEXT PASS, at most DP_REV_MAX_TRIES passes a run --
// then the runway box, the gates and the plan. The console shows the banners only; every step is in the log: the box
// under the page and logs/plan_<UT>_log.txt. planT0 = the epoch of el, rv and vv; orbAlt = the mean altitude, m.
FUNCTION dpRun {
    PARAMETER el, tilt, site, rv, vv, planT0, orbAlt.
    SET DP_RUN_T0 TO TIME:SECONDS.
    SET DP_PLAN_T0 TO planT0.
    SET DP_CS_DOWN TO "". SET DP_CS_MS TO 0. SET DP_CS_N TO 0.   // the C# on again for this run
    SET DP_NSOLVE TO 0.
    SET DP_COAST_S TO dpCoastTime(orbAlt).
    progLogStart(logFree("0:/logs/plan_" + ROUND(planT0), "_log.txt"), DP_RUN_T0).
    SET DP_PROG TO progInit().
    IF DP_PROG {
        progShowPlan(DP_COARSE_ON).
        progPlanVals(DP_FPA, PG_UNSET, PG_UNSET).
    }
    progLog((CHOOSE "COARSE" IF DP_COARSE_ON ELSE "FULL") + " PLAN: " + DP_SITE:TOUPPER + ", RUNWAY "
            + (CHOOSE "AUTO" IF DP_RUNWAY = "auto" ELSE DP_RUNWAY:TOUPPER)).
    progLog("ORBIT " + ROUND((el["sma"] * (1 - el["ecc"]) - BODY:RADIUS) / 1000) + " X "
            + ROUND((el["sma"] * (1 + el["ecc"]) - BODY:RADIUS) / 1000) + " KM, " + ROUND(tilt, 1)
            + " DEG; CROSSRANGE LIMIT " + ROUND(KEP_CROSS_OK_KM) + " KM").
    IF DP_COARSE_ON {
        // THE COARSE TABLE (dpCoarseDent): the entry distance by the mean altitude, its end rows outside the table
        LOCAL t IS DP_COARSE_DENT.
        LOCAL hKm IS (el["sma"] - BODY:RADIUS) / 1000.
        LOCAL tNote IS "".
        IF hKm < t[0][0] { SET tNote TO "BELOW TABLE: " + t[0][0] + " KM ROW". }
        IF hKm > t[t:LENGTH - 1][0] { SET tNote TO "ABOVE TABLE: " + t[t:LENGTH - 1][0] + " KM ROW". }
        progCoarseVals(hKm, dpCoarseDent(el) / 1000, tNote).
        progLog("COARSE TABLE (" + t[0][0] + "-" + t[t:LENGTH - 1][0] + " KM): MEAN ALTITUDE " + ROUND(hKm, 1)
                + " KM, D_ENT " + ROUND(dpCoarseDent(el) / 1000) + " KM" + (CHOOSE "" IF tNote = "" ELSE ("; " + tNote))).
    }
    LOCAL offer IS site[0].
    IF NOT (DP_RUNWAY = "auto") {
        SET offer TO LIST().
        FOR th IN site[0] { IF th[0] = DP_RUNWAY { offer:ADD(th). } }
        IF offer:LENGTH = 0 {
            progLog("RUNWAY " + DP_RUNWAY:TOUPPER + " IS NOT AN END OF " + DP_SITE:TOUPPER + ": OFFERING BOTH", PG_YELLOW).
            SET offer TO site[0].
        }
    }
    LOCAL st IS LEXICON("tRev", -1, "tPass", -1, "n", 0).
    // DP_START: a caller's own start state (ops2q's DEORB TGT page declares it; a plain RUN has none): where the search resumes
    IF DEFINED DP_START { IF DP_START:ISTYPE("Lexicon") { SET st TO DP_START. } }
    LOCAL cleared IS FALSE.
    LOCAL done IS FALSE.
    UNTIL done {
        LOCAL pc IS dpPlanChain(el, tilt, offer, site[1], rv, vv, st).
        // THE RUNWAY BOX (the Sol default): AUTO re-makes a converged plan whose HAC turn reaches DP_BOX_TURN for the other
        // end, on the same pass, and keeps that one only if it converges too
        IF pc["ok"] AND DP_RUNWAY = "auto" {
            IF pc["sol"]["converged"] AND 360 - pc["theta"] >= DP_BOX_TURN {
                LOCAL other IS 0.
                FOR th IN site[0] {
                    IF NOT (th[0] = pc["runway"]) { SET other TO th. }
                }
                IF NOT (other = 0) {
                    progLog("RUNWAY BOX: A HAC TURN OF " + ROUND(360 - pc["theta"]) + " DEG ON " + pc["runway"]
                            + " (THE BOX: " + DP_BOX_TURN + "): TRYING " + other[0]).
                    LOCAL pc2 IS dpPlanChain(el, tilt, LIST(other), site[1], rv, vv, st).
                    LOCAL take IS pc2["ok"].
                    IF take { SET take TO pc2["sol"]["converged"]. }
                    progLog("RUNWAY BOX: " + (CHOOSE ("TAKING " + other[0]) IF take ELSE ("KEEPING " + pc["runway"]))).
                    IF take {
                        SET pc TO pc2.
                    }
                }
            }
        }
        IF DEFINED DP_START { SET DP_START TO pc["next"]. }   // the state NEXT PASS resumes from (0: no later pass), for the caller that declared it
        IF pc["ok"] {
            LOCAL sol IS pc["sol"].
            LOCAL tag IS "PASS " + pc["n"].
            SET DP_BACK_M TO pc["backM"].

            // ---- LEAD-TIME GATE, BEFORE ANYTHING IS COMMITTED ----------------------
            //  A plan whose burn is already behind the current MET cannot be executed, so the lead is checked before the plan
            //  is written. The solve is slow, and variably slow (from about 5 s to over a minute, depending on scene load): a burn 5 minutes
            //  out when the search begins can be in the past by the time it is written.
            //  DP_MIN_LEAD_S is 600 s, not 60: shuttle_exec has to be started, it warps to the burn, and it needs its own
            //  settling time before ignition. Reject, do not warn, and write no plan file: a stale plan on disk is worse than
            //  none, because planRead accepts anything inside PLAN_MAX_AGE and ops3q would fly to it.
            LOCAL solveTook IS TIME:SECONDS - planT0.
            LOCAL leadNow IS sol["tBurn"] - solveTook.
            // The planner's own run time, kept for the coarse deorbit's go / no-go.
            IF SOCK_LOG { LOG "planner (UT " + ROUND(TIME:SECONDS, 1) + "): planning took " + ROUND(solveTook, 1)
                + " s of game time, IPU " + CONFIG:IPU TO "0:/logs/planner_time.txt". }
            // ---- RESIDUAL GATE. Reject, do not warn, as the lead-time gate.
            //  A residual of hundreds of km is not something the guidance absorbs: the whole footprint from wings level to
            //  BANK_MAX spans about 1800 km. DP_TOL_KM is 8.
            // ---- AIM-SIDE GATE, AHEAD OF THE RESIDUAL GATE ---------------------
            //  A wrong-side plan passes the residual gate comfortably, so the side is asserted separately. dpGeoErr enforces
            //  the same test on every candidate, so this cannot fire unless something upstream is broken: it asserts that the
            //  plan that is written is self-consistent.
            IF NOT sol["sideOk"] {
                progLog(tag + ": REJECTED, WRONG SIDE: BACKSET " + ROUND(sol["backsetKm"], 1) + " KM, WANTED "
                        + ROUND(DP_BACK_M / 1000, 1) + " KM (BURN WAS SOLVED FOR ANOTHER PASS)", PG_YELLOW).
            } ELSE IF NOT sol["converged"] {
                progLog(tag + ": REJECTED, SOLVE DID NOT CONVERGE: MISS " + ROUND(sol["miss"] / 1000, 1) + " KM, LIMIT "
                        + ROUND(DP_TOL_KM) + " KM", PG_YELLOW).
                progRowSet(pc["row"], 4, "NO CONVERGE", PG_YELLOW).
            } ELSE IF leadNow < DP_MIN_LEAD_S {
                IF leadNow < 0 { progLog(tag + ": REJECTED, BURN IN PAST", PG_YELLOW). }
                ELSE { progLog(tag + ": REJECTED, BURN IS " + ROUND(leadNow) + " S AHEAD, NEEDS " + ROUND(DP_MIN_LEAD_S) + " S", PG_YELLOW). }
                progRowSet(pc["row"], 4, "TOO SOON", PG_YELLOW).
            } ELSE {
                // ---- the burn (no node). Retrograde at the burn point, which is what dpDvForFpa
                // solved for: a pure retrograde impulse, no normal or radial component.
                UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
                // No node: under Principia KSP's node drifts ~45 deg off the retrograde, so shuttle_exec flies this plan file by
                // itself. Any existing node is cleared just above.
                planWrite(pc["runway"], pc["aimLat"], pc["aimLng"], DP_FPA, DP_BANK,
                          sol["tBurn"], sol["tRot"], sol["dv"],
                          sol["miss"] / 1000, pc["crossKm"], planT0,
                          pc["brng"], sol["backsetKm"]).
                // TIG last, with the pointer to the end. The page is LEFT UP -- the list, the converged values and the
                // log are worth reading, and fam_build replaces it with its own page next.
                progRowSet(pc["row"], 4, "PLAN").
                progPlanStep(0, 0, TIME:SECONDS - DP_RUN_T0).
                IF DP_PROG { progPlanDone(DP_FPA, sol["dv"], planT0 + sol["tBurn"]). }
                LOCAL kind IS "TRACK".
                IF pc["align"] = "aligned" { SET kind TO "ALIGNED". }
                progLog("PLAN WRITTEN: PASS " + pc["n"] + ", RUNWAY " + pc["runway"] + ", THE " + kind + " PLAN, BURN "
                        + pgClock(planT0 + sol["tBurn"]) + ", " + ROUND(sol["dv"], 2) + " M/S").
                IF DP_COARSE_ON { progLog("COARSE: NO ENTRIES FLOWN; THE ENTRY ABSORBS THE TABLE'S ERROR"). }
                progStatus("PLAN WRITTEN: PASS " + pc["n"] + ", " + pc["runway"] + ", " + kind).
                PRINT "==================PLAN COMPLETE===================".
                SET done TO TRUE.
            }
        }
        IF NOT done {
            // ---- THE STOP: this pass cannot be flown, and its reason is
            // the log's last REJECTED line. A rejected run leaves nothing behind: planRead accepts any plan inside PLAN_MAX_AGE
            // (20000 s) and shuttle_exec would fly a stale node, so both are deleted at the first stop. The next pass only on
            // NEXT PASS, at most DP_REV_MAX_TRIES passes a run.
            IF NOT cleared {
                IF EXISTS(PLAN_FILE) {
                    DELETEPATH(PLAN_FILE).
                    progLog("THE PREVIOUS PLAN FILE WAS DELETED").
                }
                UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
                SET cleared TO TRUE.
            }
            LOCAL canNext IS DP_PROG AND (NOT (pc["next"] = 0)) AND pc["n"] < DP_REV_MAX_TRIES.
            IF pc["why"] = "find_rev" {
                progLog("STOPPED: NO " + (CHOOSE "" IF pc["n"] = 1 ELSE "LATER ") + "PASS REACHES THE SITE. NO PLAN WRITTEN.",
                        PG_YELLOW).
            } ELSE {
                progLog("STOPPED: PASS " + pc["n"] + " CANNOT BE FLOWN. NO PLAN WRITTEN.", PG_YELLOW).
            }
            IF canNext {
                progLog((CHOOSE "PICK FULL OR ANOTHER RUNWAY AND RE-RUN, OR PRESS NEXT PASS." IF DP_COARSE_ON
                         ELSE "PICK ANOTHER RUNWAY AND RE-RUN, OR PRESS NEXT PASS."), PG_YELLOW).
            } ELSE IF NOT (pc["next"] = 0) AND pc["n"] >= DP_REV_MAX_TRIES {
                progLog("THAT WAS PASS " + DP_REV_MAX_TRIES + ", THIS RUN'S LAST: RE-RUN THE PLANNER FOR A LATER ONE.",
                        PG_YELLOW).
            } ELSE IF NOT DP_PROG {
                progLog("NO PAGE, SO NO NEXT PASS: RE-RUN THE PLANNER FOR A LATER PASS.", PG_YELLOW).
            }
            progStatus("STOPPED AT PASS " + pc["n"], PG_YELLOW).
            LOCAL goNext IS FALSE.
            IF canNext { SET goNext TO progWaitStop(). }
            IF goNext {
                progLog("NEXT PASS: PASS " + (pc["n"] + 1)).
                progStatus("").
                SET st TO pc["next"].
            } ELSE {
                // CLOSE (the page went with it) or no further pass: the console keeps the banner; a page still up waits
                // for its CLOSE at the end of the script
                PRINT "===================PLAN STOPPED===================".
                SET done TO TRUE.
            }
        }
    }
}


// ============================================================================
//  EXECUTIVE  --  plan, write the file, hand off
// ============================================================================
//  Everything above is definitions; this is what runs. It does not execute the burn: it leaves a plan file, and SHUTTLE_EXEC
//  flies it. It shows its progress on the page and in the log.
GLOBAL DP_GEO_STEP IS 40.       // s between scan probes; ~130 km of geometry error per step is too fine to step over a bracket
GLOBAL DP_TRACE_FILE IS "0:/logs/deorbit_solve.csv".
                                // Per-probe record of the burn-time solve, one row per step (the burn time, the miss, the path
                                // length, the interface and where the entry ended). Rewritten every run: it describes the
                                // most recent solve, including a rejected one.
GLOBAL DP_MIN_LEAD_S IS 600.    // s: minimum time from the present to the burn; a plan with less is rejected outright (no plan file)
GLOBAL DP_RUN IS TRUE.          // set FALSE to load the definitions without planning
GLOBAL DP_LOADED IS TRUE.       // the definitions are in (lib_o2dorb's o2dbLoad does not load the file again after a hand-over)
GLOBAL DP_SEED_LEAD_S IS 2100.  // s: the earliest crossing the rev search may return; recomputed from the orbit below
                                //   A crossing is not a burn: the burn precedes it by the coast to the interface (~770 s) plus the
                                //   interface's own lead on the crossing (~644 s of orbital arc). The rev search returns the
                                //   earliest acceptable pass, which can be a crossing two minutes away whose burn is already in
                                //   the past; this lead keeps such a pass out.
// ---- DP_NO_RUN: THE SKIP FLAG IS ONE-SHOT ---------------------------------------------------
//  port_selftest.ks RUNONCEPATHs this file for its definitions, and RUNONCEPATH runs the whole file, executive included;
//  in orbit that would write a real plan file. Setting DP_NO_RUN to TRUE before the load skips the executive. The flag is
//  consumed on read (snapshot it, clear it, branch on the snapshot), because kOS globals persist for the whole session:
//  a sticky flag would make every later RUN DEORBIT_PLAN. exit without a line.
IF NOT (DEFINED DP_NO_RUN)   { GLOBAL DP_NO_RUN IS FALSE. }
IF NOT (DEFINED DP_SKIP_NOW) { GLOBAL DP_SKIP_NOW IS FALSE. }
SET DP_SKIP_NOW TO DP_NO_RUN.
SET DP_NO_RUN TO FALSE.

// ---- THE HAND-OVER: a RUN (DP_SELECT TRUE) opens ops2q on its DEORB TGT page, where the site, runway and mode are picked, the next
//  pass of each runway end is previewed and SOLVE runs this file's planner (lib_o2dorb.ks, prog_display's sink mode: no window of
//  its own). The selection box that used to open here is gone. DP_SELECT FALSE plans from DP_SITE with no page (below), as the
//  offline tools do.
IF DP_RUN AND NOT DP_SKIP_NOW AND DP_SELECT {
    SET DP_SKIP_NOW TO TRUE.
    CLEARSCREEN.
    IF EXISTS("0:/ops2q.ks") {
        PRINT "DEORBIT PLANNER: OPENING OPS2 ON DEORB TGT ...".
        RUNPATH("0:/ops2q.ks", "", "DEORB").
    } ELSE {
        PRINT "*** 0:/OPS2Q.KS NOT FOUND: THE PLANNER'S PAGE IS OPS2'S DEORB TGT.".
        PRINT "    TO PLAN WITH NO PAGE: SET DP_SELECT TO FALSE. (AND DP_SITE), THEN RUN DEORBIT_PLAN. AGAIN.".
    }
}

IF DP_RUN AND NOT DP_SKIP_NOW {
    CLEARSCREEN.
    // Schedule the entry angle from the orbit here, before anything reads it (see dpFpaForOrbit). The mean altitude is the
    // input: the schedule is fitted to circular orbit altitude, so on a slightly eccentric orbit the average is closer to
    // its basis than either apsis.
    LOCAL dpOrbAlt IS (APOAPSIS + PERIAPSIS) / 2.
    SET DP_FPA TO dpFpaForOrbit(dpOrbAlt).

    IF SHIP:ALTITUDE < EPR_ATM {
        PRINT "*** NOT IN ORBIT -- RUN THIS ABOVE THE ATMOSPHERE.".
    } ELSE {
        // The geodesy datum must exist before anything converts a state to a ground position, and it is captured from the
        // live vessel (without it EPR_GEO_X and EPR_GEO_Y are placeholders).
        eprInitGeo().

        // Capture the epoch with the state, in the same instant. Everything the solver returns (tBurn, tRot, the rev-search
        // crossing) is measured from the moment rv and vv are read; a clock read after the solve would put the burn late by the
        // solve's own duration (70 s is ~270 km of orbital motion along the track).
        LOCAL planT0 IS TIME:SECONDS.
        LOCAL rv IS -SHIP:BODY:POSITION.
        LOCAL vv IS SHIP:VELOCITY:ORBIT.
        LOCAL el IS kepElements(rv, vv).
        IF el = 0 {
            PRINT "*** HYPERBOLIC OR DEGENERATE ORBIT: NO ELEMENTS.".
        } ELSE {
            LOCAL tilt IS kepTilt(el).
            // THE PER-ORBIT CROSSRANGE LIMIT: on Sol this orbit's, from lib_kepler's table (kepCrossOk), for
            // every rev search after this line -- the selection box's and dpRun's, FULL and COARSE (any other body keeps the
            // flat 300). By the TRUE inclination: kepTilt folds a retrograde orbit onto a prograde one, but the planet's
            // rotation tells them apart (150 km: 60 deg 302.0 km, 120 deg 330.9 km); prograde = eastward inertial velocity.
            IF SHIP:BODY:NAME = "Earth" {
                LOCAL incTrue IS (CHOOSE tilt IF VDOT(vv, eprEastNorth(rv)[0]) >= 0 ELSE (180 - tilt)).
                SET KEP_CROSS_OK_KM TO kepCrossOk(dpOrbAlt / 1000, incTrue).
            }

            // ---- which site, which end, which pass
            // The ends are DP_SITE's (dpSiteTable). dpRun plans one pass at a time, the nearest first. DP_SEED_LEAD_S is the earliest pass that can still be flown: the minimum
            // lead to the burn + the coast to the interface for THIS orbit + the interface's lead on the pass.
            SET DP_SEED_LEAD_S TO DP_MIN_LEAD_S + DP_PLAN_ALLOW_S + dpCoastTime(dpOrbAlt) + DP_EI_TO_PASS_S.
            LOCAL goOn IS TRUE.
            LOCAL site IS dpSiteTable(DP_SITE).
            IF goOn AND site = 0 {
                PRINT "*** NO RUNWAYS FOR SITE " + DP_SITE:TOUPPER + " IN " + DP_RWY_FILE + ".".
            } ELSE IF goOn {
                dpRun(el, tilt, site, rv, vv, planT0, dpOrbAlt).
            }
        }
    }
}

// The script does not end until the page is dismissed, so the list, the log and the converged FPA / dv / TIG stay on screen.
// Returns at once if the page never came up, so a missing sidecar cannot hang anything.
progWaitClose().
