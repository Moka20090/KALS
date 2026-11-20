// ============================================================================
//  ops2q.ks  --  OPS 2: the on-orbit program, OMS-2 through the deorbit burn
//  Usage: RUN ops2q. The window: MNVR EXEC 2021/ (the burn: its source plan, TIG, the LVLH dV, the burn attitude, VGO,
//  HA / HP, ARM / EXEC / CUT OFF), DEORB, ORBIT / PTG 2011/ (the orbit, the attitude, the orbit view), OMS/MPS, and
//  BRN PLN 2023/ (off the page row: a CIRC / HA / HP / PLANE / DV burn at APO / PERI / AN / DN / a time, solved on the
//  conic, LOAD -> MNVR). The cursor (black on amber): the arrows move it, + / - change its field by its STEP, ENT
//  presses an action, TYPE opens a number pad (the keys 0-9 . - BKSP ENT CANCEL); INPUT RHC reads the same keys off
//  the stick (W / S up / down, A / D left / right, E / Q + / -), Space = ENT, AG4 = TYPE.
//  PDRS CONTROL: the 5th page button, the Canadarm's
//  page (after the real SPEC 94 / 95 and DISP 169: MODE SINGLE / MAN AUG / OPR CMD / AUTO, RATE, FRAME, the POR, the 6 joints, the MPM STOW / DEPLOY / CENTER, GRAPPLE,
//  the AUTO poses, HOLD). arm.ks runs HOSTED (ARM_HOST, lib_o2arm.ks): it comes up with the page, ops2q calls its pass every physics tick
//  while the page is shown, its own hold flies the orbiter (ops2q's DAP stands by and flies again when the page is left); the pad's
//  CUT OFF slot is split into EE CAM + STOP (orange). No live camera feed on the display (EE CAM is arm.ks's camera view).
//  THE KEYBOARD (KalsCoproc's KEYLOCK / KEYS, coproc/KalsKeys.cs): while
//  ops2q runs KSP's STAGING lock is held and the stage key (Space) is ENT; while TYPE is open every key-driven control
//  is locked (the mouse and the camera stay free) and the keyboard types into the box: 0-9 (both rows) . - + edit,
//  Backspace = BKSP, Enter / Space = ENT, Esc = CANCEL, every other key nothing. The keys come through o2qKey, the
//  window pad's own path. Asked for each cycle: the coproc drops the locks 2 s after the last ask (a crash, Ctrl+C or a
//  reboot never leaves the keyboard locked); OFF when ops2q ends. Without KalsCoproc's KEYLOCK: the pad only.
//  THE BURN: flown here, PEG 7 (lib_o2peg.ks), the window up throughout. EXEC starts the sequence in
//  shuttle_exec v3.4's order and values: the bay doors closed, the warp to TIG-5:00, the OMS gimbals unlocked, SAS off,
//  RCS on, the OMS control point (AG6), the burn attitude, the rate null (0.3 deg/s for 3 s) and the fine null on the
//  wheels (0.01 deg/s, RCS off), the warp to TIG-0:20, RCS on, the settle; at TIG the burn, run by a trigger each
//  physics tick: the OMS thrust sensed, VGO decremented, the thrust line steered along VGO, the throttle tapered to
//  the cut; then the forward point (AG7), RCS off, SAS on, and VGO's rest shown as the RCS TRIM residuals (body X
//  forward, Y right, Z down). CUT OFF ends the burn, or stops the sequence before TIG. After a deorbit burn (or an
//  AOA's OMS-2) ops3q builds the entry family at its start, after an ATO's OMS-1 the ATO / AOA
//  choice plans OMS-2 (exAtoNext).
//  PEG 4 (lib_o2peg.ks): GUID PEG 4 flies to a target point HT above the surface, THETA T ahead of the TIG
//  point, on the line VRADIAL = C1 + C2 VHORIZONTAL there (the real orbiter's OMS-1 / OMS-2 / deorbit guidance, FSSR
//  LTVCON): VGO = the conic v' less v, re-solved each physics tick, the conic aimed through Principia's J2 (the J2
//  coast's offsets, one step a second). A deorbit plan loads as PEG 4, its targets the plan impulse's interface (80 km,
//  C1 0, C2 the tangent of its flight path angle); any burn in the plane can be switched to PEG 4 (its targets from its
//  impulse). Under PEG 4 DVX / DVY / DVZ show PEG 4's VGO at the burn's centre (read only, as the real page), C1 / C2 /
//  HT / THETA T are the fields; an engine change that moves TIG keeps the target point (THETA T re-measured).
//  PEG 4 is the deorbit's: it is offered only for a burn whose coast reaches the entry interface going down (o2qP4Ok:
//  lib_o2peg's o2p4Reach on the burn's state after it); else GUID's PEG 4 is dim and ENT on it says why (o2Choice's dimWhy),
//  and a PEG 4 burn edited so it no longer reaches the interface drops to PEG 7 with the same MSG.
//  THE OMS FAILURES: the real orbiter's OMS RM, one out flag
//  per engine whatever the cause, through ONE entry (o2qOmsFail): an engine meant lit found shut down (a right-click
//  Shutdown, an action group), a flameout or Pc under 80 % for 0.48 s while it burns (lib_o2peg o2pEoWhy), the part gone,
//  or our own: the "!" button's FAILURES window (lib_failui.ks: FAIL for L / R / ANY at once, MET / TIG rows, RAND,
//  for repeatable flights).
//  The engine is shut down and never relit by ops2q (1:/oms_out.txt keeps it out over a re-RUN); the message L OMS FAIL
//  (red) comes first, then its consequence above it: SINGLE OMS BURN (L OUT) (yellow; before ignition the burn re-planned
//  on the one engine, centred where it was, the attitude re-solved so its thrust lies along VGO; in the burn the thrust
//  line steered onto VGO and the time guard re-based) or BOTH OMS OUT (red; the burn ends, the dV left shown on RCS TRIM:
//  finish it with +X RCS by hand). MNVR EXEC's OMS selects BOTH / L / R (a single-engine burn: the other one shut down
//  for it, relit after). OMS/RCS: OMS L / R (status, Pc, thrust, gimbal, tank %), the RCS pods F / L / R (QTY, jets, FAIL,
//  VERN), JET SEL PRI / VERN (the verniers emulated on the primaries), XFER (BAL / TGT / GO: the RCS propellant between the fuselage modules),
//  CTRL FRM FWD / OMS, the Pc tapes (fill = actual, pointer = commanded, the bar red when failed) and the RCS CMD lamps (the DAP's jets).
//  THE ORBIT DAP (lib_o2dap.ks; AUTO and CSS for on-orbit operations):
//  at RUN SAS off, RCS on, AUTO holding INRTL on the attitude it has. ORBIT / PTG: HOLD INRTL / LVLH / TRACK (a body
//  axis, +X nose, +Y right, +Z belly, on the Earth's centre or the Sun, at the typed OMICRON, the roll about the line of
//  sight) / FREE, each taking the attitude it has (TRACK: the one with omicron); the page's R / P / Y rows read CUR | MNVR (the
//  typed MNVR target) | TGT (the DAP's own target, every mode) | ERR (the DAP's own error about its control axes) and
//  MNVR (one turn at RATE, then held in the HOLD's frame), STOP (the attitude now held); DAP AUTO /
//  CSS (the stick's rate, held where released; in AUTO the stick out of its detent goes CSS), DB and RATE. MNVR EXEC's
//  MNVR turns to the burn attitude (the OMS thrust line on VGO) and holds it INRTL. The DAP flies through KalsCoproc's
//  fly-by-wire (ADDONS:KALS:FBW3, arm.ks's hold's path), so the stick never reaches the jets: INPUT RHC reads it for
//  the page. THE BURN IS FLOWN BY THE SAME DAP, never by kOS's steering: from EXEC to the cut the DAP stays ON
//  (AUTO, INRTL): its MNVR turns to the burn attitude (the OMS thrust line on VGO) at the burn's rate (O2Q_BURN_RATE_MIN, at
//  least 1 deg/s) and deadband (O2Q_BURN_DB, at most 0.25 deg), then each cycle its reference follows the aim (PEG's VGO and the
//  trim line, the roll the MNVR left kept); the rails warps run with the DAP FREE (no jet may stop a warp; RAILSARM sets
//  the rate); the stick is read only through the sequence (no CSS downmode: the page's CSS button hands the attitude to the
//  crew); after the cut the DAP holds INRTL on the attitude at the cut, RCS left on. Without KalsCoproc's FBW3 the burn is
//  refused (NO DAP); O2Q_KOS_STEER TRUE brings back kOS's LOCK STEERING for one release. Ctrl+C: the fly-by-wire lets go in 0.5 s; SAS stays off.
//  The last ~6 s of the burn (VGO under O2Q_AIM_FREEZE_V) the aim is FROZEN (the VGO direction swings as the along part goes to 0).
//  THE BURN'S ROLL IS TV ROLL, the real MNVR item (MNVR EXEC row 10, default 180 = heads down, 0 .. 359): the orbiter's roll
//  about the OMS thrust line, measured from the local vertical (the top toward the Earth at 180; + = the star wing down), the
//  vertical now until the ignition (the aim and the roll turn with the orbit), the vertical AT the ignition during the burn
//  (inertial); the page's MNVR, OMS-2 and the deorbit burn alike (o2qAimTv: o2qAimV the fore, o2qAimT the top; lib_o2dap o2dTvAtt).
//  Writes logs/ops2q_<UT>.txt (the page and sequence events, the state at ignition and at the cut) and
//  logs/o2burn_<UT>.csv (each burn: shuttle_exec's burn_<UT>.csv columns, then VGO in body axes) when SOCK_LOG is on.
// ============================================================================
PARAMETER o2qSrcArg IS "".                   // a plan file to load first ("" = the newest written)
PARAMETER o2qPageArg IS "".                  // the page to open on ("DEORB": RUN DEORBIT_PLAN hands over to it; "" = MNVR EXEC)
GLOBAL SCRIPT_VERSION IS "ops2q v0.6 (T492 stage J1, T621 thrust line)".
RUNONCEPATH("0:/lib/lib_progreset.ks").  progReset().   // No hook of an earlier program outlives it (lib_progreset)
SET CONFIG:IPU TO 10000.                     // the patched kOS's IPU ceiling, as ops1q / deorbit_plan; set before the libraries load
RUNONCEPATH("0:/lib/lib_plan.ks").           // planRead (the plan files)
RUNONCEPATH("0:/lib/lib_logsw.ks").          // SOCK_LOG
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
kmQuiet(TRUE).                               // the terminal stays blank; the lines wait for the MSG sink (registered after o2qSay)
RUNONCEPATH("0:/lib/lib_cwui.ks").           // the caution & warning panel (lib_cw: the state, lib_cwui: the window and the tone)
RUNONCEPATH("0:/lib/lib_cwchk.ks").          // the checks' level functions (the OMS and RCS lamps)
RUNONCEPATH("0:/lib/lib_oms_plan.ks").       // omsAto / omsPlanAto / omsDvOnBoard (the ATO's OMS-2)
RUNONCEPATH("0:/lib/lib_o2ui.ks").
RUNONCEPATH("0:/lib/lib_o2orb.ks").
RUNONCEPATH("0:/lib/lib_o2peg.ks").
RUNONCEPATH("0:/lib/lib_o2line.ks").
RUNONCEPATH("0:/lib/lib_o2dap.ks").
RUNONCEPATH("0:/lib/lib_o2disp.ks").
RUNONCEPATH("0:/lib/lib_o2dorb.ks").          // DEORB TGT's planner wiring, its data and its globe
RUNONCEPATH("0:/lib/lib_o2rcs.ks").           // OMS/RCS's pure parts
RUNONCEPATH("0:/lib/lib_failui.ks").           // the FAILURES window (was lib_o2fail.ks)
RUNONCEPATH("0:/lib/lib_o2ato.ks").           // the ATO / AOA TGT page's model
RUNONCEPATH("0:/lib/lib_o2burn.ks").
RUNONCEPATH("0:/lib/lib_o2fpln.ks").          // the flight-plan tree (model)
RUNONCEPATH("0:/lib/lib_o2p8.ks").            // PEG 8, the Principia-plan guidance
RUNONCEPATH("0:/lib/lib_o2arm.ks").            // the PDRS page (the Canadarm: arm.ks hosted)
RUNONCEPATH("0:/lib/lib_o2bn.ks").           // The burn tick in C# (coproc/O2Burn.cs; the kOS side)
RUNONCEPATH("0:/lib/lib_o2orbin.ks").         // page 2: the raw values of the ORBIT / PTG page for the C# page build (O2ORBIT)
RUNONCEPATH("0:/lib/lib_o2mnvr.ks").          // The raw values of the MNVR page for the C# page build (O2MNVR)
RUNONCEPATH("0:/lib/lib_o2fpg.ks").            // the FPLN page (the tree as text, its window and cursor rules)          // the record of the burns flown (1:/o2q_burn.txt): a new RUN knows what was flown

SET O2A_SAYQ TO TRUE.                        // lib_o2arm's messages go to the MSG row
GLOBAL O2Q_DT IS 0.1.                        // s: the loop
GLOBAL O2Q_FILES IS LIST("0:/deorbit_plan.txt", "0:/oms2_plan.txt", "0:/oms1_plan.txt", "0:/ops2q_burn.txt").
GLOBAL O2Q_HO_LOG IS TRUE.                 // The three HANDOFF lines in the program log at the start (log only); FALSE = none
GLOBAL O2Q_BURN_FILE IS "0:/ops2q_burn.txt".  // stage A's edited burns (still listed; nothing writes it now)
GLOBAL O2Q_MIN_LEAD IS 60.                   // s: EXEC needs the ignition at least this far ahead (the setup + the align)
GLOBAL O2Q_OMS_ISP IS 316.                   // s: the AJ10's vacuum Isp when no engine reports one
GLOBAL O2Q_RHC_ON IS 0.5.                    // the stick's deflection that is a key press
GLOBAL O2Q_RHC_REP IS 0.4.                   // s: a held stick repeats its key this often
GLOBAL O2Q_VIEW_CX IS 448 + 135.             // the orbit view's centre on the page (px) and its radius
GLOBAL O2Q_VIEW_CY IS 50 + 135.
GLOBAL O2Q_VIEW_R IS 118.
GLOBAL O2Q_VIEW_N IS 96.                     // the drawn orbit's points
GLOBAL O2Q_EARTH_PX IS 75.                   // the Earth's drawn radius at most
// the burn sequence: shuttle_exec v3.4's values
GLOBAL O2Q_ALIGN_LEAD IS 300.                // s before TIG: the first warp ends, the burn attitude starts
GLOBAL O2Q_ALIGN_TOL IS 2.                   // deg: pointed
GLOBAL O2Q_ROLL_TOL IS 5.                    // deg: the steering's roll error, aligned
GLOBAL O2Q_TURN_K IS 1.1.                  // EXEC's MNVR need = the model's turn time x this + O2Q_TURN_PAD (p34 FAR: model 89.75 s, the DAP's capture 96 s)
GLOBAL O2Q_TURN_PAD IS 10.                 // s added (the rate null and the hold's capture)
GLOBAL O2Q_MNVR_WAIT_ON IS TRUE.           // EXEC with a MNVR turn still running finishes the turn BEFORE the first warp (the warp frees the DAP and the turn was dropped: P1b met 1101, 125.8 deg MNVR, EXEC 7.7 s later, ALIGN at TIG-5 turned 111.7 deg). Revert = FALSE
GLOBAL O2Q_ALIGN_MAX IS 180.                 // s the alignment gets
GLOBAL O2Q_WARP_RETRY IS 3.                 // A sequence warp cancelled EARLY (rate 1 long before its UT) is re-issued this many times per warp (then it goes on as before)
GLOBAL O2Q_WARP_EARLY IS 5.                 // s of UT left that still count as "arrived" (the old test used 1 s)
GLOBAL O2Q_SETTLE_LEAD IS 20.                // The second warp ends at TIG-20; s before TIG: the second warp ends. Revert = 45
GLOBAL O2Q_IGN_ERR IS 2.                     // deg, the attitude error over which the auto EXEC is HELD at TIG (the burn waits, TIG slips, PEG re-solves; the crew may press EXEC to override); 0 = off
GLOBAL O2Q_RATE_TOL IS 0.3.                  // deg/s, held O2Q_RATE_HOLD s before the fine null
GLOBAL O2Q_RATE_HOLD IS 3.
GLOBAL O2Q_RATE_FINE IS 0.01.                // deg/s: the fine null on the wheels (RCS off) before the second warp
GLOBAL O2Q_FINE_MAX IS 90.                   // s the wheels get
GLOBAL O2Q_KOS_STEER IS FALSE.               // TRUE = the burn sequence flies under kOS's cooked steering as before (the legacy path, one release; DAP on standby)
GLOBAL O2Q_BURN_RATE_MIN IS 2.0.             // deg/s, the burn attitude MNVR's rate is at least this (the page's RATE if larger)
GLOBAL O2Q_AIM_FREEZE_V IS 3.               // The freeze leaves a cross residual (the VGO direction goes on moving, the DAP's hold error rides on the frozen aim: 0.167 m/s on a stock deorbit, replay twin 13 -> 0.077, 5 -> 0.012, 3 -> 0.004); 4 m/s is ~1.7 s at the full thrust, about lib_o2peg's own O2P_HOLD_TGO. Judge by err_ang < 1 deg through the last 5 s; 6 if it swings. m/s of VGO left along the steering under which the burn's aim is FROZEN (held to the cut): the last ~6 s the VGO direction swings (the cross-track residual takes over as the along part goes to 0, in flown burns: aim 0.3 -> 2 deg/s, err 3 -> 10-13 deg); the cut is by the along part, the cross residual left is < 1 %
GLOBAL O2Q_FRZ_MEAS IS TRUE.                // FC202, the stock cut: at the aim freeze the MEASURED thrust line (OMSLINE 'meas') is put on the steering direction once (the
                                             // DAP turns the attitude by the offset, ~0.5 s time constant), instead of freezing the aim the TRIM line gave: the cross-track VGO left at
                                             // the cut = the freeze's V x the thrust's angle off the direction (the DAP's error + the trim line's miss, 'OMS LINE PRED-MEAS': stock 0.5-0.9 deg,
                                             // FAR 0.15-0.2 deg: VGO left 0.069 stock vs 0.040 FAR in the normal-tick legs). FALSE = the freeze at O2Q_AIM_FREEZE_V only
GLOBAL O2Q_FRZ_MEAS_V IS 4.5.                // m/s of VGO left along the steering where the corrected aim is frozen (the DAP has ~2 s to turn the offset; the plant
                                             // tests/o2line_selftest.ks: cross 0.002 here vs 0.016 at 3 m/s with the correction, 0.048 for a plain freeze here)
GLOBAL O2Q_FRZ_MEAS_MAX IS 4.                // deg: a measured line more off the direction than this is not trusted (a gimbal moving, a failure): the freeze as it was first built
GLOBAL O2Q_FFO IS TRUE.                      // FC202, the stock cut's cross miss: the measured thrust line's offset from the TRIM line (body pitch / yaw) is sampled ONCE early in the burn and the aim carries it
                                             // to the cut, so the correction at the freeze trims only the remainder (a 1-1.3 deg turn in the last 2 s swung the gimbal +-1 deg and left the cross).
                                             // FALSE = the correction at the freeze only
GLOBAL O2Q_FFO_T0 IS 4.                      // s into the burn where the offset's samples start (the thrust steady, the DAP settled)
GLOBAL O2Q_FFO_T1 IS 9.                      // s into the burn where they end and the bias is set
GLOBAL O2Q_FFO_N IS 20.                      // At least this many samples, else no bias (slow ticks / no line answer)
GLOBAL O2Q_BURN_DB IS 0.25.                  // deg, the burn's attitude deadband is at most this (the page's DB if smaller)
GLOBAL O2Q_BURN_K IS 0.6.                    // The burn hold's gains from the IGNITION (OMS lit: authority ~4.3 deg/s2): rate back per degree past DB (the orbit RCS-only hold keeps O2D_K 0.15: stiffer limit-cycles there)
GLOBAL O2Q_BURN_TAU IS 0.5.                  // 1.0 -> 0.5 s, the burn hold's rate-loop time constant (O2D_TAU 1.5 elsewhere): the P residual of the hold is DB + (d x TAU - RMIN) / K, so it halves; VM: the start peak 0.40 -> 0.22 (PEG 7 plant), no chatter, the same jet use
GLOBAL O2Q_BURN_DB_LIT IS 0.10.             // deg, the burn's attitude deadband from the IGNITION (with the burn gains; the RCS-only orbit hold and the ALIGN keep O2Q_BURN_DB: 0.10 there would limit-cycle); the integral sees the full error (O2D_KIFLOOR), so the held 0.3-0.5 deg offset of earlier burns closes: model 0.14 mean / 0.24 max from 10 s. Revert = 0.25.
GLOBAL O2Q_SETTLE_DB IS 0.10.                // deg, the attitude deadband from SEQ SETTLE (TIG-19 s) to the ignition. The page's DB (0.25) is a PER-AXIS box inside 2 x DB of total error (lib_o2dap), so the hold idled with jets 0 anywhere to 0.43 deg total for the whole settle. The page's DB comes back after the burn (o2qDapResume). Revert = 0.25
GLOBAL O2Q_AIM_TIG IS TRUE.                  // PEG 4's pre-ignition aim is VGO from the state at TIG, not at the burn's centre (the 1.5 deg aim step at +0.3 s). FALSE = the aim at the burn's centre.
GLOBAL O2Q_GM IS 2.                           // The OMS burn on the gimbals (and the wheels): 0 = as before (the jets fly with them), 1 = the RCS off in every burn, 2 = off with two engines, the ROLL jets only with one (its gimbal has pitch and yaw only: the real TVC DAP did the same). C# does it (KalsCoproc O2DAPSET item 16, OmsGm.cs): the jets off at 80 % thrust, back at the taper / a locked gimbal / 3 s of error over 3 deg / the cut; one-place revert: 0
GLOBAL O2Q_BURN_KI IS 0.06.                 // 0.03 -> 0.06: the full-error integral learns the thrust-onset torque twice as fast (VM: peak 0.34, from +10 s max 0.26, overshoot +0.11)
GLOBAL O2Q_PDRS_GAINS IS TRUE.              // TRUE = the hosted arm flies the DAP on O2Q_PDRS_K / O2Q_PDRS_TAU, no trim; FALSE = the orbit hold's gains (O2D_K / O2D_TAU) as before
GLOBAL O2Q_PDRS_K IS 0.6.                   // The burn hold's K: rate back per degree past DB. The orbit K 0.15 / TAU 1.5 left DB + (d x TAU - RMIN) / K = 3.2 deg against the arm's 0.3 deg/s2
GLOBAL O2Q_PDRS_TAU IS 0.5.                 // The burn hold's TAU: s, the rate loop's time constant
GLOBAL o2qPdrsGn IS FALSE.                  // The PDRS gains are on the DAP now (o2qPdrsGains)
GLOBAL O2Q_TRIM_FILE IS "1:/o2q_trim.txt".   // The pitch trim the last burn of this flight learned (the vessel's own volume, like the OMS file): ui, mass, UT
GLOBAL O2Q_SEED_K IS 0.                     // 0 = seed OFF (K 0 makes o2qSeedGet return 0: no seed line, no guard); 0.5 seeds with half the last trim. The next burn's seed = this x that trim (the DAP's sign guard drops it if it pushes the wrong way)
GLOBAL O2Q_SEED_DM IS 3.0.                   // t: the seed only when the orbiter's mass is within this of the burn that learned it
GLOBAL O2Q_SEED_MAX IS 0.2.                  // deg/s2: the seed's cap
GLOBAL O2Q_SEED_AGE IS 43200.                // s of game time: older than this the file is stale                  // deg/s2 per deg.s, the burn hold's integral trim (the OMS thrust line off the c.g.: a constant torque ~0.17 deg/s2 pitched the burns 1.7 deg); 0 elsewhere. Pass line: err_ang < 0.6 deg from 10 s in, < 1.0 at the cut
GLOBAL O2Q_RAILS_SET IS TRUE.                // the burn's second warp starts with the rate set EXACTLY (KalsCoproc RAILSARM ZERO, applied in the last frame before the pack): no NULL / FINE phases; an older DLL keeps them
GLOBAL O2Q_RAILS_SETTLE IS TRUE.              // Before a rails warp is asked for, the DLL's closed loop takes the rate to the armed one (RAILSSETTLE; the request's one impulse had no physics frame before the pack): kOS waits for it (<= O2Q_RAILS_SETTLE_TICKS physics ticks); an older DLL skips it
GLOBAL O2Q_RAILS_SETTLE_TICKS IS 150.
GLOBAL O2Q_RAILS_HOLD IS TRUE.               // a rails warp under an ops2q hold (INRTL / LVLH / TRACK) keeps the hold's rate (RAILSARM HOLD):; the DLL holds a pilot's warp request until its settle has taken the rate to the hold's (KalsAddon.Rails.cs RlGate*); an older DLL: F3b's one-shot at the request
GLOBAL O2Q_WARP_GUARD IS TRUE.               // a warp toward a loaded burn steps down so that 1x is reached O2Q_GUARD_LEAD s before TIG
GLOBAL O2Q_GUARD_LEAD IS 370.                // s before TIG at 1x (O2Q_ALIGN_LEAD + 70: time to ARM, EXEC and align)
GLOBAL O2Q_GUARD_REACT IS 3.                 // s of the loop's reaction (x the warp rate) added to the lead before a step down
GLOBAL O2Q_CTRL_PAIR IS TRUE.                // AG6 = the OMS control point for the burn, AG7 = forward after it
GLOBAL O2Q_LOG_TICKS IS 5.                   // the burn log: a row every this many physics ticks (10 Hz)
GLOBAL O2Q_STATE_HEAD IS "r,vr,vh,sma,ecc,inc,lan,argpe,ta,ap,pe,period".
GLOBAL O2Q_DAP_LOG IS 5.                     // s: the DAP's log line this often
GLOBAL O2Q_HOLDS IS LIST("INRTL", "LVLH", "TRACK", "FREE").
GLOBAL O2Q_OMS_FILE IS "1:/oms_out.txt".     // the OMS engines out (the vessel's own volume: a re-RUN keeps them out)
GLOBAL O2Q_POD_DT IS 5.                       // s: the RCS pods' parts and modules are looked up this often
GLOBAL O2Q_MSG_N IS 2.                       // the message rows: the newest on top
GLOBAL O2Q_DAP_ACT IS LEXICON("HOLD", "HOLD", "MNVR", "MNVR", "TRK", "TRACK", "RATE", "CSS RATE", "FREE", "FREE DRIFT").

GLOBAL o2qPage IS "MNVR".                    // MNVR DEORB ORBIT OMS PDRS BRN
GLOBAL o2qIn IS "PAGE".                      // the input: PAGE / RHC (changed ONLY by the pilot's INPUT PAGE / INPUT RHC press, o2qInSet)
GLOBAL O2Q_IN_FILE IS "1:/o2q_in.txt".       // the input kept on the vessel's volume (a re-RUN keeps it)
GLOBAL o2qQuit IS FALSE.
GLOBAL o2qArmed IS FALSE.
GLOBAL O2Q_TAX IS LIST("+X", "-X", "+Y", "-Y", "+Z", "-Z").     // TRACK's body axis (a drop-down list)
GLOBAL O2Q_TTG IS LIST("EARTH", "SUN").                      // TRACK's target
GLOBAL o2qAto IS LEXICON("on", FALSE, "ph", "DONE").   // the ATO / AOA hand-off: on, ho (ops1q's file), ph PRE / POST / DONE, cols, x, why, planned
GLOBAL o2qNext IS "".                        // the program to run when this one ends (OPS3 -> ops3q)
GLOBAL o2qOps3 IS FALSE.                     // the deorbit burn (or the AOA's OMS-2) is flown: the OPS3 item is on
GLOBAL o2qDb IS LEXICON().                   // DEORB TGT's last SOLVE (lib_o2dorb o2dbAfter + "peg"); empty = none
GLOBAL o2qClrT IS -1.                        // DEORB TGT's CLEAR: the UT of the first press while a deorbit burn is loaded (a second press within O2Q_CLR_WAIT s clears it too)
GLOBAL O2Q_CLR_WAIT IS 8.
GLOBAL o2qPv IS LEXICON().                   // DEORB TGT's pass preview by site (lib_o2dorb o2dbPreview); recomputed when the SITE changes or the orbit does
GLOBAL o2qPvPend IS "".                      // the site whose preview is computed next cycle (this cycle's page says COMPUTING)
GLOBAL o2qLive IS FALSE.                     // the top message is the SOLVE's progress line (replaced in place, removed at the end)
GLOBAL o2qSrc IS LIST().                     // the plan files found: LIST(LEXICON(file, name, d (its keys), real))
GLOBAL o2qLoad IS LEXICON().                 // MNVR EXEC's burn: src (name), file, tag, ut (the centre, UT), dv0 (the
                                             // source's LVLH dv, to tell an edit), tb (s)
GLOBAL o2qMsgs IS LIST().                    // the messages, newest first: LIST(text, colour class)
GLOBAL o2qDdHelp IS "".                      // the help line of the open list (it is in the MSG rows only while the list is open)
GLOBAL o2qRhcK IS "".                        // the stick's key held and when it repeats
GLOBAL o2qRhcT IS 0.
GLOBAL o2qAg4 IS AG4.
GLOBAL o2qAg6 IS AG6.                         // the action groups' states as ops2q last saw them: a change it did not make itself is a pilot press
GLOBAL o2qAg7 IS AG7.
GLOBAL o2qKeysOk IS FALSE.                   // KalsCoproc's keyboard (KEYLOCK / KEYS) is there
GLOBAL o2qKeyBuf IS LIST().                   // keys read while the loop waited (o2qInWait), handled first
GLOBAL o2qEntCyc IS FALSE.                   // the last cycle read a KalsKeys ENT (a window press now is its echo)
GLOBAL o2qEntT IS -1E9.                      // when (TIME:SECONDS)
GLOBAL o2qPassT IS -1E9.                     // UT of the last cycle's draw (the next is due O2Q_DT x the warp rate after it)
GLOBAL o2qPassRate IS 1.                     // The warp rate at that draw
GLOBAL O2Q_VIEW_PATH_DT IS 1.                 // s: the view's orbit lines (and its scale) are redrawn this often
GLOBAL o2qVw IS LEXICON("t", -1, "pg", "", "pl", LEXICON()).   // the view's last lines: t, page, pl, sc, re, paths
GLOBAL o2qKeyMode IS "OFF".                  // the mode it last said was in force
GLOBAL o2qLog IS "".
GLOBAL o2qLc IS LEXICON().                   // the orbit after the loaded burn (ORBIT / PTG draws it as BRN PLN draws its plan) and the key it was made for
GLOBAL o2qLcKey IS "".
GLOBAL o2qBrnTyped IS LIST().                // the BRN PLN target ids the pilot has changed (the others follow the live orbit)
GLOBAL o2qBrn IS LEXICON("ok", FALSE).       // BRN PLN's last SOLVE: ok, ut (the impulse), dv (LVLH LIST), el (after), type, nb (TRUE: the n-body solve's),
                                             // nodv (the Kepler solve found nothing to do), and with nb: nra / nrp (the n-body max / min radius after), kdv / kut (the Kepler solve's)
GLOBAL o2qGdWas IS FALSE.                   // SW 02 ORBIT BURN held at the last o2qGdEdge (the loss / restart is logged once)
GLOBAL o2qNbOn IS FALSE.                     // an n-body solve is running (o2qNbH: ADDONS:KALS:NBSOLVE's handle)
GLOBAL o2qNbH IS 0.
GLOBAL O2Q_J2 IS CHOOSE 0.0010826358191967033 IF SHIP:BODY:NAME = "Earth" ELSE 0.   // Sol's Earth's J2 and its reference radius (lib/entry_predict.ks EPR_J2, EPR_R_J2: Principia's own row 2)
GLOBAL O2Q_RJ2 IS 1594534.075.
GLOBAL o2qPg IS 0.                           // the page built this cycle
GLOBAL o2qSeq IS "".                         // the burn sequence: "" none, WARP SETUP SETUP2 ALIGN AIM NULL FINE (an older DLL) WARP2 SETTLE BURN
GLOBAL o2qSeqT IS 0.                         // UT the phase started
GLOBAL o2qB IS LEXICON().                    // the burn flown: ig (TIG, UT), tb, dv, peg (lib_o2peg), eng, ea (the orbit
                                             // after), the source's src / tag / d, the trigger's lit / chk / scalar / n ...
GLOBAL o2qThr IS 0.                          // LOCK THROTTLE's value (the trigger sets it)
GLOBAL o2qAimV IS V(0, 0, 0).                // LOCK STEERING's vector: the control point's fore
GLOBAL o2qAimT IS V(0, 1, 0).                // The burn attitude's top (o2qAimV is its fore): the thrust line on VGO, rolled to TV ROLL
GLOBAL o2qTvMeas IS -1.                      // The roll about the thrust line the orbiter has now (deg 0 .. 360, -1: none), from the same down
GLOBAL o2qLf IS o2lNew().                    // the steering's lagged view of the OMS thrust line (lib_o2line)
GLOBAL o2qLineT IS 0.                        // UT of the last burn tick that fed it
GLOBAL o2qBurnOn IS FALSE.                   // the trigger works while TRUE
GLOBAL o2qTrig IS FALSE.                     // the trigger exists
GLOBAL o2qDvB IS LIST().                     // the DV slider LIST(total, gained) m/s, LIST() = none (o2qPgMnvr sets it)
GLOBAL o2qRes IS LEXICON().                  // the last burn's end: peg (VGO left), why
GLOBAL o2qBurnLog IS "".
GLOBAL o2qDap IS o2dNew().                   // the orbit DAP (lib_o2dap)
GLOBAL o2qDapOk IS FALSE.                    // KalsCoproc's FBW3 is there: the DAP can fly
GLOBAL o2qDapOn IS FALSE.                    // the DAP flies (FBW3 each cycle); FALSE before RUN's start and through a burn
GLOBAL o2qDapT IS -1.                        // UT of its last tick (-1: the next tick starts afresh)
GLOBAL o2qDapAu IS V(0, 0, 0).               // FBWAUTH: deg/s2 a full command (pitch, roll, yaw), read each second
GLOBAL o2qDapAuT IS -1E9.
GLOBAL o2qDapLogT IS -1E9.
GLOBAL o2qDapDt IS 0.                        // the largest tick gap since the last log line
GLOBAL o2qGmMode IS 0.                       // The gimbal mode the DAP is told (O2DAPSET's 16th item): 0 jets fly, 1 RCS off, 2 RCS roll jets only
GLOBAL o2qGmDll IS FALSE.                    // KalsCoproc has the gimbal mode (its O2DAPCYC returns 19 items)
GLOBAL o2qGmTxt IS "IDLE".                   // The DLL's state of it (IDLE / ARMED / OFF / BACK: why)
GLOBAL o2qGmN IS 0.                          // The engines the mode was set for
GLOBAL o2qSwForced IS FALSE.                   // SW 01 forced the DAP to CSS (o2qCrewAuto gives AUTO back after RESTART SW, SAIL only)
GLOBAL o2qDapCs IS FALSE.                    // KalsCoproc's O2DAPSET: C# flies the DAP every physics tick
GLOBAL o2qWarpFree IS FALSE.                 // A sequence warp has the DAP FREE (no jet may stop it)
GLOBAL o2qBrF IS V(0, 0, 1).                 // The DAP's reference through the burn sequence: its fore (world) ...
GLOBAL o2qBrT IS V(0, 1, 0).                 // ... and its top (the roll the burn MNVR left, turned with the fore)
GLOBAL o2qAlignMax IS 180.                   // The seconds ALIGN gets under the DAP: the turn angle / the burn rate x 1.3 + 60 s, never under O2Q_ALIGN_MAX, never past the first warp's lead less the settle
GLOBAL o2qAlignTxt IS "MNVR TO BURN ATT".   // The page's ALIGN message (the angle and the time with it under the DAP)
GLOBAL o2qDapAl IS FALSE.                    // the keepalive trigger's sink
GLOBAL o2qOid IS LIST("", "").               // the OMS RM: the engines' part UIDs, L and R (set at RUN)
GLOBAL o2qOut IS LIST("", "").               // why each is out ("" = good): SHUTDOWN FLAMEOUT PC LOW GONE CREW TIMED
GLOBAL o2qOn IS LIST(FALSE, FALSE).          // seen lit since RUN: meant lit (unlit then = shut down from outside)
GLOBAL o2qOmsOff IS LIST(FALSE, FALSE).      // shut down by ops2q for a single-engine burn (relit after it)
GLOBAL o2qPcT IS LIST(0, 0).                 // the Pc test's time under 80 % (s)
GLOBAL o2qFailReq IS LIST("", "").           // a failure for the trigger to fly (in the burn the trigger owns the burn list)
GLOBAL o2qCtrl IS "FWD".                     // the control point ops2q last set (FWD = AG7, OMS = AG6; kOS cannot read it)
GLOBAL o2qVern IS LEXICON("on", FALSE, "db", 0, "rate", 0).   // JET SEL VERN: on, and the PRI deadband / rate to give back
GLOBAL o2qXf IS LEXICON("on", FALSE, "tgt", 0, "tr", "", "t", -1E9).   // XFER: running, its target %, the chunk's transfer, its start
GLOBAL o2qXtgtSet IS FALSE.                  // XFER's TGT % has its first value (the balance when the page first showed it)
GLOBAL o2qPods IS LEXICON("t", -1E9, "f", "", "a", "", "m", LIST(0, 0, 0, 0), "rcs", LIST()).   // the fuselage parts, their RCS modules
GLOBAL o2qOmsG IS LIST().                    // the OMS page's engines this build (the tapes' fill / pointer / colour)
GLOBAL o2qDapU IS V(0, 0, 0).                // the DAP's last jets command (pitch, roll, yaw): the RCS CMD lamps
GLOBAL o2qEngC IS LIST("", "").              // o2qOmsEng's engines this physics tick (o2qEngT)
GLOBAL o2qEngT IS -1.
GLOBAL o2qTbK IS "".                         // the loaded burn's engines (o2qKNames) and its length on them, last cycle
GLOBAL o2qTbL IS 0.
GLOBAL o2qP4 IS LEXICON().                   // PEG 4 on the page: its lib_o2peg burn (the target, the J2 aim,
                                             // VGO at the centre), kept cycle to cycle; empty = build afresh
GLOBAL o2qP4Rc IS LEXICON().                 // the reach test's last question (key) and its answer (ok): the J2 coast runs once per state
GLOBAL O2Q_P4_ONLY IS "PEG 4: DEORBIT ONLY, USE PEG 7 OR 8".   // the MSG when PEG 4 is refused / dropped (PEG 8 joins it)
GLOBAL o2qP8 IS LEXICON().                   // PEG 8 on the page: its lib_o2p8 burn (the aim, the last shot), kept cycle to cycle; empty = build afresh
GLOBAL o2qGuidWas IS 1.                      // the GUID before the last change (PEG 8 left: the planned dV back on the page)

// ---- the vehicle
FUNCTION o2qMu { RETURN SHIP:BODY:MU. }
FUNCTION o2qNorth { RETURN (LATLNG(90, 0):POSITION - SHIP:BODY:POSITION):NORMALIZED. }
FUNCTION o2qEqx { RETURN SOLARPRIMEVECTOR. }
FUNCTION o2qRv { RETURN SHIP:POSITION - SHIP:BODY:POSITION. }
FUNCTION o2qEls { RETURN o2Els(o2qRv(), SHIP:VELOCITY:ORBIT, o2qMu(), o2qNorth(), o2qEqx()). }
FUNCTION o2qMetOf { PARAMETER ut. RETURN ut - (TIME:SECONDS - MISSIONTIME). }
FUNCTION o2qUtOf { PARAMETER met. RETURN met + (TIME:SECONDS - MISSIONTIME). }
FUNCTION o2qOmsFind {                        // the OMS engines (lib_arm larOmsEng's match): LIST(left, right) by position
    LOCAL out IS LIST().
    FOR en IN SHIP:ENGINES {
        IF en:NAME:CONTAINS("AJ10") OR en:TITLE:CONTAINS("Manoeuvring") OR en:TITLE:CONTAINS("Maneuvering")
            OR en:TITLE:CONTAINS("Viking") { out:ADD(en). }
    }
    IF out:LENGTH = 2 {                      // left = the one on the left of the nose
        IF VDOT(out[0]:POSITION - out[1]:POSITION, SHIP:FACING:STARVECTOR) > 0 { RETURN LIST(out[1], out[0]). }
    }
    RETURN out.
}
FUNCTION o2qOmsEng {                         // OMS engine k (0 L, 1 R) by its UID, "" when it is not on the ship (found
    PARAMETER k.                             // once a physics tick)
    IF TIME:SECONDS <> o2qEngT {
        LOCAL c IS LIST("", "").
        FOR en IN SHIP:ENGINES {
            IF en:UID = o2qOid[0] { SET c[0] TO en. }
            ELSE IF en:UID = o2qOid[1] { SET c[1] TO en. }
        }
        SET o2qEngC TO c.
        SET o2qEngT TO TIME:SECONDS.
    }
    RETURN o2qEngC[k].
}
FUNCTION o2qIsEng { PARAMETER x. RETURN NOT x:ISTYPE("String"). }   // o2qOmsEng's result is an engine
FUNCTION o2qOmsK {                           // the engines a burn flies on: the good ones (not out) MNVR EXEC's OMS selects
    LOCAL sel IS ROUND(o2Val["oms"]).        // (BOTH / L / R), LIST of k
    LOCAL ks IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        IF o2qOut[k] = "" AND (sel = 0 OR sel = k + 1) AND o2qIsEng(o2qOmsEng(k)) { ks:ADD(k). }
    }
    RETURN ks.
}
FUNCTION o2qOms {                            // the burn's OMS engines (o2qOmsK's)
    LOCAL out IS LIST().
    FOR k IN o2qOmsK() { out:ADD(o2qOmsEng(k)). }
    RETURN out.
}
FUNCTION o2qOmsAll {                         // every OMS engine on the ship, good or out
    LOCAL out IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL en IS o2qOmsEng(k).
        IF o2qIsEng(en) { out:ADD(en). }
    }
    RETURN out.
}
FUNCTION o2qThrust {                         // LIST(the OMS engines' vacuum thrust along their thrust line kN, the
    LOCAL f IS 0. LOCAL fi IS 0.             // Isp s along it): the toe-in's cosine in both (2.1 % for the pair)
    LOCAL fv IS V(0, 0, 0).
    FOR en IN o2qOms() {
        LOCAL t IS en:POSSIBLETHRUSTAT(0).
        IF t <= 0 { SET t TO en:MAXTHRUSTAT(0). }
        LOCAL isp IS CHOOSE en:VISP IF en:VISP > 0 ELSE O2Q_OMS_ISP.
        SET f TO f + t. SET fi TO fi + t / isp.
        SET fv TO fv + en:FACING:FOREVECTOR * t.
    }
    IF f <= 0 { RETURN LIST(53.4 * COS(11.8), O2Q_OMS_ISP * COS(11.8)). }  // two AJ10s when none is found
    RETURN LIST(fv:MAG, fv:MAG / fi).
}
FUNCTION o2qTb {                             // s: the burn's length for dv m/s on the OMS at the mass now
    PARAMETER dv.
    LOCAL ti IS o2qThrust().
    LOCAL ve IS ti[1] * CONSTANT:G0.
    RETURN SHIP:MASS * ve * (1 - CONSTANT:E ^ (-ABS(dv) / ve)) / ti[0].
}

// ---- the plan files
FUNCTION o2qReadSrc {                        // every plan file there, newest first (written_real_days)
    SET o2qSrc TO LIST().
    LOCAL keep IS PLAN_FILE.
    FOR f IN O2Q_FILES {
        IF EXISTS(f) {
            SET PLAN_FILE TO f.
            IF planRead() {
                LOCAL d IS PLAN_D:COPY.
                LOCAL nm IS CHOOSE d["tag"] IF d:HASKEY("tag") ELSE "DEORBIT".
                IF f = O2Q_BURN_FILE { SET nm TO "EDITED " + nm. }
                LOCAL rd IS CHOOSE d["written_real_days"] IF d:HASKEY("written_real_days") ELSE 0.
                LOCAL fst IS o2bState(f, rd, CHOOSE d["burn_ut"] IF d:HASKEY("burn_ut") ELSE -1).   // "CUT" = flown, "IGN" = ended in the burn
                IF fst = "CUT" { SET nm TO "FLOWN " + nm. } ELSE IF fst = "IGN" { SET nm TO "CUT SHORT " + nm. }
                LOCAL k IS 0.
                UNTIL k >= o2qSrc:LENGTH OR o2qSrc[k]["real"] < rd { SET k TO k + 1. }
                o2qSrc:INSERT(k, LEXICON("file", f, "name", nm, "d", d, "real", rd, "flown", fst)).
            }
        }
    }
    SET PLAN_FILE TO keep.
    o2qSrcTree().                            // the tree's first burns after the plan files
}

FUNCTION o2qRerunLoad {                      // at RUN: the newest plan NOT flown is loaded; a flown one is said, not loaded
    IF o2bOps3() { SET o2qOps3 TO TRUE. }        // the deorbit burn was cut: OPS3 is on again, as it was
    IF o2qLoaded() { RETURN. }                   // (the ops1q hand-off's own plan: a pick by name, loaded as asked)
    LOCAL ld IS FALSE.
    FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH OR ld OR o2qSrc[i]["flown"] <> "" STEP { SET i TO i + 1. } DO {
        IF o2qSrc[i]["flown"] = "" AND NOT o2qSrc[i]:HASKEY("node") { o2qLoadSrc(i). SET ld TO TRUE. }   // newest first: a plan OLDER than a flown one is the flown burn's own history, not loaded
    }
    IF o2bRec:LENGTH > 0 { o2qLogLine("RERUN: " + o2bRec:LENGTH + " burn record lines, OPS3 " + o2qOps3 + ", loaded " + (CHOOSE o2qLoad["src"] IF ld ELSE "none")). }
    IF o2qSrc:LENGTH > 0 {
        IF o2qSrc[0]["flown"] <> "" {            // nothing newer than a flown plan: say why that one is not loaded
            LOCAL s0 IS o2qSrc[0].
            LOCAL nm IS s0["name"]:REPLACE("FLOWN ", ""):REPLACE("CUT SHORT ", "").
            IF s0["flown"] = "CUT" {
                LOCAL lr IS o2bLast(s0["file"], s0["real"], CHOOSE s0["d"]["burn_ut"] IF s0["d"]:HASKEY("burn_ut") ELSE -1).
                IF lr["why"] = "CUT" { o2qSay(nm + " FLOWN: NOT LOADED" + (CHOOSE ", OPS3 WHEN READY" IF o2qOps3 ELSE ""), "V"). }
                ELSE { o2qSay(nm + " ENDED SHORT: " + o2F(lr["sens"], 1, 1) + " OF " + o2F(lr["tot"], 1, 1) + " M/S (" + lr["why"] + "): REPLAN (BRN PLN)", "Y"). }
            } ELSE {                             // IGN: the program ended in the burn; nothing says how much was flown
                LOCAL rch IS FALSE.
                IF o2bIgnD3() { SET rch TO o2qReach(o2qRv(), SHIP:VELOCITY:ORBIT). }
                IF rch { SET o2qOps3 TO TRUE. }
                o2qSay(nm + " BURN CUT SHORT: " + (CHOOSE "ORBIT REACHES ENTRY, OPS3 WHEN READY" IF rch ELSE "PLAN A NEW BURN (BRN PLN)"), "Y").
            }
        } ELSE IF ld {
            IF o2qUtOf(o2Val["tig"]) < TIME:SECONDS + O2Q_MIN_LEAD {   // a plan with no record, its TIG gone: the reason, now
                o2qSay("TIG PAST OR UNDER " + O2Q_MIN_LEAD + " S AWAY: EDIT TIG OR REPLAN", "Y").
            }
        }
    }
}

FUNCTION o2qLoadSrc {                        // MNVR EXEC takes source k: its TIG and its dv in LVLH
    PARAMETER k.
    IF k < 0 OR k >= o2qSrc:LENGTH { RETURN. }
    LOCAL s IS o2qSrc[k].
    IF s:HASKEY("node") { o2qLoadNode(s["node"]). SET o2Val["src"] TO k. RETURN. }   // a tree burn
    LOCAL d IS s["d"].
    LOCAL dv IS CHOOSE d["dv"] IF d:HASKEY("dv") ELSE 0.
    LOCAL dir IS CHOOSE d["dir"] IF d:HASKEY("dir") ELSE -1.
    LOCAL dvr IS CHOOSE d["dvr"] IF d:HASKEY("dvr") ELSE 0.
    LOCAL dx IS CHOOSE dv IF dir = 1 ELSE -dv.
    LOCAL ut IS CHOOSE d["burn_ut"] IF d:HASKEY("burn_ut") ELSE TIME:SECONDS + 600.
    o2qMnvrSet(s["name"], s["file"], CHOOSE d["tag"] IF d:HASKEY("tag") ELSE "", ut, LIST(dx, 0, -dvr), "", o2flHas(o2qFpKey(ut, LIST(dx, 0, -dvr), 0))).   // a saved plan is its tree burn
    SET o2qLoad["d"] TO d.
    SET o2Val["src"] TO k.
    o2qSay(s["name"] + " LOADED: ARM WHEN READY", "V").
}

FUNCTION o2qMnvrSet {                        // MNVR EXEC's burn: centred on ut (UT), LVLH dv LIST(x, y, z)
    PARAMETER nm, f, tag, ut, dv, ty IS "", nid IS -1, nb IS FALSE.
    LOCAL tot IS SQRT(dv[0] ^ 2 + dv[1] ^ 2 + dv[2] ^ 2).
    LOCAL tb IS o2qTb(tot).
    SET o2qLoad TO LEXICON("src", nm, "file", f, "tag", tag, "ut", ut, "dv0", dv:COPY, "tb", tb, "d", LEXICON(),
        "tree", (CHOOSE o2flName(nid) IF nid >= 0 AND o2flLive(nid) ELSE "-"), "node", nid, "nb", nb, "type", CHOOSE ty IF ty <> "" ELSE o2qTypeOf(f)).   // the FPLN tree name (lib_o2fpln names it) and the burn's TYPE
    SET o2Val["tig"] TO o2qMetOf(ut - tb / 2).
    SET o2qLoad["tig0"] TO o2Val["tig"].     // the loaded TIG in MET, as the page holds it: EDITED compares MET with MET
    SET o2Val["dvx"] TO dv[0]. SET o2Val["dvy"] TO dv[1]. SET o2Val["dvz"] TO dv[2].
    SET o2qArmed TO FALSE.
    o2qP4From(ut, dv, ut - tb / 2).          // PEG 4's targets from the impulse; a deorbit plan flies PEG 4 (in the plane)
    SET o2qLoad["t4"] TO LIST(o2Val["c1"], o2Val["c2"], o2Val["ht"], o2Val["tht"]).
    SET o2Val["guid"] TO CHOOSE 0 IF f = "0:/deorbit_plan.txt" AND ABS(dv[1]) < 0.05 AND o2qImpReach(ut, dv) ELSE 1.   // and its coast reaches the interface
    SET o2qP8 TO LEXICON().
    IF o2Val["guid"] = 1 AND o2qP8Ok() { SET o2Val["guid"] TO 2. }   // a Principia / n-body burn flies PEG 8 (the deorbit keeps PEG 4, anything else PEG 7)
    SET o2qGuidWas TO ROUND(o2Val["guid"]).
}

FUNCTION o2qLoaded { RETURN o2qLoad:HASKEY("ut"). }
FUNCTION o2qSrcNames {                       // the plan files' names, the BURN drop-down's words
    LOCAL nms IS LIST().
    FOR sr IN o2qSrc { nms:ADD(sr["name"]). }
    RETURN nms.
}
FUNCTION o2qDv { RETURN LIST(o2Val["dvx"], o2Val["dvy"], o2Val["dvz"]). }
FUNCTION o2qDvTot { LOCAL d IS o2qDv(). RETURN SQRT(d[0] ^ 2 + d[1] ^ 2 + d[2] ^ 2). }
FUNCTION o2qEdited {                         // the dV or the TIG changed from the source's
    IF NOT o2qLoaded() { RETURN FALSE. }
    IF o2qPeg8() { RETURN ABS(o2Val["tig"] - o2qLoad["tig0"]) > 0.5. }   // DVX .. DVZ are the shot's VGO, not the source's
    IF o2qPeg4() AND o2qLoad:HASKEY("t4") {  // PEG 4: its targets (DVX .. DVZ are its VGO, not the source's)
        LOCAL t4 IS o2qLoad["t4"].
        IF ABS(o2Val["c1"] - t4[0]) > 0.05 OR ABS(o2Val["c2"] - t4[1]) > 1E-5 OR ABS(o2Val["ht"] - t4[2]) > 0.0005
            OR ABS(o2Val["tht"] - t4[3]) > 0.0005 { RETURN TRUE. }
        RETURN ABS(o2Val["tig"] - o2qLoad["tig0"]) > 0.5.
    }
    LOCAL d IS o2qDv().
    LOCAL d0 IS o2qLoad["dv0"].
    IF ABS(d[0] - d0[0]) + ABS(d[1] - d0[1]) + ABS(d[2] - d0[2]) > 0.001 { RETURN TRUE. }
    RETURN ABS(o2Val["tig"] - o2qLoad["tig0"]) > 0.5.     // not through the MET <-> UT offset (TIME:SECONDS - MISSIONTIME), which
}                                            // jitters by a frame of the warp rate: it flipped the row to EDITED and back in warp
FUNCTION o2qCentre { RETURN o2qUtOf(o2Val["tig"]) + o2qTb(o2qDvTot()) / 2. }   // the burn's centre, UT

// ---- PEG 4 on the page
FUNCTION o2qPeg4 { RETURN ROUND(o2Val["guid"]) = 0. }
// ---- PEG 4 only for a burn that reaches the entry interface (lib_o2peg o2p4Reach: the coast from the state after the
// burn comes down through O2P4_EI_ALT, under J2 the J2 coast's). The J2 coast runs once per state (o2qP4Rc keys it on the state
// to 100 m / 0.1 m/s): a page draw each cycle asks for it.
FUNCTION o2qReach {                          // the state after the burn rb, va (inertial): the coast reaches the interface going down
    PARAMETER rb, va.
    LOCAL k IS ROUND(rb:X / 100) + "," + ROUND(rb:Y / 100) + "," + ROUND(rb:Z / 100) + "," + ROUND(va:X * 10) + "," + ROUND(va:Y * 10) + "," + ROUND(va:Z * 10).
    IF o2qP4Rc:HASKEY("k") AND o2qP4Rc["k"] = k { RETURN o2qP4Rc["ok"]. }
    LOCAL ok IS o2p4Reach(rb, va, o2qGv(), SHIP:BODY:RADIUS).
    SET o2qP4Rc TO LEXICON("k", k, "ok", ok).
    RETURN ok.
}
FUNCTION o2qImpReach {                       // the impulse dv (LVLH) at UT ut: its coast reaches the interface
    PARAMETER ut, dv.
    LOCAL st IS o2qAt(ut).
    RETURN o2qReach(st[0], st[1] + o2FromLvlh(dv[0], dv[1], dv[2], o2Lvlh(st[0], st[1]))).
}
FUNCTION o2qP4Ok {                           // PEG 4 may be offered: no burn loaded (nothing to judge), else the burn's coast reaches the interface
    IF NOT o2qLoaded() { RETURN TRUE. }
    IF o2qPeg4() {                           // PEG 4's own burn: v' (v + VGO at the centre) once it is built
        IF o2qP4:LENGTH = 0 OR o2qP4["nosol"] { RETURN TRUE. }
        LOCAL sc IS o2qAt(o2qCentre()).
        RETURN o2qReach(sc[0], sc[1] + o2qP4["vgo"]).
    }
    RETURN o2qImpReach(o2qCentre(), o2qDv()).   // PEG 7 / 8's: the impulse at the centre
}
FUNCTION o2qGv {                             // the gravity PEG 4 aims under: Principia's J2 on Sol's Earth, else a point mass
    RETURN o2p4Grav(o2qMu(), CHOOSE O2P4_J2 IF SHIP:BODY:NAME = "Earth" ELSE 0, SHIP:BODY:ANGULARVEL).
}
FUNCTION o2qP4Tgt {                          // the target point from HT / THETA T and the TIG point on the current conic
    LOCAL st IS o2qAtJ(o2qUtOf(o2Val["tig"])).                // In the sequence the TIG point carries the J2 drift (plain conic off it)
    RETURN o2p4Tgt(st[0], o2Unit(VCRS(st[0], st[1])), o2Val["ht"] * 1000, o2Val["tht"], SHIP:BODY:RADIUS).
}
FUNCTION o2qP4From {                         // the targets of the impulse dv (LVLH) at UT ut, TIG at UT ig, onto the page
    PARAMETER ut, dv, ig.
    LOCAL st IS o2qAt(ut).
    LOCAL va IS st[1] + o2FromLvlh(dv[0], dv[1], dv[2], o2Lvlh(st[0], st[1])).
    LOCAL t4 IS o2p4FromImp(st[0], va, o2qAt(ig)[0], o2qGv(), SHIP:BODY:RADIUS).
    SET o2Val["ht"] TO t4[0] / 1000. SET o2Val["tht"] TO t4[1]. SET o2Val["c1"] TO t4[2]. SET o2Val["c2"] TO t4[3].
    SET o2qP4 TO LEXICON().
}
FUNCTION o2qP4Keep {                         // TIG moved by an engine change: THETA T re-measured to keep the point rk
    PARAMETER rk.
    LOCAL st IS o2qAt(o2qUtOf(o2Val["tig"])).
    SET o2Val["tht"] TO o2p4Ang(st[0], rk, o2Unit(VCRS(st[0], st[1]))).
    IF o2qLoad:HASKEY("t4") { SET o2qLoad["t4"][3] TO o2Val["tht"]. }
}
FUNCTION o2qP4Sync {                         // each cycle, PEG 4 loaded and no sequence: the page's burn (built afresh on a
    IF NOT o2qLoaded() OR NOT o2qPeg4() OR o2qSeq <> "" OR o2qGdLost() { RETURN. }   // SW 02 holds it. target change), its aim stepped, VGO at the
    LOCAL sc IS o2qAt(o2qCentre()).          // centre -> DVX / DVY / DVZ (the real page shows PEG 4's VGO in PEG 7's)
    LOCAL rt IS o2qP4Tgt().
    IF o2qP4:LENGTH = 0 { SET o2qP4 TO o2p4New(rt, o2Val["c1"], o2Val["c2"], o2qGv(), sc[0], sc[1]). }
    ELSE { o2p4Pre(o2qP4, rt, sc[0], sc[1], TIME:SECONDS). }
    IF o2qP4["nosol"] { RETURN. }
    IF NOT o2qReach(sc[0], sc[1] + o2qP4["vgo"]) {   // edited so the burn no longer reaches the interface: PEG 7 (DVX .. DVZ as they stand)
        SET o2Val["guid"] TO 1. SET o2qP4 TO LEXICON(). SET o2qArmed TO FALSE.
        o2qSay(O2Q_P4_ONLY, "Y").
        RETURN.
    }
    LOCAL d IS o2ToLvlh(o2qP4["vgo"], o2Lvlh(sc[0], sc[1])).
    SET o2Val["dvx"] TO d[0]. SET o2Val["dvy"] TO d[1]. SET o2Val["dvz"] TO d[2].
}

// ---- PEG 8 on the page: the Principia-plan guidance (lib_o2p8.ks). GUID's third word, available for a mirrored Principia burn or a BRN PLN burn
// whose last solve was SOLVE's n-body one; ADDONS:KALS:PEG8SOLVE shoots the velocity at the cut that meets the plan's aim (the next planned burn's ignition,
// else half an orbit after this burn) on our n-body coast. Before the sequence a shot every O2P8_DT_PRE s gives DVX .. DVZ (the shot's VGO at the burn's
// centre, read only as PEG 4's); a shot that fails before the ignition: the planned dV as PEG 7 with a MSG.
FUNCTION o2qPeg8 { RETURN ROUND(o2Val["guid"]) = 2. }
FUNCTION o2qP8Has { RETURN o2qFbwHas("PEG8SOLVE"). }
FUNCTION o2qP8Why {                          // "" = PEG 8 may be offered for the loaded burn, else the reason (ENT on the dim word says it)
    IF NOT o2qLoaded() { RETURN "PEG 8: NO BURN LOADED". }
    IF NOT o2qP8Has() { RETURN "PEG 8 NEEDS THE NEW KALSCOPROC". }
    RETURN o2p8Why(o2qLoad["node"]).
}
FUNCTION o2qP8Ok { RETURN o2qP8Why() = "". }
FUNCTION o2qDvgAt {                          // the planned dV (LVLH at the load) as an inertial vector in the LVLH frame at UT ut
    PARAMETER ut.
    LOCAL d IS o2qLoad["dv0"].
    RETURN o2FromLvlh(d[0], d[1], d[2], o2qFrameAt(ut)).
}
FUNCTION o2qP8Dv0 {                          // the planned dV back on the page (PEG 7 / 4 after PEG 8)
    IF NOT o2qLoaded() { RETURN. }
    LOCAL d IS o2qLoad["dv0"].
    SET o2Val["dvx"] TO d[0]. SET o2Val["dvy"] TO d[1]. SET o2Val["dvz"] TO d[2].
}
FUNCTION o2qP8Drop {                         // PEG 8 off: PEG 7 on the planned dV, the reason in a MSG
    PARAMETER msg.
    SET o2Val["guid"] TO 1. SET o2qGuidWas TO 1. SET o2qP8 TO LEXICON(). SET o2qArmed TO FALSE.
    o2qP8Dv0().
    o2qSay(msg, "Y").
}
FUNCTION o2qP8Sync {                         // each cycle, PEG 8 loaded and no sequence: the page's burn (built afresh on a change), a shot when due, DVX .. DVZ
    IF NOT o2qLoaded() OR NOT o2qPeg8() OR o2qSeq <> "" OR o2qGdLost() { RETURN. }   // SW 02 holds the shots
    LOCAL why IS o2qP8Why().
    IF why <> "" { o2qP8Drop(why + ": PEG 7"). RETURN. }   // the burn left (a Principia plan changed under it): PEG 7 on the planned dV
    LOCAL ct IS o2qCentre().
    IF o2qP8:LENGTH = 0 { SET o2qP8 TO o2p8New(o2qLoad["dv0"], o2qFrameAt(ct), o2p8Aim(o2qLoad["node"]), o2qGv()). }
    LOCAL pg IS o2qP8.
    LOCAL now IS TIME:SECONDS.
    IF o2p8Due(pg, now) { o2p8Shot(pg, now, o2qRv(), SHIP:VELOCITY:ORBIT, MAX(ct, now), o2qDvgAt(ct)). }
    IF pg["nosol"] OR pg["nres"] = 0 { RETURN. }
    LOCAL d IS o2ToLvlh(pg["vgo"], o2qFrameAt(ct)).
    SET o2Val["dvx"] TO d[0]. SET o2Val["dvy"] TO d[1]. SET o2Val["dvz"] TO d[2].
}
FUNCTION o2qP8Row {                          // MNVR EXEC row 4 while GUID = PEG 8: AIM T+ (the aim's UT less now) and MISS (km: the shot's own residual; after the cut, the cut's)
    PARAMETER pg.
    LOCAL p8 IS o2qP8.
    IF o2qSeq <> "" { SET p8 TO o2qB["peg"]. }
    ELSE IF NOT o2qLoaded() AND o2qRes:HASKEY("peg") { SET p8 TO o2qRes["peg"]. }
    LOCAL ok IS p8:HASKEY("p8") AND p8["nres"] > 0.
    o2Seg(pg, 4, 42, "AIM T+", CHOOSE "L" IF ok ELSE "D").
    IF ok {
        LOCAL dt IS MAX(0, p8["aimt"] - TIME:SECONDS).
        o2Read(pg, 4, 49, CHOOSE o2Ms(dt) IF dt < 6000 ELSE (FLOOR(dt / 3600) + "h" + o2P2(FLOOR(MOD(dt, 3600) / 60)))).
        o2Seg(pg, 4, 56, "MISS"). o2Read(pg, 4, 61, o2F(p8["miss"] / 1000, 6, 2) + " km").
    } ELSE {
        o2Read(pg, 4, 49, "--:--", "D"). o2Seg(pg, 4, 56, "MISS", "D"). o2Read(pg, 4, 61, "  -.-- km", "D").
    }
}

FUNCTION o2qAt {                             // the conic state LIST(r, v, el) at UT ut (the current orbit)
    PARAMETER ut.
    LOCAL el IS o2qEls().
    IF el["n"] <= 0 { RETURN LIST(o2qRv(), SHIP:VELOCITY:ORBIT, el). }
    LOCAL nu IS o2TAafter(el, el["ta"], ut - TIME:SECONDS).
    LOCAL st IS o2AtTA(el, nu).
    RETURN LIST(st[0], st[1], el).
}

// The deorbit's 1.2-1.4 deg warp-exit error: o2qAt is the osculating CONIC from now; the real orbit has J2 (Principia), so over the sequence's
// 180 s warp the predicted TIG state is off by ~1.7 m/s / 157 m (1.6 deg of the 62 m/s deorbit burn) and falls to 0.2 m/s at TIG-19 s: the PEG 4 aim re-solved
// from it moved ~1.2 deg while the DAP sat FREE in the packed warp. While a sequence runs: the state plus the first-order J2 drift over the horizon h, the
// J2 acceleration a (o2p4G with J2 less o2p4G without) taken at the conic's position at the middle of h: r + a h^2 / 2, v + a h (0.08 deg residual at h 179 s,
// 0.003 at 60 s against an RK4 J2 coast). No sequence / past ut / no J2 (not Earth): plain o2qAt (the page's plan numbers stay conic).
FUNCTION o2qAtJ {
    PARAMETER ut.
    LOCAL st IS o2qAt(ut).
    LOCAL h IS ut - TIME:SECONDS.
    IF o2qSeq = "" OR h <= 0 { RETURN st. }
    LOCAL gv IS o2qGv().
    IF gv["j2"] = 0 { RETURN st. }
    LOCAL rm IS o2qAt(TIME:SECONDS + h / 2)[0].
    LOCAL aj IS o2p4G(rm, gv) - o2p4G(rm, o2p4Grav(o2qMu(), 0, gv["ax"])).
    RETURN LIST(st[0] + aj * (h * h / 2), st[1] + aj * h, st[2]).
}

FUNCTION o2qFrameAt {                        // the LVLH frame at UT ut on the current conic
    PARAMETER ut.
    LOCAL st IS o2qAt(ut).
    RETURN o2Lvlh(st[0], st[1]).
}
FUNCTION o2qInBody {                         // an inertial vector in the orbiter's body axes LIST(X fwd, Y right, Z down):
    PARAMETER x.                             // the root part's (the nose), not the control point's (AG6: 17.8 deg down)
    LOCAL f IS SHIP:ROOTPART:FACING.
    RETURN o2pBody(x, f:FOREVECTOR, f:STARVECTOR, f:TOPVECTOR).
}
FUNCTION o2qVgo {                            // VGO now (inertial): the burn's when one runs, else the page's at its centre
    IF o2qSeq <> "" { RETURN o2qB["peg"]["vgo"]. }
    LOCAL d IS o2qDv().
    RETURN o2FromLvlh(d[0], d[1], d[2], o2qFrameAt(o2qCentre())).
}

FUNCTION o2qAfter {                          // the conic after the LVLH dv at UT ut
    PARAMETER ut, dv.
    LOCAL st IS o2qAt(ut).
    LOCAL fr IS o2Lvlh(st[0], st[1]).
    RETURN o2Els(st[0], st[1] + o2FromLvlh(dv[0], dv[1], dv[2], fr), o2qMu(), o2qNorth(), o2qEqx()).
}

// ---- the FPLN tree on the pages (lib_o2fpln: the model, lib_o2fpg: the FPLN page's tree). BRN PLN plans from FPLN STATE's conic
// (the live orbit at 0, else the conic after that burn, from its epoch); SAVE adds a child of FPLN STATE; the FPLN page edits the tree;
// the tree's first burns are in MNVR EXEC's BURN list; a burn flown leaves the tree (its siblings with it).
FUNCTION o2qBChk { IF NOT o2flLive(o2flState) { SET o2flState TO 0. } }
FUNCTION o2qBEls {                           // the conic BRN PLN plans on
    o2qBChk().
    IF o2flState = 0 { RETURN o2qEls(). }
    RETURN o2flN[o2flState]["el"].
}
FUNCTION o2qBEp {                            // its epoch (UT): now for the live orbit
    o2qBChk().
    IF o2flState = 0 { RETURN TIME:SECONDS. }
    RETURN o2flN[o2flState]["ep"].
}
FUNCTION o2qBAt {                            // LIST(r, v, el) on that conic at UT ut
    PARAMETER ut.
    o2qBChk().
    IF o2flState = 0 { RETURN o2qAt(ut). }
    LOCAL el IS o2flN[o2flState]["el"].
    LOCAL st IS o2flStateAt(el, o2flN[o2flState]["ep"], ut).
    RETURN LIST(st[0], st[1], el).
}
FUNCTION o2qBug {                            // s the orbiter bug is past the drawn conic's own anomaly: with FPLN STATE not 0 it sits where that burn ENDS
    IF o2qPage <> "BRN" { RETURN 0. }
    o2qBChk().
    RETURN o2flBugDt(o2flState).
}
FUNCTION o2qBrnGap {                         // BRN+ = the time from FPLN STATE's burn end to this burn's start (s), 0 at state 0. This burn starts tb / 2 before its
    o2qBChk().                               // TIG point once solved (as MNVR EXEC's TIG), at the TIG point before (no dV known)
    IF o2flState = 0 { RETURN 0. }
    LOCAL st IS o2qBrnUt().
    IF o2qBrn["ok"] { SET st TO st - o2qTb(SQRT(o2qBrn["dv"][0] ^ 2 + o2qBrn["dv"][1] ^ 2 + o2qBrn["dv"][2] ^ 2)) / 2. }
    RETURN st - o2flEnd(o2flState).
}
FUNCTION o2qVwSh { RETURN CHOOSE (o2qBEp() - TIME:SECONDS) IF o2qPage = "BRN" ELSE 0. }   // the view's clock: the time from the drawn conic's epoch to now

FUNCTION o2qFpKey {                          // a burn's key: the impulse UT (s), the LVLH dv (0.1 m/s) and its parent: the same burn saved twice is one node
    PARAMETER ut, dv, par.
    RETURN "K" + ROUND(ut) + "/" + ROUND(dv[0], 1) + "/" + ROUND(dv[1], 1) + "/" + ROUND(dv[2], 1) + "@" + par.
}
FUNCTION o2qFpDv {                           // a plan file's burn (its d) as the LVLH dv list, as o2qLoadSrc takes it
    PARAMETER d.
    LOCAL dv IS CHOOSE d["dv"] IF d:HASKEY("dv") ELSE 0.
    LOCAL dir IS CHOOSE d["dir"] IF d:HASKEY("dir") ELSE -1.
    LOCAL dvr IS CHOOSE d["dvr"] IF d:HASKEY("dvr") ELSE 0.
    RETURN LIST(CHOOSE dv IF dir = 1 ELSE -dv, 0, -dvr).
}
FUNCTION o2qFpPersist {
    o2flSave().
    o2qSrcTree().
}

FUNCTION o2qFpState {                        // BRN PLN row 2: FPLN STATE, a cursor field (+ / - step the tree depth-first, ENT opens the FPLN page)
    PARAMETER pg.
    o2qBChk().
    o2Seg(pg, 2, 1, "FPLN STATE").
    o2Seg(pg, 2, 13, o2flName(o2flState), "V").
    o2Fld(pg, "fstate", "A", 2, 13, o2flName(o2flState), TRUE).
    LOCAL tx IS "CURRENT".
    IF o2flState > 0 { SET tx TO o2flN[o2flState]["ty"] + " " + o2flOrb(o2flState, SHIP:BODY:RADIUS):REPLACE("x", " x ") + " km". }
    o2Read(pg, 2, 18, tx).
}
FUNCTION o2qFpStep {                         // + / - on FPLN STATE
    PARAMETER d.
    LOCAL nx IS o2flStep(o2flState, d).
    IF nx = o2flState { RETURN. }
    SET o2flState TO nx.
    SET o2flSel TO nx.
    o2qBrnTyped:CLEAR().                     // the targets follow the new orbit again
    SET o2qBrn TO LEXICON("ok", FALSE).
    o2qBrnSolve().
}

FUNCTION o2qFpSave {                         // BRN PLN's solved burn as a child of FPLN STATE: its node id, -1 when there is none to save
    IF NOT o2qBrn["ok"] { RETURN -1. }
    LOCAL tn IS LIST("CIRC", "HA", "HP", "PLANE", "DV")[o2qBrn["type"]].
    LOCAL dv IS o2qBrn["dv"].
    LOCAL key IS o2qFpKey(o2qBrn["ut"], dv, o2flState).
    LOCAL id IS o2flHas(key).
    IF id >= 0 AND o2qBrn["nb"] AND NOT o2flN[id]["nb"] {   // the same burn solved n-body after it was saved from the Kepler solve: that node becomes the n-body one
        o2flUpgrade(id, o2qBrn["ut"], dv:COPY, o2qBrn["el"], key).
        o2qFpPersist().
        RETURN id.
    }
    IF id >= 0 { o2qSay(o2flName(id) + " IS SAVED ALREADY", "V"). RETURN id. }
    LOCAL tot IS SQRT(dv[0] ^ 2 + dv[1] ^ 2 + dv[2] ^ 2).
    SET id TO o2flAdd(o2flState, "O", tn, o2qBrn["ut"], o2qBrn["ut"], dv:COPY, o2qBrn["el"], key, o2qTb(tot), o2qBrn["nb"]).
    o2qFpPersist().
    o2qSay("SAVED AS " + o2flName(id), "V").
    RETURN id.
}
FUNCTION o2qDbSave {                         // DEORB TGT's solved plan as a child of 0 (it is planned from the live orbit)
    IF NOT o2qDbOk() { o2qSay("SOLVE FIRST", "Y"). RETURN. }
    LOCAL d IS o2qDb["d"].
    LOCAL dv IS o2qFpDv(d).
    LOCAL ut IS d["burn_ut"].
    LOCAL key IS o2qFpKey(ut, dv, 0).
    LOCAL id IS o2flHas(key).
    IF id >= 0 { o2qSay(o2flName(id) + " IS SAVED ALREADY", "V"). RETURN. }
    LOCAL tot IS SQRT(dv[0] ^ 2 + dv[1] ^ 2 + dv[2] ^ 2).
    SET id TO o2flAdd(0, "O", "DEORB", ut, ut, dv, o2qAfter(ut, dv), key, o2qTb(tot)).
    o2qFpPersist().
    o2qSay("SAVED AS " + o2flName(id), "V").
}

FUNCTION o2qDbKids {                         // the saved deorbit burns: node 0's live children of type DEORB (DEORB TGT's SAVE -> FPLN)
    LOCAL out IS LIST().
    FOR id IN o2flN[0]["kids"] { IF o2flLive(id) AND o2flN[id]["ty"] = "DEORB" AND o2flN[id]["src"] = "O" { out:ADD(id). } }
    RETURN out.
}
FUNCTION o2qDbLoaded {                       // the loaded MNVR burn is a deorbit one (DEORB TGT's plan file or its saved tree burn)
    RETURN o2qLoaded() AND o2qLoad["type"] = "DEORB".
}
FUNCTION o2qDbClrOn {                        // CLEAR has something to clear
    RETURN o2qDb:LENGTH > 0 OR o2qDbKids():LENGTH > 0 OR o2qDbLoaded().
}
FUNCTION o2qDbClear {                        // The last SOLVE, its saved FPLN burn and the MNVR burn made from it go
    IF NOT o2qDbClrOn() { RETURN. }
    LOCAL ld IS o2qDbLoaded().
    IF ld AND (o2qClrT < 0 OR TIME:SECONDS - o2qClrT > O2Q_CLR_WAIT OR TIME:SECONDS < o2qClrT) {   // a loaded burn: two presses
        SET o2qClrT TO TIME:SECONDS.
        o2qSay(o2qLoad["src"] + " IS LOADED IN MNVR: CLEAR AGAIN TO UNLOAD", "Y").
        RETURN.
    }
    SET o2qClrT TO -1.
    LOCAL what IS LIST().
    IF ld { LOCAL nm IS o2qLoad["src"]. o2qUnld(). what:ADD("LOADED " + nm). }    // before the tree burn it may stand on goes
    LOCAL kids IS o2qDbKids().
    IF kids:LENGTH > 0 {
        LOCAL nms IS "".
        LOCAL under IS 0.
        FOR id IN kids {
            SET nms TO nms + (CHOOSE " " IF nms <> "" ELSE "") + o2flName(id).
            SET under TO under + o2flDel(id) - 1.
        }
        o2qFpPersist().
        what:ADD("FPLN " + nms + (CHOOSE " (+" + under + " UNDER)" IF under > 0 ELSE "")).
    }
    IF o2qDb:LENGTH > 0 { SET o2qDb TO LEXICON(). what:ADD("SOLVED PLAN"). }
    SET o2Val["dpass"] TO 1.                 // T1020: the nearest pass again
    SET o2qPv TO LEXICON().                  // the pass preview is recomputed for the page's SITE
    LOCAL txt IS "".
    FOR w IN what { SET txt TO txt + (CHOOSE ", " IF txt <> "" ELSE "") + w. }
    o2qSay("DEORB TGT CLEARED: " + txt, "V").
    o2qLogLine("DEORB TGT CLEARED: " + txt).
}

FUNCTION o2qSrcTree {                        // the BURN list's tree entries: the burns planned from the live orbit (node 0's kids), after the plan files
    FROM { LOCAL i IS o2qSrc:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO { IF o2qSrc[i]:HASKEY("node") { o2qSrc:REMOVE(i). } }
    LOCAL fk IS LIST().                      // the plan files' own burns (a saved DEORB plan is its file's entry, not twice)
    FOR sr IN o2qSrc { IF sr["file"] = "0:/deorbit_plan.txt" { fk:ADD(o2qFpKey(CHOOSE sr["d"]["burn_ut"] IF sr["d"]:HASKEY("burn_ut") ELSE 0, o2qFpDv(sr["d"]), 0)). } }
    FOR id IN o2flN[0]["kids"] {
        IF o2flLive(id) AND NOT fk:CONTAINS(o2flN[id]["key"]) {
            o2qSrc:ADD(LEXICON("file", "", "name", o2flName(id) + " " + o2flN[id]["ty"] + (CHOOSE " P" IF o2flN[id]["src"] = "P" ELSE ""),
                "d", LEXICON("burn_ut", o2flN[id]["ut"]), "real", -1, "flown", "", "node", id)).
        }
    }
}
FUNCTION o2qLoadNode {                       // MNVR EXEC takes a tree burn
    PARAMETER nid.
    IF NOT o2flLive(nid) { RETURN. }
    LOCAL nd IS o2flN[nid].
    IF nd["ty"] = "DEORB" {                  // a saved deorbit burn: its plan file's entry when that is still the same burn (PEG 4, OPS3)
        FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH STEP { SET i TO i + 1. } DO {
            IF o2qSrc[i]["file"] = "0:/deorbit_plan.txt" AND o2qSrc[i]["flown"] = "" AND o2qSrc[i]["d"]:HASKEY("burn_ut") {
                IF o2qFpKey(o2qSrc[i]["d"]["burn_ut"], o2qFpDv(o2qSrc[i]["d"]), 0) = nd["key"] { o2qLoadSrc(i). RETURN. }
            }
        }
    }
    o2qMnvrSet("FPLN " + o2flName(nid), "", "BRN PLN", CHOOSE nd["ep"] + nd["tb"] / 2 IF nd["src"] = "P" ELSE nd["ut"], nd["dv"]:COPY, nd["ty"], nid, nd["nb"]).   // our burn centred on Principia's midpoint
    o2qSay(o2flName(nid) + " LOADED: ARM WHEN READY", "V").
}

FUNCTION o2qFpAct {                          // the FPLN page's and the tree's items: TRUE when id was one of them
    PARAMETER id.
    LOCAL nid IS o2gNodeId(id).
    IF nid >= 0 { o2gEnter(nid). RETURN TRUE. }
    IF id = "fstate" { o2gOpen(o2flState). o2qGo("FPLN"). RETURN TRUE. }
    IF id = "tree" { o2gOpen(o2flSel). o2qGo("FPLN"). RETURN TRUE. }
    IF id = "fset" {
        o2flSetPath(o2flSel).
        LOCAL pth IS o2flPath().
        o2qSay("PATH " + o2flName(o2flTip) + " SET", "V").
        IF pth:LENGTH > 1 AND o2qSeq = "" {
            LOCAL f1 IS pth[1].
            IF NOT (o2qLoaded() AND o2qLoad["node"] = f1) { o2qLoadNode(f1). }
        }
        RETURN TRUE.
    }
    IF id = "fplan" {
        SET o2flState TO o2flSel.
        o2qBrnTyped:CLEAR().
        SET o2qBrn TO LEXICON("ok", FALSE).
        o2qGo("BRN").
        o2qBrnSolve().
        RETURN TRUE.
    }
    IF id = "fdel" {
        IF o2flSel <= 0 OR o2flN[o2flSel]["src"] = "P" { RETURN TRUE. }
        LOCAL nm IS o2flName(o2flSel).
        LOCAL n IS o2flDel(o2flSel).
        o2qFpPersist().
        o2qSay("DELETED " + nm + (CHOOSE (" AND " + (n - 1) + " UNDER IT") IF n > 1 ELSE ""), "V").
        RETURN TRUE.
    }
    IF id = "fcopy" {                        // a burn (Principia's or our own O) into BRN PLN as a DV burn (its LVLH dV at its time), planned from its parent
        IF o2flSel <= 0 OR NOT o2flLive(o2flSel) { RETURN TRUE. }
        LOCAL nd IS o2flN[o2flSel].
        LOCAL cpName IS o2flName(o2flSel).   // An O node stores the same LVLH dV at its ut as a P node (the solve's dl), so the same copy
        SET o2flState TO nd["par"].
        o2qBrnTyped:CLEAR().
        SET o2Val["btype"] TO 4. SET o2Val["bwhen"] TO 4.
        SET o2Val["btig"] TO o2qMetOf(nd["ut"]).
        SET o2Val["bdx"] TO nd["dv"][0]. SET o2Val["bdy"] TO nd["dv"][1]. SET o2Val["bdz"] TO nd["dv"][2].
        o2qBrnTyped:ADD("bdx"). o2qBrnTyped:ADD("bdy"). o2qBrnTyped:ADD("bdz").
        SET o2qBrn TO LEXICON("ok", FALSE).
        o2qGo("BRN").
        o2qBrnSolve().
        o2qSay("COPIED " + cpName + " TO BRN PLN", "V").   // The original node stays (DELETE removes it)
        RETURN TRUE.
    }
    RETURN FALSE.
}

FUNCTION o2qPgFpln {                         // the FPLN TREE page
    LOCAL pg IS o2PgNew().
    o2qHead(pg, "2024/", "FPLN TREE", 0).
    LOCAL el IS o2qEls().
    LOCAL lv IS "NOT IN ORBIT".
    IF el["n"] > 0 { SET lv TO ROUND(o2qKm(el["ra"])) + " x " + ROUND(o2qKm(el["rp"])). }
    o2gTree(pg, LEXICON("met0", TIME:SECONDS - MISSIONTIME, "rad", SHIP:BODY:RADIUS, "live", lv)).
    o2qMsgRow(pg, 18).
    RETURN pg.
}

// ---- Principia's flight plans mirrored into the FPLN tree (READ ONLY: KalsCoproc's PRFPLN reads, nothing is sent back).
// Once a second: PRFPLN(FALSE) = the signature of the selected plan + the plan count + the selection; only when it changed, PRFPLN(TRUE)
// = every plan read (the DLL selects each in turn and puts the selection back) -> one branch under node 0 per plan, its burns the nodes.
GLOBAL o2qPrNext IS 0.
GLOBAL o2qPrSig IS "".
GLOBAL o2qPrWhy IS "".
FUNCTION o2qPrApply {                        // a full read (PRFPLN(TRUE)) into the tree: the mirror's counts
    PARAMETER fr.
    LOCAL plans IS LIST().
    LOCAL mu IS o2qMu().
    LOCAL pole IS o2qNorth().
    LOCAL eqx IS o2qEqx().
    LOCAL nb IS 0.
    FOR pln IN fr["plans"] {
        LOCAL bl IS LIST().
        FOR bn IN pln {
            bl:ADD(o2flPrRec(bn["p"], bn["i"], bn["ig"], bn["tc"], bn["tb"], bn["r"], bn["v"], bn["dv"], mu, pole, eqx)).
            SET nb TO nb + 1.
        }
        plans:ADD(bl).
    }
    LOCAL rs IS o2flMirror(plans).
    o2flSave().
    o2qSrcTree().
    RETURN rs.
}
FUNCTION o2qPrSay {                          // a reason the mirror cannot read: only the ones the pilot can act on, once each
    PARAMETER why.
    IF why = o2qPrWhy { RETURN. }
    SET o2qPrWhy TO why.
    LOCAL bn IS SHIP:BODY:NAME:TOUPPER.      // "EARTH, NON-ROTATING" -> "ECI" (the DLL's text, body-named)
    IF why:CONTAINS("plotting frame") OR why:CONTAINS("Principia read") { o2qSay("PRINCIPIA: " + why:TOUPPER:REPLACE(bn + ", NON-ROTATING", bn:SUBSTRING(0, 1) + "CI"), "Y"). }
}
FUNCTION o2qPrTick {                         // the main loop's step: about once a second, none in a burn sequence
    IF TIME:SECONDS < o2qPrNext OR o2qSeq <> "" { RETURN. }
    SET o2qPrNext TO TIME:SECONDS + 1.
    IF NOT o2qFbwHas("PRFPLN") { SET o2qPrNext TO TIME:SECONDS + 30. RETURN. }   // an older KalsCoproc
    LOCAL r0 IS ADDONS:KALS:PRFPLN(FALSE).
    IF NOT r0["ok"] { o2qPrSay(r0["why"]). SET o2qPrNext TO TIME:SECONDS + 5. RETURN. }
    IF r0["sig"] = o2qPrSig { RETURN. }
    LOCAL fr IS ADDONS:KALS:PRFPLN(TRUE).
    IF NOT fr["ok"] { o2qPrSay(fr["why"]). SET o2qPrNext TO TIME:SECONDS + 5. RETURN. }
    SET o2qPrSig TO fr["sig"].
    SET o2qPrWhy TO "".
    o2qPrApply(fr).
}

FUNCTION o2qSay {                           // a message on top of the MSG rows, the older ones under it
    PARAMETER s, cl IS "V".
    o2qMsgs:INSERT(0, LIST(s, cl)).
    IF o2qMsgs:LENGTH > O2Q_MSG_N { o2qMsgs:REMOVE(O2Q_MSG_N). }
    o2qLogLine("MSG " + s).
}
FUNCTION o2qLogLine {
    PARAMETER s.
    IF o2qLog <> "" { LOG ROUND(MISSIONTIME, 1) + " " + s TO o2qLog. }
}
FUNCTION o2qKmSink {                        // lib_kmsg's lines (a library's warning, a failed C# draw) on the MSG rows; o2qSay logs them
    PARAMETER s, lv.
    o2qSay(s, CHOOSE "R" IF lv = "W" ELSE (CHOOSE "Y" IF lv = "C" ELSE "V")).
}
kmSink(o2qKmSink@).
FUNCTION o2qCwMet { RETURN MISSIONTIME. }
cwInit(o2qCwMet@).                          // every C / W line kmSay says becomes a row of the panel (and lights the lamp its text maps to)
cwListen().
FUNCTION o2qKm { PARAMETER rm. RETURN (rm - SHIP:BODY:RADIUS) / 1000. }

// ---- the field rules (once)
FUNCTION o2qDefs {
    o2Def("src", "C", 0).
    o2Def("oms", "C", 0).
    o2Def("guid", "C", 1).
    o2Def("tig", "T", MISSIONTIME + 600, 60, 0, 1E8, 1, 36000, 0).
    o2Def("dvx", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("dvy", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("dvz", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("c1", "N", 0, 1, -9999, 9999, 0.1, 1000, 1).          // PEG 4: m/s
    o2Def("c2", "N", 0, 0.001, -2, 2, 0.00001, 0.1, 5).
    o2Def("ht", "N", 80, 0.1, 0, 2000, 0.001, 100, 3).          // km
    o2Def("tht", "N", 0, 0.1, 0, 360, 0.001, 90, 3).            // deg
    o2Def("btype", "C", 0).                  // CIRC HA HP PLANE DV
    o2Def("bwhen", "C", 0).                  // APO PERI AN DN TIME T+
    o2Def("btig", "T", MISSIONTIME + 1200, 60, 0, 1E8, 1, 36000, 0).
    o2Def("bdt", "T", 600, 60, 0, 1E7, 1, 36000, 0).
    o2Def("bha", "N", 212, 1, 0, 5000, 0.1, 100, 1).
    o2Def("bhp", "N", 205, 1, 0, 5000, 0.1, 100, 1).
    o2Def("binc", "N", 28.5, 0.1, 0, 180, 0.01, 10, 2).
    o2Def("bdx", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("bdy", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("bdz", "N", 0, 0.1, -999, 999, 0.01, 100, 1).
    o2Def("hold", "C", 0).                   // INRTL LVLH TRACK FREE
    o2Def("tax", "C", 5).                    // TRACK's body axis +X -X +Y -Y +Z -Z (-Z: the bay)
    o2Def("ttg", "C", 0).                    // TRACK's target EARTH SUN
    o2Def("tom", "N", 0, 1, -180, 180, 0.1, 90, 1).   // TRACK's omicron: the roll about the line of sight, deg
    o2Def("tvr", "N", 180, 1, 0, 359, 0.1, 90, 1).    // TV ROLL, the burn's roll about the thrust line from the local vertical at ignition (180 = heads down)
    o2Def("dmode", "C", 0).                  // AUTO CSS
    o2Def("ddb", "N", 0.5, 0.1, 0.05, 10, 0.01, 1, 2).   // The page starts at 0.5; O2D_DB0 (lib_o2dap) stays 1.0
    o2Def("drate", "N", 2.0, 0.1, 0.01, 5, 0.01, 1, 2).   // The page RATE starts at 2 deg/s (was O2D_RATE0 = 0.5)
    o2Def("tr", "N", 0, 1, -180, 180, 0.1, 90, 1).
    o2Def("tp", "N", 0, 1, -90, 90, 0.1, 90, 1).
    o2Def("ty", "N", 0, 1, -180, 180, 0.1, 90, 1).
    o2Def("jsel", "C", 0).                   // JET SEL PRI VERN
    o2Def("ctrl", "C", 0).                   // CTRL FRM FWD OMS
    o2Def("xtgt", "N", 50, 1, 0, 100, 0.1, 10, 1).   // XFER's target balance, %
    o2Def("dsite", "C", 0).                  // DEORB TGT: SITE (O2DB_SITES)
    o2Def("drwy", "C", 0).                   // RWY: AUTO / the site's two ends
    o2Def("apick", "C", 2).                  // the ATO / AOA page's SELECT: ATO AOA AUTO
    o2Def("dmd", "C", 0).                    // MODE: FULL / COARSE (not "dmode": the DAP's)
    o2Def("dpass", "N", 1, 1, 1, O2DB_PASSES, 1, 1, 0).   // T1020: the PASS X of N, selectable: + / - or TYPE (1 .. O2DB_PASSES, whole numbers)
    o2aDefs().                               // PDRS's fields
}

// ---- the pages: each builds o2qPg afresh (lib_o2ui), its columns as the previews'
FUNCTION o2qHead {                           // the page id, its name, the MET; TIG's countdown under it
    PARAMETER pg, id, nm, tigUt.
    o2Seg(pg, 0, 1, id).
    o2Seg(pg, 0, 18, nm).
    o2Read(pg, 0, 64, o2Met(MISSIONTIME)).
    IF tigUt > 0 { o2Seg(pg, 1, 60, "TIG"). o2Read(pg, 1, 64, o2Cd(tigUt - TIME:SECONDS)). }
}

FUNCTION o2qMsgRow {
    PARAMETER pg, row.
    o2Seg(pg, row, 1, "MSG").
    IF o2Msg <> "" { o2qSay(o2Msg, o2MsgCls). SET o2Msg TO "". }
    FROM { LOCAL i IS 0. } UNTIL i >= o2qMsgs:LENGTH STEP { SET i TO i + 1. } DO {
        o2Read(pg, row + i, 8, o2qMsgs[i][0], o2qMsgs[i][1]).
    }
}

FUNCTION o2qTypeOf {                         // a loaded burn's TYPE from its plan file (BRN PLN's LOAD names its own)
    PARAMETER f.
    IF f = "0:/deorbit_plan.txt" { RETURN "DEORB". }
    IF f = "0:/oms2_plan.txt" { RETURN "OMS-2". }
    IF f = "0:/oms1_plan.txt" { RETURN "OMS-1". }
    RETURN "DV".
}

FUNCTION o2qPgMnvr {
    LOCAL pg IS o2PgNew().
    LOCAL ld IS o2qLoaded().
    LOCAL ro IS o2qSeq <> "".                // the burn is frozen while its sequence runs
    LOCAL post IS NOT ld AND o2qSeq = "" AND o2qRes:HASKEY("peg").   // the burn just ended: its page stays, read only
    LOCAL sh IS ld OR post.                  // a burn to show
    LOCAL p4 IS ld AND o2qPeg4().            // PEG 4: DVX .. DVZ read only (its VGO), its targets the fields
    LOCAL p8 IS ld AND o2qPeg8().            // PEG 8: DVX .. DVZ read only (the shot's VGO)
    LOCAL tig IS CHOOSE o2qUtOf(o2Val["tig"]) IF sh ELSE 0.
    LOCAL tot IS o2qDvTot().
    o2qHead(pg, "2021/", "MNVR EXEC", 0).
    // row 1: OMS | TIG
    o2Seg(pg, 1, 1, "OMS").
    o2Choice(pg, "oms", 1, LIST(LIST(8, "BOTH"), LIST(15, "L"), LIST(19, "R"), LIST(23, "RCS")),
        NOT ro AND (o2qOut[0] = "" OR o2qOut[1] = ""), o2qOmsDim()).
    o2Seg(pg, 1, 42, "TIG").
    IF ld AND NOT ro { o2Num(pg, "tig", 1, 49, o2Met(o2Val["tig"])). }
    ELSE IF sh { o2Read(pg, 1, 49, o2Met(o2Val["tig"])). }
    ELSE { o2Read(pg, 1, 49, "---/--:--:--", "D"). }
    // row 2: GUID | the TIG countdown
    o2Seg(pg, 2, 1, "GUID").
    LOCAL gdim IS LIST().                    // PEG 4 dim (its reason on ENT) while the loaded burn's coast does not reach the interface
    LOCAL gwhy IS LIST(O2Q_P4_ONLY, "", "").
    IF NOT o2qPeg4() AND NOT o2qP4Ok() { gdim:ADD(0). }
    LOCAL w8 IS o2qP8Why().                  // PEG 8 dim (its reason on ENT) unless the loaded burn is a Principia / n-body one
    IF w8 <> "" { gdim:ADD(2). SET gwhy[2] TO "-". }   // dim, no text on ENT
    o2Choice(pg, "guid", 2, LIST(LIST(8, "PEG 4"), LIST(15, "PEG 7"), LIST(22, "PEG 8")), NOT ro, gdim, gwhy).
    IF sh { o2Read(pg, 2, 49, o2Cd(tig - TIME:SECONDS)). }
    // row 3: BURN (the FPLN tree name; the source choice while there are several plan files) | WT
    o2Seg(pg, 3, 1, "BURN").
    IF ld {
        LOCAL st IS (CHOOSE o2flName(o2qLoad["node"]) IF o2qLoad["node"] >= 0 AND o2flLive(o2qLoad["node"]) ELSE o2qLoad["tree"]) + (CHOOSE " (EDITED)" IF o2qEdited() ELSE "").
        IF o2qSrc:LENGTH > 1 AND NOT ro {    // a word item, its plan files in a drop-down list
            o2Drop(pg, "src", 3, 8, st, o2qSrcNames(), TRUE).
        } ELSE { o2Read(pg, 3, 8, st). }
    } ELSE IF post { o2Read(pg, 3, 8, o2qRes["tree"]). }
    ELSE IF o2qSrc:LENGTH > 0 AND NOT ro {   // after UNLD a plan file can be loaded again
        SET o2Val["src"] TO -1.              // No entry is the selected one now, so the list's cursor can pick ANY entry, the one that was loaded included (a pick of the selected value is no change)
        o2Drop(pg, "src", 3, 8, "- NONE (SELECT)", o2qSrcNames(), TRUE).
    }
    ELSE { o2Read(pg, 3, 8, "- NONE (BRN PLN / DEORB)", "D"). }
    o2Seg(pg, 3, 42, "WT"). o2Read(pg, 3, 49, o2F(SHIP:MASS * 1000, 5, 0)). o2Seg(pg, 3, 55, "kg").
    // row 4: TYPE | AIM T+ / MISS (while GUID = PEG 8 only; PEG 8 is the flight-plan-matching mode)
    o2Seg(pg, 4, 1, "TYPE").
    IF ld { o2Read(pg, 4, 8, o2qLoad["type"]). }
    ELSE IF post { o2Read(pg, 4, 8, o2qRes["type"]). }
    ELSE { o2Read(pg, 4, 8, "-", "D"). }
    IF ROUND(o2Val["guid"]) = 2 { o2qP8Row(pg). }
    // rows 5-6: the DV slider (sprites, o2qDvBar); the live VGO below sets its fill
    o2Seg(pg, 7, 1, "PEG 7  LVLH  m/s").
    o2Seg(pg, 7, 42, "BURN ATT").
    LOCAL nm IS LIST("DVX", "DVY", "DVZ").
    LOCAL id IS LIST("dvx", "dvy", "dvz").
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        o2Seg(pg, 8 + i, 3, nm[i]).
        IF ld AND NOT ro AND NOT p4 AND NOT p8 { o2Num(pg, id[i], 8 + i, 8, o2Sg(o2Val[id[i]], 6, 1)). }
        ELSE IF sh { o2Read(pg, 8 + i, 8, o2Sg(o2Val[id[i]], 6, 1)). }
        ELSE { o2Read(pg, 8 + i, 8, "  ----", "D"). }
    }
    // the burn attitude: the dV's direction in LVLH, as R / P / Y (the nose along it, wings level)
    LOCAL d IS o2qDv().
    IF sh AND tot > 0.01 {
        LOCAL pt IS ARCSIN(MAX(-1, MIN(1, -d[2] / tot))).
        LOCAL yw IS ARCTAN2(d[1], d[0]).
        o2Seg(pg, 8, 42, "R"). o2Read(pg, 8, 44, o2F(o2Val["tvr"], 5, 1)).   // The roll is TV ROLL (about the thrust line, ~ the nose)
        o2Seg(pg, 8, 51, "P"). o2Read(pg, 8, 53, o2F(pt, 5, 1)).
        o2Seg(pg, 8, 60, "Y"). o2Read(pg, 8, 62, o2F(yw, 5, 1)).
    }
    o2Act(pg, "mnvr", 9, 42, "MNVR", ld AND NOT ro AND o2qDapOn AND tot > 0.01).
    o2Seg(pg, 9, 51, "ATT ERR").
    IF o2qB:HASKEY("steer") AND ro { o2Read(pg, 9, 60, o2F(VANG(SHIP:FACING:FOREVECTOR, o2qAimV), 5, 1)). }
    ELSE IF ld AND tot > 0.01 { o2Read(pg, 9, 60, o2F(VANG(o2qLine(o2qOms()), o2qVgo()), 5, 1)). }   // the thrust line off VGO
    ELSE { o2Read(pg, 9, 60, "  -.-", "D"). }
    // row 10: TV ROLL: the roll about the thrust line from the local vertical at ignition, 180 = heads down (the real MNVR item)
    o2Seg(pg, 10, 42, "TV ROLL").
    IF ld AND NOT ro { o2Num(pg, "tvr", 10, 50, o2F(o2Val["tvr"], 5, 1)). }
    ELSE IF sh { o2Read(pg, 10, 50, o2F(o2Val["tvr"], 5, 1)). }
    ELSE { o2Read(pg, 10, 50, "  ---", "D"). }
    o2Seg(pg, 10, 56, "deg").
    // row 11: PEG 4's targets, one row (dim until GUID = PEG 4)
    IF p4 {
        o2Seg(pg, 11, 1, "PEG 4"). o2Seg(pg, 11, 8, "C1"). o2Seg(pg, 11, 19, "C2"). o2Seg(pg, 11, 31, "HT").
        o2Seg(pg, 11, 42, "THETA T").
        LOCAL tx IS LIST(o2Sg(o2Val["c1"], 7, 1), o2Sg(o2Val["c2"], 7, 5), o2F(o2Val["ht"], 7, 3), o2F(o2Val["tht"], 7, 3)).
        LOCAL fi IS LIST("c1", "c2", "ht", "tht").
        LOCAL fc IS LIST(11, 22, 34, 50).
        FROM { LOCAL i IS 0. } UNTIL i >= 4 STEP { SET i TO i + 1. } DO {
            IF ro { o2Read(pg, 11, fc[i], tx[i]). } ELSE { o2Num(pg, fi[i], 11, fc[i], tx[i]). }
        }
        IF NOT ro AND o2qP4:HASKEY("nosol") { IF o2qP4["nosol"] { o2Read(pg, 11, 58, "NO SOLUTION", "R"). } }
    } ELSE IF p8 {                           // PEG 8's aim and its shot's state
        LOCAL ai IS o2p8Aim(o2qLoad["node"]).
        o2Seg(pg, 11, 1, "PEG 8"). o2Seg(pg, 11, 8, "AIM"). o2Read(pg, 11, 12, CHOOSE ("BURN " + ai["next"] + " IGNITION") IF ai["next"] <> "" ELSE "HALF AN ORBIT ON").
        IF o2qP8:HASKEY("nosol") AND o2qP8["nosol"] { o2Read(pg, 11, 42, o2qP8["why"]:TOUPPER:SUBSTRING(0, MIN(30, o2qP8["why"]:LENGTH)), "R"). }
        ELSE IF o2qP8:HASKEY("nres") AND o2qP8["nres"] > 0 { o2Seg(pg, 11, 42, "PEG 7 WOULD MISS"). o2Read(pg, 11, 59, o2F(o2qP8["missP"] / 1000, 6, 2) + " km"). }
    } ELSE { o2Seg(pg, 11, 1, "PEG 4  C1 -----  C2 -----  HT ---.-", "D"). o2Seg(pg, 11, 42, "THETA T  ----", "D"). }
    // rows 12-15: the VGO block (TOT with TBRN / TGO, VGX .. VGZ in LVLH; HA over HP in the right column)
    LOCAL gt IS 0.
    LOCAL gdl IS o2qGdLost().                // SW 02 ORBIT BURN: the guidance-fed rows (TGO once the burn runs, VGX / VGY / VGZ) show dashes, VGO TOT stays
    IF sh {
        // VGO in LVLH (X forward along the motion, Y per O2_LH, Z down; the axes of the page's DVX / DVY / DVZ).
        // Before the ignition the frame is the one AT THE BURN'S CENTRE (the planned DV's own: the rows read DVX / DVY / DVZ); from the ignition and after the cut it is the orbiter's LVLH NOW (the burn's VGO is fixed in inertial space, it turns in LVLH as the orbit goes round).
        LOCAL g IS CHOOSE o2qRes["peg"]["vgo"] IF post ELSE o2qVgo().
        LOCAL gfr IS CHOOSE o2Lvlh(o2qRv(), SHIP:VELOCITY:ORBIT) IF (o2qSeq = "BURN" OR post) ELSE o2qFrameAt(o2qCentre()).
        LOCAL gb IS o2ToLvlh(g, gfr).    // LVLH LIST(X, Y, Z); row 16's RCS TRIM stays in body axes (o2qInBody)
        SET gt TO CHOOSE o2pAlong(o2qB["peg"]) IF o2qSeq = "BURN" ELSE g:MAG.
        LOCAL tg IS o2qTb(tot).
        LOCAL burnt IS o2qSeq = "BURN" OR post.   // TGO once the burn runs (and after it), TBRN (the planned length) before it
        IF o2qSeq = "BURN" {
            LOCAL ti IS o2qThrust().
            SET tg TO o2pTgo(gt, ti[0] / SHIP:MASS, ti[1] * CONSTANT:G0).
        }
        IF post { SET tg TO 0. }
        o2Seg(pg, 12, 1, "VGO"). o2Seg(pg, 12, 8, "TOT"). o2Read(pg, 12, 12, o2F(gt, 5, 1)). o2Seg(pg, 12, 18, "m/s").
        o2Seg(pg, 12, 42, CHOOSE "TGO" IF burnt ELSE "TBRN"). o2Read(pg, 12, 49, CHOOSE "-----" IF (gdl AND burnt) ELSE o2Ms(tg)).
        o2Seg(pg, 13, 3, "VGX"). o2Read(pg, 13, 8, CHOOSE "------" IF gdl ELSE o2Sv(gb[0], 5, 1)).
        o2Seg(pg, 14, 3, "VGY"). o2Read(pg, 14, 8, CHOOSE "------" IF gdl ELSE o2Sv(gb[1], 5, 1)).
        o2Seg(pg, 15, 3, "VGZ"). o2Read(pg, 15, 8, CHOOSE "------" IF gdl ELSE o2Sv(gb[2], 5, 1)).
        LOCAL ea IS CHOOSE o2qRes["ea"] IF post ELSE (CHOOSE o2qB["ea"] IF ro ELSE o2qAfter(o2qCentre(), d)).
        LOCAL ec IS o2qEls().
        o2Seg(pg, 13, 42, "HA"). o2Seg(pg, 13, 49, "TGT"). o2Read(pg, 13, 53, o2F(o2qKm(ea["ra"]), 5, 1)).
        o2Seg(pg, 13, 59, "CUR"). o2Read(pg, 13, 63, o2F(o2qKm(ec["ra"]), 5, 1)). o2Seg(pg, 13, 69, "km").
        o2Seg(pg, 14, 42, "HP"). o2Seg(pg, 14, 49, "TGT"). o2Read(pg, 14, 53, o2F(o2qKm(ea["rp"]), 5, 1)).
        o2Seg(pg, 14, 59, "CUR"). o2Read(pg, 14, 63, o2F(o2qKm(ec["rp"]), 5, 1)). o2Seg(pg, 14, 69, "km").
        SET o2qDvB TO o2DvBar(tot, gt).
    } ELSE { SET o2qDvB TO LIST(). }
    // row 16: the RCS trim, only after the cutoff (the last burn's VGO left at the cut, body axes, to trim by hand)
    LOCAL rct IS o2qRes:HASKEY("peg") AND o2qSeq = "".
    IF rct {
        LOCAL rb IS o2qInBody(o2qRes["peg"]["vgo"]).
        o2Seg(pg, 16, 1, "RCS    TRIM").
        o2Seg(pg, 16, 18, "X"). o2Read(pg, 16, 20, o2Sg(rb[0], 5, 2)).
        o2Seg(pg, 16, 26, "Y"). o2Read(pg, 16, 28, o2Sg(rb[1], 5, 2)).
        o2Seg(pg, 16, 34, "Z"). o2Read(pg, 16, 36, o2Sg(rb[2], 5, 2)).
    }
    // the action row: ARM and EXEC are items now, not grid buttons
    LOCAL ar IS CHOOSE 17 IF rct ELSE 16.
    o2Act(pg, "unld", ar, 0, "UNLD", ld AND NOT ro).     // left of ARM; col 0 so UNLD-ARM is a 4-column gap like the others (the page's 14 px inset holds the box)
    o2Act(pg, "arm", ar, 8, "ARM", ld AND NOT ro AND tot > 0.01).
    IF o2qArmed AND ld { LOCAL sg IS pg["seg"][pg["seg"]:LENGTH - 1]. SET sg[3] TO "S". }   // armed: the brightest class
    o2Act(pg, "exec", ar, 15, "EXEC", ld AND NOT ro AND o2qArmed).
    o2Act(pg, "brn", ar, 23, "BRN PLN").
    o2Act(pg, "tree", ar, 34, "FPLN TREE", TRUE).
    o2qMsgRow(pg, ar + 1).
    RETURN pg.
}

FUNCTION o2qOmsDim {                         // OMS's choices not available: RCS (by hand), BOTH and a failed engine
    LOCAL dm IS LIST(3).
    IF o2qOut[0] <> "" OR o2qOut[1] <> "" { dm:ADD(0). }
    IF o2qOut[0] <> "" { dm:ADD(1). }
    IF o2qOut[1] <> "" { dm:ADD(2). }
    RETURN dm.
}

FUNCTION o2qPgOrbit {
    LOCAL pg IS o2PgNew().
    o2qHead(pg, "2011/", "ORBIT / PTG", 0).
    LOCAL el IS o2qEls().
    o2Seg(pg, 2, 1, "ORBIT  HA"). o2Read(pg, 2, 12, o2F(o2qKm(el["ra"]), 5, 1)). o2Seg(pg, 2, 18, "km  HP").
    o2Read(pg, 2, 25, o2F(o2qKm(el["rp"]), 5, 1)). o2Seg(pg, 2, 31, "km  INC"). o2Read(pg, 2, 39, o2F(el["inc"], 5, 1)).
    o2Seg(pg, 2, 45, "deg").
    o2Seg(pg, 3, 8, "H"). o2Read(pg, 3, 12, o2F(SHIP:ALTITUDE / 1000, 5, 1)). o2Seg(pg, 3, 18, "km  V").
    o2Read(pg, 3, 25, o2F(SHIP:VELOCITY:ORBIT:MAG, 5, 0)). o2Seg(pg, 3, 31, "m/s").
    o2Seg(pg, 4, 8, "PER"). o2Read(pg, 4, 12, o2Ms(el["period"])).
    o2Seg(pg, 4, 22, "TTA"). o2Read(pg, 4, 26, o2Ms(ETA:APOAPSIS):PADLEFT(5)).
    o2Seg(pg, 4, 36, "TTP"). o2Read(pg, 4, 40, o2Ms(ETA:PERIAPSIS):PADLEFT(5)).
    LOCAL dp IS o2qDapOn.                    // the DAP's fields live only while it flies
    o2Seg(pg, 6, 1, "HOLD").
    o2Choice(pg, "hold", 6, LIST(LIST(8, "INRTL"), LIST(16, "LVLH"), LIST(24, "TRACK"), LIST(32, "FREE")), dp).
    // TRACK's BODY and TO are word items (their options in a drop-down list: ENT opens it); OMICRON on the same row
    o2Seg(pg, 7, 1, "TRACK  BODY").
    o2Drop(pg, "tax", 7, 13, O2Q_TAX[ROUND(o2Val["tax"])], O2Q_TAX, dp).
    o2Seg(pg, 7, 18, "TO").
    o2Drop(pg, "ttg", 7, 22, O2Q_TTG[ROUND(o2Val["ttg"])], O2Q_TTG, dp).
    o2Seg(pg, 7, 30, "OMICRON"). o2Num(pg, "tom", 7, 38, o2F(o2Val["tom"], 5, 1), dp).
    o2Seg(pg, 9, 14, "CUR       MNVR      TGT       ERR").
    LOCAL at IS o2qAtt().
    LOCAL tg IS o2qDapTgt().                 // TGT = the DAP's own target, ERR = the DAP's own error, every mode
    LOCAL nm IS LIST("ROLL", "PITCH", "YAW").
    LOCAL tid IS LIST("tr", "tp", "ty").
    LOCAL ec IS CHOOSE LIST(o2qDap["e"]:Y, o2qDap["e"]:X, o2qDap["e"]:Z) IF tg:LENGTH = 3 ELSE LIST().   // V(pitch, roll, yaw)
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        o2Seg(pg, 10 + i, 1, nm[i]).
        o2Read(pg, 10 + i, 12, o2F(at[i], 5, 1)).
        o2Num(pg, tid[i], 10 + i, 22, o2F(o2Val[tid[i]], 5, 1), dp).
        IF tg:LENGTH = 3 {
            o2Read(pg, 10 + i, 32, o2F(tg[i], 5, 1)).
            o2Read(pg, 10 + i, 42, o2F(ec[i], 6, 2)).
        } ELSE {
            o2Read(pg, 10 + i, 32, "  ---", "D").
            o2Read(pg, 10 + i, 42, "   ---", "D").
        }
    }
    o2Seg(pg, 13, 1, "RATE"). o2Read(pg, 13, 12, o2F(SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI, 5, 2)). o2Seg(pg, 13, 18, "deg/s").
    o2Seg(pg, 13, 28, "DAP").
    IF dp {
        o2Read(pg, 13, 32, O2Q_DAP_ACT[o2qDap["act"]]).
        o2Seg(pg, 13, 44, "ERR"). o2Read(pg, 13, 48, o2F(o2qDap["ea"], 5, 2)). o2Seg(pg, 13, 54, "deg").
        IF o2qDap["u"]:MAG > 0 { o2Read(pg, 13, 60, "JETS"). }
    } ELSE IF o2qSeq <> "" { o2Read(pg, 13, 32, "BURN: KOS STEERING", "Y"). }
    ELSE { o2Read(pg, 13, 32, "N/A: NO KALSCOPROC FLY-BY-WIRE", "Y"). }
    o2Seg(pg, 14, 1, "DAP").                 // the legend line that sat on row 14 is gone, the DAP row closes up under the status
    o2Choice(pg, "dmode", 14, LIST(LIST(8, "AUTO"), LIST(16, "CSS")), dp).
    o2Seg(pg, 14, 25, "DB"). o2Num(pg, "ddb", 14, 28, o2F(o2qDbShown(), 5, 2), dp). o2Seg(pg, 14, 34, "deg").
    o2Seg(pg, 14, 39, "RATE"). o2Num(pg, "drate", 14, 44, o2F(o2Val["drate"], 4, 2), dp). o2Seg(pg, 14, 49, "deg/s").
    o2Act(pg, "omnvr", 17, 8, "MNVR", dp).
    o2Act(pg, "ostop", 17, 16, "STOP", dp).
    o2Act(pg, "brn", 17, 24, "BRN PLN").
    o2qMsgRow(pg, 18).
    RETURN pg.
}

FUNCTION o2qAtt {                            // the orbiter's attitude in LVLH: LIST(roll, pitch, yaw) deg (the root
    LOCAL fr IS o2Lvlh(o2qRv(), SHIP:VELOCITY:ORBIT).   // part's axes: the nose, whatever the control point)
    LOCAL bf IS SHIP:ROOTPART:FACING.
    RETURN o2dRpy(bf:FOREVECTOR, bf:STARVECTOR, bf:TOPVECTOR, fr).
}

FUNCTION o2qDapTgt {                         // the DAP's own target as the page's ROLL / PITCH / YAW (LVLH, the root's axes
    IF NOT o2qDapOn OR o2qDap["act"] = "FREE" { RETURN LIST(). }   // = o2qAtt's frame): LIST(r, p, y), empty when it has none
    LOCAL b IS o2dBasis(o2qDap["rf"], o2qGeo()).
    LOCAL fc IS SHIP:FACING. LOCAL rf IS SHIP:ROOTPART:FACING.
    LOCAL rt IS o2dMap(o2dOut(b, o2qDap["ref"][0]), o2dOut(b, o2qDap["ref"][1]), fc:FOREVECTOR, fc:TOPVECTOR, rf:FOREVECTOR, rf:TOPVECTOR).
    RETURN o2dRpy(rt[0], VCRS(rt[1], rt[0]), rt[1], o2Lvlh(o2qRv(), SHIP:VELOCITY:ORBIT)).
}

// ---- OMS/RCS: the page that replaced OMS/MPS. lib_o2rcs.ks has the pure parts; the vessel is read here.
// The failures moved out of the page: the "!" button of the page row opens lib_failui's FAILURES window (every page).
FUNCTION o2qMono {                           // a part's MonoPropellant: LIST(amount, capacity)
    PARAMETER pt.
    FOR rs IN pt:RESOURCES { IF rs:NAME = "MonoPropellant" { RETURN LIST(rs:AMOUNT, rs:CAPACITY). } }
    RETURN LIST(0, 0).
}
FUNCTION o2qPodScan {                        // the forward and the aft fuselage parts and the state of their RCS modules (every O2Q_POD_DT s; force: now)
    PARAMETER force IS FALSE.
    IF NOT force AND TIME:SECONDS - o2qPods["t"] < O2Q_POD_DT { RETURN. }
    SET o2qPods["t"] TO TIME:SECONDS.
    LOCAL fw IS "". LOCAL af IS "".
    FOR pt IN SHIP:PARTS {
        LOCAL nm IS pt:NAME:TOLOWER.
        IF nm:CONTAINS("forwardfuselage") { SET fw TO pt. }
        ELSE IF nm:CONTAINS("aftfuselage") { SET af TO pt. }
    }
    SET o2qPods["f"] TO fw. SET o2qPods["a"] TO af.
    LOCAL rx IS LIST().
    LIST RCS IN rx.
    LOCAL cnt IS LIST(0, 0, 0, 0).           // forward modules, forward ok, aft modules, aft ok
    FOR rc IN rx {
        LOCAL ok IS rc:ENABLED AND NOT rc:FLAMEOUT.
        LOCAL u IS rc:UID.
        IF o2qIsEng(fw) AND u = fw:UID { SET cnt[0] TO cnt[0] + 1. IF ok { SET cnt[1] TO cnt[1] + 1. } }
        ELSE IF o2qIsEng(af) AND u = af:UID { SET cnt[2] TO cnt[2] + 1. IF ok { SET cnt[3] TO cnt[3] + 1. } }
    }
    SET o2qPods["m"] TO cnt.
    SET o2qPods["rcs"] TO rx.
}
// the three RCS pods F, L, R: LIST of LEXICON(has, qty %, tot jets, jets working, ok = usable). L and R share the aft tank.
FUNCTION o2qRcsRead {
    o2qPodScan().
    LOCAL fw IS o2qPods["f"]. LOCAL af IS o2qPods["a"].
    LOCAL cnt IS o2qPods["m"].
    LOCAL fm IS LIST(0, 0). LOCAL am IS LIST(0, 0).
    IF o2qIsEng(fw) { SET fm TO o2qMono(fw). }
    IF o2qIsEng(af) { SET am TO o2qMono(af). }
    LOCAL out IS LIST().
    FROM { LOCAL p IS 0. } UNTIL p > 2 STEP { SET p TO p + 1. } DO {
        LOCAL fwd IS p = 0.
        LOCAL has IS CHOOSE o2qIsEng(fw) IF fwd ELSE o2qIsEng(af).
        LOCAL mo IS CHOOSE fm IF fwd ELSE am.
        LOCAL nm IS CHOOSE cnt[0] IF fwd ELSE cnt[2].
        LOCAL nk IS CHOOSE cnt[1] IF fwd ELSE cnt[3].
        LOCAL ok IS has AND mo[0] > 0.
        LOCAL wk IS CHOOSE o2rJets(O2R_JETS[p], CHOOSE nk IF ok ELSE 0, nm) IF has ELSE 0.
        out:ADD(LEXICON("has", has, "qty", o2rPct(mo[0], mo[1]), "tot", O2R_JETS[p], "wk", wk, "ok", ok, "nm", nm, "nk", nk)).   // nm / nk = the part's RCS modules / the ones enabled
    }
    RETURN o2rDllJets(out).                  // The real jets per pod (failed manifolds and single jets out) from the DLL
}
FUNCTION o2qXferBal {                        // XFER's balance %, -1 when the tanks are not there
    o2qPodScan().
    IF NOT (o2qIsEng(o2qPods["f"]) AND o2qIsEng(o2qPods["a"])) { RETURN -1. }
    RETURN o2rBal(o2qMono(o2qPods["f"])[0], o2qMono(o2qPods["a"])[0]).
}
FUNCTION o2qEngTank {                        // the % of the OMS propellant an engine is fed from (its own consumed resources, else the ship's)
    PARAMETER en, ox.
    LOCAL a IS 0. LOCAL c IS 0. LOCAL got IS FALSE.
    IF o2qIsEng(en) { IF en:HASSUFFIX("CONSUMEDRESOURCES") {
        FOR cr IN en:CONSUMEDRESOURCES:VALUES {
            LOCAL nm IS cr:NAME:REPLACE(" ", ""):TOLOWER.
            IF (ox AND (nm = "oxidizer" OR nm = "nto")) OR ((NOT ox) AND (nm = "liquidfuel" OR nm = "mmh")) {
                SET a TO a + cr:AMOUNT. SET c TO c + cr:CAPACITY. SET got TO TRUE.
            }
        }
    } }
    IF NOT got {
        FOR rs IN SHIP:RESOURCES {
            IF (ox AND (rs:NAME = "Oxidizer" OR rs:NAME = "NTO")) OR ((NOT ox) AND (rs:NAME = "LiquidFuel" OR rs:NAME = "MMH")) {
                SET a TO a + rs:AMOUNT. SET c TO c + rs:CAPACITY.
            }
        }
    }
    RETURN o2rPct(a, c).
}
FUNCTION o2qEngRead {                        // OMS engine k: LEXICON(have, out, st, pc, cmd, thr, gp, gy, ox, fu, red)
    PARAMETER k.
    LOCAL en IS o2qOmsEng(k).
    LOCAL have IS o2qIsEng(en).
    LOCAL bad IS o2qOut[k] <> "".
    LOCAL pc IS 0. LOCAL th IS 0. LOCAL gp IS 0. LOCAL gy IS 0.
    LOCAL st IS "---".
    LOCAL ox IS 0. LOCAL fu IS 0.
    IF have {
        IF en:MAXTHRUST > 0 { SET pc TO 100 * en:THRUST / en:MAXTHRUST. }
        SET th TO en:THRUST.
        SET st TO CHOOSE "ON" IF en:IGNITION ELSE "ARM".
        IF o2qOmsOff[k] { SET st TO "OFF". }
        IF en:HASGIMBAL { SET gp TO en:GIMBAL:PITCHANGLE. SET gy TO en:GIMBAL:YAWANGLE. }
        SET ox TO o2qEngTank(en, TRUE). SET fu TO o2qEngTank(en, FALSE).
    }
    IF bad { SET st TO "FAIL". }
    LOCAL cmd IS 0.                          // the commanded Pc: the throttle of a lit burn on this engine, else 0
    IF o2qSeq = "BURN" AND o2qB:HASKEY("ek") AND o2qB:HASKEY("lit") { IF o2qB["lit"] AND o2qB["ek"]:CONTAINS(k) { SET cmd TO 100 * o2qThr. } }
    // No low-Pc red until O2R_PC_GRACE s after the lit tick (the spool-up reads under the command); an out engine is red at once
    LOCAL warm IS TRUE.
    IF o2qSeq = "BURN" AND o2qB:HASKEY("t0") { SET warm TO o2rWarm(o2qB["t0"], TIME:SECONDS). }
    RETURN LEXICON("have", have, "out", bad, "st", st, "pc", pc, "cmd", cmd, "thr", th, "gp", gp, "gy", gy, "ox", ox, "fu", fu,
        "red", o2rRed(bad, pc, CHOOSE cmd IF warm ELSE 0)).
}

FUNCTION o2qPgOms {                          // OMS/RCS: OMS L / R, RCS per pod, JET SEL, XFER, CTRL FRM, the Pc tapes and lamps
    LOCAL pg IS o2PgNew().
    o2qHead(pg, "2011/", "OMS/RCS", 0).
    o2Seg(pg, 2, 0, "OMS"). o2Seg(pg, 2, 15, "L"). o2Seg(pg, 2, 24, "R").
    o2Seg(pg, 2, 33, "RCS"). o2Seg(pg, 2, 46, "F"). o2Seg(pg, 2, 54, "L"). o2Seg(pg, 2, 62, "R").
    o2Seg(pg, 3, 1, "STATUS"). o2Seg(pg, 4, 1, "Pc %"). o2Seg(pg, 5, 1, "THRUST kN").
    o2Seg(pg, 6, 1, "GMBL"). o2Seg(pg, 6, 7, "P"). o2Seg(pg, 7, 7, "Y").
    o2Seg(pg, 8, 1, "OX %"). o2Seg(pg, 9, 1, "FU %").
    LOCAL eg IS LIST().
    LOCAL ed IS LIST(16, 25).                // the columns' right edges
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL e IS o2qEngRead(k).
        eg:ADD(e).
        LOCAL cl IS CHOOSE "R" IF e["out"] ELSE "V".
        LOCAL re IS ed[k].
        IF e["have"] OR e["out"] {
            o2Read(pg, 3, re + 1 - e["st"]:LENGTH, e["st"], CHOOSE "R" IF e["out"] ELSE (CHOOSE "S" IF e["st"] = "ON" ELSE (CHOOSE "D" IF e["st"] = "OFF" ELSE "V"))).
            o2Read(pg, 4, re - 2, o2F(e["pc"], 3, 0), cl).
            o2Read(pg, 5, re - 3, o2F(e["thr"], 4, 1), cl).
            o2Read(pg, 6, re - 3, o2rSg1(e["gp"]), cl).
            o2Read(pg, 7, re - 3, o2rSg1(e["gy"]), cl).
            o2Read(pg, 8, re - 1, o2F(e["ox"], 2, 0), cl).
            o2Read(pg, 9, re - 1, o2F(e["fu"], 2, 0), cl).
        } ELSE { o2Read(pg, 3, re - 2, "---", "D"). }
    }
    SET o2qOmsG TO eg.
    // the RCS pods F L R: QTY %, JETS working / total, FAIL, VERN
    o2Seg(pg, 3, 34, "QTY %"). o2Seg(pg, 4, 34, "JETS"). o2Seg(pg, 5, 34, "FAIL"). o2Seg(pg, 6, 34, "VERN").
    LOCAL rp IS o2qRcsRead().
    LOCAL pe IS LIST(46, 54, 62).
    LOCAL pj IS LIST(43, 51, 59).
    FROM { LOCAL p IS 0. } UNTIL p > 2 STEP { SET p TO p + 1. } DO {
        LOCAL d IS rp[p].
        IF d["has"] {
            o2Read(pg, 3, pe[p] - 1, o2F(d["qty"], 2, 0), CHOOSE "V" IF d["qty"] >= 10 ELSE "Y").
            o2Read(pg, 4, pj[p], d["wk"] + "/" + d["tot"], CHOOSE "V" IF d["wk"] = d["tot"] ELSE "Y").
            IF d["wk"] = d["tot"] { o2Read(pg, 5, pe[p], "-", "D"). }
            ELSE { o2Read(pg, 5, pe[p] - 1, o2F(d["tot"] - d["wk"], 2, 0), "R"). }
            IF NOT d["ok"] { o2Read(pg, 6, pe[p] - 2, "OFF", "R"). } ELSE IF o2qVern["on"] { o2Read(pg, 6, pe[p] - 1, "ON", "V"). } ELSE { o2Read(pg, 6, pe[p] - 2, "OFF", "D"). }
        } ELSE { o2Read(pg, 3, pe[p], "-", "D"). }
    }
    o2Seg(pg, 8, 33, "JET SEL").
    o2Choice(pg, "jsel", 8, LIST(LIST(44, "PRI"), LIST(52, "VERN")), TRUE, LIST()).
    // XFER: BAL % live, TGT % typed, GO
    o2Seg(pg, 10, 33, "XFER"). o2Seg(pg, 11, 34, "BAL%"). o2Seg(pg, 12, 34, "TGT%").
    LOCAL bal IS o2qXferBal().
    IF bal < 0 { o2Read(pg, 11, 42, "--", "D"). } ELSE { o2Read(pg, 11, 42, o2Fx(bal, 1), "V"). }
    IF NOT o2qXtgtSet AND bal >= 0 { SET o2Val["xtgt"] TO ROUND(bal, 1). SET o2qXtgtSet TO TRUE. }
    o2Num(pg, "xtgt", 12, 42, o2Fx(o2Val["xtgt"], 1), bal >= 0).
    o2Act(pg, "xgo", 13, 34, "GO", bal >= 0 AND NOT o2qXf["on"]).
    IF o2qXf["on"] { o2Seg(pg, 13, 38, CHAR(8594) + " " + (CHOOSE "FWD" IF o2qXf["tgt"] > bal ELSE "AFT") + "  CANCEL", "Y"). }
    // CTRL FRM: the control point (FWD = AG7, OMS = AG6); a click is locked while a burn runs (the burn holds OMS); a pilot press of AG6 / AG7 is followed
    o2Seg(pg, 10, 54, "CTRL FRM").
    SET o2Val["ctrl"] TO CHOOSE 1 IF o2qCtrl = "OMS" ELSE 0.   // The readout is the point in force, in a burn and after it (the burn end's own switch back to FWD was never shown)
    o2Choice(pg, "ctrl", 11, LIST(LIST(55, "FWD"), LIST(60, "OMS")), o2qSeq = "", LIST()).
    o2Act(pg, "ops3", 11, 1, "OPS3", o2qOps3 AND o2qSeq = "").   // lit once the deorbit burn is flown: runs ops3q
    // the graphics' own labels: the RCS CMD lamps (sprites) and the Pc values under the tapes
    o2Seg(pg, 14, 33, "RCS CMD"). o2Seg(pg, 15, 55, "PITCH"). o2Seg(pg, 16, 34, "ROLL"). o2Seg(pg, 17, 34, "YAW").
    o2Seg(pg, 18, 9, "Pc %").
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL e IS eg[k].
        IF e["have"] OR e["out"] { o2Read(pg, 18, ed[k] - 2, o2F(e["pc"], 3, 0), CHOOSE "R" IF e["red"] ELSE "V"). }
    }
    o2qMsgRow(pg, 19).
    RETURN pg.
}

// the page's graphics, sprite slots 0 .. 16 (page px, the canvas's geometry: ch = 8.428 px, the tapes' svg at x 14 + col ch - 8, y 216)
GLOBAL O2Q_CH IS 8.428.
FUNCTION o2qOmsGfx {                         // returns the slots used
    LOCAL eg IS o2qOmsG.
    IF eg:LENGTH < 2 { RETURN 0. }
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL e IS eg[k].
        LOCAL lx IS ROUND(14 + (14 + 9 * k) * O2Q_CH - 8).
        o2SprPut(k, o2rTapeName(e["pc"], e["red"]), lx + 20, 302).
        o2SprPut(2 + k, CHOOSE "pcp_R" IF e["red"] ELSE "pcp_G", lx + 28, 216 + o2rPtrY(e["cmd"])).
    }
    LOCAL sc IS LIST("100", "50", "0").
    LOCAL sy IS LIST(225, 303, 381).
    FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
        o2SprTxt(4 + i, "<size=11>" + sc[i] + "</size>", 123.6 - sc[i]:LENGTH * 3.3, sy[i], "#3ce03c", sc[i]:LENGTH * 7 + 6).
    }
    o2SprPut(7, "lgd_tri", 26, 315).
    o2SprPut(8, "lgd_sq", 26, 336).
    o2SprTxt(9, "<size=11>CMD Pc</size>", 56, 315, "#3ce03c", 46).
    o2SprTxt(10, "<size=11>ACT Pc</size>", 56, 336, "#3ce03c", 46).
    LOCAL u IS o2qDapU.
    LOCAL pu IS o2rLamp(u:X). LOCAL ro IS o2rLamp(u:Y). LOCAL ya IS o2rLamp(u:Z).
    LOCAL lx0 IS ROUND(14 + 40 * O2Q_CH). LOCAL lx1 IS ROUND(14 + 46.5 * O2Q_CH). LOCAL lxp IS ROUND(14 + 55 * O2Q_CH).
    o2SprPut(11, "lamp_LEFT_" + (CHOOSE 1 IF ro < 0 ELSE 0), lx0 + 25.5, 357).
    o2SprPut(12, "lamp_RIGHT_" + (CHOOSE 1 IF ro > 0 ELSE 0), lx1 + 25.5, 357).
    o2SprPut(13, "lamp_LEFT_" + (CHOOSE 1 IF ya < 0 ELSE 0), lx0 + 25.5, 378).
    o2SprPut(14, "lamp_RIGHT_" + (CHOOSE 1 IF ya > 0 ELSE 0), lx1 + 25.5, 378).
    o2SprPut(15, "lamp_UP_" + (CHOOSE 1 IF pu > 0 ELSE 0), lxp + 25.5, 357).
    o2SprPut(16, "lamp_DOWN_" + (CHOOSE 1 IF pu < 0 ELSE 0), lxp + 25.5, 378).
    RETURN 17.
}

// ---- JET SEL: PRI the primaries as they are; VERN the verniers EMULATED on them: every RCS module's thrust limited to
// O2R_VERN_PCT, the DAP's deadband and rate down to O2R_VERN_DB / O2R_VERN_RATE (the crew's smaller values stay), restored at PRI.
// The burn's own RCS (ullage, the rate null) is the primaries: SETUP puts PRI back.
FUNCTION o2qVernSet {
    PARAMETER on, say IS TRUE.
    o2qPodScan(TRUE).
    FOR rc IN o2qPods["rcs"] { SET rc:THRUSTLIMIT TO CHOOSE O2R_VERN_PCT IF on ELSE 100. }   // RCS 02 is the DLL's (a duty of the ticks), not a thrust limit here
    IF on {
        IF NOT o2qVern["on"] { SET o2qVern["db"] TO o2Val["ddb"]. SET o2qVern["rate"] TO o2Val["drate"]. }
        SET o2Val["ddb"] TO MIN(o2Val["ddb"], O2R_VERN_DB).
        SET o2Val["drate"] TO MIN(o2Val["drate"], O2R_VERN_RATE).
    } ELSE IF o2qVern["on"] {
        SET o2Val["ddb"] TO o2qVern["db"]. SET o2Val["drate"] TO o2qVern["rate"].
    }
    SET o2qVern["on"] TO on.
    SET o2Val["jsel"] TO CHOOSE 1 IF on ELSE 0.
    SET o2qDap["db"] TO o2Val["ddb"]. SET o2qDap["rate"] TO o2Val["drate"].
    o2qDapPush().
    o2qLogLine("JET SEL " + (CHOOSE "VERN: RCS THRUST LIMIT " + O2R_VERN_PCT + " %, DB " + ROUND(o2Val["ddb"], 2) + ", RATE " + ROUND(o2Val["drate"], 2) IF on ELSE "PRI: RCS THRUST LIMIT 100 %")).
    IF say { o2qSay("JET SEL " + (CHOOSE "VERN" IF on ELSE "PRI"), "V"). }
}

// ---- CTRL FRM (FWD = AG7, OMS = AG6; kOS cannot read the point in force: the last one ops2q set)
FUNCTION o2qCtrlSet {
    PARAMETER nm.
    IF nm = o2qCtrl { RETURN. }
    IF o2qSeq <> "" { SET o2Val["ctrl"] TO CHOOSE 1 IF o2qCtrl = "OMS" ELSE 0. o2qSay("CTRL FRM LOCKED IN BURN", "Y"). RETURN. }
    IF nm = "OMS" { TOGGLE AG6. } ELSE { TOGGLE AG7. }
    SET o2qAg6 TO AG6. SET o2qAg7 TO AG7.     // ops2q's own toggle is not a press
    SET o2qCtrl TO nm.
    o2qSay("CTRL FRM " + nm, "V").
    o2qLogLine("CTRL FRM " + nm).
}

// ---- XFER: the RCS propellant between the forward and the aft module (kOS TRANSFER, a chunk of O2R_XFER_RATE % of the total a second
// toward TGT %); CANCEL stops it
FUNCTION o2qXferGo {
    IF o2qXf["on"] { RETURN. }
    LOCAL bal IS o2qXferBal().
    IF bal < 0 { o2qSay("NO RCS TANKS FOUND", "Y"). RETURN. }
    IF ABS(o2Val["xtgt"] - bal) < 0.1 { o2qSay("XFER: BAL ALREADY AT TGT " + o2Fx(bal, 1), "Y"). RETURN. }
    SET o2qXf["on"] TO TRUE. SET o2qXf["tgt"] TO o2Val["xtgt"]. SET o2qXf["tr"] TO "". SET o2qXf["t"] TO -1E9.
    o2qSay("XFER " + (CHOOSE "AFT " + CHAR(8594) + " FWD" IF o2Val["xtgt"] > bal ELSE "FWD " + CHAR(8594) + " AFT") + " TO " + o2Fx(o2Val["xtgt"], 1), "V").
    o2qLogLine("XFER START BAL " + ROUND(bal, 2) + " TGT " + ROUND(o2Val["xtgt"], 2)).
}
FUNCTION o2qXferEnd {
    PARAMETER why, cls.
    IF o2qIsEng(o2qXf["tr"]) { SET o2qXf["tr"]:ACTIVE TO FALSE. }
    SET o2qXf["on"] TO FALSE. SET o2qXf["tr"] TO "".
    o2qSay(why + " BAL " + o2Fx(o2qXferBal(), 1), cls).
    o2qLogLine("XFER " + why + " BAL " + ROUND(o2qXferBal(), 2)).
}
FUNCTION o2qXferTick {
    IF NOT o2qXf["on"] { RETURN. }
    IF o2qIsEng(o2qXf["tr"]) {               // a chunk is moving: wait for it
        LOCAL tr IS o2qXf["tr"].
        IF tr:STATUS = "Transferring" { RETURN. }
        IF tr:STATUS = "Failed" { o2qXferEnd("XFER FAILED: " + tr:MESSAGE, "R"). RETURN. }
        SET o2qXf["tr"] TO "".
    }
    IF TIME:SECONDS - o2qXf["t"] < 1 { RETURN. }
    o2qPodScan().
    IF NOT (o2qIsEng(o2qPods["f"]) AND o2qIsEng(o2qPods["a"])) { o2qXferEnd("XFER STOPPED: TANKS GONE", "R"). RETURN. }
    LOCAL fm IS o2qMono(o2qPods["f"]). LOCAL am IS o2qMono(o2qPods["a"]).
    LOCAL st IS o2rXferStep(fm[0], am[0], fm[1], am[1], o2qXf["tgt"]).
    IF st = 0 { o2qXferEnd("XFER DONE", "V"). RETURN. }
    LOCAL src IS CHOOSE o2qPods["a"] IF st > 0 ELSE o2qPods["f"].
    LOCAL dst IS CHOOSE o2qPods["f"] IF st > 0 ELSE o2qPods["a"].
    LOCAL tr IS TRANSFER("MonoPropellant", src, dst, ABS(st)).
    SET tr:ACTIVE TO TRUE.
    SET o2qXf["tr"] TO tr.
    SET o2qXf["t"] TO TIME:SECONDS.
}

// ---- the FAILURES window (lib_failui.ks, on lib_fail.ks's rows). The window's MET / TIG rows, RAND and FAIL all reach the OMS
// through ONE handler (o2qFlOms, registered for "OMS 01" at the start): the target L / R / ANY is resolved to a good engine and flown by
// o2qOmsFail (in a lit burn the trigger owns the burn list: o2qOmsFailAny requests it and o2qBurnRm flies it). TIG rows are s from the
// loaded burn's TIG (in the sequence: its TIG): fuiTick / fuiSched get tig = met - the burn's TIG as MET, FL_NOTIG = no burn.
FUNCTION o2qFailTig {                        // the burn's TIG as MET, -1E9 = no burn
    IF o2qSeq <> "" AND o2qB:HASKEY("ig0") { RETURN o2qMetOf(o2qB["ig0"]). }
    IF o2qLoaded() { RETURN o2Val["tig"]. }
    RETURN -1E9.
}
FUNCTION o2qGood {                           // the engines (0 L, 1 R) that are on the ship and not out
    LOCAL good IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO { IF o2qOut[k] = "" AND o2qIsEng(o2qOmsEng(k)) { good:ADD(k). } }
    RETURN good.
}
FUNCTION o2qSimPts {                         // SimSup's decision point at a loaded burn's TIG (once per burn; only while latched)
    IF NOT fuiSimOn() OR NOT o2qLoaded() { RETURN. }
    LOCAL ut IS o2qLoad["ut"] - o2qLoad["tb"] / 2.
    LOCAL ty IS "" + o2qLoad["type"].
    LOCAL nm IS "BURN_TIG".
    IF ty:CONTAINS("DEORB") { SET nm TO "DEORBIT_TIG". }
    ELSE IF ty:CONTAINS("OMS-2") { SET nm TO "OMS2_TIG". }
    ELSE IF ty:CONTAINS("OMS-1") { SET nm TO "OMS1_TIG". }
    fuiSimPt(nm, ut, nm + ROUND(ut)).
}
FUNCTION o2qFailTigNow {                     // flTick's tig: s from the burn's ignition (the TIG rows' time base)
    LOCAL tg IS o2qFailTig().
    IF tg < -1E8 { RETURN FL_NOTIG. }
    RETURN MISSIONTIME - tg.
}
FUNCTION o2qFlOms {                          // the FAILURES window's OMS 01 handler: target L / R / ANY, why CREW / MET ROW / TIG ROW / RAND
    PARAMETER tg, vl, why.
    LOCAL k0 IS LIST("L", "R", "ANY"):INDEXOF(tg).
    LOCAL k IS o2rPickEng(k0, o2qGood(), RANDOM()).
    IF k < 0 { RETURN "REFUSE: " + (CHOOSE "NO OMS ENGINE LEFT TO FAIL" IF k0 = 2 ELSE tg + " OMS ALREADY OUT"). }
    IF why:CONTAINS("ROW") { o2qLogLine("FAILURE ROW " + why + " DUE: ENGINE " + LIST("L", "R")[k]). }
    o2qOmsFailAny(k, CHOOSE "TIMED" IF why:CONTAINS("ROW") ELSE why).
    RETURN "OK:" + LIST("L", "R")[k].
}
GLOBAL o2qXOn IS FALSE.                      // The page box shows the big X (its GPC has failed)
FUNCTION o2qGpcX {                           // the page box's X look on / off (o2qDraw's: a page change moves between the two displays)
    PARAMETER on.
    IF on = o2qXOn OR NOT o2GuiOn { RETURN. }
    SET o2qXOn TO on.
    SET o2Box:STYLE:BG TO CHOOSE (UI_PANEL_DIR + "gpc_x") IF on ELSE (O2_DIR + "page.png").
}
FUNCTION o2qFlEng {                          // lib_flfx's OMS resolver (OMS 02 / 03): engine L / R when it is on the ship and not out, else ""
    PARAMETER tg.
    LOCAL k IS LIST("L", "R"):INDEXOF(tg).
    IF k < 0 { RETURN "". }
    IF o2qOut[k] <> "" { RETURN "". }
    LOCAL en IS o2qOmsEng(k).
    IF o2qIsEng(en) { RETURN en. }
    RETURN "".
}
FUNCTION o2qFlBind {                         // lib_flfx's OMS binder: the part of engine L / R for the DLL, also once it is out (o2qOid keeps the UIDs)
    PARAMETER tg.
    LOCAL k IS LIST("L", "R"):INDEXOF(tg).
    IF k < 0 { RETURN LIST(). }
    IF o2qOid[k] = "" { RETURN LIST(). }
    RETURN LIST("" + o2qOid[k]).
}
FUNCTION o2qSwPage {                        // SW 03's page = the page on screen (o2qPage) and its display (gpcPageDisp: GNC / SM)
  RETURN gpcPageDisp(o2qPage).
}
FUNCTION o2qFailInit {                       // at the start: the handler, the window's message line, the failures of an earlier program
    flInit().
    flReg("OMS 01", o2qFlOms@).
    flfxRegOms(o2qFlEng@, o2qFlBind@).                   // OMS 02 THRUST LOW / OMS 03 GIMBAL LOCKED
    flfxRegSw("ORBIT", o2qSwPage@).          // SW 03 DISPLAY SOFTWARE (lib_flfx)
    flfxRegGuid(LIST("ORBIT BURN")).         // SW 02 GUIDANCE LOST (the burn's guidance halts, the dV count flies on)
    flfxRegAuto("O2", o2qCrewAuto@).         // SAIL's crew re-selects AUTO after RESTART SW (lib_flfx)
    flfxRegRcs().                            // RCS 01 MODULES OFF (+ its fix) / RCS 02 THRUST LOW
    flSimHost("OPS2").                      // The DLL's SimSup / RAND table for this program's codes
    gpcInit("OPS2").                         // DPS 01 / 02 (a GPC fails: its pages freeze, then the big X; GNC pages = G1, SM pages = G4)
    fuiBoot(FALSE).
    flfxReapply().                           // An earlier program's caps / locks / RCS act again
}
FUNCTION o2qFailPos {                        // the window's place: right of the ops2q window
    IF o2GuiOn { RETURN LIST(o2Gui:X + O2_W + 12 + 12, o2Gui:Y). }
    RETURN LIST(60 + 750 + 12, 20).
}
FUNCTION o2qFailBang {                       // the "!" button
    LOCAL ps IS o2qFailPos().
    fuiToggle(ps[0], ps[1]).
}

// ---- the DEORB TGT page (SITE / RWY / PASS / HAC / MODE, the plan's entry and burn, SOLVE, LOAD -> MNVR) and its globe
// (lib_o2dorb.ks: o2dbSolve = deorbit_plan.ks's executive, o2dbAfter = the page's data, o2dbGfx = the sprites). o2qDb = the last
// SOLVE (o2dbAfter's lexicon + "peg"); its "key" = the selection it was solved for: another selection shows the rows dim until SOLVE.
FUNCTION o2qDbKey {                          // the selection now, as o2dbAfter's key
    LOCAL si IS ROUND(o2Val["dsite"]).
    RETURN O2DB_SITES[si] + "|" + o2dbRwy(si, ROUND(o2Val["drwy"])) + "|" + (ROUND(o2Val["dmd"]) = 1).
}
FUNCTION o2qDbPass {                         // T1020: the PASS the page selects (1 = the nearest)
    RETURN MAX(1, MIN(O2DB_PASSES, ROUND(o2Val["dpass"]))).
}
FUNCTION o2qDbOk {                           // a solved plan for the selection on the page (T1020: and its PASS)
    RETURN o2qDb:HASKEY("ok") AND o2qDb["ok"] AND o2qDbSel().
}
FUNCTION o2qDbPegCalc {                      // the plan's impulse as PEG 4 targets LIST(HT km, THETA T deg): what MNVR EXEC shows after LOAD (o2qLoadSrc: LVLH (-dv, 0, 0) at burn_ut, TIG at its start)
    PARAMETER d.
    LOCAL ut IS d["burn_ut"].
    LOCAL st IS o2qAt(ut).
    LOCAL va IS st[1] + o2FromLvlh(0 - d["dv"], 0, 0, o2Lvlh(st[0], st[1])).
    LOCAL t4 IS o2p4FromImp(st[0], va, o2qAt(ut - o2qTb(d["dv"]) / 2)[0], o2qGv(), SHIP:BODY:RADIUS).
    RETURN LIST(t4[0] / 1000, t4[1]).
}
FUNCTION o2qDbSel {                          // TRUE when the last SOLVE was for the selection now on the page (its rows and PASS belong to it): SITE / RWY / MODE and, T1020, the PASS field
    RETURN o2qDb:HASKEY("key") AND o2qDb["key"] = o2qDbKey() AND o2qDb:HASKEY("pass") AND o2qDb["pass"] = o2qDbPass().
}
FUNCTION o2qDbNext {                         // NEXT PASS is live: the last SOLVE (a plan or a rejected pass) left the planner's next state, and the run has passes left
    IF NOT o2qDbSel() OR NOT o2qDb:HASKEY("next") OR NOT o2qDb:HASKEY("pass") { RETURN FALSE. }
    RETURN o2qDb["next"]:ISTYPE("Lexicon") AND o2qDb["pass"] < O2DB_PASSES.
}
FUNCTION o2qSink {                           // lib_o2dorb's sink (prog_display's sink mode): the planner's progress is ONE line on MSG, nothing else on the page changes
    PARAMETER kind, n.
    LOCAL st IS 0.                           // the step now being worked on (kind "pass": none yet)
    IF kind = "solve" { SET st TO 1. }
    IF kind = "step" { IF n >= 4 { RETURN. } SET st TO n + 1. }
    LOCAL s IS "SOLVING PASS " + O2DB_PASS_NOW + " ..." + (CHOOSE (" STEP " + st + "/4") IF st > 0 ELSE "").
    IF o2qLive AND o2qMsgs:LENGTH > 0 { SET o2qMsgs[0] TO LIST(s, "Y"). o2qLogLine("MSG " + s). }
    ELSE { o2qSay(s, "Y"). SET o2qLive TO TRUE. }
    SET o2qPg TO o2qBuild().
    o2qDraw().
}
FUNCTION o2qDbSolve {                        // SOLVE: the planner's executive for the page's SITE / RWY / MODE, no window (the planner's progress is the MSG line); start = the "next" of the last SOLVE (NEXT PASS), 0 = the nearest pass
    PARAMETER start IS 0.
    LOCAL si IS ROUND(o2Val["dsite"]).
    LOCAL site IS O2DB_SITES[si].
    LOCAL rw IS o2dbRwy(si, ROUND(o2Val["drwy"])).
    LOCAL co IS ROUND(o2Val["dmd"]) = 1.
    LOCAL rwRun IS rw.                       // the end the planner runs for (T1020: AUTO from a later pass = the end the preview chose for it)
    LOCAL stAbs IS 0.
    LOCAL pn IS o2qDbPass().
    IF NOT start:ISTYPE("Lexicon") AND pn > 1 {      // T1020: SOLVE from the PASS the page selects: the planner starts at the pass after the preview's pn - 1
        LOCAL pv IS o2qPvStart(site, rw, pn).
        IF pv:ISTYPE("Lexicon") { SET rwRun TO pv["rwy"]. SET stAbs TO pv["abs"]. }
        ELSE { o2qSay("NO PASS " + pn + " FOUND: SOLVE FROM PASS 1", "Y"). RETURN. }
    }
    SET O2DB_PASS_NOW TO 1.
    IF start:ISTYPE("Lexicon") { SET O2DB_PASS_NOW TO start["st"]["n"] + 1. }
    ELSE IF stAbs:ISTYPE("Lexicon") { SET O2DB_PASS_NOW TO stAbs["n"] + 1. }
    o2qSink("pass", 0).
    LOCAL res IS o2dbSolve(site, rwRun, co, start, o2qSink@, stAbs).
    IF o2qLive { IF o2qMsgs:LENGTH > 0 { o2qMsgs:REMOVE(0). } SET o2qLive TO FALSE. }
    SET o2qDb TO o2dbAfter(res, site, rw, co).
    IF o2qDb["pass"] > 0 { SET o2Val["dpass"] TO MAX(1, MIN(O2DB_PASSES, o2qDb["pass"])). }   // T1020: the PASS field follows the pass planned (a NEXT PASS)
    o2qReadSrc().
    IF o2qDb["ok"] {
        SET o2qDb["peg"] TO o2qDbPegCalc(o2qDb["d"]).
        o2qSay("PASS " + o2qDb["pass"] + " PLAN OK: " + o2qDb["d"]["runway"] + ", DV " + o2F(o2qDb["d"]["dv"], 1, 1):TRIM + " M/S", "V").
    } ELSE {
        o2qSay("NO PLAN" + (CHOOSE (" PASS " + o2qDb["pass"]) IF o2qDb["pass"] > 0 ELSE "") + ": " + (CHOOSE o2qDb["why"] IF o2qDb["why"] <> "" ELSE (CHOOSE "SEE THE PLANNER'S LOG" IF o2qDb["pass"] > 0 ELSE "SEE PLANNER LOG")), "Y").
    }
}
// the pass preview (the old selection box's table): the next pass of each runway end of the SITE, before SOLVE. Computed by
// the planner's own dpPassPreview (o2dbPreview) one cycle after the page says COMPUTING (the compute blocks the loop for a few s);
// kept per site, again when the orbit changes or its pass is gone.
// T1020: the preview holds each end's passes up to the PASS the page selects (o2dbPreview's "list", nearest first); stepping the
// PASS field (+ / - / TYPE / NEXT PASS) searches only the passes not held yet, from the last held (the planner's NEXT PASS search).
FUNCTION o2qPvKeep {                         // the site's entry when its orbit is still the one it was computed on and its first pass is still ahead (its later passes can be added to), else 0
    PARAMETER site.
    IF NOT o2qPv:HASKEY(site) { RETURN 0. }
    LOCAL e IS o2qPv[site].
    IF ABS(e["sma"] - SHIP:ORBIT:SEMIMAJORAXIS) > 2000 { RETURN 0. }              // a burn changed the orbit
    IF NOT e["ok"] { RETURN 0. }
    FOR rw IN e["rows"] { IF rw["list"]:LENGTH > 0 AND rw["list"][0]["passUT"] - TIME:SECONDS < 0 { RETURN 0. } }   // its first pass has gone by: the numbering moves
    RETURN e.
}
FUNCTION o2qPvFresh {
    PARAMETER site, n IS 1.
    IF NOT o2qPv:HASKEY(site) { RETURN FALSE. }
    LOCAL e IS o2qPv[site].
    IF ABS(e["sma"] - SHIP:ORBIT:SEMIMAJORAXIS) > 2000 { RETURN FALSE. }          // a burn changed the orbit
    IF NOT e["ok"] { RETURN TIME:SECONDS - e["t0"] < 30. }
    IF NOT o2qPvKeep(site):ISTYPE("Lexicon") { RETURN FALSE. }
    FOR rw IN e["rows"] { IF rw["list"]:LENGTH < n AND NOT rw["end"] { RETURN FALSE. } }   // a later pass than it holds
    RETURN TRUE.
}
FUNCTION o2qPvTick {
    IF o2qPage <> "DEORB" OR o2qSeq <> "" OR o2qDbOk() { RETURN. }
    LOCAL site IS O2DB_SITES[ROUND(o2Val["dsite"])].
    LOCAL n IS o2qDbPass().
    IF o2qPvFresh(site, n) { SET o2qPvPend TO "". RETURN. }
    LOCAL key IS site + "|" + n.
    IF o2qPvPend <> key { SET o2qPvPend TO key. RETURN. }
    SET o2qPvPend TO "".
    SET o2qPv[site] TO o2dbPreview(site, n, o2qPvKeep(site)).
}
FUNCTION o2qPvAuto {                         // AUTO's end for pass n: the one with the lower predicted HAC turn ("" = none has that pass)
    PARAMETER e, n.
    LOCAL best IS 1000.
    LOCAL end IS "".
    FOR rw IN e["rows"] { IF rw["list"]:LENGTH >= n { IF rw["list"][n - 1]["turn"] < best { SET best TO rw["list"][n - 1]["turn"]. SET end TO rw["rwy"]. } } }
    RETURN end.
}
FUNCTION o2qPvStart {                        // SOLVE from pass n > 1: LEXICON("rwy" the end to plan, "abs" the pass before it as o2dbSolve's startAbs) from the preview (searched now when it does not hold the pass yet), 0 = no such pass
    PARAMETER site, rwy, n.
    IF NOT o2qPvFresh(site, n) { SET o2qPv[site] TO o2dbPreview(site, n, o2qPvKeep(site)). }
    LOCAL e IS o2qPv[site].
    IF NOT e["ok"] { RETURN 0. }
    LOCAL end IS rwy.
    IF rwy = "auto" { SET end TO o2qPvAuto(e, n). }
    FOR rw IN e["rows"] {
        IF rw["rwy"] = end AND rw["list"]:LENGTH >= n {
            LOCAL pp IS rw["list"][n - 2].
            RETURN LEXICON("rwy", end, "abs", LEXICON("revUT", pp["revUT"], "passUT", pp["passUT"], "n", n - 1)).
        }
    }
    RETURN 0.
}
FUNCTION o2qPvHm {                           // s -> h:mm
    PARAMETER secs.
    LOCAL m IS ROUND(MAX(0, secs) / 60).
    RETURN FLOOR(m / 60) + ":" + (CHOOSE "0" IF MOD(m, 60) < 10 ELSE "") + MOD(m, 60).
}
FUNCTION o2qPvRows {                         // rows 8-11 of the page not yet solved for the selection (the canvas's DeorbPrev)
    PARAMETER pg, site.
    o2Seg(pg, 8, 1, "PREVIEW"). o2Seg(pg, 8, 9, "RWY"). o2Seg(pg, 8, 16, "IN"). o2Seg(pg, 8, 22, "HAC"). o2Seg(pg, 8, 28, "XRNG").
    LOCAL n IS o2qDbPass().
    IF NOT o2qPvFresh(site, n) { o2Seg(pg, 9, 9, "COMPUTING " + (CHOOSE ("PASS " + n) IF n > 1 ELSE "THE NEXT PASS") + " ...", "D"). RETURN. }
    LOCAL e IS o2qPv[site].
    IF NOT e["ok"] { o2Seg(pg, 9, 9, e["why"], "Y"). RETURN. }
    LOCAL k IS 0.
    FOR rw IN e["rows"] {                    // T1020: the rows are the selected PASS's (the nearest when PASS 1)
        IF k < 2 {
            o2Read(pg, 9 + k, 9, rw["rwy"]).
            IF rw["list"]:LENGTH >= n {
                LOCAL pe IS rw["list"][n - 1].
                o2Read(pg, 9 + k, 16, o2qPvHm(pe["passUT"] - TIME:SECONDS):PADLEFT(4)).
                o2Read(pg, 9 + k, 22, o2F(pe["turn"], 3, 0), CHOOSE "Y" IF pe["turn"] >= e["warn"] ELSE "V").
                o2Read(pg, 9 + k, 28, o2F(ABS(pe["xr"]), 3, 0)). o2Seg(pg, 9 + k, 32, "km").
            } ELSE { o2Read(pg, 9 + k, 16, "NO PASS FOUND", "Y"). }
        }
        SET k TO k + 1.
    }
    LOCAL au IS o2qPvAuto(e, n).
    IF au <> "" { o2Seg(pg, 11, 9, "AUTO: RWY"). o2Read(pg, 11, 19, au:SUBSTRING(au:LENGTH - 2, 2)). }
}
GLOBAL o2qGlCs IS 0.                         // the globe in C# (KAL/S O2GLB): 0 not tried yet, 1 C# draws it, -1 kOS
FUNCTION o2qGlbCs {                          // TRUE when KalsCoproc drew the globe: o2dbItems's sprites and texts, the path as ONE image (coproc/Od.cs Glb)
    PARAMETER si, g.
    IF o2qGlCs = 0 {
        SET o2qGlCs TO -1.
        IF o2Cs = 1 { IF ADDONS:KALS:HASSUFFIX("O2GLB") {   // o2Cs = 1: KalsCoproc is there (o2CsDraw ran first)
            LOCAL su IS ADDONS:KALS:O2GSETUP(LEXICON("spr", o2Spr, "wh", O2_SPR_WH, "dir", O2_DIR)).
            IF su = "" { SET o2qGlCs TO 1. } ELSE { kmSay("OPS2: KALSCOPROC'S GLOBE NOT SET UP (" + su + "); KOS DRAWS IT", "C"). }
        } }
    }
    IF o2qGlCs < 0 { RETURN FALSE. }
    LOCAL pts IS LIST().
    IF g:HASKEY("pts") { SET pts TO g["pts"]. }
    LOCAL hi IS ADDONS:KALS:O2GLB(o2dbItems(si, g, FALSE), pts, LEXICON("hi", o2SprHi, "cx", O2DB_CX, "cy", O2DB_CY)).
    IF hi < 0 {
        SET o2qGlCs TO -1. SET o2SprHi TO o2Spr:LENGTH.   // any slot may be on: kOS's o2SprFrom looks at all of them
        kmSay("OPS2: KALSCOPROC'S GLOBE FAILED (" + ADDONS:KALS:O2GERROR + "); KOS DRAWS IT", "C").
        RETURN FALSE.
    }
    SET o2SprHi TO hi.
    RETURN TRUE.
}
FUNCTION o2qDbDraw {                         // the DEORB page's sprites: C# when it can, else kOS (the path as dots)
    LOCAL si IS ROUND(o2Val["dsite"]).
    LOCAL g IS LEXICON().
    IF o2qDbOk() { SET g TO o2qDb["g"]. }
    IF o2qGlbCs(si, g) { RETURN. }
    o2SprFrom(o2dbGfx(0, si, g)).
}
FUNCTION o2qPgDeorb {
    LOCAL pg IS o2PgNew().
    LOCAL ok IS o2qDbOk().
    LOCAL d IS LEXICON().
    LOCAL g IS LEXICON().
    LOCAL peg IS LIST().
    IF ok {
        SET d TO o2qDb["d"]. SET g TO o2qDb["g"].
        IF o2qDb:HASKEY("peg") { SET peg TO o2qDb["peg"]. }
    }
    LOCAL si IS ROUND(o2Val["dsite"]).
    LOCAL tig IS 0.
    IF ok { SET tig TO d["burn_ut"] - o2qTb(d["dv"]) / 2. }
    LOCAL dm IS "  ---".
    o2qHead(pg, "2022/", "DEORB TGT", tig).
    o2Seg(pg, 2, 1, "FPLN STATE"). o2Read(pg, 2, 13, "0"). o2Read(pg, 2, 18, "CURRENT").
    o2Seg(pg, 3, 1, "SITE").
    o2Drop(pg, "dsite", 3, 8, O2DB_SITE_W[si], O2DB_SITE_W).
    LOCAL ends IS O2DB_ENDS[O2DB_SITES[si]].
    o2Seg(pg, 4, 1, "RWY").
    o2Choice(pg, "drwy", 4, LIST(LIST(8, "AUTO"), LIST(14, ends[0]), LIST(21, ends[1]))).
    IF ok { o2Seg(pg, 4, 29, "PLAN"). o2Read(pg, 4, 34, d["runway"]). }
    o2Seg(pg, 5, 1, "PASS").
    IF o2Spec:HASKEY("dpass") { SET o2Spec["dpass"]["max"] TO O2DB_PASSES. }   // the planner's DP_REV_MAX_TRIES once it is loaded
    o2Num(pg, "dpass", 5, 8, "" + o2qDbPass()).                // T1020: the PASS to plan / preview: a field (+ / - / TYPE), the plan's own pass once solved
    o2Seg(pg, 5, 10, "of"). o2Read(pg, 5, 13, "" + O2DB_PASSES).
    o2Act(pg, "dnext", 5, 20, "NEXT PASS", o2qDbNext() OR (NOT o2qDbSel() AND o2qDbPass() < O2DB_PASSES)).   // after a SOLVE: the planner's DP_START hook (deorbit_plan.ks); before one: the preview's next pass
    o2Seg(pg, 6, 1, "HAC").
    IF NOT ok { o2Read(pg, 6, 8, "--", "D"). }               // not solved: the canvas's "HAC --"
    ELSE { o2Seg(pg, 6, 8, "OVHD"). }
    IF ok {
        LOCAL tn IS o2qDb["turn"].
        o2Read(pg, 6, 13, o2F(tn, 3, 0)). o2Seg(pg, 6, 17, "deg").
        IF tn >= o2qDb["warn"] { o2Read(pg, 6, 22, "TURN HIGH", "Y"). } ELSE { o2Read(pg, 6, 22, "TURN OK"). }
    }
    o2Seg(pg, 7, 1, "MODE").
    o2Choice(pg, "dmd", 7, LIST(LIST(8, "FULL"), LIST(14, "COARSE"))).
    IF NOT ok {                              // not solved for this selection: the pass preview (the canvas's DeorbPrev), the rest empty
        o2qPvRows(pg, O2DB_SITES[si]).
        o2Act(pg, "drun", 18, 8, "SOLVE").
        o2Act(pg, "dsave", 18, 18, "SAVE " + CHAR(8594) + " FPLN", FALSE).
        LOCAL hs IS FALSE.
        FOR sr IN o2qSrc { IF sr["file"] = "0:/deorbit_plan.txt" { SET hs TO TRUE. } }
        o2Act(pg, "dload", 18, 31, "LOAD " + CHAR(8594) + " MNVR", hs).
        o2Act(pg, "dclr", 18, 46, "CLEAR", o2qDbClrOn()).
        o2qMsgRow(pg, 19).
        RETURN pg.
    }
    o2Seg(pg, 8, 1, "ENTRY"). o2Seg(pg, 8, 8, "FPA").
    o2Seg(pg, 9, 8, "RANGE"). o2Seg(pg, 10, 8, "XRNG").
    IF ok {
        o2Read(pg, 8, 16, o2F(d["fpa"], 6, 2)).
        o2Read(pg, 9, 16, o2F(g["range"], 6, 0)).
        o2Read(pg, 10, 13, o2F(ABS(d["cross_km"]), 3, 0)).
    } ELSE { o2Read(pg, 8, 16, dm, "D"). o2Read(pg, 9, 16, dm, "D"). o2Read(pg, 10, 13, "---", "D"). }
    o2Seg(pg, 8, 23, "deg"). o2Seg(pg, 9, 23, "km").
    o2Seg(pg, 10, 17, "MAX"). o2Seg(pg, 10, 25, "km").
    IF ok { o2Read(pg, 10, 21, o2F(o2qDb["xr"], 3, 0)). } ELSE { o2Read(pg, 10, 21, "---", "D"). }
    o2Seg(pg, 11, 1, "PEG 4"). o2Seg(pg, 11, 8, "HT"). o2Seg(pg, 12, 8, "THETA T").
    IF peg:LENGTH > 0 {
        o2Read(pg, 11, 16, o2F(peg[0], 6, 1)).
        o2Read(pg, 12, 16, o2F(peg[1], 6, 1)).
    } ELSE { o2Read(pg, 11, 16, dm, "D"). o2Read(pg, 12, 16, dm, "D"). }
    o2Seg(pg, 11, 23, "km"). o2Seg(pg, 12, 23, "deg").
    o2Seg(pg, 13, 1, "BURN"). o2Seg(pg, 13, 8, "TIG").
    o2Seg(pg, 14, 8, "DV"). o2Seg(pg, 14, 17, "m/s"). o2Seg(pg, 14, 22, "TBRN").
    o2Seg(pg, 15, 8, "WT"). o2Seg(pg, 15, 17, "kg").
    IF ok {
        o2Read(pg, 13, 12, o2Met(o2qMetOf(tig))).
        o2Read(pg, 14, 11, o2F(d["dv"], 5, 1)).
        o2Read(pg, 14, 27, o2Ms(o2qTb(d["dv"])):PADLEFT(5)).
        o2Read(pg, 15, 11, o2F(SHIP:MASS * 1000, 5, 0)).
    } ELSE {
        o2Read(pg, 13, 12, "---/--:--:--", "D"). o2Read(pg, 14, 11, " ----", "D"). o2Read(pg, 14, 27, "  ---", "D"). o2Read(pg, 15, 11, "-----", "D").
    }
    o2Seg(pg, 16, 1, "MISS"). o2Seg(pg, 16, 12, "km"). o2Seg(pg, 16, 18, "TOL"). o2Seg(pg, 16, 24, "km").
    IF ok {
        o2Read(pg, 16, 8, o2F(ABS(d["residual_km"]), 3, 1)).
        o2Read(pg, 16, 22, o2F(o2qDb["tol"], 1, 0)).
    } ELSE { o2Read(pg, 16, 8, "---", "D"). o2Read(pg, 16, 22, "-", "D"). }
    LOCAL has IS FALSE.
    FOR sr IN o2qSrc { IF sr["file"] = "0:/deorbit_plan.txt" { SET has TO TRUE. } }
    o2Act(pg, "drun", 18, 8, "SOLVE").
    o2Act(pg, "dsave", 18, 18, "SAVE " + CHAR(8594) + " FPLN", TRUE).
    o2Act(pg, "dload", 18, 31, "LOAD " + CHAR(8594) + " MNVR", has).
    o2Act(pg, "dclr", 18, 46, "CLEAR", o2qDbClrOn()).
    o2qMsgRow(pg, 19).
    RETURN pg.
}

FUNCTION o2qPgBrn {
    o2qBrnDef().
    LOCAL pg IS o2PgNew().
    LOCAL ok IS o2qBrn["ok"].
    o2qHead(pg, "2023/", "BRN PLN", CHOOSE o2qBrn["ut"] IF ok ELSE 0).
    o2qFpState(pg).                          // FPLN STATE is a cursor field (+ / - step the tree depth-first, ENT opens FPLN)
    o2Seg(pg, 3, 1, "TYPE").
    o2Choice(pg, "btype", 3, LIST(LIST(8, "CIRC"), LIST(15, "HA"), LIST(19, "HP"), LIST(23, "PLANE"), LIST(30, "DV"))).
    o2Seg(pg, 4, 1, "WHEN").
    o2Choice(pg, "bwhen", 4, LIST(LIST(8, "APO"), LIST(14, "PERI"), LIST(20, "AN"), LIST(24, "DN"), LIST(28, "TIME"), LIST(34, "T+"))).
    LOCAL ty IS ROUND(o2Val["btype"]).
    LOCAL wh IS ROUND(o2Val["bwhen"]).
    o2Seg(pg, 5, 1, "TIG").
    IF wh = 4 { o2Num(pg, "btig", 5, 8, o2Met(o2Val["btig"])). }
    ELSE IF wh = 5 { o2Seg(pg, 5, 8, "T+"). o2Num(pg, "bdt", 5, 11, o2Ms(o2Val["bdt"])). }
    ELSE { o2Read(pg, 5, 8, o2Met(o2qMetOf(o2qBrnUt())), CHOOSE "V" IF ok ELSE "D"). }
    IF o2flState > 0 {                       // BRN+ right of TIG: the time from the last burn's end to this one's start
        LOCAL gp IS o2qBrnGap().
        o2Seg(pg, 5, 26, "BRN+").
        IF gp < 0 { o2Read(pg, 5, 31, "-" + o2Met(-gp), "Y"). }   // this burn would start before the last one ends
        ELSE { o2Read(pg, 5, 31, o2Met(gp), CHOOSE "V" IF ok ELSE "D"). }
    }
    o2Seg(pg, 7, 1, "TGT    HA"). o2Seg(pg, 7, 26, "HP").
    IF ty = 1 { o2Num(pg, "bha", 7, 12, o2F(o2Val["bha"], 5, 1)). } ELSE { o2Read(pg, 7, 12, "  ---", "D"). }
    IF ty = 2 { o2Num(pg, "bhp", 7, 31, o2F(o2Val["bhp"], 5, 1)). } ELSE { o2Read(pg, 7, 31, "  ---", "D"). }
    o2Seg(pg, 7, 18, "km"). o2Seg(pg, 7, 37, "km").
    o2Seg(pg, 8, 8, "INC", CHOOSE "L" IF ty = 3 ELSE "D").
    IF ty = 3 { o2Num(pg, "binc", 8, 13, o2F(o2Val["binc"], 6, 2)). } ELSE { o2Read(pg, 8, 13, "  ----", "D"). }
    o2Seg(pg, 8, 20, "deg", CHOOSE "L" IF ty = 3 ELSE "D").
    o2Seg(pg, 10, 1, "BURN   DVX"). o2Seg(pg, 10, 19, "DVY"). o2Seg(pg, 10, 30, "DVZ"). o2Seg(pg, 10, 41, "m/s").
    LOCAL ids IS LIST("bdx", "bdy", "bdz").
    LOCAL cols IS LIST(12, 23, 34).
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        IF ty = 4 { o2Num(pg, ids[i], 10, cols[i], o2Sg(o2Val[ids[i]], 6, 1)). }
        ELSE IF ok { o2Read(pg, 10, cols[i], o2Sg(o2qBrn["dv"][i], 6, 1)). }
        ELSE { o2Read(pg, 10, cols[i], "  ----", "D"). }
    }
    IF ok {
        LOCAL d IS o2qBrn["dv"].
        LOCAL tot IS SQRT(d[0] ^ 2 + d[1] ^ 2 + d[2] ^ 2).
        o2Seg(pg, 11, 8, "TOT"). o2Read(pg, 11, 12, o2F(tot, 5, 1)).
        o2Seg(pg, 11, 19, "TBRN"). o2Read(pg, 11, 24, o2Ms(o2qTb(tot)):PADLEFT(5)).   // a planned length
        o2Seg(pg, 11, 30, "WT"). o2Read(pg, 11, 34, o2F(SHIP:MASS * 1000, 5, 0)). o2Seg(pg, 11, 40, "kg").
        LOCAL ha IS CHOOSE o2qBrn["nra"] IF o2qBrn["nb"] ELSE o2qBrn["el"]["ra"].    // the n-body solve's measure: the max / min radius over its next period
        LOCAL hp IS CHOOSE o2qBrn["nrp"] IF o2qBrn["nb"] ELSE o2qBrn["el"]["rp"].
        o2Seg(pg, 12, 1, "AFTER  HA"). o2Read(pg, 12, 12, o2F(o2qKm(ha), 5, 1)). o2Seg(pg, 12, 18, "km").
        o2Seg(pg, 12, 26, "HP"). o2Read(pg, 12, 31, o2F(o2qKm(hp), 5, 1)). o2Seg(pg, 12, 37, "km").
        o2Seg(pg, 13, 8, "INC"). o2Read(pg, 13, 11, o2F(o2qBrn["el"]["inc"], 6, 2)). o2Seg(pg, 13, 18, "deg").   // the post-burn inclination
        IF o2qNbOn { o2Seg(pg, 13, 26, "N-BODY ...", "Y"). }                   // which solve the numbers are
        ELSE IF o2qBrn["nb"] { o2Seg(pg, 13, 26, "N-BODY", "V"). }
        ELSE { o2Seg(pg, 13, 26, "KEPLER", "D"). }
    }
    o2Act(pg, "bsolve", 15, 8, "SOLVE").
    o2Act(pg, "bsave", 15, 17, "SAVE " + CHAR(8594) + " FPLN", ok).
    o2Act(pg, "bload", 15, 33, "LOAD " + CHAR(8594) + " MNVR", ok AND o2flState = 0).   // a burn cannot be flown from a future state
    o2qMsgRow(pg, 16).
    RETURN pg.
}

FUNCTION o2qBrnUt {                          // BRN PLN's burn point (UT) by WHEN on the current conic
    LOCAL wh IS ROUND(o2Val["bwhen"]).
    IF wh = 4 { RETURN o2qUtOf(o2Val["btig"]). }
    IF wh = 5 { RETURN o2qBEp() + o2Val["bdt"]. }
    LOCAL el IS o2qBEls().                   // the conic of FPLN STATE (the live one at 0), from its epoch
    LOCAL w IS LIST("APO", "PERI", "AN", "DN")[wh].
    LOCAL dt IS o2DtTA(el, el["ta"], o2TAof(el, w)).
    IF dt < 120 { SET dt TO dt + el["period"]. }   // too close: the next one
    RETURN o2qBEp() + dt.
}

FUNCTION o2qBrnEd {                          // the TIG UT of a TIME / T+ value being TYPEd once its buffer parses (and is in range), else 0
    IF NOT o2Typ OR (o2Cur <> "btig" AND o2Cur <> "bdt") { RETURN 0. }
    LOCAL px IS o2TypeParse("T", o2Buf).
    IF NOT px[0] { RETURN 0. }
    LOCAL sp IS o2Spec[o2Cur].
    IF px[1] < sp["min"] OR px[1] > sp["max"] { RETURN 0. }
    RETURN CHOOSE o2qUtOf(px[1]) IF o2Cur = "btig" ELSE TIME:SECONDS + px[1].
}

FUNCTION o2qBrnTick {                        // the UT of the view's TIG tick on BRN PLN, 0 = none. Drawn from the WHEN field at every draw
    LOCAL ut IS o2qBrnEd().                  // (TIME: the typed time; T+: now + T+, so it slides with time; APO / PERI / AN / DN: the next one), before and
    IF ut = 0 {                              // without a solve; the buffer while a TYPE edit is open; a solve's own UT wins once solved (the field is
        IF o2qBrn["ok"] { SET ut TO o2qBrn["ut"]. }   // unchanged since: any change re-solves). Nothing when it is past or unset.
        ELSE IF o2qBEls()["n"] > 0 { SET ut TO o2qBrnUt(). }
    }
    RETURN CHOOSE ut IF ut > TIME:SECONDS ELSE 0.
}

FUNCTION o2qBrnDef {                         // the targets the pilot has not changed are the orbit's current values (SOLVE with nothing typed = no burn)
    LOCAL el IS o2qBEls().                   // the FPLN STATE's orbit
    IF el["n"] <= 0 { RETURN. }
    IF NOT o2qBrnTyped:CONTAINS("bha") { SET o2Val["bha"] TO o2Clamp(o2qKm(el["ra"]), 0, 5000). }
    IF NOT o2qBrnTyped:CONTAINS("bhp") { SET o2Val["bhp"] TO o2Clamp(o2qKm(el["rp"]), 0, 5000). }
    IF NOT o2qBrnTyped:CONTAINS("binc") { SET o2Val["binc"] TO o2Clamp(el["inc"], 0, 180). }
}

FUNCTION o2qBrnSolve {                       // the KEPLER solve of the burn at the point (every change); it drops a running n-body solve and its result
    SET o2qNbOn TO FALSE.
    SET o2qBrn TO LEXICON("ok", FALSE).
    o2qBrnDef().
    LOCAL el0 IS o2qBEls().                  // planned from FPLN STATE's conic (the live one at 0)
    IF el0["n"] <= 0 { o2qSay("NOT IN ORBIT", "Y"). RETURN. }
    LOCAL ut IS o2qBrnUt().
    IF ut < o2qBEp() + 60 { o2qSay("TIG TOO CLOSE", "Y"). RETURN. }
    LOCAL st IS o2qBAt(ut).
    LOCAL rv IS st[0]. LOCAL vv IS st[1].
    LOCAL ty IS ROUND(o2Val["btype"]).
    LOCAL dv IS V(0, 0, 0).
    LOCAL nodv IS FALSE.                     // HA / HP / PLANE with the target where the orbit already is: nothing to do, for the n-body solve too
    LOCAL fr IS o2Lvlh(rv, vv).
    IF ty = 0 { SET dv TO o2Circ(rv, vv, o2qMu()). }
    ELSE IF ty = 1 OR ty = 2 {
        LOCAL rt IS SHIP:BODY:RADIUS + 1000 * (CHOOSE o2Val["bha"] IF ty = 1 ELSE o2Val["bhp"]).
        IF ABS(rt - (CHOOSE el0["ra"] IF ty = 1 ELSE el0["rp"])) < 5 { SET nodv TO TRUE. }   // the target is the orbit's current apsis (5 m): no burn (a bisection at an apsis is a coin toss)
        ELSE {
            LOCAL rs IS o2Apsis(rv, vv, o2qMu(), o2qNorth(), CHOOSE "HA" IF ty = 1 ELSE "HP", rt).
            IF NOT rs[0] { o2qSay("TARGET NOT REACHABLE FROM THIS POINT", "Y"). RETURN. }
            SET dv TO rs[1].
        }
    }
    ELSE IF ty = 3 {
        LOCAL wh IS ROUND(o2Val["bwhen"]).
        IF wh <> 2 AND wh <> 3 { o2qSay("PLANE: WHEN AN OR DN", "Y"). RETURN. }
        IF ABS(o2Val["binc"] - el0["inc"]) >= 0.001 { SET dv TO o2Plane(rv, vv, o2qNorth(), o2Val["binc"]). }   // the current inclination: no burn
        ELSE { SET nodv TO TRUE. }
    }
    ELSE { SET dv TO o2FromLvlh(o2Val["bdx"], o2Val["bdy"], o2Val["bdz"], fr). }
    LOCAL dl IS o2ToLvlh(dv, fr).
    LOCAL ea IS o2Els(rv, vv + dv, o2qMu(), o2qNorth(), o2qEqx()).
    SET o2qBrn TO LEXICON("ok", TRUE, "ut", ut, "dv", dl, "el", ea, "type", ty, "nb", FALSE, "nodv", nodv).
    LOCAL tn IS LIST("CIRC", "HA", "HP", "PLANE", "DV")[ty].
    LOCAL wn IS LIST("APO", "PERI", "AN", "DN", "TIME", "T+")[ROUND(o2Val["bwhen"])].
    o2qSay("PLAN OK: " + tn + " AT " + wn, "V").
}

// ---- the N-BODY solve (the SOLVE item; the automatic re-solve above stays Kepler). ADDONS:KALS:NBSOLVE (coproc/PrNb.cs) flies the real coast
// (the body's point mass + J2 + the Moon / Sun, RK4) on its own thread from the state the plan starts from to the burn point (re-found on that coast for
// WHEN APO / PERI / AN / DN), solves the burn's target on it, and the page takes the result when the thread is done; a change of any input (the Kepler
// re-solve) drops it. An older KalsCoproc without NBSOLVE keeps the Kepler solve.
FUNCTION o2qL3 { PARAMETER x. RETURN LIST(x:X, x:Y, x:Z). }
FUNCTION o2qNbStart {
    SET o2qNbOn TO FALSE.
    IF NOT o2qBrn["ok"] { RETURN. }
    IF NOT o2qFbwHas("NBSOLVE") { o2qSay("N-BODY NEEDS KALSCOPROC: KEPLER", "Y"). RETURN. }
    LOCAL ep IS o2qBEp().
    LOCAL st IS o2qBAt(ep).                  // the state the plan starts from: the live one now, or FPLN STATE's burn's state after it
    LOCAL ty IS o2qBrn["type"].
    LOCAL rt IS 0.
    IF ty = 1 { SET rt TO SHIP:BODY:RADIUS + 1000 * o2Val["bha"]. }
    ELSE IF ty = 2 { SET rt TO SHIP:BODY:RADIUS + 1000 * o2Val["bhp"]. }
    LOCAL np IS o2qNorth().
    SET o2qNbH TO ADDONS:KALS:NBSOLVE(LEXICON("mu", o2qMu(), "j2", O2Q_J2, "rj2", O2Q_RJ2, "pole", o2qL3(np), "t0", ep, "r", o2qL3(st[0]), "v", o2qL3(st[1]),
        "ut", o2qBrn["ut"], "type", ty, "when", ROUND(o2Val["bwhen"]), "rt", rt, "inc", o2Val["binc"],
        "dvl", LIST(o2Val["bdx"], o2Val["bdy"], o2Val["bdz"]), "lh", O2_LH, "nodv", o2qBrn["nodv"])).
    SET o2qNbOn TO TRUE.
    o2qSay("N-BODY SOLVING ...", "V").
}
FUNCTION o2qNbPoll {                         // the main loop's step: the running n-body solve done -> its burn replaces the Kepler one
    IF NOT o2qNbOn { RETURN. }
    IF NOT o2qNbH:DONE { RETURN. }
    SET o2qNbOn TO FALSE.
    IF NOT o2qBrn["ok"] { RETURN. }
    IF o2qNbH:ERROR <> "" { o2qSay("N-BODY: " + o2qNbH:ERROR:TOUPPER, "Y"). RETURN. }
    LOCAL rs IS o2qNbH:RESULT.
    LOCAL rv IS V(rs["r"][0], rs["r"][1], rs["r"][2]).
    LOCAL vv IS V(rs["v"][0], rs["v"][1], rs["v"][2]).
    LOCAL dw IS V(rs["dv"][0], rs["dv"][1], rs["dv"][2]).
    LOCAL dl IS o2ToLvlh(dw, o2Lvlh(rv, vv)).
    LOCAL ea IS o2Els(rv, vv + dw, o2qMu(), o2qNorth(), o2qEqx()).
    SET ea["cra"] TO rs["ra"]. SET ea["crp"] TO rs["rp"].   // The view's PLAN caption shows the n-body apsides the AFTER line shows
    LOCAL kd IS o2qBrn["dv"].
    LOCAL kut IS o2qBrn["ut"].
    SET o2qBrn TO LEXICON("ok", TRUE, "ut", rs["ut"], "dv", dl, "el", ea, "type", o2qBrn["type"], "nb", TRUE, "nodv", o2qBrn["nodv"],
        "nra", rs["ra"], "nrp", rs["rp"], "kdv", kd, "kut", kut).
    LOCAL tot IS SQRT(dl[0] ^ 2 + dl[1] ^ 2 + dl[2] ^ 2).
    LOCAL kt IS SQRT(kd[0] ^ 2 + kd[1] ^ 2 + kd[2] ^ 2).
    o2qSay("N-BODY OK: DV " + ROUND(tot, 1) + " M/S, TIG " + (CHOOSE "+" IF rs["ut"] >= kut ELSE "-") + ROUND(ABS(rs["ut"] - kut)) + " S", "V").
}

// ---- the orbit view (ORBIT / PTG and BRN PLN): the current orbit solid, a planned one dashed yellow
GLOBAL o2qVwCs IS 0.                         // the view in C# (KAL/S O2VIEW): 0 not tried yet, 1 C# draws it, -1 kOS
FUNCTION o2qViewCs {                         // TRUE when KalsCoproc drew the view (o2qView's whole body, the same writes)
    PARAMETER el, pl, dt.
    IF o2qVwCs = 0 {
        SET o2qVwCs TO -1.
        IF o2Cs = 1 { IF ADDONS:KALS:HASSUFFIX("O2VIEW") {   // o2Cs = 1: KalsCoproc is there (o2CsDraw ran first)
            LOCAL su IS ADDONS:KALS:O2VSETUP(LEXICON("spr", o2Spr, "wh", O2_SPR_WH, "dir", O2_DIR, "cx", O2Q_VIEW_CX,
                "cy", O2Q_VIEW_CY, "r", O2Q_VIEW_R, "n", O2Q_VIEW_N, "epx", O2Q_EARTH_PX, "altx", O2_VIEW_ALT_X)).
            IF su = "" { SET o2qVwCs TO 1. } ELSE { kmSay("OPS2: KALSCOPROC'S ORBIT VIEW NOT SET UP (" + su + "); KOS DRAWS IT", "C"). }
        } }
    }
    IF o2qVwCs < 0 { RETURN FALSE. }
    LOCAL hi IS ADDONS:KALS:O2VIEW(el, pl, LEXICON("rb", SHIP:BODY:RADIUS, "dt", dt, "hi", o2SprHi, "t", TIME:SECONDS, "bg", o2qBug())).   // the clock for the re-latch spacing; the bug's offset
    IF hi < 0 {
        SET o2qVwCs TO -1. SET o2SprHi TO o2Spr:LENGTH.   // any slot may be on: kOS's o2SprFrom looks at all of them
        kmSay("OPS2: KALSCOPROC'S ORBIT VIEW FAILED (" + ADDONS:KALS:O2VERROR + "); KOS DRAWS IT", "C").
        RETURN FALSE.
    }
    SET o2SprHi TO hi.
    RETURN TRUE.
}

FUNCTION o2qLoadedConic {                    // the conic after the loaded burn, EMPTY when none is loaded (or after the burn: o2qLoad is cleared at the cutoff)
    IF NOT o2qLoaded() { SET o2qLcKey TO "". SET o2qLc TO LEXICON(). RETURN o2qLc. }
    IF o2qSeq <> "" AND o2qB:HASKEY("ea") { RETURN o2qB["ea"]. }          // the sequence's own (made at its start)
    LOCAL d IS o2qDv().
    LOCAL key IS ROUND(o2Val["tig"], 0) + "/" + ROUND(d[0], 1) + "/" + ROUND(d[1], 1) + "/" + ROUND(d[2], 1).   // MET, not UT: the offset jitters in warp
    IF key <> o2qLcKey { SET o2qLcKey TO key. SET o2qLc TO o2qAfter(o2qCentre(), d). }
    RETURN o2qLc.
}

FUNCTION o2qView {
    PARAMETER pl.                            // the planned conic, or an empty LEXICON
    LOCAL el IS CHOOSE o2qBEls() IF o2qPage = "BRN" ELSE o2qEls().   // BRN PLN's solid orbit is FPLN STATE's
    LOCAL sh IS o2qVwSh().                   // (its clock starts at that conic's epoch)
    LOCAL tu IS 0.                           // the burn's UT (the TIG tick), 0 = none
    IF o2qPage = "BRN" { SET tu TO o2qBrnTick(). }
    ELSE IF o2qPage = "ORBIT" AND o2qLoaded() { SET tu TO o2qCentre(). }
    IF o2qViewCs(el, pl, tu - TIME:SECONDS - sh) { RETURN. }
    LOCAL rb IS SHIP:BODY:RADIUS.
    IF TIME:SECONDS - o2qVw["t"] >= O2Q_VIEW_PATH_DT OR o2qVw["t"] > TIME:SECONDS OR o2qVw["pg"] <> o2qPage
        OR NOT (o2qVw["pl"] = pl OR (pl:LENGTH = 0 AND o2qVw["pl"]:LENGTH = 0)) {   // the lines, the scale,
                                             // the Earth: once a second, and at once on a new page or plan
        LOCAL els IS LIST(el).
        IF pl:LENGTH > 0 { els:ADD(pl). }
        LOCAL sc0 IS o2ViewScale(els, rb, O2Q_VIEW_R).
        LOCAL re0 IS ROUND(MIN(O2Q_EARTH_PX, rb * sc0)).
        SET sc0 TO re0 / rb.                     // the Earth's whole px sets the scale
        SET o2qVw TO LEXICON("t", TIME:SECONDS, "pg", o2qPage, "pl", pl, "sc", sc0, "re", re0,
            "p", o2ViewPath(el, rb, sc0, O2Q_VIEW_N), "q", CHOOSE o2ViewPath(pl, rb, sc0, O2Q_VIEW_N, el) IF pl:LENGTH > 0 ELSE LIST()).
    }
    LOCAL sc IS o2qVw["sc"].
    LOCAL re IS o2qVw["re"].
    LOCAL cx IS O2Q_VIEW_CX. LOCAL cy IS O2Q_VIEW_CY.
    LOCAL k IS 0.
    o2SprPut(k, "earth_" + MAX(30, MIN(80, re)), cx, cy). SET k TO k + 1.
    FOR p IN o2qVw["p"] { o2SprPut(k, "dot_g", cx + p[0], cy + p[1]). SET k TO k + 1. }
    LOCAL mk IS CHOOSE pl IF pl:LENGTH > 0 ELSE el.
    IF pl:LENGTH > 0 {
        LOCAL i IS 0.
        FOR p IN o2qVw["q"] {
            IF MOD(i, 3) <> 2 { o2SprPut(k, "dot_y", cx + p[0], cy + p[1]). SET k TO k + 1. }
            SET i TO i + 1.
        }
    }
    // A / P (the planned orbit's when there is one), AN / DN, the burn point, the orbiter
    IF mk["e"] > 0.0005 {
        LOCAL pa IS o2ViewXY(el, o2AtTA(mk, 180)[0], rb, sc).
        LOCAL pp IS o2ViewXY(el, o2AtTA(mk, 0)[0], rb, sc).
        o2SprPut(k, "dia", cx + pa[0], cy + pa[1]). SET k TO k + 1.
        o2SprPut(k, "dia", cx + pp[0], cy + pp[1]). SET k TO k + 1.
        o2SprTxt(k, "A", cx + pa[0] * 1.13, cy + pa[1] * 1.13, "#c4ffc4", 30). SET k TO k + 1.
        o2SprTxt(k, "P", cx + pp[0] * 1.13, cy + pp[1] * 1.13, "#c4ffc4", 30). SET k TO k + 1.
    }
    LOCAL pn IS o2ViewTA(el, o2TAof(el, "AN"), rb, sc).
    LOCAL pd IS o2ViewTA(el, o2TAof(el, "DN"), rb, sc).
    o2SprPut(k, "node", cx + pn[0], cy + pn[1]). SET k TO k + 1.
    o2SprPut(k, "node", cx + pd[0], cy + pd[1]). SET k TO k + 1.
    o2SprTxt(k, "AN", cx + pn[0] - 18, cy + pn[1], "#c4ffc4", 30). SET k TO k + 1.
    o2SprTxt(k, "DN", cx + pd[0] + 18, cy + pd[1], "#c4ffc4", 30). SET k TO k + 1.
    IF tu > TIME:SECONDS {
        LOCAL pt IS o2ViewTA(el, o2TAafter(el, el["ta"], tu - TIME:SECONDS - sh), rb, sc).
        o2SprPut(k, "tick", cx + pt[0], cy + pt[1]). SET k TO k + 1.
        o2SprTxt(k, "TIG", cx + pt[0] * 1.18, cy + pt[1] * 1.18, "#c4ffc4", 40). SET k TO k + 1.
    }
    LOCAL bg IS o2qBug().                    // FPLN STATE not 0: the bug is where that burn ENDS (the live vehicle at 0)
    LOCAL po IS o2ViewTA(el, CHOOSE o2TAafter(el, el["ta"], bg) IF bg > 0 AND el["n"] > 0 ELSE el["ta"], rb, sc).
    o2SprPut(k, "tri", cx + po[0], cy + po[1]). SET k TO k + 1.
    LOCAL cap IS "A <color=#a6f8a6>" + o2F(o2qKm(el["ra"]), 5, 1) + "</color>   P <color=#a6f8a6>"
        + o2F(o2qKm(el["rp"]), 5, 1) + "</color> km".
    IF pl:LENGTH > 0 {
        SET cap TO "NOW  " + cap.
        o2SprTxt(k, "<color=#f0d840>PLAN</color> A <color=#a6f8a6>" + o2F(o2qKm(CHOOSE pl["cra"] IF pl:HASKEY("cra") ELSE pl["ra"]), 5, 1)   // cra / crp = BRN PLN's n-body AFTER apsides, one measure on both
            + "</color>  P <color=#a6f8a6>" + o2F(o2qKm(CHOOSE pl["crp"] IF pl:HASKEY("crp") ELSE pl["rp"]), 5, 1) + "</color> km", cx, o2ViewCapY(cy, O2Q_VIEW_R, 1), "#3ce03c", 270).   // under the view's reach (was 50 + 290)
        SET k TO k + 1.
    }
    o2SprTxt(k, cap, cx, o2ViewCapY(cy, O2Q_VIEW_R, 0), "#3ce03c", 270). SET k TO k + 1.   // was 50 + 274, inside the TIG / A labels' reach
    o2SprFrom(k).
}

// ---- input
FUNCTION o2qPress {                          // one press of the window (o2DispTake's tags)
    PARAMETER tg.
    IF tg:STARTSWITH("N") {
        LOCAL i IS tg:SUBSTRING(1, tg:LENGTH - 1):TONUMBER(0).
        o2qLogLine("PRESS " + tg + " (page " + o2qPage + ", display " + gpcDisp(gpcPageDisp(o2qPage)) + ", seq " + (CHOOSE o2qSeq IF o2qSeq <> "" ELSE "-") + ")").   // Every page-button press that reaches the program is in the log
        IF i = O2_NAV:LENGTH { o2qFailBang(). RETURN. }    // the "!" button (after the 5 page buttons)
        o2qGo(CHOOSE "ATO" IF i = 1 AND o2qAtoShown() ELSE LIST("MNVR", "DEORB", "ORBIT", "OMS", "PDRS")[i]).   // the ATO / AOA page is DEORB's slot from the hand-off
        RETURN.
    }
    LOCAL i IS tg:SUBSTRING(1, tg:LENGTH - 1):TONUMBER(0).
    LOCAL key IS o2CellKey(CHOOSE "TYPE" IF o2Typ ELSE "PAGE", i).
    o2qKey(key).
}

FUNCTION o2qGo {                             // to a page (TYPE and a drop-down list close)
    PARAMETER p.
    SET o2Typ TO FALSE.
    SET o2DdOn TO FALSE.
    o2qDdHelpOff().
    IF p <> o2qPage {
        IF p = "PDRS" AND NOT o2qPdrsOpen() { o2qLogLine("PAGE PDRS REFUSED (see the MSG line above)"). RETURN. }   // the arm comes up with the page, goes with it
        IF o2qPage = "PDRS" AND o2aAutoOn() {   // An AUTO runs on off the page (it ends on its own, or PDRS + STOP ends it)
            o2aCamOff().
        }
        ELSE IF o2qPage = "PDRS" { o2qPdrsClose("PDRS LEFT"). }
        SET o2qPage TO p. o2qLogLine("PAGE " + p).
    }
}

// The stick is
// ONE reader's. The pilot's choice (o2qIn) is kept; o2qInEff is what the page acts on, PAGE while a lock holds, and the INPUT RHC button is greyed.
FUNCTION o2qInLock {                         // who holds the stick: "" = nobody (INPUT RHC may be picked)
    IF O2A_ON AND DEFINED ARM_UI { IF ARM_UI["aug"]:PRESSED { RETURN "MAN AUG". } }
    IF PX_ORB { RETURN "STICK ORB". }
    IF PX_ON AND PX_CSS { RETURN "CSS". }    // plain STKP holds no lock (INPUT RHC stays selectable); STKP CSS does
    IF o2qDap["mode"] = "CSS" { RETURN "CSS DAP". }
    RETURN "".
}
FUNCTION o2qInEff { RETURN CHOOSE "PAGE" IF o2qInLock() <> "" ELSE o2qIn. }
FUNCTION o2qInSet {                          // the ONLY place the input changes: the pilot's INPUT PAGE / INPUT RHC press
    PARAMETER m.
    IF m = o2qIn { RETURN. }
    SET o2qIn TO m.
    IF EXISTS(O2Q_IN_FILE) { DELETEPATH(O2Q_IN_FILE). }
    IF m <> "PAGE" { LOG m TO O2Q_IN_FILE. }
    o2qLogLine("INPUT " + m).
}
FUNCTION o2qInInit {                         // at RUN: the input the pilot set before (1:/o2q_in.txt), kept across a re-RUN
    IF EXISTS(O2Q_IN_FILE) {
        IF OPEN(O2Q_IN_FILE):READALL:STRING:TRIM = "RHC" { SET o2qIn TO "RHC". }
    }
}

FUNCTION o2qKey {                            // a key from any input
    PARAMETER key.
    IF key = "" { RETURN. }
    IF key = "INPAGE" { o2qInSet("PAGE"). RETURN. }
    IF key = "INRHC" {
        LOCAL lw IS o2qInLock().
        IF lw <> "" { o2qSay("INPUT RHC OFF: " + lw + " HAS THE STICK", "Y"). RETURN. }
        o2qInSet("RHC"). RETURN.
    }
    IF key = "CUT" { IF o2qPage = "MNVR" { o2qCut(). } ELSE IF o2qPage = "PDRS" { o2aCam(). } RETURN. }   // PDRS: the pad's cell 15 is EE CAM
    IF key = "STOP" { IF o2qPage = "PDRS" { o2aStop(). } RETURN. }                                          // ...and cell 16 STOP
    IF o2qPage = "FPLN" AND NOT o2Typ AND NOT o2DdOn AND LIST("UP", "DN", "LF", "RT"):CONTAINS(key) { IF o2gMove(key) { RETURN. } }   // the tree's cursor rules
    IF o2qPage = "BRN" AND NOT o2Typ AND NOT o2DdOn AND o2Cur = "fstate" AND (key = "PL" OR key = "MI") { o2qFpStep(CHOOSE 1 IF key = "PL" ELSE -1). RETURN. }
    // OMS/RCS, LEFT from PRI (JET SEL's first option) or from TGT % goes to OPS3 (its row is 11,
    // so the same-row walk never reaches it from these two); every other cursor move is o2Move's
    IF o2qPage = "OMS" AND key = "LF" AND NOT o2Typ AND NOT o2DdOn AND o2Find(o2qPg, "ops3"):LENGTH > 0 AND NOT o2NoCur(o2Find(o2qPg, "ops3")) {
        LOCAL jOpt IS CHOOSE o2Opt IF o2Opt >= 0 ELSE ROUND(o2Val["jsel"]).
        IF (o2Cur = "jsel" AND jOpt = 0) OR o2Cur = "xtgt" {
            SET o2Cur TO "ops3". SET o2OptFor TO o2Cur. SET o2Opt TO -1.
            RETURN.
        }
    }
    LOCAL wasTyp IS o2Typ.
    LOCAL rk IS o2Key(o2qPg, key).
    o2qDdHelpOff().
    IF rk = "CAN" AND NOT wasTyp AND o2qXf["on"] { o2qXferEnd("XFER CANCELLED", "Y"). }   // CANCEL stops XFER; a list that closed takes its help line from the MSG rows
    IF rk:STARTSWITH("ACT:") { o2qAct(rk:SUBSTRING(4, rk:LENGTH - 4)). }
    ELSE IF rk:STARTSWITH("SET:") { o2qSetVal(rk:SUBSTRING(4, rk:LENGTH - 4)). }
    ELSE IF rk:STARTSWITH("DD:") { o2qDdSay(rk:SUBSTRING(3, rk:LENGTH - 3), TRUE). }
    ELSE IF rk:STARTSWITH("DDX:") { o2qDdSay(rk:SUBSTRING(4, rk:LENGTH - 4), FALSE). }
}

FUNCTION o2qDdHelpOff {
    IF o2DdOn OR o2qDdHelp = "" { RETURN. }
    FROM { LOCAL i IS o2qMsgs:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO { IF o2qMsgs[i][0] = o2qDdHelp { o2qMsgs:REMOVE(i). } }
    SET o2qDdHelp TO "".
}

FUNCTION o2qDdSay {                          // the MSG row while a drop-down list is open / after it closed with no change
    PARAMETER id, opened.
    LOCAL f IS o2Find(o2qPg, id).
    IF f:LENGTH = 0 { RETURN. }
    // The open list's help line and the "KEPT" line are deleted: nothing is said here now (o2qDdHelp stays "")
}

FUNCTION o2qSetVal {                         // a value changed
    PARAMETER id.
    o2qLogLine("SET " + id + " " + o2Val[id]).
    IF o2aSet(id) { RETURN. }                // PDRS's values
    IF id = "src" { o2qLoadSrc(ROUND(o2Val["src"])). RETURN. }
    IF id = "apick" {                            // ATO / AOA / AUTO: the burn that follows re-planned (before OMS-1 it is the same OMS-1)
        o2qAtoApply().
   // AUTO still names the one that flies
        RETURN.
    }
    IF id = "dsite" { SET o2Val["drwy"] TO 0. SET o2Val["dpass"] TO 1. o2qSay("SITE " + O2DB_SITE_W[ROUND(o2Val["dsite"])] + ": SOLVE", "V"). RETURN. }   // a new site plans AUTO, from the nearest pass
    IF id = "drwy" OR id = "dmd" { SET o2Val["dpass"] TO 1. }      // T1020: another RWY / MODE: the nearest pass again
    IF id = "dpass" {                        // T1020: the PASS field (+ / - / TYPE): whole, within 1 .. O2DB_PASSES; the preview follows (the solved plan shows again when its own pass is back)
        SET o2Val["dpass"] TO o2qDbPass().
        IF NOT o2qDbOk() { o2qSay("PASS " + o2Val["dpass"] + ": SOLVE", "V"). }
        RETURN.
    }
    IF id = "tig" OR id = "dvx" OR id = "dvy" OR id = "dvz" { SET o2qArmed TO FALSE. }
    IF id = "guid" {
        SET o2qArmed TO FALSE.
        SET o2qP4 TO LEXICON().
        IF o2qGuidWas = 2 AND ROUND(o2Val["guid"]) <> 2 { o2qP8Dv0(). }   // PEG 8 left: the planned dV back
        SET o2qP8 TO LEXICON().
        SET o2qGuidWas TO ROUND(o2Val["guid"]).
        IF o2qPeg4() AND o2qLoaded() {
            IF ABS(o2Val["dvy"]) > 0.05 {        // PEG 4 flies in the plane (FSSR LTVCON's target projected onto it)
                SET o2Val["guid"] TO 1.
                o2qSay("PEG 4 ONLY IN PLANE: DVY NEEDS PEG 7", "Y").
                RETURN.
            }
            IF NOT o2qImpReach(o2qCentre(), o2qDv()) {   // only a burn that reaches the entry interface
                SET o2Val["guid"] TO 1.
                o2qSay(O2Q_P4_ONLY, "Y").
                RETURN.
            }
            o2qP4From(o2qCentre(), o2qDv(), o2qUtOf(o2Val["tig"])).
        }
        o2qSay("GUID " + LIST("PEG 4", "PEG 7", "PEG 8")[ROUND(o2Val["guid"])], "V").
    }
    IF id = "c1" OR id = "c2" OR id = "ht" OR id = "tht" { SET o2qArmed TO FALSE. SET o2qP4 TO LEXICON(). }
    IF LIST("bha", "bhp", "binc", "bdx", "bdy", "bdz"):CONTAINS(id) AND NOT o2qBrnTyped:CONTAINS(id) { o2qBrnTyped:ADD(id). }   // a typed target keeps its value
    IF id:STARTSWITH("b") { o2qBrnSolve(). }   // a BRN PLN input (WHEN, TIME / T+, a target, a DV; a TYPE edit's ENT, + / -, a list's pick): SOLVE again at once, the Kepler
                                             // solve (the n-body solve is the SOLVE button's; this drops a running one and its result)
    IF id = "hold" OR ((id = "tax" OR id = "ttg" OR id = "tom") AND o2qDap["hold"] = "TRACK") { o2qDapHold(O2Q_HOLDS[ROUND(o2Val["hold"])]). }
    IF id = "hold" AND O2A_ON AND NOT ARM_HOLD_EXT { o2aHoldSet(o2qPdrsHold()). }   // The arm's hold follows ORBIT / PTG's (the DAP stands by, nothing pushed)
    IF id = "dmode" {
        LOCAL md IS LIST("AUTO", "CSS")[ROUND(o2Val["dmode"])].
        LOCAL fc IS SHIP:FACING.
        LOCAL hb IS o2qDap["hold"].
        IF md = "AUTO" AND flfxSwLost("SW 01", "ORBIT") {     // SW 01 AUTO DAP LOST: AUTO refused, CSS stays
            o2qSay("AUTO DAP LOST: CSS ONLY", "V").
            SET o2Val["dmode"] TO 1.
            SET md TO "CSS".
            SET o2qSwForced TO TRUE.
        }
        o2dMode(o2qDap, md, fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()).
        IF o2qDap["hold"] <> hb {            // CSS and TRACK never both: TRACK became LVLH where CSS leaves it
            SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(o2qDap["hold"]).
        } ELSE { o2qSay("DAP " + md, "V"). }
        o2qDapPush().
    }
    IF id = "ddb" { SET o2qDap["db"] TO o2Val["ddb"]. o2qDapPush(). }
    IF id = "drate" { SET o2qDap["rate"] TO o2Val["drate"]. o2qDapPush(). }
    IF id = "jsel" { o2qVernSet(ROUND(o2Val["jsel"]) = 1). }
    IF id = "ctrl" { o2qCtrlSet(LIST("FWD", "OMS")[ROUND(o2Val["ctrl"])]). }
}

// ---- The MNVR to the burn attitude against the lead EXEC has (EXEC at TIG-65 left too little time for a 179.5 deg turn: ALIGN FAILED at TIG)
FUNCTION o2qTurnNeed {                       // LIST(s the burn MNVR needs from now, the turn in deg, the model's s): the aim built as SETUP2 builds it, on the planned dV (PEG 4 / 8's VGO is within a few deg of it); no state is written
    LOCAL ig IS o2qUtOf(o2Val["tig"]).
    LOCAL ct IS ig + o2qTb(o2qDvTot()) / 2.
    LOCAL pg IS o2pNew(o2qDv(), o2qFrameAt(ct)).
    LOCAL fc IS SHIP:FACING.
    LOCAL ba IS o2dTvAtt(fc:FOREVECTOR, fc:TOPVECTOR, o2qLineAx(o2qOms()), o2pDir(pg), o2qDnTig(), o2Val["tvr"]).   // The roll from the vertical at the ignition
    LOCAL qv IS o2dRotV(fc:FOREVECTOR, fc:TOPVECTOR, ba[0]:NORMALIZED, ba[1]).
    LOCAL dg IS qv:MAG / O2D_D2R.
    LOCAL tm IS dg / MAX(o2Val["drate"], O2Q_BURN_RATE_MIN).
    RETURN LIST(tm * O2Q_TURN_K + O2Q_TURN_PAD, dg, tm).
}
FUNCTION o2qMnvrWarn {                       // at ARM: the crew sees the MNVR time before EXEC (a TIG over O2Q_ALIGN_LEAD away needs none: the sequence warps first)
    LOCAL left IS o2qUtOf(o2Val["tig"]) - TIME:SECONDS.
    IF left <= 0 OR left >= O2Q_ALIGN_LEAD { RETURN. }
    LOCAL tn IS o2qTurnNeed().
    o2qLogLine("MNVR TO BURN ATT: " + ROUND(tn[1], 1) + " DEG, " + ROUND(tn[2], 1) + " S AT THE BURN RATE, NEEDS " + ROUND(tn[0], 1) + " S, TIG IN " + ROUND(left, 1) + " S").
    IF left < MAX(O2Q_MIN_LEAD, tn[0]) { o2qSay("TIG TOO CLOSE: MNVR " + ROUND(tn[1]) + " DEG NEEDS " + ROUND(tn[0]) + " S", "Y"). }
    ELSE { o2qSay("MNVR " + ROUND(tn[1]) + " DEG, ~ " + ROUND(tn[2]) + " S", "V"). }
}

FUNCTION o2qArm {                            // the ARM item (was the grid's ARM button): arms / disarms the loaded burn
    IF o2qSeq <> "" { o2qSay("BURN SEQUENCE RUNNING", "Y"). RETURN. }
    IF NOT o2qLoaded() { o2qSay("NO BURN LOADED", "Y"). RETURN. }
    SET o2qArmed TO NOT o2qArmed.
    IF o2qArmed { o2qSay("ARMED", "V"). o2qMnvrWarn(). }   // the input stays where the pilot set it (ARM no longer sets PAGE)
    ELSE { o2qSay("DISARMED", "V"). }
}

FUNCTION o2qUnld {                           // the UNLD item: the loaded burn leaves MNVR EXEC (it stays in the plan file / FPLN: reload it
    IF o2qSeq <> "" { o2qSay("BURN SEQUENCE RUNNING", "Y"). RETURN. }   // from the BURN list), armed or not (disarmed with it); the page is as before any load
    IF NOT o2qLoaded() { o2qSay("NO BURN LOADED", "Y"). RETURN. }
    LOCAL nm IS o2qLoad["src"].
    SET o2qLoad TO LEXICON().
    SET o2qArmed TO FALSE.
    SET o2qP4 TO LEXICON().
    SET o2qP8 TO LEXICON().
    SET o2qRes TO LEXICON().
    SET o2Val["dvx"] TO 0. SET o2Val["dvy"] TO 0. SET o2Val["dvz"] TO 0.
    o2qSay(nm + " UNLOADED", "V").
}

FUNCTION o2qAct {                            // an action pressed (ENT)
    PARAMETER id.
    o2qLogLine("ACT " + id).
    IF o2aAct(id) { RETURN. }                // PDRS's items
    IF o2qFpAct(id) { RETURN. }              // the FPLN page's items, FPLN STATE, FPLN TREE
    IF id = "bsave" { o2qFpSave(). RETURN. }
    IF id = "arm" { o2qArm(). RETURN. }
    IF id = "unld" { o2qUnld(). RETURN. }
    IF id = "exec" { o2qExec(). RETURN. }
    IF id = "brn" { o2qGo("BRN"). RETURN. }
    IF id = "xgo" { o2qXferGo(). RETURN. }
    IF id = "omnvr" OR id = "ostop" OR id = "mnvr" { o2qDapAct(id). RETURN. }
    IF id = "bsolve" { o2qBrnSolve(). o2qNbStart(). RETURN. }     // the Kepler solve at once, then the n-body one on its thread
    IF (id = "bload" OR id = "dload" OR id = "drun" OR id = "dclr") AND o2qSeq <> "" { o2qSay("NOT WHILE A BURN SEQUENCE RUNS", "Y"). RETURN. }
    IF id = "bload" {
        IF NOT o2qBrn["ok"] { RETURN. }
        LOCAL tn IS LIST("CIRC", "HA", "HP", "PLANE", "DV")[o2qBrn["type"]].
        LOCAL nid IS o2qFpSave().            // LOAD also saves (as a child of state 0) and its path becomes the active path
        o2qMnvrSet("BRN PLN " + tn, "", "BRN PLN", o2qBrn["ut"], o2qBrn["dv"], tn, nid, o2qBrn["nb"]).
        IF nid >= 0 { o2flSetPath(nid). }
        o2qGo("MNVR").
        o2qSay("BRN PLN LOADED", "V").
        RETURN.
    }
    IF id = "dload" {
        FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH STEP { SET i TO i + 1. } DO {
            IF o2qSrc[i]["file"] = "0:/deorbit_plan.txt" { o2qLoadSrc(i). o2qGo("MNVR"). }
        }
        RETURN.
    }
    IF id = "asolve" {                            // both columns again (a blocking solve), the burn the pick flies kept in MNVR EXEC
        IF o2qAtoLocked() { o2qSay("SELECTION LOCKED", "Y"). RETURN. }
        o2qSay("SOLVING ATO / AOA ...", "V").
        o2qAtoSolve().
        o2qAtoApply().
        o2qSay(o2qAtoSum(), "V").
        RETURN.
    }
    IF id = "aload" {                             // the pick's burn into MNVR EXEC, then the page
        IF o2qAtoLocked() { o2qSay("SELECTION LOCKED", "Y"). RETURN. }
        SET o2qAto["planned"] TO "".
        o2qAtoApply().
        o2qGo("MNVR").
        RETURN.
    }
    IF id = "ops3" { o2qOps3Go(). RETURN. }
    IF id = "drun" { o2qDbSolve(). RETURN. }      // deorbit_plan.ks's executive for the page's SITE / RWY / MODE (lib_o2dorb o2dbSolve)
    IF id = "dnext" {
        IF o2qDbNext() { o2qDbSolve(o2qDb["next"]). }
        ELSE IF NOT o2qDbSel() AND o2qDbPass() < O2DB_PASSES { SET o2Val["dpass"] TO o2qDbPass() + 1. o2qSay("PASS " + o2Val["dpass"] + ": SOLVE", "V"). }   // T1020: before a SOLVE, the preview's next pass
        ELSE { o2qSay("NO LATER PASS", "Y"). }
        RETURN.
    }
    IF id = "dsave" { o2qDbSave(). RETURN. }
    IF id = "dclr" { o2qDbClear(). RETURN. }
}

// ---- the burn: EXEC starts the sequence, the main loop steps it (o2qSeqTick), a trigger flies the burn
FUNCTION o2qExec {                           // EXEC: the armed burn's sequence
    IF o2qSeq = "SETTLE" {                    // The crew overrides the attitude hold
        IF o2qB["held"] AND NOT o2qB["lit"] {
            SET o2qB["ovr"] TO TRUE.
            SET o2qB["ig"] TO TIME:SECONDS.
            o2qSay("EXEC: ATT ERR HOLD OVERRIDDEN", "Y").
            o2qLogLine("EXEC HELD overridden by the crew after " + ROUND(TIME:SECONDS - o2qB["heldt"], 1) + " s").
            RETURN.
        }
    }
    IF o2qSeq <> "" { o2qSay("BURN SEQUENCE RUNNING", "Y"). RETURN. }
    IF NOT o2qArmed { o2qSay("NOT ARMED", "Y"). RETURN. }
    IF o2qDvTot() < 0.05 { o2qSay("NO DV TO BURN", "Y"). RETURN. }
    IF o2qPeg4() { IF o2qP4:LENGTH = 0 OR o2qP4["nosol"] { o2qSay("PEG 4: NO SOLUTION", "Y"). RETURN. } }
    LOCAL ig IS o2qUtOf(o2Val["tig"]).
    IF ig < TIME:SECONDS + O2Q_MIN_LEAD { o2qSay("TIG TOO CLOSE: NEEDS " + O2Q_MIN_LEAD + " S AHEAD", "Y"). RETURN. }
    IF ig < TIME:SECONDS + O2Q_ALIGN_LEAD {  // The MNVR to the burn attitude needs its time too (a sequence with a TIG over O2Q_ALIGN_LEAD away warps first)
        LOCAL tn IS o2qTurnNeed().
        IF ig < TIME:SECONDS + tn[0] {
            o2qSay("TIG TOO CLOSE: MNVR " + ROUND(tn[1]) + " DEG NEEDS " + ROUND(tn[0]) + " S", "Y").
            o2qLogLine("EXEC REFUSED: the MNVR to the burn attitude is " + ROUND(tn[1], 1) + " deg, " + ROUND(tn[2], 1) + " s at the burn rate, needs " + ROUND(tn[0], 1) + " s; TIG is " + ROUND(ig - TIME:SECONDS, 1) + " s ahead").
            RETURN.
        }
    }
    IF o2qOms():LENGTH = 0 {
        IF o2qOmsAll():LENGTH > 0 { o2qSay("BOTH OMS OUT: NO BURN", "R"). }
        ELSE { o2qSay("NO OMS ENGINE FOUND", "Y"). }
        RETURN.
    }
    IF PX_ON { pxOff("BURN EXEC"). }          // No station-keeping in a burn
    IF NOT O2Q_KOS_STEER {                   // The burn flies on our DAP
        IF O2A_ON { o2qPdrsClose("BURN EXEC"). }   // the arm's hold stands down, the DAP (if it was on) flies again
        IF NOT o2qDapOn { o2qSay("NO DAP: NO BURN", "R"). RETURN. }
    }
    SET o2qArmed TO FALSE.
    o2qSeqStart(ig).
}

FUNCTION o2qCut {                            // CUT OFF: ends the burn; before TIG, stops the sequence
    IF o2qSeq = "" { o2qSay("NO BURN IN PROGRESS", "Y"). RETURN. }
    IF o2qSeq = "BURN" OR (o2qSeq = "SETTLE" AND o2qB["lit"]) { SET o2qB["cutreq"] TO TRUE. RETURN. }
    o2qSeqStop().
    o2qSay("SEQUENCE STOPPED BEFORE TIG", "Y").
}

FUNCTION o2qPhase {
    PARAMETER p, msg.
    SET o2qSeq TO p.
    SET o2qSeqT TO TIME:SECONDS.
    o2qLogLine("SEQ " + p + " (TIG" + o2Cd(o2qB["ig"] - TIME:SECONDS) + ")").
    IF msg <> "" { o2qSay(msg, "V"). }
}

// ---- LOG ONLY: where the aim and the vessel are, in the raw frame AND in the DAP's INRTL basis, at the warp's start / end and
// at the DLL's pack / unpack lines, with what moved since the last snapshot: tells whether the AIM (o2qBrF re-converted through today's
// INRTL basis: SOLARPRIMEVECTOR + BODY:ANGULARVEL now) or the VESSEL moved during the second warp's ~170 s (the deorbit's 1.2-1.3 deg warp-exit error).
GLOBAL o2qT732P IS LEXICON().
FUNCTION o2qT732V {
    PARAMETER vq.
    RETURN "(" + ROUND(vq:X, 4) + "," + ROUND(vq:Y, 4) + "," + ROUND(vq:Z, 4) + ")".
}
FUNCTION o2qT732Ang {                        // VANG rounded, -1 for a zero vector (no exception in the burn's script)
    PARAMETER va, vb.
    IF va:MAG < 1E-9 OR vb:MAG < 1E-9 { RETURN -1. }
    RETURN ROUND(VANG(va, vb), 3).
}
FUNCTION o2qT732Snap {
    PARAMETER tag.
    LOCAL ut IS TIME:SECONDS.
    LOCAL fv IS SHIP:FACING:FOREVECTOR.
    LOCAL g IS o2qGeo().
    LOCAL bI IS o2dBasis("INRTL", g).
    LOCAL bD IS o2dBasis(o2qDap["rf"], g).
    LOCAL dr IS o2dOut(bD, o2qDap["ref"][0]).             // the fore the DAP holds now, raw, from its stored components and today's basis
    LOCAL sp IS SOLARPRIMEVECTOR.
    LOCAL bw IS SHIP:BODY:ANGULARVEL.
    LOCAL ra IS SHIP:BODY:ROTATIONANGLE.
    LOCAL fi IS o2dIn(bI, fv).
    LOCAL ai IS o2dIn(bI, o2qBrF).
    LOCAL s IS "T732 " + tag + ": UT " + ROUND(ut, 2) + " seq '" + o2qSeq + "' hold " + o2qDap["hold"] + "/" + o2qDap["rf"] + " act " + o2qDap["act"]
        + " | RAW fore " + o2qT732V(fv) + " aim(BrF) " + o2qT732V(o2qBrF) + " dapRef " + o2qT732V(dr) + " sp " + o2qT732V(sp)
        + " | BODY w " + ROUND(bw:MAG * CONSTANT:RADTODEG, 5) + " deg/s, rotAng " + ROUND(ra, 3) + ", period " + ROUND(SHIP:BODY:ROTATIONPERIOD, 1) + " s"
        + " | INRTL comps fore " + o2qT732V(fi) + " aim " + o2qT732V(ai)
        + " | fore-aim " + o2qT732Ang(fv, o2qBrF) + " fore-dapRef " + o2qT732Ang(fv, dr) + " aimV-aim " + o2qT732Ang(o2qAimV, o2qBrF).
    IF o2qT732P:HASKEY("ut") {
        LOCAL dt IS ut - o2qT732P["ut"].
        LOCAL dra IS ra - o2qT732P["ra"].
        SET dra TO dra - 360 * FLOOR((dra + 180) / 360).
        SET s TO s + " || SINCE '" + o2qT732P["tag"] + "' (" + ROUND(dt, 2) + " s, the body turns " + ROUND(bw:MAG * CONSTANT:RADTODEG * dt, 3) + " deg, rotAng moved " + ROUND(dra, 3) + "): RAW fore moved " + o2qT732Ang(fv, o2qT732P["fv"])
            + " aim " + o2qT732Ang(o2qBrF, o2qT732P["aim"]) + " dapRef " + o2qT732Ang(dr, o2qT732P["dr"]) + " sp " + o2qT732Ang(sp, o2qT732P["sp"])
            + "; INRTL comps fore moved " + o2qT732Ang(fi, o2qT732P["fi"]) + " aim " + o2qT732Ang(ai, o2qT732P["ai"]).
    }
    o2qLogLine(s).
    SET o2qT732P TO LEXICON("tag", tag, "ut", ut, "fv", fv, "aim", o2qBrF, "dr", dr, "sp", sp, "ra", ra, "fi", fi, "ai", ai).
}
FUNCTION o2qWarpFreeOn {                     // A rails warp starts: the DAP lets the attitude drift (no jet may stop it: KSP's "under acceleration")
    IF O2Q_KOS_STEER OR NOT o2qDapOn OR o2qWarpFree { RETURN. }
    LOCAL fc IS SHIP:FACING.
    o2dHold(o2qDap, "FREE", fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()).
    SET o2qWarpFree TO TRUE.
    SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF("FREE").
    o2qDapPush().
    o2qLogLine("DAP FREE FOR THE WARP").
    IF o2qSeq = "WARP" AND O2Q_RAILS_SET AND o2qRailsOk() {      // The first warp too starts at the rate 0 (the second does in o2qRailsWarp2): the attitude the hold had is the one after it
        IF o2qRailsArm("ZERO") = "" { o2qLogLine("RAILS SET: the first warp starts at the rate 0 exactly (the C# sets it at the pack)"). }
    }
}
FUNCTION o2qWarpFreeOff {                    // the warp is over: the DAP holds the aim again (before an aim exists: the attitude now)
    IF NOT o2qWarpFree { RETURN. }
    o2qT732Snap("WARP END, BEFORE THE RE-HOLD").
    SET o2qWarpFree TO FALSE.
    IF NOT o2qDapOn { RETURN. }
    LOCAL fc IS SHIP:FACING.
    IF o2qB:HASKEY("steer") AND o2qDap["mode"] = "AUTO" { o2dHold(o2qDap, "INRTL", o2qBrF, o2qBrT, o2qGeo()). }
    ELSE { o2dStop(o2qDap, fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()). }
    SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF("INRTL").
    o2qDapPush().
    o2qLogLine("DAP HOLDS AGAIN AFTER THE WARP").
    o2qT732Snap("AFTER THE RE-HOLD").
}
FUNCTION o2qWarp {                           // a rails warp to UT ut (shuttle_exec warpToUT, not waited on here)
    PARAMETER ut.
    o2qWarpFreeOn().
    o2qRailsSettle().                            // The closed loop on the rate, the DAP is FREE
    o2qT732Snap("WARP START").
    SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
    KUNIVERSE:TIMEWARP:WARPTO(ut).
    SET o2qB["wut"] TO ut.
    SET o2qB["wend"] TO -1.
    SET o2qB["wn"] TO 0.                         // The re-issues of THIS warp
    SET o2qB["wnl"] TO FALSE.
}
FUNCTION o2qWarpRetry {                      // A warp that ended EARLY (cancelled: the rate 1 long before its UT) is asked again, up to O2Q_WARP_RETRY times; TRUE = re-issued
    IF o2qB["wn"] >= O2Q_WARP_RETRY {
        IF NOT o2qB["wnl"] { o2qLogLine("WARP CANCELLED EARLY, NOT RE-ISSUED (" + O2Q_WARP_RETRY + " TRIES): CONTINUING"). SET o2qB["wnl"] TO TRUE. }
        RETURN FALSE.
    }
    LOCAL short IS ROUND(o2qB["wut"] - TIME:SECONDS).
    SET o2qB["wn"] TO o2qB["wn"] + 1.
    o2qLogLine("WARP CANCELLED EARLY at UT " + ROUND(TIME:SECONDS) + " (" + short + " s short, rate " + ROUND(KUNIVERSE:TIMEWARP:RATE) + ", mode " + KUNIVERSE:TIMEWARP:MODE + "): RE-ISSUED " + o2qB["wn"] + " / " + O2Q_WARP_RETRY).
    IF O2Q_RAILS_SET AND o2qRailsOk() { IF o2qRailsArm("ZERO") = "" { o2qRailsSettle(). } }   // a refusal is logged; the re-issue goes on anyway (no null path mid-warp); the settle runs first
    SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
    KUNIVERSE:TIMEWARP:WARPTO(o2qB["wut"]).
    SET o2qSeqT TO TIME:SECONDS.                 // the one-second guard starts again (the first frame still reads rate 1)
    RETURN TRUE.
}
FUNCTION o2qWarpDone {                       // TRUE 0.5 s after the warp is over (arrived, or cancelled and not re-issued: rate 1), settled
    IF o2qB["wend"] < 0 {
        IF TIME:SECONDS - o2qSeqT > 1 AND (TIME:SECONDS >= o2qB["wut"] - 1 OR KUNIVERSE:TIMEWARP:RATE = 1)
            AND KUNIVERSE:TIMEWARP:ISSETTLED {
            IF TIME:SECONDS < o2qB["wut"] - O2Q_WARP_EARLY AND o2qWarpRetry() { RETURN FALSE. }
            SET o2qB["wend"] TO TIME:SECONDS.
        }
        RETURN FALSE.
    }
    IF TIME:SECONDS - o2qB["wend"] >= 0.5 { o2qWarpFreeOff(). RETURN TRUE. }
    RETURN FALSE.
}

// ---- the rate set before a rails warp (KalsCoproc RAILSARM / RAILSINFO, coproc/KalsAddon.Rails.cs) and the warp-down
GLOBAL o2qRailsHoldOn IS FALSE.              // the hold's rate is armed by the main loop (O2Q_RAILS_HOLD)
GLOBAL o2qRailsHoldT IS -1E9.
GLOBAL o2qGuardT IS -1E9.
FUNCTION o2qRailsOk {                        // the DLL has the set (an older one: the NULL / FINE phases fly as before)
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("RAILSARM").
}
GLOBAL o2qRailsArmT IS -1E9.                 // The last ZERO arm (kOS time): the settle only runs under a fresh one
FUNCTION o2qRailsArm {                       // "" = armed; else the reason it is not
    PARAMETER mode.
    IF NOT o2qRailsOk() { RETURN "NO RAILSARM IN THIS DLL". }
    LOCAL rs IS ADDONS:KALS:RAILSARM(mode, V(0, 0, 0)).
    IF rs <> "" { o2qLogLine("RAILS arm " + mode + " refused: " + rs). }
    ELSE IF mode = "ZERO" { SET o2qRailsArmT TO TIME:SECONDS. }
    RETURN rs.
}
FUNCTION o2qRailsSettle {                    // The DLL's closed loop on the rate (RAILSSETTLE) runs in the physics ticks BEFORE the warp is asked for; kOS waits for it
    IF NOT O2Q_RAILS_SETTLE OR NOT o2qRailsOk() { RETURN. }
    IF TIME:SECONDS - o2qRailsArmT > 100 { RETURN. }
    IF NOT ADDONS:KALS:HASSUFFIX("RAILSSETTLE") OR NOT ADDONS:KALS:HASSUFFIX("RAILSSETTLING") { RETURN. }
    LOCAL rs IS ADDONS:KALS:RAILSSETTLE(TRUE).
    IF rs <> "" { o2qLogLine("RAILS SETTLE not run: " + rs). RETURN. }
    LOCAL n IS 0.
    UNTIL NOT ADDONS:KALS:RAILSSETTLING OR n >= O2Q_RAILS_SETTLE_TICKS { WAIT 0. SET n TO n + 1. }
    IF ADDONS:KALS:RAILSSETTLING { ADDONS:KALS:RAILSSETTLE(FALSE). o2qLogLine("RAILS SETTLE: STOPPED AFTER " + n + " TICKS (O2Q_RAILS_SETTLE_TICKS)"). }
    ELSE { o2qLogLine("RAILS SETTLE: the rate is set, " + n + " physics ticks, " + ROUND(o2qRate(), 4) + " deg/s now"). }
    o2qRailsPoll().
}
FUNCTION o2qRailsWarp2 {                     // pointed: the rate 0 set at the pack, the second warp to TIG - O2Q_SETTLE_LEAD (a refused arm: the null as before)
    PARAMETER how.
    IF o2qRailsArm("ZERO") <> "" { SET o2qB["tq"] TO -1. o2qPhase("NULL", ""). RETURN. }
    SET o2qB["rails"] TO TRUE.
    o2qLogLine("RAILS SET: the second warp starts at the rate 0 exactly (the C# sets it at the pack), " + ROUND(o2qAimErr(), 3) + " deg off the aim, the rate " + ROUND(o2qRate(), 4) + " deg/s now").
    o2qPhase("WARP2", (CHOOSE "" IF ((how = "ALIGNED") OR (how = "POINTED")) ELSE ("WARP TO TIG" + o2Cd(O2Q_SETTLE_LEAD)))).
    o2qWarp(o2qB["ig"] - O2Q_SETTLE_LEAD).
}
FUNCTION o2qRailsOff {
    SET o2qRailsHoldOn TO FALSE.
    IF o2qRailsOk() { ADDONS:KALS:RAILSARM("OFF", V(0, 0, 0)). ADDONS:KALS:RAILSWATCH(FALSE). }
}
FUNCTION o2qRailsPoll {                      // the C# lines (each pack / set / unpack) into the log
    IF NOT o2qRailsOk() { RETURN. }
    IF NOT ADDONS:KALS:HASSUFFIX("RAILSINFO") { RETURN. }
    FOR rln IN ADDONS:KALS:RAILSINFO["log"] {
        o2qLogLine(rln).
        IF rln:CONTAINS("RAILS pack:") { o2qT732Snap("POLL SAW PACK"). }
        IF rln:CONTAINS("RAILS unpack:") { o2qT732Snap("POLL SAW UNPACK"). }
    }
}
FUNCTION o2qRailsHoldTick {                  // O2Q_RAILS_HOLD: while the DAP flies a hold, the next rails warp keeps its rate (re-armed every 30 s: the arm lapses after 120 s)
    IF NOT O2Q_RAILS_HOLD { RETURN. }
    IF o2qSeq <> "" { RETURN. }
    IF NOT o2qRailsOk() { RETURN. }
    IF o2qDapOn {
        IF TIME:SECONDS - o2qRailsHoldT >= 30 {
            SET o2qRailsHoldT TO TIME:SECONDS.
            IF o2qRailsArm("HOLD") = "" { SET o2qRailsHoldOn TO TRUE. ADDONS:KALS:RAILSWATCH(TRUE). }
        }
        o2qRailsPoll().
    } ELSE IF o2qRailsHoldOn {
        o2qRailsPoll().
        o2qRailsOff().
    }
}
FUNCTION o2qWarpGuard {                      // a warp toward a loaded burn steps down: 1x at O2Q_GUARD_LEAD s before TIG, time to ARM, EXEC and align
    IF NOT O2Q_WARP_GUARD { RETURN. }
    IF o2qSeq <> "" OR NOT o2qLoaded() { RETURN. }          // the sequence's own warps end where they are meant to
    LOCAL rate IS KUNIVERSE:TIMEWARP:RATE.
    IF rate <= 4.5 { RETURN. }                               // 1x .. the physics warp: the lead is long enough
    LOCAL tti IS o2qUtOf(o2Val["tig"]) - TIME:SECONDS.
    IF tti < 0 { RETURN. }                                   // TIG gone: nothing to guard
    IF tti > O2Q_GUARD_LEAD + rate * O2Q_GUARD_REACT { RETURN. }
    IF KUNIVERSE:TIMEWARP:MODE = "RAILS" AND KUNIVERSE:TIMEWARP:WARP > 0 { SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1. }
    ELSE { KUNIVERSE:TIMEWARP:CANCELWARP(). }
    o2qLogLine("WARP GUARD: x" + ROUND(rate) + " stepped down (index now " + KUNIVERSE:TIMEWARP:WARP + "), TIG in " + ROUND(tti) + " s (lead " + O2Q_GUARD_LEAD + " s + " + O2Q_GUARD_REACT + " s of the rate)").
    IF TIME:SECONDS - o2qGuardT >= 8 {
        SET o2qGuardT TO TIME:SECONDS.
        o2qSay("WARP DOWN FOR TIG" + o2Cd(tti), "Y").
    }
}

// ---- MNVR pressed long before TIG, then EXEC. The sequence's first warp frees the DAP (o2qWarpFreeOn) and
// the rails warp keeps the attitude of that moment, so a MNVR turn still running at EXEC was dropped (P1b: MNVR 125.8 deg at the page RATE 0.5
// deg/s = 251 s, EXEC 7.7 s later, the ALIGN at TIG-5 turned 111.7 deg = 125.8 - 2.9 - 11.07 of rails drift). Now EXEC with the DAP's act MNVR
// running and room before the warp's start waits in the phase MNVR (at the PAGE RATE, as the real MNVR flies the selected rate) for 'MNVR
// COMPLETE' and the rate down, then warps as before. No room: the old path, with a message. The rails drift stays.
FUNCTION o2qMnvrLeft {                       // s the running MNVR still needs at the DAP's rate (the turn need), 0 = none running
    IF NOT O2Q_MNVR_WAIT_ON OR O2Q_KOS_STEER OR NOT o2qDapOn { RETURN 0. }
    IF o2qDap["mode"] <> "AUTO" OR o2qDap["act"] <> "MNVR" { RETURN 0. }
    RETURN o2qDap["ea"] / MAX(o2qDap["rate"], 0.05) * O2Q_TURN_K + O2Q_TURN_PAD.
}
FUNCTION o2qMnvrStep {                       // the phase MNVR's decision each tick: "WAIT", "DONE" (turn complete, rate down) or "NEAR" (no time left)
    PARAMETER now.
    IF NOT o2qDapOn { RETURN "DONE". }
    LOCAL out IS now > o2qB["mvend"] OR now > o2qB["ig"] - (O2Q_ALIGN_LEAD + 15).
    IF o2qMnvrLeft() > 0 { RETURN CHOOSE "NEAR" IF out ELSE "WAIT". }
    IF o2qDap["act"] = "HOLD" AND o2qRate() >= O2Q_RATE_TOL AND NOT out { RETURN "WAIT". }
    RETURN "DONE".
}
FUNCTION o2qWarpOrSetup {                    // after EXEC (and after the MNVR phase): the first warp when TIG is far enough, else the setup
    LOCAL ig IS o2qB["ig"].
    IF ig - TIME:SECONDS > O2Q_ALIGN_LEAD + 15 {
        o2qPhase("WARP", "WARP TO TIG" + o2Cd(O2Q_ALIGN_LEAD)).
        o2qWarp(ig - O2Q_ALIGN_LEAD).
    } ELSE { o2qPhase("SETUP", ""). }
}

FUNCTION o2qSeqStart {                       // the burn on the page, frozen: PEG 7's VGO at the centre's LVLH
    PARAMETER ig.
    LOCAL k8 IS o2qPeg8().                   // PEG 8 flies when the page has a shot; else the planned dV as PEG 7 (the fallback)
    IF k8 AND (o2qP8:LENGTH = 0 OR o2qP8["nosol"] OR o2qP8["nres"] = 0) {
        SET k8 TO FALSE.
        o2qP8Drop("PEG 8: " + (CHOOSE o2qP8["why"]:TOUPPER IF o2qP8:LENGTH > 0 AND o2qP8["why"] <> "" ELSE "NO SOLUTION") + ": BACKUP SW PEG 7").
    }
    LOCAL dv IS o2qDv().
    LOCAL tb IS o2qTb(o2qDvTot()).
    LOCAL ct IS ig + tb / 2.
    LOCAL k4 IS o2qPeg4().
    SET o2qB TO LEXICON("ig", ig, "tb", tb, "dv", dv:COPY, "peg", CHOOSE o2qP4 IF k4 ELSE (CHOOSE o2qP8 IF k8 ELSE o2pNew(dv, o2qFrameAt(ct))),
        "gn", CHOOSE "PEG 4" IF k4 ELSE (CHOOSE "PEG 8" IF k8 ELSE "PEG 7"), "eng", o2qOms(),
        "ea", o2qAfter(ct, dv), "src", o2qLoad["src"], "tree", o2qLoad["tree"], "node", o2qLoad["node"], "type", o2qLoad["type"], "tag", o2qLoad["tag"], "d", o2qLoad["d"], "lit", FALSE,
        "chk", FALSE, "scalar", FALSE, "cutreq", FALSE, "n", 0, "why", "", "t0", 0, "tcut", 0, "ag6", FALSE,
        "wut", 0, "wend", -1, "tq", -1, "ek", o2qOmsK(), "ig0", ig, "trm", -1, "rails", FALSE, "held", FALSE, "ovr", FALSE, "heldt", 0, "wn", 0, "wnl", FALSE, "rc", FALSE).
    SET o2qB["bk"] TO o2bKey(o2qLoad["file"], o2qLoad["d"], o2qOps3Rule(o2qLoad["tag"], dv[0], CHOOSE o2qLoad["d"]["runway"] IF o2qLoad["d"]:HASKEY("runway") ELSE "none")).   // the burn's key in the record
    o2bPut("EXEC", o2qB["bk"], ig, 0, o2qDvTot(), "-").
    SET o2qRes TO LEXICON().
    SET o2qP4 TO LEXICON().                  // the page's PEG 4 is the burn's now
    SET o2qP8 TO LEXICON().                  // (and PEG 8; o2qB["peg"] keeps the lexicon)
    IF k8 { o2qLogLine("EXEC PEG 8: AIM " + (CHOOSE "BURN " + o2qB["peg"]["aim"]["next"] + " IGNITION" IF o2qB["peg"]["aim"]["next"] <> "" ELSE "HALF AN ORBIT ON") + " at UT " + ROUND(o2qB["peg"]["aimt"], 1)
        + ", the shot's miss " + ROUND(o2qB["peg"]["miss"], 2) + " m, PEG 7 on the planned dV would miss by " + ROUND(o2qB["peg"]["missP"], 1) + " m, " + o2qB["peg"]["nres"] + " shots, " + ROUND(o2qB["peg"]["ms"], 2) + " ms the last"). }
    IF k4 { o2qLogLine("EXEC PEG 4: C1 " + ROUND(o2Val["c1"], 2) + " m/s, C2 " + ROUND(o2Val["c2"], 7) + ", HT "
        + ROUND(o2Val["ht"], 3) + " km, THETA T " + ROUND(o2Val["tht"], 4) + " deg from TIG, J2 " + o2qB["peg"]["gv"]["j2"]
        + ", the aim's offsets " + ROUND(o2qB["peg"]["aoff"], 5) + " / " + ROUND(o2qB["peg"]["goff"], 5) + " deg"). }
    o2qLogLine("EXEC " + o2qB["src"] + ": TIG UT " + ROUND(ig, 2) + ", LVLH DV " + ROUND(dv[0], 3) + " / "
        + ROUND(dv[1], 3) + " / " + ROUND(dv[2], 3) + " at the centre UT " + ROUND(ct, 2) + ", tb " + ROUND(tb, 2) + " s, OMS "
        + o2qKNames(o2qB["ek"]) + ", FAILURES " + (CHOOSE "SCHEDULE " IF fuiSchedOn() ELSE "") + (CHOOSE "RAND " IF fuiRandOn() ELSE "") + flPending() + " ROWS").
    IF o2qB["type"] = "DEORB" OR o2qOps3Rule(o2qLoad["tag"], dv[0], CHOOSE o2qLoad["d"]["runway"] IF o2qLoad["d"]:HASKEY("runway") ELSE "none") {
        o2qCloseBay().                       // The doors close for the burn that hands over to OPS3 only (a deorbit, the AOA's OMS-2)
    } ELSE { o2qLogLine("BAY DOORS LEFT AS THEY ARE (NOT THE DEORBIT BURN)"). }   // any other burn: on orbit they stay open for the radiators
    SET o2qWarpFree TO FALSE.
    IF O2Q_KOS_STEER { o2qDapStandby("BURN SEQUENCE"). }   // legacy: from EXEC kOS's steering flies, the DAP stands by
    ELSE { o2qLogLine("DAP STAYS ON FOR THE BURN SEQUENCE (T638: it flies the burn attitude; FREE in the warps)"). }
    IF o2qRailsOk() {                        // the C# logs every pack / unpack of the sequence's warps
        IF ADDONS:KALS:HASSUFFIX("RAILSWATCH") {
            ADDONS:KALS:RAILSWATCH(TRUE).
            SET o2qRailsHoldOn TO FALSE.
            SET o2qB["rails"] TO TRUE.
        }
    }
    LOCAL mv IS o2qMnvrLeft().               // A MNVR turn still running at EXEC
    IF mv > 0 {
        LOCAL cap IS mv * 1.3 + 60.
        IF ig - TIME:SECONDS > O2Q_ALIGN_LEAD + 15 + cap {      // room: finish the turn at 1x, then the warp
            SET o2qB["mvend"] TO TIME:SECONDS + cap.
            o2qPhase("MNVR", "MNVR TO BURN ATT: " + ROUND(o2qDap["ea"]) + " DEG: ~ " + ROUND(mv) + " S").
            RETURN.
        }
        o2qLogLine("MNVR NOT COMPLETE at EXEC: " + ROUND(o2qDap["ea"], 1) + " deg to go, no room before the warp (TIG" + o2Cd(ig - TIME:SECONDS) + ")").
        o2qSay("MNVR NOT COMPLETED", "Y").
    }
    o2qWarpOrSetup().
}

// ---- SW 02 GUIDANCE LOST (ORBIT BURN). The burn's GUIDANCE halts, nothing else: no VGO re-solve (PEG 4 cycle, PEG 8 shot, the
// page's syncs), no aim update (o2qAimTv, o2p4Aim, o2qAimPre's solve): the attitude the PEG last commanded is held (the DAP's own hold:
// SW 01 is separate). The engines' dV count (o2pSense) stays live, so VGO along falls with what was sensed and the burn ends on the
// plan's dV (o2pEnd CUT) or the time guard. TGO and VGX / VGY / VGZ on the page blank; VGO TOT (the dV counter) stays.
FUNCTION o2qGdLost {                         // TRUE while SW 02 holds the burn's guidance (O(1) with no failure: flfxSwLost's empty-list exit)
    IF NOT (DEFINED FLFX_SWPROG) { RETURN FALSE. }
    RETURN flfxSwGuid("ORBIT BURN").
}
FUNCTION o2qGdEdge {                         // o2qGdLost, and the loss / the restart logged once
    LOCAL gl IS o2qGdLost().
    IF gl <> o2qGdWas {
        SET o2qGdWas TO gl.
        IF gl {
            LOCAL al IS "-".
            IF o2qSeq <> "" { IF o2qB:HASKEY("peg") { SET al TO "" + ROUND(o2pAlong(o2qB["peg"]), 3). } }
            o2qLogLine("SW 02 ORBIT BURN GUIDANCE LOST (sequence " + o2qSeq + ", burn lit " + (CHOOSE "yes" IF (o2qSeq <> "" AND o2qB:HASKEY("lit") AND o2qB["lit"]) ELSE "no") + ", VGO along " + al + " m/s): no VGO re-solve, the aim is held, the dV count flies on to the plan's dV (cut at VGO 0, the time guard bounds it)").
        } ELSE { o2qLogLine("SW 02 ORBIT BURN GUIDANCE RESTARTED: VGO and the aim re-solve from the state (RESTART SW)"). }
    }
    RETURN gl.
}
FUNCTION o2qAimPre {                         // before ignition: VGO from the live conic, the aim through the thrust line
    LOCAL pg IS o2qB["peg"].
    IF o2qB["ig"] - TIME:SECONDS > 1 AND NOT o2qGdEdge() {   // SW 02 holds the solve (the aim stays on the last VGO direction)
        IF pg:HASKEY("rt") {                 // PEG 4: the target afresh from TIG's prediction, the aim, VGO at the centre
            LOCAL sc IS o2qAtJ(o2qB["ig"] + o2qB["tb"] / 2).      // With the J2 drift (the aim no longer moves ~1.2 deg over the second warp)
            o2p4Pre(pg, o2qP4Tgt(), sc[0], sc[1], TIME:SECONDS).
            IF NOT pg["nosol"] {                 // The aim at the IGNITION is VGO from the state at TIG (what the first in-burn o2p4Cycle solves), not the centre's:
                LOCAL s0 IS o2qAtJ(o2qB["ig"]).  // the centre's differs by the orbit's turn over half the burn (0.9 deg + the gravity part = the 1.5 deg step at +0.3 s of every PEG 4 burn); the J2 drift
                LOCAL vw0 IS o2p4Vreq(pg, s0[0], s0[1]).
                IF O2Q_AIM_TIG AND vw0:MAG > 0 { SET o2qB["aim0"] TO o2Unit(vw0 - s0[1]). }
            }
        } ELSE IF pg:HASKEY("p8") AND pg["p8"] {   // PEG 8: a shot when due (the impulse at the centre), no solution: the planned dV as PEG 7
            IF o2p8Due(pg, TIME:SECONDS) {
                LOCAL ct IS o2qB["ig"] + o2qB["tb"] / 2.
                o2p8Shot(pg, TIME:SECONDS, o2qRv(), SHIP:VELOCITY:ORBIT, MAX(ct, TIME:SECONDS), o2qDvgAt(ct)).
                IF pg["nosol"] {
                    o2p8Fall(pg, o2qFrameAt(ct)).
                    SET o2qB["gn"] TO "PEG 7".
                    o2qSay("PEG 8: " + pg["why"]:TOUPPER + ": BACKUP SW PEG 7", "Y").
                    o2qLogLine("PEG 8 fell back to PEG 7 before the ignition: " + pg["why"]).
                }
            }
        } ELSE { o2pRefresh(pg, o2qFrameAt(o2qB["ig"] + o2qB["tb"] / 2)). }
    }
    LOCAL lnP IS o2qLineAx(o2qB["eng"]).
    LOCAL lg IS o2lGet(o2lUids(o2qB["eng"]), "auto").
    SET o2qLf TO o2lNew().
    IF lg["ok"] {                            // the addon's line (the trim before any thrust): the lag starts on it, no step at the first thrust
        SET lnP TO lg["f"].
        o2lSeed(o2qLf, lnP).
    }
    o2qAimTv(CHOOSE o2qB["aim0"] IF o2qB:HASKEY("aim0") ELSE o2pDir(pg), lnP).
}
FUNCTION o2qLine {                           // the OMS thrust line (kN vector), the gimbal in it: lib_o2line's (the measured thrust, before any
    PARAMETER ens.                           // the trim through the c.g.) when the addon answers OMSLINE, else the part axes'
    RETURN o2lLine(o2lUids(ens), "auto", o2qLineAx(ens)).
}
FUNCTION o2qLineAx {                         // the part-axes line (kN vector, no gimbal): the thrust along each engine's axis, or,
    PARAMETER ens.                           // before any, the available thrust's, else the possible
    LOCAL fv IS V(0, 0, 0).
    FOR en IN ens { SET fv TO fv + en:FACING:FOREVECTOR * en:THRUST. }
    IF fv:MAG > 0.01 { RETURN fv. }
    FOR en IN ens { SET fv TO fv + en:FACING:FOREVECTOR * en:AVAILABLETHRUST. }
    IF fv:MAG > 0.01 { RETURN fv. }
    FOR en IN ens { SET fv TO fv + en:FACING:FOREVECTOR * en:POSSIBLETHRUSTAT(0). }
    IF fv:MAG > 0.01 { RETURN fv. }
    RETURN SHIP:FACING:FOREVECTOR.
}
FUNCTION o2qRate { RETURN SHIP:ANGULARVEL:MAG * CONSTANT:RADTODEG. }
FUNCTION o2qAimErr { RETURN VANG(SHIP:FACING:FOREVECTOR, o2qAimV). }

FUNCTION o2qSeqTick {                        // the main loop's step of the sequence (the burn itself is the trigger's)
    IF o2qSeq = "" { RETURN. }
    LOCAL now IS TIME:SECONDS.
    LOCAL tti IS o2qB["ig"] - now.
    IF o2qB["rails"] { o2qRailsPoll(). }
    IF o2qSeq = "MNVR" {                     // The MNVR turn finishes at 1x before the first warp
        LOCAL ms IS o2qMnvrStep(now).
        IF ms = "WAIT" { RETURN. }
        IF ms = "NEAR" {
            o2qLogLine("MNVR NOT COMPLETE after " + ROUND(now - o2qSeqT) + " s: " + ROUND(o2qDap["ea"], 1) + " deg to go (TIG" + o2Cd(tti) + ")").
            o2qSay("MNVR NOT COMPLETED", "Y").
        } ELSE { o2qLogLine("MNVR PHASE DONE in " + ROUND(now - o2qSeqT) + " s, " + ROUND(o2qDap["ea"], 2) + " deg off the aim, rate " + ROUND(o2qRate(), 3) + " deg/s"). }
        o2qWarpOrSetup().
        RETURN.
    }
    IF o2qSeq = "WARP" {
        IF o2qWarpDone() { o2qPhase("SETUP", ""). }
        RETURN.
    }
    IF o2qSeq = "SETUP" {                    // after the warp: the gimbals, SAS, RCS, the OMS control point
        LOCAL ng IS o2qUnlockGimbals().
        SAS OFF.
        RCS ON.
        IF O2Q_CTRL_PAIR { TOGGLE AG6. SET o2qAg6 TO AG6. SET o2qB["ag6"] TO TRUE. SET o2qCtrl TO "OMS". SET o2Val["ctrl"] TO 1. }   // own toggle, not a press
        IF o2qVern["on"] { o2qVernSet(FALSE, FALSE). o2qSay("JET SEL PRI", "V"). }   // the burn's RCS is the primaries
        o2qLogLine("OMS GIMBALS " + ng + " UNLOCKED, RCS ON, OMS CONTROL POINT").         // The log only, not the page
        o2qPhase("SETUP2", "").
        RETURN.
    }
    IF o2qSeq = "SETUP2" {
        IF now - o2qSeqT < (CHOOSE 1 IF O2Q_CTRL_PAIR ELSE 0.5) { RETURN. }
        o2qAimPre().
        IF O2Q_KOS_STEER { LOCK STEERING TO o2qAimV. } ELSE { o2qAlignStart(). }
        SET o2qB["steer"] TO TRUE.
        o2qPhase("ALIGN", (CHOOSE "MNVR TO BURN ATT" IF O2Q_KOS_STEER ELSE o2qAlignTxt)).
        RETURN.
    }
    IF o2qSeq = "ALIGN" OR o2qSeq = "AIM" OR o2qSeq = "NULL" OR o2qSeq = "FINE" OR o2qSeq = "WARP2" OR o2qSeq = "SETTLE" {
        IF NOT o2qB["lit"] { o2qAimPre(). }
    }
    IF o2qSeq = "ALIGN" {
        // The cut is for the legacy kOS steering (real time only), rails, or a rate over 4x; the C# DAP turns at 1x-4x physics warp
        IF KUNIVERSE:TIMEWARP:RATE > 1 AND (O2Q_KOS_STEER OR KUNIVERSE:TIMEWARP:MODE = "RAILS" OR KUNIVERSE:TIMEWARP:RATE > 4.05) {
            IF NOT o2qB["rc"] { SET o2qB["rc"] TO TRUE. o2qLogLine("ALIGN: RAILS WARP CUT (the DAP turns at 1x-4x only)"). }
            SET KUNIVERSE:TIMEWARP:WARP TO 0.
            SET o2qSeqT TO now.
            RETURN.
        }
        LOCAL ok IS FALSE.
        IF O2Q_KOS_STEER { SET ok TO o2qAimErr() < O2Q_ALIGN_TOL AND ABS(STEERINGMANAGER:ROLLERROR) < O2Q_ROLL_TOL. }
        ELSE { SET ok TO o2qAimErr() < O2Q_ALIGN_TOL AND o2qDap["act"] = "HOLD" AND o2qRate() < O2Q_RATE_TOL. }   // The DAP's MNVR complete (inside its DB), pointed, the rate down
        IF ok OR now - o2qSeqT > (CHOOSE O2Q_ALIGN_MAX IF O2Q_KOS_STEER ELSE o2qAlignMax) OR tti <= 0 {
            LOCAL how IS "ALIGNED".
            IF NOT ok { SET how TO (CHOOSE "ROLL UNSETTLED" IF O2Q_KOS_STEER ELSE "RATE UNSETTLED"). }
            IF o2qAimErr() >= O2Q_ALIGN_TOL { SET how TO "ALIGN FAILED: " + ROUND(o2qAimErr(), 1) + " DEG OFF". }
            o2qLogLine("ALIGN " + how + " in " + ROUND(now - o2qSeqT, 1) + " s, rate " + ROUND(o2qRate(), 3) + " deg/s").
            IF tti > O2Q_SETTLE_LEAD + 5 {
                IF O2Q_RAILS_SET AND o2qRailsOk() {   // no NULL / FINE: the rate is set exactly in the last frame before the pack
                    IF o2qAimErr() < O2Q_ALIGN_TOL { o2qRailsWarp2(how). }   // One alignment, straight to the second warp
                    ELSE { o2qPhase("AIM", ""). }
                } ELSE { SET o2qB["tq"] TO -1. o2qPhase("NULL", ""). }   // an older DLL (or O2Q_RAILS_SET off): the null as before
            }
            ELSE { o2qSettle(how). }
        }
        RETURN.
    }
    IF o2qSeq = "AIM" {                      // ALIGN ended unpointed: no warp until pointed (the rate needs no null: it is set at the pack)
        IF tti <= O2Q_SETTLE_LEAD + 5 { o2qSettle("NOT POINTED: NO WARP"). RETURN. }
        IF o2qAimErr() < O2Q_ALIGN_TOL { o2qRailsWarp2("POINTED"). }   // One alignment, straight to the second warp
        RETURN.
    }
    IF o2qSeq = "NULL" {                     // the rates held under O2Q_RATE_TOL for O2Q_RATE_HOLD s, pointed
        IF tti <= O2Q_SETTLE_LEAD + 5 { o2qSettle("RATES NOT NULLED: NO WARP"). RETURN. }
        IF o2qRate() < O2Q_RATE_TOL AND o2qAimErr() < O2Q_ALIGN_TOL {
            IF o2qB["tq"] < 0 { SET o2qB["tq"] TO now. }
            IF now - o2qB["tq"] >= O2Q_RATE_HOLD {
                RCS OFF.
                SET o2qB["r0"] TO o2qRate().
                o2qPhase("FINE", "").
            }
        } ELSE { SET o2qB["tq"] TO -1. }
        RETURN.
    }
    IF o2qSeq = "FINE" {                     // the wheels alone (RCS off): the first sample under O2Q_RATE_FINE
        LOCAL ok IS o2qRate() < O2Q_RATE_FINE AND o2qAimErr() < O2Q_ALIGN_TOL.
        IF ok OR now - o2qSeqT > O2Q_FINE_MAX OR tti <= O2Q_SETTLE_LEAD + 5 {
            o2qLogLine("rate null, the wheels (RCS off): " + ROUND(o2qB["r0"], 4) + " -> " + ROUND(o2qRate(), 4)
                + " deg/s in " + ROUND(now - o2qSeqT, 1) + " s (" + (CHOOSE "under" IF ok ELSE "timed out over") + " " + O2Q_RATE_FINE
                + "), " + ROUND(o2qAimErr(), 3) + " deg off the aim").
            IF tti - O2Q_SETTLE_LEAD > 2 {
                o2qPhase("WARP2", "WARP TO TIG" + o2Cd(O2Q_SETTLE_LEAD)).
                o2qWarp(o2qB["ig"] - O2Q_SETTLE_LEAD).
            } ELSE { o2qSettle(""). }
        }
        RETURN.
    }
    IF o2qSeq = "WARP2" {
        IF o2qWarpDone() { o2qSettle(""). }
        RETURN.
    }
    IF o2qSeq = "SETTLE" {
        IF o2qB["lit"] { o2qPhase("BURN", "IGNITION " + o2qB["gn"]). }
        RETURN.
    }
    IF o2qSeq = "BURN" {
        IF o2qBurnOn AND o2qB["peg"]:HASKEY("rt") AND NOT o2qGdLost() { o2p4Aim(o2qB["peg"], o2qRv(), SHIP:VELOCITY:ORBIT, now). }
        IF NOT o2qBurnOn { o2qSeqEnd(). }
        RETURN.
    }
}

FUNCTION o2qSettle {                         // RCS on, the throttle locked at 0, the trigger set: it ignites at TIG
    PARAMETER why.
    RCS ON.
    IF KUNIVERSE:TIMEWARP:RATE > 1 { SET KUNIVERSE:TIMEWARP:WARP TO 0. }
    SET o2qThr TO 0.
    LOCK THROTTLE TO o2qThr.
    o2qOmsLight().
    IF o2qDapOn AND NOT O2Q_KOS_STEER AND o2qDap["db"] > O2Q_SETTLE_DB {      // The narrower deadband for the last 59 s: the ignition error is the box edge otherwise
        SET o2qDap["db"] TO O2Q_SETTLE_DB.
        o2qDapPush().
        o2qLogLine("DAP SETTLE DB: " + O2Q_SETTLE_DB + " deg until the burn (the pre-TIG hold idled inside the page's DB box)").
    }
    SET o2qBurnOn TO TRUE.
    IF NOT o2qTrig {
        SET o2qTrig TO TRUE.
        WHEN TRUE THEN {
            IF NOT o2qBurnOn { SET o2qTrig TO FALSE. RETURN FALSE. }
            o2qBurnTick().
            RETURN TRUE.
        }
    }
    o2qPhase("SETTLE", "").
}

// each physics tick from the settle on (the trigger): ignition at TIG, the sensed dV, the steering, the throttle, the
// end (the cut, the thrust lost, the time guard, the crew's CUT OFF)
FUNCTION o2qBurnTick {
    LOCAL now IS TIME:SECONDS.
    IF NOT o2qB["lit"] AND O2Q_IGN_ERR > 0 AND NOT o2qB["ovr"] AND (o2qB["ig"] - now <= 0 OR o2qB["held"]) {   // The auto EXEC is HELD at TIG while the attitude error is over O2Q_IGN_ERR
        LOCAL ie IS CHOOSE o2qDap["ea"] IF (o2qDapOn AND NOT O2Q_KOS_STEER) ELSE o2qAimErr().
        IF ie > O2Q_IGN_ERR {
            IF NOT o2qB["held"] {
                SET o2qB["held"] TO TRUE.
                SET o2qB["heldt"] TO now.
                o2qSay("OMS ATT ERR > " + O2Q_IGN_ERR + " DEG - EXEC HELD", "Y").
                o2qLogLine("EXEC HELD at TIG: the attitude error " + ROUND(ie, 1) + " deg (over " + O2Q_IGN_ERR + "): the ignition waits for it, TIG slips with the clock (PEG re-solves for it), EXEC overrides").
            }
            SET o2qB["ig"] TO now + 2.      // the late TIG: o2qAimPre keeps solving the aim for it (it does while TIG is over 1 s ahead)
            RETURN.
        }
        IF o2qB["held"] {
            SET o2qB["held"] TO FALSE.
            SET o2qB["ig"] TO now.
            o2qLogLine("EXEC RELEASED: the attitude error " + ROUND(ie, 2) + " deg after " + ROUND(now - o2qB["heldt"], 1) + " s held (TIG slipped " + ROUND(now - o2qB["ig0"], 1) + " s)").
        }
    }
    IF now < o2qB["ig"] { RETURN. }
    LOCAL pg IS o2qB["peg"].
    IF NOT o2qB["lit"] {
        SET o2qB["lit"] TO TRUE.
        SET o2qB["t0"] TO now.
        SET o2qLineT TO now.
        SET o2qDapAuT TO -1E9.               // The authority afresh (kOS-flown DAP; the C# one reads FBWAUTH each second)
        IF o2qDapOn AND NOT O2Q_KOS_STEER {  // The burn gains + integral from the ignition (o2qDapResume puts the orbit hold's back after the burn)
            SET o2qDap["k"] TO O2Q_BURN_K. SET o2qDap["tau"] TO O2Q_BURN_TAU. SET o2qDap["ki"] TO O2Q_BURN_KI.
            SET o2qDap["db"] TO MIN(o2qDap["db"], O2Q_BURN_DB_LIT).      // The narrower burn deadband from the ignition (o2qDapResume gives the page's back)
            LOCAL sd IS o2qSeedGet().          // The pitch trim seeded from the last burn of this flight (0 = none: the unseeded law)
            IF sd <> 0 { SET o2qDap["uis"] TO sd. SET o2qDap["uisN"] TO o2qDap["uisN"] + 1. }
            o2qDapPush().
            IF sd <> 0 { o2qLogLine("DAP SEED: the pitch trim " + ROUND(sd, 3) + " deg/s2 at the ignition (" + O2Q_SEED_K + " x the last burn's learned trim, the sign guard " + O2D_SEEDGTH + " deg in " + O2D_SEEDGT + " s)"). }
            o2qLogLine("DAP BURN GAINS: K " + O2Q_BURN_K + ", TAU " + O2Q_BURN_TAU + ", KI " + O2Q_BURN_KI + ", DB " + o2qDap["db"] + " (the hold's integral trim on the full error, UI max " + O2D_UIMAX + " deg/s2)").

        }
        o2qGmSet("IGNITION").                // The gimbal mode for the burn (the DLL turns the jets off at 80 % thrust)
        IF pg:HASKEY("p8") AND pg["p8"] { SET pg["tshot"] TO -1E9. }   // the first shot in the burn at once
        o2bPut("IGN", o2qB["bk"], now, 0, 0, "-").
        o2qStateLog("ign").
        o2qBurnLogStart().
        o2qLogLine("TV ROLL at ignition: " + ROUND(o2qTvMeas, 1) + " deg about the thrust line (entry " + ROUND(o2Val["tvr"], 1) + ", from the vertical now; held inertially from here)").
        SET o2bnOn TO O2BN_ENABLE AND o2bnArm(pg, o2qB["tb"], now).   // The burn's per-tick work in C# (O2BURN*); ASSIGNS: a stale TRUE from a burn that ended outside o2bnTick (o2qSeqStop) is wiped
        IF O2BN_ENABLE { o2qLogLine("BURN TICK: " + (CHOOSE "C# (O2BURN)" IF o2bnOn ELSE "kOS (" + O2BN_FAIL + ")")). }
    }
    IF o2bnOn { IF o2bnTick(now) { RETURN. } }   // The same tick on the DLL (lib_o2bn.ks); FALSE = it failed before changing anything: the kOS tick below flies this tick and the rest
    LOCAL fv IS V(0, 0, 0).                  // the thrust along the engines' axes, kN (each gave it over the last tick)
    LOCAL fs IS 0.                           // their scalar thrust
    LOCAL av IS V(0, 0, 0).                  // the available thrust along them
    FOR en IN o2qB["eng"] {
        LOCAL ax IS en:FACING:FOREVECTOR.
        SET fv TO fv + ax * en:THRUST.
        SET fs TO fs + en:THRUST.
    }
    LOCAL ul IS o2lUids(o2qB["eng"]).
    LOCAL ol IS o2lGet(ul, "meas").          // the thrust they gave, the gimbal in it (OMSLINE); not ok: the part axes above
    IF ol["ok"] { SET fv TO ol["f"]. }
    o2qBurnRm(now).                          // the OMS RM: a failed engine out of the burn (its last tick's thrust counted)
    IF o2qGmMode <> 0 AND o2qB["eng"]:LENGTH <> o2qGmN { o2qGmSet("ENGINES " + o2qB["eng"]:LENGTH). }   // One engine left: the roll jets only
    FOR en IN o2qB["eng"] { SET av TO av + en:FACING:FOREVECTOR * en:AVAILABLETHRUST. }
    // one second in: the engines' axes must carry their thrust, else the count goes scalar along the control point's
    // fore (shuttle_exec's check)
    IF NOT o2qB["chk"] AND now - o2qB["t0"] > 1 {
        SET o2qB["chk"] TO TRUE.
        IF fs > 0 AND fv:MAG < O2P_AXIS_MIN * fs {
            SET o2qB["scalar"] TO TRUE.
            o2qLogLine("BURN the engines' axes give " + ROUND(fv:MAG / fs, 4) + " of the thrust -> the scalar count").
        }
    }
    IF o2qB["scalar"] {
        SET fv TO SHIP:FACING:FOREVECTOR * fs.
        SET av TO SHIP:FACING:FOREVECTOR * SHIP:AVAILABLETHRUST.
    }
    LOCAL ms IS SHIP:MASS.
    o2pSense(pg, fv / ms, now).
    LOCAL gdl IS o2qGdEdge().                // SW 02 ORBIT BURN: the guidance halts (the count below flies on)
    IF pg:HASKEY("rt") AND NOT gdl { o2p4Cycle(pg, SHIP:POSITION - SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT). }   // PEG 4: VGO = v' - v
    IF pg:HASKEY("p8") AND pg["p8"] AND NOT gdl AND o2p8Due(pg, now) {   // PEG 8: the shot from the state now (the impulse now, the guess what is left); a failed one: the sensed count flies on
        o2p8Shot(pg, now, SHIP:POSITION - SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT, now, pg["vgo"]).
        IF pg["nfail"] >= O2P8_FAILS AND pg["nfailrow"] = 0 { SET pg["nfailrow"] TO 1. o2qSay("PEG 8: " + pg["why"]:TOUPPER + ": BACKUP SW PEG 7", "Y"). }
    }
    LOCAL aAv IS av:MAG / ms.
    LOCAL why IS o2pEnd(pg, now, aAv, o2qB["tb"]).
    IF o2qB["eng"]:LENGTH = 0 { SET why TO "OMS". }   // both out: the burn ends, the dV left
    IF why = "" AND o2qB["cutreq"] { SET why TO "CREW". }
    IF why = "" {
        LOCAL tpr IS o2pTaper(pg).               // O2P_TAPER_S, or 12 physics ticks when the ticks are slow (the engines answer ~3 ticks late)
        SET o2qThr TO o2pThr(o2pAlong(pg), aAv, tpr).
        IF tpr > O2P_TAPER_S + 0.001 AND NOT o2qB:HASKEY("tapl") {
            SET o2qB["tapl"] TO TRUE.
            o2qLogLine("BURN TAPER stretched to " + ROUND(tpr, 2) + " s (the physics tick " + ROUND(pg["dtm"], 3) + " s: the engines answer ~3 ticks late, so the cut waits for a slower taper)").
        }
        IF o2qThr = 0 { SET why TO "CUT". }
    }
    LOCAL tl IS fv.
    IF tl:MAG < 0.01 { SET tl TO av. }
    IF tl:MAG < 0.01 { SET tl TO SHIP:FACING:FOREVECTOR. }
    IF NOT o2qB["scalar"] {                  // The steering's line = the trim (body-fixed, no gimbal deflection, no lag: lib_o2line
        LOCAL pa IS av.                      // o2lSteer); the count above saw the measured force. Without the addon: the part axes
        IF pa:MAG < 0.01 { SET pa TO SHIP:FACING:FOREVECTOR. }
        SET tl TO o2lSteer(o2lUids(o2qB["eng"]), pa).   // the engines left after the RM (one out: its partner's trim)
    }
    SET o2qLineT TO now.
    IF ol["ok"] AND NOT o2qB:HASKEY("pchk") AND now - o2qB["t0"] > 2 {   // once, the thrust steady: the trim line against the measured
        SET o2qB["pchk"] TO TRUE.
        LOCAL op IS o2lGet(ul, "trim").
        IF op["ok"] {
            LOCAL dd IS o2lAng(op["f"], ol["f"]).
            o2qLogLine("OMS LINE PRED-MEAS " + ROUND(dd, 2) + " DEG" + (CHOOSE " (OVER " + O2L_PRED_DEG + ")" IF dd > O2L_PRED_DEG ELSE "")).
            IF o2lBit(op["flags"], 2) { o2qLogLine("OMS TRIM CLAMPED TO THE GIMBAL RANGE"). }
        }
    }
    LOCAL tlb IS tl.                         // The steering line with the early bias (O2Q_FFO), until the freeze
    IF O2Q_FFO AND NOT gdl AND NOT o2qB["scalar"] AND NOT o2qB:HASKEY("frz") { SET tlb TO o2qFfo(o2qB, ol, tl, now, o2qB["eng"]:LENGTH). }
    LOCAL frzV IS O2Q_AIM_FREEZE_V.
    LOCAL frzM IS FALSE.                     // The freeze puts the thrust line the engines GAVE on the direction (the measured line, trusted)
    IF O2Q_FRZ_MEAS AND ol["ok"] AND NOT gdl AND NOT o2qB["scalar"] AND NOT o2qB:HASKEY("frz") {
        IF o2lAng(ol["f"], o2pDir(pg)) <= O2Q_FRZ_MEAS_MAX { SET frzM TO TRUE. SET frzV TO O2Q_FRZ_MEAS_V. }
    }
    IF NOT o2qB:HASKEY("frz") AND o2pAlong(pg) < frzV {      // The aim stops here
        SET o2qB["frz"] TO TRUE.
        o2qLogLine("AIM FROZEN at " + ROUND(o2pAlong(pg), 1) + " m/s left (the DAP holds the attitude to the cut; error to the aim now " + ROUND(o2qAimErr(), 2) + " deg)").
        SET o2qB["fzd"] TO o2pDir(pg).         // The csv's tl_fz = the measured line's angle off this frozen direction
        IF frzM {
            LOCAL dirF IS o2pDir(pg).
            o2qAimTv(dirF, ol["f"]).
            o2qLogLine("AIM CORRECTED to the measured thrust line: it was " + ROUND(o2lAng(ol["f"], dirF), 2) + " deg off the steering (the trim line " + ROUND(o2lAng(tl, dirF), 2) + " deg), the DAP turns the attitude by that to the cut").
        }
    }
    IF NOT o2qB:HASKEY("frz") AND NOT gdl { o2qAimTv(o2pDir(pg), tlb). }   // Held under SW 02
    SET o2qB["n"] TO o2qB["n"] + 1.
    IF why <> "" {
        IF gdl { o2qLogLine("CUTOFF BY PLAN (GUIDANCE LOST): " + why + ", sensed " + ROUND(pg["sens"]:MAG, 3) + " of " + ROUND(pg["tot"], 3) + " m/s, VGO along " + ROUND(o2pAlong(pg), 3)). }
        SET o2qThr TO 0.
        SET o2qB["why"] TO why.
        SET o2qB["tcut"] TO now.
        o2qGmEnd(why).                       // The mode 0: the jets are the DAP's again
        SET o2qBurnOn TO FALSE.
        o2qBurnRow().
        RETURN.
    }
    IF MOD(o2qB["n"], O2Q_LOG_TICKS) = 0 { o2qBurnRow(). }
}

FUNCTION o2qSafe {                           // the controls back: throttle 0, the forward point, the DAP holding INRTL
    SET o2qThr TO 0.                         // (without it: RCS off, SAS on)
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    UNLOCK THROTTLE.
    IF O2Q_KOS_STEER { UNLOCK STEERING. }
    IF o2qB["ag6"] { TOGGLE AG7. SET o2qAg7 TO AG7. SET o2qB["ag6"] TO FALSE. SET o2qCtrl TO "FWD". SET o2Val["ctrl"] TO 0. }   // own toggle, not a press (the readout follows)
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {   // a single-engine burn's other engine: relit
        IF o2qOmsOff[k] {
            SET o2qOmsOff[k] TO FALSE.
            LOCAL en IS o2qOmsEng(k).
            IF o2qOut[k] = "" AND o2qIsEng(en) { en:ACTIVATE(). o2qLogLine("OMS " + LIST("L", "R")[k] + " RELIT (THE SINGLE BURN OVER)"). }
        }
    }
    IF o2qDapOk { o2qDapResume("AFTER THE BURN"). }
    ELSE IF O2Q_KOS_STEER { RCS OFF. SAS ON. }
}

FUNCTION o2qSeqStop {                        // CUT OFF before TIG: the sequence ends, nothing burnt
    SET o2qBurnOn TO FALSE.
    IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
    o2qRailsPoll().
    o2qRailsOff().
    IF o2qSeq <> "WARP" { o2qSafe(). }
    ELSE IF o2qDapOk { o2qDapResume("SEQUENCE STOPPED"). }
    o2qLogLine("SEQ STOPPED in " + o2qSeq).
    SET o2qSeq TO "".
}

FUNCTION o2qSeqEnd {                         // after the burn: safe, the residuals, the next programs' steps
    o2qRailsPoll().
    o2qRailsOff().
    o2qSafe().
    LOCAL pg IS o2qB["peg"].
    LOCAL why IS o2qB["why"].
    o2qStateLog("cut").
    o2qLogLine("TV ROLL at the cut: " + ROUND(o2qTvMeas, 1) + " deg about the thrust line (entry " + ROUND(o2Val["tvr"], 1) + ", the vertical at the ignition)").
    IF why = "CUT" AND o2qB["node"] >= 0 AND o2flLive(o2qB["node"]) { o2flFly(o2qB["node"]). o2qFpPersist(). }   // a burn flown: its siblings dropped, its children move up
    LOCAL dn IS pg["sens"]:MAG.
    LOCAL lf IS pg["vgo"]:MAG.
    o2qLogLine("BURN END " + why + ": sensed " + ROUND(dn, 3) + " of " + ROUND(pg["tot"], 3) + " m/s in "
        + ROUND(o2qB["tcut"] - o2qB["t0"], 2) + " s, VGO left " + ROUND(lf, 3) + " m/s (along " + ROUND(o2pAlong(pg), 3)
        + "), the count " + (CHOOSE "scalar" IF o2qB["scalar"] ELSE "along the engines' axes")).
    IF DEFINED CW_VER { cwResidual(o2qCwGd, lf, pg["tot"], why). }       // GUID CAUTION when the cutoff left more than the limit
    IF pg:HASKEY("rt") {
        LOCAL ms IS o2p4Miss(o2qRv(), SHIP:VELOCITY:ORBIT, pg["rt"], pg["c1"], pg["c2"], pg["gv"]).
        o2qLogLine("PEG 4 at the cut: the coast" + (CHOOSE " (J2)" IF pg["gv"]["j2"] <> 0 ELSE "") + " meets the target "
            + ROUND(ms[0] / 1000, 3) + " km along, the flight path angle " + ROUND(ms[1], 5) + " deg off the line"
            + (CHOOSE "" IF ms[2] ELSE " (NO CROSSING)") + "; VGO re-solved " + pg["nres"] + " ticks, the J2 aim "
            + pg["naim"] + " steps, offsets " + ROUND(pg["aoff"], 5) + " / " + ROUND(pg["goff"], 5) + " deg").
    }
    IF pg:HASKEY("p8") AND pg["p8"] AND pg:HASKEY("ntry") {     // How many of the burn's shots failed, and the first why (the shots' results were not logged)
        o2qLogLine("PEG 8 SHOTS: " + pg["nfailtot"] + " of " + pg["ntry"] + " failed" + (CHOOSE " (first: " + pg["wfirst"] + ")" IF pg["nfailtot"] > 0 ELSE "")).
    }
    IF pg:HASKEY("p8") AND pg["p8"] {        // the cut's own miss at the aim: one shot from the cut state, its misscut (the coast of that state as it stands)
        LOCAL fs IS o2p8Shot(pg, TIME:SECONDS, o2qRv(), SHIP:VELOCITY:ORBIT, TIME:SECONDS, V(0, 0, 0)).
        IF fs:HASKEY("misscut") {
            SET pg["miss"] TO fs["misscut"].
            o2qLogLine("PEG 8 at the cut: the n-body coast meets the aim " + ROUND(fs["misscut"] / 1000, 3) + " km off (the planned dV as an impulse from the last state before the ignition would have missed by " + ROUND(pg["missP"] / 1000, 3) + " km); " + pg["nres"] + " shots").
            o2qSay("PEG 8: AIM MISS " + o2F(fs["misscut"] / 1000, 1, 2) + " KM (IMPULSE PLAN: " + o2F(pg["missP"] / 1000, 1, 2) + " KM)", "V").
        } ELSE { SET pg["miss"] TO 0. o2qLogLine("PEG 8 at the cut: no miss (" + fs["why"] + ")"). }
    }
    o2bPut("CUT", o2qB["bk"], TIME:SECONDS, dn, pg["tot"], why).    // the burn is flown (a re-RUN does not load its plan again)
    SET o2qRes TO LEXICON("peg", pg, "why", why, "tree", o2qB["tree"], "type", o2qB["type"], "ea", o2qB["ea"]).   // the page shows the finished burn read only
    SET o2qSeq TO "".
    SET o2qLoad TO LEXICON().
    IF why = "CUT" { o2qSay("CUTOFF: " + o2F(dn, 1, 1) + " M/S, VGO LEFT " + o2F(lf, 1, 2), "V"). }
    ELSE IF why = "CREW" { o2qSay("CUT OFF BY CREW: VGO LEFT " + o2F(lf, 1, 1) + " M/S", "Y"). }
    ELSE IF why = "THRUST" { o2qSay("THRUST LOST: VGO LEFT " + o2F(lf, 1, 1) + " M/S", "R"). }
    ELSE IF why = "OMS" { o2qSay("BOTH OMS OUT: " + o2F(lf, 1, 1) + " M/S LEFT (RCS +X BY HAND)", "R"). }
    ELSE { o2qSay("TIME GUARD CUTOFF: VGO LEFT " + o2F(lf, 1, 1) + " M/S", "Y"). }
    LOCAL tg IS o2qB["tag"].
    LOCAL rw IS CHOOSE o2qB["d"]["runway"] IF o2qB["d"]:HASKEY("runway") ELSE "none".
    IF tg = "ATO OMS-1" { o2qAtoNext(). }
    IF tg = "ATO OMS-2" OR tg = "AOA OMS-2" { o2qAtoEnd(). }
    IF o2qOps3Rule(tg, o2qB["dv"][0], rw) { SET o2qOps3 TO TRUE. }   // the deorbit burn (a deorbit or the AOA's OMS-2)
    o2qReadSrc().
}

// the payload bay doors closed (shuttle_exec exCloseBay): the event "close" exists only while the bay is open
FUNCTION o2qCloseBay {
    LOCAL n IS 0.
    FOR bp IN SHIP:PARTSNAMED("benjee10.shuttle.midFuselage") {
        LOCAL anim IS bp:GETMODULE("ModuleAnimateGeneric").
        IF anim:HASEVENT("close") { anim:DOEVENT("close"). }
        SET n TO n + 1.
    }
    IF n = 0 { o2qSay("BAY PART NOT FOUND: CLOSE THE DOORS BY HAND", "Y"). RETURN. }
    o2qLogLine("BAY CLOSE sent (" + n + " part)").
}
FUNCTION o2qUnlockGimbals {                  // the OMS gimbals unlocked (AG2 locks them); how many were locked
    LOCAL n IS 0.
    FOR en IN o2qOmsAll() {
        IF en:HASGIMBAL { IF en:GIMBAL:LOCK AND NOT flfxGlk(en) { SET en:GIMBAL:LOCK TO FALSE. SET n TO n + 1. } }   // Not one a failure holds locked (OMS 03)
    }
    RETURN n.
}

// ---- the logs: the state (shuttle_exec exStateCols) and the burn log (its burn_<UT>.csv columns, then VGO)
FUNCTION o2qStateCols {
    LOCAL rs IS V(0, 0, 0) - SHIP:BODY:POSITION.
    LOCAL vs IS SHIP:VELOCITY:ORBIT.
    LOCAL ob IS SHIP:ORBIT.
    RETURN ROUND(rs:MAG, 1) + "," + ROUND(VDOT(vs, rs:NORMALIZED), 4) + "," + ROUND(VXCL(rs, vs):MAG, 4)
        + "," + ROUND(ob:SEMIMAJORAXIS, 1) + "," + ROUND(ob:ECCENTRICITY, 7) + "," + ROUND(ob:INCLINATION, 5)
        + "," + ROUND(ob:LAN, 5) + "," + ROUND(ob:ARGUMENTOFPERIAPSIS, 4) + "," + ROUND(ob:TRUEANOMALY, 4)
        + "," + ROUND(ob:APOAPSIS, 1) + "," + ROUND(ob:PERIAPSIS, 1) + "," + ROUND(ob:PERIOD, 3).
}
FUNCTION o2qStateLog {
    PARAMETER tag.
    o2qLogLine("state " + tag + " (UT " + ROUND(TIME:SECONDS, 3) + ", mass " + ROUND(SHIP:MASS, 4) + " t, RCS "
        + (CHOOSE "on" IF RCS ELSE "off") + "): " + O2Q_STATE_HEAD + " = " + o2qStateCols()).
}
FUNCTION o2qBurnLogStart {
    SET o2qBurnLog TO "".
    IF NOT SOCK_LOG { RETURN. }
    LOCAL bb IS "0:/logs/o2burn_" + ROUND(TIME:SECONDS).
    SET o2qBurnLog TO bb + ".csv".
    LOCAL bn IS 1.
    UNTIL NOT EXISTS(o2qBurnLog) { SET bn TO bn + 1. SET o2qBurnLog TO bb + "_" + bn + ".csv". }
    LOCAL rp IS SHIP:ROOTPART:FACING.
    LOCAL dv IS o2qB["dv"].
    LOG "# " + SCRIPT_VERSION + "; UT " + ROUND(TIME:SECONDS, 2) + "; OMS engines " + o2qB["eng"]:LENGTH
        + "; mode " + o2qB["gn"] + " (dv " + ROUND(o2qB["peg"]["tot"], 4) + " as LVLH " + ROUND(dv[0], 4) + " / " + ROUND(dv[1], 4)
        + " / " + ROUND(dv[2], 4) + " at the centre UT " + ROUND(o2qB["ig"] + o2qB["tb"] / 2, 3) + ", TIG UT "
        + ROUND(o2qB["ig"], 3) + "; source " + o2qB["src"] + "; dv_left = VGO along the steering, sensed from the thrust)"
        + "; attitude " + (CHOOSE "kOS steering (O2Q_KOS_STEER)" IF O2Q_KOS_STEER ELSE "our DAP (T638): st_* its jet commands, err_* its attitude error")
        + "; thrust line " + (CHOOSE "steering on the trim line (OMSLINE, T644)" IF o2lHave() ELSE "part axes (no OMSLINE)")
        + "; the control frame vs the root part: fore " + ROUND(VANG(SHIP:FACING:FOREVECTOR, rp:FOREVECTOR), 3)
        + " deg off the nose axis, top . root top " + ROUND(VDOT(SHIP:FACING:TOPVECTOR, rp:TOPVECTOR), 4)
        + ", top . root fore " + ROUND(VDOT(SHIP:FACING:TOPVECTOR, rp:FOREVECTOR), 4)
        + "; taper " + O2P_TAPER_DT_K + " ticks (T795)"
        + "; aim bias " + (CHOOSE "on (T795b: the measured line's offset from the trim line over " + O2Q_FFO_T0 + " .. " + O2Q_FFO_T1 + " s is carried in the aim; tl_fz = the measured line off the frozen aim direction)" IF O2Q_FFO ELSE "off")
        + "; gimbal mode " + o2qGmMode + " (T789; 0 jets fly, 1 RCS off from 80 % thrust, 2 roll jets only; the rcs column is the RCS group)" TO o2qBurnLog.
    LOG "t,dv_left,throttle,thrust_oms,mass,g1_p,g1_y,g1_r,g1_lock,g2_p,g2_y,g2_r,g2_lock,st_p,st_y,st_r,err_p,err_y,err_ang,"
        + "rate_p,rate_y,rate_r,vang_burn,rcs,node_dv,a_ret,a_sum," + O2Q_STATE_HEAD + ",vgo_x,vgo_y,vgo_z,vgo,thrust_l,thrust_r,"
        + "out_l,out_r,tl_off,tl_p,tl_y,tl_src,tl_fz" TO o2qBurnLog.
}
FUNCTION o2qFfo {                            // The steering line with the early bias: tl (the trim line) rotated in the BODY by the measured line's mean offset from it over O2Q_FFO_T0 .. T1 s
    PARAMETER b, ol, tl, now, ne.            // b = o2qB, ol = the measured line (o2lGet), tl = the trim line, ne = the engines lit
    LOCAL fc IS SHIP:FACING.
    IF NOT b:HASKEY("ffn") { SET b["ffn"] TO 0. SET b["ffp"] TO 0. SET b["ffy"] TO 0. SET b["ffe"] TO ne. }
    IF b["ffe"] <> ne {                      // an engine out / back: the offset belongs to the engines it was measured on: no bias from here
        IF b:HASKEY("ffo") { o2qLogLine("AIM BIAS DROPPED: the engines lit changed " + b["ffe"] + " -> " + ne + " (the offset was measured on the others)"). }
        SET b["ffe"] TO ne.
        SET b["ffo"] TO LIST(0, 0).
        SET b["ffx"] TO TRUE.
    }
    LOCAL dt IS now - b["t0"].
    IF NOT b:HASKEY("ffo") AND NOT b:HASKEY("ffx") {
        IF dt >= O2Q_FFO_T0 AND dt <= O2Q_FFO_T1 {
            IF ol["ok"] {
                LOCAL pm IS o2lPY(ol["f"], fc:FOREVECTOR, fc:STARVECTOR, fc:TOPVECTOR).
                LOCAL pt IS o2lPY(tl, fc:FOREVECTOR, fc:STARVECTOR, fc:TOPVECTOR).
                SET b["ffp"] TO b["ffp"] + pm[0] - pt[0].
                SET b["ffy"] TO b["ffy"] + pm[1] - pt[1].
                SET b["ffn"] TO b["ffn"] + 1.
            }
        } ELSE IF dt > O2Q_FFO_T1 {
            LOCAL n IS b["ffn"].
            IF n >= O2Q_FFO_N {
                LOCAL dp IS b["ffp"] / n.
                LOCAL dy IS b["ffy"] / n.
                LOCAL mg IS SQRT(dp * dp + dy * dy).
                IF mg <= O2Q_FRZ_MEAS_MAX {
                    SET b["ffo"] TO LIST(dp, dy).
                    o2qLogLine("AIM BIAS: the measured thrust line was " + ROUND(dp, 2) + " deg in pitch (below fore) / " + ROUND(dy, 2) + " deg in yaw (to the star side) off the trim line (" + n + " samples over " + O2Q_FFO_T0 + " .. " + O2Q_FFO_T1 + " s): the aim carries it from here").
                } ELSE {
                    SET b["ffo"] TO LIST(0, 0).
                    o2qLogLine("AIM BIAS NOT USED: the measured line is " + ROUND(mg, 2) + " deg off the trim line (over " + O2Q_FRZ_MEAS_MAX + ")").
                }
            } ELSE {
                SET b["ffo"] TO LIST(0, 0).
                o2qLogLine("AIM BIAS NOT USED: " + n + " samples of the measured line (need " + O2Q_FFO_N + ")").
            }
        }
    }
    IF b:HASKEY("ffo") {
        LOCAL ff IS b["ffo"].
        IF ff[0] <> 0 OR ff[1] <> 0 {
            LOCAL ps IS o2lPY(tl, fc:FOREVECTOR, fc:STARVECTOR, fc:TOPVECTOR).     // the same body angles + the offset: pitch below fore p, yaw to the star y
            RETURN (fc:FOREVECTOR - fc:TOPVECTOR * TAN(ps[0] + ff[0]) + fc:STARVECTOR * TAN(ps[1] + ff[1])):NORMALIZED.
        }
    }
    RETURN tl.
}
FUNCTION o2qBurnRow {                        // one row (the trigger's, every O2Q_LOG_TICKS ticks and at the end)
    IF o2qBurnLog = "" { RETURN. }
    LOCAL pg IS o2qB["peg"].
    LOCAL row IS ROUND(TIME:SECONDS, 3) + "," + ROUND(o2pAlong(pg), 3) + "," + ROUND(o2qThr, 3).
    LOCAL fs IS 0.
    LOCAL fv IS V(0, 0, 0).
    FOR en IN o2qB["eng"] { SET fs TO fs + en:THRUST. SET fv TO fv + en:FACING:FOREVECTOR * en:THRUST. }
    SET row TO row + "," + ROUND(fs, 3) + "," + ROUND(SHIP:MASS, 4).
    FROM { LOCAL i IS 0. } UNTIL i >= 2 STEP { SET i TO i + 1. } DO {
        LOCAL ge IS o2qOmsEng(i).            // g1 = L, g2 = R
        IF o2qIsEng(ge) AND ge:HASGIMBAL {
            LOCAL g IS ge:GIMBAL.
            SET row TO row + "," + ROUND(g:PITCHANGLE, 4) + "," + ROUND(g:YAWANGLE, 4) + "," + ROUND(g:ROLLANGLE, 4)
                + "," + (CHOOSE 1 IF g:LOCK ELSE 0).
        } ELSE { SET row TO row + ",,,,". }
    }
    LOCAL w IS SHIP:ANGULARVEL * CONSTANT:RADTODEG.
    SET row TO row + "," + o2qSteerCols()
        + "," + ROUND(VDOT(w, SHIP:FACING:STARVECTOR), 4) + "," + ROUND(VDOT(w, SHIP:FACING:TOPVECTOR), 4)
        + "," + ROUND(VDOT(w, SHIP:FACING:FOREVECTOR), 4) + "," + ROUND(o2qAimErr(), 3)
        + "," + (CHOOSE 1 IF RCS ELSE 0).
    LOCAL gb IS o2qInBody(pg["vgo"]).
    SET row TO row + ",," + ROUND(VDOT(fv, o2pDir(pg)) / SHIP:MASS, 4) + "," + ROUND(fs / SHIP:MASS, 4)
        + "," + o2qStateCols() + "," + ROUND(gb[0], 3) + "," + ROUND(gb[1], 3) + "," + ROUND(gb[2], 3)
        + "," + ROUND(pg["vgo"]:MAG, 3).
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL en IS o2qOmsEng(k).
        SET row TO row + "," + (CHOOSE ROUND(en:THRUST, 3) IF o2qIsEng(en) ELSE "").
    }
    SET row TO row + "," + o2qOut[0] + "," + o2qOut[1].
    LOCAL tq IS o2lGet(o2lUids(o2qB["eng"]), "meas").   // the thrust line (OMSLINE): its angle off the steering, its pitch below / yaw to the star side of fore; tl_src 1 = measured, 0 = none
    IF tq["ok"] {
        LOCAL pyl IS o2lPY(tq["f"], SHIP:FACING:FOREVECTOR, SHIP:FACING:STARVECTOR, SHIP:FACING:TOPVECTOR).
        SET row TO row + "," + ROUND(o2lAng(tq["f"], o2pDir(pg)), 3) + "," + ROUND(pyl[0], 3) + "," + ROUND(pyl[1], 3) + ",1"
            + "," + (CHOOSE ROUND(o2lAng(tq["f"], o2qB["fzd"]), 3) IF o2qB:HASKEY("fzd") ELSE "").
    } ELSE { SET row TO row + ",,,,0,". }
    LOG row TO o2qBurnLog.
}

// ---- after the burn (shuttle_exec's): the ATO / AOA choice and OMS-2 plan after an ATO's OMS-1 (exAtoNext)
FUNCTION o2qOps3Rule {                       // this burn hands over to OPS3: a deorbit (no tag, retrograde, a runway) or the AOA's OMS-2
    PARAMETER tg, dvx, rw.
    RETURN (tg = "" AND dvx < 0 AND rw <> "none" AND rw <> "") OR tg = "AOA OMS-2".
}

FUNCTION o2qAtoNext {                        // after OMS-1: the hand-off's page re-asks the real orbit; without a hand-off the old window
    IF o2qAto["on"] { o2qAtoOms1Done(). RETURN. }
    o2qAtoAsk().
}
FUNCTION o2qAtoAsk {                         // ATO ("the ATO_H circle") or AOA -> OMS-2, aoaAsk's window (no ops1q hand-off to ask from)
    IF NOT EXISTS("0:/lib/lib_ascent_iload.ks") { o2qSay("ATO: NO LIB_ASCENT_ILOAD: NO OMS-2 PLAN", "Y"). RETURN. }
    RUNONCEPATH("0:/lib/lib_ascent_iload.ks").
    LOCAL a IS omsAto().
    IF a:LENGTH = 0 { o2qSay("ATO: NO APOAPSIS AHEAD AFTER OMS-1: NO OMS-2 PLAN", "Y"). RETURN. }
    LOCAL d IS o2qB["d"].
    LOCAL sn IS CHOOSE d["site"] IF d:HASKEY("site") ELSE "".   // the launch site (a VBG ATO's AOA solves for VBG)
    FOR st IN ASC_SITES { IF st["rtls"]["name"] = sn { SET ASC_RTLS_SITE TO st["rtls"]. } }
    LOCAL md IS "ATO".
    IF EXISTS("0:/lib/lib_aoa.ks") {
        RUNONCEPATH("0:/lib/lib_aoa.ks").
        o2DispHide().
        SET md TO aoaAsk(LEXICON("dv_ato", ABS(a[2]), "dv_keep", ASC_ATO_DV_DEORBIT, "dv_oms", omsDvOnBoard(),
            "dv_onorb", ASC_OMS_ONORB, "dv_emerg", ASC_OMS_EMERG)).
        o2DispShow().
    }
    IF md = "AOA" {
        IF aoaPlanOms2() { o2qSay("AOA OMS-2 PLANNED DV " + o2F(ABS(AOA_SOL["dvt"]), 1, 1) + " M/S", "V"). }
        ELSE { o2qSay("AOA OMS-2 PLAN FAILED", "R"). }
    } ELSE {
        omsPlanAto("0:/oms2_plan.txt").
        o2qSay("ATO OMS-2 PLANNED DV " + o2F(ABS(a[2]), 1, 1) + " M/S", "V").
    }
    o2qLogLine("N11 after the ATO's OMS-1: " + md).
    o2qReadSrc().
    FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH STEP { SET i TO i + 1. } DO {
        IF o2qSrc[i]["file"] = "0:/oms2_plan.txt" AND NOT o2qLoaded() { o2qLoadSrc(i). }
    }
}

FUNCTION o2qOps3Go {                         // the OPS3 item: ops2q ends and runs ops3q (the entry)
    IF NOT o2qOps3 { o2qSay("DEORBIT BURN NOT FLOWN", "Y"). RETURN. }
    IF o2qSeq <> "" { o2qSay("BURN SEQUENCE RUNNING", "Y"). RETURN. }
    IF NOT EXISTS("0:/ops3q.ks") { o2qSay("OPS3: OPS3Q.KS IS NOT INSTALLED", "R"). RETURN. }
    SET o2qNext TO "ops3q".
    SET o2qQuit TO TRUE.
    o2qLogLine("OPS3: ops2q ends, ops3q runs").
}

FUNCTION o2qRhcKey {                         // the stick's key now ("" = in its detent)
    LOCAL c IS o2qStick().
    LOCAL k IS "".
    IF c:X > O2Q_RHC_ON { SET k TO "DN". }                   // S: the stick back (pitch up) = down? W = up
    ELSE IF c:X < -O2Q_RHC_ON { SET k TO "UP". }
    ELSE IF c:Z < -O2Q_RHC_ON { SET k TO "LF". }
    ELSE IF c:Z > O2Q_RHC_ON { SET k TO "RT". }
    ELSE IF c:Y < -O2Q_RHC_ON { SET k TO "MI". }              // Q (roll left) = -   (E is +, Q is -)
    ELSE IF c:Y > O2Q_RHC_ON { SET k TO "PL". }               // E (roll right) = +
    RETURN k.
}
FUNCTION o2qRhc {                            // INPUT RHC: the stick's deflections as keys (held: repeated)
    IF o2qInEff() <> "RHC" OR o2Typ { SET o2qRhcK TO "". RETURN. }
    LOCAL k IS o2qRhcKey().
    IF k = "" { SET o2qRhcK TO "". RETURN. }
    IF k <> o2qRhcK OR TIME:SECONDS >= o2qRhcT {
        SET o2qRhcT TO TIME:SECONDS + (CHOOSE 0.8 IF k <> o2qRhcK ELSE O2Q_RHC_REP).
        SET o2qRhcK TO k.
        o2qLogLine("RHC KEY " + k).          // each stick key in the log
        o2qKey(k).
    }
}

// ---- the keyboard: KalsCoproc holds KSP's keys off the ship and reads the ones ops2q wants
FUNCTION o2qKeysStart {                      // at RUN
    SET o2qKeysOk TO o2qFbwHas("KEYLOCK") AND o2qFbwHas("KEYS").
    IF o2qKeysOk { o2qLogLine("KEYS: KalsCoproc keyboard (staging locked, Space = ENT; TYPE locks every key)"). }
    ELSE { o2qSay("KEYBOARD N/A: NO KALSCOPROC KEYLOCK", "Y"). }
}
// kOS's Button keeps
// Unity's keyboard focus after a click (GUI.FocusControl), and Unity's IMGUI presses the focused control on Space / Enter.
// So Space was ENT (KalsKeys) AND a press of the window button clicked last: the DEORB page button closed the list again,
// the grid's ENT selected and reopened it. That echo reaches kOS in the cycle of KalsKeys' ENT (its onclick runs on the
// next kOS update), or the cycle after: the presses of those cycles are dropped (logged); the presses come first as before.
FUNCTION o2qKeys {                           // each cycle: the window's presses, the keys read since the last, then the mode for the next
    PARAMETER prs IS LIST().
    LOCAL ks IS LIST().
    IF o2qKeysOk {
        FOR k IN o2qKeyBuf { ks:ADD(k). }       // read while the loop waited
        o2qKeyBuf:CLEAR().
        FOR k IN ADDONS:KALS:KEYS { ks:ADD(k). }
    }
    IF NOT gpcLive(gpcPageDisp(o2qPage)) {     // A dead / frozen display takes no input (the page keys still switch the page)
        SET ks TO LIST().
        LOCAL pn IS LIST().
        FOR tg IN prs { IF tg:STARTSWITH("N") { pn:ADD(tg). } }
        SET prs TO pn.
    }
    LOCAL ent IS ks:CONTAINS("ENT").
    IF prs:LENGTH > 0 AND (ent OR (o2qEntCyc AND TIME:SECONDS - o2qEntT < 0.3)) {
        o2qLogLine("PRESS " + prs:JOIN(" ") + " DROPPED (the Space / Enter echo of the button clicked last)").
    } ELSE { FOR tg IN prs { o2qPress(tg). } }
    SET o2qEntCyc TO ent.
    IF ent { SET o2qEntT TO TIME:SECONDS. }
    FOR k IN ks { o2qKey(k). }
    IF NOT o2qKeysOk { RETURN. }
    LOCAL km IS ADDONS:KALS:KEYLOCK(CHOOSE "TYPE" IF o2Typ ELSE "STAGE").
    IF km:STARTSWITH("ERROR") {
        SET o2qKeysOk TO FALSE.
        o2qSay("KEYBOARD OFF: " + km, "Y").
        o2qLogLine("KEYS OFF: " + km).
        RETURN.
    }
    IF km <> o2qKeyMode { SET o2qKeyMode TO km. o2qLogLine("KEYS " + km). }
}
FUNCTION o2qKeysEnd {                        // at the end: the locks dropped at once
    IF o2qKeysOk { ADDONS:KALS:KEYLOCK("OFF"). }
}

FUNCTION o2qAg4Type {                           // AG4 = the grid's TYPE button, in every state (ENT is Space, through KalsKeys)
    IF AG4 <> o2qAg4 {
        SET o2qAg4 TO AG4.
        o2qKey("TYPE").
    }
}

// ---- AG6 / AG7 pressed by the pilot: CTRL FRM follows (AG6 = OMS, AG7 = FWD). kOS cannot read the control point, but it
// reads the groups' states: a change of one that ops2q's own toggles (o2qCtrlSet, the burn's start and end) did not make is a press.
// In a burn the display follows the press too (the real point) with a warning; ops2q does not switch it back.
FUNCTION o2qAgCtrl {
    LOCAL a6 IS AG6.
    LOCAL a7 IS AG7.
    IF a6 <> o2qAg6 { SET o2qAg6 TO a6. o2qCtrlPress("OMS", "AG6"). }
    IF a7 <> o2qAg7 { SET o2qAg7 TO a7. o2qCtrlPress("FWD", "AG7"). }
}
FUNCTION o2qCtrlPress {
    PARAMETER nm, agn.
    SET o2qCtrl TO nm.
    SET o2Val["ctrl"] TO CHOOSE 1 IF nm = "OMS" ELSE 0.
    IF o2qSeq <> "" AND nm <> "OMS" { o2qSay("CTRL FRM " + nm + " IN BURN (" + agn + ")", "Y"). }
    ELSE { o2qSay("CTRL FRM " + nm + " (" + agn + ")", "V"). }
    o2qLogLine("CTRL FRM " + nm + " (" + agn + " PRESSED" + (CHOOSE " IN THE BURN" IF o2qSeq <> "" ELSE "") + ")").
}

// ---- the OMS RM: ONE entry for every OMS failure, outside or our own
FUNCTION o2qKNames {                         // engines k as their letters: "L R", "L", "NONE"
    PARAMETER ks.
    LOCAL t IS "".
    FOR k IN ks { SET t TO t + (CHOOSE " " IF t <> "" ELSE "") + LIST("L", "R")[k]. }
    RETURN CHOOSE t IF t <> "" ELSE "NONE".
}
FUNCTION o2qOmsInit {                        // at RUN: L and R by position, the ones out (1:/oms_out.txt), each kept shut
    LOCAL ens IS o2qOmsFind().
    FROM { LOCAL k IS 0. } UNTIL k >= MIN(2, ens:LENGTH) STEP { SET k TO k + 1. } DO { SET o2qOid[k] TO ens[k]:UID. }
    IF EXISTS(O2Q_OMS_FILE) {
        FOR ln0 IN OPEN(O2Q_OMS_FILE):READALL:STRING:SPLIT(CHAR(10)) {
            LOCAL f IS ln0:TRIM:SPLIT(",").
            IF f:LENGTH >= 3 {
                LOCAL k IS f[0]:TONUMBER(-1).
                IF k >= 0 AND k <= 1 AND (o2qOid[k] = f[2] OR o2qOid[k] = "") { SET o2qOut[k] TO f[1]. }
            }
        }
    }
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL en IS o2qOmsEng(k).
        IF o2qOut[k] <> "" {
            IF o2qIsEng(en) AND en:IGNITION { en:SHUTDOWN(). }
        } ELSE IF o2qIsEng(en) { SET o2qOn[k] TO en:IGNITION. }
    }
    o2qOmsSelFix().
    o2qLogLine("OMS RM: L " + (CHOOSE o2qOid[0] IF o2qOid[0] <> "" ELSE "none") + " " + (CHOOSE "OUT " + o2qOut[0] IF o2qOut[0] <> ""
        ELSE (CHOOSE "lit" IF o2qOn[0] ELSE "unlit")) + ", R " + (CHOOSE o2qOid[1] IF o2qOid[1] <> "" ELSE "none") + " "
        + (CHOOSE "OUT " + o2qOut[1] IF o2qOut[1] <> "" ELSE (CHOOSE "lit" IF o2qOn[1] ELSE "unlit"))).
    IF o2qOut[0] <> "" OR o2qOut[1] <> "" {
        o2qSay(CHOOSE "BOTH OMS OUT" IF o2qOut[0] <> "" AND o2qOut[1] <> ""
            ELSE "SINGLE OMS BURN", "Y").
    }
}
FUNCTION o2qOmsSave {                        // the engines out, to the vessel's volume
    IF EXISTS(O2Q_OMS_FILE) { DELETEPATH(O2Q_OMS_FILE). }
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        IF o2qOut[k] <> "" { LOG k + "," + o2qOut[k] + "," + o2qOid[k] TO O2Q_OMS_FILE. }
    }
}
FUNCTION o2qOmsSelFix {                      // one engine left: MNVR EXEC's OMS on it
    IF o2qOut[0] <> "" AND o2qOut[1] = "" { SET o2Val["oms"] TO 2. }
    ELSE IF o2qOut[1] <> "" AND o2qOut[0] = "" { SET o2Val["oms"] TO 1. }
    ELSE IF o2qOut[0] <> "" AND o2qOut[1] <> "" { SET o2Val["oms"] TO 0. }
}
FUNCTION o2qOmsLight {                       // at the settle (the throttle locked at 0): the burn's engines lit, a single
    LOCAL ks IS o2qOmsK().                   // burn's other engine shut down for it
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL en IS o2qOmsEng(k).
        IF o2qIsEng(en) AND o2qOut[k] = "" {
            IF ks:CONTAINS(k) {
                IF NOT en:IGNITION { en:ACTIVATE(). o2qLogLine("OMS " + LIST("L", "R")[k] + " LIT FOR THE BURN"). }
                SET o2qOmsOff[k] TO FALSE.
            } ELSE IF en:IGNITION {
                SET o2qOmsOff[k] TO TRUE.
                SET o2qOn[k] TO FALSE.
                en:SHUTDOWN().
                o2qLogLine("OMS " + LIST("L", "R")[k] + " SHUT DOWN FOR A SINGLE-ENGINE BURN").
            }
        }
    }
}
FUNCTION o2qOmsLive {                        // the burn is lit and its trigger runs: the trigger owns the burn list then
    RETURN o2qSeq <> "" AND o2qB:HASKEY("lit") AND o2qB["lit"] AND o2qBurnOn.
}
// THE OMS INTERLOCK. The OMS is inert (KalsCoproc zeroes the vessel's final throttle, OmsHold.cs) unless a burn is
// ARMed or the burn sequence owns the engines. ADDONS:KALS:OMSHOLD(armed) is a heartbeat fed every physics tick by a trigger (a stopped
// script lets go by itself after 3 s); OMSHOLDOFF at the program's exit. No KalsCoproc / no OMSHOLD: as before (no kOS fallback).
GLOBAL o2qHoldOk IS -1.                      // ADDONS:KALS:OMSHOLD there (1) or not (0); -1 unchecked
FUNCTION o2qHoldUp {                         // the burn owns the OMS: ARMed, a sequence (EXEC .. the cut), or the burn on
    RETURN o2qArmed OR o2qSeq <> "" OR o2qBurnOn.
}
FUNCTION o2qHold {
    IF o2qQuit OR o2qHoldOk = 0 { RETURN. }
    IF o2qHoldOk < 0 {
        SET o2qHoldOk TO 0.
        IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("OMSHOLD") { SET o2qHoldOk TO 1. } }
        IF o2qHoldOk = 0 { o2qLogLine("OMS INTERLOCK: NO OMSHOLD IN KALSCOPROC (the OMS follows the pilot's throttle as before)"). RETURN. }
        o2qLogLine("OMS INTERLOCK: ON (the OMS is inert unless a burn is ARMed or running)").
    }
    ADDONS:KALS:OMSHOLD(o2qHoldUp()).
}
FUNCTION o2qHoldOff {
    IF o2qHoldOk = 1 { ADDONS:KALS:OMSHOLDOFF(). }
}
FUNCTION o2qOmsFailAny {                     // a failure from the main loop: flown at once, or by the trigger in the burn
    PARAMETER k, why.
    IF o2qOut[k] <> "" { RETURN. }
    IF o2qOmsLive() { SET o2qFailReq[k] TO why. RETURN. }
    o2qOmsFail(k, why).
}
// THE ONE ENTRY: engine k (0 L, 1 R) out for the flight, whatever the cause (why): out flag + file, shut down, out of
// the burn, L OMS FAIL first, then the consequence. Off the burn (the main loop) or in it (the trigger) only.
FUNCTION o2qOmsFail {
    PARAMETER k, why.
    IF o2qOut[k] <> "" { RETURN. }
    SET o2qOut[k] TO why.
    SET o2qFailReq[k] TO "".
    SET o2qOn[k] TO FALSE.
    SET o2qOmsOff[k] TO FALSE.
    LOCAL nm IS LIST("L", "R")[k].
    flNote("OMS 01", nm, "", "P", why).      // the FAILURES window lists it (a no-op inside its own FAIL / row / RAND: flFire recorded that one)
    LOCAL en IS o2qOmsEng(k).
    IF o2qIsEng(en) AND en:IGNITION { en:SHUTDOWN(). }
    LOCAL inSeq IS o2qSeq <> "" AND o2qB:HASKEY("ek").
    IF inSeq AND o2qB["ek"]:CONTAINS(k) {    // out of the burn's lists (the engines by k: no dead part touched)
        LOCAL ks IS LIST(). LOCAL ne IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= o2qB["ek"]:LENGTH STEP { SET i TO i + 1. } DO {
            IF o2qB["ek"][i] <> k { ks:ADD(o2qB["ek"][i]). IF i < o2qB["eng"]:LENGTH { ne:ADD(o2qB["eng"][i]). } }
        }
        SET o2qB["ek"] TO ks.
        SET o2qB["eng"] TO ne.
    }
    o2qOmsSelFix().
    o2qOmsSave().
    o2qSay(nm + " OMS FAIL", "R").           // the failure first, its consequence above it
    LOCAL met IS MISSIONTIME.
    LOCAL lit IS inSeq AND o2qB["lit"].
    o2qLogLine("#omseo," + ROUND(TIME:SECONDS, 2) + "," + ROUND(met, 2) + "," + nm + "," + why + "," + (CHOOSE "BURN T+"
        + ROUND(TIME:SECONDS - o2qB["t0"], 2) IF lit ELSE (CHOOSE "SEQ " + o2qSeq + " TIG" + o2Cd(o2qB["ig"] - TIME:SECONDS)
        IF inSeq ELSE "COAST"))).
    LOCAL left IS LIST().
    FROM { LOCAL j IS 0. } UNTIL j > 1 STEP { SET j TO j + 1. } DO { IF o2qOut[j] = "" AND o2qIsEng(o2qOmsEng(j)) { left:ADD(j). } }
    IF lit {                                 // in the burn: the trigger flies on on what is left (or ends it: OMS)
        IF o2qB["ek"]:LENGTH > 0 { o2qSay("SINGLE OMS BURN (" + nm + " OUT)", "Y"). }
        RETURN.
    }
    IF NOT inSeq {
        IF left:LENGTH = 0 { o2qSay("BOTH OMS OUT", "R"). }
        ELSE { o2qSay("SINGLE OMS BURN (" + nm + " OUT)", "Y"). }
        RETURN.
    }
    o2qOmsReplan(nm).                        // before ignition
}
FUNCTION o2qOmsReplan {                      // an engine out before ignition: the burn on what is left, centred where it was
    PARAMETER nm.
    SET o2qB["ek"] TO o2qOmsK().
    SET o2qB["eng"] TO o2qOms().
    IF o2qB["ek"]:LENGTH = 0 {
        o2qSeqStop().
        o2qSay("BOTH OMS OUT: " + o2F(o2qB["peg"]["tot"], 1, 1) + " M/S LEFT", "R").
        RETURN.
    }
    LOCAL tb0 IS o2qB["tb"].
    LOCAL tb1 IS o2qTb(o2qB["peg"]["tot"]).
    LOCAL ig IS o2pReTig(o2qB["ig"], tb0, tb1, TIME:SECONDS + 2).
    o2qLogLine("SINGLE OMS BURN on " + o2qKNames(o2qB["ek"]) + ": tb " + ROUND(tb0, 2) + " -> " + ROUND(tb1, 2) + " s, TIG UT "
        + ROUND(o2qB["ig"], 2) + " -> " + ROUND(ig, 2) + " (the centre UT " + ROUND(ig + tb1 / 2, 2) + ")").
    SET o2qB["ig"] TO ig.
    SET o2qB["tb"] TO tb1.
    LOCAL rk IS CHOOSE o2qB["peg"]["rt"] IF o2qB["peg"]:HASKEY("rt") ELSE V(0, 0, 0).
    SET o2Val["tig"] TO o2qMetOf(ig).
    IF rk:MAG > 0 { o2qP4Keep(rk). }         // PEG 4: the target point kept (THETA T re-measured from the new TIG)
    o2qSay("SINGLE OMS BURN (" + nm + " OUT): TIG " + o2Met(o2Val["tig"]), "Y").
    // the attitude: the one engine's thrust along VGO (o2qAimPre through its line) -- pointed again if it was settled
    IF o2qSeq = "AIM" OR o2qSeq = "NULL" OR o2qSeq = "FINE" OR o2qSeq = "WARP2" {
        IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
        RCS ON.
        IF NOT O2Q_KOS_STEER { o2qAimPre(). o2qWarpFreeOff(). o2qAlignStart(). }   // The DAP turns to the one engine's attitude
        o2qPhase("ALIGN", "").
    }
    IF o2qSeq = "SETTLE" { o2qOmsLight(). }
}
FUNCTION o2qOmsWatch {                       // the main loop's RM, each cycle: SHUTDOWN / GONE off the burn, an out engine
    LOCAL live IS o2qOmsLive().              // kept shut (never relit), the timed failure before ignition
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        IF o2qOid[k] <> "" {
            LOCAL en IS o2qOmsEng(k).
            LOCAL inBurn IS live AND o2qB["ek"]:CONTAINS(k).
            IF o2qOut[k] <> "" {
                IF o2qIsEng(en) AND en:IGNITION { en:SHUTDOWN(). o2qLogLine("OMS " + LIST("L", "R")[k] + " OUT, FOUND LIT: SHUT DOWN AGAIN"). }
            } ELSE IF inBurn {
                // the trigger tests it
            } ELSE IF NOT o2qIsEng(en) {
                o2qOmsFailAny(k, "GONE").
            } ELSE IF o2qOmsOff[k] {
                // ops2q's own single-burn shutdown
            } ELSE IF en:IGNITION {
                SET o2qOn[k] TO TRUE.
            } ELSE IF o2qOn[k] {
                o2qOmsFailAny(k, "SHUTDOWN").
            }
        }
    }
    o2qSimPts().                             // SimSup's decision point at the loaded burn's TIG (once, only while latched)
    fuiTick(MISSIONTIME, o2qFailTigNow(), FALSE, NOT live).   // the window's keys, redraw and save; its schedule (MET / TIG rows) off the burn (the trigger owns it in the burn)
    // a loaded burn (no sequence) kept centred when its engines change (a failure, MNVR EXEC's OMS): the TIG moved by
    // half the change of its length
    LOCAL kn IS o2qKNames(o2qOmsK()).
    IF o2qSeq = "" AND o2qLoaded() AND kn <> "NONE" {
        LOCAL tb IS o2qTb(o2qDvTot()).
        IF kn <> o2qTbK AND o2qTbK <> "" AND o2qTbK <> "NONE" {
            LOCAL rk IS CHOOSE o2qP4Tgt() IF o2qPeg4() ELSE V(0, 0, 0).
            SET o2Val["tig"] TO o2Val["tig"] + o2qTbL / 2 - tb / 2.
            IF rk:MAG > 0 { o2qP4Keep(rk). }
            o2qLogLine("OMS " + o2qTbK + " -> " + kn + ": tb " + ROUND(o2qTbL, 2) + " -> " + ROUND(tb, 2) + " s, TIG moved "
                + ROUND(o2qTbL / 2 - tb / 2, 2) + " s (the centre kept)").
            SET o2qArmed TO FALSE.
        }
        SET o2qTbL TO tb.
    }
    SET o2qTbK TO kn.
}
FUNCTION o2qBurnRm {                         // the trigger's RM, each physics tick of the burn: the crew's and the timed
    PARAMETER now.                           // failures, then each burning engine's tests (lib_o2peg o2pEoWhy; o2qThr is
                                             // still the last tick's: the throttle the thrust read now was given at)
    LOCAL dt IS CHOOSE 0 IF o2qB["trm"] < 0 ELSE now - o2qB["trm"].
    SET o2qB["trm"] TO now.
    fuiSched(MISSIONTIME, o2qFailTigNow(), o2qB:HASKEY("ek")).   // the window's schedule and RAND in the burn: requests the loop below flies
    LOCAL fl IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO { IF o2qFailReq[k] <> "" { fl:ADD(LIST(k, o2qFailReq[k])). } }
    LOCAL live IS now - o2qB["t0"] >= O2P_LIVE_T.
    FROM { LOCAL i IS 0. } UNTIL i >= o2qB["ek"]:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL k IS o2qB["ek"][i].
        LOCAL en IS o2qB["eng"][i].
        IF o2qFailReq[k] = "" {
            LOCAL rr IS o2pEoWhy(TRUE, live, en:IGNITION, en:FLAMEOUT, o2qThr, en:AVAILABLETHRUST, en:THRUST, o2qPcT[k], dt).
            SET o2qPcT[k] TO rr[1].
            IF rr[0] <> "" { fl:ADD(LIST(k, rr[0])). }
        }
    }
    FOR f IN fl { o2qOmsFail(f[0], f[1]). }
}

// ---- the orbit DAP (lib_o2dap) on KalsCoproc's fly-by-wire
FUNCTION o2qFbwHas {                         // KalsCoproc's fly-by-wire has the suffix nm (lib_arm larFbwHas)
    PARAMETER nm.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX(nm).
}
FUNCTION o2qGeo { RETURN LIST(o2qRv(), SHIP:VELOCITY:ORBIT, SOLARPRIMEVECTOR, SHIP:BODY:ANGULARVEL). }
FUNCTION o2qStick {                          // the pilot's stick V(pitch, roll, yaw) -1..1: as KalsCoproc was handed it
    IF o2qDapOn {                            // while the DAP flies (the vessel's own input is the DAP's then)
        LOCAL p IS ADDONS:KALS:FBWPILOT().
        RETURN V(p[0], p[1], p[2]).
    }
    LOCAL c IS SHIP:CONTROL.
    RETURN V(c:PILOTPITCH, c:PILOTROLL, c:PILOTYAW).
}
FUNCTION o2qDapStart {                       // at RUN: AUTO, INRTL on the attitude it has (arm.ks's hold at RUN arm)
    IF DEFINED ASC_O2_HOLD {                      // ops1q's cooked hold of the gap (the attitude it held at its end) goes now, so kOS's steering and the C# DAP never fly together
        IF ASC_O2_HOLD {
            o2qLogLine("COOKED HOLD released (T726): the orbiter is " + ROUND(VANG(SHIP:FACING:FOREVECTOR, ASC_O2_DIR:FOREVECTOR), 2) + " deg from the attitude ops1q held at its end, " + ROUND(TIME:SECONDS - ASC_O2_HOLD_T, 1) + " s ago").
            IF DEFINED STEER_UNLOCKS { FOR u IN STEER_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } } }   // ops1q's own lock (a lock is released only from the file that made it; ops1q is still running when the crew path RUNPATHs ops2q)
            UNLOCK STEERING.                         // the steering manager off (this file has a LOCK STEERING, so this one disables it; ops1q already ended = the SAIL job path)
            SET ASC_O2_HOLD TO FALSE.
        }
    }
    SET o2qDapOk TO o2qFbwHas("FBW3").
    IF NOT o2qDapOk {
        o2qSay("DAP N/A: NO KALSCOPROC FLY-BY-WIRE", "Y").
        RETURN.
    }
    SET o2qDapCs TO o2qFbwHas("O2DAPSET").     // C# flies it every physics tick (else kOS, once a cycle)
    o2qLogLine("DAP: " + (CHOOSE "C# EVERY PHYSICS TICK (KalsCoproc O2DAPSET)" IF o2qDapCs ELSE "kOS ONCE A CYCLE (NO O2DAPSET IN KalsCoproc)")).
    IF o2qDapCs AND NOT o2qWakeCs {          // C#'s watchdog lets go 100 ticks after the last call: this keeps it fed (with O2TICK the OMSHOLD trigger feeds it)
        WHEN TRUE THEN { IF o2qDapCs AND o2qDapOn { SET o2qDapAl TO ADDONS:KALS:O2DAPALIVE. } RETURN NOT o2qQuit. }
    }
    LOCAL at IS o2qAtt().
    SET o2Val["tr"] TO ROUND(at[0], 1). SET o2Val["tp"] TO ROUND(at[1], 1). SET o2Val["ty"] TO ROUND(at[2], 1).
    o2qDapResume("AT RUN").
}
FUNCTION o2qSeedGet {                        // The burn's pitch trim seed: O2Q_SEED_K x the trim the last burn of this flight learned (1:/o2q_trim.txt); 0 = none
    IF NOT EXISTS(O2Q_TRIM_FILE) { RETURN 0. }
    LOCAL f IS OPEN(O2Q_TRIM_FILE):READALL:STRING:TRIM:SPLIT(",").
    IF f:LENGTH < 3 { RETURN 0. }
    LOCAL ui IS f[0]:TONUMBER(0). LOCAL m IS f[1]:TONUMBER(0). LOCAL ut IS f[2]:TONUMBER(0).
    IF ABS(ui) < 0.02 OR m <= 0 OR ABS(SHIP:MASS - m) > O2Q_SEED_DM OR TIME:SECONDS < ut OR TIME:SECONDS - ut > O2Q_SEED_AGE { RETURN 0. }
    RETURN MAX(-O2Q_SEED_MAX, MIN(O2Q_SEED_MAX, ui * O2Q_SEED_K)).
}
FUNCTION o2qSeedSave {                       // At the burn's end the pitch trim it learned, to the vessel's volume (the next burn's seed)
    IF EXISTS(O2Q_TRIM_FILE) { DELETEPATH(O2Q_TRIM_FILE). }
    LOG ROUND(o2qDap["ui"]:X, 4) + "," + ROUND(SHIP:MASS, 2) + "," + ROUND(TIME:SECONDS, 1) TO O2Q_TRIM_FILE.
}
FUNCTION o2qDapResume {                      // the DAP flies again: SAS off, RCS on, AUTO INRTL on the attitude it has
    PARAMETER why.
    IF o2qDap["ki"] > 0 AND o2qB:HASKEY("lit") AND o2qB["lit"] AND TIME:SECONDS - o2qB["t0"] > 15 AND ABS(o2qDap["ui"]:X) >= 0.02 { o2qSeedSave(). }   // Before the reset below
    SAS OFF.
    RCS ON.
    SET o2qDapOn TO TRUE.
    SET o2qWarpFree TO FALSE.
    SET o2qDapT TO -1.
    SET o2qDap["mode"] TO "AUTO". SET o2Val["dmode"] TO 0.
    SET o2qDap["db"] TO o2Val["ddb"]. SET o2qDap["rate"] TO o2Val["drate"].
    SET o2qGmMode TO 0.                      // The jets are the DAP's again (the DLL restores them at its next tick)
    SET o2qDap["k"] TO O2D_K. SET o2qDap["tau"] TO O2D_TAU. SET o2qDap["ki"] TO 0. SET o2qDap["ui"] TO V(0, 0, 0).   // The orbit hold's gains
    o2qDapHold("INRTL").
    o2qLogLine("DAP ON " + why + ": AUTO, INRTL, DB " + o2Val["ddb"] + " deg, RATE " + o2Val["drate"] + " deg/s, the orbiter turning "
        + ROUND(o2qRate(), 3) + " deg/s").
}
// ---- The burn on the gimbals (the DLL's OmsGm does the switching; this decides the mode and tells it)
FUNCTION o2qGmWant {                         // the mode for the burn now: 0 the jets fly as before, 1 RCS off, 2 RCS roll jets only (one engine)
    IF O2Q_GM <= 0 OR NOT o2qDapCs OR NOT o2qDapOn OR NOT o2qGmDll { RETURN 0. }
    IF o2qB["eng"]:LENGTH = 0 { RETURN 0. }
    FOR en IN o2qB["eng"] {                  // an engine without a free gimbal (OMS 03 GIMBAL LOCKED, none): the jets keep the attitude
        IF NOT en:HASGIMBAL { RETURN 0. }
        IF en:GIMBAL:LOCK OR flfxGlk(en) { RETURN 0. }
    }
    IF o2qB["eng"]:LENGTH >= 2 { RETURN 1. }
    RETURN CHOOSE 2 IF O2Q_GM >= 2 ELSE 1.
}
FUNCTION o2qGmSet {                          // the mode now; a change is told to the DAP and logged
    PARAMETER why.
    LOCAL w IS o2qGmWant().
    SET o2qGmN TO o2qB["eng"]:LENGTH.
    IF w = o2qGmMode AND why <> "IGNITION" { RETURN. }
    SET o2qGmMode TO w.
    LOCAL tx IS "the jets fly with the gimbals as before".
    IF w = 1 { SET tx TO "RCS OFF at 80 % thrust: the gimbals and the wheels fly the attitude". }
    IF w = 2 { SET tx TO "RCS OFF at 80 % thrust but the ROLL jets (one engine: its gimbal has pitch and yaw only)". }
    IF w = 0 {
        IF O2Q_GM <= 0 { SET tx TO tx + " (O2Q_GM 0)". }
        ELSE IF NOT o2qDapCs { SET tx TO tx + " (the DAP is kOS's: no C# gimbal mode)". }
        ELSE IF NOT o2qGmDll { SET tx TO tx + " (KalsCoproc has no gimbal mode: an older DLL)". }
        ELSE { SET tx TO tx + " (an engine of the burn has no free gimbal)". }
    }
    o2qLogLine("GIMBAL MODE " + w + " (" + why + ", " + o2qGmN + " engine(s), O2Q_GM " + O2Q_GM + "): " + tx).
    o2qDapPush().
}
FUNCTION o2qGmEnd {                          // the cut: the mode 0 (the DLL gives the jets back at once if the taper has not)
    PARAMETER why.
    IF o2qGmMode = 0 { RETURN. }
    SET o2qGmMode TO 0.
    o2qDapPush().
    o2qLogLine("GIMBAL MODE 0 at the cut (" + why + "): the jets are the DAP's again").
}
FUNCTION o2qDapStandby {                     // the DAP lets go (the burn's kOS steering flies)
    PARAMETER why.
    IF NOT o2qDapOn { RETURN. }
    SET o2qDapOn TO FALSE.
    LOCAL ok IS ADDONS:KALS:FBWOFF().
    o2qLogLine("DAP STANDBY: " + why).
}
FUNCTION o2qDapHold {                        // HOLD md on the attitude now (TRACK: the page's axis and target)
    PARAMETER md.
    LOCAL fc IS SHIP:FACING.
    IF md = "TRACK" {
        LOCAL rf IS SHIP:ROOTPART:FACING.    // the body axis on the root's (the nose's) axes: X fore, Y star, Z down
        LOCAL k IS ROUND(o2Val["tax"]).
        LOCAL aw IS LIST(rf:FOREVECTOR, -rf:FOREVECTOR, rf:STARVECTOR, -rf:STARVECTOR, -rf:TOPVECTOR, rf:TOPVECTOR)[k].
        LOCAL pw IS LIST(rf:STARVECTOR, rf:STARVECTOR, -rf:TOPVECTOR, -rf:TOPVECTOR, rf:FOREVECTOR, rf:FOREVECTOR)[k].   // omicron's second axis
        LOCAL g IS o2qGeo().
        LOCAL toEarth IS ROUND(o2Val["ttg"]) = 0.
        LOCAL axc IS V(VDOT(aw, fc:STARVECTOR), VDOT(aw, fc:TOPVECTOR), VDOT(aw, fc:FOREVECTOR)).
        LOCAL pwc IS V(VDOT(pw, fc:STARVECTOR), VDOT(pw, fc:TOPVECTOR), VDOT(pw, fc:FOREVECTOR)).
        // the reference starts on the line of sight at the typed omicron (zero: the velocity / the spin axis up)
        LOCAL rr IS o2dTrackRef(axc, pwc, CHOOSE -o2qRv() IF toEarth ELSE SUN:POSITION, CHOOSE g[1] IF toEarth ELSE g[3], o2Val["tom"]).
        LOCAL wasCss IS o2qDap["mode"] = "CSS".
        o2dTrack(o2qDap, axc, fc:FOREVECTOR, fc:TOPVECTOR, g, rr).
        IF wasCss { SET o2Val["dmode"] TO 0. o2qLogLine("DAP TRACK: AUTO (CSS and TRACK never both)"). }   // lib_o2dap's msg says it
    } ELSE { o2dHold(o2qDap, md, fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()). }
    SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(md).
    o2qDapPush().
    o2qLogLine("DAP HOLD " + md + (CHOOSE " " + LIST("+X", "-X", "+Y", "-Y", "+Z", "-Z")[ROUND(o2Val["tax"])] + " TO "
        + LIST("EARTH", "SUN")[ROUND(o2Val["ttg"])] + " OMICRON " + o2Val["tom"] IF md = "TRACK" ELSE "")).
}
FUNCTION o2qDapAct {                         // MNVR (ORBIT / PTG's TGT, MNVR EXEC's burn attitude), STOP
    PARAMETER id.
    IF NOT o2qDapOn { o2qSay("DAP NOT FLYING", "Y"). RETURN. }
    LOCAL fc IS SHIP:FACING.
    IF id = "ostop" {
        o2dStop(o2qDap, fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()).
        SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(o2qDap["hold"]).
        o2qSay("STOP: " + o2qDap["hold"] + " HOLD", "V").
        o2qDapPush().
        RETURN.
    }
    IF id = "mnvr" {                         // the burn attitude: the OMS thrust line turned onto VGO, held INRTL
        LOCAL ba IS o2dTvAtt(fc:FOREVECTOR, fc:TOPVECTOR, o2qLine(o2qOms()), o2qVgo(), o2qDnTig(), o2Val["tvr"]).   // The line on VGO, rolled TV ROLL; from the vertical AT THE IGNITION (the one now is 180 deg off over a quarter orbit before TIG)
        SET o2qDap["hold"] TO "INRTL".
        o2dMnvr(o2qDap, ba[0], ba[1], o2qGeo()).
        o2qSay("MNVR TO BURN ATT: " + ROUND(o2dRotV(fc:FOREVECTOR, fc:TOPVECTOR, ba[0], ba[1]):MAG / O2D_D2R, 1) + " DEG, TV ROLL " + ROUND(o2Val["tvr"], 1), "V").
        LOCAL qa IS o2dRotV(fc:FOREVECTOR, fc:TOPVECTOR, ba[0], ba[1]).   // The log reads the roll the held attitude will have AT THE IGNITION
        o2qLogLine("DAP MNVR TV ROLL at the ignition: " + ROUND(o2dTvRoll(o2dTurn(o2qLine(o2qOms()), qa), ba[1], o2qDnTig()), 1) + " deg about the thrust line (entry " + ROUND(o2Val["tvr"], 1) + ")").
    } ELSE {                                 // TGT R / P / Y in LVLH, the root's (the nose's); the control point mapped
        LOCAL rf IS SHIP:ROOTPART:FACING.
        LOCAL tg IS o2dFromRpy(o2Val["tr"], o2Val["tp"], o2Val["ty"], o2Lvlh(o2qRv(), SHIP:VELOCITY:ORBIT)).
        LOCAL cm IS o2dMap(tg[0], tg[1], rf:FOREVECTOR, rf:TOPVECTOR, fc:FOREVECTOR, fc:TOPVECTOR).
        o2dMnvr(o2qDap, cm[0], cm[1], o2qGeo()).
        o2qSay("MNVR TO R " + o2Val["tr"] + " P " + o2Val["tp"] + " Y " + o2Val["ty"] + ", " + o2qDap["hold"] + " HOLD", "V").
    }
    SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(o2qDap["hold"]).
    o2qDapPush().
    o2qLogLine("DAP MNVR: " + ROUND(o2dRotV(fc:FOREVECTOR, fc:TOPVECTOR, o2dOut(o2dBasis(o2qDap["rf"], o2qGeo()), o2qDap["ref"][0]),
        o2dOut(o2dBasis(o2qDap["rf"], o2qGeo()), o2qDap["ref"][1])):MAG / O2D_D2R, 2) + " deg at " + o2qDap["rate"] + " deg/s").
}
FUNCTION o2qStickOk {                        // The stick is the DAP's except through the burn sequence (no CSS downmode in the burn);
    IF O2A_ON AND DEFINED ARM_UI { IF ARM_UI["stick"]:PRESSED { RETURN FALSE. } }   // RHC STICK pressed = the stick is the ARM's (the DAP sees none: no AUTO -> CSS downmode, the orbiter does not turn with the end effector)
    RETURN O2Q_KOS_STEER OR o2qSeq = "" OR o2qDap["mode"] = "CSS".   // the page's CSS button hands the crew the attitude
}
FUNCTION o2qDnTig {                          // The down TV ROLL is measured from for a burn NOT yet
    LOCAL ig IS MAX(TIME:SECONDS, o2qUtOf(o2Val["tig"])).   // running = the Earth's centre AT THE IGNITION (the loaded burn's TIG, or now once it is past), what the burn's own roll is read from.
    RETURN o2qFrameAt(ig)[2]:NORMALIZED.     // The vertical NOW is 180 deg off once TIG is over a quarter orbit away (the aim is inertial, the roll about it is not): e.g. MNVR at TIG-800 s
}                                            // (period 2930 s) held the roll the sequence's ALIGN then turned 179.9 deg
FUNCTION o2qTvDown {                         // The down TV ROLL is measured from: the Earth's centre now until the ignition (the aim and
    IF o2qB:HASKEY("lit") AND o2qB["lit"] {  // the roll turn with the orbit, as the lead does), the one AT the ignition for the burn (the real burn's roll is inertial)
        IF NOT o2qB:HASKEY("tvdn") { SET o2qB["tvdn"] TO -o2qRv():NORMALIZED. }
        RETURN o2qB["tvdn"].
    }
    RETURN -o2qRv():NORMALIZED.
}
FUNCTION o2qAimTv {                          // The burn attitude: the thrust line tl on the aim u (the least turn of the attitude now), rolled TV ROLL about u
    PARAMETER u, tl.                         // from the local down: o2qAimV = its fore (LOCK STEERING's, the DAP's reference), o2qAimT = its top
    LOCAL fc IS SHIP:FACING.
    LOCAL dn IS o2qTvDown().
    LOCAL ba IS o2dTvAtt(fc:FOREVECTOR, fc:TOPVECTOR, tl, u, dn, o2Val["tvr"]).
    SET o2qAimV TO ba[0]:NORMALIZED.
    SET o2qAimT TO ba[1].
    SET o2qTvMeas TO o2dTvRoll(tl, fc:TOPVECTOR, dn).
}
FUNCTION o2qAlignStart {                     // The DAP turns to the burn attitude (the thrust line on VGO) at the burn's rate / deadband, then holds it
    LOCAL fc IS SHIP:FACING.
    LOCAL qv IS o2dRotV(fc:FOREVECTOR, fc:TOPVECTOR, o2qAimV, o2qAimT).   // The whole turn (the roll with it)
    SET o2qBrF TO o2qAimV:NORMALIZED.
    SET o2qBrT TO o2qAimT.                       // The roll is TV ROLL's (it was the roll the orbiter had, carried by the least turn)
    IF o2qDap["mode"] <> "AUTO" { SET o2qDap["mode"] TO "AUTO". SET o2Val["dmode"] TO 0. }
    SET o2Val["drate"] TO MAX(o2Val["drate"], O2Q_BURN_RATE_MIN).   // The page RATE shows the rate the DAP flies
    SET o2qDap["rate"] TO o2Val["drate"].
    SET o2qDap["db"] TO MIN(o2Val["ddb"], O2Q_BURN_DB).
    SET o2qDap["hold"] TO "INRTL".
    o2dMnvr(o2qDap, o2qBrF, o2qBrT, o2qGeo()).
    SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF("INRTL").
    o2qDapPush().
    LOCAL tn IS qv:MAG / O2D_D2R / o2qDap["rate"].    // s the turn takes at the burn's rate (S2)
    SET o2qAlignMax TO MIN(O2Q_ALIGN_LEAD - O2Q_SETTLE_LEAD - 10, MAX(O2Q_ALIGN_MAX, tn * 1.3 + 60)).
    SET o2qAlignTxt TO "MNVR TO BURN ATT: " + ROUND(qv:MAG / O2D_D2R) + " DEG, ABOUT " + ROUND(tn) + " S".
    o2qLogLine("DAP BURN ATT (TV ROLL " + ROUND(o2Val["tvr"], 1) + "): " + ROUND(qv:MAG / O2D_D2R, 1) + " DEG AT " + o2qDap["rate"] + " DEG/S, DB " + o2qDap["db"] + " DEG; ALIGN GETS " + ROUND(o2qAlignMax) + " S").
}
FUNCTION o2qBurnRef {                        // Each cycle the DAP's reference follows the aim (fore and top: o2qAimV / o2qAimT)
    IF O2Q_KOS_STEER OR NOT o2qDapOn OR o2qWarpFree { RETURN. }
    IF o2qDap["mode"] <> "AUTO" { RETURN. }      // CSS: the crew flies the attitude
    SET o2qBrT TO o2qAimT.                       // The aim's own top: the thrust line on VGO at TV ROLL (before the ignition from the vertical now, in the burn from the vertical at the ignition)
    SET o2qBrF TO o2qAimV:NORMALIZED.
    o2dRefSet(o2qDap, o2qBrF, o2qBrT, o2qGeo()).
    o2qDapPush().
}
FUNCTION o2qSteerCols {                      // the burn log's six steering columns (st_p, st_y, st_r, err_p, err_y, err_ang): kOS's steering manager (legacy) or our DAP's jets / error
    IF O2Q_KOS_STEER {
        RETURN ROUND(STEERINGMANAGER:PITCHPID:OUTPUT, 4) + "," + ROUND(STEERINGMANAGER:YAWPID:OUTPUT, 4) + "," + ROUND(STEERINGMANAGER:ROLLPID:OUTPUT, 4)
            + "," + ROUND(STEERINGMANAGER:PITCHERROR, 3) + "," + ROUND(STEERINGMANAGER:YAWERROR, 3) + "," + ROUND(STEERINGMANAGER:ANGLEERROR, 3).
    }
    LOCAL e IS o2qDap["e"].                  // V(pitch, roll, yaw) deg
    RETURN ROUND(o2qDapU:X, 4) + "," + ROUND(o2qDapU:Z, 4) + "," + ROUND(o2qDapU:Y, 4)
        + "," + ROUND(e:X, 3) + "," + ROUND(e:Z, 3) + "," + ROUND(o2qDap["ea"], 3).
}
FUNCTION o2qDapPush {                        // the crew's action to the C# DAP (it flies it from the next tick)
    IF NOT o2qDapCs OR NOT o2qDapOn { RETURN. }
    LOCAL b IS o2dBasis(o2qDap["rf"], o2qGeo()).
    LOCAL rs IS ADDONS:KALS:O2DAPSET(LIST(o2qDap["mode"], o2qDap["hold"], o2qDap["rf"], o2qDap["act"], o2dOut(b, o2qDap["ref"][0]),
        o2dOut(b, o2qDap["ref"][1]), o2qDap["ax"], o2qDap["db"], o2qDap["rate"], o2qDap["tk"], o2qDap["k"], o2qDap["tau"], o2qDap["ki"], o2qDap["uis"], o2qDap["uisN"], o2qGmMode)).   // items 11-13, 14-15 the seed (an old DLL ignores them)
    IF rs <> "" { o2qDapKos("O2DAPSET " + rs). }
}
FUNCTION o2qDapKos {                         // the C# DAP failed: kOS flies it from now (once a cycle, FBW3)
    PARAMETER why.
    SET o2qDapCs TO FALSE.
    SET o2qDapT TO -1.
    o2qLogLine("DAP C# FAILED (" + why + "): kOS FLIES THE DAP, ONCE A CYCLE").
}
FUNCTION o2qDapCyc {                         // the C# DAP's state back into o2qDap, once a cycle -> its jets
    LOCAL c IS ADDONS:KALS:O2DAPCYC(LIST(o2qInEff() = "PAGE" AND NOT o2Typ AND o2qStickOk(), ROUND(o2Val["ttg"]))).   // INPUT RHC: the stick is the page's
    IF NOT c[0] { o2qDapKos("C# DAP OFF: " + c[15]). RETURN V(0, 0, 0). }
    SET o2qDap["mode"] TO c[1]. SET o2qDap["act"] TO c[3]. SET o2qDap["e"] TO c[4]. SET o2qDap["ea"] TO c[5].
    IF c[2] <> o2qDap["hold"] {              // C# made the hold LVLH (CSS and TRACK never both): the frame goes with it
        SET o2qDap["hold"] TO c[2]. SET o2qDap["rf"] TO CHOOSE "LVLH" IF c[2] = "LVLH" ELSE "INRTL".
    }
    SET o2qDap["w"] TO c[6]. SET o2qDap["u"] TO c[7]. SET o2qDap["tk"] TO c[12].
    IF c:LENGTH > 16 { SET o2qDap["ui"] TO c[16]. }   // The integral trim (a DLL without it returns 16 items)
    IF c:LENGTH > 17 {                           // The seed's sign guard fired in the DLL (once)
        IF c[17] > 0 AND o2qDap["seeddrop"] = 0 { o2qLogLine("DAP SEED DROPPED: the pitch error grew with the seed (the wrong sign): the unseeded law flies on"). }
        SET o2qDap["seeddrop"] TO c[17].
    }
    IF c:LENGTH > 18 {                       // The gimbal mode's state (OmsGm.cs); a change is logged
        SET o2qGmDll TO TRUE.
        IF c[18] <> o2qGmTxt {
            o2qLogLine("GIMBAL MODE " + o2qGmMode + ": " + o2qGmTxt + " -> " + c[18] + " (RCS " + (CHOOSE "on" IF RCS ELSE "off") + ")").
            SET o2qGmTxt TO c[18].
        }
    }
    IF c[8] <> "" { SET o2qDap["msg"] TO c[8]. }
    LOCAL b IS o2dBasis(o2qDap["rf"], o2qGeo()).
    SET o2qDap["ref"] TO LIST(o2dIn(b, c[9]), o2dIn(b, c[10])).
    SET o2qDapAu TO c[11].
    SET o2qDapDt TO MAX(o2qDapDt, c[14]).
    RETURN c[7].
}
FUNCTION o2qCrewAuto {                       // The crew re-selects AUTO after RESTART SW healed SW 01 / SW 02 (lib_flfx flfxTick, only while SAIL flies: no pilot)
    IF o2qDap["mode"] <> "CSS" OR NOT o2qSwForced OR flfxSwLost("SW 01", "ORBIT") { RETURN. }
    SET o2qSwForced TO FALSE.
    LOCAL fc IS SHIP:FACING.
    LOCAL hb IS o2qDap["hold"].
    o2dMode(o2qDap, "AUTO", fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()).      // the DMODE press's own call
    SET o2Val["dmode"] TO 0.
    IF o2qDap["hold"] <> hb { SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(o2qDap["hold"]). }
    o2qSay("AUTO DAP: RE-SELECTED AFTER RESTART SW", "V").
    o2qLogLine("DAP AUTO: RE-SELECTED AFTER RESTART SW (the crew; SAIL flies)").
    o2qDapPush().
}
FUNCTION o2qDapTick {                        // one cycle of the DAP: its command on the vessel's pitch / roll / yaw
    IF NOT o2qDapOn { SET o2qDapU TO V(0, 0, 0). RETURN. }
    LOCAL now IS TIME:SECONDS.
    LOCAL u IS V(0, 0, 0).
    LOCAL fc IS SHIP:FACING.
    IF o2qDapCs { SET u TO o2qDapCyc(). }
    // SW 01 ORBIT refuses AUTO whoever flies. kOS sets CSS; with the C# DAP flying the new mode goes to
    // it once (O2DAPSET, o2qDapPush). The crew's AUTO is refused at the dmode press (ops2q.ks, the S4c-2 check there).
    IF o2qDap["mode"] = "AUTO" AND flfxSwLost("SW 01", "ORBIT") {     // SW 01 AUTO DAP LOST: the DAP is put in CSS (its page button too)
        o2dMode(o2qDap, "CSS", fc:FOREVECTOR, fc:TOPVECTOR, o2qGeo()).
        SET o2Val["dmode"] TO 1.
        SET o2qSwForced TO TRUE.
        o2qSay("AUTO DAP LOST: CSS ONLY", "V").
        IF o2qDapCs { o2qDapPush(). }
    }
    IF NOT o2qDapCs {                        // kOS flies it (a KalsCoproc without O2DAPSET, or the C# one failed)
    IF KUNIVERSE:TIMEWARP:MODE = "RAILS" AND KUNIVERSE:TIMEWARP:RATE > 1 { SET o2qDapT TO -1. RETURN. }   // on rails nothing flies
    LOCAL dt IS CHOOSE 0 IF o2qDapT < 0 OR now - o2qDapT > 2 ELSE now - o2qDapT.
    SET o2qDapT TO now.
    SET o2qDapDt TO MAX(o2qDapDt, dt).
    IF now - o2qDapAuT > 1 { LOCAL au IS ADDONS:KALS:FBWAUTH(). SET o2qDapAu TO V(au[0], au[1], au[2]). SET o2qDapAuT TO now. }
    LOCAL sk IS CHOOSE o2qStick() IF o2qInEff() = "PAGE" AND NOT o2Typ AND o2qStickOk() ELSE V(0, 0, 0).   // INPUT RHC: the stick is the page's
    LOCAL los IS V(0, 0, 0).
    IF o2qDap["hold"] = "TRACK" { SET los TO CHOOSE -o2qRv() IF ROUND(o2Val["ttg"]) = 0 ELSE SUN:POSITION. }
    SET u TO o2dTick(o2qDap, o2qGeo(), fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR, SHIP:ANGULARVEL, o2qDapAu, dt, sk, los).
    ADDONS:KALS:FBW3(u:X, u:Y, u:Z).
    }
    SET o2qDapU TO u.                        // the RCS CMD lamps
    IF o2qDap["msg"] <> "" {
        o2qSay(o2qDap["msg"], "V").
        SET o2qDap["msg"] TO "".
        SET o2Val["dmode"] TO CHOOSE 1 IF o2qDap["mode"] = "CSS" ELSE 0.
        SET o2Val["hold"] TO O2Q_HOLDS:INDEXOF(o2qDap["hold"]).     // the downmode to CSS may have ended a TRACK
    }
    IF now - o2qDapLogT > O2Q_DAP_LOG {
        SET o2qDapLogT TO now.
        LOCAL e IS o2qDap["e"]. LOCAL w IS o2qDap["w"].
        o2qLogLine("DAP " + o2qDap["mode"] + " " + o2qDap["hold"] + " " + o2qDap["act"] + ": error " + ROUND(o2qDap["ea"], 2) + " deg ("
            + ROUND(e:X, 2) + " " + ROUND(e:Y, 2) + " " + ROUND(e:Z, 2) + "), rate " + ROUND(w:X, 3) + " " + ROUND(w:Y, 3) + " "
            + ROUND(w:Z, 3) + " deg/s, jets " + ROUND(u:X, 3) + " " + ROUND(u:Y, 3) + " " + ROUND(u:Z, 3) + " (pitch, roll, yaw), authority "
            + ROUND(o2qDapAu:X, 3) + " " + ROUND(o2qDapAu:Y, 3) + " " + ROUND(o2qDapAu:Z, 3) + " deg/s2, the longest " + (CHOOSE "tick (C#) " IF o2qDapCs ELSE "cycle ")
            + ROUND(o2qDapDt, 2) + " s" + (CHOOSE ", trim " + ROUND(o2qDap["ui"]:X, 3) + " " + ROUND(o2qDap["ui"]:Y, 3) + " " + ROUND(o2qDap["ui"]:Z, 3) + " deg/s2" IF o2qDap["ki"] > 0 ELSE "")).
        SET o2qDapDt TO 0.
    }
}

// ---- the wait: the cycle every O2Q_DT as before, but an input (a press of the window, a key, AG4, the stick in
// INPUT RHC) ends it at once, so the press is acted on and drawn the next physics tick
// The cycle is due O2Q_DT of UT after the last one at 1x, O2Q_DT x the rate on rails: UT runs rate x faster per physics tick there, so
// the plain O2Q_DT made EVERY tick a full cycle (kOS CPU 3x a tick in the 10x warp).
// The smaller of the rate at the last cycle and the rate now counts: a warp starting runs cycles until one has seen the new rate,
// a warp ending (the rate falling) is due at once, never later than before.
FUNCTION o2qDue {
    RETURN TIME:SECONDS - o2qPassT >= O2Q_DT * MAX(1, MIN(o2qPassRate, KUNIVERSE:TIMEWARP:RATE)).
}
FUNCTION o2qInWait {
    IF o2qWakeCs { IF o2qK:O2WAKE(o2qAg4, o2qAg6, o2qAg7) { RETURN TRUE. } }   // The due test + the action groups 4 / 6 / 7 in one C# call (O2WAKESET holds the pass time)
    ELSE { IF o2qDue() { RETURN TRUE. } }
    IF O2A_ON { RETURN TRUE. }               // the hosted arm passes every physics tick
    IF o2Press:LENGTH > 0 { RETURN TRUE. }
    IF NOT o2qWakeCs {
        IF AG4 <> o2qAg4 { RETURN TRUE. }
        IF AG6 <> o2qAg6 OR AG7 <> o2qAg7 { RETURN TRUE. }   // a pilot press of the OMS / forward point
    }
    IF o2qKeysOk {
        LOCAL ks IS ADDONS:KALS:KEYS.
        IF ks:LENGTH > 0 { FOR k IN ks { o2qKeyBuf:ADD(k). } RETURN TRUE. }
    }
    IF o2qInEff() = "RHC" AND NOT o2Typ {
        LOCAL k IS o2qRhcKey().
        IF k <> o2qRhcK OR (k <> "" AND TIME:SECONDS >= o2qRhcT) { RETURN TRUE. }
    }
    RETURN FALSE.
}

// ---- the draw
// ---- the ATO / AOA TGT page (the model: lib_o2ato.ks). ops1q's hand-off (1:/ops2q_ho.txt) opens it when ops2q starts, BEFORE OMS-1:
// asked before OMS-1 (aoaAsk's solve unchanged behind it), reversible until OMS-1 ignition and
// after it until OMS-2 (while the other mode is still reachable), no pick = the computer's, the words ATO / AOA only.
FUNCTION o2qAtoShown { RETURN o2qAto["on"] AND o2qAto["ph"] <> "DONE". }   // the page row's second slot reads ATO / AOA (DEORB's slot)
FUNCTION o2qAtoPost { RETURN o2qAto["ph"] <> "PRE". }                       // OMS-1 flown (or none planned): the real orbit, a mode out of reach is dim
FUNCTION o2qAtoLocked {                      // the pick is final: OMS-1 burning; OMS-2's sequence started (EXEC; CUT OFF before TIG frees it); the hand-off over
    IF o2qAto["ph"] = "DONE" { RETURN TRUE. }
    IF o2qSeq = "" { RETURN FALSE. }
    IF o2qAto["ph"] = "PRE" { RETURN o2qSeq = "BURN". }
    RETURN TRUE.
}
FUNCTION o2qAtoPickNow { RETURN o2atPick(ROUND(o2Val["apick"]), o2qAto["cols"]). }
FUNCTION o2qAtoOms1 {                        // the OMS-1 still to fly (PRE): LEXICON(dv, ut (its centre), tig), EMPTY when none
    LOCAL o IS LEXICON().
    IF o2qAto["ph"] <> "PRE" { RETURN o. }
    FOR sr IN o2qSrc {
        IF sr["file"] = "0:/oms1_plan.txt" AND sr["d"]:HASKEY("dv") AND sr["d"]:HASKEY("burn_ut") {
            LOCAL dv IS sr["d"]["dv"].
            LOCAL ut IS sr["d"]["burn_ut"].
            SET o TO LEXICON("dv", dv, "ut", ut, "tig", ut - o2qTb(dv) / 2).
        }
    }
    RETURN o.
}
FUNCTION o2qAoaSolve {                       // aoaSolveNow's solve; from a predicted state (the orbit after OMS-1) through aoaSolveFrom, the same body
    PARAMETER rv, vv, t0, dvMax, predicted.
    IF NOT predicted { RETURN aoaSolveNow(). }
    RUNONCEPATH("0:/lib/entry_predict.ks").
    eprInitGeo().
    LOCAL x IS aoaSolveFrom(rv, vv, t0, dvMax).
    SET AOA_SOL TO 0.                        // a prediction is not aoaPlanOms2's to reuse: it solves from the real orbit after OMS-1
    RETURN x.
}
FUNCTION o2qAtoSolve {                       // both columns, now (blocks for the AOA solve: the C# threads, a second or two)
    LOCAL o1 IS o2qAtoOms1().
    LOCAL dvo IS omsDvOnBoard().
    LOCAL dv1 IS 0.
    LOCAL tig1 IS 0.
    LOCAL t0 IS TIME:SECONDS.
    LOCAL rv IS o2qRv().
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    IF o1:LENGTH > 0 {                       // PRE: the state OMS-1 leaves (the impulse at its centre)
        SET dv1 TO o1["dv"].
        SET tig1 TO o1["tig"].
        SET t0 TO o1["ut"].
        LOCAL st IS o2qAt(t0).
        LOCAL fr IS o2Lvlh(st[0], st[1]).
        SET rv TO st[0].
        SET vv TO st[1] + o2FromLvlh(dv1, 0, 0, fr).
    }
    LOCAL el IS o2Els(rv, vv, o2qMu(), o2qNorth(), o2qEqx()).
    LOCAL rb IS SHIP:BODY:RADIUS.
    LOCAL dv2 IS 0.
    LOCAL tig2 IS 0.
    LOCAL ra IS 0.
    LOCAL rt IS 0.
    IF el["n"] > 0 AND el["e"] < 1 {         // omsAto's: at the apoapsis to the circle at ASC_ATO_H (at the apoapsis when that lies lower)
        SET ra TO el["ra"].
        SET rt TO MIN(rb + ASC_ATO_H, ra).
        LOCAL va IS SQRT(el["mu"] * (2 / ra - 1 / el["a"])).
        SET dv2 TO SQRT(el["mu"] * (2 / ra - 2 / (ra + rt))) - va.
        SET tig2 TO t0 + o2DtTA(el, el["ta"], 180) - o2qTb(dv2) / 2.
    }
    LOCAL x IS 0.
    LOCAL why IS "NO LIB_AOA".
    IF EXISTS("0:/lib/lib_aoa.ks") {
        SET x TO o2qAoaSolve(rv, vv, t0, dvo - dv1 - AOA_OMS_RESERVE, o1:LENGTH > 0).
        IF x = 0 { SET why TO AOA_WHY. }
    }
    LOCAL tb2 IS 0.
    IF NOT (x = 0) { SET tb2 TO o2qTb(CHOOSE x["dv"] IF x:HASKEY("dvr") AND ABS(x["dvr"]) > 0 ELSE x["dvt"]). }
    LOCAL inp IS LEXICON("dvo", dvo, "keep", ASC_ATO_DV_DEORBIT, "rsv", AOA_OMS_RESERVE, "m0", SHIP:MASS, "ve", ASC_OMS_ISP * CONSTANT:G0,
        "dv1", dv1, "tig1", tig1, "dv2", dv2, "tig2", tig2, "ra", ra, "rt", rt, "rbody", rb, "x", x, "tb2", tb2, "why", why).
    LOCAL cc IS o2atCols(inp).
    SET o2qAto["cols"] TO cc.
    SET o2qAto["x"] TO x.
    SET o2qAto["why"] TO why.
    SET o2qAto["dvo"] TO dvo.
    SET o2qAto["t"] TO TIME:SECONDS.
    o2qLogLine("ATO / AOA SOLVE " + o2qAto["ph"] + ": ATO " + (CHOOSE "GO" IF cc["ato"]["go"] ELSE "NO GO") + " " + ROUND(cc["ato"]["tot"], 1) + " m/s, AOA "
        + (CHOOSE ("GO " + ROUND(cc["aoa"]["tot"], 1) + " m/s") IF cc["aoa"]["ok"] ELSE ("NO SOLUTION: " + why)) + ", auto " + cc["auto"]).
}
FUNCTION o2qAtoSum {                         // the MSG line after a solve
    LOCAL c IS o2qAto["cols"].
    // The page text "AUTO: ATO" / "AUTO: AOA" (the GO / NO GO of each column stays on the page)
    LOCAL s IS (CHOOSE "AUTO" IF ROUND(o2Val["apick"]) = 2 ELSE "CREW") + ": " + o2qAtoPickNow().
    IF NOT c["aoa"]["ok"] AND o2qAto["why"] <> "" { SET s TO s + " (AOA: " + o2qAto["why"] + ")". }
    RETURN s.
}
FUNCTION o2qAtoLoad {                        // MNVR EXEC takes the plan file's burn
    PARAMETER f.
    o2qReadSrc().
    FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH STEP { SET i TO i + 1. } DO {
        IF o2qSrc[i]["file"] = f { o2qLoadSrc(i). RETURN. }
    }
}
FUNCTION o2qAtoApply {                       // the burn the pick flies is in MNVR EXEC: PRE the OMS-1 (the same for both modes), POST the OMS-2 of the pick
    IF NOT o2qAto["on"] OR o2qAtoLocked() OR o2qSeq <> "" { RETURN. }
    IF o2qAto["ph"] = "PRE" {
        IF NOT (o2qLoaded() AND o2qLoad["file"] = "0:/oms1_plan.txt") { o2qAtoLoad("0:/oms1_plan.txt"). }
        RETURN.
    }
    LOCAL pk IS o2qAtoPickNow().
    IF o2qAto["planned"] = pk AND o2qLoaded() AND o2qLoad["file"] = "0:/oms2_plan.txt" { RETURN. }
    IF pk = "AOA" {
        IF NOT o2qAto["cols"]["aoa"]["ok"] { o2qSay("AOA: NO SOLUTION: " + o2qAto["why"], "R"). RETURN. }
        IF NOT (o2qAto["x"] = 0) { SET AOA_SOL TO o2qAto["x"]. }
        IF NOT aoaPlanOms2() { o2qSay("AOA OMS-2 PLAN FAILED", "R"). RETURN. }
    } ELSE {
        IF EXISTS("1:/abort_mode.txt") { DELETEPATH("1:/abort_mode.txt"). }   // an AOA flag left by a pick that was switched back
        IF omsPlanAto("0:/oms2_plan.txt") = 0 { o2qSay("ATO: NO APOAPSIS AHEAD: NO OMS-2 PLAN", "Y"). RETURN. }
    }
    SET o2qAto["planned"] TO pk.
    o2qAtoLoad("0:/oms2_plan.txt").
    o2qLogLine("ATO / AOA: " + pk + " OMS-2 planned and loaded").
}
FUNCTION o2qAtoInit {                        // at RUN: ops1q's hand-off -> the page, the solves, the burn the pick flies
    IF NOT EXISTS("0:/lib/lib_ascent_iload.ks") { RETURN. }
    LOCAL ho IS o2atHoRead().
    IF ho:LENGTH = 0 { RETURN. }
    LOCAL ph IS CHOOSE ho["ph"] IF ho:HASKEY("ph") ELSE "PRE".
    IF ph = "DONE" { RETURN. }
    RUNONCEPATH("0:/lib/lib_ascent_iload.ks").
    IF EXISTS("0:/lib/lib_aoa.ks") { RUNONCEPATH("0:/lib/lib_aoa.ks"). }
    LOCAL sn IS CHOOSE ho["site"] IF ho:HASKEY("site") ELSE "".     // the launch site (a VBG ATO's AOA solves for VBG)
    FOR st IN ASC_SITES { IF st["rtls"]["name"] = sn { SET ASC_RTLS_SITE TO st["rtls"]. } }
    SET o2qAto TO LEXICON("on", TRUE, "ho", ho, "ph", ph, "cols", 0, "x", 0, "why", "", "planned", "", "t", 0, "dvo", 0).
    LOCAL has IS FALSE.
    FOR sr IN o2qSrc { IF sr["file"] = "0:/oms1_plan.txt" AND sr["d"]["burn_ut"] > TIME:SECONDS - 60 { SET has TO TRUE. } }
    IF NOT has { SET o2qAto["ph"] TO "POST". }
    o2qAtoSolve().
    SET o2qPage TO "ATO".
    o2qAtoApply().
    o2qSay(o2qAtoSum(), "V").
}
FUNCTION o2qHoLog {                          // What ops2q took from ops1q's end (or from nothing), three lines in the log; reads only, sets and writes nothing else
    IF NOT O2Q_HO_LOG { RETURN. }
    LOCAL ao IS "undefined".
    IF DEFINED ASC_OPS2_AUTO { SET ao TO "" + ASC_OPS2_AUTO. }
    LOCAL ob IS SHIP:ORBIT.
    o2qLogLine("HANDOFF STATE: taken LIVE from the vessel (ops1q writes no state file); MET " + ROUND(MISSIONTIME, 1) + " ALT " + ROUND(SHIP:ALTITUDE) + " APO " + ROUND(ob:APOAPSIS) + " PERI " + ROUND(ob:PERIAPSIS) + " INC " + ROUND(ob:INCLINATION, 2) + " V " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " ASC_OPS2_AUTO " + ao).
    LOCAL pl IS "none".
    FOR sr IN o2qSrc {
        IF sr["file"] = "0:/oms2_plan.txt" AND pl = "none" {
            SET pl TO "0:/oms2_plan.txt " + sr["name"] + " (" + (CHOOSE sr["flown"] IF sr["flown"] <> "" ELSE "not flown") + ")".
            IF sr["d"]:HASKEY("dv") { SET pl TO pl + " DV " + ROUND(sr["d"]["dv"], 1). }
            IF sr["d"]:HASKEY("burn_ut") { SET pl TO pl + " CENTRE IN " + ROUND(sr["d"]["burn_ut"] - TIME:SECONDS) + " S". }
        }
    }
    o2qLogLine("HANDOFF PLAN: " + pl + "; loaded " + (CHOOSE o2qLoad["src"] + " (" + o2qLoad["file"] + ")" IF o2qLoaded() ELSE "nothing")).
    LOCAL ab IS "none (" + O2AT_HO_FILE + " absent, 1:/abort_mode.txt absent)".
    IF EXISTS(O2AT_HO_FILE) OR EXISTS("1:/abort_mode.txt") {
        SET ab TO "ATO hand-off (" + O2AT_HO_FILE + " " + EXISTS(O2AT_HO_FILE) + ", 1:/abort_mode.txt " + EXISTS("1:/abort_mode.txt") + ", page " + o2qAto["ph"] + ")".
    }
    o2qLogLine("HANDOFF ABORT: " + ab).
}
FUNCTION o2qAtoOms1Done {                    // OMS-1's cutoff (shuttle_exec's exAtoNext): the pick is asked of the real orbit now, OMS-2 planned for it
    SET o2qAto["ph"] TO "POST".
    o2atHoSet("ph", "POST").
    SET o2qAto["planned"] TO "".
    SET AOA_SOL TO 0.
    o2qAtoSolve().
    o2qAtoApply().
    o2qSay(o2qAtoSum(), "V").
}
FUNCTION o2qAtoEnd {                         // OMS-2 flown: the hand-off is over, the page row's slot is DEORB's again
    IF NOT o2qAto["on"] { RETURN. }
    SET o2qAto["ph"] TO "DONE".
    o2atHoEnd().
    IF o2qPage = "ATO" { SET o2qPage TO "MNVR". }
}
FUNCTION o2qPgAto {
    LOCAL pg IS o2PgNew().
    LOCAL c IS o2qAto["cols"].
    LOCAL ho IS o2qAto["ho"].
    LOCAL a IS c["ato"].
    LOCAL b IS c["aoa"].
    LOCAL pk IS o2qAtoPickNow().
    LOCAL lk IS o2qAtoLocked().
    LOCAL post IS o2qAtoPost().
    o2qHead(pg, "2025/", "ATO / AOA TGT", 0).
    // row 1: the cutoff's state, row 2: what ops1q passed
    LOCAL ha IS SHIP:ORBIT:APOAPSIS / 1000.
    LOCAL hp IS SHIP:ORBIT:PERIAPSIS / 1000.
    LOCAL vi IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL om IS 1000 * SHIP:MASS * (1 - CONSTANT:E ^ (-o2qAto["dvo"] / (ASC_OMS_ISP * CONSTANT:G0))).
    IF ho:HASKEY("ha") { SET ha TO ho["ha"]. }
    IF ho:HASKEY("hp") { SET hp TO ho["hp"]. }
    IF ho:HASKEY("vi") { SET vi TO ho["vi"]. }
    IF ho:HASKEY("oms") { SET om TO ho["oms"]. }
    o2Seg(pg, 1, 1, "MECO"). o2Seg(pg, 1, 8, "HA"). o2Read(pg, 1, 11, o2F(ha, 4, 0)). o2Seg(pg, 1, 16, "HP"). o2Read(pg, 1, 19, o2Sv(hp, 4, 0)). o2Seg(pg, 1, 24, "km").
    o2Seg(pg, 1, 29, "VI"). o2Read(pg, 1, 32, o2F(vi, 4, 0)). o2Seg(pg, 1, 37, "m/s"). o2Seg(pg, 1, 43, "OMS"). o2Read(pg, 1, 47, o2F(om, 4, 0)). o2Seg(pg, 1, 52, "kg").
    o2Seg(pg, 2, 1, "ABORT"). o2Read(pg, 2, 8, CHOOSE ho["why"] IF ho:HASKEY("why") ELSE "ATO").
    o2Seg(pg, 2, 29, "ops1"). o2Read(pg, 2, 35, CHOOSE ho["pick"] IF ho:HASKEY("pick") ELSE "-").
    o2Seg(pg, 3, 16, "ATO", CHOOSE "S" IF pk = "ATO" ELSE "L"). o2Seg(pg, 3, 30, "AOA", CHOOSE "S" IF pk = "AOA" ELSE "L").
    // the columns: ATO at col 16, AOA at col 30 (the canvas's two value columns)
    o2Seg(pg, 4, 1, "SITE"). o2Seg(pg, 5, 1, "TYPE").
    o2Read(pg, 4, 16, "---", "D"). o2Read(pg, 5, 16, "---", "D").
    IF b["ok"] {
        o2Read(pg, 4, 30, b["site"] + " " + b["rwy"]).
        o2Read(pg, 5, 30, b["type"] + (CHOOSE " RAMP" IF b["ramp"] ELSE "")). o2Seg(pg, 5, 41, "AUTO", "S").
    } ELSE { o2Read(pg, 4, 30, "---", "D"). o2Read(pg, 5, 30, "---", "D"). }
    o2Seg(pg, 6, 1, "OMS-1"). o2Seg(pg, 6, 8, "TIG"). o2Seg(pg, 7, 8, "DV"). o2Seg(pg, 8, 1, "OMS-2"). o2Seg(pg, 8, 8, "TIG"). o2Seg(pg, 9, 8, "DV").
    o2Seg(pg, 10, 1, "TOTAL"). o2Seg(pg, 10, 8, "DV").
    LOCAL cl IS LIST(a, b).
    LOCAL cx IS LIST(16, 30).
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL cc IS cl[k].
        LOCAL x IS cx[k].
        IF cc["ok"] {
            IF cc["dv1"] > 0 {
                o2Read(pg, 6, x, o2Met(o2qMetOf(cc["tig1"]))). o2Read(pg, 7, x - 1, o2F(cc["dv1"], 6, 1)). o2Seg(pg, 7, x + 6, "m/s").
            } ELSE { o2Read(pg, 6, x, "---/--:--:--", "D"). o2Read(pg, 7, x - 1, "  ----", "D"). }
            o2Read(pg, 8, x, o2Met(o2qMetOf(cc["tig2"]))). o2Read(pg, 9, x - 1, o2F(cc["dv2"], 6, 1)). o2Seg(pg, 9, x + 6, "m/s").
            o2Read(pg, 10, x - 1, o2F(cc["tot"], 6, 1)). o2Seg(pg, 10, x + 6, "m/s").
            o2Seg(pg, 11, x + 6, "kg"). o2Read(pg, 11, x - 1, o2F(cc["left"], 6, 0), CHOOSE "V" IF cc["go"] ELSE "Y").
        } ELSE {
            o2Read(pg, 6, x, "---/--:--:--", "D"). o2Read(pg, 7, x - 1, "  ----", "D"). o2Read(pg, 8, x, "---/--:--:--", "D"). o2Read(pg, 9, x - 1, "  ----", "D").
            o2Read(pg, 10, x - 1, "  ----", "D"). o2Read(pg, 11, x - 1, "  ----", "D").
        }
        o2Seg(pg, 15, x, CHOOSE "GO" IF cc["go"] ELSE "NO GO", CHOOSE "S" IF cc["go"] ELSE "Y").
        IF cc["why"] <> "" { o2Read(pg, 16, x, cc["why"], "Y"). }
    }
    o2Seg(pg, 11, 1, "OMS"). o2Seg(pg, 11, 8, "LEFT").
    o2Seg(pg, 12, 1, "ORBIT"). o2Seg(pg, 12, 8, "HA x HP").
    IF a["ok"] { o2Read(pg, 12, 16, o2Fx(a["ha"], 0) + " x " + o2Fx(a["hp"], 0)). } ELSE { o2Read(pg, 12, 16, "---", "D"). }
    o2Read(pg, 12, 30, "---", "D").
    o2Seg(pg, 13, 1, "ENTRY"). o2Seg(pg, 13, 8, "FPA"). o2Read(pg, 13, 16, "---", "D").
    o2Seg(pg, 14, 8, "LAND"). o2Read(pg, 14, 16, "---", "D").
    IF b["ok"] {
        o2Read(pg, 13, 29, o2Sg(b["fpa"], 6, 2)). o2Seg(pg, 13, 36, "deg").
        o2Read(pg, 14, 30, o2Met(o2qMetOf(b["land"]))).
    } ELSE { o2Read(pg, 13, 30, "---", "D"). o2Read(pg, 14, 30, "---", "D"). }
    o2Seg(pg, 15, 1, "STATUS"). o2Seg(pg, 16, 1, "WHY").
    // SELECT: ATO / AOA / AUTO; after OMS-1 a mode not GO is dim with its WHY on ENT; the pick that flies is named
    LOCAL dm IS LIST().
    LOCAL dw IS LIST("", "", "").
    IF post {
        IF NOT a["go"] { dm:ADD(0). SET dw[0] TO "ATO NO GO: " + a["why"]. }
        IF NOT b["go"] { dm:ADD(1). SET dw[1] TO "AOA NO GO: " + (CHOOSE o2qAto["why"] IF o2qAto["why"] <> "" ELSE b["why"]). }
    }
    o2Seg(pg, 17, 1, "SELECT").
    o2Choice(pg, "apick", 17, LIST(LIST(8, "ATO"), LIST(14, "AOA"), LIST(20, "AUTO")), NOT lk, dm, dw).
    o2Seg(pg, 17, 27, "FLIES " + pk, CHOOSE "D" IF lk ELSE "S").
    IF lk { o2Seg(pg, 17, 38, "LOCKED", "Y"). }
    o2Act(pg, "asolve", 18, 8, "SOLVE", NOT lk).
    o2Act(pg, "aload", 18, 18, "LOAD " + CHAR(8594) + " MNVR", NOT lk AND (post OR o2qLoaded())).
    o2qMsgRow(pg, 19).
    RETURN pg.
}

// ---- PDRS: the Canadarm's page. lib_o2arm.ks has the rows and the arm's inputs; arm.ks runs
// hosted while the page is shown: its own hold flies the orbiter (ops2q's DAP stands by) and ops2q's loop calls its pass every tick.
GLOBAL o2qPdrsDap IS FALSE.                  // ops2q's DAP was on when the arm came up (it flies again when the arm goes)
FUNCTION o2qPgPdrs {
    LOCAL pg IS o2PgNew().
    o2qHead(pg, "2011/094/", "PDRS CONTROL", 0).
    o2aPg(pg).
    o2qMsgRow(pg, 19).
    RETURN pg.
}
FUNCTION o2qPdrsGains {                     // The C# DAP flies the arm's attitude with the burn hold's gains while the arm is hosted (on), the orbit hold's back at ARM STOPPED (off)
    PARAMETER on.
    IF on {
        IF NOT O2Q_PDRS_GAINS OR NOT o2qDapOn OR NOT o2qDapCs { RETURN. }
        SET o2qDap["k"] TO O2Q_PDRS_K. SET o2qDap["tau"] TO O2Q_PDRS_TAU. SET o2qDap["ki"] TO 0. SET o2qDap["ui"] TO V(0, 0, 0).
        SET o2qPdrsGn TO TRUE.
        o2qDapPush().
        o2qLogLine("DAP PDRS GAINS: K " + O2Q_PDRS_K + ", TAU " + O2Q_PDRS_TAU + ", KI 0, DB " + o2qDap["db"] + " deg while the arm is hosted (the orbit hold's K " + O2D_K + ", TAU " + O2D_TAU + " are back at ARM STOPPED)").
    } ELSE IF o2qPdrsGn {
        SET o2qPdrsGn TO FALSE.
        SET o2qDap["k"] TO O2D_K. SET o2qDap["tau"] TO O2D_TAU. SET o2qDap["ki"] TO 0. SET o2qDap["ui"] TO V(0, 0, 0).
        o2qDapPush().
        o2qLogLine("DAP ORBIT GAINS BACK: K " + O2D_K + ", TAU " + O2D_TAU + " (the arm is not hosted)").
    }
}
FUNCTION o2qPdrsOpen {                       // TRUE: the arm is up
    IF O2A_ON { RETURN TRUE. }               // An AUTO kept it up off the page: the page just shows again
    IF o2qSeq <> "" { o2qSay("PDRS: NOT IN BURN", "Y"). RETURN FALSE. }
    LOCAL dapWas IS o2qDapOn.
    LOCAL ext IS o2qDapOn AND o2qDapCs.      // The C# DAP keeps the attitude in every mode
    IF ext {                                 // (TRACK too): arm.ks runs ARM_HOLD_EXT, it only holds the THC off the jets (FBWXOFF); FBW3 / FBWOFF are the DAP's to release, never the arm's
        LOCAL why IS o2aOpen(O2Q_HOLDS[ROUND(o2Val["hold"])], TRUE).
        IF why <> "" { o2qSay("PDRS: " + why, "Y"). RETURN FALSE. }
        o2qLogLine("PDRS: ARM UP (arm.ks hosted), the DAP keeps the attitude (" + o2qDap["mode"] + " " + o2qDap["hold"] + ")").
        o2qPdrsGains(TRUE).
        RETURN TRUE.
    }
    LOCAL hmd IS o2qPdrsHold().
    o2qDapStandby("PDRS: THE ARM'S HOLD FLIES (" + hmd + ", ORBIT / PTG'S HOLD)").
    LOCAL why IS o2aOpen(hmd).
    IF why <> "" {
        o2qSay("PDRS: " + why, "Y").
        IF dapWas { o2qDapResume("PDRS NOT OPENED"). }
        RETURN FALSE.
    }
    SET o2qPdrsDap TO dapWas.
    o2qLogLine("PDRS: ARM UP (arm.ks hosted), the DAP " + (CHOOSE "stands by" IF dapWas ELSE "was off")).
    RETURN TRUE.
}
FUNCTION o2qPdrsHold {                       // The arm's hold
    LOCAL md IS O2Q_HOLDS[ROUND(o2Val["hold"])].    // = ORBIT / PTG's HOLD; arm.ks has no TRACK: INRTL on the attitude then
    IF md = "TRACK" { o2qSay("PDRS: TRACK HELD AS INRTL", "Y"). RETURN "INRTL". }
    RETURN md.
}
FUNCTION o2qPdrsClose {
    PARAMETER why, resume IS TRUE.
    IF NOT O2A_ON { RETURN. }
    LOCAL hmd IS O2Q_HOLDS[ROUND(o2Val["hold"])].    // ORBIT / PTG's HOLD; the DAP takes it back after the arm
    o2aClose(why).
    o2qPdrsGains(FALSE).                     // The orbit hold's gains back before the DAP resumes / holds
    o2qLogLine("PDRS: ARM STOPPED (" + why + ")").
    IF resume AND o2qPdrsDap AND o2qDapOk {
        o2qDapResume(why).
        IF hmd <> "INRTL" { o2qDapHold(hmd). o2qLogLine("PDRS: THE DAP HOLDS " + hmd + " (ORBIT / PTG)"). }
    }
    SET o2qPdrsDap TO FALSE.
}

FUNCTION o2qBuild {
    IF o2qPage = "ATO" AND NOT o2qAtoShown() { SET o2qPage TO "MNVR". }
    IF o2qPage = "ATO" { RETURN o2qPgAto(). }
    IF o2qPage = "MNVR" { RETURN o2qMnvrBuild(). }
    IF o2qPage = "ORBIT" { RETURN o2qOrbitBuild(). }
    IF o2qPage = "OMS" { RETURN o2qPgOms(). }
    IF o2qPage = "PDRS" { RETURN o2qPgPdrs(). }
    IF o2qPage = "DEORB" { RETURN o2qPgDeorb(). }
    IF o2qPage = "FPLN" { RETURN o2qPgFpln(). }
    RETURN o2qPgBrn().
}

FUNCTION o2qMnvrBuild {                      // The MNVR page. C# (O2MNVR: kOS gathers the raw values, C# formats and lays out; the page equals o2qPgMnvr's, tests/o2mnvr_offline); any miss = o2qPgMnvr
    IF NOT O2Q_MNVR_CS { RETURN o2qPgMnvr(). }
    IF o2qMnvrCap < 0 {
        SET o2qMnvrCap TO CHOOSE 1 IF o2qFbwHas("O2MNVR") ELSE 0.
        o2qLogLine("MNVR PAGE: " + (CHOOSE "C# build (O2MNVR)" IF o2qMnvrCap = 1 ELSE "kOS build (no O2MNVR in KalsCoproc)")).
    }
    IF o2qMnvrCap <> 1 { RETURN o2qPgMnvr(). }
    LOCAL mr IS ADDONS:KALS:O2MNVR(o2qMnvrIn()).
    IF NOT mr:ISTYPE("Lexicon") {
        SET o2qMnvrCap TO 0.
        o2qLogLine("MNVR PAGE: C# build failed (" + mr + "), kOS builds from now on").
        RETURN o2qPgMnvr().
    }
    SET o2qDvB TO mr["dv"].
    RETURN mr["page"].
}

FUNCTION o2qOrbitBuild {                     // page 2: the ORBIT / PTG page. C# (O2ORBIT; the page equals o2qPgOrbit's, tests/o2orbit_offline); any miss = o2qPgOrbit
    IF NOT O2Q_ORBIT_CS { RETURN o2qPgOrbit(). }
    IF o2qOrbCap < 0 {
        SET o2qOrbCap TO CHOOSE 1 IF o2qFbwHas("O2ORBIT") ELSE 0.
        o2qLogLine("ORBIT PAGE: " + (CHOOSE "C# build (O2ORBIT)" IF o2qOrbCap = 1 ELSE "kOS build (no O2ORBIT in KalsCoproc)")).
    }
    IF o2qOrbCap <> 1 { RETURN o2qPgOrbit(). }
    LOCAL orr IS ADDONS:KALS:O2ORBIT(o2qOrbitIn()).
    IF NOT orr:ISTYPE("Lexicon") {
        SET o2qOrbCap TO 0.
        o2qLogLine("ORBIT PAGE: C# build failed (" + orr + "), kOS builds from now on").
        RETURN o2qPgOrbit().
    }
    RETURN orr["page"].
}

FUNCTION o2qDraw {
    LOCAL nav IS LIST("MNVR", CHOOSE "ATO" IF o2qPage = "ATO" ELSE "DEORB", "ORBIT", "OMS", "PDRS"):INDEXOF(o2qPage).
    o2NavSet(1, CHOOSE "ATO / AOA" IF o2qAtoShown() ELSE "DEORB").
    LOCAL ttl IS LEXICON("ATO", "ATO / AOA TGT", "MNVR", "MNVR EXEC", "DEORB", "DEORB TGT", "ORBIT", "ORBIT / PTG", "OMS", "OMS/RCS", "PDRS", "PDRS CONTROL", "BRN", "BRN PLN", "FPLN", "FPLN TREE").
    LOCAL gdp IS gpcDisp(gpcPageDisp(o2qPage)).      // The page's GPC: FROZEN = the last picture stays, X = the page blank under the big X (the keys and the title row stay)
    IF gdp = "FROZEN" { RETURN. }
    IF gdp = "X" {
        o2qGpcX(TRUE).
        o2DispBlank(ttl[o2qPage], nav).
        o2NavBang(fuiShown()).
        RETURN.
    }
    IF o2qXOn { o2qGpcX(FALSE). }
    SET o2InLock TO o2qInLock() <> "".          // INPUT RHC greyed while another reader has the stick
    LOCAL gm IS CHOOSE "TYPE" IF o2Typ ELSE o2qInEff().
    LOCAL pdrs IS o2qPage = "PDRS".           // the pad's CUT OFF slot is split in two (EE CAM + STOP) on this page
    LOCAL csOk IS o2CsOk(pdrs).                  // an older KalsCoproc has no drop-down list in its draw: kOS draws while one is open and one frame after
    LOCAL csDone IS FALSE.
    IF csOk { SET csDone TO o2CsDraw(o2qPg, ttl[o2qPage], nav, gm, o2Typ, o2StepTxt(o2qPg), o2qArmed, o2qSeq <> "", CHOOSE o2aCamOn() IF pdrs ELSE o2qSeq = "BURN", pdrs). }
    IF NOT csDone {
        LOCAL rr IS o2Render(o2qPg).         // kOS draws (KalsCoproc without O2DRAW, or it failed)
        o2DispPage(ttl[o2qPage], nav, rr).
        o2DispGrid(gm, o2Typ, o2StepTxt(o2qPg), o2qArmed, o2qSeq <> "", CHOOSE o2aCamOn() IF pdrs ELSE o2qSeq = "BURN", pdrs).
    }
    IF o2qPage = "ORBIT" { o2qView(o2qLoadedConic()). }
    ELSE IF o2qPage = "BRN" { o2qView(CHOOSE o2qBrn["el"] IF o2qBrn["ok"] ELSE LEXICON()). }
    ELSE IF o2qPage = "MNVR" { o2SprFrom(o2qDvBar()). }
    ELSE IF o2qPage = "OMS" { o2SprFrom(o2qOmsGfx()). }
    ELSE IF o2qPage = "DEORB" { o2qDbDraw(). }   // the globe (C# O2GLB, else the dots)
    ELSE { o2SprFrom(0). }
    o2NavBang(fuiShown()).                   // the "!" lit while the FAILURES window is open
    o2qDdHelpOff().
}

// MNVR EXEC's DV slider on rows 5-6, in the look of the ascent page's VI abort bar: o2_bg/dvbar.png is the static
// part (DV, the 0 end, a 2 px green line, the 0 and CO ticks, CO, m/s), the number at the total's end and the gained readout
// are text sprites, the yellow pointer o2_bg/dvtri.png (its tip on the line) sits at gained / total. Page px: the geometry
// of the page design (the .ln box starts at x 14, row 5 at y 115). o2qDvBar returns the slots used.
// the line's x / length / y and the pointer's placement are lib_o2disp.ks's O2_DV_* / o2DvPtr (measured off the sprites)
FUNCTION o2qDvBar {
    IF o2qDvB:LENGTH = 0 { RETURN 0. }
    LOCAL tot IS o2qDvB[0].
    LOCAL got IS o2qDvB[1].
    o2SprPut(0, "dvbar", O2_DV_BX + 300, O2_DV_BY + 21).
    LOCAL ts IS o2Fx(tot, 1).
    o2SprTxt(1, "<size=10>" + ts + "</size>", 14 + 477 + ts:LENGTH * 3 + 1, O2_DV_Y, "#3ce03c", ts:LENGTH * 6 + 6).
    LOCAL gs IS o2Fx(got, 1).
    o2SprTxt(2, "<size=14>" + gs + "</size>", 14 + 548 - gs:LENGTH * 4.2, O2_DV_Y, "#a6f8a6", gs:LENGTH * 9 + 6).
    o2DvPtr(3, tot, got).
    RETURN 4.
}

IF NOT (DEFINED O2Q_MNVR_CS) { GLOBAL O2Q_MNVR_CS IS TRUE. }   // The MNVR page built in C# (ADDONS:KALS:O2MNVR); FALSE = ops2q.ks builds it (a job file sets it before the RUN, SAIL A/B)
GLOBAL o2qMnvrCap IS -1.                     // -1 not asked yet, 0 no O2MNVR suffix / failed once (kOS builds), 1 C# builds
IF NOT (DEFINED O2Q_ORBIT_CS) { GLOBAL O2Q_ORBIT_CS IS TRUE. }   // page 2: the ORBIT / PTG page built in C# (ADDONS:KALS:O2ORBIT); FALSE = ops2q.ks builds it (a job file sets it before the RUN)
GLOBAL o2qOrbCap IS -1.                     // -1 not asked yet, 0 no O2ORBIT suffix / failed once (kOS builds), 1 C# builds
IF NOT (DEFINED O2Q_WAKE_CS) { GLOBAL O2Q_WAKE_CS IS TRUE. }   // The wait poll (O2WAKE) + the heartbeat / DAP feed (O2TICK) in C#; FALSE = the kOS polls (a job file sets it before the RUN, SAIL A/B)
GLOBAL o2qWakeCs IS FALSE.
GLOBAL o2qK IS 0.                            // ADDONS:KALS when o2qWakeCs
IF O2Q_WAKE_CS AND o2qFbwHas("O2WAKE") AND o2qFbwHas("O2WAKESET") AND o2qFbwHas("O2TICK") AND o2qFbwHas("O2DAPALIVE") { SET o2qK TO ADDONS:KALS. SET o2qWakeCs TO TRUE. }
// ---- the run
cwuiClose().                                // CLEARGUIS disposes the C&W window; cwuiMade must go FALSE or cwuiInit never rebuilds it (cwuiStart below re-arms)
CLEARGUIS().
IF SOCK_LOG { SET o2qLog TO logFree("0:/logs/ops2q_" + ROUND(TIME:SECONDS), ".txt"). o2qLogLine(SCRIPT_VERSION). SET FL_LOG TO o2qLog. SET o2ClickLog TO o2qLog. } ELSE { SET FL_LOG TO "". }   // The failures' lines
{
    LOCAL el IS SHIP:ORBIT.
    o2Handed(o2qRv(), SHIP:VELOCITY:ORBIT, o2qNorth(), el:INCLINATION).
}
o2qDefs().
o2qOmsInit().
o2qFailInit().
o2qVernSet(FALSE, FALSE).                  // the RCS at full thrust (a re-RUN after a VERN that was cut short)
o2qInInit().
o2bRead().                                  // the burns flown before this RUN (1:/o2q_burn.txt)
o2flInit().                                  // the flight-plan tree: our saved burns back from 1:/o2q_fpln.txt
o2flLoad(o2qMu(), o2qNorth(), o2qEqx()).
o2qReadSrc().
IF o2qSrcArg <> "" {
    FROM { LOCAL i IS 0. } UNTIL i >= o2qSrc:LENGTH STEP { SET i TO i + 1. } DO {
        IF o2qSrc[i]["file"] = o2qSrcArg { o2qLoadSrc(i). }
    }
}
o2qRerunLoad().
o2qAtoInit().                               // ops1q's hand-off: the ATO / AOA page opens first (before OMS-1)
o2qHoLog().                                 // The hand-off lines (log only)
IF o2qPageArg = "DEORB" AND NOT o2qAtoShown() { SET o2qPage TO "DEORB". o2qLogLine("PAGE DEORB (RUN DEORBIT_PLAN)"). }
// the OMS and RCS lamps, once a second: LEFT / RIGHT OMS (an engine out: WARNING in a lit burn, CAUTION at rest), OMS PRPLT (the
// lower tank under 10 / 3 %, the fuel / oxidizer spread, the loaded burn's dV against what the propellant gives), FWD / LEFT / RIGHT RCS
// (a pod's propellant under 20 / 5 %, a pod with every module off), RCS JET (jets working of a pod): lib_cwchk's cwOmsApply / cwRcsApply
// FLT CNTL = the DAP's attitude error in a HOLD (cwDapApply), GUID = a burn missed at TIG / the cutoff residual (cwOrbGuid, cwResidual in o2qSeqEnd)
GLOBAL o2qCwDap IS LEXICON().
GLOBAL o2qCwGd IS LEXICON().
FUNCTION o2qCwChk {
    PARAMETER ut.
    cwDapApply(o2qCwDap, ut, o2qDapOn, o2qDap["act"], o2qDap["ea"], o2qDap["db"], o2qSeq <> "" AND o2qB:HASKEY("lit") AND o2qB["lit"]).
    cwOrbGuid(o2qCwGd, ut, o2qSeq, o2qSeq <> "" AND o2qB:HASKEY("lit") AND o2qB["lit"], CHOOSE o2qB["ig"] IF o2qSeq <> "" AND o2qB:HASKEY("ig") ELSE ut).
    cwRcsApply(o2qRcsRead()).
    LOCAL fu IS -1. LOCAL ox IS -1.
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL en IS o2qOmsEng(k).
        IF fu < 0 AND o2qIsEng(en) { SET fu TO o2qEngTank(en, FALSE). SET ox TO o2qEngTank(en, TRUE). }
    }
    LOCAL dvn IS 0. LOCAL dvb IS 0.
    IF o2qLoaded() AND DEFINED ASC_OMS_ISP { SET dvn TO o2qDvTot(). IF dvn > 0 { SET dvb TO omsDvOnBoard(). } }
    cwOmsApply(o2qOut[0], o2qOut[1], o2qSeq = "BURN", fu, ox, dvb, dvn).
}
cwCheck("SYS", o2qCwChk@, 1).
o2DispInit().
cwuiStart().                                // its trigger: the window, the flash, the tone and the checks every tick
SET o2qPg TO o2qBuild().
o2qDraw().
o2DispShow().
o2qDapStart().
o2qKeysStart().
WHEN TRUE THEN {
    IF o2qWakeCs AND o2qHoldOk = 1 AND NOT o2qQuit {   // The heartbeat and the DAP watchdog feed in ONE C# call (O2TICK); this trigger carries the DAP feed too then
        LOCAL o2qFeed IS o2qDapCs AND o2qDapOn.
        LOCAL o2qAlv IS o2qK:O2TICK(o2qHoldUp(), o2qFeed).
        IF o2qFeed { SET o2qDapAl TO o2qAlv. }
    } ELSE {
        o2qHold().
        IF o2qWakeCs AND o2qDapCs AND o2qDapOn AND NOT o2qQuit { SET o2qDapAl TO o2qK:O2DAPALIVE. }
    }
    RETURN NOT o2qQuit.
}   // The OMS interlock heartbeat, every physics tick
o2qLogLine("WAKE: " + (CHOOSE "C# (O2WAKE / O2TICK)" IF o2qWakeCs ELSE "kOS polls")).
o2qLogLine(SCRIPT_VERSION + ": the window is up (close: ABORT the program with Ctrl+C; the DAP lets go, SAS stays off)").   // log only: not on the terminal
UNTIL o2qQuit {
    IF DEFINED SAIL_ON { IF SAIL_ON { sailMain(). } }   // SAIL's kos lines (EXEC ...) run here, in the program's own loop, not in the tick trigger (neutral when SAIL_ON is FALSE)
    o2qKeys(o2DispTake()).                   // the window's presses with the keys (a Space / Enter echo dropped)
    o2qRhc().
    o2qAg4Type().
    o2qAgCtrl().
    IF PX_ON { pxTick(). }                   // PROX OPS's keep-alive + state (the DLL's watchdog)
    IF O2A_ON { o2aTick(). }                 // arm.ks's pass every iteration (every physics tick while the page is up)
    IF O2A_ON AND o2qPage <> "PDRS" AND NOT o2aAutoOn() { o2qPdrsClose("AUTO DONE OFF PAGE"). }   // The AUTO ended off the page: the arm stops, the DAP's hold comes back
    LOCAL o2qSlow IS NOT O2A_ON OR o2qDue().   // the rest of the cycle at O2Q_DT as before (the arm's page redraws then too)
    IF o2qSlow {
    o2qOmsWatch().
    o2qXferTick().
    o2qP4Sync().
    o2qP8Sync().
    o2qSeqTick().
    o2qWarpGuard().   // a warp toward a loaded burn steps down
    o2qRailsHoldTick().   // O2Q_RAILS_HOLD
    o2qDapTick().
    IF o2qSeq = "ALIGN" OR o2qSeq = "AIM" OR o2qSeq = "NULL" OR o2qSeq = "FINE" OR o2qSeq = "WARP2" OR o2qSeq = "SETTLE" OR o2qSeq = "BURN" { o2qBurnRef(). }
    o2qPvTick().    // DEORB TGT's pass preview, one cycle after its page says COMPUTING
    o2qPrTick().    // Principia's flight plans into the FPLN tree (read only)
    o2qNbPoll().    // a finished n-body solve into BRN PLN
    SET o2qPg TO o2qBuild().
    o2qDraw().
    SET o2qPassT TO TIME:SECONDS.
    SET o2qPassRate TO KUNIVERSE:TIMEWARP:RATE.
    IF o2qWakeCs { o2qK:O2WAKESET(o2qPassT, o2qPassRate, O2Q_DT). }
    }
    WAIT UNTIL o2qInWait().   // O2Q_DT, or at once on an input (was WAIT O2Q_DT)
}
o2qHoldOff().                               // The OMS interlock off (ops3q and the rest fly the throttle as before)
pxOff("OPS2 ENDS").                       // PROX OPS off, the DLL lets go
o2qPdrsClose("OPS2 ENDS", FALSE).          // the hosted arm stopped, its hold off
IF o2qDapOn { o2qDapStandby("OPS2 ENDS"). }   // the axes back at once (else C#'s watchdog)
o2qKeysEnd().
IF o2qVern["on"] { o2qVernSet(FALSE, FALSE). }   // the RCS back to full thrust
fuiClose().
cwuiClose().
o2DispClose().
progReset().   // No hook of this program outlives it (lib_progreset)
IF o2qNext <> "" { RUNPATH("0:/" + o2qNext + ".ks"). }   // OPS3 -> ops3q, the window closed first
progReset().   // No hook of this program outlives it (lib_progreset)
