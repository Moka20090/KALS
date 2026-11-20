// lib_o2p8.ks -- ops2q's PEG 8: the PRINCIPIA-PLAN GUIDANCE. Pure (vectors and lexicons in, numbers
// out; the shot itself is KalsCoproc's ADDONS:KALS:PEG8SOLVE, coproc/PrShoot.cs). Needs lib_o2orb.ks, lib_o2peg.ks (o2pNew, the burn's VGO) and lib_o2fpln.ks
// (the tree: o2flN, o2flStateAt, o2flBegin) loaded first.
//   WHICH BURNS: a mirrored Principia burn (src "P") or a BRN PLN burn whose last solve was SOLVE's n-body one (nb): o2p8Node. A burn from the automatic
//     Kepler re-solve keeps the mode dim.
//   THE AIM: the next planned burn's ignition (the first live burn under this one: its begin; a Principia burn under a Principia burn: Principia's OWN planned
//     position there), else half an osculating period after this burn (the plan's own conic, flown n-body by the shot). o2p8Aim.
//   THE MATCH: the shot finds the velocity at the cut whose n-body coast meets the aim position; VGO = that velocity - the velocity now, re-solved every
//     O2P8_DT_PRE s before the ignition (at the burn's centre) and every O2P8_DT_BURN s in the burn (from the state now), and carried between shots by the SENSED
//     dV (lib_o2peg's o2pSense), as PEG 7's.
//   FALLBACK: a shot that fails (no convergence, the solution far from the plan, no aim) before the ignition: the planned dV flown as PEG 7 (o2p8Fall); in
//     the burn: the sensed count flies on with the last VGO.
GLOBAL O2P8_DT_PRE IS 2.                     // s between shots before the ignition
GLOBAL O2P8_DT_BURN IS 0.5.                  // s between shots in the burn
GLOBAL O2P8_FAILS IS 3.                      // shots in a row that failed in the burn before ops2q says so

// the node nid may be flown by PEG 8: a live burn that is Principia's or n-body solved
FUNCTION o2p8Node {
    PARAMETER nid.
    IF nid <= 0 OR NOT o2flLive(nid) { RETURN FALSE. }
    RETURN o2flN[nid]["src"] = "P" OR o2flN[nid]["nb"].
}
// the reason PEG 8 is not available for node nid ("" = it is)
FUNCTION o2p8Why {
    PARAMETER nid.
    IF nid < 0 OR NOT o2flLive(nid) { RETURN "PEG 8: NEEDS FPLN BRN". }
    IF NOT o2p8Node(nid) { RETURN "PEG 8: PRINCIPIA OR N-BODY BURNS ONLY (SOLVE)". }
    RETURN "".
}
// the aim of node nid: LEXICON(pt, pr, pv (the plan's state AFTER the burn, UT pt, inertial), at (UT of the aim, 0 = half a period after pt), ar (a position, or
// "" when the aim is the plan's coast), next (the next burn's name, "" = half an orbit))
FUNCTION o2p8Aim {
    PARAMETER nid.
    LOCAL nd IS o2flN[nid].
    LOCAL st IS o2flStateAt(nd["el"], nd["ep"], nd["ep"]).
    LOCAL ai IS LEXICON("pt", nd["ep"], "pr", st[0], "pv", st[1], "at", 0, "ar", "", "next", "").
    FOR k IN nd["kids"] {
        IF o2flLive(k) AND ai["next"] = "" {
            LOCAL kd IS o2flN[k].
            SET ai["at"] TO o2flBegin(k).
            SET ai["next"] TO o2flName(k).
            IF kd["src"] = "P" AND nd["src"] = "P" { SET ai["ar"] TO o2flStateAt(kd["el"], kd["ep"], kd["ep"])[0]. }
        }
    }
    RETURN ai.
}
FUNCTION o2p8L3 { PARAMETER x. RETURN LIST(x:X, x:Y, x:Z). }
// the burn: dv = the PLANNED dV (LVLH LIST) and fr = the LVLH frame it is turned into the inertial dvg at the centre with (lib_o2orb o2Lvlh); aim = o2p8Aim; gv = o2p4Grav
FUNCTION o2p8New {
    PARAMETER dv, fr, aim, gv.
    LOCAL pg IS o2pNew(dv, fr).
    SET pg["p8"] TO TRUE. SET pg["aim"] TO aim. SET pg["gv"] TO gv.
    SET pg["tshot"] TO -1E9. SET pg["nres"] TO 0. SET pg["nosol"] TO FALSE. SET pg["why"] TO "". SET pg["nfail"] TO 0. SET pg["nfailrow"] TO 0.
    SET pg["ntry"] TO 0. SET pg["nfailtot"] TO 0. SET pg["wfirst"] TO "".   // The shots tried / failed in all, the first failure's why and UT (the burn's log)
    SET pg["miss"] TO -1. SET pg["miss0"] TO -1. SET pg["missP"] TO -1. SET pg["mcut"] TO -1. SET pg["aimt"] TO 0. SET pg["ms"] TO 0. SET pg["fell"] TO FALSE.
    RETURN pg.
}
// one shot at the time now from the state (rq, vq) (inertial, body-relative) with the impulse at UT tc (>= now) and the planned dV dvg (inertial): the VGO of pg
// replaced by the shot's (before the ignition also the burn's total); LEXICON(ok, why, ...) as ADDONS:KALS:PEG8SOLVE gave it
FUNCTION o2p8Shot {
    PARAMETER pg, now, rq, vq, tc, dvg.
    LOCAL ai IS pg["aim"].
    LOCAL gv IS pg["gv"].
    LOCAL rq3 IS LEXICON("mu", gv["mu"], "j2", gv["j2"], "rj2", gv["rj2"], "pole", o2p8L3(gv["ax"]), "t0", now, "r", o2p8L3(rq), "v", o2p8L3(vq), "tc", tc,
        "dvg", o2p8L3(dvg), "at", ai["at"], "pt", ai["pt"], "pr", o2p8L3(ai["pr"]), "pv", o2p8L3(ai["pv"])).
    IF ai["ar"] <> "" { SET rq3["ar"] TO o2p8L3(ai["ar"]). }
    LOCAL rs IS ADDONS:KALS:PEG8SOLVE(rq3).
    SET pg["ntry"] TO pg["ntry"] + 1.
    SET pg["tshot"] TO now + (CHOOSE O2P8_DT_PRE IF pg["tprev"] < 0 ELSE O2P8_DT_BURN).
    IF NOT rs["ok"] {
        SET pg["nosol"] TO TRUE. SET pg["why"] TO rs["why"]. SET pg["nfail"] TO pg["nfail"] + 1.
        SET pg["nfailtot"] TO pg["nfailtot"] + 1.
        IF pg["wfirst"] = "" { SET pg["wfirst"] TO rs["why"] + " AT UT " + ROUND(now, 1). }
        IF rs:HASKEY("misscut") { SET pg["mcut"] TO rs["misscut"]. }
        RETURN rs.
    }
    LOCAL g IS V(rs["dv"][0], rs["dv"][1], rs["dv"][2]).
    SET pg["vgo"] TO g.
    IF pg["tprev"] < 0 { SET pg["vgo0"] TO g. SET pg["tot"] TO g:MAG. }
    SET pg["nosol"] TO FALSE. SET pg["why"] TO "". SET pg["nfail"] TO 0.
    SET pg["nres"] TO pg["nres"] + 1.
    IF pg["tprev"] < 0 { SET pg["missP"] TO rs["miss0"]. }      // before the ignition: how far the planned dV flown as an impulse (PEG 7) would miss
    SET pg["miss"] TO rs["resid"]. SET pg["miss0"] TO rs["miss0"]. SET pg["mcut"] TO rs["misscut"]. SET pg["aimt"] TO rs["aimt"]. SET pg["ms"] TO rs["ms"].
    RETURN rs.
}
// the shot is due (and the steering is not holding)
FUNCTION o2p8Due {
    PARAMETER pg, now.
    RETURN pg["p8"] AND NOT pg["hold"] AND now >= pg["tshot"].
}
// the fallback before the ignition: the planned dV as PEG 7's (pg keeps its keys; "p8" off), the VGO the planned dV in the frame fr
FUNCTION o2p8Fall {
    PARAMETER pg, fr.
    SET pg["p8"] TO FALSE. SET pg["fell"] TO TRUE.
    o2pRefresh(pg, fr).
}
