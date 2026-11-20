@LAZYGLOBAL OFF.
// ============================================================================
//  HUD.KS  --  THE HUD ON ANY AIRCRAFT.  IT FLIES NOTHING.
// ============================================================================
//  The HUD (lib_hud.ks) on any craft, flown by hand or by its SAS: the boresight, the velocity vector, the horizon
//  and the pitch ladder, the KEAS and altitude tapes (the radar altitude below 5000 ft, from the wheels), the
//  throttle on the speedbrake scale (the pilot throttle, 0 left .. full right), and SAS / MAN. Always the
//  above-4000 ft picture (hdNoDecl): the tapes and the full ladder at every height and on the ground. No guidance
//  symbols (lib_hudg.ks is the orbiter's guidance and is not loaded). No runway overlay and no runway (hdRwyIx -1:
//  lib_hud draws none and never switches ends); the height lib_hud measures from the runway's elevation (the
//  radar altimeter's gate, the declutter heights) is from the terrain below instead (hdElev).
//  On another craft lib_hud puts the eye above the canopy of the part it is flown from (a cockpit; a drone: its
//  foremost part), and takes its wheels for the gear (the larger group ahead of / behind the c.g. is the main gear).
//  HOW TO RUN
//   1. Flight view (not IVA: IVA turns the free camera off), any craft, no other program on this kOS CPU.
//   2. In the kOS terminal, each on its own line:  SWITCH TO 0.   then   RUN hud.ks.
//   3. The HUD window (top left; keep it off the HUD glass, which takes the clicks over it):
//        HUD            the HUD shown / hidden
//        HUD CAM        the camera to the cockpit's eye, looking along the nose (the HUD is conformal only in it)
//        QUIT           the stock camera back, the HUD closed
//        FWD / AFT, UP / DOWN, LEFT / RIGHT   move the HUD CAM's eye one STEP (STEP: 0.25, 0.05, 0.01 m); each move
//                       is saved at once for this craft by name (Ships/Script/hud_eye_cal_<craft name>.json; the
//                       orbiter: hud_eye_cal.json), so the next start keeps it
//        RESET          forgets the saved eye: the built-in one again
//      The eye buttons are Holo HUD's C# (HoloHud.dll, ADDONS:HOLO:HUDEYE*); without it they are not shown.
// ============================================================================

GLOBAL HD_NO_RWY IS TRUE.                  // no runway table, no Cape file, no AG4 trigger (lib_hud.ks)
RUNONCEPATH("0:/lib/lib_hud.ks").
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
SET hdNoDecl TO TRUE.                       // no declutter: the >4000 ft picture always (before hdInit: the C# reads it there)

GLOBAL huIpu IS CONFIG:IPU.
GLOBAL huDone IS FALSE.
GLOBAL huSb IS 0.
GLOBAL huMsg IS "".
GLOBAL huInfoT IS 0.
GLOBAL huCsLast IS "".
GLOBAL huEye IS FALSE.                      // the eye buttons (ADDONS:HOLO:HUDEYE*) are there
GLOBAL huEyePt IS LIST().                   // the part the eye rides

FUNCTION huInfo {
    LOCAL t IS ROUND(hdRate, 0) + " Hz".
    IF huMsg <> "" { SET t TO huMsg. }
    SET huLInfo:TEXT TO t.
    IF HD_CS_STATE <> huCsLast {                    // the drawing path goes to the log, not to the window
        SET huCsLast TO HD_CS_STATE.
        kmSay("HUD: the update runs in " + HD_CS_STATE + ".", "I").
    }
}

// the eye buttons: the eye the HUD CAM uses now (lib_hud's hdEyeOffset) into the C# (it keeps the eye and writes its
// file); after a move or a reset the camera snaps again, so hdCamSnap reads the file
FUNCTION huEyeInit {
    LOCAL eo IS hdEyeOffset(huEyePt[0], hdEyeFrame(huEyePt[0])).
    RETURN ADDONS:HOLO:HUDEYEINIT(LIST(HD_EYE_CAL_FILE, huEyePt[0]:NAME, eo[0], eo[1], eo[2])).
}
FUNCTION huEyeShow {
    IF huBCam:PRESSED AND hdCamLive() { hdCamSnap(). }
    LOCAL er IS ADDONS:HOLO:HUDEYEERR.
    SET huLEye:TEXT TO CHOOSE ADDONS:HOLO:HUDEYETEXT IF er = "" ELSE "EYE: " + er.
}

// the ground under the craft (the sea level where the body has an ocean), where lib_hud takes the runway's elevation
FUNCTION huGround {
    SET hdElev TO CHOOSE MAX(SHIP:GEOPOSITION:TERRAINHEIGHT, 0) IF BODY:HASOCEAN ELSE SHIP:GEOPOSITION:TERRAINHEIGHT.
    SET hdElevFar TO hdElev.
}

IF NOT hdInit() {
    kmSay("HUD: the HUD did not load (see above).", "C").
} ELSE {
    SET CONFIG:IPU TO MAX(CONFIG:IPU, 4000).
    SET hdRwyIx TO -1.                      // no runway (hdInit picked one): no overlay, no end switch
    SET hdRwyOn TO FALSE.
    SET hdRwyAuto TO FALSE.
    SET hdFinalOn TO FALSE.
    huGround().
    SET hdVis TO TRUE.

    GLOBAL huW IS GUI(240).
    SET huW:X TO 40.
    SET huW:Y TO 80.
    huW:ADDLABEL("<b>HUD</b>  " + SHIP:NAME).
    SET huEyePt TO hdEyePart().                 // (on another craft this names its own eye file: HD_EYE_CAL_FILE)
    IF huEyePt:LENGTH > 0 AND ADDONS:HASSUFFIX("HOLO") {
        IF ADDONS:HOLO:HASSUFFIX("HUDEYEINIT") { SET huEye TO huEyeInit() = "". }
    }
    LOCAL r1 IS huW:ADDHLAYOUT().
    GLOBAL huBHud IS r1:ADDBUTTON("HUD ON").
    SET huBHud:TOGGLE TO TRUE.
    SET huBHud:PRESSED TO TRUE.
    SET huBHud:ONTOGGLE TO { PARAMETER pr. SET hdVis TO pr. SET huBHud:TEXT TO CHOOSE "HUD ON" IF pr ELSE "HUD OFF". }.
    GLOBAL huBCam IS r1:ADDBUTTON("HUD CAM").
    SET huBCam:TOGGLE TO TRUE.
    SET huBCam:ONTOGGLE TO {
        PARAMETER pr.
        IF pr {
            IF hdCamSnap() {
                SET huMsg TO "".
            } ELSE {
                SET huMsg TO "No free camera (kOS StockCamera FREECAMERA).".
                SET huBCam:PRESSED TO FALSE.
            }
        } ELSE {
            hdCamRelease().
        }
        huInfo().
    }.
    LOCAL bQuit IS r1:ADDBUTTON("QUIT").
    SET bQuit:ONCLICK TO { SET huDone TO TRUE. }.
    IF huEye {
        LOCAL r2 IS huW:ADDHLAYOUT().
        LOCAL bF IS r2:ADDBUTTON("FWD").
        SET bF:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(0, 1). huEyeShow(). }.
        LOCAL bA IS r2:ADDBUTTON("AFT").
        SET bA:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(0, -1). huEyeShow(). }.
        LOCAL bU IS r2:ADDBUTTON("UP").
        SET bU:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(1, 1). huEyeShow(). }.
        LOCAL bD IS r2:ADDBUTTON("DOWN").
        SET bD:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(1, -1). huEyeShow(). }.
        LOCAL r3 IS huW:ADDHLAYOUT().
        LOCAL bL IS r3:ADDBUTTON("LEFT").
        SET bL:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(2, -1). huEyeShow(). }.
        LOCAL bR IS r3:ADDBUTTON("RIGHT").
        SET bR:ONCLICK TO { ADDONS:HOLO:HUDEYEMOVE(2, 1). huEyeShow(). }.
        LOCAL bS IS r3:ADDBUTTON("STEP").
        SET bS:ONCLICK TO { ADDONS:HOLO:HUDEYESTEP(). huEyeShow(). }.
        LOCAL bX IS r3:ADDBUTTON("RESET").
        SET bX:ONCLICK TO { ADDONS:HOLO:HUDEYERESET(). huEyeInit(). huEyeShow(). }.
        GLOBAL huLEye IS huW:ADDLABEL("").
        huEyeShow().
    } ELSE {
        kmSay("HUD: no eye buttons (" + (CHOOSE "no part to ride" IF huEyePt:LENGTH = 0 ELSE CHOOSE "no HoloHud.dll" IF NOT ADDONS:HASSUFFIX("HOLO") ELSE "an older HoloHud.dll")
            + ").", "I").
    }
    GLOBAL huLInfo IS huW:ADDLABEL("").
    huW:SHOW().
    kmSay("HUD: running on " + SHIP:NAME + " (" + hdGearMain:LENGTH + " main, " + hdGearNose:LENGTH
        + " nose wheels). QUIT in its window ends it.", "I").

    UNTIL huDone {
        SET hdCtlTxt TO CHOOSE "SAS" IF SAS ELSE "MAN".
        SET huSb TO MAX(0, MIN(1, SHIP:CONTROL:PILOTMAINTHROTTLE)) * H_SB_FULL.     // the throttle on the scale
        SET hdSb TO huSb.
        SET hdSbc TO huSb.
        huGround().
        hdTick().
        IF TIME:SECONDS >= huInfoT {
            SET huInfoT TO TIME:SECONDS + 1.
            huInfo().
        }
        WAIT 0.
    }
    hdClose().
    huW:DISPOSE().
    SET CONFIG:IPU TO huIpu.
    kmSay("HUD: closed.", "I").
}
