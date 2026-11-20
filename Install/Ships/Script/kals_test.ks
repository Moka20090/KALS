// kals_test.ks -- is this install ready for the KAL/S scripts? RUN kals_test.
// The terminal shows only the verdict: 'KAL/S OK', or 'KAL/S NOT READY' with one FIX line per thing to fix
// (addon missing / not available, an older KalsCoproc.dll, wrong kOS version, FAR's voxels or atmosphere, the Cape).
// Every other line of the check goes to 0:/logs/kals_test.txt only (lg). The probe never stops early: every check runs.
CLEARSCREEN.
LOCAL f IS "0:/logs/kals_test.txt".
IF EXISTS(f) { DELETEPATH(f). }
LOCAL fix IS LIST().
FUNCTION lg { PARAMETER s. LOG s TO f. }
FUNCTION pr { PARAMETER s. PRINT s. LOG s TO f. }
FUNCTION need { PARAMETER s. fix:ADD(s). }

lg("kals_test " + TIME:SECONDS).

// 1. kOS: the scripts were written and tested against kOS 1.6.0.1 (sock_setup.py patches that kOS.dll).
LOCAL kv IS "" + CORE:VERSION.
lg("kOS version: " + kv).
IF kv <> "1.6.0.1" {
    need("kOS is " + kv + ": these scripts need kOS 1.6.0.1. Install that kOS (sock_setup.py is for it).").
}

// 2. The KAL/S addon: present, and available.
LOCAL kalsOk IS FALSE.
LOCAL kalsPresent IS ADDONS:HASSUFFIX("KALS").
lg("ADDONS:KALS: " + kalsPresent).
IF NOT kalsPresent {
    need("KAL/S addon missing (no ADDONS:KALS). Put KalsCoproc.dll in GameData/KALS_Coproc/Plugins, restart KSP, and look for [KalsCoproc] in KSP.log.").
} ELSE IF NOT ADDONS:KALS:AVAILABLE {
    need("KAL/S addon not available (ADDONS:KALS:AVAILABLE is FALSE). Look for [KalsCoproc] errors in KSP.log, then restart KSP.").
} ELSE {
    SET kalsOk TO TRUE.
    lg("KAL/S suffixes: " + ADDONS:KALS:SUFFIXNAMES:JOIN(" ")).
}

// 3. An older KalsCoproc.dll: it lacks a suffix these scripts call.
LOCAL oldDll IS FALSE.
IF kalsOk {
    LOCAL reqSuf IS LIST("CAPEGEO", "ENGIND", "OMSLINE", "ASCIHAT", "FAILSET", "FARINFO", "RAILSINFO").
    LOCAL miss IS "".
    FOR sfx IN reqSuf {
        IF NOT ADDONS:KALS:HASSUFFIX(sfx) { SET miss TO miss + " " + sfx. }
    }
    IF miss <> "" {
        SET oldDll TO TRUE.
        need("KalsCoproc.dll is older than these scripts (no" + miss + "). Install the current KalsCoproc.dll in both installs.").
    }
}

// 4. FAR: a note, and a fix only when FAR is there but cannot give its numbers.
IF kalsOk AND NOT oldDll {
    LOCAL fi IS ADDONS:KALS:FARINFO.
    lg("FAR: " + fi).
    IF fi:FIND("NOT FOUND") >= 0 {
        lg("NOTE: FAR not found (a stock install).").
    } ELSE {
        IF fi:FIND("NOT VALID") >= 0 {
            need("FAR is found but its voxels are not valid. Load the craft on the pad (FAR builds them), then run kals_test again.").
        }
        IF fi:FIND("REPLACED") >= 0 {
            need("Another mod replaces FAR's atmosphere, so the aero numbers will not match the logs. Remove that mod or run a FAR-only install.").
        }
    }
}

// 5. The Cape: the KAL/S Cape place (lib_cape.ks). 'assumed' = the addon could not say where the Cape is.
RUNONCEPATH("0:/lib/lib_cape.ks").
lg("CAPE: " + CAPE_WHY).
IF kalsOk AND NOT oldDll AND CAPE_WHY:FIND("assumed") >= 0 {
    need("Cape: " + CAPE_WHY + ". Check that the KALS_CapeWater config and KCC_CapeCanaveral are in GameData.").
}

// The verdict: the only lines on the terminal.
IF fix:LENGTH = 0 {
    pr("KAL/S OK").
} ELSE {
    pr("KAL/S NOT READY: " + fix:LENGTH + " thing(s) to fix:").
    FOR msg IN fix { pr("  FIX: " + msg). }
}
lg("done").
