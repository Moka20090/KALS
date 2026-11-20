@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_PROGRESET.KS  --  nothing a program registered may outlive it (stale delegates across program runs)
// ============================================================================
//  kOS keeps GLOBALs after a program ends, and the libraries keep the state they declare under IF NOT (DEFINED ...) (RUNONCEPATH
//  runs a library once per top-level run; a nested RUNPATH does not reload it either). A GLOBAL that holds a delegate made by
//  a program that has ended (or has handed over: its window closed, its checks dead) throws "Cannot call this lock or function or
//  delegate from one program run when it was declared in another" the next time the library calls it: lib_kmsg's KM_SINK /
//  KM_HOOK (the ops2q MSG line, the C&W hook), lib_cw's CW_CHK / CW_METFN (the checks and the MET delegate), traj_display's
//  TJ_LIVE / TJ_AFTER, arm.ks's ARM_CYCLE / ARM_END / ARM_SNAP. The project owner's two crashes: ops2q -> ops3q (cwTick called ops2q's
//  "SYS" check) and 'run ops3q.' after ops2q ended (kmPut called ops2q's sink).
//  progReset() puts every one of them back to "none". Every program calls it FIRST (before the libraries it loads register
//  anything) and LAST (before it hands over or ends), so no program leaves a hook for the next one: ops1q, ops2q, ops3q, ops6q,
//  shuttle_exec, deorbit_plan, land. NOT fam_build / arm.ks: ops2q hosts them and their lines go through ops2q's own sink.
//  Safe to call whenever: each variable is touched only when it exists (the libraries may not be loaded).
//  The libraries also heal themselves when they load fresh (lib_kmsg / lib_cw drop a delegate that is dead).
// ============================================================================
IF EXISTS("0:/lib/lib_sail.ks") { RUNONCEPATH("0:/lib/lib_sail.ks"). }   // The automated test harness (SAIL), inert unless SAIL_ON; not in the release package (no SAIL_ON then)
FUNCTION progReset {
    IF DEFINED KM_SINK {                             // lib_kmsg
        SET KM_SINK TO 0.
        SET KM_HOOK TO 0.
        KM_PEND:CLEAR().                             // the lines that waited for a sink are the last program's
    }
    IF DEFINED CW_CHK {                              // lib_cw
        CW_CHK:CLEAR().
        SET CW_METFN TO 0.
    }
    IF DEFINED FL_DLL {                              // lib_fail (flDllAdopt's FL_DLL["list"]:CALL() died in ops2q after ops1q)
        FL_DLL:CLEAR().                              // the addon's calls: looked up again at the next flDllOn
        FL_BINDR:CLEAR().
        FL_HAND:CLEAR().
        FL_HEAL:CLEAR().
        FL_GUARD:CLEAR().
        SET FL_ALERT TO 0.
    }
    IF DEFINED FLFX_RES { FLFX_RES:CLEAR(). }        // lib_flfx
    IF DEFINED FLFX_AUTOS { FLFX_AUTOS:CLEAR(). SET FLFX_AUTOWANT TO FALSE. }   // The hosts' AUTO delegates
    IF DEFINED FUI_SAY { SET FUI_SAY TO 0. }         // lib_failui
    IF DEFINED GPC_WIN {                             // lib_gpc
        GPC_WIN:CLEAR().
        SET GPC_CANRS TO 0.
    }
    IF DEFINED TJ_LIVE { SET TJ_LIVE TO 0. }         // traj_display
    IF DEFINED TJ_AFTER { SET TJ_AFTER TO 0. }
    IF DEFINED ARM_CYCLE { UNSET ARM_CYCLE. }        // arm.ks
    IF DEFINED ARM_END { UNSET ARM_END. }
    IF DEFINED ARM_SNAP { UNSET ARM_SNAP. }
    IF DEFINED SAIL_ON { sailBegin(). }              // lib_sail: the pressable-widget registry emptied; an automated test run arms its command tick, else nothing
}
