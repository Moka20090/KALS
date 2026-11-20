@LAZYGLOBAL OFF.
// lib_o2bn.ks -- The kOS side of ops2q's burn tick in C# (coproc/O2Burn.cs, O2BurnKos.cs, ADDONS:KALS:O2BURN*).
// o2bnTick(now) is ops2q.ks o2qBurnTick from `LOCAL fv IS V(0, 0, 0).` to its end, with the PEG 7 count, the end / throttle / freeze DECISIONS
// handed to the DLL and everything that touches the game, the DAP or the log kept in kOS, in the original's order and with its own texts.
// The engines are read here (fv / fs / av, the OMS RM, the gimbal mode), the C# returns the end, the throttle, the steering line and the
// events; the logs, o2qAimTv, o2qFfo, o2qBurnRow, the end flow are ops2q's own functions. PEG 4 / PEG 8: kOS re-solves VGO between the DLL's
// Sense and Decide (o2p4Cycle / o2p8Shot, unchanged), the DLL takes it back with O2BURNSETVGO.
// Off in the release: ops2q.ks arms it at the ignition only when O2BN_ENABLE (below) is TRUE; FALSE = ops2q's own kOS tick flies. Needs ops2q.ks's functions and globals (o2qB, o2qThr,
// o2qLogLine, o2qAimTv, o2qFfo, o2qBurnRm, o2qBurnRow, o2qGdLost, o2qGdEdge, o2qGmMode ...) and lib_o2peg / lib_o2line: load AFTER them.
// tests/o2burn_offline flies o2qBurnTick (verbatim from ops2q.ks) and this on the same closed-loop burns in the offline kOS VM, with the
// real C# behind ADDONS:KALS, and asserts every tick's effects equal.
IF NOT (DEFINED O2BN_ENABLE) { GLOBAL O2BN_ENABLE IS FALSE. }                 // TRUE = ops2q arms the DLL's burn tick at the ignition (the one-place switch; FALSE = ops2q's own tick, as before)
GLOBAL o2bnOn IS FALSE.                      // the DLL flies this burn
GLOBAL O2BN_FAIL IS "".                      // why the C# path was dropped (the log line's text), "" = not dropped

FUNCTION o2bnHave {                          // the DLL has the burn tick
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("O2BURNSTEP").
}
FUNCTION o2bnB { PARAMETER f. RETURN CHOOSE 1 IF f ELSE 0. }
FUNCTION o2bnBit { PARAMETER n, k. RETURN MOD(FLOOR(n / 2 ^ k), 2) = 1. }

// the burn's C# object at the ignition (after o2qAimPre's last refresh: pg["vgo"] / pg["tot"] are the ignition's): TRUE = armed
FUNCTION o2bnArm {
    PARAMETER pg, tb, t0.
    IF NOT o2bnHave() { SET O2BN_FAIL TO "no O2BURN suffixes in the DLL". RETURN FALSE. }
    LOCAL vg IS pg["vgo"].
    LOCAL ra IS ADDONS:KALS:O2BURNARM(LIST(vg:X, vg:Y, vg:Z, pg["tot"], tb, t0,
        O2P_CUT, O2P_TAPER_S, O2P_TAPER_DT_K, O2P_DTM_DECAY, O2P_HOLD_DV, O2P_HOLD_TGO, O2P_GUARD_K, O2P_GUARD_S, O2P_AXIS_MIN,
        O2Q_AIM_FREEZE_V, o2bnB(O2Q_FRZ_MEAS), O2Q_FRZ_MEAS_V, O2Q_FRZ_MEAS_MAX, o2bnB(O2Q_FFO), O2Q_LOG_TICKS)).
    IF ra:ISTYPE("Boolean") { IF ra { SET O2BN_FAIL TO "". RETURN TRUE. } }
    SET O2BN_FAIL TO "" + ra.
    RETURN FALSE.
}

// the DLL's count and hold back into the burn's kOS pg (the log rows, the end log, o2qSeqEnd and the kOS path read pg): FALSE = could not
FUNCTION o2bnToPg {
    PARAMETER pg.
    LOCAL s IS ADDONS:KALS:O2BURNSTATE().
    IF s:ISTYPE("String") { RETURN FALSE. }
    SET pg["vgo"] TO V(s[0], s[1], s[2]).
    SET pg["sens"] TO V(s[3], s[4], s[5]).
    SET pg["dtm"] TO s[7].
    SET pg["hold"] TO s[8] > 0.5.
    SET pg["t0"] TO s[11].
    SET pg["tprev"] TO s[14].
    IF s[15] > 0.5 { SET pg["tguard"] TO s[9]. SET pg["aav"] TO s[10]. }
    IF pg["hold"] { SET pg["hdir"] TO V(s[16], s[17], s[18]). }
    RETURN TRUE.
}

// the C# path dropped (an error answer): the kOS pg gets what the DLL has, o2qB flags the kOS path again; the caller flies this tick on kOS
FUNCTION o2bnDrop {
    PARAMETER why, pg.
    o2bnToPg(pg).
    SET O2BN_FAIL TO why.
    SET o2bnOn TO FALSE.
    o2qLogLine("BURN TICK IN C# DROPPED: " + why + " (the kOS tick flies the rest of the burn)").
}

// the burn's tick on the DLL. TRUE = done (the tick's decisions applied); FALSE = the C# path failed before it changed anything: fly
// ops2q's own tick from `LOCAL fv` on.
FUNCTION o2bnTick {
    PARAMETER now.
    LOCAL pg IS o2qB["peg"].
    LOCAL fv IS V(0, 0, 0).                  // the thrust along the engines' axes, kN (each gave it over the last tick)
    LOCAL fs IS 0.                           // their scalar thrust
    LOCAL av IS V(0, 0, 0).                  // the available thrust along them
    FOR en IN o2qB["eng"] {
        LOCAL ax IS en:FACING:FOREVECTOR.
        SET fv TO fv + ax * en:THRUST.
        SET fs TO fs + en:THRUST.
    }
    LOCAL ul IS o2lUids(o2qB["eng"]).
    LOCAL ol IS o2lGet(ul, "meas").          // the thrust they gave, the gimbal in it (OMSLINE); not ok: the part axes above
    o2qBurnRm(now).                          // the OMS RM: a failed engine out of the burn (its last tick's thrust counted)
    IF o2qGmMode <> 0 AND o2qB["eng"]:LENGTH <> o2qGmN { o2qGmSet("ENGINES " + o2qB["eng"]:LENGTH). }
    FOR en IN o2qB["eng"] { SET av TO av + en:FACING:FOREVECTOR * en:AVAILABLETHRUST. }
    IF NOT o2qB["chk"] AND now - o2qB["t0"] > 1 { SET o2qB["chk"] TO TRUE. }
    LOCAL gdl IS o2qGdLost().                // SW 02 ORBIT BURN: the guidance halts (the count flies on); the edge is logged below
    LOCAL pa IS av.                          // the steering line's fallback (the engines left after the RM, their partner's trim): the part axes
    IF pa:MAG < 0.01 { SET pa TO SHIP:FACING:FOREVECTOR. }
    LOCAL trim IS pa.
    IF NOT o2qB["scalar"] { SET trim TO o2lSteer(o2lUids(o2qB["eng"]), pa). }   // The trim line (body-fixed, no gimbal deflection, no lag)
    LOCAL fo IS SHIP:FACING:FOREVECTOR.
    LOCAL fl IS ol["f"].
    LOCAL inl IS LIST(now, fv:X, fv:Y, fv:Z, fs, av:X, av:Y, av:Z, fo:X, fo:Y, fo:Z, SHIP:AVAILABLETHRUST, SHIP:MASS,
        o2bnB(ol["ok"]), fl:X, fl:Y, fl:Z, trim:X, trim:Y, trim:Z, o2qB["eng"]:LENGTH, o2bnB(o2qB["cutreq"]), o2bnB(gdl)).
    LOCAL out IS 0.
    LOCAL p4 IS pg:HASKEY("rt").
    LOCAL p8 IS pg:HASKEY("p8") AND pg["p8"].
    IF p4 OR p8 {                            // the re-solve between the count and the decisions
        LOCAL sn IS ADDONS:KALS:O2BURNSENSE(inl).
        IF sn:ISTYPE("String") { o2bnDrop("" + sn, pg). RETURN FALSE. }
        o2bnPre(sn[0], sn[1], gdl, pg).
        SET pg["vgo"] TO V(sn[3], sn[4], sn[5]).
        SET pg["tprev"] TO now.
        SET pg["hold"] TO sn[2] > 0.5.
        IF p4 AND NOT gdl { o2p4Cycle(pg, SHIP:POSITION - SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT). }
        IF p8 AND NOT gdl AND o2p8Due(pg, now) {
            o2p8Shot(pg, now, SHIP:POSITION - SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT, now, pg["vgo"]).
            IF pg["nfail"] >= O2P8_FAILS AND pg["nfailrow"] = 0 { SET pg["nfailrow"] TO 1. o2qSay("PEG 8: " + pg["why"]:TOUPPER + ": BACKUP SW PEG 7", "Y"). }
        }
        LOCAL sv IS ADDONS:KALS:O2BURNSETVGO(LIST(pg["vgo"]:X, pg["vgo"]:Y, pg["vgo"]:Z)).
        IF sv:ISTYPE("String") { o2bnDrop("" + sv, pg). RETURN FALSE. }
        SET out TO ADDONS:KALS:O2BURNDECIDE().
        IF out:ISTYPE("String") { o2bnDrop("" + out, pg). RETURN FALSE. }
    } ELSE {
        SET out TO ADDONS:KALS:O2BURNSTEP(inl).
        IF out:ISTYPE("String") { o2bnDrop("" + out, pg). RETURN FALSE. }
        o2bnPre(out[20], out[21], gdl, pg).
    }
    LOCAL why IS out[0].
    LOCAL ev IS ROUND(out[9]).
    SET o2qThr TO out[1].
    IF o2bnBit(ev, 0) {
        SET o2qB["tapl"] TO TRUE.
        o2qLogLine("BURN TAPER stretched to " + ROUND(out[10], 2) + " s (the physics tick " + ROUND(out[11], 3) + " s: the engines answer ~3 ticks late, so the cut waits for a slower taper)").
    }
    LOCAL tl IS V(out[6], out[7], out[8]).
    IF o2bnBit(ev, 1) {                      // once, the thrust steady: the trim line against the measured
        SET o2qB["pchk"] TO TRUE.
        LOCAL op IS o2lGet(ul, "trim").
        IF op["ok"] {
            LOCAL dd IS o2lAng(op["f"], ol["f"]).
            o2qLogLine("OMS LINE PRED-MEAS " + ROUND(dd, 2) + " DEG" + (CHOOSE " (OVER " + O2L_PRED_DEG + ")" IF dd > O2L_PRED_DEG ELSE "")).
            IF o2lBit(op["flags"], 2) { o2qLogLine("OMS TRIM CLAMPED TO THE GIMBAL RANGE"). }
        }
    }
    SET o2qLineT TO now.
    LOCAL tlb IS tl.                         // The steering line with the early bias (O2Q_FFO), until the freeze
    IF o2bnBit(ev, 4) { SET tlb TO o2qFfo(o2qB, ol, tl, now, o2qB["eng"]:LENGTH). }
    IF o2bnBit(ev, 2) {                      // The aim stops here
        SET o2qB["frz"] TO TRUE.
        o2qLogLine("AIM FROZEN at " + ROUND(out[13], 1) + " m/s left (the DAP holds the attitude to the cut; error to the aim now " + ROUND(o2qAimErr(), 2) + " deg)").
        LOCAL dirF IS V(out[16], out[17], out[18]).
        SET o2qB["fzd"] TO dirF.             // The csv's tl_fz = the measured line's angle off this frozen direction
        IF o2bnBit(ev, 3) {                  // The freeze puts the thrust line the engines GAVE on the direction
            o2qAimTv(dirF, ol["f"]).
            o2qLogLine("AIM CORRECTED to the measured thrust line: it was " + ROUND(out[14], 2) + " deg off the steering (the trim line " + ROUND(out[15], 2) + " deg), the DAP turns the attitude by that to the cut").
        }
    }
    IF o2bnBit(ev, 5) { o2qAimTv(V(out[3], out[4], out[5]), tlb). }
    SET o2qB["n"] TO ROUND(out[12]).
    IF why <> "" {
        o2bnToPg(pg).
        IF gdl { o2qLogLine("CUTOFF BY PLAN (GUIDANCE LOST): " + why + ", sensed " + ROUND(pg["sens"]:MAG, 3) + " of " + ROUND(pg["tot"], 3) + " m/s, VGO along " + ROUND(o2pAlong(pg), 3)). }
        SET o2qThr TO 0.
        SET o2qB["why"] TO why.
        SET o2qB["tcut"] TO now.
        o2qGmEnd(why).                       // The mode 0: the jets are the DAP's again
        SET o2qBurnOn TO FALSE.
        o2qBurnRow().
        ADDONS:KALS:O2BURNDROP().
        SET o2bnOn TO FALSE.
        RETURN TRUE.
    }
    IF o2bnBit(ev, 6) { o2bnToPg(pg). o2qBurnRow(). }
    RETURN TRUE.
}

// after the count: the axis check's log (o2qBurnTick logs it inside its 1 s test) and the guidance-lost edge (o2qGdEdge's own logging reads
// o2pAlong(pg), so the DLL's count is in the pg first)
FUNCTION o2bnPre {
    PARAMETER scEv, ratio, gdl, pg.
    IF scEv > 0.5 AND NOT o2qB["scalar"] {
        SET o2qB["scalar"] TO TRUE.
        o2qLogLine("BURN the engines' axes give " + ROUND(ratio, 4) + " of the thrust -> the scalar count").
    }
    IF gdl <> o2qGdWas { o2bnToPg(pg). o2qGdEdge(). }
}
