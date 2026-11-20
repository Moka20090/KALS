// ============================================================================
//  LIB_FAM.KS  --  the entry reference family, written and read
// ============================================================================
//  The entry reference family, kept in FAM_FILE (0:/family.txt): one reference profile per bank.
//  famWrite writes it, famRead reads and validates it, famInstall loads it into EPR_FAM.
//  Loaded with RUNONCEPATH by fam_build (which writes it) and by ops3q (which reads and flies it);
//  the generator of the ENTRY TRAJ background panels also reads it, offline. Both halves of the
//  format live here, so the writer and the readers cannot drift apart.
//  The build is slow (about two minutes), so the family is built once on the coast and reused.
//  FORMAT: a "key value" header, then one block per member. Lines are split on spaces; unknown
//  keys are ignored, so the writer and the readers can gain fields independently.

// The EPR_* globals used below come from entry_predict.ks (RUNONCEPATH loads it only once).
RUNONCEPATH("0:/lib/entry_predict.ks").

GLOBAL FAM_FILE IS "0:/family.txt".
// The file format version; famRead refuses any other.
GLOBAL FAM_VERSION IS 1.

// Header keys whose values stay strings (the rest of the line). Any other value is read as a number,
// so a value like "09" would become 9. Only non-numeric keys belong here: a numeric key kept as a
// string compares unreliably against a number, and a guard on it could never fail.
GLOBAL FAM_STR_KEYS IS LIST("vessel").

GLOBAL FAM_D IS LEXICON().        // header key -> value
GLOBAL FAM_M IS LIST().           // members, each LIST(bank, vs, ds, ss, rg, bk)
// FAM_OK is TRUE once famRead has accepted the file; otherwise FAM_WHY says why.
GLOBAL FAM_OK IS FALSE.
GLOBAL FAM_WHY IS "".

// ---------------------------------------------------------------------------- write
// Write EPR_FAM and its header to FAM_FILE; returns FALSE if there is no family to write.
// planBurnUT (UT), planAimLat and planAimLng (deg) identify the plan the family is built for.
FUNCTION famWrite {
    PARAMETER planBurnUT, planAimLat, planAimLng.
    IF NOT EPR_FAM_READY OR EPR_FAM:LENGTH = 0 {
        RETURN FALSE.
    }
    IF EXISTS(FAM_FILE) { DELETEPATH(FAM_FILE). }
    // Provenance: famRead refuses a file with another version, vessel, aero_ver or geo_ver.
    LOG "version " + FAM_VERSION TO FAM_FILE.
    LOG "vessel " + SHIP:NAME TO FAM_FILE.
    LOG "written " + ROUND(TIME:SECONDS, 3) TO FAM_FILE.
    LOG "aero_ver " + EPR_AERO_VER TO FAM_FILE.
    // The trace is decimated at sample time: EPR_TRACE_EVERY counts steps, so the sample spacing
    // follows EPR_IDT. Both are stored; the reader must not infer the spacing.
    LOG "idt " + EPR_IDT TO FAM_FILE.
    LOG "trace_every " + EPR_TRACE_EVERY TO FAM_FILE.
    LOG "members " + EPR_FAM:LENGTH TO FAM_FILE.
    // tcoast (s) gets 6 decimals: from a state already inside the atmosphere it is ~0.0006 s.
    LOG "tcoast " + ROUND(EPR_FAM_TCOAST, 6) TO FAM_FILE.
    // geo_t0 and tcoast are two epochs and both matter: eprToGeo measures the rotation from the
    // datum capture (geo_t0). r0 and v0 below are inertial, meaningless without geo_t0.
    LOG "geo_t0 " + ROUND(EPR_GEO_T0, 3) TO FAM_FILE.
    LOG "tbuild " + ROUND(EPR_FAM_TBUILD, 3) TO FAM_FILE.
    // aoa_high_speed is the AoA ramp start and also a panel boundary, so guidance and the display
    // read one value.
    LOG "aoa_high_speed " + EPR_AOA_HIGH_SPEED TO FAM_FILE.
    LOG "aoa_low_speed " + EPR_AOA_LOW_SPEED TO FAM_FILE.
    LOG "taem_vel " + EPR_TAEM_VEL TO FAM_FILE.
    LOG "nz_limit " + EPR_NZ_LIMIT TO FAM_FILE.
    // geo_ver, like aero_ver, is provenance: the ranges in the file are ground arcs accumulated with
    // eprToGeo and EPR_ROT_SCALE, so they are only valid under the same geodesy convention.
    LOG "geo_ver " + EPR_GEO_VER TO FAM_FILE.
    // 6 decimals: a component can be near zero, where coarser rounding is a large relative error.
    LOG "r0 " + ROUND(EPR_FAM_R0:X, 6) + " " + ROUND(EPR_FAM_R0:Y, 6)
              + " " + ROUND(EPR_FAM_R0:Z, 6) TO FAM_FILE.
    LOG "v0 " + ROUND(EPR_FAM_V0:X, 6) + " " + ROUND(EPR_FAM_V0:Y, 6)
              + " " + ROUND(EPR_FAM_V0:Z, 6) TO FAM_FILE.
    // The plan this family is built for (compared in famMatchesPlan).
    LOG "plan_burn_ut " + ROUND(planBurnUT, 3) TO FAM_FILE.
    LOG "plan_aim " + ROUND(planAimLat, 8) + " " + ROUND(planAimLng, 8) TO FAM_FILE.
    LOG "partial " + (CHOOSE 1 IF EPR_FAM_PARTIAL ELSE 0) TO FAM_FILE.

    LOCAL mi IS 0.
    UNTIL mi >= EPR_FAM:LENGTH {
        LOCAL mem IS EPR_FAM[mi].
        LOCAL vs IS mem[1].
        // member header: "M index bank samples"; then one line per sample
        LOG "M " + mi + " " + ROUND(mem[0], 2) + " " + vs:LENGTH TO FAM_FILE.
        LOCAL k IS 0.
        UNTIL k >= vs:LENGTH {
            // vrel, drag, sink, range_to_go, bank_flown: the member's columns, in stored order.
            // range_to_go is the builder's own range-to-go; it is not recomputed from the samples.
            LOG ROUND(vs[k], 2) + " " + ROUND(mem[2][k], 5) + " " + ROUND(mem[3][k], 3)
                + " " + ROUND(mem[4][k], 1) + " " + ROUND(mem[5][k], 2) TO FAM_FILE.
            SET k TO k + 1.
        }
        SET mi TO mi + 1.
    }
    RETURN TRUE.
}

// ---------------------------------------------------------------------------- read
// Read FAM_FILE into FAM_D (header) and FAM_M (members), then validate it. Returns TRUE and sets
// FAM_OK if the file is accepted; otherwise FAM_WHY says why. The reasons are about the file, not
// the trajectory; the caller decides what to do about a rejection.
FUNCTION famRead {
    SET FAM_OK TO FALSE.
    SET FAM_WHY TO "".
    SET FAM_D TO LEXICON().
    SET FAM_M TO LIST().
    IF NOT EXISTS(FAM_FILE) {
        SET FAM_WHY TO "no family file".
        RETURN FALSE.
    }
    LOCAL lines IS OPEN(FAM_FILE):READALL:ITERATOR.
    LOCAL curBank IS 0.
    LOCAL curV IS LIST(). LOCAL curD IS LIST(). LOCAL curS IS LIST().
    LOCAL curR IS LIST(). LOCAL curB IS LIST().
    LOCAL inMember IS FALSE.

    UNTIL NOT lines:NEXT {
        LOCAL raw IS lines:VALUE:TRIM.
        IF raw:LENGTH > 0 {
            LOCAL parts IS raw:SPLIT(" ").
            IF parts[0] = "M" {
                // flush the previous member before starting the next
                IF inMember {
                    FAM_M:ADD(LIST(curBank, curV, curD, curS, curR, curB)).
                }
                SET curBank TO parts[2]:TONUMBER(0).
                SET curV TO LIST(). SET curD TO LIST(). SET curS TO LIST().
                SET curR TO LIST(). SET curB TO LIST().
                SET inMember TO TRUE.
            } ELSE IF inMember AND parts:LENGTH >= 5 {
                curV:ADD(parts[0]:TONUMBER(0)).
                curD:ADD(parts[1]:TONUMBER(0)).
                curS:ADD(parts[2]:TONUMBER(0)).
                curR:ADD(parts[3]:TONUMBER(0)).
                curB:ADD(parts[4]:TONUMBER(0)).
            } ELSE IF parts:LENGTH >= 2 {
                // header. Multi-value keys keep their whole tail as a list of numbers; single
                // values become numbers unless the key is declared a string.
                LOCAL key IS parts[0].
                IF FAM_STR_KEYS:CONTAINS(key) {
                    LOCAL sv IS parts[1].
                    LOCAL j IS 2.
                    UNTIL j >= parts:LENGTH { SET sv TO sv + " " + parts[j]. SET j TO j + 1. }
                    SET FAM_D[key] TO sv.
                } ELSE IF parts:LENGTH = 2 {
                    SET FAM_D[key] TO parts[1]:TONUMBER(0).
                } ELSE {
                    LOCAL vals IS LIST().
                    LOCAL j IS 1.
                    UNTIL j >= parts:LENGTH { vals:ADD(parts[j]:TONUMBER(0)). SET j TO j + 1. }
                    SET FAM_D[key] TO vals.
                }
            }
        }
    }
    IF inMember {
        FAM_M:ADD(LIST(curBank, curV, curD, curS, curR, curB)).
    }

    // ---- validation ----------------------------------------------------------------
    IF NOT FAM_D:HASKEY("version") OR ABS(FAM_D["version"] - FAM_VERSION) > 0.001 {
        SET FAM_WHY TO "unknown version".
        RETURN FALSE.
    }
    IF NOT FAM_D:HASKEY("vessel") OR FAM_D["vessel"] <> SHIP:NAME {
        SET FAM_WHY TO "built for another vessel".
        RETURN FALSE.
    }
    // A file solved against another aero model is wrong in a way nothing downstream can detect.
    // Compared as a number with a tolerance, not with `<>`: exact equality on a float that has been
    // through text is unreliable.
    IF NOT FAM_D:HASKEY("aero_ver") OR ABS(FAM_D["aero_ver"] - EPR_AERO_VER) > 0.001 {
        SET FAM_WHY TO "built against aero " + FAM_D["aero_ver"] + " running " + EPR_AERO_VER.
        RETURN FALSE.
    }
    // geo_ver: ranges accumulated under another geodesy convention are not comparable. A missing
    // key is a refusal, not a pass.
    IF NOT FAM_D:HASKEY("geo_ver") {
        SET FAM_WHY TO "no geo_ver in header -- an old family file: rebuild it".
        RETURN FALSE.
    }
    IF ABS(FAM_D["geo_ver"] - EPR_GEO_VER) > 0.001 {
        SET FAM_WHY TO "built at geo_ver " + FAM_D["geo_ver"]
                       + ", running " + EPR_GEO_VER.
        RETURN FALSE.
    }
    LOCAL need IS LIST("tcoast", "geo_t0", "tbuild", "r0", "v0",
                       "plan_burn_ut", "plan_aim", "members").
    FOR k IN need {
        IF NOT FAM_D:HASKEY(k) {
            SET FAM_WHY TO "missing key " + k.
            RETURN FALSE.
        }
    }
    IF FAM_M:LENGTH < 2 {
        SET FAM_WHY TO "only " + FAM_M:LENGTH + " member(s)".
        RETURN FALSE.
    }
    IF FAM_M:LENGTH <> FAM_D["members"] {
        SET FAM_WHY TO "header says " + FAM_D["members"] + " members, found " + FAM_M:LENGTH.
        RETURN FALSE.
    }
    // members must be in ascending bank order, so the remaining range decreases across them:
    // eprFamInvert relies on it
    LOCAL i IS 1.
    UNTIL i >= FAM_M:LENGTH {
        IF FAM_M[i][0] < FAM_M[i-1][0] {
            SET FAM_WHY TO "members not in bank order".
            RETURN FALSE.
        }
        SET i TO i + 1.
    }
    SET FAM_OK TO TRUE.
    RETURN TRUE.
}

// TRUE if the family was built for this plan: burn time within 1 s, aim point within aimTolKm.
// The interface state is not compared: the one a real burn achieves never equals the planned one.
FUNCTION famMatchesPlan {
    PARAMETER planBurnUT, planAimLat, planAimLng, aimTolKm IS 1.0.
    IF NOT FAM_OK { RETURN FALSE. }
    IF ABS(FAM_D["plan_burn_ut"] - planBurnUT) > 1.0 { RETURN FALSE. }
    LOCAL a IS FAM_D["plan_aim"].
    IF eprGcDist(a[0], a[1], planAimLat, planAimLng) > aimTolKm * 1000 { RETURN FALSE. }
    RETURN TRUE.
}

// With no deorbit plan: TRUE when the read family was built on the orbit the vessel is on now -- the same specific
// energy and the same angular momentum as its start state (r0, v0: the interface, on the coast's Kepler orbit), within
// FAM_ORBIT_TOL (a fraction; 0.001 = about 1 m/s of burn). Magnitudes only: kOS's raw axes may turn between the build and
// now. A deorbit burn after the build moves both far past it.
GLOBAL FAM_ORBIT_TOL IS 0.001.
FUNCTION famMatchesOrbit {
    IF NOT FAM_OK { RETURN FALSE. }
    LOCAL fr IS FAM_D["r0"]. LOCAL fv IS FAM_D["v0"].
    LOCAL ra IS V(fr[0], fr[1], fr[2]). LOCAL va IS V(fv[0], fv[1], fv[2]).
    LOCAL rb IS -SHIP:BODY:POSITION. LOCAL vb IS SHIP:VELOCITY:ORBIT.
    LOCAL ea IS va:SQRMAGNITUDE / 2 - SHIP:BODY:MU / ra:MAG.
    LOCAL eb IS vb:SQRMAGNITUDE / 2 - SHIP:BODY:MU / rb:MAG.
    LOCAL ha IS VCRS(ra, va):MAG. LOCAL hb IS VCRS(rb, vb):MAG.
    RETURN ABS(eb - ea) <= FAM_ORBIT_TOL * ABS(ea) AND ABS(hb - ha) <= FAM_ORBIT_TOL * ha.
}

// Load a read family into EPR_FAM, so guidance can fly it without rebuilding.
FUNCTION famInstall {
    IF NOT FAM_OK { RETURN FALSE. }
    SET EPR_FAM TO LIST().
    FOR m IN FAM_M { EPR_FAM:ADD(m). }
    SET EPR_FAM_TCOAST TO FAM_D["tcoast"].
    SET EPR_GEO_T0 TO FAM_D["geo_t0"].
    SET EPR_FAM_TBUILD TO FAM_D["tbuild"].
    // Not named r and v: R(pitch,yaw,roll) and V(x,y,z) are kOS constructors, so a local of either
    // name does not parse.
    LOCAL fr IS FAM_D["r0"]. LOCAL fv IS FAM_D["v0"].
    SET EPR_FAM_R0 TO V(fr[0], fr[1], fr[2]).
    SET EPR_FAM_V0 TO V(fv[0], fv[1], fv[2]).
    SET EPR_FAM_PARTIAL TO (FAM_D["partial"] = 1).
    SET EPR_FAM_READY TO TRUE.
    SET EPR_FAM_OK TO TRUE.
    SET EPR_FAM_WHY TO CHOOSE "" IF NOT EPR_FAM_PARTIAL ELSE "partial, from file".
    RETURN TRUE.
}
