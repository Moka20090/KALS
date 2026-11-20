@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_ARM.KS  --  THE CANADARM'S KINEMATICS: the arm finder, the joint map, the live Jacobian, a damped least squares
// ============================================================================
//  Shared by arm.ks (SINGLE) and the arm modes after it. Nothing here moves a joint: it finds the arm, names its
//  joints, reads the geometry from the live parts and solves for joint rates.
//  THE ARM: the end effector (the LEE) is a docking port with a servo within 3 parents; the chain is walked by PARENT
//  from the LEE to the shoulder. After a capture the grapple fixture is ALSO such a port (fixture, LEE, wrist roll), so
//  the ports are ranked by part name (larEeRank): a "LEE" first, any other port that is not a fixture next, a fixture
//  never. larEnds lists the end effectors, larChain one arm's joints from the shoulder out as
//  LIST(part, module, name, parent, next part, module name).
//  THE JOINT MAP (measured on the flown arm moves;one target degree turns the joint one
//  degree, 0.99-1.04): every HINGE turns about its own TOP vector, every ROLL (rotation servo) about its own FORE vector.
//  The sign is the outward link's turn per +1 deg of 'target angle' about that axis (the component cross product of
//  VCRS, as arm_kin logs): +1 for every joint but SHOULDER YAW (-1: it is mounted by its moving side). The ELBOW
//  PITCH's -1 is PREDICTED, never measured (the elbow did not move in any run: autostrut, then the game's -176.5 deg
//  stop): a flown test settles it; until then it is one constant, LAR_ELBOW_SIGN, and LAR_PREDICTED names it.
//  The angle is the 'target angle' field (commanded, read back as set); the 'current angle' field is dead (0, or stale).
//  THE JACOBIAN: the end effector is the LEE's docking node, LAR_NODE_D (0.330 m, fitted, rms 0.5 mm) along the LEE's
//  FORE from its part origin. Joint i's column is  s * (a x (P - p))  (linear, m per rad) over  s * a  (angular, rad per
//  rad), with p the servo part's position and a its axis, all read live from the parts: no joint angle is needed. Against
//  the measured end-effector moves it matches to 0.0-1.5 mm on 14-42 mm moves (the flipped sign misses by 27-84 mm).
//  Vectors are in any ONE frame (kOS raw); the tests use the vessel's (star, top, fore), where the same formulas hold.
//  THE SOLVE: dq = J^T (J J^T + lam2 I)^-1 v (damped least squares, 6 task rows). Away from a singularity lam2 = 0
//  (the exact inverse for 6 free joints); larLam2 raises it as the manipulability larManip falls below w0.
//  THE AUTOSTRUT (the end effector and elbow parts wiggle in launch unless their autostrut is on, so it is turned off before arm
//  operation and back on at stow):
//  an autostrutted arm part is held to the vessel like the RMS's retention latches (the elbow does not move, the shoulder
//  only flexes). A part's autostrut is not a module's field, so kOS reaches it through KalsCoproc's ASTRUT. Before any
//  joint drives, larAsOff turns it OFF on every arm part (larArmParts: the end effector up to the shoulder's servo) and
//  the arm drives only when none is left on; at the stow pose (larAtStow: every joint's 'target angle' within
//  LAR_STOW_TOL of the craft's LAR_STOW) larAsStow puts the end effector's and the elbow's back ON (larAsLaunch), in the
//  mode they had (LAR_AS_WAS, this run), else LAR_AS_ON, and every other arm part larAsOff found ON (the booms) in the mode it had. Without ASTRUT (an older KalsCoproc.dll) larAsWhy says why and
//  the pilot sets the struts in the part menus.
//  MANUAL AUG (translation in the orbiter's frame: the aft-station view, the rates): the
//  THC (PILOTSTARBOARD / PILOTTOP / PILOTFORE) asks for the node's velocity (larThcVel: LAR_V_COARSE, x LAR_VERNIER),
//  the end effector's attitude held. Each tick the task is that velocity plus a pull back to a reference pose that moves
//  with the command (larAugTask: LAR_K_POS on the position, LAR_K_ATT on the attitude error larAttErr), so the axes not
//  commanded do not drift. larAugRates solves the damped least squares (all 6 joints) and scales every joint
//  together to LAR_QD_MAX; larSoftHit finds a joint that would run into its soft stop (LAR_SOFT inside LAR_RANGE);
//  larModelBad compares the node's measured move with the one the solve asked for (a wrong sign, or a joint that does not
//  follow, fails it).
//  ROTATION AND THE END EFF FRAME (the RHC through the OMS gimbal, the orbiter's torque off): the RHC (pitch, yaw, roll) asks for the end effector's turn about its node, the
//  point of resolution (larRhcRate: LAR_W_COARSE, x LAR_VERNIER; LAR_RHC_SIGN, the aft-station view of C1). SHIP:CONTROL:
//  PILOTPITCH / YAW / ROLL read 0 in this install (css-dap-mechanics 1), so the stick is the OMS gimbal's readback
//  (larOmsEng); the stick also turns the orbiter through its reaction wheels and kOS raw control cannot cancel that
//  (css-dap-mechanics 2b), so every ModuleReactionWheel's 'wheel authority' goes to 0 (larTorqueOff, the old ones kept in
//  LAR_TQ_WAS) while the stick is read and back (larTorqueBack) after. Whether that stops the stick turning the orbiter is
//  not yet seen in game (the probe, Flight Checklist); the fallback is the TRANS / ROT switch (larThcRot: the THC turns the
//  end effector). The commands are in the ORB UNL's components; larCmdAxes gives the frame's axes: ORB UNL the orbiter's,
//  END EFF the end effector's (the view along the LEE's boresight: forward its FORE, right its STAR, up its TOP; the TOP
//  as the camera's up is PREDICTED). The reference attitude turns with the command (larAugStep, after the solve) on a leash
//  of LAR_REF_ANG while turning (larAugRef); larAttErr is the exact small turn over all three axes; larModelBadW is the
//  model check's turn half (the end effector's measured turn against the one the solve asked for).
//  AUTO: stored poses in joint space, each a LEXICON(joint name ->
//  'target angle'; a joint a pose lacks holds where it is): STOW (LAR_STOW, the craft's: the elbow -180, which the
//  re-centred joint holds; without it the elbow stops at about -176.5), PRE-CRADLE (LAR_PRE_CRADLE: the shoulder pitch
//  and the elbow opened 5 deg each, so the folded arm rises 0.30-0.32 m clear of its cradles with the end effector's
//  attitude unchanged), READY (LAR_READY: the node 5 m straight up over the port sill, the attitude unchanged, the elbow
//  well above LAR_AUG_ELBOW: MAN AUG's start) and the operator's own (larPoseSave: "POSE n" in LAR_POSES_FILE, optionally
//  added to AUTO 3 or AUTO 4). AUTO 1-4 are sequences of pose names (LAR_AUTO_SEQ; the file's own AUTO n replaces the
//  default). larSafePath turns a sequence into the legs flown: a folded arm (the elbow at or below LAR_AUG_ELBOW) leaves
//  through PRE-CRADLE and READY, STOW is reached from READY through PRE-CRADLE, and both cradle legs (STOW <-> PRE-CRADLE)
//  fly at VERNIER: a single joint-space move from the cradle could sweep the arm through the bay. All of these legs stay
//  in the arm's own plane above the sill (shoulder yaw 0). A leg moves every joint on a straight line in joint space
//  (larMoveAt), so all arrive together; the fastest at LAR_QD_MAX (x LAR_VERNIER); the ramp holds while a joint lags
//  (larLegBehind). larFkNode predicts the node a leg
//  reaches from the live geometry at its start with the model's signs (or one flipped): each waypoint's log line is a
//  check of the elbow's predicted sign on any AUTO move that turns the elbow.
//  GRAPPLE (a grapple-fixture payload in the bay): the LEE
//  (ht_C1_LEE) and the HT-FRGS fixture (ht_grappleFixture) are a stock docking pair (nodeType PDGF, acquireRange 0.4 m,
//  acquireForce and acquireTorque 0.5, undockEjectionForce 0); the capture tolerances are KSP's defaults (the configs set
//  none: captureRange 0.06 m, captureMinFwdDot 0.998, any roll), to be confirmed in game. larFixtures finds the fixture
//  (the target when it is a docking port, else the nearest fixture port within LAR_GRP_SEEK of the node, on this vessel
//  or a loaded one); larGrpRel is the fixture as the end effector sees it (the END EFF view: its range along the
//  boresight, right, up; the turn that aligns the boresight with the fixture's axis, in the END EFF stick's pitch / yaw
//  / roll; the node's distance out along the fixture's axis and off it). CAPTURE (allowed within larCapOk's box) flies a
//  straight line (larLineTick): the reference slides along the fixture's axis at LAR_CAP_V to the fixture's node, held
//  while the node lags it by more than LAR_CAP_LAG, and the pulls (larAugTask's, on MAN AUG's leashes) hold the node on
//  the axis and the boresight along it with the roll kept (larCapRoll / larCapRef); larCapBad stops it when the node or
//  the boresight strays. On "Acquire" the joints lock and the magnets close the gap (KSP's acquire pull; the SCOM's
//  snares and rigidize, 2.21); on "Docked" the arm is LOADED: larLoadMass weighs the parts hanging on the LEE and
//  larLoadScale slows every rate by 1 / (1 + m / LAR_M_REF). Docked with no fixture beneath the LEE (a payload still
//  held in the bay: the same vessel) is LATCHED: the arm does not move until it is free. RELEASE undocks (larUndockEv as
//  the fallback) and flies larLineTick back LAR_REL_D along the boresight at VERNIER, the attitude held.
//  THE END EFFECTOR CAMERA: arm.ks's EE CAM snaps the flight camera (kOS StockCamera 0.3.1's FREECAMERA) to the end effector's view.
//  larCamPose is the camera's pose from the LEE's part origin and FACING: the eye LAR_CAM_D along its FORE (at the docking
//  node), looking along the boresight with the LEE's TOP up, so its right is VCRS(up, forward) = the LEE's STAR (a Unity
//  camera's right is Cross(up, forward), as a FACING's STARVECTOR is). That is the END EFF frame's view (larCmdAxes): the
//  THC's H moves the node into the picture, L to its right, I up; the RHC's pitch up tips the view up, yaw right swings it
//  right, roll right tilts its top to the right; and GRAPPLE's page (larGrpRel's RANGE / RIGHT / UP) is the fixture's
//  place in the picture (larCamSee, the eye being the node). The addon keeps the pose in the anchor part's own space, so
//  with the LEE as the anchor the view rides the end effector as the arm moves; nothing is set again each tick.
//  OPR CMD AND THE ORB LD / PL FRAMES: the RMS's four MAN AUG frames.
//  ORB UNL and END EFF resolve at the node; ORB LD (the orbiter's axes, the aft-station view) and PL (the payload's axes)
//  resolve at the point of resolution (POR) on the payload: its centre of mass (larLoadCom: the parts hanging on the
//  LEE, their origins weighed by mass), kept as components on the LEE's axes (rigid once captured). A POR r off the node
//  changes only the task (larPorTask): the POR moves at the velocity asked and the turn is about it, so the node's velocity
//  is the POR's less VCRS(the turn, r); the Jacobian stays the node's. The PL frame is the grapple fixture's (larPlView:
//  forward into the payload along the fixture's axis, up its TOP). Every view is LIST(right, up, forward) with right =
//  VCRS(up, forward), as the camera's. OPR CMD (the RMS's operator commanded auto sequence) flies the POR to a keyed pose
//  on a straight line while its attitude turns about one axis (larRotTurn: the exact eigen axis, 0 - 180 deg), both
//  arriving together (larOprNew: the time the longer of the line at the MAN AUG rate and the turn at the MAN AUG turn
//  rate). The pose is keyed as the RMS's: the position X aft, Y starboard, Z up from the shoulder (larPoseXyz /
//  larXyzPose; the window in feet), the attitude pitch, yaw, roll (deg, in that order about the moving axes;
//  larEulerAxes / larEulerOf) of the end effector's view (the PL frame's when ORB LD or PL is picked) against the
//  aft-station view (larOrbView: 0 / 0 / 0 = the boresight aft, its top out of the bay). Each tick (larOprTick) the
//  reference moves on along the line and the turn while the POR keeps within LAR_OPR_LAG / LAR_OPR_LAGA of it (the line's
//  and the turn's rates fed forward), and the pulls hold the POR on it on MAN AUG's leashes. larReach bounds what the
//  arm can reach (the links' lengths from the shoulder pitch pivot).
// ============================================================================

GLOBAL LAR_NODE_D IS 0.33.                  // m: the LEE's docking node beyond its part origin, along its FORE
GLOBAL LAR_CAM_D IS 0.30.                   // m: the end effector camera's eye beyond the LEE's part origin, along its FORE. The model's dockingNode transform (the snare's face) is at 0.317 (ht_C1_LEE.mu), LAR_NODE_D 0.33 (the IK's fitted node) put the eye 1.3 cm in front of it; 0.30 = just inside the face
GLOBAL LAR_D2R IS 3.14159265358979 / 180.
GLOBAL LAR_F_TARGET IS "target angle".      // the commanded angle, deg: read and written (the only angle field that works)
GLOBAL LAR_F_LOCK IS "locked".
GLOBAL LAR_F_DAMP IS "damping".             // the servo drive's damping, 0-200 (the parts carry 100)
GLOBAL LAR_DAMP IS 200.                     // the damping while the arm runs: the slider's top; the drive's damper is linear in it
    // (ModuleRoboticServoHinge.OnModifyServo: positionDamper = multiplier x motor size x damping / 100), so 200 doubles the
    // damper. At 100 a 2 deg elbow step overshot 10 % and rang at ~1.3 s for 5 s (arm_motion_75379: the node +-1.5 cm).
GLOBAL LAR_QSTEP IS 1.                      // deg: the step of the servos' target angle (and traverse rate, min 1) slider. kOS's
    // SETFIELD rounds a slider field to its step (KOSMath.ClampToIndent from the slider's min), so the joints move in whole
    // degrees and a target read back is the rounded one: the drives keep their own running command.
GLOBAL LAR_Q_K IS 1.5.                      // steps a joint may sit off its running command at a window's end: half a step of
                                            // rounding + one step still slewing at the traverse rate
GLOBAL LAR_MODEL_WMAX IS 10.                // s: the longest model window (the check waits until the ask clears what the steps hide)
GLOBAL LAR_HINGE IS "ModuleRoboticServoHinge".          // turns about its own TOP
GLOBAL LAR_ROLL IS "ModuleRoboticRotationServo".        // turns about its own FORE
GLOBAL LAR_ELBOW_SIGN IS -1.                // PREDICTED, not measured: a flown test settles it (SET ARM_JOINTS TO LIST(5). RUN arm_motion.)
GLOBAL LAR_PREDICTED IS LIST("ELBOW PITCH").            // the joints whose sign is a prediction
// The arm is the real SRMS's 6 joints (SY SP EP WP WY WR); the KerboArm's UPPER ARM ROLL is gone
// from every table. The MPM roll under the shoulder is not an arm joint (LAR_MPM below).
GLOBAL LAR_NAMES6 IS LIST("SHOULDER YAW", "SHOULDER PITCH", "ELBOW PITCH", "WRIST PITCH", "WRIST YAW", "WRIST ROLL").
GLOBAL LAR_MPM IS LIST().                   // the MPM roll servo (the base servo under the shoulder yaw: a hinge about the bay's axis): LIST(part, module, name, parent, next, module name); empty when the orbiter has none
GLOBAL LAR_MPM_NAME IS "MPM ROLL".
// The MPM roll's three positions. STOW 12 = the craft's
// start (the most the CLOSED bay doors allow), DEPLOY 30 (the real MPM's 31.36 clips the handrail), CENTER 0 (over the bay). The roll is 0..30.
GLOBAL LAR_MPM_CENTER IS 0.
GLOBAL LAR_MPM_STOW IS 12.
GLOBAL LAR_MPM_DEPLOY IS 30.
GLOBAL LAR_MPM_RATE IS 2.                   // deg/s of a go: the design value (11-13 "Just do 2 deg/s"; the 18 deg STOW <-> DEPLOY ~9 s); one place to change it
GLOBAL LAR_MPM_TOL IS 0.5.                  // deg: the commanded angle this close to a position IS that position
GLOBAL LAR_MPM_BAD IS "MPM MOVING".         // the arm's hold text starts with this while the MPM roll is MOVING (arm.ks armBad); the only MPM hold (the arm works at every MPM setting)
GLOBAL LAR_MPM_GO IS LIST(0, 0, 0, 0).      // the last go: from, goal, start time, duration (s; 0 = none pending)
GLOBAL LAR_EE_FLIP IS FALSE.                // The LEE sits 180 deg about its FORE on its wrist mount (the craft files' EE 180): TRUE = the END EFF frame, the EE CAM, the POR attitude and the
                                            // capture roll use the LEE's axes turned back (TOP / STAR reversed), so they read as with the old mount; FALSE (the default) = the LEE's own axes. One switch: the automated test's smoke decides.
GLOBAL LAR_BAY_TEST IS -1.                  // offline tests: 0 / 1 forces the bay doors closed / open (-1 = read the part)
GLOBAL LAR_MPM_PART IS "MPMROLL".           // The MPM roll servo is found by what it is: its part's name or title (case, dots, underscores and spaces ignored) holds this
GLOBAL LAR_ARM_JOINTS IS 6.                 // The arm's joints (the real SRMS's); a chain of another count is refused (LAR_CHAIN_ERR)
GLOBAL LAR_CHAIN_ERR IS "".                 // larChain's last verdict: "" the chain is the 6 joints, else why not (a craft from before: 7 = an UPPER ARM ROLL, ...)
GLOBAL LAR_SIGN IS LEXICON("SHOULDER YAW", -1, "SHOULDER PITCH", 1, "ELBOW PITCH", LAR_ELBOW_SIGN,
                           "WRIST PITCH", 1, "WRIST YAW", 1, "WRIST ROLL", 1).
GLOBAL LAR_TINY IS 1e-12.                   // a pivot this small is not divided by
GLOBAL LAR_AS_ON IS "Heaviest".             // the launch autostrut put back at stow when the part's own is not known
GLOBAL LAR_AS_WAS IS LEXICON().             // part UID -> the autostrut larAsOff found on it (this run)
GLOBAL LAR_STOW IS LEXICON("SHOULDER YAW", 0, "SHOULDER PITCH", -90, "ELBOW PITCH", -180,
                           "WRIST PITCH", 0, "WRIST YAW", 0, "WRIST ROLL", 0).   // deg: the craft's stowed 'target angle's
GLOBAL LAR_STOW_TOL IS 1.                   // deg: a joint this close to its LAR_STOW is stowed
GLOBAL LAR_THC_SIGN IS V(-1, 1, -1).        // the THC's (PILOTSTARBOARD, PILOTTOP, PILOTFORE) to the node's (star, top, fore)
    // in the orbiter's frame, seen from the aft flight deck facing aft (C1): H (fore +1) moves it aft, N forward; J (left,
    // starboard -1) to the operator's left = the orbiter's starboard, L to port; THC UP (top +1) out of the bay / up, DOWN
    // (top -1) into it. The top sign was -1
    // (predicted from I = TRANSLATE_DOWN), flown backwards; +1 now: the node moves the way the THC's up / down says.
GLOBAL LAR_V_COARSE IS 0.30.                // m/s: the node's rate at COARSE (C4). 0.30; REALISTIC MODE: 0.15
GLOBAL LAR_V_GRAPPLE IS 0.15.               // m/s: GRAPPLE's approach is this x LAR_VERNIER = 0.0375 m/s, the old speed (a capture is the slow, precise case; the x2 rates do not touch it)
GLOBAL LAR_VERNIER IS 0.25.                 // VERNIER = COARSE x this (C4)
GLOBAL LAR_QD_MAX IS 8.                     // deg/s: every joint's rate cap (C4; the part's own limit is 10). 8 (at 4 the arm is RATE LIMITED from 0.2 m/s up); REALISTIC MODE: 4
GLOBAL LAR_K_POS IS 0.                      // 1/s: the pull back to the reference position. 0: the pull acts on the MEASURED tip, which holds the arm base mount's 0.5 Hz swing, and pumped it (ring 21-37 cm; 0.5 cm with 0); pure resolved-rate control, like the real RMS. Keep 1 for T762 REALISTIC MODE only if wanted.
GLOBAL LAR_K_ATT IS 0.                      // 1/s: the pull back to the reference attitude (0, was 1; same reason as LAR_K_POS)
GLOBAL LAR_REF_MAX IS 0.05.                 // m: the reference position at most this far from the node (a lagging arm)
GLOBAL LAR_W0 IS 1.                         // the manipulability below which the solve is damped (SINGULAR)
GLOBAL LAR_LAM0 IS 0.1.                     // the damping at a singularity
GLOBAL LAR_SOFT IS 5.                       // deg: the soft stop inside each end of a joint's range
GLOBAL LAR_RANGE IS LEXICON("SHOULDER YAW", LIST(-180, 180), "SHOULDER PITCH", LIST(-120, 120),
                            "ELBOW PITCH", LIST(-180, 0), "WRIST PITCH", LIST(-120, 120), "WRIST YAW", LIST(-120, 120),
                            "WRIST ROLL", LIST(-180, 180)).   // deg: the htRobotics part configs
GLOBAL LAR_AUG_ELBOW IS -170.               // deg: MAN AUG only with the elbow's target above this (unstow first)
GLOBAL LAR_MODEL_MIN IS 0.02.               // m: the model check judges a move this long or longer...
GLOBAL LAR_MODEL_TOL IS 0.5.                // ...and fails it when the miss is more than this share of it + LAR_MODEL_ABS
GLOBAL LAR_MODEL_ABS IS 0.01.               // m
GLOBAL LAR_W_COARSE IS 3.                   // deg/s: the end effector's turn rate at COARSE (C4); VERNIER x LAR_VERNIER. 3; REALISTIC MODE: 1.5. OPR CMD still flies at it; MAN AUG: below
GLOBAL LAR_W_AUG IS 8.                      // deg/s: MAN AUG's COARSE turn rate: MAN AUG's VERN is LAR_W_COARSE (3, the old COARSE), COARSE = 8 (the x4 ratio would be 12, but every joint caps at LAR_QD_MAX 8, so 12 could not be flown); VERN stays 3
GLOBAL LAR_RHC_SIGN IS V(1, 1, 1).          // the RHC's (pitch, yaw, roll) to the turn about the ORB UNL's (star, top, fore),
    // seen from the aft flight deck facing aft (C1): pitch up tips the end effector's aft-pointing axis up (about +star),
    // yaw right swings it to the operator's right = port (about +top), roll right turns its top to the operator's right
    // (about +fore). The stick's own signs (the OMS gimbal, css-dap-mechanics 5): + pitch nose up, + yaw right, + roll right.
GLOBAL LAR_REF_ANG IS 1.                    // deg: while turning, the reference attitude at most this far from the end effector's
GLOBAL LAR_MODEL_WMIN IS 1.                 // deg: the model check judges a turn this big or bigger...
GLOBAL LAR_MODEL_WABS IS 0.25.              // deg: ...and fails it when the miss is more than LAR_MODEL_TOL of it + this
GLOBAL LAR_F_WHEEL IS "wheel authority".    // ModuleReactionWheel's authority slider, 0-100 (KSP's #autoLOC_6001309)
GLOBAL LAR_TQ_WAS IS LIST().                // LIST(module, authority) for every wheel larTorqueOff turned to 0
GLOBAL LAR_PRE_CRADLE IS LEXICON("SHOULDER YAW", 0, "SHOULDER PITCH", -85, "ELBOW PITCH", -175,
                                 "WRIST PITCH", 0, "WRIST YAW", 0, "WRIST ROLL", 0).   // deg: the arm just clear of its cradles
GLOBAL LAR_READY IS LEXICON("SHOULDER YAW", 0, "SHOULDER PITCH", -70, "ELBOW PITCH", -90,
                            "WRIST PITCH", -70, "WRIST YAW", 0, "WRIST ROLL", 0).      // deg: unstowed, MAN AUG's start
GLOBAL LAR_BUILT_IN IS LIST("STOW", "PRE-CRADLE", "READY").   // the poses the file cannot redefine
GLOBAL LAR_AUTO_SEQ IS LEXICON("AUTO 1", LIST("PRE-CRADLE", "READY"), "AUTO 2", LIST("READY", "PRE-CRADLE", "STOW"),
                               "AUTO 3", LIST(), "AUTO 4", LIST()).   // the default sequences (pose names)
GLOBAL LAR_AUTO_NAME IS LEXICON("AUTO 1", "UNSTOW", "AUTO 2", "STOW", "AUTO 3", "", "AUTO 4", "").
GLOBAL LAR_POSES_FILE IS "0:/arm_poses.json".   // the operator's poses and sequences
GLOBAL LAR_POSE_SAME IS 0.1.                // deg: a waypoint this close to where the arm is commanded is skipped
GLOBAL LAR_FK_TOL IS 0.05.                  // m: a waypoint's node within this + LAR_FK_SHARE x the move of the prediction
GLOBAL LAR_FK_SHARE IS 0.1.                 //    agrees with the model
GLOBAL LAR_GRP_SEEK IS 30.                  // m: a fixture this close to the node is found (larFixtures)
GLOBAL LAR_CAP_START IS 0.6.                // m: CAPTURE starts with the node at most this far out along the fixture's axis,
GLOBAL LAR_CAP_LAT IS 0.1.                  //    at most this far off it (m)
GLOBAL LAR_CAP_ANG IS 10.                   //    and the boresight at most this far off it (deg)
GLOBAL LAR_CAP_V IS 0.02.                   // m/s: CAPTURE's rate along the fixture's axis
GLOBAL LAR_CAP_LAG IS 0.02.                 // m: the line's reference waits while the node is farther than this from it
GLOBAL LAR_CAP_LAT_MAX IS 0.15.             // m: CAPTURE stops when the node strays this far off the axis
GLOBAL LAR_CAP_ANG_MAX IS 15.               // deg: ...or the boresight this far off it
GLOBAL LAR_CAP_ACQ_T IS 10.                 // s: an Acquire not docked in this long: the line flies on (the gap did not close)
GLOBAL LAR_CAP_END_T IS 10.                 // s: the line at the fixture's node this long with no Acquire: CAPTURE stops
GLOBAL LAR_REL_D IS 0.5.                    // m: RELEASE backs off this far along the boresight, at VERNIER
GLOBAL LAR_REL_T IS 3.                      // s: RELEASE waits this long for the undock, then tries the module's event
GLOBAL LAR_M_REF IS 1.6.                    // t: the payload mass that halves the arm's rates (larLoadScale)
GLOBAL LAR_KSP_CAP_R IS 0.06.               // m: KSP's default captureRange (the docking module's; the configs set none)
GLOBAL LAR_KSP_CAP_DOT IS 0.998.            // KSP's default captureMinFwdDot (3.6 deg)
GLOBAL LAR_M_FT IS 3.28084.                 // ft per m (the page shows feet and inches)
GLOBAL LAR_OPR_LAG IS 0.05.                 // m: OPR CMD's reference waits while the POR is farther than this from it...
GLOBAL LAR_OPR_LAGA IS 2.                   // deg: ...or its attitude this far off it
GLOBAL LAR_OPR_TOL IS 0.01.                 // m: OPR CMD has arrived with the POR this close to the keyed pose...
GLOBAL LAR_OPR_TOLA IS 0.5.                 // deg: ...and its attitude this close
GLOBAL LAR_REACH_SHARE IS 0.97.             // OPR CMD refuses a node farther from the shoulder pitch pivot than this share of the reach
GLOBAL LAR_FRAMES IS LIST("ORB UNL", "END EFF", "ORB LD", "PL").   // MAN AUG's frames (ORB LD and PL only LOADED)
// the orbiter's attitude hold while the arm runs (ARM-STAB): the real DAP's VERN-style phase plane in KSP terms
GLOBAL LAR_HOLD_DB IS 1.0.                  // deg: the attitude deadband (no rate is commanded inside it)
GLOBAL LAR_HOLD_K IS 0.1.                   // deg/s per deg: the rate commanded per degree past the deadband...
GLOBAL LAR_HOLD_RATE IS 0.2.                // deg/s: ...at most this (relative to the reference frame)
GLOBAL LAR_HOLD_RDB IS 0.02.                // deg/s: the rate deadband (no jet fires inside it)
GLOBAL LAR_HOLD_RMIN IS 0.04.               // deg/s: past the deadband the rate commanded back is at least this (> the rate
                                            // deadband, so the jets fire as the deadband is crossed)
GLOBAL LAR_HOLD_TAU IS 2.                   // s: the rate loop's time constant
GLOBAL LAR_HOLD_ACC IS 0.05.                // deg/s2: the hold's largest angular acceleration (its load on the arm)
// The STIFF hold while the arm WORKS (a joint
// moves, MAN AUG, a goto / slew, a capture / release, a payload held; arm.ks sets LAR_HOLD_WORK, held LAR_HOLD_WORK_HANG s after the last of these): the deadband and the acceleration cap of
// the automated test flight's b4k run (hold error <= 0.42 deg and rate <= 0.08 deg/s through the unstow, PRE-ROLL, TURN and the stand-off; the gentle law above gave 4.27 deg in b4i). The idle hold keeps LAR_HOLD_DB / _ACC.
GLOBAL LAR_HOLD_AUG_DB IS 0.3.              // deg: the deadband while the arm works
GLOBAL LAR_HOLD_AUG_ACC IS 0.25.            // deg/s2: the acceleration cap while the arm works
GLOBAL LAR_HOLD_WORK IS FALSE.              // set by arm.ks: the arm is working
GLOBAL LAR_HOLD_WORK_HANG IS 5.             // s: the stiff law stays this long after the arm's last move
GLOBAL LAR_HOLD_WF IS 1.                    // s: the reference frame's own turn rate filtered over this
// the joints driven every physics tick by KalsCoproc (ADDONS:KALS:ARMDRIVE ...; coproc/ArmDrive.cs), the kOS path kept
GLOBAL LAR_DRV IS FALSE.                    // TRUE while the C# drive has the joints (arm.ks sets it): no whole-degree steps
GLOBAL LAR_TAU IS 0.4.                      // s: the commands' smoothing (two first-order stages): no step in rate at a start
    // or a stop, so the arm's ~1.3 s attach-joint ring is not rung (arm_motion_75379); the arm coasts ~2 tau x its rate after
GLOBAL LAR_TAU_J IS 0.1.                    // s: the C# joint filter under MAN AUG / OPR CMD / CAPTURE (their command is smooth)
GLOBAL LAR_QSTEP_DRV IS 0.25.               // deg: what a C#-driven joint may sit off its command (flex, the drive's lag)
GLOBAL LAR_LAG_T IS 0.6.                    // s: a joint following a moving command trails it by up to rate x this (the kOS
                                            // path: one or two kOS ticks + the unlock; the C# path: the drive and the flex)
GLOBAL LAR_STALL_T IS 0.6.                  // s: a joint is STALLED only when it trails past the allowance this long
GLOBAL LAR_LDON IS FALSE.                   // T1018: arm_body sets it while LOADED (a payload on the LEE)
GLOBAL LAR_LD_AL IS 2.                      // deg: the allowance's extra while LOADED (arm_75697: a 5.7 t payload, WRIST PITCH 2.4 deg behind its command at a typed slew = STALL)
GLOBAL LAR_STALL_T_LD IS 1.2.               // s: ...and the time past it before a loaded joint is STALLED
GLOBAL LAR_GOTO_K IS 1.875.                 // a minimum-jerk move's time / the constant-rate time at the same peak rate
GLOBAL LAR_GOTO_TMIN IS 4.                  // s: the shortest C# GOTO (ArmDriveCore.GOTO_TMIN: shorter rings the arm)
GLOBAL LAR_GOTO_TB IS 2.                    // s: a long C# GOTO's blend (cruise at the leg's rate, its rate blended up / down over
                                            // this: the constant-rate time + 2 s, where minimum jerk takes 1.875 x; > 1.5 x the ring)

// ---- the arm finder ---------------------------------------------------------------------------------------------
FUNCTION larMod {                            // a part's servo module name, or ""
    PARAMETER pt.
    IF pt:MODULES:CONTAINS(LAR_HINGE) { RETURN LAR_HINGE. }
    IF pt:MODULES:CONTAINS(LAR_ROLL) { RETURN LAR_ROLL. }
    RETURN "".
}
FUNCTION larEeRank {                         // a docking port's part name as an end effector: 2 a LEE, 1 another port, 0 a fixture
    PARAMETER nm.
    LOCAL u IS nm:TOUPPER.
    IF u:CONTAINS("GRAPPLE") OR u:CONTAINS("FIXTURE") OR u:CONTAINS("PDGF") { RETURN 0. }
    IF u:CONTAINS("LEE") { RETURN 2. }
    RETURN 1.
}
FUNCTION larEnds {                           // the end effectors: ports with a servo within 3 parents, the best rank only
    LOCAL best IS 0.
    LOCAL cand IS LIST().
    LOCAL rk IS LIST().
    FOR dp IN SHIP:DOCKINGPORTS {
        LOCAL pq IS dp. LOCAL k IS 0.
        UNTIL k >= 3 OR NOT pq:HASPARENT {
            SET pq TO pq:PARENT. SET k TO k + 1.
            IF larMod(pq) <> "" {
                LOCAL rn IS larEeRank(dp:NAME).
                cand:ADD(dp). rk:ADD(rn).
                IF rn > best { SET best TO rn. }
                BREAK.
            }
        }
    }
    LOCAL ees IS LIST().
    IF best > 0 {
        FROM { LOCAL i IS 0. } UNTIL i >= cand:LENGTH STEP { SET i TO i + 1. } DO {
            IF rk[i] = best { ees:ADD(cand[i]). }
        }
    }
    RETURN ees.
}
FUNCTION larChain {                          // one arm's joints, shoulder out: LIST(part, module, name, parent, next, module name)
    PARAMETER ee.
    LOCAL jts IS LIST().
    LOCAL pq IS ee. LOCAL prev IS pq. LOCAL gap IS 0.
    UNTIL NOT pq:HASPARENT OR gap > 2 {
        SET prev TO pq.
        SET pq TO pq:PARENT.
        LOCAL sm IS larMod(pq).
        IF sm <> "" AND pq:HASPARENT { jts:INSERT(0, LIST(pq, pq:GETMODULE(sm), "", pq:PARENT, prev, sm)). SET gap TO 0. }
        ELSE { SET gap TO gap + 1. }
    }
    // The MPM roll servo (KALS_MpmRoll, the base servo on the shoulder pedestal) is found by WHAT IT IS, the chain's first servo whose part name
    // or title says MPM ROLL; never by the joint count (an MPM + the 6 arm joints is 7 servos, the same count the old arm without an MPM had). It is
    // kept in LAR_MPM and is not an arm joint: the arm's joint list, its names, signs and stow are the 6.
    SET LAR_MPM TO LIST().
    SET LAR_CHAIN_ERR TO "".
    IF jts:LENGTH > 0 {
        LOCAL mp IS jts[0][0].
        IF larNorm(mp:NAME):CONTAINS(LAR_MPM_PART) OR larNorm(mp:TITLE):CONTAINS(LAR_MPM_PART) {
            SET LAR_MPM TO jts[0].
            SET LAR_MPM[2] TO LAR_MPM_NAME.
            jts:REMOVE(0).
        }
    }
    LOCAL nm IS LIST().
    IF jts:LENGTH = LAR_ARM_JOINTS { SET nm TO LAR_NAMES6. }
    ELSE {
        SET LAR_CHAIN_ERR TO "THIS CRAFT'S ARM HAS " + jts:LENGTH + " JOINTS, THE ARM IS " + LAR_ARM_JOINTS + " (SY SP EP WP WY WR)"
            + (CHOOSE ": REMOVE ITS UPPER ARM ROLL IN THE VAB" IF jts:LENGTH = LAR_ARM_JOINTS + 1 ELSE "").
    }
    FROM { LOCAL i IS 0. } UNTIL i >= jts:LENGTH STEP { SET i TO i + 1. } DO {
        SET jts[i][2] TO CHOOSE nm[i] IF nm:LENGTH > 0 ELSE "JOINT " + (i + 1).
    }
    RETURN jts.
}
FUNCTION larNorm {                           // A name as upper case with the dots, underscores and spaces taken out (KSP writes KALS_MpmRoll as KALS.MpmRoll)
    PARAMETER s.
    RETURN s:TOUPPER:REPLACE(".", ""):REPLACE("_", ""):REPLACE(" ", "").
}

FUNCTION larMpmHas {                         // this orbiter has the MPM roll servo (larChain found KALS_MpmRoll under the shoulder)
    RETURN LAR_MPM:LENGTH > 0.
}
FUNCTION larMpmAngle {                       // the MPM roll servo's commanded angle (deg); 0 without one
    IF LAR_MPM:LENGTH = 0 { RETURN 0. }
    RETURN LAR_MPM[1]:GETFIELD(LAR_F_TARGET).
}
FUNCTION larEeFace {                         // The LEE's facing as the arm's frames use it (see LAR_EE_FLIP)
    PARAMETER ee.
    IF LAR_EE_FLIP { LOCAL fc IS ee:FACING. RETURN LOOKDIRUP(fc:FOREVECTOR, -fc:TOPVECTOR). }   // the same FORE, TOP (and so STAR) reversed
    RETURN ee:FACING.
}
FUNCTION larMpmClamp {                       // The MPM roll's travel is 0 (CENTER) .. 30 (DEPLOY), the limit set by design (also baked into KALS_MpmRoll.cfg)
    PARAMETER a.
    RETURN MAX(LAR_MPM_CENTER, MIN(LAR_MPM_DEPLOY, a)).
}
FUNCTION larMpmSet {                         // command the MPM roll servo to ang deg (clamped 0..30); false without one
    PARAMETER ang.
    IF LAR_MPM:LENGTH = 0 { RETURN FALSE. }
    LAR_MPM[1]:SETFIELD(LAR_F_TARGET, larMpmClamp(ang)).
    RETURN TRUE.
}
FUNCTION larBayOpen {                        // the payload bay doors are open (ops3q's test: the part's 'close' event exists only while the bay is open); LAR_BAY_TEST 0 / 1 forces it (offline tests)
    IF LAR_BAY_TEST >= 0 { RETURN LAR_BAY_TEST = 1. }
    FOR bp IN SHIP:PARTSNAMED("benjee10.shuttle.midFuselage") {
        IF bp:HASMODULE("ModuleAnimateGeneric") { RETURN bp:GETMODULE("ModuleAnimateGeneric"):HASEVENT("close"). }
    }
    RETURN FALSE.
}
FUNCTION larMpmMoving {                      // the MPM roll is still on its way to the last goal (from the time and the rate the go was made at)
    RETURN LAR_MPM_GO[3] > 0 AND TIME:SECONDS < LAR_MPM_GO[2] + LAR_MPM_GO[3].
}
FUNCTION larMpmMode {                        // NONE (no MPM), MOVING, CENTER (0), STOWED (12), DEPLOYED (30) or BETWEEN
    IF LAR_MPM:LENGTH = 0 { RETURN "NONE". }
    IF larMpmMoving() { RETURN "MOVING". }
    LOCAL a IS larMpmAngle().
    IF ABS(a - LAR_MPM_CENTER) <= LAR_MPM_TOL { RETURN "CENTER". }
    IF ABS(a - LAR_MPM_STOW) <= LAR_MPM_TOL { RETURN "STOWED". }
    IF ABS(a - LAR_MPM_DEPLOY) <= LAR_MPM_TOL { RETURN "DEPLOYED". }
    RETURN "BETWEEN".
}
FUNCTION larMpmBad {                         // the arm may not move while the MPM roll is MOVING: "" it may, else why (starts with LAR_MPM_BAD); a craft without the MPM is never held. STOW / CENTER / DEPLOY / BETWEEN all let the arm move
    IF LAR_MPM:LENGTH = 0 { RETURN "". }
    IF larMpmMode() = "MOVING" { RETURN LAR_MPM_BAD + ": WAIT, THE ROLL STOPS FIRST". }
    RETURN "".
}
FUNCTION larMpmWhy {                         // a go to goal refused: "" it may go, else why. idle = no arm mode is running; jts = the arm's joints (for the STOW rule)
    PARAMETER goal, idle, jts.
    IF LAR_MPM:LENGTH = 0 { RETURN "NO MPM ROLL SERVO ON THIS CRAFT". }
    IF NOT idle { RETURN "THE ARM IS MOVING OR HOLDING A MODE: STOP IT FIRST". }
    IF larMpmMoving() { RETURN "THE MPM IS STILL MOVING". }
    IF goal = LAR_MPM_STOW AND jts:LENGTH > 0 AND NOT larAtStow(jts) { RETURN "THE ARM IS NOT AT ITS STOW POSE (CRADLED)". }
    IF goal > LAR_MPM_STOW AND NOT larBayOpen() { RETURN "THE BAY DOORS ARE CLOSED: OPEN THEM FIRST (12 IS THE MOST WITH THEM CLOSED)". }
    RETURN "".
}
FUNCTION larMpmGo {                          // send the MPM roll to goal (clamped 0..30) at LAR_MPM_RATE deg/s (the servo's own drive does the moving: unlocked, rate, target, one write each); the checks are larMpmWhy's
    PARAMETER goal.
    IF LAR_MPM:LENGTH = 0 { RETURN FALSE. }
    LOCAL g IS larMpmClamp(goal).
    LOCAL md IS LAR_MPM[1].
    LOCAL fr IS larMpmAngle().
    md:SETFIELD(LAR_F_LOCK, FALSE).
    md:SETFIELD("traverse rate", LAR_MPM_RATE).
    md:SETFIELD(LAR_F_TARGET, g).
    SET LAR_MPM_GO TO LIST(fr, g, TIME:SECONDS, ABS(g - fr) / LAR_MPM_RATE + 1).
    RETURN TRUE.
}
FUNCTION larMpmTick {                        // once a pass: the MPM roll locked again once its go is over (a servo left unlocked sags / flexes)
    IF LAR_MPM:LENGTH = 0 { RETURN. }
    IF LAR_MPM_GO[3] > 0 AND NOT larMpmMoving() {
        IF NOT LAR_MPM[1]:GETFIELD(LAR_F_LOCK) { LAR_MPM[1]:SETFIELD(LAR_F_LOCK, TRUE). }
        SET LAR_MPM_GO[3] TO 0.
    }
}

// ---- the joint map -----------------------------------------------------------------------------------------------
FUNCTION larSign {                           // a joint's sign by its name; 0 for a joint the map does not know
    PARAMETER nm.
    IF LAR_SIGN:HASKEY(nm) { RETURN LAR_SIGN[nm]. }
    RETURN 0.
}
FUNCTION larTurnAbout {                      // The signed turn (deg, right-hand about a) that takes v0 to v1, each with its component along a dropped; 0 when one is along a
    PARAMETER a, v0, v1.
    LOCAL u IS a:NORMALIZED.
    LOCAL p0 IS v0 - VDOT(u, v0) * u.
    LOCAL p1 IS v1 - VDOT(u, v1) * u.
    IF p0:MAG < 0.05 OR p1:MAG < 0.05 { RETURN 0. }
    RETURN ARCTAN2(VDOT(u, VCRS(p0, p1)), VDOT(p0, p1)).
}
FUNCTION larJtMeas {                         // A joint's MEASURED angle
    PARAMETER hinge, sg, th0, c1, c2, r1, r2, cmd.   // from its parts' attitudes. hinge TRUE = turns about its part's TOP, else about its FORE; sg = larSign; th0 = the joint angle at the
    // calibration; c1 / r1 = LIST(top, fore) of the servo part in its PARENT's frame at the calibration / now; c2 / r2 = the next part's in the SERVO part's frame (armRel's two
    // lists). Which side the servo turns is not known to the caller: the side that moved more is used (the other stays put). th = th0 + sg x the turn about the axis (the Jacobian's
    // convention: the distal side turns sg x dth about the axis), brought within 180 deg of cmd (the command now). No sign (sg = 0): cmd.
    IF sg = 0 { RETURN cmd. }
    LOCAL k IS CHOOSE 1 IF hinge ELSE 0.     // the vector that sweeps round the axis: a hinge's FORE (axis TOP), a roll's TOP (axis FORE)
    LOCAL d1 IS larTurnAbout(c1[1 - k], c1[k], r1[k]).
    LOCAL a2 IS CHOOSE V(0, 1, 0) IF hinge ELSE V(0, 0, 1).
    LOCAL d2 IS larTurnAbout(a2, c2[k], r2[k]).
    LOCAL d IS CHOOSE d1 IF ABS(d1) >= ABS(d2) ELSE d2.
    LOCAL m IS th0 + sg * d.
    UNTIL m - cmd <= 180 { SET m TO m - 360. }
    UNTIL m - cmd >= -180 { SET m TO m + 360. }
    RETURN m.
}
FUNCTION larAxis {                           // a joint's axis now, a unit vector: its part's TOP (hinge) or FORE (roll)
    PARAMETER j.
    IF j[5] = LAR_HINGE { RETURN j[0]:FACING:TOPVECTOR. }
    RETURN j[0]:FACING:FOREVECTOR.
}
FUNCTION larGeom {                           // the live geometry: LIST(P, LIST(LIST(pivot, axis, sign) a joint each))
    PARAMETER jts, ee.
    LOCAL gs IS LIST().
    FOR j IN jts { gs:ADD(LIST(j[0]:POSITION, larAxis(j), larSign(j[2]))). }
    RETURN LIST(ee:POSITION + LAR_NODE_D * ee:FACING:FOREVECTOR, gs).
}

// ---- the Jacobian -------------------------------------------------------------------------------------------------
FUNCTION larFree {                           // the joints a Jacobian has columns for: every index but the held ones
    PARAMETER n, held.
    LOCAL fr IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        IF NOT held:CONTAINS(i) { fr:ADD(i). }
    }
    RETURN fr.
}
FUNCTION larJacob {                          // 6 rows (vx vy vz wx wy wz), a column per free joint: m / rad and rad / rad
    PARAMETER pp, gs, held.
    LOCAL rows IS LIST(LIST(), LIST(), LIST(), LIST(), LIST(), LIST()).
    FOR i IN larFree(gs:LENGTH, held) {
        LOCAL g IS gs[i].
        LOCAL lin IS g[2] * VCRS(g[1], pp - g[0]).
        LOCAL ang IS g[2] * g[1].
        rows[0]:ADD(lin:X). rows[1]:ADD(lin:Y). rows[2]:ADD(lin:Z).
        rows[3]:ADD(ang:X). rows[4]:ADD(ang:Y). rows[5]:ADD(ang:Z).
    }
    RETURN rows.
}

// ---- the solve ---------------------------------------------------------------------------------------------------
FUNCTION larSolve {                          // A x = b by Gauss with partial pivoting: LIST(x, det A); A is n x n
    PARAMETER a, b.
    LOCAL lu IS larLu(a).
    RETURN LIST(larLuSolve(lu, b), lu[1]).
}
FUNCTION larLu {                             // larSolve's elimination of A alone: LIST(the eliminated rows, det A, per column
    PARAMETER a.                             // LIST(its pivot row, the factors of the rows below)); larLuSolve replays it on a b
    LOCAL n IS a:LENGTH.
    LOCAL m IS LIST().
    FOR rw IN a { m:ADD(rw:COPY). }
    LOCAL det IS 1.
    LOCAL ops IS LIST().
    FROM { LOCAL c IS 0. } UNTIL c >= n STEP { SET c TO c + 1. } DO {
        LOCAL pv IS c.
        FROM { LOCAL i IS c + 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
            IF ABS(m[i][c]) > ABS(m[pv][c]) { SET pv TO i. }
        }
        IF pv <> c {
            LOCAL tmp IS m[c]. SET m[c] TO m[pv]. SET m[pv] TO tmp.
            SET det TO -det.
        }
        LOCAL mc IS m[c].
        LOCAL d IS mc[c].
        SET det TO det * d.
        IF ABS(d) < LAR_TINY { SET d TO LAR_TINY. }
        LOCAL fs IS LIST().
        FROM { LOCAL i IS c + 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
            LOCAL mi IS m[i].
            LOCAL f IS mi[c] / d.
            fs:ADD(f).
            IF f <> 0 {
                FROM { LOCAL k IS c. } UNTIL k >= n STEP { SET k TO k + 1. } DO { SET mi[k] TO mi[k] - f * mc[k]. }
            }
        }
        ops:ADD(LIST(pv, fs)).
    }
    RETURN LIST(m, det, ops).
}
FUNCTION larLuSolve {                        // x for larLu's A and the right side b: the same row operations, then back substitution
    PARAMETER lu, b.
    LOCAL m IS lu[0]. LOCAL ops IS lu[2].
    LOCAL n IS m:LENGTH.
    LOCAL y IS b:COPY.
    FROM { LOCAL c IS 0. } UNTIL c >= n STEP { SET c TO c + 1. } DO {
        LOCAL op IS ops[c].
        LOCAL pv IS op[0].
        IF pv <> c { LOCAL tmp IS y[c]. SET y[c] TO y[pv]. SET y[pv] TO tmp. }
        LOCAL fs IS op[1].
        LOCAL yc IS y[c].
        FROM { LOCAL i IS c + 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
            LOCAL f IS fs[i - c - 1].
            IF f <> 0 { SET y[i] TO y[i] - f * yc. }
        }
    }
    LOCAL x IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO { x:ADD(0). }
    FROM { LOCAL i IS n - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
        LOCAL mi IS m[i].
        LOCAL s IS y[i].
        FROM { LOCAL k IS i + 1. } UNTIL k >= n STEP { SET k TO k + 1. } DO { SET s TO s - mi[k] * x[k]. }
        LOCAL d IS mi[i].
        IF ABS(d) < LAR_TINY { SET d TO LAR_TINY. }
        SET x[i] TO s / d.
    }
    RETURN x.
}
FUNCTION larGram {                           // J J^T + lam2 I (rows x rows): symmetric, each entry's sum in the column order
    PARAMETER jm, lam2.
    LOCAL nr IS jm:LENGTH. LOCAL nc IS jm[0]:LENGTH.
    LOCAL g IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= nr STEP { SET i TO i + 1. } DO {
        LOCAL ri IS jm[i].
        LOCAL rw IS LIST().
        FROM { LOCAL k IS 0. } UNTIL k >= i STEP { SET k TO k + 1. } DO { rw:ADD(g[k][i]). }
        FROM { LOCAL k IS i. } UNTIL k >= nr STEP { SET k TO k + 1. } DO {
            LOCAL rk IS jm[k].
            LOCAL s IS CHOOSE lam2 IF i = k ELSE 0.
            IF nc = 6 { SET s TO s + ri[0] * rk[0] + ri[1] * rk[1] + ri[2] * rk[2] + ri[3] * rk[3] + ri[4] * rk[4] + ri[5] * rk[5]. }
            ELSE { FROM { LOCAL c IS 0. } UNTIL c >= nc STEP { SET c TO c + 1. } DO { SET s TO s + ri[c] * rk[c]. } }
            rw:ADD(s).
        }
        g:ADD(rw).
    }
    RETURN g.
}
GLOBAL LAR_LU_J IS 0.                        // the Jacobian larManip last eliminated J J^T for, and its larLu: the same tick's
GLOBAL LAR_LU IS 0.                          // larDls with no damping (lam2 0: the same matrix) replays it instead of a second solve
FUNCTION larDls {                            // the joint rates (rad/s, one per column) for the task rates v: J^T (J J^T + lam2 I)^-1 v
    PARAMETER jm, vw, lam2.
    LOCAL y IS 0.
    IF lam2 = 0 AND LAR_LU_J = jm { SET y TO larLuSolve(LAR_LU, vw). }
    ELSE { SET y TO larSolve(larGram(jm, lam2), vw)[0]. }
    LOCAL dq IS LIST().
    LOCAL nr IS jm:LENGTH.
    FROM { LOCAL c IS 0. } UNTIL c >= jm[0]:LENGTH STEP { SET c TO c + 1. } DO {
        LOCAL s IS 0.
        IF nr = 6 { SET s TO s + jm[0][c] * y[0] + jm[1][c] * y[1] + jm[2][c] * y[2] + jm[3][c] * y[3] + jm[4][c] * y[4] + jm[5][c] * y[5]. }
        ELSE { FROM { LOCAL i IS 0. } UNTIL i >= nr STEP { SET i TO i + 1. } DO { SET s TO s + jm[i][c] * y[i]. } }
        dq:ADD(s).
    }
    RETURN dq.
}
FUNCTION larManip {                          // the manipulability sqrt(det(J J^T)): 0 at a singularity
    PARAMETER jm.
    LOCAL lu IS larLu(larGram(jm, 0)).
    SET LAR_LU_J TO jm. SET LAR_LU TO lu.
    RETURN SQRT(MAX(lu[1], 0)).
}
FUNCTION larLam2 {                           // the damping: 0 at or above w0, lam0^2 (1 - w/w0)^2 below it (Nakamura-Hanafusa)
    PARAMETER w, w0, lam0.
    IF w >= w0 { RETURN 0. }
    RETURN lam0 * lam0 * (1 - w / w0) * (1 - w / w0).
}

// ---- the autostrut (ARM-AS) ---------------------------------------------------------------------------------------
FUNCTION larAsWhy {                          // "" when KalsCoproc's ASTRUT is there, else why not
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN "no KAL/S addon". }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN "the KAL/S addon is not available". }
    IF NOT ADDONS:KALS:HASSUFFIX("ASTRUT") { RETURN "an older KalsCoproc.dll". }
    RETURN "".
}
FUNCTION larArmParts {                       // one arm's parts: the end effector, then its parents up to the shoulder's servo
    PARAMETER ee, jts.
    LOCAL ps IS LIST(ee).
    IF jts:LENGTH = 0 { RETURN ps. }
    LOCAL top IS jts[0][0]:UID.
    LOCAL pq IS ee.
    UNTIL pq:UID = top OR NOT pq:HASPARENT {
        SET pq TO pq:PARENT.
        ps:ADD(pq).
    }
    RETURN ps.
}
FUNCTION larAsLaunch {                       // the parts autostrutted for launch: the end effector and the elbow
    PARAMETER ee, jts.
    LOCAL ps IS LIST(ee).
    FOR j IN jts { IF j[2] = "ELBOW PITCH" { ps:ADD(j[0]). } }
    RETURN ps.
}
FUNCTION larAsOff {                          // every part's autostrut OFF: LIST(how many were on, how many are still on, what changed)
    PARAMETER ps.
    LOCAL nOn IS 0. LOCAL nLeft IS 0. LOCAL s IS "".
    FOR pt IN ps {
        LOCAL m IS ADDONS:KALS:ASTRUT(pt, "").
        IF m <> "Off" {
            IF NOT m:STARTSWITH("ERROR") { SET LAR_AS_WAS[pt:UID] TO m. }
            LOCAL m2 IS ADDONS:KALS:ASTRUT(pt, "Off").
            SET nOn TO nOn + 1.
            IF m2 <> "Off" { SET nLeft TO nLeft + 1. }
            SET s TO s + " " + pt:NAME + " " + m + " -> " + m2 + ";".
        }
    }
    RETURN LIST(nOn, nLeft, s).
}
FUNCTION larStowOff {                        // the largest |target - stow| over the joints (deg); -1 for a joint LAR_STOW lacks
    PARAMETER names, targets.
    LOCAL w IS 0.
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        IF NOT LAR_STOW:HASKEY(names[i]) { RETURN -1. }
        SET w TO MAX(w, ABS(targets[i] - LAR_STOW[names[i]])).
    }
    RETURN w.
}
FUNCTION larAtStow {                         // every joint's 'target angle' at its stow angle
    PARAMETER jts.
    LOCAL nm IS LIST(). LOCAL tg IS LIST().
    FOR j IN jts { nm:ADD(j[2]). tg:ADD(j[1]:GETFIELD(LAR_F_TARGET)). }
    LOCAL w IS larStowOff(nm, tg).
    RETURN jts:LENGTH > 0 AND w >= 0 AND w <= LAR_STOW_TOL.
}
FUNCTION larAsStow {                         // at the stow pose the autostrut back ON: what was done, as text
    PARAMETER ee, jts.
    IF NOT larAtStow(jts) { RETURN "autostrut left OFF (the arm is not at the stow pose)". }
    LOCAL s IS "".
    LOCAL done IS LEXICON().
    FOR pt IN larAsLaunch(ee, jts) {         // the launch parts: the mode they had, else LAR_AS_ON
        LOCAL m IS LAR_AS_ON.
        IF LAR_AS_WAS:HASKEY(pt:UID) { SET m TO LAR_AS_WAS[pt:UID]. }
        SET s TO s + " " + pt:NAME + " " + ADDONS:KALS:ASTRUT(pt, m) + ";".
        SET done[pt:UID] TO TRUE.
    }
    FOR pt IN larArmParts(ee, jts) {         // every other arm part larAsOff found ON (the booms' retention latches ...)
        IF NOT done:HASKEY(pt:UID) AND LAR_AS_WAS:HASKEY(pt:UID) {
            SET s TO s + " " + pt:NAME + " " + ADDONS:KALS:ASTRUT(pt, LAR_AS_WAS[pt:UID]) + ";".
        }
    }
    RETURN "stowed, autostrut ON:" + s.
}

// ---- MANUAL AUG ----------------------------------------------------------------------------------------------
FUNCTION larThcPick {                        // the THC arm.ks reads = V(starboard, top, fore), kOS's PILOT* signs
    PARAMETER pil, xp, live.                 // pil = V(SHIP:CONTROL:PILOTSTARBOARD, PILOTTOP, PILOTFORE): the keyboard THC only
    IF NOT live { RETURN pil. }              // (kOS's PILOT* are FlightInputHandler.state: Advanced Fly-By-Wire adds its X / Y / Z
    LOCAL a IS LIST(pil:X, pil:Y, pil:Z).    // into the vessel's final FlightCtrlState inside OnFlyByWire, never into that state).
    LOCAL o IS LIST(0, 0, 0).                // live = FBWXOFF answered this tick: xp = ADDONS:KALS:FBWXPILOT() = the translation
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {   // the handler was handed = keyboard + AFBW, the total. Per
        SET o[i] TO a[i].                    // axis the larger magnitude (FBWXPILOT is 0 until the handler has run once after the
        IF ABS(xp[i]) >= ABS(a[i]) { SET o[i] TO xp[i]. }   // first FBWXOFF; the keyboard value then still counts)
    }
    RETURN V(o[0], o[1], o[2]).
}
FUNCTION larThcVel {                         // the THC (V(starboard, top, fore) inputs) -> the node's velocity, the orbiter's frame
    PARAMETER thc, spd, db.
    LOCAL c IS LIST(thc:X, thc:Y, thc:Z).
    LOCAL sg IS LIST(LAR_THC_SIGN:X, LAR_THC_SIGN:Y, LAR_THC_SIGN:Z).
    LOCAL o IS LIST(0, 0, 0).
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        IF c[i] > db { SET o[i] TO spd * sg[i]. }
        IF c[i] < -db { SET o[i] TO -spd * sg[i]. }
    }
    RETURN V(o[0], o[1], o[2]).
}
FUNCTION larAttErr {                         // the turn (rad, a vector, VCRS sense) that takes the frame (f, t) to (fR, tR):
    PARAMETER f, t, fR, tR.                  // half the sum of e x e' over the three axes = sin(angle) x the axis (the
    RETURN 0.5 * (VCRS(f, fR) + VCRS(t, tR) + VCRS(VCRS(t, f), VCRS(tR, fR))).   // third axis added; f and t alone gave half
}
FUNCTION larAugTask {                        // the 6 task rates: the commanded velocity and turn + the pulls back to the reference
    PARAMETER vc, eP, eW, wc.
    LOCAL lv IS vc + LAR_K_POS * eP.
    LOCAL aw IS wc + LAR_K_ATT * eW.
    RETURN LIST(lv:X, lv:Y, lv:Z, aw:X, aw:Y, aw:Z).
}
FUNCTION larAugRates {                       // the joint rates (deg/s, a column each) for a task: LIST(rates, the scale applied)
    PARAMETER jm, task, lam2, cap.
    LOCAL dq IS larDls(jm, task, lam2).
    LOCAL mx IS 0.
    FROM { LOCAL i IS 0. } UNTIL i >= dq:LENGTH STEP { SET i TO i + 1. } DO {
        SET dq[i] TO dq[i] / LAR_D2R.
        SET mx TO MAX(mx, ABS(dq[i])).
    }
    LOCAL sc IS 1.
    IF mx > cap { SET sc TO cap / mx. }
    FROM { LOCAL i IS 0. } UNTIL i >= dq:LENGTH STEP { SET i TO i + 1. } DO { SET dq[i] TO dq[i] * sc. }
    RETURN LIST(dq, sc).
}
FUNCTION larSoftHit {                        // the first joint the rates drive into its soft stop (-1: none); the ends LAR_RANGE less LAR_SOFT
    PARAMETER names, targets, rates.
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        IF LAR_RANGE:HASKEY(names[i]) {
            LOCAL rg IS LAR_RANGE[names[i]].
            IF rates[i] > 0 AND targets[i] >= rg[1] - LAR_SOFT { RETURN i. }
            IF rates[i] < 0 AND targets[i] <= rg[0] + LAR_SOFT { RETURN i. }
        }
    }
    RETURN -1.
}
// ----. A joint that the rates drive
// into its soft stop is now held ALONE and the others solved again (the held joint's column left out of the Jacobian, more joints held as they
// hit theirs); that motion is flown only when it is FAITHFUL (what the arm gives is what the unheld solve would have given, +-30 % and a small
// absolute slack): else the move part alone, else the turn part alone, else nothing (BLOCKED), and NEVER a latch: the next pass solves afresh.
GLOBAL LAR_SOFT_LAM2 IS 0.01.                // damping floor of a solve with joints held (J J^T has lost rank: lam2 0 would divide by ~0)
GLOBAL LAR_SOFT_TOL IS 0.3.                  // share of the asked motion the held solve may miss and still be flown
GLOBAL LAR_SOFT_ABS_V IS 0.005.              // m/s slack on that
GLOBAL LAR_SOFT_ABS_W IS 0.01.               // rad/s slack on that
FUNCTION larSoftAt {                         // one solve with the soft-stopped joints held out: LIST(rates a column each (deg/s), scale, held (the column indexes), the first solve's scale)
    PARAMETER jm, names, targets, vc, eP, eW, wc, rr, lam2, cap.
    LOCAL nj IS names:LENGTH.
    LOCAL held IS LIST().
    LOCAL dq IS LIST().
    LOCAL sc IS 1.
    LOCAL sc0 IS 1.
    LOCAL task IS larPorTask(vc, eP, eW, wc, rr).
    LOCAL pass IS 0.
    UNTIL FALSE {
        LOCAL fr IS larFree(nj, held).
        SET dq TO LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= nj STEP { SET i TO i + 1. } DO { dq:ADD(0). }
        IF fr:LENGTH = 0 { SET sc TO 1. BREAK. }
        LOCAL j2 IS jm.
        LOCAL lm IS lam2.
        IF held:LENGTH > 0 {
            SET j2 TO LIST(LIST(), LIST(), LIST(), LIST(), LIST(), LIST()).
            FOR c IN fr {
                FROM { LOCAL rw IS 0. } UNTIL rw >= 6 STEP { SET rw TO rw + 1. } DO { j2[rw]:ADD(jm[rw][c]). }
            }
            SET lm TO MAX(lam2, LAR_SOFT_LAM2).
        }
        LOCAL res IS larAugRates(j2, task, lm, cap).
        SET sc TO res[1].
        IF pass = 0 { SET sc0 TO sc. }
        FROM { LOCAL c IS 0. } UNTIL c >= fr:LENGTH STEP { SET c TO c + 1. } DO { SET dq[fr[c]] TO res[0][c]. }
        LOCAL hit IS larSoftHit(names, targets, dq).
        IF hit < 0 { BREAK. }
        held:ADD(hit).
        SET pass TO pass + 1.
    }
    RETURN LIST(dq, sc, held, sc0).
}
FUNCTION larSoftOk {                         // the held solve's motion (the rates at jm's columns) against what the unheld one would have given: TRUE = flown
    PARAMETER jm, sol, vc, wc.
    LOCAL lin IS V(0, 0, 0).
    LOCAL ang IS V(0, 0, 0).
    FROM { LOCAL c IS 0. } UNTIL c >= sol[0]:LENGTH STEP { SET c TO c + 1. } DO {
        LOCAL qr IS sol[0][c] * LAR_D2R.
        SET lin TO lin + V(jm[0][c], jm[1][c], jm[2][c]) * qr.
        SET ang TO ang + V(jm[3][c], jm[4][c], jm[5][c]) * qr.
    }
    LOCAL s0 IS sol[3].
    IF (lin - vc * s0):MAG > LAR_SOFT_TOL * s0 * vc:MAG + LAR_SOFT_ABS_V { RETURN FALSE. }
    IF (ang - wc * s0):MAG > LAR_SOFT_TOL * s0 * wc:MAG + LAR_SOFT_ABS_W { RETURN FALSE. }
    RETURN TRUE.
}
FUNCTION larAugSoft {                        // MAN AUG's rates with soft stops handled per joint: LIST(rates, scale, the held joints' columns, the mode)
    PARAMETER jm, names, targets, vc, eP, eW, wc, rr, lam2, cap.      // mode: "" none held, "SLIDE" the whole ask flown on the free joints,
    LOCAL a IS larSoftAt(jm, names, targets, vc, eP, eW, wc, rr, lam2, cap).   // "MOVE ONLY" / "TURN ONLY" one part of it, "BLOCKED" nothing
    IF a[2]:LENGTH = 0 { RETURN LIST(a[0], a[1], a[2], ""). }
    IF larSoftOk(jm, a, vc, wc) { RETURN LIST(a[0], a[1], a[2], "SLIDE"). }
    IF vc:MAG > 0 AND wc:MAG > 0 {
        LOCAL zv IS V(0, 0, 0).
        LOCAL b IS larSoftAt(jm, names, targets, vc, eP, eW, zv, rr, lam2, cap).
        IF larSoftOk(jm, b, vc, zv) { RETURN LIST(b[0], b[1], a[2], "MOVE ONLY"). }   // a[2]: the joints that blocked the whole ask (the words name them)
        SET b TO larSoftAt(jm, names, targets, zv, eP, eW, wc, rr, lam2, cap).
        IF larSoftOk(jm, b, zv, wc) { RETURN LIST(b[0], b[1], a[2], "TURN ONLY"). }
    }
    LOCAL z IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO { z:ADD(0). }
    RETURN LIST(z, 1, a[2], "BLOCKED").
}
FUNCTION larModelBad {                       // the node's measured move misses the asked-for one (both m, one frame); qAl (m) the
    PARAMETER asked, got, qAl IS 0.          // steps' share (larQuant)
    IF asked:MAG < LAR_MODEL_MIN { RETURN FALSE. }
    RETURN (got - asked):MAG > LAR_MODEL_TOL * asked:MAG + LAR_MODEL_ABS + qAl.
}
FUNCTION larModelBadW {                      // the end effector's measured turn misses the asked-for one (both rad vectors); qAl (rad)
    PARAMETER asked, got, qAl IS 0.
    IF asked:MAG < LAR_MODEL_WMIN * LAR_D2R { RETURN FALSE. }
    RETURN (got - asked):MAG > LAR_MODEL_TOL * asked:MAG + LAR_MODEL_WABS * LAR_D2R + qAl.
}
FUNCTION larQuant {                          // what the whole-degree steps can hide in a model window: LIST(m at the node, rad of
    PARAMETER jm.                            // turn), every free joint LAR_Q_K steps off its command (its column's size x that)
    LOCAL ql IS 0. LOCAL qa IS 0.
    FROM { LOCAL c IS 0. } UNTIL c >= jm[0]:LENGTH STEP { SET c TO c + 1. } DO {
        SET ql TO ql + V(jm[0][c], jm[1][c], jm[2][c]):MAG.
        SET qa TO qa + V(jm[3][c], jm[4][c], jm[5][c]):MAG.
    }
    LOCAL k IS LAR_QSTEP * LAR_Q_K * LAR_D2R.
    RETURN LIST(ql * k, qa * k).
}
GLOBAL LAR_QR_J IS 0. GLOBAL LAR_QR IS 0.   // the Jacobian larQRes last summed, and its sums (one tick asks up to 3 times; LAR_QSTEP read each call)
FUNCTION larQRes {                           // the arm's resolution at the node: LIST(m, deg) = half of one step on every free joint
    PARAMETER jm.                            // (root sum square: the nearest whole-degree pose), what OPR CMD and CAPTURE can reach
    IF NOT (LAR_QR_J = jm) {                 // kOS's = on two lists: the same list
        LOCAL sl IS 0. LOCAL sa IS 0.
        FROM { LOCAL c IS 0. } UNTIL c >= jm[0]:LENGTH STEP { SET c TO c + 1. } DO {
            LOCAL cl IS V(jm[0][c], jm[1][c], jm[2][c]). LOCAL ca IS V(jm[3][c], jm[4][c], jm[5][c]).
            SET sl TO sl + VDOT(cl, cl). SET sa TO sa + VDOT(ca, ca).
        }
        SET LAR_QR_J TO jm. SET LAR_QR TO LIST(sl, sa).
    }
    RETURN LIST(0.5 * LAR_QSTEP * LAR_D2R * SQRT(LAR_QR[0]), 0.5 * LAR_QSTEP * SQRT(LAR_QR[1])).
}
FUNCTION larModelDue {                       // the model window is judged now: past win s with the ask clear of what the steps hide
    PARAMETER dtw, win, askL, askA, qAl.     // (twice larQuant's qAl + the absolute tolerance), or at LAR_MODEL_WMAX
    IF dtw >= LAR_MODEL_WMAX { RETURN TRUE. }
    IF dtw < win { RETURN FALSE. }
    RETURN askL:MAG >= 2 * (LAR_MODEL_ABS + qAl[0]) OR askA:MAG >= 2 * (LAR_MODEL_WABS * LAR_D2R + qAl[1]).
}
FUNCTION larStallAl {                        // deg a joint driven at rate (deg/s) may trail its command: ARM's stall margin st +
    PARAMETER rate, st.                      // the rate's own lag + half a whole-degree step on the kOS path
    RETURN st + ABS(rate) * LAR_LAG_T + (CHOOSE 0 IF LAR_DRV ELSE 0.5 * LAR_QSTEP) + (CHOOSE LAR_LD_AL IF LAR_LDON ELSE 0).
}
FUNCTION larStallTick {                      // the stall timer: LIST(t0, stalled): t0 the time the lag first passed its allowance
    PARAMETER st, over, tn.                  // (-1: not past), stalled once past it LAR_STALL_T (a lag that only touches
    IF NOT over { RETURN LIST(-1, FALSE). }  // the allowance, as the whole-degree steps make it, is no stall)
    IF st[0] < 0 { RETURN LIST(tn, FALSE). }
    RETURN LIST(st[0], tn - st[0] >= (CHOOSE LAR_STALL_T_LD IF LAR_LDON ELSE LAR_STALL_T)).
}
FUNCTION larSmooth {                         // one tick of the two-stage smoothing of a command x (a vector): LIST(stage 1, stage 2)
    PARAMETER sm, x, dt, tau.                // the flown command = stage 2 (continuous, its rate too); exact for a held x
    LOCAL a IS CHOOSE 0 IF tau <= 0 ELSE 2.71828182845905 ^ (-dt / tau).
    LOCAL s1 IS x + (sm[0] - x) * a.
    RETURN LIST(s1, s1 + (sm[1] - s1) * a).
}
FUNCTION larSingWhy {                        // which singularity the pose is near (SINGULAR's reason): names / targets (deg)
    PARAMETER names, tgs.
    LOCAL ep IS names:INDEXOF("ELBOW PITCH"). LOCAL wy IS names:INDEXOF("WRIST YAW").
    IF ep >= 0 AND (tgs[ep] > -10 OR tgs[ep] < -170) { RETURN "ELBOW " + (CHOOSE "STRAIGHT" IF tgs[ep] > -10 ELSE "FOLDED"). }
    IF wy >= 0 AND ABS(ABS(tgs[wy]) - 90) < 15 { RETURN "WRIST (PITCH AND ROLL IN LINE)". }
    RETURN "SHOULDER (THE WRIST OVER THE SHOULDER YAW AXIS)".
}
FUNCTION larCmdStep {                        // the joints' running commands (deg) moved on by the rates rt (deg/s) x dt: kept here,
    PARAMETER cm, rt, dt.                    // never read back from the field (kOS rounds it to LAR_QSTEP)
    FROM { LOCAL c IS 0. } UNTIL c >= cm:LENGTH STEP { SET c TO c + 1. } DO { SET cm[c] TO cm[c] + rt[c] * dt. }
    RETURN cm.
}

// ---- rotation and the END EFF frame ---------------------------------------------------------------------------
FUNCTION larRhcRate {                        // the RHC (V(pitch, yaw, roll) inputs) -> the turn rate (rad/s, VCRS sense), ORB UNL's
    PARAMETER rhc, wspd, db.                 // (star, top, fore) components; wspd deg/s
    LOCAL c IS LIST(rhc:X, rhc:Y, rhc:Z).
    LOCAL sg IS LIST(LAR_RHC_SIGN:X, LAR_RHC_SIGN:Y, LAR_RHC_SIGN:Z).
    LOCAL o IS LIST(0, 0, 0).
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        IF c[i] > db { SET o[i] TO wspd * LAR_D2R * sg[i]. }
        IF c[i] < -db { SET o[i] TO -wspd * LAR_D2R * sg[i]. }
    }
    RETURN V(o[0], o[1], o[2]).
}
FUNCTION larThcRot {                         // TRANS / ROT at ROT: the THC (V(starboard, top, fore)) as the RHC's V(pitch, yaw, roll):
    PARAMETER thc.                           // I (top -1) pitch up, L (starboard +1) yaw right, H (fore +1) roll right
    RETURN V(-thc:Y, thc:X, thc:Z).
}
FUNCTION larCmdAxes {                        // a frame's axes for ORB UNL's components (star, top, fore), as vectors: ORB UNL the
    PARAMETER ee, s, t, f.                   // orbiter's (s, t, f); END EFF (ee TRUE) the LEE's turned 180 deg about its top, so the
    IF ee { RETURN LIST(-s, t, -f). }        // aft view's forward / right / up become the LEE's FORE / STAR / TOP
    RETURN LIST(s, t, f).
}
FUNCTION larCmdOut {                         // the components c on the axes ax (larCmdAxes)
    PARAMETER c, ax.
    RETURN ax[0] * c:X + ax[1] * c:Y + ax[2] * c:Z.
}
FUNCTION larTurnVec {                        // vec turned by the turn vector w (rad: the axis, its size the angle; VCRS sense)
    PARAMETER vec, w.
    LOCAL a IS w:MAG.
    IF a < LAR_TINY { RETURN vec. }
    LOCAL k IS w / a.
    LOCAL ad IS a / LAR_D2R.
    RETURN vec * COS(ad) + VCRS(k, vec) * SIN(ad) + k * (VDOT(k, vec) * (1 - COS(ad))).
}
FUNCTION larAugRef {                         // the reference kept near the end effector: LIST(pRef, fRef, tRef, eP, eW); the
    PARAMETER pRef, fRef, tRef, pNow, fNow, tNow, turning.   // position on LAR_REF_MAX, the attitude on LAR_REF_ANG while turning
    LOCAL eP IS pRef - pNow.
    IF eP:MAG > LAR_REF_MAX { SET pRef TO pNow + eP:NORMALIZED * LAR_REF_MAX. SET eP TO pRef - pNow. }
    LOCAL eW IS larAttErr(fNow, tNow, fRef, tRef).
    IF turning AND eW:MAG > SIN(LAR_REF_ANG) {
        LOCAL k IS eW:NORMALIZED * (LAR_REF_ANG * LAR_D2R).
        SET fRef TO larTurnVec(fNow, k). SET tRef TO larTurnVec(tNow, k).
        SET eW TO larAttErr(fNow, tNow, fRef, tRef).
    }
    RETURN LIST(pRef, fRef, tRef, eP, eW).
}
FUNCTION larAugStep {                        // the reference moved on by the command over dt (after the solve): LIST(pRef, fRef, tRef)
    PARAMETER pRef, fRef, tRef, vc, wc, dt.
    RETURN LIST(pRef + vc * dt, larTurnVec(fRef, wc * dt), larTurnVec(tRef, wc * dt)).
}

// ---- the stick and the torque -------------------------------------------------------------------------------
FUNCTION larOmsEng {                         // LIST(the OMS engine whose gimbal reads the stick), or LIST(): by name AJ10, else by
    FOR en IN SHIP:ENGINES {                 // title as lib_dap's dapInit (css-dap-mechanics 1)
        IF en:HASGIMBAL AND (en:NAME:CONTAINS("AJ10") OR en:TITLE:CONTAINS("Manoeuvring") OR en:TITLE:CONTAINS("Maneuvering")
                             OR en:TITLE:CONTAINS("Viking")) { RETURN LIST(en). }
    }
    RETURN LIST().
}
FUNCTION larTorqueOff {                      // every reaction wheel's authority to 0: LIST(wheels, wheels still able to turn, text)
    LOCAL n IS 0. LOCAL nLeft IS 0. LOCAL s IS "".
    FOR m IN SHIP:MODULESNAMED("ModuleReactionWheel") {
        SET n TO n + 1.
        IF m:HASFIELD(LAR_F_WHEEL) {
            LOCAL a0 IS m:GETFIELD(LAR_F_WHEEL).
            IF a0 <> 0 {
                LAR_TQ_WAS:ADD(LIST(m, a0)).
                m:SETFIELD(LAR_F_WHEEL, 0).
            }
            LOCAL a1 IS m:GETFIELD(LAR_F_WHEEL).
            IF a1 <> 0 { SET nLeft TO nLeft + 1. }
            SET s TO s + " " + m:PART:NAME + " " + ROUND(a0, 1) + " -> " + ROUND(a1, 1) + ";".
        } ELSE {
            SET nLeft TO nLeft + 1.
            SET s TO s + " " + m:PART:NAME + " has no '" + LAR_F_WHEEL + "' (" + m:ALLFIELDNAMES:JOIN(", ") + ");".
        }
    }
    RETURN LIST(n, nLeft, s).
}
FUNCTION larTorqueBack {                     // every wheel larTorqueOff turned to 0 back to its authority: what was done, as text
    LOCAL s IS "".
    FOR w IN LAR_TQ_WAS {
        w[0]:SETFIELD(LAR_F_WHEEL, w[1]).
        SET s TO s + " " + w[0]:PART:NAME + " " + ROUND(w[1], 1) + ";".
    }
    LAR_TQ_WAS:CLEAR().
    RETURN s.
}

// ---- AUTO: stored poses in joint space -------------------------------------------------------------------------
FUNCTION larPosesLoad {                      // LEXICON("poses", name -> pose, "seqs", AUTO n -> pose names, "user", the file's
    PARAMETER fpath.                         // pose names in order, "own", the sequences it replaced): the built-ins and the
                                             // defaults, with the file's on top
    LOCAL ps IS LEXICON("STOW", LAR_STOW, "PRE-CRADLE", LAR_PRE_CRADLE, "READY", LAR_READY).
    LOCAL sq IS LEXICON().
    FOR k IN LAR_AUTO_SEQ:KEYS { sq:ADD(k, LAR_AUTO_SEQ[k]:COPY). }
    LOCAL us IS LIST(). LOCAL own IS LIST().
    IF EXISTS(fpath) {
        LOCAL fl IS READJSON(fpath).
        IF fl:ISTYPE("Lexicon") AND fl:HASKEY("poses") AND fl["poses"]:ISTYPE("Lexicon") {
            FOR k IN fl["poses"]:KEYS {
                IF NOT LAR_BUILT_IN:CONTAINS(k) AND fl["poses"][k]:ISTYPE("Lexicon") { SET ps[k] TO fl["poses"][k]. us:ADD(k). }
            }
        }
        IF fl:ISTYPE("Lexicon") AND fl:HASKEY("seqs") AND fl["seqs"]:ISTYPE("Lexicon") {
            FOR k IN fl["seqs"]:KEYS {
                IF sq:HASKEY(k) AND fl["seqs"][k]:ISTYPE("List") { SET sq[k] TO fl["seqs"][k]:COPY. own:ADD(k). }
            }
        }
    }
    RETURN LEXICON("poses", ps, "seqs", sq, "user", us, "own", own).
}
FUNCTION larPoseSave {                       // the targets saved as the next free "POSE n" (and added to the sequence seq unless
    PARAMETER fpath, names, tgs, seq.        // ""): the pose's name
    LOCAL fl IS LEXICON("poses", LEXICON(), "seqs", LEXICON()).
    IF EXISTS(fpath) {
        LOCAL f0 IS READJSON(fpath).
        IF f0:ISTYPE("Lexicon") {
            SET fl TO f0.
            IF NOT (fl:HASKEY("poses") AND fl["poses"]:ISTYPE("Lexicon")) { SET fl["poses"] TO LEXICON(). }
            IF NOT (fl:HASKEY("seqs") AND fl["seqs"]:ISTYPE("Lexicon")) { SET fl["seqs"] TO LEXICON(). }
        }
    }
    LOCAL n IS 1.
    UNTIL NOT fl["poses"]:HASKEY("POSE " + n) { SET n TO n + 1. }
    LOCAL nm IS "POSE " + n.
    LOCAL pz IS LEXICON().
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO { SET pz[names[i]] TO ROUND(tgs[i], 2). }
    SET fl["poses"][nm] TO pz.
    IF seq <> "" {
        IF NOT (fl["seqs"]:HASKEY(seq) AND fl["seqs"][seq]:ISTYPE("List")) {
            SET fl["seqs"][seq] TO CHOOSE LAR_AUTO_SEQ[seq]:COPY IF LAR_AUTO_SEQ:HASKEY(seq) ELSE LIST().
        }
        fl["seqs"][seq]:ADD(nm).
    }
    WRITEJSON(fl, fpath).
    RETURN nm.
}
FUNCTION larPoseTargets {                    // a pose's targets for the joints names: the pose's angle, else the current one
    PARAMETER names, cur, pose.
    LOCAL out IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        out:ADD(CHOOSE pose[names[i]] IF pose:HASKEY(names[i]) ELSE cur[i]).
    }
    RETURN out.
}
FUNCTION larPoseBad {                        // the first joint past its soft stop as text ("" none); a joint at its stow angle passes
    PARAMETER names, tgs.
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        IF LAR_RANGE:HASKEY(names[i]) {
            LOCAL rg IS LAR_RANGE[names[i]].
            LOCAL atStow IS LAR_STOW:HASKEY(names[i]) AND ABS(tgs[i] - LAR_STOW[names[i]]) <= LAR_STOW_TOL.
            IF NOT atStow AND (tgs[i] < rg[0] + LAR_SOFT OR tgs[i] > rg[1] - LAR_SOFT) { RETURN names[i] + " " + ROUND(tgs[i], 1). }
        }
    }
    RETURN "".
}
FUNCTION larSoftWords {                     // A joint's typed range past the soft stops, in words: ELBOW PITCH: -175 TO -5 ONLY (SOFT STOP)
    PARAMETER nm.
    LOCAL rg IS LAR_RANGE[nm].
    RETURN nm + ": " + ROUND(rg[0] + LAR_SOFT, 0) + " TO " + ROUND(rg[1] - LAR_SOFT, 0) + " ONLY (SOFT STOP)".
}
FUNCTION larFolded {                         // the elbow at or below LAR_AUG_ELBOW: the arm on its cradle side
    PARAMETER names, tgs.
    LOCAL i IS names:INDEXOF("ELBOW PITCH").
    RETURN i >= 0 AND tgs[i] <= LAR_AUG_ELBOW.
}
FUNCTION larPoseOff {                        // the largest |a - b| over the joints, deg
    PARAMETER a, b.
    LOCAL w IS 0.
    FROM { LOCAL i IS 0. } UNTIL i >= a:LENGTH STEP { SET i TO i + 1. } DO { SET w TO MAX(w, ABS(a[i] - b[i])). }
    RETURN w.
}
FUNCTION larSafePath {                       // a sequence of pose names -> LIST(legs, why): each leg LIST(name, targets, vernier);
    PARAMETER names, cur, wps, poses.        // why "" or the reason none is flown. A folded arm leaves through PRE-CRADLE and
    LOCAL tg IS cur.                         // READY; STOW and PRE-CRADLE are reached from READY; the cradle legs at VERNIER
    LOCAL at IS "".
    FOR b IN LAR_BUILT_IN {
        IF larPoseOff(larPoseTargets(names, cur, poses[b]), cur) <= LAR_POSE_SAME { SET at TO b. }
    }
    LOCAL aLegs IS LIST().
    FOR w IN wps {
        IF NOT poses:HASKEY(w) { RETURN LIST(LIST(), "UNKNOWN POSE " + w). }
        LOCAL bad IS larPoseBad(names, larPoseTargets(names, cur, poses[w])).
        IF bad <> "" { RETURN LIST(LIST(), w + ": " + bad + " PAST ITS SOFT STOP"). }
        LOCAL fd IS larFolded(names, tg).
        LOCAL via IS LIST().
        IF w = "STOW" OR w = "PRE-CRADLE" {
            IF at <> "STOW" AND at <> "PRE-CRADLE" {
                IF NOT fd AND at <> "READY" { via:ADD("READY"). }
                IF w = "STOW" { via:ADD("PRE-CRADLE"). }
            }
        } ELSE IF fd {
            IF at <> "PRE-CRADLE" { via:ADD("PRE-CRADLE"). }
            IF w <> "READY" { via:ADD("READY"). }
        }
        via:ADD(w).
        FOR nm IN via {
            LOCAL t2 IS larPoseTargets(names, tg, poses[nm]).
            IF larPoseOff(t2, tg) > LAR_POSE_SAME { aLegs:ADD(LIST(nm, t2, nm = "STOW" OR at = "STOW")). }
            SET tg TO t2.
            SET at TO CHOOSE nm IF LAR_BUILT_IN:CONTAINS(nm) ELSE "".
        }
    }
    RETURN LIST(aLegs, "").
}
FUNCTION larMoveT {                          // a leg's time (s): its largest joint change at rate deg/s
    PARAMETER a, b, rate.
    RETURN larPoseOff(a, b) / rate.
}
FUNCTION larMoveAt {                         // the targets a share s (0-1) along the straight joint-space line a -> b
    PARAMETER a, b, s.
    LOCAL out IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= a:LENGTH STEP { SET i TO i + 1. } DO { out:ADD(a[i] + (b[i] - a[i]) * s). }
    RETURN out.
}
FUNCTION larLegBehind {                      // the last moving joint (mv: indexes) whose target runs more than tol deg ahead of
    PARAMETER mv, tgs, a0, turned, tol.      // its measured turn since the leg's start (turned, a joint each), or -1
    LOCAL bh IS -1.
    FOR i IN mv { IF ABS(tgs[i] - a0[i]) - turned[i] > tol { SET bh TO i. } }
    RETURN bh.
}
FUNCTION larFkNode {                         // the node after the joint changes dq (deg) from the geometry gs (larGeom's, one
    PARAMETER gs, pp, dq, flip.              // frame) and node pp, each joint turning by its sign (joint flip's negated; -1 none)
    LOCAL ps IS LIST(). LOCAL ks IS LIST().
    FOR g IN gs { ps:ADD(g[0]). ks:ADD(g[1]). }
    LOCAL nd IS pp.
    FROM { LOCAL i IS 0. } UNTIL i >= gs:LENGTH STEP { SET i TO i + 1. } DO {
        IF dq[i] <> 0 {
            LOCAL w IS ks[i] * ((CHOOSE -1 IF i = flip ELSE 1) * gs[i][2] * dq[i] * LAR_D2R).
            FROM { LOCAL j IS i + 1. } UNTIL j >= gs:LENGTH STEP { SET j TO j + 1. } DO {
                SET ps[j] TO ps[i] + larTurnVec(ps[j] - ps[i], w).
                SET ks[j] TO larTurnVec(ks[j], w).
            }
            SET nd TO ps[i] + larTurnVec(nd - ps[i], w).
        }
    }
    RETURN nd.
}
FUNCTION larFkBad {                          // the measured node misses the predicted one (LAR_FK_TOL + LAR_FK_SHARE x the move)
    PARAMETER p0, pred, got.
    RETURN (got - pred):MAG > LAR_FK_TOL + LAR_FK_SHARE * (pred - p0):MAG.
}

// ---- GRAPPLE -------------------------------------------------------------------------------------------------------
FUNCTION larFixtures {                       // the fixtures, the nearest to the node pN first: the target when it is a docking
    PARAMETER pN.                            // port, else every fixture port (larEeRank 0) not docked within LAR_GRP_SEEK, on
    IF HASTARGET AND TARGET:ISTYPE("DockingPort") { RETURN LIST(TARGET). }   // this vessel or a loaded one near it
    LOCAL vs IS LIST(SHIP).
    LOCAL tl IS LIST().
    LIST TARGETS IN tl.
    FOR vx IN tl { IF vx:LOADED AND vx:DISTANCE < LAR_GRP_SEEK + 200 { vs:ADD(vx). } }
    LOCAL out IS LIST(). LOCAL dd IS LIST().
    FOR vx IN vs {
        FOR dp IN vx:DOCKINGPORTS {
            LOCAL dn IS (dp:NODEPOSITION - pN):MAG.
            IF larEeRank(dp:NAME) = 0 AND dn < LAR_GRP_SEEK AND NOT dp:STATE:STARTSWITH("Docked") {
                LOCAL k IS 0.
                UNTIL k >= dd:LENGTH OR dd[k] > dn { SET k TO k + 1. }
                out:INSERT(k, dp). dd:INSERT(k, dn).
            }
        }
    }
    RETURN out.
}
FUNCTION larGrpRel {                         // the fixture as the end effector sees it (all in one frame): LEXICON of RANGE,
    PARAMETER pN, sE, tE, fE, pF, aF, tF.    // RIGHT, UP (m: the fixture's node from the end effector's, the END EFF view:
    LOCAL dv IS pF - pN.                     // along the boresight, its STAR, its TOP), PITCH, YAW, ROLL (deg: the END EFF
    LOCAL ax IS VDOT(pN - pF, aF).           // stick's turn that puts the boresight on the fixture's axis, then the top on its
    LOCAL ang IS ARCCOS(MAX(-1, MIN(1, -VDOT(fE, aF)))).   // top), ANG (deg: the boresight off the axis), AX (m: the node
    LOCAL e0 IS VCRS(fE, -aF).               // out along the axis), LAT (m: off it). e0: sin(ANG) x the turn's axis (VCRS sense)
    LOCAL pt IS 0. LOCAL yw IS 0.
    IF e0:MAG > LAR_TINY {                   // the END EFF stick turns about -STAR (pitch), TOP (yaw), -FORE (roll): larCmdAxes
        SET pt TO -ang * VDOT(e0:NORMALIZED, sE).
        SET yw TO ang * VDOT(e0:NORMALIZED, tE).
    }
    LOCAL tP IS tF - fE * VDOT(tF, fE).
    LOCAL rl IS 0.
    IF tP:MAG > LAR_TINY { SET rl TO -ARCTAN2(VDOT(VCRS(tE, tP), fE), VDOT(tE, tP)). }
    RETURN LEXICON("RANGE", VDOT(dv, fE), "RIGHT", VDOT(dv, sE), "UP", VDOT(dv, tE), "PITCH", pt, "YAW", yw, "ROLL", rl,
                   "ANG", ang, "AX", ax, "LAT", (pN - pF - aF * ax):MAG).
}
FUNCTION larCapOk {                          // "" when CAPTURE may start from rel (larGrpRel's), else why not (the page's units)
    PARAMETER rel.
    IF rel["AX"] > LAR_CAP_START { RETURN "THE NODE " + ROUND(rel["AX"], 2) + " M OUT: CLOSE TO "
        + ROUND(LAR_CAP_START, 2) + " M FIRST". }
    IF rel["AX"] < 0 { RETURN "THE NODE IS PAST THE FIXTURE". }
    IF rel["LAT"] > LAR_CAP_LAT { RETURN ROUND(rel["LAT"], 3) + " M OFF THE AXIS (AT MOST "
        + ROUND(LAR_CAP_LAT, 3) + ")". }
    IF rel["ANG"] > LAR_CAP_ANG { RETURN "BORESIGHT " + ROUND(rel["ANG"], 1) + " DEG OFF THE AXIS (AT MOST " + LAR_CAP_ANG + ")". }
    RETURN "".
}
FUNCTION larCapBad {                         // "" while CAPTURE may fly on from rel, else why it stops
    PARAMETER rel.
    IF rel["LAT"] > LAR_CAP_LAT_MAX { RETURN "OFF THE AXIS". }
    IF rel["ANG"] > LAR_CAP_ANG_MAX { RETURN "BORESIGHT OFF THE AXIS". }
    RETURN "".
}
FUNCTION larCapRoll {                        // the end effector's roll about the fixture's axis aF, kept: its top tE (pressed
    PARAMETER tE, aF, tF.                    // flat to the axis) on the fixture's top tF and VCRS(aF, tF)
    LOCAL tR IS (tE - aF * VDOT(tE, aF)):NORMALIZED.
    RETURN LIST(VDOT(tR, tF), VDOT(tR, VCRS(aF, tF))).
}
FUNCTION larCapRef {                         // CAPTURE's attitude: LIST(the boresight along -aF, the top at the roll cr kept)
    PARAMETER aF, tF, cr.
    RETURN LIST(-aF, (tF * cr[0] + VCRS(aF, tF) * cr[1]):NORMALIZED).
}
FUNCTION larLineTick {                       // one tick on a straight line to pEnd (CAPTURE, RELEASE's back-off): the reference at
    PARAMETER pN, fE, tE, pEnd, u, fR, tR, left, spd, jm, lam2, cap, dt.   // pEnd + u x left (left m to go), the attitude (fR,
    LOCAL eP IS pEnd + u * left - pN.        // tR); LIST(the joint rates deg/s, their scale, left after the tick, eP, eW). The
    LOCAL eW IS larAttErr(fE, tE, fR, tR).   // reference moves on at spd only while the node is within LAR_CAP_LAG of it; the
    LOCAL go IS left > 0 AND eP:MAG <= LAR_CAP_LAG + larQRes(jm)[0].   // pulls on MAN AUG's leashes (LAR_REF_MAX, LAR_REF_ANG);
                                             // the lag allowed grows by the arm's resolution (larQRes: whole-degree joints)
    LOCAL pc IS CHOOSE eP:NORMALIZED * LAR_REF_MAX IF eP:MAG > LAR_REF_MAX ELSE eP.
    LOCAL wc IS CHOOSE eW:NORMALIZED * SIN(LAR_REF_ANG) IF eW:MAG > SIN(LAR_REF_ANG) ELSE eW.
    LOCAL res IS larAugRates(jm, larAugTask(CHOOSE -u * spd IF go ELSE V(0, 0, 0), pc, wc, V(0, 0, 0)), lam2, cap).
    RETURN LIST(res[0], res[1], CHOOSE MAX(0, left - spd * dt) IF go ELSE left, eP, eW).
}
FUNCTION larLoadMass {                       // the parts hanging on the end effector (its children, theirs, ...): LIST(mass t,
    PARAMETER ee.                            // parts, a fixture among them)
    LOCAL mt IS 0. LOCAL n IS 0. LOCAL fxIn IS FALSE.
    LOCAL stk IS ee:CHILDREN:COPY.
    UNTIL stk:LENGTH = 0 {
        LOCAL pt IS stk[stk:LENGTH - 1].
        stk:REMOVE(stk:LENGTH - 1).
        SET mt TO mt + pt:MASS. SET n TO n + 1.
        IF larEeRank(pt:NAME) = 0 AND pt:MODULES:CONTAINS("ModuleDockingNode") { SET fxIn TO TRUE. }
        FOR c IN pt:CHILDREN { stk:ADD(c). }
    }
    RETURN LIST(mt, n, fxIn).
}
FUNCTION larLoadScale {                      // every rate's share with a payload of mt tonnes: 1 unloaded, half at LAR_M_REF
    PARAMETER mt.
    RETURN 1 / (1 + MAX(0, mt) / LAR_M_REF).
}
FUNCTION larMakePrimary {                    // RELEASE makes the EE the primary docking node
    PARAMETER pt.                            // before undocking, otherwise it does not work: the LEE's 'Make Primary Docking
    IF NOT pt:MODULES:CONTAINS("ModuleDockingNode") { RETURN "". }   // Node' event (ModuleDockingNode.MakePrimary) when
    LOCAL md IS pt:GETMODULE("ModuleDockingNode").                   // offered: the event's name, or ""
    FOR ev IN md:ALLEVENTNAMES { IF ev:TOLOWER:CONTAINS("primary") { md:DOEVENT(ev). RETURN ev. } }
    RETURN "".
}
FUNCTION larUndockEv {                       // the docking module's own undock event on part pt (the fallback when :UNDOCK
    PARAMETER pt.                            // did not part them): the event's name, or ""
    IF NOT pt:MODULES:CONTAINS("ModuleDockingNode") { RETURN "". }
    LOCAL md IS pt:GETMODULE("ModuleDockingNode").
    FOR ev IN md:ALLEVENTNAMES { IF ev:TOLOWER:CONTAINS("undock") { md:DOEVENT(ev). RETURN ev. } }
    RETURN "".
}

// ---- the end effector camera (ARM-CAM) -----------------------------------------------------------------------------
FUNCTION larCamPose {                        // the end effector camera from the LEE's part origin pE and its (s, t, f):
    PARAMETER pE, s, t, f.                   // LIST(eye, forward, up, right); up the TOP made square to the boresight,
    LOCAL fw IS f:NORMALIZED.                // right VCRS(up, forward): the camera's own right (the STAR of a square frame)
    LOCAL uv IS (t - fw * VDOT(t, fw)):NORMALIZED.
    RETURN LIST(pE + fw * LAR_CAM_D, fw, uv, VCRS(uv, fw)).
}
FUNCTION larCamSee {                         // the point pt as the camera cp (larCamPose's) sees it: V(right, up, ahead), m
    PARAMETER cp, pt.
    LOCAL d IS pt - cp[0].
    RETURN V(VDOT(d, cp[3]), VDOT(d, cp[2]), VDOT(d, cp[1])).
}
// ---- OPR CMD and the ORB LD / PL frames -------------------------------------------------------------------------
FUNCTION larViewAxes {                       // a frame's view LIST(right, up, forward) from its forward fw and up uw: uw made square,
    PARAMETER fw, uw.                        // right = VCRS(up, forward) (the camera's, larCamPose's; a FACING's STAR)
    LOCAL f1 IS fw:NORMALIZED.
    LOCAL u1 IS (uw - f1 * VDOT(uw, f1)):NORMALIZED.
    RETURN LIST(VCRS(u1, f1), u1, f1).
}
FUNCTION larOrbView {                        // the aft-station view of ORB UNL / ORB LD from the orbiter's (s, t, f): forward aft,
    PARAMETER s, t, f.                       // up out of the bay, right to port (C1)
    RETURN larViewAxes(-f, t).
}
FUNCTION larEulerAxes {                      // the view LIST(right, up, forward) turned from the reference view ax by pitch, yaw,
    PARAMETER pyr, ax.                       // roll (deg, V(p, y, r)) in that order about the moving axes: pitch up tips forward
    LOCAL cp IS COS(pyr:X). LOCAL sp IS SIN(pyr:X).   // to up, yaw right swings it to right, roll right tilts up to right
    LOCAL cy IS COS(pyr:Y). LOCAL sy IS SIN(pyr:Y).
    LOCAL cr IS COS(pyr:Z). LOCAL sr IS SIN(pyr:Z).
    LOCAL f1 IS ax[2] * cp + ax[1] * sp.     // after the pitch (right unchanged)
    LOCAL u1 IS ax[1] * cp - ax[2] * sp.
    LOCAL f2 IS f1 * cy + ax[0] * sy.        // after the yaw (up unchanged)
    LOCAL r2 IS ax[0] * cy - f1 * sy.
    LOCAL u3 IS u1 * cr + r2 * sr.           // after the roll (forward unchanged)
    LOCAL r3 IS r2 * cr - u1 * sr.
    RETURN LIST(r3, u3, f2).
}
FUNCTION larEulerOf {                        // the pitch, yaw, roll (deg, V(p, y, r)) of the view with forward fw and up uw against
    PARAMETER fw, uw, ax.                    // the reference view ax (larEulerAxes' inverse; yaw +-90 is the sequence's singularity)
    LOCAL vw IS larViewAxes(fw, uw).
    LOCAL fr IS VDOT(vw[2], ax[0]). LOCAL fu IS VDOT(vw[2], ax[1]). LOCAL ff IS VDOT(vw[2], ax[2]).
    LOCAL pt IS ARCTAN2(fu, ff).
    LOCAL yw IS ARCTAN2(fr, SQRT(fu * fu + ff * ff)).
    LOCAL f1 IS ax[2] * COS(pt) + ax[1] * SIN(pt).
    LOCAL u1 IS ax[1] * COS(pt) - ax[2] * SIN(pt).
    LOCAL r2 IS ax[0] * COS(yw) - f1 * SIN(yw).
    RETURN V(pt, yw, ARCTAN2(VDOT(vw[1], r2), VDOT(vw[1], u1))).
}
FUNCTION larRotTurn {                        // the single turn (rad, a vector: the eigen axis, its size the angle, VCRS sense)
    PARAMETER f0, t0, f1, t1.                // that takes the frame (f0, t0) to (f1, t1), both square; 0 - 180 deg
    LOCAL s0 IS VCRS(t0, f0). LOCAL s1 IS VCRS(t1, f1).
    LOCAL w IS 0.5 * (VCRS(f0, f1) + VCRS(t0, t1) + VCRS(s0, s1)).      // sin(angle) x the axis
    LOCAL c IS MAX(-1, MIN(1, (VDOT(f0, f1) + VDOT(t0, t1) + VDOT(s0, s1) - 1) / 2)).
    LOCAL ang IS ARCTAN2(w:MAG, c).
    IF ang < 1e-9 { RETURN V(0, 0, 0). }
    LOCAL k IS V(0, 0, 0).
    IF ang < 120 { SET k TO w / w:MAG. }     // not :NORMALIZED (zero below 1e-5)
    ELSE {                                   // near 180 sin(angle) carries no axis: the symmetric part (R + R^T) / 2 - cos I
        LOCAL best IS -1.                    // = (1 - cos) k k^T, its longest column
        FOR e IN LIST(f0, t0, s0) {
            LOCAL re IS f1 * VDOT(f0, e) + t1 * VDOT(t0, e) + s1 * VDOT(s0, e).
            LOCAL rte IS f0 * VDOT(f1, e) + t0 * VDOT(t1, e) + s0 * VDOT(s1, e).
            LOCAL col IS 0.5 * (re + rte) - c * e.
            IF col:MAG > best { SET best TO col:MAG. SET k TO col:NORMALIZED. }
        }
        IF VDOT(k, w) < 0 { SET k TO -k. }
    }
    RETURN k * (ang * LAR_D2R).
}
FUNCTION larPorTask {                        // larAugTask with the point of resolution rr (m) off the node, rigid with the end
    PARAMETER vc, eP, eW, wc, rr.            // effector: the POR's velocity and the turn asked; the node's is the POR's less
    LOCAL aw IS wc + LAR_K_ATT * eW.         // VCRS(the turn, rr) (rr = 0: larAugTask)
    LOCAL lv IS vc + LAR_K_POS * eP - VCRS(aw, rr).
    RETURN LIST(lv:X, lv:Y, lv:Z, aw:X, aw:Y, aw:Z).
}
FUNCTION larPorAt {                          // the point of resolution: the node pN + rL's (star, top, fore) components on the end
    PARAMETER pN, s, t, f, rL.               // effector's axes
    RETURN pN + s * rL:X + t * rL:Y + f * rL:Z.
}
FUNCTION larInEe {                           // a vector's components on the end effector's (s, t, f)
    PARAMETER vec, s, t, f.
    RETURN V(VDOT(vec, s), VDOT(vec, t), VDOT(vec, f)).
}
FUNCTION larViewIn {                         // a vector's components on a view LIST(right, up, forward)
    PARAMETER vec, vw.
    RETURN V(VDOT(vec, vw[0]), VDOT(vec, vw[1]), VDOT(vec, vw[2])).
}
FUNCTION larViewOut {                        // components on a view back to a vector (larViewIn's inverse)
    PARAMETER c, vw.
    RETURN vw[0] * c:X + vw[1] * c:Y + vw[2] * c:Z.
}
FUNCTION larLoadCom {                        // the payload's centre of mass (the parts hanging on the end effector, their origins
    PARAMETER ee.                            // weighed by mass): LIST(the point (V(0,0,0) with no mass), mass t, the first
    LOCAL mt IS 0. LOCAL ms IS V(0, 0, 0). LOCAL fxp IS 0. LOCAL fxIn IS FALSE.   // fixture part beneath the LEE (0: none),
    LOCAL stk IS ee:CHILDREN:COPY.                                               // a fixture found); nearest parts first
    UNTIL stk:LENGTH = 0 {
        LOCAL pt IS stk[0].
        stk:REMOVE(0).
        SET mt TO mt + pt:MASS. SET ms TO ms + pt:POSITION * pt:MASS.
        IF NOT fxIn AND larEeRank(pt:NAME) = 0 AND pt:MODULES:CONTAINS("ModuleDockingNode") { SET fxp TO pt. SET fxIn TO TRUE. }
        FOR c IN pt:CHILDREN { stk:ADD(c). }
    }
    RETURN LIST(CHOOSE ms / mt IF mt > 0 ELSE V(0, 0, 0), mt, fxp, fxIn).
}
FUNCTION larPlView {                         // the PL frame's view from the fixture's axis aF (out of the payload) and top tF:
    PARAMETER aF, tF.                        // forward into the payload (-aF, the LEE's boresight once captured), up its top
    RETURN larViewAxes(-aF, tF).
}
FUNCTION larPoseXyz {                        // the point p as OPR CMD shows and keys it: V(X aft, Y starboard, Z up) (m) from the
    PARAMETER p, org, ov.                    // origin org, ov the aft-station view (larOrbView: right port, up, forward aft)
    LOCAL d IS p - org.
    RETURN V(VDOT(d, ov[2]), -VDOT(d, ov[0]), VDOT(d, ov[1])).
}
FUNCTION larXyzPose {                        // larPoseXyz's inverse: the point for V(X aft, Y starboard, Z up)
    PARAMETER xyz, org, ov.
    RETURN org + ov[2] * xyz:X - ov[0] * xyz:Y + ov[1] * xyz:Z.
}
FUNCTION larReach {                          // the arm's reach from joint iSp's pivot (the shoulder pitch): the links' lengths out
    PARAMETER pp, gs, iSp.                   // to the node pp (an upper bound; gs larGeom's)
    LOCAL d IS 0.
    FROM { LOCAL i IS iSp. } UNTIL i >= gs:LENGTH - 1 STEP { SET i TO i + 1. } DO { SET d TO d + (gs[i + 1][0] - gs[i][0]):MAG. }
    RETURN d + (pp - gs[gs:LENGTH - 1][0]):MAG.
}
FUNCTION larOprNew {                         // OPR CMD's move of the POR from p0 with the attitude (f0, t0) to p1, (f1, t1), at most
    PARAMETER p0, f0, t0, p1, f1, t1, vv, wd. // vv m/s and wd deg/s, both arriving together (T the longer):
    LOCAL w IS larRotTurn(f0, t0, f1, t1).   // LEXICON(p0, f0, t0, dp, w the single turn (rad), T s, s the share flown)
    LOCAL tt IS MAX((p1 - p0):MAG / MAX(vv, LAR_TINY), w:MAG / MAX(wd * LAR_D2R, LAR_TINY)).
    RETURN LEXICON("p0", p0, "f0", f0, "t0", t0, "dp", p1 - p0, "w", w, "T", tt, "s", CHOOSE 1 IF tt < LAR_TINY ELSE 0).
}
FUNCTION larOprNodeEnd {                     // where the move leaves the node: the POR's end less r0 (the node to the POR at the
    PARAMETER op, r0.                        // start) turned with the end effector
    RETURN op["p0"] + op["dp"] - larTurnVec(r0, op["w"]).
}
FUNCTION larOprReach {                       // "" when the node's end pE lies within LAR_REACH_SHARE of the reach from the shoulder
    PARAMETER pE, pp, gs, iSp.               // pitch pivot (gs larGeom's, pp the node now), else why not (feet)
    LOCAL rc IS larReach(pp, gs, iSp).
    LOCAL d IS (pE - gs[iSp][0]):MAG.
    IF d <= LAR_REACH_SHARE * rc { RETURN "". }
    RETURN "OUT OF REACH: " + ROUND(d, 1) + " M FROM THE SHOULDER (AT MOST " + ROUND(LAR_REACH_SHARE * rc, 1) + ")".
}
FUNCTION larOprRef {                         // the move's reference at its share s: LIST(the POR on the straight line, its forward,
    PARAMETER op.                            // its up), turned that share of the single turn
    LOCAL ws IS op["w"] * op["s"].
    RETURN LIST(op["p0"] + op["dp"] * op["s"], larTurnVec(op["f0"], ws), larTurnVec(op["t0"], ws)).
}
FUNCTION larOprTick {                        // one tick of OPR CMD (op larOprNew's; its share moved on): the POR pP, rr (m) from the
    PARAMETER op, pP, fE, tE, rr, jm, lam2, cap, dt.   // node to it, the attitude (fE, tE): LIST(the joint rates deg/s, their
    LOCAL rf IS larOprRef(op).               // scale, eP, eW, the share moved on). The share moves on (the line's and the turn's
    LOCAL eP IS rf[0] - pP.                  // rates fed forward) only while the POR is within LAR_OPR_LAG and the attitude
    LOCAL eW IS larAttErr(fE, tE, rf[1], rf[2]).   // LAR_OPR_LAGA of the reference; the pulls on MAN AUG's leashes
    LOCAL rs IS larQRes(jm).                 // the lags allowed grow by the arm's resolution (whole-degree joints)
    LOCAL go IS op["s"] < 1 AND eP:MAG <= LAR_OPR_LAG + rs[0] AND eW:MAG <= SIN(LAR_OPR_LAGA + rs[1]).
    LOCAL pc IS CHOOSE eP:NORMALIZED * LAR_REF_MAX IF eP:MAG > LAR_REF_MAX ELSE eP.
    LOCAL wc IS CHOOSE eW:NORMALIZED * SIN(LAR_REF_ANG) IF eW:MAG > SIN(LAR_REF_ANG) ELSE eW.
    LOCAL vff IS V(0, 0, 0). LOCAL wff IS V(0, 0, 0).
    IF go { SET vff TO op["dp"] / op["T"]. SET wff TO op["w"] / op["T"]. }
    LOCAL res IS larAugRates(jm, larPorTask(vff, pc, wc, wff, rr), lam2, cap).
    IF go { SET op["s"] TO MIN(1, op["s"] + dt / op["T"]). }
    RETURN LIST(res[0], res[1], eP, eW, go).
}
FUNCTION larOprLeft {                        // what is left of the move: LIST(m from the POR to the end, deg from the attitude to it)
    PARAMETER op, pP, fE, tE.
    RETURN LIST((op["p0"] + op["dp"] - pP):MAG,
                larRotTurn(fE, tE, larTurnVec(op["f0"], op["w"]), larTurnVec(op["t0"], op["w"])):MAG / LAR_D2R).
}
FUNCTION larFtS {                            // m/s as the displays show it (metres per second; the name is kept)
    PARAMETER vv, nd.
    RETURN ROUND(vv, nd).
}

// ---- the orbiter's attitude hold (ARM-STAB) ----------------------------------------------------------------------
//  While the arm runs the orbiter's attitude is held on its RCS (and the wheels the arm leaves on): INRTL fixed in
//  inertial space, LVLH fixed against the local vertical and the orbit (turning at orbital rate), FREE no command (free
//  drift). The reference is the orbiter's FORE and TOP as components in the mode's basis at the engage, so it is right
//  in any frame the basis is built in: INRTL's basis from SOLARPRIMEVECTOR and the body's spin axis (both turn with
//  KSP's frame when it rotates below the inverse-rotation altitude), LVLH's from the position and the orbital velocity.
//  The reference frame's own turn rate (LVLH ~0.07 deg/s; INRTL's in a rotating KSP frame) is taken from the basis's
//  change each tick and fed forward. The law per axis (pitch, roll, yaw): inside LAR_HOLD_DB no rate is commanded;
//  past it the rate back = LAR_HOLD_RMIN + LAR_HOLD_K x the error past it, at most LAR_HOLD_RATE (a limit cycle across
//  the deadband, as the real DAP's); no jet inside LAR_HOLD_RDB of that rate; the jets' command = the rate error past the
//  deadband / (LAR_HOLD_TAU x the axis's authority), capped so the turn's acceleration stays <= LAR_HOLD_ACC (KSP's RCS
//  throttles with the command). Signs as the DAP's: + pitch nose up, + roll right, + yaw nose right; a turn vector in
//  VCRS sense (dv/dt = VCRS(w, v), as SHIP:ANGULARVEL) is pitch -w.star, roll -w.fore, yaw +w.top.
FUNCTION larFbwHas {                         // TRUE when KalsCoproc's fly-by-wire has the suffix nm (FBW3, FBWXOFF)
    PARAMETER nm.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX(nm).
}
FUNCTION larHoldBasis {                      // the mode's basis LIST(e1, e2, e3), unit and square: INRTL from the prime
    PARAMETER md, pB, vO, pr, sp.            // vector pr made square to the spin axis sp; LVLH from the position pB (from the
    IF md = "LVLH" {                         // body's centre) and the orbital velocity vO: up, VCRS(n, up), the normal n
        LOCAL eu IS pB:NORMALIZED.
        LOCAL en IS VCRS(pB, vO):NORMALIZED.
        RETURN LIST(eu, VCRS(en, eu), en).
    }
    LOCAL ez IS CHOOSE sp:NORMALIZED IF sp:MAG > LAR_TINY ELSE VCRS(pB, vO):NORMALIZED.
    LOCAL ex IS (pr - ez * VDOT(pr, ez)):NORMALIZED.
    RETURN LIST(ex, VCRS(ez, ex), ez).
}
FUNCTION larHoldIn {                         // a vector's components in a basis
    PARAMETER b, vec.
    RETURN V(VDOT(vec, b[0]), VDOT(vec, b[1]), VDOT(vec, b[2])).
}
FUNCTION larHoldOut {                        // components in a basis back to a vector
    PARAMETER b, c.
    RETURN b[0] * c:X + b[1] * c:Y + b[2] * c:Z.
}
FUNCTION larHoldPry {                        // a turn vector (VCRS sense) as the DAP's V(pitch, roll, yaw) on the axes s, t, f
    PARAMETER w, s, t, f.
    RETURN V(-VDOT(w, s), -VDOT(w, f), VDOT(w, t)).
}
FUNCTION larHoldNew {                        // the hold's state: the mode, the orbiter's FORE / TOP in the basis b now
    PARAMETER md, b, f, t.
    RETURN LEXICON("mode", md, "ref", LIST(larHoldIn(b, f), larHoldIn(b, t)), "bp", b, "wr", V(0, 0, 0)).
}
FUNCTION larHoldAx {                         // one axis: the jets' command (-1..1) for the error e (deg) and the rate w (deg/s,
    PARAMETER e, w, au.                      // relative to the reference), the authority au (deg/s2 a full command)
    LOCAL hdb IS CHOOSE LAR_HOLD_AUG_DB IF LAR_HOLD_WORK ELSE LAR_HOLD_DB.      // The stiff law while the arm works
    LOCAL wc IS CHOOSE 0 IF ABS(e) <= hdb
        ELSE MIN(LAR_HOLD_RATE, LAR_HOLD_RMIN + LAR_HOLD_K * (ABS(e) - hdb)) * (CHOOSE 1 IF e > 0 ELSE -1).
    LOCAL dw IS wc - w.
    IF ABS(dw) <= LAR_HOLD_RDB OR au <= LAR_TINY { RETURN 0. }
    LOCAL um IS MIN(1, (CHOOSE LAR_HOLD_AUG_ACC IF LAR_HOLD_WORK ELSE LAR_HOLD_ACC) / au).
    RETURN MAX(-um, MIN(um, (dw - LAR_HOLD_RDB * (CHOOSE 1 IF dw > 0 ELSE -1)) / (LAR_HOLD_TAU * au))).
}
FUNCTION larHoldTick {                       // one tick of the hold h (larHoldNew's) in the basis b now: the orbiter's axes
    PARAMETER h, b, s, t, f, w, au, dt.      // s, t, f, its turn rate w (rad/s, VCRS sense), the authority au V(pitch, roll,
    LOCAL wr IS h["wr"].                     // yaw) deg/s2, dt s -> LIST(V(pitch, roll, yaw) jets -1..1, the error (deg)
    IF dt > 0 {                              // V(p, r, y), the rate (deg/s) V(p, r, y) relative to the reference)
        LOCAL bp IS h["bp"].
        LOCAL wn IS larAttErr(bp[0], bp[1], b[0], b[1]) / dt.
        SET wr TO wr + (wn - wr) * MIN(1, dt / LAR_HOLD_WF).
        SET h["wr"] TO wr.
    }
    SET h["bp"] TO b.
    IF h["mode"] = "FREE" { RETURN LIST(V(0, 0, 0), V(0, 0, 0), larHoldPry(w - wr, s, t, f) / LAR_D2R). }
    LOCAL ref IS h["ref"].
    LOCAL e IS larHoldPry(larAttErr(f, t, larHoldOut(b, ref[0]), larHoldOut(b, ref[1])), s, t, f) / LAR_D2R.
    LOCAL wl IS larHoldPry(w - wr, s, t, f) / LAR_D2R.
    RETURN LIST(V(larHoldAx(e:X, wl:X, au:X), larHoldAx(e:Y, wl:Y, au:Y), larHoldAx(e:Z, wl:Z, au:Z)), e, wl).
}
