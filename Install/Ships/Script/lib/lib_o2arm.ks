// lib_o2arm.ks -- ops2q's PDRS CONTROL page (ONE page, a 5th page button, the pad's CUT OFF slot split into EE CAM + STOP, no live camera feed on the display).
// THE HOST: arm.ks runs here as a program of its own would, but without a window: RUNPATH("0:/arm.ks") with ARM_HOST TRUE
// builds its widgets without showing them, publishes ARM_CYCLE (one pass of its loop), ARM_END (STOP), ARM_SNAP (what the page
// shows), ARM_ACT and ARM_UI (the widgets), and ENDS; its state lives on in those delegates (proved on the kOS VM). ops2q calls ARM_CYCLE every pass while the page is up (o2aTick); the page's items press and
// release the widgets arm.ks's loop reads (SET w:PRESSED), exactly the window's own inputs. The arm is hosted only while this
// page is shown: leaving the page stops it (o2aClose) and ops2q's DAP takes the attitude again.
// No GUI of its own and no vessel except through arm.ks: tests/o2arm_selftest.ks runs it on the arm VM.
GLOBAL O2A_JN6 IS LIST("SY", "SP", "EP", "WP", "WY", "WR").
GLOBAL O2A_MODES IS LIST("SINGLE", "MAN AUG", "OPR CMD", "AUTO").
GLOBAL O2A_HOLDS IS LIST("INRTL", "LVLH", "FREE").
GLOBAL O2A_JT IS LIST("jt0", "jt1", "jt2", "jt3", "jt4", "jt5").   // The joints' CMD fields (a joint's typed target angle), one per joint
GLOBAL O2A_FLD IS LIST("cx", "cy", "cz", "cp", "cyw", "cr").   // the POR CMD row's fields: X / Y / Z m, P / Y / R deg (arm.ks's opFd order)
GLOBAL O2A_RATE_TAU IS 0.5.                  // s: the POR rate's smoothing
GLOBAL O2A_ON IS FALSE.                      // arm.ks is up (hosted)
GLOBAL ARM_HOLD_EXT IS FALSE.                // arm.ks's ARM_HOLD_EXT (o2aOpen sets it before the RUNPATH): TRUE = ops2q's DAP keeps the orbiter's attitude, the arm only holds the THC off
GLOBAL O2A_GRAPPLE_OK IS FALSE.             // FALSE = the PDRS GRAPPLE item is dim and a press does nothing; TRUE = the toggle again (the one-place revert)
GLOBAL O2A_CAPTURE_OK IS FALSE.         // FALSE = the PDRS CAPTURE item is dim and a press does nothing; TRUE = the toggle again (the one-place revert)
GLOBAL O2A_SAIL_T IS -1E9.                   // TIME:SECONDS of the last SAIL status write (o2aSailStat, every 2 s)
GLOBAL o2aSnap IS LEXICON().                 // ARM_SNAP's last answer (o2aTick)
GLOBAL O2A_SAYQ IS FALSE.                   // ops2q sets it: the messages go to its MSG row (o2qSay), else PRINT
FUNCTION o2aSay { PARAMETER s, c IS "V". IF O2A_SAYQ { o2qSay(s, c). } ELSE { PRINT s. } }
GLOBAL o2aStWas IS "".                       // arm.ks's status text sent to MSG last
GLOBAL o2aSayWas IS 0.                      // T1018: arm.ks's say counter at that send (the same word said again shows again)
GLOBAL o2aCw IS LEXICON().                   // the ARM lamp's clocks (lib_cwchk cwArmApply)
GLOBAL o2aPorT IS -1.                        // the POR rate filter: the time, the pose, the smoothed ft/s and deg/s
GLOBAL o2aPorP IS LIST().
GLOBAL o2aRt IS LIST(0, 0).
GLOBAL o2aLdWait IS 0.                       // passes until arm.ks has loaded the pose into its fields (LOAD) and the page takes them

FUNCTION o2aDefs {                           // the field rules (ops2q's o2qDefs calls it once)
    o2Def("amode", "C", 0).
    o2Def("arate", "C", 0).
    o2Def("afrm", "C", 0).
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
        IF i < 3 { o2Def(O2A_FLD[i], "N", 0, 0.01, -999, 999, 0.01, 100, 2). }    // m
        ELSE { o2Def(O2A_FLD[i], "N", 0, 1, -360, 360, 0.01, 90, 1). }           // deg
    }
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO { o2Def(O2A_JT[i], "N", 0, 0.1, -360, 360, 0.01, 90, 1). }   // Each joint's typed target angle (deg): TYPE + ENT on its CMD slews THAT joint there
}

// ---- the host
FUNCTION o2aOpen {                           // the arm up: "" or why not
    PARAMETER md IS "INRTL", ext IS FALSE.   // The hold arm.ks starts in (ORBIT / PTG's HOLD: INRTL / LVLH / FREE); ext = ops2q's DAP keeps the attitude (ARM_HOLD_EXT)
    IF O2A_ON { RETURN "". }
    IF NOT EXISTS("0:/arm.ks") { RETURN "ARM.KS NOT FOUND". }
    SET ARM_HOLD_EXT TO ext.
    IF NOT (DEFINED ARM_HOST) { GLOBAL ARM_HOST IS TRUE. } ELSE { SET ARM_HOST TO TRUE. }
    IF NOT (DEFINED ARM_HOLD) { GLOBAL ARM_HOLD IS md. } ELSE { SET ARM_HOLD TO md. }
    IF DEFINED ARM_CYCLE { UNSET ARM_CYCLE. }
    RUNPATH("0:/arm.ks").
    IF NOT (DEFINED ARM_CYCLE) {
        IF DEFINED LAR_CHAIN_ERR { IF LAR_CHAIN_ERR <> "" { RETURN LAR_CHAIN_ERR:TOUPPER. } }    // An old craft's 7-joint arm, said as it is
        RETURN "NO ARM ON THIS CRAFT".
    }
    SET O2A_ON TO TRUE.
    LOCAL ui IS ARM_UI.
    FOR b IN ui["joints"] { IF b:PRESSED { SET b:PRESSED TO FALSE. } }      // the window starts with the first joint picked: here none is
    SET o2aStWas TO "". SET o2aPorT TO -1. SET o2aRt TO LIST(0, 0).
    ARM_ACT["load"]().                       // the keyed pose = the pose now (OPR CMD never flies to an empty one)
    SET o2aLdWait TO 2.
    SET o2aSnap TO ARM_SNAP().
    RETURN "".
}

FUNCTION o2aClose {                          // the arm stopped: every mode released, the joints locked, the hold off
    PARAMETER why IS "PDRS LEFT".
    IF NOT O2A_ON { RETURN. }
    SET O2A_ON TO FALSE.
    o2aRelease().
    ARM_CYCLE().                             // the loop sees the releases (a mode ends through its own off-routine)
    ARM_END().
    IF DEFINED CW_VER { cwArmStop(o2aCw). }
    o2aSay(why + ": ARM STOPPED", "V").
}

FUNCTION o2aHoldSet {                        // ORBIT / PTG's HOLD changed while the arm is up: arm.ks's hold follows (its loop
    PARAMETER md.                            // takes a newly pressed mode on the attitude now and releases the others)
    IF NOT O2A_ON OR NOT O2A_HOLDS:CONTAINS(md) { RETURN. }
    FOR h IN ARM_UI["hold"] { IF h[0] = md AND NOT h[1]:PRESSED { SET h[1]:PRESSED TO TRUE. } }
}

FUNCTION o2aTick {                           // one pass of arm.ks's loop, the page's data, the POR rate
    IF NOT O2A_ON { RETURN. }
    ARM_CYCLE().
    SET o2aSnap TO ARM_SNAP().
    LOCAL sn IS o2aSnap.
    LOCAL now IS TIME:SECONDS.
    LOCAL p IS sn["por"].
    IF o2aPorT >= 0 AND now > o2aPorT {
        LOCAL dt IS now - o2aPorT.
        LOCAL vl IS (p[0] - o2aPorP[0]):MAG / dt.
        LOCAL w IS (p[1] - o2aPorP[1]):MAG / dt.
        LOCAL k IS MIN(1, dt / O2A_RATE_TAU).
        SET o2aRt TO LIST(o2aRt[0] + (vl - o2aRt[0]) * k, o2aRt[1] + (w - o2aRt[1]) * k).
    }
    SET o2aPorT TO now. SET o2aPorP TO LIST(p[0], p[1]).
    IF o2aLdWait > 0 {                       // LOAD: arm.ks wrote the pose into its fields in its pass; the page's CMD row takes them
        SET o2aLdWait TO o2aLdWait - 1.
        IF o2aLdWait = 0 { o2aPull(). }
    }
    LOCAL st IS sn["st"].                    // arm.ks's status line is the MSG row's news
    IF st <> o2aStWas OR sn["sayN"] <> o2aSayWas {
        SET o2aStWas TO st. SET o2aSayWas TO sn["sayN"].
        IF st <> "" { o2aSay(st, CHOOSE "Y" IF o2aBadTxt(st) ELSE "V"). }
    }
    IF DEFINED CW_VER { cwArmApply(o2aCw, now, st). }    // the ARM lamp from the status text (singular / held / stall)
    IF DEFINED SAIL_ON { IF SAIL_ON { o2aSailStat(). } }    // A SAIL run reads the arm back (no-op otherwise)
}
FUNCTION o2aSailStat {                       // The arm for SAIL (ctl/status.txt k_arm_*), every 2 s: status text, joints' target angles, modes pressed, each arm part's autostrut, the log path
    IF TIME:SECONDS - O2A_SAIL_T < 2 AND TIME:SECONDS >= O2A_SAIL_T { RETURN. }
    SET O2A_SAIL_T TO TIME:SECONDS.
    LOCAL ui IS ARM_UI.
    sailStat("arm_st", o2aSnap["st"]).
    LOCAL md IS "".
    FOR k IN LIST("aug", "opr", "grp", "cap", "rel", "cam", "stick", "rot", "vern") { IF ui[k]:PRESSED { SET md TO md + k + " ". } }
    FOR h IN ui["hold"] { IF h[1]:PRESSED { SET md TO md + "hold:" + h[0] + " ". } }
    FOR b IN ui["auto"] { IF b[0]:PRESSED { SET md TO md + b[1] + ":" + b[2] + " ". } }
    FROM { LOCAL i IS 0. } UNTIL i >= ui["joints"]:LENGTH STEP { SET i TO i + 1. } DO { IF ui["joints"][i]:PRESSED { SET md TO md + "joint:" + ui["jts"][i][2] + " ". } }
    sailStat("arm_modes", md:TRIM).
    sailStat("arm_gl", (ui["gl1"]:TEXT + " | " + ui["gl2"]:TEXT):TRIM).    // The GRAPPLE lines
    sailStat("arm_ext", CHOOSE "EXT" IF ARM_HOLD_EXT ELSE "OWN").        // Who holds the attitude
    LOCAL js IS "".
    FOR j IN ui["jts"] { SET js TO js + j[2] + "=" + ROUND(j[1]:GETFIELD(LAR_F_TARGET), 1) + " ". }
    sailStat("arm_joints", js:TRIM).
    LOCAL asx IS "n/a (" + larAsWhy() + ")".
    IF larAsWhy() = "" {
        SET asx TO "".
        FOR pt IN larArmParts(ui["ee"], ui["jts"]) { SET asx TO asx + pt:NAME + "=" + ADDONS:KALS:ASTRUT(pt, "") + " ". }
    }
    sailStat("arm_as", asx:TRIM).
    IF DEFINED ARM_LOG { sailStat("arm_log", ARM_LOG). }
}
FUNCTION o2aBadTxt {                         // a status that says something stopped or was refused
    PARAMETER s.
    FOR w IN LIST("REFUSED", " OFF", "STALL", "MODEL", "LATCHED", "INHIBITED", "BLOCK", "OUT OF REACH", "NOT ") { IF s:CONTAINS(w) { RETURN TRUE. } }
    RETURN FALSE.
}

FUNCTION o2aPull {                           // the CMD row <- arm.ks's fields (after a LOAD)
    IF NOT O2A_ON { RETURN. }
    LOCAL fd IS ARM_UI["fields"].
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
        LOCAL x IS fd[i]:TEXT:TONUMBER(0).
        SET o2Val[O2A_FLD[i]] TO x.
    }
}

// ---- the widgets as the page's inputs
FUNCTION o2aPress {                          // a toggle button set (TRUE) or released (FALSE), only when it changes
    PARAMETER w, on.
    IF w:PRESSED <> on { SET w:PRESSED TO on. }
}
FUNCTION o2aRelease {                        // every mode and the joint pick released (the arm's loop ends each through its own routine)
    LOCAL ui IS ARM_UI.
    o2aPress(ui["aug"], FALSE). o2aPress(ui["opr"], FALSE).
    o2aPress(ui["grp"], FALSE). o2aPress(ui["cap"], FALSE). o2aPress(ui["rel"], FALSE).
    FOR b IN ui["auto"] { o2aPress(b[0], FALSE). }
    FOR b IN ui["joints"] { o2aPress(b, FALSE). }
}
FUNCTION o2aStop {                           // the pad's STOP: all arm motion released (the hold, the camera and the frame stay)
    IF NOT O2A_ON { o2aSay("ARM NOT UP", "Y"). RETURN. }
    o2aRelease().
    o2aSay("STOP: ALL ARM MOTION RELEASED", "V").
}
FUNCTION o2aCam {                            // the pad's EE CAM: the flight camera on the end effector (arm.ks's own snap), or back
    IF NOT O2A_ON { o2aSay("ARM NOT UP", "Y"). RETURN. }
    LOCAL b IS ARM_UI["cam"].
    SET b:PRESSED TO NOT b:PRESSED.
}
FUNCTION o2aCamOn { RETURN O2A_ON AND ARM_UI["cam"]:PRESSED. }
FUNCTION o2aAutoOn {                        // An AUTO runs, so the arm
    IF NOT O2A_ON { RETURN FALSE. }         // keeps going when the crew leaves the PDRS page (ops2q's o2qGo / loop)
    RETURN o2aSnap["auto"].
}
FUNCTION o2aCamOff {                        // The EE CAM back to the stock view when the page is left under an AUTO
    IF o2aCamOn() { o2aCam(). }
}

FUNCTION o2aSet {                            // a page value changed (ops2q's o2qSetVal): "" or the id when it was not ours
    PARAMETER id.
    IF NOT O2A_ON { RETURN FALSE. }
    LOCAL ui IS ARM_UI.
    IF id = "amode" {
        LOCAL k IS ROUND(o2Val["amode"]).
        IF k = 3 { RETURN TRUE. }
        IF k = 1 AND PX_ORB { o2aSay(pxStickWhy(), "Y"). RETURN TRUE. }     // MAN AUG drives the joints from the stick
        o2aRelease().
        IF k = 1 { SET ui["aug"]:PRESSED TO TRUE. }
        IF k = 2 { SET ui["opr"]:PRESSED TO TRUE. }
        RETURN TRUE.
    }
    LOCAL jk IS O2A_JT:INDEXOF(id).
    IF jk >= 0 { ARM_ACT["slew"](o2Val[id], jk). RETURN TRUE. }   // The typed joint's target: arm.ks slews THAT joint there, picked or not, alongside the others (or says why not)
    IF id = "arate" { SET ui["vern"]:PRESSED TO ROUND(o2Val["arate"]) = 1. RETURN TRUE. }
    IF id = "afrm" { SET ui["frame"]:INDEX TO ROUND(o2Val["afrm"]). RETURN TRUE. }
    LOCAL k IS O2A_FLD:INDEXOF(id).
    IF k >= 0 {                              // a typed CMD value: arm.ks's OPR CMD field (ft / deg, 2 decimals as its LOAD writes)
        SET ui["fields"][k]:TEXT TO "" + ROUND(o2Val[id], 2).
        RETURN TRUE.
    }
    RETURN FALSE.
}

FUNCTION o2aAct {                            // an action word pressed (ENT): TRUE when it was ours
    PARAMETER id.
    IF id:LENGTH < 2 { RETURN FALSE. }
    LOCAL kd IS id:SUBSTRING(0, 2).
    IF kd = "ax" { pxAct(id:SUBSTRING(2, id:LENGTH - 2)). RETURN TRUE. }     // PROX OPS needs no arm
    IF NOT LIST("aj", "ag", "aa", "ap", "at", "ay"):CONTAINS(kd) { RETURN FALSE. }
    IF NOT O2A_ON { o2aSay("ARM NOT UP", "Y"). RETURN TRUE. }
    IF (kd = "aj" OR kd = "ap") AND PX_ORB { o2aSay(pxStickWhy(), "Y"). RETURN TRUE. }   // A joint pick / RHC / THC ROT need the stick
    LOCAL ui IS ARM_UI.
    LOCAL n IS id:SUBSTRING(2, id:LENGTH - 2).
    IF kd = "aj" {                           // a joint pick (SINGLE): pressed again = released
        LOCAL i IS n:TONUMBER(-1).
        IF i < 0 OR i >= ui["joints"]:LENGTH { RETURN TRUE. }
        LOCAL b IS ui["joints"][i].
        IF b:PRESSED { SET b:PRESSED TO FALSE. }
        ELSE {
            o2aPress(ui["aug"], FALSE). o2aPress(ui["opr"], FALSE).
            FOR a IN ui["auto"] { o2aPress(a[0], FALSE). }
            SET b:PRESSED TO TRUE.
        }
        RETURN TRUE.
    }
    IF kd = "ag" {                           // GRAPPLE / CAPTURE / RELEASE: toggles
        IF n = "g" AND NOT O2A_GRAPPLE_OK { RETURN TRUE. }   // GRAPPLE is dim, no flag set
        IF n = "c" AND NOT O2A_CAPTURE_OK { RETURN TRUE. }   // CAPTURE is dim, no flag set
        LOCAL w IS ui[CHOOSE "grp" IF n = "g" ELSE (CHOOSE "cap" IF n = "c" ELSE "rel")].
        SET w:PRESSED TO NOT w:PRESSED.
        RETURN TRUE.
    }
    IF kd = "aa" {                           // an AUTO sequence / a built-in pose: the arm's button n (the one pressed runs; pressed again halts)
        LOCAL i IS n:TONUMBER(-1).
        IF i < 0 OR i >= ui["auto"]:LENGTH { RETURN TRUE. }
        LOCAL b IS ui["auto"][i][0].
        IF NOT b:PRESSED { o2aPress(ui["aug"], FALSE). o2aPress(ui["opr"], FALSE). }
        SET b:PRESSED TO NOT b:PRESSED.
        RETURN TRUE.
    }
    IF kd = "ap" {                           // RHC STICK / THC ROT: toggles
        LOCAL w IS ui[CHOOSE "stick" IF n = "s" ELSE "rot"].
        SET w:PRESSED TO NOT w:PRESSED.
        RETURN TRUE.
    }
    IF kd = "ay" {                           // The MPM roll's three positions (STOW 12 / DEPLOY 30 / CENTER 0; S / D / C); refused with a reason
        LOCAL mg IS CHOOSE LAR_MPM_STOW IF n = "S" ELSE (CHOOSE LAR_MPM_DEPLOY IF n = "D" ELSE LAR_MPM_CENTER).
        LOCAL mn IS CHOOSE "STOW" IF n = "S" ELSE (CHOOSE "DEPLOY" IF n = "D" ELSE "CENTER").
        LOCAL sn IS o2aSnap.
        LOCAL idle IS NOT (sn["drv"] OR sn["aug"] OR sn["opr"] OR sn["auto"] OR sn["grp"] <> "" OR sn["gt"][0]).
        LOCAL why IS larMpmWhy(mg, idle, ui["jts"]).
        IF why <> "" { o2aSay("MPM " + mn + " REFUSED: " + why, "Y"). }
        ELSE { larMpmGo(mg). o2aSay("MPM " + mn + " (" + mg + " DEG)", "V"). }
        RETURN TRUE.
    }
    IF kd = "at" { o2aSay((CHOOSE "GRAPPLE: NOT AVAILABLE YET" IF n = "GRAPPLE" ELSE (CHOOSE "CAPTURE: NOT AVAILABLE YET" IF n = "CAPTURE" ELSE "NOT MODELLED: " + n)), "Y"). RETURN TRUE. }   // the dim items the arm does not have yet (GRAPPLE, CAPTURE until their flags exist)
    RETURN TRUE.
}

// ---- the page
FUNCTION o2aSgN {                            // x with a sign, d decimals, right-aligned in w
    PARAMETER x, w, d.
    LOCAL rd IS ROUND(ABS(x), d).
    RETURN ((CHOOSE "-" IF x < 0 AND rd > 0 ELSE "+") + o2Fx(rd, d)):PADLEFT(w).
}
FUNCTION o2aTog {                            // a toggle word: lit (the brightest) while pressed
    PARAMETER pg, id, row, col, txt, on, pressed.
    o2Seg(pg, row, col, txt, CHOOSE "S" IF pressed ELSE (CHOOSE "L" IF on ELSE "D")).
    o2Fld(pg, id, "A", row, col, txt, on).
}
FUNCTION o2aNot {                            // an item the arm does not have: dim, ENT says so
    PARAMETER pg, id, row, col, txt.
    o2Seg(pg, row, col, txt, "D").
    o2Fld(pg, id, "A", row, col, txt, TRUE).
}

FUNCTION o2aPg {                             // the PDRS rows into pg; the arm not up: its why on the MSG row
    PARAMETER pg.
    o2Seg(pg, 1, 1, "MODE"). o2Seg(pg, 2, 1, "FRAME"). o2Seg(pg, 3, 1, "PL"). o2Seg(pg, 5, 1, "POR").
    o2Seg(pg, 15, 1, "MPM"). o2Seg(pg, 16, 1, "EE"). o2Seg(pg, 17, 1, "AUTO").            // No HOLD label; ROT / RHC / THC on row 18 stay
    pxPg(pg).                                // PROX OPS, rows 13 / 14 (live with or without the arm)
    IF NOT O2A_ON {
        o2Seg(pg, 2, 8, "THE ARM IS NOT UP", "Y").
        RETURN.
    }
    LOCAL sn IS o2aSnap.
    LOCAL ui IS ARM_UI.
    LOCAL md IS O2A_MODES:INDEXOF(sn["mode"]).
    SET o2Val["amode"] TO md.
    o2Choice(pg, "amode", 1, LIST(LIST(8, "SINGLE"), LIST(16, "MAN AUG"), LIST(25, "OPR CMD"), LIST(34, "AUTO")), TRUE,
        CHOOSE LIST(3) IF md <> 3 ELSE LIST(), LIST("", "", "", "")).
    o2Seg(pg, 1, 43, "RATE").
    SET o2Val["arate"] TO CHOOSE 1 IF ui["vern"]:PRESSED ELSE 0.
    o2Choice(pg, "arate", 1, LIST(LIST(49, "COARSE"), LIST(57, "VERN")), TRUE, LIST()).
    SET o2Val["afrm"] TO sn["frm"].
    o2Choice(pg, "afrm", 2, LIST(LIST(8, "ORB UNL"), LIST(17, "END EFF"), LIST(26, "ORB LD"), LIST(34, "PL")), TRUE,
        CHOOSE LIST() IF sn["ld"] ELSE LIST(2, 3), LIST("", "", "ORB LD: NO PAYLOAD (LOADED ONLY)", "PL: NO PAYLOAD (LOADED ONLY)")).
    o2Seg(pg, 2, 43, "LOAD").
    o2Seg(pg, 2, 49, "UNL", CHOOSE "L" IF sn["ld"] ELSE "S"). o2Seg(pg, 2, 54, "LD", CHOOSE "S" IF sn["ld"] ELSE "L").
    o2Seg(pg, 3, 8, (CHOOSE (CHOOSE "LATCHED " IF sn["latched"] ELSE "") + sn["ldN"] + " PARTS" IF sn["ld"] ELSE "NONE"), CHOOSE "V" IF sn["ld"] ELSE "D").
    o2Seg(pg, 3, 44, "MASS"). o2Read(pg, 3, 49, o2F(sn["ldM"] * 1000, 7, 0)). o2Seg(pg, 3, 57, "kg").
    // the POR: the node, or the payload's point of resolution when loaded (arm.ks's POSE line), CUR live, CMD typed
    o2Seg(pg, 5, 8, "X m"). o2Seg(pg, 5, 17, "Y m"). o2Seg(pg, 5, 26, "Z m"). o2Seg(pg, 5, 35, "P deg"). o2Seg(pg, 5, 44, "Y deg"). o2Seg(pg, 5, 53, "R deg").
    o2Seg(pg, 6, 2, "CUR"). o2Seg(pg, 7, 2, "CMD"). o2Seg(pg, 8, 2, "RATE").
    LOCAL ends IS LIST(12, 20, 28, 37, 46, 55).
    LOCAL por IS sn["por"].
    LOCAL cur IS LIST(por[0]:X, por[0]:Y, por[0]:Z, por[1]:X, por[1]:Y, por[1]:Z).
    LOCAL opr IS sn["mode"] = "OPR CMD".
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
        o2Read(pg, 6, ends[i] - 5, o2aSgN(cur[i], 6, CHOOSE 2 IF i < 3 ELSE 1)).
        LOCAL tx IS o2aSgN(o2Val[O2A_FLD[i]], 6, CHOOSE 2 IF i < 3 ELSE 1).
        o2Seg(pg, 7, ends[i] - 5, tx, CHOOSE "V" IF opr ELSE "D").
        o2Fld(pg, O2A_FLD[i], "N", 7, ends[i] - 5, tx, TRUE).
    }
    o2Read(pg, 8, 9, o2F(o2aRt[0], 4, 2)). o2Seg(pg, 8, 14, "m/s"). o2Read(pg, 8, 29, o2F(o2aRt[1], 4, 2)). o2Seg(pg, 8, 34, "deg/s").
    // the joints: two columns from the shoulder out; POS = the drive's position, CMD = the target angle, RATE deg/s
    o2Seg(pg, 9, 1, "JOINT"). o2Seg(pg, 9, 10, "POS"). o2Seg(pg, 9, 18, "CMD"). o2Seg(pg, 9, 24, "RATE").
    o2Seg(pg, 9, 34, "JOINT"). o2Seg(pg, 9, 43, "POS"). o2Seg(pg, 9, 51, "CMD"). o2Seg(pg, 9, 57, "RATE").
    LOCAL nj IS ui["jts"]:LENGTH.
    LOCAL nm IS CHOOSE O2A_JN6 IF nj = 6 ELSE LIST().   // The real SRMS's 6 joints (the KerboArm's upper arm roll is gone)
    LOCAL half IS CEILING(nj / 2).
    FROM { LOCAL i IS 0. } UNTIL i >= nj STEP { SET i TO i + 1. } DO {
        LOCAL right IS i >= half.
        LOCAL row IS 10 + (CHOOSE i - half IF right ELSE i).
        LOCAL c0 IS CHOOSE 36 IF right ELSE 2.
        LOCAL pe IS CHOOSE 46 IF right ELSE 12.
        LOCAL ce IS CHOOSE 54 IF right ELSE 20.
        LOCAL re IS CHOOSE 61 IF right ELSE 27.
        LOCAL jn IS CHOOSE nm[i] IF nm:LENGTH > i ELSE "J" + (i + 1).
        o2aTog(pg, "aj" + i, row, c0, jn, TRUE, sn["sel"] = i).
        LOCAL rate IS sn["rt"][i].
        o2Read(pg, row, pe - 5, o2aSgN(sn["th"][i], 6, 1)).
        // Every joint's CMD is typeable (the field under the cursor, picked or not: TYPE + ENT slews THAT joint there); a slew on this joint shows its typed target, else the joint's command
        LOCAL slw IS sn["gts"][i] < 1E8.      // This joint's slew runs: its typed target is shown, in the Y colour
        IF slw { SET o2Val[O2A_JT[i]] TO sn["gts"][i]. } ELSE { SET o2Val[O2A_JT[i]] TO sn["tg"][i]. }
        LOCAL jtx IS o2aSgN(o2Val[O2A_JT[i]], 6, 1).
        IF slw { o2Seg(pg, row, ce - 5, jtx, "Y"). } ELSE IF sn["sel"] = i { o2Seg(pg, row, ce - 5, jtx, "V"). } ELSE { o2Read(pg, row, ce - 5, jtx). }
        o2Fld(pg, O2A_JT[i], "N", row, ce - 5, jtx, TRUE, TRUE).     // The arrows never stop on a CMD cell (TYPE on its joint's toggle only)
        o2Read(pg, row, re - 3, o2F(ABS(rate), 4, 2), CHOOSE "Y" IF ABS(rate) > 3 ELSE "V").
    }
    // arm.ks's GRAPPLE page lines, the same texts as its own window (<= 72 chars):
    // gl1 = LOADED / LATCHED or FIXTURE RNG CLOSING OFF AXIS, gl2 = RT UP P Y R (or NO FIXTURE WITHIN 98 FT); empty = nothing drawn (GRAPPLE off)
    LOCAL g1 IS ui["gl1"]:TEXT. LOCAL g2 IS ui["gl2"]:TEXT.
    IF g1 <> "" { o2Read(pg, 4, 1, g1:SUBSTRING(0, MIN(g1:LENGTH, 72))). }
    // row 14 is pxPg's readout (TGT / RNG / RDOT / ERR, or OLDER DLL) whenever PROX OPS has
    // its row; the RT / UP line takes row 14 only when pxPg left it empty (PX_ON off and the DLL present). No free row for it otherwise (rows 4 / 6-8 / 10-12 / 15-18 are used).
    IF g2 <> "" AND NOT PX_ON AND PX_API["has"]() { o2Read(pg, 14, 1, g2:SUBSTRING(0, MIN(g2:LENGTH, 72))). }
    // MPM: STOW 12 / DEPLOY 30 / CENTER 0, live on a craft with the MPM roll servo (the mode word at the right); dim, ENT says so when the craft has no MPM roll servo
    IF larMpmHas() {
        LOCAL mpd IS larMpmMode().
        o2aTog(pg, "ayS", 15, 5, "STOW", TRUE, mpd = "STOWED"). o2aTog(pg, "ayD", 15, 10, "DEPLOY", TRUE, mpd = "DEPLOYED"). o2aTog(pg, "ayC", 15, 17, "CENTER", TRUE, mpd = "CENTER").
        o2Read(pg, 15, 25, mpd, CHOOSE "Y" IF mpd = "MOVING" OR mpd = "BETWEEN" ELSE "V").
    } ELSE {
        o2aNot(pg, "atMPM STOW", 15, 5, "STOW"). o2aNot(pg, "atMPM DEPLOY", 15, 10, "DEPLOY"). o2aNot(pg, "atMPM CENTER", 15, 17, "CENTER").
    }
    IF O2A_GRAPPLE_OK { o2aTog(pg, "agg", 16, 5, "GRAPPLE", TRUE, ui["grp"]:PRESSED OR sn["grp"] <> ""). }
    ELSE { o2aNot(pg, "atGRAPPLE", 16, 5, "GRAPPLE"). }    // dim, ENT says so; arm.ks never sees the GRAPPLE flag
    IF O2A_CAPTURE_OK { o2aTog(pg, "agc", 16, 13, "CAPTURE", TRUE, sn["grp"] = "CAP"). }
    ELSE { o2aNot(pg, "atCAPTURE", 16, 13, "CAPTURE"). }    // dim, ENT says so; arm.ks never sees the CAP flag
    o2aTog(pg, "agr", 16, 21, "RELEASE", TRUE, sn["grp"] = "REL").
    // AUTO 1-4 and the built-in poses: arm.ks's buttons (LAR_BUILT_IN first, then AUTO 1-4), their labels as its autoLabels writes them
    LOCAL ab IS ui["auto"].
    LOCAL ac IS LIST(8, 18, 26, 34).
    LOCAL pc IS LIST(44, 50, 58).
    LOCAL pn IS LIST("STOW", "PRE-CR", "READY").
    FROM { LOCAL i IS 0. } UNTIL i >= ab:LENGTH STEP { SET i TO i + 1. } DO {
        IF ab[i][1] = "POSE" AND i < 3 { o2aTog(pg, "aa" + i, 17, pc[i], pn[i], TRUE, ab[i][0]:PRESSED). }
        ELSE IF ab[i][1] = "AUTO" {
            LOCAL k IS ab[i][2]:SUBSTRING(5, 1):TONUMBER(1) - 1.
            LOCAL lb IS ab[i][0]:TEXT:REPLACE("AUTO ", ""):REPLACE("(0)", "----").
            IF k >= 0 AND k < 4 { o2aTog(pg, "aa" + i, 17, ac[k], lb, TRUE, ab[i][0]:PRESSED). }
        }
    }
    // No HOLD row: the orbiter's hold is ORBIT / PTG's HOLD (ops2q's DAP keeps it, ARM_HOLD_EXT; without the C# DAP
    // arm.ks's own hold follows it: o2aOpen's md, o2aHoldSet). ROT: RHC = the stick turns the end effector, THC = THC ROT (the real names)
    o2Seg(pg, 18, 8, "ROT").
    o2aTog(pg, "aps", 18, 13, "RHC", TRUE, ui["stick"]:PRESSED).
    o2aTog(pg, "apr", 18, 18, "THC", TRUE, ui["rot"]:PRESSED).
}

// ----PROX OPS (the STKP target station-keeping + CSS, the DLL's coproc/StationKeep.cs + KalsAddon.Prox.cs) on the PDRS page, rows 13 / 14.
// PROX OPS [OFF] [STKP] [CSS]   TRANS [NORM] [PULSE]   STICK [ARM] [ORB]   /   TGT name  RNG m  RDOT m/s  ERR m  (+ the DLL's messages on the MSG rows)
// OFF = the DAP as today. STKP = null the relative velocity to the TARGET (a vessel or a docking port), then hold the point in the target's frame; the
// DLL's ops2q DAP frame becomes the target's (O2DAPSET's rf is forced). CSS = STKP with the stick moving the hold point (THC: NORM 0.05 m/s, PULSE 0.25 m
// per tap); it needs STICK ORB (the THC is PROX OPS's, not the arm's): CSS with STICK ARM flips STICK to ORB with a MSG. STICK ORB: the arm sees no THC
// (ARM_THC_OFF, arm_body.ks armThc), its RHC / THC ROT toggles are released, and an arm mode that needs the stick says STICK ON ORB. ROT (RHC) is the
// DAP's own CSS (the ORBIT / PTG rates), nothing here. PX_API = the DLL's three calls (has / set / cyc): the self-test swaps them.
// Real Shuttle: the real orbiter had no automatic translation station-keeping; STKP is a KAL/S aid (KFSD).
GLOBAL PX_ON IS FALSE.                       // PROXSET accepted and the DLL has not let go
GLOBAL PX_CSS IS FALSE.                      // the CSS word lit (the stick moves the hold point)
GLOBAL PX_TRANS IS 0.                        // CSS's translation mode: 0 NORM, 1 PULSE
GLOBAL PX_ORB IS FALSE.                      // STICK ORB: the THC / RHC are PROX OPS's, the arm's off
GLOBAL ARM_THC_OFF IS FALSE.                 // arm_body.ks armThc: TRUE = the arm sees no THC (STICK ORB)
GLOBAL PX_T IS -1E9.                         // TIME:SECONDS of the last PROXCYC (pxTick keeps the DLL's watchdog, 100 ticks, alive)
GLOBAL PX_DT IS 0.25.                        // s between PROXCYCs
GLOBAL pxSn IS LEXICON("on", FALSE, "phase", 0, "name", "", "rng", 0, "rate", 0, "ep", 0, "ev", 0, "fire", FALSE, "inrtl", FALSE, "valid", FALSE, "css", 0).
FUNCTION pxApiHas { RETURN ADDONS:HASSUFFIX("KALS") AND ADDONS:KALS:HASSUFFIX("PROXSET") AND ADDONS:KALS:HASSUFFIX("PROXCYC"). }
FUNCTION pxApiSet { PARAMETER m. RETURN ADDONS:KALS:PROXSET(m). }
FUNCTION pxApiCyc { RETURN ADDONS:KALS:PROXCYC. }
// PROXSTICK(orb) tells the DLL who has the RHC, pushed on EVERY change (not read
// off a kOS cycle): while STKP is on the DLL gives the ops2q DAP no stick unless STICK ORB (KalsAddon.Prox.cs PxStickForDap, every physics frame).
FUNCTION pxApiHasStk { RETURN ADDONS:HASSUFFIX("KALS") AND ADDONS:KALS:HASSUFFIX("PROXSTICK"). }
FUNCTION pxApiStk { PARAMETER b. RETURN ADDONS:KALS:PROXSTICK(b). }
GLOBAL PX_API IS LEXICON("has", pxApiHas@, "set", pxApiSet@, "cyc", pxApiCyc@, "hasstk", pxApiHasStk@, "stk", pxApiStk@).
FUNCTION pxStickPush {                       // the DLL knows STICK ARM / ORB now (an older DLL: nothing to tell)
    IF PX_API["hasstk"]() { PX_API["stk"](PX_ORB). }
}

FUNCTION pxMode {                            // the DLL's mode now: 1 STKP, 2 CSS NORM, 3 CSS PULSE
    IF NOT PX_CSS { RETURN 1. }
    RETURN CHOOSE 2 IF PX_TRANS = 0 ELSE 3.
}
FUNCTION pxStickOrb {                        // STICK ARM / ORB: the THC the arm sees, the arm's own RHC / THC ROT toggles
    PARAMETER orb.
    SET PX_ORB TO orb.
    pxStickPush().
    SET ARM_THC_OFF TO orb.
    IF orb AND O2A_ON {
        IF DEFINED ARM_UI { o2aPress(ARM_UI["stick"], FALSE). o2aPress(ARM_UI["rot"], FALSE). }
    }
}
FUNCTION pxOff {                             // PROX OPS off (OFF, a burn, ops2q ends): the DLL lets go, the hold point is gone
    PARAMETER why IS "".
    IF PX_ON AND PX_API["has"]() { PX_API["set"](0). }
    LOCAL was IS PX_ON.
    SET PX_ON TO FALSE. SET PX_CSS TO FALSE.
    IF was AND why <> "" { o2aSay("PROX OPS OFF: " + why, "V"). }
}
FUNCTION pxStkp {                            // STKP (or CSS with css TRUE): engage, or just the stick mode when it is on
    PARAMETER css IS FALSE.
    IF NOT PX_API["has"]() { o2aSay("PROX OPS: OLDER DLL (NO PROXSET)", "Y"). RETURN. }
    IF css AND NOT PX_ORB {
        pxStickOrb(TRUE).
    }
    SET PX_CSS TO css.
    pxStickPush().                           // before the engage: the DLL's gate is right from its first frame
    LOCAL rs IS PX_API["set"](pxMode()).
    IF rs <> "" {
        SET PX_CSS TO FALSE.
        IF NOT PX_ON { o2aSay("PROX OPS: " + (CHOOSE rs:SUBSTRING(6, rs:LENGTH - 6):TOUPPER IF rs:STARTSWITH("error ") ELSE rs:TOUPPER), "Y"). }
        RETURN.
    }
    IF NOT PX_ON { SET PX_ON TO TRUE. SET PX_T TO -1E9. o2aSay("STKP ON", "V"). }
}
FUNCTION pxTrans {                           // TRANS NORM / PULSE (CSS's translation mode), live when CSS is on
    PARAMETER m.
    SET PX_TRANS TO m.
    IF PX_ON AND PX_CSS { PX_API["set"](pxMode()). }
}
FUNCTION pxTick {                            // the DLL's keep-alive + state, every PX_DT s while PROX OPS is on (ops2q's loop)
    IF NOT PX_ON { RETURN. }
    IF TIME:SECONDS - PX_T < PX_DT AND TIME:SECONDS >= PX_T { RETURN. }
    SET PX_T TO TIME:SECONDS.
    LOCAL l IS PX_API["cyc"]().
    IF l:LENGTH < 14 { SET PX_ON TO FALSE. SET PX_CSS TO FALSE. o2aSay("PROX OPS: OLDER DLL (PROXCYC)", "Y"). RETURN. }
    SET pxSn["on"] TO l[0]. SET pxSn["phase"] TO l[1]. SET pxSn["name"] TO l[3]. SET pxSn["rng"] TO l[4]. SET pxSn["rate"] TO l[5].
    SET pxSn["ep"] TO l[6]. SET pxSn["ev"] TO l[7]. SET pxSn["fire"] TO l[8]. SET pxSn["inrtl"] TO l[12]. SET pxSn["valid"] TO l[13].
    IF l:LENGTH > 14 { SET pxSn["css"] TO l[14]. }
    IF l[2] <> "" { o2aSay(l[2], CHOOSE "Y" IF (l[2]:CONTAINS("LOST") OR l[2]:CONTAINS("OUT OF") OR l[2]:CONTAINS("TOO") OR l[2]:CONTAINS("HIGH")) ELSE "V"). }
    IF NOT l[0] {                            // the DLL let go (target lost, FBWOFF, the watchdog)
        SET PX_ON TO FALSE. SET PX_CSS TO FALSE.
        o2aSay("PROX OPS OFF", "Y").
    }
}
FUNCTION pxAct {                             // an "ax" item pressed (ENT): the word after the prefix
    PARAMETER n.
    IF n = "O" { IF PX_ON { pxOff("OFF"). } RETURN. }
    IF n = "S" { pxStkp(FALSE). RETURN. }
    IF n = "C" { pxStkp(TRUE). RETURN. }
    IF n = "N" { pxTrans(0). RETURN. }
    IF n = "P" { pxTrans(1). RETURN. }
    IF n = "A" {
        pxStickOrb(FALSE).
        IF PX_ON AND PX_CSS { SET PX_CSS TO FALSE. PX_API["set"](1). }
        RETURN.
    }
    IF n = "R" { pxStickOrb(TRUE). RETURN. }
}
FUNCTION pxStickWhy {                        // an arm item that needs the stick with STICK ORB: "" or the MSG
    IF PX_ORB { RETURN "STICK ON ORB: SET STICK ARM FIRST". }
    RETURN "".
}
FUNCTION pxPg {                              // the PROX OPS rows into pg (13: the controls, 14: the readout)
    PARAMETER pg.
    LOCAL has IS PX_API["has"]().
    o2Seg(pg, 13, 1, "PROX OPS").
    o2aTog(pg, "axO", 13, 10, "OFF", has, NOT PX_ON).
    o2aTog(pg, "axS", 13, 14, "STKP", has, PX_ON AND NOT PX_CSS).
    o2aTog(pg, "axC", 13, 19, "CSS", has, PX_ON AND PX_CSS).
    o2Seg(pg, 13, 24, "TRANS").
    o2aTog(pg, "axN", 13, 30, "NORM", has, PX_TRANS = 0).
    o2aTog(pg, "axP", 13, 35, "PULSE", has, PX_TRANS = 1).
    o2Seg(pg, 13, 44, "STICK").
    o2aTog(pg, "axA", 13, 50, "ARM", TRUE, NOT PX_ORB).
    o2aTog(pg, "axR", 13, 54, "ORB", TRUE, PX_ORB).
    IF NOT has { o2Seg(pg, 14, 1, "OLDER DLL: NO PROX OPS", "D"). RETURN. }
    IF NOT PX_ON { RETURN. }
    LOCAL nm IS pxSn["name"]:TOUPPER.
    o2Seg(pg, 14, 1, "TGT"). o2Read(pg, 14, 5, nm:SUBSTRING(0, MIN(nm:LENGTH, 16))).
    o2Seg(pg, 14, 22, "RNG"). o2Read(pg, 14, 26, o2F(pxSn["rng"], 6, 1)). o2Seg(pg, 14, 33, "M").
    o2Seg(pg, 14, 37, "RDOT"). o2Read(pg, 14, 42, o2F(pxSn["rate"], 5, 2)). o2Seg(pg, 14, 48, "M/S").
    o2Seg(pg, 14, 53, "ERR"). o2Read(pg, 14, 57, o2F(pxSn["ep"], 5, 1)). o2Seg(pg, 14, 63, "M").
    IF pxSn["inrtl"] { o2Seg(pg, 14, 67, "INRTL", "Y"). }
    ELSE IF pxSn["fire"] { o2Seg(pg, 14, 67, "FIRE", "V"). }
}
