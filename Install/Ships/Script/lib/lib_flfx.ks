@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_FLFX.KS  --  what the FAILURES DO to the vehicle, kOS side: the handlers the hosts register with lib_fail.ks (flReg)
//  for the hardware types, and the re-assertion that keeps them true while the programs write the same parts. The state is lib_fail.ks's
//  (the ACTIVE list); this file holds only the EFFECT tables (which engine is capped, which gimbal is locked, which RCS parts are off,
//  which surface is frozen) and applies them. No GUI. The DLL layer sits UNDER this (the list and the parts: coproc/FailEnforce.cs): each
//  handler's failure is bound to its parts (the binders below, lib_fail's flRegBind) and the DLL holds them every physics tick; until
//  the DLL is installed every failure here is kOS-only, a script / a program that writes the same field after us wins until flfxTick
//  writes it back (FLFX_DT, 0.5 s).
//  THE TYPES , where each is flown:
//    MPS 02 SSME THRUST LOW  L C R   60 % / 75 %   ops1q    the engine's THRUSTLIMIT capped (the SSMEs' thrust limiter was not used by any host)
//    MPS 03 SSME GIMBAL LOCKED L C R               ops1q    GIMBAL:LOCK held TRUE (the lock a failed engine already gets: asc_fail)
//    OMS 02 OMS THRUST LOW  L R      70 % / 85 %   ops2q    THRUSTLIMIT capped (the burn's thrust / duration read POSSIBLETHRUST: they follow)
//    OMS 03 OMS GIMBAL LOCKED L R                  ops2q    GIMBAL:LOCK held TRUE (ops2q's o2qUnlockGimbals skips it); ops3q lifts it: the entry's
//                                                           stick reads one OMS gimbal and must see it move (lib_dap / lib_grdap unlock it)
//    RCS 01 RCS MODULES OFF  F ALL / L ALL / R ALL / <pod> MANIFOLD 1-4   ops2q, ops3q   the pod's / manifold's jets taken out of fire BY THE DLL
//                                                           (coproc/RcsJets.cs, RcsMap.cs: the real Shuttle pods F / L / R and manifolds 1-4); PT: the real fix
//                                                           (MANIFOLD VALVES RE-OPEN, 5 s) ends the DLL's entry and the jets are back
//    RCS 02 RCS THRUST LOW  the same targets  50 % / 75 %   ops2q, ops3q   the same jets let fire on a duty of the ticks (the DLL)
//    RCS 04 RCS SINGLE JET  a jet name F3U / L2D / R4R  STUCK OFF / STUCK ON   the DLL (the LEAK value is gone: RCS 03 is the RCS leak)
//    FCS 01 FCS SURFACE FROZEN  ELEVON 1-4 / BODY FLAP / RUDDER L / RUDDER R   ops3q   the surface's angle held where it was and its axes ignored;
//                                                           lib_far's surfSetAng / surfSetLock (and the stock writes in lib_dap / lib_vehicle /
//                                                           lib_grdap / ops3q) skip a frozen surface (SURF_FROZEN), so the DAP's writes have no effect
//  The RCS codes have NO kOS side any more (the old SHIP:RCS module table is gone); the handlers below only accept, and refuse when the DLL is not there.
//  NOT built here (PDR 01, FCS 02, SW 04, SW 05 are not in the catalog at all): SW 01 / 02 / 03 (the DAP /
//  guidance / page refusals are in the programs' own AUTO paths: S4b), the leaks and single jets (C, the DLL).
//  Numbering of the surfaces: ELEVON 1..4 = the four elevons from the orbiter's LEFT to its RIGHT (by the starboard coordinate, ascending);
//  RUDDER L / R = the two halves of the split rudder, left half first (the same order).
//  THE HOST: flInit() + flReg(...) as before, then flfxRegMps(resolver) (ops1q) / flfxRegOms(resolver) (ops2q) / flfxRegRcs() / flfxRegFcs(),
//  then fuiBoot, then flfxReapply() (the failures of an earlier program act again: why RESTORE). lib_failui's fuiSched calls flfxTick().
//  A resolver is a delegate(target) -> the engine of that position that is there to fail, or "" (out, not lit, not on the ship).
//  Names flfx* / FLFX_*. Needs lib_fail.ks (lib_far.ks is used only where it is loaded: FCS).
// ============================================================================
RUNONCEPATH("0:/lib/lib_fail.ks").

GLOBAL FLFX_DT IS 0.5.                       // s (game time) between the re-assertions
GLOBAL FLFX_SWMASK IS 0.               // The SW 01 / SW 02 bits the C# twins read (flfxSwPub; the bits are listed there)
GLOBAL FLFX_CODES IS LIST("MPS 02", "MPS 03", "OMS 02", "OMS 03", "FCS 01", "SW 02", "SW 03").   // flfxReapply's codes (the others re-apply themselves)
IF NOT (DEFINED FLFX_SWPG) {               // SW 03 (DISPLAY SOFTWARE)
    GLOBAL FLFX_SWPG IS LEXICON().          // the display (GNC / SM / TOP ...) -> "FROZEN" / "BLANK" while SW 03 holds it
    GLOBAL FLFX_GPH IS LIST().              // The guidance phases the host flies for SW 02 (flfxRegGuid); empty = SW 02 refused
    GLOBAL DAP_GD_LOST_S IS 3.              // SW 02 GUIDANCE LOST: the DAP's AUTO axes fall back to CSS this many seconds after the loss
    GLOBAL FLFX_PH IS "".                   // The guidance phase the host is flying now ("ENTRY" / "TAEM" / "A/L"; landRun sets it), for the DAP's SW 02 test
    GLOBAL FLFX_SWPAGE IS 0.                // the host's pageNow delegate() -> the display on screen now ("" = none)
    GLOBAL FLFX_SWPROG IS "".               // the host's scope: "ASCENT" / "ORBIT" / "ENTRY"
}
IF NOT (DEFINED FLFX_ECAP) {
    GLOBAL FLFX_ECAP IS LEXICON().           // engine part uid -> thrust limit %
    GLOBAL FLFX_EGLK IS LEXICON().           // engine part uid -> TRUE: its gimbal is held locked
    GLOBAL FLFX_FMOD IS LEXICON().           // frozen surface uid -> LIST(module, field, held value)
    GLOBAL FLFX_RES IS LEXICON().            // "MPS" / "OMS" -> the host's resolver
    GLOBAL FLFX_NEXT IS 0.                   // the UT of the next flfxTick pass
}

// SW 01 / SW 02 force the DAP's axes to CSS and RESTART SW heals the
// failure, but the CSS toggles STAY pressed until the crew re-selects AUTO. The automated test flight has no crew, so after its RESTART SW the orbiter flew on in CSS unflown
// (the dive into the ground in the A/L, the unflown GRTLS entry). While the automated test flight has the vessel (flfxNoPilot) a heal of SW 01 / SW 02 sets FLFX_AUTOWANT and
// flfxTick, once no SW 01 / SW 02 stands, calls every host's delegate (flfxRegAuto: the host's DAP back to AUTO, as the crew's two AUTO presses would).
IF NOT (DEFINED FLFX_AUTOS) {
    GLOBAL FLFX_AUTOS IS LEXICON().          // host name -> delegate(): the crew re-selects AUTO on that host's DAP (flfxRegAuto; progReset clears it)
    GLOBAL FLFX_AUTOWANT IS FALSE.           // a RESTART SW healed SW 01 / SW 02 while the automated test flight runs: AUTO goes back as soon as nothing holds the DAP
    GLOBAL FLFX_NOPILOT IS -1.               // -1 = ask the DLL (SAILON); 0 / 1 = forced (the offline tests)
    GLOBAL FLFX_PHOLD IS FALSE.              // A DPS 04 / DPS 05 hold stood at the last flfxTick pass (its end under the test flight = the crew re-selects AUTO)
}

// ---- small things
FUNCTION flfxNum {                           // "60 %" -> 60 (the value of a catalog row); 100 for anything else
    PARAMETER vl.
    LOCAL w IS vl:TRIM:SPLIT(" ")[0].
    RETURN w:TONUMBER(100).
}
FUNCTION flfxUid { PARAMETER p. RETURN "" + p:UID. }   // an engine / a part / an RCS part
FUNCTION flfxThere { PARAMETER x. RETURN NOT x:ISTYPE("String"). }   // a resolver's / finder's answer is an object unless it is ""
FUNCTION flfxGlk {                           // is this engine's gimbal held locked by a failure?
    PARAMETER en.
    IF FLFX_EGLK:LENGTH = 0 { RETURN FALSE. }
    RETURN FLFX_EGLK:HASKEY(flfxUid(en)).
}
FUNCTION flfxEngCap {                        // the thrust limit % a failure holds this engine at (100 = none)
    PARAMETER en.
    IF FLFX_ECAP:LENGTH = 0 { RETURN 100. }
    LOCAL u IS flfxUid(en).
    IF FLFX_ECAP:HASKEY(u) { RETURN FLFX_ECAP[u]. }
    RETURN 100.
}
// ---- the engines (MPS / OMS): thrust low, gimbal locked
FUNCTION flfxEngSet {                        // one engine: the cap / the lock applied now (and kept by flfxTick)
    PARAMETER en, kind, pct.
    LOCAL u IS flfxUid(en).
    IF kind = "CAP" {
        SET FLFX_ECAP[u] TO pct.
        IF en:THRUSTLIMIT > pct { SET en:THRUSTLIMIT TO pct. }
    } ELSE {
        SET FLFX_EGLK[u] TO TRUE.
        IF en:HASGIMBAL { IF NOT en:GIMBAL:LOCK { SET en:GIMBAL:LOCK TO TRUE. } }
    }
}
FUNCTION flfxEngH {                          // the engines' handler body: (resolver key, target, kind, pct)
    PARAMETER rk, tg, kind, pct.
    IF NOT FLFX_RES:HASKEY(rk) { RETURN "REFUSE: NO " + rk + " HERE". }
    LOCAL en IS FLFX_RES[rk]:CALL(tg).
    IF NOT flfxThere(en) { RETURN "REFUSE: " + rk + " " + tg + " NOT RUNNING". }
    IF kind = "LOCK" AND NOT en:HASGIMBAL { RETURN "REFUSE: " + rk + " " + tg + " HAS NO GIMBAL". }
    flfxEngSet(en, kind, pct).
    RETURN "OK".
}
FUNCTION flfxMpsLow { PARAMETER tg, vl, why. RETURN flfxEngH("MPS", tg, "CAP", flfxNum(vl)). }
FUNCTION flfxMpsLock { PARAMETER tg, vl, why. RETURN flfxEngH("MPS", tg, "LOCK", 0). }
FUNCTION flfxOmsLow { PARAMETER tg, vl, why. RETURN flfxEngH("OMS", tg, "CAP", flfxNum(vl)). }
FUNCTION flfxOmsLock { PARAMETER tg, vl, why. RETURN flfxEngH("OMS", tg, "LOCK", 0). }
FUNCTION flfxDllHold {                       // OMS 04 / RCS 03 / RCS 04: the DLL names the parts and holds them (coproc/FailEnforce.cs SelfBind); this only accepts, so the code is flyable here
    PARAMETER tg, vl, why.
    RETURN "OK".
}
FUNCTION flfxRegMps {                        // ops1q: the SSME resolver, then MPS 02 / MPS 03 flyable; the binder (target -> LIST of its engine's part UID,
    PARAMETER resolver, binder IS "".        // answering even for an engine that is out: the DLL holds MPS 01 / 02 / 03 to that part)
    SET FLFX_RES["MPS"] TO resolver.
    flReg("MPS 02", flfxMpsLow@).
    flReg("MPS 03", flfxMpsLock@).
    IF NOT binder:ISTYPE("String") { FOR c IN LIST("MPS 01", "MPS 02", "MPS 03") { flRegBind(c, binder). } }
}
FUNCTION flfxRegOms {                        // ops2q: the OMS resolver, then OMS 02 / OMS 03 flyable; the binder as flfxRegMps's (OMS 01 / 02 / 03)
    PARAMETER resolver, binder IS "".
    SET FLFX_RES["OMS"] TO resolver.
    flReg("OMS 02", flfxOmsLow@).
    flReg("OMS 03", flfxOmsLock@).
    flReg("OMS 04", flfxDllHold@).           // OMS PROPELLANT LEAK (the DLL drains the tank parts; the fix ISOLATE TANK is the catalog's)
    IF NOT binder:ISTYPE("String") { FOR c IN LIST("OMS 01", "OMS 02", "OMS 03") { flRegBind(c, binder). } }
}

// ---- the RCS: RCS 01 / 02 / 04 are the DLL's (coproc/FailEnforce.cs RcsPass): it holds the real pods' / manifolds' / jets' state itself, from the target text, and ends
// the failure with the fix's timer. kOS only accepts the failure here (and refuses a jet name that is not one). A jet name = pod F / L / R + manifold 1-4 + firing direction F A U D L R.
FUNCTION flfxJetName {                       // F3U / L2D / R4R (a 5th jet of a direction in a pod gets a letter: L1UB)
    PARAMETER t.
    LOCAL u IS t:TOUPPER.
    IF u:LENGTH < 3 OR u:LENGTH > 4 { RETURN FALSE. }
    IF NOT "FLR":CONTAINS(u:SUBSTRING(0, 1)) { RETURN FALSE. }
    IF NOT "1234":CONTAINS(u:SUBSTRING(1, 1)) { RETURN FALSE. }
    IF NOT "FAUDLR":CONTAINS(u:SUBSTRING(2, 1)) { RETURN FALSE. }
    IF u:LENGTH = 4 { IF NOT "BCDEFGHIJKLMNOPQRSTUVWXYZ":CONTAINS(u:SUBSTRING(3, 1)) { RETURN FALSE. } }
    RETURN TRUE.
}
FUNCTION flfxRcsDll {                        // RCS 01 / 02: the DLL holds them
    PARAMETER tg, vl, why.
    IF NOT flDllOn() { RETURN "REFUSE: NEEDS THE DLL". }
    RETURN "OK".
}
FUNCTION flfxRcsJet {                        // RCS 04: a real jet name, the DLL holds it
    PARAMETER tg, vl, why.
    IF NOT flfxJetName(tg) { RETURN "REFUSE: BAD JET NAME " + tg + " (F1U .. R4R)". }
    RETURN flfxRcsDll(tg, vl, why).
}
FUNCTION flfxRegRcs {                        // ops2q / ops3q / ops6q: RCS 01, 02, 03 and 04 flyable
    flReg("RCS 01", flfxRcsDll@).
    flReg("RCS 02", flfxRcsDll@).
    flReg("RCS 03", flfxDllHold@).           // RCS PROPELLANT LEAK: the DLL names the parts and drains them (no binder)
    flReg("RCS 04", flfxRcsJet@).
}

// ---- the control surfaces (FCS 01 frozen); needs lib_far.ks (SURF_MN, SURF_FROZEN, surfHasAng ...), loaded in ops3q
FUNCTION flfxSurfs {                         // the surfaces of a target: LIST(module, ...) ELEVON n / BODY FLAP / RUDDER L / R
    PARAMETER tg.
    LOCAL kind IS CHOOSE "bodyflap" IF tg = "BODY FLAP" ELSE (CHOOSE "elevon" IF tg:STARTSWITH("ELEVON") ELSE "rudder").
    LOCAL ms IS LIST().
    LOCAL ks IS LIST().
    LOCAL fv IS SHIP:FACING:STARVECTOR.
    FOR m IN SHIP:MODULESNAMED(SURF_MN) {
        IF m:PART:NAME:TOLOWER:CONTAINS(kind) {
            modReg(m, CHOOSE ms:LENGTH IF kind = "rudder" ELSE 0).       // The 2nd rudder half is its own key (one part, two modules)
            LOCAL x IS (m:PART:POSITION - SHIP:POSITION) * fv.
            LOCAL i IS 0.
            UNTIL i >= ks:LENGTH OR ks[i] > x { SET i TO i + 1. }       // ascending by the starboard coordinate: left first
            ks:INSERT(i, x).
            ms:INSERT(i, m).
        }
    }
    RETURN ms.
}
FUNCTION flfxSurfPick {                      // the one module of tg, or "" when the ship has none
    PARAMETER tg.
    LOCAL ms IS flfxSurfs(tg).
    IF tg = "BODY FLAP" { RETURN CHOOSE ms[0] IF ms:LENGTH > 0 ELSE "". }
    IF tg:STARTSWITH("ELEVON") {
        LOCAL n IS tg:SUBSTRING(7, 1):TONUMBER(0).
        IF n < 1 OR n > ms:LENGTH { RETURN "". }
        RETURN ms[n - 1].
    }
    LOCAL n2 IS CHOOSE 0 IF tg = "RUDDER L" ELSE 1.
    IF n2 >= ms:LENGTH { RETURN "". }
    RETURN ms[n2].
}
FUNCTION flfxFreeze {                        // FCS 01's handler: the surface held where it is, its axes ignored
    PARAMETER tg, vl, why.
    IF NOT (DEFINED SURF_FROZEN) { RETURN "REFUSE: NO SURFACE LIBRARY". }
    LOCAL m IS flfxSurfPick(tg).
    IF NOT flfxThere(m) { RETURN "REFUSE: " + tg + " NOT FOUND". }
    LOCAL u IS modKey(m).                    // The MODULE's key (a rudder half's own), not its part's: one half frozen leaves the other free
    IF NOT FLFX_FMOD:HASKEY(u) {
        LOCAL fld IS CHOOSE "flp/splr dflct" IF FAR_ON ELSE "deploy angle".
        LOCAL held IS 0.
        IF m:HASFIELD(fld) { SET held TO m:GETFIELD(fld). }
        LOCAL dep IS TRUE.                    // Its deploy state too (stock): un-deployed it stays un-deployed (the stored angle 25 / 35 never acts)
        IF NOT FAR_ON { IF m:HASFIELD("deploy") { SET dep TO m:GETFIELD("deploy"). } }
        SET FLFX_FMOD[u] TO LIST(m, fld, held, dep).
        SET SURF_FROZEN[u] TO TRUE.
    }
    flfxSurfApply().
    RETURN "OK".
}
FUNCTION flfxRebind {                       // After a hold, a frozen surface whose module is not live (its part left the
                                             // ship, or a splash rebuilt the vessel) is re-bound to the fresh module of the same part, or dropped
    IF TIME:SECONDS < VES_HOLD { RETURN. }   // the vessel is being rebuilt: no module is read
    FOR u IN FLFX_FMOD:KEYS {
        LOCAL f IS FLFX_FMOD[u].
        IF NOT modLive(f[0]) {
            LOCAL found IS FALSE.
            LOCAL nm IS f[0].
            LOCAL nrk IS 0.
            LOCAL cnt IS LEXICON().
            FOR m IN SHIP:MODULESNAMED(SURF_MN) {
                LOCAL pu IS "" + m:PART:UID.
                LOCAL rk IS CHOOSE cnt[pu] IF cnt:HASKEY(pu) ELSE 0.         // Its rank among the part's surface modules (the key's #rank)
                SET cnt[pu] TO rk + 1.
                IF NOT found AND (CHOOSE pu IF rk = 0 ELSE pu + "#" + rk) = u { SET nm TO m. SET nrk TO rk. SET found TO TRUE. }
            }
            IF found {
                modReg(nm, nrk).
                LOCAL nf IS LIST(nm, f[1], f[2]).
                IF f:LENGTH > 3 { nf:ADD(f[3]). }
                SET FLFX_FMOD[u] TO nf.
            } ELSE {
                FLFX_FMOD:REMOVE(u).
                IF SURF_FROZEN:HASKEY(u) { SURF_FROZEN:REMOVE(u). }
            }
        }
    }
}
FUNCTION flfxSurfApply {                     // the frozen surfaces held (flfxTick's)
    IF NOT (DEFINED SURF_FROZEN) { RETURN. }
    flfxRebind().
    FOR u IN FLFX_FMOD:KEYS {
        LOCAL f IS FLFX_FMOD[u].
        IF modLive(f[0]) { IF f[0]:HASFIELD(f[1]) { IF ABS(f[0]:GETFIELD(f[1]) - f[2]) > 0.05 { f[0]:SETFIELD(f[1], f[2]). } } }
        IF f:LENGTH > 3 AND NOT FAR_ON {          // The deploy state held too (AG3 / a host's deploy would swing a half to its stored angle)
            IF modLive(f[0]) { IF f[0]:HASFIELD("deploy") { IF f[0]:GETFIELD("deploy") <> f[3] { f[0]:SETFIELD("deploy", f[3]). } } }
        }
        FOR ax IN LIST("pitch", "yaw", "roll") { surfSetLock(f[0], ax, TRUE). }
    }
}
FUNCTION flfxBindFcs {                       // FCS 01's binder: the frozen surface's part; a rudder half = "uid:n" (the DLL holds that one module, not the part's two)
    PARAMETER tg.
    LOCAL m IS flfxSurfPick(tg).
    IF NOT flfxThere(m) { RETURN LIST(). }
    IF tg:STARTSWITH("RUDDER") { RETURN LIST("" + m:PART:UID + ":" + (CHOOSE 0 IF tg = "RUDDER L" ELSE 1)). }
    RETURN LIST("" + m:PART:UID).
}
FUNCTION flfxRegFcs {
    flReg("FCS 01", flfxFreeze@).
    flRegBind("FCS 01", flfxBindFcs@).
}

// ---- the loop and the restart
FUNCTION flfxTick {                          // lib_failui's fuiSched: the effects written back every FLFX_DT s
    IF flUt() < FLFX_NEXT { RETURN. }
    SET FLFX_NEXT TO flUt() + FLFX_DT.
    flfxSwPub().
    LOCAL phNow IS flfxPassHold().          // DPS 04 (the pair picked / the BFS engaged) or DPS 05 (BFS engaged) just ended its hold: the crew re-selects AUTO (here, for the test flight)
    IF FLFX_PHOLD AND NOT phNow { flfxAutoWant(). }
    SET FLFX_PHOLD TO phNow.
    IF FLFX_AUTOWANT AND NOT flfxAutoHeld() {          // nothing holds the DAP any more: the crew (the test flight's) re-selects AUTO, once
        SET FLFX_AUTOWANT TO FALSE.
        LOCAL na IS flfxAutoNow().
        flLog("RESTART SW DONE: THE CREW RE-SELECTS AUTO (" + na + " DAP(S), SAIL: NO PILOT)").
    }
    IF FLFX_ECAP:LENGTH > 0 OR FLFX_EGLK:LENGTH > 0 {
        FOR en IN SHIP:ENGINES {
            LOCAL u IS flfxUid(en).
            IF FLFX_ECAP:HASKEY(u) { IF en:THRUSTLIMIT > FLFX_ECAP[u] + 0.01 { SET en:THRUSTLIMIT TO FLFX_ECAP[u]. } }
            IF FLFX_EGLK:HASKEY(u) { IF en:HASGIMBAL { IF NOT en:GIMBAL:LOCK { SET en:GIMBAL:LOCK TO TRUE. } } }
        }
    }
    IF FLFX_FMOD:LENGTH > 0 { flfxSurfApply(). }
}
// ----SW 03 DISPLAY SOFTWARE. One display page is frozen (FROZEN: the last picture, for good) or blanked (BLANK: the same
// picture until GPC_POLL_S, then the big X as a dead GPC). The display is the one on screen when the failure fires (the host's pageNow);
// RE-SELECT PAGE (2 s) gives the display back. flfxRegSw also is the place where SW 01 / SW 02 register (S4c-2 / S4c-3).
FUNCTION flfxRegSw {                        // the host's SW 03 registration: its scope ("ASCENT" / "ORBIT" / "ENTRY") and pageNow = delegate() -> display name
    PARAMETER prog, pageNow.
    SET FLFX_SWPROG TO prog.
    SET FLFX_SWPAGE TO pageNow.
    flReg("SW 03", flfxSwPage@).
    flRegFix("SW 03", flfxSwPageFix@).
    flReg("SW 01", flfxSw01@).
    flRegFix("SW 01", flfxSw01Fix@).
    // S4c-3: SW 02 (GUIDANCE LOST) registers here.
}
FUNCTION flfxSwPage {                       // SW 03's handler (tg = "PAGE", vl = "FROZEN" / "BLANK", why): the display on screen takes the failure
    PARAMETER tg, vl, why.
    IF why = "RESTORE" {                    // flfxReapply: the entry's own display is its target now
        SET FLFX_SWPG[tg] TO vl.
        RETURN "OK".
    }
    IF NOT kmLive(FLFX_SWPAGE) { RETURN "REFUSE: NO PAGE SELECTOR". }
    LOCAL d IS FLFX_SWPAGE:CALL().
    IF d = "" { RETURN "REFUSE: NO PAGE ON SCREEN". }
    IF FLFX_SWPG:HASKEY(d) { RETURN "REFUSE: ALREADY FAILED". }
    SET FLFX_SWPG[d] TO vl.
    RETURN "OK:" + d.                       // flFire stores d as the entry's target
}
FUNCTION flfxNoPilot {                       // The automated test flight has the flight (no crew to re-select AUTO after RESTART SW)
    IF FLFX_NOPILOT >= 0 { RETURN FLFX_NOPILOT = 1. }
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    IF NOT ADDONS:KALS:HASSUFFIX("SAILON") { RETURN FALSE. }
    RETURN ADDONS:KALS:SAILON.
}
FUNCTION flfxRegAuto {                       // a host's "the crew re-selects AUTO" (name, delegate() with no parameter); progReset clears the table
    PARAMETER name, d.
    SET FLFX_AUTOS[name] TO d.
}
FUNCTION flfxAutoHeld {                      // TRUE while an SW 01 / SW 02 entry stands (its fix under way counts: it is still on the list), or a DPS 04 / DPS 05 hold
    IF flfxPassHold() { RETURN TRUE. }
    FOR e IN FL_ACTIVE:COPY { IF e["code"] = "SW 01" OR e["code"] = "SW 02" { RETURN TRUE. } }
    RETURN FALSE.
}
FUNCTION flfxAutoNow {                       // every live host's delegate once; the count
    LOCAL n IS 0.
    FOR k IN FLFX_AUTOS:KEYS {
        IF kmLive(FLFX_AUTOS[k]) { FLFX_AUTOS[k]:CALL(). SET n TO n + 1. }
    }
    RETURN n.
}
FUNCTION flfxAutoWant {                      // the heal handlers': the test flight flies = the crew's wish after a RESTART SW is AUTO
    IF flfxNoPilot() { SET FLFX_AUTOWANT TO TRUE. }
}
FUNCTION flfxSwPageFix {                    // RE-SELECT PAGE's healer (flFixTick, 2 s on): the display is its own again
    PARAMETER tg, vl.
    IF FLFX_SWPG:HASKEY(tg) { FLFX_SWPG:REMOVE(tg). }
}
FUNCTION flfxSw01 {                         // SW 01 (AUTO DAP LOST): tg = the scope ("ASCENT" / "ORBIT" / "ENTRY"); this program flies only its own scope
    PARAMETER tg, vl, why.
    IF why = "RESTORE" { RETURN "OK". }     // nothing to re-apply: the query reads the ACTIVE list (flfxSwLost)
    IF tg <> FLFX_SWPROG { RETURN "REFUSE: NOT FLYABLE IN " + FLFX_SWPROG. }
    RETURN "OK".
}
FUNCTION flfxSw01Fix {                      // RESTART SW's healer: nothing to undo here (the entry goes, and the host's query stops refusing AUTO)
    PARAMETER tg, vl.
    flfxSwPub().
    flfxAutoWant().                         // The CSS the loss forced stays until the crew re-selects AUTO: the test flight's crew is this
}
FUNCTION flfxSwLost {                       // the query S4c-2 / S4c-3 use: TRUE when the ACTIVE list holds (code, scope); the scope is the entry's target
    PARAMETER code, scope.
    IF FL_ACTIVE:LENGTH = 0 { RETURN FALSE. }
    RETURN flActiveIdx(code, scope) >= 0.
}
// ----SW 02 GUIDANCE LOST (the guidance of ONE phase halts). flfxSwGuid(phase) is TRUE at once: the host stops
// its guidance update and holds the last command. flfxSwAutoLost(prog, ph) is the DAP's AUTO refusal: SW 01 on the program,
// or SW 02 on the phase after DAP_GD_LOST_S (the held command is followed for those seconds, then the AUTO axes go CSS).
FUNCTION flfxSw02 {                         // SW 02's handler: tg = the guidance phase ("ENTRY" / "TAEM" / "A/L" / ...); the host flies only its registered phases
    PARAMETER tg, vl, why.
    IF why = "RESTORE" { RETURN "OK". }     // nothing to re-apply: the query reads the ACTIVE list (flfxSwGuid)
    // SimSup ALPHA FAIL: ALPHA MOD = the entry's alpha loop: the DAP's PITCH axis only goes CSS (flfxSwAlphaLost); the guidance and roll stay
    IF tg = "ALPHA MOD" { RETURN CHOOSE "OK" IF why = "RESTORE" OR FLFX_GPH:CONTAINS("ENTRY") ELSE "REFUSE: NOT FLYABLE IN " + FLFX_SWPROG. }
    IF NOT FLFX_GPH:CONTAINS(tg) { RETURN "REFUSE: NOT FLYABLE IN " + FLFX_SWPROG. }
    RETURN "OK".
}
FUNCTION flfxSw02Fix {                      // RESTART SW's healer: the guidance resumes from the vehicle's state (nothing held in this file; the DAP stays CSS until AUTO is pressed)
    PARAMETER tg, vl.
    flfxSwPub().
    flfxAutoWant().                         // ...which the test flight's crew presses (flfxTick, once nothing holds the DAP)
}
FUNCTION flfxRegGuid {                      // the host's SW 02 registration: phases = the guidance phases it flies (ops3q: ENTRY / TAEM / A/L)
    PARAMETER phases.
    SET FLFX_GPH TO phases.
    flReg("SW 02", flfxSw02@).
    flRegFix("SW 02", flfxSw02Fix@).
}
// ----DPS 04 REDUNDANT SET SPLIT / DPS 05 PASS GENERIC FAIL hold the host like SW 02 on EVERY phase it flies (FLFX_GPH): the guidance halts, the last command flies, the DAP goes CSS
// DAP_GD_LOST_S later (DPS 05: AUTO is lost at once, the PASS set is gone). Ascent and entry only (an ORBIT program is never held: no 4-GPC set). The BFS engaged (lib_gpc GPC_BFS) or the entry gone ends the hold.
FUNCTION flfxPassIdx {                       // the ACTIVE entry of the DPS 04 / DPS 05 that holds this host (-1 = none)
    IF FL_ACTIVE:LENGTH = 0 OR FLFX_SWPROG = "ORBIT" { RETURN -1. }
    IF DEFINED GPC_BFS { IF GPC_BFS { RETURN -1. } }
    LOCAL i IS flActiveIdx("DPS 05", "G1-G4").
    IF i >= 0 { RETURN i. }
    RETURN flActiveIdx("DPS 04", "2-2").
}
FUNCTION flfxPassEnt {                       // flfxPassIdx's entry (the LEXICON, LEXICON() = none): the DAPs and flfxSwPub read the entry, not an index flFixTick's REMOVE can leave stale
    IF FL_ACTIVE:LENGTH = 0 OR FLFX_SWPROG = "ORBIT" { RETURN LEXICON(). }
    IF DEFINED GPC_BFS { IF GPC_BFS { RETURN LEXICON(). } }
    LOCAL e IS flActiveEnt("DPS 05", "G1-G4").
    IF e:LENGTH > 0 { RETURN e. }
    RETURN flActiveEnt("DPS 04", "2-2").
}
FUNCTION flfxPassHold { RETURN flfxPassIdx() >= 0. }
FUNCTION flfxPassHoldPh {                    // the hold on one guidance phase (ALPHA MOD, the entry's pitch loop, is SW 02's own)
    PARAMETER ph.
    IF ph = "ALPHA MOD" OR NOT FLFX_GPH:CONTAINS(ph) { RETURN FALSE. }
    RETURN flfxPassHold().
}
FUNCTION flfxSwGuid {                       // the host's guidance-hold test for one phase: TRUE while SW 02 (or a DPS 04 / DPS 05 hold) holds it (no update, the last command held)
    PARAMETER ph.
    IF flfxPassHoldPh(ph) { RETURN TRUE. }
    RETURN flfxSwLost("SW 02", ph).
}
FUNCTION flfxSwAlphaLost {                  // TRUE while SW 02 ALPHA MOD holds: the DAP's pitch axis stays CSS (AUTO PITCH refused), at once; RESTART SW gives it back
    RETURN flfxSwLost("SW 02", "ALPHA MOD").
}
FUNCTION flfxSwAutoLost {                   // the DAP's AUTO refusal for a program (prog) flying a guidance phase (ph): SW 01 on prog, or SW 02 on ph past DAP_GD_LOST_S
    PARAMETER prog, ph.
    IF flfxSwLost("SW 01", prog) { RETURN TRUE. }
    LOCAL pe IS flfxPassEnt().               // DPS 05 = AUTO lost at once; DPS 04 = the held phase, DAP_GD_LOST_S later (as SW 02)
    IF pe:LENGTH > 0 {
        IF pe["code"] = "DPS 05" { RETURN TRUE. }
        IF FLFX_GPH:CONTAINS(ph) AND flUt() - pe["met"] >= DAP_GD_LOST_S { RETURN TRUE. }
    }
    LOCAL se IS flActiveEnt("SW 02", ph).
    IF se:LENGTH = 0 { RETURN FALSE. }
    RETURN flUt() - se["met"] >= DAP_GD_LOST_S.
}
// ----FLFX_SWMASK = the SW 01 / SW 02 bits the C# twins read (coproc DapState / Dap / O2Dap / AscDap / guidance
// steps). Published from the ACTIVE list by flfxSwPub: at every flfxTick pass (0.5 s), at flfxReapply / flfxReset. Bits:
// 1 SW 01 ASCENT, 2 SW 01 ORBIT, 4 SW 01 ENTRY, 8 SW 02 ASCENT, 16 SW 02 ORBIT BURN, 32 SW 02 ENTRY, 64 SW 02 TAEM, 128 SW 02 A/L, 256 SW 02 ALPHA MOD.
// It is the C# gate's copy of the kOS truth; the kOS handlers stay the first line. A script that writes FLFX_SWMASK to 0 gets it
// back within 0.5 s (the DLL's FAILLIST is untouched).
FUNCTION flfxSwPub {
    LOCAL m IS 0.
    LOCAL has IS LIST().
    LOCAL bits IS LIST(LIST("SW 01", "ASCENT", 1), LIST("SW 01", "ORBIT", 2), LIST("SW 01", "ENTRY", 4),
        LIST("SW 02", "ASCENT", 8), LIST("SW 02", "ORBIT BURN", 16), LIST("SW 02", "ENTRY", 32),
        LIST("SW 02", "TAEM", 64), LIST("SW 02", "A/L", 128), LIST("SW 02", "ALPHA MOD", 256)).
    FOR b IN bits {
        IF flActiveIdx(b[0], b[1]) >= 0 { SET m TO m + b[2]. has:ADD(b[2]). }
    }
    LOCAL pe IS flfxPassEnt().               // A DPS 04 / DPS 05 hold = the SW 02 bit of every phase this host flies (+ SW 01's for DPS 05: AUTO lost at once)
    IF pe:LENGTH > 0 {
        LOCAL pb IS LIST(LIST("ASCENT", 8), LIST("ENTRY", 32), LIST("TAEM", 64), LIST("A/L", 128)).
        FOR b IN pb { IF FLFX_GPH:CONTAINS(b[0]) AND NOT has:CONTAINS(b[1]) { SET m TO m + b[1]. has:ADD(b[1]). } }
        IF pe["code"] = "DPS 05" {
            IF FLFX_SWPROG = "ASCENT" AND NOT has:CONTAINS(1) { SET m TO m + 1. has:ADD(1). }
            IF FLFX_SWPROG = "ENTRY" AND NOT has:CONTAINS(4) { SET m TO m + 4. has:ADD(4). }
        }
    }
    SET FLFX_SWMASK TO m.
    RETURN m.
}
FUNCTION flfxReapply {                       // after the host's start (flInit, flReg, fuiBoot): the earlier program's failures act again (why RESTORE)
    LOCAL n IS 0.
    FOR e IN FL_ACTIVE:COPY {
        IF FLFX_CODES:CONTAINS(e["code"]) AND flFlyable(e["code"]) {
            LOCAL ans IS FL_HAND[e["code"]]:CALL(e["tg"], e["val"], "RESTORE").
            IF ans:STARTSWITH("OK") { SET n TO n + 1. }
        }
    }
    flfxSwPub().
    RETURN n.
}
FUNCTION flfxReset {                         // a new flight: the effect tables empty (lib_fail's flReset empties the list)
    FLFX_ECAP:CLEAR().
    FLFX_EGLK:CLEAR().
    FLFX_FMOD:CLEAR().
    IF DEFINED SURF_FROZEN { SURF_FROZEN:CLEAR(). }
    IF DEFINED FLFX_SWPG { FLFX_SWPG:CLEAR(). }
    SET FLFX_PHOLD TO FALSE.
    SET FLFX_NEXT TO 0.
    flfxSwPub().
}
