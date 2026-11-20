// lib_ascent_gui.ks -- OPS 1's launch-target box: shown before anything else, it takes the target altitude (the
// apoapsis at MECO, in km), the inclination and the launch azimuth (north / south), in lib_guistyle's look (deorbit_plan's
// dpSelectBox, lib_dap's box).
// asc_gui_target() shows the box before ops1q does anything and waits: ACCEPT sets the I-loads and returns TRUE, CANCEL
// returns FALSE (ops1q then flies nothing). What ACCEPT sets:
//   ASC_VDMAG: PEG's MECO speed for the typed apoapsis at the MECO point (ASC_R + ASC_MECO_H, ASC_GAMD) -- vis-viva and
//     the angular momentum, v = sqrt(2 mu (1/r - 1/ra) / (1 - (r cos(gamd) / ra)^2)); kept bit for bit when the field
//     still shows its default;
//   ASC_TGT_AP (with a new apoapsis): the OMS-2 circle there;
//   ASC_TGT_INC: the inclination (PEG's plane, asc_iyd);
//   ASC_LAUNCH_DIR: 1 north / -1 south (asc_iyd takes that pass over the pad);
//   ASC_HDG_DELTA: stage 1's heading table (ASC_PSI, flown for ASC_PSI_INC north) turned by the change of the launch
//     azimuth, az = atan2(V sin(az_i) - v_eq cos(lat), V cos(az_i)), sin(az_i) = cos(inc) / cos(lat) (the pad's
//     latitude, the body's turn, V the MECO speed's horizontal part); south = that heading mirrored (180 - it). The
//     table's own azimuth is taken at the I-load's V (the speed it was built for), the new one at the typed apoapsis's
//     V: a new apoapsis alone turns the table by the change in the body's turn's share (hundredths of a degree).
// THE OMS RULE (lib_ascent_iload's header): OMS KEPT, the on-orbit allowance (ASC_OMS_ONORB, m/s >= 0); the note:
//   what is kept after OMS-2 (the deorbit from the typed apoapsis (asc_deorbit_dv) + the allowance + ASC_OMS_EMERG),
//   OMS-2's dV, the OMS on board (asc_gui_orb: the parts) and the spare; short: the warning, and ACCEPT takes a second
//   press at least 1 s after the first; ACCEPT sets ASC_OMS_ONORB and ASC_OMS_DV_NOW. The texts are terse, like the
//   ascent messages.
// THE ASSIST ESTIMATE: the OMS check counts the OMS assist's estimated burn (asc_gui_ast, a physics estimate: the rocket
//   equation at the SRB sep, any target; lib_ascent_iload's ASC_AST_PRE_*, then ops1q's asc_ast_est / _size / _crit as at
//   the in-flight check), the note "OMS ASSIST EST. n T"; the ET short even with all the OMS the rule spares: the
//   warning, ACCEPT twice. ACCEPT leaves the estimate in ASC_AST_PRE_LOG (ops1q logs it, "#astpre").
// THE SRB CASE WARNING (Vandenberg only): the polar launch needs the filament-wound case (the FWC subtype of the RSRM's
// B9PartSwitch "Motor case", 3.25 t lighter per SRB; the steel one is the default of every craft). From the box's
// first second on the pad the SRBs are weighed as ops1q's asc_srb_meas weighs them (asc_gui_srbcase); steel: an amber
// line under the MECO TARGET, "NO FWC SRBS (STEEL CASES): MECO TARGET MAY NOT BE REACHED" -- a warning only, ACCEPT
// still takes the box. From KSC (or while unmeasured, a packed vessel) no line but "NOT MEASURED YET" at Vandenberg.
// Not built: the real launch-azimuth limits. Not re-designed for another target: the TAL sites, the abort marks
// (lib_ascent_abr's tables: the nominal's plane). ASC_GUI FALSE before the run skips the box (the I-loads fly).
// TAL SITES (WEATHER), before liftoff only: a button per site of ASC_TAL_SITES, GO or NO WX
// (pressed: toggled); ACCEPT keeps only the GO sites in ASC_TAL_SITES for the flight (ASC_TAL_BAN the banned), so a
// banned site is gone everywhere (not ranked, not listed, never picked); none left = no TAL that flight (ops1q's
// asc_ban_b, asc_etl_new's search done at once). Before liftoff only: the box is the one place to set them.
// A launch site with no TAL site (Vandenberg: lib_ascent_iload's "tal") has no such section; the line reads NO TAL.
// THE LAUNCH SITE: the RTLS returns to the launch site's own runway. Before the box ops1q takes the site of
// lib_ascent_iload's ASC_SITES whose RTLS runway is nearest the pad (asc_site_pick) and asc_site_set makes it
// ASC_RTLS_SITE and flies its own I-loads (Vandenberg: 98 deg south by default, its MECO target, plane and stage 1
// tables), so the box opens on them, DEFAULTS too.
@LAZYGLOBAL OFF.

// the ET margin over the nominal's MECO speed (the warning past ASC_GUI_ETM m/s; ASC_GUI_ETM_FT unused: the
// texts are in m/s): KSC's;
// a site's own I-loads may set them (Vandenberg: 0, its MECO target already takes all of the ET)
GLOBAL ASC_GUI_ETM IS 60.
GLOBAL ASC_GUI_ETM_FT IS 240.
GLOBAL ASC_TAL_BAN IS LIST().          // the TAL sites banned for weather in the box (ACCEPT: out of ASC_TAL_SITES)

// THE LAUNCH SITE: the site of ASC_SITES whose RTLS runway is nearest the pad at (lat, lng), the great circle on
// ASC_R: LIST(the site, that distance m)
FUNCTION asc_site_pick {
  PARAMETER lat, lng.
  LOCAL best IS ASC_SITES[0].
  LOCAL db IS -1.
  FOR st IN ASC_SITES {
    LOCAL rw IS st["rtls"].
    LOCAL cc IS SIN(lat) * SIN(rw["lat"]) + COS(lat) * COS(rw["lat"]) * COS(rw["lng"] - lng).
    LOCAL dd IS ASC_R * ARCCOS(MAX(-1, MIN(1, cc))) * CONSTANT:PI / 180.
    IF db < 0 OR dd < db {
      SET best TO st.
      SET db TO dd.
    }
  }
  RETURN LIST(best, db).
}

// the site st's RTLS runway, then its own I-loads (lib_ascent_iload's "il", the globals' names less ASC_) and the
// ATO's MECO speed for its MECO angle (ato.ato_target's vis-viva apogee at R + ATO_H: the KSC I-load at KSC's angle)
FUNCTION asc_site_set {
  PARAMETER st.
  SET ASC_RTLS_SITE TO st["rtls"].
  IF st:HASKEY("tal") { SET ASC_TAL_SITES TO st["tal"]:COPY. }   // the site's TAL sites (Vandenberg: none)
  IF NOT st:HASKEY("il") { RETURN. }
  LOCAL il IS st["il"].
  SET ASC_TGT_INC TO il["TGT_INC"].
  SET ASC_LAUNCH_DIR TO il["LAUNCH_DIR"].
  SET ASC_GAMD TO il["GAMD"].
  SET ASC_VDMAG TO il["VDMAG"].
  SET ASC_PLANE_DLNG TO il["PLANE_DLNG"].
  SET ASC_PSI_INC TO il["PSI_INC"].
  SET ASC_T_CNS_PITCH_RATE TO il["T_CNS_PITCH_RATE"].
  SET ASC_THETC_DOT_NOM_RAD TO il["THETC_DOT_NOM_RAD"].
  SET ASC_PPOLY TO il["PPOLY"]:COPY.
  SET ASC_THET TO il["THET"]:COPY.
  SET ASC_PSI TO il["PSI"]:COPY.
  SET ASC_GUI_ETM TO il["GUI_ETM"].
  SET ASC_GUI_ETM_FT TO il["GUI_ETM_FT"].
  SET ASC_RTLS_THETA_0 TO il["RTLS_THETA_0"].
  SET ASC_RTLS_THETA_1 TO il["RTLS_THETA_1"].
  SET ASC_RTLS_THETA_4 TO il["RTLS_THETA_4"].
  SET ASC_ATO_VDMAG TO asc_gui_vd(ASC_R + ASC_ATO_H).
}

// the launch azimuth (deg from north, the rotating frame) for inc north of the pad at latitude lat
FUNCTION asc_gui_az {
  PARAMETER inc, lat.
  LOCAL sn IS COS(inc) / COS(lat).
  IF ABS(sn) > 1 { RETURN -999. }
  LOCAL ai IS ARCSIN(sn).
  LOCAL vh IS ASC_VDMAG * COS(ASC_GAMD).
  LOCAL veq IS 2 * CONSTANT:PI * BODY:RADIUS / BODY:ROTATIONPERIOD.
  RETURN ARCTAN2(vh * SIN(ai) - veq * COS(lat), vh * COS(ai)).
}

// the apoapsis radius (m) of the MECO point flown at speed spd (m/s)
FUNCTION asc_gui_ra {
  PARAMETER spd.
  LOCAL rr IS ASC_R + ASC_MECO_H.
  LOCAL sma IS 1 / (2 / rr - spd * spd / BODY:MU).
  LOCAL hh IS rr * spd * COS(ASC_GAMD).
  RETURN sma * (1 + SQRT(MAX(0, 1 - hh * hh / (BODY:MU * sma)))).
}

// OMS-2's dV (m/s) from the MECO point flown at spd to the circle at its apoapsis
FUNCTION asc_gui_oms2 {
  PARAMETER spd.
  LOCAL ra IS asc_gui_ra(spd).
  IF ra <= 0 { RETURN 0. }
  RETURN MAX(0, SQRT(BODY:MU / ra) - (ASC_R + ASC_MECO_H) * spd * COS(ASC_GAMD) / ra).
}

// a decoupler part
FUNCTION asc_gui_isdec {
  PARAMETER pt.
  RETURN pt:MODULES:CONTAINS("ModuleAnchoredDecoupler") OR pt:MODULES:CONTAINS("ModuleDecouple").
}

// the FWC's saving per SRB is 3.25 t (the cfg's addedMass): the SRBs' mean dry mass lighter than ASC_S1P_SDRY (the
// I-load's steel SRB, 21.83 t less its SolidFuel) by this much or more is the FWC (0.5 t under the full saving: one
// case of each, 1.6 t lighter, is not)
GLOBAL ASC_GUI_FWC_DM IS 2.75.

// THE SRB CASE from the vessel on the pad: ops1q's asc_srb_meas weighing (asc_srb_dry_of(asc_srb_rows(asc_srbs())), one
// SRB's mass less its own SolidFuel, the mean of the two): 1 the FWC (lighter than ASC_S1P_SDRY by ASC_GUI_FWC_DM or
// more), 0 not (steel, one of each, or any other case), -1 not measured (packed, or not two SRBs on decouplers)
FUNCTION asc_gui_srbcase {
  PARAMETER unp.
  IF NOT unp { RETURN -1. }
  LOCAL sd IS asc_srb_dry_of(asc_srb_rows(asc_srbs())).
  IF sd <= 0 { RETURN -1. }
  RETURN CHOOSE 1 IF sd <= ASC_S1P_SDRY - ASC_GUI_FWC_DM ELSE 0.
}

// a launch clamp (stock's ModuleLaunchClamp, ModularLaunchPads' LaunchClamp: the pad hangs on it)
FUNCTION asc_gui_isclamp {
  PARAMETER pt.
  FOR mn IN pt:MODULES { IF mn:CONTAINS("LaunchClamp") { RETURN TRUE. } }
  RETURN FALSE.
}

// a part on the far side of a decoupler from the root (a payload's own tank or engine, a liquid booster's): not
// the orbiter's own. The ET and the SRBs hang there too, but they are not read as OMS tanks or main engines either way.
FUNCTION asc_gui_beyond {
  PARAMETER pt.
  LOCAL anc IS pt.
  UNTIL NOT anc:HASPARENT {
    SET anc TO anc:PARENT.
    IF asc_gui_isdec(anc) { RETURN TRUE. }
  }
  RETURN FALSE.
}

// LIST(the orbiter t with its payload and OMS, its OMS propellant t) from the parts: the vessel (mtot) less the
// stack under the top-level decoupler (no decoupler above it) that holds the ET (a propellant only the SSMEs burn):
// the ET's, with the ET, the SRBs and the pad; none (after the sep): the vessel;
// the OMS = the AJ10s' propellants in the parts outside it that hold one the SSMEs do not burn, less those with a
// ModuleResourceConverter (the fuel cell's) and those beyond a decoupler (a payload's own tanks): ops1q's
// asc_oms_parts / asc_oms_mass rule. The SSMEs = the engines that are not AJ10s, not throttle-locked (the SRBs) and
// not beyond a decoupler (a payload's own engine, an LV-909 in the bay: its LiquidFuel is not what the SSMEs burn).
// LIST(-1, -1) while packed (its parts read 0) or without an AJ10.
FUNCTION asc_gui_orb {
  PARAMETER parts, engs, mtot, unp.
  IF NOT unp { RETURN LIST(-1, -1). }
  LOCAL sn IS LIST().
  LOCAL ow IS LIST().
  FOR en IN engs {
    IF en:NAME:CONTAINS("AJ10") { FOR cr IN en:CONSUMEDRESOURCES:VALUES { IF NOT ow:CONTAINS(cr:NAME) { ow:ADD(cr:NAME). } } }
    ELSE IF NOT en:THROTTLELOCK AND NOT asc_gui_beyond(en) { FOR cr IN en:CONSUMEDRESOURCES:VALUES { IF NOT sn:CONTAINS(cr:NAME) { sn:ADD(cr:NAME). } } }
  }
  IF ow:LENGTH = 0 { RETURN LIST(-1, -1). }
  LOCAL bm IS -1.
  LOCAL bp IS 0.                          // the top decoupler of that stack
  LOCAL bu IS LEXICON().
  FOR pt IN parts {
    IF asc_gui_isdec(pt) {
      LOCAL top IS TRUE.
      LOCAL qp IS pt.
      UNTIL NOT qp:HASPARENT {
        SET qp TO qp:PARENT.
        IF asc_gui_isdec(qp) { SET top TO FALSE. BREAK. }
      }
      IF top {
        LOCAL m IS 0.
        LOCAL hx IS FALSE.
        LOCAL us IS LEXICON().
        LOCAL stk IS LIST(pt).
        UNTIL stk:LENGTH = 0 {
          LOCAL p2 IS stk[stk:LENGTH - 1].
          stk:REMOVE(stk:LENGTH - 1).
          SET m TO m + p2:MASS.
          SET us[p2:UID] TO TRUE.
          FOR rs IN p2:RESOURCES { IF rs:CAPACITY > 0 AND sn:CONTAINS(rs:NAME) AND NOT ow:CONTAINS(rs:NAME) { SET hx TO TRUE. } }
          FOR ch IN p2:CHILDREN { stk:ADD(ch). }
        }
        IF hx AND m > bm { SET bm TO m. SET bu TO us. SET bp TO pt. }
      }
    }
  }
  LOCAL mo IS mtot - MAX(0, bm).
  LOCAL om IS 0.
  FOR pt IN parts {
    IF NOT bu:HASKEY(pt:UID) AND NOT pt:MODULES:CONTAINS("ModuleResourceConverter") {
      LOCAL ko IS FALSE.
      LOCAL m IS 0.
      FOR rs IN pt:RESOURCES {
        IF ow:CONTAINS(rs:NAME) {
          SET m TO m + rs:AMOUNT * rs:DENSITY.
          IF rs:CAPACITY > 0 AND NOT sn:CONTAINS(rs:NAME) { SET ko TO TRUE. }
        }
      }
      IF ko AND NOT asc_gui_beyond(pt) { SET om TO om + m. }
    }
  }
  IF mo <= om OR om <= 0 { RETURN LIST(-1, -1). }
  IF bm < 0 { RETURN LIST(mo, om). }
  // what stays after the SRB sep (the top decoupler and what hangs on it, not past another decoupler or a launch
  // clamp: the ET), its SSME propellants as asc_burnable reads them, the SSMEs' vacuum exhaust speed and mass flow
  LOCAL mse IS mo.
  LOCAL amt IS LEXICON().
  LOCAL stk IS LIST(bp).
  UNTIL stk:LENGTH = 0 {
    LOCAL p2 IS stk[stk:LENGTH - 1].
    stk:REMOVE(stk:LENGTH - 1).
    SET mse TO mse + p2:MASS.
    FOR rs IN p2:RESOURCES {
      IF sn:CONTAINS(rs:NAME) { SET amt[rs:NAME] TO rs:AMOUNT + (CHOOSE amt[rs:NAME] IF amt:HASKEY(rs:NAME) ELSE 0). }
    }
    FOR ch IN p2:CHILDREN { IF NOT asc_gui_isdec(ch) AND NOT asc_gui_isclamp(ch) { stk:ADD(ch). } }
  }
  LOCAL e0 IS 0.
  LOCAL mds IS 0.
  FOR en IN engs {
    IF NOT en:NAME:CONTAINS("AJ10") AND NOT en:THROTTLELOCK AND NOT asc_gui_beyond(en) {
      SET mds TO mds + en:MAXMASSFLOW.
      IF e0 = 0 { SET e0 TO en. }
    }
  }
  IF e0 = 0 { RETURN LIST(mo, om). }
  LOCAL n IS -1.
  LOCAL mm IS 0.
  FOR cr IN e0:CONSUMEDRESOURCES:VALUES {
    IF cr:RATIO > 0 {
      LOCAL k IS (CHOOSE amt[cr:NAME] IF amt:HASKEY(cr:NAME) ELSE 0) / cr:RATIO.
      IF n < 0 OR k < n { SET n TO k. }
      SET mm TO mm + cr:RATIO * cr:DENSITY.
    }
  }
  RETURN LIST(mo, om, mse, MAX(n, 0) * mm, e0:VISP * CONSTANT:G0, mds).
}

// the OMS assist the in-flight check (ops1q asc_ast_chk) would light, from the box: ob asc_gui_orb's list, vd the
// MECO speed, inc deg, keep m/s the OMS rule keeps after the sep (OMS-2 + the deorbit + the allowance + the margin).
// LIST(t of OMS (0 none, -1 not known), the ET's margin without, the line, the cap, the margin with the cap, M, prop, VGO)
FUNCTION asc_gui_ast {
  PARAMETER ob, vd, inc, keep.
  IF NOT ASC_AST_ON OR ob:LENGTH < 6 { RETURN LIST(-1, 0, 0, 0, 0, 0, 0, 0). }
  IF ob[3] <= 0 OR ob[5] <= 0 { RETURN LIST(-1, 0, 0, 0, 0, 0, 0, 0). }
  IF ob[2] - ob[0] > 1.2 * ob[3] + 20 { RETURN LIST(-1, 0, 0, 0, 0, 0, 0, 0). }   // more than an ET hangs there: not known
  LOCAL ms IS ob[2] - ASC_AST_PRE_B.
  LOCAL prop IS ob[3] - ASC_AST_PRE_B - ASC_ET_RESERVE_FRAC * (ob[3] - ASC_AST_PRE_B0).
  IF prop <= 0 OR prop >= ms { RETURN LIST(-1, 0, 0, 0, 0, 0, 0, 0). }
  LOCAL vgo IS ASC_AST_PRE_V0 + ASC_AST_PRE_KM * (ms - ASC_AST_PRE_M0) + ASC_AST_PRE_KV * (vd - ASC_AST_PRE_VD0)
    + ASC_AST_PRE_KI * (COS(inc) - COS(51.6)) + ASC_AST_PRE_KG * (ASC_GAMD - ASC_AST_PRE_GAM0).
  LOCAL cs IS ob[4].
  LOCAL co IS ASC_OMS_ISP * CONSTANT:G0.
  LOCAL rq IS ob[5] / (ASC_OMS_F / co).
  LOCAL e0 IS asc_ast_est(ms, prop, vgo, 0, rq, cs, co).
  LOCAL lim IS asc_ast_crit(ASC_AST_PRE_DT) + ASC_AST_PAD.
  LOCAL f IS CONSTANT:E ^ (-keep / co).
  LOCAL cap IS MAX(0, (ob[1] - ob[0] * (1 - f)) / f).
  LOCAL x IS 0.
  IF e0 < lim {
    SET x TO asc_ast_size(ms, prop, vgo, lim, rq, cs, co, cap).
    IF x < cap - 1e-6 { SET x TO MIN(cap, x * (ASC_AST_G0 + ASC_AST_G1 * x)). }
    IF x < ASC_AST_MIN { SET x TO 0. }
  }
  RETURN LIST(x, e0, lim, cap, asc_ast_est(ms, prop, vgo, cap, rq, cs, co), ms, prop, vgo).
}

// the MECO speed (m/s) for the apoapsis radius ra (m); -1 when none
FUNCTION asc_gui_vd {
  PARAMETER ra.
  LOCAL rr IS ASC_R + ASC_MECO_H.
  LOCAL qq IS 1 - (rr * COS(ASC_GAMD) / ra) ^ 2.
  IF ra <= rr OR qq <= 0 { RETURN -1. }
  RETURN SQRT(2 * BODY:MU * (1 / rr - 1 / ra) / qq).
}

// a number to one decimal as text
FUNCTION asc_gui_f1 {
  PARAMETER x.
  LOCAL s IS "" + ROUND(x, 1).
  IF NOT s:CONTAINS(".") { SET s TO s + ".0". }
  RETURN s.
}

FUNCTION asc_gui_target {
  LOCAL lat IS SHIP:LATITUDE.
  LOCAL vd0 IS ASC_VDMAG.
  LOCAL inc0 IS ASC_TGT_INC.
  LOCAL dir0 IS ASC_LAUNCH_DIR.
  LOCAL apo0 IS asc_gui_ra(vd0) - ASC_R.
  LOCAL tA0 IS asc_gui_f1(apo0 / 1000).
  LOCAL tI0 IS "" + inc0.
  LOCAL tOrb0 IS "" + ROUND(ASC_OMS_ONORB).
  LOCAL g IS uiBox("OPS 1 LAUNCH TARGET", 470, 60, 120).
  LOCAL secA IS uiSection(g, "MECO TARGET").
  LOCAL rowA IS secA:ADDHLAYOUT().
  LOCAL lA IS rowA:ADDLABEL("APOAPSIS").
  SET lA:STYLE:FONTSIZE TO UI_BODY_PT.
  SET lA:STYLE:WIDTH TO 110.
  LOCAL fApo IS rowA:ADDTEXTFIELD(tA0).
  SET fApo:STYLE:WIDTH TO 90.
  LOCAL lK IS rowA:ADDLABEL("KM").
  SET lK:STYLE:FONTSIZE TO UI_BODY_PT.
  LOCAL nA IS uiNote(secA, "").
  LOCAL wA IS uiNote(secA, "").
  SET wA:STYLE:TEXTCOLOR TO RGB(1, 0.6, 0.4).
  LOCAL vbg IS ASC_RTLS_SITE["name"] = "VBG".   // Vandenberg: the SRB case's line
  LOCAL wF IS 0.
  IF vbg {
    SET wF TO uiNote(secA, "").
    SET wF:STYLE:TEXTCOLOR TO RGB(1, 0.6, 0.4).
  }
  LOCAL secP IS uiSection(g, "ORBIT PLANE").
  LOCAL rowI IS secP:ADDHLAYOUT().
  LOCAL lI IS rowI:ADDLABEL("INCLINATION").
  SET lI:STYLE:FONTSIZE TO UI_BODY_PT.
  SET lI:STYLE:WIDTH TO 110.
  LOCAL fInc IS rowI:ADDTEXTFIELD(tI0).
  SET fInc:STYLE:WIDTH TO 90.
  LOCAL lD IS rowI:ADDLABEL("DEG").
  SET lD:STYLE:FONTSIZE TO UI_BODY_PT.
  LOCAL rowD IS secP:ADDHLAYOUT().
  LOCAL lL IS rowD:ADDLABEL("LAUNCH").
  SET lL:STYLE:FONTSIZE TO UI_BODY_PT.
  SET lL:STYLE:WIDTH TO 110.
  LOCAL bN IS uiChoice(rowD, "NORTH").
  LOCAL bS IS uiChoice(rowD, "SOUTH").
  LOCAL nP IS uiNote(secP, "").
  LOCAL wP IS uiNote(secP, "").
  SET wP:STYLE:TEXTCOLOR TO RGB(1, 0.6, 0.4).
  // the OMS kept after OMS-2 (the OMS rule): the on-orbit allowance
  LOCAL secO IS uiSection(g, "OMS KEPT AFTER OMS-2").
  LOCAL rowO IS secO:ADDHLAYOUT().
  LOCAL lO IS rowO:ADDLABEL("ON-ORBIT DV").
  SET lO:STYLE:FONTSIZE TO UI_BODY_PT.
  SET lO:STYLE:WIDTH TO 110.
  LOCAL fOrb IS rowO:ADDTEXTFIELD(tOrb0).
  SET fOrb:STYLE:WIDTH TO 90.
  LOCAL lM IS rowO:ADDLABEL("M/S").
  SET lM:STYLE:FONTSIZE TO UI_BODY_PT.
  LOCAL nO IS uiNote(secO, "").
  LOCAL wO IS uiNote(secO, "").
  SET wO:STYLE:TEXTCOLOR TO RGB(1, 0.6, 0.4).
  // the TAL sites' weather: a button per site, GO (amber, bracketed) or NO WX (orange); all NO WX: the warning
  LOCAL tls0 IS ASC_TAL_SITES:COPY.
  LOCAL ban IS LEXICON().
  FOR st IN tls0 { SET ban[st] TO ASC_TAL_BAN:CONTAINS(st). }
  LOCAL bT IS LEXICON().
  LOCAL wT IS 0.                       // no TAL site (Vandenberg): no weather section
  IF tls0:LENGTH > 0 {
    LOCAL secT IS uiSection(g, "TAL SITES (WEATHER)").
    LOCAL rowT IS secT:ADDHLAYOUT().
    FOR st IN tls0 {
      SET bT[st] TO uiChoice(rowT, st).
    }
    SET wT TO uiNote(secT, "").
    SET wT:STYLE:TEXTCOLOR TO RGB(1, 0.6, 0.4).
  }
  g:ADDSPACING(UI_GAP).
  LOCAL sel IS uiText(g, "").
  LOCAL rowB IS g:ADDHLAYOUT().
  LOCAL bGo IS uiPrimary(rowB, "ACCEPT").
  IF DEFINED SAIL_ON { sailReg("ascaccept", bGo). }
  LOCAL bDef IS uiSecondary(rowB, "DEFAULTS").
  LOCAL bCan IS uiSecondary(rowB, "CANCEL").
  g:SHOW().
  LOCAL dir IS ASC_LAUNCH_DIR.
  LOCAL tA IS "".
  LOCAL tI IS "".
  LOCAL tOrb IS "".
  LOCAL onorb IS ASC_OMS_ONORB.
  LOCAL ob IS LIST(-1, -1).            // the orbiter + its OMS (asc_gui_orb), once measured
  LOCAL tMs IS 0.
  LOCAL sc IS -1.                      // the SRB case (asc_gui_srbcase), Vandenberg only
  LOCAL tSc IS 0.
  LOCAL odv IS -1.
  LOCAL ax IS LIST(-1, 0, 0, 0, 0, 0, 0, 0).   // the assist estimate (asc_gui_ast)
  LOCAL osh IS FALSE.                  // the OMS short of OMS-2 + what is kept
  LOCAL tArm IS -1.                    // the first ACCEPT's time while short
  LOCAL dirty IS TRUE.
  LOCAL ok IS FALSE.
  LOCAL done IS FALSE.
  LOCAL vd IS vd0.
  LOCAL inc IS inc0.
  LOCAL good IS FALSE.
  LOCAL az0 IS asc_gui_az(ASC_PSI_INC, lat).
  UNTIL done {
    IF bN:TAKEPRESS { SET dir TO 1. SET dirty TO TRUE. }
    IF bS:TAKEPRESS { SET dir TO -1. SET dirty TO TRUE. }
    FOR st IN tls0 { IF bT[st]:TAKEPRESS { SET ban[st] TO NOT ban[st]. SET dirty TO TRUE. } }   // a press toggles GO / NO WX
    IF bDef:TAKEPRESS {
      SET fApo:TEXT TO tA0.
      SET fInc:TEXT TO tI0.
      SET fOrb:TEXT TO tOrb0.              // the on-orbit allowance's default
      SET dir TO dir0.
      FOR st IN tls0 { SET ban[st] TO FALSE. }   // every site GO
      SET dirty TO TRUE.
    }
    IF fApo:TEXT <> tA OR fInc:TEXT <> tI OR fOrb:TEXT <> tOrb { SET dirty TO TRUE. }
    IF ob[0] < 0 AND TIME:SECONDS >= tMs {   // measured once the vessel is unpacked, tried each second until then
      SET tMs TO TIME:SECONDS + 1.
      SET ob TO asc_gui_orb(SHIP:PARTS, SHIP:ENGINES, SHIP:MASS, SHIP:UNPACKED).
      IF ob[0] > 0 { SET dirty TO TRUE. }
    }
    IF vbg AND sc < 0 AND TIME:SECONDS >= tSc {   // the SRBs weighed the same way, each second until measured
      SET tSc TO TIME:SECONDS + 1.
      SET sc TO asc_gui_srbcase(SHIP:UNPACKED).
      IF sc >= 0 { SET dirty TO TRUE. }
    }
    IF dirty {
      SET dirty TO FALSE.
      SET tArm TO -1.
      SET tA TO fApo:TEXT.
      SET tI TO fInc:TEXT.
      SET tOrb TO fOrb:TEXT.
      uiChoiceShow(bN, "NORTH", dir > 0).
      uiChoiceShow(bS, "SOUTH", dir < 0).
      LOCAL tgo IS LIST().                // the sites GO
      FOR st IN tls0 {
        IF ban[st] { uiChoiceShow(bT[st], uiColor(st + " NO WX", UI_WARN), FALSE). }   // off the amber too
        ELSE { uiChoiceShow(bT[st], st + " GO", TRUE). tgo:ADD(st). }
      }
      IF tls0:LENGTH > 0 { SET wT:TEXT TO CHOOSE "ALL NO WX: NO TAL" IF tgo:LENGTH = 0 ELSE "". }
      LOCAL tsum IS "  TAL " + tgo:JOIN(" ").
      IF tgo:LENGTH = 0 { SET tsum TO "  " + (CHOOSE uiColor("NO TAL", UI_WARN) IF tls0:LENGTH > 0 ELSE "NO TAL"). }
      SET good TO TRUE.
      // the apoapsis (km): the default text = the I-load's speed bit for bit
      LOCAL ht IS tA:TONUMBER(-1) * 1000.
      IF tA = tA0 { SET vd TO vd0. SET ht TO apo0. }
      ELSE IF ht > 0 { SET vd TO asc_gui_vd(ASC_R + ht). } ELSE { SET vd TO -1. }
      IF vd <= 0 OR ht <= ASC_MECO_H + 1000 {
        SET nA:TEXT TO "".
        SET wA:TEXT TO "APOAPSIS MUST BE OVER " + asc_gui_f1(ASC_MECO_H / 1000) + " KM".
        SET good TO FALSE.
      } ELSE {
        SET nA:TEXT TO "MECO " + asc_gui_f1(ASC_MECO_H / 1000) + " KM, " + asc_gui_f1(ASC_GAMD) + " DEG, VI " + ROUND(vd)
          + " M/S".
        SET wA:TEXT TO "".
        IF vd - vd0 > ASC_GUI_ETM {
          SET wA:TEXT TO "VI +" + ROUND(vd - vd0) + " M/S OVER NOMINAL (ET MARGIN ~" + ASC_GUI_ETM + "): MAY RUN DRY".
        }
      }
      IF vbg {
        SET wF:TEXT TO CHOOSE "SRB CASE: NOT MEASURED YET" IF sc < 0 ELSE (CHOOSE "" IF sc > 0
          ELSE "NO FWC SRBS (STEEL CASES): MECO TARGET MAY NOT BE REACHED").
      }
      // the plane: the default text = the I-load bit for bit
      SET inc TO tI:TONUMBER(-999).
      IF tI = tI0 { SET inc TO inc0. }
      LOCAL az IS -999.
      IF inc > -999 { SET az TO asc_gui_az(inc, lat). }
      IF az = -999 OR ABS(inc) >= 180 - ABS(lat) {
        SET nP:TEXT TO "".
        SET wP:TEXT TO "INCLINATION: " + asc_gui_f1(ABS(lat)) + " TO " + asc_gui_f1(180 - ABS(lat)) + " DEG (PAD "
          + asc_gui_f1(ABS(lat)) + (CHOOSE " N" IF lat >= 0 ELSE " S") + ")".
        SET good TO FALSE.
      } ELSE {
        LOCAL h1 IS ASC_PSI[0] + az - az0.
        LOCAL hd IS CHOOSE az IF dir > 0 ELSE 180 - az.
        SET nP:TEXT TO "AZ " + asc_gui_f1(MOD(hd + 360, 360)) + " DEG, S1 HDG "
          + asc_gui_f1(MOD((CHOOSE h1 IF dir > 0 ELSE 180 - h1) + 360, 360)) + " DEG, PAD " + asc_gui_f1(ABS(lat))
          + (CHOOSE " N." IF lat >= 0 ELSE " S.").
        SET wP:TEXT TO "".
      }
      // the on-orbit allowance and the OMS kept after OMS-2 at the typed apoapsis
      SET onorb TO tOrb:TONUMBER(-1).
      SET osh TO FALSE.
      SET odv TO -1.
      IF onorb < 0 {
        SET nO:TEXT TO "".
        SET wO:TEXT TO "ON-ORBIT DV MUST BE OVER 0".
        SET good TO FALSE.
      } ELSE IF vd > 0 {
        LOCAL dvo IS asc_deorbit_dv(asc_gui_ra(vd) - ASC_R).
        LOCAL d2 IS asc_gui_oms2(vd).
        LOCAL kp IS dvo + onorb + ASC_OMS_EMERG.
        LOCAL tx IS "".                     // the KEEP / OMS / SPARE line: none
        SET wO:TEXT TO "".
        IF ob[0] > 0 {
          SET odv TO ASC_OMS_ISP * CONSTANT:G0 * LN(ob[0] / (ob[0] - ob[1])).
          SET ax TO asc_gui_ast(ob, vd, inc, d2 + kp).   // the assist's OMS off first
          LOCAL oda IS odv.
          IF ax[0] > 0 {
            SET oda TO ASC_OMS_ISP * CONSTANT:G0 * LN(MAX(ob[0] - ax[0], ob[1] + 1e-6) / (ob[0] - ob[1])).
            SET tx TO "OMS ASSIST EST. " + asc_gui_f1(ax[0]) + " T".
          }
          LOCAL sp IS oda - d2 - kp.
          IF ax[0] >= 0 AND ax[1] < ax[2] AND ax[0] >= ax[3] - 1e-6 AND ax[4] < ax[2] {
            SET osh TO TRUE.
            SET wO:TEXT TO "ET SHORT " + ROUND(ax[2] - ax[4]) + " M/S WITH OMS ASSIST: ACCEPT TWICE TO OVERRIDE".
          } ELSE IF sp < 0 {
            SET osh TO TRUE.
            SET wO:TEXT TO "OMS SHORT " + ROUND(-sp) + " M/S: ACCEPT TWICE TO OVERRIDE".
          }
        } ELSE { SET tx TO "OMS: NOT MEASURED YET". }
        SET nO:TEXT TO tx.
      }
      IF good {
        SET sel:TEXT TO "<b>" + uiColor(asc_gui_f1((asc_gui_ra(vd) - ASC_R) / 1000) + " KM, " + inc + " DEG, "
          + (CHOOSE "NORTH" IF dir > 0 ELSE "SOUTH"), UI_ACCENT) + "</b>" + tsum.
      } ELSE {
        SET sel:TEXT TO uiColor("FIX THE ORANGE LINES.", UI_WARN).
      }
    }
    IF bGo:TAKEPRESS AND good {
      IF NOT osh {
        SET ok TO TRUE.
        SET done TO TRUE.
      } ELSE IF tArm < 0 {                // short: the first press arms, a second one at least 1 s later accepts
        SET tArm TO TIME:SECONDS.
        SET sel:TEXT TO uiColor("OMS SHORT: ACCEPT AGAIN (1 S MIN).", UI_WARN).
      } ELSE IF TIME:SECONDS - tArm >= 1 {
        SET ok TO TRUE.
        SET done TO TRUE.
      }
    }
    IF bCan:TAKEPRESS { SET done TO TRUE. }
    WAIT 0.1.
  }
  g:DISPOSE().
  IF ok {
    IF vd <> vd0 {
      SET ASC_VDMAG TO vd.
      SET ASC_TGT_AP TO asc_gui_ra(vd) - ASC_R.          // the OMS-2 circle at the new apoapsis
    }
    SET ASC_TGT_INC TO inc.
    SET ASC_LAUNCH_DIR TO dir.
    SET ASC_HDG_DELTA TO asc_gui_az(inc, lat) - az0.
    LOCAL op IS LIST().                   // the GO sites fly; the banned are gone for the flight
    SET ASC_TAL_BAN TO LIST().
    FOR st IN tls0 { IF ban[st] { ASC_TAL_BAN:ADD(st). } ELSE { op:ADD(st). } }
    SET ASC_TAL_SITES TO op.
    SET ASC_OMS_ONORB TO onorb.           // the on-orbit allowance kept
    IF ax[0] >= 0 {                       // the estimate, for the log (ops1q: "#astpre")
      SET ASC_AST_PRE_LOG TO "#astpre," + ax[0] + "," + ax[1] + "," + ax[2] + "," + ax[3] + "," + ax[4] + "," + ax[5] + ","
        + ax[6] + "," + ax[7] + "," + vd + "," + inc + "," + ob[0] + "," + ob[1] + "," + ob[2] + "," + ob[3] + "," + ob[4]
        + "," + ob[5].
    }
    IF odv > 0 { SET ASC_OMS_DV_NOW TO odv. }
  }
  RETURN ok.
}
