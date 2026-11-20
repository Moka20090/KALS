// ============================================================================
//  LIB_KEPLER.KS  --  analytic orbital propagation and the rev search
// ============================================================================
//  Loaded with RUNONCEPATH by the deorbit planner (deorbit_plan.ks). No top-level action.
//  Uses entry_predict.ks for EPR_R, EPR_MU, EPR_OMEGA and the geodesy helpers.
//  Orbits are propagated analytically: Kepler's equation for two-body motion and, on Sol, an RK4 ephemeris with J2.
//  One batch of the rev search spans up to 41 orbits (about 117,000 s) and probes the ground track every 30 s, about
//  3,900 probes; integrating each probe from t=0 would take hundreds of millions of steps. kOS's POSITIONAT is not
//  used: it carries KSP's own patched-conic behaviour.
//  UNITS. kOS trig takes and returns degrees, but Kepler's equation M = E - e*sin(E) needs radians.
//  Angle variables ending _R are radians, those ending _D are degrees.

RUNONCEPATH("0:/lib/entry_predict.ks").

GLOBAL KEP_CROSS_OK_KM  IS 300.   // km: the rev search accepts a pass within this crossrange of the FTP
                                  // On Sol deorbit_plan sets it from kepCrossOk before any rev search;
                                  // it stays 300 until then, and on any other body.
// Per-orbit crossrange limit, km. Each row is the mean altitude (km) followed by one limit per true inclination in
// KEP_XR_INCS (deg; above 90 is retrograde). Circular orbits, Sol. A limit is 0.90 x the entry family's lateral reach at
// FAM_OPERATING_U 0.72 from a nominal deorbit, minimised over where on the orbit the plan starts. Read with kepCrossOk.
GLOBAL KEP_XR_INCS IS LIST(0, 15, 30, 45, 60, 75, 90, 105, 120).
GLOBAL KEP_XR_TAB IS LIST(
    LIST(125, 293.5, 290.5, 290.1, 292.3, 296.4, 302.0, 308.6, 316.4, 324.2),
    LIST(150, 298.0, 295.2, 295.2, 297.8, 302.0, 308.0, 315.1, 322.7, 330.9),
    LIST(175, 307.7, 304.4, 303.8, 305.8, 309.9, 315.3, 321.8, 329.4, 337.7),
    LIST(200, 317.7, 313.9, 312.7, 313.8, 316.8, 321.8, 328.3, 335.5, 343.6),
    LIST(250, 331.8, 327.4, 325.2, 325.4, 327.8, 331.9, 337.8, 344.5, 351.9),
    LIST(300, 340.6, 335.7, 333.1, 333.1, 334.7, 338.5, 343.8, 349.9, 357.3),
    LIST(350, 345.6, 340.7, 338.1, 337.3, 338.9, 342.2, 347.0, 353.2, 360.2),
    LIST(400, 348.5, 343.5, 340.6, 339.7, 340.8, 343.8, 348.5, 354.5, 361.2)).
GLOBAL KEP_INC_TOL      IS 0.5.   // deg: below this tilt the orbit is equatorial and there is no rev search
                                  // (an equatorial ground track never crosses the target latitude; every rev is as good)
GLOBAL KEP_SCAN_STEP    IS 30.    // s between ground-track probes
GLOBAL KEP_MAX_ORBITS   IS 41.    // revs per search batch; up to KEP_MAX_BATCHES batches are searched
GLOBAL KEP_MAX_BATCHES  IS 3.
GLOBAL KEP_EPH_DT       IS 30.    // s between the J2 ephemeris' RK4 samples
GLOBAL KEP_PASS_ITERS   IS 40.    // golden-section steps refining kepPassTime
GLOBAL KEP_APEX_MARGIN  IS 0.5.   // deg: a site beyond the orbit's reach is scanned this far inside its maximum latitude
GLOBAL KEP_GLIDE_DRIFT  IS 0.     // km of eastward sub-point drift during the glide; 0 = off
// ---- TAEM HANDOVER GEOMETRY ----------------------------------------------------------------
// This file builds the aim the entry flies. The entry flies correctly to whatever FTP it gets, so an error here is a miss
// the guidance cannot see.
// 3.2.1: TAEM transition is about 60 nm from the runway threshold at about 82,000 ft AGL, at 2500 ft/s: a glideslope
// of 24.99 km / 111.12 km = 0.2249. The altitude cannot be copied (same airframe, quarter-size planet: 4x the density,
// so 18.7 km instead of 24.99 km), so the glideslope is matched instead; 45 nm gives 0.2244.
GLOBAL KEP_NM_M          IS 1852.   // metres per nautical mile
GLOBAL KEP_FTP_RANGE_NM  IS 32.32.  // nm: the range before the HAC term below (with it 33.10 nm at the base angle)
                                    //   kepFtpRangeNm moves it per pass for the HAC wrap (below). The 45 nm glideslope
                                    //   match above does not set this range.
// The FTP law's HAC-geometry term: the range moves with the approach angle th = |norm180(track - landing heading)|
// (34.36 nm at th 0, down the runway; 33.10 at the base 63.6; 29.83 head-on) and with the runway's short-field
// aim shift dx (VBG14 426.72 m, VBG32 548.64 m, else 0). The polynomial terms around the base are zero (K1 = K2 = 0).
GLOBAL KEP_FTP_HAC_SHIFT_M  IS 4198.3.  // m
GLOBAL KEP_FTP_XALI_SHIFT_M IS 3783.4.  // m
GLOBAL KEP_FTP_THETA_BASE   IS 63.6.    // deg: the base approach angle th
GLOBAL KEP_FTP_K1           IS 0.       // nm per deg
GLOBAL KEP_FTP_K2           IS 0.       // nm per deg^2
GLOBAL KEP_FTP_LAT_KM    IS 12.964. // = 7 nm, the NEP distance (3.2.2)
GLOBAL KEP_FTP_BACK_KM   IS 59.85664. // = KEP_FTP_RANGE_NM * KEP_NM_M / 1000

// ---------------------------------------------------------------------------
//  Angle helpers
// ---------------------------------------------------------------------------
// Wraps an angle (deg) into (-180, 180].
FUNCTION kepNorm180 {
    PARAMETER d.
    UNTIL d <= 180 { SET d TO d - 360. }
    UNTIL d > -180 { SET d TO d + 360. }
    RETURN d.
}

// Initial great-circle bearing (deg) from point 1 to point 2; latitudes and longitudes in deg.
FUNCTION kepBearing {
    PARAMETER lat1, lng1, lat2, lng2.
    LOCAL dl IS lng2 - lng1.
    RETURN ARCTAN2(SIN(dl) * COS(lat2),
                   COS(lat1) * SIN(lat2) - SIN(lat1) * COS(lat2) * COS(dl)).
}

// Point at a bearing (deg) and distance (m) from another point; used to build the FTP. A wrapper: the formula is
// eprDestGeo in entry_predict.ks because lib_plan.ks needs it to derive the runway 27 threshold, and fam_build.ks
// loads lib_plan.ks without this file.
FUNCTION kepDestGeo {
    PARAMETER lat1, lng1, brngD, distM.
    RETURN eprDestGeo(lat1, lng1, brngD, distM).
}

// Perpendicular distance (m) from the point (pLat, pLng) to the great circle through (tLat, tLng) on bearing
// trackBrngD (deg).
FUNCTION kepCrossTrack {
    PARAMETER pLat, pLng, tLat, tLng, trackBrngD.
    LOCAL dD IS eprGcDist(tLat, tLng, pLat, pLng) / EPR_R * CONSTANT:RADTODEG.
    LOCAL bD IS kepBearing(tLat, tLng, pLat, pLng).
    RETURN ABS(ARCSIN(MAX(-1, MIN(1, SIN(dD) * SIN(bD - trackBrngD)))) * CONSTANT:DEGTORAD
               * EPR_R).
}

// ---------------------------------------------------------------------------
//  Orbital elements and analytic propagation
// ---------------------------------------------------------------------------
//  Orbital elements from a position rv (m) and velocity vv (m/s), captured once and reused for every probe. Returns a
//  LEXICON (so the fields cannot be reordered), or 0 for a degenerate or hyperbolic orbit.
FUNCTION kepElements {
    PARAMETER rv, vv.
    LOCAL rm IS rv:MAG.
    LOCAL vm IS vv:MAG.
    IF rm < 1 OR vm < 0.000001 { RETURN 0. }
    LOCAL h IS VCRS(rv, vv).
    IF h:MAG < 0.000001 { RETURN 0. }
    LOCAL energy IS 0.5 * vm * vm - EPR_MU / rm.
    IF energy >= 0 { RETURN 0. }               // hyperbolic; not a deorbit case
    LOCAL sma IS 0 - EPR_MU / (2 * energy).
    LOCAL ecc IS SQRT(MAX(0, 1 - h:MAG * h:MAG / (EPR_MU * sma))).
    // eccentric anomaly: ARCCOS returns degrees, so convert to radians for Kepler's equation
    LOCAL caD IS (1 - rm / sma) / MAX(ecc, 0.000000000001).
    LOCAL eaR IS ARCCOS(MAX(-1, MIN(1, caD))) * CONSTANT:DEGTORAD.
    IF VDOT(rv, vv) < 0 { SET eaR TO 0 - eaR. }
    RETURN LEXICON(
        "sma", sma, "ecc", ecc,
        "n", SQRT(EPR_MU / (sma ^ 3)),          // mean motion, rad/s
        "ea0R", eaR,                            // eccentric anomaly at epoch, RADIANS
        "r0", rv, "v0", vv, "rm0", rm,
        "h", h,
        "period", 2 * CONSTANT:PI * SQRT((sma ^ 3) / EPR_MU)
    ).
}

// J2 planner ephemeris (Sol): Principia flies the real Earth's J2, and plain Kepler drifts 10-19 km per orbit from it.
// Under EPR_J2_ON the vehicle's state comes from an RK4 ephemeris (point mass + J2, eprJ2Step) sampled every KEP_EPH_DT
// s from the elements' epoch and cached in el. kepEphReach extends it to cover time t.
FUNCTION kepEphReach {
    PARAMETER el, t.
    IF NOT el:HASKEY("ephR") {
        el:ADD("ephR", LIST(el["r0"])).
        el:ADD("ephV", LIST(el["v0"])).
    }
    LOCAL rs IS el["ephR"].
    LOCAL vs IS el["ephV"].
    UNTIL (rs:LENGTH - 1) * KEP_EPH_DT > t {
        LOCAL st IS eprJ2Step(rs[rs:LENGTH - 1], vs[vs:LENGTH - 1], KEP_EPH_DT).
        rs:ADD(st[0]).
        vs:ADD(st[1]).
    }
}

// Interpolates the ephemeris with a cubic Hermite on the position and velocity at both ends of the step; the velocity
// is the Hermite's derivative.
FUNCTION kepEphAt {                         // LIST(position, velocity) at t >= 0 s after the elements' epoch
    PARAMETER el, t.
    kepEphReach(el, t).
    LOCAL rs IS el["ephR"].
    LOCAL vs IS el["ephV"].
    LOCAL i IS FLOOR(t / KEP_EPH_DT).
    LOCAL u IS (t - i * KEP_EPH_DT) / KEP_EPH_DT.
    LOCAL u2 IS u * u.
    LOCAL u3 IS u2 * u.
    LOCAL pos IS rs[i] * (2 * u3 - 3 * u2 + 1) + vs[i] * (KEP_EPH_DT * (u3 - 2 * u2 + u))
                 + rs[i + 1] * (3 * u2 - 2 * u3) + vs[i + 1] * (KEP_EPH_DT * (u3 - u2)).
    LOCAL vel IS (rs[i] * (6 * u2 - 6 * u) + vs[i] * (KEP_EPH_DT * (3 * u2 - 4 * u + 1))
                  + rs[i + 1] * (6 * u - 6 * u2) + vs[i + 1] * (KEP_EPH_DT * (3 * u2 - 2 * u))) / KEP_EPH_DT.
    RETURN LIST(pos, vel).
}

// Position at time t (s) after the epoch of `el`. Solves Kepler's equation, then applies the f and g series in terms of
// the change in eccentric anomaly, which needs no inclination, node or argument of periapsis: the state vector carries
// them. For t >= 0 under EPR_J2_ON the J2 ephemeris is used instead.
FUNCTION kepAt {
    PARAMETER el, t.
    IF EPR_J2_ON AND t >= 0 { RETURN kepEphAt(el, t)[0]. }   // Sol: the J2 ephemeris
    LOCAL ecc IS el["ecc"].
    LOCAL sma IS el["sma"].
    LOCAL n   IS el["n"].
    LOCAL m0R IS el["ea0R"] - ecc * SIN(el["ea0R"] * CONSTANT:RADTODEG).
    LOCAL mR  IS m0R + n * t.
    // Newton on M = E - e sin E, all in radians. Trig calls convert on the way in.
    LOCAL eaR IS mR.
    IF ecc >= 0.8 { SET eaR TO CONSTANT:PI. }
    LOCAL i IS 0.
    UNTIL i >= 30 {
        SET i TO i + 1.
        LOCAL eaD IS eaR * CONSTANT:RADTODEG.
        LOCAL f IS eaR - ecc * SIN(eaD) - mR.
        LOCAL fp IS 1 - ecc * COS(eaD).
        IF ABS(fp) < 0.00000000000001 { BREAK. }
        LOCAL d IS f / fp.
        SET eaR TO eaR - d.
        IF ABS(d) < 0.0000000000001 { BREAK. }
    }
    LOCAL deaR IS eaR - el["ea0R"].
    LOCAL ff IS 1 - sma / el["rm0"] * (1 - COS(deaR * CONSTANT:RADTODEG)).
    LOCAL gg IS t + (SIN(deaR * CONSTANT:RADTODEG) - deaR) / n.
    RETURN el["r0"] * ff + el["v0"] * gg.
}

// Ground sub-point LIST(lat, lng) at time t (s from the epoch eprInitGeo captured). kepAt's position is inertial, so
// eprToGeoInertial applies the body's rotation (omega * t).
FUNCTION kepSubPoint {
    PARAMETER el, t.
    LOCAL g IS eprToGeoInertial(kepAt(el, t), t).
    RETURN LIST(g[0], kepNorm180(g[1])).
}

// Ground-track bearing (deg) at time t (s), from the sub-points at t and t + 5 s.
FUNCTION kepTrackBearing {
    PARAMETER el, t.
    LOCAL a IS kepSubPoint(el, t).
    LOCAL b IS kepSubPoint(el, t + 5).
    RETURN kepBearing(a[0], a[1], b[0], b[1]).
}

// Orbit tilt (deg, 0-90): the inclination, or 180 minus it if that is smaller.
FUNCTION kepTilt {
    PARAMETER el.
    LOCAL h IS el["h"].
    LOCAL incD IS ARCCOS(MAX(-1, MIN(1, VDOT(h:NORMALIZED, EPR_NAXIS)))).
    RETURN MIN(incD, 180 - incD).
}

// The per-orbit crossrange limit, km: KEP_XR_TAB interpolated bilinearly at the mean altitude altKm (km) and the true
// inclination incDeg (deg, 0-180), clamped to the table's edges (125-400 km, 0-120 deg).
FUNCTION kepCrossOk {
    PARAMETER altKm, incDeg.
    LOCAL tb IS KEP_XR_TAB.
    LOCAL ic IS KEP_XR_INCS.
    LOCAL aK IS MAX(tb[0][0], MIN(tb[tb:LENGTH - 1][0], altKm)).
    LOCAL iD IS MAX(ic[0], MIN(ic[ic:LENGTH - 1], incDeg)).
    LOCAL ri IS 0.
    UNTIL ri >= tb:LENGTH - 2 OR aK < tb[ri + 1][0] { SET ri TO ri + 1. }
    LOCAL ci IS 0.
    UNTIL ci >= ic:LENGTH - 2 OR iD < ic[ci + 1] { SET ci TO ci + 1. }
    LOCAL fA IS (aK - tb[ri][0]) / (tb[ri + 1][0] - tb[ri][0]).
    LOCAL fI IS (iD - ic[ci]) / (ic[ci + 1] - ic[ci]).
    RETURN (1 - fA) * ((1 - fI) * tb[ri][ci + 1] + fI * tb[ri][ci + 2])
         + fA * ((1 - fI) * tb[ri + 1][ci + 1] + fI * tb[ri + 1][ci + 2]).
}

// ---------------------------------------------------------------------------
//  Rev search
// ---------------------------------------------------------------------------
// Time (s) in [ta, tb] at which the sub-point latitude crosses aimLat (deg), found by 24 bisections.
FUNCTION kepAbeamCross {
    PARAMETER el, ta, tb, aimLat.
    LOCAL i IS 0.
    UNTIL i >= 24 {
        SET i TO i + 1.
        LOCAL tm IS 0.5 * (ta + tb).
        IF (kepSubPoint(el, ta)[0] - aimLat) * (kepSubPoint(el, tm)[0] - aimLat) <= 0 {
            SET tb TO tm.
        } ELSE {
            SET ta TO tm.
        }
    }
    RETURN 0.5 * (ta + tb).
}

// FTP range (nm) from the runway threshold for a pass with ground-track bearing gtBrng and runway landing heading
// rwyHdg (deg): KEP_FTP_RANGE_NM plus the HAC-geometry term above; aimDx (m) is the runway's short-field aim shift.
// kepBuildFtp (below) places the FTP that range back along gtBrng, the track the vehicle flies, not the extended
// centreline (they differ on an inclined approach). There is no lateral offset: the side swap of 3.2.2 is done by TAEM
// guidance, not built into the entry's target.
FUNCTION kepFtpRangeNm {                    // nm from the threshold
    PARAMETER gtBrng, rwyHdg, aimDx IS 0.
    LOCAL th IS ABS(kepNorm180(gtBrng - rwyHdg)).
    LOCAL d IS th - KEP_FTP_THETA_BASE.
    LOCAL hs IS KEP_FTP_HAC_SHIFT_M + aimDx.
    LOCAL xs IS KEP_FTP_XALI_SHIFT_M + aimDx.
    RETURN KEP_FTP_RANGE_NM + KEP_FTP_K1 * d + KEP_FTP_K2 * d * d + (hs * COS(th) - (hs - xs)) / KEP_NM_M.
}

FUNCTION kepBuildFtp {                      // the FTP as LIST(lat, lng); rwyHdg -999 (the default) uses the base range
    PARAMETER thLat, thLng, gtBrng, rwyHdg IS -999, aimDx IS 0.
    LOCAL nm IS KEP_FTP_RANGE_NM.
    IF rwyHdg > -999 { SET nm TO kepFtpRangeNm(gtBrng, rwyHdg, aimDx). }
    RETURN kepDestGeo(thLat, thLng, gtBrng + 180, nm * KEP_NM_M).
}

// Scans [wStart, wEnd] (s after the epoch) for crossings of latitude aimLat (deg). `thresholds` is a LIST of
// LIST(name, lat, lng) or LIST(name, lat, lng, landing heading, aim shift); each runway builds its FTP from its own
// threshold. Returns LIST(t, crossKm, name, ftpLat, ftpLng, brng) or 0.
// The first crossing within KEP_CROSS_OK_KM is returned at once, not the global best (on a polar orbit the best
// crossing can be ~25 revs away); the best seen is only the fallback when nothing qualifies.
// tEarliest (s) skips crossings too soon to fly: one closer than the coast to the interface plus the entry, plus
// DP_MIN_LEAD_S, cannot give an executable node.
FUNCTION kepScanWindow {
    PARAMETER el, wStart, wEnd, thresholds, aimLat, tEarliest.
    LOCAL best IS 0.
    LOCAL bestX IS 1000000000.
    LOCAL tPrev IS wStart.
    LOCAL spPrev IS kepSubPoint(el, tPrev).
    LOCAL t IS wStart + KEP_SCAN_STEP.
    UNTIL t > wEnd {
        LOCAL sp IS kepSubPoint(el, t).
        IF (spPrev[0] - aimLat) * (sp[0] - aimLat) <= 0 {
            LOCAL ta IS kepAbeamCross(el, tPrev, t, aimLat).
            IF ta >= tEarliest {
                LOCAL brng IS kepTrackBearing(el, ta).
                LOCAL spd IS kepSubPoint(el, ta).
                IF KEP_GLIDE_DRIFT > 0 {
                    SET spd TO kepDestGeo(spd[0], spd[1], 90, KEP_GLIDE_DRIFT * 1000).
                }
                // Best threshold for this crossing first, then whether the crossing is good enough to take: runways are
                // compared only within one pass, because crossranges of different passes are never alternatives.
                LOCAL revBest IS 0.
                LOCAL revX IS 1000000000.
                FOR th IN thresholds {
                    // a 5-element threshold (name, lat, lng, landing heading, aim shift) gets the FTP law's
                    // HAC-geometry term
                    LOCAL ftp IS 0.
                    IF th:LENGTH > 4 { SET ftp TO kepBuildFtp(th[1], th[2], brng, th[3], th[4]). }
                    ELSE { SET ftp TO kepBuildFtp(th[1], th[2], brng). }
                    // reject the far node: a crossing on the other side of the planet also matches
                    // the latitude but is not a landing opportunity
                    IF ABS(kepNorm180(spd[1] - ftp[1])) <= 90 {
                        LOCAL xt IS kepCrossTrack(ftp[0], ftp[1], spd[0], spd[1], brng).
                        IF xt < revX {
                            SET revX TO xt.
                            SET revBest TO LIST(ta, xt / 1000, th[0], ftp[0], ftp[1], brng).
                        }
                    }
                }
                IF NOT (revBest = 0) {
                    IF revX / 1000 <= KEP_CROSS_OK_KM { RETURN revBest. }
                    IF revX < bestX {
                        SET bestX TO revX.
                        SET best TO revBest.
                    }
                }
            }
        }
        SET spPrev TO sp.
        SET tPrev TO t.
        SET t TO t + KEP_SCAN_STEP.
    }
    RETURN best.
}

// Searches forward in batches of KEP_MAX_ORBITS revs (up to KEP_MAX_BATCHES) for a pass within KEP_CROSS_OK_KM.
// Returns a LEXICON (t, crossKm, runway, ftpLat, ftpLng, brng, accepted, batch), or 0; with no acceptable pass it holds
// the best one seen (accepted = FALSE). brng is the approach direction the aim encodes (the FTP is placed the FTP range
// back along it), so the burn solve must be held to the same pass. deorbit_plan.ks gates on it and records it in the
// plan file.
FUNCTION kepFindRev {
    PARAMETER el, thresholds, aimLat, tEarliest, after IS 0.   // after: search from there (the retry's next pass)
    LOCAL span IS KEP_MAX_ORBITS * el["period"].
    LOCAL best IS 0.
    LOCAL b IS 0.
    UNTIL b >= KEP_MAX_BATCHES {
        LOCAL got IS kepScanWindow(el, after + b * span + 1, after + (b + 1) * span, thresholds, aimLat, tEarliest).
        IF NOT (got = 0) {
            IF best = 0 { SET best TO got. }
            ELSE IF got[1] < best[1] { SET best TO got. }
            IF got[1] <= KEP_CROSS_OK_KM {
                RETURN LEXICON("t", got[0], "crossKm", got[1], "runway", got[2],
                               "ftpLat", got[3], "ftpLng", got[4], "brng", got[5],
                               "accepted", TRUE, "batch", b + 1).
            }
        }
        SET b TO b + 1.
    }
    IF best = 0 { RETURN 0. }
    RETURN LEXICON("t", best[0], "crossKm", best[1], "runway", best[2],
                   "ftpLat", best[3], "ftpLng", best[4], "brng", best[5],
                   "accepted", FALSE, "batch", KEP_MAX_BATCHES).
}

// Distance (m) from the sub-point at time t to the aim point (aimLat, aimLng).
FUNCTION kepPassDist {
    PARAMETER el, t, aimLat, aimLng.
    LOCAL sp IS kepSubPoint(el, t).
    RETURN eprGcDist(sp[0], sp[1], aimLat, aimLng).
}

// Time (s) in [tLo, tHi] at which the sub-point comes closest to the aim: a scan every KEP_SCAN_STEP s, then a golden
// section of KEP_PASS_ITERS steps on the best +- one step. The planner seeds the burn from this time, not from the
// latitude crossing: on a low-inclination orbit the crossing is not the pass.
FUNCTION kepPassTime {
    PARAMETER el, tLo, tHi, aimLat, aimLng.
    LOCAL bestT IS tLo.
    LOCAL bestD IS kepPassDist(el, tLo, aimLat, aimLng).
    LOCAL t IS tLo + KEP_SCAN_STEP.
    UNTIL t > tHi {
        LOCAL dt IS kepPassDist(el, t, aimLat, aimLng).
        IF dt < bestD {
            SET bestT TO t.
            SET bestD TO dt.
        }
        SET t TO t + KEP_SCAN_STEP.
    }
    LOCAL a IS MAX(tLo, bestT - KEP_SCAN_STEP).
    LOCAL b IS MIN(tHi, bestT + KEP_SCAN_STEP).
    LOCAL gr IS 0.5 * (SQRT(5) - 1).
    LOCAL c IS b - gr * (b - a).
    LOCAL dd IS a + gr * (b - a).
    LOCAL fc IS kepPassDist(el, c, aimLat, aimLng).
    LOCAL fd IS kepPassDist(el, dd, aimLat, aimLng).
    LOCAL i IS 0.
    UNTIL i >= KEP_PASS_ITERS {
        IF fc < fd {
            SET b TO dd.
            SET dd TO c.
            SET fd TO fc.
            SET c TO b - gr * (b - a).
            SET fc TO kepPassDist(el, c, aimLat, aimLng).
        } ELSE {
            SET a TO c.
            SET c TO dd.
            SET fc TO fd.
            SET dd TO a + gr * (b - a).
            SET fd TO kepPassDist(el, dd, aimLat, aimLng).
        }
        SET i TO i + 1.
    }
    RETURN 0.5 * (a + b).
}
