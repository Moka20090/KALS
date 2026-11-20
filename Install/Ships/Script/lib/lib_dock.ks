@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_DOCK.KS  --  THE DISPLAY DECK'S DOCKING (a top window and the bottom window docked under it)
// ============================================================================
//  Every pair, ascent too: drag the top window and the bottom one moves with it; move the bottom one and they undock;
//  drag it back within DK_SNAP px of its spot and it snaps in. The deck's place is remembered across the programs.
//  kOS (IL-read): GUI:X / :Y read the window's rect, which GUILayout.Window returns every frame,
//  so they follow a drag; the whole window is the drag handle (GUI.DragWindow() while DRAGGABLE); a SET of a negative
//  value counts from the right / bottom edge (so every SET here is clamped to >= 0). kOS has no mouse-up: a bottom
//  window that has not moved for DK_STILL real seconds has been dropped.
//  Hosts: dkAttach(top, bottom, key) once both windows exist at their default places (the offset between them is the
//  dock), dkDetach(key) when the pair closes: only the pair attached
//  under that key lets go (an RTLS: ops6q opens the GRTLS pair before it closes the ascent's).
//  Everything else runs in one trigger, every physics tick (a handful of opcodes), so the bottom follows a drag of the
//  top within a tick.
//  The deck's place is the PLAYER'S file DK_FILE (like hud_eye_cal.json): never in the repo or the release. One place
//  for every pair (ascent, entry, GRTLS, TAEM): the next pair opens where the last one was left.
// ============================================================================
RUNONCEPATH("0:/lib/lib_screen.ks").        // SCR_W, SCR_H: a saved place is clamped on-screen

GLOBAL DK_FILE IS "0:/deck_pos.json".
GLOBAL DK_SNAP IS 40.                       // px: the bottom dropped within this of its dock spot docks
GLOBAL DK_STILL IS 0.3.                     // real s without a move = the drag has ended
GLOBAL DK_SAVE_S IS 1.0.                    // real s after the last change before the file is written
GLOBAL DK_EPS IS 0.5.                       // px: the rect is float32; a smaller change is no move
GLOBAL DK_KEEP_W IS 120.                    // px of a window kept on-screen by the clamp
GLOBAL DK_KEEP_H IS 40.

GLOBAL dkOn IS FALSE.
GLOBAL dkTrig IS FALSE.                     // the trigger is made once and kept (it does nothing while NOT dkOn)
GLOBAL dkKey IS "".                        // the host that attached the pair now docked
GLOBAL dkTop IS 0.
GLOBAL dkBot IS 0.
GLOBAL dkDx IS 0.                           // the dock: the bottom's corner less the top's
GLOBAL dkDy IS 0.
GLOBAL dkDocked IS TRUE.
GLOBAL dkTx IS 0.                           // the places last seen (or set)
GLOBAL dkTy IS 0.
GLOBAL dkBx IS 0.
GLOBAL dkBy IS 0.
GLOBAL dkDropT IS -1.                       // real s of the bottom's last move while undocked (-1: no drop pending)
GLOBAL dkDirty IS FALSE.
GLOBAL dkDirtyT IS 0.
GLOBAL dkHasReal IS KUNIVERSE:HASSUFFIX("REALTIME").

FUNCTION dkNow {
    IF dkHasReal { RETURN KUNIVERSE:REALTIME. }
    RETURN TIME:SECONDS.
}

FUNCTION dkClampX { PARAMETER x. RETURN ROUND(MAX(0, MIN(SCR_W - DK_KEEP_W, x))). }
FUNCTION dkClampY { PARAMETER y. RETURN ROUND(MAX(0, MIN(SCR_H - DK_KEEP_H, y))). }

FUNCTION dkLoad {                           // the saved deck, or 0
    IF NOT EXISTS(DK_FILE) { RETURN 0. }
    LOCAL d IS READJSON(DK_FILE).
    IF NOT d:ISTYPE("Lexicon") { RETURN 0. }
    FOR k IN LIST("x", "y", "bx", "by") { IF NOT d:HASKEY(k) { RETURN 0. } IF NOT d[k]:ISTYPE("Scalar") { RETURN 0. } }
    IF NOT d:HASKEY("docked") { RETURN 0. }
    RETURN d.
}

FUNCTION dkSave {
    WRITEJSON(LEXICON("x", dkTx, "y", dkTy, "docked", dkDocked, "bx", dkBx, "by", dkBy), DK_FILE).
    SET dkDirty TO FALSE.
}

FUNCTION dkMark { PARAMETER t. SET dkDirty TO TRUE. SET dkDirtyT TO t. }

FUNCTION dkPlace {                          // the bottom to its dock spot under the top
    SET dkBot:X TO dkClampX(dkTx + dkDx).
    SET dkBot:Y TO dkClampY(dkTy + dkDy).
    SET dkBx TO dkBot:X. SET dkBy TO dkBot:Y.
}

FUNCTION dkAttach {
    PARAMETER top, bot, key.
    IF dkOn { dkDetach(dkKey). }
    SET dkKey TO key.
    SET dkTop TO top. SET dkBot TO bot.
    SET dkDx TO bot:X - top:X.              // the host's default layout is the dock
    SET dkDy TO bot:Y - top:Y.
    SET dkDocked TO TRUE.
    LOCAL d IS dkLoad().
    IF d:ISTYPE("Lexicon") {                // where the player left the deck
        SET top:X TO dkClampX(d["x"]).
        SET top:Y TO dkClampY(d["y"]).
        SET dkDocked TO d["docked"] = TRUE.
        IF NOT dkDocked { SET bot:X TO dkClampX(d["bx"]). SET bot:Y TO dkClampY(d["by"]). }
    }
    SET dkTx TO top:X. SET dkTy TO top:Y.
    IF dkDocked { dkPlace(). } ELSE { SET dkBx TO bot:X. SET dkBy TO bot:Y. }
    SET dkDropT TO -1.
    SET dkDirty TO FALSE.
    SET dkOn TO TRUE.
    IF NOT dkTrig {
        SET dkTrig TO TRUE.
        WHEN TRUE THEN { IF dkOn { dkPoll(). } RETURN TRUE. }
    }
}

FUNCTION dkDetach {
    PARAMETER key.
    IF NOT dkOn OR key <> dkKey { RETURN. }
    IF dkDirty { dkSave(). }
    SET dkOn TO FALSE.
    SET dkTop TO 0. SET dkBot TO 0.
}

FUNCTION dkPoll {
    LOCAL tx IS dkTop:X. LOCAL ty IS dkTop:Y.
    LOCAL bx IS dkBot:X. LOCAL by IS dkBot:Y.
    LOCAL t IS dkNow().
    IF ABS(bx - dkBx) > DK_EPS OR ABS(by - dkBy) > DK_EPS {   // the bottom moved: undocked
        SET dkDocked TO FALSE.
        SET dkBx TO bx. SET dkBy TO by.
        SET dkDropT TO t.
        dkMark(t).
    } ELSE IF dkDropT >= 0 AND t - dkDropT >= DK_STILL {      // dropped: near its spot -> snaps in and docks
        SET dkDropT TO -1.
        IF ABS(bx - (tx + dkDx)) <= DK_SNAP AND ABS(by - (ty + dkDy)) <= DK_SNAP {
            SET dkDocked TO TRUE.
            SET dkTx TO tx. SET dkTy TO ty.
            dkPlace().
            dkMark(t).
        }
    }
    IF ABS(tx - dkTx) > DK_EPS OR ABS(ty - dkTy) > DK_EPS {   // the top moved: a docked bottom follows
        SET dkTx TO tx. SET dkTy TO ty.
        IF dkDocked { dkPlace(). }
        dkMark(t).
    }
    IF dkDirty AND t - dkDirtyT >= DK_SAVE_S { dkSave(). }
}
