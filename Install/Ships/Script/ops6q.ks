// ============================================================================================================
//  ops6q.ks  --  OPS 6: THE TAL ENTRY, entry -> TAEM -> A/L -> the stop
// ============================================================================================================
//  ops1q runs it after a TAL's ET separation and its translation: RUNPATH("0:/ops6q.ks", "TAL", site), site "ZZA",
//  "MRN" or "SNN" (by hand: RUN ops6q("TAL", "ZZA"). ; a third argument forces the runway end, e.g. "ZZA30").
//  ops3q.ks's entry with these differences (a copy of it: a fix to ops3q's entry is made here too):
//    - no deorbit plan: the TAL site's prime runway end (ZZA30, MRN20), the aim TAL_AIM_KM short of the site (an
//      RTLS / CONT: the FTP, FTP_BACK_KM) on the great circle from the entry interface point (Phase 0.2);
//    - the reference family BUILT IN THE BACKGROUND from the ET-sep state: the loop advances it
//      TAL_BUILD_BUDGET steps a cycle (lib_tal talFamRun); no family file, no blocking build, no warp, no countdown;
//    - ops3q's pre-entry monoprop dump, its numbers unchanged: its coast call moved to the end of Phase 2,
//      after the entry attitude's lock (SAS is off since ops1q's hand-off: the lock holds the attitude through it);
//    - the TAL pre-entry: bank 0 at TAL_A0 (43) until guidance initiate, then the FSSR's ramp onto the nominal alpha
//      schedule (lib_tal talAoA); the members fly the same; the guidance cycle is lib_tal's talGuidStep;
//    - the OMS engines shut down BY PART (ops1q's ET-sep stage lit them at throttle 0; ops3q's AG2 is a bare toggle);
//    - the ENTRY TRAJ: the generic TAL panels in Script/tal/, up before the interface (with the entry DAP); the bug
//      placed among their bank lines as the vehicle sits among the live family's (lib_tal talTrajRange), the box on
//      them (talGenBankRange, through traj_display's TJ_BANK_RANGE); no bug or box before the live family is in. Once
//      the live family is in, the KAL/S addon draws ITS OWN panels (TJBGFAM) and the page switches to them (tjLiveFam);
//      the generic ones stay on any failure.
//    - SPLITS: the split-S after a 2EO / 3EO in stage 1
//      (RUNPATH("0:/ops6q.ks", "SPLITS", site), "SLF" or "VBG"): lib_grtls's split-S (phase 8 heads down in the turn
//      plane, then the GRTLS's 5 / 4, the runway END and the HAC side picked at phase 4's start, the side given to
//      landRun by TG_OVERHEAD_DEFAULT and put back after it), its steering taken right after the libraries load (AG7
//      and the lock in one tick); no reference family, no TRAJ, no AG9 (ops1q switched the surfaces on), no MP dump;
//      the speedbrake closed to TAEM; the loop's floor SS_FLOOR;
//    - THE HAND-OFF: ops1q's steering and OMS dump run on into OPS 6: no UNLOCK STEERING (the hold flies to OPS 6's
//      first LOCK); ASC_HO (this mode, under HO_FRESH_S old) with dump_on: a SPLITS holds the throttle at 1 until the
//      dump's engines are shut down (ops1q's cut by the aft tanks' mass) or flame out, or dump_left t are gone
//      (hoDumpOff: the engines off, the fuel cell's tanks put back, UNLOCK THROTTLE); a CONT's (GREEN and BLUE) and a
//      3EO TAL's (ASC_HO eo3) dump burn on the same way, the mass tracked each cycle (ASC_HO_DUMP_ON tells ops1q); a
//      1EO TAL's / an RTLS's dump ends at the hand-off.
//    - THE REACH TEST + THE CREW'S CHOICE (a deviation: the FSSR has neither): an RTLS (to the SLF or VBG) predicts TAEM's
//      EOW - EN from MECO's energy, distance and closing speed (a fit to offline GRTLS runs, rchPred); called short,
//      VERT SIT's title row shows GRTLS / BLUE and a countdown; with no pick in RCH_PICK_S it flies BLUE. EVERY BLUE
//      banks toward the line 5 km off the nearest coast and bails out over water (lib_grtls GR_BLUE_SHORE; lib_coast's
//      table for where the orbiter is: the Atlantic's, or the Pacific's west of 100 W).
//  NEVER STAGE: the next stage is the drag chute.
// ============================================================================================================
PARAMETER talMode IS "TAL", talSiteKey IS "ZZA", talRwyWant IS "".
RUNONCEPATH("0:/lib/lib_progreset.ks").  progReset().   // No hook of an earlier program outlives it (lib_progreset)
// Run from ops1q's precompiled 0:/ksm/ops6q.ksm (asc_o6_path): O6_KSM_GO is TRUE and this run's libraries load from
// 0:/ksm/ too (a shorter gap at the hand-off); cleared at the end (below)
LOCAL o6Ksm IS FALSE.
IF DEFINED O6_KSM_GO { SET o6Ksm TO O6_KSM_GO. }
GLOBAL OPS6_GR IS talMode = "RTLS" OR talMode = "CONT" OR talMode = "SPLITS".   // CONT: a 2EO
    // contingency flies the GRTLS too; SPLITS: the split-S's second half on its phases


SET TERMINAL:WIDTH TO 50.                         // kOS's default
CLEARSCREEN.                                      // the console stays blank from the start

// --- data logging module (see flightlogger.ks / logconfig.txt) -------
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/flightlogger.ksm" IF O6_KSM_GO ELSE "0:/lib/flightlogger.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/flightlogger.ks").
RUNONCEPATH("0:/lib/lib_logsw.ks").                  // SOCK_LOG: the logs on or off (0:/logging.txt)
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the MESSAGES strip)
kmQuiet(TRUE).                                       // the console stays blank from launch to landing; the lines go to the log (kmLogTo, once it opens)
// --- the caution & warning panel: ops3q's host wiring. lib_cw's state
// (every flFire lamp, the SM ALERT and every C / W line kmSay says), lib_cwui's window and tone. cwInit clears the last program's checks.
RUNONCEPATH("0:/lib/lib_cwui.ks").                   // the caution & warning panel (lib_cw: the state, lib_cwui: the window and the tone)
RUNONCEPATH("0:/lib/lib_cwchk.ks").                  // the checks' level functions
FUNCTION o6CwMet { RETURN MISSIONTIME. }
cwInit(o6CwMet@).                                    // every C / W line kmSay says becomes a row of the panel (and lights the lamp its text maps to)
cwListen().
RUNONCEPATH("0:/lib/lib_cape.ks").                   // the SLF where the Katniss Cape is (capeSlfMid)
// --- the FAILURES window and the failures an earlier program left. As ops3q's
// (lib_failui / lib_fail / lib_flfx / lib_gpc): the "!" beside BAILOUT (lib_dap builds it at dapGuiBuild only when something is registered,
// fuiHas: so these registrations come first) opens the window; fuiStart's one trigger runs its keys, the MET rows and the effects every
// FUI_DT s of real time through every wait and loop below. What OPS 6 flies: RCS 01 / 02, FCS 01, DPS 01 / 02, SW 01 / 03 (scope ENTRY) and
// SW 02 for TAEM / A/L, plus ENTRY on the TAL's guided entry (the GRTLS guidance has no hold: its SW 02 ENTRY is not offered). The ACTIVE list
// of ops1q (the DLL's list, else 1:/fail_state.txt) is KEPT: fuiBoot(FALSE) = flLoad, so an ascent's RCS / FCS / GPC / SW failure carries into
// the entry (flfxReapply, below, once lib_vehicle / lib_far are loaded). progReset (above) cleared every registration of the program before:
// nothing in ops6q's path calls it again until the end (deorbit_plan.ks does only as a program of its own).
RUNONCEPATH("0:/lib/lib_failui.ks").
flInit().
FUNCTION o6FlSwPage {                     // SW 03's page on the entry = the main display TOP (a constant: design choice, as ops3q's)
  RETURN "TOP".
}
flfxRegSw("ENTRY", o6FlSwPage@).         // SW 03 DISPLAY SOFTWARE + SW 01 AUTO DAP LOST (lib_flfx)
IF OPS6_GR { flfxRegGuid(LIST("TAEM", "A/L")). } ELSE { flfxRegGuid(LIST("ENTRY", "TAEM", "A/L")). }   // SW 02 GUIDANCE LOST
IF DEFINED FLFX_PH { SET FLFX_PH TO "ENTRY". }   // the phase the DAP / HUD SW 02 test reads (landRun sets TAEM, A/L)
flfxRegRcs().                            // RCS 01 MODULES OFF (+ its fix) / RCS 02 THRUST LOW
flfxRegFcs().                            // FCS 01 SURFACE FROZEN
flSimHost("OPS6").                         // The DLL's SimSup / RAND table for this program's codes
gpcInit("OPS6").                         // DPS 01 / 02 (a GPC fails: its window freezes, then the big X; TOP = G1, BOT = G2)
fuiBoot(FALSE).                          // the earlier program's failures back (the DLL's list / the files)
fuiStart().
SET cwuiGpc TO LEXICON().                            // The GPC clocks start with this program (a gap from the last program's would read as a GPC overrun)
cwuiStart().                                         // Its one trigger (the window at the first fault, the flash, the tone, the checks every tick), through landRun too: no close at the hand-off
// --- in-place terminal display widget --------------------------------
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/display.ksm" IF O6_KSM_GO ELSE "0:/lib/display.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/display.ks").
// --- the start-up block: each check prints its line at once (cut at the console's 50 columns) and keeps it in
// SU_LINES; suBlock writes them to the events file once the log is open. Nothing else prints to the console, which
// stays blank; a warning ("*** ...") prints there (opsWarn), not on the HUD.
GLOBAL SU_LINES IS LIST().
GLOBAL OPS_WARNS IS LIST().                // the warnings printed so far (opsCls prints them again after a clear)
// ops6q's own steering lock, released by the libraries that take the controls (lib_grdap, lib_land, lib_ascent_css):
// kOS's UNLOCK STEERING removes only the lock of the file it is compiled in, and a lock left running sets STEERING each
// tick, which turns the cooked steering back on
FUNCTION opsUnlockSteer { UNLOCK STEERING. }
IF NOT (DEFINED STEER_UNLOCKS) { GLOBAL STEER_UNLOCKS IS LIST(). }
STEER_UNLOCKS:ADD(opsUnlockSteer@).
// the throttle's locks the same way (ops1q's too: the hand-off's dump burns on under it), freed by hoDumpEnd
FUNCTION opsUnlockThr { UNLOCK THROTTLE. }
IF NOT (DEFINED THROTTLE_UNLOCKS) { GLOBAL THROTTLE_UNLOCKS IS LIST(). }
THROTTLE_UNLOCKS:ADD(opsUnlockThr@).

FUNCTION opsWarn {                         // a warning the pilot must see, on the console
    PARAMETER msg.
    OPS_WARNS:ADD(msg).
    kmSay(msg, "W").
}
FUNCTION opsCls {                          // the console cleared (displayReset), the warnings kept on it
    displayReset().
    IF NOT KM_QUIET { FOR w IN OPS_WARNS { PRINT w. } }
}
FUNCTION suNote {                          // a start-up line for the events file alone (not on the console)
    PARAMETER msg.
    IF _log_filePath <> "" { noteEvent("Start-up: " + msg). } ELSE { SU_LINES:ADD(msg). }
}
FUNCTION suLine {
    PARAMETER msg.
    IF msg:STARTSWITH("***") { opsWarn(msg). }
    IF _log_filePath <> "" { noteEvent("Start-up: " + msg). } ELSE { SU_LINES:ADD(msg). }   // queued until the log opens
}
FUNCTION suBlock {
    FOR suMsg IN SU_LINES { noteEvent("Start-up: " + suMsg). }
    SU_LINES:CLEAR().
}
// --- the entry predictor and the other libraries ---
RUNONCEPATH("0:/lib/entry_predict.ks").              // the entry predictor and reference-family tools (EPR_*)
eprMassTrack().                                   // the entry model (DREF too) at this vehicle's mass (entry_predict)
suLine("Entry Model: " + ROUND(SHIP:MASS, 3) + "t/" + (EPR_MASS_CAL / 1000) + "t, aero " + ROUND(EPR_MASS_K * 100, 2) + "%").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_vehicle.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_vehicle.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_vehicle.ks").                // trim, gimbal readout, measured aero
flfxReapply().                                       // The earlier program's failures act again (RCS off / capped, a frozen surface; lib_far is loaded now)
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_guide.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_guide.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_guide.ks").                  // profile grid, drag tracker, guidance state
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_plan.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_plan.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_plan.ks").                   // the deorbit plan handed over by the planner
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_fam.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_fam.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_fam.ks").                    // the reference family, built by fam_build
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/traj_display.ksm" IF O6_KSM_GO ELSE "0:/lib/traj_display.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/traj_display.ks").               // the ENTRY TRAJ panels
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_kepler.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_kepler.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_kepler.ks").                 // the FTP law (kepBuildFtp) for the no-plan fallback
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_land.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_land.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_land.ks").                   // TAEM + A/L (taemg, alg, fcs_pitch; lib_hud, lib_taemdisp)
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_tal.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_tal.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_tal.ks").                    // OPS 6: the TAL alpha + the copies of the build / guidance (after entry_predict)
IF OPS6_GR { RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_grtls.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_grtls.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_grtls.ks"). RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_taemdisp.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_taemdisp.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_taemdisp.ks"). RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_grdap.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_grdap.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_grdap.ks"). }   // the RTLS
    // glide (GRTLS, FSSR 4.8); its pages (MM 602) are lib_taemdisp's, one GUI with TAEM's; lib_grdap, the GRTLS's
    // DAP (no steering lock)
IF NOT OPS6_GR { RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_grdap.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_grdap.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_grdap.ks"). RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_entdisp.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_entdisp.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_entdisp.ks"). }   // the TAL's entry flies it too (CSS from EI + the entry HUD)

// THE HAND-OFF: ops1q leaves its steering and its OMS dump running into OPS 6 and describes them in GLOBAL ASC_HO:
// mode, site, ut (TIME:SECONDS at the hand-off), met, dump_on, dump_left (t; -1 = to empty), fc_lk (the fuel cell's
// tanks: LIST(resource, ENABLED before) pairs, as asc["oms_lk"]), aj10 (the dump's engines), surf_on; a split-S also
// alpha_cmd, alpha_max, rate, nz_max, nz, sep_ut, sep_met, az0 (the turn plane's heading, deg). Adopted only for this
// mode and when HO_FRESH_S fresh: a record an earlier run left must not light an OMS. No record (an ops1q that writes
// none): ops1q stopped the dump and released the steering.
GLOBAL HO_FRESH_S IS 60.                 // s: an older ASC_HO is not this hand-off's
GLOBAL HO_REC IS LEXICON().              // the adopted record (empty: none)
GLOBAL HO_DUMP IS FALSE.                 // TRUE while the hand-off's dump runs (hoDumpOff ends it)
GLOBAL HO_M0 IS SHIP:MASS.               // t at the adoption (dump_left counts from here)
GLOBAL HO_ENG IS LIST().                 // the dump's engines
GLOBAL HO_MSG IS "".                     // said on the events line once the logger is up (noteEvent is silent before)
// a CONT's / a 3EO TAL's dump ops1q's hold could not light (the ET not clear: ASC_HO dump_wait) is lit here once
// ops1q's test (ASC_HO dump_clr) holds, by ops1q's own start (ASC_HO dump_go), then it burns on as a dump_on one
GLOBAL HO_WAIT IS FALSE.                 // TRUE while such a dump waits
GLOBAL HO_WAIT_MAX IS 120.               // s: then it is not lit
GLOBAL HO_WAIT_DT IS 0.5.                // s between the tests
// preEntryMonoDump gates the tanks to monoprop (LiquidFuel / Oxidizer flow off), which would starve the hand-off's
// burning AJ10s (they flame out and hoDumpDue ends the dump); while that dump burns or waits it defers, and the loops
// run it after (mpBgTick)
GLOBAL MP_DEFER IS FALSE.                // TRUE: the pre-entry monoprop dump waits for the hand-off's OMS dump
GLOBAL MP_BG IS LEXICON().               // the deferred dump's run: tgt (units), t0, m0
// The deferred dump
// ran only from the GRTLS / entry loops (updateCgTrim -> mpBgTick); a hand-off OMS dump that burns on into TAEM ended
// in landRun's loop, which calls neither, so the forward RCS stayed full: TAEM flew on the elevon / body flap up stops
// (S-turn alpha 30 not reached, nz 0.3-1.0 g at bank 80 = a dive; Mach 1.6-1.2 L/D 0.8 vs 1.6) and every such arrival
// ended forced h<H_REF1, short. Now its own trigger (mpBgArm) ticks it in any loop.
GLOBAL MP_BG_DT IS 0.1.                 // s between the trigger's ticks of mpBgTick
GLOBAL MP_BGN IS 0.                     // TIME:SECONDS of its next tick
GLOBAL HO_WT0 IS -1.
GLOBAL HO_WTN IS 0.
GLOBAL ASC_HO_DUMP_ON IS TRUE.           // ops1q's asc_ho_dumps reads this NAME in this file: its HOPREP keeps a CONT's /
                                         //   a 3EO TAL's dump burning into OPS 6
// THE REACH TEST (the header): TAEM EOW - EN (m) = RCH_C . (1, E, d, vh) at MECO (fitted to offline GRTLS runs:
// E = h + V^2 / 2 g0 m, d the great circle to the RTLS site m, vh the closing speed m/s), short under RCH_THR (2 km under
// the lowest of the offline runs' STOPs at drag x1.0 and x0.907); d moved back to MECO along vh (ASC_HO's meco_ut;
// without it the larger of the two predictions MECO + RCH_DT_HO -+ RCH_DT_W s before the hand-off)
GLOBAL RCH_C IS LIST(-26503.8491080832, 0.1046446146439719, -0.15276775813568802, 27.060821828410084).
GLOBAL RCH_THR IS -20837.833521181117.
GLOBAL RCH_DT_HO IS 14.                  // s: MECO to ops1q's hand-off (the ET sep 4 s, its translation 5 s, the logger)
GLOBAL RCH_DT_W IS 5.                    // s: the bracket's half width
GLOBAL RCH_PICK_S IS 30.                 // s from the test: then BLUE
GLOBAL RCH_SITE IS "SLF".               // the RTLS site the test measures to (TAL_SITES' key: SLF or VBG)
GLOBAL RCH_SHORT IS FALSE.               // the test called short
GLOBAL RCH_PRED IS 0.                    // m: its prediction
GLOBAL RCH_T0 IS -1.                     // TIME:SECONDS at the test
GLOBAL RCH_BLUE0 IS FALSE.               // BLUE at once, no choice: ASC_HO's "eo2" (the locked 2EO line) is "BLUE" in an
                                         //   RTLS = a 2nd SSME out in its fuel dissipation / pitcharound, cut at once
FUNCTION rchPred {                       // the test's prediction (m) on the state now, d moved back dtb s along vh
    PARAMETER dtb.
    LOCAL site IS TAL_SITES[RCH_SITE][0].
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL toS IS site:POSITION.
    LOCAL vh IS VDOT(vs, (toS - VDOT(toS, upv) * upv):NORMALIZED).
    RETURN RCH_C[0] + RCH_C[1] * (ALTITUDE + vs:SQRMAGNITUDE / (2 * 9.80665))
           + RCH_C[2] * (groundDist(SHIP:GEOPOSITION, site) + vh * dtb) + RCH_C[3] * vh.
}
FUNCTION rchText {                       // the choice's countdown
    PARAMETER sLeft.
    RETURN "REACH SHORT: GRTLS OR BLUE  " + MAX(0, CEILING(sLeft)) + " S".
}
FUNCTION hoGet {
    PARAMETER k, dflt.
    IF HO_REC:HASKEY(k) { RETURN HO_REC[k]. }
    RETURN dflt.
}
FUNCTION hoDumpDue {                     // the dump's end: dump_left t gone, or none of its engines still burning: shut
    LOCAL lft IS hoGet("dump_left", -1). //   down (IGNITION FALSE: ops1q's cut by the aft tanks' mass; after the ET sep
    IF lft >= 0 {                        //   the mid LFO is unlocked for the fuel cell and drains last, so no flameout
        IF HO_M0 - SHIP:MASS >= lft { RETURN TRUE. }   // comes before it is gone too) or flamed out (an ops1q that
    }                                    //   keeps the mid locked: the aft tanks run dry)
    FOR eng IN HO_ENG {
        IF eng:IGNITION AND NOT eng:FLAMEOUT { RETURN FALSE. }
    }
    RETURN TRUE.
}
// The hand-off's dump burned under LOCK THROTTLE TO 1, so the vessel's throttle
// was ops6q's and the lever (SPDBK MAN's speedbrake) was taken. Now the OMS engines fly KSP's own independent throttle at 100 %
// (ADDONS:KALS:ENGIND: the DLL puts them back on the vessel's throttle 0.5 s after its last call, so a trigger calls it
// every tick), and the vessel's throttle is the pilot's: nothing is locked, the lever stays the speedbrake's in SPDBK MAN. Without
// ENGIND (an older DLL) or with HO_IND_ON FALSE: the old LOCK THROTTLE TO 1.
GLOBAL HO_IND_ON IS TRUE.                // FALSE: the dump rides the main throttle (LOCK THROTTLE TO 1)
GLOBAL HO_IND IS FALSE.                  // TRUE while the dump's engines fly their own throttle
FUNCTION hoIndCall {                     // ENGIND for the OMS engines at pct (< 0: back on the vessel's throttle); count, -1 = no ENGIND
    PARAMETER pct.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN -1. }
    IF NOT ADDONS:KALS:HASSUFFIX("ENGIND") { RETURN -1. }
    RETURN ADDONS:KALS:ENGIND("AJ10", pct).
}
GLOBAL HO_INDF IS hoIndCall@.            // (a test replaces it)
FUNCTION hoThrStart {                    // the dump's engines lit: on their own throttle at 100 %, else the main throttle at 1
    PARAMETER first.                     //   first: the start of OPS 6 (the DAP not up yet: the lever's start value is put to 0)
    LOCAL n IS 0.
    IF HO_IND_ON { SET n TO HO_INDF:CALL(100). }
    IF n > 0 {
        SET HO_IND TO TRUE.
        FOR u IN THROTTLE_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } }   // ops1q's lock (asc_thr) too: the throttle is the pilot's now
        IF first { SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0. }
        WHEN HO_IND THEN {
            IF HO_DUMP { HO_INDF:CALL(100). }
            RETURN HO_IND.
        }
    } ELSE {
        LOCK THROTTLE TO 1.
    }
}
FUNCTION hoThrWords {                    // for HO_MSG / the events line
    RETURN CHOOSE "the OMS fly their own throttle at 100 % (ENGIND), the throttle lever stays the speedbrake's in SPDBK MAN"
        IF HO_IND ELSE "the OMS ride the main throttle at 1 (no ENGIND in the DLL: SPDBK MAN's lever is taken)".
}
FUNCTION hoDumpEnd {                     // the engines off, the fuel cell's tanks as they were, the throttle released
    FOR eng IN HO_ENG {
        IF eng:IGNITION { eng:SHUTDOWN(). }
    }
    talOmsOff().
    IF HO_IND { HO_INDF:CALL(-1). SET HO_IND TO FALSE. }   // back on the vessel's throttle, the engines off
    FOR lk IN hoGet("fc_lk", LIST()) { SET lk[0]:ENABLED TO lk[1]. }
    FOR u IN THROTTLE_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } }   // every live run's lock (THROTTLE_UNLOCKS), ops6q's own among them
    SET HO_DUMP TO FALSE.
    eprMassTrack().                      // the entry model at the mass the dump left
}
FUNCTION hoDumpOff {                     // the dump's end in flight, said on the events line
    hoDumpEnd().
    noteEvent("OPS 6: the hand-off's OMS dump ended (" + ROUND(HO_M0 - SHIP:MASS, 2) + " t since the hand-off)").
}
FUNCTION hoWaitArm {                     // the waiting dump's test every HO_WAIT_DT s, for HO_WAIT_MAX s
    SET HO_WT0 TO TIME:SECONDS.
    SET HO_WTN TO 0.
    WHEN TIME:SECONDS >= HO_WTN THEN {
        SET HO_WTN TO TIME:SECONDS + HO_WAIT_DT.
        IF NOT HO_WAIT { RETURN FALSE. }
        IF hoGet("dump_clr", 0):CALL() { hoWaitGo(). RETURN FALSE. }
        IF TIME:SECONDS - HO_WT0 > HO_WAIT_MAX {
            SET HO_WAIT TO FALSE.
            noteEvent("OPS 6: the hand-off's OMS dump not lit: the ET not clear in " + HO_WAIT_MAX + " s").
            RETURN FALSE.
        }
        RETURN TRUE.
    }
}
FUNCTION hoWaitGo {                      // lit by ops1q's start, then as a dump_on one (hoDumpDue / hoDumpOff)
    SET HO_WAIT TO FALSE.
    SET HO_ENG TO hoGet("dump_go", 0):CALL().
    SET HO_M0 TO SHIP:MASS.
    SET HO_DUMP TO TRUE.
    hoThrStart(FALSE).
    WHEN hoDumpDue() THEN { hoDumpOff(). }
    noteEvent("OPS 6: the hand-off's OMS dump lit (" + hoThrWords() + "), the ET clear " + ROUND(TIME:SECONDS - HO_WT0, 1) + " s after OPS 6's "
              + "start (" + HO_ENG:LENGTH + " engines, " + (CHOOSE "to empty" IF hoGet("dump_left", -1) < 0
              ELSE ROUND(hoGet("dump_left", -1), 2) + " t") + ")").
}
IF DEFINED ASC_HO {
    IF ASC_HO:ISTYPE("Lexicon") {
        IF ASC_HO:HASKEY("mode") AND ASC_HO:HASKEY("ut") {
            IF ASC_HO["mode"] = talMode AND ABS(TIME:SECONDS - ASC_HO["ut"]) < HO_FRESH_S { SET HO_REC TO ASC_HO. }
        }
    }
}
// kOS
// keeps GLOBALs after a program ends, its FUNCTIONS go (adClose / adAdopt of ops1q's lib_ascdisp). adOn / ASC_PG_KEEP_UP left TRUE by
// a dead ops1q sent this program into adClose() / adAdopt(). ops1q is alive only when it handed over just now (a fresh ASC_HO); else
// its page state is dead and is forgotten here, before anything reads it.
GLOBAL o6Ops1Live IS FALSE.
IF DEFINED ASC_HO {
    IF ASC_HO:ISTYPE("Lexicon") {
        IF ASC_HO:HASKEY("ut") {
            IF ABS(TIME:SECONDS - ASC_HO["ut"]) < HO_FRESH_S { SET o6Ops1Live TO TRUE. }
        }
    }
}
IF NOT o6Ops1Live {
    IF DEFINED adOn { SET adOn TO FALSE. }
    IF DEFINED ASC_PG_KEEP_UP { SET ASC_PG_KEEP_UP TO FALSE. }
}
IF HO_REC:LENGTH > 0 {
    SET HO_MSG TO "OPS 6: ops1's hand-off (" + HO_REC["mode"] + ", " + ROUND(TIME:SECONDS - HO_REC["ut"], 1) + " s ago"
        + (CHOOSE ", precompiled" IF o6Ksm ELSE "") + ")".
    IF hoGet("dump_on", FALSE) {
        SET HO_ENG TO hoGet("aj10", LIST()).
        IF HO_ENG:LENGTH = 0 {
            FOR eng IN SHIP:ENGINES {
                IF eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering") OR eng:TITLE:CONTAINS("Viking") {
                    IF eng:IGNITION { HO_ENG:ADD(eng). }
                }
            }
        }
        SET HO_M0 TO SHIP:MASS.
        IF talMode = "SPLITS" OR talMode = "CONT" OR (talMode = "TAL" AND hoGet("eo3", FALSE)) {   // a split-S's, a CONT's and a 3EO TAL's
            SET HO_DUMP TO TRUE.         //   dump burns on, the mass tracked each cycle;
            hoThrStart(TRUE).            //   a 1EO TAL's / an RTLS's ends here
            WHEN hoDumpDue() THEN { hoDumpOff(). }
            IF hoGet("dump_left", -1) < 0 {
                SET HO_MSG TO HO_MSG + "; its OMS dump runs on to empty (" + HO_ENG:LENGTH + " engines)".
            } ELSE {
                SET HO_MSG TO HO_MSG + "; its OMS dump runs on for " + ROUND(hoGet("dump_left", -1), 2) + " t ("
                              + HO_ENG:LENGTH + " engines)".
            }
            SET HO_MSG TO HO_MSG + "; " + hoThrWords().
        } ELSE {
            hoDumpEnd().
            SET HO_MSG TO HO_MSG + "; its OMS dump ended at the hand-off (" + HO_ENG:LENGTH + " engines; OPS 6 burns on "
                          + "a split-S's, a CONT's and a 3EO TAL's)".
        }
    } ELSE IF hoGet("dump_wait", FALSE) AND (talMode = "CONT" OR (talMode = "TAL" AND hoGet("eo3", FALSE))) {
        SET HO_WAIT TO TRUE.                 // lit once the ET is clear (hoWaitArm, after the OMS-off below)
        SET HO_MSG TO HO_MSG + "; its OMS dump waits for the ET to clear (" + (CHOOSE "to empty" IF hoGet("dump_left", -1)
                      < 0 ELSE ROUND(hoGet("dump_left", -1), 2) + " t") + ")".
    }
}
// THE SPLIT-S's FIRST LOCK: the vehicle is in the air at q 5-13 kPa, so the steering is taken NOW (lib_grtls phase 8
// at the alpha as found, the turn plane from ASC_HO's az0 or the ground track's). AG7 (Control From Here on the
// forward fuselage) should keep ops1q's control point, but in flight the alpha read 21.98 before ops6q's toggle and
// 20.32 after it, a smooth drift, and the part's second control point is "angled", 15 deg in pitch, in its cfg. So the
// toggle and the lock in ONE tick (after a WAIT 0: a fresh tick's budget), the alpha read after the toggle; if the two
// reads agree, one tick more and the alpha read again (a point that moves a tick late): safe either way.
IF talMode = "SPLITS" {
    ssSet(hoGet("az0", -1)).
    SAS OFF.
    RCS ON.
    SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.
    WAIT 0.
    LOCAL ssA0 IS ldAlphaNow().
    TOGGLE AG7.
    LOCAL ssA1 IS ldAlphaNow().
    SET GR TO grtlsReset(ssA1, TIME:SECONDS).
    IF NOT grdStart(TRUE) { LOCK STEERING TO ssSteer(). }   // the GRTLS DAP flies phase 8 (lib_grdap; an older DLL: the lock)
    IF ABS(ssA1 - ssA0) < 0.5 {
        WAIT 0.
        SET ssA1 TO ldAlphaNow().
        SET GR["acmd"] TO ssA1.
    }
    suLine("SPLIT-S: steering at alpha " + ROUND(ssA1, 1) + ", plane " + ROUND(SS_AZ0, 1) + " deg").
    IF HO_MSG <> "" { SET HO_MSG TO HO_MSG + "; ". }
    SET HO_MSG TO HO_MSG + "OPS 6 SPLIT-S: the steering taken at alpha " + ROUND(ssA1, 2) + " (AG7's point; "
                  + ROUND(ssA0, 2) + " through ops1's), the turn plane " + ROUND(SS_AZ0, 1) + " deg ("
                  + (CHOOSE "ASCENT's az0" IF hoGet("az0", -1) >= 0 ELSE "the ground track's") + ")".
}

// OPS 6: THE OMS ENGINES OFF, BY PART. After a TAL's ET separation the stage that fired it has IGNITED both OMS engines at
// throttle 0, and in SPDBK MAN the throttle lever is the speedbrake lever (lib_dap): a lit OMS would fire on it. ops3q's
// AG2 is a bare toggle that assumes the state; this reads it. The DAP's stick readback (the OMS gimbal) works with the
// engine off, as after AG2.
FUNCTION grdOnNow {                      // the GRTLS DAP (lib_grdap, OPS6_GR only) flies now
    IF DEFINED grdOn { RETURN grdOn. }
    RETURN FALSE.
}
FUNCTION talOmsOff {
    LOCAL n IS 0.
    FOR eng IN SHIP:ENGINES {
        IF eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering") OR eng:TITLE:CONTAINS("Viking") {
            IF eng:IGNITION {
                eng:SHUTDOWN().
                SET n TO n + 1.
            }
        }
    }
    noteEvent("OPS 6: OMS off by part (" + n + " lit engine(s) shut down)").
    RETURN n.
}

// OPS 6: the background build's end, said once.
FUNCTION talFamDone {
    PARAMETER why.
    SET TAL_FAM_DONE_T TO TIME:SECONDS.
    IF EPR_FAM_OK {
        noteEvent("OPS 6: family ready: " + EPR_FAM:LENGTH + " members in " + ROUND(TAL_FAM_DONE_T - TAL_FAM_T0, 1) + " s"
                  + (CHOOSE "" IF NOT EPR_FAM_PARTIAL ELSE " -- PARTIAL: " + EPR_FAM_WHY) + why
                  + (CHOOSE " [" + EPR_FAM_CS_SAY + "]" IF (DEFINED EPR_FAM_CS_SAY) ELSE "")).   // C# or kOS (entry_predict)
    } ELSE {
        noteEvent("OPS 6: FAMILY UNUSABLE (" + EPR_FAM_WHY + ")" + why + " -- the fallback bank hold").
    }
}
GLOBAL OPS_SITE IS "SLF".                        // the site the no-plan fallback lands at

// THE LIVE FAMILY'S OWN ENTRY TRAJ PANELS. The generic tal/ panels are up from the interface; once the in-flight family
// is in (EPR_FAM_READY, EPR_FAM_OK) the KAL/S addon draws that family's own five panels on a worker thread
// (ADDONS:KALS:TJBGFAM: gen_traj_bg's drawing in C#, the drag strip 0..100 as on the tal/ panels, PNGs under
// traj_cs/ops6/ named by the stamp) and, when they are done, the page shows them (traj_display trajReload): the box then
// rides the live family's own lines (tjFamBank = eprTrajBankRange) and the bug the range the guidance inverts, with no
// mapping onto generic lines (TJ_LIVEFAM). Polled once a guidance cycle from the TRAJ block; never waits. Any failure
// (no addon, an older DLL, a refused sidecar): the generic panels stay, TJ_LIVEFAM_ON turns off for the flight and the
// events file says why.
IF NOT (DEFINED TJ_LIVEFAM_ON) { GLOBAL TJ_LIVEFAM_ON IS TRUE. }
GLOBAL TJ_LIVEFAM IS FALSE.                      // the page shows the live family's panels
GLOBAL TJ_LIVEFAM_H IS 0.                        // the drawing's handle while it runs
FUNCTION tjLiveFam {
    IF TJ_LIVEFAM OR NOT TJ_LIVEFAM_ON OR NOT TJ_OK OR NOT EPR_FAM_READY OR NOT EPR_FAM_OK { RETURN. }
    LOCAL why IS "".
    IF TJ_LIVEFAM_H:ISTYPE("Scalar") {
        IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
        ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
        ELSE IF NOT ADDONS:KALS:HASSUFFIX("TJBGFAM") { SET why TO "the KAL/S addon has no TJBGFAM (an older DLL)". }
        ELSE {
            SET TJ_LIVEFAM_H TO ADDONS:KALS:TJBGFAM(EPR_FAM, LEXICON("side", "traj_cs/ops6/traj_bg.txt", "tpl", TJ_BG_TPL,
                "pngdir", "traj_cs/ops6", "dmax", 100, "vessel", SHIP:NAME, "written", ROUND(TIME:SECONDS, 3), "aero_ver", EPR_AERO_VER,
                "taem_vel", EPR_TAEM_VEL)).
            RETURN.
        }
    } ELSE IF NOT TJ_LIVEFAM_H:DONE {
        RETURN.
    } ELSE IF NOT TJ_LIVEFAM_H:OK {
        SET why TO "TJBGFAM: " + TJ_LIVEFAM_H:WHY.
    } ELSE IF NOT trajReload("0:/" + TJ_LIVEFAM_H:SIDE) {
        SET why TO "its sidecar refused: " + TJ_WHY.
    }
    IF why <> "" {
        SET TJ_LIVEFAM_ON TO FALSE.
        noteEvent("TRAJ: the generic TAL panels stay (" + why + ")").
        RETURN.
    }
    SET TJ_LIVEFAM TO TRUE.
    SET TJ_BANK_RANGE TO tjFamBank@.             // the box on the live family's lines (C# while the C# page runs)
    noteEvent("TRAJ: the live family's own panels (" + TJ_P:LENGTH + ", drawn in " + ROUND(TJ_LIVEFAM_H:MS) + " ms)").
}

// --- INSTRUCTION BUDGET ----------------------------------------------------------------
// kOS executes CONFIG:IPU instructions per physics update (default 200) and spreads a loop body across as many
// updates as it needs. The Phase 3 loop carries the telemetry panel, two PNG-backed plots, the logger and, with
// the shadow predictor on, 50 acceleration evaluations: at 200 IPU the steering command updates too rarely to
// arrest a roll cleanly. Stock kOS clamps IPU at 2000; this install's kOS is patched to 10000, and the entry
// runs there, as landRun does from the TAEM handover (lib_land LD_IPU). It costs host CPU: if the framerate
// suffers, step IPU down rather than reaching for EPR_SHADOW_BUDGET, which trades control authority for
// prediction freshness.
SET CONFIG:IPU TO 10000.

// ----------------------------- CONFIG --------------------------------

// THE DEFAULT RUNWAY, until applyRunway() takes the one the plan names: runway 09 of lib_plan.ks's survey
// (PLAN_RWY09: the west end, heading 090, landing flying east).
GLOBAL RWY09_THRESH IS PLAN_RWY09.

// The ACTIVE runway -- applyRunway() sets these once a runway is chosen. Defaults are the
// runway-09 / equatorial-prograde case.
GLOBAL RWY_THRESH  IS RWY09_THRESH.   // active landing threshold
GLOBAL RWY_HEADING IS 90.             // active landing heading (deg): 90 = rwy 09, 270 = rwy 27
GLOBAL RWY_NAME    IS "09".           // active runway label (display/log)

// Final target point (FTP), built per runway and used as the entry's aim: FTP_LAT_KM laterally (west for 09 /
// east for 27) + FTP_BACK_KM back up the approach, the back leg laid along the REVERSED orbital ground track so
// it follows the inclined approach angle. For an equatorial orbit that back leg is due west/east, so the 09 FTP
// collapses to a point FTP_LAT_KM + FTP_BACK_KM due west.
// ---- TAEM HANDOVER GEOMETRY: THE ORBITER'S, RESCALED FOR THE PLANET ------------------------
// FSSR 3.2.1: TAEM transition occurs "approximately 60 nm from the runway threshold at an altitude of
// approximately 82,000 ft AGL", at 2500 ft/s: a glideslope of 24.99/111.12 = 0.2249. The altitude cannot be
// copied: Vc is 3961 m/s here against 7910 on Earth and lift goes as rho*V^2, so at the same fraction of
// orbital speed this vehicle has a quarter of the dynamic pressure and must fly in 4x the density, roughly
// 6-7 km lower (it arrives at about 18.7 km). So the glideslope is matched, not the altitude: the arrival
// altitude does not depend on the aim, only the range does. FTP_BACK_KM is the FTP law's base range
// (lib_kepler KEP_FTP_RANGE_NM, 32.32 nm at the base approach angle).
GLOBAL FTP_LAT_KM       IS 12.964. // = 7 nm, the NEP distance (3.2.2)
GLOBAL FTP_BACK_KM      IS 59.85664. // = 32.32 nm x 1852 m / 1000
// THE TAL'S FIXED AIM: TAL_AIM_KM short of the site's centre (Phase 0.2), on the inbound great circle without the FTP
// law's HAC term. At FTP_BACK_KM (59.86 km) TAEM began low. Offline (5 TAL cases x drag 1.0 / 1.1 / 0.9, the prime
// ends), TAEM's start energy over EN, the median: at 59.86 km the G4.8 -0.9 km, the family +0.5, the AOA +0.4 (nominal
// entries +5.6..+7.0); at 52 km +1.0 / +3.7 / +3.6; TAEM OK 30 -> 30 of 33, touchdown 31 -> 32. An RTLS / CONT keeps
// FTP_BACK_KM. lib_aoa AOA_FTP_M = the same distance, and the offline TAL model's aim mirrors it.
GLOBAL TAL_AIM_KM       IS 52.

// --- Rev-selection prediction snapshot: log columns that no live code sets ---
// Each names what the rev search predicts (the crossrange at the chosen pass's abeam crossing); nothing sets
// them, so they log their defaults. All times are absolute UT (TIME:SECONDS), the same clock as the log's MET.
GLOBAL PRED_CROSS_KM IS -1.   // predicted crossrange of the chosen rev to the FTP aim (km)
GLOBAL PRED_LAT      IS 0.    // ground-track sub-point latitude  at the abeam crossing (deg)
GLOBAL PRED_LNG      IS 0.    // ground-track sub-point longitude at the abeam crossing (deg)
GLOBAL PRED_TOVER_UT IS 0.    // chosen rev's abeam-crossing UT (tOver)
GLOBAL PRED_TD_UT    IS 0.    // touchdown estimate UT (~ the abeam crossing)
GLOBAL DESC_LAG_S    IS 0.    // (a descent-lag log column nothing sets: 0 keeps the column)
GLOBAL LEAD_TIME_S   IS 0.    // lead time used (s) ; no live code sets it

// Aim range (km): the straight-line range from the FTP to the runway threshold. applyRunway()
// recomputes it once the FTP exists; this default is the equatorial-09 case (FTP_LAT_KM + FTP_BACK_KM).
GLOBAL GLIDE_OFFSET_KM IS FTP_LAT_KM + FTP_BACK_KM.

// The aim point. The entry guidance and the logging reference KSC_TARGET; applyRunway() sets it to the chosen
// FTP. This default (equatorial 09: GLIDE_OFFSET_KM west) keeps the script valid before selection.
GLOBAL KSC_TARGET IS destGeo(RWY09_THRESH, 270, GLIDE_OFFSET_KM * 1000).

GLOBAL GS_ACQ_NEAR        IS 20.    // ACQ glideslope WITHIN GS_ACQ_BRK_M of the HAC entry (deg, steep)
GLOBAL GS_ACQ_FAR         IS 12.    // ACQ glideslope BEYOND that (deg, shallow) -- shuttle glides better fast/far
GLOBAL GS_ACQ_BRK_M       IS 30000. // ACQ glideslope breakpoint: distance from the HAC entry along the leg (m); the 12/20 kink lands at 25 km RGO

// Auto-speedbrake: the throttle axis drives the speedbrake (0 throttle = full deploy / max drag,
// full throttle = stowed).
GLOBAL sbThrottle     IS 0.5.    // current servo throttle command (LOCKed to THROTTLE in Phase 4)

// --- Mach number, for indexing the aerodynamic tables --------------------------------
// The drag coefficient is a Mach effect (stock KSP applies global Mach multiplier curves on top of the
// per-part drag cubes), so the tables are indexed on Mach, not on velocity.
// Mach needs no temperature and no thermometer: with q = rho*v^2/2 and a^2 = gamma*p/rho the density cancels,
//        M^2 = v^2/a^2 = (2q/rho) / (gamma*p/rho) = 2q / (gamma*p)
// so dynamic pressure and static pressure, in the same units, are enough.
// GAMMA is a constant, because referencing BODY:ATM:ADIABATICINDEX is a compile error where the suffix does
// not exist. Check it once from the terminal (PRINT SHIP:BODY:ATM:ADIABATICINDEX.) and correct it if this
// atmosphere differs from the stock 1.4.
GLOBAL ADIABATIC_INDEX IS 1.4.

// Static (ambient) pressure in Pa at the current altitude.
FUNCTION staticPressurePa {
    RETURN SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE) * CONSTANT:ATMTOKPA * 1000.
}

// Mach number from dynamic over static pressure -- see the identity above.
FUNCTION machNow {
    LOCAL ps IS staticPressurePa().
    IF ps < 0.0001 { RETURN 0. }
    LOCAL qd IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000.
    RETURN SQRT(MAX(2 * qd / (ADIABATIC_INDEX * ps), 0)).
}

// ============================================================================
//  DIRECT AERODYNAMIC FORCE MEASUREMENT  (for offline L/D fitting)
// ============================================================================
//  An accelerometer measures the aero force directly, which the trajectory cannot give in the hypersonic phase
//  (centrifugal relief carries much of the weight there). The kOS docs are wrong about both sensors:
//    SHIP:SENSORS:ACC   is the vessel's KINEMATIC acceleration, not "gravity plus thrust" (near zero when parked).
//                       Needs an accelerometer part.
//    SHIP:SENSORS:GRAV  is already in m/s^2, not G's. Needs a gravioli detector.
//  ACC - GRAV is the non-gravitational acceleration (aero, engines off). aeroVec (lib_vehicle.ks) computes gravity
//  as mu/r^2 instead of reading GRAV, so only the accelerometer part is needed. Calibrate on the pad before
//  trusting it: the corrected vector must read 9.81 m/s^2 pointing away from the planet (accel_check.ks). kOS issue
//  #1827: ACC:MAG may not match the value the part displays; ACC_SCALE (lib_vehicle.ks) holds the correction.
//  The switch is lib_vehicle.ks's HAS_ACCELEROMETER, FALSE here: the finite-difference route (below) needs no
//  part, and with it FALSE aeroVec() returns a zero vector (the aero_up / aero_dr / aero_side / aero_drag /
//  aero_lift / aero_ld columns log 0). With it TRUE and no part aboard, SHIP:SENSORS:ACC throws or returns zero and
//  aeroVec() returns MINUS gravity (a plausible but false lift), so the start-up check after the body-flap bias
//  forces the switch back to FALSE and says so.

// --- STEERING PID LOGGING ---------------------------------------------------------------
// TRUE makes STEERINGMANAGER dump all six of its PID loops to CSV, including the three TORQUE PIDs whose output
// becomes the actual control deflection. It is the only route: no suffix returns the applied control under cooked
// steering. SHIP:CONTROL:* is the raw channel (it reads back only what a script SET, and its trim suffixes have no
// effect on the autopilot), STEERINGMANAGER:PITCHPID is a rotational-velocity PID whose output is a target angular
// velocity in rad/s, and ModuleControlSurface exposes configuration, not live position. The torque PID (the second
// loop, whose settling time is PITCHTS) gives a torque command in kNm, not a control fraction.
// The files land OUTSIDE the kOS volume, in [KSP Root]/GameData/kOS/Plugins/PluginData/kOS, one per loop and a
// new set per vessel load. They grow quickly, so use this for one diagnostic entry, not routine flying.
GLOBAL STEER_CSV IS FALSE.  // see the FLAP_BIAS notes below

// ============================================================================
//  CLOSED-LOOP PITCH TRIM (the loop is lib_vehicle.ks's ptrimUpdate and its PTRIM_* settings)
// ============================================================================
//  Drives the body flap to null the sustained pitch command, measured by the OMS gimbal readout. Closed loop
//  because the demand grows with dynamic pressure, so a fixed flap angle is right at only one altitude; an
//  integrator needs only the right SIGN (PTRIM_SIGN -1, measured: negative flap counteracts a positive pitch
//  command; see the NO SIGN GUARD note in lib_vehicle.ks) and a gain low enough not to oscillate.
//  Slow by design: the control loop runs at 50 Hz and this at the script rate (about 2 Hz), and trim must be far
//  slower than the controller or it becomes a second controller fighting the first. PTRIM_RATE caps it at 0.5 deg/s.
//  PTRIM_GAIN 2 is the largest value that keeps it an integrator (3 would bind the rate cap and hunt); if trim_ang
//  moves at exactly PTRIM_RATE for long stretches, the gain is too high for the error size. PTRIM_MAX 19.5: the
//  flap's authority limiter is 20.

// --- ELEVON TRIM, spilled from the flap (lib_vehicle.ks's ETRIM_*) ----------------------------------
//  The flap alone can saturate (at peak q), so the elevons take what is left over. Symmetric only: both elevons
//  biased the same way is a PITCH input, while roll comes from differential deflection on top and reverses sign, so
//  no fixed bias can cancel it. It costs roll authority (with a bias X one elevon reaches its limit at d = max-X, so
//  roll authority falls by X in both directions), which is why the flap is used first. ETRIM_MAX 15 of the elevons'
//  25 limiter keeps roll headroom at 40%. The sign is not verified (the flap trims nose-up by deflecting down, the
//  elevons by deflecting up): if the elevon engages and |gmb_pitch| grows while elev_trim moves away from zero,
//  ETRIM_SIGN is wrong. It engages only once the flap saturates, so a wrong sign is bounded to that window.

// --- BODY FLAP BIAS EXPERIMENT ---------------------------------------------------------
// FLAP_BIAS deploys the body flap to a fixed angle (deg) for the whole entry; -999 disables. A bias is the probe for
// the pitch demand because the demand cannot be read (SHIP:CONTROL is the raw channel, PITCHPID a velocity-loop
// output, ModuleControlSurface exposes no position): compare the RCS propellant lost over an entry at -999 and at
// +10. FLAP_BIAS stays at -999: +10 deg raised the quiet-window RCS rate by about a third, since the pitch demand is
// an oscillation, not a bias, and trim removes bias, not swing.

// ============================================================================
//  APPLIED CONTROL, via the OMS gimbal
// ============================================================================
//  Gimbal:PITCHANGLE is the applied control on a -1..1 scale, and the only route to it in kOS. It is the
//  COMMANDED control, independent of the gimbal limit, and it works with the engines OFF; the axes are not
//  cross-coupled. OMS only: the KS-25 mains read 0. The OMS gimbal has RANGE 5 deg and RESPONSESPEED 10.
//  gmb_lock is logged because kOS returns a hard 0 whenever the gimbal is locked (the source is
//  gimbal.gimbalLock ? 0 : gimbal.gimbalAnglePitch), a column of zeros indistinguishable from no control demand.
gmbInit().
IF NOT GMB_HAVE {
    suLine("*** NO OMS GIMBAL: gmb_* log columns read 0").
}

// Handles on the body flap and the elevons, resolved once at load (GETMODULE on every log row would be
// wasteful, and the part list does not change while the program runs). ELEV_MOD is the single handle the log
// column reads; ELEV_MODS is the set the trim drives: symmetric trim has to move all four elevons together.
surfInit().
// Report the count: this orbiter carries FOUR elevons (two inner, two outer), and biasing a subset would
// produce a roll moment rather than pure pitch. Nothing else would reveal a missed part: a partial set still
// trims, just asymmetrically, and the log would show elev_trim moving normally.
IF ELEV_MODS:LENGTH <> 4 {
    suLine("*** " + ELEV_MODS:LENGTH + " ELEVONS FOUND, 4 EXPECTED").
    suLine("*** Trim would be asymmetric and roll the orbiter").
    suLine("*** Check the part titles against Elevon").
    WAIT 3.
}
IF NOT FLAP_HAVE {
    suLine("*** NO BODY FLAP: pitch trim will not run").
    WAIT 2.
}
IF GMB_HAVE AND ELEV_MODS:LENGTH = 4 AND FLAP_HAVE { suLine("Vehicle is GO"). }   // the gimbal, 4 elevons, the flap

IF STEER_CSV {
    SET STEERINGMANAGER:WRITECSVFILES TO TRUE.
    suLine("Steering PID CSVs ON: all 6 loops").
    suLine("  in GameData/kOS/Plugins/PluginData/kOS").
    suLine("  a new set per vessel load: one entry only").
    WAIT 3.
}

// Apply the bias once, at load. Deploy must be ON for the angle to have any effect.
IF FLAP_BIAS > -900 AND FLAP_HAVE {
    // Order matters: deploy first, then the angle. KSP exposes the angle slider only on a deployed surface;
    // while deploy is FALSE every angle write bounces.
    surfDeploy(FLAP_MOD).
    WAIT 0.5.
    surfSetAng(FLAP_MOD, FLAP_BIAS).
    WAIT 0.5.
    // Verify, do not assume: a custom axis bind overwrites SETFIELD every tick, silently (the flap twitches and
    // reverts while the readback says 0). If a bind is present, this says so before the entry.
    LOCAL gotD IS surfDep(FLAP_MOD).
    LOCAL gotA IS surfGetAng(FLAP_MOD).
    LOCAL fbLine IS "Flap bias: set " + ROUND(FLAP_BIAS, 1) + ", reads " + ROUND(gotA, 2) + " deg".
    IF NOT gotD OR ABS(gotA - FLAP_BIAS) > 1 {
        suLine(fbLine + (CHOOSE "" IF gotD ELSE ", undeployed")).
        suLine("*** FLAP BIAS DID NOT TAKE: not an experiment").
        suLine("*** An axis group may hold the flap: unbind it").
        WAIT 5.
    } ELSE {
        suLine(fbLine + ": holds").
    }
    WAIT 2.
} ELSE IF FLAP_BIAS > -900 {
    suLine("*** FLAP BIAS NOT APPLIED: no body flap found").
    WAIT 3.
}

IF HAS_ACCELEROMETER {
    IF accFitted() {
        suLine("Accelerometer fitted: aero_* columns live").
    } ELSE {
        SET HAS_ACCELEROMETER TO FALSE.
        suLine("*** NO ACCELEROMETER: the switch forced FALSE").
        suLine("*** aero_* columns read 0; fd_drag/fd_lift fine").
        WAIT 3.
    }
}

// Non-gravitational (aerodynamic + thrust) acceleration, m/s^2: lib_vehicle.ks's aeroVec.
// Gravity is computed, not sensed: SHIP:SENSORS:GRAV is stale, frozen at the value it held when the script
// started, so ACC - GRAV would carry a spurious upward residual equal to the change in g since then. That residual
// is easy to misread as aerodynamics (a vertical closure error, an apparent need for a larger lift). mu/r^2 is
// exact, free and needs no part: only the accelerometer is needed.
// ============================================================================
//  AERO BY FINITE DIFFERENCE -- no accelerometer part required (lib_vehicle.ks's FD_*)
// ============================================================================
//  dv/dt gives the TOTAL inertial acceleration, gravity + aero. Gravity is computed analytically (the aeroVec
//  route, because SENSORS:GRAV is stale), so subtracting it leaves the aero vector, the same quantity
//  SENSORS:ACC provides, from a vehicle with no accelerometer fitted. Drag is the component along -v_rel and
//  lift is the perpendicular residual.
//  Averaged over FD_MIN_DT, not one tick: aero acceleration ranges from 0.06 m/s^2 at 79 km to 24 at 40 km, and
//  a single 0.02 s difference of a 3600 m/s velocity has a float resolution floor around 0.021 m/s^2. Over 1 s
//  the floor drops to 0.0004. Drag changes slowly, so the averaging costs nothing.
//  RCS is the contaminant: thruster pulses (0.5-2 m/s^2) are real acceleration and appear in dv/dt like aero.
//  They can only be rejected, not subtracted (rcs_on is the system toggle, not thruster firing): FD_JUMP flags
//  samples whose magnitude jumped implausibly between windows, to be discarded offline.

// Record an event message, with a time stamp.
FUNCTION noteEvent {
    PARAMETER msg.
    LOCAL stamp IS "T+" + ROUND(MISSIONTIME) + "  ".
    // and in a text file beside the log: the console stays blank during the entry
    IF _log_filePath <> "" { LOG stamp + msg TO _log_filePath:REPLACE(".csv", "_events.txt"). }
}


// --- THE PREDICTOR (lib/entry_predict.ks; its names carry the EPR_ prefix) ---------------------------------
// entry_predict.ks carries a forward trajectory integrator and a bank solver. What flies is its reference
// family and eprGuidStep (GUID_SRC "epr", below); the bank solver is not run in flight (the deorbit planner
// uses it).
// --- WHICH GUIDANCE FLIES THE VEHICLE --------------------------------------------------------
//  "epr": the reference family flies it: eprGuidStep turns the family into the bank each guidance cycle by
//        table lookup (Phase 3). Any other value, or a family that is not ready, takes Phase 3's fallback
//        bank hold instead. The log's guid_src reads 1 for "epr".
GLOBAL GUID_SRC IS "epr".

GLOBAL EPR_SHADOW_BUDGET IS 25.  // the predictor's solve budget: RK2 steps per call (twice that many acceleration evaluations); 25 flies acceptably, 120 starves the steering of its instruction budget

// WHAT THE PREDICTOR MUST BE AIMED AT: a point it can arrive at. eprPredict terminates at the TAEM interface
// (12 km altitude or 900 m/s, the pair that ends the Phase 3 loop), so a target beyond that horizon (the runway
// threshold) makes the solver report sat = "low" on every solve and command bank 0.
// EPR_TAEM_BACK_M walks the aim back up the approach from the FTP. It is 0: the entry aims AT the FTP, because
// the FTP range is the orbiter's own handover geometry and the glideslope is matched with the aim at that point.
GLOBAL EPR_TAEM_BACK_M IS 0.
// If a bias shows up in the logged data, check first whether the FTP range wants adjusting rather than a
// correction bolted on top of it. A margin need only exceed the model's noise (about 3 km of scatter), not the
// vehicle's remaining control.

GLOBAL ROT_LNG_SIGN       IS -1.   // Kerbin spins EAST, so a fixed inertial direction's surface
                                   //   longitude DECREASES over time -> subtract the rotation.
                                   //   Flip to +1 if the timed pass comes out east/west of KSC.

// --- entry guidance (Phase 3) ---
GLOBAL ENTRY_ALT        IS 80000.  // Kerbin atmosphere edge (m)
GLOBAL WARP_STOP_ALT    IS 90000.  // settle out of warp at this altitude during the coast (m)

GLOBAL WARP_STOP_LEAD_S   IS 30.   // s before the entry interface at which the coast settles out of warp (a time, not an altitude); covers the warp unwind and the pre-entry config
GLOBAL WARP_MARGIN_M      IS 3000.  // m above ENTRY_ALT: the rails warp ends there at the latest, so the entry never begins inside the atmosphere
GLOBAL WARP_REACT_S       IS 5.     // real s the rate in use must leave before ENTRY_ALT + WARP_MARGIN_M at the current descent rate (warpAltCap): KSP's rate ramp-down plus the loop's own lag, with margin
GLOBAL WARP_FLOOR_M       IS 1000.  // m above ENTRY_ALT below which warp always stops, whatever the time solve says (a bound if timeToEntryAlt returns nonsense)
GLOBAL fbSign IS 0.                // fallback bank-hold sign latch (0 = not yet chosen)
GLOBAL fbRev  IS 0.                // fallback reversal count, for the deadband schedule
GLOBAL FAM_BUILD_BUDGET IS 400.    // RK2 steps per eprFamRun call during the pre-warp build (generous: nothing else competes for the tick here)
GLOBAL FAM_BUILD_MAX_S  IS 420.    // s of REAL time before the build gives up (throughput spans 30 to 471 steps/s across scenes)
GLOBAL HANDOVER_ALT     IS 12000.  // stop auto-guidance, hand to pilot (m)
GLOBAL NOMINAL_BANK     IS 45.     // the fallback's bank hold (deg) when the plan gives none (Phase 3);
                                   //   a plan's own bank replaces it (fbBank, Phase 3)
GLOBAL MAX_BANK         IS 85.     // bank ceiling for max energy bleed (deg)
GLOBAL BANK_RATE        IS 5.      // max commanded bank slew (deg/s); 5 matches EPR_ROLL_RATE_LIMIT, which the predictor integrates every reversal on
GLOBAL BANK_ACCEL_MAX   IS 4.      // deg/s^2: cap on how fast the commanded bank RATE may change, so a reversal never arrives as a step (at 4, +5 to -5 takes 2.5 s, which the yaw axis can follow)
GLOBAL BANK_LEVEL_HI    IS EPR_BANK_STOP_SPEED.  // start easing toward wings-level at this speed (the shared constant: the profile grid's lower bound and the rollout start cannot drift apart)
GLOBAL BANK_LEVEL_LO    IS 762.    // fully level by this speed (the TAEM handoff); equal to BANK_LEVEL_HI, so the level-out is a step at 762 (EPR_BANK_STOP_SPEED zeroes the bank there already) and the slew eases the roll
GLOBAL BANK_RATE_NOW    IS 0.      // the commanded bank rate actually in effect, carried between
                                   //   ticks so BANK_ACCEL_MAX can limit its change
GLOBAL BANK_SOFT_TIME   IS 6.      // ramp the rate cap up over this many s at entry start so the opening bank
                                   //   (rolling from rest) eases in; set small/0 to disable. Reversals run full-rate.

// Reversal loft: no compensation is applied. A roll reversal swings the ship through 0 bank, where lift is briefly
// fully vertical and adds downrange. The real orbiter overbanks about 20 deg for roughly 10 s after a reversal for
// this reason (USA005512); the predictor has no equivalent term.

// THE DRAG FILTER (FD_DRAG_TAU, s; 0 = unfiltered): the bank loop reads the measured drag through a first-order filter of
// this time constant. FD_DRAG is a finite difference of the orbital velocity; the RCS jets' push used to show in it as
// drag (a FAR entry: within 0.5 % of its trend with no roll, 3 % and up to 10 % off while rolling), and at 21 deg of bank
// a m/s^2 (K_HDOT x K_BANK_HDOT) each roll's artefact commanded the next, a ~4 s limit cycle that a 6 s filter damped
// (offline: bank jitter 2.7 -> 1.3 deg rms). fdSample now takes the jets' push out (the addon's RCSDV; the log's
// fd_rcs), so both installs fly the raw drag; 6 under FAR brings the filter back.
// IN PHYSICS WARP the samples scatter more (4x: about twice 1x's, from the coarser ticks) and each one steps the bank
// command (up to 1.5 deg at 4x), so the filter's time constant is the larger of FD_DRAG_TAU and FD_DRAG_TAU_W s per
// warp step above 1x (2x 1 s, 3x 2 s, 4x 3 s; fdDragTau). Offline (the guidance every 0.4 s, a 5 % sample scatter):
// the bank's 2-10 s jitter 3.2 deg rms unfiltered, 2.0 at 2 s, 1.4 at 4 s, against 1.9 at 1x's scatter; the miss at
// the TAEM interface within 1.2 km. 0 = no warp filter.
GLOBAL FD_DRAG_TAU IS 0.
GLOBAL FD_DRAG_TAU_W IS 1.
GLOBAL fdDragF     IS -1.
GLOBAL fdDragFN    IS -1.
FUNCTION fdDragTau {
    IF KUNIVERSE:TIMEWARP:MODE = "PHYSICS" AND KUNIVERSE:TIMEWARP:RATE > 1 {
        RETURN MAX(FD_DRAG_TAU, FD_DRAG_TAU_W * (KUNIVERSE:TIMEWARP:RATE - 1)).
    }
    RETURN FD_DRAG_TAU.
}
FUNCTION fdDragFilt {
    IF FD_N <> fdDragFN {
        SET fdDragFN TO FD_N.
        LOCAL tau IS fdDragTau().
        IF fdDragF < 0 OR tau <= 0 { SET fdDragF TO FD_DRAG. }
        ELSE { SET fdDragF TO fdDragF + (FD_DRAG - fdDragF) * FD_DT / (tau + FD_DT). }
    }
    RETURN fdDragF.
}

// AoA schedule (Phase 3 back end): hold AOA_HIGH at/above AOA_HIGH_SPEED,
// ramp linearly to AOA_LOW at AOA_LOW_SPEED, then hand over to TAEM.
GLOBAL AOA_HIGH       IS 40.    // angle of attack (deg) at/above AOA_HIGH_SPEED
GLOBAL AOA_LOW        IS 15.    // angle of attack (deg) at AOA_LOW_SPEED
GLOBAL AOA_HIGH_SPEED IS 2000.  // surface speed (m/s) for AOA_HIGH -- Mach 6
GLOBAL AOA_LOW_SPEED  IS 762.   // surface speed (m/s) for AOA_LOW; entry guidance ends here -> TAEM
// A deviation: the FSSR ends entry on velocity alone (STS 83-0001-34: "If VE < V_TAEM, then EG_END = TRUE", V_TAEM
// 2500 ft/s). Here a long entry still above AOA_LOW_SPEED inside TAEM_SW_KM of the threshold goes to TAEM there, where
// S-turns and the speedbrake can still shed the energy (a 2EO TAL crossed 80 km at Mach 3.8 and reached the runway at
// Mach 2.9). Not above TAEM_SW_MACH: taem_sim took that flight's states at Mach 3.5-4.0 (40-100 km) to the A/L
// interface every time; above it TAEM is unflown and its low alpha unchecked for heating. FALSE = velocity only.
GLOBAL TAEM_SW_ON   IS TRUE.
// TAEM_SW_KM: the nominal entries reach 762 m/s 43-62 km from the threshold (a few 70-94 km), so 80 km cut nearly every
// one short at ~950 m/s (stock and FAR entries alike: all BY RANGE at 80 km, 887-955 m/s). 35 km stays clear of them
// and still catches the short ones (762 m/s at 14-22 km) near Mach 3.
GLOBAL TAEM_SW_KM   IS 35.     // km to the threshold (the nominal hand-overs: 43-62 km at 762 m/s)
GLOBAL TAEM_SW_MACH IS 4.0.    // Mach: no switch above
GLOBAL TAEM_SW_HIT  IS FALSE.
FUNCTION taemRngSw {
    IF NOT TAEM_SW_ON OR TAEM_SW_HIT { RETURN TAEM_SW_HIT. }
    IF SHIP:VELOCITY:SURFACE:MAG < AOA_LOW_SPEED OR machNow() > TAEM_SW_MACH { RETURN FALSE. }
    LOCAL dk IS groundDist(SHIP:GEOPOSITION, RWY_THRESH) / 1000.
    IF dk >= TAEM_SW_KM { RETURN FALSE. }
    SET TAEM_SW_HIT TO TRUE.
    noteEvent("ENTRY -> TAEM BY RANGE: " + ROUND(dk, 1) + " km to " + RWY_NAME + ", Mach " + ROUND(machNow(), 2)
              + ", " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s, h " + ROUND(ALTITUDE / 1000, 1) + " km").
    RETURN TRUE.
}

// --- S-turn geometry: the MSP and the energy lines (logged only) ------
// The Manual Switchover Point (MSP) is the handover point: ST_MSP_BACK_M up-track of the HAC-in-point ALONG the
// target path (ship -> HAC entry), at V_MSP = 100 m/s IAS. R_GO is the distance still to fly along that path to
// the MSP, hitting 0 at the switchover. The log records e (specific energy, MJ/kg, from the ACTUAL speed) vs
// range-to-go to the MSP, with three constant-glideslope reference lines fanning out from eMSP: HEL (21 deg) /
// IEL (20 deg) / LEL (19 deg), and the energy and range predicted 10 s ahead (ST_EPRED, ST_RPRED).
// Nothing here commands the vehicle: the values are only logged.
GLOBAL ST_MSP_BACK_M  IS 5000.   // MSP sits this far up-track of the HAC entry along the target path (m)
GLOBAL ST_GS_HEL      IS 21.     // High Energy Line glideslope (deg): command S-turn if the predictor is above
GLOBAL ST_REF_IAS     IS 100.    // reference IAS (m/s) for the lines, converted to TAS at altitude
GLOBAL ST_MSP_ALT     IS 0.      // MSP altitude ASL (m); no live code sets it
GLOBAL ST_EDOT        IS 0.      // smoothed specific-energy rate (MJ/kg/s)
GLOBAL ST_RDOT        IS 0.      // smoothed range-to-go rate (km/s)

GLOBAL ST_SCALE_H     IS 6558.  // JNSQ density scale height (m) over 0-20 km: rho/rho0 = e^(-h/H), measured as rho = 2q/v_srf^2 from the entry logs, not from the pressure curve (this feeds a density model); tune to calibrate

GLOBAL ST_INTERCEPT_RGO IS MAX((GS_ACQ_BRK_M - ST_MSP_BACK_M) / 1000, 1).   // HEL-intercept range (km) = the 12/20 kink (=25)

// ---- ACQ-phase tracker (cooked steering, S-turn-DONE -> MSP, then manual) --------------------
// Flies the acquisition leg down to the MSP with two cooked-steering params (bank, AoA), reusing
// entrySteer() (which reads bankNow/entryAoaCmd). BANK nulls the course/heading deviation (localizer);
// PITCH is a 2-servo stack -- OUTER maps glideslope deviation to a target descent angle (clamped per
// leg), INNER PIDs the measured descent angle to that target via AoA. Yields to the S-turn while it is
// ACTIVE, resumes when it is DONE, releases to the pilot at the MSP.
GLOBAL ACQ_AP_MODE    IS "OFF".    // OFF / ACTIVE / DONE
GLOBAL acqBankNow     IS 0.        // rate-limited bank command (deg)
GLOBAL acqGlideTgt    IS 0.        // OUTER servo output: target descent angle (deg)
GLOBAL acqGlideNow    IS 0.        // low-passed measured descent angle (deg)
GLOBAL acqPitchCmd    IS 0.        // INNER servo output: commanded pitch attitude from the horizon (deg)
GLOBAL acqYawCmd      IS 0.        // YAW servo output: commanded yaw offset (deg)
GLOBAL acqBetaNow     IS 0.        // low-passed measured sideslip (deg)
GLOBAL ST_AP_MODE       IS "ARMED". // "ARMED" (watching) / "ACTIVE" (flying) / "DONE" (finished -> manual)
GLOBAL ST_THETA         IS 0.      // last heading-weave theta (deg): ground track - target path
GLOBAL ST_AOA_CMD       IS 0.      // last commanded AoA (deg) from the glide servo
GLOBAL ST_GLIDE_TGT     IS 0.      // last target glide angle (deg)
GLOBAL ST_GLIDE_NOW     IS 0.      // last actual descent angle (deg)
// S-turn state (no live code sets these: they keep their initial values):
GLOBAL ST_E             IS 0.      // current specific energy (MJ/kg)
GLOBAL ST_RGO_NOW       IS 0.      // current range-to-go to the MSP (km)
GLOBAL ST_EPRED         IS 0.      // predicted energy 10 s ahead (MJ/kg)
GLOBAL ST_RPRED         IS 0.      // predicted RGO 10 s ahead (km)

// --- the airspeed for the entry log's "ias" column ---
// sqrt(2*Q/rho0): an equivalent airspeed (no compressibility), rho0 = the sea-level density. It has
// no readout on the displays.
GLOBAL RHO0     IS 1.2231.   // Kerbin sea-level air density (kg/m^3)

// ----------------------- HELPER FUNCTIONS ----------------------------

// Clamp val into [lo, hi].
FUNCTION clamp { PARAMETER val, lo, hi. RETURN MAX(lo, MIN(hi, val)). }

FUNCTION norm180 {
    PARAMETER x.
    UNTIL x <= 180  { SET x TO x - 360. }
    UNTIL x > -180  { SET x TO x + 360. }
    RETURN x.
}

// Great-circle distance (m) between two GeoCoordinates.
FUNCTION groundDist {
    PARAMETER a, b.
    LOCAL la IS a:LAT. LOCAL lo IS a:LNG.
    LOCAL lb IS b:LAT. LOCAL lob IS b:LNG.
    LOCAL h IS SIN((lb - la) / 2)^2
             + COS(la) * COS(lb) * SIN((lob - lo) / 2)^2.
    RETURN 2 * SHIP:BODY:RADIUS * ARCSIN(SQRT(MIN(1, h))) * CONSTANT:DEGTORAD.
}

// Initial compass bearing (deg, 0=N, 90=E) from GeoCoordinate a to b.
FUNCTION bearing {
    PARAMETER a, b.
    LOCAL dLon IS b:LNG - a:LNG.
    LOCAL y IS SIN(dLon) * COS(b:LAT).
    LOCAL x IS COS(a:LAT) * SIN(b:LAT) - SIN(a:LAT) * COS(b:LAT) * COS(dLon).
    RETURN ARCTAN2(y, x).
}

// Forward geodesic: the point distM metres from `origin` along surface bearing `brngDeg` (deg from north,
// clockwise); spherical destination formula (kOS trig is in degrees).
FUNCTION destGeo {
    PARAMETER origin, brngDeg, distM.
    LOCAL ad  IS (distM / SHIP:BODY:RADIUS) * CONSTANT:RADTODEG.   // angular distance, deg
    LOCAL la1 IS origin:LAT.
    LOCAL lo1 IS origin:LNG.
    LOCAL la2 IS ARCSIN(SIN(la1) * COS(ad) + COS(la1) * SIN(ad) * COS(brngDeg)).
    LOCAL lo2 IS lo1 + ARCTAN2(SIN(brngDeg) * SIN(ad) * COS(la1),
                               COS(ad) - SIN(la1) * SIN(la2)).
    RETURN LATLNG(la2, lo2).
}

// Live entry steering: rebuilds the AoA-hold attitude (rolled by the commanded bank) from the CURRENT velocity
// each call. It sits behind LOCK STEERING, so kOS re-evaluates it every physics tick and the autopilot keeps
// flying while the main loop is busy (building a GUI). Reads entryAoaCmd and bankNow.
// THE ENTRY SPEEDBRAKE. The split rudder opens to EPR_SB_HINGE below EPR_SB_V m/s of relative speed, ramped over
// about 60 s to EPR_SB_V_FULL (a ramp, the orbiter's shape: a step gives a 0.78 deg sideslip blip), and stays there
// to the handover, where TAEM's DAP picks it up bumplessly (both halves at 32.5 a side, deploy TRUE): never
// un-deploy a half or press AG3 after this. The constants live in entry_predict.ks with the drag model's term
// (eprSbFrac), so EPR_SB_ON FALSE turns off both. The hinge is 65, not the orbiter's 81: above 65 the sideslip grows.
// THE ACTUATOR: the two halves are set directly, the ModuleControlSurface modules on parts named "rudder"
// (lib_dap's search), deploy TRUE, the deploy angle a side = hinge / 2.
GLOBAL ENTRY_SB_RUD IS LIST().       // the two rudder halves, found on the first write
GLOBAL ENTRY_SB_SET IS 0.            // the hinge last written (deg); 0 = as found (stowed): nothing is written above EPR_SB_V
FUNCTION entrySbUpdate {
    IF NOT EPR_SB_ON { RETURN. }
    LOCAL h IS EPR_SB_HINGE * clamp((EPR_SB_V - SHIP:VELOCITY:SURFACE:MAG) / (EPR_SB_V - EPR_SB_V_FULL), 0, 1).
    IF ABS(h - ENTRY_SB_SET) < 0.5 { RETURN. }
    IF surfListRefind("sbrud") { ENTRY_SB_RUD:CLEAR(). }   // A splashdown's rebuild: found again below
    IF ENTRY_SB_RUD:LENGTH = 0 {
        FOR m IN SHIP:MODULESNAMED(SURF_MN) {
            IF m:PART:NAME:TOLOWER:CONTAINS("rudder") { ENTRY_SB_RUD:ADD(modReg(m, ENTRY_SB_RUD:LENGTH)). }
        }
        surfListMark("sbrud").
        IF ENTRY_SB_RUD:LENGTH <> 2 {
            SET EPR_SB_ON TO FALSE.
            noteEvent("entry speedbrake OFF: " + ENTRY_SB_RUD:LENGTH + " rudder halves found, not 2").
            RETURN.
        }
        noteEvent("entry speedbrake opening at " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s, M" + ROUND(machNow(), 2) + " (to " + EPR_SB_HINGE + " by " + EPR_SB_V_FULL + " m/s)").
    }
    IF NOT (surfFrozen(ENTRY_SB_RUD[0]) OR surfFrozen(ENTRY_SB_RUD[1])) {      // A rudder half failed = no speedbrake (the good half is the rudder's)
        IF FAR_ON { surfSetAng(ENTRY_SB_RUD[0], h / 2). surfSetAng(ENTRY_SB_RUD[1], h / 2, -1). }
        ELSE { FOR m IN ENTRY_SB_RUD { IF modLive(m) AND NOT surfFrozen(m) { m:SETFIELD("deploy", TRUE). m:SETFIELD("deploy angle", h / 2). } } }
    }
    SET ENTRY_SB_SET TO h.
    SET sbThrottle TO 1 - h / 98.6.   // the log's sb_throttle (0 = full 98.6, 1 = stowed); nothing else reads it in Phase 3
}

// THE ENTRY'S STEERING GAINS. At the kOS defaults the bank runs 5-7 deg behind the 5 deg/s reversal ramp (the
// attitude loop's KP 1: target rate = KP x the angle error) while the steering's outputs never pass 0.95 and
// sideslip stays under 0.3 deg. KP 1.5 with the torque loop's settling time at 1.5 s raises the sideslip and the
// RCS use, so both stay at the defaults. Set at the entry's steering lock; the values found there are put back
// before landRun (which flies no cooked steering).
GLOBAL ENTRY_STEER_KP IS 1.       // pitch + roll rotational-velocity PID KP (the kOS default 1; 1.5 raises the sideslip and the RCS use)
GLOBAL ENTRY_STEER_TS IS 2.       // pitch + roll torque settling time, s (the kOS default 2: see ENTRY_STEER_KP)
GLOBAL ENTRY_STEER_WAS IS LIST().
FUNCTION entrySteerGains {
    PARAMETER on.
    IF on {
        SET ENTRY_STEER_WAS TO LIST(STEERINGMANAGER:PITCHPID:KP, STEERINGMANAGER:ROLLPID:KP,
                                    STEERINGMANAGER:PITCHTS, STEERINGMANAGER:ROLLTS).
        SET STEERINGMANAGER:PITCHPID:KP TO ENTRY_STEER_KP.
        SET STEERINGMANAGER:ROLLPID:KP TO ENTRY_STEER_KP.
        SET STEERINGMANAGER:PITCHTS TO ENTRY_STEER_TS.
        SET STEERINGMANAGER:ROLLTS TO ENTRY_STEER_TS.
    } ELSE IF ENTRY_STEER_WAS:LENGTH = 4 {
        SET STEERINGMANAGER:PITCHPID:KP TO ENTRY_STEER_WAS[0].
        SET STEERINGMANAGER:ROLLPID:KP TO ENTRY_STEER_WAS[1].
        SET STEERINGMANAGER:PITCHTS TO ENTRY_STEER_WAS[2].
        SET STEERINGMANAGER:ROLLTS TO ENTRY_STEER_WAS[3].
    }
}
FUNCTION entrySteer {
    LOCAL velDir IS SHIP:VELOCITY:SURFACE:NORMALIZED.
    LOCAL upDir  IS (-SHIP:BODY:POSITION):NORMALIZED.
    LOCAL upPerp IS (upDir - VDOT(upDir, velDir) * velDir):NORMALIZED.
    LOCAL aoaAim IS (COS(entryAoaCmd) * velDir + SIN(entryAoaCmd) * upPerp):NORMALIZED.
    LOCAL bankRot IS ANGLEAXIS(bankNow, velDir).
    LOCAL topAxis IS bankRot * upDir.
    LOCAL noseAim IS bankRot * aoaAim.
    IF entrySlipCmd <> 0 { SET noseAim TO ANGLEAXIS(entrySlipCmd, topAxis) * noseAim. }   // rudder yaw about the (banked) top axis -- S-turn glide assist
    RETURN LOOKDIRUP(noseAim, topAxis).
}

// --- last-action history (2 deep) ------------------------------------
// Each discrete step calls setAction("..."), which shifts the current entry into PREV_ACTION and stores the new
// one in LAST_ACTION. Both are shown on the live display.
GLOBAL LAST_ACTION IS "startup".
GLOBAL PREV_ACTION IS "startup".
FUNCTION setAction {
    PARAMETER act.
    SET PREV_ACTION TO LAST_ACTION.
    SET LAST_ACTION TO act.
}




// Rotation-corrected sub-point of the ship at a future universal time, as a LATLNG in the surface frame AT THAT
// TIME. POSITIONAT gives the inertial position and GEOPOSITIONOF maps it using the body's CURRENT rotation, so the
// longitude is corrected for how far the body will have spun by then (ROT_LNG_SIGN sets the direction); latitude
// is unaffected. groundDist uses sin(half-difference), so the longitude is normalised only for display.
FUNCTION subPointGeo {
    PARAMETER ut, tNow.
    LOCAL gp    IS SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, ut)).
    LOCAL omega IS 360 / SHIP:BODY:ROTATIONPERIOD.        // deg/s, eastward
    LOCAL lng   IS gp:LNG + ROT_LNG_SIGN * omega * (ut - tNow).
    SET lng TO MOD(MOD(lng + 180, 360) + 360, 360) - 180.   // normalise to -180..180
    RETURN LATLNG(gp:LAT, lng).
}

// Ground-track bearing (deg from north) at a future time: the rotation-corrected sub-point advanced a few seconds,
// so it captures ascending/descending and Kerbin's spin. It sets the reversed approach direction along which the
// FTP's backtrack leg is laid.
FUNCTION groundTrackBearing {
    PARAMETER ut, tNow.
    RETURN bearing(subPointGeo(ut, tNow), subPointGeo(ut + 5, tNow)).
}

// Build a runway's final target point: KEP_FTP_RANGE_NM (lib_kepler) back up the approach from the threshold,
// along the reversed ground-track bearing gtBrng of the chosen pass. No lateral offset: FSSR 3.2.2's side swap is
// something TAEM guidance does DURING TAEM (the HAC sits 7 nm from the threshold and the interface is
// KEP_FTP_RANGE_NM out), not a displacement baked into the entry's target. Back along the entry track, not the
// extended centreline: the two coincide on an aligned approach, but on an inclined one the track crosses the
// centreline at an angle, and the track is what the vehicle flies down.
FUNCTION buildFTP {                         // the FTP law (lib_kepler kepBuildFtp), THIS runway's
    PARAMETER thresh, gtBrng.                //   heading (RWY_HEADING) and short-field aim shift (RWY_AIM_DX)
    LOCAL f IS kepBuildFtp(thresh:LAT, thresh:LNG, gtBrng, RWY_HEADING, RWY_AIM_DX).
    RETURN LATLNG(f[0], f[1]).
}

// Commit the chosen runway: the runway BY NAME from hud/hud_runways.txt (lib_land ldLoadRunway), its
// threshold / heading / name, the FTP into KSC_TARGET (the plan's aim VERBATIM when given: the plan is
// the only source of the runway and the aim) and the FTP's range to the threshold. RWY_NAME is
// what landRun flies. An unknown name falls back to SLF33.
GLOBAL RWY_AIM_DX IS 0.                      // m: the runway's short-field aim shift (-2286 - x_ogs; VBG only)
FUNCTION applyRunway {
    PARAMETER rwy, gtBrng, aimOverride IS 0.
    LOCAL rw IS ldLoadRunway(rwy).
    IF rw:LENGTH = 0 {
        suLine("*** RUNWAY " + rwy + " NOT IN hud_runways.txt: SLF33").
        SET rw TO ldLoadRunway("SLF33").
    }
    SET RWY_THRESH  TO LATLNG(rw["lat"], rw["lon"]).
    SET RWY_HEADING TO rw["hdg"].
    SET RWY_NAME    TO rw["name"].
    SET RWY_AIM_DX  TO -2286 - rw["x_ogs"].
    SET KSC_TARGET  TO buildFTP(RWY_THRESH, gtBrng).
    IF NOT (aimOverride = 0) { SET KSC_TARGET TO aimOverride. }
    SET GLIDE_OFFSET_KM TO groundDist(KSC_TARGET, RWY_THRESH) / 1000.   // the FTP's range to the threshold
    suLine("Runway " + RWY_NAME + ", heading " + ROUND(RWY_HEADING, 1) + ", FTP " + ROUND(GLIDE_OFFSET_KM, 1) + " km out").
}

// The no-plan fallback: the OPS_SITE end whose landing heading is nearest the ground track
FUNCTION opsFallbackRunway {
    PARAMETER gtBrng.
    LOCAL best IS "SLF33".
    LOCAL bestE IS 1000.
    FOR nm IN LIST(OPS_SITE + "15", OPS_SITE + "33", OPS_SITE + "06", OPS_SITE + "24", OPS_SITE + "14", OPS_SITE + "32") {
        LOCAL rw IS ldLoadRunway(nm).
        IF rw:LENGTH > 0 {
            LOCAL he IS ABS(norm180(rw["hdg"] - gtBrng)).
            IF he < bestE {
                SET bestE TO he.
                SET best TO nm.
            }
        }
    }
    RETURN best.
}

// ===================== S-TURN LINES (logged only) ========================
// Specific energy (MJ/kg) on a reference line at range-to-go rgoKm from the MSP, flying ST_REF_IAS converted to
// TAS at that line's altitude. The line follows the SEGMENTED target path: its NEAR (inner) glideslope within the
// kink, dropping by (GS_ACQ_NEAR - GS_ACQ_FAR) beyond it. At rgo = 0 (the MSP) every line equals eMSP, so the
// three lines fan from a common point, with a kink where the 12/20 segmentation lands. Evaluated LIVE, with
// ST_MSP_ALT.
// Atmospheric density ratio rho/rho0 at an ASL altitude, an exponential with scale height ST_SCALE_H (tunable to
// calibrate the IAS -> TAS conversion).
FUNCTION stAirDensityRatio {
    PARAMETER altM.
    RETURN MAX(CONSTANT:E ^ (0 - altM / ST_SCALE_H), 0.0003).
}
FUNCTION stLineEfor {
    PARAMETER mspAltM, rgoKm, gsDeg.   // gsDeg = this line's NEAR (inner) slope; drops by (GS_ACQ_NEAR-GS_ACQ_FAR) past the kink
    LOCAL g0     IS SHIP:BODY:MU / SHIP:BODY:RADIUS^2.
    LOCAL brk    IS MAX((GS_ACQ_BRK_M - ST_MSP_BACK_M) / 1000, 0).        // RGO (km) where the 12/20 kink lands
    LOCAL nearKm IS MIN(MAX(rgoKm, 0), brk).
    LOCAL farKm  IS MAX(MAX(rgoKm, 0) - brk, 0).
    LOCAL altM   IS mspAltM + (nearKm * TAN(gsDeg) + farKm * TAN(gsDeg - (GS_ACQ_NEAR - GS_ACQ_FAR))) * 1000.
    LOCAL pr     IS stAirDensityRatio(altM).                              // rho/rho0 (exp model)
    LOCAL tas2   IS ST_REF_IAS^2 / pr.                                    // IAS -> TAS^2
    RETURN (0.5 * tas2 + g0 * altM) / 1000000.
}
FUNCTION stLineE {
    PARAMETER rgoKm, gsDeg.
    RETURN stLineEfor(ST_MSP_ALT, rgoKm, gsDeg).                          // the CURRENT approach's corridor
}

// Current indicated airspeed (m/s). Q already carries the true-density factor, so this is
// exact: IAS = sqrt(2*Q/rho0). DYNAMICPRESSURE is in atmospheres -> convert to Pa.
FUNCTION indicatedAirspeed {
    RETURN SQRT(2 * SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000 / RHO0).
}

// =====================================================================
//  PHASE 0  --  VALIDATION + DESCENT PROFILE + TARGET
// =====================================================================
CLEARSCREEN.

// The entry target (KSC_TARGET = the chosen runway's FTP) is set in Phase 0.2 by
// applyRunway() once the runway is selected -- see below.

// Bank angle ACTUALLY ACHIEVED, from vehicle attitude, as opposed to bankNow, the rate-limited COMMAND. Near an
// 85 deg bank the difference matters out of all proportion (cos(80)/cos(85) = 2.0, so five degrees of tracking
// error doubles the vertical component of lift). It is the angle about the surface-velocity vector between local
// vertical and the vehicle's dorsal direction, both projected perpendicular to velocity, so the comparison happens
// in the plane lift rotates in. Signed to match bankNow; if the log shows the two mirrored, flip BANK_ACT_SIGN
// rather than editing the maths.
GLOBAL BANK_ACT_SIGN IS 1.

FUNCTION bankActual {
    LOCAL vd IS SHIP:VELOCITY:SURFACE.
    IF vd:MAG < 1 { RETURN 0. }
    SET vd TO vd:NORMALIZED.
    LOCAL upP  IS VXCL(vd, SHIP:UP:VECTOR).
    LOCAL topP IS VXCL(vd, SHIP:FACING:TOPVECTOR).
    IF upP:MAG < 0.001 OR topP:MAG < 0.001 { RETURN 0. }
    SET upP  TO upP:NORMALIZED.
    SET topP TO topP:NORMALIZED.
    LOCAL sgn IS 1.
    IF VDOT(VCRS(upP, topP), vd) < 0 { SET sgn TO -1. }
    RETURN BANK_ACT_SIGN * sgn * VANG(upP, topP).
}

// --- logging state (exposed as globals so the delegates can read them) ---
GLOBAL bankNow     IS 0.   // current commanded bank angle (deg), set in Phase 3
GLOBAL entryAoaCmd IS AOA_HIGH.  // last commanded AoA (deg); read live by the steering lock (entrySteer)
GLOBAL entrySlipCmd IS 0.  // commanded sideslip/rudder (deg), read live by entrySteer; nonzero only during the S-turn yaw assist
GLOBAL entryStartT IS 0.   // TIME:SECONDS when Phase 3 began, for the soft-start ramp
GLOBAL logPhase    IS 0.   // 1 = deorbit burn, 3 = entry (0 = setup/transit)
GLOBAL logDownErr  IS 0.   // downrange error (m). NOTHING ASSIGNS IT or logCrossErr:
GLOBAL logCrossErr IS 0.   //   they stay so the log keeps its columns

// Master delegate lexicon. logconfig.txt selects which keys actually get
// written, so keep this superset and just edit the config per run.
LOCAL params IS LEXICON(
  "altitude",       { RETURN SHIP:ALTITUDE.             },
  "speed_srf",      { RETURN SHIP:VELOCITY:SURFACE:MAG. },
  "speed_orb",      { RETURN SHIP:VELOCITY:ORBIT:MAG.   },
  "vert_speed",     { RETURN SHIP:VERTICALSPEED.        },
  "periapsis",      { RETURN SHIP:PERIAPSIS.            },
  "apoapsis",       { RETURN SHIP:APOAPSIS.             },
  // SHIP:DYNAMICPRESSURE IS IN ATMOSPHERES. Every other consumer in this file converts it (machNow,
  // indicatedAirspeed, the "rho" column below); this column logs it raw, next to a "pressure" column in Pa and a
  // "rho" column in kg/m^3, so the unit cannot be told from the file (read as kPa, a q of 299 psf prints as 2.5).
  // Prefer "q_pa" for new configs.
  "dynpressure",    { RETURN SHIP:DYNAMICPRESSURE.      },   // ATM: the ascent configs read it
  "q_pa",           { RETURN SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000. },
  // The warp rate, because the tracker's behaviour depends on it. EPR_GS_CORR is PROPORTIONAL and carries no dt, so
  // its gains are warp-independent by construction; the PLANT is not: a coarser physics step makes hdotNow laggier
  // and lets eprBankSlew take bigger steps per tick, so a fixed proportional gain overshoots more. Paired with
  // fam_dt (= EPR_GS_DT) it separates clamp railing at EPR_TRK_MAX from a possible integral term in the tracker:
  // warp up -> dt up -> corr rails. In atmosphere only PHYSICS warp is available, so the rate alone identifies
  // the setting (1-4).
  "warp_rate",      { RETURN KUNIVERSE:TIMEWARP:RATE. },
  "throttle",       { RETURN THROTTLE.                  },
  "pitch",          { RETURN SHIP:FACING:PITCH.         },
  "yaw",            { RETURN SHIP:FACING:YAW.           },
  "roll",           { RETURN SHIP:FACING:ROLL.          },
  // ground distance from the vessel's sub-point to KSC (always valid)
  "dist_ksc",       { RETURN groundDist(SHIP:GEOPOSITION, KSC_TARGET). },
  // downrange (along-track) ground distance to KSC: great-circle distance
  // projected onto the direction of travel. + = KSC ahead, - = behind.
  "downrange_ksc",  { LOCAL u IS (-SHIP:BODY:POSITION):NORMALIZED.
                      LOCAL f IS VXCL(u, SHIP:VELOCITY:SURFACE):NORMALIZED.
                      LOCAL k IS VXCL(u, KSC_TARGET:POSITION):NORMALIZED.
                      RETURN groundDist(SHIP:GEOPOSITION, KSC_TARGET) * VDOT(f, k). },
  // The logger resolves field names against this table: a config asking for a field that is not
  // here is a broken log rather than a missing column, so a field leaves this table and the
  // logconfig files (logconfig_entry.txt, logconfig_entry_jnsq.txt) together.
  // --- rev-selection prediction snapshot (constant across the entry) ---
  // Nothing sets the pred_* / desc_lag_s / lead_time_s columns: they log their defaults (the rev
  // search's prediction snapshot). ftp_lat/lng give the aim point.
  "pred_cross_km",  { RETURN PRED_CROSS_KM. },
  "pred_lat",       { RETURN PRED_LAT.      },
  "pred_lng",       { RETURN PRED_LNG.      },
  "pred_tover_ut",  { RETURN PRED_TOVER_UT. },
  "pred_td_ut",     { RETURN PRED_TD_UT.    },
  "desc_lag_s",     { RETURN DESC_LAG_S.    },
  "lead_time_s",    { RETURN LEAD_TIME_S.   },
  "ftp_lat",        { RETURN KSC_TARGET:LAT. },
  "ftp_lng",        { RETURN KSC_TARGET:LNG. },
  // specific energy (J/kg): 1/2 v^2 + g h
  "energy",         { RETURN (1/2 * (SHIP:VELOCITY:SURFACE:MAG)^2) + 9.81 * SHIP:ALTITUDE. },
  // specific energy (MJ/kg) using the body's surface gravity.
  "energy_mj",      { RETURN (0.5 * SHIP:VELOCITY:SURFACE:MAG^2
                             + (SHIP:BODY:MU / SHIP:BODY:RADIUS^2) * SHIP:ALTITUDE) / 1000000. },
  // ground range to the RUNWAY (km): with energy_mj, the entry's energy against range.
  "range_runway_km",{ RETURN groundDist(SHIP:GEOPOSITION, RWY_THRESH) / 1000. },
  "bank_cmd",       { RETURN bankNow.     },
  // --- aero columns, for offline fitting -----------------------------
  // bank_act is the achieved bank; vert_speed is the single most useful column for the fit (the logconfig must
  // list it for it to reach the file): with it, lift can be FITTED from the normal equation
  //     m*v*dgam/dt = L*cos(bank) - m*g*cos(gam) + m*v^2*cos(gam)/r
  // instead of tuned against an altitude profile.
  "bank_act",       { RETURN bankActual().            },
  // Direct aero force measurement -- the only route that works hypersonically.
  // Zero unless HAS_ACCELEROMETER is set and an accelerometer part is aboard.
  "aero_drag",      { RETURN aeroAccel()[0]. },
  "aero_lift",      { RETURN aeroAccel()[1]. },
  // Orthonormal decomposition -- no projection assumption, closes the equations exactly.
  // aero_up is the one that settles the vertical balance; aero_side drives the turn rate
  // and so the crossrange. Sign of aero_side is whatever the e_up x e_h triad gives;
  // verify against the bank sign before relying on it.
  "aero_up",        { RETURN aeroFrame()[0]. },
  "aero_dr",        { RETURN aeroFrame()[1]. },
  "aero_side",      { RETURN aeroFrame()[2]. },
  // Mach and static pressure, so the aero tables can be re-indexed on Mach offline.
  "mach",           { RETURN machNow().         },
  "ep_phase",       { RETURN EPR_PH.       },
  // Solver internals: the published bank and miss cannot tell a real reachability limit from a bug. ep_rlong and
  // ep_rshort are the two bracket misses the verdict is computed from (signed, positive = beyond the aim).
  // What guidance thinks its own position is: compare gs_glat/glng against ship_lat/lng (the same instant), so any
  // difference is eprToGeo's error, and gs_rng against a great-circle from ship_lat/lng shows what it costs in range.
  "gs_glat",        { RETURN EPR_GS_GLAT. },
  "gs_glng",        { RETURN EPR_GS_GLNG. },
  "gs_rng",         { RETURN EPR_GS_RNG.  },
  "gs_trot",        { RETURN EPR_GS_TROT. },
  "gs_past",        { RETURN CHOOSE 1 IF EPR_GS_PAST ELSE 0. },
  "ep_rlong",       { RETURN EPR_RLONG. },
  "ep_rshort",      { RETURN EPR_RSHORT. },
  "ep_tgt_lat",     { RETURN EPR_TGT_LAT. },
  "ep_tgt_lng",     { RETURN EPR_TGT_LNG. },
  "ep_itime",       { RETURN EPR_IT. },
  "ep_term_alt",    { RETURN EPR_TERM_ALT. },
  "ep_term_vel",    { RETURN EPR_TERM_VEL. },
  "ep_term_why",    { RETURN EPR_TERM_WHY. },
  "ep_solve_dt",    { RETURN EPR_SOLVE_DT. },
  "ep_st_alt",      { RETURN EPR_ST_ALT. },
  "ep_st_vel",      { RETURN EPR_ST_VEL. },
  "ep_st_vs",       { RETURN EPR_ST_VS.  },
  "ep_st_lat",      { RETURN EPR_ST_LAT. },
  "ep_st_lng",      { RETURN EPR_ST_LNG. },
  "ep_st_hdg",      { RETURN EPR_ST_HDG. },
  // --- aero by finite difference, no accelerometer needed ---
  "fd_drag",        { RETURN FD_DRAG. },
  "fd_drag_f",      { RETURN fdDragF. },   // what the bank loop reads
  "fd_rcs",         { RETURN FD_RCSA. },   // the RCS jets' push along the drag axis, taken out of fd_drag
  "fd_lift",        { RETURN FD_LIFT. },
  "fd_mag",         { RETURN FD_MAG. },
  "fd_dt",          { RETURN FD_DT. },
  "fd_n",           { RETURN FD_N. },
  "fd_jump",        { RETURN FD_JUMP. },
  // Modelled drag from the tables, for the same state: fd_drag is a MEASUREMENT and this a PREDICTION, so their
  // difference is the aero table error.
  "fd_model_drag",  { LOCAL a IS SHIP:ALTITUDE.
                      LOCAL vr IS SHIP:VELOCITY:SURFACE:MAG.
                      LOCAL rho IS eprRho(a).
                      IF rho <= 0 OR vr < 1 { RETURN 0. }
                      // the model's own pseudo-Reynolds term, eprPrMult (the cube share)
                      RETURN eprCda(eprAoA(vr), eprMach(a, vr)) * (0.5 * rho * vr * vr)
                             * eprPrMult(rho * vr). },
  // --- SIDESLIP, the quantity actually being targeted ---
  //  Beta is the angle between the surface-relative velocity and the vehicle's plane of symmetry: positive means the
  //  airflow comes from the right. acq_beta belongs to the acquisition phase and reads zero through the entry, and
  //  gmb_yaw saturation says only that the yaw axis is working hard, not how far the nose is off the wind.
  "beta",           { LOCAL vs IS SHIP:VELOCITY:SURFACE.
                      IF vs:MAG < 1 { RETURN 0. }
                      RETURN ARCSIN(MAX(-1, MIN(1,
                             VDOT(vs:NORMALIZED, SHIP:FACING:STARVECTOR)))). },
  // and the yaw rate, since sideslip builds when the nose cannot follow the roll
  "yaw_rate",       { RETURN VDOT(SHIP:ANGULARVEL, SHIP:FACING:TOPVECTOR)
                             * CONSTANT:RADTODEG. },

  // --- the bank command chain, so the rate limiter can be checked rather than inferred ---
  //  bankNow is written by the entry slew and set to 0 at the handover. bank_rate is the rate the limiter ACTUALLY
  //  applies; bank_tgt is what it aims at. With both, the chain target -> rate -> command is visible end to end.
  "bank_rate",      { RETURN BANK_RATE_NOW. },
  "bank_lvl",       { LOCAL sp IS SHIP:VELOCITY:SURFACE:MAG.
                      IF sp > BANK_LEVEL_HI { RETURN 1. }
                      RETURN clamp((sp - BANK_LEVEL_LO)
                                   / MAX(BANK_LEVEL_HI - BANK_LEVEL_LO, 1), 0, 1). },

  // --- the guidance: which source flew, and what each stage contributed ---
  //  These separate the feedforward bank from the tracker's correction and from the lateral logic, so a bad miss
  //  can be attributed to one stage.
  "guid_src",       { RETURN CHOOSE 1 IF GUID_SRC = "epr" ELSE 0. },
  "trk_on",         { RETURN CHOOSE 1 IF TRK_ON ELSE 0. },
  "trk_err",        { RETURN TRK_ERR. },       // measured drag minus the reference
  "trk_corr",       { RETURN TRK_CORR. },      // the bank correction it produced
  "grd_have",       { RETURN CHOOSE 1 IF GRD_HAVE ELSE 0. },
  "grd_n",          { RETURN GRD_N. },
  "grd_vhi",        { RETURN GRD_VHI. },
  "grd_age",        { RETURN TIME:SECONDS - GRD_AGE. },   // seconds since the grid was built
  "gd_sign",        { RETURN GD_SIGN. },
  "gd_az",          { RETURN GD_AZ. },
  "gd_db",          { RETURN GD_DB. },
  "gd_rev",         { RETURN GD_REVERSALS. },

  // --- closed-loop pitch trim state ---
  "trim_ang",       { RETURN PTRIM_ANG. },
  "trim_sign",      { RETURN PTRIM_SIGN. },
  "elev_trim",      { RETURN ETRIM_ANG. },

  // --- applied control, from the OMS gimbal. see the notes at gmbInit above ---
  "gmb_pitch",      { IF NOT gmbLive() { RETURN 0. } RETURN GMB_ENG:GIMBAL:PITCHANGLE. },   // gmbLive on every gmb_* read
  "gmb_yaw",        { IF NOT gmbLive() { RETURN 0. } RETURN GMB_ENG:GIMBAL:YAWANGLE. },
  "gmb_roll",       { IF NOT gmbLive() { RETURN 0. } RETURN GMB_ENG:GIMBAL:ROLLANGLE. },
  // logged because a locked gimbal returns a hard 0 that looks like no demand
  "gmb_lock",       { IF NOT gmbLive() { RETURN -1. }
                      RETURN CHOOSE 1 IF GMB_ENG:GIMBAL:LOCK ELSE 0. },

  // No trim-investigation columns (flap_deploy/angle, elev_angle, flap_auth/elev_auth, ctl_pitch/yaw/roll,
  // ctl_perr/yerr/rerr): they cost per-tick delegate work. ctl_pitch is not what its name suggests: STEERINGMANAGER:
  // PITCHPID is a rotational VELOCITY loop whose output is rad/s, not deflection. Do not add it as a control measurement.
  "ep_st_klat",     { RETURN EPR_ST_KLAT. },
  "ep_st_klng",     { RETURN EPR_ST_KLNG. },
  "pressure",       { RETURN staticPressurePa(). },
  "aero_ld",        { LOCAL aa IS aeroAccel().
                      IF aa[0] <= 0.0001 { RETURN 0. }
                      RETURN aa[1] / aa[0]. },
  "rcs_on",         { IF RCS { RETURN 1. } RETURN 0. },
  "bank_err",       { RETURN bankActual() - bankNow.  },
  "mass",           { RETURN SHIP:MASS.               },
  "ship_lat",       { RETURN SHIP:GEOPOSITION:LAT.    },
  "ship_lng",       { RETURN SHIP:GEOPOSITION:LNG.    },
  "rho",            { LOCAL vv IS SHIP:VELOCITY:SURFACE:MAG.
                      IF vv < 1 { RETURN 0. }
                      RETURN 2 * SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000 / vv^2. },
  // These two are constant zero: nothing assigns logDownErr / logCrossErr. They stay as columns so the CSV schema
  // does not change under the analysis scripts.
  "downrange_err",  { RETURN logDownErr.  },
  "crossrange_err", { RETURN logCrossErr. },
  // What the family guidance knows, and what a display should plot:
  "fam_u",          { RETURN EPR_GS_U. },
  "fam_sat",        { RETURN CHOOSE 0 IF EPR_GS_SAT = "" ELSE (CHOOSE -1 IF EPR_GS_SAT = "low" ELSE 1). },
  "fam_derr",       { RETURN EPR_GS_DERR. },
  "fam_dref",       { RETURN EPR_GS_DREF. },
  "fam_corr",       { RETURN EPR_GS_CORR. },
  // SIGNED: EPR_GS_ROLLREF is a MAGNITUDE; the side lives in EPR_GS_SIGN. Unsigned, the display would borrow
  // bank_cmd's sign for its ROLL REF readout, wrong during a reversal. Multiplying here makes the side real
  // everywhere downstream.
  "fam_rollref",    { RETURN EPR_GS_SIGN * EPR_GS_ROLLREF. },
  "fam_az",         { RETURN EPR_GS_AZ. },
  "fam_rev",        { RETURN EPR_GS_REV. },
  "fam_reving",     { RETURN CHOOSE 1 IF EPR_GS_REVERSING ELSE 0. },
  // both drags, so the model can be checked against the vehicle without inference
  "fam_dnow",       { RETURN EPR_GS_DNOW. },
  "fam_dmeas",      { RETURN EPR_GS_DMEAS. },
  // the alpha modulation: the alpha command (-1 = the schedule) and the measured drag at the scheduled alpha
  "fam_acmd",       { RETURN EPR_GS_ACMD. },
  "fam_deq",        { RETURN EPR_GS_DEQ. },
  "fam_dt",         { RETURN EPR_GS_DT. },
  // the CG trim (cg_fore = the last measured CoM, m from the root part along fore; cg_tgt its target; monoprop units)
  "cg_fore",        { RETURN CG_TARGET_FORE + cgErrM. },
  "cg_tgt",         { RETURN CG_TARGET_FORE. },
  "mono_f",         { RETURN cgMonoF. },
  "mono_a",         { RETURN cgMonoA. },
  // a TAL's Nz limiter (TAL_V4N): the led Nz at the last drag sample and its limit alpha (-1 = none)
  "tal_nz",         { RETURN TAL_NZ_NOW. },
  "tal_nza",        { RETURN TAL_NZ_A. },
  // --- S-turn (Stage 2) telemetry, for gain tuning ---
  "st_mode",     { IF ST_AP_MODE = "ACTIVE" { RETURN 1. } IF ST_AP_MODE = "DONE" { RETURN 2. } RETURN 0. },
  "st_e",        { RETURN ST_E.        },
  "st_rgo",      { RETURN ST_RGO_NOW.  },
  "st_edot",     { RETURN ST_EDOT.     },
  "st_rdot",     { RETURN ST_RDOT.     },
  "st_epred",    { RETURN ST_EPRED.    },
  "st_rpred",    { RETURN ST_RPRED.    },
  "st_ehel",     { RETURN stLineE(ST_RGO_NOW, ST_GS_HEL).       },
  "st_ehel_int", { RETURN stLineE(ST_INTERCEPT_RGO, ST_GS_HEL). },
  "st_eerr",     { RETURN ST_E - stLineE(ST_RGO_NOW, ST_GS_HEL). },  // actual energy margin above the HEL (MJ/kg)
  "st_glide_tgt",{ RETURN ST_GLIDE_TGT. },
  "st_glide_now",{ RETURN ST_GLIDE_NOW. },
  "st_theta",    { RETURN ST_THETA.    },
  "st_aoa_cmd",  { RETURN ST_AOA_CMD.  },
  "st_yaw",      { RETURN entrySlipCmd. },   // commanded sideslip/rudder (deg) from the yaw glide assist
  "aoa_actual",  { RETURN VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE). },
  "acq_mode",     { RETURN ACQ_AP_MODE. },     // OFF / ACTIVE / DONE
  "acq_bank",     { RETURN acqBankNow.  },     // commanded bank (deg)
  "acq_glide_tgt",{ RETURN acqGlideTgt. },     // outer servo: target descent angle (deg)
  "acq_glide_now",{ RETURN acqGlideNow. },     // low-passed measured descent angle (deg)
  "acq_pitch_cmd",{ RETURN acqPitchCmd. },     // inner servo: commanded pitch from horizon (deg)
  "acq_beta",     { RETURN acqBetaNow.  },     // low-passed measured sideslip (deg)
  "acq_yaw_cmd",  { RETURN acqYawCmd.   },     // yaw servo: commanded yaw offset (deg)
  "sb_throttle", { RETURN sbThrottle. },              // 0 = full speedbrake, 1 = stowed
  "ias",         { RETURN indicatedAirspeed(). },
  "phase",          { RETURN logPhase.    }
).

// The log interval is short because the offline lift fit differentiates the path angle gamma, so its noise floor
// goes as 1/dt.
initLogFlight(0.2, params, "0:/logconfig_entry_jnsq.txt").   // log every 0.2 s using the entry config
IF _log_filePath <> "" { kmLogTo(_log_filePath:REPLACE(".csv", "_events.txt")). }
SET FL_LOG TO _log_filePath:REPLACE(".csv", "_events.txt").   // The failures' lines go to the events file ("" = no log)   // the warnings said so far, and every kmSay from now, in the events file
IF gmbLive() { noteEvent("OMS gimbal: " + GMB_ENG:TITLE). }   // the engine's full name: the events file, not the console
noteEvent(pfixLine()).                  // the pitch fix's switch (lib_vehicle PFIX_*): one line each entry
IF HO_MSG <> "" { noteEvent(HO_MSG). }   // the hand-off / the split-S's first lock: said now

// No jump-in detection: ops3q always starts on the coast. deorbit_plan.ks and shuttle_exec.ks do the deorbit, so
// by the time this runs the burn is always done.

// =====================================================================
//  PHASE 0.2 (OPS 6)  --  THE TAL SITE'S RUNWAY + THE AIM
// =====================================================================
// No deorbit plan in a TAL. The site comes from ops1q (ZZA, MRN or SNN). THE RUNWAY END is the site's PRIME END, chosen before
// flight as the orbiter's TAL runway was (by the winds), not in flight: ZZA30 at Zaragoza (three ZZA TAEM interface
// states flown to a stop in the sims: ZZA30 CLEAN in all 3, ZZA12 off-energy in 2 of 3: the overhead approach spends
// the energy the entry delivers to the FTP), MRN20 at Moron (the overhead end by the same geometry for an arrival
// from the west; not flown in the sims). talRwyWant (the third argument) forces an end. THE AIM = TAL_AIM_KM (a TAL; an
// RTLS / CONT: the FTP, FTP_BACK_KM) short of the site's centre on the great circle from the ENTRY INTERFACE point
// (eprKepToEI's conic coast, the build's own), handed to applyRunway as its aim.
GLOBAL PLAN_AIM IS 0.
GLOBAL TAL_SITES IS LEXICON(
    "ZZA", LIST(LATLNG(41.67024, -1.06107), "ZZA30", "ZZA12"),      // Zaragoza: the KK centre, the PRIME end, the other
    "MRN", LIST(LATLNG(37.17608, -5.61555), "MRN20", "MRN02"),      // Moron
    // Shannon: the KK centre; SNN23 the prime end by the same rule
    //   (the overhead end for an arrival from the south-west, as ZZA30 / MRN20; not flown in the sims)
    "SNN", LIST(LATLNG(52.6943, -8.9475), "SNN23", "SNN05")).       // Shannon
IF talMode = "RTLS" OR talMode = "SPLITS" {   // SPLITS: the RTLS's sites. An RTLS
    //   lands at the SLF; SLF33 = its prime end (offline, the GRTLS reaches TAEM 1.0-1.3 km higher on SLF33 than
    //   on SLF15 in all three cases); the third argument forces SLF15
    TAL_SITES:ADD("SLF", LIST(LATLNG(capeSlfMid()[0], capeSlfMid()[1]), "SLF33", "SLF15")).   // the midpoint of the thresholds (lib_cape: the Cape in place)
    // VBG: from SLC-6 ops1q hands off "VBG" = Vandenberg, the midpoint of the KK runway's thresholds; VBG32 = its
    //   prime end (offline, the 17 MECO states of an SLC-6 ascent sweep reach TAEM 0.6-4.8 km above the nominal
    //   energy on VBG32, 3.5 below to 0.5 above on VBG14, the corridor's floor EMIN 914 m below; TAEM OK 34 of 34);
    //   the third argument forces VBG14
    TAL_SITES:ADD("VBG", LIST(LATLNG(34.736902, -120.5842495), "VBG32", "VBG14")).
    IF talSiteKey <> "SLF" {
        IF talSiteKey <> "VBG" {
            suNote("*** OPS 6: an RTLS lands at the SLF or VBG: " + talSiteKey + " ignored").
            SET talSiteKey TO "SLF".
        }
    }
    grtlsContSet(0).                     // the RTLS's own I-loads (a CONT run earlier leaves its own set)
}
IF talMode = "RTLS" {   // THE REACH TEST (the header): short -> the crew's choice in the GRTLS loop
    SET RCH_SITE TO talSiteKey.
    LOCAL rchMeco IS hoGet("meco_ut", -1).
    LOCAL rchHow IS "".
    IF HO_REC:LENGTH = 0 {
        SET RCH_PRED TO rchPred(0).
        SET rchHow TO "no hand-off record: the state now as MECO's".
    } ELSE IF rchMeco >= 0 {
        SET RCH_PRED TO rchPred(TIME:SECONDS - rchMeco).
        SET rchHow TO "d moved back to MECO, " + ROUND(TIME:SECONDS - rchMeco, 1) + " s ago (ASC_HO meco_ut)".
    } ELSE {
        LOCAL rchDc IS TIME:SECONDS - HO_REC["ut"] + RCH_DT_HO.
        SET RCH_PRED TO MAX(rchPred(rchDc - RCH_DT_W), rchPred(rchDc + RCH_DT_W)).
        SET rchHow TO "MECO's time unknown: the larger of d moved back " + ROUND(rchDc - RCH_DT_W, 1) + " / "
                      + ROUND(rchDc + RCH_DT_W, 1) + " s".
    }
    SET RCH_T0 TO TIME:SECONDS.
    SET RCH_SHORT TO RCH_PRED < RCH_THR.
    SET RCH_BLUE0 TO hoGet("eo2", "") = "BLUE".
    noteEvent("OPS 6 RTLS REACH TEST (ours, ABORT's python fit) to " + RCH_SITE + ": TAEM EOW-EN predicted " + ROUND(RCH_PRED)
              + " m, the line "
              + ROUND(RCH_THR) + " m (" + rchHow + "): " + (CHOOSE ("SHORT -- GRTLS or BLUE on VERT SIT within "
              + RCH_PICK_S + " s, else BLUE") IF RCH_SHORT ELSE "GREEN, the GRTLS")
              + (CHOOSE "; BUT A 2ND SSME OUT CUT AT ONCE (ASC_HO eo2 BLUE): BLUE AT ONCE, no choice" IF RCH_BLUE0 ELSE "")).
}
IF talMode = "CONT" {   // CONT (a 2EO contingency: ECAL / BDA or BLUE): ops1q's
    //   hand-off RUNPATH("0:/ops6q.ks", "CONT", site | "NONE"). GREEN = an ELS site of hud_runways.txt (the table below =
    //   its thresholds), its end = the threshold NEARER the ship (the end landed on from this side; offline, BDA10 was
    //   TAEM OK at t2 146-162 where BDA28 was not); BLUE ("NONE", or no such site) = no site: the SLF's frame (unused),
    //   the bailout below Mach 1. The third argument forces a GREEN end.
    LOCAL contEls IS LEXICON(
        "BDA", LIST(LATLNG(32.3680887, -64.6999367), "BDA10", LATLNG(32.3587454, -64.6478984), "BDA28"),
        "NKT", LIST(LATLNG(34.8658695, -76.8369811), "NKT31", LATLNG(34.9263524, -76.9107243), "NKT13"),
        "DOV", LIST(LATLNG(39.1170632, -75.4469832), "DOV31", LATLNG(39.1434765, -75.4938498), "DOV13"),
        "YQX", LIST(LATLNG(48.9181060, -54.5666318), "YQX01", LATLNG(48.9623605, -54.5547519), "YQX19"),
        "YHZ", LIST(LATLNG(44.8670509, -63.5260895), "YHZ04", LATLNG(44.9371180, -63.4568241), "YHZ22"),
        "LGA", LIST(LATLNG(40.7679909, -73.8496049), "LGA30", LATLNG(40.7911352, -73.9004730), "LGA12"),
        "MRN", LIST(LATLNG(37.1549656, -5.6251938), "MRN02", LATLNG(37.1971928, -5.6059043), "MRN20"),
        "MYR", LIST(LATLNG(33.6561536, -78.9225205), "MYR35", LATLNG(33.7001088, -78.9337478), "MYR17"),
        "SNN", LIST(LATLNG(52.6891666, -8.9526353), "SNN05", LATLNG(52.7418278, -8.8413668), "SNN23"),
        "ZZA", LIST(LATLNG(41.6488586, -1.0114860), "ZZA30", LATLNG(41.6916263, -1.1106537), "ZZA12")).
    IF contEls:HASKEY(talSiteKey) {
        LOCAL ce IS contEls[talSiteKey].
        LOCAL near1 IS ce[0]:DISTANCE <= ce[2]:DISTANCE.
        SET TAL_SITES[talSiteKey] TO LIST(LATLNG((ce[0]:LAT + ce[2]:LAT) / 2, (ce[0]:LNG + ce[2]:LNG) / 2),
                                          CHOOSE ce[1] IF near1 ELSE ce[3], CHOOSE ce[3] IF near1 ELSE ce[1]).
        grtlsContSet(1).
    } ELSE {
        IF talSiteKey <> "NONE" { suNote("*** OPS 6 CONT: no ELS site " + talSiteKey + ": BLUE (no site)"). }
        SET TAL_SITES["SLF"] TO LIST(LATLNG(capeSlfMid()[0], capeSlfMid()[1]), "SLF33", "SLF15").
        SET talSiteKey TO "SLF".
        grtlsContSet(2).
        noteEvent("OPS 6 CONT BLUE: no landing site -- the pullout, alpha-Mach banked toward the coast (wings level without "
                  + "the coast table), the bailout hold over water below Mach " + GR_BAIL_MACH + " at " + GR_BAIL_KEAS
                  + " KEAS (the SLF's frame only for the display)").
    }
}
IF talMode <> "TAL" AND NOT OPS6_GR { suNote("*** OPS 6: mode " + talMode + " not built: flying the TAL logic"). }
IF NOT TAL_SITES:HASKEY(talSiteKey) {
    suNote("*** OPS 6: no TAL site " + talSiteKey + ": ZZA").
    SET talSiteKey TO "ZZA".
}
LOCAL talCtr IS TAL_SITES[talSiteKey][0].
LOCAL talRwy IS CHOOSE talRwyWant IF talRwyWant <> "" ELSE TAL_SITES[talSiteKey][1].
LOCAL talRw IS ldLoadRunway(talRwy).
IF talRw:LENGTH = 0 {
    suNote("*** OPS 6: runway " + talRwy + " not in hud_runways.txt: " + TAL_SITES[talSiteKey][2]).
    SET talRwy TO TAL_SITES[talSiteKey][2].
}
LOCAL talFrom IS SHIP:GEOPOSITION.                       // the interface point: here when already inside it
LOCAL talEI IS eprKepToEI(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT).
IF talEI[2] > 0 {                                        // the conic's point, the body's spin over the coast added
    LOCAL talGp IS SHIP:BODY:GEOPOSITIONOF(talEI[0] + SHIP:BODY:POSITION).
    SET talFrom TO LATLNG(talGp:LAT, norm180(talGp:LNG + ROT_LNG_SIGN * 360 / SHIP:BODY:ROTATIONPERIOD * talEI[2])).
}
LOCAL talIn IS MOD(bearing(talCtr, talFrom) + 180, 360).          // the inbound course at the site
IF talMode = "RTLS" AND talRwyWant = "" {   // an RTLS's DEFAULT end is the one OPPOSITE
    //   the nearer (the lower overhead HAC turn), as the deorbit planner's runway box: ldLowTurnEnd on the inbound course.
    //   Only the default: a third argument forces an end, the crew's SW RWY / site switch in the GRTLS is unchanged. (CONT
    //   keeps the threshold nearer the ship; the split-S's ssPick scores both ends; the phase-4 pick scores the 4 pairs.)
    LOCAL rtLt IS ldLowTurnEnd(talRwy, talIn).
    noteEvent("OPS 6 RTLS RUNWAY END (default: the lower HAC turn on the inbound course " + ROUND(talIn, 1) + "): "
              + rtLt[0] + " (" + ROUND(rtLt[1]) + " deg)" + (CHOOSE "" IF rtLt[0] = talRwy ELSE " over " + talRwy + " ("
              + ROUND(rtLt[2]) + " deg), the old prime end")).
    SET talRwy TO rtLt[0].
}
SET PLAN_AIM TO destGeo(talCtr, bearing(talCtr, talFrom), (CHOOSE TAL_AIM_KM IF talMode = "TAL" ELSE FTP_BACK_KM) * 1000).
applyRunway(talRwy, talIn, PLAN_AIM).
IF talMode = "SPLITS" {                  // the split-S picks between the site's two ends at phase 4's start (lib_grtls
    SET SS_ENDS TO LIST(TAL_SITES[talSiteKey][1], TAL_SITES[talSiteKey][2]).   //   ssPick); a forced end: that one
    IF talRwyWant <> "" { SET SS_ENDS TO LIST(RWY_NAME, RWY_NAME). }
}
noteEvent("OPS 6 " + talMode + " to " + talSiteKey + ": runway " + RWY_NAME + " (inbound " + ROUND(talIn, 1)
          + " deg), aim " + ROUND(PLAN_AIM:LAT, 4) + " / " + ROUND(PLAN_AIM:LNG, 4) + ", "
          + ROUND(groundDist(SHIP:GEOPOSITION, PLAN_AIM) / 1000) + " km out; the interface in "
          + ROUND(MAX(talEI[2], 0)) + " s").

// =====================================================================
//  ENTRY CONFIGURATION  --  the deorbit burn is already done
// =====================================================================
//  ops3q starts where shuttle_exec leaves off, post-burn and coasting to the interface, EVERY TIME rather than by
//  detection: deorbit_plan.ks solves the burn and shuttle_exec.ks flies it. The burn does not use Trajectories,
//  which does not model the edited aero: a burn that walks a wrong predicted impact onto the target lands elsewhere.
//  This block leaves the vehicle in the state entry needs. SAS goes OFF where steering is taken (TAKE THE ENTRY
//  ATTITUDE, below); left on, it would fight entrySteer() the whole way down.
//  AG5/AG2/AG9 are handled by the Phase 2 pre-entry block; AG8 stays with the CG trim. This path assumes the
//  usual orbital configuration (bay open, OMS on, surfaces stowed); if yours is not, set them by hand first.
RCS ON.
// OPS 6: no UNLOCK STEERING here: ops1q's steering (its hold) flies on to OPS 6's first LOCK (Phase 2's entrySteer; the
// split-S's ssSteer, taken after the libraries load); without one nothing is locked here either.
setAction("AG7 fwd").
IF talMode <> "SPLITS" { TOGGLE AG7. WAIT 1. }   // forward control point (skip on
    // the split-S toggled it with its first lock)

// ============================ CARGO CG MANAGEMENT (entry) ============================
// (Declared here, at the top level: the monoprop dump runs at the coast's warp stop, before the interface, and
//  needs these by then.)
// With cargo aboard, the entry CG can drift and make the orbiter too stable (won't hold AoA) or unstable. During
// Phase 3 the longitudinal CG is trimmed toward the CLEAN (no-cargo) value by shuttling monopropellant between
// the forward (nose) and aft tanks and, only if monoprop is saturated and the error is large, by toggling a
// fuel-dump action group.
// The clean-CG reference is HARD-BAKED (CG_REF_FORE_M, below); no calibration is needed. CG_CALIBRATE TRUE still
// records the clean longitudinal CG at the entry interface to CG_REF_FILE, as a record only: the trim target never
// reads it.
GLOBAL CG_TRIM_ON      IS TRUE.        // master enable for entry CG management
GLOBAL CG_CALIBRATE    IS FALSE.       // TRUE records the clean CG to CG_REF_FILE (a record only; the target is CG_REF_FORE_M)
GLOBAL CG_REF_FILE     IS "sock_cg_ref.json".  // file (current volume): records only (each entry's monoUsed, the calibration), NOT the target
GLOBAL CG_RES_NAME     IS "MonoPropellant".    // resource shuttled fore/aft to trim CG
GLOBAL CG_DEADBAND_M   IS 0.05.        // |CG - target| within this (m) -> stop trimming
GLOBAL DUMP_AG         IS 8.           // fuel-dump valve action group; the CG trim opens it DURING entry, not pre-entry; 0 = no dump
GLOBAL DUMP_FIELD      IS "drain".     // ModuleResourceDrain boolean on/off field; "" = fall back to action/AG
GLOBAL CG_ENTRY_DUMP_ON IS FALSE.      // entry tail-heavy LF/OX dump (gates monoprop flow off mid-burst -> brief RCS loss); enable for tail-heavy cargo
GLOBAL DUMP_USE_ACTION IS TRUE.        // TRUE = open the dump via a part-module ACTION (AG-free) instead of an action group
GLOBAL DUMP_ACTION_NAME IS "drain".    //   ACTION that OPENS the dump valve (ReleaseValve/ModuleResourceDrain)
GLOBAL DUMP_ACTION_OFF  IS "stop draining". //   ACTION that CLOSES it; "" = DUMP_ACTION_NAME is a single toggle taking a bool
GLOBAL MONO_AUTH_K     IS 0.00238.     // CG swing per unit of monoprop relocated fore<->aft (m/unit), from cg_authority.csv
GLOBAL DUMP_GATE_ON    IS TRUE.         // pick the drained resource via tank flow flags -- REQUIRES all 3 resources selected in the valve PAW
GLOBAL DUMP_GATE_RES   IS LIST("LiquidFuel", "Oxidizer", "MonoPropellant").  // resources the gate manages
GLOBAL DUMP_DUTY       IS 1.            // dump speed as a fraction of the valve's native rate (1 = full; <1 pulses the valve)
GLOBAL DUMP_PULSE_S    IS 1.            // pulse period (s) used when DUMP_DUTY < 1
GLOBAL DUMP_RATE_FIELD IS "drain rate". // valve's tweakable rate field; script drives it. "" = leave the valve's own rate alone
GLOBAL DUMP_RATE_FULL_M IS 1.0.         //   CG error (m) at/above which the valve runs at its full (PAW-set) rate
GLOBAL DUMP_RATE_MIN   IS 0.2.          //   floor: rate eases to this fraction of full as the CoM nears the target
GLOBAL DUMP_RATE_MAX   IS 20.           // the valve's FULL rate (%), set by readDumpRate: the stock FTE-1 slider's maximum (ModuleResourceDrain drainRate 1-20); 0 = the PAW's own value
GLOBAL cgDumpNativeRate IS 0.           // the valve's full rate, read from the PAW at entry start
GLOBAL cgDumpRateSet   IS -1.           // last rate fraction written (skips redundant SETFIELDs)
GLOBAL MONO_LOG_ON     IS TRUE.         // log per-entry monoprop usage to a CSV (to choose a pre-entry MP load)
GLOBAL MONO_LOG_FILE   IS "mono_usage.csv". // one summary row appended per entry
GLOBAL cgMonoStart     IS 0.            // total monoprop at entry start (units)
GLOBAL cgMonoMin       IS 0.            // lowest total monoprop seen during the entry
GLOBAL cgMaxAbsErr     IS 0.            // largest |CG err| seen during the entry (m)
GLOBAL cgMonoAtMaxErr  IS 0.            // total monoprop at the moment of that largest error
GLOBAL monoLogged      IS FALSE.        // guard so the summary row is written once
// --- pre-EI monoprop dump: shed monoprop at EI so the authority peak lands late in entry ---
GLOBAL MONO_PRE_DUMP   IS TRUE.         // at EI, dump monoprop down to the authority-optimal level before heating
GLOBAL MONO_PEAK_UNITS IS 200.          // monoprop level of peak CG authority (tent-curve peak)
GLOBAL MONO_PRE_FRAC   IS 0.75.         // target = MONO_PEAK_UNITS + this * (monoprop the entry consumes)
GLOBAL MONO_USED_EST   IS 30.           // the entry's monoprop use (units), BAKED from the Sol entries (range 17.4-44.7); sock_cg_ref.json's monoUsed is a record only
GLOBAL MONO_PRE_MIN    IS 5.            // skip the dump if it would remove fewer than this many units
GLOBAL MONO_PRE_TMO_S  IS 30.           // safety timeout (s) on the pre-EI dump, which holds the Phase 3 loop while it runs; 30 s fits ~120 units at >= 4 units/s and ends by ~77 km
GLOBAL MONO_PRE_CHECK_S IS 2.           // abort the pre-EI dump unless MONO_PRE_CHECK_U units have gone within this many s
GLOBAL MP_STEADY_DEG IS 2.             // deg: the pre-entry MP dump waits until the nose is within this of the entry attitude...
GLOBAL MP_STEADY_W IS 0.3.             // deg/s: ...the body rates under this...
GLOBAL MP_STEADY_S IS 3.               // s: ...for this long;
GLOBAL MP_STEADY_TMO_S IS 30.          // s: this long at most,
GLOBAL MP_STEADY_Q IS 1.               // kPa: and not past this dynamic pressure (the entry loop must start)
GLOBAL MONO_PRE_CHECK_U IS 5.           // units that must have gone within MONO_PRE_CHECK_S: RCS use alone (~1 unit/s after the warp) passes 1 in 4 s; the valve at 20 % sheds tens per second
GLOBAL MONO_PRE_LAG_S   IS 0.24.        // the early close's allowance for the valve's lag (s): setDumpValve scans every part, and the flow stops 0.23-0.25 s after the close command
GLOBAL DUMP_RES_MIN     IS 3.           // a drain valve must drain >= this many resources (its "resources" field) for the dump: MonoPropellant + LiquidFuel + Oxidizer = 3; LF + Ox only = 2 (no mono)
GLOBAL cgMonoUsedRef   IS 0.            // the ref file's monoUsed (the last entry's use): a record only -- the dump uses MONO_USED_EST
GLOBAL cgValveOpen     IS FALSE.        // tracked valve state, so we only toggle on change
GLOBAL CG_DUMP_ERR_M   IS 0.30.        // only dump when monoprop is saturated AND |CG error| exceeds this (m)
GLOBAL CG_DUMP_CHECK_S IS 1.5.         // after a dump starts, window (s) to confirm it is moving CG the right way
GLOBAL CG_TARGET_FORE  IS 0.           // the trim target (m) = CG_REF_FORE_M + CG_TARGET_BIAS_M, set by loadCleanCg
// THE CLEAN-CG REFERENCE IS HARD-BAKED, so it does not change: the JNSQ calibration's clean longitudinal CG (cgFore
// of the clean orbiter, mass 20.918579 t), the same in the JNSQ and the Sol files. The trim target does not read
// sock_cg_ref.json, so neither a CG_CALIBRATE entry nor a cg_probe run (CG_WRITE_REF) can move it. The Sol
// orbiter measures 3.7 cm aft of the JNSQ one (cg_probe), small next to the 1 m bias.
GLOBAL CG_REF_FORE_M   IS -9.6175647417544088.  // m, clean-CG reference (the JNSQ calibration) -- HARD-BAKED
GLOBAL CG_TARGET_BIAS_M IS -0.94.      // shift the target from the clean ref (m): negative = aft (back), positive = forward
// -0.94: 6 cm forward of -1.0, so that with the stock pitch fix on (SockPitchFix) the body flap trims about 5 deg trailing
// edge up from Mach 12 to 8 on alpha-40 and alpha-30 entries alike (about 1.1 deg of flap a cm). The trim stops anywhere
// inside CG_DEADBAND_M.
GLOBAL CG_FAR_BIAS_M IS 0.            // m: 0, the c.g. is stock's (the clean ref - 0.94 m) under FAR; was -0.06 (ref - 1.0 m) until T529B
                                       // (stock's before -0.95); SockFarTrim moves the CoL 0.6 m forward instead (colShift).
                                       // The c.g. 0.6 m aft would trim the same: a FAR entry's elevon carried -4 to -8 deg
                                       // from Mach 11 to 5 at a CoM of -10.86 .. -11.03 m (flap on its -19 limit), about
                                       // 25-30 deg a metre, so zero elevon wants ~-11.2 m.
// A target further aft reduces the pitch trim demand, but erodes static margin, which is invisible until it
// bites. The flap is the real constraint (it sits at PTRIM_MAX for much of the hypersonic phase, and the elevons
// only spill because the flap has run out). Watch gmb_pitch for the onset of chasing: an increase there is the
// signal to stop going aft.
GLOBAL cgRefOK         IS FALSE.       // TRUE once a reference target is available
GLOBAL cgFwdTanks      IS LIST().      // monoprop tanks ahead of the CoM (cached at entry start)
GLOBAL cgAftTanks      IS LIST().      // monoprop tanks behind the CoM
GLOBAL cgXfer          IS 0.           // active resource-transfer object (0 = none)
GLOBAL cgXferDir       IS 0.           // +1 = fwd->aft (CoM aft), -1 = aft->fwd, 0 = idle
GLOBAL cgDumpActive    IS FALSE.       // fuel dump currently engaged
GLOBAL cgDumpStartT    IS 0.           // TIME:SECONDS the current dump began
GLOBAL cgDumpStartErr  IS 0.           // |CG error| when the dump began (to verify it helps)
GLOBAL cgDumpDisabled  IS FALSE.       // latched off if a dump moved CG the wrong way
GLOBAL cgErrM          IS 0.           // last CG error (m), for the panel
GLOBAL cgMonoF         IS 0.           // forward monoprop amount, for the panel
GLOBAL cgMonoA         IS 0.           // aft monoprop amount, for the log
// THE FAR TARGET'S WALK (CG_FAR_ADAPT_ON): under FAR the target walks aft while the elevon trim carries nose up and
// forward while it carries nose down, with the CoM at the target, to fly zero elevon; the body flap is not counted (it
// trims first, the elevon takes the spill). In a FAR entry the walk stopped at the elevon 0.5 deg off its limit and
// still carried -3 to -5 deg.
GLOBAL CG_FAR_ADAPT_ON     IS FALSE.   // FALSE: off, the target fixed (CG_FAR_BIAS_M); TRUE walks it
GLOBAL CG_FAR_ADAPT_STEP_M IS 0.05.    // m a step
GLOBAL CG_FAR_ADAPT_HOLD_S IS 5.       // s off zero, with the CoM within CG_DEADBAND_M of the target, before each step
GLOBAL CG_FAR_ADAPT_MAX_M  IS 0.4.     // m: the most it walks either way from the FAR target
GLOBAL CG_FAR_ELEV_DB      IS 0.5.     // deg of elevon trim either side of zero that counts as zero
GLOBAL cgAdaptM            IS 0.       // m walked so far (negative = aft)
GLOBAL cgPinT              IS -1.      // since when the elevon has been off zero with the CoM at the target (-1 = not)
GLOBAL CG_TRIM_DT      IS 0.5.         // s: the trim's update interval (each update walks every part twice; the CoM moves far slower than this)
GLOBAL cgTrimT         IS -999.        // TIME:SECONDS of the last trim update

// =====================================================================
//  PHASE 2  --  COAST TO ATMOSPHERE
// =====================================================================
{   // Phase 2 (the coast)
setAction("coast").
SET logPhase TO 2.

// The warp never outruns the altitude. The time gate trusts KSP's Keplerian orbit, and under Principia (J2) its
// interface time can run late; a late gate keeps a high rate until the floor, and the ramp-down from there carries
// the vehicle deep into the atmosphere. warpAltCap caps the rails index from the vehicle's own altitude and descent
// rate: the fastest rate that still leaves WARP_REACT_S real seconds before ENTRY_ALT + WARP_MARGIN_M. It is
// evaluated every tick, so each step down is checked against the altitude it actually reached.
FUNCTION warpAltCap {
    LOCAL h IS ALTITUDE - (ENTRY_ALT + WARP_MARGIN_M).
    IF h <= 0 { RETURN 0. }
    LOCAL rmax IS h / (MAX(-SHIP:VERTICALSPEED, 1) * WARP_REACT_S).
    LOCAL rl IS KUNIVERSE:TIMEWARP:RAILSRATELIST.
    LOCAL idx IS 0.
    FROM { LOCAL i IS 1. } UNTIL i >= MIN(rl:LENGTH, 5) STEP { SET i TO i + 1. } DO {
        IF rl[i] <= rmax { SET idx TO i. }
    }
    RETURN idx.
}

// Seconds until the orbit descends through ENTRY_ALT. Keplerian and exact rather than marching the trajectory
// forward, so it is cheap enough to evaluate every tick inside a warp loop. Returns -1 if the orbit never reaches
// that radius, or is too circular for the solve to mean anything: callers fall back to the altitude test.
// Method: the true anomaly magnitude at r = R + ENTRY_ALT, converted to the time from the DESCENDING crossing to
// periapsis via the eccentric and mean anomalies, and subtracted from ETA:PERIAPSIS.
FUNCTION timeToEntryAlt {
    LOCAL ecc IS SHIP:ORBIT:ECCENTRICITY.
    IF ecc < 0.000001 { RETURN -1. }
    LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL rEI IS SHIP:BODY:RADIUS + ENTRY_ALT.
    LOCAL cth IS ((sma * (1 - ecc^2) / rEI) - 1) / ecc.
    IF cth > 1 OR cth < -1 { RETURN -1. }
    LOCAL th IS ARCCOS(cth).
    LOCAL Ed IS 2 * ARCTAN(SQRT((1 - ecc) / (1 + ecc)) * TAN(th / 2)).
    LOCAL M  IS Ed * CONSTANT:DEGTORAD - ecc * SIN(Ed).
    LOCAL n  IS 2 * CONSTANT:PI / MAX(SHIP:ORBIT:PERIOD, 1).
    RETURN ETA:PERIAPSIS - M / n.
}

opsCls().
// Close the payload bay by driving its OWN module, not by pressing AG5: AG5 is bound to the bay AND the fuel cell,
// because they are the same part (the OV-100 Mid Fuselage Section, benjee10.shuttle.midFuselage, carries both
// ModuleAnimateGeneric act "toggle bay doors" fld "status" | "deploy limit" and ModuleResourceConverter act "toggle
// fuel cell" fld "fuel cell"), so one AG5 keypress shuts the doors and kills the power source. An action group is a
// keypress; the script cannot see the second binding. DOEVENT("close") is also STATE-INDEPENDENT (a toggle on an
// already shut bay would OPEN it just before entry), and the close is VERIFIED through the module's "status" field,
// so a wrong event string cannot fail silently.
FUNCTION closeBayDoors {
    LOCAL done IS FALSE.
    FOR bp IN SHIP:PARTSNAMED("benjee10.shuttle.midFuselage") {
        LOCAL anim IS bp:GETMODULE("ModuleAnimateGeneric").
        // The event is named "close" while the bay is open and "open" once it is shut, so its
        // PRESENCE is the state test. Nothing to do if it is already closed.
        IF anim:HASEVENT("close") {
            anim:DOEVENT("close").
            SET done TO TRUE.
        } ELSE {
            SET done TO TRUE.   // already closed
        }
    }
    IF NOT done {
        opsWarn("*** bay part not found: close the doors by hand.").
        noteEvent("bay part not found: close the doors by hand").
        RETURN.
    }
}

// =====================================================================
//  THE REFERENCE FAMILY  --  OPS 6: BUILT IN THE BACKGROUND, from the ET-sep state
// =====================================================================
//  ops3q builds it on the coast before the warp or reads fam_build's file. A TAL has 32-95 s from the ET sep to the
//  interface and 125-345 s to guidance initiate (offline, the build needs 10-14 RK2 steps per game second; kOS did
//  54-85 in fam_build), so OPS 6 STARTS it here and the entry loop advances it TAL_BUILD_BUDGET steps a cycle
//  (talFamRun). The members fly the TAL pre-entry (EPR_PREENTRY_BANK 0 at TAL_A0) as the vehicle does. eprArm FIRST,
//  so the geodesy epoch is not re-stamped under a running build. The mass: eprMassTrack at the top (after the ET sep).
GLOBAL TRAJ_ON IS talMode <> "SPLITS".   // FALSE skips the ENTRY TRAJ display entirely (the split-S: none)
GLOBAL o6DeckOn IS FALSE.           // the TAL's deck is up (since its DAP, before the entry loop)
GLOBAL O6_TJ_PRE IS TRUE.           // ENTRY TRAJ is updated through the pre-entry dump's waits too (o6TjPre); FALSE = only from the entry loop, as before
GLOBAL O6_TJ_PRE_DT IS 0.1.         // s between those updates (the entry loop's own period)
GLOBAL o6TjNext IS 0.
GLOBAL TRAJ_EVERY IS 1.
GLOBAL trajTick IS 0.
GLOBAL TAL_BUILD_BUDGET IS 20.    // RK2 steps per entry-loop cycle while the build runs (ops3q's shadow solve flew 25)
GLOBAL TAL_FAM_LATE_S IS 60.      // s past the vehicle's initiate before a short build is finished with what it has
// THE GEODESY DATUM FOLLOWS KSP'S FRAME (entry_predict eprDatumFollow): eprArm captures the datum at the ET sep, above
// KSP's inverse-rotation altitude (about 76 km), where the world frame is inertial; the live position (eprToGeoLive, no
// rotation term) then sat 0.33-0.39 deg (7-8 km) east of the ship for the whole entry on the TALs that armed up there
//. Once the family is built (the build's
// integrator measures its ground positions from the datum, so never while it runs) and below TAL_DATUM_ALT, the datum
// is re-taken whenever it has drifted more than TAL_DATUM_TOL from SHIP:GEOPOSITION:LNG; after KSP's frame turns with the
// body it stays right, so it is taken once more at the switch and then not again.
GLOBAL TAL_DATUM_ALT IS 70000.    // m, below the frame switch (76 km on the logs) so the first re-take is not above it
GLOBAL TAL_DATUM_TOL IS 0.02.     // deg of longitude (about 2 km) the datum may be off before it is re-taken
GLOBAL TAL_DATUM_N IS 0.          // re-takes so far
GLOBAL TAL_FAM_T0 IS 0.
GLOBAL TAL_FAM_DONE_T IS -1.
SET EPR_PREENTRY_BANK TO 0.       // the TAL pre-entry wings level, the members and the vehicle
eprGuidReset().
SET TAL_VEH_VI TO -1.
SET TAL_VEH_T TO -1.
// TAL_V4N (lib_tal's block above it): a TAL's servo overbank and Nz limiter; an RTLS or a contingency flies the GRTLS
// and arms neither
talV4nArm(TAL_V4N AND talMode = "TAL").
IF TAL_V4N_ON {
    noteEvent("OPS 6: servo overbank to u " + ROUND(EPR_FAM_UTOP, 2) + " (bank to " + EPR_BANK_MAX_ABORT + " deg), Nz limiter at "
              + TAL_NZ_SET + " g").
}
LOCAL talAim0 IS destGeo(KSC_TARGET, RWY_HEADING + 180, EPR_TAEM_BACK_M).
eprArm(talAim0:LAT, talAim0:LNG).
// EPR_FAM_ADD (entry_predict): the plan's HAC, as ops3q -- the TAL runway as applyRunway committed it; the target's
// origin = the site (talCtr, the point the TAL aim is built from)
IF EPR_FAM_ADD AND NOT OPS6_GR {
    eprArmHac(RWY_THRESH:LAT, RWY_THRESH:LNG, RWY_HEADING, TG_X_AIM_NOM - RWY_AIM_DX - TG_H_HAC_NEP / TG_TGGS, TG_RFMX,
              talCtr:LAT, talCtr:LNG).
    talArmRhg(RWY_THRESH:LAT, RWY_THRESH:LNG, RWY_HEADING, TG_X_AIM_NOM - RWY_AIM_DX - TG_H_HAC_NEP / TG_TGGS, TG_RFMX).
    noteEvent("family HAC: centre " + ROUND(EPR_HAC_LAT, 4) + " / " + ROUND(EPR_HAC_LNG, 4) + ", side " + EPR_HAC_YSGN
              + " (aim " + ROUND(EPR_HAC_YAIM / 1000, 1) + " km off the line), origin the site").
}
IF NOT OPS6_GR {   // an RTLS builds no reference family (the GRTLS flies none)
SET TAL_FAM_T0 TO TIME:SECONDS.
talFamStart(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT).
noteEvent("OPS 6: family build started in the background (" + TAL_BUILD_BUDGET + " steps a cycle, mass factor "
          + ROUND(EPR_MASS_K, 3) + "); coast skipped " + ROUND(EPR_FAM_TCOAST, 1) + " s").
}   // the end of the family build's start

opsCls().

// ---- the ENTRY TRAJ display -------------------------------------------------------------
//  Started before the warp, deliberately: it needs EPR_FAM populated (true by here) and the pilot's attention while
//  there is still time to react. A display must never stop an entry: if the sidecar is missing, drawn for another
//  vessel, or built against a different aero model, this says so and flies on, as everything else here degrades
//  rather than refuses.
IF TRAJ_ON AND NOT OPS6_GR {   // an RTLS / CONT (ECAL, BDA, BLUE) / split-S flies the GRTLS: no ENTRY TRAJ at all
    // OPS 6: THE GENERIC TAL PANELS (Script/tal/, drawn once from one generic TAL family) and their lines for the bug
    // (lib_tal talGenRead); the box on those lines; no bug or box until the live family is in, but the display is up
    // before it. Their sidecar names no vessel: a TAL's vessel is not the one the nominal panels were drawn for. The
    // TAL only: an RTLS / CONT flies the GRTLS, with no ENTRY TRAJ.
    LOCAL tjOk IS FALSE.
    SET TJ_SIDE TO "0:/tal/traj_bg.txt".
    SET TJ_BANK_RANGE TO tjGenBank@.         // talGenBankRange, in C# while the C# page runs
    SET TJ_BUG_ON TO FALSE.
    IF talGenRead("0:/tal/family_tal.txt") { SET tjOk TO trajInit(). } ELSE { SET TJ_WHY TO TAL_GEN_WHY. }
    IF tjOk {
        noteEvent("TRAJ display armed (" + TJ_P:LENGTH + " panels; drawing " + TJ_CS_STATE + ")").
    } ELSE {
        opsWarn("*** ENTRY TRAJ unavailable: " + TJ_WHY).
        noteEvent("TRAJ display unavailable (" + TJ_WHY + ") -- flying without it").
    }
    // OPS 6: no countdown (nothing may block: the build runs only in the entry loop)
}
suBlock().                                       // the start-up lines to the events file

// OPS 6: no warp (the ET sep to the interface is 32-95 s, flown at 1x with the build running)
// THE MONOPROP DUMP RUNS HERE, BEFORE THE INTERFACE: at 1x, in
// vacuum, at least WARP_MARGIN_M above ENTRY_ALT. The Phase 3 calls repeat the CG setup and find the monoprop at its target.
classifyCgTanks().
IF CG_CALIBRATE { captureCleanCg(). } ELSE { loadCleanCg(). }
IF dumpAvailable() { setDumpValve(FALSE). }
SET cgValveOpen TO FALSE.
SET cgDumpActive TO FALSE.
readDumpRate().
// OPS 6: the pre-entry monoprop dump runs at the end of Phase 2, after the entry attitude's lock

// =====================================================================
//  TAKE THE ENTRY ATTITUDE NOW  --  before the interface, not after it
// =====================================================================
//  The vehicle must be at AoA 40, wings level, when it reaches the interface. It cannot rotate during rails warp,
//  so the alignment happens here, the moment warp ends, with WARP_STOP_LEAD_S of coast still to run. Not at
//  Phase 3: guidance takes steering AT the interface, so the roll to attitude would happen during the first seconds
//  in the atmosphere at 3700 m/s, and the first drag the family sees would come from an attitude the family did
//  not assume.
//  entrySteer() is the same function Phase 3 uses, reading entryAoaCmd and bankNow live, so this is not a second
//  attitude controller to keep in step: the handover to guidance is continuous, and nothing changes at the
//  interface except that bankNow starts moving. entryAoaCmd and bankNow are set explicitly here (a default is not
//  a command). SAS goes off here: a steering lock and SAS fight.
setAction("entry attitude").
SAS OFF.
SET entryAoaCmd  TO TAL_A0.            // OPS 6: the TAL pre-entry alpha
IF OPS6_GR { SET entryAoaCmd TO ldAlphaNow(). }   // the RTLS holds its alpha to the GRTLS's phase 6
IF talMode = "SPLITS" { SET entryAoaCmd TO GR["acmd"]. }   // SPLITS: phase 8's command (its ssSteer lock flies on)
SET bankNow      TO 0.
SET entrySlipCmd TO 0.
// Widen the roll-control range BEFORE the lock, not after: kOS only corrects roll once the nose
// is within 5 deg of target by default, which would read as "yaw, then roll" on the way to
// attitude. Phase 3 sets this too; setting it here makes the initial alignment coordinated.
SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.
IF talMode <> "SPLITS" {                // SPLITS: ssSteer to phase 5 (lib_grtls; the GRTLS loop)
    // the RTLS / CONT attitude is lib_grdap's DAP (CSS) from here to landRun, and the TAL's entry too, as ops3q's (CSS
    // from the interface, the entry HUD); an older DLL without FBW3: the steering lock
    IF OPS6_GR { IF NOT grdStart(FALSE) { LOCK STEERING TO entrySteer(). } }
    ELSE { IF NOT grdStart(FALSE, TRUE) { LOCK STEERING TO entrySteer(). } }
}
entrySteerGains(TRUE).            // ENTRY_STEER_KP / ENTRY_STEER_TS on pitch + roll for the entry
// The TAL's deck goes up here, right after its DAP, not at the entry loop's start (up to MONO_PRE_TMO_S of the
// pre-entry dump later), so ops1q's displays turn straight into these without going away: ENTRY TRAJ (no bug or box
// before the live family), its DAP buttons and the entry page, in the deck's place (lib_dock), and only then the OPS 1
// pages ops1q left up go (ASC_PG_KEEP_TAL: ops1q reads this name in this file and keeps them up, as an RTLS's ASC_PG_KEEP).
// The entry page is drawn through the dump's waits (o6PreTick).
IF NOT OPS6_GR {
    IF TRAJ_ON { trajShow(). }
    IF grdOn {
        dapGuiBuild("ORBITER DAP", "ENTRY", FALSE, TRUE).
        SET dBtnBail:ENABLED TO FALSE.
    }
    edDeckUp().
    SET o6DeckOn TO TRUE.
    o6PreTick().
}
// An RTLS / a contingency / a split-S puts its MM 602 pages and their DAP buttons up here, before the pre-entry dump,
// in the OPS 1 windows ops1q kept up (lib_taemdisp tdAdopt): the GUIs stay up through the hand-off and only the screens
// and buttons switch; they draw from the GRTLS loop's first cycle (tdGrTick). Not taken (a page file missing): the
// GRTLS loop's start puts them up (tdGrStart).
GLOBAL o6GrPgUp IS FALSE.
IF OPS6_GR AND (DEFINED ASC_PG_KEEP_UP) { IF ASC_PG_KEEP_UP {
    IF tdGrStart() {
        dapGuiBuild("ORBITER DAP", "GRTLS", FALSE, grdOn).
        SET o6GrPgUp TO TRUE.
    }
} }
IF DEFINED adOn { IF adOn { adClose(). } }   // the OPS 1 pages (ASC_PG_KEEP_TAL) go once the deck is up

// Configure for entry BEFORE reaching the atmosphere. TOGGLE fires each group
// like a single key press:
//   AG5 = payload bay doors, AG2 = OMS off, AG9 = control surfaces,
// (AG8 fuel dump is deferred to the CG trim during entry -- not opened here.)
setAction("close bay").
closeBayDoors().
// AG2 and AG9 are bare toggles, a known risk: neither is checked for a second binding the way AG5 is, and a toggle
// assumes the current state (run ops3q with the surfaces already deployed and AG9 stows them just before entry).
// They stay toggles because the parts they drive are not identified. If either misbehaves, bay_probe.ks with its
// `want` list widened lists every module, event, action and field on a matching part.
IF NOT HO_DUMP {                  // the hand-off's dump runs on (hoDumpOff ends it)
    setAction("OMS off").
    talOmsOff().                  // OPS 6: by part, not the AG2 toggle (see talOmsOff)
    IF talMode <> "SPLITS" { WAIT 0.3. }
}
IF HO_WAIT { hoWaitArm(). }       // the hand-off's dump lit once the ET is clear
IF NOT hoGet("surf_on", talMode = "SPLITS") {   // ops1q's split-S switched the surfaces on at its arm (their fields)
    setAction("AG9 surfaces").
    TOGGLE AG9. WAIT 0.3.
}

// Coast down to the entry interface; the Phase 3 loop below starts there.
IF talMode <> "SPLITS" { preEntryMonoDump(). eprMassTrack(). }   // OPS 6: ops3q's dump (then the entry model at the mass it left), the entry attitude held by the
    // steering lock (the split-S: none, in the air on its RCS)
// OPS 6: no wait for the interface: the entry loop (and with it the build) starts now
}   // end of Phase 2 (the coast)

// =====================================================================
//  PHASE 3  --  BANK-MANAGED ENTRY GUIDANCE
// =====================================================================
// Vessel centre of mass: kOS has no CoM suffix, so build it from the parts (mass-weighted mean
// of part positions). Frame-agnostic -- cgFore subtracts the root position in the same frame.
FUNCTION shipCoM {
    LOCAL sm IS 0.
    LOCAL sp IS V(0, 0, 0).
    FOR p IN SHIP:PARTS {
        LOCAL pm IS p:MASS.
        SET sm TO sm + pm.
        SET sp TO sp + pm * p:POSITION.
    }
    IF sm <= 0 { RETURN V(0, 0, 0). }
    RETURN sp / sm.
}
// Longitudinal position (m) of the CoM along the nose axis, from the (fixed) root part.
// Monotonic with fore/aft CG; the absolute value is calibrated, not assumed.
FUNCTION cgFore {
    RETURN VDOT(shipCoM() - SHIP:ROOTPART:POSITION, SHIP:FACING:FOREVECTOR).
}
// Cache the monoprop tanks as forward / aft of the CoM (call once at entry start).
FUNCTION classifyCgTanks {
    SET cgFwdTanks TO LIST().
    SET cgAftTanks TO LIST().
    LOCAL com  IS shipCoM().
    LOCAL fore IS SHIP:FACING:FOREVECTOR.
    FOR p IN SHIP:PARTS {
        FOR res IN p:RESOURCES {
            IF res:NAME = CG_RES_NAME AND res:CAPACITY > 0 {
                IF VDOT(p:POSITION - com, fore) > 0 { cgFwdTanks:ADD(p). }
                ELSE { cgAftTanks:ADD(p). }
            }
        }
    }
}
// Total CG_RES_NAME aboard the WHOLE vessel (units). Fore/aft transfers don't change this; only RCS burns do.
FUNCTION monoTotalAll {
    LOCAL tot IS 0.
    FOR p IN SHIP:PARTS { FOR res IN p:RESOURCES { IF res:NAME = CG_RES_NAME { SET tot TO tot + res:AMOUNT. } } }
    RETURN tot.
}
// Restrict what the (Drain-All) valve sheds by toggling tank resource-flow flags: only resources in
// allow[] keep flowing, so the valve drains exactly those. Engines/RCS share these flags, so gate only
// resources not needed at the time (LF/OX while engines are off; monoprop only during a short burst).
FUNCTION dumpSelect {
    PARAMETER allow.
    IF NOT DUMP_GATE_ON { RETURN. }
    FOR p IN SHIP:PARTS {
        FOR res IN p:RESOURCES {
            IF DUMP_GATE_RES:CONTAINS(res:NAME) AND res:TOGGLEABLE { SET res:ENABLED TO allow:CONTAINS(res:NAME). }
        }
    }
}
// Re-enable flow on all gated resources.
FUNCTION dumpSelectAll {
    IF NOT DUMP_GATE_ON { RETURN. }
    FOR p IN SHIP:PARTS {
        FOR res IN p:RESOURCES {
            IF DUMP_GATE_RES:CONTAINS(res:NAME) AND res:TOGGLEABLE { SET res:ENABLED TO TRUE. }
        }
    }
}
// Total CG_RES_NAME currently in a tank list.
FUNCTION monoIn {
    PARAMETER tanks.
    LOCAL tot IS 0.
    FOR p IN tanks { FOR res IN p:RESOURCES { IF res:NAME = CG_RES_NAME { SET tot TO tot + res:AMOUNT. } } }
    RETURN tot.
}
// Free CG_RES_NAME capacity in a tank list.
FUNCTION monoCap {
    PARAMETER tanks.
    LOCAL tot IS 0.
    FOR p IN tanks { FOR res IN p:RESOURCES { IF res:NAME = CG_RES_NAME { SET tot TO tot + (res:CAPACITY - res:AMOUNT). } } }
    RETURN tot.
}
// Record the current (clean) longitudinal CG to CG_REF_FILE -- a record only; the target stays CG_REF_FORE_M.
FUNCTION captureCleanCg {
    LOCAL cgv IS cgFore().
    WRITEJSON(LEXICON("cgFore", cgv, "mass", SHIP:MASS), CG_REF_FILE).   // a RECORD only -- see CG_REF_FORE_M
    SET CG_TARGET_FORE TO CG_REF_FORE_M + CG_TARGET_BIAS_M + (CHOOSE CG_FAR_BIAS_M IF FAR_TRIM_ON ELSE 0) + cgAdaptM.
    SET cgRefOK TO TRUE.
    setAction("cg ref saved").
}
// The trim target: the HARD-BAKED clean-CG reference + the bias, never the file (see CG_REF_FORE_M). The ref
// file supplies only monoUsed, a record (the pre-EI dump's estimate is the baked MONO_USED_EST).
FUNCTION loadCleanCg {
    SET CG_TARGET_FORE TO CG_REF_FORE_M + CG_TARGET_BIAS_M + (CHOOSE CG_FAR_BIAS_M IF FAR_TRIM_ON ELSE 0) + cgAdaptM.
    // FAR flown raw (no SockFarTrim: such an entry railed the flap and elevon down) keeps the stock target
    IF FAR_ON AND NOT FAR_TRIM_ON { noteEvent("FAR WITHOUT SOCKFARTRIM (7_FAR_TRIM.CFG MISSING): NO FAR TRIM, CoL NOT MOVED"). }
    SET cgRefOK TO TRUE.
    IF EXISTS(CG_REF_FILE) {
        LOCAL refj IS READJSON(CG_REF_FILE).
        IF refj:HASKEY("monoUsed") { SET cgMonoUsedRef TO refj["monoUsed"]. }
    }
    setAction("cg ref fixed").
}
// Set the monoprop transfer direction (+1 fwd->aft, -1 aft->fwd, 0 stop).
FUNCTION setCgXfer {
    PARAMETER dir.
    IF dir = cgXferDir { RETURN. }
    IF cgXferDir <> 0 { SET cgXfer:ACTIVE TO FALSE. }
    SET cgXferDir TO dir.
    IF dir = 0 { SET cgXfer TO 0. RETURN. }
    LOCAL fromT IS cgFwdTanks.
    LOCAL toT   IS cgAftTanks.
    IF dir < 0 { SET fromT TO cgAftTanks. SET toT TO cgFwdTanks. }
    SET cgXfer TO TRANSFERALL(CG_RES_NAME, fromT, toT).
    SET cgXfer:ACTIVE TO TRUE.
}
// Toggle a numbered action group (1..10) to a definite state.
FUNCTION setAg {
    PARAMETER agn, st.
    IF      agn = 1  { SET AG1  TO st. }
    ELSE IF agn = 2  { SET AG2  TO st. }
    ELSE IF agn = 3  { SET AG3  TO st. }
    ELSE IF agn = 4  { SET AG4  TO st. }
    ELSE IF agn = 5  { SET AG5  TO st. }
    ELSE IF agn = 6  { SET AG6  TO st. }
    ELSE IF agn = 7  { SET AG7  TO st. }
    ELSE IF agn = 8  { SET AG8  TO st. }
    ELSE IF agn = 9  { SET AG9  TO st. }
    ELSE IF agn = 10 { SET AG10 TO st. }
}
// CG (m) monoprop can still add toward FORWARD from the current split = slope x the monoprop still
// movable aft->fwd (limited by remaining forward capacity).
FUNCTION fwdMonoAuthority {
    RETURN MONO_AUTH_K * MIN(monoIn(cgAftTanks), monoCap(cgFwdTanks)).
}
// Is any dump mechanism configured?
FUNCTION dumpAvailable {
    RETURN (DUMP_FIELD <> "") OR (DUMP_USE_ACTION AND DUMP_ACTION_NAME <> "") OR (DUMP_AG > 0).
}
// Open/close the dump valve. AG-free path: fire the named part-module ACTION directly on every part
// that has it (no action group needed). Otherwise toggle the DUMP_AG action group.
FUNCTION setDumpValve {
    PARAMETER st.
    IF DUMP_FIELD <> "" {                         // ModuleResourceDrain boolean on/off
        FOR p IN SHIP:PARTS {
            FOR mn IN p:MODULES {
                LOCAL md IS p:GETMODULE(mn).
                IF md:HASFIELD(DUMP_FIELD) { md:SETFIELD(DUMP_FIELD, st). }
            }
        }
    } ELSE IF DUMP_USE_ACTION AND DUMP_ACTION_NAME <> "" {
        LOCAL useName IS DUMP_ACTION_NAME.   // open action
        LOCAL useArg IS st.
        IF DUMP_ACTION_OFF <> "" {            // separate open/close actions: fire the right one with TRUE
            IF NOT st { SET useName TO DUMP_ACTION_OFF. }
            SET useArg TO TRUE.
        }
        FOR p IN SHIP:PARTS {
            FOR mn IN p:MODULES {
                LOCAL md IS p:GETMODULE(mn).
                IF md:HASACTION(useName) { md:DOACTION(useName, useArg). }
            }
        }
    } ELSE IF DUMP_AG > 0 {
        setAg(DUMP_AG, st).
    }
}
// Set the valve only when the desired state changes (avoids re-scanning parts every tick).
FUNCTION dumpValve {
    PARAMETER want.
    IF want <> cgValveOpen { setDumpValve(want). SET cgValveOpen TO want. }
}
// If the dump part exposes a tweakable drain-rate FIELD, set it once for direct speed control.
FUNCTION readDumpRate {
    SET cgDumpNativeRate TO 0.
    SET cgDumpRateSet TO -1.
    IF DUMP_RATE_FIELD = "" { RETURN. }
    FOR p IN SHIP:PARTS {
        FOR mn IN p:MODULES {
            LOCAL md IS p:GETMODULE(mn).
            IF md:HASFIELD(DUMP_RATE_FIELD) {
                SET cgDumpNativeRate TO md:GETFIELD(DUMP_RATE_FIELD).
                // the full rate is the slider's maximum, written to every valve here -- not whatever the save holds
                IF DUMP_RATE_MAX > 0 { SET cgDumpNativeRate TO DUMP_RATE_MAX. SET cgDumpRateSet TO -1. setDumpRate(1). }
                RETURN.
            }
        }
    }
}
// Set the valve's drain rate to frac (0..1) of its full rate, clamped to [DUMP_RATE_MIN, 1].
FUNCTION setDumpRate {
    PARAMETER frac.
    IF DUMP_RATE_FIELD = "" OR cgDumpNativeRate <= 0 { RETURN. }
    LOCAL f IS MAX(DUMP_RATE_MIN, MIN(1, frac)).
    IF ABS(f - cgDumpRateSet) < 0.03 { RETURN. }   // skip tiny changes
    SET cgDumpRateSet TO f.
    LOCAL val IS f * cgDumpNativeRate.
    FOR p IN SHIP:PARTS {
        FOR mn IN p:MODULES {
            LOCAL md IS p:GETMODULE(mn).
            IF md:HASFIELD(DUMP_RATE_FIELD) { md:SETFIELD(DUMP_RATE_FIELD, val). }
        }
    }
}
FUNCTION startCgDump {
    PARAMETER absErr.
    SET cgDumpActive TO TRUE.
    SET cgDumpStartT TO TIME:SECONDS.
    SET cgDumpStartErr TO absErr.
    dumpSelect(LIST("LiquidFuel", "Oxidizer")).   // entry dump sheds LF+OX only
}
FUNCTION stopCgDump {
    SET cgDumpActive TO FALSE.
    dumpValve(FALSE).
    setDumpRate(1).   // leave the valve at its full (PAW) rate
    dumpSelectAll().  // restore flow on all gated resources
}
// Fuel dump (last resort): only when monoprop can't close the error. Engages when the needed
// side of monoprop is exhausted/full and |err| is large; stops when |err| comes back down. If a
// started dump is NOT reducing |err| within CG_DUMP_CHECK_S it is aborted and disabled for the rest of the entry.
FUNCTION updateCgDump {
    PARAMETER err.
    IF (NOT dumpAvailable()) OR cgDumpDisabled OR (NOT CG_ENTRY_DUMP_ON) { RETURN. }
    LOCAL ae IS ABS(err).
    // The dumped fuel sits AFT, so opening the dump pulls the CoM FORWARD (+0.625 m for a full LFO dump). It only
    // helps a tail-heavy CoM (err < 0). Dump when the deficit is both significant AND beyond what monoprop can still
    // add toward forward.
    LOCAL fwdAuth IS fwdMonoAuthority().
    LOCAL wantDump IS (err < 0) AND (ae > CG_DUMP_ERR_M) AND (ae > fwdAuth + CG_DEADBAND_M).
    IF NOT cgDumpActive {
        IF wantDump { startCgDump(ae). }
    } ELSE {
        IF err >= 0 OR ae <= CG_DUMP_ERR_M * 0.6 OR ae <= CG_DEADBAND_M {
            stopCgDump().
        } ELSE IF (TIME:SECONDS - cgDumpStartT) >= CG_DUMP_CHECK_S {
            IF ae >= cgDumpStartErr - 0.01 {
                stopCgDump().
                SET cgDumpDisabled TO TRUE.
            } ELSE {
                SET cgDumpStartErr TO ae.
                SET cgDumpStartT TO TIME:SECONDS.
            }
        }
    }
    // valve speed control: hold open at full duty; otherwise pulse so the average dump rate is
    // ~DUMP_DUTY of the valve's native rate.
    IF cgDumpActive {
        IF DUMP_RATE_FIELD <> "" {
            // drive the valve's own rate: full when far off, easing to DUMP_RATE_MIN as the CoM nears target
            setDumpRate(ABS(err) / MAX(DUMP_RATE_FULL_M, 0.01)).
            dumpValve(TRUE).
        } ELSE IF DUMP_DUTY < 1 {
            LOCAL period IS MAX(DUMP_PULSE_S, 0.2).
            LOCAL elapsed IS TIME:SECONDS - cgDumpStartT.
            LOCAL ph IS elapsed - period * FLOOR(elapsed / period).
            dumpValve(ph < DUMP_DUTY * period).
        } ELSE {
            dumpValve(TRUE).
        }
    } ELSE {
        dumpValve(FALSE).
    }
}
// TRUE unless the drain valves are known not to drain monoprop: a ModuleResourceDrain's "resources" field is how many
// resources it drains (DUMP_RES_MIN). No valve with that field at all -> TRUE (the dump's own check still guards it).
FUNCTION dumpMonoReady {
    LOCAL seen IS FALSE.
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleResourceDrain") {
            LOCAL md IS p:GETMODULE("ModuleResourceDrain").
            IF md:HASFIELD("resources") {
                SET seen TO TRUE.
                IF md:GETFIELD("resources") >= DUMP_RES_MIN { RETURN TRUE. }
            }
        }
    }
    RETURN NOT seen.
}
// At EI, dump monoprop down to MONO_PEAK_UNITS + MONO_PRE_FRAC*used so the tent-curve authority
// peak (~MONO_PEAK_UNITS) is reached late in the entry, when CG control is most needed.
// the TAL's entry page between its deck-up and the entry loop (the pre-entry dump's waits), on the entry loop's
// own reads before the guidance runs: the azimuth error and the first deadband (eprAzError, eprAzDeadband) and the range
// (eprGcDist) to EPR_TGT (eprArm's, set before the deck); edTick draws (C#: its 10 Hz redraws between) or holds
// The C# family build is done in milliseconds but it was only
// POLLED by the entry loop, which starts after the dump's waits (mpSteadyWait + the dump: 13.6 s on flight_73430), and ENTRY TRAJ was
// only drawn by the loop too. Now the dump's waits poll the C# build (a handle check; the kOS fallback build still runs only in the
// entry loop, as before) and update ENTRY TRAJ (o6TjPre) at the loop's period.
FUNCTION o6PreTick {
    IF NOT OPS6_GR AND EPR_FAM_CS_ON AND NOT EPR_FAM_READY {
        IF talFamRun(TAL_BUILD_BUDGET) { talFamDone(" (polled in the pre-entry waits)"). }
    }
    IF NOT o6DeckOn { RETURN. }
    LOCAL rvP IS -SHIP:BODY:POSITION.
    LOCAL spP IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL dzP IS eprAzError(rvP, SHIP:VELOCITY:ORBIT, 0, EPR_TGT_LAT, EPR_TGT_LNG).
    LOCAL dbP IS eprAzDeadband(eprMach(SHIP:ALTITUDE, spP), TRUE).
    LOCAL rgP IS eprGcDist(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG).
    o6TjPre(spP, dzP, dbP).
    edTick(dzP, dbP, rgP).
}
// ENTRY TRAJ through the pre-entry waits: the loop's TRAJ block (its trajUpdate call, below) with the pre-initiate values (the
// schedule's alpha, the bank held where it is: no command yet). KEEP IN STEP with the loop's block. O6_TJ_PRE FALSE = off.
FUNCTION o6TjPre {
    PARAMETER spd, dzP, dbP.
    IF NOT O6_TJ_PRE OR NOT TRAJ_ON OR OPS6_GR OR NOT TJ_OK { RETURN. }
    IF TIME:SECONDS < o6TjNext { RETURN. }
    SET o6TjNext TO TIME:SECONDS + O6_TJ_PRE_DT.
    LOCAL tjRgo IS eprGcDist(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG).
    tjLiveFam().
    SET TJ_BUG_ON TO EPR_FAM_READY AND EPR_FAM_OK AND TJ_OK.
    IF TJ_BUG_ON {
        IF EPR_FAM_ADD {
            SET tjRgo TO talRngTo(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG) + eprFamExcess().
        }
        IF NOT TJ_LIVEFAM { SET tjRgo TO tjTalRange(spd, tjRgo). }
    }
    LOCAL bkP IS bankActual().
    trajUpdate(spd, tjRgo, EPR_GS_DREF * 3.28084, FD_DRAG * 3.28084,
               talAoA(spd, -1), VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE),
               EPR_GS_SIGN * EPR_GS_ROLLREF, bkP, bkP, EPR_GS_CORR,
               dzP, dbP,
               SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA, SHIP:ALTITUDE / 1000,
               SHIP:VERTICALSPEED, PTRIM_ANG, FD_LIFT / EPR_G0,
               tjURowU(EPR_GS_U_ST), CHOOSE 1 IF EPR_GS_REVERSING ELSE 0, MISSIONTIME,
               ETRIM_ANG,
               EPR_GS_SIGN * (CHOOSE eprBankWithFlare(EPR_GS_ROLLREF, spd) IF EPR_FAM_ADD ELSE EPR_GS_ROLLREF),
               tjURowBank(spd, EPR_GS_U_ST)).
}

// NOTE: this dumps whatever the valve is plumbed to -- the valve must be draining MonoPropellant here.
// THE MP DUMP WAITS UNTIL STEADY AT THE ENTRY ATTITUDE (the jets' turn to it done first): the nose within MP_STEADY_DEG
// of entrySteer's and the body rates under MP_STEADY_W for MP_STEADY_S; at most MP_STEADY_TMO_S, and not past
// MP_STEADY_Q. The log and the TAL's entry page run through the wait, as through the dump.
FUNCTION mpSteadyWait {
    LOCAL t0 IS TIME:SECONDS.
    LOCAL tOk IS -1.
    LOCAL held IS FALSE.
    setAction("mp wait att").
    UNTIL held OR TIME:SECONDS - t0 > MP_STEADY_TMO_S OR SHIP:Q * CONSTANT:ATMTOKPA > MP_STEADY_Q {
        LOCAL ok IS VANG(SHIP:FACING:FOREVECTOR, entrySteer():FOREVECTOR) < MP_STEADY_DEG
            AND SHIP:ANGULARVEL:MAG * CONSTANT:RADTODEG < MP_STEADY_W.
        IF NOT ok { SET tOk TO -1. }
        ELSE IF tOk < 0 { SET tOk TO TIME:SECONDS. }
        SET held TO tOk >= 0 AND TIME:SECONDS - tOk >= MP_STEADY_S.
        logFlight().
        o6PreTick().
        WAIT 0.
    }
    noteEvent("MP dump: " + (CHOOSE "steady at the entry attitude" IF held ELSE "not steady at the entry attitude")
        + " after " + ROUND(TIME:SECONDS - t0, 1) + " s").
}

FUNCTION preEntryMonoDump {
    IF NOT MONO_PRE_DUMP OR CG_CALIBRATE OR NOT dumpAvailable() { RETURN. }
    // in the background (mpBgTick): after the hand-off's OMS dump (its tank gate would starve the OMS), and always in the
    // GRTLS modes, whose GRTLS DAP flies its own alpha and bank (never the entry attitude mpSteadyWait waits for) and
    // whose guidance must start at once, as the real alpha recovery does
    IF HO_DUMP OR HO_WAIT OR OPS6_GR {
        IF NOT MP_DEFER {
            SET MP_DEFER TO TRUE.
            mpBgArm().                   // runs it whichever loop flies when the OMS dump ends (TAEM's too)
            noteEvent(CHOOSE "OPS 6: the pre-entry monoprop dump waits for the hand-off's OMS dump (its tank gate would starve the OMS)"
                IF HO_DUMP OR HO_WAIT ELSE "OPS 6: the pre-entry monoprop dump runs in the background while the GRTLS flies").
        }
        RETURN.
    }
    // the baked constant: one odd entry's monoUsed does not move the next entry's target
    LOCAL usedEst IS MONO_USED_EST.
    LOCAL tgt IS MONO_PEAK_UNITS + MONO_PRE_FRAC * usedEst.
    LOCAL cur IS monoTotalAll().
    IF cur <= tgt + MONO_PRE_MIN { setAction("mp ok " + ROUND(cur)). RETURN. }
    // THE VALVES MUST DRAIN MONOPROPELLANT: a valve on LiquidFuel + Oxidizer only ("Drain: No" for MonoPropellant
    // in the valve's menu) sheds no monoprop, and RCS use alone can pass a small-drop check. kOS cannot set a valve's
    // resource list, only read how many resources it drains -- so say so and go on without the dump.
    IF NOT dumpMonoReady() {
        setAction("mp valve: no mono").
        opsWarn("*** MP DUMP SKIPPED: valves do not drain mono (valve menus: Mono, LF, Ox all Drain: Yes)").
        noteEvent("MP dump skipped: the drain valves do not drain MonoPropellant").
        RETURN.
    }
    mpSteadyWait().                      // at the entry attitude first
    setAction("mp dump>" + ROUND(tgt)).
    dumpSelect(LIST("MonoPropellant")).   // gate tank flow so the valve sheds monoprop only
    LOCAL t0 IS TIME:SECONDS.
    LOCAL startMP IS cur.
    LOCAL tPrev IS t0.        // the last check's time and monoprop: the measured rate and the loop's period (the early close)
    LOCAL mPrev IS cur.
    dumpValve(TRUE).
    UNTIL monoTotalAll() <= tgt OR (TIME:SECONDS - t0) > MONO_PRE_TMO_S {
        IF (TIME:SECONDS - t0) > MONO_PRE_CHECK_S AND (startMP - monoTotalAll()) < MONO_PRE_CHECK_U {
            setAction("mp dump FAIL").    // monoprop not falling -- check all resources are selected in the valve PAW
            BREAK.
        }
        // The entry log runs through the dump: this loop is the one wait between the 80 km crossing and the Phase 3
        // loop, so logging here starts the log at the interface.
        logFlight().
        o6PreTick().                     // the TAL's entry page through the dump
        // The early close: at ~80 units/s one 0.24 s check is worth ~19 units, so stopping at the first check below
        // the target can leave the dump ~20 units under it. From the measured rate: when the target falls before the
        // next check (1.5 x the last period), wait out the remainder less the valve's lag, and close.
        LOCAL tNow IS TIME:SECONDS.
        LOCAL mNow IS monoTotalAll().
        IF tNow - tPrev > 0.01 AND mPrev > mNow {
            LOCAL tLeft IS (mNow - tgt) * (tNow - tPrev) / (mPrev - mNow) - MONO_PRE_LAG_S.
            IF tLeft < 1.5 * (tNow - tPrev) {
                IF tLeft > 0 { WAIT tLeft. }
                BREAK.
            }
        }
        SET tPrev TO tNow.
        SET mPrev TO mNow.
        WAIT 0.1.
    }
    dumpValve(FALSE).
    dumpSelectAll().
    setAction("mp set " + ROUND(monoTotalAll())).
}
// The deferred dump's own trigger: mpBgTick every MP_BG_DT s until the dump is done (MP_DEFER FALSE), whichever
// loop flies (the GRTLS / entry loops also call it from updateCgTrim: a second call in a tick is harmless)
FUNCTION mpBgArm {
    SET MP_BGN TO 0.
    WHEN TIME:SECONDS >= MP_BGN THEN {
        SET MP_BGN TO TIME:SECONDS + MP_BG_DT.
        IF MP_DEFER { mpBgTick(). }
        RETURN MP_DEFER.
    }
}
// the deferred pre-entry monoprop dump, without blocking the loop (each updateCgTrim): once the hand-off's OMS dump
// is over, the gate to monoprop and the valve open; closed and the gate back at preEntryMonoDump's target, its timeout, or
// no fall in MONO_PRE_CHECK_S; the entry model's mass (eprMassTrack) follows it each tick it runs, the closing one too
FUNCTION mpBgTick {
    IF NOT MP_DEFER OR HO_DUMP OR HO_WAIT { RETURN. }
    LOCAL cur IS monoTotalAll().
    IF MP_BG:LENGTH = 0 {
        LOCAL tgt IS MONO_PEAK_UNITS + MONO_PRE_FRAC * MONO_USED_EST.
        IF cur <= tgt + MONO_PRE_MIN OR NOT dumpMonoReady() {
            SET MP_DEFER TO FALSE.
            noteEvent("OPS 6: the deferred monoprop dump not needed (" + ROUND(cur) + " units" + (CHOOSE "" IF dumpMonoReady()
                      ELSE ", the valves do not drain MonoPropellant") + ")").
            RETURN.
        }
        dumpSelect(LIST("MonoPropellant")).
        dumpValve(TRUE).
        SET MP_BG TO LEXICON("tgt", tgt, "t0", TIME:SECONDS, "m0", cur).
        noteEvent("OPS 6: the deferred monoprop dump: " + ROUND(cur) + " -> " + ROUND(tgt) + " units").
        RETURN.
    }
    eprMassTrack().                      // the model (the GRTLS's Nz, the TAL's entry) at the mass the dump leaves
    LOCAL dt IS TIME:SECONDS - MP_BG["t0"].
    LOCAL fail IS dt > MONO_PRE_CHECK_S AND MP_BG["m0"] - cur < MONO_PRE_CHECK_U.
    IF cur <= MP_BG["tgt"] OR dt > MONO_PRE_TMO_S OR fail {
        dumpValve(FALSE).
        dumpSelectAll().
        SET MP_DEFER TO FALSE.
        noteEvent("OPS 6: the deferred monoprop dump " + (CHOOSE "FAILED (not falling)" IF fail ELSE "done") + ": "
                  + ROUND(cur) + " units in " + ROUND(dt, 1) + " s").
    }
}
// Per-tick CG trim (called in the Phase 3 loop).
// the FAR target's walk toward zero elevon (see CG_FAR_ADAPT_ON)
FUNCTION cgFarAdapt {
    PARAMETER err.
    LOCAL pinUp IS ETRIM_ANG <= 0 - CG_FAR_ELEV_DB.     // the elevons carry nose up: the CoM is forward of where FAR trims
    LOCAL pinDn IS ETRIM_ANG >= CG_FAR_ELEV_DB.
    IF NOT (pinUp OR pinDn) OR ABS(err) > CG_DEADBAND_M { SET cgPinT TO -1. RETURN. }
    IF cgPinT < 0 { SET cgPinT TO TIME:SECONDS. RETURN. }
    IF TIME:SECONDS - cgPinT < CG_FAR_ADAPT_HOLD_S { RETURN. }
    SET cgPinT TO -1.
    LOCAL nw IS MIN(CG_FAR_ADAPT_MAX_M, MAX(0 - CG_FAR_ADAPT_MAX_M, cgAdaptM + (CHOOSE 0 - CG_FAR_ADAPT_STEP_M IF pinUp ELSE CG_FAR_ADAPT_STEP_M))).
    IF nw = cgAdaptM { RETURN. }
    SET cgAdaptM TO nw.
    SET CG_TARGET_FORE TO CG_REF_FORE_M + CG_TARGET_BIAS_M + CG_FAR_BIAS_M + cgAdaptM.
    noteEvent("FAR CG target " + ROUND(CG_TARGET_FORE, 3) + " m (walked " + ROUND(cgAdaptM, 2) + " m; elevon "
              + ROUND(ETRIM_ANG, 1) + ", flap " + ROUND(PTRIM_ANG, 1) + ")").
}

FUNCTION updateCgTrim {
    mpBgTick().
    IF NOT CG_TRIM_ON OR CG_CALIBRATE OR NOT cgRefOK { RETURN. }
    IF TIME:SECONDS - cgTrimT < CG_TRIM_DT { RETURN. }
    SET cgTrimT TO TIME:SECONDS.
    LOCAL err IS cgFore() - CG_TARGET_FORE.    // + = CoM too far forward
    SET cgErrM TO err.
    SET cgMonoF TO monoIn(cgFwdTanks).
    SET cgMonoA TO monoIn(cgAftTanks).
    IF FAR_ON AND CG_FAR_ADAPT_ON { cgFarAdapt(err). }
    IF MONO_LOG_ON {
        LOCAL mt IS cgMonoF + monoIn(cgAftTanks).   // = monoTotalAll(): classifyCgTanks holds every monoprop tank
        IF mt < cgMonoMin { SET cgMonoMin TO mt. }
        IF ABS(err) > cgMaxAbsErr { SET cgMaxAbsErr TO ABS(err). SET cgMonoAtMaxErr TO mt. }
    }
    IF ABS(err) <= CG_DEADBAND_M {
        setCgXfer(0).
    } ELSE IF err > 0 {
        IF monoIn(cgFwdTanks) > 0.1 AND monoCap(cgAftTanks) > 0.1 { setCgXfer(1). } ELSE { setCgXfer(0). }
    } ELSE {
        IF monoIn(cgAftTanks) > 0.1 AND monoCap(cgFwdTanks) > 0.1 { setCgXfer(0 - 1). } ELSE { setCgXfer(0). }
    }
    updateCgDump(err).
}

{   // Phase 3 (the entry)
CLEARSCREEN.                       // the entry interface: the console stays blank to wheel stop
setAction("entry guid").
// The panel goes up at the interface, not before: it was built and validated on the coast, so a missing sidecar
// is known about while there is still time to fix it, but nothing on it means anything until bankNow starts moving.
IF TRAJ_ON AND NOT o6DeckOn { trajShow(). }   // the TAL's is up since its DAP (o6DeckOn)
// the TAL's DAP buttons on the deck from EI and HUD | HUD CAM on the bottom window's row, as ops3q's (BAILOUT grey
// to TAEM); an RTLS / CONT builds its row at tdGrStart (the GRTLS loop)
IF grdOn AND NOT OPS6_GR AND NOT o6DeckOn {
    dapGuiBuild("ORBITER DAP", "ENTRY", FALSE, TRUE).
    SET dBtnBail:ENABLED TO FALSE.
}
IF NOT OPS6_GR AND NOT o6DeckOn { edDeckUp(). }   // the entry page (lib_entdisp), or the row alone
RCS ON.
// SAS is already off and steering is already locked to entrySteer(), both taken at the end of the warp, so the
// vehicle has been holding AoA 40 wings-level through the last of the coast. Nothing changes at the interface
// except that bankNow starts moving: no attitude transient at Mach 12. ROLLCONTROLANGLERANGE was already widened
// to 180 at the attitude lock, for the same reason.
SET logPhase TO 3.
SET bankNow  TO 0.
SET entryStartT TO TIME:SECONDS.
// eprArm sets the entry target: EPR_TGT_LAT/LNG, which eprFamInvert uses to measure range-to-go (without it guidance
// would measure its range to the origin off West Africa and rail at u = 1.00 and bank 85 from the moment it initiates).
SET EPR_BUDGET TO EPR_SHADOW_BUDGET.
// Aim at where TAEM should be crossed (see the note by EPR_TAEM_BACK_M; 0 = the FTP itself); RWY_HEADING + 180 is
// the reciprocal, so the walk back is uprange for either runway.
// KSC_TARGET is set in Phase 0.2, from the plan when there is one and by the fallback otherwise, so the aim is
// read from there rather than from PLAN_D, which may not exist. One source: two reads could disagree about what
// "the aim" is, and the planner's runway choice and FTP are not recomputable here without repeating the rev search.
LOCAL eprAim IS destGeo(KSC_TARGET, RWY_HEADING + 180, EPR_TAEM_BACK_M).
LOCAL aimLat IS eprAim:LAT.
LOCAL aimLng IS eprAim:LNG.
noteEvent("entry aim " + ROUND(aimLat, 4) + " / " + ROUND(aimLng, 4)
          + " (runway " + RWY_NAME + ")").
// Clamp the OMS gimbal to 1%, turning it into a passive control-output sensor: Gimbal:PITCHANGLE reports the COMMANDED
// control on a -1..1 scale (the only route to the applied control in kOS), and at a 1% limit (0.05 deg of travel out of
// 5) it tracks raw pitch with zero error, a full-resolution reading from an actuator with no meaningful authority. At
// full authority the gimbal would be a real effector, and the kOS docs state that STEERINGMANAGER does not account for
// control surfaces or atmospheric drag. Done at the interface: the OMS burns use the gimbal's authority to hold
// attitude without spending RCS, and they are over. The lock must be FALSE or PITCHANGLE returns a hard 0
// (gimbal.gimbalLock ? 0 : gimbal.gimbalAnglePitch), which looks like no control demand; gmb_lock is logged so that
// stays visible. With the GRTLS DAP on (lib_grdap) its tick sets every OMS gimbal's limit by its engine (100 % while
// a dump burns on, 1 % once off), so not here.
IF gmbLive() AND NOT grdOnNow() {   // Not GMB_HAVE alone: the engine may be gone
    LOCAL gmod IS GMB_ENG:GETMODULE("ModuleGimbal").
    IF gmod:HASFIELD("gimbal limit") {
        gmod:SETFIELD("gimbal limit", 1).
    }
    SET GMB_ENG:GIMBAL:LOCK TO FALSE.
    WAIT 0.
}

// OPS 6: eprArm ran before the build (no geodesy re-stamp under it)

// The family is built on the coast, before the interface, so guidance is fully referenced from the first tick of
// Phase 3: there is no first-solve window to cover and nothing to seed.

noteEvent("entry target armed on TAEM aim " + ROUND(aimLat, 4)
          + " / " + ROUND(aimLng, 4) + "  ("
          + ROUND(EPR_TAEM_BACK_M / 1000, 1) + " km uprange of the FTP)").

// The target must not be at the origin: EPR_TGT_LAT/LNG start at 0 and are only set by eprArm. If that call is
// ever skipped, guidance measures range to 0/0 in the Atlantic (3986 km to go against a family reaching 2320) and
// rails the whole way, u pinned at 1.00 and bank at 85. Nothing downstream can tell that apart from a genuinely
// unreachable target, so it is caught HERE, where the value is set. 0.01 deg is about 1.1 km, far outside any
// rounding, and no runway in this game is within 1 km of the origin.
IF ABS(EPR_TGT_LAT) < 0.01 AND ABS(EPR_TGT_LNG) < 0.01 {
    opsWarn("*** ENTRY TARGET AT 0/0: eprArm did not take. Falling back to the fixed bank hold.").
    noteEvent("ENTRY TARGET UNSET (0/0) -- eprArm did not take, falling back to bank hold").
    SET EPR_FAM_OK TO FALSE.
    SET EPR_FAM_WHY TO "target unset".
}
// cargo CG management: cache monoprop tanks, then capture (calibration entry) or load the target
classifyCgTanks().
IF CG_CALIBRATE { captureCleanCg(). } ELSE { loadCleanCg(). }
// Not while a deferred dump owns the valve (MP_DEFER): in the RTLS the Phase 2 call
// defers and mpBgArm's trigger opens the valve at once; this reset closed it under the running dump ("FAILED (not falling)",
// the forward RCS full, TAEM trim-limited, 539 / 553 m short). mpBgTick closes it itself when the dump ends.
IF NOT MP_DEFER {
    IF dumpAvailable() { setDumpValve(FALSE). }   // CG system takes the dump valve from a known-closed state at EI
    SET cgValveOpen TO FALSE.
}
SET cgDumpActive TO FALSE.
readDumpRate().   // learn the valve full drain rate so the script can scale it
IF talMode <> "SPLITS" { preEntryMonoDump(). eprMassTrack(). }   // shed monoprop to the authority-optimal level, then the entry model at the mass it left
SET cgMonoStart TO monoTotalAll().
SET cgMonoMin TO cgMonoStart.
SET cgMaxAbsErr TO 0.
SET cgMonoAtMaxErr TO cgMonoStart.
SET monoLogged TO FALSE.
IF MONO_LOG_ON AND NOT EXISTS(MONO_LOG_FILE) {
    IF SOCK_LOG { LOG "met_s,mono_start,mono_end,mono_used,mono_min,mono_at_maxerr,max_abs_err,cg_target,cg_err_end" TO MONO_LOG_FILE. }
}
// Steering is already locked to entrySteer(), taken at the end of the warp so the vehicle reaches the interface at
// AoA 40 wings-level. It is not re-locked here, so the two sites cannot drift apart; the lock is live, recomputed
// every tick, so control keeps flying even while this loop is busy drawing.
LOCAL lastT IS TIME:SECONDS.

opsCls().
IF NOT OPS6_GR {   // the TAL's entry loop; an RTLS flies the GRTLS loop below
// the ENTRY TRAJ page's live reads for its 10 Hz redraws between the guidance cycles (traj_display's
// TJ_LIVE): the same expressions as the trajUpdate call in the loop below (the bug's range among the generic lines once
// the live family is in: TJ_BUG_ON, set by the loop)
SET TJ_LIVE TO {
    LOCAL spd IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL rg IS eprGcDist(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG).
    IF TJ_BUG_ON {
        IF EPR_FAM_ADD {
            SET rg TO talRngTo(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG) + eprFamExcess().
        }
        IF NOT TJ_LIVEFAM { SET rg TO tjTalRange(spd, rg). }   // on the live family's own panels, unmapped
    }
    RETURN LIST(spd, rg, VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE), bankActual(),
                SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA, SHIP:ALTITUDE / 1000, SHIP:VERTICALSPEED, MISSIONTIME).
}.
GLOBAL TAL_GD_HELD_X IS 0.     // The display cross / deadband held while SW 02 ENTRY holds (ops3q's ENTRY_GD_HELD_X / _DB)
GLOBAL TAL_GD_HELD_DB IS 0.
GLOBAL TAL_GD_HELD IS 0.     // The last bank command while SW 02 ENTRY holds the guidance (the C# step is not called); declared HERE, not in the loop (a GLOBAL statement in a loop is assigned again every pass: the hold would read 0)
UNTIL ALTITUDE < HANDOVER_ALT OR SHIP:VELOCITY:SURFACE:MAG < AOA_LOW_SPEED OR taemRngSw() {
    IF HO_DUMP { eprMassTrack(). }   // a 3EO TAL's dump burning on: the model (the build too) at the mass now
    // Commanded angle of attack from the speed schedule (clamped to the band): AOA_HIGH at/above AOA_HIGH_SPEED,
    // ramping to AOA_LOW at AOA_LOW_SPEED. entrySteer() builds the velocity-relative attitude live; here the
    // commanded AoA is published for it to use.
    LOCAL spd IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL aoaCmd IS talAoA(spd, (CHOOSE TAL_VEH_VI IF EPR_GS_STARTED ELSE -1)).   // OPS 6: the TAL schedule (lib_tal)
    // The alpha in use: the schedule, or eprGuidStep's modulated command, SET ONCE PER CYCLE after the guidance (below
    // the fallback branch). The steering lock reads entryAoaCmd every tick and this loop spans several: setting the
    // schedule here and the command later would flip the target between the two for the ticks the guidance takes.
    LOCAL aoaFly IS aoaCmd.

    // OPS 6: THE BACKGROUND BUILD, one slice a cycle until the family is ready. If the vehicle initiates first (not
    // expected, >= 3.8x margin) and two members are stored (EPR_FAM_ORDER builds 0 and 85 first: they bracket the
    // range; under the addon, the members it has done), finish with them; with fewer keep building, up to TAL_FAM_LATE_S past initiate, then finish anyway (two or
    // more usable -> flown; else ops3q's fallback bank hold below).
    IF NOT EPR_FAM_READY {
        IF EPR_GS_STARTED AND (eprFamCount() >= 2 OR TIME:SECONDS - TAL_VEH_T > TAL_FAM_LATE_S) {
            SET EPR_FAM_ACTIVE TO FALSE.
            SET EPR_TRACE_ON TO FALSE.
            eprFamFinish().
            talFamDone(" -- finished at the vehicle's initiate").
        } ELSE IF talFamRun(TAL_BUILD_BUDGET) {
            talFamDone("").
        }
    }
    IF EPR_GS_STARTED { fuiSimPt("GUID_INIT", 0). }   // SimSup's GUID_INIT point = the vehicle's guidance initiate (once; nothing while SIMSUP is not latched)
    LOCAL bankTarget IS 0.
    LOCAL gdLost IS FALSE.       // SW 02 ENTRY (flfxSwGuid, the same test as ops3q's entry hold)
    IF DEFINED FLFX_SWPROG { SET gdLost TO flfxSwGuid("ENTRY"). }
    LOCAL dispCross    IS 0.
    LOCAL dispDeadband IS 0.
    LOCAL eprFlew IS FALSE.

    // ---- FAMILY-DRIVEN BANK ----------------------------------------------------------------
    //  eprGuidStep is the whole guidance cycle: range inversion, the Hdot tracker on the reference roll, the 2.14.1
    //  deadband, the reversal latch, the 2.14.2 minimum-bank floor, and a rate- AND acceleration-limited slew.
    //  No integration in this loop: the family is built on the coast and every tick is table lookup.
    //  dt is measured, not passed. This loop runs at WAIT 0.1 nominally but not exactly, and the slew advances bank
    //  by rate*dt, so a hardcoded dt is a wrong roll rate, which desynchronises the vehicle from the model that
    //  assumes 5 deg/s. eprGuidStep reads TIME:SECONDS itself and clamps the result.
    //  The epoch is eprFamTRot(), not a raw clock: the family build skips the vacuum coast analytically, so its frame
    //  starts EPR_FAM_TCOAST later than the caller's (up to ~1000 s, about 60 km of longitude at JNSQ's rotation
    //  rate). eprFamTRot converts absolute time into the family's epoch.
    IF EPR_FAM_READY AND SHIP:ALTITUDE < TAL_DATUM_ALT {   // the datum follows KSP's frame (TAL_DATUM_ALT's note)
        LOCAL dDat IS eprDatumFollow(-SHIP:BODY:POSITION, SHIP:GEOPOSITION:LNG, TAL_DATUM_TOL).
        IF dDat <> 0 {
            SET TAL_DATUM_N TO TAL_DATUM_N + 1.
            IF ABS(dDat) > 0.1 { noteEvent("OPS 6: geodesy datum re-taken at " + ROUND(SHIP:ALTITUDE / 1000, 1) + " km, was "
                                           + ROUND(dDat, 3) + " deg (" + ROUND(eprGcDist(SHIP:GEOPOSITION:LAT, 0, SHIP:GEOPOSITION:LAT, dDat) / 1000, 1) + " km) east of the ship"). }
        }
    }
    IF gdLost {
        SET bankTarget TO TAL_GD_HELD.
        SET dispCross TO TAL_GD_HELD_X.
        SET dispDeadband TO TAL_GD_HELD_DB.
    }
    ELSE IF GUID_SRC = "epr" AND (EPR_FAM_OK OR NOT EPR_FAM_READY) {   // OPS 6: also while the build runs (|bank| EPR_PREENTRY_BANK)
        LOCAL rv IS -SHIP:BODY:POSITION.
        LOCAL vv IS SHIP:VELOCITY:ORBIT.
        eprTrimTrack(ETRIM_ANG, eprMach(SHIP:ALTITUDE, spd)).   // the model at the elevon trim of the moment (entry_predict EPR_TRIM_*)
        // FD_DRAG is handed in so the loop closes on the vehicle, not the model. Passing -1 for dt keeps eprGuidStep's
        // own timing; the extra argument is the measured drag, from lib_vehicle.
        // The alpha modulation: the vehicle's actual angle of attack goes in, so eprGuidStep can command alpha within
        // EPR_AM_LIM of the schedule (EPR_GS_ACMD, -1 = the schedule) and take the bank loop's drag error at the
        // scheduled alpha (the demodulation). entrySteer flies entryAoaCmd. FD_N (the FD sample count) lets it pair
        // each drag sample with the mean alpha of its window (EPR_AM_SYNC).
        SET bankTarget TO talGuidStep(rv, vv, EPR_TGT_LAT, EPR_TGT_LNG,
                                      eprFamTRot(TIME:SECONDS), -1, fdDragFilt(),
                                      VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE), FD_N).
        SET TAL_GD_HELD TO bankTarget.
        fuiSimBank(bankTarget).              // ROLL_REV (the guidance's reversals)
        IF EPR_GS_ACMD > 0 { SET aoaFly TO EPR_GS_ACMD. }
        // TAL_V4N: one event line when the servo first passes the top member, one when the Nz limiter first cuts alpha
        IF TAL_V4N_ON AND NOT TAL_V4N_SAID_U AND EPR_GS_U > 1 {
            SET TAL_V4N_SAID_U TO TRUE.
            noteEvent("OPS 6: servo overbank: u " + ROUND(EPR_GS_U, 3) + " past the top member").
        }
        IF TAL_V4N_ON AND NOT TAL_V4N_SAID_NZ AND TAL_NZ_N > 0 {
            SET TAL_V4N_SAID_NZ TO TRUE.
            noteEvent("OPS 6: Nz limiter: alpha cut to " + ROUND(EPR_GS_ACMD, 1) + " deg (Nz " + ROUND(TAL_NZ_NOW, 2) + " g led)").
        }
        SET dispCross TO EPR_GS_AZ.
        // the DB lines flash at the first reversal: the guidance widens the band the cycle its first reversal fires
        // (eprAzDeadband: 10.5 -> 17.5), so |DELAZ| would never show outside it; the first band is shown until that
        // roll is done (EPR_GS_REVERSING)
        LOCAL dbFirst IS EPR_GS_REV = 0.
        IF EPR_GS_REV = 1 AND EPR_GS_REVERSING { SET dbFirst TO TRUE. }
        SET dispDeadband TO eprAzDeadband(eprMach(SHIP:ALTITUDE, spd), dbFirst).
        SET eprFlew TO TRUE.
    } ELSE {
        // ---- FALLBACK BANK HOLD ------------------------------------------------------------
        //  Reached only when the family is unusable. The vehicle is suborbital and entering regardless, so this exists
        //  to keep it STABLE AND ROUGHLY ON TRACK rather than to hit anything: a fixed magnitude with the lateral logic
        //  still running, which is what the orbiter's own guidance degrades to when the reference is lost.
        //  fbBank is the plan's bank where there is one (the planner solved a burn at which THAT CONSTANT BANK arrives
        //  on the aim, so it is a verified feedforward) and NOMINAL_BANK otherwise. The deadband comes from
        //  eprAzDeadband and the reversals from its crossings, so the vehicle steers toward the site; only the
        //  DOWNRANGE half is missing. Expect a large miss.
        LOCAL fbBank IS NOMINAL_BANK.
        IF PLAN_OK { SET fbBank TO planGet("bank", NOMINAL_BANK). }
        LOCAL rvF IS -SHIP:BODY:POSITION.
        LOCAL vvF IS SHIP:VELOCITY:ORBIT.
        LOCAL azF IS eprAzError(rvF, vvF, 0, EPR_TGT_LAT, EPR_TGT_LNG).
        LOCAL machF IS eprMach(SHIP:ALTITUDE, spd).
        IF fbSign = 0 { SET fbSign TO CHOOSE 1 IF azF >= 0 ELSE -1. }
        LOCAL dbF IS eprAzDeadband(machF, fbRev = 0).
        IF azF > dbF AND fbSign < 0 { SET fbSign TO 1. SET fbRev TO fbRev + 1. }
        IF azF < 0 - dbF AND fbSign > 0 { SET fbSign TO -1. SET fbRev TO fbRev + 1. }
        SET bankTarget TO fbSign * fbBank.
        fuiSimBank(bankTarget).              // ROLL_REV (the fallback's reversals)
        IF spd <= EPR_BANK_STOP_SPEED { SET bankTarget TO 0. }
        SET dispCross TO azF.
        SET dispDeadband TO dbF.
    }
    IF NOT gdLost { SET TAL_GD_HELD_X TO dispCross. SET TAL_GD_HELD_DB TO dispDeadband. }   // Held for SW 02 ENTRY
    SET entryAoaCmd TO aoaFly.      // the alpha in use: once per cycle (see aoaFly at the top of the loop)

    // Below the cutover speed, stop banking and roll wings-level so the orbiter can pitch its nose down and shed the
    // high entry AoA for the approach. The bank target goes to zero between BANK_LEVEL_HI and BANK_LEVEL_LO (both
    // 762 m/s, so a step, see the note at those constants), and the accel-limited slew below eases the roll back.
    IF NOT gdLost AND spd <= BANK_LEVEL_HI {
        LOCAL lvl IS clamp((spd - BANK_LEVEL_LO) / MAX(BANK_LEVEL_HI - BANK_LEVEL_LO, 1), 0, 1).
        SET bankTarget TO bankTarget * lvl.
    }

    SET grdBkWant TO bankTarget.        // the guidance's bank before the slew (the entry HUD's CSS-roll diamond)
    // The bank slew: drive bankNow straight toward the target, capped at the commanded rate. The
    // rate cap ramps up over BANK_SOFT_TIME at entry start so the opening bank (rolling from rest)
    // eases in; after that it's the full BANK_RATE for the reversals.
    LOCAL dt IS MAX(TIME:SECONDS - lastT, 0.001).
    SET lastT TO TIME:SECONDS.
    LOCAL rateCap IS BANK_RATE * clamp((TIME:SECONDS - entryStartT) / BANK_SOFT_TIME, 0.15, 1).
    // Rate first, then the ACCELERATION limit on how fast that rate may change: the first clamp bounds how fast the
    // bank moves, the second how abruptly that speed may change. Only the second stops a command reversal arriving
    // as a step.
    LOCAL wantRate IS clamp((bankTarget - bankNow) / dt, 0 - rateCap, rateCap).
    LOCAL vBrk IS SQRT(2 * BANK_ACCEL_MAX * ABS(bankTarget - bankNow)).   // the braking bound: the rate that can still stop
    SET wantRate TO clamp(wantRate, 0 - vBrk, vBrk).                       //   at the target (entry_predict's eprBankSlew)
    SET wantRate TO clamp(wantRate, BANK_RATE_NOW - BANK_ACCEL_MAX * dt,
                                    BANK_RATE_NOW + BANK_ACCEL_MAX * dt).
    SET BANK_RATE_NOW TO wantRate.
    SET bankNow TO bankNow + wantRate * dt.
    // entrySteer() (the steering lock) reads bankNow + entryAoaCmd live every tick.

    updateCgTrim().   // cargo CG trim: monoprop fwd/aft (+ optional fuel dump)

    fdSample().                          // cheap: self-gates on FD_MIN_DT
    ptrimUpdate().                       // closed-loop pitch trim, self-gates on q
    IF grdOn AND NOT dSbAuto {           // SPDBK MAN from EI (lib_grdap: the throttle lever), as the GRTLS's
        grdSbMan().
    } ELSE {
        entrySbUpdate().                 // the entry speedbrake (65 below 2000 m/s, ramped to 1500 m/s)
    }

    // No periodic eprInitGeo re-stamp: with EPR_ROT_SCALE at 0 there is no rotation drift to cover.

    // ---- the ENTRY TRAJ display ---------------------------------------------------------
    //  Runs every cycle by default (TRAJ_EVERY raises the interval): skipping frames would show where the vehicle WAS.
    //  Placed with logFlight() so the picture and the logged row are the same tick.
    IF TRAJ_ON {
        SET trajTick TO trajTick + 1.
        IF MOD(trajTick, TRAJ_EVERY) = 0 {
            // Units are converted HERE, not inside the display: the panel's scales are the orbiter's (drag in ft/s2,
            // altitude in km) while the guidance works in SI, and this keeps the display a renderer. EPR_GS_DREF is
            // the reference drag guidance published this tick (a value, not a call); FD_DRAG is the measured actual.
            LOCAL tjD IS EPR_GS_DREF * 3.28084.
            LOCAL tjA IS FD_DRAG * 3.28084.
            LOCAL tjRgo IS eprGcDist(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG,
                                     EPR_TGT_LAT, EPR_TGT_LNG).
            LOCAL tjRgoE IS tjRgo.               // the entry page's RANGE: the range itself, never the mapped one below
            // OPS 6: the bug among the generic lines where the vehicle sits among the live family's (lib_tal
            // talTrajRange); no bug or box before the live family is in. The live family's own panels once drawn
            // (tjLiveFam; the bug then unmapped)
            tjLiveFam().
            SET TJ_BUG_ON TO EPR_FAM_READY AND EPR_FAM_OK AND TJ_OK.
            IF TJ_BUG_ON {
                // EPR_FAM_ADD: the bracket on the range the guidance inverts (its HAC reference + the excess), so the bug
                // sits where the bank flown puts the vehicle among the live family
                IF EPR_FAM_ADD {
                    SET tjRgo TO talRngTo(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG, EPR_TGT_LAT, EPR_TGT_LNG)
                                 + eprFamExcess().
                }
                SET tjRgoE TO tjRgo.
                IF NOT TJ_LIVEFAM { SET tjRgo TO tjTalRange(spd, tjRgo). }   // talTrajRange (C#); not on the live panels
            }
            trajUpdate(spd, tjRgo, tjD, tjA,
                       aoaCmd, VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE),
                       EPR_GS_SIGN * EPR_GS_ROLLREF, bankTarget, bankActual(), EPR_GS_CORR,
                       dispCross, dispDeadband,
                       // kPa: trajUpdate renders this as ROUND(qbar, 1), and fed raw atmospheres that
                       // would show one significant figure of nothing.
                       SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA, SHIP:ALTITUDE / 1000,
                       // PTRIM_ANG and ETRIM_ANG: the display formats these with tjTrim() (U/D prefix, flap angle, and
                       // +elevon when the elevons are carrying anything). Negative PTRIM_ANG is nose up.
                       SHIP:VERTICALSPEED, PTRIM_ANG, FD_LIFT / EPR_G0,
                       // U = the state's u, not the servo's; ROLL REF above stays the servoed u's
                       tjURowU(EPR_GS_U_ST), CHOOSE 1 IF EPR_GS_REVERSING ELSE 0, MISSIONTIME,
                       ETRIM_ANG,
                       // the ROLL REF row through the TAEM bank ramp the command flies (EPR_FAM_ADD's bank column is
                       // before it)
                       EPR_GS_SIGN * (CHOOSE eprBankWithFlare(EPR_GS_ROLLREF, spd) IF EPR_FAM_ADD ELSE EPR_GS_ROLLREF),
                       // the U row's bank, the family's at the state's u (through the ramp, as ROLL REF)
                       tjURowBank(spd, EPR_GS_U_ST)).
            edTick(dispCross, dispDeadband, tjRgoE).  // the entry page (HORIZ SIT in entry), the same tick
        }
    }

    logFlight().
    IF grdOn { grdHudPass(). }           // the entry HUD (loaded on the crew's first HUD / HUD CAM press; off by default)
    IF grdOn AND hdOK AND hdVis {        // the HUD every tick through the loop's 0.1 s (as the GRTLS loop's; hdTick /
        LOCAL tw IS TIME:SECONDS + 0.1.  //   hdgTick hold it to HD_MAX_HZ)
        UNTIL TIME:SECONDS >= tw {
            WAIT 0.
            grdHudPass().
        }
    } ELSE {
        WAIT 0.1.
    }
}
}   // the end of the TAL's entry loop
IF OPS6_GR {   // THE GRTLS (lib_grtls; FSSR 4.8, the intact path): phases 6 / 5 / 4 to Mach GR_MSW1,
    //   then the hand-off below as the TAL's (landRun RWY_NAME); HANDOVER_ALT hands over in any phase (said on the events line)
    IF TRAJ_ON { trajHide(). }           // the entry's drag display has no meaning in a GRTLS
    IF GR_COAST_FILE = CST_FILE { SET GR_COAST_FILE TO cstFileHere(). }   // the coast where the orbiter is
    IF GR_BLUE_SHORE AND (GR_CONT = 2 OR RCH_SHORT OR RCH_BLUE0) {   // a BLUE, or an RTLS that turns / may turn BLUE
        IF grtlsCoastLoad(GR_COAST_FILE) {
            noteEvent("OPS 6 BLUE: the coast table " + GR_COAST_FILE + " (" + GR_COAST["s"]:LENGTH + " segments): a BLUE "
                      + "banks toward the line " + ROUND(GR_BLUE_DOFF / 1000, 1) + " km off the nearest coast").
        } ELSE {
            noteEvent("*** OPS 6 BLUE: no coast table (" + GR_COAST_FILE + "): a BLUE flies wings level").
        }
    }
    grtlsStart(RWY_NAME, entryAoaCmd, _log_filePath:REPLACE(".csv", "_grtls.csv")).
    SET dRwyAlt TO ldOtherEnd(RWY_NAME).    // the SW RWY button's runway in the GRTLS too (lib_grtls grtlsDmPress)
    IF o6GrPgUp {                        // up since the hand-off (above)
    } ELSE IF tdGrStart() {              // the MM 602 pages (without their files: none); the
        dapGuiBuild("ORBITER DAP", "GRTLS", FALSE, grdOn).   //   DAP's buttons on them (TAEM's whole row, the
            //   GRTLS DAP's PITCH / ROLL/YAW / SPDBK live, the rest grey until landRun)
        IF DEFINED TD_CS_STATE {         // the pages' C# switch, logged
            noteEvent("GRTLS pages: " + TD_CS_STATE + (CHOOSE ", redrawn every " + TD_DT_CS + " s between the cycles" IF tdFast() ELSE ", once a cycle")).
        }
    } ELSE IF grdOn {                    // no pages: the DAP's window (PITCH / ROLL/YAW reachable)
        dapGuiBuild("ORBITER DAP", "GRTLS", FALSE, TRUE).
    }
    IF DEFINED adOn { IF adOn { adClose(). } }   // the OPS 1 pages ops1q left up (ASC_PG_KEEP) go now
    LOCAL grPgTn IS GR["tnext"].         // the pages draw one pass after each guidance cycle (as landRun's)
    LOCAL grPgDue IS FALSE.
    LOCAL grPgNx IS 0.                   // the redraws: while the
                                         //   C# draws the pages (tdFast) they are drawn again every TD_DT_CS between the
                                         //   cycles (a pass apart at least: the loop's WAIT 0.1), on the vehicle now and the
                                         //   cycle's GR (tdGrTick's cyc FALSE); kOS drawing: once per cycle
    LOCAL ssPl IS SS_ON.                 // SPLITS: ssSteer flies phase 8, entrySteer from phase 5;
    LOCAL ssRw IS FALSE.                 //   ssPick's runway end applied once; the loop's floor SS_FLOOR (the pull-out's
    LOCAL grFloor IS CHOOSE SS_FLOOR IF SS_ON ELSE HANDOVER_ALT.   //   lowest is ~10 km: HANDOVER_ALT would cut it)
    LOCAL chOn IS RCH_SHORT AND NOT RCH_BLUE0 AND GR["cont"] = 0 AND NOT SS_ON.   // THE CREW'S CHOICE (the
    LOCAL chLast IS -1.                  //   header): GRTLS / BLUE in VERT SIT's title row, RCH_PICK_S
    IF RCH_BLUE0 AND GR["cont"] = 0 AND NOT SS_ON {   //   from the test, then BLUE; a 2EO cut at once: BLUE at the first
        grtlsBluePick().                 //   guidance cycle, no choice
        noteEvent("OPS 6: BLUE AT ONCE (a 2nd SSME out cut at once, ASC_HO eo2 BLUE; his word BLUE at once): no choice").
        IF tdOn { tdLogEvent("BLUE (2EO)"). }
    }
    LOCAL grBail IS FALSE.               // the crew's BAILOUT taken (the loop, below)
    SET dDmGr TO TRUE.                   // the OTT row from the first guidance cycle (lib_grtls grtlsDmShow)
    LOCAL grDmTn IS GR["tnext"].
    IF chOn {
        SET TD_PICK TO "".
        SET chLast TO CEILING(RCH_T0 + RCH_PICK_S - TIME:SECONDS).
        tdChoice(TRUE, rchText(RCH_T0 + RCH_PICK_S - TIME:SECONDS)).
    }
    UNTIL GR["done"] OR (CHOOSE grtlsBlueEnd() IF GR["cont"] = 2 ELSE ALTITUDE < grFloor) {   // CONT: BLUE to the end (the water)
        LOCAL dt IS MAX(TIME:SECONDS - lastT, 0.001).
        SET lastT TO TIME:SECONDS.
        IF SS_ON OR HO_DUMP { eprMassTrack(). }   // SPLITS / a CONT's dump burning on: the Nz model at the mass now
        IF chOn {                        // THE CREW'S CHOICE: BLUE (picked, or none in time) at the next guidance cycle
            LOCAL chLeft IS RCH_T0 + RCH_PICK_S - TIME:SECONDS.
            IF TD_PICK = "BLUE" OR chLeft <= 0 {
                grtlsBluePick().
                noteEvent(CHOOSE ("OPS 6: THE CREW PICKED BLUE, " + ROUND(TIME:SECONDS - RCH_T0, 1) + " s after the reach "
                          + "test") IF TD_PICK = "BLUE" ELSE ("OPS 6: NO PICK IN " + RCH_PICK_S + " S: BLUE (the default)")).
                IF tdOn { tdLogEvent(CHOOSE "BLUE (CREW)" IF TD_PICK = "BLUE" ELSE "BLUE (AUTO)"). }
                tdChoice(FALSE, "").
                SET chOn TO FALSE.
            } ELSE IF TD_PICK = "GRTLS" {
                noteEvent("OPS 6: THE CREW PICKED GRTLS, " + ROUND(TIME:SECONDS - RCH_T0, 1) + " s after the reach test "
                          + "(it said short): the RTLS flies on to " + RWY_NAME).
                IF tdOn { tdLogEvent("GRTLS (CREW)"). }
                tdChoice(FALSE, "").
                SET chOn TO FALSE.
            } ELSE IF CEILING(chLeft) <> chLast {
                SET chLast TO CEILING(chLeft).
                tdChoice(TRUE, rchText(chLeft)).
            }
        }
        IF dBailReq AND NOT grBail {     // the crew's BAILOUT (lib_dap's two presses 1 s apart, the
            SET grBail TO TRUE.          //   button on top of HORIZ SIT) flies CONT BLUE's bailout:
            LOCAL c0 IS GR["cont"].      //   an RTLS (grtlsBluePick) or a GREEN (as the reach check's) turns BLUE,
            IF c0 = 0 { grtlsBluePick(). } ELSE IF c0 = 1 { SET GR["cont"] TO 2. }   //   no TAEM, the hold below Mach 1
            IF chOn { tdChoice(FALSE, ""). SET chOn TO FALSE. }
            noteEvent("OPS 6: THE CREW'S BAILOUT (BAILOUT, two presses) in phase " + GR["iphase"] + ": "
                      + LIST("the RTLS turns BLUE", "GREEN turns BLUE", "BLUE already")[c0] + "; the bailout hold below Mach "
                      + GR_BAIL_MACH + ", no TAEM").
            IF tdOn { tdLogEvent("BAILOUT (CREW)"). }
            IF GR_BLUE_SHORE AND NOT GR_COAST["ok"] {   // the coast table loaded at the BAILOUT
                IF grtlsCoastLoad(GR_COAST_FILE) {      //   press: the start loads it only when a BLUE may come
                    noteEvent("OPS 6 BAILOUT: the coast table " + GR_COAST_FILE + " (" + GR_COAST["s"]:LENGTH + " segments): "
                              + "the hold banks toward the line " + ROUND(GR_BLUE_DOFF / 1000, 1) + " km off the nearest coast").
                } ELSE {
                    noteEvent("*** OPS 6 BAILOUT: no coast table (" + GR_COAST_FILE + "): the hold flies wings level").
                }
            }
        }
        dapBailTick().                   // a first press unconfirmed in time is dropped
        ldSiteTick().                    // VERT SIT's < SITE >
        IF dDmReq <> "" {                // the crew's OTT row (lib_grtls grtlsDmPress); SW RWY: the runway now
            IF grtlsDmPress() {
                IF ldSiteSw {            // another site: the plan's aim goes, the FTP from the bearing to it
                    SET PLAN_AIM TO 0.
                    SET talIn TO bearing(SHIP:GEOPOSITION, LATLNG(ldRwy["lat"], ldRwy["lon"])).
                }
                applyRunway(GR["rwy"], talIn, PLAN_AIM).
            }
        }
        grtlsCycle(dt, bankNow, BANK_RATE_NOW).   // the guidance every GR_DTG; the alpha command slewed every pass
        IF GR["tnext"] <> grDmTn {       // the OTT row after each guidance cycle
            SET grDmTn TO GR["tnext"].
            grtlsDmShow().
        }
        SET entryAoaCmd TO GR["acmd"].
        IF GR["iphase"] = 7 { dapBailFlies(). }   // the hold flies (the crew's or the BLUE's own): BAILOUT ON
        IF ssPl AND GR["iphase"] <> 8 {  // SPLITS: heads up at phase 5's start: the bank formulation from the bank whose
            SET bankNow TO GR["bank_eq"].   //   lift points as phase 8's (lib_grtls ssBankEq)
            SET BANK_RATE_NOW TO 0.
            IF grdOn { SET grdSs TO FALSE. } ELSE { LOCK STEERING TO entrySteer(). }   // the DAP on the bank
            SET ssPl TO FALSE.
        }
        IF SS_ON AND NOT ssRw AND GR["rwy"] <> "" {   // SPLITS: ssPick's end for landRun (RWY_NAME), once
            SET ssRw TO TRUE.
            IF GR["rwy"] <> RWY_NAME { applyRunway(GR["rwy"], talIn, PLAN_AIM). }
        }
        IF GR["gpk"] AND GR["rwy"] <> RWY_NAME {   // A GREEN's end picked at phase 4's start (lib_grtls grPickGreen):
            applyRunway(GR["rwy"], talIn, PLAN_AIM).   //   RWY_NAME and the aim, as the crew's SW RWY above
        }
        // the bank slew: the entry loop's (the rate cap, the braking bound, then the acceleration limit)
        LOCAL rateCap IS BANK_RATE * clamp((TIME:SECONDS - entryStartT) / BANK_SOFT_TIME, 0.15, 1).
        LOCAL wantRate IS clamp((GR["bank_want"] - bankNow) / dt, 0 - rateCap, rateCap).
        LOCAL vBrk IS SQRT(2 * BANK_ACCEL_MAX * ABS(GR["bank_want"] - bankNow)).   // the braking bound (as the entry loop's)
        SET wantRate TO clamp(wantRate, 0 - vBrk, vBrk).
        SET wantRate TO clamp(wantRate, BANK_RATE_NOW - BANK_ACCEL_MAX * dt, BANK_RATE_NOW + BANK_ACCEL_MAX * dt).
        SET BANK_RATE_NOW TO wantRate.
        SET bankNow TO bankNow + wantRate * dt.
        updateCgTrim().
        fdSample().
        ptrimUpdate().
        IF GR["iphase"] = 7 {            // CONT BLUE's hold: the speedbrake closed (FSSR TGSBC: DSBC = 0 under BAILOUT_ARM)
            IF ENTRY_SB_SET > 0 AND ENTRY_SB_RUD:LENGTH = 2 {
                FOR m IN ENTRY_SB_RUD { IF FAR_ON { surfSetAng(m, 0). } ELSE { IF modLive(m) AND NOT surfFrozen(m) { m:SETFIELD("deploy angle", 0). } } }
                SET ENTRY_SB_SET TO 0.
                SET sbThrottle TO 1.
            }
        } ELSE IF grdOn AND NOT dSbAuto {   // SPDBK MAN, the throttle lever (lib_grdap)
            grdSbMan().
        } ELSE IF NOT SS_ON {            // SPLITS: the speedbrake stays closed to TAEM
            entrySbUpdate().
        }
        logFlight().
        IF grPgDue {                     // the pages, one pass after their cycle
            LOCAL amD IS ldAlphaNow().
            tdGrTick(GR, ldState(), grtlsSense(amD), amD, ENTRY_SB_SET).
            SET grPgDue TO FALSE.
            SET grPgNx TO 0.             // the redraws, from TD_DT_CS after the cycle's draw (the C# drawing only)
            IF DEFINED TD_DT_CS { IF tdFast() { SET grPgNx TO tdGridNx(uiRt()). } }   // real time
        } ELSE IF GR["tnext"] <> grPgTn {
            SET grPgTn TO GR["tnext"].
            SET grPgDue TO tdOn.
        } ELSE IF grPgNx > 0 AND uiRt() >= grPgNx {
            SET grPgNx TO 0.
            IF tdFast() {                // (a fallback since the cycle's draw: no kOS redraws)
                SET grPgNx TO tdGridNx(uiRt()).
                LOCAL amR IS ldAlphaNow().
                tdGrTick(GR, ldState(), grtlsSense(amR), amR, ENTRY_SB_SET, FALSE).
            }
        }
        IF grdOn { grdHudPass(). }       // the HUD (loaded on the crew's first HUD / HUD CAM press; off by default)
        IF grdOn AND hdOK AND hdVis {    // the HUD every tick through the
            LOCAL tw IS TIME:SECONDS + 0.1.   //   loop's 0.1 s (hdTick / hdgTick hold it to HD_MAX_HZ, as TAEM's
            UNTIL TIME:SECONDS >= tw {   //   dapHudTick), not once a pass (<= 8 Hz with the pass's own work)
                WAIT 0.
                grdHudPass().
            }
        } ELSE {
            WAIT 0.1.
        }
    }
    IF chOn { tdChoice(FALSE, ""). }     // (the loop ended inside the choice's time)
    SET dDmGr TO FALSE.                  // landRun's TAEM flies the row from here
    IF GR["cont"] = 2 {                  // CONT BLUE: no TAEM, no landing: the hold ended at GR_BAIL_END; OPS 6 keeps the
        IF GR_DITCH {                    // the ditch's end, in the water
            noteEvent("GRTLS DITCH: in the water (" + SHIP:STATUS + "), " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s, sink "
                      + ROUND(0 - SHIP:VERTICALSPEED, 1) + " m/s, alpha " + ROUND(ldAlphaNow(), 1)).
        }
        noteEvent("CONT BLUE: the bailout hold ended at " + ROUND(ALTITUDE) + " m; no landing site: OPS 6 holds the "
                  + "attitude (CTRL+C ends it)").   //   attitude (the steering stays locked, or the DAP's trigger runs on) until CTRL+C
        logFlight().
        WAIT UNTIL FALSE.
    }
    grtlsEnd(grFloor).
    // the pages stay open (the same GUI, its background swapped): landRun's tdInit turns them to TAEM's (MM 603)
}
}   // end of Phase 3 (the entry)

// ----------------------- HAND OVER TO PILOT --------------------------
setAction("handover").
// NO manual handover -- the entry's LOCK STEERING (entrySteer, 180 deg roll range) holds the attitude while
// landRun builds its GUI and warms its Nz window, and landRun's own LOCK STEERING replaces it; SAS stays off.
RCS OFF.   // RCS off at the TAEM switch
IF CG_TRIM_ON { setCgXfer(0). IF cgDumpActive { stopCgDump(). } }   // stop any CG trim/dump at handover
IF MONO_LOG_ON AND CG_TRIM_ON AND NOT monoLogged {
    LOCAL monoEnd IS monoTotalAll().
    IF SOCK_LOG { LOG ROUND(MISSIONTIME) + "," + ROUND(cgMonoStart,1) + "," + ROUND(monoEnd,1) + "," + ROUND(cgMonoStart - monoEnd,1) + "," + ROUND(cgMonoMin,1) + "," + ROUND(cgMonoAtMaxErr,1) + "," + ROUND(cgMaxAbsErr,3) + "," + ROUND(CG_TARGET_FORE,3) + "," + ROUND(cgErrM,3) TO MONO_LOG_FILE. }
    IF EXISTS(CG_REF_FILE) {                       // persist usage so next entry can pre-trim the load
        LOCAL rj IS READJSON(CG_REF_FILE).
        SET rj["monoUsed"] TO cgMonoStart - monoEnd.
        WRITEJSON(rj, CG_REF_FILE).
    }
    SET monoLogged TO TRUE.
}

// =====================================================================
//  PHASE 4  --  TAEM + A/L GUIDANCE  (lib_land.ks landRun)
// =====================================================================
// landRun flies G4.9 TAEM from here, then G4.10 A/L to the ground and the rollout, on RWY_NAME (the plan's
// runway), starting the pitch loop from the entry's alpha command. Its GUI's CSS button hands the vehicle to
// the pilot (css_dap.ks), END stops it; its log is logs/land_<t>.csv / .txt.
IF TRAJ_ON { trajHide(). }                   // ENTRY TRAJ gives way to VERT SIT / HORIZ SIT, as the orbiter's CRTs
entrySteerGains(FALSE).           // the kOS default steering gains back for TAEM
IF OPS6_GR {                      // SPLITS and a GREEN's pick (grPickGreen): landRun's HAC side = the pick's (its
    IF SS_ON OR GR["gpk"] {       //   rule -same / same by TG_OVERHEAD_DEFAULT on y's sign at its start: set from y's sign now)
        IF GR["ysgn"] <> 0 {
            SET TG_OVERHEAD_DEFAULT TO GR["ysgn"] <> (CHOOSE 1 IF ldState()["y"] >= 0.0 ELSE -1).
        }
    }
}
IF grdOn AND NOT OPS6_GR { SET dBtnBail:ENABLED TO TRUE. }   // the TAL's BAILOUT live from TAEM
// While the automated test flight has
// the flight (flfxNoPilot: no crew to take the downmode the GO CSS / OTT message recommends) a GREEN's TAEM downmodes by the
// guidance's own probe (LD_DOWNMODE "probe", the python crew model's policy). A crew flight is unchanged ("off": the buttons).
LOCAL o6Dm0 IS LD_DOWNMODE.
IF OPS6_GR {
    IF GR["cont"] = 1 AND LD_DOWNMODE = "off" AND flfxNoPilot() {
        SET LD_DOWNMODE TO "probe".
        noteEvent("TAEM downmodes: probe (SAIL has the flight: no crew to press OTT STRT / OTT MEP)").
    }
}
GLOBAL OPS_LAND_OK IS landRun(RWY_NAME, FALSE, entryAoaCmd).
SET LD_DOWNMODE TO o6Dm0.
IF OPS6_GR {
    IF SS_ON OR GR["gpk"] { SET TG_OVERHEAD_DEFAULT TO SS_OVH0. }   // the default back (a GLOBAL outlives this program)
}
IF NOT OPS_LAND_OK { opsWarn("*** landRun short of the stop: css_dap.ks (CSS)."). }
noteEvent("landRun ended (" + OPS_LAND_OK + ").").
IF DEFINED O6_KSM_GO { SET O6_KSM_GO TO FALSE. }   // the next program loads the sources
fuiStop().                    // The FAILURES window's trigger and window end with the program
cwuiClose().                                         // The panel down with the program (ops2q's end)
progReset().   // No hook of this program outlives it (lib_progreset)
