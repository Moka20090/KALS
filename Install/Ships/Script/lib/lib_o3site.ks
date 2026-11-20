// ============================================================================================================
//  lib_o3site.ks  --  ops3q's LANDING SITE WHEN THERE IS NO DEORBIT PLAN
// ============================================================================================================
//  With a plan the runway and the aim come from the plan file and none of this runs (ops3q loads this file only on its
//  no-plan branch). With none, ops3q used to land at OPS_SITE's end nearest the ground track, reach or no reach. o3stPick
//  does what the orbiter's crew does from the footprint: from the vessel's REAL post-burn orbit it predicts the entry and
//  picks, among the sites we have, the one whose runway is inside the entry's reach with the most margin.
//  THE FOOTPRINT TEST IS THE PLANNER'S OWN (deorbit_plan.ks, loaded here the way lib_o2dorb's o2dbLoad loads it): what a
//  planned burn is checked against. Its constants (DP_AZ_MAX, DP_TURN_LOSS_MAX, DP_BANK, DP_FTP_ARRIVAL_K, DP_SIDE_TOL_M) and its
//  predictions (dpArcAt: the arc flown to TAEM at a constant bank, on Sol with the entry's own lateral logic toward the aim,
//  so the CROSSRANGE shortens the long arc; the KAL/S coprocessor's DPARC, kOS's own on any failure) are read from it, none
//  copied. Per runway end, from the interface state eprKepToEI coasts from the orbit (J2 on Sol):
//    AIM       the planner's arrival-aligned FTP without a burn solve: the FTP built on the bearing of the great circle through
//              the interface and the threshold, then rebuilt on dpArrivalBearing (the bearing the entry arrives on);
//    SIDE      the aim on the approach side of the threshold (dpBackset, dpFlyable's side gate);
//    AZIMUTH   mA = 1 - |interface azimuth error to the aim| / DP_AZ_MAX;
//    REACH     the range to the aim between the arc flown at EPR_BANK_MAX (short) and at EPR_BANK_MIN (long):
//              mR = the smaller distance to either edge / half the window;
//    TURN LOSS (Sol) one prediction at DP_BANK: mT = 1 - the along-track shortfall at TAEM / (DP_TURN_LOSS_MAX x range).
//  Each m is a fraction of its own limit: 1 dead centre, 0 on the limit, below 0 outside. score = the smallest of the three
//  (>= 0 exactly when dpFlyable would say ""). Cheap rejects first (side, azimuth): most ends cost no prediction.
//  THE CHOICE: the main sites SLF, EAFB, VBG first (the abort sites, rows flagged 1 in hud_runways.txt, only when no main end
//  is flyable). Per site the end with the lower predicted HAC turn (360 - |norm180(arrival bearing - landing heading)|, the
//  planner's AUTO rule) among the ends whose score >= O3ST_END_MIN, else the best score. The site with the best score wins;
//  a gap under O3ST_TIE keeps the earlier site in the list. NONE FLYABLE: the end with the best (least negative) score and
//  ok = FALSE: ops3q lands at it (the nearest runway the entry can reach) and says so. Nothing could be judged (no entry, no
//  rows, the time cap before the first judgement): 0, and ops3q's old fallback (opsFallbackRunway) runs unchanged.
//  O3ST_MAX_S: the whole pick stops judging ends past this much game time (without the C# addon every prediction is kOS's
//  and takes minutes).
//  KNOWN APPROXIMATION: the predictions fly DP_BANK (60), not an AOA's pre-entry bank 90 (an AOA nearly always has its plan).
//  Needs entry_predict.ks, lib_kepler.ks (loaded by the planner), lib_kmsg.ks, lib_logsw.ks (ops3q loads both).
// ============================================================================================================
@LAZYGLOBAL OFF.

GLOBAL O3ST_ON IS FALSE.                 // the planner's definitions are loaded
GLOBAL O3ST_WHY IS "".                   // why the last pick returned 0
GLOBAL O3ST_MAX_S IS 90.                 // s of game time the pick may judge ends for
GLOBAL O3ST_END_MIN IS 0.15.             // the margin an end needs for the lower-turn rule to prefer it over the better-margin end
GLOBAL O3ST_TIE IS 0.05.                 // a margin gap under this keeps the earlier site
GLOBAL O3ST_MAIN IS LIST("SLF", "EAFB", "VBG").
GLOBAL O3ST_LOG IS "0:/logs/o3_site.txt".
GLOBAL O3ST_ROWS IS LIST().              // the last pick's rows (the log's lines)
GLOBAL O3ST_SOL IS 0.                    // the last pick's interface state LEXICON(rei, vei, tRot, sideOk) (the tests)

FUNCTION o3stLoad {                      // the planner's definitions (the ~90 KB file; lib_o2dorb's o2dbLoad does the same)
    IF O3ST_ON { RETURN TRUE. }
    IF NOT (DEFINED DP_LOADED) {
        IF NOT EXISTS("0:/deorbit_plan.ks") { SET O3ST_WHY TO "NO DEORBIT_PLAN.KS". RETURN FALSE. }
        GLOBAL DP_NO_RUN IS TRUE.        // consumed by the file (DP_SKIP_NOW): its executive does not run
        RUNONCEPATH("0:/deorbit_plan.ks").
    }
    SET O3ST_ON TO TRUE.
    RETURN TRUE.
}

// The sites of the runway table, LIST(main in O3ST_MAIN's order, the abort sites in the file's order): an abort site is a row
// whose last field (the table's els column) is 1.
FUNCTION o3stSites {
    LOCAL abSites IS LIST().
    IF EXISTS(DP_RWY_FILE) {
        FOR lin IN OPEN(DP_RWY_FILE):READALL:STRING:SPLIT(CHAR(10)) {
            LOCAL w IS capeLine(lin:REPLACE(CHAR(13), "")):SPLIT(" ").
            IF w:LENGTH >= 15 {
                IF w[0] = "R" AND w[14] = "1" AND NOT abSites:CONTAINS(w[1]) { abSites:ADD(w[1]). }
            }
        }
    }
    RETURN LIST(O3ST_MAIN, abSites).
}

// One runway end th (dpSiteTable's row LIST(name, lat, lng, landing heading, aim shift)) against the interface state of sol and
// its ground point gEi: a LEXICON (see the header). tEnd = the UT past which no prediction is started.
FUNCTION o3stEval {
    PARAMETER site, th, sol, gEi, tEnd.
    LOCAL row IS LEXICON("site", site, "rwy", th[0], "ok", FALSE, "judged", FALSE, "why", "", "score", -9, "mR", 0, "mA", 0, "mT", 0,
                         "az", 0, "rng", 0, "shortM", 0, "longM", 0, "shortE", 0, "turn", 0, "beta", 0, "aimLat", 0, "aimLng", 0).
    // THE AIM: the planner's two steps (dpPlanChain: the FTP on the track, then on the arrival bearing), the track here being
    // the great circle's continuation through the threshold
    LOCAL b0 IS kepBearing(th[1], th[2], gEi[0], gEi[1]) + 180.
    LOCAL f0 IS kepBuildFtp(th[1], th[2], b0, th[3], th[4]).
    LOCAL beta IS dpArrivalBearing(sol, f0[0], f0[1]).
    LOCAL aim IS kepBuildFtp(th[1], th[2], beta, th[3], th[4]).
    SET row["beta"] TO beta.
    SET row["aimLat"] TO aim[0].
    SET row["aimLng"] TO aim[1].
    SET row["turn"] TO 360 - ABS(kepNorm180(beta - th[3])).
    SET row["rng"] TO eprGcDist(gEi[0], gEi[1], aim[0], aim[1]).
    // SIDE: the FTP is this far from its threshold by construction; the backset must be one FTP range (dpSolveBurn's assert)
    LOCAL ftpM IS eprGcDist(th[1], th[2], aim[0], aim[1]).
    IF ABS(dpBackset(gEi, aim[0], aim[1], th[1], th[2]) - ftpM) > DP_SIDE_TOL_M {
        SET row["why"] TO "WRONG SIDE".
        RETURN row.
    }
    // AZIMUTH
    LOCAL az IS eprAzErrorAt(sol["rei"], sol["vei"], sol["tRot"], aim[0], aim[1]).
    SET row["az"] TO az.
    SET row["mA"] TO 1 - ABS(az) / DP_AZ_MAX.
    SET row["score"] TO row["mA"].
    SET row["judged"] TO TRUE.
    IF ABS(az) > DP_AZ_MAX {
        SET row["why"] TO "AZIMUTH " + ROUND(ABS(az)) + " DEG, LIMIT " + ROUND(DP_AZ_MAX).
        RETURN row.
    }
    IF TIME:SECONDS > tEnd {
        SET row["judged"] TO FALSE.
        SET row["why"] TO "NOT JUDGED (TIME)".
        SET row["score"] TO -7.
        RETURN row.
    }
    // REACH: the two edges (dpArcAt: -1 = no prediction)
    LOCAL longM IS dpArcAt(sol, EPR_BANK_MIN, aim[0], aim[1]).
    LOCAL shortM IS dpArcAt(sol, EPR_BANK_MAX, aim[0], aim[1]).
    IF longM < 0 OR shortM < 0 {
        SET row["why"] TO "PREDICTION FAILED".
        SET row["score"] TO -8.
        RETURN row.
    }
    SET row["longM"] TO longM.
    SET row["shortM"] TO shortM.
    LOCAL half IS MAX(1000, (longM - shortM) / 2).
    LOCAL rng IS row["rng"].
    SET row["mR"] TO MIN(longM - rng, rng - shortM) / half.
    SET row["mT"] TO 1.
    IF rng > longM {
        SET row["why"] TO "BEYOND REACH " + ROUND((rng - longM) / 1000) + " KM, LONGEST " + ROUND(longM / 1000).
    } ELSE IF rng < shortM {
        SET row["why"] TO "INSIDE REACH " + ROUND((shortM - rng) / 1000) + " KM, SHORTEST " + ROUND(shortM / 1000).
    }
    IF row["why"] = "" AND EPR_PRED_LATERAL {       // TURN LOSS (Sol): one entry at the preentry bank
        IF dpArcAt(sol, DP_BANK, aim[0], aim[1]) < 0 {
            SET row["why"] TO "PREDICTION FAILED".
            SET row["score"] TO -8.
            RETURN row.
        }
        LOCAL te IS sol["tRot"] + EPR_IT.
        LOCAL gEnd IS eprToGeoInertial(EPR_IR, te).
        LOCAL azE IS eprAzErrorAt(EPR_IR, EPR_IV, te, aim[0], aim[1]).
        LOCAL shortE IS eprGcDist(gEnd[0], gEnd[1], aim[0], aim[1]) * COS(azE).
        SET row["shortE"] TO shortE.
        SET row["mT"] TO 1 - shortE / (DP_TURN_LOSS_MAX * rng).
        IF shortE > DP_TURN_LOSS_MAX * rng {
            SET row["why"] TO "TURN LOSS " + ROUND(shortE / 1000) + " KM, LIMIT " + ROUND(DP_TURN_LOSS_MAX * rng / 1000).
        }
    }
    SET row["score"] TO MIN(row["mR"], MIN(row["mA"], row["mT"])).
    SET row["ok"] TO (row["why"] = "").
    RETURN row.
}

// A site's best end among its flyable rows: the lower HAC turn among those with score >= O3ST_END_MIN, else the best score; 0
// when none is flyable.
FUNCTION o3stEnd {
    PARAMETER rows.
    LOCAL bestMargin IS 0.
    LOCAL bestAny IS 0.
    FOR rw IN rows {
        IF rw["ok"] {
            IF bestAny = 0 { SET bestAny TO rw. } ELSE IF rw["score"] > bestAny["score"] { SET bestAny TO rw. }
            IF rw["score"] >= O3ST_END_MIN {
                IF bestMargin = 0 { SET bestMargin TO rw. } ELSE IF rw["turn"] < bestMargin["turn"] { SET bestMargin TO rw. }
            }
        }
    }
    IF NOT (bestMargin = 0) { RETURN bestMargin. }
    RETURN bestAny.
}

// One line per judged end for the log file (SOCK_LOG): the table the choice came from.
FUNCTION o3stLog {
    PARAMETER pick.
    IF NOT SOCK_LOG { RETURN. }
    IF EXISTS(O3ST_LOG) { DELETEPATH(O3ST_LOG). }
    LOG "site,rwy,ok,rng_km,short_km,long_km,az_deg,turnloss_km,hac_turn,mR,mA,mT,score,why" TO O3ST_LOG.
    FOR rw IN O3ST_ROWS {
        LOG rw["site"] + "," + rw["rwy"] + "," + rw["ok"] + "," + ROUND(rw["rng"] / 1000) + "," + ROUND(rw["shortM"] / 1000) + ","
            + ROUND(rw["longM"] / 1000) + "," + ROUND(rw["az"], 1) + "," + ROUND(rw["shortE"] / 1000, 1) + "," + ROUND(rw["turn"]) + ","
            + ROUND(rw["mR"], 3) + "," + ROUND(rw["mA"], 3) + "," + ROUND(rw["mT"], 3) + "," + ROUND(rw["score"], 3) + "," + rw["why"] TO O3ST_LOG.
    }
    IF pick:ISTYPE("Lexicon") {
        LOG "# CHOSEN " + pick["rwy"] + " score " + ROUND(pick["score"], 3) + " flyable " + pick["ok"] + " rows " + O3ST_ROWS:LENGTH TO O3ST_LOG.
    } ELSE { LOG "# NO PICK: " + O3ST_WHY TO O3ST_LOG. }
}

// THE PICK: LEXICON("ok", flyable, "rwy", the end, "site", .., "aim", LATLNG, "beta", the arrival bearing, "score", .., "turn", ..,
// "line", a one-line verdict) or 0 (see the header; O3ST_WHY says why).
FUNCTION o3stPick {
    SET O3ST_WHY TO "".
    SET O3ST_ROWS TO LIST().
    IF NOT o3stLoad() { RETURN 0. }
    LOCAL pgSinkWas IS PG_SINK.              // dpArcAt's fallback line goes through progLog: file only, never the console
    LOCAL pgFnWas IS PG_SINK_FN.
    SET PG_SINK TO TRUE. SET PG_SINK_FN TO 0.
    LOCAL res IS o3stPickRun().
    SET PG_SINK TO pgSinkWas. SET PG_SINK_FN TO pgFnWas.
    o3stLog(res).
    RETURN res.
}

FUNCTION o3stPickRun {
    LOCAL tEnd IS TIME:SECONDS + O3ST_MAX_S.
    eprInitGeo().                            // ops3q takes the datum again before the family build (and at Phase 3)
    LOCAL ei IS eprKepToEI(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT).
    IF ei[2] < 0 { SET O3ST_WHY TO "THE ORBIT NEVER REACHES THE INTERFACE". RETURN 0. }
    LOCAL sol IS LEXICON("rei", ei[0], "vei", ei[1], "tRot", (TIME:SECONDS - EPR_GEO_T0) + ei[2], "sideOk", TRUE).
    RETURN o3stChoose(sol, tEnd).
}

// THE CHOICE from an interface state sol (LEXICON(rei, vei, tRot, sideOk); tRot = s after EPR_GEO_T0, the datum eprInitGeo
// took): o3stPick's body, apart so a test can give it a fixed state. Needs the planner's definitions (o3stLoad).
FUNCTION o3stChoose {
    PARAMETER sol, tEnd.
    SET O3ST_SOL TO sol.
    LOCAL gEi IS eprToGeoInertial(sol["rei"], sol["tRot"]).
    LOCAL sites IS o3stSites().
    LOCAL best IS 0.
    LOCAL tier IS 0.
    UNTIL tier >= 2 OR NOT (best = 0) {
        FOR site IN sites[tier] {
            LOCAL tab IS dpSiteTable(site).
            IF NOT (tab = 0) {
                LOCAL rows IS LIST().
                FOR th IN tab[0] {
                    LOCAL rw IS o3stEval(site, th, sol, gEi, tEnd).
                    rows:ADD(rw).
                    O3ST_ROWS:ADD(rw).
                }
                LOCAL e IS o3stEnd(rows).
                IF e = 0 {
                    LOCAL why IS "".
                    FOR rw IN rows { SET why TO why + (CHOOSE " / " IF why <> "" ELSE "") + rw["rwy"] + ": " + rw["why"]. }
                    kmSay("SITE " + site + " OUT OF REACH (" + why + ")", "I").
                } ELSE IF best = 0 {
                    SET best TO e.
                } ELSE IF e["score"] > best["score"] + O3ST_TIE {
                    SET best TO e.
                }
            }
        }
        SET tier TO tier + 1.
    }
    IF NOT (best = 0) {
        RETURN o3stResult(best, TRUE, "").
    }
    // none flyable: the least bad judged end of the MAIN sites (an abort site that is out of reach is no better than SLF)
    LOCAL bad IS 0.
    FOR rw IN O3ST_ROWS {
        IF rw["judged"] AND rw["score"] > -7 AND O3ST_MAIN:CONTAINS(rw["site"]) {
            IF bad = 0 { SET bad TO rw. } ELSE IF rw["score"] > bad["score"] { SET bad TO rw. }
        }
    }
    IF bad = 0 { SET O3ST_WHY TO "NO MAIN END COULD BE JUDGED". RETURN 0. }
    RETURN o3stResult(bad, FALSE, bad["why"]).
}

FUNCTION o3stResult {
    PARAMETER rw, ok, why.
    LOCAL txt IS rw["rwy"] + " (" + ROUND(rw["rng"] / 1000) + " KM, REACH " + ROUND(rw["shortM"] / 1000) + "-" + ROUND(rw["longM"] / 1000)
                + ", AZ " + ROUND(rw["az"]) + ", MARGIN " + ROUND(MAX(0, rw["score"]) * 100) + " %, HAC TURN " + ROUND(rw["turn"]) + ")".
    IF NOT ok { SET txt TO "NO SITE IN REACH: " + rw["rwy"] + " NEAREST: " + why. }
    RETURN LEXICON("ok", ok, "rwy", rw["rwy"], "site", rw["site"], "aim", LATLNG(rw["aimLat"], rw["aimLng"]), "beta", rw["beta"],
                   "score", rw["score"], "turn", rw["turn"], "line", txt).
}
