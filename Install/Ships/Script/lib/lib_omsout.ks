// lib_omsout.ks -- the OMS engines that FAILED, read back from ops2q's state file, and kept shut down (a failed engine must not come back on when ops3q toggles both).
//  The record: ops2q's o2qOmsFail (the one entry of every OMS failure) writes 1:/oms_out.txt, one line per failed engine,
//  "<k>,<why>,<engine UID>" (k 0 = L, 1 = R), the vessel's own volume, so a re-RUN of ops2q and the programs after it
//  (shuttle_exec, ops3q, ops6q's DAP) read it. A failure that HAS happened is kept; the failure SCHEDULE of the "!" window is not.
//  What the readers do with it: NEVER light, toggle or gimbal a failed engine again, the other flies alone:
//    omsOutRead()   the file into omsOutUid (by k); call it at the program's start (and again when ops2q may have written).
//    omsOutIs(en)   the engine en is a failed one (its UID is in the file).
//    omsOutAny()    at least one engine is failed.
//    omsOutKeep()   every failed engine found lit is shut down; returns how many (0 = none found lit).
//    omsOutOff()    "OMS off" for the entry (ops3q's AG2): with no failure, the craft's AG2 toggle as before; with one, NO toggle
//                   (a bare toggle FLIPS the engines: the shut-down failed one would come on), each lit OMS engine shut down
//                   by name instead. Returns the text for the program's event line ("" = AG2 toggled).
// Needs nothing else (SHIP:ENGINES, the volume 1:).
GLOBAL OMSOUT_FILE IS "1:/oms_out.txt".          // ops2q.ks O2Q_OMS_FILE (the same path)
GLOBAL omsOutUid IS LIST("", "").                // the failed engines' UIDs by k ("" = that engine is good)
GLOBAL omsOutWhy IS LIST("", "").                // why each failed (CREW, TIMED, SHUTDOWN, ...)

FUNCTION omsOutRead {
    SET omsOutUid TO LIST("", "").
    SET omsOutWhy TO LIST("", "").
    IF NOT EXISTS(OMSOUT_FILE) { RETURN. }
    FOR ln0 IN OPEN(OMSOUT_FILE):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL f IS ln0:TRIM:SPLIT(",").
        IF f:LENGTH >= 3 {
            LOCAL k IS f[0]:TONUMBER(-1).
            IF k >= 0 AND k <= 1 AND f[2]:TRIM <> "" {
                SET omsOutUid[k] TO f[2]:TRIM.
                SET omsOutWhy[k] TO f[1]:TRIM.
            }
        }
    }
}

FUNCTION omsOutAny { RETURN omsOutUid[0] <> "" OR omsOutUid[1] <> "". }

FUNCTION omsOutIs {
    PARAMETER en.
    IF NOT omsOutAny() { RETURN FALSE. }
    LOCAL u IS "" + en:UID.
    RETURN (omsOutUid[0] <> "" AND u = omsOutUid[0]) OR (omsOutUid[1] <> "" AND u = omsOutUid[1]).
}

FUNCTION omsOutKeep {
    LOCAL n IS 0.
    IF NOT omsOutAny() { RETURN 0. }
    FOR en IN SHIP:ENGINES {
        IF omsOutIs(en) AND en:IGNITION { en:SHUTDOWN(). SET n TO n + 1. }
    }
    RETURN n.
}

FUNCTION omsOutIsOms {                           // an OMS engine (ops2q's o2qOmsFind match)
    PARAMETER en.
    RETURN en:NAME:CONTAINS("AJ10") OR en:TITLE:CONTAINS("Manoeuvring") OR en:TITLE:CONTAINS("Maneuvering") OR en:TITLE:CONTAINS("Viking").
}

FUNCTION omsOutOff {
    omsOutRead().
    IF NOT omsOutAny() {
        TOGGLE AG2. WAIT 0.3.
        RETURN "".
    }
    LOCAL n IS 0.
    FOR en IN SHIP:ENGINES {
        IF omsOutIsOms(en) AND en:IGNITION { en:SHUTDOWN(). SET n TO n + 1. }
    }
    RETURN "OMS off by shutdown, no AG2 toggle (a failed engine stays out): " + n + " engine(s) shut down".
}
