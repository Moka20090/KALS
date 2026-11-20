// lib_ascent_cd.ks -- THE LAUNCH COUNTDOWN, T-30 s to T-0, flown by ops1q on the pad: the ignition and launch sequence
// as the real countdown's (the sparklers, the throttle up, the SRBs), the launch tower's arms retracted if still out
// (the count holds at T-30 until they are in); the SSMEs at 100 %, 104 % from liftoff; the RSS left as it is (always
// parked); no pad abort but RSLS (below).
// The sequence (the real countdown's last 30 s): T-30 the count starts; an arm still out (the crew access arm, the LOX
// vent arm, the intertank access arm: Modular Launch Pads' "Retract Arm") is retracted and the count HOLDS at T-30
// until every one is in (and while ops1q names another hold reason in its "hold_x"); T-10 the sparklers (the hydrogen
// burn-off igniters: the two tail service masts' small engines, lit by part); T-6.6 main engine start, 120 ms apart in
// the order 3, 2, 1 (right, left, centre: lib_ascdisp's adEngIds), the throttle ramped from ASC_CD_K0 to ASC_CD_K1
// (100 %) over ASC_CD_RAMP s, then the SSMEs' stage used up; T-0 the SRBs' stage (the SRBs, the hold-down release, the
// tail service masts' umbilicals, the hydrogen vent arm). Stage 1 takes 104 % from liftoff (ops1q). MET from T-0.
// Vessel calls only here; ops1q's asc_pad calls asc_cd_new once and asc_cd_tick every pass, and reads its "k" (the
// throttle, PL %), "txt" (the pages' GUID field), "t_fire" (T-0's UT) and "log" (its lines for the PEG log,
// written at liftoff). SET ASC_CD TO FALSE. before the run: no countdown (the crew stages).
// RSLS (an SSME failure between the T-6.6 SSME start and T-0: the SSMEs shut down, the SRBs not lit): the real
// Redundant Set Launch Sequencer watches the SSMEs from main engine start to T-0
// (the SRB ignition command): one that fails, or is below 90 % by T-3, and all three are shut down, the SRBs never lit,
// the count stopped (STS 41-D, 51-F, 55, 51, 68). asc_cd_watch: a started SSME not lit / flamed out (ASC_CD_RSLS_G s
// after its start), or from T-ASC_CD_RSLS_T below ASC_CD_RSLS_K x the strongest's thrust -> asc_cd_rsls_go: every SSME
// shut down, its gimbal locked, the throttle 0, "st" RSLS (no staging after it: the SRBs and the hold-downs stay),
// "txt" RSLS ABORT; "rsls_k" (out / low <%> / no start) and "rsls_uid" for ops1q's message (asc_pad_rsls), which ends
// the run ASC_CD_RSLS_HOLD s later. asc_cd_fail: ops1q's failure on the pad (a FAIL button, ASC_EO at a time before T-0).
@LAZYGLOBAL OFF.
RUNONCEPATH("0:/lib/lib_ascent_iload.ks").   // ASC_SSME_RPL
RUNONCEPATH("0:/lib/lib_ascdisp.ks").        // adEngIds (the SSMEs by position)

GLOBAL ASC_CD_ON IS TRUE.        // ops1q: FALSE with SET ASC_CD TO FALSE. before the run
GLOBAL ASC_CD_T IS 30.           // s: the count starts, and holds, at T-30
GLOBAL ASC_CD_SPK IS 10.         // s: T-10, the sparklers
GLOBAL ASC_CD_MES IS 6.6.        // s: T-6.6, main engine start (engine 3)
GLOBAL ASC_CD_DT IS 0.12.        // s: between the SSMEs' starts (3, 2, 1)
GLOBAL ASC_CD_K0 IS 10.          // PL %: the throttle at the first start
GLOBAL ASC_CD_K1 IS 100.         // PL %: on the pad from the end of the ramp (104 % from liftoff: stage 1's)
GLOBAL ASC_CD_RAMP IS 3.5.       // s: the ramp K0 -> K1
GLOBAL ASC_CD_ARM_T IS 15.       // s: an arm whose module has no status field counts as in this long after its command
GLOBAL ASC_CD_ARM_MIN IS 1.      // s: an arm's status read no sooner than this after its command (it starts moving)
GLOBAL ASC_CD_RSLS IS TRUE.      // RSLS: the SSME monitor from main engine start to T-0 (FALSE: none, as before)
GLOBAL ASC_CD_RSLS_K IS 0.9.     // an SSME below this x the strongest's thrust from T-3 is low (the real RSLS: 90 % by T-3)
GLOBAL ASC_CD_RSLS_T IS 3.       // s: the thrust check from T-3
GLOBAL ASC_CD_RSLS_G IS 0.5.     // s: an SSME watched from this long after its start (KSP lights it at ACTIVATE)
GLOBAL ASC_CD_RSLS_HOLD IS 5.    // s: ops1q ends the run this long after an RSLS abort

// The SSMEs before they start: the engines KSP throttles that give at least half an SSME's rated thrust (asc_ssme_detect's
// test), none lit
FUNCTION asc_cd_ssmes {
  LOCAL es IS LIST().
  LIST ENGINES IN es.
  LOCAL out IS LIST().
  FOR en IN es {
    IF NOT en:THROTTLELOCK { IF en:POSSIBLETHRUSTAT(0) > ASC_SSME_RPL / 2 { out:ADD(en). } }
  }
  RETURN out.
}

// The arms still out, each commanded in: LIST(module, UT of the command, title)
FUNCTION asc_cd_arms {
  LOCAL out IS LIST().
  FOR pt IN SHIP:PARTS {
    IF pt:NAME:CONTAINS("ShuttleTower") AND pt:HASMODULE("ModuleAnimateGenericExtra") {
      LOCAL m IS pt:GETMODULE("ModuleAnimateGenericExtra").
      IF m:HASEVENT("retract arm") {
        m:DOEVENT("retract arm").
        out:ADD(LIST(m, TIME:SECONDS, pt:TITLE)).
      }
    }
  }
  RETURN out.
}

FUNCTION asc_cd_arm_in {                 // an arm commanded in: in once its status no longer says moving
  PARAMETER a.
  LOCAL m IS a[0].
  LOCAL dt IS TIME:SECONDS - a[1].
  IF m:HASEVENT("retract arm") {          // the command did not take: again
    m:DOEVENT("retract arm").
    SET a[1] TO TIME:SECONDS.
    RETURN FALSE.
  }
  IF dt < ASC_CD_ARM_MIN { RETURN FALSE. }
  IF m:HASFIELD("status") { RETURN NOT m:GETFIELD("status"):TOLOWER:CONTAINS("moving"). }
  RETURN dt >= ASC_CD_ARM_T.
}

FUNCTION asc_cd_say {                    // a line for the PEG log: #cd,<s to T-0>,<what>
  PARAMETER cdst, s.
  LOCAL tm IS -1.
  IF cdst["t0"] > 0 { SET tm TO ROUND(cdst["t0"] - TIME:SECONDS, 2). }
  cdst["log"]:ADD("#cd," + tm + "," + s).
}

// The countdown's state; st OFF (on = FALSE, off the pad, or an SSME already lit: the crew's launch as before), HOLD
// (at T-30), COUNT, T0 (the SRBs' stage asked), LIT (fired)
FUNCTION asc_cd_new {
  PARAMETER use.
  LOCAL cdst IS LEXICON("st", "OFF", "t0", -1, "t_fire", -1, "k", 0, "txt", "", "log", LIST(), "arms", LIST(),
    "hold_x", LIST(), "spk", FALSE, "eng", LIST(), "mes", 0, "t_mes", -1, "s4", FALSE, "why", "", "fail", LIST(),
    "rsls_k", "", "rsls_uid", "").
  LOCAL ss IS asc_cd_ssmes().
  LOCAL lit IS FALSE.
  FOR en IN ss { IF en:IGNITION { SET lit TO TRUE. } }
  IF NOT use { SET cdst["why"] TO "ASC_CD FALSE". }
  ELSE IF SHIP:STATUS <> "PRELAUNCH" AND SHIP:STATUS <> "LANDED" { SET cdst["why"] TO "not on the pad (" + SHIP:STATUS + ")". }
  ELSE IF lit { SET cdst["why"] TO "an SSME already lit". }
  ELSE IF ss:LENGTH = 0 { SET cdst["why"] TO "no SSME found". }
  IF cdst["why"] <> "" {
    asc_cd_say(cdst, "off," + cdst["why"]).
    RETURN cdst.
  }
  LOCAL ord IS "as listed".
  IF ss:LENGTH = 3 {
    LOCAL ids IS adEngIds(ss).
    IF ids:HASKEY("C") { SET cdst["eng"] TO LIST(ids["R"], ids["L"], ids["C"]). SET ord TO "3-2-1". }   // R L C
  }
  IF cdst["eng"]:LENGTH = 0 { SET cdst["eng"] TO ss. }
  SET cdst["arms"] TO asc_cd_arms().
  SET cdst["st"] TO "HOLD".
  SET cdst["t0"] TO TIME:SECONDS + ASC_CD_T.
  LOCAL nm IS "".
  FOR a IN cdst["arms"] { SET nm TO nm + ";" + a[2]. }
  asc_cd_say(cdst, "start,ssmes " + ss:LENGTH + ",order " + ord + ",arms out " + cdst["arms"]:LENGTH + nm).
  RETURN cdst.
}

FUNCTION asc_cd_stage_of {               // the stage a part list fires in (-1: none)
  PARAMETER ps.
  IF ps:LENGTH = 0 { RETURN -1. }
  RETURN ps[0]:STAGE.
}

FUNCTION asc_cd_srbs {                   // the SRBs before ignition: throttle-locked engines with solid fuel
  LOCAL es IS LIST().
  LIST ENGINES IN es.
  LOCAL out IS LIST().
  FOR en IN es {
    IF en:THROTTLELOCK {
      LOCAL sol IS FALSE.
      FOR rs IN en:RESOURCES { IF rs:NAME = "SolidFuel" AND rs:CAPACITY > 0 { SET sol TO TRUE. } }
      IF sol { out:ADD(en). }
    }
  }
  RETURN out.
}

FUNCTION asc_cd_rsls_go {                // RSLS: every SSME shut down, the count stopped for good
  PARAMETER cdst, kind, uid.
  FOR en IN cdst["eng"] {
    en:SHUTDOWN().                       // lit or not (a started SSME not lit yet would light later)
    IF en:HASGIMBAL { SET en:GIMBAL:LOCK TO TRUE. }
  }
  SET cdst["st"] TO "RSLS".
  SET cdst["rsls_k"] TO kind.
  SET cdst["rsls_uid"] TO uid.
  SET cdst["k"] TO 0.
  SET cdst["t_mes"] TO -1.
  SET cdst["txt"] TO "RSLS ABORT".
  asc_cd_say(cdst, "rsls," + kind + "," + uid).
}

FUNCTION asc_cd_watch {                  // the monitor, each pass of the count once an SSME has started (tm: s to T-0)
  PARAMETER cdst, tm, now.
  IF NOT ASC_CD_RSLS OR cdst["mes"] = 0 { RETURN. }
  LOCAL tmax IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= cdst["mes"] STEP { SET i TO i + 1. } DO {
    LOCAL en IS cdst["eng"][i].
    IF now - (cdst["t_mes"] + i * ASC_CD_DT) >= ASC_CD_RSLS_G {
      IF NOT en:IGNITION OR en:FLAMEOUT { asc_cd_rsls_go(cdst, "out", en:UID). RETURN. }
    }
    SET tmax TO MAX(tmax, en:THRUST).
  }
  IF tm <= ASC_CD_RSLS_T AND cdst["mes"] >= cdst["eng"]:LENGTH AND tmax > 0 {
    FOR en IN cdst["eng"] {
      IF en:THRUST < ASC_CD_RSLS_K * tmax { asc_cd_rsls_go(cdst, "low " + ROUND(en:THRUST / tmax * 100), en:UID). RETURN. }
    }
  }
}

FUNCTION asc_cd_fail {                   // ops1q's failure on the pad: TRUE when en is one of the count's SSMEs
  PARAMETER cdst, en.
  LOCAL i IS 0.
  FOR eg IN cdst["eng"] {
    IF eg:UID = en:UID {
      IF i < cdst["mes"] { en:SHUTDOWN(). }                      // started: the monitor stops the count
      ELSE { cdst["fail"]:ADD(en:UID). }                         // not yet: it will not start
      RETURN TRUE.
    }
    SET i TO i + 1.
  }
  RETURN FALSE.
}

FUNCTION asc_cd_tick {
  PARAMETER cdst.
  LOCAL now IS TIME:SECONDS.
  IF cdst["st"] = "OFF" OR cdst["st"] = "RSLS" { RETURN. }
  IF cdst["st"] = "HOLD" {
    LOCAL out IS 0.
    FOR a IN cdst["arms"] { IF NOT asc_cd_arm_in(a) { SET out TO out + 1. } }
    LOCAL why IS cdst["hold_x"]:COPY.
    IF out > 0 { why:INSERT(0, "ARMS " + out). }
    SET cdst["t0"] TO now + ASC_CD_T.
    IF why:LENGTH = 0 {
      SET cdst["st"] TO "COUNT".
      asc_cd_say(cdst, "count").
    } ELSE {
      SET cdst["txt"] TO "T-" + ASC_CD_T + " HOLD".
      IF NOT cdst:HASKEY("why_l") OR cdst["why_l"] <> why:JOIN(";") {
        SET cdst["why_l"] TO why:JOIN(";").
        asc_cd_say(cdst, "hold," + cdst["why_l"]).
      }
      RETURN.
    }
  }
  LOCAL tm IS cdst["t0"] - now.
  IF cdst["st"] = "COUNT" {
    IF NOT cdst["spk"] AND tm <= ASC_CD_SPK {
      SET cdst["spk"] TO TRUE.
      LOCAL es IS LIST().
      LIST ENGINES IN es.
      LOCAL n IS 0.
      FOR en IN es { IF en:NAME:CONTAINS("ShuttleLauncherTSM") AND NOT en:IGNITION { en:ACTIVATE(). SET n TO n + 1. } }
      asc_cd_say(cdst, "sparklers," + n).
    }
    UNTIL cdst["mes"] >= cdst["eng"]:LENGTH OR tm > ASC_CD_MES - cdst["mes"] * ASC_CD_DT {
      IF cdst["mes"] = 0 { SET cdst["t_mes"] TO now. SET cdst["k"] TO ASC_CD_K0. }
      LOCAL en IS cdst["eng"][cdst["mes"]].
      SET cdst["mes"] TO cdst["mes"] + 1.
      IF cdst["fail"]:CONTAINS(en:UID) AND ASC_CD_RSLS { asc_cd_rsls_go(cdst, "no start", en:UID). RETURN. }   // RSLS
      en:ACTIVATE().
      asc_cd_say(cdst, "ssme " + cdst["mes"] + "," + en:UID).
    }
    asc_cd_watch(cdst, tm, now).            // RSLS: before any staging this pass
    IF cdst["st"] = "RSLS" { RETURN. }
    IF cdst["mes"] >= cdst["eng"]:LENGTH AND NOT cdst["s4"] AND STAGE:READY {
      SET cdst["s4"] TO TRUE.
      IF asc_cd_stage_of(cdst["eng"]) = STAGE:NUMBER - 1 { STAGE. asc_cd_say(cdst, "ssme stage," + STAGE:NUMBER). }
      ELSE { asc_cd_say(cdst, "ssme stage not next," + asc_cd_stage_of(cdst["eng"]) + "," + STAGE:NUMBER). }
    }
    IF tm <= 0 { SET cdst["st"] TO "T0". }
  }
  IF cdst["t_mes"] > 0 { SET cdst["k"] TO MIN(ASC_CD_K1, ASC_CD_K0 + (ASC_CD_K1 - ASC_CD_K0) * (now - cdst["t_mes"]) / ASC_CD_RAMP). }
  IF cdst["st"] = "T0" AND STAGE:READY {
    LOCAL nx IS STAGE:NUMBER - 1.
    LOCAL sb IS asc_cd_stage_of(asc_cd_srbs()).
    IF sb = nx {
      STAGE.
      SET cdst["st"] TO "LIT".
      SET cdst["t_fire"] TO now.
      asc_cd_say(cdst, "srb stage," + STAGE:NUMBER).
    } ELSE IF asc_cd_stage_of(cdst["eng"]) = nx {
      STAGE.                               // the SSMEs' stage still next: use it up first
      asc_cd_say(cdst, "ssme stage late," + STAGE:NUMBER).
    } ELSE {
      SET cdst["st"] TO "LIT".                // not the SRBs' stage: no staging by the count (the crew's)
      asc_cd_say(cdst, "srb stage not next," + sb + "," + nx).
      SET cdst["txt"] TO "STAGE SRBS".
      RETURN.
    }
  }
  IF cdst["st"] = "COUNT" { SET cdst["txt"] TO "T-" + MAX(0, CEILING(tm)). }
  ELSE IF cdst["st"] = "T0" OR cdst["st"] = "LIT" { IF cdst["txt"] <> "STAGE SRBS" { SET cdst["txt"] TO "T-0". } }
}
