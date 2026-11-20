@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_DAP.KS  --  the orbiter's DAP (CSS, and AUTO from the guidance) as a library.
// ============================================================================
//  Loaded by landRun (lib_land.ks) and by the stand-alone css_dap.ks: both fly this DAP.
//  Writes 0:/logs/css_dap_<t>.csv (a row every D_LOG_EVERY physics ticks: 25 Hz) and .txt (the setup).
//  API (the host calls, in this order):
//      RUNONCEPATH("0:/lib/lib_hud.ks"). RUNONCEPATH("0:/lib/lib_dap.ks").
//      dapInit().                the gimbal (the stick), the surfaces, the brakes, the log; every surface deployed
//      dapGuiBuild(title).       the window: PITCH, ROLL/YAW (click-to-toggle AUTO / CSS), END, ROLLOUT, HUD CAM
//                                (+ SPDBK and the downmode row OTT STRT / OTT MEP / SW RWY with the guidance,
//                                DAP_AUTO_GUID)
//      dapDmShow(tg).            the downmode row's states after each guidance cycle (lib_land)
//      dapDmRec(tg).             the OTT message to show: the downmodes recommended now (lib_land's ldDmShow)
//                                (no OTT MEP while VERT SIT's MEP mark and the energy both lie above the low-energy
//                                tick: dapDmMepRec)
//      dapHudInit().             lib_hud's hdInit (the HUD CAM button is enabled once it has loaded)
//      dapBegin().               the axes' locks, the csv header
//      WHEN TRUE THEN { IF NOT dDone { dapTick(). } RETURN NOT dDone. }     one DAP tick per physics tick
//      UNTIL dDone { dapHudTick(). WAIT 0. }                                the HUD (<= 25 Hz real) + the host's work
//      dapStop().                every axis back to the stick, the brakes' sliders back, the log flushed
//  TWO COMMAND SOURCES FOR AUTO:
//   DAP_AUTO_GUID FALSE (css_dap.ks): AUTO = the surfaces unlocked, flown by the stick directly.
//   DAP_AUTO_GUID TRUE (landRun): the DAP flies both modes and every surface stays locked (the rudder is the stick's only
//   in a CSS rollout), because kOS's cooked steering does not handle the speedbrake well; the stick only turns the
//   capsule's reaction wheel, as in CSS. AUTO takes the record the guidance host writes (dGd*):
//   PITCH  qc = KA_ALPHA (alpha_c - alpha) + alpha_c' + the flight path's pitch rotation (the velocity's turn toward the
//          body top, measured and filtered with PATH_TAU; with DAP_QPATH_MEAS FALSE, from the commanded Nz). alpha_c is
//          ramped over each publication interval (DAP_AC_RAMP, as the bank). Then the same PI rate loop, speedbrake
//          crossfeed and flap auto-trim. A deviation: the orbiter's AUTO pitch closes on Nz (the Nz error gives the pitch
//          rate); this one closes on the alpha command, because the pitch loop (fcs_pitch) turns the Nz command into alpha.
//   ROLL   pc = KA_PHI (bank_c - bank) + bank_c' (the guidance's bank, ramped over its cycle), then the same
//          stability-axis roll loop. YAW: the same rudder law (no sideslip asked).
//   LIMITS both rate commands are held to CSS's full-stick rates for the Mach; the aileron keeps AIL_ROOM_MIN whatever
//          the elevator needs.
//   SPEEDBRAKE  SPDBK AUTO (the guidance's) or CSS (the lever; AG3 toggles it; an AG3 press in AUTO takes it to CSS).
//   GROUND the same ground mode; the derotation follows the guidance's rate (alg_derot_rate: 2.0 deg/s below 185 KEAS,
//          5 at once on the short field), ramped at DR_ACC_AUTO; ROLLOUT AUTO on the landing runway (dGdRwyThr / dGdRwyFar).
//  AG9 / ABORT (unlock all) cannot take the surfaces in the guidance mode: the DAP locks them again (END does).
//  THE DAP ITSELF: the orbiter's Control Stick Steering, Mach 2.5 to landing. The controls are locked; kOS reads the
//  stick off the OMS gimbal and commands the surfaces' deploy angles: stick input -> rate -> deflection, on the
//  orbiter's Mach schedules. The laws are the orbiter's CSS (FSSR STS 83-0007-34 OI-34 Part C, the USA DAP workbook);
//  the gains are this vehicle's, identified in flight tests.
//  PER AXIS, EVERY PHYSICS TICK (50 Hz; the orbiter's DAP ran its rate loops at 25 Hz):
//   PITCH  stick -> RHC deg (gimbal 1.0 = the 19.5 deg soft stop) - 1.15 deadband -> (0.36 + 0.0484|x|)x, cap 23
//          -> x GPRHC (0.125 (deg/s)/deg at M >= 2.0 .. 0.40 at M <= 1.2) = the pitch-rate command, + the r tan(phi)
//          turn term (the nose follows a level turn); PI on the rate error: elevator = GDQ (e + trim), the trim
//          integrating GTRE (1.5 below M3) x GDQ x e, so a centred stick HOLDS THE PITCH ATTITUDE. GDQ = KPIT(M) / sqrt(q).
//   ROLL   stick -> RHC deg - 1.25 -> (KDAMLIN + KDAMPAR|x|)x, cap DAMAX -> x GRRHC (all on Mach: 6 deg/s at full stick
//          at M >= 1.5 .. 27 at M <= 0.6); the rate error about the stability axis (the command x cos alpha, the
//          steady-turn roll rate removed) -> aileron = GDA x error (P only below M1.25; a slow aileron trim above).
//          GDA = KGDA(M) / q. The orbiter's 0.1 s stick prefilter is the OMS gimbal's own lag (response speed 10).
//   YAW    IN FLIGHT: automatic, as on the orbiter. The rudder (by deploy angle; its stick input is locked in CSS
//          roll/yaw) coordinates the turn (the roll command x sin alpha + the steady-turn yaw rate: GDRC = KDRC / q on
//          the yaw-rate error) and holds the sideslip the yaw stick asks (KBETA; PED_BETA at full stick: the orbiter's
//          pedals bias Ny), below RUD_MACH. The yaw stick also turns the capsule's reaction wheel directly (the DAP
//          cannot command it).
//          The rudder's sign depends on the brake. SHUT (<= 5 a side): the halves move opposite (RUD_SIGN -1). Above
//          that the scheme depends on RUD_CURVE_PATCH (the rudder section below).
//          ON THE GROUND (from main-gear contact): NO ROLL STICK (the slapdown contaminates it). The ailerons run the
//          orbiter's load balance instead (wings level on the mains, faded out over 100 s from WONG), the rudder law is
//          off (the rudder is the yaw stick's again), and the yaw stick brakes the mains differentially. Before WONG the
//          DAP owns the brakes (the mains at 2.5 +- 2.5 %, the nose gear at 0 so it lands unbraked); from WONG the brakes are
//          yours (B) and the main away from the yaw is lowered from its slider by up to 5 % (CSS: 2 x YB_SPAN / BRK_TORQUE_K;
//          AUTO's centreline up to 10 %: YB_AUTO_SPAN / BRK_TORQUE_K), never above 95 % (the brakes
//          lock at 100 %). The slider moves in 5 % steps (kOS snaps SETFIELD to them), so the values between are pulsed.
//   MIXING elevator +/- aileron on the four elevons by DEPLOY ANGLE (+ = trailing edge down; ELV_DIF + = LEFT roll);
//          the aileron keeps AIL_ROOM_MIN (the elevator gives it up; beyond that the pitch has priority); the body flap
//          auto-trims (slowly) to take the steady elevator off the elevons.
//   SPEEDBRAKE  AG3 (the rudder halves' deploy), but the DAP owns the halves: every AG3 press flips the brake between
//          shut and open (SB_OPEN a side), moved at SB_RATE, and fed forward to the elevator (SBX_TAB: the orbiter's
//          speedbrake -> elevator crossfeed) so the brake's pitch moment does not kick the nose.
//          SPDBK CSS with the lever ARMED (kOS has seen the throttle lever move, or MAN with a live AFBW lever):
//          the lever is the brake, 0 % = open
//          RUD_HALF_LIM a side (98.6 hinge), 100 % = shut, capped above SB_SUPER_MACH at SB_SUPER_MAX as AUTO is; AG3
//          then only hands the brake over.
//  MODES (a small window): PITCH and ROLL/YAW, each click-to-toggle AUTO / CSS (the orbiter's two pushbuttons). In
//  the stand-alone css_dap AUTO = the surfaces unlocked, flown by the stick directly (as without the DAP); CSS = that
//  axis locked on every surface (the 'pitch' / 'roll' (/'yaw') fields) and flown by the DAP. END stops the DAP. AG9
//  (unlock all; also ABORT) = BOTH AXES TO AUTO; AG10 (lock all) = BOTH TO CSS: the DAP follows the action groups
//  instead of fighting them.
//  THE HUD: lib_hud.ks draws the orbiter's HUD over the view (the velocity vector, the pitch ladder, the runway outline and
//  aim circles, KEAS, the main gear's altitude, the speedbrake, CSS / AUTO). It needs the screen's set (lib_screen.ks);
//  without it the DAP runs alone. HUD CAM snaps the camera to the flight deck (the conformal symbols need it; click again
//  to release). The runway is landRun's landing runway, or stand-alone the nearest one facing your track; AG4 toggles the
//  overlay. The DAP runs in a per-tick trigger and the HUD in the main loop at <= 25 Hz of real time (one kOS CPU for
//  both). The map view hides the HUD.
//  ROLLOUT AUTO: from main-gear contact to wheels stop the DAP steers to the HUD runway's centreline (the line through
//  its two ends), as the orbiter's AUTO roll/yaw rollout does (it steered the nosewheel; this one uses the mains'
//  differential braking and the rudder). The offset y -> a heading command (CL_KY deg per m, <= CL_PSI_MAX); the heading
//  error and the yaw rate -> the brake differential (PD: CL_KP, CL_KD; before WONG within 2.5 +- 2.5 %, after WONG the far
//  main lowered up to YB_AUTO_SPAN from <= 95 %) and the rudder (its stick input locked). ROLLOUT button: AUTO / CSS
//  (the yaw stick's differential braking); the yaw stick past CL_HOT for CL_HOT_T s takes it (CSS): the hot stick.
//  The brakes' yaw power is an estimate: the loop is stable for 1/3 to 3 times it.
//  DEROTATION AUTO, like the real orbiter's: triggered, then automatic. On the mains before WONG, a nose-down stick
//  past DR_TRIG (33 %) starts the orbiter's beep-trim derotation: a nose-down rate command ramped at DR_ACC to DR_RATE
//  (0.6 deg/s2 to 1.5 deg/s: FPH-ALR 4.11). Once running it ignores the stick (no nose-up cancel, no stick added to
//  it; the orbiter's RHC would add); WONG ends it (the load relief). The capsule's reaction wheel still answers the stick.
//  In the guided DAP (DAP_AUTO_GUID) the ROLLOUT button governs it, whatever PITCH is: ROLLOUT AUTO starts it when the
//  guidance asks a rate (dGdDerot > 0: 185 KEAS, the short field at once), ROLLOUT CSS when the crew's nose-down stick
//  passes DR_TRIG (semi-auto); either way it flies the guidance's rate (DR_RATE_SEMI until the guidance asks one) at
//  DR_ACC_AUTO, the pitch axis handed to it. The HUD's control text adds PUSH (ROLLOUT CSS, the guidance's rate due, no push yet); no DEROT text.
//  STAND-ALONE USE (css_dap.ks): start at Mach 2.5 or below, with the flight script not running (its trim loops write
//  the same deploy angles). SAS OFF (the DAP switches it off in CSS: the gimbal must read the stick alone), KSP pitch
//  trim at zero once in CSS (Alt+X: trim reads as stick), RCS as you like. RUNPATH("0:/css_dap.ks"). Click PITCH (the
//  DAP takes over whatever the stick and KSP trim were deflecting, bumpless), then Alt+X, then ROLL/YAW. The CSS gearing
//  wants BIGGER stick movements than flying the surfaces directly (roll inputs of a few % of the stick sit inside CSS's
//  deadband): subsonic, 30 % stick = 1.1 deg/s pitch / 2.5 roll, 50 % = 2.7 / 6.8, full = 9.2 / 26.5.
//  If anything feels wrong, click it back to AUTO (or AG9).
//  SIGNS: + gimbal pitch = nose up, + gimbal roll = a RIGHT roll.
// ============================================================================

RUNONCEPATH("0:/lib/lib_hud.ks").
RUNONCEPATH("0:/lib/lib_guistyle.ks").         // the window's look (dapGuiBuild)
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/taemg_const.ksm" IF O6_KSM_GO ELSE "0:/lib/taemg_const.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/taemg_const.ks").          // the CSS gearing (TG_CSS_*; the guidance's limits too)
RUNONCEPATH("0:/lib/lib_far.ks").             // FAR's control surfaces when FAR is installed (SURF_MN, surfSetAng)
RUNONCEPATH("0:/lib/lib_logsw.ks").            // SOCK_LOG: the logs on or off (css_dap_<t>.csv / .txt)

// ---------------------------------------------------------------- the stick (the orbiter's RHC, K-loads)
// The CSS gearing is TG_CSS_* (taemg_const.ks). The guidance's rate limits (taemg_roll_lim / taemg_alpha_rate) use
// the same numbers.
GLOBAL RHC_FULL IS TG_CSS_RHC_FULL.    // RHC deg at gimbal 1.0 (the soft stop): 19.5
GLOBAL P_DB IS TG_CSS_P_DB.            // pitch deadband, deg: 1.15
GLOBAL KDEMLIN IS TG_CSS_KDEMLIN.      // pitch shaping, linear (TM-81349): 0.36
GLOBAL PKQ IS TG_CSS_PKQ.              // pitch shaping, quadratic (FSSR XKQO): 0.0484
GLOBAL DEMAX IS TG_CSS_DEMAX.          // shaped cap (inferred: 2.88 / 9.2 deg/s at the soft stop): 23
GLOBAL R_DB IS TG_CSS_R_DB.            // roll deadband, deg: 1.25
GLOBAL CSS_RMAX IS 12.                 // CSS's roll at full stick at least this, deg/s (cssRx; AUTO keeps shapeR)
GLOBAL STICK_P_SIGN IS 1.      // + gimbal pitch = a nose-UP command
GLOBAL STICK_R_SIGN IS -1.     // + gimbal roll = a RIGHT roll = p < 0 in the kOS frame

// ---------------------------------------------------------------- the keyboard mode
// KSP's flight keys set the stick to exactly -1 / 0 / +1 at once (FlightInputHandler.Update; Caps Lock's fine mode
// ramps instead). A full-throw step on an axis (0 to 1 in one tick) marks the keyboard: from then a held key BUILDS the
// input from KB_MIN (half stick) to KB_FULL (full stick) over KB_RISE s, a tap is a KB_MIN pulse of at
// least KB_TAP s, and the release drops it to 0 at once (the detent: the DAP holds the attitude).
// Values between the stops for KB_STICK_T s (a real stick, the fine mode, KSP trim) hand the axis back to the raw input.
// Not the orbiter's (its RHC is a stick; the keyboard has no counterpart).
GLOBAL KB_MODE IS 1.           // 0 off, 1 detected per axis, 2 always on
GLOBAL KB_FULL IS 1.0.         // a held key's input at the end of the build: full stick, 19.5 deg RHC
GLOBAL KB_RISE IS 0.5.         // s: KB_MIN -> KB_FULL
GLOBAL KB_MIN IS 0.5.          // a press's (and a tap's) first input: half stick, 9.75 deg RHC
GLOBAL KB_TAP IS 0.25.         // s: a tap's shortest pulse
GLOBAL KB_STEPS IS 1.          // full-throw steps that mark the keyboard (one: the first press is already shaped)
GLOBAL KB_STICK_T IS 0.5.      // s of in-between values that mark a stick
GLOBAL KB_AXN IS LIST("PITCH", "ROLL", "YAW").
// per axis (pitch, roll, yaw): on, the output, the last raw input, the last time, the steps, the in-between s,
// the press's start, the press's sign
GLOBAL dKb IS LIST(LIST(FALSE, 0, 0, 0, 0, 0, 0, 0), LIST(FALSE, 0, 0, 0, 0, 0, 0, 0), LIST(FALSE, 0, 0, 0, 0, 0, 0, 0)).

// ---------------------------------------------------------------- the loops
GLOBAL LOOP_P IS 5.            // 1/s: pitch loop gain GDQ x |Md| at Q_REF (x sqrt(q / Q_REF) elsewhere)
GLOBAL LOOP_R IS 10.           // 1/s: roll loop gain GDA x Ld at every q
GLOBAL Q_REF IS 15.            // kPa
GLOBAL QB_MIN IS 4.            // kPa: the gain-scheduling floor (the orbiter's QBLIM; rollout)
GLOBAL GTRA IS 0.1.            // 1/s: the CSS aileron trim above M1.25 (held below, FSSR TGTRA_CSS)
GLOBAL QTURN_TAU IS 1.         // s: the turn-term filter
// |Md| / q, nose-up deg/s2 per deg of elevator per kPa (ELV_SYM, identified in flight tests)
GLOBAL MD_TAB IS LIST(LIST(0.3, 0.145), LIST(0.9, 0.147), LIST(1.2, 0.150), LIST(1.6, 0.122), LIST(2.0, 0.099),
    LIST(2.7, 0.073), LIST(3.5, 0.055), LIST(4.0, 0.055)).
// Ld / q, roll deg/s2 per deg of aileron per kPa (ELV_DIF, identified in flight tests)
GLOBAL LD_TAB IS LIST(LIST(0.3, 1.30), LIST(0.5, 1.52), LIST(1.0, 1.70), LIST(1.5, 1.54), LIST(1.9, 1.28),
    LIST(2.5, 1.01), LIST(3.3, 0.745), LIST(4.0, 0.73)).
// the speedbrake -> elevator crossfeed: elevator deg TED per deg of brake a side (opening the brake is NOSE UP), by Mach;
// measured over the brake's whole travel (the orbiter's is 0.06 below M4). Small moves near full open want more (the
// local slope is steeper); the pitch integrator takes the rest. Held beyond the ends.
GLOBAL SBX_TAB IS LIST(LIST(0.3, 0.30), LIST(0.78, 0.135), LIST(1.19, 0.07), LIST(3.2, 0.14)).

// ---------------------------------------------------------------- the rudder (the in-flight yaw)
GLOBAL RUD_ON IS TRUE.         // the DAP flies the rudder in flight
GLOBAL RUD_MACH IS 2.5.        // the rudder flies below this Mach (the gain tables are held beyond their M0.75 end)
GLOBAL RUD_MACH_FAR IS 5.      // under FAR from Mach 5, as the real orbiter's rudder (without it the orbiter departed in yaw at
                               // Mach 2.9 with the rudder off and RCS off: no yaw control above 2.5)
IF FAR_ON { SET RUD_MACH TO RUD_MACH_FAR. }
// THE YAW JETS: the real orbiter flies its yaw jets down to Mach 1, and so does this DAP: from its start to YJ_MACH 1.0,
// with the rudder below RUD_MACH 2.5 (FAR: 5). Under FAR they are essential: at TAEM's Mach 2.5 the orbiter is
// directionally unstable (N_beta -3.5 deg/s2 per deg of sideslip) and FAR's rudder barely yaws it (0.034 deg/s2 per deg,
// while it rolls it 1.1). kOS's raw control does not reach the vessel, so the addon adds the command to the vessel's
// yaw (ADDONS:KALS:YAWJET) with the RCS parts on yaw only. YJ_KA is 0.1 in stock, 0 under FAR; the high-alpha roll
// guard is off (AG_LOC_TAB 99 / AG_KJ 0).
GLOBAL YJ_ON IS FALSE.
IF ADDONS:HASSUFFIX("KALS") {
    // and the trim the addon adds, read off the OMS gimbal (YAWJETGMB; an older KalsCoproc.dll: no jets, rather than an
    // error)
    IF ADDONS:KALS:AVAILABLE { IF ADDONS:KALS:HASSUFFIX("YAWJET") AND ADDONS:KALS:HASSUFFIX("YAWJETGMB") {
        SET YJ_ON TO TRUE. } }
}
GLOBAL YJ_MACH IS 1.0.         // the yaw jets fly above this Mach (the orbiter's)
// Below Mach 1 the jets stop and the rudder flies the yaw alone (the orbiter's). Under FAR near Mach 1 the fin yaws
// 0.05-0.06 deg/s2 per deg per kPa the DAP's way and rolls 0.55-1.06 x that the other way, and FAR's aileron yaw is
// small and proverse. At Mach 0.9 the rudder alone, its yaw from the measured roll, holds every case with the fin's
// roll / yaw <= 3, its yaw 0.05-1.0 deg/s2 per deg at 9.5 kPa and the aileron's yaw 0 .. +0.56, at a 1 and a 3 tick
// delay.
GLOBAL YJ_MACH_FAR IS 1.0.
IF FAR_ON { SET YJ_MACH TO YJ_MACH_FAR. }
GLOBAL YJ_RUD_MACH IS 0.       // under FAR, below this Mach the jets fly the yaw alone (the rudder law off); 0 = never
GLOBAL YJ_KR IS 1.0.           // the jets' command (-1..1) per deg/s of yaw-rate error
GLOBAL YJ_KB IS 2.0.           // ...and per deg of sideslip (N_beta -3.5 deg/s2 per deg needs more than 3.5 / the jets' ~5.5)
GLOBAL YJ_KA IS 0.1.           // ...and per deg of aileron: its adverse yaw (-0.56 deg/s2 per deg) / the jets' ~5.5 deg/s2
// Under FAR the aileron's own yaw is small and the other way (+ = LEFT roll gives nose RIGHT, +0.05 .. +0.25 deg/s2 per
// deg at Mach 1.1-3 with SockFarTrim's elevon fix v2; the feed-forward that cancels it is -0.01 .. -0.05): stock's
// +0.1 would add 0.55 deg/s2 per deg of adverse yaw. 0 under FAR.
IF FAR_ON { SET YJ_KA TO 0. }
// THE HIGH-ALPHA ROLL GUARD (FAR only, off by default): while the jets fly, the aileron is held to
// +-MAX(0, AG_LOC - alpha - elevator): the down-going elevon's local angle of attack (alpha + its deflection, TED +)
// does not pass AG_LOC_TAB(Mach), where FAR's supersonic elevon (a diamond airfoil: its lower shock detaches) stops
// rolling the orbiter. At M2.2 one side's elevons roll it -8 .. -14 kN m per deg up to a local 22 deg, ~0 (then the
// wrong way) past 24, while their adverse yaw stays +3.6 .. +5. The roll the guard holds off the aileron goes to the
// yaw jets (AG_KJ per deg; a LEFT roll = nose LEFT: at high alpha a yaw about the body z is a roll about the velocity).
// SockFarTrim's elevon fix v2 (far_trim.cfg ELEVON_FIX version 2) gives the elevons a smooth, monotonic lift with no
// plateau at any Mach, so with it the guard only holds aileron the elevons have: the table is 99 (off), as in stock.
// WITHOUT v2 installed (no ELEVON_FIX version 2 in far_trim.cfg, or elevonFix false) put this table back:
//     LIST(LIST(1.5, 99), LIST(1.6, 13), LIST(2.0, 21), LIST(2.5, 27.5), LIST(3.2, 35), LIST(3.5, 99)), AG_KJ 0.5.
// (99 = off: below Mach 1.5, and above Mach 3.5 where entry alpha would hold the aileron through the whole entry.)
GLOBAL AG_LOC_TAB IS LIST(LIST(0, 99)).
GLOBAL AG_KJ IS 0.
IF FAR_ON {
    SET AG_LOC_TAB TO LIST(LIST(0, 99)).                  // off (the table above is for no v2)
    SET AG_KJ TO 0.5.
}
// Under FAR the roll-rate command has CSS's own limit (shapeR), as in stock.
GLOBAL RUD_SIGN IS -1.         // RUD_OPP (half 0 +, half 1 -) = a nose-LEFT rudder WITH THE BRAKE SHUT: +1 diverges in yaw
                               // (with the brake open the sign flips back: the halves are past their lift peak)
// The gains: the probe's design (KDRC = 3 /s / (Nd/q) = 263 / 472, KBETA = N_beta / Nd = 5.26 / 9.45) x 0.25, then KDRC
// x0.75 below Mach 1.1 and x0.5 above it, KBETA x1.5, so the yaw loop does not fight the speedbrake angle. At x0.25 the
// loop stays damped for a rudder 1-12x the probe's; at x1 it cycles from ~5x.
GLOBAL KDRC_TAB IS LIST(LIST(0.45, 49.3), LIST(0.75, 88.6), LIST(0.9, 88.6), LIST(1.1, 59.05)).   // GDRC = KDRC / q: rudder
                               // deg per deg/s of yaw rate
GLOBAL KBETA_TAB IS LIST(LIST(0.45, 1.97), LIST(0.75, 3.54)).   // rudder deg per deg of sideslip, NOT / q: the rudder's
                               // power grows with q like the weathercock it adds to (the probe)
GLOBAL PED_BETA IS 2.          // deg of sideslip the yaw stick asks at full deflection in flight (the orbiter's pedals
                               // bias Ny; ~ what the capsule torque alone holds at 10 kPa, so the loop does not fight it)

// ---------------------------------------------------------------- the surfaces (OV_*.cfg: ctrlSurfaceRange)
GLOBAL ELV_LIM IS 25.          // each elevon
GLOBAL AIL_LIM IS 10.          // the aileron component (the orbiter's DAC_LIM)
GLOBAL AIL_ROOM_MIN IS 5.      // deg the aileron always keeps: the elevator gives it up (else a pitch loop holding the elevons on a stop leaves none)
                               //   The orbiter's own elevon priority is not in our documents: a stated deviation.
GLOBAL FLAP_LIM IS 19.5.       // the body flap (range 20)
GLOBAL ELV_STICK IS 25.        // deg of elevon at full stick when unlocked (ctrlSurfaceRange x authority 100 %)
GLOBAL FLAP_STICK IS 20.       // deg of body flap at full stick when unlocked
GLOBAL RUD_HALF_LIM IS 49.3.   // each rudder half's SPEEDBRAKE cap = 98.6 / 2 (the orbiter's max speedbrake).
                               // Above Mach 1.5 SB_SUPER_MAX still holds 32.5; a half's TRAVEL is
                               // RUD_OPEN_MAX 55. At touchdown the brake opens to this (the max hinge); the HUD's full scale.
GLOBAL RUD_LIM IS 10.          // the rudder component
GLOBAL FLAP_K IS 0.5.          // 1/s: flap deg/s per deg of elevator trim off the schedule
GLOBAL FLAP_RATE IS 2.         // deg/s (the orbiter: 1.6-3)
GLOBAL FLAP_DB IS 1.           // deg of elevator trim (the orbiter's 1 deg deadband)
GLOBAL SB_OPEN IS 32.5.        // deg a side AG3 opens the brake to (hinge 65), whatever it started at -- the most the
                               // sideslip allows at every Mach
GLOBAL SB_SUPER_MAX IS 32.5.   // deg a side: SPDBK AUTO's most above SB_SUPER_MACH; at 35 a side the Dutch roll from the TAEM interface does not damp
                               //   (65 hinge above Mach 1.5; 70 below, where the rudder works)
GLOBAL SB_SUPER_MACH IS 1.5.   // SB_SUPER_MAX applies above this Mach
GLOBAL SB_RUD_MAX IS 5.        // deg a side: up to here the brake counts as SHUT (both halves move, RUD_SIGN -1)...
GLOBAL SB_CLOSE_MAX IS 28.     // ...from there to here a yaw CLOSES ONE half (below the halves' lift peak)...
GLOBAL SB_SPLIT_MIN IS 31.     // ...and from here (past the peak) OPENS ONE half further; in between neither is
                               // monotonic: the rudder law is off there and SPDBK AUTO does not hold the brake there
// YAW ACROSS THE WHOLE SPEEDBRAKE RANGE: on KSP's stock lifting-surface curve (Cl(sin incidence), a cusp at 30 deg; SOCK
// RealAero patches every SOCK part but the rudder) a rudder half's lift slope falls from 0.98 of its zero-incidence value
// at 15 deg to 0.48 at 28 and reverses at the 30 deg peak (-0.45 at 32.5). Below the peak the shut-brake sign holds and an
// open scheme has the wrong sign from 25 to 30. Closing a half, or opening one past the peak, moves it away from the peak.
GLOBAL RUD_CLOSE_LIM IS 10.    // deg: a closing half may go this far past zero (the steepest lift there)
// the close scheme's gain on the shut-brake law: 2 / (one half's slope averaged over a 3 deg close), by the brake a side
GLOBAL RUD_CLOSE_K_TAB IS LIST(LIST(5, 2.00), LIST(10, 2.01), LIST(15, 2.04), LIST(20, 2.12), LIST(24, 2.42),
    LIST(26, 2.77), LIST(28, 3.39)).
GLOBAL RUD_HINGE_MAX IS 55.    // deg: with the brake open a yaw command opens ONE half further, up to this (the
                               // speedbrake deploys to the full 55 degrees during yaw inputs); the other half stays
GLOBAL RUD_OPEN_K IS 4.        // the rudder gains x this with the brake open (the probe's design: it measured the split)
// THE RUDDER CURVE PATCH: SOCK RealAero 14_rudder_curve.cfg gives the rudder halves a lift curve without the 30 deg cusp:
// a half's lateral force F(d) = Cl(sin d) cos d rises to 36 deg instead of peaking at 30, and the speedbrake's drag is
// unchanged to 30 a side. With it there is ONE SCHEME at every brake angle above SB_RUD_MAX: a yaw CLOSES one half by the
// angle whose lateral force matches the shut-brake rudder's at the same command, F(brake) - F(half) = 2 F(command), so
// the loop sees the shut-brake rudder's power at every brake angle (no open scheme, no dead band).
// TRUE ONLY WITH THE PATCH INSTALLED: on KSP's stock curve a small close past 30 deg yaws the wrong way. Set FALSE if the
// patch is removed.
GLOBAL RUD_CURVE_PATCH IS TRUE.
// THE HINGE-KEEPING SPLIT: with the patch, a yaw closes one half AND opens the other by as much, up to RUD_OPEN_MAX,
// solved so F(open) - F(close) = 2 F(command): the same yaw force per command as the close scheme, so the loop's gain is
// unchanged, and the hinge (the two halves' sum, the speedbrake) is kept while the opening half has room (fully below
// ~30 a side for the usual commands, partly at 32.5, not at 35 a side: there the close scheme applies). FALSE = the
// close scheme.
GLOBAL RUD_SPLIT IS TRUE.
// THE OPENING HALF'S LIMIT: a half may open past the brake's 35 for a yaw. 14_rudder_curve.cfg holds a half's side force
// from 36 deg (rising 0.2 %/deg past 40) to 58 and stalls past it, and KSP clamps a half at 1.5 x its ctrlSurfaceRange
// (37): 55.5. So the opening half keeps the hinge to 55 without taking yaw away. While it yaws the brake drags more (a
// half at 55 makes 2.3-3x a half's drag at 35), as the real orbiter's mixing keeps the panels' sum.
GLOBAL RUD_OPEN_MAX IS 55.
GLOBAL RUD_F_TAB IS LIST(LIST(-12, -0.4014), LIST(-10, -0.3372), LIST(-8, -0.2716), LIST(-6, -0.2047), LIST(-4, -0.1369),
    LIST(-2, -0.0686), LIST(0, 0.0), LIST(2, 0.0686), LIST(4, 0.1369), LIST(6, 0.2047), LIST(8, 0.2716),
    LIST(10, 0.3372), LIST(12, 0.4014), LIST(14, 0.4637), LIST(16, 0.5228), LIST(18, 0.5796), LIST(20, 0.6331),
    LIST(22, 0.6811), LIST(24, 0.7215), LIST(26, 0.7525), LIST(28, 0.7729), LIST(30, 0.7817), LIST(32, 0.7849),
    LIST(34, 0.7880), LIST(36, 0.7911), LIST(38, 0.7911), LIST(40, 0.7911), LIST(42, 0.7943), LIST(44, 0.7974),
    LIST(46, 0.8006), LIST(48, 0.8038), LIST(50, 0.8069), LIST(52, 0.8101), LIST(54, 0.8132),
    LIST(56, 0.8164)).   // F(d), the patched curve (Mach-free shape)
GLOBAL RUD_FINV_TAB IS LIST(LIST(-0.4014, -12), LIST(-0.3372, -10), LIST(-0.2716, -8), LIST(-0.2047, -6), LIST(-0.1369, -4),
    LIST(-0.0686, -2), LIST(0.0, 0), LIST(0.0686, 2), LIST(0.1369, 4), LIST(0.2047, 6), LIST(0.2716, 8),
    LIST(0.3372, 10), LIST(0.4014, 12), LIST(0.4637, 14), LIST(0.5228, 16), LIST(0.5796, 18), LIST(0.6331, 20),
    LIST(0.6811, 22), LIST(0.7215, 24), LIST(0.7525, 26), LIST(0.7729, 28), LIST(0.7817, 30), LIST(0.7849, 32),
    LIST(0.7880, 34), LIST(0.7911, 36)).   // its inverse
GLOBAL CL_RUD_CLOSE_K IS 0.37. // the rollout centreline's rudder through the close scheme: x this keeps its yaw per command
// The rudder's sense under FAR: SockFarTrim takes it from the fin's geometry, so the gains keep their stock sign (+1);
// -1 flips the rudder's gains under FAR, a spare in case it is wrong.
GLOBAL FAR_RUD_SIGN IS 1.
IF FAR_ON AND FAR_RUD_SIGN < 0 {
    FOR row IN KDRC_TAB { SET row[1] TO 0 - row[1]. }
    FOR row IN KBETA_TAB { SET row[1] TO 0 - row[1]. }
    SET CL_RUD_CLOSE_K TO 0 - CL_RUD_CLOSE_K.
}
// Under FAR the fin flies the halves' COMMON deflection, linear, the brake ignored (SockFarTrim), so the patch's
// force-matched throw (made for stock's lift peak) would be a pure gain on FAR's rudder (x8 near zero at TAEM's brake of
// 32.5 a side). So under FAR, in flight, the rudder takes the shut-brake mapping at every brake angle: the fin flies the
// command, within RUD_LIM. 0 = stock.
GLOBAL RUD_LIN IS 0.
IF FAR_ON { SET RUD_LIN TO 1. }
// Under FAR the yaw loops (the rudder's and the jets') take the roll about the velocity from the MEASURED roll rate, not
// the command: a roll about the velocity (r = -p TAN(alpha)) must not read as a yaw error, and under FAR the fin's roll
// goes the same way as such a departure. With the measured rate a roll about the velocity is no yaw error at any rate;
// a steady roll at the command flies as before. 0 = stock (the command).
GLOBAL YAW_PK IS 0.
IF FAR_ON { SET YAW_PK TO 1. }
                               //   what the open scheme gave at 35 a side (stock curve: 1.1 against 2 F'(0) = 2.95 per deg)
// THE GROUND MODE (the orbiter's WOWLON / WONG): see the pitch law
GLOBAL GND_H_FT IS 1.0.        // the main gear this close to the runway (the HUD's radar height) = main-gear contact
GLOBAL GND_OFF_FT IS 20.       // ...and back above this = airborne again (a go-around), the ground mode cleared
GLOBAL CTC_OFF_FT IS 3.        // THE CONTACT MODE (the guidance mode, before landRun's latch): a bounce past this hands the
                               //   pitch back to the flare law (an attitude held after a skip floats the vehicle).
                               //   3 -> 8 ft (2.4 m): the gear's first-contact HOP is 1.3-1.4 m; at 3 ft the flare law came back mid-hop and answered with elev -25 (the nose-up kick, 2-4 hops)
                               //   8 -> 12 ft (3.7 m): the hop apex read 8.2 ft in a stock test; at 8 ft the
                               //   contact released once there (elev -20 nose-up kick). 12 ft covers the 2.5 m hop.
                               //   reverted to 3 ft (the 12 ft setting crashed a stock test).
GLOBAL GND_STICK IS 0.5.       // the pitch stick sensitivity after main-gear contact (the orbiter: halved)
GLOBAL GND_ELV_UP IS 20.       // the up-elevon limit after main-gear contact, deg (the orbiter's CSS: -20)
// MORE PITCH-DOWN ON THE MAINS: before WONG the body flap goes trailing-edge DOWN and the elevator has pitch priority
// (with the elevator capped by the aileron's room and the flap frozen trailing edge up, the vehicle cannot derotate from
// 12-14 deg). A deviation: the orbiter's derotation is the elevons' alone.
GLOBAL GND_FLAP_TED IS 10.     // deg TED: the body flap on the mains, from main-gear contact to WONG (then back to 0)...
GLOBAL GND_FLAP_TED_MAX IS 19.5. // ...and up to its full travel (FLAP_LIM) while the derotation's integral works (DR_FLAP_I):
                               //   the full flap only when needed
GLOBAL DR_FLAP_I IS 5.         // deg of the derotation's integral (dDrI) at which the flap is at GND_FLAP_TED_MAX
GLOBAL GND_FLAP_RATE IS 5.     // deg/s
GLOBAL GND_FLAP_THETA IS 15.   // deg of pitch: above it the flap goes back to 0 (its trailing edge off the runway; the elevons scrape at ~17.5 with ~16 TED)
// AUTO on the mains HOLDS THE ATTITUDE of the main-gear latch until the derotation (the guidance's 185 KEAS), as the
// orbiter's auto rollout ("guidance commands an attitude hold and derotates at 180 KEAS"). A rate hold alone (qc 0,
// the trim frozen on the ground) would let the speedbrake's crossfeed (SBX_TAB at 49.3 a side: ~15 deg TED) and the
// flap's GND_FLAP_TED bring the nose down ~2 deg/s. So: a rate command toward the held attitude, the trim integrating
// (the hold's integral: the crossfeed, the chute, the c.g.); the body flap keeps its ground schedule (to GND_FLAP_TED,
// frozen at the latch). CSS unchanged (the pilot holds it).
GLOBAL GND_HOLD_MAX IS 12.     // deg: the held attitude no higher than this (the tail and the elevons scrape at ~15-17.5)
GLOBAL GND_HOLD_K IS 2.       // 1/s: the nose-up rate asked per deg below it (1 sags 0.5-1 deg after the latch;
                              //   held in warp by the pitch loop's factor)...
GLOBAL GND_HOLD_QMAX IS 2.    // ...within this, deg/s (the derotation's FSSR rate: no faster back than it comes down)
GLOBAL LR_ELEV IS 10.          // the nose-gear load relief: the elevons to 10 deg TED...
GLOBAL LR_RATE IS 20.          // ...at 20 deg/s
GLOBAL LB_K IS 1.              // 1/s: the ground load balance's roll-rate command per deg of bank (no roll stick)
GLOBAL LB_FADE IS 100.         // s: the load balance fades out over this from WONG (the orbiter's 100 s)
// THE AUTO ROLLOUT (see the header)
GLOBAL CL_KY IS 0.2.           // deg of heading command per m off the centreline
GLOBAL CL_PSI_MAX IS 3.        // deg: the heading command's limit
GLOBAL CL_KP IS 12.            // % of brake differential per deg of heading error (the brakes' yaw: ~0.015 deg/s2 per %,
GLOBAL CL_KD IS 30.            // % per deg/s of yaw rate                          an estimate)
GLOBAL CL_KPR IS 4.            // rudder deg per deg of heading error (the brake-open scheme, one half toward 55)
GLOBAL CL_KDR IS 10.           // rudder deg per deg/s
GLOBAL YB_AUTO_SPAN IS 20.     // % after WONG in AUTO: the far main lowered by up to this (CSS: 2 x YB_SPAN)
GLOBAL CL_HOT IS 0.5.          // the yaw stick past this (gimbal units)...
GLOBAL CL_HOT_T IS 0.3.        // ...for this long (s) = the pilot takes the rollout (CSS)
// THE AUTOMATIC DEROTATION (see the header)
GLOBAL DR_TRIG IS 0.33.        // a nose-down pitch stick past this = the trigger (> 33 %); no cancel once it runs
GLOBAL DR_ACC IS 0.6.          // deg/s2: the nose-down rate command's ramp (the orbiter's beep-trim derotation)...
// THE AUTO DEROTATION'S RAMP: at DR_ACC the guidance's rate takes 3.3 s to reach 2 deg/s and 8 s to reach the short
// field's 5 (~680 m on the mains without brakes). At 3 deg/s2 (as brisk as the real orbiter's) it takes 0.7 s and 1.7 s,
// done while the drag chute (its nose-up pull on the mains) is ~30 % open. The rates stay the FSSR's (2 deg/s; the short field 5).
GLOBAL DR_ACC_AUTO IS 3.0.     // deg/s2: the AUTO (guidance) derotation's ramp; the CSS stick's keeps DR_ACC
GLOBAL DR_RATE IS 1.5.         // deg/s: ...to this
GLOBAL DR_RATE_SEMI IS 3.0.    // deg/s: a ROLLOUT CSS push before the guidance asks a rate (dapInit: AL_DEROT_RATE when defined)
// THE DEROTATION USES THE ELEVONS FULLY: a large drag chute can lift the nose on the mains, and once the nose sticks the
// P loop alone holds little elevator. On the mains while derotating, a nose-down-only integral of the nose's lag behind
// the rate command adds elevator while the nose comes down slower than commanded and gives it back when it comes down
// faster (dDrI, 0..ELV_LIM; it stops growing at the elevator's limit). A deviation: the orbiter's derotation is the
// elevons' P loop alone.
GLOBAL DR_KI IS 5.             // deg of elevator per s, per deg/s the nose lags the derotation command
// THE CHUTE GUARD: on the mains before WONG, the nose rising faster than CHUTE_GUARD_Q for CHUTE_GUARD_T with the
// elevator at its nose-down limit means the drag chute out-pulls the derotation: the DAP asks the host (landRun) to cut it
// (dChuteCutReq). Above ~9 deg of pitch on the mains gravity lifts the nose too, and at low speed nothing brings it back.
GLOBAL CHUTE_GUARD_Q IS 0.5.   // deg/s nose-up...
GLOBAL CHUTE_GUARD_T IS 0.5.   // ...for this long (s)
// THE GROUND YAW: the yaw stick -> differential braking on the mains (see the header)
GLOBAL YB_BASE IS 5.           // % each main before WONG, the DAP owning the brakes
GLOBAL YB_SPAN IS 5.           // +- % from the yaw stick -> 0..10 % before WONG; after WONG the far main - 2 x this
GLOBAL NOSE_BRK_MAX IS 65.     // % the nose gear's slider at most after WONG (the lightly loaded
                               //   nose gear locks up first); the mains keep YB_MAX
GLOBAL YB_MAX IS 95.           // % (the brakes lock at 100 %) -- at 100 % KSP swaps in a
                               //   parking-brake torque (maxBrakeTorqueRest 1000, hard-coded): the lock
GLOBAL BRK_TORQUE_K IS 2.      // the brake torque patch's factor (11_brake_torque.cfg: main 7 -> 14,
                               //   nose 4 -> 8): the differential %s below are divided by it, so their forces stay as tuned
GLOBAL DAP_BRK_BASE IS -1.     // % after WONG, every wheel's slider base: the host's (landRun: 95, the firmest);
                               //   -1 = the craft's own values (standalone css_dap)
// SHORT FIELDS: THE BRAKES FROM THE MAIN GEAR (the short-field technique: touchdown near the threshold, an instant
// derotation and the full brakes): the host sets DAP_BRK_FROM_WOW on a short field (landRun: the A/L's aim shift > 0),
// and the ground yaw's full-brake mode (dYb 2) starts with the ground mode instead of at WONG: the mains' sliders ramp from
// YB_BASE at BRK_SF_RAMP to YB_MAX, the nose gear unbraked until it touches. Braking on the mains also pitches the nose
// down (the force acts below the CoM). A deviation: the orbiter brakes after the nose gear.
GLOBAL DAP_BRK_FROM_WOW IS FALSE. // the host's
GLOBAL BRK_SF_RAMP IS 45.      // % per s: the mains' sliders from YB_BASE to YB_MAX in about 2 s
// ...AND THEY BACK OFF WHILE THE NOSE FALLS FAST: the braking's nose-down moment can slap the nose gear down at -10
// deg/s and more with the elevator at its -20 nose-up limit. Before WONG: the nose falling faster than MAX(BRK_SF_QMIN, BRK_SF_QK x the derotation
// command) with the elevator at the ground nose-up limit restarts the ramp from YB_BASE; full braking otherwise.
GLOBAL BRK_SF_QMIN IS 4.       // deg/s nose-down at least (the CSS stick's derotation commands 1.5)...
GLOBAL BRK_SF_QK IS 1.5.       // ...or this times the derotation's rate command (the short field's AUTO 5 -> 7.5)
GLOBAL YB_STEP IS 5.           // % the slider's step (UI_FloatRange stepIncrement 5; kOS SETFIELD snaps to it)
// THE GEAR'S SUSPENSION SLIDERS, forced here: 6_gear_suspension.cfg is tuned for these values with Spring/Damper Override
// (auto off). KSP saves the sliders per vessel; at 0.35 / 1 the vessel bounces on landing.
GLOBAL GEAR_SPRING IS 1.       // Spring Strength (0.05-3)
GLOBAL GEAR_DAMPER IS 2.       // Damper Strength (0.05-2)
GLOBAL YB_PWM IS 10.           // ticks per pulse period for a value between two steps (0.2 s)
GLOBAL YB_DB IS 0.02.          // the yaw stick's deadband, gimbal units
GLOBAL SB_RATE IS 10.          // deg/s a side (the orbiter: 6-11)
GLOBAL SB_LEVER_ARM IS 0.01.   // MAN: the lever law arms once kOS reads the lever this far (1 %) from its start value
                               //   (a live lever, dLevLive: at once in MAN)
GLOBAL DT IS 0.02.             // s: the tick (dapTick sets it each tick to the game time since the last)
GLOBAL DT_1X IS 0.02.          // s: one physics tick at 1x
// PHYSICS WARP: KSP's physics warp (2-4x) makes a physics tick 0.04-0.08 s and the DAP ticks once a physics tick. With a
// fixed DT its integrators, slews and filters would run 2-4x slow and its rate loops (gain x tick 0.2 at 1x) near the
// discrete limit (a roll limit cycle at 4x: the poles of the roll loop at gain x tick 0.8 are at 1.95 Hz). dapTick sets
// DT to the real tick (whole physics ticks, 5 at most) and each rate loop's gain x tick is held to DAP_WARP_KT (damped
// at 0.08 s up to 1.5 x the tables' power). Every loop is below it at 1x.
GLOBAL DAP_WARP_KT IS 0.3.
// The AIR roll loop's own gain x tick cap. The true roll authority in TAEM is 0.2-0.5 of LD_TAB (fits of 13 stock + 8 FAR logs),
// not the 0.7-1.4 DAP_WARP_KT 0.3 was sized for: at x4 the reversal ran 8 deg behind the bank command (1x: 2). 0.4 = a 2x stability margin over the largest authority seen.
GLOBAL DAP_WARP_KT_R IS 0.4.
GLOBAL YJ_ACC IS 5.5.          // deg/s2: the jets' yaw at full command (~5.5), for DAP_WARP_KT
GLOBAL dTickT IS -1.           // s: the last tick's game time (dapTick; -1: none yet)
GLOBAL D_FLUSH IS 25.          // log rows per LOG: one a second at D_LOG_EVERY 2
GLOBAL D_LOG_EVERY IS 2.       // a log row every this many ticks: 25 Hz
// AUTO from the guidance (the header): KA_ALPHA and KA_PHI are designed on the probe's plant from M2.7 to M0.35, with the
// one-tick write delay and the actuator slew. KA_ALPHA 2.0 limit-cycles at the low-q point (M0.35, 7.7 kPa). KA_PHI 1.5
// overshoots a 45 deg roll-in by up to 4.7 deg (the inner loop's lag at the slew's end); less feed-forward trades that for
// more lag. The DAP csv logs both (gd_alpha / aoa, gd_bank / bank).
GLOBAL DAP_AUTO_GUID IS FALSE.
GLOBAL KA_ALPHA IS 1.          // 1/s: deg/s of nose-up rate asked per deg of alpha error
// THE SUPERSONIC PITCH LOOP: at Mach 1.75-1.15 (q 3-4 kPa, alpha 15-21) the loop sits on a nearly unstable plant, which
// gives a ~3.5 s pitch swing (the elevator at times saturated; the guidance's Nz and alpha commands follow it). Above
// DAP_SUP_MACH (blended over +-0.1 Mach) the alpha gain is KA_ALPHA_SUP and the rate loop LOOP_P_SUP (CSS's too: one rate
// loop): zeta 0.40 / 0.52 there, against 0.23 / 0.34 with the base gains. Below Mach 1.0 the base gains apply (TAEM
// subsonic, the A/L).
GLOBAL KA_ALPHA_SUP IS 0.7.
GLOBAL LOOP_P_SUP IS 7.
GLOBAL DAP_SUP_MACH IS 1.1.
// THE SUPERSONIC FEED-FORWARD'S LAG: the ramp's rate acd steps at every 0.24 s publication (qc steps by 5-15 deg of
// elevator), which gives ~1 s elevator spikes supersonic. A first-order lag on acd, its time constant DAP_FF_TAU_SUP x
// the supersonic share fSup (none below Mach 1.0: the A/L and the flare are unchanged), smooths them.
GLOBAL DAP_FF_TAU_SUP IS 0.48.  // s
// Below it DAP_FF_TAU_SUB: the A/L's alpha lands every 0.08-0.16 s (AL_DT / AL_NSUB, the kOS loop) and its 0.08 s
// ramp's rate, zeroed after DAP_RAMP_HOLD, would ripple the elevator at 6.25 Hz; lagged 0.12 s, the mean rate unchanged,
// alpha lands 0.08 deg rms later in the flare.
GLOBAL DAP_FF_TAU_SUB IS 0.12.  // s
GLOBAL DAP_QPATH_MEAS IS TRUE. // AUTO pitch: the flight path's rotation measured (FALSE: from the commanded Nz)
GLOBAL PATH_TAU IS 0.2.        // s: its filter
GLOBAL DAP_AC_RAMP IS TRUE.    // AUTO pitch: the alpha command ramped over its publication interval (FALSE: stepped)
GLOBAL DAP_RAMP_HOLD IS 1.5.   // the ramps' rate (alpha + bank) holds to this many publication intervals: the DAP's tick
                               //   runs before the host publishes, so the next value lands one tick after a ramp's end.
                               //   Zeroed at the end, the A/L's 4-tick alpha ramp would run its rate 3 ticks of 4 and the
                               //   elevator would chatter through the flare
GLOBAL KA_PHI IS 1.5.          // 1/s: deg/s of roll rate asked per deg of bank error
// THE AUTO RATE LIMITS ARE CSS'S (the guidance obeys them too): the stick's full-deflection rates at the Mach, shapeP(1, M) / shapeR(1, M) --
// pitch 9.2 deg/s at M1.2 and below .. 2.9 at M2 and above, roll 26.5 at M0.6 and below .. 5.9 at M1.5 and above (the
// FSSR's CSS gearing above).

// ---------------------------------------------------------------- the state (declared here: every global a GUI
// callback or the per-tick trigger touches exists before them; dapInit SETs every one again, so the library
// can be initialised more than once in a program)
GLOBAL dGmb IS 0.
GLOBAL dGmbMod IS 0.            // The gimbal's module, registered (modReg), so dGmbLive can see a lost engine; 0 = not registered
GLOBAL dGmbHave IS FALSE.
GLOBAL dGmbLock0 IS TRUE.
GLOBAL dGmbLim0 IS -1.
GLOBAL D_T IS 0.
GLOBAL D_TAG IS "".
GLOBAL D_TXT IS "".
GLOBAL D_CSV IS "".
GLOBAL dAll IS LIST().
GLOBAL dElv IS LIST().          // LIST(module, side: +1 right, -1 left, key)
GLOBAL dRud IS LIST().          // the two rudder halves (the speedbrake split)
GLOBAL dFlap IS 0.
GLOBAL dHaveFlap IS FALSE.
GLOBAL dFlapAng IS 0.
GLOBAL dRudHave IS FALSE.
// A rudder half FROZEN by FCS 01 (lib_flfx): 0 none, 1 half 0 (RUDDER L), 2 half 1, 3 both. dapTick sets it each tick (the C# DAP reads it).
// With one half failed: the speedbrake is gone (the DAP holds it shut, the guidance's command is not flown), the GOOD half flies the rudder
// alone (RUD_ONE_K x the loop's command, <= RUD_ONE_LIM deg: one half has half the side force), and the yaw jets fly below YJ_MACH down to
// touchdown (dGnd) instead of stopping at Mach 1. FLIGHT-ONLY tuning: RUD_ONE_K / RUD_ONE_LIM (no sim has a half-rudder plant).
GLOBAL dRudFail IS 0.
GLOBAL RUD_ONE_K IS 2.
GLOBAL RUD_ONE_LIM IS 20.
GLOBAL dBk IS LIST().
GLOBAL dBkL IS -1.             // the index in dBk of the left main, the right main, the nose gear
GLOBAL dBkR IS -1.
GLOBAL dBkN IS -1.
GLOBAL dBkHave IS FALSE.
GLOBAL dSbOpen IS SB_OPEN.     // AG3's open angle: always SB_OPEN, not the angle found
GLOBAL dSbTarget IS 0.
GLOBAL dSbBase IS dSbTarget.
GLOBAL dSbFlips IS 0.
GLOBAL dLast IS LEXICON().     // last angle written, per surface key (the two rudder halves share one part)
GLOBAL dElev IS 0.              // elevator, deg TED (deploy +): the mean of the angles FOUND (0 if un-deployed)
GLOBAL dReqP IS FALSE.
GLOBAL dReqR IS FALSE.
GLOBAL dReqEnd IS FALSE.
GLOBAL dMsg IS "".            // before the window: its buttons' callbacks set it (a click can come at any tick)
GLOBAL dGui IS 0.
GLOBAL dRow IS 0.
GLOBAL dBtnP IS 0.
GLOBAL dBtnR IS 0.
GLOBAL dRow2 IS 0.
GLOBAL dBtnEnd IS 0.
GLOBAL dClReq IS TRUE.         // the rollout: AUTO (the centreline) asked -- the ROLLOUT button; the hot stick clears it
GLOBAL dBtnCl IS 0.
GLOBAL dRow3 IS 0.
GLOBAL dBtnCam IS 0.
GLOBAL dBtnHud IS 0.           // HUD (HORIZ SIT's row, left of HUD CAM): the HUD shown / hidden (lib_hud hdVis)
GLOBAL dHudReq IS FALSE.       // HUD / HUD CAM pressed before the HUD loaded (the GRTLS): the host's loop loads it
GLOBAL dCamWant IS FALSE.      // HUD CAM pressed before the HUD loaded: the camera once it has
GLOBAL dBtnBail IS 0.         // BAILOUT (HORIZ SIT's row, the right 20 %): two presses confirm (dapBailPress)
GLOBAL dBtnFail IS 0.         // "!": the FAILURES window (lib_failui), only where the host registered a handler (ops3q)
GLOBAL dBtnAlt IS 0.          // ALT MODE (HORIZ SIT's second row): the HUD's altitude, RDR / RWY (lib_hud hdAltMode)
GLOBAL dBtnTu IS 0.           // TRK UP / RWY UP (HORIZ SIT's second row beside ALT MODE): lib_taemdisp's TD_TRKUP
GLOBAL dBailReq IS FALSE.      // the crew's bailout confirmed (latched): ops6q's GRTLS turns BLUE, landRun's TAEM holds
GLOBAL dBailT1 IS -1.          // the first press's time (-1: none)
GLOBAL dBailOn IS FALSE.       // the bailout hold flies (BAILOUT ON; presses ignored)
GLOBAL DAP_BAIL_GAP IS 1.0.    // s: the confirming press at least this long after the first
GLOBAL DAP_BAIL_WIN IS 5.0.    // s: ... and at most this long, else the first press is dropped (a deviation: no orbiter counterpart)
GLOBAL dRowDm IS 0.            // the crew's downmode row (OTT STRT / OTT MEP / SW RWY), guidance mode only; dapDmShow
                               //   sets it
GLOBAL dBtnStrt IS 0.
GLOBAL dBtnMep IS 0.
GLOBAL dBtnRwy IS 0.           // SW RWY: the runway's other end + the straight-in; again: back
GLOBAL dRwyAlt IS "".          // the landing runway's other end, "" none (lib_land's landRun / ldSwitchRunway)
GLOBAL dBtnSiteL IS 0.         // < SITE >: browse the sites (lib_land ldSiteTick), the middle one takes the one shown
GLOBAL dBtnSite IS 0.
GLOBAL dBtnSiteR IS 0.
GLOBAL dSiteStep IS 0.         // a browse press for ldSiteTick: -1 / +1, 99 = refresh in place, 0 none
GLOBAL dSiteNm IS "".          // the runway end shown ("" = the current site's: nothing to take)
GLOBAL dSiteReq IS "".         // the end a press took (dDmReq "site")
GLOBAL dDmReq IS "".           // a press for the guidance's next cycle, "strt" | "mep" (lib_land hands it to tg["dm_crew"])
                               //   | "site" (lib_land ldSiteGo, the runway dSiteReq)
GLOBAL dDmGr IS FALSE.         // the GRTLS flies the OTT row (ops6q; lib_grtls grtlsDmShow): dapDmShow live
                               //   | "rwy" (lib_land switches the runway itself, then taemg_rwy_switch)
GLOBAL dLblHud IS 0.
GLOBAL dStat IS 0.             // the window's STATUS section (landRun adds its line there)
GLOBAL dLbl IS 0.
GLOBAL dHud IS FALSE.
GLOBAL dCssP IS FALSE.
GLOBAL dCssR IS FALSE.
GLOBAL dTrimE IS 0.            // pitch trim, deg of NOSE-UP elevator (dapInit: the elevator found, less the crossfeed)
GLOBAL dTrimA IS 0.            // aileron trim, deg (ELV_DIF units)
GLOBAL dAil IS 0.              // aileron, deg (ELV_DIF units: + = right TED = LEFT roll)
GLOBAL dRudC IS 0.             // rudder, deg (RUD_OPP units x RUD_SIGN)
GLOBAL dQturnF IS 0.           // the filtered turn term, deg/s
GLOBAL dRows IS LIST().
GLOBAL dFtOn IS FALSE.         // the addon has FTGROUNDCOLS: the csv's ft_* columns on the mains (log only)
GLOBAL dLoop IS 0.
GLOBAL dRclDb IS -99999.       // rudCloseLim's memo: its last call's brake angle and RUD_CLOSE_LIM, and the answer
GLOBAL dRclLim IS -99999.
GLOBAL dRclV IS 0.
GLOBAL dSasOff IS 0.
GLOBAL dRelock IS 0.
GLOBAL dDone IS FALSE.
GLOBAL dGnd IS FALSE.          // the main gear has touched (latched; cleared above GND_OFF_FT)
GLOBAL dCtc IS FALSE.          // the contact mode: the main gear touched, landRun's latch not yet (the guidance mode)
GLOBAL dCtcElev IS 0.          // deg: the elevator at the contact (the contact mode's nose-up limit)
GLOBAL dGndTh IS 0.            // deg: the pitch attitude AUTO holds on the mains (the latch's, <= GND_HOLD_MAX)
GLOBAL dWong IS FALSE.         // the nose gear is down (the pitch load relief)
GLOBAL dWongT IS 0.            // TIME:SECONDS at WONG (the load balance's fade)
GLOBAL dYb IS 0.               // the ground yaw's brakes: 0 not engaged, 1 the DAP's (before WONG), 2 the pilot's (after)
GLOBAL dYbU IS 0.              // the yaw stick's differential, % (+ = brake the right main more = nose right)
GLOBAL dBetaC IS 0.            // the sideslip the yaw stick asks in flight, deg
GLOBAL dYawJ IS 0.             // the yaw jets' command, -1..1 (+ = nose right)
GLOBAL dYjAct IS FALSE.        // the yaw jets fly this tick
GLOBAL dYjRcs IS FALSE.        // dapYawJet turned RCS on for them
GLOBAL dBkLast IS LEXICON().   // the last brake slider written, per wheel key
GLOBAL dBkSfT IS -1.           // s: the short field's brake ramp since the ground mode (-1 = none)
GLOBAL dBkSfBack IS 0.         // the short field's brake back-offs (the nose falling fast), for the message
GLOBAL dClAct IS FALSE.        // the AUTO rollout steering now
GLOBAL dClPrev IS FALSE.
GLOBAL dClY IS 0.              // m off the centreline (+ right)
GLOBAL dClYd IS 0.             // m/s
GLOBAL dClDpsi IS 0.           // deg: the nose vs the runway (+ right)
GLOBAL dClPsiC IS 0.           // deg: the heading asked
GLOBAL dClUb IS 0.             // %: the brake differential asked (+ = nose right)
GLOBAL dClUr IS 0.             // deg: the rudder asked (+ = nose right)
GLOBAL dClHotT IS 0.           // s: the yaw stick past CL_HOT
GLOBAL dDerot IS FALSE.        // the automatic derotation running
GLOBAL dDrQ IS 0.              // deg/s: its nose-down pitch-rate command (<= 0)
GLOBAL dDrI IS 0.              // deg TED: the derotation's nose-down integral (0..ELV_LIM; DR_KI)
GLOBAL dChuteLiftT IS 0.       // s: the nose rising against the nose-down elevator limit (CHUTE_GUARD_*)
GLOBAL dChuteCutReq IS FALSE.  // the DAP asks the host to cut the drag chute (landRun cuts it)
GLOBAL dHudLblT IS 0.
// the guidance's record (the host writes it; the DAP reads it every tick) -- the guidance mode only
GLOBAL dGdOn IS FALSE.         // the host has published (AUTO holds until then)
GLOBAL dGdAlpha IS 0.          // deg: the alpha command
GLOBAL dGdAlphaDot IS 0.       // deg/s: its rate
GLOBAL dGdAlphaT IS -1.        // s: when the host published it (-1: never -- no ramp)
GLOBAL dGdAlphaDt IS 0.24.     // s: the host's publication interval (its pitch sub-step)
GLOBAL dGdNz IS 1.             // g: the normal load factor the guidance flies (the path-rate feed-forward)
GLOBAL dGdBank0 IS 0.          // deg, + = LEFT (the ship's sign): the bank command ramps from this ...
GLOBAL dGdBank1 IS 0.          // ... to this, over dGdBankDt s from dGdBankT (one guidance cycle)
GLOBAL dGdBankT IS 0.
GLOBAL dGdBankDt IS 1.
GLOBAL dGdSb IS 0.             // deg a side: the speedbrake command
GLOBAL dGdDerot IS 0.          // deg/s >= 0: the nose-down derotation rate the guidance asks on the mains (0 = hold)
GLOBAL dGdWow IS FALSE.        // the host's main-gear contact (landRun: 0.3 m for 0.5 s): the guidance mode's touchdown
GLOBAL dGdWong IS FALSE.       // the host's nose-gear contact
GLOBAL dGdHm IS 1E9.           // The host's main-gear radar height, m (landRun, each tick; 1E9 until it runs)
GLOBAL DAP_HUD_STALE_S IS 1.   // sHft not written for this long (game s) = the HUD is not measuring: the ground handover
                               //   (contact / bounce) takes the host's gear height dGdHm, or SHIP:STATUS, instead
GLOBAL dGdRwyOk IS FALSE.      // the landing runway given (the rollout's centreline); else the HUD's runway
GLOBAL dGdRwyThr IS LATLNG(0, 0).
GLOBAL dGdRwyFar IS LATLNG(0, 0).
GLOBAL dSbAuto IS FALSE.       // the speedbrake from the guidance (SPDBK AUTO) or AG3's (CSS)
GLOBAL dSbLever IS FALSE.      // MAN: the brake on the throttle lever, armed once kOS has seen the lever move
GLOBAL dThr0 IS 0.             // the lever as kOS read it at the DAP's start (SHIP:CONTROL:PILOTMAINTHROTTLE)
GLOBAL dThrPilot IS 0.         // the lever as kOS reads it this tick
GLOBAL dLevLive IS FALSE.      // the AFBW throttle lever is the pilot's throttle and read each tick (ADDONS:KALS:LEVERLIVE)
GLOBAL dLevK IS -1.            // the addon has LEVERLIVE: -1 not checked yet, 0 no (no KAL/S or an older DLL), 1 yes
GLOBAL dBtnSb IS 0.
GLOBAL dYawLk IS TRUE.         // the guidance mode's yaw lock (the rudder the stick's only in a CSS rollout)
GLOBAL dRelockN IS 0.          // the surfaces found unlocked (AG9 / ABORT) and locked again
GLOBAL dQa IS 0.               // the AUTO pitch-rate command, deg/s (the log)
GLOBAL dVhPrev IS V(0, 0, 0).  // the last tick's velocity direction (the flight path's measured rotation)
GLOBAL dVhT IS -1.
GLOBAL dPathQ IS 0.            // deg/s: the flight path's nose-up rotation, filtered
GLOBAL dNzM IS 1.              // g: the normal load factor, measured every tick from the path's rotation (the HUD's)
GLOBAL dAc0 IS 0.              // deg: the alpha command's ramp starts here ...
GLOBAL dAcdF IS 0.             // deg/s: the alpha feed-forward after its supersonic lag (DAP_FF_TAU_SUP)
GLOBAL dAcT IS -1.             // ... at the publication it ramps to
GLOBAL dAcNow IS 0.            // deg: the ramped alpha command in use (the log)
GLOBAL dPa IS 0.               // the AUTO bank command now, deg (the log)
GLOBAL dPcPrev IS 0.           // deg/s: the AUTO roll-rate command of the tick before ...
GLOBAL dPcN IS -9.             // ... and that tick's dLoop (its rate of change only from the tick just before)

// ---------------------------------------------------------------- THE C# DAP
// With D_CS on and the KAL/S addon installed with its DAP part, each tick's math is ADDONS:KALS:DAPTICK (coproc/Dap.cs, a
// line-for-line port of dapTickK below): kOS reads the vessel (dapCsIn), the addon reads and writes the DAP's globals
// itself (the state stays these kOS globals, exact), kOS applies the surfaces and the rare actions (dapCsAng,
// dapCsAct). The kOS cost of a tick: ~3000-4400 opcodes -> ~200. On any addon failure (no addon, an older DLL without
// DAPTICK, a tick's error: nothing written) D_CS turns off for the rest of the program with a line in the DAP's log
// (D_CS_ERR says why) and dapTickK flies that tick and the rest. SET D_CS TO FALSE. at the
// terminal before the run = kOS only. A change to dapTickK must be made in Dap.cs too.
IF NOT (DEFINED D_CS) { GLOBAL D_CS IS TRUE. }
GLOBAL D_CS_ERR IS "".
GLOBAL D_CS_N IS 0.            // the ticks the addon flew
GLOBAL dCsOk IS -1.            // -1 not looked at yet, 1 the addon's DAP is there

FUNCTION dapSay {
    PARAMETER s.
    IF NOT DAP_AUTO_GUID { PRINT s. }      // landRun's console stays blank; the log has it
    IF SOCK_LOG { LOG s TO D_TXT. }
}

// ---------------------------------------------------------------- helpers
FUNCTION linM {
    PARAMETER x, xLo, vLo, xHi, vHi.
    IF x <= xLo { RETURN vLo. }
    IF x >= xHi { RETURN vHi. }
    RETURN vLo + (vHi - vLo) * (x - xLo) / (xHi - xLo).
}
FUNCTION linS {                // linM on a schedule LIST(x lo, at lo, x hi, at hi) (the TG_CSS_* gearing)
    PARAMETER x, sch.
    RETURN linM(x, sch[0], sch[1], sch[2], sch[3]).
}

// THE PATCHED RUDDER'S CLOSE SCHEME (RUD_CURVE_PATCH): the closing half's angle that gives the shut-brake rudder's lateral
// force at c deg, F(db) - F(half) = 2 F(c), no further than RUD_CLOSE_LIM past zero; and the command that closes it fully
FUNCTION rudCloseTo {
    PARAMETER db, c.
    RETURN MAX(0 - RUD_CLOSE_LIM, rudFinv(rudFt(db) - 2 * rudFt(c))).
}
FUNCTION rudCloseLim {              // memoised: the brake angle changes only while it ramps
    PARAMETER db.
    IF db <> dRclDb OR RUD_CLOSE_LIM <> dRclLim {
        SET dRclV TO rudFinv((rudFt(db) - rudFt(0 - RUD_CLOSE_LIM)) / 2).
        SET dRclDb TO db.
        SET dRclLim TO RUD_CLOSE_LIM.
    }
    RETURN dRclV.
}
// THE TABLES WITHOUT THE SCAN (with the brake open the rudder's look-ups would cost the DAP ~1.4k opcodes a tick): rudFt = tabLook(RUD_F_TAB, d) and rudFinv = tabLook(RUD_FINV_TAB, f) TO THE BIT -- tabLook's
// interval (rudFt from the table's even grid, then walked to tabLook's test; rudFinv by halving), then its interpolation
FUNCTION rudFt {
    PARAMETER d.
    LOCAL n IS RUD_F_TAB:LENGTH - 1.
    IF d <= RUD_F_TAB[0][0] { RETURN RUD_F_TAB[0][1]. }
    IF NOT (d <= RUD_F_TAB[n][0]) { RETURN RUD_F_TAB[n][1]. }
    LOCAL i IS MAX(1, MIN(n, CEILING((d - RUD_F_TAB[0][0]) / (RUD_F_TAB[1][0] - RUD_F_TAB[0][0])))).
    UNTIL d <= RUD_F_TAB[i][0] { SET i TO i + 1. }
    UNTIL i <= 1 { IF d > RUD_F_TAB[i - 1][0] { BREAK. } SET i TO i - 1. }
    RETURN RUD_F_TAB[i - 1][1] + (RUD_F_TAB[i][1] - RUD_F_TAB[i - 1][1]) * (d - RUD_F_TAB[i - 1][0])
        / (RUD_F_TAB[i][0] - RUD_F_TAB[i - 1][0]).
}
FUNCTION rudFinv {
    PARAMETER f.
    LOCAL n IS RUD_FINV_TAB:LENGTH.
    IF f <= RUD_FINV_TAB[0][0] { RETURN RUD_FINV_TAB[0][1]. }
    IF NOT (f <= RUD_FINV_TAB[n - 1][0]) { RETURN RUD_FINV_TAB[n - 1][1]. }
    LOCAL lo IS 1.
    LOCAL hi IS n - 1.
    UNTIL lo >= hi {
        LOCAL mid IS FLOOR((lo + hi) / 2).
        IF f <= RUD_FINV_TAB[mid][0] { SET hi TO mid. } ELSE { SET lo TO mid + 1. }
    }
    RETURN RUD_FINV_TAB[lo - 1][1] + (RUD_FINV_TAB[lo][1] - RUD_FINV_TAB[lo - 1][1]) * (f - RUD_FINV_TAB[lo - 1][0])
        / (RUD_FINV_TAB[lo][0] - RUD_FINV_TAB[lo - 1][0]).
}
FUNCTION rudFq {                    // F(d) on RUD_F_TAB's uniform 2 deg grid (-12 .. 56): no scan
    PARAMETER d.
    LOCAL x IS (MIN(56, MAX(-12, d)) + 12) / 2.
    LOCAL i IS MIN(33, FLOOR(x)).
    RETURN RUD_F_TAB[i][1] + (RUD_F_TAB[i + 1][1] - RUD_F_TAB[i][1]) * (x - i).
}
FUNCTION rudFs {                    // its slope there, per deg
    PARAMETER d.
    LOCAL i IS MIN(33, FLOOR((MIN(56, MAX(-12, d)) + 12) / 2)).
    RETURN (RUD_F_TAB[i + 1][1] - RUD_F_TAB[i][1]) / 2.
}
// THE HINGE-KEEPING SPLIT (RUD_SPLIT): the closing half's angle h when the other opens to MIN(RUD_OPEN_MAX, 2 db - h) and
// F(open) - F(h) = 2 F(c), c >= 0: from the close scheme's answer three Newton steps (F is piecewise linear); with the
// opening half on its stop the closing one makes up the rest
FUNCTION rudSplitTo {
    PARAMETER db, c.
    LOCAL tgt IS 2 * rudFq(c).
    LOCAL hmin IS 2 * db - RUD_OPEN_MAX.
    IF rudFq(RUD_OPEN_MAX) - rudFq(hmin) <= tgt {
        RETURN MAX(0 - RUD_CLOSE_LIM, rudFinv(rudFq(RUD_OPEN_MAX) - tgt)).
    }
    LOCAL h IS MAX(hmin, rudCloseTo(db, c)).
    FROM { LOCAL k IS 0. } UNTIL k >= 3 STEP { SET k TO k + 1. } DO {
        LOCAL ho IS MIN(RUD_OPEN_MAX, 2 * db - h).
        LOCAL s IS rudFs(h) + (CHOOSE rudFs(ho) IF ho < RUD_OPEN_MAX ELSE 0).
        IF s > 0.000001 { SET h TO MAX(hmin, MIN(db, h + (rudFq(ho) - rudFq(h) - tgt) / s)). }
    }
    RETURN MAX(0 - RUD_CLOSE_LIM, MIN(db, h)).
}
FUNCTION tabLook {
    PARAMETER tb, x.
    IF x <= tb[0][0] { RETURN tb[0][1]. }
    LOCAL i IS 1.
    UNTIL i >= tb:LENGTH {
        IF x <= tb[i][0] {
            RETURN tb[i - 1][1] + (tb[i][1] - tb[i - 1][1]) * (x - tb[i - 1][0]) / (tb[i][0] - tb[i - 1][0]).
        }
        SET i TO i + 1.
    }
    RETURN tb[tb:LENGTH - 1][1].
}

FUNCTION clampV {
    PARAMETER x, lim.
    RETURN MAX(-lim, MIN(lim, x)).
}

FUNCTION dapMach {
    LOCAL ps IS SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE) * CONSTANT:ATMTOKPA * 1000.
    IF ps < 0.0001 { RETURN 0. }
    LOCAL qd IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000.
    RETURN SQRT(MAX(2 * qd / (1.4 * ps), 0)).
}

FUNCTION dapBank {              // + = LEFT bank (p > 0 = a LEFT roll raises it)
    LOCAL vd IS SHIP:VELOCITY:SURFACE.
    IF vd:MAG < 1 { RETURN 0. }
    SET vd TO vd:NORMALIZED.
    LOCAL upP IS VXCL(vd, SHIP:UP:VECTOR).
    LOCAL topP IS VXCL(vd, SHIP:FACING:TOPVECTOR).
    IF upP:MAG < 0.001 OR topP:MAG < 0.001 { RETURN 0. }
    SET upP TO upP:NORMALIZED.
    SET topP TO topP:NORMALIZED.
    LOCAL sgn IS 1.
    IF VDOT(VCRS(upP, topP), vd) < 0 { SET sgn TO -1. }
    RETURN sgn * VANG(upP, topP).
}

// the stick shapes (deg/s of commanded rate, the stick's own sign)
FUNCTION shapeP {
    PARAMETER g, M.
    LOCAL x IS ABS(g) * RHC_FULL - P_DB.
    IF x <= 0 { RETURN 0. }
    LOCAL s IS MIN(DEMAX, (KDEMLIN + PKQ * x) * x) * linS(M, TG_CSS_P_GAIN).     // 0.40 at M1.2 .. 0.125 at M2
    IF g < 0 { RETURN -s. }
    RETURN s.
}

// one axis through the keyboard mode (KB_*); the raw input back while the axis reads as a stick
FUNCTION kbAxis {
    PARAMETER i, raw.
    IF KB_MODE = 0 { RETURN raw. }
    LOCAL s IS dKb[i].
    LOCAL tn IS TIME:SECONDS.
    LOCAL dt IS 0.
    IF s[3] > 0 { SET dt TO MAX(0, MIN(0.2, tn - s[3])). }
    SET s[3] TO tn.
    LOCAL a IS ABS(raw).
    LOCAL atStop IS a < 0.0001 OR ABS(a - 1) < 0.0001.
    IF atStop AND ABS(raw - s[2]) > 0.9 { SET s[4] TO s[4] + 1. SET s[5] TO 0. }
    IF NOT atStop { SET s[5] TO s[5] + dt. }
    SET s[2] TO raw.
    IF KB_MODE = 1 {
        IF NOT s[0] AND s[4] >= KB_STEPS {
            SET s[0] TO TRUE.
            SET s[5] TO 0.
            addMsg(KB_AXN[i] + " KEYBOARD: a held key builds to " + ROUND(100 * KB_FULL) + " % in " + KB_RISE + " s, a tap nudges").
        }
        IF s[0] AND s[5] > KB_STICK_T {
            SET s[0] TO FALSE.
            SET s[4] TO 0.
            SET s[7] TO 0.
            SET s[1] TO 0.
            addMsg(KB_AXN[i] + " STICK: the raw input").
        }
        IF NOT s[0] {
            SET s[5] TO MIN(s[5], KB_STICK_T).
            RETURN raw.
        }
    }
    LOCAL sg IS 0.
    IF a >= 0.5 { SET sg TO CHOOSE 1 IF raw > 0 ELSE -1. }
    IF sg <> 0 {
        IF sg <> s[7] {
            SET s[6] TO tn.
            SET s[7] TO sg.
            SET s[1] TO sg * KB_MIN.
        } ELSE {
            SET s[1] TO sg * MIN(KB_FULL, ABS(s[1]) + (KB_FULL - KB_MIN) / KB_RISE * dt).
        }
    } ELSE IF s[7] = 0 OR tn - s[6] >= KB_TAP {
        SET s[7] TO 0.
        SET s[1] TO 0.
    }
    RETURN s[1].
}

FUNCTION shapeR {
    PARAMETER g, M.
    LOCAL x IS ABS(g) * RHC_FULL - R_DB.
    IF x <= 0 { RETURN 0. }
    LOCAL kl IS linS(M, TG_CSS_R_KL).          // 0.20 at M0.6 .. 0.9324 at M1.5
    LOCAL kp IS linS(M, TG_CSS_R_KP).          // 0.0571 .. 0.008
    LOCAL dmax IS linS(M, TG_CSS_R_DMAX).      // 23 .. 20
    LOCAL s IS MIN(dmax, (kl + kp * x) * x) * linS(M, TG_CSS_R_GAIN).      // 1.17 .. 0.30
    IF g < 0 { RETURN -s. }
    RETURN s.
}

// the CSS roll's top rate: added to shapeR's on the CSS path (lib_dap, lib_grdap; Dap.cs): (CSS_RMAX - shapeR's full
// stick) x the stick past the detent (0..1) cubed, so the centre's feel is nearly shapeR's; 0 where shapeR's full stick
// is already faster (subsonic). shapeR's sign convention (+ with g).
FUNCTION cssRx {
    PARAMETER g, M.
    LOCAL x IS MIN(1, (ABS(g) * RHC_FULL - R_DB) / (RHC_FULL - R_DB)).
    IF x <= 0 { RETURN 0. }
    LOCAL e IS MAX(0, CSS_RMAX - shapeR(1, M)) * x * x * x.
    IF g < 0 { RETURN -e. }
    RETURN e.
}

// The OMS gimbal engine (dGmb) is a part that a breakup / ditching can remove: every touch of it goes through dGmbLive
// (modLive on the gimbal's registered module: the vessel generation + the live part UIDs), like every other surface module.
FUNCTION dGmbReg {
    SET dGmbMod TO modReg(dGmb:GETMODULE("ModuleGimbal")).
}
FUNCTION dGmbLive {
    IF NOT dGmbHave { RETURN FALSE. }
    IF dGmbMod:ISTYPE("Scalar") { RETURN TRUE. }      // never registered: no touch rule of modLive (a fresh gimbal is on the ship)
    RETURN modLive(dGmbMod).
}

FUNCTION setAng {
    PARAMETER m, k, ang.
    IF surfFrozen(m) { RETURN. }
    IF NOT modLive(m) { RETURN. }
    IF dLast:HASKEY(k) AND ABS(dLast[k] - ang) < 0.01 { RETURN. }
    IF FAR_ON { surfSetAng(m, ang, CHOOSE -1 IF k = "R1" ELSE 1). SET dLast[k] TO ang. }
    ELSE IF m:HASFIELD("deploy angle") {
        m:SETFIELD("deploy angle", ang).
        SET dLast[k] TO ang.
    }
}

// ---------------------------------------------------------------- the locks (per axis, on every surface)
FUNCTION lockAxis {
    PARAMETER fld, lockIt.
    FOR s IN dAll { surfSetLock(s[0], fld, lockIt). }
}

// the brake sliders (the ground yaw): written only on a change; values between the slider's 5 % steps are pulsed
FUNCTION setBrk {
    PARAMETER i, k, pct.
    IF i < 0 { RETURN. }
    SET pct TO MAX(0, pct).
    IF dBkLast:HASKEY(k) AND ABS(dBkLast[k] - pct) < 0.01 { RETURN. }
    IF NOT modLive(dBk[i][0]) { RETURN. }
    dBk[i][0]:SETFIELD(dBk[i][1], pct).
    SET dBkLast[k] TO pct.
}
FUNCTION pwm5 {                // bv % -> the step below or above it, the duty = the fraction (YB_PWM ticks)
    PARAMETER bv.
    LOCAL lo IS FLOOR(bv / YB_STEP) * YB_STEP.
    IF MOD(dLoop, YB_PWM) < ROUND((bv - lo) / YB_STEP * YB_PWM) { RETURN lo + YB_STEP. }
    RETURN lo.
}
FUNCTION brkBase {             // a wheel's slider after WONG: the host's DAP_BRK_BASE, else the craft's value
    PARAMETER i.
    RETURN CHOOSE DAP_BRK_BASE IF DAP_BRK_BASE >= 0 ELSE dBk[i][2].
}
FUNCTION brkBack {             // every brake slider back to the craft's value
    IF dBkL >= 0 { setBrk(dBkL, "L", dBk[dBkL][2]). }
    IF dBkR >= 0 { setBrk(dBkR, "R", dBk[dBkR][2]). }
    IF dBkN >= 0 { setBrk(dBkN, "N", dBk[dBkN][2]). }
}
FUNCTION brkNow {              // the slider last written (else as found), for the log
    PARAMETER i, k.
    IF dBkLast:HASKEY(k) { RETURN dBkLast[k]. }
    IF i >= 0 { RETURN dBk[i][2]. }
    RETURN -1.
}
FUNCTION addMsg {
    PARAMETER s.
    IF dMsg = "" { SET dMsg TO s. } ELSE { SET dMsg TO dMsg + "; " + s. }
}
FUNCTION hdgNow {              // the nose's compass heading, deg (the log)
    PARAMETER fwd.
    LOCAL nv IS SHIP:NORTH:VECTOR.
    RETURN MOD(ARCTAN2(VDOT(fwd, VCRS(SHIP:UP:VECTOR, nv)), VDOT(fwd, nv)) + 360, 360).
}
// the HUD runway's centreline (the line through its two ends): y m (+ = right of it), y' m/s, the heading error deg
// (+ = the nose right of the runway direction); kOS VCRS(up, a heading) = its right side (VCRS(UP, NORTH) = EAST)
FUNCTION clGeom {
    PARAMETER fwd.
    LOCAL thr IS dGdRwyThr.                  // the landing runway (the guidance mode) ...
    LOCAL far IS dGdRwyFar.
    IF NOT dGdRwyOk {                        // ... else the HUD's
        SET thr TO hdRwys[hdRwyIx][2].
        SET far TO hdRwys[hdRwyIx][8].
    }
    LOCAL uv IS SHIP:UP:VECTOR.
    LOCAL hv IS VXCL(uv, far:POSITION - thr:POSITION):NORMALIZED.
    LOCAL rv IS VCRS(uv, hv):NORMALIZED.
    SET dClY TO VDOT(-thr:POSITION, rv).
    SET dClYd TO VDOT(SHIP:VELOCITY:SURFACE, rv).
    LOCAL fh IS VXCL(uv, fwd).
    SET dClDpsi TO ARCTAN2(VDOT(fh, rv), VDOT(fh, hv)).
}

// ---------------------------------------------------------------- dapInit: find everything, reset the state
// The elevons, the body flap and the rudder halves, found from SHIP (dAll, dElv, dRud, dFlap, dHaveFlap,
// dFlapAng, dRudHave). dapInit calls it at the start; dapTick calls it once after a splashdown's rebuild (surfListRefind).
FUNCTION dapFindSurfs {
    SET dAll TO LIST().
    SET dElv TO LIST().
    SET dRud TO LIST().
    SET dFlap TO 0.
    SET dHaveFlap TO FALSE.
    SET dFlapAng TO 0.
    FOR m IN SHIP:MODULESNAMED(SURF_MN) {
        LOCAL nm IS m:PART:NAME:TOLOWER.
        modReg(m, CHOOSE dRud:LENGTH IF nm:CONTAINS("rudder") ELSE 0).     // The 2nd rudder half is its own key (a frozen half is the only one skipped)
        LOCAL dep IS surfDep(m).
        LOCAL ang IS 0.
        IF dep AND surfHasAng(m) { SET ang TO surfGetAng(m, CHOOSE -1 IF (nm:CONTAINS("rudder") AND dRud:LENGTH = 1) ELSE 1). }
        IF nm:CONTAINS("elevon") OR nm:CONTAINS("bodyflap") OR nm:CONTAINS("rudder") {
            dAll:ADD(LIST(m, dep, ang, surfGetLock(m, "pitch"), surfGetLock(m, "yaw"), surfGetLock(m, "roll"))).
        }
        IF nm:CONTAINS("elevon") {
            LOCAL sd IS 1.
            IF VDOT(m:PART:POSITION, SHIP:FACING:STARVECTOR) < 0 { SET sd TO -1. }
            dElv:ADD(LIST(m, sd, "E" + dElv:LENGTH, ang)).
        } ELSE IF nm:CONTAINS("bodyflap") {
            SET dFlap TO m.
            SET dHaveFlap TO TRUE.
            SET dFlapAng TO ang.
        } ELSE IF nm:CONTAINS("rudder") {
            dRud:ADD(m).
        }
    }
    SET dRudHave TO dRud:LENGTH = 2.
    surfListMark("dap").
}

FUNCTION dapInit {
    SET dGmb TO 0.
    SET dGmbMod TO 0.
    SET dGmbHave TO FALSE.
    SET dGmbLock0 TO TRUE.
    SET dGmbLim0 TO -1.
    FOR eng IN SHIP:ENGINES {
        IF NOT dGmbHave AND eng:HASMODULE("ModuleGimbal") {
            IF eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering") OR eng:TITLE:CONTAINS("Viking") {
                SET dGmb TO eng.
                SET dGmbHave TO TRUE.
            }
        }
    }
    IF dGmbHave {
        dGmbReg().
        LOCAL gmod IS dGmbMod.
        SET dGmbLock0 TO dGmb:GIMBAL:LOCK.
        IF gmod:HASFIELD("gimbal limit") {
            SET dGmbLim0 TO gmod:GETFIELD("gimbal limit").
            IF modLive(gmod) { gmod:SETFIELD("gimbal limit", 1). }
        }
        SET dGmb:GIMBAL:LOCK TO FALSE.
    }

    IF SOCK_LOG AND NOT EXISTS("0:/logs") { CREATEDIR("0:/logs"). }   // the logs on (lib_logsw)
    SET D_T TO ROUND(TIME:SECONDS, 0).
    // a save loaded again starts at the same TIME:SECONDS: never append to an old log
    SET D_TAG TO "" + D_T.
    LOCAL dTagN IS 2.
    UNTIL NOT EXISTS("0:/logs/css_dap_" + D_TAG + ".csv") {
        SET D_TAG TO D_T + "_" + dTagN.
        SET dTagN TO dTagN + 1.
    }
    SET D_TXT TO "0:/logs/css_dap_" + D_TAG + ".txt".
    SET D_CSV TO "0:/logs/css_dap_" + D_TAG + ".csv".

    dapFindSurfs().

    SET dBk TO LIST().
    FOR m IN SHIP:MODULESNAMED("ModuleWheelBrakes") {
        LOCAL fld IS "".
        FOR f IN m:ALLFIELDNAMES { IF fld = "" AND f:TOLOWER:CONTAINS("brake") { SET fld TO f. } }
        IF fld <> "" {
            dBk:ADD(LIST(modReg(m), fld, m:GETFIELD(fld), VDOT(m:PART:POSITION, SHIP:FACING:FOREVECTOR),
                VDOT(m:PART:POSITION, SHIP:FACING:STARVECTOR))).
        }
    }
    SET dBkL TO -1.
    SET dBkR TO -1.
    SET dBkN TO -1.
    LOCAL bkFore IS -1E9.
    FOR bw IN dBk { IF bw[3] > bkFore { SET bkFore TO bw[3]. } }
    LOCAL bkI IS 0.
    UNTIL bkI >= dBk:LENGTH {
        IF dBk[bkI][3] = bkFore AND dBk:LENGTH > 2 { SET dBkN TO bkI. }
        ELSE IF dBk[bkI][4] < 0 { SET dBkL TO bkI. }
        ELSE { SET dBkR TO bkI. }
        SET bkI TO bkI + 1.
    }
    SET dBkHave TO dBkL >= 0 AND dBkR >= 0.

    // THE GEAR'S SUSPENSION, FORCED (GEAR_SPRING / GEAR_DAMPER, Override): the sliders by their names; KSP hides them
    // while Spring/Damper is Auto, so the toggle (an event) is pressed only then -- a correct setting is never flipped
    LOCAL gearN IS 0.
    LOCAL gearTxt IS "".
    FOR m IN SHIP:MODULESNAMED("ModuleWheelSuspension") {
        LOCAL sfd IS "".
        LOCAL dfd IS "".
        FOR f IN m:ALLFIELDNAMES {
            LOCAL fl IS f:TOLOWER.
            IF fl:CONTAINS("spring") AND NOT fl:CONTAINS("damper") { SET sfd TO f. }
            IF fl:CONTAINS("damper") AND NOT fl:CONTAINS("spring") { SET dfd TO f. }
        }
        IF sfd = "" OR dfd = "" {                        // hidden: Auto -> press it once, then look again
            FOR ev IN m:ALLEVENTNAMES { IF ev:TOLOWER:CONTAINS("spring/damper") { m:DOEVENT(ev). } }
            WAIT 0.
            FOR f IN m:ALLFIELDNAMES {
                LOCAL fl IS f:TOLOWER.
                IF fl:CONTAINS("spring") AND NOT fl:CONTAINS("damper") { SET sfd TO f. }
                IF fl:CONTAINS("damper") AND NOT fl:CONTAINS("spring") { SET dfd TO f. }
            }
        }
        IF sfd <> "" AND dfd <> "" {
            LOCAL s0 IS m:GETFIELD(sfd).
            LOCAL d0 IS m:GETFIELD(dfd).
            IF modLive(m) {
                m:SETFIELD(sfd, GEAR_SPRING).
                m:SETFIELD(dfd, GEAR_DAMPER).
            }
            SET gearN TO gearN + 1.
            SET gearTxt TO gearTxt + " " + m:PART:TITLE + " " + ROUND(s0, 2) + "/" + ROUND(d0, 2).
        } ELSE {
            SET gearTxt TO gearTxt + " " + m:PART:TITLE + " (sliders NOT found)".
        }
    }

    SET dSbOpen TO SB_OPEN.
    SET dSbTarget TO 0.
    IF dRudHave {
        IF surfDep(dRud[0]) AND surfDep(dRud[1]) AND surfHasAng(dRud[0]) {
            SET dSbTarget TO surfGetAng(dRud[0]).     // start where it is (bumpless); AG3: shut / SB_OPEN
            IF dSbTarget < 1 { SET dSbTarget TO 0. }
        }
    }
    SET dSbBase TO dSbTarget.
    SET dSbFlips TO 0.

    dapSay("=== CSS DAP -- " + SHIP:NAME + " -- " + dElv:LENGTH + " elevons, flap " + dHaveFlap + ", rudder halves "
        + dRud:LENGTH + " ===").
    IF dGmbHave {
        dapSay("  the stick: OMS gimbal on " + dGmb:TITLE + " -- wiggle it: the 'stick' numbers must move.").
    } ELSE {
        dapSay("  *** NO OMS GIMBAL FOUND -- the stick cannot be read: CSS is disabled.").
    }
    IF dElv:LENGTH <> 4 OR NOT dHaveFlap OR NOT dRudHave {
        dapSay("  *** expected 4 elevons, a body flap and 2 rudder halves -- check the log.").
    }
    FOR s IN dAll {
        IF SOCK_LOG { LOG "  " + s[0]:PART:TITLE + ": deploy " + s[1] + " at " + ROUND(s[2], 2) + ", ignore pitch " + s[3] + " yaw " + s[4]
            + " roll " + s[5] TO D_TXT. }
    }
    dapSay("  speedbrake: " + (CHOOSE ("open " + ROUND(dSbTarget, 1) + " a side") IF dSbTarget > 1 ELSE "shut")
        + "; AG3 toggles it shut / " + SB_OPEN + " a side (" + SB_RATE + " deg/s); in MAN the throttle lever drives it "
        + (CHOOSE "from the MAN press (the AFBW lever is live)" IF dapLevLive() ELSE "once kOS has seen the lever move") + " (0 % = " + RUD_HALF_LIM + " a side, 100 % = shut; above M" + SB_SUPER_MACH
        + " at most " + SB_SUPER_MAX + ").  Rudder law: "
        + (CHOOSE ("ON below M" + RUD_MACH + " in flight" + (CHOOSE ", one close scheme at every brake angle (the rudder "
        + "curve patch)" IF RUD_CURVE_PATCH ELSE ", brake <= " + SB_RUD_MAX + " a side / close 5-" + SB_CLOSE_MAX + " / open "
        + SB_SPLIT_MIN + "+ (28-31 skipped)")) IF RUD_ON ELSE "OFF") + ".").
    dapSay("  gear suspension: " + gearN + " wheel(s) set to spring " + GEAR_SPRING + " / damper " + GEAR_DAMPER
        + " (6_gear_suspension.cfg rev 4); found:" + gearTxt).
    IF dBkHave {
        LOCAL bkTxt IS "  ground yaw: the yaw stick brakes the mains (sliders L " + dBk[dBkL][2] + " / R " + dBk[dBkR][2].
        IF dBkN >= 0 { SET bkTxt TO bkTxt + ", nose " + dBk[dBkN][2]. }
        dapSay(bkTxt + " %; field '" + dBk[dBkL][1] + "'): " + ROUND(YB_BASE / MAX(1, BRK_TORQUE_K), 1) + " +- "
            + ROUND(YB_SPAN / MAX(1, BRK_TORQUE_K), 1) + " % before WONG (the DAP's brakes; torque x" + BRK_TORQUE_K + "), "
            + "the far main -" + ROUND(2 * YB_SPAN / MAX(1, BRK_TORQUE_K), 1) + " % after (yours, B), <= " + YB_MAX + " %.").
    } ELSE {
        dapSay("  *** no brake slider found on both mains: the ground yaw is off.").
    }
    IF DEFINED AL_DEROT_RATE { SET DR_RATE_SEMI TO AL_DEROT_RATE. }      // the guidance's rate (alg_const)
    dapSay("  ROLLOUT AUTO = the centreline from main-gear contact (the ROLLOUT button, or a yaw stick past "
        + ROUND(100 * CL_HOT) + " % for " + CL_HOT_T + " s, takes it); DEROTATION AUTO = a nose-down stick past "
        + ROUND(100 * DR_TRIG) + " % on the mains (" + DR_RATE + " deg/s; then the pitch stick is ignored until the nose gear).").
    IF DAP_AUTO_GUID {
        dapSay("  GUIDED: the ROLLOUT button governs the derotation: AUTO at the guidance's rate, CSS on a nose-down stick past "
            + ROUND(100 * DR_TRIG) + " % (then the guidance's rate, " + DR_RATE_SEMI + " deg/s before it asks one).").
    }
    dapSay("  loops: pitch " + LOOP_P + " /s at " + Q_REF + " kPa (" + LOOP_P_SUP + " above M" + DAP_SUP_MACH + "), roll "
        + LOOP_R + " /s; stick signs pitch " + STICK_P_SIGN
        + " roll " + STICK_R_SIGN + "; zero the KSP trim (Alt+X) before CSS: it reads as stick.").

    SET dLast TO LEXICON().
    FOR s IN dAll {
        IF NOT surfDep(s[0]) AND NOT surfFrozen(s[0]) { surfDeploy(s[0]). }     // A FROZEN surface found un-deployed stays so (deployed it swings to its stored angle: the design's 25)
    }
    LOCAL tWait IS TIME:SECONDS + 2.
    // write the intended angles AT ONCE and on every tick of the wait: a surface found un-deployed must not slew toward
    // its stored deploy angle (the craft's: elevons 25, flap 20, rudder halves 35)
    UNTIL TIME:SECONDS > tWait {
        FOR ev IN dElv { setAng(ev[0], ev[2], ev[3]). }
        IF dHaveFlap { setAng(dFlap, "F", dFlapAng). }
        IF dRudHave {
            setAng(dRud[0], "R0", dSbBase).
            setAng(dRud[1], "R1", dSbBase).
        }
        LOCAL allOk IS TRUE.
        FOR s IN dAll { IF NOT surfHasAng(s[0]) { SET allOk TO FALSE. } }
        IF allOk { BREAK. }
        WAIT 0.
    }
    SET dElev TO 0.
    FOR ev IN dElv { SET dElev TO dElev + ev[3] / MAX(dElv:LENGTH, 1). }
    IF ABS(dElev) < 0.01 { SET dElev TO 0. }

    // the GUI requests and the state
    SET dReqP TO FALSE.
    SET dReqR TO FALSE.
    SET dReqEnd TO FALSE.
    SET dMsg TO "".
    SET dClReq TO TRUE.
    SET dCssP TO FALSE.
    SET dCssR TO FALSE.
    SET dTrimE TO -(dElev - tabLook(SBX_TAB, dapMach()) * dSbBase).
    SET dTrimA TO 0.
    SET dAil TO 0.
    SET dRudC TO 0.
    SET dQturnF TO 0.
    SET dRows TO LIST().
    SET dFtOn TO FALSE.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("FTGROUNDCOLS") { SET dFtOn TO TRUE. } }
    SET dLoop TO 0.
    SET dSasOff TO 0.
    SET dRelock TO 0.
    SET dDone TO FALSE.
    SET dGnd TO FALSE.
    SET dCtc TO FALSE.
    SET dCtcElev TO 0.
    SET dGndTh TO 0.
    SET dWong TO FALSE.
    SET dWongT TO 0.
    SET dYb TO 0.
    SET dYbU TO 0.
    SET dBetaC TO 0.
    SET dBkLast TO LEXICON().
    SET dBkSfT TO -1.
    SET dBkSfBack TO 0.
    SET dClAct TO FALSE.
    SET dClPrev TO FALSE.
    SET dClY TO 0.
    SET dClYd TO 0.
    SET dClDpsi TO 0.
    SET dClPsiC TO 0.
    SET dClUb TO 0.
    SET dClUr TO 0.
    SET dClHotT TO 0.
    SET dDerot TO FALSE.
    SET dDrQ TO 0.
    SET dDrI TO 0.
    SET dChuteLiftT TO 0.
    SET dChuteCutReq TO FALSE.
    SET dHud TO FALSE.
    SET dHudLblT TO 0.
    SET dGdOn TO FALSE.
    SET dGdAlpha TO 0.
    SET dGdAlphaDot TO 0.
    SET dGdAlphaT TO -1.
    SET dGdAlphaDt TO 0.24.
    SET dTickT TO -1.
    SET DT TO DT_1X.
    SET dGdNz TO 1.
    SET dGdBank0 TO dapBank().
    SET dGdBank1 TO dGdBank0.
    SET dGdBankT TO TIME:SECONDS.
    SET dGdBankDt TO 1.
    SET dGdSb TO dSbBase.
    SET dGdDerot TO 0.
    SET dGdWow TO FALSE.
    SET dGdWong TO FALSE.
    SET dGdHm TO 1E9.
    SET dGdRwyOk TO FALSE.
    SET dSbAuto TO DAP_AUTO_GUID.
    SET dSbLever TO FALSE.
    SET dThr0 TO SHIP:CONTROL:PILOTMAINTHROTTLE.
    SET dThrPilot TO dThr0.
    SET dYawLk TO TRUE.
    SET dRelockN TO 0.
    SET dQa TO 0.
    SET dVhPrev TO V(0, 0, 0).
    SET dVhT TO -1.
    SET dPathQ TO 0.
    SET dNzM TO 1.
    SET dAc0 TO 0.
    SET dAcT TO -1.
    SET dAcNow TO 0.
    SET dPa TO 0.
}

// the guidance's bank command now (the ship's sign), ramped over its cycle -> LIST(bank, rate)
FUNCTION dapGdBank {
    LOCAL f IS (TIME:SECONDS - dGdBankT) / MAX(dGdBankDt, 0.02).
    IF f >= DAP_RAMP_HOLD { RETURN LIST(dGdBank1, 0). }          // the rate held to the next publication (DAP_RAMP_HOLD)
    RETURN LIST(dGdBank0 + (dGdBank1 - dGdBank0) * MIN(1, MAX(0, f)), (dGdBank1 - dGdBank0) / MAX(dGdBankDt, 0.02)).
}

// ---------------------------------------------------------------- dapGuiBuild: the window
// the SPDBK AUTO / CSS button on row rw (dBtnSb), wherever it is missing
FUNCTION dapSbBtn {
    PARAMETER rw.
    SET dBtnSb TO rw:ADDBUTTON(CHOOSE "SPDBK AUTO" IF dSbAuto ELSE "SPDBK CSS").
    // pressed = CSS (AUTO is the non-pressed option, like PITCH and ROLL/YAW)
    SET dBtnSb:TOGGLE TO TRUE.
    SET dBtnSb:PRESSED TO NOT dSbAuto.
    SET dBtnSb:ONTOGGLE TO { PARAMETER val. SET dSbAuto TO NOT val. SET dBtnSb:TEXT TO CHOOSE "SPDBK CSS" IF val
        ELSE "SPDBK AUTO". }.
}
// the crew's downmode buttons on row rw (grey until dapDmShow opens them)
FUNCTION dapDmBtns {
    PARAMETER rw, rw2 IS 0.                 // rw2 = VERT SIT's second row (< SITE >, SW RWY), else all on rw
    LOCAL r2 IS CHOOSE rw IF rw2:ISTYPE("Scalar") ELSE rw2.
    SET dRowDm TO rw.
    // < SITE > first: the arrows browse the sites in a fixed order (lib_land ldSiteTick; always live), the middle button takes the
    // site shown (live as SW RWY: taemg_rwy_rej, dapDmShow), its label the current runway or "TO <end> <nm> NM";
    // OTT STRT / OTT MEP on rw, then < SITE > and SW RWY on r2
    SET dBtnStrt TO rw:ADDBUTTON("OTT STRT").
    SET dBtnMep TO rw:ADDBUTTON("OTT MEP").
    SET dBtnSiteL TO r2:ADDBUTTON("<").
    SET dBtnSite TO r2:ADDBUTTON("SITE").
    SET dBtnSiteR TO r2:ADDBUTTON(">").
    SET dBtnSiteL:ONCLICK TO { SET dSiteStep TO -1. }.
    SET dBtnSiteR:ONCLICK TO { SET dSiteStep TO 1. }.
    SET dBtnSite:ONCLICK TO { IF dSiteNm <> "" { SET dSiteReq TO dSiteNm. SET dDmReq TO "site".
        SET dBtnSite:TEXT TO dapDmWait(dBtnSite:TEXT). } }.
    SET dBtnSite:ENABLED TO FALSE.
    SET dSiteStep TO 99.
    SET dSiteNm TO "".
    SET dBtnRwy TO r2:ADDBUTTON("SW RWY").
    SET dBtnStrt:ONCLICK TO { SET dDmReq TO "strt". SET dBtnStrt:TEXT TO dapDmWait(dBtnStrt:TEXT). }.
    SET dBtnMep:ONCLICK TO { SET dDmReq TO "mep". SET dBtnMep:TEXT TO dapDmWait(dBtnMep:TEXT). }.
    SET dBtnRwy:ONCLICK TO { SET dDmReq TO "rwy". SET dBtnRwy:TEXT TO dapDmWait(dBtnRwy:TEXT). }.
    SET dBtnStrt:ENABLED TO FALSE.
    SET dBtnMep:ENABLED TO FALSE.
    SET dBtnRwy:ENABLED TO FALSE.
}

GLOBAL DAP_ARW_W IS 20.                 // px, < and >'s width (inside their 2 x 4 px margins)
GLOBAL DAP_GAP IS 4.                    // px between two buttons (GUILayout collapses the 4 px margins)

FUNCTION dapSiteArrows {               // < and > narrow, the row's height
    FOR bt IN LIST(dBtnSiteL, dBtnSiteR) {
        IF NOT bt:ISTYPE("Scalar") {
            SET bt:STYLE:HSTRETCH TO FALSE.
            SET bt:STYLE:WIDTH TO DAP_ARW_W.
            SET bt:STYLE:HEIGHT TO TD_ROW_H - 4.
        }
    }
}

// VERT SIT's two rows as a 2 x 4 grid, the DAP's items on the left, the OTT's on the right (PITCH | SPDBK | STRT | MEP /
// ROLL/YAW | ROLLOUT | SITE | SW RWY), each column a quarter of row rw's width less the margins (GUILayout collapses the
// 4 px margins between buttons, so the 4 buttons + 3 x 4 + the 4 px each side = the row; was cw - 8: 12 px slack on the right);
// the SITE column holds < SITE >
FUNCTION dapGrid {
    PARAMETER rw.
    LOCAL bw IS (rw:STYLE:WIDTH - 20) / 4.   // 4 buttons + 3 x 4 px between + 2 x 4 px margins = the row: equal left / right gap
    FOR bt IN LIST(dBtnP, dBtnSb, dBtnStrt, dBtnMep, dBtnR, dBtnCl, dBtnRwy) {
        IF NOT bt:ISTYPE("Scalar") {
            SET bt:STYLE:HSTRETCH TO FALSE.
            SET bt:STYLE:WIDTH TO bw.
        }
    }
    IF NOT dBtnSite:ISTYPE("Scalar") {
        SET dBtnSite:STYLE:HSTRETCH TO FALSE.
        SET dBtnSite:STYLE:WIDTH TO bw - 2 * (DAP_ARW_W + DAP_GAP).   // < SITE > = the column above
    }
}

// THE LOOK is lib_guistyle's: the title bar (+ a grey subtitle), the sections CONTROL (the modes), HUD (the camera, the
// runway), STATUS (the HUD line, the air data, landRun's line), END apart.
// grd TRUE (the GRTLS, lib_grdap) builds TAEM's whole row (PITCH, ROLL/YAW, SPDBK, ROLLOUT, OTT STRT, OTT MEP, SW RWY):
// PITCH, ROLL/YAW and SPDBK live (lib_grdap flies them), ROLLOUT and the three OTT grey. HORIZ SIT's row is HUD (a third
// of HUD CAM's width; it shows / hides the HUD, off by default), HUD CAM, BAILOUT in both phases; the HUD starts as
// hdVis says (the GRTLS: off, TAEM: on). TAEM after the GRTLS keeps the row and reads the GRTLS's choices back (dapInit
// reset them).
FUNCTION dapGuiBuild {
    PARAMETER title, sub IS "", live IS TRUE, grd IS FALSE.
    IF NOT dGui:ISTYPE("Scalar") { dGui:DISPOSE(). }   // a window of the GRTLS's (no pages) does not stay up
    // With the pages up (lib_taemdisp's tdRowV / tdRowH) the CONTROL buttons go into VERT SIT's row and HUD CAM fills
    // HORIZ SIT's, built once (a second call, landRun's after the GRTLS's, keeps them and their state); the window is still
    // built (its STATUS lines are written to; lib_land reads its subtitle) but never shown. Without the pages: the window.
    // live FALSE (the GRTLS: no DAP flies yet) greys the mode buttons; landRun's call (live) opens them.
    LOCAL pg IS FALSE.
    LOCAL rv IS 0.
    LOCAL rv2 IS 0.                     // VERT SIT's second row (the guidance's choices)
    LOCAL two IS FALSE.
    LOCAL rh IS 0.
    IF DEFINED tdRowV {                 // ENTRY TRAJ's windows (lib_taemdisp tdDeck, from EI) count as the pages
        LOCAL tdUp IS tdOn.
        IF DEFINED tdDeck { IF tdDeck { SET tdUp TO TRUE. } }
        IF tdUp AND NOT tdRowV:ISTYPE("Scalar") { SET pg TO TRUE. SET rv TO tdRowV. SET rh TO tdRowH.
            SET two TO NOT tdRowV2:ISTYPE("Scalar"). SET rv2 TO CHOOSE tdRowV2 IF two ELSE tdRowV. } }
    LOCAL fresh IS TRUE.
    IF pg { SET fresh TO rv:WIDGETS:LENGTH = 0. }
    SET dGui TO uiBox(title, 300, 40, 160, sub).
    LOCAL secC IS uiSection(dGui, "CONTROL").
    IF fresh {
        SET dRow TO CHOOSE rv IF pg ELSE secC:ADDHLAYOUT().
        LOCAL rB IS CHOOSE rv2 IF two ELSE dRow.   // VERT SIT's grid: ROLL/YAW under PITCH, ROLLOUT under SPDBK
        // labelled from dReqP / dReqR (OPS 1's axes: lib_grdap's first grdTick took them before these buttons existed),
        // so a CSS axis carried from OPS 1 reads CSS
        SET dBtnP TO dRow:ADDBUTTON(CHOOSE "PITCH  CSS" IF dReqP ELSE "PITCH  AUTO").
        SET dBtnR TO rB:ADDBUTTON(CHOOSE "ROLL/YAW  CSS" IF dReqR ELSE "ROLL/YAW  AUTO").
        SET dBtnP:TOGGLE TO TRUE.
        SET dBtnR:TOGGLE TO TRUE.
        SET dBtnP:PRESSED TO dReqP.         // OPS 1's CSS axes carried (lib_grdap grdStart); before the ONTOGGLEs
        SET dBtnR:PRESSED TO dReqR.
        SET dBtnP:ONTOGGLE TO { PARAMETER val. SET dReqP TO val. }.
        SET dBtnR:ONTOGGLE TO { PARAMETER val. SET dReqR TO val. }.
        SET dRow2 TO CHOOSE rv IF pg ELSE secC:ADDHLAYOUT().
        IF DAP_AUTO_GUID OR grd { dapSbBtn(dRow2). }   // the speedbrake's source: the guidance (AUTO) or AG3 (MAN)
        SET dClReq TO TRUE.
        LOCAL rC IS CHOOSE rB IF two ELSE dRow2.   // ROLLOUT under SPDBK
        SET dBtnCl TO rC:ADDBUTTON("ROLLOUT AUTO").
        // pressed = CSS (AUTO is the non-pressed option, like PITCH and ROLL/YAW)
        SET dBtnCl:TOGGLE TO TRUE.
        SET dBtnCl:PRESSED TO FALSE.
        SET dBtnCl:ONTOGGLE TO { PARAMETER val. SET dClReq TO NOT val. SET dBtnCl:TEXT TO CHOOSE "ROLLOUT CSS" IF val
            ELSE "ROLLOUT AUTO". }.
        // THE CREW'S DOWNMODES IN THEIR OWN ROW (on the page: the one row): plain buttons; a click asks the guidance's next
        // cycle (lib_land hands dDmReq over); grey until dapDmShow opens them in the acquisition phase. SW RWY: the runway's
        // other end + the straight-in, before the HAC; no message. Each a TOGGLE: pressed again it undoes itself (OTT OVHD /
        // OTT NEP / SW RWY back; dapDmShow's labels).
        IF DAP_AUTO_GUID OR grd {
            SET dRowDm TO CHOOSE rv IF pg ELSE secC:ADDHLAYOUT().    // OTT STRT / MEP on row 1, < SITE > and
            dapDmBtns(dRowDm, CHOOSE rv2 IF two ELSE 0).           //   SW RWY on row 2
        }
        LOCAL secH IS uiSection(dGui, "HUD").
        SET dRow3 TO CHOOSE rh IF pg ELSE secH:ADDHLAYOUT().
        SET dBtnHud TO dRow3:ADDBUTTON(CHOOSE "HUD ON" IF hdVis ELSE "HUD OFF").   // pressed = shown
        SET dBtnHud:TOGGLE TO TRUE.
        SET dBtnHud:PRESSED TO hdVis.
        SET dBtnHud:ONTOGGLE TO {
            PARAMETER val.
            SET hdVis TO val.
            SET dBtnHud:TEXT TO CHOOSE "HUD ON" IF val ELSE "HUD OFF".
            IF val AND NOT hdOK { SET dHudReq TO TRUE. }   // the GRTLS: loaded by its loop (lib_grdap grdHudPass)
        }.
        SET dBtnCam TO dRow3:ADDBUTTON("HUD CAM OFF").
        SET dBtnCam:TOGGLE TO TRUE.
        IF hdCamLive() { SET dBtnCam:PRESSED TO TRUE. SET dBtnCam:TEXT TO "HUD CAM ON". }   // OPS 1's camera kept
        SET dBtnCam:ONTOGGLE TO {
            PARAMETER val.
            IF val {
                IF NOT hdOK {           // the GRTLS before the HUD has loaded: its loop loads it, then the camera
                    SET dHudReq TO TRUE.
                    SET dCamWant TO TRUE.
                    SET dBtnCam:TEXT TO "HUD CAM ...".
                } ELSE IF hdCamSnap() {
                    SET dBtnCam:TEXT TO "HUD CAM ON".
                } ELSE {
                    addMsg("HUD CAM: no free camera here (kOS StockCamera 0.3.1; not in IVA / map)").
                    SET dBtnCam:PRESSED TO FALSE.
                }
            } ELSE {
                SET dCamWant TO FALSE.
                hdCamRelease().
                SET dBtnCam:TEXT TO "HUD CAM OFF".
            }
        }.
        SET dBtnCam:ENABLED TO grd.     // on once the HUD has loaded (dapHudInit); the GRTLS loads it on a press
        // BAILOUT beside HUD CAM (the right 20 % of HORIZ SIT's row): bailout mode, two presses at least 1 s apart; live in
        // the GRTLS too (live greys the mode buttons only)
        SET dBtnBail TO dRow3:ADDBUTTON("BAILOUT").
        uiDispWarn(dBtnBail).           // a guarded action (orange edge; UI_DISP FALSE: as before)
        SET dBtnBail:ONCLICK TO { dapBailPress(). }.
        SET dBailReq TO FALSE.
        SET dBailT1 TO -1.
        SET dBailOn TO FALSE.
        IF pg {                         // the page rows' buttons share the row's width (HUD CAM all of HORIZ SIT's)
            FOR bt IN rv:WIDGETS { SET bt:STYLE:HSTRETCH TO TRUE. SET bt:STYLE:HEIGHT TO TD_ROW_H - 4. }
            IF two { FOR bt IN rv2:WIDGETS { SET bt:STYLE:HSTRETCH TO TRUE. SET bt:STYLE:HEIGHT TO TD_ROW_H - 4. } }
            dapSiteArrows().
            IF two { dapGrid(rv). }         // the 2 x 4 grid
            SET dBtnHud:STYLE:HSTRETCH TO FALSE.    // HUD a third of HUD CAM's old 80 % (its 2 x 4 px margins
            SET dBtnHud:STYLE:WIDTH TO ROUND(rh:STYLE:WIDTH * 0.8 / 3) - 8.   //   inside it), HUD CAM the rest
            SET dBtnHud:STYLE:HEIGHT TO TD_ROW_H - 4.
            SET dBtnCam:STYLE:HSTRETCH TO TRUE.
            SET dBtnCam:STYLE:HEIGHT TO TD_ROW_H - 4.
            SET dBtnBail:STYLE:HSTRETCH TO FALSE.   // BAILOUT the right 20 % of the row (its 2 x 4 px margins inside it),
            SET dBtnBail:STYLE:WIDTH TO ROUND(rh:STYLE:WIDTH * 0.2) - 8.   //   HUD CAM the rest
            SET dBtnBail:STYLE:HEIGHT TO TD_ROW_H - 4.
        }
        IF DEFINED FL_HAND { IF fuiHas() {      // "!" after BAILOUT: the FAILURES window; HUD CAM (stretched) gives it the room
            SET dBtnFail TO dRow3:ADDBUTTON("!").
            SET dBtnFail:STYLE:HSTRETCH TO FALSE.
            SET dBtnFail:STYLE:WIDTH TO 34.
            IF pg { SET dBtnFail:STYLE:HEIGHT TO TD_ROW_H - 4. }
            SET dBtnFail:ONCLICK TO { dapFailBang(). }.
        } }
        // ALT MODE in its own row under HUD / HUD CAM / BAILOUT: the HUD's altitude, RDR (the radar's below
        // HD_RADALT_FT, ASL above) or RWY (above the runway, its letter W); pressed = RWY. OPS 1's BARO goes back to RDR
        IF NOT (DEFINED hdAltMode) { GLOBAL hdAltMode IS "RDR". }
        IF hdAltMode <> "RWY" { SET hdAltMode TO "RDR". }
        LOCAL rA IS 0.
        IF pg { SET rA TO tdRowH2. }
        IF rA:ISTYPE("Scalar") { SET rA TO secH:ADDHLAYOUT(). }
        SET dBtnAlt TO rA:ADDBUTTON("ALT MODE " + hdAltMode).
        SET dBtnAlt:TOGGLE TO TRUE.
        SET dBtnAlt:PRESSED TO hdAltMode = "RWY".
        SET dBtnAlt:ONTOGGLE TO { PARAMETER val. SET hdAltMode TO CHOOSE "RWY" IF val ELSE "RDR".
            SET dBtnAlt:TEXT TO "ALT MODE " + hdAltMode. }.
        SET dBtnAlt:STYLE:HSTRETCH TO TRUE.
        IF pg { SET dBtnAlt:STYLE:HEIGHT TO TD_ROW_H - 4. }
        IF pg AND DEFINED TD_TRKUP {        // HORIZ SIT's page: track up (the ground track up, the runway turns) or
            SET dBtnTu TO rA:ADDBUTTON(CHOOSE "TRK UP" IF TD_TRKUP ELSE "RWY UP").   //   runway up (as flown before); pressed = RWY UP
            SET dBtnTu:TOGGLE TO TRUE.
            SET dBtnTu:PRESSED TO NOT TD_TRKUP.
            SET dBtnTu:ONTOGGLE TO { PARAMETER val. SET TD_TRKUP TO NOT val.
                SET dBtnTu:TEXT TO CHOOSE "TRK UP" IF TD_TRKUP ELSE "RWY UP". }.
            SET dBtnTu:STYLE:HSTRETCH TO TRUE.
            SET dBtnTu:STYLE:HEIGHT TO TD_ROW_H - 4.
        }
    } ELSE {
        SET dClReq TO NOT dBtnCl:PRESSED.   // the row kept (the GRTLS's): its state goes on (pressed = CSS)
        SET dReqP TO dBtnP:PRESSED.         // the GRTLS's PITCH / ROLL/YAW / SPDBK choices (dapInit reset them)
        SET dReqR TO dBtnR:PRESSED.
        IF NOT dBtnSb:ISTYPE("Scalar") { SET dSbAuto TO NOT dBtnSb:PRESSED. }
        IF DAP_AUTO_GUID AND dBtnSb:ISTYPE("Scalar") {   // the GRTLS's row has none (DAP_AUTO_GUID came on since)
            dapSbBtn(dRow2).
            dapDmBtns(CHOOSE rv IF pg ELSE dRow2, CHOOSE rv2 IF two ELSE 0).   // OTT on row 1, SITE / SW RWY row 2
            FOR bt IN LIST(dBtnSb, dBtnSite, dBtnStrt, dBtnMep, dBtnRwy) {
                SET bt:STYLE:HSTRETCH TO TRUE.
                SET bt:STYLE:HEIGHT TO TD_ROW_H - 4.
            }
            dapSiteArrows().
            IF two { dapGrid(rv). }
        }
    }
    SET dDmReq TO "".
    FOR bt IN LIST(dBtnP, dBtnR, dBtnCl) { SET bt:ENABLED TO live. }
    IF DAP_AUTO_GUID AND NOT dBtnSb:ISTYPE("Scalar") { SET dBtnSb:ENABLED TO live. }
    IF pg AND NOT dBtnTu:ISTYPE("Scalar") { SET dBtnTu:ENABLED TO sub <> "ENTRY". }   // TRK UP / RWY UP: grey in the entry (no HORIZ SIT page yet), on from the GRTLS and TAEM
    IF grd {                            // the GRTLS DAP flies PITCH, ROLL/YAW and SPDBK; ROLLOUT grey; OTT
                                        //   grey until the GRTLS's first guidance cycle (grtlsDmShow)
        SET dBtnP:ENABLED TO TRUE.
        SET dBtnR:ENABLED TO TRUE.
        SET dBtnSb:ENABLED TO TRUE.
    }
    SET dStat TO uiSection(dGui, "STATUS").
    SET dLblHud TO uiNote(dStat, "").
    SET dLbl TO uiText(dStat, "").
    dGui:ADDSPACING(UI_GAP).
    SET dBtnEnd TO uiSecondary(dGui, "END").
    SET dBtnEnd:ONCLICK TO { SET dReqEnd TO TRUE. }.
    IF NOT dGmbHave {
        SET dBtnP:ENABLED TO FALSE.
        SET dBtnR:ENABLED TO FALSE.
    }
    IF NOT pg { dGui:SHOW(). }          // with the pages the window stays hidden (STATUS and END unseen)
}

// ---------------------------------------------------------------- BAILOUT, two presses at least 1 s apart
FUNCTION dapFailBang {                      // the "!" button: the window right of the panel it is in (VERT SIT when up, else the DAP window dGui), toggled
    LOCAL x IS 68.
    LOCAL y IS 20.
    LOCAL onTd IS FALSE.
    // dapGuiBuild's tdUp is a LOCAL there, so DEFINED tdUp was never TRUE here (the branch was dead: the "!" went
    // right of the hidden DAP window, on top of VERT SIT). VERT SIT is up when the pages are drawn (tdOn) or the deck's
    // windows are (tdDeck): the same test as dapGuiBuild's.
    IF DEFINED tdOn AND DEFINED tdGuiV AND DEFINED tdGeo {
        IF (tdOn OR tdDeck) AND tdGuiV:ISTYPE("GUI") AND tdGeo:HASKEY("png_w") { SET onTd TO TRUE. SET x TO MAX(0, tdGuiV:X + tdGeo["png_w"][0] + 8). SET y TO MAX(0, tdGuiV:Y). }
    }
    // VERT SIT is not up: the window goes right of the DAP window (dapGuiBuild's uiBox, 300 px), not at the screen's left over it
    IF NOT onTd AND dGui:ISTYPE("GUI") { SET x TO MAX(0, dGui:X + 300 + 8). SET y TO MAX(0, dGui:Y). }
    fuiToggle(x, y).
}
FUNCTION dapBailPress {                     // the click: the first arms (CONFIRM); a second DAP_BAIL_GAP .. DAP_BAIL_WIN s after
    IF NOT (dBailReq OR dBailOn) {          //   it confirms (latched, no undo); one sooner is ignored; later: a first again
        LOCAL dt IS TIME:SECONDS - dBailT1.
        IF dBailT1 >= 0 AND dt <= DAP_BAIL_WIN {
            IF dt >= DAP_BAIL_GAP {
                SET dBailReq TO TRUE.
                SET dBtnBail:TEXT TO "BAIL ARMED".
            }
        } ELSE {
            SET dBailT1 TO TIME:SECONDS.
            SET dBtnBail:TEXT TO "CONFIRM".
        }
    }
}

FUNCTION dapBailTick {                      // each pass of the GRTLS's / TAEM's loop: a first press unconfirmed for
    IF NOT dBtnBail:ISTYPE("Scalar") AND NOT (dBailReq OR dBailOn) AND dBailT1 >= 0 {   //   DAP_BAIL_WIN s is dropped
        IF TIME:SECONDS - dBailT1 > DAP_BAIL_WIN {
            SET dBailT1 TO -1.
            SET dBtnBail:TEXT TO "BAILOUT".
        }
    }
}

FUNCTION dapBailFlies {                     // the hold flies (the crew's, or a BLUE's own): the button says so
    IF NOT dBailOn {
        SET dBailOn TO TRUE.
        IF NOT dBtnBail:ISTYPE("Scalar") { SET dBtnBail:TEXT TO "BAILOUT ON". }
    }
}

// ---------------------------------------------------------------- dapDmLive / dapDmRec: the downmodes' state, ONE rule for
// the buttons and the displays. LIVE exactly while VERT SIT draws the EMOH arrow (OTT STRT) / the MEP mark (OTT MEP)
// (lib_taemdisp tdVs's conditions), never once taken (the undo is dapDmShow's; MEP closes the straight-in);
// RECOMMENDED = live and the guidance's own alert up (OHALRT / below EMEP: what the automatic policy would act on).
FUNCTION dapDmLive {                        // -> LIST(OTT STRT live, OTT MEP live)
    PARAMETER tg.
    LOCAL acq IS tg["iphase"] = TG_IPH_ACQ OR tg["iphase"] = TG_IPH_STURN.   // the acquisition phase and the S-turn
    RETURN LIST((NOT tg["strt"]) AND acq AND tg["strt_avail"]   // under MEP too
                AND tg["drpred"] > taemg_drpred_of(TG_RMOH)
                AND tg["t_to_hac"] >= TG_DM_T_HAC_STRT,
                tg["nep"] AND acq AND tg["mep_avail"] AND tg["t_to_hac"] >= TG_DM_T_HAC_MEP).
}

// the OTT message the HUD and the TAEM windows show (lib_land's ldDmShow): the downmodes RECOMMENDED now, in the
// ladder's order ("OTT STRT", "OTT MEP" or "OTT STRT OTT MEP"), "" when none: never after one is taken (a message for a
// downmode already flown tells the crew nothing). The buttons' "!" is the same test (dapDmMepRec for OTT MEP).
FUNCTION dapDmRec {
    PARAMETER tg.
    LOCAL lv IS dapDmLive(tg).
    LOCAL m IS "".
    IF lv[0] AND tg["ohalrt"] { SET m TO TG_DM_MSG_STRT. }
    IF dapDmMepRec(tg, lv) { SET m TO (m + " " + TG_DM_MSG_MEP):TRIM. }
    RETURN m.
}

// OTT MEP recommended: live and below EMEP, and VERT SIT's MEP mark (EOW - EN = emep - en) or the energy itself (EOW - EN)
// at or below its overbright low-energy tick (-TG_EMIN_DELTA: emep <= emin or eow <= emin). Only with both above the tick
// is the energy inside the margins: no message.
FUNCTION dapDmMepRec {
    PARAMETER tg, lv.
    RETURN lv[1] AND tg["mep"] AND (tg["emep"] <= tg["emin"] OR tg["eow"] <= tg["emin"]).
}

// a pressed downmode button's label until the guidance's next cycle answers (dapDmShow): its label, no "!", + " ..."
FUNCTION dapDmWait {
    PARAMETER s.
    SET s TO s:REPLACE(" !", "").
    RETURN CHOOSE s IF s:ENDSWITH(" ...") ELSE s + " ...".
}

// ---------------------------------------------------------------- dapDmShow: the downmode row after a guidance cycle
// GREY outside the acquisition phase and the S-turn and once closed; LIVE and "!" by dapDmLive / dapDmRec's rule (above).
// Once taken the button UNDOES it: OTT OVHD (back to the overhead; live in the acquisition phase or the S-turn, the HAC
// >= TG_DM_T_HAC_STRT s away, under MEP too) and OTT NEP (back to NEP; the acquisition phase or the S-turn, >= TG_DM_T_HAC_MEP s),
// never a "!". SW RWY: live while taemg_rwy_rej has no reason (the acquisition phase, the switch back in the S-turn too,
// not after MEP), never a "!"; its label the other end's number (dRwyAlt, from lib_land: after a switch the runway it
// came from).
FUNCTION dapDmShow {
    PARAMETER tg.
    IF NOT (DAP_AUTO_GUID OR dDmGr) OR dBtnStrt:ISTYPE("Scalar") { RETURN. }
    LOCAL lv IS dapDmLive(tg).
    LOCAL und IS tg["iphase"] = TG_IPH_ACQ OR tg["iphase"] = TG_IPH_STURN.    // where an undo is taken
    IF tg["strt"] {
        SET dBtnStrt:TEXT TO "OTT OVHD".
        SET dBtnStrt:ENABLED TO und AND tg["t_to_hac"] >= TG_DM_T_HAC_STRT.   // the undo under MEP too
    } ELSE {
        SET dBtnStrt:TEXT TO CHOOSE "OTT STRT !" IF lv[0] AND tg["ohalrt"] ELSE "OTT STRT".
        SET dBtnStrt:ENABLED TO lv[0].
    }
    IF NOT tg["nep"] {
        SET dBtnMep:TEXT TO "OTT NEP".
        SET dBtnMep:ENABLED TO und AND tg["t_to_hac"] >= TG_DM_T_HAC_MEP.
    } ELSE {
        SET dBtnMep:TEXT TO CHOOSE "OTT MEP !" IF dapDmMepRec(tg, lv) ELSE "OTT MEP".
        SET dBtnMep:ENABLED TO lv[1].
    }
    SET dBtnRwy:TEXT TO ("SW RWY " + dRwyAlt:SUBSTRING(MAX(dRwyAlt:LENGTH - 2, 0), MIN(dRwyAlt:LENGTH, 2))):TRIM.
    SET dBtnRwy:ENABLED TO taemg_rwy_rej(tg, dRwyAlt <> "") = "".
    IF NOT dBtnSite:ISTYPE("Scalar") {      // the site shown taken as SW RWY's switch is
        SET dBtnSite:ENABLED TO dSiteNm <> "" AND taemg_rwy_rej(tg, TRUE) = "".
    }
}

// ---------------------------------------------------------------- dapHudInit: the HUD (lib_hud), then its buttons
FUNCTION dapHudInit {
    SET dLblHud:TEXT TO "HUD: loading...".
    SET hdVis TO TRUE.                  // TAEM starts with the HUD on
    IF NOT dBtnHud:ISTYPE("Scalar") { SET dBtnHud:PRESSED TO TRUE. SET dBtnHud:TEXT TO "HUD ON". }
    SET dHudReq TO FALSE.
    IF hdOK { SET dHud TO TRUE. } ELSE { SET dHud TO hdInit(). }   // the GRTLS's HUD (hdInit is not re-entrant)
    IF dHud {
        SET dBtnCam:ENABLED TO TRUE.
        IF dCamWant {                   // HUD CAM pressed in the GRTLS while its HUD was loading
            SET dCamWant TO FALSE.
            IF hdCamSnap() { SET dBtnCam:TEXT TO "HUD CAM ON". }
            ELSE { SET dBtnCam:PRESSED TO FALSE. SET dBtnCam:TEXT TO "HUD CAM OFF". }
        }
        SET dLblHud:TEXT TO "HUD " + hdRwyName().
    } ELSE {
        SET dLblHud:TEXT TO "HUD: not loaded (" + HD_ARCH + " -- see the terminal)".
    }
}

// ---------------------------------------------------------------- dapBegin: the axes' locks, the csv header
FUNCTION dapBegin {
    IF DAP_AUTO_GUID {
        // the guidance mode: every surface LOCKED in both modes -- the DAP writes every deploy angle (the header)
        lockAxis("pitch", TRUE).
        lockAxis("roll", TRUE).
        lockAxis("yaw", TRUE).
        SET dYawLk TO TRUE.
        SAS OFF.
    } ELSE {
        // every axis starts in AUTO = unlocked (the stick flies the surfaces, as without the DAP)
        lockAxis("pitch", FALSE).
        lockAxis("roll", FALSE).
        lockAxis("yaw", FALSE).
    }

    // lo: always 0, kept for the log readers' columns
    // thr_pilot, sb_lever: the throttle lever as kOS reads it; 1 = the lever law armed
    IF SOCK_LOG { LOG "t,mach,q_kpa,alt,agl,tas,aoa,beta,bank,theta,p,q,r,gmb_p,gmb_r,gmb_y,css_p,css_r,lo,qc,qturn,qe,trim_e,elev,"
        + "pc,pe,ail,trim_a,rud,flap,sb,sb_tgt,sas,hud_h,wow,wong,beta_c,yb,yb_u,brk_l,brk_r,brk_n,brakes,hdg,"
        + "cl,cl_y,cl_yd,cl_dpsi,cl_psic,cl_ub,cl_ur,dr,dr_q,gd,gd_alpha,gd_nz,gd_bank,gd_sb,sb_auto,auto_q,ac_ramp,qpath,ctc,dr_i,thr_pilot,sb_lever,yjet,"
        + "ft_dm,ft_dl,ft_se,ft_col,ft_gd,ft_gl,ft_ep" TO D_CSV. }
    // + the HUD: main-gear height ft, weight on wheels; + the yaw: the sideslip asked, the ground yaw's mode and
    // differential, the three brake sliders written, the BRAKES group, the nose's compass heading
    // ft_*: on the mains, SockFarTrim's terms of the last tick (ADDONS:KALS:FTGROUNDCOLS: kN m / kN, its signs; empty
    // off the mains and without it): its dM rows + the brake's moment, its lift, the sub elevator, colFix, the gear's
    // drag and lift, the elevon fix's pitch
    dapSay("  running. Click PITCH / ROLL/YAW for CSS; END (or wheels stopped) finishes.").
}

// ---------------------------------------------------------------- the C# DAP's hook (the block at D_CS)
FUNCTION dapCsOff {                    // the C# DAP off for the program: kOS's dapTickK from here
    PARAMETER why.
    SET D_CS_ERR TO why.
    SET D_CS TO FALSE.
    SET dCsOk TO 0.
    dapSay("  DAP: kOS flies the ticks (the C# DAP off: " + why + ")").
}
// the AFBW throttle lever live (KalsCoproc's AfbwThrottle: the lever is PILOTMAINTHROTTLE at every tick); FALSE without
// the addon or with an older DLL (no LEVERLIVE: the move rule alone)
FUNCTION dapLevLive {
    IF dLevK < 0 {
        SET dLevK TO 0.
        IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("LEVERLIVE") { SET dLevK TO 1. } }
    }
    IF dLevK = 0 { RETURN FALSE. }
    RETURN ADDONS:KALS:LEVERLIVE.
}
FUNCTION dapCsSetup {                  // once, at the first tick: the addon and its DAP part
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("DAPTICK") { SET why TO "the KAL/S addon has no DAP (an older KalsCoproc.dll)". }
    IF why <> "" { dapCsOff(why). RETURN. }
    SET dCsOk TO 1.
    // the log only (not on screen)
    IF SOCK_LOG { LOG "  DAP: the C# coprocessor flies the ticks" TO D_TXT. }
}
// The elevon read (pitch / roll, every 25 ticks) needs an elevon module on the ship: dElv is made at setup, so a
// splashdown can leave its module on the old vessel (the modLive guard)
FUNCTION dElvLive {
    IF dElv:LENGTH = 0 { RETURN FALSE. }
    RETURN modLive(dElv[0][0]).
}
FUNCTION dapCsIn {                     // the tick's reads, in coproc/Dap.cs DapIn's order
    RETURN LIST(SHIP:ANGULARVEL, SHIP:FACING:FOREVECTOR, SHIP:FACING:STARVECTOR, SHIP:FACING:TOPVECTOR,
        SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR, SHIP:NORTH:VECTOR, SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE),
        SHIP:DYNAMICPRESSURE, SHIP:ALTITUDE, ALT:RADAR, SHIP:AIRSPEED, SHIP:GROUNDSPEED, SHIP:STATUS,
        SHIP:CONTROL:PILOTMAINTHROTTLE, TIME:SECONDS, SAS, BRAKES, CHOOSE dGmb:GIMBAL IF dGmbLive() ELSE 0,
        CHOOSE (surfDep(dRud[0]) OR surfFrozen(dRud[0])) IF dRudHave ELSE TRUE,     // A frozen half reads as deployed (the C# DAP would re-deploy it each tick)
        CHOOSE (surfDep(dRud[1]) OR surfFrozen(dRud[1])) IF dRudHave ELSE TRUE,
        CHOOSE LIST(surfGetLock(dElv[0][0], "pitch"), surfGetLock(dElv[0][0], "roll")) IF (MOD(dLoop, 25) = 0 AND dElvLive()) ELSE 0,
        CHOOSE LIST(dGdRwyThr:POSITION, dGdRwyFar:POSITION) IF dGdRwyOk
            ELSE (CHOOSE LIST(hdRwys[hdRwyIx][2]:POSITION, hdRwys[hdRwyIx][8]:POSITION) IF (dHud AND hdRwyIx >= 0) ELSE 0)).
}
FUNCTION dapCsAng {                    // setAng's write (its memo was the addon's)
    PARAMETER m, k, ang.
    IF surfFrozen(m) { RETURN. }
    IF NOT modLive(m) { RETURN. }
    IF FAR_ON { surfSetAng(m, ang, CHOOSE -1 IF k = "R1" ELSE 1). SET dLast[k] TO ang. }
    ELSE IF m:HASFIELD("deploy angle") {
        m:SETFIELD("deploy angle", ang).
        SET dLast[k] TO ang.
    }
}
FUNCTION dapCsAct {                    // the tick's rare actions, in their order (coproc/Dap.cs DapAct)
    PARAMETER al.
    FOR a IN al {
        LOCAL c IS a[0].
        IF c = 1 { lockAxis(a[1], a[2]). }
        ELSE IF c = 2 { SAS OFF. }
        ELSE IF c = 3 { IF a[1] { BRAKES ON. } ELSE { BRAKES OFF. } }
        ELSE IF c = 4 { IF dGmbLive() { SET dGmb:GIMBAL:LOCK TO FALSE. } }
        ELSE IF c = 5 OR c = 6 {
            LOCAL bt IS CHOOSE dBtnP IF a[1] = "P" ELSE (CHOOSE dBtnR IF a[1] = "R" ELSE (CHOOSE dBtnSb IF a[1] = "Sb" ELSE dBtnCl)).
            // the C# DAP's BTNPRESSED value for Sb / Cl is the AUTO state; their buttons are pressed in MAN / CSS
            IF c = 5 { SET bt:TEXT TO a[2]. } ELSE IF a[1] = "Sb" OR a[1] = "Cl" { SET bt:PRESSED TO NOT a[2]. }
            ELSE { SET bt:PRESSED TO a[2]. }
        }
        ELSE IF c = 7 { surfDeploy(dRud[a[1]]). }
        ELSE IF c = 8 { IF modLive(dBk[a[1]][0]) { dBk[a[1]][0]:SETFIELD(dBk[a[1]][1], a[2]). } }
        ELSE IF c = 9 { SET dLbl:TEXT TO a[1]. }
        ELSE IF c = 10 { LOG a[1] TO D_TXT. }
        ELSE IF c = 11 { PRINT a[1] AT(0, a[2]). }
        ELSE IF c = 12 { LOG dRows:JOIN(CHAR(10)) TO D_CSV. dRows:CLEAR(). }
    }
}
FUNCTION dapCsTick {                   // TRUE: the addon flew this tick (the globals written, kOS applies the I/O)
    LOCAL co IS ADDONS:KALS:DAPTICK(dapCsIn()).
    IF co:ISTYPE("String") { dapCsOff("DAPTICK: " + co). RETURN FALSE. }
    SET D_CS_N TO D_CS_N + 1.
    IF co[7]:LENGTH > 0 { dapCsAct(co[7]). }
    IF co[0] > -1E8 { dapCsAng(dElv[0][0], dElv[0][2], co[0]). }
    IF co[1] > -1E8 { dapCsAng(dElv[1][0], dElv[1][2], co[1]). }
    IF co[2] > -1E8 { dapCsAng(dElv[2][0], dElv[2][2], co[2]). }
    IF co[3] > -1E8 { dapCsAng(dElv[3][0], dElv[3][2], co[3]). }
    IF co[4] > -1E8 { dapCsAng(dFlap, "F", co[4]). }
    IF co[5] > -1E8 { dapCsAng(dRud[0], "R0", co[5]). }
    IF co[6] > -1E8 { dapCsAng(dRud[1], "R1", co[6]). }
    RETURN TRUE.
}
// ONE PHYSICS TICK OF THE DAP: the C# DAP's (D_CS), else kOS's dapTickK
FUNCTION dapRudFail {                   // Which rudder halves FCS 01 holds frozen (0 none, 1 half 0, 2 half 1, 3 both); none = no cost
    IF NOT dRudHave { RETURN 0. }
    IF SURF_FROZEN:LENGTH = 0 { RETURN 0. }
    RETURN (CHOOSE 1 IF surfFrozen(dRud[0]) ELSE 0) + (CHOOSE 2 IF surfFrozen(dRud[1]) ELSE 0).
}
FUNCTION dapTick {
    IF surfListRefind("dap") { dapFindSurfs(). }   // A splashdown's rebuild: found again
    LOCAL tn IS TIME:SECONDS.      // the tick, in whole physics ticks (physics warp: 2-4)
    SET DT TO CHOOSE DT_1X * MAX(1, MIN(5, ROUND((tn - dTickT) / DT_1X))) IF dTickT >= 0 ELSE DT_1X.
    SET dTickT TO tn.
    SET dLevLive TO dapLevLive().  // both DAPs read it (the C# one as a global)
    SET dRudFail TO dapRudFail().  // likewise
    dapTickOne().
    IF YJ_ON { dapYawJet(). }      // the yaw jets' I/O, after whichever DAP flew the tick
}
// the yaw jets' I/O: RCS on (the parts on yaw only) while the jets fly, the command to the addon each tick
FUNCTION dapYawJet {
    IF dYjAct <> dYjRcs {
        SET dYjRcs TO dYjAct.
        IF dYjAct { RCS ON. ADDONS:KALS:YAWJETAXES(TRUE). } ELSE { ADDONS:KALS:YAWJETAXES(FALSE). RCS OFF. }
        IF SOCK_LOG { LOG "  yaw jets " + (CHOOSE "ON (" + (CHOOSE "FAR" IF FAR_ON ELSE "stock") + ", above Mach " + YJ_MACH + "; RCS on, yaw only)" IF dYjAct
            ELSE "OFF (Mach " + ROUND(dapMach(), 2) + "; RCS off)") TO D_TXT. }
    }
    IF dYjAct { ADDONS:KALS:YAWJET(dYawJ). }
}
FUNCTION dapTickOne {
    IF D_CS {
        IF dCsOk < 0 { dapCsSetup(). }
        IF D_CS { IF dapCsTick() { RETURN. } }
    }
    dapTickK().
}

// ONE PHYSICS TICK OF THE DAP in kOS (the body of the main loop; the C# DAP: coproc/Dap.cs)
FUNCTION dapTickK {
    // ---- measure (everything first)
    LOCAL w IS SHIP:ANGULARVEL * CONSTANT:RADTODEG.
    LOCAL fv IS SHIP:FACING:FOREVECTOR.
    LOCAL sv IS SHIP:FACING:STARVECTOR.
    LOCAL tv IS SHIP:FACING:TOPVECTOR.
    LOCAL qu IS -VDOT(w, sv).          // nose-UP pitch rate (kOS ANGULARVEL is left-handed)
    LOCAL pk IS VDOT(w, fv).           // + = LEFT roll
    LOCAL rk IS VDOT(w, tv).           // + = nose RIGHT
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL vm IS MAX(vs:MAG, 1).
    LOCAL aoa IS 0.
    LOCAL beta IS 0.
    IF vs:MAG > 1 {
        SET aoa TO ARCTAN2(-VDOT(vs, tv), VDOT(vs, fv)).
        SET beta TO ARCSIN(MAX(-1, MIN(1, VDOT(vs:NORMALIZED, sv)))).   // + = the velocity to the right
        // the flight path's nose-up rotation: the velocity direction's turn toward the body top, per s (alpha' = q - it)
        LOCAL vh IS vs:NORMALIZED.
        LOCAL tn IS TIME:SECONDS.
        IF dVhT > 0 AND tn - dVhT > 0.001 {
            LOCAL pq IS 57.2958 * VDOT(vh - dVhPrev, tv) / ((tn - dVhT) * MAX(COS(aoa), 0.3)).
            SET dPathQ TO dPathQ + (pq - dPathQ) * MIN(1, (tn - dVhT) / PATH_TAU).
        }
        // the normal load factor: the path's turn toward the body top (V w / g) + gravity's share along it (up . n) --
        // per tick, for the HUD's diamond (the 1 s finite-difference window would make it jump)
        LOCAL nb IS VXCL(vh, tv).
        IF nb:MAG > 0.001 { SET dNzM TO vm * dPathQ / 57.2958 / 9.80665 + VDOT(SHIP:UP:VECTOR, nb:NORMALIZED). }
        SET dVhPrev TO vh.
        SET dVhT TO tn.
    }
    LOCAL mach IS dapMach().
    LOCAL qk IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA.
    LOCAL qkc IS MAX(qk, QB_MIN).
    LOCAL phi IS dapBank().
    LOCAL th IS 90 - VANG(SHIP:UP:VECTOR, fv).
    LOCAL agl IS ALT:RADAR.
    LOCAL gp IS 0.
    LOCAL gr IS 0.
    LOCAL gy IS 0.
    IF dGmbLive() {
        SET gp TO dGmb:GIMBAL:PITCHANGLE.
        SET gr TO dGmb:GIMBAL:ROLLANGLE.
        SET gy TO dGmb:GIMBAL:YAWANGLE.
    }
    // While the jets fly the addon adds a trim to the vessel's yaw (the DAP's command - the pilot's yaw), so the jets fly
    // the DAP's command alone; the gimbal reads the vessel's yaw, and the gimbal less that trim is the pilot's yaw. The
    // pilot's yaw is read by the addon off the OMS gimbal (the vessel's final yaw) less its own trim each physics frame,
    // guarded (an impossible yaw reads 0): YAWJETPILOT. Not from the input devices: a fly-by-wire mod (AFBW) reads the
    // stick itself, and the yaw the handler is handed can sit at 2.0.
    IF dYjAct { SET gy TO ADDONS:KALS:YAWJETPILOT. }

    // ---- the action groups' locks: AG9 / ABORT unlock (-> AUTO), AG10 locks (-> CSS); the gimbal kept unlocked
    IF MOD(dLoop, 25) = 0 {
        IF dGmbLive() {
            IF dGmb:GIMBAL:LOCK {
                SET dGmb:GIMBAL:LOCK TO FALSE.
                SET dRelock TO dRelock + 1.
            }
        }
        IF dElvLive() {
            LOCAL ip IS dElv[0][0]:GETFIELD("pitch").
            LOCAL ir IS dElv[0][0]:GETFIELD("roll").
            IF DAP_AUTO_GUID {
                IF NOT ip OR NOT ir {       // AG9 / ABORT unlocked them: the DAP flies both modes -> locked again
                    lockAxis("pitch", TRUE).
                    lockAxis("roll", TRUE).
                    lockAxis("yaw", dYawLk).
                    SET dRelockN TO dRelockN + 1.
                    addMsg("surfaces unlocked (AG9 / ABORT): locked again -- END hands you the raw surfaces").
                }
            } ELSE IF (dCssP AND NOT ip) OR (dCssR AND NOT ir) {
                addMsg("surfaces unlocked (AG9 / ABORT): BOTH AXES TO AUTO").
                SET dBtnP:PRESSED TO FALSE.
                SET dBtnR:PRESSED TO FALSE.
                SET dReqP TO FALSE.
                SET dReqR TO FALSE.
            } ELSE IF dGmbHave AND ((NOT dCssP AND ip) OR (NOT dCssR AND ir)) {
                addMsg("surfaces locked (AG10): BOTH AXES TO CSS").
                SET dBtnP:PRESSED TO TRUE.
                SET dBtnR:PRESSED TO TRUE.
                SET dReqP TO TRUE.
                SET dReqR TO TRUE.
            }
        }
    }

    // 2 / S4c-3A: AUTO DAP LOST (SW 01 on ENTRY at once; SW 02 on the phase FLFX_PH after DAP_GD_LOST_S): AUTO is refused every pass,
    // both axes stay CSS (the stick flies them; RESTART SW gives AUTO back)
    IF DEFINED FLFX_SWPROG {
        IF flfxSwAutoLost("ENTRY", FLFX_PH) {
            IF NOT dReqP OR NOT dReqR { addMsg("AUTO DAP LOST: CSS ONLY"). }
            SET dReqP TO TRUE.
            SET dReqR TO TRUE.
            // The buttons show
            // CSS as a click leaves them (pressed, the CSS text, live); AUTO is refused every pass by the press above, not by a grey button
            IF dBtnP:HASSUFFIX("ENABLED") {
                SET dBtnP:PRESSED TO TRUE. SET dBtnP:TEXT TO "PITCH  CSS". SET dBtnP:ENABLED TO TRUE.
                SET dBtnR:PRESSED TO TRUE. SET dBtnR:TEXT TO "ROLL/YAW  CSS". SET dBtnR:ENABLED TO TRUE.
            }
        } ELSE IF dBtnP:HASSUFFIX("ENABLED") AND (NOT dBtnP:ENABLED OR NOT dBtnR:ENABLED) AND NOT flfxSwAlphaLost() {
            SET dBtnP:ENABLED TO TRUE.
            SET dBtnR:ENABLED TO TRUE.
        }
        // SW 02 ALPHA MOD (SimSup ALPHA FAIL): the PITCH axis only goes CSS and AUTO PITCH is refused; roll / yaw as they were; RESTART SW gives AUTO back
        IF flfxSwAlphaLost() {
            IF NOT dReqP { addMsg("ALPHA LOOP LOST: PITCH CSS"). }
            SET dReqP TO TRUE.
            // As the SW 01 branch above (pressed, CSS text, live)
            IF dBtnP:HASSUFFIX("ENABLED") { SET dBtnP:PRESSED TO TRUE. SET dBtnP:TEXT TO "PITCH  CSS". SET dBtnP:ENABLED TO TRUE. }
            IF dBtnR:HASSUFFIX("ENABLED") AND NOT dBtnR:ENABLED AND NOT flfxSwAutoLost("ENTRY", FLFX_PH) { SET dBtnR:ENABLED TO TRUE. }
        }
    }
    // ---- mode changes (bumpless)
    IF dReqP <> dCssP AND DAP_AUTO_GUID {
        // the guidance mode: the same loop, another command source -- bumpless both ways (the trim carries on)
        SET dCssP TO dReqP.
        SET dQturnF TO 0.
        IF dCssP AND ABS(gp) * RHC_FULL > P_DB {
            addMsg("PITCH CSS -- stick / trim reads " + ROUND(gp, 2) + ": centre it, Alt+X zeroes KSP trim").
        } ELSE {
            addMsg(CHOOSE "PITCH CSS (the stick)" IF dCssP ELSE "PITCH AUTO (the guidance)").
        }
        SET dBtnP:TEXT TO CHOOSE "PITCH  CSS" IF dCssP ELSE "PITCH  AUTO".
    }
    IF dReqP <> dCssP {
        SET dCssP TO dReqP.
        lockAxis("pitch", dCssP).
        IF dCssP {
            // BUMPLESS: in AUTO the stick (and KSP trim) deflects the elevons and the flap
            // directly; locking the axis would drop that at once -- so the deploy angles take it over first
            SET dElev TO clampV(dElev - ELV_STICK * STICK_P_SIGN * gp, ELV_LIM).
            IF dHaveFlap { SET dFlapAng TO clampV(dFlapAng - FLAP_STICK * STICK_P_SIGN * gp, FLAP_LIM). }
            // the trim takes over the elevator where it is, less the crossfeed
            SET dTrimE TO -(dElev - tabLook(SBX_TAB, mach) * dSbBase).
            SET dQturnF TO 0.
            IF ABS(gp) * RHC_FULL > P_DB {        // KSP trim reads as stick
                addMsg("PITCH CSS -- stick / trim " + ROUND(gp, 2) + " taken over as trim: NOW Alt+X (trim = a rate command)").
            } ELSE {
                addMsg("PITCH CSS").
            }
        } ELSE {
            // the P term off, the trim (+ the brake crossfeed as it is now) kept -- then held while in AUTO
            SET dElev TO clampV(-dTrimE + tabLook(SBX_TAB, mach) * dSbBase, ELV_LIM).
            addMsg("PITCH AUTO (the trim stays on the elevons)").
        }
        SET dBtnP:TEXT TO CHOOSE "PITCH  CSS" IF dCssP ELSE "PITCH  AUTO".
    }
    IF dReqR <> dCssR AND DAP_AUTO_GUID {
        SET dCssR TO dReqR.
        IF dCssR AND ABS(gr) * RHC_FULL > R_DB {
            addMsg("ROLL/YAW CSS -- stick / trim reads " + ROUND(gr, 2) + ": centre it, Alt+X zeroes KSP trim").
        } ELSE {
            addMsg(CHOOSE "ROLL/YAW CSS (the stick)" IF dCssR ELSE "ROLL/YAW AUTO (the guidance)").
        }
        SET dBtnR:TEXT TO CHOOSE "ROLL/YAW  CSS" IF dCssR ELSE "ROLL/YAW  AUTO".
    }
    IF dReqR <> dCssR {
        SET dCssR TO dReqR.
        lockAxis("roll", dCssR).
        IF RUD_ON { lockAxis("yaw", dCssR AND NOT dGnd). }   // on the ground the rudder is the stick's
        IF NOT dCssR {
            SET dAil TO 0.
            SET dRudC TO 0.
        }
        IF dCssR AND ABS(gr) * RHC_FULL > R_DB {
            addMsg("ROLL/YAW CSS -- stick / trim reads " + ROUND(gr, 2) + ": centre it, Alt+X zeroes KSP trim").
        } ELSE {
            addMsg(CHOOSE "ROLL/YAW CSS" IF dCssR ELSE "ROLL/YAW AUTO").
        }
        SET dBtnR:TEXT TO CHOOSE "ROLL/YAW  CSS" IF dCssR ELSE "ROLL/YAW  AUTO".
    }
    IF (dCssP OR dCssR OR DAP_AUTO_GUID) AND SAS {
        SAS OFF.
        SET dSasOff TO dSasOff + 1.
        addMsg("SAS switched OFF: in CSS the gimbal must read the stick alone").
    }

    // the keyboard mode (KB_*): a key's 0 / 1 builds like a stick from here on (the takeovers above keep the raw
    // input: in AUTO KSP deflects the surfaces by it)
    SET gp TO kbAxis(0, gp).
    SET gr TO kbAxis(1, gr).
    SET gy TO kbAxis(2, gy).

    // ---- the speedbrake: AG3 un-deploys the halves; the DAP re-deploys them and reads the press as open / shut
    IF dRudHave {
        IF (CHOOSE FALSE IF FAR_ON ELSE ((NOT surfDep(dRud[0]) AND NOT surfFrozen(dRud[0])) OR (NOT surfDep(dRud[1]) AND NOT surfFrozen(dRud[1])))) {     // A frozen half left un-deployed is no AG3 press
            IF dSbAuto {                   // an AG3 press in SPDBK AUTO: the speedbrake is the pilot's (CSS) from here
                SET dSbAuto TO FALSE.
                IF DAP_AUTO_GUID AND NOT dBtnSb:ISTYPE("Scalar") { SET dBtnSb:PRESSED TO TRUE. SET dBtnSb:TEXT TO "SPDBK CSS". }
                addMsg("SPDBK CSS (AG3)").
            }
            IF NOT dSbLever {               // armed, the lever is the brake (below): AG3 only re-deploys the halves
                IF dSbTarget > 1 { SET dSbTarget TO 0. } ELSE { SET dSbTarget TO dSbOpen. }
            }
            FOR rm IN dRud { IF modLive(rm) AND NOT surfFrozen(rm) { IF NOT rm:GETFIELD("deploy") { rm:SETFIELD("deploy", TRUE). } } }
            SET dSbFlips TO dSbFlips + 1.
            SET dLast TO LEXICON().          // the re-deployed halves need their angle written again
            addMsg(CHOOSE "speedbrake: on the throttle lever" IF dSbLever
                ELSE ("speedbrake " + (CHOOSE "OPENING" IF dSbTarget > 0 ELSE "CLOSING"))).
        }
    }
    // ---- THE LEVER: in SPDBK CSS the throttle lever is the speedbrake lever (the orbiter's speedbrake / thrust
    // controller): 0 % = open RUD_HALF_LIM a side (98.6), 100 % = shut, a straight line, capped above SB_SUPER_MACH at
    // AUTO's SB_SUPER_MAX. kOS reads it as the pilot's input (PILOTMAINTHROTTLE = FlightInputHandler.state). A live AFBW
    // lever (dLevLive: KalsCoproc writes it there every tick) arms the law at once in MAN; otherwise (the keyboard's
    // throttle) it ARMS once kOS has seen the lever move (SB_LEVER_ARM from its start value) and until then MAN is AG3's.
    // Armed, it stays armed. No throttle lock: ops3q's AG2 shuts both OMS down before entry.
    SET dThrPilot TO SHIP:CONTROL:PILOTMAINTHROTTLE.
    IF NOT dSbLever AND ((dLevLive AND NOT dSbAuto) OR ABS(dThrPilot - dThr0) > SB_LEVER_ARM) {
        SET dSbLever TO TRUE.
        addMsg("SPDBK LEVER ARMED: kOS reads the throttle (" + ROUND(100 * dThrPilot) + " %); in CSS it is the brake").
    }
    IF dSbLever AND NOT dSbAuto {
        SET dSbTarget TO RUD_HALF_LIM * (1 - MAX(0, MIN(1, dThrPilot))).
        // AUTO's supersonic cap (SB_SUPER_MAX's note: the Dutch roll at 35 a side does not damp)
        IF mach > SB_SUPER_MACH { SET dSbTarget TO MIN(dSbTarget, SB_SUPER_MAX). }
    }
    IF dSbAuto AND dGdOn {
        SET dSbTarget TO MAX(0, MIN(RUD_HALF_LIM, dGdSb)).
        IF mach > SB_SUPER_MACH { SET dSbTarget TO MIN(dSbTarget, SB_SUPER_MAX). }
        IF NOT RUD_CURVE_PATCH AND dSbTarget > SB_CLOSE_MAX AND dSbTarget < SB_SPLIT_MIN {   // the stock curve's crossover:
            LOCAL mid IS (SB_CLOSE_MAX + SB_SPLIT_MIN) / 2.           //   to the nearer edge, with 0.5 deg of hysteresis
            IF dSbBase >= mid { SET mid TO mid - 0.5. } ELSE { SET mid TO mid + 0.5. }
            SET dSbTarget TO CHOOSE SB_SPLIT_MIN IF dSbTarget >= mid ELSE SB_CLOSE_MAX.
        }
    }
    SET dSbBase TO dSbBase + clampV(dSbTarget - dSbBase, SB_RATE * DT).
    IF dRudFail <> 0 { SET dSbTarget TO 0. SET dSbBase TO 0. }      // No speedbrake with a rudder half failed (the good half is the rudder's)
    LOCAL sbx IS tabLook(SBX_TAB, mach) * dSbBase.     // elevator deg TED that cancels the brake's pitch moment

    // ---- THE GROUND: main-gear contact from the HUD's gear radar height (KSP's LANDED without the HUD).
    // THE GUIDANCE MODE takes the host's contact instead (dGdWow / dGdWong: landRun's 0.3 m for 0.5 s, lib_hud's rule):
    // one touchdown for the program, and no unlatch of its own: a skip of the gear on the runway must not latch the
    // ground mode (the attitude held, the guidance dropped) while landRun still flies the flare.
    LOCAL gdC IS DAP_AUTO_GUID AND dGdOn.
    LOCAL hudOk IS dHud AND TIME:SECONDS - sHftT <= DAP_HUD_STALE_S.   // A frozen sHft is no height
    LOCAL onGnd IS SHIP:STATUS = "LANDED".
    IF hudOk { SET onGnd TO sHft < GND_H_FT. }
    IF gdC { SET onGnd TO dGdWow. }
    IF onGnd AND NOT dGnd {
        SET dGnd TO TRUE.
        IF RUD_ON AND dCssR AND NOT DAP_AUTO_GUID { lockAxis("yaw", FALSE). }
        // the speedbrake to its full hinge at touchdown (the orbiter's
        // opens to 100 % at WOWLON); AG3 can still flip it. SPDBK AUTO: the guidance's ground command instead;
        // the armed lever: the lever (0 % = this full brake).
        IF NOT dSbAuto AND NOT dSbLever { SET dSbTarget TO RUD_HALF_LIM. }
        addMsg("MAIN GEAR: pitch ground mode (trim held, stick x" + GND_STICK + ", up-elevon -" + GND_ELV_UP
            + "), speedbrake to " + RUD_HALF_LIM + " a side").
        SET dGndTh TO MIN(th, GND_HOLD_MAX).          // the attitude AUTO holds until the derotation
        IF DAP_AUTO_GUID AND NOT dCssP AND dGdOn { addMsg("PITCH HOLD: theta " + ROUND(dGndTh, 1) + " until the derotation"). }
    } ELSE IF dGnd AND NOT dWong AND NOT gdC AND hudOk AND sHft > GND_OFF_FT {
        SET dGnd TO FALSE.
        IF RUD_ON AND dCssR AND NOT DAP_AUTO_GUID { lockAxis("yaw", TRUE). }
        addMsg("AIRBORNE again (> " + GND_OFF_FT + " ft): the pitch ground mode off").
    }
    // THE CONTACT MODE (the guidance mode): from the FIRST main-gear contact until landRun's latch the flare law is off.
    // AUTO holds the attitude with the elevator no more nose-up than at the contact, the trim and the flap frozen, so the
    // gear's one-tick kick is not answered with full nose-up (which flies the vehicle back into the air). A bounce past
    // CTC_OFF_FT gives the pitch back to the flare law; the latch (dGdWow) starts the ground mode.
    IF gdC AND NOT dGnd {
        LOCAL ctcNow IS SHIP:STATUS = "LANDED" OR (hudOk AND sHft < GND_H_FT) OR dGdHm < GND_H_FT * 0.3048.   // + the host's height
        IF ctcNow AND NOT dCtc {
            SET dCtc TO TRUE.
            SET dCtcElev TO dElev.
            addMsg("CONTACT: the flare law held until the touchdown latch (attitude hold, elevator no more nose-up than "
                + ROUND(dElev, 1) + ")").
        } ELSE IF dCtc AND (CHOOSE sHft > CTC_OFF_FT IF hudOk ELSE dGdHm > CTC_OFF_FT * 0.3048) AND SHIP:STATUS <> "LANDED" {
            SET dCtc TO FALSE.
            addMsg("BOUNCE past " + CTC_OFF_FT + " ft: the flare law back").
        }
    }
    IF dGnd { SET dCtc TO FALSE. }
    IF dGnd AND NOT dWong AND (CHOOSE dGdWong IF gdC ELSE (dHud AND hdWong)) {
        SET dWong TO TRUE.
        SET dWongT TO TIME:SECONDS.
        addMsg("NOSE GEAR: pitch load relief (elevons " + LR_ELEV + " deg TED)").
    }

    // ---- THE AUTOMATIC DEROTATION on the mains, before WONG (the header): guided, the ROLLOUT button governs it whatever
    // PITCH is (AUTO: the guidance's rate; CSS: the crew's push, then the guidance's rate); stand-alone, a CSS pitch push
    IF dGnd AND NOT dWong AND DAP_AUTO_GUID {
        IF NOT dDerot AND dClReq AND dGdDerot > 0 {          // ROLLOUT AUTO: the guidance's derotation (alg_derot_rate)
            SET dDerot TO TRUE.
            addMsg("DEROTATION AUTO (ROLLOUT AUTO): " + ROUND(dGdDerot, 2) + " deg/s (the guidance)").
        } ELSE IF NOT dDerot AND NOT dClReq AND STICK_P_SIGN * gp < 0 - DR_TRIG {     // ROLLOUT CSS: semi-auto
            SET dDerot TO TRUE.
            addMsg("DEROTATION CSS (ROLLOUT CSS): the crew's push, then " + ROUND(CHOOSE dGdDerot IF dGdDerot > 0
                ELSE DR_RATE_SEMI, 2) + " deg/s (the pitch stick is ignored until the nose gear)").
        }
    } ELSE IF dGnd AND NOT dWong AND dCssP {
        IF NOT dDerot AND STICK_P_SIGN * gp < 0 - DR_TRIG {
            SET dDerot TO TRUE.
            addMsg("DEROTATION: automatic, " + DR_RATE + " deg/s (the pitch stick is ignored until the nose gear)").
        }
    } ELSE {
        SET dDerot TO FALSE.
    }
    LOCAL drRate IS DR_RATE.
    LOCAL drAcc IS DR_ACC.
    IF DAP_AUTO_GUID {                                       // guided: the guidance's rate, ramped at DR_ACC_AUTO
        SET drRate TO CHOOSE dGdDerot IF dGdDerot > 0 ELSE DR_RATE_SEMI.
        SET drAcc TO DR_ACC_AUTO.
    }
    IF dDerot { SET dDrQ TO MAX(0 - drRate, dDrQ - drAcc * DT). } ELSE { SET dDrQ TO 0. }

    // ---- THE AUTO ROLLOUT: the centreline, from main-gear contact to the stop
    // logged whenever there is a runway: every tick on the ground, at 10 Hz in flight (the approach; saves IPU for the HUD)
    LOCAL clRwy IS dGdRwyOk OR (dHud AND hdRwyIx >= 0).
    IF clRwy AND (dGnd OR MOD(dLoop, 5) = 0) { clGeom(fv). }
    SET dClAct TO dClReq AND dGnd AND (dCssR OR DAP_AUTO_GUID) AND dBkHave AND clRwy.
    IF dClAct {
        IF ABS(gy) > CL_HOT { SET dClHotT TO dClHotT + DT. } ELSE { SET dClHotT TO 0. }
        IF dClHotT > CL_HOT_T {                          // the hot stick: the pilot takes the rollout
            SET dClReq TO FALSE.
            SET dBtnCl:PRESSED TO TRUE.             // pressed = CSS
            SET dClAct TO FALSE.
            addMsg("ROLLOUT CSS: the yaw stick took it").
        }
    } ELSE {
        SET dClHotT TO 0.
    }
    IF dClAct {
        SET dClPsiC TO clampV(0 - CL_KY * dClY, CL_PSI_MAX).
        LOCAL ce IS dClPsiC - dClDpsi.
        SET dClUb TO CL_KP * ce - CL_KD * rk.
        SET dClUr TO CL_KPR * ce - CL_KDR * rk.
    } ELSE {
        SET dClUb TO 0.
        SET dClUr TO 0.
    }
    IF DAP_AUTO_GUID {                                   // the rudder: the DAP's except in a CSS rollout
        LOCAL yl IS dClAct OR NOT dGnd.
        IF yl <> dYawLk {
            lockAxis("yaw", yl).
            SET dYawLk TO yl.
        }
    }
    IF dClAct <> dClPrev {                               // the rudder: the DAP's in AUTO, else as before
        IF NOT DAP_AUTO_GUID { lockAxis("yaw", dClAct OR (RUD_ON AND dCssR AND NOT dGnd)). }
        IF dClAct { addMsg("ROLLOUT AUTO: the centreline of " + hdRwyName()). }
        SET dClPrev TO dClAct.
    }

    // ---- PITCH
    LOCAL qc IS 0.
    LOCAL qe IS 0.
    LOCAL fSup IS MAX(0, MIN(1, (mach - DAP_SUP_MACH + 0.1) / 0.2)).     // the supersonic gains' share (above)
    LOCAL tphi IS clampV(TAN(clampV(phi, 89)), 1).
    LOCAL qturn IS 57.2958 * 9.81 / vm * SIN(phi) * tphi * COS(th).     // the nose-up rate of a level turn
    IF dGnd { SET qturn TO 0. }
    SET dQturnF TO dQturnF + (qturn - dQturnF) * DT / QTURN_TAU.
    IF (dCssP OR DAP_AUTO_GUID) AND dWong {
        // THE NOSE-GEAR LOAD RELIEF (the orbiter: pitch forced to AUTO, the elevons to 10 deg TED at 20 deg/s)
        SET dElev TO dElev + clampV(LR_ELEV - dElev, LR_RATE * DT).
        SET dDrI TO 0.                                       // the derotation's integral and the chute guard end at WONG
        SET dChuteLiftT TO 0.
    } ELSE IF dCssP OR DAP_AUTO_GUID {
        LOCAL gs IS 1.
        IF dGnd { SET gs TO GND_STICK. }                      // the orbiter halves the RHC pitch sensitivity at WOWLON
        LOCAL autoP IS FALSE.
        // AUTO on the mains before the derotation: the latch's attitude held (GND_HOLD_*, above)
        LOCAL gndHold IS dGnd AND NOT dWong AND NOT dDerot AND NOT dCssP AND DAP_AUTO_GUID AND dGdOn.
        IF dDerot { SET qc TO dDrQ. }                         // the automatic derotation ALONE: the stick ignored
        ELSE IF dCssP { SET qc TO gs * STICK_P_SIGN * shapeP(gp, mach). }
        ELSE IF gndHold {                                     // until the derotation; the gain's warp factor
            SET qc TO clampV(GND_HOLD_K * MIN(1, DAP_WARP_KT / (LOOP_P * DT)) * (dGndTh - th), GND_HOLD_QMAX).
        }
        ELSE IF dGnd OR dCtc OR NOT dGdOn { SET qc TO 0. }    // AUTO: the rate held (the contact mode: until the latch;
                                                              //   on the mains without the guidance)
        ELSE {
            // AUTO: the alpha command + the flight path's own pitch rotation (the header): measured (dPathQ), else from
            // the commanded Nz; the command ramped over its publication interval (DAP_AC_RAMP), else stepped
            LOCAL gam IS 90 - VANG(SHIP:UP:VECTOR, vs).
            LOCAL qpath IS CHOOSE dPathQ IF DAP_QPATH_MEAS ELSE 57.2958 * 9.81 / vm * (dGdNz - COS(gam) * COS(phi)).
            LOCAL acn IS dGdAlpha.
            LOCAL acd IS dGdAlphaDot.
            IF DAP_AC_RAMP AND dGdAlphaT >= 0 {
                IF dGdAlphaT <> dAcT { SET dAc0 TO dAcNow. SET dAcT TO dGdAlphaT. }
                LOCAL fu IS (TIME:SECONDS - dAcT) / MAX(dGdAlphaDt, 0.02).
                SET acn TO dAc0 + (dGdAlpha - dAc0) * MIN(1, fu).
                SET acd TO CHOOSE (dGdAlpha - dAc0) / MAX(dGdAlphaDt, 0.02) IF fu < DAP_RAMP_HOLD ELSE 0.
            }
            LOCAL ffTau IS DAP_FF_TAU_SUP * fSup + DAP_FF_TAU_SUB * (1 - fSup).   // the feed-forward's lag (above)
            IF ffTau > DT { SET dAcdF TO dAcdF + (acd - dAcdF) * DT / ffTau. SET acd TO dAcdF. }
            ELSE { SET dAcdF TO acd. }
            SET dAcNow TO acn.
            SET autoP TO TRUE.
            // CSS's pitch-rate limit on the alpha part (LIMITS, the header); the path's own rotation on top, as CSS adds
            // its turn term to the stick's command
            SET qc TO clampV((KA_ALPHA + (KA_ALPHA_SUP - KA_ALPHA) * fSup) * (acn - aoa) + acd, shapeP(1, mach)) + qpath.
        }
        IF NOT autoP {                                        // out of the AUTO law the ramp restarts at the vehicle
            SET dAcNow TO aoa.                                // not the record (0 before the first: it would ramp
            SET dAcdF TO 0.                                   //   0 -> 14.3 in 0.24 s, the elevator to -18)
            SET dAc0 TO aoa.
            SET dAcT TO dGdAlphaT.
        }
        SET dQa TO qc.
        SET qe TO qc + (CHOOSE dQturnF IF dCssP ELSE 0) - qu.
        LOCAL gdq IS (LOOP_P + (LOOP_P_SUP - LOOP_P) * fSup) * SQRT(Q_REF) / (tabLook(MD_TAB, mach) * Q_REF) / SQRT(qkc).
        SET gdq TO gdq * MIN(1, DAP_WARP_KT / MAX(1E-6, (LOOP_P + (LOOP_P_SUP - LOOP_P) * fSup) * SQRT(qkc / Q_REF) * DT)).   // the warp cap
        LOCAL gtre IS linM(mach, 3.0, 1.5, 3.5, 1.0).
        LOCAL uNU IS gdq * qe + dTrimE.                       // nose-up elevator, deg
        // the trim integrates unless the elevator is saturated in the error's direction (anti-windup) -- and NOT on the
        // ground: after main-gear contact the attitude hold would answer the gear's nose-down kick with full nose-up and
        // lift the vehicle back off; the P loop only there. Except AUTO's hold on the mains (gndHold), from the
        // latch (landRun's 0.5 s after the contact: the kick is past) to a target no higher than the latch's attitude
        LOCAL elvLim IS ELV_LIM - ABS(dAil).                  // what the aileron (last tick's) leaves it: AIL_ROOM_MIN
        IF dGnd AND NOT dWong { SET elvLim TO ELV_LIM. }     // on the mains: pitch priority (the derotation)
        LOCAL satUp IS -uNU + sbx <= -elvLim.
        LOCAL satDn IS -uNU + sbx >= elvLim.
        IF ((NOT dGnd AND NOT dCtc) OR gndHold) AND NOT ((satUp AND qe > 0) OR (satDn AND qe < 0)) {
            SET dTrimE TO dTrimE + gtre * gdq * qe * DT.
        }
        LOCAL elvUp IS elvLim.
        IF dGnd { SET elvUp TO MIN(elvLim, GND_ELV_UP). }     // the orbiter's CSS up-elevon limit after WOWLON
        LOCAL elvNd IS -(gdq * qe + dTrimE) + sbx.             // the nose-down elevator before the derotation's integral
        // the derotation's integral (DR_KI, above): on the mains while derotating only, nose-down only, no wind-up
        IF dGnd AND NOT dWong AND dDerot {
            LOCAL dri IS DR_KI * (qu - qc) * DT.
            IF dri < 0 OR elvNd + dDrI < elvLim { SET dDrI TO MAX(0, MIN(ELV_LIM, dDrI + dri)). }
        } ELSE { SET dDrI TO 0. }
        SET dElev TO MAX(0 - elvUp, MIN(elvLim, elvNd + dDrI)).
        // the chute guard (CHUTE_GUARD_*, above)
        IF dGnd AND NOT dWong AND qu > CHUTE_GUARD_Q AND dElev >= elvLim - 0.5 {
            SET dChuteLiftT TO dChuteLiftT + DT.
            IF dChuteLiftT >= CHUTE_GUARD_T AND NOT dChuteCutReq {
                SET dChuteCutReq TO TRUE.
                addMsg("CHUTE GUARD: the nose rises " + ROUND(qu, 1) + " deg/s on the mains at full nose-down elevator -- cut it").
            }
        } ELSE { SET dChuteLiftT TO 0. }
        // the contact mode (AUTO): no nose-up answer to the gear's kick -- the elevator no further up than at the contact
        IF dCtc AND NOT dCssP { SET dElev TO MAX(dElev, MIN(dCtcElev, elvLim)). }
        // the body flap takes the steady elevator off the elevons (slow; schedule 0: our elevons are symmetric) --
        // in the air only
        IF dHaveFlap AND NOT dGnd AND NOT dCtc {
            LOCAL etrim IS -dTrimE + sbx.
            IF ABS(etrim) > FLAP_DB {
                SET dFlapAng TO clampV(dFlapAng + clampV(FLAP_K * etrim, FLAP_RATE) * DT, FLAP_LIM).
            }
        } ELSE IF dHaveFlap AND dGnd {
            // ON THE GROUND: trailing edge DOWN on the mains (the derotation's help), back to 0 from WONG or above
            // GND_FLAP_THETA of pitch
            LOCAL fTed IS GND_FLAP_TED + (GND_FLAP_TED_MAX - GND_FLAP_TED) * MIN(1, dDrI / DR_FLAP_I).   // full only when needed
            LOCAL fTgt IS CHOOSE fTed IF (NOT dWong AND th < GND_FLAP_THETA) ELSE 0.
            SET dFlapAng TO clampV(dFlapAng + clampV(fTgt - dFlapAng, GND_FLAP_RATE * DT), FLAP_LIM).
        }
    }
    // AUTO: the stick flies the surfaces; the elevons' offset is HELD (no crossfeed: as without the DAP)

    // ---- ROLL / YAW
    LOCAL pc IS 0.
    LOCAL pe IS 0.
    LOCAL agLost IS 0.                // the aileron the FAR roll guard holds off (+ = LEFT), to the jets
    LOCAL pcFf IS 0.                  // the aileron's feed-forward of the AUTO roll acceleration in warp (0 at 1x)
    IF (dCssR OR DAP_AUTO_GUID) AND dGnd {
        // ON THE GROUND, FROM MAIN-GEAR CONTACT: the roll stick is IGNORED (the slapdown contaminates it) and the orbiter's
        // automatic aileron LOAD BALANCE runs, inferred as a wings-level hold on the mains (equal gear loads), on the
        // roll-rate loop plus the held aileron trim; faded out over LB_FADE s from WONG (the orbiter: 100 s). No rudder
        // law on the ground.
        LOCAL lbk IS 1.
        IF dWong { SET lbk TO MAX(0, 1 - (TIME:SECONDS - dWongT) / LB_FADE). }
        SET pc TO -LB_K * phi.                                   // kOS frame: + = LEFT roll; phi + = LEFT bank
        SET pe TO pc - pk.
        LOCAL gda IS LOOP_R / tabLook(LD_TAB, mach) / qkc * MIN(1, DAP_WARP_KT / (LOOP_R * DT)).   // the warp cap
        // the aileron's room: on the mains (before WONG) only what the elevator leaves -- pitch priority, the derotation
        LOCAL room IS MAX(CHOOSE 0 IF NOT dWong ELSE AIL_ROOM_MIN, MIN(AIL_LIM, ELV_LIM - ABS(dElev))).
        SET dAil TO clampV(lbk * gda * pe + dTrimA, room).
        SET dElev TO clampV(dElev, ELV_LIM - ABS(dAil)).         // the elevator gives the aileron its room
        SET dRudC TO 0.
        IF dClAct AND RUD_CURVE_PATCH AND dSbBase > SB_RUD_MAX {
            SET dRudC TO clampV(CL_RUD_CLOSE_K * dClUr, rudCloseLim(dSbBase)).     // the close scheme (the patch)
        } ELSE IF dClAct AND dSbBase >= SB_SPLIT_MIN {
            SET dRudC TO clampV(dClUr, MAX(0, RUD_HINGE_MAX - dSbBase)).
        }
        SET dBetaC TO 0.
    } ELSE IF dCssR OR DAP_AUTO_GUID {
        IF dCssR {
            SET pc TO STICK_R_SIGN * (shapeR(gr, mach) + cssRx(gr, mach)).   // kOS frame: + = LEFT roll; cssRx the roll at full stick
        } ELSE {
            LOCAL gb IS dapGdBank().                               // AUTO: the guidance's bank (+ = LEFT, as phi)
            SET dPa TO gb[0].
            // in warp the bank loop takes the roll loop's warp factor (with the inner loop alone capped the outer one
            // outran it and the roll-ins rang); its rate limit stays CSS's (LIMITS), so a reversal rolls as fast as at 1x,
            // and the aileron gets the commanded roll acceleration fed forward (pcFf) for the inner loop's lost gain
            LOCAL rwf IS MIN(1, DAP_WARP_KT_R / (LOOP_R * DT)).
            SET pc TO clampV(KA_PHI * rwf * (gb[0] - phi) + gb[1], shapeR(1, mach)).
            IF dPcN = dLoop - 1 {
                SET pcFf TO MIN(1, 4 * (1 - rwf)) * (pc - dPcPrev) / DT * COS(aoa) / (tabLook(LD_TAB, mach) * qkc).   // 0 at 1x
            }
            SET dPcPrev TO pc.
            SET dPcN TO dLoop.
        }
        LOCAL pturn IS -57.2958 * 9.81 / vm * clampV(TAN(clampV(phi, 89)), 1.73) * SIN(th).
        SET pe TO pc * COS(aoa) - (pk - pturn).
        LOCAL gda IS LOOP_R / tabLook(LD_TAB, mach) / qkc * MIN(1, DAP_WARP_KT_R / (LOOP_R * DT)).   // the warp cap
        IF mach > 1.25 AND mach < 3.55 {
            SET dTrimA TO clampV(dTrimA + GTRA * gda * pe * DT, 3).
        }
        LOCAL room IS MAX(AIL_ROOM_MIN, MIN(AIL_LIM, ELV_LIM - ABS(dElev))).
        SET dAil TO clampV(gda * pe + dTrimA + pcFf, room).
        IF YJ_ON AND mach > YJ_MACH {     // the FAR high-alpha roll guard (AG_LOC_TAB); the jets take the rest
            LOCAL agA IS clampV(dAil, MAX(0, tabLook(AG_LOC_TAB, mach) - aoa - dElev)).
            SET agLost TO dAil - agA.
            SET dAil TO agA.
        }
        SET dElev TO clampV(dElev, ELV_LIM - ABS(dAil)).
        IF RUD_ON AND mach < RUD_MACH AND NOT dGnd AND (RUD_CURVE_PATCH OR dSbBase <= SB_CLOSE_MAX
                                                         OR dSbBase >= SB_SPLIT_MIN) {
            LOCAL rturn IS -57.2958 * 9.81 / vm * SIN(phi) * COS(th).    // + = nose right; a LEFT bank turns left
            LOCAL rc IS -pc * SIN(aoa) + rturn.                           // the stability-axis roll's yaw
            IF YAW_PK > 0.5 { SET rc TO -(pk - pturn) * TAN(clampV(aoa, 45)) + rturn. }   // the measured roll's
            LOCAL rOpen IS dSbBase >= SB_SPLIT_MIN AND NOT RUD_CURVE_PATCH AND RUD_LIN < 0.5.
            LOCAL rClose IS dSbBase > SB_RUD_MAX AND NOT rOpen AND RUD_LIN < 0.5.   // the close scheme (5 - 28 a side; the patch: all; not under FAR)
            // the patch's close scheme is force-matched: the shut-brake gain at every brake angle (RUD_CURVE_PATCH)
            LOCAL rgk IS (CHOOSE RUD_OPEN_K IF rOpen ELSE (CHOOSE tabLook(RUD_CLOSE_K_TAB, dSbBase)
                IF (rClose AND NOT RUD_CURVE_PATCH) ELSE 1)).
            LOCAL rlim IS CHOOSE MAX(0, RUD_HINGE_MAX - dSbBase) IF rOpen ELSE (CHOOSE (CHOOSE rudCloseLim(dSbBase)
                IF RUD_CURVE_PATCH ELSE dSbBase + RUD_CLOSE_LIM) IF rClose ELSE RUD_LIM).
            LOCAL gdr IS rgk * tabLook(KDRC_TAB, mach) / qkc.
            // the yaw stick (+ = nose right) asks a sideslip (the velocity to the LEFT: beta < 0), so the loop does not
            // fight the capsule torque the same stick commands (the orbiter's pedals bias Ny)
            SET dBetaC TO 0.
            IF dCssR AND ABS(gy) > YB_DB { SET dBetaC TO -PED_BETA * clampV(gy, 1). }
            SET dRudC TO clampV(gdr * (rc - rk) + rgk * tabLook(KBETA_TAB, mach) * (beta - dBetaC), rlim).
            IF YJ_ON AND mach < YJ_RUD_MACH { SET dRudC TO 0. }      // under FAR the jets fly the yaw alone
        } ELSE {
            SET dRudC TO 0.
            SET dBetaC TO 0.
        }
    }

    // ---- THE YAW JETS (FAR, above YJ_MACH, in flight): the rudder's yaw-rate error (the stability-axis roll's yaw
    // and the turn) and the sideslip (less the yaw stick's in CSS); dapYawJet hands the command to the addon
    IF YJ_ON AND (mach > YJ_MACH OR dRudFail <> 0) AND NOT dGnd AND (dCssR OR DAP_AUTO_GUID) {     // A failed rudder half: the jets to touchdown
        LOCAL rcj IS -pc * SIN(aoa) - 57.2958 * 9.81 / vm * SIN(phi) * COS(th).
        IF YAW_PK > 0.5 {     // the measured roll's (less the turn's roll rate, as the roll loop's pturn)
            SET rcj TO -(pk + 57.2958 * 9.81 / vm * clampV(TAN(clampV(phi, 89)), 1.73) * SIN(th)) * TAN(clampV(aoa, 45))
                       - 57.2958 * 9.81 / vm * SIN(phi) * COS(th).
        }
        SET dYawJ TO clampV((YJ_KR * (rcj - rk) + YJ_KB * (beta - dBetaC) + YJ_KA * dAil
                            - AG_KJ * agLost) * MIN(1, DAP_WARP_KT / (YJ_KR * YJ_ACC * DT)), 1).   // LEFT = nose LEFT; the warp cap
        SET dYjAct TO TRUE.
    } ELSE {
        SET dYawJ TO 0.
        SET dYjAct TO FALSE.
    }

    // ---- THE GROUND YAW: the yaw stick -> differential braking on the mains (see the header)
    LOCAL ybWant IS 0.
    IF dBkHave AND (dCssR OR DAP_AUTO_GUID) AND dGnd { SET ybWant TO CHOOSE 2 IF (dWong OR DAP_BRK_FROM_WOW) ELSE 1. }
    IF ybWant <> dYb {
        IF dYb = 1 AND BRAKES { BRAKES OFF. }          // the DAP's brakes end: the pilot's B from here
        IF ybWant = 0 {
            brkBack().
        } ELSE IF ybWant = 1 {
            setBrk(dBkN, "N", 0).                        // the nose gear lands unbraked
            addMsg("GROUND YAW: the yaw stick brakes the mains " + ROUND(YB_BASE / MAX(1, BRK_TORQUE_K), 1) + " +- "
                   + ROUND(YB_SPAN / MAX(1, BRK_TORQUE_K), 1) + " % (the DAP's brakes)").
        } ELSE {
            IF dBkN >= 0 { setBrk(dBkN, "N", CHOOSE MIN(NOSE_BRK_MAX, brkBase(dBkN)) IF dWong ELSE 0). }
            SET dBkSfT TO CHOOSE -1 IF dWong ELSE 0.             // the short field: from the main gear, ramped
            IF NOT dWong {
                addMsg("SHORT FIELD: the brakes from the main gear (the mains to " + MIN(YB_MAX, brkBase(dBkR))
                       + " % in about " + ROUND((MIN(YB_MAX, brkBase(dBkR)) - YB_BASE / MAX(1, BRK_TORQUE_K)) / BRK_SF_RAMP, 1)
                       + " s; the nose gear unbraked until it touches)").
            }
            IF DAP_AUTO_GUID {
                addMsg("the brakes: the host's while ROLLOUT is AUTO (sliders " + MIN(YB_MAX, brkBase(dBkR))
                       + " %, the nose " + (CHOOSE MIN(NOSE_BRK_MAX, brkBase(dBkN)) IF dBkN >= 0 ELSE "-")
                       + " %, the centreline lowers the far main up to " + ROUND(YB_AUTO_SPAN / MAX(1, BRK_TORQUE_K), 1)
                       + " %); yours (B) in a CSS rollout").
            } ELSE {
                addMsg("the brakes are yours (B); the yaw stick lowers the far main up to "
                       + ROUND(2 * YB_SPAN / MAX(1, BRK_TORQUE_K), 1) + " %").
            }
        }
        SET dYb TO ybWant.
    }
    SET dYbU TO 0.                 // the differential, % (+ = nose right): before WONG +- about YB_BASE; after WONG
    IF dYb > 0 {                   // the far main lowered by it
        LOCAL bk IS MAX(1, BRK_TORQUE_K).                       // the %s at the installed torque (above)
        LOCAL ybLim IS (CHOOSE YB_SPAN IF dYb = 1 ELSE (CHOOSE YB_AUTO_SPAN IF dClAct ELSE 2 * YB_SPAN)) / bk.
        IF dClAct {
            SET dYbU TO clampV(dClUb / bk, ybLim).               // AUTO: the centreline tracking
        } ELSE IF ABS(gy) > YB_DB {
            SET dYbU TO ybLim * clampV(gy, 1).                   // CSS: the yaw stick
        }
        IF dYb = 1 {
            IF NOT BRAKES { BRAKES ON. }
            setBrk(dBkR, "R", pwm5(YB_BASE / bk + dYbU)).
            setBrk(dBkL, "L", pwm5(YB_BASE / bk - dYbU)).
        } ELSE {
            LOCAL bcap IS 100.                                    // the short field's ramp from the main gear (above)
            IF dBkSfT >= 0 {
                SET dBkSfT TO dBkSfT + DT.
                IF qu < 0 - MAX(BRK_SF_QMIN, BRK_SF_QK * ABS(dDrQ)) AND dElev <= 0.5 - MIN(ELV_LIM, GND_ELV_UP) {
                    IF dBkSfBack = 0 {                    // the nose falls fast at full nose-up elevator (above)
                        addMsg("SHORT FIELD: the brakes back off -- the nose falls " + ROUND(0 - qu, 1)
                               + " deg/s at full nose-up elevator").
                    }
                    SET dBkSfBack TO dBkSfBack + 1.
                    SET dBkSfT TO 0.
                }
                SET bcap TO YB_BASE / bk + BRK_SF_RAMP * dBkSfT.
                IF dWong {                                        // the nose gear down: its slider; the ramp ends
                    IF dBkN >= 0 { setBrk(dBkN, "N", MIN(NOSE_BRK_MAX, brkBase(dBkN))). }
                    SET dBkSfT TO -1.
                }
            }
            setBrk(dBkR, "R", pwm5(MIN(bcap, MIN(YB_MAX, brkBase(dBkR)) - MAX(0, 0 - dYbU)))).
            setBrk(dBkL, "L", pwm5(MIN(bcap, MIN(YB_MAX, brkBase(dBkL)) - MAX(0, dYbU)))).
        }
    }

    // ---- the surfaces
    FOR ev IN dElv { setAng(ev[0], ev[2], clampV(dElev + ev[1] * dAil, ELV_LIM)). }
    IF dHaveFlap { setAng(dFlap, "F", dFlapAng). }
    IF dRudHave {
        LOCAL rLin IS RUD_LIN > 0.5 AND NOT dGnd.          // FAR in flight = the shut mapping
        IF dRudFail <> 0 {      // The good half = the rudder alone (the frozen half's write is refused by setAng)
            LOCAL dr1 IS clampV(RUD_ONE_K * dRudC, RUD_ONE_LIM).
            IF dRudFail <> 1 { setAng(dRud[0], "R0", RUD_SIGN * dr1). }
            IF dRudFail <> 2 { setAng(dRud[1], "R1", -RUD_SIGN * dr1). }
        } ELSE IF RUD_CURVE_PATCH AND dSbBase > SB_RUD_MAX AND NOT rLin {    // THE PATCH: one scheme -- the force-matched close (above);
            // RUD_SPLIT: the other half opens by as much (the hinge kept while it has room). + = nose right closes half 0
            LOCAL hc IS dSbBase.
            IF dRudC <> 0 {
                SET hc TO CHOOSE rudSplitTo(dSbBase, ABS(dRudC)) IF RUD_SPLIT ELSE rudCloseTo(dSbBase, ABS(dRudC)).
            }
            LOCAL ho IS CHOOSE MIN(RUD_OPEN_MAX, 2 * dSbBase - hc) IF RUD_SPLIT ELSE dSbBase.
            setAng(dRud[0], "R0", CHOOSE hc IF dRudC > 0 ELSE ho).
            setAng(dRud[1], "R1", CHOOSE hc IF dRudC < 0 ELSE ho).
        } ELSE IF dSbBase >= SB_SPLIT_MIN AND NOT rLin { // in flight, and on the ground (the AUTO rollout; else 0)
            // THE BRAKE OPEN: the yaw opens ONE half further (<= RUD_HINGE_MAX), the other stays at the brake -- at the
            // split + RUD_OPP (half 0 opening) = nose RIGHT (measured), so nose right opens half 0, nose left half 1
            LOCAL dr IS clampV(dRudC, MAX(0, RUD_HINGE_MAX - dSbBase)).
            setAng(dRud[0], "R0", dSbBase + MAX(0, dr)).
            setAng(dRud[1], "R1", dSbBase + MAX(0, -dr)).
        } ELSE IF dSbBase > SB_RUD_MAX AND NOT rLin {    // the brake part-open, below the peak: the yaw CLOSES one half
            // (away from the peak): nose right closes half 0 (the left half: its outward lift pushes the tail right),
            // nose left closes half 1 -- the shut sign (RUD_SIGN -1 moves half 0 down for nose right) on one half
            LOCAL dr IS clampV(dRudC, dSbBase + RUD_CLOSE_LIM).
            setAng(dRud[0], "R0", dSbBase - MAX(0, dr)).
            setAng(dRud[1], "R1", dSbBase - MAX(0, -dr)).
        } ELSE {
            LOCAL rroom IS MAX(0, RUD_HALF_LIM - dSbBase).
            LOCAL dr IS clampV(dRudC, rroom).
            setAng(dRud[0], "R0", dSbBase + RUD_SIGN * dr).
            setAng(dRud[1], "R1", dSbBase - RUD_SIGN * dr).
        }
    }

    // ---- log, display: a row every D_LOG_EVERY ticks (25 Hz), one LIST
    // joined once, which avoids the garbage of many string concatenations
    IF SOCK_LOG AND MOD(dLoop, D_LOG_EVERY) = 0 {   // the logs off (lib_logsw): no row is built
        dRows:ADD(LIST(ROUND(TIME:SECONDS, 3), ROUND(mach, 4), ROUND(qk, 3), ROUND(SHIP:ALTITUDE, 1), ROUND(agl, 1),
            ROUND(SHIP:AIRSPEED, 2), ROUND(aoa, 3), ROUND(beta, 3), ROUND(phi, 2), ROUND(th, 3), ROUND(pk, 4),
            ROUND(qu, 4), ROUND(rk, 4), ROUND(gp, 3), ROUND(gr, 3), ROUND(gy, 3), (CHOOSE 1 IF dCssP ELSE 0),
            (CHOOSE 1 IF dCssR ELSE 0), 0, ROUND(qc, 3), ROUND(dQturnF, 3), ROUND(qe, 3),
            ROUND(dTrimE, 3), ROUND(dElev, 3), ROUND(pc, 3), ROUND(pe, 3), ROUND(dAil, 3), ROUND(dTrimA, 3),
            ROUND(dRudC, 3), ROUND(dFlapAng, 2), ROUND(dSbBase, 2), ROUND(dSbTarget, 1), (CHOOSE 1 IF SAS ELSE 0),
            ROUND(sHft, 1), (CHOOSE 1 IF hdWow ELSE 0), (CHOOSE 1 IF hdWong ELSE 0), ROUND(dBetaC, 2), dYb,
            ROUND(dYbU, 2), brkNow(dBkL, "L"), brkNow(dBkR, "R"), brkNow(dBkN, "N"), (CHOOSE 1 IF BRAKES ELSE 0),
            ROUND(hdgNow(fv), 2), (CHOOSE 1 IF dClAct ELSE 0), ROUND(dClY, 2), ROUND(dClYd, 2), ROUND(dClDpsi, 3),
            ROUND(dClPsiC, 2), ROUND(dClUb, 2), ROUND(dClUr, 2), (CHOOSE 1 IF dDerot ELSE 0), ROUND(dDrQ, 3),
            (CHOOSE 1 IF DAP_AUTO_GUID ELSE 0), ROUND(dGdAlpha, 3), ROUND(dGdNz, 4), ROUND(dPa, 3), ROUND(dGdSb, 2),
            (CHOOSE 1 IF dSbAuto ELSE 0), ROUND(dQa, 3), ROUND(dAcNow, 3), ROUND(dPathQ, 3), (CHOOSE 1 IF dCtc ELSE 0),
            ROUND(dDrI, 2), ROUND(dThrPilot, 3), (CHOOSE 1 IF dSbLever ELSE 0), ROUND(dYawJ, 3)):JOIN(",")
            + (CHOOSE ADDONS:KALS:FTGROUNDCOLS IF (hdWow AND dFtOn) ELSE ",,,,,,,")).
        IF dRows:LENGTH >= D_FLUSH {
            LOG dRows:JOIN(CHAR(10)) TO D_CSV.
            dRows:CLEAR().
        }
    }
    SET dLoop TO dLoop + 1.
    IF MOD(dLoop, 25) = 0 {
        LOCAL keas IS SQRT(2 * qk * 1000 / 1.225) / 0.514444.
        SET dLbl:TEXT TO "M " + ROUND(mach, 2) + "  " + ROUND(keas) + " KEAS  " + ROUND(agl * 3.28084) + " ft".
        IF NOT DAP_AUTO_GUID {             // the status rows: standalone css_dap only (landRun's console stays blank)
            PRINT "M " + ROUND(mach, 2) + "  q " + ROUND(qk * 20.885) + " psf  " + ROUND(keas) + " KEAS  AGL "
                + ROUND(agl * 3.28084) + " ft  alpha " + ROUND(aoa, 1) + "  beta " + ROUND(beta, 1) + "          " AT(0, 22).
            PRINT "PITCH " + (CHOOSE "CSS " IF dCssP ELSE "AUTO") + "  cmd " + ROUND(qc + dQturnF, 2) + "  rate "
                + ROUND(qu, 2) + " deg/s  elev " + ROUND(dElev, 1) + "  flap " + ROUND(dFlapAng, 1) + "          " AT(0, 23).
            PRINT "ROLL  " + (CHOOSE "CSS " IF dCssR ELSE "AUTO") + "  cmd " + ROUND(-pc, 1) + "  rate " + ROUND(-pk, 1)
                + " deg/s (+ right)  ail " + ROUND(dAil, 1) + "  bank " + ROUND(-phi, 1) + "          " AT(0, 24).
            PRINT "SB " + ROUND(dSbBase, 1) + " a side (" + (CHOOSE "open" IF dSbTarget > 0 ELSE "shut") + ")  rudder "
                + ROUND(dRudC, 1) + "  stick p " + ROUND(gp, 2) + " r " + ROUND(gr, 2) + " y " + ROUND(gy, 2)
                + "          " AT(0, 25).
            PRINT "YAW  beta " + ROUND(beta, 1) + " asked " + ROUND(dBetaC, 1) + "  brakes L/R " + brkNow(dBkL, "L") + "/"
                + brkNow(dBkR, "R") + (CHOOSE " (DAP)" IF dYb = 1 ELSE (CHOOSE " (yours)" IF dYb = 2 ELSE ""))
                + "          " AT(0, 27).
            PRINT "ROLLOUT " + (CHOOSE "AUTO" IF dClReq ELSE "CSS ") + (CHOOSE " (on)" IF dClAct ELSE "") + "  y "
                + ROUND(dClY, 1) + " m  hdg err " + ROUND(dClDpsi, 2) + "  asked " + ROUND(dClPsiC, 1)
                + (CHOOSE "  DEROT" IF dDerot ELSE "") + "          " AT(0, 28).
        }
        IF dMsg <> "" {
            IF NOT DAP_AUTO_GUID { PRINT dMsg + "                                        " AT(0, 26). }
            IF SOCK_LOG { LOG "  t " + ROUND(TIME:SECONDS - D_T, 1) + " M " + ROUND(mach, 2) + ": " + dMsg TO D_TXT. }
            SET dMsg TO "".
        }
    }
    IF dReqEnd OR (SHIP:STATUS = "LANDED" AND SHIP:GROUNDSPEED < 1) { SET dDone TO TRUE. }
}

// the main loop's HUD part: the control mode and the speedbrake to the HUD, one
// update when its real-time slot has come, the HUD line in the window once a second
FUNCTION dapHudTick {
    IF dHud {
        SET hdCtlTxt TO (CHOOSE "CSS" IF (dCssP OR dCssR) ELSE "AUTO").
        IF DAP_AUTO_GUID AND (dCssP <> dCssR) { SET hdCtlTxt TO CHOOSE "CSS P" IF dCssP ELSE "CSS R". }
        IF DAP_AUTO_GUID AND dGnd AND NOT dWong {             // on the mains: the derotation (the header)
            IF NOT dDerot AND NOT dClReq AND dGdDerot > 0 { SET hdCtlTxt TO hdCtlTxt + " PUSH". }
        }
        SET hdSb TO H_SB_FULL * dSbBase / RUD_HALF_LIM.       // the HUD's scale is the orbiter's 0-98.6: full = RUD_HALF_LIM a side
        SET hdSbc TO H_SB_FULL * dSbTarget / RUD_HALF_LIM.
        hdTick().
        IF TIME:SECONDS >= dHudLblT {
            SET dLblHud:TEXT TO "HUD " + hdRwyName() + (CHOOSE "" IF hdRwyOn ELSE " (overlay off: AG4)") + ", "
                + ROUND(hdRate) + " Hz, " + ROUND(hdCost) + " op/update".
            SET dHudLblT TO TIME:SECONDS + 1.
        }
    }
}

// ---------------------------------------------------------------- dapStop: every axis back to the stick, trims kept
FUNCTION dapStop {
    IF dHud { hdClose(). }
    lockAxis("pitch", FALSE).
    lockAxis("roll", FALSE).
    lockAxis("yaw", FALSE).
    IF dYjRcs { ADDONS:KALS:YAWJETAXES(FALSE). RCS OFF. SET dYjRcs TO FALSE. }   // the yaw jets end with the DAP
    SET dYjAct TO FALSE.
    SET dYawJ TO 0.
    IF dYb = 1 AND BRAKES { BRAKES OFF. }      // the DAP's brakes (before WONG) end with it
    IF dBkHave { brkBack(). }                  // every brake slider back to the craft's value
    FOR ev IN dElv { setAng(ev[0], ev[2], dElev). }   // the aileron off, the pitch trim kept (as AUTO)
    IF dRudHave {
        setAng(dRud[0], "R0", dSbBase).
        setAng(dRud[1], "R1", dSbBase).
    }
    IF dGmbLive() {                            // Not after the OMS engine is lost (a breakup / ditching)
        LOCAL gmod IS dGmb:GETMODULE("ModuleGimbal").
        IF dGmbLim0 >= 0 AND gmod:HASFIELD("gimbal limit") { IF modLive(gmod) { gmod:SETFIELD("gimbal limit", dGmbLim0). } }
        SET dGmb:GIMBAL:LOCK TO dGmbLock0.
    }
    IF dRows:LENGTH > 0 { LOG dRows:JOIN(CHAR(10)) TO D_CSV. }
    dGui:HIDE().
    dapSay("DONE -- the surfaces are unlocked (flown by the stick), the pitch trim and the brake left as they were; SAS "
        + "switched off " + dSasOff + "x, brake flips " + dSbFlips + ", gimbal relocks " + dRelock
        + "; the wheel brakes' sliders back at the craft's values." + (CHOOSE " Log: " + D_CSV + "." IF SOCK_LOG ELSE "")).
}

// The crew re-selects AUTO on both axes after RESTART SW healed SW 01 / SW 02 (lib_flfx flfxTick, only while the automated test flight flies: no pilot). dReqP / dReqR are
// what the DAP (kOS and the C# twin: DapState reads them every tick) follow; the toggles' ONTOGGLE sets the same two.
FUNCTION dapCrewAuto {
    SET dReqP TO FALSE.
    SET dReqR TO FALSE.
    IF NOT dBtnP:ISTYPE("Scalar") {          // the toggles built (0 = not yet): enabled again, released (their ONTOGGLE sets the same two wishes)
        SET dBtnP:ENABLED TO TRUE. SET dBtnR:ENABLED TO TRUE.
        SET dBtnP:PRESSED TO FALSE. SET dBtnR:PRESSED TO FALSE.
    }
    addMsg("AUTO DAP: RE-SELECTED AFTER RESTART SW").
}
IF DEFINED FLFX_AUTOS { flfxRegAuto("DAP", dapCrewAuto@). }   // NOT "IF DEFINED flfxRegAuto" (DEFINED on a function name leaves arg markers: the call died "PARAMETER name, d" at the ops2q -> ops3q hand-off); lib_flfx's global marks it loaded
