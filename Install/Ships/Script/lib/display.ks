// display.ks
// Persistent, in-place terminal display widget for kOS. Reads and writes no files.
// Draws a rows x cols grid of cells, each showing "<label>  <value>". All cells share one label width
// (descW, the widest label) and one value width (valW, the rest of the cell). The frame and labels are
// drawn once, and again only when the layout or a label changes. Each call repaints only the values whose
// text changed, each in a fixed-width field so that a changed value fully overwrites the old one.
// Usage: run once "0:/lib/display.ks". Then call displayUpdate in a loop, e.g. a 2 x 3 grid:
//   displayUpdate(2, 3, list("Alt", ship:altitude, 0, "Vel", ship:velocity:surface:mag, 1,
//       "Mode", "ASCENT", 0, "Peri", ship:periapsis, 0, "Thr", throttle, 3, "Stat", "OK", 0)).
// Each entry is a triplet (label, value, decimals):
//   - number: `decimals` (clamped to 0..15) is the digits after the point; the point stays in one column.
//   - string: `decimals` is ignored; the string is shown right-aligned, cut or padded with leading spaces to the field.
// Call displayReset() to make the next update redraw from scratch.

// Cache of the drawn frame (layout, labels) and of the text last painted in each value cell.
global DISPLAY_STATE is lexicon().
// Padding sources for _dpPad (spaces, zeros, '#'): cutting from a constant string takes far fewer kOS
// instructions than appending one character per loop pass.
global _DP_SPACES is "                                                                                ".
global _DP_ZEROS is "00000000000000000000".
global _DP_HASHES is "################################################################################".
// Return n copies of ch (a space, "0" or "#"); "" if n <= 0.
function _dpPad {
    parameter ch, n.
    if n <= 0 { return "". }
    local src is _DP_SPACES.
    if ch = "0" { set src to _DP_ZEROS. } else if ch = "#" { set src to _DP_HASHES. }
    if n <= src:length { return src:substring(0, n). }
    local s is src.
    until s:length >= n { set s to s + ch. }
    return s.
}

// Forget the cached frame and clear the screen, so the next displayUpdate redraws everything.
function displayReset {
    set DISPLAY_STATE to lexicon().
    clearscreen.
}

// Draw the rows x cols grid, or repaint only the value cells whose text changed.
// data is a flat LIST of label, value, decimals triplets; entries past rows * cols are ignored.
function displayUpdate {
    parameter rows.
    parameter cols.
    parameter data.    // LIST: label1, value1, dec1, label2, value2, dec2, ...

    local nCells    is rows * cols.
    local nEntries  is floor(data:length / 3).
    if nEntries > nCells { set nEntries to nCells. }   // silently ignore extras

    // ---- Split the flat list into labels, values, and decimal counts ----
    // Cells past nEntries stay blank: empty label, value of spaces; their vals / decs are unused.
    local labels is list().
    local vals   is list().
    local decs   is list().
    from { local i is 0. } until i >= nCells step { set i to i + 1. } do {
        if i < nEntries {
            labels:add("" + data[i * 3]).
            vals:add(data[i * 3 + 1]).
            decs:add(data[i * 3 + 2]).
        } else {
            labels:add("").
            vals:add(0).
            decs:add(0).
        }
    }

    // ---- Layout math ----
    local termW is terminal:width.
    local cellW is floor((termW - 1) / cols).   // cell incl. its leading '│'
    if cellW < 6 { set cellW to 6. }            // minimum sensible cell

    // descW: the label width, i.e. the widest label.
    local descW is 1.
    for lbl in labels {
        if lbl:length > descW { set descW to lbl:length. }
    }
    // Cell layout inside the two '│' bars: " <label> <value> "
    //   contentW = cellW - 1 = descW + valW + 3  ->  valW = cellW - descW - 4
    // (1 lead space + descW + 1 sep space + valW + 1 trail space)
    if descW > cellW - 5 { set descW to cellW - 5. }
    if descW < 1         { set descW to 1.         }
    local valW is cellW - descW - 4.
    if valW < 1 { set valW to 1. }

    // ---- Decide whether the frame needs a full redraw ----
    local redraw is false.
    if not DISPLAY_STATE:haskey("init") {
        set redraw to true.
    } else if DISPLAY_STATE:rows  <> rows
           or DISPLAY_STATE:cols  <> cols
           or DISPLAY_STATE:termW <> termW
           or DISPLAY_STATE:descW <> descW
           or DISPLAY_STATE:valW  <> valW {
        set redraw to true.
    } else {
        from { local k is 0. } until k >= labels:length step { set k to k + 1. } do {
            if DISPLAY_STATE:labels[k] <> labels[k] {
                set redraw to true.
                break.
            }
        }
    }

    // ---- Full redraw: frame + labels + blank value slots ----
    if redraw {
        clearscreen.

        local topSep is buildSeparator("┌", "┬", "┐", cols, cellW).
        local midSep is buildSeparator("├", "┼", "┤", cols, cellW).
        local botSep is buildSeparator("└", "┴", "┘", cols, cellW).

        // Row ri: separator on line 2*ri, cells on line 2*ri + 1; the bottom separator on line 2*rows.
        from { local ri is 0. } until ri >= rows step { set ri to ri + 1. } do {
            local sep is midSep.
            if ri = 0 { set sep to topSep. }
            print sep at (0, ri * 2).

            local line is "│".
            from { local ci is 0. } until ci >= cols step { set ci to ci + 1. } do {
                local idx is ri * cols + ci.
                local lbl is labels[idx].
                if lbl:length > descW { set lbl to lbl:substring(0, descW). }
                until lbl:length >= descW { set lbl to lbl + " ". }
                local blank is "".
                until blank:length >= valW { set blank to blank + " ". }
                set line to line + " " + lbl + " " + blank + " │".
            }
            print line at (0, ri * 2 + 1).
        }
        print botSep at (0, rows * 2).

        // Re-seed the cached state.  "" forces every value to repaint below.
        set DISPLAY_STATE to lexicon(
            "init",   true,
            "rows",   rows,
            "cols",   cols,
            "termW",  termW,
            "cellW",  cellW,
            "descW",  descW,
            "valW",   valW,
            "labels", labels:copy(),
            "vals",   list()
        ).
        from { local m is 0. } until m >= nCells step { set m to m + 1. } do {
            DISPLAY_STATE:vals:add("").
        }
    }

    // ---- Update only the value cells whose formatted text changed ----
    local cachedVals is DISPLAY_STATE:vals.
    from { local j is 0. } until j >= nCells step { set j to j + 1. } do {
        local formatted is "".
        if j < nEntries {
            set formatted to formatValue(vals[j], decs[j], valW).
        } else {
            set formatted to _dpPad(" ", valW).
        }
        if cachedVals[j] <> formatted {
            local rr  is floor(j / cols).
            local cc  is j - rr * cols.
            local col is cc * DISPLAY_STATE:cellW + DISPLAY_STATE:descW + 3.
            local row is rr * 2 + 1.
            print formatted at (col, row).
            set cachedVals[j] to formatted.
        }
    }
}

// One horizontal frame line: leftCh, then per cell cellW - 1 horizontal-line characters (as wide as a
// data row's cell), with midCh between cells and rightCh at the end (corners, T-junctions or crosses).
function buildSeparator {
    parameter leftCh.
    parameter midCh.
    parameter rightCh.
    parameter cols.
    parameter cellW.

    local s is leftCh.
    from { local ci is 0. } until ci >= cols step { set ci to ci + 1. } do {
        from { local k is 0. } until k >= cellW - 1 step { set k to k + 1. } do {
            set s to s + "─".
        }
        if ci < cols - 1 {
            set s to s + midCh.
        } else {
            set s to s + rightCh.
        }
    }
    return s.
}

// Format a value (number or string) into a field of exactly w characters.
// Numbers: the decimal point stays in one column; exactly `decimals` digits follow it (zero-padded).
// If the integer part (sign included) does not fit, the whole field is '#'.
// Strings: right-aligned, cut at w, padded with leading spaces.
function formatValue {
    parameter val.
    parameter decimals.
    parameter w.

    // ---- String branch: right-aligned by leading spaces, so the last character sits one column from
    // the right cell bar, as with numbers. Strings longer than the field are cut from the right.
    if val:istype("String") {
        local s is val.
        if s:length > w { set s to s:substring(0, w). }
        if s:length < w { set s to _dpPad(" ", w - s:length) + s. }
        return s.
    }

    // ---- Numeric branch ----
    // Clamp decimals to kOS round()'s supported range.
    local d is decimals.
    if d > 15 { set d to 15. }
    if d < 0  { set d to 0.  }

    // Width budget for the integer portion (sign included).  If we're showing
    // decimals, the '.' eats one more character.
    local intWidth is w - d.
    if d > 0 { set intWidth to intWidth - 1. }

    local rounded is round(val, d).
    local sign    is "".
    if rounded < 0 { set sign to "-". }
    local absR    is abs(rounded).
    local intPart is floor(absR).
    local intStr  is sign + ("" + intPart).

    // Build the fractional string ("" if d = 0, else ".dddd...")
    local decStr is "".
    if d > 0 {
        local fracInt is round((absR - intPart) * (10 ^ d)).
        local fracStr is "" + fracInt.
        if fracStr:length < d { set fracStr to _dpPad("0", d - fracStr:length) + fracStr. }
        // Defensive trim in case float error pushed the digit count over d.
        if fracStr:length > d {
            set fracStr to fracStr:substring(fracStr:length - d, d).
        }
        set decStr to "." + fracStr.
    }

    if intStr:length > intWidth or intWidth < 1 {
        return _dpPad("#", w).
    }

    if intStr:length < intWidth { set intStr to _dpPad(" ", intWidth - intStr:length) + intStr. }
    return intStr + decStr.
}
