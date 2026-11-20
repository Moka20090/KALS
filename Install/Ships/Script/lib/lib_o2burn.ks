// lib_o2burn.ks -- the record of the burns ops2q flew, on the vessel's own volume. A new RUN of ops2q 42000 s before the deorbit TIG found nothing that said which burns were
// flown: it loaded the plan file again (a deorbit that was already flown showed "DEORBIT LOADED: ARM WHEN READY" with its TIG in
// the past, a burn cut short by Ctrl+C reloaded with its full dV as unflown) and, after the deorbit cut, lost the OPS3 item.
//  The record: 1:/o2q_burn.txt (the vessel's own volume, like 1:/oms_out.txt and 1:/o2q_in.txt), one line per burn event,
//    ph,file,written,burn_ut,ut,sens,tot,why,d3
//    ph      EXEC (the sequence started: the burn is armed and committed), IGN (ignition), CUT (the burn ended: why = CUT / CREW /
//            THRUST / OMS / GUARD, sens the sensed dV, tot the planned one)
//    file    the plan file the burn was loaded from; written = its written_real_days; burn_ut = its burn_ut (the three name the plan)
//    ut      the UT of the event (EXEC: the TIG); d3 = 1 when this burn is the one that hands over to OPS3 (the deorbit burn or
//            the AOA's OMS-2: ops2q's o2qOps3Rule)
//  A plan is FLOWN when the newest line of its three keys is a CUT, CUT SHORT when it is an IGN (the program ended in the burn:
//  nothing says how much was flown), untouched when it is an EXEC or there is none (a sequence that never ignited: the plan is
//  still loadable). A new plan (another written / burn_ut) is never matched by an old line. The file keeps the newest O2B_MAX lines.
//    o2bRead()                the file into o2bRec (call at RUN, before ops2q lists the plan files).
//    o2bState(file, w, bu)    "" / "IGN" / "CUT" for that plan.   o2bLast(...): its newest line (sens, tot, why) or an empty LEXICON.
//    o2bPut(ph, k, ut, sens, tot, why)   one event of burn k (o2bKey) to the file and to o2bRec.
//    o2bOps3()                a CUT of an OPS3 burn is in the record.   o2bIgnD3(): an OPS3 burn ignited and never cut.
//  The file is small (a line is ~100 bytes) and written once per event; a full volume skips the write, never stops the burn.
GLOBAL O2B_FILE IS "1:/o2q_burn.txt".
GLOBAL O2B_MAX IS 12.                            // the newest lines kept
GLOBAL O2B_PHS IS LIST("EXEC", "IGN", "CUT").
GLOBAL o2bRec IS LIST().                         // LEXICON(ph, file, w, bu, ut, sens, tot, why, d3), oldest first

FUNCTION o2bKey {                                // the burn's identity from its source: LIST(file, written, burn_ut, d3)
    PARAMETER file, d, d3.
    RETURN LIST(file, CHOOSE d["written_real_days"] IF d:HASKEY("written_real_days") ELSE 0, CHOOSE d["burn_ut"] IF d:HASKEY("burn_ut") ELSE -1, d3).
}

FUNCTION o2bLine {
    PARAMETER rc.
    RETURN rc["ph"] + "," + rc["file"] + "," + ROUND(rc["w"], 7) + "," + ROUND(rc["bu"], 3) + "," + ROUND(rc["ut"], 2) + "," + ROUND(rc["sens"], 3)
        + "," + ROUND(rc["tot"], 3) + "," + rc["why"] + "," + rc["d3"].
}

FUNCTION o2bRead {
    SET o2bRec TO LIST().
    IF NOT EXISTS(O2B_FILE) { RETURN. }
    FOR ln0 IN OPEN(O2B_FILE):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL f IS ln0:TRIM:SPLIT(",").
        IF f:LENGTH >= 9 AND O2B_PHS:CONTAINS(f[0]) {
            o2bRec:ADD(LEXICON("ph", f[0], "file", f[1], "w", f[2]:TONUMBER(0), "bu", f[3]:TONUMBER(-1), "ut", f[4]:TONUMBER(0),
                "sens", f[5]:TONUMBER(0), "tot", f[6]:TONUMBER(0), "why", f[7], "d3", f[8]:TONUMBER(0))).
        }
    }
}

FUNCTION o2bSame {                               // the record r is a line of this plan
    PARAMETER rc, file, w, bu.
    RETURN rc["file"] = file AND ABS(rc["w"] - w) < 5E-7 AND ABS(rc["bu"] - bu) < 0.05.
}

FUNCTION o2bState {
    PARAMETER file, w, bu.
    FROM { LOCAL i IS o2bRec:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
        IF o2bSame(o2bRec[i], file, w, bu) {
            IF o2bRec[i]["ph"] = "EXEC" { RETURN "". }
            RETURN o2bRec[i]["ph"].
        }
    }
    RETURN "".
}

FUNCTION o2bLast {                               // the newest line of this plan (LEXICON), an empty one when there is none
    PARAMETER file, w, bu.
    FROM { LOCAL i IS o2bRec:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
        IF o2bSame(o2bRec[i], file, w, bu) { RETURN o2bRec[i]. }
    }
    RETURN LEXICON().
}

FUNCTION o2bPut {
    PARAMETER ph, k, ut, sens, tot, why.
    LOCAL rc IS LEXICON("ph", ph, "file", k[0], "w", k[1], "bu", k[2], "ut", ut, "sens", sens, "tot", tot, "why", why, "d3", CHOOSE 1 IF k[3] ELSE 0).
    o2bRec:ADD(rc).
    IF ph = "EXEC" AND o2bRec:LENGTH > O2B_MAX {         // the trim runs at EXEC (nothing hangs on it), never at ignition
        UNTIL o2bRec:LENGTH <= O2B_MAX { o2bRec:REMOVE(0). }
        IF EXISTS(O2B_FILE) { DELETEPATH(O2B_FILE). }
        FOR bq IN o2bRec { LOG o2bLine(bq) TO O2B_FILE. }
        RETURN.
    }
    LOCAL txl IS o2bLine(rc).
    IF VOLUME(1):FREESPACE < txl:LENGTH + 60 { RETURN. }
    LOG txl TO O2B_FILE.
}

FUNCTION o2bOps3 {
    FOR rc IN o2bRec { IF rc["ph"] = "CUT" AND rc["d3"] = 1 { RETURN TRUE. } }
    RETURN FALSE.
}

FUNCTION o2bIgnD3 {                              // an OPS3 burn that ignited and has no CUT after it
    FOR rc IN o2bRec {
        IF rc["ph"] = "IGN" AND rc["d3"] = 1 AND o2bState(rc["file"], rc["w"], rc["bu"]) = "IGN" { RETURN TRUE. }
    }
    RETURN FALSE.
}
