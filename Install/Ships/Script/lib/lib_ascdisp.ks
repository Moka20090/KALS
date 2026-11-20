@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_ASCDISP.KS  --  THE ASCENT PAGES, LIVE: ASCENT TRAJ 1, ASCENT TRAJ 2, RTLS TRAJ 2, OMS/MPS
// ============================================================================
//  ops1q's displays: the gist of the orbiter's ASCENT TRAJ 1 / 2 (LAUNCH TRAJ 1 on the pad, the abort's title after an
//  abort), of RTLS TRAJ 2 (an RTLS in stage 2) and of the MEDS OMS/MPS page, in two kOS GUI windows like TAEM's
//  VERT SIT / HORIZ SIT (each page 736 x 460 px): TRAJ at VERT SIT's place with two button rows above its page (the CSS
//  toggles, the Mode list, ABORT, the TAL site list, "!" for the FAILURES window), OMS/MPS at HORIZ SIT's with one
//  (HUD | HUD CAM); both always up. The console stays empty: what ops1q printed is on the pages. Units: H and ranges
//  km + K, the bars, VI / VREL / HDOT m/s, the EAS scale KEAS; the data metric, the sidecar's geometry in ft.
//  Host: ops1q calls adInit() once (FALSE = no pages: the console instead), adTick(asc) every loop tick (it draws a
//  window at most every AD_DT / 2 s, AD_DT_CS / 2 s with the C# drawing, the two in turn), adEvent(met, msg) for each
//  event and adEnd(asc) at the end (then adClose, or the windows stay up for OPS 6: lib_taemdisp's tdAdopt takes them
//  over through adAdopt). The buttons only set adReq ("ABORT"); the lists their picks adSel / adSite (the failures are the
//  FAILURES window's, lib_failui.ks); ops1q takes adReq with adTake(), fills the lists (adSetModes / adSetSites) and marks a failed SSME in adOut. Reads ops1q's run state (asc)
//  and its libraries' I-loads and functions
//  (ASC_*, asc_burnable; for RTLS TRAJ 2 lib_ascent_rtls.ks's asc_rtls_wxr / asc_rtls_vline and ops1q's asc["rl"]).
//  Reads asc_bg/ (written by the offline background generator): the backgrounds, sprites.txt (the TAEM pages' own
//  sprites re-used from taem_bg/sprites) and asc_bg.txt, which holds all the geometry and the abort boundaries.
//  Construction, as lib_taemdisp's pages: a zero-padded window whose page box has the background as STYLE:BG; sprites,
//  bars and text sit in 1x1 flow boxes moved by MARGIN (the Nth starts N px low, so the top rows' slots come first).
//  Every slot stays SHOWN: kOS drops a hidden label's box from the flow, which moves each later slot 1 px up per hidden
//  one (up to 29 px measured); an unused slot is blanked instead (no text, the blank sprite).
//  Each window's page box has its own slots and its own flow count (adMk / adMkAll while adInit builds it).
// ============================================================================

RUNONCEPATH("0:/lib/lib_screen.ks").        // SCR_H: the windows' place on a smaller screen
RUNONCEPATH("0:/lib/lib_guistyle.ks").      // the windows' frames in the panel look (uiDispSkin ...)
RUNONCEPATH("0:/lib/lib_failui.ks").        // the FAILURES window of the "!" button
RUNONCEPATH("0:/lib/lib_dock.ks").         // OMS/MPS docked under TRAJ, the deck where the crew left it

GLOBAL AD_ARCH IS "0:/".
GLOBAL AD_DIR IS "asc_bg/".
// the windows' start: TRAJ at the left edge, OMS/MPS right under it (placed on 3840x2160; a window's corner sits 30 px
// above its page's); on a screen under 2160 px the pair keeps its x and fits from the top
GLOBAL AD_X IS 167.                         // the TRAJ window, px
GLOBAL AD_Y IS MAX(0, MIN(405, SCR_H - 1080)).
GLOBAL AD_X2 IS AD_X.                       // the OMS/MPS window: under TRAJ, whose window is 560 px:
GLOBAL AD_Y2 IS AD_Y + 560.                 // its page 460 + 48 + its two button rows (2 x AD_BTN_H)
GLOBAL AD_DT IS 1.0.                        // s between a window's updates (~1 Hz, so PEG keeps its time; the two in turn)
// AD_DT_CS: with the C# drawing live (~1.5k opcodes a draw, max ~2.6k, against kOS's 5-14k) each window every
// AD_DT_CS s; kOS drawing (AD_CS off, a fallback) keeps AD_DT
GLOBAL AD_DT_CS IS 0.1.    // 10 Hz a window
GLOBAL AD_IMG_DY IS -2.                     // px: a sprite's row correction, measured with every slot shown
                                            // (a +2.7 drew the sprites ~5 px high). WHOLE px: kOS turns a margin into
                                            // whole pixels half to even, so a .5 here put each sprite 2 or 3 px
                                            // down by its row's parity and neighbours 1 px apart (the seams)
GLOBAL AD_TXT_DY IS 7.                      // px: text sits 7 px low in its label (TD_TXT_DY)
GLOBAL AD_FLOW_PX IS 1.0.                   // px per flow child (TD_FLOW_PX)
GLOBAL AD_FIT_IN IS 1.5.                    // px a sprite keeps inside its field (TD_FIT_IN)
GLOBAL AD_TXT_W IS 200.                     // a text label's width, px
GLOBAL AD_MSG_W IS 700.                     // a MESSAGES line's width, px
GLOBAL AD_ROW_DY IS 2.65.                   // px lower for every text: a value's caps centre on its background label's
                                            // (measured: the backgrounds' labels sit 1.55 px above their rows;
                                            // a 4.5 drew the values 1-3 px low)
GLOBAL AD_HDR_DY IS 2.85.                   // px: clock_px (the header's baseline) to a row's centre
GLOBAL AD_CLK_DY IS 0.                      // px lower: the clock (in AD_FONT at 13 px its digits end on the page
                                            // id's; AD_ROW_DY is the 11 px values')
GLOBAL AD_FONT IS "DejaVu Sans Mono Bold".   // the clock's face: the page id's (bold already, so no <b>)
GLOBAL AD_BTN_H IS 26.                      // px: a button row (TRAJ's two and OMS/MPS's one, above their pages);
                                            //   lib_taemdisp's TD_ROW_H: OPS 6 takes the rows over
GLOBAL AD_FT IS 0.3048.
GLOBAL AD_NM IS 1852.
GLOBAL AD_RHO0 IS 1.225.                    // kg/m3: the sea-level density, EAS from q
GLOBAL AD_KT IS 0.514444.                   // m/s per knot: TRAJ 1's EAS scale in KEAS (0-500)
GLOBAL AD_HIST_S IS 4.                      // s of samples kept for the predictors' rates
GLOBAL AD_ET_SEP_S IS 4.                    // s from MECO to the ET's separation (ASC_ET_SEP_DELAY)
GLOBAL AD_YELLOW IS "#f0d840".              // the DROOP row while the droop is engaged (traj_display's TJ_YELLOW)
GLOBAL AD_RED IS "#ff2929".                 // the MESSAGES' SSME out (ops1q asc_col_word's RED); also a failed SSME's OUT on the OMS/MPS page (Ad.cs reads it)
GLOBAL AD_DIM IS "#227822".                 // the frozen lower engine-out levels (dark green; fill_dim.png)
GLOBAL AD_DRP_X IS 416.1.                   // the DROOP word's left x, px (the mock-up's LR_X0 0.565 x
                                            // 736.4: the THROT / PRPLT / TMECO labels' left)

GLOBAL adOn IS FALSE.
GLOBAL adGui IS 0.                          // the TRAJ window and its page box
GLOBAL adBox IS 0.
GLOBAL adGuiE IS 0.                         // the OMS/MPS window and its page box
GLOBAL adBoxE IS 0.
GLOBAL adRow2 IS 0.                         // its second row (ROLL/YAW, TAL site, "!")
GLOBAL adCssBtnP IS 0.                      // the ascent's CSS toggles (pressed = CSS; lib_ascent_css)
GLOBAL adCssBtnR IS 0.
GLOBAL adCssReqP IS FALSE.                  // the crew's wishes, ops1q hands them to ascCssMode each pass
GLOBAL adCssReqR IS FALSE.
GLOBAL adCssEn IS TRUE.                     // the toggles live (FALSE: grey, AUTO)
GLOBAL adHudBtn IS 0.                       // the ascent's HUD | HUD CAM (the OMS/MPS page's row; ops1q acts on them)
GLOBAL adCamBtn IS 0.
GLOBAL adOps2Btn IS 0.                       // OPS2 in HUD CAM's place at an ATO's end (adOps2Arm); pressed -> adOps2Req
GLOBAL adOps2Req IS FALSE.
GLOBAL adRowH IS 0.                          // the OMS/MPS window's HUD row
GLOBAL adAltBtn IS 0.                       // OPS 1's ALT MODE (the OMS/MPS page's second row): RDR / BARO (lib_hud hdAltMode)
GLOBAL adHudOn IS FALSE.                    // the crew's wishes: the HUD shown, the camera at the HUD's eye
GLOBAL adCamReq IS FALSE.
GLOBAL adRow1 IS 0.                         // the TRAJ window's first button row above its page (PITCH, Mode,
                                            // ABORT; adRow2: ROLL/YAW, TAL site, "!")
GLOBAL adBg IS "".                          // the TRAJ background shown now (STYLE:BG set only on a change)
GLOBAL adCnt IS 0.                          // the flow-child count of the page box being built
GLOBAL adMk IS 0.                           // the page box being built (adInit) and its slot list
GLOBAL adMkAll IS LIST().
GLOBAL adS IS LEXICON().                    // the slots by name
GLOBAL adAll IS LIST().                     // every TRAJ slot, for adSweep
GLOBAL adAllE IS LIST().                    // every OMS/MPS slot
GLOBAL adGeo IS LEXICON().
GLOBAL adBnd IS LEXICON().
GLOBAL adSpr IS LEXICON().
GLOBAL adFill IS "".
GLOBAL adBlank IS "".                       // the blank sprite: an unused sprite or bar shows it (no slot is hidden)
GLOBAL adFillDim IS "".                     // the dark fill (sprites/fill_dim.png; fill.png without it)
GLOBAL adCyc IS 0.                          // the update count; each slot stores the update that last drew it
GLOBAL adNext IS 0.
GLOBAL adMsgs IS LIST().                    // the MESSAGES, newest first
GLOBAL adHist IS LIST().                    // LIST(t, vrel, vi, h, hdot) samples for the predictors
GLOBAL adReq IS "".                         // a button's request for ops1q ("FAIL L" / "FAIL C" / "FAIL R" / "ABORT")
GLOBAL adSel IS "".                         // the Mode list's pick: "RTLS" / "TAL" / "ATO" / "" (ops1q sets it at a
                                            // selection: the mode flown)
GLOBAL adSite IS "".                        // the TAL site list's pick (an ASC_TAL_SITES key; "": none)
GLOBAL adPmMode IS 0.                       // the two popups and the lists they show (adSetList)
GLOBAL adPmSite IS 0.
GLOBAL adModesL IS LIST().
GLOBAL adSitesL IS LIST().
GLOBAL adSiteHand IS FALSE.                // the TAL site list's pick moved by hand (ops1q: a TAL to it keeps it)
GLOBAL adPmSiteIx IS -1.                   // the INDEX adSetSites last left the site list at
GLOBAL adPkMode IS "".                      // the picks the lists last showed (a pick moved by code moves its
GLOBAL adPkSite IS "".                      // popup; one moved by hand is the popup's already)
GLOBAL AD_FW_DX IS 8.                       // the FAILURES window (lib_failui), px right of TRAJ's
// the marks drawn here at the predictor's boundaries (lib_ascent_abr: asc["abr"]["b"], m/s), so they stay accurate as
// the flight goes, else at the sidecar's nominal ones (adBnd, ft/s); the backgrounds carry the bar alone
GLOBAL AD_TICKS IS LIST("E_TAL", "ATO", "PRESS", "TAL_2EO", "NEG_RTN", "ATO_2EO", "PRESS_2EO").
GLOBAL AD_TICK_LAB IS LEXICON("E_TAL", "TAL", "ATO", "ATO", "PRESS", "PRESS", "TAL_2EO", "2EO TAL", "NEG_RTN",
    "NEG RTN", "ATO_2EO", "2EO ATO", "PRESS_2EO", "2EO PRESS").
// the earliest TAL's mark (E_TAL) reads "TAL"
// once a 1EO abort is selected the bar keeps only ITS 1EO mark (AD_TICK_1EO: the abort -> its own mark; a mark the
// selection cannot fly would read as an option): the other 1EO marks (E TAL, ATO, PRESS, NEG RTN) hidden; the 2EO marks
// by adTickRel's own rule
GLOBAL AD_TICK_1EO IS LEXICON("TAL", "E_TAL", "ATO", "ATO", "AOA", "ATO", "RTLS", "NEG_RTN").
GLOBAL AD_TICKS_1EO IS LIST("E_TAL", "ATO", "PRESS", "NEG_RTN").
GLOBAL AD_TICK_CW IS 6.                     // px per character of a mark's label (font 9, bold): the rows' packing
GLOBAL adWarn IS "".                        // a red line over the messages
GLOBAL adIds IS LEXICON().                  // the SSMEs ("L", "C", "R") and SRBs ("SL", "SR") by position
GLOBAL adPk IS LEXICON().                   // each SRB's peak thrust by UID
GLOBAL adOut IS LEXICON().                  // the SSMEs failed by ops1q ("L" / "C" / "R" -> TRUE)
// after an engine out only the relevant info: what no longer applies hidden (adTickRel, adRel2: e.g. the ATO marks
// after a TAL, the 2EO PRESS in a 1EO ATO), and the readouts and marks of the engine-out levels below the current one
// (a 2EO: the 1EO's; a 3EO: the 1EO's and the 2EO's) dark green, locked at their last values. The levels frozen (1 = the
// 1EO, 2 = the 1EO and the 2EO) caught once each at the first draw after the failure (adOut: the SSMEs out), the
// readouts (adLines) and the marks (adTicks) apart
GLOBAL adFrzNL IS 0.                        // the readouts' levels frozen
GLOBAL adFrzL IS LIST("", "").              // their texts (the 1EO, the 2EO line), without the yellow
GLOBAL adFrzNM IS 0.                        // the marks' levels frozen
GLOBAL adFrzM IS LEXICON().                 // their VIs (ft/s) by key, the marks shown at the freeze
// the MARKS of the level that just failed freeze too (a 1EO its 1EO marks, a 2EO its 2EO marks), dark, at their VIs at
// the failure; a frozen mark the selection no longer flies hides as a live one does (adTickRel). The readouts keep the
// rule above (the levels below the current one).
GLOBAL AD_TICK_FRZ_1EO IS TRUE.             // FALSE: the marks freeze as the readouts (a 2EO the 1EO's only)
// the MESSAGES' names for ops1q's phase changes ("" = not shown; the PEG log keeps them all)
GLOBAL AD_REN IS LEXICON("PAD -> STAGE1", "LIFTOFF", "STAGE1 -> SRBSEP", "SRB SEP", "ETSEP -> OMS2PLAN", "ET SEP",
    "ETSEP -> DONE", "ET SEP", "SRBSEP -> STAGE2", "", "STAGE2 -> MECO", "", "MECO -> ETSEP", "", "OMS2PLAN -> DONE", "",
    "ETSEP -> ETCLR", "", "ETCLR -> OMS2PLAN", "", "ETCLR -> DONE", "").

// The pages' math in C#, in the KAL/S
// coprocessor (coproc Ad.cs / AdKos.cs: ADDONS:KALS:ADSETUP, ADDRAW). kOS keeps the game reads (adCsIn, with the other
// libraries' calls), the state (the slots, adHist, the freezes: C# reads them and writes them back) and every widget
// write (ADDRAW returns them, adCsApply sets them). AD_CS (default TRUE): C# draws; on ANY failure kOS draws that same
// update and from then on (adCsOff; AD_CS_STATE says why).
IF NOT (DEFINED AD_CS) { GLOBAL AD_CS IS TRUE. }
// THE PAINTER (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE; lib_taemdisp's TD_PAINT): the two pages' slot labels (groups AD_T = TRAJ, AD_E = OMS/MPS)
// drawn by C# inside kOS's window (each with its own style and content, at the rect kOS's layout gives it), their
// boxes hidden from kOS's layout. AD_PAINT: 0 OFF (the default until the test harness's CHECK + A/B proof: kOS draws as
// before), 1 CHECK (kOS draws; KSP.log [KalsPaint] worst px), 2 PAINT, 3 AB; live: adPaintSet(m). Any failure: kOS draws
// (AD_PAINT_STATE says why).
IF NOT (DEFINED AD_PAINT) { GLOBAL AD_PAINT IS 0. }
GLOBAL AD_PAINT_STATE IS "OFF".
GLOBAL adPaintReg IS FALSE.
GLOBAL adPaintNames IS LIST().            // the groups registered
GLOBAL adCsOn IS FALSE.
GLOBAL AD_CS_ERR IS "".
GLOBAL AD_CS_STATE IS "kOS (not set up)".

FUNCTION adNums {                           // "key a b c" -> LIST of the numbers after the key
    PARAMETER lin.
    LOCAL out IS LIST().
    LOCAL p IS lin:SPLIT(" ").
    FROM { LOCAL i IS 1. } UNTIL i >= p:LENGTH STEP { SET i TO i + 1. } DO {
        IF p[i] <> "" { out:ADD(p[i]:TONUMBER(0)). }
    }
    RETURN out.
}

FUNCTION adLoad {                           // reads the sidecars (asc_bg.txt, sprites.txt)
    FOR l0 IN OPEN(AD_ARCH + AD_DIR + "asc_bg.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        IF lin <> "" AND NOT lin:STARTSWITH("#") {
            LOCAL p IS lin:SPLIT(" ").
            IF p[0] = "bnd" {
                FROM { LOCAL i IS 1. } UNTIL i + 1 >= p:LENGTH STEP { SET i TO i + 2. } DO {
                    SET adBnd[p[i]] TO p[i + 1]:TONUMBER(0).
                }
            } ELSE { SET adGeo[p[0]] TO adNums(lin). }
        }
    }
    FOR l0 IN OPEN(AD_ARCH + AD_DIR + "sprites.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        LOCAL p IS lin:SPLIT(" ").
        IF lin:STARTSWITH("S ") AND p:LENGTH >= 7 {
            SET adSpr[p[1]] TO LIST(p[2], p[3]:TONUMBER(0), p[4]:TONUMBER(0), p[5]:TONUMBER(0), p[6]:TONUMBER(0)).
        } ELSE IF lin:STARTSWITH("F ") AND p:LENGTH >= 3 { SET adFill TO p[2]. }
    }
    IF NOT (adGeo:HASKEY("png_w") AND adGeo:HASKEY("hdnom") AND adBnd:HASKEY("CO") AND adSpr:HASKEY("veh")) { RETURN FALSE. }
    IF adFill = "" OR NOT adSpr:HASKEY("blank") { RETURN FALSE. }
    SET adBlank TO adSpr["blank"][0].
    SET adFillDim TO adFill:REPLACE("fill.png", "fill_dim.png").
    IF NOT EXISTS(AD_ARCH + adFillDim) { SET adFillDim TO adFill. }
    RETURN EXISTS(AD_ARCH + adFill) AND EXISTS(AD_ARCH + adBlank) AND EXISTS(AD_ARCH + AD_DIR + "t1_launch.png").
}

// ---- the slots: LIST(widget, flow index, last sprite / text, last x, y, ON, the update that last drew it, align,
// width, font size (a bar: its height), a text slot's own px lower, the last call's x, y, align, a text slot's full width,
// the kind: "T" text, "I" sprite, "B" bar). A slot's widget is never hidden (see the header): off = blanked.
FUNCTION adNewBox {
    LOCAL bx IS adMk:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    RETURN bx:ADDLABEL("").
}

FUNCTION adSlot {
    PARAMETER m, w, fs, dy, kd.
    LOCAL sl IS LIST(m, adCnt, "", -99999, -99999, FALSE, -1, "", w, fs, dy, -99999, -99999, -1, w, kd, adFill).
    SET adCnt TO adCnt + 1.
    adMkAll:ADD(sl).
    RETURN sl.
}

FUNCTION adImgSlot {
    LOCAL m IS adNewBox().
    SET m:STYLE:WIDTH TO 4. SET m:STYLE:HEIGHT TO 4.
    RETURN adSlot(m, -1, 0, 0, "I").
}

FUNCTION adTxtSlot {                        // bd FALSE: the page face AD_FONT, plain text (no <b>), sl[17]
    PARAMETER fs, col, w, bd IS TRUE.
    LOCAL m IS adNewBox().
    SET m:STYLE:FONTSIZE TO fs.
    SET m:STYLE:TEXTCOLOR TO col.
    SET m:STYLE:WIDTH TO w. SET m:STYLE:HEIGHT TO fs * 2.
    SET m:STYLE:RICHTEXT TO bd.
    IF NOT bd { SET m:STYLE:FONT TO AD_FONT. }
    LOCAL sl IS adSlot(m, w, fs, AD_ROW_DY, "T").
    sl:ADD(bd).
    RETURN sl.
}

FUNCTION adBarSlot {                        // a filled bar: an empty label whose STYLE:BG is the fill, sized to the bar
    LOCAL m IS adNewBox().
    SET m:STYLE:BG TO adBlank.                // off until adBar draws it (adSlotOn puts the fill on)
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:WIDTH TO 4. SET m:STYLE:HEIGHT TO 4.
    RETURN adSlot(m, 4, 4, 0, "B").
}

FUNCTION adSlotOn {                         // on (a bar's fill back) only on a change, and marked drawn this update
    PARAMETER sl.
    SET sl[6] TO adCyc.
    IF NOT sl[5] {
        IF sl[15] = "B" { SET sl[0]:STYLE:BG TO sl[16]. }   // the slot's own fill (adBarFill)
        SET sl[5] TO TRUE.
    }
}

FUNCTION adSlotOff {                        // blanked, never hidden: a hidden label's box leaves kOS's flow
    PARAMETER sl.
    IF sl[5] {
        IF sl[15] = "T" { SET sl[0]:TEXT TO "". }
        ELSE IF sl[15] = "I" { SET sl[0]:IMAGE TO adBlank. }
        ELSE { SET sl[0]:STYLE:BG TO adBlank. }
        SET sl[2] TO "".
        SET sl[5] TO FALSE.
    }
}

FUNCTION adPut {                            // a sprite's anchor at page px (x, y); name "" hides it
    PARAMETER sl, nm, x, y.
    IF x = sl[11] AND y = sl[12] AND nm = sl[2] AND nm <> "" { adSlotOn(sl). RETURN. }
    IF nm = "" OR NOT adSpr:HASKEY(nm) { adSlotOff(sl). RETURN. }
    LOCAL sp IS adSpr[nm].
    IF sl[2] <> nm {
        SET sl[0]:IMAGE TO sp[0].
        SET sl[0]:STYLE:WIDTH TO sp[1].
        SET sl[0]:STYLE:HEIGHT TO sp[2].
        SET sl[2] TO nm.
    }
    LOCAL xx IS ROUND(x - sp[3]).
    LOCAL yy IS ROUND(y - sp[4]).
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy - AD_IMG_DY - sl[1] * AD_FLOW_PX).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    SET sl[11] TO x. SET sl[12] TO y.
    adSlotOn(sl).
}

FUNCTION adText {                           // text; align 0 left, 1 right (right edge at x), 2 centred
    PARAMETER sl, s, x, y, align.
    IF s = "" { adSlotOff(sl). RETURN. }
    IF x = sl[11] AND y = sl[12] AND align = sl[13] AND s = sl[2] { adSlotOn(sl). RETURN. }
    IF sl[2] <> s { SET sl[0]:TEXT TO CHOOSE "<b>" + s + "</b>" IF sl[17] ELSE s. SET sl[2] TO s. }
    // a right-aligned or centred label near the page's left edge narrows to the room it has (lib_taemdisp's tdText)
    LOCAL w IS sl[14].
    LOCAL xx IS ROUND(x).
    LOCAL al IS "LEFT".
    IF align = 1 { SET w TO MAX(1, MIN(sl[14], xx)). SET xx TO xx - w. SET al TO "RIGHT". }
    ELSE IF align = 2 { SET w TO MAX(2, MIN(sl[14], 2 * xx)). SET xx TO ROUND(x - w / 2). SET al TO "CENTER". }
    IF sl[7] <> al { SET sl[0]:STYLE:ALIGN TO al. SET sl[7] TO al. }
    IF sl[8] <> w { SET sl[0]:STYLE:WIDTH TO w. SET sl[8] TO w. }
    LOCAL yy IS ROUND(y - sl[9] * 0.7 - AD_TXT_DY + sl[10]).    // one rounding (two put rows 1 px off by parity)
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy - sl[1] * AD_FLOW_PX).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    SET sl[11] TO x. SET sl[12] TO y. SET sl[13] TO align.
    adSlotOn(sl).
}

FUNCTION adBar {                            // a fill bar over page px x0..x1, y0 (top)..y1 (bottom)
    PARAMETER sl, x0, y0, x1, y1.
    LOCAL w IS ROUND(x1 - x0).
    LOCAL h IS ROUND(y1 - y0).
    IF w < 1 OR h < 1 { adSlotOff(sl). RETURN. }
    IF sl[8] <> w { SET sl[0]:STYLE:WIDTH TO w. SET sl[8] TO w. }
    IF sl[9] <> h { SET sl[0]:STYLE:HEIGHT TO h. SET sl[9] TO h. }
    LOCAL xx IS ROUND(x0).
    LOCAL yy IS ROUND(y0).
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy - sl[1] * AD_FLOW_PX).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    adSlotOn(sl).
}

FUNCTION adBarFill {                        // a bar slot's fill (adFill / adFillDim), changed only on a change
    PARAMETER sl, f.
    IF sl[16] = f { RETURN. }
    SET sl[16] TO f.
    IF sl[5] { SET sl[0]:STYLE:BG TO f. }
}

FUNCTION adSweep {                          // after a window's drawing: blank only its slots that are on but not drawn
    PARAMETER lst.
    FOR sl IN lst { IF sl[5] { IF sl[6] <> adCyc { adSlotOff(sl). } } }
}

FUNCTION adSetBg {
    PARAMETER nm.
    LOCAL f IS AD_DIR + nm + ".png".
    IF f <> adBg { SET adBox:STYLE:BG TO f. SET adBg TO f. }
}

// ---- the buttons: their delegates only set a global (each made in its own call, so it keeps its own value)
FUNCTION adReqFn {
    PARAMETER s.
    RETURN { SET adReq TO s. }.
}

FUNCTION adTake {                           // ops1q takes a button's request (once)
    LOCAL rq IS adReq.
    SET adReq TO "".
    RETURN rq.
}

// ---- the abort controls (after Giulio Dondi's script: the Mode list shows only the modes available now, the TAL site
// list only the sites available): the TRAJ window's rows (Mode [list] ABORT, TAL site [list] "!") and the FAILURES
// window ("!"). ops1q fills the lists (adSetModes / adSetSites, twice a second); their OPTIONS are set only on a change
// and the pick is kept by name (gone: the first); "NONE" alone when a list is empty. A list's pick is its global
// (adSel / adSite); ops1q sets them at a selection (the mode, the site flown).
FUNCTION adSetList {                        // the popup pm to the list L (it shows old); its INDEX to the pick pk when the
    PARAMETER pm, L, old, pk, moved.        // list changes or code moved the pick (moved) -> the list shown
    LOCAL nl IS L:COPY.
    IF nl:LENGTH = 0 { nl:ADD("NONE"). }
    LOCAL same IS nl:LENGTH = old:LENGTH.
    IF same {
        FROM { LOCAL i IS 0. } UNTIL i >= nl:LENGTH STEP { SET i TO i + 1. } DO { IF nl[i] <> old[i] { SET same TO FALSE. } }
    }
    IF NOT same { SET pm:OPTIONS TO nl. }
    IF (NOT same) OR moved { SET pm:INDEX TO MAX(0, nl:INDEXOF(pk)). }
    RETURN nl.
}

FUNCTION adSetModes {                       // ops1q: the Mode list (in the order RTLS, TAL, ATO)
    PARAMETER L.
    SET adModesL TO adSetList(adPmMode, L, adModesL, adSel, adSel <> adPkMode).
    LOCAL vx IS adModesL[MAX(0, MIN(adPmMode:INDEX, adModesL:LENGTH - 1))].
    SET adSel TO CHOOSE "" IF vx = "NONE" ELSE vx.
    SET adPkMode TO adSel.
}

// ops1q: the TAL site list -- the keys L (best first), their labels lb (the key and the rank margin); with fw the pick
// follows the first (the least-dV site, the default) until the crew moves it by hand (adSiteHand: the list's INDEX moved
// since the last pass; it ends when that site leaves the list), else the pick is kept by key (a TAL flown: its site
// until the crew picks another for the switch)
FUNCTION adSetSites {
    PARAMETER L, lb IS L, fw IS FALSE.
    LOCAL kl IS L:COPY.
    LOCAL nl IS lb:COPY.
    IF kl:LENGTH = 0 { kl:ADD("NONE"). nl:ADD("NONE"). }
    IF fw AND adPmSiteIx >= 0 AND adPmSite:INDEX <> adPmSiteIx { SET adSiteHand TO TRUE. }
    IF NOT fw { SET adSiteHand TO FALSE. }
    LOCAL pk IS CHOOSE adSite IF adSite <> "" ELSE "NONE".
    IF fw AND NOT (adSiteHand AND kl:CONTAINS(pk)) { SET adSiteHand TO FALSE. SET pk TO kl[0]. }
    LOCAL same IS nl:LENGTH = adSitesL:LENGTH.
    IF same {
        FROM { LOCAL i IS 0. } UNTIL i >= nl:LENGTH STEP { SET i TO i + 1. } DO { IF nl[i] <> adSitesL[i] { SET same TO FALSE. } }
    }
    IF NOT same { SET adPmSite:OPTIONS TO nl. }
    LOCAL ix IS MAX(0, kl:INDEXOF(pk)).
    IF (NOT same) OR adPmSite:INDEX <> ix { SET adPmSite:INDEX TO ix. }
    SET adSitesL TO nl.
    SET adPmSiteIx TO ix.
    SET adSite TO CHOOSE "" IF kl[ix] = "NONE" ELSE kl[ix].
    SET adPkSite TO adSite.
}

// The FAILURES window is lib_failui.ks's (the same window in ops1q / ops2q / ops3q; was the ENGINE FAILURE window here).
// "!" shows / hides it, docked right of TRAJ where TRAJ is now; ops1q registers its SSME handler (asc_failInit) and runs its schedule.
FUNCTION adFwToggle {                       // "!"
    fuiToggle(MAX(0, adGui:X + adGeo["png_w"][0] + AD_FW_DX), MAX(0, adGui:Y)).
}

FUNCTION adWin {                            // a window: a title row, a button row, a zero-padded page box
    PARAMETER title, x, y, w, h, btn IS TRUE, nrow IS 1.   // (lib_taemdisp's tdWin: the button rows between the title
                                            // and the page); btn FALSE: no button row
    LOCAL g IS GUI(w).                      // exactly the page's width (was w + 24: a grey strip right of the screen)
    uiDispSkin(g).                          // the frame in the panel look (the page's labels untouched)
    SET g:STYLE:HEIGHT TO h + 48 + (CHOOSE nrow * AD_BTN_H IF btn ELSE 0).   // nrow 2 = TRAJ's two rows
    SET g:X TO x. SET g:Y TO y.
    SET g:STYLE:PADDING:H TO 0.
    SET g:STYLE:PADDING:V TO 0.
    LOCAL tb IS g:ADDHLAYOUT().
    LOCAL tl IS tb:ADDLABEL("<b>" + title + "</b>").
    uiDispTitle(tb, tl).
    LOCAL rw IS 0.                          // kOS lays a window out in the order added: the row before the box
    LOCAL rw2 IS 0.
    IF btn {                                // every row at a fixed height and the page's width, as tdWin's
        SET rw TO g:ADDHLAYOUT().           //   (OPS 6 takes the rows over: lib_dap sizes its buttons by the width)
        SET rw:STYLE:HEIGHT TO AD_BTN_H.
        SET rw:STYLE:WIDTH TO w.
        IF nrow > 1 {                       // the second row; both at a fixed height (the page stays put)
            SET rw2 TO g:ADDHLAYOUT().
            SET rw2:STYLE:HEIGHT TO AD_BTN_H.
            SET rw2:STYLE:WIDTH TO w.
        }
    }
    LOCAL bx IS g:ADDVLAYOUT().
    SET bx:STYLE:PADDING:H TO 0.
    SET bx:STYLE:PADDING:V TO 0.
    SET bx:STYLE:WIDTH TO w.
    SET bx:STYLE:HEIGHT TO h.
    RETURN LIST(g, bx, rw, rw2).
}

FUNCTION adCommonSlots {                    // the clock, the abort modes, the MESSAGES: on both pages ("" / "e" names)
    PARAMETER pre, grn, alc.
    SET adS[pre + "met"] TO adTxtSlot(13, grn, AD_TXT_W, FALSE).
    LOCAL mc IS adS[pre + "met"]. SET mc[10] TO AD_CLK_DY.
    FOR k IN LIST("ab0", "ab1", "ab2") { SET adS[pre + k] TO adTxtSlot(11, grn, AD_TXT_W). }
    FOR k IN LIST("m0", "m1", "m2") { SET adS[pre + k] TO adTxtSlot(10, grn, AD_MSG_W). }
    SET adS[pre + "warn"] TO adTxtSlot(11, alc, AD_MSG_W).
}

FUNCTION adInit {
    IF NOT (EXISTS(AD_ARCH + AD_DIR + "asc_bg.txt") AND EXISTS(AD_ARCH + AD_DIR + "sprites.txt")) { RETURN FALSE. }
    IF NOT adLoad() { RETURN FALSE. }
    LOCAL w IS adGeo["png_w"][0].
    LOCAL h IS adGeo["png_h"][0].
    LOCAL wt IS adWin("OPS 1 TRAJ", AD_X, AD_Y, w, h, TRUE, 2).
    SET adGui TO wt[0].
    SET adBox TO wt[1].
    SET adBg TO "".
    adSetBg("t1_launch").
    // the CSS toggles on the left in 2 rows, the abort controls right of them, also in 2 rows: a 2 x 4 grid as VERT
    // SIT's (lib_dap dapGrid), each column a quarter of the page's width: PITCH | Mode [list] | ABORT over
    // ROLL/YAW | TAL site [list] | "!" (Dondi's top row, split in two)
    SET adRow1 TO wt[2].
    SET adRow2 TO wt[3].
    LOCAL bw IS (w - 20) / 4.               // 4 widgets + 3 x 4 px between + 2 x 4 px margins = w: equal left / right gap
    SET adCssBtnP TO adRow1:ADDBUTTON("PITCH  AUTO").
    SET adCssBtnR TO adRow2:ADDBUTTON("ROLL/YAW  AUTO").
    FOR bt IN LIST(adCssBtnP, adCssBtnR) {
        SET bt:TOGGLE TO TRUE.
        SET bt:STYLE:HSTRETCH TO FALSE.
        SET bt:STYLE:WIDTH TO bw.
    }
    SET adCssBtnP:ONTOGGLE TO { PARAMETER val. SET adCssReqP TO val AND adCssEn.
        SET adCssBtnP:TEXT TO CHOOSE "PITCH  CSS" IF adCssReqP ELSE "PITCH  AUTO". }.
    SET adCssBtnR:ONTOGGLE TO { PARAMETER val. SET adCssReqR TO val AND adCssEn.
        SET adCssBtnR:TEXT TO CHOOSE "ROLL/YAW  CSS" IF adCssReqR ELSE "ROLL/YAW  AUTO". }.
    LOCAL lm IS adRow1:ADDLABEL("Mode").
    SET lm:STYLE:WIDTH TO 64.
    SET adPmMode TO adRow1:ADDPOPUPMENU().
    SET adPmMode:STYLE:HSTRETCH TO FALSE.
    SET adPmMode:STYLE:WIDTH TO 2 * bw - 64.       // the label (64) + 4 + this = two columns (2 bw + 4)
    SET adPmMode:OPTIONS TO LIST("NONE").
    SET adPmMode:INDEX TO 0.                // "NONE" shown (adSetList sets INDEX only on a change)
    SET adModesL TO LIST("NONE").
    SET adPmMode:ONCHANGE TO { PARAMETER val. SET adSel TO CHOOSE "" IF val = "NONE" ELSE val. }.
    LOCAL b IS adRow1:ADDBUTTON("ABORT").
    SET b:STYLE:HSTRETCH TO FALSE.
    SET b:STYLE:WIDTH TO bw.
    SET b:ONCLICK TO adReqFn("ABORT").
    LOCAL ls IS adRow2:ADDLABEL("TAL site").
    SET ls:STYLE:WIDTH TO 64.
    SET adPmSite TO adRow2:ADDPOPUPMENU().
    SET adPmSite:STYLE:HSTRETCH TO FALSE.
    SET adPmSite:STYLE:WIDTH TO 2 * bw - 64.
    SET adPmSite:OPTIONS TO LIST("NONE").
    SET adPmSite:INDEX TO 0.                // "NONE" shown
    SET adSitesL TO LIST("NONE").
    SET adPmSite:ONCHANGE TO { PARAMETER val. SET adSite TO CHOOSE "" IF val = "NONE" ELSE val:SPLIT(" ")[0]. }.   // the label's key
    LOCAL bx IS adRow2:ADDBUTTON("!").
    SET bx:STYLE:HSTRETCH TO FALSE.
    SET bx:STYLE:WIDTH TO bw.
    SET bx:ONCLICK TO { adFwToggle(). }.
    IF uiDispOn() {                         // the panel look: the rows' labels grey, ABORT guarded, the controls
        uiDispLabel(lm).                    //   AD_BTN_H - 4 high (fixed: the row's height does not follow the font)
        uiDispLabel(ls).
        uiDispWarn(b).
        FOR wd IN LIST(adCssBtnP, adCssBtnR, lm, adPmMode, b, ls, adPmSite, bx) { SET wd:STYLE:HEIGHT TO AD_BTN_H - 4. }
        // the deck's 22 px (lib_taemdisp's TD_ROW_H - 4)
    }
    LOCAL we IS adWin("OPS 1 OMS/MPS", AD_X2, AD_Y2, w, h, TRUE, 2).   // its rows: HUD | HUD CAM (FAIL: the failure window),
                                            //   ALT MODE
    SET adGuiE TO we[0].
    SET adBoxE TO we[1].
    SET adBoxE:STYLE:BG TO AD_DIR + "omsmps.png".
    // HUD | HUD CAM on the bottom page's row, as the entry's and TAEM's (HUD a quarter, HUD CAM the rest); grey until
    // ops1q's HUD has loaded (adHudSet)
    LOCAL cwe IS (w - 20) / 4.              // The same column width as the rows above (HUD CAM stretches to the right margin)
    SET adHudBtn TO we[2]:ADDBUTTON("HUD OFF").
    SET adHudBtn:TOGGLE TO TRUE.
    SET adHudBtn:STYLE:HSTRETCH TO FALSE.
    SET adHudBtn:STYLE:WIDTH TO cwe.
    SET adHudBtn:ONTOGGLE TO { PARAMETER val. SET adHudOn TO val.
        SET adHudBtn:TEXT TO CHOOSE "HUD ON" IF val ELSE "HUD OFF". }.
    SET adCamBtn TO we[2]:ADDBUTTON("HUD CAM OFF").
    SET adCamBtn:TOGGLE TO TRUE.
    SET adCamBtn:STYLE:HSTRETCH TO TRUE.
    SET adCamBtn:ONTOGGLE TO { PARAMETER val. SET adCamReq TO val.
        SET adCamBtn:TEXT TO CHOOSE "HUD CAM ON" IF val ELSE "HUD CAM OFF". }.
    SET adRowH TO we[2].
    // ALT MODE on the second row: the HUD's altitude, RDR (the radar's) or BARO (ASL); pressed = RDR (the selected look), BARO the unselected. lib_hud switches
    // it as the radar's height crosses HD_RADALT_FT (ops1q's adAltSet shows it)
    SET adAltBtn TO we[3]:ADDBUTTON("ALT MODE RDR").
    SET adAltBtn:TOGGLE TO TRUE.
    SET adAltBtn:PRESSED TO TRUE.
    SET adAltBtn:STYLE:HSTRETCH TO TRUE.
    SET adAltBtn:ONTOGGLE TO { PARAMETER val. SET hdAltMode TO CHOOSE "RDR" IF val ELSE "BARO".
        SET adAltBtn:TEXT TO "ALT MODE " + hdAltMode. }.
    SET adHudBtn:ENABLED TO FALSE.
    SET adCamBtn:ENABLED TO FALSE.
    SET adAltBtn:ENABLED TO FALSE.
    IF uiDispOn() { FOR wd IN LIST(adHudBtn, adCamBtn, adAltBtn) { SET wd:STYLE:HEIGHT TO AD_BTN_H - 4. } }
    SET adS TO LEXICON().
    LOCAL grn IS RGB(0.235, 0.878, 0.235).
    LOCAL alc IS RGB(1, 0.16, 0.16).        // the alert colour (not "red": RED is a kOS bound variable)
    // each window's own slots in its own box (a slot's flow index must stay below its row: the common ones
    // first, then the page's; the highest index 47 (the marks: tk 30-37 from 56 px, tl 38-45 from 68 px; the
    // DROOP row dr 46-47 at 288 px), every row below the clock's at 62 px or lower)
    SET adAll TO LIST().
    SET adMk TO adBox. SET adMkAll TO adAll. SET adCnt TO 0.
    adCommonSlots("", grn, alc).
    SET adS["bar"] TO adImgSlot().
    FOR k IN LIST("veh", "p1", "p2", "ptr1", "ptr2") { SET adS[k] TO adImgSlot(). }
    FOR k IN LIST("c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "r0", "r1", "r2", "hdot", "lr0", "lr1", "lr2") {
        SET adS[k] TO adTxtSlot(11, grn, AD_TXT_W).
    }
    FROM { LOCAL i IS 0. } UNTIL i >= 8 STEP { SET i TO i + 1. } DO { SET adS["tk" + i] TO adBarSlot(). }
    FROM { LOCAL i IS 0. } UNTIL i >= 8 STEP { SET i TO i + 1. } DO { SET adS["tl" + i] TO adTxtSlot(9, grn, 70). }
    FOR k IN LIST("dr0", "dr1") { SET adS[k] TO adTxtSlot(11, grn, AD_TXT_W). }   // TRAJ 2's DROOP row
    SET adAllE TO LIST().
    SET adMk TO adBoxE. SET adMkAll TO adAllE. SET adCnt TO 0.
    adCommonSlots("e", grn, alc).
    FOR k IN LIST("b0", "b1", "b2", "b3", "b4") { SET adS[k] TO adBarSlot(). }
    FOR k IN LIST("v0", "v1", "v2", "v3", "v4", "s0", "s1", "s2", "s3", "s4", "l0", "l1", "l2", "l3", "l5", "l6") {
        SET adS[k] TO adTxtSlot(11, grn, AD_TXT_W).
    }
    dkAttach(adGui, adGuiE, "asc").        // the deck (lib_dock): OMS/MPS docked under TRAJ, both where the crew left them
    adGui:SHOW().
    adGuiE:SHOW().
    SET adOn TO TRUE.
    SET adNext TO 0.
    adCsSetup().                            // the C# pages (or why not)
    adPaintSetup().                         // The painter (AD_PAINT; OFF by default)
    gpcWin("TOP", adGpcXT@).                // The windows' X looks (lib_gpc)
    gpcWin("BOT", adGpcXB@).
    RETURN TRUE.
}

// ops1q each pass, after ascCssMode: en FALSE greys both toggles (before liftoff, the split-S, from MECO, no
// FBW3); offP / offR: the arbiter forced that axis back to AUTO (its toggle released; from the wish ops1q passed, so a
// click between the two calls stays)
FUNCTION adCssSet {
    PARAMETER en, offP, offR.
    IF adCssBtnP:ISTYPE("Scalar") { RETURN. }
    IF en <> adCssEn {
        SET adCssEn TO en.
        SET adCssBtnP:ENABLED TO en.
        SET adCssBtnR:ENABLED TO en.
    }
    IF offP { SET adCssBtnP:PRESSED TO FALSE. }   // its ONTOGGLE clears the wish and the text
    IF offR { SET adCssBtnR:PRESSED TO FALSE. }
}

// ops1q once its HUD has loaded (en TRUE) or not / at its end (grey)
FUNCTION adHudSet {
    PARAMETER en.
    IF adHudBtn:ISTYPE("Scalar") { RETURN. }
    SET adHudBtn:ENABLED TO en.
    SET adCamBtn:ENABLED TO en.
    SET adAltBtn:ENABLED TO en.
}

// an ATO's end hands the orbit on to ops2q (the ATO / AOA TGT page asks the pick before OMS-1): the OMS/MPS page's
// HUD CAM button is replaced by OPS2 (the press is adOps2Req; ops1q waits for it, then closes the pages and runs ops2q)
FUNCTION adOps2Arm {
    PARAMETER lb IS "OPS2".                  // A nominal ascent's end labels it "OPS 2 PRO"
    IF NOT adOn { RETURN. }
    IF adRowH:ISTYPE("Scalar") { RETURN. }
    IF NOT adCamBtn:ISTYPE("Scalar") { adCamBtn:DISPOSE(). SET adCamBtn TO 0. }
    SET adOps2Req TO FALSE.
    SET adOps2Btn TO adRowH:ADDBUTTON(lb).
    SET adOps2Btn:STYLE:HSTRETCH TO TRUE.
    IF uiDispOn() { SET adOps2Btn:STYLE:HEIGHT TO AD_BTN_H - 4. }
    SET adOps2Btn:ONCLICK TO { SET adOps2Req TO TRUE. SET adOps2Btn:TEXT TO adOps2Btn:TEXT + " ...". }.
    IF DEFINED SAIL_ON { sailReg("ops2pro", adOps2Btn). }   // The test harness may press it (lib_sail; a no-op unless a test run)
}

// ALT MODE shown as the HUD has it (RDR: pressed); its ONTOGGLE sets the same mode back
FUNCTION adAltSet {
    PARAMETER baro.
    IF adAltBtn:ISTYPE("Scalar") { RETURN. }
    IF adAltBtn:PRESSED = baro { SET adAltBtn:PRESSED TO NOT baro. }
}

// the camera refused (no free camera): HUD CAM released (its ONTOGGLE clears the wish and the text)
FUNCTION adHudCamOff {
    IF adCamBtn:ISTYPE("Scalar") { RETURN. }
    SET adCamBtn:PRESSED TO FALSE.
}

FUNCTION adEnd {                            // ops1q's end: a last update, the failure window gone (then adClose,
                                            // or OPS 6's adAdopt); the row stays: hidden, it would leave kOS's flow
                                            // and move the page up for the moment before the windows close
    PARAMETER asc.
    IF adOn {
        SET adNext TO 0.
        adTick(asc).
        SET adNext TO 0.
        adTick(asc).                        // the other window (the two are drawn in turn)
        fuiHide().
    }
}

FUNCTION adClose {
    IF adOn {
        gpcWinForget("TOP").                // their X looks forgotten before the windows go (fuiClose's gpcClose would write to them)
        gpcWinForget("BOT").
        dkDetach("asc").                    // the deck's place saved, before the windows go
        adGui:HIDE().
        adGui:DISPOSE().
        adGuiE:HIDE().
        adGuiE:DISPOSE().
        fuiClose().
        SET adOn TO FALSE.
    }
}

// OPS 6's deck (lib_taemdisp tdAdopt) takes the two windows over in place when ops1q kept them up, so the displays stay
// up from OPS 1 into OPS 6 and only the pages and the buttons switch: the ascent's pages hidden (out of kOS's flow), its
// row controls disposed (lib_dap fills the empty rows), the failure window gone, the dock handed on as it is (one saved
// place: nothing moves); RETURNS LIST(TRAJ, its two rows, its title label, OMS/MPS, its row, its title label), or an
// empty list (nothing to take)
FUNCTION adAdopt {
    IF NOT adOn { RETURN LIST(). }
    LOCAL rw IS adGui:WIDGETS[1].
    LOCAL rw2 IS adGui:WIDGETS[2].
    LOCAL rwE IS adGuiE:WIDGETS[1].
    LOCAL rwE2 IS adGuiE:WIDGETS[2].
    FOR rr IN LIST(rw, rw2, rwE, rwE2) { FOR wd IN rr:WIDGETS { wd:DISPOSE(). } }
    adBox:HIDE().
    adBoxE:HIDE().
    fuiClose().
    IF dkOn AND dkKey = "asc" { SET dkKey TO "td". }
    LOCAL L IS LIST(adGui, rw, rw2, adGui:WIDGETS[0]:WIDGETS[0], adGuiE, rwE, adGuiE:WIDGETS[0]:WIDGETS[0], rwE2).
    SET adCssBtnP TO 0. SET adCssBtnR TO 0. SET adHudBtn TO 0. SET adCamBtn TO 0. SET adAltBtn TO 0. SET adOps2Btn TO 0.
    SET adOn TO FALSE.                      // adClose: nothing left to close
    RETURN L.
}

// ---- formats
FUNCTION adMmss {                           // t s as m:ss
    PARAMETER t.
    LOCAL a IS FLOOR(MAX(t, 0)).
    LOCAL ss IS MOD(a, 60).
    RETURN FLOOR(a / 60) + ":" + (CHOOSE "0" IF ss < 10 ELSE "") + ss.
}

FUNCTION adFx {                             // x with nd decimals ("" + ROUND drops a trailing .0)
    PARAMETER x, nd.
    LOCAL s IS "" + ROUND(x, nd).
    IF nd > 0 {
        IF s:FIND(".") < 0 { SET s TO s + ".". }
        UNTIL s:LENGTH - s:FIND(".") > nd { SET s TO s + "0". }
    }
    RETURN s.
}

FUNCTION adSgn {                            // a signed whole number
    PARAMETER x.
    LOCAL n IS ROUND(x).
    RETURN (CHOOSE "+" IF n >= 0 ELSE "") + n.
}

FUNCTION adPl {                             // a power level as the orbiter prints it: whole percent, truncated, up to
    PARAMETER pl.                           // the SSMEs' full throttle (100 / ASC_PL_TO_KSP: Block I 104.6, Block II
    // 109.2; ops1q's asc_ssme_detect), 0.05 % slack: the thrust is read a tick behind its rise through the air (a
    // flight read 103.996 at 104 %: "103" without it; a fixed 104.6 scale would read a Block II's 104 % as 99)
    RETURN "" + FLOOR(MIN(pl, 100 / ASC_PL_TO_KSP) + 0.05).
}

FUNCTION adClock {                          // DDD/HH:MM:SS
    PARAMETER t.
    LOCAL a IS FLOOR(MAX(t, 0)).
    LOCAL d IS FLOOR(a / 86400).
    LOCAL hh IS FLOOR(MOD(a, 86400) / 3600).
    LOCAL mm IS FLOOR(MOD(a, 3600) / 60).
    LOCAL ss IS MOD(a, 60).
    RETURN ("" + d):PADLEFT(3):REPLACE(" ", "0") + "/" + ("" + hh):PADLEFT(2):REPLACE(" ", "0") + ":"
        + ("" + mm):PADLEFT(2):REPLACE(" ", "0") + ":" + ("" + ss):PADLEFT(2):REPLACE(" ", "0").
}

// ---- the page's geometry
FUNCTION adScaleY {                         // a scale's row for val (clamped): spine x, row lo, row hi, v lo, v hi
    PARAMETER g, val.
    LOCAL f IS (MIN(MAX(val, g[3]), g[4]) - g[3]) / (g[4] - g[3]).
    RETURN g[1] + f * (g[2] - g[1]).
}

FUNCTION adField {                          // a (x, H kft) point of TRAJ field k -> page px; clamp = keep it inside
    PARAMETER k, x, y, clamp.
    RETURN adFieldG(adGeo["t" + k + "_field_px"], x, y, clamp).
}

FUNCTION adFieldG {                         // the same on a field's geometry g: left top width height (px), x0 x1, y0 y1
    PARAMETER g, x, y, clamp.
    LOCAL fx IS (x - g[4]) / (g[5] - g[4]).
    LOCAL fy IS (y - g[6]) / (g[7] - g[6]).
    IF clamp { SET fx TO MIN(MAX(fx, 0), 1). SET fy TO MIN(MAX(fy, 0), 1). }
    ELSE IF fx < 0 OR fx > 1 OR fy < 0 OR fy > 1 { RETURN LIST(). }
    RETURN LIST(g[0] + g[2] * fx, g[1] + g[3] * (1 - fy)).
}

// a sprite is shown only when it is FULLY inside the box it lives in: the sprite nm anchored at page px p, where adPut
// draws it, wholly inside the field g (left top width height px) less AD_FIT_IN (adFits); p moved the least that keeps
// it so (adHold)
FUNCTION adFits {
    PARAMETER nm, p, g.
    IF NOT adSpr:HASKEY(nm) { RETURN FALSE. }
    LOCAL sp IS adSpr[nm].
    LOCAL l IS ROUND(p[0] - sp[3]).
    LOCAL t IS ROUND(p[1] - sp[4]).
    RETURN l >= g[0] + AD_FIT_IN AND l + sp[1] <= g[0] + g[2] - AD_FIT_IN AND t >= g[1] + AD_FIT_IN
        AND t + sp[2] <= g[1] + g[3] - AD_FIT_IN.
}

FUNCTION adHold {
    PARAMETER nm, p, g.
    IF NOT adSpr:HASKEY(nm) { RETURN p. }
    LOCAL sp IS adSpr[nm].
    RETURN LIST(MAX(g[0] + sp[3] + AD_FIT_IN, MIN(g[0] + g[2] - sp[1] + sp[3] - AD_FIT_IN, p[0])),
                MAX(g[1] + sp[4] + AD_FIT_IN, MIN(g[1] + g[3] - sp[2] + sp[4] - AD_FIT_IN, p[1]))).
}

FUNCTION adBarX {                           // the VI bar's x for vi (clamped): x0 x1 y v0 v1
    PARAMETER g, vi.
    RETURN g[0] + (MIN(MAX(vi, g[3]), g[4]) - g[3]) / (g[4] - g[3]) * (g[1] - g[0]).
}

FUNCTION adInterp {                         // y at x on the (x, y) pairs of a sidecar line (x rising)
    PARAMETER pr, x.
    IF x <= pr[0] { RETURN pr[1]. }
    FROM { LOCAL i IS 2. } UNTIL i >= pr:LENGTH STEP { SET i TO i + 2. } DO {
        IF x <= pr[i] { RETURN pr[i - 1] + (x - pr[i - 2]) / (pr[i] - pr[i - 2]) * (pr[i + 1] - pr[i - 1]). }
    }
    RETURN pr[pr:LENGTH - 1].
}

FUNCTION adB {                              // boundary k's VI (ft/s): the predictor's, else the sidecar's
    PARAMETER asc, k.
    IF asc:HASKEY("abr") {
        IF asc["abr"]["b"]:HASKEY(k) { RETURN asc["abr"]["b"][k] / AD_FT. }
    }
    RETURN adBnd[k].
}

FUNCTION adCont {                           // the contingency with n SSMEs out at vi (ft/s): GREEN = it steers for an ELS
    PARAMETER asc, n, vi.                   // runway (asc_abr_site, the one lookup), BLUE = none in reach
    IF NOT asc:HASKEY("abr") { RETURN "CONT". }
    IF asc_abr_site(n, vi * AD_FT) = "NONE" { RETURN "BLUE". }
    RETURN "GREEN".
}

// The 1EO / 2EO / 3EO lines: the modes open at this VI (ft/s), best first, at the predictor's boundaries (the ARD's
// from the state): PRESS alone once open; else ATO, TAL (from their marks), RTLS (to NEG RTN); with none open the
// contingency's BLUE / GREEN. After the first SSME out the 1EO line is locked at the line at the failure (ops1q's
// asc["eo1_ln"]); an abort selected (with or without an SSME out) is the line alone.
FUNCTION adModes {
    PARAMETER asc, vi.
    LOCAL one IS "PRESS".
    IF vi < adB(asc, "PRESS") {
        SET one TO "".
        IF vi >= adB(asc, "ATO") { SET one TO "ATO ". }
        IF vi >= adB(asc, "E_TAL") { SET one TO one + "TAL ". }
        IF vi < adB(asc, "NEG_RTN") { SET one TO one + "RTLS". }
        SET one TO one:TRIM.
        IF one = "" { SET one TO adCont(asc, 1, vi). }
    }
    IF asc:HASKEY("eo1_ln") { IF asc["eo1_ln"] <> "" { SET one TO asc["eo1_ln"]. } }
    IF asc:HASKEY("abort") { IF asc["abort"] <> "" AND asc["abort"] <> "CONT" { SET one TO asc["abort"]. } }
    LOCAL two IS "PRESS".
    IF vi < adB(asc, "PRESS_2EO") {
        SET two TO "".
        IF vi >= adB(asc, "ATO_2EO") { SET two TO "ATO ". }
        IF vi >= adB(asc, "TAL_2EO") { SET two TO two + "TAL". }
        SET two TO two:TRIM.
        IF two = "" { SET two TO adCont(asc, 2, vi). }
    }
    LOCAL three IS adCont(asc, 3, vi).
    IF asc:HASKEY("eo3_ln") { IF asc["eo3_ln"] <> "" { SET three TO asc["eo3_ln"]. } }   // ops1q's 3EO pick
    RETURN LIST(one, two, three).
}

FUNCTION adCo {                             // CO's VI (ft/s): PEG's MECO speed (an abort's once it has its target)
    PARAMETER asc.
    IF asc["s2_on"] { RETURN asc["g"]["peg"]["VDMAG"] / AD_FT. }
    RETURN ASC_VDMAG / AD_FT.
}

// the engine-out level of mark k (1 the 1EO's, 2 the 2EO's) and the levels frozen now (the SSMEs out less one, up
// to 2: a 2EO freezes the 1EO, a 3EO the 1EO and the 2EO)
FUNCTION adTickLv {
    PARAMETER k.
    RETURN CHOOSE 1 IF AD_TICKS_1EO:CONTAINS(k) ELSE 2.
}

FUNCTION adFrzLv {
    RETURN MIN(2, MAX(0, adOut:LENGTH - 1)).
}

FUNCTION adFrzLvTk {                        // the marks' levels frozen (the SSMEs out, up to 2)
    IF AD_TICK_FRZ_1EO { RETURN MIN(2, adOut:LENGTH). }
    RETURN adFrzLv().
}

// mark k still useful with the abort selected: the 1EO marks by AD_TICK_1EO (a selection keeps its own mark only); the
// 2EO marks the modes a second SSME out can still fly with it (asc_2eo_go, the ARD's levels: none selected all three;
// ATO the 2EO ATO and TAL, no 2EO PRESS; TAL the 2EO TAL only; an RTLS (its colour word) and the contingency none)
FUNCTION adTickRel {
    PARAMETER asc, k.
    LOCAL sel IS "".
    IF asc:HASKEY("abort") { SET sel TO asc["abort"]. }
    IF AD_TICKS_1EO:CONTAINS(k) {
        IF AD_TICK_1EO:HASKEY(sel) { RETURN k = AD_TICK_1EO[sel]. }
        RETURN TRUE.
    }
    IF sel = "" { RETURN TRUE. }
    IF sel = "ATO" OR sel = "AOA" { RETURN k <> "PRESS_2EO". }
    IF sel = "TAL" { RETURN k = "TAL_2EO". }
    RETURN FALSE.
}

// the 2EO readout before a second SSME is out, as asc_2eo_go would fly it with the abort selected: TAL selected,
// any mode open flies the TAL; ATO selected, PRESS flies the ATO (the TAL stays a TAL); the contingency's colour as is
FUNCTION adRel2 {
    PARAMETER sel, tx.
    LOCAL ws IS tx:SPLIT(" ").
    LOCAL op IS ws:CONTAINS("PRESS") OR ws:CONTAINS("ATO") OR ws:CONTAINS("TAL").
    IF NOT op { RETURN tx. }
    IF sel = "TAL" { RETURN "TAL". }
    IF sel = "ATO" OR sel = "AOA" {
        LOCAL out IS LIST().
        FOR w IN ws {
            LOCAL w2 IS CHOOSE "ATO" IF w = "PRESS" ELSE w.
            IF NOT out:CONTAINS(w2) { out:ADD(w2). }
        }
        RETURN out:JOIN(" ").
    }
    RETURN tx.
}

// The marks on VI bar g (x0 x1 y v0 v1; CO at co ft/s, < 0 none): a 1 px tick each (barlab_px's half-lengths: a mark,
// CO), their labels centred on barlab_px's three rows, packed left to right in VI order, each on the first row with
// room after the last label there (the gap barlab_px[5]), else the last row (the background generator's rule).
FUNCTION adTicks {
    PARAMETER asc, g, co.
    LOCAL bl IS adGeo["barlab_px"].
    LOCAL t IS LIST().
    LOCAL fz IS adFrzLvTk().                // the marks' levels (the readouts': adFrzLv)
    UNTIL adFrzNM >= fz {                   // a level frozen: its marks shown now, caught
        SET adFrzNM TO adFrzNM + 1.
        FOR k IN AD_TICKS { IF adTickLv(k) = adFrzNM AND adTickRel(asc, k) { SET adFrzM[k] TO adB(asc, k). } }
    }
    FOR k IN AD_TICKS {
        LOCAL vk IS -1.
        LOCAL dim IS adTickLv(k) <= adFrzNM.
        IF dim { IF adFrzM:HASKEY(k) AND (adTickRel(asc, k) OR NOT AD_TICK_FRZ_1EO) { SET vk TO adFrzM[k]. } }
        ELSE IF adTickRel(asc, k) { SET vk TO adB(asc, k). }
        IF vk >= g[3] AND vk <= g[4] { t:ADD(LIST(vk, AD_TICK_LAB[k], bl[3], dim)). }
    }
    IF co >= g[3] AND co <= g[4] { t:ADD(LIST(co, "CO", bl[4], FALSE)). }
    FROM { LOCAL i IS 1. } UNTIL i >= t:LENGTH STEP { SET i TO i + 1. } DO {
        FROM { LOCAL j IS i. } UNTIL j < 1 STEP { SET j TO j - 1. } DO {
            IF t[j - 1][0] > t[j][0] { LOCAL tq IS t[j]. SET t[j] TO t[j - 1]. SET t[j - 1] TO tq. }
        }
    }
    LOCAL last IS LIST(-999, -999, -999).
    FROM { LOCAL i IS 0. } UNTIL i >= MIN(t:LENGTH, 8) STEP { SET i TO i + 1. } DO {
        LOCAL x IS adBarX(g, t[i][0]).
        adBarFill(adS["tk" + i], CHOOSE adFillDim IF t[i][3] ELSE adFill).
        adBar(adS["tk" + i], x - 0.5, g[2] - t[i][2], x + 0.5, g[2] + t[i][2]).
        LOCAL w IS t[i][1]:LENGTH * AD_TICK_CW.
        LOCAL rw IS 2.
        FROM { LOCAL j IS 2. } UNTIL j < 0 STEP { SET j TO j - 1. } DO { IF x - w / 2 > last[j] + bl[5] { SET rw TO j. } }
        SET last[rw] TO x + w / 2.
        adText(adS["tl" + i], CHOOSE "<color=" + AD_DIM + ">" + t[i][1] + "</color>" IF t[i][3] ELSE t[i][1], x, bl[rw], 2).
    }
}

// The SSMEs by position, once all three are known: C the apex of their isosceles triangle (seen from behind), L and R
// the base's ends, R on the right of the C side (in the body frame: x star, y top, z nose; any roll of the control part)
FUNCTION adEngIds {
    PARAMETER engs.
    IF adIds:HASKEY("C") OR engs:LENGTH <> 3 { RETURN adIds. }
    LOCAL inv IS SHIP:FACING:INVERSE.
    LOCAL bq IS LIST().
    FOR en IN engs { LOCAL b IS inv * en:POSITION. bq:ADD(V(b:X, b:Y, 0)). }
    LOCAL best IS -1.
    LOCAL ia IS 0.
    FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
        LOCAL j IS MOD(i + 1, 3).
        LOCAL k IS MOD(i + 2, 3).
        LOCAL d IS ABS((bq[i] - bq[j]):MAG - (bq[i] - bq[k]):MAG).        // the apex is equidistant from the other two
        IF best < 0 OR d < best { SET best TO d. SET ia TO i. }
    }
    LOCAL j0 IS MOD(ia + 1, 3).
    LOCAL k0 IS MOD(ia + 2, 3).
    LOCAL mid IS (bq[j0] + bq[k0]) / 2.
    LOCAL u IS bq[ia] - mid.
    LOCAL rt IS V(u:Y, -u:X, 0).
    SET adIds["C"] TO engs[ia].
    IF VDOT(bq[j0] - mid, rt) > 0 { SET adIds["R"] TO engs[j0]. SET adIds["L"] TO engs[k0]. }
    ELSE { SET adIds["L"] TO engs[j0]. SET adIds["R"] TO engs[k0]. }
    SET adIds["rt"] TO rt.
    RETURN adIds.
}

FUNCTION adSrbIds {                         // the SRBs, left and right of the SSMEs' C side
    PARAMETER srbs.
    IF adIds:HASKEY("SL") OR srbs:LENGTH <> 2 OR NOT adIds:HASKEY("rt") { RETURN. }
    LOCAL inv IS SHIP:FACING:INVERSE.
    LOCAL b0 IS inv * srbs[0]:POSITION.
    LOCAL b1 IS inv * srbs[1]:POSITION.
    IF VDOT(V(b0:X - b1:X, b0:Y - b1:Y, 0), adIds["rt"]) > 0 { SET adIds["SR"] TO srbs[0]. SET adIds["SL"] TO srbs[1]. }
    ELSE { SET adIds["SL"] TO srbs[0]. SET adIds["SR"] TO srbs[1]. }
}

// the MESSAGES' colours: an SSME out red; an abort, its throttle-up and the 2EO / 3EO lines (the split-S, BLUE / GREEN,
// the 2EO TAL) yellow; the abort search's own notices (ABORT FLIGHTS, ABORT REFRESH) and the rest in the page's green
GLOBAL AD_MSG_YEL IS LIST("ABORT", "2EO", "3EO", "RTLS 2EO", "RTLS 3EO", "SPLIT-S", "BAILOUT", "OMS ASSIST:").
GLOBAL AD_MSG_GRN IS LIST("ABORT FLIGHTS", "ABORT REFRESH").
FUNCTION adMsgCol {                         // the message's colour ("" = the page's)
    PARAMETER s.
    IF s:CONTAINS("SSME ") AND (s:CONTAINS(" FAIL") OR s:CONTAINS(" OUT")) { RETURN AD_RED. }   // SSME 2 FAIL, RSLS ABORT: SSME 2 OUT
    FOR p IN AD_MSG_GRN { IF s:STARTSWITH(p) { RETURN "". } }
    FOR p IN AD_MSG_YEL { IF s:STARTSWITH(p) { RETURN AD_YELLOW. } }
    RETURN "".
}

FUNCTION adEvent {                          // a message (newest first); the page redraws at the next tick
    PARAMETER met, msg.
    LOCAL s IS msg.
    IF AD_REN:HASKEY(msg) { SET s TO AD_REN[msg]. }
    IF s = "" { RETURN. }
    LOCAL mline IS "T+" + adMmss(met) + "  " + s.
    LOCAL c IS adMsgCol(s).
    adMsgs:INSERT(0, CHOOSE mline IF c = "" ELSE "<color=" + c + ">" + mline + "</color>").
    IF adMsgs:LENGTH > 30 { adMsgs:REMOVE(30). }
    SET adNext TO 0.
}

// ---- the state each update: the vehicle, the stage, the predictors' rates
FUNCTION adState {
    PARAMETER asc.
    LOCAL st IS LEXICON().
    LOCAL now IS TIME:SECONDS.
    LOCAL met IS 0.
    IF asc["t_lo"] >= 0 { SET met TO now - asc["t_lo"]. }
    LOCAL ph IS asc["phase"].
    SET st["met"] TO met.
    SET st["ph"] TO ph.
    SET st["s1"] TO ph = "PAD" OR ph = "STAGE1".
    SET st["after"] TO asc["t_meco"] >= 0.
    SET st["vrel"] TO SHIP:VELOCITY:SURFACE:MAG.
    SET st["vi"] TO SHIP:VELOCITY:ORBIT:MAG.
    SET st["h"] TO SHIP:ALTITUDE.
    SET st["hdot"] TO SHIP:VERTICALSPEED.
    // an RTLS (adTrajR2): VH, the horizontal relative speed away from the site (+) or toward it (-); the MECO line
    SET st["vh"] TO 0.
    LOCAL rl IS LEXICON().
    IF asc:HASKEY("rl") { SET rl TO asc["rl"]. }
    IF rl:LENGTH > 0 {
        LOCAL sm IS asc_sample(asc["fr"], now).
        LOCAL aw IS VXCL(sm[1], sm[1] - asc_rotz(rl["ef"], rl["w"] * met)):NORMALIZED.
        SET st["vh"] TO VDOT(sm[2] - asc_rtls_wxr(rl, sm[1]), aw).
        SET st["vl"] TO asc_rtls_vline(rl, met, sm[1], sm[2], 0).
    }
    LOCAL fs IS 0.
    LOCAL pk IS 0.
    adEngIds(asc["ssme"]).
    IF st["s1"] {
        adSrbIds(asc["srbs"]).
        FOR en IN asc["srbs"] {
            LOCAL f IS en:THRUST.
            SET fs TO fs + f.
            IF NOT adPk:HASKEY(en:UID) { SET adPk[en:UID] TO f. }       // (no AND / OR on a key that may be missing)
            IF f > adPk[en:UID] { SET adPk[en:UID] TO f. }
            SET pk TO pk + adPk[en:UID].
        }
    }
    SET st["fsrb"] TO fs.
    SET st["fsrb_pk"] TO pk.
    LOCAL fl IS 0.
    FOR en IN asc["ssme"] { SET fl TO fl + en:THRUST. }
    IF asc:HASKEY("oms") { FOR en IN asc["oms"] { SET fl TO fl + en:THRUST. } }       // the TAL OMS dump
    SET st["g"] TO (fs + fl) / (SHIP:MASS * CONSTANT:G0).
    SET st["keas"] TO SQRT(2 * SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA * 1000 / AD_RHO0) / AD_KT.   // KEAS
    adHist:ADD(LIST(now, st["vrel"], st["vi"], st["h"], st["hdot"], st["vh"])).
    UNTIL adHist:LENGTH <= 1 OR now - adHist[0][0] <= AD_HIST_S { adHist:REMOVE(0). }
    LOCAL o IS adHist[0].
    LOCAL dt IS now - o[0].
    SET st["vreld"] TO 0. SET st["vid"] TO 0. SET st["hdd"] TO 0. SET st["vhd"] TO 0.
    IF dt >= 1 AND met > 0 {
        SET st["vreld"] TO (st["vrel"] - o[1]) / dt.
        SET st["vhd"] TO (st["vh"] - o[5]) / dt.
        SET st["vid"] TO (st["vi"] - o[2]) / dt.
        SET st["hdd"] TO (st["hdot"] - o[4]) / dt.
    }
    RETURN st.
}

FUNCTION adPred {                           // the predicted (x ft/s, H kft) dt s ahead: speed order 1, H order 2
    PARAMETER st, key, dt.
    LOCAL x IS st[key] + st[key + "d"] * dt.
    LOCAL h IS st["h"] + st["hdot"] * dt + 0.5 * st["hdd"] * dt * dt.
    RETURN LIST(x / AD_FT, h / AD_FT / 1000).
}

// SW 02 GUIDANCE LOST on the ascent (lib_ascent_s2 asc_gdl's test): the GUID text and the CMD (attitude error) rows show "----" / "---"
FUNCTION adGdLost {
    IF DEFINED FLFX_SWPROG { RETURN flfxSwGuid("ASCENT"). }
    RETURN FALSE.
}

// GUID: READY on the pad, OPEN LOOP in stage 1, then PEG's state (ops1q's console words), the MECO cause after MECO
FUNCTION adGuid {
    PARAMETER asc, st.
    IF st["after"] {
        IF asc["why"] = "res" { RETURN "MECO LOW LVL". }
        IF asc["why"] = "out" { RETURN "MECO ENG OUT". }
        IF asc["why"] = "esep" { RETURN "EMERGENCY SEP". }
        RETURN "MECO CUT".
    }
    IF st["ph"] = "PAD" {                  // the countdown's text (T-30 HOLD, T-12, T-0) in place of READY
        IF asc:HASKEY("cd_txt") { IF asc["cd_txt"] <> "" { RETURN asc["cd_txt"]. } }
        RETURN "READY".
    }
    IF adGdLost() { RETURN "----". }       // SW 02 holds the ascent guidance
    IF NOT asc["s2_on"] { RETURN "OPEN LOOP". }
    LOCAL g IS asc["g"].
    LOCAL p IS g["peg"].
    IF g["S_MECO"] {
        IF g["T_MECO"] >= 0 { RETURN "MECO SET". }
        RETURN "FINE COUNT".
    }
    // UNCONV in yellow
    RETURN CHOOSE "CONV" IF p["SCONV"] ELSE "<color=" + AD_YELLOW + ">UNCONV " + p["unconv"] + "</color>".
}

FUNCTION adTgo {                            // s to MECO (-1 = none): PEG's TGO, the fine count's, the set MECO time's
    PARAMETER asc, st.
    IF st["after"] OR NOT asc["s2_on"] { RETURN -1. }
    LOCAL g IS asc["g"].
    IF g["S_MECO"] {
        IF g["T_MECO"] >= 0 { RETURN MAX(0, g["T_MECO"] - st["met"]). }
        IF g["TGO_FC"] >= 0 { RETURN g["TGO_FC"]. }
    }
    RETURN g["peg"]["TGO"].
}

FUNCTION adRoll {
    PARAMETER asc, st.
    IF st["ph"] = "PAD" { RETURN "". }
    IF st["s1"] {                           // the roll program: the rise, then until the command reaches the tables'
        IF NOT asc["s1"]["clear"] OR asc["slew"] { RETURN "ROLL PGM". }
        RETURN "HEADS DOWN".
    }
    IF asc["t_roll"] < 0 { RETURN "HEADS DOWN". }
    IF ASC_ROLL_RATE * (st["met"] - asc["t_roll"]) < 180 { RETURN "ROLLING". }
    RETURN "HEADS UP".
}

FUNCTION adRpyErr {                         // the attitude errors (deg) from the facing (fore ff, top ft, starboard
    PARAMETER ff, ft, fs, tf, tt.           // fs) to the target (fore tf, top tt): LIST(roll, pitch, yaw), fly-to
    // (roll + = right: the top toward the right wing; pitch + = up: the nose toward the canopy side; yaw + = right).
    // Pitch and yaw: the nose's turn to tf, its angle split by its direction in the facing's top / starboard plane;
    // roll: what is left about tf after that turn (the turn's formula has VCRS twice: right in kOS's left-handed
    // raw frame too). Straight ahead (0.0001 deg) or within 0.08 deg of behind: the roll of the tops, the turn pitch.
    LOCAL a IS VDOT(tf, ft).
    LOCAL b IS VDOT(tf, fs).
    LOCAL c IS VDOT(tf, ff).
    LOCAL m IS SQRT(a * a + b * b).
    LOCAL ang IS ARCTAN2(m, c).
    IF m < 0.000001 OR c < -0.999999 { RETURN LIST(ARCTAN2(VDOT(tt, fs), VDOT(tt, ft)), ang, 0). }
    LOCAL k IS VCRS(ff, tf).
    LOCAL tp IS ft * c + VCRS(k, ft) + k * (VDOT(k, ft) / (1 + c)).
    LOCAL sp IS fs * c + VCRS(k, fs) + k * (VDOT(k, fs) / (1 + c)).
    RETURN LIST(ARCTAN2(VDOT(tt, sp), VDOT(tt, tp)), ang * a / m, ang * b / m).
}

FUNCTION adRpy {                            // the attitude errors to ops1q's steering target asc["dir"], fly-to letters
    PARAMETER asc, key.                     // (kOS's steering and the EO DAP alike; STEERINGMANAGER's freeze under
    LOCAL g IS adGeo[key].                  // the DAP)
    LOCAL er IS LIST(0, 0, 0).
    IF asc:HASKEY("dir") {
        LOCAL fc IS SHIP:FACING.
        LOCAL tg IS asc["dir"].
        SET er TO adRpyErr(fc:FOREVECTOR, fc:TOPVECTOR, fc:STARVECTOR, tg:FOREVECTOR, tg:TOPVECTOR).
    }
    LOCAL ng IS LIST("L", "D", "L").
    LOCAL ps IS LIST("R", "U", "R").
    LOCAL gl IS adGdLost().                 // SW 02 GUIDANCE LOST: the CMD rows blank
    FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
        LOCAL ae IS er[i].
        LOCAL n IS ROUND(ABS(ae)).
        LOCAL s IS " 00".
        IF gl { SET s TO "---". }
        ELSE IF n > 0 { SET s TO (CHOOSE ps[i] IF ae >= 0 ELSE ng[i]) + (CHOOSE "0" IF n < 10 ELSE "") + MIN(n, 99). }
        adText(adS["r" + i], s, g[0], g[1 + i], 0).
    }
}

FUNCTION adCol {                            // a column of values, right-aligned at its x
    PARAMETER key, pre, vals.
    LOCAL g IS adGeo[key].
    FROM { LOCAL i IS 0. } UNTIL i >= vals:LENGTH STEP { SET i TO i + 1. } DO {
        adText(adS[pre + i], vals[i], g[0], g[1 + i], 1).
    }
}

FUNCTION adHilite {                         // the line s with its word w in yellow (the words split by one space)
    PARAMETER s, w.
    LOCAL ws IS s:SPLIT(" ").
    LOCAL k IS ws:INDEXOF(w).
    IF k < 0 { RETURN s. }
    SET ws[k] TO "<color=" + AD_YELLOW + ">" + ws[k] + "</color>".
    RETURN ws:JOIN(" ").
}

// The 1EO / 2EO / 3EO lines as the pages draw them (md = adModes' three). The 2EO modes locked: after the second SSME
// out the 2EO line holds ops1q's asc["eo2_ln"] (the line at the failure, then the mode flown: the 2EO PRESS / ATO / TAL,
// the contingency's GREEN / BLUE); here, not in adModes, whose line MODE SEL reads (asc_2eo_line) from the marks. The
// selected abort in yellow: on the 1EO / 2EO lines the selector's mode, the running abort's once ABORT is pushed, the
// contingency's colour word while it flies (the 3EO line: below); on the 2EO line only once the second SSME is out
// (asc["eo2_ln"] set: a 1EO TAL's 2EO TAL stays green)
FUNCTION adLines {
    PARAMETER asc, md.
    LOCAL lns IS LIST(md[0], md[1], md[2]).
    // in an RTLS the 2EO line is ops1q's RTLS colour (asc["rl2_ln"]: GREEN / ORANGE / RED / RTLS, what a second SSME
    // out flies now), not the uphill table's
    IF asc:HASKEY("rl2_ln") { IF asc["rl2_ln"] <> "" AND asc["rl"]:LENGTH > 0 { SET lns[1] TO asc["rl2_ln"]. } }
    LOCAL two IS FALSE.                     // a 2EO (or the split-S): only then the 2EO line's word in yellow
    IF asc:HASKEY("eo2_ln") { IF asc["eo2_ln"] <> "" { SET lns[1] TO asc["eo2_ln"]. SET two TO TRUE. } }
    LOCAL sel IS "".                        // the mode flown alone (the Mode list shows the pick)
    LOCAL cnt IS FALSE.
    IF asc:HASKEY("abort") {
        IF asc["abort"] = "CONT" { SET cnt TO TRUE. } ELSE IF asc["abort"] <> "" { SET sel TO asc["abort"]. }
    }
    IF NOT two AND sel <> "RTLS" { SET lns[1] TO adRel2(sel, lns[1]). }   // what a 2EO would fly now
    FROM { LOCAL i IS 0. } UNTIL i > 1 STEP { SET i TO i + 1. } DO {
        LOCAL w IS sel.
        IF i = 1 AND (cnt OR (two AND sel = "RTLS")) { SET w TO lns[1]. }   // an RTLS's 2EO, its colour word
        IF w <> "" AND ((i = 0 AND adOut:LENGTH > 0) OR two) { SET lns[i] TO adHilite(lns[i], w). }   // yellow: an SSME out
    }
    // once a third SSME is out the 3EO line's word (the mode flown, e.g. SPLITS: ops1q's asc["eo3_ln"]) in yellow, as
    // the 2EO line's above
    IF adOut:LENGTH >= 3 AND lns[2] <> "" { SET lns[2] TO "<color=" + AD_YELLOW + ">" + lns[2] + "</color>". }
    LOCAL fz IS adFrzLv().                  // the lower levels frozen, dark green
    UNTIL adFrzNL >= fz {
        SET adFrzL[adFrzNL] TO lns[adFrzNL]:REPLACE("<color=" + AD_YELLOW + ">", ""):REPLACE("</color>", "").
        SET adFrzNL TO adFrzNL + 1.
    }
    FROM { LOCAL i IS 0. } UNTIL i >= adFrzNL STEP { SET i TO i + 1. } DO {
        SET lns[i] TO CHOOSE "" IF adFrzL[i] = "" ELSE "<color=" + AD_DIM + ">" + adFrzL[i] + "</color>".
    }
    RETURN lns.
}

FUNCTION adMode {                           // the abort's title word ("ascent" until an abort: asc["abort"])
    PARAMETER asc, allowed.
    IF asc:HASKEY("abort") { IF allowed:CONTAINS(asc["abort"]) { RETURN asc["abort"]:TOLOWER. } }
    RETURN "ascent".
}

// ---- the pages
FUNCTION adCommon {                         // the clock, the abort modes, the MESSAGES ("" TRAJ, "e" OMS/MPS)
    PARAMETER asc, st, pre.
    LOCAL ck IS adGeo["clock_px"].
    adText(adS[pre + "met"], adClock(st["met"]), ck[0], ck[1] - AD_HDR_DY, 1).     // clock_px: the header's baseline
    LOCAL ab IS adGeo["abt_px"].
    IF NOT st["after"] {
        LOCAL md IS adLines(asc, adModes(asc, st["vi"] / AD_FT)).
        FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO { adText(adS[pre + "ab" + i], md[i], ab[1], ab[2 + i], 0). }
    }
    LOCAL mp IS adGeo["msg_px"].
    LOCAL r0 IS 0.
    IF adWarn <> "" { adText(adS[pre + "warn"], adWarn, mp[0], mp[1], 0). SET r0 TO 1. }
    FROM { LOCAL i IS 0. } UNTIL i + r0 > 2 OR i >= adMsgs:LENGTH STEP { SET i TO i + 1. } DO {
        adText(adS[pre + "m" + (i + r0)], adMsgs[i], mp[0], mp[1 + i + r0], 0).
    }
}

FUNCTION adTraj1 {
    PARAMETER asc, st.
    IF st["ph"] = "PAD" { adSetBg("t1_launch"). } ELSE { adSetBg("t1_" + adMode(asc, LIST("RTLS", "TAL"))). }
    LOCAL bg IS adGeo["bar1_px"].
    adPut(adS["bar"], "bartri", adBarX(bg, st["vi"] / AD_FT), bg[2]).
    IF st["ph"] <> "PAD" { adTicks(asc, bg, -1). }   // none before liftoff (the pad would show the nominal-mass marks)
    LOCAL k IS adGeo["t1_keas_px"].
    adPut(adS["ptr1"], "ewtri", k[0], adScaleY(k, st["keas"])).
    adRpy(asc, "t1_rpy_px").
    LOCAL p IS adHold("veh", adField(1, st["vrel"] / AD_FT, st["h"] / AD_FT / 1000, TRUE), adGeo["t1_field_px"]).
    adPut(adS["veh"], "veh", p[0], p[1]).
    IF st["met"] > 0 {
        LOCAL pr IS adPred(st, "vrel", adGeo["pred_s"][0]).
        LOCAL pt IS adField(1, pr[0], pr[1], FALSE).
        IF pt:LENGTH = 2 { IF adFits("pred", pt, adGeo["t1_field_px"]) { adPut(adS["p1"], "pred", pt[0], pt[1]). } }
    }
    LOCAL pc IS "".
    // PC<: shown from 2-3 s before the SRB separation (asc_bg's pclo: the share of the SRB peak thrust, and the chamber
    // psi the message shows)
    IF st["fsrb"] > 0 AND st["fsrb"] < adGeo["pclo"][0] * st["fsrb_pk"] { SET pc TO "PC<" + adGeo["pclo"][1]. }
    adCol("t1_lr_px", "lr", LIST(adPl(asc["kcmd"]), pc)).
    adCol("t1_col_px", "c", LIST(adFx(st["h"] / 1000, 1) + "K", "" + ROUND(st["vrel"]),
        adSgn(st["hdot"]), adGuid(asc, st), adRoll(asc, st))).
}

FUNCTION adTraj2 {
    PARAMETER asc, st.
    adSetBg("t2_" + adMode(asc, LIST("TAL", "ATO", "AOA"))).
    LOCAL vi IS st["vi"] / AD_FT.
    LOCAL bg IS adGeo["bar2_px"].
    adPut(adS["bar"], "bartri", adBarX(bg, vi), bg[2]).
    adTicks(asc, bg, adCo(asc)).
    LOCAL k IS adGeo["t2_dhd_px"].
    adPut(adS["ptr1"], "ewtri", k[0], adScaleY(k, st["hdot"] / AD_FT - adInterp(adGeo["hdnom"], vi))).
    LOCAL hp IS adGeo["t2_hdot_px"].
    adText(adS["hdot"], adSgn(st["hdot"]), hp[0], hp[1], 1).
    adRpy(asc, "t2_rpy_px").
    LOCAL p IS adHold("veh", adField(2, vi, st["h"] / AD_FT / 1000, TRUE), adGeo["t2_field_px"]).
    adPut(adS["veh"], "veh", p[0], p[1]).
    IF NOT st["after"] {
        LOCAL ps IS adGeo["pred_s"].
        FROM { LOCAL i IS 1. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
            LOCAL pr IS adPred(st, "vi", ps[i]).
            LOCAL pt IS adField(2, pr[0], pr[1], FALSE).
            IF pt:LENGTH = 2 { IF adFits("pred", pt, adGeo["t2_field_px"]) { adPut(adS["p" + i], "pred", pt[0], pt[1]). } }
        }
    }
    LOCAL gk IS adGeo["t2_g_px"].
    adPut(adS["ptr2"], "ewtri", gk[0], adScaleY(gk, st["g"])).
    LOCAL tgo IS adTgo(asc, st).
    LOCAL pp IS "".
    IF NOT st["after"] AND asc["et_full"] > 0 { SET pp TO "" + ROUND(100 * asc_burnable(asc["ssme"]) / asc["et_full"]). }
    LOCAL tm IS "".
    IF st["after"] { SET tm TO adMmss(asc["t_meco"]). } ELSE IF tgo >= 0 { SET tm TO adMmss(st["met"] + tgo). }
    adCol("t2_lr_px", "lr", LIST(adPl(asc["kcmd"]), pp, tm)).
    // DROOP ALT: the DPS dictionary's DROOP item (ASCENT TRAJ 2, item 19): the word and PRED_DROOP_ALT (km;
    // lib_ascent_cnt's droop) in stage 2 until MECO, a row just above THROT / PRPLT / TMECO, blank while the contingency
    // flies; the whole row yellow from DROOP ENGAGED to DROOP DONE (S_CDROOP; A deviation: the real one is overbright
    // only while the task commands the pitch, from DROOP STEERS); no flashing
    LOCAL drs IS asc:HASKEY("drp") AND NOT st["after"].
    IF drs AND asc["cn"]:LENGTH > 0 { SET drs TO NOT asc["cn"]["on"]. }
    IF drs {
        LOCAL dr IS asc["drp"].
        IF dr["ok"] {
            LOCAL lr IS adGeo["t2_lr_px"].
            LOCAL dw IS "DROOP".
            LOCAL dn IS "" + ROUND(dr["PRED"] / 1000) + "K".
            IF dr["S_CDROOP"] {
                SET dw TO "<color=" + AD_YELLOW + ">" + dw + "</color>".
                SET dn TO "<color=" + AD_YELLOW + ">" + dn + "</color>".
            }
            adText(adS["dr0"], dw, AD_DRP_X, 2 * lr[1] - lr[2], 0).
            adText(adS["dr1"], dn, lr[0], 2 * lr[1] - lr[2], 1).
        }
    }
    LOCAL ts IS "".
    IF st["after"] { SET ts TO "0:00". } ELSE IF tgo >= 0 { SET ts TO adMmss(tgo). }
    LOCAL ha IS "".
    LOCAL hpe IS "".
    IF st["after"] { SET ha TO "" + ROUND(SHIP:APOAPSIS / 1000) + "K". SET hpe TO "" + ROUND(SHIP:PERIAPSIS / 1000) + "K". }
    LOCAL hm IS ASC_MECO_H.                 // the MECO target: PEG's (a TAL's once selected)
    LOCAL gm IS ASC_GAMD.
    IF asc["s2_on"] { SET hm TO asc["g"]["peg"]["RDMAG"] - ASC_R. SET gm TO asc["g"]["peg"]["GAMD"]. }
    adCol("t2_col_px", "c", LIST(ts, adGuid(asc, st), adRoll(asc, st), "" + ROUND(st["vi"]),
        adFx(st["h"] / 1000, 1) + "K", adFx(hm / 1000, 1) + "K", adFx(gm, 2), ha, hpe)).
}

// the RTLS page's TMECO blank in the fuel dissipation and the pitcharound; after it, shown once the predicted MECO MET
// has drifted at most AD_TM_DRIFT s/s pass to pass for AD_TM_HOLD s (the same test as lib_ascent_rtls's on the PPA
// timer, its numbers); once shown, a step over AD_TM_JUMP s hides it again (the test starts over). AD_TM_WAIT FALSE:
// shown whenever predicted.
GLOBAL AD_TM_WAIT IS TRUE.
GLOBAL AD_TM_DRIFT IS 0.5.   // s/s
GLOBAL AD_TM_HOLD IS 10.     // s
GLOBAL AD_TM_JUMP IS 5.      // s: a step in the predicted MECO MET from one pass to the next
GLOBAL adTmS IS LEXICON("p", -1, "t", -1, "ok", -1, "on", FALSE).
FUNCTION adTmSettle {                  // TRUE: show TMECO (md: the RTLS mode, t: the MET, mc: the predicted MECO MET, -1 none)
    PARAMETER md, t, mc.
    IF NOT AD_TM_WAIT { RETURN mc >= 0. }
    IF md = "fd" OR md = "turn" OR mc < 0 {
        SET adTmS["on"] TO FALSE. SET adTmS["ok"] TO -1. SET adTmS["p"] TO -1.
        RETURN FALSE.
    }
    IF adTmS["p"] < 0 { SET adTmS["p"] TO mc. SET adTmS["t"] TO t. RETURN adTmS["on"]. }
    IF t < adTmS["t"] + 0.05 { RETURN adTmS["on"]. }
    LOCAL dm IS ABS(mc - adTmS["p"]).
    IF adTmS["on"] {
        IF dm > AD_TM_JUMP { SET adTmS["on"] TO FALSE. SET adTmS["ok"] TO -1. }
    } ELSE IF dm / (t - adTmS["t"]) <= AD_TM_DRIFT {
        IF adTmS["ok"] < 0 { SET adTmS["ok"] TO adTmS["t"]. }
        IF t - adTmS["ok"] >= AD_TM_HOLD { SET adTmS["on"] TO TRUE. }
    } ELSE {
        SET adTmS["ok"] TO -1.
    }
    SET adTmS["p"] TO mc.
    SET adTmS["t"] TO t.
    RETURN adTmS["on"].
}

// RTLS TRAJ 2: the delta-R triangle on the flyback only (VH < 0: the range
// short of the MECO line at this speed, (VREL - V_line) / A6, nm), the vehicle on the VH-H field, the 30 / 60 s
// predictors, g, R/P/Y, THROT / PRPLT / TMECO; TGO to MECO, GUID, MODE, VREL, H, HDOT, ALPHA, BETA, RNG (to the site)
FUNCTION adTrajR2 {
    PARAMETER asc, st.
    adSetBg("r2_rtls").
    LOCAL rl IS asc["rl"].
    LOCAL g IS asc["g"].
    LOCAL vl IS st["vl"].
    LOCAL vh IS st["vh"] / AD_FT.
    IF vh < 0 {
        LOCAL bg IS adGeo["r2_bar_px"].
        adPut(adS["bar"], "bartri", adBarX(bg, (vl[0] - vl[3]) / ASC_RTLS_A_MECO[1] / AD_NM), bg[2]).
    }
    adRpy(asc, "t2_rpy_px").
    LOCAL fg IS adGeo["r2_field_px"].
    LOCAL p IS adHold("veh", adFieldG(fg, vh, st["h"] / AD_FT / 1000, TRUE), fg).
    adPut(adS["veh"], "veh", p[0], p[1]).
    IF NOT st["after"] {
        LOCAL ps IS adGeo["pred_r2"].
        FROM { LOCAL i IS 0. } UNTIL i > 1 STEP { SET i TO i + 1. } DO {
            LOCAL pr IS adPred(st, "vh", ps[i]).
            LOCAL pt IS adFieldG(fg, pr[0], pr[1], FALSE).
            IF pt:LENGTH = 2 { IF adFits("pred", pt, fg) { adPut(adS["p" + (i + 1)], "pred", pt[0], pt[1]). } }
        }
    }
    LOCAL gk IS adGeo["r2_g_px"].
    adPut(adS["ptr2"], "ewtri", gk[0], adScaleY(gk, st["g"])).
    // TGO to MECO: PEG's TGO to the pitchdown (in the fuel dissipation and the pitcharound from DT_TURN ahead) + its
    // planned length; the fine countdown's; the set MECO time's; the cutoff's
    LOCAL md IS rl["mode"].
    LOCAL tgo IS -1.
    IF NOT st["after"] {
        IF md = "fd" OR md = "turn" { SET tgo TO rl["DT_TURN"] + g["peg"]["TGO"] + asc_rtls_dt_pitch(). }
        ELSE IF md = "fb" { SET tgo TO g["peg"]["TGO"] + asc_rtls_dt_pitch(). }
        ELSE IF md = "fc" { SET tgo TO MAX(0, rl["TP_hold"] - st["met"]) + asc_rtls_dt_pitch(). }
        ELSE IF md = "m5" { SET tgo TO MAX(0, rl["m5_tgo"]). }   // mode 5's TGO
        ELSE IF g["T_MECO"] >= 0 { SET tgo TO MAX(0, g["T_MECO"] - st["met"]). }
        ELSE IF rl["tgo_co"] >= 0 { SET tgo TO rl["tgo_co"]. }
    }
    LOCAL pp IS "".
    IF NOT st["after"] AND asc["et_full"] > 0 { SET pp TO "" + ROUND(100 * asc_burnable(asc["ssme"]) / asc["et_full"]). }
    LOCAL tm IS "".
    IF st["after"] { SET tm TO adMmss(asc["t_meco"]). }
    ELSE IF adTmSettle(md, st["met"], CHOOSE st["met"] + tgo IF tgo >= 0 ELSE -1) { SET tm TO adMmss(st["met"] + tgo). }
    adCol("r2_lr_px", "lr", LIST(adPl(asc["kcmd"]), pp, tm)).
    LOCAL ts IS "".
    // in the fuel dissipation the time to PPA (lib_ascent_rtls rl["tpa"]), marked PPA (the TGO label is the
    // background's)
    IF st["after"] { SET ts TO "0:00". }
    // the time to PPA hidden until it settles: only once lib_ascent_rtls's test says so (rl["tpa_on"])
    ELSE IF md = "fd" { IF rl:HASKEY("tpa_on") { IF rl["tpa_on"] AND rl["tpa"] >= 0 { SET ts TO "PPA " + adMmss(rl["tpa"]). } } }
    ELSE IF tgo >= 0 { SET ts TO adMmss(tgo). }
    LOCAL mw IS "MECO".
    IF NOT st["after"] {
        // the modes' words; a mode not in the table shows its own name (an unknown mode must not stop the page)
        LOCAL nm IS LEXICON("fd", "DISSIP", "turn", "PPA", "fb", "FLYBACK", "fc", "FLYBACK", "ppd", "PPD", "m5", "5").
        IF nm:HASKEY(md) { SET mw TO nm[md]. } ELSE { SET mw TO md:TOUPPER. }
    }
    // alpha and beta of the nose against the relative wind (body: fore, top, star)
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL f IS SHIP:FACING.
    LOCAL al IS 0.
    LOCAL be IS 0.
    IF vs:MAG > 1 {
        SET al TO ARCTAN2(-VDOT(vs, f:TOPVECTOR), VDOT(vs, f:FOREVECTOR)).
        SET be TO ARCSIN(MAX(-1, MIN(1, VDOT(vs:NORMALIZED, f:STARVECTOR)))).
    }
    adCol("t2_col_px", "c", LIST(ts, adGuid(asc, st), mw, "" + ROUND(vl[0]),
        adFx(st["h"] / 1000, 1) + "K", adSgn(st["hdot"]), "" + ROUND(al), "" + ROUND(be),
        "" + ROUND(vl[2] / 1000) + "K")).
}

GLOBAL AD_ENG_BAR_HW IS 18.0.   // px, the OMS/MPS bars' fill half-width (the frame's inside 34 px + 1 px each side)
GLOBAL AD_ENG_BAR_YB IS 321.0.  // px, the fill's bottom edge (the frame's bottom line starts at 321)
FUNCTION adEng {
    PARAMETER asc, st.
    LOCAL b IS adGeo["eng_bar_px"].
    LOCAL vy IS adGeo["eng_val_px"].
    // the fill covers the frame's inside to its lines (omsmps.png: 3 px frame lines, the inside 34 px wide at each x,
    // the bottom line from y 321): 18 px either side (1 px onto the same-green lines) and down to 321, not the
    // sidecar's half-width 15.8 / bottom 319.6 (the 40 % mark, still the scale's zero), which leave black gaps of 2 px
    // at the right and 1 px at the bottom
    LOCAL hw IS AD_ENG_BAR_HW.
    LOCAL yb IS AD_ENG_BAR_YB.
    LOCAL ids IS adEngIds(asc["ssme"]).
    LOCAL xs IS adGeo["eng_ssme_x"].
    LOCAL ks IS LIST("L", "C", "R").
    FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
        LOCAL x IS xs[i].
        LOCAL pl IS 0.
        LOCAL s IS "READY".
        IF ids:HASKEY(ks[i]) {
            LOCAL en IS ids[ks[i]].
            IF adOut:HASKEY(ks[i]) { SET s TO "<color=" + AD_RED + ">OUT</color>". }
            ELSE IF st["after"] { SET s TO "SHDN". }
            ELSE IF NOT en:IGNITION AND st["ph"] = "PAD" { SET s TO "READY". }   // not lit on the pad is READY (the SRBs' rule), OUT only in flight
            ELSE IF NOT en:IGNITION OR en:FLAMEOUT { SET s TO "<color=" + AD_RED + ">OUT</color>". }
            ELSE {
                SET s TO "ON".
                IF en:AVAILABLETHRUST > 0 { SET pl TO en:THRUST / en:AVAILABLETHRUST * 100 / ASC_PL_TO_KSP. }
            }
        }
        IF pl >= b[3] { adBar(adS["b" + i], x - hw, b[0] + (MIN(pl, b[4]) - b[3]) / (b[4] - b[3]) * (b[1] - b[0]), x + hw, yb). }
        IF s = "ON" { adText(adS["v" + i], adPl(pl), x, vy[0], 2). }
        adText(adS["s" + i], s, x, vy[1], 2).
    }
    LOCAL sx IS adGeo["eng_srb_x"].
    LOCAL sk IS LIST("SL", "SR").
    FROM { LOCAL i IS 0. } UNTIL i > 1 STEP { SET i TO i + 1. } DO {
        LOCAL x IS sx[i].
        LOCAL s IS "SEP".
        IF st["s1"] {
            SET s TO CHOOSE "READY" IF st["ph"] = "PAD" ELSE "BURN".
            IF adIds:HASKEY(sk[i]) {
                LOCAL en IS adIds[sk[i]].
                LOCAL pk IS 0.
                IF adPk:HASKEY(en:UID) { SET pk TO adPk[en:UID]. }
                IF pk > 0 AND en:THRUST > 0 {
                    LOCAL f IS en:THRUST / pk.
                    adBar(adS["b" + (3 + i)], x - hw, b[0] + f * (b[1] - b[0]), x + hw, yb).
                    adText(adS["v" + (3 + i)], "" + ROUND(100 * f), x, vy[0], 2).
                }
            }
        }
        adText(adS["s" + (3 + i)], s, x, vy[1], 2).
    }
    LOCAL lo IS "".
    LOCAL lh IS "".
    IF asc["ssme"]:LENGTH > 0 AND NOT (st["after"] AND st["met"] >= asc["t_meco"] + AD_ET_SEP_S) {
        FOR cr IN asc["ssme"][0]:CONSUMEDRESOURCES:VALUES {
            IF cr:CAPACITY > 0 {
                IF cr:NAME:CONTAINS("Ox") { SET lo TO adFx(100 * cr:AMOUNT / cr:CAPACITY, 1). }
                ELSE { SET lh TO adFx(100 * cr:AMOUNT / cr:CAPACITY, 1). }
            }
        }
    }
    LOCAL om IS "".
    FOR rs IN SHIP:RESOURCES { IF rs:NAME = "LiquidFuel" AND rs:CAPACITY > 0 { SET om TO adFx(100 * rs:AMOUNT / rs:CAPACITY, 1). } }
    LOCAL gb IS "FREE".
    IF asc["ssme"]:LENGTH > 0 { IF asc["ssme"][0]:HASGIMBAL { IF asc["ssme"][0]:GIMBAL:LOCK { SET gb TO "LOCKED". } } }
    LOCAL lg IS adGeo["eng_list_px"].
    LOCAL vals IS LIST(lo, lh, om, om, "", CHOOSE "ON" IF asc["fc"] ELSE "OFF", gb).
    FROM { LOCAL i IS 0. } UNTIL i > 6 STEP { SET i TO i + 1. } DO {
        IF i <> 4 { adText(adS["l" + i], vals[i], lg[0], lg[1 + i], 1). }
    }
}

FUNCTION adTick {                           // ops1q: every loop tick (it skips a tick with a PEG pass); the two
    PARAMETER asc.                          // windows in turn: an update every AD_DT / 2 s, each window every AD_DT s
    IF NOT adOn OR uiRt() < adNext { RETURN. }   // the updates in real time (uiRt)
    // The next slot on a FIXED real-time grid (as lib_entdisp's edNx), not now + dt / 2: a late pass no longer
    // pushes every later slot back (p21: 132 ms mean, gaps to 880 ms, for 100 ms). The rate is unchanged.
    LOCAL adSl IS (CHOOSE AD_DT_CS IF adCsOn AND AD_CS ELSE AD_DT) / 2.
    SET adNext TO (FLOOR((uiRt() + 0.005) / adSl) + 1) * adSl - 0.005.
    SET adCyc TO adCyc + 1.
    IF NOT gpcLive(CHOOSE "BOT" IF MOD(adCyc, 2) = 0 ELSE "TOP") { RETURN. }   // This update's window has lost its GPC: frozen, then the big X (adGpcX); nothing drawn
    IF adCsOn AND AD_CS {
        IF adCsDraw(asc) { RETURN. }
    }
    LOCAL st IS adState(asc).
    IF MOD(adCyc, 2) = 0 {
        adEng(asc, st).
        adCommon(asc, st, "e").
        adSweep(adAllE).
    } ELSE {
        IF st["s1"] { adTraj1(asc, st). }
        ELSE IF st:HASKEY("vl") { adTrajR2(asc, st). }
        ELSE { adTraj2(asc, st). }
        adCommon(asc, st, "").
        adSweep(adAll).
    }
}

// ---- the C# pages (see the globals' note above)
// lib_gpc: the X look of a window whose GPC has failed. dead TRUE: its slots blanked, the page box shows the big X (gui_panel/gpc_x);
// FALSE: TRAJ's background is set again by its next draw (adBg cleared), OMS/MPS's is put back here. The draws are not called while dead (adTick).
FUNCTION adGpcX {
    PARAMETER win, dead.
    IF NOT adOn { RETURN. }
    IF win = "TOP" {
        IF dead {
            FOR sl IN adAll { IF sl[5] { adSlotOff(sl). } }
            SET adBox:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
        }
        SET adBg TO "".
    } ELSE {
        IF dead {
            FOR sl IN adAllE { IF sl[5] { adSlotOff(sl). } }
            SET adBoxE:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
        } ELSE { SET adBoxE:STYLE:BG TO AD_DIR + "omsmps.png". }
    }
}
FUNCTION adGpcXT { PARAMETER dead. adGpcX("TOP", dead). }
FUNCTION adGpcXB { PARAMETER dead. adGpcX("BOT", dead). }

FUNCTION adCsOff {                          // any failure: kOS draws from now on, for the flight
    PARAMETER why.
    SET AD_CS_ERR TO why.
    SET AD_CS_STATE TO "kOS (" + why + ")".
    SET adCsOn TO FALSE.
    SET AD_CS TO FALSE.
}

// ---- the painter (see AD_PAINT at the top)
FUNCTION adPaintGroups {                   // LIST(LIST(name, page box, LIST(LIST(label, flow index) ...), the page box's child count))
    LOCAL res IS LIST().
    FOR gp IN LIST(LIST("AD_T", adBox, adAll), LIST("AD_E", adBoxE, adAllE)) {   // TRAJ, OMS/MPS: every child a slot
        LOCAL its IS LIST().
        FOR sl IN gp[2] { its:ADD(LIST(sl[0], sl[1])). }
        res:ADD(LIST(gp[0], gp[1], its, gp[2]:LENGTH)).
    }
    RETURN res.
}

FUNCTION adPaintPh {                       // a placeholder: the page box's LAST child, a 1 x 1 box + an empty 1 x 1 label
    PARAMETER pg, fl.                       //   (shown: its draw is where C# paints the page, after every slot box)
    LOCAL bx IS pg:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 1. SET m:STYLE:HEIGHT TO 1.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:MARGIN:H TO 0. SET m:STYLE:MARGIN:V TO 0.
    RETURN LIST(m, fl, pg).
}

FUNCTION adPaintSetup {                    // adInit's end (after every slot): AD_PAINT 0 = nothing created
    SET adPaintReg TO FALSE.
    adPaintNames:CLEAR().
    IF AD_PAINT = 0 { SET AD_PAINT_STATE TO "OFF". RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        FOR gp IN adPaintGroups() {
            IF why = "" {
                LOCAL er IS ADDONS:KALS:PAINTREG(gp[0], adPaintPh(gp[1], gp[3]), gp[2]).
                IF er = "" { adPaintNames:ADD(gp[0]). SET er TO ADDONS:KALS:PAINTMODE(gp[0], AD_PAINT). }
                IF er <> "" { SET why TO gp[0] + ": " + er. }
            }
        }
    }
    IF why <> "" { adPaintOff(why). RETURN. }
    SET adPaintReg TO TRUE.
    SET AD_PAINT_STATE TO adPaintName(AD_PAINT).
}

FUNCTION adPaintName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
}

// the mode switched live (the test harness's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a AD_PAINT > 0 adInit
FUNCTION adPaintSet {
    PARAMETER m.
    IF NOT adPaintReg { RETURN "not registered (AD_PAINT was 0 at adInit, or it failed: " + AD_PAINT_STATE + ")". }
    FOR gn IN adPaintNames {
        LOCAL er IS ADDONS:KALS:PAINTMODE(gn, m).
        IF er <> "" { adPaintOff(gn + ": " + er). RETURN er. }
    }
    SET AD_PAINT TO m.
    SET AD_PAINT_STATE TO adPaintName(m).
    RETURN "".
}

FUNCTION adPaintOff {                      // any failure: kOS draws from now on (C# showed the boxes, or never hid them)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") {
        FOR gn IN adPaintNames { ADDONS:KALS:PAINTMODE(gn, 0). }
    } }
    SET AD_PAINT_STATE TO "OFF (" + why + ")".
    SET AD_PAINT TO 0.
    SET adPaintReg TO FALSE.
}

FUNCTION adCsSetup {                        // adInit's end: the slots and tables to the addon
    SET adCsOn TO FALSE.
    IF NOT AD_CS {
        SET AD_CS_STATE TO "kOS (AD_CS off)".
        RETURN.
    }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("ADDRAW") { SET why TO "the KAL/S addon has no ascent pages (an older DLL)". }
    ELSE {
        LOCAL er IS ADDONS:KALS:ADSETUP().
        IF er <> "" { SET why TO "ADSETUP: " + er. }
    }
    IF why <> "" {
        adCsOff(why).
        RETURN.
    }
    SET adCsOn TO TRUE.
    SET AD_CS_STATE TO "C#".
}

// One update's game reads (adState's, adRpy's, adTraj2's, adTrajR2's, adEng's) and the other libraries' calls, at once, for
// ADDRAW (Ad.cs reads them by index): now, VREL, VI, H, HDOT, mass, q, G0, ATMTOKPA, the SRBs' thrust and peak sums (adPk
// kept here, as adState does), the SSMEs' + OMS thrust, the RTLS (has, VH, the MECO line), the facing (fore, top, star),
// the steering target (has, fore, top), asc_abr_site at adModes' VI for 1, 2, 3 SSMEs out, then the page's own: OMS/MPS
// (even updates) or TRAJ (odd).
FUNCTION adCsIn {
    PARAMETER asc.
    LOCAL now IS TIME:SECONDS.
    LOCAL met IS 0.
    IF asc["t_lo"] >= 0 { SET met TO now - asc["t_lo"]. }
    LOCAL ph IS asc["phase"].
    LOCAL s1 IS ph = "PAD" OR ph = "STAGE1".
    LOCAL vi IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL inp IS LIST(now, SHIP:VELOCITY:SURFACE:MAG, vi, SHIP:ALTITUDE, SHIP:VERTICALSPEED, SHIP:MASS,
        SHIP:DYNAMICPRESSURE, CONSTANT:G0, CONSTANT:ATMTOKPA).
    LOCAL fs IS 0.
    LOCAL pk IS 0.
    adEngIds(asc["ssme"]).
    IF s1 {
        adSrbIds(asc["srbs"]).
        FOR en IN asc["srbs"] {
            LOCAL f IS en:THRUST.
            SET fs TO fs + f.
            IF NOT adPk:HASKEY(en:UID) { SET adPk[en:UID] TO f. }
            IF f > adPk[en:UID] { SET adPk[en:UID] TO f. }
            SET pk TO pk + adPk[en:UID].
        }
    }
    LOCAL fl IS 0.
    FOR en IN asc["ssme"] { SET fl TO fl + en:THRUST. }
    IF asc:HASKEY("oms") { FOR en IN asc["oms"] { SET fl TO fl + en:THRUST. } }
    inp:ADD(fs). inp:ADD(pk). inp:ADD(fl).
    LOCAL rl IS LEXICON().
    IF asc:HASKEY("rl") { SET rl TO asc["rl"]. }
    IF rl:LENGTH > 0 {
        LOCAL sm IS asc_sample(asc["fr"], now).
        LOCAL aw IS VXCL(sm[1], sm[1] - asc_rotz(rl["ef"], rl["w"] * met)):NORMALIZED.
        inp:ADD(TRUE).
        inp:ADD(VDOT(sm[2] - asc_rtls_wxr(rl, sm[1]), aw)).
        inp:ADD(asc_rtls_vline(rl, met, sm[1], sm[2], 0)).
    } ELSE { inp:ADD(FALSE). inp:ADD(0). inp:ADD(0). }
    LOCAL fc IS SHIP:FACING.
    inp:ADD(fc:FOREVECTOR). inp:ADD(fc:TOPVECTOR). inp:ADD(fc:STARVECTOR).
    IF asc:HASKEY("dir") {
        LOCAL tg IS asc["dir"].
        inp:ADD(TRUE). inp:ADD(tg:FOREVECTOR). inp:ADD(tg:TOPVECTOR).
    } ELSE { inp:ADD(FALSE). inp:ADD(0). inp:ADD(0). }
    LOCAL vift IS vi / AD_FT.               // adModes' VI (ft/s): adCont hands asc_abr_site vi * AD_FT, the same bits
    LOCAL hab IS asc:HASKEY("abr").
    FROM { LOCAL n IS 1. } UNTIL n > 3 STEP { SET n TO n + 1. } DO {
        IF hab { inp:ADD(asc_abr_site(n, vift * AD_FT)). } ELSE { inp:ADD(""). }
    }
    LOCAL pg IS LIST().
    IF MOD(adCyc, 2) = 0 {
        FOR k IN LIST("L", "C", "R") {
            IF adIds:HASKEY(k) {
                LOCAL en IS adIds[k].
                pg:ADD(LIST(TRUE, en:IGNITION, en:FLAMEOUT, en:AVAILABLETHRUST, en:THRUST)).
            } ELSE { pg:ADD(LIST(FALSE)). }
        }
        FOR k IN LIST("SL", "SR") {
            IF s1 AND adIds:HASKEY(k) {
                LOCAL en IS adIds[k].
                LOCAL p IS 0.
                IF adPk:HASKEY(en:UID) { SET p TO adPk[en:UID]. }
                pg:ADD(LIST(TRUE, p, en:THRUST)).
            } ELSE { pg:ADD(LIST(FALSE)). }
        }
        LOCAL crl IS LIST().
        LOCAL gb IS FALSE.
        IF asc["ssme"]:LENGTH > 0 {
            FOR cr IN asc["ssme"][0]:CONSUMEDRESOURCES:VALUES { crl:ADD(cr:NAME). crl:ADD(cr:AMOUNT). crl:ADD(cr:CAPACITY). }
            IF asc["ssme"][0]:HASGIMBAL { IF asc["ssme"][0]:GIMBAL:LOCK { SET gb TO TRUE. } }
        }
        pg:ADD(crl).
        LOCAL lf IS LIST().
        FOR rs IN SHIP:RESOURCES { IF rs:NAME = "LiquidFuel" { lf:ADD(rs:AMOUNT). lf:ADD(rs:CAPACITY). } }
        pg:ADD(lf).
        pg:ADD(gb).
    } ELSE {
        LOCAL bu IS 0.
        IF NOT s1 AND asc["t_meco"] < 0 AND asc["et_full"] > 0 { SET bu TO asc_burnable(asc["ssme"]). }
        LOCAL dtp IS 0.
        IF rl:LENGTH > 0 { SET dtp TO asc_rtls_dt_pitch(). }
        pg:ADD(SHIP:APOAPSIS). pg:ADD(SHIP:PERIAPSIS). pg:ADD(SHIP:VELOCITY:SURFACE). pg:ADD(bu). pg:ADD(dtp).
    }
    inp:ADD(pg).
    RETURN inp.
}

FUNCTION adCsDraw {                         // TRUE: C# drew this update; FALSE: kOS draws it (a failure)
    PARAMETER asc.
    LOCAL inp IS adCsIn(asc).
    LOCAL ops IS ADDONS:KALS:ADDRAW(asc, inp).
    IF ops:ISTYPE("String") {               // nothing was written: kOS draws this update
        adCsOff("ADDRAW: " + ops).
        RETURN FALSE.
    }
    adCsApply(ops).
    RETURN TRUE.
}

FUNCTION adCsApply {                        // ADDRAW's widget writes, in order: widget, code, value
    PARAMETER o.
    FROM { LOCAL i IS 0. } UNTIL i >= o:LENGTH STEP { SET i TO i + 3. } DO {
        LOCAL w IS o[i].
        LOCAL c IS o[i + 1].
        LOCAL x IS o[i + 2].
        IF c = 0 { SET w:TEXT TO x. }
        ELSE IF c = 4 { SET w:STYLE:MARGIN:H TO x. }
        ELSE IF c = 5 { SET w:STYLE:MARGIN:V TO x. }
        ELSE IF c = 2 { SET w:STYLE:WIDTH TO x. }
        ELSE IF c = 1 { SET w:IMAGE TO x. }
        ELSE IF c = 3 { SET w:STYLE:HEIGHT TO x. }
        ELSE IF c = 6 { SET w:STYLE:ALIGN TO x. }
        ELSE { SET w:STYLE:BG TO x. }
    }
}
