// lib_o2disp.ks -- ops2q's WINDOW: the lib_guistyle panel around a black MEDS page:
// the title bar (the page's name), the page row (4 equal buttons, the shown page lit), the 738 x 460 page
// (o2_bg/page.png: black, a green rim) with 20 text rows, and under it the control grid of equal cells (3 rows x 6 on
// MNVR EXEC: the pad, INPUT PAGE / RHC, TYPE / CANCEL, STEP, ARM / EXEC / CUT OFF; x 5 on the others).
// The rows: each an HLAYOUT of three labels (before the cursor, the cursor, after it), the page face (DejaVu Sans Mono
// Bold 14 px, the page green), rich text. The cursor is BLACK TEXT ON A FILLED AMBER BOX: its label's
// background is o2_bg/cur.png. Laid out by kOS, the box sits right after the text before it, so it lands on its field
// whatever the font's advance; the text before it keeps its trailing spaces as no-break spaces (Unity measures them).
// The orbit view's sprites: lib_entdisp's nested 1 x 1 boxes (O2_NEST of them, before the rows in the flow, so the rows
// start O2_NEST px lower: the page's top padding takes them back), each child placed by its margins.
// THE GRID'S GEOMETRY: every cell is a fixed-size CONTAINER (a VLAYOUT o2ColW wide, O2_CELL_H high, no margin or
// padding) with its button inside, so a cell's width never depends on its text, its lit / hover / pressed style or the
// layout's margin rules; a row is an HLAYOUT exactly O2_W wide; the STEP readout is a container as wide as its two
// columns; the widths come from o2ColW (6 columns 123 px, 5 columns 148 148 148 147 147: each sums to O2_W); the window has a
// fixed size (O2_WIN_H) that holds the title, the page row, the page and the three grid rows.
// the page and the grid are separated by a GAP (a spacer label O2_GAP high, every margin around it 0). Flat grid rows (margin 0)
// took the skin's gap away: measured in a real KSP run the page's green rim ended on pixel row
// 534 and the grid's first button began on row 534, so the rim touched the buttons. The page box's own margin is set to 0 as well, so the gap is O2_GAP exactly (o2Layout is the same arithmetic).
// the same on the TOP edge. The clear strip first sat under the box only; above it the page-button row ended on pixel row 54 of the window
// and the box's green rim began on row 54 (measured in a real KSP run: screen rows 74 / 74). A second spacer (o2GapTop, O2_GAP high, every margin 0) now sits between the page-button row and the box:
// the box starts at O2_TOP = O2_NAV_BOTTOM + O2_GAP; the window keeps its O2_WIN_H (its slack under the grid went from 24 to 14 px).
// CUT OFF is no longer in the sixth column: on every page (INPUT PAGE and INPUT RHC) it is ONE button in grid row 3 under TYPE and
// CANCEL, as wide as the two (cell 15 widened to the width of columns 4 + 5; cells 16 and 17 hidden), so the grid is 5 columns wide
// on every page. Only the TYPE keypad keeps its own layout (6 columns: 0 ENT CUT OFF). The STEP readout left the grid: a small label
// in the page's bottom right corner (o2StepL, in a ninth sprite nest group), its text '' except while the cursor is on a number.
// The buttons' delegates only add their cell to o2Press (each made in its own call, so it keeps its own number); the
// host takes them with o2DispTake.
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
RUNONCEPATH("0:/lib/lib_guistyle.ks").

GLOBAL O2_DIR IS "o2_bg/".                   // the sprites (generated offline)
GLOBAL O2_W IS 738.                          // the page px
GLOBAL O2_H IS 460.
GLOBAL O2_PAD_X IS 14.                       // the page's text inset (px)
GLOBAL O2_PAD_Y IS 10.
GLOBAL O2_ROW_H IS 21.
GLOBAL O2_FONT IS "DejaVu Sans Mono Bold".
GLOBAL O2_FS IS 14.
GLOBAL O2_CELL_H IS 24.
GLOBAL O2_NEST IS 8.                         // the sprite boxes (each takes 1 px of the flow)
GLOBAL O2_NEST_N IS 40.                      // sprites a box
GLOBAL O2_X IS 60.                           // the window's place on the screen
GLOBAL O2_WIN_H IS 620.                      // the window's height: title 22 + page row 24 + page 460 + grid 3 x 24 + the gaps + slack
RUNONCEPATH("0:/lib/lib_screen.ks").         // SCR_H: the window's start place (T1014)
GLOBAL O2_Y IS MAX(0, MIN(405, SCR_H - O2_WIN_H)).   // T1014: the top of ops1's OPS 1 TRAJ window (lib_ascdisp AD_Y = 405 on 4K), kept on the screen; was 20 (the top bar)
GLOBAL O2_GAP IS 10.                         // the clear gap between the page box and the grid (px)
GLOBAL O2_STEP_X IS 574.                     // the STEP label's place on the page (px): its left edge, top and size
GLOBAL O2_STEP_Y IS 430.
GLOBAL O2_STEP_W IS 150.
GLOBAL O2_STEP_H IS 18.
GLOBAL O2_NAV_BOTTOM IS 54.                  // the page-button row's bottom below the window's top (title + page row; measured in KSP)
GLOBAL O2_TOP IS O2_NAV_BOTTOM + O2_GAP.     // the page box's top: the clear strip O2_GAP under the page-button row
GLOBAL O2_NAV IS LIST("MNVR EXEC", "DEORB", "ORBIT / PTG", "OMS/RCS", "PDRS").   // the 5th page, PDRS, is the arm
GLOBAL O2_BANG_W IS 34.                      // the "!" button (the FAILURES window) at the right end of the page row, outside the face
GLOBAL O2_GO_RGB IS RGB(143 / 255, 209 / 255, 143 / 255).

GLOBAL o2Gui IS 0.
GLOBAL o2GuiOn IS FALSE.                     // o2Gui is made (a GUI is never compared with a number)
GLOBAL o2Title IS 0.
GLOBAL o2Box IS 0.
GLOBAL o2NavB IS LIST().
GLOBAL o2RowW IS LIST().                     // LIST(LIST(pre, cur, post)) a row
GLOBAL o2Cells IS LIST().                    // the grid's 18 buttons, row by row (6 a row; the 6th = ARM / EXEC / CUT OFF)
GLOBAL o2StepL IS 0.                         // the STEP readout, a small label in the page's bottom right corner ('' = hidden text)
GLOBAL o2StepBox IS 0.                       // = o2StepL (O2SETUP's 'stepbox': shown / hidden with the grid's mode)
GLOBAL o2CellBox IS LIST().                  // each grid cell's fixed-size container (o2Cells[i] is the button inside)
GLOBAL o2GridRows IS LIST().                 // the grid's three row layouts
GLOBAL o2Gap IS 0.                           // the spacer between the page box and the grid
GLOBAL o2GapTop IS 0.                        // the spacer between the page-button row and the page box
GLOBAL o2ClickLog IS "".                  // The log file a page-button click is written to at the click (ops2q sets it; "" = none)
GLOBAL o2Press IS LIST().                    // the presses not taken yet: "N<i>" a page button, "C<i>" a grid cell
GLOBAL o2Spr IS LIST().                      // the sprite slots: LIST(label, name, x, y, on)
GLOBAL o2SprHi IS 0.                         // every slot from o2SprHi on is off (o2SprFrom loops only to it)
// THE PAINTER (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE; lib_taemdisp's TD_PAINT): the page's sprite labels (groups O2_0 .. O2_7, one a sprite nest; the text rows stay kOS's)
// drawn by C# inside kOS's window (each with its own style and content, at the rect kOS's layout gives it), their
// boxes hidden from kOS's layout. O2_PAINT: 2 PAINT is the DEFAULT since, 0 OFF, 1 CHECK (kOS draws; KSP.log [KalsPaint] worst px), 2 PAINT, 3 AB; live: o2PaintSet(m). Any failure: kOS draws
// (O2_PAINT_STATE says why).
IF NOT (DEFINED O2_PAINT) { GLOBAL O2_PAINT IS 2. }
GLOBAL O2_PAINT_STATE IS "OFF".
GLOBAL o2PaintReg IS FALSE.
GLOBAL o2PaintNames IS LIST().            // the groups registered
GLOBAL o2Nests IS LIST().                   // the sprite nests (the groups' page boxes)
GLOBAL o2SprMk IS 0.
GLOBAL o2Last IS LEXICON().                  // the last text / state written to each widget (writes only on a change)
GLOBAL o2Wide IS -1.                         // the grid's layout now: 1 = the TYPE keypad's 6 columns, 0 = 5 columns with the wide CUT OFF, 2 = 5 columns with CUT OFF split in two (PDRS: EE CAM + STOP)
GLOBAL O2_SPR_WH IS LEXICON("dot_g", LIST(2, 2), "dot_y", LIST(2, 2), "dot_w", LIST(2, 2), "dia", LIST(11, 11),
    "node", LIST(9, 9), "tri", LIST(15, 14), "tick", LIST(5, 5), "dvbar", LIST(600, 42), "dvtri", LIST(16, 15),
    "globe_fl", LIST(330, 330), "globe_wc", LIST(330, 330), "gx", LIST(13, 13), "gring", LIST(11, 11), "gsite", LIST(11, 11)).   // DEORB TGT's globe (dot_v: the 2 x 2 default)

FUNCTION o2NewBtn {                          // a button whose press adds its tag to o2Press
    PARAMETER parent, tag, txt.
    LOCAL b IS parent:ADDBUTTON(txt).
    SET b:ONCLICK TO { o2Press:ADD(tag). IF o2ClickLog <> "" AND tag:STARTSWITH("N") { LOG ROUND(MISSIONTIME, 1) + " CLICK " + tag + " (the page button reached kOS)" TO o2ClickLog. } }.   // A page-button click in the log at the click itself, before the program takes it
    IF DEFINED SAIL_ON { sailReg("o2." + tag, b). }   // SAIL may press it (lib_sail; a no-op unless a SAIL run)
    SET b:STYLE:HEIGHT TO O2_CELL_H.
    RETURN b.
}

FUNCTION o2EdgeLbl {                         // a 2 px amber bar one row high (hidden): the drop-down's left / right edge
    PARAMETER parent.
    LOCAL lb IS o2FaceLbl(parent).
    SET lb:STYLE:BG TO O2_DIR + "ddedge.png".
    SET lb:STYLE:WIDTH TO 2.
    lb:HIDE().
    RETURN lb.
}

FUNCTION o2FaceLbl {                         // a page label: the page face, the page green, rich text, no padding
    PARAMETER parent.
    LOCAL lb IS parent:ADDLABEL("").
    SET lb:STYLE:FONT TO O2_FONT.
    SET lb:STYLE:FONTSIZE TO O2_FS.
    SET lb:STYLE:TEXTCOLOR TO RGB(60 / 255, 224 / 255, 60 / 255).
    SET lb:STYLE:RICHTEXT TO TRUE.
    SET lb:STYLE:WORDWRAP TO FALSE.
    SET lb:STYLE:HSTRETCH TO FALSE.
    SET lb:STYLE:PADDING:H TO 0. SET lb:STYLE:PADDING:V TO 0.
    SET lb:STYLE:MARGIN:H TO 0. SET lb:STYLE:MARGIN:V TO 0.
    SET lb:STYLE:HEIGHT TO O2_ROW_H.
    RETURN lb.
}

FUNCTION o2Flat {                            // no margin, no padding: a container's size is its WIDTH / HEIGHT exactly
    PARAMETER w.
    SET w:STYLE:MARGIN:H TO 0. SET w:STYLE:MARGIN:V TO 0.
    SET w:STYLE:PADDING:H TO 0. SET w:STYLE:PADDING:V TO 0.
}

FUNCTION o2ColW {                            // the grid's column widths (px, each list sums to O2_W): 6 = MNVR EXEC, 5 = the other pages
    PARAMETER wide.
    IF wide { RETURN LIST(123, 123, 123, 123, 123, 123). }
    RETURN LIST(148, 148, 148, 147, 147).
}

// the window's vertical flow below the title and page row, in px, from the same constants o2DispInit builds with: the page
// box (O2_H high), the gap, the grid's three rows; margins between neighbours are 0 (set above). Returns LEXICON: navBottom, boxTop,
// topGap (boxTop - navBottom), boxBottom, gridTop, gap (gridTop - boxBottom), gridBottom, the window's slack (O2_WIN_H - gridBottom),
// content (the rows' height for n rows).
FUNCTION o2Layout {
    PARAMETER nrows IS O2_ROWS.
    LOCAL lx IS LEXICON().
    SET lx["navBottom"] TO O2_NAV_BOTTOM.
    SET lx["boxTop"] TO O2_TOP.
    SET lx["topGap"] TO lx["boxTop"] - lx["navBottom"].
    SET lx["boxBottom"] TO O2_TOP + O2_H.
    SET lx["gridTop"] TO lx["boxBottom"] + O2_GAP.
    SET lx["gap"] TO lx["gridTop"] - lx["boxBottom"].
    SET lx["gridBottom"] TO lx["gridTop"] + 3 * O2_CELL_H.
    SET lx["slack"] TO O2_WIN_H - lx["gridBottom"].
    SET lx["content"] TO O2_NEST + 1 + MAX(0, O2_PAD_Y - O2_NEST - 1) + nrows * O2_ROW_H.   // the sprite nests, the STEP nest, the inset, the rows
    RETURN lx.
}

FUNCTION o2DispInit {                        // the window (once); hidden until o2DispShow
    IF o2GuiOn { RETURN. }
    LOCAL g IS GUI(O2_W + 12).                // The page + the 6 px padding each side (was + 14: 2 px more grey on the right)
    uiDispSkin(g).
    SET g:X TO O2_X. SET g:Y TO O2_Y.
    SET g:STYLE:WIDTH TO O2_W + 12. SET g:STYLE:HEIGHT TO O2_WIN_H.
    SET g:STYLE:PADDING:H TO 6. SET g:STYLE:PADDING:V TO 0.
    LOCAL tb IS g:ADDHLAYOUT().
    SET o2Title TO tb:ADDLABEL("<b>MNVR EXEC</b>").
    uiDispTitle(tb, o2Title).
    LOCAL nv IS g:ADDHLAYOUT().
    o2Flat(nv).                               // No margin / padding on the page-button row (its children margins were pushing the "!" past the window edge)
    SET nv:STYLE:HEIGHT TO O2_CELL_H.
    SET o2NavB TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= O2_NAV:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL b IS o2NewBtn(nv, "N" + i, O2_NAV[i]).
        SET b:STYLE:MARGIN:H TO 0. SET b:STYLE:MARGIN:V TO 0.     // The skin margins are counted by the row
        SET b:STYLE:WIDTH TO (O2_W - O2_BANG_W) / O2_NAV:LENGTH.   // The 5 pages + the "!" = the page width O2_W
        o2NavB:ADD(b).
    }
    LOCAL bg IS o2NewBtn(nv, "N" + O2_NAV:LENGTH, "!").     // the FAILURES window's button (every page; the canvas's last cell of the page row)
    SET bg:STYLE:MARGIN:H TO 0. SET bg:STYLE:MARGIN:V TO 0.       // At the page's right edge
    SET bg:STYLE:WIDTH TO O2_BANG_W.
    o2NavB:ADD(bg).
    // the clear gap between the page-button row and the page box
    SET o2GapTop TO g:ADDLABEL("").
    SET o2GapTop:STYLE:HEIGHT TO O2_GAP.
    SET o2GapTop:STYLE:PADDING:V TO 0. SET o2GapTop:STYLE:MARGIN:V TO 0.
    SET o2Box TO g:ADDVLAYOUT().
    SET o2Box:STYLE:WIDTH TO O2_W. SET o2Box:STYLE:HEIGHT TO O2_H.
    SET o2Box:STYLE:BG TO O2_DIR + "page.png".
    SET o2Box:STYLE:PADDING:H TO 0. SET o2Box:STYLE:PADDING:V TO 0.
    SET o2Box:STYLE:MARGIN:V TO 0.           // the gap under the page is the spacer's alone
    // the sprite boxes first (the rows flow after them)
    SET o2Spr TO LIST().
    SET o2SprMk TO o2Box.
    SET o2Nests TO LIST().
    FROM { LOCAL k IS 0. } UNTIL k >= O2_NEST STEP { SET k TO k + 1. } DO {
        SET o2SprMk TO o2Box:ADDVLAYOUT().
        SET o2SprMk:STYLE:WIDTH TO 1. SET o2SprMk:STYLE:HEIGHT TO 1.
        SET o2SprMk:STYLE:PADDING:H TO 0. SET o2SprMk:STYLE:PADDING:V TO 0.
        SET o2SprMk:STYLE:MARGIN:H TO 0. SET o2SprMk:STYLE:MARGIN:V TO 0.
        o2Nests:ADD(o2SprMk).
        FROM { LOCAL i IS 0. } UNTIL i >= O2_NEST_N STEP { SET i TO i + 1. } DO {
            LOCAL bx IS o2SprMk:ADDVLAYOUT().
            SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
            LOCAL lb IS bx:ADDLABEL("").
            SET lb:IMAGE TO O2_DIR + "blank.png".
            SET lb:STYLE:PADDING:H TO 0. SET lb:STYLE:PADDING:V TO 0.
            SET lb:STYLE:WIDTH TO 2. SET lb:STYLE:HEIGHT TO 2.
            SET lb:STYLE:FONT TO O2_FONT. SET lb:STYLE:FONTSIZE TO 13.
            SET lb:STYLE:TEXTCOLOR TO RGB(196 / 255, 1, 196 / 255).
            SET lb:STYLE:WORDWRAP TO FALSE.
            o2Spr:ADD(LIST(lb, "", -1, -1, FALSE, k + i)).   // [5] = its flow offset (px)
        }
    }
    // the STEP readout's own nest group (a ninth, after the sprites' O2_NEST: 1 px of flow, its label placed by margins as a sprite is)
    LOCAL sn IS o2Box:ADDVLAYOUT().
    SET sn:STYLE:WIDTH TO 1. SET sn:STYLE:HEIGHT TO 1.
    SET sn:STYLE:PADDING:H TO 0. SET sn:STYLE:PADDING:V TO 0.
    SET sn:STYLE:MARGIN:H TO 0. SET sn:STYLE:MARGIN:V TO 0.
    LOCAL sb IS sn:ADDVLAYOUT().
    SET sb:STYLE:WIDTH TO 1. SET sb:STYLE:HEIGHT TO 1.
    SET o2StepL TO o2FaceLbl(sb).
    SET o2StepL:STYLE:FONTSIZE TO 12.
    SET o2StepL:STYLE:ALIGN TO "RIGHT".
    SET o2StepL:STYLE:WIDTH TO O2_STEP_W. SET o2StepL:STYLE:HEIGHT TO O2_STEP_H.
    SET o2StepL:STYLE:MARGIN:H TO O2_STEP_X. SET o2StepL:STYLE:MARGIN:V TO O2_STEP_Y - O2_NEST.
    SET o2StepBox TO o2StepL.
    LOCAL sp IS o2Box:ADDLABEL("").          // the rows' top inset less the sprite boxes' (and the STEP nest's) flow
    SET sp:STYLE:HEIGHT TO MAX(0, O2_PAD_Y - O2_NEST - 1).
    SET sp:STYLE:PADDING:V TO 0. SET sp:STYLE:MARGIN:V TO 0.
    SET o2RowW TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= O2_ROWS STEP { SET i TO i + 1. } DO {
        LOCAL hl IS o2Box:ADDHLAYOUT().
        SET hl:STYLE:HEIGHT TO O2_ROW_H.
        SET hl:STYLE:PADDING:H TO 0. SET hl:STYLE:PADDING:V TO 0.
        SET hl:STYLE:MARGIN:H TO O2_PAD_X. SET hl:STYLE:MARGIN:V TO 0.
        LOCAL a IS o2FaceLbl(hl).
        LOCAL le IS o2EdgeLbl(hl).           // the drop-down's outline, left of the cell
        LOCAL c IS o2FaceLbl(hl).
        SET c:STYLE:BG TO O2_DIR + "cur.png".
        SET c:STYLE:TEXTCOLOR TO BLACK.
        c:HIDE().
        LOCAL re IS o2EdgeLbl(hl).           // and right of it
        LOCAL d IS o2FaceLbl(hl).
        hl:ADDSPACING(-1).
        o2RowW:ADD(LIST(a, c, d, le, re)).
    }
    // the clear gap between the page box and the grid
    SET o2Gap TO g:ADDLABEL("").
    SET o2Gap:STYLE:HEIGHT TO O2_GAP.
    SET o2Gap:STYLE:PADDING:V TO 0. SET o2Gap:STYLE:MARGIN:V TO 0.
    // the grid: 3 rows of 6 fixed-size cells (the 6th column only in the TYPE keypad; elsewhere CUT OFF is cell 15 widened over columns 4 + 5)
    SET o2Cells TO LIST().
    SET o2CellBox TO LIST().
    SET o2GridRows TO LIST().
    LOCAL cw0 IS o2ColW(TRUE).
    FROM { LOCAL rw IS 0. } UNTIL rw >= 3 STEP { SET rw TO rw + 1. } DO {
        LOCAL hl IS g:ADDHLAYOUT().
        SET hl:STYLE:HEIGHT TO O2_CELL_H. SET hl:STYLE:WIDTH TO O2_W.
        o2Flat(hl).
        o2GridRows:ADD(hl).
        FROM { LOCAL i IS 0. } UNTIL i >= 6 STEP { SET i TO i + 1. } DO {
            LOCAL bx IS hl:ADDVLAYOUT().
            o2Flat(bx).
            SET bx:STYLE:WIDTH TO cw0[i]. SET bx:STYLE:HEIGHT TO O2_CELL_H.
            LOCAL b IS o2NewBtn(bx, "C" + (rw * 6 + i), "").
            SET b:STYLE:MARGIN:H TO 1. SET b:STYLE:MARGIN:V TO 0.
            SET b:STYLE:WIDTH TO cw0[i] - 2.
            o2Cells:ADD(b).
            o2CellBox:ADD(bx).
        }
    }
    SET o2Gui TO g.
    SET o2GuiOn TO TRUE.
    SET o2Wide TO -1.
    SET o2Last TO LEXICON().
    o2PaintSetup().                         // The painter (O2_PAINT; OFF by default)
}

// ---- the painter (see O2_PAINT at the top)
FUNCTION o2PaintGroups {                   // LIST(LIST(name, page box, LIST(LIST(label, flow index) ...), the page box's child count))
    LOCAL res IS LIST().                      // nest k: its O2_NEST_N sprites flow 0 .. from the nest's top (the rows are HLAYOUTs: kOS's)
    FROM { LOCAL k IS 0. } UNTIL k >= o2Nests:LENGTH STEP { SET k TO k + 1. } DO {
        LOCAL its IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= O2_NEST_N STEP { SET i TO i + 1. } DO { its:ADD(LIST(o2Spr[k * O2_NEST_N + i][0], i)). }
        res:ADD(LIST("O2_" + k, o2Nests[k], its, O2_NEST_N)).
    }
    RETURN res.
}

FUNCTION o2PaintPh {                       // a placeholder: the page box's LAST child, a 1 x 1 box + an empty 1 x 1 label
    PARAMETER pg, fl.                       //   (shown: its draw is where C# paints the page, after every slot box)
    LOCAL bx IS pg:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1. SET bx:STYLE:HEIGHT TO 1.
    LOCAL m IS bx:ADDLABEL("").
    SET m:STYLE:WIDTH TO 1. SET m:STYLE:HEIGHT TO 1.
    SET m:STYLE:PADDING:H TO 0. SET m:STYLE:PADDING:V TO 0.
    SET m:STYLE:MARGIN:H TO 0. SET m:STYLE:MARGIN:V TO 0.
    RETURN LIST(m, fl, pg).
}

FUNCTION o2PaintSetup {                    // o2DispInit's end (after every slot): O2_PAINT 0 = nothing created
    SET o2PaintReg TO FALSE.
    o2PaintNames:CLEAR().
    IF O2_PAINT = 0 { SET O2_PAINT_STATE TO "OFF". RETURN. }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        FOR gp IN o2PaintGroups() {
            IF why = "" {
                LOCAL er IS ADDONS:KALS:PAINTREG(gp[0], o2PaintPh(gp[1], gp[3]), gp[2]).
                IF er = "" { o2PaintNames:ADD(gp[0]). SET er TO ADDONS:KALS:PAINTMODE(gp[0], O2_PAINT). }
                IF er <> "" { SET why TO gp[0] + ": " + er. }
            }
        }
    }
    IF why <> "" { o2PaintOff(why). RETURN. }
    SET o2PaintReg TO TRUE.
    SET O2_PAINT_STATE TO o2PaintName(O2_PAINT).
}

FUNCTION o2PaintName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
}

// the mode switched live (SAIL's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a O2_PAINT > 0 o2DispInit
FUNCTION o2PaintSet {
    PARAMETER m.
    IF NOT o2PaintReg { RETURN "not registered (O2_PAINT was 0 at o2DispInit, or it failed: " + O2_PAINT_STATE + ")". }
    FOR gn IN o2PaintNames {
        LOCAL er IS ADDONS:KALS:PAINTMODE(gn, m).
        IF er <> "" { o2PaintOff(gn + ": " + er). RETURN er. }
    }
    SET O2_PAINT TO m.
    SET O2_PAINT_STATE TO o2PaintName(m).
    RETURN "".
}

FUNCTION o2PaintOff {                      // any failure: kOS draws from now on (C# showed the boxes, or never hid them)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") {
        FOR gn IN o2PaintNames { ADDONS:KALS:PAINTMODE(gn, 0). }
    } }
    SET O2_PAINT_STATE TO "OFF (" + why + ")".
    SET O2_PAINT TO 0.
    SET o2PaintReg TO FALSE.
}

FUNCTION o2NavSet {                          // page button i's text (the ATO / AOA page takes DEORB's slot from an ops1q hand-off); written only on a change
    PARAMETER i, txt.
    IF o2GuiOn { IF o2NavB:LENGTH > i { o2Set("navt" + i, o2NavB[i], txt). } }
}

FUNCTION o2NavBang {                         // the "!" button lit while the FAILURES window is open (in its warning colours)
    PARAMETER on.
    IF o2GuiOn { IF o2NavB:LENGTH > O2_NAV:LENGTH { o2Lit("n" + O2_NAV:LENGTH, o2NavB[O2_NAV:LENGTH], on, "WARN"). } }
}

FUNCTION o2DispShow { IF o2GuiOn { o2Gui:SHOW(). } }
FUNCTION o2DispHide { IF o2GuiOn { o2Gui:HIDE(). } }
FUNCTION o2DispClose { IF o2GuiOn { o2Gui:HIDE(). o2Gui:DISPOSE(). SET o2GuiOn TO FALSE. } }

FUNCTION o2Set {                             // a widget's text, written only on a change
    PARAMETER key, w, txt.
    IF o2Last:HASKEY(key) { IF o2Last[key] = txt { RETURN. } }
    SET o2Last[key] TO txt.
    SET w:TEXT TO txt.
}

FUNCTION o2DispTake {                        // the presses since the last call, oldest first
    LOCAL out IS o2Press:COPY.
    o2Press:CLEAR().
    RETURN out.
}

FUNCTION o2NbSp {                            // trailing spaces as no-break spaces (Unity keeps their width)
    PARAMETER s.
    LOCAL n IS 0.
    UNTIL n >= s:LENGTH OR s[s:LENGTH - 1 - n] <> " " { SET n TO n + 1. }
    IF n = 0 { RETURN s. }
    RETURN s:SUBSTRING(0, s:LENGTH - n) + "":PADLEFT(n):REPLACE(" ", CHAR(160)).
}

// the page: its title, the lit page button (-1 none: BRN PLN / FPLN / ATO / AOA), the rendered rows (o2Render's)
FUNCTION o2DispPage {
    PARAMETER title, nav, rr.
    o2Set("title", o2Title, "<b>" + title + "</b>").
    FROM { LOCAL i IS 0. } UNTIL i >= O2_NAV:LENGTH STEP { SET i TO i + 1. } DO { o2Lit("n" + i, o2NavB[i], i = nav, ""). }
    LOCAL rows IS rr[0].
    LOCAL cur IS rr[1].
    LOCAL ovr IS LEXICON().                  // the open drop-down's rows (row -> LIST(row, text, bg, pre, post))
    IF rr:LENGTH > 3 { IF rr[3]:LENGTH > 0 { FOR cl IN rr[3]["cells"] { SET ovr["r" + cl[0]] TO cl. } } }
    FROM { LOCAL i IS 0. } UNTIL i >= O2_ROWS STEP { SET i TO i + 1. } DO {
        LOCAL w IS o2RowW[i].
        IF ovr:HASKEY("r" + i) {
            LOCAL cl IS ovr["r" + i].
            o2Set("a" + i, w[0], o2NbSp(cl[3])).
            o2Set("c" + i, w[1], o2AllNb(cl[1])).
            o2Set("d" + i, w[2], cl[4]).
            o2DdBg(i, w[1], cl[2]).
            IF NOT w[1]:VISIBLE { w[1]:SHOW(). }
            o2DdEdges(w, TRUE).
        } ELSE IF i = cur[0] {
            o2Set("a" + i, w[0], o2NbSp(rr[2][0])).
            o2Set("c" + i, w[1], cur[2]).
            o2Set("d" + i, w[2], rr[2][1]).
            o2DdBg(i, w[1], "a").
            IF NOT w[1]:VISIBLE { w[1]:SHOW(). }
            o2DdEdges(w, FALSE).
        } ELSE {
            IF w[1]:VISIBLE { w[1]:HIDE(). }
            o2Set("a" + i, w[0], rows[i]).
            o2Set("d" + i, w[2], "").
            o2DdEdges(w, FALSE).
        }
    }
}

// A page whose GPC has failed: its rows empty, its views off (the page box shows the big X, ops2q's o2qGpcX); the title and the page keys stay
FUNCTION o2DispBlank {
    PARAMETER title, nav.
    LOCAL rows IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= O2_ROWS STEP { SET i TO i + 1. } DO { rows:ADD(""). }
    o2DispPage(title, nav, LIST(rows, LIST(-1, 0, ""), LIST("", ""))).
    o2SprFrom(0).
}

// a text with every space a no-break space (the drop-down's cells keep their padding's width)
FUNCTION o2AllNb { PARAMETER s. RETURN s:REPLACE(" ", CHAR(160)). }

// the drop-down cell's background (the cursor row amber, else black with the outline's stripes), written on a change
FUNCTION o2DdBg {
    PARAMETER i, w, bg.
    LOCAL nm IS "cur".
    IF bg = "k" { SET nm TO "ddk". }
    IF bg = "kt" { SET nm TO "ddkt". }
    IF bg = "kb" { SET nm TO "ddkb". }
    IF bg = "tb" { SET nm TO "ddtb". }
    LOCAL key IS "b" + i.
    IF o2Last:HASKEY(key) { IF o2Last[key] = nm { RETURN. } }
    SET o2Last[key] TO nm.
    SET w:STYLE:BG TO O2_DIR + nm + ".png".
}

FUNCTION o2DdEdges {                         // a row's two outline bars shown / hidden
    PARAMETER w, on.
    IF w:LENGTH < 5 { RETURN. }
    IF w[3]:VISIBLE <> on { IF on { w[3]:SHOW(). w[4]:SHOW(). } ELSE { w[3]:HIDE(). w[4]:HIDE(). } }
}

// the grid: mode "PAGE" / "RHC" / "TYPE"; the layout follows the mode (TYPE = the 6-column keypad, the others 5 columns with CUT OFF
// as cell 15 widened over columns 4 + 5, cells 16 and 17 hidden); `wide` is kept for the callers' signature and ignored. The STEP text goes
// to the small label in the page's corner ('' = nothing shown); armOn / execOn are unused (ARM / EXEC are page items), cutOn = CUT OFF lit
FUNCTION o2DispGrid {
    PARAMETER mode, wide, stepTxt, armOn IS FALSE, execOn IS FALSE, cutOn IS FALSE, split IS FALSE.
    LOCAL t IS LIST().
    IF mode = "TYPE" {
        SET t TO LIST("7", "8", "9", "-", "CANCEL", "", "4", "5", "6", ".", "BKSP", "", "1", "2", "3", "0", "ENT", "CUT OFF").
    } ELSE IF mode = "RHC" {
        SET t TO LIST("Q  " + CHAR(8722), "W  " + CHAR(8593), "E  +", "INPUT PAGE", "INPUT RHC", "",
            "A  " + CHAR(8592), "SPACE  ENT", "D  " + CHAR(8594), "AG4  TYPE", "CANCEL", "",
            "STEP x10", "S  " + CHAR(8595), "STEP /10", "CUT OFF", "", "").
    } ELSE {
        SET t TO LIST(CHAR(8722), CHAR(8593), "+", "INPUT PAGE", "INPUT RHC", "",
            CHAR(8592), "ENT", CHAR(8594), "TYPE", "CANCEL", "",
            "STEP x10", CHAR(8595), "STEP /10", "CUT OFF", "", "").
    }
    LOCAL ty IS mode = "TYPE".
    SET split TO split AND NOT ty.
    IF split { SET t[15] TO "EE CAM". SET t[16] TO "STOP". }      // PDRS: the CUT OFF slot split in two
    FROM { LOCAL i IS 0. } UNTIL i >= 18 STEP { SET i TO i + 1. } DO {
        LOCAL b IS o2Cells[i].
        LOCAL bx IS o2CellBox[i].
        LOCAL show IS o2CellShow(ty, i, split).
        IF show { o2Set("g" + i, b, t[i]). }
        IF bx:VISIBLE <> show { IF show { bx:SHOW(). } ELSE { bx:HIDE(). } }
    }
    o2GridW(ty, split).
    LOCAL sv IS NOT ty.
    IF o2StepBox:VISIBLE <> sv { IF sv { o2StepBox:SHOW(). } ELSE { o2StepBox:HIDE(). } }
    o2Set("step", o2StepL, stepTxt).
    o2GridLit(mode, cutOn, split).
}

// is grid cell i drawn? (ARM / EXEC, cells 5 and 11, are page items; the TYPE keypad has 5 columns and CUT OFF in the sixth (cell 17);
// the other modes have 5 columns with CUT OFF as cell 15 and cell 16 under it hidden)
FUNCTION o2CellShow {
    PARAMETER ty, i, split IS FALSE.         // split = PDRS: cell 16 is shown (STOP) beside cell 15 (EE CAM)
    LOCAL col IS MOD(i, 6).
    IF ty { RETURN col < 5 OR i = 17. }
    RETURN col < 5 AND (i <> 16 OR split).
}

// the lights: INPUT PAGE / INPUT RHC lit by the mode, CUT OFF lit (orange, WARN) when the burn burns: it is cell 15 in the modes
// with the widened button and cell 17 in the TYPE keypad (the other one has its own plain look)
GLOBAL o2InLock IS FALSE.                    // INPUT RHC greyed out (ops2q sets it every draw: MAN AUG, CSS DAP, PROX OPS, STICK ORB hold the stick)
FUNCTION o2GridLit {
    PARAMETER mode, cutOn, split IS FALSE.   // split: cell 15 EE CAM lit (cutOn) like a toggle, cell 16 STOP always in the warning colours
    LOCAL ty IS mode = "TYPE".
    o2Lit("g3", o2Cells[3], NOT ty AND mode = "PAGE", "").
    o2Lit("g4", o2Cells[4], NOT ty AND mode = "RHC", CHOOSE "DIM" IF o2InLock AND NOT ty ELSE "").     // greyed while locked
    IF split AND NOT ty {
        o2Lit("g15", o2Cells[15], cutOn, "").
        o2Lit("g16", o2Cells[16], FALSE, "WARN").
        o2Lit("g17", o2Cells[17], FALSE, "WARN").
    } ELSE IF ty {
        o2Lit("g15", o2Cells[15], FALSE, "").
        o2Lit("g17", o2Cells[17], cutOn, "WARN").
    } ELSE {
        o2Lit("g15", o2Cells[15], cutOn, "WARN").
        o2Lit("g17", o2Cells[17], FALSE, "WARN").
    }
}

// the grid's column widths when its layout changes (o2DispGrid's; the C# draw's too). `wide` = the TYPE keypad's 6 columns;
// else 5 columns and cell 15 as wide as columns 4 + 5
FUNCTION o2GridW {
    PARAMETER wide, split IS FALSE.
    LOCAL lay IS CHOOSE 1 IF wide ELSE (CHOOSE 2 IF split ELSE 0).
    IF lay <> o2Wide {                       // the column widths of this layout (every container, every row)
        LOCAL cws IS o2ColW(wide).
        FROM { LOCAL i IS 0. } UNTIL i >= 18 STEP { SET i TO i + 1. } DO {
            LOCAL w IS cws[MIN(MOD(i, 6), cws:LENGTH - 1)].
            IF i = 15 AND NOT wide AND NOT split { SET w TO cws[3] + cws[4]. }
            SET o2CellBox[i]:STYLE:WIDTH TO w.
            SET o2Cells[i]:STYLE:WIDTH TO w - 2.
        }
        SET o2Wide TO lay.
    }
}

// may KalsCoproc draw this frame? An older KalsCoproc has no drop-down list in its page draw (no O2DD suffix): kOS draws the
// frames while a list is open, and ONE frame more after it closed. That frame is kOS's closed page, which gives back what the
// list's draw changed (the cursor cell's background, the outline bars) and the older KalsCoproc's draw does not know. From the
// next frame on KalsCoproc draws as before. (Without the extra frame the TO box stayed black on black and the bars stayed.)
GLOBAL o2KosDd IS FALSE.                     // the last frame was kOS's with a list open: the next frame is kOS's too
FUNCTION o2CsOk {
    PARAMETER split IS FALSE.                // the PDRS page's split pad (EE CAM + STOP): only a KalsCoproc with O2PDRS draws it
    LOCAL ok IS TRUE.
    IF ADDONS:HASSUFFIX("KALS") {            // an older KalsCoproc draws the grid with CUT OFF in the sixth column: kOS draws
        IF ADDONS:KALS:AVAILABLE AND ADDONS:KALS:HASSUFFIX("O2DRAW") AND NOT ADDONS:KALS:HASSUFFIX("O2CUT") { RETURN FALSE. }
        IF split AND ADDONS:KALS:AVAILABLE AND ADDONS:KALS:HASSUFFIX("O2DRAW") AND NOT ADDONS:KALS:HASSUFFIX("O2PDRS") { RETURN FALSE. }
    }
    IF o2DdOn {
        SET ok TO FALSE.
        IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:AVAILABLE { IF ADDONS:KALS:HASSUFFIX("O2DD") { SET ok TO TRUE. } } }
        IF NOT ok { SET o2KosDd TO TRUE. }
    } ELSE IF o2KosDd {
        SET o2KosDd TO FALSE.
        SET ok TO FALSE.
    }
    RETURN ok.
}

// the page and the grid drawn by KalsCoproc (coproc/Od.cs: o2Render + o2DispPage's title / rows + o2DispGrid's texts and
// boxes, the same writes); the lights (o2Lit) and the widths stay here. FALSE = kOS draws (no O2DRAW in the DLL, or it failed)
GLOBAL o2Cs IS 0.                            // 0 not tried yet, 1 C# draws, -1 kOS draws
FUNCTION o2CsDraw {
    PARAMETER pg, title, nav, mode, wide, stepTxt, armOn, execOn, cutOn, split IS FALSE.
    IF o2Cs = 0 {
        SET o2Cs TO -1.
        IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:AVAILABLE AND ADDONS:KALS:HASSUFFIX("O2DRAW") {
            LOCAL su IS ADDONS:KALS:O2SETUP(LEXICON("title", o2Title, "rows", o2RowW, "cells", o2Cells, "boxes", o2CellBox,
                "stepbox", o2StepBox, "stepl", o2StepL, "c", O2_C, "last", o2Last, "nrows", O2_ROWS)).
            IF su = "" { SET o2Cs TO 1. } ELSE { kmSay("OPS2: KALSCOPROC'S PAGE DRAW NOT SET UP (" + su + "); KOS DRAWS", "C"). }
        } }
    }
    IF o2Cs < 0 { RETURN FALSE. }
    LOCAL dr IS ADDONS:KALS:O2DRAW(pg, LEXICON("title", title, "cur", o2CurFld(pg), "typ", o2Typ, "buf", o2Buf,
        "mode", mode, "wide", mode = "TYPE", "step", stepTxt, "dd", o2DdLayout(pg), "split", split AND mode <> "TYPE")).
    IF dr <> "" { SET o2Cs TO -1. kmSay("OPS2: KALSCOPROC'S PAGE DRAW FAILED (" + dr + "); KOS DRAWS", "C"). RETURN FALSE. }
    FROM { LOCAL i IS 0. } UNTIL i >= O2_NAV:LENGTH STEP { SET i TO i + 1. } DO { o2Lit("n" + i, o2NavB[i], i = nav, ""). }
    o2GridW(mode = "TYPE", split AND mode <> "TYPE").
    o2GridLit(mode, cutOn, split).
    RETURN TRUE.
}

// a button drawn lit (the switch on: an amber edge, amber text) or not, in its own colours (base "" grey text,
// "GO" the green ARM / EXEC, "WARN" the orange CUT OFF); kOS toggles are not used: setting PRESSED echoes a click
FUNCTION o2Lit {
    PARAMETER key, b, on, base.
    LOCAL st IS (CHOOSE "1" IF on ELSE "0") + base.
    IF o2Last:HASKEY("L" + key) { IF o2Last["L" + key] = st { RETURN. } }
    SET o2Last["L" + key] TO st.
    IF NOT uiDispOn() { RETURN. }
    IF base = "DIM" { uiStates(b:STYLE, "gp_btn", "gp_btn", "gp_btn", RGB(0.38, 0.38, 0.38)). RETURN. }     // greyed out (INPUT RHC while something else reads the stick)
    IF on { uiStates(b:STYLE, "gp_tog_on", "gp_tog_on_hov", "gp_btn_act", UI_ACCENT_RGB). RETURN. }
    IF base = "WARN" { uiStates(b:STYLE, "gp_warn", "gp_warn_hov", "gp_btn_act", UI_WARN_RGB). RETURN. }
    uiStates(b:STYLE, "gp_btn", "gp_btn_hov", "gp_btn_act", CHOOSE O2_GO_RGB IF base = "GO" ELSE UI_TEXT_RGB).
}

// the cell's key in the mode (o2Key's names; "" = none)
FUNCTION o2CellKey {
    PARAMETER mode, i.
    IF mode = "TYPE" {
        LOCAL k IS LIST("7", "8", "9", "-", "CAN", "", "4", "5", "6", ".", "BKSP", "", "1", "2", "3", "0", "ENT", "CUT").
        RETURN k[i].
    }
    // - left, + right, so Q (-) and E (+) sit where they are on a keyboard
    LOCAL k IS LIST("MI", "UP", "PL", "INPAGE", "INRHC", "", "LF", "ENT", "RT", "TYPE", "CAN", "",
        "X10", "DN", "D10", "CUT", "STOP", "").    // cell 16 is shown only on PDRS (STOP, beside EE CAM = "CUT")
    RETURN k[i].
}

// ---- the sprites (the orbit view): slot k at page px (x, y) = the sprite's centre; "" = off. Text sprites: o2SprTxt.
FUNCTION o2SprWH {
    PARAMETER nm.
    IF O2_SPR_WH:HASKEY(nm) { RETURN O2_SPR_WH[nm]. }
    IF nm:STARTSWITH("earth_") { LOCAL rp IS nm:SUBSTRING(6, nm:LENGTH - 6):TONUMBER(40). RETURN LIST(2 * rp + 4, 2 * rp + 4). }
    IF nm:STARTSWITH("pcg_") OR nm:STARTSWITH("pcr_") { RETURN LIST(40, 172). }   // OMS/RCS's Pc tapes, pointers, lamps, legend glyphs
    IF nm:STARTSWITH("pcp_") { RETURN LIST(8, 11). }
    IF nm:STARTSWITH("lamp_") { RETURN LIST(51, 18). }
    IF nm:STARTSWITH("lgd_") { RETURN LIST(7, 10). }
    RETURN LIST(2, 2).
}

FUNCTION o2SprPut {
    PARAMETER k, nm, x, y.
    IF k >= o2Spr:LENGTH { RETURN. }
    LOCAL sl IS o2Spr[k].
    IF nm = "" { o2SprOff(k). RETURN. }
    LOCAL wh IS o2SprWH(nm).
    LOCAL xx IS FLOOR(x - wh[0] / 2 + 0.5).
    LOCAL yy IS FLOOR(y - wh[1] / 2 + 0.5).
    IF sl[1] = nm AND sl[2] = xx AND sl[3] = yy AND sl[4] { RETURN. }
    LOCAL lb IS sl[0].
    IF sl[1] <> nm {
        SET lb:TEXT TO "".
        SET lb:IMAGE TO O2_DIR + nm + ".png".
        SET lb:STYLE:WIDTH TO wh[0]. SET lb:STYLE:HEIGHT TO wh[1].
        SET sl[1] TO nm.
    }
    SET lb:STYLE:MARGIN:H TO MAX(0, xx).
    SET lb:STYLE:MARGIN:V TO MAX(0, yy - sl[5]).
    SET sl[2] TO xx. SET sl[3] TO yy. SET sl[4] TO TRUE.
    IF k >= o2SprHi { SET o2SprHi TO k + 1. }
}

// MNVR EXEC's DV slider. The owner 11-05 00:39 "Misaligned.": the yellow pointer's tip sat 2 px left of the bar's 0 tick before the
// burn (and 1 px right of the CO tick at the cutoff): the line start / length (81.4 / 403.6) were read off a preview, not off the
// sprite. Measured off o2_bg/dvbar.png (tests/o2dvbar_pngcheck.py proves it): the 0 tick is columns 68-69 (centre 69.0), the CO tick
// columns 469-470 (centre 470.0) -> the pointer's tip runs 83.0 .. 484.0 in page px (the bar's left edge is at page x 14); the
// pointer o2_bg/dvtri.png (16 x 15) has its tip on its centre column (8.0) and its bottom row (the line's top edge is page y 138).
GLOBAL O2_DV_BX IS 14.                       // the bar sprite's left edge (page px)
GLOBAL O2_DV_BY IS 115.                      // its top edge
GLOBAL O2_DV_T0 IS 69.                       // the 0 tick's centre, in the bar sprite's px
GLOBAL O2_DV_T1 IS 470.                      // the CO tick's centre
GLOBAL O2_DV_TIPX IS 8.                      // the pointer's tip, in the pointer sprite's px (its centre column)
GLOBAL O2_DV_X0 IS 14 + 69.                  // the 0 tick, page px
GLOBAL O2_DV_L IS 470 - 69.                  // 0 tick .. CO tick
GLOBAL O2_DV_Y IS 115 + 24.                  // the line's y
FUNCTION o2DvTipX {                          // the page x the pointer's tip is drawn at: round(x0 + length * gained / total), 0 .. 1 clamped
    PARAMETER tot, got.
    LOCAL fr IS CHOOSE 0 IF tot < 0.05 ELSE MAX(0, MIN(1, got / tot)).
    RETURN FLOOR(O2_DV_X0 + O2_DV_L * fr + 0.5).
}
FUNCTION o2DvPtr {                           // slot k: the pointer (its tip at o2DvTipX, its bottom row on the line)
    PARAMETER k, tot, got.
    o2SprPut(k, "dvtri", o2DvTipX(tot, got) - O2_DV_TIPX + 8, O2_DV_Y - 8).
}

FUNCTION o2SprTxt {                          // a text sprite: txt centred at (x, y), in colour hex
    PARAMETER k, txt, x, y, hex IS "#c4ffc4", w IS 120.
    IF k >= o2Spr:LENGTH { RETURN. }
    LOCAL sl IS o2Spr[k].
    IF txt = "" { o2SprOff(k). RETURN. }
    LOCAL key IS "@" + hex + txt.             // "@" is no letter: kOS STARTSWITH / = ignore case, so a "T" key matched the image names "tri" / "tick"
    LOCAL xx IS FLOOR(x - w / 2 + 0.5).
    LOCAL yy IS FLOOR(y - 9 + 0.5).
    IF sl[1] = key AND sl[2] = xx AND sl[3] = yy AND sl[4] { RETURN. }
    LOCAL lb IS sl[0].
    IF sl[1] <> key {
        IF NOT sl[1]:STARTSWITH("@") { SET lb:IMAGE TO O2_DIR + "blank.png". }
        SET lb:STYLE:RICHTEXT TO TRUE.
        SET lb:STYLE:ALIGN TO "CENTER".
        SET lb:TEXT TO "<color=" + hex + ">" + txt + "</color>".
        SET lb:STYLE:WIDTH TO w. SET lb:STYLE:HEIGHT TO 18.
        SET sl[1] TO key.
    }
    SET lb:STYLE:MARGIN:H TO MAX(0, xx).
    SET lb:STYLE:MARGIN:V TO MAX(0, yy - sl[5]).
    SET sl[2] TO xx. SET sl[3] TO yy. SET sl[4] TO TRUE.
    IF k >= o2SprHi { SET o2SprHi TO k + 1. }
}

FUNCTION o2SprOff {
    PARAMETER k.
    LOCAL sl IS o2Spr[k].
    IF NOT sl[4] { RETURN. }
    LOCAL lb IS sl[0].
    SET lb:TEXT TO "".
    SET lb:IMAGE TO O2_DIR + "blank.png".
    SET lb:STYLE:WIDTH TO 2. SET lb:STYLE:HEIGHT TO 2.
    SET lb:STYLE:MARGIN:H TO 0. SET lb:STYLE:MARGIN:V TO 0.
    SET sl[1] TO "". SET sl[4] TO FALSE.
}

FUNCTION o2SprFrom {                         // every slot from k on off (a view drew fewer this time)
    PARAMETER k.
    LOCAL hi IS MIN(o2SprHi, o2Spr:LENGTH).    // the slots from o2SprHi on are off already
    FROM { LOCAL i IS k. } UNTIL i >= hi STEP { SET i TO i + 1. } DO { IF o2Spr[i][4] { o2SprOff(i). } }
    IF k < o2SprHi { SET o2SprHi TO MAX(k, 0). }
}
