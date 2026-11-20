// lib_ascent_con.ks -- ops1q's console: the state every ASC_CON_DT s at fixed rows, the events
// below it (the newest last). Units: H / AP / PE km + K, VI m/s,
// VREL / HDOT / VGO m/s; degrees, g and PL % as they are; converted at the print. Everything comes from ops1q's run state (asc).
@LAZYGLOBAL OFF.

GLOBAL ASC_CON_DT IS 0.5.       // s between state updates
GLOBAL ASC_CON_W IS 50.         // columns (kOS's default terminal width)
GLOBAL ASC_CON_EV0 IS 14.       // the first event row
GLOBAL ASC_CON_NEV IS 9.        // event rows
GLOBAL ASC_FT IS 0.3048.        // m per ft

// MET from ops1q's liftoff UT (0 on the pad)
FUNCTION asc_met_of {
  PARAMETER asc.
  IF asc["t_lo"] < 0 { RETURN 0. }
  RETURN TIME:SECONDS - asc["t_lo"].
}

// x with nd decimals, right-aligned in w columns
FUNCTION asc_fmt {
  PARAMETER x, nd, w.
  LOCAL s IS "" + ROUND(x, nd).
  IF nd > 0 {
    LOCAL k IS s:FIND(".").
    IF k < 0 { SET s TO s + ".". SET k TO s:LENGTH - 1. }
    UNTIL s:LENGTH - k > nd { SET s TO s + "0". }
  }
  RETURN s:PADLEFT(w).
}

// t s as mm:ss (a minus sign before it when negative)
FUNCTION asc_mmss {
  PARAMETER t.
  LOCAL a IS ROUND(ABS(t)).
  LOCAL m IS FLOOR(a / 60).
  LOCAL ms IS "" + m.
  LOCAL ss IS "" + (a - 60 * m).
  LOCAL out IS ms:PADLEFT(2):REPLACE(" ", "0") + ":" + ss:PADLEFT(2):REPLACE(" ", "0").
  IF t < 0 { RETURN "-" + out. }
  RETURN out.
}

// one console row: s padded or cut to the width
FUNCTION asc_row {
  PARAMETER rw, s.
  PRINT s:PADRIGHT(ASC_CON_W):SUBSTRING(0, ASC_CON_W) AT (0, rw).
}

// the screen: its size, the rules; the state rows come with the first asc_con
FUNCTION asc_con_init {
  IF TERMINAL:WIDTH < ASC_CON_W { SET TERMINAL:WIDTH TO ASC_CON_W. }
  IF TERMINAL:HEIGHT < ASC_CON_EV0 + ASC_CON_NEV + 1 { SET TERMINAL:HEIGHT TO ASC_CON_EV0 + ASC_CON_NEV + 1. }
  CLEARSCREEN.
  LOCAL bar IS "".
  UNTIL bar:LENGTH >= ASC_CON_W { SET bar TO bar + "-". }
  asc_row(1, bar).
  asc_row(7, bar).
  asc_row(ASC_CON_EV0 - 1, bar).
}

// an event: on the console (the newest last), or in the pages' MESSAGES when they are up (lib_ascdisp's adEvent), and,
// from liftoff, in the PEG log as "#ev,met,text"
FUNCTION asc_event {
  PARAMETER asc, msg.
  LOCAL met IS asc_met_of(asc).
  IF DEFINED CW_VER { cwFromAsc(msg). }          // a fault line lights its lamp on the caution & warning panel (lib_cw's CW_MAP_ASC)
  IF asc["pg"] { adEvent(met, msg). }
  ELSE {
    asc["ev"]:ADD("T+" + asc_mmss(met) + " " + msg).
    IF asc["ev"]:LENGTH > ASC_CON_NEV { asc["ev"]:REMOVE(0). }
    LOCAL i IS 0.
    FOR l IN asc["ev"] {
      asc_row(ASC_CON_EV0 + i, l).
      SET i TO i + 1.
    }
  }
  IF asc["log"] <> "" { LOG "#ev," + met + "," + msg TO asc["log"]. }
}

// a line kept off the screen: in the PEG log alone (its #ev row, as asc_event's, for the tools)
FUNCTION asc_note {
  PARAMETER asc, msg.
  IF asc["log"] <> "" { LOG "#ev," + asc_met_of(asc) + "," + msg TO asc["log"]. }
}

// a message in a colour (kOS rich text; the pages' labels and the console both take it)
FUNCTION asc_col {
  PARAMETER s, c.
  RETURN "<color=" + c + ">" + s + "</color>".
}

// The state rows, at most every ASC_CON_DT s; cmd = the commanded attitude. G = the engines' thrust over the weight;
// PEG = converged, or the unconverged passes in a row, then the fine count from Event 31 and the MECO time once set.
FUNCTION asc_con {
  PARAMETER asc, cmd.
  IF TIME:SECONDS < asc["con_next"] { RETURN. }
  SET asc["con_next"] TO TIME:SECONDS + ASC_CON_DT.
  LOCAL met IS asc_met_of(asc).
  LOCAL upv IS SHIP:UP:VECTOR.
  LOCAL vo IS SHIP:VELOCITY:ORBIT.
  LOCAL f IS 0.
  IF asc["phase"] = "PAD" OR asc["phase"] = "STAGE1" { FOR en IN asc["srbs"] { SET f TO f + en:THRUST. } }
  FOR en IN asc["ssme"] { SET f TO f + en:THRUST. }
  LOCAL rs IS "HEADS DOWN".
  IF asc["t_roll"] >= 0 {
    SET rs TO "HEADS UP".
    IF ASC_ROLL_RATE * (met - asc["t_roll"]) < 180 { SET rs TO "ROLLING". }
  }
  asc_row(0, "OPS 1 ASCENT   " + asc["phase"]:PADRIGHT(10) + "   MET " + asc_mmss(met)).
  asc_row(2, "VREL  " + asc_fmt(SHIP:VELOCITY:SURFACE:MAG, 0, 7) + "     H     "
    + asc_fmt(SHIP:ALTITUDE / 1000, 1, 7) + "K").
  asc_row(3, "VI    " + asc_fmt(vo:MAG, 0, 7) + "     HDOT  " + asc_fmt(SHIP:VERTICALSPEED, 0, 8)).
  asc_row(4, "GAMMA " + asc_fmt(90 - VANG(vo, upv), 2, 7) + "     G     "
    + asc_fmt(f / (SHIP:MASS * CONSTANT:G0), 2, 8)).
  asc_row(5, "PITCH CMD " + asc_fmt(90 - VANG(cmd:VECTOR, upv), 1, 6) + "    FLOWN "
    + asc_fmt(90 - VANG(SHIP:FACING:VECTOR, upv), 1, 6)).
  asc_row(6, "K CMD " + asc_fmt(asc["kcmd"], 1, 7) + "     ROLL  " + rs).
  LOCAL st IS "--".
  LOCAL tgo IS 0.
  LOCAL vgo IS 0.
  LOCAL np IS 0.
  IF asc["s2_on"] {
    LOCAL g IS asc["g"].
    LOCAL p IS g["peg"].
    SET np TO p["npass"].
    SET tgo TO p["TGO"].
    SET vgo TO p["vgo"]:MAG.
    SET st TO CHOOSE "CONV" IF p["SCONV"] ELSE "UNCONV " + p["unconv"].
    IF g["S_MECO"] {
      SET st TO "FINE COUNT".
      SET vgo TO p["VDMAG"] - vo:MAG.
      IF g["TGO_FC"] >= 0 { SET tgo TO g["TGO_FC"]. }
      IF g["T_MECO"] >= 0 { SET st TO "MECO SET". SET tgo TO g["T_MECO"] - met. }
    }
  }
  asc_row(8, "PEG   " + st:PADRIGHT(10) + "  PASS " + asc_fmt(np, 0, 4) + "   TGO " + asc_mmss(tgo)).
  asc_row(9, "VGO   " + asc_fmt(vgo, 0, 7)).
  LOCAL hm IS ASC_MECO_H.        // the MECO target: PEG's (a TAL's once selected)
  LOCAL vm IS ASC_VDMAG.
  LOCAL gm IS ASC_GAMD.
  IF asc["s2_on"] {
    LOCAL pg IS asc["g"]["peg"].
    SET hm TO pg["RDMAG"] - ASC_R. SET vm TO pg["VDMAG"]. SET gm TO pg["GAMD"].
  }
  asc_row(10, "MECO TGT  H " + asc_fmt(hm / 1000, 1, 6) + "K" + "  VI " + asc_fmt(vm, 0, 6)
    + "  GAMMA " + asc_fmt(gm, 2, 5)).
  asc_row(11, "AP    " + asc_fmt(SHIP:APOAPSIS / 1000, 1, 6) + "K" + "     PE    " + asc_fmt(SHIP:PERIAPSIS / 1000, 1, 7) + "K").
  IF asc["why"] <> "" AND asc["t_meco"] >= 0 { asc_row(12, "MECO  " + asc["why"]:TOUPPER + " AT T+" + asc_mmss(asc["t_meco"])). }
}
