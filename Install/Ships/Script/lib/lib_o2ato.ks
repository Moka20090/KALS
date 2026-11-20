// ============================================================================================================
//  lib_o2ato.ks  --  ops2q's ATO / AOA TGT page: the numbers behind it (the decision is asked before OMS-1 and reversible until its ignition)
// ============================================================================================================
//  The page (the canvas Ri1pDLPR9Wd4RJGyhKBPbg, board AtoAoa 2025/) shows the two modes side by side, ATO in one column and AOA
//  in the other: SITE, TYPE (SHALLOW / STEEP, the computer's), OMS-1 and OMS-2 (TIG, DV), TOTAL DV, OMS LEFT, the orbit after
//  (ATO), the entry FPA and the landing time (AOA), STATUS GO / NO GO and WHY; SELECT ATO / AOA / AUTO.
//  THE SOLVES ARE THE OLD ONES, UNCHANGED: the ATO's OMS-2 is omsAto's (the circle at ASC_ATO_H at the apoapsis: lib_oms_plan.ks),
//  the AOA's is aoaSolve's (lib_aoa.ks, through aoaSolveFrom = aoaSolveNow's body on a given state), GO is aoaAsk's rule (the
//  ATO: the OMS left after OMS-2 covers the deorbit reserve dv_keep; the AOA: the solve found a plan within the OMS less
//  AOA_OMS_RESERVE). Before OMS-1 both are computed on the orbit AFTER it (Kepler, the impulse at its centre: ops2q's o2qAfter), the
//  state aoaAsk solved from after OMS-1 was flown; after OMS-1 on the real orbit. This file holds the pure parts (ops2q.ks has the
//  glue and the page): o2atCols, the rule of the computer's pick, the hand-off file ops1q writes, the text helpers.
//  THE HAND-OFF (ops1q -> ops2q): 1:/ops2q_ho.txt on the vessel's volume, "key value" lines: abort (ATO), why, pick (ops1q's own
//  guess), ha / hp (km) / vi (m/s) / oms (kg) at MECO, dv1 / dv2 / keep / dvo (m/s), oms1 (1 = an OMS-1 plan was written),
//  site (the launch site), ph (PRE until OMS-1 is flown, POST after it, DONE once OMS-2 ignites). ops1q deletes it at liftoff.
// ============================================================================================================


GLOBAL O2AT_HO_FILE IS "1:/ops2q_ho.txt".
GLOBAL O2AT_LAND_S IS 2000.                  // s: the entry interface to the landing (the LAND row's estimate)
GLOBAL O2AT_SITE_NAME IS LEXICON("SLF", "KSC SLF", "VBG", "VBG").

// ---- the hand-off file
FUNCTION o2atHoRead {                        // the hand-off as a LEXICON (numbers as numbers where they parse), EMPTY when there is none
    LOCAL ho IS LEXICON().
    IF NOT EXISTS(O2AT_HO_FILE) { RETURN ho. }
    FOR hl IN OPEN(O2AT_HO_FILE):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL t IS hl:TRIM.
        LOCAL k IS t:FIND(" ").
        IF k > 0 {
            LOCAL key IS t:SUBSTRING(0, k).
            LOCAL val IS t:SUBSTRING(k + 1, t:LENGTH - k - 1):TRIM.
            LOCAL nv IS val:TONUMBER(-1E30).
            IF nv > -1E29 AND key <> "why" AND key <> "site" AND key <> "abort" AND key <> "pick" AND key <> "ph" { SET ho[key] TO nv. }
            ELSE { SET ho[key] TO val. }
        }
    }
    RETURN ho.
}

FUNCTION o2atHoWrite {                       // ho = LEXICON: written afresh (the file is the whole state)
    PARAMETER ho.
    IF EXISTS(O2AT_HO_FILE) { DELETEPATH(O2AT_HO_FILE). }
    FOR k IN ho:KEYS { LOG k + " " + ho[k] TO O2AT_HO_FILE. }
}

FUNCTION o2atHoSet {                         // one key changed in the file
    PARAMETER key, val.
    LOCAL ho IS o2atHoRead().
    IF ho:LENGTH = 0 { RETURN. }
    SET ho[key] TO val.
    o2atHoWrite(ho).
}

FUNCTION o2atHoEnd {                         // OMS-2 flown (or no OMS-2 to come): the hand-off is over
    IF EXISTS(O2AT_HO_FILE) { DELETEPATH(O2AT_HO_FILE). }
}

// ---- propellant
FUNCTION o2atKg {                            // kg of OMS propellant left after dvT m/s of the dvo m/s on board (m0 t at the start, ve m/s): the rocket equation both ways
    PARAMETER m0, dvo, dvT, ve.
    RETURN 1000 * m0 * (CONSTANT:E ^ (-dvT / ve) - CONSTANT:E ^ (-dvo / ve)).
}

// ---- the columns
// inp: dvo (m/s on board now), keep (m/s: the deorbit's reserve), rsv (AOA_OMS_RESERVE), m0 (t), ve (m/s),
//   dv1, tig1 (UT of ignition) the OMS-1 still to fly (0 = none), dv2 (the ATO's OMS-2 signed m/s on the orbit after it, 0 with none),
//   tig2 (its ignition UT), ra, rt (the orbit after OMS-2: apoapsis radius, the new periapsis radius, m), rbody (m),
//   x (aoaSolve's lexicon, 0 = none), tb2 (the AOA burn's length s), why (AOA_WHY)
// returns LEXICON("ato", col, "aoa", col, "auto", "ATO" / "AOA"); a col: ok go why dv1 tig1 dv2 tig2 tot left (kg) leftdv
//   (m/s) rsvkg (kg wanted) + the ATO's ha / hp (km), the AOA's site rwy type fpa land
FUNCTION o2atCols {
    PARAMETER inp.
    LOCAL dvo IS inp["dvo"].
    LOCAL dv1 IS inp["dv1"].
    LOCAL ato IS LEXICON("ok", FALSE, "go", FALSE, "why", "", "dv1", dv1, "tig1", inp["tig1"], "dv2", 0, "tig2", 0, "tot", 0,
        "left", 0, "leftdv", 0, "ha", 0, "hp", 0).
    LOCAL aoa IS LEXICON("ok", FALSE, "go", FALSE, "why", "", "dv1", dv1, "tig1", inp["tig1"], "dv2", 0, "tig2", 0, "tot", 0,
        "left", 0, "leftdv", 0, "site", "", "rwy", "", "type", "", "fpa", 0, "land", 0, "ramp", FALSE).
    LOCAL rsvkg IS o2atKg(inp["m0"], dvo, dvo - inp["keep"], inp["ve"]).   // the kg of propellant that is the deorbit's reserve
    SET ato["rsvkg"] TO rsvkg.
    // the ATO
    IF ABS(inp["dv2"]) > 0 OR inp["tig2"] > 0 {
        SET ato["ok"] TO TRUE.
        SET ato["dv2"] TO ABS(inp["dv2"]).
        SET ato["tig2"] TO inp["tig2"].
        SET ato["tot"] TO dv1 + ABS(inp["dv2"]).
        SET ato["leftdv"] TO dvo - ato["tot"].
        SET ato["left"] TO o2atKg(inp["m0"], dvo, ato["tot"], inp["ve"]).
        SET ato["ha"] TO (inp["ra"] - inp["rbody"]) / 1000.
        SET ato["hp"] TO (inp["rt"] - inp["rbody"]) / 1000.
        SET ato["go"] TO ato["leftdv"] >= inp["keep"].
        IF NOT ato["go"] { SET ato["why"] TO "OMS RSV " + ROUND(rsvkg). }
    } ELSE { SET ato["why"] TO "NO APOAPSIS". }
    // the AOA
    LOCAL x IS inp["x"].
    IF NOT (x = 0) {
        LOCAL dv2 IS CHOOSE x["dv"] IF x:HASKEY("dvr") AND ABS(x["dvr"]) > 0 ELSE ABS(x["dvt"]).
        SET aoa["ok"] TO TRUE.
        SET aoa["dv2"] TO dv2.
        SET aoa["tig2"] TO x["ut"] - inp["tb2"] / 2.
        SET aoa["tot"] TO dv1 + dv2.
        SET aoa["leftdv"] TO dvo - aoa["tot"].
        SET aoa["left"] TO o2atKg(inp["m0"], dvo, aoa["tot"], inp["ve"]).
        SET aoa["go"] TO TRUE.
        SET aoa["site"] TO CHOOSE O2AT_SITE_NAME[x["site"]] IF O2AT_SITE_NAME:HASKEY(x["site"]) ELSE x["site"].
        SET aoa["rwy"] TO x["rwy"]:REPLACE(x["site"], "").
        LOCAL steep IS FALSE.
        IF x:HASKEY("fpaUsed") AND x:HASKEY("fpaTarget") { SET steep TO x["fpaUsed"] > x["fpaTarget"] + 1E-6. }
        SET aoa["type"] TO (CHOOSE "STEEP" IF steep ELSE "SHALLOW").
        SET aoa["ramp"] TO x["ramp"].
        SET aoa["fpa"] TO -ABS(x["fpa"]).
        SET aoa["land"] TO x["ut"] + x["tc"] + O2AT_LAND_S.
    } ELSE { SET aoa["why"] TO o2atWhy(inp["why"]). }
    LOCAL pick IS "ATO".
    IF NOT ato["go"] AND aoa["go"] { SET pick TO "AOA". }
    RETURN LEXICON("ato", ato, "aoa", aoa, "auto", pick).
}

FUNCTION o2atWhy {                           // aoaSolve's why text as the page's short word (the whole text goes to MSG)
    PARAMETER w.
    IF w:STARTSWITH("EI IN") { RETURN "NO TIME". }
    IF w:STARTSWITH("NOT IN ORBIT") { RETURN "NOT ORBIT". }
    IF w:STARTSWITH("NO OMS-2 WITHIN") { RETURN "NO REACH". }
    RETURN "NO SOLUTION".
}

FUNCTION o2atPick {                          // the pick that flies: the crew's (0 ATO, 1 AOA) or, on AUTO (2), the computer's
    PARAMETER sel, cols.
    IF sel = 0 { RETURN "ATO". }
    IF sel = 1 { RETURN "AOA". }
    RETURN cols["auto"].
}

FUNCTION o2atMode {                          // the mode its column can take now: TRUE = selectable (after OMS-1 only a GO mode is)
    PARAMETER cols, md, post.
    IF NOT post { RETURN TRUE. }
    RETURN cols[CHOOSE "ato" IF md = "ATO" ELSE "aoa"]["go"].
}
