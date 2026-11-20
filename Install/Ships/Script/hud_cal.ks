@LAZYGLOBAL OFF.
// ============================================================================
//  HUD_CAL.KS  --  PUT THE HUD CAMERA'S EYE WHERE YOU WANT IT, AND SAVE IT.  NOT FLIGHT LOGIC.
// ============================================================================
//  It flies nothing and commands nothing: it snaps the HUD camera to the flight deck, draws the HUD as in flight,
//  and moves the eye where you click.
//  HOW TO RUN
//   1. Your craft in flight view (not IVA: IVA turns the free camera off), with no flight script running on this
//      CPU (a kOS CPU runs one program at a time). On the runway or on final, where the nose and the runway show,
//      is the easiest place; anywhere works.
//   2. In the kOS terminal:  RUNPATH("0:/hud_cal.ks").
//   3. The HUD CAMERA EYE window (top left; drag it anywhere off the HUD glass):
//        FWD / AFT, UP / DOWN, LEFT / RIGHT   move the eye one STEP (click STEP for 1 m, 0.25 m, 0.05 m);
//        the three boxes                      type an exact value, then Enter;
//        CENTER                               right = 0 (on the craft's centreline);
//        BUILT-IN                             back to the eye the scripts use without a saved one (CENTERED);
//        CENTERED / CDR WINDOW                the two presets: the centreline, or the commander's window;
//        SAVE                                 writes Ships/Script/hud_eye_cal.json: every HUD CAM after that
//                                             (land, css_dap, ops3q, ...) puts the eye there;
//        FORGET                               deletes it: HUD CAM goes back to the built-in eye;
//        FOV                                  the HUD CAM's field of view, 40, 60 or 70 deg (wider sees more, the
//                                             HUD smaller), saved at once to Ships/Script/hud_fov.txt; the HUD is
//                                             drawn for it from the next start (QUIT and run hud_cal again to see it);
//        QUIT                                 gives the stock camera back.
//      The values are metres from the forward fuselage part's origin, along its nose / roof / right axes. The
//      boresight (where the camera looks) does not change: only where it looks from.
//   4. The saved files are yours: an upgrade does not overwrite them and an uninstall leaves them. To share a good eye,
//      send the three numbers (logs/hud_eye.txt has a line for every SAVE).
// ============================================================================

RUNONCEPATH("0:/lib/lib_hud.ks").

// the window and its loop: pt the forward fuselage, hudOn TRUE when the HUD loaded (then it draws as in flight)
FUNCTION calRun {
    PARAMETER pt, hudOn.
    LOCAL steps IS LIST(1, 0.25, 0.05).
    LOCAL si IS 1.
    LOCAL done IS FALSE.
    LOCAL eo IS hdEyeOffset(pt, hdEyeFrame(pt)).
    LOCAL ex IS LIST(eo[0], eo[1], eo[2]).          // fwd, up, right: m from the part's origin
    LOCAL msg IS "Started from " + eo[3] + ".".

    LOCAL w IS GUI(330).
    SET w:X TO 20.
    SET w:Y TO 120.
    w:ADDLABEL("<b>HUD CAMERA EYE</b>  (m from the forward fuselage)").
    LOCAL tfs IS LIST().
    LOCAL names IS LIST("FWD", "UP", "RIGHT").
    FROM { LOCAL k IS 0. } UNTIL k >= 3 STEP { SET k TO k + 1. } DO {
        LOCAL row IS w:ADDHLAYOUT().
        LOCAL lb IS row:ADDLABEL(names[k]).
        SET lb:STYLE:WIDTH TO 70.
        tfs:ADD(row:ADDTEXTFIELD("")).
    }
    LOCAL bStep IS w:ADDBUTTON("").
    LOCAL r1 IS w:ADDHLAYOUT().
    LOCAL bFwd IS r1:ADDBUTTON("FWD").
    LOCAL bAft IS r1:ADDBUTTON("AFT").
    LOCAL r2 IS w:ADDHLAYOUT().
    LOCAL bUp IS r2:ADDBUTTON("UP").
    LOCAL bDn IS r2:ADDBUTTON("DOWN").
    LOCAL r3 IS w:ADDHLAYOUT().
    LOCAL bLt IS r3:ADDBUTTON("LEFT").
    LOCAL bRt IS r3:ADDBUTTON("RIGHT").
    LOCAL r4 IS w:ADDHLAYOUT().
    LOCAL bCtr IS r4:ADDBUTTON("CENTER").
    LOCAL bDef IS r4:ADDBUTTON("BUILT-IN").
    LOCAL r6 IS w:ADDHLAYOUT().                    // the presets
    LOCAL bPc IS r6:ADDBUTTON("CENTERED").
    LOCAL bPw IS r6:ADDBUTTON("CDR WINDOW").
    LOCAL r5 IS w:ADDHLAYOUT().
    LOCAL bSave IS r5:ADDBUTTON("SAVE").
    LOCAL bForget IS r5:ADDBUTTON("FORGET").
    LOCAL bFov IS w:ADDBUTTON("").
    LOCAL fovNow IS SCR_FOV.
    IF EXISTS(SCR_FOV_FILE) { SET fovNow TO ROUND(OPEN(SCR_FOV_FILE):READALL:STRING:SPLIT(CHAR(10))[0]:TRIM:TONUMBER(SCR_FOV)). }
    SET bFov:TEXT TO "FOV " + fovNow + " deg".
    LOCAL bQuit IS w:ADDBUTTON("QUIT").
    LOCAL lMsg IS w:ADDLABEL("").
    SET lMsg:STYLE:WORDWRAP TO TRUE.

    // the eye where ex says, the HUD's own boresight (hdCamFacing) and FOV
    LOCAL pose IS {
        LOCAL f IS hdEyeFrame(pt).
        SET hdCam:ANCHOR TO pt.
        SET hdCam:FOV TO H_FOV.
        SET hdCam:ENABLED TO TRUE.
        hdCam:SETPOSE(pt:POSITION + f:FOREVECTOR * ex[0] + f:TOPVECTOR * ex[1] + f:STARVECTOR * ex[2], hdCamFacing()).
        FROM { LOCAL k IS 0. } UNTIL k >= 3 STEP { SET k TO k + 1. } DO { SET tfs[k]:TEXT TO "" + ROUND(ex[k], 3). }
        SET bStep:TEXT TO "STEP " + steps[si] + " m".
        SET lMsg:TEXT TO msg.
    }.
    LOCAL nudge IS {
        PARAMETER k, sgn.
        SET ex[k] TO ex[k] + sgn * steps[si].
        SET msg TO "".
        pose().
    }.

    LOCAL typed IS {
        PARAMETER k, s.
        SET ex[k] TO s:TONUMBER(ex[k]).
        SET msg TO "".
        pose().
    }.
    SET tfs[0]:ONCONFIRM TO { PARAMETER s. typed(0, s). }.
    SET tfs[1]:ONCONFIRM TO { PARAMETER s. typed(1, s). }.
    SET tfs[2]:ONCONFIRM TO { PARAMETER s. typed(2, s). }.
    SET bStep:ONCLICK TO { SET si TO MOD(si + 1, steps:LENGTH). pose(). }.
    SET bFwd:ONCLICK TO { nudge(0, 1). }.
    SET bAft:ONCLICK TO { nudge(0, -1). }.
    SET bUp:ONCLICK TO { nudge(1, 1). }.
    SET bDn:ONCLICK TO { nudge(1, -1). }.
    SET bLt:ONCLICK TO { nudge(2, -1). }.
    SET bRt:ONCLICK TO { nudge(2, 1). }.
    SET bCtr:ONCLICK TO { SET ex[2] TO 0. SET msg TO "". pose(). }.
    SET bDef:ONCLICK TO {
        LOCAL d IS CHOOSE HD_EYE_DEF IF HD_EYE_DEF:LENGTH = 3 ELSE hdEyeBounds(pt, hdEyeFrame(pt)).
        SET ex TO LIST(d[0], d[1], d[2]).
        SET msg TO "The built-in eye (not saved).".
        pose().
    }.
    SET bPc:ONCLICK TO { LOCAL d IS HD_EYE_PRESETS["CENTERED"]. SET ex TO LIST(d[0], d[1], d[2]). SET msg TO "Preset CENTERED (not saved).". pose(). }.
    SET bPw:ONCLICK TO { LOCAL d IS HD_EYE_PRESETS["CDR WINDOW"]. SET ex TO LIST(d[0], d[1], d[2]). SET msg TO "Preset CDR WINDOW (not saved).". pose(). }.
    SET bSave:ONCLICK TO {
        WRITEJSON(LEXICON("fwd", ROUND(ex[0], 3), "up", ROUND(ex[1], 3), "star", ROUND(ex[2], 3), "part", pt:NAME),
                  HD_EYE_CAL_FILE).
        IF DEFINED SOCK_LOG { IF SOCK_LOG { LOG TIME:SECONDS + " SAVED by hud_cal: " + ROUND(ex[0], 3) + " fwd " + ROUND(ex[1], 3) + " up "
            + ROUND(ex[2], 3) + " right of " + pt:NAME + "'s origin" TO "0:/logs/hud_eye.txt". } }
        SET msg TO "Saved: every HUD CAM now uses this eye.".
        pose().
    }.
    SET bForget:ONCLICK TO {
        IF EXISTS(HD_EYE_CAL_FILE) { DELETEPATH(HD_EYE_CAL_FILE). }
        SET msg TO "Forgotten: HUD CAM uses the built-in eye (this view stays until you move it).".
        pose().
    }.
    SET bFov:ONCLICK TO {
        // the next field of view that has a set on this screen
        LOCAL k IS SCR_FOVS:FIND(fovNow).
        LOCAL nxt IS fovNow.
        FROM { LOCAL j IS 1. } UNTIL j > SCR_FOVS:LENGTH STEP { SET j TO j + 1. } DO {
            LOCAL f IS SCR_FOVS[MOD(k + j, SCR_FOVS:LENGTH)].
            IF nxt = fovNow AND f <> fovNow AND EXISTS("0:/" + scrHudDir(SCR_W, SCR_H, f) + "hud_layout.txt") { SET nxt TO f. }
        }
        IF nxt = fovNow {
            SET msg TO "No other field of view has a HUD set on this screen (the installer builds them).".
        } ELSE {
            SET fovNow TO nxt.
            IF EXISTS(SCR_FOV_FILE) { DELETEPATH(SCR_FOV_FILE). }
            LOG fovNow TO SCR_FOV_FILE.
            SET bFov:TEXT TO "FOV " + fovNow + " deg".
            SET msg TO "FOV " + fovNow + " deg saved: QUIT and run hud_cal again to see the HUD drawn for it.".
        }
        pose().
    }.
    SET bQuit:ONCLICK TO { SET done TO TRUE. }.

    w:SHOW().
    pose().
    UNTIL done {
        IF hudOn { hdTick(). }
        WAIT 0.
    }
    w:DISPOSE().
}

PRINT "HUD CAL: loading the HUD...".
LOCAL calHud IS hdInit().
IF NOT calHud { PRINT "HUD CAL: the HUD did not load (see above); the camera still moves, without the symbols.". }
IF NOT hdCamOK AND ADDONS:HASSUFFIX("CAMERA") {
    IF ADDONS:CAMERA:HASSUFFIX("FREECAMERA") {
        SET hdCam TO ADDONS:CAMERA:FREECAMERA.
        SET hdCamOK TO TRUE.
    }
}
LOCAL calPt IS hdEyePart().
IF NOT hdCamOK {
    PRINT "HUD CAL: no free camera (the kOS StockCamera addon's FREECAMERA) -- nothing to calibrate.".
} ELSE IF calPt:LENGTH = 0 {
    PRINT "HUD CAL: this vessel has no forward fuselage (" + HD_EYE_PART + ") -- nothing to calibrate.".
} ELSE {
    calRun(calPt[0], calHud).
}
hdCamRelease().
hdClose().
PRINT "HUD CAL: done.".

