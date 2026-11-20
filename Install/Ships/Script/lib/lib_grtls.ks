@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_GRTLS.KS  --  THE RTLS GLIDE: GRTLS (FSSR STS 83-0001-34 4.8, THE INTACT PATH) FOR OPS 6's RTLS
// ============================================================================
//  From the ET separation: PHASE 6 the alpha recovery (alpha ALPREC, wings level; HDMAX = the deepest sink ->
//  DGRNZ), PHASE 5 the Nz hold (NZC = GRNZC1 - SMNZ1 - SMNZ2 + DGRNZ, incremental; ends when HDOT > HDTRN and
//  ALPHA > GRALPR), PHASE 4 the alpha transition to GRALPR (GRALL / GRALU a cycle) with TAEM's HAC geometry (taemg_gtp /
//  taemg_init / taemg_comp) and its bank GPHI * DPSAC (or an S-turn at PHILM1), then TAEM (landRun) below Mach MSW1.
//  The FSSR prints NO value for any GRTLS I-load (MX / SX): the values are this vehicle's, from the offline model's
//  I-loads (an offline python model of this guidance, flown on this vehicle).
//  The deviations from the FSSR:
//   (1) the aero = entry_predict's model (eprCla / eprCdaEntry, x EPR_MASS_K: the vehicle's own mass here, where the
//       offline model flew the reference mass) x GR_AERO_FIX (the GRTLS's measured lift and drag); the speedbrake = the
//       entry's schedule (ops6q's entrySbUpdate), not GRSBC;
//   (2) the Nz hold flies ALPHA: the alpha whose model Nz (body normal: L cos a + D sin a) is NZC + COS(gamma) /
//       COS(bank), by bisection each pass (the real DAP closes on the accelerometers); the 6 -> 5 switch reads the
//       model's Nz at the measured alpha; the alpha command slewed at GR_ALPHA_RATE;
//   (3) THE HOLD GUARD: the Nz hold also ends when the sink reverses (HDOT > 0) -- the FSSR's end needs
//       ALPHA > GRALPR too, and a low hold target lets alpha fall under GRALPR first (a zoom); THE HOLD'S ARM: no exit
//       of the hold before its Nz has passed NZSW1 + DGRNZ (GR_HOLD_ARM; after the alpha trap);
//   (4) the bank = ops6q's entry slew (BANK_RATE 5 deg/s, BANK_ACCEL_MAX 4); TAEM starts in its phase 1 (landRun).
//  THE CHECK: the guidance functions (grtlsNzAt .. grtlsFcsK) translate mechanically to python; flown on the offline
//  model's vehicle they give the same phases, commands and events as the offline model's own guidance.
//  Signs: the ship's bank + = LEFT (bankNow); G4.9's PHIC + = RIGHT (taemg_bank_to_ship / taemg_ship_to_bank).
//  CONT (SCOM 6.7: the 2EO BLUE and the ECAL / BDA guidance): grtlsContSet(1 | 2) before
//  grtlsStart flies a 2EO contingency on the same phases: the Nz target -HDMAX/1000 + 0.65 g (1.2 .. 3.9) through DGRNZ,
//  the hold from 0.4 g below it, the recovery + hold alpha by Mach (MIDVAL(ALPRS M + ALPRI, ALPRL, ALPREC)); GREEN (1):
//  the bank toward the site from the Nz hold on (<= PHILM_E 70; the Nz kept <= NZMAX and <= NZAVF x the alpha cap's),
//  phase 4's roll limit PHILM_E, BLUE when TAEM's EOW - EN < DEOW_REACH at phase 4's start (OPS 6's reach check);
//  BLUE (2): wings level, no TAEM, below BAIL_MACH (any phase) the bailout hold, iphase 7 (FSSR TGNZC eqs 2.2 + 3.6-3.7
//  in form: the Nz command from the q-bar error to BAIL_KEAS; ops6q closes the speedbrake: TGSBC's DSBC = 0). The
//  deviations from the FSSR: the hold flies to BAIL_KEAS (the real crew sets 185-195 KEAS, then the guidance snaps it);
//  the hold ends above HDTRN -320 ft/s as the RTLS (SCOM 6.7 says Hdot > 0: never reached at low energy). The values:
//  the offline model's CONT I-loads.
//  SPLITS (A DEVIATION from the FSSR: the 1987 scheme of AIAA 87-2398, never certified, flown here after a 2EO / 3EO
//  in stage 1; the ascent flies the loft and the separation, then ops6q):
//  ssSet before grtlsStart flies the split-S's second half on the GRTLS's phases. PHASE 8 (from ops6q's first lock, at
//  the alpha as found): heads down in the vertical plane of SS_AZ0 (the lift toward the canopy: toward the ground while
//  the path is above straight down; ssSteer, not the bank formulation), the alpha whose model Nz (body normal) is SS_NZ,
//  at most SS_ALPHA; past straight down + SS_SW_DEG the vehicle is heads up: PHASE 5 from the bank whose lift points
//  the same way (ops6q takes it into bankNow and the steering back to entrySteer), SS_NZ held (the total, not the FSSR's
//  NZC + cos(gamma) / cos(phi)), wings level, to the RTLS's phase-5 end; PHASE 4 and TAEM as the RTLS, the runway END
//  AND THE HAC SIDE picked at phase 4's start (ssPick: of the 4 pairs the EOW - EN nearest TAEM's corridor EN - 914 ..
//  EN + 1829 m, inside it the highest; the overhead rule alone lands about half: its HAC costs ~10 km on a split-S
//  arrival); the side flown by phase 4 (GR["ysgn"]) and by landRun (TG_OVERHEAD_DEFAULT set so its rule gives it; ops6q
//  restores SS_OVH0 after landRun). Phase 4 ends at alpha <= GR_AMAXLD as well as Mach < MSW1, wings level until then
//  (a split-S is subsonic at phase 4's start, near SS_ALPHA: TAEM's first bank comes after the alpha transition, as in
//  the RTLS). The Nz model's drag: the speedbrake closed (eprCda x (1 + eprCdFix)), which ops6q
//  keeps so to TAEM. The law and the pick: the offline split-S model's (the speedbrake closed, the turn plane at the
//  local azimuth).
//  BLUE TOWARD THE COAST (A DEVIATION from the FSSR, which has none: the bailout as close to shore as possible while
//  still over water; the reach test first, then the crew's choice): every BLUE (a CONT BLUE
//  from the start, a GREEN out of reach, an RTLS the crew or the default turned BLUE: grtlsBluePick, applied at the top
//  of the next cycle with the CONT I-loads grtlsContSet(2), the alpha trap off) banks in phases 5 / 4 / 7 toward a line
//  GR_BLUE_DOFF off the nearest coast (grtlsShoreHdg: every CST_TSEL s the nearest segment of the coast table
//  grtls_bg/coast_blue.txt, Sol's ocean coast traced from its biome map, and TERRAINHEIGHT < 0 for at sea; the lean off
//  the coast's direction CST_KL x (the distance - DOFF at sea, + DOFF inland) / the turn radius at GR_BLUE_PHILM,
//  straight for the coast at 90 deg or more), the bank GPHI x the heading error, <= GR_BLUE_PHILM, none at or below the
//  flight path GR_BLUE_GAM4 (full from GAM4 + GAMW up: a steep dive's pull-out wings level) or under the q GR_BLUE_QB, in
//  phase 5 the total Nz kept as GREEN's; GRALPR without 1 / cos(bank) for a BLUE (GR_BLUE_NOCOS); the bailout hold only
//  with the q GR_BAIL_QMIN (not engaged subsonic in vacuum). No table (not loaded / off it): wings level.
//  The offline model's numbers: Nz <= 3.82 g; the bailout band reached at sea in 318 of 321 flights, 166 of them
//  ending 0-7 km off the coast; the coast table 261008 points.
//  The coast table and the heading toward the coast are lib_coast's (cstLoad / cstNear / cstSeg / cstShoreHdg / cstTrk,
//  and its cstMid / cstRes180 for the guidance's MIDVAL / the +-180 wrap): one copy; GR carries the search's state
//  (sh_t, sh, sh_side) into cstShoreHdg; GR_COAST is CST (one table, lib_land's bailout reads it too); GR_BLUE_DOFF /
//  _PHILM are CST_DOFF / CST_PHILM (the same numbers).
//  THE ECAL LOGIC IN A GREEN (CONT 1, GR_ECAL), FSSR STS 83-0001-34 4.8 TGCOMP 2.1.1, GRTRN 3.3.1-3.3.13 + 4.1, GRALPC
//  3.4 / 4.1, GRPHIC 1.2 / 1.3.B / 1.3.2: one rule set for both inclinations; the I-loads' block below says what each
//  does and where it deviates from the FSSR.
// ============================================================================

RUNONCEPATH("0:/lib/entry_predict.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/taemg_const.ksm" IF O6_KSM_GO ELSE "0:/lib/taemg_const.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/taemg_const.ks").
RUNONCEPATH(CHOOSE (CHOOSE "0:/ksm/lib/lib_coast.ksm" IF O6_KSM_GO ELSE "0:/lib/lib_coast.ks") IF (DEFINED O6_KSM_GO) ELSE "0:/lib/lib_coast.ks").   // the coast table + heading, cstMid / cstRes180
RUNONCEPATH("0:/lib/lib_far.ks").             // FAR_ON (GR_AERO_FIX_ON)

// ---- the I-loads (this vehicle's, the FSSR prints none: the offline model's I-loads)
GLOBAL GR_DTG IS 0.96.              // s: the guidance cycle (the FSSR's)
GLOBAL GR_ALPREC IS 50.0.           // deg: phase 6 alpha (SCOM 6.3)
GLOBAL GR_GRNZC1 IS 1.2.            // g incremental: the hold's target, 2.2 g total (SCOM 6.3)
GLOBAL GR_SMNZC1 IS 0.4.            // g: the lead term's start ..
GLOBAL GR_SMNZC3 IS 0.9.            //   .. decaying 10 % a cycle
GLOBAL GR_SMNZC2 IS 0.2.            // g: the ramp term's start ..
GLOBAL GR_SMNZC4 IS 0.02.           //   .. down 0.02 g a cycle ..
GLOBAL GR_SMNZ2L IS 0.0.            //   .. to 0
GLOBAL GR_NZSW1 IS GR_GRNZC1 + 1.0 - GR_SMNZC1 - GR_SMNZC2.   // g total: phase 5's first command (no step)
GLOBAL GR_HDNOM IS -1700.0.         // ft/s: the nominal deepest sink (the offline model's three cases)
GLOBAL GR_DHDNZ IS 0.001.           // g per ft/s
GLOBAL GR_DHDLL IS -0.2.            // g: the total target 2.0 ..
GLOBAL GR_DHDUL IS 0.3.             //   .. 2.5 g
GLOBAL GR_HDTRN IS -320.0.          // ft/s: the hold ends above this sink (SCOM 6.3)
GLOBAL GR_MSW1 IS 2.5.              // Mach: the switch to TAEM (this vehicle's TAEM interface: 762 m/s at 25 km)
GLOBAL GR_GRALPS IS (EPR_AOA_HIGH - EPR_AOA_LOW) / (EPR_AOA_HIGH_SPEED - EPR_AOA_LOW_SPEED) * (EPR_TAEM_VEL / GR_MSW1).
GLOBAL GR_GRALPI IS EPR_AOA_LOW - GR_GRALPS * GR_MSW1.          // the alpha line = the entry schedule in Mach ..
GLOBAL GR_GRALPL IS EPR_AOA_LOW.    //   .. 15 ..
GLOBAL GR_GRALPU IS EPR_AOA_HIGH.   //   .. 40 deg
GLOBAL GR_AMAXLD IS 30.0.           // deg: GRALPR's cap in a bank
GLOBAL GR_GRALL IS -1.92.           // deg a cycle: the alpha transition (2 deg/s)
GLOBAL GR_GRALU IS 1.92.
GLOBAL GR_GPHI IS TG_GPHI.          // deg / deg: TAEM's own (2.5)
GLOBAL GR_PHILM1 IS 45.0.           // deg: phase 4's roll limit (SCOM 6.3)
GLOBAL GR_MSW3 IS 3.0.              // Mach: phase 4's S-turn below this
GLOBAL GR_PSSTRN IS 325.0.          // deg: the GRTLS's own S-turn gate (TAEM's TG_PSSTRN went 325 -> 350, this stays 325)
GLOBAL GR_ALP_TRAP_ARM IS 45.0.     // deg: the alpha trap arms ..
GLOBAL GR_ALP_TRAP_TRIG IS 40.0.    //   .. and fires on a 10 deg drop
GLOBAL GR_HOLD_GUARD IS TRUE.       // the hold guard, a deviation (header (3))
// THE HOLD'S ARM (a deviation from the FSSR): phase 5's exits (the FSSR's HDTRN, the hold guard, ECAL's GRTRN 4.1)
// wait until the Nz has once passed NZSW1 + DGRNZ, the FSSR's own phase 6 -> 5 test. Entered by Nz the hold is armed at
// once; entered by the alpha trap (a deviation) it is armed once the load has built. The case: after a slow, low CONT
// MECO (below Mach 3.5 ALPREC is under 40, so the slew down from the MECO's alpha fires the trap) the unarmed hold ended
// a second later, the sink still above HDTRN / HDTRNA, and phase 4 dived at alpha 30 and up to 70 deg of bank: q 33 kPa
// (690 psf) unarmed, 11 kPa armed, Nz 3.9-4.0 in the hold as the nominal. FALSE: the exits do not wait.
GLOBAL GR_HOLD_ARM IS TRUE.
// THE GRTLS IN VACUUM: after a high contingency MECO (a 133 km hand-off) the phases would step 6 -> 5 -> 4 -> TAEM above
// the air: the Mach there is vrel / the speed of sound at the highest altitude with pressure (grtlsSosTop; eprMach is 0
// where KSP's pressure is 0), and phase 6's alpha trap and phase 5's two exits (the FSSR's, the hold guard) act only
// with the q GR_PH_QMIN (a deviation: the FSSR enters the GRTLS in the air; there the q is far above it). Phase 6 -> 5
// by Nz needs the air by itself.
GLOBAL GR_PH_QMIN IS 50.0.          // Pa (~1 psf): the phase steps above (in vacuum the q is ~0)
GLOBAL GR_SOS_TOP IS -1.            // m/s: grtlsSosTop's (found once)
GLOBAL GR_ALPHA_RATE IS 5.0.        // deg/s: the alpha command's slew (the offline model's FCS)
GLOBAL GR_ALPHA_NZ_LO IS 5.0.       // deg: the Nz bisection's floor
GLOBAL GR_NZ_ITERS IS 30.           // the bisection's halvings (the offline model's)
// THE SENSED NZ: the guidance's Nz (the phase 6 -> 5 switch, the hold's arming, ECAL's relay and IPPRTF, VERT SIT) is
// the measured body-normal load factor: the GRTLS DAP's grdNzM (the HUD's, the sensed acceleration along the top), the
// finite-difference lift and drag without the DAP. The model's Nz (the alpha the hold flies, ECAL's alpha limits, the
// HUD's Nz slope) is scaled by GR_NZK, the measured / model ratio filtered over GR_NZK_TAU while the model reads at least
// GR_NZK_MIN: the Nz loop closes on the measured load. Unscaled, the model read 7 % over the flown Nz in the hold (up to
// 0.5 g) and the hold flew under its target. FALSE = the model's Nz throughout.
// THE GRTLS's AERO, MEASURED IN FLIGHT: along the RTLS glide the entry polar reads high, most at the recovery's alpha
// (13 intact stock RTLS: flown / polar lift 0.92-0.95 and drag 0.85-0.88 at alpha 20-40, the same at Mach 2-4). The 45 / 50
// knots are refitted on the flown fd lift / drag of 19 stock RTLS / GREEN logs (10-23 .. 11-03, no OMS thrust, the flown
// mass): flown / polar lift 0.881 / 0.824, drag 0.789 / 0.729 at alpha 45 / 50 (the 13 RTLS' 0.80 / 0.76 and 0.75 / 0.66 were
// 5-17 % light on drag, 6-10 % on lift); the knots at alpha <= 40 stay (the split-S flies them). The drag also rises about 3 %
// per Mach (the GREENs at Mach 5-6 read 4 % over the table): an alpha table cannot carry it. grtlsNzAt's lift and drag carry
// these factors, so the model the hold flies reads the flown Nz and GR_NZK stays near 1. Rows LIST(alpha, lift factor, drag factor), knots 5 deg apart (indexed directly), linear between, flat
// outside. FAR keeps the bare polar (GR_AERO_FIX_ON FALSE): its GRTLS aero is to be matched to stock's at its source.
// python GR_AERO_FIX (the offline model: its guidance and its vehicle).
GLOBAL GR_AERO_FIX IS LIST(LIST(10, 1.035, 0.883), LIST(15, 0.986, 0.919), LIST(20, 0.920, 0.869), LIST(25, 0.946, 0.877), LIST(30, 0.923, 0.851), LIST(35, 0.926, 0.860), LIST(40, 0.901, 0.842), LIST(45, 0.881, 0.789), LIST(50, 0.824, 0.729)).
GLOBAL GR_AERO_FIX_ON IS NOT FAR_ON.
GLOBAL GR_NZ_MEAS IS TRUE.
GLOBAL GR_NZK IS 1.0.               // the model's scale (1 at grtlsStart)
GLOBAL GR_NZK_TAU IS 3.0.           // s
GLOBAL GR_NZK_MIN IS 1.0.           // g
GLOBAL GR_NZK_LO IS 0.7.
GLOBAL GR_NZK_HI IS 1.2.
GLOBAL GR_NZ_ALIM IS 3.8.           // g: LIMITER A (a deviation): in a CONT's phases 6 and 4 (no Nz loop there:
                                    //   the pull-out, the S-turn) the alpha command at most the alpha whose body-normal
                                    //   Nz is this (measured: the peak 4.68 -> 4.03 g, 29 -> 30 of 45 flights caught); 0: off
GLOBAL GR_NZ_ALIM_RTLS IS TRUE.     // limiter A in an RTLS's phases 6 and 4 too (GR["cont"]
                                    //   0; not the split-S), a guard: the RTLS peaks 2.24 g there, so its flights
                                    //   (SLF, VBG) fly bit for bit as without it
GLOBAL GR_FT IS 0.3048.
GLOBAL GR_HDMAX0 IS 7.2E75.         // the FSSR's HDMAX start: above any sink
GLOBAL GR_CONT IS 0.                // 0 = the RTLS; 1 = GREEN (an ECAL / BDA site); 2 = BLUE (none): grtlsContSet
GLOBAL GR_PHILM_E IS 70.0.          // deg: GREEN's roll limit, phases 5 + 4 (SCOM 6.7: the ECAL bank 0 to 70)
GLOBAL GR_NZMAX IS 3.9.             // g: GREEN's phase-5 bank keeps the Nz command under this (SCOM 6.7: 3.9 g) ..
GLOBAL GR_NZAVF IS 0.9.             //   .. and under NZAVF x the Nz at the alpha cap (a deviation)
GLOBAL GR_DEOW_REACH IS -15000.0.   // m: GREEN -> BLUE at phase 4's start below this EOW - EN (not in the FSSR)
GLOBAL GR_BAIL_MACH IS 1.0.         // BLUE: the bailout hold below this Mach (SCOM 6.7: armed under Mach 1.0)
GLOBAL GR_BAIL_KEAS IS 190.0.       // KEAS: the hold (SCOM 6.7: 185 to 195 KEAS, zero roll)
GLOBAL GR_BQG1 IS 0.1.              // 1/s: the q-bar error gain (FSSR TGNZC eq 2.2's QBG1 form; the value this vehicle's)
GLOBAL GR_BQG2 IS 0.0026107.        // g per Pa/s (0.125 g per psf/s; eq 2.2's QBG2 form; the value this vehicle's)
GLOBAL GR_BAIL_NZCDL IS 0.2.        // g/s: the hold's Nz command rate (eq 3.6's DNZCDL; taem_sim's)
GLOBAL GR_BAIL_ALPMAX IS 20.0.      // deg: the hold's alpha ceiling (not in the FSSR)
GLOBAL GR_BAIL_END IS 300.0.        // m: BLUE's loop in ops6q ends here (no TAEM)
// THE DITCH (not in the FSSR; no crew on board: the bailout follows the coast so the orbiter lands in the water, ditched
// as softly as it can be). In the hold (phase 7), once the height above the water (ALT:RADAR) is at most GR_DITCH_TAU x
// the sink, an exponential flare: hdot command -MAX(GR_DITCH_HDTD, h / GR_DITCH_TAU), its Nz (the hdot error x
// GR_DITCH_K / g) as the alpha (<= GR_DITCH_ALPMAX), wings level; ops6q's BLUE loop runs to the water (grtlsBlueEnd)
// instead of ending at GR_BAIL_END. Measured on al_sim's plant from the 190 KEAS hold: the flare at ~76 m, the water at
// ~138 KEAS and 3 m/s sink, alpha 25 deg, against ~193 KEAS and 25 m/s with the attitude held from 300 m. GR_DITCH
// FALSE: no flare, the loop ends at GR_BAIL_END.
GLOBAL GR_DITCH IS TRUE.
GLOBAL GR_DITCH_TAU IS 3.0.         // s: the flare's time constant (and its entry: h <= TAU x the sink)
GLOBAL GR_DITCH_HDTD IS 0.6.        // m/s: the sink it ends on
GLOBAL GR_DITCH_K IS 1.5.           // 1/s: the hdot error to Nz (x 1 / g)
GLOBAL GR_DITCH_ALPMAX IS 25.0.     // deg: the alpha ceiling (the hold's 20 leaves ~12 m/s of sink)
GLOBAL GR_ALPRS IS 10.0.            // deg / Mach: CONT's recovery + hold alpha MIDVAL(ALPRS M + ALPRI, ALPRL, ALPREC):
GLOBAL GR_ALPRI IS 5.0.             //   20 at Mach 1.5 .. 50 at Mach 4.5 (SCOM 6.7: "a function of Mach number and
GLOBAL GR_ALPRL IS 20.0.            //   trim ... 20 to 58"; the line not in the FSSR)
GLOBAL GR_CQG IS 1.0.               // the q-bar filter's gain (taem_sim's CQG)
GLOBAL GR_QBARDL IS 500.0.          // Pa/s: its rate clamp (taem_sim's QBARDL)
// ---- THE ECAL LOGIC IN A GREEN (one rule set for both inclinations). FSSR STS 83-0001-34 4.8 for an ECAL abort:
// TGCOMP 2.1.1 the phugoid correction (phase 4: EOW += ECOMPG EOW HDOT), GRTRN 3.3.1-3.3.9 the energy bias on GRALPR
// (EN_DELTA = EOW - EN: low ENALPL / EN_BIAS1, falling or rising in 0 .. ENLIMHI EN_BIAS2 / 3, high ENALPU unless the
// load > TLFMX1, within ALPHA_MIN / ALPHA_MAX), GRTRN 4.1 ECAL's phase 5 -> 4 (HDOT > HDTRNA, or HDOT > HDTBNK once
// ACC_VERT < 0), GRPHIC 1.2 / 1.3.B / 1.3.2 the S-turn (EOW > ES: the bank PHISTN toward the HAC and on past it by
// DPSACLMT = MIN(DPHISLP M + DPHIINT, DPSACLMT_MAX), then back; out at EOW < EST), and GRTRN 3.3.10-3.3.13 + GRALPC
// 3.4 / 4.1 the second pull-out's protection (phase 4's alpha command <= ALPHA_UL, the alpha whose load is ALPPRT).
// The rule set (ECOMPG 0.0014, HDTRNA -900, ENALPL 0, EN_BIAS2 0, ECAL_MSW3 3, ECAL_ST_LEAD 10, HDTRNA_DPSAC 20,
// ECAL_PPRT 3.7 always) raised the onboard test's landings from 104 to 109 of 234 GREEN calls at inclination 51.6 deg
// and from 44 to 45 of 160 at 36.25 deg. The FSSR prints no value for any of these (MX): all are this vehicle's. The
// deviations from the FSSR: (1) ALPHA_UL from the aero model (grtlsAfn: the alpha whose model Nz is ALPPRT, in
// ALPHA_MIN .. ALPHA_MAX) in place of the FSSR's gain prediction ALPHA + Q / ALPG1 + (ALPPRT - LOAD_TOTAL) / (ALPG1
// ALPG2) (no FSSR values for ALPG1 / ALPG2; the model has no pitch rate); (2) the cap armed through all of phase 4
// (GR_ECAL_PPRT_ARM "always"; "fssr" = the FSSR's IPPRTF: LOAD_TOTAL < TLFMX1 once ICNTR >= ICNTR_LIM passes had
// ACC_VERT < 0, which never armed in this vehicle's flights: the load stays above 2.5 g); (3) the S-turn starts only
// below Mach ECAL_MSW3 and with the lead EOW + ECAL_ST_LEAD x MIN(DEOWERR, 0) > ES; the HDTRNA exit only while |DPSAC|
// > HDTRNA_DPSAC; (4) the bias rides on the intact phase-4 line (with 1 / cos bank), not the FSSR's contingency line;
// the energy references are TAEM's EN / ES / EST (TGCOMP 2.12-2.16 not built); ACC_VERT = the HDOT change over the
// guidance cycle. Not built (both off in the rule set): GRPHIC 3.1 / 3.5's wings-level hold and a far energy
// reference. GR_ECAL FALSE: a GREEN flies without the ECAL logic.
GLOBAL GR_ECAL IS TRUE.             // TRUE: the ECAL logic in a GREEN
GLOBAL GR_ECOMPG IS 0.0014.         // s/m: TGCOMP 2.1.1's phugoid gain, EOW += ECOMPG EOW HDOT (HDOT m/s) in phase 4
GLOBAL GR_HDTBNK IS -1000.0.        // ft/s: phase 5 -> 4 above this sink once ACC_VERT < 0 (GRTRN 4.1)
GLOBAL GR_HDTRNA IS -900.0.         // ft/s: phase 5 -> 4 above this sink, no alpha test (GRTRN 4.1) ..
GLOBAL GR_HDTRNA_DPSAC IS 20.0.     //   .. only while |DPSAC| > this (deg; a deviation; 0 = always, the FSSR's form)
GLOBAL GR_ENLIMHI IS 3000.0.        // m: EN_DELTA above this = high (GRTRN 3.3.2, EN_HIS 0)
GLOBAL GR_ENLIMLO IS -1000.0.       // m: EN_DELTA below this (and |DPSAC| < DPSAC2) = low (3.3.3, EN_LOS 0)
GLOBAL GR_DPSAC2 IS 20.0.           // deg: the heading error limit for ENALPL (3.3.7.1)
GLOBAL GR_ENALPL IS 0.0.            // deg: the low-energy bias (the rule set; the offline model's default -8)
GLOBAL GR_ENALPU IS 8.0.            // deg: the high-energy bias
GLOBAL GR_EN_BIAS1 IS 0.0.          // deg: low but turning (|DPSAC| >= DPSAC2) or above ENLIMLO
GLOBAL GR_EN_BIAS2 IS 0.0.          // deg: in 0 .. ENLIMHI and falling (the rule set; the offline model's default -3)
GLOBAL GR_EN_BIAS3 IS 0.0.          // deg: in 0 .. ENLIMHI and rising
GLOBAL GR_EN_BIAS4 IS 0.0.          // deg: high but the load > TLFMX1
GLOBAL GR_TLFMX1 IS 2.5.            // g: the body-normal load above which the high bias is withheld (3.3.7.3); IPPRTF's
GLOBAL GR_ECAL_AMIN IS 14.0.        // deg: ALPHA_MIN (3.3.5; not in the FSSR: the model's L/D max at Mach 2.5-6)
GLOBAL GR_ECAL_AMAX IS 40.0.        // deg: ALPHA_MAX (3.3.6; not in the FSSR: GRALPU)
GLOBAL GR_ECAL_PPRT IS 3.7.         // g: ALPPRT (GRTRN 3.3.12), the second pull-out's load limit (at 3.9 alpha lags the
                                    //   command and the load overshoots 4 g); 0 = off
GLOBAL GR_ECAL_PPRT_ARM IS "always".   // "always": the cap through all of phase 4; "fssr": once IPPRTF is on
GLOBAL GR_ECAL_ICNTR_LIM IS 5.      // ICNTR_LIM (the FSSR prints none)
// THE RELAY'S FIXED POINT: in phase 4 at Mach 3.4-3.8 the alpha command flipped 22 <-> 30 deg pass to pass in flight:
// 3.3.7.3's relay, ENALPU (+8) while the load is under TLFMX1 and EN_BIAS4 (0) above it, with GRALPC 4.1's ALPCMD =
// GRALPR each cycle and the 5 deg/s FCS slew reaching it within the cycle (the alpha with the bias is over 2.5 g and the
// alpha without it under; sn["nz"] is the measured Nz with GR_NZ_MEAS, the model's nz_mod without it).
// "cont" (a stated deviation) commands the relay's fixed point
// instead: the bias that puts the alpha where the model reads TLFMX1 (grtlsAfn), within EN_BIAS4 .. ENALPU; where the
// relay would hold a side the two agree. Against the offline model's reference (292 GREEN flights): the same 284 TAEM /
// 8 bailouts, the TAEM hand-over within -89..+83 m and 1 s, the worst pass-to-pass swing of the command 16-17 -> 1.2 deg
// (8.1 where the energy falls under ENLIMHI: 3.3.7.2's one step, in both), the load held at 2.43-2.46 g. "fssr" = the
// FSSR's relay.
GLOBAL GR_ECAL_TLF IS "cont".
GLOBAL GR_ECAL_ST_LEAD IS 10.0.     // s: an ECAL S-turn starts only if EOW + DEOWERR x this > ES (a deviation; 0 = no lead)
GLOBAL GR_ECAL_MSW3 IS 3.0.         // Mach: an ECAL S-turn starts only below this (a deviation, as MSW3; 0 = always)
GLOBAL GR_PHISTN IS 45.0.           // deg: the S-turn's bank toward and past the HAC (GRPHIC 1.3.2.2)
GLOBAL GR_DPHISLP IS 10.0.          // deg / Mach: how far past the HAC's tangency: DPSACLMT = MIN(DPHISLP M + DPHIINT, ..
GLOBAL GR_DPHIINT IS 5.0.           //   deg ..
GLOBAL GR_DPSACLMT_MAX IS 60.0.     //   .. DPSACLMT_MAX) deg (1.3.2.3-4)
// ---- RANGE CONTROL BEFORE PHASE 4 IN A GREEN (not in the FSSR): a GREEN that starts phase 4 high and close overflies
// the site above Mach GR_ECAL_MSW3, where no ECAL S-turn starts, and reaches TAEM below EN. While the HAC-route range
// RPRED is under GR_RC_RNG, Mach is above GR_RC_MLO and EOW - EN is above GR_RC_DE, the bank is held at GR_RC_PHI toward
// the HAC side ysgn: in phase 5 in place of GPHI x DPSAC (the Nz hold's bank limit still binds), in phase 4 in place of
// set 3 (an ECAL S-turn that starts comes first). Phase 4's EOW - EN is TGCOMP's (with TGCOMP 2.1.1); phase 5's comes
// from a throwaway TGINIT + GTP + TGCOMP on phase 5's HAC each cycle (grtlsRcE5). When it ends, the laws above take
// over. Not in the split-S. Offline (the GRTLS model, the 350-point overflight grid): 191 caught against 157 without it
// (35 gained, 1 lost); the 234 GREEN calls of the onboard test unchanged.
GLOBAL GR_RC_RNG IS 200000.0.       // m: on only while RPRED is under this (0 = off) ..
GLOBAL GR_RC_MLO IS 3.0.            //   .. Mach above this ..
GLOBAL GR_RC_DE IS 60000.0.         //   .. and EOW - EN above this (m)
GLOBAL GR_RC_PHI IS 70.0.           // deg: the bank held toward the HAC side
// ---- A GREEN'S RUNWAY END AND HAC SIDE AT PHASE 4'S START (not in the FSSR): a GREEN that flies past the site in phase 6
// (wings level) turns back in phases 5 and 4 and starts phase 4 under TAEM's corridor, the HAC of the end it was given
// up to ~500 km of route away. At phase 4's start above Mach GR_PICK_MLO, when the pair flown (the end, the side
// GR["ysgn"] or phase 4's rule) has EOW - EN (with TGCOMP 2.1.1, as phase 4 flies it) under EN + SS_EMIN_D and passes
// the reach check (its raw EOW - EN at GR_DEOW_REACH or above: a BLUE stands), grPickGreen scores both runway ends x
// both HAC sides as the split-S's ssPick does (ssEndE, ssBetter) and takes the best when its ssScore beats the pair
// flown by more than GR_PICK_DE. The end goes in as the crew's SW RWY puts it (ldSwitchRunway; ops6q applies RWY_NAME
// and the aim), the side by GR["ysgn"] and TG_OVERHEAD_DEFAULT (ops6q sets it for landRun and puts SS_OVH0 back after).
// Once, at phase 4's start; not after a crew OTT / SW RWY / site switch (GR["dmcrew"]), not in an RTLS, a BLUE or the
// split-S. The Mach floor: from Mach 4 the compensated EOW - EN predicts TAEM's start (the GRTLS model's 234 GREEN
// calls: TAEM's minus phase 4's, mean -0.7 km); a phase 4 that starts at Mach 2.5-3.5 hands to TAEM within seconds on
// the raw EOW, ~13 km above it, and a pick there lost 8 of the 234 calls. The margin: the largest switch that cost a
// landing in the model scored 4.5 km better. Offline (the model, the margin and the floor
// these): the 234 calls and the 350-point grid's landings unchanged; a Halifax case takes 22 straight-in at
// phase 4's start and lands 796 m past the threshold (on 04: 10 km short); two other flown cases unchanged.
// Order among the 4 pairs: ssScore first (a pair under the corridor, too LOW, never beats one
// inside it; all low = the highest), then, for pairs inside the corridor (score 0), the smallest |EOW - EN| (grPickBetter; a
// tie keeps the first), no longer the higher EOW - EN. The trigger, GR_PICK_DE, GR_PICK_MLO and the reach check are unchanged.
GLOBAL GR_PICK_DE IS 8000.0.        // m: the margin over the pair flown (ssScore) the best pair must beat (< 0 = off)
GLOBAL GR_PICK_MLO IS 4.0.          // the pick only when phase 4 starts above this Mach
GLOBAL GR_PICK_NOM IS TRUE.         // of the pairs scoring alike INSIDE the corridor, the one nearest nominal (the smallest
                                    //   |EOW - EN|) wins, not the higher EOW - EN (FALSE = ssBetter's order)
GLOBAL GR IS LEXICON().             // the guidance state (grtlsReset)
GLOBAL GR_LOG IS "".                // the per-cycle CSV ("" = none)
// ---- THE SPLIT-S (not in the FSSR; ssSet): the offline split-S model's I-loads (the law: SS_ALPHA / SS_NZ)
GLOBAL SS_ON IS FALSE.              // TRUE: the split-S (ssSet, before grtlsStart)
GLOBAL SS_NZ IS 2.5.                // g: the body-normal Nz held in phases 8 and 5
GLOBAL SS_ALPHA IS 38.0.            // deg: the alpha ceiling in phases 8 and 5
GLOBAL SS_ALPHA_LO IS 0.0.          // deg: the Nz bisection's floor
GLOBAL SS_SW_DEG IS 10.0.           // deg past straight down: phase 8 -> 5, heads up
GLOBAL SS_AZ0 IS 0.0.               // deg: the turn plane's heading (the ascent's az0, or the ground track's at ssSet)
GLOBAL SS_ENDS IS LIST().           // the site's two runway ends (ops6q), ssPick's choice at phase 4's start
GLOBAL SS_OVH0 IS TRUE.             // TG_OVERHEAD_DEFAULT before the split-S (ssSet; ops6q puts it back after landRun)
GLOBAL SS_EMIN_D IS -914.0.         // m: TAEM's corridor about EN, EMIN .. EMAX (taem_sim: EN - 914 / EN + 1829)
GLOBAL SS_EMAX_D IS 1829.0.
GLOBAL SS_FLOOR IS 5000.0.          // m: ops6q's GRTLS loop hands to TAEM below this in any phase (the pull-out's lowest
                                    //   is ~10 km: HANDOVER_ALT's 12 km would cut it)
// ---- BLUE TOWARD THE COAST (not in the FSSR; the header's BLUE paragraph): the offline model's I-loads
GLOBAL GR_BAIL_QMIN IS 2000.0.      // Pa: the bailout hold engages only with this q (BAIL_QMIN: one subsonic in vacuum dived)
GLOBAL GR_BLUE_NOCOS IS TRUE.       // a BLUE's GRALPR without the FSSR's 1 / |cos bank| (BLUE_NOCOS)
GLOBAL GR_BLUE_REARM IS TRUE.       // the pick drops the alpha trap for the rest of phase 6 (BLUE_REARM)
GLOBAL GR_BLUE_IL IS TRUE.          // the pick takes the CONT I-loads, grtlsContSet(2) (BLUE_IL)
GLOBAL GR_BLUE_SHORE IS TRUE.       // a BLUE banks toward the coast (BLUE_SHORE); FALSE = wings level
GLOBAL GR_BLUE_DOFF IS CST_DOFF.    // m: the line off the coast (BLUE_DOFF; lib_coast's 5000, its lean CST_KL 45)
GLOBAL GR_BLUE_PHILM IS CST_PHILM.  // deg: the bank's limit, and the turn radius's bank (BLUE_PHILM; lib_coast's 45;
                                    //   the search every CST_TSEL 1 s)
GLOBAL GR_BLUE_GAM4 IS -30.0.       // deg: no bank at or below this flight path .. (BLUE_GAM4)
GLOBAL GR_BLUE_GAMW IS 10.0.        //   .. full from 10 deg above it (BLUE_GAMW)
GLOBAL GR_BLUE_QB IS 3000.0.        // Pa: no bank under this q (BLUE_QB)
GLOBAL GR_COAST_FILE IS CST_FILE.   // the coast table (lib_coast's file)
GLOBAL GR_COAST IS CST.             // grtlsCoastLoad: the table ("ok" FALSE: none, a BLUE flies wings level); lib_coast's

// ---- THE NZ MODEL AND THE ALPHA SLEW IN C# (the KAL/S coprocessor: ADDONS:KALS:GRFCS / GRNZ) ---------------------
// On from the start: a failure costs nothing, kOS flies the call. With GR_CS and the addon installed, grtlsFcs (every
// loop pass: the bisection of the Nz model, 2 + 30 aero evaluations in phases 5 / 7 / the ditch / the split-S, ~90-130k
// kOS opcodes a pass) and grtlsNz (grtlsSense's, the display's, GREEN's / BLUE's phase-5 bank limit) go to the addon
// (coproc/GrtlsGuid.cs: a line-for-line port of grtlsFcsK / grtlsAlphaForNz / grtlsNzAt / grtlsNzK and entry_predict's
// model). The state stays these globals: the addon reads them at the call and writes back what kOS's call SETs
// (GR["acmd"], EPR_HINT_RHO, EPR_PR_REF; nothing on an error). kOS keeps the game reads (the pressure, ALT:RADAR) and the
// ditch's latch (grtlsDitch). ANY addon failure (no addon, an older DLL, an error) turns the switch off for the rest of
// the flight, says why (GR_CS_ERR) and kOS's own function flies that same call.
IF NOT (DEFINED GR_CS) { GLOBAL GR_CS IS TRUE. }               // TRUE: the addon flies grtlsFcs / grtlsNz
GLOBAL GR_CS_ERR IS "".           // why the addon is off ("" = it is not)
GLOBAL GR_CS_SET IS 0.            // 0 = not tried yet, 1 = ready, -1 = off for the flight
GLOBAL GR_CS_N IS 0.              // calls the addon flew
GLOBAL GR_CS_AFN IS 0.            // 0 = not asked yet, 1 = the addon has GRAFN, -1 = not (an older DLL: kOS's bisection)

FUNCTION grtlsCsOff {             // the addon off for the rest of the flight: kOS flies
    PARAMETER why.
    SET GR_CS_ERR TO why.
    SET GR_CS TO FALSE.
    SET GR_CS_SET TO -1.
}

FUNCTION grtlsCsReady {           // TRUE when the addon can take the call (checked once a flight)
    IF GR_CS_SET = 0 {
        LOCAL why IS "".
        IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
        ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
        ELSE IF NOT ADDONS:KALS:HASSUFFIX("GRFCS") { SET why TO "the KAL/S addon has no GRTLS model (an older KalsCoproc.dll)". }
        ELSE {
            LOCAL res IS ADDONS:KALS:GRSETUP(LIST(CONSTANT:E)).
            IF res <> "" { SET why TO "GRSETUP: " + res. }
        }
        IF why = "" { SET GR_CS_SET TO 1. } ELSE { grtlsCsOff(why). }
    }
    RETURN GR_CS_SET = 1.
}

FUNCTION grtlsNz {                          // the model's Nz at alpha (the dispatcher: the addon or grtlsNzK)
    PARAMETER aoa, altm, vrel.
    IF GR_CS AND grtlsCsReady() {
        LOCAL inp IS LIST(aoa, altm, vrel, eprPres(altm)).
        LOCAL res IS ADDONS:KALS:GRNZ(inp).
        IF res:ISTYPE("Scalar") { SET GR_CS_N TO GR_CS_N + 1. RETURN res. }
        grtlsCsOff("GRNZ: " + res).
    }
    RETURN grtlsNzK(aoa, altm, vrel).
}

FUNCTION grtlsFcs {                         // each pass (the dispatcher: the addon or grtlsFcsK below)
    PARAMETER dt, altm, vrel, gam, bank.
    IF GR_CS AND grtlsCsReady() {
        LOCAL dit IS FALSE.                 // the ditch's latch stays kOS's (grtlsFcsK's own order: its branch only)
        IF NOT (SS_ON AND (GR["iphase"] = 8 OR GR["iphase"] = 5)) AND GR["iphase"] = 7 { SET dit TO grtlsDitch(vrel, gam). }
        LOCAL inp IS LIST(dt, altm, vrel, gam, bank, dit, CHOOSE ALT:RADAR IF dit ELSE 0, eprPres(altm)).
        LOCAL res IS ADDONS:KALS:GRFCS(inp).
        IF res:ISTYPE("Scalar") { SET GR_CS_N TO GR_CS_N + 1. RETURN. }
        grtlsCsOff("GRFCS: " + res).
    }
    grtlsFcsK(dt, altm, vrel, gam, bank).
}

FUNCTION grtlsAfn {                         // grtlsAlphaForNz's dispatcher for ECAL's ALPHA_UL (the addon's GRAFN,
    PARAMETER nzt, altm, vrel, lo, hi.      //   or kOS's bisection: ~32 model Nz, ~100k opcodes); an older DLL
    IF GR_CS AND grtlsCsReady() {           //   without GRAFN: kOS's here, the rest stays the addon's
        IF GR_CS_AFN = 0 { SET GR_CS_AFN TO CHOOSE 1 IF ADDONS:KALS:HASSUFFIX("GRAFN") ELSE -1. }
        IF GR_CS_AFN = 1 {
            LOCAL inp IS LIST(nzt, altm, vrel, lo, hi, eprPres(altm)).
            LOCAL res IS ADDONS:KALS:GRAFN(inp).
            IF res:ISTYPE("Scalar") { SET GR_CS_N TO GR_CS_N + 1. RETURN res. }
            grtlsCsOff("GRAFN: " + res).
        }
    }
    RETURN grtlsAlphaForNz(nzt, altm, vrel, lo, hi).
}

// ------------------------------------------------ the guidance (translated to python line for line: the check)
FUNCTION grtlsAeroFix {                     // GR_AERO_FIX's factor at alpha: j 1 = the lift's, 2 = the drag's
    PARAMETER aoa, j.
    LOCAL t IS GR_AERO_FIX.
    LOCAL n IS t:LENGTH.
    IF aoa <= t[0][0] { RETURN t[0][j]. }
    IF aoa >= t[n - 1][0] { RETURN t[n - 1][j]. }
    LOCAL i IS MIN(FLOOR((aoa - t[0][0]) / (t[1][0] - t[0][0])), n - 2).
    RETURN t[i][j] + (t[i + 1][j] - t[i][j]) * (aoa - t[i][0]) / (t[i + 1][0] - t[i][0]).
}

FUNCTION grtlsNzAt {                        // the model's body-normal Nz (g) at alpha, the alpha-free terms given
    PARAMETER aoa, mach, vrel, pr, qb.
    LOCAL cdv IS 0.
    IF SS_ON {                              // the split-S: the speedbrake closed to TAEM (ops6q keeps it so)
        SET cdv TO eprCda(aoa, mach) * (1 + eprCdFix(mach)).
    } ELSE {
        SET cdv TO eprCda(aoa, mach) * (1 + eprCdFix(mach)) * (1 + eprSbFrac(mach, vrel)).   // eprCdaEntry without EPR_AERO_FIX (measured at entry only; GrtlsGuid.cs the same)
    }
    LOCAL cl IS eprCla(aoa, mach).
    IF GR_AERO_FIX_ON {                     // the GRTLS's measured aero (GR_AERO_FIX)
        SET cl TO cl * grtlsAeroFix(aoa, 1).
        SET cdv TO cdv * grtlsAeroFix(aoa, 2).
    }
    RETURN (cl * COS(aoa) + cdv * pr * SIN(aoa)) * qb / EPR_G0.
}

FUNCTION grtlsNzK {                         // the model's Nz at alpha (kOS's own; the dispatcher: grtlsNz above)
    PARAMETER aoa, altm, vrel.
    IF altm >= EPR_ATM { RETURN 0.0. }
    LOCAL rho IS eprRho(altm).
    RETURN grtlsNzAt(aoa, eprMach(altm, vrel), vrel, eprPrMult(rho * vrel), 0.5 * rho * vrel * vrel) * GR_NZK.
}

FUNCTION grtlsAlphaForNz {                  // the alpha in [lo, hi] whose Nz is nzt; hi / lo out of reach
    PARAMETER nzt, altm, vrel, lo, hi.
    IF altm >= EPR_ATM { RETURN hi. }
    SET nzt TO nzt / GR_NZK.                // the model x GR_NZK reads nzt
    LOCAL rho IS eprRho(altm).
    LOCAL mach IS eprMach(altm, vrel).
    LOCAL pr IS eprPrMult(rho * vrel).
    LOCAL qb IS 0.5 * rho * vrel * vrel.
    IF grtlsNzAt(hi, mach, vrel, pr, qb) <= nzt { RETURN hi. }
    IF grtlsNzAt(lo, mach, vrel, pr, qb) >= nzt { RETURN lo. }
    LOCAL k IS 0.
    UNTIL k >= GR_NZ_ITERS {
        LOCAL mid IS 0.5 * (lo + hi).
        IF grtlsNzAt(mid, mach, vrel, pr, qb) > nzt { SET hi TO mid. } ELSE { SET lo TO mid. }
        SET k TO k + 1.
    }
    RETURN 0.5 * (lo + hi).
}

FUNCTION grtlsContSet {                     // before grtlsStart: 0 = the RTLS (its own I-loads, after a CONT in this kOS
    PARAMETER mode.                         //   session too); 1 GREEN / 2 BLUE = CONT's I-loads (SCOM 6.7)
    SET GR_CONT TO mode.
    SET GR_HDNOM TO CHOOSE -1550.0 IF mode > 0 ELSE -1700.0.
    SET GR_DHDUL TO CHOOSE 1.7 IF mode > 0 ELSE 0.3.
    SET GR_DHDLL TO CHOOSE -1.0 IF mode > 0 ELSE -0.2.
    SET GR_SMNZC1 TO CHOOSE 0.25 IF mode > 0 ELSE 0.4.
    SET GR_SMNZC2 TO CHOOSE 0.15 IF mode > 0 ELSE 0.2.
    SET GR_NZSW1 TO GR_GRNZC1 + 1.0 - GR_SMNZC1 - GR_SMNZC2.
}

FUNCTION grtlsQ {                           // the model's dynamic pressure (Pa)
    PARAMETER altm, vrel.
    IF altm >= EPR_ATM { RETURN 0.0. }
    RETURN 0.5 * eprRho(altm) * vrel * vrel.
}

FUNCTION grtlsKeas {
    PARAMETER qb.
    RETURN SQRT(MAX(0, 2 * qb / 1.225)) / 0.5144444.
}

FUNCTION grtlsReset {                       // the guidance state at the ET separation (phase 6; the split-S: phase 8)
    PARAMETER a0, tnow.
    LOCAL ip IS 6.
    IF SS_ON { SET ip TO 8. }
    RETURN LEXICON("iphase", ip, "itsw", 0, "igra", 0, "alpcmd", GR_ALPREC, "hdmax", GR_HDMAX0, "dgrnz", 0.0,
                   "dgrnzt", 0.0, "smnz1", GR_SMNZC1, "smnz2", GR_SMNZC2, "nzc", 0.0, "istp4", 1, "ssgn", 0.0,
                   "ysgn", 0, "tg", 0, "gp", 0, "phic_at", 0.0, "gralpr", 0.0, "acmd", a0, "bank_want", 0.0,
                   "cont", GR_CONT, "psha5", 0.0, "qbarf", 0.0, "qbard", 0.0, "qbars", 0.0, "alprec", GR_ALPREC,
                   "done", FALSE, "tnext", tnow, "t0", tnow, "ang", 0.0, "angp", 999.0, "unw", 0.0, "bank_eq", 0.0,
                   "rwy", "", "ss_e", LIST(), "notrap", FALSE, "pick", FALSE, "sh_t", -1, "sh", LIST(), "sh_side", 0,
                   "hdg_c", -1, "ditch", FALSE, "hdp", 0.0, "hdp_ok", FALSE, "acc_vert", 0.0, "en_dold", 0.0,
                   "en_bias", 0.0, "dpsac_init", FALSE, "dpsaci", 0.0, "icntr", 0, "ipprtf", FALSE, "alpha_ul", -1,
                   "arm5", FALSE, "tgon", 0, "gpd", 0, "dmcrew", FALSE,   // TAEM's state since the boot, its gtp, a crew OTT
                   "rc", FALSE, "rcw", "",                 // range control on, its event's numbers
                   "gpk", FALSE, "gpw", "").               // grPickGreen took a pair, its event's words
}

FUNCTION grtlsGuid {                        // one guidance cycle: GTP / TGCOMP in phase 4, GRTRN, GRNZC or GRALPC, GRPHIC
    PARAMETER sn, am, bank, brate, st.      // sn: the sensed state; am: the measured alpha; bank / brate: the ship's
    LOCAL hdft IS sn["hdot"] / GR_FT.       //   (+ = left); st: TAEM's state (ldState)
    LOCAL gp IS 0.
    LOCAL gpOn IS FALSE.
    IF GR["hdp_ok"] { SET GR["acc_vert"] TO (sn["hdot"] - GR["hdp"]) / GR_DTG. }   // ACC_VERT (m/s2; GRTRN 4.1)
    SET GR["hdp"] TO sn["hdot"].
    SET GR["hdp_ok"] TO TRUE.
    LOCAL ecal IS GR_ECAL AND GR["cont"] = 1.   // the ECAL logic this cycle (a GREEN; held through a REACH below)
    IF ecal AND GR_ECAL_PPRT > 0 AND (GR["iphase"] = 5 OR GR["iphase"] = 4) {   // GRTRN 3.3.10-3.3.13, IPPRTF
        IF sn["nz"] < GR_TLFMX1 AND GR["icntr"] >= GR_ECAL_ICNTR_LIM AND NOT GR["ipprtf"] {
            SET GR["ipprtf"] TO TRUE.
            grtlsEv("IPPRTF", sn, am).
        }
        IF GR["acc_vert"] < 0.0 { SET GR["icntr"] TO GR["icntr"] + 1. }
    }
    IF GR["pick"] {                         // THE CREW'S BLUE or the default (not in the FSSR; ops6q's choice): a BLUE
        SET GR["pick"] TO FALSE.            //   from this cycle, its I-loads CONT's, the alpha trap off for phase 6 (the
        IF GR["cont"] = 0 {                 //   alpha falls from ALPREC to CONT's by Mach: the trap would fire in vacuum)
            SET GR["cont"] TO 2.
            SET GR["tg"] TO 0.
            IF GR_BLUE_REARM {
                SET GR["itsw"] TO 0.
                SET GR["notrap"] TO TRUE.
            }
            IF GR_BLUE_IL {
                grtlsContSet(2).
                IF GR["iphase"] = 6 {
                    SET GR["smnz1"] TO GR_SMNZC1.
                    SET GR["smnz2"] TO GR_SMNZC2.
                }
            }
            grtlsEv("BLUEPICK", sn, am).
        }
    }
    IF GR["cont"] <> 0 { SET GR["alprec"] TO cstMid(GR_ALPRS * sn["mach"] + GR_ALPRI, GR_ALPRL, GR_ALPREC). }
    IF GR["iphase"] = 4 AND GR["cont"] <> 2 {
        LOCAL tcs IS grtlsTgCs("p4", st, 0, 0, ecal, sn["hdot"]).
        IF tcs:ISTYPE("Lexicon") {
            SET gp TO tcs["gp"].
            SET gpOn TO TRUE.
        } ELSE {
            LOCAL tg IS GR["tg"].
            SET gp TO taemg_gtp(st, tg["ysgn"], TG_IPH_ACQ, tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"]).
            SET gpOn TO TRUE.
            SET tg["psha_prev"] TO gp["psha"].
            taemg_comp(tg, st, gp).
            IF ecal { SET tg["eow"] TO tg["eow"] + GR_ECOMPG * tg["eow"] * sn["hdot"]. }   // TGCOMP 2.1.1 (ECAL)
            SET tg["ecompk"] TO CHOOSE GR_ECOMPG IF ecal ELSE 0.0.   // the pages' redraws apply it too (tdEnNow)
            SET gp TO grtlsTgDm(tg, st, gp, CHOOSE sn["hdot"] IF ecal ELSE 0.0).   // the OTT row's fields, a press
        }
    } ELSE IF GR["cont"] = 1 AND GR["iphase"] = 5 {   // GREEN (a deviation): the HAC geometry from the Nz hold on, for its bank
        IF GR["ysgn"] = 0 {
            LOCAL same5 IS CHOOSE 1.0 IF st["y"] >= 0.0 ELSE -1.0.
            SET GR["ysgn"] TO CHOOSE -same5 IF TG_OVERHEAD_DEFAULT ELSE same5.
        }
        SET gp TO taemg_gtp(st, GR["ysgn"], TG_IPH_ACQ, TG_RFMX, GR["psha5"], TRUE, TG_R2).
        SET gpOn TO TRUE.
        SET GR["psha5"] TO gp["psha"].
    }
    IF GR["cont"] <> 2 AND (GR["iphase"] = 6 OR GR["iphase"] = 5) AND NOT SS_ON {   // TAEM's state from the boot
        IF NOT grtlsTgCs("pre", st, bank, brate, FALSE, 0):ISTYPE("Lexicon") { grtlsTgPre(st, bank, brate). }
    }
    LOCAL rc IS FALSE.                      // RANGE CONTROL (GR_RC_*) this cycle: from phase 5's or phase 4's state
    IF GR_RC_RNG > 0 AND GR["cont"] = 1 AND gpOn AND NOT SS_ON {
        LOCAL rcw IS "".
        SET rc TO gp["rpred"] < GR_RC_RNG AND sn["mach"] > GR_RC_MLO.
        IF rc {
            LOCAL rcde IS 0.0.
            IF GR["iphase"] = 5 { SET rcde TO grtlsRcE5(st, gp["psha"]). }
            ELSE { SET rcde TO GR["tg"]["eow"] - GR["tg"]["en"]. }
            SET rc TO rcde > GR_RC_DE.
            SET rcw TO ", EOW-EN " + ROUND(rcde) + " m".
        }
        IF rc <> GR["rc"] {
            SET GR["rcw"] TO "phase " + GR["iphase"] + ": RPRED " + ROUND(gp["rpred"] / 1000, 1) + " km, Mach "
                             + ROUND(sn["mach"], 2) + rcw.
        }
    } ELSE IF GR["rc"] {
        SET GR["rcw"] TO "phase " + GR["iphase"].
    }
    IF rc <> GR["rc"] {
        SET GR["rc"] TO rc.
        grtlsEv("RC", sn, am).
    }
    LOCAL cosphi IS COS(bank).
    // BLUE (not in the FSSR): subsonic in any phase, with q (GR_BAIL_QMIN) -> the bailout hold; not in the split-S's
    // phase 8 (a crew BAILOUT there, ops6q's BLUE, waits for phase 5: heads up)
    IF GR["cont"] = 2 AND GR["iphase"] <> 7 AND GR["iphase"] <> 8 AND sn["mach"] < GR_BAIL_MACH AND sn["q"] >= GR_BAIL_QMIN {
        grtlsEv("BAIL", sn, am).
        SET GR["iphase"] TO 7.
        SET GR["qbars"] TO 0.5 * 1.225 * (GR_BAIL_KEAS * 0.5144444) ^ 2.
        SET GR["qbarf"] TO sn["q"].
        SET GR["qbard"] TO 0.0.
        SET GR["nzc"] TO 0.0.
    }
    IF GR["iphase"] = 8 {                   // THE SPLIT-S (not in the FSSR): past straight down + SS_SW_DEG the vehicle is heads
        IF sn["ang"] <= -90.0 - SS_SW_DEG { //   up: phase 5 from the bank whose lift points as phase 8's (ssSense's
            SET GR["iphase"] TO 5.          //   beq; ops6q takes it into bankNow, the steering back to entrySteer)
            SET bank TO sn["beq"].
            SET brate TO 0.0.
            SET cosphi TO COS(bank).
            SET GR["bank_eq"] TO bank.
            SET GR["arm5"] TO TRUE.         // the split-S's hold armed at once
            grtlsEv("SS5", sn, am).
        }
    }
    // GRTRN (4.8.2.8)
    IF GR["iphase"] = 6 {
        IF sn["nz"] > GR_NZSW1 + GR["dgrnz"] {
            SET GR["iphase"] TO 5.
            SET GR["arm5"] TO TRUE.         // entered by Nz, the hold armed at once
            grtlsEv("P5", sn, am).
        } ELSE {
            IF am > GR_ALP_TRAP_ARM AND NOT GR["notrap"] AND sn["q"] >= GR_PH_QMIN { SET GR["itsw"] TO 1. }   // (not after a pick: BLUE_REARM; in the air only)
            IF GR["itsw"] = 1 AND am < GR_ALP_TRAP_TRIG AND sn["q"] >= GR_PH_QMIN {
                SET GR["iphase"] TO 5.
                grtlsEv("P5TRAP", sn, am).
            }
        }
    } ELSE IF GR["iphase"] <> 8 {
        SET GR["gralpr"] TO MIN(cstMid(GR_GRALPS * sn["mach"] + GR_GRALPI, GR_GRALPL, GR_GRALPU)
                                / (CHOOSE 1 IF (GR["cont"] = 2 AND GR_BLUE_NOCOS) ELSE ABS(cosphi)), GR_AMAXLD).
        IF ecal AND GR["iphase"] = 4 AND gpOn {   // GRTRN 3.3.1-3.3.9, the energy bias (EN_DELTA = EOW - EN)
            LOCAL edl IS GR["tg"]["eow"] - GR["tg"]["en"].
            IF edl < 0.0 {
                SET GR["en_bias"] TO CHOOSE GR_ENALPL IF (ABS(gp["dpsac"]) < GR_DPSAC2 AND edl < GR_ENLIMLO) ELSE GR_EN_BIAS1.
            } ELSE IF edl < GR_ENLIMHI {
                SET GR["en_bias"] TO CHOOSE GR_EN_BIAS2 IF edl < GR["en_dold"] ELSE GR_EN_BIAS3.
            } ELSE {
                IF GR_ECAL_TLF = "cont" {       // the relay's fixed point (GR_ECAL_TLF above)
                    LOCAL alf IS grtlsAfn(GR_TLFMX1, sn["alt"], sn["vr"], GR_ECAL_AMIN, GR_ECAL_AMAX).
                    SET GR["en_bias"] TO MAX(GR_EN_BIAS4, MIN(GR_ENALPU, alf - GR["gralpr"])).
                } ELSE {
                    SET GR["en_bias"] TO CHOOSE GR_EN_BIAS4 IF sn["nz"] > GR_TLFMX1 ELSE GR_ENALPU.
                }
            }
            SET GR["en_dold"] TO edl.
            SET GR["gralpr"] TO cstMid(GR["gralpr"] + GR["en_bias"], GR_ECAL_AMIN, GR_ECAL_AMAX).
        }
        IF GR["iphase"] = 5 {
            IF NOT GR["arm5"] AND sn["nz"] > GR_NZSW1 + GR["dgrnz"] {   // the hold armed once its load has built
                SET GR["arm5"] TO TRUE.
                grtlsEv("ARM5", sn, am).
            }
            LOCAL fssr IS hdft > GR_HDTRN AND am > GR["gralpr"].
            LOCAL guard IS GR_HOLD_GUARD AND sn["hdot"] > 0.0 AND NOT fssr.
            LOCAL etop IS FALSE.            // GRTRN 4.1, ECAL's exit (HDTRNA with the heading gate (a deviation), or HDTBNK falling)
            IF ecal AND NOT (fssr OR guard) {
                LOCAL big IS TRUE.
                IF gpOn { SET big TO ABS(gp["dpsac"]) > GR_HDTRNA_DPSAC. }
                SET etop TO (hdft > GR_HDTRNA AND big) OR (hdft > GR_HDTBNK AND GR["acc_vert"] < 0.0).
            }
            IF (fssr OR guard OR etop) AND sn["q"] >= GR_PH_QMIN   // not while the orbiter still climbs above the air
               AND (GR["arm5"] OR NOT GR_HOLD_ARM) {                // nor before the hold's load has built
                SET GR["iphase"] TO 4.
                IF etop { grtlsEv("ECAL54", sn, am). }
                IF guard { grtlsEv("GUARD", sn, am). }
                IF GR["cont"] = 2 {
                    grtlsEv("P4BLUE", sn, am).
                } ELSE {
                    IF SS_ON {              // THE SPLIT-S: the runway END and the HAC side picked here (ssPick, TAEM's
                        SET st TO ssPick(bank, brate).   //   corridor): st = TAEM's state on that end, GR["ysgn"] its side
                        grtlsEv("SSPICK", sn, am).
                    } ELSE IF GR["cont"] = 1 AND GR_PICK_DE >= 0 AND NOT GR["dmcrew"] AND sn["mach"] > GR_PICK_MLO {
                        SET st TO grPickGreen(st, bank, brate, CHOOSE GR_ECOMPG * sn["hdot"] IF ecal ELSE 0.0).   // A GREEN
                        IF GR["gpw"] <> "" { grtlsEv("GPICK", sn, am). }   //   under the corridor: its end and side
                    }
                    LOCAL same IS CHOOSE 1.0 IF st["y"] >= 0.0 ELSE -1.0.
                    LOCAL ysgn IS CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same.
                    IF GR["ysgn"] <> 0 { SET ysgn TO GR["ysgn"]. }
                    LOCAL p0 IS taemg_gtp(st, ysgn, TG_IPH_ACQ, TG_RFMX, 0.0, TRUE, TG_R2)["psha"].
                    LOCAL tg0 IS GR["tg"].  // the display's state since the boot: the crew's choices kept
                    SET GR["tg"] TO taemg_init(st, ysgn, TG_RFMX, taemg_gtp(st, ysgn, TG_IPH_ACQ, TG_RFMX, p0, TRUE, TG_R2)["psha"],
                                               taemg_ship_to_bank(bank), taemg_ship_to_bank(brate)).
                    SET GR["ysgn"] TO ysgn.
                    LOCAL tg IS GR["tg"].
                    IF GR["tgon"] = 1 AND tg0:ISTYPE("Lexicon") { FOR k IN GR_TG_CREW { SET tg[k] TO tg0[k]. } }
                    SET GR["tgon"] TO 1.
                    SET gp TO taemg_gtp(st, ysgn, TG_IPH_ACQ, tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"]).
                    SET gpOn TO TRUE.
                    SET tg["psha_prev"] TO gp["psha"].
                    taemg_comp(tg, st, gp).
                    SET gp TO grtlsTgDm(tg, st, gp, 0.0).
                    grtlsEv("P4", sn, am).
                    IF GR["cont"] = 1 AND tg["eow"] - tg["en"] < GR_DEOW_REACH {   // OPS 6's reach check (not in the FSSR)
                        grtlsEv("REACH", sn, am).
                        SET GR["cont"] TO 2.
                    }
                    IF ecal AND GR["cont"] = 1 {   // TGCOMP 2.1.1 on phase 4's first call too (after the raw check)
                        SET tg["eow"] TO tg["eow"] + GR_ECOMPG * tg["eow"] * sn["hdot"].
                    }
                    SET tg["ecompk"] TO CHOOSE GR_ECOMPG IF ecal AND GR["cont"] = 1 ELSE 0.0.   // the pages' redraws apply it too
                }
            }
        } ELSE IF GR["iphase"] = 4 {
            IF GR["cont"] <> 2 AND sn["mach"] < GR_MSW1 AND NOT (SS_ON AND am > GR_AMAXLD) {   // a split-S: the alpha
                SET GR["done"] TO TRUE.                                                       //   transition first
                grtlsEv("TAEM", sn, am).
            }
        }
    }
    SET GR["gp"] TO gp.
    IF NOT GR["done"] {
        // GRNZC (4.8.2.9) in phase 5, GRALPC (4.8.2.10) in 6 and 4
        IF GR["iphase"] = 5 {
            SET GR["smnz1"] TO GR_SMNZC3 * GR["smnz1"].
            SET GR["smnz2"] TO MAX(GR["smnz2"] - GR_SMNZC4, GR_SMNZ2L).
            SET GR["nzc"] TO GR_GRNZC1 - GR["smnz1"] - GR["smnz2"] + GR["dgrnz"].
        } ELSE IF GR["iphase"] = 7 {          // BLUE's bailout: the q-bar hold (FSSR TGNZC eqs 2.2, 3.6-3.7; taem_sim's filter)
            SET GR["qbard"] TO cstMid(GR_CQG * (sn["q"] - GR["qbarf"]), -GR_QBARDL, GR_QBARDL).
            SET GR["qbarf"] TO GR["qbarf"] + GR["qbard"] * GR_DTG.
            LOCAL nzcl IS GR_BQG2 * (GR_BQG1 * (GR["qbarf"] - GR["qbars"]) + GR["qbard"]).
            SET GR["nzc"] TO GR["nzc"] + cstMid((nzcl - GR["nzc"]) * GR_CQG, -GR_BAIL_NZCDL, GR_BAIL_NZCDL) * GR_DTG.
        } ELSE IF GR["iphase"] = 6 {
            SET GR["alpcmd"] TO GR["alprec"].
            IF hdft < GR["hdmax"] {
                SET GR["hdmax"] TO hdft.
            } ELSE {
                SET GR["dgrnz"] TO cstMid((GR_HDNOM - GR["hdmax"]) * GR_DHDNZ, GR_DHDLL, GR_DHDUL).
                SET GR["dgrnzt"] TO GR_GRNZC1 + GR["dgrnz"] + 1.0.
            }
        } ELSE IF GR["iphase"] <> 8 {
            IF GR["igra"] = 0 {
                SET GR["alpcmd"] TO am.
                SET GR["igra"] TO 1.
            }
            IF GR["igra"] = 1 {
                LOCAL dgralp IS cstMid(GR["gralpr"] - am, GR_GRALL, GR_GRALU).
                SET GR["alpcmd"] TO GR["alpcmd"] + dgralp.
                IF (dgralp < 0.0 AND GR["alpcmd"] <= GR["gralpr"]) OR (dgralp > 0.0 AND GR["alpcmd"] >= GR["gralpr"]) {
                    SET GR["alpcmd"] TO GR["gralpr"].
                    SET GR["igra"] TO 2.
                }
            } ELSE {
                SET GR["alpcmd"] TO GR["gralpr"].
            }
            IF ecal AND GR_ECAL_PPRT > 0 AND GR["iphase"] = 4 AND (GR["ipprtf"] OR GR_ECAL_PPRT_ARM = "always") {
                SET GR["alpha_ul"] TO grtlsAfn(GR_ECAL_PPRT, sn["alt"], sn["vr"], GR_ECAL_AMIN, GR_ECAL_AMAX).
                IF GR["alpha_ul"] < GR["alpcmd"] { SET GR["alpcmd"] TO GR["alpha_ul"]. }   // GRALPC 3.4 / 4.1 (ALPHA_UL from the aero model: a deviation)
            }
        }
        // GRPHIC (4.8.2.12)
        LOCAL blueH IS GR["cont"] = 2 AND GR_BLUE_SHORE AND GR_COAST["ok"]
                       AND (GR["iphase"] = 5 OR GR["iphase"] = 4 OR GR["iphase"] = 7).
        LOCAL philm IS CHOOSE GR_PHILM_E IF GR["cont"] = 1 ELSE (CHOOSE GR_BLUE_PHILM IF blueH ELSE GR_PHILM1).
        LOCAL phic IS 0.0.
        IF blueH {                          // BLUE TOWARD THE COAST (not in the FSSR): the bank toward grtlsShoreHdg's
            LOCAL phib IS philm * cstMid((sn["gam"] - GR_BLUE_GAM4) / GR_BLUE_GAMW, 0.0, 1.0).   // heading; a
            IF sn["q"] < GR_BLUE_QB { SET phib TO 0.0. }   //   steep dive / thin air wings level; in the Nz hold the
            IF GR["iphase"] = 5 {                          //   total Nz kept as GREEN's
                LOCAL nzb IS MIN(GR_NZMAX, GR_NZAVF * grtlsNz(GR["alprec"], sn["alt"], sn["vr"])) - GR["nzc"].
                LOCAL cgb IS COS(sn["gam"]).
                SET phib TO MIN(phib, CHOOSE ARCCOS(cgb / nzb) IF nzb > cgb ELSE 0.0).
            }
            LOCAL hc IS grtlsShoreHdg(sn, am).
            SET GR["hdg_c"] TO hc.
            IF hc >= 0 { SET phic TO cstMid(GR_GPHI * cstRes180(hc - sn["trk"]), 0 - phib, phib). }
        } ELSE IF GR["cont"] = 1 AND GR["iphase"] = 5 AND gpOn {     // GREEN (a deviation): bank toward the site in the Nz hold, the
            LOCAL nzm IS MIN(GR_NZMAX, GR_NZAVF * grtlsNz(GR["alprec"], sn["alt"], sn["vr"])) - GR["nzc"].   // Nz kept
            LOCAL cg IS COS(sn["gam"]).                           //   <= NZMAX and <= NZAVF x the alpha cap's
            LOCAL phinz IS 0.0.
            IF nzm > cg { SET phinz TO ARCCOS(cg / nzm). }
            SET phic TO cstMid(CHOOSE GR_RC_PHI * GR["ysgn"] IF rc ELSE GR_GPHI * gp["dpsac"], -MIN(philm, phinz),
                               MIN(philm, phinz)).
        } ELSE IF GR["iphase"] = 4 AND GR["cont"] <> 2 AND ecal {   // GRPHIC 1.2, 1.3.B, 1.3.2, set 3 (ECAL)
            LOCAL tg IS GR["tg"].
            IF GR["istp4"] = 0 AND tg["eow"] < tg["est"] {                  // 1.2: the S-turn ends
                SET GR["istp4"] TO 1.
                SET GR["dpsac_init"] TO FALSE.
                grtlsEv("ECALSTEND", sn, am).
            }
            IF (tg["eow"] + GR_ECAL_ST_LEAD * MIN(tg["deowerr"], 0.0) > tg["es"]
                AND (GR_ECAL_MSW3 <= 0 OR sn["mach"] < GR_ECAL_MSW3)) OR GR["istp4"] = 0 {   // 1.3.B (+ the lead and the Mach: deviations)
                IF GR["istp4"] <> 0 { grtlsEv("ECALST", sn, am). }
                SET GR["istp4"] TO 0.
                IF NOT GR["dpsac_init"] {                                   // 1.3.2.1
                    SET GR["dpsaci"] TO gp["dpsac"].
                    SET GR["dpsac_init"] TO TRUE.
                }
                LOCAL sgs IS CHOOSE 1.0 IF GR["dpsaci"] >= 0.0 ELSE -1.0.
                SET phic TO GR_PHISTN * sgs.                                // 1.3.2.2
                LOCAL dpsact IS 0 - MIN(GR_DPHISLP * sn["mach"] + GR_DPHIINT, GR_DPSACLMT_MAX) * sgs.   // 1.3.2.3-4
                IF (dpsact <= 0.0 AND gp["dpsac"] <= dpsact) OR (dpsact > 0.0 AND gp["dpsac"] >= dpsact) {
                    SET GR["dpsac_init"] TO FALSE.                          // 1.3.2.5: past it, back next cycle
                }
            } ELSE IF rc {
                SET phic TO GR_RC_PHI * GR["ysgn"].                         // range control: the held bank
            } ELSE {
                SET phic TO GR_GPHI * gp["dpsac"].                          // set 3: on the heading error
            }
        } ELSE IF GR["iphase"] = 4 AND GR["cont"] <> 2 {
            LOCAL tg IS GR["tg"].
            IF GR["istp4"] = 0 {
                IF tg["eow"] < tg["est"] {
                    SET GR["istp4"] TO 1.
                    grtlsEv("STEND", sn, am).
                }
            } ELSE IF tg["eow"] > tg["es"] AND sn["mach"] < GR_MSW3 AND gp["psha"] < GR_PSSTRN {
                SET GR["istp4"] TO 0.
                SET GR["ssgn"] TO -GR["ysgn"].
                IF GR["ssgn"] * cstRes180(st["psd"]) < 0.0 AND gp["psha"] < 90.0 { SET GR["ssgn"] TO -GR["ssgn"]. }
                grtlsEv("STURN", sn, am).
            }
            SET phic TO CHOOSE GR["ssgn"] * philm IF GR["istp4"] = 0 ELSE GR_GPHI * gp["dpsac"].
        }
        IF GR["ditch"] { SET phic TO 0.0. }   // the ditch wings level
        IF SS_ON AND GR["iphase"] = 4 AND am > GR_AMAXLD { SET phic TO 0.0. }   // the split-S's alpha transition wings level
        SET GR["phic_at"] TO cstMid(phic, -philm, philm).
        SET GR["bank_want"] TO taemg_bank_to_ship(GR["phic_at"]).
    }
}

// TAEM'S STATE FROM THE BOOT: GR["tg"] from the first guidance cycle on (GR["tgon"] 1), so the displays are usable from
// the start: the MM 602 pages (tdGrTick draws TAEM's page on it from phase 6) and the crew's OTT STRT / OTT MEP / SW RWY
// (the DAP window's row, live from the boot as in TAEM's acquisition phase). A DEVIATION from the orbiter: its guidance
// computes no energy state before the alpha transition (the DPS Dictionary; lib_taemdisp's header). The GRTLS guidance
// reads none of it before phase 4 (GREEN's phase-5 bank keeps its own GR["gp"]); the HAC side follows phase 4's rule
// (y's sign at each cycle) until the crew or GREEN sets one (GR["ysgn"]); at 5 -> 4 phase 4's state starts afresh, with
// the crew's choices (GR_TG_CREW) kept, and landRun takes them too (GR["dmcrew"]). Not in a BLUE (no TAEM) nor the
// split-S before phase 4 (ssPick picks the end and the side).
GLOBAL GR_TG_CREW IS LIST("strt", "nep", "dm_msg", "dm_msg0", "rwy_sw", "dm_why").

// THE TAEM DISPLAY'S STATE IN C# (ADDONS:KALS:GRTG): with GR_TG_CS and the addon installed, phases 6 / 5's grtlsTgPre and
// phase 4's pass (GTP, TGCOMP, ECAL's TGCOMP 2.1.1), each with grtlsTgDm, are one call into the coprocessor's TAEM guidance
// (Taemg.taemg_grtls: the same functions as taemg.ks's), which writes tg, GR["tgon"], GR["ysgn"], GR["dmcrew"] and
// GR["gpd"] as these do; kOS writes the crew press's event line. ANY addon failure turns it off for the rest of the
// flight (GR_TG_CS_ERR) and kOS flies that same call.
IF NOT (DEFINED GR_TG_CS) { GLOBAL GR_TG_CS IS TRUE. }   // TRUE: the addon keeps the TAEM display's state
GLOBAL GR_TG_CS_SET IS 0.         // 0 = not tried yet, 1 = ready, -1 = off for the flight
GLOBAL GR_TG_CS_ERR IS "".        // why it is off

FUNCTION grtlsTgCsOff {
    PARAMETER why.
    SET GR_TG_CS_ERR TO why.
    SET GR_TG_CS TO FALSE.
    SET GR_TG_CS_SET TO -1.
}

FUNCTION grtlsTgCs {                        // -> the addon's LEXICON(gp, ev, req) when it took the call, else ""
    PARAMETER mode, st, bank, brate, ecal, hdot.
    IF NOT GR_TG_CS { RETURN "". }
    IF GR_TG_CS_SET = 0 {
        LOCAL why IS "".
        IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
        ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
        ELSE IF NOT ADDONS:KALS:HASSUFFIX("GRTG") { SET why TO "the KAL/S addon has no GRTG (an older KalsCoproc.dll)". }
        ELSE IF NOT ADDONS:KALS:GRTGSETUP(OPEN("0:/lib/taemg_const.ks"):READALL:STRING,
                                          OPEN("0:/lib/solq_atm_data.ks"):READALL:STRING) {
            SET why TO "GRTGSETUP: " + ADDONS:KALS:GRTGERROR.
        }
        IF why = "" { SET GR_TG_CS_SET TO 1. } ELSE { grtlsTgCsOff(why). RETURN "". }
    }
    LOCAL tcr IS ADDONS:KALS:GRTG(LIST(mode, GR, st, grtlsTgGl(), bank, brate, ecal, hdot, TG_OVERHEAD_DEFAULT, GR_ECOMPG)).
    IF NOT tcr:ISTYPE("Lexicon") {
        grtlsTgCsOff("GRTG: " + tcr).
        RETURN "".
    }
    IF tcr["ev"] = "ok" {
        LOCAL tg IS GR["tg"].
        noteEvent("GRTLS OTT: the crew's " + tcr["req"] + " in phase " + GR["iphase"] + " (" + tg["dm_why"] + "): HAC ysgn "
                  + tg["ysgn"] + ", strt " + tg["strt"] + ", nep " + tg["nep"] + ", psha " + ROUND(tcr["gp"]["psha"])).
    } ELSE IF tcr["ev"] = "rej" {
        noteEvent("GRTLS OTT: the crew's " + tcr["req"] + " refused (" + GR["tg"]["dm_rej"] + ")").
    }
    RETURN tcr.
}

FUNCTION grtlsTgPre {                       // phases 6 / 5: TAEM's state on the display's HAC (GTP + TGCOMP)
    PARAMETER st, bank, brate.
    LOCAL same IS CHOOSE 1.0 IF st["y"] >= 0.0 ELSE -1.0.
    LOCAL ys IS CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same.   // phase 4's rule until a side is set
    IF GR["ysgn"] <> 0 { SET ys TO GR["ysgn"]. }
    IF GR["tgon"] = 0 {
        LOCAL p0 IS taemg_gtp(st, ys, TG_IPH_ACQ, TG_RFMX, 0.0, TRUE, TG_R2)["psha"].
        SET GR["tg"] TO taemg_init(st, ys, TG_RFMX, taemg_gtp(st, ys, TG_IPH_ACQ, TG_RFMX, p0, TRUE, TG_R2)["psha"],
                                   taemg_ship_to_bank(bank), taemg_ship_to_bank(brate)).
        SET GR["tgon"] TO 1.
    }
    LOCAL tg IS GR["tg"].
    IF tg["ysgn"] <> ys {                   // the rule's side moved with y's sign: the HAC turn afresh
        SET tg["ysgn"] TO ys.
        SET tg["psha_prev"] TO 0.0.
    }
    LOCAL gp IS taemg_gtp(st, tg["ysgn"], TG_IPH_ACQ, tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"]).
    SET tg["psha_prev"] TO gp["psha"].
    taemg_comp(tg, st, gp).
    SET tg["ecompk"] TO 0.0.               // the raw EOW (no TGCOMP 2.1.1 before phase 4)
    grtlsTgDm(tg, st, gp, 0.0).
}

FUNCTION grtlsTgGl {                        // the TAEM globals the addon's GRTG / GRTGE5 read
    RETURN LIST(TG_X_AIM, TG_XALI_X, TG_R2MAX, tgDsbMax, TG_DSBSUP, TG_DSBLIM, TG_DSBNOM, TG_DOWNMODE_POLICY).
}

FUNCTION grtlsRcE5 {                        // range control's EOW - EN in phase 5: a throwaway TGINIT + GTP + TGCOMP on
    PARAMETER st, psha.                     //   phase 5's HAC (side GR["ysgn"], its psha); the addon's GRTGE5 when it
    IF GR_TG_CS AND GR_TG_CS_SET = 1 {      //   has it (a failure turns GRTG off, as grtlsTgCs's)
        IF ADDONS:KALS:HASSUFFIX("GRTGE5") {
            LOCAL e5r IS ADDONS:KALS:GRTGE5(LIST(st, grtlsTgGl(), GR["ysgn"], psha)).
            IF e5r:ISTYPE("Scalar") { RETURN e5r. }
            grtlsTgCsOff("GRTGE5: " + e5r).
        }
    }
    LOCAL tg5 IS taemg_init(st, GR["ysgn"], TG_RFMX, psha, 0.0, 0.0).
    LOCAL gp5 IS taemg_gtp(st, GR["ysgn"], TG_IPH_ACQ, tg5["rf"], psha, tg5["nep"], tg5["r2"]).
    taemg_comp(tg5, st, gp5).
    RETURN tg5["eow"] - tg5["en"].
}

FUNCTION grtlsTgDm {                        // after TGCOMP: the fields the OTT row reads (taemg_cycle's probe, MEP and
    PARAMETER tg, st, gp, eadj.             //   OHALRT lines), then a crew press (taemg_crew_act, as TAEM's acquisition
    taemg_probe(tg, st, gp).                //   phase takes it); eadj: ECAL's hdot for its TGCOMP 2.1.1. -> the gtp
    SET tg["mep"] TO (tg["eow"] < tg["emep"] AND tg["nep"] AND tg["mep_avail"]).
    SET tg["ohalrt"] TO (tg["eow"] < tg["emoh"] AND tg["strt_avail"] AND gp["psha"] > TG_PSOHAL AND gp["rpred"] > TG_RMOH).
    IF tg["dm_crew"] <> "" {
        LOCAL req IS tg["dm_crew"].
        taemg_crew_act(tg, st, gp).
        IF tg["dm_rej"] = "" {
            SET GR["ysgn"] TO tg["ysgn"].
            SET GR["dmcrew"] TO TRUE.
            SET gp TO taemg_gtp(st, tg["ysgn"], TG_IPH_ACQ, tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"]).
            SET tg["psha_prev"] TO gp["psha"].
            taemg_comp(tg, st, gp).
            IF eadj <> 0 { SET tg["eow"] TO tg["eow"] + GR_ECOMPG * tg["eow"] * eadj. }
            taemg_probe(tg, st, gp).
            noteEvent("GRTLS OTT: the crew's " + req + " in phase " + GR["iphase"] + " (" + tg["dm_why"] + "): HAC ysgn "
                      + tg["ysgn"] + ", strt " + tg["strt"] + ", nep " + tg["nep"] + ", psha " + ROUND(gp["psha"])).
        } ELSE {
            noteEvent("GRTLS OTT: the crew's " + req + " refused (" + tg["dm_rej"] + ")").
        }
    }
    SET GR["gpd"] TO gp.
    RETURN gp.
}

FUNCTION grtlsDmPress {                     // ops6q's loop, on a press (dDmReq): OTT STRT / MEP at the next guidance
    LOCAL req IS dDmReq.                    //   cycle (tg["dm_crew"]); SW RWY now, the frame first (as landRun's);
    SET dDmReq TO "".                       //   TRUE when the runway changed (ops6q applies it: RWY_NAME, the aim)
    IF GR["tgon"] = 0 OR GR["cont"] = 2 {
        IF req = "site" { SET dSiteStep TO 99. }   // the label back from "..."
        noteEvent("GRTLS OTT: the crew's " + req + " ignored (no TAEM state in phase " + GR["iphase"] + ")").
        RETURN FALSE.
    }
    LOCAL tg IS GR["tg"].
    IF req = "site" {                       // the crew's site switch (lib_land ldSiteGo: SW RWY's path)
        LOCAL sg IS ldSiteGo(tg).
        noteEvent("GRTLS " + sg[1] + " (the crew's, phase " + GR["iphase"] + ")").
        IF NOT sg[0] { RETURN FALSE. }
        SET GR["rwy"] TO ldRwy["name"].
        SET GR["ysgn"] TO tg["ysgn"].
        SET GR["dmcrew"] TO TRUE.
        IF SS_ON { SET SS_ENDS TO LIST(ldRwy["name"], CHOOSE dRwyAlt IF dRwyAlt <> "" ELSE ldRwy["name"]). }   // ssPick's
        RETURN TRUE.                        //   ends at the new site
    }
    IF req <> "rwy" {
        SET tg["dm_crew"] TO req.
        RETURN FALSE.
    }
    LOCAL rej IS taemg_rwy_rej(tg, dRwyAlt <> "").
    IF rej <> "" {
        noteEvent("GRTLS SW RWY: refused (" + rej + ")").
        RETURN FALSE.
    }
    LOCAL old IS ldRwy["name"].
    LOCAL nw IS dRwyAlt.
    ldSwitchRunway(nw).
    SET GR["rwy"] TO nw.
    LOCAL st IS ldState().
    taemg_rwy_switch(tg, st, nw).
    SET GR["ysgn"] TO tg["ysgn"].
    SET GR["dmcrew"] TO TRUE.
    noteEvent("GRTLS SW RWY " + old + " -> " + nw + " (the crew's, phase " + GR["iphase"] + "): HAC ysgn " + tg["ysgn"]
              + ", x " + ROUND(st["x"]) + " y " + ROUND(st["y"]) + " m in the new frame").
    RETURN TRUE.
}

FUNCTION grtlsDmShow {                      // after each guidance cycle: the OTT row (lib_dap's dapDmShow), grey without
    IF dBtnStrt:ISTYPE("Scalar") { RETURN. }    //   TAEM's state (a BLUE, the split-S before phase 4, phase 7)
    IF GR["tgon"] = 1 AND GR["cont"] <> 2 AND GR["iphase"] <> 7 AND GR["iphase"] <> 8 {
        dapDmShow(GR["tg"]).
    } ELSE {
        FOR bt IN LIST(dBtnStrt, dBtnMep, dBtnRwy) { SET bt:ENABLED TO FALSE. }
        IF NOT dBtnSite:ISTYPE("Scalar") { SET dBtnSite:ENABLED TO FALSE. }   // the site button too
    }
}

FUNCTION grtlsDitch {                       // TRUE once the ditch's flare is on (latched when the height above the
    PARAMETER vrel, gam.                    //   water is at most GR_DITCH_TAU x the sink; wings level from then)
    IF NOT GR_DITCH { RETURN FALSE. }
    IF NOT GR["ditch"] {
        LOCAL sink IS 0 - vrel * SIN(gam).
        IF sink <= 0 OR ALT:RADAR > GR_DITCH_TAU * sink { RETURN FALSE. }
        SET GR["ditch"] TO TRUE.
        SET GR["phic_at"] TO 0.0.
        SET GR["bank_want"] TO taemg_bank_to_ship(0.0).
        noteEvent("GRTLS DITCH (ours): the flare at " + ROUND(ALT:RADAR) + " m above the water, sink " + ROUND(sink, 1)
                  + " m/s, " + ROUND(vrel) + " m/s, alpha " + ROUND(GR["acmd"], 1) + " (<= " + GR_DITCH_ALPMAX + "), wings level").
    }
    RETURN TRUE.
}

FUNCTION grtlsBlueEnd {                     // CONT BLUE's loop end in ops6q: in the water (GR_DITCH), else GR_BAIL_END
    IF NOT GR_DITCH { RETURN ALTITUDE < GR_BAIL_END. }
    RETURN SHIP:STATUS = "SPLASHED" OR SHIP:STATUS = "LANDED" OR ALT:RADAR < 1.
}

FUNCTION grtlsFcsK {                        // kOS's own (the dispatcher: grtlsFcs) each pass: the alpha command slewed toward ALPCMD (6, 4) or the Nz's alpha (5)
    PARAMETER dt, altm, vrel, gam, bank.
    LOCAL tgt IS GR["alpcmd"].
    IF SS_ON AND (GR["iphase"] = 8 OR GR["iphase"] = 5) {   // the split-S: the body-normal Nz SS_NZ, alpha <= SS_ALPHA
        SET tgt TO grtlsAlphaForNz(SS_NZ, altm, vrel, SS_ALPHA_LO, SS_ALPHA).
    } ELSE IF GR["iphase"] = 7 AND grtlsDitch(vrel, gam) {   // the ditch's flare, hdot -MAX(HDTD, h / TAU)
        LOCAL hdc IS 0 - MAX(GR_DITCH_HDTD, ALT:RADAR / GR_DITCH_TAU).
        SET tgt TO grtlsAlphaForNz(COS(gam) / COS(bank) + GR_DITCH_K * (hdc - vrel * SIN(gam)) / 9.80665, altm, vrel,
                                   GR_ALPHA_NZ_LO, GR_DITCH_ALPMAX).
    } ELSE IF GR["iphase"] = 5 OR GR["iphase"] = 7 {
        LOCAL amax IS GR_BAIL_ALPMAX.
        IF GR["iphase"] = 5 { SET amax TO GR["alprec"]. }
        SET tgt TO grtlsAlphaForNz(GR["nzc"] + COS(gam) / COS(bank), altm, vrel, GR_ALPHA_NZ_LO, amax).
    } ELSE IF GR_NZ_ALIM > 0 AND (GR["cont"] > 0 OR (GR_NZ_ALIM_RTLS AND NOT SS_ON))
        AND (GR["iphase"] = 4 OR GR["iphase"] = 6) {   // limiter A (the RTLS too: GR_NZ_ALIM_RTLS)
        SET tgt TO MIN(tgt, grtlsAlphaForNz(GR_NZ_ALIM, altm, vrel, GR_ALPHA_NZ_LO, MAX(tgt, GR_ALPHA_NZ_LO))).
    }
    SET GR["acmd"] TO GR["acmd"] + cstMid(tgt - GR["acmd"], -GR_ALPHA_RATE * dt, GR_ALPHA_RATE * dt).
}

FUNCTION ssEndE {                           // THE SPLIT-S: EOW - EN at phase 4's start, TAEM's state st on a loaded
    PARAMETER st, ysgn, bank, brate, ec IS 0.0.   //   runway end and the HAC side ysgn (TAEM's init as phase 4's below);
                                            //   ec = GR_ECOMPG x HDOT: TGCOMP 2.1.1's EOW (grPickGreen; 0 = none)
    LOCAL p0 IS taemg_gtp(st, ysgn, TG_IPH_ACQ, TG_RFMX, 0.0, TRUE, TG_R2)["psha"].
    LOCAL tg IS taemg_init(st, ysgn, TG_RFMX, taemg_gtp(st, ysgn, TG_IPH_ACQ, TG_RFMX, p0, TRUE, TG_R2)["psha"],
                           taemg_ship_to_bank(bank), taemg_ship_to_bank(brate)).
    LOCAL gp IS taemg_gtp(st, ysgn, TG_IPH_ACQ, tg["rf"], tg["psha_prev"], tg["nep"], tg["r2"]).
    SET tg["psha_prev"] TO gp["psha"].
    taemg_comp(tg, st, gp).
    RETURN tg["eow"] + ec * tg["eow"] - tg["en"].
}

FUNCTION ssScore {                          // 0 inside TAEM's corridor (EN + SS_EMIN_D .. EN + SS_EMAX_D), else minus the
    PARAMETER de.                           //   distance to it (de: EOW - EN, m)
    RETURN 0.0 - MAX(0.0, SS_EMIN_D - de) - MAX(0.0, de - SS_EMAX_D).
}

FUNCTION ssBetter {                         // the pair with EOW - EN de beats the best so far (pde): the higher ssScore,
    PARAMETER de, pde.                      //   then the higher EOW - EN
    IF ssScore(de) > ssScore(pde) { RETURN TRUE. }
    IF ssScore(de) = ssScore(pde) AND de > pde { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION ssPick {                           // THE SPLIT-S's runway END and HAC SIDE at phase 4's start: of the 4 pairs
    PARAMETER bank, brate.                  //   (SS_ENDS[0] +1 / -1, SS_ENDS[1] +1 / -1) the best by ssBetter (a tie: the
    ssLoadEnd(SS_ENDS[0]).                  //   first); GR["ysgn"] = its side (phase 4's init takes it),
    LOCAL st0 IS ldState().                 //   TG_OVERHEAD_DEFAULT set so the rule gives it (the HSIT, landRun);
    LOCAL e0 IS ssEndE(st0, 1, bank, brate).   // -> TAEM's state on the end (loaded)
    LOCAL e1 IS ssEndE(st0, -1, bank, brate).
    ssLoadEnd(SS_ENDS[1]).
    LOCAL st1 IS ldState().
    LOCAL e2 IS ssEndE(st1, 1, bank, brate).
    LOCAL e3 IS ssEndE(st1, -1, bank, brate).
    SET GR["ss_e"] TO LIST(e0, e1, e2, e3).
    LOCAL k IS 0.
    LOCAL pde IS e0.
    IF ssBetter(e1, pde) { SET k TO 1. SET pde TO e1. }
    IF ssBetter(e2, pde) { SET k TO 2. SET pde TO e2. }
    IF ssBetter(e3, pde) { SET k TO 3. SET pde TO e3. }
    LOCAL rw IS SS_ENDS[0].
    IF k > 1 { SET rw TO SS_ENDS[1]. }
    LOCAL ys IS 1.
    IF k = 1 OR k = 3 { SET ys TO -1. }
    SET GR["rwy"] TO rw.
    SET GR["ysgn"] TO ys.
    ssLoadEnd(rw).
    LOCAL st IS ldState().
    LOCAL same IS CHOOSE 1 IF st["y"] >= 0.0 ELSE -1.
    SET TG_OVERHEAD_DEFAULT TO ys <> same.
    RETURN st.
}

FUNCTION grPickBetter {                     // grPickGreen's order: the pair with EOW - EN de beats the best so far (pde):
    PARAMETER de, pde.                      //   the higher ssScore; the same score INSIDE the corridor (0): the smaller
    LOCAL s IS ssScore(de).                 //   |EOW - EN| (GR_PICK_NOM FALSE: ssBetter's, the higher EOW - EN)
    LOCAL ps IS ssScore(pde).
    IF s <> ps { RETURN s > ps. }
    IF GR_PICK_NOM AND s = 0.0 { RETURN ABS(de) < ABS(pde). }
    RETURN de > pde.
}

FUNCTION grPickGreen {                      // A GREEN's runway END and HAC SIDE at phase 4's start (GR_PICK_DE's paragraph):
    PARAMETER st, bank, brate, ec.          //   st = TAEM's state on the end flown, ec = GR_ECOMPG x HDOT (0 without ECAL)
    LOCAL rw0 IS ldRwy["name"].             //   -> TAEM's state on the end taken; GR["gpw"] = the event's words when it
    LOCAL rw1 IS ldOtherEnd(rw0).           //   scored the 4 pairs ("" when the pair flown was in or above the corridor)
    IF rw1 = "" { RETURN st. }
    LOCAL same IS CHOOSE 1 IF st["y"] >= 0.0 ELSE -1.
    LOCAL ys0 IS CHOOSE -same IF TG_OVERHEAD_DEFAULT ELSE same.
    IF GR["ysgn"] <> 0 { SET ys0 TO GR["ysgn"]. }
    LOCAL k0 IS CHOOSE 0 IF ys0 > 0 ELSE 1.
    LOCAL e0 IS ssEndE(st, 1, bank, brate, ec).
    LOCAL e1 IS ssEndE(st, -1, bank, brate, ec).
    IF (CHOOSE e0 IF k0 = 0 ELSE e1) >= SS_EMIN_D { RETURN st. }
    IF ssEndE(st, ys0, bank, brate) < GR_DEOW_REACH { RETURN st. }   // the reach check's BLUE stands
    ssLoadEnd(rw1).
    LOCAL st1 IS ldState().
    LOCAL ee IS LIST(e0, e1, ssEndE(st1, 1, bank, brate, ec), ssEndE(st1, -1, bank, brate, ec)).
    LOCAL k IS 0.                           // grPickBetter over (rw0 +1, rw0 -1, rw1 +1, rw1 -1): a tie, the first
    FOR j IN LIST(1, 2, 3) { IF grPickBetter(ee[j], ee[k]) { SET k TO j. } }
    LOCAL take IS k <> k0 AND ssScore(ee[k]) - ssScore(ee[k0]) > GR_PICK_DE.
    IF NOT take { SET k TO k0. }
    LOCAL ys IS CHOOSE 1 IF k = 0 OR k = 2 ELSE -1.
    ssLoadEnd(rw0).                         // the end flown back: ldSwitchRunway's other end (dRwyAlt) is the one left
    LOCAL stk IS st.
    IF k > 1 {
        ldSwitchRunway(rw1).
        SET stk TO st1.
    }
    SET GR["ss_e"] TO ee.
    SET GR["ysgn"] TO ys.
    IF take {
        SET GR["rwy"] TO ldRwy["name"].
        SET GR["gpk"] TO TRUE.
        SET SS_OVH0 TO TG_OVERHEAD_DEFAULT.
        SET TG_OVERHEAD_DEFAULT TO ys <> (CHOOSE 1 IF stk["y"] >= 0.0 ELSE -1).
    }
    SET GR["gpw"] TO (CHOOSE "TAKEN" IF take ELSE "KEPT") + ": RUNWAY " + ldRwy["name"] + ", HAC ysgn " + ys + " (was "
                     + rw0 + " " + ys0 + "); EOW-EN at phase 4: " + rw0 + " +1 " + ROUND(ee[0]) + " / -1 " + ROUND(ee[1])
                     + " m, " + rw1 + " +1 " + ROUND(ee[2]) + " / -1 " + ROUND(ee[3]) + " m (TAEM's corridor " + SS_EMIN_D
                     + " .. +" + SS_EMAX_D + ", the margin " + GR_PICK_DE + ")".
    RETURN stk.
}

// ---------------------------------------------------------------- BLUE TOWARD THE COAST (not in the FSSR)
FUNCTION grtlsBluePick {                    // the crew's BLUE or the default (ops6q's choice): applied at the top of the
    SET GR["pick"] TO TRUE.                 //   next guidance cycle (an RTLS only: GR["cont"] 0)
}

FUNCTION grtlsShoreHdg {                    // the heading (deg) toward the line GR_BLUE_DOFF off the nearest coast
    PARAMETER sn, am.                       //   (lib_coast cstShoreHdg on GR's search state); -1 off the table:
    LOCAL first IS GR["sh_t"] < 0.          //   wings level. The first search says SHORE
    LOCAL hc IS cstShoreHdg(GR, sn).
    IF first { grtlsEv("SHORE", sn, am). }
    RETURN hc.
}

FUNCTION grtlsCoastLoad {                   // the coast table: lib_coast's cstLoad; GR_COAST = CST, TRUE when
    PARAMETER cpath.                        //   read whole
    LOCAL ok IS cstLoad(cpath).
    SET GR_COAST TO CST.
    RETURN ok.
}

// ---------------------------------------------------------------- OPS 6's glue (the ship's state, the events, the log)
FUNCTION grtlsGam {
    PARAMETER vrel.
    RETURN ARCSIN(MAX(-1, MIN(1, SHIP:VERTICALSPEED / MAX(vrel, 1)))).
}

// the speed of sound (m/s) at the highest altitude with pressure and density (1 km steps down from EPR_ATM), once
FUNCTION grtlsSosTop {
    IF GR_SOS_TOP > 0 { RETURN GR_SOS_TOP. }
    LOCAL h IS EPR_ATM.
    UNTIL h <= 0 {
        LOCAL ps IS eprPres(h).
        LOCAL rh IS eprRho(h).
        IF ps > 0 AND rh > 0 {
            SET GR_SOS_TOP TO SQRT(EPR_GAMMA * ps / rh).
            RETURN GR_SOS_TOP.
        }
        SET h TO h - 1000.
    }
    SET GR_SOS_TOP TO 300.
    RETURN GR_SOS_TOP.
}

FUNCTION grtlsNzMeas {                      // the measured body-normal Nz (g): the DAP's grdNzM, else the finite-difference
    PARAMETER am, nzmod.                    //   lift and drag, else the model's nzmod
    IF (DEFINED grdOn) AND grdOn { RETURN grdNzM. }   // (lib_grtls loads without lib_grdap / lib_vehicle too)
    IF (DEFINED FD_LIFT) AND FD_LIFT > 0 { RETURN (FD_LIFT * COS(am) + FD_DRAG * SIN(am)) / EPR_G0. }
    RETURN nzmod.
}

FUNCTION grtlsSense {                       // the sensed state: the model's Mach, the measured Nz (nz_mod: the model's)
    PARAMETER am.
    LOCAL altm IS ALTITUDE.
    LOCAL vrel IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL mach IS eprMach(altm, vrel).
    IF mach <= 0 AND vrel > 0 { SET mach TO vrel / grtlsSosTop(). }   // above the air (eprMach 0 there)
    LOCAL sn IS LEXICON("alt", altm, "vr", vrel, "hdot", SHIP:VERTICALSPEED, "gam", grtlsGam(vrel),
                        "mach", mach, "nz_mod", grtlsNz(am, altm, vrel), "q", grtlsQ(altm, vrel)).
    SET sn["nz"] TO CHOOSE grtlsNzMeas(am, sn["nz_mod"]) IF GR_NZ_MEAS ELSE sn["nz_mod"].
    IF GR_BLUE_SHORE AND GR_COAST["ok"] {   // BLUE toward the coast: the time, the position, at sea, the ground track
        LOCAL geo IS SHIP:GEOPOSITION.
        SET sn["t"] TO TIME:SECONDS.
        SET sn["lat"] TO geo:LAT.
        SET sn["lng"] TO geo:LNG.
        SET sn["sea"] TO geo:TERRAINHEIGHT < 0.   // (the offline model: the biome map's ocean; here the terrain below sea level)
        SET sn["trk"] TO cstTrk().
    }
    RETURN sn.
}

// THE SPLIT-S's glue (the ship's state: kOS vectors; the turn plane at the local azimuth, as the offline model's)
FUNCTION ssSet {                            // before grtlsStart: the split-S on, the turn plane's heading az0 (deg; < 0:
    PARAMETER az0.                          //   the ground track's now); TG_OVERHEAD_DEFAULT kept in SS_OVH0 (ssPick sets
    SET SS_ON TO TRUE.                      //   it, ops6q puts it back after landRun: a GLOBAL outlives the program)
    SET SS_OVH0 TO TG_OVERHEAD_DEFAULT.
    IF az0 < 0 {
        LOCAL upv IS SHIP:UP:VECTOR.
        LOCAL vs IS SHIP:VELOCITY:SURFACE.
        LOCAL vh IS vs - VDOT(vs, upv) * upv.
        LOCAL east IS VCRS(upv, SHIP:NORTH:VECTOR).
        SET az0 TO MOD(ARCTAN2(VDOT(vh, east), VDOT(vh, SHIP:NORTH:VECTOR)) + 360, 360).
    }
    SET SS_AZ0 TO az0.
}

FUNCTION ssLiftV {                          // the turn plane's lift direction: n x v with n = up x al, = al (up . v) -
    PARAMETER upv, vh, al.                  //   up (al . v): toward the ground while the path is above straight down
    RETURN (al * VDOT(upv, vh) - upv * VDOT(al, vh)):NORMALIZED.
}

FUNCTION ssLift {                           // phase 8's lift direction now (the plane of SS_AZ0 here)
    RETURN ssLiftV(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE:NORMALIZED, HEADING(SS_AZ0, 0):VECTOR).
}

FUNCTION ssBankEq {                         // the bank (the ship's, + = left) whose lift, entrySteer's ANGLEAXIS(bank, v)
    LOCAL upv IS SHIP:UP:VECTOR.            //   x up_perp, points as ssLift's: phase 5's start (the same ANGLEAXIS
    LOCAL vh IS SHIP:VELOCITY:SURFACE:NORMALIZED.   //   decides the sign)
    LOCAL upp IS (upv - VDOT(upv, vh) * vh):NORMALIZED.
    LOCAL lp IS ssLift().
    LOCAL bq IS VANG(upp, lp).
    IF VANG(ANGLEAXIS(0 - bq, vh) * upp, lp) < VANG(ANGLEAXIS(bq, vh) * upp, lp) { SET bq TO 0 - bq. }
    RETURN bq.
}

FUNCTION ssSense {                          // grtlsSense's lexicon + the path angle in the turn plane (0 level ahead, -90
    PARAMETER sn.                           //   straight down, -180 level heading back; unwrapped past -180) + ssBankEq
    LOCAL pa IS ARCTAN2(SHIP:VERTICALSPEED, VDOT(HEADING(SS_AZ0, 0):VECTOR, SHIP:VELOCITY:SURFACE)).
    IF GR["angp"] < 900 {
        IF pa - GR["angp"] > 180 { SET GR["unw"] TO GR["unw"] - 360. }
    }
    SET GR["angp"] TO pa.
    SET sn["ang"] TO pa + GR["unw"].
    SET sn["beq"] TO ssBankEq().
}

FUNCTION ssSteer {                          // phase 8's attitude: alpha GR["acmd"] about the wind toward the lift, the top
    LOCAL vh IS SHIP:VELOCITY:SURFACE:NORMALIZED.   //   on the lift (heads down while it points down), sideslip 0
    LOCAL lh IS ssLift().
    RETURN LOOKDIRUP(COS(GR["acmd"]) * vh + SIN(GR["acmd"]) * lh, lh).
}

FUNCTION ssLoadEnd {                        // the runway end rw as grtlsStart loads one (ldState's frame + taemg's aim)
    PARAMETER rw.
    SET ldRwy TO ldLoadRunway(rw).
    taemg_set_aim(rw, ldAimLaw()).
}

FUNCTION grtlsStart {                       // from OPS 6 after the ET separation: the runway, the state, the log
    PARAMETER rwyName, a0, logPath.
    SET GR_NZK TO 1.0.
    SET ldRwy TO ldLoadRunway(rwyName).     // ldState (TAEM's frame) + taemg's aim, as landRun sets them
    taemg_set_aim(rwyName, ldAimLaw()).
    IF SS_ON {
        IF SS_ENDS:LENGTH < 2 { SET SS_ENDS TO LIST(rwyName, rwyName). }
    }
    SET GR TO grtlsReset(a0, TIME:SECONDS).
    SET GR_LOG TO logPath.
    IF GR_LOG <> "" {
        LOG "met_s,iphase,alt_m,vr_ms,mach,hdot_fts,gam,alpha,acmd,alpcmd,nz,nz_fd,nzc_tot,bank,bank_want,gralpr,dgrnz,"
            + "hdmax_fts,psha,eow,en,es,est,istp4" + (CHOOSE ",ang,beq,mass_t" IF SS_ON ELSE "")
            + (CHOOSE ",lat,lng,coast_km,hdg_c,trk,sea" IF (GR_BLUE_SHORE AND GR_COAST["ok"]) ELSE "") TO GR_LOG.
    }
    LOCAL vrel IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL mw IS "RTLS: the GRTLS to " + rwyName + " (FSSR 4.8, the intact path)".
    IF GR_CONT = 1 { SET mw TO "CONT GREEN (2EO, SCOM 6.7) to " + rwyName + ": the GRTLS phases + the ECAL bank". }
    IF GR_CONT = 1 AND GR_ECAL {
        SET mw TO mw + " + ECAL (FSSR 4.8 GRTRN 3.3 / 4.1; the pull-out cap " + (CHOOSE (GR_ECAL_PPRT + " g") IF GR_ECAL_PPRT > 0
                   ELSE "off") + ")".
    }
    IF GR_CONT = 2 { SET mw TO "CONT BLUE (2EO, no site): the GRTLS phases, then the bailout hold below Mach " + GR_BAIL_MACH. }
    IF GR_CONT = 2 AND GR_BLUE_SHORE AND GR_COAST["ok"] { SET mw TO mw + ", banked toward the coast (ours)". }
    IF SS_ON {
        noteEvent("OPS 6 SPLIT-S (ours: AIAA 87-2398's scheme, his choice) to " + SS_ENDS[0] + " / " + SS_ENDS[1]
                  + ": phase 8 heads down in the plane of " + ROUND(SS_AZ0, 1) + " deg, alpha " + ROUND(a0, 1)
                  + " -> the Nz " + SS_NZ + " g (alpha <= " + SS_ALPHA + "); h " + ROUND(ALTITUDE / 1000, 1) + " km, "
                  + ROUND(vrel) + " m/s, Mach " + ROUND(eprMach(ALTITUDE, vrel), 2) + ", hdot "
                  + ROUND(SHIP:VERTICALSPEED / GR_FT) + " ft/s, " + ROUND(SHIP:MASS, 2) + " t").
    } ELSE {
        noteEvent("OPS 6 " + mw + ": phase 6, alpha " + ROUND(a0, 1)
                  + " -> " + GR_ALPREC + " wings level; h " + ROUND(ALTITUDE / 1000, 1) + " km, " + ROUND(vrel)
                  + " m/s, Mach " + ROUND(eprMach(ALTITUDE, vrel), 2) + ", hdot " + ROUND(SHIP:VERTICALSPEED / GR_FT)
                  + " ft/s").
    }
}

FUNCTION grtlsCycle {                       // one pass of OPS 6's RTLS loop: the guidance when due, then the alpha slew
    PARAMETER dt, bank, brate.              // bank / brate: bankNow / BANK_RATE_NOW (the ship's, + = left)
    LOCAL am IS ldAlphaNow().
    IF TIME:SECONDS >= GR["tnext"] {
        LOCAL sn IS grtlsSense(am).
        IF GR_NZ_MEAS AND sn["nz_mod"] >= GR_NZK_MIN {   // the model's scale from the measured Nz
            SET GR_NZK TO cstMid(GR_NZK + (sn["nz"] * GR_NZK / sn["nz_mod"] - GR_NZK) * MIN(1, GR_DTG / GR_NZK_TAU),
                                 GR_NZK_LO, GR_NZK_HI).
        }
        IF SS_ON { ssSense(sn). }           // the split-S: the path angle in its plane, the equivalent bank
        grtlsGuid(sn, am, bank, brate, ldState()).
        grtlsLog(sn, am, bank).
        SET GR["tnext"] TO GR["tnext"] + GR_DTG.
        IF GR["tnext"] < TIME:SECONDS { SET GR["tnext"] TO TIME:SECONDS + GR_DTG. }
    }
    IF NOT GR["done"] {
        LOCAL vrel IS SHIP:VELOCITY:SURFACE:MAG.
        grtlsFcs(dt, ALTITUDE, vrel, grtlsGam(vrel), bank).
    }
}

FUNCTION grtlsAt {
    PARAMETER sn.
    RETURN "; Mach " + ROUND(sn["mach"], 2) + ", h " + ROUND(sn["alt"] / 1000, 1) + " km, " + ROUND(sn["vr"]) + " m/s, hdot "
           + ROUND(sn["hdot"] / GR_FT) + " ft/s, alpha ".
}

FUNCTION grtlsEv {                          // the events line
    PARAMETER kind, sn, am.
    LOCAL tail IS grtlsAt(sn) + ROUND(am, 1) + ", T+" + ROUND(TIME:SECONDS - GR["t0"], 1) + " s, model Nz "
                   + ROUND(sn["nz_mod"], 2) + " (NZK " + ROUND(GR_NZK, 3) + ")".
    IF kind = "P5" {
        noteEvent("GRTLS PHASE 5 (the Nz hold, " + ROUND(GR_GRNZC1 + 1.0 + GR["dgrnz"], 2) + " g): Nz "
                  + ROUND(sn["nz"], 2) + " > NZSW1 + DGRNZ " + ROUND(GR_NZSW1 + GR["dgrnz"], 2) + ", HDMAX "
                  + ROUND(GR["hdmax"]) + " ft/s" + tail).
    } ELSE IF kind = "P5TRAP" {
        noteEvent("GRTLS PHASE 5 BY THE ALPHA TRAP (alpha under " + GR_ALP_TRAP_TRIG + " after " + GR_ALP_TRAP_ARM + ")" + tail).
    } ELSE IF kind = "ARM5" {
        noteEvent("GRTLS: THE NZ HOLD ARMED (its exits wait for the load): Nz " + ROUND(sn["nz"], 2)
                  + " > NZSW1 + DGRNZ " + ROUND(GR_NZSW1 + GR["dgrnz"], 2) + tail).
    } ELSE IF kind = "GUARD" {
        noteEvent("GRTLS: THE HOLD GUARD (ours): the sink reversed with alpha <= GRALPR " + ROUND(GR["gralpr"], 1) + tail).
    } ELSE IF kind = "P4" {
        noteEvent("GRTLS PHASE 4 (the alpha transition to GRALPR " + ROUND(GR["gralpr"], 1) + "): HAC ysgn " + GR["ysgn"]
                  + ", psha " + ROUND(GR["tg"]["psha_prev"]) + " deg, EOW-EN " + ROUND(GR["tg"]["eow"] - GR["tg"]["en"])
                  + " m" + tail).
    } ELSE IF kind = "STURN" {
        noteEvent("GRTLS S-TURN (EOW " + ROUND(GR["tg"]["eow"]) + " > ES " + ROUND(GR["tg"]["es"]) + " m), S "
                  + GR["ssgn"] + tail).
    } ELSE IF kind = "STEND" {
        noteEvent("GRTLS S-TURN ENDS (EOW < EST)" + tail).
    } ELSE IF kind = "ECAL54" {
        noteEvent("GRTLS ECAL PHASE 5 -> 4 (GRTRN 4.1: HDTRNA " + GR_HDTRNA + " ft/s with |DPSAC| > " + GR_HDTRNA_DPSAC
                  + " deg, or HDTBNK " + GR_HDTBNK + " ft/s with ACC_VERT < 0): ACC_VERT " + ROUND(GR["acc_vert"], 2)
                  + " m/s2" + tail).
    } ELSE IF kind = "ECALST" {
        noteEvent("GRTLS ECAL S-TURN (GRPHIC 1.3.2; EOW " + ROUND(GR["tg"]["eow"]) + " > ES " + ROUND(GR["tg"]["es"])
                  + " m): bank " + GR_PHISTN + " toward and past the HAC" + tail).
    } ELSE IF kind = "ECALSTEND" {
        noteEvent("GRTLS ECAL S-TURN ENDS (EOW < EST)" + tail).
    } ELSE IF kind = "IPPRTF" {
        noteEvent("GRTLS ECAL: THE SECOND PULL-OUT's PROTECTION ARMED (IPPRTF, GRTRN 3.3.12): load " + ROUND(sn["nz"], 2)
                  + " g < TLFMX1 " + GR_TLFMX1 + ", ICNTR " + GR["icntr"] + tail).
    } ELSE IF kind = "BAIL" {
        noteEvent("CONT BLUE: BAILOUT -- the hold from phase " + GR["iphase"] + " (Mach under " + GR_BAIL_MACH + "): "
                  + ROUND(grtlsKeas(sn["q"])) + " -> " + GR_BAIL_KEAS + " KEAS, " + grtlsBlueWord()
                  + ", the speedbrake closed" + tail).
    } ELSE IF kind = "P4BLUE" {
        noteEvent("GRTLS PHASE 4 BLUE (alpha-Mach to GRALPR " + ROUND(GR["gralpr"], 1) + ", " + grtlsBlueWord()
                  + ", no site)" + tail).
    } ELSE IF kind = "BLUEPICK" {
        noteEvent("BLUE FROM PHASE " + GR["iphase"] + " (ours: the crew's pick or the default): CONT BLUE, its I-loads"
                  + (CHOOSE ", the alpha trap off" IF GR_BLUE_REARM ELSE "") + ", " + grtlsBlueWord() + ", the bailout "
                  + "hold below Mach " + GR_BAIL_MACH + tail).
    } ELSE IF kind = "SHORE" {
        LOCAL shw IS "off the coast table: wings level".
        IF GR["sh"]:LENGTH > 0 {
            SET shw TO "the nearest coast " + ROUND(GR["sh"][0] / 1000, 1) + " km away, "
                       + (CHOOSE "at sea" IF GR["sh"][3] ELSE "inland") + "; the line " + ROUND(GR_BLUE_DOFF / 1000, 1)
                       + " km off it, the bank <= " + GR_BLUE_PHILM.
        }
        noteEvent("BLUE TOWARD THE COAST (ours; his words: as close to shore as possible while still over water): " + shw
                  + tail).
    } ELSE IF kind = "REACH" {
        noteEvent("CONT GREEN -> BLUE: the site is out of reach (EOW - EN " + ROUND(GR["tg"]["eow"] - GR["tg"]["en"])
                  + " m under " + GR_DEOW_REACH + "): the bailout below Mach " + GR_BAIL_MACH + tail).
    } ELSE IF kind = "SS5" {
        noteEvent("SPLIT-S: PAST STRAIGHT DOWN + " + SS_SW_DEG + " deg (path " + ROUND(sn["ang"]) + "): heads up, GRTLS "
                  + "PHASE 5 (the Nz " + SS_NZ + " g held, wings level) from bank " + ROUND(GR["bank_eq"], 1) + tail).
    } ELSE IF kind = "SSPICK" {
        LOCAL ee IS GR["ss_e"].
        noteEvent("SPLIT-S: RUNWAY " + GR["rwy"] + ", HAC ysgn " + GR["ysgn"] + " (" + (CHOOSE "overhead" IF
                  TG_OVERHEAD_DEFAULT ELSE "straight-in side") + "); EOW-EN at phase 4: " + SS_ENDS[0] + " +1 "
                  + ROUND(ee[0]) + " / -1 " + ROUND(ee[1]) + " m, " + SS_ENDS[1] + " +1 " + ROUND(ee[2]) + " / -1 "
                  + ROUND(ee[3]) + " m (TAEM's corridor " + SS_EMIN_D + " .. +" + SS_EMAX_D + ")" + tail).
    } ELSE IF kind = "GPICK" {
        noteEvent("GRTLS GREEN END / SIDE PICK (ours) " + GR["gpw"] + tail).
    } ELSE IF kind = "RC" {
        noteEvent("GRTLS RANGE CONTROL " + (CHOOSE "ON (" + GR["rcw"] + "): bank " + GR_RC_PHI + " toward the HAC side "
                  + GR["ysgn"] IF GR["rc"] ELSE "OFF (" + GR["rcw"] + ")") + tail).
    } ELSE IF kind = "TAEM" {
        noteEvent("GRTLS -> TAEM (Mach under " + GR_MSW1 + (CHOOSE ", alpha at or under " + GR_AMAXLD IF SS_ON ELSE "")
                  + "): EOW-EN " + ROUND(GR["tg"]["eow"] - GR["tg"]["en"])
                  + " m, ES-EOW " + ROUND(GR["tg"]["es"] - GR["tg"]["eow"]) + " m, psha " + ROUND(GR["tg"]["psha_prev"])
                  + " deg" + tail).
    }
}

FUNCTION grtlsBlueWord {                    // a BLUE's bank in the event texts
    RETURN CHOOSE "banked toward the coast" IF (GR_BLUE_SHORE AND GR_COAST["ok"]) ELSE "wings level".
}

FUNCTION grtlsLog {                         // one CSV row a guidance cycle (nz_fd: ops6q's finite-difference lift / drag)
    PARAMETER sn, am, bank.
    IF GR_LOG = "" { RETURN. }
    LOCAL nzt IS -1.
    IF SS_ON AND (GR["iphase"] = 8 OR GR["iphase"] = 5) {
        SET nzt TO SS_NZ.
    } ELSE IF GR["iphase"] = 5 OR GR["iphase"] = 7 {
        SET nzt TO GR["nzc"] + COS(sn["gam"]) / COS(bank).
    }
    LOCAL sst IS "".
    IF SS_ON { SET sst TO "," + ROUND(sn["ang"], 2) + "," + ROUND(sn["beq"], 2) + "," + ROUND(SHIP:MASS, 3). }
    IF GR_BLUE_SHORE AND GR_COAST["ok"] {   // BLUE toward the coast's columns (the search's distance, the heading flown to)
        SET sst TO sst + "," + ROUND(sn["lat"], 4) + "," + ROUND(sn["lng"], 4) + ","
                   + (CHOOSE ("" + ROUND(GR["sh"][0] / 1000, 2)) IF GR["sh"]:LENGTH > 0 ELSE "") + ","
                   + ROUND(GR["hdg_c"], 1) + "," + ROUND(sn["trk"], 1) + "," + (CHOOSE 1 IF sn["sea"] ELSE 0).
    }
    LOCAL tgs IS ",,,,".
    IF GR["ysgn"] <> 0 AND NOT GR["tg"]:ISTYPE("Scalar") {   // (CONT GREEN: ysgn from phase 5 on, tg from phase 4's start)
        LOCAL tg IS GR["tg"].
        SET tgs TO ROUND(tg["psha_prev"], 2) + "," + ROUND(tg["eow"]) + "," + ROUND(tg["en"]) + "," + ROUND(tg["es"]) + ","
                   + ROUND(tg["est"]).
    }
    LOG ROUND(MISSIONTIME, 2) + "," + GR["iphase"] + "," + ROUND(sn["alt"]) + "," + ROUND(sn["vr"], 1) + ","
        + ROUND(sn["mach"], 3) + "," + ROUND(sn["hdot"] / GR_FT) + "," + ROUND(sn["gam"], 2) + "," + ROUND(am, 2) + ","
        + ROUND(GR["acmd"], 2) + "," + ROUND(GR["alpcmd"], 2) + "," + ROUND(sn["nz"], 3) + ","
        + ROUND((FD_LIFT * COS(am) + FD_DRAG * SIN(am)) / EPR_G0, 3) + "," + ROUND(nzt, 3) + "," + ROUND(bank, 2) + ","
        + ROUND(GR["bank_want"], 2) + "," + ROUND(GR["gralpr"], 2) + "," + ROUND(GR["dgrnz"], 3) + ","
        + ROUND(MIN(GR["hdmax"], 99999)) + "," + tgs + "," + GR["istp4"] + sst TO GR_LOG.
}

FUNCTION grtlsEnd {                         // the loop's end: TAEM by Mach (said by grtlsEv), or the altitude floor
    PARAMETER floorAlt.
    IF NOT GR["done"] {
        noteEvent("GRTLS: handed to TAEM at the altitude floor (" + ROUND(floorAlt / 1000, 1) + " km) in phase "
                  + GR["iphase"] + ", not by Mach" + grtlsAt(grtlsSense(ldAlphaNow())) + ROUND(ldAlphaNow(), 1)).
    }
}
