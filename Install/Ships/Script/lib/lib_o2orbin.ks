@LAZYGLOBAL OFF.
// lib_o2orbin.ks -- The kOS side of ORBIT / PTG's page build in C#. o2qOrbitIn() gathers the RAW VALUES the page shows
// (what needs the game: o2qEls, o2qAtt, o2qDapTgt, SHIP, ETA ...) into ONE lexicon for coproc/O2Orbit.cs (O2OrbitIn.FromKos reads these
// keys; a missing key makes the C# build fail and ops2q keeps its own o2qPgOrbit). Same decisions and calls as o2qPgOrbit, in the same
// order; the formatting and the row assembly are C#. Load AFTER ops2q.ks's functions and globals; call from ops2q's loop only.
// T1015: the DB the DAP flies: while it flies, its own deadband (the settle's and the burn's narrower one, the VERN one
// included: o2qDap["db"]); else the page's value. The page and the C# build show this, not the crew's typed value.
FUNCTION o2qDbShown {
    IF o2qDapOn { RETURN o2qDap["db"]. }
    RETURN o2Val["ddb"].
}
FUNCTION o2qOrbitIn {
    LOCAL el IS o2qEls().
    LOCAL dp IS o2qDapOn.
    LOCAL at IS o2qAtt().
    LOCAL tg IS o2qDapTgt().
    LOCAL ec IS LIST().
    IF tg:LENGTH = 3 { SET ec TO LIST(o2qDap["e"]:Y, o2qDap["e"]:X, o2qDap["e"]:Z). }
    LOCAL act IS "".
    LOCAL ea IS 0.
    LOCAL jets IS FALSE.
    IF dp { SET act TO O2Q_DAP_ACT[o2qDap["act"]]. SET ea TO o2qDap["ea"]. SET jets TO o2qDap["u"]:MAG > 0. }
    IF o2Msg <> "" { o2qSay(o2Msg, o2MsgCls). SET o2Msg TO "". }
    LOCAL mt IS LIST().
    LOCAL mc IS LIST().
    FOR m IN o2qMsgs { mt:ADD(m[0]). mc:ADD(m[1]). }
    RETURN LEXICON("met", MISSIONTIME, "raKm", o2qKm(el["ra"]), "rpKm", o2qKm(el["rp"]), "inc", el["inc"], "per", el["period"],
        "altKm", SHIP:ALTITUDE / 1000, "spd", SHIP:VELOCITY:ORBIT:MAG, "etaA", ETA:APOAPSIS, "etaP", ETA:PERIAPSIS, "dp", dp,
        "hold", ROUND(o2Val["hold"]), "tax", ROUND(o2Val["tax"]), "ttg", ROUND(o2Val["ttg"]), "dmode", ROUND(o2Val["dmode"]),
        "taxWords", O2Q_TAX, "ttgWords", O2Q_TTG, "tom", o2Val["tom"], "tr", o2Val["tr"], "tp", o2Val["tp"], "ty", o2Val["ty"],
        "ddb", o2qDbShown(), "drate", o2Val["drate"], "at", at, "tg", tg, "ec", ec, "rate", SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI,
        "dapAct", act, "dapEa", ea, "jets", jets, "seqOn", o2qSeq <> "", "msgTxt", mt, "msgCls", mc).
}
