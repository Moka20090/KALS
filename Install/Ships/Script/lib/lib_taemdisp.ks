@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_TAEMDISP.KS  --  THE GRTLS (MM 602) AND TAEM (MM 603) DISPLAYS, VERT SIT AND HORIZ SIT, LIVE: ONE GUI
// ============================================================================
//  ONE library and ONE pair of windows for the GRTLS and TAEM pages (the two are alike: the same windows, the pages
//  swapped). Hosts: ops6q.ks's RTLS loop tdGrStart() (MM 602), tdGrTick(..); landRun (lib_land) tdInit() -- on the
//  GRTLS's open windows it swaps to MM 603 (tdSetMm), else it opens them on MM 603 --, tdTick(tg, st) after each TAEM
//  cycle, tdPagesOff() at A/L (the pages hidden, the windows' button rows kept), tdClose() at landRun's end. Each window
//  has a button row between its title and its page: VERT SIT's takes lib_dap's buttons (tdRowV), HORIZ SIT's HUD CAM
//  (tdRowH), dapGuiBuild fills them; the DAP's own window is not shown.
//  Two kOS GUI windows of 736 x 460 px pages, imperial on the glass, metric inside; taem_bg/ (the sprites, the HORIZ SIT
//  pages, taem_bg.txt) + grtls_bg/ (VERT SIT's MM 602 pages vsit1_602.png / vsit2_602.png, grtls_bg.txt, grblank.png).
// ============================================================================
GLOBAL TD_DIR IS "taem_bg/".
RUNONCEPATH("0:/lib/lib_screen.ks").        // SCR_W: the screen width
RUNONCEPATH("0:/lib/lib_guistyle.ks").      // the windows' frames in the panel look (uiDispSkin ...)
RUNONCEPATH("0:/lib/lib_gpc.ks").            // A window whose GPC has failed freezes, then shows the big X
RUNONCEPATH("0:/lib/lib_dock.ks").         // HORIZ SIT docked under VERT SIT, the deck where the crew left it
GLOBAL TD_ARCH IS "0:/taem_bg/".
GLOBAL TD_OFF_X IS 0.                       // ENTRY TRAJ's construction: MARGIN = px from the box's top-left
GLOBAL TD_OFF_Y IS 0.
// the image slots draw 1:1 (no label padding), so the centred sprites sit where their anchors say and the off-centre
// tips land on their anchors
GLOBAL TD_IMG_DY IS -0.3.                    // px: an image sits 2.7 px low in its label (traj_display's TJ_IMG_DY)
GLOBAL TD_TXT_DY IS 7.                      // px: text sits 7 px low in its label (lib_hud's value)
GLOBAL TD_VS_ROW_DY IS 3.                   // px lower: VERT SIT's value rows (TAEM's 7 was measured with
                                            // 4 slots before them hidden, each lifting them 1 px; these hide none)
GLOBAL TD_HS_ROW_DY IS 3.                   // px lower: HORIZ SIT's value rows (measured: 4 drew them 1 px below their
                                            // labels)
GLOBAL TD_CLK_DY IS -3.                     // px lower: the clock (clock_px is the header's baseline: in TD_FONT at 13 px
                                            // its digits end on the page id's, as the entry pages' clock)
GLOBAL TD_FONT IS "DejaVu Sans Mono Bold".   // the clock's face: the page id's (bold already, so no <b>)
GLOBAL TD_FIT_IN IS 1.5.                    // px a sprite keeps inside its field (the frame's stroke)
GLOBAL TD_FLOW_PX IS 1.0.                   // px per flow child: the Nth starts N px low (traj_display's TJ_FLOW_PX)
GLOBAL TD_TXT_W IS 200.                     // a text label's width, px; tdText narrows it near the page's left edge
GLOBAL TD_VS_X IS 167.                      // VERT SIT window x, y, px: where the ascent windows sit (the upper one's
GLOBAL TD_VS_Y IS 405.                      // corner on a 4K screen)
GLOBAL TD_HS_X IS 167.                      // HORIZ SIT right under VERT SIT (tdInit adds VERT SIT's height)
// A screen too short for the two stacked (1920x1080: the DAP window and the HUD's glass in the way) keeps the old
// places: VERT SIT left of the glass under the DAP window, HORIZ SIT right of the glass (lib_hud's window ends at
// ~2383 at 4K) and inside the screen (the window is 736 wide).
GLOBAL TD_VS_X0 IS 40.
GLOBAL TD_VS_Y0 IS 420.
GLOBAL TD_HS_X0 IS MIN(2440, SCR_W - 780).
GLOBAL TD_HS_Y0 IS 420.
GLOBAL TD_HAC_RMIN IS 10.                   // px: the smallest HAC circle sprite's radius (the sprites run hac_010 .. hac_116)
GLOBAL TD_HAC_RMAX IS 116.
// the HAC as tangent dashes (hacd_00 .. hacd_31, gen_taem_sprites) where its whole circle does not fit the field: each
// dash shown when wholly inside, so the page shows the arc that crosses it (kOS draws no clip)
GLOBAL TD_HACD_L IS 16.                     // px: a dash's length (gen_taem_sprites HACD_L); the dashes stand <= this apart
GLOBAL TD_HACD_NO IS 32.                    // the dash sprites' orientations over 180 deg (HACD_N)
GLOBAL TD_HACD_N IS 72.                     // the dash slots, last in the HORIZ SIT box (tdInit); a radius past 183 px
                                            //   spaces its dashes wider
GLOBAL TD_FT IS 0.3048.
GLOBAL TD_NM IS 1852.
GLOBAL TD_PSF IS 47.88025898.
GLOBAL TD_SB_PCT IS 100 / 98.6.            // VERT SIT's SPD BK and CMD in percent: 100 = the 98.6 deg hinge (the orbiter's full brake)
GLOBAL TD_BAR_SHOW_S IS 20.                 // s: HAC bar show / move time (same as HAC_BAR_SHOW_S / HAC_BAR_MOVE_S in the page generator)
GLOBAL TD_BAR_MOVE_S IS 10.
GLOBAL TD_TTH_BLEND_S IS 2.                 // s: the HAC bar's step at a cycle blends out over this
GLOBAL TD_TTH_RK IS 0.3.                    // the filter on the measured countdown rate (per cycle)

// THE C# PAGES: the pages' math in the KAL/S coprocessor (coproc Td.cs / TdKos.cs: ADDONS:KALS:TDSETUP, TDDRAW). kOS keeps
// the game reads (tdCsIn: TIME, ldDmShow, ldRwy, the trims, lib_grtls's SS_ON / SS_NZ / GR_GRNZC1, and taemg_gtp for
// tdGrPre's range), the state (the slots, the draw's globals: C# reads them and writes them back) and every widget write
// (TDDRAW returns them, tdCsApply sets them). TD_CS (default TRUE): C# draws; on ANY failure kOS draws that same draw and
// from then on (tdCsOff; TD_CS_STATE says why).
IF NOT (DEFINED TD_CS) { GLOBAL TD_CS IS TRUE. }
// TD_CS_HIDE (default TRUE): with a DLL that has TDHIDE, the C# draws (TD and ED) show / hide the labels they
// write by tdVis's rule, so kOS hides the blank labels again while the C# draws (tdNoHide only for an older DLL)
IF NOT (DEFINED TD_CS_HIDE) { GLOBAL TD_CS_HIDE IS TRUE. }
GLOBAL tdCsHide IS FALSE.                  // TRUE: the C# applies tdVis's rule (tdHideSetup, at tdInit)
GLOBAL tdCsOn IS FALSE.
// A GPC window down (the BFS flying, a DPS 02 / 03 / 05) used to
// tdCsOff("GPC FAIL") the C# draw FOR THE FLIGHT (kOS then draws once a cycle). With a DLL that has TDGPC (tdGpcCs) the C# draw is told
// which windows are live (tdCsIn [23] TOP = VERT SIT, [24] BOT = HORIZ SIT) and draws only those, 10 Hz as ever; an older DLL keeps the old fallback.
GLOBAL tdGpcCs IS FALSE.
GLOBAL TD_CS_ERR IS "".
GLOBAL TD_CS_STATE IS "kOS (not set up)".
// THE PAINTER (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE / PAINTSTATE): the pages' slot labels drawn by
// C# inside kOS's window (each with its own style and content, at the rect kOS's layout gives it), the slots' boxes
// hidden from kOS's layout. TD_PAINT: 0 OFF (default until the test harness's CHECK + A/B proof: kOS draws as before), 1 CHECK
// (kOS draws; C# compares every label's real rect with its own: KSP.log [KalsPaint] worst px), 2 PAINT, 3 AB (PAINT
// and kOS in turn every 2 s, for the screenshot diff). Any failure: kOS draws (TD_PAINT_STATE says why).
IF NOT (DEFINED TD_PAINT) { GLOBAL TD_PAINT IS 0. }
GLOBAL TD_PAINT_STATE IS "OFF".
GLOBAL tdPaintOn IS FALSE.                  // C# paints the pages now: tdNbTrim leaves the boxes to it
GLOBAL tdPaintReg IS FALSE.                 // both pages registered with the painter (TD_PAINT > 0 at tdInit)
GLOBAL tdOrd IS LEXICON("V", LIST(), "H", LIST()).   // each page's slots in creation (= draw) order: LIST(label, flow)
// THE 10 Hz REDRAWS: with the C# drawing live (tdFast: tdCsOn, TD_CS) the hosts redraw the pages every
// TD_DT_CS s between the guidance cycles (tdTick / tdGrTick with cyc FALSE: the vehicle now, the cycle's guidance state);
// kOS drawing (TD_CS off, a fallback) keeps one draw per cycle. The turn rate of HORIZ SIT's predictors
// (tdRate) is measured on each cycle's draw only (cyc TRUE): the redraws do not shorten its baseline. The flash
// (tdFlash) steps at every draw, the redraws' too: 5 Hz.
GLOBAL TD_DT_CS IS 0.1.
// THE FLASH CLOCK: a cycle's own draw falls anywhere between two redraws, and a flash stepped there would make one
// half-period a cycle short. While the C# draws live (tdFlashClk: tdFast, TD_DT_CS > 0) the flash is the parity of the
// TD_DT_CS grid's slot at the draw, and the hosts redraw on that grid (tdGridNx): one redraw a slot, and a cycle's draw
// inside a slot shows that slot's phase. kOS drawing keeps the step a draw.
GLOBAL tdFlashClk IS FALSE.
GLOBAL tdRtT IS 0.                           // the draw's real time (uiRt): the grid's flash, Td.cs reads it
// BETWEEN THE CYCLES: the flash steps at every draw, the redraws' too (tdFlashStep): lit one draw, dark the next, 5 Hz at
// TD_DT_CS 0.1 and even at any draw timing (a clock gate sampled at the draw rate would alias); kOS drawing (one draw a
// cycle) steps once a cycle. VERT SIT's bug range, energy box and E/W triangle, HORIZ SIT's GSI and RANGE move on between
// the cycles (tdEnNow): the range down at the ground speed, the energy reference, the box's kinetic part and the height
// reference along their slopes over range (the last two cycles'), the energy over weight the vehicle's now (taemg_comp's
// h + v^2 / 2g). The MEP / OH marks keep the cycle's (their energy differences are the guidance's).
GLOBAL tdEnS IS LEXICON().                  // the last cycle's draw: t, d, en, eh, hr and their slopes over range
GLOBAL tdRate IS 0.                         // deg/s: HORIZ SIT's measured turn rate (the last cycle's draw)

GLOBAL tdOn IS FALSE.
GLOBAL tdMm IS 603.                        // the pages' major mode: 602 the GRTLS (tdGrStart), 603 TAEM
GLOBAL tdPg IS FALSE.                      // the pages drawn (FALSE after tdPagesOff: the button rows alone)
GLOBAL tdRowV IS 0.                        // VERT SIT's button row (lib_dap's buttons), HORIZ SIT's (HUD CAM)
GLOBAL tdRowH IS 0.
GLOBAL tdRowV2 IS 0.                       // VERT SIT's second row (lib_dap's < SITE > and the OTT buttons)
GLOBAL tdRowH2 IS 0.                       // HORIZ SIT's second row (lib_dap's ALT MODE)
GLOBAL TD_ROW_H IS 26.                     // px: a button row's height (each window grows by it)
GLOBAL TD_BAR_WIN_H IS 60.                 // px: a window's height with its page hidden (the title + the row)
GLOBAL TD_LIB IS TRUE.                     // traj_display asks for the deck only when this library is loaded
GLOBAL tdDeck IS FALSE.                    // the windows are up before the pages (ENTRY TRAJ's top page)
GLOBAL tdTitV IS 0.                        // the windows' title labels (the page swap renames them)
GLOBAL tdTitH IS 0.
GLOBAL tdGuiV IS 0.                         // the two windows ("V" VERT SIT, "H" HORIZ SIT), their boxes, their slots
GLOBAL tdGuiH IS 0.
GLOBAL tdBoxV IS 0.
GLOBAL tdBoxH IS 0.
GLOBAL tdBgV IS "".                         // the background shown now (STYLE:BG set only on a change)
GLOBAL tdBgH IS "".
GLOBAL TD_HS_TTH_Z3 IS 20.                 // s to the HAC at which HORIZ SIT goes to its 1 NM page (zoom 3)
GLOBAL TD_HS_OUT IS 0.93.                  // a zoom holds the vehicle inside this fraction of its half-width
GLOBAL TD_HS_ZMIN IS -1.                   // HORIZ SIT's widest zoom (hs-1_km, +-500 km)
// HORIZ SIT TRACK UP. The page is turned about the vehicle so that the ground track (st["psd"]) is up: the bug is the
// upright hsbug_000 at TD_TU_BY down the field, the runway strip, its extended centreline, the HAC circle and the predictors
// are placed on the turned world. kOS cannot turn an image, so the runway (baked into hsit<z>.png in the runway-up mode) is
// drawn as dashes: cld_NN (centreline), rwd_NN / rws_NN (the strip), NN = the dash's orientation over 180 deg in
// TD_HACD_NO steps (gen_taem_sprites), on the page set hsit<z>t.png (no runway baked). FALSE: the runway-up page as before.
GLOBAL TD_TRKUP IS TRUE.
GLOBAL TD_TU_BY IS 0.82.                    // the vehicle's place down the field (as lib_entdisp's 18 % up from the bottom)
GLOBAL TD_TU_IN IS 0.85.                    // a zoom holds the aim inside this fraction of the room each way (HS_ZOOM_IN's)
GLOBAL TD_CLD_P IS 8.52.                    // px: the centreline dash's period (4.8 pt on + 3.2 pt off, gen_taem_bg)
GLOBAL TD_CLD_N IS 56.                      // the centreline slots: dash k in slot k mod this (the field's diagonal holds 54)
GLOBAL TD_RWD_L IS 16.                      // px: a strip dash's length (gen_taem_sprites RWD_L); RWS_L the short one
GLOBAL TD_RWS_L IS 8.
GLOBAL TD_RW_N IS 16.                       // the strip slots
GLOBAL TD_RW_STK IS 6.24.                   // px: the baked strip's outline sticks out half this at each end (RWY_LW)
GLOBAL TD_RW_DEF IS 2513.                   // m: a runway length when none is known (what the pages baked)
GLOBAL tdTuG IS LIST(0, 0, 1, 0, 0, 0, 1).  // this draw's turn: vehicle x, y (km), cos, sin of the track, the bug's page px x, y, px per km
GLOBAL tdZoomLatch IS 1.                    // HORIZ SIT's zoom latch: the tightest level reached this run
GLOBAL tdHdKey IS "".                       // the HAC dashes' centre and radius px when last placed ("" = place again)
GLOBAL tdHdUsed IS 0.                       // the dash slots they took (hd0 ..)
GLOBAL tdCnt IS LEXICON("V", 0, "H", 0).    // each box's flow-child count
GLOBAL tdSV IS LEXICON().
GLOBAL tdSH IS LEXICON().
GLOBAL tdGeo IS LEXICON().
GLOBAL tdSpr IS LEXICON().
GLOBAL tdPrev IS LEXICON().
GLOBAL tdTh IS LEXICON().                   // the HAC bar's time: the cycle's time, estimate, rate, step
GLOBAL tdCyc IS 0.                          // the TAEM cycle count; each slot stores the cycle that last drew it
GLOBAL tdFlash IS FALSE.
GLOBAL tdLog IS LIST().
GLOBAL tdLastPh IS -1.
GLOBAL tdLastMsg IS "".
GLOBAL tdT0 IS 0.
GLOBAL tdMet0 IS 0.                         // UT s at the mission's MET 0 (the clock: TIME:SECONDS - tdMet0)
GLOBAL tdAll IS LIST().                     // every slot, for tdSweep (tdInit)
GLOBAL tdLogSl IS LIST().                   // the message log's 13 row slots (tdInit)
GLOBAL tdLogDrawn IS -1.                    // tdLog's length when the rows were last drawn

FUNCTION tdNums {                           // "key a b c" -> LIST of numbers after the key
    PARAMETER lin.
    LOCAL out IS LIST().
    LOCAL p IS lin:SPLIT(" ").
    FROM { LOCAL i IS 1. } UNTIL i >= p:LENGTH STEP { SET i TO i + 1. } DO {
        IF p[i] <> "" { out:ADD(p[i]:TONUMBER(0)). }
    }
    RETURN out.
}

FUNCTION tdLoad {                           // reads the sidecars (taem_bg.txt, sprites.txt)
    FOR l0 IN OPEN(TD_ARCH + "taem_bg.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        IF lin <> "" AND NOT lin:STARTSWITH("#") { SET tdGeo[lin:SPLIT(" ")[0]] TO tdNums(lin). }
    }
    FOR l0 IN OPEN(TD_ARCH + "sprites.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        IF lin:STARTSWITH("S ") {
            LOCAL p IS lin:SPLIT(" ").
            SET tdSpr[p[1]] TO LIST(TD_DIR + "sprites/" + p[1] + ".png", p[2]:TONUMBER(0), p[3]:TONUMBER(0), p[4]:TONUMBER(0), p[5]:TONUMBER(0)).
        }
    }
    RETURN tdGeo:HASKEY("png_w") AND tdSpr:HASKEY("pred").
}

FUNCTION tdBoxOf {
    PARAMETER w.                            // "V" or "H": the window's box
    IF w = "V" { RETURN tdBoxV. }
    RETURN tdBoxH.
}

FUNCTION tdImgSlot {                        // traj_display tjMarker: a 1x1 box holding one image label
    PARAMETER w.
    LOCAL bx IS tdBoxOf(w):ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 4. SET m:STYLE:HEIGHT TO 4.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.   // 1:1 (gen_taem_sprites draws them at their shown size)
    // the slot: widget, flow index, last sprite / text, last x, y, SHOWN, the cycle that last drew it, align, width, font,
    // a text slot's own px lower (the value rows), and the last full call's x, y, align (a repeat of it changes nothing)
    LOCAL sl IS LIST(m, tdCnt[w], "", -99999, -99999, FALSE, -1, "", -1, 0, 0, -99999, -99999, -1).
    tdOrd[w]:ADD(LIST(m, tdCnt[w])).
    SET tdCnt[w] TO tdCnt[w] + 1.
    // blank: the label hidden, its 1 x 1 box never: a hidden box drops out of the flow and moves every later slot up
    SET m:IMAGE TO TD_GR_DIR + "grblank.png".
    IF NOT tdNoHide() { m:HIDE(). }
    RETURN sl.
}

FUNCTION tdNestSlot {                       // tdImgSlot's slot inside the nested box nst, as its child fl (its flow index)
    PARAMETER nst, fl, nb IS 0.             // nb: a tdNbNew group, the slot and its box added to it (tdNbTrim)
    LOCAL bx IS nst:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 4. SET m:STYLE:HEIGHT TO 4.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    LOCAL sl IS LIST(m, fl, "", -99999, -99999, FALSE, -1, "", -1, 0, 0, -99999, -99999, -1).
    tdOrd["H"]:ADD(LIST(m, fl)).            // the nested boxes are HORIZ SIT's
    SET m:IMAGE TO TD_GR_DIR + "grblank.png".
    IF NOT tdNoHide() { m:HIDE(). }
    IF nb:ISTYPE("List") { nb[0]:ADD(sl). nb[1]:ADD(bx). SET nb[2] TO nb[2] + 1. }
    RETURN sl.
}

// A nested box's TRAILING blank slots have their 1 x 1 boxes hidden too. A hidden box gives up its pixel of
// the flow, which moves only the children after it, and those are hidden as well; the nested box is 1 x 1 whatever it
// holds, so nothing outside it moves. A group: LIST(its slots, their boxes, the boxes shown (the first n)).
GLOBAL tdNb IS LIST().                      // the groups (tdInit: the runway's centreline + strip, the HAC dashes)
FUNCTION tdNbNew {
    LOCAL nb IS LIST(LIST(), LIST(), 0).
    tdNb:ADD(nb).
    RETURN nb.
}
FUNCTION tdNbTrim {                         // after a draw (tdSweep / tdSweepW / tdCsApply): the boxes up to the last
    IF tdPaintOn { IF NOT tdPaintGone() { RETURN. } }   // C# paints: the boxes are its (hidden)
    FOR nb IN tdNb {                        //   SHOWN slot shown, the rest hidden (only the ones that change)
        LOCAL sls IS nb[0].
        LOCAL L IS sls:LENGTH.
        UNTIL L = 0 { IF sls[L - 1][5] { BREAK. } SET L TO L - 1. }
        LOCAL n IS nb[2].
        IF L > n { LOCAL bxs IS nb[1]. FROM { LOCAL i IS n. } UNTIL i >= L STEP { SET i TO i + 1. } DO { bxs[i]:SHOW(). } SET nb[2] TO L. }
        ELSE IF L < n { LOCAL bxs IS nb[1]. FROM { LOCAL i IS L. } UNTIL i >= n STEP { SET i TO i + 1. } DO { bxs[i]:HIDE(). } SET nb[2] TO L. }
    }
}

FUNCTION tdNestNew {                        // a nested 1 x 1 box as the HORIZ SIT box's next child: LIST(box, its flow index p);
    LOCAL nst IS tdBoxH:ADDVLAYOUT().       //   its child i flows p + i px down (tdNestSlot's fl)
    SET nst:STYLE:WIDTH TO 1. SET nst:STYLE:HEIGHT TO 1.
    SET nst:STYLE:PADDING:H TO 0. SET nst:STYLE:PADDING:V TO 0.
    SET nst:STYLE:PADDING:BOTTOM TO 1.      // A nest whose boxes are all hidden keeps its row (tdImgSlot)
    SET nst:STYLE:MARGIN:H TO 0. SET nst:STYLE:MARGIN:V TO 0.
    LOCAL p IS tdCnt["H"].
    SET tdCnt["H"] TO p + 1.
    RETURN LIST(nst, p).
}

FUNCTION tdTxtSlot {                        // bd FALSE: the page face TD_FONT, plain text (no <b>)
    PARAMETER w, fs, col, bd IS TRUE.
    LOCAL bx IS tdBoxOf(w):ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:FONTSIZE TO fs.
    SET m:STYLE:TEXTCOLOR TO col.
    SET m:STYLE:WIDTH TO TD_TXT_W. SET m:STYLE:HEIGHT TO fs * 2.
    SET m:STYLE:RICHTEXT TO bd.
    IF NOT bd { SET m:STYLE:FONT TO TD_FONT. }
    LOCAL sl IS LIST(m, tdCnt[w], "", -99999, -99999, FALSE, -1, "", TD_TXT_W, fs, 0, -99999, -99999, -1, bd).
    tdOrd[w]:ADD(LIST(m, tdCnt[w])).
    SET tdCnt[w] TO tdCnt[w] + 1.
    // blank: the label hidden, its 1 x 1 box never: a hidden box drops out of the flow and moves every later slot up
    SET m:TEXT TO " ".
    IF NOT tdNoHide() { m:HIDE(). }
    RETURN sl.
}

// A slot is filled / blanked only on a change, and marked drawn this cycle; never hidden (the flow stays put)
FUNCTION tdSlotOn {
    PARAMETER sl.
    SET sl[6] TO tdCyc.
    IF NOT sl[5] {                          // re-filled from the slot's own content (sl[2]), as SHOW kept it
        IF sl[9] = 0 { IF sl[2] <> "" { LOCAL im IS tdSpr[sl[2]][0]. SET sl[0]:IMAGE TO im. tdVis(sl[0], 1, im). } }
        ELSE { LOCAL tx IS CHOOSE "<b>" + sl[2] + "</b>" IF sl[14] ELSE sl[2]. SET sl[0]:TEXT TO tx. tdVis(sl[0], 0, tx). }
        SET sl[5] TO TRUE.
    }
}
FUNCTION tdSlotOff {
    PARAMETER sl.
    IF sl[5] {                              // blanked (an image slot: sl[9] 0), its content kept in sl[2]
        IF sl[9] = 0 { SET sl[0]:IMAGE TO TD_GR_DIR + "grblank.png". } ELSE { SET sl[0]:TEXT TO " ". }
        IF NOT tdNoHide() { sl[0]:HIDE(). }
        SET sl[5] TO FALSE.
    }
}

// kOS's IMGUI draws every SHOWN label every frame, a blank
// one (grblank.png, " ") as dearly as a drawn one; so a label is shown only while it has something to draw. Only the
// label: its 1 x 1 box stays shown and keeps its pixel of the flow, so no other slot moves (the look is unchanged).
// Called after every IMAGE / TEXT write (kOS's own and tdCsApply's): c 1 an image path, 0 a text.
// NOT while the C# draws (TD_CS): coproc TdKos.Apply writes TEXT / IMAGE itself (T427K), never through
// tdVis, and cannot SHOW a label kOS hid; so then no label is hidden at all (the gain waits for the C# to show / hide).
// unless tdCsHide: the DLL's WApply then shows / hides each label the C# writes by this same rule.
FUNCTION tdNoHide {
    RETURN TD_CS AND NOT tdCsHide.
}
FUNCTION tdHideSetup {                      // tdInit, before the slots: is the C# show / hide there (TDHIDE)?
    SET tdCsHide TO FALSE.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN. }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN. }
    IF NOT ADDONS:KALS:HASSUFFIX("TDHIDE") { RETURN. }
    ADDONS:KALS:TDHIDE(CHOOSE TD_BLANK_IMG IF TD_CS_HIDE ELSE "").
    SET tdCsHide TO TD_CS_HIDE.
}
FUNCTION tdVis {
    PARAMETER w, c, x.
    IF tdNoHide() { w:SHOW(). RETURN. }
    IF c = 1 { IF x = TD_BLANK_IMG { w:HIDE(). } ELSE { w:SHOW(). } }
    ELSE IF x = " " OR x = "<b> </b>" OR x = "" OR x = "<b></b>" { w:HIDE(). }
    ELSE { w:SHOW(). }
}

FUNCTION tdPut {                            // a sprite's anchor at page px (x, y); name "" hides it
    PARAMETER sl, nm, x, y.
    IF x = sl[11] AND y = sl[12] AND nm = sl[2] AND nm <> "" { tdSlotOn(sl). RETURN. }   // the same call as last time: leave the slot as it is
    IF nm = "" OR NOT tdSpr:HASKEY(nm) { tdSlotOff(sl). RETURN. }
    LOCAL sp IS tdSpr[nm].
    IF sl[2] <> nm {
        SET sl[0]:IMAGE TO sp[0].
        tdVis(sl[0], 1, sp[0]).
        SET sl[0]:STYLE:WIDTH TO sp[1].
        SET sl[0]:STYLE:HEIGHT TO sp[2].
        SET sl[2] TO nm.
    }
    LOCAL xx IS ROUND(x - sp[3]).
    LOCAL yy IS ROUND(y - sp[4]).
    IF xx <> sl[3] {                        // only the margin that moved (a track-up page moves ~100 dashes a draw)
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx + TD_OFF_X).
        SET sl[3] TO xx.
    }
    IF yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy + TD_OFF_Y - TD_IMG_DY - sl[1] * TD_FLOW_PX).
        SET sl[4] TO yy.
    }
    SET sl[11] TO x. SET sl[12] TO y.
    tdSlotOn(sl).
}

FUNCTION tdText {                           // text; align 0 left, 1 right (right edge at x), 2 centred
    PARAMETER sl, s, x, y, align.
    IF s = "" { tdSlotOff(sl). RETURN. }
    IF x = sl[11] AND y = sl[12] AND align = sl[13] AND s = sl[2] { tdSlotOn(sl). RETURN. }   // the same call as last time: leave the slot as it is
    IF sl[2] <> s { LOCAL tx IS CHOOSE "<b>" + s + "</b>" IF sl[14] ELSE s. SET sl[0]:TEXT TO tx. tdVis(sl[0], 0, tx). SET sl[2] TO s. }
    // The label is TD_TXT_W wide, but a right-aligned or centred one near the page's left edge narrows to the room it
    // has: the margin cannot go below 0, so a full-width label there would push the text right.
    LOCAL w IS TD_TXT_W.
    LOCAL xx IS ROUND(x).
    LOCAL al IS "LEFT".
    IF align = 1 { SET w TO MAX(1, MIN(TD_TXT_W, xx)). SET xx TO xx - w. SET al TO "RIGHT". }
    ELSE IF align = 2 { SET w TO MAX(2, MIN(TD_TXT_W, 2 * xx)). SET xx TO ROUND(x - w / 2). SET al TO "CENTER". }
    IF sl[7] <> al { SET sl[0]:STYLE:ALIGN TO al. SET sl[7] TO al. }
    IF sl[8] <> w { SET sl[0]:STYLE:WIDTH TO w. SET sl[8] TO w. }
    LOCAL yy IS ROUND(y - sl[9] * 0.7).
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx + TD_OFF_X).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, ROUND(yy + TD_OFF_Y - TD_TXT_DY + sl[10] - sl[1] * TD_FLOW_PX)).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    SET sl[11] TO x. SET sl[12] TO y. SET sl[13] TO align.
    tdSlotOn(sl).
}

FUNCTION tdWin {                            // ENTRY TRAJ's window: a title row, then a zero-padded box whose STYLE:BG is the page
    PARAMETER title, x, y, w, h, bg, nrow IS 1.   // nrow 2 = a second button row (VERT SIT)
    LOCAL g IS GUI(w).                      // exactly the page's width (was w + 24: a grey strip right of the screen)
    uiDispSkin(g).                          // the frame in the panel look; lib_dap's row buttons take it (made later)
    SET g:STYLE:HEIGHT TO h + 48 + nrow * TD_ROW_H.   // + the button row(s)
    SET g:X TO x. SET g:Y TO y.
    SET g:STYLE:PADDING:H TO 0.
    SET g:STYLE:PADDING:V TO 0.
    LOCAL tb IS g:ADDHLAYOUT().
    LOCAL tl IS tb:ADDLABEL("<b>" + title + "</b>").
    uiDispTitle(tb, tl).
    LOCAL rw IS g:ADDHLAYOUT().             // the button row (lib_dap fills it), its height fixed: the page stays put
    SET rw:STYLE:HEIGHT TO TD_ROW_H.
    SET rw:STYLE:WIDTH TO w.
    LOCAL rw2 IS 0.
    IF nrow > 1 {                           // the second row, as the first
        SET rw2 TO g:ADDHLAYOUT().
        SET rw2:STYLE:HEIGHT TO TD_ROW_H.
        SET rw2:STYLE:WIDTH TO w.
    }
    LOCAL bx IS g:ADDVLAYOUT().
    SET bx:STYLE:PADDING:H TO 0.
    SET bx:STYLE:PADDING:V TO 0.
    SET bx:STYLE:WIDTH TO w.
    SET bx:STYLE:HEIGHT TO h.
    SET bx:STYLE:BG TO bg.
    RETURN LIST(g, bx, rw, rw2, tl).        // + the title label
}

// a hand-off that kept OPS 1's two windows up (ops1q ASC_PG_KEEP_UP) gives them to the deck, so the displays stay up and
// only the pages and buttons switch (lib_ascdisp adAdopt: the ascent's pages hidden, the rows emptied for lib_dap, the
// dock handed on); the same size (the page 736 x 460, the rows TD_ROW_H), retitled, this deck's page boxes added
// (hidden, as tdDeckOpen's)
FUNCTION tdAdopt {
    PARAMETER w, h, tv, th, bgv, bgh.
    IF NOT (DEFINED ASC_PG_KEEP_UP) { RETURN FALSE. }
    IF NOT ASC_PG_KEEP_UP { RETURN FALSE. }
    LOCAL L IS adAdopt().
    IF L:LENGTH = 0 { RETURN FALSE. }
    SET tdGuiV TO L[0]. SET tdRowV TO L[1]. SET tdRowV2 TO L[2]. SET tdTitV TO L[3].
    SET tdGuiH TO L[4]. SET tdRowH TO L[5]. SET tdTitH TO L[6]. SET tdRowH2 TO L[7].
    SET tdTitV:TEXT TO "<b>" + tv + "</b>".
    SET tdTitH:TEXT TO "<b>" + th + "</b>".
    SET tdBoxV TO tdAdoptBox(tdGuiV, w, h, bgv).
    SET tdBoxH TO tdAdoptBox(tdGuiH, w, h, bgh).
    RETURN TRUE.
}

FUNCTION tdAdoptBox {                     // a page box as tdWin's, at the end of a taken window
    PARAMETER g, w, h, bg.
    LOCAL bx IS g:ADDVLAYOUT().
    SET bx:STYLE:PADDING:H TO 0.
    SET bx:STYLE:PADDING:V TO 0.
    SET bx:STYLE:WIDTH TO w.
    SET bx:STYLE:HEIGHT TO h.
    SET bx:STYLE:BG TO bg.
    RETURN bx.
}

// one GUI, the pages swapped: the deck's two windows before the pages, for ENTRY TRAJ's page (traj_display trajInit
// puts its box in tdGuiV); tdInit then puts VERT SIT / HORIZ SIT in the same windows. The page boxes start hidden (kOS
// drops a hidden box from the flow, so the shown one sits under the button row).
FUNCTION tdWins {                          // the pair at the default places (stacked when the screen fits both)
    PARAMETER w, h, tv, th, bgv, bgh.
    IF tdAdopt(w, h, tv, th, bgv, bgh) { RETURN. }   // OPS 1's windows, kept up, taken over in place
    LOCAL stk IS SCR_H >= TD_VS_Y + 2 * (h + 48 + 2 * TD_ROW_H).   // the two stacked fit (tdWin's: the page + 48 px
                                            //   + the rows, two each)
    LOCAL wv IS tdWin(tv, CHOOSE TD_VS_X IF stk ELSE TD_VS_X0, CHOOSE TD_VS_Y IF stk ELSE TD_VS_Y0, w, h, bgv, 2).
    SET tdGuiV TO wv[0]. SET tdBoxV TO wv[1]. SET tdRowV TO wv[2]. SET tdRowV2 TO wv[3]. SET tdTitV TO wv[4].
    LOCAL wh IS tdWin(th, CHOOSE TD_HS_X IF stk ELSE TD_HS_X0,
        CHOOSE TD_VS_Y + h + 48 + 2 * TD_ROW_H IF stk ELSE TD_HS_Y0, w, h, bgh, 2).
    SET tdGuiH TO wh[0]. SET tdBoxH TO wh[1]. SET tdRowH TO wh[2]. SET tdRowH2 TO wh[3]. SET tdTitH TO wh[4].
    dkAttach(tdGuiV, tdGuiH, "td").         // the deck (lib_dock): HORIZ SIT docked under VERT SIT, both where the crew left them
}

FUNCTION tdDeckOpen {                      // trajInit's call; the windows built and hidden, their page boxes hidden
    PARAMETER w, h.
    IF tdDeck OR tdOn { RETURN TRUE. }
    tdWins(w, h, "ENTRY TRAJ", "HORIZ SIT", TD_DIR + "hsit1.png", TD_DIR + "hsit1.png").
    tdBoxV:HIDE(). tdBoxH:HIDE().
    SET tdDeck TO TRUE.
    RETURN TRUE.
}

FUNCTION tdDeckClose {                     // the deck without its pages (a page file missing at tdInit)
    IF NOT tdDeck { RETURN. }
    dkDetach("td").
    tdGuiV:HIDE(). tdGuiH:HIDE().
    SET tdDeck TO FALSE.
}

FUNCTION tdDeckBarH {                     // the bottom window's button rows alone in entry (HUD | HUD CAM | BAILOUT, ALT MODE)
    IF NOT tdDeck { RETURN. }               //   until the entry page fills its box; tdInit gives it its page height back
    SET tdGuiH:STYLE:HEIGHT TO TD_BAR_WIN_H + TD_ROW_H.
    tdGuiH:SHOW().
}

FUNCTION tdInit {
    IF tdOn { tdSetMm(603). RETURN TRUE. }  // the GRTLS's windows go on as TAEM's (one GUI, the pages swapped)
    IF NOT (EXISTS(TD_ARCH + "taem_bg.txt") AND EXISTS(TD_ARCH + "sprites.txt")) { tdDeckClose(). RETURN FALSE. }
    IF NOT tdLoad() { tdDeckClose(). RETURN FALSE. }
    IF NOT tdGrLoad() { tdDeckClose(). RETURN FALSE. }   // grtls_bg.txt
    tdHideSetup().                          // Before any slot is made (their blank labels hide at once)
    SET tdZoomLatch TO CHOOSE 0 IF tdMm = 602 ELSE 1.   // each run starts at the widest zoom (the GRTLS's 0)
    LOCAL w IS tdGeo["png_w"][0].
    LOCAL h IS tdGeo["png_h"][0].
    SET tdBgV TO CHOOSE TD_GR_DIR + "vsit1_602.png" IF tdMm = 602 ELSE TD_DIR + "vsit1.png".   // by the mode
    SET tdBgH TO TD_DIR + "hsit1" + (CHOOSE "t" IF TD_TRKUP ELSE "") + ".png".
    IF tdDeck {                             // ENTRY TRAJ's windows: its page out, VERT SIT / HORIZ SIT in
        SET tdTitV:TEXT TO "<b>VERT SIT</b>".
        SET tdTitH:TEXT TO "<b>HORIZ SIT</b>".
        SET tdBoxV:STYLE:BG TO tdBgV.
        SET tdBoxH:STYLE:BG TO tdBgH.
        SET tdGuiH:STYLE:HEIGHT TO h + 48 + 2 * TD_ROW_H.   // tdWin's (tdDeckBarH's rows alone in entry)
        IF DEFINED tjBox { IF NOT tjBox:ISTYPE("Scalar") { tjBox:HIDE(). } }
        IF DEFINED tjXBox { IF NOT tjXBox:ISTYPE("Scalar") { tjXBox:HIDE(). } }   // ENTRY TRAJ's big X box out too
        IF DEFINED edBox { IF NOT edBox:ISTYPE("Scalar") { edBox:HIDE(). } }   // the entry page out (lib_entdisp)
        IF DEFINED edXBox { IF NOT edXBox:ISTYPE("Scalar") { edXBox:HIDE(). SET edShownF TO FALSE. } }   // And its big X box
        tdBoxV:SHOW().
        tdBoxH:SHOW().
        SET tdDeck TO FALSE.                // the pages own the windows now (tdClose ends them)
    } ELSE {
        tdWins(w, h, "VERT SIT", "HORIZ SIT", tdBgV, tdBgH).
    }
    SET tdCnt TO LEXICON("V", 0, "H", 0).
    SET tdOrd TO LEXICON("V", LIST(), "H", LIST()).
    SET tdSV TO LEXICON().
    SET tdSH TO LEXICON().
    tdGrSlots().                            // the MM 602 slots, first in the VERT SIT box
    // the track-up runway's slots (centreline, then strip) in ONE nested 1 x 1 box, the HORIZ SIT box's first child
    // (lib_entdisp's edNest): its child i flows i px down, so the dashes reach the field's top rows (103 px); as flat
    // children 105 .. 176 they could not (a margin cannot go below 0). The box itself takes flow index 0.
    LOCAL nst IS tdBoxH:ADDVLAYOUT().
    SET nst:STYLE:WIDTH TO 1. SET nst:STYLE:HEIGHT TO 1.
    SET nst:STYLE:PADDING:H TO 0. SET nst:STYLE:PADDING:V TO 0.
    SET nst:STYLE:PADDING:BOTTOM TO 1.      // A nest whose boxes are all hidden keeps its row (tdImgSlot)
    SET nst:STYLE:MARGIN:H TO 0. SET nst:STYLE:MARGIN:V TO 0.
    SET tdCnt["H"] TO 1.
    SET tdNb TO LIST().
    LOCAL nbr IS tdNbNew().
    FROM { LOCAL i IS 0. } UNTIL i >= TD_CLD_N STEP { SET i TO i + 1. } DO { SET tdSH["cl" + i] TO tdNestSlot(nst, i, nbr). }
    FROM { LOCAL i IS 0. } UNTIL i >= TD_RW_N STEP { SET i TO i + 1. } DO { SET tdSH["rw" + i] TO tdNestSlot(nst, TD_CLD_N + i, nbr). }
    // the draw order is the creation order, so the HAC dashes (below) and the orbiter bug with the predictor dots (the
    // LAST child, above everything) each sit in a nested box of their own, as the runway's
    LOCAL nsh IS tdNestNew().
    LOCAL nbh IS tdNbNew().
    FROM { LOCAL i IS 0. } UNTIL i >= TD_HACD_N STEP { SET i TO i + 1. } DO { SET tdSH["hd" + i] TO tdNestSlot(nsh[0], nsh[1] + i, nbh). }
    LOCAL grn IS RGB(0.235, 0.878, 0.235).
    LOCAL alc IS RGB(1, 0.16, 0.16).    // the alert colour (not "red": RED is a kOS bound variable)
    // each page's clock early in its box (last in the flow, its margin would go below 0: clamped, 7 px low)
    SET tdSV["met"] TO tdTxtSlot("V", 13, grn, FALSE).
    SET tdSH["met"] TO tdTxtSlot("H", 13, grn, FALSE).
    FOR k IN LIST("bug", "ebox", "ewtri", "ewarr", "mep", "stn", "albox") { SET tdSV[k] TO tdImgSlot("V"). }
    FOR k IN LIST("r0", "r1", "r2", "r3", "r4", "r5", "r6", "ph", "zm", "al", "stnl", "mepl", "trml") {
        SET tdSV[k] TO tdTxtSlot("V", CHOOSE 13 IF k = "al" ELSE 11, CHOOSE alc IF k = "al" ELSE grn).
    }
    FOR k IN LIST("hac", "bar", "gsi") { SET tdSH[k] TO tdImgSlot("H"). }
    FOR k IN LIST("r0", "r1", "r2", "r3", "r4", "r5", "ph", "zm", "al", "b0", "b1", "b2") {
        SET tdSH[k] TO tdTxtSlot("H", CHOOSE 13 IF k = "al" ELSE 11, CHOOSE alc IF k = "al" ELSE grn).
    }
    FROM { LOCAL i IS 0. } UNTIL i >= 13 STEP { SET i TO i + 1. } DO { SET tdSH["log" + i] TO tdTxtSlot("H", 10, grn). }
    // the bug and the predictor dots last (on top): the box's last child, a nested box, its children flow p + i px down
    LOCAL nsb IS tdNestNew().
    LOCAL ik IS 0.
    FOR k IN LIST("bug", "p1", "p2", "p3") { SET tdSH[k] TO tdNestSlot(nsb[0], nsb[1] + ik). SET ik TO ik + 1. }
    SET tdHdKey TO "".
    FROM { LOCAL i IS 0. } UNTIL i >= 7 STEP { SET i TO i + 1. } DO { LOCAL rs IS tdSV["r" + i]. SET rs[10] TO TD_VS_ROW_DY. }
    LOCAL rtl IS tdSV["trml"]. SET rtl[10] TO TD_VS_ROW_DY.   // the GRTLS pages' TRIM label on the readouts' rows
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO { LOCAL rs IS tdSH["r" + i]. SET rs[10] TO TD_HS_ROW_DY. }
    LOCAL cv IS tdSV["met"]. SET cv[10] TO TD_CLK_DY.
    LOCAL ch IS tdSH["met"]. SET ch[10] TO TD_CLK_DY.
    SET tdAll TO LIST().                    // the sweep's list: tdSV's slots, then tdSH's, in their order
    FOR k IN tdSV:KEYS { tdAll:ADD(tdSV[k]). }
    FOR k IN tdSH:KEYS { tdAll:ADD(tdSH[k]). }
    SET tdLogSl TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= 13 STEP { SET i TO i + 1. } DO { tdLogSl:ADD(tdSH["log" + i]). }
    SET tdLogDrawn TO -1.
    tdGuiV:SHOW().
    tdGuiH:SHOW().
    SET tdOn TO TRUE.
    SET tdPg TO TRUE.
    SET tdT0 TO TIME:SECONDS.
    SET tdMet0 TO TIME:SECONDS - MISSIONTIME.
    tdCsSetup().                            // the C# pages (or why not)
    tdPaintSetup().                         // The painter (TD_PAINT; OFF by default)
    gpcWin("TOP", tdGpcXT@).                // The windows' X looks (lib_gpc): TOP = VERT SIT, BOT = HORIZ SIT
    gpcWin("BOT", tdGpcXB@).
    RETURN TRUE.
}

FUNCTION tdSweep {                          // after a cycle's drawing: hide only the shown slots it did not draw
    FOR sl IN tdAll { IF sl[5] { IF sl[6] <> tdCyc { tdSlotOff(sl). } } }
    tdNbTrim().
}

FUNCTION tdMsgRow {                         // the status row on one page: phase, ZOOM, the alert, the MET clock
    PARAMETER sl, tg, msg.
    LOCAL mr IS tdGeo["msg_row_px"].
    tdText(sl["ph"], CHOOSE tg["ph_word"] IF tg:HASKEY("ph_word") ELSE LIST("S-TURN", "ACQ", "HDG", "PRFNL")[tg["iphase"]],
           mr[0], mr[3], 0).                // the GRTLS phase word
    IF tg:HASKEY("zoom") AND tg["zoom"] <> 0 { tdText(sl["zm"], "ZOOM", mr[1], mr[3], 0). }
    tdText(sl["al"], msg, mr[2], mr[3], 2).
    LOCAL ck IS tdGeo["clock_px"].
    tdText(sl["met"], tdClock(), ck[0], ck[1], 1).
}

FUNCTION tdClock {                          // the mission's MET, DDD/HH:MM:SS (ENTRY TRAJ's tjClock)
    LOCAL a IS FLOOR(MAX(0, TIME:SECONDS - tdMet0)).
    RETURN ("" + FLOOR(a / 86400)):PADLEFT(3):REPLACE(" ", "0") + "/"
        + ("" + FLOOR(MOD(a, 86400) / 3600)):PADLEFT(2):REPLACE(" ", "0") + ":"
        + ("" + FLOOR(MOD(a, 3600) / 60)):PADLEFT(2):REPLACE(" ", "0") + ":"
        + ("" + MOD(a, 60)):PADLEFT(2):REPLACE(" ", "0").
}

FUNCTION tdKmPx {                           // a (range km, h km) point of VERT SIT panel k -> page px
    PARAMETER k, xkm, ykm.
    LOCAL f IS tdGeo["vs_field_px"].
    LOCAL a IS tdGeo["vs" + k + "_km"].
    LOCAL fx IS (xkm - a[0]) / (a[1] - a[0]).
    LOCAL fy IS (ykm - a[2]) / (a[3] - a[2]).
    RETURN LIST(f[0] + f[2] * fx, f[1] + f[3] * (1 - fy)).   // the panel's x runs lo to hi, its y up (the page's y runs down)
}

// inside VERT SIT panel k's range (km), and inside the HORIZ SIT field (page px): an energy box off-scale, a bug or
// predictor circle off the plot is hidden
FUNCTION tdInVs {
    PARAMETER k, xkm, ykm.
    LOCAL a IS tdGeo["vs" + k + "_km"].
    RETURN xkm >= a[0] AND xkm <= a[1] AND ykm >= a[2] AND ykm <= a[3].
}

// the sprite nm anchored at page px (x, y), where tdPut draws it, wholly inside the box b (left, top, width, height px)
// less TD_FIT_IN: a sprite is shown only when it is FULLY inside the box it lives in
FUNCTION tdFits {
    PARAMETER nm, x, y, b.
    IF NOT tdSpr:HASKEY(nm) { RETURN FALSE. }
    LOCAL sp IS tdSpr[nm].
    LOCAL l IS ROUND(x - sp[3]).
    LOCAL t IS ROUND(y - sp[4]).
    RETURN l >= b[0] + TD_FIT_IN AND l + sp[1] <= b[0] + b[2] - TD_FIT_IN AND t >= b[1] + TD_FIT_IN
        AND t + sp[2] <= b[1] + b[3] - TD_FIT_IN.
}

FUNCTION tdVsBugLeft {                      // TRUE when the VERT SIT bug sprite nm anchored at x ends left of the readouts'
    PARAMETER nm, x.                        //   labels (vs_readout_px[0]): the energy / range
    IF NOT tdSpr:HASKEY(nm) { RETURN FALSE. }   // bug shows only left of the labels
    RETURN x - tdSpr[nm][3] + tdSpr[nm][1] < tdGeo["vs_readout_px"][0].
}

// VERT SIT's sprite nm anchored at (x, y) is drawn only left of the labels (tdVsBugLeft) and, on the GRTLS pages
// (MM 602), clear of the alpha / Mach box (the bug and the box hide under it)
FUNCTION tdVsShow {
    PARAMETER nm, x, y.
    IF NOT tdFits(nm, x, y, tdGeo["vs_field_px"]) { RETURN FALSE. }   // wholly inside the field
    IF NOT tdVsBugLeft(nm, x) { RETURN FALSE. }
    IF tdMm <> 602 OR NOT tdGr:HASKEY("am_box_px") { RETURN TRUE. }
    LOCAL sp IS tdSpr[nm].
    LOCAL b IS tdGr["am_box_px"].           // x, y, w, h (page px)
    LOCAL l IS x - sp[3].
    LOCAL t IS y - sp[4].
    RETURN NOT (l < b[0] + b[2] AND l + sp[1] > b[0] AND t < b[1] + b[3] AND t + sp[2] > b[1]).
}

FUNCTION tdEwY {                            // EOW - EN (m) -> the strip's row (px)
    PARAMETER val.
    LOCAL s IS tdGeo["vs_strip_px"].        // spine x, top row, bottom row, E lo, E hi
    LOCAL f IS MAX(0, MIN(1, (val - s[3]) / (s[4] - s[3]))).
    RETURN s[2] + (s[1] - s[2]) * f.
}

FUNCTION tdLogEvent {
    PARAMETER s.
    LOCAL met IS TIME:SECONDS - tdT0.
    LOCAL mm IS FLOOR(met / 60).
    LOCAL ss IS FLOOR(MOD(met, 60)).
    tdLog:INSERT(0, (CHOOSE "0" IF mm < 10 ELSE "") + mm + ":" + (CHOOSE "0" IF ss < 10 ELSE "") + ss + " " + s:SUBSTRING(0, MIN(s:LENGTH, 22))).
}

// lib_gpc: the X look of a window whose GPC has failed (TOP = VERT SIT's box, BOT = HORIZ SIT's): dead TRUE: its slots blanked, the box shows
// the big X (gui_panel/gpc_x); FALSE: the box's background set again by the next draw (tdBgV / tdBgH cleared). tdTickK does not draw a dead window.
FUNCTION tdGpcX {
    PARAMETER win, dead.
    IF NOT tdOn { RETURN. }
    IF win = "TOP" {
        IF dead {
            FOR sl IN tdSV:VALUES { IF sl[5] { tdSlotOff(sl). } }
            SET tdBoxV:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
        }
        SET tdBgV TO "".
    } ELSE {
        IF dead {
            FOR sl IN tdSH:VALUES { IF sl[5] { tdSlotOff(sl). } }
            SET tdBoxH:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
        }
        SET tdBgH TO "".
    }
}
FUNCTION tdGpcXT { PARAMETER dead. tdGpcX("TOP", dead). }
FUNCTION tdGpcXB { PARAMETER dead. tdGpcX("BOT", dead). }
FUNCTION tdSweepW {                         // tdSweep for the live windows only (a frozen / dead one keeps what it shows)
    PARAMETER lvT, lvB.
    IF lvT { FOR sl IN tdSV:VALUES { IF sl[5] { IF sl[6] <> tdCyc { tdSlotOff(sl). } } } }
    IF lvB { FOR sl IN tdSH:VALUES { IF sl[5] { IF sl[6] <> tdCyc { tdSlotOff(sl). } } } }
    tdNbTrim().
}

FUNCTION tdGpcGate {                        // TRUE = draw nothing this call (both windows' GPCs out, or the DLL cannot draw one window and it is not a cycle's draw)
    PARAMETER cyc.
    LOCAL gpT IS gpcLive("TOP").
    LOCAL gpB IS gpcLive("BOT").
    IF gpT AND gpB { RETURN FALSE. }
    IF NOT tdGpcCs {                        // an older DLL does not know the X look's blanked slots: the kOS draw takes over (tdCsOff, as any failure), once per cycle
        IF tdCsOn { tdCsOff("GPC FAIL"). }
        IF NOT cyc { RETURN TRUE. }
    }
    RETURN NOT (gpT OR gpB).
}

FUNCTION tdTick {                           // draws both pages; the host calls it after each TAEM cycle (cyc TRUE) and,
    PARAMETER tg, st, cyc IS TRUE.          //   between the cycles every TD_DT_CS s while tdFast (cyc FALSE)
    IF NOT tdOn OR NOT tdPg { RETURN. }
    IF tdGpcGate(cyc) { RETURN. }           // A window whose GPC failed is not drawn (the C# draw is told which ones live)
    SET tdFlashClk TO tdFast() AND TD_DT_CS > 0.   // the flash on the grid (Td.cs reads it)
    SET tdRtT TO uiRt().                    // the grid in real time
    SET tdSbA TO CHOOSE 2 * dSbBase IF (DEFINED dSbBase) ELSE -1.
    IF DEFINED SB_SUPER_MAX { SET tdSbCap TO 2 * SB_SUPER_MAX. SET tdSbCapM TO SB_SUPER_MACH. }
    IF tdCsOn AND TD_CS {                   // C# draws (TD_CS)
        IF tdCsDraw(0, tg, st, cyc, 0, 0, 0) { RETURN. }
    }
    tdTickK(tg, st, cyc).
}

GLOBAL tdGdLost IS FALSE.                   // Only the guidance COMMANDS blank (VERT SIT's SB cmd and NZ cmd); the HAC geometry and EOW stay live. SW 02 GUIDANCE LOST for the TAEM phase (tdTickK): the command readouts show "----"
FUNCTION tdTickK {                          // tdTick's kOS drawing (tdGrTick's phase 4 calls it directly)
    PARAMETER tg, st, cyc.
    IF NOT tdOn OR NOT tdPg { RETURN. }
    SET tdGdLost TO FALSE.
    IF DEFINED FLFX_SWPROG { IF DEFINED FLFX_PH { SET tdGdLost TO flfxSwGuid(FLFX_PH). } }
    tdFlashStep(cyc).                       // the flash
    LOCAL g IS tg["g"].
    LOCAL phs IS LIST("S-TURN", "ACQ", "HDG", "PRFNL").
    IF tg["iphase"] <> tdLastPh { tdLogEvent(phs[tg["iphase"]]). SET tdLastPh TO tg["iphase"]. }
    LOCAL msg IS "".                        // the event list: the messages as latched, each logged once when it changes
    IF tg["dm_msg"] <> "" { SET msg TO tg["dm_msg"]:TRIM. }
    IF msg <> tdLastMsg { IF msg <> "" { tdLogEvent(msg). } SET tdLastMsg TO msg. }
    // the message row: the OTT message while the guidance RECOMMENDS it, never after it is taken (lib_land's ldDmShow =
    // lib_dap's dapDmRec); none without lib_land
    LOCAL dmShown IS "".
    IF DEFINED ldDmShow { SET dmShown TO ldDmShow. }
    SET msg TO "".
    IF dmShown <> "" { SET msg TO dmShown:TRIM. }
    SET tdCyc TO tdCyc + 1.                 // draw, then hide what this cycle did not draw
    LOCAL e IS tdEnNow(tg, st, cyc).        // the range and energies now
    LOCAL lvT IS gpcLive("TOP").            // Only the windows whose GPC lives
    LOCAL lvB IS gpcLive("BOT").
    IF lvT { tdVs(tg, st, g, e). }          // both pages every cycle (two windows)
    IF lvB { tdHs(tg, st, g, cyc, e). }
    IF lvT { tdMsgRow(tdSV, tg, msg). }
    IF lvB { tdMsgRow(tdSH, tg, msg). }
    IF lvT AND lvB { tdSweep(). } ELSE { tdSweepW(lvT, lvB). }
    IF cyc { SET tdPrev TO LEXICON("psd", st["psd"], "t", TIME:SECONDS). }   // the turn rate's baseline: a cycle
}

FUNCTION tdFlashStep {                      // the flash steps at every draw (5 Hz at the redraws' 10 Hz);
    PARAMETER cyc.                          //   while the C# draws live (tdFlashClk) the grid slot's parity
    IF tdFlashClk { SET tdFlash TO MOD(FLOOR((tdRtT + 0.005) / TD_DT_CS), 2) = 0. }   // real time
    ELSE { SET tdFlash TO NOT tdFlash. }
}

FUNCTION tdGridNx {                         // the next redraw, the grid point after t's slot (0.005 s early, so
    PARAMETER t.                            //   the tick at the point fires and counts as the new slot); t
                                            //   and the result in real seconds (uiRt)
    RETURN (FLOOR((t + 0.005) / TD_DT_CS) + 1) * TD_DT_CS - 0.005.
}

FUNCTION tdEnNow {                          // LIST(drpred, en, en_of_dr - href, eow, href) now: a cycle's tg's
    PARAMETER tg, st, cyc.                  //   (tdEnS set), a redraw's moved on from the cycle's draw
    LOCAL now IS TIME:SECONDS.
    IF cyc {
        LOCAL d IS tg["drpred"].
        LOCAL en IS tg["en"].
        LOCAL eh IS tg["en_of_dr"] - tg["href"].
        LOCAL hr IS tg["href"].
        LOCAL sk IS LIST(0, 0, 0).
        IF tdEnS:HASKEY("t") {
            LOCAL dd IS d - tdEnS["d"].
            IF ABS(dd) > 1 AND now - tdEnS["t"] < 5 {
                SET sk TO LIST(MAX(-2, MIN(2, (en - tdEnS["en"]) / dd)), MAX(-2, MIN(2, (eh - tdEnS["eh"]) / dd)),
                               MAX(-2, MIN(2, (hr - tdEnS["hr"]) / dd))).
            }
        }
        SET tdEnS TO LEXICON("t", now, "d", d, "en", en, "eh", eh, "hr", hr, "sen", sk[0], "seh", sk[1], "shr", sk[2]).
        RETURN LIST(d, en, eh, tg["eow"], hr).
    }
    LOCAL ok IS tdEnS:HASKEY("t").
    IF ok { SET ok TO now - tdEnS["t"] <= 5. }
    IF NOT ok {
        RETURN LIST(tg["drpred"], tg["en"], tg["en_of_dr"] - tg["href"], tg["eow"], tg["href"]).
    }
    LOCAL dd IS 0 - st["vh"] * MAX(0, MIN(2, now - tdEnS["t"])).
    LOCAL ew IS st["h"] + st["surfv"] ^ 2 / (2 * TG_GO).
    // the GRTLS's ECAL phugoid term (TGCOMP 2.1.1, EOW += GR_ECOMPG EOW HDOT; lib_grtls sets its gain tg["ecompk"]), as
    // the cycle draws it, so the energy state does not jump at each guidance update
    IF tg:HASKEY("ecompk") { SET ew TO ew + tg["ecompk"] * ew * st["hdot"]. }
    RETURN LIST(tdEnS["d"] + dd, tdEnS["en"] + tdEnS["sen"] * dd, tdEnS["eh"] + tdEnS["seh"] * dd,
                ew, tdEnS["hr"] + tdEnS["shr"] * dd).
}

// the HAC bar's time counts down at the rate the guidance's own estimate (rtan / vh) has been falling, not 1 s/s: in
// the acquisition turn the estimate holds while the orbiter turns onto the tangent, so a 1 s/s count would fall away
// from it and jump back up at every cycle. At a cycle the step to the new estimate blends out over TD_TTH_BLEND_S.
FUNCTION tdTthNow {
    PARAMETER est, cyc.
    LOCAL now IS TIME:SECONDS.
    IF NOT tdTh:HASKEY("t") OR (cyc AND now > tdTh["t"] + 0.05) {
        LOCAL rate IS 1.
        LOCAL stp IS 0.
        IF tdTh:HASKEY("t") AND now - tdTh["t"] < 10 {
            LOCAL dt IS now - tdTh["t"].
            SET rate TO tdTh["rate"] + TD_TTH_RK * (MAX(-0.5, MIN(1.5, (tdTh["est"] - est) / dt)) - tdTh["rate"]).
            SET stp TO tdTthAt(dt) - est.
            IF ABS(stp) >= 30 { SET stp TO 0. }
        }
        SET tdTh TO LEXICON("t", now, "est", est, "rate", rate, "off", stp).
    }
    RETURN tdTthAt(now - tdTh["t"]).
}
FUNCTION tdTthAt {
    PARAMETER el.
    RETURN tdTh["est"] - tdTh["rate"] * el + tdTh["off"] * MAX(0, 1 - el / TD_TTH_BLEND_S).
}

// the GRTLS's (MM 602) wider zooms: VERT SIT 0 (taem_bg vs0_km, 60-220 km, 10-70 km) while outside panel 1, and HORIZ
// SIT 0 (hs0_km, +-180 km) while outside zoom 1: the RTLS boots 124-140 km from the site, 53-56 km up. TAEM's pages
// (MM 603) keep 1 / 2 and 1-3.
FUNCTION tdVsK {                            // VERT SIT's panel for drpred d and height h (m)
    PARAMETER d, h.
    IF d / 1000 < tdGeo["vs_switch_km"][0] { RETURN 2. }
    LOCAL a IS tdGeo["vs1_km"].
    IF tdMm = 602 AND (d / 1000 > a[1] OR h / 1000 > a[3]) { RETURN 0. }
    RETURN 1.
}

FUNCTION tdVs {                             // draws the VERT SIT page
    PARAMETER tg, st, g, e.                 // e = tdEnNow's
    LOCAL d IS e[0].
    LOCAL k IS tdVsK(d, st["h"]).
    LOCAL bgv IS CHOOSE TD_GR_DIR + "vsit" + k + "_602.png" IF tdMm = 602 ELSE TD_DIR + "vsit" + k + ".png".
    IF bgv <> tdBgV { SET tdBoxV:STYLE:BG TO bgv. SET tdBgV TO bgv. }
    LOCAL gam IS ARCTAN2(st["hdot"], MAX(st["surfv"], 1)).
    LOCAL gi IS MAX(-40, MIN(14, 2 * ROUND(gam / 2))).
    LOCAL bp IS tdKmPx(k, d / 1000, st["h"] / 1000).
    LOCAL bn IS "vsbug_" + (CHOOSE "m" IF gi < 0 ELSE "p") + (CHOOSE "0" IF ABS(gi) < 10 ELSE "") + ABS(gi).
    IF tdVsShow(bn, bp[0], bp[1]) { tdPut(tdSV["bug"], bn, bp[0], bp[1]). }   // left of the labels only (not drawn = hidden)
    LOCAL hb IS (e[3] - e[2]) / 1000.       // taemg_comp's en_of and href at d (not computed again; moved on)
    LOCAL ep IS tdKmPx(k, d / 1000, hb).
    // off the panel (or over the labels, as the bug) not drawn
    IF tdInVs(k, d / 1000, hb) AND tdVsShow("ebox", ep[0], ep[1]) { tdPut(tdSV["ebox"], "ebox", ep[0], ep[1]). }   // The energy box is EOW: it stays under SW 02
    LOCAL sx IS tdGeo["vs_strip_px"][0].
    LOCAL lab IS tdGeo["vs_label_px"].      // label x, NOM row, STN row, MEP clearance
    IF NOT (tg["iphase"] = TG_IPH_STURN AND NOT tdFlash) { tdPut(tdSV["ewtri"], "ewtri", sx, tdEwY(e[3] - e[1])). }   // EOW stays under SW 02
    IF tg["iphase"] = TG_IPH_STURN OR (tg["iphase"] = TG_IPH_ACQ AND d > TG_RMINST AND g["psha"] < TG_PSSTRN) {
        LOCAL ys IS tdEwY(TG_STURN_DELTA).
        tdPut(tdSV["stn"], "stn", sx, ys).
        tdText(tdSV["stnl"], "STN", lab[0], ys, 0).
    }
    IF tg["mep_avail"] AND tg["iphase"] = TG_IPH_ACQ AND tg["t_to_hac"] >= TG_DM_T_HAC_MEP {
        LOCAL ym IS tdEwY(tg["emep"] - tg["en"]).
        tdPut(tdSV["mep"], "mep", sx, ym).
        LOCAL yl IS ym.
        FOR ysn IN LIST(tdEwY(0), tdEwY(TG_STURN_DELTA)) {
            IF ABS(yl - ysn) < lab[3] { SET yl TO CHOOSE ysn - lab[3] IF ym < ysn ELSE ysn + lab[3]. }
        }
        tdText(tdSV["mepl"], "MEP", lab[0], yl, 0).
    }
    IF tg["strt_avail"] AND tg["iphase"] = TG_IPH_ACQ AND d > taemg_drpred_of(TG_RMOH) AND tg["t_to_hac"] >= TG_DM_T_HAC_STRT {
        tdPut(tdSV["ewarr"], "ewarr", sx, tdEwY(tg["emoh"] - tg["en"])).
    }
    LOCAL rd IS tdGeo["vs_readout_px"].     // label x, value right x, 7 rows
    LOCAL sbCmd IS tg["dsbc"].               // the command as the DAP flies it: capped above Mach 1.5 (the GRTLS's sbSet is capped already)
    IF tdSbA >= 0 AND st["mach"] > tdSbCapM { SET sbCmd TO MIN(sbCmd, tdSbCap). }
    LOCAL vals IS LIST(ROUND(TD_SB_PCT * (CHOOSE tdSbA IF tdSbA >= 0 ELSE tg["dsbc"])), ROUND(TD_SB_PCT * sbCmd), ROUND(CHOOSE tg["nz_meas"] IF tg:HASKEY("nz_meas") ELSE tg["nz_total"], 2),
                       ROUND(tg["nz_total"], 2), ROUND(tg["qbarf"] / TD_PSF),
                       CHOOSE tdTrimTxt() IF tdMm = 602 ELSE ROUND(tg["qbref"] / TD_PSF), ROUND(st["mach"], 2)).
    // The guidance's commands blank while SW 02 holds TAEM (rows 1 sb command, 3 Nz command;
    // row 0 the sb actual when there is one, else the command). Row 5 (trim / QREF) stays: not a command. Rows 2 (Nz measured), 4 (q), 6 (Mach) stay: raw
    FROM { LOCAL i IS 0. } UNTIL i >= 7 STEP { SET i TO i + 1. } DO {
        LOCAL vb IS tdGdLost AND (i = 1 OR i = 3 OR (i = 0 AND tdSbA < 0)).
        tdText(tdSV["r" + i], CHOOSE "----" IF vb ELSE "" + vals[i], rd[1], rd[2 + i], 1).
    }
    IF tdMm = 602 { tdText(tdSV["trml"], "TRIM", rd[0], rd[7], 0). }   // GRTLS: TRIM where TAEM says QREF (its label out of vsit*_602.png)
}

// ---- the track-up world. A runway-frame point (X, Y km) seen from the vehicle (x, y km) on the track psd: ahead =
// (X - x) COS psd + (Y - y) SIN psd, right = (Y - y) COS psd - (X - x) SIN psd; the page px = the bug's + right * ppk, - ahead * ppk
FUNCTION tdTuHead {                         // the turn of this draw (the bug's place and the scale follow: tdTuPlace)
    PARAMETER xk, yk, psd.
    SET tdTuG TO LIST(xk, yk, COS(psd), SIN(psd), 0, 0, 1).
}
FUNCTION tdTuPlace {
    PARAMETER bx, by, ppk.
    SET tdTuG[4] TO bx. SET tdTuG[5] TO by. SET tdTuG[6] TO ppk.
}
FUNCTION tdTuRel {                          // a runway-frame point (km) -> LIST(km ahead along the track, km to the right)
    PARAMETER xk, yk.
    LOCAL dx IS xk - tdTuG[0].
    LOCAL dy IS yk - tdTuG[1].
    RETURN LIST(dx * tdTuG[2] + dy * tdTuG[3], dy * tdTuG[2] - dx * tdTuG[3]).
}
FUNCTION tdTuPg {                           // the same point -> page px
    PARAMETER xk, yk.
    LOCAL rl IS tdTuRel(xk, yk).
    RETURN LIST(tdTuG[4] + rl[1] * tdTuG[6], tdTuG[5] - rl[0] * tdTuG[6]).
}
FUNCTION tdTuHolds {                        // zoom z holds every (ahead, right) km point of pts inside frac of the room: ahead
    PARAMETER z, frac, pts.                 //   2 hw TD_TU_BY, behind 2 hw (1 - TD_TU_BY), to a side hw
    LOCAL hw IS tdGeo["hs" + z + "_km"][2].
    FOR p IN pts {
        IF p[0] > 2 * hw * TD_TU_BY * frac OR p[0] < -2 * hw * (1 - TD_TU_BY) * frac OR ABS(p[1]) > hw * frac { RETURN FALSE. }
    }
    RETURN TRUE.
}
FUNCTION tdTuAim {                          // the aim's centre: the HAC circle's (phases 1 / 2), the threshold in the final (3)
    PARAMETER iph, hx, hy.
    IF iph = 3 { RETURN tdTuRel(0, 0). }
    RETURN tdTuRel(hx, hy).
}
FUNCTION tdTuPts {                          // what zoom must hold: the HAC circle's four extreme points, or the threshold
    PARAMETER iph, rkm, hx, hy.
    IF iph = 3 { RETURN LIST(tdTuRel(0, 0)). }
    LOCAL c IS tdTuRel(hx, hy).
    RETURN LIST(LIST(c[0] + rkm, c[1]), LIST(c[0] - rkm, c[1]), LIST(c[0], c[1] + rkm), LIST(c[0], c[1] - rkm)).
}
FUNCTION tdTuOut {                          // tdHsOut's twin: zoom z, or the tightest wider one on which the aim a (ahead, right km)
    PARAMETER z, a.                         //   lies inside TD_HS_OUT of the room; TD_HS_ZMIN at the most
    UNTIL z <= TD_HS_ZMIN {
        IF tdTuHolds(z, TD_HS_OUT, LIST(a)) { RETURN z. }
        SET z TO z - 1.
    }
    RETURN TD_HS_ZMIN.
}
FUNCTION tdTuRlen {                         // the runway's length (m) for the strip
    IF DEFINED ldRwy { IF ldRwy:HASKEY("len") { RETURN ldRwy["len"]. } }
    RETURN TD_RW_DEF.
}
FUNCTION tdTuName {                         // the dash sprite of family fam ("cld_", "rwd_", "rws_") for the page angle ang (deg from
    PARAMETER fam, ang.                     //   +x toward +y, a line: mod 180) at the nearest of TD_HACD_NO orientations
    LOCAL o IS MOD(ROUND(MOD(MOD(ang, 180) + 180, 180) * TD_HACD_NO / 180), TD_HACD_NO).
    RETURN fam + (CHOOSE "0" IF o < 10 ELSE "") + o.
}
FUNCTION tdTuRwy {                          // the runway as dashes on the turned world: the strip, its centreline both ways
    PARAMETER f, rlen.                      //   (the field px, the runway's length m)
    LOCAL ppk IS tdTuG[6].
    LOCAL ux IS -tdTuG[3].                  // the runway's +x on the page, per px along it
    LOCAL uy IS -tdTuG[2].
    LOCAL ang IS ARCTAN2(uy, ux).
    LOCAL t0 IS tdTuPg(0, 0).
    LOCAL lpx IS rlen / 1000 * ppk.
    LOCAL h IS TD_RW_STK / 2.
    LOCAL ls IS lpx + TD_RW_STK.            // the strip as the page drew it: the outline adds half a stroke at each end
    LOCAL dl IS TD_RWD_L.
    LOCAL fam IS "rwd_".
    IF ls < dl { SET dl TO TD_RWS_L. SET fam TO "rws_". }
    LOCAL nm IS tdTuName(fam, ang).
    LOCAL n IS MIN(TD_RW_N, MAX(1, CEILING(ls / dl))).
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        LOCAL c IS ls / 2 - h.              // a strip of one dash, else butted from the threshold end, the last one overlapping
        IF ls > dl { SET c TO MIN(ls - dl / 2, i * dl + dl / 2) - h. }
        LOCAL px IS t0[0] + ux * c.
        LOCAL py IS t0[1] + uy * c.
        IF tdFits(nm, px, py, f) { tdPut(tdSH["rw" + i], nm, px, py). }
    }
    // the centreline, dashes at s = k TD_CLD_P px along the axis from the threshold (anchored to the world: they stream by),
    // none under the strip; the k that can show: within the field's reach from the bug
    LOCAL cnm IS tdTuName("cld_", ang).
    // the dashes sit on ONE digital line: the threshold rounded once (the whole line steps together by whole pixels),
    // every dash's offset along the line rounded on the line's major axis and the other axis from that rounded one (never both
    // axes independently), so the dashes stay collinear, step together and keep one pattern while the line slides
    LOCAL csp IS CHOOSE tdSpr[cnm] IF tdSpr:HASKEY(cnm) ELSE LIST(0, 0, 0, 0, 0).
    LOCAL cx0 IS ROUND(t0[0] - csp[3]) + csp[3].
    LOCAL cy0 IS ROUND(t0[1] - csp[4]) + csp[4].
    LOCAL cxm IS ABS(ux) >= ABS(uy).
    LOCAL bx IS tdTuG[4].
    LOCAL by IS tdTuG[5].
    LOCAL rr IS MAX(bx - f[0], f[0] + f[2] - bx) ^ 2 + MAX(by - f[1], f[1] + f[3] - by) ^ 2.
    LOCAL yy IS (tdTuG[1] * ppk) ^ 2.
    IF rr > yy {
        LOCAL hh IS SQRT(rr - yy).
        LOCAL s0 IS tdTuG[0] * ppk.
        LOCAL k1 IS FLOOR((s0 + hh) / TD_CLD_P).
        FROM { LOCAL k IS CEILING((s0 - hh) / TD_CLD_P). } UNTIL k > k1 STEP { SET k TO k + 1. } DO {
            LOCAL s IS k * TD_CLD_P.
            IF s < -h OR s > lpx + h {
                LOCAL dx IS 0.
                LOCAL dy IS 0.
                IF cxm { SET dx TO ROUND(s * ux). SET dy TO ROUND(dx * uy / ux). }
                ELSE { SET dy TO ROUND(s * uy). SET dx TO ROUND(dy * ux / uy). }
                LOCAL px IS cx0 + dx.
                LOCAL py IS cy0 + dy.
                IF tdFits(cnm, px, py, f) { tdPut(tdSH["cl" + MOD(MOD(k, TD_CLD_N) + TD_CLD_N, TD_CLD_N)], cnm, px, py). }
            }
        }
    }
}

// HORIZ SIT keeps the orbiter on the page: zoom z, or the tightest wider one whose window holds the vehicle (x, y km)
// inside TD_HS_OUT x its half-width (the zoom-in rule's HS_ZOOM_IN 0.85 below it: no chatter); TD_HS_ZMIN at the most
FUNCTION tdHsOut {
    PARAMETER z, x, y.
    UNTIL z <= TD_HS_ZMIN {
        LOCAL zz IS tdGeo["hs" + z + "_km"].
        LOCAL lim IS TD_HS_OUT * zz[2].
        IF ABS(x - zz[0]) <= lim AND ABS(y - zz[1]) <= lim { RETURN z. }
        SET z TO z - 1.
    }
    RETURN TD_HS_ZMIN.
}
FUNCTION tdHsPin {                          // sprite nm at page px (x, y) held wholly inside the field b
    PARAMETER nm, x, y, b.
    IF NOT tdSpr:HASKEY(nm) { RETURN LIST(x, y). }
    LOCAL sp IS tdSpr[nm].
    LOCAL e IS TD_FIT_IN + 1.
    RETURN LIST(MAX(b[0] + e + sp[3], MIN(b[0] + b[2] - e - sp[1] + sp[3], x)),
                MAX(b[1] + e + sp[4], MIN(b[1] + b[3] - e - sp[2] + sp[4], y))).
}

FUNCTION tdHacArc {                         // the HAC circle (centre cx, cy, radius rpx page px) as tangent dashes,
    PARAMETER cx, cy, rpx, f.               //   each shown when wholly inside the field f
    LOCAL ky IS ROUND(cx) + " " + ROUND(cy) + " " + ROUND(rpx).
    IF ky = tdHdKey {                       // placed already: kept on
        FROM { LOCAL j IS 0. } UNTIL j >= tdHdUsed STEP { SET j TO j + 1. } DO { tdSlotOn(tdSH["hd" + j]). }
        RETURN.
    }
    SET tdHdKey TO ky.
    LOCAL n IS MIN(TD_HACD_N, MAX(8, CEILING(2 * CONSTANT:PI * rpx / TD_HACD_L))).
    LOCAL j IS 0.
    FROM { LOCAL k IS 0. } UNTIL k >= n STEP { SET k TO k + 1. } DO {
        LOCAL th IS 360 * k / n.            // from the page's up, clockwise: the tangent lies th from +x toward +y (down)
        LOCAL o IS MOD(ROUND(th * TD_HACD_NO / 180), TD_HACD_NO).
        LOCAL nm IS "hacd_" + (CHOOSE "0" IF o < 10 ELSE "") + o.
        LOCAL x IS cx + rpx * SIN(th).
        LOCAL y IS cy - rpx * COS(th).
        IF tdFits(nm, x, y, f) {
            tdPut(tdSH["hd" + j], nm, x, y).
            SET j TO j + 1.
        }
    }
    SET tdHdUsed TO j.
}

FUNCTION tdHs {                             // draws the HORIZ SIT page
    PARAMETER tg, st, g, cyc, e.            // e = tdEnNow's
    // the smallest zoom window that holds the vehicle and the HAC circle inside HS_ZOOM_IN x hw
    LOCAL x IS st["x"] / 1000.
    LOCAL y IS st["y"] / 1000.
    LOCAL rkm IS taemg_rturn_of(g["psha"], tg["rf"], tg["r2"]) / 1000.
    LOCAL hx IS taemg_xhac_of(tg["nep"]) / 1000.
    LOCAL hy IS tg["ysgn"] * tg["rf"] / 1000.
    LOCAL zin IS tdGeo["hs_zoom_in"][0].
    LOCAL zoom IS -9.                       // none yet (-1 is a zoom)
    LOCAL tu IS TD_TRKUP.
    IF tu {                                 // track up: the vehicle is fixed on the page, so the AIM decides
        tdTuHead(x, y, st["psd"]).
        LOCAL pts IS tdTuPts(tg["iphase"], rkm, hx, hy).
        FOR z IN LIST(3, 2, 1) { IF zoom < 0 AND tdTuHolds(z, TD_TU_IN, pts) { SET zoom TO z. } }
    } ELSE {
    FOR z IN LIST(3, 2, 1) {
        LOCAL zz IS tdGeo["hs" + z + "_km"].
        LOCAL lim IS zin * zz[2].
        LOCAL ok IS x >= zz[0] - lim AND x <= zz[0] + lim AND y >= zz[1] - lim AND y <= zz[1] + lim.
        IF tg["iphase"] <> 3 AND ok {
            SET ok TO hx - rkm >= zz[0] - lim AND hx + rkm <= zz[0] + lim AND hy - rkm >= zz[1] - lim AND hy + rkm <= zz[1] + lim.
        }
        IF ok AND zoom < 0 { SET zoom TO z. }
    }
    }
    IF zoom = -9 { SET zoom TO CHOOSE 0 IF tdMm = 602 ELSE 1. }
    // the 1 NM page (zoom 3) from TD_HS_TTH_Z3 s to the HAC on, before the HAC (the probe's t_to_hac); the latch holds it
    // after
    IF tg["probe_valid"] AND (tg["iphase"] = TG_IPH_STURN OR tg["iphase"] = TG_IPH_ACQ) AND tg["t_to_hac"] <= TD_HS_TTH_Z3 {
        SET zoom TO 3.
    }
    // LATCHED: never wider than the tightest zoom reached this run, so a zoom-in cannot zoom back out (tdInit resets
    // it)
    SET zoom TO MAX(zoom, tdZoomLatch).
    // a zoom that would leave the vehicle off the page steps out (the latch with it)
    IF tu { SET zoom TO tdTuOut(zoom, tdTuAim(tg["iphase"], hx, hy)). } ELSE { SET zoom TO tdHsOut(zoom, x, y). }
    SET tdZoomLatch TO zoom.
    LOCAL bgh IS TD_DIR + "hsit" + zoom + (CHOOSE "t" IF tu ELSE "") + ".png".
    IF bgh <> tdBgH { SET tdBoxH:STYLE:BG TO bgh. SET tdBgH TO bgh. }
    LOCAL zz IS tdGeo["hs" + zoom + "_km"].
    LOCAL f IS tdGeo["hs_field_px"].
    LOCAL ppk IS f[2] / (2 * zz[2]).        // px per km
    IF tu { tdTuPlace(f[0] + f[2] / 2, f[1] + TD_TU_BY * f[3], ppk). }
    // the page: the lateral y to the right, the runway x UP
    LOCAL px IS f[0] + f[2] / 2 + (y - zz[1]) * ppk.
    LOCAL py IS f[1] + f[3] / 2 - (x - zz[0]) * ppk.
    // a latched zoom can leave the vehicle off the page: tdFits hides its bug there
    LOCAL hdg IS MOD(ROUND(st["psd"] / 5) * 5 + 360, 360).
    LOCAL hbn IS "hsbug_" + (CHOOSE "00" IF hdg < 10 ELSE (CHOOSE "0" IF hdg < 100 ELSE "")) + hdg.
    LOCAL pp IS tdHsPin(hbn, px, py, f).    // past the widest zoom, held at the edge
    IF tu { SET hbn TO "hsbug_000". SET pp TO LIST(tdTuG[4], tdTuG[5]). }   // track up: the nose up, fixed
    IF tdFits(hbn, pp[0], pp[1], f) { tdPut(tdSH["bug"], hbn, pp[0], pp[1]). }   // wholly inside the field
    // the predictors (20, 40 and 60 s ahead, on the measured turn rate)
    LOCAL rate IS tdRate.                   // a redraw (cyc FALSE) keeps the cycle's rate
    IF cyc {
        SET rate TO 0.
        IF tdPrev:HASKEY("t") AND TIME:SECONDS > tdPrev["t"] { SET rate TO taemg_norm180(st["psd"] - tdPrev["psd"]) / (TIME:SECONDS - tdPrev["t"]). }
        SET tdRate TO rate.
    }
    LOCAL vh IS st["vh"].
    LOCAL i IS 1.
    FOR tt IN LIST(20, 40, 60) {
        LOCAL xx IS st["x"]. LOCAL yy IS st["y"]. LOCAL hh IS st["psd"].
        LOCAL dh IS rate * tt / 20.         // the step's turn, once a horizon (the same number)
        FROM { LOCAL n IS 0. } UNTIL n >= 20 STEP { SET n TO n + 1. } DO {
            SET hh TO hh + dh.
            SET xx TO xx + vh * COS(hh) * tt / 20.
            SET yy TO yy + vh * SIN(hh) * tt / 20.
        }
        LOCAL qx IS f[0] + f[2] / 2 + (yy / 1000 - zz[1]) * ppk.
        LOCAL qy IS f[1] + f[3] / 2 - (xx / 1000 - zz[0]) * ppk.
        IF tu { LOCAL qp IS tdTuPg(xx / 1000, yy / 1000). SET qx TO qp[0]. SET qy TO qp[1]. }
        IF tdFits("pred", qx, qy, f) { tdPut(tdSH["p" + i], "pred", qx, qy). }   // wholly inside the field
        SET i TO i + 1.
    }
    IF tg["iphase"] <> 3 {
        LOCAL rt IS rkm * ppk.              // px
        LOCAL rp IS MAX(TD_HAC_RMIN, 2 * ROUND(rt / 2)).
        LOCAL hcn IS "hac_" + (CHOOSE "0" IF rp < 100 ELSE "") + rp.
        LOCAL hcx IS f[0] + f[2] / 2 + (hy - zz[1]) * ppk.
        LOCAL hcy IS f[1] + f[3] / 2 - (hx - zz[0]) * ppk.
        IF tu { LOCAL hp IS tdTuPg(hx, hy). SET hcx TO hp[0]. SET hcy TO hp[1]. }
        // the whole circle when its sprite is wholly inside the field, else the arc that crosses the field in dashes
        IF rp <= TD_HAC_RMAX AND tdFits(hcn, hcx, hcy, f) {
            tdPut(tdSH["hac"], hcn, hcx, hcy).
            SET tdHdKey TO "".
        } ELSE { tdHacArc(hcx, hcy, rt, f). }
    } ELSE { SET tdHdKey TO "". }
    IF tu { tdTuRwy(f, tdTuRlen()). }       // the runway on the turned world
    // the top bar
    LOCAL bar IS tdGeo["hs_bar_px"].        // x0, x1, y, numeral drop, end-label gap
    LOCAL side IS CHOOSE 1 IF tg["ysgn"] > 0 ELSE -1.
    LOCAL fb IS -1.
    IF tg["iphase"] = 1 AND tg["t_to_hac"] > 0 {   // The HAC geometry (the bar) stays under SW 02
        LOCAL rt IS taemg_rturn_of(g["psha"], tg["rf"], tg["r2"]).
        // a redraw counts down from the cycle, at the estimate's own rate
        LOCAL tth IS MAX(0, tdTthNow(tg["t_to_hac"], cyc) - SQRT(TG_P2TRNC1 ^ 2 - 1) * rt / MAX(vh, 1)).
        IF tth <= TD_BAR_SHOW_S {
            LOCAL f0 IS CHOOSE 1 IF side > 0 ELSE 0.
            SET fb TO f0 + (1 - 2 * f0) * MIN(tth, TD_BAR_MOVE_S) / TD_BAR_MOVE_S.
            IF NOT (tth > TD_BAR_MOVE_S AND NOT tdFlash) {
                tdPut(tdSH["bar"], "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]).
            }
            tdText(tdSH["b0"], "0", bar[0] + (bar[1] - bar[0]) * f0, bar[2] - bar[3], 2).
            tdText(tdSH["b1"], "5", bar[0] + (bar[1] - bar[0]) * 0.5, bar[2] - bar[3], 2).
            tdText(tdSH["b2"], "10", bar[0] + (bar[1] - bar[0]) * (1 - f0), bar[2] - bar[3], 2).
        }
    } ELSE IF tg["iphase"] = 2 {
        SET fb TO 0.5 - 0.5 * side * MAX(-1, MIN(1, tg["rerrc"] / (5000 * TD_FT))).
        tdPut(tdSH["bar"], "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]).
        tdText(tdSH["b0"], "5K", bar[0] - bar[4], bar[2], 1).
        tdText(tdSH["b2"], "5K", bar[1] + bar[4], bar[2], 0).
    } ELSE IF tg["iphase"] = 3 {
        SET fb TO 0.5 + 0.5 * MAX(-1, MIN(1, st["y"] / (2500 * TD_FT))).
        tdPut(tdSH["bar"], "bartri", bar[0] + (bar[1] - bar[0]) * fb, bar[2]).
        tdText(tdSH["b0"], "2.5K", bar[0] - bar[4], bar[2], 1).
        tdText(tdSH["b2"], "2.5K", bar[1] + bar[4], bar[2], 0).
    }
    // the glide-slope indicator: the height error (+ = below the reference) over +-hs_gsi_px ft
    LOCAL gs IS tdGeo["hs_gsi_px"].         // x, top y, bottom y, ft
    LOCAL her IS CHOOSE tg["herror"] IF cyc ELSE e[4] - st["h"].   // a redraw's moved on (taemg_comp's href - h)
    LOCAL fg IS 0.5 + 0.5 * MAX(-1, MIN(1, her / (gs[3] * TD_FT))).
    tdPut(tdSH["gsi"], "gsi", gs[0], gs[2] + (gs[1] - gs[2]) * fg).
    LOCAL rd IS tdGeo["hs_readout_px"].
    LOCAL vals IS LIST(ldRwy["name"], (CHOOSE "R " IF side > 0 ELSE "L ") + (CHOOSE "STRT" IF tg["strt"] ELSE "OVHD"),
                       CHOOSE "NEP" IF tg["nep"] ELSE "MEP", "" + ROUND(g["psha"]), "" + ROUND(e[0] / TD_NM, 1),
                       CHOOSE "" + ROUND(g["dpsac"]) IF tg["iphase"] = 1 ELSE "").
    // 3A blanked the guidance's readouts under SW 02 (side / STRT-OVHD, NEP-MEP, the HAC turn, the offset); they are the HAC
    // geometry, not a command: every row stays live
    FROM { LOCAL j IS 0. } UNTIL j >= 6 STEP { SET j TO j + 1. } DO {
        tdText(tdSH["r" + j], vals[j], rd[1], rd[2 + j], 1).
    }
    // the message log (newest at the top, 13 rows): drawn again only when an event was added (tdLog only grows)
    LOCAL nlg IS MIN(13, tdLog:LENGTH).
    IF tdLog:LENGTH <> tdLogDrawn {
        LOCAL lg IS tdGeo["log_px"].        // left x, first row y, row pitch, rows
        FROM { LOCAL j IS 0. } UNTIL j >= nlg STEP { SET j TO j + 1. } DO {
            tdText(tdLogSl[j], tdLog[j], lg[0], lg[1] + j * lg[2], 0).
        }
        SET tdLogDrawn TO tdLog:LENGTH.
    } ELSE {
        FROM { LOCAL j IS 0. } UNTIL j >= nlg STEP { SET j TO j + 1. } DO { tdSlotOn(tdLogSl[j]). }
    }
}

FUNCTION tdClose {
    gpcWinForget("TOP").                    // their X looks forgotten before the windows go
    gpcWinForget("BOT").
    tdDeckClose().                          // a deck that never got its pages (an entry cut short)
    tdChoice(FALSE, "").                    // the crew's choice too, if still up
    IF tdOn {
        dkDetach("td").                     // the deck's place saved
        tdGuiV:HIDE().
        tdGuiH:HIDE().
        SET tdOn TO FALSE.
    }
    SET tdPg TO FALSE.
    SET tdMm TO 603.                        // a later tdInit opens on TAEM's pages
    SET tdRowV TO 0.
    SET tdRowV2 TO 0.
    SET tdRowH TO 0.
    SET tdRowH2 TO 0.
}

// the open pages to major mode mm (603: TAEM's VERT SIT pages from the next tdTick, the MM 602 items blanked, the
// crew's choice gone; the zoom latch, the log and the clock go on: one run)
FUNCTION tdSetMm {
    PARAMETER mm.
    IF NOT tdOn OR mm = tdMm { RETURN. }
    SET tdMm TO mm.
    IF mm = 603 {
        tdChoice(FALSE, "").
        FOR k IN tdGS:KEYS { tdSlotOff(tdGS[k]). }
        SET tdLastPh TO -1.                 // tdTick logs TAEM's first phase
        tdLogEvent("TAEM").
    }
}

// the pages end (A/L: VERT SIT 2's A/L box has flashed) but the windows stay as the button rows (the DAP's, HUD
// CAM) until landRun's end (tdClose)
FUNCTION tdPagesOff {
    IF NOT tdOn OR NOT tdPg { RETURN. }
    SET tdPg TO FALSE.
    tdChoice(FALSE, "").
    tdBoxV:HIDE().
    tdBoxH:HIDE().
    SET tdGuiV:STYLE:HEIGHT TO TD_BAR_WIN_H + TD_ROW_H.     // each window's two rows
    SET tdGuiH:STYLE:HEIGHT TO TD_BAR_WIN_H + TD_ROW_H.
}

// ============================================================================================================
//  THE MM 602 ITEMS -- VERT SIT 1 in MM 602 (DPS Dictionary 3-64 .. 3-66; SCOM 6.3)
// ============================================================================================================
//  The display is close to TAEM's VERT SIT 1, so it is built on it, styled toward the real one: no labels, no clean box.
//  OPS 6's RTLS loop calls tdGrStart() after grtlsStart and tdGrTick(..) one loop pass after each GRTLS guidance cycle;
//  landRun's tdInit then turns the same windows to TAEM's pages (MM 603, tdSetMm).
//  THE PAGES = TAEM's (the generated copy above) on grtls_bg/vsit1_602.png / vsit2_602.png (taem_bg's VERT SIT pages +
//  the upper-left corner's two lines, no frame or labels: gen_grtls_bg.py), and:
//   [10] the alpha / Mach corner: the orbiter symbol at (Mach, alpha); dashed = the nominal profile (GRALPR wings level),
//        solid = the q-bar limit (the alpha whose lift holds TG_QBRUL); the symbol flashes below the q-bar limit
//        (A DEVIATION: the orbiter's flashes outside I-loaded alpha limits, whose values are not published);
//   (12) "NZ" overbright (the energy ticks' pale green: no white text) right of the NZ value in the constant-Nz phase
//        (5); the value itself at the readouts' normal intensity;
//   (13) TGT NZ = the pullout Nz GRNZC1 + DGRNZ + 1 g (total), from its computation (the sink's turn, phase 6) on;
//   (14) BAILOUT, (15) ECAL/BDA: slots for the contingency entries, blank in an RTLS;
//   the status row and the log: ALPHA REC / NZ HOLD / ALPHA TRAN (phases 6 / 5 / 4) in TAEM's phase field.
//  BEFORE PHASE 4 (the DPS Dictionary: guidance computes no energy state "until alpha transition begins ... these
//  indicators will appear off-scale low and the energy triangle will flash"): the E/W triangle off-scale low, flashing;
//  the H-vs-range symbol when on its panel (the range via the HAC from TAEM's pure taemg_gtp on the display's own HAC
//  turn, the side as lib_grtls's phase 4 takes it; GR untouched); the readouts; HORIZ SIT at its widest zoom: the
//  symbol, RWY, RANGE, the log.
//  TAEM's page from the first guidance cycle (lib_grtls grtlsTgPre: GR["tg"] from the boot, GR["tgon"]), so the whole
//  display and the OTT buttons are usable from the start; the "BEFORE PHASE 4" drawing above stays for CONT BLUE, the
//  split-S's phases 8 / 5 and the bailout (phase 7).
//  FROM PHASE 4: tdTick on a COPY of lib_grtls's TAEM state plus what its phase 4 does not compute (lib_grtls runs
//  taemg_gtp + taemg_comp, not taemg_cycle): "g" its gtp result, "nz_total" the pullout Nz, "nz_meas" the model's Nz,
//  "dsbc" the speedbrake set, "ph_word" ALPHA TRAN (tdMsgRow).
//  NZ = the model's Nz at the measured alpha (what the hold flies; A DEVIATION: the orbiter's is the accelerometers').
//  The items' slots come FIRST in the VERT SIT box and are never hidden (blanked): a hidden slot drops out of kOS's flow
//  and would move every later slot (TAEM's) up a pixel.

GLOBAL TD_GR_DIR IS "grtls_bg/".
GLOBAL TD_BLANK_IMG IS TD_GR_DIR + "grblank.png".   // tdVis: a label showing it is hidden
GLOBAL TD_GR_ARCH IS "0:/grtls_bg/".
GLOBAL TD_GR_BRIGHT IS RGB(0.769, 1, 0.769).  // "overbright" = #c4ffc4, the TAEM pages' overbright NOM ticks (no white text)
GLOBAL tdGr IS LEXICON().                   // grtls_bg.txt: the corner's box and its two lines
GLOBAL tdGS IS LEXICON().                   // the MM 602 slots (first in the VERT SIT box)
GLOBAL tdGrPh IS -1.                        // the GRTLS phase last logged
GLOBAL tdGrPsha IS 0.                       // the display's own HAC turn before phase 4
GLOBAL tdSbA IS -1.                         // VERT SIT's SPD BK, the speedbrake as flown (deg): TAEM's DAP slews it
                                            //   (2 x lib_dap's dSbBase); -1 = the command (the GRTLS writes it at once)
GLOBAL tdSbCap IS 1000.                     // VERT SIT's CMD row: the command AFTER the DAP's supersonic cap (deg, 2 x lib_dap's
GLOBAL tdSbCapM IS 1.5.                     //   SB_SUPER_MAX above Mach SB_SUPER_MACH), so SPD BK and CMD agree; tdTick copies them

FUNCTION tdGrLoad {                         // reads grtls_bg.txt; registers the blank sprite
    IF NOT EXISTS(TD_GR_ARCH + "grtls_bg.txt") { RETURN FALSE. }
    SET tdGr TO LEXICON().
    FOR l0 IN OPEN(TD_GR_ARCH + "grtls_bg.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        IF lin <> "" AND NOT lin:STARTSWITH("#") { SET tdGr[lin:SPLIT(" ")[0]] TO tdNums(lin). }
    }
    SET tdSpr["grblank"] TO LIST(TD_GR_DIR + "grblank.png", 4, 4, 0, 0).
    IF NOT (tdGr:HASKEY("am_box_px") AND tdGr:HASKEY("am_mach") AND tdGr:HASKEY("am_alpha")) { RETURN FALSE. }
    RETURN tdGr:HASKEY("am_nom") AND tdGr:HASKEY("am_qlim").
}

FUNCTION tdGrSlots {                        // inside tdInit, before TAEM's slots: the items' slots, shown blank
    SET tdGS TO LEXICON().
    SET tdGS["am"] TO tdImgSlot("V").
    SET tdGS["nzv"] TO tdTxtSlot("V", 11, TD_GR_BRIGHT).
    SET tdGS["nzi"] TO tdTxtSlot("V", 11, TD_GR_BRIGHT).
    SET tdGS["bail"] TO tdTxtSlot("V", 13, RGB(0.235, 0.878, 0.235)).
    SET tdGS["ecal"] TO tdTxtSlot("V", 11, RGB(0.235, 0.878, 0.235)).
    LOCAL rv IS tdGS["nzv"].                // value rows, as TAEM's r0 .. r6
    SET rv[10] TO TD_VS_ROW_DY.
    LOCAL ri IS tdGS["nzi"].
    SET ri[10] TO TD_VS_ROW_DY.
    LOCAL rbl IS tdGS["bail"].              // CONT's BAILOUT and ECAL/BDA on readout rows, as the rows
    SET rbl[10] TO TD_VS_ROW_DY.
    LOCAL rel IS tdGS["ecal"].
    SET rel[10] TO TD_VS_ROW_DY.
    tdPut(tdGS["am"], "grblank", 0, 0).
    FOR k IN LIST("nzv", "nzi", "bail", "ecal") { tdText(tdGS[k], " ", 0, 0, 0). }
}

FUNCTION tdGrLine {                         // the alpha (deg) on a sampled line ("am_nom" / "am_qlim") at Mach m
    PARAMETER key, m.
    LOCAL p IS tdGr[key].
    LOCAL n IS FLOOR(p:LENGTH / 2).
    IF m <= p[0] { RETURN p[1]. }
    IF m >= p[2 * n - 2] { RETURN p[2 * n - 1]. }
    LOCAL i IS 1.
    UNTIL i >= n - 1 OR p[2 * i] >= m { SET i TO i + 1. }
    LOCAL m0 IS p[2 * i - 2].
    LOCAL a0 IS p[2 * i - 1].
    RETURN a0 + (p[2 * i + 1] - a0) * (m - m0) / MAX(p[2 * i] - m0, 0.000001).
}

FUNCTION tdGrAmPx {                         // (Mach, alpha) -> the corner's page px, held inside its box
    PARAMETER m, a.
    LOCAL b IS tdGr["am_box_px"].
    LOCAL sm IS tdGr["am_mach"].
    LOCAL sa IS tdGr["am_alpha"].
    LOCAL fx IS MAX(0, MIN(1, (m - sm[0]) / (sm[1] - sm[0]))).
    LOCAL fy IS MAX(0, MIN(1, (a - sa[0]) / (sa[1] - sa[0]))).
    LOCAL sp IS tdSpr["vsbug_p00"].         // held with its bug wholly inside the box
    RETURN LIST(MAX(b[0] + sp[3] + TD_FIT_IN, MIN(b[0] + b[2] - sp[1] + sp[3] - TD_FIT_IN, b[0] + b[2] * fx)),
                MAX(b[1] + sp[4] + TD_FIT_IN, MIN(b[1] + b[3] - sp[2] + sp[4] - TD_FIT_IN, b[1] + b[3] * (1 - fy)))).
}

FUNCTION tdGrPhw {                          // the GRTLS phase's word
    PARAMETER ph.
    IF ph = 6 { RETURN "ALPHA REC". }
    IF ph = 5 { RETURN "NZ HOLD". }
    IF ph = 7 { RETURN "BAILOUT". }      // CONT BLUE's hold
    IF ph = 8 { RETURN "SPLIT-S". }      // the split-S's heads-down pull
    RETURN "ALPHA TRAN".
}

// the GRTLS pages' TRIM row (where TAEM's shows QBREF, empty in the GRTLS): the pitch trim as ENTRY TRAJ shows it
// (traj_display tjTrim: the body flap U nose up / D nose down, then "+" and the elevons' share when they carry any), to
// one decimal: this value column is narrower (an over-long text drops the elevons' decimal). lib_vehicle's PTRIM_ANG /
// ETRIM_ANG; "" before they exist.
FUNCTION tdTrimTxt {
    IF NOT (DEFINED PTRIM_ANG) { RETURN "". }
    LOCAL t IS (CHOOSE "U" IF PTRIM_ANG <= 0 ELSE "D") + ROUND(ABS(PTRIM_ANG), 1).
    IF (DEFINED ETRIM_ANG) AND ABS(ETRIM_ANG) > 0.05 {
        LOCAL es IS "+" + ROUND(ABS(ETRIM_ANG), 1).
        IF t:LENGTH + es:LENGTH > 8 { SET es TO "+" + ROUND(ABS(ETRIM_ANG)). }
        SET t TO t + es.
    }
    RETURN t.
}

FUNCTION tdGrTgtNz {                        // (13) the pullout Nz (g total) once computed, else ""
    PARAMETER gr.
    IF SS_ON { RETURN "" + ROUND(SS_NZ, 2). }   // the split-S: its Nz, phases 8 and 5
    IF gr["iphase"] = 6 AND gr["dgrnzt"] <= 0 { RETURN "". }
    RETURN "" + ROUND(GR_GRNZC1 + gr["dgrnz"] + 1.0, 2).
}

FUNCTION tdGrStart {                        // OPS 6's RTLS: the pages up (FALSE: a file missing -> no pages)
    IF tdOn { tdClose(). }                  // a fresh pair on MM 602
    SET tdMm TO 602.
    SET tdGrPh TO -1.
    SET tdGrPsha TO 0.
    RETURN tdInit().
}

FUNCTION tdGrTick {                         // one loop pass after each GRTLS guidance cycle (cyc TRUE); between the
    PARAMETER gr, st, sn, am, sbSet, cyc IS TRUE.   // cycles every TD_DT_CS s while tdFast (cyc FALSE). lib_grtls's GR,
    IF NOT tdOn OR NOT tdPg { RETURN. }     //   TAEM's state (ldState), grtlsSense at the measured alpha am (deg), the
    IF tdGpcGate(cyc) { RETURN. }           //   A window whose GPC failed is not drawn, the GRTLS pages too (the BFS's one display)
    SET tdFlashClk TO tdFast() AND TD_DT_CS > 0. SET tdRtT TO uiRt().   //   speedbrake set (deg). The flash on
                                            //   the grid; the grid in real time
    IF tdCsOn AND TD_CS {                   //   C# draws (TD_CS)
        IF tdCsDraw(1, gr, st, cyc, sn, am, sbSet) { RETURN. }
    }
    tdGrTickK(gr, st, sn, am, sbSet, cyc).
}

FUNCTION tdGrTickK {                        // tdGrTick's kOS drawing
    PARAMETER gr, st, sn, am, sbSet, cyc.
    IF NOT tdOn OR NOT tdPg { RETURN. }
    SET tdSbA TO -1.                        // the GRTLS: the brake as written (sbSet)
    LOCAL ph IS gr["iphase"].
    LOCAL phw IS tdGrPhw(ph).
    IF ph <> tdGrPh { tdLogEvent(phw). SET tdGrPh TO ph. }
    IF gr["tgon"] = 1 AND gr["cont"] <> 2 AND (ph = 4 OR ph = 5 OR ph = 6) {   // from the boot (CONT BLUE: no
        LOCAL tgd IS gr["tg"]:COPY.         //   TAEM page: tdGrPre's); the display's copy: what lib_grtls does not compute
        SET tgd["g"] TO gr["gpd"].
        SET tgd["nz_total"] TO GR_GRNZC1 + gr["dgrnz"] + 1.0.
        SET tgd["nz_meas"] TO sn["nz"].
        SET tgd["dsbc"] TO sbSet.
        SET tgd["ph_word"] TO phw.
        SET tdLastPh TO tgd["iphase"].      // tdTick logs no TAEM phase word (the GRTLS one is logged above)
        tdTickK(tgd, st, cyc).
    } ELSE {
        tdGrPre(gr, st, sn, sbSet, phw, cyc).
    }
    IF NOT gpcLive("TOP") { RETURN. }       // The alpha bug, the NZ readout, BAILOUT / ECAL are VERT SIT's: its GPC is out
    LOCAL p IS tdGrAmPx(sn["mach"], am).
    IF am < tdGrLine("am_qlim", sn["mach"]) AND NOT tdFlash {
        tdPut(tdGS["am"], "grblank", p[0], p[1]).
    } ELSE {
        tdPut(tdGS["am"], "vsbug_p00", p[0], p[1]).
    }
    LOCAL rd IS tdGeo["vs_readout_px"].     // label x, value right x, the 7 rows (NZ = rd[4])
    tdText(tdGS["nzv"], " ", rd[1], rd[4], 1).      // the value: TAEM's readout (tdTickK / tdGrPre), normal intensity
    tdText(tdGS["nzi"], CHOOSE "NZ" IF (ph = 5 OR ph = 8) ELSE " ", rd[1] + 10, rd[4], 0).
    IF gr["cont"] <> 0 {                    // CONT: (14) BAILOUT in the hold, (15) ECAL/BDA ENA (GREEN) /
        LOCAL rb IS rd[8] + rd[4] - rd[3].  //   INH (BLUE), under the readouts (the DPS Dictionary's MM 602 items):
        //   the next readout pair's two rows (not 7 and 14 px under MACH's row, which lands on its text)
        tdText(tdGS["bail"], CHOOSE "BAILOUT" IF ph = 7 ELSE " ", rd[0], rb, 0).
        tdText(tdGS["ecal"], CHOOSE "ECAL/BDA ENA" IF gr["cont"] = 1 ELSE "ECAL/BDA INH", rd[0], rb + rd[3] - rd[2], 0).
    }
}

// THE CREW'S CHOICE: two buttons, GRTLS and BLUE, with the countdown, in the GRTLS page's window, shown only when the
// reach test calls an RTLS short: ops6q shows it and reads TD_PICK; at its end (a pick, or 30 s: BLUE) it takes it down.
GLOBAL TD_PICK IS "".                       // "" no pick, "GRTLS", "BLUE" (the buttons' ONCLICK)
GLOBAL tdCh IS LEXICON().                   // the choice's widgets (empty: not shown)

FUNCTION tdChoice {                         // on: shown with the text txt (the countdown; a second call sets the text);
    PARAMETER shown, txt.                   //   off: gone. In VERT SIT's title row; without the pages a window of its own
    IF NOT shown {                          //   at VERT SIT's place
        IF tdCh:LENGTH > 0 {
            tdCh["bg"]:DISPOSE().
            tdCh["bb"]:DISPOSE().
            tdCh["lb"]:DISPOSE().
            IF tdCh["own"] { tdCh["win"]:DISPOSE(). }
            SET tdCh TO LEXICON().
        }
        RETURN.
    }
    IF tdCh:LENGTH > 0 {
        SET tdCh["lb"]:TEXT TO txt.
        RETURN.
    }
    LOCAL own IS NOT tdOn.
    LOCAL win IS 0.
    LOCAL row IS 0.
    IF own {
        SET win TO GUI(320).
        uiDispSkin(win).                    // the panel look
        SET win:X TO TD_VS_X0.
        SET win:Y TO TD_VS_Y0.
        SET row TO win:ADDHLAYOUT().
    } ELSE {
        SET row TO tdGuiV:WIDGETS[0].       // tdWin's title row
    }
    LOCAL lb IS row:ADDLABEL(txt).
    uiDispLabel(lb).                        // the panel font (the colour stays the alert's)
    SET lb:STYLE:TEXTCOLOR TO RGB(1, 0.16, 0.16).   // the alert colour
    LOCAL bg IS row:ADDBUTTON("GRTLS").
    LOCAL bb IS row:ADDBUTTON("BLUE").
    FOR bt IN LIST(bg, bb) {                // a title row's height (the page's box below keeps its place)
        SET bt:STYLE:HEIGHT TO 18.
        SET bt:STYLE:MARGIN:V TO 0.
        SET bt:STYLE:PADDING:V TO 0.
    }
    SET bg:ONCLICK TO { SET TD_PICK TO "GRTLS". }.
    SET bb:ONCLICK TO { SET TD_PICK TO "BLUE". }.
    SET tdCh TO LEXICON("lb", lb, "bg", bg, "bb", bb, "own", own, "win", win).
    IF own { win:SHOW(). }
}

// a CONT BLUE (gr["cont"] 2) draws nothing referenced to the runway: VERT SIT's H-vs-range symbol and E/W triangle (its
// panel fixed at 1), HORIZ SIT's RWY and RANGE, the runway and its centreline (the field on grtls_bg/hsit1_blue.png), the
// orbiter symbol at the field's centre for its heading only. The readouts, the alpha / Mach corner, NZ, BAILOUT,
// ECAL/BDA, the log and the clock as usual.
GLOBAL TD_GR_HS_BLUE IS "hsit1_blue.png".   // in TD_GR_DIR
FUNCTION tdGrPre {                          // phases 6 / 5: both pages without TAEM guidance (tdTick's structure)
    PARAMETER gr, st, sn, sbSet, phw, cyc.
    tdFlashStep(cyc).                       // the flash
    SET tdCyc TO tdCyc + 1.
    LOCAL isBlue IS gr["cont"] = 2.
    LOCAL lvT IS gpcLive("TOP").            // Only the windows whose GPC lives (VERT SIT = TOP, HORIZ SIT = BOT)
    LOCAL lvB IS gpcLive("BOT").
    // VERT SIT: the range via the HAC as lib_grtls's phase 4 will take it (the display's own HAC turn); none in a BLUE
    LOCAL d IS 0.
    LOCAL k IS 1.
    IF NOT isBlue {
        LOCAL same IS CHOOSE 1 IF st["y"] >= 0 ELSE -1.
        LOCAL gp IS taemg_gtp(st, CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same, TG_IPH_ACQ, TG_RFMX, tdGrPsha, TRUE, TG_R2).
        SET tdGrPsha TO gp["psha"].
        SET d TO taemg_drpred_of(gp["rpred"]).
        SET k TO CHOOSE 2 IF d / 1000 < tdGeo["vs_switch_km"][0] ELSE 1.
    }
    IF lvT {
    LOCAL bgv IS TD_GR_DIR + "vsit" + k + "_602.png".
    IF bgv <> tdBgV { SET tdBoxV:STYLE:BG TO bgv. SET tdBgV TO bgv. }
    LOCAL a IS tdGeo["vs" + k + "_km"].
    LOCAL dk IS d / 1000.
    LOCAL hk IS st["h"] / 1000.
    IF NOT isBlue AND dk >= a[0] AND dk <= a[1] AND hk >= a[2] AND hk <= a[3] {
        LOCAL gi IS MAX(-40, MIN(14, 2 * ROUND(ARCTAN2(st["hdot"], MAX(st["surfv"], 1)) / 2))).
        LOCAL bp IS tdKmPx(k, dk, hk).
        LOCAL bn IS "vsbug_" + (CHOOSE "m" IF gi < 0 ELSE "p") + (CHOOSE "0" IF ABS(gi) < 10 ELSE "") + ABS(gi).
        IF tdVsShow(bn, bp[0], bp[1]) { tdPut(tdSV["bug"], bn, bp[0], bp[1]). }   // left of the labels only
    }
    IF tdFlash AND NOT isBlue { tdPut(tdSV["ewtri"], "ewtri", tdGeo["vs_strip_px"][0], tdEwY(-1E9)). }   // off-scale low, flashing
    LOCAL rd IS tdGeo["vs_readout_px"].
    LOCAL nzs IS "" + ROUND(sn["nz"], 2).
    LOCAL vals IS LIST("" + ROUND(TD_SB_PCT * sbSet), "" + ROUND(TD_SB_PCT * sbSet), nzs, tdGrTgtNz(gr), "" + ROUND(st["qbar"] / TD_PSF), tdTrimTxt(),
                       "" + ROUND(st["mach"], 2)).
    FROM { LOCAL i IS 0. } UNTIL i >= 7 STEP { SET i TO i + 1. } DO { tdText(tdSV["r" + i], vals[i], rd[1], rd[2 + i], 1). }
    tdText(tdSV["trml"], "TRIM", rd[0], rd[7], 0).   // TRIM where QREF was (empty in GRTLS)
    }
    // HORIZ SIT: zoom 1 or wider, the symbol on it, the runway, the range, the log (a BLUE: no runway, no RWY / RANGE,
    // the symbol at the centre). The RTLS boots 124-140 km out, past zoom 1: the tightest zoom from 1 out that holds the
    // vehicle (tdHsOut; the latch is TAEM's), and past the widest the symbol held at the edge
    IF lvB {
    LOCAL x IS 0.
    LOCAL y IS 0.
    LOCAL zm IS 1.
    LOCAL tu IS TD_TRKUP AND NOT isBlue.    // the runway on the turned world (a BLUE has none: the bug upright)
    IF NOT isBlue {
        SET x TO st["x"] / 1000.
        SET y TO st["y"] / 1000.
        IF tu { tdTuHead(x, y, st["psd"]). SET zm TO tdTuOut(1, tdTuRel(0, 0)). } ELSE { SET zm TO tdHsOut(1, x, y). }
    }
    LOCAL bgh IS CHOOSE TD_GR_DIR + TD_GR_HS_BLUE IF isBlue ELSE TD_DIR + "hsit" + zm + (CHOOSE "t" IF tu ELSE "") + ".png".
    IF bgh <> tdBgH { SET tdBoxH:STYLE:BG TO bgh. SET tdBgH TO bgh. }
    LOCAL zz IS tdGeo["hs" + zm + "_km"].
    LOCAL f IS tdGeo["hs_field_px"].
    LOCAL ppk IS f[2] / (2 * zz[2]).
    IF isBlue { SET x TO zz[0]. SET y TO zz[1]. }
    LOCAL hdg IS MOD(ROUND(st["psd"] / 5) * 5 + 360, 360).
    LOCAL hbn IS "hsbug_" + (CHOOSE "00" IF hdg < 10 ELSE (CHOOSE "0" IF hdg < 100 ELSE "")) + hdg.
    LOCAL hbp IS tdHsPin(hbn, f[0] + f[2] / 2 + (y - zz[1]) * ppk, f[1] + f[3] / 2 - (x - zz[0]) * ppk, f).
    IF TD_TRKUP {                           // track up: the nose up, fixed (a BLUE: at the field's centre)
        SET hbn TO "hsbug_000".
        IF tu { tdTuPlace(f[0] + f[2] / 2, f[1] + TD_TU_BY * f[3], ppk). SET hbp TO LIST(tdTuG[4], tdTuG[5]). }
        ELSE { SET hbp TO LIST(f[0] + f[2] / 2, f[1] + f[3] / 2). }
    }
    IF tdFits(hbn, hbp[0], hbp[1], f) { tdPut(tdSH["bug"], hbn, hbp[0], hbp[1]). }   // wholly inside the field
    IF tu { tdTuRwy(f, tdTuRlen()). }
    LOCAL rh IS tdGeo["hs_readout_px"].     // RWY / HAC / EP / HAC TURN / RANGE / HDG ERR
    IF NOT isBlue {
        tdText(tdSH["r0"], ldRwy["name"], rh[1], rh[2], 1).
        tdText(tdSH["r4"], "" + ROUND(d / TD_NM, 1), rh[1], rh[6], 1).
    }
    LOCAL nlg IS MIN(13, tdLog:LENGTH).
    IF tdLog:LENGTH <> tdLogDrawn {
        LOCAL lg IS tdGeo["log_px"].        // left x, first row y, row pitch, rows
        FROM { LOCAL j IS 0. } UNTIL j >= nlg STEP { SET j TO j + 1. } DO {
            tdText(tdLogSl[j], tdLog[j], lg[0], lg[1] + j * lg[2], 0).
        }
        SET tdLogDrawn TO tdLog:LENGTH.
    } ELSE {
        FROM { LOCAL j IS 0. } UNTIL j >= nlg STEP { SET j TO j + 1. } DO { tdSlotOn(tdLogSl[j]). }
    }
    }
    // the status rows: the phase word and the clock (tdMsgRow's places)
    LOCAL mr IS tdGeo["msg_row_px"].
    LOCAL ck IS tdGeo["clock_px"].
    LOCAL clk IS tdClock().
    FOR sv IN LIST(tdSV, tdSH) {
        IF (sv = tdSV AND lvT) OR (sv = tdSH AND lvB) {
            tdText(sv["ph"], phw, mr[0], mr[3], 0).
            tdText(sv["met"], clk, ck[0], ck[1], 1).
        }
    }
    IF lvT AND lvB { tdSweep(). } ELSE { tdSweepW(lvT, lvB). }
    IF cyc { SET tdPrev TO LEXICON("psd", st["psd"], "t", TIME:SECONDS). }   // a cycle's draw
}

// ---- the C# pages (see the globals' note at the top)
FUNCTION tdCsOff {                          // any failure: kOS draws from now on, for the flight
    PARAMETER why.
    SET TD_CS_ERR TO why.
    SET TD_CS_STATE TO "kOS (" + why + ")".
    SET tdCsOn TO FALSE.
    SET TD_CS TO FALSE.
}

FUNCTION tdCsSetup {                        // tdInit's end: the slots and tables to the addon
    SET tdCsOn TO FALSE.
    IF NOT TD_CS {
        IF TD_CS_ERR = "" { SET TD_CS_STATE TO "kOS (TD_CS off)". }
        RETURN.
    }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("TDDRAW") { SET why TO "the KAL/S addon has no TAEM pages (an older DLL)". }
    ELSE {
        LOCAL er IS ADDONS:KALS:TDSETUP().
        IF er <> "" { SET why TO "TDSETUP: " + er. }
    }
    IF why <> "" {
        tdCsOff(why).
        RETURN.
    }
    SET tdCsOn TO TRUE.
    SET tdGpcCs TO ADDONS:KALS:HASSUFFIX("TDGPC").   // The DLL draws only the live windows
    SET TD_CS_STATE TO "C#".
}

// TRUE while the C# draws the pages: the hosts (lib_land's TAEM loop, ops6q's GRTLS loop) then redraw them every
// TD_DT_CS s between the guidance cycles (cyc FALSE); FALSE: one draw per cycle
FUNCTION tdFast {
    RETURN tdOn AND tdPg AND tdCsOn AND TD_CS.
}

// One draw's reads for TDDRAW (Td.cs reads them by index): kind (0 tdTick, 1 tdGrTick), TIME:SECONDS, cyc, lib_land's
// ldDmShow (defined, value), ldRwy's name (has, value: [20]), the GRTLS's sn Nz / Mach, am, sbSet, lib_vehicle's trims
// (defined, value), lib_grtls's SS_ON, SS_NZ, GR_GRNZC1, and tdGrPre's taemg_gtp (has, psha, rpred) on the display's own
// HAC turn tdGrPsha (C# sets tdGrPsha from it, as tdGrPre: only when the whole draw succeeded)
FUNCTION tdCsIn {
    PARAMETER kind, a, st, cyc, sn, am, sbSet.
    LOCAL inp IS LIST(kind, TIME:SECONDS, cyc).
    IF DEFINED ldDmShow { inp:ADD(TRUE). inp:ADD(ldDmShow). } ELSE { inp:ADD(FALSE). inp:ADD(""). }
    LOCAL rn IS "".
    IF DEFINED ldRwy { IF ldRwy:HASKEY("name") { SET rn TO ldRwy["name"]. } }
    inp:ADD(rn <> "").
    IF kind = 1 { inp:ADD(sn["nz"]). inp:ADD(sn["mach"]). inp:ADD(am). inp:ADD(sbSet). }
    ELSE { inp:ADD(0). inp:ADD(0). inp:ADD(0). inp:ADD(tdSbA). }
    IF DEFINED PTRIM_ANG { inp:ADD(TRUE). inp:ADD(PTRIM_ANG). } ELSE { inp:ADD(FALSE). inp:ADD(0). }
    IF DEFINED ETRIM_ANG { inp:ADD(TRUE). inp:ADD(ETRIM_ANG). } ELSE { inp:ADD(FALSE). inp:ADD(0). }
    IF kind = 1 {
        inp:ADD(SS_ON). inp:ADD(SS_NZ). inp:ADD(GR_GRNZC1).
        IF a["cont"] <> 2 AND NOT (a["iphase"] = 4 AND a["ysgn"] <> 0) {   // tdGrPre's range (not in a BLUE)
            LOCAL same IS CHOOSE 1 IF st["y"] >= 0 ELSE -1.
            LOCAL gp IS taemg_gtp(st, CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same, TG_IPH_ACQ, TG_RFMX, tdGrPsha, TRUE, TG_R2).
            inp:ADD(TRUE). inp:ADD(gp["psha"]). inp:ADD(gp["rpred"]).
        } ELSE { inp:ADD(FALSE). inp:ADD(0). inp:ADD(0). }
    } ELSE { inp:ADD(FALSE). inp:ADD(0). inp:ADD(0). inp:ADD(FALSE). inp:ADD(0). inp:ADD(0). }
    inp:ADD(rn).
    inp:ADD(tdTuRlen()).                    // [21] the runway's length (m), the track-up strip
    LOCAL gdl IS FALSE.                     // [22]SW 02 GUIDANCE LOST for the phase flown (tdTickK's rule; tdGdLost is set only on the kOS draw): the C# draw blanks the same things
    IF DEFINED FLFX_SWPROG { IF DEFINED FLFX_PH { SET gdl TO flfxSwGuid(FLFX_PH). } }
    inp:ADD(gdl).
    inp:ADD(gpcLive("TOP")).                // [23]VERT SIT's window lives (a frozen / dead one is not drawn: its slots stay as they are)
    inp:ADD(gpcLive("BOT")).                // [24] HORIZ SIT's
    RETURN inp.
}

FUNCTION tdCsDraw {                         // TRUE: C# drew this draw; FALSE: kOS draws it (a failure)
    PARAMETER kind, a, st, cyc, sn, am, sbSet.
    LOCAL inp IS tdCsIn(kind, a, st, cyc, sn, am, sbSet).
    LOCAL ops IS ADDONS:KALS:TDDRAW(a, st, inp).
    IF ops:ISTYPE("String") {               // nothing was written: kOS draws this draw
        tdCsOff("TDDRAW: " + ops).
        RETURN FALSE.
    }
    tdCsApply(ops).
    RETURN TRUE.
}

FUNCTION tdCsApply {                        // TDDRAW's widget writes, in order: widget, code, value
    PARAMETER o.
    FROM { LOCAL i IS 0. } UNTIL i >= o:LENGTH STEP { SET i TO i + 3. } DO {
        LOCAL w IS o[i].
        LOCAL c IS o[i + 1].
        LOCAL x IS o[i + 2].
        IF c = 4 { SET w:STYLE:MARGIN:H TO x. }
        ELSE IF c = 5 { SET w:STYLE:MARGIN:V TO x. }
        ELSE IF c = 0 { SET w:TEXT TO x. tdVis(w, 0, x). }
        ELSE IF c = 1 { SET w:IMAGE TO x. tdVis(w, 1, x). }
        ELSE IF c = 2 { SET w:STYLE:WIDTH TO x. }
        ELSE IF c = 3 { SET w:STYLE:HEIGHT TO x. }
        ELSE IF c = 6 { SET w:STYLE:ALIGN TO x. }
        ELSE { SET w:STYLE:BG TO x. }
    }
    tdNbTrim().
}

// ---- the painter (see TD_PAINT at the top)
FUNCTION tdPaintPh {                        // the placeholder: the page box's LAST child, a 1 x 1 box + an empty 1 x 1 label
    PARAMETER w.                            //   (shown: its draw is where C# paints the page, after every slot box)
    LOCAL bx IS tdBoxOf(w):ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 1. SET m:STYLE:HEIGHT TO 1.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:MARGIN:H TO 0. SET m:STYLE:MARGIN:V TO 0.
    LOCAL fl IS tdCnt[w].
    SET tdCnt[w] TO fl + 1.
    RETURN LIST(m, fl, tdBoxOf(w)).
}

FUNCTION tdPaintSetup {                     // tdInit's end (after the bug group: nothing follows the placeholders)
    SET tdPaintOn TO FALSE.
    SET tdPaintReg TO FALSE.
    IF TD_PAINT = 0 { SET TD_PAINT_STATE TO "OFF". RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        FOR w IN LIST("V", "H") {
            IF why = "" {
                LOCAL er IS ADDONS:KALS:PAINTREG("TD_" + w, tdPaintPh(w), tdOrd[w]).
                IF er = "" { SET er TO ADDONS:KALS:PAINTMODE("TD_" + w, TD_PAINT). }
                IF er <> "" { SET why TO "TD_" + w + ": " + er. }
            }
        }
    }
    IF why <> "" { tdPaintOff(why). RETURN. }
    SET tdPaintReg TO TRUE.
    SET tdPaintOn TO TD_PAINT >= 2.
    SET TD_PAINT_STATE TO CHOOSE "CHECK" IF TD_PAINT = 1 ELSE CHOOSE "PAINT" IF TD_PAINT = 2 ELSE "AB".
}

// the mode switched live (the test harness's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a TD_PAINT > 0 tdInit
FUNCTION tdPaintSet {
    PARAMETER m.
    IF NOT tdPaintReg { RETURN "not registered (TD_PAINT was 0 at tdInit, or it failed: " + TD_PAINT_STATE + ")". }
    LOCAL er IS ADDONS:KALS:PAINTMODE("TD_V", m).
    IF er = "" { SET er TO ADDONS:KALS:PAINTMODE("TD_H", m). }
    IF er <> "" { tdPaintOff(er). RETURN er. }
    SET TD_PAINT TO m.
    SET tdPaintOn TO m >= 2.
    IF m < 2 { FOR nb IN tdNb { SET nb[2] TO nb[1]:LENGTH. } }   // C# showed every box again
    SET TD_PAINT_STATE TO CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
    RETURN "".
}

FUNCTION tdPaintOff {                       // any failure: kOS draws from now on (the boxes shown again by C# or never hidden)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") {
        ADDONS:KALS:PAINTMODE("TD_V", 0). ADDONS:KALS:PAINTMODE("TD_H", 0).
    } }
    SET TD_PAINT_STATE TO "OFF (" + why + ")".
    SET tdPaintOn TO FALSE.
    SET tdPaintReg TO FALSE.
    FOR nb IN tdNb { SET nb[2] TO nb[1]:LENGTH. }   // every box shown: tdNbTrim starts from all
}

FUNCTION tdPaintGone {                      // FALSE: C# still paints; TRUE: it failed (it showed the boxes): kOS draws again
    IF ADDONS:KALS:PAINTSTATE("TD_H") >= 0 AND ADDONS:KALS:PAINTSTATE("TD_V") >= 0 { RETURN FALSE. }
    tdPaintOff("C#: " + ADDONS:KALS:PAINTERR).
    RETURN TRUE.
}
