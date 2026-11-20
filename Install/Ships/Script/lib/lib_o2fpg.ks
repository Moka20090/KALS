// lib_o2fpg.ks -- ops2q's FPLN page: the flight-plan tree (lib_o2fpln.ks) drawn as TEXT on the 84 x 20 page. THE VIEW SCROLLS BOTH WAYS: the tree is a grid (one column per leaf in tree order, one row per burn), the page shows 5 columns x 3 burn rows of it (a node is 3 lines in
// a 16-character column: its name (+ P for a Principia burn), its type and dV, its orbit after it as HA x HP in km); the view FOLLOWS THE CURSOR (the
// arrows move node to node, the window scrolls when the cursor leaves it) and 'BR a-b OF n  BURN a-b OF m' + edge marks say what lies beyond. A parent
// sits centred over its children's columns with a bus line (a fan); the active path is the brightest. Node 0 is the row above the first burn row.
//  THE CURSOR: on the tree the arrows go node to node (up = parent, down = first child, left / right = along the row across
//  parents); ENT on a burn SELECTS it and moves the cursor to the action row (SET PATH / PLAN FROM HERE / DELETE / COPY); on the action row left / right
//  move across the four, ENT runs the item on the selected burn, UP returns the cursor to the selected burn on the tree.
//  Ids: a node's cursor stop is "fn<id>"; the actions are fset, fplan, fdel, fcopy (ops2q's o2qAct runs them).
//  Needs lib_o2ui.ks and lib_o2fpln.ks (and lib_o2orb.ks for the tree's own calls).
GLOBAL O2G_COLS IS 5.                        // leaf columns shown
GLOBAL O2G_ROWS IS 3.                        // burn rows shown
GLOBAL O2G_CW IS 16.                         // characters a column
GLOBAL O2G_X0 IS 2.                          // the first column's first character
GLOBAL o2gC0 IS 0.                           // the first leaf column shown
GLOBAL o2gR0 IS 1.                           // the first burn row (depth) shown

FUNCTION o2gNodeId {                         // "fn12" -> 12, -1 when it is not a node's cursor stop
    PARAMETER cid.
    IF NOT cid:STARTSWITH("fn") { RETURN -1. }
    RETURN cid:SUBSTRING(2, cid:LENGTH - 2):TONUMBER(-1).
}
FUNCTION o2gIsAct { PARAMETER cid. RETURN LIST("fset", "fplan", "fdel", "fcopy"):CONTAINS(cid). }

FUNCTION o2gU { PARAMETER lay, id. RETURN (lay["c0"][id] + lay["c1"][id] + 1) / 2. }          // a node's centre in leaf units
FUNCTION o2gShown {                          // the node is in the window (its cell fits)
    PARAMETER lay, id.
    LOCAL d IS lay["dp"][id].
    IF d = 0 { RETURN o2gR0 = 1. }           // node 0 is drawn centred over whatever depth-1 burns the window shows
    LOCAL u IS o2gU(lay, id) - o2gC0.
    IF u < 0.5 OR u > O2G_COLS - 0.5 { RETURN FALSE. }
    RETURN d >= o2gR0 AND d <= o2gR0 + O2G_ROWS - 1.
}
FUNCTION o2gCol { PARAMETER lay, id. RETURN O2G_X0 + ROUND((o2gU(lay, id) - o2gC0) * O2G_CW). }   // a node's centre character

FUNCTION o2gFollow {                         // scroll the window just enough to show the node
    PARAMETER id.
    IF NOT o2flLive(id) { RETURN. }
    LOCAL lay IS o2flLay().
    LOCAL d IS lay["dp"][id].
    IF d = 0 { SET o2gR0 TO 1. RETURN. }     // the columns stay where they are (node 0 is centred over what the window shows)
    IF d < o2gR0 { SET o2gR0 TO d. }
    ELSE IF d > o2gR0 + O2G_ROWS - 1 { SET o2gR0 TO d - O2G_ROWS + 1. }
    LOCAL u IS o2gU(lay, id).
    IF u - 0.5 < o2gC0 { SET o2gC0 TO FLOOR(u - 0.5 + 0.001). }
    ELSE IF u + 0.5 > o2gC0 + O2G_COLS { SET o2gC0 TO CEILING(u + 0.5 - 0.001) - O2G_COLS. }
    SET o2gC0 TO MAX(0, MIN(o2gC0, lay["n"] - O2G_COLS)).
    SET o2gR0 TO MAX(1, MIN(o2gR0, MAX(1, lay["md"] - O2G_ROWS + 1))).
}

FUNCTION o2gCh {                             // the box character of a cell's four arms
    PARAMETER cu, cdn, cl, cr.
    IF cu AND cdn AND cl AND cr { RETURN CHAR(9532). }
    IF cdn AND cl AND cr { RETURN CHAR(9516). }
    IF cu AND cl AND cr { RETURN CHAR(9524). }
    IF cu AND cdn AND cr { RETURN CHAR(9500). }
    IF cu AND cdn AND cl { RETURN CHAR(9508). }
    IF cdn AND cr { RETURN CHAR(9484). }
    IF cdn AND cl { RETURN CHAR(9488). }
    IF cu AND cr { RETURN CHAR(9492). }
    IF cu AND cl { RETURN CHAR(9496). }
    IF cl OR cr { RETURN CHAR(9472). }
    IF cu OR cdn { RETURN CHAR(9474). }
    RETURN " ".
}

FUNCTION o2gDvTot { PARAMETER nd. RETURN SQRT(nd["dv"][0] ^ 2 + nd["dv"][1] ^ 2 + nd["dv"][2] ^ 2). }

FUNCTION o2gCenter {                         // the text centred on character column cc
    PARAMETER pg, row, cc, txt, cls.
    o2Seg(pg, row, MAX(0, cc - FLOOR(txt:LENGTH / 2)), txt, cls).
}

// the tree on rows 1 .. 15 and the action row 16 of pg. opts: met0 (the UT of MET 0), rad (the body's radius, m), live (node 0's orbit as text)
FUNCTION o2gTree {
    PARAMETER pg, opts.
    LOCAL lay IS o2flLay().
    IF NOT o2flLive(o2flSel) { SET o2flSel TO 0. }
    LOCAL curN IS o2gNodeId(o2Cur).
    IF curN >= 0 AND NOT o2flLive(curN) { SET o2Cur TO "fn" + o2flSel. SET curN TO o2flSel. }
    IF curN < 0 AND NOT o2gIsAct(o2Cur) { SET o2Cur TO "fn" + o2flSel. SET curN TO o2flSel. }
    o2gFollow(CHOOSE curN IF curN >= 0 ELSE o2flSel).
    LOCAL pth IS o2flPath().
    LOCAL ps IS "".
    FOR p IN pth { SET ps TO ps + (CHOOSE "" IF ps = "" ELSE " > ") + o2flName(p). }
    IF ps:LENGTH > 40 { SET ps TO "..." + ps:SUBSTRING(ps:LENGTH - 37, 37). }
    o2Seg(pg, 1, 1, "PATH"). o2Seg(pg, 1, 6, ps, "S").
    LOCAL b1 IS o2gC0 + 1. LOCAL b2 IS MIN(o2gC0 + O2G_COLS, lay["n"]).
    LOCAL d2 IS MIN(o2gR0 + O2G_ROWS - 1, lay["md"]).
    o2Seg(pg, 1, 54, "BR " + b1 + "-" + b2 + " OF " + lay["n"] + "  BURN " + (CHOOSE o2gR0 IF lay["md"] > 0 ELSE 0) + "-" + d2 + " OF " + lay["md"]).
    // the rows: the connector row above each burn row, then the burn row's 3 lines
    LOCAL kidCols IS LEXICON().              // parent id -> the visible kids' centre characters
    FROM { LOCAL k IS 0. } UNTIL k >= O2G_ROWS STEP { SET k TO k + 1. } DO {
        LOCAL dk IS o2gR0 + k.
        LOCAL r0 IS 4 + 4 * k.
        FOR id IN lay["ord"] {
            IF lay["dp"][id] = dk AND o2gShown(lay, id) {
                LOCAL cc IS o2gCol(lay, id).
                LOCAL nd IS o2flN[id].
                LOCAL onp IS pth:CONTAINS(id).
                LOCAL nm IS o2flName(id) + (CHOOSE " P" IF nd["src"] = "P" ELSE "").
                LOCAL c1 IS CHOOSE "S" IF onp ELSE "L".
                LOCAL c2 IS CHOOSE "V" IF onp ELSE "L".
                o2Seg(pg, r0, MAX(0, cc - FLOOR(nm:LENGTH / 2)), nm, c1).
                o2Fld(pg, "fn" + id, "A", r0, MAX(0, cc - FLOOR(nm:LENGTH / 2)), nm, TRUE).
                o2gCenter(pg, r0 + 1, cc, nd["ty"] + " " + o2Fx(o2gDvTot(nd), 1), c2).
                o2gCenter(pg, r0 + 2, cc, o2flOrb(id, opts["rad"]):REPLACE("x", " x "), c2).
                IF NOT kidCols:HASKEY(nd["par"]) { SET kidCols[nd["par"]] TO LIST(). }
                kidCols[nd["par"]]:ADD(cc).
            }
        }
    }
    // node 0 above the first burn row (the live orbit); centred over the visible depth-1 burns
    LOCAL rootCol IS O2G_X0 + FLOOR(O2G_COLS * O2G_CW / 2).
    IF o2gR0 = 1 {
        IF kidCols:HASKEY(0) {
            LOCAL sm IS 0.
            FOR x IN kidCols[0] { SET sm TO sm + x. }
            SET rootCol TO ROUND(sm / kidCols[0]:LENGTH).
        }
        LOCAL rt IS "0  " + opts["live"].
        o2Seg(pg, 2, rootCol, rt, CHOOSE "S" IF pth:CONTAINS(0) ELSE "L").
        o2Fld(pg, "fn0", "A", 2, rootCol, "0", TRUE).
    }
    // the connectors
    FROM { LOCAL k IS 0. } UNTIL k >= O2G_ROWS STEP { SET k TO k + 1. } DO {
        LOCAL dk IS o2gR0 + k.
        LOCAL aU IS LIST(). LOCAL aD IS LIST(). LOCAL aL IS LIST(). LOCAL aR IS LIST().
        FROM { LOCAL i IS 0. } UNTIL i >= 84 STEP { SET i TO i + 1. } DO { aU:ADD(FALSE). aD:ADD(FALSE). aL:ADD(FALSE). aR:ADD(FALSE). }
        LOCAL any IS FALSE.
        FOR id IN lay["ord"] {
            IF lay["dp"][id] = dk - 1 AND kidCols:HASKEY(id) {
                LOCAL cols IS kidCols[id].
                LOCAL pc IS -1.
                IF id = 0 { IF o2gR0 = 1 { SET pc TO rootCol. } }
                ELSE IF o2gShown(lay, id) { SET pc TO o2gCol(lay, id). }
                LOCAL lo IS cols[0]. LOCAL hi IS cols[cols:LENGTH - 1].
                IF pc >= 0 { SET lo TO MIN(lo, pc). SET hi TO MAX(hi, pc). SET aU[pc] TO TRUE. }
                FROM { LOCAL x IS lo. } UNTIL x > hi STEP { SET x TO x + 1. } DO {
                    IF x > lo { SET aL[x] TO TRUE. }
                    IF x < hi { SET aR[x] TO TRUE. }
                }
                FOR x IN cols { SET aD[x] TO TRUE. }
                SET any TO TRUE.
            }
        }
        IF any {
            LOCAL s IS "".
            FROM { LOCAL i IS 0. } UNTIL i >= 84 STEP { SET i TO i + 1. } DO { SET s TO s + o2gCh(aU[i], aD[i], aL[i], aR[i]). }
            o2Seg(pg, 3 + 4 * k, 0, s, "L").
        }
    }
    // the edge marks: more lies beyond
    IF o2gC0 > 0 { o2Seg(pg, 8, 0, CHAR(9668), "Y"). }
    IF o2gC0 + O2G_COLS < lay["n"] { o2Seg(pg, 8, 83, CHAR(9658), "Y"). }
    IF o2gR0 > 1 { o2Seg(pg, 4, 83, CHAR(9650), "Y"). }
    IF o2gR0 + O2G_ROWS - 1 < lay["md"] { o2Seg(pg, 14, 83, CHAR(9660), "Y"). }
    // SEL: the selected burn
    LOCAL sn IS o2flN[o2flSel].
    o2Seg(pg, 15, 1, "SEL"). o2Seg(pg, 15, 5, o2flName(o2flSel), "S").
    IF o2flSel = 0 {
        o2Seg(pg, 15, 11, "NOW", "L"). o2Seg(pg, 15, 52, "ORBIT"). o2Read(pg, 15, 58, opts["live"]). o2Seg(pg, 15, 70, "km").
    } ELSE {
        o2Seg(pg, 15, 11, sn["ty"], "V").
        o2Seg(pg, 15, 18, "TIG"). o2Read(pg, 15, 22, o2Met(sn["ut"] - sn["tb"] / 2 - opts["met0"])).
        o2Seg(pg, 15, 36, "DV"). o2Read(pg, 15, 39, o2F(o2gDvTot(sn), 6, 1)). o2Seg(pg, 15, 46, "m/s").
        o2Seg(pg, 15, 52, "AFTER"). o2Read(pg, 15, 58, o2flOrb(o2flSel, opts["rad"]):REPLACE("x", " x ")). o2Seg(pg, 15, 70, "km").
    }
    // the action row
    LOCAL isP IS sn["src"] = "P".
    o2Act(pg, "fset", 17, 4, "SET PATH", TRUE).
    o2Act(pg, "fplan", 17, 15, "PLAN FROM HERE", o2flSel = 0 OR sn["el"]:HASKEY("ra")).
    o2Act(pg, "fdel", 17, 32, "DELETE", o2flSel > 0 AND NOT isP).
    o2Act(pg, "fcopy", 17, 41, "COPY " + CHAR(8594) + " BRN PLN", o2flSel > 0).   // Any burn node (P or own O), the root never
}

// the cursor's arrow on this page; TRUE when handled here (the tree's rules), FALSE leaves it to o2Move (the action row's left / right)
FUNCTION o2gMove {
    PARAMETER key.
    LOCAL cid IS o2gNodeId(o2Cur).
    IF cid >= 0 {
        IF NOT o2flLive(cid) { SET cid TO o2flSel. }
        LOCAL nx IS cid.
        IF key = "UP" { SET nx TO o2flUpOf(cid). }
        ELSE IF key = "DN" { SET nx TO o2flDownOf(cid). }
        ELSE IF key = "LF" { SET nx TO o2flSide(cid, -1). }
        ELSE IF key = "RT" { SET nx TO o2flSide(cid, 1). }
        ELSE { RETURN FALSE. }
        SET o2Cur TO "fn" + nx.
        o2gFollow(nx).
        RETURN TRUE.
    }
    IF o2gIsAct(o2Cur) AND key = "UP" {
        SET o2Cur TO "fn" + o2flSel.
        o2gFollow(o2flSel).
        RETURN TRUE.
    }
    RETURN FALSE.
}

FUNCTION o2gEnter {                          // ENT on a burn: it is the selected one and the cursor goes to the action row
    PARAMETER id.
    IF NOT o2flLive(id) { RETURN. }
    SET o2flSel TO id.
    SET o2Cur TO "fset".
    SET o2flVer TO o2flVer + 1.
}

FUNCTION o2gOpen {                           // the page opens with the cursor on a burn (BRN PLN's FPLN STATE ENT: its burn)
    PARAMETER id.
    IF NOT o2flLive(id) { SET id TO 0. }
    SET o2flSel TO id.
    SET o2Cur TO "fn" + id.
    o2gFollow(id).
}
