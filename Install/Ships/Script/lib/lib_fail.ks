@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_FAIL.KS  --  the FAILURE SYSTEM's state: the catalog of failure codes, the pending ROWS (MET / TIG), the ACTIVE list,
//  the real FIXES (with their delays), RAND, persistence, the lamp / log calls. NO GUI here (lib_failui.ks draws the window, S2);
//  no host is on it yet (S1 is behaviour-neutral: nothing loads this file but tests/fail_selftest.ks).
// ============================================================================
//  The design (catalog, GPC, software, architecture):
//   * CODE  "MPS 01" ... "SW 03": one line of the catalog = LEXICON(name, grp, tg, val, lamp, cls, modes, fix, delay, tier, lampmap, free).
//     grp = MPS OMS RCS FCS DPS SOFTWARE (the window's FILTER); tg = the TARGETS (free = any text is a target); val = the VALUES
//     (LIST of text, "" or an empty list = none); lamp = a C&W lamp key ("" = none), lampmap = target -> lamp where the lamp depends
//     on it; cls = "W" warning (class 2, red) / "C" caution (class 2, amber) / "S" software alert (class 3, SM ALERT, no lamp);
//     modes = "P" permanent only, "PT" permanent or transient, "T" transient only (the MODE rule: a failure is PERMANENT unless the
//     real crew could fix it in flight); fix = the REAL fix's name ("" = none), delay = its time in s (design numbers: no source
//     gives them, except the GPC ones, S3); tier = "A" kOS only, "C" needs the DLL, "S12" spike.
//   * HOSTS register what they can fly: flReg(code, handler) with handler(target, value, why) -> "OK" | "OK:<resolved target>"
//     | "DEFER" (tried again next tick: ops2q's lit burn) | "REFUSE: text"; flRegFix(code, healer) with healer(target, value).
//     A handler of a program that ended is never called (kmLive). flInit() at a host's start clears the handlers, not the state.
//   * flFire(code, target, value, mode, why)  = THE ENTRY: validates (known, flyable here, target, value, mode, not already failed),
//     calls the handler, adds the ACTIVE entry, lights the lamp (cwSet) or raises the SM ALERT hook, logs. Returns the text above.
//   * ROWS: flAddRow(when, t, code, target, value, mode) (MET s since launch / TIG s from the burn's ignition, EVENT / CHAIN = S10);
//     flTick(met, tig) fires the due ones (DEFER keeps it), completes the fixes. FL_MAX rows. flRand(scale, dt, rnd) = RAND.
//   * FIX: flFix(i) starts the real fix of ACTIVE entry i (refused for a PERMANENT one / one with no fix / one already under way);
//     flTick completes it after the delay: the healer runs, the entry goes, the lamp steps down.
//   * PERSISTENCE: flSave() / flLoad() on 1:/fail_state.txt (ACTIVE) and 1:/fail_rows.txt (ROWS); flReapply() calls the handlers again
//     for what the vessel does not keep (why "RESTORE").
//   * THE DLL'S LIST (coproc/Fail.cs, FailVessel.cs, KalsAddon.Fail.cs; only when ADDONS:KALS has FAILSET / FAILFIX / FAILLIST, else
//     everything here is as before): the vessel keeps the failures in its own save and a script cannot clear them. flFire / flNote
//     MIRROR each failure into it (FAILSET), flFix asks the DLL first (FAILFIX: its refusals stand) and the DLL ends the fix itself,
//     flLoad / flReset take the DLL's list as THE ACTIVE list when it has entries (the files are the fallback; entries the DLL does
//     not have yet are pushed to it, except one whose fix is already running). The hook table FL_DLL holds the three calls so a test
//     can stand in for the addon.
//   * THE PARTS (FAILBIND): right after FAILSET said OK, flDllSet asks the BINDER the host registered for the code
//     (flRegBind(code, fn), fn(target) -> LIST of part tokens "uid" / "uid:n") which parts the failure acts on and tells the DLL
//     (once: a second bind is refused), so the DLL holds exactly those parts to the failure (coproc/FailEnforce.cs). A host that
//     registers no binder, or a DLL without FAILBIND, leaves the failure kOS-only as before.
//  Names: fl* / FL_*. Needs lib_cw (lamps) and lib_kmsg (kmLive).
// ============================================================================
RUNONCEPATH("0:/lib/lib_cw.ks").

IF NOT (DEFINED FL_ROWS) {
    GLOBAL FL_ROWS IS LIST().                        // pending / done rows: LEXICON(when, t, code, tg, val, mode, done, res)
    GLOBAL FL_ACTIVE IS LIST().                      // what has happened: LEXICON(code, tg, val, mode, met, fixAt)
    GLOBAL FL_FAKE IS -1.                            // >= 0: the tests' clock (UT)
    GLOBAL FL_ALERT IS 0.                            // the SM ALERT hook: delegate(text); 0 / a dead one = lib_cw's cwAlert
    GLOBAL FL_INFIRE IS FALSE.                       // TRUE while flFire's handler runs (flNote stays out of it)
    GLOBAL FL_DLL IS LEXICON().                      // the DLL's calls: "set"(code, tg, val, mode), "fix"(code, tg, via), "list"() -> LIST(LIST(code, tg, val, mode, at, healAt, via)), "bind"(code, tg, parts) (optional); empty = not looked up yet / none
}
IF NOT (DEFINED FL_BINDR) { GLOBAL FL_BINDR IS LEXICON(). }       // code -> the host's binder: fn(target) -> LIST of the part tokens the failure acts on
// A delegate is callable only while the program run that made it is alive (kOS: "Cannot call this lock or function or delegate from
// one program run when it was declared in another"). FL_DLL / FL_BINDR / FL_ALERT live on in the GLOBALs above after their program ended
// (ops1q's run, then 'run ops2q.': flDllAdopt died on FL_DLL["list"]:CALL() at ops2q's o2qFailInit), so a dead one is dropped when this
// library loads in a new run (and flDllOn re-checks); the DATA globals (FL_ROWS / FL_ACTIVE) stay on purpose. lib_progreset clears them too.
IF NOT kmLive(FL_ALERT) { SET FL_ALERT TO 0. }
IF FL_DLL:HASKEY("set") { IF NOT kmLive(FL_DLL["set"]) { FL_DLL:CLEAR(). } }
LOCAL flDeadB IS LIST().
FOR flK IN FL_BINDR:KEYS { IF NOT kmLive(FL_BINDR[flK]) { flDeadB:ADD(flK). } }
FOR flK IN flDeadB { FL_BINDR:REMOVE(flK). }
GLOBAL FL_CAT IS LEXICON().
GLOBAL FL_HAND IS LEXICON().                         // code -> the host's handler
GLOBAL FL_HEAL IS LEXICON().                         // code -> the host's healer
GLOBAL FL_GUARD IS LEXICON().                        // code -> a delegate(target) -> "" (the fix may start) or the refusal text (RESTART after MECO)
GLOBAL FL_MAX IS 16.                                 // rows
GLOBAL FL_NOTIG IS -1000000.                         // flTick's tig when the host has no burn
GLOBAL FL_FILE IS "1:/fail_state.txt".
GLOBAL FL_ROWFILE IS "1:/fail_rows.txt".
GLOBAL FL_LOG IS "".                                 // a log path the host sets (flLog); "" = none
GLOBAL FL_GROUPS IS LIST("ALL", "MPS", "OMS", "RCS", "FCS", "DPS", "SW").   // the window's FILTER keys (SW = group SOFTWARE)
// RAND's hazard table: % per second per target (today ops1q 0.08 per SSME, ops2q 0.05 per OMS; the new types stay at 0
// until the survivability check (S9a) is in)
GLOBAL FL_HAZ IS LEXICON("MPS 01", 0.08, "OMS 01", 0.05).

FUNCTION flUt { RETURN CHOOSE FL_FAKE IF FL_FAKE >= 0 ELSE TIME:SECONDS. }

// ---- the catalog
FUNCTION flDef {
    PARAMETER code, nm, grp, tg, vl, lamp, cls, modes, fix, dly, tier.
    SET FL_CAT[code] TO LEXICON("name", nm, "grp", grp, "tg", tg, "val", vl, "lamp", lamp, "cls", cls, "modes", modes,
                                "fix", fix, "delay", dly, "tier", tier, "lampmap", LEXICON(), "free", FALSE).
}
// The RCS targets are the real Shuttle's pods (F forward, L / R the aft pods) and manifolds 1-4 (primary only: no verniers). The old FWD 1 / FWD ALL /
// AFT 1 / AFT ALL / FWD / AFT are retired from the window; the DLL (coproc/RcsMap.cs) still reads them in an old save. FL_ALIAS maps the retired names that have ONE new
// name (an old scenario row, an old fail_rows.txt) at flFire; the AFT ones have two pods and are refused as a BAD TARGET.
GLOBAL FL_RCSTG IS LIST("F ALL", "L ALL", "R ALL", "F MANIFOLD 1", "F MANIFOLD 2", "F MANIFOLD 3", "F MANIFOLD 4", "L MANIFOLD 1", "L MANIFOLD 2", "L MANIFOLD 3", "L MANIFOLD 4", "R MANIFOLD 1", "R MANIFOLD 2", "R MANIFOLD 3", "R MANIFOLD 4", "ANY").
GLOBAL FL_ALIAS IS LEXICON("RCS 01|FWD ALL", "F ALL", "RCS 01|FWD 1", "F MANIFOLD 1", "RCS 02|FWD", "F ALL", "RCS 03|FWD", "F").
// The catalog: a failure whose target is ANY picks one itself: a random one of the catalog's targets that is not already failed with this code and that the host
// accepts (flFireAny); it is logged. MPS 01 / OMS 01 / DPS 01 / DPS 02 / DPS 03 / DPS 06 resolve their own ANY in the host (the engines running, the GPCs good).
GLOBAL FL_ANYGEN IS LIST("MPS 02", "MPS 03", "OMS 02", "OMS 03", "OMS 04", "RCS 01", "RCS 02", "RCS 03", "FCS 01").
FUNCTION flRcsLamp {                                 // the lamp key of an RCS target by its pod letter
    PARAMETER t.
    IF t:STARTSWITH("L") { RETURN "LRCS". }
    IF t:STARTSWITH("R") { RETURN "RRCS". }
    RETURN "FRCS".
}
IF FL_CAT:LENGTH = 0 {
    //     code      name                   grp         targets                                       values                   lamp   cls  modes fix                         delay tier
    flDef("MPS 01", "SSME OUT",            "MPS",      LIST("L", "C", "R", "ANY"),                    LIST(),                  "MPS", "W", "P",  "",                         0,  "A").
    flDef("MPS 02", "SSME THRUST LOW",     "MPS",      LIST("L", "C", "R", "ANY"),                        LIST("60 %", "75 %"),    "MPS", "W", "P",  "",                         0,  "A").
    flDef("MPS 03", "SSME GIMBAL LOCKED",  "MPS",      LIST("L", "C", "R", "ANY"),                        LIST(),                  "",    "S", "P",  "",                         0,  "A").
    flDef("OMS 01", "OMS ENGINE OUT",      "OMS",      LIST("L", "R", "ANY"),                         LIST(),                  "",    "W", "P",  "",                         0,  "A").
    flDef("OMS 02", "OMS THRUST LOW",      "OMS",      LIST("L", "R", "ANY"),                          LIST("70 %", "85 %"),    "",    "W", "P",  "",                         0,  "A").
    flDef("OMS 03", "OMS GIMBAL LOCKED",   "OMS",      LIST("L", "R", "ANY"),                          LIST(),                  "",    "W", "P",  "",                         0,  "A").
    flDef("OMS 04", "OMS PROPELLANT LEAK", "OMS",      LIST("FU", "OX", "BOTH", "ANY"),                LIST("0.05 KG/S", "0.2 KG/S"), "OPRP", "W", "PT", "ISOLATE TANK",      5,  "C").
    flDef("RCS 01", "RCS MODULES OFF",     "RCS",      FL_RCSTG,                                      LIST(),                  "FRCS", "W", "PT", "MANIFOLD VALVES RE-OPEN", 5, "C").
    flDef("RCS 02", "RCS THRUST LOW",      "RCS",      FL_RCSTG,                                      LIST("50 %", "75 %"),    "JET", "W", "P",  "",                         0,  "C").
    flDef("RCS 03", "RCS PROPELLANT LEAK", "RCS",      LIST("F", "L", "R", "ANY"),                    LIST("1 %/MIN", "5 %/MIN"), "FRCS", "W", "PT", "MANIFOLD CLOSE",      5,  "C").
    flDef("RCS 04", "RCS SINGLE JET",      "RCS",      LIST(),                                        LIST("STUCK OFF", "STUCK ON"), "JET", "W", "PT", "MANIFOLD CLOSE", 5, "C").
    flDef("FCS 01", "FCS SURFACE FROZEN",  "FCS",      LIST("ELEVON 1", "ELEVON 2", "ELEVON 3", "ELEVON 4", "BODY FLAP", "RUDDER L", "RUDDER R", "ANY"), LIST(), "FCS", "W", "P", "", 0, "A").
    flDef("DPS 01", "GPC HARDWARE FAIL",   "DPS",      LIST("G1", "G2", "G3", "G4", "G5", "ANY"),     LIST(),                  "GPC", "W", "P",  "",                         0,  "A").
    flDef("DPS 02", "GPC TRANSIENT FAIL",  "DPS",      LIST("G1", "G2", "G3", "G4", "G5", "ANY"),     LIST(),                  "GPC", "W", "T",  "RESTART",                  65, "A").
    flDef("DPS 03", "GPC FAIL TO SYNC",    "DPS",      LIST("G1", "G2", "G3", "G4", "ANY"),           LIST(),                  "GPC", "W", "PT", "RESTART",                  65, "A").    // dropped out of the redundant set (a transient one restarts)
    flDef("DPS 06", "GPC OUTPUT BAD",      "DPS",      LIST("G1", "G2", "G3", "G4", "ANY"),           LIST(),                  "GPC", "W", "T",  "RESTART",                  65, "A").    // A 1-3 s bad-command spell on one axis, then out of the set
    flDef("DPS 04", "REDUNDANT SET SPLIT", "DPS",      LIST("2-2"),                                   LIST(),                  "GPC", "W", "T",  "PICK PAIR",                3,  "A").    // The four PASS GPCs split 2-2: the guidance holds until the crew picks the right pair (the PAIR keys) or engages the BFS; the plain FIX is guarded
    flDef("DPS 05", "PASS FAIL",           "DPS",      LIST("G1-G4"),                                 LIST(),                  "GPC", "W", "T",  "RE-IPL PASS",              20, "A").    // All four PASS GPCs fail at once: AUTO + the guidance lost, the displays dead until BFS ENGAGE; the PASS set is loaded again at the OPS 2 start (or RE-IPL PASS in orbit)    // A 1-3 s bad-command spell on one axis, then out of the set
    flDef("SW 01",  "AUTO DAP LOST",       "SOFTWARE", LIST("ASCENT", "ORBIT", "ENTRY"),              LIST(),                  "FCS", "W", "PT", "RESTART SW",               10, "A").
    flDef("SW 02",  "GUIDANCE LOST",       "SOFTWARE", LIST("ASCENT", "ENTRY", "TAEM", "A/L", "ALPHA MOD"), LIST(), "GUID", "W", "PT", "RESTART SW",              10, "A").   // Not in ORBIT BURN for v1.0 (the orbit burn's guidance loss is not drawn)
    flDef("SW 03",  "DISPLAY SOFTWARE",    "SOFTWARE", LIST("PAGE"),                                  LIST("FROZEN", "BLANK"), "",    "S", "T",  "RE-SELECT PAGE",           2,  "A").
    // the lamp by target where it depends on it
    SET FL_CAT["MPS 01"]["lampmap"] TO LEXICON().
    SET FL_CAT["OMS 01"]["lampmap"] TO LEXICON("L", "LOMS", "R", "ROMS", "ANY", "LOMS").
    SET FL_CAT["OMS 02"]["lampmap"] TO LEXICON("L", "LOMS", "R", "ROMS").
    SET FL_CAT["OMS 03"]["lampmap"] TO LEXICON("L", "LOMS", "R", "ROMS").
    FOR flRt IN FL_RCSTG { IF flRt <> "ANY" { SET FL_CAT["RCS 01"]["lampmap"][flRt] TO flRcsLamp(flRt). } }       // The lamp of the pod: FRCS / LRCS / RRCS
    SET FL_CAT["RCS 03"]["lampmap"] TO LEXICON("F", "FRCS", "L", "LRCS", "R", "RRCS").
    // a free target (any text): a named jet
    SET FL_CAT["RCS 04"]["free"] TO TRUE.
}

FUNCTION flKnown { PARAMETER code. RETURN FL_CAT:HASKEY(code). }
FUNCTION flSkipGone {                                // A saved failure / list entry names a code the catalog no longer has (PDR 01, FCS 02, SW 04, SW 05 were removed): ignored, one log line
    PARAMETER code.
    flLog("IGNORED SAVED FAILURE " + code + ": NOT IN THE CATALOG (REMOVED)").
    RETURN FALSE.
}
FUNCTION flName {                                    // "OMS 01 OMS ENGINE OUT L"
    PARAMETER code, tg.
    LOCAL s IS code.
    IF FL_CAT:HASKEY(code) { SET s TO code + " " + FL_CAT[code]["name"]. }
    IF tg <> "" { SET s TO s + " " + tg. }
    RETURN s.
}
GLOBAL FL_MSG_W IS 28.                               // A C/W message row shows this many characters (lib_cwui CWUI_MSG_W)
FUNCTION flMsg {                                     // The C/W text of (code, target): the whole name + target when it fits the row, else the name alone (never cut mid-word)
    PARAMETER code, tg.
    LOCAL s IS flName(code, tg).
    IF s:LENGTH <= FL_MSG_W { RETURN s. }
    RETURN flName(code, "").
}
FUNCTION flLampOf {                                  // the lamp key of (code, target); "" = none
    PARAMETER code, tg.
    IF NOT FL_CAT:HASKEY(code) { RETURN "". }
    LOCAL lm IS FL_CAT[code]["lampmap"].
    IF lm:HASKEY(tg) { RETURN lm[tg]. }
    RETURN FL_CAT[code]["lamp"].
}
FUNCTION flGroupOf {                                 // the FILTER key of a code ("SW" for SOFTWARE)
    PARAMETER code.
    IF NOT FL_CAT:HASKEY(code) { RETURN "". }
    LOCAL g IS FL_CAT[code]["grp"].
    IF g = "SOFTWARE" { RETURN "SW". }
    RETURN g.
}
FUNCTION flCodes {                                   // the catalog's codes under a FILTER key ("ALL" = every one), in catalog order
    PARAMETER filt IS "ALL".
    LOCAL out IS LIST().
    FOR c IN FL_CAT:KEYS { IF filt = "ALL" OR flGroupOf(c) = filt { out:ADD(c). } }
    RETURN out.
}
FUNCTION flModeOk {                                  // may this code be set to mode "P" / "T"?
    PARAMETER code, mode.
    IF NOT FL_CAT:HASKEY(code) { RETURN FALSE. }
    RETURN FL_CAT[code]["modes"]:CONTAINS(mode).
}
FUNCTION flModeDef {                                 // the default mode of a code ("P" unless it is transient only)
    PARAMETER code.
    IF NOT FL_CAT:HASKEY(code) { RETURN "P". }
    IF FL_CAT[code]["modes"] = "T" { RETURN "T". }
    RETURN "P".
}

// ---- the hosts
FUNCTION flInit { FL_HAND:CLEAR(). FL_HEAL:CLEAR(). FL_GUARD:CLEAR(). }
FUNCTION flReg { PARAMETER code, hd. SET FL_HAND[code] TO hd. }
FUNCTION flRegFix { PARAMETER code, hd. SET FL_HEAL[code] TO hd. }
FUNCTION flRegBind { PARAMETER code, fn. SET FL_BINDR[code] TO fn. }
FUNCTION flFlyable { PARAMETER code. RETURN FL_HAND:HASKEY(code) AND kmLive(FL_HAND[code]). }
FUNCTION flLog {
    PARAMETER txt.
    IF FL_LOG <> "" AND SOCK_LOG { LOG "#fail " + txt + " @" + ROUND(flUt(), 1) TO FL_LOG. }   // '#' first (a CSV log skips it), the UT last
}

// ---- the DLL's failure list (see the header): all of it a no-op without the addon's suffixes
FUNCTION flDllOn {
    IF FL_DLL:HASKEY("set") {
        IF kmLive(FL_DLL["set"]) { RETURN TRUE. }                      // looked up (or a test's stand-ins), made by a run that is alive
        FL_DLL:CLEAR().                                                // made by a program run that has ended: looked up again below
    }
    IF FL_FAKE >= 0 { RETURN FALSE. }                                  // the tests' fake clock = no game
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT (ADDONS:KALS:HASSUFFIX("FAILSET") AND ADDONS:KALS:HASSUFFIX("FAILFIX") AND ADDONS:KALS:HASSUFFIX("FAILLIST")) { RETURN FALSE. }
    SET FL_DLL["set"] TO { PARAMETER dc, dt, dv, dm. RETURN ADDONS:KALS:FAILSET(dc, dt, dv, dm). }.
    SET FL_DLL["fix"] TO { PARAMETER dc, dt, dw. RETURN ADDONS:KALS:FAILFIX(dc, dt, dw). }.
    SET FL_DLL["list"] TO { RETURN ADDONS:KALS:FAILLIST(). }.
    IF ADDONS:KALS:HASSUFFIX("FAILBIND") { SET FL_DLL["bind"] TO { PARAMETER dc, dt, dp. RETURN ADDONS:KALS:FAILBIND(dc, dt, dp). }. }
    RETURN TRUE.
}
FUNCTION flDllSet {                                  // mirror one failure into the DLL ("" = no DLL, "OK", or its refusal)
    PARAMETER code, tg, vl, mode.
    IF NOT flDllOn() { RETURN "". }
    LOCAL a IS FL_DLL["set"]:CALL(code, tg, vl, mode).
    IF a <> "OK" { flLog("DLL " + flName(code, tg) + ": " + a). }
    ELSE { flDllBind(code, tg). }
    RETURN a.
}
FUNCTION flDllBind {                                 // tell the DLL which parts the failure just injected acts on: "" = nothing to do, "OK", or the reason
    PARAMETER code, tg.
    IF NOT FL_DLL:HASKEY("bind") OR NOT FL_BINDR:HASKEY(code) { RETURN "". }
    IF NOT kmLive(FL_BINDR[code]) { RETURN "". }
    LOCAL ids IS FL_BINDR[code]:CALL(tg).
    IF ids:LENGTH = 0 { flLog("DLL BIND " + flName(code, tg) + ": NO PARTS"). RETURN "NO PARTS". }
    LOCAL txt IS "".
    FOR t IN ids { SET txt TO txt + (CHOOSE "" IF txt = "" ELSE ";") + t. }
    LOCAL a IS FL_DLL["bind"]:CALL(code, tg, txt).
    IF a <> "OK" { flLog("DLL BIND " + flName(code, tg) + ": " + a). }
    RETURN a.
}
FUNCTION flDllFix {                                  // start a real fix in the DLL ("" = no DLL, "OK", or its refusal); a failure it does not hold yet is pushed first
    PARAMETER code, tg, via.
    IF NOT flDllOn() { RETURN "". }
    LOCAL a IS FL_DLL["fix"]:CALL(code, tg, via).
    IF a = "REFUSE: NO SUCH FAILURE" {
        LOCAL i IS flActiveIdx(code, tg).
        IF i >= 0 AND flDllSet(code, tg, FL_ACTIVE[i]["val"], FL_ACTIVE[i]["mode"]) = "OK" { SET a TO FL_DLL["fix"]:CALL(code, tg, via). }
    }
    RETURN a.
}
FUNCTION flDllAdopt {                                // the DLL's list becomes the ACTIVE list when it has entries; otherwise what we hold goes into it. Returns the entries now active.
    IF NOT flDllOn() { RETURN FL_ACTIVE:LENGTH. }
    LOCAL dl IS FL_DLL["list"]:CALL().
    IF dl:LENGTH > 0 {
        FL_ACTIVE:CLEAR().
        FOR dr0 IN dl {
            IF FL_CAT:HASKEY(dr0[0]) { FL_ACTIVE:ADD(LEXICON("code", dr0[0], "tg", dr0[1], "val", dr0[2], "mode", dr0[3], "met", dr0[4], "fixAt", dr0[5])). } ELSE { flSkipGone(dr0[0]). }
        }
    } ELSE {
        FOR e IN FL_ACTIVE:COPY { IF e["fixAt"] < 0 { flDllSet(e["code"], e["tg"], e["val"], e["mode"]). } }
    }
    RETURN FL_ACTIVE:LENGTH.
}

// ---- the lamp
FUNCTION flLampCls {                                 // the highest class of an ACTIVE entry on a lamp ("" = none)
    PARAMETER lamp.
    LOCAL m IS "".
    FOR e IN FL_ACTIVE:COPY {
        IF flLampOf(e["code"], e["tg"]) = lamp AND FL_CAT[e["code"]]["cls"] <> "S" { SET m TO cwMax(m, FL_CAT[e["code"]]["cls"]). }
    }
    RETURN m.
}
FUNCTION flLamp {                                    // a failure happened: its lamp / the SM ALERT
    PARAMETER code, tg.
    LOCAL cl IS FL_CAT[code]["cls"].
    LOCAL txt IS flMsg(code, tg).
    IF cl = "S" {
        IF kmLive(FL_ALERT) { FL_ALERT:CALL(txt). } ELSE { cwAlert(txt). }
        RETURN.
    }
    LOCAL lamp IS flLampOf(code, tg).
    IF lamp <> "" { cwSet(lamp, cl, txt). }
}
FUNCTION flLampDown {                                // an entry went: the lamp steps down / goes out when nothing else holds it
    PARAMETER code, tg.
    IF FL_CAT[code]["cls"] = "S" { flSmDown(). RETURN. }   // A software alert went: the SM ALERT readout follows what still stands
    LOCAL lamp IS flLampOf(code, tg).
    IF lamp = "" { RETURN. }
    cwSet(lamp, flLampCls(lamp), flMsg(code, tg)).
}
FUNCTION flSmDown {                                  // The SM ALERT readout shows another standing software alert, else goes dark
    FOR e IN FL_ACTIVE:COPY {
        IF FL_CAT[e["code"]]["cls"] = "S" { cwSmShow(flMsg(e["code"], e["tg"])). RETURN. }
    }
    cwSmShow("").
}

// ---- THE ENTRY
FUNCTION flActiveIdx {                               // the ACTIVE entry of (code, target), -1 = none
    PARAMETER code, tg.
    LOCAL i IS 0.
    FOR e IN FL_ACTIVE:COPY { IF e["code"] = code AND e["tg"] = tg { RETURN i. } SET i TO i + 1. }
    RETURN -1.
}
FUNCTION flActiveEnt {                               // the ACTIVE entry (the LEXICON) of (code, target), LEXICON() = none; a main-loop reader reads the entry, not an index that flFixTick's REMOVE can leave stale
    PARAMETER code, tg.
    FOR e IN FL_ACTIVE:COPY { IF e["code"] = code AND e["tg"] = tg { RETURN e. } }
    RETURN LEXICON().
}
FUNCTION flFireAny {                                 // ANY = one of the catalog's targets, not yet failed with this code, that the host takes; "OK", "DEFER..." or the last refusal
    PARAMETER code, vl, mode, why.
    LOCAL cands IS LIST().
    FOR t IN FL_CAT[code]["tg"] { IF t <> "ANY" AND flActiveIdx(code, t) < 0 { cands:ADD(t). } }
    LOCAL last IS "REFUSE: NO TARGET LEFT".
    UNTIL cands:LENGTH = 0 {
        LOCAL k IS MIN(cands:LENGTH - 1, FLOOR(flRnd() * cands:LENGTH)).
        LOCAL t IS cands[k].
        cands:REMOVE(k).
        LOCAL ans IS flFire(code, t, vl, mode, why).
        IF ans = "OK" { flLog(flName(code, t) + " PICKED BY ANY"). RETURN "OK". }
        IF ans:STARTSWITH("DEFER") { RETURN ans. }
        SET last TO ans.
    }
    RETURN last.
}
FUNCTION flFire {
    PARAMETER code, tg, vl, mode, why.
    IF NOT FL_CAT:HASKEY(code) { RETURN "REFUSE: UNKNOWN CODE " + code. }
    LOCAL cat IS FL_CAT[code].
    IF NOT flFlyable(code) { RETURN "REFUSE: NOT FLYABLE HERE". }
    IF FL_ALIAS:HASKEY(code + "|" + tg) { SET tg TO FL_ALIAS[code + "|" + tg]. }
    IF tg = "ANY" AND FL_ANYGEN:CONTAINS(code) { RETURN flFireAny(code, vl, mode, why). }
    IF NOT cat["free"] {
        IF cat["tg"]:LENGTH > 0 AND NOT cat["tg"]:CONTAINS(tg) { RETURN "REFUSE: BAD TARGET " + tg. }
        IF cat["tg"]:LENGTH = 0 AND tg <> "" { RETURN "REFUSE: BAD TARGET " + tg. }
    } ELSE IF tg = "" { RETURN "REFUSE: TARGET NEEDED". }
    IF cat["val"]:LENGTH > 0 AND NOT cat["val"]:CONTAINS(vl) { RETURN "REFUSE: BAD VALUE " + vl. }
    IF cat["val"]:LENGTH = 0 AND vl <> "" { RETURN "REFUSE: BAD VALUE " + vl. }
    IF NOT flModeOk(code, mode) { RETURN "REFUSE: MODE " + mode + " NOT OFFERED". }
    IF flActiveIdx(code, tg) >= 0 { RETURN "REFUSE: ALREADY FAILED". }
    SET FL_INFIRE TO TRUE.
    LOCAL ans IS FL_HAND[code]:CALL(tg, vl, why).
    SET FL_INFIRE TO FALSE.
    LOCAL res IS tg.
    IF ans:STARTSWITH("OK:") { SET res TO ans:SUBSTRING(3, ans:LENGTH - 3). SET ans TO "OK". }
    IF ans <> "OK" { RETURN ans. }                       // DEFER / REFUSE: the host's words
    IF flActiveIdx(code, res) >= 0 { RETURN "REFUSE: ALREADY FAILED". }
    FL_ACTIVE:ADD(LEXICON("code", code, "tg", res, "val", vl, "mode", mode, "met", flUt(), "fixAt", -1)).
    flDllSet(code, res, vl, mode).
    flLamp(code, res).
    flLog(flName(code, res) + " " + mode + " " + vl + " (" + why + ")").
    RETURN "OK".
}

// A failure the HOST found itself (an engine shut down from outside, a part gone): the host's own entry has already flown it, this
// only RECORDS it (the ACTIVE entry, the lamp, the log) so the window lists it and flFire refuses a second one. Inside flFire's
// handler it does nothing (flFire records that one). "OK" = recorded, "" = nothing to do.
FUNCTION flNote {
    PARAMETER code, tg, vl, mode, why.
    IF FL_INFIRE OR NOT FL_CAT:HASKEY(code) { RETURN "". }
    IF flActiveIdx(code, tg) >= 0 { RETURN "". }
    FL_ACTIVE:ADD(LEXICON("code", code, "tg", tg, "val", vl, "mode", mode, "met", flUt(), "fixAt", -1)).
    flDllSet(code, tg, vl, mode).
    flLamp(code, tg).
    flLog(flName(code, tg) + " " + mode + " " + vl + " (" + why + ")").
    RETURN "OK".
}
// a new flight: nothing failed, nothing scheduled (ops1q at the pad); the files go too
FUNCTION flReset {
    FL_ACTIVE:CLEAR().
    FL_ROWS:CLEAR().
    IF EXISTS(FL_FILE) { DELETEPATH(FL_FILE). }
    IF EXISTS(FL_ROWFILE) { DELETEPATH(FL_ROWFILE). }
    flDllAdopt().                                    // the vessel's own list is not ours to clear: whatever the DLL holds is still failed
}

// ---- the rows
FUNCTION flAddRow {                                  // "OK" or "REFUSE: text"
    PARAMETER when, t, code, tg, vl, mode.
    IF FL_ROWS:LENGTH >= FL_MAX { RETURN "REFUSE: ROW LIST FULL". }
    IF NOT FL_CAT:HASKEY(code) { RETURN "REFUSE: UNKNOWN CODE " + code. }
    IF when <> "MET" AND when <> "TIG" AND when <> "EVENT" AND when <> "CHAIN" { RETURN "REFUSE: BAD WHEN " + when. }
    IF NOT flModeOk(code, mode) { RETURN "REFUSE: MODE " + mode + " NOT OFFERED". }
    FL_ROWS:ADD(LEXICON("when", when, "t", t, "code", code, "tg", tg, "val", vl, "mode", mode, "done", FALSE, "res", "")).
    RETURN "OK".
}
FUNCTION flPending {                                 // rows not yet fired
    LOCAL n IS 0.
    FOR rw IN FL_ROWS { IF NOT rw["done"] { SET n TO n + 1. } }
    RETURN n.
}
FUNCTION flClearRows { FL_ROWS:CLEAR(). }
FUNCTION flRowDue {                                  // MET rows by met (s since launch), TIG rows by tig (s from ignition); EVENT / CHAIN = S10
    PARAMETER rw, met, tig.
    IF rw["when"] = "MET" { RETURN met >= rw["t"]. }
    IF rw["when"] = "TIG" { RETURN tig > FL_NOTIG AND tig >= rw["t"]. }
    RETURN FALSE.
}
FUNCTION flTick {                                    // each host loop: returns the number of rows fired this call
    PARAMETER met, tig IS FL_NOTIG.
    LOCAL n IS 0.
    FOR rw IN FL_ROWS {
        IF NOT rw["done"] AND flRowDue(rw, met, tig) {
            LOCAL ans IS flFire(rw["code"], rw["tg"], rw["val"], rw["mode"], rw["when"] + " ROW").
            IF NOT ans:STARTSWITH("DEFER") {
                SET rw["done"] TO TRUE.
                SET rw["res"] TO ans.
                SET n TO n + 1.
                IF ans <> "OK" { flLog("ROW " + flName(rw["code"], rw["tg"]) + " NOT FIRED: " + ans). }
            }
        }
    }
    flFixTick().
    RETURN n.
}

// ---- the real fixes
FUNCTION flFixName {                                 // the fix hint of ACTIVE entry i ("" = none: a permanent failure, or none in the catalog)
    PARAMETER i.
    IF i < 0 OR i >= FL_ACTIVE:LENGTH { RETURN "". }
    LOCAL e IS FL_ACTIVE[i].
    IF e["mode"] <> "T" { RETURN "". }
    RETURN FL_CAT[e["code"]]["fix"].
}
FUNCTION flFixGuard {                                // Why the real fix of ACTIVE entry i may not start NOW (the host's rule: DPS 05's re-IPL only in orbit, a GPC RESTART only after MECO); "" = it may
    PARAMETER i.
    IF i < 0 OR i >= FL_ACTIVE:LENGTH { RETURN "". }
    LOCAL e IS FL_ACTIVE[i].
    IF FL_GUARD:HASKEY(e["code"]) AND kmLive(FL_GUARD[e["code"]]) { RETURN FL_GUARD[e["code"]]:CALL(e["tg"]). }
    RETURN "".
}
FUNCTION flFixLeft {                                 // whole seconds left on entry i's fix (0 = none under way)
    PARAMETER i.
    IF i < 0 OR i >= FL_ACTIVE:LENGTH { RETURN 0. }
    IF FL_ACTIVE[i]["fixAt"] < 0 { RETURN 0. }
    RETURN MAX(0, ROUND(FL_ACTIVE[i]["fixAt"] - flUt())).
}
FUNCTION flFixSay {                                  // A fix's own line on the host's MSG line, level I: "<code> <target>: <fix> IN PROGRESS, nn S" / "... DONE" (a flight event, like the C&W lines; the window's own answers stay in the window)
    PARAMETER txt.
    kmSay(txt, "I").
}
FUNCTION flFix {                                     // start the real fix of ACTIVE entry i: "OK" or "REFUSE: text"
    PARAMETER i.
    IF i < 0 OR i >= FL_ACTIVE:LENGTH { RETURN "REFUSE: NO SUCH FAILURE". }
    LOCAL e IS FL_ACTIVE[i].
    IF flFixName(i) = "" { RETURN "REFUSE: NO FIX". }
    IF e["fixAt"] >= 0 { RETURN "REFUSE: FIX UNDER WAY". }
    LOCAL gr IS flFixGuard(i).
    IF gr <> "" { RETURN "REFUSE: " + gr. }
    LOCAL dr IS flDllFix(e["code"], e["tg"], flFixName(i)).
    IF dr <> "" AND dr <> "OK" { RETURN dr. }
    SET e["fixAt"] TO flUt() + FL_CAT[e["code"]]["delay"].
    flLog("FIX " + flFixName(i) + " " + flName(e["code"], e["tg"]) + " (" + FL_CAT[e["code"]]["delay"] + " S)").
    flFixSay(e["code"] + " " + e["tg"] + ": " + flFixName(i) + " IN PROGRESS, " + FL_CAT[e["code"]]["delay"] + " S").
    RETURN "OK".
}
FUNCTION flRemove {                                  // an entry repaired by something other than flFix's timer (a GPC swapped for the spare): it goes, the lamp steps down
    PARAMETER i, why.
    IF i < 0 OR i >= FL_ACTIVE:LENGTH { RETURN. }
    LOCAL e IS FL_ACTIVE[i].
    FL_ACTIVE:REMOVE(i).
    flLampDown(e["code"], e["tg"]).
    flLog(why + " " + flName(e["code"], e["tg"])).
}
FUNCTION flFixTick {                                 // complete the fixes whose delay is over
    LOCAL ut IS flUt().
    LOCAL i IS FL_ACTIVE:LENGTH - 1.
    UNTIL i < 0 {
        LOCAL e IS FL_ACTIVE[i].
        IF e["fixAt"] >= 0 AND ut >= e["fixAt"] {
            IF FL_HEAL:HASKEY(e["code"]) AND kmLive(FL_HEAL[e["code"]]) { FL_HEAL[e["code"]]:CALL(e["tg"], e["val"]). }
            FL_ACTIVE:REMOVE(i).
            flLampDown(e["code"], e["tg"]).
            flLog("FIXED " + flName(e["code"], e["tg"])).
            flFixSay(e["code"] + " " + e["tg"] + ": " + (CHOOSE FL_CAT[e["code"]]["fix"] IF FL_CAT[e["code"]]["fix"] <> "" ELSE "FIX") + " DONE").
        }
        SET i TO i - 1.
    }
}

// ---- RAND: one draw per call (dt = s since the last call); rnd = a delegate () -> 0..1 (RANDOM()); returns the failure fired ("" = none)
FUNCTION flRnd { RETURN RANDOM(). }
FUNCTION flRand {
    PARAMETER scale, dt, rnd IS flRnd@.
    IF FL_SIMPROG <> "" AND flSimOn() {             // The DLL's table (coproc/SimSup.cs): every flyable code, NO floors
        RETURN flSimPick(ADDONS:KALS:SIMRAND(scale, dt, FL_SIMPH), "RAND").
    }
    FOR code IN FL_HAZ:KEYS {
        IF flFlyable(code) {
            FOR tg IN FL_CAT[code]["tg"] {
                IF tg <> "ANY" AND tg <> "ALPHA MOD" AND flActiveIdx(code, tg) < 0 {      // ALPHA MOD is a scenario-only target (the DLL's ScenTargets)
                    IF rnd:CALL() < FL_HAZ[code] / 100 * scale * dt {
                        IF flFire(code, tg, "", "P", "RAND") = "OK" { RETURN flName(code, tg). }
                    }
                }
            }
        }
    }
    RETURN "".
}

// ----SIMSUP MODE + RAND in the DLL (coproc/SimSup.cs: the planner, the survivability floors, RAND's table for every
// flyable code). INERT until a host calls flSimHost:
// before that flRand keeps FL_HAZ and nothing here runs. Without the DLL's SIMTICK every call is a no-op.
//   flSimHost(prog)              at the host's start, after its flReg calls: the program ("OPS1" / "OPS2" / "OPS3" / "OPS6") + its flyable codes
//   flSimPhase(ph)               the guidance phase now ("ASCENT" / "ORBIT" / "ENTRY" / "TAEM" / "A/L"): SW 02's target
//   flSimPoint(name, edgeUt)     slPoint: a named decision point (SimSup.cs Points) whose edge is at edgeUt; the counter
//   flSimTick(tig, randOk, dt)   each host tick while latched: the due SimSup pick fired with why "SIMSUP" (its name, or "")
//   flSimCheck(code, tg, mode)   "" or "RTN IMPSBLE: <floor>" for a player's own row (the window's warning)
GLOBAL FL_SIMPROG IS "".
GLOBAL FL_SIMPH IS "".
GLOBAL FL_SIMVRN IS -1.                  // -1 = not asked, 1 = the DLL has SIMVR, 0 = an older DLL (the entry clock then runs on time)
// ForceAbort: "" = the DLL's drawn outcome; else "ORBIT" / "RTLS" / "1EO TAL" / "2EO TAL" / "AOA" / "2EO GREEN" / "2EO BLUE" / "3EO BLUE" / "3EO GREEN" / "3EO TAL" / "3EO ATO" / "3EO RTLS" / "3EO SPLITS" / "2EO SPLITS" / "RTLS 2EO GREEN" / "RTLS 2EO BLUE" (applied at ENGAGE by fuiSimEngage)
GLOBAL FL_SIMFORCE IS "".
// The failure codes SimSup never draws (';'-joined, "FCS 01"): a clean-flight ticket sets it before ENGAGE; "" = every code (the DLL's own guards still apply: NoPilot's abort-arrival frozen surface)
GLOBAL FL_SIMNOCODE IS "".
FUNCTION flSimNoCode {
    PARAMETER lst.
    IF NOT flSimOn() { RETURN "REFUSE: NO DLL". }
    IF NOT ADDONS:KALS:HASSUFFIX("SIMNOCODE") { RETURN "REFUSE: DLL TOO OLD". }
    RETURN ADDONS:KALS:SIMNOCODE(lst).
}
FUNCTION flSimForce {
    PARAMETER nm.
    IF NOT flSimOn() { RETURN "REFUSE: NO DLL". }
    IF NOT ADDONS:KALS:HASSUFFIX("SIMFORCE") { RETURN "REFUSE: DLL TOO OLD". }
    RETURN ADDONS:KALS:SIMFORCE(nm).
}
FUNCTION flSimOn {
    IF FL_FAKE >= 0 OR NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("SIMTICK").
}
FUNCTION flSimHost {
    PARAMETER prog.
    IF NOT flSimOn() { RETURN "". }
    LOCAL cs IS "".
    FOR c IN FL_HAND:KEYS { IF flFlyable(c) { SET cs TO cs + (CHOOSE "" IF cs = "" ELSE ";") + c. } }
    SET FL_SIMPROG TO prog.
    RETURN ADDONS:KALS:SIMHOST(prog, cs).
}
FUNCTION flSimPhase { PARAMETER ph. SET FL_SIMPH TO ph. }
FUNCTION flSimVr {                           // The relative velocity (m/s) for the DLL's ENTRY / TAEM pick clock; a no-op on an older DLL
    PARAMETER vr.
    IF FL_SIMPROG = "" OR NOT flSimOn() { RETURN. }
    IF FL_SIMVRN < 0 { SET FL_SIMVRN TO CHOOSE 1 IF ADDONS:KALS:HASSUFFIX("SIMVR") ELSE 0. }
    IF FL_SIMVRN > 0 { ADDONS:KALS:SIMVR(vr). }
}
FUNCTION flSimPick {                                 // fire a DLL pick "code|target|value|mode": its name when it fired, else ""
    PARAMETER pk, why.
    IF pk = "" { RETURN "". }
    LOCAL f IS pk:SPLIT("|").
    IF f:LENGTH <> 4 { RETURN "". }
    LOCAL fr IS flFire(f[0], f[1], f[2], f[3], why).
    IF why = "SIMSUP" { ADDONS:KALS:SIMRES(f[0], f[1], fr). }
    IF fr:STARTSWITH("OK") { RETURN flName(f[0], f[1]). }
    RETURN "".
}
FUNCTION flSimTick {
    PARAMETER tig, randOk, dt.
    IF FL_SIMPROG = "" OR NOT flSimOn() { RETURN "". }
    RETURN flSimPick(ADDONS:KALS:SIMTICK(tig, FL_SIMPH, randOk, dt), "SIMSUP").
}
FUNCTION flSimPoint {
    PARAMETER nm, edgeUt.
    IF FL_SIMPROG = "" OR NOT flSimOn() { RETURN 0. }
    RETURN ADDONS:KALS:SIMPOINT(nm, edgeUt, FL_SIMPH).
}
FUNCTION flSimCheck {
    PARAMETER code, tg, mode.
    IF NOT flSimOn() { RETURN "". }
    RETURN ADDONS:KALS:SIMCHECK(code, tg, mode).
}

// ---- persistence (kOS files on the vessel's own volume; S6's DLL list replaces the source)
FUNCTION flSave {
    IF EXISTS(FL_FILE) { DELETEPATH(FL_FILE). }
    FOR e IN FL_ACTIVE:COPY { LOG e["code"] + "," + e["tg"] + "," + e["val"] + "," + e["mode"] + "," + e["met"] + "," + e["fixAt"] TO FL_FILE. }
    IF EXISTS(FL_ROWFILE) { DELETEPATH(FL_ROWFILE). }
    FOR rw IN FL_ROWS {
        LOG rw["when"] + "," + rw["t"] + "," + rw["code"] + "," + rw["tg"] + "," + rw["val"] + "," + rw["mode"] + "," + (CHOOSE 1 IF rw["done"] ELSE 0) TO FL_ROWFILE.
    }
}
FUNCTION flLoad {                                    // the files into the state (replaces it); returns the number of active entries read
    FL_ACTIVE:CLEAR().
    FL_ROWS:CLEAR().
    IF EXISTS(FL_FILE) {
        FOR ln0 IN OPEN(FL_FILE):READALL:STRING:SPLIT(CHAR(10)) {
            LOCAL f IS ln0:TRIM:SPLIT(",").
            IF f:LENGTH >= 6 AND FL_CAT:HASKEY(f[0]) {
                FL_ACTIVE:ADD(LEXICON("code", f[0], "tg", f[1], "val", f[2], "mode", f[3], "met", f[4]:TONUMBER(0), "fixAt", f[5]:TONUMBER(-1))).
            } ELSE IF f:LENGTH >= 6 { flSkipGone(f[0]). }
        }
    }
    IF EXISTS(FL_ROWFILE) {
        FOR ln1 IN OPEN(FL_ROWFILE):READALL:STRING:SPLIT(CHAR(10)) {
            LOCAL g IS ln1:TRIM:SPLIT(",").
            IF g:LENGTH >= 7 AND FL_CAT:HASKEY(g[2]) AND FL_ROWS:LENGTH < FL_MAX {
                FL_ROWS:ADD(LEXICON("when", g[0], "t", g[1]:TONUMBER(0), "code", g[2], "tg", g[3], "val", g[4], "mode", g[5], "done", g[6] = "1", "res", "")).
            } ELSE IF g:LENGTH >= 7 AND NOT FL_CAT:HASKEY(g[2]) { flSkipGone(g[2]). }
        }
    }
    RETURN flDllAdopt().
}
FUNCTION flReapply {                                 // after a re-RUN / the next program: the handlers act again (why RESTORE) on what is active; lamps relit
    LOCAL n IS 0.
    FOR e IN FL_ACTIVE:COPY {
        IF flFlyable(e["code"]) {
            LOCAL ans IS FL_HAND[e["code"]]:CALL(e["tg"], e["val"], "RESTORE").
            IF ans:STARTSWITH("OK") { SET n TO n + 1. }
        }
        flLamp(e["code"], e["tg"]).
    }
    RETURN n.
}
