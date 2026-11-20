// lib_o2ui.ks -- ops2q's PAGE MODEL: what a page shows and what the cursor does, with no GUI and no vessel (so the
// kOS VM runs it: tests/o2ui_selftest.ks).
// A page is built afresh every draw by its host (ops2q's o2Pg* functions) as segments and fields on a 64 x 20 character
// grid: o2Seg = fixed text in a colour class, o2Num = a number the cursor edits (+ / - by its STEP, TYPE), o2Choice = a
// set of words of which one is selected (+ / - cycles it; LF / RT walk the cursor over the options, ENT selects), o2Act = an action word (ENT presses it), o2Read = a value the
// cursor never visits. The values live in o2Val (field id -> number; a choice's index), their edit rules in o2Spec
// (o2Def). o2Key takes one key (the pad's buttons, the RHC's, the keyboard's through the coproc) and returns what the
// host must do ("" = nothing; "ACT:<id>" = an action pressed; "SET:<id>" = a value changed). o2Render turns the page
// into 20 rich-text rows and the cursor's box (LIST(row, col, text); row -1 = none): the cursor is drawn by the display
// as BLACK TEXT ON A FILLED AMBER BOX over the row, so the rows carry the field's own text under it.
// The colour classes (no asterisks): "S" a selected choice (brightest), "V" a live value (a step
// dimmer), "L" fixed labels and unselected choices (the page green), "D" unused / no data (dim), "Y" a caution, "R" a
// warning. A disabled field is drawn "D" and refuses ENT / + / - with a message.

GLOBAL O2_C IS LEXICON("L", "#3ce03c", "V", "#a6f8a6", "S", "#c4ffc4", "D", "#2f9a2f", "Y", "#f0d840", "R", "#ff2929",
    "K", "#000000").
GLOBAL O2_ROWS IS 20.

GLOBAL o2Val IS LEXICON().                   // field id -> number (a choice: the selected index)
GLOBAL o2Spec IS LEXICON().                  // field id -> LEXICON(kind, step, min, max, smin, smax, dec)
GLOBAL o2Cur IS "".                          // the cursor's field id ("" = the page's first field)
GLOBAL o2Typ IS FALSE.                       // TYPE open on the cursor's field
GLOBAL o2Buf IS "".                          // the TYPE text
GLOBAL o2Fresh IS TRUE.                      // the next typed character replaces the shown value
GLOBAL o2Opt IS -1.                          // the cursor's option within a choice row (-1 = the selected one)
GLOBAL o2OptFor IS "".                       // the field id o2Opt belongs to (a cursor put elsewhere resets it)
GLOBAL O2_DD_MAX IS 8.                       // the drop-down list's window (options shown at once)
GLOBAL o2DdOn IS FALSE.                      // the cursor's item has its drop-down list open
GLOBAL o2DdIx IS 0.                          // the list's cursor (an option index)
GLOBAL o2DdTop IS 0.                         // the first option shown
GLOBAL o2Msg IS "".                          // the model's own message (refusals); the host shows it on MSG
GLOBAL o2MsgCls IS "V".

// a field's edit rules: kind "N" number / "T" a time (s, typed as digits DDDHHMMSS) / "C" a choice of n; step and its
// range (STEP x10 / /10), the value's range, the decimals TYPE accepts
FUNCTION o2Def {
    PARAMETER id, kind, val, step IS 1, lo IS -1E9, hi IS 1E9, smin IS 0.1, smax IS 1000, dec IS 1.
    SET o2Spec[id] TO LEXICON("kind", kind, "step", step, "min", lo, "max", hi, "smin", smin, "smax", smax, "dec", dec).
    IF NOT o2Val:HASKEY(id) { SET o2Val[id] TO val. }
}

FUNCTION o2PgNew { RETURN LEXICON("seg", LIST(), "fld", LIST()). }

FUNCTION o2Seg {                             // fixed text at (row, col) in colour class cls
    PARAMETER pg, row, col, txt, cls IS "L".
    IF txt <> "" { pg["seg"]:ADD(LIST(row, col, txt, cls)). }
}

FUNCTION o2Fld {                             // a cursor stop: its box at (row, col) with the text under it
    PARAMETER pg, id, kind, row, col, txt, on, nocur IS FALSE.   // nocur = the arrows never walk onto it (a CMD cell: only TYPE on its joint reaches it)
    pg["fld"]:ADD(LEXICON("id", id, "kind", kind, "row", row, "col", col, "txt", txt, "on", on, "nocur", nocur)).
}

FUNCTION o2NoCur {                           // A stop the arrows walk past (a CMD cell, nocur TRUE); a field without the flag is a stop
    PARAMETER f.
    IF f:HASKEY("nocur") { RETURN f["nocur"]. }
    RETURN FALSE.
}

FUNCTION o2Num {                             // an editable number (kind from o2Spec: "N" / "T"), txt = its shown text
    PARAMETER pg, id, row, col, txt, on IS TRUE.
    o2Seg(pg, row, col, txt, CHOOSE "V" IF on ELSE "D").
    o2Fld(pg, id, CHOOSE o2Spec[id]["kind"] IF o2Spec:HASKEY(id) ELSE "N", row, col, txt, on).
}

FUNCTION o2Choice {                          // words at their columns (LIST(LIST(col, word))), o2Val[id] the selected
    PARAMETER pg, id, row, items, on IS TRUE, dimSet IS LIST(), dimWhy IS LIST().   // dimSet: indices drawn dim (not available);
    // dimWhy: per option index, the MSG text when ENT is pressed on that dim option ("" or none: "<word> NOT AVAILABLE"; "-": silent, no text)
    LOCAL k IS ROUND(o2Val[id]).
    FROM { LOCAL i IS 0. } UNTIL i >= items:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL cl IS "L".
        IF i = k { SET cl TO "S". }
        IF dimSet:CONTAINS(i) OR NOT on { SET cl TO "D". }
        o2Seg(pg, row, items[i][0], items[i][1], cl).
    }
    IF k >= 0 AND k < items:LENGTH {
        LOCAL f IS LEXICON("id", id, "kind", "C", "row", row, "col", items[k][0], "txt", items[k][1], "on", on,
            "n", items:LENGTH, "dim", dimSet, "items", items, "why", dimWhy).
        pg["fld"]:ADD(f).
    }
}

// a word item stepped by + / - whose options are NOT on the row: its selected word (txt) at (row, col); ENT opens a
// drop-down list of words (dimSet: indices not available), the cursor walks it, ENT selects. The field is kind "C" (n, dim:
// + / - as a choice) with "words" and "drop".
FUNCTION o2Drop {
    PARAMETER pg, id, row, col, txt, words, on IS TRUE, dimSet IS LIST().
    o2Seg(pg, row, col, txt, CHOOSE "V" IF on ELSE "D").
    o2Fld(pg, id, "C", row, col, txt, on).
    LOCAL f IS pg["fld"][pg["fld"]:LENGTH - 1].
    SET f["n"] TO words:LENGTH. SET f["dim"] TO dimSet. SET f["words"] TO words. SET f["drop"] TO TRUE.
}

FUNCTION o2Act {                             // an action word; on FALSE = drawn dim, ENT refused
    PARAMETER pg, id, row, col, txt, on IS TRUE.
    o2Seg(pg, row, col, txt, CHOOSE "L" IF on ELSE "D").
    o2Fld(pg, id, "A", row, col, txt, on).
}

FUNCTION o2Read {                            // a live value the cursor never visits
    PARAMETER pg, row, col, txt, cls IS "V".
    o2Seg(pg, row, col, txt, cls).
}

FUNCTION o2Find {                            // the page's field by id, else an empty LEXICON
    PARAMETER pg, id.
    FOR f IN pg["fld"] { IF f["id"] = id { RETURN f. } }
    RETURN LEXICON().
}

FUNCTION o2CurFld {                          // the cursor's field (put on the first one when its id is not on the page)
    PARAMETER pg.
    IF pg["fld"]:LENGTH = 0 { RETURN LEXICON(). }
    LOCAL f IS o2Find(pg, o2Cur).
    IF f:LENGTH = 0 { SET f TO pg["fld"][0]. SET o2Cur TO f["id"]. SET o2Typ TO FALSE. }
    IF o2OptFor <> o2Cur { SET o2OptFor TO o2Cur. SET o2Opt TO -1. SET o2DdOn TO FALSE. }
    IF o2DdOn { IF NOT f:HASKEY("drop") OR NOT f["on"] { SET o2DdOn TO FALSE. } }
    IF o2Opt >= 0 {                          // a choice's cursor on one of its options: that option's column and text
        IF f:HASKEY("items") { IF o2Opt < f["items"]:LENGTH {
            LOCAL it IS f["items"][o2Opt].
            RETURN LEXICON("id", f["id"], "kind", f["kind"], "row", f["row"], "col", it[0], "txt", it[1], "on", f["on"],
                "n", f["n"], "dim", f["dim"], "items", f["items"], "why", CHOOSE f["why"] IF f:HASKEY("why") ELSE LIST()).
        } }
        SET o2Opt TO -1.
    }
    RETURN f.
}

FUNCTION o2Mid { PARAMETER f. RETURN f["col"] + f["txt"]:LENGTH / 2. }

// the cursor's move: UP / DN = the nearest row above / below that has a field, its field nearest in column;
// LF / RT = the next stop along the same row (every option of a choice row is a stop: the cursor walks them one
// by one, then goes on to the next field; it lands on a choice's first option coming from the left, its last from the
// right; UP / DN land on a choice's selected option); nothing that way = the cursor stays
FUNCTION o2Move {
    PARAMETER pg, dir.
    LOCAL f IS o2CurFld(pg).
    IF f:LENGTH = 0 { RETURN. }
    IF (dir = "LF" OR dir = "RT") AND f:HASKEY("items") {
        LOCAL k2 IS (CHOOSE o2Opt IF o2Opt >= 0 ELSE ROUND(o2Val[f["id"]])) + (CHOOSE 1 IF dir = "RT" ELSE -1).
        IF k2 >= 0 AND k2 < f["items"]:LENGTH { SET o2Opt TO k2. RETURN. }
    }
    LOCAL best IS LEXICON().
    LOCAL bk IS 1E9.
    FOR g IN pg["fld"] {
        IF g["id"] <> f["id"] AND NOT o2NoCur(g) {
            LOCAL dr IS g["row"] - f["row"].
            LOCAL k IS 1E9.
            LOCAL gc IS g["col"].            // the column the cursor would land on
            IF g:HASKEY("items") AND dir = "RT" { SET gc TO g["items"][0][0]. }
            IF g:HASKEY("items") AND dir = "LF" { SET gc TO g["items"][g["items"]:LENGTH - 1][0]. }
            IF dir = "UP" AND dr < 0 { SET k TO -dr * 1000 + ABS(o2Mid(g) - o2Mid(f)). }
            ELSE IF dir = "DN" AND dr > 0 { SET k TO dr * 1000 + ABS(o2Mid(g) - o2Mid(f)). }
            ELSE IF dir = "LF" AND dr = 0 AND gc < f["col"] { SET k TO f["col"] - gc. }
            ELSE IF dir = "RT" AND dr = 0 AND gc > f["col"] { SET k TO gc - f["col"]. }
            IF k < bk { SET bk TO k. SET best TO g. }
        }
    }
    IF best:LENGTH > 0 {
        SET o2Cur TO best["id"].
        SET o2OptFor TO o2Cur.
        SET o2Opt TO -1.
        IF best:HASKEY("items") AND dir = "RT" { SET o2Opt TO 0. }
        IF best:HASKEY("items") AND dir = "LF" { SET o2Opt TO best["items"]:LENGTH - 1. }
    }
}

// ---- the drop-down list. o2DdFit: the list's window (m options, below / above the item) and the scroll that keeps the
// cursor in it; o2DdLayout: what to draw (LEXICON(), nothing, while closed).
FUNCTION o2DdFit {
    PARAMETER f.
    LOCAL n IS f["words"]:LENGTH.
    LOCAL m IS MIN(n, O2_DD_MAX).
    LOCAL below IS O2_ROWS - 1 - f["row"].
    LOCAL above IS f["row"].
    LOCAL dn IS below >= m OR below >= above.
    SET m TO MAX(1, MIN(m, CHOOSE below IF dn ELSE above)).
    SET o2DdIx TO o2Clamp(o2DdIx, 0, n - 1).
    IF o2DdIx < o2DdTop { SET o2DdTop TO o2DdIx. }
    IF o2DdIx >= o2DdTop + m { SET o2DdTop TO o2DdIx - m + 1. }
    SET o2DdTop TO o2Clamp(o2DdTop, 0, MAX(0, n - m)).
    RETURN LIST(m, dn).
}

FUNCTION o2DdLayout {
    PARAMETER pg.
    IF NOT o2DdOn { RETURN LEXICON(). }
    LOCAL f IS o2CurFld(pg).
    IF f:LENGTH = 0 OR NOT o2DdOn { RETURN LEXICON(). }
    LOCAL words IS f["words"].
    LOCAL n IS words:LENGTH.
    LOCAL fit IS o2DdFit(f).
    LOCAL m IS fit[0].
    LOCAL dn IS fit[1].
    LOCAL wmax IS 0.
    FOR wd IN words { SET wmax TO MAX(wmax, wd:LENGTH). }
    LOCAL mk IS CHOOSE 1 IF n > m ELSE 0.             // a column for the "more above / below" mark
    LOCAL w IS MAX(wmax + mk, f["txt"]:LENGTH).
    LOCAL sel IS ROUND(o2Val[f["id"]]).
    LOCAL cells IS LIST().
    cells:ADD(LIST(f["row"], "<color=" + O2_C["V"] + ">" + f["txt"]:PADRIGHT(w) + "</color>", "tb")).   // the item: outlined
    FROM { LOCAL j IS 0. } UNTIL j >= m STEP { SET j TO j + 1. } DO {
        LOCAL ix IS o2DdTop + j.
        LOCAL txt IS words[ix]:PADRIGHT(wmax).
        IF mk > 0 {
            LOCAL mkc IS " ".
            IF j = 0 AND o2DdTop > 0 { SET mkc TO CHAR(8593). }
            IF j = m - 1 AND o2DdTop + m < n { SET mkc TO CHAR(8595). }
            SET txt TO txt + mkc.
        }
        SET txt TO txt:PADRIGHT(w).
        LOCAL bg IS "k".
        IF j = 0 AND NOT dn { SET bg TO "kt". }
        IF j = m - 1 AND dn { SET bg TO "kb". }
        IF ix = o2DdIx { SET bg TO "a". }
        ELSE {
            LOCAL cl IS "L".
            IF ix = sel { SET cl TO "S". }
            IF f["dim"]:CONTAINS(ix) { SET cl TO "D". }
            SET txt TO "<color=" + O2_C[cl] + ">" + txt + "</color>".
        }
        cells:ADD(LIST(CHOOSE f["row"] + 1 + j IF dn ELSE f["row"] - m + j, txt, bg)).
    }
    RETURN LEXICON("col", f["col"], "w", w, "irow", f["row"], "cells", cells).
}

FUNCTION o2Say { PARAMETER s, cl IS "Y". SET o2Msg TO s. SET o2MsgCls TO cl. }

FUNCTION o2Clamp { PARAMETER x, lo, hi. RETURN MAX(lo, MIN(hi, x)). }

FUNCTION o2Bump {                            // + / - on the cursor's field
    PARAMETER f, sg.
    LOCAL id IS f["id"].
    IF f["kind"] = "C" {
        LOCAL n IS f["n"].
        LOCAL k IS ROUND(o2Val[id]).
        FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {   // the next one that is not dim
            SET k TO MOD(k + sg + n, n).
            IF NOT f["dim"]:CONTAINS(k) { BREAK. }
        }
        SET o2Val[id] TO k.
        SET o2Opt TO -1.                     // the cursor follows the new selection
        RETURN "SET:" + id.
    }
    IF f["kind"] = "N" OR f["kind"] = "T" {
        LOCAL sp IS o2Spec[id].
        SET o2Val[id] TO o2Clamp(o2Val[id] + sg * sp["step"], sp["min"], sp["max"]).
        RETURN "SET:" + id.
    }
    RETURN "".
}

FUNCTION o2StepTxt {                         // the STEP readout for the cursor's field ("" = not a number)
    PARAMETER pg.
    LOCAL f IS o2CurFld(pg).
    IF f:LENGTH = 0 { RETURN "". }
    IF NOT o2Spec:HASKEY(f["id"]) OR f["kind"] = "C" OR f["kind"] = "A" { RETURN "". }
    LOCAL st IS o2Spec[f["id"]]["step"].
    IF f["kind"] = "T" { RETURN "STEP " + o2Dur(st). }
    RETURN "STEP " + st.
}

FUNCTION o2Dur {                             // a step in s as the shortest of 1 S, 10 S, 1 M, 10 M, 1 H ...
    PARAMETER s.
    IF s >= 3600 { RETURN ROUND(s / 3600, 2) + " H". }
    IF s >= 60 { RETURN ROUND(s / 60, 2) + " M". }
    RETURN s + " S".
}

FUNCTION o2Rescale {                         // STEP x10 / /10: the cursor field's step, within its smin .. smax
    PARAMETER f, k.
    IF NOT o2Spec:HASKEY(f["id"]) { RETURN. }
    LOCAL sp IS o2Spec[f["id"]].
    IF sp["kind"] = "T" {                    // a time steps 1 s, 10 s, 1 m, 10 m, 1 h, 10 h
        LOCAL ladder IS LIST(1, 10, 60, 600, 3600, 36000).
        LOCAL i IS MAX(0, ladder:INDEXOF(sp["step"])).
        SET i TO o2Clamp(i + (CHOOSE 1 IF k > 1 ELSE -1), 0, ladder:LENGTH - 1).
        SET sp["step"] TO o2Clamp(ladder[i], sp["smin"], sp["smax"]).
        RETURN.
    }
    SET sp["step"] TO o2Clamp(ROUND(sp["step"] * k, 6), sp["smin"], sp["smax"]).
}

FUNCTION o2TypeParse {                       // the TYPE text -> LIST(ok, the number)
    PARAMETER kind, s.
    IF s = "" OR s = "-" OR s = "+" OR s = "." OR s = "-." { RETURN LIST(FALSE, 0). }
    IF kind = "T" {                          // digits DDDHHMMSS, right-aligned: 130 = 1:30, 10000 = 1:00:00
        LOCAL d IS s:PADLEFT(9):REPLACE(" ", "0").
        IF d:LENGTH > 9 { RETURN LIST(FALSE, 0). }
        LOCAL n IS LIST(d:SUBSTRING(0, 3), d:SUBSTRING(3, 2), d:SUBSTRING(5, 2), d:SUBSTRING(7, 2)).
        LOCAL tot IS 0.
        LOCAL mul IS LIST(86400, 3600, 60, 1).
        FROM { LOCAL i IS 0. } UNTIL i >= 4 STEP { SET i TO i + 1. } DO {
            LOCAL x IS n[i]:TONUMBER(-1).
            IF x < 0 { RETURN LIST(FALSE, 0). }
            IF i > 1 AND x > 59 { RETURN LIST(FALSE, 0). }
            IF i = 1 AND x > 23 { RETURN LIST(FALSE, 0). }
            SET tot TO tot + x * mul[i].
        }
        RETURN LIST(TRUE, tot).
    }
    LOCAL x IS s:TONUMBER(-1E30).
    IF x = -1E30 { RETURN LIST(FALSE, 0). }
    RETURN LIST(TRUE, x).
}

// After ENT / CANCEL on a joint's CMD cell (jtN) the cursor goes back to that joint's toggle (ajN) on its row
FUNCTION o2JtBack {
    PARAMETER pg, f.
    IF NOT f["id"]:STARTSWITH("jt") { RETURN. }
    LOCAL af IS o2Find(pg, "aj" + f["id"]:SUBSTRING(2, f["id"]:LENGTH - 2)).
    IF af:LENGTH > 0 AND af["row"] = f["row"] { SET o2Cur TO af["id"]. }
}

// one key: UP DN LF RT (the arrows), PL MI (+ / -), ENT, TYPE, CAN (CANCEL / Esc), X10 D10 (STEP x10 / /10), and in
// TYPE "0".."9" "." "-" "+" BKSP. Returns "" / "ACT:<id>" / "SET:<id>" (the host reacts) / "TYPE" / "CAN".
FUNCTION o2Key {
    PARAMETER pg, key.
    LOCAL f IS o2CurFld(pg).
    IF f:LENGTH = 0 { RETURN "". }
    IF o2DdOn {                              // the open list owns the keys (nothing else reacts)
        LOCAL nw IS f["words"]:LENGTH.
        IF key = "UP" OR key = "DN" {
            SET o2DdIx TO o2Clamp(o2DdIx + (CHOOSE 1 IF key = "DN" ELSE -1), 0, nw - 1).
            o2DdFit(f).
            RETURN "".
        }
        IF key = "ENT" {
            IF f["dim"]:CONTAINS(o2DdIx) { o2Say(f["words"][o2DdIx]:TRIM + " NOT AVAILABLE"). RETURN "". }
            SET o2DdOn TO FALSE.
            IF o2DdIx = ROUND(o2Val[f["id"]]) { RETURN "DDX:" + f["id"]. }
            SET o2Val[f["id"]] TO o2DdIx.
            RETURN "SET:" + f["id"].
        }
        IF key = "LF" OR key = "RT" OR key = "CAN" { SET o2DdOn TO FALSE. RETURN "DDX:" + f["id"]. }
        RETURN "".
    }
    IF o2Typ {
        LOCAL kind IS f["kind"].
        IF key = "ENT" {
            LOCAL px IS o2TypeParse(kind, o2Buf).
            IF NOT px[0] { o2Say("NOT A NUMBER"). RETURN "". }
            LOCAL x IS px[1].
            LOCAL sp IS o2Spec[f["id"]].
            IF x < sp["min"] OR x > sp["max"] {
                o2Say("OUT OF RANGE " + o2Lim(kind, sp["min"]) + "..." + o2Lim(kind, sp["max"])).
                RETURN "".
            }
            SET o2Val[f["id"]] TO x.
            SET o2Typ TO FALSE.
            o2JtBack(pg, f).
            RETURN "SET:" + f["id"].
        }
        IF key = "CAN" { SET o2Typ TO FALSE. o2JtBack(pg, f). RETURN "CAN". }
        IF key = "BKSP" {
            SET o2Fresh TO FALSE.
            IF o2Buf:LENGTH > 0 { SET o2Buf TO o2Buf:SUBSTRING(0, o2Buf:LENGTH - 1). }
            RETURN "".
        }
        LOCAL digit IS "0123456789":CONTAINS(key) AND key:LENGTH = 1.
        LOCAL ok IS digit.
        IF kind <> "T" {
            IF key = "." { SET ok TO TRUE. }
            IF key = "-" OR key = "+" { SET ok TO TRUE. }
        }
        IF NOT ok { RETURN "". }              // letters, symbols: nothing
        IF o2Fresh { SET o2Buf TO "". SET o2Fresh TO FALSE. }
        IF key = "-" OR key = "+" {           // a sign only first
            IF o2Buf = "" { SET o2Buf TO CHOOSE "-" IF key = "-" ELSE "". }
            ELSE IF o2Buf:STARTSWITH("-") { SET o2Buf TO o2Buf:SUBSTRING(1, o2Buf:LENGTH - 1). }
            ELSE IF key = "-" { SET o2Buf TO "-" + o2Buf. }
            RETURN "".
        }
        IF key = "." AND o2Buf:CONTAINS(".") { RETURN "". }
        IF o2Buf:LENGTH < (CHOOSE 9 IF kind = "T" ELSE 10) { SET o2Buf TO o2Buf + key. }
        RETURN "".
    }
    IF key = "UP" OR key = "DN" OR key = "LF" OR key = "RT" { o2Move(pg, key). RETURN "". }
    IF key = "X10" { o2Rescale(f, 10). RETURN "". }
    IF key = "D10" { o2Rescale(f, 0.1). RETURN "". }
    IF NOT f["on"] {
        IF key = "ENT" OR key = "PL" OR key = "MI" OR key = "TYPE" { o2Say(f["txt"]:TRIM + " NOT AVAILABLE"). }
        RETURN "".
    }
    IF key = "PL" { RETURN o2Bump(f, 1). }
    IF key = "MI" { RETURN o2Bump(f, -1). }
    IF key = "ENT" {
        IF f["kind"] = "A" { RETURN "ACT:" + f["id"]. }
        IF f["kind"] = "C" AND f:HASKEY("drop") {   // ENT opens the item's drop-down list, the cursor on the current value
            SET o2DdOn TO TRUE.
            SET o2DdIx TO ROUND(o2Val[f["id"]]).
            SET o2DdTop TO 0.
            o2DdFit(f).
            RETURN "DD:" + f["id"].
        }
        IF f["kind"] = "C" AND o2Opt >= 0 AND f:HASKEY("items") {   // ENT selects the option the cursor is on
            IF f["dim"]:CONTAINS(o2Opt) {
                IF f:HASKEY("why") AND f["why"]:LENGTH > o2Opt AND f["why"][o2Opt] = "-" { RETURN "". }   // silent
                o2Say(CHOOSE f["why"][o2Opt] IF f:HASKEY("why") AND f["why"]:LENGTH > o2Opt AND f["why"][o2Opt] <> "" ELSE f["txt"]:TRIM + " NOT AVAILABLE").   // a reason, where one is given
                RETURN "".
            }
            IF o2Opt = ROUND(o2Val[f["id"]]) { RETURN "". }
            SET o2Val[f["id"]] TO o2Opt.
            SET o2Opt TO -1.
            RETURN "SET:" + f["id"].
        }
        RETURN "".
    }
    IF key = "TYPE" {
        IF f["id"]:STARTSWITH("aj") {                 // TYPE on a joint's toggle (ajN) types that joint's CMD cell (jtN, the same row)
            LOCAL jtf IS o2Find(pg, "jt" + f["id"]:SUBSTRING(2, f["id"]:LENGTH - 2)).
            IF jtf:LENGTH > 0 AND jtf["row"] = f["row"] { SET f TO jtf. SET o2Cur TO jtf["id"]. }
        }
        IF f["kind"] = "N" OR f["kind"] = "T" {
            SET o2Typ TO TRUE.
            SET o2Fresh TO TRUE.
            SET o2Buf TO CHOOSE o2TimeDigits(o2Val[f["id"]]) IF f["kind"] = "T"
                ELSE ("" + ROUND(o2Val[f["id"]], o2Spec[f["id"]]["dec"])).
            RETURN "TYPE".
        }
        RETURN "".                           // TYPE on a choice / an action does nothing
    }
    IF key = "CAN" { RETURN "CAN". }
    RETURN "".
}

FUNCTION o2Lim { PARAMETER kind, x. IF kind = "T" { RETURN o2Met(x). } RETURN "" + ROUND(x, 3). }

FUNCTION o2TimeDigits {                      // a time as its typed digits (leading zeros dropped)
    PARAMETER t.
    LOCAL s IS o2Met(t):REPLACE("/", ""):REPLACE(":", "").
    UNTIL s:LENGTH <= 1 OR NOT s:STARTSWITH("0") { SET s TO s:SUBSTRING(1, s:LENGTH - 1). }
    RETURN s.
}

// ---- formats (fixed width, so the grid holds)
FUNCTION o2Fx {                              // x with d decimals, always shown (no sign for x >= 0)
    PARAMETER x, d.
    LOCAL m IS 10 ^ d.
    LOCAL a IS ROUND(ABS(x) * m).
    LOCAL ip IS FLOOR(a / m).
    LOCAL s IS "" + ip.
    IF d > 0 { SET s TO s + "." + ("" + (a - ip * m)):PADLEFT(d):REPLACE(" ", "0"). }
    IF x < 0 AND a > 0 { SET s TO "-" + s. }
    RETURN s.
}
FUNCTION o2F { PARAMETER x, w, d. RETURN o2Fx(x, d):PADLEFT(w). }
FUNCTION o2Sv {                              // x right-aligned in w with a sign only when it is not 0: "+41.6", "  0.0", " -2.1"
    PARAMETER x, w, d.
    IF ROUND(ABS(x) * 10 ^ d) = 0 { RETURN o2Fx(0, d):PADLEFT(w). }
    RETURN ((CHOOSE "-" IF x < 0 ELSE "+") + o2Fx(ABS(x), d)):PADLEFT(w).
}
FUNCTION o2DvBar {                           // the DV slider's state LIST(total, gained) m/s: gained = total less the live
    PARAMETER tot, vgo.                      // VGO TOT, clamped 0 .. total (LIST() = no burn: the slider is not drawn)
    IF tot < 0.05 { RETURN LIST(). }
    RETURN LIST(tot, MAX(0, MIN(tot, tot - vgo))).
}
FUNCTION o2Sg {                              // the sign in front, the number right-aligned after it: "+ 41.6", "-  2.1"
    PARAMETER x, w, d.
    LOCAL a IS o2Fx(ABS(x), d).
    LOCAL sg IS CHOOSE "-" IF x < 0 AND ROUND(ABS(x) * 10 ^ d) > 0 ELSE "+".
    RETURN sg + a:PADLEFT(w - 1).
}
FUNCTION o2P2 { PARAMETER n. RETURN ("" + n):PADLEFT(2):REPLACE(" ", "0"). }
FUNCTION o2Met {                             // DDD/HH:MM:SS
    PARAMETER t.
    LOCAL s IS FLOOR(MAX(0, t) + 0.5).
    LOCAL d IS FLOOR(s / 86400).
    SET s TO s - d * 86400.
    LOCAL h IS FLOOR(s / 3600).
    SET s TO s - h * 3600.
    LOCAL mi IS FLOOR(s / 60).
    RETURN ("" + d):PADLEFT(3):REPLACE(" ", "0") + "/" + o2P2(h) + ":" + o2P2(mi) + ":" + o2P2(s - mi * 60).
}
FUNCTION o2Cd {                              // a countdown: -HH:MM:SS before, +HH:MM:SS after
    PARAMETER t.
    LOCAL s IS FLOOR(ABS(t) + 0.5).
    LOCAL h IS FLOOR(s / 3600).
    SET s TO s - h * 3600.
    LOCAL mi IS FLOOR(s / 60).
    RETURN (CHOOSE "-" IF t > 0 ELSE "+") + o2P2(h) + ":" + o2P2(mi) + ":" + o2P2(s - mi * 60).
}
FUNCTION o2Ms {                              // m:ss
    PARAMETER t.
    LOCAL s IS FLOOR(MAX(0, t) + 0.5).
    RETURN FLOOR(s / 60) + ":" + o2P2(MOD(s, 60)).
}

// ---- the render: 20 rich-text rows + the cursor box + the cursor row cut at the box (LIST(before, after): the
// display lays them out with the box between, so the box sits on its field whatever the font's advance)
FUNCTION o2RowStr {                          // the columns c0 .. c1 - 1 of a row's sorted segments as rich text
    PARAMETER l, c0, c1.
    RETURN o2RowStrN(l, c0, c1)[0].
}
FUNCTION o2RowStrN {                         // o2RowStr's text and the column it reached (o2Vis of the text
    PARAMETER l, c0, c1.                     // is that less c0: no o2Vis pass over it)
    LOCAL s IS "".
    LOCAL n IS c0.                           // the column reached
    FOR sg IN l {
        LOCAL t IS sg[2].
        LOCAL c IS sg[1].
        IF c < n {                           // an overlap (or the cut): the covered start goes
            LOCAL cut IS n - c.
            SET t TO CHOOSE "" IF cut >= t:LENGTH ELSE t:SUBSTRING(cut, t:LENGTH - cut).
            SET c TO n.
        }
        IF c + t:LENGTH > c1 { SET t TO CHOOSE "" IF c >= c1 ELSE t:SUBSTRING(0, c1 - c). }
        IF t <> "" {
            IF c > n { SET s TO s + "":PADLEFT(c - n). }
            IF sg[3] = "L" { SET s TO s + t. }
            ELSE { SET s TO s + "<color=" + O2_C[sg[3]] + ">" + t + "</color>". }
            SET n TO c + t:LENGTH.
        }
    }
    RETURN LIST(s, n).
}

FUNCTION o2Render {
    PARAMETER pg.
    LOCAL rows IS LIST().
    LOCAL byRow IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= O2_ROWS STEP { SET i TO i + 1. } DO { byRow:ADD(LIST()). }
    FOR sg IN pg["seg"] {
        IF sg[0] >= 0 AND sg[0] < O2_ROWS {
            LOCAL l IS byRow[sg[0]].
            LOCAL k IS 0.                    // insertion by column (a few segments a row)
            UNTIL k >= l:LENGTH OR l[k][1] > sg[1] { SET k TO k + 1. }
            l:INSERT(k, sg).
        }
    }
    FROM { LOCAL i IS 0. } UNTIL i >= O2_ROWS STEP { SET i TO i + 1. } DO { rows:ADD(o2RowStr(byRow[i], 0, 999)). }
    LOCAL cur IS LIST(-1, 0, "").
    LOCAL cut IS LIST("", "").
    LOCAL f IS o2CurFld(pg).
    LOCAL dd IS o2DdLayout(pg).              // an open drop-down list replaces the cursor box
    IF f:LENGTH > 0 AND dd:LENGTH = 0 {
        LOCAL t IS f["txt"].
        IF o2Typ {
            LOCAL b IS o2Buf.
            IF f["kind"] = "T" { SET b TO o2TimeShow(o2Buf). }
            SET t TO b:PADLEFT(MAX(t:LENGTH, b:LENGTH + 1)).
        }
        SET cur TO LIST(f["row"], f["col"], t).
        LOCAL l IS byRow[f["row"]].
        SET cut TO LIST("", o2RowStr(l, f["col"] + t:LENGTH, 999)).
        // the box's own text may be wider than the field's (TYPE): the row after it starts at the box's end
        LOCAL pn IS o2RowStrN(l, 0, f["col"]).
        LOCAL pre IS pn[0].
        LOCAL vis IS pn[1].                  // = o2Vis(pre) (the column reached, c0 = 0)
        IF vis < f["col"] { SET pre TO pre + "":PADLEFT(f["col"] - vis). }
        SET cut[0] TO pre.
    }
    IF dd:LENGTH > 0 {                       // each list row's text before and after the cell (the draw lays the cell between)
        FOR cl IN dd["cells"] {
            LOCAL l2 IS byRow[cl[0]].
            LOCAL pn2 IS o2RowStrN(l2, 0, dd["col"]).
            LOCAL pre2 IS pn2[0].
            IF pn2[1] < dd["col"] { SET pre2 TO pre2 + "":PADLEFT(dd["col"] - pn2[1]). }
            cl:ADD(pre2).
            cl:ADD(o2RowStr(l2, dd["col"] + dd["w"], 999)).
        }
    }
    RETURN LIST(rows, cur, cut, dd).
}

FUNCTION o2Vis {                             // the visible characters of a rich-text string (the tags left out)
    PARAMETER s.
    LOCAL n IS 0.
    LOCAL intag IS FALSE.
    FROM { LOCAL i IS 0. } UNTIL i >= s:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL ch IS s[i].
        IF ch = "<" AND (s:FINDAT("<color=", i) = i OR s:FINDAT("</color>", i) = i) { SET intag TO TRUE. }
        ELSE IF intag AND ch = ">" { SET intag TO FALSE. }
        ELSE IF NOT intag { SET n TO n + 1. }
    }
    RETURN n.
}

FUNCTION o2TimeShow {                        // typed time digits with the / and : put in (right-aligned)
    PARAMETER b.
    LOCAL d IS b:PADLEFT(9):REPLACE(" ", "0").
    RETURN d:SUBSTRING(0, 3) + "/" + d:SUBSTRING(3, 2) + ":" + d:SUBSTRING(5, 2) + ":" + d:SUBSTRING(7, 2).
}
