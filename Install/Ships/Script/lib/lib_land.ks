@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_LAND.KS  --  TAEM, APPROACH AND LANDING, AND THE ROLLOUT, FLOWN
// ============================================================================
//  The flight side of the guidance: landRun(runway) flies from the TAEM interface (762 m/s, or wherever it is called)
//  to wheels stop:
//   TAEM   every TG_DTG (0.96 s): st (the runway state + the TAEM state, the air data LIVE) -> taemg_cycle -> the bank
//          (G4.9 sign -> the ship's, + = LEFT), the speedbrake (orbiter deg = hinge = 2 x each rudder panel), Nz -> the
//          pitch loop (fcs_pitch: TG_NZL_NSUB alpha updates per cycle, the trim at each finite-difference window).
//   A/L    from tg_end, every AL_DT (0.16 s): nav in the guidance frame (x + the short-field shift; h = the main gear
//          above the runway PLANE) -> alg_cycle -> the bank slewed, the speedbrake, the gear, the chute, Nz
//          -> the pitch loop (AL_NSUB updates per cycle).
//   GROUND from main-gear contact: the derotation rate (hold, then AL_DEROT_RATE at 185 KEAS; short field at once), the
//          brakes to the 1000 ft short stop (BRAKES on / off, the sliders <= 95 %), the chute cut at 60 KGS; the
//          propellant behind the CoM dumped at the contact (ldDumpStart: the CoM forward for the derotation).
//  One flight program: lib_dap.ks flies the vehicle in AUTO (the guidance's commands: the alpha, the bank, the Nz, the
//  speedbrake, the derotation: its dGd* record) or CSS (the stick); PITCH and ROLL/YAW switch AUTO <-> CSS at any time.
//  No LOCK STEERING (kOS's cooked steering does not handle the speedbrake well). The rollout is the DAP's ROLLOUT AUTO
//  on the landing runway. END stops it all.
//  Loads taemg.ks, alg.ks, fcs_pitch.ks, lib_hud.ks, lib_hudg.ks and lib_dap.ks; reads the runways in
//  hud/hud_runways.txt (written by gen_hud.py). Logs 0:/logs/land_<t>.csv (every guidance cycle) + .txt (events), and
//  the DAP's css_dap_<t>.csv (every tick) + .txt.
// ============================================================================

RUNONCEPATH("0:/lib/lib_far.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/taemg.ksm" IF O6_KSM_GO ELSE "0:/lib/taemg.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/taemg.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/alg.ksm" IF O6_KSM_GO ELSE "0:/lib/alg.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/alg.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/fcs_pitch.ksm" IF O6_KSM_GO ELSE "0:/lib/fcs_pitch.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/fcs_pitch.ks").
RUNONCEPATH("0:/lib/lib_hud.ks").
RUNONCEPATH("0:/lib/lib_hudg.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_dap.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_dap.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_dap.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_coast.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_coast.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_coast.ks").   // the coast table (the bailout hold toward the coast)
RUNONCEPATH("0:/lib/lib_logsw.ks").   // SOCK_LOG: the logs on or off (land_<t>.csv / .txt)
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
RUNONCEPATH("0:/lib/lib_cape.ks").    // the SLF where the Katniss Cape is (capeLine)
// lib_grdap's GLOBAL grdOn outlives the program that set it, its functions do not (land.ks after an aborted ops6q
// would call an undefined grdStop); a program loads lib_land once (ops6q before lib_grdap), so a grdOn found here is
// stale (KAL/S's FBW drops each axis 0.5 s after its last call).
IF DEFINED grdOn { SET grdOn TO FALSE. }

// ---------------------------------------------------------------- configuration
// kOS instructions per update (CONFIG:IPU), set at the start of landRun
GLOBAL LD_IPU IS 10000.
GLOBAL LD_CWE IS LIST(0, 0, -100).             // the C&W panel's read of TAEM: LIST(phase, EOW - EN m, UT) written once a TAEM cycle (nothing reads it back into the guidance)
IF NOT (DEFINED LD_HUD) { GLOBAL LD_HUD IS TRUE. }    // the HUD (lib_hud.ks) in the loop, <= 25 Hz real;
                                            // SET LD_HUD TO FALSE. at the terminal before the run to fly without it
IF NOT (DEFINED LD_DISP) { GLOBAL LD_DISP IS TRUE. }  // the TAEM displays (lib_taemdisp.ks); SET LD_DISP TO FALSE. first
                                            // to fly without them (VERT SIT / HORIZ SIT, drawn once per guidance cycle)
                                            // the TAEM start's bumpless pitch (below): a steering command this close to the stop is a limit cycle's sample, not a
                                            // trim (FAR: -1 -> elevons 25 and the flap 19.5 TED, alpha 14 -> 0 in 2.6 s);
                                            // then the entry / GRTLS DAP's pitch integral (lib_grdap grdI[0], its trim) is taken, or 0 without it
GLOBAL LD_GP0_SAT IS 0.95.
GLOBAL LD_FD_WIN IS 1.0.                    // s, the Nz finite-difference window in TAEM (lib_vehicle's FD_MIN_DT)
GLOBAL LD_AL_FD_WIN IS 0.48.                // s, the finite-difference window in A/L (three cycles)
GLOBAL LD_SB_GROUND_MAX IS 98.6.            // hinge on the ground: alg's AL_DSBC_WW 98.6 at WOWLON passes in
                                            //   full
GLOBAL LD_SB_CAP IS 70.                     // the airborne speedbrake cap, hinge; landRun sets the
                                            //   guidance's 65s to it at start (ldSbCap). <= 0: off, the guidance keeps its own. 70 = 35 a side: the
                                            //   open-half rudder's room 20. ABOVE MACH 1.5 THE DAP HOLDS 65 (lib_dap
                                            //   SB_SUPER_MAX: a Dutch roll at 35 a side there)
GLOBAL LD_SB_MAX IS 98.6.                   // the speedbrake maximum, hinge (the orbiter's) --
                                            //   taemg's subsonic upper limit (tgDsbMax) and S-turn (DSBLIM), A/L's cap
                                            //   (AL_SB_MAX; its 3000 ft and short-field 80 % = 78.9). The nominal and the
                                            //   supersonic setting stay at LD_SB_CAP; lib_dap RUD_HALF_LIM 49.3 a side lets
                                            //   it through below Mach 1.5, on the ground too (LD_SB_GROUND_MAX 98.6).
                                            //   -1 = off: LD_SB_CAP everywhere.
// THE C# TAEM GUIDANCE. With LD_TG_CS on and the KAL/S addon installed with its TAEM part (ADDONS:KALS:TGCYCLE), each
// TAEM pass (taemg_cycle) is flown by the addon's port of taemg.ks (coproc/Taemg.cs: python's 972 vectors to ~1e-11, as
// the kOS file): one SYNCHRONOUS call per guidance cycle, tg updated in place (the same lexicon: the logs, the pages,
// the DAP read it unchanged). The constants come from the same files kOS ran (taemg_const.ks, solq_atm_data.ks: TGSETUP
// at the TAEM start); the globals lib_land sets in flight go with each call (ldTgGlobals). Never throws: an addon
// failure (TGSETUP FALSE or a TGCYCLE error, tg then untouched) turns it off for the rest of the flight and kOS flies
// that pass and the rest (LD_TG_CS_ERR says why, the event log too).
// FALSE / no addon: kOS's taemg_cycle.
IF NOT (DEFINED LD_TG_CS) { GLOBAL LD_TG_CS IS TRUE. }   // TRUE: the C# flies TAEM
GLOBAL LD_TG_CS_ERR IS "".
// THE C# A/L GUIDANCE AND PITCH LOOP. With LD_AL_CS on and the KAL/S addon installed with its A/L part
// (ADDONS:KALS:ALSTEP ...), the per-cycle A/L and pitch-loop calls are flown by the addon's ports of alg.ks and
// fcs_pitch.ks (coproc/Alg.cs, Fcs.cs: python's 8951 vectors to ~1e-12, as the kOS files), one SYNCHRONOUS call each,
// the lexicons updated in place (ags, fc, tg: the logs, the HUD, the DAP read them unchanged):
//   A/L, every AL_DT    alg_cycle + the bank slew on fc + alg_nz_total     -> ALSTEP (ldAlStep)
//   A/L pitch loop      fcs_al_alpha (FCALALPHA), fcs_al_trim (FCALTRIM), the CSS reseed's fcs_alpha_ff (FCALPHAFF)
//   TAEM pitch loop     fcs_alpha_cmd + the bailout ceiling + fcs_alpha_slew -> FCTAEM (ldFcTaem); fcs_window_end
//                       (FCWINDOW); fcs_trim_seed (FCSEED)
// The constants come from the same files kOS ran (alg_const.ks, taemg_const.ks, solq_atm_data.ks: ALSETUP at the TAEM
// start). Never throws: an addon failure (ALSETUP FALSE, or a call's error: the lexicons then untouched) turns it off for
// the rest of the flight and kOS flies that call and the rest (LD_AL_CS_ERR says why, the event log too).
// FALSE / no addon: kOS's alg.ks and fcs_pitch.ks.
IF NOT (DEFINED LD_AL_CS) { GLOBAL LD_AL_CS IS TRUE. }   // TRUE: the C# flies A/L and the pitch loop (no harm if it fails)
GLOBAL LD_AL_CS_ERR IS "".
GLOBAL LD_SB_HOLD_S IS 5.                   // s: the speedbrake held as found this long from the TAEM start, then the
                                            //   guidance's: the interface's alpha, bank and speedbrake moves must not all
                                            //   come at once (the speedbrake after the attitude)
GLOBAL LD_VMASS IS AL_VEHICLE_MASS.         // A/L's mass, ORBITER-EQUIVALENT; set at the A/L start from SHIP:MASS (below)
// the mass, scaled (this orbiter is much lighter than the real one): the aero model is mass-specific, fitted at the
// calibration mass LD_MASS_CAL, so the vehicle at SHIP:MASS flies like the orbiter model at
// AL_VEHICLE_MASS x SHIP:MASS / LD_MASS_CAL.
GLOBAL LD_MASS_CAL IS 24200.                // kg, the aero model's calibration mass
GLOBAL LD_FF_K IS 1.                        // the A/L pitch loop's mass factor on the alpha table's Nz: LD_VMASS /
                                            //   AL_ORB_MASS in IGS 2 (and IGS 1 above AL_ORB_MASS) with AL_HEAVY_FF,
                                            //   else 1 (al_sim ff_k)
// the downmode policy, "off" by default: the CREW selects OTT STRT / OTT MEP by the DAP window's buttons (lib_dap
// dapDmShow; taemg_crew_act takes a press at the guidance's next cycle, whatever this says). landRun sets
// TG_DOWNMODE_POLICY to this; SET LD_DOWNMODE TO "probe". before the run has the guidance downmode by itself (python's
// crew model, its DOWNMODE_POLICY), the buttons on top.
IF NOT (DEFINED LD_DOWNMODE) { GLOBAL LD_DOWNMODE IS "off". }
// the OTT message (OTT STRT / OTT MEP) on the HUD and the TAEM windows' message row: shown while the guidance
// RECOMMENDS the downmode, never after it is taken: ldDmShow = lib_dap's dapDmRec, the buttons' "!" rule. The guidance
// keeps tg["dm_msg"] latched when taken (the log, the TAEM windows' event list, python's trace); an undo clears it
// (OVHD) or puts back the one before MEP (NEP).
GLOBAL LD_WOW_M IS 0.3.                     // the main / nose gear this close to the ground (radar), m ...
GLOBAL LD_WOW_S IS 0.5.                     // ... for this long, s = on the ground (lib_hud's rule)
GLOBAL LD_BRAKE_HYST IS 0.1.                // m/s2 around the brakes' deceleration target
GLOBAL LD_BRAKE_PCT IS 95.                  // % on each wheel's brake slider at most: the mains LOCK at 100
GLOBAL LD_BRAKE_FULL IS TRUE.               // the firmest braking (the stopping power):
                                            //   ROLLOUT AUTO holds BRAKES ON from the nose gear to the
                                            //   stop, every slider at LD_BRAKE_PCT; FALSE = the modulation to
                                            //   alg_brake_need (past midfield below 140 kt, the stop 1000 ft short)
GLOBAL LD_STOP_VG IS 0.3.                   // m/s: wheels stop (a landed rollout ends first: the DAP's dDone at LANDED
                                            //   and ground speed < 1 m/s)
// THE CG TARGETER AT TOUCHDOWN: the drain valves (stock FTE-1) on the parts behind the CoM dump those parts' propellant
// (the aft fuselage: the OMS LF / OX and the aft RCS mono) and move the CoM forward, so the elevons have the authority
// to hold the nose up (a CoM too far aft derotates at once). The valves drain only while the main gear's contact lies
// more than LD_CG_TGT ahead of the CoM along the body, and stop there; a vehicle already forward of it dumps nothing.
// It starts at the main gear's contact; then the mono fine trim (ldMpTick): the MonoPropellant moved between the most
// forward and the most aft mono tank (the forward RCS, the aft fuselage) toward LD_CG_TGT, both ways, to the nose gear.
// Measured: with no dump the contact sat 0.17-0.25 m ahead of the CoM light and 0.40-0.53 m heavy (the landings that
// could not pitch down were the heavy ones); a full dump left -0.27..+0.10 m and the nose came down by itself.
// SET LD_DUMP TO FALSE. before the run keeps it all aboard. A deviation: the orbiter's CG is set before entry, it
// dumps nothing and moves no propellant at landing.
IF NOT (DEFINED LD_DUMP) { GLOBAL LD_DUMP IS TRUE. }
IF NOT (DEFINED LD_CG_MP) { GLOBAL LD_CG_MP IS TRUE. }    // the mono fine trim (SET LD_CG_MP TO FALSE. keeps it still)
GLOBAL LD_DUMP_RATE IS 10.                  // % of each tank's capacity per second per valve (2 valves: a full tank in 5 s; 20 overshot the target)
GLOBAL LD_CG_TGT IS 0.25.                   // m: the main gear's contact ahead of the CoM (ldGearGeom's) the targeter leaves
GLOBAL LD_CG_DB IS 0.02.                    // m: nothing dumped, and the mono trim done, within this of the target
GLOBAL LD_MP_ITER IS 3.                     // mono transfers at most (each re-aimed from the CoM it left)
GLOBAL LD_MP_WAIT IS 6.                     // s: a transfer still running after this is stopped (200 units take 4 s)
GLOBAL LD_DUMP_LOG_S IS 6.                  // s after the start: the dump's outcome and the gear geometry to the log
GLOBAL LD_THETA_WARN_FT IS 50.              // the tail's clearance on the HUD (the 13 deg pitch
GLOBAL LD_THETA_WARN_DEG IS 1.              //   limit): PITCH flashes below this height with the pitch past
                                            //   AL_THETA_TD_MAX less this -- CSS's cue; AUTO's pitch loop holds the cap
GLOBAL LD_CSS_PSHA_CLEAR IS 200.            // deg of HAC turn to go: below it GO CSS is gone (ldCssShown)
// the crew's BAILOUT in TAEM (lib_dap's button) flies the GRTLS's bailout hold (lib_grtls phase 7, CONT BLUE's): its
// numbers, as lib_grtls's GR_* (a VM check asserts them equal; its CQG / DTG are TG_CQG / TG_DTG)
GLOBAL LD_BAIL_MACH IS 1.0.                 // the hold below this Mach (GR_BAIL_MACH; SCOM 6.7: armed under Mach 1.0) ..
GLOBAL LD_BAIL_QMIN IS 2000.0.              // Pa: .. with this q (GR_BAIL_QMIN)
GLOBAL LD_BAIL_KEAS IS 190.0.               // KEAS: the hold (GR_BAIL_KEAS; SCOM 6.7: 185 to 195 KEAS, zero roll)
GLOBAL LD_BAIL_QBG1 IS 0.1.                 // 1/s: the q-bar error gain (GR_BQG1)
GLOBAL LD_BAIL_QBG2 IS 0.0026107.           // g per Pa/s (GR_BQG2)
GLOBAL LD_BAIL_NZCDL IS 0.2.                // g/s: the Nz command's rate (GR_BAIL_NZCDL)
GLOBAL LD_BAIL_QBARDL IS 500.0.             // Pa/s: the q-bar filter's rate clamp (GR_QBARDL)
GLOBAL LD_BAIL_ALPMAX IS 20.0.              // deg: the alpha ceiling (GR_BAIL_ALPMAX)
GLOBAL LD_BAIL_END IS 300.0.                // m: the hold ends this high above the ground (GR_BAIL_END: ops6q's, over the sea)
// below the hold the ditch's flare (lib_grtls GR_DITCH's law and numbers; the crew bails out, the orbiter ditches as
// softly as it can): once the height above the water (ALT:RADAR) is at most LD_DITCH_TAU x the sink, the Nz for hdot
// -MAX(LD_DITCH_HDTD, h / LD_DITCH_TAU) in the pitch loop, alpha <= LD_DITCH_ALPMAX, wings level (the hold's); the loop
// ends in the water. LD_DITCH FALSE: no flare.
GLOBAL LD_DITCH IS TRUE.
GLOBAL LD_DITCH_TAU IS 3.0.                 // s (GR_DITCH_TAU)
GLOBAL LD_DITCH_HDTD IS 0.6.                // m/s (GR_DITCH_HDTD)
GLOBAL LD_DITCH_K IS 1.5.                   // 1/s (GR_DITCH_K)
GLOBAL LD_DITCH_ALPMAX IS 25.0.             // deg (GR_DITCH_ALPMAX)
// the coast steering in the bailout hold: it banks toward the line CST_DOFF off the nearest coast as the GRTLS BLUE's
// (lib_coast; GR_BLUE_*'s numbers): the bank TG_GPHI x the heading error, <= LD_COAST_PHILM, none at or below the flight
// path LD_COAST_GAM4 (full from GAM4 + GAMW up) or under the q LD_COAST_QB; wings level off the table and once ditching
GLOBAL LD_COAST IS TRUE.                    // FALSE = wings level
GLOBAL LD_COAST_PHILM IS 45.0.              // deg (GR_BLUE_PHILM)
GLOBAL LD_COAST_GAM4 IS -30.0.              // deg (GR_BLUE_GAM4)
GLOBAL LD_COAST_GAMW IS 10.0.               // deg (GR_BLUE_GAMW)
GLOBAL LD_COAST_QB IS 3000.0.               // Pa (GR_BLUE_QB)

// ---------------------------------------------------------------- state (every global a GUI callback touches exists here)
GLOBAL ldRwy IS LEXICON().
GLOBAL ldAlpha IS 0.                        // deg, the alpha command (the pitch loop's, to the DAP)
GLOBAL ldAcHist IS LIST().                  // TAEM's last TG_NZL_NSUB sub-step alpha commands (their mean to the DAP)
GLOBAL ldBank IS 0.                         // deg, the SHIP's bank command (+ = LEFT)
GLOBAL ldPhase IS "INIT".
GLOBAL ldMsg IS "".
GLOBAL ldWhy IS "".                         // the last tg["dm_why"] logged (each downmode taken or undone)
GLOBAL ldDmShow IS "".                     // the OTT message the displays show this cycle: the downmodes recommended (dapDmRec)
GLOBAL ldRud IS LIST().
GLOBAL ldGearM IS LIST().
GLOBAL ldGearN IS LIST().
GLOBAL ldCgOn IS FALSE.                    // the targeter's valves are draining
GLOBAL ldMpF IS LIST().                     // the most forward mono tank (ldFindParts)
GLOBAL ldMpA IS LIST().                     // the most aft mono tank
GLOBAL ldMpSt IS 0.                         // the mono trim: 0 idle / done, 1 to aim, 2 transferring
GLOBAL ldMpN IS 0.                          // transfers made
GLOBAL ldMpT IS -1.                         // the running transfer's start
GLOBAL ldMpS IS 0.                          // the running transfer's sign (+1 aft -> forward, -1 forward -> aft)
GLOBAL ldMpX IS LEXICON().                  // the running transfer (kOS TRANSFER), under the key "x"
GLOBAL ldDrain IS LIST().                   // the drain valves whose parent part sits behind the CoM (ldFindParts; ldDumpStart)
GLOBAL ldBndM IS LIST().
GLOBAL ldBndN IS LIST().
GLOBAL ldBndT IS -1.
GLOBAL ldPartsN IS -1.                       // SHIP:PARTS:LENGTH when ldFindParts last ran (a lost part = the lists are old)
GLOBAL ldGearLast IS LIST(1E9, 1E9, 1E9).   // ldGearH's last reading (ldLive false: it is returned)
GLOBAL ldFdPv IS V(0, 0, 0).
GLOBAL ldFdPb IS V(0, 0, 0).                // a body-fixed point (LATLNG(0,0)) from the body's centre at the previous sample (ldFd)
GLOBAL ldFdK IS 0.                          // the raw frame's turn over the last window as a fraction of the body's (1: it turns with it)
GLOBAL ldFdPt IS -1.
GLOBAL ldFdLift IS 0.
GLOBAL ldFdDrag IS 0.
GLOBAL ldFdNew IS FALSE.
GLOBAL ldCsv IS "".
GLOBAL ldTxt IS "".
GLOBAL ldT0 IS 0.
GLOBAL ldLbl IS 0.                          // landRun's status line, in the DAP's window
GLOBAL ldHudBd IS LIST(0, 0, -1, 1).        // the HUD diamond's ramps (ldRamp: from, to, when, over): the bank demand ...
GLOBAL ldHudNz IS LIST(1, 1, -1, 1).        // ... and the Nz command

// ---- the C# TAEM guidance (the block above LD_TG_CS)
// at the TAEM start: the capsule's reaction wheels off for the rest of the flight (the orbiter flies on its surfaces and
// jets; no input the vessel takes as the stick can run the battery down through them)
FUNCTION ldRwOff {
    IF NOT ADDONS:HASSUFFIX("KALS") { ldSay("reaction wheels: left on (no KAL/S addon)"). RETURN. }
    IF NOT ADDONS:KALS:AVAILABLE { ldSay("reaction wheels: left on (the KAL/S addon is not available)"). RETURN. }
    IF NOT ADDONS:KALS:HASSUFFIX("RWHEELS") { ldSay("reaction wheels: left on (an older KalsCoproc.dll)"). RETURN. }
    ldSay("reaction wheels off: " + ADDONS:KALS:RWHEELS(FALSE)).
}

FUNCTION ldTgCsSetup {                      // at the TAEM start: the addon's constants, or both switches off
    IF NOT LD_TG_CS { RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("TGCYCLE") { SET why TO "the KAL/S addon has no TAEM (an older KalsCoproc.dll)". }
    ELSE IF NOT ADDONS:KALS:TGSETUP(OPEN("0:/lib/taemg_const.ks"):READALL:STRING,
                                    OPEN("0:/lib/solq_atm_data.ks"):READALL:STRING) {
        SET why TO "TGSETUP: " + ADDONS:KALS:TGERROR.
    }
    IF why = "" {
        ldSay("TAEM guidance: the C# coprocessor").
        RETURN.
    }
    SET LD_TG_CS_ERR TO why.
    SET LD_TG_CS TO FALSE.
    ldSay("TAEM guidance: kOS (the C# one off: " + why + ")").
}

FUNCTION ldTgGlobals {                      // the globals taemg.ks reads that change in flight (TaemgKos.Cycle's order)
    RETURN LIST(TG_X_AIM, TG_XALI_X, TG_R2MAX, tgDsbMax, TG_DSBSUP, TG_DSBLIM, TG_DSBNOM, TG_DOWNMODE_POLICY).
}

FUNCTION ldTgCycle {                        // one TAEM pass: the addon's, or kOS's taemg_cycle
    PARAMETER tg, st.
    IF LD_TG_CS {
        LOCAL cse IS ADDONS:KALS:TGCYCLE(tg, st, ldTgGlobals()).
        IF cse = "" { RETURN. }
        SET LD_TG_CS_ERR TO cse.              // tg untouched: kOS flies this pass and the rest
        SET LD_TG_CS TO FALSE.
        ldSay("C# TAEM guidance off (kOS flies on): " + cse).
    }
    taemg_cycle(tg, st).
}

// ---- the C# A/L guidance and pitch loop (the block above LD_AL_CS)
FUNCTION ldAlCsSetup {                      // at the TAEM start: the addon's constants, or both switches off
    IF NOT LD_AL_CS { RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("ALSTEP") { SET why TO "the KAL/S addon has no A/L (an older KalsCoproc.dll)". }
    ELSE IF NOT ADDONS:KALS:ALSETUP(OPEN("0:/lib/alg_const.ks"):READALL:STRING, OPEN("0:/lib/taemg_const.ks"):READALL:STRING,
                                    OPEN("0:/lib/solq_atm_data.ks"):READALL:STRING) {
        SET why TO "ALSETUP: " + ADDONS:KALS:ALERROR.
    }
    IF why = "" {
        ldSay("A/L guidance and pitch loop: the C# coprocessor").
        RETURN.
    }
    ldAlCsOff("", why).
}

FUNCTION ldAlCsOff {                        // an addon failure: both switches off for the rest of the flight, kOS flies on
    PARAMETER at_, why.
    SET LD_AL_CS_ERR TO why.
    SET LD_AL_CS TO FALSE.
    ldSay("A/L guidance and pitch loop: kOS (the C# one off" + at_ + ": " + why + ")").
}

FUNCTION ldAlStepKos {                      // kOS's A/L cycle: alg_cycle, the bank slew (G4.9 sign), the Nz -> nzt
    PARAMETER ags, nav, fc.
    alg_cycle(ags, nav).
    LOCAL rlm IS taemg_roll_lim(nav["mach"]).                                   // CSS's roll rate
    LOCAL sl IS taemg_bank_slew(fc["bank"], ags["phic_al"], fc["bank_rate"], AL_DT, rlm[0], rlm[1]).
    SET fc["bank"] TO sl[0].
    SET fc["bank_rate"] TO sl[1].
    RETURN alg_nz_total(ags["nzc"], nav["gamma"], fc["bank"]).
}

FUNCTION ldAlStep {                         // one A/L cycle -> nzt (ALSTEP when LD_AL_CS)
    PARAMETER ags, nav, fc.
    IF LD_AL_CS {
        LOCAL xcs IS ADDONS:KALS:ALSTEP(ags, nav, fc).
        IF xcs > -99990 { RETURN xcs. }
        ldAlCsOff(" at ALSTEP", ADDONS:KALS:ALERROR).   // ags, fc untouched: kOS flies this cycle and the rest
    }
    RETURN ldAlStepKos(ags, nav, fc).
}

FUNCTION ldFcTaemKos {                      // kOS's TAEM pitch update -> the alpha command (the slewed one: tg["alpha_rl"])
    PARAMETER tg, st, dts, aceil.           // aceil: the bailout's alpha ceiling (1E9: none)
    LOCAL ac IS fcs_alpha_cmd(tg, st).
    IF aceil < 1E8 { SET ac TO MIN(ac, aceil). }
    fcs_alpha_slew(tg, ac, dts, taemg_alpha_rate(st["mach"])).     // CSS's pitch rate
    RETURN ac.
}

FUNCTION ldFcTaem {                         // TAEM's pitch update (FCTAEM when LD_AL_CS)
    PARAMETER tg, st, dts, aceil.
    IF LD_AL_CS {
        LOCAL xcs IS ADDONS:KALS:FCTAEM(tg, st, dts, aceil).
        IF xcs > -99990 { RETURN xcs. }
        ldAlCsOff(" at FCTAEM", ADDONS:KALS:ALERROR).
    }
    RETURN ldFcTaemKos(tg, st, dts, aceil).
}

FUNCTION ldFcWindow {                       // TAEM's FD window end: fcs_window_end, then the bind cleared (FCWINDOW)
    PARAMETER tg, nzm, qb.
    IF LD_AL_CS {
        LOCAL scs IS ADDONS:KALS:FCWINDOW(tg, nzm, qb).
        IF scs <> "" {
            ldAlCsOff(" at FCWINDOW", scs).
            fcs_window_end(tg, nzm, qb).
        }
    } ELSE { fcs_window_end(tg, nzm, qb). }
    SET tg["alpha_rl_bind"] TO 0.           // cleared at each window's end: the next window gathers its own
}

FUNCTION ldFcSeed {                         // fcs_trim_seed (FCSEED)
    PARAMETER tg, a_ent, nz0, qb, mach.
    IF LD_AL_CS {
        LOCAL scs IS ADDONS:KALS:FCSEED(tg, a_ent, nz0, qb, mach).
        IF scs = "" { RETURN. }
        ldAlCsOff(" at FCSEED", scs).
    }
    fcs_trim_seed(tg, a_ent, nz0, qb, mach).
}

FUNCTION ldFcAlAlpha {                      // A/L's pitch update -> the alpha (FCALALPHA)
    PARAMETER fc, nzt, qb, mach, dts, amx.
    IF LD_AL_CS {
        LOCAL xcs IS ADDONS:KALS:FCALALPHA(fc, nzt, qb, mach, dts, amx).
        IF xcs > -99990 { RETURN xcs. }
        ldAlCsOff(" at FCALALPHA", ADDONS:KALS:ALERROR).
    }
    RETURN fcs_al_alpha(fc, nzt, qb, mach, dts, taemg_alpha_rate(mach), amx).
}

FUNCTION ldFcAlTrim {                       // A/L's FD window end: fcs_al_trim, then the bind cleared (FCALTRIM)
    PARAMETER fc, nzc, nzm, qb, dt_.
    IF LD_AL_CS {
        LOCAL scs IS ADDONS:KALS:FCALTRIM(fc, nzc, nzm, qb, dt_).
        IF scs <> "" {
            ldAlCsOff(" at FCALTRIM", scs).
            fcs_al_trim(fc, nzc, nzm, qb, dt_).
        }
    } ELSE { fcs_al_trim(fc, nzc, nzm, qb, dt_). }
    SET fc["rl_bind"] TO 0.                 // cleared at each window's end: the next window gathers its own
}

FUNCTION ldFcAlphaFf {                      // fcs_alpha_ff(nz, qbar, Mach)[0] (FCALPHAFF)
    PARAMETER nz, qb, mach.
    IF LD_AL_CS {
        LOCAL xcs IS ADDONS:KALS:FCALPHAFF(nz, qb, mach).
        IF xcs > -99990 { RETURN xcs. }
        ldAlCsOff(" at FCALPHAFF", ADDONS:KALS:ALERROR).
    }
    RETURN fcs_alpha_ff(nz, qb, mach)[0].
}
// ---- the C# A/L end

FUNCTION ldSay {
    PARAMETER s.
    LOCAL line IS "t " + ROUND(TIME:SECONDS - ldT0, 1) + ": " + s.
    // the console stays blank in flight: the log has every line; the console only before the log exists
    IF ldTxt = "" { kmSay(line, "I"). } ELSE IF SOCK_LOG { LOG line TO ldTxt. }   // the logs off (lib_logsw): silent in flight
}

// ---------------------------------------------------------------- the runway (hud/hud_runways.txt)
FUNCTION ldLoadRunway {                     // -> LEXICON(name, lat, lon, hdg, len, elev, far_elev, slope), or empty
    PARAMETER nm.
    LOCAL f IS "0:/hud/hud_runways.txt".
    IF NOT EXISTS(f) { RETURN LEXICON(). }
    FOR l0 IN OPEN(f):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS capeLine(l0:REPLACE(CHAR(13), "")).     // the Cape's SLF rows
        IF lin:STARTSWITH("R ") {
            LOCAL p IS lin:SPLIT(" ").
            IF p:LENGTH >= 15 AND p[2] = nm {        // 15 columns, as lib_hud's hdLoadRunways reads them
                LOCAL elev IS p[8]:TONUMBER(0).
                LOCAL slope IS p[9]:TONUMBER(0).
                LOCAL rlen IS p[6]:TONUMBER(0).
                RETURN LEXICON("name", nm, "lat", p[3]:TONUMBER(0), "lon", p[4]:TONUMBER(0), "hdg", p[5]:TONUMBER(0),
                               "len", rlen, "elev", elev, "far_elev", elev + slope * rlen, "slope", slope,
                               "surveyed", elev > -9999, "x_ogs", p[12]:TONUMBER(-2286)).
            }
        }
    }
    RETURN LEXICON().
}

FUNCTION ldOtherEnd {                       // -> runway nm's other end (its site's other R line), "" if none
    PARAMETER nm.
    LOCAL f IS "0:/hud/hud_runways.txt".
    IF NOT EXISTS(f) { RETURN "". }
    LOCAL ends IS LIST().
    LOCAL site IS "".
    FOR l0 IN OPEN(f):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS capeLine(l0:REPLACE(CHAR(13), "")).     // the Cape's SLF rows
        IF lin:STARTSWITH("R ") {
            LOCAL p IS lin:SPLIT(" ").
            IF p:LENGTH >= 15 {
                ends:ADD(LIST(p[1], p[2])).
                IF p[2] = nm { SET site TO p[1]. }
            }
        }
    }
    IF site = "" { RETURN "". }
    FOR oe IN ends {
        IF oe[0] = site AND oe[1] <> nm {
            LOCAL rw IS ldLoadRunway(oe[1]).
            IF rw:LENGTH > 0 AND rw["surveyed"] { RETURN oe[1]. }
        }
    }
    RETURN "".
}

// A SITE'S DEFAULT END BY THE HAC TURN (the deorbit planner's runway box rule, deorbit_plan.ks DP_BOX_TURN): for an
// approach on the course inbound (deg, the track's bearing at the site) an end's turn is 360 - |inbound - its landing
// heading|; the two ends' turns sum to 540, so one is under 270: the end OPPOSITE the one nearer the approach (the lower
// overhead HAC turn). -> LIST(the end taken, its turn, the other's turn); nm itself when it has no surveyed other end
// (its turn alone); a tie keeps nm.
FUNCTION ldLowTurnEnd {
    PARAMETER nm, inbound.
    LOCAL rw0 IS ldLoadRunway(nm).
    IF rw0:LENGTH = 0 { RETURN LIST(nm, 0, 0). }
    LOCAL t0 IS 360 - ABS(MOD(inbound - rw0["hdg"] + 540, 360) - 180).
    LOCAL ot IS ldOtherEnd(nm).
    IF ot = "" { RETURN LIST(nm, t0, t0). }
    LOCAL rw1 IS ldLoadRunway(ot).
    LOCAL t1 IS 360 - ABS(MOD(inbound - rw1["hdg"] + 540, 360) - 180).
    IF t1 < t0 { RETURN LIST(ot, t1, t0). }
    RETURN LIST(nm, t0, t1).
}

// THE CREW'S RUNWAY SWITCH (the DAP window's SW RWY): the landing runway becomes its other end -- the frame (ldState),
// TAEM's aim, the HUD's runway, the rollout's centreline, HORIZ SIT's zoom (a new frame: its latch restarts) and the
// window's title; A/L reads ldRwy at its start. The guidance's part: taemg_rwy_switch (the caller).
FUNCTION ldAimLaw {                         // the short-field aim shift (m) TAEM takes for ldRwy: A/L's slope law below
    IF ldRwy:LENGTH = 0 { RETURN 0.0. }     //   AL_SF_LEN_MAX (alg_aim_shift's; the 1249 m runways), else 0; the named
    IF ldRwy["len"] < AL_SF_LEN_MAX { RETURN alg_sf_law(ldRwy["slope"])[0]. }   //   ones (VBG) keep TAEM's own
    RETURN 0.0.
}

FUNCTION ldSwitchRunway {
    PARAMETER nm.
    LOCAL old IS ldRwy["name"].
    SET ldRwy TO ldLoadRunway(nm).
    taemg_set_aim(nm, ldAimLaw()).
    SET dRwyAlt TO old.
    IF LD_HUD AND dHud {
        FROM { LOCAL k IS 0. } UNTIL k >= hdRwys:LENGTH STEP { SET k TO k + 1. } DO {
            IF hdRwys[k][1] = nm { hdSelectRunway(k). }
        }
    }
    SET dGdRwyThr TO LATLNG(ldRwy["lat"], ldRwy["lon"]).
    SET dGdRwyFar TO hdDest(dGdRwyThr, ldRwy["hdg"], ldRwy["len"]).
    IF DEFINED tdZoomLatch { SET tdZoomLatch TO 1. }
    LOCAL w IS dGui:WIDGETS.                // uiBox: the title, then the subtitle
    IF w:LENGTH > 1 { IF w[1]:ISTYPE("Label") { SET w[1]:TEXT TO "TAEM, A/L, rollout -- " + nm. } }
}

// THE CREW'S SITE SWITCH (another airport from the GRTLS or TAEM). VERT SIT's second row: < SITE > browses the sites of
// hud_runways.txt in LD_SITE_ORD's order (each its surveyed end whose landing heading is nearest the bearing from the vehicle:
// the approach from the vehicle's side; the current site keeps its runway), the middle button takes the one shown when
// SW RWY could (taemg_rwy_rej: NEP, the acquisition phase or the S-turn): SW RWY's path (ldSwitchRunway +
// taemg_rwy_switch, its own switch state cleared), SW RWY then offers the new site's other end.
// A deviation: the real crew selects a landing site by an item entry on SPEC 50 HORIZ SIT.
GLOBAL LD_SITE_ORD IS LIST("VBG", "EAFB", "SLF", "Myrtle_Beach", "Cherry_Point", "Dover", "LaGuardia", "Halifax",
    "Gander", "Shannon", "Zaragoza", "Moron", "Bermuda").   // the browse order; a site not named here follows, nearest first
GLOBAL ldSiteSw IS FALSE.                   // a site switch was taken (ops6q: the plan's aim no longer applies)
GLOBAL ldSiteL IS LIST().                   // the browsed sites, LIST(end, site, km), in LD_SITE_ORD's order (ldSites)
GLOBAL ldSiteK IS 0.                        // the one shown
GLOBAL ldSiteCur IS "".                     // the current runway's site (ldSites)

FUNCTION ldSites {                          // -> every site, LIST(end, site, km), in LD_SITE_ORD's order
    LOCAL f IS "0:/hud/hud_runways.txt".
    IF NOT EXISTS(f) { RETURN LIST(). }
    LOCAL gp IS SHIP:GEOPOSITION.
    LOCAL cur IS CHOOSE ldRwy["name"] IF ldRwy:HASKEY("name") ELSE "".
    LOCAL best IS LEXICON().                // site -> LIST(end, km, the heading's error)
    FOR l0 IN OPEN(f):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS capeLine(l0:REPLACE(CHAR(13), "")).
        IF lin:STARTSWITH("R ") {
            LOCAL p IS lin:SPLIT(" ").
            IF p:LENGTH >= 15 AND p[8]:TONUMBER(0) > -9999 {        // surveyed (ldLoadRunway's test)
                LOCAL gc IS ldGreatCircle(gp:LAT, gp:LNG, p[3]:TONUMBER(0), p[4]:TONUMBER(0)).
                LOCAL he IS ABS(MOD(p[5]:TONUMBER(0) - gc[1] + 540, 360) - 180).
                IF p[2] = cur { SET ldSiteCur TO p[1]. SET he TO -1. }   // the current site keeps its runway
                IF NOT best:HASKEY(p[1]) { SET best[p[1]] TO LIST(p[2], gc[0] / 1000, he). }
                ELSE IF he < best[p[1]][2] { SET best[p[1]] TO LIST(p[2], gc[0] / 1000, he). }
            }
        }
    }
    LOCAL out IS LIST().
    FOR k IN LD_SITE_ORD { IF best:HASKEY(k) { out:ADD(LIST(best[k][0], k, best[k][1])). } }
    LOCAL srt IS LIST().                    // the sites LD_SITE_ORD does not name, nearest first
    FOR k IN best:KEYS {
        IF NOT LD_SITE_ORD:CONTAINS(k) {
            LOCAL it IS LIST(best[k][0], k, best[k][1]).
            LOCAL i IS 0.
            UNTIL i >= srt:LENGTH { IF srt[i][2] > it[2] { BREAK. } SET i TO i + 1. }
            srt:INSERT(i, it).
        }
    }
    FOR it IN srt { out:ADD(it). }
    RETURN out.
}

FUNCTION ldSiteTick {                       // each pass: the browse presses (lib_dap's dSiteStep) and the label
    IF dSiteStep = 0 OR dBtnSite:ISTYPE("Scalar") { RETURN. }
    LOCAL was IS CHOOSE ldSiteL[ldSiteK][1] IF ldSiteK < ldSiteL:LENGTH ELSE "".   // the site shown
    SET ldSiteL TO ldSites().
    LOCAL n IS ldSiteL:LENGTH.
    IF n = 0 { SET dSiteStep TO 0. SET dSiteNm TO "". RETURN. }
    LOCAL want IS CHOOSE ldSiteCur IF dSiteStep = 99 OR was = "" ELSE was.   // a refresh: the current site
    LOCAL k0 IS 0.
    FROM { LOCAL k IS 0. } UNTIL k >= n STEP { SET k TO k + 1. } DO { IF ldSiteL[k][1] = want { SET k0 TO k. } }
    SET ldSiteK TO MOD(k0 + (CHOOSE 0 IF dSiteStep = 99 ELSE dSiteStep) + n, n).
    SET dSiteStep TO 0.
    LOCAL it IS ldSiteL[ldSiteK].
    IF it[1] = ldSiteCur {
        SET dSiteNm TO "".
        SET dBtnSite:TEXT TO "SITE " + ldRwy["name"].
    } ELSE {
        SET dSiteNm TO it[0].
        SET dBtnSite:TEXT TO "TO " + it[0] + " " + ROUND(it[2] / 1.852) + " NM".
    }
    SET dBtnSite:ENABLED TO FALSE.          // dapDmShow opens it at the next guidance cycle
}

FUNCTION ldSiteGo {                         // the crew's site switch (dDmReq "site") -> LIST(taken, the line)
    PARAMETER tg.
    LOCAL nw IS dSiteReq.
    SET dDmReq TO "".
    SET dSiteStep TO 99.                    // the label back from "..."
    LOCAL rej IS taemg_rwy_rej(tg, nw <> "").
    IF rej = "" { IF ldLoadRunway(nw):LENGTH = 0 { SET rej TO "crew-site:no runway " + nw. } }
    IF rej <> "" {
        SET tg["dm_rej"] TO rej.
        RETURN LIST(FALSE, "SITE " + nw + ": refused (" + rej + ")").
    }
    LOCAL old IS ldRwy["name"].
    ldSwitchRunway(nw).
    SET dRwyAlt TO ldOtherEnd(nw).          // SW RWY now offers the new site's other end
    LOCAL st IS ldState().                  // the new runway's frame, before any guidance function
    taemg_rwy_switch(tg, st, nw).
    SET tg["rwy_sw"] TO FALSE.              // SW RWY's own switch not taken at the new site
    SET tg["dm_why"] TO tg["dm_why"]:REPLACE("crew:rwy", "crew:site").
    SET ldSiteSw TO TRUE.
    RETURN LIST(TRUE, "SITE SWITCH " + old + " -> " + nw + ": " + tg["dm_why"] + ", HAC ysgn " + tg["ysgn"] + ", x "
                + ROUND(st["x"]) + " y " + ROUND(st["y"]) + " m in the new frame").
}

FUNCTION ldGreatCircle {                    // -> LIST(dist m, bearing deg 0-360)
    PARAMETER lat1, lon1, lat2, lon2.
    LOCAL dl IS lon2 - lon1.
    LOCAL a IS SIN((lat2 - lat1) / 2.0) ^ 2 + COS(lat1) * COS(lat2) * SIN(dl / 2.0) ^ 2.
    LOCAL dist IS 2.0 * SHIP:BODY:RADIUS * ARCSIN(MIN(1.0, SQRT(a))) * TG_D2R.
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(lat2), COS(lat1) * SIN(lat2) - SIN(lat1) * COS(lat2) * COS(dl)).
    IF brg < 0 { SET brg TO brg + 360.0. }
    RETURN LIST(dist, brg).
}

FUNCTION ldMach {                           // css_dap machNow: the LIVE air data
    LOCAL ps IS SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE) * CONSTANT:ATMTOKPA * 1000.
    IF ps < 0.0001 { RETURN 0. }
    LOCAL qd IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000.
    RETURN SQRT(MAX(2 * qd / (1.4 * ps), 0)).
}

FUNCTION ldState {                          // the runway state + the TAEM state, the air data live
    LOCAL geo IS SHIP:GEOPOSITION.
    LOCAL gc IS ldGreatCircle(ldRwy["lat"], ldRwy["lon"], geo:LAT, geo:LNG).
    LOCAL rel IS taemg_norm180(gc[1] - ldRwy["hdg"]).
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL hdot IS VDOT(vs, upv).
    LOCAL vhv IS vs - upv * hdot.
    LOCAL vh IS vhv:MAG.
    LOCAL nv IS SHIP:NORTH:VECTOR.
    LOCAL east IS VCRS(upv, nv).          // kOS is left-handed: VCRS(UP, NORTH) = EAST
    LOCAL hdg IS ARCTAN2(VDOT(vhv, east), VDOT(vhv, nv)).
    IF hdg < 0 { SET hdg TO hdg + 360.0. }
    LOCAL psd IS taemg_norm180(hdg - ldRwy["hdg"]).
    LOCAL surfv IS vs:MAG.
    LOCAL qbar IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000.
    LOCAL gamu IS 0.
    IF surfv > 1.0 { SET gamu TO ARCSIN(MAX(-1.0, MIN(1.0, hdot / surfv))). }
    RETURN LEXICON("x", gc[0] * COS(rel), "y", gc[0] * SIN(rel), "h", SHIP:ALTITUDE - ldRwy["elev"],
                   "xdot", vh * COS(psd), "ydot", vh * SIN(psd), "hdot", hdot, "psd", psd, "vh", vh,
                   "surfv", surfv, "mach", ldMach(), "qbar", qbar,
                   "rho", CHOOSE 2 * qbar / (surfv * surfv) IF surfv > 1 ELSE 0,
                   "gam", -gamu, "costh", COS(gamu), "acc_drag", ldFdDrag).
}

// ---------------------------------------------------------------- the finite-difference aero (lib_vehicle fdSample)
FUNCTION ldFd {                             // sets ldFdLift / ldFdDrag (m/s2) at the end of each window
    PARAMETER win.
    LOCAL now IS TIME:SECONDS.
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    SET ldFdNew TO FALSE.
    IF ldFdPt < 0 {
        SET ldFdPv TO vv. SET ldFdPb TO LATLNG(0, 0):ALTITUDEPOSITION(0) - SHIP:BODY:POSITION. SET ldFdPt TO now. RETURN.
    }
    LOCAL dt IS now - ldFdPt.
    IF dt < win { RETURN. }
    LOCAL bp IS LATLNG(0, 0):ALTITUDEPOSITION(0) - SHIP:BODY:POSITION.      // read at the window's end only: the tick's budget
    // the raw frame turns with the body below KSP's inverse-rotation altitude, so the previous sample sits in axes that
    // have turned by w dt; differenced as it is, the window would carry -w x v_orb. The turn is measured on the
    // body (lib_vehicle's fdSample method): a body-fixed point holds still in a frame that turns with the body and moves
    // by w x b dt in one that does not, so ldFdK = 1 - (its move . w x b) / (dt |w x b|^2), and the previous velocity
    // comes into the current axes as pv - ldFdK dt (w x pv) (first order in w dt; VCRS(w, X) is
    // eprOmegaCross's w x X).
    LOCAL wv IS SHIP:BODY:ANGULARVEL:NORMALIZED * (2 * CONSTANT:PI / SHIP:BODY:ROTATIONPERIOD).
    LOCAL wb IS VCRS(wv, ldFdPb).
    SET ldFdK TO 1 - VDOT(bp - ldFdPb, wb) / (dt * MAX(wb:SQRMAGNITUDE, 1e-9)).
    LOCAL pv IS ldFdPv - dt * MIN(MAX(ldFdK, 0), 1) * VCRS(wv, ldFdPv).
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL gv IS -rv:NORMALIZED * (SHIP:BODY:MU / rv:SQRMAGNITUDE).
    LOCAL aero IS (vv - pv) / dt - gv.
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    IF vs:MAG > 1 {
        LOCAL vn IS vs:NORMALIZED.
        SET ldFdDrag TO -VDOT(aero, vn).
        SET ldFdLift TO (aero - vn * VDOT(aero, vn)):MAG.
        SET ldFdNew TO TRUE.
    }
    SET ldFdPv TO vv.
    SET ldFdPb TO bp.
    SET ldFdPt TO now.
}

// ---------------------------------------------------------------- the actuators
FUNCTION ldLive {                          // TRUE when the landing may read its parts now
    IF TIME:SECONDS < VES_HOLD { RETURN FALSE. }  // A splash or a HARD touchdown: the vessel may be rebuilt, no part is read until the hold ends
    IF NOT surfListOld("land") {
        // A part lost without a splash (a gear leg exploded after a touchdown and the vessel was rebuilt: b:BOTTOMALT
        // on a stale part): the lists are found again from SHIP when the part count changed
        liveRefresh().
        IF ldPartsN >= 0 AND LIVE_N <> ldPartsN { ldFindParts(TRUE). }
        RETURN TRUE.
    }
    IF TIME:SECONDS < VES_HOLD { RETURN FALSE. }  // a splashdown's rebuild: the old parts are not read until the hold ends
    ldFindParts(TRUE).                     // then found again once, from SHIP
    RETURN TRUE.
}

FUNCTION ldFindParts {
    PARAMETER again IS FALSE.             // TRUE = a re-find after a splashdown's rebuild (ldLive): the dump and the trim go on
    surfListMark("land").
    SET ldBndT TO -1.                     // the gear's bounds are read again (ldGearH)
    ldBndM:CLEAR(). ldBndN:CLEAR().       // never keep bounds of parts that are gone
    liveRefresh().
    SET ldPartsN TO LIVE_N.
    ldRud:CLEAR(). ldGearM:CLEAR(). ldGearN:CLEAR(). ldDrain:CLEAR().
    FOR m IN SHIP:MODULESNAMED(SURF_MN) {
        IF m:PART:NAME:TOLOWER:CONTAINS("rudder") { ldRud:ADD(modReg(m, ldRud:LENGTH)). }
    }
    ldMpF:CLEAR(). ldMpA:CLEAR().
    SET ldMpSt TO 0.
    IF NOT again { SET ldCgOn TO FALSE. }   // nothing of the targeter left from an earlier run (a re-find keeps it)
    LOCAL fpFw IS SHIP:FACING:FOREVECTOR.
    FOR pt IN SHIP:PARTS {
        LOCAL nm IS pt:NAME:TOLOWER.
        IF nm:CONTAINS("maingear") { ldGearM:ADD(pt). } ELSE IF nm:CONTAINS("nosegear") { ldGearN:ADD(pt). }
        IF ldMpCap(pt) > 0 {        // the mono tanks at the ends: the forward one ahead of the CoM, the aft behind
            LOCAL fpMx IS VDOT(pt:POSITION, fpFw).
            IF fpMx > 0 { IF ldMpF:LENGTH = 0 { ldMpF:ADD(pt). } ELSE IF fpMx > VDOT(ldMpF[0]:POSITION, fpFw) { SET ldMpF[0] TO pt. } }
            IF fpMx < 0 { IF ldMpA:LENGTH = 0 { ldMpA:ADD(pt). } ELSE IF fpMx < VDOT(ldMpA[0]:POSITION, fpFw) { SET ldMpA[0] TO pt. } }
        }
    }
    // the drain valves (ModuleResourceDrain) on a part behind the CoM (kOS's origin): in Part mode each drains its parent
    FOR m IN SHIP:MODULESNAMED("ModuleResourceDrain") {
        IF m:PART:HASPARENT {
            IF VDOT(m:PART:PARENT:POSITION, SHIP:FACING:FOREVECTOR) < 0 { ldDrain:ADD(modReg(m)). }
        }
    }
    // the brake sliders: BRAKES ON applies each wheel's slider, and at 100 % the mains lock -- so no
    // slider above LD_BRAKE_PCT (css_dap's method: the ModuleWheelBrakes field whose name holds "brake"; step 5 %)
    FOR m IN SHIP:MODULESNAMED("ModuleWheelBrakes") {
        LOCAL fld IS "".
        FOR f IN m:ALLFIELDNAMES { IF fld = "" AND f:TOLOWER:CONTAINS("brake") { SET fld TO f. } }
        IF fld <> "" {
            IF m:GETFIELD(fld) > LD_BRAKE_PCT {
                m:SETFIELD(fld, LD_BRAKE_PCT).
                ldSay("brake slider " + m:PART:TITLE + ": capped at " + LD_BRAKE_PCT + " %").
            }
        }
    }
}



FUNCTION ldGearH {                          // -> LIST(main gear above the threshold elevation m, main radar m, nose radar m)
    IF NOT ldLive() { RETURN ldGearLast. }   // The hold of a splashdown: the last reading
    IF TIME:SECONDS - ldBndT > 2 OR ldBndT < 0 {
        ldBndM:CLEAR(). ldBndN:CLEAR().
        FOR pt IN ldGearM { ldBndM:ADD(pt:BOUNDS). }
        FOR pt IN ldGearN { ldBndN:ADD(pt:BOUNDS). }
        SET ldBndT TO TIME:SECONDS.
    }
    LOCAL hm IS 1e9. LOCAL rm IS 1e9. LOCAL rn IS 1e9.
    FOR b IN ldBndM { SET hm TO MIN(hm, b:BOTTOMALT). SET rm TO MIN(rm, b:BOTTOMALTRADAR). }
    FOR b IN ldBndN { SET rn TO MIN(rn, b:BOTTOMALTRADAR). }
    IF hm > 1e8 { SET hm TO SHIP:ALTITUDE. SET rm TO ALT:RADAR. }
    SET ldGearLast TO LIST(hm - ldRwy["elev"], rm, rn).
    RETURN ldGearLast.
}

FUNCTION ldChute {                          // the drag chute (stock ModuleParachute): "deploy chute" / "cut parachute"
    PARAMETER ev.
    SET ev TO chuteEv(ev).                   // FAR's RealChuteFAR: "cut chute"
    LOCAL n IS 0.
    FOR m IN SHIP:MODULESNAMED(CHUTE_MN) {
        IF m:HASEVENT(ev) { m:DOEVENT(ev). SET n TO n + 1. }
    }
    ldSay("chute: " + ev + " on " + n + " part(s)").
}

FUNCTION ldChuteProbe {                     // log only: FAR's chute as RealChuteFAR has it (ADDONS:KALS:FARCHUTE: its state,
    // area, the height it compares with deployAltitude, its reef timer); nothing without a RealChuteFAR
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN. }
    IF NOT ADDONS:KALS:HASSUFFIX("FARCHUTE") { RETURN. }
    LOCAL s IS ADDONS:KALS:FARCHUTE.
    IF s <> "" { ldSay("chute probe: " + s). }
}

// the aft dump. KSP's names (ModuleResourceDrain): the fields "drain" (draining), "drain rate" (% of the capacity per
// second), "drain mode" (TRUE Vessel, FALSE Part); the actions "drain" (start) and "stop draining". Part mode drains only
// the valve's parent -- Vessel mode would take the forward RCS's mono too and move the CoM aft: never dumped in it. All
// valves or none: one alone pushes the tail sideways (~47 kN at 20 %/s, 4.4 m behind the CoM).
FUNCTION ldDumpFld {
    PARAMETER m, f.
    IF NOT modLive(m) { RETURN "gone". }      // A valve of a rebuilt vessel is not read
    IF m:HASFIELD(f) { RETURN m:GETFIELD(f). }
    RETURN "?".
}

FUNCTION ldDumpSay {                        // the valves and their parents' propellant, to the log
    PARAMETER tag.
    IF ldDrain:LENGTH = 0 { ldSay("DUMP (" + tag + "): no drain valve behind the CoM"). RETURN. }
    LOCAL dsV IS "".
    LOCAL dsR IS "".
    LOCAL dsT IS 0.
    LOCAL dsP IS LIST().
    FOR m IN ldDrain {
        SET dsV TO dsV + (CHOOSE "" IF dsV = "" ELSE ", ") + ldDumpFld(m, "drain mode") + " " + ldDumpFld(m, "drain rate")
                 + " " + ldDumpFld(m, "drain").
        IF modLive(m) { IF NOT dsP:CONTAINS(m:PART:PARENT:UID) {   // A valve of a rebuilt vessel is not read
            dsP:ADD(m:PART:PARENT:UID).
            SET dsR TO dsR + " " + m:PART:PARENT:NAME + ":".
            FOR rs IN m:PART:PARENT:RESOURCES {
                IF rs:CAPACITY > 0 {
                    SET dsR TO dsR + " " + rs:NAME + " " + ROUND(rs:AMOUNT, 1) + "/" + ROUND(rs:CAPACITY).
                    SET dsT TO dsT + rs:AMOUNT * rs:DENSITY.
                }
            }
        } }
    }
    ldSay("DUMP (" + tag + "): " + ldDrain:LENGTH + " valve(s) [vessel mode, rate %/s, draining: " + dsV + "] on" + dsR
          + " = " + ROUND(dsT, 3) + " t of " + ROUND(SHIP:MASS, 3) + " t").
}

FUNCTION ldGearF {                          // the main gear's contact ahead of the CoM along the body, m (ldGearGeom's ggF)
    IF ldGearM:LENGTH = 0 { RETURN -99. }
    IF NOT ldLive() { RETURN -99. }          // The gear parts' bounds only while they are this vessel's (a part lost in a breakup)
    LOCAL gfFw IS SHIP:FACING:FOREVECTOR.
    LOCAL gfDn IS V(0, 0, 0) - SHIP:FACING:TOPVECTOR.
    LOCAL gfF IS 0.
    FOR pt IN ldGearM {
        LOCAL gfB IS pt:BOUNDS.
        SET gfF TO gfF + (VDOT(gfB:FURTHESTCORNER(gfDn - 0.1 * gfFw), gfFw) + VDOT(gfB:FURTHESTCORNER(gfDn + 0.1 * gfFw), gfFw)) / 2.
    }
    RETURN gfF / ldGearM:LENGTH.
}

FUNCTION ldCgStart {                        // the CG targeter's start: TRUE = the valves drain toward LD_CG_TGT
    PARAMETER tag.
    IF NOT ldLive() { RETURN FALSE. }      // Not while a splashdown's rebuild is being read (the hold)
    IF NOT LD_DUMP { ldSay("CG TARGET (" + tag + "): off (LD_DUMP FALSE)"). RETURN FALSE. }
    LOCAL csF IS ldGearF().
    IF csF < -90 { ldSay("CG TARGET (" + tag + "): no main gear found"). RETURN FALSE. }
    SET ldMpN TO 0.                         // the mono trim follows the dump (ldCgTick)
    SET ldMpSt TO 0.
    IF NOT LD_CG_MP { ldSay("CG TRIM: off (LD_CG_MP FALSE)"). }
    ELSE IF ldMpF:LENGTH = 0 OR ldMpA:LENGTH = 0 { ldSay("CG TRIM: no mono tank " + (CHOOSE "ahead of" IF ldMpF:LENGTH = 0 ELSE "behind") + " the CoM"). }
    ELSE { SET ldMpSt TO 1. }
    IF csF <= LD_CG_TGT + LD_CG_DB {
        ldSay("CG TARGET (" + tag + "): the main gear's contact " + ROUND(csF, 2) + " m ahead of the CoM, target "
              + LD_CG_TGT + ": nothing to dump").
        RETURN FALSE.
    }
    ldSay("CG TARGET (" + tag + "): the main gear's contact " + ROUND(csF, 2) + " m ahead of the CoM, target "
          + LD_CG_TGT + ": dumping aft").
    ldDumpStart().
    FOR m IN ldDrain { IF m:HASFIELD("drain") { IF m:GETFIELD("drain") { SET ldCgOn TO TRUE. } } }
    RETURN ldCgOn.
}

FUNCTION ldCgTick {                         // each pass while draining: stop at the target or when the tanks are dry
    IF NOT ldLive() { RETURN. }            // The valves and the parts are read only while they are this vessel's
    IF NOT ldCgOn { IF ldMpSt > 0 { ldMpTick(). } RETURN. }     // then the mono trim
    LOCAL ctF IS ldGearF().
    LOCAL ctOn IS 0.
    FOR m IN ldDrain { IF m:HASFIELD("drain") { IF m:GETFIELD("drain") { SET ctOn TO ctOn + 1. } } }
    IF ctF <= LD_CG_TGT OR ctOn = 0 {
        FOR m IN ldDrain { IF m:HASACTION("stop draining") { m:DOACTION("stop draining", TRUE). } }
        SET ldCgOn TO FALSE.
        ldDumpSay("CG TARGET " + (CHOOSE "reached" IF ctF <= LD_CG_TGT ELSE "short, the tanks dry") + ": the contact "
                  + ROUND(ctF, 2) + " m ahead of the CoM").
    }
}

FUNCTION ldMpCap {                         // a part's MonoPropellant capacity (0: none)
    PARAMETER pt.
    FOR rs IN pt:RESOURCES { IF rs:NAME = "MonoPropellant" { RETURN rs:CAPACITY. } }
    RETURN 0.
}

FUNCTION ldMpRs {                          // a mono tank's MonoPropellant (ldMpF / ldMpA hold only parts with it)
    PARAMETER pt.
    FOR rs IN pt:RESOURCES { IF rs:NAME = "MonoPropellant" { RETURN rs. } }
    RETURN pt:RESOURCES[0].
}

FUNCTION ldMpSay {                          // the mono trim's line
    PARAMETER tag, f.
    ldSay("CG TRIM " + tag + ": the contact " + ROUND(f, 3) + " m ahead of the CoM, target " + LD_CG_TGT + "; mono forward "
          + ROUND(ldMpRs(ldMpF[0]):AMOUNT, 1) + " / aft " + ROUND(ldMpRs(ldMpA[0]):AMOUNT, 1) + ", " + ldMpN + " transfer(s)").
}

FUNCTION ldMpTick {                         // the mono fine trim, each pass after the dump (ldCgTick)
    LOCAL mtF IS ldGearF().
    LOCAL mtE IS mtF - LD_CG_TGT.           // > 0: the CoM too far aft: mono aft -> forward
    IF ldMpSt = 2 {                         // a transfer running: stop it as the target is crossed
        LOCAL mtX IS ldMpX["x"].
        IF ldMpS * mtE <= 0 OR TIME:SECONDS - ldMpT > LD_MP_WAIT {
            IF mtX:STATUS = "Transferring" { SET mtX:ACTIVE TO FALSE. }
        } ELSE IF mtX:STATUS = "Transferring" OR TIME:SECONDS - ldMpT < 0.3 { RETURN. }   // the CoM follows the tanks a tick late
        IF mtX:STATUS = "Failed" { ldSay("CG TRIM: the transfer failed: " + mtX:MESSAGE). }
        SET ldMpSt TO 1.
        SET ldMpT TO TIME:SECONDS.
        RETURN.                             // aimed again from the CoM it left
    }
    IF ldMpN > 0 AND TIME:SECONDS - ldMpT < 0.3 { RETURN. }
    IF ABS(mtE) <= LD_CG_DB OR ldMpN >= LD_MP_ITER {
        ldMpSay(CHOOSE "done" IF ABS(mtE) <= LD_CG_DB ELSE "left", mtF).
        SET ldMpSt TO 0.
        RETURN.
    }
    LOCAL mtFp IS ldMpF[0].
    LOCAL mtAp IS ldMpA[0].
    LOCAL mtRf IS ldMpRs(mtFp).
    LOCAL mtRa IS ldMpRs(mtAp).
    LOCAL mtD IS VDOT(mtFp:POSITION - mtAp:POSITION, SHIP:FACING:FOREVECTOR).     // m, the tanks' spacing
    LOCAL mtU IS ABS(mtE) * SHIP:MASS / (mtRf:DENSITY * MAX(mtD, 1)).            // units to move
    IF mtE > 0 { SET mtU TO MIN(mtU, MIN(mtRa:AMOUNT, mtRf:CAPACITY - mtRf:AMOUNT)). }
    ELSE { SET mtU TO MIN(mtU, MIN(mtRf:AMOUNT, mtRa:CAPACITY - mtRa:AMOUNT)). }
    IF mtD < 1 OR mtU < 0.5 {
        ldMpSay("short (" + (CHOOSE "no tank spacing" IF mtD < 1 ELSE (CHOOSE "the aft tank empty or the forward full" IF mtE > 0
                ELSE "the forward tank empty or the aft full")) + ")", mtF).
        SET ldMpSt TO 0.
        RETURN.
    }
    SET ldMpS TO CHOOSE 1 IF mtE > 0 ELSE -1.
    LOCAL mtX IS 0.
    IF mtE > 0 { SET mtX TO TRANSFER("MonoPropellant", mtAp, mtFp, mtU). }
    ELSE { SET mtX TO TRANSFER("MonoPropellant", mtFp, mtAp, mtU). }
    SET mtX:ACTIVE TO TRUE.
    SET ldMpX["x"] TO mtX.
    SET ldMpN TO ldMpN + 1.
    SET ldMpT TO TIME:SECONDS.
    SET ldMpSt TO 2.
    ldMpSay("moving " + ROUND(mtU, 1) + " units " + (CHOOSE "aft -> forward" IF mtE > 0 ELSE "forward -> aft") + " over "
            + ROUND(mtD, 2) + " m", mtF).
}

FUNCTION ldDumpStart {                      // the valves on (Part mode, LD_DUMP_RATE); ldCgStart decides and ldCgTick stops
    IF NOT LD_DUMP { ldSay("DUMP: off (LD_DUMP FALSE)"). RETURN. }
    IF ldDrain:LENGTH = 0 { ldSay("DUMP: no drain valve behind the CoM"). RETURN. }
    LOCAL dsOk IS TRUE.
    FOR m IN ldDrain {
        IF m:HASFIELD("drain mode") { IF m:GETFIELD("drain mode") { m:SETFIELD("drain mode", FALSE). } }
        IF m:HASFIELD("drain rate") { m:SETFIELD("drain rate", LD_DUMP_RATE). }
        IF NOT (m:HASFIELD("drain mode") AND m:HASFIELD("drain") AND m:HASACTION("drain") AND m:HASACTION("stop draining")) {
            SET dsOk TO FALSE.
            ldSay("DUMP: " + m:PART:TITLE + " lacks a control: fields " + m:ALLFIELDNAMES:JOIN(", ") + "; actions "
                  + m:ALLACTIONNAMES:JOIN(", ")).
        } ELSE IF m:GETFIELD("drain mode") { SET dsOk TO FALSE. }      // still Vessel mode: never dumped in it
    }
    IF NOT dsOk { ldDumpSay("NOT STARTED: a valve not in Part mode or without its controls"). RETURN. }
    LOCAL dsOn IS 0.
    FOR m IN ldDrain {
        m:DOACTION("drain", TRUE).
        IF m:GETFIELD("drain") { SET dsOn TO dsOn + 1. }
    }
    IF dsOn > 0 AND dsOn < ldDrain:LENGTH {
        FOR m IN ldDrain { m:DOACTION("stop draining", TRUE). }
        ldDumpSay("STOPPED: only " + dsOn + " of " + ldDrain:LENGTH + " valve(s) started (one alone pushes the tail sideways)").
        RETURN.
    }
    ldDumpSay(CHOOSE "started" IF dsOn > 0 ELSE "nothing to dump").
}

FUNCTION ldPitchNow { RETURN 90 - VANG(SHIP:FACING:FOREVECTOR, SHIP:UP:VECTOR). }

// the main gear's contact relative to the CoM in body axes (the fore-aft middle of each main gear's bounds' bottom
// face), and the pitch above which the CoM is behind the contact: gravity then lifts the nose on the mains. The CoM
// is kOS's origin; the parts' mass-weighted origins are logged against it, and the root part and ALTITUDE's point
// with it (the land log's h is ALTITUDE's). Taken once in the air (gear down) and once on the mains (loaded).
FUNCTION ldGearGeom {
    PARAMETER tag.
    IF NOT ldLive() { RETURN. }              // The gear parts only while they are this vessel's
    IF ldGearM:LENGTH = 0 { RETURN. }
    LOCAL ggFw IS SHIP:FACING:FOREVECTOR.
    LOCAL ggTp IS SHIP:FACING:TOPVECTOR.
    LOCAL ggUp IS SHIP:UP:VECTOR.
    LOCAL ggDn IS V(0, 0, 0) - ggTp.
    LOCAL ggF IS 0. LOCAL ggU IS 0. LOCAL ggAlt IS 0. LOCAL ggLow IS 0.
    FOR pt IN ldGearM {
        LOCAL ggB IS pt:BOUNDS.
        LOCAL ggCr IS ggB:FURTHESTCORNER(ggDn - 0.1 * ggFw).     // the rear-bottom corner (body axes)
        LOCAL ggCf IS ggB:FURTHESTCORNER(ggDn + 0.1 * ggFw).     // the front-bottom corner
        SET ggF TO ggF + (VDOT(ggCr, ggFw) + VDOT(ggCf, ggFw)) / 2.
        SET ggU TO ggU + (VDOT(ggCr, ggTp) + VDOT(ggCf, ggTp)) / 2.
        SET ggAlt TO ggAlt + SHIP:ALTITUDE - ggB:BOTTOMALT.
        SET ggLow TO ggLow - VDOT(ggB:FURTHESTCORNER(V(0, 0, 0) - ggUp), ggUp).
    }
    LOCAL ggN IS ldGearM:LENGTH.
    SET ggF TO ggF / ggN.                       // m ahead of the CoM (< 0: behind)
    SET ggU TO ggU / ggN.                       // m above the CoM (< 0: below)
    LOCAL ggTh IS ldPitchNow().
    LOCAL ggTip IS ARCTAN2(0 - ggF, 0 - ggU).   // the CoM straight above the contact at this pitch
    LOCAL ggX IS ggF * COS(ggTh) - ggU * SIN(ggTh).     // the contact's lead on the CoM at this pitch, m (> 0: gravity nose-up)
    LOCAL ggSm IS 0.
    LOCAL ggSp IS V(0, 0, 0).
    FOR p IN SHIP:PARTS { SET ggSm TO ggSm + p:MASS. SET ggSp TO ggSp + p:MASS * p:POSITION. }
    LOCAL ggCp IS ggSp / MAX(ggSm, 0.001).
    LOCAL ggRp IS SHIP:ROOTPART:POSITION.
    ldSay("GEAR GEOMETRY (" + tag + ", theta " + ROUND(ggTh, 1) + "): the main gear's contact " + ROUND(0 - ggF, 2)
          + " m behind the CoM, " + ROUND(0 - ggU, 2) + " m below it -> on the mains gravity lifts the nose above "
          + ROUND(ggTip, 1) + " deg of pitch (the contact now " + ROUND(ggX, 2) + " m ahead of the CoM).").
    ldSay("  (body axes, m, fore / up of kOS's origin: the parts' CoM " + ROUND(VDOT(ggCp, ggFw), 2) + " / "
          + ROUND(VDOT(ggCp, ggTp), 2) + ", the root part " + ROUND(VDOT(ggRp, ggFw), 2) + " / " + ROUND(VDOT(ggRp, ggTp), 2)
          + "; ALTITUDE's point " + ROUND(ggAlt / ggN - ggLow / ggN, 2) + " m above the origin; " + ggN + " main gear)").
}




// ---------------------------------------------------------------- the log
FUNCTION ldLogHead {
    IF NOT SOCK_LOG { RETURN. }   // the logs off (lib_logsw)
    LOG "t,phase,x,y,h,psd,surfv,mach,qbar,iphase,psha,rpred,drpred,eow,en,emax,emin,herror,nzc,nz_total,phic_at,"
        + "bank,dsbc,alpha_cmd,alpha_rl,nzl_trim,nz_meas,nz_sat,zoom,dm_msg,p_mode,f_mode,sb_mode,h_gear,h_dot,"
        + "nzc_al,phic_al,dsbc_al,wow,wong,theta,cl_dpsi,brakes,decel,alpha_ff,nz_err,aoa_act,mass_t,css_p,css_r,"
        + "sb_auto,zoom_frac,eowerror,bind_en,bind_qb,bind_zoom,bind_rate,qbarf,qbref" TO ldCsv.
}

FUNCTION ldKey {                            // a state value, 0 before the loop first sets it
    PARAMETER lx, k.
    IF lx:HASKEY(k) { RETURN lx[k]. }
    RETURN 0.
}

FUNCTION ldAoa { RETURN VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE). }

FUNCTION ldLogRow {
    PARAMETER st, tg, ags, extra.
    IF NOT SOCK_LOG { RETURN. }   // the logs off (lib_logsw): no row is built
    LOCAL row IS LIST(ROUND(TIME:SECONDS - ldT0, 2), ldPhase, ROUND(st["x"], 1), ROUND(st["y"], 1), ROUND(st["h"], 1),
                      ROUND(st["psd"], 2), ROUND(st["surfv"], 2), ROUND(st["mach"], 4), ROUND(st["qbar"], 1)).
    IF tg:LENGTH > 0 {
        LOCAL g IS tg["g"].
        FOR fv IN LIST(tg["iphase"], ROUND(g["psha"], 2), ROUND(g["rpred"], 1), ROUND(tg["drpred"], 1), ROUND(tg["eow"], 1),
                      ROUND(tg["en"], 1), ROUND(tg["emax"], 1), ROUND(tg["emin"], 1), ROUND(tg["herror"], 1),
                      ROUND(tg["nzc"], 4), ROUND(tg["nz_total"], 4), ROUND(tg["phic_at"], 2)) { row:ADD(fv). }
    } ELSE { FOR fv IN LIST(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) { row:ADD(fv). } }
    FOR fv IN extra { row:ADD(fv). }
    // the Nz cascade's stages in TAEM (which loop binds -- the zoom taper, energy, qbar, rate)
    IF tg:LENGTH > 0 AND ldPhase = "TAEM" {
        FOR k IN LIST("zoom_frac", "eowerror", "bind_en", "bind_qb", "bind_zoom", "bind_rate", "qbarf", "qbref") {
            row:ADD(ROUND(ldKey(tg, k), 4)).
        }
    } ELSE { FOR k IN LIST(0, 0, 0, 0, 0, 0, 0, 0) { row:ADD(0). } }
    LOG row:JOIN(",") TO ldCsv.
}

// ============================================================================ the flight
// one flight program (two buttons, PITCH and ROLL/YAW, as css_dap.ks): the guidance runs every cycle in every mode;
// lib_dap flies the vehicle in both (DAP_AUTO_GUID: AUTO from the record below, CSS from the stick); the HUD (+ HUD
// CAM, RWY) and the TAEM displays stay up in both. No LOCK STEERING: at the start the entry's cooked steering is
// folded into the deploy angles (css_dap's bumpless engage) and switched off.
// Bumpless back to AUTO: while an axis is CSS the guidance's own slew states follow the vehicle (the pitch loop
// re-seeded on the flown alpha and Nz, the bank slew on the flown bank): the orbiter keeps its AUTO loops
// synchronised in CSS.
FUNCTION ldAlphaNow {                       // the pitch-plane angle of attack, deg (lib_dap's)
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    IF vs:MAG < 1 { RETURN 0. }
    RETURN ARCTAN2(-VDOT(vs, SHIP:FACING:TOPVECTOR), VDOT(vs, SHIP:FACING:FOREVECTOR)).
}

FUNCTION ldPubBank {                        // the DAP's bank command: from where its ramp stands to the guidance's bank of this cycle
    PARAMETER shipBank, dtc.
    SET dGdBank0 TO dapGdBank()[0].
    SET dGdBank1 TO shipBank.
    SET dGdBankT TO TIME:SECONDS.
    SET dGdBankDt TO dtc.
    SET ldBank TO shipBank.
}

// a value published once a cycle, ramped over the cycle from where its ramp is (the DAP's bank publication's rule):
// the HUD diamond's bank demand and Nz command (smooth, not a jump each cycle). rs = LIST(from, to, when, over),
// changed in place; the first value is taken whole.
FUNCTION ldRamp {
    PARAMETER rs, val, dt.
    LOCAL now IS TIME:SECONDS.
    LOCAL cur IS rs[1].
    IF rs[2] >= 0 { SET cur TO rs[0] + (rs[1] - rs[0]) * MIN(1, (now - rs[2]) / MAX(rs[3], 0.02)). }
    IF val <> rs[1] OR rs[2] < 0 {
        SET rs[0] TO CHOOSE cur IF rs[2] >= 0 ELSE val.
        SET rs[1] TO val.
        SET rs[2] TO now.
        SET rs[3] TO dt.
        RETURN rs[0].
    }
    RETURN cur.
}

// GO CSS on the HUD and the status label: shown while it is raised (a HAC turn of TG_CSS_PSHA_ALERT or more, latched),
// the HUD reads AUTO (neither axis in CSS: lib_dap's hdCtlTxt) and LD_CSS_PSHA_CLEAR or more of HAC turn is to go
// (prefinal: psha 0); back in AUTO with that much to go it shows again
FUNCTION ldCssShown {
    PARAMETER raised, cssP, cssR, psha.
    RETURN raised AND NOT (cssP OR cssR) AND psha >= LD_CSS_PSHA_CLEAR.
}

FUNCTION ldHudCues {                        // the HUD's frame: the DAP's part (mode, speedbrake), then the guidance symbols
    PARAMETER hudG.
    dapHudTick().
    IF hudG { hdgTick(). }
}

FUNCTION ldEnd {                            // the program ends: the DAP stopped (every surface back to the stick), the pages closed
    PARAMETER why.
    SET dDone TO TRUE.
    WAIT 0.
    dapStop().
    IF DEFINED tdOn { tdClose(). }
    ldSay(why).
}

FUNCTION ldSbCap {                          // the speedbrake cap (LD_SB_CAP): the guidance's 65s -> the cap
    IF LD_SB_CAP <= 0 { RETURN. }
    SET TG_DSBSUP TO LD_SB_CAP.             // taemg: the supersonic setting and the subsonic upper limit
    SET TG_DSBLIM TO LD_SB_CAP.             //   the S-turn's command (Eq 2.1)
    SET TG_DSBNOM TO LD_SB_CAP.             //   the energy law's nominal (Eq 2.7)
    SET tgDsbMax TO LD_SB_CAP.              //   the subsonic upper limit, unless the max below
    SET AL_SB_MAX TO LD_SB_CAP.             // alg: the cap, then the 3000 ft retract's and the short field's 80 %
    SET AL_SB_MAX_RET TO MIN(0.8 * 98.6, LD_SB_CAP).
    SET AL_SB_MAX_TD TO LIST(AL_SB_MAX_TD[0], MIN(0.8 * 98.6, LD_SB_CAP)).
    IF LD_SB_MAX > LD_SB_CAP {              // the maximum (LD_SB_MAX): the limits only -- the nominal stays
        SET tgDsbMax TO LD_SB_MAX.          // taemg: the subsonic energy law's upper limit
        SET TG_DSBLIM TO LD_SB_MAX.         //   the S-turn's command (Eq 2.1)
        SET AL_SB_MAX TO LD_SB_MAX.         // alg: the cap, then the 3000 ft retract's and the short field's 80 %
        SET AL_SB_MAX_RET TO MIN(0.8 * 98.6, LD_SB_MAX).
        SET AL_SB_MAX_TD TO LIST(AL_SB_MAX_TD[0], MIN(0.8 * 98.6, LD_SB_MAX)).
    }
    ldSay("speedbrake cap " + LD_SB_CAP + " hinge, max " + MAX(LD_SB_CAP, LD_SB_MAX) + " (EXPERIMENTS): TAEM supersonic "
          + TG_DSBSUP + ", subsonic up to " + MAX(TG_DSBSUP, tgDsbMax) + ", S-turn " + TG_DSBLIM + ", A/L " + AL_SB_MAX).
}

// ---------------------------------------------------------------- the crew's bailout in TAEM (lib_dap's BAILOUT)
FUNCTION ldDitch {                          // lib_grtls grtlsDitch's law: once the height above the water is at
    PARAMETER tg, st, bl.                   //   most LD_DITCH_TAU x the sink, the exponential flare's Nz for the pitch loop
    LOCAL sink IS 0 - st["hdot"].
    IF NOT bl["dit"] {
        IF sink <= 0 OR ALT:RADAR > LD_DITCH_TAU * sink { RETURN. }
        SET bl["dit"] TO TRUE.
        ldSay("BAILOUT DITCH: the flare at " + ROUND(ALT:RADAR) + " m above the water, sink " + ROUND(sink, 1) + " m/s, "
              + ROUND(SQRT(2 * st["qbar"] / 1.225) / 0.5144444) + " KEAS, alpha <= " + LD_DITCH_ALPMAX + ", wings level").
    }
    LOCAL hdc IS 0 - MAX(LD_DITCH_HDTD, ALT:RADAR / LD_DITCH_TAU).
    LOCAL cosphi IS MAX(COS(tg["phic_at"]), 0.20).
    SET tg["nz_total"] TO taemg_midval(st["costh"] / cosphi + LD_DITCH_K * (hdc - st["hdot"]) / TG_GO, -TG_NZ_TOTAL_LIM,
                                       TG_NZ_TOTAL_LIM).
    SET dGdNz TO tg["nz_total"].
}

FUNCTION ldBailCoast {                      // the hold's bank (G4.9's sign: + = a right turn) toward the
    PARAMETER st, bl.                       //   line CST_DOFF off the nearest coast (lib_coast's cstShoreHdg, the
    IF NOT LD_COAST OR NOT CST["ok"] OR bl["dit"] { RETURN 0.0. }   //   GRTLS BLUE's law); 0 off the table, ditching
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL vr IS vs:MAG.
    LOCAL gam IS 0.0.
    IF vr > 1 { SET gam TO ARCSIN(cstMid(VDOT(vs, SHIP:UP:VECTOR) / vr, -1.0, 1.0)). }
    LOCAL geo IS SHIP:GEOPOSITION.
    LOCAL sn IS LEXICON("t", TIME:SECONDS, "lat", geo:LAT, "lng", geo:LNG, "sea", geo:TERRAINHEIGHT < 0, "vr", vr,
                        "gam", gam, "trk", cstTrk()).
    LOCAL phib IS LD_COAST_PHILM * cstMid((gam - LD_COAST_GAM4) / LD_COAST_GAMW, 0.0, 1.0).
    IF st["qbar"] < LD_COAST_QB { SET phib TO 0.0. }
    LOCAL first IS bl["sh_t"] < 0.
    LOCAL hc IS cstShoreHdg(bl, sn).
    IF first {
        ldSay("BAILOUT: toward the coast" + (CHOOSE (": " + ROUND(bl["sh"][0] / 1000, 1) + " km, heading " + ROUND(hc)
              + ", track " + ROUND(sn["trk"]) + (CHOOSE ", at sea" IF sn["sea"] ELSE ", over land"))
              IF bl["sh"]:LENGTH > 0 ELSE ": off the table, wings level")).
    }
    IF hc < 0 { RETURN 0.0. }
    RETURN cstMid(TG_GPHI * cstRes180(hc - sn["trk"]), 0 - phib, phib).
}

FUNCTION ldBailStep {                       // after taemg_cycle, once dBailReq: no A/L; below LD_BAIL_MACH with q the GRTLS's
    PARAMETER tg, st, bl, ph0, pr0.         //   hold; bl: its state; ph0 / pr0: the bank and its rate before the cycle
    IF NOT bl["req"] {
        SET bl["req"] TO TRUE.
        ldSay("BAILOUT CONFIRMED (the crew): TAEM phase " + tg["iphase"] + ", Mach " + ROUND(st["mach"], 2) + ", h "
              + ROUND(st["h"]) + " m: no A/L; the hold below Mach " + LD_BAIL_MACH).
        IF LD_COAST AND NOT CST["ok"] {     // the coast table, once (lib_coast; the GRTLS's file)
            LOCAL cf IS cstFileHere().      // the coast where the orbiter is
            IF cstLoad(cf) { ldSay("BAILOUT: the coast table " + cf + " (" + CST["s"]:LENGTH + " segments)"). }
            ELSE { ldSay("BAILOUT: no coast table (" + cf + "): the hold flies wings level"). }
        }
    }
    IF tg["tg_end"] {                       // no A/L (the FSSR's BAIL_ARM term in TGTRAN's TG_END test)
        SET tg["tg_end"] TO FALSE.
        SET tg["itran"] TO FALSE.
    }
    IF NOT bl["on"] AND st["mach"] < LD_BAIL_MACH AND st["qbar"] >= LD_BAIL_QMIN {   // lib_grtls's engagement
        SET bl["on"] TO TRUE.
        SET bl["qbars"] TO 0.5 * 1.225 * (LD_BAIL_KEAS * 0.5144444) ^ 2.
        SET bl["qbarf"] TO st["qbar"].
        SET bl["qbard"] TO 0.0.
        SET bl["nzc"] TO tg["nzc"].         // a deviation: from TAEM's Nz command, bumpless (the GRTLS's phase 7 starts at 0)
        dapBailFlies().
        ldSay("BAILOUT: the hold engaged, TAEM phase " + tg["iphase"] + ", Mach " + ROUND(st["mach"], 2) + ", h "
              + ROUND(st["h"]) + " m, " + ROUND(SQRT(2 * st["qbar"] / 1.225) / 0.5144444) + " -> " + LD_BAIL_KEAS
              + " KEAS, " + (CHOOSE "toward the coast" IF LD_COAST AND CST["ok"] ELSE "wings level")
              + ", the speedbrake closed").
    }
    IF bl["on"] {                           // lib_grtls phase 7's lines (FSSR TGNZC eqs 2.2, 3.6-3.7 in its form)
        SET bl["qbard"] TO taemg_midval(TG_CQG * (st["qbar"] - bl["qbarf"]), -LD_BAIL_QBARDL, LD_BAIL_QBARDL).
        SET bl["qbarf"] TO bl["qbarf"] + bl["qbard"] * TG_DTG.
        LOCAL nzcl IS LD_BAIL_QBG2 * (LD_BAIL_QBG1 * (bl["qbarf"] - bl["qbars"]) + bl["qbard"]).
        SET bl["nzc"] TO bl["nzc"] + taemg_midval((nzcl - bl["nzc"]) * TG_CQG, -LD_BAIL_NZCDL, LD_BAIL_NZCDL) * TG_DTG.
        SET tg["nzc"] TO bl["nzc"].
        SET tg["dsbc"] TO 0.0.              // the speedbrake closed (FSSR TGSBC 3.1: DSBC = 0 under BAILOUT_ARM)
        LOCAL phc IS ldBailCoast(st, bl).   // toward the coast (SCOM 6.7: zero roll = off the table, ditching,
        SET tg["phic_dem"] TO phc.          //   or LD_COAST FALSE)
        IF NOT dCssR {                      //   slewed from the bank before the cycle, as taemg_cycle's
            IF TG_ROLL_SLEW {
                LOCAL rlm IS taemg_roll_lim(st["mach"]).
                LOCAL sl IS taemg_bank_slew(ph0, phc, pr0, TG_DTG, rlm[0], rlm[1]).
                SET tg["phic_at"] TO sl[0].
                SET tg["phic_rate"] TO sl[1].
            } ELSE {
                SET tg["phic_rate"] TO (phc - ph0) / TG_DTG.
                SET tg["phic_at"] TO phc.
            }
        }
        taemg_nz_total(tg, st).
        IF NOT LD_DITCH AND ALT:RADAR < LD_BAIL_END { SET bl["end"] TO TRUE. }
        IF LD_DITCH AND (SHIP:STATUS = "SPLASHED" OR SHIP:STATUS = "LANDED" OR ALT:RADAR < 1) { SET bl["end"] TO TRUE. }   // the ditch ends in the water
    }
}

FUNCTION landRun {
    PARAMETER rwyName, useCss IS FALSE, aEnt IS -1.     // useCss: start with both axes in CSS; aEnt: the entry's alpha
    SET CONFIG:IPU TO LD_IPU.                           //   COMMAND at the switch (-1: the flown alpha)
    SET ldT0 TO TIME:SECONDS.
    SET ldMsg TO "".                                    // a second landRun in one session starts clean
    SET ldWhy TO "".
    SET ldFdPt TO -1. SET ldBndT TO -1.
    SET ldHudBd TO LIST(0, 0, -1, 1).                   // the HUD diamond's ramps start clean
    SET ldHudNz TO LIST(1, 1, -1, 1).
    SET ldRwy TO ldLoadRunway(rwyName).
    IF ldRwy:LENGTH = 0 { kmSay("landRun: no runway " + rwyName + " in hud/hud_runways.txt", "W"). RETURN FALSE. }
    IF NOT ldRwy["surveyed"] { kmSay("landRun: " + rwyName + " has no surveyed elevation -- an ELS: not flown by landRun", "W"). RETURN FALSE. }
    taemg_set_aim(rwyName, ldAimLaw()).
    SET dRwyAlt TO ldOtherEnd(rwyName).     // the SW RWY button's runway, "" none
    LOCAL tagT IS "" + ROUND(TIME:SECONDS).
    LOCAL tagN IS 2.                        // a save flown again starts at the same TIME: never append
    UNTIL NOT EXISTS("0:/logs/land_" + tagT + ".csv") {
        SET tagT TO ROUND(TIME:SECONDS) + "_" + tagN.
        SET tagN TO tagN + 1.
    }
    SET ldCsv TO "0:/logs/land_" + tagT + ".csv".
    SET ldTxt TO "0:/logs/land_" + tagT + ".txt".
    ldLogHead().
    ldSay("landRun " + rwyName + " (hdg " + ROUND(ldRwy["hdg"], 2) + ", len " + ROUND(ldRwy["len"]) + " m, elev "
          + ROUND(ldRwy["elev"], 2) + "): TAEM from " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s, "
          + ROUND(SHIP:ALTITUDE) + " m").
    ldFindParts().                          // before the DAP: it records the brake sliders as found (capped at 95 %)
    ldSay("parts: rudder halves " + ldRud:LENGTH + ", main gear " + ldGearM:LENGTH + ", nose gear " + ldGearN:LENGTH).
    ldDumpSay(CHOOSE "armed" IF LD_DUMP ELSE "off").
    ldSbCap().                                  // the speedbrake cap: logged, before the guidance initialises

    // ---- the DAP (lib_dap, the guidance mode): it flies AUTO and CSS; its window holds the mode buttons + our status
    SET DAP_AUTO_GUID TO TRUE.
    SET DAP_BRK_BASE TO CHOOSE LD_BRAKE_PCT IF LD_BRAKE_FULL ELSE -1.    // the sliders after WONG (else the craft's)
    dapInit().
    ldSay("the DAP: log " + D_CSV + " (" + (50 / D_LOG_EVERY) + " Hz); AUTO = the guidance through the DAP, CSS = the stick; "
          + "no LOCK STEERING").
    // the entry's cooked steering (ops3q) is still on: its pitch command, read off the gimbal (it IS the vessel's
    // control state), into the elevons' and the flap's deploy angles before the lock -- css_dap's bumpless engage
    IF dGmbLive() {
        LOCAL gpr IS dGmb:GIMBAL:PITCHANGLE.
        LOCAL gp0 IS gpr.
        LOCAL gpw IS "".
        IF ABS(gp0) >= LD_GP0_SAT {
            LOCAL gpi IS 0.
            IF DEFINED grdI { SET gpi TO clampV(grdI[0], 1). }
            SET gpw TO " (on the stop: the DAP's trim " + ROUND(gpi, 3) + " instead)".
            SET gp0 TO gpi.
        }
        SET dElev TO clampV(dElev - ELV_STICK * STICK_P_SIGN * gp0, ELV_LIM).
        IF dHaveFlap { SET dFlapAng TO clampV(dFlapAng - FLAP_STICK * STICK_P_SIGN * gp0, FLAP_LIM). }
        SET dTrimE TO -(dElev - tabLook(SBX_TAB, dapMach()) * dSbBase).
        ldSay("the steering's pitch command " + ROUND(gpr, 3) + gpw + " taken into the deploy angles (elevons "
              + ROUND(dElev, 2) + ", flap " + ROUND(dFlapAng, 2) + ")").
    }
    LOCAL dispOn IS FALSE.                  // the pages first (their rows take the DAP's buttons); on the
    IF LD_DISP AND EXISTS("0:/lib/lib_taemdisp.ks") {   //   GRTLS's open windows tdInit swaps to TAEM's pages
        RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_taemdisp.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_taemdisp.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_taemdisp.ks").
        SET dispOn TO tdInit().
    }
    IF dispOn AND (DEFINED TD_CS_STATE) {   // the pages' C# switch, logged
        ldSay("TAEM pages: " + TD_CS_STATE + (CHOOSE ", redrawn every " + TD_DT_CS + " s between the cycles" IF tdFast() ELSE ", once a cycle")).
    }
    dapGuiBuild("ORBITER DAP", "TAEM, A/L, rollout -- " + rwyName).
    SET ldLbl TO uiText(dStat, "TAEM / A/L: starting").
    LOCAL hudG IS FALSE.                    // lib_hudg.ks: the guidance symbols on the HUD
    IF LD_HUD {
        dapHudInit().
        IF dHud {
            SET hudG TO hdgInit().
            // the HUD on the LANDING runway, fixed (RWY still steps the overlay through the others)
            FROM { LOCAL k IS 0. } UNTIL k >= hdRwys:LENGTH STEP { SET k TO k + 1. } DO {
                IF hdRwys[k][1] = rwyName { hdSelectRunway(k). }
            }
            SET hdRwyAuto TO FALSE.
            SET hdFinalOn TO FALSE.
        }
    }
    // the rollout's centreline: the landing runway (lib_dap clGeom)
    SET dGdRwyThr TO LATLNG(ldRwy["lat"], ldRwy["lon"]).
    SET dGdRwyFar TO hdDest(dGdRwyThr, ldRwy["hdg"], ldRwy["len"]).
    SET dGdRwyOk TO TRUE.
    IF DEFINED grdOn { IF grdOn { grdStop(). } }   // the GRTLS DAP (lib_grdap, ops6q) held the attitude to here
    dapBegin().                             // every surface locked from here, SAS off
    LOCK STEERING TO SHIP:FACING.           // the lock known to this file, so the UNLOCK below compiles to the release
    UNLOCK STEERING.
    IF DEFINED STEER_UNLOCKS { FOR u IN STEER_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } } }   // live runs' locks (STEER_UNLOCKS)
    WHEN TRUE THEN {
        IF NOT dDone { dapTick(). }
        RETURN NOT dDone.
    }
    IF useCss {
        SET dBtnP:PRESSED TO TRUE.
        SET dBtnR:PRESSED TO TRUE.
    }

    // ---- TAEM
    LOCAL st IS ldState().
    LOCAL same IS CHOOSE 1.0 IF st["y"] >= 0.0 ELSE -1.0.
    LOCAL ysgn IS CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same.
    LOCAL gtg IS 0.                         // the GRTLS's crew choices (OTT STRT / MEP, SW RWY) carry into TAEM
    IF DEFINED GR { IF GR:ISTYPE("Lexicon") { IF GR:HASKEY("dmcrew") { IF GR["dmcrew"] { SET gtg TO GR["tg"]. } } } }
    IF gtg:ISTYPE("Lexicon") { SET ysgn TO gtg["ysgn"]. }
    LOCAL bank0 IS dapBank().               // + = LEFT (the ship's)
    SET TG_DOWNMODE_POLICY TO LD_DOWNMODE.
    LOCAL tg IS taemg_init(st, ysgn, TG_RFMX, 0.0, taemg_ship_to_bank(bank0), 0.0).   // TAEM from the handover bank
    IF gtg:ISTYPE("Lexicon") {
        FOR k IN GR_TG_CREW { SET tg[k] TO gtg[k]. }
        SET GR["dmcrew"] TO FALSE.          // taken once (a GLOBAL outlives the program)
        ldSay("the GRTLS's crew choices: HAC ysgn " + ysgn + ", strt " + tg["strt"] + ", nep " + tg["nep"] + ", rwy_sw "
              + tg["rwy_sw"]).
    }
    ldTgCsSetup().                          // the C# guidance's constants (or kOS's guidance)
    ldAlCsSetup().                          // the C# A/L guidance's and pitch loop's (or kOS's)
    ldRwOff().
    SET ldBank TO bank0.
    ldSay("TAEM start: bank " + ROUND(bank0, 3) + " deg (the vehicle's, ship sign + = left; land_replay.py reads it)").
    ldSay("mass " + ROUND(SHIP:MASS, 4) + " t; downmodes " + LD_DOWNMODE).
    ldSay("SW RWY: " + (CHOOSE dRwyAlt IF dRwyAlt <> "" ELSE "none (no other end)")).
    SET ldAlpha TO ldAlphaNow().
    LOCAL fdWarm IS TIME:SECONDS.
    UNTIL TIME:SECONDS - fdWarm > LD_FD_WIN + 0.1 { ldFd(LD_FD_WIN). WAIT 0. }
    IF aEnt >= 0 { SET ldAlpha TO aEnt. }
    ldFcSeed(tg, ldAlpha, ldFdLift / TG_GO, st["qbar"], st["mach"]).   // fcs_trim_seed (FCSEED when LD_AL_CS)
    // nz_sat must exist before its first reader: the first guidance cycle (and its log) runs before the first pitch update.
    SET tg["nz_sat"] TO 0.
    SET ldPhase TO "TAEM".
    // the DAP's first AUTO record: where the vehicle is
    SET dGdAlpha TO ldAlpha.
    SET ldAcHist TO LIST(ldAlpha).          // the mean starts there
    SET dGdAlphaDot TO 0.
    SET dGdNz TO st["costh"] / MAX(COS(bank0), 0.2).
    ldPubBank(bank0, 1).
    SET dGdSb TO dSbBase.
    SET dGdOn TO TRUE.
    LOCAL tTaem0 IS TIME:SECONDS.           // the speedbrake held as found until LD_SB_HOLD_S from here
    LOCAL sb0 IS dSbBase.
    LOCAL tNext IS TIME:SECONDS.
    LOCAL tSub IS TIME:SECONDS.
    IF DEFINED FLFX_PH { SET FLFX_PH TO "TAEM". }   // The phase the DAP's SW 02 test reads
    LOCAL goCss IS FALSE.                   // GO CSS raised (latched)
    LOCAL goCssUp IS FALSE.                 // ... and shown (ldCssShown, every tick: the crew's CSS at once)
    LOCAL cmd IS ldAlpha.
    // the load spread: a guidance cycle would be one burst of 20-25k opcodes (the guidance, the pages, the log row; the
    // HUD would stand 5-8 ticks each cycle), so the pages draw at the start of the next tick (tdDue: the same tg and
    // state, the HUD and the pitch loop between), and the HUD record's and the status label's per-cycle parts are
    // written once a cycle (cueNew), their per-tick parts (the diamond's ramps, the measured Nz) every tick
    LOCAL tdDue IS FALSE.
    LOCAL tdSt IS st.
    // while the C# draws the pages (lib_taemdisp tdFast) they are drawn again every TD_DT_CS (0.1 s) between the
    // cycles, on the vehicle now (ldState) and the cycle's tg (tdTick's cyc FALSE: the flash and the turn rate stay the
    // cycle's); never in a guidance cycle's tick (TIME < tNext); on the TD_DT_CS grid (tdGridNx: one redraw a 0.1 s
    // slot, the flash its parity). kOS drawing (TD_CS off, a fallback): once per cycle (tdNxt 0). The grid
    // and the redraws' test in real time (uiRt), the cycle (tNext) in game time.
    LOCAL tdNxt IS 0.
    LOCAL cueNew IS TRUE.
    LOCAL bl IS LEXICON("req", FALSE, "on", FALSE, "end", FALSE, "qbars", 0, "qbarf", 0, "qbard", 0, "nzc", 0, "dit", FALSE,
        "sh_t", -1, "sh", LIST(), "sh_side", 0).   // the bailout; the coast search's state (lib_coast)
    UNTIL tg["tg_end"] OR dDone OR bl["end"] {
        IF tdDue {                          // the pages, one tick after their cycle (tdTick reads no key the pitch loop writes)
            SET tdDue TO FALSE.
            tdTick(tg, tdSt).
            SET tdNxt TO 0.                 // the redraws, from TD_DT_CS after the cycle's draw (the C# drawing only)
            IF DEFINED TD_DT_CS { IF tdFast() { SET tdNxt TO tdGridNx(uiRt()). } }   // real time
        } ELSE IF tdNxt > 0 AND uiRt() >= tdNxt AND TIME:SECONDS < tNext {
            SET tdNxt TO 0.
            IF tdFast() {                   // (a fallback since the cycle's draw: no kOS redraws)
                SET tdNxt TO tdGridNx(uiRt()).
                tdTick(tg, ldState(), FALSE).
            }
        }
        dapBailTick().                      // a BAILOUT first press unconfirmed in time is dropped
        ldSiteTick().                       // VERT SIT's < SITE >
        ldFd(LD_FD_WIN).
        IF ldFdNew AND tg:HASKEY("nz_total") {     // a window end after the first guidance cycle
            ldFcWindow(tg, ldFdLift / TG_GO, st["qbar"]).   // fcs_window_end + alpha_rl_bind 0 (FCWINDOW when LD_AL_CS)
        }
        // SW 02 GUIDANCE LOST (TAEM): the last COMMAND is held (no bank, alpha, Nz or speedbrake update to the DAP). The cycle itself still runs, so the display's HAC
        // geometry, E/W and altitude error stay live (only the commands blank there: lib_taemdisp tdGdLost)
        LOCAL tgLost IS FALSE.
        IF DEFINED FLFX_SWPROG { SET tgLost TO flfxSwGuid("TAEM"). }
        IF TIME:SECONDS >= tNext {
            SET tNext TO tNext + TG_DTG.
            SET st TO ldState().
            IF dCssR {                              // CSS roll: the guidance's bank slew follows the vehicle
                SET tg["phic_at"] TO taemg_ship_to_bank(dapBank()).
                SET tg["phic_rate"] TO 0.
            }
            IF dDmReq = "site" {                    // the crew's site switch (SW RWY's path)
                ldSay("downmode press: site " + dSiteReq + " (TAEM phase " + tg["iphase"] + ")").
                LOCAL sg IS ldSiteGo(tg).
                ldSay(sg[1]).
                IF sg[0] { SET st TO ldState(). }
            } ELSE IF dDmReq = "rwy" {              // the crew's SW RWY: the runway first, then the guidance
                LOCAL rej IS taemg_rwy_rej(tg, dRwyAlt <> "").
                ldSay("downmode press: rwy (TAEM phase " + tg["iphase"] + ")").
                IF rej <> "" {
                    SET tg["dm_rej"] TO rej.        // the cycle clears dm_rej: logged here
                    ldSay("downmode press refused: " + rej).
                } ELSE {
                    LOCAL old IS ldRwy["name"].
                    LOCAL nw IS dRwyAlt.
                    ldSwitchRunway(nw).
                    SET st TO ldState().            // the new runway's frame, before any guidance function
                    taemg_rwy_switch(tg, st, nw).
                    ldSay("RWY SWITCH " + old + " -> " + nw + ": " + tg["dm_why"] + ", x " + ROUND(st["x"]) + " y "
                          + ROUND(st["y"]) + " m in the new frame").
                }
                SET dDmReq TO "".
            } ELSE IF dDmReq <> "" {                // the crew's press (the DAP window): taken this cycle
                SET tg["dm_crew"] TO dDmReq.
                ldSay("downmode press: " + dDmReq + " (TAEM phase " + tg["iphase"] + ")").
                SET dDmReq TO "".
            }
            LOCAL ph0 IS tg["phic_at"].             // the bank before the cycle (the bailout's wings-level slew)
            LOCAL pr0 IS tg["phic_rate"].
            ldTgCycle(tg, st).                      // taemg_cycle, by the C# coprocessor when LD_TG_CS (runs under SW 02 too: its products feed the displays, the commands are held below)
            IF dBailReq { ldBailStep(tg, st, bl, ph0, pr0). }   // the crew's BAILOUT (lib_dap)
            IF DEFINED FLFX_SWPROG {            // 2 / S4c-3A: AUTO DAP LOST (SW 01 at once, SW 02 TAEM after DAP_GD_LOST_S): GO CSS
                IF NOT goCss AND flfxSwAutoLost("ENTRY", "TAEM") {
                    SET goCss TO TRUE.
                    ldSay("GO CSS: AUTO DAP LOST").
                }
            }
            IF NOT goCss AND tg["g"]["psha"] >= TG_CSS_PSHA_ALERT {
                SET goCss TO TRUE.
                ldSay("GO CSS: the HAC turn is " + ROUND(tg["g"]["psha"]) + " deg (>= " + TG_CSS_PSHA_ALERT + ")").
            }
            SET ldMsg TO tg["dm_msg"].              // the label's downmode in effect (an undo clears it)
            IF tg["dm_why"] <> ldWhy {              // each downmode taken or undone, once; a runway switch
                SET ldWhy TO tg["dm_why"].          //   has its own line (RWY SWITCH, above)
                IF NOT ldWhy:STARTSWITH("crew:rwy") { ldSay("downmode: " + ldWhy). }
            }
            SET ldDmShow TO dapDmRec(tg).           // the HUD's / the TAEM windows' OTT message: while RECOMMENDED
            IF tg["dm_rej"]:STARTSWITH("crew") { ldSay("downmode press refused: " + tg["dm_rej"]). }   // its cycle only
            dapDmShow(tg).                          // the downmode buttons' states for the next cycle (lib_dap)
            IF tg["itran"] { ldSay("TAEM phase " + tg["iphase"] + (CHOOSE " (end: " + tg["why_end"] + ")" IF tg:HASKEY("why_end") ELSE "")). }
            // the DAP's AUTO record: the bank (ramped over the cycle), the Nz, the speedbrake (hinge = 2 x a side)
            IF NOT tgLost { ldPubBank(taemg_bank_to_ship(tg["phic_at"]), TG_DTG). }   // Held while SW 02 holds TAEM
            IF NOT tgLost {                         // The Nz and speedbrake commands the DAP flies are held while SW 02 holds TAEM
                SET dGdNz TO tg["nz_total"].
                SET dGdSb TO CHOOSE sb0 IF (TIME:SECONDS - tTaem0 < LD_SB_HOLD_S AND NOT bl["on"]) ELSE tg["dsbc"] / 2.
            }
            SET LD_CWE TO LIST(tg["iphase"], tg["eow"] - tg["en"], TIME:SECONDS).
            IF dispOn { SET tdDue TO TRUE. SET tdSt TO st. }   // the pages: at the next tick (above)
            SET cueNew TO TRUE.
            ldLogRow(st, tg, LEXICON(), LIST(ROUND(ldBank, 2), ROUND(tg["dsbc"], 2), ROUND(cmd, 3),
                     ROUND(tg["alpha_rl"], 3), ROUND(tg["nzl_trim"], 3), ROUND(ldFdLift / TG_GO, 4), tg["nz_sat"],
                     tg["zoom"], tg["dm_msg"], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                     ROUND(ldKey(tg, "alpha_ff"), 3), ROUND(ldKey(tg, "nz_err"), 4), ROUND(ldAoa(), 3), ROUND(SHIP:MASS, 4),
                     CHOOSE 1 IF dCssP ELSE 0, CHOOSE 1 IF dCssR ELSE 0, CHOOSE 1 IF dSbAuto ELSE 0)).
        }
        IF TIME:SECONDS >= tSub {           // the pitch loop, TG_NZL_NSUB updates per guidance cycle
            LOCAL dts IS TG_DTG / TG_NZL_NSUB.
            SET tSub TO tSub + dts.
            SET st TO ldState().
            IF dCssP {                      // CSS pitch: the pitch loop re-seeded on the vehicle (bumpless back to AUTO)
                ldFcSeed(tg, ldAlphaNow(), ldFdLift / TG_GO, st["qbar"], st["mach"]).   // fcs_trim_seed
                SET ldAlpha TO tg["alpha_rl"].
            }
            LOCAL aPrev IS ldAlpha.
            IF bl["on"] AND LD_DITCH { ldDitch(tg, st, bl). }   // the ditch's flare sets the Nz
            // fcs_alpha_cmd, the bailout / ditch ceiling, fcs_alpha_slew at CSS's pitch rate (FCTAEM when LD_AL_CS)
            IF NOT tgLost {                 // The alpha is held while SW 02 holds TAEM
                SET cmd TO ldFcTaem(tg, st, dts, CHOOSE (CHOOSE LD_DITCH_ALPMAX IF bl["dit"] ELSE LD_BAIL_ALPMAX) IF bl["on"] ELSE 1E9).
            }
            SET ldAlpha TO tg["alpha_rl"].          // the slewed command (fcs_alpha_slew's)
            // the DAP flies the mean of the last TG_NZL_NSUB sub-step commands, one guidance cycle. The Nz steps once a
            // cycle (TG_DTG), so the command jumped at one sub-step in four (+0.19 deg at M2.1) and the DAP's 0.24 s ramp
            // kicked the elevator 2.5 deg once a second. The mean over the cycle is that staircase's ramp, 0.36 s later
            // (the elevator's 1 Hz swing 1.19 -> 0.06 deg sd at M2.3; the Nz integrator's loop, ~5 s, is unaffected). In
            // CSS it restarts on the vehicle.
            IF dCssP { ldAcHist:CLEAR(). }
            ldAcHist:ADD(ldAlpha).
            UNTIL ldAcHist:LENGTH <= TG_NZL_NSUB { ldAcHist:REMOVE(0). }
            LOCAL am IS 0.
            FOR x IN ldAcHist { SET am TO am + x. }
            SET am TO am / ldAcHist:LENGTH.
            SET dGdAlphaDot TO (am - dGdAlpha) / dts.
            SET dGdAlpha TO am.
            SET dGdAlphaT TO TIME:SECONDS.          // the DAP ramps to it over dts (DAP_AC_RAMP)
            SET dGdAlphaDt TO dts.
        }
        LOCAL cssUp IS ldCssShown(goCss, dCssP, dCssR, tg["g"]["psha"]).    // GO CSS shown
        IF cssUp <> goCssUp {
            SET goCssUp TO cssUp.
            SET cueNew TO TRUE.             // the HUD record and the status label at once
            ldSay("GO CSS " + (CHOOSE "shown" IF cssUp ELSE "off") + ": "
                  + (CHOOSE "CSS" IF (dCssP OR dCssR) ELSE "AUTO")
                  + ", HAC turn to go " + ROUND(tg["g"]["psha"]) + " deg").
        }
        IF dHud {
            IF hudG {                       // the TAEM HUD symbols: the FD square (the VV in prefinal), the diamond
                IF cueNew {                 // the cycle's values: once a cycle (only the cycle changes them)
                    SET hdgRec["phase"] TO LIST("S-TURN", "ACQ", "HDG", "PRFNL")[tg["iphase"]].
                    SET hdgRec["vv"] TO tg["iphase"] = 3.
                    SET hdFdMode TO NOT hdgRec["vv"].   // no velocity vector before PRFNL, the ladder about the FD square
                    SET hgDiaOff TO FALSE.
                    SET hdgRec["herror"] TO tg["herror"].
                    SET hdgRec["css"] TO CHOOSE "GO CSS" IF goCssUp ELSE "".
                    SET hdgRec["dm"] TO ldDmShow.          // the OTT message: while recommended, gone once taken
                    SET hdgRec["zoom"] TO tg["zoom"].
                }
                // the diamond: the slewed bank the DAP flies in AUTO; in CSS roll the demand (the slew follows the vehicle)
                // ramped over the cycle, the Nz measured every tick (ldRamp, lib_dap dNzM)
                SET hdgRec["bankDem"] TO ldRamp(ldHudBd, CHOOSE tg["phic_dem"] IF dCssR ELSE tg["phic_at"], TG_DTG).
                SET hdgRec["nzc"] TO ldRamp(ldHudNz, tg["nz_total"], TG_DTG).
                SET hdgRec["nzm"] TO dNzM.
            }
            ldHudCues(hudG).
        }
        IF cueNew {
            SET ldLbl:TEXT TO "TAEM " + tg["iphase"] + "  psha " + ROUND(tg["g"]["psha"]) + "  E/W "
                              + ROUND(tg["eow"] - tg["en"]) + " m  " + (CHOOSE "GO CSS  " IF goCssUp ELSE "")
                              + ldMsg.
            SET cueNew TO FALSE.
        }
        WAIT 0.
    }
    IF bl["end"] {                          // the bailout hold ended (as ops6q's BLUE): the DAP holds the last attitude
        ldSay("BAILOUT: the hold ended " + ROUND(ALT:RADAR) + " m above the ground; the DAP holds the attitude (CTRL+C ends it)").
        UNTIL dDone { WAIT 0.1. }
    }
    IF dDone { ldEnd("END: the vehicle is the pilot's (every surface back to the stick)"). RETURN FALSE. }
    // ---- A/L
    SET ldPhase TO "AL".
    IF NOT dBtnBail:ISTYPE("Scalar") { SET dBtnBail:ENABLED TO FALSE. }   // no BAILOUT in A/L
    LOCAL sf IS alg_aim_shift(ldRwy["len"], ldRwy["slope"]).
    SET DAP_BRK_FROM_WOW TO sf > 0.         // a short field: the brakes from the main gear (lib_dap)
    SET LD_VMASS TO AL_VEHICLE_MASS * SHIP:MASS * 1000 / LD_MASS_CAL.   // SHIP:MASS is in tonnes
    LOCAL kdr IS alg_k_dr_srw_sf(ldRwy["name"], ldRwy["slope"], LD_VMASS).   // ldRwy: SW RWY may have changed it
    LOCAL nav IS ldNav(sf, FALSE, 0, ldState()).
    LOCAL ags IS alg_init(nav, tg["phic_at"], LD_VMASS, TRUE, TRUE, sf, kdr, tg["nzc"], ldRwy["len"]).   // TAEM's NZC: the pitch fader
    LOCAL fc IS LEXICON("trim", tg["nzl_trim"], "alpha_rl", tg["alpha_rl"], "bank", tg["phic_at"],
                        "bank_rate", tg["phic_rate"], "nz_sat", 0, "rl_bind", 0, "nz_err", 0).
    // IGS 2, and IGS 1 above the model mass (AL_HEAVY_FF): the alpha table told the mass; TAEM's trim moves by the
    // table's change at the hand-over state, so the alpha command does not step (al_sim ff_k, ff_trim_seed)
    SET LD_FF_K TO CHOOSE LD_VMASS / AL_ORB_MASS IF AL_HEAVY_FF AND (ags["igs"] = 2 OR ags["mass"] > AL_ORB_MASS) ELSE 1.
    IF LD_FF_K <> 1 {
        LOCAL nz0 IS tg["nz_total"].
        SET fc["trim"] TO taemg_midval(fc["trim"] - (ldFcAlphaFf(nz0 * LD_FF_K, nav["qbar"], nav["mach"])
                                       - ldFcAlphaFf(nz0, nav["qbar"], nav["mach"])), -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX).
    }
    ldSay("A/L: aim shift " + ROUND(sf, 1) + " m, K_DR_SRW " + ROUND(ags["k_dr_srw"], 1) + ", guidance mass " + ROUND(LD_VMASS)
          + " kg (vehicle " + ROUND(SHIP:MASS, 4) + " t / calibration " + ROUND(LD_MASS_CAL / 1000, 1) + " t)").
    IF dispOn { tdPagesOff(). }             // the TAEM pages end with TAEM (VERT SIT 2's A/L box has flashed); their
                                            // windows stay as the DAP's button rows to landRun's end (ldEnd: tdClose)
    LOCAL gearDown IS FALSE.
    LOCAL gearT IS -1.                      // GEAR ON's time (the pitch loop's gear lift ramps over AL_GEAR_T_DEPLOY)
    LOCAL geomT IS -1.                      // the gear geometry log is due at this time (ldGearGeom)
    LOCAL dumpT IS -1.                      // the aft dump's outcome log is due at this time (ldDumpSay)
    LOCAL chuteOut IS FALSE.
    LOCAL chuteCut IS FALSE.
    LOCAL chuteT IS -1.                     // the chute probe's next line (1 Hz from the deploy; ldChuteProbe)
    LOCAL chutePost IS 0.                   // its lines since the cut (it stops at 3)
    LOCAL wowT IS -1.
    LOCAL wongT IS -1.
    LOCAL wow IS FALSE.
    LOCAL wong IS FALSE.
    LOCAL braking IS FALSE.
    LOCAL vgPrev IS -1.
    LOCAL tvPrev IS 0.
    LOCAL decel IS 0.
    LOCAL needNow IS -1.                    // the brakes' deceleration target, m/s2 (the HUD's braking cue)
    LOCAL stopped IS FALSE.
    SET ldFdPt TO -1.
    SET tNext TO TIME:SECONDS.
    SET tSub TO TIME:SECONDS.
    LOCAL nzt IS 1.
    SET cueNew TO TRUE.                     // the HUD record's and the label's per-cycle parts (as TAEM's): the first cycle
    IF DEFINED FLFX_PH { SET FLFX_PH TO "A/L". }   // The phase the DAP's SW 02 test reads
    UNTIL dDone OR stopped {
        ldFd(LD_AL_FD_WIN).
        IF ldFdNew AND NOT wow {
            ldFcAlTrim(fc, nzt, ldFdLift / TG_GO, nav["qbar"], LD_AL_FD_WIN).   // fcs_al_trim + rl_bind 0 (FCALTRIM)
        }
        LOCAL gh IS ldGearH().
        SET dGdHm TO gh[1].                     // The DAP's contact mode reads the host's live gear height (the HUD's sHft can be stale)
        IF geomT > 0 AND TIME:SECONDS >= geomT {
            ldGearGeom(CHOOSE "on the mains" IF wow ELSE "in the air").
            SET geomT TO -1.
        }
        ldCgTick().                                 // the dump toward the CG target, then the mono trim
        IF dumpT > 0 AND TIME:SECONDS >= dumpT {
            ldDumpSay(LD_DUMP_LOG_S + " s after the dump's start").
            ldGearGeom((CHOOSE "on the mains" IF wow ELSE "in the air") + ", " + LD_DUMP_LOG_S + " s after the dump's start").
            SET dumpT TO -1.
        }
        // weight on wheels (the guidance's): the main gear, then the nose gear, within LD_WOW_M of the ground for LD_WOW_S
        IF NOT wow {
            IF gh[1] < LD_WOW_M { IF wowT < 0 { SET wowT TO TIME:SECONDS. } } ELSE { SET wowT TO -1. }
            IF wowT >= 0 AND TIME:SECONDS - wowT >= LD_WOW_S {
                SET wow TO TRUE.
                SET cueNew TO TRUE.                 // the HUD record and the label show the touchdown
                SET dGdWow TO TRUE.                 // the DAP's touchdown too: one for the program
                SET ldPhase TO "GROUND".
                ldSay("MAIN GEAR: " + ROUND(nav["eas"] / AL_KT) + " KEAS, theta " + ROUND(ldPitchNow(), 1) + ", sink "
                      + ROUND(-nav["h_dot"] / AL_FT, 1) + " ft/s, x " + ROUND(nav["x"] - sf) + " m").
                SET geomT TO TIME:SECONDS + 1.      // the gear geometry, loaded
                IF ldCgStart("at the main gear") {  // the CG targeter at touchdown (the dump, then the mono)
                    SET dumpT TO TIME:SECONDS + LD_DUMP_LOG_S.
                }
            }
        } ELSE IF NOT wong {
            IF gh[2] < LD_WOW_M { IF wongT < 0 { SET wongT TO TIME:SECONDS. } } ELSE { SET wongT TO -1. }
            IF wongT >= 0 AND TIME:SECONDS - wongT >= LD_WOW_S {
                SET wong TO TRUE.
                SET cueNew TO TRUE.
                SET dGdWong TO TRUE.
                ldSay("NOSE GEAR: " + ROUND(nav["eas"] / AL_KT) + " KEAS").
                IF ldMpSt > 0 {                     // the mono trim ends with the nose gear
                    IF ldMpSt = 2 { LOCAL ngX IS ldMpX["x"]. IF ngX:STATUS = "Transferring" { SET ngX:ACTIVE TO FALSE. } }
                    SET ldMpSt TO 0.
                    ldMpSay("stopped at the nose gear", ldGearF()).
                }
            }
        }
        // SW 02 GUIDANCE LOST (A/L): the last COMMAND is held (no bank, alpha, Nz or speedbrake update, no automatic gear / chute). The step itself still runs, so
        // the cues (flare triangles, OGS), the altitude error and the mode word keep their live values (lib_hudg blanks only the diamond and the decel cue)
        LOCAL alLost IS FALSE.
        IF DEFINED FLFX_SWPROG { SET alLost TO flfxSwGuid("A/L"). }
        IF TIME:SECONDS >= tNext {
            SET tNext TO tNext + AL_DT.
            SET st TO ldState().
            SET nav TO ldNav(sf, wow, gh[0], st).   // the cycle's one state, passed in
            // CSS roll first (the bank slew follows the vehicle; alg_cycle reads no fc key), then the cycle: alg_cycle,
            // the bank slewed (G4.9 sign), the Nz (ldAlStep: ALSTEP when LD_AL_CS)
            IF dCssR AND NOT wow {
                SET fc["bank"] TO taemg_ship_to_bank(dapBank()).
                SET fc["bank_rate"] TO 0.
            }
            LOCAL nzs IS ldAlStep(ags, nav, fc).    // runs under SW 02 too (the cues are its products); the commands are held below
            IF NOT alLost { SET nzt TO nzs. }
            SET cueNew TO TRUE.
            // the bank -> the DAP (wings level on the ground: its load balance)
            IF NOT alLost { ldPubBank(CHOOSE 0 IF wow ELSE taemg_bank_to_ship(fc["bank"]), AL_DT). }   // Held while SW 02 holds A/L
            LOCAL sbc IS MIN(ags["dsbc_al"], CHOOSE LD_SB_GROUND_MAX IF wow ELSE AL_SB_MAX).
            IF NOT alLost { SET dGdSb TO sbc / 2. }   // Held while SW 02 holds A/L
            IF ags["rco_lg_deploy"] AND NOT gearDown AND NOT alLost {
                GEAR ON. SET gearDown TO TRUE. SET gearT TO TIME:SECONDS. ldSay("gear down at " + ROUND(nav["h"] / AL_FT) + " ft").
                SET geomT TO TIME:SECONDS + 10.     // the gear geometry once the gear is down and locked
            }
            IF ags["rco_dc_deploy"] AND NOT chuteOut AND NOT alLost { ldChute("deploy chute"). SET chuteOut TO TRUE. SET chuteT TO TIME:SECONDS. }
            IF chuteT >= 0 AND TIME:SECONDS >= chuteT AND chutePost < 3 {
                ldChuteProbe().
                SET chuteT TO chuteT + 1.
                IF chuteCut { SET chutePost TO chutePost + 1. }
            }
            SET dGdNz TO nzt.                       // (ldAlStep's alg_nz_total, above)
            IF wow {
                // the ground: the derotation rate to the DAP (hold, then AL_DEROT_RATE at 185 KEAS), the brakes, the chute
                SET dGdDerot TO CHOOSE 0 IF wong ELSE alg_derot_rate(nav["eas"], sf > 0).
                LOCAL vg IS st["vh"].
                IF vgPrev >= 0 AND TIME:SECONDS > tvPrev { SET decel TO (vgPrev - vg) / (TIME:SECONDS - tvPrev). }
                SET vgPrev TO vg. SET tvPrev TO TIME:SECONDS.
                LOCAL need IS alg_brake_need(vg, st["x"], ldRwy["len"], wong, sf > 0).
                SET needNow TO need.
                // BRAKES: before WONG the DAP's (2.5 +- 2.5 %); after, the pilot's B -- a deviation, while ROLLOUT is AUTO: on to the
                // stop (LD_BRAKE_FULL), else toggled to alg_brake_need
                IF dYb = 2 AND dClReq {
                    LOCAL want IS LD_BRAKE_FULL OR (need >= 0 AND (need >= 99 OR decel < need + (CHOOSE LD_BRAKE_HYST IF braking ELSE -LD_BRAKE_HYST))).
                    IF want <> braking { SET braking TO want. IF braking { BRAKES ON. } ELSE { BRAKES OFF. } }
                }
                IF chuteOut AND NOT chuteCut AND alg_chute_jettison(vg) { ldChute("cut parachute"). SET chuteCut TO TRUE. }   // the EVENT's name ("Cut Chute" is the action group's)
                IF chuteOut AND NOT chuteCut AND dChuteCutReq {    // the DAP's chute guard (lib_dap CHUTE_GUARD_*)
                    ldSay("chute: the DAP's guard -- the nose rose on the mains against full nose-down elevator").
                    ldChute("cut parachute"). SET chuteCut TO TRUE.
                }
                IF vg < LD_STOP_VG { SET stopped TO TRUE. }
            }
            ldLogRow(st, tg, ags, LIST(ROUND(ldBank, 2), ROUND(sbc, 2), ROUND(ldAlpha, 3), ROUND(fc["alpha_rl"], 3),
                     ROUND(fc["trim"], 3), ROUND(ldFdLift / TG_GO, 4), fc["nz_sat"], 0, "", ags["p_mode"], ags["f_mode"],
                     ags["sb_mode"], ROUND(nav["h"], 2), ROUND(nav["h_dot"], 3), ROUND(ags["nzc"], 4), ROUND(ags["phic_al"], 2),
                     ROUND(ags["dsbc_al"], 2), CHOOSE 1 IF wow ELSE 0, CHOOSE 1 IF wong ELSE 0, ROUND(ldPitchNow(), 2),
                     ROUND(dClDpsi, 2), CHOOSE 1 IF braking ELSE 0, ROUND(decel, 3),
                     ROUND(ldKey(fc, "alpha_ff"), 3), ROUND(ldKey(fc, "nz_err"), 4), ROUND(ldAoa(), 3), ROUND(SHIP:MASS, 4),
                     CHOOSE 1 IF dCssP ELSE 0, CHOOSE 1 IF dCssR ELSE 0, CHOOSE 1 IF dSbAuto ELSE 0)).
        }
        IF NOT wow AND TIME:SECONDS >= tSub {   // the pitch loop, AL_NSUB updates per A/L cycle
            LOCAL dts IS AL_DT / AL_NSUB.
            SET tSub TO tSub + dts.
            IF dCssP {                          // CSS pitch: the A/L pitch loop re-seeded on the vehicle
                LOCAL an IS ldAlphaNow().
                SET fc["trim"] TO taemg_midval(an - ldFcAlphaFf(ldFdLift / TG_GO * LD_FF_K, nav["qbar"], nav["mach"]),
                                               -TG_NZL_TRIM_MAX, TG_NZL_TRIM_MAX).
                SET fc["alpha_rl"] TO an.
                SET ldAlpha TO an.
            }
            LOCAL aPrev IS ldAlpha.
            // the tail's clearance: alpha at most AL_THETA_TD_MAX - gamma
            LOCAL amx IS CHOOSE AL_THETA_TD_MAX - nav["gamma"] IF AL_THETA_TD_MAX > 0 ELSE 999.
            // the alpha table knows the gear-down lift (al_sim FCS_GEAR_LK; without it the orbiter balloons)
            LOCAL gf IS CHOOSE MIN((TIME:SECONDS - gearT) / AL_GEAR_T_DEPLOY, 1) IF gearT >= 0 ELSE 0.
            IF NOT alLost {                 // The alpha is held while SW 02 holds A/L
                SET ldAlpha TO ldFcAlAlpha(fc, nzt * LD_FF_K / (1 + AL_FCS_GEAR_LK * gf), nav["qbar"], nav["mach"], dts, amx).
            }
            SET dGdAlpha TO ldAlpha.
            SET dGdAlphaDot TO (ldAlpha - aPrev) / dts.
            SET dGdAlphaT TO TIME:SECONDS.
            SET dGdAlphaDt TO dts.
        }
        IF dHud {
            IF hudG {                       // the A/L HUD symbols: the VV + diamond, the preflare triangles, the OGS cue
                IF cueNew {                 // the cycle's values (and the touchdown's), once, as TAEM's
                    SET hdgRec["phase"] TO CHOOSE "" IF wow ELSE alg_mode_text(ags).
                    SET hdgRec["vv"] TO TRUE.
                    SET hdFdMode TO FALSE.
                    SET hdgRec["herror"] TO ags["h_error"].
                    SET hdgRec["dm"] TO "".
                    SET hdgRec["zoom"] TO FALSE.
                    LOCAL tri IS alg_tri_gam(ags, nav, NOT wow).
                    SET hdgRec["flare"] TO tri.
                    SET hdgRec["ogs"] TO alg_ogs_cue_gam(ags, NOT wow, tri).    // (its merge latch: at the same call)
                    SET hdgRec["decelTgt"] TO CHOOSE needNow IF wong ELSE -1.
                    SET hdgRec["decelAct"] TO decel.
                }
                SET hdgRec["bankDem"] TO ldRamp(ldHudBd, ags["phic_al"], AL_DT).     // as TAEM's
                SET hdgRec["nzc"] TO ldRamp(ldHudNz, nzt, AL_DT).
                SET hdgRec["nzm"] TO dNzM.
                // the tail's clearance: PITCH flashes (the GO CSS slot) near the ground with the pitch at the cap
                SET hdgRec["css"] TO CHOOSE "PITCH" IF NOT wow AND nav["h"] < LD_THETA_WARN_FT * AL_FT
                    AND ldPitchNow() > AL_THETA_TD_MAX - LD_THETA_WARN_DEG ELSE "".
            }
            ldHudCues(hudG).
        }
        IF cueNew {
            SET ldLbl:TEXT TO "A/L " + alg_mode_text(ags) + "  h " + ROUND(nav["h"] / AL_FT) + " ft  " + ROUND(nav["eas"] / AL_KT)
                              + " KEAS" + (CHOOSE "  ROLLOUT" IF wow ELSE "").
            SET cueNew TO FALSE.
        }
        WAIT 0.
    }
    IF dReqEnd { ldEnd("END: the vehicle is the pilot's (every surface back to the stick)"). RETURN FALSE. }
    BRAKES ON.
    ldSay("WHEELS STOP at x " + ROUND(ldState()["x"]) + " m (" + ROUND(ldRwy["len"] - ldState()["x"]) + " m of runway left)").
    ldEnd("landRun done").
    RETURN TRUE.
}

FUNCTION ldNav {                            // -> the A/L nav (the guidance frame: x + sf), on the state st
    PARAMETER sf, wow, hgear, st.
    LOCAL x IS st["x"].
    LOCAL plane IS alg_rwy_plane(x, ldRwy["elev"], ldRwy["far_elev"], ldRwy["len"]).
    LOCAL h IS hgear - plane.
    IF hgear = 0 { SET h TO ldGearH()[0] - plane. }
    LOCAL hdot IS st["hdot"] - alg_rwy_plane_slope(x, ldRwy["elev"], ldRwy["far_elev"], ldRwy["len"]) * st["xdot"].
    LOCAL rho IS st["rho"].
    RETURN LEXICON("x", x + sf, "y", st["y"], "h", h, "h_dot", hdot, "v_g", st["vh"], "v_i", st["surfv"],
                   "gamma", -st["gam"], "psi_gnd", st["psd"], "y_dot", st["ydot"], "tas", st["surfv"],
                   "eas", st["surfv"] * SQRT(MAX(rho, 0) / AL_RHO0), "qbar", st["qbar"], "mach", st["mach"],
                   "theta", ldPitchNow(), "wowlon", wow, "flatturn", wow).
}

