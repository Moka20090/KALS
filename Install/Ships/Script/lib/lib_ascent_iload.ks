// lib_ascent_iload.ks -- GENERATED offline by the I-load export. DO NOT EDIT the generated values by hand: re-run the
// export after any change to its sources (the stage-1 I-loads, the PEG fly-off, the TAL, RTLS and ATO sims).
// The I-loads of ops1q.ks: SI units (m, s), angles in deg unless named _RAD; throttles in PL % (KSP throttle =
// PL % / 100 x ASC_PL_TO_KSP). The numbers fly the DRAG x1 FIRST GUESS until a flight refits it.
@LAZYGLOBAL OFF.
// ---- the planet the I-loads were made for (ops1q compares BODY:MU and BODY:RADIUS)
GLOBAL ASC_MU IS 24912527214756.0.   // m3/s2
GLOBAL ASC_R IS 1592752.5.   // m
GLOBAL ASC_PL_TO_KSP IS 0.9560439560439561.   // KSP throttle per PL % / 100 (KSP 100 % = 104.6 PL: Block I);
//   ops1q's asc_ssme_detect sets it from the SSMEs' variant: the late craft files carry the newer SSME (the late
//   Shuttle's, not the SLS one), flown at 104 % of its rated thrust, up to 109 % in an abort
GLOBAL ASC_SSME_RPL IS 522.   // kN vac: the SSMEs' rated thrust (100 % PL) = RMM Cotopaxi's FOCF config at full throttle
GLOBAL ASC_SSME_VARIANTS IS LIST("FOCF", 522, "BLOCK I", 546, "BLOCK II", 570, "BLOCK III", 626).   // kN vac, full
GLOBAL ASC_J2 IS 0.0010826358191967033.   // the J2 Principia flies, for the sensed velocity change (the velocity change less gravity)
GLOBAL ASC_R_J2 IS 1594534.075.   // m, its reference radius
// ---- the target (160 km circular at 36.25 deg; MECO by direct insertion, then OMS-2 at the apoapsis)
GLOBAL ASC_TGT_INC IS 36.25.   // deg
GLOBAL ASC_LAUNCH_DIR IS 1.   // 1 north, -1 south: the pass over the pad PEG's plane takes (the target box)
GLOBAL ASC_PSI_INC IS 36.25.   // deg: the inclination (north) stage 1's heading table ASC_PSI was flown for
GLOBAL ASC_HDG_DELTA IS 0.   // deg: ASC_PSI turned by this (the target box, lib_ascent_gui: the azimuth's change)
GLOBAL ASC_TGT_AP IS 160000.0.   // m above R: the OMS-2 circle
GLOBAL ASC_MECO_H IS 90000.0.   // m above R: RDMAG = R + this
GLOBAL ASC_GAMD IS 2.1037943166369715.   // deg, the flight path angle at MECO
GLOBAL ASC_VDMAG IS 3856.2054731546614.   // m/s, the inertial speed at MECO
GLOBAL ASC_PLANE_DLNG IS 1.7921209849378164.   // deg: the plane turned east about the spin axis from the one through the pad at liftoff
// ---- stage 1 (FSSR 4.2.3): the tables on VREL_AERO_REF, m/s; PPOLY1 = the pad, PPOLY2 = the tower clear on
// the raw relative speed; THET = pitch above the local horizontal, PSI = the heading, PHI = the roll (PHI1 unused:
// the vertical rise holds the pad attitude). Interpolated in tan(angle / 4) as the FSSR does; I <= 29.
GLOBAL ASC_PPOLY IS LIST(0.0, 35.0, 52.084603492666226, 70.98613489653468, 92.641998936385, 93.82295526014224, 118.17812509934456,
    141.71871530716902, 175.33597432565566, 189.02903729476958, 201.53124620755202, 220.92592142723893,
    254.41082844563874, 262.4157080529626, 270.64601422187104, 279.8351702981754, 289.1397751475898,
    306.1716289246096, 324.28860790257863, 343.26690113236094, 365.28247752961005, 401.8666026563696,
    443.0521930041668, 481.2649204599216, 521.6028862617086, 566.1709176053679, 611.3061317239482,
    649.9731153959946, 695.2347602778942, 769.4149729198799).
GLOBAL ASC_THET IS LIST(90.0, 90.0, 87.29999999999991, 84.60151062638701, 84.60151062638688, 84.5463434346498, 82.71829219367753,
    80.84160386779887, 77.94712467321044, 76.66543361886897, 75.41647326257875, 73.32856088648539,
    69.5062179539746, 68.46797904918147, 67.49310751256648, 66.50606278074028, 65.59386638257494,
    64.09367758864657, 62.67724049738521, 61.35276612008599, 59.96208504174871, 57.87932322966173,
    55.78228901565141, 54.20846307618866, 52.69331519683485, 51.16772217022469, 49.76926479061175,
    48.678077732850134, 47.50127140191763, 45.3904256425957).
GLOBAL ASC_PSI IS LIST(65.56382518068695, 65.56382518068695, 65.56382518068699, 65.56382518068692, 65.56382518068695,
    67.60097792651005, 67.87822053207256, 68.03725403638639, 68.17873441209572, 68.22127379914133,
    68.25592920375817, 68.3038041016247, 68.37235285597255, 68.38840661835268, 68.40282730924196,
    68.41689734103831, 68.42951404675482, 68.44965674674712, 68.46822045345714, 68.48539788770223,
    68.50345799446461, 68.53099689979659, 68.55990963996446, 68.58286999699942, 68.6064279696224,
    68.63192869791105, 68.6571977122599, 68.67840129035137, 68.7029670564769, 68.7522576209197).
GLOBAL ASC_PHI IS LIST(0.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0).
GLOBAL ASC_SSSL IS 343.62449484775993.   // m/s: SS = SSSL - DSSA min(ALTG, ALTSS)
GLOBAL ASC_DSSA IS 0.003981291427971787.   // 1/s
GLOBAL ASC_ALTSS IS 13540.0.   // m
GLOBAL ASC_T_CNS_PITCH_RATE IS 69.9.   // s MET: the constant pitch rate from here
GLOBAL ASC_THETC_DOT_NOM_RAD IS -0.00955306189931197.   // rad/s: tan(theta / 4) grows 0.25 x this per s
// ---- the boost throttle (FSSR 4.2.4): K_CMD = THROT(J) when V_rel >= QPOLY(J), at most four; nominally the
// bucket through max q (the crew workbook's Tables 2-2 / 2-3)
GLOBAL ASC_QPOLY IS LIST(18.288, 198.12, 241.4016, 397.4592).   // m/s of V_rel (the surface speed)
GLOBAL ASC_THROT IS LIST(104, 104, 72.0, 104).   // PL %
GLOBAL ASC_K_STAGE1 IS 104.   // PL %, from the pad
// ---- stage 2: the FSSR K-loads (Table 4.3.5-4, in SI)
GLOBAL ASC_DTGD IS 1.92.   // s, the guidance cycle
GLOBAL ASC_DT_FCD IS 0.32.   // s, the fine count cycle
GLOBAL ASC_AL IS 29.108400000000003.   // m/s2, the acceleration limit
GLOBAL ASC_ALIM_1 IS 28.041600000000003.   // m/s2, G-LIM off below
GLOBAL ASC_ALIM_2 IS 28.86456.   // m/s2, G-LIM on above
GLOBAL ASC_AD_INIT IS 28.71216.   // m/s2, the first G-LIM target
GLOBAL ASC_K_PROP IS 0.15.   // 1/s
GLOBAL ASC_K_INT IS 0.01.   // 1/s2
GLOBAL ASC_TLAG IS 0.5.   // s between throttle commands
GLOBAL ASC_KDOT IS 10.0.   // PL %/s (DV_RAMP only)
GLOBAL ASC_EPSTGO IS 0.04.   // the steering update test
GLOBAL ASC_ETB IS 5.0.   // s, the constant thrust phase dropped below
GLOBAL ASC_KMISS IS 0.01.   // converged
GLOBAL ASC_DTRD IS 40.0.   // s, the position release TGO
GLOBAL ASC_PHIDOT_MAX IS 0.035.   // rad/s
GLOBAL ASC_NSEG IS 10.   // the coast segments
GLOBAL ASC_DTMIN IS 2.0.   // s
GLOBAL ASC_DTMAX IS 1.0e+20.   // s
GLOBAL ASC_RHOMAG IS 1.0.
GLOBAL ASC_FT_FACTOR IS 0.998.
GLOBAL ASC_STG2_MECO_INIT_TGO IS 0.96.   // s, T_MECO fixed below
// ---- stage 2: the I-loads the FSSR leaves blank (this vehicle's choices)
GLOBAL ASC_KMIN IS 67.0.   // PL %, the floor
GLOBAL ASC_KMAX IS 104.   // PL %: the nominal; ASC_KMAX_ABORT from an SSME out / an abort
GLOBAL ASC_KMAX_ABORT IS 109.   // PL %: KMAX in an abort (ops1q asc_kabort), capped at the SSMEs' full thrust
GLOBAL ASC_TGO_FCD IS 10.0.   // s, the fine count from
GLOBAL ASC_DT_MIN_K IS 6.0.   // s at KMIN before MECO
GLOBAL ASC_DT_TAILOFF IS 0.0.   // s
GLOBAL ASC_V_RHO_PHI IS 1700.0.   // m/s, the heads-up roll (relative speed)
GLOBAL ASC_ET_RESERVE_FRAC IS 0.01.   // of the ET load: the ABORT PLANNERS' guard only (the TAL / ATO / RTLS /
// droop / ARD / ABR tests plan to it, a margin on what the flight can really burn); the flown MECO keeps none: MASS_MIN =
// the core with the ET empty
GLOBAL ASC_ET_MECO_FRAC IS 0.002.   // of the ET load: the
// commanded MECO's floor (ops1q asc_et_low: MECO "res" at it, ~0.4 t: 0.55 s of 3 SSMEs at full (0.70 t/s), ~0.9 s at
// the 3 g limit, so the cutoff is commanded, never the dry tank's flame-out); the EO watch's window ends at it
// (lib_ascent_eo)
GLOBAL ASC_ET_MECO_PASSES IS 2.   // passes: MECO "res" also when the floor is this many passes of the last pass's burn
// away (a slow pass never reaches the dry tank: the cutoff lands one pass after the test)
GLOBAL ASC_ET_SEP_DELAY IS 4.0.   // s from MECO to the ET separation (the next stage of the craft)
GLOBAL ASC_ROLL_RATE IS 5.0.   // deg/s, the roll to heads up at V_RHO_PHI (this vehicle's)
GLOBAL ASC_ROLL_RAMP IS 2.0.   // s: the roll's rate fed forward to the engine-out DAP, ramped down over it
GLOBAL ASC_WFF_TAU IS 2.0.     // s: the low-pass on the guidance attitude's rate fed forward to the DAP (~a PEG cycle)
GLOBAL ASC_WFF_STEP IS 2.0.    // deg: a pass turning the guidance attitude more is a step, not a rate (adds none)
GLOBAL ASC_OMS2_MAX IS 150.0.   // m/s, the OMS-2 budget
// ---- TAL (FSSR 4.8.1 PEG subtask 15a; the offline TAL sim): MECO at RDMAG, GAMD deg; the cutoff speed
// from the range RTHETA (m) to the site at TP: VDMAG = MIDVAL(VMIN, A0 + A1 R + A2 R^2 + A3 R^3, VMAX). The cubic
// puts the site where the entry flies 67.5 deg of bank: the constant bank whose reach from the interface is the
// range to the aim, 52 km short of the site, the site CRMAX beside the MECO track as the plane below leaves it (a
// little more margin than a nominal deorbit's 60; offline flown 66.9-67.7 deg for SSME outs 40-200 s). The plane
// the present orbit's while the site lies within CRMAX (m) of it, else swung toward a point CRMAX short of it.
// The sites: only those in reach are listed (a short site is hidden), and the TAL site can be switched after the
// abort is called. The order is the fallback only -- ops1q ranks them by the ARD's rank (the most ET at MECO), else by
// the crossrange; lat / lng deg (the KK centres), alt m. Shannon's cubic is fitted offline the same way (the 67.5 deg
// fit that gives ZZA's and MRN's below exactly; SNN within 3 m/s of them from 1000 to 2400 km).
GLOBAL ASC_TAL_SITES IS LIST("ZZA", "MRN", "SNN").
// THE 2EO LOW-ENERGY TARGETS: a 2EO TAL on the 1EO targets enters far too hot. The FSSR's S_DROOP_TARGETS
// (STS 83-0002-34: a TAL whose droop goes below MIN_DROOP_ALT flies RDMAG = RD_LOW, GAMD = GAMD_LOW, CR_MAX =
// CR_MAX_LOW) with this vehicle's own cubic and floor: "A_LOW", "VMIN_LOW", "RDMAG_LOW", "GAMD_LOW", "CRMAX_LOW" per
// site, used (ops1q asc_tal_low) once one SSME is left after liftoff. RD_LOW 75 km / GAMD_LOW +1.0 deg are this
// vehicle's (the FSSR text gives no values; a 2EO TAL that failed in flight cut at 77.8 km, +1.2 deg). The cubic: the
// site where the entry flies 45 deg of bank from that MECO at the TAL's mass (aero x1.153), the 0-deg pre-entry hold
// and the 3.7 g Nz limiter in the reach (offline; the 45 deg from the closed loop on that flight: MECO 3300 -> 26 km
// past the aim, +17 km EOW; 3100-3140 lands). Checked in the closed loop (TAL guidance + V4n/F2 limiter + TAEM's first
// cycle) over 3 sites x 600-1350 km: at <= 85 km of crossrange 750-1350 km miss 1-13 km, EOW +3..+8 km (the 1EO line's
// own +2.4..+4.1); 600 km +10..+13 km; past ~150 km of crossrange short -> CRMAX_LOW 100 km. 40 / 42 deg moved the
// energy by < 1 km.
// A_LOW is the closed-loop refit of that cubic (one common correction 600 -160 .. 1650 +35 m/s, refitted per site
// 600..1650 km; VALID 600-1650 km ONLY) and VMIN_LOW 2500 (a 2600 floor undoes it at short range: ~2530 at 600 km).
// With the TAL range through the HAC, over 2EO TALs 750-1350 km, crossrange <= 85 km, MECO -20/0/+20 m/s, the refit
// takes EOW +3.1 -> +2.1 km mean, worst +8.3 -> +6.2, miss max 28.8 -> 21.1 km, Nz <= 3.31.
GLOBAL ASC_TAL_LOW_ON IS TRUE.   // FALSE: a 2EO TAL flies the 1EO targets
GLOBAL ASC_TAL IS LEXICON(
    "ZZA", LEXICON("name", "Zaragoza", "lat", 41.67024, "lng", -1.06107, "alt", 0.0,
        "A", LIST(1475.4503974125957, 0.0031046353397828565, -1.4624809620964027e-09, 2.3876806733244766e-16),
        "VMIN", 3300.0, "VMAX", 3780.0, "CRMAX", 200000.0, "RDMAG", 1674752.5, "GAMD", 0.0,
        "A_LOW", LIST(-720.6195930516016, 0.008321855163439232, -5.638592244860359e-09, 1.3328271507440228e-15),
        "VMIN_LOW", 2500.0, "CRMAX_LOW", 100000.0, "RDMAG_LOW", 1667752.5, "GAMD_LOW", 1.0),
    "MRN", LEXICON("name", "Moron", "lat", 37.17608, "lng", -5.61555, "alt", 0.0,
        "A", LIST(1466.734908337184, 0.003141365480726291, -1.491788355051137e-09, 2.453521131254965e-16),
        "VMIN", 3300.0, "VMAX", 3780.0, "CRMAX", 200000.0, "RDMAG", 1674752.5, "GAMD", 0.0,
        "A_LOW", LIST(-702.8918387333796, 0.008290792268484996, -5.61888428739262e-09, 1.3286282653155656e-15),
        "VMIN_LOW", 2500.0, "CRMAX_LOW", 100000.0, "RDMAG_LOW", 1667752.5, "GAMD_LOW", 1.0),
    "SNN", LEXICON("name", "Shannon", "lat", 52.6943, "lng", -8.9475, "alt", 0.0,
        "A", LIST(1387.3891864764682, 0.0032836863284422665, -1.5745723604770872e-09, 2.6078933357564327e-16),
        "VMIN", 3300.0, "VMAX", 3780.0, "CRMAX", 200000.0, "RDMAG", 1674752.5, "GAMD", 0.0,
        "A_LOW", LIST(-772.4800369956166, 0.008423027571550406, -5.708511060298349e-09, 1.3488681036678683e-15),
        "VMIN_LOW", 2500.0, "CRMAX_LOW", 100000.0, "RDMAG_LOW", 1667752.5, "GAMD_LOW", 1.0)).
GLOBAL ASC_TAL_DUMP IS 2.5.   // t of OMS propellant dumped
GLOBAL ASC_TAL_OMS_DELAY IS 5.0.   // s from the selection (or PEG's start) to the OMS dump
GLOBAL ASC_TAL_OMS_TGO_OFF IS 20.0.   // s: the dump stops at this TGO at the latest
GLOBAL ASC_TAL_DT_SITE IS 60.0.   // s from the selection: the propellant check on PEG's first converged pass from then
GLOBAL ASC_TAL_MARGIN IS 0.0.   // m/s: the second site when the ET's dV less VGO is under this
// ---- RTLS (FSSR 4.6 powered RTLS + PEG SMODE 5 + 4.8.5; the offline RTLS sim): the site and this vehicle's
// I-loads (the FSSR leaves them blank or gives the orbiter's)
// THE LAUNCH SITES (the RTLS returns to the runway of the site it launched from): each site's RTLS runway ("rtls":
// its name = ops6q's site key; the midpoint of its thresholds, hud/hud_runways.txt) and, where the site's I-loads
// differ from the KSC set in this file, its own ("il", by the globals' names less ASC_). ops1q takes the site whose
// runway lies nearest the pad (lib_ascent_gui's asc_site_pick / asc_site_set) before the target box: the RTLS, NEG
// RTN and the OPS 6 hand-off go to that runway, the box opens on that site's target. Vandenberg (SLC-6): 98 deg south
// by default; its I-loads are the offline sandbox's (160 km at 98 deg south from SLC-6), written by this file's
// generator where they differ from KSC's: the MECO target (no ET margin left from Vandenberg: OMS-2
// about 159 m/s), the plane, stage 1's tables (PSI mirrored north, -180 - the heading, as a south launch flies
// 180 - it); the ATO's MECO speed for the site's MECO angle (asc_site_set); the box's ET margin 0; the RTLS's
// fuel dissipation angle (heavier returns: 73 deg after an SSME out at liftoff, 65 from 700 m/s).
// A site's "tal", the TAL sites flown from it, replaces ASC_TAL_SITES (asc_site_set); a site without the key keeps
// KSC's. Vandenberg: none, so no TAL that flight: no TAL site weather selector in the launch target GUI, and ops1q's
// path for every site NO WX (no TAL marks, no TAL in the Mode list, a TAL by hand refused).
RUNONCEPATH("0:/lib/lib_cape.ks").   // the SLF where the Katniss Cape is (capeSlfMid)
GLOBAL ASC_SITES IS LIST(
  LEXICON("name", "KSC", "rtls", LEXICON("name", "SLF", "lat", capeSlfMid()[0], "lng", capeSlfMid()[1], "alt", 7.7)),
  LEXICON("name", "VBG", "rtls", LEXICON("name", "VBG", "lat", 34.736902, "lng", -120.5842495, "alt", 24.16), "tal", LIST(),
    "il", LEXICON(
    "TGT_INC", 98.0, "LAUNCH_DIR", -1, "GAMD", 4.167954572291465, "VDMAG", 3771.1668122801234,
    "PLANE_DLNG", 1.2338058628307937, "PSI_INC", 98.0, "T_CNS_PITCH_RATE", 69.8,
    "THETC_DOT_NOM_RAD", -0.010068634760657301, "GUI_ETM", 0, "GUI_ETM_FT", 0,
    "RTLS_THETA_0", 157.5, "RTLS_THETA_1", -0.04, "RTLS_THETA_4", -0.15,
    "PPOLY", LIST(0.0, 35.0, 48.90959831408459, 61.86198309756648, 77.93818375505995, 79.19373786541136,
      114.24754739256058, 147.13525310303467, 179.437934186836, 192.4603390595646, 204.34607281920287,
      223.2711543555538, 254.39461071558713, 263.6492337464087, 271.9186020305722, 281.1355183564666, 291.3572817615207,
      308.5801082201819, 326.8977554936953, 347.3290933204322, 371.0289115708918, 405.32633174522766, 443.8764933144221,
      484.28000623380296, 528.9898436717609, 572.0913164376119, 617.7412071599265, 656.8286732694634, 697.8530915434156,
      775.1868426078998),
    "THET", LIST(90.0, 90.0, 87.79999999999977, 85.9, 85.88856707874545, 85.83437875470523, 83.1815004707394,
      80.46138039630728, 77.53789681495608, 76.25524473131165, 75.01018071758074, 72.88461969820459, 69.18971850731099,
      67.93162438555257, 66.90603957442042, 65.86740748691534, 64.81970050768582, 63.23974682262015, 61.74792691291125,
      60.26607659646105, 58.71674252777874, 56.692944723573305, 54.64403685577195, 52.903203743026076,
      51.15510004137552, 49.62187004690127, 48.1474889620985, 46.996560853130724, 45.88328482053744, 43.58540151102233),
    "PSI", LIST(-12.569974999684689, -12.569974999684689, -12.569974999684746, -12.569974999684689, -12.569974999684632,
      -12.842397523312684, -13.332804665335033, -13.679349635048027, -13.957036231497824, -14.05829089204255,
      -14.147281090363833, -14.281662871390722, -14.475172399937975, -14.53212180696923, -14.575768938178896,
      -14.617841132551291, -14.658445333730356, -14.716811911918256, -14.769370717563532, -14.819659303740508,
      -14.870640980051434, -14.935312383525257, -14.9990300071033, -15.052301621601202, -15.105427322070057,
      -15.151803707967673, -15.19627624334936, -15.230956684842596, -15.264508252771066, -15.33383717185049)))).
GLOBAL ASC_RTLS_SITE IS ASC_SITES[0]["rtls"].   // ops1q: the pad's site's (asc_site_set)
GLOBAL ASC_RTLS_H_PPD IS 55500.0.   // m above R: PEG's RDMAG at the PPD start
GLOBAL ASC_RTLS_GAMD IS 3.0.   // deg: PEG's flight path angle at the PPD start
GLOBAL ASC_RTLS_A_MECO IS LIST(-64.47, 0.007094, 912.4).   // 4.8.5: the MECO line V_RHO = A5 + A6 RTHETA - A7 gam (m/s, 1/s, m/s per rad)
// A5 is 30 m/s above the fit's -94.47 (offline GRTLS: TAEM CLEAN 6 of 6; the powered RTLS valid 0-169 s)
// The fuel dissipation thrust angle (FSSR 4.6.6): THETA_0 + THETA_1 V + THETA_4 HDOT below V_SWTCH, V and HDOT the
// relative speed and climb rate at the RTLS's start (an SSME out in stage 1: at the SRB separation). KSC's: about
// 63-66 deg over stage 1 (a stack climbing faster at the separation pitches less), 65 at V_SWTCH (= THETA_2): the
// middle of the angles that return from every stage-1 failure offline (kOS's stage 1, empty to +4 t payload, drag
// x0.8-1.2, a flown case; a flatter stage 1 too). A line fitted on a flatter stage 1 (181.6667 - 0.1666667 V) gives
// 80 deg after an SSME out at 1.6 s: the stack climbs past 78 km, never pitches around, and PEG never converges for
// the turn. A site's own: ASC_SITES (asc_site_set).
GLOBAL ASC_RTLS_THETA_0 IS 90.2.   // deg
GLOBAL ASC_RTLS_THETA_1 IS 0.06.   // deg per m/s
GLOBAL ASC_RTLS_THETA_4 IS -0.15.   // deg per m/s of climb rate
GLOBAL ASC_RTLS_V_SWTCH IS 700.0.   // m/s of V_RTLS_FD (the relative speed at the selection)
GLOBAL ASC_RTLS_THETA_2 IS 65.0.   // deg: THETA_2 + THETA_3 V from V_SWTCH
GLOBAL ASC_RTLS_THETA_3 IS 0.0.   // deg per m/s
GLOBAL ASC_RTLS_THETA_MIN IS 25.0.   // deg
GLOBAL ASC_RTLS_THETA_MAX IS 85.0.   // deg
GLOBAL ASC_RTLS_THETA_FB IS 130.0.   // deg: the first flyback thrust angle from the downrange horizon
GLOBAL ASC_RTLS_DTHETA_LIM IS 10.0.   // deg/s: the pitcharound rate
GLOBAL ASC_RTLS_DTHETA_RATE IS 5.0.   // deg/s2: in DT_TURN
GLOBAL ASC_RTLS_SLEW_MIN IS 2.0.   // deg: smaller command changes are taken at once
GLOBAL ASC_RTLS_RETGT_MAX IS 10.0.   // deg: PEG's command re-sent while its slew runs moves the slew's target this far
GLOBAL ASC_RTLS_SEP_HOLD_MAX IS 5.0.   // s: an RTLS from stage 1 holds the SRB sep's attitude at most this long
GLOBAL ASC_RTLS_TGO_PPD IS 8.0.   // s: PEG's TGO for the fine countdown; the PPD at its TP
GLOBAL ASC_RTLS_PPD_RATE IS 10.0.   // deg/s: the pitchdown's slew
GLOBAL ASC_RTLS_ALPHA_PPD IS -2.0.   // deg: the ET separation alpha
GLOBAL ASC_RTLS_THRUST_OFF IS 8.0.   // deg: the SSMEs' thrust below the nose (the python's; kOS uses the measured axis)
GLOBAL ASC_RTLS_THETA_PPD0 IS 65.0.   // deg: the thrust above V_rel at the PPD start (ppd_predict)
GLOBAL ASC_RTLS_THETA_PPD0_3ENG IS 85.0.   // deg: the same for an RTLS begun on 3 SSMEs (its PPD starts higher)
GLOBAL ASC_RTLS_T_SETTLE IS 1.0.   // s at the ET separation attitude before MECO may come
GLOBAL ASC_RTLS_DT_PPD_MARGIN IS 3.0.   // s at KMIN beyond the planned PPD, in MBO
GLOBAL ASC_RTLS_M_BIAS IS 2.0.   // t: the bias against a late turnaround
GLOBAL ASC_RTLS_DK_ROUND IS 1.0.   // PL %: the flyback's throttle granularity
GLOBAL ASC_RTLS_RNG_TURN_PRED IS 30000.0.   // m: PEG reinitializes below this range
// PEG's first throttle K = the K_CMD flown (no separate two- / three-engine first throttles)
GLOBAL ASC_RTLS_DELK_MAX IS 2.0.   // PL % per pass: the throttle's step limit
GLOBAL ASC_RTLS_KMISS IS 0.025.   // PEG RTLS converged: |vmiss| <= KMISS |vgo| (not 0.02: at 109 % the miss reaches 2.2 %)
GLOBAL ASC_RTLS_PHIDOT_MAX IS 0.05.   // rad/s: PEG RTLS's turning-rate limit (ASC_PHIDOT_MAX 0.035 = the FSSR's)
GLOBAL ASC_RTLS_MECO_INIT_TGO IS 0.96.   // s: T_MECO set below this TGO
GLOBAL ASC_RTLS_DT_FCD IS 0.16.   // s: the cutoff cycle in the PPD
GLOBAL ASC_RTLS_DUMP_T IS 2.5.   // t of OMS dumped (the two-level rule: ASC_RTLS_DUMP_T_LO below V_DUMP_SW)
GLOBAL ASC_RTLS_DUMP_T_LO IS 4.0.   // t of OMS dumped when V_RTLS_FD < V_DUMP_SW
GLOBAL ASC_RTLS_V_DUMP_SW IS 750.0.   // m/s

// FSSR 4.9.7 mode 5 after a second SSME out on the RTLS flyback (this vehicle's I-loads, from the offline sim)
GLOBAL ASC_RTLS_M5_VH IS -650.0.   // m/s toward the site: mode 5 at or above (on the flyback), PEG on one SSME below
GLOBAL ASC_RTLS_M5_TH IS 70.0.   // deg: the thrust's largest elevation (THETA_MODE5_MAX - PITCH_CANT)
GLOBAL ASC_RTLS_M5_HDT IS 30.0.   // m/s: the H-dot target (HDOT_TGT_MODE5; 0, 30 and 60 fly the same in the python)
GLOBAL ASC_RTLS_M5_RATE IS 5.0.   // deg/s: the command's slew (DEL_LAMC_MODE5)
// mode 5's emergency sep (lib_ascent_rtls asc_rtls_es_test; SCOM 6.7's fast seps)
GLOBAL ASC_RTLS_ES_Q IS 0.7 * 47.880259.   // Pa: q ahead that calls it (SCOM: the rate fast sep starts at ~0.7 psf)
GLOBAL ASC_RTLS_ES_DT IS 5.0.     // s: how far ahead q is predicted (MECO, the sep, a pass)
GLOBAL ASC_RTLS_ES_H IS 40000.0.  // m: the sink must stop above this, else the sep (50 km: still none in the python)
GLOBAL ASC_RTLS_ES_TSEP IS 1.0.   // s: MECO to the ET sep (as the 2EO rate sep's, ASC_CNT_T_SEP_RATE)
// ---- ATO / AOA (FSSR 4.5.2; the offline ATO sim): PEG's MECO speed at the selection for an apogee at
// R + ATO_H (the nominal RDMAG and GAMD kept; the AOA too); after the ET separation the OMS plans: ATO an ATO_H
// circle with ATO_DV_DEORBIT kept, AOA the apogee at least AOA_H, then the perigee to AOA_HPE (the entry)
GLOBAL ASC_ATO_VDMAG IS 3845.693094699531.   // m/s: the ATO MECO target speed (the vis-viva apogee at R + ATO_H)
GLOBAL ASC_ATO_H IS 150000.0.   // m above R: the ATO orbit (circular)
// ---- THE OMS RULE: after OMS-2 there must be left 1. the deorbit's fuel, from the target altitude; 2. 100 m/s by
// default for on-orbit manoeuvres and rendezvous (settable in the launch selection GUI); 3. a 50 m/s emergency margin.
// The ATO is pre-selected when the deorbit from the ATO orbit + the emergency margin is left after its OMS-2 (no
// on-orbit allowance; the ATO / AOA window shows whether that is left too); the AOA keeps the emergency margin (lib_aoa).
GLOBAL ASC_OMS_ONORB IS 100.0.   // m/s: the on-orbit allowance kept after OMS-2 (the launch box sets it)
GLOBAL ASC_OMS_EMERG IS 50.0.    // m/s: the emergency margin kept after OMS-2 (the AOA's too: AOA_OMS_RESERVE)
GLOBAL ASC_OMS_DV_NOW IS -1.     // m/s: the OMS dV after the ET sep with the payload (the launch box measures it); -1 =
                                 //   not measured (the abort search's ATO then takes ASC_ARD_OMS_DV)
GLOBAL ASC_DO_EI IS 80000.0.     // m: the interface (= deorbit_plan.ks DP_GEO_EI_ALT, deorbit_sim ATM)
GLOBAL ASC_DO_FPA_SLOPE IS -0.000009445687.   // deg per m of the orbit's height  \  the deorbit planner's interface
GLOBAL ASC_DO_FPA_ICPT IS 0.6554.             // deg                             >  angle (= deorbit_plan.ks DP_FPA_*,
GLOBAL ASC_DO_FPA_MARGIN IS 0.75.             // deg steeper                    /   deorbit_sim FPA_*)
// The deorbit dV (m/s) from a circle altM above R: the retrograde burn whose orbit meets the interface at the
// planner's angle (two-body, impulsive; within +0.3..+4.9 m/s ABOVE deorbit_sim.dv_for_fpa from 110 to 350 km at
// 28.5 and 51.6 deg, offline). v1 from h = re v_ei cos(fpa) and the energy.
FUNCTION asc_deorbit_dv {
  PARAMETER altM.
  LOCAL r1 IS ASC_R + altM.
  LOCAL re IS ASC_R + ASC_DO_EI.
  IF r1 <= re { RETURN 0. }
  LOCAL c2 IS COS(ASC_DO_FPA_SLOPE * altM + ASC_DO_FPA_ICPT - ASC_DO_FPA_MARGIN) ^ 2.
  LOCAL v1 IS SQRT(2 * ASC_MU * re * re * c2 * (1 / re - 1 / r1) / (r1 * r1 - re * re * c2)).
  RETURN SQRT(ASC_MU / r1) - v1.
}
GLOBAL ASC_ATO_DV_DEORBIT IS asc_deorbit_dv(ASC_ATO_H) + ASC_OMS_EMERG.   // m/s kept after the ATO's OMS-2 (the OMS rule's
                                 //   ATO case: the deorbit from the ATO orbit + the emergency margin; 105.4 at 150 km)
GLOBAL ASC_OMS_F IS 60.0.   // kN, both OMS engines: the plans' burn time
GLOBAL ASC_OMS_ISP IS 316.0.   // s: the plans' budget and burn time
// ---- THE OMS ASSIST (ops1q asc_ast_*; active only when the mass exceeds the limits without it): the ET's margin line
// of the heaviest flight that reaches the MECO target without it (4.35 t of payload, the 1 % reserve; offline: 8
// points within 0.25 m/s of its 101 passes) and the law fitted on the offline flyer
GLOBAL ASC_AST_ON IS TRUE.      // FALSE: never
GLOBAL ASC_AST_DT IS 6.         // s after the sep: the check at the first converged PEG pass from then
GLOBAL ASC_AST_DT2 IS 40.       // s after the sep: the re-check (once) from then, and ASC_AST_WAIT s after the stop
GLOBAL ASC_AST_WAIT IS 4.
GLOBAL ASC_AST_PAD IS 4.        // m/s over the line: the check's and the size's aim (the game: -0.4..+2.6 over
//                                 python; 4, not 2: the logged heavy flight lost ~3.5 m/s more over stage 2 than
//                                 python)
GLOBAL ASC_AST_RC IS 1.         // m/s over the line: the re-check's
GLOBAL ASC_AST_G0 IS 0.90.      // the size's gain G0 + G1 X (X in t): the joint burn's smaller gravity loss
GLOBAL ASC_AST_G1 IS 0.015.
GLOBAL ASC_AST_MIN IS 0.02.     // t: no smaller assist (~1 s of both AJ10s)
GLOBAL ASC_AST_TDT IS LIST(3.84, 5.76, 7.68, 13.44, 21.12, 34.56, 59.52, 195.84).   // s after the sep
GLOBAL ASC_AST_TE IS LIST(17.8, 12.92, 10.95, 7.61, 4.98, 2.73, 1.35, 0.72).        // m/s: that flight's margin then
// The launch box's estimate of the assist, with the OMS dump (lib_ascent_gui asc_gui_ast; a physics estimate, the
// rocket equation at the SRB sep, for any target): the state at the first check from the parts and the target (the
// mass and the ET's burnable load after the sep less what the SSMEs burn by then, PEG's |VGO| then), sized by
// asc_ast_size as in flight. The burn to the check from three clean flights (60.94, 61.00, 61.21 t), |VGO| fitted on
// the 13 clean nominal game flights (-8..+5 m/s on the current code's 12) with the offline flyer's mass slope (12.0 m/s
// per t).
GLOBAL ASC_AST_PRE_B IS 61.0.      // t of the ET burned from the box (engines off) to the check, 3 SSMEs
GLOBAL ASC_AST_PRE_B0 IS 3.7.      // t of it before liftoff (asc["et_full"], the reserve's base, is the liftoff's)
GLOBAL ASC_AST_PRE_DT IS 7.7.      // s after the sep: the check (the first converged pass from ASC_AST_DT)
GLOBAL ASC_AST_PRE_V0 IS 3447.03.  // m/s: |VGO| then at the reference: M0, VD0, 51.6 deg, GAM0
GLOBAL ASC_AST_PRE_M0 IS 166.8.    // t: the vessel at the check
GLOBAL ASC_AST_PRE_KM IS 12.0.     // m/s per t of it
GLOBAL ASC_AST_PRE_VD0 IS 3856.2.  // m/s: VDMAG
GLOBAL ASC_AST_PRE_KV IS 0.9705.   // per m/s of VDMAG
GLOBAL ASC_AST_PRE_KI IS -266.56.  // m/s per unit of cos(inc) - cos(51.6)
GLOBAL ASC_AST_PRE_GAM0 IS 2.104.  // deg: GAMD
GLOBAL ASC_AST_PRE_KG IS -43.45.   // m/s per deg of GAMD (Vandenberg's I-loads)
GLOBAL ASC_AST_PRE_LOG IS "".      // the box's "#astpre" line at ACCEPT (ops1q logs it at liftoff)
GLOBAL ASC_ABT_OMS1_LEAD IS 120.0.   // s from the plans' writing to OMS-1's start (this vehicle's)
