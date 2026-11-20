// arm.ks -- the Canadarm controller, SINGLE mode: one joint at a time, as the RMS's SINGLE (joint select + drive).
// arm_body.ks : this is the Canadarm controller itself. RUN arm runs arm.ks, the stub, which
// prints 'use ops2q' alone and runs this file only when ops2q's PDRS page hosts the arm (ARM_HOST TRUE).
// RUN arm. The window lists the joints from the shoulder out (the RMS's names; a 7-joint KerboArm has a roll on the
// upper arm the RMS does not have) with each joint's commanded angle. Pick a joint (its button; another button picks
// that joint, the same button again releases it: no joint, the THC drives nothing; a pick during a drive locks the
// driven joint at once), then drive it with the THC's
// up/down axis (SHIP:CONTROL:PILOTTOP, or the total FBWXPILOT hands over while the hold's intercept is live, so Advanced
// Fly-By-Wire's THC axes count too: + drives the target angle up, - down) at the RATE: COARSE ARM_RATE_C or
// VERNIER ARM_RATE_V deg/s. The THC translates nothing while the hold keeps it off the jets (below, ARM-STAB, with the
// KalsCoproc.dll that has FBWXOFF); without that, RCS must be off (the THC would translate the orbiter): RCS on inhibits it.
// The joint is unlocked while driven and locked again once it has stopped; the joint's 'current angle' field is not
// used (arm_motion read 0 on every joint, at any angle). The joint's real turn is measured from the parts (the servo
// in its parent's frame and the next part in the servo's: some joints move the servo part itself, some the next part)
// and the target is held when it runs more than ARM_STALL deg ahead of it (STALL: the joint does not follow).
// A deviation: the rates are this arm's (the RMS's SINGLE rates not modelled); no soft stops beyond the part's own.
// The autostrut (the end effector and the elbow keep it ON for launch, on again at stow):
// an autostrutted arm part holds the arm like the RMS's retention latches (that elbow does not move, the shoulder only
// flexes). At the start, and again before each drive starts, lib_arm's larAsOff turns it OFF on every arm part through
// KalsCoproc's ASTRUT, and no joint drives while one is still on (AUTOSTRUT ON). Without ASTRUT (an older
// KalsCoproc.dll) the pilot turns it off in the parts' menus and confirms with STRUTS OFF BY HAND; until then no drive.
// MAN AUG (the aft-station view, the rates): the THC flies the end effector's node in
// the orbiter's frame as seen from the aft flight deck facing aft (H aft / N forward, J the operator's left = starboard /
// L port, THC up out of the bay / down into it; lib_arm LAR_THC_SIGN (the up / down sign flipped): the status line names the
// direction), COARSE 0.15 m/s or VERNIER x 0.25, the end effector's attitude held. Each tick lib_arm solves the six RMS
// joints (all six; the 6 x 6 solve is damped near a singularity) for that velocity from the live parts and scales every joint together to 4 deg/s (RATE
// LIMITED); damping near a singularity (SINGULAR). The joints unlock while the THC is held and lock in detent once it is
// released. Allowed only with the elbow's target above LAR_AUG_ELBOW (unstow first in SINGLE), RCS off (unless the hold
// keeps the THC off the jets, ARM-STAB) and the struts off; a joint button leaves it. SOFT STOP (a joint LAR_SOFT inside its range end) holds the arm until the THC is
// released; STALL (a joint ARM_STALL behind its target) or MODEL (the node's move over ARM_AUG_WIN s misses the one asked
// for, or the attitude drifts ARM_AUG_ATT deg: a wrong joint sign, the elbow's being predicted) leave MAN AUG.
// THE DRIVE (damped joints, MAN AUG steps smooth and free of overshoot and ringing): with
// KalsCoproc's ARMDRIVE (ARM_DLL) every joint's command is moved by C# every physics tick, unrounded (coproc/ArmDrive.cs):
// SINGLE / MAN AUG / OPR CMD / the CAPTURE line hand it rates (ARMRATE: two smoothing stages, no step in rate), AUTO hands
// it each leg (ARMGOTO: minimum jerk, or a cruise blended over LAR_GOTO_TB s), and ARMDAMP sets each joint's damper for
// ARM_ZETA on the inertia outboard of it (at RUN and at each dock / undock). A STALL is a joint trailing the drive's command
// NOW past larStallAl (the stall margin + its rate's lag) for LAR_STALL_T. Without the DLL (or ARM_DLL FALSE) the kOS path
// as it was without the drive (whole-degree targets), with the same stall rule.
// STOP ends it with every joint it drove locked and its traverse rate as it was; at the stow pose (every joint's target
// at the craft's stow angle) larAsStow puts the end effector's and the elbow's autostrut back ON. Logs 0:/logs/arm_<t>.txt.
// MAN AUG rotation and END EFF (the RHC through the OMS gimbal with the orbiter's torque off): the RHC turns the end effector about its node at COARSE 8 deg/s (LAR_W_AUG; the joints' LAR_QD_MAX 8 is the ceiling), VERNIER 3 (the old COARSE),
// as seen from the aft station (pitch up tips its aft-pointing axis up, yaw right swings it to port, roll right; lib_arm
// LAR_RHC_SIGN); THC and RHC together fly both. STICK (pressed at the start when ARM_RHC is "STICK"): the stick is read off
// the OMS gimbal (SHIP:CONTROL:PILOTPITCH etc. read 0 here), the gimbal unlocked, and every reaction wheel's authority goes
// to 0 so the stick does not also turn the orbiter; both are put back when STICK is released or MAN AUG ends. Whether the
// wheels at 0 stop the stick turning the orbiter is NOT YET SEEN (the probe, Flight Checklist: the log's "the orbiter turns"
// lines); SAS on, a wheel left able to turn, or no OMS gimbal inhibit the stick (the status says why). THC ROT is the
// fallback (the TRANS / ROT switch at ROT): the THC turns the end effector (I pitch up, L yaw right, H roll right), the stick
// not read. END EFF (the FRAME list): the THC and RHC in the end effector's frame, as seen along the LEE's boresight (H
// forward along it, L right, I up; the LEE's TOP as up is predicted); ORB UNL the default. A turn the arm does not make (the end
// effector's measured turn misses the asked-for one, lib_arm larModelBadW) leaves MAN AUG (MODEL (TURN)).
// AUTO: stored poses flown in joint space. STOW, PRE-CRADLE (the arm
// just clear of its cradles) and READY (unstowed, MAN AUG's start) fly to that pose; AUTO 1 (UNSTOW: PRE-CRADLE, READY),
// AUTO 2 (STOW: READY, PRE-CRADLE, STOW), AUTO 3 and AUTO 4 (the operator's) fly a sequence; GO flies the saved pose picked
// in the list. SAVE writes the joints' targets to 0:/arm_poses.json as the next "POSE n" (and adds it to AUTO 3 or AUTO 4
// when the list beside it says so); the file's own AUTO n replaces the default. The path is lib_arm's larSafePath: a folded
// arm leaves through PRE-CRADLE and READY, STOW is reached from READY through PRE-CRADLE, and the cradle legs (STOW <->
// PRE-CRADLE) fly at VERNIER. Each leg moves every joint on a straight line in joint space, all arriving together, the
// fastest at 4 deg/s (VERNIER x 0.25). The ramp holds while a joint runs ARM_STALL behind its target and the leg stops
// (STALL) after ARM_AUTO_STALL_T s of it; the joints lock at each waypoint. Each waypoint logs the node against lib_arm's
// prediction with the elbow's predicted sign and with it flipped (answered by any AUTO move of the elbow).
// The pressed button released, a joint picked or STOP halts AUTO with the joints locked; at STOW the autostrut goes back
// on (larAsStow). Not with a SINGLE drive or MAN AUG on (the RCS may be on: the THC is not read).
// GRAPPLE (a grapple-fixture payload in the bay): GRAPPLE (pressed)
// shows the page: the fixture (the target when it is a docking port, else the nearest HT-FRGS fixture within 98 ft, lib_arm
// larFixtures) as the end effector sees it, in feet and inches: its range along the boresight and
// the closing rate, its offset right / up, the END EFF stick's pitch / yaw / roll that align with it, the node off its axis.
// Fly MAN AUG (END EFF) to within 2 ft of the fixture, 3.9 in of its axis and 10 deg of it, then CAPTURE: the arm flies
// the node along the fixture's axis at 0.02 m/s to the fixture's node, holding the node on the axis and the boresight
// along it (lib_arm larLineTick; the reference waits for a lagging arm); off the axis 0.15 m or 15 deg, a SOFT STOP or a
// STALL stops it. On "Acquire" the joints lock and the magnets close the gap; on "Docked" CAPTURE ends and the arm is
// LOADED: the chain is found again (a different chain stops every motion: STOP and RUN arm again) and every rate (SINGLE,
// MAN AUG, AUTO, the joints' cap) is scaled by lib_arm larLoadScale of the payload's mass (the parts hanging on the LEE).
// Docked with no fixture beneath the LEE (a payload still held in the bay) is LATCHED: no motion until it is free. A dock
// by any means (MAN AUG flown in by hand too) ends MAN AUG, AUTO and a SINGLE drive. RELEASE undocks (DOCKINGPORT:UNDOCK,
// then the module's own undock event after 3 s) and backs the node 0.5 m off along the boresight at VERNIER, the attitude
// held. CAPTURE or RELEASE released, a joint picked or STOP halts it with the joints locked; MAN AUG and AUTO wait for it.
// EE CAM: pressed, it
// snaps the flight camera to the end effector's view (kOS StockCamera 0.3.1's FREECAMERA, as the HUD's eye): the eye at the
// LEE's docking node, looking along its boresight with its TOP up (lib_arm larCamPose). That is END EFF's view: the THC's H
// moves the node into the picture, L right, I up, and GRAPPLE's RIGHT / UP are the fixture's place in it. The camera is
// anchored to the LEE (the addon keeps the pose in the part's own space), so it rides the end effector as the arm moves.
// Released, or STOP, gives the view back to the stock camera (the addon restores it and its FOV); the IVA view takes it back
// too (the button released). Without the addon's FREECAMERA the button is refused. Should the script stop on an error with
// the view on the LEE, SET ADDONS:CAMERA:FREECAMERA:ENABLED TO FALSE. at the terminal gives it back.
// THE ORBITER'S ATTITUDE HOLD (INRTL on at the start, LVLH / FREE by button; the RCS holds it and the stick inputs do not go straight
// through): the HOLD row's INRTL (the attitude fixed in
// inertial space), LVLH (fixed against the local vertical and the orbit, turning at orbital rate) or FREE (free drift: no
// jet); one is pressed, a press takes the attitude the orbiter has then (the pressed mode pressed again takes it again).
// At RUN arm: SAS off, RCS on, INRTL on the attitude it has. The hold flies through KalsCoproc's fly-by-wire handler, as
// the DAP's do: ADDONS:KALS:FBW3 every tick puts the hold's command on the vessel's pitch / roll / yaw ALONE (FREE: 0), so
// the RHC and the rotation keys never reach the jets or the wheels; FBWXOFF holds the translation at 0, so the THC and its
// keys translate nothing (kOS's PILOT* read the keyboard before the handler; AFBW's axes are added inside it: the arm reads
// the keyboard's PILOT* and, while FBWXOFF is live, the total the handler was handed, ADDONS:KALS:FBWXPILOT). The law (lib_arm
// larHold*): the real DAP's VERN-style phase plane, LAR_HOLD_DB deg attitude deadband, at most LAR_HOLD_RATE deg/s back,
// LAR_HOLD_RDB deg/s rate deadband, the jets' command capped so the orbiter's angular acceleration (its load on the arm)
// stays <= LAR_HOLD_ACC deg/s2. The arm's references are in the shoulder's frame, so the orbiter's turn moves no end
// effector. STICK reads the pilot's stick as FBWPILOT (under FBW3 the OMS gimbal shows the hold's command); C2 (the wheels at
// 0 in STICK) stays: the hold then flies on the RCS alone. STOP: the axes and the translation back to the pilot (FBWOFF),
// RCS and SAS back as they were. Without FBW3 (no KalsCoproc) no hold; with FBW3 but no FBWXOFF (an older DLL) the hold
// flies on what is on (RCS left as it was) and RCS on still inhibits the THC's drives.
// THE FRAMES AND OPR CMD: the list beside MAN AUG picks its frame, the
// RMS's four: ORB UNL (the orbiter's axes from the aft station, at the node), END EFF (the end effector's, along the LEE's
// boresight, at the node), ORB LD (the orbiter's axes at the payload's point of resolution) and PL (the payload's axes, the
// grapple fixture's, at its point of resolution). The POR is the payload's centre of mass (lib_arm larLoadCom, found as it
// is weighed): the THC moves it, the RHC turns the payload about it. ORB LD and PL only LOADED (refused, the frame back to
// ORB UNL / END EFF; an undock puts it back too). A frame change while MAN AUG moves locks the joints; the next THC / RHC
// input takes the references again in the new frame. The POSE line shows the POR (the node; the payload's in ORB LD / PL):
// X aft, Y starboard, Z up from the shoulder (ft), and its attitude P / Y / R (deg: the end effector's view, the PL frame's
// in ORB LD / PL, against the aft-station view: 0 / 0 / 0 = the boresight aft, its top out of the bay; pitch, yaw, roll in
// that order about the moving axes, as the RHC's signs). OPR CMD (the RMS's operator commanded auto sequence): key X / Y / Z
// and P / Y / R (LOAD copies the pose now), then OPR CMD flies the POR on a straight line while its attitude turns about one
// axis, both arriving together, at MAN AUG's rates (COARSE 0.98 ft/s; the OPR turn rate LAR_W_COARSE; VERNIER x 0.25, LOADED x the load's
// share). The line waits while the arm lags (HELD; ARM_OPR_HELD_T s of it stops OPR CMD); a SOFT STOP, a STALL or MODEL (the
// node's move misses the one asked for) stops it; a node end farther than lib_arm's LAR_REACH_SHARE of the arm's reach from
// the shoulder pitch pivot is refused (OUT OF REACH). It has ARRIVED with the POR within 0.4 in and 0.5 deg of the pose
// (else NOT SETTLED ARM_OPR_SETTLE_T s after the line's end); the joints lock. Released, a joint picked, STOP or a dock halts
// it. Not with MAN AUG, AUTO, CAPTURE / RELEASE or a SINGLE drive on. MAN AUG's status line shows its rate in FT/S.
// The arm is found by lib_arm (larEnds: the end effector = a LEE, else another docking port that is not a grapple fixture,
// with a servo within 3 parents; larChain: the chain by PARENT); ARM_N picks one of several (1 = first).
@LAZYGLOBAL OFF.
RUNONCEPATH("0:/lib/lib_arm.ks").
IF NOT (DEFINED ARM_N) { GLOBAL ARM_N IS 1. }
IF NOT (DEFINED ARM_RHC) { GLOBAL ARM_RHC IS "STICK". }   // MAN AUG's STICK pressed at the start ("STICK", C2), else not
IF NOT (DEFINED ARM_HOST) { GLOBAL ARM_HOST IS FALSE. }   // TRUE = hosted by ops2q's PDRS page: no window shown, the loop body is ARM_CYCLE (ops2q calls it), STOP is ARM_END
GLOBAL ARM_RATE_C IS 4.          // deg/s: COARSE (x2, was 2; the part's own limit is 10, LAR_QD_MAX 8)
GLOBAL ARM_RATE_V IS 1.          // deg/s: VERNIER (x2, was 0.5)
GLOBAL ARM_RATE_C_WR IS 10.      // deg/s: the WRIST ROLL's COARSE
GLOBAL ARM_RATE_BOOST IS 8.      // deg/s: SINGLE COARSE with THC FORWARD held (half = 6, full = 8) on every joint but the WRIST ROLL
GLOBAL ARM_GOTO_TOL IS 0.2.      // deg: a typed SINGLE slew (the PDRS page's TYPE on the picked joint) stops this close to its target
GLOBAL ARM_GOTO_K IS 2.             // 1/s: a typed SINGLE slew steers its STOP POINT (the joint's stop with its input off) onto the target at this rate
GLOBAL ARM_GOTO_MIN IS 0.05.        // deg/s: a typed slew's input below this is 0 (the drive ends)
GLOBAL ARM_LOCK_LOADED IS FALSE. // TRUE = a LOADED arm locks its joints as before; FALSE = a LOADED arm engages NO joint lock (a lock snapped the payload to another pose): each joint then holds its target on the servo's own drive (the C# drive's Th / the damper armDamp set for the loaded subtree)
GLOBAL ARM_STALL IS 2.           // deg: the target at most this far ahead of the joint's measured turn
GLOBAL ARM_DB IS 0.5.            // the THC's input past this drives
GLOBAL ARM_STILL IS 0.02.        // deg a tick: the joint has stopped (then locked)...
GLOBAL ARM_STILL_T IS 3.         // s: ...or this long after the drive ended
GLOBAL ARM_AUG_MARGIN IS 0.5.    // deg/s: MAN AUG sets each joint's traverse rate to its rate + this
GLOBAL ARM_AUG_WIN IS 1.         // s: the model check's shortest window (longer until the ask clears the steps: lib_arm larModelDue)
GLOBAL ARM_AUG_ATT IS 2.         // deg: the attitude drift that stops MAN AUG (MODEL), + the arm's resolution (larQRes)
GLOBAL ARM_REL_BACKOFF IS FALSE.  // RELEASE undocks the end effector and stops (the arm holds its pose); TRUE = the old back-off of LAR_REL_D along the boresight after the undock (dormant)
GLOBAL ARM_AUG_ATT_LD IS 6.      // The same while LOADED with ARM_LOCK_LOADED FALSE: no joint lock, each joint on the servo's drive, so a 3 t payload sags the attitude ~0.3 deg/s (the arm_75458 run: 2.3 / 2.4 deg 6 s into a loaded MAN AUG OUT, the unloaded 13 windows clean)
// While LOADED every joint is
// UNLOCKED on the C# drive (a locked joint under a payload stays wherever it is pushed: arm_75697 SHOULDER PITCH -28 -> -15 deg in one elbow slew, WRIST PITCH 4 deg off
// for 50 s; an unlocked, driven joint tracked within 0.5 deg) and a joint off its command on its MEASURED angle is pulled back at ARM_LDH_K x the error, at
// most ARM_LDH_R deg/s (no snap), the whole correction at most ARM_LDH_MAX deg; the correction rides on every ARMRATE of the pass, the commands kOS reads stay the pure ones
GLOBAL ARM_LDH_ON IS TRUE.       // FALSE = only a joint driven since the dock is unlocked, the rest stay locked
GLOBAL ARM_LDH_K IS 0.3.         // 1/s: the correction rate per deg of error
GLOBAL ARM_LDH_R IS 0.4.         // deg/s: the most a joint is pulled back
GLOBAL ARM_LDH_MAX IS 6.         // deg: the most the written command may lead the commanded one (the measured angle's own bias is not chased further)
GLOBAL ARM_LDH_DB IS 0.15.       // deg: an error inside this is left alone (the measurement's noise)
GLOBAL ARM_LDH_ZERO IS TRUE.     // the measured zero: a joint that sits still (ARM_LDH_ZB deg for ARM_LDH_ZT s) on its drive is taken to be AT its command (the dock locked it up to ~2 deg off the command: arm_75697 SHOULDER PITCH); only deviations after that are pulled back
GLOBAL ARM_LDH_ZB IS 0.1.        // deg: still = the measured angle within this
GLOBAL ARM_LDH_ZT IS 4.          // s
IF NOT (DEFINED ARM_DAMP) { GLOBAL ARM_DAMP IS LAR_DAMP. }   // the joints' damping while the arm runs (0-200; back at STOP)
IF NOT (DEFINED ARM_DLL) { GLOBAL ARM_DLL IS TRUE. }       // the joints driven by KalsCoproc every physics tick (FALSE: kOS)
IF NOT (DEFINED ARM_ZETA) { GLOBAL ARM_ZETA IS 0.9. }      // the damping ratio the C# drive sets on each joint (0: ARM_DAMP)
IF NOT (DEFINED ARM_TAU) { GLOBAL ARM_TAU IS LAR_TAU. }    // s, the commands' smoothing (no step in rate: no ring)
GLOBAL ARM_AUG_LOCK IS 1.        // s: the joints lock this long after the THC is released (the drive stops them then; with ARM_AUG_NOLOCK nothing is locked)
GLOBAL ARM_AUG_NOLOCK IS TRUE.   // MAN AUG never locks a joint, at the detent or at its end: each joint holds its target on the servo's own drive (the C# drive's Th / the kOS target field), as a LOADED arm does. The other modes lock as before
GLOBAL ARM_AUG_IPU IS 2000.      // CONFIG:IPU at least this while MAN AUG runs (put back after)
GLOBAL ARM_AUTO_STALL_T IS 5.    // s: an AUTO leg held this long by a joint behind its target stops (STALL)
GLOBAL ARM_AUTO_EPS IS 0.01.     // deg: a joint an AUTO leg changes less than this is not driven
GLOBAL ARM_GRP_SEEK_T IS 2.      // s: the fixture looked for again this often (GRAPPLE's page, not docked)
GLOBAL ARM_GRP_CL_T IS 0.5.      // s: the closing rate's window
GLOBAL ARM_LOAD_T IS 1.          // s: the load weighed again this often while docked
GLOBAL ARM_OPR_HELD_T IS 10.     // s: OPR CMD held this long (the arm cannot keep up with its line) stops (HELD)
GLOBAL ARM_OPR_SETTLE_T IS 10.   // s: OPR CMD at its line's end this long, not within its tolerance, stops (NOT SETTLED)
IF NOT (DEFINED ARM_HOLD) { GLOBAL ARM_HOLD IS "INRTL". }   // the hold at RUN arm: "INRTL", "LVLH", "FREE"
IF NOT (DEFINED ARM_HOLD_EXT) { GLOBAL ARM_HOLD_EXT IS FALSE. }   // TRUE = the orbiter's attitude belongs to ops2q's C# DAP (hosted, PDRS): no FBW3 / FBWOFF / hold law here, FBWXOFF (the THC) stays
GLOBAL ARM_HOLD_LOG IS 5.        // s: the hold's log line this often
GLOBAL ARM_HOLD_DB IS 1.0.       // deg: the hold's attitude deadband (lib_arm's LAR_HOLD_* are set from these four)
GLOBAL ARM_HOLD_RATE IS 0.2.     // deg/s: the hold's largest rate back to the reference
GLOBAL ARM_HOLD_RDB IS 0.02.     // deg/s: the hold's rate deadband (no jet inside it)
GLOBAL ARM_HOLD_ACC IS 0.05.     // deg/s2: the hold's largest angular acceleration (its load on the arm)
SET LAR_HOLD_DB TO ARM_HOLD_DB. SET LAR_HOLD_RATE TO ARM_HOLD_RATE. SET LAR_HOLD_RDB TO ARM_HOLD_RDB. SET LAR_HOLD_ACC TO ARM_HOLD_ACC.
RUNONCEPATH("0:/lib/lib_logsw.ks").   // logFree
LOCAL armLog IS "".   // The arm log only when the logs are on (SOCK_LOG; the release ships them off)
IF SOCK_LOG { SET armLog TO logFree("0:/logs/arm_" + ROUND(TIME:SECONDS), ".txt"). }
GLOBAL ARM_LOG IS armLog.   // This run's log path, for the automated test flight's status (lib_o2arm o2aSailStat k_arm_log)
FUNCTION armPr { PARAMETER s. IF NOT ARM_HOST { PRINT s. } IF armLog <> "" { LOG ROUND(TIME:SECONDS, 1) + " " + s TO armLog. } }   // hosted by ops2q = the arm log only (the console stays blank)

FUNCTION armIn {                             // a vector in a frame: its (star, top, fore) components
    PARAMETER vec, fr.
    RETURN V(VDOT(vec, fr:STARVECTOR), VDOT(vec, fr:TOPVECTOR), VDOT(vec, fr:FOREVECTOR)).
}
FUNCTION armRel {                            // part b's top and fore in part a's frame
    PARAMETER a, b.
    RETURN LIST(armIn(b:FACING:TOPVECTOR, a:FACING), armIn(b:FACING:FOREVECTOR, a:FACING)).
}
FUNCTION armTurn {                           // the angle (deg, unsigned) between two armRel's
    PARAMETER r0, r1.
    RETURN MAX(VANG(r0[0], r1[0]), VANG(r0[1], r1[1])).
}

// ---- the arm: the joints from the shoulder out, each LIST(part, module, name, parent, next part, module name)
LOCAL ees IS larEnds().
LOCAL chErr IS "".                           // Why the craft's chain is not the 6 joints ("" = it is)
IF ees:LENGTH >= ARM_N { larChain(ees[ARM_N - 1]). SET chErr TO LAR_CHAIN_ERR. }
IF ees:LENGTH < ARM_N { armPr("arm: NO ARM (" + ees:LENGTH + " end effector(s) found, ARM_N " + ARM_N + ")"). }
ELSE IF chErr <> "" { armPr("arm: " + chErr + ": NO ARM"). }
ELSE {
    LOCAL ee IS ees[ARM_N - 1].
    LOCAL jts IS larChain(ee).
    armPr("arm: '" + SHIP:NAME + "', " + jts:LENGTH + " joints, SINGLE mode").

    // ---- the autostrut: off on every arm part before any joint drives
    LOCAL asParts IS larArmParts(ee, jts).
    LOCAL asWhy IS larAsWhy().
    LOCAL asBlock IS "".                     // why the autostrut inhibits the drive ("" = it does not)
    FUNCTION armAsOff {                      // every arm part's autostrut off: "" when none is left on
        IF asWhy <> "" { RETURN "". }
        LOCAL asR IS larAsOff(asParts).
        IF asR[0] > 0 { armPr("arm: autostrut OFF:" + asR[2]). }
        IF asR[1] > 0 { RETURN "AUTOSTRUT ON (" + asR[1] + " PART" + (CHOOSE "S" IF asR[1] > 1 ELSE "") + "): DRIVE INHIBITED". }
        RETURN "".
    }
    IF asWhy = "" { SET asBlock TO armAsOff(). }
    ELSE { armPr("arm: autostrut not reachable (" + asWhy + "): set it OFF in the arm parts' menus, then STRUTS OFF BY HAND"). }

    // ---- the orbiter's attitude hold (ARM-STAB): SAS off, RCS on, the pilot's stick and THC kept off the jets
    LOCAL hOk IS larFbwHas("FBW3").          // the fly-by-wire handler: the hold can fly
    LOCAL xOk IS larFbwHas("FBWXOFF").       // ...and keep the THC's translation off the jets
    LOCAL xLive IS FALSE.                    // FBWXOFF answered this tick: the THC is held off the jets now
    LOCAL rcs0 IS RCS. LOCAL sas0 IS SAS.
    LOCAL hMd IS ARM_HOLD. LOCAL hSt IS 0. LOCAL hAu IS V(0, 0, 0). LOCAL hAuT IS -1E9. LOCAL hLogT IS -1E9. LOCAL hThcT IS -1E9. LOCAL hWorkT IS -1E9.
    LOCAL hRes IS LIST(V(0, 0, 0), V(0, 0, 0), V(0, 0, 0)).
    FUNCTION armRcsBad {                     // RCS on would translate the orbiter on the THC (FBWXOFF not live this tick)
        RETURN RCS AND NOT xLive.
    }
    FUNCTION armThc {                        // the THC as the arm reads it, V(starboard, top, fore): the keyboard's PILOT*
        IF DEFINED ARM_THC_TEST { RETURN ARM_THC_TEST. }     // A test job's THC (V(starboard, top, fore)); never defined in flight
        IF DEFINED ARM_THC_OFF { IF ARM_THC_OFF { RETURN V(0, 0, 0). } }     // STICK ORB: the THC is PROX OPS's
        LOCAL pil IS V(SHIP:CONTROL:PILOTSTARBOARD, SHIP:CONTROL:PILOTTOP, SHIP:CONTROL:PILOTFORE).     // plus AFBW's
        IF NOT xLive { RETURN pil. }         // translation axes (only in the vessel's final state, which the hold's intercept
        RETURN larThcPick(pil, ADDONS:KALS:FBWXPILOT(), TRUE).     // reads as FBWXPILOT)
    }
    FUNCTION holdBasis {
        RETURN larHoldBasis(hMd, -SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT, SOLARPRIMEVECTOR, SHIP:BODY:ANGULARVEL).
    }
    FUNCTION holdSet {                       // the hold in mode md on the attitude the orbiter has now
        PARAMETER md.
        SET hMd TO md.
        IF ARM_HOLD_EXT { RETURN. }          // The DAP owns the attitude, nothing to hold here
        SET hSt TO larHoldNew(md, holdBasis(), SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
        armPr("HOLD " + md + (CHOOSE ": no jet (free drift)" IF md = "FREE" ELSE ": on the attitude it has now") + ", the orbiter turns "
            + ROUND(SHIP:ANGULARVEL:MAG / LAR_D2R, 3) + " deg/s; RCS " + (CHOOSE "ON" IF RCS ELSE "OFF") + ", SAS " + (CHOOSE "ON" IF SAS ELSE "OFF")).
    }
    FUNCTION holdX {                         // the THC held off the jets (FBWXOFF, a 0.5 s watchdog that lapses by itself) + the in-game THC check log
        PARAMETER tn.
        IF xOk {
            SET xLive TO ADDONS:KALS:FBWXOFF().
            LOCAL thc IS V(SHIP:CONTROL:PILOTSTARBOARD, SHIP:CONTROL:PILOTTOP, SHIP:CONTROL:PILOTFORE).
            LOCAL xp IS ADDONS:KALS:FBWXPILOT().
            IF armLog <> "" AND (thc:MAG > 0.05 OR V(xp[0], xp[1], xp[2]):MAG > 0.05) AND tn - hThcT > 1 {   // the in-game check: the THC as kOS reads it = as handed
                SET hThcT TO tn.
                LOG ROUND(tn, 1) + " HOLD THC: PILOT " + ROUND(thc:X, 2) + " " + ROUND(thc:Y, 2) + " " + ROUND(thc:Z, 2) + ", handed "
                    + ROUND(xp[0], 2) + " " + ROUND(xp[1], 2) + " " + ROUND(xp[2], 2) + " (held at 0 on the jets)" TO armLog.
            }
        }
    }
    FUNCTION holdTick {                      // one tick: the hold's command on the vessel's pitch / roll / yaw, the THC off
        PARAMETER tn, dt.
        SET xLive TO FALSE.
        IF NOT hOk { RETURN. }
        IF ARM_HOLD_EXT { holdX(tn). RETURN. }     // No FBW3, no hold law: the DAP flies; the THC intercept below stays
        IF tn - hAuT > 1 { LOCAL au IS ADDONS:KALS:FBWAUTH(). SET hAu TO V(au[0], au[1], au[2]). SET hAuT TO tn. }
        LOCAL fc IS SHIP:FACING.
        SET hRes TO larHoldTick(hSt, holdBasis(), fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR, SHIP:ANGULARVEL, hAu, dt).
        LOCAL u IS hRes[0].
        ADDONS:KALS:FBW3(u:X, u:Y, u:Z).
        holdX(tn).
        IF armLog <> "" AND tn - hLogT > ARM_HOLD_LOG {
            SET hLogT TO tn.
            LOG ROUND(tn, 1) + " HOLD " + hMd + ": error " + ROUND(hRes[1]:X, 2) + " " + ROUND(hRes[1]:Y, 2) + " " + ROUND(hRes[1]:Z, 2)
                + " deg, rate " + ROUND(hRes[2]:X, 3) + " " + ROUND(hRes[2]:Y, 3) + " " + ROUND(hRes[2]:Z, 3) + " deg/s, jets "
                + ROUND(u:X, 3) + " " + ROUND(u:Y, 3) + " " + ROUND(u:Z, 3) + " (pitch, roll, yaw), authority " + ROUND(hAu:X, 3) + " "
                + ROUND(hAu:Y, 3) + " " + ROUND(hAu:Z, 3) + " deg/s2" TO armLog.
        }
    }
    FUNCTION holdText {                      // the hold's status line
        IF NOT hOk { RETURN "HOLD N/A: NO KALSCOPROC FLY-BY-WIRE (THE STICK GOES STRAIGHT THROUGH)". }
        IF ARM_HOLD_EXT { RETURN "HOLD: OPS2 DAP" + (CHOOSE "" IF xLive ELSE "  THC NOT HELD OFF"). }
        LOCAL u IS hRes[0].
        RETURN "HOLD " + hMd + (CHOOSE "" IF hMd = "FREE" ELSE "  ERR " + ROUND(hRes[1]:X, 1) + " " + ROUND(hRes[1]:Y, 1) + " "
            + ROUND(hRes[1]:Z, 1)) + "  RATE " + ROUND(hRes[2]:X, 2) + " " + ROUND(hRes[2]:Y, 2) + " " + ROUND(hRes[2]:Z, 2)
            + (CHOOSE "  JETS" IF u:MAG > 0 ELSE "") + (CHOOSE "" IF xLive ELSE "  THC NOT HELD OFF").
    }
    IF hOk AND ARM_HOLD_EXT {                // The DAP's SAS / RCS / attitude stand; only the THC intercept is the arm's
        armPr("HOLD EXT: the orbiter's attitude stays with ops2's DAP (no FBW3 / FBWOFF here); the THC held off the jets by FBWXOFF" + (CHOOSE "" IF xOk ELSE " (NOT AVAILABLE: an older KalsCoproc.dll)")).
    } ELSE IF hOk {
        IF SAS { SAS OFF. }
        IF xOk AND NOT RCS { RCS ON. }
        holdSet(hMd).
        IF xOk { armPr("HOLD PATH: INTERCEPT LIVE (FBW3 + FBWXOFF): RCS on, the stick and the THC held off the jets; the RCS-on drive inhibits lifted"). }
        ELSE { armPr("HOLD PATH: WHEELS-ONLY (an older KalsCoproc.dll, no FBWXOFF): the stick held off (FBW3), the THC NOT; RCS left "
            + (CHOOSE "ON" IF RCS ELSE "OFF") + ", RCS on still inhibits the THC's drives"). }
    } ELSE { armPr("HOLD N/A: no KalsCoproc fly-by-wire (ADDONS:KALS:FBW3): the orbiter is not held, the stick goes straight through"). }

    // ---- the window
    LOCAL quit IS FALSE.
    LOCAL g IS GUI(360).
    SET g:X TO 40. SET g:Y TO 300.
    g:ADDLABEL("<b>RMS  SINGLE</b>   THC UP / DOWN drives the joint" + (CHOOSE "" IF xOk ELSE " (RCS OFF)")).
    LOCAL rwH IS g:ADDHLAYOUT().             // the orbiter's attitude hold (ARM-STAB): one pressed
    rwH:ADDLABEL("HOLD").
    LOCAL hBt IS LIST().
    FOR k IN LIST("INRTL", "LVLH", "FREE") {
        LOCAL b IS rwH:ADDBUTTON(k).
        SET b:TOGGLE TO TRUE.
        SET b:PRESSED TO k = hMd.
        hBt:ADD(LIST(k, b)).
    }
    LOCAL hl IS g:ADDLABEL("").
    LOCAL lb IS LIST().
    LOCAL rb IS LIST().              // the joint buttons: plain toggles, one pressed at most (the loop's joint select)
    FOR j IN jts {
        LOCAL rw IS g:ADDHLAYOUT().
        LOCAL b IS rw:ADDBUTTON(j[2]).
        SET b:TOGGLE TO TRUE.
        SET b:PRESSED TO rb:LENGTH = 0.
        SET b:STYLE:WIDTH TO 170.
        rb:ADD(b).
        lb:ADD(rw:ADDLABEL("")).
    }
    LOCAL rw2 IS g:ADDHLAYOUT().
    LOCAL bv IS rw2:ADDBUTTON("VERNIER").
    SET bv:TOGGLE TO TRUE.
    LOCAL bh IS 0.                           // STRUTS OFF BY HAND (only without ASTRUT)
    IF asWhy <> "" {
        SET bh TO rw2:ADDBUTTON("STRUTS OFF BY HAND").
        SET bh:TOGGLE TO TRUE.
    }
    LOCAL bAug IS rw2:ADDBUTTON("MAN AUG").
    SET bAug:TOGGLE TO TRUE.
    LOCAL pFrm IS rw2:ADDPOPUPMENU().        // MAN AUG's frame: ORB UNL, END EFF, ORB LD, PL (the last two LOADED)
    SET pFrm:OPTIONS TO LAR_FRAMES:COPY.
    SET pFrm:INDEX TO 0.
    LOCAL bs IS rw2:ADDBUTTON("STOP").
    SET bs:ONCLICK TO { SET quit TO TRUE. }.
    LOCAL rw3 IS g:ADDHLAYOUT().
    LOCAL bStk IS rw3:ADDBUTTON("STICK").    // the RHC read off the OMS gimbal, the orbiter's torque off (C2)
    SET bStk:TOGGLE TO TRUE.
    SET bStk:PRESSED TO ARM_RHC = "STICK".
    LOCAL bRot IS rw3:ADDBUTTON("THC ROT").  // the TRANS / ROT switch at ROT: the THC turns the end effector (the fallback)
    SET bRot:TOGGLE TO TRUE.
    LOCAL bCam IS rw3:ADDBUTTON("EE CAM").   // the flight camera on the end effector's view (ARM-CAM); released: the stock one
    SET bCam:TOGGLE TO TRUE.
    // AUTO's buttons: plain toggles, one pressed at most (the running one), each LIST(button, kind, key): kind "POSE" flies
    // to the pose key, "AUTO" the sequence key, "GO" the saved pose picked in the list
    LOCAL apz IS larPosesLoad(LAR_POSES_FILE).
    LOCAL abt IS LIST().
    LOCAL rw4 IS g:ADDHLAYOUT().
    FOR k IN LAR_BUILT_IN { abt:ADD(LIST(rw4:ADDBUTTON(k), "POSE", k)). }
    LOCAL rw5 IS g:ADDHLAYOUT().
    FOR k IN LIST("AUTO 1", "AUTO 2", "AUTO 3", "AUTO 4") { abt:ADD(LIST(rw5:ADDBUTTON(k), "AUTO", k)). }
    LOCAL rw6 IS g:ADDHLAYOUT().
    LOCAL pmu IS rw6:ADDPOPUPMENU().         // the operator's saved poses
    abt:ADD(LIST(rw6:ADDBUTTON("GO"), "GO", "")).
    LOCAL svReq IS FALSE.
    LOCAL bSave IS rw6:ADDBUTTON("SAVE").
    SET bSave:ONCLICK TO { SET svReq TO TRUE. }.
    LOCAL pTo IS rw6:ADDPOPUPMENU().         // SAVE also adds the pose to AUTO 3 / AUTO 4
    SET pTo:OPTIONS TO LIST("POSE ONLY", "+ AUTO 3", "+ AUTO 4").
    FOR b IN abt { SET b[0]:TOGGLE TO TRUE. }
    FUNCTION autoLabels {                    // the AUTO buttons' names and the saved-pose list, from apz
        FOR b IN abt {
            IF b[1] = "AUTO" {
                LOCAL nm IS CHOOSE LAR_AUTO_NAME[b[2]] IF LAR_AUTO_NAME:HASKEY(b[2]) ELSE "".
                SET b[0]:TEXT TO b[2] + " " + (CHOOSE nm IF nm <> "" AND NOT apz["own"]:CONTAINS(b[2])
                    ELSE "(" + apz["seqs"][b[2]]:LENGTH + ")").
            }
        }
        SET pmu:OPTIONS TO CHOOSE apz["user"]:COPY IF apz["user"]:LENGTH > 0 ELSE LIST("NO SAVED POSE").
    }
    autoLabels().
    LOCAL rw8 IS g:ADDHLAYOUT().             // OPR CMD: the keyed pose (X / Y / Z ft, P / Y / R deg), LOAD, OPR CMD
    LOCAL opFd IS LIST().
    FOR k IN LIST("X", "Y", "Z") { rw8:ADDLABEL(k). LOCAL tfd IS rw8:ADDTEXTFIELD(""). SET tfd:STYLE:WIDTH TO 60. opFd:ADD(tfd). }
    rw8:ADDLABEL("M").
    LOCAL rw9 IS g:ADDHLAYOUT().
    FOR k IN LIST("P", "Y", "R") { rw9:ADDLABEL(k). LOCAL tfd IS rw9:ADDTEXTFIELD(""). SET tfd:STYLE:WIDTH TO 60. opFd:ADD(tfd). }
    rw9:ADDLABEL("DEG").
    LOCAL oprLdReq IS FALSE.
    LOCAL bLoad IS rw9:ADDBUTTON("LOAD").    // the keyed pose = the pose now
    SET bLoad:ONCLICK TO { SET oprLdReq TO TRUE. }.
    LOCAL bOpr IS rw9:ADDBUTTON("OPR CMD").  // a toggle: pressed while it flies
    SET bOpr:TOGGLE TO TRUE.
    LOCAL pl0 IS g:ADDLABEL("").             // the POSE line: the POR (the node, or the payload's) and its attitude now
    LOCAL rw7 IS g:ADDHLAYOUT().             // GRAPPLE: the page, CAPTURE and RELEASE (toggles: pressed while they fly)
    LOCAL bGrp IS rw7:ADDBUTTON("GRAPPLE").
    LOCAL bCap IS rw7:ADDBUTTON("CAPTURE").
    LOCAL bRel IS rw7:ADDBUTTON("RELEASE").
    FOR b IN LIST(bGrp, bCap, bRel) { SET b:TOGGLE TO TRUE. }
    LOCAL gl1 IS g:ADDLABEL("").
    LOCAL gl2 IS g:ADDLABEL("").
    LOCAL st IS g:ADDLABEL("").
    IF NOT ARM_HOST { g:SHOW(). }

    // ---- the drive
    LOCAL sel IS 0.              // the selected joint (-1: none)
    // The typed SINGLE slews are a SET, one per joint (one law each): swPh 0 idle / 1 running / 2 stopping (the rate smoothed to rest,
    // then the joint locked), its own target, command, references, stall timer and flown-rate memory. swN = the joints with a slew (running or stopping).
    LOCAL swN IS 0. LOCAL swLastJ IS -1. LOCAL swLastX IS 0.           // the newest slew's joint and target (the snapshot's "gt")
    LOCAL swPh IS LIST(). LOCAL swTg IS LIST(). LOCAL swCm IS LIST(). LOCAL swTg0 IS LIST(). LOCAL swRS IS LIST(). LOCAL swRC IS LIST().
    LOCAL swLast IS LIST(). LOCAL swStill IS LIST(). LOCAL swTEnd IS LIST(). LOCAL swStl IS LIST(). LOCAL swR2p IS LIST().
    LOCAL swRl IS LIST().                                              // this pass's slew rates for the C# drive (a joint each)
    LOCAL gotoSt IS "". LOCAL gotoStT IS -1E9.                       // The slew's last word for the status line (5 s after it ends)
    LOCAL drv IS FALSE.         // the selected joint unlocked (driven, or stopping)
    LOCAL jSave IS LIST().       // each joint's lock and traverse rate when first driven (-1: never driven)
    LOCAL lkNote IS FALSE.       // "LOADED: joint locks off" logged once per load
    LOCAL ldhOn IS FALSE. LOCAL ldhTr IS LIST(). LOCAL ldhCorr IS LIST(). LOCAL ldhMeas IS LIST(). LOCAL ldhSent IS FALSE. LOCAL ldhNoT IS -1E9. LOCAL ldhWhy IS "". LOCAL gSayN IS 0. LOCAL ldhZ IS LIST(). LOCAL ldhM0 IS LIST(). LOCAL ldhZT IS LIST().   // T1018: the loaded hold (trim = what the written command leads the commanded one by), the say counter
    LOCAL ldForce IS FALSE.      // offline tests only (ARM_ACT["ldtest"]): ldOn forced, the LEE's docked state not consulted; never TRUE in flight
    FUNCTION armLk {             // lock a joint's servo, except while LOADED with ARM_LOCK_LOADED FALSE: then the joint stays on its drive (target = where it was commanded to)
        PARAMETER sv.
        IF ldOn AND NOT ARM_LOCK_LOADED {
            IF NOT lkNote { SET lkNote TO TRUE. armPr("LOADED: joint locks off (ARM_LOCK_LOADED FALSE): each joint holds its target on the servo's drive"). }
            IF dOn { armRates(dZero, LAR_TAU_J). }       // a lock froze the joint at once; unlocked, the C# drive must be told to stop (also ends a GOTO)
            RETURN.
        }
        sv:SETFIELD("locked", TRUE).
    }
    FUNCTION armUnld {           // The arm unloaded (undocked): the joints left unlocked while loaded are locked now, on an idle arm (a running mode locks at its own end, unloaded by then)
        SET lkNote TO FALSE.
        IF NOT (aug OR auto OR opr OR drv OR swN > 0 OR grp <> "") {
            FOR jl IN jts { IF NOT jl[1]:GETFIELD("locked") { jl[1]:SETFIELD("locked", TRUE). } }
        }
    }
    // ---- MAN AUG's state (the reference pose and the checks in the shoulder's parent's frame: the orbiter's turn drops out)
    LOCAL aug IS FALSE. LOCAL augMv IS FALSE. LOCAL augSt IS "". LOCAL augHalt IS "". LOCAL augSoftTx IS "".   // augHalt is never set now (a soft stop no longer latches); augSoftTx = the soft-stop words said last
    LOCAL augHeld IS LIST(). LOCAL augEl IS -1.
    FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
        IF jts[i][2] = "ELBOW PITCH" { SET augEl TO i. }
    }
    LOCAL augFr IS larFree(jts:LENGTH, augHeld).
    LOCAL augNm IS LIST().
    FOR i IN augFr { augNm:ADD(jts[i][2]). }
    LOCAL root IS jts[0][3].
    LOCAL pRef IS V(0, 0, 0). LOCAL fRef IS V(0, 0, 1). LOCAL tRef IS V(0, 1, 0).
    LOCAL askW IS V(0, 0, 0). LOCAL pWin IS V(0, 0, 0). LOCAL tWin IS 0. LOCAL tEndA IS -1.
    LOCAL augFirst IS TRUE.          // The model check's first window after MAN AUG starts is not judged (the joints' start-up lag from rest: asked 0.267 m, moved 0.081 at the x2 rates)
    LOCAL augTg0 IS LIST(). LOCAL augR0 IS LIST().
    LOCAL augCm IS LIST().       // the joints' running commands (deg): kOS rounds the target field to LAR_QSTEP, never read back
    LOCAL augCmM IS LIST().      // the C# drive's commands at the last measurement (the model check's asked move)
    LOCAL augSv IS LIST(V(0, 0, 0), V(0, 0, 0)). LOCAL augSw IS LIST(V(0, 0, 0), V(0, 0, 0)).   // the smoothed commands
    LOCAL augStl IS LIST(-1, FALSE).   // MAN AUG's stall timer (larStallTick)
    LOCAL askA IS V(0, 0, 0). LOCAL fWn IS V(0, 0, 1). LOCAL tWn IS V(0, 1, 0). LOCAL wUse IS FALSE.   // the turn's window
    LOCAL rhcOn IS FALSE. LOCAL rhcWhy IS "".   // STICK on (the torque off, the gimbal unlocked); why the stick is inhibited
    LOCAL omsL IS larOmsEng(). LOCAL gmSave IS LIST().
    LOCAL ipu0 IS CONFIG:IPU.
    FUNCTION augRhc {                        // STICK on: every wheel's torque off, the OMS gimbal unlocked; off: both as they were
        PARAMETER on.
        IF on AND NOT rhcOn {
            SET rhcOn TO TRUE. SET rhcWhy TO "".
            LOCAL tq IS (CHOOSE LIST(0, 0, "") IF hOk AND NOT ARM_HOLD_EXT ELSE larTorqueOff()).   // under the live FBW3 hold the stick never reaches the vessel (FBWPILOT), so the wheels STAY ON: the hold keeps their authority (roll 10 vs 4.5 deg/s2)
            IF hOk AND NOT ARM_HOLD_EXT { armPr("MAN AUG: STICK on, the wheels stay ON (the FBW3 hold has them)"). }
            ELSE armPr("MAN AUG: STICK on, torque OFF (" + tq[0] + " wheel" + (CHOOSE "" IF tq[0] = 1 ELSE "s") + "):" + tq[2]).
            IF tq[1] > 0 { SET rhcWhy TO "TORQUE NOT OFF (" + tq[1] + " WHEEL" + (CHOOSE "" IF tq[1] = 1 ELSE "S") + ")". }
            IF omsL:LENGTH = 0 { SET rhcWhy TO "NO OMS GIMBAL". }
            ELSE {
                LOCAL gm IS omsL[0]:GIMBAL.
                SET gmSave TO LIST(gm:LOCK, gm:PITCH, gm:YAW, gm:ROLL).
                SET gm:LOCK TO FALSE. SET gm:PITCH TO TRUE. SET gm:YAW TO TRUE. SET gm:ROLL TO TRUE.
                armPr("MAN AUG: the stick = the OMS gimbal on " + omsL[0]:TITLE + " (its lock was " + gmSave[0]
                    + "); the orbiter turns " + ROUND(SHIP:ANGULARVEL:MAG / LAR_D2R, 3) + " deg/s").
            }
            IF rhcWhy <> "" { armPr("MAN AUG: STICK INHIBITED: " + rhcWhy). }
        }
        IF NOT on AND rhcOn {
            SET rhcOn TO FALSE.
            armPr("MAN AUG: STICK off, torque back:" + larTorqueBack()).
            IF gmSave:LENGTH = 4 {
                LOCAL gm IS omsL[0]:GIMBAL.
                SET gm:LOCK TO gmSave[0]. SET gm:PITCH TO gmSave[1]. SET gm:YAW TO gmSave[2]. SET gm:ROLL TO gmSave[3].
                SET gmSave TO LIST().
            }
        }
    }
    FUNCTION augLock {                       // every MAN AUG joint locked where it is commanded
        IF dOn { armRates(dZero, LAR_TAU_J). }
        SET augSv TO LIST(V(0, 0, 0), V(0, 0, 0)). SET augSw TO LIST(V(0, 0, 0), V(0, 0, 0)). SET augStl TO LIST(-1, FALSE).
        IF NOT ARM_AUG_NOLOCK { FOR i IN augFr { armLk(jts[i][1]). } }     // No lock in MAN AUG
        SET augMv TO FALSE.
    }
    FUNCTION augOff {                        // MAN AUG left: the joints locked, the IPU back
        PARAMETER why.
        IF augMv { augLock(). }
        augRhc(FALSE).
        SET aug TO FALSE. SET bAug:PRESSED TO FALSE. SET augHalt TO "".
        SET CONFIG:IPU TO ipu0.
        armPr("MAN AUG off: " + why).
    }
    FUNCTION augWords {                      // the commanded move and turn (ORB UNL's components), as the operator sees them:
        PARAMETER vc, wc, ee.                // from the aft station, or along the LEE's boresight (END EFF)
        LOCAL s IS "".
        IF ee {
            IF vc:Z < 0 { SET s TO s + " FWD". }
            IF vc:Z > 0 { SET s TO s + " BACK". }
            IF vc:Y > 0 { SET s TO s + " UP". }
            IF vc:Y < 0 { SET s TO s + " DOWN". }
            IF vc:X < 0 { SET s TO s + " RIGHT". }
            IF vc:X > 0 { SET s TO s + " LEFT". }
        } ELSE {
            IF vc:Z < 0 { SET s TO s + " AFT". }
            IF vc:Z > 0 { SET s TO s + " FWD". }
            IF vc:Y > 0 { SET s TO s + " OUT". }
            IF vc:Y < 0 { SET s TO s + " IN". }
            IF vc:X > 0 { SET s TO s + " STBD". }
            IF vc:X < 0 { SET s TO s + " PORT". }
        }
        IF wc:X > 0 { SET s TO s + " PITCH UP". }
        IF wc:X < 0 { SET s TO s + " PITCH DN". }
        IF wc:Y > 0 { SET s TO s + " YAW R". }
        IF wc:Y < 0 { SET s TO s + " YAW L". }
        IF wc:Z > 0 { SET s TO s + " ROLL R". }
        IF wc:Z < 0 { SET s TO s + " ROLL L". }
        RETURN s.
    }
    // ---- AUTO's state: the legs (larSafePath's), the leg flown, its start and goal targets, the share s along it
    LOCAL auto IS FALSE. LOCAL asel IS -1. LOCAL autoSt IS "". LOCAL autoStT IS 0. LOCAL autoTag IS "".
    LOCAL sqTo IS LIST("", "AUTO 3", "AUTO 4").   // pTo's options as sequence names
    LOCAL aLegs IS LIST(). LOCAL li IS 0. LOCAL lgA IS LIST(). LOCAL lgB IS LIST(). LOCAL lT IS 1. LOCAL lS IS 0.
    LOCAL lMv IS LIST(). LOCAL lR0 IS LIST(). LOCAL lSet IS FALSE. LOCAL lStall IS -1. LOCAL lStill IS 0. LOCAL lLast IS 0.
    LOCAL lTset IS 0. LOCAL lGs IS LIST(). LOCAL lP0 IS V(0, 0, 0). LOCAL lStT IS LIST(-1, FALSE).
    LOCAL anm IS LIST().
    FOR j IN jts { anm:ADD(j[2]). }
    FUNCTION autoTgs {                       // every joint's 'target angle' now
        LOCAL out IS LIST().
        FOR j IN jts { out:ADD(j[1]:GETFIELD("target angle")). }
        RETURN out.
    }
    FUNCTION autoTurned {                    // joint c's measured turn since its leg started (deg, unsigned)
        PARAMETER c.
        LOCAL jj IS jts[c].
        RETURN MAX(armTurn(lR0[c][0], armRel(jj[3], jj[0])), armTurn(lR0[c][1], armRel(jj[0], jj[4]))).
    }
    FUNCTION autoRoot {                      // the node and the geometry in the shoulder's parent's frame (larGeom's, moved)
        LOCAL fr IS root:FACING.
        LOCAL gm IS larGeom(jts, ee).
        LOCAL gs2 IS LIST().
        FOR gg IN gm[1] { gs2:ADD(LIST(armIn(gg[0] - root:POSITION, fr), armIn(gg[1], fr), gg[2])). }
        RETURN LIST(armIn(gm[0] - root:POSITION, fr), gs2).
    }
    FUNCTION autoList {                      // targets as text
        PARAMETER tg.
        LOCAL s IS "".
        FOR x IN tg { SET s TO s + (CHOOSE "" IF s = "" ELSE " ") + ROUND(x, 1). }
        RETURN "(" + s + ")".
    }
    FUNCTION autoLeg {                       // leg li starts: the moving joints unlocked at their rates, the references taken
        SET lgA TO autoTgs(). SET lgB TO aLegs[li][1].
        LOCAL vern IS aLegs[li][2] OR bv:PRESSED.
        SET lT TO MAX(larMoveT(lgA, lgB, LAR_QD_MAX * ldS * (CHOOSE LAR_VERNIER IF vern ELSE 1)), 0.1).
        SET lS TO 0. SET lSet TO FALSE. SET lStall TO -1. SET lStill TO 0. SET lLast TO 0. SET lStT TO LIST(-1, FALSE).
        SET lMv TO LIST(). SET lR0 TO LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            LOCAL jj IS jts[i].
            lR0:ADD(LIST(armRel(jj[3], jj[0]), armRel(jj[0], jj[4]))).
            IF ABS(lgB[i] - lgA[i]) >= ARM_AUTO_EPS {
                lMv:ADD(i).
                IF jSave[i][0] < 0 { SET jSave[i] TO LIST(CHOOSE 1 IF jj[1]:GETFIELD("locked") ELSE 0, jj[1]:GETFIELD("traverse rate")). }
                IF NOT dOn { jj[1]:SETFIELD("traverse rate", ABS(lgB[i] - lgA[i]) / lT + ARM_AUG_MARGIN). }
                jj[1]:SETFIELD("locked", FALSE).
            }
        }
        IF dOn {                             // the C# drive flies the leg, every joint arriving together, its peak rate the
            LOCAL tBl IS LAR_GOTO_TB.        // leg's rate, no step in rate (no ring): a long leg cruises, blended over LAR_GOTO_TB;
            IF lT > tBl { SET lT TO lT + tBl. }   // a short one (no time to cruise) on the minimum-jerk profile
            ELSE { SET lT TO MAX(LAR_GOTO_TMIN, LAR_GOTO_K * lT). SET tBl TO 0. }
            ADDONS:KALS:ARMGOTO(lgB, lT, tBl).
        }
        LOCAL rg IS autoRoot().
        SET lP0 TO rg[0]. SET lGs TO rg[1].
        SET autoTag TO aLegs[li][0] + " (" + (li + 1) + "/" + aLegs:LENGTH + (CHOOSE ", VERNIER" IF vern ELSE "")
            + (CHOOSE ", LOADED" IF ldOn ELSE "") + ")".
        armPr("AUTO: leg " + (li + 1) + "/" + aLegs:LENGTH + " to " + aLegs[li][0] + (CHOOSE " at VERNIER" IF vern ELSE "")
            + ", " + ROUND(lT, 1) + " s, " + lMv:LENGTH + " joints; from " + autoList(lgA) + " to " + autoList(lgB)).
    }
    FUNCTION autoLock {                      // the leg's moving joints locked
        FOR i IN lMv { armLk(jts[i][1]). }
        SET lMv TO LIST().
    }
    FUNCTION autoOff {                       // AUTO ended (why), the joints locked, its button released
        PARAMETER why, stText.
        autoLock().
        SET auto TO FALSE.
        IF asel >= 0 { SET abt[asel][0]:PRESSED TO FALSE. }
        SET asel TO -1.
        SET autoSt TO stText. SET autoStT TO TIME:SECONDS.
        armPr("AUTO off: " + why).
    }
    FUNCTION autoStart {                     // AUTO button i pressed: its legs, or refused (the button released)
        PARAMETER i.
        LOCAL b IS abt[i].
        LOCAL nm IS b[2].
        IF b[1] = "GO" { SET nm TO CHOOSE apz["user"][pmu:INDEX] IF apz["user"]:LENGTH > 0 AND pmu:INDEX >= 0 ELSE "". }
        LOCAL seq IS CHOOSE apz["seqs"][nm] IF b[1] = "AUTO" ELSE LIST(nm).
        LOCAL why IS "".
        IF drv { SET why TO "A SINGLE DRIVE IS ON". }
        ELSE IF aug { SET why TO "MAN AUG IS ON". }
        ELSE IF opr { SET why TO "OPR CMD IS ON". }
        ELSE IF grp <> "" { SET why TO (CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE") + " IS ON". }
        ELSE IF latched { SET why TO "LATCHED: THE PAYLOAD IS STILL HELD IN THE BAY". }
        ELSE IF armBad <> "" { SET why TO armWhy(). }
        ELSE IF nm = "" { SET why TO "NO SAVED POSE (SAVE ONE FIRST)". }
        ELSE IF seq:LENGTH = 0 { SET why TO nm + ": NO POINTS (SAVE WITH + " + nm + ")". }
        LOCAL res IS LIST(LIST(), "").
        IF why = "" {
            SET res TO larSafePath(anm, autoTgs(), seq, apz["poses"]).
            SET why TO res[1].
            IF why = "" AND res[0]:LENGTH = 0 { SET why TO "THE ARM IS AT " + seq[seq:LENGTH - 1]. }
        }
        IF why = "" {                        // the autostrut first: no drive while an arm part has it on
            IF asWhy = "" { SET asBlock TO armAsOff(). }
            ELSE IF bh:PRESSED { SET asBlock TO "". }
            ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
            SET why TO asBlock.
        }
        IF why <> "" {
            SET b[0]:PRESSED TO FALSE. SET asel TO -1.
            SET autoSt TO "AUTO REFUSED: " + why. SET autoStT TO TIME:SECONDS.
            armPr(autoSt).
            RETURN.
        }
        IF sel >= 0 { SET rb[sel]:PRESSED TO FALSE. SET sel TO -1. }
        SET aLegs TO res[0]. SET li TO 0. SET auto TO TRUE. SET autoSt TO "".
        LOCAL s IS "".
        FOR lg IN aLegs { SET s TO s + " -> " + lg[0] + (CHOOSE " (VERNIER)" IF lg[2] ELSE ""). }
        armPr("AUTO " + (CHOOSE nm IF b[1] <> "GO" ELSE "GO " + nm) + ":" + s).
        autoLeg().
    }
    FUNCTION autoArrive {                    // leg li done: the joints locked, the node checked against the model, the next leg
        autoLock().
        LOCAL rg IS autoRoot().
        LOCAL dq IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= lgA:LENGTH STEP { SET i TO i + 1. } DO { dq:ADD(lgB[i] - lgA[i]). }
        LOCAL pm IS larFkNode(lGs, lP0, dq, -1).
        LOCAL s IS "AUTO: at " + aLegs[li][0] + ", the node moved " + ROUND((rg[0] - lP0):MAG, 3) + " m to " + ROUND(rg[0]:X, 3)
            + " " + ROUND(rg[0]:Y, 3) + " " + ROUND(rg[0]:Z, 3) + " (the shoulder base's frame); the model misses by "
            + ROUND((rg[0] - pm):MAG, 3) + " m" + (CHOOSE ", MODEL MISS" IF larFkBad(lP0, pm, rg[0]) ELSE "").
        IF augEl >= 0 AND ABS(dq[augEl]) >= 1 {
            LOCAL pf IS larFkNode(lGs, lP0, dq, augEl).
            SET s TO s + "; with the elbow's sign flipped by " + ROUND((rg[0] - pf):MAG, 3) + " m (the elbow turned "
                + ROUND(autoTurned(augEl), 1) + " deg of " + ROUND(ABS(dq[augEl]), 1) + ")".
        }
        armPr(s).
        SET li TO li + 1.
        IF li < aLegs:LENGTH { autoLeg(). }
        ELSE {
            LOCAL lEnd IS aLegs[aLegs:LENGTH - 1][0].
            autoOff("complete at " + lEnd, "AUTO COMPLETE: AT " + lEnd).
            IF lEnd = "STOW" AND asWhy = "" { armPr("arm: " + larAsStow(ee, jts)). }
        }
    }
    // ---- GRAPPLE's state: the fixture, CAPTURE / RELEASE's line (to lnEnd along lnU, lnR m to go, the attitude
    // (lnF, lnT)), LOADED / LATCHED and the payload, all in the shoulder's parent's frame as MAN AUG's
    LOCAL fx IS 0. LOCAL fxOk IS FALSE. LOCAL fxT IS -99. LOCAL fxChk IS FALSE.
    LOCAL grp IS "". LOCAL grpSt IS "". LOCAL grpStT IS 0.   // "CAP" / "REL" while one flies; the status and its time
    LOCAL lnR IS 0. LOCAL lnEnd IS V(0, 0, 0). LOCAL lnU IS V(0, 0, 1). LOCAL lnF IS V(0, 0, 1). LOCAL lnT IS V(0, 1, 0).
    LOCAL lnCr IS LIST(1, 0). LOCAL lnMv IS FALSE. LOCAL lnTg0 IS LIST(). LOCAL lnRel0 IS LIST(). LOCAL lnEP IS 0.
    LOCAL lnStl IS LIST(-1, FALSE).   // the line's stall timer (larStallTick)
    LOCAL lnCm IS LIST(). LOCAL lnQR IS 0.   // the line's running commands (deg, as augCm); the arm's resolution at the node (m)
    LOCAL lnAcq IS -1. LOCAL lnEndT IS -1. LOCAL lnUnd IS -1. LOCAL lnEv IS FALSE. LOCAL ipuG IS CONFIG:IPU.
    LOCAL ldOn IS FALSE. LOCAL latched IS FALSE. LOCAL ldM IS 0. LOCAL ldN IS 0. LOCAL ldS IS 1. LOCAL ldT IS 0.
    LOCAL ldCal IS LIST().   // Per joint LIST(armRel parent->part, armRel part->next, angle) taken at the dock; the PDRS page's POS is measured from it while loaded
    LOCAL armBad IS "".                      // why the arm cannot go on (the chain changed at a dock / undock; or the MPM roll is MOVING): nothing moves
    FUNCTION armWhy {                        // armBad as the refusal's words
        RETURN CHOOSE armBad:TOUPPER IF armBad:STARTSWITH(LAR_MPM_BAD) ELSE "THE ARM CHANGED: STOP, RUN arm AGAIN".
    }
    FUNCTION armMpmSync {                    // The arm moves at STOW 12 / DEPLOY 30 / CENTER 0 / BETWEEN; only a MOVING roll holds it; once a pass, armBad follows it
        LOCAL w IS larMpmBad().
        IF armBad = "" {
            IF w <> "" { SET armBad TO w. }   // silent: an arm-mode pick says why; the MPM moving to STOW is no refusal
        } ELSE IF armBad:STARTSWITH(LAR_MPM_BAD) {
            IF w = "" { armPr("arm: MPM STOPPED: the arm may move"). }
            SET armBad TO w.
        }
    }
    LOCAL clR IS -1. LOCAL clT IS 0. LOCAL clV IS 0.         // the closing rate: the last range, its time, the rate
    FUNCTION grpSg {                         // a number with its sign
        PARAMETER x, nd.
        RETURN (CHOOSE "+" IF x >= 0 ELSE "") + ROUND(x, nd).
    }
    FUNCTION grpNode {                       // the end effector's node and its STAR, TOP, FORE in the shoulder's parent's frame
        LOCAL fr0 IS root:FACING.
        LOCAL fc IS larEeFace(ee).
        RETURN LIST(armIn(ee:POSITION + LAR_NODE_D * fc:FOREVECTOR - root:POSITION, fr0), armIn(fc:STARVECTOR, fr0),
                    armIn(fc:TOPVECTOR, fr0), armIn(fc:FOREVECTOR, fr0)).
    }
    FUNCTION grpFix {                        // the fixture's node, axis (its port's FORE) and TOP in the same frame
        LOCAL fr0 IS root:FACING.
        LOCAL pfc IS fx:PORTFACING.
        RETURN LIST(armIn(fx:NODEPOSITION - root:POSITION, fr0), armIn(pfc:FOREVECTOR, fr0), armIn(pfc:TOPVECTOR, fr0)).
    }
    FUNCTION grpRel {                        // the fixture as the end effector sees it (lib_arm larGrpRel)
        LOCAL nd IS grpNode(). LOCAL fxv IS grpFix().
        RETURN larGrpRel(nd[0], nd[1], nd[2], nd[3], fxv[0], fxv[1], fxv[2]).
    }
    FUNCTION grpFind {                       // the fixture looked for (lib_arm larFixtures): the nearest; logged when it changes
        SET fxT TO TIME:SECONDS.
        LOCAL nd IS ee:POSITION + LAR_NODE_D * ee:FACING:FOREVECTOR.
        IF NOT fxChk {                       // once: the LEE's own docking node against lib_arm's fitted one (an in-game check)
            SET fxChk TO TRUE.
            armPr("GRAPPLE: the LEE's NODEPOSITION is " + ROUND((ee:NODEPOSITION - nd):MAG, 3) + " m from lib_arm's node ("
                + LAR_NODE_D + " m along its FORE), its PORTFACING " + ROUND(VANG(ee:PORTFACING:FOREVECTOR, ee:FACING:FOREVECTOR), 2)
                + " deg off its FACING" + (CHOOSE "; acquire range " + ee:ACQUIRERANGE + " m" IF ee:HASSUFFIX("ACQUIRERANGE") ELSE "")).
        }
        LOCAL fl IS larFixtures(nd).
        IF fl:LENGTH = 0 {
            IF fxOk { armPr("GRAPPLE: no fixture within " + LAR_GRP_SEEK + " m"). }
            SET fxOk TO FALSE.
            RETURN.
        }
        IF fxOk AND fl[0]:UID = fx:UID { RETURN. }
        SET fx TO fl[0]. SET fxOk TO TRUE. SET clR TO -1. SET clV TO 0.
        LOCAL r1 IS grpRel().
        armPr("GRAPPLE: fixture " + fx:TITLE + " on '" + fx:SHIP:NAME + "' (" + fx:STATE + "), " + ROUND(r1["RANGE"], 3)
            + " m ahead, " + ROUND(r1["RIGHT"], 3) + " m right, " + ROUND(r1["UP"], 3) + " m up; " + ROUND(r1["AX"], 3)
            + " m out along its axis, " + ROUND(r1["LAT"], 3) + " m off it, the boresight " + ROUND(r1["ANG"], 2) + " deg off").
    }
    FUNCTION grpWeigh {                      // docked: the payload weighed, LATCHED or not, the rates' share; logged when it changes
        SET ldT TO TIME:SECONDS.
        LOCAL lm IS larLoadMass(ee).
        LOCAL isLat IS NOT lm[2].
        LOCAL chg IS isLat <> latched OR ABS(lm[0] - ldM) > 0.001 OR lm[1] <> ldN.
        SET latched TO isLat. SET ldM TO lm[0]. SET ldN TO lm[1].
        SET ldS TO CHOOSE 1 IF latched ELSE larLoadScale(ldM).
        IF chg {
            armPr(CHOOSE "GRAPPLE: LATCHED: the LEE is docked with no fixture hanging on it (" + ldN + " parts, " + ROUND(ldM, 3)
                + " t): a payload still held in the bay; the arm does not move until it is free (or RELEASE)"
                IF latched ELSE "GRAPPLE: LOADED: " + ROUND(ldM, 3) + " t in " + ldN + " parts on the LEE; every rate x " + ROUND(ldS, 3)).
        }
        IF latched { SET porOk TO FALSE. }
        ELSE IF chg OR NOT porOk { porSet(). }
    }
    FUNCTION grpRefind {                     // the chain found again after a dock / undock: "" or why the arm cannot go on
        LOCAL e2 IS larEnds().
        LOCAL hit IS -1.
        FROM { LOCAL i IS 0. } UNTIL i >= e2:LENGTH STEP { SET i TO i + 1. } DO { IF e2[i]:UID = ee:UID { SET hit TO i. } }
        IF hit < 0 { RETURN "THE LEE IS NO END EFFECTOR NOW (" + e2:LENGTH + " FOUND)". }
        LOCAL j2 IS larChain(e2[hit]).
        IF j2:LENGTH <> jts:LENGTH { RETURN "THE CHAIN HAS " + j2:LENGTH + " JOINTS (WAS " + jts:LENGTH + ")". }
        FROM { LOCAL i IS 0. } UNTIL i >= j2:LENGTH STEP { SET i TO i + 1. } DO {
            IF j2[i][0]:UID <> jts[i][0]:UID { RETURN jts[i][2] + " IS ANOTHER PART". }
        }
        FROM { LOCAL i IS 0. } UNTIL i >= j2:LENGTH STEP { SET i TO i + 1. } DO { SET jts[i] TO j2[i]. }
        SET ee TO e2[hit]. SET root TO jts[0][3]. SET asParts TO larArmParts(ee, jts).
        RETURN "".
    }
    FUNCTION grpLock {                       // the line's joints locked
        FOR i IN augFr { armLk(jts[i][1]). }
        SET lnMv TO FALSE.
    }
    FUNCTION grpGo {                         // the line's joints unlocked, the stall check's references taken
        SET lnTg0 TO LIST(). SET lnRel0 TO LIST(). SET lnStl TO LIST(-1, FALSE).
        FOR i IN augFr {
            LOCAL md2 IS jts[i][1].
            IF jSave[i][0] < 0 { SET jSave[i] TO LIST(CHOOSE 1 IF md2:GETFIELD("locked") ELSE 0, md2:GETFIELD("traverse rate")). }
            md2:SETFIELD("locked", FALSE).
            lnTg0:ADD(md2:GETFIELD("target angle")).
            lnRel0:ADD(LIST(armRel(jts[i][3], jts[i][0]), armRel(jts[i][0], jts[i][4]))).
        }
        IF dOn { LOCAL th0 IS armSt()[1]. FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET lnTg0[c] TO th0[augFr[c]]. } }
        SET lnCm TO lnTg0:COPY.
        SET lnMv TO TRUE.
    }
    FUNCTION grpOff {                        // CAPTURE / RELEASE ended (why), the joints locked, its button released
        PARAMETER why, stText.
        LOCAL nm IS CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE".
        IF lnMv { grpLock(). }
        IF grp = "CAP" { SET bCap:PRESSED TO FALSE. }
        IF grp = "REL" { SET bRel:PRESSED TO FALSE. }
        SET grp TO "". SET lnUnd TO -1.
        SET CONFIG:IPU TO ipuG.
        SET grpSt TO stText. SET grpStT TO TIME:SECONDS.
        armPr(nm + " off: " + why).
    }
    FUNCTION grpFly {                        // one tick of the line to lnEnd along lnU at spd, the attitude (lnF, lnT) (lib_arm
        PARAMETER spd, dtk.                  // larLineTick): "" or why it stops (a SOFT STOP, a STALL)
        LOCAL fr0 IS root:FACING.
        LOCAL gm IS larGeom(jts, ee).
        LOCAL pNow IS armIn(gm[0] - root:POSITION, fr0).
        LOCAL gs2 IS LIST().
        FOR gg IN gm[1] { gs2:ADD(LIST(armIn(gg[0] - root:POSITION, fr0), armIn(gg[1], fr0), gg[2])). }
        LOCAL jm IS larJacob(pNow, gs2, augHeld).
        LOCAL res IS larLineTick(pNow, armIn(larEeFace(ee):FOREVECTOR, fr0), armIn(larEeFace(ee):TOPVECTOR, fr0), lnEnd, lnU, lnF, lnT,
            lnR, spd, jm, larLam2(larManip(jm), LAR_W0, LAR_LAM0), LAR_QD_MAX * ldS, dtk).
        LOCAL rt IS res[0].
        LOCAL tgs IS lnCm.                   // the running commands: the field holds them rounded to LAR_QSTEP
        SET lnQR TO larQRes(jm)[0].
        LOCAL hit IS larSoftHit(augNm, tgs, rt).
        IF hit >= 0 { RETURN "SOFT STOP " + augNm[hit] + " AT " + ROUND(tgs[hit], 1) + " DEG". }
        LOCAL sNow IS armNow(). LOCAL stl IS "".
        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH OR stl <> "" STEP { SET c TO c + 1. } DO {
            IF armOver(c, tgs[c], lnTg0[c], lnRel0[c], rt[c], sNow) { SET stl TO jts[augFr[c]][2]. }
        }
        SET lnStl TO larStallTick(lnStl, stl <> "", TIME:SECONDS).   // past the allowance for LAR_STALL_T, not a touch
        IF lnStl[1] { RETURN "STALL " + stl. }
        IF dOn {                             // the C# drive takes the rates; its commands read back
            LOCAL rl IS dZero:COPY.
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET rl[augFr[c]] TO rt[c]. }
            LOCAL th IS armRates(rl, LAR_TAU_J).
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET lnCm[c] TO th[augFr[c]]. }
        } ELSE {
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {
                LOCAL md2 IS jts[augFr[c]][1].
                md2:SETFIELD("traverse rate", ABS(rt[c]) + ARM_AUG_MARGIN).
                SET lnCm[c] TO lnCm[c] + rt[c] * dtk.
                md2:SETFIELD("target angle", lnCm[c]).
            }
        }
        SET lnR TO res[2]. SET lnEP TO res[3]:MAG.
        RETURN "".
    }
    FUNCTION armLdCal {                      // The joints' attitudes and angles at the dock, the zero of the measured POS while loaded (the arm is still unloaded here: the drive's command is the angle)
        SET ldCal TO LIST().
        LOCAL th0 IS armSt()[1].
        IF th0:LENGTH < jts:LENGTH { RETURN. }
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            LOCAL j IS jts[i].
            ldCal:ADD(LIST(armRel(j[3], j[0]), armRel(j[0], j[4]), th0[i])).
        }
    }
    FUNCTION armPosMeas {                    // The measured joint angles (deg) while loaded: cmd = the drive's commands (the fallback for a joint with no sign)
        PARAMETER cmd.
        LOCAL o IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            LOCAL j IS jts[i]. LOCAL c IS ldCal[i].
            o:ADD(larJtMeas(j[5] = LAR_HINGE, larSign(j[2]), c[2], c[0], c[1], armRel(j[3], j[0]), armRel(j[0], j[4]), cmd[i])).
        }
        RETURN o.
    }
    FUNCTION grpDock {                       // the LEE docked (on) or undocked (stE its state): the chain found again, the load
        PARAMETER on, stE.
        SET ldOn TO on. SET LAR_LDON TO on.   // T1018: the STALL check sized for a loaded arm (lib_arm larStallAl)
        LOCAL why IS grpRefind().
        IF why <> "" AND armBad = "" { armPr("GRAPPLE: THE ARM CHANGED: " + why + ": nothing moves; STOP and RUN arm again"). }
        SET armBad TO why.
        IF on {
            armPr("GRAPPLE: DOCKED (" + stE + ")" + (CHOOSE "; the chain found again (" + jts:LENGTH + " joints)" IF why = "" ELSE "")).
            IF why = "" { armLdCal(). } ELSE { SET ldCal TO LIST(). }
            grpWeigh().
            armDamp("DOCKED").
            IF grp = "CAP" { grpOff("docked (" + stE + ")", "CAPTURED" + (CHOOSE ": LATCHED" IF latched ELSE ": LOADED")). }
            IF aug { augOff("the LEE docked"). }
            IF auto { autoOff("the LEE docked", "AUTO OFF: THE LEE DOCKED"). }
            IF opr { oprOff("the LEE docked", "OPR CMD OFF: THE LEE DOCKED"). }
            IF drv { armLk(jts[sel][1]). SET drv TO FALSE. armPr(jts[sel][2] + ": stopped (the LEE docked)"). }
        } ELSE {
            SET latched TO FALSE. SET ldM TO 0. SET ldN TO 0. SET ldS TO 1. SET porOk TO FALSE. SET ldCal TO LIST().
            armPr("GRAPPLE: undocked (" + stE + "): the arm unloaded").
            armUnld().
            armDamp("UNDOCKED").
        }
    }
    FUNCTION grpWhy {                        // why the arm may not start CAPTURE / RELEASE now ("" it may)
        IF armBad <> "" { RETURN armWhy(). }
        IF augFr:LENGTH <> 6 OR augEl < 0 { RETURN "NOT A 6-JOINT RMS ARM (" + jts:LENGTH + " JOINTS)". }
        IF jts[augEl][1]:GETFIELD("target angle") <= LAR_AUG_ELBOW { RETURN "ELBOW AT OR BELOW " + LAR_AUG_ELBOW + ": UNSTOW FIRST". }
        IF drv { RETURN "A SINGLE DRIVE IS ON". }
        IF auto { RETURN "AUTO IS ON". }
        IF opr { RETURN "OPR CMD IS ON". }
        IF augMv { RETURN "MAN AUG IS MOVING". }
        IF asWhy = "" { SET asBlock TO armAsOff(). }
        ELSE IF bh:PRESSED { SET asBlock TO "". }
        ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
        RETURN asBlock.
    }
    // ---- the frames and OPR CMD's state: the POR on the payload (porL its components on the LEE's STAR / TOP / FORE
    // from the node; plF / plU the PL frame's forward and up the same way; porOk once weighed), the frame flown (frmI), the
    // shoulder (X / Y / Z's origin, in the shoulder's parent's frame), the move (op), its POR offset, stall references, checks
    LOCAL porL IS V(0, 0, 0). LOCAL plF IS V(0, 0, 1). LOCAL plU IS V(0, 1, 0). LOCAL porOk IS FALSE.
    LOCAL frmI IS 0. LOCAL frmSt IS "". LOCAL frmStT IS 0.
    LOCAL iSp IS -1.
    FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO { IF jts[i][2] = "SHOULDER PITCH" { SET iSp TO i. } }
    LOCAL orgR IS armIn(jts[0][0]:POSITION - root:POSITION, root:FACING).
    LOCAL opr IS FALSE. LOCAL oprSt IS "". LOCAL oprStT IS 0. LOCAL op IS LEXICON(). LOCAL opLd IS FALSE.
    LOCAL opTg0 IS LIST(). LOCAL opRel0 IS LIST(). LOCAL opHeldT IS -1. LOCAL opEndT IS -1.
    LOCAL opStl IS LIST(-1, FALSE).   // OPR CMD's stall timer (larStallTick)
    LOCAL opCm IS LIST().        // OPR CMD's running commands (deg, as augCm)
    LOCAL opCmM IS LIST().       // as augCmM
    LOCAL opAsk IS V(0, 0, 0). LOCAL opPWin IS V(0, 0, 0). LOCAL opTWin IS 0. LOCAL ipuO IS CONFIG:IPU. LOCAL opFirst IS TRUE.   // OPR CMD's first model window is not judged either
    FUNCTION frmLd {                         // frame i resolves on the payload (ORB LD, PL)
        PARAMETER i.
        RETURN i >= 2.
    }
    FUNCTION porNow {                        // now, in the shoulder's parent's frame: LIST(the node, the POR (the payload's when ld,
        PARAMETER ld.                        // else the node), the LEE's FORE, TOP, the attitude's view (PL's when ld, else END
        LOCAL fr0 IS root:FACING.            // EFF's), the aft-station view)
        LOCAL fc IS larEeFace(ee).
        LOCAL sv IS armIn(fc:STARVECTOR, fr0). LOCAL tv IS armIn(fc:TOPVECTOR, fr0). LOCAL fv IS armIn(fc:FOREVECTOR, fr0).
        LOCAL pN IS armIn(ee:POSITION + LAR_NODE_D * fc:FOREVECTOR - root:POSITION, fr0).
        LOCAL sf IS SHIP:FACING.
        LOCAL ov IS larOrbView(armIn(sf:STARVECTOR, fr0), armIn(sf:TOPVECTOR, fr0), armIn(sf:FOREVECTOR, fr0)).
        IF ld AND porOk {
            RETURN LIST(pN, larPorAt(pN, sv, tv, fv, porL), fv, tv,
                        larViewAxes(larPorAt(V(0, 0, 0), sv, tv, fv, plF), larPorAt(V(0, 0, 0), sv, tv, fv, plU)), ov).
        }
        RETURN LIST(pN, pN, fv, tv, larViewAxes(fv, tv), ov).
    }
    FUNCTION porSet {                        // LOADED: the POR (the payload's centre of mass) and the PL frame (the fixture's) kept
        LOCAL lc IS larLoadCom(ee).          // on the LEE's axes (rigid once captured)
        LOCAL fc IS larEeFace(ee).
        LOCAL pN IS ee:POSITION + LAR_NODE_D * fc:FOREVECTOR.
        SET porL TO larInEe(lc[0] - pN, fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR).
        LOCAL pv IS larViewAxes(fc:FOREVECTOR, fc:TOPVECTOR).
        LOCAL src IS "the fixture's".
        IF lc[3] {
            LOCAL pf IS CHOOSE lc[2]:PORTFACING IF lc[2]:HASSUFFIX("PORTFACING") ELSE lc[2]:FACING.
            SET pv TO larPlView(pf:FOREVECTOR, pf:TOPVECTOR).
        } ELSE { SET src TO "no fixture found: END EFF's". }
        SET plF TO larInEe(pv[2], fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR).
        SET plU TO larInEe(pv[1], fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR).
        SET porOk TO lc[1] > 0.
        armPr("GRAPPLE: the POR (the payload's centre of mass, " + ROUND(lc[1], 3) + " t) " + ROUND(porL:Z, 3) + " m along the boresight, "
            + ROUND(porL:X, 3) + " m right, " + ROUND(porL:Y, 3) + " m up of the node; the PL frame (" + src + ") "
            + ROUND(VANG(pv[2], fc:FOREVECTOR), 2) + " deg off the boresight, its up "
            + ROUND(ARCTAN2(VDOT(pv[1], fc:STARVECTOR), VDOT(pv[1], fc:TOPVECTOR)), 1) + " deg right of the LEE's TOP").
    }
    FUNCTION oprOff {                        // OPR CMD ended (why), the joints locked, its button released
        PARAMETER why, stText.
        FOR i IN augFr { armLk(jts[i][1]). }
        SET opr TO FALSE. SET bOpr:PRESSED TO FALSE.
        SET CONFIG:IPU TO ipuO.
        SET oprSt TO stText. SET oprStT TO TIME:SECONDS.
        armPr("OPR CMD off: " + why).
    }
    FUNCTION oprStart {                      // OPR CMD pressed: the move to the keyed pose (lib_arm larOprNew), or refused
        LOCAL why IS "".
        IF armBad <> "" { SET why TO armWhy(). }
        ELSE IF augFr:LENGTH <> 6 OR augEl < 0 OR iSp < 0 { SET why TO "NOT A 6-JOINT RMS ARM (" + jts:LENGTH + " JOINTS)". }
        ELSE IF jts[augEl][1]:GETFIELD("target angle") <= LAR_AUG_ELBOW { SET why TO "ELBOW AT OR BELOW " + LAR_AUG_ELBOW + ": UNSTOW FIRST". }
        ELSE IF drv { SET why TO "A SINGLE DRIVE IS ON". }
        ELSE IF aug { SET why TO "MAN AUG IS ON". }
        ELSE IF auto { SET why TO "AUTO IS ON". }
        ELSE IF grp <> "" { SET why TO (CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE") + " IS ON". }
        ELSE IF latched { SET why TO "LATCHED: THE PAYLOAD IS STILL HELD IN THE BAY". }
        LOCAL kv IS LIST().
        LOCAL kn IS LIST("X", "Y", "Z", "PITCH", "YAW", "ROLL").
        FROM { LOCAL i IS 0. } UNTIL i >= 6 OR why <> "" STEP { SET i TO i + 1. } DO {
            LOCAL x IS opFd[i]:TEXT:TRIM:TONUMBER(-1E9).
            IF x <= -1E9 { SET why TO kn[i] + " IS NOT A NUMBER (LOAD KEYS THE POSE NOW)". }
            kv:ADD(x).
        }
        LOCAL ld IS frmLd(frmI).
        IF why = "" {
            LOCAL pz IS porNow(ld).
            LOCAL p1 IS larXyzPose(V(kv[0], kv[1], kv[2]), orgR, pz[5]).
            LOCAL vw1 IS larEulerAxes(V(kv[3], kv[4], kv[5]), pz[5]).
            // the LEE's FORE and TOP at the keyed attitude: as they sit in the view now, in the keyed view
            LOCAL f1 IS larViewOut(larViewIn(pz[2], pz[4]), vw1).
            LOCAL t1 IS larViewOut(larViewIn(pz[3], pz[4]), vw1).
            LOCAL vern IS (CHOOSE LAR_VERNIER IF bv:PRESSED ELSE 1) * ldS.
            SET op TO larOprNew(pz[1], pz[2], pz[3], p1, f1, t1, LAR_V_COARSE * vern, LAR_W_COARSE * vern).
            LOCAL rg IS autoRoot().
            SET why TO larOprReach(larOprNodeEnd(op, pz[1] - pz[0]), rg[0], rg[1], iSp).
            IF why = "" AND op["s"] >= 1 { SET why TO "ALREADY AT THE POSE". }
            IF why = "" {
                LOCAL wk IS CHOOSE op["w"] / op["w"]:MAG IF op["w"]:MAG > 1E-9 ELSE V(0, 0, 0).
                LOCAL wv IS larViewIn(wk, pz[5]).
                armPr("OPR CMD (" + LAR_FRAMES[frmI] + ", the " + (CHOOSE "payload's POR" IF ld ELSE "node") + "): to X " + kv[0] + " Y "
                    + kv[1] + " Z " + kv[2] + " m, P " + kv[3] + " Y " + kv[4] + " R " + kv[5] + " deg; the line " + ROUND(op["dp"]:MAG, 3)
                    + " m, the turn " + ROUND(op["w"]:MAG / LAR_D2R, 2) + " deg about (right " + ROUND(wv:X, 3) + ", up " + ROUND(wv:Y, 3)
                    + ", aft " + ROUND(wv:Z, 3) + ") of the aft view, " + ROUND(op["T"], 1) + " s" + (CHOOSE " at VERNIER" IF bv:PRESSED ELSE "")
                    + (CHOOSE ", LOADED x " + ROUND(ldS, 3) IF ldOn ELSE "")).
            }
        }
        IF why = "" {                        // the autostrut first: no drive while an arm part has it on
            IF asWhy = "" { SET asBlock TO armAsOff(). }
            ELSE IF bh:PRESSED { SET asBlock TO "". }
            ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
            SET why TO asBlock.
        }
        IF why <> "" {
            SET bOpr:PRESSED TO FALSE.
            SET oprSt TO "OPR CMD REFUSED: " + why. SET oprStT TO TIME:SECONDS.
            armPr(oprSt).
            RETURN.
        }
        IF sel >= 0 { SET rb[sel]:PRESSED TO FALSE. SET sel TO -1. }
        SET opLd TO ld.
        SET opTg0 TO LIST(). SET opRel0 TO LIST(). SET opStl TO LIST(-1, FALSE).
        FOR i IN augFr {
            LOCAL md2 IS jts[i][1].
            IF jSave[i][0] < 0 { SET jSave[i] TO LIST(CHOOSE 1 IF md2:GETFIELD("locked") ELSE 0, md2:GETFIELD("traverse rate")). }
            md2:SETFIELD("locked", FALSE).
            opTg0:ADD(md2:GETFIELD("target angle")).
            opRel0:ADD(LIST(armRel(jts[i][3], jts[i][0]), armRel(jts[i][0], jts[i][4]))).
        }
        IF dOn { LOCAL th0 IS armSt()[1]. FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET opTg0[c] TO th0[augFr[c]]. } }
        SET opCm TO opTg0:COPY. SET opCmM TO opTg0:COPY.
        SET ipuO TO CONFIG:IPU. SET CONFIG:IPU TO MAX(ipuO, ARM_AUG_IPU).
        SET opr TO TRUE. SET opHeldT TO -1. SET opEndT TO -1. SET oprSt TO "OPR CMD 0 %".
        SET opAsk TO V(0, 0, 0). SET opPWin TO porNow(FALSE)[0]. SET opTWin TO TIME:SECONDS. SET opFirst TO TRUE.
    }
    FUNCTION oprTick {                       // one tick of OPR CMD (lib_arm larOprTick): arrived, its checks, the joints driven
        PARAMETER tn, dtk.
        LOCAL fr0 IS root:FACING.
        LOCAL gm IS larGeom(jts, ee).
        LOCAL pNow IS armIn(gm[0] - root:POSITION, fr0).
        LOCAL gs2 IS LIST().
        FOR gg IN gm[1] { gs2:ADD(LIST(armIn(gg[0] - root:POSITION, fr0), armIn(gg[1], fr0), gg[2])). }
        LOCAL pz IS porNow(opLd).
        LOCAL pPor IS pNow + (pz[1] - pz[0]).
        LOCAL lf IS larOprLeft(op, pPor, pz[2], pz[3]).
        LOCAL jm IS larJacob(pNow, gs2, augHeld).
        LOCAL qr IS larQRes(jm).                 // the arm's resolution: ARRIVED within it (whole-degree joints)
        IF op["s"] >= 1 {
            IF opEndT < 0 { SET opEndT TO tn. }
            IF lf[0] < LAR_OPR_TOL + qr[0] AND lf[1] < LAR_OPR_TOLA + qr[1] {
                oprOff("ARRIVED: the POR " + ROUND(lf[0] * 1000, 1) + " mm and " + ROUND(lf[1], 2) + " deg from the keyed pose",
                    "OPR CMD ARRIVED: " + ROUND(lf[0], 3) + " M, " + ROUND(lf[1], 2) + " DEG OFF").
                RETURN.
            }
            IF tn - opEndT > ARM_OPR_SETTLE_T {
                oprOff("NOT SETTLED " + ARM_OPR_SETTLE_T + " s after the line's end: " + ROUND(lf[0] * 1000, 1) + " mm, " + ROUND(lf[1], 2)
                    + " deg off", "OPR CMD OFF: NOT SETTLED (" + ROUND(lf[0], 3) + " M, " + ROUND(lf[1], 1) + " DEG OFF)").
                RETURN.
            }
        }
        LOCAL wm IS larManip(jm).
        LOCAL res IS larOprTick(op, pPor, pz[2], pz[3], pPor - pNow, jm, larLam2(wm, LAR_W0, LAR_LAM0), LAR_QD_MAX * ldS, dtk).
        LOCAL rt IS res[0].
        LOCAL tgs IS opCm.                   // the running commands: the field holds them rounded to LAR_QSTEP
        LOCAL hit IS larSoftHit(augNm, tgs, rt).
        IF hit >= 0 {
            oprOff("SOFT STOP " + augNm[hit] + " at " + ROUND(tgs[hit], 1) + " deg", "OPR CMD OFF: SOFT STOP " + augNm[hit]).
            RETURN.
        }
        LOCAL sNow IS armNow(). LOCAL stl IS "".
        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH OR stl <> "" STEP { SET c TO c + 1. } DO {
            IF armOver(c, tgs[c], opTg0[c], opRel0[c], rt[c], sNow) { SET stl TO jts[augFr[c]][2]. }
        }
        SET opStl TO larStallTick(opStl, stl <> "", tn).   // past the allowance for LAR_STALL_T, not a touch
        IF opStl[1] { oprOff("STALL " + stl, "OPR CMD OFF: STALL " + stl). RETURN. }
        IF res[4] OR op["s"] >= 1 { SET opHeldT TO -1. }
        ELSE IF opHeldT < 0 { SET opHeldT TO tn. }
        IF opHeldT >= 0 AND tn - opHeldT > ARM_OPR_HELD_T {
            oprOff("HELD " + ARM_OPR_HELD_T + " s: the POR " + ROUND(res[2]:MAG, 3) + " m and " + ROUND(ARCSIN(MIN(1, res[3]:MAG)), 2)
                + " deg behind the line", "OPR CMD OFF: HELD (THE ARM CANNOT KEEP UP)").
            RETURN.
        }
        LOCAL lin IS V(0, 0, 0).
        LOCAL dTh IS LIST().                 // each joint's commanded change this tick (deg)
        IF dOn AND sNow:LENGTH > 0 {
            LOCAL rl IS dZero:COPY.
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET rl[augFr[c]] TO rt[c]. }
            LOCAL th IS armRates(rl, LAR_TAU_J).
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {   // asked: between measurements
                dTh:ADD(sNow[1][augFr[c]] - opCmM[c]). SET opCmM[c] TO sNow[1][augFr[c]]. SET opCm[c] TO th[augFr[c]].
            }
        } ELSE {
            FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {
                LOCAL md2 IS jts[augFr[c]][1].
                md2:SETFIELD("traverse rate", ABS(rt[c]) + ARM_AUG_MARGIN).
                SET opCm[c] TO opCm[c] + rt[c] * dtk.
                md2:SETFIELD("target angle", opCm[c]).
                dTh:ADD(rt[c] * dtk).
            }
        }
        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {
            SET lin TO lin + V(jm[0][c], jm[1][c], jm[2][c]) * (dTh[c] * LAR_D2R).
        }
        SET opAsk TO opAsk + lin.
        LOCAL oq IS larQuant(jm).                // the model check: the node's move over the window against the one asked for,
        IF larModelDue(tn - opTWin, ARM_AUG_WIN, opAsk, V(0, 0, 0), oq) {   // what the whole-degree steps hide allowed for
            IF NOT opFirst AND larModelBad(opAsk, pNow - opPWin, oq[0]) {
                oprOff("MODEL: asked " + ROUND(opAsk:MAG, 3) + " m, moved " + ROUND((pNow - opPWin):MAG, 3) + " m, missed by "
                    + ROUND((pNow - opPWin - opAsk):MAG, 3) + " m", "OPR CMD OFF: MODEL").
                RETURN.
            }
            SET opAsk TO V(0, 0, 0). SET opPWin TO pNow. SET opTWin TO tn. SET opFirst TO FALSE.
        }
        SET oprSt TO "OPR CMD " + ROUND(100 * op["s"]) + " %  TO GO " + ROUND(lf[0], 2) + " M " + ROUND(lf[1], 1) + " DEG"
            + (CHOOSE "  RATE LIMITED" IF res[1] < 1 ELSE "") + (CHOOSE "  SINGULAR" IF wm < LAR_W0 ELSE "")
            + (CHOOSE "  HELD" IF opHeldT >= 0 ELSE "").
    }
    FOR j IN jts { jSave:ADD(LIST(-1, 0)). }
    LOCAL dmpWas IS LIST().      // each joint's damping at RUN arm (ARM_DAMP while the arm runs, back at STOP)
    LOCAL dmpTx IS "".
    FOR j IN jts {
        LOCAL d0 IS CHOOSE j[1]:GETFIELD(LAR_F_DAMP) IF j[1]:HASFIELD(LAR_F_DAMP) ELSE -1.
        dmpWas:ADD(d0).
        IF d0 >= 0 {
            j[1]:SETFIELD(LAR_F_DAMP, ARM_DAMP).
            SET dmpTx TO dmpTx + " " + j[2] + " " + ROUND(d0) + " -> " + ROUND(j[1]:GETFIELD(LAR_F_DAMP)) + ";".
        } ELSE { SET dmpTx TO dmpTx + " " + j[2] + " NO DAMPING FIELD;". }
    }
    armPr("arm: damping" + dmpTx).
    // the C# drive (ADDONS:KALS:ARMDRIVE): every joint's command unrounded every physics tick, the dampers set for the
    // inertia outboard of each joint (ARM_ZETA); the kOS path (whole degrees) when it is not there or ARM_DLL is FALSE
    LOCAL dOn IS FALSE. LOCAL dWhy IS "".
    LOCAL dBack IS FALSE. LOCAL dBackT IS 0. LOCAL dBackWhy IS "".   // The drive let go only for the active vessel: bind it again when the orbiter is active and the arm idle
    LOCAL dBackDt IS 1.                      // s between the tries
    LOCAL dZero IS LIST(). FOR j IN jts { dZero:ADD(0). }
    FOR j IN jts {                           // The slew set, a slot per joint
        swPh:ADD(0). swTg:ADD(0). swCm:ADD(0). swTg0:ADD(0). swRS:ADD(0). swRC:ADD(0).
        swLast:ADD(0). swStill:ADD(0). swTEnd:ADD(-1). swStl:ADD(LIST(-1, FALSE)). swR2p:ADD(0). swRl:ADD(0).
    }
    IF NOT ARM_DLL { SET dWhy TO "ARM_DLL FALSE". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("ARMDRIVE") { SET dWhy TO "AN OLDER KalsCoproc.dll (NO ARMDRIVE)". }
    ELSE {
        LOCAL pl IS LIST(). FOR j IN jts { pl:ADD(j[0]). }
        SET dWhy TO ADDONS:KALS:ARMDRIVE(pl).
        SET dOn TO dWhy = "".
    }
    SET LAR_DRV TO dOn.
    FUNCTION armDamp {                       // the dampers for ARM_ZETA on the inertia now (RUN, a dock / undock), logged
        PARAMETER why.
        IF NOT dOn OR ARM_ZETA <= 0 { RETURN. }
        FOR dl IN ADDONS:KALS:ARMDAMP(ARM_ZETA) { armPr("DAMP (" + why + ") " + dl). }
    }
    FUNCTION armSt {                         // ARMSTATE with a joint list for EVERY joint, always. The C# drive lets go at an undock (the vessel splits: its
        LOCAL s IS ADDONS:KALS:ARMSTATE.     // lists come back EMPTY, ArmStateOf with no drive): then kOS's own commands in the same shape (and the main loop's let-go
        IF s[0] AND s[1]:LENGTH >= jts:LENGTH AND s[2]:LENGTH >= jts:LENGTH { RETURN CHOOSE LIST(s[0], ldhCmd(s[1]), s[2], s[3], s[4], s[5]) IF ldhOn ELSE s. }   // T1018: the loaded hold's trim is not the command   // test falls back to the kOS path at its next pass)
        LOCAL tg IS LIST().
        FOR j IN jts { tg:ADD(j[1]:GETFIELD("target angle")). }
        RETURN LIST(FALSE, tg, dZero:COPY, FALSE, "", s[5]).
    }
    FUNCTION armRates {                      // the C# drive's joints at rates rl (deg/s, a joint each) through tau: its commands
        PARAMETER rl, tau.
        LOCAL rr IS rl.
        IF ldhOn {                           // T1018: the loaded hold's correction rides on every send of the pass
            SET rr TO rl:COPY.
            FROM { LOCAL i IS 0. } UNTIL i >= rr:LENGTH STEP { SET i TO i + 1. } DO { SET rr[i] TO rr[i] + ldhCorr[i]. }
            SET ldhSent TO TRUE.
        }
        LOCAL rtn IS ADDONS:KALS:ARMRATE(rr, tau)[1].
        IF rtn:LENGTH < jts:LENGTH { RETURN armSt()[1]. }     // The drive let go under this call
        RETURN CHOOSE ldhCmd(rtn) IF ldhOn ELSE rtn.
    }
    FUNCTION ldhCmd {                        // T1018: the drive's commands less the hold's trim = the commands the modes asked for
        PARAMETER l.
        LOCAL o IS l:COPY.
        FROM { LOCAL i IS 0. } UNTIL i >= o:LENGTH STEP { SET i TO i + 1. } DO { SET o[i] TO l[i] - ldhTr[i]. }
        RETURN o.
    }
    FUNCTION armMeasGet {                    // T1018: the measured joint angles, worked out once a pass (ldhTick clears it): the hold and the page share them
        PARAMETER cmd.
        IF ldhMeas:LENGTH < jts:LENGTH { SET ldhMeas TO armPosMeas(cmd). }
        RETURN ldhMeas.
    }
    FUNCTION ldhTick {                       // T1018: once a pass, before any mode sends: LOADED = every joint unlocked on the drive and pulled back to its command on its measured angle
        PARAMETER tn, dt.
        SET ldhMeas TO LIST(). SET ldhSent TO FALSE.
        LOCAL want IS ARM_LDH_ON AND dOn AND ldOn AND NOT ARM_LOCK_LOADED AND NOT latched AND armBad = "" AND NOT auto AND ldCal:LENGTH = jts:LENGTH.
        IF NOT want {
            IF ldhOn {
                SET ldhOn TO FALSE. SET ldhTr TO dZero:COPY. SET ldhCorr TO dZero:COPY.
                armPr("LOADED HOLD OFF (" + (CHOOSE "AUTO" IF auto ELSE "unloaded, latched, bad or drive let go") + ")").
            }
            RETURN.
        }
        IF NOT ldhOn {                       // engage: the autostrut off first (as a drive), then every joint unlocked: the C# drive seeds each where its drive is
            IF tn < ldhNoT { RETURN. }
            LOCAL why IS "".
            IF asWhy = "" { SET why TO armAsOff(). }
            ELSE IF NOT bh:PRESSED { SET why TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
            IF why <> "" {
                SET ldhNoT TO tn + 5.
                IF why <> ldhWhy { SET ldhWhy TO why. gotoSay("LOADED: JOINTS NOT HELD: " + why). }
                RETURN.
            }
            FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
                LOCAL md IS jts[i][1].
                IF jSave[i][0] < 0 { SET jSave[i] TO LIST(CHOOSE 1 IF md:GETFIELD("locked") ELSE 0, md:GETFIELD("traverse rate")). }
                IF md:GETFIELD("locked") { md:SETFIELD("locked", FALSE). }
            }
            SET ldhOn TO TRUE. SET ldhTr TO dZero:COPY. SET ldhCorr TO dZero:COPY. SET ldhWhy TO "".
            SET ldhZ TO LIST(). SET ldhM0 TO dZero:COPY. SET ldhZT TO LIST().
            FOR jq IN jts { ldhZ:ADD(NOT ARM_LDH_ZERO). ldhZT:ADD(-1). }
            armPr("LOADED HOLD ON: every joint unlocked on the C# drive, pulled back to its command on its measured angle (" + ARM_LDH_K + " /s, at most " + ARM_LDH_R + " deg/s, "
                + ARM_LDH_MAX + " deg)").
            RETURN.                          // measured and corrected from the next pass: the drive seeds the unlocked joints in its next tick
        }
        LOCAL cmdL IS armSt()[1].
        LOCAL ms IS armMeasGet(cmdL).
        SET ldhCorr TO dZero:COPY.
        LOCAL dtc IS MAX(0.02, MIN(0.5, dt)).
        LOCAL mx IS 0.
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            LOCAL e IS cmdL[i] - ms[i].
            LOCAL rg IS LAR_RANGE[jts[i][2]].
            LOCAL c IS 0.
            IF NOT ldhZ[i] {                 // the measured zero first: the joint still on its drive for ARM_LDH_ZT s = at its command
                IF ldhZT[i] < 0 OR ABS(ms[i] - ldhM0[i]) > ARM_LDH_ZB { SET ldhM0[i] TO ms[i]. SET ldhZT[i] TO tn. }
                ELSE IF tn - ldhZT[i] >= ARM_LDH_ZT {
                    SET ldCal[i][2] TO ldCal[i][2] + e.
                    SET ldhZ[i] TO TRUE. SET ldhMeas TO LIST().
                    IF ABS(e) >= 0.3 { armPr("LOADED HOLD: " + jts[i][2] + " measured zero moved " + ROUND(e, 2) + " deg (it sat still that far off its command)"). }
                }
            }
            ELSE IF ABS(e) > ARM_LDH_DB { SET c TO MAX(-ARM_LDH_R, MIN(ARM_LDH_R, ARM_LDH_K * (e - (CHOOSE ARM_LDH_DB IF e > 0 ELSE -ARM_LDH_DB)))). }
            LOCAL nt IS ldhTr[i] + c * dtc.
            IF ABS(nt) > ARM_LDH_MAX AND ABS(nt) > ABS(ldhTr[i]) { SET c TO 0. }                  // the bound: no further out
            ELSE IF cmdL[i] + nt < rg[0] + 1 OR cmdL[i] + nt > rg[1] - 1 { IF ABS(nt) > ABS(ldhTr[i]) { SET c TO 0. } }   // the range's ends: the drive clamps there
            SET ldhCorr[i] TO c. SET ldhTr[i] TO ldhTr[i] + c * dtc.
            SET mx TO MAX(mx, ABS(ldhTr[i])).
        }
    }
    FUNCTION armNow {                        // the C# drive's state now for a stall check (LIST() on the kOS path, or when the drive has just let go)
        IF NOT dOn { RETURN LIST(). }
        LOCAL s IS armSt().
        RETURN CHOOSE s IF s[0] ELSE LIST().
    }
    FUNCTION armOver {                       // joint augFr[c] trails its command past larStallAl: the C# drive's command now
        PARAMETER c, cm, tg0, rel0, rt, sNow.   // (sNow = armNow(): kOS's last read is a whole loop old, ~1 s at IPU 200, so a
        LOCAL i IS augFr[c].                 // reversing joint looked ~2 deg behind), else kOS's own command cm; rate rt (deg/s)
        LOCAL jj IS jts[i].
        LOCAL mvd IS MAX(armTurn(rel0[0], armRel(jj[3], jj[0])), armTurn(rel0[1], armRel(jj[0], jj[4]))).
        IF sNow:LENGTH > 0 { RETURN ABS(sNow[1][i] - tg0) - mvd > larStallAl(MAX(ABS(rt), ABS(sNow[2][i])), ARM_STALL). }
        RETURN ABS(cm - tg0) - mvd > larStallAl(rt, ARM_STALL).
    }
    IF dOn {
        SET LAR_QSTEP TO LAR_QSTEP_DRV.
        armPr("arm: DRIVE C# (every physics tick, unrounded; smoothing " + ARM_TAU + " s, damping ratio " + ARM_ZETA + ")").
        armDamp("RUN").
    } ELSE { armPr("arm: DRIVE kOS (whole degrees): " + dWhy). }
    LOCAL tg0 IS 0. LOCAL cmd IS 0. LOCAL rS0 IS 0. LOCAL rC0 IS 0.
    LOCAL stall IS FALSE. LOCAL tEnd IS -1. LOCAL last IS 0. LOCAL still IS 0.
    LOCAL sT1 IS LIST(-1, FALSE).    // SINGLE's stall timer (larStallTick)
    LOCAL tPrev IS TIME:SECONDS.
    // ---- the end effector camera (ARM-CAM): kOS StockCamera 0.3.1's FREECAMERA, anchored to the LEE
    LOCAL cam IS 0. LOCAL camOK IS FALSE. LOCAL camOn IS FALSE. LOCAL camSt IS "". LOCAL camStT IS 0.
    IF ADDONS:HASSUFFIX("CAMERA") {
        IF ADDONS:CAMERA:HASSUFFIX("FREECAMERA") { SET cam TO ADDONS:CAMERA:FREECAMERA. SET camOK TO TRUE. }
    }
    FUNCTION camSnap {                       // the flight camera snapped to the end effector's view: "" or why not
        IF NOT camOK { RETURN "NO FREE CAMERA (kOS StockCamera 0.3.1 NEEDED)". }
        IF NOT cam:AVAILABLE { RETURN "NO FLIGHT CAMERA NOW". }
        LOCAL fc IS larEeFace(ee).
        LOCAL cp IS larCamPose(ee:POSITION, fc:STARVECTOR, fc:TOPVECTOR, fc:FOREVECTOR).
        SET cam:ANCHOR TO ee.                // first: SETPOSE's pose is then kept in the LEE's own space (lib_hud hdCamSnap's order)
        SET cam:ENABLED TO TRUE.
        cam:SETPOSE(cp[0], LOOKDIRUP(cp[1], cp[2])).
        armPr("EE CAM ON: the eye at the LEE's node, along its boresight, its TOP up; the LEE's PORTFACING "
            + ROUND(VANG(ee:PORTFACING:FOREVECTOR, fc:FOREVECTOR), 2) + " deg off its FACING (" + cam:STATUS + ")").
        IF fxOk {                            // where the picture should show the fixture (the in-game check of the view)
            LOCAL sp IS larCamSee(cp, fx:NODEPOSITION).
            armPr("EE CAM: the fixture " + fx:TITLE + "'s node should show " + ROUND(sp:X, 3) + " m right, " + ROUND(sp:Y, 3)
                + " m up, " + ROUND(sp:Z, 3) + " m ahead").
        }
        RETURN "".
    }
    FUNCTION camOff {                        // the view back to the stock camera (the addon restores it and its FOV)
        PARAMETER why.
        SET cam:ENABLED TO FALSE.
        SET camOn TO FALSE. SET bCam:PRESSED TO FALSE.
        IF ADDONS:KALS:HASSUFFIX("EECROSS") { ADDONS:KALS:EECROSS(0). }   // The cross goes with the view
        SET camSt TO "EE CAM OFF (" + why + ")". SET camStT TO TIME:SECONDS.
        armPr(camSt + ": the stock camera back").
    }
    LOCAL pubPor IS LIST(V(0, 0, 0), V(0, 0, 0)).   // the POR now (m: X aft, Y starboard, Z up of the shoulder) and its attitude P / Y / R (deg), set each pass
    FUNCTION armSnap {                       // what the PDRS page shows (ops2q), read once a pass: no widget is touched
        LOCAL tg IS LIST().
        FOR j IN jts { tg:ADD(j[1]:GETFIELD("target angle")). }
        LOCAL as IS CHOOSE armSt() IF dOn ELSE LIST(FALSE, tg, dZero, FALSE, "", "").
        IF ldhOn { SET tg TO as[1]. }          // T1018: the written target carries the hold trim: CMD is the commanded angle
        // loaded, the joints hold their targets on the servo's own drive (no lock), so a payload sags / swings them off the command: POS is then measured from the parts, against the angles at the dock
        LOCAL thP IS as[1].
        IF ldOn AND armBad = "" AND ldCal:LENGTH = jts:LENGTH AND thP:LENGTH >= jts:LENGTH {
            SET thP TO armMeasGet(as[1]).
        }
        RETURN LEXICON("mode", CHOOSE "OPR CMD" IF opr ELSE (CHOOSE "MAN AUG" IF aug ELSE (CHOOSE "AUTO" IF auto ELSE "SINGLE")),
            "sel", sel, "aug", aug, "augMv", augMv, "opr", opr, "auto", auto, "asel", asel, "grp", grp, "drv", drv, "stall", stall,
            "latched", latched, "ld", ldOn, "ldM", ldM, "ldN", ldN, "ldS", ldS, "frm", frmI, "por", pubPor, "bad", armBad,
            "cam", camOn, "hold", hMd, "hOk", hOk, "rcsBad", armRcsBad(), "dOn", dOn, "tg", tg, "th", thP, "rt", as[2], "gt", LIST(swN > 0, swLastX, swLastJ), "gts", swList(), "st", st:TEXT, "sayN", gSayN, "ldh", ldhOn, "ldtr", ldhTr).
    }
    FUNCTION gotoSay {                       // A slew's word: the status line (5 s after it ends) and the log
        PARAMETER s.
        SET gotoSt TO s. SET gotoStT TO TIME:SECONDS. SET gSayN TO gSayN + 1. armPr(s).   // T1018: gSayN = the page's cue for a repeated word
    }
    FUNCTION swList {                        // Each joint's typed target while its slew runs, else 1E9 (the page shows the target on that joint's CMD)
        LOCAL l IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO { l:ADD(CHOOSE swTg[i] IF swPh[i] = 1 ELSE 1E9). }
        RETURN l.
    }
    FUNCTION swWords {                       // the status line with several slews: SLEW J1 TO x, J3 TO y
        LOCAL w IS "SLEW".
        LOCAL n IS 0.
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            IF swPh[i] = 1 { SET w TO w + (CHOOSE " " IF n = 0 ELSE ", ") + jts[i][2] + " TO " + ROUND(swTg[i], 1). SET n TO n + 1. }
        }
        RETURN w + " DEG".
    }
    FUNCTION swCount {
        LOCAL n IS 0.
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO { IF swPh[i] > 0 { SET n TO n + 1. } }
        SET swN TO n.
    }
    FUNCTION swCancelAll {                   // STOP / a mode / a hold / a latch / RCS / a stall: every slew ends, each joint locked at once (as a joint select locks the driven joint)
        PARAMETER msg.
        IF swN = 0 { RETURN. }
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            IF swPh[i] > 0 { armLk(jts[i][1]). SET swPh[i] TO 0. }
        }
        SET swN TO 0. SET swRl TO dZero:COPY.
        IF dOn { armRates(dZero, ARM_TAU). }
        gotoSay(msg).
    }
    FUNCTION swBegin {                       // joint jj slews to x: a fresh slew first takes the autostrut, unlocks the joint, takes the references; one already stopping just gets its new target
        PARAMETER jj, x.
        LOCAL j IS jts[jj].
        LOCAL md IS j[1].
        IF swPh[jj] = 0 {
            IF asWhy = "" { SET asBlock TO armAsOff(). }
            ELSE IF bh:PRESSED { SET asBlock TO "". }
            ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
            IF asBlock <> "" { gotoSay("SLEW REFUSED: " + asBlock). RETURN. }
            IF jSave[jj][0] < 0 { SET jSave[jj] TO LIST(CHOOSE 1 IF md:GETFIELD("locked") ELSE 0, md:GETFIELD("traverse rate")). }
            md:SETFIELD("locked", FALSE).
            SET swCm[jj] TO CHOOSE armSt()[1][jj] IF dOn ELSE md:GETFIELD("target angle").
            SET swTg0[jj] TO swCm[jj].
            SET swRS[jj] TO armRel(j[3], j[0]). SET swRC[jj] TO armRel(j[0], j[4]).
            SET swLast[jj] TO 0. SET swStill[jj] TO 0. SET swTEnd[jj] TO -1. SET swR2p[jj] TO 0.
        }
        SET swStl[jj] TO LIST(-1, FALSE).
        SET swTg[jj] TO x. SET swPh[jj] TO 1. SET swLastJ TO jj. SET swLastX TO x.
        swCount().
        gotoSay("SLEW " + j[2] + " TO " + ROUND(x, 1) + " DEG (" + (CHOOSE "VERNIER" IF bv:PRESSED ELSE "COARSE") + ")" + (CHOOSE ", " + (swN - 1) + " MORE" IF swN > 1 ELSE "")).
    }
    FUNCTION armSlew {                       // ARM_ACT "slew": the PDRS page's TYPE + ENT on a joint's CMD: SINGLE slews that joint to the typed target
        PARAMETER x, ji IS -1.               // (deg) at COARSE (VERNIER with VERN, the THC FORWARD boost); a soft stop refused; the joint is locked at the end
        // ji = the joint whose CMD field was typed (-1 = the picked one);
        // Any number of joints slew at once, each to its own typed target, picked or not (a pick, the THC on another joint, a typed value on a third touch nothing)
        LOCAL jj IS CHOOSE sel IF ji < 0 ELSE ji.
        IF jj < 0 OR jj >= jts:LENGTH { gotoSay("SLEW REFUSED: NO JOINT PICKED"). RETURN. }
        LOCAL j IS jts[jj].
        LOCAL pb IS larPoseBad(LIST(j[2]), LIST(x)).
        LOCAL why IS "".
        IF jj = sel AND ABS(armThc():Y) > ARM_DB { SET why TO "THE THC IS IN USE". }
        ELSE IF drv AND jj = sel { SET why TO "A DRIVE IS ON". }
        ELSE IF aug { SET why TO "MAN AUG IS ON". }
        ELSE IF opr { SET why TO "OPR CMD IS ON". }
        ELSE IF auto { SET why TO "AUTO IS ON". }
        ELSE IF armRcsBad() { SET why TO "RCS ON (THE THC WOULD TRANSLATE THE ORBITER)". }
        ELSE IF grp <> "" { SET why TO "CAPTURE OR RELEASE IS ON". }
        ELSE IF latched { SET why TO "LATCHED: THE PAYLOAD IS STILL HELD IN THE BAY". }
        ELSE IF armBad <> "" { SET why TO armWhy(). }
        ELSE IF pb <> "" { SET why TO larSoftWords(j[2]). }
        IF why <> "" { gotoSay("SLEW REFUSED: " + why). RETURN. }
        swBegin(jj, x).
    }
    FUNCTION swTick {                        // Every slew one step, the law per joint (the stop point predicted from the flown rate's tail, the input steering it onto the target)
        PARAMETER tn, dt, fwd, inp.           // fwd = THC FORWARD 0 .. 1 (the SINGLE COARSE boost applies to a slew too), inp = THC Y (the picked joint's stick)
        LOCAL why IS "".
        IF aug OR opr OR auto OR bAug:PRESSED OR bOpr:PRESSED { SET why TO "A MODE TOOK THE ARM". }
        ELSE IF grp <> "" OR bGrp:PRESSED OR bCap:PRESSED OR bRel:PRESSED { SET why TO "CAPTURE OR RELEASE". }
        ELSE IF latched { SET why TO "LATCHED". }
        ELSE IF armBad <> "" { SET why TO armWhy(). }
        ELSE IF armRcsBad() { SET why TO "RCS ON". }
        FOR ab IN abt { IF ab[0]:PRESSED { SET why TO "AUTO". } }
        IF why <> "" { swCancelAll("SLEW STOPPED: " + why). RETURN. }
        LOCAL st0 IS CHOOSE armSt() IF dOn ELSE LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            IF swPh[i] > 0 {
                LOCAL j IS jts[i].
                LOCAL md IS j[1].
                LOCAL mv IS MAX(armTurn(swRS[i], armRel(j[3], j[0])), armTurn(swRC[i], armRel(j[0], j[4]))).
                IF swPh[i] = 1 {
                    LOCAL gCur IS CHOOSE st0[1][i] IF dOn ELSE swCm[i].
                    IF dOn { SET swCm[i] TO gCur. }          // the kOS path's running command follows the drive's, so a drive that lets go mid-slew hands over from where the joint is
                    LOCAL gErr IS swTg[i] - gCur.
                    LOCAL gEps IS gErr.                      // The stop point's error (the kOS path: the command has no tail, so the command's error)
                    LOCAL gU IS 0.
                    IF dOn {                                 // the C# command runs on past the input's cut by the flown rate's tail (2 x ARM_TAU x rate): the stop point is predicted
                        LOCAL gR2 IS st0[2][i].              // the flown rate now (deg/s)
                        LOCAL gR1 IS gR2 + ARM_TAU * (gR2 - swR2p[i]) / MAX(dt, 0.02).     // its first stage, from R2' = (R1 - R2) / tau
                        SET swR2p[i] TO gR2.
                        SET gEps TO swTg[i] - (gCur + ARM_TAU * (gR1 + gR2)).
                        SET gU TO MIN(ARM_GOTO_K, 0.5 / MAX(dt, 0.02)) * gEps.      // the input steers the stop point onto the target (the gain capped so each pass stays stable)
                    }
                    IF i = sel AND ABS(inp) > ARM_DB {       // the stick took the picked joint: ITS slew ends (no lock: the stick drive starts from where it is), the others run on
                        SET swPh[i] TO 0.
                        gotoSay("SLEW " + j[2] + " STOPPED AT " + ROUND(gCur, 1) + " DEG (THC)").
                    } ELSE IF ABS(gErr) <= ARM_GOTO_TOL AND ABS(gEps) <= ARM_GOTO_TOL {
                        SET swPh[i] TO 2. SET swTEnd[i] TO -1.
                        gotoSay(j[2] + " ARRIVED AT " + ROUND(gCur, 1) + " DEG").
                    } ELSE {
                        LOCAL dir IS 0.
                        IF dOn { SET dir TO CHOOSE 1 IF gU >= ARM_GOTO_MIN ELSE (CHOOSE -1 IF gU <= -ARM_GOTO_MIN ELSE 0). }
                        ELSE { SET dir TO CHOOSE 1 IF gErr > 0 ELSE -1. }
                        LOCAL rate IS (CHOOSE ARM_RATE_V IF bv:PRESSED ELSE (CHOOSE ARM_RATE_C_WR IF j[2] = "WRIST ROLL"
                            ELSE ARM_RATE_C + fwd * (ARM_RATE_BOOST - ARM_RATE_C))) * ldS.
                        IF dOn { SET rate TO MIN(rate, ABS(gU)). } ELSE { SET rate TO MIN(rate, ABS(gErr) / MAX(dt, 0.02)). }   // the last step lands on the target, never past it
                        // a STALL: the joint trailing its command past the stall margin + its rate's own lag (larStallAl) for LAR_STALL_T (as the stick drive)
                        SET swStl[i] TO larStallTick(swStl[i], ABS(gCur - swTg0[i]) - mv > larStallAl(rate, ARM_STALL), tn).
                        IF swStl[i][1] {
                            swCancelAll("SLEW STALLED AT " + ROUND(gCur, 1) + " DEG (" + j[2] + ")").
                            RETURN.
                        }
                        IF dOn { SET swRl[i] TO dir * rate. }
                        ELSE {
                            md:SETFIELD("traverse rate", rate).         // the kOS path unchanged (a faster traverse turns each step into a rate step)
                            SET swCm[i] TO swCm[i] + dir * rate * dt.
                            md:SETFIELD("target angle", swCm[i]).
                        }
                    }
                } ELSE {                             // stopping: the C# drive slows the joint to rest (its rate 0 in swRl), locked once it has stopped
                    IF swTEnd[i] < 0 { SET swTEnd[i] TO tn. }
                    IF ABS(mv - swLast[i]) < ARM_STILL { SET swStill[i] TO swStill[i] + 1. } ELSE { SET swStill[i] TO 0. }
                    IF swStill[i] >= 5 OR tn - swTEnd[i] > ARM_STILL_T {
                        armLk(md).
                        SET swPh[i] TO 0.
                        armPr(j[2] + ": slew ended (moved " + ROUND(mv, 2) + " deg)").
                    }
                }
                SET swLast[i] TO mv.
            }
        }
        swCount().
    }
    FUNCTION armCycle {                      // one pass of the loop (the window runs it every tick, ops2q every pass)
        LOCAL tn IS TIME:SECONDS.
        LOCAL dt IS MIN(0.5, tn - tPrev).
        SET tPrev TO tn.
        ldhTick(tn, dt).                 // T1018: the loaded hold (before any mode sends its rates)
        larMpmTick(). armMpmSync().      // The MPM roll locked when its go is over; armBad follows whether it is MOVING
        // the hold: a newly pressed mode takes the attitude now and releases the others; the pressed mode pressed again
        // (released) takes it again
        IF hOk AND NOT ARM_HOLD_EXT {
            LOCAL hPick IS "".
            FOR hb IN hBt { IF hb[1]:PRESSED AND hb[0] <> hMd { SET hPick TO hb[0]. } }
            IF hPick <> "" {
                FOR hb IN hBt { IF hb[0] <> hPick AND hb[1]:PRESSED { SET hb[1]:PRESSED TO FALSE. } }
                holdSet(hPick).
            } ELSE {
                FOR hb IN hBt { IF hb[0] = hMd AND NOT hb[1]:PRESSED { SET hb[1]:PRESSED TO TRUE. holdSet(hMd). } }
            }
        }
        IF aug OR dOn OR swN > 0 OR grp <> "" OR latched OR ldOn { SET hWorkT TO tn. }     // The arm works: the hold is stiff (LAR_HOLD_AUG_DB / _ACC) and stays so a few s after
        SET LAR_HOLD_WORK TO tn - hWorkT < LAR_HOLD_WORK_HANG.
        holdTick(tn, dt).
        IF dOn AND NOT ADDONS:KALS:ARMALIVE {   // the C# drive let go (its watchdog, a scene change): the kOS path from here
            SET dOn TO FALSE. SET LAR_DRV TO FALSE. SET LAR_QSTEP TO 1.
            LOCAL lgWhy IS ADDONS:KALS:ARMSTATE[5].
            armPr("arm: DRIVE C# LET GO (" + lgWhy + "): DRIVE kOS from here").
            // An EVA / vessel switch only (NOT a vessel loss: the undock split stays on the kOS path); an older DLL's text has "not the active one" too
            SET dBack TO ARM_DLL AND (lgWhy:CONTAINS("NOT THE ACTIVE VESSEL") OR lgWhy:CONTAINS("not the active one")). SET dBackT TO tn. SET dBackWhy TO "".
            IF dBack { armPr("arm: DRIVE C# will bind again when the orbiter is the active vessel and the arm is idle"). }
        }
        IF dBack AND NOT dOn AND tn - dBackT >= dBackDt AND KUNIVERSE:ACTIVEVESSEL = SHIP AND NOT (aug OR swN > 0 OR grp <> "" OR drv OR auto OR latched OR ldOn) {
            SET dBackT TO tn.                // from the joints' own target fields (the C# start seeds there: no jump); the dampers set again
            LOCAL pl2 IS LIST(). FOR j IN jts { pl2:ADD(j[0]). }
            LOCAL bWhy IS ADDONS:KALS:ARMDRIVE(pl2).
            IF bWhy = "" {
                SET dOn TO TRUE. SET dBack TO FALSE. SET LAR_DRV TO TRUE. SET LAR_QSTEP TO LAR_QSTEP_DRV.
                armPr("arm: DRIVE C# BACK (the orbiter is the active vessel again; every physics tick, unrounded)").
                armDamp("BACK").
            } ELSE IF bWhy <> dBackWhy {     // log a refusal once per reason
                SET dBackWhy TO bWhy. armPr("arm: DRIVE C# not back yet (" + bWhy + ")").
            }
        }
        SET hl:TEXT TO holdText().
        // the joint select: a newly pressed button picks its joint and releases the others; the selected joint's
        // button released (pressed again) leaves no joint. A pick during a drive locks the driven joint first.
        LOCAL pick IS sel.
        IF sel >= 0 AND NOT rb[sel]:PRESSED { SET pick TO -1. }
        FROM { LOCAL i IS 0. } UNTIL i >= rb:LENGTH STEP { SET i TO i + 1. } DO {
            IF i <> sel AND rb[i]:PRESSED { SET pick TO i. }
        }
        IF pick <> sel {
            IF drv {
                armLk(jts[sel][1]).
                SET drv TO FALSE.
                armPr(jts[sel][2] + ": stopped at " + ROUND(cmd, 2) + " (joint select)" + (CHOOSE ", STALLED" IF stall ELSE "")).
            }
            FROM { LOCAL i IS 0. } UNTIL i >= rb:LENGTH STEP { SET i TO i + 1. } DO {
                IF i <> pick AND rb[i]:PRESSED { SET rb[i]:PRESSED TO FALSE. }
            }
            SET sel TO pick.
        }
        LOCAL j IS jts[MAX(sel, 0)].
        LOCAL md IS j[1].
        LOCAL thcV IS armThc().                      // The THC, V(starboard, top, fore)
        LOCAL fwd IS MAX(0, MIN(1, thcV:Z)).         // THC FORWARD, 0 .. 1: the COARSE boost in SINGLE (VERNIER unchanged)
        LOCAL inp IS thcV:Y.
        LOCAL rSent IS FALSE.                        // The C# drive's rates sent this pass (the slews' and the stick drive's go in ONE ARMRATE call: it takes every joint's rate)
        SET swRl TO dZero:COPY.
        IF swN > 0 { swTick(tn, dt, fwd, inp). }      // the typed slews (the law, per joint); the picked joint's THC Y ends its own slew first
        LOCAL rate IS (CHOOSE ARM_RATE_V IF bv:PRESSED ELSE (CHOOSE ARM_RATE_C_WR IF j[2] = "WRIST ROLL"
            ELSE ARM_RATE_C + fwd * (ARM_RATE_BOOST - ARM_RATE_C))) * ldS.
        LOCAL want IS ABS(inp) > ARM_DB AND NOT armRcsBad() AND sel >= 0 AND grp = "" AND NOT latched AND armBad = "".
        IF want AND NOT drv {                    // the autostrut first: no drive while an arm part has it on
            IF asWhy = "" { SET asBlock TO armAsOff(). }
            ELSE IF bh:PRESSED { SET asBlock TO "". }
            ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
            IF asBlock <> "" { SET want TO FALSE. }
        }
        IF want AND NOT drv {                    // the drive starts: unlocked, the reference taken
            IF jSave[sel][0] < 0 { SET jSave[sel] TO LIST(CHOOSE 1 IF md:GETFIELD("locked") ELSE 0, md:GETFIELD("traverse rate")). }
            md:SETFIELD("locked", FALSE).
            SET tg0 TO CHOOSE armSt()[1][sel] IF dOn ELSE md:GETFIELD("target angle"). SET cmd TO tg0.
            SET rS0 TO armRel(j[3], j[0]). SET rC0 TO armRel(j[0], j[4]).
            SET stall TO FALSE. SET drv TO TRUE. SET last TO 0. SET still TO 0. SET sT1 TO LIST(-1, FALSE).
            armPr(j[2] + ": drive from " + ROUND(tg0, 2)).
        }
        IF drv {
            LOCAL mv IS MAX(armTurn(rS0, armRel(j[3], j[0])), armTurn(rC0, armRel(j[0], j[4]))).
            IF want {
                SET tEnd TO -1.
                LOCAL dir IS CHOOSE 1 IF inp > 0 ELSE -1.
                // a STALL is the joint trailing its command past the stall margin + its rate's own lag (larStallAl) for
                // LAR_STALL_T, not a touch of it (a flown run logged 100+ STALL lines at 2 deg/s, the traverse rate = the
                // command's, so the whole-degree steps could never be caught up); stalled, the command waits for the joint
                LOCAL cNow IS CHOOSE armSt()[1][sel] IF dOn ELSE cmd.   // the C# drive's command now
                SET sT1 TO larStallTick(sT1, ABS(cNow - tg0) - mv > larStallAl(rate, ARM_STALL), tn).
                IF sT1[1] AND NOT stall { armPr(j[2] + ": STALL at " + ROUND(cmd, 2) + " (moved " + ROUND(mv, 2) + " deg)"). }
                SET stall TO sT1[1].
                IF dOn {                         // the C# drive: the rate, smoothed (no step at the start or the stop)
                    LOCAL rl IS swRl:COPY. SET rl[sel] TO CHOOSE 0 IF stall ELSE dir * rate.
                    SET cmd TO armRates(rl, ARM_TAU)[sel]. SET rSent TO TRUE.
                } ELSE IF NOT stall {
                    md:SETFIELD("traverse rate", rate).   // the kOS path unchanged (a faster traverse turns each step into a rate step)
                    SET cmd TO cmd + dir * rate * dt.
                    md:SETFIELD("target angle", cmd).
                }
            } ELSE {                             // the drive ended: locked once the joint has stopped
                IF dOn { SET cmd TO armRates(swRl, ARM_TAU)[sel]. SET rSent TO TRUE. }   // the C# drive slows the joint to rest, smoothly (the slews' rates ride along)
                IF tEnd < 0 { SET tEnd TO tn. }
                IF ABS(mv - last) < ARM_STILL { SET still TO still + 1. } ELSE { SET still TO 0. }
                IF still >= 5 OR tn - tEnd > ARM_STILL_T {
                    armLk(md).
                    SET drv TO FALSE.
                    armPr(j[2] + ": stopped at " + ROUND(cmd, 2) + " (moved " + ROUND(mv, 2) + " deg)" + (CHOOSE ", STALLED" IF stall ELSE "")).
                }
            }
            SET last TO mv.
        }

        IF dOn AND swN > 0 AND NOT rSent { armRates(swRl, ARM_TAU). }     // No stick drive this pass: the slews' rates (0 for a stopping one) go alone

        // ---- the frame: ORB LD / PL only LOADED (else back to ORB UNL / END EFF); a change while MAN AUG moves locks
        // the joints (the next input takes the references again in the new frame)
        IF pFrm:INDEX < 0 { SET pFrm:INDEX TO frmI. }
        IF frmLd(pFrm:INDEX) AND NOT (ldOn AND NOT latched AND porOk) {
            LOCAL fb IS pFrm:INDEX - 2.
            SET frmSt TO LAR_FRAMES[pFrm:INDEX] + (CHOOSE " LEFT: NOT LOADED NOW" IF pFrm:INDEX = frmI
                ELSE " REFUSED: NO PAYLOAD (LOADED ONLY)") + ": " + LAR_FRAMES[fb].
            SET frmStT TO tn.
            armPr("FRAME: " + frmSt).
            SET pFrm:INDEX TO fb.
        }
        IF pFrm:INDEX <> frmI {
            IF augMv { augLock(). armPr("MAN AUG: the frame changed to " + LAR_FRAMES[pFrm:INDEX] + ": the joints locked"). }
            ELSE { armPr("FRAME: " + LAR_FRAMES[pFrm:INDEX]). }
            SET frmI TO pFrm:INDEX.
        }
        // ---- MAN AUG: engage / leave
        IF bAug:PRESSED AND NOT aug {
            LOCAL why IS "".
            IF armRcsBad() { SET why TO "RCS ON (THE THC WOULD TRANSLATE THE ORBITER)". }
            ELSE IF augFr:LENGTH <> 6 OR augEl < 0 { SET why TO "NOT A 6-JOINT RMS ARM (" + jts:LENGTH + " JOINTS)". }
            ELSE IF jts[augEl][1]:GETFIELD("target angle") <= LAR_AUG_ELBOW { SET why TO "ELBOW AT OR BELOW " + LAR_AUG_ELBOW + ": UNSTOW FIRST (SINGLE)". }
            ELSE IF drv { SET why TO "A SINGLE DRIVE IS ON". }
            ELSE IF auto { SET why TO "AUTO IS ON". }
            ELSE IF opr { SET why TO "OPR CMD IS ON". }
            ELSE IF grp <> "" { SET why TO (CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE") + " IS ON". }
            ELSE IF latched { SET why TO "LATCHED: THE PAYLOAD IS STILL HELD IN THE BAY". }
            ELSE IF armBad <> "" { SET why TO armWhy(). }
            IF why <> "" { SET bAug:PRESSED TO FALSE. SET augSt TO "MAN AUG REFUSED: " + why. armPr(augSt). }
            ELSE {
                IF sel >= 0 { SET rb[sel]:PRESSED TO FALSE. SET sel TO -1. }
                FOR i IN augFr {
                    IF jSave[i][0] < 0 { SET jSave[i] TO LIST(CHOOSE 1 IF jts[i][1]:GETFIELD("locked") ELSE 0, jts[i][1]:GETFIELD("traverse rate")). }
                }
                SET ipu0 TO CONFIG:IPU. SET CONFIG:IPU TO MAX(ipu0, ARM_AUG_IPU).
                SET aug TO TRUE. SET augSt TO "". SET augHalt TO "".
                armPr("MAN AUG on (" + LAR_FRAMES[frmI] + (CHOOSE " at the payload's POR" IF frmLd(frmI) ELSE " at the node")
                    + (CHOOSE ", THC ROT" IF bRot:PRESSED ELSE "") + ")").
                augRhc(bStk:PRESSED).
            }
        }
        IF aug AND (NOT bAug:PRESSED OR sel >= 0) { augOff(CHOOSE "a joint picked" IF sel >= 0 ELSE "MAN AUG released"). }
        IF aug AND bStk:PRESSED <> rhcOn { augRhc(bStk:PRESSED). }
        IF aug {
            LOCAL vern IS (CHOOSE LAR_VERNIER IF bv:PRESSED ELSE 1) * ldS.     // LOADED: every rate x the load's share
            LOCAL arate IS LAR_V_COARSE * vern.
            LOCAL wrate IS (CHOOSE LAR_W_COARSE IF bv:PRESSED ELSE LAR_W_AUG) * ldS.     // VERN = the old COARSE (3), COARSE 8 (LAR_W_AUG); the translation keeps COARSE x VERNIER
            LOCAL eeF IS frmI = 1 OR frmI = 3.       // END EFF, PL: the view along the boresight / into the payload
            LOCAL frm IS LAR_FRAMES[frmI].
            LOCAL thc IS armThc().
            LOCAL vcV IS V(0, 0, 0).
            LOCAL rhc IS V(0, 0, 0).                 // V(pitch, yaw, roll)
            LOCAL rhcTag IS "".
            IF bRot:PRESSED { SET rhc TO larThcRot(thc). SET rhcTag TO "  THC ROT". }
            ELSE {
                SET vcV TO larThcVel(thc, arate, ARM_DB).
                IF rhcOn {
                    IF rhcWhy <> "" { SET rhcTag TO "  STICK INHIBITED: " + rhcWhy. }
                    ELSE IF SAS { SET rhcTag TO "  STICK INHIBITED: SAS ON". }
                    ELSE IF hOk {                // under the hold the gimbal shows its command: the pilot's own stick
                        LOCAL fp IS ADDONS:KALS:FBWPILOT().
                        SET rhc TO V(fp[0], fp[2], fp[1]).
                        SET rhcTag TO "  STICK " + ROUND(rhc:X, 2) + " " + ROUND(rhc:Y, 2) + " " + ROUND(rhc:Z, 2).
                    } ELSE {
                        LOCAL gm IS omsL[0]:GIMBAL.
                        SET rhc TO V(gm:PITCHANGLE, gm:YAWANGLE, gm:ROLLANGLE).
                        SET rhcTag TO "  STICK " + ROUND(rhc:X, 2) + " " + ROUND(rhc:Y, 2) + " " + ROUND(rhc:Z, 2).
                    }
                }
            }
            LOCAL wcV IS larRhcRate(rhc, wrate, ARM_DB).
            LOCAL awant IS (vcV:MAG > 0 OR wcV:MAG > 0) AND NOT armRcsBad() AND NOT latched AND armBad = "".
            IF NOT awant { SET augHalt TO "". }      // a SOFT STOP holds until the THC is released
            IF augHalt <> "" { SET awant TO FALSE. }
            IF awant AND NOT augMv {                 // the motion starts: struts off, joints unlocked, the references taken
                IF asWhy = "" { SET asBlock TO armAsOff(). }
                ELSE IF bh:PRESSED { SET asBlock TO "". }
                ELSE { SET asBlock TO "AUTOSTRUT: SET IT OFF BY HAND, THEN STRUTS OFF BY HAND". }
                IF asBlock <> "" { SET awant TO FALSE. }
                ELSE {
                    LOCAL pz0 IS porNow(frmLd(frmI)).   // the reference on the POR (the node unless ORB LD / PL)
                    SET pRef TO pz0[1].
                    SET fRef TO pz0[2]. SET tRef TO pz0[3].
                    SET askW TO V(0, 0, 0). SET pWin TO pz0[0]. SET tWin TO tn. SET augFirst TO TRUE.
                    SET askA TO V(0, 0, 0). SET fWn TO fRef. SET tWn TO tRef. SET wUse TO FALSE.
                    SET augTg0 TO LIST(). SET augR0 TO LIST().
                    FOR i IN augFr {
                        jts[i][1]:SETFIELD("locked", FALSE).
                        augTg0:ADD(jts[i][1]:GETFIELD("target angle")).
                        augR0:ADD(LIST(armRel(jts[i][3], jts[i][0]), armRel(jts[i][0], jts[i][4]))).
                    }
                    IF dOn { LOCAL th0 IS armSt()[1]. FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET augTg0[c] TO th0[augFr[c]]. } }
                    SET augCm TO augTg0:COPY. SET augCmM TO augTg0:COPY.
                    SET augMv TO TRUE. SET augStl TO LIST(-1, FALSE).
                    armPr("MAN AUG " + frm + ": move" + augWords(vcV, wcV, eeF) + " at " + arate + " m/s, " + wrate + " deg/s"
                        + rhcTag).
                }
            }
            // the operator's command smoothed (two stages of ARM_TAU): no step in rate at a start or a stop, and the arm
            // coasts to rest after the release (the reference and the solve follow the smoothed command, so they agree)
            IF NOT augMv { SET augSv TO LIST(V(0, 0, 0), V(0, 0, 0)). SET augSw TO LIST(V(0, 0, 0), V(0, 0, 0)). }
            // (the kOS path unsmoothed: its whole-degree steps are jerky anyway and a coast only adds steps)
            SET augSv TO larSmooth(augSv, CHOOSE vcV IF awant ELSE V(0, 0, 0), dt, CHOOSE ARM_TAU IF dOn ELSE 0).
            SET augSw TO larSmooth(augSw, CHOOSE wcV IF awant ELSE V(0, 0, 0), dt, CHOOSE ARM_TAU IF dOn ELSE 0).
            LOCAL vS IS augSv[1]. LOCAL wS IS augSw[1].
            LOCAL amove IS augMv AND (awant OR vS:MAG > 1e-4 OR wS:MAG > 1e-4).
            IF amove {
                SET tEndA TO -1.
                LOCAL fr IS root:FACING.
                LOCAL gm IS larGeom(jts, ee).
                LOCAL pNow IS armIn(gm[0] - root:POSITION, fr).
                LOCAL gs2 IS LIST().
                FOR gg IN gm[1] { gs2:ADD(LIST(armIn(gg[0] - root:POSITION, fr), armIn(gg[1], fr), gg[2])). }
                LOCAL pz IS porNow(frmLd(frmI)).
                LOCAL sf IS SHIP:FACING.             // the frame's axes (END EFF / PL: the view's; ORB UNL / ORB LD: the orbiter's)
                LOCAL ax IS CHOOSE larCmdAxes(TRUE, pz[4][0], pz[4][1], pz[4][2]) IF eeF
                    ELSE larCmdAxes(FALSE, armIn(sf:STARVECTOR, fr), armIn(sf:TOPVECTOR, fr), armIn(sf:FOREVECTOR, fr)).
                LOCAL vcR IS larCmdOut(vS, ax).
                LOCAL wcR IS larCmdOut(wS, ax).
                LOCAL fNow IS pz[2]. LOCAL tNow IS pz[3].
                LOCAL pPor IS pNow + (pz[1] - pz[0]).   // the POR: the node in ORB UNL / END EFF
                // the reference is where the POR and the frame should be now; it moves on after the solve
                LOCAL rf IS larAugRef(pRef, fRef, tRef, pPor, fNow, tNow, wcR:MAG > 0).
                SET pRef TO rf[0]. SET fRef TO rf[1]. SET tRef TO rf[2].
                LOCAL eP IS rf[3]. LOCAL eW IS rf[4].
                LOCAL jm IS larJacob(pNow, gs2, augHeld).
                LOCAL wm IS larManip(jm).
                LOCAL res IS larAugSoft(jm, augNm, augCm, vcR, eP, eW, wcR, pPor - pNow, larLam2(wm, LAR_W0, LAR_LAM0), LAR_QD_MAX * ldS).   // A joint at its soft stop is held ALONE
                LOCAL softTx IS "".                  // the held joints and what the rest still does: said loudly, on the status line and once in the log
                IF res[3] <> "" {
                    FOR hj IN res[2] { SET softTx TO softTx + " " + augNm[hj]. }
                    SET softTx TO "  SOFT STOP" + softTx + " (" + res[3] + ")".
                }
                IF softTx <> augSoftTx {
                    SET augSoftTx TO softTx.
                    armPr("MAN AUG:" + (CHOOSE softTx IF softTx <> "" ELSE " soft stop clear")).
                }
                LOCAL rt IS res[0].
                LOCAL tgs IS augCm.                  // the running commands: the field holds them rounded to LAR_QSTEP
                LOCAL stl IS "". LOCAL sNow IS armNow().
                FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH OR stl <> "" STEP { SET c TO c + 1. } DO {
                    IF armOver(c, tgs[c], augTg0[c], augR0[c], rt[c], sNow) { SET stl TO jts[augFr[c]][2]. }
                }
                SET augStl TO larStallTick(augStl, stl <> "", tn).   // past the allowance for LAR_STALL_T, not a touch
                IF NOT augStl[1] { SET stl TO "". }
                IF stl <> "" {
                    augOff("STALL " + stl).
                    SET augSt TO "MAN AUG OFF: STALL " + stl.
                } ELSE IF eW:MAG / LAR_D2R > (CHOOSE ARM_AUG_ATT_LD IF (ldOn AND NOT ARM_LOCK_LOADED) ELSE ARM_AUG_ATT) + larQRes(jm)[1] {
                    augOff("MODEL: the attitude drifted " + ROUND(eW:MAG / LAR_D2R, 1) + " deg").
                    SET augSt TO "MAN AUG OFF: MODEL (ATTITUDE)".
                } ELSE {
                    LOCAL lin IS V(0, 0, 0).
                    LOCAL ang IS V(0, 0, 0).
                    LOCAL dTh IS LIST().                 // each joint's commanded change this tick (deg)
                    IF dOn AND sNow:LENGTH > 0 {         // the C# drive (and not just let go): the rates handed over, its commands read back
                        LOCAL rl IS dZero:COPY.
                        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO { SET rl[augFr[c]] TO rt[c]. }
                        LOCAL th IS armRates(rl, LAR_TAU_J).
                        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {   // asked: between measurements
                            dTh:ADD(sNow[1][augFr[c]] - augCmM[c]). SET augCmM[c] TO sNow[1][augFr[c]]. SET augCm[c] TO th[augFr[c]].
                        }
                    } ELSE {
                        FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {
                            LOCAL md2 IS jts[augFr[c]][1].
                            md2:SETFIELD("traverse rate", ABS(rt[c]) + ARM_AUG_MARGIN).
                            SET augCm[c] TO augCm[c] + rt[c] * dt.
                            md2:SETFIELD("target angle", augCm[c]).
                            dTh:ADD(rt[c] * dt).
                        }
                    }
                    FROM { LOCAL c IS 0. } UNTIL c >= augFr:LENGTH STEP { SET c TO c + 1. } DO {
                        SET lin TO lin + V(jm[0][c], jm[1][c], jm[2][c]) * (dTh[c] * LAR_D2R).
                        SET ang TO ang + V(jm[3][c], jm[4][c], jm[5][c]) * (dTh[c] * LAR_D2R).
                    }
                    SET askW TO askW + lin.
                    SET askA TO askA + ang.
                    IF wcV:MAG > 0 AND NOT bRot:PRESSED { SET wUse TO TRUE. }
                    LOCAL nx IS larAugStep(pRef, fRef, tRef, vcR, wcR, dt).
                    SET pRef TO nx[0]. SET fRef TO nx[1]. SET tRef TO nx[2].
                    SET augSt TO "MAN AUG " + frm + augWords(vcV, wcV, eeF) + " " + larFtS(arate, 2) + " M/S " + ROUND(wrate, 2) + " DEG/S"
                        + (CHOOSE "  RATE LIMITED" IF res[1] < 1 ELSE "") + softTx + (CHOOSE "  SINGULAR: " + larSingWhy(augNm, augCm) IF wm < LAR_W0 ELSE "") + rhcTag.
                    LOCAL aq IS larQuant(jm).          // what the whole-degree steps can hide: the window waits until the ask clears it
                    IF larModelDue(tn - tWin, ARM_AUG_WIN, askW, askA, aq) {
                        LOCAL gotA IS larAttErr(fWn, tWn, fNow, tNow).
                        IF NOT augFirst AND larModelBad(askW, pNow - pWin, aq[0]) {
                            augOff("MODEL: asked " + ROUND(askW:MAG, 3) + " m, moved " + ROUND((pNow - pWin):MAG, 3) + " m, missed by "
                                + ROUND((pNow - pWin - askW):MAG, 3) + " m").
                            SET augSt TO "MAN AUG OFF: MODEL".
                        } ELSE IF NOT augFirst AND larModelBadW(askA, gotA, aq[1]) {
                            augOff("MODEL: asked a turn of " + ROUND(askA:MAG / LAR_D2R, 2) + " deg, turned " + ROUND(gotA:MAG / LAR_D2R, 2)
                                + " deg, missed by " + ROUND((gotA - askA):MAG / LAR_D2R, 2) + " deg").
                            SET augSt TO "MAN AUG OFF: MODEL (TURN)".
                        }
                        IF wUse {                    // the probe: does the stick still turn the orbiter with the wheels at 0?
                            armPr("MAN AUG: stick " + ROUND(rhc:X, 2) + " / " + ROUND(rhc:Y, 2) + " / " + ROUND(rhc:Z, 2)
                                + " (pitch / yaw / roll), the end effector turned " + ROUND(gotA:MAG / LAR_D2R, 2)
                                + " deg in the window, the orbiter turns " + ROUND(SHIP:ANGULARVEL:MAG / LAR_D2R, 3) + " deg/s").
                        }
                        SET askW TO V(0, 0, 0). SET pWin TO pNow. SET tWin TO tn. SET augFirst TO FALSE.
                        SET askA TO V(0, 0, 0). SET fWn TO fNow. SET tWn TO tNow. SET wUse TO FALSE.
                    }
                }
            }
            IF aug AND augMv AND NOT amove {         // the THC released (and the coast over): the joints lock in detent
                IF dOn { armRates(dZero, LAR_TAU_J). }
                IF tEndA < 0 { SET tEndA TO tn. }
                IF tn - tEndA > ARM_AUG_LOCK {
                    augLock().
                    armPr("MAN AUG: detent, " + (CHOOSE "the joints held on their drive" IF ARM_AUG_NOLOCK ELSE "the joints locked")).
                }
            }
            IF aug AND NOT augMv {
                SET augSt TO "MAN AUG " + frm + " " + (CHOOSE augHalt IF augHalt <> "" ELSE "READY") + rhcTag
                    + (CHOOSE "  " + asBlock IF asBlock <> "" ELSE "").
            }
        }
        // ---- OPR CMD: LOAD keys the pose now; OPR CMD pressed flies to the keyed pose, released halts it; the POSE line
        LOCAL pzO IS porNow(frmLd(frmI)).
        LOCAL xyzN IS larPoseXyz(pzO[1], orgR, pzO[5]).
        LOCAL pyrN IS larEulerOf(pzO[4][2], pzO[4][1], pzO[5]).
        IF oprLdReq {
            SET oprLdReq TO FALSE.
            SET opFd[0]:TEXT TO "" + ROUND(xyzN:X, 2). SET opFd[1]:TEXT TO "" + ROUND(xyzN:Y, 2).
            SET opFd[2]:TEXT TO "" + ROUND(xyzN:Z, 2).
            SET opFd[3]:TEXT TO "" + ROUND(pyrN:X, 1). SET opFd[4]:TEXT TO "" + ROUND(pyrN:Y, 1). SET opFd[5]:TEXT TO "" + ROUND(pyrN:Z, 1).
        }
        IF bOpr:PRESSED AND NOT opr { oprStart(). }
        IF opr AND (NOT bOpr:PRESSED OR sel >= 0) {
            oprOff(CHOOSE "a joint picked" IF sel >= 0 ELSE "released", CHOOSE "OPR CMD OFF: A JOINT PICKED" IF sel >= 0 ELSE "OPR CMD OFF: HALTED").
        }
        IF opr { oprTick(tn, dt). }
        SET pl0:TEXT TO (CHOOSE "POR " IF frmLd(frmI) ELSE "NODE") + "  X " + grpSg(xyzN:X, 2) + "  Y " + grpSg(xyzN:Y, 2)
            + "  Z " + grpSg(xyzN:Z, 2) + " M   P " + grpSg(pyrN:X, 1) + "  Y " + grpSg(pyrN:Y, 1) + "  R " + grpSg(pyrN:Z, 1) + " DEG".
        SET pubPor TO LIST(xyzN, pyrN).
        // ---- AUTO: a newly pressed AUTO button starts its legs and releases the others; the running one released halts
        LOCAL apick IS asel.
        IF asel >= 0 AND NOT abt[asel][0]:PRESSED { SET apick TO -1. }
        FROM { LOCAL i IS 0. } UNTIL i >= abt:LENGTH STEP { SET i TO i + 1. } DO {
            IF i <> asel AND abt[i][0]:PRESSED { SET apick TO i. }
        }
        IF apick <> asel {
            IF auto { autoOff(CHOOSE "released" IF apick < 0 ELSE "another AUTO picked", "AUTO OFF: HALTED AT " + autoTag). }
            FROM { LOCAL i IS 0. } UNTIL i >= abt:LENGTH STEP { SET i TO i + 1. } DO {
                IF i <> apick AND abt[i][0]:PRESSED { SET abt[i][0]:PRESSED TO FALSE. }
            }
            SET asel TO apick.
            IF asel >= 0 { autoStart(asel). }
        }
        IF auto AND sel >= 0 { autoOff("a joint picked", "AUTO OFF: A JOINT PICKED"). }
        IF auto AND dOn {
            // the C# drive flies the leg (ARMGOTO); a joint trailing its command past larStallAl for LAR_STALL_T is a
            // STALL (the profile is not held: the leg stops); arrival = the profile done + the joints still
            LOCAL st IS armSt().
            LOCAL th IS st[1]. LOCAL rt IS st[2].
            LOCAL trn IS LIST(). LOCAL mvSum IS 0.
            FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
                trn:ADD(CHOOSE autoTurned(i) IF lMv:CONTAINS(i) ELSE 0).
                SET mvSum TO mvSum + trn[i].
            }
            LOCAL behind IS -1.
            FOR i IN lMv { IF ABS(th[i] - lgA[i]) - trn[i] > larStallAl(rt[i], ARM_STALL) { SET behind TO i. } }
            SET lStT TO larStallTick(lStT, behind >= 0, tn).
            IF NOT lSet {
                SET lS TO MIN(1, lS + dt / lT).
                IF st[3] { SET lS TO 1. SET lSet TO TRUE. SET lTset TO tn. SET lStill TO 0. }
            } ELSE IF ABS(mvSum - lLast) < ARM_STILL { SET lStill TO lStill + 1. } ELSE { SET lStill TO 0. }
            IF lStT[1] {
                LOCAL hint IS CHOOSE " (THE ELBOW'S STOP?)" IF behind = augEl AND th[behind] < -176 ELSE "".
                autoOff("STALL " + anm[behind] + " at " + ROUND(th[behind], 2) + " (moved " + ROUND(trn[behind], 2)
                    + " deg of " + ROUND(ABS(lgB[behind] - lgA[behind]), 2) + ")" + hint, "AUTO OFF: STALL " + anm[behind] + hint).
            } ELSE IF lSet AND behind < 0 AND (lStill >= 5 OR tn - lTset > ARM_STILL_T) { autoArrive(). }
            SET lLast TO mvSum.
            IF auto { SET autoSt TO "AUTO " + autoTag + " " + ROUND(100 * lS) + " %" + (CHOOSE "  BEHIND: " + anm[behind] IF behind >= 0 ELSE ""). }
        } ELSE IF auto {
            // the ramp moves on unless a joint runs ARM_STALL behind its target (held; STALL after ARM_AUTO_STALL_T s)
            LOCAL tgs IS autoTgs().
            LOCAL trn IS LIST(). LOCAL mvSum IS 0.
            FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
                trn:ADD(CHOOSE autoTurned(i) IF lMv:CONTAINS(i) ELSE 0).
                SET mvSum TO mvSum + trn[i].
            }
            LOCAL behind IS larLegBehind(lMv, tgs, lgA, trn, ARM_STALL).
            IF NOT lSet {
                IF behind >= 0 {
                    IF lStall < 0 { SET lStall TO tn. armPr("AUTO: " + anm[behind] + " behind its target at " + ROUND(tgs[behind], 2)
                        + " (moved " + ROUND(trn[behind], 2) + " deg): held"). }
                    IF tn - lStall > ARM_AUTO_STALL_T {
                        LOCAL hint IS CHOOSE " (THE ELBOW'S STOP?)" IF behind = augEl AND tgs[behind] < -176 ELSE "".
                        autoOff("STALL " + anm[behind] + " at " + ROUND(tgs[behind], 2) + " (moved " + ROUND(trn[behind], 2)
                            + " deg of " + ROUND(ABS(lgB[behind] - lgA[behind]), 2) + ")" + hint, "AUTO OFF: STALL " + anm[behind] + hint).
                    }
                } ELSE {
                    SET lStall TO -1.
                    SET lS TO MIN(1, lS + dt / lT).
                    LOCAL nx IS larMoveAt(lgA, lgB, lS).
                    FOR i IN lMv { jts[i][1]:SETFIELD("target angle", nx[i]). }
                    IF lS >= 1 { SET lSet TO TRUE. SET lTset TO tn. SET lStill TO 0. }
                }
            } ELSE {                             // at the goal: the waypoint once the joints have stopped
                IF ABS(mvSum - lLast) < ARM_STILL { SET lStill TO lStill + 1. } ELSE { SET lStill TO 0. }
                IF behind >= 0 AND tn - lTset > ARM_AUTO_STALL_T {
                    autoOff("STALL " + anm[behind] + " short of " + aLegs[li][0], "AUTO OFF: STALL " + anm[behind]).
                } ELSE IF behind < 0 AND (lStill >= 5 OR tn - lTset > ARM_STILL_T) { autoArrive(). }
            }
            SET lLast TO mvSum.
            IF auto { SET autoSt TO "AUTO " + autoTag + " " + ROUND(100 * lS) + " %" + (CHOOSE "  HELD: " + anm[behind] IF behind >= 0 ELSE ""). }
        }
        // ---- GRAPPLE: the dock watched (LOADED / LATCHED), the page, CAPTURE and RELEASE
        LOCAL eSt IS ee:STATE.
        IF NOT ldForce AND eSt:STARTSWITH("Docked") <> ldOn { grpDock(eSt:STARTSWITH("Docked"), eSt). }
        IF ldOn AND NOT ldForce AND tn - ldT > ARM_LOAD_T { grpWeigh(). }
        LOCAL page IS bGrp:PRESSED OR grp <> "".
        IF page AND grp = "" AND NOT ldOn AND tn - fxT > ARM_GRP_SEEK_T { grpFind(). }
        LOCAL rel IS LEXICON().
        IF page AND fxOk AND NOT ldOn {
            SET rel TO grpRel().
            IF clR < 0 OR tn - clT >= ARM_GRP_CL_T {
                IF clR >= 0 { SET clV TO (clR - rel["RANGE"]) / (tn - clT). }
                SET clR TO rel["RANGE"]. SET clT TO tn.
            }
        }
        IF (bCap:PRESSED OR bRel:PRESSED) AND grp = "" {
            LOCAL isCap IS bCap:PRESSED.
            IF isCap AND bRel:PRESSED { SET bRel:PRESSED TO FALSE. }
            IF sel >= 0 { SET rb[sel]:PRESSED TO FALSE. SET sel TO -1. }   // CAPTURE / RELEASE leave SINGLE's joint select
            LOCAL why IS "".
            IF isCap AND NOT ldOn AND rel:LENGTH = 0 {   // GRAPPLE is dim on the PDRS page, so the fixture is looked for here too
                grpFind().
                IF fxOk { SET rel TO grpRel(). }
            }
            IF isCap {
                IF ldOn { SET why TO "THE LEE IS DOCKED". }
                ELSE IF NOT fxOk OR rel:LENGTH = 0 { SET why TO "NO FIXTURE (TARGET ONE OR FLY WITHIN "
                    + ROUND(LAR_GRP_SEEK) + " M)". }
                ELSE { SET why TO larCapOk(rel). }
            } ELSE IF NOT ldOn { SET why TO "THE LEE IS NOT DOCKED". }
            IF why = "" { SET why TO grpWhy(). }
            IF why <> "" {
                SET bCap:PRESSED TO FALSE. SET bRel:PRESSED TO FALSE.
                SET grpSt TO (CHOOSE "CAPTURE" IF isCap ELSE "RELEASE") + " REFUSED: " + why. SET grpStT TO tn.
                armPr(grpSt).
            } ELSE {
                IF aug { augOff(CHOOSE "CAPTURE" IF isCap ELSE "RELEASE"). }
                SET ipuG TO CONFIG:IPU. SET CONFIG:IPU TO MAX(ipuG, ARM_AUG_IPU).
                IF isCap {
                    LOCAL nd IS grpNode(). LOCAL fxv IS grpFix().
                    SET lnCr TO larCapRoll(nd[2], fxv[1], fxv[2]).
                    SET lnR TO rel["AX"]. SET lnAcq TO -1. SET lnEndT TO -1. SET lnEP TO 0.
                    grpGo().
                    SET grp TO "CAP".
                    armPr("CAPTURE: " + ROUND(rel["AX"], 3) + " m out along the fixture's axis, " + ROUND(rel["LAT"], 3)
                        + " m off it, the boresight " + ROUND(rel["ANG"], 2) + " deg off; along the axis at " + LAR_CAP_V + " m/s").
                } ELSE {
                    SET grp TO "REL". SET lnUnd TO tn. SET lnEv TO FALSE.
                    LOCAL mpEv IS larMakePrimary(ee).   // The LEE the primary docking node first, else the undock fails
                    IF mpEv <> "" { WAIT 0. }
                    armPr("RELEASE: " + (CHOOSE "'" + mpEv + "', then " IF mpEv <> "" ELSE "") + "undock (" + eSt + ")").
                    ee:UNDOCK().
                }
            }
        }
        IF (grp = "CAP" AND bRel:PRESSED) OR (grp = "REL" AND bCap:PRESSED) {   // not queued behind the one flying
            SET bRel:PRESSED TO grp = "REL". SET bCap:PRESSED TO grp = "CAP".
            armPr((CHOOSE "RELEASE" IF grp = "CAP" ELSE "CAPTURE") + " REFUSED: " + (CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE")
                + " IS ON (release its button first)").
        }
        IF grp = "CAP" AND NOT bCap:PRESSED { grpOff("released", "CAPTURE OFF: RELEASED"). }
        IF grp = "REL" AND NOT bRel:PRESSED { grpOff("released", "RELEASE OFF: RELEASED"). }
        IF grp <> "" AND sel >= 0 { grpOff("a joint picked", "OFF: A JOINT PICKED"). }
        IF grp = "CAP" {                         // CAPTURE: the line along the fixture's axis; on Acquire the joints lock
            IF eSt:STARTSWITH("Acquire") AND lnAcq = -1 {
                grpLock(). SET lnAcq TO tn.
                armPr("CAPTURE: ACQUIRE (" + eSt + ") " + ROUND(rel["AX"], 3) + " m out, " + ROUND(rel["LAT"], 3) + " m off the axis, "
                    + ROUND(rel["ANG"], 2) + " deg: the joints locked, the magnets close the gap").
            }
            IF lnAcq >= 0 {                      // waiting for the dock
                IF NOT eSt:STARTSWITH("Acquire") {
                    SET lnAcq TO -1. grpGo().
                    armPr("CAPTURE: the acquire lost (" + eSt + "): the line flies on").
                } ELSE IF tn - lnAcq > LAR_CAP_ACQ_T {
                    SET lnAcq TO -2. grpGo().
                    armPr("CAPTURE: not docked " + LAR_CAP_ACQ_T + " s after the acquire (" + ROUND(rel["AX"], 3)
                        + " m out): the line flies on").
                }
            }
            IF lnAcq < 0 {
                LOCAL fxv IS grpFix().
                LOCAL rf IS larCapRef(fxv[1], fxv[2], lnCr).
                SET lnEnd TO fxv[0]. SET lnU TO fxv[1]. SET lnF TO rf[0]. SET lnT TO rf[1].
                LOCAL bad IS larCapBad(rel).
                IF bad = "" { SET bad TO grpFly(LAR_CAP_V, dt). }
                IF bad <> "" {
                    grpOff(bad + " (" + ROUND(rel["AX"], 3) + " m out, " + ROUND(rel["LAT"], 3) + " m off the axis, the boresight "
                        + ROUND(rel["ANG"], 1) + " deg off)", "CAPTURE OFF: " + bad).
                } ELSE IF lnR <= 0 {
                    IF lnEndT < 0 { SET lnEndT TO tn. }
                    IF tn - lnEndT > LAR_CAP_END_T {
                        grpOff("at the fixture's node " + LAR_CAP_END_T + " s, " + eSt + " (" + ROUND(rel["AX"], 3) + " m out)",
                            "CAPTURE OFF: NO " + (CHOOSE "DOCK" IF lnAcq = -2 ELSE "ACQUIRE")).
                    }
                }
            }
            IF grp = "CAP" {
                SET grpSt TO "CAPTURE " + (CHOOSE "ACQUIRE: THE MAGNETS CLOSE THE GAP" IF lnAcq >= 0
                    ELSE ROUND(lnR, 2) + " M TO GO" + (CHOOSE "  WAITING FOR THE ARM" IF lnEP > LAR_CAP_LAG + lnQR ELSE "")).
            }
        }
        IF grp = "REL" {                         // RELEASE: the undock (and stop; with ARM_REL_BACKOFF the back-off along the boresight after it)
            IF NOT lnMv AND lnUnd >= 0 {
                IF NOT ldOn AND armBad <> "" AND NOT armBad:STARTSWITH(LAR_MPM_BAD) { grpOff("undocked, but the arm changed: " + armBad, "RELEASE OFF: THE ARM CHANGED"). }
                ELSE IF NOT ldOn AND NOT ARM_REL_BACKOFF {      // undocked and unloaded: done, the arm stays where it is
                    grpOff("undocked: the arm holds its pose", "RELEASED: UNDOCKED").
                } ELSE IF NOT ldOn {
                    LOCAL nd IS grpNode().
                    SET lnEnd TO nd[0] - nd[3] * LAR_REL_D. SET lnU TO nd[3]. SET lnF TO nd[3]. SET lnT TO nd[2].
                    SET lnR TO LAR_REL_D. SET lnUnd TO -1. SET lnEP TO 0.
                    grpGo().
                    armPr("RELEASE: undocked; backing off " + LAR_REL_D + " m along the boresight at VERNIER").
                } ELSE IF tn - lnUnd > 2 * LAR_REL_T {
                    grpOff("still docked (" + eSt + ") " + (2 * LAR_REL_T) + " s after the undock", "RELEASE FAILED: STILL DOCKED").
                } ELSE IF NOT lnEv AND tn - lnUnd > LAR_REL_T {
                    SET lnEv TO TRUE.
                    LOCAL ev IS larUndockEv(ee).
                    IF ev = "" AND fxOk { SET ev TO larUndockEv(fx). }
                    armPr("RELEASE: still docked " + LAR_REL_T + " s after the undock: the module's event '" + ev + "'").
                }
            }
            IF grp = "REL" AND lnMv {
                LOCAL bad IS grpFly(LAR_V_GRAPPLE * LAR_VERNIER, dt).   // The approach stays at the old 0.0375 m/s
                IF bad <> "" { grpOff(bad, "RELEASE OFF: " + bad). }
                ELSE IF lnR <= 0 AND lnEP < LAR_CAP_LAG / 4 + lnQR {
                    grpOff("complete: backed off " + LAR_REL_D + " m", "RELEASED: BACKED OFF " + ROUND(LAR_REL_D, 2) + " M").
                }
            }
            IF grp = "REL" {
                SET grpSt TO "RELEASE " + (CHOOSE "BACKING OFF " + ROUND(lnR, 2) + " M TO GO" IF lnMv
                    ELSE "UNDOCKING (" + eSt + ")").
            }
        }
        IF ldOn {                                // the page: LOADED / LATCHED, else the fixture as the end effector sees it
            SET gl1:TEXT TO CHOOSE "" IF latched   // A latched payload shows no line
                ELSE "LOADED: " + ROUND(ldM * 2204.62) + " LB (" + ldN + " PARTS)  RATE x " + ROUND(ldS, 2).
            LOCAL leeP IS eSt:FIND(" (").   // The state without its " (...)" suffix (KSP: "Docked (dockee)")
            SET gl2:TEXT TO ("LEE: " + (CHOOSE eSt:SUBSTRING(0, leeP) IF leeP > 0 ELSE eSt) + (CHOOSE "   " + armBad IF armBad <> "" ELSE "")):TOUPPER.
        } ELSE IF page AND rel:LENGTH > 0 {
            SET gl1:TEXT TO "FIXTURE " + fx:STATE:TOUPPER + "  RNG " + ROUND(rel["RANGE"], 2) + " M  CLOSING "
                + grpSg(clV, 2) + " M/S  OFF AXIS " + ROUND(rel["LAT"], 3) + " M".
            SET gl2:TEXT TO "RT " + grpSg(rel["RIGHT"], 3) + " M  UP " + grpSg(rel["UP"], 3)
                + " M   PITCH " + grpSg(rel["PITCH"], 1) + "  YAW " + grpSg(rel["YAW"], 1) + "  ROLL " + grpSg(rel["ROLL"], 1) + " DEG".
        } ELSE IF page {
            SET gl1:TEXT TO "GRAPPLE: NO FIXTURE WITHIN " + ROUND(LAR_GRP_SEEK) + " M (TARGET ONE)".
            SET gl2:TEXT TO "".
        } ELSE { SET gl1:TEXT TO "". SET gl2:TEXT TO "". }
        IF svReq {                               // SAVE: the joints' targets as the next POSE n (+ AUTO 3 / AUTO 4)
            SET svReq TO FALSE.
            IF auto OR augMv OR drv OR lnMv OR opr { SET autoSt TO "SAVE REFUSED: THE ARM IS MOVING". SET autoStT TO tn. armPr(autoSt). }
            ELSE {
                LOCAL sq IS sqTo[MAX(0, pTo:INDEX)].
                LOCAL tg IS autoTgs().
                LOCAL nm IS larPoseSave(LAR_POSES_FILE, anm, tg, sq).
                SET apz TO larPosesLoad(LAR_POSES_FILE).
                autoLabels().
                SET pmu:INDEX TO apz["user"]:INDEXOF(nm).
                SET autoSt TO "SAVED " + nm + (CHOOSE " TO " + sq IF sq <> "" ELSE ""). SET autoStT TO tn.
                armPr("SAVE: " + nm + " " + autoList(tg) + (CHOOSE ", added to " + sq IF sq <> "" ELSE "") + " (" + LAR_POSES_FILE + ")").
            }
        }
        FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
            SET lb[i]:TEXT TO ROUND(jts[i][1]:GETFIELD("target angle"), 1) + " deg"
                + (CHOOSE (CHOOSE "  STALL" IF stall ELSE "  DRIVE") IF drv AND i = sel ELSE "")
                + (CHOOSE "  AUTO" IF auto AND lMv:CONTAINS(i) ELSE "")
                + (CHOOSE "  " + (CHOOSE "CAPTURE" IF grp = "CAP" ELSE "RELEASE") IF lnMv AND augFr:CONTAINS(i) ELSE "")
                + (CHOOSE "  OPR" IF opr AND augFr:CONTAINS(i) ELSE "").
        }
        // EE CAM: pressed snaps the camera to the end effector, released puts the stock one back; the addon letting go of it
        // (the IVA view) releases the button
        IF bCam:PRESSED AND NOT camOn {
            LOCAL cw IS camSnap().
            IF cw = "" { SET camOn TO TRUE. SET camSt TO "EE CAM: THE VIEW ALONG THE LEE'S BORESIGHT". }
            IF cw = "" AND ADDONS:KALS:HASSUFFIX("EECROSS") { ADDONS:KALS:EECROSS(1). }   // The centre cross while the view is on
            ELSE { SET bCam:PRESSED TO FALSE. SET camSt TO "EE CAM REFUSED: " + cw. armPr(camSt). }
            SET camStT TO tn.
        } ELSE IF camOn AND NOT bCam:PRESSED { camOff("released"). }
        ELSE IF camOn AND NOT cam:ENABLED {
            SET camOn TO FALSE. SET bCam:PRESSED TO FALSE.
            IF ADDONS:KALS:HASSUFFIX("EECROSS") { ADDONS:KALS:EECROSS(0). }
            SET camSt TO "EE CAM OFF: THE CAMERA ADDON LET GO (" + cam:STATUS + ")". SET camStT TO tn. armPr(camSt).
        }
        IF ldhOn AND NOT ldhSent AND NOT auto { armRates(dZero, ARM_TAU). }     // T1018: no mode sent this pass: the loaded hold correction goes alone (it is also the drive heartbeat)
        IF sel >= 0 { SET augSt TO "". SET autoSt TO "". SET grpSt TO "". SET oprSt TO "". }   // a joint picked: SINGLE's status again
        IF gotoSt <> "" AND tn - gotoStT < 5 AND swN < 2 { SET st:TEXT TO gotoSt:TOUPPER. }       // T1018: a slew's word (a refusal, a stop) 5 s, ahead of the stale words below (a MAN AUG OFF word stayed until a joint was picked)
        ELSE IF camSt <> "" AND tn - camStT < 5 { SET st:TEXT TO camSt:TOUPPER. }                   // EE CAM's last word 5 s
        ELSE IF frmSt <> "" AND tn - frmStT < 5 { SET st:TEXT TO frmSt:TOUPPER. }                   // a frame refused 5 s
        ELSE IF grp <> "" OR (grpSt <> "" AND tn - grpStT < 10) { SET st:TEXT TO grpSt:TOUPPER. } // GRAPPLE's last word 10 s
        ELSE IF opr OR (oprSt <> "" AND tn - oprStT < 10) { SET st:TEXT TO oprSt:TOUPPER. }       // OPR CMD's last word 10 s
        ELSE IF auto OR (autoSt <> "" AND tn - autoStT < (CHOOSE 5 IF aug ELSE 10)) { SET st:TEXT TO autoSt:TOUPPER. }   // AUTO's last word 10 s
        ELSE IF aug OR augSt:STARTSWITH("MAN AUG OFF") OR augSt:STARTSWITH("MAN AUG REFUSED") { SET st:TEXT TO augSt:TOUPPER. }
        ELSE IF swN > 1 { SET st:TEXT TO swWords():TOUPPER. }
        ELSE IF gotoSt <> "" AND (swN > 0 OR TIME:SECONDS - gotoStT < 5) { SET st:TEXT TO gotoSt:TOUPPER. }   // A typed slew's word
        ELSE SET st:TEXT TO (CHOOSE armWhy() IF armBad <> "" AND NOT armBad:STARTSWITH(LAR_MPM_BAD) ELSE CHOOSE "LATCHED: NO DRIVE"
            IF latched ELSE CHOOSE "RCS ON: DRIVE INHIBITED" IF armRcsBad() ELSE (CHOOSE asBlock IF asBlock <> "" ELSE "RATE "
            + (CHOOSE "VERNIER " IF bv:PRESSED ELSE "COARSE ") + ROUND(rate, 2) + " DEG/S"))
            + (CHOOSE "   NO JOINT SELECTED" IF sel < 0 ELSE "").
    }
    FUNCTION armEnd {                        // STOP: everything the arm holds given back
    IF grp <> "" { grpOff("STOP", ""). }
    IF aug { augOff("STOP"). }
    IF auto { autoOff("STOP", ""). }
    IF opr { oprOff("STOP", ""). }
    IF dOn { ADDONS:KALS:ARMFREE("STOP"). SET dOn TO FALSE. SET LAR_DRV TO FALSE. }
    FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
        IF jSave[i][0] >= 0 {
            jts[i][1]:SETFIELD("traverse rate", jSave[i][1]).
            armLk(jts[i][1]).
        }
        IF dmpWas[i] >= 0 { jts[i][1]:SETFIELD(LAR_F_DAMP, dmpWas[i]). }
    }
    IF camOn { camOff("STOP"). }
    IF hOk AND ARM_HOLD_EXT {                // nothing was taken: the DAP keeps the attitude (FBWXOFF lapses 0.5 s after the last tick)
        armPr("HOLD EXT OFF: the THC back to the pilot in 0.5 s; the DAP unchanged").
    } ELSE IF hOk {                          // the hold off: the axes and the translation back to the pilot, RCS / SAS as they were
        LOCAL ok IS ADDONS:KALS:FBWOFF().
        SET RCS TO rcs0. SET SAS TO sas0.
        armPr("HOLD OFF: the stick and the THC back to the pilot; RCS " + (CHOOSE "ON" IF RCS ELSE "OFF") + ", SAS " + (CHOOSE "ON" IF SAS ELSE "OFF")
            + " (as at RUN arm)").
    }
    g:DISPOSE().
    armPr("arm: STOP, the driven joints locked").
    IF asWhy = "" { armPr("arm: " + larAsStow(ee, jts)). }
    ELSE IF larAtStow(jts) { armPr("arm: stowed: set the end effector's and the elbow's AUTOSTRUT back ON in their menus"). }
    }
    IF ARM_HOST {                            // hosted: the loop body, STOP and the widgets handed to ops2q; this file ends
        GLOBAL ARM_CYCLE IS armCycle@.
        GLOBAL ARM_END IS armEnd@.
        GLOBAL ARM_SNAP IS armSnap@.
        GLOBAL ARM_ACT IS LEXICON("ldtest", { PARAMETER on. SET ldForce TO on. SET ldOn TO on. SET LAR_LDON TO on. IF on { armLdCal(). } ELSE { SET ldCal TO LIST(). armUnld(). } }, "ldbias", { PARAMETER i, d. IF ldCal:LENGTH > i { SET ldCal[i][2] TO ldCal[i][2] + d. } }, "stop", { SET quit TO TRUE. }, "save", { SET svReq TO TRUE. }, "load", { SET oprLdReq TO TRUE. }, "slew", armSlew@, "quit", { RETURN quit. }).
        GLOBAL ARM_UI IS LEXICON("jts", jts, "ee", ee, "hold", hBt, "joints", rb, "jl", lb, "vern", bv, "aug", bAug, "frame", pFrm, "stick", bStk,
            "rot", bRot, "cam", bCam, "auto", abt, "saved", pmu, "saveto", pTo, "opr", bOpr, "fields", opFd, "grp", bGrp, "cap", bCap, "rel", bRel,
            "hl", hl, "pl0", pl0, "gl1", gl1, "gl2", gl2, "st", st, "gui", g).
    } ELSE {
        UNTIL quit { armCycle(). WAIT 0. }
        armEnd().
    }
}
