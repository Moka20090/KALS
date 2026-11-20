// ============================================================================
//  LIB_PLAN.KS  --  the deorbit plan file, written and read
// ============================================================================
//  Loaded with RUNONCEPATH by deorbit_plan.ks, which writes the plan file (0:/deorbit_plan.txt), and by
//  shuttle_exec.ks, fam_build.ks and ops3q.ks, which read it. The programs share no script state, so the
//  file carries the planner's choices to the others: the runway, the aim point, the entry angle, the
//  bank, the burn time and the rotation epoch at the entry interface. Writer and reader share one file
//  so the format cannot drift apart.
//  FORMAT: "key value", one per line, no commas or quotes, split at spaces. Unknown keys with numeric values are ignored, so
//  either side can gain fields. Keys in PLAN_STR_KEYS stay strings (`runway 09` is the string "09", not
//  the number 9).
//  written_real_days: the real-world time of writing, in days since 1970-01-01 UTC (KUNIVERSE:REALWORLDTIME / 86400; a
//  small number on purpose: TONUMBER does not parse an integer above 2147483647). shuttle_exec flies the plan written
//  last; ops1q.ks's OMS-2 plan file carries the same key.

// --- THE LANDING TARGET ----------------------------------------------------------------------
//  The surveyed runway, kept here so the planner can use it without loading ops3q.ks.
//  entry_predict.ks supplies eprDestGeo (used by planRwy27). It is loaded here so this file does not
//  rely on the loading program having loaded it first; RUNONCEPATH runs a file only once.
RUNONCEPATH("0:/lib/entry_predict.ks").

// Runway 09 as surveyed: the threshold (the west end), the heading in deg and the length in m.
GLOBAL PLAN_RWY09 IS LATLNG(0.017789, -91.848195).
GLOBAL PLAN_RWY_HDG IS 89.99.
GLOBAL PLAN_RWY_LEN IS 2513.

// The runway 27 threshold (the east end), derived from the 09 threshold, heading and length so the
// survey is stated once. It needs coordinates of its own: two candidate thresholds at the same point
// would build the same FTP and score the same crossrange, so the first in the list would always win.
FUNCTION planRwy27 {
    LOCAL ll27 IS eprDestGeo(PLAN_RWY09:LAT, PLAN_RWY09:LNG, PLAN_RWY_HDG, PLAN_RWY_LEN).
    RETURN LATLNG(ll27[0], ll27[1]).
}
GLOBAL PLAN_RWY27 IS planRwy27().

GLOBAL PLAN_FILE IS "0:/deorbit_plan.txt".
GLOBAL PLAN_MAX_AGE IS 20000.   // s: a plan older than this is rejected as stale (a leftover plan
                                //   would silently retarget the entry). Generous, because the gap from
                                //   writing to the interface is the coast, not the wait.
// Keys whose values stay strings; every other value is a number.
GLOBAL PLAN_STR_KEYS IS LIST("vessel", "runway", "tag", "site").   // "tag": the OMS plans' burn (lib_oms_plan.ks);
                                                                  // "site": the ATO OMS-1 plan's launch site

// Set by planRead: whether the plan is usable, the reason in words, and the fields by key.
GLOBAL PLAN_OK IS FALSE.
GLOBAL PLAN_WHY IS "not read".
GLOBAL PLAN_D IS LEXICON().

// Write the plan file, replacing any old one; returns TRUE. Angles in deg, times in s, residKm, crossKm
// and backsetKm in km, dv in m/s; runway is the runway's name (a string).
FUNCTION planWrite {
    PARAMETER runway, aimLat, aimLng, fpa, bank, tBurn, tRot, dv, residKm, crossKm, epochUT,
              apchBrng, backsetKm.
    // apchBrng and backsetKm record the direction the aim was built for: a plan built for the wrong
    // direction still looks converged. The aim (the handover point) sits KEP_FTP_RANGE_NM back along
    // the chosen pass's ground track, so that bearing alone decides which side of the field it lands on.
    // backsetKm is gc(interface, threshold) - gc(interface, aim), gc being the great-circle distance:
    // positive (the FTP range) when the aim lies between the interface and the runway, negative when
    // it lies beyond the runway.
    // tBurn and tRot count from epochUT, the UT at which the planner read the vehicle state, not from
    // the time of writing. The file has them as t_burn, t_rot (s after epoch) and burn_ut, rot_ut (UT).
    IF EXISTS(PLAN_FILE) { DELETEPATH(PLAN_FILE). }
    LOG "version 1" TO PLAN_FILE.
    LOG "vessel " + SHIP:NAME TO PLAN_FILE.
    LOG "written " + ROUND(TIME:SECONDS, 3) TO PLAN_FILE.
    LOG "written_real_days " + ROUND(KUNIVERSE:REALWORLDTIME / 86400, 7) TO PLAN_FILE.
    LOG "epoch " + ROUND(epochUT, 3) TO PLAN_FILE.
    LOG "burn_ut " + ROUND(epochUT + tBurn, 3) TO PLAN_FILE.
    LOG "rot_ut " + ROUND(epochUT + tRot, 3) TO PLAN_FILE.
    LOG "runway " + runway TO PLAN_FILE.
    LOG "aim_lat " + ROUND(aimLat, 8) TO PLAN_FILE.
    LOG "aim_lng " + ROUND(aimLng, 8) TO PLAN_FILE.
    LOG "fpa " + ROUND(fpa, 4) TO PLAN_FILE.
    LOG "bank " + ROUND(bank, 3) TO PLAN_FILE.
    LOG "t_burn " + ROUND(tBurn, 3) TO PLAN_FILE.
    LOG "t_rot " + ROUND(tRot, 3) TO PLAN_FILE.
    LOG "dv " + ROUND(dv, 4) TO PLAN_FILE.
    LOG "residual_km " + ROUND(residKm, 4) TO PLAN_FILE.
    LOG "cross_km " + ROUND(crossKm, 4) TO PLAN_FILE.
    LOG "apch_brng " + ROUND(apchBrng, 4) TO PLAN_FILE.
    LOG "backset_km " + ROUND(backsetKm, 4) TO PLAN_FILE.
    RETURN TRUE.
}

// Read and validate the plan file. Sets PLAN_OK, PLAN_WHY and PLAN_D; returns PLAN_OK.
// A bad plan is rejected, never repaired: a wrong aim point does not announce itself, it shows up as
// guidance saturation hundreds of km out.
FUNCTION planRead {
    SET PLAN_OK TO FALSE.
    SET PLAN_D TO LEXICON().
    IF NOT EXISTS(PLAN_FILE) {
        SET PLAN_WHY TO "no plan file at " + PLAN_FILE.
        RETURN FALSE.
    }
    LOCAL content IS OPEN(PLAN_FILE):READALL.
    // FOR over the FileContent (READALL's result), not over content:ITERATOR: FOR calls :ITERATOR
    // itself, and an Iterator has no :ITERATOR suffix.
    FOR line IN content {
        LOCAL parts IS line:TRIM:SPLIT(" ").
        IF parts:LENGTH >= 2 {
            LOCAL key IS parts[0].
            LOCAL raw IS parts[1].
            IF PLAN_STR_KEYS:CONTAINS(key) {
                // Rejoin the remaining tokens: a value such as the vessel name may contain spaces; only
                // keys are single tokens.
                LOCAL joined IS raw.
                FROM { LOCAL tk IS 2. } UNTIL tk >= parts:LENGTH STEP { SET tk TO tk + 1. } DO {
                    SET joined TO joined + " " + parts[tk].
                }
                SET PLAN_D[key] TO joined.
            } ELSE {
                // TONUMBER with a sentinel default, not bare TONUMBER: a malformed line must be
                // detectable rather than throwing or silently yielding zero.
                LOCAL n IS raw:TONUMBER(-987654321).
                IF n = -987654321 {
                    SET PLAN_WHY TO "unparsable value for " + key + ": " + raw.
                    RETURN FALSE.
                }
                SET PLAN_D[key] TO n.
            }
        }
    }
    IF NOT PLAN_D:HASKEY("version") OR NOT (PLAN_D["version"] = 1) {
        SET PLAN_WHY TO "unknown plan version".
        RETURN FALSE.
    }
    FOR need IN LIST("runway", "aim_lat", "aim_lng", "fpa", "bank", "t_rot", "t_burn") {
        IF NOT PLAN_D:HASKEY(need) {
            SET PLAN_WHY TO "plan missing " + need.
            RETURN FALSE.
        }
    }
    IF NOT PLAN_D:HASKEY("vessel") OR NOT (PLAN_D["vessel"] = SHIP:NAME) {
        SET PLAN_WHY TO "plan is for " + PLAN_D["vessel"] + ", this is " + SHIP:NAME.
        RETURN FALSE.
    }
    IF PLAN_D:HASKEY("written") {
        LOCAL age IS TIME:SECONDS - PLAN_D["written"].
        // A plan written more than 1 s in the future means the save was reverted past the point it was
        // made; the vehicle is no longer on the trajectory it was planned for.
        IF age < -1 {
            SET PLAN_WHY TO "plan written " + ROUND(0 - age) + " s in the future -- reverted save?".
            RETURN FALSE.
        }
        // The limit counts from the plan's own entry: PLAN_MAX_AGE past t_rot (the seconds from the plan's epoch
        // to the interface), not past the writing. A plan written for a burn 12 h ahead (42600 s) is 42600 s old
        // when ops2q's family build reads it after the burn; the old flat 20000 s rejected it and the family
        // was built for the no-plan site. A leftover plan is still rejected: PLAN_MAX_AGE after its entry.
        LOCAL maxAge IS PLAN_MAX_AGE + MAX(0, PLAN_D["t_rot"]).
        IF age > maxAge {
            SET PLAN_WHY TO "plan is " + ROUND(age) + " s old, limit " + ROUND(maxAge).
            RETURN FALSE.
        }
    }
    SET PLAN_WHY TO "ok".
    SET PLAN_OK TO TRUE.
    RETURN TRUE.
}

// The plan's value for key, or dflt if the plan has none (for optional fields).
FUNCTION planGet {
    PARAMETER key, dflt.
    IF PLAN_D:HASKEY(key) { RETURN PLAN_D[key]. }
    RETURN dflt.
}
