@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_GPC.KS  --  the GPC FAILURES: DPS 01 GPC HARDWARE FAIL / DPS 02 GPC TRANSIENT FAIL and what the crew does about them.
//  Two more ways a PASS GPC (G1..G4) leaves the redundant set: DPS 03 GPC FAIL TO SYNC (the others vote it out; its displays FREEZE (no big X) until the
//  crew HALTs it and RE-ASSIGNs them; a transient one RESTARTs, a permanent one only has its displays moved) and DPS 06 GPC OUTPUT BAD (a 1-3 s spell of wrong
//  commands = a felt control bias on one axis (the DLL's GPCKICK, coproc/GpcKick.cs), then the same out-of-set GPC, transient: RESTART). An out-of-set GPC counts
//  as failed everywhere below (gpcIdx), so the strips, keys, floors and restarts are the old ones.
//  Also the PASS SET as a whole (ascent / entry only: OPS 2 flies 2 GNC + 1 SM GPCs, no 4-GPC set, and refuses both): DPS 04 REDUNDANT SET SPLIT (the four PASS GPCs split 2-2:
//  the guidance HOLDS (lib_flfx: the SW 02 hold on every phase the host flies, the DAP goes CSS after DAP_GD_LOST_S) until the crew picks the right pair (PAIR 1-2 / PAIR 3-4: the good
//  pair is drawn and HIDDEN; the wrong pair re-votes GPC_PAIR_WRONG_S s, then the other is the answer) or engages the BFS) and DPS 05 PASS GENERIC FAIL (all four PASS GPCs at once: AUTO and the
//  guidance lost, the PASS displays dead until BFS ENGAGE). THE BFS (G5) FLIES THE REST WITH LESS: the guidance and AUTO come back, but ONE display window only (TOP / GNC moves to G5, the other
//  stays dead: the big X), until the PASS set is loaded again (the OPS 2 start). The automated test flight's crew (no pilot) picks the good pair after GPC_NP_PAIR_S s and presses BFS ENGAGE after GPC_NP_BFS_S s.
//  The real thing: a display (CRT = IDP = MEDS MDU) is driven by exactly
//  ONE GPC; when that GPC dies its display stops updating (the IDP's own clock keeps running), after 3 s with no data the IDP draws the
//  BIG X over the page (+ POLL FAIL); the vehicle flies on (ascent / entry run 4 PASS GPCs + the BFS; on orbit 2 GNC GPCs + 1 SM GPC);
//  a GPC failure is a class 2 alarm (the GPC lamp); the crew gets the display back with GPC/CRT X/Y EXEC (RE-ASSIGN), and the GPC itself
//  back with a re-IPL (RESTART a TRANSIENT one: MODE STBY, HALT 5 s, IPL + load 60 s, hands off 10 s; ascent only after MECO), by moving
//  its job to the freeze-dried GPC on orbit (LOAD JOB), or by swapping in the spare (SWAP SPARE, once per flight, orbit, a hardware fail).
//  THE STATE IS lib_fail.ks's: a failed GPC = an ACTIVE entry (code DPS 01 / DPS 02, target G1..G5, met = the UT it failed); this file
//  keeps only what the vessel's crew has done since (the displays' re-assignments, the jobs moved, the spare, the tasks under way: the
//  tasks / jobs / spare persist in 1:/gpc_state.txt across the programs; the re-assignments do NOT: an OPS transition recalls the NBAT).
//  THE DISPLAYS (a DESIGN CHOICE, flagged: no source says which GPC owns which CRT; keep this table to one line to change):
//    OPS1 / OPS3 (4 PASS GPCs): the deck's TOP window (ASCENT TRAJ / ENTRY TRAJ / VERT SIT) = G1, its BOTTOM window (OMS/MPS / the entry page /
//        HORIZ SIT) = G2; G3 and G4 drive no display (PASS drives 3 buses) and G5 (the BFS) none of ours: their failure is a lamp + a row only.
//    OPS2: the GNC pages (MNVR EXEC, DEORB, ORBIT / PTG, ATO / AOA, BRN PLN, FPLN) = G1 (G2 is the second GNC GPC); the SM pages
//        (OMS/RCS, PDRS CONTROL) = G4; G3 is freeze-dried (a LOAD JOB makes it the failed GPC's replacement), G5 halted.
//  THE WINDOWS' LOOK: each display registers gpcWin(name, apply) with apply(dead) -> the X look on (TRUE) / off (FALSE); the draw code asks
//  gpcLive(name) at its entry and draws nothing while the display is frozen / dead. lib_gpc holds NO GUI code.
//  THE KEYS (lib_failui.ks, fixed legends): per failed GPC RE-ASSIGN | LOAD JOB | SWAP SPARE | RESTART; the key a failure does not allow
//  is dark (gpcCan). Every action returns "OK" or "REFUSE: text".
//  The host: flInit() then gpcInit(prog, canRestart) (it registers DPS 01 / 02 in lib_fail), the windows' gpcWin, gpcTick() each loop
//  (lib_failui's fuiTick calls it), gpcClose() at its end. Needs lib_fail.ks. Names gpc* / GPC_*.
// ============================================================================
RUNONCEPATH("0:/lib/lib_fail.ks").

GLOBAL GPC_POLL_S IS 3.                      // s from the failure to the big X (the IDP's 3 s without data)
GLOBAL GPC_ASG_S IS 1.                       // RE-ASSIGN (GPC/CRT X/Y EXEC): the new commander takes over in about 0.16 s; we show 1 s
GLOBAL GPC_JOB_S IS 30.                      // LOAD JOB (design number)
GLOBAL GPC_SPARE_S IS 3600.                  // SWAP SPARE: a 60-minute task (design number)
GLOBAL GPC_HANDS_S IS 10.                    // hands off this long before the restarted GPC goes to RUN
GLOBAL GPC_HALT_S IS 5.                      // HALT of an out-of-sync GPC before its displays can be re-assigned (design number)
GLOBAL GPC_KICKS IS 0.                       // DPS 06 spells started (a test reads it)
GLOBAL GPC_PAIR_WRONG_S IS 15.               // s the PAIR keys stay dark after the crew picked the wrong pair (the pairs re-vote)
GLOBAL GPC_NP_PAIR_S IS 10.                  // The automated test flight's crew (no pilot) picks the good pair this long after the split
GLOBAL GPC_NP_BFS_S IS 5.                    // ... and presses BFS ENGAGE this long after the PASS generic fail
GLOBAL GPC_FILE IS "1:/gpc_state.txt".

IF NOT (DEFINED GPC_PROG) {
    GLOBAL GPC_PROG IS "".                   // "OPS1" / "OPS2" / "OPS3" ("" = gpcInit not called: every display is live)
    GLOBAL GPC_MAP IS LEXICON().             // display -> its default GPC
    GLOBAL GPC_ASG IS LEXICON().             // display -> the GPC it was RE-ASSIGNED to (overrides the map)
    GLOBAL GPC_PEND IS LEXICON().            // display -> LEXICON(g, at): a RE-ASSIGN under way
    GLOBAL GPC_JOBS IS LIST().               // the failed GPC numbers whose job G3 carries (LOAD JOB done)
    GLOBAL GPC_TASKS IS LIST().              // LEXICON(kind "JOB" / "SPARE", g, at (UT)): under way
    GLOBAL GPC_SPARE IS FALSE.               // the spare is spoken for
    GLOBAL GPC_WIN IS LEXICON().             // display -> LEXICON(ap = delegate(dead), st = the state last applied)
    GLOBAL GPC_CANRS IS 0.                   // delegate() -> "" or the refusal text (RESTART), the host's
    GLOBAL GPC_SIG IS "".                    // the state as last saved
    GLOBAL GPC_BFS IS FALSE.                 // The BFS (G5) flies (BFS ENGAGE after DPS 04 / DPS 05): the PASS displays are dead but one
    GLOBAL GPC_BFSAT IS 0.                   // UT the BFS was engaged
    GLOBAL GPC_BFSD IS "".                   // The display the BFS drives ("TOP" / "BOT"; "" = not engaged): the crew moves it (gpcBfsMove), saved with the BFS line
    GLOBAL GPC_PAIR IS 0.                   // DPS 04: the GOOD pair (1 = G1+G2, 2 = G3+G4), drawn at the split, hidden; 0 = none drawn
    GLOBAL GPC_PWRONG IS 0.                  // the pair the crew picked wrong (0 = none)
    GLOBAL GPC_PLOCK IS 0.                   // UT the pair keys light again after a wrong pick
    GLOBAL GPC_PAIROK IS FALSE.              // TRUE while gpcPair / the OPS 2 re-IPL calls flFix (the guard lets exactly that through)
    GLOBAL GPC_NOPILOT IS -1.                // -1 = ask the DLL (SAILON); 0 / 1 = forced (the offline tests)
}

// ---- who has failed (lib_fail's ACTIVE list is the truth)
FUNCTION gpcNum {                            // "G2" -> 2 (0 for anything else)
    PARAMETER tg.
    IF tg:LENGTH = 2 AND tg:STARTSWITH("G") { RETURN tg:SUBSTRING(1, 1):TONUMBER(0). }
    RETURN 0.
}
FUNCTION gpcIsCode {                         // The four GPC failure codes
    PARAMETER c.
    RETURN c = "DPS 01" OR c = "DPS 02" OR c = "DPS 03" OR c = "DPS 06".
}
FUNCTION gpcIdx {                            // the ACTIVE index of failed GPC k (DPS 01 / 02 / 03 / 06), -1 = it is good
    PARAMETER k.
    LOCAL i IS 0.
    FOR e IN FL_ACTIVE:COPY {
        IF gpcIsCode(e["code"]) AND e["tg"] = "G" + k { RETURN i. }
        SET i TO i + 1.
    }
    RETURN -1.
}
FUNCTION gpcEnt {                            // the ACTIVE entry (the LEXICON) of failed GPC k, LEXICON() = it is good (read the entry, not an index a REMOVE can leave stale)
    PARAMETER k.
    FOR e IN FL_ACTIVE:COPY {
        IF gpcIsCode(e["code"]) AND e["tg"] = "G" + k { RETURN e. }
    }
    RETURN LEXICON().
}
FUNCTION gpcFailed { PARAMETER k. RETURN gpcIdx(k) >= 0. }
FUNCTION gpcKind {                           // "HW" (DPS 01: the spare) / "TR" (a transient one: RESTART) / "PM" (DPS 03 permanent: displays moved, no restart, no spare) / "" (good)
    PARAMETER k.
    LOCAL e IS gpcEnt(k).
    IF e:LENGTH = 0 { RETURN "". }
    IF e["code"] = "DPS 01" { RETURN "HW". }
    IF e["mode"] = "P" { RETURN "PM". }
    RETURN "TR".
}
FUNCTION gpcSyncOut {                        // TRUE when GPC k is out of the set by DPS 03 / DPS 06 (its displays FREEZE, never the big X)
    PARAMETER k.
    LOCAL e IS gpcEnt(k).
    IF e:LENGTH = 0 { RETURN FALSE. }
    RETURN e["code"] = "DPS 03" OR e["code"] = "DPS 06".
}
FUNCTION gpcFailedList {                     // the failed GPC numbers, in order
    LOCAL out IS LIST().
    FROM { LOCAL k IS 1. } UNTIL k > 5 STEP { SET k TO k + 1. } DO { IF gpcFailed(k) { out:ADD(k). } }
    RETURN out.
}
FUNCTION gpcPassLive {                       // how many of the four PASS GPCs (G1..G4) are good
    LOCAL n IS 0.
    FROM { LOCAL k IS 1. } UNTIL k > 4 STEP { SET k TO k + 1. } DO { IF NOT gpcFailed(k) { SET n TO n + 1. } }
    RETURN n.
}

// ---- the displays
FUNCTION gpcOwner {                          // the GPC driving display d now (0 = none of ours)
    PARAMETER d.
    IF GPC_ASG:HASKEY(d) { RETURN GPC_ASG[d]. }
    IF GPC_MAP:HASKEY(d) { RETURN GPC_MAP[d]. }
    RETURN 0.
}
FUNCTION gpcDisp {                           // "LIVE" / "FROZEN" (its GPC died < 3 s ago: the last picture, the clock running) / "X" (the big X)
    PARAMETER d.
    IF DEFINED FLFX_SWPG {                  // A SW 03 page (lib_flfx): FROZEN = the last picture; BLANK = FROZEN, then the X after GPC_POLL_S
        IF FLFX_SWPG:HASKEY(d) {
            LOCAL se IS flActiveEnt("SW 03", d).
            IF FLFX_SWPG[d] = "BLANK" AND se:LENGTH > 0 AND flUt() - se["met"] >= GPC_POLL_S { RETURN "X". }
            RETURN "FROZEN".
        }
    }
    IF FL_ACTIVE:LENGTH = 0 { RETURN "LIVE". }
    LOCAL g IS gpcOwner(d).
    IF g = 0 { RETURN "LIVE". }
    IF g <= 4 AND gpcPassOut() { RETURN CHOOSE "FROZEN" IF flUt() - gpcPassOutAt() < GPC_POLL_S ELSE "X". }     // DPS 05 / the BFS flying: the PASS displays freeze, then the big X (G5's display is live)
    LOCAL e IS gpcEnt(g).
    IF e:LENGTH = 0 { RETURN "LIVE". }
    IF e["code"] = "DPS 03" OR e["code"] = "DPS 06" { RETURN "FROZEN". }                // out of sync / bad output: the display keeps its last picture (no big X) until it is re-assigned
    IF flUt() - e["met"] < GPC_POLL_S { RETURN "FROZEN". }
    RETURN "X".
}
FUNCTION gpcLive { PARAMETER d. RETURN gpcDisp(d) = "LIVE". }
FUNCTION gpcPageDisp {                       // OPS2: the display a page is on
    PARAMETER pg.
    IF pg = "OMS" OR pg = "PDRS" { RETURN "SM". }
    RETURN "GNC".
}
FUNCTION gpcDispsOf {                        // the displays GPC k drives now
    PARAMETER k.
    LOCAL out IS LIST().
    FOR d IN GPC_MAP:KEYS { IF gpcOwner(d) = k { out:ADD(d). } }
    RETURN out.
}
FUNCTION gpcClassOf {                        // OPS2: the class of the job GPC k runs: "GNC" (G1, G2) or "SM" (G4)
    PARAMETER k.
    RETURN CHOOSE "SM" IF k = 4 ELSE "GNC".
}
FUNCTION gpcCanHost {                        // may good GPC c drive display d?
    PARAMETER c, d.
    IF c < 1 OR c > 4 OR gpcFailed(c) { RETURN FALSE. }
    IF gpcPassOut() { RETURN FALSE. }                    // The PASS set flies nothing: no PASS GPC takes a display
    IF GPC_PROG <> "OPS2" { RETURN TRUE. }               // ascent / entry: all four PASS GPCs are in the one redundant set
    IF c = 1 OR c = 2 { RETURN d = "GNC". }
    IF c = 4 { RETURN d = "SM". }
    FOR j IN GPC_JOBS { IF gpcClassOf(j) = d { RETURN TRUE. } }     // c = 3: the freeze-dried GPC, carrying a job
    RETURN FALSE.
}
FUNCTION gpcReTarget {                       // the GPC GPC k's displays would move to (0 = none, or it drives no display)
    PARAMETER k.
    LOCAL ds IS gpcDispsOf(k).
    IF ds:LENGTH = 0 { RETURN 0. }
    FOR d IN ds { IF GPC_PEND:HASKEY(d) { RETURN 0. } }
    FROM { LOCAL c IS 1. } UNTIL c > 4 STEP { SET c TO c + 1. } DO {
        IF c <> k {
            LOCAL ok IS TRUE.
            FOR d IN ds { IF NOT gpcCanHost(c, d) { SET ok TO FALSE. } }
            IF ok { RETURN c. }
        }
    }
    RETURN 0.
}

// ---- the registered windows (the display libraries' X look)
FUNCTION gpcWin {                            // display name, apply(dead) -> the X look on (TRUE) / off (FALSE)
    PARAMETER d, ap.
    SET GPC_WIN[d] TO LEXICON("ap", ap, "st", "LIVE").
}
FUNCTION gpcWinSync {                        // apply the X look of every registered display whose state changed (gpcTick's; a window built later: call it)
    FOR d IN GPC_WIN:KEYS {
        LOCAL w IS GPC_WIN[d].
        LOCAL xs IS gpcDisp(d) = "X".
        LOCAL was IS w["st"] = "X".
        IF xs <> was {
            SET w["st"] TO CHOOSE "X" IF xs ELSE "LIVE".
            IF kmLive(w["ap"]) { w["ap"]:CALL(xs). }
        }
    }
}
FUNCTION gpcWinForget {                      // a window gone (its X look off by itself): its registration dropped
    PARAMETER d.
    IF GPC_WIN:HASKEY(d) { GPC_WIN:REMOVE(d). }
}

// ---- the entry (lib_fail's handler) and the host's calls
FUNCTION gpcKickGo {                         // DPS 06's bad-command spell: one random axis, a random sign, 1-3 s (the DLL's GPCKICK adds the bias to the final control state)
    PARAMETER k.
    LOCAL axs IS LIST("PITCH", "YAW", "ROLL").
    LOCAL ax IS axs[MIN(2, FLOOR(RANDOM() * 3))].
    LOCAL sg IS CHOOSE 1 IF RANDOM() < 0.5 ELSE -1.
    LOCAL du IS ROUND(1 + RANDOM() * 2, 1).
    SET GPC_KICKS TO GPC_KICKS + 1.
    LOCAL dl IS "NO DLL".
    IF FL_FAKE < 0 AND ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("GPCKICK") { SET dl TO ADDONS:KALS:GPCKICK(ax, sg, du). } }
    flLog("GPC G" + k + " OUTPUT BAD: " + ax + " " + (CHOOSE "+" IF sg > 0 ELSE "-") + " " + du + " S (" + dl + ")").
}
FUNCTION gpcHandle {                         // flReg("DPS 01" / 02 / 03 / 06, gpcHandle@): (tg, vl, why) -> "OK" / "OK:Gk" / "REFUSE: text"
    PARAMETER tg, vl, why.
    IF why = "RESTORE" { RETURN "OK". }
    IF gpcCommonIdx() >= 0 { RETURN "REFUSE: SET SPLIT / PASS FAILED". }
    LOCAL k IS gpcNum(tg).
    IF tg = "ANY" {
        LOCAL c IS LIST().
        FROM { LOCAL i IS 1. } UNTIL i > 4 STEP { SET i TO i + 1. } DO { IF NOT gpcFailed(i) { c:ADD(i). } }
        IF c:LENGTH <= 1 { RETURN "REFUSE: NO GPC LEFT". }
        SET k TO c[MIN(c:LENGTH - 1, FLOOR(RANDOM() * c:LENGTH))].
    }
    IF k < 1 OR k > 5 { RETURN "REFUSE: BAD TARGET " + tg. }
    IF gpcFailed(k) { RETURN "REFUSE: ALREADY FAILED". }
    IF k <= 4 AND gpcPassLive() <= 1 { RETURN "REFUSE: NO GPC LEFT". }     // up to 3 of the 4 PASS GPCs may fail: the last good one is refused
    RETURN "OK:G" + k.
}
FUNCTION gpcHandle6 {                        // DPS 06's handler = gpcHandle + the bad-command spell (not on a RESTORE: the spell is over by then)
    PARAMETER tg, vl, why.
    LOCAL ans IS gpcHandle(tg, vl, why).
    IF why <> "RESTORE" AND ans:STARTSWITH("OK:G") { gpcKickGo(ans:SUBSTRING(4, 1):TONUMBER(0)). }
    RETURN ans.
}
// ----the PASS set as a whole (DPS 04 REDUNDANT SET SPLIT, DPS 05 PASS GENERIC FAIL) and the BFS
FUNCTION gpcSplitIdx { RETURN flActiveIdx("DPS 04", "2-2"). }
FUNCTION gpcPassFailIdx { RETURN flActiveIdx("DPS 05", "G1-G4"). }
FUNCTION gpcCommonIdx {                      // the ACTIVE index of the standing DPS 04 / DPS 05 (-1 = none)
    LOCAL i IS gpcSplitIdx().
    IF i >= 0 { RETURN i. }
    RETURN gpcPassFailIdx().
}
FUNCTION gpcCommonEnt {                      // the standing DPS 04 / DPS 05 entry (LEXICON() = none), for a reader that must not hold an index
    LOCAL e IS flActiveEnt("DPS 04", "2-2").
    IF e:LENGTH > 0 { RETURN e. }
    RETURN flActiveEnt("DPS 05", "G1-G4").
}
FUNCTION gpcPassOut {                        // TRUE when the PASS GPCs fly nothing: DPS 05 stands, or the BFS took over (from a split too). Not in orbit (no 4-GPC set there)
    IF GPC_PROG = "OPS2" { RETURN FALSE. }
    RETURN GPC_BFS OR gpcPassFailIdx() >= 0.
}
FUNCTION gpcPassOutAt {                      // the UT the PASS set went out
    LOCAL pe IS flActiveEnt("DPS 05", "G1-G4").
    IF pe:LENGTH > 0 { RETURN pe["met"]. }
    RETURN GPC_BFSAT.
}
FUNCTION gpcNoPilot {                        // the automated test flight has the flight: the crew's picks are ours
    IF GPC_NOPILOT >= 0 { RETURN GPC_NOPILOT = 1. }
    IF FL_FAKE >= 0 { RETURN FALSE. }
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:HASSUFFIX("SAILON") { RETURN FALSE. }
    RETURN ADDONS:KALS:SAILON.
}
FUNCTION gpcPairName { PARAMETER p. RETURN CHOOSE "1-2" IF p = 1 ELSE "3-4". }
FUNCTION gpcPairSeed {                       // the good pair, drawn once per split and hidden (the crew's only cue: none)
    IF GPC_PAIR = 0 { SET GPC_PAIR TO CHOOSE 1 IF RANDOM() < 0.5 ELSE 2. gpcSave(). }
}
FUNCTION gpcSay {                            // One short line on the SM ALERT readout (28 characters; the crew's MASTER ALARM press clears it), the way lib_fail raises a software alert
    PARAMETER txt.
    IF kmLive(FL_ALERT) { FL_ALERT:CALL(txt). } ELSE { cwAlert(txt). }
}
FUNCTION gpcHandle4 {                        // flReg("DPS 04"): the four PASS GPCs split 2-2
    PARAMETER tg, vl, why.
    IF why = "RESTORE" { RETURN "OK". }
    IF gpcPassFailIdx() >= 0 { RETURN "REFUSE: PASS SET ALREADY DOWN". }
    IF gpcPassLive() < 4 { RETURN "REFUSE: NO FOUR-GPC SET TO SPLIT". }
    SET GPC_PAIR TO CHOOSE 1 IF RANDOM() < 0.5 ELSE 2.
    SET GPC_PWRONG TO 0.
    SET GPC_PLOCK TO 0.
    gpcSave().
    flLog("GPC SET SPLIT 2-2: G1+G2 AND G3+G4 DISAGREE").
    gpcSay("SET SPLIT: PAIR OR BFS").
    RETURN "OK".
}
FUNCTION gpcHandle5 {                        // flReg("DPS 05"): all four PASS GPCs fail at once; the BFS (G5) must be alive to take over
    PARAMETER tg, vl, why.
    IF why = "RESTORE" { RETURN "OK". }
    IF gpcSplitIdx() >= 0 { RETURN "REFUSE: SET SPLIT STANDS". }
    IF gpcFailed(5) { RETURN "REFUSE: NO BFS (G5 FAILED)". }
    SET GPC_BFS TO FALSE.
    flLog("GPC PASS FAIL: G1-G4 DOWN, THE BFS (G5) IS READY").
    gpcSay("PASS DOWN: CSS, ENGAGE BFS").
    RETURN "OK".
}
FUNCTION gpcGuard4 {                         // DPS 04's fix is the PAIR keys' (the window's plain FIX would skip the choice)
    PARAMETER tg.
    IF GPC_PAIROK { RETURN "". }
    RETURN "USE THE PAIR KEYS (1-2 / 3-4)".
}
FUNCTION gpcGuard5 {                         // DPS 05's fix: the PASS set is loaded again in orbit
    PARAMETER tg.
    IF GPC_PROG = "OPS2" { RETURN "". }
    RETURN "RE-IPL IN ORBIT ONLY: BFS ENGAGE UNTIL THEN".
}
FUNCTION gpcGuard {                          // lib_fail's guard of DPS 02's fix (RESTART): the host's rule
    PARAMETER tg.
    IF kmLive(GPC_CANRS) { RETURN GPC_CANRS:CALL(). }
    RETURN "".
}
FUNCTION gpcInit {                           // the host's start (after flInit): its program, its displays, DPS 01 / 02 registered, the tasks back
    PARAMETER prog, canRestart IS 0.
    SET GPC_PROG TO prog.
    SET GPC_CANRS TO canRestart.
    GPC_MAP:CLEAR().
    GPC_ASG:CLEAR().
    GPC_PEND:CLEAR().
    IF prog = "OPS2" { SET GPC_MAP["GNC"] TO 1. SET GPC_MAP["SM"] TO 4. }
    ELSE { SET GPC_MAP["TOP"] TO 1. SET GPC_MAP["BOT"] TO 2. }
    flReg("DPS 01", gpcHandle@).
    flReg("DPS 02", gpcHandle@).
    flReg("DPS 03", gpcHandle@).           // GPC FAIL TO SYNC
    flReg("DPS 06", gpcHandle6@).          // GPC OUTPUT BAD (the bad-command spell, then out of the set)
    SET FL_GUARD["DPS 02"] TO gpcGuard@.
    SET FL_GUARD["DPS 03"] TO gpcGuard@.
    SET FL_GUARD["DPS 06"] TO gpcGuard@.
    SET FL_GUARD["DPS 04"] TO gpcGuard4@.
    SET FL_GUARD["DPS 05"] TO gpcGuard5@.
    IF prog <> "OPS2" {                    // ascent / entry only (orbit has no 4-GPC PASS set)
        flReg("DPS 04", gpcHandle4@).
        flReg("DPS 05", gpcHandle5@).
    }
    // Every host calls flSimHost BEFORE gpcInit, so the code list it sent the DLL's SimSup lacked DPS 01 / DPS 02 (flFlyable is true only once flReg ran):
    // SimSup never drew a GPC failure. Host again now that they are registered (the same program: idempotent).
    IF FL_SIMPROG <> "" { flSimHost(FL_SIMPROG). }
    gpcLoad().
    IF GPC_BFS AND prog <> "OPS2" {          // The BFS flies: its display survives the program change (the display the crew moved it to, TOP by default)
        LOCAL bd IS "".
        IF GPC_BFSD <> "" AND GPC_MAP:HASKEY(GPC_BFSD) { SET bd TO GPC_BFSD. }
        ELSE { FOR d IN GPC_MAP:KEYS { IF bd = "" AND (d = "TOP" OR d = "GNC") { SET bd TO d. } } }
        IF bd <> "" { SET GPC_ASG[bd] TO 5. SET GPC_BFSD TO bd. }
    }
}
FUNCTION gpcHas { RETURN GPC_PROG <> "". }
FUNCTION gpcClose {                          // the host's end: the X looks off, the windows forgotten
    FOR d IN GPC_WIN:KEYS {
        LOCAL w IS GPC_WIN[d].
        IF w["st"] = "X" AND kmLive(w["ap"]) { w["ap"]:CALL(FALSE). }
    }
    GPC_WIN:CLEAR().
    gpcSave().
}

// ---- the crew's actions: "OK" or "REFUSE: text"
FUNCTION gpcTask {                           // the task of kind under way for GPC k (the entry, or 0 -> index -1)
    PARAMETER kind, k.
    LOCAL i IS 0.
    FOR t IN GPC_TASKS { IF t["kind"] = kind AND t["g"] = k { RETURN i. } SET i TO i + 1. }
    RETURN -1.
}
FUNCTION gpcReassign {                       // GPC/CRT X/Y EXEC: every display of failed GPC k to a good GPC that may carry it
    PARAMETER k.
    IF NOT gpcFailed(k) { RETURN "REFUSE: G" + k + " IS GOOD". }
    LOCAL ds IS gpcDispsOf(k).
    IF ds:LENGTH = 0 { RETURN "REFUSE: G" + k + " DRIVES NO DISPLAY". }
    FOR d IN ds { IF GPC_PEND:HASKEY(d) { RETURN "REFUSE: RE-ASSIGN UNDER WAY". } }
    LOCAL t IS gpcReTarget(k).
    IF t = 0 { RETURN "REFUSE: NO GPC CAN TAKE IT". }
    LOCAL hl IS CHOOSE GPC_HALT_S IF gpcSyncOut(k) ELSE 0.         // An out-of-sync GPC is HALTed first
    FOR d IN ds { SET GPC_PEND[d] TO LEXICON("g", t, "at", flUt() + hl + GPC_ASG_S, "hl", flUt() + hl). }
    IF hl > 0 { flLog("GPC " + k + " HALT"). }
    flLog("GPC/CRT " + t + "/" + ds:JOIN(",") + " EXEC (G" + k + " FAILED)").
    RETURN "OK".
}
FUNCTION gpcLoadJob {                        // OPS 2: the failed GPC's job to the freeze-dried G3
    PARAMETER k.
    IF GPC_PROG <> "OPS2" { RETURN "REFUSE: ORBIT ONLY". }
    IF NOT gpcFailed(k) { RETURN "REFUSE: G" + k + " IS GOOD". }
    IF k = 3 OR k = 5 { RETURN "REFUSE: NO JOB TO LOAD". }
    IF GPC_JOBS:CONTAINS(k) OR gpcTask("JOB", k) >= 0 { RETURN "REFUSE: JOB ALREADY MOVED". }
    IF gpcFailed(3) { RETURN "REFUSE: G3 FAILED". }
    IF GPC_JOBS:LENGTH > 0 OR gpcTaskAny("JOB") { RETURN "REFUSE: G3 BUSY". }
    GPC_TASKS:ADD(LEXICON("kind", "JOB", "g", k, "at", flUt() + GPC_JOB_S)).
    flLog("LOAD JOB G" + k + " TO G3 (" + GPC_JOB_S + " S)").
    RETURN "OK".
}
FUNCTION gpcTaskAny {                        // any task of this kind under way
    PARAMETER kind.
    FOR t IN GPC_TASKS { IF t["kind"] = kind { RETURN TRUE. } }
    RETURN FALSE.
}
FUNCTION gpcSwapSpare {                      // OPS 2, once per flight: the failed hardware GPC replaced by the spare
    PARAMETER k.
    IF GPC_PROG <> "OPS2" { RETURN "REFUSE: ORBIT ONLY". }
    IF NOT gpcFailed(k) { RETURN "REFUSE: G" + k + " IS GOOD". }
    IF gpcKind(k) <> "HW" { RETURN CHOOSE "REFUSE: A TRANSIENT NEEDS NO SPARE" IF gpcKind(k) = "TR" ELSE "REFUSE: NO SPARE FOR THIS FAILURE". }
    IF GPC_SPARE { RETURN "REFUSE: THE SPARE IS USED". }
    LOCAL dr IS flDllFix("DPS 01", "G" + k, "SWAP SPARE").       // the vessel's own list ends it with the same 3600 s (its refusal stands)
    IF dr <> "" AND dr <> "OK" { RETURN dr. }
    SET GPC_SPARE TO TRUE.
    GPC_TASKS:ADD(LEXICON("kind", "SPARE", "g", k, "at", flUt() + GPC_SPARE_S)).
    flLog("SWAP SPARE G" + k + " (" + GPC_SPARE_S + " S)").
    RETURN "OK".
}
FUNCTION gpcRestart {                        // re-IPL a TRANSIENT GPC (lib_fail's fix with its guard and its delay)
    PARAMETER k.
    LOCAL i IS gpcIdx(k).
    IF i < 0 { RETURN "REFUSE: G" + k + " IS GOOD". }
    IF gpcKind(k) <> "TR" { RETURN CHOOSE "REFUSE: HARDWARE FAIL: NO RESTART" IF gpcKind(k) = "HW" ELSE "REFUSE: PERMANENT: NO RESTART". }
    RETURN flFix(i).
}

FUNCTION gpcPair {                           // PAIR 1-2 (p = 1) / PAIR 3-4 (p = 2): the crew's pick for DPS 04
    PARAMETER p.
    LOCAL i IS gpcSplitIdx().
    IF i < 0 { RETURN "REFUSE: NO SET SPLIT". }
    IF GPC_BFS { RETURN "REFUSE: BFS FLYING". }
    IF FL_ACTIVE[i]["fixAt"] >= 0 { RETURN "REFUSE: PAIR ALREADY PICKED". }
    LOCAL ut IS flUt().
    IF ut < GPC_PLOCK { RETURN "REFUSE: PAIRS RE-VOTING " + MAX(1, ROUND(GPC_PLOCK - ut)) + " S". }
    IF p = GPC_PWRONG { RETURN "REFUSE: PAIR " + gpcPairName(p) + " DISAGREES". }
    gpcPairSeed().
    IF p <> GPC_PAIR {
        SET GPC_PWRONG TO p.
        SET GPC_PLOCK TO ut + GPC_PAIR_WRONG_S.
        gpcSave().
        flLog("PAIR " + gpcPairName(p) + " DISAGREES WITH THE OTHER PAIR: THE SET RE-VOTES " + GPC_PAIR_WRONG_S + " S").
        RETURN "REFUSE: PAIR " + gpcPairName(p) + " DISAGREES: RE-VOTE " + GPC_PAIR_WRONG_S + " S".
    }
    SET GPC_PAIROK TO TRUE.
    LOCAL fr IS flFix(i).
    SET GPC_PAIROK TO FALSE.
    IF fr = "OK" { flLog("PAIR " + gpcPairName(p) + " TAKES THE SET"). }
    RETURN fr.
}
FUNCTION gpcBfsEngage {                      // BFS ENGAGE: G5 flies the rest (after DPS 04 or DPS 05): the guidance and AUTO come back, ONE display window
    LOCAL i IS gpcCommonIdx().
    IF GPC_BFS { RETURN "REFUSE: BFS ALREADY ENGAGED". }
    IF i < 0 { RETURN "REFUSE: NO PASS FAILURE: THE BFS STAYS ASLEEP". }
    IF gpcFailed(5) { RETURN "REFUSE: G5 FAILED: NO BFS". }
    IF FL_ACTIVE[i]["code"] = "DPS 04" AND FL_ACTIVE[i]["fixAt"] >= 0 { RETURN "REFUSE: PAIR PICKED". }
    SET GPC_BFS TO TRUE.
    SET GPC_BFSAT TO flUt().
    LOCAL dd IS "".
    FOR d IN GPC_MAP:KEYS { IF dd = "" AND (d = "TOP" OR d = "GNC") { SET dd TO d. } }
    IF dd <> "" { SET GPC_ASG[dd] TO 5. }
    SET GPC_BFSD TO dd.
    flLog("BFS ENGAGE: G5 FLIES, ONE DISPLAY (" + dd + "), THE OTHER STAYS DEAD").
    gpcSay("BFS ENGAGED: " + (CHOOSE dd + " DISPLAY" IF dd <> "" ELSE "ONE DISPLAY")).
    gpcSave().
    RETURN "OK".
}
FUNCTION gpcBfsDisp { RETURN CHOOSE GPC_BFSD IF GPC_BFS AND GPC_PROG <> "OPS2" ELSE "". }      // The display the BFS drives now ("" = the BFS is not flying)
FUNCTION gpcBfsOther {                       // The other of the two PASS displays ("TOP" <-> "BOT"; "" = the program has no such pair)
    IF NOT (GPC_MAP:HASKEY("TOP") AND GPC_MAP:HASKEY("BOT")) { RETURN "". }
    RETURN CHOOSE "BOT" IF GPC_BFSD = "TOP" ELSE "TOP".
}
FUNCTION gpcBfsMove {                        // The crew moves the BFS display: to d ("TOP" / "BOT"), or "" = the other one; the slot left gets the big X, the new one is live
    PARAMETER d IS "".
    IF NOT GPC_BFS { RETURN "REFUSE: THE BFS IS NOT FLYING". }
    IF GPC_PROG = "OPS2" { RETURN "REFUSE: NO BFS DISPLAY IN ORBIT". }
    IF gpcFailed(5) { RETURN "REFUSE: G5 FAILED: NO BFS". }
    LOCAL nd IS d.
    IF nd = "" { SET nd TO gpcBfsOther(). }
    IF nd <> "TOP" AND nd <> "BOT" { RETURN "REFUSE: NO SUCH DISPLAY". }
    IF NOT GPC_MAP:HASKEY(nd) { RETURN "REFUSE: NO SUCH DISPLAY". }
    IF nd = GPC_BFSD { RETURN "REFUSE: THE BFS IS ALREADY ON " + nd. }
    LOCAL old IS GPC_BFSD.
    IF old <> "" AND GPC_ASG:HASKEY(old) { IF GPC_ASG[old] = 5 { GPC_ASG:REMOVE(old). } }
    IF GPC_PEND:HASKEY(nd) { GPC_PEND:REMOVE(nd). }
    SET GPC_ASG[nd] TO 5.
    SET GPC_BFSD TO nd.
    flLog("BFS DISPLAY MOVED: " + old + " -> " + nd + " (" + old + " IS THE BIG X)").
    gpcSave().
    gpcWinSync().
    RETURN "OK".
}

// ---- what a key may do now (lib_failui lights / darkens its keys by this)
FUNCTION gpcCan {                            // LEXICON(ra, lj, ss, rs): booleans for failed GPC k
    PARAMETER k.
    LOCAL c IS LEXICON("ra", FALSE, "lj", FALSE, "ss", FALSE, "rs", FALSE).
    LOCAL ge IS gpcEnt(k).
    IF ge:LENGTH = 0 { RETURN c. }
    SET c["ra"] TO gpcReTarget(k) > 0.
    IF GPC_PROG = "OPS2" {
        SET c["lj"] TO k <> 3 AND k <> 5 AND NOT GPC_JOBS:CONTAINS(k) AND gpcTask("JOB", k) < 0 AND NOT gpcFailed(3) AND GPC_JOBS:LENGTH = 0 AND NOT gpcTaskAny("JOB").
        SET c["ss"] TO gpcKind(k) = "HW" AND NOT GPC_SPARE.
    }
    IF gpcKind(k) = "TR" AND ge["fixAt"] < 0 AND gpcGuard("G" + k) = "" { SET c["rs"] TO TRUE. }
    RETURN c.
}
FUNCTION gpcStrip {                          // the two lines of GPC k's screen strip (caps, as the window's other screens)
    PARAMETER k.
    LOCAL e IS gpcEnt(k).
    IF e:LENGTH = 0 { RETURN LIST("", ""). }
    LOCAL kind IS CHOOSE "HARDWARE FAIL" IF gpcKind(k) = "HW" ELSE "TRANSIENT FAIL".
    IF e["code"] = "DPS 03" { SET kind TO "FAIL TO SYNC". }
    IF e["code"] = "DPS 06" { SET kind TO "OUTPUT BAD". }
    LOCAL t IS gpcReTarget(k).
    LOCAL l0 IS "G" + k + " " + kind.
    IF t > 0 { SET l0 TO l0 + "  RE-ASSIGN TO G" + t. }
    ELSE IF gpcDispsOf(k):LENGTH = 0 { SET l0 TO l0 + "  NO DISPLAY". }
    LOCAL ut IS flUt().
    LOCAL l1 IS "".
    IF e["fixAt"] >= 0 {
        LOCAL rm IS MAX(0, ROUND(e["fixAt"] - ut)).
        SET l1 TO "RESTART " + rm + " S".
        IF rm <= GPC_HANDS_S { SET l1 TO l1 + "  HANDS OFF". }
    }
    FOR d IN gpcDispsOf(k) { IF GPC_PEND:HASKEY(d) { IF GPC_PEND[d]:HASKEY("hl") AND ut < GPC_PEND[d]["hl"] { SET l1 TO "HALT " + MAX(0, ROUND(GPC_PEND[d]["hl"] - ut)) + " S". } ELSE { SET l1 TO "RE-ASSIGN " + MAX(0, ROUND(GPC_PEND[d]["at"] - ut)) + " S". } } }
    IF gpcTask("JOB", k) >= 0 { SET l1 TO "LOAD JOB " + MAX(0, ROUND(GPC_TASKS[gpcTask("JOB", k)]["at"] - ut)) + " S". }
    IF gpcTask("SPARE", k) >= 0 { SET l1 TO "SWAP SPARE " + MAX(0, ROUND((GPC_TASKS[gpcTask("SPARE", k)]["at"] - ut) / 60)) + " MIN". }
    IF l1 = "" AND GPC_JOBS:CONTAINS(k) { SET l1 TO "JOB ON G3". }
    IF l1 = "" AND GPC_SPARE AND gpcKind(k) = "HW" AND GPC_PROG = "OPS2" { SET l1 TO "SPARE USED". }
    IF l1 = "" AND gpcSyncOut(k) AND gpcDispsOf(k):LENGTH > 0 AND t > 0 { SET l1 TO "HALT + RE-ASSIGN". }        // The out-of-set GPC's displays still sit frozen on it
    RETURN LIST(l0, l1).
}
FUNCTION gpcSetCan {                         // LEXICON(p1, p2, bf): the SET slot's keys (PAIR 1-2, PAIR 3-4, BFS ENGAGE)
    LOCAL c IS LEXICON("p1", FALSE, "p2", FALSE, "bf", FALSE, "bd", FALSE).
    LOCAL e IS gpcCommonEnt().
    IF e:LENGTH > 0 AND GPC_BFS { SET c["bd"] TO gpcBfsOther() <> "" AND NOT gpcFailed(5) AND GPC_PROG <> "OPS2". }     // BFS DISP: the BFS flies, G5 is good, there is another display to move it to
    IF e:LENGTH = 0 OR GPC_BFS { RETURN c. }
    IF e["fixAt"] >= 0 { RETURN c. }
    IF e["code"] = "DPS 04" AND flUt() >= GPC_PLOCK {
        SET c["p1"] TO GPC_PWRONG <> 1.
        SET c["p2"] TO GPC_PWRONG <> 2.
    }
    SET c["bf"] TO NOT gpcFailed(5).
    RETURN c.
}
FUNCTION gpcBfsLine {                        // The strip line while the BFS flies: which display it drives
    LOCAL d IS gpcBfsDisp().
    IF d = "TOP" { RETURN "BFS FLYING (G5): TOP DISPLAY". }
    IF d = "BOT" { RETURN "BFS FLYING (G5): BOTTOM DISPLAY". }
    RETURN "BFS FLYING (G5): ONE DISPLAY".
}
FUNCTION gpcSetStrip {                       // The two lines of the SET slot's screen strip ("" = nothing stands: the slot is hidden)
    LOCAL e IS gpcCommonEnt().
    IF e:LENGTH = 0 { RETURN LIST("", ""). }
    LOCAL ut IS flUt().
    IF e["code"] = "DPS 04" {
        LOCAL a IS "PICK A PAIR OR ENGAGE BFS".
        IF GPC_BFS { SET a TO gpcBfsLine(). }
        ELSE IF e["fixAt"] >= 0 { SET a TO "PAIR PICKED: THE SET REFORMS " + MAX(0, ROUND(e["fixAt"] - ut)) + " S". }
        ELSE IF ut < GPC_PLOCK { SET a TO "PAIR " + gpcPairName(GPC_PWRONG) + " DISAGREES: RE-VOTE " + MAX(1, ROUND(GPC_PLOCK - ut)) + " S". }
        ELSE IF GPC_PWRONG <> 0 { SET a TO "PAIR " + gpcPairName(GPC_PWRONG) + " DISAGREES: PICK THE OTHER OR BFS". }
        RETURN LIST("SET SPLIT 2-2: G1+G2 / G3+G4", a).
    }
    LOCAL b IS "BFS ENGAGE".
    IF GPC_BFS { SET b TO gpcBfsLine(). }
    IF e["fixAt"] >= 0 { SET b TO "RE-IPL PASS " + MAX(0, ROUND(e["fixAt"] - ut)) + " S". }
    RETURN LIST("PASS FAIL: G1-G4 DOWN", b).
}
FUNCTION gpcSigNow {                         // changes whenever a strip or a key would (lib_failui redraws on it)
    LOCAL ss IS gpcSetStrip().
    LOCAL sc IS gpcSetCan().
    LOCAL s IS ss[0] + ss[1] + sc["p1"] + sc["p2"] + sc["bf"] + sc["bd"] + gpcBfsDisp() + ";".
    FOR k IN gpcFailedList() {
        LOCAL c IS gpcCan(k).
        LOCAL st IS gpcStrip(k).
        SET s TO s + k + ":" + c["ra"] + c["lj"] + c["ss"] + c["rs"] + st[0] + st[1] + ";".
    }
    RETURN s.
}

// ---- the loop
FUNCTION gpcCommonTick {                     // The PASS set failures: the OPS 2 re-IPL, the test flight's crew, the state cleaned up when nothing stands
    PARAMETER ut.
    LOCAL i IS gpcCommonIdx().
    IF i < 0 {
        IF GPC_BFS {
            SET GPC_BFS TO FALSE.
            LOCAL rm IS LIST().
            FOR d IN GPC_ASG:KEYS { IF GPC_ASG[d] = 5 { rm:ADD(d). } }
            FOR d IN rm { GPC_ASG:REMOVE(d). }
            SET GPC_BFSD TO "".
            flLog("PASS SET BACK: THE BFS STANDS DOWN").
            gpcSave().
        }
        IF GPC_PAIR <> 0 OR GPC_PWRONG <> 0 { SET GPC_PAIR TO 0. SET GPC_PWRONG TO 0. SET GPC_PLOCK TO 0. gpcSave(). }
        RETURN.
    }
    LOCAL e IS FL_ACTIVE[i].
    IF GPC_PROG = "OPS2" {                 // the OPS 2 start loads the PASS set again (the same real fix, started by the program change)
        IF e["fixAt"] < 0 {
            SET GPC_PAIROK TO TRUE.
            LOCAL fr IS flFix(i).
            SET GPC_PAIROK TO FALSE.
            flLog("OPS 2: THE PASS SET IS LOADED AGAIN (" + e["code"] + "): " + fr).
        }
        RETURN.
    }
    IF gpcNoPilot() AND NOT GPC_BFS AND e["fixAt"] < 0 {
        IF e["code"] = "DPS 04" AND ut - e["met"] >= GPC_NP_PAIR_S AND ut >= GPC_PLOCK {
            gpcPairSeed().
            flLog("SAIL CREW: PAIR " + gpcPairName(GPC_PAIR)).
            gpcPair(GPC_PAIR).
        }
        IF e["code"] = "DPS 05" AND ut - e["met"] >= GPC_NP_BFS_S {
            flLog("SAIL CREW: BFS ENGAGE").
            gpcBfsEngage().
        }
    }
}
FUNCTION gpcTick {
    IF NOT gpcHas() { RETURN. }
    LOCAL ut IS flUt().
    LOCAL ch IS FALSE.
    FOR d IN GPC_PEND:KEYS {                 // re-assignments that are over
        IF ut >= GPC_PEND[d]["at"] {
            SET GPC_ASG[d] TO GPC_PEND[d]["g"].
            flLog("DISPLAY " + d + " NOW ON G" + GPC_PEND[d]["g"]).
            GPC_PEND:REMOVE(d).
        }
    }
    FROM { LOCAL j IS GPC_TASKS:LENGTH - 1. } UNTIL j < 0 STEP { SET j TO j - 1. } DO {
        LOCAL t IS GPC_TASKS[j].
        IF ut >= t["at"] {
            GPC_TASKS:REMOVE(j).
            IF t["kind"] = "JOB" { IF NOT GPC_JOBS:CONTAINS(t["g"]) { GPC_JOBS:ADD(t["g"]). } flLog("JOB OF G" + t["g"] + " LOADED ON G3"). }
            ELSE { flRemove(gpcIdx(t["g"]), "SPARE SWAPPED IN FOR"). }
            SET ch TO TRUE.
        }
    }
    IF GPC_JOBS:LENGTH > 0 AND gpcFailed(3) { GPC_JOBS:CLEAR(). flLog("G3 FAILED: ITS JOB IS LOST"). SET ch TO TRUE. }
    gpcCommonTick(ut).
    gpcWinSync().
    LOCAL sg IS GPC_JOBS:LENGTH + "/" + GPC_SPARE + "/" + GPC_TASKS:LENGTH.
    IF sg <> GPC_SIG OR ch { SET GPC_SIG TO sg. gpcSave(). }
}

// ---- persistence (what survives a program change)
FUNCTION gpcSave {
    IF EXISTS(GPC_FILE) { DELETEPATH(GPC_FILE). }
    IF GPC_SPARE { LOG "SPARE,1" TO GPC_FILE. }
    FOR j IN GPC_JOBS { LOG "JOB," + j TO GPC_FILE. }
    FOR t IN GPC_TASKS { LOG "TASK," + t["kind"] + "," + t["g"] + "," + t["at"] TO GPC_FILE. }
    IF GPC_BFS { LOG "BFS," + GPC_BFSAT + "," + GPC_BFSD TO GPC_FILE. }
    IF GPC_PAIR <> 0 { LOG "PAIR," + GPC_PAIR + "," + GPC_PWRONG + "," + GPC_PLOCK TO GPC_FILE. }
}
FUNCTION gpcLoad {
    SET GPC_SPARE TO FALSE.
    GPC_JOBS:CLEAR().
    GPC_TASKS:CLEAR().
    SET GPC_BFS TO FALSE.
    SET GPC_BFSD TO "".
    SET GPC_PAIR TO 0.
    SET GPC_PWRONG TO 0.
    SET GPC_PLOCK TO 0.
    IF EXISTS(GPC_FILE) {
        FOR gln IN OPEN(GPC_FILE):READALL:STRING:SPLIT(CHAR(10)) {
            LOCAL f IS gln:TRIM:SPLIT(",").
            IF f[0] = "SPARE" { SET GPC_SPARE TO TRUE. }
            ELSE IF f[0] = "JOB" AND f:LENGTH >= 2 { GPC_JOBS:ADD(f[1]:TONUMBER(0)). }
            ELSE IF f[0] = "BFS" AND f:LENGTH >= 2 { SET GPC_BFS TO TRUE. SET GPC_BFSAT TO f[1]:TONUMBER(0). IF f:LENGTH >= 3 { SET GPC_BFSD TO f[2]. } }
            ELSE IF f[0] = "PAIR" AND f:LENGTH >= 4 { SET GPC_PAIR TO f[1]:TONUMBER(0). SET GPC_PWRONG TO f[2]:TONUMBER(0). SET GPC_PLOCK TO f[3]:TONUMBER(0). }
            ELSE IF f[0] = "TASK" AND f:LENGTH >= 4 { GPC_TASKS:ADD(LEXICON("kind", f[1], "g", f[2]:TONUMBER(0), "at", f[3]:TONUMBER(0))). }
        }
    }
}
FUNCTION gpcReset {                          // a new flight (lib_fail's flReset also ran): nothing moved, the spare back
    SET GPC_SPARE TO FALSE.
    GPC_JOBS:CLEAR().
    GPC_TASKS:CLEAR().
    GPC_ASG:CLEAR().
    GPC_PEND:CLEAR().
    SET GPC_BFS TO FALSE.
    SET GPC_BFSD TO "".
    SET GPC_PAIR TO 0.
    SET GPC_PWRONG TO 0.
    SET GPC_PLOCK TO 0.
    IF EXISTS(GPC_FILE) { DELETEPATH(GPC_FILE). }
}
