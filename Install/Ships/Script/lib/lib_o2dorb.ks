// ============================================================================
//  lib_o2dorb.ks  --  ops2q's DEORB TGT page: the planner wiring, the page's data and the globe's maths
// ============================================================================
//  deorbit_plan.ks's planning logic stays UNCHANGED behind the page (its selection box is gone; RUN DEORBIT_PLAN opens
//  ops2q on this page; DP_SELECT FALSE plans headless). The page loads its DEFINITIONS (DP_NO_RUN, the one-shot skip flag the
//  file documents for port_selftest; a RUN that handed over to ops2q has them already: DP_LOADED) and then does what the
//  file's executive does, line for line (o2dbSolve), ending in dpRun:
//  the chain, the runway box, the gates and planWrite are the planner's own, so the page's plan file is the file RUN
//  DEORBIT_PLAN writes for the same inputs (compared byte for byte on the kOS VM).
//  DP_RUNWAY / DP_COARSE_ON are reset by the file's `GLOBAL .. IS` lines at load, so they are set AFTER the load, as the
//  planner's selection box sets them.
//  The page's data (o2dbAfter) and the globe's maths (o2dbGeom, o2dbGfx): the plan's post-burn conic Earth-relative (the ground
//  track: the planner's own dpStateAtKep + eprToGeoInertial at the burn's time), seen orthographically over a fixed background
//  (o2_bg/globe_fl.png, globe_wc.png by tools/gen_o2_globe.py); the path starts where the Earth shows it, runs past the entry
//  interface and periapsis and ends where the Earth hides it.
//  Prefix o2db / O2DB_.

GLOBAL O2DB_ON IS FALSE.                 // deorbit_plan.ks's definitions are loaded
GLOBAL O2DB_WHY IS "".                   // why o2dbLoad / o2dbSolve could not
GLOBAL O2DB_PASSES IS 4.                 // DP_REV_MAX_TRIES, shown "of 4" before the planner is loaded
GLOBAL O2DB_PASS_NOW IS 0.               // the pass the SOLVE now running plans (the sink's "SOLVING PASS n")

FUNCTION o2dbLoad {                      // the planner's definitions (lazy: ~90 KB of script, loaded on the first SOLVE)
    IF O2DB_ON { RETURN TRUE. }
    IF NOT (DEFINED DP_LOADED) {         // a RUN DEORBIT_PLAN that handed over to ops2q has loaded the file already
        IF NOT EXISTS("0:/deorbit_plan.ks") { SET O2DB_WHY TO "DEORBIT_PLAN.KS MISSING". RETURN FALSE. }
        GLOBAL DP_NO_RUN IS TRUE.        // consumed by the file (DP_SKIP_NOW): the executive does not run
        RUNONCEPATH("0:/deorbit_plan.ks").
    }
    SET O2DB_ON TO TRUE.
    SET O2DB_PASSES TO DP_REV_MAX_TRIES.
    RETURN TRUE.
}

// The planner's executive (deorbit_plan.ks, the IF DP_RUN block) as one call. site = "SLF" / "EAFB" / "VBG", rwy = "auto" or an
// end of the site ("SLF15"), coarse = the planning mode. Returns LEXICON("ok", a plan file was written, "why", the last
// planner line when not, "pass", the pass the plan is for, "cont" (what plans the NEXT PASS: the planner's own state it resumes
// from plus the orbit and epoch it works on, as its window keeps them; 0 = no later pass; give it back as cont, same site / runway /
// mode: the planner's DP_START hook), "rv", "vv", "t0": the orbit it planned from).
// the planner runs in prog_display's SINK mode: no window; its burn-solve progress goes to sink, a delegate (kind, n):
// ("solve", 0) a solve starts, ("step", n) step n of 4 is done (0 = none: the planner's log file only).
FUNCTION o2dbSolve {
    PARAMETER site, rwy, coarse, cont IS 0, sink IS 0, startAbs IS 0.   // T1020: startAbs = the pass BEFORE the one wanted, as the preview holds it (LEXICON("revUT", "passUT" (UT; revUT -1 = none), "n")): the planner starts at the pass after it
    LOCAL out IS LEXICON("ok", FALSE, "why", "", "pass", 0, "cont", 0).
    IF NOT o2dbLoad() { SET out["why"] TO O2DB_WHY. RETURN out. }
    SET DP_SITE TO site.
    SET DP_RUNWAY TO rwy.
    SET DP_COARSE_ON TO coarse.
    LOCAL goOn IS cont:ISTYPE("Lexicon").   // NEXT PASS goes on from the earlier call's orbit, epoch, FPA and geo datum, as the planner's window does
    LOCAL dpOrbAlt IS (APOAPSIS + PERIAPSIS) / 2.
    IF goOn { SET dpOrbAlt TO cont["alt"]. }
    ELSE {
        eprMassTrack().                  // the model at the mass of NOW (the file calls it once at load)
        SET DP_FPA TO dpFpaForOrbit(dpOrbAlt).
    }
    IF SHIP:ALTITUDE < EPR_ATM { SET out["why"] TO "NOT IN ORBIT". RETURN out. }
    IF NOT goOn { eprInitGeo(). }
    LOCAL planT0 IS TIME:SECONDS.
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    IF goOn { SET planT0 TO cont["t0"]. SET rv TO cont["rv"]. SET vv TO cont["vv"]. }
    LOCAL el IS kepElements(rv, vv).
    IF el = 0 { SET out["why"] TO "HYPERBOLIC OR DEGENERATE ORBIT". RETURN out. }
    LOCAL tilt IS kepTilt(el).
    IF SHIP:BODY:NAME = "Earth" {
        LOCAL incTrue IS (CHOOSE tilt IF VDOT(vv, eprEastNorth(rv)[0]) >= 0 ELSE (180 - tilt)).
        SET KEP_CROSS_OK_KM TO kepCrossOk(dpOrbAlt / 1000, incTrue).
    }
    SET DP_SEED_LEAD_S TO DP_MIN_LEAD_S + DP_PLAN_ALLOW_S + dpCoastTime(dpOrbAlt) + DP_EI_TO_PASS_S.
    LOCAL st IS dpSiteTable(DP_SITE).
    IF st = 0 { SET out["why"] TO "NO RUNWAYS FOR " + DP_SITE:TOUPPER. RETURN out. }
    // the planner's DP_START hook: declared here and only here (a plain RUN has none): the state dpRun starts from (the pass
    // after an earlier call's), and what dpRun leaves in it is the state NEXT PASS resumes from. Unset again: no later RUN sees it.
    LOCAL startN IS 0.
    IF NOT (DEFINED DP_START) { GLOBAL DP_START IS 0. }
    IF goOn { SET DP_START TO cont["st"]. SET startN TO cont["st"]["n"]. }
    ELSE {
        SET DP_START TO LEXICON("tRev", -1, "tPass", -1, "n", 0).
        IF startAbs:ISTYPE("Lexicon") {      // the earlier pass's crossing / pass time on THIS orbit's clock; one already gone = the nearest pass (the search's own fallback)
            LOCAL sRev IS CHOOSE startAbs["revUT"] - planT0 IF startAbs["revUT"] >= 0 ELSE -1.
            LOCAL sPass IS startAbs["passUT"] - planT0.
            IF sPass > 0 AND (sRev > 0 OR startAbs["revUT"] < 0) {
                SET DP_START TO LEXICON("tRev", sRev, "tPass", sPass, "n", startAbs["n"]).
                SET startN TO startAbs["n"].
            }
        }
    }
    SET O2DB_PASS_NOW TO startN + 1.
    SET PG_SINK TO TRUE. SET PG_SINK_FN TO sink.
    dpRun(el, tilt, st, rv, vv, planT0, dpOrbAlt).
    SET PG_SINK TO FALSE. SET PG_SINK_FN TO 0.
    IF DP_START:ISTYPE("Lexicon") { SET out["cont"] TO LEXICON("st", DP_START, "rv", rv, "vv", vv, "t0", planT0, "alt", dpOrbAlt). }
    UNSET DP_START.
    SET out["ok"] TO EXISTS(PLAN_FILE).
    SET out["rv"] TO rv. SET out["vv"] TO vv. SET out["t0"] TO planT0.   // the orbit the plan is for (o2dbAfter's globe)
    SET out["pass"] TO startN + 1.       // the pass dpRun tried first (a window can go on to later ones: the log line below)
    LOCAL ll IS pgLog:COPY.              // prog_display's log lines LIST(line, colour) (kept in the sink mode and while a window is up)
    FOR lnx IN ll {
        IF lnx[0]:CONTAINS("PLAN WRITTEN: PASS ") { SET out["pass"] TO lnx[0]:SPLIT("PASS ")[1]:SPLIT(",")[0]:TONUMBER(1). }
    }
    IF NOT out["ok"] AND ll:LENGTH > 0 {  // the window with the reason is gone: the page's MSG says it: the planner's STOPPED line (else its last), without the log's clock
        LOCAL wi IS ll:LENGTH - 1.
        LOCAL k IS ll:LENGTH - 1.
        UNTIL k < 0 { IF ll[k][0]:CONTAINS("STOPPED:") { SET wi TO k. BREAK. } SET k TO k - 1. }
        SET out["why"] TO ll[wi][0]:SUBSTRING(8, ll[wi][0]:LENGTH - 8):TRIM.
    }
    RETURN out.
}

// THE PASS PREVIEW (the old selection box's table): for each end of the site the planner's own dpPassPreview on the
// orbit of NOW, as dpSelectBox did it (the same prologue as o2dbSolve's: the model at this mass, the geodesy datum, the orbit's
// crossrange limit, the earliest flyable pass). T1020: PASS n of the page: pass = the pass wanted (1 = the nearest); each end's
// passes up to it are searched the way the planner's NEXT PASS does (dpPassPreview with the earlier pass as its resume state);
// prev = this site's earlier result on the same orbit (its passes are kept, the search goes on from the last).
// Returns LEXICON("ok", .., "why", "", "site", .., "t0" (the epoch of the orbit), "sma" (to tell the orbit changed), "rows",
// LIST(LEXICON("rwy" (the end, "SLF15"), "list" (LIST of the passes found, nearest first: LEXICON("revUT" (the crossing, -1 =
// none), "passUT", "turn" (the HAC turn, deg), "xr" (the crossrange, km))), "end" (no pass beyond the list), and the first
// pass's "ok", "tPass" (s after t0), "turn", "xr"))), "auto" (AUTO's end for pass 1, the lower predicted turn, "" = none),
// "warn" (the turn the planner flags, DP_TURN_WARN)).
FUNCTION o2dbPreview {
    PARAMETER site, pass IS 1, prev IS 0.
    LOCAL out IS LEXICON("ok", FALSE, "why", "", "site", site, "t0", TIME:SECONDS, "sma", SHIP:ORBIT:SEMIMAJORAXIS, "rows", LIST(), "auto", "", "warn", 315).
    IF NOT o2dbLoad() { SET out["why"] TO O2DB_WHY. RETURN out. }
    SET out["warn"] TO DP_TURN_WARN.
    IF SHIP:ALTITUDE < EPR_ATM { SET out["why"] TO "NOT IN ORBIT". RETURN out. }
    LOCAL dpOrbAlt IS (APOAPSIS + PERIAPSIS) / 2.
    eprMassTrack().
    SET DP_FPA TO dpFpaForOrbit(dpOrbAlt).
    eprInitGeo().
    LOCAL planT0 IS TIME:SECONDS.
    LOCAL rv IS -SHIP:BODY:POSITION.
    LOCAL vv IS SHIP:VELOCITY:ORBIT.
    LOCAL el IS kepElements(rv, vv).
    IF el = 0 { SET out["why"] TO "HYPERBOLIC OR DEGENERATE ORBIT". RETURN out. }
    LOCAL tilt IS kepTilt(el).
    IF SHIP:BODY:NAME = "Earth" {
        LOCAL incTrue IS (CHOOSE tilt IF VDOT(vv, eprEastNorth(rv)[0]) >= 0 ELSE (180 - tilt)).
        SET KEP_CROSS_OK_KM TO kepCrossOk(dpOrbAlt / 1000, incTrue).
    }
    SET DP_SEED_LEAD_S TO DP_MIN_LEAD_S + DP_PLAN_ALLOW_S + dpCoastTime(dpOrbAlt) + DP_EI_TO_PASS_S.
    SET out["t0"] TO planT0.
    LOCAL tab IS dpSiteTable(site).
    IF tab = 0 { SET out["why"] TO "NO RUNWAYS FOR " + site:TOUPPER. RETURN out. }
    LOCAL autoTurn IS 1000.
    LOCAL ri IS 0.
    FOR th IN tab[0] {
        LOCAL lst IS LIST().
        LOCAL ended IS FALSE.
        IF prev:ISTYPE("Lexicon") {
            LOCAL prows IS prev["rows"].
            IF prows:LENGTH > ri {
                LOCAL prow IS prows[ri].
                IF prow["rwy"] = th[0] {
                    FOR pe IN prow["list"] { lst:ADD(pe). }
                    SET ended TO prow["end"].
                }
            }
        }
        UNTIL lst:LENGTH >= pass OR ended {
            LOCAL pst IS 0.                  // the last pass found, on THIS orbit's clock: the planner's resume state
            IF lst:LENGTH > 0 {
                LOCAL lp IS lst[lst:LENGTH - 1].
                SET pst TO LEXICON("tRev", (CHOOSE lp["revUT"] - planT0 IF lp["revUT"] >= 0 ELSE -1), "tPass", lp["passUT"] - planT0).
            }
            LOCAL pv IS dpPassPreview(el, tilt, th, tab[1], rv, vv, pst).
            IF pv = 0 { SET ended TO TRUE. }
            ELSE { lst:ADD(LEXICON("revUT", (CHOOSE planT0 + pv["tRev"] IF pv["tRev"] >= 0 ELSE -1), "passUT", planT0 + pv["tPass"], "turn", pv["turn"], "xr", pv["crossKm"])). }
        }
        LOCAL row IS LEXICON("rwy", th[0], "ok", FALSE, "tPass", 0, "turn", 0, "xr", 0, "list", lst, "end", ended).
        IF lst:LENGTH > 0 {
            SET row["ok"] TO TRUE. SET row["tPass"] TO lst[0]["passUT"] - planT0. SET row["turn"] TO lst[0]["turn"]. SET row["xr"] TO lst[0]["xr"].
            IF lst[0]["turn"] < autoTurn { SET autoTurn TO lst[0]["turn"]. SET out["auto"] TO th[0]. }
        }
        out["rows"]:ADD(row).
        SET ri TO ri + 1.
    }
    SET out["ok"] TO TRUE.
    RETURN out.
}

// ---- the page's selection
GLOBAL O2DB_SITES IS LIST("SLF", "EAFB", "VBG").                  // the surveyed sites (the ELS are not offered)
GLOBAL O2DB_SITE_W IS LIST("KSC SLF", "EAFB", "VBG").             // the SITE word
GLOBAL O2DB_SITE_L IS LIST("KSC", "EAFB", "VBG").                 // the globe's site label
GLOBAL O2DB_ENDS IS LEXICON("SLF", LIST("SLF15", "SLF33"), "EAFB", LIST("EAFB06", "EAFB24"), "VBG", LIST("VBG14", "VBG32")).
GLOBAL O2DB_SITE_LL IS LEXICON("SLF", LIST(28.6695, -80.7754), "EAFB", LIST(34.8959, -117.9022), "VBG", LIST(34.7369, -120.5842)).
// the two backgrounds' centres (tools/gen_o2_globe.py VIEWS): Florida (the entry arrives from the west of KSC), the west coast
GLOBAL O2DB_VIEW IS LEXICON("SLF", LIST(24, -125, "globe_fl"), "EAFB", LIST(26, -163, "globe_wc"), "VBG", LIST(26, -163, "globe_wc")).
GLOBAL O2DB_CX IS 390 + 165.             // the globe's centre on the page (px): the canvas's .globe box
GLOBAL O2DB_CY IS 52 + 165.
GLOBAL O2DB_R IS 158.                    // the rim's radius
GLOBAL O2DB_NS IS 360.                   // the path's samples a post-burn period
GLOBAL O2DB_DRAW_MAX IS 200.             // dots at most (the kOS draw: one sprite each)

// the selection's end name: ri 0 = AUTO, 1 / 2 = the site's ends
FUNCTION o2dbRwy {
    PARAMETER si, ri.
    IF ri <= 0 { RETURN "auto". }
    RETURN O2DB_ENDS[O2DB_SITES[si]][MIN(1, ri - 1)].
}

// The orthographic projection of the surface point (lat, lng) for the view vw = LIST(lat0, lng0, ..): LIST(dx, dy (px from the
// globe's centre, y down), z): z > 0 = the Earth shows it (z <= 0 = behind the limb).
FUNCTION o2dbProj {
    PARAMETER lat, lng, vw.
    LOCAL cp IS COS(lat).
    LOCAL dl IS lng - vw[1].
    LOCAL x IS cp * SIN(dl).
    LOCAL y IS COS(vw[0]) * SIN(lat) - SIN(vw[0]) * cp * COS(dl).
    LOCAL z IS SIN(vw[0]) * SIN(lat) + COS(vw[0]) * cp * COS(dl).
    RETURN LIST(O2DB_R * x, 0 - O2DB_R * y, z).
}

FUNCTION o2dbGeoAt {                     // the ground point under the post-burn conic elp, tau s after the burn at tb (s from the epoch)
    PARAMETER elp, tb, tau.
    RETURN eprToGeoInertial(dpStateAtKep(elp, tau)[0], tb + tau).
}

FUNCTION o2dbEdge {                      // the limb between tau ta and tz (the point at ta shows when visA): LIST(dx, dy, tau) on the showing side
    PARAMETER elp, tb, vw, ta, tz, visA.
    LOCAL lo IS ta.
    LOCAL hi IS tz.
    LOCAL i IS 0.
    UNTIL i >= 7 {
        SET i TO i + 1.
        LOCAL mid IS (lo + hi) / 2.
        LOCAL g IS o2dbGeoAt(elp, tb, mid).
        LOCAL pj IS o2dbProj(g[0], g[1], vw).
        IF (pj[2] > 0) = visA { SET lo TO mid. } ELSE { SET hi TO mid. }
    }
    LOCAL tv IS CHOOSE lo IF visA ELSE hi.
    LOCAL g2 IS o2dbGeoAt(elp, tb, tv).
    LOCAL p2 IS o2dbProj(g2[0], g2[1], vw).
    RETURN LIST(p2[0], p2[1], tv).
}

// The globe of the plan d (o2dbSolve's out res: the orbit): LEXICON("ok", .., "pts", LIST(LIST(dx, dy, seg)) (seg 0 = before the
// interface, 1 = after), "ei", LIST(dx, dy) or 0, "pe", LIST(dx, dy, alt km) or 0, "range", EI .. aim (km), "tei", "tp" (s after the burn)).
// deorbit_plan.ks's own functions, called only: the parking orbit's state at the burn (dpStateAt), the burn as the chain flies it
// (v less dv along v), its conic (kepElements), the interface (dpInterfaceKep for the picture, dpInterface = the J2 coast for RANGE).
FUNCTION o2dbGeom {
    PARAMETER res, d, site.
    LOCAL vw IS O2DB_VIEW[site].
    LOCAL out IS LEXICON("ok", FALSE, "pts", LIST(), "ei", 0, "pe", 0, "range", 0, "tei", -1, "tp", 0).
    LOCAL el IS kepElements(res["rv"], res["vv"]).
    IF el = 0 { RETURN out. }
    LOCAL tb IS d["t_burn"].
    LOCAL bs IS dpStateAt(el, tb).
    LOCAL va IS bs[1] - bs[1]:NORMALIZED * d["dv"].
    LOCAL elp IS kepElements(bs[0], va).
    IF elp = 0 { RETURN out. }
    LOCAL ek IS dpInterfaceKep(bs[0], va).
    LOCAL tei IS -1.
    IF NOT (ek = 0) { SET tei TO ek[2]. }
    // periapsis: the first time after the burn the mean anomaly is a whole turn
    LOCAL m0 IS elp["ea0R"] - elp["ecc"] * SIN(elp["ea0R"] * CONSTANT:RADTODEG).
    LOCAL tw IS 2 * CONSTANT:PI.
    LOCAL tp IS (tw * CEILING(m0 / tw) - m0) / elp["n"].
    IF tp < 0.001 { SET tp TO tp + elp["period"]. }
    SET out["tei"] TO tei. SET out["tp"] TO tp.
    // the range the plan flies: the interface (the J2 coast) to the aim point
    LOCAL ej IS dpInterface(bs[0], va).
    IF NOT (ej = 0) {
        LOCAL gj IS eprToGeoInertial(ej[0], tb + ej[2]).
        SET out["range"] TO eprGcDist(gj[0], gj[1], d["aim_lat"], d["aim_lng"]) / 1000.
    }
    // the ground track from the burn: the run the Earth shows, to where it hides it (past the interface and periapsis)
    LOCAL tEnd IS tp + elp["period"] * 0.35.
    LOCAL ds IS elp["period"] / O2DB_NS.
    LOCAL pts IS out["pts"].
    LOCAL inRun IS FALSE.
    LOCAL ended IS FALSE.
    LOCAL tau IS 0.
    LOCAL tprev IS -1.
    UNTIL tau > tEnd OR ended {
        LOCAL g IS o2dbGeoAt(elp, tb, tau).
        LOCAL pj IS o2dbProj(g[0], g[1], vw).
        IF pj[2] > 0 {
            IF NOT inRun {
                SET inRun TO TRUE.
                IF tprev >= 0 {                  // it came over the limb between tprev and tau
                    LOCAL e0 IS o2dbEdge(elp, tb, vw, tprev, tau, FALSE).
                    pts:ADD(LIST(e0[0], e0[1], CHOOSE 0 IF e0[2] < tei OR tei < 0 ELSE 1)).
                }
            }
            pts:ADD(LIST(pj[0], pj[1], CHOOSE 0 IF tau < tei OR tei < 0 ELSE 1)).
        } ELSE IF inRun {
            LOCAL e1 IS o2dbEdge(elp, tb, vw, tprev, tau, TRUE).
            pts:ADD(LIST(e1[0], e1[1], CHOOSE 0 IF e1[2] < tei OR tei < 0 ELSE 1)).
            SET ended TO TRUE.
        }
        SET tprev TO tau.
        SET tau TO tau + ds.
    }
    IF tei >= 0 {
        LOCAL ge IS o2dbGeoAt(elp, tb, tei).
        LOCAL pe0 IS o2dbProj(ge[0], ge[1], vw).
        IF pe0[2] > 0 { SET out["ei"] TO LIST(pe0[0], pe0[1]). }
    }
    LOCAL gp IS o2dbGeoAt(elp, tb, tp).
    LOCAL pp IS o2dbProj(gp[0], gp[1], vw).
    IF pp[2] > 0 { SET out["pe"] TO LIST(pp[0], pp[1], (elp["sma"] * (1 - elp["ecc"]) - EPR_R) / 1000). }
    SET out["ok"] TO pts:LENGTH > 1.
    RETURN out.
}

// After a solve (res = o2dbSolve's out, site = "SLF" / ..): the page's data. "d" = the plan file's lines, "turn" = the HAC turn
// 360 - theta (theta: the interface bearing's offset to the runway's heading, as dpPlanChain's), "xr" = the crossrange limit,
// "tol" = the accepted miss, "warn" = the turn from which the planner flags it, "g" = the globe.
FUNCTION o2dbAfter {
    PARAMETER res, site, rwySel, coarse.
    LOCAL o IS LEXICON("ok", FALSE, "key", site + "|" + rwySel + "|" + coarse, "site", site, "d", LEXICON(), "g", LEXICON(),
        "turn", 0, "xr", 0, "tol", 0, "warn", 315, "pass", res["pass"], "why", res["why"], "next", res["cont"]).
    IF NOT res["ok"] { RETURN o. }
    SET o["xr"] TO KEP_CROSS_OK_KM. SET o["tol"] TO DP_TOL_KM. SET o["warn"] TO DP_TURN_WARN.   // the planner's own limits
    LOCAL keep IS PLAN_FILE.
    SET PLAN_FILE TO "0:/deorbit_plan.txt".
    LOCAL got IS planRead().
    LOCAL d IS LEXICON().
    IF got { SET d TO PLAN_D:COPY. }
    SET PLAN_FILE TO keep.
    IF NOT got { SET o["why"] TO "PLAN FILE NOT READ". RETURN o. }
    SET o["d"] TO d.
    SET o["ok"] TO TRUE.
    LOCAL st IS dpSiteTable(site).
    IF NOT (st = 0) {
        LOCAL th IS dpThreshold(st[0], d["runway"]).
        SET o["turn"] TO 360 - ABS(kepNorm180(d["apch_brng"] - th[3])).
    }
    SET o["g"] TO o2dbGeom(res, d, site).
    RETURN o.
}

// ---- the sprites. o2dbItems = the globe's drawing as data (the page's kOS draw and KalsCoproc's O2GLB take the same list): the
// background, the path's dots (<= O2DB_DRAW_MAX), EI's X + label, periapsis's ring + label, the site's dot + label. An item is
// LIST("s", sprite name, x, y) or LIST("t", text, x, y, colour, width), x / y in page px. g = o2dbGeom's lexicon or an empty one
// (not solved: the background and the site only).
FUNCTION o2dbItems {
    PARAMETER siteIx, g, dots IS TRUE.
    LOCAL site IS O2DB_SITES[siteIx].
    LOCAL cx IS O2DB_CX.
    LOCAL cy IS O2DB_CY.
    LOCAL it IS LIST().
    it:ADD(LIST("s", O2DB_VIEW[site][2], cx, cy)).
    IF g:HASKEY("pts") {
        LOCAL pts IS g["pts"].
        IF NOT dots { SET pts TO LIST(). }                 // KalsCoproc's O2GLB draws the path as an image
        LOCAL stride IS MAX(1, CEILING(pts:LENGTH / O2DB_DRAW_MAX)).
        LOCAL i IS 0.
        FOR p IN pts {
            IF MOD(i, stride) = 0 { it:ADD(LIST("s", CHOOSE "dot_v" IF p[2] = 0 ELSE "dot_w", cx + p[0], cy + p[1])). }
            SET i TO i + 1.
        }
        IF NOT (g["ei"] = 0) {
            it:ADD(LIST("s", "gx", cx + g["ei"][0], cy + g["ei"][1])).
            it:ADD(LIST("t", "EI", cx + g["ei"][0], cy + g["ei"][1] - 14, "#a6f8a6", 30)).
        }
        IF NOT (g["pe"] = 0) {
            it:ADD(LIST("s", "gring", cx + g["pe"][0], cy + g["pe"][1])).
            it:ADD(LIST("t", "P " + ROUND(g["pe"][2]), cx + g["pe"][0], cy + g["pe"][1] - 14, "#a6f8a6", 60)).
        }
    }
    LOCAL ll IS O2DB_SITE_LL[site].
    LOCAL ps IS o2dbProj(ll[0], ll[1], O2DB_VIEW[site]).
    IF ps[2] > 0 {
        it:ADD(LIST("s", "gsite", cx + ps[0], cy + ps[1])).
        it:ADD(LIST("t", O2DB_SITE_L[siteIx], cx + ps[0] - 20, cy + ps[1] - 10, "#c4ffc4", 44)).
    }
    RETURN it.
}

// kOS draws o2dbItems from slot k0 on (lib_o2disp's sprites); returns the next free slot
FUNCTION o2dbGfx {
    PARAMETER k0, siteIx, g.
    LOCAL k IS k0.
    FOR it IN o2dbItems(siteIx, g) {
        IF it[0] = "s" { o2SprPut(k, it[1], it[2], it[3]). } ELSE { o2SprTxt(k, it[1], it[2], it[3], it[4], it[5]). }
        SET k TO k + 1.
    }
    RETURN k.
}
