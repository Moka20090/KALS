// ============================================================================
//  ENTRY_PREDICT.KS  --  forward entry predictor and bank solver
// ============================================================================
//  Forward entry predictor: the vehicle's aero model, the atmosphere, the entry integration and the reference family.
//  Loaded (RUNONCEPATH) by lib_guide.ks and by the flight programs (ops3q.ks, fam_build.ks, deorbit_plan.ks);
//  writes logs/fam_dump.csv (the family's own range table).
//  WHAT FLIES: the reference family (built once at boot, in orbit) and the flown loop eprGuidStep, which turns it into
//  the bank each guidance cycle by table lookup only. The bank solver (eprSolveStart / eprSolveRun) steers nothing: it
//  publishes EPR_SOL_*; the deorbit planner runs it (the entry scripts do not).
//  INCREMENTAL: one solve is about 3800 acceleration evaluations (about a second of kOS time), so the integration keeps
//  its state in globals and advances a fixed number of steps per call; the published solution is a few seconds stale.
// ============================================================================

// ---------------------------------------------------------------- body constants
GLOBAL EPR_R    IS SHIP:BODY:RADIUS.
GLOBAL EPR_MU   IS SHIP:BODY:MU.
GLOBAL EPR_ATM  IS SHIP:BODY:ATM:HEIGHT.
GLOBAL EPR_WMAG IS 2 * CONSTANT:PI / SHIP:BODY:ROTATIONPERIOD.

// Rotation axis, from SHIP:BODY:ANGULARVEL. It points SOUTH in KSP's left-handed frame. That does not disturb omega x r
// (VCRS is consistent with it) but breaks anything that treats the axis as north: latitude and the east/north frame.
// So the raw axis is kept for the equations of motion, and the north-bearing quantities are calibrated at init
// against kOS's own NORTH direction. Nothing below assumes a handedness.
GLOBAL EPR_WAXIS IS SHIP:BODY:ANGULARVEL:NORMALIZED.
// J2 gravity: Principia flies the real Earth's J2 on Sol's quarter-size Earth, so the prediction's gravity carries it
// there; the stock-gravity bodies (JNSQ) keep a point mass. The axis's sign does not matter (z enters squared and as p z).
GLOBAL EPR_J2 IS 0.0010826358191967033.        // ND, = -C20bar sqrt(5) (Principia's geopotential row 2)
GLOBAL EPR_R_J2 IS 1594534.075.                // m, Principia's reference radius
GLOBAL EPR_J2_ON IS SHIP:BODY:NAME = "Earth".  // Sol's Earth only
GLOBAL EPR_NAXIS IS SHIP:BODY:ANGULARVEL:NORMALIZED.   // flipped to point north at init
GLOBAL EPR_NSIGN IS 1.        // sign that makes VCRS(up, east) point north

GLOBAL EPR_TAEM_VEL IS 762.      // m/s surface-relative: prediction stops here
GLOBAL EPR_TAEM_ALT IS 12000.    // m: ...or here, whichever comes first
GLOBAL EPR_GAMMA    IS 1.4.      // adiabatic index

GLOBAL EPR_BANK_MIN IS 0.
GLOBAL EPR_BANK_MAX IS 85.       // deg, nominal ceiling (120 is for aborts; higher spends thermal margin on range errors)
GLOBAL EPR_BANK_MAX_ABORT IS 120. // deg, the abort ceiling (python BANK_MAX_ABORT): a TAL's bank clamp with lib_tal's TAL_V4N

// ---------------------------------------------------------------- measured tables
// Density by altitude, back-solved from flight logs as rho = 2q/v_srf^2.
GLOBAL EPR_RHO IS LIST(
  LIST(0,1.048577e+0), LIST(2000,9.315008e-1), LIST(4000,7.233725e-1),
  LIST(6000,5.580169e-1), LIST(8000,4.308223e-1), LIST(10000,3.279926e-1),
  LIST(12000,2.418073e-1), LIST(14000,1.688595e-1), LIST(16000,1.144883e-1),
  LIST(18000,7.703027e-2), LIST(20000,5.138128e-2), LIST(22000,3.502184e-2),
  LIST(24000,2.401241e-2), LIST(26000,1.633560e-2), LIST(28000,1.133337e-2),
  LIST(30000,7.974412e-3), LIST(32000,5.702712e-3), LIST(34000,4.046947e-3),
  LIST(36000,2.885264e-3), LIST(38000,2.096313e-3), LIST(40000,1.537624e-3),
  LIST(42000,1.120582e-3), LIST(44000,8.378747e-4), LIST(46000,6.388645e-4),
  LIST(48000,4.807162e-4), LIST(50000,3.616450e-4), LIST(52000,2.715937e-4),
  LIST(54000,2.035764e-4), LIST(56000,1.500551e-4), LIST(58000,1.095789e-4),
  LIST(60000,7.959640e-5), LIST(62000,5.651897e-5), LIST(64000,3.945884e-5),
  LIST(66000,2.768780e-5), LIST(68000,1.873009e-5), LIST(70000,1.263744e-5),
  LIST(72000,8.546465e-6), LIST(74000,5.399442e-6), LIST(76000,3.987922e-6),
  LIST(78000,1.578803e-6), LIST(80000,1.382233e-7)
).
// SOL'S DENSITY. The table above is JNSQ's; used on Sol it would read the density 1.10x to 1.39x too high (rising with
// altitude) and the Mach 5-17 percent high, skewing everything kOS integrates (the family's members, the planner's
// entry, eprAltForDrag). These rows are Sol's atmosphere sampled every 2 km; the last row is 10 m below the 80 km top
// because a log table cannot hold the curve's zero. Selected on Sol's Earth, like EPR_J2_ON and the lift pad.
GLOBAL EPR_RHO_SOL IS LIST(
  LIST(0,1.201368974e+00), LIST(2000,9.374903247e-01), LIST(4000,7.246549517e-01),
  LIST(6000,5.620963006e-01), LIST(8000,4.267577225e-01), LIST(10000,3.158208577e-01),
  LIST(12000,2.233799907e-01), LIST(14000,1.541687525e-01), LIST(16000,1.041355033e-01),
  LIST(18000,6.967691245e-02), LIST(20000,4.680415491e-02), LIST(22000,3.167523292e-02),
  LIST(24000,2.149621239e-02), LIST(26000,1.471192686e-02), LIST(28000,1.016576212e-02),
  LIST(30000,7.068645192e-03), LIST(32000,4.957035864e-03), LIST(34000,3.495226708e-03),
  LIST(36000,2.493520433e-03), LIST(38000,1.802640912e-03), LIST(40000,1.315486181e-03),
  LIST(42000,9.785672682e-04), LIST(44000,7.291215116e-04), LIST(46000,5.509242690e-04),
  LIST(48000,4.127771725e-04), LIST(50000,3.070618620e-04), LIST(52000,2.258504046e-04),
  LIST(54000,1.653884728e-04), LIST(56000,1.192628252e-04), LIST(58000,8.527946310e-05),
  LIST(60000,6.031561131e-05), LIST(62000,4.207495991e-05), LIST(64000,2.916528147e-05),
  LIST(66000,2.003553931e-05), LIST(68000,1.361478399e-05), LIST(70000,9.192658723e-06),
  LIST(72000,6.158350312e-06), LIST(74000,4.078578960e-06), LIST(76000,2.680201176e-06),
  LIST(78000,1.706395922e-06), LIST(79990,9.047066917e-11)
).
IF SHIP:BODY:NAME = "Earth" { SET EPR_RHO TO EPR_RHO_SOL. }

// No pressure table: kOS exposes the exact value, so this uses it. A table measured from a flight log would start at
// 20 km and clamp below it, which overestimates Mach across the last 8 km of every prediction.
// ---------------------------------------------------------------- AERO
// THE ORBITER'S OWN POLAR, not a table fitted to KSP flight data. The airframe carries SOCK_RealAero, whose lift and
// drag curves were derived from the real orbiter, so the predictor evaluates those curves directly.
//   1. MACH: the curves are Mach-flat above about 5, so they hold to Mach 25 by construction. No blend, no handover.
//   2. ALPHA: defined 0-90 deg, so aborts at 45-50 and the sub-15 TAEM region are not extrapolation.
//   3. NO ALPHA-30 SEAM: eprAoA ramps continuously from 40 to 15, so the polar is smooth through the 15-30 band.
// The empirical parts are two scalars and a six-point drag Mach residual; everything else is the orbiter.
// S_REF/MASS is the orbiter's: 249.909 m2 / 85,230 kg (Bornemann & Surber, NASA 19790013835, Fig 2 and Table 2).
// THE MATCH IS THEREFORE MASS-SPECIFIC: the calibration flights were at 24.1-24.3 t, and at a different vehicle mass
// the same aero gives a different Cl per kg.
// EPR_AERO_VER, the model's version (the curves are v7's, below), goes into the family file's and the TRAJ file's
// headers so neither can be flown by a different model than built it.
GLOBAL EPR_AERO_VER IS 7.1.

GLOBAL EPR_ORB_SM IS 0.0029322.      // orbiter S_ref / entry mass, m2/kg
// THE MODEL AT THE VEHICLE'S MASS. The fit is mass-specific (accelerations per unit q at the calibration mass), so a
// vehicle of mass m feels the same forces as accelerations x EPR_MASS_CAL / m. eprPolar carries the factor, so every
// user of the model follows: the predictor, the reference family (DREF), the guidance's drag checks. Default 1 = the
// calibration model; the flight hosts set it from SHIP:MASS: deorbit_plan before the burn (its propellant is not
// taken off), fam_build and ops3q after it.
GLOBAL EPR_MASS_CAL IS 24200.         // kg, the calibration flights' mass (lib_land LD_MASS_CAL)
GLOBAL EPR_MASS_K IS 1.
FUNCTION eprMassTrack {               // the host: the model at the vehicle's current mass
    SET EPR_MASS_K TO EPR_MASS_CAL / MAX(SHIP:MASS * 1000, 1).
    RETURN EPR_MASS_K.
}
// THE ELEVON TRIM IN THE MODEL. The flown drag and lift follow the elevon trim (lib_vehicle's ETRIM_ANG, negative = nose
// up), the same on the deorbits and the TALs: +0.6 % drag per deg within a Mach band. The model's level already carries
// the deorbits' own trim, so the term is the offset from it: drag x e^(EPR_TRIM_KD d), lift x e^(EPR_TRIM_KL d), d =
// MAX(trim, EPR_TRIM_MIN) - E0(Mach), E0 = the deorbits' median trim by Mach (EPR_TRIM_E0, linear between, flat outside).
// The predictor holds the OFFSET over the rest of the entry: eprTrimTrack works out the two factors once a guidance pass
// at the Mach of the moment, on the trim lagged EPR_TRIM_TAU s, and eprPolar carries them as constants (EPR_TRIM_FD /
// _FL), so every user of the model follows (the predictor, the guidance's drag checks, the addon's cycle, which reads
// them every call). 1 at and above EPR_TRIM_MACH (there a TAL's trim has not engaged and the term reads wrong) and
// wherever nothing calls eprTrimTrack: the hosts call it for the entry and the TAL only (the GRTLS keeps 1; no RTLS in
// the fit). Fitted on 57 stock entries, 19 more held out: drag 1.82 -> 1.52 % rms below Mach 8.8, the TALs' median
// -1.08 -> -0.07 %. python ENTRY_TRIM_* / entry_trim_factors (sync_check pairs them; the sims keep both factors 1).
GLOBAL EPR_TRIM_ON IS TRUE.           // FALSE: both factors stay 1
GLOBAL EPR_TRIM_KD IS 0.0055.         // per deg of offset, drag
GLOBAL EPR_TRIM_KL IS 0.0023.         // per deg of offset, lift
GLOBAL EPR_TRIM_MACH IS 8.8.          // the factors are 1 at and above this Mach
GLOBAL EPR_TRIM_MIN IS -15.           // deg, the trim's input clamp (lib_vehicle ETRIM_MAX nose up)
GLOBAL EPR_TRIM_TAU IS 10.            // s, the first-order lag on the trim
GLOBAL EPR_TRIM_E0 IS LIST(LIST(4.5, 0), LIST(5.0, 0), LIST(5.5, -0.18), LIST(6.0, -0.89), LIST(6.5, -1.57), LIST(7.3, -1.83), LIST(8.3, -2.88)).
GLOBAL EPR_TRIM_FD IS 1.              // the drag factor eprPolar carries
GLOBAL EPR_TRIM_FL IS 1.              // the lift factor eprPolar carries
GLOBAL EPR_TRIM_X IS 0.               // the lagged trim, deg
GLOBAL EPR_TRIM_T IS -1.              // the lag's last time (-1: not started)
FUNCTION eprTrimE0 {                  // the deorbits' median trim at this Mach
    PARAMETER mach.
    LOCAL t IS EPR_TRIM_E0.
    IF mach <= t[0][0] { RETURN t[0][1]. }
    IF mach >= t[t:LENGTH - 1][0] { RETURN t[t:LENGTH - 1][1]. }
    FROM { LOCAL i IS 1. } UNTIL i >= t:LENGTH STEP { SET i TO i + 1. } DO {
        IF mach <= t[i][0] { RETURN t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]). }
    }
    RETURN t[t:LENGTH - 1][1].
}
FUNCTION eprTrimTrack {               // the host, each guidance pass: the factors from the elevon trim at this Mach
    PARAMETER trim, mach.
    LOCAL now IS TIME:SECONDS.
    IF EPR_TRIM_T < 0 { SET EPR_TRIM_X TO trim. }
    ELSE {
        LOCAL dt IS MAX(0, now - EPR_TRIM_T).
        SET EPR_TRIM_X TO EPR_TRIM_X + (trim - EPR_TRIM_X) * dt / (EPR_TRIM_TAU + dt).
    }
    SET EPR_TRIM_T TO now.
    IF NOT EPR_TRIM_ON OR mach >= EPR_TRIM_MACH {
        SET EPR_TRIM_FD TO 1.
        SET EPR_TRIM_FL TO 1.
    } ELSE {
        LOCAL d IS MAX(EPR_TRIM_X, EPR_TRIM_MIN) - eprTrimE0(mach).
        SET EPR_TRIM_FD TO CONSTANT:E ^ (EPR_TRIM_KD * d).
        SET EPR_TRIM_FL TO CONSTANT:E ^ (EPR_TRIM_KL * d).
    }
}
// The model's lift is DEFINED as the force the game DELIVERS, so fd_lift/q and the model are the same quantity and a
// trim against fd_lift is legitimate. A model of the REQUESTED force (the cfg's lift times its normal-force projection)
// would not be: there the fd_lift / model ratio IS the projection, and trimming it away over-predicts lift.

// AERO v7: ONE LIFT CURVE FITTED ON BOTH CORRIDORS (ENTRY AND TAEM), THREE DRAG TERMS.
// Weighting both corridors in one separable lift curve costs the entry nothing measurable. Fit error:
//     entry corridor   CL 1.11 pct rms, worst 2.6    CD 1.01 pct, worst 2.5
//     TAEM box         CL 3.00 pct rms, worst 10.9   CD 2.19 pct, worst 7.6
// Lift is NOT split per part, though splitting scores better: the fit reproduces the total but is free to distribute
// it, and the distribution is where the force acts. The delivery correction in the cfg (liftCurve x
// (cos 13.99 / cos a)^0.602, for KSP's normal-force loss) was fitted on the whole vehicle at one curve's spread and does
// not survive a change of distribution: with 99 percent of the lift on the wing the cfg asks for the right total at
// AoA 40 / Mach 8 and the game delivers about half. So do not change the lift distribution without refitting the
// delivery correction; a single part's loss cannot be measured from total-vehicle forces.
// DRAG KEEPS THREE TERMS: induced drag is CL*tan(a), applied wherever the lift is, so only the parasitic fraction (3 to
// 6 percent of the total force) moves with the distribution.
GLOBAL EPR_PAR_W_WING IS 14.0.
GLOBAL EPR_PAR_W_FUS IS 4.4.
GLOBAL EPR_PAR_W_CTL IS 4.4.
GLOBAL EPR_K_LIFT IS 0.0029322.   // S/m; the lift curve is in absolute orbiter CL units
GLOBAL EPR_K_PAR IS 0.0029322.

GLOBAL EPR_LIFT_CURVE IS LIST(
  LIST(0.0871557,0.0812894,1.177818,1.177818), LIST(0.1305262,0.1323719,1.219530,1.219530),
  LIST(0.1736482,0.1867696,1.204323,1.204323), LIST(0.2164396,0.2358394,1.122337,1.122337),
  LIST(0.2588190,0.2823599,1.068707,1.068707), LIST(0.3007058,0.3258953,1.026358,1.026358),
  LIST(0.3420201,0.3677540,0.808640,0.808640), LIST(0.3826834,0.3921856,1.719203,1.719203),
  LIST(0.4226183,0.5063186,2.379793,2.379793), LIST(0.5000000,0.6713748,1.946544,1.946544),
  LIST(0.5735764,0.8001652,1.610067,1.610067), LIST(0.6427876,0.9012724,1.420161,1.420161),
  LIST(0.7071068,0.9898000,1.136842,1.136842), LIST(0.7660444,1.0413959,0.875433,0.875433)
).
// SOL'S ZERO-INCIDENCE LIFT KEY: the game's GameData/SOCK_RealAero/Patches/1b_lift_zero_pad.cfg adds key (0, 0) to
// the lifting parts, so on Sol the curve starts at (0, 0) with both tangents LIFT_PAD_SOLQ = 0.0812894 / 0.0871557
// per unit sin(alpha). JNSQ flies the table as above.
IF SHIP:BODY:NAME = "Earth" { EPR_LIFT_CURVE:INSERT(0, LIST(0.0, 0.0, 0.932691722973942, 0.932691722973942)). }
GLOBAL EPR_LIFT_MACH IS LIST(
  LIST(0.2500000,2.2664216,0.235377,0.235377), LIST(0.4000000,2.3017281,0.571114,0.571114),
  LIST(0.6000000,2.4663113,0.263206,0.263206), LIST(0.8000000,2.4070103,-0.382432,-0.382432),
  LIST(0.8500000,2.3707033,-0.034542,-0.034542), LIST(0.9000000,2.4035561,1.654539,1.654539),
  LIST(0.9200000,2.4865210,4.829549,4.829549), LIST(0.9500000,2.6450335,4.044279,4.044279),
  LIST(0.9800000,2.7291777,1.097613,1.097613), LIST(1.0500000,2.7547949,0.141692,0.141692),
  LIST(1.1000000,2.7461808,-0.689094,-0.689094), LIST(1.2000000,2.6514307,-0.938409,-0.938409),
  LIST(1.3000000,2.5584990,-1.163210,-1.163210), LIST(1.5000000,2.3024677,-0.999908,-0.999908),
  LIST(2.0000000,1.8585632,-0.691765,-0.691765), LIST(2.5000000,1.6107025,-0.635295,-0.635295),
  LIST(3.0000000,1.2232679,-0.322898,-0.322898), LIST(4.0000000,1.1263558,-0.079427,-0.079427),
  LIST(5.0000000,1.0644141,-0.031589,-0.031589), LIST(8.0000000,1.0000000,-0.018125,-0.018125),
  LIST(10.0000000,0.9737876,-0.003734,-0.003734), LIST(15.0000000,0.9738612,0.000004,0.000004),
  LIST(20.0000000,0.9738304,-0.000003,-0.000003), LIST(25.0000000,0.9738304,0.000000,0.000000),
  LIST(30.0000000,0.9738304,0.000000,0.000000)
).
GLOBAL EPR_WING_PAR_A IS LIST(
  LIST(0.0871557,0.0005118,0.007707,0.007707), LIST(0.1305262,0.0008461,0.007711,0.007711),
  LIST(0.1736482,0.0011788,0.006707,0.006707), LIST(0.2164396,0.0014223,0.001745,0.001745),
  LIST(0.2588190,0.0013274,-0.004504,-0.004504), LIST(0.3007058,0.0010428,-0.006097,-0.006097),
  LIST(0.3420201,0.0008201,-0.006706,-0.006706), LIST(0.3826834,0.0004931,-0.005994,-0.005994),
  LIST(0.4226183,0.0003370,-0.002666,-0.002666), LIST(0.5000000,0.0001803,-0.001693,-0.001693),
  LIST(0.5735764,0.0000815,-0.001031,-0.001031), LIST(0.6427876,0.0000331,-0.000495,-0.000495),
  LIST(0.7071068,0.0000154,-0.000267,-0.000267), LIST(0.7660444,0.0000002,-0.000259,-0.000259)
).
GLOBAL EPR_WING_PAR_M IS LIST(
  LIST(0.2500000,0.0000000,0.063809,0.063809), LIST(0.4000000,0.0095714,0.065858,0.065858),
  LIST(0.6000000,0.0230503,0.534778,0.534778), LIST(0.8000000,0.2234825,1.588436,1.588436),
  LIST(0.8500000,0.4201593,5.627267,5.627267), LIST(0.9000000,0.7862092,8.456745,8.456745),
  LIST(0.9200000,1.0121314,12.466847,12.466847), LIST(0.9500000,1.4095515,17.175120,17.175120),
  LIST(0.9800000,2.0426387,9.265612,9.265612), LIST(1.0500000,2.3361128,3.802667,3.802667),
  LIST(1.1000000,2.4989587,4.264321,4.264321), LIST(1.2000000,2.9757610,3.634615,3.634615),
  LIST(1.3000000,3.2258818,-0.303504,-0.303504), LIST(1.5000000,2.8847098,-1.004880,-1.004880),
  LIST(2.0000000,2.5224654,-0.606903,-0.606903), LIST(2.5000000,2.2778067,-0.442556,-0.442556),
  LIST(3.0000000,2.0799098,-0.442161,-0.442161), LIST(4.0000000,1.6145654,-0.408404,-0.408404),
  LIST(5.0000000,1.2631022,-0.153641,-0.153641), LIST(8.0000000,1.0000000,-0.060343,-0.060343),
  LIST(10.0000000,0.9613869,-0.005984,-0.005984), LIST(15.0000000,0.9581126,-0.000404,-0.000404),
  LIST(20.0000000,0.9573451,-0.000087,-0.000087), LIST(25.0000000,0.9572412,-0.000012,-0.000012),
  LIST(30.0000000,0.9572264,-0.000003,-0.000003)
).
GLOBAL EPR_FUS_PAR_A IS LIST(
  LIST(0.0871557,0.0018345,0.032542,0.032542), LIST(0.1305262,0.0032459,0.038213,0.038213),
  LIST(0.1736482,0.0051397,0.045646,0.045646), LIST(0.2164396,0.0071675,0.035562,0.035562),
  LIST(0.2588190,0.0081685,0.021307,0.021307), LIST(0.3007058,0.0089629,0.018840,0.018840),
  LIST(0.3420201,0.0097360,0.023057,0.023057), LIST(0.3826834,0.0108530,0.024667,0.024667),
  LIST(0.4226183,0.0117241,0.017125,0.017125), LIST(0.5000000,0.0128621,0.012252,0.012252),
  LIST(0.5735764,0.0135736,0.004925,0.004925), LIST(0.6427876,0.0135653,-0.002351,-0.002351),
  LIST(0.7071068,0.0132597,-0.003723,-0.003723), LIST(0.7660444,0.0131064,-0.002600,-0.002600)
).
GLOBAL EPR_FUS_PAR_M IS LIST(
  LIST(0.2500000,0.0000000,0.285934,0.285934), LIST(0.4000000,0.0428901,0.311585,0.311585),
  LIST(0.6000000,0.1090547,2.804598,2.804598), LIST(0.8000000,1.1647292,5.583728,5.583728),
  LIST(0.8500000,1.5049867,5.880433,5.880433), LIST(0.9000000,1.7527725,4.668753,4.668753),
  LIST(0.9200000,1.8317995,3.561446,3.561446), LIST(0.9500000,1.9308448,8.118299,8.118299),
  LIST(0.9800000,2.3188974,5.618381,5.618381), LIST(1.0500000,2.4926829,1.012779,1.012779),
  LIST(1.1000000,2.4404309,-2.314467,-2.314467), LIST(1.2000000,2.1455129,-1.992452,-1.992452),
  LIST(1.3000000,2.0419405,-0.836812,-0.836812), LIST(1.5000000,1.8944693,-0.805515,-0.805515),
  LIST(2.0000000,1.4780802,-0.645886,-0.645886), LIST(2.5000000,1.2485830,-0.363837,-0.363837),
  LIST(3.0000000,1.1142435,-0.103962,-0.103962), LIST(4.0000000,1.0926394,-0.021162,-0.021162),
  LIST(5.0000000,1.0719205,-0.023160,-0.023160), LIST(8.0000000,1.0000000,-0.015487,-0.015487),
  LIST(10.0000000,0.9944876,-0.000647,-0.000647), LIST(15.0000000,0.9954710,0.000135,0.000135),
  LIST(20.0000000,0.9958389,0.000041,0.000041), LIST(25.0000000,0.9958790,0.000005,0.000005),
  LIST(30.0000000,0.9958846,0.000001,0.000001)
).
GLOBAL EPR_CTL_PAR_A IS LIST(
  LIST(0.0871557,0.0123888,-0.074164,-0.074164), LIST(0.1305262,0.0091723,-0.079378,-0.079378),
  LIST(0.1736482,0.0055232,-0.078628,-0.078628), LIST(0.2164396,0.0024171,-0.045740,-0.045740),
  LIST(0.2588190,0.0016275,-0.004822,-0.004822), LIST(0.3007058,0.0020108,0.006575,0.006575),
  LIST(0.3420201,0.0021745,0.002939,0.002939), LIST(0.3826834,0.0022518,0.002355,0.002355),
  LIST(0.4226183,0.0023643,0.003597,0.003597), LIST(0.5000000,0.0026737,0.005408,0.005408),
  LIST(0.5735764,0.0031808,0.010568,0.010568), LIST(0.6427876,0.0041827,0.022591,0.022591),
  LIST(0.7071068,0.0061973,0.033645,0.033645), LIST(0.7660444,0.0083297,0.036181,0.036181)
).
GLOBAL EPR_CTL_PAR_M IS LIST(
  LIST(0.2500000,1.0075041,0.064842,0.064842), LIST(0.4000000,1.0172304,0.071833,0.071833),
  LIST(0.6000000,1.0326455,-0.070077,-0.070077), LIST(0.8000000,0.9891995,0.037674,0.037674),
  LIST(0.8500000,1.0420641,2.622068,2.622068), LIST(0.9000000,1.2514062,4.442268,4.442268),
  LIST(0.9200000,1.3530228,6.093308,6.093308), LIST(0.9500000,1.5560717,7.677385,7.677385),
  LIST(0.9800000,1.8136660,6.223159,6.223159), LIST(1.0500000,2.1783875,3.626154,3.626154),
  LIST(1.1000000,2.2488044,0.294685,0.294685), LIST(1.2000000,2.2225903,-0.568080,-0.568080),
  LIST(1.3000000,2.1351885,-0.387586,-0.387586), LIST(1.5000000,2.1063146,-0.486846,-0.486846),
  LIST(2.0000000,1.7943965,-0.536503,-0.536503), LIST(2.5000000,1.5698112,-0.408106,-0.408106),
  LIST(3.0000000,1.3862907,-0.254210,-0.254210), LIST(4.0000000,1.1884959,-0.149744,-0.149744),
  LIST(5.0000000,1.0868020,-0.047124,-0.047124), LIST(8.0000000,1.0000000,-0.015778,-0.015778),
  LIST(10.0000000,1.0079114,0.001211,0.001211), LIST(15.0000000,1.0084742,0.000064,0.000064),
  LIST(20.0000000,1.0085484,0.000009,0.000009), LIST(25.0000000,1.0085610,0.000001,0.000001),
  LIST(30.0000000,1.0085629,0.000000,0.000000)
).

// THE PARASITIC ROW. The three PAR_A tables have the lift curve's alpha keys without Sol's pad
// key (0, 0) in front, so eprPolar reads them at the lift row minus this: 1 on Sol, 0 on JNSQ.
GLOBAL EPR_PAR_SHIFT IS EPR_LIFT_CURVE:LENGTH - EPR_WING_PAR_A:LENGTH.

// physics.cfg curves. key = x, y, inTangent, outTangent -- cubic Hermite, tangents scaled
// by the key spacing, which is how Unity's FloatCurve evaluates.
GLOBAL EPR_PSEUDORE IS LIST(
  LIST(0,4,0,-2975.412), LIST(0.0001,3,-251.1479,-251.1479),
  LIST(0.01,2,-19.63584,-19.63584), LIST(0.1,1.2,-0.7846036,-0.7846036),
  LIST(1,1,0,0), LIST(100,1,0,0), LIST(200,0.82,0,0),
  LIST(500,0.86,0.0001932119,0.0001932119), LIST(1000,0.9,1.54299E-05,1.54299E-05),
  LIST(10000,0.95,0,0)
).

// ---------------------------------------------------------------- interpolation
// Table lookups carry an index HINT: altitude and speed change monotonically through a prediction, so resuming the scan
// where it last stopped turns a 41-entry linear search per step into one or two comparisons.
GLOBAL EPR_HINT_RHO IS 0.

FUNCTION eprLogInterp {
    PARAMETER tab, x, hint.
    LOCAL n IS tab:LENGTH.
    IF x <= tab[0][0]     { RETURN LIST(tab[0][1], 0). }
    IF x >= tab[n-1][0]   { RETURN LIST(0, n-2). }        // above the top: no atmosphere
    LOCAL i IS MAX(0, MIN(hint, n - 2)).
    UNTIL i <= 0 OR tab[i][0] <= x { SET i TO i - 1. }
    UNTIL i >= n - 2 OR tab[i+1][0] >= x { SET i TO i + 1. }
    LOCAL a0 IS tab[i][0].   LOCAL a1 IS tab[i+1][0].
    LOCAL y0 IS tab[i][1].   LOCAL y1 IS tab[i+1][1].
    IF y0 <= 0 OR y1 <= 0 { RETURN LIST(0, i). }
    LOCAL f IS (x - a0) / (a1 - a0).
    RETURN LIST(CONSTANT:E ^ (LN(y0) + f * (LN(y1) - LN(y0))), i).
}


FUNCTION eprRho {
    PARAMETER altm.
    LOCAL res IS eprLogInterp(EPR_RHO, altm, EPR_HINT_RHO).
    SET EPR_HINT_RHO TO res[1].
    RETURN res[0].
}

FUNCTION eprPres {
    PARAMETER altm.
    IF altm >= EPR_ATM { RETURN 0. }
    RETURN SHIP:BODY:ATM:ALTITUDEPRESSURE(MAX(altm, 0)) * CONSTANT:ATMTOKPA * 1000.
}

GLOBAL EPR_PR_REF IS -1.        // the pseudo-Reynolds normalisation reference, eprHermite(EPR_PSEUDORE, 1): a constant, computed once

// The reference, computed once. Call sites use this instead of eprHermite(EPR_PSEUDORE, 1).
FUNCTION eprPrRef {
    IF EPR_PR_REF < 0 { SET EPR_PR_REF TO eprHermite(EPR_PSEUDORE, 1). }
    RETURN EPR_PR_REF.
}
// THE CUBE SHARE: KSP applies the pseudo-Reynolds curve to the DRAG CUBES only, not to the lifting surfaces' own drag
// (most of this orbiter's, with the RealAero patches); the cubes are about 6 % of the drag hypersonically. Every drag
// site in this file goes through eprPrMult, since the full curve on all of the drag would over-predict it. The
// multiplier is exactly 1 where the curve is 1 (below about 50 km).
GLOBAL EPR_PR_SHARE IS 0.06.
FUNCTION eprPrMult {
    PARAMETER rhov.
    LOCAL pr IS eprHermite(EPR_PSEUDORE, rhov) / eprPrRef().
    IF pr <= 1 { RETURN pr. }       // the dense-air dip: the full curve
    RETURN 1 + EPR_PR_SHARE * (pr - 1).
}

FUNCTION eprHermite {
    PARAMETER keys, x.
    LOCAL n IS keys:LENGTH.
    IF x <= keys[0][0]   { RETURN keys[0][1]. }
    IF x >= keys[n-1][0] { RETURN keys[n-1][1]. }
    FROM {LOCAL i IS 1.} UNTIL i >= n STEP {SET i TO i + 1.} DO {
        IF keys[i][0] >= x {
            LOCAL x0 IS keys[i-1][0]. LOCAL y0 IS keys[i-1][1].
            LOCAL x1 IS keys[i][0].   LOCAL y1 IS keys[i][1].
            LOCAL sp IS x1 - x0.
            LOCAL t  IS (x - x0) / sp.
            LOCAL m0 IS keys[i-1][3] * sp.
            LOCAL m1 IS keys[i][2] * sp.
            LOCAL t2 IS t * t. LOCAL t3 IS t2 * t.
            RETURN (2*t3 - 3*t2 + 1) * y0 + (t3 - 2*t2 + t) * m0
                   + (-2*t3 + 3*t2) * y1 + (t3 - t2) * m1.
        }
    }
    RETURN keys[n-1][1].
}

// ---------------------------------------------------------------- aero
FUNCTION eprMach {
    PARAMETER altm, vrel.
    RETURN eprMachFrom(altm, vrel, eprRho(altm)).
}

// Mach when the CALLER ALREADY HAS rho (eprAccel computes rho first): the same arithmetic as eprMach, one density scan.
FUNCTION eprMachFrom {
    PARAMETER altm, vrel, rh.
    LOCAL ps IS eprPres(altm).
    IF ps <= 0 OR rh <= 0 { RETURN 0. }
    RETURN vrel / SQRT(EPR_GAMMA * ps / rh).
}

GLOBAL EPR_AOA_HIGH       IS 40.    // deg at or above EPR_AOA_HIGH_SPEED
GLOBAL EPR_AOA_LOW        IS 15.    // deg at EPR_AOA_LOW_SPEED
GLOBAL EPR_AOA_HIGH_SPEED IS 2000.  // m/s, about Mach 6
GLOBAL EPR_AOA_LOW_SPEED  IS 762.   // m/s; entry guidance ends here, handing to TAEM

// THE AOA'S ALPHA RAMP: EPR_AOA_RAMP_ON TRUE flies (and predicts) min(the schedule, the ramp: EPR_AOA_RAMP_HI above
// EPR_AOA_RAMP_V_HI, linear to EPR_AOA_RAMP_LO at EPR_AOA_RAMP_V_LO, flat below), for the AOA entries that lower alpha
// to about 30 deg near Mach 11 to reach their site (VBG). OFF by default: eprAoA = eprAoANom, nothing changes (the KSC
// AOA flies the nominal schedule). The offline sims carry the same ramp.
GLOBAL EPR_AOA_RAMP_ON IS FALSE.
// The ramp is centred on Mach 12 (3750 -> 3450 m/s at ~57 km), and below EPR_AOA_HIGH_SPEED it follows the line from
// EPR_AOA_RAMP_LO there to EPR_AOA_LOW at EPR_AOA_LOW_SPEED (the schedule's own 40 -> 15 line goes under 30 deg only at
// ~1505 m/s). Offline, the real guidance (python fly_family) reaches VBG on the first revolution from the 150 km ATO at
// 56-104 deg, +12..+80 km.
GLOBAL EPR_AOA_RAMP_V_HI IS 3750.   // m/s (Mach 12 is ~3430-3760 m/s at 65-50 km)
GLOBAL EPR_AOA_RAMP_V_LO IS 3450.   // m/s
GLOBAL EPR_AOA_RAMP_HI IS 40.       // deg
GLOBAL EPR_AOA_RAMP_LO IS 30.       // deg
FUNCTION eprAoA {
    PARAMETER vrel.
    IF EPR_AOA_RAMP_ON { RETURN MIN(eprAoANom(vrel), eprAoARamp(vrel)). }
    RETURN eprAoANom(vrel).
}
FUNCTION eprAoARamp {
    PARAMETER vrel.
    IF vrel < EPR_AOA_HIGH_SPEED {          // from EPR_AOA_RAMP_LO at EPR_AOA_HIGH_SPEED down to EPR_AOA_LOW
        LOCAL fl IS (vrel - EPR_AOA_LOW_SPEED) / (EPR_AOA_HIGH_SPEED - EPR_AOA_LOW_SPEED).
        RETURN EPR_AOA_LOW + (EPR_AOA_RAMP_LO - EPR_AOA_LOW) * MAX(0, MIN(1, fl)).
    }
    IF vrel >= EPR_AOA_RAMP_V_HI { RETURN EPR_AOA_RAMP_HI. }
    IF vrel <= EPR_AOA_RAMP_V_LO { RETURN EPR_AOA_RAMP_LO. }
    RETURN EPR_AOA_RAMP_LO + (EPR_AOA_RAMP_HI - EPR_AOA_RAMP_LO) * (vrel - EPR_AOA_RAMP_V_LO) / (EPR_AOA_RAMP_V_HI - EPR_AOA_RAMP_V_LO).
}
// The flown AoA schedule: EPR_AOA_HIGH at or above EPR_AOA_HIGH_SPEED, ramping LINEARLY to EPR_AOA_LOW at
// EPR_AOA_LOW_SPEED, clamped at both ends. It mirrors the entry script. A ramp, not a step: a step would make the
// predictor think the drag jumps where it actually eases in, under-estimating the range still to fly.
FUNCTION eprAoANom {
    PARAMETER vrel.
    IF vrel >= EPR_AOA_HIGH_SPEED { RETURN EPR_AOA_HIGH. }
    LOCAL span IS EPR_AOA_HIGH_SPEED - EPR_AOA_LOW_SPEED.
    IF span <= 0 { RETURN EPR_AOA_LOW. }
    LOCAL fr IS (vrel - EPR_AOA_LOW_SPEED) / span.
    IF fr < 0 { SET fr TO 0. }
    IF fr > 1 { SET fr TO 1. }
    // EPR_AOA_HIGH itself, not a switchable current value (the AoA-mode override is deliberately absent here).
    RETURN EPR_AOA_LOW + (EPR_AOA_HIGH - EPR_AOA_LOW) * fr.
}

// MACH, not velocity: the tables are indexed on Mach, so passing velocity here would be
// silently wrong rather than an error.
// BRACKET ONCE, EVALUATE MANY: eprHermite scans linearly for the bracketing key on every call, and eprPolar evaluates
// eight curves (the lift and the three parasitic terms, each in alpha and in Mach). The curves share their key
// positions: the three PAR_A tables have the lift curve's 14 alpha keys (on Sol the lift curve also has the pad key at
// 0, in front), and all four Mach tables the same 25. So one alpha bracket and one Mach bracket serve all eight (the
// PAR_A row is the lift row minus EPR_PAR_SHIFT).
// eprBracket returns the index i with keys[i-1] <= x <= keys[i], or 0 / LENGTH for the clamps.
// eprHermAt is eprHermite's arithmetic with that index handed in. It does not check that the index belongs to the
// table it reads: the caller hands each table its own row.
FUNCTION eprBracket {
    PARAMETER keys, x.
    LOCAL n IS keys:LENGTH.
    IF x <= keys[0][0] { RETURN 0. }
    IF x >= keys[n-1][0] { RETURN n. }
    FROM {LOCAL i IS 1.} UNTIL i >= n STEP {SET i TO i + 1.} DO {
        IF keys[i][0] >= x { RETURN i. }
    }
    RETURN n.
}

FUNCTION eprHermAt {
    PARAMETER keys, x, i.
    IF i <= 0 { RETURN keys[0][1]. }
    LOCAL n IS keys:LENGTH.
    IF i >= n { RETURN keys[n-1][1]. }
    LOCAL x0 IS keys[i-1][0]. LOCAL y0 IS keys[i-1][1].
    LOCAL x1 IS keys[i][0].   LOCAL y1 IS keys[i][1].
    LOCAL sp IS x1 - x0.
    LOCAL t  IS (x - x0) / sp.
    LOCAL m0 IS keys[i-1][3] * sp.
    LOCAL m1 IS keys[i][2] * sp.
    LOCAL t2 IS t * t. LOCAL t3 IS t2 * t.
    RETURN (2*t3 - 3*t2 + 1) * y0 + (t3 - 2*t2 + t) * m0
           + (-2*t3 + 3*t2) * y1 + (t3 - t2) * m1.
}

// Both coefficients from ONE pair of brackets and ONE evaluation of the lift terms: eprCda needs cla for the induced
// half, and every hot call site also needs cla to form L/D. Returns LIST(cla, cda).
// ONE ALPHA BRACKET, TWO ROWS: the bracket is taken on the lift curve. The three PAR_A tables have no pad key, so they
// are read at that row minus EPR_PAR_SHIFT, which is each table's own row. Below the first PAR_A key (5 deg) the row is
// 0 and the table's first value holds; at or above the last (50 deg) the row is the table's length and its last value
// holds. The parasitic lookup clamps at 89 deg and the lift's at 90; with the last alpha key at sin 50 = 0.766, both
// hold that key above 50, so one s serves both.
FUNCTION eprPolar {
    PARAMETER aoa, mach.
    LOCAL a IS MAX(0, MIN(89, aoa)).
    LOCAL s IS SIN(MAX(0, MIN(90, aoa))).
    LOCAL ia IS eprBracket(EPR_LIFT_CURVE, s).
    LOCAL im IS eprBracket(EPR_LIFT_MACH, mach).
    LOCAL ip IS MAX(0, ia - EPR_PAR_SHIFT).         // the PAR_A tables' row
    LOCAL cl IS EPR_K_LIFT * eprHermAt(EPR_LIFT_CURVE, s, ia) * eprHermAt(EPR_LIFT_MACH, mach, im).
    LOCAL pa IS EPR_K_PAR * (
        EPR_PAR_W_WING * eprHermAt(EPR_WING_PAR_A, s, ip) * eprHermAt(EPR_WING_PAR_M, mach, im) +
        EPR_PAR_W_FUS * eprHermAt(EPR_FUS_PAR_A, s, ip) * eprHermAt(EPR_FUS_PAR_M, mach, im) +
        EPR_PAR_W_CTL * eprHermAt(EPR_CTL_PAR_A, s, ip) * eprHermAt(EPR_CTL_PAR_M, mach, im)).
    RETURN LIST(cl * EPR_MASS_K * EPR_TRIM_FL, (cl * TAN(a) + pa) * EPR_MASS_K * EPR_TRIM_FD).   // x the mass and trim factors (above)
}

FUNCTION eprCla {
    PARAMETER aoa, mach.
    RETURN eprPolar(aoa, mach)[0].
}

FUNCTION eprCda {
    PARAMETER aoa, mach.
    RETURN eprPolar(aoa, mach)[1].
}
// THE ENTRY SPEEDBRAKE IN THE DRAG MODEL: ops3q opens the split rudder to the hinge below from the first speed (ramped
// to the second) and holds it to the handover. The entry's drag (eprCdaEntry, at the entry's drag sites; the alpha
// modulation's ratios keep eprCda) carries the brake's share of the drag: about 2 % above Mach 4.9, rising to 9 % at
// Mach 3.1 (one segment). EPR_SB_ON FALSE turns off both the brake (ops3q) and this term.
GLOBAL EPR_SB_ON IS TRUE.        // TRUE: the flight flies the brake
// The brake opens below EPR_SB_V (m/s, the relative speed) and is fully open from EPR_SB_V_FULL down; the share table
// below is indexed by Mach.
GLOBAL EPR_SB_V IS 2000.
GLOBAL EPR_SB_V_FULL IS 1500.
GLOBAL EPR_SB_HINGE IS 65.
GLOBAL EPR_SB_FRAC IS LIST(LIST(3.1, 0.089), LIST(3.6, 0.055), LIST(4.2, 0.043), LIST(4.9, 0.023), LIST(10.0, 0.019)).
FUNCTION eprSbFrac {
    PARAMETER mach, spd.
    IF NOT EPR_SB_ON OR spd >= EPR_SB_V { RETURN 0. }
    LOCAL ramp IS MIN(1, (EPR_SB_V - spd) / (EPR_SB_V - EPR_SB_V_FULL)).
    LOCAL t IS EPR_SB_FRAC.
    LOCAL fr IS t[t:LENGTH - 1][1].
    IF mach <= t[0][0] {
        SET fr TO t[0][1].
    } ELSE IF mach < t[t:LENGTH - 1][0] {
        FROM { LOCAL i IS 1. } UNTIL i >= t:LENGTH STEP { SET i TO i + 1. } DO {
            IF mach <= t[i][0] {
                SET fr TO t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]).
                BREAK.
            }
        }
    }
    RETURN fr * ramp.
}
// THE ENTRY'S DRAG BELOW MACH 7, MEASURED IN FLIGHT: the polar is short of the flown drag below Mach ~6 along
// the entry's alpha schedule (4-6 % at Mach 4.3-5, 8-10 % at 3.1-4.3, 8-22 % at 2.5-3.1), the brake stowed or out; the
// entry's drag (eprCdaEntry) carries (1 + this) x the polar. Uniform knots 0.5 apart (indexed directly), linear between, flat
// outside. Measured against eprCdaEntry with EPR_AERO_FIX in it: a refit of EPR_AERO_FIX moves these knots. python
// ENTRY_CD_FIX / entry_cd_fix (sync_check pairs them).
GLOBAL EPR_CD_FIX IS LIST(LIST(2.5, 0.218), LIST(3.0, 0.075), LIST(3.5, 0.096), LIST(4.0, 0.079), LIST(4.5, 0.056), LIST(5.0, 0.053), LIST(5.5, 0.028), LIST(6.0, 0.006), LIST(6.5, 0.005), LIST(7.0, 0)).
FUNCTION eprCdFix {
    PARAMETER mach.
    LOCAL t IS EPR_CD_FIX.
    LOCAL n IS t:LENGTH.
    IF mach <= t[0][0] { RETURN t[0][1]. }
    IF mach >= t[n - 1][0] { RETURN t[n - 1][1]. }
    LOCAL i IS MIN(FLOOR((mach - t[0][0]) / (t[1][0] - t[0][0])), n - 2).
    RETURN t[i][1] + (t[i + 1][1] - t[i][1]) * (mach - t[i][0]) / (t[i + 1][0] - t[i][0]).
}
// THE ENTRY'S LIFT AND DRAG AT THE FLOWN MASS: at the vehicle's true mass the polar reads high along the entry, more so above
// alpha 40 (the flown drag rises ~3.3 %/deg there against the polar's ~5.3). Fitted on 14 stock entries, each flight weighted
// equally: ln(flown / polar) = level + slope x (alpha - 40) above 40; rows LIST(Mach, drag level, drag slope /deg, lift
// level, lift slope /deg) at Mach 5.5 and 7.5, linear in Mach between, flat outside. The entry's drag (eprCdaEntry, the
// integrators) and lift (the integrators) carry it; eprCda / eprCla stay the polar (the guidance's demodulation and alpha
// step, the GRTLS). python ENTRY_AERO_FIX / entry_aero_fix (sync_check pairs them).
GLOBAL EPR_AERO_FIX IS LIST(LIST(5.5, -0.0664, -0.0085, -0.0246, -0.0150), LIST(7.5, -0.0550, -0.0207, -0.0339, -0.0183)).
// THE BODY FLAP IN THE ENTRY MODEL (stock only). The flown hypersonic drag over the model above rises with the flap the flight flew
// (lib_vehicle PTRIM_ANG, + = trailing edge down): 0.0031 .. 0.0044 per deg at Mach 5.5-12.5 on 15 stock entries (the alpha-30 and
// alpha-40 deorbits and the TALs alike; ~0.0022 inside one flight). The model's level above was fitted with the flap pinned up, so
// ln drag factor += EPR_FLAP_KF x w(M) x (X - FREF(M)), X = EPR_FLAP_X, the flap eprFlapTrack follows (lag EPR_FLAP_TAU s) and the
// predictor HOLDS over the rest of the entry (the elevon trim's way). EPR_FLAP_TAB rows LIST(Mach, w, FREF deg), linear between,
// flat outside: w 0 at Mach 4.5 up to 1 at 5.5 (EPR_CD_FIX carries the flap-mixed level below), FREF = the flap at which the
// model is right. EPR_FLAP_X <= -90 = no term. EPR_FLAP_NOM = X where nothing tracks the flap (the family build on the coast, the
// planner, a host before the flap trims, FAR): -99 = no term. The drag factor only (the lift is not touched). python
// ENTRY_FLAP_* / entry_flap_term / entry_flap_track; C# FlapTerm in EntryGuid / DpCore / Fam (sync_check pairs the constants).
GLOBAL EPR_FLAP_KF IS 0.0036.       // per deg of flap above FREF
GLOBAL EPR_FLAP_TAB IS LIST(LIST(4.5, 0, -13), LIST(5.5, 1, -13), LIST(6.5, 1, -15), LIST(7.5, 1, -18), LIST(8.5, 1, -20)).
GLOBAL EPR_FLAP_TAU IS 10.          // s, the lag on the live flap
GLOBAL EPR_FLAP_NOM IS -99.         // deg, X where nothing tracks the flap (-99: no term)
GLOBAL EPR_FLAP_X IS -99.           // deg, the flap the model carries
GLOBAL EPR_FLAP_T IS -1.            // the lag's last time (-1: not started)
FUNCTION eprFlapTerm {              // ln of the flap's drag factor at this Mach
    PARAMETER mach.
    IF EPR_FLAP_X <= -90 { RETURN 0. }
    LOCAL t IS EPR_FLAP_TAB.
    LOCAL n IS t:LENGTH.
    LOCAL w IS t[n - 1][1].
    LOCAL f IS t[n - 1][2].
    IF mach <= t[0][0] {
        SET w TO t[0][1].
        SET f TO t[0][2].
    } ELSE IF mach < t[n - 1][0] {
        FROM { LOCAL i IS 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
            IF mach <= t[i][0] {
                LOCAL u IS (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]).
                SET w TO t[i - 1][1] + (t[i][1] - t[i - 1][1]) * u.
                SET f TO t[i - 1][2] + (t[i][2] - t[i - 1][2]) * u.
                BREAK.
            }
        }
    }
    RETURN EPR_FLAP_KF * w * (EPR_FLAP_X - f).
}
FUNCTION eprFlapTrack {             // the host, each guidance pass: the flap the model carries (act FALSE: the flap is not trimming, or FAR)
    PARAMETER flap, act.
    LOCAL now IS TIME:SECONDS.
    IF NOT act {
        SET EPR_FLAP_X TO EPR_FLAP_NOM.
        SET EPR_FLAP_T TO -1.
        RETURN.
    }
    IF EPR_FLAP_T < 0 OR EPR_FLAP_X <= -90 { SET EPR_FLAP_X TO flap. }
    ELSE {
        LOCAL dt IS MAX(0, now - EPR_FLAP_T).
        SET EPR_FLAP_X TO EPR_FLAP_X + (flap - EPR_FLAP_X) * dt / (EPR_FLAP_TAU + dt).
    }
    SET EPR_FLAP_T TO now.
}
FUNCTION eprAeroFix {             // LIST(drag factor, lift factor)
    PARAMETER aoa, mach.
    LOCAL lo IS EPR_AERO_FIX[0].
    LOCAL hi IS EPR_AERO_FIX[1].
    LOCAL w IS MIN(1, MAX(0, (mach - lo[0]) / (hi[0] - lo[0]))).
    LOCAL da IS MAX(aoa - 40, 0).
    LOCAL ft IS 0.
    IF EPR_FLAP_X > -90 { SET ft TO eprFlapTerm(mach). }
    RETURN LIST(CONSTANT:E ^ (lo[1] + (hi[1] - lo[1]) * w + (lo[2] + (hi[2] - lo[2]) * w) * da + ft),
                CONSTANT:E ^ (lo[3] + (hi[3] - lo[3]) * w + (lo[4] + (hi[4] - lo[4]) * w) * da)).
}
FUNCTION eprCdaEntry {
    PARAMETER aoa, mach, spd.
    RETURN eprCda(aoa, mach) * (1 + eprCdFix(mach)) * eprAeroFix(aoa, mach)[0] * (1 + eprSbFrac(mach, spd)).
}

FUNCTION eprOmegaCross {
    PARAMETER rv.
    RETURN VCRS(EPR_WAXIS * EPR_WMAG, rv).
}

// Total inertial acceleration: central gravity plus aero acting on the SURFACE-RELATIVE velocity. Bank rotates the lift
// vector about v_rel; positive bank tilts it toward +side, where side = up_perp CROSS v_hat.
// ============================================================================
//  PASS 1 LEAF FUNCTIONS  --  scalar in, scalar out, no trajectory
// ============================================================================
//  The family builder and the corridor use every one of these; everything that integrates rests on them.
//  kOS has a namespace a transcribed formula can clobber, and a clash is a PARSE error: the file does not load at all.
//  Hence two local names that differ from the usual symbols:
//      `cd`   -> the change-directory BUILTIN FUNCTION      (here `cdrag`)
//      `alt`  -> the BUILTIN READONLY VARIABLE ALT          (here `altm`)
//  kOS says: "Not allowed to SET a name that will clobber or hide the BUILTIN_FUNCTION called 'cd'". Same family as
//  `adD` hiding the builtin `ADD` (eprDestGeo's note). Running kOS's compiler offline finds a clash before a flight does.

GLOBAL EPR_G0 IS 9.80665.        // m/s^2, standard gravity, for load factors only (not the local gravity, EPR_MU/r^2)

// ---- Nz LIMITS (2.8.2) ---------------------------------------------------------------
GLOBAL EPR_NZ_LIMIT       IS 2.5.   // g, NOMINAL ceiling: the orbiter's structural limit, adopted for this vehicle
GLOBAL EPR_NZ_LIMIT_ABORT IS 4.     // g, abort ceiling (same split as EPR_BANK_MAX vs EPR_BANK_MAX_ABORT)

// ---- MINIMUM BANK ANGLE (2.14.2) -----------------------------------------------------
// The floor that stops the downrange solver spending all the turn authority: when the range solve wants to stretch it
// reduces bank, and at zero bank the vehicle cannot turn at all.
GLOBAL EPR_MIN_BANK_HI_LOW  IS 15.  // deg above EPR_MIN_BANK_MACH when 2.2*delaz allows it
GLOBAL EPR_MIN_BANK_HI_HIGH IS 37.  //   ...and when it does not
GLOBAL EPR_MIN_BANK_LOW     IS 20.  // deg below EPR_MIN_BANK_MACH
GLOBAL EPR_MIN_BANK_MACH    IS 10.
GLOBAL EPR_MIN_BANK_DELAZ_K IS 2.2. // the manual's crew technique for "is 15 enough"
GLOBAL EPR_USE_MIN_BANK     IS TRUE.

// ---- DELTA-AZIMUTH DEADBAND (2.14.1) -------------------------------------------------
// 10.5 first reversal, 17.5 subsequent, ramping to 7 between EPR_AZ_MACH_HI and _LO. Keyed on MACH, not speed: at a
// given speed the actual Mach varies with altitude. The manual's values are used but its window is not: 2.14.1 ramps
// between Mach 4 and 3, a sliver of this entry, so the ramp is re-derived to start at Mach 6.
GLOBAL EPR_AZ_FIRST   IS 10.5.
GLOBAL EPR_AZ_SUBS    IS 17.5.
GLOBAL EPR_AZ_LATE    IS 7.
GLOBAL EPR_AZ_MACH_HI IS 6.
GLOBAL EPR_AZ_MACH_LO IS 3.

// ---- ROLL SLEW -----------------------------------------------------------------------
// BOTH ROLL LIMITS ARE DECLARED HERE, and lib_guide.ks reads them without declaring its own: with a declaration in each
// file, whichever loads last wins, and this lower-level module must run eprBankSlew standalone.
GLOBAL EPR_ROLL_RATE_LIMIT  IS 5.   // deg/s; matches BANK_RATE in sock_ops3_jnsq.ks
GLOBAL EPR_ROLL_ACCEL_LIMIT IS 4.   // deg/s^2; matches BANK_ACCEL_MAX (one number in several files: change them together)

// Invert the density table: a table SEARCH in one pass, not a bisection on eprRho.
FUNCTION eprAltForRho {
    PARAMETER rho.
    LOCAL n IS EPR_RHO:LENGTH.
    IF rho >= EPR_RHO[0][1] { RETURN EPR_RHO[0][0]. }
    IF rho <= 0 { RETURN EPR_RHO[n-1][0]. }
    LOCAL i IS 1.
    UNTIL i >= n {
        LOCAL a1 IS EPR_RHO[i][0].
        LOCAL r1 IS EPR_RHO[i][1].
        IF r1 <= rho {
            LOCAL a0 IS EPR_RHO[i-1][0].
            LOCAL r0 IS EPR_RHO[i-1][1].
            IF r0 <= 0 OR r1 <= 0 { RETURN a1. }
            LOCAL fr IS (LN(r0) - LN(rho)) / (LN(r0) - LN(r1)).
            RETURN a0 + fr * (a1 - a0).
        }
        SET i TO i + 1.
    }
    RETURN EPR_RHO[n-1][0].
}

// Altitude at which the vehicle makes `drag` m/s^2 at `vrel`: the INVERSE of the aero model (D and V determine rho, and
// rho determines h). Iterated, because eprCda and the pseudo-Reynolds factor both need the altitude being solved for;
// damped (halfway each pass) rather than Newton, because the Mach dependence has kinks a Newton step can jump across.
FUNCTION eprAltForDrag {
    PARAMETER drag, vrel, altGuess IS 60000, iters IS 14.
    LOCAL a IS altGuess.
    LOCAL k IS 0.
    UNTIL k >= iters {
        LOCAL cdrag IS eprCdaEntry(eprAoA(vrel), eprMach(a, vrel), vrel).
        LOCAL pr IS eprPrMult(eprRho(a) * vrel).
        LOCAL den IS vrel * vrel * cdrag * pr.
        IF den < 0.000000000001 { SET den TO 0.000000000001. }
        LOCAL a2 IS eprAltForRho(2 * drag / den).
        IF ABS(a2 - a) < 1 { RETURN a2. }
        SET a TO 0.5 * (a + a2).
        SET k TO k + 1.
    }
    RETURN a.
}

// MINIMUM drag: the equilibrium-glide boundary (2.8.3's minimum-lift constraint).
//     D_min = g (1 - (V/Vc)^2) / (L/D)
// Below this, wings-level lift cannot hold the vehicle up: it climbs into thin air, loses lift, comes back down, and
// phugoids (2.9). A soft boundary: the vehicle survives crossing it, but a reference below it is not a plan. It is the
// locus where wings-level flight stops being possible, not a claim that the vehicle flies equilibrium glide.
FUNCTION eprDMinGlide {
    PARAMETER vrel, altGuess IS 60000, iters IS 20.
    LOCAL a IS altGuess.
    LOCAL d IS 0.
    LOCAL k IS 0.
    UNTIL k >= iters {
        LOCAL rr IS EPR_R + a.
        LOCAL g IS EPR_MU / (rr * rr).
        LOCAL vc IS SQRT(EPR_MU / rr).
        LOCAL m IS eprMach(a, vrel).
        LOCAL al IS eprAoA(vrel).
        LOCAL cdrag IS eprCdaEntry(al, m, vrel).   // the entry's drag and lift (python d_min_glide: cda_entry, cla_entry)
        IF cdrag <= 0 { RETURN 0. }
        LOCAL ld IS eprCla(al, m) * eprAeroFix(al, m)[1] / cdrag.
        IF ld < 0.000001 { SET ld TO 0.000001. }
        SET d TO g * (1 - (vrel / vc) * (vrel / vc)) / ld.
        IF d <= 0 { RETURN 0. }
        LOCAL a2 IS eprAltForDrag(d, vrel, a).
        IF ABS(a2 - a) < 1 { RETURN d. }
        SET a TO 0.5 * (a + a2).
        SET k TO k + 1.
    }
    RETURN MAX(d, 0).
}

// MAXIMUM drag from the normal load factor. Nz is the BODY-NORMAL acceleration, so at angle of attack BOTH lift and
// drag project onto it:
//     Nz g0 = L cos(alpha) + D sin(alpha)  ->  D_max = Nz g0 / ((L/D) cos a + sin a)
// Above about 2400 m/s this does not bind: the vehicle cannot reach it (at 3600 m/s even EPR_BANK_MAX makes 2.198 m/s^2
// against a 17.324 ceiling). A caller wanting the true upper edge must take the smaller of this and what BANK_MAX can
// REACH from the current state, a trajectory property; this function is the fixed part.
FUNCTION eprDMaxNz {
    PARAMETER vrel, altm, nz IS -1.
    LOCAL nzl IS CHOOSE EPR_NZ_LIMIT IF nz < 0 ELSE nz.
    LOCAL m IS eprMach(altm, vrel).
    LOCAL al IS eprAoA(vrel).
    LOCAL cdrag IS eprCdaEntry(al, m, vrel).   // the entry's drag and lift (python d_max_nz: cda_entry, cla_entry)
    IF cdrag <= 0 { RETURN 0. }
    LOCAL ld IS eprCla(al, m) * eprAeroFix(al, m)[1] / cdrag.
    // kOS trig takes DEGREES, so COS(al)/SIN(al) needs no radian conversion.
    LOCAL den IS ld * COS(al) + SIN(al).
    IF den < 0.000001 { SET den TO 0.000001. }
    RETURN nzl * EPR_G0 / den.
}

// Minimum |bank| while banked TOWARD the site, per 2.14.2. The caller must apply this only when banked toward: rule (a)
// of 2.14.2 is not expressible here, because this function cannot see the commanded sign.
FUNCTION eprMinBank {
    PARAMETER mach, delazDeg.
    IF NOT EPR_USE_MIN_BANK { RETURN 0. }
    IF mach > EPR_MIN_BANK_MACH {
        LOCAL need IS EPR_MIN_BANK_DELAZ_K * ABS(delazDeg).
        IF need <= EPR_MIN_BANK_HI_LOW { RETURN EPR_MIN_BANK_HI_LOW. }
        RETURN EPR_MIN_BANK_HI_HIGH.
    }
    RETURN EPR_MIN_BANK_LOW.
}

// Delta-azimuth deadband in degrees, per 2.14.1. `first` is whether NO reversal has happened yet this entry, not
// whether this is the first guidance cycle: the initial heading error is a targeting residual, worth taking out early
// with the tighter threshold; after that, reversing costs drag and the band widens.
FUNCTION eprAzDeadband {
    PARAMETER mach, first.
    IF first { RETURN EPR_AZ_FIRST. }
    IF mach >= EPR_AZ_MACH_HI { RETURN EPR_AZ_SUBS. }
    IF mach <= EPR_AZ_MACH_LO { RETURN EPR_AZ_LATE. }
    LOCAL f IS (mach - EPR_AZ_MACH_LO) / (EPR_AZ_MACH_HI - EPR_AZ_MACH_LO).
    RETURN EPR_AZ_LATE + (EPR_AZ_SUBS - EPR_AZ_LATE) * f.
}

// Rate- AND acceleration-limited slew of the COMMANDED bank. Returns LIST(bank, rate). THREE CLAMPS, in this order:
//   1. the rate the error alone would ask for, bounded by EPR_ROLL_RATE_LIMIT
//   2. the BRAKING bound SQRT(2a|err|): the fastest rate that can still be brought to zero within the remaining error
//   3. the acceleration bound, rate +/- EPR_ROLL_ACCEL_LIMIT*dt
// CLAMP 2 IS NOT OPTIONAL: without it the acceleration clamp stops the rate falling fast enough near the target, and
// the command sails past and hunts.
FUNCTION eprBankSlew {
    PARAMETER cur, tgt, rate, dt.
    LOCAL err IS tgt - cur.
    LOCAL dtc IS MAX(dt, 0.001).
    LOCAL want IS err / dtc.
    IF want > EPR_ROLL_RATE_LIMIT { SET want TO EPR_ROLL_RATE_LIMIT. }
    IF want < 0 - EPR_ROLL_RATE_LIMIT { SET want TO 0 - EPR_ROLL_RATE_LIMIT. }
    LOCAL vmax IS SQRT(2 * EPR_ROLL_ACCEL_LIMIT * ABS(err)).
    IF want > vmax { SET want TO vmax. }
    IF want < 0 - vmax { SET want TO 0 - vmax. }
    LOCAL hi IS rate + EPR_ROLL_ACCEL_LIMIT * dt.
    LOCAL lo IS rate - EPR_ROLL_ACCEL_LIMIT * dt.
    IF want > hi { SET want TO hi. }
    IF want < lo { SET want TO lo. }
    RETURN LIST(cur + want * dt, want).
}


FUNCTION eprJ2Accel {                       // J2 acceleration in vector form (p = the axis):
    PARAMETER rv, rmag.                     //   k (r (1 - 5 z2/r2) + p 2 z), k = -1.5 J2 MU R_J2^2 / r^5
    LOCAL z IS VDOT(rv, EPR_WAXIS).
    LOCAL k IS -1.5 * EPR_J2 * EPR_MU * EPR_R_J2 * EPR_R_J2 / (rmag ^ 5).
    LOCAL zz IS 5.0 * z * z / (rmag * rmag).
    RETURN (rv * (1.0 - zz) + EPR_WAXIS * (2.0 * z)) * k.
}

FUNCTION eprAccel {
    PARAMETER rv, vv, bankDeg.
    LOCAL rmag IS rv:MAG.
    LOCAL g IS rv * (-EPR_MU / (rmag * rmag * rmag)).
    IF EPR_J2_ON { SET g TO g + eprJ2Accel(rv, rmag). }
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL vr IS vrelv:MAG.
    LOCAL altm IS rmag - EPR_R.
    IF vr < 1 OR altm >= EPR_ATM { RETURN g. }
    LOCAL rho IS eprRho(altm).
    IF rho <= 0 { RETURN g. }
    LOCAL qdyn IS 0.5 * rho * vr * vr.
    LOCAL vh IS vrelv / vr.
    LOCAL mach IS eprMachFrom(altm, vr, rho).
    LOCAL aoa IS eprAoA(vr).
    LOCAL pr IS eprPrMult(rho * vr).
    // ONE eprPolar for the whole step: this is the integrator's inner loop, and eprCda plus
    // eprCla with the same arguments would evaluate the two lift terms twice.
    LOCAL pol IS eprPolar(aoa, mach).
    // THE ENTRY'S DRAG = eprCdaEntry's: the polar x (1 + eprCdFix) x (1 + eprSbFrac), as the stored drag column
    // (eprTraceSample) and python's integrator (accel(..., sb_entry=True) -> cda_entry). With the raw polar the members
    // fly too little drag below Mach ~6 (the brake's share, the measured correction), their range tables run 12-28 km
    // long, and the guidance, tracking the higher drag reference, falls behind them and saturates short.
    LOCAL fix IS eprAeroFix(aoa, mach).
    LOCAL aDrag IS vh * (-pol[1] * (1 + eprCdFix(mach)) * fix[0] * (1 + eprSbFrac(mach, vr)) * qdyn * pr).
    LOCAL upv IS rv / rmag.
    LOCAL upp IS upv - vh * VDOT(upv, vh).
    IF upp:MAG < 0.000001 { RETURN g + aDrag. }
    SET upp TO upp:NORMALIZED.
    // THE LIFT SIDE VECTOR: a cross product deciding a direction, in a left-handed frame. VCRS(vh, upp), forward x up.
    // The opposite order (up x forward) steers the wrong way; kOS's handedness does not cancel it. Only steering sees
    // this sign: range prediction cares about the magnitude of the turn.
    // NOT `VCRS(vh, upp) * EPR_NSIGN`: EPR_NSIGN is calibrated for the up/east/NORTH frame, not this one, and
    // VCRS(vh,upp) = -VCRS(upp,vh), so an NSIGN of -1 would turn this back into the opposite order.
    LOCAL sd IS VCRS(vh, upp).
    LOCAL b IS bankDeg.
    LOCAL ldir IS upp * COS(b) + sd * SIN(b).
    RETURN g + aDrag + ldir * (pol[0] * fix[1] * qdyn).
}

// ---------------------------------------------------------------- geodesy
// Reference equatorial axes, captured once so eprToGeo has a fixed longitude datum. Built
// from the CURRENT vessel position and the known geo coordinates, so the datum matches
// whatever kOS calls longitude zero.
GLOBAL EPR_GEO_T0 IS 0.          // TIME:SECONDS when the geodesy datum was captured; eprToGeo's rotation is measured from here
GLOBAL EPR_GEO_X IS V(1,0,0).
GLOBAL EPR_GEO_Y IS V(0,1,0).

// Sign of the body-rotation correction in eprToGeo: 1 = subtract omega*tRot, 0 = none. Applied only on the PROPAGATED
// path (eprToGeoInertial); the live path passes tRot 0 (see the notes below).
GLOBAL EPR_ROT_SIGN IS 1.
// ON A LIVE VECTOR THE CORRECTION IS SPURIOUS: KSP's frame turns with the body, so a stationary vessel's vector is
// constant and ARCTAN2 against the captured axes already gives ground longitude; subtracting omega*t double-counts it
// and displaces every position west by exactly omega*t, an error that grows through the entry.

// The rotation offset MUST be applied for a future time: BODY:GEOPOSITIONOF resolves at NOW, and the body turns under a
// 400 s entry (JNSQ 3.3 degrees, 93 km of surface motion), so the live conversion is wrong for a terminal point.
// ==========================================================================================
//  TWO KINDS OF POSITION, TWO FUNCTIONS
//  LIVE, from -SHIP:BODY:POSITION: KSP's frame turns WITH the body, so ARCTAN2 against the captured axes already gives
//    ground longitude. Subtracting omega*t is spurious.
//  PROPAGATED, from Kepler: inertial by construction. The body turns UNDER it by omega*t, so ground longitude =
//    inertial longitude - omega*t. The correction is required.
//  One global scale could only be right for one of the two, so the function names (eprToGeoLive, eprToGeoInertial)
//  carry the distinction: a tRot argument whose correct value depends on where the caller got its vector invites a mistake.
// ==========================================================================================

// The geodesy convention's version, written into family.txt so a family built under one convention cannot be flown
// under another (lib_fam checks it):
//   1 = one eprToGeo with a global scale deciding whether to apply omega*t: right for the live path or the propagated
//       one, never both.
//   2 = eprToGeoLive / eprToGeoInertial: the caller's choice, not a global.
GLOBAL EPR_GEO_VER IS 2.

FUNCTION eprToGeoLive {
    PARAMETER rv.
    RETURN eprToGeoRaw(rv, 0).
}

FUNCTION eprToGeoInertial {
    PARAMETER rv, tRot.
    RETURN eprToGeoRaw(rv, tRot).
}

FUNCTION eprToGeoRaw {
    PARAMETER rv, tRot.
    LOCAL rmag IS rv:MAG.
    LOCAL lat IS ARCSIN(MAX(-1, MIN(1, VDOT(rv:NORMALIZED, EPR_NAXIS)))).
    LOCAL eq IS rv - EPR_NAXIS * VDOT(rv, EPR_NAXIS).
    LOCAL lng IS 0.
    IF eq:MAG > 1 {
        LOCAL e0 IS EPR_GEO_X.
        LOCAL e1 IS EPR_GEO_Y.
        SET lng TO ARCTAN2(VDOT(eq, e1), VDOT(eq, e0))
                   - EPR_ROT_SIGN * EPR_WMAG * tRot * CONSTANT:RADTODEG.
    }
    UNTIL lng <= 180 { SET lng TO lng - 360. }
    UNTIL lng > -180 { SET lng TO lng + 360. }
    RETURN LIST(lat, lng, rmag - EPR_R).
}

// Surface lat/lng/alt -> inertial position, the inverse of eprToGeo at tRot 0. Exists so a
// test can construct a FIXED state without a vessel.
FUNCTION eprGeoToInertial {
    PARAMETER lat, lng, altm.
    LOCAL rm IS EPR_R + altm.
    LOCAL eq IS EPR_GEO_X * COS(lng) + EPR_GEO_Y * SIN(lng).
    RETURN (eq * COS(lat) + EPR_NAXIS * SIN(lat)) * rm.
}

FUNCTION eprGcDist {
    PARAMETER lat1, lng1, lat2, lng2.
    LOCAL h IS SIN((lat2 - lat1) / 2) ^ 2
              + COS(lat1) * COS(lat2) * SIN((lng2 - lng1) / 2) ^ 2.
    RETURN 2 * EPR_R * ARCSIN(MIN(1, SQRT(MAX(h, 0)))) * CONSTANT:DEGTORAD.
}

// Point at a bearing and distance from another. HERE, NOT IN lib_kepler.ks: sock_ops3_jnsq.ks and fam_build.ks load
// lib_plan.ks without lib_kepler.ks, so a lib_plan call to kepDestGeo would be an undefined name in exactly the two files
// that fly. Every file involved loads this one, so this is the only place a shared helper can live. kepDestGeo and
// ops3's destGeo both delegate here, so the formula exists once.
// The local is arcDeg, NOT adD: `add` is a kOS builtin (the manoeuvre-node one) and kerboscript is CASE-INSENSITIVE,
// so a local spelled adD cannot hide it -- a PARSE error, so the whole script fails to load.
FUNCTION eprDestGeo {
    PARAMETER lat1, lng1, brngD, distM.
    LOCAL arcDeg IS distM / EPR_R * CONSTANT:RADTODEG.
    LOCAL lat2 IS ARCSIN(MAX(-1, MIN(1,
        SIN(lat1) * COS(arcDeg) + COS(lat1) * SIN(arcDeg) * COS(brngD)))).
    LOCAL lng2 IS lng1 + ARCTAN2(SIN(brngD) * SIN(arcDeg) * COS(lat1),
                                 COS(arcDeg) - SIN(lat1) * SIN(lat2)).
    UNTIL lng2 <= 180 { SET lng2 TO lng2 - 360. }
    UNTIL lng2 > -180 { SET lng2 TO lng2 + 360. }
    RETURN LIST(lat2, lng2).
}

// Calibrate the two sign conventions against kOS's own NORTH direction. NORTH:VECTOR is a real northward unit vector at
// any latitude, so the dot products below are decisive (at the equator NORTH is parallel to the rotation axis, so the
// first test returns very nearly +/-1); if a kOS release changes the convention, this follows it.
FUNCTION eprInitFrame {
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL nref IS NORTH:VECTOR:NORMALIZED.
    SET EPR_NAXIS TO EPR_WAXIS.
    IF VDOT(EPR_WAXIS, nref) < 0 { SET EPR_NAXIS TO EPR_WAXIS * -1. }
    LOCAL upv IS rv:NORMALIZED.
    LOCAL eastv IS eprOmegaCross(rv).
    IF eastv:MAG < 0.001 { RETURN. }
    SET eastv TO eastv:NORMALIZED.
    SET EPR_NSIGN TO 1.
    IF VDOT(VCRS(upv, eastv), nref) < 0 { SET EPR_NSIGN TO -1. }
}

// Local east and north at a predicted state. East is taken from omega x r, the direction the surface moves and
// therefore unambiguous (it matches VELOCITY:ORBIT - VELOCITY:SURFACE). North then follows from the calibrated
// cross-product sign.
FUNCTION eprEastNorth {
    PARAMETER rv.
    LOCAL upv IS rv:NORMALIZED.
    LOCAL eastv IS eprOmegaCross(rv).
    IF eastv:MAG < 0.001 { RETURN LIST(V(0,0,0), V(0,0,0)). }
    SET eastv TO eastv:NORMALIZED.
    RETURN LIST(eastv, VCRS(upv, eastv) * EPR_NSIGN).
}

FUNCTION eprInitGeo {
    eprInitFrame().
    // STAMP THE DATUM WITH ITS OWN CAPTURE TIME: eprToGeo's rotation correction is measured from this instant. See eprFamTRot.
    SET EPR_GEO_T0 TO TIME:SECONDS.
    eprInitGeoAt(-SHIP:BODY:POSITION, SHIP:GEOPOSITION:LNG).
}

// THE DATUM FROM A POSITION AND ITS LONGITUDE (eprInitGeo's body: rv = -SHIP:BODY:POSITION, rad = SHIP:GEOPOSITION:LNG
// at the moment of capture). Split out so the datum can be re-taken from a given pair, and tested on one.
FUNCTION eprInitGeoAt {
    PARAMETER rv, rad.                       // rad: the longitude of the vessel, as kOS reports it
    LOCAL eq IS rv - EPR_NAXIS * VDOT(rv, EPR_NAXIS).
    IF eq:MAG < 1 { RETURN. }
    LOCAL e IS eq:NORMALIZED.                // radial-equatorial direction at the vessel
    // NO VCRS HERE. The datum needs a direction 90 degrees EAST of e, and VCRS cannot supply it without assuming a
    // handedness: in kOS's left-handed frame VCRS(NAXIS, e) points WEST, which makes longitude westward-positive and the
    // gradient backwards. eprOmegaCross is the verified east (the surface moves east by definition), so the datum is
    // built from it and the handedness never enters.
    LOCAL eastv IS eprOmegaCross(rv).
    IF eastv:MAG < 0.001 { RETURN. }
    SET eastv TO eastv:NORMALIZED.
    // e is GEO_X rotated EAST by rad, so inverting:
    //     GEO_X = e*cos(rad) - east*sin(rad)
    //     GEO_Y = e*sin(rad) + east*cos(rad)      (90 deg east of GEO_X)
    SET EPR_GEO_X TO e * COS(rad) - eastv * SIN(rad).
    SET EPR_GEO_Y TO e * SIN(rad) + eastv * COS(rad).
}

// THE DATUM AGAINST KSP'S FRAME. Above KSP's inverse-rotation altitude (about 76 km on Earth) the world frame is
// INERTIAL: a vector from the body's centre turns against the ground at the body's rate, so a datum captured there is
// right only at its own instant, and eprToGeoLive (no rotation term) drifts east of the vessel by omega x the time since.
// Below that altitude the frame turns WITH the body and the drift stops, frozen at whatever it had grown to. This is the
// datum's error against kOS's own ground longitude of the same vessel (SHIP:GEOPOSITION:LNG, which is right in both
// frames), signed, wrapped to +-180: eprToGeoLive minus the truth, deg.
FUNCTION eprDatumDrift {
    PARAMETER rv, lng.
    LOCAL d IS eprToGeoLive(rv)[1] - lng.
    UNTIL d <= 180 { SET d TO d - 360. }
    UNTIL d > -180 { SET d TO d + 360. }
    RETURN d.
}

// Re-take the datum when it has drifted more than tolDeg; returns the drift it removed (deg), 0 when it left the datum
// alone. The caller must not call this while a family is being built (the integrator's ground positions are measured
// from the datum: eprFamStart's note) or while a solve runs.
FUNCTION eprDatumFollow {
    PARAMETER rv, lng, tolDeg.
    LOCAL d IS eprDatumDrift(rv, lng).
    IF ABS(d) <= tolDeg { RETURN 0. }
    SET EPR_GEO_T0 TO TIME:SECONDS.
    eprInitGeoAt(rv, lng).
    RETURN d.
}


// ---------------------------------------------------------------- incremental integrator
GLOBAL EPR_IR   IS V(0,0,0).     // integration state
GLOBAL EPR_IV   IS V(0,0,0).
GLOBAL EPR_IT   IS 0.
GLOBAL EPR_IBK  IS 0.
GLOBAL EPR_IDT  IS 2.            // s, the integration step
GLOBAL EPR_IOK  IS FALSE.
GLOBAL EPR_IDONE IS FALSE.
GLOBAL EPR_STEPS IS 0.
// Previous integration state, kept so the terminal crossing can be INTERPOLATED rather than
// overshot. See eprIntRun.
GLOBAL EPR_PR IS V(0,0,0).
GLOBAL EPR_PV IS V(0,0,0).
GLOBAL EPR_PT IS 0.
GLOBAL EPR_PA IS 0.
GLOBAL EPR_PVR IS 0.
GLOBAL EPR_HAVEPREV IS FALSE.

// On Sol every trial of the bank solve flies the LATERAL logic from the vehicle's lateral state: the reversals on the
// azimuth error with the deadband, the minimum bank, the flare / TAEM ramp, the slew. The family build and the shadow
// prediction keep the plain bank. The lateral path has no Nz arrest and no pre-entry switch.
GLOBAL EPR_PRED_LATERAL IS SHIP:BODY:NAME = "Earth".   // Sol's Earth only
GLOBAL EPR_LAT_ON IS FALSE.       // armed by eprSolveStart, dropped when the solve ends (and by eprFamStart)
GLOBAL EPR_LAT_TROT IS 0.         // the rotation epoch of the trial's t = 0
GLOBAL EPR_LAT_SIGN IS 0.
GLOBAL EPR_LAT_REV IS 0.
GLOBAL EPR_LAT_CMD IS 0.
GLOBAL EPR_LAT_RATE IS 0.

FUNCTION eprLatReset {            // the lateral state = the vehicle's (the guidance's) at the solve
    SET EPR_LAT_SIGN TO EPR_GS_SIGN.
    SET EPR_LAT_REV TO EPR_GS_REV.
    SET EPR_LAT_CMD TO EPR_GS_BANK.
    SET EPR_LAT_RATE TO EPR_GS_RATE.
}

FUNCTION eprLatBank {             // the signed, slewed bank
    PARAMETER bankDeg, rv, vv, t.
    LOCAL altm IS rv:MAG - EPR_R.
    LOCAL vrel IS (vv - eprOmegaCross(rv)):MAG.
    LOCAL az IS eprAzErrorAt(rv, vv, EPR_LAT_TROT + t, EPR_TGT_LAT, EPR_TGT_LNG).   // a FUTURE state: rotated
    IF EPR_LAT_SIGN = 0 { SET EPR_LAT_SIGN TO CHOOSE 1 IF az >= 0 ELSE -1. }
    LOCAL rho IS eprRho(altm).
    LOCAL mach IS eprMachFrom(altm, vrel, rho).
    LOCAL db IS eprAzDeadband(mach, EPR_LAT_REV = 0).
    LOCAL ns IS EPR_LAT_SIGN.
    IF az > db { SET ns TO 1. } ELSE IF az < -db { SET ns TO -1. }
    IF ns <> EPR_LAT_SIGN {
        SET EPR_LAT_REV TO EPR_LAT_REV + 1.
        SET EPR_LAT_SIGN TO ns.
    }
    LOCAL want IS EPR_LAT_SIGN * bankDeg.
    IF EPR_USE_MIN_BANK AND EPR_LAT_SIGN * az > 0 AND rho > 0 AND vrel > 1 {
        LOCAL pr IS eprPrMult(rho * vrel).
        IF eprCdaEntry(eprAoA(vrel), mach, vrel) * 0.5 * rho * vrel * vrel * pr >= EPR_GUID_DRAG_INIT {
            LOCAL fl IS eprMinBank(mach, az).
            IF ABS(want) < fl { SET want TO EPR_LAT_SIGN * fl. }
        }
    }
    LOCAL sg IS CHOOSE 1 IF want >= 0 ELSE -1.
    SET want TO sg * eprBankWithFlare(want, vrel).
    IF vrel <= EPR_BANK_STOP_SPEED { SET want TO 0. }
    LOCAL sl IS eprBankSlew(EPR_LAT_CMD, want, EPR_LAT_RATE, EPR_IDT).
    SET EPR_LAT_CMD TO sl[0].
    SET EPR_LAT_RATE TO sl[1].
    RETURN EPR_LAT_CMD.
}

FUNCTION eprIntStart {
    PARAMETER rv, vv, bankDeg.
    IF EPR_TRACE_ON { eprTraceReset(). }
    SET EPR_IR TO rv. SET EPR_IV TO vv. SET EPR_IT TO 0. SET EPR_IARC TO 0.
    SET EPR_IBK TO bankDeg. SET EPR_IOK TO FALSE. SET EPR_IDONE TO FALSE.
    SET EPR_HAVEPREV TO FALSE.
    IF EPR_LAT_ON { eprLatReset(). }
}

// Advance up to `budget` RK2 steps. Returns TRUE when the integration has terminated.
FUNCTION eprIntRun {
    PARAMETER budget.
    LOCAL k IS 0.
    // EPR_FAM_ADD (2): a family build runs on to EPR_FAM_EXT_V (the TAEM bank ramp still ends at EPR_TAEM_VEL); the
    // solver and the planner stop at EPR_TAEM_VEL
    LOCAL famAdd IS EPR_FAM_ACTIVE AND EPR_FAM_ADD.
    LOCAL vstop IS EPR_TAEM_VEL.
    IF famAdd { SET vstop TO EPR_FAM_EXT_V. }
    UNTIL k >= budget {
        LOCAL rmag IS EPR_IR:MAG.
        LOCAL altm IS rmag - EPR_R.
        LOCAL vr IS (EPR_IV - eprOmegaCross(EPR_IR)):MAG.
        IF altm <= EPR_TAEM_ALT OR (altm < EPR_ATM AND vr <= vstop) {
            // INTERPOLATE TO THE CROSSING, do not return the first state past it: overshooting quantises the terminal
            // point by up to a full step (about 2 km of range at 900 m/s and dt 2), and that is not smooth in bank, so the
            // secant thrashes and can return a bank far from the root. Interpolating costs one division.
            IF EPR_HAVEPREV {
                LOCAL fr IS 1.
                IF altm <= EPR_TAEM_ALT AND EPR_PA > EPR_TAEM_ALT {
                    SET fr TO (EPR_PA - EPR_TAEM_ALT) / MAX(EPR_PA - altm, 0.000000001).
                } ELSE IF EPR_PVR > vstop {
                    SET fr TO (EPR_PVR - vstop) / MAX(EPR_PVR - vr, 0.000000001).
                }
                SET fr TO MAX(0, MIN(1, fr)).
                SET EPR_IR TO EPR_PR + (EPR_IR - EPR_PR) * fr.
                SET EPR_IV TO EPR_PV + (EPR_IV - EPR_PV) * fr.
                SET EPR_IT TO EPR_PT + (EPR_IT - EPR_PT) * fr.
                SET altm TO EPR_IR:MAG - EPR_R.
                SET vr TO (EPR_IV - eprOmegaCross(EPR_IR)):MAG.
                // EPR_FAM_ADD (2): the arc to the crossing too (python's carry-on to exactly FAM_EXT_V), so the members'
                // range to go ends at the crossing, not up to a step past it
                IF famAdd { SET EPR_FAM_ARC TO EPR_PARC + (EPR_IARC - EPR_PARC) * fr. }
            }
            // EPR_FAM_ADD (2): AN END SAMPLE at the crossing (range to go 0). A member is sampled every EPR_TRACE_EVERY
            // steps (10 s; python every 1 s), and a lookup below the last sample holds it, so without this the
            // excess (the range from EPR_TAEM_VEL on) could read a sample up to 10 s early. None when the last
            // sample already sits at or below this speed (taken at the state past the crossing).
            IF famAdd AND EPR_TRACE_ON {
                IF EPR_TR_V:LENGTH = 0 { eprTraceSample(EPR_IR, EPR_IV). }
                ELSE IF EPR_TR_V[EPR_TR_V:LENGTH - 1] > vr { eprTraceSample(EPR_IR, EPR_IV). }
            }
            SET EPR_TERM_ALT TO altm.
            SET EPR_TERM_VEL TO vr.
            IF altm <= EPR_TAEM_ALT + 1 { SET EPR_TERM_WHY TO "taemalt". }
            ELSE { SET EPR_TERM_WHY TO "taemvel". }
            SET EPR_IOK TO TRUE. SET EPR_IDONE TO TRUE. RETURN TRUE.
        }
        IF altm < 0 OR EPR_IT > 2500 {
            SET EPR_TERM_ALT TO altm.
            SET EPR_TERM_VEL TO vr.
            IF altm < 0 { SET EPR_TERM_WHY TO "ground". } ELSE { SET EPR_TERM_WHY TO "timeout". }
            SET EPR_IOK TO FALSE. SET EPR_IDONE TO TRUE. RETURN TRUE.
        }
        SET EPR_PR TO EPR_IR. SET EPR_PV TO EPR_IV. SET EPR_PT TO EPR_IT.
        SET EPR_PA TO altm. SET EPR_PVR TO vr. SET EPR_HAVEPREV TO TRUE.
        SET EPR_PARC TO EPR_IARC.         // EPR_FAM_ADD (2): the arc at this state, for the crossing
        // PER-STEP BANK. EPR_IBK is a constant for the solver; the family needs a bank that changes with state (preentry
        // hold, then the member's bank, capped by the Nz arrest ramp and the terminal flare). Hooked here so there is one
        // integrator loop, with eprIntRun's interpolate-to-crossing logic.
        LOCAL bnk IS EPR_IBK.
        IF EPR_FAM_ACTIVE { SET bnk TO eprFamBankAt(altm, vr). }
        IF EPR_LAT_ON { SET bnk TO eprLatBank(EPR_IBK, EPR_IR, EPR_IV, EPR_IT). }   // PRED_LATERAL
        LOCAL a1 IS eprAccel(EPR_IR, EPR_IV, bnk).
        LOCAL rm IS EPR_IR + EPR_IV * (0.5 * EPR_IDT).
        LOCAL vm IS EPR_IV + a1 * (0.5 * EPR_IDT).
        LOCAL a2 IS eprAccel(rm, vm, bnk).
        SET EPR_FAM_BANK_NOW TO bnk.
        // EPR_FAM_ADD: the members' bank column BEFORE the TAEM ramp (python's col 7): the step ramps
        // the reference roll once, where the column after the ramp had it ramped twice
        IF famAdd { SET EPR_FAM_BANK_NOW TO EPR_FAM_BANK_PRE. }
        // Ground ARC accumulated during the run, ALWAYS (not only during a family build) and not reconstructed from
        // lat/lng afterwards: the stored family needs no lat/lng columns, and the deorbit planner needs the PATH LENGTH of an
        // entry to solve the burn time geometrically (the path is nearly constant across burn phase, because the FPA
        // schedule fixes the interface speed and flight path angle) instead of searching over integrations.
        LOCAL arcVrel IS EPR_IV - eprOmegaCross(EPR_IR).
        LOCAL arcVh IS VXCL(EPR_IR:NORMALIZED, arcVrel):MAG.
        SET EPR_IARC TO EPR_IARC + arcVh * EPR_IDT * (EPR_R / EPR_IR:MAG).
        IF EPR_FAM_ACTIVE { SET EPR_FAM_ARC TO EPR_IARC. }
        SET EPR_IR TO EPR_IR + vm * EPR_IDT.
        SET EPR_IV TO EPR_IV + a2 * EPR_IDT.
        SET EPR_IT TO EPR_IT + EPR_IDT.
        // Trace sampling, gated so the solve iterations pay nothing for it.
        IF EPR_TRACE_ON {
            SET EPR_TRACE_K TO EPR_TRACE_K + 1.
            // EPR_FAM_ADD (2): a family build samples EVERY STEP below EPR_FAM_FINE_V: the excess and the end of the
            // inversion read the members near EPR_TAEM_VEL, where 10 s between samples is coarse (python: 1 s)
            IF famAdd AND vr < EPR_FAM_FINE_V { SET EPR_TRACE_K TO EPR_TRACE_EVERY. }
            IF EPR_TRACE_K >= EPR_TRACE_EVERY {
                SET EPR_TRACE_K TO 0.
                eprTraceSample(EPR_IR, EPR_IV).
            }
        }
        SET k TO k + 1.
        SET EPR_STEPS TO EPR_STEPS + 1.
    }
    RETURN FALSE.
}

// ============================================================================
//  THE REFERENCE FAMILY  --  built once at boot, then no integration in entry
// ============================================================================
//  A solve (eprSolveStart / eprSolveRun) is about 3800 acceleration evaluations; the family is about 14,700 for all
//  eight members, ONCE, in orbit, and after that the entry loop does table lookups only.
//  MEMBERS ARE WHOLE TRAJECTORIES, NOT PERTURBATIONS OF ONE. Every member is a constant-bank entry actually integrated,
//  so flyability is structural. A uniform scale of one drag curve fails (bank changes the SHAPE of D(V), not its level),
//  and so does a pointwise blend between the corridor boundaries: drag is not a free variable at each speed, it is a
//  state you have to fly to.
//  MEMBERS SHARE THE PREENTRY PHASE: each flies EPR_PREENTRY_BANK until guidance initiate, then its own bank. Otherwise
//  they diverge from t=0, none passes through the state the vehicle is in when tracking begins, and the ends of the
//  family are unreachable.
//  BUILT INCREMENTALLY, one member at a time, reusing eprIntStart/eprIntRun, so there is one integrator loop and the
//  interpolate-to-crossing logic is not written twice.

GLOBAL EPR_FAM_BANKS IS LIST(0, 12, 24, 36, 48, 60, 72, 85).
GLOBAL EPR_FAM_ORDER IS LIST(0, 7, 3, 5, 1, 6, 2, 4).
                                 // BUILD ORDER, bracketing rather than sequential (indices into EPR_FAM_BANKS: 0, 85, 36,
                                 // 60, 12, 72, 24, 48). A build can run out of time, and in sequential order the members
                                 // that finish are all LOW bank, the long-range end, so a vehicle needing to SHED range
                                 // would saturate 'high' immediately. In bracketing order two members already span the
                                 // full range, so running out of time degrades resolution instead of removing half the
                                 // footprint. The family is SORTED BY BANK after building, because eprFamInvert relies on
                                 // remaining range decreasing monotonically across members.
                                 // EIGHT members is the knee of the worst-case interpolation error across a sweep of u:
                                 // 3 members 9.88 percent, 4 -> 6.03, 6 -> 1.50, 8 -> 0.77, 9 -> 0.71.
// ---- THE FAMILY EXTENSION (EPR_FAM_ADD), A DEVIATION from the FSSR: ON by default; FALSE = the plain family guidance.
//  Python's twin is entry_predict.py FAM_ADD (flown there on 12 offline entries); sync_check pairs the scalars. Four
//  pieces:
//   (1) THE HAC REFERENCE: the flight code arms the plan's HAC after eprArm (eprArmHac); the heading error is then to the
//       HAC centre and the range to go = gc(position, origin) - gc(target, origin), the origin = the point the target was
//       built from (the FTP's threshold; a TAL / AOA aim's site) -- eprFamRngTo;
//   (2) THE EXTENSION: a family build's members run on to EPR_FAM_EXT_V (eprIntRun: the TAEM bank ramp still ends at
//       EPR_TAEM_VEL, the arc is interpolated to the crossing, an end sample there, every step sampled below
//       EPR_FAM_FINE_V) and the range to go carries the middle member's range from EPR_TAEM_VEL on to there
//       (eprFamExcess), so the inversion still has range to work with at the handover;
//   (3) THE SERVO: the flown member shifted past the EPR_FAM_SRV_BANK member (an overbank or underbank) so that the
//       state's own inverted u comes onto it (eprFamServo);
//   (4) THE BAND: the alpha modulation's band between EPR_AM_V_FULL_FAM and EPR_AM_V_ZERO_FAM (eprAmBand).
GLOBAL EPR_FAM_ADD IS TRUE.
GLOBAL EPR_FAM_EXT_V IS 700.     // m/s: (2) the members' end in a family build
GLOBAL EPR_FAM_FINE_V IS 900.    // m/s: (2) a family build samples every step below this (kOS only: python samples every 1 s)
GLOBAL EPR_FAM_SRV_BANK IS 60.   // deg: (3) the servo's target member
GLOBAL EPR_FAM_SRV_K IS 1.       // (3) the gain: the member shift per unit of u away from the target (3 -> 1, the
                                 //   owner 11-07: at 3 it limit-cycled the SLF entry, drag 40-48 % short of the reference)
GLOBAL EPR_FAM_SRV_DMAX IS 0.15. // (3) the largest shift, in u
GLOBAL EPR_FAM_SRV_V1 IS 2000.   // m/s: (3) full gain above this (surface speed) ...
GLOBAL EPR_FAM_SRV_V0 IS 1000.   // ... none below this, linear between
GLOBAL EPR_FAM_UTOP IS 1.         // (3) the servo's top u, and eprFamRef's: 1 = the top member (python fly_family's min(1.0,
                                 //   ...)); a TAL's overbank arms 1 + EPR_FAM_SRV_DMAX (lib_tal talV4nArm): past 1 the
                                 //   references run on along the top segment
GLOBAL EPR_FAM_EEXT IS 0.        // m: (2) the excess on the range to go (eprFamAddPrep, once per family)
GLOBAL EPR_FAM_UT IS -1.         // (3) the servo's target u (eprFamAddPrep); -1 = none
GLOBAL EPR_FAM_ADD_PREP IS FALSE.    // eprFamAddPrep has run on this family (eprArm, eprGuidReset and eprFamFinish clear it)
GLOBAL EPR_FAM_EXTD IS FALSE.    // (2) eprFamAddPrep: this family's members run on to EPR_FAM_EXT_V (else no excess)
GLOBAL EPR_HAC_ON IS FALSE.      // (1) the plan's HAC is armed (eprArmHac; eprArm and eprGuidReset clear it)
GLOBAL EPR_HAC_LAT IS 0.         // (1) its centre ...
GLOBAL EPR_HAC_LNG IS 0.
GLOBAL EPR_HAC_YSGN IS 0.        // ... its side (+1: right of the landing direction) ...
GLOBAL EPR_HAC_YAIM IS 0.        // ... and the aim's offset off the centreline that chose it (m, + right)
GLOBAL EPR_ORG_LAT IS 0.         // (1) the point the target was built from
GLOBAL EPR_ORG_LNG IS 0.
GLOBAL EPR_PARC IS 0.            // (2) eprIntRun: the arc at the previous step's state
GLOBAL EPR_FAM_BANK_PRE IS 0.    // eprFamBankAt's bank before the TAEM ramp: the bank column
GLOBAL EPR_PREENTRY_BANK IS 60.  // deg held from the interface to guidance initiate, by BOTH the members and the vehicle
                                 //   Not 0 as in 2.15.1: our preentry is long, and wings level would spend 19-54 percent
                                 //   of the footprint before guidance can influence anything. 60 is what the deorbit
                                 //   planner solves the burn against (one number, two files).
GLOBAL EPR_GUID_DRAG_INIT IS 0.914.
                                 // m/s^2 = 0.132 g of TOTAL load factor (2.22.1), expressed as drag under an assumed L/D
                                 //   of ~1.0. Not really a drag constant: at L/D 1.3 the same 0.132 g is 0.79. Ours is
                                 //   1.008 at the initiate condition, so it transfers, but it moves if the AoA schedule
                                 //   there does.

// ---- Nz ARREST (see eprDMaxNz for why Nz is not an actuator limit) --------------------
// Bank 85 is SAFE EARLY (at 3600 m/s it makes 2.198 m/s^2 against a 17.3 ceiling); it is illegal only because of where
// it puts you LATER, so the constraint is scheduled on ALTITUDE: the critical point's altitude is nearly constant across
// orbits where velocity, Mach, q and energy all spread, so one constant covers the envelope.
// A SOFT KNEE, RAMPED. A flat clip collapses the family's upper half onto one bank and the inversion loses all
// authority; proportional scaling cuts the low members, which are never at risk; a knee applied as a STEP moves the
// reference roll by about 14 deg in one interpolation and rails the correction.
GLOBAL EPR_NZ_ARREST_TOP   IS 46000.  // m: compression begins
GLOBAL EPR_NZ_ARREST_ALT   IS 41000.  // m: full compression
GLOBAL EPR_NZ_ARREST_KNEE  IS 55.     // deg at or below this: untouched
GLOBAL EPR_NZ_ARREST_SLOPE IS 0.45.   // compression on the excess above the knee

// ---- terminal flare ------------------------------------------------------------------
GLOBAL EPR_BANK_STOP_SPEED IS 762.    // m/s: roll WINGS LEVEL below this
                                      //   Declared here, not in lib_guide.ks: the family builder in this file uses it too,
                                      //   so it is declared once, in the lower module (otherwise the last file loaded wins).
GLOBAL EPR_BANK_FLARE_SPEED IS 0.     // m/s below which bank is compressed; 0 = DISABLED
                                      //   Disabled: the lever plateaus at about 21.5 km of handover altitude and costs
                                      //   10-15 km of accuracy, and the arrival altitude does not depend on the aim.
GLOBAL EPR_BANK_FLARE_MAX   IS 55.
GLOBAL EPR_BANK_FLARE_SLOPE IS 0.45.  // a knee, not a cap, for the same reason as the arrest

GLOBAL EPR_XR_USABLE IS 0.90.         // usable fraction of a member's lateral reach

// ---- build state ---------------------------------------------------------------------
GLOBAL EPR_FAM_ACTIVE IS FALSE.  // gates the per-step bank hook inside eprIntRun
RUNONCEPATH("0:/lib/lib_logsw.ks").                  // SOCK_LOG: eprFamDump writes only when the logs are on
GLOBAL EPR_FAM_DUMP_FILE IS "0:/logs/fam_dump.csv".  // the family's own range table
GLOBAL EPR_IARC IS 0.            // m, ground arc flown by the current integration: the entry's PATH LENGTH (reset by eprIntStart)
GLOBAL EPR_FAM_ARC IS 0.
GLOBAL EPR_FAM_BANK_NOW IS 0.
GLOBAL EPR_FAM_MEMBER_BANK IS 0. // the bank THIS member holds after guidance initiate
GLOBAL EPR_FAM_STARTED IS FALSE. // has this member reached guidance initiate yet
GLOBAL EPR_FAM IS LIST().        // one entry per member: LIST(bank, V, D, S, RNG, BK)
GLOBAL EPR_FAM_HINT IS LIST().   // per member: eprFamAt's last bracket (only a starting point: see there)
GLOBAL EPR_FAM_I IS 0.           // member being built
GLOBAL EPR_FAM_READY IS FALSE.
GLOBAL EPR_FAM_OK IS FALSE.      // TRUE when the build produced USABLE members (READY = finished, OK = worth flying)
                                 //   A build from a state that never enters the atmosphere completes normally with eight
                                 //   EMPTY members (every integration times out above EPR_ATM with nothing sampled).
GLOBAL EPR_FAM_WHY IS "".        // "" | "no-entry" | "too-few" | "partial N of 8"
GLOBAL EPR_FAM_PARTIAL IS FALSE. // TRUE when fewer than EPR_FAM_BANKS members are usable

GLOBAL EPR_FAM_KEPLER IS TRUE.   // solve the vacuum coast instead of integrating it
GLOBAL EPR_FAM_TCOAST IS 0.      // seconds skipped by the Kepler coast -- THE EPOCH SHIFT
GLOBAL EPR_FAM_TBUILD IS 0.      // TIME:SECONDS at which eprFamStart was called
GLOBAL EPR_FAM_R0 IS V(0,0,0).
GLOBAL EPR_FAM_V0 IS V(0,0,0).

// The bank this member flies at this state. Called once per RK2 step during a family build.
FUNCTION eprFamBankAt {
    PARAMETER altm, vr.
    // THE GUIDANCE-INITIATE LATCH IS CHECKED HERE, PER STEP, not once per eprFamRun call: a call advances up to `budget`
    // steps, so a latch tested once per call would leave every member flying EPR_PREENTRY_BANK for hundreds of steps
    // past initiate.
    IF NOT EPR_FAM_STARTED AND altm < EPR_ATM AND vr > 1 {
        LOCAL rho IS eprRho(altm).
        IF rho > 0 {
            LOCAL pr IS eprPrMult(rho * vr).
            IF eprCdaEntry(eprAoA(vr), eprMachFrom(altm, vr, rho), vr) * 0.5 * rho * vr * vr * pr
                   >= EPR_GUID_DRAG_INIT {
                SET EPR_FAM_STARTED TO TRUE.
            }
        }
    }
    IF NOT EPR_FAM_STARTED { SET EPR_FAM_BANK_PRE TO EPR_PREENTRY_BANK. RETURN EPR_PREENTRY_BANK. }
    LOCAL b IS EPR_FAM_MEMBER_BANK.
    // Nz arrest: ramped, and only on the excess above the knee.
    IF altm < EPR_NZ_ARREST_TOP AND b > EPR_NZ_ARREST_KNEE {
        LOCAL w IS 1.
        IF altm > EPR_NZ_ARREST_ALT {
            SET w TO (EPR_NZ_ARREST_TOP - altm) / (EPR_NZ_ARREST_TOP - EPR_NZ_ARREST_ALT).
        }
        SET b TO EPR_NZ_ARREST_KNEE
                 + (b - EPR_NZ_ARREST_KNEE) * (1 - w * (1 - EPR_NZ_ARREST_SLOPE)).
    }
    SET EPR_FAM_BANK_PRE TO b.        // EPR_FAM_ADD: the bank before the ramp, for the bank column
    RETURN eprBankWithFlare(b, vr).
}

// The terminal bank schedule the guidance will actually fly. THE BUILDER AND THE VEHICLE MUST BOTH APPLY THIS: if only
// the builder did, the vehicle would hold a bank where its own reference member flies another, and the miss would grow
// several-fold.
// THE TAEM BANK RAMP: proportional from EPR_BANK_TAEM_SPEED down to EPR_BANK_TAEM_LIMIT at EPR_TAEM_VEL (the bank-85
// line ends at 30). 30, not 40: at most PHILMSUP and slewable in four TAEM cycles.
GLOBAL EPR_BANK_TAEM_LIMIT IS 30.     // deg
GLOBAL EPR_BANK_TAEM_SPEED IS 1400.   // m/s surface-relative where the ramp begins (0 = off)
FUNCTION eprBankWithFlare {
    PARAMETER bankDeg, vr, taemRamp IS TRUE.   // taemRamp FALSE: the flare and the stop only (the flown bank profile)
    LOCAL b IS ABS(bankDeg).
    IF EPR_BANK_FLARE_SPEED > 0 AND vr <= EPR_BANK_FLARE_SPEED AND b > EPR_BANK_FLARE_MAX {
        SET b TO EPR_BANK_FLARE_MAX + (b - EPR_BANK_FLARE_MAX) * EPR_BANK_FLARE_SLOPE.
    }
    IF taemRamp AND EPR_BANK_TAEM_SPEED > 0 AND vr < EPR_BANK_TAEM_SPEED {
        LOCAL span IS EPR_BANK_TAEM_SPEED - EPR_TAEM_VEL.
        LOCAL w IS 1.
        IF span > 0 { SET w TO (EPR_BANK_TAEM_SPEED - vr) / span. }
        SET w TO MAX(0, MIN(1, w)).
        SET b TO b * (1 - w * (1 - EPR_BANK_TAEM_LIMIT / EPR_BANK_MAX)).
    }
    IF vr <= EPR_BANK_STOP_SPEED { SET b TO 0. }
    RETURN b.
}

// ---- KEPLER COAST TO THE INTERFACE ----------------------------------------------------
// Above EPR_ATM there is no aerodynamics, so the trajectory is a pure two-body conic and has a CLOSED FORM: solving it is
// both faster and more accurate than integrating it. Every member of the family flies the SAME vacuum arc, so
// integrating the coast would repeat it EIGHT TIMES OVER. The wall-time saving is small (vacuum steps are the cheap
// ones: eprAccel returns gravity immediately above EPR_ATM); the real argument is accuracy. Hundreds of RK2 steps
// accumulate truncation error over an arc with an exact answer, and because all eight members share the coast, any
// error there is a BIAS COMMON TO THE WHOLE FAMILY rather than scatter between members.

// f-and-g propagation through eccentric anomaly. Returns LIST(position, velocity).
// Trig convention follows kepAt: angles are carried in RADIANS and converted on the way into
// kOS's degree-taking SIN/COS.
FUNCTION eprKepState {
    PARAMETER rv, vv, dt.
    LOCAL r0m IS rv:MAG.
    LOCAL v0m IS vv:MAG.
    LOCAL sma IS 1 / (2 / r0m - v0m * v0m / EPR_MU).
    IF sma <= 0 { RETURN LIST(rv, vv). }          // hyperbolic: not a case we coast on
    LOCAL sig0 IS VDOT(rv, vv) / SQRT(EPR_MU).
    LOCAL ecosE IS 1 - r0m / sma.
    LOCAL esinE IS sig0 / SQRT(sma).
    LOCAL e0R IS ARCTAN2(esinE, ecosE) * CONSTANT:DEGTORAD.
    LOCAL ecc IS SQRT(ecosE * ecosE + esinE * esinE).
    LOCAL n IS SQRT(EPR_MU / (sma * sma * sma)).
    LOCAL mR IS e0R - esinE + n * dt.
    LOCAL eaR IS mR.
    // Newton converges in a handful of passes for the near-circular eccentricities this coast
    // uses; the cap is a safety stop, not an expected count. It breaks on |d| < 1e-13.
    LOCAL i IS 0.
    UNTIL i >= 20 {
        SET i TO i + 1.
        LOCAL eaD IS eaR * CONSTANT:RADTODEG.
        LOCAL fv IS eaR - ecc * SIN(eaD) - mR.
        LOCAL fp IS 1 - ecc * COS(eaD).
        IF ABS(fp) < 0.00000000000001 { BREAK. }
        LOCAL d IS fv / fp.
        SET eaR TO eaR - d.
        IF ABS(d) < 0.0000000000001 { BREAK. }
    }
    LOCAL deaR IS eaR - e0R.
    LOCAL deaD IS deaR * CONSTANT:RADTODEG.
    LOCAL ff IS 1 - sma / r0m * (1 - COS(deaD)).
    LOCAL gg IS dt - SQRT(sma * sma * sma / EPR_MU) * (deaR - SIN(deaD)).
    LOCAL rNew IS rv * ff + vv * gg.
    LOCAL rNm IS rNew:MAG.
    LOCAL fd IS 0 - SQRT(EPR_MU * sma) / (rNm * r0m) * SIN(deaD).
    LOCAL gd IS 1 - sma / rNm * (1 - COS(deaD)).
    RETURN LIST(rNew, rv * fd + vv * gd).
}

FUNCTION eprJ2Grav {                        // vacuum gravity with J2
    PARAMETER rv.
    LOCAL rmag IS rv:MAG.
    RETURN rv * (-EPR_MU / (rmag * rmag * rmag)) + eprJ2Accel(rv, rmag).
}

FUNCTION eprJ2ToEI {                        // the coast to the interface under J2: RK4 at 30 s, the crossing by bisection
    PARAMETER rv, vv.                       //   of the last step (the closed-form Kepler coast has no J2)
    LOCAL tgt IS EPR_R + EPR_ATM.
    LOCAL t IS 0.
    LOCAL h IS 30.                          // s, the RK4 step
    UNTIL t > 20000 {
        LOCAL st IS eprJ2Step(rv, vv, h).
        IF st[0]:MAG <= tgt {
            LOCAL lo IS 0. LOCAL hi IS h.
            FROM { LOCAL k IS 0. } UNTIL k >= 20 STEP { SET k TO k + 1. } DO {     // 30 s / 2^20: 3e-5 s
                LOCAL mid IS 0.5 * (lo + hi).
                IF eprJ2Step(rv, vv, mid)[0]:MAG > tgt { SET lo TO mid. } ELSE { SET hi TO mid. }
            }
            LOCAL fin IS eprJ2Step(rv, vv, hi).
            RETURN LIST(fin[0], fin[1], t + hi).
        }
        SET rv TO st[0]. SET vv TO st[1]. SET t TO t + h.
    }
    RETURN LIST(rv, vv, -1).                // never descends
}

FUNCTION eprJ2Step {                        // one RK4 step of the vacuum motion
    PARAMETER rv, vv, h.
    LOCAL a1 IS eprJ2Grav(rv).
    LOCAL r2 IS rv + vv * (h / 2). LOCAL v2 IS vv + a1 * (h / 2).
    LOCAL a2 IS eprJ2Grav(r2).
    LOCAL r3 IS rv + v2 * (h / 2). LOCAL v3 IS vv + a2 * (h / 2).
    LOCAL a3 IS eprJ2Grav(r3).
    LOCAL r4 IS rv + v3 * h. LOCAL v4 IS vv + a3 * h.
    LOCAL a4 IS eprJ2Grav(r4).
    RETURN LIST(rv + (vv + v2 * 2 + v3 * 2 + v4) * (h / 6), vv + (a1 + a2 * 2 + a3 * 2 + a4) * (h / 6)).
}

// Coast to the atmospheric interface. Returns LIST(position, velocity, elapsed).
// Bisection on time: radius is monotone through a descending coast, so there is one crossing.
FUNCTION eprKepToEI {
    PARAMETER rv, vv.
    IF EPR_J2_ON { RETURN eprJ2ToEI(rv, vv). }
    LOCAL tgt IS EPR_R + EPR_ATM.
    IF rv:MAG <= tgt { RETURN LIST(rv, vv, 0). }
    LOCAL lo IS 0.
    LOCAL hi IS 10.
    LOCAL guard IS 0.
    UNTIL eprKepState(rv, vv, hi)[0]:MAG <= tgt OR guard > 20 {
        SET hi TO hi * 2.
        SET guard TO guard + 1.
    }
    IF eprKepState(rv, vv, hi)[0]:MAG > tgt { RETURN LIST(rv, vv, -1). }  // never descends
    // 34 halvings of a <=20,000 s bracket leave ~1e-6 s, nine orders below the 2 s integration step that follows; 60 would
    // cost nearly twice the work (each bisection step runs a full Newton solve inside eprKepState).
    LOCAL k IS 0.
    UNTIL k >= 34 {
        SET k TO k + 1.
        LOCAL mid IS 0.5 * (lo + hi).
        IF eprKepState(rv, vv, mid)[0]:MAG > tgt { SET lo TO mid. } ELSE { SET hi TO mid. }
    }
    LOCAL st IS eprKepState(rv, vv, hi).
    RETURN LIST(st[0], st[1], hi).
}

// ---- THE BUILD IN C# (the KAL/S coprocessor, GameData/KALS_Coproc: ADDONS:KALS:FAMSTART) ------------------------------
// ON by default (a failed addon costs nothing: kOS then builds the family itself). With EPR_FAM_CS and the addon
// installed,
// eprFamStart hands the build to the addon (coproc/Fam.cs: a line-for-line port of this file's build path and of
// lib_tal.ks's TAL copies): it solves the coast at once (EPR_FAM_R0 / V0 / TCOAST as kOS sets them) and flies the eight members on
// their own worker threads; eprFamRun (talFamRun) polls it and, when it is done, EPR_FAM gets the eight members in build
// order with the integrator's globals as kOS's build leaves them, and eprFamFinish runs as usual. ANY addon failure (no
// addon, an older DLL, FAMSTART's error, a member's error) turns the switch off for the rest of the flight, says why
// (EPR_FAM_CS_ERR) and kOS builds the family from the start. A direct eprFamFinish call (a host's timeout) takes the
// members the addon has done, in build order.
// The model is read from this file's globals at the start (eprFamCsLex): a later SET (eprMassTrack mid-build) reaches the
// kOS build's later members, not the addon's (which are done within a second).
IF NOT (DEFINED EPR_FAM_CS) { GLOBAL EPR_FAM_CS IS TRUE. }               // TRUE: the addon builds the family
GLOBAL EPR_FAM_CS_ERR IS "".      // why the addon is off ("" = it is not)
GLOBAL EPR_FAM_CS_ON IS FALSE.    // this build is the addon's
GLOBAL EPR_FAM_CS_HAVE IS FALSE.  // EPR_FAM_CS_H holds this build's handle
GLOBAL EPR_FAM_CS_H IS 0.
GLOBAL EPR_FAM_CS_N IS 0.         // members taken from it
GLOBAL EPR_FAM_CS_MS IS -1.       // its wall time, ms (the coast not included)
GLOBAL EPR_FAM_CS_SAY IS "kOS".   // one line on how the last family was built (fam_dump.csv)
GLOBAL EPR_FAM_CS_TAL IS LIST().  // lib_tal's talFamStart: LIST(TAL_A0, TAL_VALPD1, TAL_VALPD2), a TAL build's alpha
GLOBAL EPR_FAM_CS_ISTAL IS FALSE. // this build is a TAL's (eprFamCsTake sets TAL_FAM_VI then)
GLOBAL EPR_FAM_CS_RV IS V(0,0,0). // the build's start (the fallback starts kOS's build from it)
GLOBAL EPR_FAM_CS_VV IS V(0,0,0).

FUNCTION eprFamCsOff {             // the addon off for the rest of the flight: kOS builds
    PARAMETER why.
    SET EPR_FAM_CS_ERR TO why.
    SET EPR_FAM_CS TO FALSE.
    SET EPR_FAM_CS_ON TO FALSE.
    SET EPR_FAM_CS_HAVE TO FALSE.
    SET EPR_FAM_CS_SAY TO "kOS (the C# build off: " + why + ")".
}

FUNCTION eprFamCsLex {             // everything the build reads, by its name without EPR_ (coproc/Fam.cs FamConsts)
    PARAMETER rv, vv.
    LOCAL l IS LEXICON("rv", rv, "vv", vv, "tal", EPR_FAM_CS_TAL,
        "R", EPR_R, "MU", EPR_MU, "ATM", EPR_ATM, "WMAG", EPR_WMAG, "WAXIS", EPR_WAXIS, "J2", EPR_J2, "R_J2", EPR_R_J2,
        "J2_ON", EPR_J2_ON, "TAEM_VEL", EPR_TAEM_VEL, "TAEM_ALT", EPR_TAEM_ALT, "GAMMA", EPR_GAMMA, "MASS_K", EPR_MASS_K,
        "TRIM_FD", EPR_TRIM_FD, "TRIM_FL", EPR_TRIM_FL, "FLAP_X", EPR_FLAP_X, "FLAP_KF", EPR_FLAP_KF).
    l:ADD("PAR_W_WING", EPR_PAR_W_WING). l:ADD("PAR_W_FUS", EPR_PAR_W_FUS). l:ADD("PAR_W_CTL", EPR_PAR_W_CTL).
    l:ADD("K_LIFT", EPR_K_LIFT). l:ADD("K_PAR", EPR_K_PAR). l:ADD("PAR_SHIFT", EPR_PAR_SHIFT). l:ADD("PR_SHARE", EPR_PR_SHARE).
    l:ADD("RHO", EPR_RHO). l:ADD("LIFT_CURVE", EPR_LIFT_CURVE). l:ADD("LIFT_MACH", EPR_LIFT_MACH).
    l:ADD("WING_PAR_A", EPR_WING_PAR_A). l:ADD("WING_PAR_M", EPR_WING_PAR_M). l:ADD("FUS_PAR_A", EPR_FUS_PAR_A).
    l:ADD("FUS_PAR_M", EPR_FUS_PAR_M). l:ADD("CTL_PAR_A", EPR_CTL_PAR_A). l:ADD("CTL_PAR_M", EPR_CTL_PAR_M).
    l:ADD("PSEUDORE", EPR_PSEUDORE). l:ADD("SB_FRAC", EPR_SB_FRAC). l:ADD("CD_FIX", EPR_CD_FIX). l:ADD("AERO_FIX", EPR_AERO_FIX). l:ADD("FLAP_TAB", EPR_FLAP_TAB).
    l:ADD("AOA_HIGH", EPR_AOA_HIGH). l:ADD("AOA_LOW", EPR_AOA_LOW). l:ADD("AOA_HIGH_SPEED", EPR_AOA_HIGH_SPEED).
    l:ADD("AOA_LOW_SPEED", EPR_AOA_LOW_SPEED). l:ADD("AOA_RAMP_ON", EPR_AOA_RAMP_ON). l:ADD("AOA_RAMP_V_HI", EPR_AOA_RAMP_V_HI).
    l:ADD("AOA_RAMP_V_LO", EPR_AOA_RAMP_V_LO). l:ADD("AOA_RAMP_HI", EPR_AOA_RAMP_HI). l:ADD("AOA_RAMP_LO", EPR_AOA_RAMP_LO).
    l:ADD("SB_ON", EPR_SB_ON). l:ADD("SB_V", EPR_SB_V). l:ADD("SB_V_FULL", EPR_SB_V_FULL).
    l:ADD("FAM_ADD", EPR_FAM_ADD). l:ADD("FAM_KEPLER", EPR_FAM_KEPLER). l:ADD("IDT", EPR_IDT).
    l:ADD("FAM_EXT_V", EPR_FAM_EXT_V). l:ADD("FAM_FINE_V", EPR_FAM_FINE_V). l:ADD("TRACE_EVERY", EPR_TRACE_EVERY).
    l:ADD("TRACE_MAX", EPR_TRACE_MAX). l:ADD("GUID_DRAG_INIT", EPR_GUID_DRAG_INIT). l:ADD("PREENTRY_BANK", EPR_PREENTRY_BANK).
    l:ADD("NZ_ARREST_TOP", EPR_NZ_ARREST_TOP). l:ADD("NZ_ARREST_ALT", EPR_NZ_ARREST_ALT).
    l:ADD("NZ_ARREST_KNEE", EPR_NZ_ARREST_KNEE). l:ADD("NZ_ARREST_SLOPE", EPR_NZ_ARREST_SLOPE).
    l:ADD("BANK_FLARE_SPEED", EPR_BANK_FLARE_SPEED). l:ADD("BANK_FLARE_MAX", EPR_BANK_FLARE_MAX).
    l:ADD("BANK_FLARE_SLOPE", EPR_BANK_FLARE_SLOPE). l:ADD("BANK_TAEM_SPEED", EPR_BANK_TAEM_SPEED).
    l:ADD("BANK_TAEM_LIMIT", EPR_BANK_TAEM_LIMIT). l:ADD("BANK_MAX", EPR_BANK_MAX). l:ADD("BANK_STOP_SPEED", EPR_BANK_STOP_SPEED).
    l:ADD("FAM_BANKS", EPR_FAM_BANKS). l:ADD("FAM_ORDER", EPR_FAM_ORDER).
    l:ADD("HINT_RHO", EPR_HINT_RHO). l:ADD("FAM_BANK_NOW", EPR_FAM_BANK_NOW).
    l:ADD("CE", CONSTANT:E). l:ADD("ATMTOKPA", CONSTANT:ATMTOKPA). l:ADD("DEGTORAD", CONSTANT:DEGTORAD).
    l:ADD("RADTODEG", CONSTANT:RADTODEG).
    RETURN l.
}

FUNCTION eprFamCsStart {           // the addon's build (EPR_FAM_CS_ON), or the switch off
    PARAMETER rv, vv.
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("FAMSTART") { SET why TO "the KAL/S addon has no family build (an older KalsCoproc.dll)". }
    ELSE {
        LOCAL h IS ADDONS:KALS:FAMSTART(eprFamCsLex(rv, vv)).
        IF h:ERROR <> "" { SET why TO "FAMSTART: " + h:ERROR. }
        ELSE {
            SET EPR_FAM_CS_H TO h.
            SET EPR_FAM_CS_HAVE TO TRUE.
            SET EPR_FAM_R0 TO h:R0.
            SET EPR_FAM_V0 TO h:V0.
            SET EPR_FAM_TCOAST TO h:TCOAST.
            SET EPR_FAM_CS_ON TO TRUE.
            RETURN.
        }
    }
    eprFamCsOff(why).
}

FUNCTION eprFamCsTake {            // the addon's members up to n (build order) into EPR_FAM, and the build's globals
    PARAMETER n.
    LOCAL h IS EPR_FAM_CS_H.
    UNTIL EPR_FAM_CS_N >= n {
        LOCAL mem IS h:MEMBER(EPR_FAM_CS_N).
        IF mem:LENGTH <> 7 { RETURN FALSE. }
        EPR_FAM:ADD(mem).
        SET EPR_STEPS TO EPR_STEPS + h:END(EPR_FAM_CS_N)["STEPS"].
        SET EPR_FAM_CS_N TO EPR_FAM_CS_N + 1.
    }
    SET EPR_FAM_I TO EPR_FAM_CS_N.
    IF n > 0 {                     // as kOS's build leaves them: the last member's state and trace
        LOCAL ee IS h:END(n - 1).
        LOCAL tr IS h:TRACE(n - 1).
        IF ee:LENGTH = 0 OR tr:LENGTH <> 6 { RETURN FALSE. }
        SET EPR_IR TO ee["IR"]. SET EPR_IV TO ee["IV"]. SET EPR_IT TO ee["IT"]. SET EPR_IARC TO ee["IARC"].
        SET EPR_IBK TO ee["IBK"]. SET EPR_IOK TO ee["IOK"]. SET EPR_IDONE TO ee["IDONE"].
        SET EPR_PR TO ee["PR"]. SET EPR_PV TO ee["PV"]. SET EPR_PT TO ee["PT"]. SET EPR_PA TO ee["PA"]. SET EPR_PVR TO ee["PVR"].
        SET EPR_HAVEPREV TO ee["HAVEPREV"]. SET EPR_PARC TO ee["PARC"]. SET EPR_FAM_ARC TO ee["FAM_ARC"].
        SET EPR_FAM_BANK_NOW TO ee["BANK_NOW"]. SET EPR_FAM_BANK_PRE TO ee["BANK_PRE"]. SET EPR_FAM_STARTED TO ee["STARTED"].
        SET EPR_FAM_MEMBER_BANK TO ee["MEMBER_BANK"]. SET EPR_TRACE_K TO ee["TRACE_K"].
        SET EPR_TERM_ALT TO ee["TERM_ALT"]. SET EPR_TERM_VEL TO ee["TERM_VEL"]. SET EPR_TERM_WHY TO ee["TERM_WHY"].
        SET EPR_HINT_RHO TO ee["HINT_RHO"].
        IF EPR_FAM_CS_ISTAL AND (DEFINED TAL_FAM_VI) { SET TAL_FAM_VI TO ee["TAL_FAM_VI"]. }
        SET EPR_TR_V TO tr[0]. SET EPR_TR_D TO tr[1]. SET EPR_TR_S TO tr[2].
        SET EPR_TR_A TO tr[3]. SET EPR_TR_ARC TO tr[4]. SET EPR_TR_BK TO tr[5].
    }
    SET EPR_FAM_CS_MS TO h:MS.
    RETURN TRUE.
}

FUNCTION eprFamCsRun {             // eprFamRun / talFamRun while the addon builds: TRUE when the family is in
    LOCAL h IS EPR_FAM_CS_H.
    IF NOT h:DONE { RETURN FALSE. }
    LOCAL why IS "".
    IF NOT h:OK { SET why TO "the build: " + h:ERROR. }
    ELSE IF NOT eprFamCsTake(h:N) { SET why TO "the members could not be read". }
    IF why <> "" {
        eprFamCsOff(why).          // kOS builds it from the start
        SET EPR_FAM TO LIST().
        SET EPR_FAM_I TO 0.
        SET EPR_FAM_TCOAST TO 0.   // the addon's coast is dropped with it (eprFamKosStart sets R0 / V0 always, TCOAST on a coast)
        eprFamKosStart(EPR_FAM_CS_RV, EPR_FAM_CS_VV).
        RETURN FALSE.
    }
    SET EPR_FAM_ACTIVE TO FALSE.
    SET EPR_TRACE_ON TO FALSE.
    SET EPR_FAM_READY TO TRUE.
    SET EPR_FAM_CS_SAY TO "C# (" + EPR_FAM_CS_N + " members on threads, " + ROUND(EPR_FAM_CS_MS, 1) + " ms)".
    eprFamFinish().
    RETURN TRUE.
}

FUNCTION eprFamCount {             // the members a finish now would have: EPR_FAM, or under the addon the ones it has done
    IF EPR_FAM_CS_ON AND EPR_FAM_CS_HAVE AND EPR_FAM_CS_H:OK { RETURN MAX(EPR_FAM:LENGTH, EPR_FAM_CS_H:PREFIX). }
    RETURN EPR_FAM:LENGTH.
}

FUNCTION eprFamCsFinish {          // eprFamFinish's first step
    IF EPR_FAM_CS_ON {             // a direct call while the addon builds (a host's timeout): the members it has done
        IF EPR_FAM_CS_N = 0 AND EPR_FAM_CS_H:OK {
            IF eprFamCsTake(EPR_FAM_CS_H:PREFIX) {
                SET EPR_FAM_CS_SAY TO "C# (" + EPR_FAM_CS_N + " members done at the host's finish)".
            }
        }
        SET EPR_FAM_CS_ON TO FALSE.
    }
    IF NOT EPR_FAM_CS_HAVE AND EPR_FAM_CS_ERR = "" {
        SET EPR_FAM_CS_SAY TO "kOS".
    }
}

// ---- the incremental build -----------------------------------------------------------
// eprFamStart(r, v) then eprFamRun(budget) until it returns TRUE. One member at a time; each
// uses eprIntStart/eprIntRun so there is exactly one integrator in this file.
FUNCTION eprFamStart {
    PARAMETER rv, vv.
    SET EPR_LAT_ON TO FALSE.              // the family flies the plain bank
    SET EPR_FAM TO LIST().
    SET EPR_FAM_HINT TO LIST().
    SET EPR_FAM_I TO 0.
    SET EPR_FAM_READY TO FALSE.
    // SKIP THE VACUUM COAST ANALYTICALLY: if the start is above the atmosphere, solve the conic to the interface instead of
    // integrating it eight times. EPR_FAM_TCOAST IS THE EPOCH SHIFT: EPR_FAM_R0 is not at the caller's epoch, and anything
    // converting it to a ground position must add it, or the longitude comes out rotated by the length of the coast.
    SET EPR_FAM_TCOAST TO 0.
    SET EPR_FAM_TBUILD TO TIME:SECONDS.
    // THE BUILD IN C# (the block above EPR_FAM_CS): the addon does the coast at once and the members on its threads
    SET EPR_FAM_CS_ON TO FALSE.
    SET EPR_FAM_CS_HAVE TO FALSE.
    SET EPR_FAM_CS_N TO 0.
    SET EPR_FAM_CS_RV TO rv.
    SET EPR_FAM_CS_VV TO vv.
    SET EPR_FAM_CS_ISTAL TO EPR_FAM_CS_TAL:LENGTH = 3.   // talFamStart clears EPR_FAM_CS_TAL before the members are taken
    IF EPR_FAM_CS { eprFamCsStart(rv, vv). }
    IF EPR_FAM_CS_ON { RETURN. }
    eprFamKosStart(rv, vv).
}

// eprFamStart's kOS half: the coast, then the first member (also the fallback when the addon's build fails)
FUNCTION eprFamKosStart {
    PARAMETER rv, vv.
    IF EPR_FAM_KEPLER AND rv:MAG > EPR_R + EPR_ATM {
        LOCAL ei IS eprKepToEI(rv, vv).
        IF ei[2] >= 0 {
            SET EPR_FAM_R0 TO ei[0].
            SET EPR_FAM_V0 TO ei[1].
            SET EPR_FAM_TCOAST TO ei[2].
        } ELSE {
            SET EPR_FAM_R0 TO rv.
            SET EPR_FAM_V0 TO vv.
        }
    } ELSE {
        SET EPR_FAM_R0 TO rv.
        SET EPR_FAM_V0 TO vv.
    }
    eprFamBeginMember().
}

FUNCTION eprFamBeginMember {
    SET EPR_FAM_MEMBER_BANK TO EPR_FAM_BANKS[EPR_FAM_ORDER[EPR_FAM_I]].
    SET EPR_FAM_STARTED TO FALSE.
    SET EPR_FAM_ARC TO 0.   // eprIntStart resets EPR_IARC, which this mirrors
    SET EPR_FAM_ACTIVE TO TRUE.
    SET EPR_TRACE_ON TO TRUE.
    eprIntStart(EPR_FAM_R0, EPR_FAM_V0, EPR_FAM_MEMBER_BANK).
}

// Advance the build. Returns TRUE when every member is stored.
FUNCTION eprFamRun {
    PARAMETER budget.
    IF EPR_FAM_READY { RETURN TRUE. }
    IF EPR_FAM_CS_ON { RETURN eprFamCsRun(). }     // the addon's build (the block above EPR_FAM_CS)
    // The guidance-initiate latch lives in eprFamBankAt, which runs per STEP -- see there.
    IF eprIntRun(budget) {
        eprFamStoreMember().
        SET EPR_FAM_I TO EPR_FAM_I + 1.
        IF EPR_FAM_I >= EPR_FAM_BANKS:LENGTH {
            SET EPR_FAM_ACTIVE TO FALSE.
            SET EPR_TRACE_ON TO FALSE.
            SET EPR_FAM_READY TO TRUE.
            // VALIDATE: a build from a state that does not reach the atmosphere finishes cleanly with every member empty;
            // without this the first lookup would index an empty list and fail far from the cause.
            eprFamFinish().
            RETURN TRUE.
        }
        eprFamBeginMember().
    }
    RETURN FALSE.
}

// Copy the finished trace into the family, converting cumulative arc into RANGE TO GO, which can only be done backwards
// from the terminal point. SAMPLES BEFORE GUIDANCE INITIATE ARE DROPPED: the member is only defined from there, and
// speed is not monotone before initiate (it rises as gravity outruns drag), so an interpolator that assumes monotone
// speed would read the wrong branch.
FUNCTION eprFamStoreMember {
    // ALTITUDE IS COLUMN 6, FOR DIAGNOSIS (EPR_TR_A records it at every trace sample): it answers "is the vehicle at the
    // altitude the family expects at this speed?" without reimplementing the integrator. It is APPENDED, NOT INSERTED:
    // eprFamAt takes a column index, so columns 1-5 must not move. A file-loaded family has no column 6, which
    // eprFamDump checks for rather than assuming.
    LOCAL vs IS LIST(). LOCAL ds IS LIST(). LOCAL ss IS LIST().
    LOCAL rg IS LIST(). LOCAL bk IS LIST(). LOCAL alts IS LIST().
    LOCAL n IS EPR_TR_V:LENGTH.
    IF n = 0 {
        EPR_FAM:ADD(LIST(EPR_FAM_MEMBER_BANK, vs, ds, ss, rg, bk, alts)).
        RETURN.
    }
    LOCAL arcEnd IS EPR_FAM_ARC.
    LOCAL i IS 0.
    UNTIL i >= n {
        IF EPR_TR_D[i] >= EPR_GUID_DRAG_INIT {
            vs:ADD(EPR_TR_V[i]).
            ds:ADD(EPR_TR_D[i]).
            ss:ADD(EPR_TR_S[i]).
            rg:ADD(arcEnd - EPR_TR_ARC[i]).
            bk:ADD(EPR_TR_BK[i]).
            alts:ADD(EPR_TR_A[i]).
        }
        SET i TO i + 1.
    }
    EPR_FAM:ADD(LIST(EPR_FAM_MEMBER_BANK, vs, ds, ss, rg, bk, alts)).
}

// Drop unusable members, sort what is left by bank, and judge whether it is flyable. CALLED WHETHER THE BUILD FINISHED
// OR NOT: ops3 calls it on the timeout path too, because members that DID complete are good and a partial family
// beats none. The outcomes (EPR_FAM_WHY):
//   "no-entry"  every member empty: the trajectory does not reach the atmosphere, which on a post-burn vehicle means THE
//               DEORBIT UNDERPERFORMED and periapsis is still above it. Guidance cannot fix that; it needs another burn.
//   "too-few"   fewer than two usable members; the inversion needs two to interpolate between.
//   ""          usable. EPR_FAM_PARTIAL says whether it is the full eight.
FUNCTION eprFamFinish {
    eprFamCsFinish().                    // a running C# build hands over what it has
    LOCAL keep IS LIST().
    LOCAL mi IS 0.
    UNTIL mi >= EPR_FAM:LENGTH {
        IF EPR_FAM[mi][1]:LENGTH >= 6 { keep:ADD(EPR_FAM[mi]). }
        SET mi TO mi + 1.
    }
    // insertion sort by bank -- the list is at most eight long and eprFamInvert requires
    // remaining range to decrease monotonically across members, which bank order gives.
    LOCAL i IS 1.
    UNTIL i >= keep:LENGTH {
        LOCAL j IS i.
        UNTIL j < 1 OR keep[j-1][0] <= keep[j][0] {
            LOCAL t IS keep[j-1].
            SET keep[j-1] TO keep[j].
            SET keep[j] TO t.
            SET j TO j - 1.
        }
        SET i TO i + 1.
    }
    SET EPR_FAM TO keep.
    SET EPR_FAM_HINT TO LIST().
    SET EPR_FAM_ADD_PREP TO FALSE.          // a new family: eprFamAddPrep runs again
    SET EPR_FAM_PARTIAL TO (keep:LENGTH < EPR_FAM_BANKS:LENGTH).
    IF keep:LENGTH = 0 {
        SET EPR_FAM_OK TO FALSE.
        SET EPR_FAM_WHY TO "no-entry".
    } ELSE IF keep:LENGTH < 2 {
        SET EPR_FAM_OK TO FALSE.
        SET EPR_FAM_WHY TO "too-few".
    } ELSE {
        SET EPR_FAM_OK TO TRUE.
        SET EPR_FAM_WHY TO CHOOSE "" IF NOT EPR_FAM_PARTIAL
                           ELSE ("partial " + keep:LENGTH + " of " + EPR_FAM_BANKS:LENGTH).
    }
    SET EPR_FAM_READY TO TRUE.
    eprFamDump().
}

// Write the family's own range table to disk, once, at build time (the table is fixed from then on). The guidance
// publishes fam_u and fam_dref per tick but not the TABLE they come from, so when the inversion returns a u that looks
// wrong, only the table can say whether the inversion or the ranges it inverts are at fault.
FUNCTION eprFamDump {
    IF NOT SOCK_LOG { RETURN. }   // the logs off (lib_logsw)
    IF EXISTS(EPR_FAM_DUMP_FILE) { DELETEPATH(EPR_FAM_DUMP_FILE). }
    LOG "member,bank,samples,arc_end_km,v_first,v_last" TO EPR_FAM_DUMP_FILE.
    LOCAL mi IS 0.
    UNTIL mi >= EPR_FAM:LENGTH {
        LOCAL mem IS EPR_FAM[mi].
        LOCAL vs IS mem[1].
        LOCAL rg IS mem[4].
        LOCAL nn IS vs:LENGTH.
        LOG mi + "," + ROUND(mem[0], 1) + "," + nn + ","
            + ROUND(rg[0] / 1000, 2) + "," + ROUND(vs[0], 1) + ","
            + ROUND(vs[nn - 1], 1) TO EPR_FAM_DUMP_FILE.
        SET mi TO mi + 1.
    }
    // and the range table at the speeds guidance will actually ask about
    LOG "vrel,m0,m1,m2,m3,m4,m5,m6,m7" TO EPR_FAM_DUMP_FILE.
    LOCAL vq IS 3600.
    UNTIL vq < 900 {
        LOCAL row IS "" + vq.
        LOCAL k IS 0.
        UNTIL k >= EPR_FAM:LENGTH {
            SET row TO row + "," + ROUND(eprFamAt(k, vq, 4) / 1000, 1).
            SET k TO k + 1.
        }
        LOG row TO EPR_FAM_DUMP_FILE.
        SET vq TO vq - 200.
    }

    // ALTITUDE PER MEMBER: compare a flight's logged altitude at a given speed against the member whose bank it was
    // flying. If the members sit consistently HIGHER at the same speed, the vehicle is in denser air than the family
    // assumes, drags more and covers less ground. Guarded: a family read from file has five columns and no altitude.
    IF EPR_FAM:LENGTH > 0 AND EPR_FAM[0]:LENGTH >= 7 {
        LOG " " TO EPR_FAM_DUMP_FILE.
        LOG "ALT_KM at velocity" TO EPR_FAM_DUMP_FILE.
        LOG "vrel,m0,m1,m2,m3,m4,m5,m6,m7" TO EPR_FAM_DUMP_FILE.
        LOCAL va IS 3600.
        UNTIL va < 900 {
            LOCAL arow IS "" + va.
            LOCAL j IS 0.
            UNTIL j >= EPR_FAM:LENGTH {
                SET arow TO arow + "," + ROUND(eprFamAt(j, va, 6) / 1000, 2).
                SET j TO j + 1.
            }
            LOG arow TO EPR_FAM_DUMP_FILE.
            SET va TO va - 100.
        }
    } ELSE {
        LOG " " TO EPR_FAM_DUMP_FILE.
        LOG "# no altitude column -- this family came from a file, which stores five" TO EPR_FAM_DUMP_FILE.
    }
    // EPR_FAM_ADD: the excess, the servo target and whether the members run on to EPR_FAM_EXT_V (eprFamAddPrep)
    IF EPR_FAM_ADD {
        eprFamAddPrep().
        LOG " " TO EPR_FAM_DUMP_FILE.
        LOG "# family additions: excess " + ROUND(EPR_FAM_EEXT, 0) + " m, servo target u " + ROUND(EPR_FAM_UT, 4)
            + ", members to " + EPR_FAM_EXT_V + " m/s " + EPR_FAM_EXTD TO EPR_FAM_DUMP_FILE.
    }
    LOG "# C# build: " + EPR_FAM_CS_SAY TO EPR_FAM_DUMP_FILE.
}

// ---- lookups: this is all the entry loop does ----------------------------------------
// Interpolate one member on SPEED. Speed falls monotonically from guidance initiate onward,
// which is why the pre-initiate samples are dropped in eprFamStoreMember.
FUNCTION eprFamAt {
    PARAMETER mi, vr, col.
    LOCAL vs IS EPR_FAM[mi][1].
    LOCAL cs IS EPR_FAM[mi][col].
    LOCAL n IS vs:LENGTH.
    IF n = 0 { RETURN 0. }
    IF vr >= vs[0] { RETURN cs[0]. }
    IF vr <= vs[n-1] { RETURN cs[n-1]. }
    // THE SCAN STARTS AT THIS MEMBER'S LAST BRACKET: a scan from sample 1 on every call is about 17k opcodes a cycle late
    // in the entry. Speed falls, so the bracket moves a sample or none per cycle; searched both ways from the hint, the
    // result is the same first i with vs[i] <= vr as a scan from 1 (the samples strictly decrease: eprFamStoreMember
    // keeps the falling part), whatever the hint.
    UNTIL EPR_FAM_HINT:LENGTH > mi { EPR_FAM_HINT:ADD(1). }
    LOCAL i IS MAX(1, MIN(n - 1, EPR_FAM_HINT[mi])).
    IF vs[i] <= vr {
        UNTIL i <= 1 OR vs[i - 1] > vr { SET i TO i - 1. }
    } ELSE {
        UNTIL vs[i] <= vr { SET i TO i + 1. }
    }
    SET EPR_FAM_HINT[mi] TO i.
    LOCAL f IS (vs[i-1] - vr) / MAX(vs[i-1] - vs[i], 0.000000001).
    RETURN cs[i-1] + (cs[i] - cs[i-1]) * f.
}

// Interpolate ACROSS members. u in [0,1] spans the family; col 2 = drag, 3 = sink,
// 4 = range to go, 5 = flown bank.
FUNCTION eprFamRef {
    PARAMETER vr, u, col.
    LOCAL uu IS MAX(0, MIN(EPR_FAM_UTOP, u)).   // past 1 (EPR_FAM_UTOP > 1: a TAL's overbank) the top segment runs on, f > 1
    LOCAL x IS uu * (EPR_FAM:LENGTH - 1).
    LOCAL i IS MIN(FLOOR(x), EPR_FAM:LENGTH - 2).
    LOCAL f IS x - i.
    RETURN eprFamAt(i, vr, col) * (1 - f) + eprFamAt(i + 1, vr, col) * f.
}

// Range-to-go on the line for an arbitrary BANK at a velocity, interpolating between the two bracketing members. The
// TRAJ display's prediction box needs it: the box sits on the bank guidance wants, which is almost never exactly a
// member's bank. Banks ascend and range descends across the family, so the interpolation weight is taken on bank and
// applied to range, not the other way round.
FUNCTION eprTrajBankRange {
    PARAMETER bank, vr.
    LOCAL n IS EPR_FAM:LENGTH.
    IF n < 2 { RETURN 0. }
    IF bank <= EPR_FAM[0][0] { RETURN eprFamAt(0, vr, 4). }
    IF bank >= EPR_FAM[n-1][0] { RETURN eprFamAt(n-1, vr, 4). }
    LOCAL i IS 1.
    UNTIL i >= n {
        IF bank <= EPR_FAM[i][0] {
            LOCAL b0 IS EPR_FAM[i-1][0].
            LOCAL b1 IS EPR_FAM[i][0].
            LOCAL f IS (bank - b0) / MAX(b1 - b0, 0.000001).
            LOCAL r0 IS eprFamAt(i-1, vr, 4).
            LOCAL r1 IS eprFamAt(i, vr, 4).
            RETURN r0 + (r1 - r0) * f.
        }
        SET i TO i + 1.
    }
    RETURN eprFamAt(n-1, vr, 4).
}

// REFERENCE ROLL (2.12): the bank that holds member u at this speed, and the feedforward the Hdot correction rides on.
// A LOOKUP, NOT THE MEMBER'S NOMINAL BANK: the Nz arrest ramp clips the upper members, so returning the nominal would
// hand back 85 where the member is flying 50 and make the correction absorb 35 deg of feedforward error. Without a
// feedforward the correction is a bare loop starting from zero bank. 2.12's own formula,
// cos(sigma) = (g - V^2/r)/((L/D) D_ref), is UNUSABLE on this airframe: no bank satisfies H-double-dot = 0 at that
// drag, because it presumes equilibrium glide and this vehicle is not in it for most of the entry.
FUNCTION eprFamRoll {
    PARAMETER vr, u.
    RETURN eprFamRef(vr, u, 5).
}

// THE INVERSION: find u whose remaining range at this speed equals rngToGo. Remaining range is strictly DECREASING in
// u (member 0 is wings level and flies furthest), so there is exactly one crossing.
// Returns LIST(u, sat) with sat "" | "low" | "high": "low" when even wings level cannot stretch far enough, "high"
// when even the top member cannot shed enough.
FUNCTION eprFamInvert {
    PARAMETER vr, rngToGo.
    LOCAL n IS EPR_FAM:LENGTH.
    LOCAL r0 IS eprFamAt(0, vr, 4).
    IF rngToGo >= r0 { RETURN LIST(0, "low"). }
    LOCAL rn IS eprFamAt(n-1, vr, 4).
    IF rngToGo <= rn { RETURN LIST(1, "high"). }
    LOCAL i IS 1.
    UNTIL i >= n {
        LOCAL ri IS eprFamAt(i, vr, 4).
        IF ri <= rngToGo {
            LOCAL rp IS eprFamAt(i-1, vr, 4).
            LOCAL span IS rp - ri.
            LOCAL f IS 0.
            IF ABS(span) > 0.000000001 { SET f TO (rp - rngToGo) / span. }
            RETURN LIST((i - 1 + f) / (n - 1), "").
        }
        SET i TO i + 1.
    }
    RETURN LIST(1, "high").
}

// ---- THE FAMILY EXTENSION (the block above EPR_FAM_ADD) --------------------------------------------------------
// (2) + (3), once per family (the first guidance step with the family ready, the TAL bug, the family dump): the excess
// the range to go carries = the middle member's range at EPR_TAEM_VEL (python: the middle of the members' list, in bank
// order), and the servo's target u = the u of member bank EPR_FAM_SRV_BANK (u = i / (n - 1) at member i, linear
// between; none outside the family or on banks that do not rise). A FAMILY WITHOUT THE EXTENSION (a family.txt built
// before it, or with EPR_FAM_ADD off) gets no excess: its members end at EPR_TAEM_VEL, where the excess would read
// whatever range its last sample holds; the test is the middle member's last speed (EPR_FAM_EXT_V when extended: the end
// sample; about EPR_TAEM_VEL, a step either side, when not). No family yet (under two members): nothing latched, again
// at the next call. The members' search hints are kept as they were.
FUNCTION eprFamAddPrep {
    SET EPR_FAM_EEXT TO 0.
    SET EPR_FAM_UT TO -1.
    SET EPR_FAM_EXTD TO FALSE.
    LOCAL n IS EPR_FAM:LENGTH.
    IF n < 2 { RETURN. }
    SET EPR_FAM_ADD_PREP TO TRUE.
    LOCAL h IS FLOOR(n / 2).
    LOCAL vsm IS EPR_FAM[h][1].
    IF vsm:LENGTH > 0 {
        IF vsm[vsm:LENGTH - 1] < 0.5 * (EPR_TAEM_VEL + EPR_FAM_EXT_V) { SET EPR_FAM_EXTD TO TRUE. }
    }
    IF EPR_FAM_EXTD {
        LOCAL hs IS EPR_FAM_HINT:COPY.
        LOCAL ex IS LIST().
        LOCAL mi IS 0.
        UNTIL mi >= n {
            ex:ADD(eprFamAt(mi, EPR_TAEM_VEL, 4)).
            SET mi TO mi + 1.
        }
        SET EPR_FAM_HINT TO hs.
        IF MOD(n, 2) = 1 { SET EPR_FAM_EEXT TO ex[h]. } ELSE { SET EPR_FAM_EEXT TO 0.5 * (ex[h - 1] + ex[h]). }
    }
    LOCAL ut IS -1.
    LOCAL i IS 0.
    UNTIL i >= n - 1 {
        LOCAL b0 IS EPR_FAM[i][0].
        LOCAL b1 IS EPR_FAM[i + 1][0].
        IF b1 <= b0 { RETURN. }
        IF ut < 0 AND b0 <= EPR_FAM_SRV_BANK AND EPR_FAM_SRV_BANK <= b1 {
            SET ut TO (i + (EPR_FAM_SRV_BANK - b0) / (b1 - b0)) / (n - 1).
        }
        SET i TO i + 1.
    }
    SET EPR_FAM_UT TO ut.
}

// (2): the excess the range to go carries; 0 without EPR_FAM_ADD. Call with the family ready.
FUNCTION eprFamExcess {
    IF NOT EPR_FAM_ADD { RETURN 0. }
    IF NOT EPR_FAM_ADD_PREP { eprFamAddPrep(). }
    RETURN EPR_FAM_EEXT.
}

// (1): the range to go the family is inverted on, from a ground position, before the excess: with the plan's HAC armed
// gc(position, origin) - gc(target, origin), signed already (it goes negative past the target's distance from the
// origin); else the great-circle range to the target.
FUNCTION eprFamRngTo {
    PARAMETER glat, glng, tgtLat, tgtLng.
    IF EPR_FAM_ADD AND EPR_HAC_ON {
        RETURN eprGcDist(glat, glng, EPR_ORG_LAT, EPR_ORG_LNG) - eprGcDist(tgtLat, tgtLng, EPR_ORG_LAT, EPR_ORG_LNG).
    }
    RETURN eprGcDist(glat, glng, tgtLat, tgtLng).
}

// (3) THE SERVO: the flown u shifted past EPR_FAM_UT (an overbank or underbank) so that the state's own u comes onto it:
// EPR_FAM_SRV_K per unit of u away, at most EPR_FAM_SRV_DMAX, full above
// EPR_FAM_SRV_V1 and none below EPR_FAM_SRV_V0 (surface speed), kept in 0..EPR_FAM_UTOP (1; a TAL's overbank 1.15); u as
// it is without the switch or a target.
FUNCTION eprFamServo {
    PARAMETER u, vr.
    IF (NOT EPR_FAM_ADD) OR EPR_FAM_UT < 0 { RETURN u. }
    LOCAL fv IS 0.
    IF vr >= EPR_FAM_SRV_V1 { SET fv TO 1. }
    ELSE IF vr > EPR_FAM_SRV_V0 { SET fv TO (vr - EPR_FAM_SRV_V0) / (EPR_FAM_SRV_V1 - EPR_FAM_SRV_V0). }
    RETURN MAX(0, MIN(EPR_FAM_UTOP, u + MAX(0 - EPR_FAM_SRV_DMAX, MIN(EPR_FAM_SRV_DMAX, EPR_FAM_SRV_K * fv * (u - EPR_FAM_UT))))).
}

// (4) THE BAND: the alpha modulation's band at this surface speed, deg (EPR_AM_V_FULL / _ZERO, or their EPR_FAM_ADD pair).
FUNCTION eprAmBand {
    PARAMETER vr.
    LOCAL vf IS EPR_AM_V_FULL.
    LOCAL vz IS EPR_AM_V_ZERO.
    IF EPR_FAM_ADD { SET vf TO EPR_AM_V_FULL_FAM. SET vz TO EPR_AM_V_ZERO_FAM. }
    RETURN EPR_AM_LIM * MAX(0, MIN(1, (vr - vz) / (vf - vz))).
}

// (1) THE PLAN'S HAC, armed by the flight code right after eprArm (the aim = the armed target): the centre from the plan
// runway's threshold (thrLat, thrLng) and landing heading hdg, TAEM's HAC x (xc, m, negative: where the glideslope
// reaches the HAC height, from the runway's aim) and radius (rf, m), on the OVERHEAD side -- the far side from the aim's
// offset off the centreline, as taem_sim pick_ysgn and lib_land at TAEM's start -- latched for the flight; and the point
// the target was built from (orgLat, orgLng). The TAEM numbers come in as arguments, so this file stays standalone. The
// geometry is python's (the offline model's hac_centre: taem_sim great_circle / dest_point = eprGcDist,
// the bearing below, eprDestGeo).
FUNCTION eprArmHac {
    PARAMETER thrLat, thrLng, hdg, xc, rf, orgLat, orgLng.
    LOCAL dA IS eprGcDist(thrLat, thrLng, EPR_TGT_LAT, EPR_TGT_LNG).
    LOCAL dl IS EPR_TGT_LNG - thrLng.
    LOCAL bA IS ARCTAN2(SIN(dl) * COS(EPR_TGT_LAT),
                        COS(thrLat) * SIN(EPR_TGT_LAT) - SIN(thrLat) * COS(EPR_TGT_LAT) * COS(dl)).
    SET EPR_HAC_YAIM TO dA * SIN(bA - hdg).
    SET EPR_HAC_YSGN TO -1.
    IF EPR_HAC_YAIM < 0 { SET EPR_HAC_YSGN TO 1. }
    LOCAL yc IS EPR_HAC_YSGN * rf.
    LOCAL hc IS eprDestGeo(thrLat, thrLng, hdg + ARCTAN2(yc, xc), SQRT(xc * xc + yc * yc)).
    SET EPR_HAC_LAT TO hc[0].
    SET EPR_HAC_LNG TO hc[1].
    SET EPR_ORG_LAT TO orgLat.
    SET EPR_ORG_LNG TO orgLng.
    SET EPR_HAC_ON TO TRUE.
}

// THE ROTATION EPOCH FOR A FAMILY-RELATIVE GROUND POSITION. CALL THIS RATHER THAN BUILDING tRot BY HAND: the Kepler
// coast moves the family's time origin forward by EPR_FAM_TCOAST (up to ~1000 s), and forgetting it is SILENT (at
// JNSQ's rotation rate 1000 s is about 60 km of longitude, which reads as a targeting bias, not an epoch error).
// Pass the ABSOLUTE mission time; get back the rotation epoch the family's frame expects.
// MEASURED FROM THE GEODESY DATUM, NOT FROM THE FAMILY BUILD: eprToGeo(r, tRot) rotates the longitude back by
// omega*tRot, measured from the instant eprInitGeo captured the datum, so tRot for any state is (time of that state)
// minus (time of the datum). NOT tNow - EPR_FAM_TBUILD: the family is built in Phase 2 BEFORE the warp ladder, and
// eprArm, which calls eprInitGeo, runs at Phase 3 after it, so the two epochs differ by the warped coast (~1400 s).
FUNCTION eprFamTRot {
    PARAMETER tNow.
    RETURN tNow - EPR_GEO_T0.
}

// ============================================================================
//  PASS 3  --  THE FLOWN LOOP. No integration in it at all.
// ============================================================================
//  eprGuidStep() is called once per guidance cycle and returns the bank to fly. Everything it does is table lookup and
//  arithmetic: the family was built at boot and nothing here integrates (solve-and-track would re-solve a trajectory
//  every 30 s at ~3800 acceleration evaluations a time).
//  The lateral half is the solve-and-track loop's (same deadband schedule, minimum-bank floor and slew law); only the
//  longitudinal half differs.

GLOBAL EPR_GS_SIGN IS 0.        // 0 = not yet chosen. Latched on the first cycle from the sign
                                //   of the azimuth error, then only changed by a reversal.
GLOBAL EPR_GS_REV IS 0.
GLOBAL EPR_GS_GLAT IS 0.        // guidance's OWN ground position, from eprToGeo -- logged so it
GLOBAL EPR_GS_GLNG IS 0.        //   can be compared against SHIP:GEOPOSITION
GLOBAL EPR_GS_RNG IS 0.         // the range-to-go it actually flew on
GLOBAL EPR_GS_TROT IS 0.        // the rotation epoch that produced it
GLOBAL EPR_GS_PAST IS FALSE.    // TRUE once the target is BEHIND the vehicle -- see eprGuidStep
GLOBAL EPR_GS_REVERSING IS FALSE. // TRUE while a commanded roll reversal is still slewing
GLOBAL EPR_GS_REV_TOL IS 1.0.     // deg; the slew has arrived when it is this close to want
GLOBAL EPR_GS_DNOW IS 0.          // the MODEL's drag at the current state
GLOBAL EPR_GS_DMEAS IS -1.        // the MEASURED drag handed in, or -1 if none
GLOBAL EPR_GS_CORR IS 0.
GLOBAL EPR_GS_BANK IS 0.        // last COMMANDED bank, signed -- carried because the slew is
GLOBAL EPR_GS_RATE IS 0.        //   rate AND acceleration limited
GLOBAL EPR_GS_U IS 0.5.
GLOBAL EPR_GS_U_ST IS 0.5.     // the state's u (the inversion, before the servo): ENTRY TRAJ's U
GLOBAL EPR_GS_SAT IS "".
GLOBAL EPR_GS_STARTED IS FALSE.
GLOBAL EPR_GS_DREF IS 0.
GLOBAL EPR_GS_DERR IS 0.
GLOBAL EPR_GS_AZ IS 0.
GLOBAL EPR_GS_ROLLREF IS 0.
GLOBAL EPR_GS_TLAST IS -1.      // TIME:SECONDS at the previous eprGuidStep call, so the loop
                                //   can MEASURE its own dt instead of being told one.
GLOBAL EPR_GS_DT IS 0.          // the dt actually used, for logging
GLOBAL EPR_GS_DT_MAX IS 2.      // s. Clamp on a measured dt.
                                //   The slew advances bank by rate*dt, so a wrong dt is a wrong roll rate. The clamp matters
                                //   at the FIRST call after a gap: the family build takes ~126 s of game time, and without a
                                //   bound the first guidance cycle after it would command a huge roll step. eprGuidReset
                                //   clears the timestamp for the same reason.

// ---- THE ALPHA MODULATION (the FSSR's G4.8 EGLODVCMD / EGROLCMD) ------------------------------------------------
//  Bank is the drag control; alpha is the vernier the orbiter added before STS-1. eprGuidStep, given the vehicle's actual
//  alpha (aoaNow), commands alpha + DELALP inside +-EPR_AM_LIM of the schedule (EPR_GS_ACMD; the band fades to 0 from
//  EPR_AM_V_FULL to EPR_AM_V_ZERO, so TAEM gets the scheduled alpha), DELALP = Cd(alpha) (DREF / D - 1) / (dCd/dalpha),
//  0 inside the deadband; and takes the bank loop's drag error at the SCHEDULED alpha (EPR_GS_DEQ = D Cd(sched) /
//  Cd(alpha)) -- the demodulation: bank keeps removing the error alpha is covering, so alpha drifts back to the schedule.
//  Without aoaNow (the selftests) nothing changes.
GLOBAL EPR_AM_ON IS TRUE.          // ON, with the SYNC law (EPR_AM_SYNC below)
GLOBAL EPR_AM_LIM IS 3.          // deg about the schedule (the workbook: "Never change alpha by more than +-3 deg")
GLOBAL EPR_AM_V_FULL IS 1500.    // m/s: the full band above ...
GLOBAL EPR_AM_V_ZERO IS 900.     // ... none below (the TAEM handover at 762 m/s flies the schedule)
GLOBAL EPR_AM_V_FULL_FAM IS 1000.   // m/s: EPR_FAM_ADD (4) -- the band full above this ...
GLOBAL EPR_AM_V_ZERO_FAM IS 800.    // ... none below: inside the TAEM bank ramp (EPR_BANK_TAEM_SPEED to EPR_TAEM_VEL)
GLOBAL EPR_AM_DDMIN IS 0.01.     // the deadband, a fraction of DREF
// THE STEP'S SHARE IN PHYSICS WARP: in 4x below Mach 7 the measured drag error scatters 10-11 % sample to sample (1x
// 1.8-3 %, 4x above Mach 7 1 %). The full Newton step turned each sample into an alpha step (sd 0.65 deg, 40 % over
// 0.5 deg; 1x 2-4 %), the 4x pitch loop overshot each step ~50 % and rang (q sd 2.0 deg/s at 4.2-5 kPa against 0.5 at
// 1x), and the next sample read that ring: a loop through the guidance (the window's alpha comes from 1-2 cycle samples;
// the true 25 Hz mean would take out only a quarter of the scatter). The bank command swung with it (its drag error is
// the same sample's). Offline (this law, lib_grdap's pitch loop on the fitted plant, the drag on its flown slope k 0.7-2
// with 5 % noise a sample) the step's share g = 0.25 takes the 4x ring from q sd 2.0-2.6 to 0.48-0.50 (the steps
// 1.4-1.9 -> 0.3 deg) and still takes out a 5 % density error (in ~9 s, not ~2). EPR_AM_G = MIN(1, EPR_AM_WG / the
// physics warp) (eprAmGain, set by the dispatchers each cycle): 1x the full step, 2x 0.5, 4x 0.25.
GLOBAL EPR_AM_WG IS 1.0.         // the step's share x the physics warp rate (1 = the full step at 1x only)
GLOBAL EPR_AM_G IS 1.           // this cycle's share of the Newton step (eprAmGain)
FUNCTION eprAmGain {             // 1 off physics warp, else MIN(1, EPR_AM_WG / the warp rate)
    IF KUNIVERSE:TIMEWARP:MODE <> "PHYSICS" { RETURN 1. }
    RETURN MIN(1, EPR_AM_WG / MAX(1, KUNIVERSE:TIMEWARP:RATE)).
}
GLOBAL EPR_GS_ACMD IS -1.        // the alpha command (deg); -1 = fly the schedule
GLOBAL EPR_GS_DEQ IS 0.          // the measured drag at the scheduled alpha (the bank loop's error)
// THE PAIRING: FD_DRAG is a window mean of at least 1 s, sample-and-held (lib_vehicle fdSample, FD_MIN_DT), so it is
// about 1.0-1.3 s older than aoaNow. Paired with the current alpha every cycle, the law winds up into a limit cycle.
// EPR_AM_SYNC: act ONCE PER NEW FD SAMPLE (fdN = FD_N), referenced to, and demodulating with, the MEAN alpha over that
// sample's window; hold the command between samples. (The orbiter needs none of this: its drag comes from the IMU at a
// high rate.)
GLOBAL EPR_AM_SYNC IS TRUE.
// THE STEP ON THE FLOWN SLOPE: EPR_AM_SLOPE_K = LIST(Mach, k) rows, k = the drag's alpha slope AS FLOWN / the onboard
// polar's, by Mach (d ln(D/q) vs the window-mean alpha per FD sample). The step is a full Newton step, so on the model
// slope it multiplies the drag error by (1 - k) per sample: no damping above Mach 10 (k 2.0-2.2), a ring at high Mach.
// Linear between rows, flat outside.
GLOBAL EPR_AM_SLOPE_K IS LIST(LIST(3.25, 0.84), LIST(5.0, 1.0), LIST(7.0, 1.22), LIST(9.0, 1.69), LIST(11.0, 2.04), LIST(13.5, 2.24)).
FUNCTION eprAmSlopeK {
    PARAMETER mach.
    LOCAL t IS EPR_AM_SLOPE_K.
    IF mach <= t[0][0] { RETURN t[0][1]. }
    FROM { LOCAL i IS 1. } UNTIL i >= t:LENGTH STEP { SET i TO i + 1. } DO {
        IF mach <= t[i][0] { RETURN t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]). }
    }
    RETURN t[t:LENGTH - 1][1].
}
GLOBAL EPR_AM_ASUM IS 0.         // the alpha samples since the last FD sample (the window being measured now) ...
GLOBAL EPR_AM_AN IS 0.           // ... and their count
GLOBAL EPR_AM_FDN IS -1.         // the FD sample count last seen (-1 = none)
GLOBAL EPR_AM_AFD IS -1.         // the mean alpha of the sample in use (deg; -1 = none yet)
GLOBAL EPR_AM_HOLD IS -1.        // the held alpha command (deg; -1 = none)

// ---- THE SATURATION ALPHA BIAS -------------------------------------------------
//  At u = 1 the bank cannot shed more energy. The alpha modulation above sees only the drag error against the
//  saturated reference, and its band fades out from EPR_AM_V_FULL_FAM to _ZERO_FAM (1000 -> 800 m/s). This bias reads how
//  far past u = 1 the range is (EPR_SAT_AM_UX, eprFamInvertX: 1 = the EPR_BANK_MAX member exactly) and raises the
//  alpha schedule by up to EPR_SAT_AM_MAX: target = MAX x smoothstep((ux - U0) / (U1 - U0)) x the speed fade (full above
//  V_FULL, none below V_ZERO, so TAEM gets the schedule); value and slope 0 at u = 1 (no step). The bias follows the
//  target through a first-order lag EPR_SAT_AM_TAU, then a rate (RATE) and an acceleration (ACC) limit. No latch and no
//  band: a continuous function of the state, filtered; nothing switches, so nothing can toggle. The reference drag moves
//  with the raised schedule by the polar's ratio (EPR_SAT_AM_DREF), so the bank loop and the vernier work around the
//  raised schedule. ONE TOTAL CAP: the alpha command (bias + the vernier) stays at or under the schedule +
//  EPR_SAT_AM_MAX (with EPR_AM_LIM 3 the vernier alone never passes it: nothing changes without the bias). On a late
//  long entry the drag is short of the saturated reference and the vernier is at its top already, so under the cap
//  the bias adds alpha only where the vernier's band fades (below 1000 m/s): its target is + 3 to 950 m/s and 0 by
//  800 (the lagged bias 0.7 deg or less at the handover; python replays: 0.4-1.1 km of TAEM energy on 10-30 km). The real
//  orbiter had no such law; its limits are kept: +-3 deg of the schedule, slow, demodulated, the schedule at TAEM.
//  The nominal entry only (lib_tal keeps its law; the C# EGSTEP's TAL path too). Python fly_family SAT_AM_* (sync_check).
GLOBAL EPR_SAT_AM_ON IS TRUE.      // FALSE = off (bit-identical to before)
GLOBAL EPR_SAT_AM_MAX IS 3.        // deg: the bias's top AND the total cap above the schedule (the Shuttle's +-3)
GLOBAL EPR_SAT_AM_U0 IS 1.         // ux where the target starts (value 0, slope 0) ...
GLOBAL EPR_SAT_AM_U1 IS 1.1.       // ... and where it is full (0.7 of a member spacing past the EPR_BANK_MAX member)
GLOBAL EPR_SAT_AM_V_FULL IS 950.   // m/s surface: the target full above this ...
GLOBAL EPR_SAT_AM_V_ZERO IS 800.   // ... none below (back on the schedule before the TAEM handover at 762 m/s)
GLOBAL EPR_SAT_AM_TAU IS 4.        // s: the first-order lag
GLOBAL EPR_SAT_AM_RATE IS 0.5.     // deg/s: the bias's rate limit
GLOBAL EPR_SAT_AM_ACC IS 0.25.     // deg/s^2: its acceleration limit
GLOBAL EPR_SAT_AM_DREF IS TRUE.    // the reference drag scaled with the raised schedule (Cd(sched + b) / Cd(sched))
GLOBAL EPR_SAT_AM_UX IS 0.         // this cycle's ux (the log's fam_satux)
GLOBAL EPR_SAT_AM_B IS 0.          // the bias, deg (the log's fam_satb)
GLOBAL EPR_SAT_AM_BF IS 0.         // the lagged target, deg
GLOBAL EPR_SAT_AM_BR IS 0.         // the bias's rate, deg/s

// eprFamInvert's u carried past the family's ends, linear on the end pair's range span (u = that call's u inside it)
FUNCTION eprFamInvertX {
    PARAMETER vr, rngToGo, u.
    LOCAL n IS EPR_FAM:LENGTH.
    LOCAL rn IS eprFamAt(n - 1, vr, 4).
    IF rngToGo <= rn {
        LOCAL sp IS eprFamAt(n - 2, vr, 4) - rn.
        LOCAL f IS 0.
        IF sp > 0.000000001 { SET f TO (rn - rngToGo) / sp. }
        RETURN 1 + f / (n - 1).
    }
    LOCAL r0 IS eprFamAt(0, vr, 4).
    IF rngToGo >= r0 {
        LOCAL sp IS r0 - eprFamAt(1, vr, 4).
        LOCAL f IS 0.
        IF sp > 0.000000001 { SET f TO (rngToGo - r0) / sp. }
        RETURN 0 - f / (n - 1).
    }
    RETURN u.
}

// the bias's target, deg: 0 up to U0, MAX from U1, a smoothstep between, x the speed fade
FUNCTION eprSatAmTarget {
    PARAMETER ux, vr.
    LOCAL x IS (ux - EPR_SAT_AM_U0) / (EPR_SAT_AM_U1 - EPR_SAT_AM_U0).
    LOCAL sm IS 0.
    IF x >= 1 { SET sm TO 1. } ELSE IF x > 0 { SET sm TO x * x * (3 - 2 * x). }
    LOCAL fv IS MAX(0, MIN(1, (vr - EPR_SAT_AM_V_ZERO) / (EPR_SAT_AM_V_FULL - EPR_SAT_AM_V_ZERO))).
    RETURN EPR_SAT_AM_MAX * sm * fv.
}

// one cycle of the bias: the lag, then the acceleration and the rate limits. Returns the bias, deg
FUNCTION eprSatAmStep {
    PARAMETER tgt, dtc.
    SET EPR_SAT_AM_BF TO EPR_SAT_AM_BF + (tgt - EPR_SAT_AM_BF) * dtc / (EPR_SAT_AM_TAU + dtc).
    LOCAL want IS (EPR_SAT_AM_BF - EPR_SAT_AM_B) / dtc.
    LOCAL rt IS MAX(EPR_SAT_AM_BR - EPR_SAT_AM_ACC * dtc, MIN(EPR_SAT_AM_BR + EPR_SAT_AM_ACC * dtc, want)).
    SET EPR_SAT_AM_BR TO MAX(0 - EPR_SAT_AM_RATE, MIN(EPR_SAT_AM_RATE, rt)).
    SET EPR_SAT_AM_B TO EPR_SAT_AM_B + EPR_SAT_AM_BR * dtc.
    RETURN EPR_SAT_AM_B.
}

// ---- tracker gains ------------------------------------------------------------------
GLOBAL EPR_K_HDOT IS 35.        // m/s of sink commanded per m/s^2 of drag error
GLOBAL EPR_K_BANK_HDOT IS 0.60. // deg of bank per m/s of sink error
GLOBAL EPR_HDOT_MAX IS 60.      // clamp on the sink bias
GLOBAL EPR_TRK_MAX IS 25.       // clamp on the bank correction
// THE DEMODULATION'S WEIGHT AND THE C16 DRAG BIAS: after each roll reversal the bank swung (84 -> 46 -> 58 deg, the
// alpha 38.7 -> 43 -> 38.6). The full demodulation (D_eq below) turned the alpha the modulation raised into ~7 deg of
// bank per deg through this loop, on the polar's slope, and the flown slope over the phugoid is 0.6-0.8 of it: the two
// loops swung together (shown offline, flying entry_predict.fly_family from the flown interface). The nominal entry
// only (the TAL keeps its law and its H-dot gate):
GLOBAL EPR_AM_DW IS 0.5.        // A deviation: D_eq = D_meas (Cd(sched) / Cd(alpha))^EPR_AM_DW (1 = the full demodulation)
GLOBAL EPR_K3_HDOT IS 20.       // the FSSR's EGGNSLCT C16 drag bias (CT16(3) DD, "roll reversal phugoid damping"): the
GLOBAL EPR_KH_MIN IS 15.        //   sink bias gain = MIDVAL(EPR_K_HDOT + EPR_K3_HDOT x the drag error, EPR_KH_MIN, EPR_KH_MAX)
GLOBAL EPR_KH_MAX IS 50.        //   (CT16MN / CT16MX); EPR_K3_HDOT 0 = no drag bias
// The late-entry bank switches (python BANK_TAEM_REF /
// K3_LATE_POS, EntryGuid.cs; booleans, sync_check cannot pair them). An entry that falls behind its drag reference late (a reversal float at Mach 4.4-4.8) could not
// catch up: flight B (flight_73763) saturated at Mach 3.24 and handed TAEM ~4 km of its +9. The nominal entry only:
GLOBAL EPR_BANK_TAEM_REF IS TRUE.  // the TAEM ramp (eprBankWithFlare) on the REFERENCE roll only; the Hdot correction,
                                   //   the minimum bank and the slew act on the flown bank, up to EPR_BANK_MAX (before: the
                                   //   ramp scaled reference and correction together, down to 30/85 at EPR_TAEM_VEL)
GLOBAL EPR_K3_LATE_POS IS TRUE.    // (B3-late) below EPR_BANK_TAEM_SPEED: K3 on a positive drag error only (the gain stays
                                   //   EPR_K_HDOT while the drag is short; K3 had put it on EPR_KH_MIN); the bias clamp stays
                                   //   EPR_HDOT_MAX. Above EPR_BANK_TAEM_SPEED the K3 damping is unchanged. Measured on 8
                                   //   flight replays: the five long entries -1.8..-3.0 km of
                                   //   TAEM energy, controls +0.2..+1.2.
                                //   The correction is PROPORTIONAL, not integral (corr = K*err, not corr += K*err*dt): an
                                //   integral with no proportional term and no anti-windup winds to TRK_MAX and leaves the
                                //   loop effectively open. EPR_GS_CORR sitting at +/-EPR_TRK_MAX for a sustained stretch
                                //   means an integral term has come back.

// THE DRAG SAMPLE'S STEP: dMeas (FD_DRAG) is a window mean held between samples (~1.3 s), so the drag error and the
// alpha modulation's command step at each new sample, and the bank and alpha commands with them (a 5-7 s roll and a
// 1-4 s pitch wiggle in the flown entries). The bias's drag error and the alpha command go through a first-order lag
// of EPR_GS_TAU s, one sample; the Hdot term stays unfiltered (the loop's damping). The orbiter reads its drag from
// the IMU at a high rate, with no step to smooth. 0 = no lag.
GLOBAL EPR_GS_TAU IS 1.3.
GLOBAL EPR_GS_DERRF IS -1E9.     // the lagged drag error (m/s^2; -1E9 = seed on the next pass)
GLOBAL EPR_GS_ACMDF IS -1.       // the lagged alpha command (deg; -1 = seed on the next pass)
FUNCTION eprLagD {
    PARAMETER x, dtc.
    IF EPR_GS_DERRF < -1E8 OR EPR_GS_TAU <= 0 { SET EPR_GS_DERRF TO x. }
    ELSE { SET EPR_GS_DERRF TO EPR_GS_DERRF + (x - EPR_GS_DERRF) * dtc / (EPR_GS_TAU + dtc). }
    RETURN EPR_GS_DERRF.
}
FUNCTION eprLagA {
    PARAMETER x, dtc.
    IF EPR_GS_ACMDF < 0 OR EPR_GS_TAU <= 0 { SET EPR_GS_ACMDF TO x. }
    ELSE { SET EPR_GS_ACMDF TO EPR_GS_ACMDF + (x - EPR_GS_ACMDF) * dtc / (EPR_GS_TAU + dtc). }
    RETURN EPR_GS_ACMDF.
}

FUNCTION eprGuidReset {
    SET EPR_GS_SIGN TO 0.
    SET EPR_FAM_ADD_PREP TO FALSE.          // EPR_FAM_ADD: the excess, the servo target and the HAC are set again
    SET EPR_HAC_ON TO FALSE.
    SET EPR_AM_ASUM TO 0. SET EPR_AM_AN TO 0. SET EPR_AM_FDN TO -1. SET EPR_AM_AFD TO -1. SET EPR_AM_HOLD TO -1.
    SET EPR_SAT_AM_UX TO 0. SET EPR_SAT_AM_B TO 0. SET EPR_SAT_AM_BF TO 0. SET EPR_SAT_AM_BR TO 0.
    SET EPR_GS_REV TO 0.
    SET EPR_GS_CORR TO 0.
    SET EPR_GS_DERRF TO -1E9. SET EPR_GS_ACMDF TO -1.
    SET EPR_GS_BANK TO 0.
    SET EPR_GS_RATE TO 0.
    SET EPR_GS_U TO 0.5.
    SET EPR_GS_U_ST TO 0.5.
    SET EPR_GS_SAT TO "".
    SET EPR_GS_STARTED TO FALSE.
    SET EPR_GS_DREF TO 0.
    SET EPR_GS_DERR TO 0.
    SET EPR_GS_AZ TO 0.
    SET EPR_GS_ROLLREF TO 0.
    SET EPR_GS_TLAST TO -1.
    SET EPR_GS_DT TO 0.
    SET EPR_GS_ACMD TO -1.
    SET EPR_GS_DEQ TO 0.
}

// ---- THE GUIDANCE CYCLE IN C# (the KAL/S coprocessor: ADDONS:KALS:EGSTEP) ---------------------------------------------
// ON by default (a failed addon costs nothing: kOS's own cycle then flies). With EPR_GS_CS and the addon installed,
// eprGuidStep (and lib_tal's talGuidStep) hand the cycle to the addon (coproc/EntryGuid.cs: a line-for-line port of
// eprGuidStepK / talGuidStepK and every function they call; ~8-9k kOS opcodes a cycle, up to 40k on a TAL's Nz-limiter
// sample, become ~0.3k). The state
// stays these globals: the addon reads them at the call and writes back what the cycle SETs (nothing on an error). kOS
// keeps the game reads (TIME:SECONDS, the pressure, the caller's state). ANY addon failure (no addon, an older DLL, an
// error) turns the switch off for the rest of the flight, says why (EPR_GS_CS_ERR) and kOS's own cycle flies that same
// cycle.
IF NOT (DEFINED EPR_GS_CS) { GLOBAL EPR_GS_CS IS TRUE. }               // TRUE: the addon flies the guidance cycle
GLOBAL EPR_GS_CS_ERR IS "".       // why the addon is off ("" = it is not)
GLOBAL EPR_GS_CS_SET IS 0.        // 0 = not tried yet, 1 = ready, -1 = off for the flight
GLOBAL EPR_GS_CS_N IS 0.          // cycles the addon flew

FUNCTION eprGsCsOff {             // the addon off for the rest of the flight: kOS flies the cycle
    PARAMETER why.
    SET EPR_GS_CS_ERR TO why.
    SET EPR_GS_CS TO FALSE.
    SET EPR_GS_CS_SET TO -1.
}

FUNCTION eprGsCsReady {           // TRUE when the addon can take the cycle (checked once a flight)
    IF EPR_GS_CS_SET = 0 {
        LOCAL why IS "".
        IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
        ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
        ELSE IF NOT ADDONS:KALS:HASSUFFIX("EGSTEP") { SET why TO "the KAL/S addon has no entry guidance (an older KalsCoproc.dll)". }
        ELSE {
            LOCAL res IS ADDONS:KALS:EGSETUP(LIST(CONSTANT:E, CONSTANT:DEGTORAD, CONSTANT:RADTODEG)).
            IF res <> "" { SET why TO "EGSETUP: " + res. }
        }
        IF why = "" { SET EPR_GS_CS_SET TO 1. } ELSE { eprGsCsOff(why). }
    }
    RETURN EPR_GS_CS_SET = 1.
}

FUNCTION eprGsCsIn {              // the cycle's inputs (coproc/EntryGuid.cs EgIn): the arguments + the two game reads
    PARAMETER isTal, rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN.
    RETURN LIST(isTal, rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN, TIME:SECONDS, eprPres(rv:MAG - EPR_R)).
}

FUNCTION eprGsCsStep {            // the addon's cycle: the bank (a number), or a string (the switch is off then)
    PARAMETER inp.
    LOCAL res IS ADDONS:KALS:EGSTEP(inp).
    IF res:ISTYPE("Scalar") { SET EPR_GS_CS_N TO EPR_GS_CS_N + 1. RETURN res. }
    eprGsCsOff("EGSTEP: " + res).
    RETURN res.
}

// One guidance cycle (the dispatcher: the addon, or kOS's eprGuidStepK below). Returns the SIGNED bank, deg.
FUNCTION eprGuidStep {
    PARAMETER rv, vv, tgtLat, tgtLng, tRot, dt IS -1, dMeas IS -1, aoaNow IS -1, fdN IS -1.
    IF aoaNow > 0 { SET EPR_AM_G TO eprAmGain(). }   // the step's share this cycle (kOS and the addon alike)
    IF EPR_GS_CS AND eprGsCsReady() {
        LOCAL inp IS eprGsCsIn(FALSE, rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN).
        LOCAL res IS eprGsCsStep(inp).
        IF res:ISTYPE("Scalar") { RETURN res. }
    }
    RETURN eprGuidStepK(rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN).
}

// eprGuidStepK: kOS's own guidance cycle (the dispatcher is eprGuidStep above). Returns the SIGNED bank, deg.
//   rv, vv  inertial state
//   tRot    epoch for the ground-position conversion. IF THE FAMILY WAS BUILT THROUGH A KEPLER COAST, THIS MUST
//           INCLUDE EPR_FAM_TCOAST -- otherwise every longitude is rotated by the length of the coast.
FUNCTION eprGuidStepK {
    PARAMETER rv, vv, tgtLat, tgtLng, tRot, dt IS -1, dMeas IS -1, aoaNow IS -1, fdN IS -1.
    // dt < 0 means MEASURE IT: the flight loop should always do that, since its rate is not constant. The selftests pass an
    // explicit dt so a simulated entry stays deterministic.
    LOCAL dtc IS dt.
    IF dtc < 0 {
        LOCAL now IS TIME:SECONDS.
        IF EPR_GS_TLAST < 0 { SET dtc TO 0.05. } ELSE { SET dtc TO now - EPR_GS_TLAST. }
        SET EPR_GS_TLAST TO now.
        IF dtc > EPR_GS_DT_MAX { SET dtc TO EPR_GS_DT_MAX. }
        IF dtc < 0.001 { SET dtc TO 0.001. }
    }
    SET EPR_GS_DT TO dtc.
    LOCAL altm IS rv:MAG - EPR_R.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL vr IS vrelv:MAG.
    LOCAL rho IS 0.
    IF altm < EPR_ATM { SET rho TO eprRho(altm). }
    LOCAL mach IS 0.
    LOCAL dNow IS 0.
    IF rho > 0 AND vr > 1 {
        SET mach TO eprMachFrom(altm, vr, rho).
        LOCAL pr IS eprPrMult(rho * vr).
        SET dNow TO eprCdaEntry(eprAoA(vr), mach, vr) * 0.5 * rho * vr * vr * pr.
    }
    // THE INITIATE THRESHOLD STAYS ON THE MODEL, ON PURPOSE: fam_build decides which samples to store with the same test
    // against the same model, so guidance must start where the family starts. Only the CONTROL error uses the measurement.
    IF dNow >= EPR_GUID_DRAG_INIT { SET EPR_GS_STARTED TO TRUE. }
    // ARGUMENT ORDER: eprAzError is (rv, vv, tRot, tgtLat, tgtLng), tRot THIRD. Another order would not make kOS complain:
    // it would compute the azimuth to a target at latitude tRot and longitude tgtLat.
    // EPR_FAM_ADD (1): with the plan's HAC armed (eprArmHac) the heading error is to the HAC centre
    LOCAL famAddHac IS EPR_FAM_ADD AND EPR_HAC_ON.
    IF famAddHac { SET EPR_GS_AZ TO eprAzError(rv, vv, tRot, EPR_HAC_LAT, EPR_HAC_LNG). }
    ELSE { SET EPR_GS_AZ TO eprAzError(rv, vv, tRot, tgtLat, tgtLng). }

    LOCAL mag IS EPR_PREENTRY_BANK.
    IF EPR_GS_STARTED AND EPR_FAM_READY AND EPR_FAM_OK {
        LOCAL gi IS eprToGeoLive(rv).                  // guidance: live kOS position
        LOCAL rng IS eprFamRngTo(gi[0], gi[1], tgtLat, tgtLng).   // EPR_FAM_ADD (1): to the HAC's origin when armed

        // PAST THE TARGET, RANGE-TO-GO MUST GO NEGATIVE. eprGcDist is an unsigned great-circle distance: once the vehicle
        // overflies the aim point it grows again, and the inversion would read that as falling short and command LESS bank.
        // EPR_GS_AZ is the signed angle from heading to the bearing to the target; beyond 90 deg the target is BEHIND.
        // Negating the range drives eprFamInvert to u = 1, maximum bank, which is the correct response.
        // THIS IS A GUARD, NOT A RECOVERY: reaching this state means the entry already failed upstream (TAEM should have
        // taken over at 762 m/s). It keeps guidance from deepening the failure, and the log says plainly that it happened.
        SET EPR_GS_PAST TO (ABS(EPR_GS_AZ) > 90).
        IF EPR_GS_PAST AND NOT famAddHac { SET rng TO -rng. }   // EPR_FAM_ADD (1): the HAC range is signed already
        SET rng TO rng + eprFamExcess().                  // EPR_FAM_ADD (2): the excess (0 without it)
        // PUBLISHED SO THE LOG CAN SEE WHAT GUIDANCE THINKS ITS POSITION IS: a range error cannot otherwise be traced to
        // eprToGeo, tRot or the frame axes. IF A VALUE STEERS THE VEHICLE, IT BELONGS IN THE LOG.
        SET EPR_GS_GLAT TO gi[0].
        SET EPR_GS_GLNG TO gi[1].
        SET EPR_GS_RNG TO rng.
        SET EPR_GS_TROT TO tRot.
        LOCAL inv IS eprFamInvert(vr, rng).
        IF EPR_SAT_AM_ON { SET EPR_SAT_AM_UX TO eprFamInvertX(vr, rng, inv[0]). }   // u past the ends (before the servo)
        SET EPR_GS_U_ST TO inv[0].                        // the state's u, for the page's U only
        SET EPR_GS_U TO eprFamServo(inv[0], vr).          // EPR_FAM_ADD (3): the servo (sat stays the family's own)
        SET EPR_GS_SAT TO inv[1].
        SET EPR_GS_DREF TO eprFamRef(vr, EPR_GS_U, 2).
        // THE ERROR IS MEASURED MINUS REFERENCE, NOT MODEL MINUS REFERENCE. A model drag against the reference compares the
        // aero model with itself (the reference comes from the family, which eprCda built): it can never see a modelling
        // mistake, an open loop wearing a feedback loop's clothes.
        // dMeas is FD_DRAG, from the accelerometer path in lib_vehicle, passed in rather than referenced so entry_predict
        // stays standalone. Negative means "not supplied" and the model is used.
        SET EPR_GS_DNOW TO dNow.
        IF dMeas >= 0 {
            SET EPR_GS_DMEAS TO dMeas.
            SET EPR_GS_DERR TO dMeas - EPR_GS_DREF.
        } ELSE {
            SET EPR_GS_DMEAS TO -1.
            SET EPR_GS_DERR TO dNow - EPR_GS_DREF.
        }
        // THE ALPHA MODULATION (the block above EPR_AM_ON). Needs the measured drag and the actual alpha; without them
        // EPR_GS_ACMD = -1 and the vehicle flies the schedule.
        SET EPR_GS_ACMD TO -1.
        SET EPR_GS_DEQ TO EPR_GS_DERR + EPR_GS_DREF.
        IF EPR_AM_ON AND aoaNow > 0 AND dMeas > 0 {
            LOCAL sched IS eprAoA(vr).
            LOCAL aTop IS sched + EPR_SAT_AM_MAX.  // the one total cap (the schedule's own + EPR_SAT_AM_MAX)
            IF EPR_SAT_AM_ON {              // the schedule up by the bias, the reference drag with it
                LOCAL sb IS eprSatAmStep(eprSatAmTarget(EPR_SAT_AM_UX, vr), dtc).
                IF sb <> 0 {
                    IF EPR_SAT_AM_DREF { SET EPR_GS_DREF TO EPR_GS_DREF * eprCda(sched + sb, mach) / eprCda(sched, mach). }
                    SET sched TO sched + sb.
                }
            }
            LOCAL band IS eprAmBand(vr).   // EPR_FAM_ADD (4): EPR_AM_V_FULL_FAM / _ZERO_FAM with it
            LOCAL aRef IS aoaNow.          // the alpha the measured drag belongs to (EPR_AM_SYNC: its window's mean)
            LOCAL fresh IS TRUE.           // a new drag sample: solve the command again (else hold it)
            IF EPR_AM_SYNC AND fdN >= 0 {
                IF fdN <> EPR_AM_FDN {
                    IF EPR_AM_AN > 0 { SET EPR_AM_AFD TO EPR_AM_ASUM / EPR_AM_AN. } ELSE { SET EPR_AM_AFD TO aoaNow. }
                    SET EPR_AM_ASUM TO 0.
                    SET EPR_AM_AN TO 0.
                    SET EPR_AM_FDN TO fdN.
                } ELSE IF EPR_AM_HOLD > 0 {
                    SET fresh TO FALSE.
                }
                SET EPR_AM_ASUM TO EPR_AM_ASUM + aoaNow.   // this cycle's alpha belongs to the NEXT sample's window
                SET EPR_AM_AN TO EPR_AM_AN + 1.
                IF EPR_AM_AFD > 0 { SET aRef TO EPR_AM_AFD. }
            }
            LOCAL cdn IS eprCda(aRef, mach).
            SET EPR_GS_DEQ TO dMeas * (eprCda(sched, mach) / cdn) ^ EPR_AM_DW.   // the demodulation, at the weight EPR_AM_DW
            SET EPR_GS_DERR TO EPR_GS_DEQ - EPR_GS_DREF.
            IF fresh {
                LOCAL dela IS 0.
                IF ABS(dMeas - EPR_GS_DREF) >= EPR_AM_DDMIN * EPR_GS_DREF {
                    LOCAL slope IS (eprCda(aRef + 0.5, mach) - eprCda(aRef - 0.5, mach)) * eprAmSlopeK(mach).   // the flown slope
                    IF slope > 0 {
                        SET dela TO MAX(0 - EPR_AM_LIM, MIN(EPR_AM_LIM, EPR_AM_G * cdn * (EPR_GS_DREF / dMeas - 1) / slope)).
                    }
                }
                SET EPR_AM_HOLD TO aRef + dela.
            }
            LOCAL ac IS MAX(sched - band, MIN(sched + band, EPR_AM_HOLD)).
            IF EPR_SAT_AM_ON { SET ac TO MIN(aTop, ac). }   // the vernier clipped inside the total cap
            SET EPR_GS_ACMD TO eprLagA(ac, dtc).
        }
        // Hdot loop: a drag error is converted into a SINK RATE the vehicle should be holding,
        // and bank trims toward that. 2.12.3 -- corrections are excursions around the
        // reference roll, not a bank built from scratch.
        LOCAL hdotNow IS VDOT(vrelv, rv:NORMALIZED).
        LOCAL derrF IS eprLagD(EPR_GS_DERR, dtc).                     // the drag sample's step smoothed (eprLagD)
        LOCAL late IS EPR_K3_LATE_POS AND EPR_BANK_TAEM_SPEED > 0 AND vr < EPR_BANK_TAEM_SPEED.   // the late-position K3 term
        LOCAL dK3 IS derrF.
        IF late { SET dK3 TO MAX(0, derrF). }
        LOCAL khEff IS MAX(EPR_KH_MIN, MIN(EPR_KH_MAX, EPR_K_HDOT + EPR_K3_HDOT * dK3)).   // the FSSR's C16 drag bias
        LOCAL bias IS MAX(0 - EPR_HDOT_MAX, MIN(EPR_HDOT_MAX, khEff * derrF)).
        LOCAL hdotDes IS eprFamRef(vr, EPR_GS_U, 3) + bias.
        SET EPR_GS_CORR TO MAX(0 - EPR_TRK_MAX, MIN(EPR_TRK_MAX,
                               EPR_K_BANK_HDOT * (hdotNow - hdotDes))).
        SET EPR_GS_ROLLREF TO eprFamRoll(vr, EPR_GS_U).
        // the reference through the TAEM ramp, the correction on top. EPR_FAM_ADD's bank column is the bank
        // BEFORE the ramp; without it the column is already ramped (the ROLL REF row's same CHOOSE, ops3q)
        LOCAL rrf IS EPR_GS_ROLLREF.
        IF EPR_BANK_TAEM_REF AND EPR_FAM_ADD { SET rrf TO eprBankWithFlare(EPR_GS_ROLLREF, vr). }
        SET mag TO MAX(EPR_BANK_MIN, MIN(EPR_BANK_MAX, rrf + EPR_GS_CORR)).
    } ELSE {
        SET EPR_GS_ROLLREF TO 0.
        SET EPR_GS_DREF TO 0.
        SET EPR_GS_DERR TO 0.
        SET EPR_GS_ACMD TO -1.
        SET EPR_GS_DEQ TO 0.
    }

    // ---- lateral: deadband, reversal, minimum bank -----------------------------------
    IF EPR_GS_SIGN = 0 {
        SET EPR_GS_SIGN TO CHOOSE 1 IF EPR_GS_AZ >= 0 ELSE -1.
    }
    // Computed into a local first: `eprAzDeadband(mach, EPR_GS_REV = 0)` would put an equality expression directly in an
    // argument list, and this avoids relying on how kOS parses that.
    LOCAL isFirst IS FALSE.
    IF EPR_GS_REV = 0 { SET isFirst TO TRUE. }
    LOCAL db IS eprAzDeadband(mach, isFirst).
    LOCAL ns IS EPR_GS_SIGN.
    IF EPR_GS_AZ > db { SET ns TO 1. }
    ELSE IF EPR_GS_AZ < 0 - db { SET ns TO -1. }
    IF ns <> EPR_GS_SIGN {
        SET EPR_GS_REV TO EPR_GS_REV + 1.
        SET EPR_GS_SIGN TO ns.
        // SAY SO, RATHER THAN MAKE THE DISPLAY INFER IT: this line decides a reversal, and its side effects cannot stand in
        // for it (a counter says one happened, not that one is HAPPENING). EPR_GS_REVERSING is that flag.
        SET EPR_GS_REVERSING TO TRUE.
    }
    LOCAL want IS EPR_GS_SIGN * mag.
    // MINIMUM BANK applies only when banked TOWARD the site -- rule (a) of 2.14.2. Banked
    // away, a floor would drive the vehicle further off.
    IF EPR_USE_MIN_BANK AND EPR_GS_STARTED AND EPR_GS_SIGN * EPR_GS_AZ > 0
       AND dNow >= EPR_GUID_DRAG_INIT {
        LOCAL fl IS eprMinBank(mach, EPR_GS_AZ).
        IF ABS(want) < fl { SET want TO EPR_GS_SIGN * fl. }
    }
    IF vr <= EPR_BANK_STOP_SPEED { SET want TO 0. }

    LOCAL sl IS eprBankSlew(EPR_GS_BANK, want, EPR_GS_RATE, dtc).
    SET EPR_GS_BANK TO sl[0].
    // The roll is over when the slew has arrived. Cleared HERE, where `want` and the achieved command are both in hand
    // (`want` is rollref plus the Hdot correction and is not published on its own).
    IF EPR_GS_REVERSING AND ABS(sl[0] - want) <= EPR_GS_REV_TOL {
        SET EPR_GS_REVERSING TO FALSE.
    }
    SET EPR_GS_RATE TO sl[1].
    // The flare acts on MAGNITUDE and the sign is carried separately: eprBankWithFlare returns an absolute value, so the
    // sign of the COMMAND (not of the target) is reapplied, or a reversal in progress would flip the flare mid-roll.
    LOCAL sg IS 1.
    IF EPR_GS_BANK < 0 { SET sg TO -1. }
    // with EPR_BANK_TAEM_REF the ramp is already in the reference (above): the flare and the stop only
    RETURN sg * eprBankWithFlare(EPR_GS_BANK, vr, NOT EPR_BANK_TAEM_REF).
}

// ---------------------------------------------------------------- bank solver
//  Shooting method on bank magnitude. Range-to-TAEM is monotonic in bank, so a bracket plus secant is safe, and a constant
//  bank is also the CROSSRANGE-optimal way to meet a given range (sqrt(1-c^2) is concave in c), so a range requirement
//  maps to exactly one bank.
GLOBAL EPR_PH IS "idle".         // idle | lo | hi | sec | done
GLOBAL EPR_R0 IS V(0,0,0).
GLOBAL EPR_V0 IS V(0,0,0).
GLOBAL EPR_T0 IS 0.
GLOBAL EPR_TGT_LAT IS 0.
GLOBAL EPR_TGT_LNG IS 0.
GLOBAL EPR_LNG0 IS 0.
GLOBAL EPR_RLONG IS 0.
GLOBAL EPR_RSHORT IS 0.
// Terminal position of each bracket, kept separately so the published point matches the published bank: with one shared
// endpoint, whichever bracket ran LAST would leave its endpoint there, and a saturated solve publishing EPR_BANK_MIN
// would show the "hi" bracket's bank-85 endpoint.
GLOBAL EPR_LO_LAT IS 0.
GLOBAL EPR_LO_LNG IS 0.
GLOBAL EPR_HI_LAT IS 0.
GLOBAL EPR_HI_LNG IS 0.
GLOBAL EPR_SB0 IS 0.
GLOBAL EPR_SF0 IS 0.
GLOBAL EPR_SB1 IS 0.
GLOBAL EPR_SF1 IS 0.
GLOBAL EPR_SIT IS 0.
// m: the secant converges to this. 1500 m, not 500: with the crossing interpolated about 2 km of jitter remains, and a
// secant asked to converge below the noise floor does not converge, it thrashes.
GLOBAL EPR_STOL IS 1500.
GLOBAL EPR_SMAXIT IS 6.

// --- PROFILE TRACE ---------------------------------------------------------------------------
//  The integrator records nothing by default (a bank solve runs it three to six times and none needs a trace). The
//  drag-tracking reference comes from one run, the last, at the solved bank, with recording on. It samples every
//  EPR_TRACE_EVERY steps, since grdBuild resamples onto a fixed velocity grid anyway.
GLOBAL EPR_TRACE_ON IS FALSE.
GLOBAL EPR_TRACE_EVERY IS 5.     // steps between samples; 5 gives about 47 points over a 470 s entry
GLOBAL EPR_TRACE_MAX IS 300.     // hard cap, so a pathological run cannot grow without bound.
                                 //   The cap must hold the longest member: at EPR_IDT 2 the wings-level member is 602 steps
                                 //   (120 samples at EPR_TRACE_EVERY 5; 240 at dt 1). A longer member SILENTLY TRUNCATES,
                                 //   because eprTraceSample returns quietly at the cap, and every lookup below the last
                                 //   stored speed would clamp to the last row. A safety stop, not a tuning knob.
GLOBAL EPR_TR_V IS LIST().
GLOBAL EPR_TR_D IS LIST().
GLOBAL EPR_TR_S IS LIST().
GLOBAL EPR_TR_A IS LIST().
GLOBAL EPR_TR_ARC IS LIST().     // cumulative ground arc from the start of the run
GLOBAL EPR_TR_BK IS LIST().      // the bank actually flown at that sample
GLOBAL EPR_TRACE_K IS 0.

FUNCTION eprTraceReset {
    SET EPR_TR_V TO LIST().
    SET EPR_TR_D TO LIST().
    SET EPR_TR_S TO LIST().
    SET EPR_TR_A TO LIST().
    SET EPR_TR_ARC TO LIST().
    SET EPR_TR_BK TO LIST().
    SET EPR_TRACE_K TO 0.
}

// Drag magnitude and sink rate at a state. Recomputes the aero rather than having eprAccel return
// it: eprAccel is on the integrator's hot path and is called twice per RK2 step, so widening its
// return to carry diagnostics would cost on every step to serve one in five.
FUNCTION eprTraceSample {
    PARAMETER rv, vv.
    IF EPR_TR_V:LENGTH >= EPR_TRACE_MAX { RETURN. }
    LOCAL rmag IS rv:MAG.
    LOCAL altm IS rmag - EPR_R.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL vr IS vrelv:MAG.
    IF vr < 1 OR altm >= EPR_ATM { RETURN. }
    LOCAL rho IS eprRho(altm).
    IF rho <= 0 { RETURN. }
    LOCAL qdyn IS 0.5 * rho * vr * vr.
    LOCAL pr IS eprPrMult(rho * vr).
    LOCAL drag IS eprCdaEntry(eprAoA(vr), eprMachFrom(altm, vr, rho), vr) * qdyn * pr.
    EPR_TR_V:ADD(vr).
    EPR_TR_D:ADD(drag).
    EPR_TR_S:ADD(VDOT(vrelv, rv / rmag)).
    EPR_TR_A:ADD(altm).
    // Arc and flown bank, for the family. RANGE-TO-GO is filled in afterwards by running the
    // arc column backwards from the terminal point -- it cannot be known forwards.
    EPR_TR_ARC:ADD(EPR_FAM_ARC).
    EPR_TR_BK:ADD(EPR_FAM_BANK_NOW).
}

// The published solution: these are what the log reads.
GLOBAL EPR_SOL_BANK IS 0.
GLOBAL EPR_SOL_MISS IS 0.
GLOBAL EPR_SOL_SAT  IS "none".   // none | high | low | nosolution
GLOBAL EPR_MP_LAT IS 0.         // eprMissPath's own geolocation of the interface it scored
GLOBAL EPR_MP_LNG IS 0.
GLOBAL EPR_MP_TROT IS 0.        // the rotation epoch it used
GLOBAL EPR_MP_GC IS 0.          // and the great-circle range it derived
GLOBAL EPR_SOL_LAT  IS 0.
GLOBAL EPR_SOL_LNG  IS 0.
GLOBAL EPR_SOL_N    IS 0.
// Terminal state of the last completed integration, and how long the solve took. They say WHICH termination condition
// fired and at what state: the published bank and miss alone cannot distinguish "the vehicle cannot reach" from "the
// integration ended somewhere impossible".
GLOBAL EPR_TERM_ALT IS 0.
GLOBAL EPR_TERM_VEL IS 0.
GLOBAL EPR_TERM_WHY IS "none".   // taemalt | taemvel | ground | timeout
GLOBAL EPR_SOLVE_T0 IS 0.        // TIME:SECONDS when the current solve began
// The state the solve actually STARTED from. The solve is up to 50 s stale and the vehicle may fly uncoordinated, so an
// offline comparison cannot reconstruct it from lat/lng plus a finite-difference heading.
GLOBAL EPR_ST_ALT IS 0.
GLOBAL EPR_ST_VEL IS 0.
GLOBAL EPR_ST_VS  IS 0.
GLOBAL EPR_ST_LAT IS 0.
GLOBAL EPR_ST_LNG IS 0.
// What kOS itself says the position is, captured in the SAME statement block as the eprToGeo result: if the two
// disagree in flight, the displacement is real; if they agree, the analysis is at fault.
GLOBAL EPR_ST_KLAT IS 0.
GLOBAL EPR_ST_KLNG IS 0.

GLOBAL EPR_ST_HDG IS 0.   // ground-track heading at solve start, the last piece of the initial state
                          //   It matters: at 3600 m/s the vehicle is near orbital, the surface rotation adds 233 m/s
                          //   eastward to the inertial speed, and circular speed at 70 km is 3877, so an eastward
                          //   trajectory is barely descending while a 45 deg one loses 7% of its flight time.
GLOBAL EPR_SOLVE_DT IS 0.        // how long the last solve took, in game seconds

// Signed miss of the current integration's terminal point against the aim. MAGNITUDE is the great-circle distance
// between the terminal point and the aim, both proper surface coordinates at their own correct times, so no epoch
// mixing. SIGN comes from the terminal HEADING, not from comparing arc lengths (an epoch error flips that sign): is the
// aim ahead of or behind the terminal velocity vector? That is epoch-free, everything is evaluated at the terminal state.
// PATH-LENGTH RESIDUAL: how far the entry FLIES minus how far the aim IS. Positive means the trajectory goes too far.
// THIS IS WHAT THE PLANNER MUST SCORE ON, NOT eprMissTo: the planner predicts a CONSTANT-BANK entry, which turns the
// vehicle continuously and leaves the terminal point hundreds of km off to one side, a crossrange the flown entry
// removes by reversing bank. The planner's job is the right DOWNRANGE distance; the lateral half belongs to the rev
// search and to the entry guidance's reversals.
FUNCTION eprMissPath {
    PARAMETER r0, tgtLat, tgtLng.
    LOCAL g IS eprToGeoInertial(EPR_IR, EPR_T0 + EPR_IT).   // integrated: propagated
    SET EPR_SOL_LAT TO g[0].
    SET EPR_SOL_LNG TO g[1].
    LOCAL g0 IS eprToGeoInertial(r0, EPR_T0).               // the planner's interface
    // PUBLISH WHERE THE PLANNER THINKS ITS INTERFACE IS (EPR_MP_*): the whole residual hangs on this position, and a wrong
    // geolocation of a correctly placed interface is invisible in it. Logged, these values show the geolocation directly.
    SET EPR_MP_LAT TO g0[0].
    SET EPR_MP_LNG TO g0[1].
    SET EPR_MP_TROT TO EPR_T0.
    SET EPR_MP_GC TO eprGcDist(g0[0], g0[1], tgtLat, tgtLng).
    RETURN EPR_IARC - EPR_MP_GC.
}

FUNCTION eprMissTo {
    PARAMETER tgtLat, tgtLng.
    LOCAL g IS eprToGeoInertial(EPR_IR, EPR_T0 + EPR_IT).   // integrated: propagated
    SET EPR_SOL_LAT TO g[0].
    SET EPR_SOL_LNG TO g[1].
    LOCAL d IS eprGcDist(g[0], g[1], tgtLat, tgtLng).

    // ground-track heading at the terminal point
    LOCAL vrelv IS EPR_IV - eprOmegaCross(EPR_IR).
    LOCAL upv IS EPR_IR:NORMALIZED.
    LOCAL hz IS vrelv - upv * VDOT(vrelv, upv).
    // 0, not d: the function returns a SIGNED along-track value, and an UNSIGNED great-circle distance here would report a
    // degenerate state as a large positive "long" miss and push the solver toward more bank on no information.
    IF hz:MAG < 1 { RETURN 0. }
    LOCAL en IS eprEastNorth(EPR_IR).
    IF en[0]:MAG < 0.5 { RETURN 0. }
    LOCAL hdg IS ARCTAN2(VDOT(hz, en[0]), VDOT(hz, en[1])).

    // bearing from the terminal point to the aim
    LOCAL dl IS tgtLng - g[1].
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(tgtLat),
                         COS(g[0]) * SIN(tgtLat) - SIN(g[0]) * COS(tgtLat) * COS(dl)).
    LOCAL rel IS brg - hdg.
    UNTIL rel <= 180 { SET rel TO rel - 360. }
    UNTIL rel > -180 { SET rel TO rel + 360. }
    // ALONG-TRACK PROJECTION, not the raw distance: a great-circle distance is two-dimensional and has a floor at the
    // crossrange offset, while bank controls only downrange, so a secant driving |d| to zero chases a quantity that cannot
    // reach zero. Projecting onto the ground track removes it; crossrange is the azimuth deadband's job, not the solver's.
    // aim ahead (rel near 0) -> the prediction fell SHORT -> negative
    RETURN 0 - d * COS(rel).
}


FUNCTION eprSolveStart {
    PARAMETER rv, vv, tRot, tgtLat, tgtLng.
    // RE-DATUM ON EVERY SOLVE, and use tRot = 0 for the start position: eprToGeo drifts from SHIP:GEOPOSITION as the
    // datum ages since eprArm captured it. Recapturing the datum at each solve and measuring tRot from the solve makes
    // the start position exact by construction (the tRot = 0 case), and the terminal point needs the correction only over
    // the FLIGHT time (~400 s), never over the whole entry. Costs a handful of vector operations per solve.
    eprInitGeo().
    SET EPR_R0 TO rv. SET EPR_V0 TO vv. SET EPR_T0 TO 0.
    LOCAL g IS eprToGeoLive(rv).                    // solve start: live
    SET EPR_LNG0 TO g[1].
    SET EPR_TGT_LAT TO tgtLat.
    SET EPR_TGT_LNG TO tgtLng.
    SET EPR_LAT_ON TO EPR_PRED_LATERAL.    // every trial flies the lateral logic (Sol)
    SET EPR_LAT_TROT TO 0.                 // eprInitGeo above put the geo frame at NOW: a trial's t = 0 is its epoch
    SET EPR_PH TO "lo".
    SET EPR_SIT TO 0.
    SET EPR_STEPS TO 0.
    SET EPR_SOLVE_T0 TO TIME:SECONDS.
    SET EPR_ST_ALT TO rv:MAG - EPR_R.
    LOCAL vrel0 IS vv - eprOmegaCross(rv).
    SET EPR_ST_VEL TO vrel0:MAG.
    SET EPR_ST_VS TO VDOT(vrel0, rv:NORMALIZED).
    SET EPR_ST_LAT TO g[0].
    SET EPR_ST_LNG TO g[1].
    SET EPR_ST_KLAT TO SHIP:GEOPOSITION:LAT.
    SET EPR_ST_KLNG TO SHIP:GEOPOSITION:LNG.
    LOCAL hz0 IS vrel0 - rv:NORMALIZED * VDOT(vrel0, rv:NORMALIZED).
    LOCAL en0 IS eprEastNorth(rv).
    IF hz0:MAG > 1 AND en0[0]:MAG > 0.5 {
        SET EPR_ST_HDG TO ARCTAN2(VDOT(hz0, en0[0]), VDOT(hz0, en0[1])).
    }
    eprIntStart(rv, vv, EPR_BANK_MIN).
}

// Drive the state machine. Call once per tick with a step budget.
FUNCTION eprSolveRun {
    PARAMETER budget.
    IF EPR_PH = "idle" OR EPR_PH = "done" { RETURN TRUE. }
    IF NOT eprIntRun(budget) { RETURN FALSE. }

    IF EPR_PH = "lo" {
        IF NOT EPR_IOK { eprPublish(EPR_BANK_MIN, 0, "nosolution"). RETURN TRUE. }
        SET EPR_RLONG TO eprMissTo(EPR_TGT_LAT, EPR_TGT_LNG).   // signed: + = beyond the aim
        SET EPR_LO_LAT TO EPR_SOL_LAT.
        SET EPR_LO_LNG TO EPR_SOL_LNG.
        SET EPR_PH TO "hi".
        eprIntStart(EPR_R0, EPR_V0, EPR_BANK_MAX).
        RETURN FALSE.
    }
    IF EPR_PH = "hi" {
        IF NOT EPR_IOK { eprPublish(EPR_BANK_MAX, 0, "nosolution"). RETURN TRUE. }
        SET EPR_RSHORT TO eprMissTo(EPR_TGT_LAT, EPR_TGT_LNG).  // max bank = shortest range
        SET EPR_HI_LAT TO EPR_SOL_LAT.
        SET EPR_HI_LNG TO EPR_SOL_LNG.
        // wings level still SHORT of the aim -> cannot reach it at any bank
        IF EPR_RLONG < 0 {
            SET EPR_SOL_LAT TO EPR_LO_LAT.     // report where BANK_MIN lands, not BANK_MAX
            SET EPR_SOL_LNG TO EPR_LO_LNG.
            eprPublish(EPR_BANK_MIN, EPR_RLONG, "low"). RETURN TRUE.
        }
        // max bank still BEYOND the aim -> cannot shed enough range
        IF EPR_RSHORT > 0 {
            SET EPR_SOL_LAT TO EPR_HI_LAT.
            SET EPR_SOL_LNG TO EPR_HI_LNG.
            eprPublish(EPR_BANK_MAX, EPR_RSHORT, "high"). RETURN TRUE.
        }
        SET EPR_SB0 TO EPR_BANK_MIN. SET EPR_SF0 TO EPR_RLONG.
        SET EPR_SB1 TO EPR_BANK_MAX. SET EPR_SF1 TO EPR_RSHORT.
        SET EPR_PH TO "sec".
        SET EPR_SIT TO 0.
        eprSecantNext().
        RETURN FALSE.
    }
    IF EPR_PH = "sec" {
        IF NOT EPR_IOK { eprPublish(EPR_IBK, EPR_SF1, "nosolution"). RETURN TRUE. }
        LOCAL f IS eprMissTo(EPR_TGT_LAT, EPR_TGT_LNG).
        SET EPR_SB0 TO EPR_SB1. SET EPR_SF0 TO EPR_SF1.
        SET EPR_SB1 TO EPR_IBK. SET EPR_SF1 TO f.
        SET EPR_SIT TO EPR_SIT + 1.
        IF ABS(f) <= EPR_STOL OR EPR_SIT >= EPR_SMAXIT {
            eprPublish(EPR_IBK, f, "none"). RETURN TRUE.
        }
        eprSecantNext().
        RETURN FALSE.
    }
    RETURN TRUE.
}

FUNCTION eprSecantNext {
    LOCAL b IS EPR_SB1.
    // GUARD AGAINST A DEGENERATE SECANT: two residuals nearly equal mean the step is inside the noise, and dividing by that
    // difference extrapolates to nonsense. The threshold is the jitter scale, not machine epsilon, because that is what
    // limits the solve.
    IF ABS(EPR_SF1 - EPR_SF0) > 200 {
        SET b TO EPR_SB1 - EPR_SF1 * (EPR_SB1 - EPR_SB0) / (EPR_SF1 - EPR_SF0).
    }
    SET b TO MAX(EPR_BANK_MIN, MIN(EPR_BANK_MAX, b)).
    eprIntStart(EPR_R0, EPR_V0, b).
}

FUNCTION eprPublish {
    PARAMETER bankDeg, miss, sat.
    SET EPR_SOLVE_DT TO TIME:SECONDS - EPR_SOLVE_T0.
    SET EPR_SOL_BANK TO bankDeg.
    SET EPR_SOL_MISS TO miss.
    SET EPR_SOL_SAT TO sat.
    SET EPR_SOL_N TO EPR_SOL_N + 1.
    SET EPR_PH TO "done".
    SET EPR_LAT_ON TO FALSE.
}

// ---------------------------------------------------------------- lateral logic
// eprAzError for a PREDICTED state: the same, but the position is converted with the body's rotation over tRot s since the
// geo frame's epoch (eprToGeoInertial); eprAzError itself uses the live conversion, right for the vehicle's current state
// only (Sol turns 8.4 deg of longitude per 1000 s).
FUNCTION eprAzErrorAt {
    PARAMETER rv, vv, tRot, tgtLat, tgtLng.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL upv IS rv:NORMALIZED.
    LOCAL hz IS vrelv - upv * VDOT(vrelv, upv).
    IF hz:MAG < 1 { RETURN 0. }
    LOCAL g IS eprToGeoInertial(rv, tRot).
    LOCAL eq IS rv - EPR_WAXIS * VDOT(rv, EPR_WAXIS).
    IF eq:MAG < 1 { RETURN 0. }
    LOCAL en IS eprEastNorth(rv).
    IF en[0]:MAG < 0.5 { RETURN 0. }
    LOCAL hdg IS ARCTAN2(VDOT(hz, en[0]), VDOT(hz, en[1])).
    LOCAL dl IS tgtLng - g[1].
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(tgtLat), COS(g[0]) * SIN(tgtLat) - SIN(g[0]) * COS(tgtLat) * COS(dl)).
    LOCAL e IS -(brg - hdg).
    UNTIL e <= 180 { SET e TO e - 360. }
    UNTIL e > -180 { SET e TO e + 360. }
    RETURN e.
}

FUNCTION eprAzError {
    PARAMETER rv, vv, tRot, tgtLat, tgtLng.
    LOCAL vrelv IS vv - eprOmegaCross(rv).
    LOCAL upv IS rv:NORMALIZED.
    LOCAL hz IS vrelv - upv * VDOT(vrelv, upv).
    IF hz:MAG < 1 { RETURN 0. }
    LOCAL g IS eprToGeoLive(rv).                    // azimuth: live kOS position
    LOCAL eq IS rv - EPR_WAXIS * VDOT(rv, EPR_WAXIS).
    IF eq:MAG < 1 { RETURN 0. }
    LOCAL en IS eprEastNorth(rv).
    LOCAL east IS en[0].
    LOCAL nrth IS en[1].
    IF east:MAG < 0.5 { RETURN 0. }
    LOCAL hdg IS ARCTAN2(VDOT(hz, east), VDOT(hz, nrth)).
    LOCAL dl IS tgtLng - g[1].
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(tgtLat),
                         COS(g[0]) * SIN(tgtLat) - SIN(g[0]) * COS(tgtLat) * COS(dl)).
    // NEGATED: the cross-track and azimuth formulae share the sin(brg - hdg) factor and so a sign convention that needed
    // inverting; with the raw sign the closed loop banks away from the target.
    LOCAL e IS -(brg - hdg).
    UNTIL e <= 180 { SET e TO e - 360. }
    UNTIL e > -180 { SET e TO e + 360. }
    RETURN e.
}

// ---------------------------------------------------------------- shadow-mode driver
GLOBAL EPR_BUDGET IS 40.         // RK2 steps per call; 40 makes a solve take about 4 s
// EPR_TGT_LAT / EPR_TGT_LNG are declared ONCE, with the solve state above: a second declaration
// is a place for the two to diverge, and it hides which one a reader should trust.
GLOBAL EPR_T_EPOCH IS 0.

FUNCTION eprArm {
    PARAMETER tgtLat, tgtLng.
    SET EPR_TGT_LAT TO tgtLat.
    SET EPR_TGT_LNG TO tgtLng.
    SET EPR_T_EPOCH TO TIME:SECONDS.
    SET EPR_PH TO "idle".
    SET EPR_LAT_ON TO FALSE.
    SET EPR_HAC_ON TO FALSE.            // EPR_FAM_ADD (1): the flight code arms the plan's HAC after this (eprArmHac)
    SET EPR_FAM_ADD_PREP TO FALSE.
    eprInitGeo().
}

