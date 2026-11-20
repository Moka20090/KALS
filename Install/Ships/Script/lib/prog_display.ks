// ==========================================================================================
//  PROG_DISPLAY.KS -- progress displays for DEORBIT PLAN and FAMILY BUILD
// ==========================================================================================
//  The deorbit plan pages (FULL and COARSE, with a log box under them) and the family-build page. Loaded with
//  RUNONCEPATH("0:/lib/prog_display.ks") by the deorbit planner and the family build.
//  Same construction as traj_display: a generated PNG behind a GUI box, live values placed over it with STYLE:MARGIN,
//  geometry read from a sidecar. The sidecar (0:/prog_bg.txt) and the page PNGs it names come from gen_prog_bg.py;
//  the backgrounds are static, and only the family bar's tick spacing (from the bank schedule) depends on the family.
//  Plan: progLogStart, progInit, progShowPlan, then progRowAdd / progRowSet / progStatus / progLog and progPlanSolve /
//  progPlanStep / progPlanVals / progCoarseVals / progPlanDone as the planner runs, then progWaitStop or progWaitClose.
//  Family: progInit, progShowFam, progFamUpdate / progFamMember as members complete, progWaitClose.
// ==========================================================================================

// The sidecar path; PROG_ON FALSE switches the displays off (progInit then returns FALSE).
GLOBAL PROG_SIDE IS "0:/prog_bg.txt".
GLOBAL PROG_ON IS TRUE.

// SINK MODE: ops2q's DEORB TGT page sets PG_SINK TRUE (lib_o2dorb's o2dbSolve) and PG_SINK_FN to a delegate taking
// (kind, n) before the planner runs: no window is built or shown (progInit returns TRUE with PG_OK FALSE, so every page call
// below is a no-op), the log lines still go to the log file and to pgLog (the caller reads the outcome there) and nowhere
// else, a burn solve's progress goes to the delegate ("solve" = a solve starts, "step" = step n of 4 is done), and
// progWaitStop returns FALSE at once (the caller has its own NEXT PASS).
GLOBAL PG_SINK IS FALSE.
GLOBAL PG_SINK_FN IS 0.
FUNCTION pgSink {
    PARAMETER kind, n.
    IF PG_SINK_FN:HASSUFFIX("CALL") { PG_SINK_FN:CALL(kind, n). }   // a delegate (0 = none)
}

// Display state: the parsed sidecar (PG_D); ready flag and reason (PG_OK, PG_WHY); the GUI and its image box; the
// page shown (pgPage: "plan", "coarse" or "fam"); the CLOSE button.
RUNONCEPATH("0:/lib/lib_logsw.ks").   // SOCK_LOG: the log box keeps its file only when the logs are on
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
RUNONCEPATH("0:/lib/lib_guistyle.ks").   // the window's frame in the panel look (uiDispSkin)
GLOBAL PG_D IS LEXICON().
GLOBAL PG_OK IS FALSE.
GLOBAL PG_WHY IS "".
GLOBAL pgGui IS 0.
GLOBAL pgBox IS 0.
GLOBAL pgShown IS FALSE.
GLOBAL pgChildN IS 0.
GLOBAL pgPage IS "".
GLOBAL pgBtn IS 0.

// The page's reference width in px: the font, sprite and label sizes below are for this width and are scaled by
// png_w / PG_REF_W (pgS).
GLOBAL PG_REF_W IS 1104.0.
// A live value's top margin is its row y - PG_ROW_OFF - PG_FLOW_PX * its child index in the image box. Both numbers
// were measured on a screenshot at 736 px wide: the GUI's accumulated flow for child idx is about PG_ROW_OFF +
// PG_FLOW_PX * idx. The rows come from figure coordinates, so the constant part is explicit. Re-measure both if the
// font, the slot count or the scale changes: put a value on a known row, screenshot it, and read off the difference.
GLOBAL PG_ROW_OFF IS 164.2.      // px at 736 wide: the constant part of the flow
GLOBAL PG_FLOW_PX IS 0.96.       // px per child
// Font size of the live values (scaled by pgS in progInit); it follows the size of the labels baked into the page
// PNGs (14 pt, about 11 px).
GLOBAL PG_FONT IS 23.
// The pointer sprite (19 x 18 px, pointing up): its apex is at row 0, so the triangle hangs below the bar with its
// point on the spine. PG_PTR_TIPX is the tip's x as a fraction of the width (column 9.5 of 19); PG_IMG_DY is a
// vertical offset in px that pgPutPtr subtracts from the pointer's margin.
GLOBAL PG_PTR_W IS 28.5.         // px: the drawn width at PG_REF_W (19 px after the scale at 736 wide)
GLOBAL PG_PTR_TIPX IS 9.5 / 19.0.
GLOBAL PG_IMG_DY IS 2.7.

// GUI image names are bare filenames, with no "0:/" prefix: kOS resolves them relative to the script's own volume,
// so a "0:/..." path is read as a parent-directory reference and throws.
GLOBAL PG_PTR_IMG IS "prog_ptr.png".

// The page PNG names, filled in from the sidecar by progInit. kOS caches a GUI image by path for as long as the game
// runs, so a page overwritten in place keeps showing the first texture. The generator stamps each name over the
// constants that affect the drawing: a changed layout gets a different filename, an unchanged one keeps its own.
GLOBAL PG_PLAN_BG IS "".
GLOBAL PG_COARSE_BG IS "".
GLOBAL PG_LOG_BG IS "".
GLOBAL PG_FAM_BG IS "".

// Text colours of the live values (rich-text hex).
GLOBAL PG_GREEN IS "#3ce03c".
GLOBAL PG_YELLOW IS "#f0d840".
// Sentinel for a value not computed yet: any real FPA is negative but far above it, and dv and TIG are positive.
GLOBAL PG_UNSET IS -99999.

// pgS: the page scale (png_w / PG_REF_W). pgVals: LIST(child index, label) per value slot. pgPtr: the bar pointer,
// pgPtrI: its child index.
GLOBAL pgS IS 1.0.
GLOBAL pgVals IS LIST().
GLOBAL pgPtr IS 0.
GLOBAL pgPtrI IS 0.

// Value slots (pgVals): 0-7 the family's arcs, 8-14 the left column's values (14: COARSE's table note), 15 the status
// line, then from PG_LIST0 the list: list_rows lines of five cells, the newest in view. The log is its own box under
// the page.
GLOBAL PG_SLOTS IS 56.
GLOBAL PG_LIST0 IS 16.
GLOBAL pgRows IS LIST().         // the list: LIST(5 texts, 5 colours) per burn solve, oldest first
GLOBAL pgRowMiss IS LIST().      // FULL: the misses of the newest line, km
// The log box and its row labels; the log file; the zero of the run's clock (UT s); the NEXT PASS button; the page and
// log box heights in px.
GLOBAL pgLogBox IS 0.
GLOBAL pgLogLab IS LIST().
GLOBAL pgLog IS LIST().          // the log: LIST(line, colour), oldest first; the box shows the newest
GLOBAL pgLogFile IS "".
GLOBAL pgLogT0 IS 0.
GLOBAL pgNext IS 0.
GLOBAL pgH IS 0.
GLOBAL pgLogH IS 0.

// Text t wrapped in a rich-text colour tag.
FUNCTION pgCol { PARAMETER t, c. RETURN "<color=" + c + ">" + t + "</color>". }

// The per-child part of the flow offset for child number idx, in px.
FUNCTION pgFlow { PARAMETER idx. RETURN idx * PG_FLOW_PX. }

// Adds a text label of the given width and alignment to the parent and returns it. The 1x1 VLAYOUT wrapper is the
// structure traj_display's tjText uses and the flow constants were measured against: a label built directly on the
// box changes how the layout flows and puts the values on the wrong rows.
FUNCTION pgText {
    PARAMETER parent, wide, algn IS "right".
    LOCAL bx IS parent:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO wide.
    SET m:STYLE:ALIGN TO algn.
    SET m:STYLE:FONTSIZE TO PG_FONT.
    SET m:STYLE:RICHTEXT TO TRUE.
    SET pgChildN TO pgChildN + 1.
    RETURN m.
}

// Adds an image label of the given width to the parent and returns it.
FUNCTION pgImg {
    PARAMETER parent, wide, img.
    LOCAL m IS parent:ADDLABEL("").
    SET m:IMAGE TO img.
    SET m:STYLE:WIDTH TO wide.
    SET m:STYLE:HEIGHT TO 0.
    SET pgChildN TO pgChildN + 1.
    RETURN m.
}

// ---- sidecar ---------------------------------------------------------------------------
// The numbers in a space-separated string, as a list (a non-number reads as 0).
FUNCTION pgNums {
    PARAMETER line.
    LOCAL out IS LIST().
    FOR t IN line:SPLIT(" ") { IF t:LENGTH > 0 { out:ADD(t:TONUMBER(0)). } }
    RETURN out.
}

// Reads the sidecar, builds the GUI (hidden) and checks that the page files exist. Returns FALSE, with the reason in
// PG_WHY, when the display cannot be built (disabled, no sidecar, a key missing, a page file missing).
FUNCTION progInit {
    IF NOT PROG_ON { SET PG_WHY TO "disabled". RETURN FALSE. }
    IF PG_SINK { SET PG_OK TO FALSE. SET pgShown TO FALSE. SET PG_WHY TO "sink". RETURN TRUE. }   // no window; the planner goes on as with a page
    IF NOT EXISTS(PROG_SIDE) {
        SET PG_WHY TO "no " + PROG_SIDE + " -- reinstall it and its pages from the release".
        kmSay("PROG: " + PG_WHY, "C").
        RETURN FALSE.
    }
    SET PG_D TO LEXICON().
    // The sidecar is "key value" lines; lines starting with # are skipped. Drive the iterator with NEXT / VALUE: a FOR
    // over :READALL:ITERATOR fails at runtime (FOR asks its subject for an :ITERATOR suffix; an iterator has none).
    LOCAL it IS OPEN(PROG_SIDE):READALL:ITERATOR.
    UNTIL NOT it:NEXT {
        LOCAL s IS it:VALUE:TRIM.
        IF s:LENGTH > 0 AND s[0] <> "#" {
            LOCAL i IS s:FIND(" ").
            IF i > 0 { SET PG_D[s:SUBSTRING(0, i)] TO s:SUBSTRING(i + 1, s:LENGTH - i - 1). }
        }
    }
    // Refuse a sidecar missing any key: without fam_order the family ticks are in bank order, and the pointer would sit
    // on the wrong segment all through the build.
    FOR k IN LIST("png_w", "png_h", "bar_px", "fam_ticks", "plan_ticks", "coarse_ticks", "fam_order",
                  "fam_rrows", "fam_lrows", "plan_lrows", "coarse_lrows", "coarse_note",
                  "list_rows", "list_status", "plan_cols", "coarse_cols",
                  "log_h", "log_top", "log_rows", "log_row_px", "log_x",
                  "plan_png", "coarse_png", "log_png", "fam_png", "stamp") {
        IF NOT PG_D:HASKEY(k) {
            SET PG_WHY TO "sidecar has no " + k + " -- regenerate it".
            kmSay("PROG: " + PG_WHY, "C").
            RETURN FALSE.
        }
    }
    LOCAL w IS PG_D["png_w"]:TONUMBER(0).
    LOCAL h IS PG_D["png_h"]:TONUMBER(0).
    SET PG_PLAN_BG TO PG_D["plan_png"].
    SET PG_COARSE_BG TO PG_D["coarse_png"].
    SET PG_LOG_BG TO PG_D["log_png"].
    SET PG_FAM_BG TO PG_D["fam_png"].
    SET pgH TO ROUND(h).
    SET pgLogH TO ROUND(PG_D["log_h"]:TONUMBER(0)).
    SET pgS TO w / PG_REF_W.
    SET PG_FONT TO ROUND(PG_FONT * pgS).

    SET pgGui TO GUI(ROUND(w)).    // exactly the page's width (was + 24)
    uiDispSkin(pgGui).               // the window and CLOSE / NEXT PASS in the panel look (its padding, the page's
                                     //   place and its labels as before: PG_ROW_OFF holds)
    SET pgGui:STYLE:PADDING:H TO 0.  // The kOS default side padding left the window narrower than the page box (the page overhung
                                     //   the right edge: a gap on the left only); 0 = the other display windows' (vertical padding stays: PG_ROW_OFF)
    SET pgGui:STYLE:HEIGHT TO ROUND(h) + 48.
    SET pgBox TO pgGui:ADDVLAYOUT().
    SET pgBox:STYLE:WIDTH TO ROUND(w).
    SET pgBox:STYLE:HEIGHT TO ROUND(h).

    SET pgChildN TO 0.
    SET pgPtrI TO pgChildN.
    SET pgPtr TO pgImg(pgBox, ROUND(PG_PTR_W * pgS), PG_PTR_IMG).

    // PG_SLOTS value labels in the image box, 300 px wide at PG_REF_W; each slot records its child index for pgFlow.
    SET pgVals TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= PG_SLOTS STEP { SET i TO i + 1. } DO {
        pgVals:ADD(LIST(pgChildN, pgText(pgBox, ROUND(300 * pgS), "right"))).
    }
    // The log box under the page: its own background (log_png: the frame and the heading) with log_rows fixed rows over
    // it, the newest at the bottom. An ordinary flow with every row log_row_px tall, so the slot arithmetic above does
    // not apply. Shown with the plan pages only: progShowPlan grows the window by its height, progShowFam takes it back.
    SET pgLogBox TO pgGui:ADDVLAYOUT().
    SET pgLogBox:STYLE:WIDTH TO ROUND(w).
    SET pgLogBox:STYLE:HEIGHT TO pgLogH.
    pgLogBox:ADDSPACING(PG_D["log_top"]:TONUMBER(0)).
    LOCAL lx IS PG_D["log_x"]:TONUMBER(0).
    SET pgLogLab TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= PG_D["log_rows"]:TONUMBER(0) STEP { SET i TO i + 1. } DO {
        LOCAL m IS pgLogBox:ADDLABEL("").
        SET m:STYLE:FONTSIZE TO ROUND(PG_FONT * 0.85).
        SET m:STYLE:RICHTEXT TO TRUE.
        SET m:STYLE:WORDWRAP TO FALSE.
        SET m:STYLE:ALIGN TO "left".
        SET m:STYLE:WIDTH TO ROUND(w - 2 * lx).
        SET m:STYLE:HEIGHT TO PG_D["log_row_px"]:TONUMBER(0).
        SET m:STYLE:MARGIN:V TO 0.
        SET m:STYLE:PADDING:V TO 0.
        SET m:STYLE:MARGIN:LEFT TO lx.
        pgLogLab:ADD(m).
    }
    pgLogBox:HIDE().
    // The buttons go in their own layout below the image box, not inside it: every child of the box is a flow element,
    // and PG_ROW_OFF / PG_FLOW_PX were measured against the children that are there. The window is png_h + 48 tall for
    // a png_h box, so the strip below the page is already reserved.
    LOCAL bar IS pgGui:ADDHLAYOUT().
    SET pgBtn TO bar:ADDBUTTON("CLOSE").
    SET pgBtn:STYLE:WIDTH TO ROUND(120 * pgS).
    SET pgBtn:STYLE:FONTSIZE TO PG_FONT.
    // THE STOP's second button, shown only while progWaitStop waits.
    SET pgNext TO bar:ADDBUTTON("NEXT PASS").
    SET pgNext:STYLE:WIDTH TO ROUND(200 * pgS).
    SET pgNext:STYLE:FONTSIZE TO PG_FONT.
    pgNext:HIDE().

    // The sidecar names the page files; if a copy step missed one, the box would have no background, so report it.
    LOCAL missing IS LIST().
    FOR f IN LIST(PG_PLAN_BG, PG_COARSE_BG, PG_LOG_BG, PG_FAM_BG, PG_PTR_IMG) {
        IF NOT EXISTS("0:/" + f) { missing:ADD(f). }
    }
    IF missing:LENGTH > 0 {
        kmSay("*** PROG: " + missing:LENGTH + " page/sprite file(s) missing: " + missing:JOIN(", ") + ". The sidecar names them, so this is a copy step that did not finish.", "C").
        SET PG_WHY TO "missing page files".
        RETURN FALSE.
    }

    SET PG_OK TO TRUE.
    RETURN TRUE.
}

// Blocks until CLOSE is pressed, then hides the page, so the next program cannot replace it unread. TAKEPRESS is
// polled rather than using an ONCLICK delegate: no closure over local state, and it cannot fire while the script is
// inside a solve that does not yield. Returns at once if the display never came up.
FUNCTION progWaitClose {
    IF NOT PG_OK OR NOT pgShown { RETURN. }
    UNTIL pgBtn:TAKEPRESS { WAIT 0.1. }
    progHide().
}

// ---- placement -------------------------------------------------------------------------
// Puts the bar pointer at fraction frac (0..1) along the bar; the sidecar's bar_px is the bar's left x, right x and y.
FUNCTION pgPutPtr {
    PARAMETER frac.
    IF NOT PG_OK { RETURN. }
    LOCAL b IS pgNums(PG_D["bar_px"]).
    LOCAL x IS b[0] + MIN(MAX(frac, 0), 1) * (b[1] - b[0]).
    LOCAL pw IS PG_PTR_W * pgS.
    // Horizontally on the tip's own column, not the sprite's centre.
    SET pgPtr:STYLE:MARGIN:H TO x - pw * PG_PTR_TIPX.
    // Vertically the apex is row 0, so the sprite starts AT the bar and hangs below it.
    SET pgPtr:STYLE:MARGIN:V TO b[2] - PG_IMG_DY - pgFlow(pgPtrI).
}

// Puts txt in value slot `slot`, right-aligned, its right edge at xRight, on the row at yRow (px).
FUNCTION pgPut {
    PARAMETER slot, xRight, yRow, txt.
    pgPutA(slot, xRight, "right", ROUND(300 * pgS), yRow, txt).
}

// The same with the alignment and the width given: x = the right edge ("right") or the left edge ("left").
FUNCTION pgPutA {
    PARAMETER slot, x, algn, wide, yRow, txt.
    IF NOT PG_OK OR slot >= pgVals:LENGTH { RETURN. }
    LOCAL e IS pgVals[slot].
    SET e[1]:TEXT TO txt.
    SET e[1]:STYLE:ALIGN TO algn.
    SET e[1]:STYLE:WIDTH TO wide.
    IF algn = "right" { SET e[1]:STYLE:MARGIN:H TO x - wide. }
    ELSE { SET e[1]:STYLE:MARGIN:H TO x. }
    SET e[1]:STYLE:MARGIN:V TO yRow - PG_ROW_OFF - pgFlow(e[0]).
}

// Blanks every value slot.
FUNCTION pgClearAll {
    IF NOT PG_OK { RETURN. }
    FOR e IN pgVals { SET e[1]:TEXT TO "". }
}

// Hides the window.
FUNCTION progHide {
    IF PG_OK AND pgShown { pgGui:HIDE(). SET pgShown TO FALSE. }
}

// ---- deorbit plan ----------------------------------------------------------------------
// Shows the FULL (default) or COARSE plan page and the log box under it, with an empty list. Returns FALSE if the
// display is not up.
FUNCTION progShowPlan {
    PARAMETER coarse IS FALSE.
    IF NOT PG_OK { RETURN FALSE. }
    IF coarse {
        SET pgBox:STYLE:BG TO PG_COARSE_BG.
        SET pgPage TO "coarse".
    } ELSE {
        SET pgBox:STYLE:BG TO PG_PLAN_BG.
        SET pgPage TO "plan".
    }
    pgClearAll().
    SET pgRows TO LIST().
    SET pgRowMiss TO LIST().
    pgPutPtr(0).
    // the log box under the page, and the window grown to hold it
    SET pgLogBox:STYLE:BG TO PG_LOG_BG.
    pgLogBox:SHOW().
    pgLogDraw().
    SET pgGui:STYLE:HEIGHT TO pgH + pgLogH + 56.
    pgGui:SHOW().
    SET pgShown TO TRUE.
    RETURN TRUE.
}

// Restarts the bar for each burn solve; the caller adds the solve's list line (progRowAdd).
FUNCTION progPlanSolve {
    IF PG_SINK { pgSink("solve", 0). RETURN. }
    IF NOT PG_OK { RETURN. }
    pgPutPtr(0).
}

// Moves the bar to the end of solve step n, which just finished, and shows tSec (seconds) as the left column's first
// value. The display can only advance between steps: dpSolve does not yield, so nothing repaints while a step runs.
// FULL also adds the step's miss (missKm) to the newest list line.
FUNCTION progPlanStep {
    // The parameter is tSec, not `note`: `note` is a kOS builtin, and as a parameter name it is a CLOBBERBUILTINS error
    // at parse time, so the whole script refuses to load.
    PARAMETER n, missKm, tSec.
    IF PG_SINK { IF n >= 1 { pgSink("step", n). } RETURN. }
    IF NOT PG_OK OR NOT (pgPage = "plan" OR pgPage = "coarse") { RETURN. }
    LOCAL tk IS pgNums(PG_D[pgPage + "_ticks"]).
    IF pgPage = "coarse" {
        // TABLE | SOLVE (NO ENTRIES): the probe closes the first, each verify the second
        IF n = 1 { pgPutPtr(tk[1]). }
        IF n = 4 { pgPutPtr(tk[2]). }
    } ELSE {
        IF n >= 1 AND n < tk:LENGTH { pgPutPtr(tk[n]). }
        // FULL's list line: the probe's miss, then each verify's, growing
        IF (n = 1 OR n = 4) AND pgRows:LENGTH > 0 AND ABS(missKm) < 900000 {
            pgRowMiss:ADD(missKm).
            progRowSet(pgRows:LENGTH - 1, 3, pgMissTxt()).
        }
    }
    LOCAL lr IS pgNums(PG_D[pgPage + "_lrows"]).
    pgPut(8, PG_D["plan_lval_px"]:TONUMBER(0), lr[0], pgCol("" + ROUND(tSec), PG_GREEN)).
}

// Shows FPA, dv and TIG in the left column, each as soon as it is known. Pass PG_UNSET for any that is not yet known:
// its row stays blank. Call it as often as needed; the rows fill in independently. tigUT is a UT, shown as hh:mm:ss.
FUNCTION progPlanVals {
    PARAMETER fpa, dv, tigUT.
    IF NOT PG_OK OR NOT (pgPage = "plan" OR pgPage = "coarse") { RETURN. }
    LOCAL lr IS pgNums(PG_D[pgPage + "_lrows"]).
    LOCAL xv IS PG_D["plan_lval_px"]:TONUMBER(0).
    IF fpa > PG_UNSET { pgPut(9,  xv, lr[1], pgCol("" + ROUND(fpa, 3), PG_GREEN)). }
    IF dv > PG_UNSET  { pgPut(10, xv, lr[2], pgCol("" + ROUND(dv, 2), PG_GREEN)). }
    IF tigUT > PG_UNSET { pgPut(11, xv, lr[3], pgCol(pgClock(tigUT), PG_GREEN)). }
}

// Shows the final FPA, dv and TIG (as progPlanVals) and moves the bar to its end.
FUNCTION progPlanDone {
    PARAMETER fpa, dv, tigUT.
    progPlanVals(fpa, dv, tigUT).
    pgPutPtr(1).
}

// COARSE's left column under FPA / DV / TIG: the parking orbit's mean altitude (the table's argument), its D_ENT, and
// the table's note under them (an altitude outside the table flies its end row).
FUNCTION progCoarseVals {
    PARAMETER hKm, dentKm, txt.
    IF NOT PG_OK OR pgPage <> "coarse" { RETURN. }
    LOCAL lr IS pgNums(PG_D["coarse_lrows"]).
    LOCAL xv IS PG_D["plan_lval_px"]:TONUMBER(0).
    pgPut(12, xv, lr[4], pgCol("" + ROUND(hKm, 1), PG_GREEN)).
    pgPut(13, xv, lr[5], pgCol("" + ROUND(dentKm), PG_GREEN)).
    LOCAL nt IS pgNums(PG_D["coarse_note"]).
    pgPutA(14, nt[0], "left", ROUND(300 * pgS), nt[1], pgCol(txt, PG_YELLOW)).
}

// ---- the list: one line per burn solve ----------------------------------------------------
// FULL: # / PASS / PLAN / MISS km / RESULT; COARSE: PASS / PLAN / BURN IN / CROSS / RESULT. The columns come from the
// sidecar as triples: x, 1 = right-aligned at x (0 = left from x), the width. The newest list_rows lines stay in view.
// progRowAdd adds a line from the five cell texts (all green at first) and returns its index; progRowSet changes
// one cell.
FUNCTION progRowAdd {
    PARAMETER cells.
    LOCAL cl IS LIST().
    FOR c IN cells { cl:ADD(PG_GREEN). }
    pgRows:ADD(LIST(cells:COPY, cl)).
    SET pgRowMiss TO LIST().
    pgRowsDraw().
    RETURN pgRows:LENGTH - 1.
}

// Sets cell c of list line i to txt, in colour colr.
FUNCTION progRowSet {
    PARAMETER i, c, txt, colr IS PG_GREEN.
    IF i < 0 OR i >= pgRows:LENGTH { RETURN. }
    SET pgRows[i][0][c] TO txt.
    SET pgRows[i][1][c] TO colr.
    pgRowsDraw().
}

// Draws the newest list_rows lines into the list slots.
FUNCTION pgRowsDraw {
    IF NOT PG_OK OR NOT (pgPage = "plan" OR pgPage = "coarse") { RETURN. }
    LOCAL rr IS pgNums(PG_D["list_rows"]).
    LOCAL cs IS pgNums(PG_D[pgPage + "_cols"]).
    LOCAL k0 IS MAX(0, pgRows:LENGTH - rr:LENGTH).
    FROM { LOCAL ri IS 0. } UNTIL ri >= rr:LENGTH STEP { SET ri TO ri + 1. } DO {
        FROM { LOCAL c IS 0. } UNTIL c >= 5 STEP { SET c TO c + 1. } DO {
            LOCAL txt IS "".
            IF k0 + ri < pgRows:LENGTH { SET txt TO pgCol(pgRows[k0 + ri][0][c], pgRows[k0 + ri][1][c]). }
            LOCAL algn IS "left".
            IF cs[3 * c + 1] = 1 { SET algn TO "right". }
            pgPutA(PG_LIST0 + 5 * ri + c, cs[3 * c], algn, cs[3 * c + 2], rr[ri], txt).
        }
    }
}

// FULL's MISS km cell: every miss while three fit, else the first, "..", the last two; whole km from 10 up.
FUNCTION pgMissTxt {
    LOCAL s IS LIST().
    FOR m IN pgRowMiss {
        IF ABS(m) >= 10 { s:ADD("" + ROUND(m)). } ELSE { s:ADD("" + ROUND(m, 1)). }
    }
    IF s:LENGTH > 3 { RETURN s[0] + " .. " + s[s:LENGTH - 2] + " " + s[s:LENGTH - 1]. }
    LOCAL t IS "".
    FOR x IN s {
        IF t:LENGTH > 0 { SET t TO t + " ". }
        SET t TO t + x.
    }
    RETURN t.
}

FUNCTION progStatus {                       // the line under the list: the STOP, the plan written
    PARAMETER txt, colr IS PG_GREEN.
    IF NOT PG_OK OR NOT (pgPage = "plan" OR pgPage = "coarse") { RETURN. }
    LOCAL st IS pgNums(PG_D["list_status"]).
    pgPutA(15, st[0], "left", st[2], st[1], pgCol(txt, colr)).
}

// ---- the log -------------------------------------------------------------------------------
// The log box under the page, and a copy of each kept line in the log file. Each line carries the run's clock (seconds
// from t0). keep FALSE = a placeholder that a progLogSet replaces ("checking the reach ..."): shown, not filed.
// Without the page the kept lines go to the console. progLogStart names the log file (deleted first if it exists) and
// t0, the UT of the clock's zero.
FUNCTION progLogStart {
    PARAMETER fPath, t0.
    SET pgLogFile TO CHOOSE fPath IF SOCK_LOG ELSE "".   // the logs off (lib_logsw): the box only
    SET pgLogT0 TO t0.
    SET pgLog TO LIST().
    IF pgLogFile <> "" AND EXISTS(fPath) { DELETEPATH(fPath). }
}

// Adds a line to the box and, if keep, to the file; with no page up, a kept line is printed.
FUNCTION progLog {
    PARAMETER txt, colr IS PG_GREEN, keep IS TRUE.
    LOCAL ts IS "" + ROUND(TIME:SECONDS - pgLogT0) + " S".
    LOCAL lineTxt IS ts:PADLEFT(6) + "  " + txt.
    IF keep AND pgLogFile:LENGTH > 0 { LOG lineTxt TO pgLogFile. }
    IF PG_SINK {                             // the file and pgLog only (no console line, no box)
        pgLog:ADD(LIST(lineTxt, colr)).
    } ELSE IF PG_OK AND pgShown AND pgPage <> "fam" {
        pgLog:ADD(LIST(lineTxt, colr)).
        pgLogDraw().
    } ELSE IF keep {
        PRINT lineTxt.
    }
}

// Like progLog, but replaces the box's last line (a placeholder) instead of adding one.
FUNCTION progLogSet {
    PARAMETER txt, colr IS PG_GREEN.
    IF (PG_SINK OR (PG_OK AND pgShown AND pgPage <> "fam")) AND pgLog:LENGTH > 0 { pgLog:REMOVE(pgLog:LENGTH - 1). }
    progLog(txt, colr).
}

// Draws the newest log lines into the box's rows.
FUNCTION pgLogDraw {
    LOCAL n IS pgLogLab:LENGTH.
    LOCAL k0 IS MAX(0, pgLog:LENGTH - n).
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        IF k0 + i < pgLog:LENGTH { SET pgLogLab[i]:TEXT TO pgCol(pgLog[k0 + i][0], pgLog[k0 + i][1]). }
        ELSE { SET pgLogLab[i]:TEXT TO "". }
    }
}

// THE STOP: blocks on the page's two buttons. Returns TRUE on NEXT PASS (the page stays up and the planner tries the
// next pass) and FALSE on CLOSE (the page is hidden). Returns FALSE at once without a page.
FUNCTION progWaitStop {
    IF PG_SINK OR NOT PG_OK OR NOT pgShown { RETURN FALSE. }
    pgNext:SHOW().
    LOCAL go IS FALSE.
    UNTIL FALSE {
        IF pgNext:TAKEPRESS { SET go TO TRUE. BREAK. }
        IF pgBtn:TAKEPRESS { BREAK. }
        WAIT 0.1.
    }
    pgNext:HIDE().
    IF NOT go {
        progHide().
    }
    RETURN go.
}

// ---- family build ----------------------------------------------------------------------
// Shows the family-build page, with the bar at its start and no log box. Returns FALSE if the display is not up.
FUNCTION progShowFam {
    IF NOT PG_OK { RETURN FALSE. }
    SET pgBox:STYLE:BG TO PG_FAM_BG.
    SET pgPage TO "fam".
    pgClearAll().
    pgPutPtr(0).
    pgLogBox:HIDE().
    pgNext:HIDE().
    SET pgGui:STYLE:HEIGHT TO pgH + 48.
    pgGui:SHOW().
    SET pgShown TO TRUE.
    RETURN TRUE.
}

// Updates the page for member mi (its position in the build order): the bar goes by trace sample count (`samples` is
// EPR_TR_V:LENGTH so far; fam_work in the sidecar is the count the member is expected to need), then the left column
// shows the elapsed time, the time to go, vEI, tEI and vInit. Velocity is a poor progress measure (not monotone early,
// much faster late): a velocity-driven pointer would stall, twitch backwards, then bolt.
FUNCTION progFamUpdate {
    PARAMETER mi, samples, tEl, vEI, tEI, vInit, doneCount IS -1.
    // doneCount is unused: the parameter stays so callers that pass it still work. TGO uses f.
    IF NOT PG_OK OR pgPage <> "fam" { RETURN. }
    LOCAL tk IS pgNums(PG_D["fam_ticks"]).
    LOCAL wk IS pgNums(PG_D["fam_work"]).
    LOCAL f IS 0.
    LOCAL within IS 0.
    IF mi >= 0 AND mi < wk:LENGTH {
        SET within TO MIN(1, MAX(0, samples / MAX(wk[mi], 1))).
        SET f TO tk[mi] + within * (tk[mi + 1] - tk[mi]).
    }
    pgPutPtr(f).

    LOCAL lr IS pgNums(PG_D["fam_lrows"]).
    LOCAL xv IS PG_D["fam_lval_px"]:TONUMBER(0).
    // TGO = tEl * (1 - f) / f once f exceeds 0.02 (else 0), with f the fraction done: valid because the build is
    // deterministic (eight members, a known step budget). The bar is in build order, so its position is that fraction,
    // weighted by each member's real sample count; `mi` is EPR_FAM_I, a position in the build sequence, not a bank index.
    LOCAL tgo IS 0.
    IF f > 0.02 { SET tgo TO tEl * (1 - f) / f. }
    pgPut(8,  xv, lr[0], pgCol("" + ROUND(tEl), PG_GREEN)).
    pgPut(9,  xv, lr[1], pgCol("" + ROUND(tgo), PG_GREEN)).
    pgPut(10, xv, lr[2], pgCol("" + ROUND(vEI), PG_GREEN)).
    pgPut(11, xv, lr[3], pgCol("" + ROUND(tEI), PG_GREEN)).
    pgPut(12, xv, lr[4], pgCol("" + ROUND(vInit), PG_GREEN)).
}

// Shows member mi's arc length (km) in the right column as it completes. Eight arcs in a column make a non-monotone
// member or a collapsed spread visible while the build runs.
FUNCTION progFamMember {
    PARAMETER mi, arcKm.
    IF NOT PG_OK OR pgPage <> "fam" { RETURN. }
    LOCAL rr IS pgNums(PG_D["fam_rrows"]).
    IF mi < 0 OR mi >= rr:LENGTH { RETURN. }
    pgPut(mi, PG_D["fam_rval_px"]:TONUMBER(0), rr[mi],
          pgCol("" + ROUND(arcKm), PG_GREEN)).
}

// A time in seconds as hh:mm:ss (negative reads as 0; the hours do not wrap).
FUNCTION pgClock {
    PARAMETER ut.
    LOCAL t IS MAX(0, ut).
    LOCAL h IS FLOOR(t / 3600).
    LOCAL m IS FLOOR((t - h * 3600) / 60).
    LOCAL sec IS FLOOR(t - h * 3600 - m * 60).
    LOCAL hs IS "" + h. IF h < 10 { SET hs TO "0" + hs. }
    LOCAL ms IS "" + m. IF m < 10 { SET ms TO "0" + ms. }
    LOCAL ss IS "" + sec. IF sec < 10 { SET ss TO "0" + ss. }
    RETURN hs + ":" + ms + ":" + ss.
}
