@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_CW.KS  --  the CAUTION & WARNING / MASTER ALARM state, shared by every program (no GUI here: lib_cwui.ks draws it)
// ============================================================================
//  The design: a panel of 12 lamps and a list of fault rows that pops up ONLY on a
//  CAUTION ("C", yellow) or a WARNING ("W", red). THE MASTER ALARM flashes red (with the class 2 tone, 400 / 1024 Hz, for a
//  CAUTION and a WARNING alike) until it is PRESSED; the press acknowledges everything (no ACK button), the SM ALERT light too. MSG RESET drops the
//  acknowledged rows whose fault is over; HIDE closes the panel (the next fault opens it again). A lamp stays lit while its
//  fault lasts (acknowledging does not put it out). A new row is in its class colour, an acknowledged one back to the display
//  green (lib_cwui).
//  Every C&W text is stored and shown in ALL CAPS (cwRaise / cwSet / cwAlert / cwSmShow upper it once); the log lines keep their case.
//  THE CLEAN API (the failure window and the checks of lib_cwchk call these; nothing else touches the state):
//    cwSet(lamp, cls, text)      the LEVEL form: "this lamp's fault is cls now" ("" = the fault is over). Raises when new,
//                                updates the row's text in place when it only changed, re-alarms only when the class rises.
//    cwRaise(lamp, cls, text)    the EVENT form: a fault happened (a row, a re-alarm; a repeat of an active one is ignored).
//    cwClear(lamp)               the fault is over (a FIX): the lamp goes dark and its rows are GREENED (acknowledged, as the
//                                press, that lamp only) until MSG RESET.
//    cwAlert(text)               a SOFTWARE ALERT (class 3, no lamp, no row, no master alarm): the SM ALERT light on the window lights
//                                with the text and the window sounds the 512 Hz tone once; the master press puts the light out.
//    cwPress() / cwReset() / cwHide()  the panel's three buttons.      cwFromKm(text, level): lib_kmsg's kmHook delegate.
//  LAMP KEYS (the grid, left to right, top to bottom):
//    LOMS ROMS OPRP MPS / FRCS LRCS RRCS JET / FCS GUID GPC ARM   (LEFT OMS, RIGHT OMS, OMS PRPLT, MPS / FWD RCS, LEFT RCS,
//    RIGHT RCS, RCS JET / FLT CNTL, GUID, GPC, ARM).   A line with lamp "" is a row with no lamp.
//  The host calls cwTick() each loop (the flash phase, the registered checks); the window follows CW_VER (it changes with
//  every change of the state) and the flash phase.
// ============================================================================
RUNONCEPATH("0:/lib/lib_kmsg.ks").

IF NOT (DEFINED CW_VER) {
    GLOBAL CW_VER IS 0.                              // +1 at every change of the lamps / rows / visibility (the window redraws)
    GLOBAL CW_VIS IS FALSE.                          // the panel is wanted open (a raise sets it, HIDE clears it)
    GLOBAL CW_LAMP IS LEXICON().                     // lamp key -> "" / "C" / "W"
    GLOBAL CW_ROWS IS LIST().                        // newest first: LIST(cls, text, met s, acked, lamp, active)
    GLOBAL CW_CHK IS LIST().                         // the checks: LIST(name, delegate(ut), dt, next ut)
    GLOBAL CW_METFN IS 0.                            // the host's MET delegate () -> s, 0 = seconds since cwInit
    GLOBAL CW_T0 IS -1.                              // the UT of cwInit
    GLOBAL CW_FAKE IS -1.                            // >= 0: the tests' clock (UT)
    GLOBAL CW_SM IS FALSE.                           // the SM ALERT light: a software alert waits for the MASTER ALARM press
    GLOBAL CW_SMTXT IS "".                           // the text of the latest software alert (shown while the light is on)
    GLOBAL CW_SMSEQ IS 0.                            // +1 per new software alert: the window sounds its tone once per count
}
GLOBAL CW_KEYS IS LIST("LOMS", "ROMS", "OPRP", "MPS", "FRCS", "LRCS", "RRCS", "JET", "FCS", "GUID", "GPC", "ARM").
GLOBAL CW_LBL IS LIST("LEFT OMS", "RIGHT OMS", "OMS PRPLT", "MPS", "FWD RCS", "LEFT RCS", "RIGHT RCS", "RCS JET", "FLT CNTL", "GUID", "GPC", "ARM").
GLOBAL CW_MAXROWS IS 12.                             // the fault screen's rows
GLOBAL CW_FLASH_HZ IS 2.                             // MASTER ALARM flash: on / off changes per second
// lib_kmsg line -> lamp: the first pattern the (upper-case) text contains wins; no match = a row with no lamp. The ascent's own
// lines go through CW_MAP_ASC (cwFromAsc); the checks of lib_cwchk raise their lamps themselves.
GLOBAL CW_MAP IS LIST(
    LIST("ENTRY TARGET AT", "GUID"),
    LIST("LANDRUN SHORT", "GUID")
).

// the ascent's own lines (ops1q: lib_ascent_con's asc_event, 100 call sites, no kmSay): LIST(pattern, second pattern or "", lamp or "", class);
// the first entry whose patterns the upper-case line contains wins; no entry = not a fault (an INFO line, a mode notice, a refused
// request that is only a prompt). The SSME-out detector (lib_ascent_eo) and the abort logic already say these lines; the 2EO / 3EO
// notices that follow an "SSME k FAIL" are not repeated (one failure = one row, as the real C&W's one MPS light).
GLOBAL CW_MAP_ASC IS LIST(
    LIST("SSME ", " FAIL", "MPS", "W"),              // SSME 2 FAIL  VI 6500
    LIST("RSLS ABORT", "", "MPS", "W"),              // RSLS ABORT: SSME 2 OUT AT T-1.2
    LIST("PAST NEGATIVE RETURN", "", "GUID", "W"),
    LIST("NO TAL SITE", "", "GUID", "W"),
    LIST("NO REACH", "", "GUID", "W"),               // SPLIT-S NO REACH: BAILOUT
    LIST("TOO LATE", "", "GUID", "C"),               // ABORT x: TOO LATE (the request is refused)
    LIST("PAD ABORT SEARCH FAILED", "", "GUID", "C"),
    LIST("NO OMS", "", "GUID", "C"),                 // NO OMS-2 PLAN / ATO: NO OMS PLAN / ATO: NO OMS-1 (no target)
    LIST("NO PLAN", "", "GUID", "C"),                // AOA OMS-2 NO PLAN
    LIST("OVER THE BUDGET", "", "OPRP", "C"),        // OMS-2 DV OVER THE BUDGET
    LIST("NO SPARE OMS", "", "OPRP", "C"),           // OMS ASSIST: NO SPARE OMS  ET MARGIN
    LIST("C# DAP", "", "FCS", "C"),                  // C# DAP LET GO / NOT ARMED: the kOS DAP flies
    LIST("C# CHECK: ERROR", "", "", "C"),
    LIST("KOS (", "", "", "C"),                      // a C# helper fell back to kOS (PEG / HUD / refresh / search)
    LIST("NOT INSTALLED", "", "", "C")
).

FUNCTION cwUt { RETURN CHOOSE CW_FAKE IF CW_FAKE >= 0 ELSE TIME:SECONDS. }
FUNCTION cwInit {                                    // metFn: a delegate () -> MET s, or 0
    PARAMETER metFn IS 0.
    SET CW_METFN TO metFn.
    CW_CHK:CLEAR().                                  // A new host brings its own checks (the last program's are dead or not its)
    SET CW_T0 TO cwUt().
    FOR k IN CW_KEYS { IF NOT CW_LAMP:HASKEY(k) { SET CW_LAMP[k] TO "". } }
}
FUNCTION cwMet {
    IF kmLive(CW_METFN) { RETURN CW_METFN:CALL(). }
    IF CW_T0 < 0 { RETURN 0. }
    RETURN cwUt() - CW_T0.
}
FUNCTION cwBump { SET CW_VER TO CW_VER + 1. }
FUNCTION cwMax {                                     // the higher class of two ("W" > "C" > "")
    PARAMETER a, b.
    IF a = "W" OR b = "W" { RETURN "W". }
    IF a = "C" OR b = "C" { RETURN "C". }
    RETURN "".
}

// the lamp's class now
FUNCTION cwLampCls {
    PARAMETER k.
    IF CW_LAMP:HASKEY(k) { RETURN CW_LAMP[k]. }
    RETURN "".
}
// the highest class among the unacknowledged rows = the MASTER ALARM ("" = quiet: nothing waits for a press)
FUNCTION cwMaster {
    LOCAL m IS "".
    FOR rw IN CW_ROWS { IF NOT rw[3] { SET m TO cwMax(m, rw[0]). } }
    RETURN m.
}
// the MASTER ALARM lamp's phase now (flashing while it is not acknowledged; always lit when steady is TRUE)
FUNCTION cwFlash {
    PARAMETER ut.
    RETURN MOD(FLOOR(ut * CW_FLASH_HZ), 2) = 0.
}
FUNCTION cwActiveRow {                               // the active row of a lamp (-1 = none)
    PARAMETER k.
    LOCAL i IS 0.
    FOR rw IN CW_ROWS { IF rw[4] = k AND rw[5] { RETURN i. } SET i TO i + 1. }
    RETURN -1.
}
FUNCTION cwLit { PARAMETER k. RETURN cwLampCls(k) <> "". }

// ---- the raising
FUNCTION cwAdd {                                     // a new row on top; the panel opens; the alarm is unacknowledged
    PARAMETER k, cls, txt.
    CW_ROWS:INSERT(0, LIST(cls, txt, cwMet(), FALSE, k, k <> "")).
    UNTIL CW_ROWS:LENGTH <= CW_MAXROWS { CW_ROWS:REMOVE(CW_ROWS:LENGTH - 1). }
    SET CW_VIS TO TRUE.
    cwBump().
}
FUNCTION cwRaise {
    PARAMETER k, cls, txt0, lg IS TRUE.
    LOCAL txt IS txt0:TOUPPER.                       // ALL CAPS; the log below keeps txt0
    IF cls <> "C" AND cls <> "W" { RETURN. }
    IF k <> "" { SET CW_LAMP[k] TO cwMax(cwLampCls(k), cls). }
    LOCAL i IS 0.
    FOR rw IN CW_ROWS {
        IF rw[1] = txt AND ((k <> "" AND rw[4] = k AND rw[5]) OR (k = "" AND rw[4] = "" AND NOT rw[3])) {
            SET rw[2] TO cwMet().                    // a repeat of an active fault: its time moves, no new alarm ...
            IF cls = "W" AND rw[0] = "C" { SET rw[0] TO "W". SET rw[3] TO FALSE. SET CW_VIS TO TRUE. }   // ... unless it got worse
            cwBump().
            RETURN.
        }
        SET i TO i + 1.
    }
    IF lg AND KM_LOG <> "" AND SOCK_LOG { LOG ROUND(cwUt(), 1) + " [" + cls + "] C&W " + k + " " + txt0 TO KM_LOG. }
    cwAdd(k, cls, txt).
}
FUNCTION cwClear {
    PARAMETER k.
    IF NOT CW_LAMP:HASKEY(k) { RETURN. }
    IF CW_LAMP[k] = "" { RETURN. }
    SET CW_LAMP[k] TO "".
    FOR rw IN CW_ROWS { IF rw[4] = k { SET rw[5] TO FALSE. SET rw[3] TO TRUE. } }   // A fix greens its own rows
    cwBump().
}
// the level form: the lamp's fault is cls now ("" = over)
FUNCTION cwSet {
    PARAMETER k, cls, txt0.
    IF cls = "" { cwClear(k). RETURN. }
    LOCAL txt IS txt0:TOUPPER.                       // ALL CAPS, as cwRaise (cwRaise logs txt0)
    LOCAL i IS cwActiveRow(k).
    IF i < 0 { cwRaise(k, cls, txt0). RETURN. }
    LOCAL rw IS CW_ROWS[i].
    IF cwMax(rw[0], cls) <> rw[0] {                  // worse: the row takes the class and the alarm sounds again
        SET rw[0] TO cls. SET rw[1] TO txt. SET rw[3] TO FALSE.
        SET CW_LAMP[k] TO cls.
        SET CW_VIS TO TRUE.
        cwBump().
    } ELSE IF rw[1] <> txt OR rw[0] <> cls {         // only the words changed (a count) or it got better: in place, silently
        SET rw[1] TO txt.
        IF cls <> rw[0] { SET rw[0] TO cls. SET CW_LAMP[k] TO cls. }   // better: the lamp steps down (W -> C)
        cwBump().
    }
}

// ---- the panel's buttons
FUNCTION cwPress {                                   // MASTER ALARM: acknowledge everything
    LOCAL ch IS FALSE.
    FOR rw IN CW_ROWS { IF NOT rw[3] { SET rw[3] TO TRUE. SET ch TO TRUE. } }
    IF CW_SM { SET CW_SM TO FALSE. SET ch TO TRUE. }  // any master alarm press resets every tone and the SM ALERT light (the log keeps the text)
    IF ch { cwBump(). }
}
FUNCTION cwReset {                                   // MSG RESET: the acknowledged rows whose fault is over go
    LOCAL i IS CW_ROWS:LENGTH - 1.
    LOCAL ch IS FALSE.
    UNTIL i < 0 {
        LOCAL rw IS CW_ROWS[i].
        IF rw[3] AND NOT rw[5] { CW_ROWS:REMOVE(i). SET ch TO TRUE. }
        SET i TO i - 1.
    }
    IF ch { cwBump(). }
}
FUNCTION cwHide { IF CW_VIS { SET CW_VIS TO FALSE. cwBump(). } }

// ---- lib_kmsg's hook: every CAUTION / WARNING line a program says; the text names its lamp by CW_MAP, or none
FUNCTION cwMapLamp {
    PARAMETER txt, map.
    LOCAL u IS txt:TOUPPER.
    FOR m IN map { IF u:CONTAINS(m[0]) { RETURN m[1]. } }
    RETURN "".
}
FUNCTION cwClean {                                   // "*** text" and "ops2q: text" -> the words; at most 60 characters
    PARAMETER txt.
    LOCAL s IS txt:TRIM.
    UNTIL NOT s:STARTSWITH("*") { SET s TO s:SUBSTRING(1, s:LENGTH - 1):TRIM. }
    IF s:LENGTH > 60 { SET s TO s:SUBSTRING(0, 60). }
    RETURN s.
}
// a SOFTWARE ALERT (class 3): no lamp, no row, no master alarm; the light + the text on the window, the tone once. A repeat of the
// text while the light is still on is ignored (no second tone).
FUNCTION cwSmShow {                               // The SM ALERT readout (CW_SM / CW_SMTXT) shows t, "" = the light and the text go out (no new alert: CW_SMSEQ stays)
    PARAMETER t.
    IF t = "" { SET CW_SM TO FALSE. SET CW_SMTXT TO "". cwBump(). RETURN. }
    SET CW_SM TO TRUE. SET CW_SMTXT TO cwClean(t):TOUPPER. cwBump().
}
FUNCTION cwAlert {
    PARAMETER txt, lg IS TRUE.
    LOCAL t IS cwClean(txt).
    IF t = "" { RETURN. }
    LOCAL tu IS t:TOUPPER.                           // ALL CAPS on the window (the log keeps t)
    IF CW_SM AND tu = CW_SMTXT { RETURN. }
    IF lg AND KM_LOG <> "" AND SOCK_LOG { LOG ROUND(cwUt(), 1) + " [S] C&W SM " + t TO KM_LOG. }
    SET CW_SM TO TRUE.
    SET CW_SMTXT TO tu.
    SET CW_SMSEQ TO CW_SMSEQ + 1.
    SET CW_VIS TO TRUE.
    cwBump().
}
FUNCTION cwFromKm {
    PARAMETER txt, lvl.
    IF lvl <> "C" AND lvl <> "W" { RETURN. }
    cwRaise(cwMapLamp(txt, CW_MAP), lvl, cwClean(txt), FALSE).   // kmSay logged it already
}
// the ascent's line: the map above (ops1q's asc_event calls this; the log has the line already)
FUNCTION cwFromAsc {
    PARAMETER msg.
    LOCAL u IS msg:TOUPPER.
    FOR m IN CW_MAP_ASC {
        IF u:CONTAINS(m[0]) AND (m[1] = "" OR u:CONTAINS(m[1])) {
            cwRaise(m[2], m[3], cwClean(msg), FALSE).
            RETURN.
        }
    }
}
// kmHook(cwFromKm@) for a program that has the panel
FUNCTION cwListen { kmHook(cwFromKm@). }

// ---- the checks: cwCheck(name, delegate(ut), dt s); cwTick runs the due ones
FUNCTION cwCheck {
    PARAMETER nm, fn, dt.
    CW_CHK:ADD(LIST(nm, fn, dt, 0)).
}
FUNCTION cwTick {                                    // each host loop (cheap when nothing is due)
    LOCAL ut IS cwUt().
    FOR c IN CW_CHK {
        IF ut >= c[3] {
            SET c[3] TO ut + c[2].
            IF kmLive(c[1]) { c[1]:CALL(ut). }       // never a delegate of a run that ended
        }
    }
}
