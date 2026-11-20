// lib_ascent_cnt.ks -- THE 2EO CONTINGENCY: FSSR 4.9 POWERED CONTINGENCY GUIDANCE (PW CONT GUID; STS 83-0002-34),
// uphill, in plane, with the rate fast sep. After the second SSME out in stage 2 ops1q arms it (asc_cnt_new) and,
// at the next tick (CREW_DELAY 0), starts it in the mode MODE SEL gives (asc_cnt_sel: 1 while HDOT > HDOT_MODE1; else 0
// above VI_MIN_DROOP -- no contingency, PEG + the droop fly on; else 2) as ops1q's choice at the start takes it
// (asc_cnt_pick: the pages' 2EO line and the live sweep's mode); then its own passes every ASC_DTGD (asc_cnt_cycle) and
// the thrust direction + the roll attitude every tick (asc_cnt_dir, asc_cnt_top). A late 2EO's MODE SEL 1 flies mode 2
// (asc_cnt_m1to2).
// A port of the offline sim's contingency guidance (with its rate fast sep and its yaw to an ELS): the same I-loads,
// phases, formulas and order, in PEG's inertial frame (lib_ascent_peg: right-handed, z the spin axis; r and v as
// asc_sample gives them, wv the velocity relative to the air), so the offline vectors replay through it:
//   MODE 1 ("fly horizontal"): the thrust to THETA_MODE1 heads down (man), the roll heads up (roll), heads up to apogee
//   (hold), then the rate fast sep (ppd2: the pitch-down rate built up at PITCH_ACC to HIGH_SEP_RATE, C/O once past
//   QMECO_HIGH; a roll that ends past apogee goes straight to it) or, ASC_CNT_RATE_SEP FALSE, the alpha fast sep
//   (ppd1: to ALPHA_PPD, C/O within DALF_PPD); GREEN's yaw (4.9.4's second procedure, SCOM 6.7: 45 deg, open loop, for
//   an ECAL / BDA landing): with cn["yaw"] (asc_cnt_yaw) all of it PSI_MODE1_YAW toward the ELS until apogee, then back
//   in plane (yawback), then the fast sep;
//   MODE 2 ("stand on the tail"): THETA_MODE2 heads down, the roll, heads up until EAS > EAS_PD past apogee, then the
//   rate fast sep; or sooner, once the contingency's site is within ASC_CNT_DCO (a deviation: the early C/O).
//   THE MODE-2 HOLD (a deviation, ASC_CNT_M2H): in mode 2's hold the thrust holds HDOT under an altitude cap, yawed
//   toward a runway end, until the cut law's C/O (asc_cnt_m2; the I-loads after ASC_CNT_DCO).
// kOS ONLY (the offline sim is 3-DOF: the thrust direction alone): the roll attitude (asc_cnt_top: the canopy side,
// -Zb); the roll's angle at most ROLL_LEAD past the stack's own (asc_cnt_phi; the RCS rolls it: lib_ascent_dap's
// "roll1"; the replay: the open loop); a stack already heads up at the start (the nominal roll begun) skips man + roll.
// An RTLS's second failure can start it too (cn["rtls"], ops1q's asc_rtls_m2_go: mode 2 with the load gate).
// NOT BUILT: a 2EO in stage 1. THE DROOP (FSSR 4.3.4): at this file's end.
@LAZYGLOBAL OFF.

// the I-loads (the offline sim's; the FSSR lists the names only): this vehicle's
// A 2EO needs no crew decision (its mode is picked by itself: ab_auto off), so the start and the OMS dump follow the
// second failure at once; a combined yaw, pitch, roll and dump right away improves the chance of making a runway. The
// roll to heads up starts at the failure.
GLOBAL ASC_CNT_CREW_DELAY IS 0.0.        // s: the start after the second failure (0: at once, no crew action)
GLOBAL ASC_CNT_BOTH_S IS 4.0.            // s: a second failure this soon after the first = both out together (the 2EO marks' case)
GLOBAL ASC_CNT_DUMP_DELAY IS 0.0.        // s: a 2EO's OMS dump from its start (0: at once)
GLOBAL ASC_CNT_HDOT_MODE1 IS 300.0.      // m/s: mode 1 above this altitude rate
GLOBAL ASC_CNT_VI_MIN_DROOP IS 1408.0.   // m/s (4,620 ft/s): mode 0 (no contingency) above it when not mode 1
GLOBAL ASC_CNT_THETA_MODE1 IS 13.0.      // deg body pitch: the thrust on the horizon heads up ("toward the horizon")
GLOBAL ASC_CNT_THETA_MODE2 IS 90.0.      // deg body pitch: near the vertical ("a vertical thrust vector")
GLOBAL ASC_CNT_HDOT_MODE1_PD IS 0.0.     // m/s: mode 1's pitchdown at apogee
GLOBAL ASC_CNT_EAS_PD IS 10.0.           // KEAS: mode 2's pitchdown (EAS above it, HDOT < 0)
GLOBAL ASC_CNT_ALPHA_PPD IS -2.0.        // deg: the alpha fast sep's alpha (ASC_CNT_RATE_SEP FALSE)
GLOBAL ASC_CNT_DALF_PPD IS 2.0.          // deg
GLOBAL ASC_CNT_HIGH_SEP_RATE IS -4.0.    // deg/s: the rate fast sep's pitch rate ("a -4 deg per second pitch rate")
GLOBAL ASC_CNT_QMECO_HIGH IS -3.5.       // deg/s: C/O once the rate is past it
GLOBAL ASC_CNT_CANT IS 13.0.             // deg: the thrust vs the body X axis (the FSSR's default 0.2269 rad)
GLOBAL ASC_CNT_SLEW IS 2.0.              // deg/s: the attitude slew (the DAP's rate limit)
GLOBAL ASC_CNT_ROLL_RATE IS 5.0.         // deg/s: the roll heads up (the RCS with one SSME)
GLOBAL ASC_CNT_PITCH_ACC IS 1.0.         // deg/s2: the pitch-down rate's build-up
GLOBAL ASC_CNT_ROLL_DELAY_PASSES IS 2.   // passes aligned before the roll
GLOBAL ASC_CNT_ALIGN_DEG IS 3.0.         // deg
GLOBAL ASC_CNT_RATE_SEP IS TRUE.         // mode 1 separates by the rate (the rate fast sep); FALSE: alpha -2
GLOBAL ASC_CNT_T_SEP_FAST IS 5.0.        // s: MECO to the ET separation (the fast sep, "about 5 seconds")
GLOBAL ASC_CNT_T_SEP_RATE IS 1.0.        // s: the same after the rate sep
GLOBAL ASC_CNT_ROLL_LEAD IS 10.0.        // deg: the roll's angle at most this far past the stack's own (kOS only)
GLOBAL ASC_CNT_PSI_MODE1_YAW IS 45.0.    // deg: GREEN's yaw toward the ELS (SCOM 6.7: 45 deg for an ECAL / BDA landing)
GLOBAL ASC_CNT_PSI_MODE1_YAW2 IS 20.0.   // deg: the live footprint's smaller yaw (its yaw code +-2; a deviation: SCOM 6.7
                                         // names 45 only; offline: 51.6 t2 82 s lands only so)
GLOBAL ASC_CNT_THETA_MODE1_YAW IS 13.0.  // deg body pitch while yawed (= THETA_MODE1)
GLOBAL ASC_CNT_HDOT_MODE1_BACK IS 0.0.   // m/s: the yaw back in plane below this altitude rate (at apogee)
GLOBAL ASC_CNT_VI_YAW_MAX IS 1355.0.     // m/s: the yaw only for a second failure below it (offline: both
                                         // out by 156 s yawed lands as well or better; from 157 s in plane does)
GLOBAL ASC_CNT_YAW_SITES IS LEXICON("BDA", LIST(32.3634171, -64.6739176)).   // the ELS the yaw turns toward: lat,
                                         // lng of the runway's midpoint (hud/hud_runways.txt)
GLOBAL ASC_CNT_DCO IS 180.0.             // km: THE EARLY C/O (a deviation; FSSR 4.9.9 cuts on the attitude / rate only):
                                         // a cut that reaches a pocket the stack would otherwise overshoot. Mode 2's
                                         // rate fast sep at once in the hold when the contingency's site (cn["site"]) is
                                         // this close (cn["d_site"]: the caller's ground distance, -1 none). Offline:
                                         // 180 catches BDA at the 6 late points that bailed out (the MECO 31-91 km from
                                         // it), none lost; 120 / 140 too close, 200 too far for TAEM. Only when the
                                         // early MECO scores better: cn["early_ok"] (the caller's: the live sweep's
                                         // window at vi2 is GREEN by its early MECO, lib_ascent_bgl's bgl_early_ok;
                                         // offline: 36.25 and 51.6 unchanged, 60 deg the 2 NKT landings kept)

// THE MODE-2 HOLD ON THIS VEHICLE (a deviation): a late 2EO before the 2EO TAL line can have the thrust to keep a
// positive HDOT, and mode 2 then climbs to a bad trajectory. FSSR 4.9.5 holds the thrust at THETA_MODE2 - CANT = 77 deg
// up until EAS > EAS_PD past apogee; one SSME late on this stack climbs to the ET's end instead (MECO VI 2023 at
// 122 km, seen twice in flight). A port of the offline sim's mode-2 hold (the same formulas and order, asc_cnt_m2
// before the pass, the yaw after it):
//   THE HOLD: the thrust's elevation e above the local horizontal holds HDOT at M2_HT: e = asin((GACC + M2_K (ht -
//     HDOT)) / (F / m)) within [M2_EMIN, 77] (GACC: gravity less the horizontal speed's centrifugal term), the rest of
//     the thrust adds speed; a stack that cannot hold keeps the FSSR's 77 deg and its pitch-down;
//   THE CAP: above M2_HCAP the HDOT target sinks (ht = M2_HT - M2_KH (h - M2_HCAP), at least M2_HDMIN), and a climb
//     whose coast alone tops M2_HCAP gets e = M2_EMIN (a lower MECO: a softer pull-out);
//   THE CUT LAW (fitted offline on the GRTLS runs): the hold's C/O (the rate fast sep) the first pass the predicted
//     distance at the TAEM hand-over to an end of ASC_CNT_LAW_ENDS, d - R, is at most LAW_HO km: d the great-circle
//     range (km), R the GRTLS's glide (km) = LAW_K . (1, VI, VI^2, h km, HDOT, |rel|, rel^2), VI capped at LAW_VIPK
//     (the fit's peak), rel the end's bearing off the ground track (deg); ops1q makes the end's site the
//     contingency's (OPS 6 lands there); in a contingency an RTLS started (cn["rtls"]) R uses LAW_KR and the C/O
//     comes at LAW_HOR (THE RTLS LAW, below);
//   THE YAW (the ECAL yaw: SCOM 6.7's 45 deg is mode 1's): the hold's thrust keeps e, its horizontal part turned toward
//     the law's best end of this pass, at most M2_PSI off the track;
//   THE FLAT THRUST (the catch work; ASC_CNT_M2_FLAT): a stack that cannot climb at 77 deg even at the ET's low
//     level (F / m_bo sin 77 < M2_EGATE GACC) thrusts at M2_EFIX instead.
// offline (the 51.6 sandbox, limiter A in the GRTLS, mode 2 flown): the late 2EOs caught 9 of 23 (10 with the flat thrust)
GLOBAL ASC_CNT_M2H IS TRUE.              // the hold, the cap, the cut law and the yaw (FALSE: the FSSR's mode 2)
GLOBAL ASC_CNT_M2_HT IS 5.0.             // m/s: the HDOT held
GLOBAL ASC_CNT_M2_K IS 0.1.              // 1/s: its gain
GLOBAL ASC_CNT_M2_EMIN IS 0.0.           // deg: the lowest elevation
GLOBAL ASC_CNT_M2_HCAP IS 80000.0.       // m: the altitude cap (0: none)
GLOBAL ASC_CNT_M2_KH IS 0.02.            // 1/s: the HDOT target's slope above the cap
GLOBAL ASC_CNT_M2_HDMIN IS -60.0.        // m/s: the lowest HDOT target
GLOBAL ASC_CNT_M2_PSI IS 45.0.           // deg: the yaw's largest angle off the track (0: no yaw)
GLOBAL ASC_CNT_M2_FLAT IS TRUE.          // the flat thrust
GLOBAL ASC_CNT_M2_EFIX IS 15.0.          // deg: its elevation
GLOBAL ASC_CNT_M2_EGATE IS 2.0.          // its gate, in GACCs
GLOBAL ASC_CNT_LATE_M2 IS TRUE.          // a late 2EO's MODE SEL 1 flies mode 2 + the hold (asc_cnt_m1to2)
GLOBAL ASC_CNT_LATE_M2_VI IS ASC_CNT_VI_YAW_MAX.   // m/s: late = the second failure at or above it (where mode 1's yaw
                                         // ends; offline: both out at 160-200 s, VI 1373-1860, mode 2 catches all that
                                         // mode 1 does + 160 / 170 s; at 130-150 s, VI 1114-1268, neither does)
GLOBAL ASC_CNT_LAW IS TRUE.              // the cut law and the yaw (with ASC_CNT_M2H)
GLOBAL ASC_CNT_LAW_HO IS 90.0.           // km: the hand-over distance it cuts at (THE UPHILL LAW, below; was 58)
// THE LOAD GATE (a deviation) in a contingency an RTLS started (cn["rtls"]: ops1q's asc_rtls_m2_go): the law still names
// its best end (the yaw) but cuts only once the stack is at or below LAW_GH or at most LAW_GV over the ground (offline:
// the 51.6 Halifax pullouts 1225 -> 487 psf and 4.8 -> 4.0 g for one catch; 36.25 unchanged: its Bermuda cuts are
// slow); the uphill contingency has no gate
GLOBAL ASC_CNT_LAW_GH IS 81000.0.        // m
GLOBAL ASC_CNT_LAW_GV IS 1300.0.         // m/s: the air-relative velocity's horizontal part
GLOBAL ASC_CNT_LAW_VIPK IS 2232.0.       // m/s: the fit's VI cap
// THE UPHILL LAW: LAW_K fitted on the GRTLS glide to the TAEM hand-over (Mach 2.5) from the flown uphill
// MODE SEL 2 hold passes to BDA10, from
// synthetic ends at 0..45 deg off the track and from synthetic hold states at VI 1400-2200 (h 65-80 km, HDOT -40..150)
// with the site near the cut, by the truth mapper (reproduces the flown glides to ~1 km): rms 7.5 km on the flown
// passes near the cut. The old list (-908.637, 1.1162, -0.00025, 0.70145, 0.11366, -7.58948, -0.12166; the 51.6
// sandbox, an older GRTLS) under-predicted the glide by 13-100 km (about 140 km at VI 2000): the C/O came late and
// TAEM began 37-44 km out with EOW-EN +14..+19 km over an overhead HAC; the test-run GREENs to BDA10 landed 8.6-10.7
// km short. LAW_HO 90: the truth hand-over where TAEM starts at EOW-EN about 0 (e0 = 0 at a hand-over 75-110 km out).
GLOBAL ASC_CNT_LAW_K IS LIST(-89.0033517, -0.193676271, 0.000194106192, 2.69551901, 0.279381358, -0.721925393, -0.0177193229).
// THE RTLS LAW: in a contingency an RTLS started (cn["rtls"]: ops1q's asc_rtls_m2_go) the glide R = LAW_KR . (the same 7
// terms) and the C/O comes at d - R <= LAW_HOR. LAW_K (fitted on uphill late 2EOs) under-predicts an RTLS cut's glide by
// 20-68 km;
// LAW_KR is fitted on the GRTLS glide to the TAEM hand-over (Mach 2.5) from the flown RTLS hold passes
// and from synthetic ends at 0..45 deg off the track (the truth mapper, which reproduces the 4 flown cuts
// to 3 km): 156 cases, rms 3.6 km near the cut, max 8.6; the 3 paths' TAEM catches overlap at a 33..55 km hand-over,
// LAW_HOR its middle. The uphill contingency (and the pad search's hold predictor) use LAW_K / LAW_HO (THE UPHILL LAW).
GLOBAL ASC_CNT_LAW_KR IS LIST(-354.863488, 0.405672646, -0.0000703608783, 1.38669577, 0.179988748, -0.143688155,
  -0.0235022181).
GLOBAL ASC_CNT_LAW_HOR IS 45.0.          // km: the RTLS law's hand-over distance
// THE REL GATE: the uphill law judges only the ends within LAW_REL of the track (|rel|); an end past it is not a
// cut and not a yaw target; none within: no law cut this pass, no yaw (the hold flies on). The uphill law is fitted on
// ends 0..45 deg off the track and the 2EO footprint (lib_ascent_bgl ASC_BGL_FP) has no span past about 45-50 deg at
// MECO VI 1100-1400; without the gate an early MODE SEL 2 (HDOT 150-300 m/s at the 2nd out) cut on its FIRST pass
// toward NKT31 at 58-75 deg off the track, d 127-145 km, which the GRTLS cannot reach (the truth mapper: BAIL_END):
// A 310-state test lost 51 landings the old law made (td >= -3 km, KD 1.3; 76 at KD 1.0); with the gate 15 (2).
// The RTLS law (cn["rtls"]) is not gated. 0: no gate. The pad search's hold predictor (CntHold, C#) does not gate yet.
GLOBAL ASC_CNT_LAW_REL IS 45.0.          // deg
// the ends it judges: every end of the East Coast ELS (bg1.CONT_SITES: BDA MYR NKT DOV LGA YHZ YQX), name, lat, lng of
// the threshold (hud/hud_runways.txt, as OPS 6's CONT table)
GLOBAL ASC_CNT_LAW_ENDS IS LIST(
  LIST("BDA10", 32.3680887, -64.6999367),
  LIST("BDA28", 32.3587454, -64.6478984),
  LIST("MYR35", 33.6561536, -78.9225205),
  LIST("MYR17", 33.7001088, -78.9337478),
  LIST("NKT31", 34.8658695, -76.8369811),
  LIST("NKT13", 34.9263524, -76.9107243),
  LIST("DOV31", 39.1170632, -75.4469832),
  LIST("DOV13", 39.1434765, -75.4938498),
  LIST("LGA30", 40.7679909, -73.8496049),
  LIST("LGA12", 40.7911352, -73.900473),
  LIST("YHZ04", 44.8670509, -63.5260895),
  LIST("YHZ22", 44.937118, -63.4568241),
  LIST("YQX01", 48.918106, -54.5666318),
  LIST("YQX19", 48.9623605, -54.5547519)).

FUNCTION asc_cnt_new {                   // armed at the second failure: its MET t2 and VI vi2 (m/s, the site's lookup)
  PARAMETER t2, vi2.
  RETURN LEXICON("t2", t2, "vi2", vi2, "on", FALSE, "sel", -1, "mode", 0, "ph", "", "t_start", -1, "t_next", 0,
    "k_al", 0, "t_roll", 0, "phi", 0, "t_ppd", 0, "u0", V(0, 0, 0), "t0", 0, "tgt", V(0, 0, 0), "xb", V(0, 0, 0),
    "nb", V(0, 0, 0), "sb", V(0, 0, 0), "beta", 0, "hu", FALSE, "ix", V(0, 0, 0), "iz", V(0, 0, 0), "t_cut", -1,
    "ph_cut", "", "alpha", 0, "rate", 0, "site", "NONE", "said0", FALSE, "yaw", 0, "d_site", -1, "early", -1,
    "early_said", FALSE, "early_ok", FALSE, "now", FALSE, "vd", "",   // now; vd ("", "RUN", the verdict's line)
    "th2", ASC_CNT_THETA_MODE2, "e2", -1, "acc", 0, "abo", 0, "eps", LIST(), "law_k", -1, "law_x", 0, "law_d", 0,
    "law_rel", 0, "law_cut", -1, "law_said", FALSE, "law_site", "",   // the mode-2 hold (asc_cnt_m2)
    "rtls", FALSE, "law_gated", 0, "gate_said", FALSE).   // started by an RTLS (the load gate), its holds
}

FUNCTION asc_cnt_sel {                   // CONT MODE SEL (4.9.2) on the inertial rr, vv: 1, 0 or 2
  PARAMETER rr, vv.
  IF VDOT(rr:NORMALIZED, vv) > ASC_CNT_HDOT_MODE1 { RETURN 1. }
  IF vv:MAG > ASC_CNT_VI_MIN_DROOP { RETURN 0. }
  RETURN 2.
}

// The start's choice, so the contingency flies what the pages show (and does not press to MECO on a 2EO the pages call
// GREEN). From MODE SEL's sel, the pages' 2EO line at the second failure two ("" with a mark unknown), trusted
// (the marks made for this failure: both out together, or the ARD's refresh on the two SSMEs left) and the live sweep's
// mode at vi2 wm (bgl_md; 0 outside its GREEN windows), and the pages' 2EO line at the FIRST failure two1 (ops1q's
// asc["eo1_2ln"]; "" none): -1 = the 2EO line's mode (ops1q's asc_2eo_go: PEG flies the PRESS / ATO / TAL it
// opens); -2 = two1's mode (the same); 0 = PEG flies on (the marks unknown only); 1 / 2 = the contingency there.
//   a mode open and trusted: that mode;
//   untrusted, two1 opening a mode: two1's (so a GREEN is not picked where an ATO is open) -- the marks were made for
//     the first failure's state on three SSMEs, and the two SSMEs after it only add speed (a flown case: the first out
//     at VI 1713 past the 2EO ATO's 1700, the second 7.3 s later at 1781; offline at that mass the ATO from that pair
//     reaches MECO at 90 km); after the ARD's refresh on two SSMEs (trusted) its marks decide instead;
//   GREEN (wm): the mode the sweep scored there (MODE SEL at the failure point; a flown case: HDOT 300 m/s at the
//     failure, 282 at the start a few s later on one SSME, so MODE SEL then said 0 while the sweep had scored mode 1
//     to BDA);
//   MODE SEL 0 (FSSR 4.9.2: the droop covers a 2EO) with the line known: the line's mode where it opens one (not PRESS
//     when only a TAL / ATO is open), else mode 1 -- the droop covers no mode there (a flown case: VI 1409 over
//     VI_MIN_DROOP 1408, under the droop's own bound 1415 and the 2EO TAL's 1516; offline on that failure pair mode 1
//     lands at BDA, mode 2 climbs to the ET's end at 100 km);
//   else MODE SEL's own.
FUNCTION asc_cnt_pick {
  PARAMETER sel, two, trusted, wm, two1 IS "".
  LOCAL open2 IS asc_cnt_open(two).
  IF trusted { IF open2 { RETURN -1. } }
  ELSE IF asc_cnt_open(two1) { RETURN -2. }
  IF wm > 0 { RETURN wm. }
  IF sel = 0 AND two <> "" {
    IF open2 { RETURN -1. }
    RETURN 1.
  }
  RETURN sel.
}

// THE LATE MODE 2 (ASC_CNT_LATE_M2): the start's pick pk of mode 1 from MODE SEL's own 1 (sel, at the start) after a
// second failure at vi2 >= ASC_CNT_LATE_M2_VI flies mode 2 instead, with the mode-2 hold, cap, yaw and cut law (mode 1
// flies none of them; offline over the 23 late 2EOs: 4 caught -> 6). TRUE = fly mode 2. MODE SEL 0's mode 1 (the droop
// covers no mode there) stays, as do mode 1 below the line (its yaw toward BDA) and every other pick.
FUNCTION asc_cnt_m1to2 {
  PARAMETER pk, sel, vi2.
  RETURN ASC_CNT_LATE_M2 AND pk = 1 AND sel = 1 AND vi2 >= ASC_CNT_LATE_M2_VI.
}

FUNCTION asc_cnt_open {                  // a 2EO line (asc_2eo_line's) that opens a mode: PRESS, ATO or TAL
  PARAMETER x.
  RETURN x = "PRESS" OR x:CONTAINS("ATO") OR x:CONTAINS("TAL").
}

FUNCTION asc_cnt_yaw {                   // GREEN's yaw for a contingency in mode md after the second failure at
  PARAMETER md, vi2, rr, wv, ps.         // vi2 (m/s), toward an ELS at ps (inertial, from the body's centre): 0 none,
  IF md <> 1 OR vi2 >= ASC_CNT_VI_YAW_MAX { RETURN 0. }   // 1 left, -1 right of the track
  LOCAL fz IS asc_cnt_frame(rr, wv).
  IF VDOT(ps, fz[1]) > 0 { RETURN -1. }
  RETURN 1.
}

FUNCTION asc_cnt_psi {                   // a yaw code (0; +-1 = 45 deg, +-2 = 20 deg; + left) ->
  PARAMETER yc.                          // the yaw in deg (+ left, - right of the track)
  IF ABS(yc) = 2 { RETURN (yc / 2) * ASC_CNT_PSI_MODE1_YAW2. }
  RETURN yc * ASC_CNT_PSI_MODE1_YAW.
}

FUNCTION asc_cnt_frame {                 // LIST(ix up, iy = wv x ix, iz = ix x iy downrange)
  PARAMETER rr, wv.
  LOCAL ix IS rr:NORMALIZED.
  LOCAL iy IS VCRS(wv, ix):NORMALIZED.
  RETURN LIST(ix, iy, VCRS(ix, iy)).
}

FUNCTION asc_cnt_upn {                   // the unit normal to u in the vertical plane on the sky side (uprange past
  PARAMETER u, ix, iz.                   // the vertical)
  LOCAL d IS VDOT(ix, u).
  IF ABS(d) > 0.9995 { RETURN -iz. }
  RETURN (ix - d * u):NORMALIZED.
}

FUNCTION asc_cnt_gc {                    // u0 turned toward u1 by at most amax deg on the great circle
  PARAMETER u0, u1, amax.
  LOCAL cs IS MIN(1, MAX(-1, VDOT(u0, u1))).
  LOCAL ang IS ARCCOS(cs).
  IF ang <= amax OR ang < 0.0000000573 { RETURN u1. }
  LOCAL w IS (u1 - cs * u0):NORMALIZED.
  RETURN COS(amax) * u0 + SIN(amax) * w.
}

FUNCTION asc_cnt_ppd2_ang {              // the pitch-down's angle (deg) at t: the rate built up at PITCH_ACC
  PARAMETER cn, t.
  LOCAL tau IS t - cn["t_ppd"].
  LOCAL wr IS ABS(ASC_CNT_HIGH_SEP_RATE).
  LOCAL t1 IS wr / ASC_CNT_PITCH_ACC.
  IF tau < t1 { RETURN 0.5 * ASC_CNT_PITCH_ACC * tau * tau. }
  RETURN 0.5 * ASC_CNT_PITCH_ACC * t1 * t1 + wr * (tau - t1).
}

FUNCTION asc_cnt_phi {                   // the roll's angle (deg) at t: ROLL_RATE from its start, at most ROLL_LEAD past
  PARAMETER cn, t, pa.                   // pa, the stack's own (kOS only; the replay: pa large = the offline sim's open loop)
  IF cn["ph"] = "roll" {
    SET cn["phi"] TO MAX(cn["phi"], MIN(MIN(180, ASC_CNT_ROLL_RATE * (t - cn["t_roll"])), pa + ASC_CNT_ROLL_LEAD)).
  }
}

FUNCTION asc_cnt_dir {                   // the thrust direction at t; after the C/O the cut's
  PARAMETER cn, t.
  LOCAL ph IS cn["ph"].
  LOCAL tt IS t.
  IF ph = "cut" {
    SET ph TO cn["ph_cut"].
    SET tt TO cn["t_cut"].
  }
  IF ph = "roll" {
    LOCAL zb IS COS(cn["phi"]) * cn["nb"] + SIN(cn["phi"]) * cn["sb"].
    RETURN (COS(cn["beta"]) * cn["xb"] + SIN(cn["beta"]) * zb):NORMALIZED.
  }
  IF ph = "ppd2" {
    LOCAL ang IS asc_cnt_ppd2_ang(cn, tt).
    LOCAL xb IS COS(ang) * cn["xb"] - SIN(ang) * cn["nb"].
    LOCAL nb IS SIN(ang) * cn["xb"] + COS(ang) * cn["nb"].
    RETURN (COS(ASC_CNT_CANT) * xb - SIN(ASC_CNT_CANT) * nb):NORMALIZED.
  }
  RETURN asc_cnt_gc(cn["u0"], cn["tgt"], ASC_CNT_SLEW * (tt - cn["t0"])).
}

FUNCTION asc_cnt_bx {                    // the body X axis at t
  PARAMETER cn, t, ix, iz.
  IF cn["ph"] = "ppd2" {
    LOCAL ang IS asc_cnt_ppd2_ang(cn, t).
    RETURN COS(ang) * cn["xb"] - SIN(ang) * cn["nb"].
  }
  LOCAL u IS asc_cnt_dir(cn, t).
  LOCAL sg IS 1.
  IF cn["ph"] = "man" OR cn["ph"] = "roll" { SET sg TO -1. }
  RETURN (COS(ASC_CNT_CANT) * u + sg * SIN(ASC_CNT_CANT) * asc_cnt_upn(u, ix, iz)):NORMALIZED.
}

FUNCTION asc_cnt_top {                   // kOS only: the roll attitude, -Zb (the canopy): heads down the ground side of
  PARAMETER cn, u.                       // u, heads up the sky side, mid-roll -zb(phi)
  IF cn["ph"] = "roll" { RETURN -(COS(cn["phi"]) * cn["nb"] + SIN(cn["phi"]) * cn["sb"]). }
  LOCAL n IS asc_cnt_upn(u, cn["ix"], cn["iz"]).
  IF cn["hu"] { RETURN n. }
  RETURN -n.
}

FUNCTION asc_cnt_start {                 // AUTO CONT's first pass + INIT (4.9.10) at t, u the thrust direction now; hu:
  PARAMETER cn, t, u, mode, hu.          // the stack heads up already (kOS only: man + roll skipped)
  SET cn["on"] TO TRUE.
  SET cn["mode"] TO mode.
  SET cn["ph"] TO "man".
  IF hu {
    SET cn["ph"] TO "hold".
    SET cn["hu"] TO TRUE.
  }
  SET cn["t_start"] TO t.
  SET cn["t_next"] TO t + ASC_DTGD.
  SET cn["u0"] TO u.
  SET cn["t0"] TO t.
  SET cn["tgt"] TO u.
}

FUNCTION asc_cnt_rsep {                  // the switch to the rate fast sep at t: the body X from the hold's
  PARAMETER cn, t, ix, iy, iz.           // thrust, the pitch-down from it
  LOCAL xb0 IS asc_cnt_bx(cn, t, ix, iz).
  SET cn["ph"] TO "ppd2".
  SET cn["t_ppd"] TO t.
  SET cn["k_al"] TO 0.
  SET cn["xb"] TO xb0.
  SET cn["nb"] TO asc_cnt_upn(xb0, ix, iz).
  SET cn["sb"] TO iy.
}

// THE MODE-2 HOLD'S PASS IN C#. asc_cnt_m2 is ~1.7-1.9k opcodes a pass in kOS (its loop over the 14 ends of
// ASC_CNT_LAW_ENDS), the contingency's one
// pass over ~1k; with ASC_CNT_CS on and the KAL/S addon's RTM2 (coproc/CntM2.cs, a line-for-line port) the addon computes it
// and kOS writes its result into cn (asc_cnt_m2_kos, the kOS pass, unchanged, does not run). Any addon error turns it off
// for the flight; kOS flies that pass and the rest. Without the addon (or an older KalsCoproc.dll) kOS flies it.
IF NOT (DEFINED ASC_CNT_CS) { GLOBAL ASC_CNT_CS IS TRUE. }
GLOBAL ASC_CNT_CS_ON IS 0.              // the addon looked at: 0 not yet, 1 set up, -1 not there
GLOBAL ASC_CNT_CS_AD IS 0.
GLOBAL ASC_CNT_CS_ERR IS "".
GLOBAL ASC_CNT_CS_N IS 0.

FUNCTION asc_cnt_cs_setup {
  SET ASC_CNT_CS_ON TO -1.
  LOCAL why IS "".
  IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
  ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
  ELSE IF NOT ADDONS:KALS:HASSUFFIX("RTM2") { SET why TO "the KAL/S addon has no 2EO mode 2 hold (an older KalsCoproc.dll)". }
  IF why = "" {
    SET ASC_CNT_CS_AD TO ADDONS:KALS.
    SET ASC_CNT_CS_ON TO 1.
    RETURN.
  }
  SET ASC_CNT_CS_ERR TO why.
}

// the cut law's coefficients and hand-over distance for this contingency (THE RTLS LAW when an RTLS started it)
FUNCTION asc_cnt_lawk {
  PARAMETER cn.
  IF cn["rtls"] { RETURN ASC_CNT_LAW_KR. }
  RETURN ASC_CNT_LAW_K.
}

FUNCTION asc_cnt_lawho {
  PARAMETER cn.
  IF cn["rtls"] { RETURN ASC_CNT_LAW_HOR. }
  RETURN ASC_CNT_LAW_HO.
}

// THE REL GATE: LIST(the ends of cn["eps"] the law judges, their indexes in cn["eps"]): all of them in a
// contingency an RTLS started or with LAW_REL 0, else those within LAW_REL deg of the track (rel as asc_cnt_m2_kos)
FUNCTION asc_cnt_lawe {
  PARAMETER cn, iy, iz.
  LOCAL ps IS LIST().
  LOCAL kx IS LIST().
  LOCAL i IS 0.
  FOR p IN cn["eps"] {
    IF cn["rtls"] OR ASC_CNT_LAW_REL <= 0 OR ABS(ARCTAN2(VDOT(p, iy), VDOT(p, iz))) <= ASC_CNT_LAW_REL {
      ps:ADD(p).
      kx:ADD(i).
    }
    SET i TO i + 1.
  }
  RETURN LIST(ps, kx).
}

FUNCTION asc_cnt_lawek {                 // the gated list's end number k -> its number in cn["eps"] (-1: none)
  PARAMETER eg, k.
  IF k < 0 { RETURN -1. }
  RETURN eg[1][k].
}

// the mode-2 hold at a pass: by C# (RTM2) or kOS (asc_cnt_m2_kos)
FUNCTION asc_cnt_m2 {
  PARAMETER cn, rr, vv, ix, iy, iz.
  IF ASC_CNT_CS {
    IF ASC_CNT_CS_ON = 0 { asc_cnt_cs_setup(). }
    IF ASC_CNT_CS_ON > 0 {
      LOCAL eg IS asc_cnt_lawe(cn, iy, iz).   // THE REL GATE: the ends the law judges (C# gets only those)
      LOCAL cr IS ASC_CNT_CS_AD:RTM2(LIST(rr, vv, ix, iy, iz, cn["acc"], cn["abo"], cn["law_x"], eg[0], ASC_MU, ASC_R,
        ASC_CNT_THETA_MODE2, ASC_CNT_CANT, ASC_CNT_M2_FLAT, ASC_CNT_M2_EGATE, ASC_CNT_M2_EFIX, ASC_CNT_M2_HCAP,
        ASC_CNT_M2_EMIN, ASC_CNT_M2_HT, ASC_CNT_M2_HDMIN, ASC_CNT_M2_KH, ASC_CNT_M2_K, ASC_CNT_LAW, ASC_CNT_LAW_VIPK,
        asc_cnt_lawk(cn), asc_cnt_lawho(cn))).
      IF cr:ISTYPE("List") {
        SET cn["e2"] TO cr[0]. SET cn["th2"] TO cr[1]. SET cn["law_k"] TO asc_cnt_lawek(eg, cr[2]).
        IF cr[3] { SET cn["law_x"] TO cr[4]. SET cn["law_d"] TO cr[5]. SET cn["law_rel"] TO cr[6]. }
        SET ASC_CNT_CS_N TO ASC_CNT_CS_N + 1.
        RETURN cr[7].
      }
      SET ASC_CNT_CS_ERR TO cr.
      SET ASC_CNT_CS TO FALSE.
    }
  }
  RETURN asc_cnt_m2_kos(cn, rr, vv, ix, iy, iz).
}

FUNCTION asc_cnt_m2_kos {                  // the mode-2 hold at a pass (before the contingency's pass):
  PARAMETER cn, rr, vv, ix, iy, iz.      // the thrust's elevation (cn["e2"], cn["th2"] = it + CANT), the cut law's best
  LOCAL hdot IS VDOT(ix, vv).            // end (cn["law_k"], -1 none; its law_x = d - R km, law_d km, law_rel deg);
  LOCAL rm IS rr:MAG.                    // TRUE = the law's C/O. The caller's: cn["acc"] the thrust over the mass now
  LOCAL h IS rm - ASC_R.                 // (m/s2), cn["abo"] the same at the ET's low level, cn["eps"] the ends of
  LOCAL gacc IS ASC_MU / rm ^ 2 - (VDOT(vv, vv) - hdot * hdot) / rm.   // ASC_CNT_LAW_ENDS inertial, as rr
  LOCAL acc IS cn["acc"].
  LOCAL emax IS ASC_CNT_THETA_MODE2 - ASC_CNT_CANT.
  LOCAL el IS emax.                      // the FSSR's while one SSME cannot climb at it
  IF ASC_CNT_M2_FLAT AND acc * SIN(emax) <= gacc AND cn["abo"] * SIN(emax) < ASC_CNT_M2_EGATE * gacc {
    SET el TO ASC_CNT_M2_EFIX.           // the flat thrust: it cannot climb even at the ET's low level
  }
  IF ASC_CNT_M2_HCAP > 0 AND hdot > 0 AND h + hdot * hdot / (2 * MAX(gacc, 0.5)) > ASC_CNT_M2_HCAP {
    SET el TO ASC_CNT_M2_EMIN.           // the cap: the coast alone tops it, all the thrust to speed
  } ELSE IF acc * SIN(emax) > gacc {     // it can climb: HDOT held at the target, the rest of the thrust to speed
    LOCAL ht IS ASC_CNT_M2_HT.
    IF ASC_CNT_M2_HCAP > 0 {
      SET ht TO MAX(ASC_CNT_M2_HDMIN, MIN(ASC_CNT_M2_HT, ASC_CNT_M2_HT - ASC_CNT_M2_KH * (h - ASC_CNT_M2_HCAP))).
    }
    LOCAL s IS (gacc + ASC_CNT_M2_K * (ht - hdot)) / MAX(acc, 0.000001).
    SET el TO ARCSIN(MAX(SIN(ASC_CNT_M2_EMIN), MIN(SIN(emax), s))).
  }
  SET cn["e2"] TO el.
  SET cn["th2"] TO el + ASC_CNT_CANT.
  SET cn["law_k"] TO -1.
  IF NOT ASC_CNT_LAW OR cn["eps"]:LENGTH = 0 { RETURN FALSE. }
  LOCAL k IS asc_cnt_lawk(cn).
  LOCAL vi IS MIN(vv:MAG, ASC_CNT_LAW_VIPK).
  LOCAL g0 IS k[0] + k[1] * vi + k[2] * vi * vi + k[3] * h / 1000 + k[4] * hdot.
  LOCAL i IS 0.
  FOR ps IN cn["eps"] {
    LOCAL rel IS ARCTAN2(VDOT(ps, iy), VDOT(ps, iz)).   // deg: the end's bearing off the ground track, + right
    IF cn["rtls"] OR ASC_CNT_LAW_REL <= 0 OR ABS(rel) <= ASC_CNT_LAW_REL {   // THE REL GATE
      LOCAL d IS ARCTAN2(VCRS(rr, ps):MAG, VDOT(rr, ps)) * ASC_R / 57295.779513082323.   // km: the central angle * R
      LOCAL x IS d - (g0 + k[5] * ABS(rel) + k[6] * rel * rel).
      IF cn["law_k"] < 0 OR x < cn["law_x"] {
        SET cn["law_k"] TO i.
        SET cn["law_x"] TO x.
        SET cn["law_d"] TO d.
        SET cn["law_rel"] TO rel.
      }
    }
    SET i TO i + 1.
  }
  IF cn["law_k"] < 0 { RETURN FALSE. }   // no end within the gate
  RETURN cn["law_x"] <= asc_cnt_lawho(cn).
}

FUNCTION asc_cnt_cycle {                 // one pass at t (with the switch to the rate fast sep): rr, vv inertial,
  PARAMETER cn, t, rr, vv, wv, qq.       // wv relative to the air, qq Pa (the EAS); the C/O sets cn["t_cut"]
  LOCAL fz IS asc_cnt_frame(rr, wv).
  LOCAL ix IS fz[0].
  LOCAL iy IS fz[1].
  LOCAL iz IS fz[2].
  SET cn["ix"] TO ix.
  SET cn["iz"] TO iz.
  LOCAL hdot IS VDOT(ix, vv).
  LOCAL ph0 IS cn["ph"].
  LOCAL yw IS cn["mode"] = 1 AND cn["yaw"] <> 0.   // GREEN's yaw (the contingency's own passes)
  LOCAL m2 IS ASC_CNT_M2H AND cn["mode"] = 2 AND cn["ph"] = "hold".   // the mode-2 hold (before the pass)
  IF m2 AND asc_cnt_m2(cn, rr, vv, ix, iy, iz) {
    IF cn["rtls"] AND rr:MAG - ASC_R > ASC_CNT_LAW_GH AND SQRT(MAX(0, VDOT(wv, wv) - hdot * hdot)) > ASC_CNT_LAW_GV {
      SET cn["law_gated"] TO cn["law_gated"] + 1.   // the load gate holds the C/O (the hold flies on)
    } ELSE {
      asc_cnt_rsep(cn, t, ix, iy, iz).   // the cut law's C/O: the rate fast sep at once
      SET cn["law_cut"] TO t.
    }
  }
  IF cn["mode"] = 1 AND cn["ph"] = "hold" AND ASC_CNT_RATE_SEP AND NOT yw AND hdot < ASC_CNT_HDOT_MODE1_PD {
    asc_cnt_rsep(cn, t, ix, iy, iz).     // the switch to the rate fast sep, before the pass
  }
  IF cn["mode"] = 2 AND cn["ph"] = "hold" AND cn["early_ok"] AND cn["d_site"] >= 0 AND cn["d_site"] <= ASC_CNT_DCO {
    asc_cnt_rsep(cn, t, ix, iy, iz).     // the early C/O near the site (its switch, before the
    SET cn["early"] TO t.                // pass), its own rate fast sep
  }
  LOCAL eas IS SQRT(MAX(2 * qq / 1.225, 0)) / 0.514444.
  LOCAL u_now IS asc_cnt_dir(cn, t).
  LOCAL ca IS ASC_CNT_CANT.
  LOCAL th IS ASC_CNT_THETA_MODE1.
  IF yw { SET th TO ASC_CNT_THETA_MODE1_YAW. }
  ELSE IF cn["mode"] = 2 { SET th TO cn["th2"]. }   // the hold's elevation + CANT (ASC_CNT_THETA_MODE2 without it)
  LOCAL pyw IS 0.                        // deg: the yaw (+ left, - right of the track; the pitch, then the yaw)
  IF yw { SET pyw TO asc_cnt_psi(cn["yaw"]). }
  LOCAL u_hd IS COS(pyw) * (SIN(th + ca) * ix + COS(th + ca) * iz) - SIN(pyw) * iy.
  LOCAL u_hu IS COS(pyw) * (SIN(th - ca) * ix + COS(th - ca) * iz) - SIN(pyw) * iy.
  IF cn["ph"] = "man" {                  // the initial pitch heads down
    IF VDOT(u_now, u_hd) > COS(ASC_CNT_ALIGN_DEG) { SET cn["k_al"] TO cn["k_al"] + 1. }
    IF cn["k_al"] >= ASC_CNT_ROLL_DELAY_PASSES {
      SET cn["ph"] TO "roll".
      SET cn["t_roll"] TO t.
      SET cn["phi"] TO 0.
    } ELSE {
      SET cn["u0"] TO u_now.
      SET cn["t0"] TO t.
      SET cn["tgt"] TO u_hd.
    }
  }
  IF cn["ph"] = "roll" {                 // the roll heads up: the thrust sweeps the cant cone
    IF cn["phi"] >= 180 - 0.000000005 {
      SET cn["ph"] TO "hold".
      SET cn["hu"] TO TRUE.
    } ELSE {
      LOCAL xb0 IS (u_hd + u_hu):NORMALIZED.
      LOCAL nb0 IS (u_hd - u_hu):NORMALIZED.
      SET cn["xb"] TO xb0.
      SET cn["nb"] TO nb0.
      SET cn["sb"] TO VCRS(xb0, nb0).
      SET cn["beta"] TO 0.5 * ARCCOS(MIN(1, MAX(-1, VDOT(u_hd, u_hu)))).
    }
  }
  IF cn["ph"] = "hold" {                 // heads up until the final maneuver
    SET cn["u0"] TO u_now.
    SET cn["t0"] TO t.
    SET cn["tgt"] TO u_hu.
    LOCAL go IS FALSE.
    IF yw { SET go TO hdot < ASC_CNT_HDOT_MODE1_BACK. }
    ELSE IF cn["mode"] = 1 { SET go TO hdot < ASC_CNT_HDOT_MODE1_PD. }
    ELSE { SET go TO eas > ASC_CNT_EAS_PD AND hdot < 0. }
    IF go AND yw {                       // back in plane first (yawback)
      SET cn["ph"] TO "yawback".
      SET cn["t_ppd"] TO t.
      SET cn["k_al"] TO 0.
    } ELSE IF go AND cn["mode"] = 1 AND ASC_CNT_RATE_SEP {
      // the roll ended past apogee in this pass -> the rate fast sep as the switch above, not the alpha sep (offline:
      // a 4 deg/s roll, both out at 82 s: q at the cut 13.5 psf, not 18.3)
      asc_cnt_rsep(cn, t, ix, iy, iz).
    } ELSE IF go AND cn["mode"] = 2 {
      // the rate fast sep from the hold's body X (asc_cnt_rsep). Not the roll's cone axis: a start heads up (hu, every
      // 2EO rolls to heads up at once) never sets it, so it is V(0, 0, 0) and the thrust would point straight down
      asc_cnt_rsep(cn, t, ix, iy, iz).
    } ELSE IF go {
      SET cn["ph"] TO "ppd1".
      SET cn["t_ppd"] TO t.
      SET cn["k_al"] TO 0.
    }
  }
  IF m2 AND cn["ph"] = "hold" AND ASC_CNT_M2_PSI > 0 AND cn["law_k"] >= 0 {   // the mode-2 hold's yaw toward the law's end
    LOCAL ps IS MAX(-ASC_CNT_M2_PSI, MIN(ASC_CNT_M2_PSI, cn["law_rel"])).   // deg, + right of the track (iy)
    LOCAL el IS cn["th2"] - ca.
    SET cn["tgt"] TO SIN(el) * ix + COS(el) * (COS(ps) * iz + SIN(ps) * iy).
  }
  IF cn["ph"] = "yawback" {              // back to the current plane (yawback, PD_DELAY_COUNTER)
    LOCAL tgy IS SIN(th - ca) * ix + COS(th - ca) * iz.
    IF VDOT(u_now, tgy) > COS(ASC_CNT_ALIGN_DEG) { SET cn["k_al"] TO cn["k_al"] + 1. }
    IF cn["k_al"] >= ASC_CNT_ROLL_DELAY_PASSES {
      SET cn["ph"] TO "ppd1".
    } ELSE {
      SET cn["u0"] TO u_now.
      SET cn["t0"] TO t.
      SET cn["tgt"] TO tgy.
    }
  }
  IF cn["ph"] = "ppd1" {                 // the alpha fast sep: to ALPHA_PPD; C/O there
    LOCAL w IS wv:NORMALIZED.
    LOCAL nw IS asc_cnt_upn(w, ix, iz).
    LOCAL al IS ASC_CNT_ALPHA_PPD.
    LOCAL xb1 IS COS(al) * w + SIN(al) * nw.
    LOCAL nb1 IS -SIN(al) * w + COS(al) * nw.
    LOCAL tg IS (COS(ca) * xb1 - SIN(ca) * nb1):NORMALIZED.
    SET cn["u0"] TO u_now.
    SET cn["t0"] TO t.
    SET cn["tgt"] TO tg.
    IF VDOT(u_now, tg) > COS(ASC_CNT_DALF_PPD) { asc_cnt_cut(cn, t, wv, ix, iz, 0). }
  } ELSE IF cn["ph"] = "ppd2" {          // the rate fast sep: C/O once the rate is built up
    LOCAL rt IS MIN(ABS(ASC_CNT_HIGH_SEP_RATE), ASC_CNT_PITCH_ACC * (t - cn["t_ppd"])).
    IF rt >= ABS(ASC_CNT_QMECO_HIGH) - 0.000000001 { asc_cnt_cut(cn, t, wv, ix, iz, ASC_CNT_HIGH_SEP_RATE). }
  }
  IF ph0 = "yawback" AND cn["ph"] = "ppd1" AND ASC_CNT_RATE_SEP {
    asc_cnt_rsep(cn, t, ix, iy, iz).     // back in plane -> the rate fast sep, not the alpha sep
  }
}

FUNCTION asc_cnt_tsep {                  // s: MECO to the ET separation: ASC_CNT_T_SEP_RATE after the rate sep (a
  PARAMETER cn.                          // pitch rate at the cut), else the fast sep's ASC_CNT_T_SEP_FAST
  IF cn["rate"] < 0 { RETURN ASC_CNT_T_SEP_RATE. }
  RETURN ASC_CNT_T_SEP_FAST.
}
FUNCTION asc_cnt_cut {                   // the C/O at t: the alpha (deg, in the vertical plane), the
  PARAMETER cn, t, wv, ix, iz, rt.       // rate (deg/s)
  LOCAL xb IS asc_cnt_bx(cn, t, ix, iz).
  LOCAL w IS wv:NORMALIZED.
  LOCAL nw IS asc_cnt_upn(w, ix, iz).
  SET cn["alpha"] TO ARCTAN2(VDOT(xb, nw), VDOT(xb, w)).
  SET cn["rate"] TO rt.
  SET cn["ph_cut"] TO cn["ph"].
  SET cn["ph"] TO "cut".
  SET cn["t_cut"] TO t.
}

// ==== THE DROOP: FSSR 4.3.4 SECOND STAGE DROOP CONTROL TASK (DRP CTL TSK; STS 83-0002-34: the text at
// refs/txt/fssr_asc.txt line 4945, the flow diagrams A4.3.4.(1)-(9) at line 30190), a port of the offline sim's droop
// (its droop and predict): the same I-loads, flags, formulas and order, in PEG's inertial frame. ops1q runs
// asc_drp_pass after each PEG pass in stage 2 (not in an RTLS or the contingency,
// whose passes are their own) and steers by its command while cmd_on:
//   subtask 1: the state in PEG's plane (IR up, IZ the horizontal of PEG's thrust, IY across);
//   subtask 2: with one SSME left (N_SSME < DRP_NSSME) the minimum altitude predicted for the actual thrust at the
//     droop attitude THR_ATT (THRESH_ATT while the task does not steer); below MIN_DROOP_ALT the task engages
//     (S_CDROOP): THR_ATT goes to THR_MAX, and once the floor is held there (S_DRP_EARLY) the task steers from
//     THR_MIN, ATT_INCR a pass, to hold the predicted minimum just above MIN_DROOP_ALT (deadband ALT_DBND ATT_INCR);
//     PEG steers again at the minimum (T1NEW <= 0) or once PEG converges below THR_ATT with the minimum ALT_PEG_LOSS
//     T1NEW above the floor (S_MIN_ALT, latched);
//   subtask 4: the hypothetical single-engine droop altitude (one SSME at THR_MAX) while the task does not steer;
//   subtask 5: PRED_DROOP_ALT, TRAJ 2's DROOP row (lib_ascdisp);
//   subtask 6: the predictor (Newton-Raphson on the closed-form vertical velocity: a constant thrust attitude, a
//     linear mass, constant gravity less the centrifugal term of the growing horizontal speed).
// kOS ONLY: subtask 4 at the abort throttle ASC_KMAX_ABORT (a 2EO throttles up by itself) where the FSSR assumes
// the current thrust (its crew throttles up by hand, SCOM 6.4), and with the TAL's OMS dump (ASC_DRP_HYP_OMS: its
// thrust and flow averaged over the time to the low point, as subtask 2 averages the dump's rest; ko[2], ko[3] the
// dump's start and burn time from now) where the FSSR counts the SSME alone: on the offline sim's 2EO TALs (both out,
// the dump 2.5 t) the FSSR's hypothetical crosses the floor about 5 s after the true
// boundary, this one about 0.4 s before it; from it the VI from which a 2EO holds the floor (vi_b: the crossing once
// above, latched; below, this VI plus the rest at the rate since the last pass), which bounds the 2EO marks
// (lib_ascent_abr: no 2EO TAL / ATO / PRESS before it). NOT PORTED: S_MODE_2 (this vehicle's contingency replaces the
// droop), the low-energy TAL targets (S_DROOP_TARGETS: the offline sim logs the flag only), ALT_DBND's calibration.
// the I-loads (FSSR 4.3.5 lists the names only): this vehicle's (the offline sim's, measured there)
GLOBAL ASC_DRP_MIN_ALT IS 67000.0.       // m: the real 265,000 ft (ET heating, SCOM 6.2) at the same air density here
GLOBAL ASC_DRP_THR_MAX IS 60.0.          // deg: SCOM 6.4 "Droop guidance will engage and pitch up to 60 deg on the ADI"
GLOBAL ASC_DRP_THR_MIN IS 40.0.          // deg (offline: 10 took over from a PEG that held the floor itself)
GLOBAL ASC_DRP_THRESH_ATT IS 40.0.       // deg (the same)
GLOBAL ASC_DRP_ATT_INCR IS 2.0.          // deg a pass
GLOBAL ASC_DRP_ALT_DBND IS 60000.0.      // m/rad (x ATT_INCR = the deadband; the scan v2's dh/dtheta median 28, p95 94)
GLOBAL ASC_DRP_ALT_PEG_LOSS IS 2500.0.   // m/s (offline: 20 and 2500 the same boundaries)
GLOBAL ASC_DRP_VMISS IS 0.3.             // m/s (1 ft/s)
GLOBAL ASC_DRP_PASS_MAX IS 20.
GLOBAL ASC_DRP_NSSME IS 2.               // the task steers with fewer SSMEs running than this
GLOBAL ASC_DRP_ENA IS FALSE.             // the crew's enable for N_SSME < 3
GLOBAL ASC_DRP_ON IS TRUE.               // kOS: FALSE = no droop task at all (no steering, no DROOP row)
GLOBAL ASC_DRP_HYP_OMS IS TRUE.          // kOS: subtask 4 with the TAL's OMS dump (FALSE: the FSSR's SSME alone)

FUNCTION asc_drp_new {
  RETURN LEXICON("T1NEW", 0, "T2NEW", 1000, "S_MIN_ALT", FALSE, "S_DRP_EARLY", FALSE, "S_CDROOP", FALSE,
    "S_DRP_FLASH", FALSE, "S_DRP_LATCH", FALSE, "PRED", 0, "THR_ATT", ASC_DRP_THRESH_ATT, "cmd", V(0, 0, 0),
    "cmd_on", FALSE, "t_prev", -1, "t_on", -1, "t_cmd", -1, "ok", FALSE, "rout", 0, "peg_att", 0, "hyp", 0,
    "hv", LIST(), "above", FALSE, "vi_b", -1).
}

// subtask 6, the droop predictor: LIST(ROUT m, TNEW s, found, in range); ROUT -1E12 without one
FUNCTION asc_drp_pred {
  PARAMETER M, TV_VERT, TV_HORIZ, GACC, MDT, VGDIY, TMMAX, VGDIX, VGDIZ, RINIT, TNEW, GE, ALT_GD.
  IF GACC <= 0 { RETURN LIST(ALT_GD, 0, TRUE, FALSE). }   // the horizontal speed holds the stack up: no droop ahead
  LOCAL found IS FALSE.
  LOCAL inr IS TRUE.
  LOCAL TMMIN IS MAX(0, MIN((M - TV_VERT / GACC) / MDT, TMMAX - 10)).
  LOCAL XK1 IS GACC - 2 * VGDIZ * TV_HORIZ / (RINIT * MDT) - 2 * TV_HORIZ ^ 2 / (RINIT * MDT ^ 2).
  LOCAL XK3 IS TV_HORIZ ^ 2 * M / (RINIT * MDT ^ 3).
  LOCAL XK2 IS 2 * VGDIZ * TV_HORIZ * M / (RINIT * MDT ^ 2) + 2 * XK3.
  LOCAL XK4 IS (XK2 + XK3) / 2.
  LOCAL TVAL IS 1.
  LOCAL LNV IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= ASC_DRP_PASS_MAX STEP { SET i TO i + 1. } DO {
    SET TNEW TO MAX(TMMIN, MIN(TNEW, TMMAX)).
    SET TVAL TO 1 - MDT * TNEW / M.
    SET LNV TO LN(TVAL).
    LOCAL VGRAV IS XK1 * TNEW - TVAL * LNV * (XK2 - XK3 * LNV).
    LOCAL VOUT IS VGDIX - (TV_VERT / MDT) * LNV - VGRAV.
    IF ABS(VOUT) <= ASC_DRP_VMISS { SET found TO TRUE. BREAK. }
    LOCAL AGRAV IS GE - (VGDIZ - (TV_HORIZ / MDT) * LNV) ^ 2 / RINIT - VGDIY ^ 2 / RINIT.
    LOCAL VDT IS TV_VERT / (M * TVAL) - AGRAV.
    LOCAL TNEXT IS TNEW - VOUT / VDT.
    IF TNEW = TMMIN AND TNEXT < TMMIN { SET inr TO FALSE. SET found TO TRUE. BREAK. }
    IF TNEW = TMMAX AND TNEXT > TMMAX { SET found TO TRUE. BREAK. }
    SET TNEW TO TNEXT.
  }
  IF NOT found { RETURN LIST(-1E12, TNEW, FALSE, inr). }
  SET TVAL TO 1 - MDT * TNEW / M.
  SET LNV TO LN(TVAL).
  LOCAL XK5 IS TNEW - MDT * TNEW ^ 2 / (2 * M) - M / (2 * MDT).
  LOCAL RGRAV IS LNV ^ 2 * XK3 * XK5 - 2 * LNV * XK4 * XK5 + XK4 * TNEW + (TNEW ^ 2 / 2) * (XK1 - MDT * XK4 / M).
  RETURN LIST(ALT_GD + VGDIX * TNEW + TV_VERT * TNEW / MDT + (M / MDT - TNEW) * (TV_VERT / MDT) * LNV - RGRAV, TNEW,
    TRUE, inr).
}

// subtasks 1-5 after a PEG pass at MET t: D asc_drp_new's state, p PEG's; rr, vv PEG's
// inertial (m, m/s); M t; VEX m/s and FT_S kN the engines' at K_CMD (PEG's ATR M / FT_FACTOR: the OMS dump's in);
// FTSS kN the SSMEs' alone at K_CMD; FS1 kN one SSME at 100 % PL, VS1 m/s the SSMEs' exhaust speed (at this pressure);
// MLL t the mass at the ET's low level; n the SSMEs running; ko LIST(the OMS dump on, s of it left; for subtask 4
// the s until the dump a TAL burns (on: 0; selected; a 2EO's own) and its s of burn from then)
FUNCTION asc_drp_pass {
  PARAMETER D, p, t, rr, vv, M, VEX, FT_S, FTSS, FS1, VS1, MLL, n, ko.
  LOCAL dtgd IS ASC_DTGD.
  IF D["t_prev"] >= 0 { SET dtgd TO t - D["t_prev"]. }
  SET D["t_prev"] TO t.
  IF D["S_MIN_ALT"] { SET D["cmd_on"] TO FALSE. RETURN. }
  LOCAL HMIN IS ASC_DRP_MIN_ALT.
  // ---- subtask 1: the state
  LOCAL RINIT IS rr:MAG.
  LOCAL IR IS rr:NORMALIZED.
  LOCAL IY IS VCRS(p["lamc"], IR):NORMALIZED.
  LOCAL IZ IS VCRS(IR, IY).
  LOCAL PEG_CMD IS (p["lamc"] + (t - p["tlamc"]) * p["lamdc"]):NORMALIZED.
  LOCAL PEG_ATT IS 90 - ARCCOS(MAX(-1, MIN(1, VDOT(PEG_CMD, IR)))).
  LOCAL VX IS VDOT(vv, IR).
  LOCAL VY IS VDOT(vv, IY).
  LOCAL VZ IS VDOT(vv, IZ).
  LOCAL GE IS p["mu"] / RINIT ^ 2.
  LOCAL GACC IS GE - (VY ^ 2 + VZ ^ 2) / RINIT.
  LOCAL TNEW IS D["T1NEW"] - dtgd.
  LOCAL TV_MAX IS FT_S.
  LOCAL MDT IS FT_S / VEX.
  IF NOT D["S_CDROOP"] { SET D["THR_ATT"] TO ASC_DRP_THRESH_ATT. }
  ELSE IF ko[0] AND TNEW > 0 {              // the OMS dump's share of the thrust until it stops
    LOCAL fon IS MIN(1, ko[1] / TNEW).
    SET TV_MAX TO FT_S * fon + FTSS * (1 - fon).
    SET MDT TO TV_MAX / (VEX * fon + VS1 * (1 - fon)).
  }
  LOCAL TMMAX IS (M - MLL) / MDT.
  // ---- subtask 2: the control determination
  LOCAL pr IS asc_drp_pred(M, TV_MAX * SIN(D["THR_ATT"]), TV_MAX * COS(D["THR_ATT"]), GACC, MDT, VY, TMMAX, VX, VZ,
    RINIT, TNEW, GE, RINIT - ASC_R).
  LOCAL ROUT IS pr[0].
  LOCAL found IS pr[2].
  SET D["rout"] TO ROUT.
  SET D["peg_att"] TO PEG_ATT.
  IF found {
    SET D["T1NEW"] TO pr[1].
    SET D["S_DRP_FLASH"] TO FALSE.
    LOCAL S_ATT_CMD IS ROUT < HMIN AND pr[3].
    LOCAL S_PEG_OK IS (NOT p["low_tw"]) AND p["SCONV"] AND PEG_ATT < D["THR_ATT"].
    SET D["S_MIN_ALT"] TO D["S_CDROOP"] AND (D["T1NEW"] <= 0
      OR (S_PEG_OK AND ROUT > HMIN + ASC_DRP_ALT_PEG_LOSS * D["T1NEW"])).
    SET D["S_CDROOP"] TO (NOT D["S_MIN_ALT"]) AND (S_ATT_CMD OR D["S_CDROOP"])
      AND (n < ASC_DRP_NSSME OR (n < 3 AND ASC_DRP_ENA)).
  } ELSE {
    SET D["S_CDROOP"] TO FALSE.
    SET D["S_DRP_FLASH"] TO TRUE.
  }
  // ---- subtask 3: the steering parameters
  IF D["S_CDROOP"] {
    IF D["t_on"] < 0 { SET D["t_on"] TO t. }
    SET D["S_DRP_LATCH"] TO TRUE.
    IF ROUT < HMIN { SET D["THR_ATT"] TO D["THR_ATT"] + ASC_DRP_ATT_INCR. }
    ELSE IF ROUT > HMIN + ASC_DRP_ALT_DBND * ASC_DRP_ATT_INCR * 3.141592653589793 / 180 {
      SET D["THR_ATT"] TO D["THR_ATT"] - ASC_DRP_ATT_INCR.
    }
    SET D["THR_ATT"] TO MAX(ASC_DRP_THR_MIN, MIN(D["THR_ATT"], ASC_DRP_THR_MAX)).
    IF NOT D["S_DRP_EARLY"] {
      SET D["THR_ATT"] TO ASC_DRP_THR_MAX.
      IF ROUT > HMIN {
        SET D["S_DRP_EARLY"] TO TRUE.
        SET D["THR_ATT"] TO ASC_DRP_THR_MIN.
      }
    }
    IF D["S_DRP_EARLY"] {
      SET D["cmd"] TO (SIN(D["THR_ATT"]) * IR + COS(D["THR_ATT"]) * IZ):NORMALIZED.
      SET D["cmd_on"] TO TRUE.
      IF D["t_cmd"] < 0 { SET D["t_cmd"] TO t. }
    }
    IF ROUT < HMIN { SET D["S_DRP_FLASH"] TO TRUE. }
  } ELSE {
    SET D["cmd_on"] TO FALSE.
  }
  // ---- subtask 4: the hypothetical single-engine droop (kOS: at the abort throttle, with the TAL's OMS dump)
  IF NOT D["S_CDROOP"] AND NOT D["S_MIN_ALT"] {
    LOCAL TV1 IS FS1 * ASC_KMAX_ABORT / 100.
    LOCAL MD1 IS TV1 / VS1.
    IF ASC_DRP_HYP_OMS AND ko[3] > 0 AND D["T2NEW"] > 0 {
      LOCAL MDO IS ASC_OMS_F / (ASC_OMS_ISP * 9.80665).
      LOCAL fon IS MAX(0, MIN(D["T2NEW"], ko[2] + ko[3]) - ko[2]) / D["T2NEW"].
      SET TV1 TO TV1 + fon * ASC_OMS_F.
      SET MD1 TO MD1 + fon * MDO.
    }
    LOCAL ph IS asc_drp_pred(M, SIN(ASC_DRP_THR_MAX) * TV1, COS(ASC_DRP_THR_MAX) * TV1, GACC, MD1, VY, (M - MLL) / MD1,
      VX, VZ, RINIT, D["T2NEW"], GE, RINIT - ASC_R).
    SET ROUT TO ph[0].
    SET D["T2NEW"] TO ph[1].
    SET found TO ph[2].
    SET D["hyp"] TO ROUT.
    // kOS: the VI from which a 2EO holds the floor (lib_ascent_abr's 2EO marks)
    IF found {
      LOCAL vi IS vv:MAG.
      LOCAL hv IS D["hv"].
      IF ROUT >= HMIN {
        IF NOT D["above"] {
          SET D["vi_b"] TO 0.
          IF hv:LENGTH = 2 { IF hv[1] < HMIN AND vi > hv[0] {
            SET D["vi_b"] TO hv[0] + (HMIN - hv[1]) / (ROUT - hv[1]) * (vi - hv[0]).
          } }
          SET D["above"] TO TRUE.
        }
      } ELSE {
        SET D["above"] TO FALSE.
        SET D["vi_b"] TO 100000.
        IF hv:LENGTH = 2 { IF vi > hv[0] AND ROUT > hv[1] {
          SET D["vi_b"] TO vi + (HMIN - ROUT) * (vi - hv[0]) / (ROUT - hv[1]).
        } }
      }
      SET D["hv"] TO LIST(vi, ROUT).
    }
  }
  // ---- subtask 5: the display
  IF found {
    IF D["S_DRP_LATCH"] AND ROUT > HMIN { SET D["PRED"] TO MAX(HMIN, ROUT - ASC_DRP_ALT_PEG_LOSS * D["T1NEW"]). }
    ELSE { SET D["PRED"] TO MAX(ROUT, 0). }
  } ELSE {
    SET D["PRED"] TO 0.
  }
  SET D["ok"] TO TRUE.
}
