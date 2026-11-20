// lib_entdisp.ks -- THE ENTRY PAGE: HORIZ SIT in entry, the display deck's bottom window from EI to TAEM
// The page: the map heading-up (up = the ground track), the vehicle fixed 18 % up from the bottom, the zoom the
// tightest of 2000 / 1000 / 500 / 250 / 100 NM (entry_bg.txt's zooms) that holds the site within 85 %; the rings about
// the site (half and the whole step, and the TAEM interface's 33.1 NM), each ring in arc pieces shown only when wholly
// inside the field (kOS draws no clip); the azimuth deadband's two lines off the vehicle at +-DB from the track,
// overbright while |DELAZ| > DB (the reversal) and flashing with ENTRY TRAJ's bug (edLit); the target's runway bar with
// its landing chevron, the HAC centre at the 250 / 100 NM steps, the nearest alternates; five predictor circles on the
// ground track the current bank flies (a log spiral: the bank, L/D and drag held, analytic); the left block (RWY, HAC,
// RANGE, XRNG, DELAZ, TRK), the ADI's ATT / GUID rows (every angle with its side's letter: L / R roll and yaw, U / D
// pitch, edLR) and the RATE / ERROR bars on the right. A deviation: the real SPEC 50 is heading-up with no deadband
// lines and no ADI bars.
// Files: entry_bg/ (written by the offline generator): hsit_e.png, sprites/ at their shown size (the slots have no
// label padding: 1:1), sprites.txt, entry_bg.txt. The hosts (ops3q, ops6q's TAL / AOA): edDeckUp() after trajShow (the
// page in the deck's bottom window; without the files the row alone, tdDeckBarH), edTick(daz, db, rgo m) with each
// trajUpdate. lib_taemdisp's tdInit hides the page when VERT SIT / HORIZ SIT take the windows.
// The slots (lib_ascdisp's way): every widget made once, a slot never hidden (blanked: a hidden label leaves kOS's
// flow), each placed by its margins from the box's top-left less its flow offset. ~150 slots would push the flow below
// the field's top (1 px a child), so they sit in nested 1 x 1 boxes (ED_NEST): box k's child i flows k + i px down
// (measured: exact). The boxes are also the draw order (a later box draws over an earlier one): the rings, the map's
// symbols, the texts, the bars. kOS turns a margin into whole pixels half to even, and ROUND is half to even too, so
// every position is FLOOR(x + 0.5) and every margin whole: a .5 margin (an ED_IMG_DY of -2.5) puts each sprite 2 or 3
// px low by its parity, neighbouring ring pieces 1-2 px apart.

RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_land.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_land.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_land.ks").           // ldGreatCircle, capeLine (the hosts have it already)
RUNONCEPATH("0:/lib/lib_guistyle.ks").       // uiRt, the displays' real-time clock
RUNONCEPATH("0:/lib/lib_gpc.ks").            // gpcLive (a window whose GPC failed is not redrawn)

GLOBAL ED_ARCH IS "0:/".
GLOBAL ED_DIR IS "entry_bg/".
GLOBAL ED_ON IS TRUE.                        // FALSE: no entry page (the deck's bottom window shows its row alone)
GLOBAL ED_DT IS 0.                           // s between updates: 0 = every host cycle (the C# twin
                                             //   redraws at 10 Hz between the cycles)
GLOBAL ED_SITE_DT IS 20.                     // s between the alternates' searches
GLOBAL ED_ALT_N IS 7.                        // the alternates shown (the 8 nearest sites less the target)
// The map's label placer: the labels in priority order (the target's runway name, the alternates' nearest first, the
// rings', the DB's), each at the first of its spots whose box is 2 px inside the field and clear of the symbols' and the
// labels' placed before it; no clear spot: the label off. A ring's label slides along its ring; close sites merge
GLOBAL ED_FIT_IN IS 1.5.                    // px a map sprite keeps inside the field (the rings' 1.5)
GLOBAL ED_LB_CW IS 0.602.                    // em: a character's advance (DejaVu Sans Mono), the labels' boxes
GLOBAL ED_MERGE_PX IS 12.                    // px: an alternate this near one shown before joins its label
GLOBAL ED_MERGE_N IS 3.                      // the names to a merged label at most
GLOBAL ED_RG_DA IS 22.5.                     // deg: a ring label's step along its ring, out from 240 (lower left)
GLOBAL ED_RG_TRY IS 16.                      // a ring label's tries (16 x 22.5: the whole ring)
GLOBAL ED_LB_RW IS LIST(LIST(9, -9, 0), LIST(9, 9, 0), LIST(-9, -9, 1), LIST(-9, 9, 1)).   // the runway name's spots
GLOBAL ED_LB_AL IS LIST(LIST(6, 0, 0), LIST(-6, 0, 1), LIST(6, -9, 0), LIST(6, 9, 0), LIST(-6, -9, 1), LIST(-6, 9, 1),
    LIST(0, -10, 2), LIST(0, 11, 2)).        // an alternate's name's spots (dx, dy, align) off its circle
GLOBAL edLbOb IS LIST().                     // the boxes taken this draw: LIST(x0, x1, y0, y1), field px
GLOBAL edLbDb IS LIST(0, 0, 0).              // the DB lines this draw: the bug's x, y and the tangent of their angle
// The labels hold still until the zoom changes: they are asked for in priority order (edLbAdd) and placed together
// (edLbRun): first every label at the spot it had at the last draw (its id in edLbMem by the label's key: "rw", "a" +
// the alternate's name, "r0".."r2" the rings', "db"), the predictor's dots not in its way there (they sweep across with
// the bank); then the rest each at the first clear of its spots. A label moves only when its own spot is taken by a
// symbol, a DB line or the field's edge, never to make room for another; a new zoom forgets them all
GLOBAL edLbMem IS LEXICON().                 // the labels' spots at the last draw: key -> the spot's id
GLOBAL edLbZm IS 0.                          // the zoom edLbMem's spots were taken at
GLOBAL edLbOld IS LEXICON().                 // this draw's memory (edLbMem, or empty after a zoom change)
GLOBAL edLbNw IS LEXICON().                  // this draw's spots (edLbMem from the draw's end)
GLOBAL edLbRq IS LIST().                     // this draw's labels: LIST(slot, text, spots LIST(x, y, align, id), key)
GLOBAL edLbHold IS FALSE.                    // edLbRun's first pass: the soft boxes (a 5th field) are not in the way
GLOBAL ED_LB_HYS IS 2.                       // px: a label holding its spot may overlap a DB line or a box by this much
GLOBAL ED_NEST IS TRUE.
GLOBAL ED_IMG_DY IS 0.                       // px: a sprite's row correction (0, measured on a screenshot)
GLOBAL ED_FLOW_PX IS 1.0.                    // px per flow child (AD_FLOW_PX)
GLOBAL ED_FONT IS "DejaVu Sans Mono Bold".   // the page's own face (the background's labels); "" = kOS's
GLOBAL ED_TXT_DY IS 7 - 2.35 + 1.            // px: AD_TXT_DY less DejaVu's lower baseline (traj_display TJ_TEXT_DY's
                                             //   2.35), + 1 measured in game (the map's labels 1 px below their
                                             //   symbols' centres without it)
GLOBAL ED_ROW_DY IS 2.65.                    // px: AD_ROW_DY (the value's caps centred on its label's row)
GLOBAL ED_VAL_DY IS ED_ROW_DY - 3.           // px: the value rows' (ENTRY TGT, ADI): measured, their caps on their
                                             //   labels' (a larger text sits lower in its label)
GLOBAL ED_CLK_DY IS ED_ROW_DY - 7.           // px: the clock's: the met row is the header's baseline, not a centre
                                             //   (measured: its digits end on the page id's)
GLOBAL ED_TXT_W IS 90.
GLOBAL ED_VT IS 762.                         // m/s: the TAEM interface's speed (the predictor ends there)
GLOBAL ED_PRED_STEPS IS 24.                  // the predictor's velocity steps (the speed now to ED_VT)
// The predictor's path ends at ED_VT, the TAEM interface, or at PRED's 3/4 of the field, whichever it reaches first;
// the last dot is on its end
// The turn along the path is the one the guidance will fly: L/D x sin(bank) on the reference drag, with the bank on the
// guidance's TAEM bank ramp (eprBankWithFlare's, scaled from the bank now) and L/D on alpha: the schedule (eprAoA) plus
// the alpha's offset from it now, so a crew's alpha shows, floored at ED_PRED_AOA_MIN; the L/D is the measured one
// scaled by the model's (eprPolar) ratio. The path turns at most ED_PRED_TURN from the track now, then runs straight;
// where it reaches the cap there is always a dot.
GLOBAL ED_PRED_AOA_MIN IS 15.                // deg
GLOBAL ED_PRED_TURN IS 120.                  // deg
GLOBAL ED_PR_DV IS 100.                      // m/s: the schedule table's step (from ED_VT to ED_PR_VMAX)
GLOBAL ED_PR_VMAX IS 7800.
GLOBAL ED_PR_DA IS 2.5.                      // deg: the L/D table's step (from ED_PRED_AOA_MIN to ED_PR_AMAX)
GLOBAL ED_PR_AMAX IS 50.
GLOBAL ED_PR_MACH IS 3.                      // the L/D table's Mach (its ratios between alphas move < 8 % from Mach 1.5 to 12)
GLOBAL edPrTab IS LIST().                    // edPrBuild's: LIST(v0, dv, alphas, a0, da, L/Ds, ramp v1, v0, k); empty: none
GLOBAL edCyc IS 0.                           // the flash phase without ENTRY TRAJ (no tjFlashN): edTick counts
GLOBAL edDbA IS LIST().                      // the overbright DB lines' sprites and anchor (empty: not overbright)

GLOBAL edOn IS FALSE.
GLOBAL edBox IS 0.
GLOBAL edXBox IS 0.                          // The big X's box (gui_panel/gpc_x), a sibling of edBox, shown in its place while the bottom window's GPC is dead
GLOBAL edXOn IS FALSE.                       // The X look is on (edGpcX)
GLOBAL edShownF IS FALSE.                    // The page is up (edShow)
GLOBAL edGeo IS LEXICON().
GLOBAL edSpr IS LEXICON().
GLOBAL edRgB IS LIST().                      // the rings' piece boxes about the site: LIST(LIST(x0, x1, y0, y1)) per ring
GLOBAL edTmB IS LEXICON().                   // the TAEM ring's, by zoom step
GLOBAL edBlank IS "".
GLOBAL edMk IS 0.                            // the nested box being filled and its child count
GLOBAL edMkN IS 0.
GLOBAL edMkK IS 0.                           // the nested boxes made
GLOBAL edS IS LEXICON().                     // the slots by name
GLOBAL edRg IS LIST().                       // the ring slots: LIST(ring 1's, ring 2's, the TAEM ring's)
GLOBAL edAl IS LIST().                       // the alternates' slots: LIST(LIST(circle, label))
GLOBAL edSites IS LIST().                    // hud_runways.txt's surveyed ends: LIST(site, end, lat, lng)
GLOBAL edNear IS LIST().                     // the alternates: LIST(end, lat, lng), nearest first
GLOBAL edSiteT IS -1.
GLOBAL edNext IS 0.
GLOBAL edRgKey IS "".                        // the rings' last site px + zoom (redrawn only on a change)
// The page's draw in C# (coproc Ed.cs / EdKos.cs, ADDONS:KALS:EDDRAW), so the whole page runs at 10 Hz; TD_CS's pattern:
// the state and the widgets stay kOS's, EDDRAW returns every widget write (tdCsApply sets them). ED_CS (default TRUE):
// C# draws; on ANY failure kOS draws that same draw and from then on (edCsOff; ED_CS_STATE says why).
// With C# live a trigger redraws the page every ED_DT_CS s between the host's
// calls: the vehicle now (position, track, attitude, rates, drag / lift, the guidance's bank / alpha, the DAP's command,
// the flash phase), the guidance's daz / db and TRAJ's range held from the last call; the alternates' search stays on
// the call (ED_SITE_DT). kOS drawing, a hidden page and a host that stopped calling (ED_CS_STALE s) keep one
// draw per call.
IF NOT (DEFINED ED_CS) { GLOBAL ED_CS IS TRUE. }
// THE PAINTER (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE; lib_taemdisp's TD_PAINT): the entry page's slot labels (group ED; in their nests, as HORIZ SIT's)
// drawn by C# inside kOS's window (each with its own style and content, at the rect kOS's layout gives it), their
// boxes hidden from kOS's layout. ED_PAINT: 0 OFF (the default until the test harness's CHECK + A/B proof: kOS draws as
// before), 1 CHECK (kOS draws; KSP.log [KalsPaint] worst px), 2 PAINT, 3 AB; live: edPaintSet(m). Any failure: kOS draws
// (ED_PAINT_STATE says why).
IF NOT (DEFINED ED_PAINT) { GLOBAL ED_PAINT IS 0. }
GLOBAL ED_PAINT_STATE IS "OFF".
GLOBAL edPaintReg IS FALSE.
GLOBAL edPaintNames IS LIST().            // the groups registered
GLOBAL edOrd IS LIST().                     // the slots in creation (= kOS's draw) order: LIST(label, flow index)
GLOBAL edCsOn IS FALSE.
GLOBAL ED_CS_ERR IS "".
GLOBAL EDG_CHK IS FALSE.                   // The DLL's EDGDL suffix looked up once (edCsIn's 34th item, SW 02 GUIDANCE LOST)
GLOBAL EDG_OK IS FALSE.
GLOBAL ED_CS_STATE IS "kOS (not set up)".
GLOBAL ED_CS_NRD IS 0.                       // redraws drawn
GLOBAL ED_DT_CS IS 0.1.                      // s between the redraws (0: none)
// With C# drawing, every draw is the trigger's, at the start of a physics tick (the host's call only hands it daz / db /
// rgo), once a tick, so every ground-anchored sprite moves on the same frame: the site, its rings, the HAC and the
// alternates step together off the site's whole px
GLOBAL ED_RD_TICK IS TRUE.                   // TRUE: a redraw every physics tick (ED_DT_CS's grid unused)
GLOBAL ED_CS_STALE IS 3.                     // s: no host call for this long ends the redraws
GLOBAL edArgs IS LIST().                     // the last call's daz, db, rgo (the redraws' held values)
GLOBAL edArgT IS 0.                          // TIME:SECONDS of the last call
GLOBAL edNx IS 0.                            // uiRt of the next redraw (on the ED_DT_CS grid, real s)
GLOBAL edBusy IS FALSE.                      // a draw is running: a redraw / edFlashDb waits
GLOBAL edTrig IS FALSE.                      // the redraw trigger is armed

FUNCTION edNums {
    PARAMETER lin.
    LOCAL out IS LIST().
    LOCAL p IS lin:SPLIT(" ").
    FROM { LOCAL i IS 1. } UNTIL i >= p:LENGTH STEP { SET i TO i + 1. } DO {
        IF p[i] <> "" { out:ADD(p[i]:TONUMBER(0)). }
    }
    RETURN out.
}

FUNCTION edLoad {
    LOCAL f IS ED_ARCH + ED_DIR + "entry_bg.txt".
    IF NOT EXISTS(f) OR NOT EXISTS(ED_ARCH + ED_DIR + "sprites.txt") OR NOT EXISTS(ED_ARCH + ED_DIR + "hsit_e.png") {
        RETURN FALSE.
    }
    SET edRgB TO LIST(LIST(), LIST()).
    SET edTmB TO LEXICON().
    FOR l0 IN OPEN(f):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        IF lin <> "" AND NOT lin:STARTSWITH("#") {
            LOCAL p IS lin:SPLIT(" ").
            LOCAL n IS edNums(lin).
            IF p[0] = "rgp" { edRgB[n[0] - 1]:ADD(LIST(n[2], n[3], n[4], n[5])). }
            ELSE IF p[0] = "tmp" {
                LOCAL z IS "" + n[0].
                IF NOT edTmB:HASKEY(z) { SET edTmB[z] TO LIST(). }
                edTmB[z]:ADD(LIST(n[2], n[3], n[4], n[5])).
            } ELSE { SET edGeo[p[0]] TO n. }
        }
    }
    FOR l0 IN OPEN(ED_ARCH + ED_DIR + "sprites.txt"):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS l0:REPLACE(CHAR(13), "").
        LOCAL p IS lin:SPLIT(" ").
        IF lin:STARTSWITH("S ") AND p:LENGTH >= 7 {
            SET edSpr[p[1]] TO LIST(p[2], p[3]:TONUMBER(0), p[4]:TONUMBER(0), p[5]:TONUMBER(0), p[6]:TONUMBER(0)).
        }
    }
    IF NOT (edGeo:HASKEY("field") AND edGeo:HASKEY("bar_ey") AND edSpr:HASKEY("blank") AND edSpr:HASKEY("bug")
            AND edSpr:HASKEY("triv") AND edSpr:HASKEY("arrv")) {   // the vertical bars' pointers
        RETURN FALSE.
    }
    IF edGeo["bar_ey"]:LENGTH < 5 {         // an older entry_bg.txt (its bars as x0 x1 y lim: no vertical bar)
        RETURN FALSE.
    }
    IF edRgB[0]:LENGTH = 0 OR edRgB[1]:LENGTH = 0 OR edTmB:LENGTH = 0 { RETURN FALSE. }
    SET edBlank TO edSpr["blank"][0].
    RETURN EXISTS(ED_ARCH + edBlank).
}

FUNCTION edSiteLoad {                        // hud_runways.txt's surveyed ends (lib_land ldSites' test)
    SET edSites TO LIST().
    LOCAL f IS "0:/hud/hud_runways.txt".
    IF NOT EXISTS(f) { RETURN. }
    FOR l0 IN OPEN(f):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL lin IS capeLine(l0:REPLACE(CHAR(13), "")).
        IF lin:STARTSWITH("R ") {
            LOCAL p IS lin:SPLIT(" ").
            IF p:LENGTH >= 15 { IF p[8]:TONUMBER(0) > -9999 {
                edSites:ADD(LIST(p[1], p[2], p[3]:TONUMBER(0), p[4]:TONUMBER(0))).
            } }
        }
    }
}

FUNCTION edSiteNear {                        // the nearest ED_ALT_N sites but the target's (one end each)
    LOCAL gp IS SHIP:GEOPOSITION.
    LOCAL seen IS LEXICON().
    LOCAL srt IS LIST().
    FOR s IN edSites {
        IF NOT seen:HASKEY(s[0]) {
            SET seen[s[0]] TO TRUE.
            LOCAL dt IS ldGreatCircle(RWY_THRESH:LAT, RWY_THRESH:LNG, s[2], s[3])[0].
            IF dt > 20000 {                  // not the target's site
                LOCAL d IS ldGreatCircle(gp:LAT, gp:LNG, s[2], s[3])[0].
                LOCAL it IS LIST(s[1], s[2], s[3], d).
                LOCAL i IS 0.
                UNTIL i >= srt:LENGTH { IF srt[i][3] > d { BREAK. } SET i TO i + 1. }
                srt:INSERT(i, it).
            }
        }
    }
    SET edNear TO LIST().
    FOR it IN srt { IF edNear:LENGTH < ED_ALT_N { edNear:ADD(it). } }
}

// ---- the slots: LIST(widget, flow offset px, last sprite / text, last x, y, ON, align, width, font size, own px
// lower, the last call's x, y, align, full width, kind "T" / "I")
FUNCTION edNest {                            // a new nested box: its children flow from edMkK px down
    IF ED_NEST {
        SET edMk TO edBox:ADDVLAYOUT().
        SET edMk:STYLE:WIDTH TO 1. SET edMk:STYLE:HEIGHT TO 1.
        SET edMk:STYLE:PADDING:H TO 0. SET edMk:STYLE:PADDING:V TO 0.
        SET edMk:STYLE:PADDING:BOTTOM TO 1.  // A nest whose boxes are all hidden keeps its row (edNewBox)
        SET edMk:STYLE:MARGIN:H TO 0. SET edMk:STYLE:MARGIN:V TO 0.
        SET edMkN TO edMkK.
        SET edMkK TO edMkK + 1.
    }
}

FUNCTION edNewBox {
    LOCAL bx IS edMk:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    RETURN bx:ADDLABEL("").
}

FUNCTION edSlot {
    PARAMETER m, w, fs, kd.
    LOCAL sl IS LIST(m, edMkN * ED_FLOW_PX, "", -99999, -99999, FALSE, "", w, fs, ED_ROW_DY, -99999, -99999, -1, w, kd).
    edOrd:ADD(LIST(m, edMkN)).              // The painter's list (ED_FLOW_PX 1)
    SET edMkN TO edMkN + 1.
    RETURN sl.
}

FUNCTION edImg {
    LOCAL m IS edNewBox().
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.   // 1:1 (the sprites are made at their shown size)
    SET m:STYLE:WIDTH TO 4. SET m:STYLE:HEIGHT TO 4.
    SET m:IMAGE TO edBlank.
    RETURN edSlot(m, -1, 0, "I").
}

FUNCTION edTxt {
    PARAMETER fs, w IS ED_TXT_W.
    LOCAL m IS edNewBox().
    SET m:STYLE:FONTSIZE TO fs.
    IF ED_FONT <> "" { SET m:STYLE:FONT TO ED_FONT. }
    SET m:STYLE:TEXTCOLOR TO RGB(0.235, 0.878, 0.235).
    SET m:STYLE:WIDTH TO w. SET m:STYLE:HEIGHT TO fs * 2.
    SET m:STYLE:RICHTEXT TO FALSE.
    RETURN edSlot(m, w, fs, "T").
}

FUNCTION edOff {
    PARAMETER sl.
    IF sl[5] {
        IF sl[14] = "T" { SET sl[0]:TEXT TO "". } ELSE { SET sl[0]:IMAGE TO edBlank. }
        SET sl[2] TO "".
        SET sl[5] TO FALSE.
    }
}

FUNCTION edPut {                             // a sprite's anchor at page px (x, y)
    PARAMETER sl, nm, x, y.
    IF nm = sl[2] AND x = sl[10] AND y = sl[11] { RETURN. }
    IF NOT edSpr:HASKEY(nm) { edOff(sl). RETURN. }
    LOCAL sp IS edSpr[nm].
    IF sl[2] <> nm {
        SET sl[0]:IMAGE TO sp[0].
        SET sl[0]:STYLE:WIDTH TO sp[1].
        SET sl[0]:STYLE:HEIGHT TO sp[2].
        SET sl[2] TO nm.
    }
    LOCAL xx IS FLOOR(x - sp[3] + 0.5).          // half up (ROUND is half to even)
    LOCAL yy IS FLOOR(y - sp[4] + 0.5).
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, FLOOR(yy - ED_IMG_DY - sl[1] + 0.5)).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    SET sl[10] TO x. SET sl[11] TO y.
    SET sl[5] TO TRUE.
}

FUNCTION edPutIn {                           // a map sprite at field px, only when its box is wholly in the field
    PARAMETER sl, nm, x, y.
    LOCAL sp IS edSpr[nm].
    LOCAL f IS edGeo["field"].
    // only a sprite wholly inside the field shows: ED_FIT_IN px inside the box it lives in
    IF x - sp[3] < ED_FIT_IN OR x - sp[3] + sp[1] > f[2] - ED_FIT_IN OR y - sp[4] < ED_FIT_IN
        OR y - sp[4] + sp[2] > f[2] - ED_FIT_IN {
        edOff(sl). RETURN FALSE.
    }
    edPut(sl, nm, f[0] + x, f[1] + y).
    RETURN TRUE.
}

FUNCTION edText {                            // text; align 0 left, 1 right (its right edge at x), 2 centred
    PARAMETER sl, s, x, y, align.
    IF s = "" { edOff(sl). RETURN. }
    IF s = sl[2] AND x = sl[10] AND y = sl[11] AND align = sl[12] { RETURN. }
    IF sl[2] <> s { SET sl[0]:TEXT TO s. SET sl[2] TO s. }
    LOCAL w IS sl[13].
    LOCAL xx IS FLOOR(x + 0.5).
    LOCAL al IS "LEFT".
    IF align = 1 { SET w TO MAX(1, MIN(sl[13], xx)). SET xx TO xx - w. SET al TO "RIGHT". }
    ELSE IF align = 2 { SET w TO MAX(2, MIN(sl[13], 2 * xx)). SET xx TO FLOOR(x - w / 2 + 0.5). SET al TO "CENTER". }
    IF sl[6] <> al { SET sl[0]:STYLE:ALIGN TO al. SET sl[6] TO al. }
    IF sl[7] <> w { SET sl[0]:STYLE:WIDTH TO w. SET sl[7] TO w. }
    LOCAL yy IS FLOOR(y - sl[8] * 0.7 - ED_TXT_DY + sl[9] + 0.5).
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy - sl[1]).
        SET sl[3] TO xx. SET sl[4] TO yy.
    }
    SET sl[10] TO x. SET sl[11] TO y. SET sl[12] TO align.
    SET sl[5] TO TRUE.
}

FUNCTION edInit {                            // the page in the deck's bottom window (once); FALSE: no page
    IF edOn { RETURN TRUE. }
    IF NOT ED_ON { RETURN FALSE. }
    IF NOT (DEFINED tdDeck) { RETURN FALSE. }
    IF NOT tdDeck { RETURN FALSE. }
    IF NOT edLoad() { RETURN FALSE. }
    edSiteLoad().
    SET edBox TO tdGuiH:ADDVLAYOUT().        // after tdBoxH (hidden: out of the flow), so under the button row
    SET edBox:STYLE:PADDING:H TO 0.
    SET edBox:STYLE:PADDING:V TO 0.
    SET edBox:STYLE:WIDTH TO edGeo["png_w"][0].
    SET edBox:STYLE:HEIGHT TO edGeo["png_h"][0].
    SET edBox:STYLE:BG TO ED_DIR + "hsit_e.png".
    SET edXBox TO tdGuiH:ADDVLAYOUT().        // The X look (edGpcX), right after edBox: the same place in the flow, hidden until the window's GPC is dead
    SET edXBox:STYLE:PADDING:H TO 0.
    SET edXBox:STYLE:PADDING:V TO 0.
    SET edXBox:STYLE:WIDTH TO edGeo["png_w"][0].
    SET edXBox:STYLE:HEIGHT TO edGeo["png_h"][0].
    SET edXBox:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
    edXBox:HIDE().
    SET edMk TO edBox. SET edMkN TO 0. SET edMkK TO 0.
    SET edOrd TO LIST().
    LOCAL fs IS edGeo["fs"].                 // values, map labels, runway / zoom, TRK (px)
    LOCAL fv IS ROUND(fs[0]).
    LOCAL fm IS ROUND(fs[1]).
    // the boxes in the draw order (the DB lines above the rings)
    // boxes 0-2: the rings (the big one in two)
    SET edRg TO LIST(LIST(), LIST(), LIST()).
    edNest().
    FOR b IN edRgB[0] { edRg[0]:ADD(edImg()). }
    edNest().
    LOCAL n2 IS edRgB[1]:LENGTH.
    FROM { LOCAL i IS 0. } UNTIL i >= n2 STEP { SET i TO i + 1. } DO {
        IF i = ROUND(n2 / 2) { edNest(). }
        edRg[1]:ADD(edImg()).
    }
    // box 3: the TAEM ring
    edNest().
    FOR b IN edTmB[edTmB:KEYS[0]] { edRg[2]:ADD(edImg()). }
    // box 4: the map's symbols over the rings (the alternates, the runway, the HAC, the deadband, the predictor, the bug)
    edNest().
    SET edAl TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= ED_ALT_N STEP { SET i TO i + 1. } DO { edAl:ADD(LIST(edImg(), edTxt(fm))). }
    FOR k IN LIST("rwy", "hac", "db0", "db1", "p1", "p2", "p3", "p4", "p5", "bug") { SET edS[k] TO edImg(). }
    // box 5: the page's texts (the clock and TRK above the field first)
    edNest().
    SET edS["met"] TO edTxt(13, 160).
    LOCAL mc IS edS["met"]. SET mc[9] TO ED_CLK_DY.
    SET edS["trk"] TO edTxt(ROUND(fs[3])).
    FOR k IN LIST("aR", "aP", "aY", "gR", "gP", "gY") { SET edS[k] TO edTxt(fv). }
    FOR k IN LIST("l0", "l1", "l2", "l3", "l4", "l5") { SET edS[k] TO edTxt(fv). }
    FOR k IN LIST("aR", "aP", "aY", "gR", "gP", "gY", "l0", "l1", "l2", "l3", "l4", "l5") {
        LOCAL vc IS edS[k]. SET vc[9] TO ED_VAL_DY.
    }
    FOR k IN LIST("lr1", "lr2", "ltm", "ldb") { SET edS[k] TO edTxt(fm). }
    SET edS["lrw"] TO edTxt(ROUND(fs[2])).
    SET edS["zm"] TO edTxt(ROUND(fs[2])).
    // box 6: the bars' pointers
    edNest().
    FOR k IN LIST("rp", "rq", "rr") { SET edS["t" + k] TO edImg(). SET edS["c" + k] TO edImg(). }
    FOR k IN LIST("eb", "ea", "ey") { SET edS["t" + k] TO edImg(). }
    SET edRgKey TO "".
    SET edSiteT TO -1.
    SET edNext TO 0.
    SET edOn TO TRUE.
    IF DEFINED TJ_AFTER { SET TJ_AFTER TO edFlashDb@. }   // the DB lines flash with ENTRY TRAJ's redraws
    edPrBuild().
    edCsSetup().                             // the slots to the addon
    edPaintSetup().                          // The painter (ED_PAINT; OFF by default)
    gpcWin("BOT", edGpcX@).                  // The bottom window's X look (lib_gpc): its GPC failed = the big X in place of the page
    RETURN TRUE.
}

FUNCTION edShow {
    IF NOT edOn { RETURN. }
    SET tdGuiH:STYLE:HEIGHT TO edGeo["png_h"][0] + 48 + 2 * TD_ROW_H.   // tdWin's (the page under the rows)
    SET edShownF TO TRUE.
    IF edXOn { edXBox:SHOW(). } ELSE { edBox:SHOW(). }   // The X in place of the page while its GPC is dead
    tdGuiH:SHOW().
    gpcWinSync().                            // A GPC already dead: the X now, not at the next gpcTick
}

// lib_gpc: the X look of the bottom window = the entry page. dead TRUE: the page box hidden and the big X box shown in its
// place (the C# writes into the hidden page do no harm; edTick / edRedraw draw nothing while the GPC is dead); FALSE (the GPC
// back, GPC/CRT X/Y EXEC): the page again, redrawn by the next edTick. edXOn is kept while the page is down (edShow honours it).
FUNCTION edGpcX {
    PARAMETER dead.
    IF NOT edOn { RETURN. }
    SET edXOn TO dead.
    IF NOT edShownF { RETURN. }
    IF dead { edBox:HIDE(). edXBox:SHOW(). } ELSE { edXBox:HIDE(). edBox:SHOW(). }
}

FUNCTION edDeckUp {                          // the hosts' call at EI: the page, or the row alone (tdDeckBarH)
    IF NOT (DEFINED tdDeck) { RETURN. }
    IF NOT tdDeck { RETURN. }
    IF edInit() { edShow(). } ELSE { tdDeckBarH(). }
}

FUNCTION edF1 {                              // one decimal, always shown
    PARAMETER x.
    LOCAL s IS ROUND(x, 1):TOSTRING.
    IF NOT s:CONTAINS(".") { SET s TO s + ".0". }
    RETURN s.
}

FUNCTION edLR {                              // one decimal behind its side's letter (a at + , b at -),
    PARAMETER x, a, b.                       // none at 0.0
    LOCAL rx IS ROUND(x, 1).
    IF rx = 0 { RETURN "0.0". }
    RETURN (CHOOSE a IF rx > 0 ELSE b) + edF1(ABS(rx)).
}

FUNCTION edLit {                             // ENTRY TRAJ's flash phase (its bug's: tjFlashN's parity; edTick runs
    IF DEFINED tjFlashClk { IF tjFlashClk { RETURN MOD(FLOOR((uiRt() + 0.005) / TJ_DT_CS), 2) = 0. } }
    IF DEFINED tjFlashN { RETURN MOD(tjFlashN, 2) = 0. }   // right after trajUpdate, so both draw the same half)
    RETURN MOD(edCyc, 2) = 0.
}

FUNCTION edFlashDb {                         // at 5 Hz, as every flash: traj_display's TJ_AFTER, after
    IF NOT edOn OR edDbA:LENGTH = 0 { RETURN. }   // each C# draw (its 10 Hz redraws too): the overbright lines in its phase
    IF edBusy { RETURN. }                    // the page is drawing (its own draw puts them in the same phase)
    IF edLit() {
        edPut(edS["db0"], edDbA[0], edDbA[2], edDbA[3]).
        edPut(edS["db1"], edDbA[1], edDbA[2], edDbA[3]).
    } ELSE {
        edOff(edS["db0"]).
        edOff(edS["db1"]).
    }
}

FUNCTION edS1 {                              // signed, one decimal
    PARAMETER x.
    LOCAL rx IS ROUND(x, 1).
    RETURN (CHOOSE "+" IF rx >= 0 ELSE "") + edF1(rx).
}

FUNCTION edP3 {                              // 000-359
    PARAMETER x.
    LOCAL s IS MOD(ROUND(x) + 720, 360):TOSTRING.
    UNTIL s:LENGTH >= 3 { SET s TO "0" + s. }
    RETURN s.
}

FUNCTION edP2 {
    PARAMETER n.
    RETURN (CHOOSE "0" IF n < 10 ELSE "") + n.
}

FUNCTION edBar {                             // a bar's pointer: its tip on the line at the value (clamped to the scale)
    PARAMETER sl, nm, key, val.              // bar_<key> = the - end (x, y), the + end, the scale; a vertical
    LOCAL b IS edGeo["bar_" + key].         //   bar (pitch, + = up) takes the pointers that point left (nm + "v")
    LOCAL f IS 0.5 + 0.5 * MAX(-1, MIN(1, val / b[4])).
    edPut(sl, CHOOSE nm + "v" IF b[0] = b[2] ELSE nm, b[0] + (b[2] - b[0]) * f, b[1] + (b[3] - b[1]) * f).
}

// the predictor's track, from the speed now down to ED_VT, until it has run sm m. The drag follows the entry guidance's
// reference (eprFamRef's member blend at EPR_GS_U, column 2) scaled to the measured drag now (the drag now held is ~1
// m/s2 off early and grows, so the dots ran 500 s ahead, where the bank had turned the track 7 deg); the bank and L/D
// held, so the heading turns kk LN(v0 / v) whatever the drag. Without the family (or a 0 reference) the drag now held.
// -> LIST(t s, x m right, y m ahead), one point per step, the first 0. Its own bracket per member: the guidance's
// EPR_FAM_HINT is not touched.
FUNCTION edFamPrep {
    PARAMETER v0.
    IF NOT (DEFINED EPR_FAM_OK) { RETURN 0. }
    IF NOT EPR_FAM_OK OR EPR_FAM:LENGTH < 2 { RETURN 0. }
    LOCAL uu IS MAX(0, MIN(EPR_FAM_UTOP, EPR_GS_U)).
    LOCAL x IS uu * (EPR_FAM:LENGTH - 1).
    LOCAL i IS MIN(FLOOR(x), EPR_FAM:LENGTH - 2).
    LOCAL fm IS LIST(EPR_FAM[i], EPR_FAM[i + 1], x - i, LIST(1, 1)).
    FROM { LOCAL m IS 0. } UNTIL m > 1 STEP { SET m TO m + 1. } DO {
        LOCAL vs IS fm[m][1].
        IF vs:LENGTH < 2 { RETURN 0. }
        LOCAL lo IS 1.                           // the first k with vs[k] <= v0 (the samples fall)
        LOCAL hi IS vs:LENGTH - 1.
        UNTIL lo >= hi {
            LOCAL md IS FLOOR((lo + hi) / 2).
            IF vs[md] <= v0 { SET hi TO md. } ELSE { SET lo TO md + 1. }
        }
        SET fm[3][m] TO lo.
    }
    RETURN fm.
}

FUNCTION edFamD {                             // the blended reference drag at vr (vr falls from call to call)
    PARAMETER fm, vr.
    LOCAL d IS LIST(0, 0).
    FROM { LOCAL m IS 0. } UNTIL m > 1 STEP { SET m TO m + 1. } DO {
        LOCAL vs IS fm[m][1].
        LOCAL cs IS fm[m][2].
        LOCAL n IS vs:LENGTH.
        IF vr >= vs[0] { SET d[m] TO cs[0]. }
        ELSE IF vr <= vs[n - 1] { SET d[m] TO cs[n - 1]. }
        ELSE {
            LOCAL k IS MAX(1, fm[3][m]).
            UNTIL vs[k] <= vr { SET k TO k + 1. }
            SET fm[3][m] TO k.
            SET d[m] TO cs[k - 1] + (cs[k] - cs[k - 1]) * (vs[k - 1] - vr) / MAX(vs[k - 1] - vs[k], 0.000000001).
        }
    }
    RETURN d[0] * (1 - fm[2]) + d[1] * fm[2].
}

FUNCTION edPrBuild {                         // edInit's: the predictor's tables from entry_predict (none without it)
    SET edPrTab TO LIST().
    IF NOT (DEFINED EPR_AOA_HIGH) { RETURN. }
    IF NOT (DEFINED EPR_LIFT_CURVE) { RETURN. }
    IF NOT (DEFINED EPR_BANK_MAX) { RETURN. }
    LOCAL av IS LIST().
    FROM { LOCAL vq IS ED_VT. } UNTIL vq > ED_PR_VMAX STEP { SET vq TO vq + ED_PR_DV. } DO { av:ADD(eprAoA(vq)). }
    LOCAL lv IS LIST().
    FROM { LOCAL a IS ED_PRED_AOA_MIN. } UNTIL a > ED_PR_AMAX STEP { SET a TO a + ED_PR_DA. } DO {
        LOCAL pl IS eprPolar(a, ED_PR_MACH).
        lv:ADD(pl[0] / MAX(pl[1], 0.000001)).
    }
    LOCAL r1 IS 0.
    LOCAL r0 IS 0.
    LOCAL rk IS 1.
    IF DEFINED EPR_BANK_TAEM_SPEED {
        SET r1 TO EPR_BANK_TAEM_SPEED.
        SET r0 TO EPR_TAEM_VEL.
        SET rk TO EPR_BANK_TAEM_LIMIT / EPR_BANK_MAX.
    }
    SET edPrTab TO LIST(ED_VT, ED_PR_DV, av, ED_PRED_AOA_MIN, ED_PR_DA, lv, r1, r0, rk).
}
FUNCTION edPrAt {                            // the table l (l[0] at x0, step dx) at x, linear, held at both ends
    PARAMETER l, x0, dx, x.
    LOCAL n IS l:LENGTH.
    LOCAL i IS MAX(0, MIN(n - 1, (x - x0) / dx)).
    LOCAL k IS MIN(n - 2, FLOOR(i)).
    RETURN l[k] + (l[k + 1] - l[k]) * (i - k).
}
FUNCTION edPrRamp {                          // eprBankWithFlare's TAEM ramp factor at vq (1 above it)
    PARAMETER vq.
    IF edPrTab:LENGTH = 0 { RETURN 1. }
    LOCAL r1 IS edPrTab[6].
    IF r1 > 0 AND vq < r1 {
        LOCAL sp IS r1 - edPrTab[7].
        LOCAL w IS 1.
        IF sp > 0 { SET w TO (r1 - vq) / sp. }
        SET w TO MAX(0, MIN(1, w)).
        RETURN 1 - w * (1 - edPrTab[8]).
    }
    RETURN 1.
}
FUNCTION edPrK {                             // the turn per ln(speed) at vq: L/D x sin(bank), + = right
    PARAMETER vq, ld, bk, ao, l0, r0.
    IF edPrTab:LENGTH = 0 { RETURN ld * SIN(0 - bk). }
    LOCAL a IS MAX(ED_PRED_AOA_MIN, edPrAt(edPrTab[2], edPrTab[0], edPrTab[1], vq) + ao).
    RETURN ld * edPrAt(edPrTab[5], edPrTab[3], edPrTab[4], a) / l0 * SIN(0 - bk * edPrRamp(vq) / r0).
}

FUNCTION edPredPath {
    PARAMETER v0, d0, ld, bk, al, sm.        // the speed, drag, L/D, bank and alpha now; the path's longest, m
    LOCAL ao IS 0.                           // the alpha's offset from the schedule
    LOCAL l0 IS 1.                           // the model's L/D at the alpha now
    LOCAL r0 IS 1.                           // the ramp factor now
    IF edPrTab:LENGTH > 0 {
        SET ao TO al - edPrAt(edPrTab[2], edPrTab[0], edPrTab[1], v0).
        SET l0 TO edPrAt(edPrTab[5], edPrTab[3], edPrTab[4], MAX(ED_PRED_AOA_MIN, al)).
        SET r0 TO edPrRamp(v0).
    }
    LOCAL fm IS edFamPrep(v0).
    LOCAL sc IS 1.
    IF NOT fm:ISTYPE("Scalar") {
        LOCAL dr0 IS edFamD(fm, v0).
        IF dr0 > 0.05 { SET sc TO d0 / dr0. } ELSE { SET fm TO 0. }
    }
    LOCAL dv IS (v0 - ED_VT) / ED_PRED_STEPS.
    LOCAL tt IS LIST(0).
    LOCAL xs IS LIST(0).
    LOCAL ys IS LIST(0).
    LOCAL t IS 0.
    LOCAL s IS 0.
    LOCAL x IS 0.
    LOCAL y IS 0.
    LOCAL vv IS v0.
    LOCAL ps IS 0.                           // the heading at vv, deg from the track now
    LOCAL ta IS -1.                          // the time the turn reaches ED_PRED_TURN (a step's start); -1: never
    FROM { LOCAL j IS 0. } UNTIL j >= ED_PRED_STEPS OR s >= sm STEP { SET j TO j + 1. } DO {
        LOCAL vm IS vv - dv / 2.
        LOCAL dm IS d0.
        IF NOT fm:ISTYPE("Scalar") { SET dm TO MAX(0.05, sc * edFamD(fm, vm)). }
        LOCAL dt IS dv / dm.
        LOCAL kk IS edPrK(vm, ld, bk, ao, l0, r0).
        LOCAL pm IS MAX(0 - ED_PRED_TURN, MIN(ED_PRED_TURN, ps + kk * LN(vv / vm) * CONSTANT:RADTODEG)).
        IF ta < 0 AND ABS(pm) >= ED_PRED_TURN { SET ta TO t. }
        LOCAL ds IS vm * dt.
        IF s + ds > sm {                     // the last step cut to end on sm
            LOCAL g IS (sm - s) / ds.
            SET dt TO dt * g.
            SET ds TO ds * g.
        }
        SET x TO x + ds * SIN(pm).
        SET y TO y + ds * COS(pm).
        SET s TO s + ds.
        SET t TO t + dt.
        SET ps TO ps + kk * LN(vv / (vv - dv)) * CONSTANT:RADTODEG.
        SET vv TO vv - dv.
        tt:ADD(t). xs:ADD(x). ys:ADD(y).
    }
    RETURN LIST(tt, xs, ys, ta).
}

FUNCTION edTick {                            // once a guidance cycle: daz, db deg (the guidance's), rgo m (TRAJ's range)
    PARAMETER daz, db, rgo.
    IF NOT edOn { RETURN. }
    IF NOT gpcLive("BOT") { RETURN. }        // The entry page is the bottom window: its GPC failed, the last picture stays, then the big X (edGpcX)
    IF TIME:SECONDS < edNext { RETURN. }
    SET edNext TO TIME:SECONDS + ED_DT.
    SET edCyc TO edCyc + 1.
    IF TIME:SECONDS - edSiteT >= ED_SITE_DT OR edSiteT < 0 { SET edSiteT TO TIME:SECONDS. edSiteNear(). }   // the alternates
    SET edArgs TO LIST(daz, db, rgo).        // the redraws' held values
    SET edArgT TO TIME:SECONDS.
    // the trigger draws at the next tick's start (one frame for every sprite, not a draw spread over the ticks)
    IF ED_RD_TICK AND edTrig AND edCsOn AND ED_CS AND edBox:VISIBLE { RETURN. }
    LOCAL inp IS edCsIn(daz, db, rgo).       // the draw's reads, the same for kOS's draw and C#'s
    SET edBusy TO TRUE.
    IF edCsOn AND ED_CS {                    // C# draws (ED_CS)
        SET edNx TO CHOOSE 0 IF ED_RD_TICK ELSE (FLOOR((uiRt() + 0.005) / ED_DT_CS) + 1) * ED_DT_CS - 0.005.
        IF edCsDraw(inp) {
            SET edBusy TO FALSE.
            edRateArm().
            RETURN.
        }
    }
    edTickK(inp).
    SET edBusy TO FALSE.
}

// one draw's reads (Ed.cs reads them by index; edTickK too): [0] TIME, [1] daz, [2] db, [3] rgo, [4] lat, [5] lng,
// [6] the body's radius, [7] RWY_THRESH lat, [8] lng, [9] the ground track, [10] the speed, [11] the bank (+ = LEFT),
// [12] FD_DRAG, [13] FD_LIFT, [14] MISSIONTIME, [15] alpha, [16] beta (+ = the velocity to the right), [17] alpha with its
// side, [18] the guidance's bank, [19] its alpha, [20..22] the rates (+ = right roll / nose up / nose right), [23] the
// DAP's rate command (a LIST, or 0), [24] edLit(), [25] the HAC on, [26] its lat, [27] lng, [28] EPR_HAC_YSGN,
// [29] RWY_HEADING, [30] RWY_NAME, [31] the entry guidance's family defined, [32] pre-entry (NOT EPR_GS_STARTED:
// the guidance has not started; the HUD's PREENT)
// [33] (only for a DLL with the EDGDL suffix) SW 02 GUIDANCE LOST (ENTRY)
FUNCTION edCsIn {
    PARAMETER daz, db, rgo.
    LOCAL gp IS SHIP:GEOPOSITION.
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL spd IS vs:MAG.
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL nv IS SHIP:NORTH:VECTOR.
    LOCAL trk IS ARCTAN2(VDOT(vs, VCRS(upv, nv)), VDOT(vs, nv)).   // the ground track (VCRS(up, north) = east)
    LOCAL fc IS SHIP:FACING.
    LOCAL vh IS CHOOSE vs:NORMALIZED IF spd > 1 ELSE fc:FOREVECTOR.
    LOCAL upP IS VXCL(vh, upv).
    LOCAL topP IS VXCL(vh, fc:TOPVECTOR).
    LOCAL bk IS 0.                           // + = LEFT (ops3q bankActual's)
    IF upP:MAG > 0.001 AND topP:MAG > 0.001 {
        SET bk TO VANG(upP, topP).
        IF VDOT(VCRS(upP:NORMALIZED, topP:NORMALIZED), vh) < 0 { SET bk TO 0 - bk. }
    }
    LOCAL fv IS fc:FOREVECTOR.
    LOCAL alf IS VANG(fv, vh).
    LOCAL be IS ARCSIN(MAX(-1, MIN(1, VDOT(vh, fc:STARVECTOR)))).   // + = the velocity to the right
    LOCAL gb IS 0.
    IF DEFINED bankNow { SET gb TO bankNow. }
    LOCAL ga IS alf.
    IF DEFINED entryAoaCmd { SET ga TO entryAoaCmd. }
    // each angle with the attitude's side (L / R, U / D, for the pitch and yaw too),
    // as the bank's L / R: alpha U = the nose above the velocity, beta L = the nose left of it (the velocity to the right)
    LOCAL au IS CHOOSE alf IF VDOT(vh, fc:TOPVECTOR) <= 0 ELSE 0 - alf.
    LOCAL w IS SHIP:ANGULARVEL * CONSTANT:RADTODEG.   // w . FORE = LEFT roll, w . -STAR = nose up, w . TOP = nose right
    LOCAL wc IS 0.
    IF DEFINED grdWc { IF grdOn { SET wc TO grdWc. } }
    LOCAL hon IS FALSE.
    IF DEFINED EPR_HAC_ON { SET hon TO EPR_HAC_ON. }
    LOCAL inp IS LIST(TIME:SECONDS, daz, db, rgo, gp:LAT, gp:LNG, SHIP:BODY:RADIUS, RWY_THRESH:LAT, RWY_THRESH:LNG, trk,
                      spd, bk, FD_DRAG, FD_LIFT, MISSIONTIME, alf, be, au, gb, ga).
    inp:ADD(0 - VDOT(w, fv)). inp:ADD(0 - VDOT(w, fc:STARVECTOR)). inp:ADD(VDOT(w, fc:TOPVECTOR)).
    inp:ADD(wc). inp:ADD(edLit()). inp:ADD(hon).
    IF hon { inp:ADD(EPR_HAC_LAT). inp:ADD(EPR_HAC_LNG). inp:ADD(EPR_HAC_YSGN). } ELSE { inp:ADD(0). inp:ADD(0). inp:ADD(0). }
    inp:ADD(RWY_HEADING). inp:ADD(RWY_NAME).
    IF DEFINED EPR_FAM_OK { inp:ADD(TRUE). } ELSE { inp:ADD(FALSE). }
    IF DEFINED EPR_GS_STARTED { inp:ADD(NOT EPR_GS_STARTED). } ELSE { inp:ADD(FALSE). }
    // [33]:SW 02 GUIDANCE LOST (ENTRY): the C# page blanks the guidance's bank / alpha rows and the two fly-to bars as edDraw's kOS twin does.
    // Only a DLL that knows the 34th item (EDGDL) gets it: the scripts go live before the DLL (an older one counts 33 reads and refuses the draw)
    IF NOT EDG_CHK { SET EDG_CHK TO TRUE. SET EDG_OK TO ADDONS:HASSUFFIX("KALS") AND ADDONS:KALS:HASSUFFIX("EDGDL"). }
    IF EDG_OK {
        LOCAL gdl IS FALSE.
        IF DEFINED FLFX_SWPROG { SET gdl TO flfxSwGuid("ENTRY"). }
        inp:ADD(gdl).
    }
    RETURN inp.
}

FUNCTION edGc {                              // lib_land's ldGreatCircle on the body radius rb -> LIST(dist m, bearing deg)
    PARAMETER lat1, lon1, lat2, lon2, rb.
    LOCAL dl IS lon2 - lon1.
    LOCAL a IS SIN((lat2 - lat1) / 2.0) ^ 2 + COS(lat1) * COS(lat2) * SIN(dl / 2.0) ^ 2.
    LOCAL dist IS 2.0 * rb * ARCSIN(MIN(1.0, SQRT(a))) * TG_D2R.
    LOCAL brg IS ARCTAN2(SIN(dl) * COS(lat2), COS(lat1) * SIN(lat2) - SIN(lat1) * COS(lat2) * COS(dl)).
    IF brg < 0 { SET brg TO brg + 360.0. }
    RETURN LIST(dist, brg).
}

// a label's box (field px): its characters at ED_LB_CW em, the row's y - 0.6 .. + 0.5 em, 1 px around
FUNCTION edLbBox {
    PARAMETER s, fz, x, y, al.
    LOCAL w IS s:LENGTH * ED_LB_CW * fz.
    LOCAL x0 IS x - 1.
    IF al = 1 { SET x0 TO x - w - 1. } ELSE IF al = 2 { SET x0 TO x - w / 2 - 1. }
    RETURN LIST(x0, x0 + w + 2, y - 0.6 * fz - 1, y + 0.5 * fz + 1).
}

FUNCTION edLbOne {                           // the label at field px (x, y) if its box is 2 px inside the field
    PARAMETER sl, s, x, y, al, f.            //   and clear of every box taken; it then takes its box
    LOCAL b IS edLbBox(s, sl[8], x, y, al).
    IF b[0] < 2 OR b[1] > f[2] - 2 OR b[2] < 2 OR b[3] > f[2] - 2 { RETURN FALSE. }
    LOCAL bf IS b.                           // holding its spot, tested ED_LB_HYS smaller (it takes its full box)
    IF edLbHold { SET b TO LIST(b[0] + ED_LB_HYS, b[1] - ED_LB_HYS, b[2] + ED_LB_HYS, b[3] - ED_LB_HYS). }
    IF b[2] < edLbDb[1] {                    // the DB lines, x = vx -+ (vy - y) tan, above the bug (1.5 px their stroke)
        LOCAL ya IS (edLbDb[1] - b[2]) * edLbDb[2].
        LOCAL yb IS MAX(0, edLbDb[1] - b[3]) * edLbDb[2].
        IF edLbDb[0] + yb < b[1] + 1.5 AND edLbDb[0] + ya > b[0] - 1.5 { RETURN FALSE. }
        IF edLbDb[0] - ya < b[1] + 1.5 AND edLbDb[0] - yb > b[0] - 1.5 { RETURN FALSE. }
    }
    FOR o IN edLbOb {
        IF (o:LENGTH < 5 OR NOT edLbHold) AND b[0] < o[1] AND b[1] > o[0] AND b[2] < o[3] AND b[3] > o[2] { RETURN FALSE. }
    }
    edLbOb:ADD(bf).
    edText(sl, s, f[0] + x, f[1] + y, al).
    RETURN TRUE.
}

FUNCTION edLbPut {                           // the label at the first clear of its spots (dx, dy, align); else off
    PARAMETER sl, s, x, y, cs, ky.           // asked for (edLbAdd); ky its memory's key, the spots' ids their index
    LOCAL ab IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= cs:LENGTH STEP { SET i TO i + 1. } DO {
        ab:ADD(LIST(x + cs[i][0], y + cs[i][1], cs[i][2], i)).
    }
    edLbAdd(sl, s, ab, ky).
}

FUNCTION edLbAdd {                           // a label asked for, at one of cs (LIST(x, y, align, id)), in order
    PARAMETER sl, s, cs, ky.
    edLbRq:ADD(LIST(sl, s, cs, ky)).
}

FUNCTION edLbRun {                           // this draw's labels: each at its last draw's spot if still clear
    PARAMETER f.                             //   (the soft boxes not counted), then the rest at the first clear of
    LOCAL dn IS LIST().                      //   their spots in their order; none: off
    SET edLbHold TO TRUE.
    FOR lq IN edLbRq {
        LOCAL ok IS FALSE.
        IF edLbOld:HASKEY(lq[3]) {
            LOCAL m IS edLbOld[lq[3]].
            FOR c IN lq[2] { IF NOT ok AND c[3] = m { SET ok TO edLbOne(lq[0], lq[1], c[0], c[1], c[2], f). } }
            IF ok { SET edLbNw[lq[3]] TO m. }
        }
        dn:ADD(ok).
    }
    SET edLbHold TO FALSE.
    FROM { LOCAL i IS 0. } UNTIL i >= edLbRq:LENGTH STEP { SET i TO i + 1. } DO {
        IF NOT dn[i] {
            LOCAL lq IS edLbRq[i].
            LOCAL ok IS FALSE.
            FOR c IN lq[2] {
                IF NOT ok { IF edLbOne(lq[0], lq[1], c[0], c[1], c[2], f) { SET ok TO TRUE. SET edLbNw[lq[3]] TO c[3]. } }
            }
            IF NOT ok { edOff(lq[0]). }
        }
    }
}

FUNCTION edTickK {                           // edTick's kOS drawing on edCsIn's reads (Ed.cs's Draw, line for line)
    PARAMETER inp.
    LOCAL daz IS inp[1].
    LOCAL db IS inp[2].
    LOCAL rgo IS inp[3].
    LOCAL lat IS inp[4].
    LOCAL lng IS inp[5].
    LOCAL br IS inp[6].
    LOCAL trk IS inp[9].
    LOCAL spd IS inp[10].
    LOCAL bk IS inp[11].
    LOCAL f IS edGeo["field"].
    LOCAL fs IS f[2].
    LOCAL vx IS edGeo["veh"][0].
    LOCAL vy IS edGeo["veh"][1].
    LOCAL ah IS edGeo["ahead"][0].
    // the zoom: the tightest step with the site inside ZOOM_IN of it
    LOCAL gc IS edGc(lat, lng, inp[7], inp[8], br).
    LOCAL rnm IS gc[0] / 1852.
    LOCAL zs IS edGeo["zooms"].              // entry_bg.txt's steps (2000 NM down), the widest first
    LOCAL zm IS zs[0].
    FOR z IN zs { IF rnm <= edGeo["zoom_in"][0] * z { SET zm TO z. } }
    LOCAL ppn IS ah / zm.
    LOCAL a IS gc[1] - trk.
    LOCAL sx IS vx + rnm * ppn * SIN(a).
    LOCAL sy IS vy - rnm * ppn * COS(a).
    // the rings about the site: a piece shown only when wholly inside (1.5 px), on a change of the site's px or the step
    // (their labels are placed with the map's other labels, below)
    LOCAL rsx IS ROUND(sx).
    LOCAL rsy IS ROUND(sy).
    LOCAL ky IS rsx + " " + rsy + " " + zm.
    IF ky <> edRgKey {
        SET edRgKey TO ky.
        FROM { LOCAL g IS 0. } UNTIL g >= 3 STEP { SET g TO g + 1. } DO {
            LOCAL bb IS CHOOSE edTmB["" + zm] IF g = 2 ELSE edRgB[g].
            LOCAL pre IS CHOOSE "tm" + zm + "_" IF g = 2 ELSE "rg" + (g + 1) + "_".
            FROM { LOCAL k IS 0. } UNTIL k >= bb:LENGTH STEP { SET k TO k + 1. } DO {
                LOCAL b IS bb[k].
                LOCAL sl IS edRg[g][k].
                IF rsx + b[0] >= 1.5 AND rsx + b[1] <= fs - 1.5 AND rsy + b[2] >= 1.5 AND rsy + b[3] <= fs - 1.5 {
                    edPut(sl, pre + edP2(k), f[0] + rsx, f[1] + rsy).
                } ELSE { edOff(sl). }
            }
        }
    }
    // the boxes the labels keep clear of: the bug's, then each symbol's as it is placed
    SET edLbOb TO LIST(LIST(vx - 10, vx + 10, vy - 10, vy + 10)).
    // the deadband: the two lines off the vehicle, overbright while the site is outside it (the reversal); overbright,
    // they flash in ENTRY TRAJ's phase, with its bug: lit in its bug's lit half and blank in the dark one
    LOCAL dj IS ROUND(MAX(0, MIN(edGeo["db"][1], db)) / edGeo["db"][0]).
    LOCAL dc IS CHOOSE "o" IF ABS(daz) > db ELSE "m".
    LOCAL dn IS (dj * 5):TOSTRING.
    UNTIL dn:LENGTH >= 3 { SET dn TO "0" + dn. }
    SET edDbA TO CHOOSE LIST() IF dc = "m" ELSE LIST("dbl" + dn + dc, "dbr" + dn + dc, f[0] + vx, f[1] + vy).
    IF dc = "m" OR inp[24] {
        edPut(edS["db0"], "dbl" + dn + dc, f[0] + vx, f[1] + vy).
        edPut(edS["db1"], "dbr" + dn + dc, f[0] + vx, f[1] + vy).
    } ELSE {
        edOff(edS["db0"]).
        edOff(edS["db1"]).
    }
    // the target's runway and its name. RWY_HEADING is from the site's north and the page is track-up about the
    // vehicle: the symbol's angle is the bearing out (gc[1]) less the track, plus the heading off the great circle's
    // arrival (the site's back bearing + 180) stretched across the radial by c / SIN(c), as the page's map is (c the
    // arc; 0.001 deg worst against the projected runway, within 2000 NM). RWY_HEADING less the track alone is 180 deg
    // off once the track swings over a pole while the site stays put on the page
    LOCAL gbk IS edGc(inp[7], inp[8], lat, lng, br).
    LOCAL gcc IS gc[0] / br.
    LOCAL gph IS inp[29] - gbk[1] - 180.
    LOCAL rh IS MOD(ROUND((gc[1] - trk + ARCTAN2(gcc / MAX(SIN(gcc / TG_D2R), 0.01) * SIN(gph), COS(gph))) / 10) * 10
        + 1440, 360).
    // the site at its rings' whole px (it stepped on other draws than they), the HAC and the alternates at whole
    // px off it: the ground's symbols step together
    LOCAL rwOk IS edPutIn(edS["rwy"], "rwy" + edP3(rh), rsx, rsy).
    IF rwOk { edLbOb:ADD(LIST(rsx - 6, rsx + 6, rsy - 6, rsy + 6)). }
    // the HAC centre the DELAZ aims at (250 / 100 NM steps)
    LOCAL hon IS inp[25].
    IF hon AND zm <= 250 {
        LOCAL hg IS edGc(lat, lng, inp[26], inp[27], br).
        LOCAL ha IS hg[1] - trk.
        LOCAL hx IS rsx + ROUND(vx + hg[0] / 1852 * ppn * SIN(ha) - sx).
        LOCAL hy IS rsy + ROUND(vy - hg[0] / 1852 * ppn * COS(ha) - sy).
        IF edPutIn(edS["hac"], "hacx", hx, hy) { edLbOb:ADD(LIST(hx - 5, hx + 5, hy - 5, hy + 5)). }
    } ELSE { edOff(edS["hac"]). }
    // the alternates (edNear: edTick's search). One within ED_MERGE_PX of one shown before (nearer the vehicle)
    // joins that one's label ("DOV/LGA", ED_MERGE_N names at most) and its own goes off; its circle stays
    LOCAL ap IS LIST().                      // the labels: LIST(x, y, slot, names, count, the key, the first's name)
    FROM { LOCAL i IS 0. } UNTIL i >= ED_ALT_N STEP { SET i TO i + 1. } DO {
        LOCAL al IS edAl[i].
        LOCAL ok IS FALSE.
        IF i < edNear:LENGTH {
            LOCAL it IS edNear[i].
            LOCAL ag IS edGc(lat, lng, it[1], it[2], br).
            LOCAL aa IS ag[1] - trk.
            LOCAL x IS rsx + ROUND(vx + ag[0] / 1852 * ppn * SIN(aa) - sx).
            LOCAL y IS rsy + ROUND(vy - ag[0] / 1852 * ppn * COS(aa) - sy).
            IF x >= 6 AND x <= fs - 6 AND y >= 6 AND y <= fs - 6 {
                SET ok TO edPutIn(al[0], "alt", x, y).
            }
            IF ok {
                edLbOb:ADD(LIST(x - 4, x + 4, y - 4, y + 4)).
                LOCAL nm IS it[0]:SUBSTRING(0, MIN(3, it[0]:LENGTH)).
                LOCAL j IS -1.
                FROM { LOCAL k IS 0. } UNTIL k >= ap:LENGTH OR j >= 0 STEP { SET k TO k + 1. } DO {
                    LOCAL ddx IS ap[k][0] - x.
                    LOCAL ddy IS ap[k][1] - y.
                    IF ap[k][4] < ED_MERGE_N AND ddx * ddx + ddy * ddy <= ED_MERGE_PX * ED_MERGE_PX { SET j TO k. }
                }
                IF j >= 0 {
                    SET ap[j][3] TO ap[j][3] + "/" + nm.
                    SET ap[j][4] TO ap[j][4] + 1.
                    edOff(al[1]).
                } ELSE { ap:ADD(LIST(x, y, al[1], nm, 1, nm)). }
            }
        }
        IF NOT ok { edOff(al[0]). edOff(al[1]). }
    }
    // the predictor: PRED_N circles on the track the guidance's bank and alpha fly on the reference drag (edPredPath)
    LOCAL dr IS inp[12].
    LOCAL pn IS edGeo["pred"][0].
    LOCAL np IS 0.
    IF dr > 0.3 AND spd > ED_VT + 10 AND NOT inp[32] {   // no predictor dots in pre-entry
        LOCAL pt IS edPredPath(spd, dr, inp[13] / dr, bk, inp[15], edGeo["pred"][1] * fs / ppn * 1852).
        LOCAL tt IS pt[0].
        LOCAL tl IS tt[tt:LENGTH - 1].
        LOCAL ta IS pt[3].
        LOCAL ka IS pn.                      // the dots even in time to tk, the rest on the path's end
        LOCAL tk IS tl.
        IF ta > 0 AND ta < tl AND pn > 1 { SET ka TO pn - 1. SET tk TO ta. }   // the last but one on the turn's cap
        LOCAL j IS 1.
        FROM { LOCAL i IS 1. } UNTIL i > pn STEP { SET i TO i + 1. } DO {
            LOCAL ti IS MIN(tl, CHOOSE tk * i / ka IF i <= ka ELSE tl).
            LOCAL sl IS edS["p" + i].
            IF ti <= tl {
                UNTIL tt[j] >= ti { SET j TO j + 1. }
                LOCAL g IS (ti - tt[j - 1]) / MAX(tt[j] - tt[j - 1], 0.001).
                LOCAL x IS vx + (pt[1][j - 1] + (pt[1][j] - pt[1][j - 1]) * g) / 1852 * ppn.
                LOCAL y IS vy - (pt[2][j - 1] + (pt[2][j] - pt[2][j - 1]) * g) / 1852 * ppn.
                IF x >= 6 AND x <= fs - 6 AND y >= 6 AND y <= fs - 6 {
                    IF edPutIn(sl, "pred", x, y) { edLbOb:ADD(LIST(x - 4, x + 4, y - 4, y + 4, 1)). }   // soft (edLbHold)
                } ELSE { edOff(sl). }
            } ELSE { edOff(sl). }
            SET np TO i.
        }
    }
    FROM { LOCAL i IS np + 1. } UNTIL i > pn STEP { SET i TO i + 1. } DO { edOff(edS["p" + i]). }
    // the labels in priority (after the predictor: its dots are boxes too, the DB lines a line test): the
    // target's runway name, the alternates' (nearest first), the rings' (sliding along the ring out from its lower
    // left, each beside a piece shown), the DB's
    SET edLbDb TO LIST(vx, vy, TAN(dj * edGeo["db"][0])).
    SET edLbOld TO CHOOSE edLbMem IF zm = edLbZm ELSE LEXICON().
    SET edLbNw TO LEXICON().
    SET edLbRq TO LIST().
    IF rwOk { edLbPut(edS["lrw"], inp[30], rsx, rsy, ED_LB_RW, "rw"). } ELSE { edOff(edS["lrw"]). }
    FOR lb IN ap { edLbPut(lb[2], lb[3], lb[0], lb[1], ED_LB_AL, "a" + lb[5]). }
    LOCAL lsl IS LIST(edS["lr1"], edS["lr2"], edS["ltm"]).
    LOCAL lt IS LIST("" + ROUND(edGeo["ring_f"][0] * zm), "" + ROUND(edGeo["ring_f"][1] * zm), "TAEM").
    LOCAL rr IS LIST(edGeo["ring_f"][0] * ah, edGeo["ring_f"][1] * ah, edGeo["taem"][0] * ppn).
    FROM { LOCAL g IS 0. } UNTIL g >= 3 STEP { SET g TO g + 1. } DO {
        LOCAL bb IS CHOOSE edTmB["" + zm] IF g = 2 ELSE edRgB[g].
        LOCAL n IS bb:LENGTH.
        LOCAL cs IS LIST().                  // the spots beside a piece shown, id the try j
        FROM { LOCAL j IS 0. } UNTIL j >= ED_RG_TRY OR n = 0 STEP { SET j TO j + 1. } DO {
            LOCAL am IS 240 + ED_RG_DA * (CHOOSE j / 2 IF MOD(j, 2) = 0 ELSE -(j + 1) / 2).
            LOCAL k IS MIN(n - 1, FLOOR(MOD(am, 360) * n / 360)).
            IF edRg[g][k][5] {
                LOCAL ca IS COS(am).
                LOCAL la IS 2.
                IF ca < -0.3 { SET la TO 1. } ELSE IF ca > 0.3 { SET la TO 0. }
                cs:ADD(LIST(rsx + (rr[g] + 8) * ca, rsy - (rr[g] + 8) * SIN(am), la, j)).
            }
        }
        edLbAdd(lsl[g], lt[g], cs, "r" + g).
    }
    LOCAL tb IS TAN(db).
    LOCAL dbs IS "DB " + edF1(db).
    edLbAdd(edS["ldb"], dbs, LIST(LIST(vx + 70 * tb + 6, vy - 70, 0, 0), LIST(vx - 70 * tb - 6, vy - 70, 1, 1),
        LIST(vx + 100 * tb + 6, vy - 100, 0, 2)), "db").
    edLbRun(f).                              // the labels placed together
    SET edLbMem TO edLbNw.
    SET edLbZm TO zm.
    edPut(edS["bug"], "bug", f[0] + vx, f[1] + vy).   // the orbiter bug, heading 000 (track-up)
    // the texts
    LOCAL mt IS inp[14].
    LOCAL dd IS FLOOR(mt / 86400).
    LOCAL ds IS dd:TOSTRING.
    UNTIL ds:LENGTH >= 3 { SET ds TO "0" + ds. }
    LOCAL m0 IS edGeo["met"].
    edText(edS["met"], ds + "/" + edP2(FLOOR(MOD(mt, 86400) / 3600)) + ":" + edP2(FLOOR(MOD(mt, 3600) / 60)) + ":"
           + edP2(FLOOR(MOD(mt, 60))), m0[0], m0[1], 2).
    edText(edS["trk"], "TRK " + edP3(trk), edGeo["trk"][0], edGeo["trk"][1], 2).
    edText(edS["zm"], zm + " NM", edGeo["zoomlab"][0], edGeo["zoomlab"][1], 0).
    LOCAL lv IS edGeo["lval"].
    LOCAL hs IS "".
    IF hon { SET hs TO (CHOOSE "L" IF inp[28] < 0 ELSE "R") + " OVHD". }
    LOCAL rows IS LIST(inp[30], hs, "" + ROUND(rgo / 1852), "" + ROUND(ABS(rnm * SIN(a))), edS1(daz), edP3(trk)).
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
        edText(edS["l" + i], rows[i], lv[0], lv[1] + i * lv[2], 1).
    }
    LOCAL alf IS inp[15].
    LOCAL be IS inp[16].
    LOCAL gb IS inp[18].
    LOCAL ga IS inp[19].
    LOCAL ad IS edGeo["adi"].
    // SW 02 GUIDANCE LOST (ENTRY): the guidance's bank and alpha rows and the two error bars show "----" / off (the C#
    // draw does the same from edCsIn's 34th item)
    LOCAL gl IS FALSE.
    IF DEFINED FLFX_SWPROG { SET gl TO flfxSwGuid("ENTRY"). }
    LOCAL av IS LIST(edLR(bk, "L", "R"), edLR(inp[17], "U", "D"), edLR(be, "L", "R"),
                     CHOOSE "----" IF gl ELSE edLR(gb, "L", "R"), CHOOSE "----" IF gl ELSE edLR(ga, "U", "D"), edLR(0, "L", "R")).
    LOCAL ak IS LIST("aR", "aP", "aY", "gR", "gP", "gY").
    FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
        edText(edS[ak[i]], av[i], ad[0] + MOD(i, 3) * ad[1], CHOOSE ad[2] IF i < 3 ELSE ad[3], 1).
    }
    // the bars: RATE (deg/s, + = right roll / nose up / nose right) with the DAP's command; ERROR fly-to:
    // each pointer on the side to steer toward, + = roll right / pitch up / yaw right
    LOCAL wr IS LIST(inp[20], inp[21], inp[22]).
    LOCAL rk IS LIST("rp", "rq", "rr").
    LOCAL wc IS inp[23].
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
        edBar(edS["t" + rk[i]], "tri", rk[i], wr[i]).
        IF wc:ISTYPE("List") { edBar(edS["c" + rk[i]], "arr", rk[i], wc[i]). } ELSE { edOff(edS["c" + rk[i]]). }
    }
    IF gl {
        edOff(edS["teb"]).
        edOff(edS["tea"]).
    } ELSE {
        edBar(edS["teb"], "tri", "eb", bk - gb).    // + = the guidance's bank is right of the bank (the bank's + is LEFT)
        edBar(edS["tea"], "tri", "ea", ga - alf).   // + = the guidance's alpha is above the alpha
    }
    edBar(edS["tey"], "tri", "ey", be).         // + = the velocity is right of the nose (beta's +)
}

// ---- the C# page (see the globals' note at the top)
FUNCTION edCsOff {                           // any failure: kOS draws from now on, for the flight
    PARAMETER why.
    SET ED_CS_ERR TO why.
    SET ED_CS_STATE TO "kOS (" + why + ")".
    SET edCsOn TO FALSE.
    SET ED_CS TO FALSE.
}

// ---- the painter (see ED_PAINT at the top)
FUNCTION edPaintGroups {                   // LIST(LIST(name, page box, LIST(LIST(label, flow index) ...), the page box's child count))
    RETURN LIST(LIST("ED", edBox, edOrd, CHOOSE edMkK IF ED_NEST ELSE edMkN)).   // edBox's children: the nests (or the slots)
}

FUNCTION edPaintPh {                       // a placeholder: the page box's LAST child, a 1 x 1 box + an empty 1 x 1 label
    PARAMETER pg, fl.                       //   (shown: its draw is where C# paints the page, after every slot box)
    LOCAL bx IS pg:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // An empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 1. SET m:STYLE:HEIGHT TO 1.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:MARGIN:H TO 0. SET m:STYLE:MARGIN:V TO 0.
    RETURN LIST(m, fl, pg).
}

FUNCTION edPaintSetup {                    // edInit's end (after every slot): ED_PAINT 0 = nothing created
    SET edPaintReg TO FALSE.
    edPaintNames:CLEAR().
    IF ED_PAINT = 0 { SET ED_PAINT_STATE TO "OFF". RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        FOR gp IN edPaintGroups() {
            IF why = "" {
                LOCAL er IS ADDONS:KALS:PAINTREG(gp[0], edPaintPh(gp[1], gp[3]), gp[2]).
                IF er = "" { edPaintNames:ADD(gp[0]). SET er TO ADDONS:KALS:PAINTMODE(gp[0], ED_PAINT). }
                IF er <> "" { SET why TO gp[0] + ": " + er. }
            }
        }
    }
    IF why <> "" { edPaintOff(why). RETURN. }
    SET edPaintReg TO TRUE.
    SET ED_PAINT_STATE TO edPaintName(ED_PAINT).
}

FUNCTION edPaintName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
}

// the mode switched live (the test harness's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a ED_PAINT > 0 edInit
FUNCTION edPaintSet {
    PARAMETER m.
    IF NOT edPaintReg { RETURN "not registered (ED_PAINT was 0 at edInit, or it failed: " + ED_PAINT_STATE + ")". }
    FOR gn IN edPaintNames {
        LOCAL er IS ADDONS:KALS:PAINTMODE(gn, m).
        IF er <> "" { edPaintOff(gn + ": " + er). RETURN er. }
    }
    SET ED_PAINT TO m.
    SET ED_PAINT_STATE TO edPaintName(m).
    RETURN "".
}

FUNCTION edPaintOff {                      // any failure: kOS draws from now on (C# showed the boxes, or never hid them)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") {
        FOR gn IN edPaintNames { ADDONS:KALS:PAINTMODE(gn, 0). }
    } }
    SET ED_PAINT_STATE TO "OFF (" + why + ")".
    SET ED_PAINT TO 0.
    SET edPaintReg TO FALSE.
}

FUNCTION edCsSetup {                         // edInit's end: the slots and tables to the addon
    SET edCsOn TO FALSE.
    IF NOT ED_CS {
        IF ED_CS_ERR = "" { SET ED_CS_STATE TO "kOS (ED_CS off)". }
        RETURN.
    }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("EDDRAW") { SET why TO "the KAL/S addon has no entry page (an older DLL)". }
    ELSE {
        LOCAL er IS ADDONS:KALS:EDSETUP().
        IF er <> "" { SET why TO "EDSETUP: " + er. }
    }
    IF why <> "" {
        edCsOff(why).
        RETURN.
    }
    SET edCsOn TO TRUE.
    SET ED_CS_STATE TO "C#".
}

FUNCTION edCsDraw {                          // TRUE: C# drew this draw; FALSE: kOS draws it (a failure)
    PARAMETER inp.
    LOCAL ops IS ADDONS:KALS:EDDRAW(inp).
    IF ops:ISTYPE("String") {                // nothing was written: kOS draws this draw
        edCsOff("EDDRAW: " + ops).
        RETURN FALSE.
    }
    tdCsApply(ops).                          // lib_taemdisp's (the same widget codes)
    RETURN TRUE.
}

FUNCTION edRateArm {                         // after a C# draw on the host's call: the redraw trigger, armed once
    IF edTrig OR ED_DT_CS <= 0 { RETURN. }
    IF NOT edBox:VISIBLE { RETURN. }
    SET edTrig TO TRUE.
    WHEN uiRt() >= edNx THEN { RETURN edRedraw(). }   // real time
}

FUNCTION edRedraw {                          // the trigger's body: one redraw between the calls; FALSE ends the trigger
    LOCAL go IS edOn AND edCsOn AND ED_CS AND ED_DT_CS > 0.
    IF go { SET go TO edBox:VISIBLE AND edArgs:LENGTH = 3 AND TIME:SECONDS - edArgT <= ED_CS_STALE. }
    IF NOT go {
        SET edTrig TO FALSE.                 // the next C# draw on a call arms it again
        RETURN FALSE.
    }
    IF edBusy { RETURN TRUE. }               // the call is drawing: the next tick
    IF NOT gpcLive("BOT") { RETURN TRUE. }   // Its GPC failed: no redraw
    SET edNx TO CHOOSE 0 IF ED_RD_TICK ELSE (FLOOR((uiRt() + 0.005) / ED_DT_CS) + 1) * ED_DT_CS - 0.005.
    SET edBusy TO TRUE.
    IF edCsDraw(edCsIn(edArgs[0], edArgs[1], edArgs[2])) { SET ED_CS_NRD TO ED_CS_NRD + 1. }
    SET edBusy TO FALSE.
    RETURN TRUE.
}
