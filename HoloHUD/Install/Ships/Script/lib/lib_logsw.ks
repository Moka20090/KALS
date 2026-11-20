@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_LOGSW.KS  --  the logs' switch
// ============================================================================
//  SOCK_LOG is TRUE when 0:/logging.txt holds the one word "on"; without the file, or with any other word, it is
//  FALSE. The logs in 0:/logs (the flight and its events, the DAP, the landing, the burn, the planner's) and
//  mono_usage.csv are written only when it is TRUE; the plan, the family and the other files the programs hand on
//  are written either way. To switch, change the word in the file: each program reads it when it starts. The
//  release ships it "off".
//  Loaded by the programs and the libraries that log: RUNONCEPATH("0:/lib/lib_logsw.ks").
// ============================================================================

GLOBAL SOCK_LOG IS FALSE.
IF EXISTS("0:/logging.txt") {
    SET SOCK_LOG TO OPEN("0:/logging.txt"):READALL:STRING:TRIM:TOLOWER = "on".
}

// T686: a flight's id (ROUND(UT) at its start) repeats when the owner reloads one save, so a log named by it must never
// reuse an existing file (kOS LOG appends: the later flight lands in the earlier one's file). The repo's rule, first free:
// <base><ext>, then <base>_2<ext>, <base>_3<ext> ... (flightlogger, shuttle_exec, ops2q's burn log did it already).
FUNCTION logFree {
    PARAMETER base, ext.
    LOCAL p IS base + ext.
    LOCAL k IS 1.
    UNTIL NOT EXISTS(p) { SET k TO k + 1. SET p TO base + "_" + k + ext. }
    RETURN p.
}
// the same tag for SEVERAL files of one flight: the first of <t>, <t>_2, <t>_3 ... for which none of pfxs[i] + tag + ext
// exists (ops1q: ascent_peg_ and ascdap_ share it). Returns the tag as a string.
FUNCTION logFreeTag {
    PARAMETER t, pfxs, ext.
    LOCAL tag IS "" + t.
    LOCAL k IS 1.
    LOCAL again IS TRUE.
    UNTIL NOT again {
        SET again TO FALSE.
        FOR pf IN pfxs { IF EXISTS(pf + tag + ext) { SET again TO TRUE. } }
        IF again { SET k TO k + 1. SET tag TO t + "_" + k. }
    }
    RETURN tag.
}
