@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_CWCHK.KS  --  the C&W checks' pure parts (no vessel, no GUI: the kOS VM tests them, tests/cw_selftest.ks)
// ============================================================================
//  A check (lib_cw's cwCheck) reads the vessel in its host, asks these functions, and calls cwSet / cwClear for its lamp.
//  cwDeb is the debounce: a condition must hold for secs before it counts (a spool-up, a throttle step or a one-tick
//  glitch is not a fault); it keeps its clocks in the lexicon st, one per key.
//  The level functions of the orbit systems (the host reads the vessel, these decide and call cwSet / cwClear, so the
//  VM tests drive them with made-up readings): cwRcsApply (the pods FWD / LEFT / RIGHT RCS and RCS JET), cwOmsApply (LEFT /
//  RIGHT OMS and OMS PRPLT). Every threshold has a hysteresis (CW_HYST): a lamp lit at a limit goes out CW_HYST past it.
// ============================================================================
RUNONCEPATH("0:/lib/lib_cw.ks").
GLOBAL CW_PC_LOW IS 0.8.                     // an SSME lit below this fraction of its expected thrust is a CAUTION (the O2R_PC_RED rule; lib_ascent_eo's out is 0.3)
GLOBAL CW_PC_LOW_S IS 2.                     // s it must hold (throttle steps are not a fault)
GLOBAL CW_PC_MIN_THR IS 0.3.                 // the commanded throttle below which the thrust is not judged

FUNCTION cwDeb {                             // st: LEXICON key -> UT the condition began (-1 = not holding); TRUE when it has held for secs
    PARAMETER st, key, cond, ut, secs.
    IF NOT cond { SET st[key] TO -1. RETURN FALSE. }
    IF NOT st:HASKEY(key) { SET st[key] TO -1. }
    IF st[key] < 0 { SET st[key] TO ut. }
    RETURN ut - st[key] >= secs.
}
FUNCTION cwPcLow {                           // a lit SSME under CW_PC_LOW x (throttle x available thrust): TRUE
    PARAMETER lit, thr, avail, thrust.
    IF NOT lit OR thr < CW_PC_MIN_THR OR avail <= 0 { RETURN FALSE. }
    RETURN thrust < CW_PC_LOW * thr * avail.
}

// ---- RCS pods and OMS
GLOBAL CW_HYST IS 2.                         // % past a limit before a lit lamp steps back
GLOBAL CW_RCS_QTY_W IS 5.                    // a pod's propellant, %: WARNING below ...
GLOBAL CW_RCS_QTY_C IS 20.                   // ... CAUTION below
GLOBAL CW_OPRP_W IS 3.                       // the OMS propellant (the lower of fuel / oxidizer), %
GLOBAL CW_OPRP_C IS 10.
GLOBAL CW_OPRP_IMB IS 8.                     // points between the fuel and oxidizer fractions: an unbalanced draw (CAUTION)
GLOBAL CW_DV_MARGIN IS 0.98.                 // the loaded burn needs more dV than the propellant left gives (x this): WARNING
GLOBAL CW_POD IS LIST("FWD", "LEFT", "RIGHT").
GLOBAL CW_POD_KEY IS LIST("FRCS", "LRCS", "RRCS").

FUNCTION cwLow {                             // val below the limits wTh / cTh -> "W" / "C" / "" (prev = the lamp's class now: its limits move CW_HYST up)
    PARAMETER val, prev, wTh, cTh.
    IF val < wTh + (CHOOSE CW_HYST IF prev = "W" ELSE 0) { RETURN "W". }
    IF val < cTh + (CHOOSE CW_HYST IF prev <> "" ELSE 0) { RETURN "C". }
    RETURN "".
}

// rp = LIST of 3 LEXICON(has, qty %, tot jets, wk jets working, ok, nm modules, nk modules enabled[, jets]) for the pods F, L, R (ops2q's
// o2qRcsRead / lib_cwsys's cwRcsRead). With the DLL (d["jets"] TRUE: o2rDllJets) RCS JET is at JET level: tot / wk are the pod's REAL jets
// (a closed manifold, a stuck-off jet are not working), and the row names the pods that lost jets: "RCS L 9/12  F 11/14". Without the DLL the old
// MODULE-GROUP row stays ("RCS FWD 3/4 MOD  AFT 2/3 MOD L+R": kOS can fail only a whole RCS module).
FUNCTION cwRcsApply {
    PARAMETER rp.
    LOCAL jt IS "".
    LOCAL jw IS FALSE.
    FROM { LOCAL p IS 0. } UNTIL p > 2 STEP { SET p TO p + 1. } DO {
        LOCAL d IS rp[p].
        LOCAL key IS CW_POD_KEY[p].
        IF NOT d["has"] { cwClear(key). }
        ELSE {
            LOCAL cls IS cwLow(d["qty"], cwLampCls(key), CW_RCS_QTY_W, CW_RCS_QTY_C).
            LOCAL tx IS CW_POD[p] + " RCS QTY " + ROUND(d["qty"]).
            IF cls = "" AND d["ok"] AND d["tot"] > 0 AND d["wk"] = 0 { SET cls TO "C". SET tx TO CW_POD[p] + " RCS OFF". }   // the pod's modules all disabled
            cwSet(key, cls, tx).
            IF d:HASKEY("jets") {                  // The DLL's real jets: this pod's lost jets; a pod with none working is the "RCS OFF" caution above
                IF d["ok"] AND d["wk"] > 0 AND d["wk"] < d["tot"] {
                    SET jt TO jt + (CHOOSE " " IF jt = "" ELSE "  ") + (CHOOSE "F" IF p = 0 ELSE (CHOOSE "L" IF p = 1 ELSE "R")) + " " + d["wk"] + "/" + d["tot"].
                    IF d["wk"] * 2 <= d["tot"] { SET jw TO TRUE. }
                }
            }
            ELSE IF p < 2 AND d["ok"] AND d["nm"] > 0 AND d["nk"] > 0 AND d["nk"] < d["nm"] {     // the aft part is read once (the L pod's entry; the R pod shares it)
                SET jt TO jt + (CHOOSE " " IF jt = "" ELSE "  ") + (CHOOSE "FWD " IF p = 0 ELSE "AFT ") + d["nk"] + "/" + d["nm"] + " MOD" + (CHOOSE "" IF p = 0 ELSE " L+R").
                IF d["nk"] * 2 <= d["nm"] { SET jw TO TRUE. }
            }
        }
    }
    LOCAL jc IS "".
    IF jt <> "" { SET jc TO CHOOSE "W" IF jw ELSE "C". }
    cwSet("JET", jc, "RCS" + jt).
}

// out0 / out1: why the OMS engine is out ("" = good); burning: a burn is lit; fu / ox: the OMS tanks %, -1 = no engine to read;
// dvBoard / dvNeed: m/s the propellant gives / the loaded burn needs (0 = none loaded)
FUNCTION cwOmsCause {                             // The causes ops2q / lib_o2peg write (o2pEoWhy: SHUTDOWN, FLAMEOUT, PC LOW; o2qOmsFail: GONE, CREW, TIMED); any other text is a source tag, not a cause
    PARAMETER s.
    RETURN LIST("SHUTDOWN", "FLAMEOUT", "PC LOW", "GONE", "CREW", "TIMED"):CONTAINS(s).
}
FUNCTION cwOmsApply {
    PARAMETER out0, out1, burning, fu, ox, dvBoard, dvNeed.
    LOCAL outs IS LIST(out0, out1).
    FROM { LOCAL k IS 0. } UNTIL k > 1 STEP { SET k TO k + 1. } DO {
        LOCAL oc IS "".
        IF outs[k] <> "" { SET oc TO CHOOSE "W" IF burning ELSE "C". }
        cwSet(LIST("LOMS", "ROMS")[k], oc, LIST("L", "R")[k] + " OMS OUT" + (CHOOSE " " + outs[k] IF cwOmsCause(outs[k]) ELSE "")).   // Only a real cause shows; a failure source tag (SIMSUP) never does
    }
    IF fu < 0 { RETURN. }
    LOCAL lo IS MIN(fu, ox).
    LOCAL cls IS cwLow(lo, cwLampCls("OPRP"), CW_OPRP_W, CW_OPRP_C).
    LOCAL tx IS "OMS PRPLT " + ROUND(lo) + " PCT".
    IF dvNeed > 0 AND dvBoard < dvNeed * CW_DV_MARGIN { SET cls TO "W". SET tx TO "OMS DV " + ROUND(dvBoard) + " < BURN " + ROUND(dvNeed). }
    IF cls = "" AND ABS(fu - ox) > CW_OPRP_IMB { SET cls TO "C". SET tx TO "OMS PRPLT IMBAL " + ROUND(fu) + "/" + ROUND(ox). }
    cwSet("OPRP", cls, tx).
}

// ============================================================================
//  FLT CNTL, GUID, GPC, ARM. Each is a pure function of readings the host passes in (the VM tests drive them with made-up
//  ones), debounced (cwDeb) and with a hysteresis, calling cwSet / cwClear for ITS lamp only: cwOwn clears a lamp only when this
//  check lit it (the key in st), so a row another source raised is never wiped. Conservative on purpose: a false alarm in
//  nominal flight is worse than a missing check (the limits below come from the nominal logs; every one is a GLOBAL to tune).
// ============================================================================
GLOBAL CW_DAP_X IS 5.                        // orbit DAP: a HOLD off by more than this x its deadband ...
GLOBAL CW_DAP_S IS 5.                        // ... for this many s = FLT CNTL CAUTION (a MNVR / CSS rate / track is not judged)
GLOBAL CW_DAP_DBMIN IS 0.1.                  // deg: the deadband used for that rule never below this
GLOBAL CW_DAP_W IS 20.                       // deg: a HOLD this far off for CW_DAP_WS s = WARNING (a runaway)
GLOBAL CW_DAP_WS IS 2.
GLOBAL CW_DAP_BURN IS 1.0.                  // deg: in a burn (ignition to cutoff) the CAUTION limit is this, fixed, not 5 x the deadband (T1016: the burn's 0.10 gave 0.5 deg)
GLOBAL CW_TRIM_S IS 3.                       // entry: the flap trim AND the elevon trim both at their stops this long = FLT CNTL CAUTION
GLOBAL CW_GMB_SAT IS 0.98.                   // ascent: an SSME gimbal (fraction of its range) at its stop ...
GLOBAL CW_GMB_S IS 3.                        // ... this long = FLT CNTL CAUTION
GLOBAL CW_PEG_UNCONV IS 40.                  // ascent: PEG passes in a row not converged (the nominal logs reach 18) = GUID CAUTION
GLOBAL CW_BANK_S IS 25.                      // entry: the commanded bank at MAX_BANK this long (guidance on the rail) = GUID CAUTION
GLOBAL CW_TAEM_DE IS 4000.                   // TAEM, from the HAC (iphase >= 2): |EOW - EN| m past this for CW_TAEM_S s = GUID CAUTION (nominal: under 2200)
GLOBAL CW_TAEM_S IS 5.
GLOBAL CW_TIG_GRACE IS 15.                   // orbit: s past TIG with no ignition = the burn was missed (GUID CAUTION)
GLOBAL CW_GPC_GAP IS 0.5.                    // s of real time between two ticks of the panel's trigger past which a cycle is a miss ...
GLOBAL CW_GPC_N IS 3.                        // ... this many in a row = GPC CAUTION "CYCLE OVERRUN" ...
GLOBAL CW_GPC_OK_S IS 10.                    // ... gone after this many s of normal cycles
GLOBAL CW_ARM_HOLD_S IS 10.                  // the arm's stall / model warning stays lit this long after its status text goes
GLOBAL CW_ARM_S IS 2.                        // a singular / held status must stay this long

FUNCTION cwOwn {                             // the level cls for lamp ("" = fine): lit by this check (st[key]) and cleared only by it
    PARAMETER st, key, lamp, cls, txt.
    IF cls <> "" { cwSet(lamp, cls, txt). SET st[key] TO TRUE. }
    ELSE IF st:HASKEY(key) AND st[key] { SET st[key] TO FALSE. cwClear(lamp). }
}

// FLT CNTL, orbit (ops2q): the DAP's attitude error ea (deg) against its deadband db while it flies a HOLD (act "HOLD"; on = the DAP flies)
FUNCTION cwDapApply {
    PARAMETER st, ut, on, act, ea, db, burn IS FALSE.
    LOCAL judged IS on AND act = "HOLD".
    LOCAL k IS CHOOSE 0.8 IF st:HASKEY("f") AND st["f"] ELSE 1.      // a lit lamp's limits are 20 % lower (hysteresis)
    LOCAL wy IS cwDeb(st, "dw", judged AND ea > CW_DAP_W * k, ut, CW_DAP_WS).
    LOCAL cLim IS CW_DAP_X * MAX(db, CW_DAP_DBMIN).
    IF burn { SET cLim TO CW_DAP_BURN. }
    LOCAL cy IS cwDeb(st, "dc", judged AND ea > cLim * k, ut, CW_DAP_S).
    LOCAL cls IS "".
    IF wy { SET cls TO "W". } ELSE IF cy { SET cls TO "C". }
    cwOwn(st, "f", "FCS", cls, "DAP ATT ERR " + ROUND(ea, 1) + " DEG").
}
// FLT CNTL, entry (ops3q): the flap trim (pAng, limit pLim) and the elevon trim (eAng, limit eLim) both on their stops; active = the trim runs
FUNCTION cwTrimApply {
    PARAMETER st, ut, active, pAng, pLim, eAng, eLim.
    LOCAL both IS active AND ABS(pAng) >= pLim - 0.3 AND ABS(eAng) >= eLim - 0.1.
    cwOwn(st, "f", "FCS", CHOOSE "C" IF cwDeb(st, "t", both, ut, CW_TRIM_S) ELSE "", "PITCH TRIM BOTH AT STOP").
}
// FLT CNTL, ascent (ops1q): frac = the largest lit SSME gimbal deflection as a fraction of its range (-1 = none lit)
FUNCTION cwGmbApply {
    PARAMETER st, ut, frac.
    LOCAL lim IS CW_GMB_SAT - (CHOOSE 0.03 IF st:HASKEY("f") AND st["f"] ELSE 0).
    cwOwn(st, "f", "FCS", CHOOSE "C" IF cwDeb(st, "g", frac >= lim, ut, CW_GMB_S) ELSE "", "SSME GIMBAL AT STOP").
}
// GUID, ascent (ops1q): the PEG's count of unconverged passes in a row
FUNCTION cwPegApply {
    PARAMETER st, unconv.
    cwOwn(st, "f", "GUID", CHOOSE "C" IF unconv > CW_PEG_UNCONV ELSE "", "PEG UNCONVERGED " + unconv).
}
// GUID, entry + TAEM (ops3q), one lamp: the bank command at its ceiling for CW_BANK_S (bankOn = entry guidance flies in the atmosphere), the TAEM
// energy off the profile (iph = the TAEM phase, de = EOW - EN in m, age = s since the TAEM cycle wrote them)
FUNCTION cwEntGuid {
    PARAMETER st, ut, bankOn, bank, maxb, iph, de, age.
    LOCAL k IS CHOOSE 0.8 IF st:HASKEY("f") AND st["f"] ELSE 1.
    LOCAL rail IS cwDeb(st, "b", bankOn AND ABS(bank) >= maxb - 0.5, ut, CW_BANK_S).
    LOCAL off IS cwDeb(st, "e", age < 3 AND iph >= 2 AND ABS(de) > CW_TAEM_DE * k, ut, CW_TAEM_S).
    LOCAL cls IS "". LOCAL tx IS "".
    IF off { SET cls TO "C". SET tx TO "TAEM OFF PROFILE " + ROUND(de / 1000, 1) + " KM". }
    ELSE IF rail { SET cls TO "C". SET tx TO "ENTRY GUIDANCE AT MAX BANK". }
    cwOwn(st, "f", "GUID", cls, tx).
}
// GUID, orbit (ops2q): a burn sequence running (seq <> "") past TIG (ig, UT) + CW_TIG_GRACE with no ignition (lit) = missed. A cutoff residual's
// row (cwResidual) stays until the next sequence starts before its TIG.
FUNCTION cwOrbGuid {
    PARAMETER st, ut, seq, lit, ig.
    IF seq <> "" AND ut < ig AND st:HASKEY("res") AND st["res"] { cwOwn(st, "res", "GUID", "", ""). }
    LOCAL miss IS seq <> "" AND NOT lit AND ut > ig + CW_TIG_GRACE.
    cwOwn(st, "m", "GUID", CHOOSE "C" IF miss ELSE "", "BURN MISSED").
}
// the burn's end (ops2q's o2qSeqEnd): lf = VGO left (m/s), tot = the burn's dV, why = "CUT" / "CREW" / "THRUST"; a crew cut is the crew's call
FUNCTION cwResidual {
    PARAMETER st, lf, tot, why.
    IF why = "CREW" { RETURN. }
    // The BURN SHORT row is deleted (the two texts, THRUST LOST / CUTOFF RESIDUAL): no row is set here now
}
// GPC: rt = the real time at each tick of the panel's trigger. CW_GPC_N gaps over CW_GPC_GAP in a row = the cycle overran
FUNCTION cwGpcStep {
    PARAMETER st, rt.
    IF NOT st:HASKEY("last") { SET st["last"] TO rt. SET st["n"] TO 0. SET st["ok"] TO 0. SET st["f"] TO FALSE. RETURN. }
    LOCAL gap IS rt - st["last"].
    SET st["last"] TO rt.
    IF gap > CW_GPC_GAP {
        SET st["n"] TO st["n"] + 1.
        SET st["ok"] TO 0.
        IF st["n"] >= CW_GPC_N { cwOwn(st, "f", "GPC", "C", "GPC CYCLE OVERRUN " + ROUND(gap, 1) + " S"). }
    } ELSE {
        SET st["n"] TO 0.
        SET st["ok"] TO st["ok"] + gap.
        IF st["f"] AND st["ok"] >= CW_GPC_OK_S { cwOwn(st, "f", "GPC", "", ""). }
    }
}
// ARM (ops2q's arm page): arm.ks's status text txt (upper case, "" none). A joint stall / model miss / "cannot keep up" = WARNING (kept
// CW_ARM_HOLD_S s: arm.ks shows it for a moment); SINGULAR or a held command = CAUTION once it stays CW_ARM_S s. RATE LIMITED alone is routine.
FUNCTION cwArmApply {
    PARAMETER st, ut, txt.
    LOCAL wt IS "".
    IF txt:CONTAINS("STALL") { SET wt TO "ARM JOINT STALL". }
    ELSE IF txt:CONTAINS("MODEL") { SET wt TO "ARM MODEL MISS". }
    ELSE IF txt:CONTAINS("CANNOT KEEP UP") { SET wt TO "ARM CANNOT KEEP UP". }
    IF wt <> "" { SET st["wu"] TO ut + CW_ARM_HOLD_S. SET st["wt"] TO wt. }
    LOCAL cls IS "". LOCAL tx IS "".
    IF st:HASKEY("wu") AND ut < st["wu"] { SET cls TO "W". SET tx TO st["wt"]. }
    ELSE {
        IF cwDeb(st, "s", txt:CONTAINS("SINGULAR"), ut, CW_ARM_S) { SET cls TO "C". SET tx TO "ARM SINGULAR". }
        ELSE IF cwDeb(st, "h", txt:CONTAINS("  HELD"), ut, CW_ARM_S) { SET cls TO "C". SET tx TO "ARM HELD: CANNOT KEEP UP". }
    }
    cwOwn(st, "f", "ARM", cls, tx).
}
FUNCTION cwArmStop {                         // the arm program ended: its lamp goes dark (only what this check lit)
    PARAMETER st.
    SET st["wu"] TO -1.
    cwOwn(st, "f", "ARM", "", "").
}
