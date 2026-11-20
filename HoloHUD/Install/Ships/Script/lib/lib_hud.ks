@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_HUD.KS  --  the HUD, drawn live
// ============================================================================
//  The head-up display for a flight script (css_dap and landRun), drawn live in a kOS GUI window:
//  pre-rendered sprites placed at whole pixels, rotated families every 2 deg, anything leaving the combiner field
//  hidden whole. Reads hud_layout.txt (every px constant), hud_runways.txt (the runway table) and the sprite images
//  from the screen's HUD folder (lib_screen.ks: hud/ at 3840x2160; each rotated family in a sub-folder named in
//  sprites.txt), all written by gen_hud.py.
//  Draws: the boresight; the velocity vector; the horizon and the pitch ladder (rotating about the velocity vector;
//  rungs only above the 4000 ft declutter); the conformal runway overlay (AG4 toggles it; the host's RWY button steps
//  through the table, Sol's six + the 22 ELS ends, nearest first); the KEAS and altitude tapes (below the declutter
//  two digital values ride the velocity vector instead); the speedbrake actual / command; the control mode (CSS / AUTO).
//  After main-gear touchdown (USA005512 Figs 4-19 / 4-20): no velocity vector, KEAS at the boresight, the groundspeed
//  ("G150") once the nose gear is down. The guidance's symbols (diamond, GSI, phase word, messages, ...) are drawn by
//  lib_hudg.ks.
//  Host: RUNONCEPATH("0:/lib/lib_hud.ks"). IF hdInit() {...}; every tick of its main loop hdTick() with hdCtlTxt /
//  hdSb / hdSbc set (the brake in the orbiter's degrees, 0-98.6); hdCamSnap() / hdCamRelease() from its button;
//  hdClose() at the end; hdRwyName() / hdRate / hdCost for its readout.
// ============================================================================

// ---------------------------------------------------------------- configuration
RUNONCEPATH("0:/lib/lib_screen.ks").        // SCR_HUD: the HUD's folder for this screen
IF NOT (DEFINED HD_NO_RWY) { GLOBAL HD_NO_RWY IS FALSE. }      // TRUE (hud.ks): no runway table, no Cape, no AG4 trigger
IF NOT HD_NO_RWY { RUNONCEPATH("0:/lib/lib_cape.ks"). }      // the SLF where the Katniss Cape is (capeLine)
GLOBAL HD_DIR IS SCR_HUD.                   // image paths: relative to the ARCHIVE (Ships/Script); hud/ at 3840x2160
GLOBAL HD_ARCH IS "0:/" + SCR_HUD.          // file reads
GLOBAL HD_OFF_X IS 2.5.                     // x offset of the texts (hdTxtSlot); a sprite needs none (hdImgSlot)
GLOBAL HD_OFF_Y IS 2.5.                     // y offset of the texts (hdTxtSlot), with HD_TXT_DY
GLOBAL HD_TXT_DY IS 7.                      // px: every label draws this far low
GLOBAL HD_FLOW_PX IS 1.0.                   // the Nth child of the layer starts N px low
GLOBAL HD_MAX_HZ IS 25.                     // updates per real second, at most (as on the orbiter)
GLOBAL HD_EYE_FWD IS 10.                    // the flight-deck eye point, m: FROM THE C.G. -- only on a vessel with
GLOBAL HD_EYE_UP IS 1.5.                    //   no HD_EYE_PART (another craft); the orbiter's is HD_EYE_PART_*
// The eye rides the FORWARD FUSELAGE part (FREECAMERA ANCHOR = the part: its pose is kept in the part's own space), so
// no c.g. shift moves it; an eye from the c.g. moves with the c.g. (1.6 m between cgFore -9.6 and -11.2). The offset,
// in m, from the PART'S ORIGIN along the PART'S AXES (PART:FACING: fore = the nose, top = the roof; the part model's
// +Y and -Z, x 1.02 rescale). The part: the nose's skin 0.60 m up at the origin, the windshield from 0.70 m up at 0.0
// to 1.45 m up at 0.9 m aft, the roof 1.47 m up. The boresight does not depend on the eye (hdCamFacing).
GLOBAL HD_EYE_PART IS "benjee10.shuttle.forwardfuselage".   // PART:NAME, lower case, "_" read as "."
GLOBAL HD_EYE_PART_FWD IS 1.6.              // m ahead of the part's origin, along the part's nose axis
GLOBAL HD_EYE_PART_UP IS 1.0.               // m above the part's origin, along the part's top axis
// The eye from the part's BOUNDS (hdCamSnap): HD_EYE_NOSE_FRAC of its length back from its nose tip, HD_EYE_ROOF_UP
// above its highest point (the cabin roof): ahead of the windshield, above the nose, outside the shell (the view of the
// Edwards approach photo). An eye at a fixed offset from the part's origin sits inside its shell (at FWD 0.4 and 1.6
// only the window frames draw): HD_EYE_PART_FWD / _UP only if the bounds read implausibly.
GLOBAL HD_EYE_NOSE_FRAC IS 0.2.
GLOBAL HD_EYE_ROOF_UP IS 0.3.               // m
// hud_cal.ks moves the eye freely and SAVE writes it to this file: the offset from the forward fuselage's origin along
// its nose / roof / right axes, m. The file wins over everything below; the release does not ship it, so a player's
// own calibration survives an upgrade (and the uninstall leaves it). HD_EYE_DEF: the built-in calibration, LIST(fwd,
// up, right) in m, used when there is no file; empty = the bounds eye.
GLOBAL HD_EYE_CAL_FILE IS "0:/hud_eye_cal.json".
// The two presets the release ships: the centred one is the built-in eye, and hud_cal.ks offers both (SAVE keeps the
// one picked).
GLOBAL HD_EYE_PRESETS IS LEXICON("CENTERED", LIST(-0.27, 0.963, 0), "CDR WINDOW", LIST(-0.37, 0.963, -0.4)).
GLOBAL HD_EYE_DEF IS HD_EYE_PRESETS["CENTERED"].
// Any aircraft: on a craft without the forward fuselage the eye rides the part it is flown from (hdAnyPart), its eye
// file is the craft's own (HD_EYE_CAL_FILE then names it: hud_cal.ks saves there) and the orbiter's built-in eye does
// not apply (HD_EYE_DEF emptied: the bounds eye)
GLOBAL hdEyeAny IS FALSE.
GLOBAL HD_RUNG_N IS 9.                      // rung slots
GLOBAL HD_TAPE_N IS 4.                      // tick / number slots per tape
GLOBAL HD_RWY_N IS 28.                      // runway segment slots
GLOBAL HD_PAD IS 200.                       // px of window around the glass (sprite halves, label boxes, the flow)
GLOBAL HD_FONT IS "".                       // the text's font by its name in the game; "" = kOS's default (Arial)
GLOBAL HD_FONT_FILE IS "HUD Stroke".        // the HUD font by the end of its name; "" = Arial (hdFindFont)
GLOBAL HD_FONT_SET IS "HUD Stroke Wide ".   // a font per size, "<this>NNN", stroke NNN / 1000 em; "" = none
GLOBAL HD_PEN_PX IS 2.66.                   // px at 2160 px high, each text slot's stroke (hdTxtFont)
GLOBAL hdFontSet IS LIST().                 // the set in the game: LIST(NNN, its name) each (hdFindFont)
GLOBAL HD_FK IS 1.                          // the font size per layout size: 1 in Arial (hdTxtSize)
GLOBAL HD_FASC IS 0.95.                     // x font size: the label top to the baseline (va 1; Arial: a guess)
GLOBAL HD_FCTR IS 0.62.                     // x font size: the label top to the capitals' middle (va 0; Arial: a guess)
GLOBAL hdB0 IS "<b>".                       // the text's bold tags: Arial in <b>, the HUD font at its own weight
GLOBAL hdB1 IS "</b>".
GLOBAL HD_RADALT_FT IS 5000.                // ft: the radar altimeter's height (and its R) below this (USA005512 Fig 4-13)
GLOBAL HD_RAD_GAP_PX IS 6.                  // px: the tape mode's R this far right of the GSI's ink
GLOBAL HD_WOW_M IS 0.3.                     // a gear this close to the ground (radar), m...
GLOBAL HD_WOW_S IS 0.5.                     // ...for this long, s = weight on wheels
GLOBAL HD_BOUNCE_M IS 2.                    // the main gear back above this: airborne again (a bounce), m
GLOBAL HD_ALT_OFS_FT IS 0.                  // the gear height's calibration, ft (on the runway it must read 0)
GLOBAL HD_ALT_TAU IS 1.0.                   // s: a change of the altitude's source blends out with this time constant
GLOBAL HD_RWY_FT IS 5000.                   // ft above the runway: ALT MODE RWY (its 'W') below this only
// ALT MODE RWY over the runway: the table's threshold elevation is not the pavement under the wheels (the runway's own
// slope; the mains roll within 0.6 m of the table at most sites, BDA's 2.9 m above it on some loads), so low over the
// runway the height blends into the radar's (the pavement itself, HD_WOW_M at contact): in full HD_RWY_RA_X m past the
// threshold and below HD_RWY_RA_LO_FT, none above HD_RWY_RA_HI_FT or off the runway (hdRwyW)
GLOBAL HD_RWY_RA_HI_FT IS 200.
GLOBAL HD_RWY_RA_LO_FT IS 50.
GLOBAL HD_RWY_RA_X IS 150.
GLOBAL HD_FINAL_FT IS 12000.                // ft: the final-approach runway switch works below this (hdFinalSwitch)
GLOBAL HD_FINAL_KM IS 25.
GLOBAL HD_FINAL_DEG IS 20.
// The HUD's math in C#: hdState's logic and all of hdRender (the ladder, the runway overlay, the tapes, the fixed
// symbols), and lib_hudg's hdgTick body, run in the Holo HUD addon (HoloHud.dll, ADDONS:HOLO:HUDSTATE / HUDRENDER / HUDGTICK). kOS
// keeps the game reads (hdCsIn, hdCsPos), hdRunwayElev, hdGearBounds, hdFinalSwitch and every widget write (hdCsApply
// applies the ones the addon returns). On ANY addon failure the switches turn off for the flight and kOS draws
// (HD_CS_ERR says why).
IF NOT (DEFINED HD_CS) { GLOBAL HD_CS IS TRUE. }                // the HUD's math in C#; SET HD_CS TO FALSE. first = kOS
IF NOT (DEFINED HD_CS_AP) { GLOBAL HD_CS_AP IS TRUE. }          // T680 S3: hdCsApply's writes in C# (HDAPPLY) when there
GLOBAL hdCsAp IS FALSE.
GLOBAL HD_CS_AP_ERR IS "".
IF NOT (DEFINED HD_CS_CHECK) { GLOBAL HD_CS_CHECK IS FALSE. }   // kOS draws, C# shadows on the same reads (wins over HD_CS)
GLOBAL HD_CS_ERR IS "".                     // why the C# math went off ("" = it did not)
GLOBAL HD_CS_STATE IS "kOS".                // "C#", "CHECK" or "kOS (<why>)": for the host's readout
GLOBAL HD_CS_WORST IS 0.                    // CHECK: the worst difference so far (0 = bit for bit), HD_CS_WKEY where
GLOBAL HD_CS_WKEY IS "".
GLOBAL HD_CS_NCHK IS 0.                     // CHECK: the updates compared
GLOBAL hdCsOn IS FALSE.                     // lib_hud's math in C# (hdCsSetup)
// T680 S2 THE PAINTER for the HUD (coproc Paint.cs, ADDONS:KALS:PAINTREG / PAINTMODE / PAINTSTATE; lib_taemdisp's
// TD_PAINT for the TAEM pages): the slot labels drawn by C# inside kOS's window, at one placeholder label (hdBox's last
// child), the slots' 1 x 1 boxes hidden from kOS's layout. HD_PAINT: 0 OFF (the default until SAIL's CHECK + A/B proof:
// kOS draws as before, nothing is created), 1 CHECK (kOS draws; C# compares every label's real rect with its own:
// KSP.log "[KalsPaint] HUD: CHECK worst .. px"), 2 PAINT, 3 AB (PAINT and kOS in turn every 2 s, for the screenshot
// diff). Any failure: kOS draws (HD_PAINT_STATE says why). hdgInit's slots come later: it registers the group again.
IF NOT (DEFINED HD_PAINT) { GLOBAL HD_PAINT IS 0. }
GLOBAL HD_PAINT_STATE IS "OFF".
GLOBAL hdPaintReg IS FALSE.                 // the group "HUD" registered with the painter (HD_PAINT > 0 at hdInit)
// T730 S1a THE HUD DRAWN BY C# (coproc/HudWin.cs, ADDONS:KALS:HWREG / HWMODE / HWDRAW / HWSYNC / HWSHOW / HWSTATE): C# keeps
// the slot table and draws it itself in its own OnGUI pass; kOS's hdHud window is hidden while it does. HD_WIN: 0 OFF (the
// default until SAIL's CHECK + A/B proof: kOS draws as before, nothing is created), 1 CHECK (kOS draws, the table is
// compared with every real rect: KSP.log "[KalsHudWin] mode CHECK: worst .. px"), 2 WIN (C# draws), 3 AB (WIN and kOS in
// turn every 2 s, for the screenshot diff). Needs the C# HUD math (HD_CS on, HD_CS_CHECK off): its op lists are what C#
// takes (hdCsApply -> HWDRAW). Any failure: kOS draws (HD_WIN_STATE says why). Excludes the painter (HD_PAINT forced 0).
IF NOT (DEFINED HD_WIN) { GLOBAL HD_WIN IS 0. }
GLOBAL HD_WIN_STATE IS "OFF".
GLOBAL hdWinReg IS FALSE.                   // the window registered with C# (HD_WIN > 0 at hdInit)
GLOBAL hdOrd IS LIST().                     // the slots in creation (= kOS's draw) order: LIST(label, flow index)
GLOBAL hdPhs IS LIST().                     // the placeholders made so far: LIST(label, flow index); the last is live
GLOBAL hdCsG IS FALSE.                      // lib_hudg's too (its hdgCsSetup)
GLOBAL hdInOn IS FALSE.                     // CHECK: kOS's own hdRunway reads hdInPos (what the shadow got), not the game
GLOBAL hdInPos IS LIST().

// ---------------------------------------------------------------- state
GLOBAL hdOK IS FALSE.
GLOBAL hdAg4 IS FALSE.                      // AG4's trigger armed (once: an hdInit after hdClose added a second)
GLOBAL hdLay IS LEXICON().                  // hud_layout.txt
GLOBAL hdSpr IS LEXICON().                  // name -> LIST(path, size, ax, ay, ink l, t, r, b)
GLOBAL hdHzTab IS LIST().                   // sprite records by angle step
GLOBAL hdRpTab IS LIST().
GLOBAL hdRnTab IS LIST().
GLOBAL hdRwyTab IS LIST().                  // the four runway segment families, 90 angle steps each
GLOBAL hdSegL IS LIST().                    // their lengths, px (96 32 12 6)
GLOBAL hdRwys IS LIST().                    // LIST(site, name, threshold, hdg, len, wid, elev, slope, far, x_ogs,
                                            //      x_igs, els)
GLOBAL hdOther IS LIST().                   // per runway end: the index of the same runway's other end
GLOBAL hdRwyIx IS -1.
GLOBAL hdRwyAuto IS TRUE.                   // picked by hdPickRunway (landRun: FALSE -- it sets the landing runway)
GLOBAL hdFinalOn IS TRUE.                   // the final-approach end switch (landRun: FALSE -- the landing runway is fixed)
GLOBAL hdFdMode IS FALSE.                   // the orbiter's TAEM HUD (landRun, before PRFNL): no velocity vector, the
                                            //   ladder about the frozen FD square
GLOBAL hdAzOn IS FALSE.                     // the ladder on a vertical plane: the launch azimuth's (ops1q's stage 1), a
                                            //   split-S's turn plane (ops1q, ops6q)
GLOBAL hdAzN IS V(0, 0, 0).                 // that plane's normal (horizontal), the host's each tick
GLOBAL hdAzPit IS -99.                      // deg: the pitch the line marks on that plane (below -90: through the FD box)
GLOBAL hdAzRoll IS FALSE.                   // the roll program done (the host's): the line's gap under the cross, else
                                            //   straight above or below it
GLOBAL hdGapU IS 0.                         // hdAzGap's result: the line's gap, screen px
GLOBAL hdGapV IS 0.
GLOBAL hdAzUx IS 1.                         // hdAzLine's direction on the glass (hdAzUSet), for the rungs (hdAzRung)
GLOBAL hdAzUy IS 0.
GLOBAL hdAzUOk IS FALSE.
GLOBAL hdRwyOn IS TRUE.                     // the overlay (AG4)
GLOBAL hdPts IS LIST().                     // the picked runway: threshold L / R, far L / R, OGS aim, IGS aim
GLOBAL hdThr IS LATLNG(0, 0).
GLOBAL hdElev IS 0.
GLOBAL hdElevFar IS 0.
GLOBAL hdRwyFx IS 0.                        // 0..1: over the picked runway, ramped in over HD_RWY_RA_X (hdRunwayElev)
GLOBAL hdElevT IS -1000.
GLOBAL hdSwitchT IS -1.
GLOBAL hdHud IS 0.
GLOBAL hdBox IS 0.
GLOBAL hdChildN IS 0.
GLOBAL hdWinX IS 0.
GLOBAL hdWinY IS 0.
GLOBAL hdShown IS FALSE.
GLOBAL hdVis IS TRUE.                       // the crew's HUD button (lib_dap dBtnHud): FALSE hides the HUD
GLOBAL hdHasReal IS KUNIVERSE:HASSUFFIX("REALTIME").
GLOBAL hdCamOK IS FALSE.
GLOBAL hdCam IS 0.
GLOBAL hdNextUpd IS 0.
GLOBAL hdLadWin IS 20.                      // deg about the camera axis a rung / the runway can reach the glass from
GLOBAL hdGlassHP IS LIST().                 // the glass as inward half-planes LIST(nu, nv, c): inside iff nu u + nv v >= c
GLOBAL hdGearMain IS LIST().
GLOBAL hdGearNose IS LIST().
GLOBAL hdBndMain IS LIST().
GLOBAL hdBndNose IS LIST().
GLOBAL hdBndT IS -1000.
GLOBAL hdGearN IS -1.                           // T901: SHIP:PARTS:LENGTH when hdFindGear ran
GLOBAL hdGearChkT IS -1.                        // T901: the game time hdGearBounds last compared the part count
GLOBAL hdWow IS FALSE.                      // main gear on the ground
GLOBAL hdWong IS FALSE.                     // nose gear on the ground
GLOBAL hdWowT IS -1.
GLOBAL hdWongT IS -1.
// what the host sets before hdTick
GLOBAL hdCtlTxt IS "AUTO".
GLOBAL hdSb IS 0.                           // speedbrake actual / command, the orbiter's deg (0-98.6)
GLOBAL hdSbc IS 0.
GLOBAL hdSpdMode IS 0.                      // the speed tape: 0 KEAS, 1 VI (the ascent after SRB SEP), 2 VHH (an RTLS)
GLOBAL hdSpdV IS 0.                         // VI or VHH (signed), m/s (hdSpdMode 1 / 2)
// readouts for the host
GLOBAL hdRate IS 0.                         // updates per real second
GLOBAL hdCost IS 0.                         // opcodes per update (the host's per-tick trigger included)
GLOBAL hdCostSum IS 0.
GLOBAL hdCostN IS 0.
GLOBAL hdWinT0 IS 0.
// drawing flags (a group hidden once, not every update)
GLOBAL hdHzOn IS TRUE.
GLOBAL hdRungHi IS 99.
GLOBAL hdSeg IS 0.
GLOBAL hdSegHi IS 99.
GLOBAL hdRwyVis IS TRUE.
GLOBAL hdBoxOn IS FALSE.
GLOBAL hdStaticOn IS FALSE.
GLOBAL hdBoreOn IS FALSE.
GLOBAL hdConfOn IS TRUE.
// the layout (hdHoist), as plain globals: a lexicon read per use costs more
GLOBAL H_STEP IS 2.
GLOBAL H_FOV IS 60.
GLOBAL H_FPX IS 1870.
GLOBAL H_U0 IS 1920.
GLOBAL H_V0 IS 850.
GLOBAL H_VS IS 1080.
GLOBAL H_CAMP IS 7.
GLOBAL H_FL IS 0.
GLOBAL H_FT IS 0.
GLOBAL H_FR IS 0.
GLOBAL H_FB IS 0.
GLOBAL H_LAD_FB IS 0.                       // the ladder's floor, px (hdHoist): no horizon segment, rung or number
                                            //   below it -- clear of the speedbrake scale, the phase word, AUTO / CSS
GLOBAL H_FDV IS 0.
GLOBAL H_LAD_ALONG IS 0.
GLOBAL H_LAD_UP IS 0.
GLOBAL H_LAD_FS IS 17.
GLOBAL H_HZ_GAP IS 0.
GLOBAL H_HZ_SEGS IS 8.
GLOBAL H_HZ_SEG IS 0.
GLOBAL H_VC IS 0.
GLOBAL H_HALF IS 0.
GLOBAL H_XS IS 0.
GLOBAL H_XA IS 0.
GLOBAL H_TAPE_KT IS 0.
GLOBAL H_TAPE_FT IS 0.
GLOBAL H_PER_KT IS 0.
GLOBAL H_PER_FT IS 0.
GLOBAL H_TAPE_FS IS 18.
GLOBAL H_BOX_KX IS 0.
GLOBAL H_BOX_AX IS 0.
GLOBAL H_BOX_Y IS 0.
GLOBAL H_DECL IS 4000.
// TRUE: always the above-declutter mode, on the ground too (the tapes, the full ladder about the velocity vector):
// the drawing ignores the height and the gear (hdWow / hdWong are still computed). Only hud.ks sets it.
GLOBAL hdNoDecl IS FALSE.
GLOBAL H_DIG_FS IS 20.
GLOBAL H_SB_B0 IS 0.
GLOBAL H_SB_B1 IS 0.
GLOBAL H_SB_YB IS 0.
GLOBAL H_SB_TIP IS 0.
GLOBAL H_SB_FULL IS 98.6.
GLOBAL H_XM IS 0.
GLOBAL H_YC IS 0.
GLOBAL H_CTL_FS IS 20.
GLOBAL H_AIM_R IS 0.
GLOBAL H_AIM_MIN IS 0.
GLOBAL H_ZNEAR IS 1.
GLOBAL H_GTOP IS 0.
GLOBAL H_GHW IS 0.
GLOBAL H_OVL IS 4.
GLOBAL H_CLIP IS 3.
GLOBAL H_HSTROKE IS 1.5.
GLOBAL H_VV_HW IS 0.
GLOBAL H_VV_TOP IS 0.
GLOBAL H_VV_GAP IS 0.
GLOBAL H_RHO0 IS 1.225.
GLOBAL H_KT IS 1.943844.
GLOBAL H_FTM IS 0.3048.
GLOBAL H_COL IS "#90ff97".
GLOBAL H_MONO IS 0.602.
GLOBAL H_BORE_DX IS 0.
GLOBAL H_BORE_DY IS 0.
GLOBAL SP_BORE IS 0.
GLOBAL SP_FPM IS 0.
GLOBAL SP_AIM IS 0.
GLOBAL SP_TICK IS 0.
GLOBAL SP_BOX IS 0.
GLOBAL SP_SBSCALE IS 0.
GLOBAL SP_SBDN IS 0.
GLOBAL SP_SBUP IS 0.
GLOBAL HD_CLEAR IS HD_DIR + "clear.png".
// the state of this update
GLOBAL hdLadKey IS "".                      // the ladder's last picture key (the ladder is redrawn only when it changes)
GLOBAL HD_LAD_DEL_EL IS 0.02.               // deg of the camera's elevation that redraws the ladder...
GLOBAL HD_LAD_DEL_RL IS 0.05.               // ...deg of its roll
GLOBAL hdTapeKK IS -99999.                  // the KEAS tape's last pixel offset
GLOBAL hdTapeKA IS -99999.                  // the altitude tape's
GLOBAL sHftT IS -1E9.                       // T862b: TIME:SECONDS of sHft's last write (the DAP's staleness test: no write for DAP_HUD_STALE_S = the HUD is not measuring)
GLOBAL sHft IS 99999.                       // the displayed height, ft (high until the first update: a host reading it
                                            //   for main-gear contact must not see 0 before the HUD has measured)
GLOBAL sRad IS FALSE.                       // TRUE: the displayed height is the radar altimeter's
GLOBAL sHdisp IS 99999.                     // the HUD's altitude (the tape, the readout), ft: by ALT MODE (hdAltPick). sHft stays
                                            //   the logic's height
GLOBAL hdRadX IS 0.                         // px: the tape mode's R, its left edge (right of the GSI's column)
// the crew's ALT MODE (lib_dap's button in OPS 6, lib_ascdisp's in OPS 1): "RDR" the radar's height below HD_RADALT_FT,
// ASL above it; "RWY" the height above the runway; OPS 1 (hdAltAsc): "RDR" the radar's at every height, "BARO" ASL.
// Kept when a library that sets it loads first (the GRTLS builds its buttons before the HUD loads)
IF NOT (DEFINED hdAltMode) { GLOBAL hdAltMode IS "RDR". }
GLOBAL hdAltAsc IS FALSE.                   // OPS 1's RDR / BARO (ops1q sets it): the mode switched as the radar's height
                                            //   crosses HD_RADALT_FT, a press holding until the next crossing
GLOBAL hdAltRad0 IS TRUE.                   // the last update's sRad (OPS 1's switch)
GLOBAL hdAltHidT IS -99.                    // the last hidden-HUD radar test (hdAltHidden), real s
GLOBAL HD_ALT_HID_S IS 0.5.                 // s between those tests
GLOBAL hdAltTag IS "".                      // the altitude's letter: R the radar's, W the runway's, none ASL
GLOBAL hdAltOfs IS 0.                       // ft: the blend left from the last change of source (decays by HD_ALT_TAU)
GLOBAL hdAltT IS -1.                        // the last update's time (-1: none yet)
GLOBAL sKeas IS 0.
GLOBAL sKgs IS 0.
GLOBAL bSnap IS FALSE.                      // the camera is snapped (conformal)
GLOBAL bFwd IS V(1, 0, 0).
GLOBAL bUp IS V(0, 1, 0).
GLOBAL bRight IS V(0, 0, 1).
GLOBAL bU IS V(0, 1, 0).
GLOBAL bEye IS V(0, 0, 0).
GLOBAL bVhat IS V(1, 0, 0).
GLOBAL bHasV IS FALSE.
GLOBAL gVVu IS 0.
GLOBAL gVVv IS 0.
// projection / cut results (globals, so the hot path allocates nothing)
GLOBAL pOK IS FALSE.
GLOBAL pU IS 0.
GLOBAL pV IS 0.
GLOBAL fFootU IS 0.
GLOBAL fFootV IS 0.
GLOBAL fUx IS 1.
GLOBAL fUy IS 0.
GLOBAL fNx IS 0.
GLOBAL fNy IS -1.
GLOBAL gAu IS 0.
GLOBAL gAv IS 0.
GLOBAL gBu IS 0.
GLOBAL gBv IS 0.
GLOBAL gRa IS FALSE.
GLOBAL gRb IS FALSE.
// widget slots: LIST(label, flow index, current image path / text, current X, current Y, current size)
GLOBAL pHz IS LIST().
GLOBAL pRung IS LIST().
GLOBAL pRnum IS LIST().
GLOBAL pRwy IS LIST().
GLOBAL pAim IS LIST().
GLOBAL pKtick IS LIST().
GLOBAL pAtick IS LIST().
GLOBAL pKnum IS LIST().
GLOBAL pAnum IS LIST().
GLOBAL sBore IS 0.
GLOBAL sFpm IS 0.
GLOBAL sKbox IS 0.
GLOBAL sAbox IS 0.
GLOBAL sSbScale IS 0.
GLOBAL sSbAct IS 0.
GLOBAL sSbCmd IS 0.
GLOBAL tKdig IS 0.
GLOBAL tAdig IS 0.
GLOBAL tArad IS 0.                          // the tape mode's R
GLOBAL tCtl IS 0.

// ---------------------------------------------------------------- small helpers
FUNCTION hdReal {
    IF hdHasReal { RETURN KUNIVERSE:REALTIME. }
    RETURN TIME:SECONDS.
}

FUNCTION hdPad3 {
    PARAMETER n.
    LOCAL s IS "" + n.
    UNTIL s:LENGTH >= 3 { SET s TO "0" + s. }
    RETURN s.
}

FUNCTION hdPad2 {
    PARAMETER n.
    LOCAL s IS "" + n.
    IF s:LENGTH < 2 { SET s TO "0" + s. }
    RETURN s.
}

FUNCTION hdNorm180 {
    PARAMETER a.
    LOCAL wr IS MOD(a + 180, 360).
    IF wr < 0 { SET wr TO wr + 360. }
    RETURN wr - 180.
}

// round to the sprite step, wrapped into [0, period) -> the table index
FUNCTION hdSnapIx {
    PARAMETER th, period.
    LOCAL a IS MOD(ROUND(th / H_STEP) * H_STEP + 3600, period).
    RETURN ROUND(a / H_STEP).
}

// the point dist m from geo along the great circle leaving it on bearing brg
FUNCTION hdDest {
    PARAMETER geo, brg, dist.
    LOCAL dl IS dist / BODY:RADIUS * CONSTANT:RADTODEG.
    LOCAL la1 IS geo:LAT.
    LOCAL la2 IS ARCSIN(SIN(la1) * COS(dl) + COS(la1) * SIN(dl) * COS(brg)).
    LOCAL lo2 IS geo:LNG + ARCTAN2(SIN(brg) * SIN(dl) * COS(la1), COS(dl) - SIN(la1) * SIN(la2)).
    RETURN LATLNG(la2, lo2).
}

// a centreline point x m past the threshold (negative: before it)
FUNCTION hdAlong {
    PARAMETER geo, hdg, x.
    IF x >= 0 { RETURN hdDest(geo, hdg, x). }
    RETURN hdDest(geo, hdg + 180, 0 - x).
}

FUNCTION hdLines {
    PARAMETER fpath.
    IF NOT EXISTS(fpath) { RETURN LIST(). }
    RETURN OPEN(fpath):READALL:STRING:SPLIT(CHAR(10)).
}

// the ground track, deg true; -1 when slower than 1 m/s
FUNCTION hdTrack {
    LOCAL vg IS VXCL(UP:VECTOR, SHIP:VELOCITY:SURFACE).
    IF vg:MAG < 1 { RETURN -1. }
    LOCAL ea IS VCRS(UP:VECTOR, NORTH:VECTOR).
    RETURN MOD(ARCTAN2(VDOT(vg, ea), VDOT(vg, NORTH:VECTOR)) + 360, 360).
}

// the decluttered digital altitude steps like the orbiter's: 200 ft above 1000, 100 to 500, 10 to 50, then 1 ft
FUNCTION hdAltDig {
    PARAMETER hft.
    LOCAL stp IS 1.
    IF hft > 1000 { SET stp TO 200. } ELSE IF hft > 500 { SET stp TO 100. } ELSE IF hft > 50 { SET stp TO 10. }
    RETURN ROUND(hft / stp) * stp.
}

// ---------------------------------------------------------------- loading
FUNCTION hdLoadLayout {
    FOR lineTxt IN hdLines(HD_ARCH + "hud_layout.txt") {
        LOCAL tk IS lineTxt:SPLIT(" ").
        IF tk:LENGTH >= 3 {
            IF tk[0] = "N" {
                hdLay:ADD(tk[1], tk[2]:TONUMBER(0)).
            } ELSE IF tk[0] = "T" {
                LOCAL s IS tk[2].
                FROM { LOCAL k IS 3. } UNTIL k >= tk:LENGTH STEP { SET k TO k + 1. } DO {
                    SET s TO s + " " + tk[k].
                }
                hdLay:ADD(tk[1], s).
            }
        }
    }
    RETURN hdLay:HASKEY("GLASS_TOP") AND hdLay:HASKEY("STROKE") AND hdLay:HASKEY("RWY_SEG_4").
}

FUNCTION hdLoadSprites {
    FOR lineTxt IN hdLines(HD_ARCH + "sprites.txt") {
        LOCAL tk IS lineTxt:SPLIT(" ").
        IF tk:LENGTH >= 8 {
            IF tk[0] <> "#" {
                LOCAL sImg IS tk[0] + ".png".
                IF tk:LENGTH >= 9 { IF tk[8] <> "" { SET sImg TO tk[8] + "/" + sImg. } }   // a family's sub-folder
                hdSpr:ADD(tk[0], LIST(HD_DIR + sImg, tk[1]:TONUMBER(0), tk[2]:TONUMBER(0),
                                      tk[3]:TONUMBER(0), tk[4]:TONUMBER(0), tk[5]:TONUMBER(0),
                                      tk[6]:TONUMBER(0), tk[7]:TONUMBER(0))).
            }
        }
    }
    IF NOT (hdSpr:HASKEY("rwy96_000") AND hdSpr:HASKEY("rwy06_178") AND hdSpr:HASKEY("boresight")) { RETURN FALSE. }
    LOCAL stp IS hdLay["ANGLE_STEP"].
    FROM { LOCAL a IS 0. } UNTIL a >= 360 STEP { SET a TO a + stp. } DO {
        IF a < 180 { hdHzTab:ADD(hdSpr["hz_" + hdPad3(a)]). }
        hdRpTab:ADD(hdSpr["rung_p_" + hdPad3(a)]).
        hdRnTab:ADD(hdSpr["rung_n_" + hdPad3(a)]).
    }
    FOR k IN LIST(1, 2, 3, 4) {
        LOCAL sl IS hdLay["RWY_SEG_" + k].
        hdSegL:ADD(sl).
        LOCAL fam IS LIST().
        LOCAL nm IS "rwy" + hdPad2(ROUND(sl)) + "_".
        FROM { LOCAL a IS 0. } UNTIL a >= 180 STEP { SET a TO a + stp. } DO { fam:ADD(hdSpr[nm + hdPad3(a)]). }
        hdRwyTab:ADD(fam).
    }
    RETURN hdSpr:HASKEY("fpm") AND hdSpr:HASKEY("sb_scale") AND hdSpr:HASKEY("aim_circle").
}

// hud/hud_runways.txt lines: R site name lat lon hdg len wid elev slope far_lat far_lon x_ogs x_igs els
FUNCTION hdLoadRunways {
    FOR lineTxt IN hdLines(HD_ARCH + "hud_runways.txt") {
        LOCAL tk IS capeLine(lineTxt):SPLIT(" ").           // the Cape's SLF rows
        IF tk:LENGTH >= 15 {
            IF tk[0] = "R" {
                hdRwys:ADD(LIST(tk[1], tk[2], LATLNG(tk[3]:TONUMBER(0), tk[4]:TONUMBER(0)), tk[5]:TONUMBER(0),
                                tk[6]:TONUMBER(0), tk[7]:TONUMBER(0), tk[8]:TONUMBER(0), tk[9]:TONUMBER(0),
                                LATLNG(tk[10]:TONUMBER(0), tk[11]:TONUMBER(0)), tk[12]:TONUMBER(0), tk[13]:TONUMBER(0),
                                tk[14] = "1")).
            }
        }
    }
    // each end's partner: the other end of the same site
    FROM { LOCAL k IS 0. } UNTIL k >= hdRwys:LENGTH STEP { SET k TO k + 1. } DO {
        LOCAL o IS k.
        FROM { LOCAL j IS 0. } UNTIL j >= hdRwys:LENGTH STEP { SET j TO j + 1. } DO {
            IF j <> k AND hdRwys[j][0] = hdRwys[k][0] { SET o TO j. }
        }
        hdOther:ADD(o).
    }
    RETURN hdRwys:LENGTH > 0.
}

FUNCTION hdHoist {
    SET H_STEP TO hdLay["ANGLE_STEP"].
    SET H_FOV TO hdLay["CAM_FOV_V"].
    SET H_FPX TO hdLay["F_PX"].
    SET H_U0 TO hdLay["U0"].
    SET H_V0 TO hdLay["V0"].
    SET H_VS TO hdLay["VS"].
    SET H_CAMP TO hdLay["CAM_PITCH_DEG"].
    SET H_FL TO hdLay["FIELD_L"].
    SET H_FT TO hdLay["FIELD_T"].
    SET H_FR TO hdLay["FIELD_R"].
    SET H_FB TO hdLay["FIELD_B"].
    SET H_FDV TO hdLay["FD_V"].
    SET H_LAD_ALONG TO hdLay["LAD_NUM_ALONG"].
    SET H_LAD_UP TO hdLay["LAD_NUM_UP"].
    SET H_LAD_FS TO hdLay["LAD_NUM_FS"].
    SET H_HZ_GAP TO hdLay["HZ_GAP"].
    SET H_HZ_SEGS TO hdLay["HZ_SEGS"].
    SET H_HZ_SEG TO hdLay["HZ_SEG_PX"].
    SET H_VC TO hdLay["VC"].
    SET H_HALF TO hdLay["HALF"].
    SET H_XS TO hdLay["XS"].
    SET H_XA TO hdLay["XA"].
    SET H_TAPE_KT TO hdLay["TAPE_KT"].
    SET H_TAPE_FT TO hdLay["TAPE_FT"].
    SET H_PER_KT TO hdLay["PER_KT"].
    SET H_PER_FT TO hdLay["PER_FT"].
    SET H_TAPE_FS TO hdLay["TAPE_FS"].
    SET H_BOX_KX TO hdLay["BOX_KX"].
    SET H_BOX_AX TO hdLay["BOX_AX"].
    SET H_BOX_Y TO hdLay["BOX_Y"].
    SET H_DECL TO hdLay["DECLUTTER_FT"].
    SET H_DIG_FS TO hdLay["DIG_FS"].
    SET H_SB_B0 TO hdLay["SB_B0"].
    SET H_SB_B1 TO hdLay["SB_B1"].
    SET H_SB_YB TO hdLay["SB_YB"].
    SET H_SB_TIP TO hdLay["SB_TIP"].
    SET H_SB_FULL TO hdLay["SB_FULL"].
    SET H_XM TO hdLay["XM"].
    SET H_YC TO hdLay["YC"].
    SET H_CTL_FS TO hdLay["CTL_FS"].
    SET H_AIM_R TO hdLay["AIM_R"].
    SET H_AIM_MIN TO hdLay["AIM_MIN_SPAN"].
    SET H_ZNEAR TO hdLay["RWY_ZNEAR"].
    SET H_GTOP TO hdLay["GLASS_TOP"].
    SET H_GHW TO hdLay["GLASS_HW"].
    SET H_OVL TO hdLay["RWY_OVL"].
    SET H_CLIP TO hdLay["RWY_CLIP"].
    SET H_HSTROKE TO hdLay["STROKE"] / 2.
    SET H_VV_HW TO hdLay["VV_HW"].
    SET H_VV_TOP TO hdLay["VV_TOP"].
    SET H_VV_GAP TO hdLay["VV_GAP"].
    SET H_RHO0 TO hdLay["RHO0"].
    SET H_KT TO hdLay["KT"].
    SET H_FTM TO hdLay["FT"].
    SET H_COL TO hdLay["HUD_COLOR"].
    SET H_MONO TO hdLay["MONO_ADV"].
    // the speed at the boresight after touchdown: its bottom-right 0.15 deg left of and 0.2 deg above the cross
    SET H_BORE_DX TO H_FPX * TAN(0.15).
    SET H_BORE_DY TO H_FPX * TAN(0.2).
    SET SP_BORE TO hdSpr["boresight"].
    SET SP_FPM TO hdSpr["fpm"].
    SET SP_AIM TO hdSpr["aim_circle"].
    SET SP_TICK TO hdSpr["tick"].
    SET SP_BOX TO hdSpr["box"].
    // the tape mode's R: right of the GSI's column (lib_hudg's GSI_X + the gsi sprite's ink right of its
    // anchor), HD_RAD_GAP_PX out, so the moving GSI never covers it
    SET hdRadX TO H_XA + 42.
    IF hdLay:HASKEY("GSI_X") { SET hdRadX TO hdLay["GSI_X"]. }
    IF hdSpr:HASKEY("gsi") { SET hdRadX TO hdRadX + hdSpr["gsi"][6] - hdSpr["gsi"][2]. }
    SET hdRadX TO hdRadX + HD_RAD_GAP_PX.
    SET SP_SBSCALE TO hdSpr["sb_scale"].
    SET SP_SBDN TO hdSpr["sb_ptr_dn"].
    SET SP_SBUP TO hdSpr["sb_ptr_up"].
    // the ladder's floor: SB_TIP above the actual pointer's ink top, the highest of the bottom readouts
    SET H_LAD_FB TO MIN(H_FB, H_SB_YB - H_SB_TIP + (SP_SBDN[5] - SP_SBDN[3]) - H_SB_TIP).
}

// the glass (the field plus the chamfered top 5 deg above the boresight) as inward half-planes, and the ladder / runway window
FUNCTION hdGlassSetup {
    LOCAL poly IS LIST(LIST(H_FL, H_FB), LIST(H_FL, H_FT), LIST(H_U0 - H_GHW, H_GTOP), LIST(H_U0 + H_GHW, H_GTOP),
                       LIST(H_FR, H_FT), LIST(H_FR, H_FB)).
    LOCAL np IS poly:LENGTH.
    LOCAL area IS 0.
    FROM { LOCAL k IS 0. } UNTIL k >= np STEP { SET k TO k + 1. } DO {
        LOCAL pa IS poly[k].
        LOCAL pb IS poly[MOD(k + 1, np)].
        SET area TO area + pa[0] * pb[1] - pb[0] * pa[1].
    }
    FROM { LOCAL k IS 0. } UNTIL k >= np STEP { SET k TO k + 1. } DO {
        LOCAL pa IS poly[k].
        LOCAL pb IS poly[MOD(k + 1, np)].
        LOCAL eu IS pb[0] - pa[0].
        LOCAL ev IS pb[1] - pa[1].
        LOCAL nu IS ev.
        LOCAL nv IS 0 - eu.
        IF area > 0 {
            SET nu TO 0 - ev.
            SET nv TO eu.
        }
        LOCAL nn IS SQRT(nu * nu + nv * nv).
        hdGlassHP:ADD(LIST(nu / nn, nv / nn, (nu * pa[0] + nv * pa[1]) / nn)).
    }
    // a line of elevation e lies |e - camEl| from the camera axis: a rung (or the runway) further than the glass's
    // corner furthest from the axis (VS is the axis on screen), + 1 deg for ticks, numbers and ink, cannot show
    SET hdLadWin TO 0.
    FOR pc IN poly {
        SET hdLadWin TO MAX(hdLadWin, ARCTAN(SQRT((pc[0] - H_U0) ^ 2 + (pc[1] - H_VS) ^ 2) / H_FPX)).
    }
    SET hdLadWin TO hdLadWin + 1.
}

// ---------------------------------------------------------------- styles and widgets
FUNCTION hdClearAllStates {
    PARAMETER st.
    SET st:BG TO HD_CLEAR.
    IF st:HASSUFFIX("NORMAL")     { SET st:NORMAL:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("ON")         { SET st:ON:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("HOVER")      { SET st:HOVER:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("HOVER_ON")   { SET st:HOVER_ON:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("ACTIVE")     { SET st:ACTIVE:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("ACTIVE_ON")  { SET st:ACTIVE_ON:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("FOCUSED")    { SET st:FOCUSED:BG TO HD_CLEAR. }
    IF st:HASSUFFIX("FOCUSED_ON") { SET st:FOCUSED_ON:BG TO HD_CLEAR. }
}

FUNCTION hdZeroBox {
    PARAMETER st.
    SET st:PADDING:H TO 0.
    SET st:PADDING:V TO 0.
    SET st:MARGIN:H TO 0.
    SET st:MARGIN:V TO 0.
    IF st:HASSUFFIX("BORDER") {
        SET st:BORDER:H TO 0.
        SET st:BORDER:V TO 0.
    }
}

// T680 (the owner 11-09 17:3x: "Lag in ops6q. Fix that now"): kOS's IMGUI draws every SHOWN label every frame, a
// clear one as dearly as a drawn one, so a slot's label is shown only while it holds a sprite / text; its 1x1 box stays
// shown and keeps its pixel of the flow, so no other slot moves.
// an image slot: a 1x1 VLAYOUT holding a label whose :IMAGE is the sprite. The label has no padding: with kOS's
// default (3 px top and bottom) a sprite S px square must fit S - 6 px, and kOS scales it by (S - 6) / S from the
// label's left edge. Without the padding the sprite lands 1:1, its anchor where hdBlit puts it.
FUNCTION hdImgSlot {
    LOCAL bx IS hdBox:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // T680 S5: an empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    hdZeroBox(m:STYLE).
    SET m:IMAGE TO HD_CLEAR.
    m:HIDE().                               // T680: a blank label hidden (its 1 x 1 box keeps the flow: nothing moves)
    SET m:STYLE:WIDTH TO 4.
    SET m:STYLE:HEIGHT TO 4.
    LOCAL sl IS LIST(m, hdChildN, HD_CLEAR, -99999, -99999, 4).
    hdOrd:ADD(LIST(m, hdChildN)).           // T680 S2: the painter's list
    SET hdChildN TO hdChildN + 1.
    RETURN sl.
}

// The HUD text in a squared, one-width stroke font, as the real HUD's narrow letters. kOS's STYLE:FONT takes only a
// font already loaded in the game, by its name there (LIST FONTS = fl), and kOS keeps a font installed in Windows only
// when it is monospaced (its terminal's test). A .ttf in GameData (ConformalDecals' font loader, named by its full path)
// is listed but does NOT draw in a label: not a dynamic font (Unity: "Font size and style overrides are only supported
// for dynamic fonts"; every label draws blank). So the HUD fonts are installed in Windows for all users, fixed-pitch:
// "HUD Stroke" (HD_FONT_FILE), Saira Extra Condensed's heights in a cell of 0.413 em like the real HUD's (1000 upm;
// hhea = typo = win: ascent 1.135, capitals 0.688; Arial's capitals 0.716, so 0.716 / 0.688 x the size keeps the
// layout's letter height); and the set "HUD Stroke Wide NNN" (HD_FONT_SET), the same shapes and heights in a 0.516 em
// cell with the stroke NNN / 1000 em: each text slot takes the one whose stroke draws nearest HD_PEN_PX at its size
// (hdTxtFont). Not in the list: Arial in <b>; no set: HUD Stroke alone.
FUNCTION hdFindFont {
    PARAMETER fl.
    IF HD_FONT_FILE = "" { RETURN. }
    hdFontSet:CLEAR().
    LOCAL n IS HD_FONT_SET:LENGTH.
    FOR fn IN fl {
        IF HD_FONT = "" AND fn:ENDSWITH(HD_FONT_FILE) { SET HD_FONT TO fn. }
        ELSE IF n > 0 AND fn:LENGTH >= n + 3 {
            IF fn:STARTSWITH(HD_FONT_SET) {
                LOCAL u IS fn:SUBSTRING(n, 3):TONUMBER(-1).
                IF u > 0 { hdFontSet:ADD(LIST(u, fn)). }
            }
        }
    }
    IF HD_FONT = "" AND hdFontSet:LENGTH > 0 { SET HD_FONT TO hdFontSet[0][1]. }
    IF HD_FONT <> "" {                              // HUD Stroke's heights (the set's too)
        SET HD_FK TO 0.716 / 0.688.
        SET HD_FASC TO 1.135.
        SET HD_FCTR TO 1.135 - 0.688 / 2.
        SET hdB0 TO "".
        SET hdB1 TO "".
    }
}

// a text slot's font size for its layout size fs (fs itself in Arial)
FUNCTION hdTxtSize {
    PARAMETER fs.
    IF HD_FONT = "" { RETURN fs. }
    RETURN ROUND(fs * HD_FK).
}

// a text slot's font for its layout size fs: of the set, the one whose stroke draws nearest HD_PEN_PX x
// SCR_H / 2160 px at the slot's font size (3840 x 2160: 18 px 148, 19 px 140, 21 px 127, 23 px 116, 29 px 092);
// no set = HD_FONT ("" = Arial)
FUNCTION hdTxtFont {
    PARAMETER fs.
    IF hdFontSet:LENGTH = 0 { RETURN HD_FONT. }
    LOCAL u IS 1000 * HD_PEN_PX * SCR_H / 2160 / MAX(hdTxtSize(fs), 1).
    LOCAL b IS hdFontSet[0].
    FOR f IN hdFontSet { IF ABS(f[0] - u) < ABS(b[0] - u) { SET b TO f. } }
    RETURN b[1].
}

// px: a text slot's label top above its y (va as hdTxtSlot), from the font's metrics at its size
FUNCTION hdTxtTop {
    PARAMETER fs, va.
    IF va = 1 { RETURN hdTxtSize(fs) * HD_FASC. }
    RETURN hdTxtSize(fs) * HD_FCTR.
}

// a text slot: align 0 = centred on x, 1 = left edge at x, 2 = right edge at x; va 0 = centred on y, 1 = baseline at y.
// The label box is 8 x the font size wide: it must stay inside this window, not the screen.
FUNCTION hdTxtSlot {
    PARAMETER fs, align, va.
    LOCAL bx IS hdBox:ADDVLAYOUT().
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // T680 S5: an empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    hdZeroBox(m:STYLE).
    SET m:STYLE:RICHTEXT TO TRUE.
    SET m:STYLE:WORDWRAP TO FALSE.
    SET m:STYLE:FONTSIZE TO hdTxtSize(fs).
    SET m:STYLE:WIDTH TO 8 * fs.
    SET m:STYLE:HEIGHT TO ROUND(fs * 1.5).
    IF align = 0 { SET m:STYLE:ALIGN TO "CENTER". } ELSE IF align = 2 { SET m:STYLE:ALIGN TO "RIGHT". }
    ELSE { SET m:STYLE:ALIGN TO "LEFT". }
    LOCAL fnt IS hdTxtFont(fs).
    IF fnt <> "" { IF m:STYLE:HASSUFFIX("FONT") { SET m:STYLE:FONT TO fnt. } }
    // LIST(label, flow index, current text, X, Y, font size, align, va, last input x, y, the label top above y)
    LOCAL sl IS LIST(m, hdChildN, "", -99999, -99999, fs, align, va, -99999, -99999, hdTxtTop(fs, va)).
    m:HIDE().                               // T680: blank, hidden (hdImgSlot's)
    hdOrd:ADD(LIST(m, hdChildN)).           // T680 S2: the painter's list
    SET hdChildN TO hdChildN + 1.
    RETURN sl.
}

FUNCTION hdHide {
    PARAMETER sl.
    IF sl[2] <> HD_CLEAR {
        SET sl[0]:IMAGE TO HD_CLEAR.
        sl[0]:HIDE().
        SET sl[2] TO HD_CLEAR.
    }
}

FUNCTION hdHideT {
    PARAMETER sl.
    IF sl[2] <> "" {
        SET sl[0]:TEXT TO "".
        sl[0]:HIDE().
        SET sl[2] TO "".
    }
}

FUNCTION hdHideFrom {
    PARAMETER pool, k0.
    FROM { LOCAL k IS k0. } UNTIL k >= pool:LENGTH STEP { SET k TO k + 1. } DO { hdHide(pool[k]). }
}

FUNCTION hdHideTFrom {
    PARAMETER pool, k0.
    FROM { LOCAL k IS k0. } UNTIL k >= pool:LENGTH STEP { SET k TO k + 1. } DO { hdHideT(pool[k]). }
}

// hide only the slots [k0, k1) -- k1 = those used last time, so an idle pool costs nothing
FUNCTION hdHideRange {
    PARAMETER pool, k0, k1.
    LOCAL kE IS MIN(k1, pool:LENGTH).
    FROM { LOCAL k IS k0. } UNTIL k >= kE STEP { SET k TO k + 1. } DO { hdHide(pool[k]). }
}

FUNCTION hdHideTRange {
    PARAMETER pool, k0, k1.
    LOCAL kE IS MIN(k1, pool:LENGTH).
    FROM { LOCAL k IS k0. } UNTIL k >= kE STEP { SET k TO k + 1. } DO { hdHideT(pool[k]). }
}

// a sprite's top-left at the whole pixel (xx, yy) of the SCREEN (the window's own offset taken off here)
FUNCTION hdPlace {
    PARAMETER sl, rec, xx, yy.
    IF sl[2] <> rec[0] {
        SET sl[0]:IMAGE TO rec[0].
        IF rec[0] = HD_CLEAR { sl[0]:HIDE(). } ELSE { sl[0]:SHOW(). }
        SET sl[2] TO rec[0].
        IF sl[5] <> rec[1] {
            SET sl[0]:STYLE:WIDTH TO rec[1].
            SET sl[0]:STYLE:HEIGHT TO rec[1].
            SET sl[5] TO rec[1].
        }
    }
    IF xx <> sl[3] OR yy <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, xx - hdWinX).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, yy - sl[1] * HD_FLOW_PX - hdWinY).
        SET sl[3] TO xx.
        SET sl[4] TO yy.
    }
}

// the sprite's anchor at (x, y), whole pixels; hidden whole if its ink leaves the field.
// rec = LIST(path, size, ax, ay, ink l, t, r, b)
FUNCTION hdBlit {
    PARAMETER sl, rec, x, y.
    LOCAL xx IS FLOOR(x - rec[2] + 0.5).
    LOCAL yy IS FLOOR(y - rec[3] + 0.5).
    IF xx + rec[4] < H_FL OR xx + rec[6] > H_FR OR yy + rec[5] < H_FT OR yy + rec[7] > H_FB {
        hdHide(sl).
        RETURN FALSE.
    }
    hdPlace(sl, rec, xx, yy).
    RETURN TRUE.
}

// the ladder's blit (the horizon segments and the rungs): as hdBlit, with the ladder's floor H_LAD_FB at the bottom
FUNCTION hdBlitLad {
    PARAMETER sl, rec, x, y.
    LOCAL xx IS FLOOR(x - rec[2] + 0.5).
    LOCAL yy IS FLOOR(y - rec[3] + 0.5).
    IF xx + rec[4] < H_FL OR xx + rec[6] > H_FR OR yy + rec[5] < H_FT OR yy + rec[7] > H_LAD_FB {
        hdHide(sl).
        RETURN FALSE.
    }
    hdPlace(sl, rec, xx, yy).
    RETURN TRUE.
}

// as hdBlit, for the aim circles: hidden whole unless all four corners of its ink are inside the glass
FUNCTION hdBlitGlass {
    PARAMETER sl, rec, x, y.
    LOCAL xx IS FLOOR(x - rec[2] + 0.5).
    LOCAL yy IS FLOOR(y - rec[3] + 0.5).
    LOCAL l IS xx + rec[4].
    LOCAL t IS yy + rec[5].
    LOCAL rr IS xx + rec[6].
    LOCAL bb IS yy + rec[7].
    FOR hp IN hdGlassHP {
        LOCAL hu IS hp[0].
        LOCAL hv IS hp[1].
        LOCAL hc IS hp[2].
        IF hu * l + hv * t < hc OR hu * rr + hv * t < hc OR hu * l + hv * bb < hc OR hu * rr + hv * bb < hc {
            SET xx TO -99999.
        }
    }
    IF xx = -99999 {
        hdHide(sl).
        RETURN FALSE.
    }
    hdPlace(sl, rec, xx, yy).
    RETURN TRUE.
}

// as hdBlit, for the runway segments: the line was cut to the glass first, so every segment fits: no test
FUNCTION hdBlitNT {
    PARAMETER sl, rec, x, y.
    hdPlace(sl, rec, FLOOR(x - rec[2] + 0.5), FLOOR(y - rec[3] + 0.5)).
}

// a label at (x, y); hidden whole when its (estimated, monospace) box leaves the field
FUNCTION hdText {
    PARAMETER sl, s, x, y.
    IF s = sl[2] {                                  // unchanged text at the same place: nothing to do
        IF s = "" { RETURN. }
        IF ROUND(x) = sl[8] { IF ROUND(y) = sl[9] { RETURN. } }
    }
    LOCAL fs IS sl[5].
    LOCAL w IS s:LENGTH * H_MONO * fs.
    LOCAL x0 IS x.
    IF sl[6] = 0 { SET x0 TO x - w / 2. } ELSE IF sl[6] = 2 { SET x0 TO x - w. }
    LOCAL y0 IS y - fs * 0.5.
    IF sl[7] = 1 { SET y0 TO y - fs * 0.75. }
    IF s = "" OR x0 < H_FL OR x0 + w > H_FR OR y0 < H_FT OR y0 + fs > H_FB {
        hdHideT(sl).
        RETURN.
    }
    IF s <> sl[2] {
        SET sl[0]:TEXT TO "<color=" + H_COL + ">" + hdB0 + s + hdB1 + "</color>".
        sl[0]:SHOW().
        SET sl[2] TO s.
    }
    LOCAL lw IS 8 * fs.
    LOCAL lx IS x.
    IF sl[6] = 0 { SET lx TO x - lw / 2. } ELSE IF sl[6] = 2 { SET lx TO x - lw. }
    LOCAL ly IS y - sl[10].                         // hdTxtTop: the capitals' middle (va 0) or the baseline at y
    SET lx TO ROUND(lx).
    SET ly TO ROUND(ly).
    IF lx <> sl[3] OR ly <> sl[4] {
        SET sl[0]:STYLE:MARGIN:H TO MAX(0, lx + HD_OFF_X - hdWinX).
        SET sl[0]:STYLE:MARGIN:V TO MAX(0, ly + HD_OFF_Y - HD_TXT_DY - sl[1] * HD_FLOW_PX - hdWinY).
        SET sl[3] TO lx.
        SET sl[4] TO ly.
    }
    SET sl[8] TO ROUND(x).
    SET sl[9] TO ROUND(y).
}

// ---------------------------------------------------------------- the HUD window + widget pools
// the window covers the glass plus a margin (HD_PAD), not the screen, so every other window (the host's buttons, the kOS
// terminal, MechJeb) stays clickable: a kOS window takes every click where it lies. The map view hides it.
FUNCTION hdBuild {
    SET hdWinX TO ROUND(H_FL - HD_PAD).
    SET hdWinY TO ROUND(H_GTOP - HD_PAD).
    LOCAL ww IS ROUND(H_FR + HD_PAD) - hdWinX.
    LOCAL wh IS ROUND(H_FB + 60) - hdWinY.
    SET hdHud TO GUI(ww, wh).
    SET hdHud:X TO hdWinX.
    SET hdHud:Y TO hdWinY.
    hdClearAllStates(hdHud:STYLE).
    hdZeroBox(hdHud:STYLE).
    IF hdHud:HASSUFFIX("DRAGGABLE") { SET hdHud:DRAGGABLE TO FALSE. }
    SET hdBox TO hdHud:ADDVLAYOUT().
    hdZeroBox(hdBox:STYLE).
    SET hdBox:STYLE:WIDTH TO ww.
    SET hdBox:STYLE:HEIGHT TO wh.
    SET hdChildN TO 0.
    SET hdOrd TO LIST().                    // T680 S2
    SET hdPhs TO LIST().
    // images, in draw order: the ladder, the runway, the boresight, the velocity vector, the scales
    FROM { LOCAL k IS 0. } UNTIL k >= 2 * H_HZ_SEGS STEP { SET k TO k + 1. } DO { pHz:ADD(hdImgSlot()). }
    FROM { LOCAL k IS 0. } UNTIL k >= HD_RUNG_N STEP { SET k TO k + 1. } DO { pRung:ADD(hdImgSlot()). }
    FROM { LOCAL k IS 0. } UNTIL k >= HD_RWY_N STEP { SET k TO k + 1. } DO { pRwy:ADD(hdImgSlot()). }
    FROM { LOCAL k IS 0. } UNTIL k >= 2 STEP { SET k TO k + 1. } DO { pAim:ADD(hdImgSlot()). }
    SET sBore TO hdImgSlot().
    SET sFpm TO hdImgSlot().
    FROM { LOCAL k IS 0. } UNTIL k >= HD_TAPE_N STEP { SET k TO k + 1. } DO {
        pKtick:ADD(hdImgSlot()).
        pAtick:ADD(hdImgSlot()).
    }
    SET sKbox TO hdImgSlot().
    SET sAbox TO hdImgSlot().
    SET sSbScale TO hdImgSlot().
    SET sSbAct TO hdImgSlot().
    SET sSbCmd TO hdImgSlot().
    // text
    FROM { LOCAL k IS 0. } UNTIL k >= HD_RUNG_N STEP { SET k TO k + 1. } DO {
        pRnum:ADD(hdTxtSlot(H_LAD_FS, 0, 0)).
    }
    FROM { LOCAL k IS 0. } UNTIL k >= HD_TAPE_N STEP { SET k TO k + 1. } DO {
        pKnum:ADD(hdTxtSlot(H_TAPE_FS, 0, 0)).
        pAnum:ADD(hdTxtSlot(H_TAPE_FS, 0, 0)).
    }
    SET tKdig TO hdTxtSlot(H_DIG_FS, 2, 1).        // right edge + baseline: rides the velocity vector
    SET tAdig TO hdTxtSlot(H_DIG_FS, 1, 1).        // left edge + baseline
    SET tArad TO hdTxtSlot(H_TAPE_FS, 1, 0).       // left edge, centred
    SET tCtl TO hdTxtSlot(H_CTL_FS, 1, 0).
    IF hdVis {                                  // built hidden while the HUD button is off (the GRTLS)
        hdHud:SHOW().
        SET hdShown TO TRUE.
    }
}

// ---------------------------------------------------------------- camera
// snaps the kOS StockCamera 0.3.1 FREECAMERA to the flight deck (the host's button); only then are the conformal
// symbols drawn. The eye rides the forward fuselage (HD_EYE_PART_*), the c.g. only on another craft; the
// HUD's math reads the camera's own POSITION / FACING every update (hdState, hdCsIn), so it follows either way
FUNCTION hdCamSnap {
    IF NOT hdCamOK { RETURN FALSE. }
    IF NOT hdCam:AVAILABLE { RETURN FALSE. }
    LOCAL f IS SHIP:FACING.
    LOCAL eye IS f:FOREVECTOR * HD_EYE_FWD + f:TOPVECTOR * HD_EYE_UP.
    LOCAL ep IS hdEyePart().
    IF ep:LENGTH > 0 {
        SET f TO hdEyeFrame(ep[0]).
        SET hdCam:ANCHOR TO ep[0].                  // first: SETPOSE's pose is then stored in the part's space
        // the saved calibration, the built-in one, the bounds eye or the fixed offsets (hdEyeOffset)
        LOCAL p0 IS ep[0]:POSITION.
        LOCAL eo IS hdEyeOffset(ep[0], f).
        SET eye TO p0 + f:FOREVECTOR * eo[0] + f:TOPVECTOR * eo[1] + f:STARVECTOR * eo[2].
        LOG TIME:SECONDS + " eye: part " + ep[0]:NAME + " -> " + ROUND(eo[0], 2) + " fwd " + ROUND(eo[1], 2) + " up "
            + ROUND(eo[2], 2) + " right of the part's origin (" + eo[3] + "), which is "
            + ROUND(VDOT(SHIP:FACING:FOREVECTOR, p0), 2) + " m ahead of the c.g." TO "0:/logs/hud_eye.txt".
    } ELSE {
        SET hdCam:ANCHOR TO SHIP.
        SET hdCam:ANCHORFRAME TO "FACING".
        // say why (a silent fallback leaves the view where it was)
        LOCAL fus IS "".
        FOR pt IN SHIP:PARTS { IF pt:NAME:TOLOWER:CONTAINS("fuselage") { SET fus TO fus + " [" + pt:NAME + "]". } }
        LOG TIME:SECONDS + " eye: NO forward fuselage found (" + HD_EYE_PART + ") among " + SHIP:PARTS:LENGTH
            + " parts -> the c.g. eye " + HD_EYE_FWD + " fwd " + HD_EYE_UP + " up; fuselage parts:" + fus TO "0:/logs/hud_eye.txt".
    }
    SET hdCam:FOV TO H_FOV.
    SET hdCam:ENABLED TO TRUE.
    hdCam:SETPOSE(eye, hdCamFacing()).
    RETURN TRUE.
}

// the part's own axes, unless they are not the nose's (another model's layout): then the ship's. A control point
// other than "Forward" turns SHIP:FACING (the angled one 15 deg), not the part's. (Its own function: hud_cal.ks uses it)
FUNCTION hdEyeFrame {
    PARAMETER pt.
    LOCAL f IS SHIP:FACING.
    LOCAL pf IS pt:FACING.
    IF VANG(pf:FOREVECTOR, f:FOREVECTOR) < 30 AND VANG(pf:TOPVECTOR, f:TOPVECTOR) < 30 { RETURN pf. }
    RETURN f.
}

// the eye from the part's BOUNDS (an eye at a fixed offset from the part's origin sits inside its shell); the
// fixed offsets only if the bounds read implausibly. LIST(fwd, up, right, what) in m from the part's origin along f.
FUNCTION hdEyeBounds {
    PARAMETER pt, f.
    LOCAL p0 IS pt:POSITION.
    LOCAL bb IS pt:BOUNDS.
    LOCAL nose IS VDOT(f:FOREVECTOR, bb:FURTHESTCORNER(f:FOREVECTOR) - p0).
    LOCAL tail IS VDOT(f:FOREVECTOR, bb:FURTHESTCORNER(f:FOREVECTOR * (-1)) - p0).
    LOCAL roof IS VDOT(f:TOPVECTOR, bb:FURTHESTCORNER(f:TOPVECTOR) - p0).
    LOCAL what IS "bounds: nose " + ROUND(nose, 2) + " tail " + ROUND(tail, 2) + " roof " + ROUND(roof, 2) + " m".
    IF hdEyeAny AND nose - tail > 0.2 {         // a cockpit of any size, the same rule (above its canopy)
        RETURN LIST(nose - HD_EYE_NOSE_FRAC * (nose - tail), MAX(roof, 0) + HD_EYE_ROOF_UP, 0, what + ", any craft").
    }
    IF nose - tail > 3 AND nose - tail < 30 AND roof > 0.3 AND roof < 6 {
        RETURN LIST(nose - HD_EYE_NOSE_FRAC * (nose - tail), roof + HD_EYE_ROOF_UP, 0, what).
    }
    RETURN LIST(HD_EYE_PART_FWD, HD_EYE_PART_UP, 0, what + " IMPLAUSIBLE, the old offsets").
}

// the player's saved calibration (hud_cal.ks), LIST(fwd, up, right) in m, or LIST() when there is none (or the
// file is not one)
FUNCTION hdEyeSaved {
    IF NOT EXISTS(HD_EYE_CAL_FILE) { RETURN LIST(). }
    LOCAL c IS READJSON(HD_EYE_CAL_FILE).
    IF NOT c:ISTYPE("Lexicon") { RETURN LIST(). }
    FOR k IN LIST("fwd", "up", "star") {
        IF NOT c:HASKEY(k) { RETURN LIST(). }
        IF NOT c[k]:ISTYPE("Scalar") { RETURN LIST(). }
    }
    RETURN LIST(c["fwd"], c["up"], c["star"]).
}

// the eye the HUD CAM uses, LIST(fwd, up, right, what): the saved calibration, else the built-in one
// (HD_EYE_DEF), else the bounds eye
FUNCTION hdEyeOffset {
    PARAMETER pt, f.
    LOCAL sv IS hdEyeSaved().
    IF sv:LENGTH = 3 { RETURN LIST(sv[0], sv[1], sv[2], "saved: " + HD_EYE_CAL_FILE). }
    IF HD_EYE_DEF:LENGTH = 3 { RETURN LIST(HD_EYE_DEF[0], HD_EYE_DEF[1], HD_EYE_DEF[2], "built-in HD_EYE_DEF"). }
    RETURN hdEyeBounds(pt, f).
}

// the part the eye rides (HD_EYE_PART, the first found), or LIST() when the vessel has none (the c.g. eye)
// the exact name, then PARTSNAMED (case-blind, as ops3q's mid fuselage), then any name containing "forwardfuselage"
FUNCTION hdEyePart {
    FOR pt IN SHIP:PARTS {
        IF pt:NAME:TOLOWER:REPLACE("_", ".") = HD_EYE_PART { RETURN LIST(pt). }
    }
    LOCAL pn IS SHIP:PARTSNAMED(HD_EYE_PART).
    IF pn:LENGTH > 0 { RETURN LIST(pn[0]). }
    FOR pt IN SHIP:PARTS {
        IF pt:NAME:TOLOWER:CONTAINS("forwardfuselage") { RETURN LIST(pt). }
    }
    LOCAL ap IS hdAnyPart().                    // any other craft
    IF ap:LENGTH > 0 AND NOT hdEyeAny {
        SET hdEyeAny TO TRUE.
        SET HD_EYE_CAL_FILE TO "0:/hud_eye_cal_" + hdFileName(SHIP:NAME) + ".json".
        SET HD_EYE_DEF TO LIST().
    }
    RETURN ap.
}

// the part another craft is flown from: SHIP:CONTROLPART when it is crewed (a cockpit), else the foremost crewed
// part, else the foremost part (a drone's nose)
FUNCTION hdAnyPart {
    LOCAL fw IS SHIP:FACING:FOREVECTOR.
    IF SHIP:HASSUFFIX("CONTROLPART") {
        LOCAL cp IS SHIP:CONTROLPART.
        IF cp:HASSUFFIX("CREWCAPACITY") { IF cp:CREWCAPACITY > 0 { RETURN LIST(cp). } }
    }
    LOCAL best IS LIST().
    LOCAL bx IS -1E9.
    LOCAL crewed IS FALSE.
    FOR pt IN SHIP:PARTS {
        LOCAL c IS FALSE.
        IF pt:HASSUFFIX("CREWCAPACITY") { SET c TO pt:CREWCAPACITY > 0. }
        LOCAL x IS VDOT(fw, pt:POSITION).
        IF (c AND NOT crewed) OR (c = crewed AND x > bx) {
            SET best TO LIST(pt).
            SET bx TO x.
            SET crewed TO c.
        }
    }
    RETURN best.
}

// a craft's name as a file name: letters, digits, "-" and "_" kept, the rest "_"
FUNCTION hdFileName {
    PARAMETER nm.
    LOCAL ok IS "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".
    LOCAL s IS "".
    FROM { LOCAL i IS 0. } UNTIL i >= nm:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL ch IS nm:SUBSTRING(i, 1).
        SET s TO s + (CHOOSE ch IF ok:CONTAINS(ch) ELSE "_").
    }
    RETURN s.
}

// the camera looks H_CAMP below the nose: the frozen-FD point on the screen centre
FUNCTION hdCamFacing {
    LOCAL f IS SHIP:FACING.
    LOCAL cpc IS COS(H_CAMP).
    LOCAL cps IS SIN(H_CAMP).
    RETURN LOOKDIRUP(f:FOREVECTOR * cpc - f:TOPVECTOR * cps, f:TOPVECTOR * cpc + f:FOREVECTOR * cps).
}

FUNCTION hdCamRelease {
    IF hdCamOK { SET hdCam:ENABLED TO FALSE. }
}

FUNCTION hdCamLive {
    IF NOT hdCamOK { RETURN FALSE. }
    IF NOT hdCam:ENABLED { RETURN FALSE. }
    RETURN hdCam:ACTIVE.
}

// ---------------------------------------------------------------- the runway
// the runway being approached: the nearest threshold, an end facing away from the track costing up to 20 km
FUNCTION hdPickRunway {
    LOCAL trk IS hdTrack().
    LOCAL best IS -1.
    LOCAL bestS IS 1E12.
    FROM { LOCAL k IS 0. } UNTIL k >= hdRwys:LENGTH STEP { SET k TO k + 1. } DO {
        LOCAL rw IS hdRwys[k].
        LOCAL sc IS rw[2]:DISTANCE.
        IF trk >= 0 { SET sc TO sc + 10000 * (1 - COS(rw[3] - trk)). }
        IF sc < bestS {
            SET bestS TO sc.
            SET best TO k.
        }
    }
    RETURN best.
}

FUNCTION hdSelectRunway {
    PARAMETER ix.
    IF ix < 0 OR ix >= hdRwys:LENGTH { RETURN. }
    SET hdRwyIx TO ix.
    LOCAL rw IS hdRwys[ix].
    LOCAL thr IS rw[2].
    LOCAL hdg IS rw[3].
    LOCAL w2 IS rw[5] / 2.
    LOCAL far IS rw[8].
    SET hdThr TO thr.
    SET hdPts TO LIST(hdDest(thr, hdg - 90, w2), hdDest(thr, hdg + 90, w2), hdDest(far, hdg - 90, w2),
                      hdDest(far, hdg + 90, w2), hdAlong(thr, hdg, rw[9]), hdAlong(thr, hdg, rw[10])).
    SET hdElevT TO -1000.
    hdRunwayElev().
    SET hdSwitchT TO -1.
}

// the surveyed elevation; an emergency site (none surveyed) the terrain's at its threshold, re-read every 2 s (kOS
// raycasts to the scenery -- the runway static -- once it is loaded, the terrain before). The far end: + slope x length.
FUNCTION hdRunwayElev {
    SET hdRwyFx TO 0.
    IF hdRwyIx < 0 { RETURN. }
    LOCAL rw IS hdRwys[hdRwyIx].
    IF rw[11] {
        IF TIME:SECONDS - hdElevT > 2 {
            SET hdElev TO rw[2]:TERRAINHEIGHT.
            SET hdElevT TO TIME:SECONDS.
        }
    } ELSE {
        SET hdElev TO rw[6].
    }
    SET hdElevFar TO hdElev + rw[7] * rw[4].
    IF hdAltMode = "RWY" AND ALT:RADAR < 2 * HD_RWY_RA_HI_FT * H_FTM {
        LOCAL p0 IS rw[2]:POSITION.             // the threshold; the vessel at the origin
        LOCAL ud IS VXCL(UP:VECTOR, rw[8]:POSITION - p0):NORMALIZED.
        LOCAL x IS VDOT(-p0, ud).
        IF ABS(VDOT(-p0, VCRS(UP:VECTOR, ud))) < rw[5] AND x < rw[4] + HD_RWY_RA_X {
            SET hdRwyFx TO MAX(0, MIN(1, x / HD_RWY_RA_X)).
        }
    }
}

// on final (below 12,000 ft, within 25 km, the track within 20 deg of the OTHER end of the picked runway for 3 s: an
// overhead approach): switch to the end the track is lined up on
FUNCTION hdFinalSwitch {
    IF hdRwyIx < 0 OR NOT hdFinalOn { RETURN. }
    LOCAL oi IS hdOther[hdRwyIx].
    LOCAL trk IS hdTrack().
    LOCAL lined IS FALSE.
    IF oi <> hdRwyIx AND trk >= 0 AND sHft < HD_FINAL_FT AND NOT hdWow {
        IF hdRwys[oi][2]:DISTANCE < HD_FINAL_KM * 1000 {
            IF ABS(hdNorm180(hdRwys[oi][3] - trk)) < HD_FINAL_DEG { SET lined TO TRUE. }
        }
    }
    IF NOT lined {
        SET hdSwitchT TO -1.
        RETURN.
    }
    IF hdSwitchT < 0 {
        SET hdSwitchT TO TIME:SECONDS.
    } ELSE IF TIME:SECONDS - hdSwitchT > 3 {
        hdSelectRunway(oi).
    }
}

FUNCTION hdRwyName {
    IF hdRwyIx < 0 { RETURN "none". }
    LOCAL s IS hdRwys[hdRwyIx][1].
    IF hdRwys[hdRwyIx][11] { SET s TO s + " (ELS)". }
    RETURN s.
}

// ---------------------------------------------------------------- the gear (the altitude, weight on wheels)
FUNCTION hdFindGear {
    hdGearMain:CLEAR().
    hdGearNose:CLEAR().
    LOCAL ps IS SHIP:PARTS.
    SET hdGearN TO ps:LENGTH.                   // T901: the part count the lists were found at (hdGearBounds re-finds when it changes)
    FOR pt IN ps {
        LOCAL nm IS pt:NAME:TOLOWER.
        IF nm:CONTAINS("maingear") { hdGearMain:ADD(pt). } ELSE IF nm:CONTAINS("nosegear") { hdGearNose:ADD(pt). }
    }
    // another craft (no part named main gear): its wheels (ModuleWheelBase: gear, fixed wheels, legs) -- the
    // larger group of those ahead of / behind the c.g. is the main gear (behind on a tie: a tricycle), the other the
    // nose gear (a taildragger's tail wheel)
    IF hdGearMain:LENGTH = 0 {
        LOCAL fw IS SHIP:FACING:FOREVECTOR.
        LOCAL ahead IS LIST().
        LOCAL behind IS LIST().
        FOR pt IN SHIP:PARTS {
            IF pt:HASMODULE("ModuleWheelBase") {
                IF VDOT(fw, pt:POSITION) > 0 { ahead:ADD(pt). } ELSE { behind:ADD(pt). }
            }
        }
        LOCAL mg IS CHOOSE ahead IF ahead:LENGTH > behind:LENGTH ELSE behind.
        LOCAL ng IS CHOOSE behind IF ahead:LENGTH > behind:LENGTH ELSE ahead.
        FOR pt IN mg { hdGearMain:ADD(pt). }
        FOR pt IN ng { hdGearNose:ADD(pt). }
    }
}

// the part bounds are costly to BUILD and cheap to READ: rebuilt every 2 s (which also catches the gear coming down)
// T901: a part lost (a crash blows the main gear off, SAIL 094237) leaves its PartValue in hdGearMain and its BoundsValue in
// hdBndMain, and kOS throws on bd:BOTTOMALT of a dead part (NullReference in PartValue.GetFacing: the landing program died).
// Once per game time (every read of the bounds goes through here first) the ship's part count is compared with the count the
// gear lists were found at; a change re-finds the gear on the live ship and drops the cached bounds, so a wreck reads like a
// craft with fewer / no gear parts (SHIP:BOUNDS when no wheel is left), never a dead part.
FUNCTION hdGearBounds {
    IF TIME:SECONDS <> hdGearChkT {
        SET hdGearChkT TO TIME:SECONDS.
        IF SHIP:PARTS:LENGTH <> hdGearN {
            hdFindGear().
            hdBndMain:CLEAR().
            hdBndNose:CLEAR().
            SET hdBndT TO -1000.
        }
    }
    IF TIME:SECONDS - hdBndT > 2 {
        hdBndMain:CLEAR().
        hdBndNose:CLEAR().
        FOR pt IN hdGearMain { hdBndMain:ADD(pt:BOUNDS). }
        FOR pt IN hdGearNose { hdBndNose:ADD(pt:BOUNDS). }
        IF hdBndMain:LENGTH = 0 { hdBndMain:ADD(SHIP:BOUNDS). }
        SET hdBndT TO TIME:SECONDS.
    }
}

// ---------------------------------------------------------------- state
FUNCTION hdState {
    SET bSnap TO hdCamLive().
    IF bSnap {
        LOCAL fac IS hdCam:FACING.
        SET bEye TO hdCam:POSITION.
        SET bFwd TO fac:FOREVECTOR.
        SET bUp TO fac:TOPVECTOR.
        SET bRight TO fac:STARVECTOR.
    }
    SET bU TO UP:VECTOR.
    LOCAL vsf IS SHIP:VELOCITY:SURFACE.
    SET bHasV TO vsf:MAG > 5.
    IF bHasV { SET bVhat TO vsf:NORMALIZED. }
    SET sKeas TO SQRT(2 * MAX(SHIP:Q * CONSTANT:ATMTOKPA * 1000, 0) / H_RHO0) * H_KT.
    SET sKgs TO SHIP:GROUNDSPEED * H_KT.
    hdRunwayElev().
    hdGearBounds().
    // the main gear's height (its parts' bounds; in the flare the tail is the lowest point): above the threshold's
    // elevation and, low down (below HD_RADALT_FT), its radar height
    LOCAL hb IS 1E9.
    FOR bd IN hdBndMain { SET hb TO MIN(hb, bd:BOTTOMALT). }
    LOCAL hasl IS hb.                           // the gear above sea level: the HUD's altitude above the radar's range
    SET hb TO hb - hdElev.
    LOCAL hr IS hb.
    IF hb < (HD_RADALT_FT + 1000) * H_FTM OR hdWow OR hdAltAsc {
        SET hr TO 1E9.
        FOR bd IN hdBndMain { SET hr TO MIN(hr, bd:BOTTOMALTRADAR). }
    }
    SET sRad TO hr < HD_RADALT_FT * H_FTM.
    SET sHft TO (CHOOSE hr IF sRad ELSE hb) / H_FTM + HD_ALT_OFS_FT.
    SET sHftT TO TIME:SECONDS.
    hdAltPick(hr, hb, hasl, TIME:SECONDS).
    // weight on wheels: the main gear within HD_WOW_M of the ground for HD_WOW_S; a bounce above HD_BOUNCE_M ends it
    IF hr < HD_WOW_M {
        IF hdWowT < 0 { SET hdWowT TO TIME:SECONDS. }
        IF TIME:SECONDS - hdWowT >= HD_WOW_S { SET hdWow TO TRUE. }
    } ELSE {
        SET hdWowT TO -1.
        IF hr > HD_BOUNCE_M {
            SET hdWow TO FALSE.
            SET hdWong TO FALSE.
        }
    }
    IF hdWow AND NOT hdWong AND hdBndNose:LENGTH > 0 {
        LOCAL hn IS 1E9.
        FOR bd IN hdBndNose { SET hn TO MIN(hn, bd:BOTTOMALTRADAR). }
        IF hn < HD_WOW_M {
            IF hdWongT < 0 { SET hdWongT TO TIME:SECONDS. }
            IF TIME:SECONDS - hdWongT >= HD_WOW_S { SET hdWong TO TRUE. }
        } ELSE {
            SET hdWongT TO -1.
        }
    }
}

// the HUD's altitude (sHdisp) and its letter (hdAltTag) by ALT MODE (hdAltMode), from the radar's height hr, the height
// above the runway hb and ASL hasl (m); OPS 1 (hdAltAsc): the mode switched as sRad changes. A change of source starts
// the value from where it was and blends to the new source over HD_ALT_TAU (hdAltOfs), so it never jumps
FUNCTION hdAltPick {
    PARAMETER hr, hb, hasl, now.
    hdAltSwitch().
    LOCAL tg IS "".
    IF hdAltMode = "RWY" AND hb / H_FTM < HD_RWY_FT { SET tg TO "W". }   // RWY: below HD_RWY_FT only
    ELSE IF hdAltMode = "RDR" AND (hdAltAsc OR sRad) { SET tg TO "R". }
    LOCAL h IS hdAltRaw(tg, hr, hb, hasl).
    IF hdAltT >= 0 {
        SET hdAltOfs TO hdAltOfs * CONSTANT:E ^ (-MAX(now - hdAltT, 0) / HD_ALT_TAU).
        IF tg <> hdAltTag { SET hdAltOfs TO hdAltOfs + hdAltRaw(hdAltTag, hr, hb, hasl) - h. }
        IF ABS(hdAltOfs) < 0.01 { SET hdAltOfs TO 0. }
    }
    SET hdAltTag TO tg.
    SET hdAltT TO now.
    SET sHdisp TO h + hdAltOfs.
}

// OPS 1's RDR / BARO switch (hdAltAsc): the mode follows sRad (the radar's height below HD_RADALT_FT)
FUNCTION hdAltSwitch {
    IF hdAltAsc {
        IF sRad <> hdAltRad0 { SET hdAltMode TO CHOOSE "RDR" IF sRad ELSE "BARO". }
        SET hdAltRad0 TO sRad.
    }
}

// the same radar test and switch with the HUD hidden (hdTick's hidden branch: no hdState runs), HD_ALT_HID_S apart; the
// ALT MODE button (lib_ascdisp) shows hdAltMode whether or not the HUD is drawn
FUNCTION hdAltHidden {
    IF NOT hdAltAsc { RETURN. }
    LOCAL now IS hdReal().
    IF now - hdAltHidT < HD_ALT_HID_S { RETURN. }
    SET hdAltHidT TO now.
    hdGearBounds().
    LOCAL hr IS 1E9.
    FOR bd IN hdBndMain { SET hr TO MIN(hr, bd:BOTTOMALTRADAR). }
    SET sRad TO hr < HD_RADALT_FT * H_FTM.
    hdAltSwitch().
}

FUNCTION hdAltRaw {                         // ft: the altitude of the source with letter tg
    PARAMETER tg, hr, hb, hasl.
    RETURN (CHOOSE hr IF tg = "R" ELSE (CHOOSE hdRwyW(hr, hb) IF tg = "W" ELSE hasl)) / H_FTM + HD_ALT_OFS_FT.
}

FUNCTION hdRwyW {                           // m: ALT MODE RWY's height: above the threshold's elevation, low over the
    PARAMETER hr, hb.                       //   runway the radar's (HD_RWY_RA_*)
    LOCAL f IS hdRwyFx * MAX(0, MIN(1, (HD_RWY_RA_HI_FT - hr / H_FTM) / (HD_RWY_RA_HI_FT - HD_RWY_RA_LO_FT))).
    RETURN hb + f * (hr - hb).
}

// ---------------------------------------------------------------- projection + ladder
FUNCTION hdProj {
    PARAMETER d.
    LOCAL zc IS VDOT(d, bFwd).
    IF zc <= 0.000001 {
        SET pOK TO FALSE.
        RETURN.
    }
    SET pOK TO TRUE.
    SET pU TO H_U0 + H_FPX * VDOT(d, bRight) / zc.
    SET pV TO H_VS - H_FPX * VDOT(d, bUp) / zc.
}

// ladder frame(e): the pivot's foot on elevation e's screen line, the unit vector along it and the unit normal
// toward HIGHER elevation (screen v runs down). The line runs along rh through elevation e's point on hf's plane; rh's
// step is not scaled by cos(e), so the line keeps one sense past the vertical and exists at +-90
// a mirrored picture of the ladder (rh is kept screen-right, so heads down the elevation runs against fN): TRUE
// where a higher elevation on the line lies on fN's far side; the rung is then turned 180 deg, its horns toward the
// horizon and its number on the higher side as in the upright picture
FUNCTION hdLadMirror {
    PARAMETER elv, hf.
    hdProj(hf * (COS(4) * COS(elv)) + bU * SIN(elv)).
    IF NOT pOK { RETURN FALSE. }
    LOCAL u0 IS pU.
    LOCAL v0 IS pV.
    hdProj(hf * (COS(4) * COS(elv + 1)) + bU * SIN(elv + 1)).
    IF NOT pOK { RETURN FALSE. }
    RETURN (pU - u0) * fNx + (pV - v0) * fNy < 0.
}

FUNCTION hdFrame {
    PARAMETER elv, hf, rh, pivU, pivV.
    LOCAL ce IS COS(elv).
    LOCAL se IS SIN(elv).
    hdProj(hf * (COS(4) * ce) + bU * se - rh * SIN(4)).
    IF NOT pOK { RETURN FALSE. }
    LOCAL lu IS pU.
    LOCAL lv IS pV.
    hdProj(hf * (COS(4) * ce) + bU * se + rh * SIN(4)).
    IF NOT pOK { RETURN FALSE. }
    LOCAL du IS pU - lu.
    LOCAL dv IS pV - lv.
    LOCAL segLen IS SQRT(du * du + dv * dv).
    IF segLen < 0.001 { RETURN FALSE. }
    SET fUx TO du / segLen.
    SET fUy TO dv / segLen.
    LOCAL s IS (pivU - lu) * fUx + (pivV - lv) * fUy.
    SET fFootU TO lu + fUx * s.
    SET fFootV TO lv + fUy * s.
    SET fNx TO fUy.
    SET fNy TO 0 - fUx.
    RETURN TRUE.
}

// The line on hdAzOn's plane (stage 1's launch azimuth, a split-S's turn plane), always shown: its segments run along
// the screen's picture of hdAzN (the plane's normal: level when the wings are square to the plane), at the elevation
// hdAzPit on that plane (the pitch to fly; the split-S's: 0, the horizon), or through the ladder's pivot (the FD box)
// when hdAzPit is below -90 or hf is zero; no rungs. The gap between its arms is at the cross (hdAzGap)
FUNCTION hdAzLine {
    PARAMETER pivU, pivV, hf, rh.
    SET hdAzUOk TO FALSE.
    IF hdAzPit >= -90 AND hf:MAG > 0.000001 {
        IF hdFrame(MIN(90, hdAzPit), hf, rh, pivU, pivV) {
            hdAzUSet().
            LOCAL rec IS hdHzTab[hdSnapIx(ARCTAN2(0 - fUy, fUx), 180)].
            hdAzGap(fFootU, fFootV).
            LOCAL k IS 0.
            FOR sg IN LIST(-1, 1) {
                FROM { LOCAL j IS 0. } UNTIL j >= H_HZ_SEGS STEP { SET j TO j + 1. } DO {
                    LOCAL dd IS sg * (H_HZ_GAP + (j + 0.5) * H_HZ_SEG).
                    hdBlitLad(pHz[k], rec, hdGapU + fUx * dd, hdGapV + fUy * dd).
                    SET k TO k + 1.
                }
            }
            SET hdHzOn TO TRUE.
        } ELSE IF hdHzOn {
            hdHideFrom(pHz, 0).
            SET hdHzOn TO FALSE.
        }
        RETURN.
    }
    LOCAL du IS VDOT(hdAzN, bRight).
    LOCAL dv IS 0 - VDOT(hdAzN, bUp).
    LOCAL m IS SQRT(du * du + dv * dv).
    IF m < 0.000001 {
        IF hdHzOn {
            hdHideFrom(pHz, 0).
            SET hdHzOn TO FALSE.
        }
        RETURN.
    }
    SET fUx TO du / m.
    SET fUy TO dv / m.
    hdAzUSet().
    LOCAL ang IS ARCTAN2(0 - fUy, fUx).
    LOCAL rec IS hdHzTab[hdSnapIx(ang, 180)].
    hdAzGap(pivU, pivV).
    LOCAL k IS 0.
    FOR sg IN LIST(-1, 1) {
        FROM { LOCAL j IS 0. } UNTIL j >= H_HZ_SEGS STEP { SET j TO j + 1. } DO {
            LOCAL dd IS sg * (H_HZ_GAP + (j + 0.5) * H_HZ_SEG).
            hdBlitLad(pHz[k], rec, hdGapU + fUx * dd, hdGapV + fUy * dd).
            SET k TO k + 1.
        }
    }
    SET hdHzOn TO TRUE.
}

FUNCTION hdAzUSet {                         // the line's direction on the glass, for hdAzRung
    SET hdAzUx TO fUx.
    SET hdAzUy TO fUy.
    SET hdAzUOk TO TRUE.
}

// a rung on hdAzOn's plane: along the azimuth line on the glass (hdAzUSet), the sense of its own frame kept. In
// perspective the plane's rungs are parallel in space but fan out on the glass away from the camera axis (several deg
// past the vertical with the camera off the plane); the HUD draws them parallel to the line
FUNCTION hdAzRung {
    IF NOT hdAzUOk { RETURN. }
    LOCAL sg IS CHOOSE 1 IF fUx * hdAzUx + fUy * hdAzUy >= 0 ELSE -1.
    SET fUx TO sg * hdAzUx.
    SET fUy TO sg * hdAzUy.
    SET fNx TO fUy.
    SET fNy TO 0 - fUx.
}

// the gap of hdAzLine's line through (au, av) along (fUx, fUy) -> hdGapU / hdGapV: the cross's (the boresight's) foot
// on the line once the roll program is done (hdAzRoll); before, the line's point straight above or below the cross,
// at most half the arms' segments along the line from the foot (a line steep on the glass stays about the cross)
FUNCTION hdAzGap {
    PARAMETER au, av.
    LOCAL s IS (H_U0 - au) * fUx + (H_V0 - av) * fUy.
    IF NOT hdAzRoll AND ABS(fUx) > 0.000001 {
        LOCAL lim IS H_HZ_SEGS * H_HZ_SEG / 2.
        SET s TO s + MAX(0 - lim, MIN(lim, (H_U0 - au) / fUx - s)).
    }
    SET hdGapU TO au + fUx * s.
    SET hdGapV TO av + fUy * s.
}

FUNCTION hdLadder {
    PARAMETER pivU, pivV, withRungs.
    LOCAL azk IS "".                      // hdAzOn: the ladder on hdAzN's plane: its angle, the nose's angle out of
    LOCAL hf IS bFwd - bU * VDOT(bFwd, bU). //   the plane and within it
    IF hdAzOn {
        SET hf TO VCRS(hdAzN, bU).          // the rungs' heading: the plane's, not the nose's
        SET azk TO ",az" + ROUND(ARCTAN2(VDOT(hdAzN, bUp), VDOT(hdAzN, bRight)) / HD_LAD_DEL_RL)
            + "," + ROUND(ARCSIN(MAX(-1, MIN(1, VDOT(bFwd, hdAzN)))) / HD_LAD_DEL_EL)
            + "," + ROUND(ARCTAN2(VDOT(bFwd, bU), VDOT(bFwd, hf)) / HD_LAD_DEL_EL) + "," + ROUND(hdAzPit / HD_LAD_DEL_EL)
            + "," + hdAzRoll.
    }
    IF hf:MAG < 0.000001 {
        hdLadderOff().
        IF hdAzOn { hdAzLine(pivU, pivV, hf, hf). }
        RETURN.
    }
    SET hf TO hf:NORMALIZED.
    LOCAL rh IS VCRS(bU, hf):NORMALIZED.
    IF VDOT(rh, bRight) < 0 { SET rh TO V(0, 0, 0) - rh. }
    // only what can reach the glass: a line of elevation e lies |e - camEl| from the camera axis
    LOCAL camEl IS ARCSIN(MAX(-1, MIN(1, VDOT(bFwd, bU)))).
    // the ladder's picture is set by the camera's elevation and roll, the pivot and the rungs' switch: unchanged to
    // HD_LAD_DEL_EL / HD_LAD_DEL_RL and a pixel, nothing is redrawn
    LOCAL lkey IS ROUND(camEl / HD_LAD_DEL_EL) + "," + ROUND(ARCTAN2(VDOT(rh, bUp), VDOT(rh, bRight)) / HD_LAD_DEL_RL)
        + "," + ROUND(pivU) + "," + ROUND(pivV) + "," + withRungs + azk.
    IF lkey = hdLadKey { RETURN. }
    SET hdLadKey TO lkey.
    IF hdAzOn { hdAzLine(pivU, pivV, hf, rh). }
    // the horizon: HZ_SEGS segments per arm from the gap outward, each shown only whole
    LOCAL hzDrawn IS hdAzOn.
    IF NOT hdAzOn AND ABS(camEl) <= hdLadWin {
        IF hdFrame(0, hf, rh, pivU, pivV) {
            LOCAL rec IS hdHzTab[hdSnapIx(ARCTAN2(0 - fUy, fUx), 180)].
            LOCAL k IS 0.
            FOR sg IN LIST(-1, 1) {
                FROM { LOCAL j IS 0. } UNTIL j >= H_HZ_SEGS STEP { SET j TO j + 1. } DO {
                    LOCAL dd IS sg * (H_HZ_GAP + (j + 0.5) * H_HZ_SEG).
                    hdBlitLad(pHz[k], rec, fFootU + fUx * dd, fFootV + fUy * dd).
                    SET k TO k + 1.
                }
            }
            SET hzDrawn TO TRUE.
            SET hdHzOn TO TRUE.
        }
    }
    IF NOT hzDrawn {
        IF hdHzOn {
            hdHideFrom(pHz, 0).
            SET hdHzOn TO FALSE.
        }
    }
    IF NOT withRungs {
        hdHideRange(pRung, 0, hdRungHi).
        hdHideTRange(pRnum, 0, hdRungHi).
        SET hdRungHi TO 0.
        RETURN.
    }
    // the rungs: every 5 deg within the window of the camera axis's elevation; on hdAzOn's plane within the window of
    // the nose's angle in the plane, on through the vertical (90, 95, 100, ... past straight up, -90, -95 ... past
    // straight down, the horns toward the horizon on the azimuth), wrapped at 180
    LOCAL eC IS camEl.
    LOCAL eLo IS -85.
    LOCAL eHi IS 85.
    IF hdAzOn {
        SET eC TO ARCTAN2(VDOT(bFwd, bU), VDOT(bFwd, hf)).
        SET eLo TO eC - hdLadWin.
        SET eHi TO eC + hdLadWin.
    }
    LOCAL elv IS MAX(eLo, CEILING((eC - hdLadWin) / 5) * 5).
    LOCAL eTop IS MIN(eHi, eC + hdLadWin).
    LOCAL slot IS 0.
    UNTIL elv > eTop OR slot >= HD_RUNG_N {
        LOCAL ev IS elv.
        IF ev > 180 { SET ev TO ev - 360. } ELSE IF ev <= -180 { SET ev TO ev + 360. }
        IF ev <> 0 {
            IF hdFrame(ev, hf, rh, pivU, pivV) {
                IF hdAzOn { hdAzRung(). }
                IF hdLadMirror(ev, hf) {
                    SET fUx TO 0 - fUx. SET fUy TO 0 - fUy. SET fNx TO 0 - fNx. SET fNy TO 0 - fNy.
                }
                LOCAL ix IS hdSnapIx(ARCTAN2(0 - fUy, fUx), 360).
                LOCAL rec IS hdRnTab[ix].
                IF ev > 0 { SET rec TO hdRpTab[ix]. }
                IF hdBlitLad(pRung[slot], rec, fFootU, fFootV) {
                    LOCAL rnV IS fFootV + fUy * H_LAD_ALONG + fNy * H_LAD_UP.
                    IF rnV + H_LAD_FS / 2 <= H_LAD_FB {
                        hdText(pRnum[slot], "" + ABS(ev), fFootU + fUx * H_LAD_ALONG + fNx * H_LAD_UP, rnV).
                    } ELSE {                                // its number below the floor: the rung goes with it
                        hdHide(pRung[slot]).
                        hdHideT(pRnum[slot]).
                    }
                } ELSE {
                    hdHideT(pRnum[slot]).                   // its number goes with it, never alone
                }
                SET slot TO slot + 1.
            }
        }
        SET elv TO elv + 5.
    }
    hdHideRange(pRung, slot, hdRungHi).
    hdHideTRange(pRnum, slot, hdRungHi).
    SET hdRungHi TO slot.
}

FUNCTION hdLadderOff {
    SET hdLadKey TO "".
    IF hdHzOn {
        hdHideFrom(pHz, 0).
        SET hdHzOn TO FALSE.
    }
    hdHideRange(pRung, 0, hdRungHi).
    hdHideTRange(pRnum, 0, hdRungHi).
    SET hdRungHi TO 0.
}

// ---------------------------------------------------------------- the runway overlay: outline, aim circles, centreline
// cuts a world segment (points relative to the eye) RWY_ZNEAR in front of the eye BEFORE projecting it, so a corner
// behind the eye still leaves the visible part of its edges; a cut end is not a real one.
// -> gAu gAv gBu gBv (screen), gRa gRb (real ends); FALSE when nothing is in front.
FUNCTION hdCut {
    PARAMETER da, db.
    LOCAL za IS VDOT(da, bFwd).
    LOCAL zb IS VDOT(db, bFwd).
    IF za < H_ZNEAR AND zb < H_ZNEAR { RETURN FALSE. }
    SET gRa TO za >= H_ZNEAR.
    SET gRb TO zb >= H_ZNEAR.
    LOCAL a3 IS da.
    LOCAL b3 IS db.
    IF NOT gRa {
        SET a3 TO da + (db - da) * ((H_ZNEAR - za) / (zb - za)).
    } ELSE IF NOT gRb {
        SET b3 TO db + (da - db) * ((H_ZNEAR - zb) / (za - zb)).
    }
    hdProj(a3).
    IF NOT pOK { RETURN FALSE. }
    SET gAu TO pU.
    SET gAv TO pV.
    hdProj(b3).
    IF NOT pOK { RETURN FALSE. }
    SET gBu TO pU.
    SET gBv TO pV.
    RETURN TRUE.
}

// chains a screen line: cut to the glass shrunk by RWY_CLIP (Cyrus-Beck), then n overlapping copies of the longest
// segment (96 / 32 / 12 / 6 px) <= its length, the first starting and the last ending on its ends, neighbours
// overlapping >= RWY_OVL; the sprite rwyNN_TTT at the line's angle (2 deg over 180). Shorter than 6 px: not drawn.
FUNCTION hdChain {
    PARAMETER au, av, bu, bv.
    LOCAL du IS bu - au.
    LOCAL dv IS bv - av.
    LOCAL t0 IS 0.
    LOCAL t1 IS 1.
    LOCAL ok IS TRUE.
    FROM { LOCAL k IS 0. } UNTIL k >= hdGlassHP:LENGTH OR NOT ok STEP { SET k TO k + 1. } DO {
        LOCAL hp IS hdGlassHP[k].
        LOCAL num IS hp[0] * au + hp[1] * av - (hp[2] + H_CLIP).
        LOCAL den IS hp[0] * du + hp[1] * dv.
        IF ABS(den) < 0.000000000001 {
            IF num < 0 { SET ok TO FALSE. }
        } ELSE {
            LOCAL tt IS (0 - num) / den.
            IF den > 0 { SET t0 TO MAX(t0, tt). } ELSE { SET t1 TO MIN(t1, tt). }
            IF t0 > t1 { SET ok TO FALSE. }
        }
    }
    IF NOT ok { RETURN. }
    LOCAL a0u IS au + du * t0.
    LOCAL a0v IS av + dv * t0.
    LOCAL lu IS du * (t1 - t0).
    LOCAL lv IS dv * (t1 - t0).
    LOCAL lp IS SQRT(lu * lu + lv * lv).
    LOCAL fam IS -1.
    FROM { LOCAL k IS 0. } UNTIL k >= hdSegL:LENGTH OR fam >= 0 STEP { SET k TO k + 1. } DO {
        IF lp >= hdSegL[k] { SET fam TO k. }
    }
    IF fam < 0 { RETURN. }
    LOCAL sl IS hdSegL[fam].
    LOCAL uu IS lu / lp.
    LOCAL uv IS lv / lp.
    LOCAL rec IS hdRwyTab[fam][hdSnapIx(ARCTAN2(0 - uv, uu), 180)].
    LOCAL n IS 1.
    IF lp - sl >= 0.000001 { SET n TO 1 + CEILING((lp - sl) / (sl - H_OVL)). }
    FROM { LOCAL i IS 0. } UNTIL i >= n OR hdSeg >= HD_RWY_N STEP { SET i TO i + 1. } DO {
        LOCAL s IS sl / 2.
        IF n > 1 { SET s TO sl / 2 + (lp - sl) * i / (n - 1). }
        hdBlitNT(pRwy[hdSeg], rec, a0u + uu * s, a0v + uv * s).
        SET hdSeg TO hdSeg + 1.
    }
}

// an outline edge: its real corners pushed out half a stroke so the corners close
FUNCTION hdLine {
    PARAMETER da, db.
    IF NOT hdCut(da, db) { RETURN. }
    LOCAL du IS gBu - gAu.
    LOCAL dv IS gBv - gAv.
    LOCAL dd IS SQRT(du * du + dv * dv).
    IF dd >= 0.000000001 {
        LOCAL eu IS du / dd * H_HSTROKE.
        LOCAL ev IS dv / dd * H_HSTROKE.
        IF gRa {
            SET gAu TO gAu - eu.
            SET gAv TO gAv - ev.
        }
        IF gRb {
            SET gBu TO gBu + eu.
            SET gBv TO gBv + ev.
        }
    }
    hdChain(gAu, gAv, gBu, gBv).
}

// the centreline, circle edge to circle edge: an end whose circle is behind the eye is where the cut put it, and the
// glass clip then ends the line at the glass edge; nothing when the circles (nearly) touch
FUNCTION hdCentre {
    PARAMETER dOgs, dIgs.
    IF NOT hdCut(dOgs, dIgs) { RETURN. }
    LOCAL du IS gBu - gAu.
    LOCAL dv IS gBv - gAv.
    LOCAL dd IS SQRT(du * du + dv * dv).
    LOCAL ta IS 0.
    LOCAL tb IS 0.
    IF gRa { SET ta TO H_AIM_R. }
    IF gRb { SET tb TO H_AIM_R. }
    IF dd - ta - tb <= H_AIM_MIN { RETURN. }
    LOCAL eu IS du / dd.
    LOCAL ev IS dv / dd.
    hdChain(gAu + eu * ta, gAv + ev * ta, gBu - eu * tb, gBv - ev * tb).
}

FUNCTION hdRunway {
    IF NOT hdRwyOn OR hdRwyIx < 0 {
        hdRwyOff().
        RETURN.
    }
    // the whole group when it cannot show: every point lies within ~3.5 km of the threshold (the OGS aim point up to
    // 2.8 km out, the SLF's far end 3.2 km in); when that cluster's cone is outside the window: no work, hidden once
    LOCAL dth IS (CHOOSE hdInPos[0] IF hdInOn ELSE hdThr:ALTITUDEPOSITION(hdElev)) - bEye.  // hdInPos (CHECK)
    LOCAL dthm IS dth:MAG.
    IF dthm > 7000 {
        IF VANG(bFwd, dth) > hdLadWin + ARCTAN(3500 / dthm) {
            hdRwyOff().
            RETURN.
        }
    }
    SET hdRwyVis TO TRUE.
    LOCAL pL0 IS (CHOOSE hdInPos[1] IF hdInOn ELSE hdPts[0]:ALTITUDEPOSITION(hdElev)) - bEye.
    LOCAL pR0 IS (CHOOSE hdInPos[2] IF hdInOn ELSE hdPts[1]:ALTITUDEPOSITION(hdElev)) - bEye.
    LOCAL pL1 IS (CHOOSE hdInPos[3] IF hdInOn ELSE hdPts[2]:ALTITUDEPOSITION(hdElevFar)) - bEye.
    LOCAL pR1 IS (CHOOSE hdInPos[4] IF hdInOn ELSE hdPts[3]:ALTITUDEPOSITION(hdElevFar)) - bEye.
    LOCAL pAo IS (CHOOSE hdInPos[5] IF hdInOn ELSE hdPts[4]:ALTITUDEPOSITION(hdElev)) - bEye.
    LOCAL pAi IS (CHOOSE hdInPos[6] IF hdInOn ELSE hdPts[5]:ALTITUDEPOSITION(hdElev)) - bEye.
    SET hdSeg TO 0.
    hdLine(pL0, pR0).                               // the threshold
    hdLine(pL0, pL1).                               // the left edge
    hdLine(pR0, pR1).                               // the right edge
    hdLine(pL1, pR1).                               // the far end
    hdProj(pAo).                                    // the aim circles, shown whole inside the glass
    IF pOK { hdBlitGlass(pAim[0], SP_AIM, pU, pV). } ELSE { hdHide(pAim[0]). }
    hdProj(pAi).
    IF pOK { hdBlitGlass(pAim[1], SP_AIM, pU, pV). } ELSE { hdHide(pAim[1]). }
    hdCentre(pAo, pAi).
    hdHideRange(pRwy, hdSeg, hdSegHi).
    SET hdSegHi TO hdSeg.
}

FUNCTION hdRwyOff {
    IF hdRwyVis {
        hdHideRange(pRwy, 0, hdSegHi).
        SET hdSegHi TO 0.
        hdHide(pAim[0]).
        hdHide(pAim[1]).
        SET hdRwyVis TO FALSE.
    }
}

// ---------------------------------------------------------------- the fixed symbology
// In hdSpdMode 1 (VI, the ascent after SRB SEP) the tape runs in units of 10 m/s, so the KEAS tape's steps (a tick
// every 5, a label every 10) are 50 and 100 m/s; a label reads km/s ("7.6"). hdSpdMode 2 (an RTLS) the same in m/s of
// VHH, signed ("-0.5")
FUNCTION hdSpdLab {
    PARAMETER k.
    IF hdSpdMode = 0 { RETURN "" + k. }
    LOCAL a IS ABS(k).
    RETURN (CHOOSE "-" IF k < 0 ELSE "") + FLOOR(a / 100) + "." + MOD(ROUND(a / 10), 10).
}

FUNCTION hdSpdTxt {                         // the speed's digits by the velocity vector (decluttered)
    PARAMETER keas.
    IF hdSpdMode = 0 { RETURN "" + ROUND(keas). }
    RETURN "" + ROUND(hdSpdV / 1000, 2).
}

FUNCTION hdScales {
    PARAMETER tapes.
    LOCAL vc IS H_VC.
    LOCAL half IS H_HALF.
    LOCAL keas IS CHOOSE hdSpdV / 10 IF hdSpdMode <> 0 ELSE sKeas.  // VI or VHH in 10 m/s units
    LOCAL hft IS sHdisp.                            // the HUD's altitude: ASL above the radar's range
    IF tapes {
        // KEAS, increasing DOWNWARD; the tape is redrawn only when its value moves a pixel
        LOCAL tk IS H_TAPE_KT.
        LOCAL per IS H_PER_KT.
        LOCAL nt IS 0.
        LOCAL nn IS 0.
        LOCAL kKey IS ROUND(keas * per).
        LOCAL aKey IS ROUND(hft * H_PER_FT).
      IF kKey <> hdTapeKK {
        SET hdTapeKK TO kKey.
        LOCAL k IS FLOOR((keas - tk / 2) / 5) * 5.
        LOCAL kEnd IS FLOOR(keas + tk / 2) + 5.
        UNTIL k > kEnd {
            LOCAL vy IS vc + (k - keas) * per.
            IF ABS(vy - vc) <= half {
                IF MOD(k, 10) = 0 {
                    IF nn < HD_TAPE_N {
                        hdText(pKnum[nn], hdSpdLab(k), H_XS, vy).
                        SET nn TO nn + 1.
                    }
                } ELSE {
                    IF nt < HD_TAPE_N {
                        hdBlit(pKtick[nt], SP_TICK, H_XS, vy).
                        SET nt TO nt + 1.
                    }
                }
            }
            SET k TO k + 5.
        }
        hdHideFrom(pKtick, nt).
        hdHideTFrom(pKnum, nn).
      }
      IF aKey <> hdTapeKA {
        SET hdTapeKA TO aKey.
        // altitude, ft, increasing UPWARD
        LOCAL tf IS H_TAPE_FT.
        LOCAL pera IS H_PER_FT.
        SET nt TO 0.
        SET nn TO 0.
        LOCAL k IS FLOOR((hft - tf / 2) / 500) * 500.         // its own (the KEAS block may be skipped)
        LOCAL kEnd IS FLOOR(hft + tf / 2) + 500.
        UNTIL k > kEnd {
            LOCAL vy IS vc - (k - hft) * pera.
            IF ABS(vy - vc) <= half AND k >= 0 {
                IF MOD(k, 1000) = 0 {
                    LOCAL kk IS ROUND(k / 1000).
                    LOCAL lab IS "" + kk.
                    IF kk > 0 AND (MOD(kk, 5) = 0 OR kk = 1) { SET lab TO kk + "K". }
                    IF nn < HD_TAPE_N {
                        hdText(pAnum[nn], lab, H_XA, vy).
                        SET nn TO nn + 1.
                    }
                } ELSE {
                    IF nt < HD_TAPE_N {
                        hdBlit(pAtick[nt], SP_TICK, H_XA, vy).
                        SET nt TO nt + 1.
                    }
                }
            }
            SET k TO k + 500.
        }
        hdHideFrom(pAtick, nt).
        hdHideTFrom(pAnum, nn).
      }
        IF NOT hdBoxOn {                            // the index boxes never move: placed once
            hdBlit(sKbox, SP_BOX, H_BOX_KX, H_BOX_Y).
            hdBlit(sAbox, SP_BOX, H_BOX_AX, H_BOX_Y).
            SET hdBoxOn TO TRUE.
        }
        hdHideT(tKdig).
        hdHideT(tAdig).
        // the altitude's letter (R the radar's, W the runway's) beside the altitude tick: aligned with the tick but
        // right of the GS error triangle, clear of it
        IF hdAltTag <> "" { hdText(tArad, hdAltTag, hdRadX, H_VC). } ELSE { hdHideT(tArad). }
    } ELSE {
        hdHideT(tArad).
        SET hdTapeKK TO -99999.                     // the tapes redraw in full when they come back
        SET hdTapeKA TO -99999.
        hdHideFrom(pKtick, 0).
        hdHideFrom(pAtick, 0).
        hdHideTFrom(pKnum, 0).
        hdHideTFrom(pAnum, 0).
        IF hdBoxOn {
            hdHide(sKbox).
            hdHide(sAbox).
            SET hdBoxOn TO FALSE.
        }
        IF hdWow {
            // after main-gear touchdown the speed moves to the boresight: KEAS, the groundspeed once the nose is down
            LOCAL spd IS "" + ROUND(keas).
            IF hdWong { SET spd TO "G" + ROUND(sKgs). }
            hdText(tKdig, spd, H_U0 - H_BORE_DX, H_V0 - H_BORE_DY).
            hdHideT(tAdig).
        } ELSE {
            // decluttered: the two values ride the velocity vector (speed bottom-right at its top-left corner,
            // altitude bottom-left at its top-right, VV_GAP out); gVVu / gVVv = the frozen-FD point without one
            LOCAL dxv IS H_VV_HW + H_VV_GAP.
            LOCAL dyv IS H_VV_TOP + H_VV_GAP.
            hdText(tKdig, hdSpdTxt(keas), gVVu - dxv, gVVv - dyv).
            LOCAL altTxt IS "" + hdAltDig(hft).
            IF hdAltTag <> "" { SET altTxt TO altTxt + " " + hdAltTag. }      // "1000 R"
            hdText(tAdig, altTxt, gVVu + dxv, gVVv - dyv).
        }
    }
    // speedbrake: actual above pointing down, command below pointing up; LEFT = closed; each tip ON its mark: 0 at
    // SB_B0, 98.6 at SB_B1 (the line's end), the ticks between at 25 / 50 / 75 %
    hdBlit(sSbAct, SP_SBDN, H_SB_B0 + (H_SB_B1 - H_SB_B0) * MAX(0, MIN(1, hdSb / H_SB_FULL)), H_SB_YB - H_SB_TIP).
    hdBlit(sSbCmd, SP_SBUP, H_SB_B0 + (H_SB_B1 - H_SB_B0) * MAX(0, MIN(1, hdSbc / H_SB_FULL)), H_SB_YB + H_SB_TIP).
    hdText(tCtl, hdCtlTxt, H_XM, H_YC).
}

// ---------------------------------------------------------------- one update
FUNCTION hdRender {
    LOCAL wd IS hdWow AND NOT hdNoDecl.
    LOCAL wg IS hdWong AND NOT hdNoDecl.
    LOCAL tapes IS (NOT wd) AND (hdNoDecl OR sHft > H_DECL).
    LOCAL refU IS H_U0.
    LOCAL refV IS H_FDV.
    IF bSnap {
        // the velocity vector: in the field, and not after main-gear touchdown, nor in the FD-square mode (hdFdMode:
        // TAEM before PRFNL, where the frozen FD square is the reference and the ladder's pivot)
        LOCAL refOK IS FALSE.
        IF bHasV AND NOT wd AND NOT hdFdMode {
            hdProj(bVhat).
            IF pOK {
                IF pU >= H_FL AND pU <= H_FR AND pV >= H_FT AND pV <= H_FB {
                    SET refOK TO TRUE.
                    SET refU TO pU.
                    SET refV TO pV.
                }
            }
        }
        // the horizon at every height, the rungs above the declutter (OPS 1, hdAltAsc: at every height); on the rollout
        // the ladder about the boresight until the nose gear is down, then none
        IF wg {
            hdLadderOff().
        } ELSE IF wd {
            hdLadder(H_U0, H_V0, TRUE).
        } ELSE {
            hdLadder(refU, refV, tapes OR hdAltAsc).
        }
        hdRunway().
        IF NOT hdBoreOn {
            hdBlit(sBore, SP_BORE, H_U0, H_V0).
            SET hdBoreOn TO TRUE.
        }
        IF refOK { hdBlit(sFpm, SP_FPM, refU, refV). } ELSE { hdHide(sFpm). }
        SET hdConfOn TO TRUE.
    } ELSE {
        // the camera not snapped: the conformal symbols hide, the fixed ones stay
        IF hdConfOn {
            hdLadderOff().
            hdRwyOff().
            hdHide(sBore).
            SET hdBoreOn TO FALSE.
            hdHide(sFpm).
            SET hdConfOn TO FALSE.
        }
    }
    SET gVVu TO refU.
    SET gVVv TO refV.
    IF NOT hdStaticOn {
        hdBlit(sSbScale, SP_SBSCALE, H_SB_B0, H_SB_YB).
        SET hdStaticOn TO TRUE.
    }
    hdScales(tapes).
}

// HD_CS_CHECK: hdState on the values hdCsIn read (the C# shadow got the same), generated from
// hdState
FUNCTION hdStateK {
    PARAMETER inp.
    SET bSnap TO inp[0].
    IF bSnap {
        SET bEye TO inp[4].
        SET bFwd TO inp[1].
        SET bUp TO inp[2].
        SET bRight TO inp[3].
    }
    SET bU TO inp[5].
    LOCAL vsf IS inp[6].
    SET bHasV TO vsf:MAG > 5.
    IF bHasV { SET bVhat TO vsf:NORMALIZED. }
    SET sKeas TO SQRT(2 * MAX(inp[7] * CONSTANT:ATMTOKPA * 1000, 0) / H_RHO0) * H_KT.
    SET sKgs TO inp[8] * H_KT.
    hdRunwayElev().
    hdGearBounds().
    // the main gear's height (its parts' bounds; in the flare the tail is the lowest point): above the threshold's
    // elevation and, low down (below HD_RADALT_FT), its radar height
    LOCAL hb IS 1E9.
    FOR bd IN inp[10] { SET hb TO MIN(hb, bd). }
    LOCAL hasl IS hb.                           // the gear above sea level: the HUD's altitude above the radar's range
    SET hb TO hb - hdElev.
    LOCAL hr IS hb.
    IF hb < (HD_RADALT_FT + 1000) * H_FTM OR hdWow OR hdAltAsc {
        SET hr TO 1E9.
        FOR bd IN inp[11] { SET hr TO MIN(hr, bd). }
    }
    SET sRad TO hr < HD_RADALT_FT * H_FTM.
    SET sHft TO (CHOOSE hr IF sRad ELSE hb) / H_FTM + HD_ALT_OFS_FT.
    SET sHftT TO TIME:SECONDS.
    hdAltPick(hr, hb, hasl, inp[9]).
    // weight on wheels: the main gear within HD_WOW_M of the ground for HD_WOW_S; a bounce above HD_BOUNCE_M ends it
    IF hr < HD_WOW_M {
        IF hdWowT < 0 { SET hdWowT TO inp[9]. }
        IF inp[9] - hdWowT >= HD_WOW_S { SET hdWow TO TRUE. }
    } ELSE {
        SET hdWowT TO -1.
        IF hr > HD_BOUNCE_M {
            SET hdWow TO FALSE.
            SET hdWong TO FALSE.
        }
    }
    IF hdWow AND NOT hdWong AND inp[12]:LENGTH > 0 {
        LOCAL hn IS 1E9.
        FOR bd IN inp[12] { SET hn TO MIN(hn, bd). }
        IF hn < HD_WOW_M {
            IF hdWongT < 0 { SET hdWongT TO inp[9]. }
            IF inp[9] - hdWongT >= HD_WOW_S { SET hdWong TO TRUE. }
        } ELSE {
            SET hdWongT TO -1.
        }
    }
}

// ---------------------------------------------------------------- the math in the Holo HUD addon (C#)
FUNCTION hdCsOff {                          // any failure: kOS draws from now on, for the flight
    PARAMETER why.
    IF hdWinReg { hdWinOff("the HUD math went to kOS: " + why). }     // T730: kOS's own update writes the widgets
    IF HD_CS_CHECK AND hdCsOn { ADDONS:HOLO:HUDDRY(FALSE). }
    SET HD_CS_ERR TO why.
    SET HD_CS_STATE TO "kOS (" + why + ")".
    SET hdCsOn TO FALSE.
    SET hdCsG TO FALSE.
    SET HD_CS TO FALSE.
    SET HD_CS_CHECK TO FALSE.
    SET hdInOn TO FALSE.
}

FUNCTION hdCsSetup {                        // hdInit's end: the layout, sprite tables and slots to the addon
    SET hdCsOn TO FALSE.
    SET hdCsG TO FALSE.
    IF NOT (HD_CS OR HD_CS_CHECK) {
        SET HD_CS_STATE TO "kOS (HD_CS off)".
        RETURN.
    }
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("HOLO") { SET why TO "no Holo HUD addon". }
    ELSE IF NOT ADDONS:HOLO:AVAILABLE { SET why TO "the Holo HUD addon is not available". }
    ELSE IF NOT ADDONS:HOLO:HASSUFFIX("HUDSETUP") { SET why TO "the Holo HUD addon has no HUD (an older DLL)". }
    ELSE {
        LOCAL er IS ADDONS:HOLO:HUDSETUP(CONSTANT:ATMTOKPA).
        IF er <> "" { SET why TO "HUDSETUP: " + er. }
    }
    IF why <> "" {
        hdCsOff(why).
        RETURN.
    }
    SET hdCsOn TO TRUE.
    SET HD_CS_STATE TO CHOOSE "CHECK" IF HD_CS_CHECK ELSE "C#".
    SET hdCsAp TO FALSE.                    // T680 S3: the widget writes in C# too (HDAPPLY)?
    IF HD_CS_AP AND ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:AVAILABLE { SET hdCsAp TO ADDONS:KALS:HASSUFFIX("HDAPPLY"). } }
}

// the game's values hdState reads, read here at once (hdRunwayElev and hdGearBounds first, as hdState runs them)
FUNCTION hdCsIn {
    LOCAL bs IS hdCamLive().
    hdRunwayElev().
    hdGearBounds().
    LOCAL bm IS LIST().
    LOCAL bmr IS LIST().
    LOCAL bnr IS LIST().
    FOR bd IN hdBndMain {
        bm:ADD(bd:BOTTOMALT).
        bmr:ADD(bd:BOTTOMALTRADAR).
    }
    FOR bd IN hdBndNose { bnr:ADD(bd:BOTTOMALTRADAR). }
    IF bs {
        LOCAL fac IS hdCam:FACING.
        RETURN LIST(bs, fac:FOREVECTOR, fac:TOPVECTOR, fac:STARVECTOR, hdCam:POSITION, UP:VECTOR, SHIP:VELOCITY:SURFACE,
                    SHIP:Q, SHIP:GROUNDSPEED, TIME:SECONDS, bm, bmr, bnr).
    }
    RETURN LIST(bs, 0, 0, 0, 0, UP:VECTOR, SHIP:VELOCITY:SURFACE, SHIP:Q, SHIP:GROUNDSPEED, TIME:SECONDS, bm, bmr, bnr).
}

// the runway's points hdRunway reads (after hdFinalSwitch); none when hdRunway would hide the overlay at its first test
FUNCTION hdCsPos {
    PARAMETER bs.
    IF NOT bs OR NOT hdRwyOn OR hdRwyIx < 0 { RETURN LIST(). }
    RETURN LIST(hdThr:ALTITUDEPOSITION(hdElev), hdPts[0]:ALTITUDEPOSITION(hdElev), hdPts[1]:ALTITUDEPOSITION(hdElev),
                hdPts[2]:ALTITUDEPOSITION(hdElevFar), hdPts[3]:ALTITUDEPOSITION(hdElevFar),
                hdPts[4]:ALTITUDEPOSITION(hdElev), hdPts[5]:ALTITUDEPOSITION(hdElev)).
}

// the widget writes the addon returned: LIST(img: label, path ..., size: label, px ..., margin: label, H, V ...,
// text: label, text ...), each exactly as hdPlace / hdHide / hdText / hdHideT would make it (and, T680, a blank label
// hidden, any other shown, as they do)
// T680 S3: in C# (ADDONS:KALS:HDAPPLY, the same 4 loops) when the DLL has it; on its error kOS's own loops below, from
// then on (HD_CS_AP_ERR says why). HD_CS_AP (default TRUE) FALSE = kOS's loops.
FUNCTION hdCsApply {
    PARAMETER rr.
    IF hdWinReg {                           // T730 S1a: C# keeps the table (and, but in WIN, makes HDAPPLY's kOS writes)
        LOCAL e IS ADDONS:KALS:HWDRAW(rr).
        IF e = "" { RETURN. }
        hdWinOff("C#: " + e).               // C# synced its table; kOS writes this list below
    }
    IF hdCsAp {
        LOCAL e IS ADDONS:KALS:HDAPPLY(rr, HD_CLEAR).
        IF e = "" { RETURN. }
        SET hdCsAp TO FALSE.
        SET HD_CS_AP_ERR TO e.
    }
    LOCAL o IS rr[0].
    FROM { LOCAL k IS 0. } UNTIL k >= o:LENGTH STEP { SET k TO k + 2. } DO {
        SET o[k]:IMAGE TO o[k + 1].
        IF o[k + 1] = HD_CLEAR { o[k]:HIDE(). } ELSE { o[k]:SHOW(). }
    }
    SET o TO rr[1].
    FROM { LOCAL k IS 0. } UNTIL k >= o:LENGTH STEP { SET k TO k + 2. } DO {
        SET o[k]:STYLE:WIDTH TO o[k + 1].
        SET o[k]:STYLE:HEIGHT TO o[k + 1].
    }
    SET o TO rr[2].
    FROM { LOCAL k IS 0. } UNTIL k >= o:LENGTH STEP { SET k TO k + 3. } DO {
        SET o[k]:STYLE:MARGIN:H TO o[k + 1].
        SET o[k]:STYLE:MARGIN:V TO o[k + 2].
    }
    SET o TO rr[3].
    FROM { LOCAL k IS 0. } UNTIL k >= o:LENGTH STEP { SET k TO k + 2. } DO {
        SET o[k]:TEXT TO o[k + 1].
        IF o[k + 1] = "" { o[k]:HIDE(). } ELSE { o[k]:SHOW(). }
    }
}

FUNCTION hdCsWorst {                        // CHECK: after kOS's own update, the shadow's worst difference
    PARAMETER wd.
    SET HD_CS_NCHK TO HD_CS_NCHK + 1.
    IF wd > HD_CS_WORST {
        SET HD_CS_WORST TO wd.
        SET HD_CS_WKEY TO ADDONS:HOLO:HUDDIFFKEY.
    }
}

// one update: hdState + hdFinalSwitch + hdRender, the math in C#
FUNCTION hdCsUpdate {
    LOCAL inp IS hdCsIn().
    IF HD_CS_CHECK {
        // the shadow: C# on these reads (nothing written), then kOS's own update on the SAME reads, then the comparison
        LOCAL rwy0 IS hdRwyIx.
        LOCAL er IS ADDONS:HOLO:HUDDRY(TRUE).
        IF er = "" { SET er TO ADDONS:HOLO:HUDSTATE(inp). }
        LOCAL pos IS hdCsPos(inp[0]).
        LOCAL rr IS "".
        IF er = "" { SET rr TO ADDONS:HOLO:HUDRENDER(pos). }
        SET hdInPos TO pos.
        SET hdInOn TO TRUE.
        hdStateK(inp).
        hdFinalSwitch().
        hdRender().
        SET hdInOn TO FALSE.
        IF er <> "" {
            hdCsOff("HUDSTATE: " + er).
            RETURN.
        }
        IF rr:ISTYPE("String") {
            hdCsOff("HUDRENDER: " + rr).
            RETURN.
        }
        LOCAL wd IS ADDONS:HOLO:HUDCMP.
        IF hdRwyIx = rwy0 { hdCsWorst(wd). }      // (a runway switch in this update: the shadow drew the old runway)
        RETURN.
    }
    LOCAL er IS ADDONS:HOLO:HUDSTATE(inp).
    IF er <> "" {                           // nothing was written: kOS's own update
        hdCsOff("HUDSTATE: " + er).
        hdState().
        hdFinalSwitch().
        hdRender().
        RETURN.
    }
    hdFinalSwitch().
    LOCAL rr IS ADDONS:HOLO:HUDRENDER(hdCsPos(bSnap)).
    IF rr:ISTYPE("String") {
        hdCsOff("HUDRENDER: " + rr).
        hdRender().
        RETURN.
    }
    hdCsApply(rr).
}

// ---------------------------------------------------------------- the host's calls
// ---------------------------------------------------------------- T680 S2: the painter (see HD_PAINT at the top)
FUNCTION hdPaintPh {                        // a placeholder: hdBox's LAST child, a 1 x 1 box + an empty 1 x 1 label
    LOCAL bx IS hdBox:ADDVLAYOUT().         //   (shown: its draw is where C# paints the HUD, after every slot box)
    SET bx:STYLE:WIDTH TO 1.
    SET bx:STYLE:HEIGHT TO 1.
    SET bx:STYLE:PADDING:BOTTOM TO 1.       // T680 S5: an empty layout box (its label hidden) is padding.vertical tall, not its fixed 1 px (Unity GUILayoutGroup.CalcHeight): this bottom pad keeps its row, so no later slot moves up
    LOCAL m IS bx:ADDLABEL("").
    hdZeroBox(m:STYLE).
    SET m:STYLE:WIDTH TO 1.
    SET m:STYLE:HEIGHT TO 1.
    LOCAL fl IS hdChildN.
    SET hdChildN TO fl + 1.
    RETURN LIST(m, fl, hdBox).
}

// hdInit's end and hdgInit's (after its slots): a NEW placeholder after every slot, the group (re-)registered with every
// slot + the older placeholders (their labels hidden: their boxes keep the flow and, as the group's, are hidden while
// painting, so the new one is the first shown child as the rect rule needs)
FUNCTION hdPaintSetup {
    LOCAL was IS hdPaintReg.
    SET hdPaintReg TO FALSE.
    IF HD_PAINT = 0 AND NOT was { RETURN. }  // OFF: nothing created (HD_PAINT_STATE kept: "OFF" or why it went off)
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("PAINTREG") { SET why TO "the KAL/S addon has no painter (an older DLL)". }
    ELSE {
        LOCAL ph IS hdPaintPh().
        LOCAL its IS hdOrd:COPY.
        FOR p IN hdPhs { its:ADD(p). }
        SET why TO ADDONS:KALS:PAINTREG("HUD", ph, its).
        IF why = "" { SET why TO ADDONS:KALS:PAINTMODE("HUD", HD_PAINT). }
        FOR p IN hdPhs { p[0]:HIDE(). }
        hdPhs:ADD(LIST(ph[0], ph[1])).
    }
    IF why <> "" { hdPaintOff(why). RETURN. }
    SET hdPaintReg TO TRUE.
    SET HD_PAINT_STATE TO hdPaintName(HD_PAINT).
}

FUNCTION hdPaintName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "PAINT" IF m = 2 ELSE "AB".
}

// the mode switched live (SAIL's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a HD_PAINT > 0 hdInit
FUNCTION hdPaintSet {
    PARAMETER m.
    IF NOT hdPaintReg { RETURN "not registered (HD_PAINT was 0 at hdInit, or it failed: " + HD_PAINT_STATE + ")". }
    LOCAL er IS ADDONS:KALS:PAINTMODE("HUD", m).
    IF er <> "" { hdPaintOff(er). RETURN er. }
    SET HD_PAINT TO m.
    SET HD_PAINT_STATE TO hdPaintName(m).
    RETURN "".
}

FUNCTION hdPaintOff {                       // any failure: kOS draws from now on (C# showed the boxes, or never hid them)
    PARAMETER why.
    IF ADDONS:HASSUFFIX("KALS") { IF ADDONS:KALS:HASSUFFIX("PAINTMODE") { ADDONS:KALS:PAINTMODE("HUD", 0). } }
    SET HD_PAINT_STATE TO "OFF (" + why + ")".
    SET HD_PAINT TO 0.
    SET hdPaintReg TO FALSE.
}

FUNCTION hdPaintPoll {                      // hdTick, every 2 s: C# failed (or the group is gone): kOS draws, say why
    IF ADDONS:KALS:PAINTSTATE("HUD") >= 0 { RETURN. }
    hdPaintOff("C#: " + ADDONS:KALS:PAINTERR).
}

// ---------------------------------------------------------------- T730 S1a: the HUD window drawn by C# (see HD_WIN at the top)
// hdInit's end and hdgInit's (after its slots): the window and every slot (hdOrd) to C#, then the mode
FUNCTION hdWinSetup {
    IF HD_WIN = 0 AND NOT hdWinReg { RETURN. }  // OFF: nothing created (HD_WIN_STATE kept: "OFF" or why it went off)
    LOCAL why IS "".
    IF NOT hdCsOn OR HD_CS_CHECK { SET why TO "needs the C# HUD math (HD_CS on, HD_CS_CHECK off)". }
    ELSE IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("HWREG") { SET why TO "the KAL/S addon has no HUD window (an older DLL)". }
    ELSE {
        SET why TO ADDONS:KALS:HWREG(LIST(hdHud, hdWinX, hdWinY, HD_CLEAR, hdShown), hdOrd).
        IF why = "" { SET why TO ADDONS:KALS:HWMODE(HD_WIN). }
    }
    IF why <> "" { hdWinOff(why). RETURN. }
    SET hdWinReg TO TRUE.
    SET HD_WIN_STATE TO hdWinName(HD_WIN).
}

FUNCTION hdWinName {
    PARAMETER m.
    RETURN CHOOSE "OFF" IF m = 0 ELSE CHOOSE "CHECK" IF m = 1 ELSE CHOOSE "WIN" IF m = 2 ELSE "AB".
}

// the mode switched live (SAIL's A/B and ms legs, a kOS line): 0 OFF .. 3 AB; only after a HD_WIN > 0 hdInit
FUNCTION hdWinSet {
    PARAMETER m.
    IF NOT hdWinReg { RETURN "not registered (HD_WIN was 0 at hdInit, or it failed: " + HD_WIN_STATE + ")". }
    LOCAL er IS ADDONS:KALS:HWMODE(m).
    IF er <> "" { hdWinOff(er). RETURN er. }
    SET HD_WIN TO m.
    SET HD_WIN_STATE TO hdWinName(m).
    RETURN "".
}

FUNCTION hdWinOff {                         // any failure: kOS draws from now on (C# synced the table, kOS's window shown)
    PARAMETER why.
    IF hdWinReg {
        IF ADDONS:HASSUFFIX("KALS") {
            IF ADDONS:KALS:HASSUFFIX("HWMODE") {
                ADDONS:KALS:HWMODE(0).
                IF hdShown { hdHud:SHOW(). } ELSE { hdHud:HIDE(). }
                ADDONS:KALS:HWCLOSE().
            }
        }
    }
    SET HD_WIN_STATE TO "OFF (" + why + ")".
    SET HD_WIN TO 0.
    SET hdWinReg TO FALSE.
}

FUNCTION hdWinPoll {                        // hdTick, every 2 s: C# failed (or the window is gone): kOS draws, say why
    IF ADDONS:KALS:HWSTATE >= 0 { RETURN. }
    hdWinOff("C#: " + ADDONS:KALS:HWERR).
}

// T687: hdInit is re-entrant. Everything the loaders and hdBuild fill by ADD is emptied first: a second hdInit after
// hdClose (entry's HUD press, then the landing program's) used to die at hdLay:ADD (duplicate key), lib_hud.ks:426.
FUNCTION hdResetTables {
    hdLay:CLEAR().
    hdSpr:CLEAR().
    hdHzTab:CLEAR().
    hdRpTab:CLEAR().
    hdRnTab:CLEAR().
    hdRwyTab:CLEAR().
    hdSegL:CLEAR().
    hdRwys:CLEAR().
    hdOther:CLEAR().
    hdGlassHP:CLEAR().
    hdGearMain:CLEAR().
    hdGearNose:CLEAR().
    hdBndMain:CLEAR().
    hdBndNose:CLEAR().
    SET hdBndT TO -1000.
    hdOrd:CLEAR().
    hdPhs:CLEAR().
    pHz:CLEAR().                                    // hdBuild's widget pools (the old window's slots are disposed)
    pRung:CLEAR().
    pRnum:CLEAR().
    pRwy:CLEAR().
    pAim:CLEAR().
    pKtick:CLEAR().
    pAtick:CLEAR().
    pKnum:CLEAR().
    pAnum:CLEAR().
    // T824 (the owner 11-12: "The lines on the tapes seem to be missing on the HUD"): the drawing flags are state of the
    // WINDOW, and the window is new: a flag left TRUE by the last HUD (ops1q's ascent ends with the tapes up, hdBoxOn TRUE)
    // kept hdScales from ever placing the new window's index boxes (the bars beside the tapes, "placed once"), the same
    // for the boresight / the speedbrake scale (hdBoreOn / hdStaticOn). Back to the declared values, as at load.
    SET hdHzOn TO TRUE.
    SET hdRungHi TO 99.
    SET hdSeg TO 0.
    SET hdSegHi TO 99.
    SET hdRwyVis TO TRUE.
    SET hdBoxOn TO FALSE.
    SET hdStaticOn TO FALSE.
    SET hdBoreOn TO FALSE.
    SET hdConfOn TO TRUE.
    SET hdLadKey TO "".
    SET hdTapeKK TO -99999.
    SET hdTapeKA TO -99999.
}

FUNCTION hdInit {
    IF hdOK { hdClose(). }                          // T687: a HUD still up is closed first (its window disposed)
    hdResetTables().
    LOCAL fl IS LIST().                             // the fonts loaded in the game: the HUD font among them?
    LIST FONTS IN fl.
    hdFindFont(fl).
    // gen_hud.py kos-hud (on the PC; not in the release) draws a set: these files and the sprites
    IF NOT hdLoadLayout() {
        kmSay("HUD: " + HD_ARCH + "hud_layout.txt missing or old -- reinstall Ships/Script/" + SCR_HUD, "C").
        RETURN FALSE.
    }
    IF NOT hdLoadSprites() {
        kmSay("HUD: " + HD_ARCH + "sprites.txt missing or old -- reinstall Ships/Script/" + SCR_HUD, "C").
        RETURN FALSE.
    }
    IF NOT HD_NO_RWY AND NOT hdLoadRunways() {
        kmSay("HUD: " + HD_ARCH + "hud_runways.txt missing -- reinstall Ships/Script/" + SCR_HUD, "C").
        RETURN FALSE.
    }
    hdHoist().
    hdGlassSetup().
    IF ADDONS:HASSUFFIX("CAMERA") {
        IF ADDONS:CAMERA:HASSUFFIX("FREECAMERA") {
            SET hdCam TO ADDONS:CAMERA:FREECAMERA.
            SET hdCamOK TO TRUE.
        }
    }
    hdFindGear().
    IF NOT HD_NO_RWY { hdSelectRunway(hdPickRunway()). }
    hdBuild().
    hdCsSetup().                                    // the math to the KAL/S coprocessor (or kOS)
    SET hdPaintReg TO FALSE.
    SET hdWinReg TO FALSE.
    IF HD_WIN > 0 { SET HD_PAINT TO 0. }            // T730 S1a: the window and the painter exclude each other
    hdPaintSetup().                                 // T680 S2: the painter (HD_PAINT; OFF by default)
    hdWinSetup().                                   // T730 S1a: the C# window (HD_WIN; OFF by default)
    SET hdWinT0 TO hdReal().
    SET hdOK TO TRUE.
    // AG4 toggles the runway overlay, as on the orbiter
    IF NOT hdAg4 AND NOT HD_NO_RWY {                                  // armed once, for the whole program (ops1q's HUD, then OPS 6's)
        SET hdAg4 TO TRUE.
        ON AG4 {
            IF hdOK { SET hdRwyOn TO NOT hdRwyOn. }
            RETURN TRUE.
        }
    }
    RETURN TRUE.
}

// every tick of the host's main loop: one update when its real-time slot has come (<= HD_MAX_HZ per real second)
FUNCTION hdTick {
    IF NOT hdOK { RETURN. }
    IF MAPVIEW OR NOT hdVis {                   // or the HUD button off (no update either)
        IF hdShown {
            IF hdWinReg { ADDONS:KALS:HWSHOW(FALSE). } ELSE { hdHud:HIDE(). }
            SET hdShown TO FALSE.
        }
        hdAltHidden().                          // OPS 1: ALT MODE's radar test and switch go on
        RETURN.
    }
    IF NOT hdShown {
        IF hdWinReg { ADDONS:KALS:HWSHOW(TRUE). } ELSE { hdHud:SHOW(). }
        SET hdShown TO TRUE.
    }
    LOCAL now IS hdReal().
    IF now < hdNextUpd - 0.002 { RETURN. }
    SET hdNextUpd TO MAX(hdNextUpd, now - 1 / HD_MAX_HZ) + 1 / HD_MAX_HZ.
    LOCAL t0 IS TIME:SECONDS.
    LOCAL o0 IS OPCODESLEFT.
    IF hdCsOn AND (HD_CS OR HD_CS_CHECK) {          // the math in C#
        hdCsUpdate().
    } ELSE {
        hdState().
        hdFinalSwitch().
        hdRender().
    }
    // OPCODESLEFT refills at every tick: an update spanning kt tick boundaries used o0 - o1 + kt x IPU (the host's
    // per-tick trigger included)
    LOCAL kt IS ROUND((TIME:SECONDS - t0) / 0.02).
    SET hdCostSum TO hdCostSum + o0 - OPCODESLEFT + kt * CONFIG:IPU.
    SET hdCostN TO hdCostN + 1.
    IF now - hdWinT0 >= 2 {
        IF hdPaintReg { hdPaintPoll(). }        // T680 S2
        IF hdWinReg { hdWinPoll(). }            // T730 S1a
        SET hdRate TO hdCostN / (now - hdWinT0).
        SET hdCost TO hdCostSum / hdCostN.
        SET hdCostSum TO 0.
        SET hdCostN TO 0.
        SET hdWinT0 TO now.
    }
}

FUNCTION hdClose {
    IF hdOK {
        hdCamRelease().
        IF hdPaintReg { ADDONS:KALS:PAINTMODE("HUD", 0). SET hdPaintReg TO FALSE. }   // T680 S2
        IF hdWinReg { ADDONS:KALS:HWMODE(0). ADDONS:KALS:HWCLOSE(). SET hdWinReg TO FALSE. }   // T730 S1a
        hdHud:DISPOSE().
        SET hdOK TO FALSE.
        SET hdShown TO FALSE.
        IF DEFINED hdgOK { SET hdgOK TO FALSE. }    // T687: lib_hudg's slots lived in that window: hdgInit loads them again
    }
}
