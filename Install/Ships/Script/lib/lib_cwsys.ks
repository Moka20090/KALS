@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_CWSYS.KS  --  the vessel readers for the C&W checks of a program that has no pod readers of its own (ops3q; ops2q
//  reads its pods itself, o2qRcsRead). The same shape and the same rules as ops2q's: the orbiter has ONE forward-fuselage part
//  (the F pod: 14 jets, MonoPropellant 200) and ONE aft-fuselage part (the L and R pods, 12 jets each, one shared tank); a pod's
//  jets working = its jets x the share of its RCS modules enabled and not flamed out (lib_o2rcs o2rJets).
// ============================================================================
RUNONCEPATH("0:/lib/lib_o2rcs.ks").
GLOBAL CWS_POD_DT IS 5.                      // s: the parts and modules are looked up this often
GLOBAL cwsPods IS LEXICON("t", -1E9, "f", "", "a", "", "m", LIST(0, 0, 0, 0)).

FUNCTION cwsMono {                           // a part's MonoPropellant: LIST(amount, capacity)
    PARAMETER pt.
    FOR rs IN pt:RESOURCES { IF rs:NAME = "MonoPropellant" { RETURN LIST(rs:AMOUNT, rs:CAPACITY). } }
    RETURN LIST(0, 0).
}
FUNCTION cwsScan {
    IF TIME:SECONDS - cwsPods["t"] < CWS_POD_DT { RETURN. }
    SET cwsPods["t"] TO TIME:SECONDS.
    LOCAL fw IS "". LOCAL af IS "".
    FOR pt IN SHIP:PARTS {
        LOCAL nm IS pt:NAME:TOLOWER.
        IF nm:CONTAINS("forwardfuselage") { SET fw TO pt. }
        ELSE IF nm:CONTAINS("aftfuselage") { SET af TO pt. }
    }
    SET cwsPods["f"] TO fw. SET cwsPods["a"] TO af.
    LOCAL rx IS LIST().
    LIST RCS IN rx.
    LOCAL cnt IS LIST(0, 0, 0, 0).           // forward modules, forward ok, aft modules, aft ok
    FOR rc IN rx {
        LOCAL ok IS rc:ENABLED AND NOT rc:FLAMEOUT.
        LOCAL u IS rc:UID.
        IF NOT fw:ISTYPE("String") AND u = fw:UID { SET cnt[0] TO cnt[0] + 1. IF ok { SET cnt[1] TO cnt[1] + 1. } }
        ELSE IF NOT af:ISTYPE("String") AND u = af:UID { SET cnt[2] TO cnt[2] + 1. IF ok { SET cnt[3] TO cnt[3] + 1. } }
    }
    SET cwsPods["m"] TO cnt.
}
// the three RCS pods F, L, R: LIST of LEXICON(has, qty %, tot jets, jets working, ok = usable) (ops2q's o2qRcsRead shape)
FUNCTION cwRcsRead {
    cwsScan().
    LOCAL fw IS cwsPods["f"]. LOCAL af IS cwsPods["a"].
    LOCAL cnt IS cwsPods["m"].
    LOCAL fm IS LIST(0, 0). LOCAL am IS LIST(0, 0).
    IF NOT fw:ISTYPE("String") { SET fm TO cwsMono(fw). }
    IF NOT af:ISTYPE("String") { SET am TO cwsMono(af). }
    LOCAL out IS LIST().
    FROM { LOCAL p IS 0. } UNTIL p > 2 STEP { SET p TO p + 1. } DO {
        LOCAL fwd IS p = 0.
        LOCAL pt IS CHOOSE fw IF fwd ELSE af.
        LOCAL has IS NOT pt:ISTYPE("String").
        LOCAL mo IS CHOOSE fm IF fwd ELSE am.
        LOCAL nm IS CHOOSE cnt[0] IF fwd ELSE cnt[2].
        LOCAL nk IS CHOOSE cnt[1] IF fwd ELSE cnt[3].
        LOCAL ok IS has AND mo[0] > 0.
        LOCAL wk IS 0.
        IF has { SET wk TO o2rJets(O2R_JETS[p], CHOOSE nk IF ok ELSE 0, nm). }
        out:ADD(LEXICON("has", has, "qty", o2rPct(mo[0], mo[1]), "tot", O2R_JETS[p], "wk", wk, "ok", ok, "nm", nm, "nk", nk)).
    }
    RETURN o2rDllJets(out).                  // The real jets per pod from the DLL
}
