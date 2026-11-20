@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_FAILUI.KS  --  the FAILURES window shared by ops1q / ops2q / ops3q. The state is lib_fail.ks's; this file draws the
//  window and turns its keys into lib_fail calls. The look is the 1981-95 MCC console: CRT glass screens
//  (#0c0b0f, cyan capitals, Consolas) and key modules (70 x 50 caps, fixed legends: a key never changes its text, its STATE shows
//  by lighting it: amber / green / yellow / red, dark = disabled), sprites gui_panel/fk_*.png (tools/gen_fail_ui.py).
//  The window holds NO failure logic: a click only puts a tag on FUI_PRESS; fuiTick (the host's loop) takes the tags, moves the
//  builder / the filter / the modes itself, and calls flFire / flAddRow / flClearRows / flFix. What a failure DOES is the host's
//  handler (flReg), which the host registers before the window is used.
//  The modules (S2 + S3's GPC keys; S9b's SIMSUP section):
//    SIMSUP   DIFFICULTY EASY NORMAL HARD BRUTAL (the chosen one lit green) | ARM (amber: "ONE WAY FOR THIS FLIGHT") ENGAGE (red, only within
//             FUI_ARM_S = 10 s of ARM): the DLL's one-way latch (ADDONS:KALS:SIMLATCH): the rows are discarded, SCHEDULE / RAND / FILTER / FAIL NOW / ROWS grey out
//             (hidden), the screen reads "SIMSUP ACTIVE"; ACTIVE (what has failed, FIX) and the GPC keys stay: the crew's real fixes. No DLL: "DLL NEEDED".
//             fuiSched runs the DLL's planner while latched (flSimTick, plus the decision points fuiSimWatch / fuiSimPt / fuiSimBank derive from the hosts' state).
//    top      SCHEDULE (lit amber = the MET / TIG rows run) | RAND (lit amber = random failures) | MANUAL (lit green = neither)
//    RAND     scale X0.5 X1 X2 X5 / X10 X20 (the chosen one lit green)
//    FILTER   ALL MPS OMS RCS / FCS DPS SW (the chosen one lit green; a group nothing here can fly: dark)
//    FAIL NOW the BUILDER screen (the row being built: WHEN t, the type, its target / value / mode, then the last answer) and its
//             keys: WHEN MET TIG | STEP - STEP + (1 10 60 600 3600 s) | T - T + TYPE PREV TYPE NEXT (the step: top right of the readout) | TARGET NEXT
//             VALUE NEXT MODE NEXT FAIL (FAIL = at once, amber)
//    ROWS     the pending rows' screen ("N OF M ROWS") and + (add the builder's row) CONFIRM (SCHEDULE on, window hides)
//             CLEAR ALL (the pending rows go; nothing that has happened is undone: D11, no instructor CLEAR)
//    ACTIVE   what has failed (a > on the chosen one, its real fix on the next line) and ACTIVE PREV / NEXT / FIX
//    GPC      (only where the host flies DPS 01) up to four slots, one per FAILED GPC, each a two-line screen strip (the GPC, its failure,
//             the RE-ASSIGN target / the task under way) over a key row RE-ASSIGN | LOAD JOB | SWAP SPARE | RESTART (lit amber = allowed now,
//             dark = not: lib_gpc's gpcCan); a slot with no failed GPC is hidden. The keys call lib_gpc's gpcReassign / gpcLoadJob /
//             gpcSwapSpare / gpcRestart; the legends never change.
//  Only the types the host can fly (flFlyable) are offered.
//  The host: flInit() + flReg(...) for its codes, fuiBoot(reset), fuiInit(x, y) (or lazily: fuiToggle builds it), fuiTick(met, tig,
//  randOk) in its loop, fuiToggle() on its "!" button, fuiClose() at its end. FUI_SAY: obsolete (the answers stay in the failure window), never called.
//  Names fui* / FUI_*. Needs lib_guistyle.ks and lib_fail.ks.
// ============================================================================
RUNONCEPATH("0:/lib/lib_guistyle.ks").
RUNONCEPATH("0:/lib/lib_fail.ks").
RUNONCEPATH("0:/lib/lib_flfx.ks").         // What the failures do (fuiSched writes the effects back)
RUNONCEPATH("0:/lib/lib_gpc.ks").

GLOBAL FUI_W IS 330.                         // px wide
GLOBAL FUI_KW IS 70.                         // a key cap, px
GLOBAL FUI_KH IS 50.
GLOBAL FUI_ROW_H IS 17.                      // a screen line
GLOBAL FUI_FS IS 12.                         // screen font size
GLOBAL FUI_ROWS_SHOWN IS 6.                  // the rows screen's lines
GLOBAL FUI_ACT_SHOWN IS 4.                   // the ACTIVE screen's entry lines (+ the fix line)
GLOBAL FUI_CYAN IS "#27a9d1".                // the CRT text
GLOBAL FUI_AMB IS "#ffb000".                 // the caution amber
GLOBAL FUI_DIM IS "#136480".                 // a dim cyan
GLOBAL FUI_SCALES IS LIST(0.5, 1, 2, 5, 10, 20).
GLOBAL FUI_T_STEP IS 10.
GLOBAL FUI_STEPS IS LIST(1, 10, 60, 600, 3600).   // the FAIL NOW step: STEP - / STEP + walk it
GLOBAL FUI_STEPOK IS FALSE.                 // the STEP readout exists
GLOBAL FUI_STEPLB IS 0.                     // its label (top right of the FAIL NOW readout)
GLOBAL FUI_FXHOLD IS 8.                      // s a refusal stays on the fix line
GLOBAL FUI_GSLOTS IS 4.                      // the GPC slots (G1..G4 may fail, G5 too: four at most with the last good PASS GPC refused)

IF NOT (DEFINED FUI_GUI) {
    GLOBAL FUI_GUI IS 0.
    GLOBAL FUI_MADE IS FALSE.
    GLOBAL FUI_PRESS IS LIST().              // the keys' tags, taken by fuiTick
    GLOBAL FUI_KEYS IS LEXICON().            // tag -> LEXICON(b = the button, kind = its face)
    GLOBAL FUI_SCR IS LEXICON().             // screen name -> LIST(its labels)
    GLOBAL FUI_TXT IS LEXICON().             // screen name -> LIST(its drawn texts)
    GLOBAL FUI_SCHED IS FALSE.               // the MET / TIG rows run
    GLOBAL FUI_RAND IS FALSE.                // random failures
    GLOBAL FUI_SC IS 1.                      // the RAND scale's index (X1)
    GLOBAL FUI_FILT IS "ALL".                // the FILTER key
    GLOBAL FUI_B IS LEXICON("when", "MET", "t", 0, "ci", 0, "ti", 0, "vi", 0, "mi", 0).   // the builder
    GLOBAL FUI_CUR IS 0.                     // the ACTIVE cursor
    GLOBAL FUI_MSG IS "".                    // the last answer (the builder screen's third line)
    GLOBAL FUI_FXMSG IS "".                  // A refused ACTIVE-window key's words, shown on the ACTIVE screen's fix line for FUI_FXHOLD s (the builder line is not on screen in the SIMSUP layout)
    GLOBAL FUI_FXUT IS -1.                   // The UT that answer stops showing
    GLOBAL FUI_VSIG IS "".                   // The ACTIVE screen's time-dependent look (the fix countdowns, the answer, the guard) as last drawn
    GLOBAL FUI_SAY IS 0.                     // obsolete, never called (the answers stay in the failure window); the hosts' SET FUI_SAY lines are dead
    GLOBAL FUI_DIRTY IS TRUE.                // the window needs a redraw
    GLOBAL FUI_SIG IS "".                    // lib_fail's state as last saved
    GLOBAL FUI_LAST IS -1.                   // the game time of fuiTick's last call (RAND's dt)
    GLOBAL FUI_RUN IS FALSE.                 // fuiStart's trigger runs while this is TRUE
    GLOBAL FUI_NEXT IS 0.                    // the real time of the trigger's next fuiTick
    GLOBAL FUI_GMOD IS LIST().               // the GPC slots' modules (empty where the host flies no GPC failure)
    GLOBAL FUI_GVIS IS LIST().               // each slot shown (TRUE) / hidden
    GLOBAL FUI_SMOD IS 0.                    // The SET slot's module (PAIR 1-2 / PAIR 3-4 / BFS ENGAGE; DPS 04 / DPS 05), built where the host flies DPS 04
    GLOBAL FUI_SHAS IS FALSE.                // the SET slot exists
    GLOBAL FUI_SVIS IS FALSE.                // ... and is shown
    GLOBAL FUI_GSL IS LIST().                // the failed GPC number each slot stands for now (0 = none)
    GLOBAL FUI_SIM IS FALSE.                 // The DLL's SimSup latch (SIMSTATE()[0]), read at boot / ENGAGE / every 5 s: NOT a kOS flag
    GLOBAL FUI_SIMLV IS 2.                   // the DIFFICULTY key's pick (1 EASY .. 4 BRUTAL)
    GLOBAL FUI_ARM IS -1.                    // the real time ARM was pressed (-1 = not armed)
    GLOBAL FUI_GREY IS LIST().               // the widgets the latch hides (the setup modules)
    GLOBAL FUI_GR IS FALSE.                  // they are hidden now
    GLOBAL FUI_SIMFAKE IS LIST().            // a test's stand-in for the DLL (LIST(latched, difficulty, ...): the DLL counts as present)
    GLOBAL FUI_RTFAKE IS -1.                 // a test's real-time clock (>= 0)
    GLOBAL FUI_SIMRD IS -100.                // the real time SIMSTATE was last read
    GLOBAL FUI_SIMPH IS "".                  // the guidance phase last passed to the DLL (OPS 3 / 6)
    GLOBAL FUI_SIMPT IS LEXICON().           // the decision points already passed to the DLL (once each)
    GLOBAL FUI_SIMBK IS 0.                   // the sign of the last real bank command (ROLL_REV)
    GLOBAL FUI_SIMLT IS -1.                  // the game time of the last SIMTICK
}
GLOBAL FUI_ARM_S IS 10.                      // s: ENGAGE must follow ARM within this (real time)
GLOBAL FUI_DT IS 0.25.                       // s (real time) between the trigger's ticks

// ---- the builder's lists (the types the host can fly, under the FILTER)
FUNCTION fuiCodes {
    LOCAL out IS LIST().
    FOR c IN flCodes(FUI_FILT) { IF flFlyable(c) { out:ADD(c). } }
    RETURN out.
}
FUNCTION fuiCode {                           // the builder's code ("" = nothing to fail here)
    LOCAL cs IS fuiCodes().
    IF cs:LENGTH = 0 { RETURN "". }
    RETURN cs[MAX(0, MIN(cs:LENGTH - 1, FUI_B["ci"]))].
}
// RCS 04's targets are the vessel's jet names (the DLL's map, ADDONS:KALS:RCSJETS: "NAME pod manifold direction part module jet"),
// read once and kept (the jets do not change). No DLL = no names = an empty list (flFire refuses a blank target), never ALL.
GLOBAL FUI_JETS IS LIST().
FUNCTION fuiJetNames {
    IF FUI_JETS:LENGTH = 0 {
        IF ADDONS:HASSUFFIX("KALS") {
            IF ADDONS:KALS:HASSUFFIX("RCSJETS") {
                FOR t IN ADDONS:KALS:RCSJETS() { FUI_JETS:ADD(t:SPLIT(" ")[0]). }
            }
        }
    }
    RETURN FUI_JETS.
}
FUNCTION fuiTargets {                        // LIST of the code's targets ("ALL" stands for a free target)
    PARAMETER code.
    IF code = "" { RETURN LIST(). }
    IF code = "RCS 04" { RETURN fuiJetNames(). }
    IF FL_CAT[code]["free"] { RETURN LIST("ALL"). }
    RETURN FL_CAT[code]["tg"].
}
FUNCTION fuiValues {
    PARAMETER code.
    IF code = "" { RETURN LIST(). }
    RETURN FL_CAT[code]["val"].
}
FUNCTION fuiModes {                          // the modes the code offers, P first
    PARAMETER code.
    IF code = "" { RETURN LIST("P"). }
    LOCAL m IS FL_CAT[code]["modes"].
    IF m = "T" { RETURN LIST("T"). }
    IF m = "PT" { RETURN LIST("P", "T"). }
    RETURN LIST("P").
}
FUNCTION fuiPick {                           // item i of a list, wrapped; "" for an empty list
    PARAMETER ls, i.
    IF ls:LENGTH = 0 { RETURN "". }
    RETURN ls[MOD(MAX(0, i), ls:LENGTH)].
}
FUNCTION fuiTg { PARAMETER code. RETURN fuiPick(fuiTargets(code), FUI_B["ti"]). }
FUNCTION fuiVal { PARAMETER code. RETURN fuiPick(fuiValues(code), FUI_B["vi"]). }
FUNCTION fuiMode { PARAMETER code. RETURN fuiPick(fuiModes(code), FUI_B["mi"]). }
FUNCTION fuiBReset {                         // a new type: its first target / value / mode
    SET FUI_B["ti"] TO 0. SET FUI_B["vi"] TO 0. SET FUI_B["mi"] TO 0.
}

// ---- formats
FUNCTION fuiHMS {                            // seconds as M:SS, or H:MM:SS when the hours are not 0 (DISPLAY ONLY: the logs keep seconds)
    PARAMETER s.
    LOCAL n IS MAX(0, ROUND(s)).
    LOCAL h IS FLOOR(n / 3600).
    LOCAL m IS FLOOR(MOD(n, 3600) / 60).
    LOCAL x IS MOD(n, 60).
    LOCAL ss IS (CHOOSE "0" IF x < 10 ELSE "") + x.
    LOCAL mm IS (CHOOSE "0" IF m < 10 AND h > 0 ELSE "") + m.
    IF h > 0 { RETURN "" + h + ":" + mm + ":" + ss. }
    RETURN "" + m + ":" + ss.
}
FUNCTION fuiT {                              // a row's time: "MET 2:05" / "TIG +0:30" / "TIG -1:00" (display only)
    PARAMETER when, t.
    IF when = "MET" { RETURN "MET " + fuiHMS(t). }
    RETURN when + " " + (CHOOSE "+" IF t >= 0 ELSE "-") + fuiHMS(ABS(t)).
}
FUNCTION fuiStepLbl {                        // a FAIL NOW step in a key's legend: "10" under a minute, else M:SS / H:MM:SS
    PARAMETER s.
    IF s < 60 { RETURN "" + ROUND(s). }
    RETURN fuiHMS(s).
}
FUNCTION fuiStepMove {                       // STEP - / STEP +: one place along FUI_STEPS, clamped at both ends
    PARAMETER d.
    LOCAL i IS FUI_STEPS:FIND(FUI_T_STEP).
    IF i < 0 { SET i TO 1. }
    SET FUI_T_STEP TO FUI_STEPS[MAX(0, MIN(FUI_STEPS:LENGTH - 1, i + d))].
}
FUNCTION fuiRowLine {                        // one pending row on the rows screen
    PARAMETER rw.
    LOCAL s IS fuiT(rw["when"], rw["t"]) + " " + rw["code"] + " " + (CHOOSE rw["tg"] IF rw["tg"] <> "" ELSE "-").
    IF rw["val"] <> "" { SET s TO s + " " + rw["val"]. }
    SET s TO s + " " + rw["mode"].
    IF rw["done"] { SET s TO s + " " + (CHOOSE "DONE" IF rw["res"] = "OK" ELSE "NOT FIRED"). }
    RETURN s.
}
FUNCTION fuiCol {                            // text in a colour
    PARAMETER col, txt.
    RETURN "<color=" + col + ">" + txt + "</color>".
}

// ---- the keys
FUNCTION fuiTag {                            // a key's click: its tag onto the press list (each in its own call: its own number)
    PARAMETER tg.
    RETURN { FUI_PRESS:ADD(tg). }.
}
FUNCTION fuiFace {                           // the face of a key: u unlit, d dark (disabled), a amber, g green, y yellow, r red
    PARAMETER tg, kind.
    IF NOT FUI_KEYS:HASKEY(tg) { RETURN. }
    LOCAL k IS FUI_KEYS[tg].
    IF k["kind"] = kind { RETURN. }
    SET k["kind"] TO kind.
    LOCAL st IS k["b"]:STYLE.
    IF kind = "d" {
        uiStates(st, "fk_dark", "fk_dark", "fk_dark", RGB(0.54, 0.51, 0.43)).
    } ELSE IF kind = "u" {
        uiStates(st, "fk_unlit", "fk_unlit_h", "fk_unlit_p", RGB(0.07, 0.08, 0.10)).
    } ELSE {
        LOCAL nm IS "fk_" + (CHOOSE "amber" IF kind = "a" ELSE (CHOOSE "green" IF kind = "g" ELSE (CHOOSE "yellow" IF kind = "y" ELSE "red"))).
        uiStates(st, nm, nm + "_h", nm + "_p", RGB(0.10, 0.08, 0.02)).
    }
    SET k["b"]:ENABLED TO kind <> "d".
}
FUNCTION fuiKey {                            // a key in a row: legend (| = a line break), tag, its first face
    PARAMETER row, leg, tg, kind.
    LOCAL b IS row:ADDBUTTON(leg:REPLACE("|", CHAR(10))).
    SET b:STYLE:WIDTH TO FUI_KW.
    SET b:STYLE:HEIGHT TO FUI_KH.
    SET b:STYLE:HSTRETCH TO FALSE.
    uiRect(b:STYLE:BORDER, 4, 4, 4, 4).
    uiRect(b:STYLE:MARGIN, 0, 3, 0, 3).
    uiRect(b:STYLE:PADDING, 2, 2, 2, 2).
    SET b:STYLE:FONT TO UI_PANEL_FONT.
    SET b:STYLE:FONTSIZE TO 10.
    SET b:STYLE:ALIGN TO "CENTER".
    SET b:STYLE:WORDWRAP TO TRUE.
    SET b:ONCLICK TO fuiTag(tg).
    FUI_KEYS:ADD(tg, LEXICON("b", b, "kind", "")).
    fuiFace(tg, kind).
}
FUNCTION fuiKeys {                           // a module row of up to four keys: LIST(LIST(legend, tag, kind), ...)
    PARAMETER bx, ks.
    LOCAL row IS bx:ADDHLAYOUT().
    FOR k IN ks { fuiKey(row, k[0], k[1], k[2]). }
}
FUNCTION fuiModule {                         // a key module: the dark frame (9-slice, the screws in the corners)
    PARAMETER g.
    LOCAL m IS g:ADDVLAYOUT().
    SET m:STYLE:BG TO UI_PANEL_DIR + "fk_frame".
    uiRect(m:STYLE:BORDER, 6, 6, 6, 6).
    uiRect(m:STYLE:PADDING, 8, 5, 8, 5).
    RETURN m.
}
FUNCTION fuiLabel {                          // a module's label (the old words)
    PARAMETER g, txt.
    LOCAL lb IS g:ADDLABEL(txt).
    uiDispLabel(lb).
    RETURN lb.
}
FUNCTION fuiScrLabel {                      // a screen line's label (CRT style, no wrap)
    PARAMETER parent.
    LOCAL lb IS parent:ADDLABEL("").
    SET lb:STYLE:FONT TO UI_PANEL_FONT.
    SET lb:STYLE:FONTSIZE TO FUI_FS.
    SET lb:STYLE:TEXTCOLOR TO RGB(0.153, 0.663, 0.82).
    SET lb:STYLE:RICHTEXT TO TRUE.
    SET lb:STYLE:WORDWRAP TO FALSE.
    SET lb:STYLE:ALIGN TO "LEFT".
    SET lb:STYLE:HEIGHT TO FUI_ROW_H.
    SET lb:STYLE:PADDING:H TO 0. SET lb:STYLE:PADDING:V TO 0.
    SET lb:STYLE:MARGIN:H TO 0. SET lb:STYLE:MARGIN:V TO 0.
    RETURN lb.
}
FUNCTION fuiScreen {                        // a CRT glass screen of n lines: the labels, in FUI_SCR[nm]; head TRUE: line 1 also has the STEP readout at its right
    PARAMETER g, nm, n, head IS FALSE.
    LOCAL bx IS g:ADDVLAYOUT().
    SET bx:STYLE:BG TO UI_PANEL_DIR + "fk_glass".
    uiRect(bx:STYLE:BORDER, 4, 4, 4, 4).
    uiRect(bx:STYLE:PADDING, 6, 6, 4, 4).
    SET bx:STYLE:HEIGHT TO n * FUI_ROW_H + 8.
    LOCAL ls IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        IF i = 0 AND head {
            LOCAL hl IS bx:ADDHLAYOUT().
            LOCAL lt IS fuiScrLabel(hl).
            SET lt:STYLE:HSTRETCH TO TRUE.
            ls:ADD(lt).
            LOCAL st IS fuiScrLabel(hl).
            SET st:STYLE:ALIGN TO "RIGHT".
            SET st:STYLE:HSTRETCH TO FALSE.
            SET FUI_STEPLB TO st.
            SET FUI_STEPOK TO TRUE.
        } ELSE {
            ls:ADD(fuiScrLabel(bx)).
        }
    }
    FUI_SCR:ADD(nm, ls).
    LOCAL tx IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO { tx:ADD(""). }
    FUI_TXT:ADD(nm, tx).
}

// ---- the window
FUNCTION fuiInit {
    PARAMETER x IS 60, y IS 20.
    IF FUI_MADE { RETURN. }
    FUI_GREY:CLEAR().
    SET FUI_GR TO FALSE.
    LOCAL g IS 0.
    IF uiDispOn() { SET g TO uiBox("FAILURES", FUI_W, x, y). }
    ELSE { SET g TO GUI(FUI_W). SET g:X TO x. SET g:Y TO y. g:ADDLABEL("<b>FAILURES</b>"). }
    // SIMSUP: the one-way latch; the setup modules below grey out (hide) once it is latched
    fuiLabel(g, "SIMSUP").
    LOCAL mS IS fuiModule(g).
    fuiScreen(mS, "s", 2).
    fuiKeys(mS, LIST(LIST("EASY", "D1", "u"), LIST("NORMAL", "D2", "g"), LIST("HARD", "D3", "u"), LIST("BRUTAL", "D4", "u"))).
    fuiKeys(mS, LIST(LIST("ARM", "SARM", "u"), LIST("ENGAGE", "SENG", "d"))).
    // top
    LOCAL m0 IS fuiModule(g).
    FUI_GREY:ADD(m0).
    fuiKeys(m0, LIST(LIST("SCHEDULE", "SCH", "u"), LIST("RAND", "RND", "u"), LIST("MANUAL", "MAN", "g"))).
    // RAND scale
    FUI_GREY:ADD(fuiLabel(g, "RAND")).
    LOCAL m1 IS fuiModule(g).
    FUI_GREY:ADD(m1).
    fuiKeys(m1, LIST(LIST("X0.5", "SC0", "u"), LIST("X1", "SC1", "g"), LIST("X2", "SC2", "u"), LIST("X5", "SC3", "u"))).
    fuiKeys(m1, LIST(LIST("X10", "SC4", "u"), LIST("X20", "SC5", "u"))).
    // FILTER
    FUI_GREY:ADD(fuiLabel(g, "FILTER")).
    LOCAL m2 IS fuiModule(g).
    FUI_GREY:ADD(m2).
    fuiKeys(m2, LIST(LIST("ALL", "FLALL", "g"), LIST("MPS", "FLMPS", "u"), LIST("OMS", "FLOMS", "u"), LIST("RCS", "FLRCS", "u"))).
    fuiKeys(m2, LIST(LIST("FCS", "FLFCS", "u"), LIST("DPS", "FLDPS", "u"), LIST("SW", "FLSW", "u"))).
    // FAIL NOW: the builder and its keys
    FUI_GREY:ADD(fuiLabel(g, "FAIL NOW")).
    LOCAL m3 IS fuiModule(g).
    FUI_GREY:ADD(m3).
    fuiScreen(m3, "b", 3, TRUE).
    fuiKeys(m3, LIST(LIST("MET", "W0", "g"), LIST("TIG", "W1", "u"), LIST("STEP|-", "STM", "u"), LIST("STEP|+", "STP", "u"))).
    fuiKeys(m3, LIST(LIST("T -", "TM", "u"), LIST("T +", "TP", "u"), LIST("TYPE|PREV", "YP", "u"), LIST("TYPE|NEXT", "YN", "u"))).
    fuiKeys(m3, LIST(LIST("TARGET|NEXT", "GN", "u"), LIST("VALUE|NEXT", "VN", "u"), LIST("MODE|NEXT", "MN", "u"), LIST("FAIL", "FAIL", "a"))).
    // ROWS
    LOCAL m4 IS fuiModule(g).
    FUI_GREY:ADD(m4).
    fuiScreen(m4, "r", FUI_ROWS_SHOWN + 1).
    fuiKeys(m4, LIST(LIST("+", "ADD", "u"), LIST("CONFIRM", "CONF", "u"), LIST("CLEAR|ALL", "CLR", "u"))).
    // ACTIVE
    fuiLabel(g, "ACTIVE").
    LOCAL m5 IS fuiModule(g).
    fuiScreen(m5, "a", FUI_ACT_SHOWN + 1).
    fuiKeys(m5, LIST(LIST("ACTIVE|PREV", "AP", "u"), LIST("ACTIVE|NEXT", "AN", "u"), LIST("FIX", "FX", "u"))).
    // GPC: a slot per failed GPC (hidden until one has failed)
    IF FL_HAND:HASKEY("DPS 01") {
        FROM { LOCAL gs IS 0. } UNTIL gs >= FUI_GSLOTS STEP { SET gs TO gs + 1. } DO {
            LOCAL mg IS fuiModule(g).
            fuiScreen(mg, "g" + gs, 2).
            fuiKeys(mg, LIST(LIST("RE-|ASSIGN", "KR" + gs, "d"), LIST("LOAD|JOB", "KL" + gs, "d"), LIST("SWAP|SPARE", "KS" + gs, "d"), LIST("RESTART", "KT" + gs, "d"))).
            mg:HIDE().
            FUI_GMOD:ADD(mg).
            FUI_GVIS:ADD(FALSE).
            FUI_GSL:ADD(0).
        }
    }
    IF FL_HAND:HASKEY("DPS 04") {            // The SET slot: the PASS set failures' keys (one slot: a split or a PASS generic fail, never both)
        LOCAL ms IS fuiModule(g).
        fuiScreen(ms, "gs", 2).
        fuiKeys(ms, LIST(LIST("PAIR|1-2", "PA", "d"), LIST("PAIR|3-4", "PB", "d"), LIST("BFS|ENGAGE", "PF", "d"), LIST("BFS|DISP", "PD", "d"))).
        ms:HIDE().
        SET FUI_SMOD TO ms.
        SET FUI_SHAS TO TRUE.
        SET FUI_SVIS TO FALSE.
    }
    g:HIDE().
    SET FUI_GUI TO g.
    SET FUI_MADE TO TRUE.
    SET FUI_DIRTY TO TRUE.
}
FUNCTION fuiShown { RETURN FUI_MADE AND FUI_GUI:VISIBLE. }
FUNCTION fuiHide { IF FUI_MADE { FUI_GUI:HIDE(). } }
FUNCTION fuiPlace {                          // move the window (the host's "!" puts it beside its own window)
    PARAMETER x, y.
    IF FUI_MADE { SET FUI_GUI:X TO x. SET FUI_GUI:Y TO y. }
}
FUNCTION fuiToggle {                         // the host's "!" button; the window is built at the first press
    PARAMETER x IS -1, y IS -1.
    fuiInit(MAX(0, x), MAX(0, y)).
    IF FUI_GUI:VISIBLE { FUI_GUI:HIDE(). RETURN. }
    IF x >= 0 { fuiPlace(x, y). }
    SET FUI_DIRTY TO TRUE.
    fuiDraw().
    FUI_GUI:SHOW().
}
FUNCTION fuiClose {
    IF FUI_MADE { FUI_GUI:HIDE(). FUI_GUI:DISPOSE(). SET FUI_MADE TO FALSE. SET FUI_GUI TO 0. FUI_KEYS:CLEAR(). FUI_SCR:CLEAR(). FUI_TXT:CLEAR(). FUI_GMOD:CLEAR(). FUI_GVIS:CLEAR(). FUI_GSL:CLEAR(). SET FUI_SHAS TO FALSE. SET FUI_SVIS TO FALSE. FUI_GREY:CLEAR(). SET FUI_GR TO FALSE. }
    gpcClose().
}

// ---- SIMSUP (the DLL's latch; the planner is the DLL's: lib_fail's flSim*)
FUNCTION fuiRt { IF FUI_RTFAKE >= 0 { RETURN FUI_RTFAKE. } RETURN uiRt(). }
FUNCTION fuiSimHas {                         // the DLL with the SimSup suffixes is here (a test's FUI_SIMFAKE counts)
    IF FUI_SIMFAKE:LENGTH > 0 { RETURN TRUE. }
    IF FL_FAKE >= 0 OR NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("SIMLATCH").
}
FUNCTION fuiSimState {                       // SIMSTATE(): LIST(latched, difficulty, counter, fired, spare used); LIST(FALSE) without the DLL
    IF FUI_SIMFAKE:LENGTH > 0 { RETURN FUI_SIMFAKE. }
    IF NOT fuiSimHas() { RETURN LIST(FALSE). }
    IF NOT ADDONS:KALS:HASSUFFIX("SIMSTATE") { RETURN LIST(FALSE). }
    RETURN ADDONS:KALS:SIMSTATE().
}
FUNCTION fuiSimLatch {                       // the latch (TRUE the first time only)
    PARAMETER lv, seed.
    IF FUI_SIMFAKE:LENGTH > 0 {
        IF FUI_SIMFAKE[0] = TRUE { RETURN FALSE. }
        SET FUI_SIMFAKE TO LIST(TRUE, lv, 0, 0, FALSE).
        RETURN TRUE.
    }
    IF NOT fuiSimHas() { RETURN FALSE. }
    RETURN ADDONS:KALS:SIMLATCH(lv, seed).
}
FUNCTION fuiSimRead {                        // FUI_SIM from the DLL (force, or every 5 s of real time)
    PARAMETER force IS FALSE.
    LOCAL t IS fuiRt().
    IF NOT force AND t < FUI_SIMRD + 5 { RETURN. }
    SET FUI_SIMRD TO t.
    LOCAL st IS fuiSimState().
    LOCAL isOn IS st:LENGTH > 0 AND st[0] = TRUE.
    IF isOn <> FUI_SIM { SET FUI_SIM TO isOn. SET FUI_DIRTY TO TRUE. }
    IF isOn AND st:LENGTH > 1 { SET FUI_SIMLV TO MAX(1, MIN(4, ROUND(st[1]))). }
}
FUNCTION fuiSimOn { RETURN FUI_SIM. }
FUNCTION fuiSimName {
    PARAMETER lv.
    RETURN LIST("EASY", "NORMAL", "HARD", "BRUTAL")[MAX(0, MIN(3, ROUND(lv) - 1))].
}
FUNCTION fuiArmed { RETURN FUI_ARM >= 0 AND fuiRt() - FUI_ARM <= FUI_ARM_S. }
FUNCTION fuiSimEngage {                      // ENGAGE: within FUI_ARM_S of ARM; the DLL latches (once), the pending rows go, the seed is logged
    IF FUI_SIM OR NOT fuiArmed() { RETURN. }
    LOCAL lv IS FUI_SIMLV.
    LOCAL seed IS MOD(FLOOR(TIME:SECONDS * 1000), 2147483647).
    SET FUI_ARM TO -1.
    IF fuiSimLatch(lv, seed) {
        SET FUI_SIM TO TRUE.
        SET FUI_SIMRD TO fuiRt().
        IF FL_SIMFORCE <> "" { flLog("SIMSUP FORCE " + FL_SIMFORCE + ": " + flSimForce(FL_SIMFORCE)). }   // ForceAbort
        IF FL_SIMNOCODE <> "" { flLog("SIMSUP NO CODES " + FL_SIMNOCODE + ": " + flSimNoCode(FL_SIMNOCODE)). }
        flClearRows().                       // the pending manual rows go; failures that already happened stay
        SET FUI_SCHED TO FALSE.
        SET FUI_RAND TO FALSE.
        flLog("SIMSUP ENGAGED " + fuiSimName(lv) + " SEED " + seed).
        fuiSay("SIMSUP ENGAGED " + fuiSimName(lv)).
        flSave().
    } ELSE { fuiSay("SIMSUP: NOT LATCHED (ACTIVE ALREADY, OR NO DLL)"). }
}
FUNCTION fuiSimPt {                          // a decision point, once per key (the DLL plans around the edge UT; edgeUt <= 0 = now)
    PARAMETER nm, ut, key IS "".
    IF key = "" { SET key TO nm. }
    IF NOT FUI_SIM OR FUI_SIMPT:HASKEY(key) { RETURN. }
    SET FUI_SIMPT[key] TO flSimPoint(nm, ut).
}
FUNCTION fuiSimEiUt {                        // the entry interface's UT while still above it and falling, else 0 (= now)
    IF SHIP:HASSUFFIX("VERTICALSPEED") {
        IF SHIP:ALTITUDE > 122000 AND SHIP:VERTICALSPEED < -5 { RETURN TIME:SECONDS + (SHIP:ALTITUDE - 121920) / (-SHIP:VERTICALSPEED). }
    }
    RETURN 0.
}
FUNCTION fuiSimWatch {                       // each tick while latched: the guidance phase (SW 02's target) and the decision points the phase tells (OPS 3 / 6)
    IF FL_SIMPROG = "OPS3" OR FL_SIMPROG = "OPS6" { flSimVr(SHIP:VELOCITY:SURFACE:MAG). }     // The entry's pick clock runs on VR (m/s), not seconds
    IF FL_SIMPROG = "OPS1" { flSimPhase("ASCENT"). }
    ELSE IF FL_SIMPROG = "OPS2" { flSimPhase("ORBIT"). }
    ELSE IF DEFINED FLFX_PH {
        IF FLFX_PH <> "" AND FLFX_PH <> FUI_SIMPH {
            SET FUI_SIMPH TO FLFX_PH.
            flSimPhase(FLFX_PH).
            IF FLFX_PH = "ENTRY" { fuiSimPt("EI", fuiSimEiUt()). }
            IF FLFX_PH = "ENTRY" { fuiSimPt("COAST", 0). }   // COAST = the entry program's coast starts (the DLL adds its +20 s)
            ELSE IF FLFX_PH = "TAEM" { fuiSimPt("TAEM", 0). }
            ELSE IF FLFX_PH = "A/L" { fuiSimPt("HAC", 0). fuiSimPt("PREFLARE", 0). }
        }
    }
}
FUNCTION fuiSimBank {                        // the host's bank command each cycle: a sign change of a real bank (> 20 deg) is a ROLL_REV point
    PARAMETER b.
    IF NOT FUI_SIM OR ABS(b) < 20 { RETURN. }
    LOCAL sg IS CHOOSE 1 IF b > 0 ELSE -1.
    IF FUI_SIMBK = 0 { flSimPoint("ROLL_FIRST", TIME:SECONDS). }   // The first real bank command
    IF FUI_SIMBK <> 0 AND sg <> FUI_SIMBK { flSimPoint("ROLL_REV", TIME:SECONDS). }
    SET FUI_SIMBK TO sg.
}
FUNCTION fuiSimDraw {                        // the SIMSUP section's screen and keys; latched: the setup modules hidden, only the section and ACTIVE / GPC stay
    LOCAL has IS fuiSimHas().
    LOCAL lv IS FUI_SIMLV.
    IF FUI_SIM {
        IF NOT FUI_GR { FOR w IN FUI_GREY { w:HIDE(). } SET FUI_GR TO TRUE. }
        fuiSet("s", 0, fuiCol(FUI_AMB, "SIMSUP ACTIVE")).
        fuiSet("s", 1, fuiCol(FUI_DIM, fuiSimName(lv) + " - ONE WAY FOR THIS FLIGHT")).
        FOR tg IN LIST("D1", "D2", "D3", "D4", "SARM", "SENG") { fuiFace(tg, "d"). }
        RETURN.
    }
    IF FUI_GR { FOR w IN FUI_GREY { w:SHOW(). } SET FUI_GR TO FALSE. }
    FROM { LOCAL i IS 1. } UNTIL i > 4 STEP { SET i TO i + 1. } DO { fuiFace("D" + i, CHOOSE "d" IF NOT has ELSE (CHOOSE "g" IF i = ROUND(lv) ELSE "u")). }
    LOCAL armed IS fuiArmed().
    fuiFace("SARM", CHOOSE "d" IF NOT has ELSE (CHOOSE "a" IF armed ELSE "u")).
    fuiFace("SENG", CHOOSE "r" IF armed ELSE "d").
    IF NOT has {
        fuiSet("s", 0, fuiCol(FUI_DIM, "DLL NEEDED")).
        fuiSet("s", 1, "").
    } ELSE {
        fuiSet("s", 0, "DIFFICULTY " + fuiSimName(lv)).
        fuiSet("s", 1, CHOOSE fuiCol(FUI_AMB, "ARMED: ENGAGE WITHIN " + FUI_ARM_S + " S - ONE WAY") IF armed ELSE fuiCol(FUI_DIM, "ARM, THEN ENGAGE WITHIN " + FUI_ARM_S + " S")).
    }
}

// ---- drawing (only what changed)
FUNCTION fuiSet {                            // a screen's line n
    PARAMETER nm, n, txt.
    IF FUI_TXT[nm][n] = txt { RETURN. }
    SET FUI_TXT[nm][n] TO txt.
    SET FUI_SCR[nm][n]:TEXT TO txt.
}
FUNCTION fuiDraw {
    IF NOT FUI_MADE OR NOT FUI_DIRTY { RETURN. }
    SET FUI_DIRTY TO FALSE.
    fuiSimDraw().
    // the modes
    fuiFace("SCH", CHOOSE "a" IF FUI_SCHED ELSE "u").
    fuiFace("RND", CHOOSE "a" IF FUI_RAND ELSE "u").
    fuiFace("MAN", CHOOSE "g" IF NOT FUI_SCHED AND NOT FUI_RAND ELSE "u").
    FROM { LOCAL i IS 0. } UNTIL i >= FUI_SCALES:LENGTH STEP { SET i TO i + 1. } DO { fuiFace("SC" + i, CHOOSE "g" IF i = FUI_SC ELSE "u"). }
    // the filter: a group the host cannot fly anything of is dark
    FOR gk IN FL_GROUPS {
        LOCAL has IS gk = "ALL".
        IF NOT has { FOR c IN flCodes(gk) { IF flFlyable(c) { SET has TO TRUE. } } }
        fuiFace("FL" + gk, CHOOSE "d" IF NOT has ELSE (CHOOSE "g" IF gk = FUI_FILT ELSE "u")).
    }
    // the builder
    LOCAL code IS fuiCode().
    fuiFace("W0", CHOOSE "g" IF FUI_B["when"] = "MET" ELSE "u").
    fuiFace("W1", CHOOSE "g" IF FUI_B["when"] = "TIG" ELSE "u").
    LOCAL none IS code = "".
    FOR tg IN LIST("TM", "TP", "YP", "YN", "GN", "VN", "MN", "ADD") { fuiFace(tg, CHOOSE "d" IF none ELSE "u"). }
    fuiFace("STM", CHOOSE "d" IF FUI_T_STEP <= FUI_STEPS[0] ELSE "u").
    fuiFace("STP", CHOOSE "d" IF FUI_T_STEP >= FUI_STEPS[FUI_STEPS:LENGTH - 1] ELSE "u").
    IF FUI_STEPOK {
        LOCAL stl IS "STEP " + fuiStepLbl(FUI_T_STEP).
        IF FUI_STEPLB:TEXT <> stl { SET FUI_STEPLB:TEXT TO stl. }
    }
    fuiFace("FAIL", CHOOSE "d" IF none ELSE "a").
    IF none {
        fuiSet("b", 0, fuiCol(FUI_DIM, "NOTHING TO FAIL HERE")).
        fuiSet("b", 1, "").
    } ELSE {
        fuiSet("b", 0, fuiT(FUI_B["when"], FUI_B["t"]) + " " + code + " " + FL_CAT[code]["name"]).
        LOCAL tg IS fuiTg(code).
        LOCAL vl IS fuiVal(code).
        fuiSet("b", 1, (CHOOSE tg IF tg <> "" ELSE "-") + " " + (CHOOSE vl IF vl <> "" ELSE "-") + " " + fuiMode(code)).
    }
    fuiSet("b", 2, fuiCol(FUI_AMB, FUI_MSG)).
    // the rows
    LOCAL n IS FL_ROWS:LENGTH.
    FROM { LOCAL i IS 0. } UNTIL i >= FUI_ROWS_SHOWN STEP { SET i TO i + 1. } DO {
        fuiSet("r", i, CHOOSE fuiRowLine(FL_ROWS[i]) IF i < n ELSE "").
    }
    fuiSet("r", FUI_ROWS_SHOWN, fuiCol(FUI_DIM, MIN(n, FUI_ROWS_SHOWN) + " OF " + n + " ROWS")).
    fuiFace("CLR", CHOOSE "d" IF n = 0 ELSE "u").
    fuiFace("CONF", CHOOSE "d" IF flPending() = 0 ELSE "u").
    // the active list
    LOCAL act IS FL_ACTIVE:COPY.             // one snapshot for the draw: flFixTick's REMOVE (the burn's trigger, ops2q) cannot shrink it under the reads below
    LOCAL na IS act:LENGTH.
    SET FUI_CUR TO MAX(0, MIN(MAX(0, na - 1), FUI_CUR)).
    LOCAL top IS MAX(0, MIN(FUI_CUR - FUI_ACT_SHOWN + 1, na - FUI_ACT_SHOWN)).
    IF FUI_CUR < top { SET top TO FUI_CUR. }
    FROM { LOCAL i IS 0. } UNTIL i >= FUI_ACT_SHOWN STEP { SET i TO i + 1. } DO {
        LOCAL j IS top + i.
        IF j < na {
            LOCAL e IS act[j].
            fuiSet("a", i, (CHOOSE ">" IF j = FUI_CUR ELSE " ") + e["code"] + " " + (CHOOSE e["tg"] IF e["tg"] <> "" ELSE "-") + " " + e["mode"]
                + (CHOOSE " FIX... " + flFixLeft(j) + " S" IF e["fixAt"] >= 0 ELSE "")).
        } ELSE { fuiSet("a", i, (CHOOSE fuiCol(FUI_DIM, "NONE FAILED") IF na = 0 AND i = 0 ELSE "")). }
    }
    LOCAL fx IS "".
    LOCAL fxGr IS "".
    LOCAL fxBusy IS FALSE.
    IF na > 0 {
        SET fx TO flFixName(FUI_CUR).
        SET fxBusy TO act[FUI_CUR]["fixAt"] >= 0.
        IF fx <> "" AND NOT fxBusy { SET fxGr TO flFixGuard(FUI_CUR). }      // The host's rule that stops the fix NOW (the words stay on the line, the key dark)
    }
    LOCAL fxLn IS "".
    IF na > 0 {                              // The fix line: under way (seconds left) > a refusal just answered > no fix > the guard's words > the fix hint
        IF fxBusy { SET fxLn TO fuiCol(FUI_AMB, "FIX... " + fx + " " + flFixLeft(FUI_CUR) + " S"). }
        ELSE IF FUI_FXMSG <> "" AND flUt() < FUI_FXUT { SET fxLn TO fuiCol(FUI_CYAN, fuiWhy(FUI_FXMSG)). }
        ELSE IF fx = "" { SET fxLn TO fuiCol(FUI_DIM, "(NO FIX)"). }
        ELSE IF fxGr <> "" { SET fxLn TO fuiCol(FUI_CYAN, fuiWhy(fxGr)). }
        ELSE { SET fxLn TO fuiCol(FUI_AMB, "[FIX: " + fx + "]"). }
    }
    fuiSet("a", FUI_ACT_SHOWN, fxLn).
    fuiFace("AP", CHOOSE "d" IF na < 2 ELSE "u").
    fuiFace("AN", CHOOSE "d" IF na < 2 ELSE "u").
    fuiFace("FX", CHOOSE "d" IF fx = "" OR fxBusy OR fxGr <> "" ELSE "a").
    // the GPC slots: one per failed GPC, in GPC order
    IF FUI_GMOD:LENGTH > 0 {
        LOCAL fl IS gpcFailedList().
        FROM { LOCAL gs IS 0. } UNTIL gs >= FUI_GSLOTS STEP { SET gs TO gs + 1. } DO {
            IF gs < fl:LENGTH {
                LOCAL k IS fl[gs].
                SET FUI_GSL[gs] TO k.
                LOCAL st IS gpcStrip(k).
                LOCAL cn IS gpcCan(k).
                fuiSet("g" + gs, 0, st[0]).
                fuiSet("g" + gs, 1, CHOOSE fuiCol(FUI_AMB, st[1]) IF st[1] <> "" ELSE "").
                fuiFace("KR" + gs, CHOOSE "a" IF cn["ra"] ELSE "d").
                fuiFace("KL" + gs, CHOOSE "a" IF cn["lj"] ELSE "d").
                fuiFace("KS" + gs, CHOOSE "a" IF cn["ss"] ELSE "d").
                fuiFace("KT" + gs, CHOOSE "a" IF cn["rs"] ELSE "d").
                IF NOT FUI_GVIS[gs] { FUI_GMOD[gs]:SHOW(). SET FUI_GVIS[gs] TO TRUE. }
            } ELSE {
                SET FUI_GSL[gs] TO 0.
                IF FUI_GVIS[gs] { FUI_GMOD[gs]:HIDE(). SET FUI_GVIS[gs] TO FALSE. }
            }
        }
    }
    IF FUI_SHAS {                            // The SET slot: shown while a DPS 04 / DPS 05 stands
        LOCAL ss IS gpcSetStrip().
        IF ss[0] <> "" {
            LOCAL sc IS gpcSetCan().
            fuiSet("gs", 0, ss[0]).
            fuiSet("gs", 1, CHOOSE fuiCol(FUI_AMB, ss[1]) IF ss[1] <> "" ELSE "").
            fuiFace("PA", CHOOSE "a" IF sc["p1"] ELSE "d").
            fuiFace("PB", CHOOSE "a" IF sc["p2"] ELSE "d").
            fuiFace("PF", CHOOSE "a" IF sc["bf"] ELSE "d").
            fuiFace("PD", CHOOSE "a" IF sc["bd"] ELSE "d").       // BFS DISP moves the BFS to the other display
            IF NOT FUI_SVIS { FUI_SMOD:SHOW(). SET FUI_SVIS TO TRUE. }
        } ELSE IF FUI_SVIS { FUI_SMOD:HIDE(). SET FUI_SVIS TO FALSE. }
    }
}

// ---- the keys' actions
FUNCTION fuiSay {                            // an answer: the failure window's own status line (the builder screen's third line) and the log; NEVER the host's pages
    PARAMETER txt.
    SET FUI_MSG TO txt.
    flLog("UI " + txt).                      // The log keeps the answer (#fail UI ...); the host's message line never shows it
}
FUNCTION fuiAnswer {                         // lib_fail's "OK" / "REFUSE: text" / "DEFER" as a message
    PARAMETER what, ans.
    IF ans = "OK" { fuiSay(what + ": OK"). }
    ELSE IF ans:STARTSWITH("REFUSE: ") { fuiSay(ans:SUBSTRING(8, ans:LENGTH - 8)). }
    ELSE { fuiSay(what + ": " + ans). }
}
FUNCTION fuiCut {                            // A text cut to n characters
    PARAMETER t, n.
    RETURN CHOOSE t:SUBSTRING(0, n) IF t:LENGTH > n ELSE t.
}
FUNCTION fuiWhy {                            // A refusal's words as the window's reason line (40 characters): the whole text when it fits, else the clause before its first ':' (RE-IPL IN ORBIT ONLY: BFS ENGAGE UNTIL THEN -> RE-IPL IN ORBIT ONLY), else cut
    PARAMETER t.
    IF t:LENGTH <= 40 { RETURN t. }
    IF t:CONTAINS(":") {
        LOCAL c IS t:SPLIT(":")[0].
        IF c:LENGTH <= 40 { RETURN c. }
    }
    RETURN fuiCut(t, 40).
}
FUNCTION fuiActAns {                         // An ACTIVE-window key's answer (FIX, the GPC / SET keys): fuiAnswer, and a refusal ALSO on the ACTIVE screen's fix line
    PARAMETER what, ans.
    fuiAnswer(what, ans).
    IF ans:STARTSWITH("REFUSE: ") { SET FUI_FXMSG TO ans:SUBSTRING(8, ans:LENGTH - 8). SET FUI_FXUT TO flUt() + FUI_FXHOLD. }
    ELSE { SET FUI_FXMSG TO "". }
}
FUNCTION fuiViewSig {                        // What the ACTIVE screen shows that changes with time or the host's rules: each fix's seconds left, the refusal on show, the cursor entry's guard
    LOCAL s IS "".
    FROM { LOCAL k IS 0. } UNTIL k >= FL_ACTIVE:LENGTH STEP { SET k TO k + 1. } DO { SET s TO s + flFixLeft(k) + ",". }
    RETURN s + "/" + (CHOOSE 1 IF FUI_FXMSG <> "" AND flUt() < FUI_FXUT ELSE 0) + "/" + flFixGuard(FUI_CUR).
}
FUNCTION fuiDo {                             // one tag
    PARAMETER tg.
    LOCAL code IS fuiCode().
    IF tg = "SCH" { SET FUI_SCHED TO NOT FUI_SCHED. }
    ELSE IF tg = "RND" { SET FUI_RAND TO NOT FUI_RAND. }
    ELSE IF tg = "MAN" { SET FUI_SCHED TO FALSE. SET FUI_RAND TO FALSE. }
    ELSE IF tg:LENGTH = 2 AND tg:STARTSWITH("D") { IF NOT FUI_SIM { SET FUI_SIMLV TO MAX(1, MIN(4, tg:SUBSTRING(1, 1):TONUMBER(2))). SET FUI_ARM TO -1. } }
    ELSE IF tg = "SARM" { IF fuiSimHas() AND NOT FUI_SIM { SET FUI_ARM TO fuiRt(). } }
    ELSE IF tg = "SENG" { fuiSimEngage(). }
    ELSE IF tg:STARTSWITH("SC") { SET FUI_SC TO MAX(0, MIN(FUI_SCALES:LENGTH - 1, tg:SUBSTRING(2, tg:LENGTH - 2):TONUMBER(1))). }
    ELSE IF tg:STARTSWITH("FL") { SET FUI_FILT TO tg:SUBSTRING(2, tg:LENGTH - 2). SET FUI_B["ci"] TO 0. fuiBReset(). }
    ELSE IF tg = "W0" { SET FUI_B["when"] TO "MET". SET FUI_B["t"] TO MAX(0, FUI_B["t"]). }
    ELSE IF tg = "W1" { SET FUI_B["when"] TO "TIG". }
    ELSE IF tg = "STM" { fuiStepMove(-1). }
    ELSE IF tg = "STP" { fuiStepMove(1). }
    ELSE IF tg = "TM" { SET FUI_B["t"] TO FUI_B["t"] - FUI_T_STEP. IF FUI_B["when"] = "MET" { SET FUI_B["t"] TO MAX(0, FUI_B["t"]). } }
    ELSE IF tg = "TP" { SET FUI_B["t"] TO FUI_B["t"] + FUI_T_STEP. }
    ELSE IF tg = "YP" OR tg = "YN" {
        LOCAL n IS fuiCodes():LENGTH.
        IF n > 0 { SET FUI_B["ci"] TO MOD(MIN(FUI_B["ci"], n - 1) + n + (CHOOSE 1 IF tg = "YN" ELSE -1), n). }
        fuiBReset().
    }
    ELSE IF tg = "GN" { SET FUI_B["ti"] TO FUI_B["ti"] + 1. }
    ELSE IF tg = "VN" { SET FUI_B["vi"] TO FUI_B["vi"] + 1. }
    ELSE IF tg = "MN" { SET FUI_B["mi"] TO FUI_B["mi"] + 1. }
    ELSE IF tg = "FAIL" {
        IF code <> "" {
            LOCAL sw IS flSimCheck(code, fuiTg(code), fuiMode(code)).      // a pilot's own failure: let through, the floor it breaks said
            fuiAnswer(flName(code, fuiTg(code)), flFire(code, fuiTg(code), fuiVal(code), fuiMode(code), "CREW")).
            IF sw <> "" { SET FUI_MSG TO FUI_MSG + " " + sw. }
        }
    }
    ELSE IF tg = "ADD" {
        IF code <> "" {
            LOCAL sw IS flSimCheck(code, fuiTg(code), fuiMode(code)).      // RTN IMPSBLE on the row, the row let through
            fuiAnswer("ROW", flAddRow(FUI_B["when"], FUI_B["t"], code, fuiTg(code), fuiVal(code), fuiMode(code))).
            IF sw <> "" { SET FUI_MSG TO FUI_MSG + " " + sw. }
        }
    }
    ELSE IF tg = "CONF" {
        IF flPending() > 0 { SET FUI_SCHED TO TRUE. fuiSay("SCHEDULE ON: " + flPending() + " ROW" + (CHOOSE "S" IF flPending() <> 1 ELSE "")). fuiHide(). }
    }
    ELSE IF tg = "CLR" { flClearRows(). fuiSay("ROWS CLEARED"). }
    ELSE IF tg = "AP" { SET FUI_CUR TO MAX(0, FUI_CUR - 1). }
    ELSE IF tg = "AN" { SET FUI_CUR TO MIN(MAX(0, FL_ACTIVE:LENGTH - 1), FUI_CUR + 1). }
    ELSE IF tg = "FX" { fuiActAns("FIX", flFix(FUI_CUR)). }
    ELSE IF tg = "PA" { fuiActAns("PAIR 1-2", gpcPair(1)). }          // The SET slot's keys
    ELSE IF tg = "PB" { fuiActAns("PAIR 3-4", gpcPair(2)). }
    ELSE IF tg = "PF" { fuiActAns("BFS ENGAGE", gpcBfsEngage()). }
    ELSE IF tg = "PD" { fuiActAns("BFS DISP", gpcBfsMove("")). }
    ELSE IF tg:LENGTH = 3 AND tg:STARTSWITH("K") {          // a GPC slot's key: K + R / L / S / T + the slot
        LOCAL gsl IS tg:SUBSTRING(2, 1):TONUMBER(-1).
        IF gsl >= 0 AND gsl < FUI_GSL:LENGTH {
            LOCAL gk IS FUI_GSL[gsl].
            LOCAL gw IS tg:SUBSTRING(1, 1).
            IF gk > 0 {
                IF gw = "R" { fuiActAns("RE-ASSIGN G" + gk, gpcReassign(gk)). }
                ELSE IF gw = "L" { fuiActAns("LOAD JOB G" + gk, gpcLoadJob(gk)). }
                ELSE IF gw = "S" { fuiActAns("SWAP SPARE G" + gk, gpcSwapSpare(gk)). }
                ELSE IF gw = "T" { fuiActAns("RESTART G" + gk, gpcRestart(gk)). }
            }
        }
    }
    SET FUI_DIRTY TO TRUE.
}
FUNCTION fuiPoll {                           // the keys' tags taken (cheap with none)
    UNTIL FUI_PRESS:LENGTH = 0 {
        LOCAL tg IS FUI_PRESS[0].
        FUI_PRESS:REMOVE(0).
        fuiDo(tg).
    }
}

// ---- the host's calls
FUNCTION fuiBoot {                           // at the host's start: the failure state of an earlier program back (reset = a new flight: none)
    PARAMETER reset IS FALSE.
    IF reset { flReset(). flfxReset(). } ELSE { flLoad(). }
    SET FUI_SIG TO "".
    fuiSimRead(TRUE).                        // The DLL's latch (a restart, a new program, a scene change cannot clear it)
}
// ONE trigger for the host's life, for a program with blocking loops (ops3q): fuiTick every FUI_DT s of real time, through everything
FUNCTION fuiStart {
    IF FUI_RUN { RETURN. }
    SET FUI_RUN TO TRUE.
    WHEN TRUE THEN {
        IF FUI_RUN AND uiRt() >= FUI_NEXT {
            SET FUI_NEXT TO (FLOOR((uiRt() + 0.005) / FUI_DT) + 1) * FUI_DT - 0.005.   // A fixed grid, no drift
            fuiTick(MISSIONTIME, FL_NOTIG, TRUE).   // randOk TRUE (RAND and SimSup's random-time picks run in OPS 3 / 6 now; was FALSE)
        }
        RETURN FUI_RUN.
    }
}
FUNCTION fuiStop { SET FUI_RUN TO FALSE. fuiClose(). }
FUNCTION fuiHas { RETURN FL_HAND:LENGTH > 0. }          // the host registered something to fail: its "!" button is worth showing
FUNCTION fuiSchedOn { RETURN FUI_SCHED. }
FUNCTION fuiRandOn { RETURN FUI_RAND. }
FUNCTION fuiRandScale { RETURN FUI_SCALES[FUI_SC]. }
FUNCTION fuiSig { RETURN FL_ACTIVE:LENGTH + "/" + FL_ROWS:LENGTH + "/" + flPending() + "/" + FUI_SCHED + FUI_RAND + FUI_SIM + (CHOOSE "/" + gpcSigNow() IF FUI_GMOD:LENGTH > 0 ELSE ""). }
// each loop of the host: the keys, the schedule (SCHEDULE on: the rows due fire; the fixes always complete), RAND (randOk = the host
// allows a random draw now: ops2q only in a burn), the redraw, the state saved when it changed. met = s since launch (a row's MET),
// tig = s from the burn's ignition (FL_NOTIG = none). Returns the number of rows fired. fuiSched = its schedule + RAND part alone.
FUNCTION fuiSched {                          // the schedule and RAND alone (a trigger's call: no window work)
    PARAMETER met, tig IS FL_NOTIG, randOk IS TRUE.
    LOCAL n IS 0.
    IF FUI_SIM {                             // SIMSUP is latched: the DLL's planner picks; no rows, no RAND (the fixes still complete)
        SET FUI_SCHED TO FALSE.
        SET FUI_RAND TO FALSE.
        flFixTick().
        flfxTick().
        fuiSimWatch().
        LOCAL tu IS flUt().
        IF FUI_SIMLT < 0 { SET FUI_SIMLT TO tu. }
        IF tu - FUI_SIMLT >= 0.1 {
            IF flSimTick(tig, randOk, MIN(1, tu - FUI_SIMLT)) <> "" { SET n TO 1. }
            SET FUI_SIMLT TO tu.
        }
        SET FUI_LAST TO tu.
        RETURN n.
    }
    IF FUI_SCHED { SET n TO flTick(met, tig). } ELSE { flFixTick(). }
    flfxTick().                              // The caps / locks / RCS / frozen surfaces held (every FLFX_DT s)
    LOCAL now IS flUt().
    IF FUI_RAND AND randOk {
        IF FUI_LAST >= 0 AND now > FUI_LAST { flRand(FUI_SCALES[FUI_SC], MIN(1, now - FUI_LAST)). }
    }
    SET FUI_LAST TO now.
    RETURN n.
}
FUNCTION fuiTick {
    PARAMETER met, tig IS FL_NOTIG, randOk IS TRUE, sched IS TRUE.   // sched FALSE: the schedule is run elsewhere (ops2q's trigger in a burn)
    fuiSimRead().
    IF FUI_ARM >= 0 AND NOT fuiArmed() { SET FUI_ARM TO -1. SET FUI_DIRTY TO TRUE. }   // ARM timed out (ENGAGE within FUI_ARM_S or nothing happens)
    fuiPoll().
    LOCAL n IS 0.
    IF sched { SET n TO fuiSched(met, tig, randOk). }
    gpcTick().                               // the displays' dead / frozen / live looks, the GPC tasks (lib_gpc)
    LOCAL sg IS fuiSig().
    IF sg <> FUI_SIG { SET FUI_SIG TO sg. SET FUI_DIRTY TO TRUE. flSave(). }
    LOCAL vs IS fuiViewSig().                // A fix countdown / an answer timing out / a guard lifting redraws (no save: nothing of lib_fail's state changed)
    IF vs <> FUI_VSIG { SET FUI_VSIG TO vs. SET FUI_DIRTY TO TRUE. }
    IF FUI_DIRTY { fuiDraw(). }
    RETURN n.
}
