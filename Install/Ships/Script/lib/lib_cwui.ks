@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_CWUI.KS  --  the CAUTION & WARNING panel's window (kOS GUI) and tone. The state is lib_cw.ks's.
// ============================================================================
//  OUR panel look (lib_guistyle: uiDispSkin / uiDispTitle, the gp_* sprites): a title bar with the MASTER ALARM button in it
//  (flashing red until it is pressed; the press acknowledges; dark when quiet), the 12 lamps in a 4 x 3 grid (dark with a dim
//  legend, backlit amber CAUT / red WARN), the fault rows in ops2q's display box (a black screen, a green rim, DejaVu Sans Mono
//  Bold 14, green #3ce03c; a new row in its class colour, an acknowledged one back to green), and MSG RESET + HIDE. No LOG
//  footer. The window is built at the first fault and shown only while lib_cw's CW_VIS is TRUE (a CAUTION or WARNING raises it;
//  HIDE lowers it; the next fault reopens it).
//  The tones (the real Shuttle classes, from NASA's published spec): CLASS 2 = every C&W lamp, caution and warning alike:
//  400 Hz for 0.4 s then 1024 Hz for 0.4 s, repeating, from the first unacknowledged fault until the MASTER ALARM press; CLASS 3 =
//  SM ALERT (cwuiAlert(): a software alert, no lamp, no master alarm): a steady 512 Hz for 1 s. No klaxon, no siren (a siren is
//  for a fire failure, which does not exist yet). Played from the sound files GameData/KALS_CW/Sounds/cw_class2.wav / cw_class3.wav
//  through ADDONS:KALS:SNDPLAY (the DLL's audio); without that suffix or a file the same notes come from kOS voice 1 (the host's
//  beeps keep voice 0). Timed on the real clock (uiRt), not game time.
//  The window opens at 77.5 % across / 14 % down of the screen (lib_screen's size; 3840x2160 without it) in every program,
//  unless the player moved it: a move is saved to 0:/cw_pos.json and the next program opens there.
//  The host calls cwuiStart() once (a WHEN TRUE trigger runs cwuiTick and cwTick every physics tick, through every blocking
//  stretch of the program; cheap: it does work only when the state, the flash phase or a check is due), or its own loop calls
//  cwuiTick().
//  Needs lib_guistyle.ks and lib_cw.ks. No vessel, no host globals.
// ============================================================================
RUNONCEPATH("0:/lib/lib_guistyle.ks").
RUNONCEPATH("0:/lib/lib_cw.ks").
RUNONCEPATH("0:/lib/lib_cwchk.ks").            // the GPC cycle check runs from the trigger below
RUNONCEPATH("0:/lib/lib_screen.ks").           // SCR_W / SCR_H: the default place scales with the screen

GLOBAL CWUI_W IS 352.                        // px wide
GLOBAL CWUI_FX IS 0.775.                     // The default place as a fraction of the screen (the project owner's pick, 11-08 11:21) ...
GLOBAL CWUI_FY IS 0.14.                      // ... 77.5 % across, 14 % down (a 3840 x 2160 screen: x 2976, y 302)
GLOBAL CWUI_X IS ROUND(CWUI_FX * SCR_W).     // px: the default place (the saved move overrides it)
GLOBAL CWUI_Y IS ROUND(CWUI_FY * SCR_H).
GLOBAL CWUI_POS_FILE IS "0:/cw_pos.json".    // where a move by the player is kept for the next program
GLOBAL CWUI_MOVE_S IS 2.                     // s a moved window must stand still before it is saved
GLOBAL CWUI_LAMP_H IS 22.                    // px: a lamp is one line (about half the height of draft 3)
GLOBAL CWUI_ROW_H IS 22.                     // px: a fault row (18 -> 22, more line spacing in the readout)
GLOBAL CWUI_MSG_W IS 28.                     // characters of a message on a row (the log has the whole line)
GLOBAL CWUI_FONT IS "DejaVu Sans Mono Bold". // ops2q's display font ...
GLOBAL CWUI_FS IS 14.                        // ... and size
GLOBAL CWUI_GREEN IS "#3ce03c".              // the display green
GLOBAL CWUI_RED IS "#ff4a4a".                // a WARNING row (bright on the black screen)
GLOBAL CWUI_AMBER IS "#f2c14e".              // a CAUTION row (UI_ACCENT)
GLOBAL CWUI_HZ_LO IS 400.                    // class 2 (C&W, every lamp): 400 Hz ...
GLOBAL CWUI_HZ_HI IS 1024.                   // ... then 1024 Hz, 0.4 s each, repeating until the MASTER ALARM press
GLOBAL CWUI_HZ_STEP IS 0.4.
GLOBAL CWUI_HZ_SM IS 512.                    // class 3 (SM ALERT): a steady 512 Hz for 1 s
GLOBAL CWUI_SM_S IS 1.
GLOBAL CWUI_VOL IS 1.                        // the kOS voice's volume, the fallback without the DLL (was 0.5)
GLOBAL CW_SND_VOL IS 0.5.                    // The DLL sound's level 0..1 (ADDONS:KALS:SNDVOL; KSP's master slider applies on top); trim it in flight
GLOBAL CWUI_SND_C2 IS "cw_class2".           // the sound files (GameData/KALS_CW/Sounds/<name>.wav)
GLOBAL CWUI_SND_C3 IS "cw_class3".

IF NOT (DEFINED cwuiGui) {
    GLOBAL cwuiGui IS 0.
    GLOBAL cwuiMade IS FALSE.
    GLOBAL cwuiShown IS FALSE.
    GLOBAL cwuiLamps IS LIST().              // the 12 lamp labels
    GLOBAL cwuiRows IS LIST().               // the fault rows' labels
    GLOBAL cwuiMaster IS 0.                  // the MASTER ALARM button
    GLOBAL cwuiSm IS 0.                      // the SM ALERT light (a label like a lamp)
    GLOBAL cwuiSmTxt IS 0.                   // the software alert's message line, beside the light
    GLOBAL cwuiSmSeq IS 0.                   // CW_SMSEQ sounded: a higher CW_SMSEQ = a new software alert = the class 3 tone once
    GLOBAL cwuiPress IS LIST().              // the buttons' tags, taken by cwuiTick (a click never edits the state itself)
    GLOBAL cwuiVer IS -1.                    // CW_VER drawn
    GLOBAL cwuiPh IS -1.                     // the master's phase drawn: 0 dark, 1 lit, 2 off-phase of a flash
    GLOBAL cwuiToneAt IS 0.                  // the real time of the next class 2 pair (the kOS voice's fallback)
    GLOBAL cwuiSndOn IS FALSE.               // the class 2 loop is playing through the DLL
    GLOBAL cwuiSndBad IS FALSE.              // the DLL could not play a file: the kOS voice does the tones
    GLOBAL cwuiSndLogged IS FALSE.           // the DLL sound level has been written to the log once
    GLOBAL cwuiPX IS -1.                     // the window's place as last seen (a change = the player dragged it)
    GLOBAL cwuiPY IS -1.
    GLOBAL cwuiMovedAt IS -1.                // the real time the place last changed, -1 = nothing waiting to be saved
    GLOBAL cwuiVoice IS 0.
    GLOBAL cwuiRun IS FALSE.                 // the host's trigger (cwuiStart) keeps ticking while this is TRUE
    GLOBAL cwuiGpc IS LEXICON().             // cwGpcStep's clocks (the GPC lamp: a cycle overrun)
}

FUNCTION cwuiTag {                           // a button's tag onto the press list (each in its own call: its own number)
    PARAMETER tg.
    RETURN { cwuiPress:ADD(tg). }.
}

FUNCTION cwuiHms {                           // MET s -> "HH:MM:SS" (a sign for before zero; 99 h cap)
    PARAMETER t.
    LOCAL a IS ABS(ROUND(t)).
    LOCAL h IS MIN(99, FLOOR(a / 3600)).
    LOCAL m IS FLOOR(MOD(a, 3600) / 60).
    LOCAL s IS MOD(a, 60).
    RETURN (CHOOSE "-" IF t < 0 ELSE "") + (CHOOSE "0" IF h < 10 ELSE "") + h + ":" + (CHOOSE "0" IF m < 10 ELSE "") + m + ":" + (CHOOSE "0" IF s < 10 ELSE "") + s.
}
FUNCTION cwuiPad {                           // txt cut / padded to n characters
    PARAMETER txt, n.
    LOCAL s IS txt.
    IF s:LENGTH > n { SET s TO s:SUBSTRING(0, n). }
    UNTIL s:LENGTH >= n { SET s TO s + " ". }
    RETURN s.
}
FUNCTION cwuiRowText {                       // one fault row: the class letter, the message, the MET; colour by its state
    PARAMETER rw.
    LOCAL col IS CWUI_GREEN.
    IF NOT rw[3] { SET col TO CHOOSE CWUI_RED IF rw[0] = "W" ELSE CWUI_AMBER. }
    RETURN "<color=" + col + ">" + rw[0] + " " + cwuiPad(rw[1], CWUI_MSG_W) + " " + cwuiHms(rw[2]) + "</color>".
}

FUNCTION cwuiLampStyle {                     // a lamp label's face for the class cls ("" dark, "C" amber, "W" red)
    PARAMETER lb, cls.
    IF cls = "W" {
        SET lb:STYLE:BG TO UI_PANEL_DIR + "cw_lamp_w".
        SET lb:STYLE:TEXTCOLOR TO RGB(1, 1, 1).
    } ELSE IF cls = "C" {
        SET lb:STYLE:BG TO UI_PANEL_DIR + "cw_lamp_c".
        SET lb:STYLE:TEXTCOLOR TO UI_ON_RGB.
    } ELSE {
        SET lb:STYLE:BG TO UI_PANEL_DIR + "gp_btn_act".
        SET lb:STYLE:TEXTCOLOR TO RGB(0.40, 0.42, 0.45).
    }
}

// a move the player made in an earlier program (cw_pos.json = x, y in screen px; one that would put the window off the screen is ignored)
FUNCTION cwuiLoadPos {
    IF NOT EXISTS(CWUI_POS_FILE) { RETURN. }
    LOCAL pj IS READJSON(CWUI_POS_FILE).
    IF NOT (pj:HASKEY("x") AND pj:HASKEY("y")) { RETURN. }
    LOCAL px IS pj["x"]. LOCAL py IS pj["y"].
    IF px < 0 OR py < 0 OR px > SCR_W - 100 OR py > SCR_H - 100 { RETURN. }
    SET CWUI_X TO px. SET CWUI_Y TO py.
}
// the player's drag: the window's place differs from the last one seen -> wait CWUI_MOVE_S still, then save it
FUNCTION cwuiWatchPos {
    PARAMETER rt.
    LOCAL gx IS ROUND(cwuiGui:X). LOCAL gy IS ROUND(cwuiGui:Y).
    IF ABS(gx - cwuiPX) > 2 OR ABS(gy - cwuiPY) > 2 {
        SET cwuiPX TO gx. SET cwuiPY TO gy. SET cwuiMovedAt TO rt.
    } ELSE IF cwuiMovedAt >= 0 AND rt - cwuiMovedAt >= CWUI_MOVE_S {
        SET cwuiMovedAt TO -1.
        SET CWUI_X TO cwuiPX. SET CWUI_Y TO cwuiPY.
        WRITEJSON(LEXICON("x", cwuiPX, "y", cwuiPY), CWUI_POS_FILE).
    }
}

FUNCTION cwuiInit {
    IF cwuiMade { RETURN. }
    cwuiLoadPos().
    LOCAL g IS GUI(CWUI_W).
    SET g:X TO CWUI_X. SET g:Y TO CWUI_Y.
    SET cwuiPX TO CWUI_X. SET cwuiPY TO CWUI_Y.
    IF uiDispOn() {
        uiDispSkin(g).
        // kOS's window padding is 8 left / 6 right (measured on the test harness's 4K shots: the title and screen rows 7 | 5 grey px,
        // the lamp rows 11 | 9): 7 + 7 keeps the window's width and puts the same grey gap on both sides
        SET g:STYLE:PADDING:LEFT TO 7.
        SET g:STYLE:PADDING:RIGHT TO 7.
    }
    // the title bar with the MASTER ALARM button in it
    LOCAL th IS g:ADDHLAYOUT().
    LOCAL tl IS th:ADDLABEL("<b>CAUTION / WARNING</b>").
    uiDispTitle(th, tl).
    SET tl:STYLE:HSTRETCH TO TRUE.
    SET cwuiMaster TO th:ADDBUTTON("MASTER ALARM").
    SET cwuiMaster:STYLE:WIDTH TO 120.
    SET cwuiMaster:STYLE:HEIGHT TO 22.
    SET cwuiMaster:ONCLICK TO cwuiTag("MA").
    // the lamps, 4 x 3, one line each
    SET cwuiLamps TO LIST().
    LOCAL lw IS (CWUI_W - 12 - 3 * 4) / 4.
    FROM { LOCAL lr IS 0. } UNTIL lr >= 3 STEP { SET lr TO lr + 1. } DO {
        LOCAL rw IS g:ADDHLAYOUT().
        FROM { LOCAL lc IS 0. } UNTIL lc >= 4 STEP { SET lc TO lc + 1. } DO {
            LOCAL lb IS rw:ADDLABEL(CW_LBL[lr * 4 + lc]).
            SET lb:STYLE:WIDTH TO lw. SET lb:STYLE:HEIGHT TO CWUI_LAMP_H.
            SET lb:STYLE:FONT TO UI_PANEL_FONT. SET lb:STYLE:FONTSIZE TO UI_DISP_PT.
            SET lb:STYLE:ALIGN TO "CENTER".
            uiRect(lb:STYLE:BORDER, 2, 2, 2, 2).
            uiRect(lb:STYLE:PADDING, 0, 0, 0, 0).
            cwuiLampStyle(lb, "").
            cwuiLamps:ADD(lb).
            IF lr = 2 { SET lb:STYLE:MARGIN:BOTTOM TO 0. }   // The last lamp row has no bottom margin
        }
        IF lr = 2 { SET rw:STYLE:MARGIN:BOTTOM TO 0. }      // so the SM ALERT row's own top margin (6) is the whole gap above it
    }
    // the SM ALERT line: the light (a lamp's size) and the latest software alert's text beside it
    LOCAL sr IS g:ADDHLAYOUT().
    uiRect(sr:STYLE:MARGIN, 0, 0, 6, 6).     // A 6 px gap above the SM ALERT row (it sat tight under the lamp grid); T1005: and 6 below it (the readout box's own bottom margin did not show, the fault screen touched the row)
    SET cwuiSm TO sr:ADDLABEL("SM ALERT").
    SET cwuiSm:STYLE:WIDTH TO lw. SET cwuiSm:STYLE:HEIGHT TO CWUI_LAMP_H.
    SET cwuiSm:STYLE:FONT TO UI_PANEL_FONT. SET cwuiSm:STYLE:FONTSIZE TO UI_DISP_PT.
    SET cwuiSm:STYLE:ALIGN TO "CENTER".
    uiRect(cwuiSm:STYLE:BORDER, 2, 2, 2, 2).
    uiRect(cwuiSm:STYLE:PADDING, 0, 0, 0, 0).
    uiRect(cwuiSm:STYLE:MARGIN, 0, 0, 0, 0).   // The inherited margin pushed the lamp text down: zero
    cwuiLampStyle(cwuiSm, "").
    // The software alert's text in its own small readout box (the fault screen's style: black, green rim); dark and
    // empty when no alert (cwuiDraw writes "")
    LOCAL sb IS sr:ADDVLAYOUT().
    SET sb:STYLE:BG TO UI_PANEL_DIR + "cw_screen".
    uiRect(sb:STYLE:BORDER, 8, 8, 8, 8).
    uiRect(sb:STYLE:PADDING, 6, 6, 0, 0).
    uiRect(sb:STYLE:MARGIN, 0, 0, 0, 6).     // The readout box level with the lamp (top 0) and a 6 px gap above the fault screen (the rims touched)
    SET sb:STYLE:HSTRETCH TO TRUE.
    SET sb:STYLE:HEIGHT TO CWUI_LAMP_H.
    SET cwuiSmTxt TO sb:ADDLABEL("").
    SET cwuiSmTxt:STYLE:FONT TO CWUI_FONT. SET cwuiSmTxt:STYLE:FONTSIZE TO CWUI_FS.
    SET cwuiSmTxt:STYLE:RICHTEXT TO TRUE.
    SET cwuiSmTxt:STYLE:WORDWRAP TO FALSE.
    SET cwuiSmTxt:STYLE:ALIGN TO "LEFT".
    SET cwuiSmTxt:STYLE:HSTRETCH TO TRUE.
    uiRect(cwuiSmTxt:STYLE:PADDING, 0, 0, 0, 0).   // The text takes the box height (no inherited padding): centred like the lamp label
    uiRect(cwuiSmTxt:STYLE:MARGIN, 0, 0, 0, 0).    // The inherited margin pushed the text down: zero (a border does not offset content; a margin does)
    SET cwuiSmTxt:STYLE:HEIGHT TO CWUI_LAMP_H.      // 22 = the box height, so the text centre = the box centre = the lamp centre
    // the fault screen: ops2q's display box
    LOCAL bx IS g:ADDVLAYOUT().
    SET bx:STYLE:BG TO UI_PANEL_DIR + "cw_screen".
    uiRect(bx:STYLE:BORDER, 8, 8, 8, 8).     // The 24 x 24 sprite (tools/gen_cw_screen.py): circular r 8 corners, transparent outside the rim; the 8 x 8 centre is plain black, so the stretched centre never blends the rim in (the glow)
    uiRect(bx:STYLE:PADDING, 6, 6, 4, 4).
    SET bx:STYLE:MARGIN:TOP TO 0.               // The fault screen's top margin 0, so the gap below the SM ALERT row is the box's bottom margin (6) alone
    SET bx:STYLE:HEIGHT TO CW_MAXROWS * CWUI_ROW_H + 8.
    SET cwuiRows TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= CW_MAXROWS STEP { SET i TO i + 1. } DO {
        LOCAL lb IS bx:ADDLABEL("").
        SET lb:STYLE:FONT TO CWUI_FONT. SET lb:STYLE:FONTSIZE TO CWUI_FS.
        SET lb:STYLE:TEXTCOLOR TO RGB(60 / 255, 224 / 255, 60 / 255).
        SET lb:STYLE:RICHTEXT TO TRUE.
        SET lb:STYLE:WORDWRAP TO FALSE.
        SET lb:STYLE:ALIGN TO "LEFT".
        SET lb:STYLE:HEIGHT TO CWUI_ROW_H.
        SET lb:STYLE:PADDING:H TO 0. SET lb:STYLE:PADDING:V TO 0.
        SET lb:STYLE:MARGIN:H TO 0. SET lb:STYLE:MARGIN:V TO 0.
        cwuiRows:ADD(lb).
    }
    // MSG RESET + HIDE
    LOCAL br IS g:ADDHLAYOUT().
    LOCAL b1 IS br:ADDBUTTON("MSG RESET").
    SET b1:ONCLICK TO cwuiTag("MR").
    LOCAL b2 IS br:ADDBUTTON("HIDE").
    SET b2:ONCLICK TO cwuiTag("HD").
    g:HIDE().
    SET cwuiGui TO g.
    SET cwuiMade TO TRUE.
    SET cwuiVer TO -1. SET cwuiPh TO -1.
}

FUNCTION cwuiDraw {                          // the lamps and the rows from lib_cw's state
    FROM { LOCAL i IS 0. } UNTIL i >= 12 STEP { SET i TO i + 1. } DO { cwuiLampStyle(cwuiLamps[i], cwLampCls(CW_KEYS[i])). }
    cwuiLampStyle(cwuiSm, CHOOSE "C" IF CW_SM ELSE "").
    SET cwuiSmTxt:TEXT TO CHOOSE ("<color=" + CWUI_AMBER + ">" + cwuiPad(CW_SMTXT, CWUI_MSG_W) + "</color>") IF CW_SM ELSE "".

    FROM { LOCAL i IS 0. } UNTIL i >= CW_MAXROWS STEP { SET i TO i + 1. } DO {
        IF i < CW_ROWS:LENGTH { SET cwuiRows[i]:TEXT TO cwuiRowText(CW_ROWS[i]). } ELSE { SET cwuiRows[i]:TEXT TO "". }
    }
    SET cwuiVer TO CW_VER.
}

FUNCTION cwuiMasterDraw {                    // the MASTER ALARM button: dark when quiet, flashing red while it waits for a press
    PARAMETER rt.
    LOCAL ph IS 0.
    IF cwMaster() <> "" { SET ph TO CHOOSE 1 IF cwFlash(rt) ELSE 2. }
    IF ph = cwuiPh { RETURN. }
    SET cwuiPh TO ph.
    LOCAL st IS cwuiMaster:STYLE.
    IF ph = 1 {
        uiStates(st, "cw_master_on", "cw_master_on", "cw_master_on", RGB(1, 1, 1)).
    } ELSE IF ph = 2 {
        uiStates(st, "cw_master_off", "cw_master_off", "cw_master_off", RGB(0.75, 0.45, 0.45)).
    } ELSE {
        uiStates(st, "gp_btn_act", "gp_btn_act", "gp_btn_act", RGB(0.40, 0.42, 0.45)).
    }
}

// ---- the tones ----
FUNCTION cwuiHasSnd {
    IF cwuiSndBad { RETURN FALSE. }
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    RETURN ADDONS:KALS:AVAILABLE AND ADDONS:KALS:HASSUFFIX("SNDPLAY").
}
FUNCTION cwuiVoiceGet {
    IF NOT cwuiVoice:HASSUFFIX("PLAY") { SET cwuiVoice TO GETVOICE(1). }
    RETURN cwuiVoice.
}
// play a sound file (loop or once); FALSE = the DLL has no such file / suffix: the kOS voice has to do it
FUNCTION cwuiSndPlay {
    PARAMETER nm, lp.
    IF NOT cwuiHasSnd() { RETURN FALSE. }
    // only a trim is sent: the DLL's own default is 0.5 = CW_SND_VOL's, so an old DLL + this script plays exactly as before
    IF CW_SND_VOL <> 0.5 AND ADDONS:KALS:HASSUFFIX("SNDVOL") { ADDONS:KALS:SNDVOL(MAX(0, MIN(1, CW_SND_VOL))). }
    IF NOT ADDONS:KALS:SNDPLAY(nm, lp) { SET cwuiSndBad TO TRUE. RETURN FALSE. }
    IF NOT cwuiSndLogged {
        SET cwuiSndLogged TO TRUE.
        IF DEFINED KM_LOG { IF KM_LOG <> "" AND SOCK_LOG { LOG ROUND(cwUt(), 1) + " [S] C&W SND vol " + ROUND(MAX(0, MIN(1, CW_SND_VOL)), 2) TO KM_LOG. } }
    }
    RETURN TRUE.
}
FUNCTION cwuiSndQuiet {                      // every tone off (the press, HIDE, the close)
    IF cwuiSndOn { SET cwuiSndOn TO FALSE. IF cwuiHasSnd() { ADDONS:KALS:SNDSTOP(CWUI_SND_C2). } }
    IF cwuiHasSnd() { ADDONS:KALS:SNDSTOP(CWUI_SND_C3). }
    IF cwuiVoice:HASSUFFIX("STOP") { cwuiVoice:STOP(). }
}
// CLASS 3, the SM ALERT tone: a steady 512 Hz for 1 s, once per software alert (cwuiTick plays it when lib_cw's CW_SMSEQ rose).
FUNCTION cwuiAlert {
    IF cwuiSndPlay(CWUI_SND_C3, FALSE) { RETURN. }
    cwuiVoiceGet():PLAY(NOTE(CWUI_HZ_SM, CWUI_SM_S, CWUI_SM_S, CWUI_VOL)).
}
// CLASS 2, every C&W lamp: 400 / 1024 Hz alternating until the MASTER ALARM press (the file loops in the DLL; the kOS voice is
// given one 0.8 s pair at a time)
FUNCTION cwuiTone {
    PARAMETER rt.
    LOCAL m IS cwMaster().
    IF m = "" { IF cwuiSndOn { cwuiSndQuiet(). } RETURN. }
    IF cwuiSndOn { RETURN. }
    IF NOT cwuiSndBad AND cwuiSndPlay(CWUI_SND_C2, TRUE) { SET cwuiSndOn TO TRUE. RETURN. }
    IF rt < cwuiToneAt { RETURN. }
    cwuiVoiceGet():PLAY(LIST(NOTE(CWUI_HZ_LO, CWUI_HZ_STEP, CWUI_HZ_STEP, CWUI_VOL), NOTE(CWUI_HZ_HI, CWUI_HZ_STEP, CWUI_HZ_STEP, CWUI_VOL))).
    SET cwuiToneAt TO rt + 2 * CWUI_HZ_STEP.
}

// the host's loop: the buttons, the window's visibility, the redraw, the flash, the tone
FUNCTION cwuiTick {
    UNTIL cwuiPress:LENGTH = 0 {
        LOCAL tg IS cwuiPress[0].
        cwuiPress:REMOVE(0).
        IF tg = "MA" { cwPress(). cwuiSndQuiet(). }
        ELSE IF tg = "MR" { cwReset(). }
        ELSE IF tg = "HD" { cwHide(). }
    }
    IF CW_VIS AND NOT cwuiMade { cwuiInit(). }
    IF NOT cwuiMade { RETURN. }
    IF CW_VIS AND NOT cwuiShown { cwuiGui:SHOW(). SET cwuiShown TO TRUE. }
    IF NOT CW_VIS AND cwuiShown { cwuiGui:HIDE(). SET cwuiShown TO FALSE. cwuiSndQuiet(). }
    IF NOT cwuiShown { RETURN. }
    IF cwuiVer <> CW_VER { cwuiDraw(). }
    LOCAL rt IS uiRt().
    cwuiMasterDraw(rt).
    IF cwuiSmSeq <> CW_SMSEQ {
        IF CW_SMSEQ > cwuiSmSeq { cwuiAlert(). }
        SET cwuiSmSeq TO CW_SMSEQ.
    }
    cwuiTone(rt).
    cwuiWatchPos(rt).
}
// one trigger for the host's life (a program with several blocking loops: ops2q, ops3q)
// The background work off kOS's tick: the trigger still runs every physics
// tick, but its work runs on fixed real-time slots: the window + tone + master alarm (cwuiTick) and the checks (cwTick)
// every CWUI_DT s (25 Hz, the HUD's rate: a master alarm <= 40 ms after its cause), the GPC cycle check every
// CWUI_GPC_DT s (10 Hz; it flags gaps over CW_GPC_GAP 0.5 s, so 0.1 s slots are normal cycles). Was every tick (50 Hz).
GLOBAL CWUI_DT IS 0.04.
GLOBAL CWUI_GPC_DT IS 0.1.
GLOBAL cwuiNx IS 0.
GLOBAL cwuiGpcNx IS 0.
FUNCTION cwuiStart {
    IF cwuiRun { RETURN. }
    SET cwuiRun TO TRUE.
    WHEN TRUE THEN {
        IF cwuiRun {
            LOCAL rt IS uiRt().
            IF rt >= cwuiNx {
                SET cwuiNx TO (FLOOR((rt + 0.005) / CWUI_DT) + 1) * CWUI_DT - 0.005.
                cwuiTick().
                cwTick().
            }
            IF rt >= cwuiGpcNx {
                SET cwuiGpcNx TO (FLOOR((rt + 0.005) / CWUI_GPC_DT) + 1) * CWUI_GPC_DT - 0.005.
                cwGpcStep(cwuiGpc, rt).         // the real-time gap between two GPC slots of this trigger
            }
        }
        RETURN cwuiRun.
    }
}
FUNCTION cwuiClose {
    SET cwuiRun TO FALSE.
    cwuiSndQuiet().
    IF cwuiMade { cwuiGui:HIDE(). cwuiGui:DISPOSE(). SET cwuiMade TO FALSE. SET cwuiShown TO FALSE. } }
