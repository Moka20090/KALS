@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_SCREEN.KS  --  the screen size the displays are drawn for
// ============================================================================
//  Reads 0:/display.txt once: one line with the screen size, e.g. 1920x1080. Without the file: 3840x2160. kOS GUI
//  units are screen pixels (KSP's UI scale does not change them). The HUD has one image set per screen size and HUD
//  CAM field of view: hud/ for 3840x2160 through 60 deg, hud_<W>x<H>/ for the other sizes, hud_<W>x<H>_fov<N>/ for
//  the other fields of view (the installer builds them with hud_build.py; gen_hud.py kos-hud <folder> --screen
//  <W>x<H> --fov <N> on the development side). The field of view is 0:/hud_fov.txt's number (hud_cal.ks saves it),
//  60 without the file. A size or a field of view without a set prints a warning and keeps 3840x2160 / 60 deg. The
//  other windows keep their pixel size on every screen.
//  Loaded by lib_hud.ks and lib_taemdisp.ks: RUNONCEPATH("0:/lib/lib_screen.ks").
// ============================================================================

RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
GLOBAL SCR_W IS 3840.                       // px: the screen width
GLOBAL SCR_H IS 2160.                       // px: the screen height
GLOBAL SCR_HUD IS "hud/".                   // the HUD's folder in the archive (Ships/Script)
GLOBAL SCR_FOV IS 60.                       // deg: the HUD CAM's vertical field of view (the set drawn for it)
GLOBAL SCR_FOVS IS LIST(40, 60, 70).        // the fields of view hud_cal.ks offers (the installer builds each)
GLOBAL SCR_FOV_FILE IS "0:/hud_fov.txt".

// the HUD set's folder for a screen size and a field of view
FUNCTION scrHudDir {
    PARAMETER w, h, fov.
    IF fov <> 60 { RETURN "hud_" + w + "x" + h + "_fov" + fov + "/". }
    IF w = 3840 AND h = 2160 { RETURN "hud/". }
    RETURN "hud_" + w + "x" + h + "/".
}

IF EXISTS("0:/display.txt") {
    LOCAL scrTxt IS OPEN("0:/display.txt"):READALL:STRING:SPLIT(CHAR(10))[0]:TRIM:TOLOWER.
    LOCAL scrWh IS scrTxt:SPLIT("x").
    LOCAL scrW IS -1.
    LOCAL scrH IS -1.
    IF scrWh:LENGTH = 2 {
        SET scrW TO scrWh[0]:TRIM:TONUMBER(-1).
        SET scrH TO scrWh[1]:TRIM:TONUMBER(-1).
    }
    IF NOT (scrW = 3840 AND scrH = 2160) {
        IF scrW > 0 AND scrH > 0 AND EXISTS("0:/hud_" + scrW + "x" + scrH + "/hud_layout.txt") {
            SET SCR_W TO scrW.
            SET SCR_H TO scrH.
            SET SCR_HUD TO "hud_" + scrW + "x" + scrH + "/".
        } ELSE {
            kmSay("display.txt: no HUD set for '" + scrTxt + "' -- drawing for 3840x2160", "C").
        }
    }
}

IF EXISTS(SCR_FOV_FILE) {
    LOCAL scrFov IS ROUND(OPEN(SCR_FOV_FILE):READALL:STRING:SPLIT(CHAR(10))[0]:TRIM:TONUMBER(60)).
    IF scrFov <> 60 {
        IF EXISTS("0:/" + scrHudDir(SCR_W, SCR_H, scrFov) + "hud_layout.txt") {
            SET SCR_FOV TO scrFov.
            SET SCR_HUD TO scrHudDir(SCR_W, SCR_H, scrFov).
        } ELSE {
            kmSay("hud_fov.txt: no HUD set for " + scrFov + " deg on " + SCR_W + "x" + SCR_H + " -- drawing for 60 deg", "C").
        }
    }
}
