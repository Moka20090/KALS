// ============================================================================
//  TRAJ_DISPLAY.KS  --  the ENTRY TRAJ panels, live
// ============================================================================
//  Called by the entry program (ops3q): trajInit(), trajShow(), trajHide(), trajClose(), trajUpdate(...).
//  kOS cannot draw lines, so each panel's guided lines, drag ladder, scales and fixed text are a PNG drawn offline from
//  family.txt (traj1..5.png, plus the sidecar traj_bg.txt) and shown as the plot box's STYLE:BG. Only the symbols and
//  the readout values are live. The KAL/S addon draws the same panels and sidecar itself (ADDONS:KALS:TJBG, TJ_BG_CS
//  below), so no python watcher has to run.
//  The sidecar owns all geometry (field bounds, zoom factors, panel bands, strip scales); nothing here re-derives it.
//  A marker is a zero-size VLAYOUT holding a label whose IMAGE is the sprite, moved by STYLE:MARGIN:H and
//  :MARGIN:V in pixels from the plot box's top-left (the pattern of entry_range_display.ks).

// entry_predict.ks defines EPR_AERO_VER, EPR_GUID_DRAG_INIT and eprTrajBankRange (RUNONCEPATH loads it only once).
RUNONCEPATH("0:/lib/entry_predict.ks").
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
RUNONCEPATH("0:/lib/lib_gpc.ks").                // gpcLive (a window whose GPC failed is not redrawn)
RUNONCEPATH("0:/lib/lib_guistyle.ks").      // the window's frame in the panel look (uiDispSkin ...)
// The page is the deck's top window (lib_taemdisp tdDeckOpen: VERT SIT's, with its button row, HORIZ SIT's docked under
// it): one GUI, its pages swapped; at TAEM / GRTLS tdInit swaps VERT SIT's page into the same window. TJ_DECK FALSE (or
// no lib_taemdisp): its own window.
IF NOT (DEFINED TJ_DECK) { GLOBAL TJ_DECK IS TRUE. }
IF TJ_DECK AND EXISTS("0:/lib/lib_taemdisp.ks") { RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_taemdisp.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_taemdisp.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_taemdisp.ks"). }
GLOBAL tjDeckOn IS FALSE.                  // this page is in the deck's window

// TJ_SIDE: the sidecar file. TJ_ON: FALSE turns the display off (trajInit then returns FALSE).
GLOBAL TJ_SIDE IS "0:/traj_bg.txt".
GLOBAL TJ_ON IS TRUE.
// TJ_BG_CS (default TRUE): trajInit has the KAL/S addon draw the panels from TJ_BG_FAM (TJBG: a worker thread,
// the offline drawing ported to C#, its sidecar numbers identical; the PNGs into traj_cs/, named by the family's
// written stamp so kOS's image cache never shows an old one) and shows them, when TJ_SIDE is the watcher's own sidecar
// (TJ_BG_WATCH: the deorbit entry; OPS 6 sets its own), so nothing but KSP has to run. On ANY failure (no addon, an
// older DLL, no family file, no answer in TJ_BG_TICKS physics ticks, a refused sidecar) it turns itself off for the
// flight and the watcher's files are used; TJ_BG_STATE says which (trajInit appends it to TJ_CS_STATE, which the
// callers' "TRAJ display armed" event line names; TJ_WHY carries it when no sidecar is usable).
// Paths are relative to the archive (Ships/Script); the template is a static asset made offline.
IF NOT (DEFINED TJ_BG_CS) { GLOBAL TJ_BG_CS IS TRUE. }
GLOBAL TJ_BG_WATCH IS "0:/traj_bg.txt".
GLOBAL TJ_BG_FAM IS "family.txt".
GLOBAL TJ_BG_SIDE IS "traj_cs/traj_bg.txt".
GLOBAL TJ_BG_TPL IS "traj_tpl/tpl_0.667.bin".
GLOBAL TJ_BG_TICKS IS 250.     // physics ticks trajInit waits for the drawing (~0.2 s needed; 5 s at 50 Hz)
GLOBAL TJ_BG_STATE IS "watcher (not asked)".
GLOBAL TJ_BG_ERR IS "".
// TJ_BANK_RANGE: the box's range (m) for a bank (deg) at a speed (m/s), called as TJ_BANK_RANGE:CALL(bank, vrel); OPS 6
// points it at the generic TAL lines (lib_tal talGenBankRange@). TJ_BUG_ON: FALSE hides the bug, the box and the crumbs
// (OPS 6 until its live family is in). The defaults are the nominal's: eprTrajBankRange and the bug on.
GLOBAL TJ_BANK_RANGE IS tjFamBank@.       // eprTrajBankRange, in C# while the C# page runs
GLOBAL TJ_BUG_ON IS TRUE.

// sprite files in Ships/Script, made with the backgrounds; TJ_EMPTY is a blank image that hides a marker
GLOBAL TJ_BUG_IMG   IS "orbiter_bug.png".
GLOBAL TJ_BOX_IMG   IS "traj_pred_bug.png".
GLOBAL TJ_TRAIL_IMG IS "traj_trail_bug.png".
GLOBAL TJ_DOT_IMG   IS "box_dot.png".
GLOBAL TJ_DARR_IMG  IS "drag_arrow.png".
GLOBAL TJ_DTRI_IMG  IS "drag_tri.png".
GLOBAL TJ_AARR_IMG  IS "aoa_arrow.png".
GLOBAL TJ_ATRI_IMG  IS "aoa_tri.png".
GLOBAL TJ_EMPTY     IS "empty.png".

// The sizes below are drawn sizes in px at a render 1104 px wide (TJ_REF_W), not the sprite files' own sizes.
// trajInit scales them by png_w / TJ_REF_W, so the symbols keep their proportions at any render size.
// Regenerate the sprite PNGs at the same scale to keep them crisp.
GLOBAL TJ_REF_W   IS 1104.0.
GLOBAL tjS        IS 1.0.        // set from the sidecar in trajInit
// widths (px): the orbiter bug, the predicted-bank box, a bug-trail crumb and a box-trail dot
GLOBAL TJ_BUG_W   IS 26.
GLOBAL TJ_BOX_W   IS 14.
GLOBAL TJ_TRAIL_W IS 16.
GLOBAL TJ_DOT_W   IS 5.
// widths (px) of the strip arrow (commanded or reference value) and triangle (actual value); the sprites are
// cropped to their ink, so a width is the drawn width
GLOBAL TJ_ARR_W   IS 34.
GLOBAL TJ_TRI_W   IS 23.
// A strip marker's tip, not the middle of its sprite, points at the value. TJ_ARR_TIPF and TJ_TRI_TIPF give the tip's
// row as a fraction of the sprite height, so they survive a scale change. They are calibrated on screen, not derived
// from the sprite polygon, because they include kOS's own offset in placing a label: re-measure them if the sprites
// change size. TJ_ARR_H and TJ_TRI_H are the sprite heights in px at the reference render.
GLOBAL TJ_ARR_TIPF IS 8.0 / 13.0.
GLOBAL TJ_TRI_TIPF IS 8.0 / 17.0.
GLOBAL TJ_ARR_H   IS 19.5.   // 13 px at 0.667, so the scaled value is the sprite exactly
GLOBAL TJ_TRI_H   IS 25.5.   // 17 px at 0.667

// The orbiter bug's nose carries the position (2.4). The sprite is 38x25 px and its nose is at (0.000, 0.229) of its
// box, so the image is lifted by its height * (1 - 0.229). Derived from the width, so a size change keeps the anchor.
GLOBAL TJ_BUG_OFF_X IS 0.
GLOBAL TJ_BUG_OFF_Y IS -(TJ_BUG_W * (25.0/38.0) * 0.771).
// px every sprite keeps inside the field: a sprite shows only when it is wholly inside the box it lives in (the bug's
// nose 2 px)
GLOBAL TJ_FIT_IN IS 2.

// crumbs kept in each of the two trails (orbiter bug and predicted-bank box)
GLOBAL TJ_TRAIL_N IS 5.
// Seconds between crumbs: a time, not a cycle count, so the spacing does not depend on the loop rate. The orbiter's
// display drops one every 29 s (2.13); the shorter entries here use 20.
GLOBAL TJ_TRAIL_S IS 20.
// on panels TJ_TRAIL_V_LO .. TJ_TRAIL_V_HI (ENTRY TRAJ 2 and 3, which a TAL and some normal entries fly through
// in well under TJ_TRAIL_S x TJ_TRAIL_N) the crumbs drop by VELOCITY, not by time: the page's velocity span (vhi - vlo)
// is cut into TJ_TRAIL_V_N equal steps and the first draw in each step drops its crumb, so the 5 drops fall at 0, 20,
// 40, 60 and 80 % of the span below the page's top (vhi); the 5th step runs on to vlo. Every other panel keeps TJ_TRAIL_S.
GLOBAL TJ_TRAIL_V_LO IS 2.
GLOBAL TJ_TRAIL_V_HI IS 3.
GLOBAL TJ_TRAIL_V_N IS 5.

// ---- sidecar ---------------------------------------------------------------------------
GLOBAL TJ_D IS LEXICON().     // header
GLOBAL TJ_P IS LIST().        // per panel: LIST(n, vhi, vlo, x0km, x1km, arrestV, png,
                              //                aLo, aHi, dLo, dHi)  -- 11 elements.
                              //   Strip scales are per panel: read them with trajAlphaScale / trajDragScale,
                              //   never by index at the call site.
// TJ_OK: TRUE once a sidecar has been read and accepted. TJ_WHY: the reason it was refused.
GLOBAL TJ_OK IS FALSE.
// px: the band's pad inside the field's top and bottom (the sidecar's v_pad_px: the bug's height and a little), so
// the bug clears the 14 px offscale inset at a panel switch and stays on screen; 0 for a sidecar without the line (the
// band edge to edge)
GLOBAL tjVPad IS 0.
GLOBAL TJ_WHY IS "".

// Reads the sidecar into TJ_D (the key lines) and TJ_P (one entry per panel); returns FALSE, with TJ_WHY set, if it is
// unusable. Lines: "key value", "key v1 v2 ..." (numbers; vessel is text), and per panel
// "P n vhi vlo x0km x1km arrestV png aLo aHi dLo dHi"; a line starting with # is a comment. Keys read: version, vessel,
// aero_ver, png_w, png_h, field_px, strip_a, strip_d, tl_rows, tl_right, br_rows, br_right, clock_px.
FUNCTION trajReadSide {
    SET TJ_OK TO FALSE.
    SET TJ_WHY TO "".
    SET TJ_D TO LEXICON().
    SET TJ_P TO LIST().
    IF NOT EXISTS(TJ_SIDE) {
        SET TJ_WHY TO "traj_bg.txt not found".
        RETURN FALSE.
    }
    LOCAL it IS OPEN(TJ_SIDE):READALL:ITERATOR.
    UNTIL NOT it:NEXT {
        LOCAL raw IS it:VALUE:TRIM.
        IF raw:LENGTH > 0 AND raw[0] <> "#" {
            LOCAL pp IS raw:SPLIT(" ").
            IF pp[0] = "P" {
                // exactly 12 tokens: a short line would be indexed past its end, and a space in the filename (pp[7])
                // would shift the scales read after it, which TONUMBER(0) turns into 0 with no error
                IF pp:LENGTH <> 12 {
                    SET TJ_WHY TO "traj_bg.txt: a panel line has " + pp:LENGTH
                                  + " fields, not 12".
                    RETURN FALSE.
                }
                LOCAL aL IS pp[8]:TONUMBER(0).  LOCAL aH IS pp[9]:TONUMBER(0).
                LOCAL dL IS pp[10]:TONUMBER(0). LOCAL dH IS pp[11]:TONUMBER(0).
                IF aH - aL <= 0 OR dH - dL <= 0 {
                    SET TJ_WHY TO "traj_bg.txt: panel " + pp[1] + " has an invalid strip scale".
                    RETURN FALSE.
                }
                TJ_P:ADD(LIST(pp[1]:TONUMBER(0), pp[2]:TONUMBER(0), pp[3]:TONUMBER(0),
                              pp[4]:TONUMBER(0), pp[5]:TONUMBER(0), pp[6]:TONUMBER(0), pp[7],
                              aL, aH, dL, dH)).
            } ELSE IF pp:LENGTH = 2 {
                IF pp[0] = "vessel" { SET TJ_D[pp[0]] TO pp[1]. }
                ELSE { SET TJ_D[pp[0]] TO pp[1]:TONUMBER(0). }
            } ELSE IF pp:LENGTH > 2 {
                IF pp[0] = "vessel" {
                    LOCAL sv IS pp[1]. LOCAL j IS 2.
                    UNTIL j >= pp:LENGTH { SET sv TO sv + " " + pp[j]. SET j TO j + 1. }
                    SET TJ_D[pp[0]] TO sv.
                } ELSE {
                    LOCAL vals IS LIST(). LOCAL j IS 1.
                    UNTIL j >= pp:LENGTH { vals:ADD(pp[j]:TONUMBER(0)). SET j TO j + 1. }
                    SET TJ_D[pp[0]] TO vals.
                }
            }
        }
    }
    IF NOT TJ_D:HASKEY("field_px") OR TJ_D["field_px"]:LENGTH <> 4 {
        SET TJ_WHY TO "traj_bg.txt has no field size (field_px)". RETURN FALSE.
    }
    IF TJ_P:LENGTH < 1 { SET TJ_WHY TO "traj_bg.txt lists no panels". RETURN FALSE. }
    // scale_a / scale_d are the keys of the one-scale format; version 2 puts the strip scales on the P lines.
    // Refuse the one-scale format rather than guess a scale.
    IF TJ_D:HASKEY("scale_a") OR TJ_D:HASKEY("scale_d") {
        SET TJ_WHY TO "traj_bg.txt is in the old one-scale format".
        RETURN FALSE.
    }
    // Two separate checks, so no message reads a version key that may be missing (a missing LEXICON key throws,
    // and kOS has no try/catch). A garbled version value reads as 0 and is refused as "version 0".
    IF NOT TJ_D:HASKEY("version") {
        SET TJ_WHY TO "traj_bg.txt has no version line".
        RETURN FALSE.
    }
    IF TJ_D["version"] < 2 {
        SET TJ_WHY TO "traj_bg.txt is version " + TJ_D["version"] + ", not 2".
        RETURN FALSE.
    }
    // refuse panels drawn for another vessel or another aero model: they look right and are wrong
    IF TJ_D:HASKEY("vessel") AND TJ_D["vessel"] <> SHIP:NAME {
        SET TJ_WHY TO "Panels drawn for " + TJ_D["vessel"]. RETURN FALSE.
    }
    IF TJ_D:HASKEY("aero_ver") AND ABS(TJ_D["aero_ver"] - EPR_AERO_VER) > 0.001 {
        SET TJ_WHY TO "Panels drawn for aero model " + TJ_D["aero_ver"] + ", not " + EPR_AERO_VER. RETURN FALSE.
    }
    SET tjVPad TO 0.
    IF TJ_D:HASKEY("v_pad_px") { SET tjVPad TO TJ_D["v_pad_px"]. }
    SET TJ_OK TO TRUE.
    RETURN TRUE.
}

// ---- geometry --------------------------------------------------------------------------
// The panel whose velocity band (vhi down to vlo) holds vrel; above the first band the first panel, otherwise the last.
FUNCTION trajPanelFor {
    PARAMETER vrel.
    LOCAL best IS TJ_P[0].
    FOR p IN TJ_P {
        IF vrel <= p[1] AND vrel >= p[2] { RETURN p. }
        IF vrel > p[1] { SET best TO p. }
    }
    IF vrel > TJ_P[0][1] { RETURN TJ_P[0]. }
    RETURN TJ_P[TJ_P:LENGTH - 1].
}

// The velocity step (1 .. TJ_TRAIL_V_N) of vrel on a velocity-keyed panel p: 0 above the page's top, 1 in its first
// 1 / TJ_TRAIL_V_N of the span, ... TJ_TRAIL_V_N from the last fifth on (to vlo and below).
FUNCTION trajTrailStep {
    PARAMETER p, vrel.
    LOCAL k IS FLOOR((p[1] - vrel) / ((p[1] - p[2]) / TJ_TRAIL_V_N)) + 1.
    IF k < 0 { RETURN 0. }
    IF k > TJ_TRAIL_V_N { RETURN TJ_TRAIL_V_N. }
    RETURN k.
}

// Range (km) and velocity (m/s) to pixels in the plot field, clamped to it. Range grows rightward and velocity
// downward; MARGIN:V is measured from the top, so vhi maps to 0.
FUNCTION trajPx {
    PARAMETER p, rngKm, vrel.
    LOCAL fx IS TJ_D["field_px"].
    LOCAL xn IS (rngKm - p[3]) / MAX(0.001, p[4] - p[3]).
    LOCAL yn IS (tjVPad + (p[1] - vrel) / MAX(0.001, p[1] - p[2]) * (fx[3] - 2 * tjVPad)) / MAX(0.001, fx[3]).
    IF xn < 0 { SET xn TO 0. }
    IF xn > 1 { SET xn TO 1. }
    IF yn < 0 { SET yn TO 0. }
    IF yn > 1 { SET yn TO 1. }
    RETURN LIST(fx[0] + xn * fx[2], (fx[1] + yn * fx[3]) * TJ_V_SCALE).
}

// ---- a panel's own strip scales --------------------------------------------------------
// A panel's alpha strip scale, LIST(lo, hi) in deg. Read the scales through these functions, not by TJ_P's position:
// the generator skips a panel with no members in its band, so TJ_P[4] is not necessarily panel 5.
FUNCTION trajAlphaScale {
    PARAMETER p.
    RETURN LIST(p[7], p[8]).
}

// A panel's drag strip scale, LIST(lo, hi) in ft/s^2
FUNCTION trajDragScale {
    PARAMETER p.
    RETURN LIST(p[9], p[10]).
}

// a strip marker's vertical pixel, from a value on that strip's scale
FUNCTION trajStripPx {
    PARAMETER val, lo, hi, topPx, botPx.
    LOCAL f IS (val - lo) / MAX(0.001, hi - lo).
    IF f < 0 { SET f TO 0. }
    IF f > 1 { SET f TO 1. }
    RETURN (botPx - f * (botPx - topPx)) * TJ_V_SCALE.
}

// ---- the GUI ---------------------------------------------------------------------------
GLOBAL tjGui IS 0.
GLOBAL tjBox IS 0.
GLOBAL tjXBox IS 0.                         // The big X's box (gui_panel/gpc_x), a sibling of tjBox, shown in its place while the top window's GPC is dead
GLOBAL tjXOn IS FALSE.                      // The X look is on (tjGpcX)
GLOBAL tjPanel IS 0.          // the panel LIST currently shown, 0 before the first update
GLOBAL tjTrail IS LIST().     // crumb positions, data units: LIST(rngKm, vrel)
GLOBAL tjBoxTrail IS LIST().
// update counter (a guidance cycle's draw)
GLOBAL tjCycle IS 0.
// the draw counter, its parity the flash phase (every flash at 5 Hz): every draw steps it (the guidance cycle's and, C#
// live, the redraws' every TJ_DT_CS): lit one draw, dark the next, 5 Hz at 10 Hz and even at any draw timing; kOS
// drawing (once a cycle) steps it once a cycle, as tjCycle does
GLOBAL tjFlashN IS 0.
// while the C# draws live with its redraws (tjFlashClkNow) tjFlashN is the TJ_DT_CS grid's slot at the draw and the
// redraws run on that grid (tjGridNx), so the guidance cycle's own draw cannot cut a half-period short (an uneven
// flash). kOS drawing steps it at every draw.
GLOBAL tjFlashClk IS FALSE.
GLOBAL tjRtT IS 0.            // the draw's real time (uiRt): the grid's flash, Tj.cs reads it
// called after each C# draw (a delegate, 0 = none): lib_entdisp's DB lines flash in this phase between its ticks
GLOBAL TJ_AFTER IS 0.
GLOBAL tjTrailT IS -999.      // TIME:SECONDS of the last crumb
// An update writes only what changed: the crumb sprites move only when a crumb is added or the panel changes,
// the corner rows' margins are set once, and their text is rewritten only when it differs from the last write.
GLOBAL tjTrailDirty IS TRUE.  // the crumbs' sprites need placing
GLOBAL tjRowsPlaced IS FALSE. // the corner rows' margins are set
// the last text written to each top-left (5) and lower-right (9) readout row
GLOBAL tjTLtxt IS LIST("", "", "", "", "").
GLOBAL tjBRtxt IS LIST("", "", "", "", "", "", "", "", "").

// MARGIN is added to the layout's flow position, and each 1 px marker box still advances the VLAYOUT by about
// TJ_FLOW_PX (px), so the Nth child starts N * TJ_FLOW_PX down. Each widget records its child index and subtracts
// that. Measured: change TJ_FLOW_PX if a kOS version spaces children differently.
GLOBAL TJ_FLOW_PX IS 1.0.
// Vertical scale between the PNG and how it is drawn: 1.0 with the padding zeroed. If the frame comes out shorter
// than the file, put the measured ratio here and every pixel row from the sidecar follows it.
GLOBAL TJ_V_SCALE IS 1.0.
// px: a label's own vertical anchor inside its box, a constant on every row (the per-row drift is TJ_FLOW_PX).
// Tuned to the sidecar rows, which are the text anchor at draw time, not the glyph centre.
// with the readouts in DejaVu Sans Mono Bold 11 px (TJ_FONT) the text's baseline sits nearer its label's top than
// Arial 13 px's (ascent 0.928 x 11 = 10.2 px vs 0.905 x 13 = 11.8 px): 1.56 px at 736 = 2.35 px at the 1104 reference
// less. ESTIMATED from the fonts' metrics: re-measure on the first screenshot (the baseline on the sidecar's row).
GLOBAL TJ_TEXT_DY IS 18.5 - 2.35.
// px: kOS insets an image inside its label by about this much, the same at every child index (so it is not the flow
// drift). Measured: re-measure if a kOS version changes the padding.
GLOBAL TJ_IMG_DY IS 2.7.
// Font size of the readout values (scaled in trajInit), chosen to match the baked labels: kOS's default is smaller.
// the labels' face and size for the readouts too: the offline TXT_FS 8.5 (TAEM's) = 11 px at 736 = 16.5 at the 1104
// reference (Arial 13 px would be 19)
GLOBAL TJ_FONT IS "DejaVu Sans Mono Bold".   // a monospaced Windows font kOS keeps; an unknown name = kOS's Arial
GLOBAL TJ_TL_FONT IS 16.5.
GLOBAL TJ_BR_FONT IS 16.5.   // matched to the top-left so the two blocks read as one set
// kOS anchors a label by its top edge but the sidecar rows are the text's centre, so a taller glyph needs its row
// lowered by half the growth: (14 - 9) / 2 for a glyph that grows from 9 px to 14 px.
// + 1.5 (1 px at 736): measured in game, the values drew 1 px below their labels without it
GLOBAL TJ_TL_DY IS TJ_TEXT_DY + (14 - 9) / 2 + 1.5.
// the same size and so the same correction as the top-left block
GLOBAL TJ_BR_DY IS TJ_TL_DY.
// the clock: the header's size (the page id's FSZ(10), 13 px at 736) in the readouts' face, on clock_px (the header's
// baseline); 2 px at 736 above the readouts' 11 px row correction, as the larger glyph sits 2 px lower in its label
GLOBAL TJ_CLK_FONT IS 19.5.
GLOBAL TJ_CLK_DY IS TJ_TEXT_DY + (14 - 9) / 2 + 3.
// the child index of the next widget; tjMarker and tjText each count themselves with it
GLOBAL tjChildN IS 0.

// The page's math in C# (all the displays at 10 Hz), in the KAL/S coprocessor (coproc
// Tj.cs / TjKos.cs: ADDONS:KALS:TJSETUP, TJDRAW). kOS keeps the game reads (TIME:SECONDS, the box's TJ_BANK_RANGE call,
// uiDispOn), the state (tjCycle, tjPanel, the crumbs, the readout caches: C# reads them and writes them back) and every
// widget write (TJDRAW returns them, tjCsApply sets them). TJ_CS (default TRUE): C# draws; on ANY failure kOS draws that
// same update and from then on (tjCsOff; TJ_CS_STATE says why). TJ_CS_SKIP (default TRUE): C# drops a write that would set a widget property to the value it set last (the
// page's own "an update writes only what changed", for every property).
IF NOT (DEFINED TJ_CS) { GLOBAL TJ_CS IS TRUE. }
// THE PAINTER (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE; lib_taemdisp's TD_PAINT): ENTRY TRAJ's markers and readouts (group TJ)
// drawn by C# inside kOS's window (each with its own style and content, at the rect kOS's layout gives it), their
// boxes hidden from kOS's layout. TJ_PAINT: 0 OFF (the default until the test harness's CHECK + A/B proof: kOS draws as
// before), 1 CHECK (kOS draws; KSP.log [KalsPaint] worst px), 2 PAINT, 3 AB; live: tjPaintSet(m). Any failure: kOS draws
// (TJ_PAINT_STATE says why).
IF NOT (DEFINED TJ_PAINT) { GLOBAL TJ_PAINT IS 0. }
GLOBAL TJ_PAINT_STATE IS "OFF".
GLOBAL tjPaintReg IS FALSE.
GLOBAL tjPaintNames IS LIST().            // the groups registered
GLOBAL tjOrd IS LIST().                     // the widgets in creation (= kOS's draw) order: LIST(label, flow index)
GLOBAL tjOrd0 IS 0.                         // tjChildN when tjBox was made (the flow indices count from it)
IF NOT (DEFINED TJ_CS_SKIP) { GLOBAL TJ_CS_SKIP IS TRUE. }
GLOBAL tjCsOn IS FALSE.
GLOBAL tjCsKos IS FALSE.      // kOS drew since C# last did (C# then forgets TJ_CS_SKIP's memory)
GLOBAL TJ_CS_ERR IS "".
GLOBAL TJ_CS_STATE IS "kOS (not set up)".
// THE 10 Hz PAGE: with the C# drawing live (tjCsOn, TJ_CS) and the caller's live reads given (TJ_LIVE: a
// delegate returning LIST(vrel, rngM, aAct, bankAct, qbar, altKm, hdot, met), the same expressions its trajUpdate call
// passes), a trigger redraws the page every TJ_DT_CS s between the guidance cycles' trajUpdate calls: those eight new, the
// guidance's values (D REF, the alpha command, ROLL REF, the bank command, CORR, the azimuth error and deadband, U, the
// reversal flag, the trims, Nz: they change once a cycle) and the box's range held from the last cycle. The flash phase
// counts guidance cycles (tjCycle steps only in trajUpdate) and the crumbs are time-based (TJ_TRAIL_S): both keep their
// meaning at any draw rate. kOS drawing (TJ_CS off, a fallback), a hidden page and TJ_LIVE = 0 keep one
// draw per guidance cycle.
GLOBAL TJ_DT_CS IS 0.1.
GLOBAL TJ_LIVE IS 0.
GLOBAL tjArgs IS LIST().      // the last cycle's trajUpdate arguments (the redraws' held values)
GLOBAL tjBxr IS 0.            // the last cycle's box range (m)
GLOBAL tjNext IS 0.           // uiRt of the next redraw (real seconds)
GLOBAL tjBusy IS FALSE.       // trajUpdate is drawing: a redraw waits a tick
GLOBAL tjTrig IS FALSE.       // the redraw trigger is armed
GLOBAL tjShown IS FALSE.      // the window is up (trajShow / trajHide / trajClose)
GLOBAL TJ_CS_NRD IS 0.        // redraws drawn

// px to subtract from a margin for the widget at child index idx (see TJ_FLOW_PX)
FUNCTION tjFlow {
    PARAMETER idx.
    RETURN idx * TJ_FLOW_PX.
}

// An image marker: a 1 x 1 px box holding a label whose IMAGE is img, wide px wide, so MARGIN moves the image
// and the layout does not reflow around it.
FUNCTION tjFits {                           // a square sprite w px wide centred on p wholly inside the field fx
    PARAMETER p, w, fx.                     //   less TJ_FIT_IN
    RETURN p[0] - w / 2 >= fx[0] + TJ_FIT_IN AND p[0] + w / 2 <= fx[0] + fx[2] - TJ_FIT_IN
        AND p[1] - w / 2 >= fx[1] + TJ_FIT_IN AND p[1] + w / 2 <= fx[1] + fx[3] - TJ_FIT_IN.
}

FUNCTION tjMarker {
    PARAMETER parent, img, wide.
    LOCAL bx IS parent:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:IMAGE TO img.
    SET m:STYLE:WIDTH TO wide.
    tjOrd:ADD(LIST(m, tjChildN - tjOrd0)).  // The painter's list
    SET tjChildN TO tjChildN + 1.
    RETURN m.
}

// kOS has no label colour in STYLE, so each value string carries Unity rich-text colour (tjCol): TJ_GREEN for the
// values and title, TJ_YELLOW for the INIT label. The font is the labels' own, TJ_FONT (tjText).
GLOBAL TJ_GREEN IS "#3ce03c".
GLOBAL TJ_YELLOW IS "#f0d840".

// txt wrapped in a rich-text colour tag; col is "#rrggbb"
FUNCTION tjCol {
    PARAMETER txt, col.
    RETURN "<color=" + col + ">" + txt + "</color>".
}

// A text-only readout: a 1 x 1 px box holding a label wide px wide, with font size fsz (0 keeps the default) and
// alignment algn. It never sets IMAGE, so it is separate from tjMarker. The readouts float over the plot field.
FUNCTION tjText {
    PARAMETER parent, wide, fsz IS 0, algn IS "right".
    LOCAL bx IS parent:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO wide.
    SET m:STYLE:ALIGN TO algn.
    IF fsz > 0 { SET m:STYLE:FONTSIZE TO fsz. }
    SET m:STYLE:FONT TO TJ_FONT.            // the labels' face (bold already: no <b>)
    // count this widget, as tjMarker does: the flow compensation needs every widget's index
    tjOrd:ADD(LIST(m, tjChildN - tjOrd0)).  // The painter's list
    SET tjChildN TO tjChildN + 1.
    RETURN m.
}

// Prints the names of any missing sprite files and returns FALSE. A missing image makes a label render empty with
// no error. kOS resolves an IMAGE path against the archive (Ships/Script), not the script's volume.
FUNCTION trajCheckSprites {
    LOCAL miss IS LIST().
    FOR f IN LIST(TJ_BUG_IMG, TJ_BOX_IMG, TJ_TRAIL_IMG, TJ_DOT_IMG,
                  TJ_DARR_IMG, TJ_DTRI_IMG, TJ_AARR_IMG, TJ_ATRI_IMG, TJ_EMPTY) {
        IF NOT EXISTS("0:/" + f) { miss:ADD(f). }
    }
    IF miss:LENGTH > 0 {
        kmSayAt("*** " + miss:LENGTH + " sprite(s) missing: " + miss:JOIN(", ") + ". Invisible until copied into Ships/Script.", "C", 0, 4).
        RETURN FALSE.
    }
    RETURN TRUE.
}

// Reads the sidecar, then builds the window and every widget (hidden; trajShow shows it). Returns FALSE if TJ_ON is
// FALSE or the sidecar is refused (TJ_WHY says why).
FUNCTION trajInit {
    SET tjTrailDirty TO TRUE.         // fresh widgets: place and write everything
    SET tjRowsPlaced TO FALSE.
    SET tjTLtxt TO LIST("", "", "", "", "").
    SET tjBRtxt TO LIST("", "", "", "", "", "", "", "", "").
    IF NOT TJ_ON { RETURN FALSE. }
    tjBgSide().                             // the panels drawn by the addon (TJ_SIDE switched), or why not
    IF NOT trajReadSide() {
        IF TJ_SIDE = TJ_BG_WATCH {
            IF TJ_BG_ERR <> "" { SET TJ_WHY TO TJ_WHY + " (C# panels: " + TJ_BG_ERR + ")". }
            RETURN FALSE.
        }
        IF TJ_BG_STATE:STARTSWITH("C#") {   // the addon's sidecar refused: the watcher's, as before
            tjBgOff("sidecar refused: " + TJ_WHY).
            SET TJ_SIDE TO TJ_BG_WATCH.
            IF NOT trajReadSide() {
                SET TJ_WHY TO TJ_WHY + " (C# panels: " + TJ_BG_ERR + ")".
                RETURN FALSE.
            }
        } ELSE {
            RETURN FALSE.
        }
    }
    // scale the sizes given for the 1104 px reference render to this render (in place, so once per load)
    SET tjS TO TJ_D["png_w"] / TJ_REF_W.
    SET TJ_BUG_W   TO TJ_BUG_W   * tjS.
    SET TJ_BOX_W   TO TJ_BOX_W   * tjS.
    SET TJ_TRAIL_W TO TJ_TRAIL_W * tjS.
    SET TJ_DOT_W   TO MAX(2, TJ_DOT_W * tjS).
    SET TJ_ARR_W   TO TJ_ARR_W   * tjS.
    SET TJ_ARR_H   TO TJ_ARR_H   * tjS.
    SET TJ_TRI_W   TO TJ_TRI_W   * tjS.
    SET TJ_TRI_H   TO TJ_TRI_H   * tjS.
    SET TJ_TL_FONT TO ROUND(TJ_TL_FONT * tjS).
    SET TJ_BR_FONT TO ROUND(TJ_BR_FONT * tjS).
    SET TJ_CLK_FONT TO ROUND(TJ_CLK_FONT * tjS).
    SET TJ_TL_DY   TO TJ_TL_DY   * tjS.
    SET TJ_BR_DY   TO TJ_BR_DY   * tjS.
    SET TJ_CLK_DY  TO TJ_CLK_DY  * tjS.
    SET TJ_BUG_OFF_Y TO TJ_BUG_OFF_Y * tjS.
    // kOS cannot read an image's size, so a sidecar png_w that disagrees with the PNGs stretches the background and
    // every symbol lands proportionally wrong; trajCheckSprites below reports only missing sprite files.
    trajCheckSprites().
    LOCAL fx IS TJ_D["field_px"].
    SET tjDeckOn TO FALSE.
    IF TJ_DECK AND (DEFINED TD_LIB) { SET tjDeckOn TO tdDeckOpen(TJ_D["png_w"], TJ_D["png_h"]). }
    IF tjDeckOn {                           // the deck's top window (its title row and button row are lib_taemdisp's)
        SET tjGui TO tdGuiV.
        GLOBAL tjTitle IS tdTitV.
    } ELSE {
        SET tjGui TO GUI(TJ_D["png_w"]).      // exactly the page's width (was + 24)
        uiDispSkin(tjGui).                  // the frame in the panel look (the page's labels untouched)
        SET tjGui:STYLE:HEIGHT TO TJ_D["png_h"] + 48.

        LOCAL tb IS tjGui:ADDHLAYOUT().
        GLOBAL tjTitle IS tb:ADDLABEL("<b>ENTRY TRAJ</b>").
        uiDispTitle(tb, tjTitle).
        LOCAL qb IS tb:ADDBUTTON("X").
        SET qb:STYLE:WIDTH TO 24.
        SET qb:ONCLICK TO { trajHide(). }.

        // The default padding compresses the background vertically, so the sidecar's pixel rows land high. Zero
        // padding on the window and the box keeps it 1:1 with the PNG; TJ_V_SCALE corrects any remainder.
        SET tjGui:STYLE:PADDING:H TO 0.
        SET tjGui:STYLE:PADDING:V TO 0.
    }
    SET tjBox TO tjGui:ADDVLAYOUT().
    SET tjBox:STYLE:PADDING:H TO 0.
    SET tjBox:STYLE:PADDING:V TO 0.
    SET tjBox:STYLE:WIDTH TO TJ_D["png_w"].
    SET tjBox:STYLE:HEIGHT TO TJ_D["png_h"].
    SET tjBox:STYLE:BG TO TJ_P[0][6].
    SET tjXBox TO tjGui:ADDVLAYOUT().       // The X look (tjGpcX), right after tjBox: the same place in the flow, hidden until the window's GPC is dead
    SET tjXBox:STYLE:PADDING:H TO 0.
    SET tjXBox:STYLE:PADDING:V TO 0.
    SET tjXBox:STYLE:WIDTH TO TJ_D["png_w"].
    SET tjXBox:STYLE:HEIGHT TO TJ_D["png_h"].
    SET tjXBox:STYLE:BG TO UI_PANEL_DIR + "gpc_x".
    tjXBox:HIDE().
    SET tjXOn TO FALSE.
    SET tjOrd TO LIST().
    SET tjOrd0 TO tjChildN.

    // Every widget is created once (creating and destroying them each tick is slow); the trail slots are pre-built and
    // hidden with an empty image. Each marker records its flow index (see TJ_FLOW_PX).
    GLOBAL tjTrailM IS LIST().
    GLOBAL tjTrailI IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k >= TJ_TRAIL_N STEP { SET k TO k + 1. } DO {
        tjTrailI:ADD(tjChildN).
        tjTrailM:ADD(tjMarker(tjBox, TJ_EMPTY, TJ_TRAIL_W)).
    }
    GLOBAL tjDotM IS LIST().
    GLOBAL tjDotI IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k >= TJ_TRAIL_N STEP { SET k TO k + 1. } DO {
        tjDotI:ADD(tjChildN).
        tjDotM:ADD(tjMarker(tjBox, TJ_EMPTY, TJ_DOT_W)).
    }
    GLOBAL tjBoxI IS tjChildN.
    GLOBAL tjBoxM IS tjMarker(tjBox, TJ_BOX_IMG, TJ_BOX_W).
    GLOBAL tjBugI IS tjChildN.
    GLOBAL tjBugM IS tjMarker(tjBox, TJ_BUG_IMG, TJ_BUG_W).
    GLOBAL tjDArrI IS tjChildN.
    GLOBAL tjDArr IS tjMarker(tjBox, TJ_DARR_IMG, TJ_ARR_W).
    GLOBAL tjDTriI IS tjChildN.
    GLOBAL tjDTri IS tjMarker(tjBox, TJ_DTRI_IMG, TJ_TRI_W).
    GLOBAL tjAArrI IS tjChildN.
    GLOBAL tjAArr IS tjMarker(tjBox, TJ_AARR_IMG, TJ_ARR_W).
    GLOBAL tjATriI IS tjChildN.
    GLOBAL tjATri IS tjMarker(tjBox, TJ_ATRI_IMG, TJ_TRI_W).

    // the readout values (their labels are in the PNG), and the clock, drawn live over a blank space in the PNG
    GLOBAL tjInitI IS tjChildN.
    // INIT label: left-aligned, because the margin places the box and right alignment would leave the text at its far end
    GLOBAL tjInitM IS tjText(tjBox, 46, TJ_BR_FONT, "left").

    GLOBAL tjClkI IS tjChildN.
    GLOBAL tjClk IS tjText(tjBox, 190, TJ_CLK_FONT).

    GLOBAL tjTL IS LIST().
    GLOBAL tjTLidx IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k >= 5 STEP { SET k TO k + 1. } DO {
        tjTLidx:ADD(tjChildN).
        tjTL:ADD(tjText(tjBox, 120, TJ_TL_FONT)).
    }
    GLOBAL tjBR IS LIST().
    GLOBAL tjBRidx IS LIST().
    FROM { LOCAL k IS 0. } UNTIL k >= 9 STEP { SET k TO k + 1. } DO {
        tjBRidx:ADD(tjChildN).
        tjBR:ADD(tjText(tjBox, 120, TJ_BR_FONT)).
    }
    SET tjPanel TO TJ_P[0].
    tjCsSetup().                            // the C# page (or why not)
    tjPaintSetup().                         // The painter (TJ_PAINT; OFF by default)
    gpcWin("TOP", tjGpcX@).                 // The top windows X look (lib_gpc): its GPC failed = the big X in place of the page
    SET TJ_CS_STATE TO TJ_CS_STATE + "; panels " + TJ_BG_STATE.   // the event line names both
    // Built but not shown: building here early reports a missing sidecar with the coast still ahead, but the panel is
    // meaningless before the interface (no drag, no guidance, the orbiter bug offscale). trajShow() puts it up at the
    // entry interface.
    RETURN TRUE.
}

// trajShow and trajHide show and hide the window; trajClose disposes of it.
// on the deck, trajHide leaves the page up for tdInit to swap (VERT SIT takes the window); without the TAEM
// pages to come (LD_DISP FALSE) the deck goes; trajClose lets the deck's window be (lib_taemdisp owns it).
FUNCTION trajShow {   // tjShown (the redraws); the big X's box in place of the page while its GPC is dead (tjGpcX)
    IF tjGui <> 0 {
        IF tjDeckOn { IF tjXOn { tjXBox:SHOW(). } ELSE { tjBox:SHOW(). } }
        tjGui:SHOW().
        SET tjShown TO TRUE.
        gpcWinSync().                       // a GPC already dead: the X now, not at the next gpcTick
    }
}
// lib_gpc: the X look of the top window = ENTRY TRAJ. dead TRUE: the page box hidden and the big X box shown in its place
// (the C# writes into the hidden page do no harm; trajUpdate / tjRedraw draw nothing while the GPC is dead); FALSE (the GPC back,
// GPC/CRT X/Y EXEC): the page again, redrawn by the next update. tjXOn is kept while the page is down (trajShow honours it).
FUNCTION tjGpcX {
    PARAMETER dead.
    IF tjGui = 0 OR tjXBox:ISTYPE("Scalar") { RETURN. }
    SET tjXOn TO dead.
    IF NOT tjShown { RETURN. }
    IF dead { tjBox:HIDE(). tjXBox:SHOW(). } ELSE { tjXBox:HIDE(). tjBox:SHOW(). }
}
FUNCTION trajHide {
    SET tjShown TO FALSE.
    IF tjGui = 0 { RETURN. }
    IF NOT tjDeckOn { tjGui:HIDE(). RETURN. }
    LOCAL pg IS TRUE.
    IF DEFINED LD_DISP { SET pg TO LD_DISP. }
    IF NOT pg { tdDeckClose(). }
}
FUNCTION trajClose {
    IF tjGui <> 0 { IF tjDeckOn { tjBox:HIDE(). tjXBox:HIDE(). tdDeckClose(). } ELSE { tjGui:DISPOSE(). } SET tjGui TO 0. }
    SET tjShown TO FALSE.
}

// ---- the per-tick update ----------------------------------------------------------------
// Updates everything the panel shows. The caller passes the flight state in. Units: vrel m/s, rngM m, dref and dact ft/s^2,
// aCmd / aAct and the bank angles deg, qbar kPa, altKm km, hdot m/s, met s.
FUNCTION trajUpdate {
    PARAMETER vrel, rngM, dref, dact, aCmd, aAct.
    PARAMETER rollref, bankCmd, bankAct, corr, azErr, deadband.
    PARAMETER qbar, altKm, hdot, hddot, nz, famU, famRev, met, famRev2 IS 0.
    PARAMETER rollShow IS 1E9.
    PARAMETER famBank IS -1E9.             // the bank of the U row's u (deg; -1E9: none, U alone)
    // rollShow = the ROLL REF row's value, signed (1E9: rollref itself): ROLL REF follows the bank ramp. The members'
    // bank column is the bank BEFORE the TAEM ramp (the command ramps once), so rollref does not ramp: the callers pass
    // it through the ramp for the row only; the box keeps rollref (the guidance's want)
    // hddot carries the flap angle and famRev2 the elevon angle (the TRIM row; the names keep the call order). famRev is
    // EPR_GS_REVERSING as 1 or 0, not the reversal count.

    IF tjGui = 0 OR NOT TJ_OK { RETURN. }
    IF NOT gpcLive("TOP") { RETURN. }       // ENTRY TRAJ is the top window: its GPC failed, the last picture stays, then the big X (tjGpcX)
    LOCAL now IS TIME:SECONDS.              // the update's one clock read (the panel handover, the crumbs)
    IF tjCsOn AND TJ_CS {                   // C# draws (TJ_CS)
        LOCAL a IS LIST(vrel, rngM, dref, dact, aCmd, aAct, rollref, bankCmd, bankAct, corr, azErr, deadband, qbar, altKm,
                        hdot, hddot, nz, famU, famRev, met, famRev2, rollShow, famBank).
        LOCAL bxr IS 0.
        IF TJ_BUG_ON { SET bxr TO TJ_BANK_RANGE:CALL(tjBoxBank(rollref, corr, dref), vrel). }
        SET tjBusy TO TRUE.                 // the redraws hold these until the next cycle
        SET tjArgs TO a.
        SET tjBxr TO bxr.
        SET tjNext TO tjGridNx(uiRt()).
        LOCAL drew IS FALSE.
        IF tjCsOn { SET drew TO tjCsDraw(a, now, bxr, 1). }   // (a failed C# box lookup turned it off: kOS draws)
        SET tjBusy TO FALSE.
        IF drew {
            tjRateArm().
            RETURN.
        }
    }
    SET tjCsKos TO TRUE.
    SET tjCycle TO tjCycle + 1.
    SET tjFlashClk TO FALSE.                // kOS draws: the flash steps at every draw
    SET tjFlashN TO tjFlashN + 1.

    // ---- panel handover ------------------------------------------------------------
    LOCAL p IS trajPanelFor(vrel).
    IF p[0] <> tjPanel[0] {
        SET tjPanel TO p.
        SET tjBox:STYLE:BG TO p[6].
        // crumbs are positions in the previous panel's frame, so they are cleared on a panel change
        SET tjTrail TO LIST().
        SET tjBoxTrail TO LIST().
        SET tjTrailT TO now.            // a fresh panel starts a fresh trail
        FOR m IN tjTrailM { SET m:IMAGE TO TJ_EMPTY. }
        FOR m IN tjDotM { SET m:IMAGE TO TJ_EMPTY. }
        SET tjTrailDirty TO TRUE.
    }

    LOCAL rngKm IS rngM / 1000.
    LOCAL fx IS TJ_D["field_px"].

    // ---- is the orbiter bug drawable where it belongs? --------------------------
    // Offscale means the orbiter bug cannot be drawn inside the field less the sprite inset (padX, padY), for any reason;
    // otherwise it would be clamped silently and its position would lie.
    // Every side from the sprite's own box (TJ_BUG_W by 25/38 of it, the nose at the anchor), TJ_FIT_IN inside, so the
    // bug drawn (or held at the edge, flashing) is wholly inside the field: the nose carries the position (TJ_BUG_OFF_X
    // 0) and the sprite trails right, so a fixed inset of 0.6 of its width held the bug ~3 km right of its line at panel
    // 5's left edge (it drifted across the lines toward the handover).
    LOCAL padL IS TJ_FIT_IN - TJ_BUG_OFF_X.
    LOCAL padX IS TJ_BUG_W + TJ_BUG_OFF_X + TJ_FIT_IN.
    LOCAL padT IS TJ_FIT_IN - TJ_BUG_OFF_Y.
    LOCAL padB IS TJ_BUG_W * (25.0 / 38.0) + TJ_BUG_OFF_Y + TJ_FIT_IN.
    LOCAL bp IS trajPx(p, rngKm, vrel).
    LOCAL offscale IS FALSE.
    IF rngKm < p[3] OR rngKm > p[4] { SET offscale TO TRUE. }
    IF vrel > p[1] OR vrel < p[2] { SET offscale TO TRUE. }
    IF bp[0] < fx[0] + padL OR bp[0] > fx[0] + fx[2] - padX { SET offscale TO TRUE. }
    IF bp[1] < fx[1] + padT OR bp[1] > fx[1] + fx[3] - padB { SET offscale TO TRUE. }

    // ---- flashing --------------------------------------------------------------------
    // one phase for every flashing symbol: on for one draw, off for the next (a gate on the clock blinks
    // unevenly when the loop rate varies): every draw (tjFlashN), 5 Hz at the 10 Hz redraws
    LOCAL lit IS (MOD(tjFlashN, 2) = 0).
    // A reversal is announced by guidance, not guessed here: eprGuidStep sets EPR_GS_REVERSING when it flips EPR_GS_SIGN
    // and eprBankSlew clears it when the command arrives at `want`, the bank it is slewing to. The flash runs until then.
    LOCAL reversing IS (famRev > 0.5).

    LOCAL showBug IS TRUE.
    IF offscale OR reversing { SET showBug TO lit. }
    IF NOT TJ_BUG_ON { SET showBug TO FALSE. }

    // ---- bug -------------------------------------------------------------------------
    LOCAL bx IS MAX(fx[0] + padL, MIN(fx[0] + fx[2] - padX, bp[0])).
    LOCAL by IS MAX(fx[1] + padT, MIN(fx[1] + fx[3] - padB, bp[1])).
    IF showBug { SET tjBugM:IMAGE TO TJ_BUG_IMG. } ELSE { SET tjBugM:IMAGE TO TJ_EMPTY. }
    SET tjBugM:STYLE:MARGIN:H TO bx + TJ_BUG_OFF_X.
    SET tjBugM:STYLE:MARGIN:V TO by + TJ_BUG_OFF_Y - TJ_IMG_DY - tjFlow(tjBugI).

    // ---- box: the bank guidance WANTS, before the slew --------------------------------
    // rollref + corr, not bankCmd: bankCmd (eprBankSlew's output) passes through zero in a reversal and would swing the
    // box. The gap between box and bug is corr drawn. The same want as the reversal-clear test. Before guidance
    // initiate, the pre-bank held (tjBoxBank).
    LOCAL bxr IS 0.
    // SW 02 holds ENTRY guidance, so its bank want (the box, the family's guidance marker) is stale: no box.
    // The bug is the live position (navigation), so it stays. The C# box (tjCsDraw) does not follow this until S4c-4.
    IF TJ_BUG_ON AND NOT tjGdLost() { SET bxr TO TJ_BANK_RANGE:CALL(tjBoxBank(rollref, corr, dref), vrel). }
    // held wholly inside the field across, and drawn only when wholly inside it up and down
    IF bxr > 0 AND showBug AND by - TJ_BOX_W / 2 >= fx[1] + TJ_FIT_IN AND by + TJ_BOX_W / 2 <= fx[1] + fx[3] - TJ_FIT_IN {
        LOCAL pxb IS trajPx(p, bxr / 1000, vrel).
        SET tjBoxM:IMAGE TO TJ_BOX_IMG.
        SET tjBoxM:STYLE:MARGIN:H TO MAX(fx[0] + TJ_BOX_W / 2 + TJ_FIT_IN, MIN(fx[0] + fx[2] - TJ_BOX_W / 2 - TJ_FIT_IN,
            pxb[0])) - TJ_BOX_W / 2.
        SET tjBoxM:STYLE:MARGIN:V TO by - TJ_BOX_W / 2 - TJ_IMG_DY - tjFlow(tjBoxI).
    } ELSE {
        SET tjBoxM:IMAGE TO TJ_EMPTY.
    }

    // ---- crumbs ----------------------------------------------------------------------
    // no crumb while offscale: a clamped position is false, and unlike the flashing symbol a crumb persists
    // panels TJ_TRAIL_V_LO .. HI drop by velocity: a crumb when vrel is in a later step than the last crumb (its
    // stored vrel; none = step 0); the other panels by time
    LOCAL trailDue IS FALSE.
    IF p[0] >= TJ_TRAIL_V_LO AND p[0] <= TJ_TRAIL_V_HI {
        LOCAL lastStep IS 0.
        IF tjTrail:LENGTH > 0 { SET lastStep TO trajTrailStep(p, tjTrail[tjTrail:LENGTH - 1][1]). }
        SET trailDue TO trajTrailStep(p, vrel) > lastStep.
    } ELSE {
        SET trailDue TO now - tjTrailT >= TJ_TRAIL_S.
    }
    IF trailDue AND NOT offscale AND TJ_BUG_ON {
        SET tjTrailT TO now.
        SET tjTrailDirty TO TRUE.
        tjTrail:ADD(LIST(rngKm, vrel)).
        IF tjTrail:LENGTH > TJ_TRAIL_N { tjTrail:REMOVE(0). }
        IF bxr > 0 {
            tjBoxTrail:ADD(LIST(bxr / 1000, vrel)).
            IF tjBoxTrail:LENGTH > TJ_TRAIL_N { tjBoxTrail:REMOVE(0). }
        }
    }
    IF tjTrailDirty { SET tjTrailDirty TO FALSE. FROM { LOCAL k IS 0. } UNTIL k >= TJ_TRAIL_N STEP { SET k TO k + 1. } DO {
        IF k < tjTrail:LENGTH {
            LOCAL tp IS trajPx(p, tjTrail[k][0], tjTrail[k][1]).
            IF tjFits(tp, TJ_TRAIL_W, fx) {           // only wholly inside the field
                SET tjTrailM[k]:IMAGE TO TJ_TRAIL_IMG.
                SET tjTrailM[k]:STYLE:MARGIN:H TO tp[0] - TJ_TRAIL_W / 2.
                SET tjTrailM[k]:STYLE:MARGIN:V TO tp[1] - TJ_TRAIL_W / 2 - TJ_IMG_DY - tjFlow(tjTrailI[k]).
            } ELSE { SET tjTrailM[k]:IMAGE TO TJ_EMPTY. }
        } ELSE { SET tjTrailM[k]:IMAGE TO TJ_EMPTY. }
        IF k < tjBoxTrail:LENGTH AND tjFits(trajPx(p, tjBoxTrail[k][0], tjBoxTrail[k][1]), TJ_DOT_W, fx) {
            LOCAL dp IS trajPx(p, tjBoxTrail[k][0], tjBoxTrail[k][1]).
            SET tjDotM[k]:IMAGE TO TJ_DOT_IMG.
            SET tjDotM[k]:STYLE:MARGIN:H TO dp[0] - TJ_DOT_W / 2.
            SET tjDotM[k]:STYLE:MARGIN:V TO dp[1] - TJ_DOT_W / 2 - TJ_IMG_DY - tjFlow(tjDotI[k]).
        } ELSE { SET tjDotM[k]:IMAGE TO TJ_EMPTY. }
    } }

    // ---- strip markers ----------------------------------------------------------------
    // strip positions come from the sidecar (strip_a, strip_d); the scales come from the panel
    LOCAL sa IS TJ_D["strip_a"].
    LOCAL sd IS TJ_D["strip_d"].
    LOCAL sTop IS sa[1].
    LOCAL sBot IS sa[2].
    // The strip scales come from the panel (the generator writes them on its P line), not from a rule assumed here:
    // TRAJ 5's alpha strip is 10-35 because the AoA schedule takes it down to 15, where a 25-50 strip would clamp.
    // The alpha markers jump at the 4 -> 5 handover, when the scale changes with the background; that is expected.
    LOCAL sca IS trajAlphaScale(p).
    LOCAL scd IS trajDragScale(p).
    LOCAL aLo IS sca[0]. LOCAL aHi IS sca[1].
    LOCAL dLo IS scd[0]. LOCAL dHi IS scd[1].
    LOCAL aArrOff IS (aCmd < aLo OR aCmd > aHi).
    LOCAL aTriOff IS (aAct < aLo OR aAct > aHi).
    // Before guidance runs (fam_dref is 0 until eprGuidStep), the drag arrow points at EPR_GUID_DRAG_INIT, where guidance
    // starts, and is labelled INIT; the actual-drag triangle climbing to it counts down to closed loop.
    LOCAL preGuid IS (dref <= 0).
    LOCAL dRefShown IS dref.
    IF preGuid { SET dRefShown TO EPR_GUID_DRAG_INIT * 3.28084. }
    LOCAL dArrOff IS (dRefShown < dLo OR dRefShown > dHi).
    LOCAL dTriOff IS (dact < dLo OR dact > dHi).
    LOCAL aArrLit IS (NOT aArrOff) OR lit.
    LOCAL aTriLit IS (NOT aTriOff) OR lit.
    LOCAL dArrLit IS (NOT dArrOff) OR lit.
    LOCAL dTriLit IS (NOT dTriOff) OR lit.
    LOCAL aArrY IS trajStripPx(aCmd, aLo, aHi, sTop, sBot).
    LOCAL aTriY IS trajStripPx(aAct, aLo, aHi, sTop, sBot).
    LOCAL dArrY IS trajStripPx(dRefShown, dLo, dHi, sTop, sBot).
    LOCAL dTriY IS trajStripPx(dact, dLo, dHi, sTop, sBot).
    LOCAL aX IS sa[0].
    LOCAL dX IS sd[0].
    IF aArrLit { SET tjAArr:IMAGE TO TJ_AARR_IMG. } ELSE { SET tjAArr:IMAGE TO TJ_EMPTY. }
    IF aTriLit { SET tjATri:IMAGE TO TJ_ATRI_IMG. } ELSE { SET tjATri:IMAGE TO TJ_EMPTY. }
    IF dArrLit { SET tjDArr:IMAGE TO TJ_DARR_IMG. } ELSE { SET tjDArr:IMAGE TO TJ_EMPTY. }
    IF dTriLit { SET tjDTri:IMAGE TO TJ_DTRI_IMG. } ELSE { SET tjDTri:IMAGE TO TJ_EMPTY. }
    // the tip's row within each sprite (px), not half its height
    LOCAL arrH IS TJ_ARR_H * TJ_ARR_TIPF.
    LOCAL triH IS TJ_TRI_H * TJ_TRI_TIPF.
    SET tjAArr:STYLE:MARGIN:H TO aX - TJ_ARR_W. SET tjAArr:STYLE:MARGIN:V TO aArrY - arrH - TJ_IMG_DY - tjFlow(tjAArrI).
    SET tjATri:STYLE:MARGIN:H TO aX - TJ_TRI_W. SET tjATri:STYLE:MARGIN:V TO aTriY - triH - TJ_IMG_DY - tjFlow(tjATriI).
    SET tjDArr:STYLE:MARGIN:H TO aX + (dX - aX). SET tjDArr:STYLE:MARGIN:V TO dArrY - arrH - TJ_IMG_DY - tjFlow(tjDArrI).
    SET tjDTri:STYLE:MARGIN:H TO dX.             SET tjDTri:STYLE:MARGIN:V TO dTriY - triH - TJ_IMG_DY - tjFlow(tjDTriI).
    IF preGuid AND dArrLit {
        SET tjInitM:TEXT TO tjCol("INIT", TJ_YELLOW).
        SET tjInitM:STYLE:MARGIN:H TO dX + TJ_ARR_W + 4 * tjS.
        // +6.6 px (measured): TJ_BR_DY alone leaves the label high against the arrow tip
        SET tjInitM:STYLE:MARGIN:V TO dArrY - TJ_BR_DY + 6.6 - tjFlow(tjInitI).
    } ELSE {
        SET tjInitM:TEXT TO "".
    }

    // ---- readouts ----------------------------------------------------------------------
    // The row pixels come from the sidecar, where the generator drew each row; recomputing them here comes out one row low.
    LOCAL tlr IS TJ_D["tl_rows"].
    LOCAL tlx IS TJ_D["tl_right"] - 120.
    // Imperial at print (the baked labels carry no units, as on the orbiter): q-bar kPa to psf, H km to kft, H-dot m/s
    // to ft/s; D REF is already in ft/s^2. The row below H-dot's two shows the Mach number as X.XX (tjMach), not V.
    LOCAL tlv IS LIST(tjUBank(famU, famBank), CHOOSE "----" IF tjGdLost() ELSE ROUND(dRefShown, 1), ROUND(qbar * 20.885434),
                      ROUND(azErr, 1), ROUND(deadband, 1)).
    FROM { LOCAL k IS 0. } UNTIL k >= 5 STEP { SET k TO k + 1. } DO {
        LOCAL tx IS "" + tlv[k].
        IF tx <> tjTLtxt[k] OR NOT tjRowsPlaced { SET tjTLtxt[k] TO tx. SET tjTL[k]:TEXT TO tjCol(tx, TJ_GREEN). }
        IF NOT tjRowsPlaced {
            SET tjTL[k]:STYLE:MARGIN:H TO tlx.
            SET tjTL[k]:STYLE:MARGIN:V TO tlr[k]*TJ_V_SCALE - TJ_TL_DY - tjFlow(tjTLidx[k]).
        }
    }
    LOCAL brr IS TJ_D["br_rows"].
    LOCAL brx IS TJ_D["br_right"] - 120.
    // ROLL REF carries its own side, signed by the caller: in a reversal it disagrees with CMD, as on the orbiter (2.13).
    LOCAL brv IS LIST(tjSigned(corr), tjLR(CHOOSE rollref IF rollShow > 1E8 ELSE rollShow), tjLR(bankCmd), tjLR(bankAct),
                      tjMach(qbar, altKm), "" + ROUND(altKm * 3.28084, 1), "" + ROUND(hdot * 3.28084),
                      tjTrim(hddot, famRev2), ROUND(nz, 2) + " G").
    FROM { LOCAL k IS 0. } UNTIL k >= 9 STEP { SET k TO k + 1. } DO {
        LOCAL tx IS "" + brv[k].
        IF tx <> tjBRtxt[k] OR NOT tjRowsPlaced { SET tjBRtxt[k] TO tx. SET tjBR[k]:TEXT TO tjCol(tx, TJ_GREEN). }
        IF NOT tjRowsPlaced {
            SET tjBR[k]:STYLE:MARGIN:H TO brx.
            SET tjBR[k]:STYLE:MARGIN:V TO brr[k]*TJ_V_SCALE - TJ_BR_DY - tjFlow(tjBRidx[k]).
        }
    }
    SET tjRowsPlaced TO TRUE.
    // the window's title row reads ENTRY TRAJ without the number (the GUI's title, not the screen's); the page itself
    // keeps its ENTRY TRAJ n
    SET tjTitle:TEXT TO CHOOSE "<b>ENTRY TRAJ</b>" IF uiDispOn()   // the green only
        ELSE tjCol("<b>ENTRY TRAJ</b>", TJ_GREEN).                   //   inside the display
    IF TJ_D:HASKEY("clock_px") {
        LOCAL cp IS TJ_D["clock_px"].
        SET tjClk:TEXT TO tjCol(tjClock(met), TJ_GREEN).
        SET tjClk:STYLE:MARGIN:H TO cp[0] - 190.
        SET tjClk:STYLE:MARGIN:V TO cp[1]*TJ_V_SCALE - TJ_CLK_DY - tjFlow(tjClkI).
    }
}

// ---- the C# page and its 10 Hz redraws (see the globals' note above)
FUNCTION tjCsOff {                          // any failure: kOS draws from now on, for the flight (once a cycle)
    PARAMETER why.
    SET TJ_CS_ERR TO why.
    SET TJ_CS_STATE TO "kOS (" + why + ")".
    SET tjCsOn TO FALSE.
    SET TJ_CS TO FALSE.
}

// ---- the painter (see TJ_PAINT at the top)
FUNCTION tjPaintGroups {                   // LIST(LIST(name, page box, LIST(LIST(label, flow index) ...), the page box's child count))
    RETURN LIST(LIST("TJ", tjBox, tjOrd, tjChildN - tjOrd0)).
}

FUNCTION tjPaintPh {                       // a placeholder: the page box's LAST child, a 1 x 1 box + an empty 1 x 1 label
    PARAMETER pg, fl.                       //   (shown: its draw is where C# paints the page, after every slot box)
    LOCAL bx IS pg:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 1. SET m:STYLE:HEIGHT TO 1.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:MARGIN:H TO 0. SET m:STYLE:MARGIN:V TO 0.
    RETURN LIST(m, fl, pg).
}

FUNCTION tjPaintSetup {                    // trajInit's end (after every slot): TJ_PAINT 0 = nothing created
    SET tjPaintReg TO FALSE.
    tjPaintNames:CLEAR().
    IF TJ_PAINT = 0 { SET TJ_PAINT_STATE TO "OFF". RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        FOR gp IN tjPaintGroups() {
            IF why = "" {
                LOCAL er IS ADDONS:KALS:PAINTREG(gp[0], tjPaintPh(gp[1], gp[3]), gp[2]).
                IF er = "" { tjPaintNames:ADD(gp[0]). SET er TO ADDONS:KALS:PAINTMODE(gp[0], TJ_PAINT). }
                IF er <> "" { SET why TO gp[0] + ": " + er. }
            }
        }
    }
    IF why <> "" { tjPaintOff(why). RETURN. }
    SET tjPaintReg TO TRUE.
    SET TJ_PAINT_STATE TO tjPaintName(TJ_PAINT).
}

FUNCTION tjPaintName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
}

// the mode switched live (the test harness's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a TJ_PAINT > 0 trajInit
FUNCTION tjPaintSet {
    PARAMETER m.
    IF NOT tjPaintReg { RETURN "not registered (TJ_PAINT was 0 at trajInit, or it failed: " + TJ_PAINT_STATE + ")". }
    FOR gn IN tjPaintNames {
        LOCAL er IS ADDONS:KALS:PAINTMODE(gn, m).
        IF er <> "" { tjPaintOff(gn + ": " + er). RETURN er. }
    }
    SET TJ_PAINT TO m.
    SET TJ_PAINT_STATE TO tjPaintName(m).
    RETURN "".
}

FUNCTION tjPaintOff {                      // any failure: kOS draws from now on (C# showed the boxes, or never hid them)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") {
        FOR gn IN tjPaintNames { ADDONS:KALS:PAINTMODE(gn, 0). }
    } }
    SET TJ_PAINT_STATE TO "OFF (" + why + ")".
    SET TJ_PAINT TO 0.
    SET tjPaintReg TO FALSE.
}

FUNCTION tjCsSetup {                        // trajInit's end: the widgets and constants to the addon
    SET tjCsOn TO FALSE.
    IF NOT TJ_CS {
        SET TJ_CS_STATE TO "kOS (TJ_CS off)".
        RETURN.
    }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("TJDRAW") { SET why TO "the KAL/S addon has no ENTRY TRAJ page (an older DLL)". }
    ELSE {
        LOCAL er IS ADDONS:KALS:TJSETUP().
        IF er <> "" { SET why TO "TJSETUP: " + er. }
    }
    IF why <> "" {
        tjCsOff(why).
        RETURN.
    }
    SET tjCsOn TO TRUE.
    SET TJ_CS_STATE TO "C#".
}

FUNCTION tjCsDraw {                         // TRUE: C# drew this update; FALSE: kOS draws it (a failure)
    PARAMETER a, now, bxr, cnt.             // trajUpdate's 22 arguments, TIME:SECONDS, the box's range, 1 = a guidance cycle
    LOCAL inp IS LIST(a, now, bxr, uiDispOn(), cnt).
    SET tjFlashClk TO tjFlashClkNow().       // Tj.cs reads it (the flash on the grid)
    SET tjRtT TO uiRt().                    // the grid in real time
    LOCAL ops IS ADDONS:KALS:TJDRAW(inp).
    IF ops:ISTYPE("String") {               // nothing was written: kOS draws this update
        tjCsOff("TJDRAW: " + ops).
        RETURN FALSE.
    }
    tjCsApply(ops).
    IF NOT TJ_AFTER:ISTYPE("Scalar") { TJ_AFTER:CALL(). }   // the entry page's DB lines in this draw's phase
    RETURN TRUE.
}

FUNCTION tjCsApply {                        // TJDRAW's widget writes, in order: widget, code, value
    PARAMETER o.
    FROM { LOCAL i IS 0. } UNTIL i >= o:LENGTH STEP { SET i TO i + 3. } DO {
        LOCAL w IS o[i].
        LOCAL c IS o[i + 1].
        IF c = 4 { SET w:STYLE:MARGIN:H TO o[i + 2]. }
        ELSE IF c = 5 { SET w:STYLE:MARGIN:V TO o[i + 2]. }
        ELSE IF c = 1 { SET w:IMAGE TO o[i + 2]. }
        ELSE IF c = 0 { SET w:TEXT TO o[i + 2]. }
        ELSE { SET w:STYLE:BG TO o[i + 2]. }
    }
}

FUNCTION tjRateArm {                        // after a C# cycle draw: the redraw trigger, armed once (until it ends)
    IF tjTrig OR NOT tjShown OR TJ_DT_CS <= 0 OR TJ_LIVE:ISTYPE("Scalar") { RETURN. }
    SET tjTrig TO TRUE.
    WHEN uiRt() >= tjNext THEN { RETURN tjRedraw(). }   // real time
}

FUNCTION tjRedraw {                         // the trigger's body: one redraw between cycles; FALSE ends the trigger
    IF NOT (tjCsOn AND TJ_CS AND tjShown AND TJ_OK) OR tjGui = 0 OR TJ_DT_CS <= 0
            OR TJ_LIVE:ISTYPE("Scalar") {
        SET tjTrig TO FALSE.                // the next C# cycle draw arms it again when the redraws may run
        RETURN FALSE.
    }
    IF tjBusy OR tjArgs:LENGTH < 22 { RETURN TRUE. }    // trajUpdate is drawing: the next tick (22 or 23 args)
    IF NOT gpcLive("TOP") { RETURN TRUE. }              // Its GPC failed: no redraw (the trigger stays armed)
    LOCAL now IS TIME:SECONDS.
    SET tjNext TO tjGridNx(uiRt()).
    LOCAL lv IS TJ_LIVE:CALL().
    LOCAL a IS tjArgs:COPY.
    SET a[0] TO lv[0]. SET a[1] TO lv[1]. SET a[5] TO lv[2]. SET a[8] TO lv[3].
    SET a[12] TO lv[4]. SET a[13] TO lv[5]. SET a[14] TO lv[6]. SET a[19] TO lv[7].
    IF tjCsDraw(a, now, tjBxr, 0) { SET TJ_CS_NRD TO TJ_CS_NRD + 1. }
    RETURN TRUE.
}

FUNCTION tjFlashClkNow {                     // the redraws run (tjRateArm's / tjRedraw's tests): the flash on the grid
    RETURN tjCsOn AND TJ_CS AND tjShown AND TJ_OK AND TJ_DT_CS > 0 AND NOT TJ_LIVE:ISTYPE("Scalar").
}

FUNCTION tjGridNx {                          // lib_taemdisp's tdGridNx on TJ_DT_CS
    PARAMETER t.
    RETURN (FLOOR((t + 0.005) / TJ_DT_CS) + 1) * TJ_DT_CS - 0.005.
}

// The bank (deg) the box stands for, handed to TJ_BANK_RANGE (which interpolates
// between the member lines). Before guidance initiate -- dref <= 0, the page's own preGuid test (EPR_GS_DREF stays 0
// until the first guidance cycle; the INIT label shows meanwhile) -- the pre-bank the vehicle and the members hold from the
// interface, EPR_PREENTRY_BANK (entry_predict; 90 on an AOA abort, 0 on a TAL); after it the guidance's want,
// |rollref| + corr. One kOS function for both draws: the C# page is handed the range this gives.
FUNCTION tjBoxBank {
    PARAMETER rollref, corr, dref.
    IF dref <= 0 { RETURN ABS(EPR_PREENTRY_BANK). }
    RETURN ABS(rollref) + corr.
}

// ---- the panels drawn by the KAL/S addon (see TJ_BG_CS above) ----------------------
FUNCTION tjBgOff {                          // any failure: the watcher's files, for the flight
    PARAMETER why.
    SET TJ_BG_ERR TO why.
    SET TJ_BG_STATE TO "watcher (" + why + ")".
    SET TJ_BG_CS TO FALSE.
}

FUNCTION tjBgSide {                         // trajInit, before the sidecar is read: draw (or find up to date) and switch
    IF NOT TJ_BG_CS {
        IF TJ_BG_ERR = "" { SET TJ_BG_STATE TO "watcher (TJ_BG_CS off)". }
        RETURN.
    }
    IF TJ_SIDE <> TJ_BG_WATCH AND TJ_SIDE <> "0:/" + TJ_BG_SIDE {
        SET TJ_BG_STATE TO "fixed (" + TJ_SIDE + ")".       // a caller's own panels (OPS 6): not family.txt's
        RETURN.
    }
    SET TJ_SIDE TO TJ_BG_WATCH.             // (a second trajInit: asked again; an up-to-date drawing answers at once)
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("TJBG") { SET why TO "the KAL/S addon has no TJBG (an older DLL)". }
    ELSE IF NOT EXISTS("0:/" + TJ_BG_FAM) { SET why TO "no " + TJ_BG_FAM. }
    LOCAL h IS 0.
    IF why = "" {
        SET h TO ADDONS:KALS:TJBG(TJ_BG_FAM, TJ_BG_SIDE, TJ_BG_TPL).
        LOCAL n IS 0.
        UNTIL h:DONE OR n >= TJ_BG_TICKS { WAIT 0. SET n TO n + 1. }
        IF NOT h:DONE { SET why TO "no answer in " + n + " ticks". }
        ELSE IF NOT h:OK { SET why TO "TJBG: " + h:WHY. }
    }
    IF why <> "" { tjBgOff(why). RETURN. }
    SET TJ_SIDE TO "0:/" + h:SIDE.
    SET TJ_BG_STATE TO "C#" + (CHOOSE " (up to date)" IF h:UPTODATE ELSE " (" + ROUND(h:MS) + " ms)").
}

// OPS 6: shows another sidecar's panels in the open window (the live family's own, once the addon has drawn them).
// FALSE, with the page as it was and TJ_WHY saying why, when the new sidecar is refused or is another size. The next
// update's panel handover puts up the right panel (tjPanel is reset) and clears the crumbs (another x window).
FUNCTION trajReload {
    PARAMETER side.
    IF tjGui = 0 OR NOT TJ_OK { SET TJ_WHY TO "no page to reload". RETURN FALSE. }
    LOCAL oSide IS TJ_SIDE. LOCAL oD IS TJ_D. LOCAL oP IS TJ_P.
    SET TJ_SIDE TO side.
    LOCAL ok IS trajReadSide().
    IF ok AND (TJ_D["png_w"] <> oD["png_w"] OR TJ_D["png_h"] <> oD["png_h"]) {
        SET ok TO FALSE.
        SET TJ_WHY TO side + " is " + TJ_D["png_w"] + " x " + TJ_D["png_h"] + " px, not " + oD["png_w"] + " x " + oD["png_h"].
    }
    IF NOT ok {
        LOCAL why IS TJ_WHY.
        SET TJ_SIDE TO oSide. SET TJ_D TO oD. SET TJ_P TO oP. SET TJ_OK TO TRUE.
        SET TJ_WHY TO why.
        RETURN FALSE.
    }
    SET tjPanel TO LIST(0, 0, 0, 0, 0, 0, TJ_P[0][6], 0, 0, 0, 0).
    SET tjCsKos TO TRUE.                    // the C# page forgets what it last wrote (TJ_CS_SKIP): all is written anew
    RETURN TRUE.
}

// the box's range (TJ_BANK_RANGE) and the TAL bug's range among the generic lines, in C# (Tj.cs TjFam: the
// same numbers): tjFamBank = entry_predict's eprTrajBankRange (the default TJ_BANK_RANGE), tjGenBank = lib_tal's
// talGenBankRange (OPS 6's TJ_BANK_RANGE), tjTalRange = lib_tal's talTrajRange (OPS 6's bug). With the C# page off: kOS's
// own function; an addon failure turns the C# page off (tjCsOff) and kOS answers.
FUNCTION tjFamBank {
    PARAMETER bank, vr.
    IF tjCsOn {
        LOCAL cr IS ADDONS:KALS:TJFAMBANK(bank, vr).
        IF cr:ISTYPE("String") { tjCsOff("TJFAMBANK: " + cr). }
        ELSE { RETURN cr. }
    }
    RETURN eprTrajBankRange(bank, vr).
}

FUNCTION tjGenBank {
    PARAMETER bank, vr.
    IF tjCsOn {
        LOCAL cr IS ADDONS:KALS:TJGENBANK(bank, vr).
        IF cr:ISTYPE("String") { tjCsOff("TJGENBANK: " + cr). }
        ELSE { RETURN cr. }
    }
    RETURN talGenBankRange(bank, vr).
}

FUNCTION tjTalRange {
    PARAMETER vr, rng.
    IF tjCsOn {
        LOCAL cr IS ADDONS:KALS:TJTALRANGE(vr, rng).
        IF cr:ISTYPE("String") { tjCsOff("TJTALRANGE: " + cr). }
        ELSE { RETURN cr. }
    }
    RETURN talTrajRange(vr, rng).
}

// A bank angle as L (positive) or R (negative) and its rounded magnitude, as the orbiter shows it
FUNCTION tjLR {
    PARAMETER b.
    RETURN (CHOOSE "L" IF b >= 0 ELSE "R") + ROUND(ABS(b)).
}

// The TRIM readout: the flap angle as U (nose up, negative PTRIM_ANG) or D (nose down), then "+" and the elevon angle
// whenever the elevons carry any load (ETRIM_ANG non-zero), not only with the flap at its limit. Elevon spill starts at
// PTRIM_MAX - ETRIM_SPILL (19.0 deg, not 19.5). Examples: U5.23, D2.34, U19.5+2.65 (flap saturated, elevons carrying 2.65 deg).
FUNCTION tjTrim {
    PARAMETER flap, elev.
    LOCAL t IS CHOOSE "U" IF flap <= 0 ELSE "D".
    SET t TO t + ROUND(ABS(flap), 2).
    IF ABS(elev) > 0.01 { SET t TO t + "+" + ROUND(ABS(elev), 2). }
    RETURN t.
}

// the Mach number as X.XX, from q-bar (kPa) and the static pressure at altKm (ops3q's machNow: M^2 = 2q / (1.4 p));
// 0.00 above the air. Tj.cs's Mach is the same.
// The U row: u always with two decimals, then " | " and the bank (deg, whole) in a 2-character field ("0.73 | 60"); the
// row is right-aligned in a monospaced font, so the bank keeps its place on the x-axis whatever u's digits. Tj.cs UBank
// prints the same.
FUNCTION tjGdLost {                           // TRUE while SW 02 holds ENTRY (the guidance's rows on this page blank)
    IF NOT (DEFINED FLFX_SWPROG) { RETURN FALSE. }
    RETURN flfxSwGuid("ENTRY").
}
FUNCTION tjURowBank {                         // the callers' bank for the U row (-1E9 without a family)
    PARAMETER vIn, uIn.
    IF tjGdLost() { RETURN -1E9. }            // The bank of the U row blanks ("U alone")
    IF NOT (DEFINED EPR_FAM) { RETURN -1E9. }
    IF EPR_FAM:LENGTH < 2 { RETURN -1E9. }
    IF tjPreInit() { RETURN ABS(EPR_PREENTRY_BANK). }   // the pre-bank, held to guidance initiate
    LOCAL bk IS eprFamRoll(vIn, uIn).
    IF EPR_FAM_ADD { SET bk TO eprBankWithFlare(bk, vIn). }
    RETURN bk.
}

// Before the initiate the U row shows the pre-bank (EPR_PREENTRY_BANK: 60, an AOA 90, a TAL 0) as the family's u,
// between the members' banks (EPR_FAM's column 0, sorted; u = the index over n - 1, as eprFamInvert), with
// tjURowBank's bank the pre-bank itself; from the initiate the state's u. Without a family the state's u.
FUNCTION tjPreInit {
    IF NOT (DEFINED EPR_FAM) { RETURN FALSE. }
    IF EPR_FAM:LENGTH < 2 { RETURN FALSE. }
    IF NOT (DEFINED EPR_GS_STARTED) { RETURN FALSE. }
    RETURN NOT EPR_GS_STARTED.
}

FUNCTION tjURowU {
    PARAMETER uIn.
    IF NOT tjPreInit() { RETURN uIn. }
    LOCAL bk IS ABS(EPR_PREENTRY_BANK).
    LOCAL nf IS EPR_FAM:LENGTH.
    IF bk <= EPR_FAM[0][0] { RETURN 0. }
    IF bk >= EPR_FAM[nf - 1][0] { RETURN 1. }
    LOCAL ix IS 1.
    UNTIL ix >= nf {
        IF EPR_FAM[ix][0] >= bk {
            LOCAL b0 IS EPR_FAM[ix - 1][0].
            LOCAL fr IS (bk - b0) / MAX(EPR_FAM[ix][0] - b0, 1E-9).
            RETURN (ix - 1 + fr) / (nf - 1).
        }
        SET ix TO ix + 1.
    }
    RETURN 1.
}

FUNCTION tjUBank {
    PARAMETER uIn, bIn.
    LOCAL uRnd IS ROUND(ABS(uIn), 2).
    LOCAL uTxt IS "" + uRnd.
    IF NOT uTxt:CONTAINS(".") { SET uTxt TO uTxt + ".00". }
    ELSE IF uTxt:LENGTH - uTxt:FIND(".") = 2 { SET uTxt TO uTxt + "0". }
    IF uIn < 0 AND uRnd > 0 { SET uTxt TO "-" + uTxt. }
    IF bIn < -1E8 { RETURN uTxt. }
    LOCAL bTxt IS "" + ROUND(ABS(bIn)).
    IF bTxt:LENGTH < 2 { SET bTxt TO " " + bTxt. }
    RETURN uTxt + " | " + bTxt.
}

FUNCTION tjMach {
    PARAMETER qbar, altKm.
    LOCAL ps IS SHIP:BODY:ATM:ALTITUDEPRESSURE(altKm * 1000) * CONSTANT:ATMTOKPA.
    LOCAL m IS 0.
    IF ps > 1E-7 { SET m TO SQRT(MAX(2 * qbar / (1.4 * ps), 0)). }
    LOCAL c IS ROUND(m * 100).
    RETURN FLOOR(c / 100) + "." + tjPad(MOD(c, 100), 2).
}

// x to one decimal, with a + sign when it is not negative
FUNCTION tjSigned {
    PARAMETER x.
    RETURN (CHOOSE "+" IF x >= 0 ELSE "") + ROUND(x, 1).
}

// n rounded and zero-padded on the left to w digits
FUNCTION tjPad {
    PARAMETER n, w.
    LOCAL t IS "" + ROUND(n).
    UNTIL t:LENGTH >= w { SET t TO "0" + t. }
    RETURN t.
}

// t seconds as DDD/HH:MM:SS, zero-padded like the orbiter's (2.4)
FUNCTION tjClock {
    PARAMETER t.
    LOCAL d IS FLOOR(t / 86400).
    LOCAL h IS FLOOR(MOD(t, 86400) / 3600).
    LOCAL mi IS FLOOR(MOD(t, 3600) / 60).
    LOCAL sc IS FLOOR(MOD(t, 60)).
    RETURN tjPad(d, 3) + "/" + tjPad(h, 2) + ":" + tjPad(mi, 2) + ":" + tjPad(sc, 2).
}
