// lib_o2rcs.ks -- ops2q's OMS/RCS page: the pure parts. No vessel, no GUI: the kOS VM runs it
// (tests/o2rcs_selftest.ks). ops2q.ks reads the vessel and calls these.
// THE VEHICLE (read off the part cfgs, Benjee10_shuttleOrbiter): the orbiter has ONE forward-fuselage part (RCS modules
// RCS_Y / RCS_Z+ / RCS_Z- / RCS_X: 14 jets, a MonoPropellant tank of 200) and ONE aft-fuselage part (3 RCS modules, the 24 jets
// of the left and right aft pods, 12 each; MonoPropellant 200; the OMS tanks: LiquidFuel 360 / Oxidizer 440 for BOTH OMS engines)
// and NO vernier part. So: the pods F / L / R are 14 / 12 / 12 jets (O2R_JETS: a table, kOS has no per-thruster list), the L and
// R pods share the aft tank (their QTY % is the same number) and the XFER moves MonoPropellant between the two fuselage parts.
// The verniers are EMULATED on the primaries: JET SEL VERN limits every RCS
// module's thrust to O2R_VERN_PCT and the DAP's deadband and rate to O2R_VERN_DB / O2R_VERN_RATE.
GLOBAL O2R_JETS IS LIST(14, 12, 12).         // the jets of the pods F, L, R (the part models)
GLOBAL O2R_VERN_PCT IS 3.                    // JET SEL VERN: the RCS modules' thrust limit, % (the real vernier: 25 lbf of 870)
GLOBAL O2R_VERN_DB IS 0.1.                   // deg: the DAP's deadband in VERN (the page's DB, kept when it is smaller already)
GLOBAL O2R_VERN_RATE IS 0.2.                 // deg/s: the DAP's rate in VERN (the page's RATE, kept when it is smaller already)
GLOBAL O2R_XFER_RATE IS 1.                   // % of the RCS propellant a second
GLOBAL O2R_XFER_DONE IS 0.05.                // % of the total: the transfer is at its target within this
GLOBAL O2R_LAMP_ON IS 0.05.                  // the DAP's command (-1 .. 1) past which a jet lamp is lit
GLOBAL O2R_PC_RED IS 0.8.                    // a Pc under this fraction of the commanded one is red (lib_o2peg o2pEoWhy's 80 %)
GLOBAL O2R_PC_GRACE IS 1.5.                  // s after an OMS engine's ignition before its Pc may read red (the spool-up)

// ---- the Pc tapes (sprites o2_bg/pcg_<n> green, pcr_<n> red: the whole bar red = a failed engine)
FUNCTION o2rTapeN { PARAMETER pc. RETURN MAX(0, MIN(100, ROUND(pc))). }
FUNCTION o2rTapeName {                       // the tape sprite for the actual Pc (fill), red or green
    PARAMETER act, isRed.
    RETURN (CHOOSE "pcr_" IF isRed ELSE "pcg_") + o2rTapeN(act).
}
FUNCTION o2rPtrY {                           // the commanded-Pc pointer's tip, px below the tape sprite's top: 165 at 0, 9 at 100
    PARAMETER cmd.
    RETURN 165 - 1.56 * MAX(0, MIN(100, cmd)).
}
FUNCTION o2rRed {                            // the bar is red: the engine is out, or it burns under 80 % of what is commanded
    PARAMETER out, act, cmd.
    RETURN out OR (cmd > 5 AND act < O2R_PC_RED * cmd).
}
FUNCTION o2rWarm {                           // the red test may read a low Pc: O2R_PC_GRACE s since the engine's ignition t0
    PARAMETER t0, now.
    RETURN now - t0 >= O2R_PC_GRACE.
}

// ---- the RCS CMD lamps: the DAP's command on an axis -> -1 (the first lamp: LEFT / DOWN), 0 (none), +1 (the second: RIGHT / UP)
FUNCTION o2rLamp {
    PARAMETER u.
    IF u >= O2R_LAMP_ON { RETURN 1. }
    IF u <= -O2R_LAMP_ON { RETURN -1. }
    RETURN 0.
}

// ---- the RCS pods
FUNCTION o2rPct {                            // amount of capacity as a percent (0 when there is no tank)
    PARAMETER amt, cap.
    IF cap <= 0 { RETURN 0. }
    RETURN 100 * amt / cap.
}
FUNCTION o2rJets {                           // the jets working of a pod: its jets x the share of its modules that are enabled and lit-able
    PARAMETER tot, ok, all.
    IF all <= 0 { RETURN tot. }
    RETURN ROUND(tot * ok / all).
}
FUNCTION o2rDllJets {                        // The pods' REAL jet counts from the DLL (ADDONS:KALS:RCSPOD, coproc/RcsJets.cs): tot / wk replaced, "jets" TRUE; a no-op without the suffix. out = o2qRcsRead's / cwRcsRead's list of the pods F, L, R. A jet a failure took out (RCS 01 manifold, RCS 04 stuck off) is not working; a pod whose tank is empty works 0.
    PARAMETER out.
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN out. }
    IF NOT ADDONS:KALS:HASSUFFIX("RCSPOD") { RETURN out. }
    LOCAL pc IS ADDONS:KALS:RCSPOD().
    IF pc:LENGTH <> 3 { RETURN out. }
    FROM { LOCAL p IS 0. } UNTIL p > 2 STEP { SET p TO p + 1. } DO {
        LOCAL d IS out[p].
        IF d["has"] AND pc[p][1] > 0 {
            SET d["tot"] TO pc[p][1].
            SET d["wk"] TO CHOOSE pc[p][2] IF d["ok"] ELSE 0.
            SET d["jets"] TO TRUE.
        }
    }
    RETURN out.
}
FUNCTION o2rBal {                            // XFER's balance: the forward module's share of all the RCS propellant, % (100 = all forward)
    PARAMETER fwd, aft.
    IF fwd + aft <= 0 { RETURN 0. }
    RETURN 100 * fwd / (fwd + aft).
}
// one XFER step: the propellant to move this chunk, signed (+ = aft -> forward), toward the target balance tgt (%). 0 = at the
// target (within O2R_XFER_DONE % of the total). The chunk is O2R_XFER_RATE % of the total (a second's worth); never more than
// is needed, the source holds or the destination has room for.
FUNCTION o2rXferStep {
    PARAMETER fwd, aft, fwdCap, aftCap, tgt.
    LOCAL tot IS fwd + aft.
    IF tot <= 0 { RETURN 0. }
    LOCAL need IS (tgt - o2rBal(fwd, aft)) / 100 * tot.   // + = the forward module must gain
    IF ABS(need) < O2R_XFER_DONE / 100 * tot { RETURN 0. }
    LOCAL chunk IS MIN(ABS(need), O2R_XFER_RATE / 100 * tot).
    IF need > 0 { RETURN MIN(chunk, MIN(aft, fwdCap - fwd)). }
    RETURN -MIN(chunk, MIN(fwd, aftCap - aft)).
}

// ---- formatting
FUNCTION o2rSg1 {                            // a signed number, one decimal, no space: "+0.4", "-5.7", "+0.0"
    PARAMETER x.
    LOCAL a IS ROUND(ABS(x), 1).
    LOCAL s IS "" + a.
    IF NOT s:CONTAINS(".") { SET s TO s + ".0". }
    RETURN (CHOOSE "-" IF x < 0 AND a > 0 ELSE "+") + s.
}

// ---- the engine failures (the window's schedule). A row is LIST(mode "MET" / "TIG", t s, engine 0 L / 1 R / 2 ANY, done). MET: the
// mission time t; TIG: t s from the loaded burn's TIG (negative = before). metNow, tigMet = the burn's TIG as MET (-1E9 = no burn).
FUNCTION o2rDue {
    PARAMETER row, metNow, tigMet.
    IF row[3] { RETURN FALSE. }
    IF row[0] = "MET" { RETURN metNow >= row[1]. }
    IF tigMet < -1E8 { RETURN FALSE. }
    RETURN metNow >= tigMet + row[1].
}
FUNCTION o2rPickEng {                        // the engine a row fails: its own, or (ANY) one of the good ones by the roll rn (0 .. 1); -1 = none left
    PARAMETER k, good, rn.
    IF k = 0 OR k = 1 { RETURN CHOOSE k IF good:CONTAINS(k) ELSE -1. }
    IF good:LENGTH = 0 { RETURN -1. }
    RETURN good[MIN(good:LENGTH - 1, FLOOR(rn * good:LENGTH))].
}
