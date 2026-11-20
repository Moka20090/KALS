@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_KMSG.KS  --  the kOS terminal stays blank in flight; every line goes to the log and to the window's MSG line
// ============================================================================
//  The terminal is blank from launch to landing, nominal flight or not. A flight program says
//  its lines with kmSay(text, level) instead of PRINT. The level is the severity (for the caution and
//  warning panel that hooks in here): "I" INFO, "C" CAUTION (a fallback, a missing file, a feature that did not
//  start: the flight goes on), "W" WARNING (an abort, an engine out, a failure that changes the flight). The order of kmSay:
//    1. the program's log (kmLogTo's path), when the logs are on (lib_logsw's SOCK_LOG): "<UT> [<level>] <text>";
//    2. the sink (kmSink's delegate (text, level), the window's MSG line: ops2q's MSG rows);
//    3. the hook (kmHook's delegate (text, level)), for every CAUTION and WARNING: the place a panel attaches;
//    4. the terminal (PRINT) only while the quiet flag is FALSE.
//  The quiet flag starts FALSE, so the kOS VM tests, the tools and a headless run print as before. A flight program sets
//  it TRUE (kmQuiet); a program whose window cannot be built leaves it FALSE: with no window the terminal is the only
//  display, so it prints. A program with no window that has a MSG line has no sink: its lines are in the log only
//  (log only). While quiet and with no sink the lines wait in KM_PEND (the newest 40); kmSink hands them
//  to the sink, kmQuiet(FALSE) prints them, and kmLogTo writes the ones said before the log's path was known.
//  Loaded by the programs and the libraries that say anything: RUNONCEPATH("0:/lib/lib_kmsg.ks").
// ============================================================================
RUNONCEPATH("0:/lib/lib_logsw.ks").                  // SOCK_LOG

IF NOT (DEFINED KM_QUIET) {
    GLOBAL KM_QUIET IS FALSE.
    GLOBAL KM_SINK IS 0.                             // a delegate (text, level), 0 = none
    GLOBAL KM_HOOK IS 0.                             // a delegate (text, level) for the CAUTION and WARNING lines, 0 = none
    GLOBAL KM_LOG IS "".                             // the log file's path, "" = none
    GLOBAL KM_PEND IS LIST().                        // the lines said while quiet with no sink: LIST(text, level, UT)
    GLOBAL KM_UNLOGGED IS LIST().                    // the lines said before kmLogTo: LIST(text, level, UT)
    GLOBAL KM_N IS 0.                                // the lines said (the tests read it)
}
GLOBAL KM_PEND_MAX IS 40.
// T648: a delegate is callable only while the program run that made it is alive (kOS: "Cannot call this lock or function or
// delegate from one program run when it was declared in another"). KM_SINK / KM_HOOK live on in the GLOBALs above after their
// program ended, so a dead one is dropped when this library loads in a new run, and kmPut never calls a dead one.
FUNCTION kmLive {
    PARAMETER d.
    IF NOT d:HASSUFFIX("CALL") { RETURN FALSE. }
    IF d:HASSUFFIX("ISDEAD") { IF d:ISDEAD { RETURN FALSE. } }
    RETURN TRUE.
}
IF NOT kmLive(KM_SINK) { SET KM_SINK TO 0. }
IF NOT kmLive(KM_HOOK) { SET KM_HOOK TO 0. }

// the log's path; the lines said before it was known are written now
FUNCTION kmLogTo {
    PARAMETER lf.
    SET KM_LOG TO lf.
    IF lf <> "" {
        IF SOCK_LOG { FOR u IN KM_UNLOGGED { LOG ROUND(u[2], 1) + " [" + u[1] + "] " + u[0] TO lf. } }
        KM_UNLOGGED:CLEAR().
    }
}

// quiet TRUE: the terminal stays blank; FALSE: it prints (and the lines that waited are printed now)
FUNCTION kmQuiet {
    PARAMETER qt.
    SET KM_QUIET TO qt.
    IF NOT qt {
        FOR p IN KM_PEND { PRINT p[0]. }
        KM_PEND:CLEAR().
    }
}

// the window's MSG line: fn is a delegate (text, level); the lines that waited go to it now
FUNCTION kmSink {
    PARAMETER fn.
    SET KM_SINK TO fn.
    IF kmLive(KM_SINK) {
        FOR p IN KM_PEND { KM_SINK:CALL(p[0], p[1]). }
        KM_PEND:CLEAR().
    }
}

// the hook for a caution / warning panel: a delegate (text, level), 0 = none
FUNCTION kmHook { PARAMETER fn. SET KM_HOOK TO fn. }

// at (col, row) on the terminal when it prints: the fixed-row lines of a console display (the same line as kmSay otherwise)
FUNCTION kmPut {
    PARAMETER txt, lvl, col, row.
    SET KM_N TO KM_N + 1.
    IF KM_LOG <> "" {
        IF SOCK_LOG { LOG ROUND(TIME:SECONDS, 1) + " [" + lvl + "] " + txt TO KM_LOG. }
    } ELSE {
        KM_UNLOGGED:ADD(LIST(txt, lvl, TIME:SECONDS)).
        IF KM_UNLOGGED:LENGTH > KM_PEND_MAX { KM_UNLOGGED:REMOVE(0). }
    }
    IF kmLive(KM_SINK) {
        KM_SINK:CALL(txt, lvl).
    } ELSE IF KM_QUIET {
        KM_PEND:ADD(LIST(txt, lvl)).
        IF KM_PEND:LENGTH > KM_PEND_MAX { KM_PEND:REMOVE(0). }
    }
    IF lvl <> "I" AND kmLive(KM_HOOK) { KM_HOOK:CALL(txt, lvl). }
    IF NOT KM_QUIET {
        IF row >= 0 { PRINT txt AT (col, row). } ELSE { PRINT txt. }
    }
}
FUNCTION kmSay {
    PARAMETER txt, lvl IS "I".
    kmPut(txt, lvl, 0, -1).
}
FUNCTION kmSayAt {
    PARAMETER txt, lvl, col, row.
    kmPut(txt, lvl, col, row).
}
