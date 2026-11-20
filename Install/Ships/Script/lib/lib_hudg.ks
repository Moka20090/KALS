// lib_hudg.ks -- THE HUD'S GUIDANCE SYMBOLS, on lib_hud.ks.
//  Symbols drawn: the flight director (the frozen TAEM square) and the GUIDANCE DIAMOND offset from it -- or from the
//  velocity vector in prefinal and A/L -- by the bank and Nz errors ("fly the FD onto the diamond"), the G-meter beside
//  the square, the GSI beside the altitude tape, the phase word on the speedbrake's row, ZOOM beside the control mode,
//  the messages at the top (GO CSS flashing, OTT STRT / OTT MEP steady), the PREFLARE TRIANGLES and the OGS CUE either
//  side of the velocity vector (A/L), and the BRAKING CUE after the nose gear.
//  This file adds its own slots to lib_hud's window after hdInit and draws them after each hdTick, from the record the
//  guidance fills (hdgRec). Before PRFNL the host also sets lib_hud's hdFdMode: lib_hud then hides its velocity vector
//  and pivots its pitch ladder on the frozen FD square. Standalone css_dap keeps the default.
//  HOST: RUNONCEPATH("0:/lib/lib_hudg.ks"). IF hdInit() { hdgInit(). }  then per loop tick: fill hdgRec, hdTick(). hdgTick().
//  hdgRec (all optional): "phase" word, "vv" TRUE in prefinal / A/L (the diamond rides the velocity vector), "bankDem"
//  the demanded bank (deg, RIGHT +: G4.9 phic's sense), "nzc" the total Nz demanded, "nzm" the measured Nz (g),
//  "herror" href - h (m; > 0 = below: the GSI rides up), "css" / "dm" the messages ("" = none), "zoom", "flare" /
//  "ogs" the triangles' flight path angles (deg, -999 = none), "decelTgt" / "decelAct" (m/s2; tgt < 0 = no cue),
//  "qaAct" / "qaCmd" (kPa deg: the ascent's q x |alpha| now and of the steering target; act < 0 = no cue).
//  Needs hud/sprites.txt (written by gen_hud.py) with diamond, fd, gsi, flare_tri_l / _r, decel_scale, decel_ptr_l / _r
//  (and qa_scale for the q x alpha cue: without it no cue).
@LAZYGLOBAL OFF.

// Placement constants the layout file does not carry, deg (HDG_DECEL_FULL: ft/s2)
GLOBAL HDG_TRI_DX_DEG IS 1.1.               // the triangles' offset either side of the velocity vector
GLOBAL HDG_DECEL_X_DEG IS 4.6.              // the braking cue's column right of the boresight
GLOBAL HDG_DECEL_TOP_DEG IS 1.0.            // the braking cue's top above the boresight
GLOBAL HDG_DECEL_H_DEG IS 3.0.              // the braking cue's height
GLOBAL HDG_DECEL_FULL IS 16.0.              // ft/s2 at the top of the braking cue
GLOBAL HDG_QA_FULL IS 60.0.                 // kPa deg at the top of the ascent's q x alpha cue (the braking cue's column,
                                            //   size and pointers; gen_hud.py QA_FULL)
GLOBAL HDG_QA_LIM IS 40.0.                  // kPa deg, the limit L (qa_scale's long tick): the actual pointer flashes above it
GLOBAL HDG_CUE_OFF_FT IS 50.                // ft, the HUD's height: below it neither the guidance diamond nor the
                                            //   preflare triangles / OGS cue, AUTO and CSS alike. A deviation: the
                                            //   real HUD drops them at about 75 ft; 50 ft makes the landing a
                                            //   little harder

GLOBAL HDG_YAW_K IS 1.0.                    // the ascent's yaw line, deg of line per deg of yaw error;
GLOBAL HDG_YAW_MIN IS 0.25.                 //   hidden under this;
GLOBAL HDG_YAW_MAX IS 5.0.                  //   at most this, flashing (2 Hz, hdgLit) there;
GLOBAL HDG_YAW_STEP IS 0.25.                //   the step between gen_hud.py's yawln_01 .. yawln_20
GLOBAL hgYawTab IS LIST().                  // the yaw line's sprites by length (empty: no yaw line)
GLOBAL hgFdPlain IS FALSE.                  // the FD square without its wings and tail (fd_sq; ops1q's ascent)
GLOBAL hgDiaOff IS FALSE.                   // no diamond or yaw line (ops1q's hand-off gap: no guidance to show)
GLOBAL sgYaw IS 0.
GLOBAL hdgOK IS FALSE.
GLOBAL hdgRec IS LEXICON().
GLOBAL hdgNext IS 0.
GLOBAL hdgGdLost IS FALSE.                   // SW 02 GUIDANCE LOST for the host's phase (hdgTick): the guidance-fed symbols blank
GLOBAL hdgLit IS TRUE.                      // the GO CSS / PITCH flash phase: 2 Hz from the HUD's clock (hdgTick)
GLOBAL hdgSp IS LEXICON().                  // sprite name -> lib_hud record
GLOBAL sgFd IS 0.
GLOBAL sgDia IS 0.
GLOBAL sgGsi IS 0.
GLOBAL pgTri IS LIST().                     // 4 slots: flare L / R, OGS L / R
GLOBAL hgTriTab IS LIST().                  // the triangles' rotated family ftri_000 ..; empty: the upright pair
GLOBAL sgDcS IS 0.
GLOBAL sgDcT IS 0.
GLOBAL sgDcA IS 0.
GLOBAL sgQaS IS 0.                          // the q x alpha cue: scale, demanded and actual pointers, the number above
GLOBAL sgQaT IS 0.
GLOBAL sgQaA IS 0.
GLOBAL tgQa IS 0.
GLOBAL tgNz IS 0.
GLOBAL tgPh IS 0.
GLOBAL tgZoom IS 0.
GLOBAL tgMsg IS 0.
GLOBAL tgDm IS 0.
GLOBAL hgFdV IS 1080.
GLOBAL hgDiaDeg IS 0.1.
GLOBAL hgDiaG IS 4.
GLOBAL hgNzDx IS 0.
GLOBAL hgNzDy IS 0.
GLOBAL hgGsiX IS 0.
GLOBAL hgGsiFull IS 5000.
GLOBAL hgGsiFine IS 500.
GLOBAL hgGsiHi IS 10000.
GLOBAL hgGsiLo IS 5000.
GLOBAL hgPhX IS 0.
GLOBAL hgPhY IS 0.
GLOBAL hgZoomX IS 0.
GLOBAL hgYtop IS 0.
GLOBAL hgDmDy IS 0.

FUNCTION hdgPx {                            // pixels for a size of deg degrees at the screen centre
    PARAMETER deg.
    RETURN H_FPX * TAN(deg).
}

FUNCTION hdgLayN {
    PARAMETER k, dflt.
    IF hdLay:HASKEY(k) { RETURN hdLay[k]. }
    RETURN dflt.
}

FUNCTION hdgInit {
    IF NOT hdOK { RETURN FALSE. }
    IF hdgOK { RETURN TRUE. }               // the GRTLS's HUD loaded it (lib_grdap); landRun's call keeps it
    hdgSp:CLEAR().                          // A second HUD (hdClose, hdInit) loads them again
    pgTri:CLEAR().
    FOR nm IN LIST("diamond", "fd", "gsi", "flare_tri_l", "flare_tri_r", "decel_scale", "decel_ptr_l", "decel_ptr_r") {
        IF NOT hdSpr:HASKEY(nm) {
            kmSay("HUDG: sprite " + nm + " missing -- reinstall Ships/Script/" + SCR_HUD, "C").
            RETURN FALSE.
        }
        hdgSp:ADD(nm, hdSpr[nm]).
    }
    IF hdSpr:HASKEY("fd_sq") { hdgSp:ADD("fd_sq", hdSpr["fd_sq"]). }   // the ascent's FD square (hgFdPlain)
    IF hdSpr:HASKEY("qa_scale") { hdgSp:ADD("qa_scale", hdSpr["qa_scale"]). }   // the ascent's q x alpha cue
    // the triangles rotating with the HUD: ftri_<th> every ANGLE_STEP deg (gen_hud.py); without the whole
    // family the upright flare_tri_l / _r
    hgTriTab:CLEAR().
    IF hdSpr:HASKEY("ftri_000") {
        FROM { LOCAL a IS 0. } UNTIL a >= 360 STEP { SET a TO a + H_STEP. } DO {
            IF hdSpr:HASKEY("ftri_" + hdPad3(a)) { hgTriTab:ADD(hdSpr["ftri_" + hdPad3(a)]). }
        }
        IF hgTriTab:LENGTH <> ROUND(360 / H_STEP) { hgTriTab:CLEAR(). }
    }
    hgYawTab:CLEAR().                       // the whole family or none
    LOCAL ny IS ROUND(HDG_YAW_MAX / HDG_YAW_STEP).
    FROM { LOCAL k IS 1. } UNTIL k > ny STEP { SET k TO k + 1. } DO {
        IF hdSpr:HASKEY("yawln_" + hdPad2(k)) { hgYawTab:ADD(hdSpr["yawln_" + hdPad2(k)]). }
    }
    IF hgYawTab:LENGTH <> ny { hgYawTab:CLEAR(). }
    SET hgFdV TO hdgLayN("FD_V", H_FDV).
    SET hgDiaDeg TO hdgLayN("DIA_DEG_PER_DEG", 0.1).
    SET hgDiaG TO hdgLayN("DIA_DEG_PER_G", 4).
    SET hgNzDx TO hdgLayN("NZ_DX", -hdgPx(1.2)).
    SET hgNzDy TO hdgLayN("NZ_DY", hdgPx(0.7)).
    SET hgGsiX TO hdgLayN("GSI_X", H_XA + 42).
    SET hgGsiFull TO hdgLayN("GSI_FULL_FT", 5000).
    SET hgGsiFine TO hdgLayN("GSI_FINE_FT", 500).
    SET hgGsiHi TO hdgLayN("GSI_HI_FT", 10000).
    SET hgGsiLo TO hdgLayN("GSI_LO_FT", 5000).
    SET hgPhX TO H_XM + hdgLayN("AUTO_W", 49.3).
    SET hgPhY TO hdgLayN("PH_Y", H_SB_YB + 10).
    SET hgZoomX TO H_XM + hdgLayN("ZOOM_DX", 62).
    SET hgYtop TO hdgLayN("YTOP", H_V0 - 42).
    SET hgDmDy TO hdgLayN("DM_DY", 24.5).
    // the slots, appended to lib_hud's window (the flow index keeps counting: hdPlace / hdText correct for it)
    SET sgFd TO hdImgSlot().
    SET sgDia TO hdImgSlot().
    SET sgGsi TO hdImgSlot().
    FROM { LOCAL k IS 0. } UNTIL k >= 4 STEP { SET k TO k + 1. } DO { pgTri:ADD(hdImgSlot()). }
    SET sgDcS TO hdImgSlot().
    SET sgDcT TO hdImgSlot().
    SET sgDcA TO hdImgSlot().
    SET tgNz TO hdTxtSlot(hdgLayN("NZ_FS", 18), 0, 0).
    SET tgPh TO hdTxtSlot(hdgLayN("PH_FS", 28), 1, 1).
    SET tgZoom TO hdTxtSlot(H_CTL_FS, 1, 0).
    SET tgMsg TO hdTxtSlot(hdgLayN("MSG_FS", 22), 0, 0).
    SET tgDm TO hdTxtSlot(hdgLayN("MSG_FS", 22), 0, 0).
    SET sgYaw TO hdImgSlot().               // the yaw line (the last slot: the others' flow kept)
    SET sgQaS TO hdImgSlot().
    SET sgQaT TO hdImgSlot().
    SET sgQaA TO hdImgSlot().
    SET tgQa TO hdTxtSlot(H_CTL_FS, 0, 0).
    SET hdgOK TO TRUE.
    hdgCsSetup().                           // the symbols' math to the KAL/S coprocessor (with lib_hud's)
    hdPaintSetup().                         // The painter's group again, with these slots (OFF: nothing)
    hdWinSetup().                           // The C# window again, with these slots (OFF: nothing)
    RETURN TRUE.
}

FUNCTION hdgGet {
    PARAMETER k, dflt.
    IF hdgRec:HASKEY(k) { RETURN hdgRec[k]. }
    RETURN dflt.
}

FUNCTION hdgGsiScale {                      // the GSI's scale, ft
    PARAMETER hft.
    IF hft >= hgGsiHi { RETURN hgGsiFull. }
    IF hft <= hgGsiLo { RETURN hgGsiFine. }
    RETURN hgGsiFine + (hft - hgGsiLo) / (hgGsiHi - hgGsiLo) * (hgGsiFull - hgGsiFine).
}

FUNCTION hdgBankNow {                       // the vessel's bank about the velocity, deg, RIGHT + (lib_land's bank0, negated)
    LOCAL vsn IS SHIP:VELOCITY:SURFACE:NORMALIZED.
    LOCAL upP IS VXCL(vsn, SHIP:UP:VECTOR).
    LOCAL topP IS VXCL(vsn, SHIP:FACING:TOPVECTOR).
    IF upP:MAG < 0.001 OR topP:MAG < 0.001 { RETURN 0. }
    LOCAL b IS VANG(upP, topP).
    IF VDOT(VCRS(upP:NORMALIZED, topP:NORMALIZED), vsn) < 0 { SET b TO -b. }
    RETURN -b.
}

// the C# side (lib_hud's HD_CS; ADDONS:HOLO:HUDGSETUP / HUDGTICK)
// hdgRec "yaw" (deg, RIGHT + = yaw right): the yaw error as a horizontal line out of the guidance diamond's side, a
// fly-to (the line on the right = yaw right) whose length shows the error: from the diamond's side (its ink edge at
// pu), HDG_YAW_K deg of line per deg, shortened to stay inside the field; placed by its ink's centre row on pv (the
// yawln sprites' ink sits a pixel below their anchor)
FUNCTION hdgYaw {
    PARAMETER pu, pv.
    LOCAL n IS 0.
    LOCAL ye IS 0.
    IF hdgRec:HASKEY("yaw") AND hgYawTab:LENGTH > 0 {
        SET ye TO hdgRec["yaw"] * HDG_YAW_K.
        IF ABS(ye) >= HDG_YAW_MIN { SET n TO MAX(1, MIN(hgYawTab:LENGTH, ROUND(ABS(ye) / HDG_YAW_STEP))). }
        IF ABS(ye) >= HDG_YAW_MAX AND NOT hdgLit { SET n TO 0. }
    }
    IF n > 0 {
        LOCAL ds IS hdgSp["diamond"].
        LOCAL x0 IS CHOOSE pu + ds[6] - ds[2] IF ye > 0 ELSE pu - ds[2] + ds[4].
        LOCAL room IS CHOOSE H_FR - 1 - x0 IF ye > 0 ELSE x0 - H_FL - 1.
        UNTIL n = 0 OR hgYawTab[MAX(n - 1, 0)][6] - hgYawTab[MAX(n - 1, 0)][4] <= room { SET n TO n - 1. }
        IF n > 0 {
            LOCAL yr IS hgYawTab[n - 1].
            hdBlit(sgYaw, yr, CHOOSE x0 + yr[2] - yr[4] IF ye > 0 ELSE x0 - yr[6] + yr[2], pv + yr[3] - (yr[5] + yr[7]) / 2).
            RETURN.
        }
    }
    hdHide(sgYaw).
}

FUNCTION hdgCsSetup {
    SET hdCsG TO FALSE.
    IF NOT hdCsOn { RETURN. }
    LOCAL er IS ADDONS:HOLO:HUDGSETUP.
    IF er = "" { SET hdCsG TO TRUE. } ELSE { hdCsOff("HUDGSETUP: " + er). }
}

FUNCTION hdgCsTick {
    LOCAL inp IS LIST(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR, SHIP:FACING:TOPVECTOR, hdgGdLost).   // The 4th = SW 02 GUIDANCE LOST (the C# body blanks what hdgBody blanks)
    LOCAL rr IS ADDONS:HOLO:HUDGTICK(inp).
    IF rr:ISTYPE("String") {                // nothing was written: kOS's own
        hdCsOff("HUDGTICK: " + rr).
        hdgBody().
        RETURN.
    }
    hdCsApply(rr).
}

FUNCTION hdgTick {
    IF NOT hdgOK OR NOT hdOK OR NOT hdShown { RETURN. }
    LOCAL now IS hdReal().
    IF now < hdgNext - 0.002 { RETURN. }
    SET hdgNext TO MAX(hdgNext, now - 1 / HD_MAX_HZ) + 1 / HD_MAX_HZ.
    // The flash: 2 Hz (0.25 s on, 0.25 s off) from the HUD's own clock, REALTIME (what the eye sees, even when the
    // game clock lags), whatever the update rate. The PITCH warning shares this phase.
    SET hdgLit TO MOD(FLOOR(now * 4), 2) = 0.
    // SW 02 GUIDANCE LOST for the host's phase (FLFX_PH): the guidance-fed symbols blank (hdgBody, and the C# body via hdgCsTick's 4th element)
    SET hdgGdLost TO FALSE.
    IF DEFINED FLFX_SWPROG { IF DEFINED FLFX_PH { SET hdgGdLost TO flfxSwGuid(FLFX_PH). } }
    IF hdCsG AND HD_CS {                    // the body's math in C#
        hdgCsTick().
        RETURN.
    }
    hdgBody().
}

// hdgTick's body after its clock
FUNCTION hdgBody {
    LOCAL vvMode IS hdgGet("vv", FALSE).
    // ---- the reference: the frozen FD square in TAEM, the velocity vector in prefinal / A/L; none after WOW
    LOCAL refOn IS FALSE.
    LOCAL ru IS H_U0.
    LOCAL rv IS hgFdV.
    IF NOT hdWow {
        IF vvMode {
            IF sFpm[2] <> HD_CLEAR {         // lib_hud shows the velocity vector (inside the field)
                SET refOn TO TRUE.
                SET ru TO gVVu.
                SET rv TO gVVv.
            }
            hdHide(sgFd).
        } ELSE {
            // the ascent's FD box without the ticks around it (the other FD boxes keep them): the
            // square alone while hgFdPlain
            SET refOn TO hdBlit(sgFd, CHOOSE hdgSp["fd_sq"] IF hgFdPlain AND hdgSp:HASKEY("fd_sq") ELSE hdgSp["fd"], ru, rv).
        }
    } ELSE {
        hdHide(sgFd).
    }
    LOCAL cueOn IS refOn AND sHft >= HDG_CUE_OFF_FT.
    IF cueOn {
        LOCAL du IS 0.
        LOCAL dv IS 0.
        IF hdgRec:HASKEY("diaDx") {
            // the ascent's: the host's offsets in HUD deg (right / up +), the diamond held inside the field
            LOCAL ds IS hdgSp["diamond"].
            SET du TO MAX(H_FL + 1 + ds[2] - ds[4] - ru, MIN(H_FR - 1 - ds[6] + ds[2] - ru, hdgPx(hdgRec["diaDx"]))).
            SET dv TO MAX(H_FT + 1 + ds[3] - ds[5] - rv, MIN(H_FB - 1 - ds[7] + ds[3] - rv, -hdgPx(hdgGet("diaDy", 0)))).
        } ELSE {
            SET du TO hdgPx(hgDiaDeg * (hdgGet("bankDem", 0) - hdgBankNow())).
            SET dv TO -hdgPx(hgDiaG * (hdgGet("nzc", 1) - hdgGet("nzm", 1))).
        }
        IF hgDiaOff OR hdgGdLost {
            hdHide(sgDia).
            hdHide(sgYaw).
        } ELSE {
            hdBlit(sgDia, hdgSp["diamond"], ru + du, rv + dv).
            hdgYaw(ru + du, rv + dv).
        }
        IF vvMode { hdHideT(tgNz). }
        ELSE { hdText(tgNz, "" + ROUND(hdgGet("nzm", 1), 1) + "G", ru + hgNzDx, rv + hgNzDy). }
    } ELSE {
        hdHide(sgDia).
        hdHide(sgYaw).
        hdHideT(tgNz).
    }
    // ---- the preflare triangles and the OGS cue: either side of the velocity vector, at the screen height of the
    //      flight path angle along the track
    LOCAL used IS 0.
    IF cueOn AND vvMode {
        LOCAL hdir IS VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE).
        IF hdir:MAG > 1 {
            SET hdir TO hdir:NORMALIZED.
            LOCAL dxT IS hdgPx(HDG_TRI_DX_DEG).
            LOCAL rhT IS VCRS(bU, hdir):NORMALIZED.   // the track's horizontal right, for the cues' own frame
            IF VDOT(rhT, bRight) < 0 { SET rhT TO V(0, 0, 0) - rhT. }
            FOR gk IN LIST("flare", "ogs") {
                LOCAL gm IS hdgGet(gk, -999).       // The flare / OGS triangles are open-loop (the runway and the vehicle state): they stay under SW 02
                IF gm > -900 {
                    hdProj(hdir * COS(gm) + SHIP:UP:VECTOR * SIN(gm)).
                    IF pOK {
                        IF hgTriTab:LENGTH > 0 {
                            // rotating with the HUD: either side of the FPA's point, each turned with the ladder
                            // (the right one = the left one + 180 deg). The axis is the cue's OWN elevation line
                            // through its point (hdFrame at gm along the track), not the ladder's last frame (fU):
                            // below the declutter, or with the horizon off the glass, the ladder frames nothing and
                            // the triangles would keep a stale tilt from higher up (the HAC's bank)
                            LOCAL cU IS pU.
                            LOCAL cV IS pV.
                            IF NOT hdFrame(gm, hdir, rhT, cU, cV) {
                                SET fUx TO 1.
                                SET fUy TO 0.
                            }
                            LOCAL ix IS hdSnapIx(ARCTAN2(0 - fUy, fUx), 360).
                            LOCAL nt IS hgTriTab:LENGTH.
                            hdBlit(pgTri[used], hgTriTab[ix], cU - dxT * fUx, cV - dxT * fUy).
                            hdBlit(pgTri[used + 1], hgTriTab[MOD(ix + ROUND(nt / 2), nt)], cU + dxT * fUx, cV + dxT * fUy).
                        } ELSE {
                            hdBlit(pgTri[used], hdgSp["flare_tri_l"], ru - dxT, pV).
                            hdBlit(pgTri[used + 1], hdgSp["flare_tri_r"], ru + dxT, pV).
                        }
                        SET used TO used + 2.
                    }
                }
            }
        }
    }
    hdHideFrom(pgTri, used).
    // ---- the GSI, with the tapes only (above the declutter, before WOW): fly-to
    IF (NOT hdWow) AND sHft > H_DECL AND hdgRec:HASKEY("herror") {   // The altitude error needle stays under SW 02
        LOCAL f IS MAX(-1, MIN(1, (hdgRec["herror"] / H_FTM) / hdgGsiScale(sHft))).
        hdBlit(sgGsi, hdgSp["gsi"], hgGsiX, H_VC - f * H_HALF).
        SET hdGsiOn TO TRUE.                // T1012: the altitude tag's R stands right of the GSI while it is drawn
    } ELSE {
        hdHide(sgGsi).
        SET hdGsiOn TO FALSE.
    }
    // ---- the phase word on the speedbrake's row, ZOOM beside the control mode
    hdText(tgPh, hdgGet("phase", ""), hgPhX, hgPhY).   // The phase word stays (only the command symbols blank)
    IF hdgGet("zoom", FALSE) { hdText(tgZoom, "ZOOM", hgZoomX, H_YC). } ELSE { hdHideT(tgZoom). }
    // ---- the messages: GO CSS flashes (2 Hz from the clock), the downmode stays, one line lower under GO CSS
    LOCAL css IS hdgGet("css", "").
    IF css <> "" AND hdgLit { hdText(tgMsg, css, H_U0, hgYtop). } ELSE { hdHideT(tgMsg). }
    LOCAL dm IS hdgGet("dm", "").
    IF dm <> "" { hdText(tgDm, dm, H_U0, hgYtop + (CHOOSE hgDmDy IF css <> "" ELSE 0)). } ELSE { hdHideT(tgDm). }
    // ---- the braking cue after the nose gear: demanded in from the left, actual from the right
    LOCAL dTgt IS CHOOSE -1 IF hdgGdLost ELSE hdgGet("decelTgt", -1).
    IF hdWong AND dTgt >= 0 {
        LOCAL x0 IS H_U0 + hdgPx(HDG_DECEL_X_DEG).
        LOCAL y1 IS H_V0 - hdgPx(HDG_DECEL_TOP_DEG).
        LOCAL y0 IS y1 + hdgPx(HDG_DECEL_H_DEG).
        hdBlit(sgDcS, hdgSp["decel_scale"], x0, y0).
        LOCAL ft IS MAX(0, MIN(1, dTgt / H_FTM / HDG_DECEL_FULL)).
        LOCAL fa IS MAX(0, MIN(1, hdgGet("decelAct", 0) / H_FTM / HDG_DECEL_FULL)).
        hdBlit(sgDcT, hdgSp["decel_ptr_l"], x0 - hdgPx(0.1), y0 - (y0 - y1) * ft).
        hdBlit(sgDcA, hdgSp["decel_ptr_r"], x0 + hdgPx(0.1), y0 - (y0 - y1) * fa).
    } ELSE {
        hdHide(sgDcS).
        hdHide(sgDcT).
        hdHide(sgDcA).
    }
    // ---- the ascent's q x alpha cue in the braking cue's place, after SRB sep (qaAct < 0 = none): the actual pointer
    // from the right (flashing above the limit), the steering target's from the left, both pinned at the top past the scale
    LOCAL qAct IS hdgGet("qaAct", -1).
    IF qAct >= 0 AND hdgSp:HASKEY("qa_scale") {
        LOCAL x0 IS H_U0 + hdgPx(HDG_DECEL_X_DEG).
        LOCAL y1 IS H_V0 - hdgPx(HDG_DECEL_TOP_DEG).
        LOCAL y0 IS y1 + hdgPx(HDG_DECEL_H_DEG).
        hdBlit(sgQaS, hdgSp["qa_scale"], x0, y0).
        LOCAL fc IS MAX(0, MIN(1, hdgGet("qaCmd", 0) / HDG_QA_FULL)).
        LOCAL fa IS MAX(0, MIN(1, qAct / HDG_QA_FULL)).
        IF hdgGet("qaCmd", 0) < 0 { hdHide(sgQaT). }       // T1001: no steering target (the guidance failed): the commanded pointer is hidden, the actual one stays
        ELSE { hdBlit(sgQaT, hdgSp["decel_ptr_l"], x0 - hdgPx(0.1), y0 - (y0 - y1) * fc). }
        IF qAct > HDG_QA_LIM AND NOT hdgLit { hdHide(sgQaA). }
        ELSE { hdBlit(sgQaA, hdgSp["decel_ptr_r"], x0 + hdgPx(0.1), y0 - (y0 - y1) * fa). }
        hdText(tgQa, "QA " + ROUND(qAct), x0, y1 - hdgPx(0.35)).
    } ELSE {
        hdHide(sgQaS).
        hdHide(sgQaT).
        hdHide(sgQaA).
        hdHideT(tgQa).
    }
}
