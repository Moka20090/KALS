// lib_far.ks -- the control surfaces and the drag chute under Ferram Aerospace Research (FAR), with SOCK RealAero's
// alternate FAR cfgs.
// With FAR, SOCK_RealAero's 6_far.cfg replaces each stock ModuleControlSurface with a FARControllableSurface whose flap
// function is on at its full setting (isFlap, setting 3), so FAR's "Flp/Splr Dflct" is the surface's angle: the twin of
// the stock "deploy angle". FAR's ModuleParachute is RealChuteFAR. Without FAR every call here is the stock one.
// The stock rudder halves split through deployInvert on the first (rudder.002); FAR has no such flag, so the second half
// (rudder.003) takes the opposite sign. kOS rounds each angle to FAR's 0.5 deg slider step.
// UNTESTED IN GAME. FAR_DSIGN +1 is worked out, not flown (from KSP's ModuleControlSurface, FAR's source, the
// craft and the models): the craft's deploy flags turn every elevon and the body flap by -angle about the part's x, as
// FAR's flap does at flapLocation +1. The rudder's flapLocation is the sign of a near-zero dot product, so its split may
// show the halves closing into each other (the same drag, a visual fault). Under FAR, AG3 does not un-deploy the rudder halves (FAR has no deploy toggle): the speedbrake's
// AG3 press is not seen; the throttle lever and the guidance still drive it.
// Loaded with RUNONCEPATH by lib_vehicle, lib_dap, lib_land, ops1q, ops3q, ops6q; no top-level action but the globals
// (and, with FAR, farShow: up to 2 s at load).

GLOBAL FAR_ON IS SHIP:MODULESNAMED("FARControllableSurface"):LENGTH > 0.
// SockFarTrim (KalsCoproc.dll + 7_far_trim.cfg) on the vessel: the FAR CG bias was fitted with it
GLOBAL FAR_TRIM_ON IS FAR_ON AND SHIP:MODULESNAMED("SockFarTrim"):LENGTH > 0.
GLOBAL SURF_MN IS CHOOSE "FARControllableSurface" IF FAR_ON ELSE "ModuleControlSurface".
GLOBAL CHUTE_MN IS CHOOSE "RealChuteFAR" IF SHIP:MODULESNAMED("RealChuteFAR"):LENGTH > 0 ELSE "ModuleParachute".
GLOBAL FAR_DSIGN IS 1.
GLOBAL FAR_SHOWN IS FALSE.
GLOBAL SURF_FROZEN IS LEXICON().         // FCS 01, lib_flfx.ks: part uid -> TRUE for each FROZEN surface; surfSetAng / surfSetLock skip them
FUNCTION surfFrozen {                    // is this surface module frozen by a failure? (one LENGTH test with none)
    PARAMETER m.
    IF SURF_FROZEN:LENGTH = 0 { RETURN FALSE. }
    // A module whose part is gone (a splashdown or crash rebuilt the vessel) must not be read: TRUE = skipped, the
    // same answer as a frozen surface, so every writer that tests surfFrozen first stops (the modLive guard comes first)
    IF NOT modLive(m) { RETURN TRUE. }
    RETURN SURF_FROZEN:HASKEY(modKey(m)).      // The module's own key (a rudder half has its own), not its part's
}
// may this module be written? Its part must still be on SHIP: a splashdown rebuilds the vessel, and a module of the old
// one throws KOSWrongCPUVesselException at SETFIELD (the test harness, 11-12, an elevon after touchdown). Every SETFIELD of the surf helpers
// and of lib_dap goes through this; a module on the ship answers TRUE, so nothing changes in flight.
// the modLive test itself (m:PART:SHIP) THROWS on a module of a vessel that was rebuilt, and a splashdown rebuilds
// the vessel ('Unloaded vessel', then m:PART NullReference in VesselTarget.ConstructParts).
// So modLive never touches m, and a splashdown opens a hold. A module is REGISTERED (modReg) with the vessel generation
// VES_GEN and its part's UID (MOD_UID[m] = LIST(gen, uid, key)). vesWatch() reads SHIP:STATUS once per game time: the change to
// SPLASHED starts a new generation and a hold of VES_HOLD_S game seconds: until it ends, modLive is FALSE for every module
// and modReg registers nothing (no m:PART, no SHIP:PARTS walk). A module of an earlier generation is an old instance: FALSE.
// After the hold, LIVE_UIDS = the UIDs of SHIP:PARTS, rebuilt once per game time and when the part count, the vessel name
// or the generation changes. A module never registered (a fresh SHIP list used at once) answers TRUE with no touch.
// Flight without a splashdown: VES_HOLD -1, VES_GEN 0, nothing changes. kOS LEXICON keys a structure by object identity
// (offline VM, t859/keys.log): modReg's module must be the same object the caller passes.
GLOBAL MOD_UID IS LEXICON().          // module -> LIST(VES_GEN, its part's UID, its surface key) (modReg; the key tells the two
                                      // rudder halves of ONE part apart: uid for the first, uid#1 for the second)
GLOBAL LIVE_UIDS IS LEXICON().        // the UIDs of SHIP:PARTS (liveRefresh)
GLOBAL LIVE_N IS -1.
GLOBAL LIVE_NAME IS "".
GLOBAL LIVE_GEN IS -1.
GLOBAL LIVE_T IS -1.
GLOBAL VES_GEN IS 0.                  // the vessel generation: +1 at each splashdown (vesWatch)
GLOBAL VES_STAT IS "".
GLOBAL VES_HOLD IS -1.                // game time until which no module is touched (-1: no hold)
GLOBAL VES_T IS -1.
GLOBAL VES_HOLD_S IS 2.
GLOBAL VES_HARD_V IS 6.               // m/s of sink (the last reading before the contact) over which a touchdown opens the hold
GLOBAL VES_VSP IS 0.                  // the vertical speed at the previous vesWatch (the status flips AFTER the impact has taken the speed)
FUNCTION vesWatch {                   // once per game time: a SPLASHED from another status opens a new generation and a hold
    IF TIME:SECONDS = VES_T { RETURN. }
    SET VES_T TO TIME:SECONDS.
    LOCAL st IS SHIP:STATUS.
    // The hold does not open at every touchdown: every module write is refused during the hold, so the DAP could not derotate after a gentle one.
    // A splash always opens it (and a new generation); a touchdown only when it was hard (the last sink before the contact over VES_HARD_V):
    // that is the crash that rebuilds the vessel. A gentle touchdown rebuilds nothing, and a part lost later is caught by the part count (ldLive).
    IF st <> VES_STAT AND st = "SPLASHED" {
        SET VES_HOLD TO TIME:SECONDS + VES_HOLD_S.
        SET VES_GEN TO VES_GEN + 1.                             // only a splash rebuilds the vessel (old instances dead)
    } ELSE IF st <> VES_STAT AND st = "LANDED" AND VES_VSP < 0 - VES_HARD_V {
        SET VES_HOLD TO TIME:SECONDS + VES_HOLD_S.
    }
    SET VES_VSP TO SHIP:VERTICALSPEED.
    SET VES_STAT TO st.
}
FUNCTION modReg {                     // register a module of a part on SHIP NOW (a fresh SHIP list, or a holder's build)
    PARAMETER m, rk IS 0.             // rk = the module's rank among the same part's surface modules (0: the first / the only one)
    vesWatch().
    IF TIME:SECONDS < VES_HOLD { RETURN m. }      // the vessel is being rebuilt: no touch, no registration
    IF MOD_UID:HASKEY(m) {
        IF MOD_UID[m][0] = VES_GEN { RETURN m. }
    }
    LOCAL pu IS "" + m:PART:UID.
    SET MOD_UID[m] TO LIST(VES_GEN, pu, CHOOSE pu IF rk <= 0 ELSE pu + "#" + rk).
    RETURN m.
}
FUNCTION modUid {                     // the part UID of a module: the registered one (no touch), else read now
    PARAMETER m.
    IF MOD_UID:HASKEY(m) { RETURN MOD_UID[m][1]. }
    RETURN "" + m:PART:UID.
}
FUNCTION modKey {                     // The key a failure holds a surface module by: the part's UID, the 2nd half of a part: UID#1
    PARAMETER m.
    IF MOD_UID:HASKEY(m) { RETURN MOD_UID[m][2]. }
    RETURN "" + m:PART:UID.
}
FUNCTION liveRefresh {                // LIVE_UIDS: once per game time; rebuilt only when the part count, the vessel or the generation changed
    IF TIME:SECONDS = LIVE_T { RETURN. }
    SET LIVE_T TO TIME:SECONDS.
    LOCAL ps IS SHIP:PARTS.
    IF ps:LENGTH = LIVE_N AND SHIP:NAME = LIVE_NAME AND VES_GEN = LIVE_GEN { RETURN. }
    LOCAL u IS LEXICON().
    FOR p IN ps { SET u["" + p:UID] TO TRUE. }
    SET LIVE_UIDS TO u.
    SET LIVE_N TO ps:LENGTH.
    SET LIVE_NAME TO SHIP:NAME.
    SET LIVE_GEN TO VES_GEN.
}
FUNCTION modLive {
    PARAMETER m.
    vesWatch().
    IF TIME:SECONDS < VES_HOLD { RETURN FALSE. }  // the vessel is being rebuilt: no module is touched
    IF NOT MOD_UID:HASKEY(m) { RETURN TRUE. }     // never registered: no touch (a fresh module is on the ship)
    IF MOD_UID[m][0] <> VES_GEN { RETURN FALSE. } // an earlier vessel's module: an old instance, gone
    liveRefresh().
    RETURN LIVE_UIDS:HASKEY(MOD_UID[m][1]).
}

// A surface list (ELEV_MODS and FLAP_MOD, dElv / dRud, ENTRY_SB_RUD, the landing's rudder / drain / gear lists) is
// built in one vessel generation. A splashdown rebuilds the vessel (VES_GEN + 1), so the list then holds dead modules: its
// owner re-finds it from SHIP once the hold is over (surfListRefind). A touchdown rebuilds nothing (VES_GEN unchanged), so
// its lists stay as they are through the touchdown's hold. surfListMark(k) at each build; a list never marked is never old.
GLOBAL SURF_LIST_GEN IS LEXICON().     // list name -> VES_GEN it was built in
FUNCTION surfListMark {
    PARAMETER k.
    vesWatch().
    IF TIME:SECONDS < VES_HOLD { SET SURF_LIST_GEN[k] TO -1. RETURN. }   // built in a hold: old at once, found again after it
    SET SURF_LIST_GEN[k] TO VES_GEN.
}
FUNCTION surfListOld {                 // TRUE while list k was built in an earlier vessel generation (its modules are dead)
    PARAMETER k.
    vesWatch().
    IF NOT SURF_LIST_GEN:HASKEY(k) { RETURN FALSE. }
    RETURN SURF_LIST_GEN[k] <> VES_GEN.
}
FUNCTION surfListRefind {              // TRUE when list k must be re-found now: it is old and the splash's hold is over
    PARAMETER k.
    IF NOT surfListOld(k) { RETURN FALSE. }
    RETURN TIME:SECONDS >= VES_HOLD.
}
IF FAR_ON { farShow(). }      // FAR's hidden fields out once, at load, not in a guidance loop

// FAR hides the flap angle and the axis gains until its "Flp/Splr" and "Std. Ctrl" toggles are on; they show on FAR's
// next update, so the first call waits up to 2 s for them.
FUNCTION farShow {
    IF NOT FAR_ON OR FAR_SHOWN { RETURN. }
    SET FAR_SHOWN TO TRUE.
    FOR m IN SHIP:MODULESNAMED("FARControllableSurface") {
        IF modLive(m) {
            IF m:HASFIELD("flp/splr") { m:SETFIELD("flp/splr", TRUE). }
            IF m:HASFIELD("std. ctrl") { m:SETFIELD("std. ctrl", TRUE). }
        }
    }
    LOCAL t IS TIME:SECONDS + 2.
    UNTIL TIME:SECONDS > t {
        LOCAL ok IS TRUE.
        FOR m IN SHIP:MODULESNAMED("FARControllableSurface") {
            IF NOT m:HASFIELD("flp/splr dflct") OR NOT m:HASFIELD("pitch %") { SET ok TO FALSE. }
        }
        IF ok { BREAK. }
        WAIT 0.
    }
}

// the stock "deploy angle" (deg) and its FAR twin; sg -1 for the second rudder half
FUNCTION surfSetAng {
    PARAMETER m, ang, sg IS 1.
    IF surfFrozen(m) { RETURN. }
    IF NOT modLive(m) { RETURN. }
    IF FAR_ON {
        farShow().
        // FAR flies only the rudder's first half (one wing model a part); SockFarTrim reads the split from the
        // two halves, keeps the brake off the first and adds the brake's drag (the second shows the split)
        IF m:HASFIELD("flp/splr dflct") { m:SETFIELD("flp/splr dflct", MAX(-85, MIN(85, sg * FAR_DSIGN * ang))). }
        RETURN.
    }
    m:SETFIELD("deploy angle", ang).
}
FUNCTION surfGetAng {
    PARAMETER m, sg IS 1.
    IF FAR_ON { farShow(). }
    IF NOT modLive(m) { RETURN 0. }         // A gone part (a stale list entry) reads the safe default
    IF FAR_ON {
        IF m:HASFIELD("flp/splr dflct") { RETURN sg * FAR_DSIGN * m:GETFIELD("flp/splr dflct"). }
        RETURN 0.
    }
    RETURN m:GETFIELD("deploy angle").
}
FUNCTION surfHasAng {
    PARAMETER m.
    IF FAR_ON { farShow(). }
    IF NOT modLive(m) { RETURN FALSE. }     // A gone part has no angle to read
    IF FAR_ON { RETURN m:HASFIELD("flp/splr dflct"). }
    RETURN m:HASFIELD("deploy angle").
}
// the stock "deploy" toggle: under FAR the flap is always on (6_far.cfg)
FUNCTION surfDep {
    PARAMETER m.
    IF FAR_ON { RETURN TRUE. }
    IF NOT modLive(m) { RETURN TRUE. }      // A gone part reads as deployed (no re-deploy, no read)
    RETURN m:GETFIELD("deploy").
}
FUNCTION surfDeploy {
    PARAMETER m.
    IF surfFrozen(m) { RETURN. }           // A frozen surface stays where it is: deploy would swing it to its stored deploy angle (25 / 35)
    IF FAR_ON { farShow(). RETURN. }
    IF NOT modLive(m) { RETURN. }
    m:SETFIELD("deploy", TRUE).
}
// the stock axis toggles ("pitch" / "yaw" / "roll": TRUE = the axis ignored) and FAR's gains ("pitch %": 0 = ignored;
// freed, an axis takes back 6_far.cfg's gain: the elevons pitch and roll, the rudder halves yaw, the body flap none)
FUNCTION farGain {
    PARAMETER m, ax.
    LOCAL nm IS m:PART:NAME:TOLOWER.
    IF nm:CONTAINS("elevon") AND ax <> "yaw" { RETURN 100. }
    IF nm:CONTAINS("rudder") AND ax = "yaw" { RETURN 100. }
    RETURN 0.
}
FUNCTION surfGetLock {
    PARAMETER m, ax.
    IF FAR_ON { farShow(). }
    IF NOT modLive(m) { RETURN TRUE. }      // A gone part reads as locked (its axis is not flown)
    IF FAR_ON {
        IF m:HASFIELD(ax + " %") { RETURN m:GETFIELD(ax + " %") = 0. }
        RETURN TRUE.
    }
    RETURN m:GETFIELD(ax).
}
FUNCTION surfSetLock {
    PARAMETER m, ax, ign.
    IF NOT ign AND surfFrozen(m) { RETURN. }
    IF NOT modLive(m) { RETURN. }
    IF FAR_ON {
        farShow().
        IF m:HASFIELD(ax + " %") { m:SETFIELD(ax + " %", CHOOSE 0 IF ign ELSE farGain(m, ax)). }
        RETURN.
    }
    IF m:HASFIELD(ax) { m:SETFIELD(ax, ign). }
}
// the chute's events: the stock "deploy chute" / "cut parachute"; RealChuteFAR's "deploy chute" / "cut chute"
FUNCTION chuteEv {
    PARAMETER ev.
    IF CHUTE_MN = "RealChuteFAR" AND ev:CONTAINS("cut") { RETURN "cut chute". }
    RETURN ev.
}
