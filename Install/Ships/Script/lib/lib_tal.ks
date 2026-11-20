// ============================================================================================================
//  lib_tal.ks  --  THE TAL ENTRY'S OWN LIBRARY (OPS 6: ops6q.ks)
// ============================================================================================================
//  The TAL flies the same entry family as the nominal entry, built in OPS 6 after MECO, with a 0 deg pre-bank at 43 deg
//  alpha. The members and the vehicle fly the same pre-entry: bank 0 (EPR_PREENTRY_BANK, set by ops6q) at alpha TAL_A0
//  until guidance initiate (the model drag >= EPR_GUID_DRAG_INIT), then ONE ramp onto the nominal alpha schedule: the
//  orbiter's TAL reconfiguration (FSSR STS 83-0001-34 4.5.2.11, EGALPCMD: two quadratic segments ending TAL_VALPD1
//  below the speed at the switch).
//  DEVIATIONS FROM THE ORBITER: the ramp starts at initiate (the FSSR's when DRAG > DREFP + DRFPB after the phase
//  change); VNOALP is not modelled (the alpha modulation fades in only below EPR_AM_V_FULL); VALPD1 / VALPD2 are
//  mission I-loads with no FSSR values: this vehicle's.
//  THE SHARED lib/entry_predict.ks IS NOT EDITED. Its six functions whose alpha comes from eprAoA are COPIED here under
//  tal* names with ONLY these edits (generated and checked by the offline staging tool, which re-extracts each original
//  and fails if one changed shape):
//    talAccel       = eprAccel        aoa = talAoA(vr, the member's latch)
//    talFamBankAt   = eprFamBankAt    the initiate test at TAL_A0; latches TAL_FAM_VI
//    talTraceSample = eprTraceSample  the sampled (stored) drag at talAoA(vr, the member's latch)
//    talIntRun      = eprIntRun       calls talFamBankAt / talAccel / talTraceSample
//    talFamRun      = eprFamRun       calls talIntRun
//    talGuidStep    = eprGuidStep     dNow and sched at talAoA(vr, the vehicle's latch); latches TAL_VEH_VI / TAL_VEH_T
//  Everything else is entry_predict's (eprFamStart / BeginMember / StoreMember / Finish, eprFamInvert / Ref / Roll,
//  eprIntStart, the aero). Load it AFTER entry_predict.ks.
//  AT THE END: the generic TAL TRAJ lines: talGenRead, talGenAt, talGenBankRange, talTrajRange (appended by the
//  staging tool).
//  V4n: the servo's overbank and the Nz limiter -- the block above TAL_V4N, talV4nArm / talNzAt / talNzStep before the
//  TRAJ lines, talGuidStep's edits marked "TAL V4n"; entry_predict.ks carries EPR_FAM_UTOP (the servo's and eprFamRef's
//  top) and EPR_BANK_MAX_ABORT. The Nz limiter's F2 (talNzStep, talNzAt, the cap in talGuidStep) does not cycle.
// ============================================================================================================

GLOBAL TAL_A0 IS 43.          // deg: the TAL alpha from MECO to guidance initiate (SCOM 6.4's 43 deg TAL pullout)
GLOBAL TAL_VALPD1 IS 500.     // m/s: the ramp reaches the nominal schedule this far below the speed at initiate (FSSR VALPD1)
GLOBAL TAL_VALPD2 IS 250.     // m/s: its two segments meet this far below it (FSSR VALPD2)
GLOBAL TAL_FAM_VI IS -1.      // m/s: the member being built: its speed at its initiate (read only while EPR_FAM_STARTED)
GLOBAL TAL_VEH_VI IS -1.      // m/s: the vehicle's speed at its initiate (read only while EPR_GS_STARTED)
GLOBAL TAL_VEH_T IS -1.       // TIME:SECONDS of the vehicle's initiate (-1 = not yet)

// V4n, THE SERVO'S OVERBANK AND THE Nz LIMITER (no new family member: a command from the servo, to reach the target u
// a little faster; Nz at most 3.9 g). Offline, over 53 staged TAL cases x 8 dispersions: none past the aim (without it
// 18 of 424, up to 44 km), peak Nz <= 3.86 g. A TAL only (ops6q: talV4nArm): (1) the servo may command u past the top
// member, to EPR_FAM_UTOP = 1 + EPR_FAM_SRV_DMAX, and the references (eprFamRef / eprFamRoll) run on along the top
// segment there; (2) the bank command's clamp is EPR_BANK_MAX_ABORT (120; the TAEM ramp's scale stays EPR_BANK_MAX);
// (3) after the alpha modulation the alpha command is the lower of the modulation's and the alpha that gives TAL_NZ_SET
// at this q (talNzStep). DEVIATION FROM THE WORKBOOK: it keeps the modulation within +-3 deg of the schedule; the limit
// may go TAL_NZ_DA below it (the limiter is not the orbiter's). TAL_V4N FALSE = no overbank, no limiter.
// THE LIMITER (F2): leading its Nz by the Nz's own rise since the last drag sample (a rise its own alpha cut makes) and
// releasing below an arm cycles in the game's loop (alpha 27.8..39.2 deg, Nz 5.27 g on a flight). F2 carries the
// measured drag to each alpha on the FLOWN slope (eprAmSlopeK, as the modulation's), leads by the air data's q rise
// (alpha-free), solves on every drag sample (no arm) and the cap follows the solve down at once and up at TAL_NZ_RATE
// deg/s (offline on that flight: alpha swing 0.08 deg, Nz 3.75 g; over the 53 TAL cases x 8 dispersions at a 3.7 g set
// point: lands as without F2, peak Nz <= 3.87 g).
GLOBAL TAL_V4N IS TRUE.       // the switch (ops6q arms it for a TAL)
GLOBAL TAL_V4N_ON IS FALSE.   // armed for this flight (talV4nArm)
// THE H-DOT GATE: with the drag far under the reference (6-8 against 12 m/s2) the H-dot bias sits on its clamp
// (EPR_HDOT_MAX 60 m/s against K_HDOT x the error 100-250) at a saturated family (u 1.15), so the desired sink stays
// shallower than the flown -150 m/s and the loop's bank correction holds -EPR_TRK_MAX (-25 deg: 74.6 -> ~50 deg of
// bank) for ~60 s: less drag, an overshoot (ENTRY -> TAEM BY RANGE at Mach 3.6). A DEVIATION: while K_HDOT x the drag
// error is under -EPR_HDOT_MAX (the bias clamped low) the correction may not be negative (it may still add bank).
// Offline closed loop (the same TAL guidance + the V4n / F2 limiter): that flight +15.4 km EOW / handover 35 km from
// the site -> +6.1 / 50.7 (the aim 52); 4 1EO cases unchanged (the gate never acts); 4 2EO cases: EOW +0.6..+3.3 km
// (+3.3..+7.3 without). The entry's other guidance (ops3q's eprGuidStep) untouched. FALSE = no gate.
GLOBAL TAL_HDOT_GATE IS TRUE.
// THE TAL'S RANGE TO GO RUNS THROUGH THE HAC (the TAL only: it does not help a deorbit's entry). The family's range (a
// great-circle radius from the site, eprFamRngTo) ignores the arrival's bearing, which moves TAEM's own predicted path
// (rpred) +-5 km at the same radius: a cause of TAL overshoots (+6.2 km EOW - EN on a flight). Inside TAL_RHG_BLB of
// that range the guidance flies on TAEM's path (talHacPath: straight to the HAC tangency + the spiral arc + the final,
// taemg's R1 / R2 / PSHA_MAX, the plan's HAC as eprArmHac armed it) minus TAL_RHG_RSTAR, in full inside TAL_RHG_BLA,
// blended linearly between. Offline closed loop: that flight +6.2 -> +0.8 km, the normal 1EO TALs +3.2 -> +1.0, the 2EO
// +8.5 -> +6.7 (tighter); the real orbiter's entry range runs through the HAC too. FALSE = the family's range alone.
GLOBAL TAL_RHG_ON IS TRUE.
GLOBAL TAL_RHG_RSTAR IS 98000.  // m: R*, the HAC path's range at the TAEM interface
GLOBAL TAL_RHG_BLA IS 300000.   // m of the family's range: the HAC path in full inside this
GLOBAL TAL_RHG_BLB IS 600000.   // m: none past this
GLOBAL TAL_HAC_TLAT IS 0.       // the plan's HAC (talArmRhg, beside eprArmHac): the runway threshold, heading, the centre's
GLOBAL TAL_HAC_TLNG IS 0.       //   x (m along the heading, negative uprange) and the spiral's radius at PSHA 0
GLOBAL TAL_HAC_HDG IS 0.
GLOBAL TAL_HAC_XC IS 0.
GLOBAL TAL_HAC_RF IS 0.
GLOBAL TAL_NZ_SET IS 3.70.    // g: the limiter's set point (0.2 under the 3.9 g limit)
GLOBAL TAL_NZ_LEAD IS 2.      // s: the air data's q rise added, its rate since the last drag sample x this
GLOBAL TAL_NZ_RATE IS 2.      // deg/s: the cap's rise (a drop at once)
GLOBAL TAL_NZ_DA IS 10.       // deg: the limit's floor below the schedule (python NZ_DA)
GLOBAL TAL_NZ_ITER IS 12.     // bisection steps: 13 deg / 2^12 = 0.003 deg (python 40)
GLOBAL TAL_NZ_QPREV IS -1.    // the last sample's q (-1 = none yet)
GLOBAL TAL_NZ_EL IS 0.        // s since the last sample (talGuidStep adds its dt)
GLOBAL TAL_NZ_A IS -1.        // deg: the limit alpha from the last sample (-1 = none yet)
GLOBAL TAL_NZ_CAP IS -1.      // deg: the cap on the alpha command, TAL_NZ_A rate-limited up (-1 = none yet)
GLOBAL TAL_NZ_NOW IS -1.      // g: the last sample's Nz, led (the log's tal_nz)
GLOBAL TAL_NZ_N IS 0.         // cycles in which the limit cut the alpha command
GLOBAL TAL_V4N_SAID_U IS FALSE.    // ops6q's two event lines: once each
GLOBAL TAL_V4N_SAID_NZ IS FALSE.

// THE TAL ALPHA at speed vr for an entry that initiated at vi (vi < 0: not yet). Above vi (or before initiate): TAL_A0.
// From vi down to vi - TAL_VALPD1 the FSSR's two quadratics (segment 12 flat at vi; value and slope continuous at
// vi - TAL_VALPD2 and onto the nominal schedule at vi - TAL_VALPD1), written about their end points: the same
// polynomials as the FSSR's CALP0 / CALP1 / CALP2 form (ALPCMD = TAL_A0, ALP3 = the schedule at VALP10, ALPDT3 its
// slope), without that form's cancellation. Below: eprAoA, the nominal schedule.
FUNCTION talAoA {
    PARAMETER vr, vi.
    IF vi < 0 OR vr >= vi { RETURN TAL_A0. }
    LOCAL v10 IS vi - TAL_VALPD1.
    IF vr < v10 { RETURN eprAoA(vr). }
    LOCAL v11 IS vi - TAL_VALPD2.
    LOCAL alp3 IS eprAoA(v10).
    LOCAL adt3 IS 0.
    IF v10 > EPR_AOA_LOW_SPEED AND v10 < EPR_AOA_HIGH_SPEED {
        SET adt3 TO (EPR_AOA_HIGH - EPR_AOA_LOW) / (EPR_AOA_HIGH_SPEED - EPR_AOA_LOW_SPEED).
    }
    LOCAL dl1 IS vi - v10.
    LOCAL dl2 IS vi - v11.
    LOCAL dl3 IS v11 - v10.
    LOCAL c211 IS 0 - (alp3 - TAL_A0 + adt3 * (dl3 + 0.5 * dl2)) / (dl3 * dl1).
    IF vr < v11 {
        LOCAL x1 IS vr - v10.
        RETURN alp3 + adt3 * x1 + c211 * x1 * x1.
    }
    LOCAL c212 IS 0 - (adt3 + 2 * c211 * dl3) / (2 * dl2).
    LOCAL x2 IS vr - vi.
    RETURN TAL_A0 + c212 * x2 * x2.
}

// eprFamStart (the Kepler coast to the interface, then the first member), the TAL members' latch cleared.
FUNCTION talFamStart {
    PARAMETER rv, vv.
    SET TAL_FAM_VI TO -1.
    SET EPR_FAM_CS_TAL TO LIST(TAL_A0, TAL_VALPD1, TAL_VALPD2).   // the C# build flies the TAL alpha (Fam.cs TAL)
    eprFamStart(rv, vv).
    SET EPR_FAM_CS_TAL TO LIST().
}

// ---- talAccel: a copy of entry_predict's eprAccel (stage_ops6.py; the edits are marked TAL) ----
FUNCTION talAccel {
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
    LOCAL aoa IS talAoA(vr, (CHOOSE TAL_FAM_VI IF EPR_FAM_STARTED ELSE -1)).   // TAL: the member's alpha
    LOCAL pr IS eprPrMult(rho * vr).
    // ONE eprPolar for the whole step: this is the integrator's inner loop, and eprCda plus
    // eprCla with the same arguments would evaluate the two lift terms twice.
    LOCAL pol IS eprPolar(aoa, mach).
    // THE ENTRY'S DRAG, as eprAccel's: the polar x (1 + eprCdFix) x (1 + eprSbFrac) = eprCdaEntry, the drag the
    // stored column (talTraceSample) carries. The raw polar alone runs the members' range tables long.
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

// ---- talFamBankAt: a copy of entry_predict's eprFamBankAt (stage_ops6.py; the edits are marked TAL) ----
FUNCTION talFamBankAt {
    PARAMETER altm, vr.
    // THE GUIDANCE-INITIATE LATCH IS CHECKED HERE, PER STEP, not once per eprFamRun call: a call advances up to `budget`
    // steps, so a latch tested once per call would leave every member flying EPR_PREENTRY_BANK for hundreds of steps
    // past initiate.
    IF NOT EPR_FAM_STARTED AND altm < EPR_ATM AND vr > 1 {
        LOCAL rho IS eprRho(altm).
        IF rho > 0 {
            LOCAL pr IS eprPrMult(rho * vr).
            IF eprCdaEntry(talAoA(vr, -1), eprMachFrom(altm, vr, rho), vr) * 0.5 * rho * vr * vr * pr   // TAL: at TAL_A0
                   >= EPR_GUID_DRAG_INIT {
                SET EPR_FAM_STARTED TO TRUE.
                SET TAL_FAM_VI TO vr.                // TAL: the alpha ramp starts at this speed
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
    SET EPR_FAM_BANK_PRE TO b.        // the bank before the ramp, for the bank column
    RETURN eprBankWithFlare(b, vr).
}

// ---- talTraceSample: a copy of entry_predict's eprTraceSample (stage_ops6.py; the edits are marked TAL) ----
FUNCTION talTraceSample {
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
    LOCAL drag IS eprCdaEntry(talAoA(vr, (CHOOSE TAL_FAM_VI IF EPR_FAM_STARTED ELSE -1)), eprMachFrom(altm, vr, rho), vr) * qdyn * pr.   // TAL
    EPR_TR_V:ADD(vr).
    EPR_TR_D:ADD(drag).
    EPR_TR_S:ADD(VDOT(vrelv, rv / rmag)).
    EPR_TR_A:ADD(altm).
    // Arc and flown bank, for the family. RANGE-TO-GO is filled in afterwards by running the
    // arc column backwards from the terminal point -- it cannot be known forwards.
    EPR_TR_ARC:ADD(EPR_FAM_ARC).
    EPR_TR_BK:ADD(EPR_FAM_BANK_NOW).
}

// ---- talIntRun: a copy of entry_predict's eprIntRun (stage_ops6.py; the edits are marked TAL) ----
FUNCTION talIntRun {
    PARAMETER budget.
    LOCAL k IS 0.
    // a family build runs on to EPR_FAM_EXT_V (the TAEM bank ramp still ends at EPR_TAEM_VEL); the
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
                // the arc to the crossing too (python's carry-on to exactly FAM_EXT_V), so the members'
                // range to go ends at the crossing, not up to a step past it
                IF famAdd { SET EPR_FAM_ARC TO EPR_PARC + (EPR_IARC - EPR_PARC) * fr. }
            }
            // AN END SAMPLE at the crossing (range to go 0). A member is sampled every EPR_TRACE_EVERY
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
        SET EPR_PARC TO EPR_IARC.         // the arc at this state, for the crossing
        // PER-STEP BANK. EPR_IBK is a constant for the solver; the family needs a bank that changes with state (preentry
        // hold, then the member's bank, capped by the Nz arrest ramp and the terminal flare). Hooked here so there is one
        // integrator loop, with eprIntRun's interpolate-to-crossing logic.
        LOCAL bnk IS EPR_IBK.
        IF EPR_FAM_ACTIVE { SET bnk TO talFamBankAt(altm, vr). }
        IF EPR_LAT_ON { SET bnk TO eprLatBank(EPR_IBK, EPR_IR, EPR_IV, EPR_IT). }   // PRED_LATERAL
        LOCAL a1 IS talAccel(EPR_IR, EPR_IV, bnk).
        LOCAL rm IS EPR_IR + EPR_IV * (0.5 * EPR_IDT).
        LOCAL vm IS EPR_IV + a1 * (0.5 * EPR_IDT).
        LOCAL a2 IS talAccel(rm, vm, bnk).
        SET EPR_FAM_BANK_NOW TO bnk.
        // the members' bank column BEFORE the TAEM ramp (python's col 7): the step ramps
        // the reference roll once (the column after the ramp would ramp it twice)
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
            // a family build samples EVERY STEP below EPR_FAM_FINE_V: the excess and the end of the
            // inversion read the members near EPR_TAEM_VEL, where 10 s between samples is coarse (python: 1 s)
            IF famAdd AND vr < EPR_FAM_FINE_V { SET EPR_TRACE_K TO EPR_TRACE_EVERY. }
            IF EPR_TRACE_K >= EPR_TRACE_EVERY {
                SET EPR_TRACE_K TO 0.
                talTraceSample(EPR_IR, EPR_IV).
            }
        }
        SET k TO k + 1.
        SET EPR_STEPS TO EPR_STEPS + 1.
    }
    RETURN FALSE.
}

// ---- talFamRun: a copy of entry_predict's eprFamRun (stage_ops6.py; the edits are marked TAL) ----
FUNCTION talFamRun {
    PARAMETER budget.
    IF EPR_FAM_READY { RETURN TRUE. }
    IF EPR_FAM_CS_ON { RETURN eprFamCsRun(). }     // the addon's build (entry_predict's block above EPR_FAM_CS)
    // The guidance-initiate latch lives in eprFamBankAt, which runs per STEP -- see there.
    IF talIntRun(budget) {
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

// the plan's HAC for the TAL's range to go: the same arguments as eprArmHac (its side: EPR_HAC_YSGN)
FUNCTION talArmRhg {
    PARAMETER thrLat, thrLng, hdg, xc, rf.
    SET TAL_HAC_TLAT TO thrLat.
    SET TAL_HAC_TLNG TO thrLng.
    SET TAL_HAC_HDG TO hdg.
    SET TAL_HAC_XC TO xc.
    SET TAL_HAC_RF TO rf.
}

// TAEM's predicted ground path (taemg_gtp's rpred without the acquisition turn: rtan to the tangency + the spiral arc
// + the final -xc) from a ground position, in the plan runway's threshold frame (x = d cos(rel), y = d sin(rel)); two passes
// (psha from 0, then again from that, gtp's order). Python: entry_predict.fam_hac_path; C#: EntryGuid.TalHacPath.
FUNCTION talHacPath {
    PARAMETER glat, glng.
    LOCAL d IS eprGcDist(TAL_HAC_TLAT, TAL_HAC_TLNG, glat, glng).
    LOCAL dl IS glng - TAL_HAC_TLNG.
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(glat), COS(TAL_HAC_TLAT) * SIN(glat) - SIN(TAL_HAC_TLAT) * COS(glat) * COS(dl)).
    LOCAL rel IS brg - TAL_HAC_HDG.
    LOCAL x IS d * COS(rel).
    LOCAL y IS d * SIN(rel).
    LOCAL ys IS EPR_HAC_YSGN.
    LOCAL rf IS TAL_HAC_RF.
    LOCAL xcir IS TAL_HAC_XC - x.
    LOCAL ycir IS ys * rf - y.
    LOCAL rcir IS SQRT(xcir * xcir + ycir * ycir).
    LOCAL signy IS 1.
    IF y < 0 { SET signy TO -1. }
    LOCAL pp IS 0.
    LOCAL rtan IS 0.
    FROM { LOCAL k IS 0. } UNTIL k >= 2 STEP { SET k TO k + 1. } DO {
        LOCAL rturn IS rf + TG_R1 * pp + TG_R2 * pp * pp.
        SET rtan TO 0.
        IF rcir > rturn { SET rtan TO SQRT(rcir * rcir - rturn * rturn). }
        LOCAL pst IS ARCTAN2(ycir, xcir) - ys * ARCTAN2(rturn, rtan).
        UNTIL pst <= 180 { SET pst TO pst - 360. }
        UNTIL pst > -180 { SET pst TO pst + 360. }
        LOCAL pshan IS 0 - pst * ys.
        LOCAL acq IS pp > 0 AND pp <= 30.
        IF ((NOT acq) AND (pshan < -1 OR ys <> signy)) OR (pp > 90 AND pshan < pp - 180) { SET pshan TO pshan + 360. }
        SET pp TO MAX(0, MIN(TG_PSHA_MAX, pshan)).
    }
    RETURN (rf * pp + 0.5 * TG_R1 * pp * pp + (1 / 3) * TG_R2 * pp ^ 3) * CONSTANT:DEGTORAD - TAL_HAC_XC + rtan.
}

// the TAL's range to go: the family's range (eprFamRngTo), the HAC path - R* blended in inside TAL_RHG_BLB
FUNCTION talRngTo {
    PARAMETER glat, glng, tgtLat, tgtLng.
    LOCAL rgc IS eprFamRngTo(glat, glng, tgtLat, tgtLng).
    IF (NOT TAL_RHG_ON) OR (NOT EPR_FAM_ADD) OR (NOT EPR_HAC_ON) OR TAL_HAC_RF <= 0 OR rgc >= TAL_RHG_BLB { RETURN rgc. }
    LOCAL rh IS talHacPath(glat, glng) - TAL_RHG_RSTAR.
    LOCAL w IS 1.
    IF rgc > TAL_RHG_BLA { SET w TO (TAL_RHG_BLB - rgc) / (TAL_RHG_BLB - TAL_RHG_BLA). }
    RETURN rgc + w * (rh - rgc).
}

// the dispatcher (entry_predict.ks's EPR_GS_CS block): the addon's cycle (coproc/EntryGuid.cs, the TAL's
// edits included), or kOS's talGuidStepK below.
FUNCTION talGuidStep {
    PARAMETER rv, vv, tgtLat, tgtLng, tRot, dt IS -1, dMeas IS -1, aoaNow IS -1, fdN IS -1.
    IF aoaNow > 0 { SET EPR_AM_G TO eprAmGain(). }   // the step's share this cycle (kOS and the addon alike)
    IF EPR_GS_CS AND eprGsCsReady() {
        LOCAL inp IS eprGsCsIn(TRUE, rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN).
        LOCAL res IS eprGsCsStep(inp).
        IF res:ISTYPE("Scalar") { RETURN res. }
    }
    RETURN talGuidStepK(rv, vv, tgtLat, tgtLng, tRot, dt, dMeas, aoaNow, fdN).
}

// ---- talGuidStepK: a copy of entry_predict's eprGuidStep (the staging tool's; the edits are marked TAL; the
// dispatcher talGuidStep above) ----
FUNCTION talGuidStepK {
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
    SET TAL_NZ_EL TO TAL_NZ_EL + dtc.     // TAL V4n (3): the time since the limiter's last drag sample
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
        SET dNow TO eprCdaEntry(talAoA(vr, (CHOOSE TAL_VEH_VI IF EPR_GS_STARTED ELSE -1)), mach, vr) * 0.5 * rho * vr * vr * pr.   // TAL
    }
    // THE INITIATE THRESHOLD STAYS ON THE MODEL, ON PURPOSE: fam_build decides which samples to store with the same test
    // against the same model, so guidance must start where the family starts. Only the CONTROL error uses the measurement.
    IF dNow >= EPR_GUID_DRAG_INIT {
        IF NOT EPR_GS_STARTED {               // TAL: the vehicle's alpha ramp starts at this speed
            SET TAL_VEH_VI TO vr.
            SET TAL_VEH_T TO TIME:SECONDS.
        }
        SET EPR_GS_STARTED TO TRUE.
    }
    // ARGUMENT ORDER: eprAzError is (rv, vv, tRot, tgtLat, tgtLng), tRot THIRD. Another order would not make kOS complain:
    // it would compute the azimuth to a target at latitude tRot and longitude tgtLat.
    // with the plan's HAC armed (eprArmHac) the heading error is to the HAC centre
    LOCAL famAddHac IS EPR_FAM_ADD AND EPR_HAC_ON.
    IF famAddHac { SET EPR_GS_AZ TO eprAzError(rv, vv, tRot, EPR_HAC_LAT, EPR_HAC_LNG). }
    ELSE { SET EPR_GS_AZ TO eprAzError(rv, vv, tRot, tgtLat, tgtLng). }

    LOCAL mag IS EPR_PREENTRY_BANK.
    IF EPR_GS_STARTED AND EPR_FAM_READY AND EPR_FAM_OK {
        LOCAL gi IS eprToGeoLive(rv).                  // guidance: live kOS position
        LOCAL rng IS talRngTo(gi[0], gi[1], tgtLat, tgtLng).   // to the HAC's origin when armed; TAEM's HAC path

        // PAST THE TARGET, RANGE-TO-GO MUST GO NEGATIVE. eprGcDist is an unsigned great-circle distance: once the vehicle
        // overflies the aim point it grows again, and the inversion would read that as falling short and command LESS bank.
        // EPR_GS_AZ is the signed angle from heading to the bearing to the target; beyond 90 deg the target is BEHIND.
        // Negating the range drives eprFamInvert to u = 1, maximum bank, which is the correct response.
        // THIS IS A GUARD, NOT A RECOVERY: reaching this state means the entry already failed upstream (TAEM should have
        // taken over at 762 m/s). It keeps guidance from deepening the failure, and the log says plainly that it happened.
        SET EPR_GS_PAST TO (ABS(EPR_GS_AZ) > 90).
        IF EPR_GS_PAST AND NOT famAddHac { SET rng TO -rng. }   // the HAC range is signed already
        SET rng TO rng + eprFamExcess().                  // the excess (0 without EPR_FAM_ADD)
        // PUBLISHED SO THE LOG CAN SEE WHAT GUIDANCE THINKS ITS POSITION IS: a range error cannot otherwise be traced to
        // eprToGeo, tRot or the frame axes. IF A VALUE STEERS THE VEHICLE, IT BELONGS IN THE LOG.
        SET EPR_GS_GLAT TO gi[0].
        SET EPR_GS_GLNG TO gi[1].
        SET EPR_GS_RNG TO rng.
        SET EPR_GS_TROT TO tRot.
        LOCAL inv IS eprFamInvert(vr, rng).
        SET EPR_GS_U_ST TO inv[0].                        // the state's u for ENTRY TRAJ's U (not the
        //                                                   servo's), as entry_predict's eprGuidStep
        //                                                   sets it
        SET EPR_GS_U TO eprFamServo(inv[0], vr).          // the servo (sat stays the family's own)
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
            LOCAL sched IS talAoA(vr, TAL_VEH_VI).   // TAL: the schedule the modulation works around
            LOCAL band IS eprAmBand(vr).   // EPR_AM_V_FULL_FAM / _ZERO_FAM with EPR_FAM_ADD
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
            SET EPR_GS_DEQ TO dMeas * eprCda(sched, mach) / cdn.
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
            SET EPR_GS_ACMD TO eprLagA(MAX(sched - band, MIN(sched + band, EPR_AM_HOLD)), dtc).
            // TAL V4n (3): the Nz limiter after the modulation: talNzStep on each new drag sample (F2: the limit alpha,
            // the air data's q its lead), the cap following it down at once and up at TAL_NZ_RATE deg/s, every cycle
            IF TAL_V4N_ON {
                IF fresh { talNzStep(dMeas, aRef, sched, mach, TAL_NZ_EL, 0.5 * rho * vr * vr). SET TAL_NZ_EL TO 0. }
                IF TAL_NZ_A > 0 {
                    SET TAL_NZ_CAP TO (CHOOSE TAL_NZ_A IF TAL_NZ_CAP < 0 ELSE MIN(TAL_NZ_A, TAL_NZ_CAP + TAL_NZ_RATE * dtc)).
                    IF TAL_NZ_CAP < EPR_GS_ACMD { SET EPR_GS_ACMD TO TAL_NZ_CAP. SET TAL_NZ_N TO TAL_NZ_N + 1. }
                }
            }
        }
        // Hdot loop: a drag error is converted into a SINK RATE the vehicle should be holding,
        // and bank trims toward that. 2.12.3 -- corrections are excursions around the
        // reference roll, not a bank built from scratch.
        LOCAL hdotNow IS VDOT(vrelv, rv:NORMALIZED).
        LOCAL derrF IS eprLagD(EPR_GS_DERR, dtc).                     // the drag sample's step smoothed (entry_predict eprLagD)
        LOCAL bias IS MAX(0 - EPR_HDOT_MAX, MIN(EPR_HDOT_MAX, EPR_K_HDOT * derrF)).
        LOCAL hdotDes IS eprFamRef(vr, EPR_GS_U, 3) + bias.
        SET EPR_GS_CORR TO MAX(0 - EPR_TRK_MAX, MIN(EPR_TRK_MAX,
                               EPR_K_BANK_HDOT * (hdotNow - hdotDes))).
        // no bank taken away while the drag is so low that the bias is clamped (TAL_HDOT_GATE above)
        IF TAL_HDOT_GATE AND EPR_GS_CORR < 0 { IF EPR_K_HDOT * derrF < 0 - EPR_HDOT_MAX { SET EPR_GS_CORR TO 0. } }
        SET EPR_GS_ROLLREF TO eprFamRoll(vr, EPR_GS_U).
        // TAL V4n (2): with the overbank the clamp is EPR_BANK_MAX_ABORT (eprBankWithFlare's TAEM ramp keeps EPR_BANK_MAX)
        SET mag TO MAX(EPR_BANK_MIN, MIN((CHOOSE EPR_BANK_MAX_ABORT IF TAL_V4N_ON ELSE EPR_BANK_MAX), EPR_GS_ROLLREF + EPR_GS_CORR)).
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
    RETURN sg * eprBankWithFlare(EPR_GS_BANK, vr).
}

// ---- V4n (the block above TAL_V4N) ------------------------------------------------------------------------------------
// Arm (doArm TRUE) or disarm it for this flight and clear the limiter's state; ops6q calls it once, at the TAL's start.
FUNCTION talV4nArm {
    PARAMETER doArm.
    SET TAL_V4N_ON TO doArm.
    SET EPR_FAM_UTOP TO CHOOSE 1 + EPR_FAM_SRV_DMAX IF doArm ELSE 1.
    SET TAL_NZ_QPREV TO -1.
    SET TAL_NZ_EL TO 0.
    SET TAL_NZ_A TO -1.
    SET TAL_NZ_CAP TO -1.
    SET TAL_NZ_NOW TO -1.
    SET TAL_NZ_N TO 0.
    SET TAL_V4N_SAID_U TO FALSE.
    SET TAL_V4N_SAID_NZ TO FALSE.
}

// F2: the Nz at alpha a from the measured drag dk (x the q lead) taken at the polar drag c0 (at the sample's alpha),
// carried to a on the FLOWN slope (ks, eprAmSlopeK: the drag's change with alpha is ks x the polar's), the polar's L/D:
// D sqrt(1 + (L/D)^2) / g0 (the offline model's am_f2 nz_at, cr7 = hypot(cla_v7, cda_v7)).
FUNCTION talNzAt {
    PARAMETER a, mach, dk, ks, c0.
    LOCAL p IS eprPolar(a, mach).
    RETURN dk * (1 + ks * (p[1] - c0) / c0) * SQRT(p[0] * p[0] + p[1] * p[1]) / p[1] / EPR_G0.
}

// (3) ONE DRAG SAMPLE OF THE Nz LIMITER (F2): the lead kq = 1 + the air data's q rise since the last sample (qa, el
// s ago, floored at 0.5 s: the FD windows are >= 1 s; none on the first sample) x TAL_NZ_LEAD / qa (alpha-free: the alpha cut
// cannot feed it); the alpha whose Nz (talNzAt, the measured drag dm x kq) is TAL_NZ_SET, by bisection between
// sched - TAL_NZ_DA and sched + EPR_AM_LIM (the Nz rises with alpha there) -> TAL_NZ_A on every sample (the top end when
// it stays under, the floor when it cannot get under); TAL_NZ_NOW = the sample's Nz, led. talGuidStep caps the alpha
// command at it, the cap's rise rate-limited. Python: t17/flyob_f2.py am_f2 (one sample a 1 s step), t17/loop_model.py f2.
FUNCTION talNzStep {
    PARAMETER dm, aRef, sched, mach, el, qa.
    LOCAL kq IS 1.
    IF TAL_NZ_QPREV > 0 AND qa > 0 { SET kq TO 1 + MAX(0, qa - TAL_NZ_QPREV) / MAX(el, 0.5) * TAL_NZ_LEAD / qa. }
    SET TAL_NZ_QPREV TO qa.
    LOCAL ks IS eprAmSlopeK(mach).
    LOCAL p IS eprPolar(aRef, mach).
    LOCAL c0 IS p[1].
    LOCAL dk IS dm * kq.
    SET TAL_NZ_NOW TO dk * SQRT(p[0] * p[0] + p[1] * p[1]) / c0 / EPR_G0.
    LOCAL lo IS sched - TAL_NZ_DA.
    LOCAL hi IS sched + EPR_AM_LIM.
    IF talNzAt(hi, mach, dk, ks, c0) <= TAL_NZ_SET { SET TAL_NZ_A TO hi. RETURN. }
    IF talNzAt(lo, mach, dk, ks, c0) >= TAL_NZ_SET { SET TAL_NZ_A TO lo. RETURN. }
    FROM { LOCAL k IS 0. } UNTIL k >= TAL_NZ_ITER STEP { SET k TO k + 1. } DO {
        LOCAL mid IS 0.5 * (lo + hi).
        IF talNzAt(mid, mach, dk, ks, c0) > TAL_NZ_SET { SET hi TO mid. } ELSE { SET lo TO mid. }
    }
    SET TAL_NZ_A TO 0.5 * (lo + hi).
}
// ============================================================================================================
//  THE GENERIC TAL TRAJ LINES
// ============================================================================================================
//  A TAL's ENTRY TRAJ fixes only the velocity and places the bug by the baked bank lines: not a true range-velocity
//  plot, but more informative. Its panels are drawn ONCE, offline, from ONE generic TAL family (Zaragoza at the
//  fastest TAL MECO) and ship in Script/tal/ with the lines' own data (tal/family_tal.txt, family.txt's format), read
//  here once by talGenRead.
//  THE BUG keeps the vehicle's velocity. Its horizontal place is where the vehicle sits among the LIVE family's members
//  at that velocity (eprFamInvert's bracket, the guidance's own inversion, on the display's range to go), carried over
//  to the generic lines of the same two banks at the same fraction (talTrajRange): on a member, on that bank's line.
//  Outside the fan it moves on past the outer line, the range beyond it scaled by the outer gap.
//  THE BOX: the generic line of the bank the guidance wants, interpolated between the lines (talGenBankRange =
//  entry_predict's eprTrajBankRange on these lines; traj_display calls it through TJ_BANK_RANGE).
//  DEVIATION FROM THE ORBITER: its ENTRY TRAJ is a true range-velocity plot; this horizontal axis is not a range.

GLOBAL TAL_GEN IS LIST().     // the generic lines, banks ascending: per line LIST(bank deg, v list m/s, range list m)
GLOBAL TAL_GEN_WHY IS "".     // why talGenRead refused ("" = read)
GLOBAL TAL_GEN_GAP_MIN IS 1000.   // m: the live outer gap's floor in the scale past the fan (the members close up at the end)

// Read the generic lines from file genFile (family.txt's format: an "M index bank rows" line before each line's rows "vrel drag
// sink range bank"; the header's aero_ver). Refuses (FALSE; TAL_GEN_WHY says why; TAL_GEN empty) unless they are drawn for
// this aero model, at the live family's banks (EPR_FAM_BANKS), each with its stated row count (>= 2), its speeds strictly
// falling (talGenAt's search needs it) and no garbled number (TONUMBER's -1).
FUNCTION talGenRead {
    PARAMETER genFile.
    SET TAL_GEN TO LIST().
    SET TAL_GEN_WHY TO "".
    IF NOT EXISTS(genFile) {
        SET TAL_GEN_WHY TO genFile + " not found".
        RETURN FALSE.
    }
    LOCAL gen IS LIST().
    LOCAL rowsWant IS LIST().
    LOCAL aero IS -1.
    LOCAL it IS OPEN(genFile):READALL:ITERATOR.
    UNTIL NOT it:NEXT {
        LOCAL pp IS it:VALUE:TRIM:SPLIT(" ").
        IF pp:LENGTH = 4 AND pp[0] = "M" {
            gen:ADD(LIST(pp[2]:TONUMBER(-1), LIST(), LIST())).
            rowsWant:ADD(pp[3]:TONUMBER(-1)).
        } ELSE IF pp:LENGTH = 5 AND gen:LENGTH > 0 {
            gen[gen:LENGTH - 1][1]:ADD(pp[0]:TONUMBER(-1)).
            gen[gen:LENGTH - 1][2]:ADD(pp[3]:TONUMBER(-1)).
        } ELSE IF pp:LENGTH = 2 AND pp[0] = "aero_ver" {
            SET aero TO pp[1]:TONUMBER(-1).
        }
    }
    IF ABS(aero - EPR_AERO_VER) > 0.001 {
        SET TAL_GEN_WHY TO "TAL lines: aero model " + aero + ", not " + EPR_AERO_VER.
        RETURN FALSE.
    }
    IF gen:LENGTH <> EPR_FAM_BANKS:LENGTH {
        SET TAL_GEN_WHY TO "TAL lines: " + gen:LENGTH + " lines, not " + EPR_FAM_BANKS:LENGTH.
        RETURN FALSE.
    }
    LOCAL k IS 0.
    UNTIL k >= gen:LENGTH {
        LOCAL vs IS gen[k][1].
        LOCAL rs IS gen[k][2].
        IF ABS(gen[k][0] - EPR_FAM_BANKS[k]) > 0.001 {
            SET TAL_GEN_WHY TO "TAL lines: line " + k + " is bank " + gen[k][0] + ", not " + EPR_FAM_BANKS[k].
            RETURN FALSE.
        }
        IF vs:LENGTH < 2 OR vs:LENGTH <> rowsWant[k] {
            SET TAL_GEN_WHY TO "TAL lines: line " + k + " has " + vs:LENGTH + " rows of " + rowsWant[k].
            RETURN FALSE.
        }
        LOCAL j IS 0.
        UNTIL j >= vs:LENGTH {
            IF vs[j] <= 0 OR rs[j] < 0 {
                SET TAL_GEN_WHY TO "TAL lines: line " + k + " row " + j + " garbled".
                RETURN FALSE.
            }
            IF j > 0 {
                IF vs[j] >= vs[j - 1] {
                    SET TAL_GEN_WHY TO "TAL lines: line " + k + " speeds not falling at row " + j.
                    RETURN FALSE.
                }
            }
            SET j TO j + 1.
        }
        SET k TO k + 1.
    }
    SET TAL_GEN TO gen.
    RETURN TRUE.
}

// The generic line mi's range (m) at speed vr: linear between its rows, held at its ends (eprFamAt's interpolation; the
// bracket found by halving, the line's speeds strictly falling). gen_traj_bg draws each line through points on this
// same interpolation (row_at), so a range from here sits on the drawn line.
FUNCTION talGenAt {
    PARAMETER mi, vr.
    LOCAL vs IS TAL_GEN[mi][1].
    LOCAL rs IS TAL_GEN[mi][2].
    LOCAL nv IS vs:LENGTH.
    IF vr >= vs[0] { RETURN rs[0]. }
    IF vr <= vs[nv - 1] { RETURN rs[nv - 1]. }
    LOCAL lo IS 0.
    LOCAL hi IS nv - 1.
    UNTIL hi - lo <= 1 {
        LOCAL mid IS FLOOR((lo + hi) / 2).
        IF vs[mid] > vr { SET lo TO mid. } ELSE { SET hi TO mid. }
    }
    LOCAL fr IS (vs[lo] - vr) / (vs[lo] - vs[hi]).
    RETURN rs[lo] + (rs[hi] - rs[lo]) * fr.
}

// The range (m) of the generic line of bank `bank` at speed vr: linear in bank between the two lines around it, held at
// the outer lines; a bank on a line gives that line exactly (entry_predict's eprTrajBankRange on the generic lines). The
// box (traj_display's TJ_BANK_RANGE) and talTrajRange's lines.
FUNCTION talGenBankRange {
    PARAMETER bank, vr.
    LOCAL ng IS TAL_GEN:LENGTH.
    IF ng < 2 { RETURN 0. }
    IF bank <= TAL_GEN[0][0] { RETURN talGenAt(0, vr). }
    IF bank >= TAL_GEN[ng - 1][0] { RETURN talGenAt(ng - 1, vr). }
    LOCAL i IS 1.
    UNTIL i >= ng {
        IF bank <= TAL_GEN[i][0] {
            LOCAL r1 IS talGenAt(i, vr).
            IF bank = TAL_GEN[i][0] { RETURN r1. }
            LOCAL b0 IS TAL_GEN[i - 1][0].
            LOCAL fr IS (bank - b0) / MAX(TAL_GEN[i][0] - b0, 0.000001).
            LOCAL r0 IS talGenAt(i - 1, vr).
            RETURN r0 + (r1 - r0) * fr.
        }
        SET i TO i + 1.
    }
    RETURN talGenAt(ng - 1, vr).
}

// THE BUG'S HORIZONTAL PLACE (m on the generic panels' range axis) for the vehicle at speed vr with range to go rng (the
// display's great-circle range to the aim): eprFamInvert's bracket among the LIVE family's members at vr (banks
// EPR_FAM[i][0] ascending, a partial family too; remaining range falls with bank), the same fraction between the generic
// lines of those two banks. Beyond the first member (rng >= its range: the guidance's "low") or inside the last (rng <=
// its range: "high") it moves on past that line by the range beyond it times the outer gap generic over live (the live
// gap at least TAL_GEN_GAP_MIN), so it shows how far out the vehicle is; continuous at the outer lines, with the
// edge bracket's own scale while the live gap is above the floor.
// Call with the live family ready and usable (EPR_FAM_READY AND EPR_FAM_OK: >= 2 members, sorted by bank) and TAL_GEN read.
FUNCTION talTrajRange {
    PARAMETER vr, rng.
    LOCAL nf IS EPR_FAM:LENGTH.
    IF nf < 2 OR TAL_GEN:LENGTH < 2 { RETURN rng. }
    LOCAL ra IS eprFamAt(0, vr, 4).
    IF rng >= ra {
        LOCAL ga IS talGenBankRange(EPR_FAM[0][0], vr).
        LOCAL gb IS talGenBankRange(EPR_FAM[1][0], vr).
        RETURN ga + (rng - ra) * (ga - gb) / MAX(ra - eprFamAt(1, vr, 4), TAL_GEN_GAP_MIN).
    }
    LOCAL rz IS eprFamAt(nf - 1, vr, 4).
    IF rng <= rz {
        LOCAL gz IS talGenBankRange(EPR_FAM[nf - 1][0], vr).
        LOCAL gy IS talGenBankRange(EPR_FAM[nf - 2][0], vr).
        RETURN gz - (rz - rng) * (gy - gz) / MAX(eprFamAt(nf - 2, vr, 4) - rz, TAL_GEN_GAP_MIN).
    }
    LOCAL i IS 1.
    UNTIL i >= nf {
        LOCAL ri IS eprFamAt(i, vr, 4).
        IF ri <= rng {
            LOCAL rp IS eprFamAt(i - 1, vr, 4).
            LOCAL span IS rp - ri.
            LOCAL fr IS 0.
            IF ABS(span) > 0.000000001 { SET fr TO (rp - rng) / span. }
            LOCAL gp IS talGenBankRange(EPR_FAM[i - 1][0], vr).
            RETURN gp + (talGenBankRange(EPR_FAM[i][0], vr) - gp) * fr.
        }
        SET i TO i + 1.
    }
    RETURN talGenBankRange(EPR_FAM[nf - 1][0], vr).
}
