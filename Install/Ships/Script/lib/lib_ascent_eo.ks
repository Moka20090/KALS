// lib_ascent_eo.ks -- THE SSME-OUT DETECTOR: an engine failure from outside our script (a hand shutdown, an action
// group, a failure mod's shutdown, flame-out or explosion) flown as our own engine-out. The real Shuttle: the GPC's SSME
// SOP reads each engine controller's status; an engine in shutdown or post-shutdown that the GPC did not command is a
// premature shutdown, its out flag set and the "SSME FAIL" message annunciated, and guidance never asks why: it counts
// N_SSME = 3 - SUM(out flags) and every engine-out task runs when N_SSME drops (FSSR STS 83-0002-34 4.2.1-4.2.2; SCOM
// USA007587 2.16). Here: asc_eo_watch (ops1q's main loop, once a pass before the phase's work) returns the engines found
// out as LIST(k, why), ops1q hands each to asc_fail(k, why), the same call a FAIL button makes, so the messages, the
// displays, the aborts and the DAP are the same as for our own failure; only the log (#eo,<met>,<k>,<why>) has the cause.
// Our own shutdowns take the engine out of asc["ssme"] first (asc_fail) or come after t_meco (asc_meco), so an engine
// found dead in the list is premature by the real definition. An engine is out when:
//   G  it is gone from the vessel's engine list (found by the UID stored while it was whole; no suffix on a dead part)
//   S  NOT IGNITION (controller in shutdown)           F  FLAMEOUT (shutdown phase)
//   P  THRUST below ASC_EO_PK x the expected thrust (throttle x AVAILABLETHRUST) for ASC_EO_PT s (the real Pc < 30 %,
//      three 0.16 s GPC cycles); a thrust limiter lowers AVAILABLETHRUST too, so a degraded engine is flown on
// The watch runs from liftoff to MECO while the ET is above its reserve (at depletion MECO "res" fires first, as the
// real low-level cutoff). SET ASC_EO_EXT TO FALSE. before the run: no detector (the older behaviour).
@LAZYGLOBAL OFF.
// (ops1q loads lib_ascent_iload (ASC_ET_MECO_FRAC), lib_ascent_s2 (asc_burnable) and lib_ascdisp (adEngIds, adOut) before this
// one; asc_eo_why needs none of them, so tests/eo_selftest.ks runs on the kOS VM with this file alone)

GLOBAL ASC_EO_EXT_ON IS TRUE.    // ops1q: FALSE with SET ASC_EO_EXT TO FALSE. before the run
GLOBAL ASC_EO_DT IS 0.16.        // s: between two passes (the GPC cycle)
GLOBAL ASC_EO_PK IS 0.3.         // a lit SSME below this x its expected thrust ...
GLOBAL ASC_EO_PT IS 0.48.        // s: ... for this long is out

// The SSMEs of the liftoff list (ops1q's asc_pad; lit = asc_liquids()): the lit ones first, in their order; after a count
// that ran (cdst "eng", three SSMEs) the count's SSMEs still on the vessel that are not lit are added behind them, so an
// SSME that died between T-0 and the liftoff detection stays in asc["ssme"] and the detector's first pass declares it
// (S), instead of the flight going on with two engines and no failure. With three lit, without a count, with the count
// stopped (RSLS) or the detector off: lit as it is (a flight with every SSME lit is unchanged).
FUNCTION asc_eo_lift {
  PARAMETER cdst, lit.
  IF NOT ASC_EO_EXT_ON OR cdst:LENGTH = 0 OR lit:LENGTH >= 3 { RETURN lit. }
  IF cdst["st"] = "OFF" OR cdst["st"] = "RSLS" OR cdst["eng"]:LENGTH <> 3 { RETURN lit. }
  LOCAL es IS LIST().
  LIST ENGINES IN es.
  LOCAL alive IS LEXICON().
  FOR en IN es { SET alive[en:UID] TO TRUE. }
  LOCAL have IS LEXICON().
  FOR en IN lit { SET have[en:UID] TO TRUE. }
  LOCAL out IS lit:COPY.
  FOR en IN cdst["eng"] {
    IF alive:HASKEY(en:UID) AND NOT have:HASKEY(en:UID) { out:ADD(en). }
  }
  RETURN out.
}

// The rule for one engine, pure: LIST(why, tl). why "" (running), "G", "S", "F" or "P"; tl the seconds the thrust has
// been low. live: the watch window is open (FALSE: nothing is out, tl reset); gone: the part is no longer in the
// vessel's engine list (the other inputs are not read then); thr: the KSP throttle commanded (0 = nothing expected);
// avail: AVAILABLETHRUST (kN); thrust: THRUST (kN); tlow: tl of the last pass; dt: s since it.
FUNCTION asc_eo_why {
  PARAMETER live, gone, ign, flame, thr, avail, thrust, tlow, dt.
  IF NOT live { RETURN LIST("", 0). }
  IF gone { RETURN LIST("G", 0). }
  IF NOT ign { RETURN LIST("S", 0). }
  IF flame { RETURN LIST("F", 0). }
  IF thr > 0 AND avail > 0 AND thrust < ASC_EO_PK * thr * avail {
    LOCAL tl IS tlow + dt.
    IF tl >= ASC_EO_PT - 0.001 { RETURN LIST("P", tl). }
    RETURN LIST("", tl).
  }
  RETURN LIST("", 0).
}

// The engines found out this pass: LIST of LIST(k, why), k = "L" / "C" / "R" (the pages' positions). asc: ops1q's run
// state; thr: ops1q's throttle (asc_thr). Its state is asc["eo"]: LEXICON(t: the last pass's UT, recs: one LEXICON per
// SSME at liftoff: k, uid, en, tl, done).
FUNCTION asc_eo_watch {
  PARAMETER asc, thr.
  LOCAL out IS LIST().
  IF NOT ASC_EO_EXT_ON OR asc["t_lo"] < 0 OR asc["t_meco"] >= 0 OR asc["ssme"]:LENGTH = 0 { RETURN out. }
  LOCAL now IS TIME:SECONDS.
  IF NOT asc:HASKEY("eo") { SET asc["eo"] TO LEXICON("t", now, "recs", LIST()). }
  LOCAL st IS asc["eo"].
  IF now - st["t"] < ASC_EO_DT { RETURN out. }
  LOCAL dt IS now - st["t"].
  SET st["t"] TO now.
  LOCAL recs IS st["recs"].
  IF recs:LENGTH = 0 {                          // the SSMEs at liftoff by position, once adEngIds knows them
    LOCAL ids IS adEngIds(asc["ssme"]).
    FOR k IN LIST("L", "C", "R") {
      IF ids:HASKEY(k) {
        FOR en IN asc["ssme"] {
          IF en:UID = ids[k]:UID { recs:ADD(LEXICON("k", k, "uid", en:UID, "en", en, "tl", 0, "done", FALSE)). }
        }
      }
    }
    IF recs:LENGTH = 0 { RETURN out. }
  }
  LOCAL es IS LIST().
  LIST ENGINES IN es.
  LOCAL alive IS LEXICON().
  FOR en IN es { SET alive[en:UID] TO TRUE. }
  LOCAL live IS FALSE.                           // the window: the ET above its reserve, read on an engine still whole
  FOR rc IN recs {
    IF NOT rc["done"] AND alive:HASKEY(rc["uid"]) AND NOT adOut:HASKEY(rc["k"]) AND NOT live {
      SET live TO asc_burnable(LIST(rc["en"])) > ASC_ET_MECO_FRAC * asc["et_full"].   // T1008: MECO's floor
    }
  }
  FOR rc IN recs {
    IF NOT rc["done"] {
      IF adOut:HASKEY(rc["k"]) { SET rc["done"] TO TRUE. }     // out already: our own failure (a button, ASC_EO, RAND)
      ELSE {
        LOCAL rs IS LIST("", 0).
        IF NOT alive:HASKEY(rc["uid"]) { SET rs TO asc_eo_why(TRUE, TRUE, FALSE, FALSE, 0, 0, 0, 0, dt). }
        ELSE {
          LOCAL en IS rc["en"].
          SET rs TO asc_eo_why(live, FALSE, en:IGNITION, en:FLAMEOUT, thr, en:AVAILABLETHRUST, en:THRUST, rc["tl"], dt).
        }
        SET rc["tl"] TO rs[1].
        IF rs[0] <> "" {
          SET rc["done"] TO TRUE.
          out:ADD(LIST(rc["k"], rs[0])).
        }
      }
    }
  }
  RETURN out.
}
