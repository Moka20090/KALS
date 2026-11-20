@LAZYGLOBAL OFF.
// lib_o2mnvr.ks -- The kOS side of MNVR EXEC's page build in C#. o2qMnvrIn() gathers the RAW VALUES the page shows (what needs the
// game and the guidance: o2qLoaded, o2qVgo, o2qEls, o2qAfter, the LVLH frames ...) into ONE lexicon for coproc/O2Mnvr.cs
// (O2MnvrIn.FromKos reads these keys; a missing key makes the C# build fail and ops2q keeps its own o2qPgMnvr). The decisions
// and the values are ops2q.ks o2qPgMnvr's own, in the same order of calls; the formatting and the row assembly are not here: they are C#.
// Needs ops2q.ks's functions and globals (o2qLoaded, o2qSeq, o2qRes, o2qLoad ... lib_o2ui's o2Val): load AFTER them, call from ops2q's loop only.
// tests/o2mnvr_offline runs this against the VM stubs of the offline proof: the lexicon must equal what the test derives from the same state.
FUNCTION o2qMnvrIn {
    LOCAL ld IS o2qLoaded().
    LOCAL ro IS o2qSeq <> "".                // the burn is frozen while its sequence runs
    LOCAL post IS NOT ld AND o2qSeq = "" AND o2qRes:HASKEY("peg").
    LOCAL sh IS ld OR post.
    LOCAL p4 IS ld AND o2qPeg4().
    LOCAL p8 IS ld AND o2qPeg8().
    LOCAL tot IS o2qDvTot().
    LOCAL d IS o2qDv().
    LOCAL guid IS ROUND(o2Val["guid"]).
    // GUID: the dim words and why (o2qPgMnvr's own conditions)
    LOCAL gdim IS LIST().
    LOCAL gwhy IS LIST(O2Q_P4_ONLY, "", "").
    IF NOT o2qPeg4() AND NOT o2qP4Ok() { gdim:ADD(0). }
    LOCAL w8 IS o2qP8Why().
    IF w8 <> "" { gdim:ADD(2). SET gwhy[2] TO "-". }   // dim, no text on ENT
    // BURN: the name (or the last burn's tree), the plan files
    LOCAL burnTxt IS "".
    LOCAL srcNames IS LIST().
    IF ld {
        SET burnTxt TO (CHOOSE o2flName(o2qLoad["node"]) IF o2qLoad["node"] >= 0 AND o2flLive(o2qLoad["node"]) ELSE o2qLoad["tree"]) + (CHOOSE " (EDITED)" IF o2qEdited() ELSE "").
        IF o2qSrc:LENGTH > 1 AND NOT ro { SET srcNames TO o2qSrcNames(). }
    } ELSE IF post { SET burnTxt TO o2qRes["tree"]. }
    ELSE IF o2qSrc:LENGTH > 0 AND NOT ro {
        SET o2Val["src"] TO -1.              // No entry is the selected one, so the list's cursor can pick ANY entry
        SET srcNames TO o2qSrcNames().
    }
    LOCAL typ IS "".
    IF ld { SET typ TO o2qLoad["type"]. } ELSE IF post { SET typ TO o2qRes["type"]. }
    // row 4 (GUID = PEG 8): the shot (o2qP8Row's own choice of the record)
    LOCAL p8Ok IS FALSE.
    LOCAL p8Aimt IS 0.
    LOCAL p8Miss IS 0.
    IF guid = 2 {
        LOCAL pr IS o2qP8.
        IF o2qSeq <> "" { SET pr TO o2qB["peg"]. }
        ELSE IF NOT o2qLoaded() AND o2qRes:HASKEY("peg") { SET pr TO o2qRes["peg"]. }
        SET p8Ok TO pr:HASKEY("p8") AND pr["nres"] > 0.
        IF p8Ok { SET p8Aimt TO pr["aimt"]. SET p8Miss TO pr["miss"]. }
    }
    // ATT ERR
    LOCAL attErr IS -1E99.                   // -1E99 = no value (the page shows dashes)
    IF o2qB:HASKEY("steer") AND ro { SET attErr TO VANG(SHIP:FACING:FOREVECTOR, o2qAimV). }
    ELSE IF ld AND tot > 0.01 { SET attErr TO VANG(o2qLine(o2qOms()), o2qVgo()). }
    // row 11: PEG 4 / PEG 8
    LOCAL p4NoSol IS NOT ro AND o2qP4:HASKEY("nosol") AND o2qP4["nosol"].
    LOCAL aiNext IS "".
    LOCAL p8NoSol IS FALSE.
    LOCAL p8Why IS "".
    LOCAL p8NRes IS 0.
    LOCAL p8MissP IS 0.
    IF p8 AND NOT p4 {
        SET aiNext TO o2p8Aim(o2qLoad["node"])["next"].
        SET p8NoSol TO o2qP8:HASKEY("nosol") AND o2qP8["nosol"].
        IF p8NoSol { SET p8Why TO o2qP8["why"]. }
        ELSE IF o2qP8:HASKEY("nres") AND o2qP8["nres"] > 0 { SET p8NRes TO o2qP8["nres"]. SET p8MissP TO o2qP8["missP"]. }
    }
    // rows 12-15: the VGO block
    LOCAL gt IS 0.
    LOCAL tg IS 0.
    LOCAL burnt IS FALSE.
    LOCAL gdl IS o2qGdLost().
    LOCAL gb IS LIST(0, 0, 0).
    LOCAL raT IS 0.
    LOCAL rpT IS 0.
    LOCAL raC IS 0.
    LOCAL rpC IS 0.
    IF sh {
        LOCAL g IS CHOOSE o2qRes["peg"]["vgo"] IF post ELSE o2qVgo().
        LOCAL gfr IS CHOOSE o2Lvlh(o2qRv(), SHIP:VELOCITY:ORBIT) IF (o2qSeq = "BURN" OR post) ELSE o2qFrameAt(o2qCentre()).
        SET gb TO o2ToLvlh(g, gfr).
        SET gt TO CHOOSE o2pAlong(o2qB["peg"]) IF o2qSeq = "BURN" ELSE g:MAG.
        SET tg TO o2qTb(tot).
        SET burnt TO o2qSeq = "BURN" OR post.
        IF o2qSeq = "BURN" {
            LOCAL ti IS o2qThrust().
            SET tg TO o2pTgo(gt, ti[0] / SHIP:MASS, ti[1] * CONSTANT:G0).
        }
        IF post { SET tg TO 0. }
        LOCAL ea IS CHOOSE o2qRes["ea"] IF post ELSE (CHOOSE o2qB["ea"] IF ro ELSE o2qAfter(o2qCentre(), d)).
        LOCAL ec IS o2qEls().
        SET raT TO o2qKm(ea["ra"]). SET rpT TO o2qKm(ea["rp"]). SET raC TO o2qKm(ec["ra"]). SET rpC TO o2qKm(ec["rp"]).
    }
    // row 16: the RCS trim after the cut
    LOCAL rct IS o2qRes:HASKEY("peg") AND o2qSeq = "".
    LOCAL rb IS LIST(0, 0, 0).
    IF rct { SET rb TO o2qInBody(o2qRes["peg"]["vgo"]). }
    // the MSG rows (o2qMsgRow's own side effect: the pending message goes into the list)
    IF o2Msg <> "" { o2qSay(o2Msg, o2MsgCls). SET o2Msg TO "". }
    LOCAL mt IS LIST().
    LOCAL mc IS LIST().
    FOR m IN o2qMsgs { mt:ADD(m[0]). mc:ADD(m[1]). }
    RETURN LEXICON("ld", ld, "ro", ro, "post", post, "sh", sh, "p4", p4, "p8", p8, "met", MISSIONTIME, "now", TIME:SECONDS,
        "tigMet", o2Val["tig"], "tig", CHOOSE o2qUtOf(o2Val["tig"]) IF sh ELSE 0, "dv", d, "tot", tot,
        "omsSel", o2Val["oms"], "guidSel", o2Val["guid"], "omsOn", NOT ro AND (o2qOut[0] = "" OR o2qOut[1] = ""),
        "omsDim", o2qOmsDim(), "gdim", gdim, "gwhy", gwhy, "burnTxt", burnTxt, "srcNames", srcNames, "massT", SHIP:MASS, "typ", typ,
        "p8Ok", p8Ok, "p8Aimt", p8Aimt, "p8Miss", p8Miss, "tvr", o2Val["tvr"], "dapOn", o2qDapOn, "attErr", attErr,
        "c1", o2Val["c1"], "c2", o2Val["c2"], "ht", o2Val["ht"], "tht", o2Val["tht"], "p4NoSol", p4NoSol,
        "aiNext", aiNext, "p8NoSol", p8NoSol, "p8Why", p8Why, "p8NRes", p8NRes, "p8MissP", p8MissP,
        "gt", gt, "tg", tg, "burnt", burnt, "gdl", gdl, "gb", gb, "raT", raT, "rpT", rpT, "raC", raC, "rpC", rpC,
        "rct", rct, "rb", rb, "armed", o2qArmed, "msgTxt", mt, "msgCls", mc).
}
