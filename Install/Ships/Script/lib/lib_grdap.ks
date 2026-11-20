@LAZYGLOBAL OFF.
// ============================================================================
//  LIB_GRDAP.KS  --  the GRTLS / ECAL DAP (ops6q, OPS6_GR: RTLS, CONT GREEN / BLUE, SPLITS) and the OPS 3 entry's
//  (ops3q, grdStart(FALSE, TRUE): CSS from the entry interface, and the entry HUD, grdHudRecE)
// ============================================================================
//  No LOCK STEERING from the entry attitude (ops6q Phase 2; SPLITS: its first lock) to landRun: this DAP flies the
//  vessel's pitch, roll and yaw per axis through the addon's fly-by-wire handler (ADDONS:KALS:FBW3, the yaw jets'
//  handler on three axes: KalsAddon.YawJet.cs), and KSP mixes them into every effector as it does for the cooked
//  steering (RCS, the wheel, the surfaces, a lit gimbal). No surface is actuated on its own: no lockAxis, no deploy
//  angles (TAEM's lib_dap does that from landRun on).
//  THE LAWS (one per physics tick, a WHEN TRUE trigger, so the attitude holds through every blocking stretch: the
//  mono dump, the GRTLS loop's WAIT 0.1, BLUE's WAIT UNTIL FALSE, landRun's setup):
//   - the attitude as one rotation-rate vector (deg/s, the ANGLEAXIS / ANGULARVEL sense), no bank singularity:
//       alpha:     (GRD_KA (alpha_c - alpha) + alpha_c') about the pitch axis (-STAR), CSS's rate limit GRD_QLIM;
//       the lift:  (GRD_KPHI eps + bank_c') about the velocity (a stability-axis roll: the yaw coordinated), eps the
//                  roll about the velocity from the body top to the target lift (entrySteer's ANGLEAXIS(bankNow, v) x
//                  up_perp; SPLITS phase 8: ssLift, the turn plane's), limit GRD_PLIM;
//       sideslip:  GRD_KB beta about the top (the velocity to the right yaws the nose right);
//       the path:  the velocity direction's own rotation (filtered PATH_TAU, lib_dap's), so alpha and the bank hold;
//   - CSS per axis (PITCH / ROLL/YAW, lib_dap's buttons): out of the detent the stick's shaped rate (lib_dap shapeP /
//     shapeR, the orbiter's gearing) replaces the pitch rate / the roll rate about the velocity; in the detent the alpha
//     / the bank as they were when the stick came back are held. The yaw is the DAP's in CSS too (sideslip 0);
//   - each body axis: u = rate error / (GRD_T x the authority) + its integral, the authority FBWAUTH's (the vessel's
//     potential torque over its inertia, as kOS's steering estimates it: RCS + wheel at low q, the surfaces as q builds)
//     x grdAk (the share the vehicle has), floor GRD_A_MIN; the gain x tick capped at GRD_WARP_KT (pitch, roll) /
//     GRD_WARP_KY (yaw).
//  THE AUTHORITY AND THE INTEGRAL: FBWAUTH reads 3-10 x the surfaces' real authority above 5 kPa (the fits: pitch
//  0.1-0.45, roll and yaw ~0.3; RCS at low q 0.6-1.1), and a nose-down 1-3 deg/s2 needs a trim a P loop could only hold
//  with a large rate error (a full stick's 2.86 deg/s flew as 0.46). So the authority is x GRD_AUTH_K above GRD_AUTH_Q1
//  kPa (the whole below GRD_AUTH_Q0), and each axis has an integral (GRD_TI, held to +-GRD_I_MAX, frozen against the
//  clamp; from 0 at grdStart, kept through CSS <-> AUTO: it is the trim).
//  The pilot's stick: ADDONS:KALS:FBWPILOT (the gimbal less the handler's trims, read back on three axes).
//  The log: logs/grdap_<t>.csv at 25 Hz (SOCK_LOG).

GLOBAL GRD_T_P IS 0.3.          // s: the body pitch rate loop's time constant
GLOBAL GRD_T_R IS 0.3.          // s: the body roll rate loop's
GLOBAL GRD_T_Y IS 0.3.          // s: the body yaw rate loop's
GLOBAL GRD_A_MIN IS 0.5.        // deg/s2: the authority's floor (FBWAUTH reads 0: no RCS, no q)
GLOBAL GRD_KA IS 1.0.           // 1/s: nose-up rate per deg of alpha error (lib_dap KA_ALPHA)
GLOBAL GRD_KPHI IS 1.0.         // 1/s: roll rate about the velocity per deg of lift error
GLOBAL GRD_KB IS 1.0.           // 1/s: nose-right rate per deg of sideslip
GLOBAL GRD_QLIM IS 7.           // deg/s: AUTO's pitch rate (the GRTLS's alpha slews at GR_ALPHA_RATE 5)
GLOBAL GRD_PLIM IS 10.          // deg/s: AUTO's roll rate about the velocity
GLOBAL GRD_AUTH_N IS 5.         // ticks between the authority's reads (0.1 s)
GLOBAL GRD_LOG_EVERY IS 2.      // a log row every this many ticks: 25 Hz
GLOBAL GRD_FLUSH IS 25.         // rows per LOG
GLOBAL GRD_TI IS 1.5.           // s: the body rate loops' integral time
GLOBAL GRD_I_MAX IS 0.5.        // the integral's limit (of the control's +-1)
GLOBAL GRD_AUTH_K IS 0.3.       // FBWAUTH's share the vehicle has from GRD_AUTH_Q1 (the log's fits 0.1-0.45)
GLOBAL GRD_AUTH_Q0 IS 1.        // kPa: below it the whole of FBWAUTH (RCS: the fits 0.6-1.1)
GLOBAL GRD_AUTH_Q1 IS 5.        // kPa: from it GRD_AUTH_K (linear between)
GLOBAL GRD_HUD_NZE IS 1.5.      // g: the HUD diamond's Nz error shown at most
GLOBAL GRD_HUD_SL_S IS 1.       // s: the entry HUD's lift slope (grdNzSl) recomputed this often
// THE ENTRY BANK PREFILTER: in the OPS 3 entry the yaw jets give ~5 deg/s2 a unit of control against the roll's 40-130,
// and a roll about the velocity at alpha 40 needs 0.64 of its rate in yaw. The guidance ramp's bank rate (each pass's
// step over its interval, +-4 deg/s pulses) saturated the yaw jets 9 % of the time, the roll ran ahead of the yaw, the
// sideslip built and the bank swung +-2.5 deg about its command. So the bank command is prefiltered (a first order lag
// GRD_ENT_TAU) and the filter's own rate is the feed-forward: on the fitted plant the yaw never saturates, the sideslip
// halves and the bank's 4 s jitter drops 40 %. Entry and GRTLS; not SPLITS phase 8 (grdSs).
GLOBAL GRD_ENT_TAU IS 0.8.      // s: the entry bank command's prefilter (0 = off: the ramp's rate)
// THE ENTRY'S ALPHA REFERENCE MODEL: the alpha modulation steps the command once per drag sample, and grdRamp turns
// each step into a 0.5 s ramp whose rate is held 1.5 intervals: through the rate feed-forward and the integral the
// loop overshot every step by about its own size (stock's 4x entry: 0.44 deg steps overshot 0.46). The entry flies a
// reference alpha grdAm instead: the ramp's rate up to GRD_AREF_FF passes straight through (the schedule's ramps,
// -0.15 deg/s, follow without lag), the rest of the command is reached as a first-order lag of GRD_AREF_TM, and the
// pitch integral holds while the reference catches up faster than GRD_AREF_FZ. On the fitted plant a 0.44 deg step
// overshoots 9 % at 4x (59 % before) and 10 % at 1x (62 %) and settles in 1.3 s; the schedule's ramp lags 0.03 deg.
// Entry only (grdEnt): the GRTLS's 5 deg/s slews keep the ramp as it is.
GLOBAL GRD_AREF_TM IS 0.5.      // s: the reference's lag (0 = off)
GLOBAL GRD_AREF_FF IS 0.3.      // deg/s: the ramp rate passed straight through
GLOBAL GRD_AREF_FZ IS 0.05.     // deg/s: the pitch integral holds while the reference catches up faster than this
GLOBAL grdAm IS 0.              // the entry's reference alpha
GLOBAL grdAmOn IS FALSE.
GLOBAL GRD_R_DB IS 2.5.         // deg of RHC: CSS roll's detent (lib_dap's R_DB 1.25 is |stick| 0.064)
GLOBAL GRD_CAP_W IS 0.3.        // deg/s: a CSS hold is caught once the roll about the velocity (the alpha rate) is slower...
GLOBAL GRD_CAP_T IS 2.          // s: ...or this long after the stick came back (the rate damped first)
GLOBAL grdCapT0 IS -1.          // when the stick came back into the roll detent (-1: out of it, or caught)
GLOBAL grdCapQT0 IS -1.         // when the stick came back into the pitch detent (-1: out of it, or caught)
GLOBAL grdBf IS 0.              // the prefiltered bank command (+ = LEFT)
GLOBAL grdBfOn IS FALSE.
// THE YAW AUTHORITY FLOOR: FBWAUTH reads the yaw 1.5-2.7 x below what the yaw jets give (fitted per q: 4.3-6.0 deg/s2 a
// unit against 2.1-4.1), so the yaw loop's gain x tick was that much above GRD_T_Y's; at 4x warp's 0.08 s ticks, with
// the control two ticks late, it limit-cycled (the jets +-1, r +-0.7 deg/s, 34 % saturated near q 0). The yaw authority
// is at least GRD_YJA: on the fitted plants the 4x hold's r sd 0.2-0.7 -> 0.03-0.08 deg/s, 1x unchanged. The GRTLS has
// the same cycle below ~0.5 kPa (the jets 6.0 deg/s2 a unit against FBWAUTH's 2.47), so the floor is every mode's
// (entry, GRTLS, SPLITS); above ~1.5 kPa FBWAUTH x grdAk is 4.4-5.7 and the floor hardly binds.
GLOBAL GRD_YJA IS 5.0.          // deg/s2: the yaw authority at least (the yaw jets a unit, measured)
// THE WARP CAP: at 4x warp (0.08 s ticks, the control two ticks late) a step in the alpha command's rate rang the pitch
// loop (u_p +-1, q +-4 deg/s, alpha +-1.5 deg, a 1.3 s period); with the elevons on the pitch stops the roll had no
// authority (p +-35 deg/s, the sideslip +-6 deg, the bank +-10 deg about its command). The fits: the pitch gives 19
// deg/s2 a unit against the DAP's 13, the roll 150-440 against 110-180 from 3.7 kPa (FBWAUTH's share 0.6-0.9, not
// GRD_AUTH_K's 0.3), so the gain x tick was 0.4-0.7 where DAP_WARP_KT meant 0.3. With the pitch / roll loops' gain x
// tick held to GRD_WARP_KT and the outer loops (GRD_KA, GRD_KPHI, GRD_KB) scaled by the same factor the ring damps (q
// 1.7, 0 % saturated, decay 0.09-0.29); the roll's share GRD_AUTH_KR damps its 4x runaways at 1.8-8 kPa (p sd 6-64 ->
// 0.1-0.4 deg/s). 1x and 2x unchanged by the cap (it binds from 0.045 s ticks); the share halves the roll's gain above
// ~3 kPa at 1x, to GRD_T_R's design. Cost at 4x, low q: a 40 deg bank step tracks slower (sideslip up to ~3 deg).
GLOBAL GRD_WARP_KT IS 0.15.     // the pitch / roll rate loops' gain x tick at most
// THE YAW'S WARP CAP: under DAP_WARP_KT (binding from 0.09 s ticks) the yaw loop ran at full gain at 4x (0.08 s, the
// control two ticks late): the yaw jets bang-banged +-1 and, through their roll and the aileron crossfeed, the roll rang
// at ~1 Hz (a FAR entry below Mach 5: p +-5-8 deg/s, the jets 18-33 % on their stops). On the fitted lateral plants (FAR
// and stock) at 4x the yaw held to GRD_WARP_KY settles a 5 deg bank step (p sd 13-16 -> ~0 deg/s) and the guidance's
// sawtooth (8-14 -> 0.5-4.8; FAR's plant at 6.7-8.5 kPa rings or diverges under any cap, the old one too); 1x
// unchanged (it binds from 0.03 s ticks; 2x's 0.04 s runs at 0.75 of the gain).
GLOBAL GRD_WARP_KY IS 0.10.     // the yaw rate loop's gain x tick at most
GLOBAL GRD_AUTH_KR IS 0.75.     // the roll's GRD_AUTH_K (FBWAUTH's share from GRD_AUTH_Q1)
// THE YAW JETS' ROLL: the yaw jets roll the vehicle LEFT, 3-15 deg/s2 per unit of yaw command against the aileron's
// 27-350: a share of the aileron GRD_YJR_V (12 % to 2 kPa, 7 % at 2.5-3.5, 1 % at 10; one plant fitted on the 1x and 4x
// rows together, since the two warps close the loop differently). With the roll loop held to GRD_WARP_KT at 4x that roll
// went through, and the bank loop and the sideslip closed on it: from ~2.5 kPa the bank swung +-2-3 deg on a 2.6 s
// period, growing. The aileron takes the yaw jets' roll out (cmdR + GRD_YJR x cmdY): on the fitted plants 4x settles
// at every q (p sd, a tick late 1.4-3.4 -> 0.7-1.3 deg/s, two ticks 2-15 -> 0.8-1.7; a 5 deg step peaks at 5.5-7.2)
// and 1x improves (1.0-1.3 -> 0.6-1.0); half or 1.5 x the share still helps. In the GRTLS the share reads 2.1 % at 4-8
// kPa, 1.1 % at 8-12, 1.7 % at 15-21 (within what helps); with the prefilter it takes 4x's p sd 6.0-11.3 -> 3.5-3.9
// deg/s, the bank error 4.4-5.0 -> 1.7-2.6 deg, the yaw jets on their stops 0-9 -> 0 %; 1x 3.3-5.1 -> 2.2-3.2. So both
// fly in every mode but SPLITS phase 8 (NOT grdSs).
GLOBAL GRD_YJR_Q IS LIST(0, 1.5, 2.5, 3.5, 4.8, 6.7, 10).                  // kPa
GLOBAL GRD_YJR_V IS LIST(0.12, 0.12, 0.071, 0.073, 0.037, 0.014, 0.010).   // the yaw jets' roll / the aileron's
// Under FAR the yaw command rolls the orbiter far harder: fitted on a FAR GRTLS (pdot on u_r, u_y, beta per q band)
// the share is 0.44 at 3.5-4.8 kPa, 0.49 at 4.8-6.7, 0.38 at 6.7-10 and 0.76 at 10-14 (stock's fits 0.00-0.06), and
// with stock's table the roll and yaw rang together at ~1 Hz from Mach 4 (p +-21 deg/s, both commands on their stops).
// FAR's table cancels a little less than measured (half to 1.5 x the share still helps).
GLOBAL GRD_YJR_V_FAR IS LIST(0.12, 0.12, 0.2, 0.4, 0.45, 0.45, 0.55).
IF (DEFINED FAR_ON) AND FAR_ON { SET GRD_YJR_V TO GRD_YJR_V_FAR. }
// The FAR entry's share by Mach: GRD_YJR_V_FAR is the GRTLS's (alpha 20-30); at the entry's alpha ~40 FAR's aileron and
// jets share 0.05-0.20 (fitted on the 4x FAR entry grdap_200900_3: 0.06 at Mach 8-10, 0.20 at 5-6.5, 0.05 at 4-5), and
// with the q table's 0.40-0.44 the aileron over-took the jets' roll: with the roll's gain below (GRD_AUTH_FAR_R) the
// sideslip cycled to 6.9 deg at Mach 8-4 (yaw jets on their stops, the yaw integral at its limit). In the entry (grdEnt)
// under FAR: GRD_YJR_EV on GRD_YJR_EM (Mach knots; linear, held past the ends), weight 0 at Mach GRD_YJR_EB[0] (the q
// table's) to 1 at GRD_YJR_EB[1]. Empty lists: off (stock). With far_trim.cfg's ELEVON_FIX through the entry the
// aileron rolls at 0.6-1 x stock's power per unit command above Mach 3.5, about the body roll axis (no yaw of its own),
// with the roll's gain below: 0.12 at Mach 4.5, 0.02 above (0 at 7.25), swept on the lateral plant of the 4x FAR entry
// 200064 (grdap_200900_4) with the elevons' yaw at FAR's own: at
// 1x-2x the sideslip peaks at 0.6 deg, at 4x 2.1, the yaw jets off their stops.
// GRD_YJR_E_ENT TRUE: the Mach table in the entry (grdEnt) only; FALSE: in the FAR GRTLS too, where above Mach 3.5
// the same aileron flies the entry's alpha and the q table's 0.4-0.55 (fitted on the weak aileron) over-cancels.
GLOBAL GRD_YJR_EM IS LIST().
GLOBAL GRD_YJR_EV IS LIST().
GLOBAL GRD_YJR_EB IS LIST(3.5, 4.5).
GLOBAL GRD_YJR_E_ENT IS FALSE.
IF (DEFINED FAR_ON) AND FAR_ON {
    SET GRD_YJR_EM TO LIST(4.5, 5, 6.5, 7.25, 9, 11).
    SET GRD_YJR_EV TO LIST(0.12, 0.02, 0.02, 0, 0.02, 0.02).
}
// Under FAR the authority is FBWAUTHS: FBWAUTH as stock's estimate reads it. Stock's surface estimate multiplies each
// axis by the surface's lever (SockFarTrim.cs 15.), and every share and floor here is fitted on that; FAR's own is the
// torque alone, so FBWAUTH read the elevons' pitch and roll ~4 x low (stock's FBWAUTH per kPa 4.2-4.8 x FAR's in
// pitch, 3.7-4.4 x in roll at Mach 4-9) and the loops flew at 1.6-5 x their gain. GRD_AUTH_FAR_S FALSE: FBWAUTH x
// GRD_AUTH_FAR (pitch, roll, yaw; the yaw's from Mach GRD_AUTH_FAR_M[1] up, none below [0]), a fit right above Mach
// 6 only.
GLOBAL GRD_AUTH_FAR_S IS TRUE.
// FBWAUTHS's pitch under FAR x GRD_AUTH_FAR_P (Mach knots, scale; linear, held past the ends): the pitch fits of the
// same entry flown in both (4x; stock grdap_200900_11, FAR grdap_200900_2) put the true pitch power per unit of the
// command at 1.22 x stock's FBWAUTH at Mach 12.6 but 1.47-1.55 x FAR's FBWAUTHS at Mach 11-12.6 (the true powers alike:
// 6.4 vs 6.35 deg/s2 at 0.4 kPa); FBWAUTHS reads FAR's elevons at FAR's linear lift slope, which falls with Mach while
// the plate's at 40 deg does not. From Mach 10 down the two ratios agree (1.0-1.2).
GLOBAL GRD_AUTH_FAR_P IS LIST(LIST(10.5, 1), LIST(11, 1.15), LIST(12, 1.25), LIST(13, 1.25), LIST(14, 1)).
// FBWAUTHS's pitch in the FAR entry (grdEnt) x GRD_AUTH_FAR_PL at Mach 2-5.25 (as GRD_AUTH_FAR_P, applied on top of it;
// the GRTLS and stock: none). There FBWAUTHS reads the pitch power 4-5 x low (the fitted true power per unit of the
// command / the read: 4.8 at Mach 2.45-2.7, 5.1 at 2.7-2.9, 4.5 at 2.9-3.1, 3.8 at 3.1-3.3, 3.9 at 3.3-3.6, 3.5 at
// 3.6-4, 2.7 at 4-4.5, 2.5 at 4.5-5, 1.07 at 5-6; the true power itself, 15-20 deg/s2, is stock's), so the pitch loop
// flew at 4-5 x its gain: at the 4x warp (kcw 0.56, a tick of 0.08 s) gain x tick 0.55-0.77 against a limit near 0.6, and
// the elevons banged +-1 on a 0.7 s period before the GRTLS hand-off. The table is the
// ratio, rounded to the loop's gain x tick 0.15-0.2 at every warp (the fitted plant: calm at 1x, 2x and 4x).
GLOBAL GRD_AUTH_FAR_PL IS LIST(LIST(2, 1), LIST(2.45, 4), LIST(2.8, 4.2), LIST(3.2, 3.3), LIST(3.8, 2.9), LIST(4.25, 2.25), LIST(4.75, 2.1), LIST(5.25, 1)).
// FBWAUTHS's roll in the FAR entry (grdEnt) x GRD_AUTH_FAR_R (as GRD_AUTH_FAR_P). far_trim.cfg's ELEVON_FIX runs
// through the entry: FAR's elevons roll at 0.6-1 x stock's power per unit command, but FBWAUTHS reads its correction's
// slope at 2.1-3.3 x the true roll from Mach 4.75 up (stock's estimate 1.0-1.1 x): the table is stock's estimate / true
// over FAR's (the 4x entries stock grdap_200900_11, FAR grdap_200900_4), so the roll loop flies at stock's gain.
GLOBAL GRD_AUTH_FAR_R IS LIST(LIST(4.5, 1), LIST(4.75, 0.38), LIST(5, 0.31), LIST(7.25, 0.30), LIST(9, 0.41), LIST(10.5, 0.40), LIST(11.5, 0.33)).
GLOBAL GRD_AUTH_FAR IS LIST(1.8, 1.0, 2.3).
// THE TAL'S ROLL (stock): FBWAUTH reads the aileron at alpha 46 up to 5 x high on some vehicles: the two TALs of
// 11-02 rolled at 0.2-0.7 x FBWAUTH from 0.6 to 3 kPa (Mach 11.5-10; the elevons' pitch trim u_p -0.06 to -0.25, one
// elevon near its stop leaves little differential throw), the TALs of 10-27 .. 10-31 at the same alpha at 0.9-1.3 x
// (u_p +0.1 to +0.3), normal OPS 3 entries at alpha 40-43 at 0.6-1.0 x. At 4x the warp cap then held the weak roll
// loop below its own integral and the bank, sideslip and yaw rang on a 6.5-7 s period (sideslip to 9 deg). In the
// stock entry (grdEnt) the roll's FBWAUTH x GRD_AUTH_ALPHA_R at the alpha command (alpha knots, scale; linear, held
// past the ends; LIST() = off). On the fitted lateral plants of both weak TALs x0.5 settles 4x (sideslip max 3.2 /
// 0.47 -> 0.01 deg on a 5 deg bank step) and keeps 1x / 2x; on the same plants with the aileron at FBWAUTH's power
// x0.5 still settles at 1x-4x, while x0.25 rang that aileron at 2x / 4x (gain x tick 0.6 behind two ticks of delay).
// Normal entries (alpha command <= 43) fly as before.
GLOBAL GRD_AUTH_ALPHA_R IS LIST(LIST(43, 1), LIST(46, 0.5)).
GLOBAL GRD_AUTH_FAR_M IS LIST(5, 6).
// THE JETS' SHARE (both trees, every mode): FBWAUTH's RCS read is the jets' potential torque summed per thruster, not
// what they give: in the jets-only entry (Mach 13-14, q 0.01 kPa) it reads the roll 18-25 deg/s2 (9-13 while the jets
// fire; the DAP re-reads it every GRD_AUTH_N ticks) and the pitch 1.7, while the jets roll the orbiter 8.1-9.4 and pitch
// it 4.1-4.3 deg/s2 a unit (measured in flight: the same
// jets). The roll loop flew at 0.45 of its gain, the pitch at 2.5 x: the first bank's capture rang at 4x (bank 3-4 deg
// past, sideslip 1-1.7, pitch rate +-1 deg/s on the stock 4x first banks; FAR, whose roll table holds the jets' read
// x 0.33 there, captured within 1.1 deg). grdAuthRead takes the RCS group out of the read (FBWAUTHX's [6-8]) and adds
// GRD_RCS_A on each axis whose RCS reads at least GRD_RCS_ON: the jets' measured response, as the real DAP's jet
// I-loads; the surfaces' tables (GRD_AUTH_ALPHA_R, GRD_AUTH_FAR_*) scale the rest only. 0 on an axis = the RCS read
// kept (the yaw: GRD_YJA floors it at the jets' 4.6-5). On the jets-only plant fitted from those logs with this law:
// the 4x capture 3.3 -> 1.0 deg past, sideslip 1.5 -> 0.13; 1x 0.4 -> 0.26 deg (stock), FAR's 1.2 -> 1.0 at 4x.
GLOBAL GRD_RCS_A IS LIST(4.2, 8.6, 0).   // deg/s2 a full command: the jets' (pitch, roll, yaw); LIST() = off
GLOBAL GRD_RCS_ON IS 0.5.                // deg/s2: an RCS read under it = no jets on that axis
// FAR'S READ JUMPS (grdAuthSlew): FBWAUTHS reads ELEVON_FIX's slope as a +-2.5 deg secant at the elevons' DEFLECTED
// local AoA; at Mach 2.5-3 that AoA sits on FAR's section detachment (the section's lift races, then drops), so each
// deflection moves the read 0.2-3.6 x (FAR grdap_78379: pitch 3.1-50.5, roll 31-798 between 0.5 s reads at Mach 2.6;
// grdap_78135 3.4-84.7). The gain is 1 / the read: the low reads put the pitch and roll on their stops and the loop
// rang into TAEM. Between Mach GRD_AUTH_SLEW_M[0] and [1] each axis of the FBWAUTHS read moves at most GRD_AUTH_SLEW x
// per second from the last;
// grdStart's first read as it is. Outside the band as before: subsonic (the GRTLS's alpha recovery moves the true power
// fast), the entry start (q builds) and GRD_AUTH_FAR_R's step at Mach 4.5-5; stock untouched.
GLOBAL GRD_AUTH_SLEW IS 1.5.
GLOBAL GRD_AUTH_SLEW_M IS LIST(1.5, 3.5).
// THE ENTRY DIAMOND: the entry's Nz per deg of alpha is 0.005-0.02 g, so an Nz-error diamond would move 0.02-0.08 HUD deg
// a degree of alpha error. In entry it shows the alpha error itself, GRD_HUD_ENT_K HUD deg a degree, held to
// GRD_HUD_ENT_AMAX deg.
GLOBAL GRD_HUD_ENT_K IS 1.      // HUD deg per deg of alpha error: the entry diamond's pitch
GLOBAL GRD_HUD_AR_K IS 1.       // HUD deg per deg of alpha error: the GRTLS diamond's pitch in ALPREC
GLOBAL GRD_HUD_ENT_AMAX IS 5.   // deg: the alpha error shown at most

GLOBAL grdOn IS FALSE.          // the DAP flies (grdStart .. grdStop)
GLOBAL grdDone IS TRUE.         // its trigger ends
GLOBAL grdSs IS FALSE.          // SPLITS phase 8: the lift toward ssLift
GLOBAL grdSrcGr IS FALSE.       // the alpha command GR["acmd"] (SPLITS) or entryAoaCmd
GLOBAL grdEnt IS FALSE.         // the OPS 3 entry flies (ops3q): no GR; the HUD's record from the entry guidance
GLOBAL grdBkWant IS 0.          // the entry guidance's bank before the slew (ops3q, each cycle; + = LEFT): CSS roll's diamond
GLOBAL grdWc IS LIST(0, 0, 0).  // the body-rate commands, deg/s, + = right roll / nose up / nose right (the
                                //   entry page's RATE arrows, lib_entdisp)
GLOBAL grdNzTe IS -1.           // when grdNzSl was last computed in the entry (TIME:SECONDS)
GLOBAL grdT IS 0.
GLOBAL grdN IS 0.
GLOBAL grdVoP IS V(0, 0, 0).   // m/s: the last tick's orbital velocity (the HUD's Nz)
GLOBAL grdVhP IS V(0, 0, 0).
GLOBAL grdPath IS V(0, 0, 0).   // deg/s: the velocity direction's rotation
GLOBAL grdAuth IS LIST(1, 1, 1).
GLOBAL grdAuS IS LIST().        // grdAuthSlew's last value (LIST(): none yet) and its time
GLOBAL grdAuST IS 0.
GLOBAL grdAuthFb IS FALSE.      // under FAR without SockFarTrim's StockAuth (FBWAUTHSON FALSE): FBWAUTH x GRD_AUTH_FAR
GLOBAL grdAk IS 1.              // grdAuthK() at the authority's read
GLOBAL grdAkR IS 1.             // the roll's (grdAuthK(GRD_AUTH_KR))
GLOBAL grdYjr IS 0.             // GRD_YJR at the authority's read (grdYjrAt())
GLOBAL grdI IS LIST(0, 0, 0).   // the rate loops' integrals (the control's units)
GLOBAL grdNzM IS 1.             // the measured body Nz (g): the sensed acceleration along the orbiter's top, for the HUD
                                //   (the orbital velocity's rate less gravity, filtered PATH_TAU)
GLOBAL grdNzSl IS 0.05.         // the model's Nz per deg of alpha at the guidance's alpha (g/deg), once a cycle
GLOBAL grdNzTn IS -1.           //   (at GR["tnext"]'s change)
GLOBAL grdRpA IS LIST(0, 0, 0, 0.1).   // the ramps: LIST(from, to, published at, the interval) (lib_dap dapGdBank's)
GLOBAL grdRpB IS LIST(0, 0, 0, 0.1).
GLOBAL grdCssP IS FALSE.
GLOBAL grdCssR IS FALSE.
GLOBAL grdHoldP IS FALSE.       // CSS in the detent: the alpha held (grdAHold)
GLOBAL grdHoldR IS FALSE.       //   the bank held (grdBHold, + = LEFT as bankNow)
GLOBAL grdAHold IS 0.
GLOBAL grdBHold IS 0.
GLOBAL grdU IS LIST(0, 0, 0).
GLOBAL grdCsv IS "".
GLOBAL grdBuf IS "".
GLOBAL grdBufN IS 0.
GLOBAL grdThr0 IS 0.            // SPDBK CSS: the lever at the start (lib_dap's dThr0)
GLOBAL grdSbLever IS FALSE.
GLOBAL grdHudRwy IS "".
GLOBAL GRD_OMS_LIM_ON IS 100.   // the OMS gimbals' limit (%) while an OMS engine fires (the dump: their authority)
GLOBAL GRD_OMS_LIM_OFF IS 1.    // and while it is off (the stick's readback only; 0.05 deg of travel)
RUNONCEPATH("0:/lib/lib_omsout.ks").   // the OMS engines ops2q failed (1:/oms_out.txt): never lit again, their gimbal limit stays OFF
GLOBAL grdOms IS LIST().        // LIST(engine, its ModuleGimbal, the limit last written, the time a failed engine found lit was noted) per gimbaled OMS engine
// THE C# DAP. With GRD_CS on and the KAL/S addon carrying GRDTICK, each tick's math is ADDONS:KALS:GRDTICK
// (coproc/Grd.cs, a line-for-line port of grdTickK below): kOS reads the vessel (grdCsIn: the facing, the velocity, the
// rates, UP, the pressures, FBWPILOT's raw stick, FBWAUTH after grdOmsGmb when due, the guidance's alpha and bank,
// ssLift in SPLITS phase 8, GR["iphase"] on a log row), the addon reads and writes the DAP's globals itself (the state
// stays these kOS globals, exact; lib_dap's keyboard mode, kbAxis, runs in the addon on lib_dap's dKb), kOS hands the
// commands to FBW3 and applies the rare actions (the keyboard mode's messages to addMsg, the CSS buttons' text, the
// csv's LOG). On any addon failure (an older DLL without GRDTICK, a tick's error: nothing written) GRD_CS turns off
// for the rest of the program with an event line (GRD_CS_ERR says why) and grdTickK flies that tick and the rest.
// SET GRD_CS TO FALSE. before the run = kOS only.
IF NOT (DEFINED GRD_CS) { GLOBAL GRD_CS IS TRUE. }
GLOBAL GRD_CS_ERR IS "".
GLOBAL GRD_CS_N IS 0.           // the ticks the addon flew
GLOBAL grdCsOk IS -1.           // -1 not looked at yet, 1 the addon's GRDTICK is there, 0 off

FUNCTION grdRamp {              // a published value ramped over its publication interval, the rate held to
    PARAMETER rp, nv, t.          //   DAP_RAMP_HOLD intervals (lib_dap's): LIST(value, rate)
    IF nv <> rp[1] {
        LOCAL f0 IS (t - rp[2]) / rp[3].
        LOCAL x0 IS rp[0] + (rp[1] - rp[0]) * MIN(1, MAX(0, f0)).
        SET rp[3] TO MIN(0.5, MAX(0.04, t - rp[2])).
        SET rp[0] TO x0.
        SET rp[1] TO nv.
        SET rp[2] TO t.
    }
    LOCAL f IS (t - rp[2]) / rp[3].
    IF f >= DAP_RAMP_HOLD { RETURN LIST(rp[1], 0). }
    RETURN LIST(rp[0] + (rp[1] - rp[0]) * MIN(1, MAX(0, f)), (rp[1] - rp[0]) / rp[3]).
}

FUNCTION grdBankNow {           // the bank about the velocity, + = LEFT (bankNow's sense: ANGLEAXIS(bank, v) x up_perp = top)
    PARAMETER vh, tv.
    LOCAL upP IS VXCL(vh, SHIP:UP:VECTOR).
    LOCAL topP IS VXCL(vh, tv).
    IF upP:MAG < 0.01 OR topP:MAG < 0.01 { RETURN 0. }
    RETURN ARCTAN2(VDOT(vh, VCRS(upP, topP)), VDOT(upP, topP)).
}

FUNCTION grdSsRoll {            // SPLITS phase 8: the roll about the velocity from slP (ssLift's, across the velocity) to
    PARAMETER vh, tv, slP.      //   the top, + = LEFT (grdBankNow's sense, from ssLift instead of up_perp)
    LOCAL topP IS VXCL(vh, tv).
    IF slP:MAG < 0.01 OR topP:MAG < 0.01 { RETURN 0. }
    RETURN ARCTAN2(VDOT(vh, VCRS(slP, topP)), VDOT(slP, topP)).
}

FUNCTION grdAcIn {              // the alpha command: SPLITS GR["acmd"] (from its first lock, before ops6q's entryAoaCmd
    IF grdSrcGr { RETURN GR["acmd"]. }      //   exists), else entryAoaCmd (the GRTLS loop sets it from GR["acmd"])
    RETURN entryAoaCmd.
}

FUNCTION grdBkIn {              // the bank command (bankNow, + = LEFT); 0 before ops6q declares it (SPLITS phase 8: unused)
    IF DEFINED bankNow { RETURN bankNow. }
    RETURN 0.
}

FUNCTION grdAvail {             // this DLL flies three axes
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN FALSE. }
    RETURN ADDONS:KALS:HASSUFFIX("FBW3").
}

// THE START: TRUE = the DAP flies (no steering lock from here); FALSE = an older DLL: the caller locks as before
FUNCTION grdStart {
    PARAMETER ss,               // SPLITS: phase 8's lift (ssLift), the alpha GR["acmd"]
              ent IS FALSE.     // the OPS 3 entry (ops3q: entryAoaCmd + bankNow, no GR)
    IF grdOn {
        IF ss <> grdSs {                               // SPLITS <-> GRTLS: the prefilter restarts on the command, and a
            SET grdBfOn TO FALSE.                      //   CSS roll hold is caught again (phase 8 holds it from ssLift,
            SET grdHoldR TO FALSE.                     //   the others from up)
            SET grdCapT0 TO -1.
        }
        SET grdSs TO ss.
        RETURN TRUE.
    }
    IF NOT grdAvail() {
        noteEvent("*** GRTLS DAP: this coprocessor DLL has no FBW3 (an older build): the cooked steering flies").
        RETURN FALSE.
    }
    // ops1q's C# hand-off hold (ADDONS:KALS:HOHOLD) released: this DAP flies from here (FBW3 releases it too)
    IF ADDONS:KALS:HASSUFFIX("HOHOLDOFF") { LOCAL hoOff IS ADDONS:KALS:HOHOLDOFF. }
    SET grdSs TO ss.
    SET grdSrcGr TO ss.
    SET grdEnt TO ent.
    SET grdNzTe TO -1.
    SET grdBfOn TO FALSE.        // the prefilter starts on the command
    SET grdAmOn TO FALSE.        // the alpha reference too
    LOCK STEERING TO SHIP:FACING.   // the lock known to this file, so the UNLOCK below compiles to the release
    UNLOCK STEERING.            // a lock and the handler fight; the readback would read the steering, not the stick
    IF DEFINED STEER_UNLOCKS { FOR u IN STEER_UNLOCKS { IF NOT u:ISDEAD { u:CALL(). } } }   // live runs' locks (STEER_UNLOCKS)
    SAS OFF.
    IF NOT GMB_HAVE { gmbInit(). }  // a split-S starts here before ops6q's gmbInit: PITCH / ROLL would grey to TAEM
    IF gmbLive() { SET GMB_ENG:GIMBAL:LOCK TO FALSE. }   // gmbLive, not GMB_HAVE. the stick's readback: an unlocked gimbal (the OMS's)
    SET dGmb TO GMB_ENG.        // lib_dap's buttons: PITCH / ROLL grey without it
    SET dGmbHave TO GMB_HAVE.
    IF GMB_HAVE { dGmbReg(). }  // registered, so lib_dap's dGmbLive can see a lost engine
    SET dReqP TO FALSE.
    SET dReqR TO FALSE.
    SET dSbAuto TO TRUE.        // SPDBK AUTO: the entry's schedule
    SET hdVis TO FALSE.         // the HUD OFF in the GRTLS until the HUD button
    SET grdThr0 TO SHIP:CONTROL:PILOTMAINTHROTTLE.
    SET grdSbLever TO FALSE.
    SET grdCssP TO FALSE.
    SET grdCssR TO FALSE.
    // OPS 1's CSS / HUD / HUD CAM states at the hand-off (ops1q asc_ho_set), carried across the programs, once
    IF DEFINED ASC_HO { IF ASC_HO:HASKEY("css_p") {
        SET dReqP TO ASC_HO["css_p"].
        SET dReqR TO ASC_HO["css_r"].
        SET hdVis TO ASC_HO["hud"].
        ASC_HO:REMOVE("css_p").
    } }
    SET grdHoldP TO FALSE.
    SET grdHoldR TO FALSE.
    SET grdCapT0 TO -1.
    SET grdCapQT0 TO -1.
    SET grdT TO TIME:SECONDS.
    SET grdN TO 0.
    SET grdOms TO LIST().       // every gimbaled OMS engine (lib_vehicle gmbInit's titles), each limit written fresh
    FOR eng IN SHIP:ENGINES {
        IF eng:HASMODULE("ModuleGimbal") AND (eng:TITLE:CONTAINS("Manoeuvring") OR eng:TITLE:CONTAINS("Maneuvering")
                                              OR eng:TITLE:CONTAINS("Viking")) {
            grdOms:ADD(LIST(eng, eng:GETMODULE("ModuleGimbal"), -1, -99)).
            SET eng:GIMBAL:LOCK TO FALSE.
        }
    }
    omsOutRead().               // the failed engines (ops2q's 1:/oms_out.txt), read once here
    grdOmsGmb().
    SET grdVoP TO V(0, 0, 0).
    SET grdVhP TO V(0, 0, 0).
    SET grdPath TO V(0, 0, 0).
    LOCAL a0 IS grdAcIn().
    LOCAL b0 IS grdBkIn().
    SET grdRpA TO LIST(a0, a0, grdT, 0.1).
    SET grdRpB TO LIST(b0, b0, grdT, 0.1).
    SET grdAuS TO LIST().
    SET grdAuth TO grdAuthRead().
    SET grdAk TO grdAuthK().
    SET grdAkR TO grdAuthK(GRD_AUTH_KR).
    SET grdYjr TO grdYjrAt().
    SET grdI TO LIST(0, 0, 0).
    SET grdNzM TO 1.
    SET grdNzTn TO -1.
    SET grdCsv TO "".
    IF SOCK_LOG {
        IF NOT EXISTS("0:/logs") { CREATEDIR("0:/logs"). }
        LOCAL tg IS "" + ROUND(TIME:SECONDS, 0).
        LOCAL n IS 2.
        UNTIL NOT EXISTS("0:/logs/grdap_" + tg + ".csv") {
            SET tg TO ROUND(TIME:SECONDS, 0) + "_" + n.
            SET n TO n + 1.
        }
        SET grdCsv TO "0:/logs/grdap_" + tg + ".csv".
        LOG "t,mach,q_kpa,iphase,ss,css_p,css_r,hold_p,hold_r,alpha,a_cmd,a_rate,beta,bank,bank_c,bank_rate,eps,"
            + "qc,pc,rc,q,p,r,u_p,u_r,u_y,auth_p,auth_r,auth_y,stk_p,stk_r,stk_y,path,i_p,i_r,i_y,ak,nz" TO grdCsv.
    }
    SET grdBuf TO "".
    SET grdBufN TO 0.
    SET grdOn TO TRUE.
    SET grdDone TO FALSE.
    WHEN TRUE THEN {
        IF NOT grdDone { grdTick(). }
        RETURN NOT grdDone.
    }
    noteEvent((CHOOSE "ENTRY DAP ON (" IF ent ELSE "GRTLS DAP ON (")
              + (CHOOSE "SPLITS phase 8: the lift to the turn plane" IF ss ELSE "alpha + bank")
              + "): no steering lock; authority p/r/y " + ROUND(grdAuth[0], 2) + " / " + ROUND(grdAuth[1], 2) + " / "
              + ROUND(grdAuth[2], 2) + " deg/s2"
              + (CHOOSE " (FAR's members not found: FBWAUTH x GRD_AUTH_FAR)" IF grdAuthFb ELSE "")
              + (CHOOSE "; log " + grdCsv IF grdCsv <> "" ELSE "")).
    RETURN TRUE.
}

FUNCTION grdStop {              // landRun, just before lib_dap's DAP takes the axes: every axis back to the pilot
    IF NOT grdOn { RETURN. }
    SET grdDone TO TRUE.
    SET grdOn TO FALSE.
    LOCAL ok IS ADDONS:KALS:FBWOFF().
    IF grdCsv <> "" AND grdBuf <> "" { LOG grdBuf TO grdCsv. }
    SET grdBuf TO "".
    SET grdBufN TO 0.
    noteEvent("GRTLS DAP OFF at " + ROUND(ALTITUDE) + " m, M" + ROUND(dapMach(), 2) + ": TAEM's DAP from here").
}

// ---------------------------------------------------------------- the C# DAP's hook (the block at GRD_CS)
FUNCTION grdCsOff {                     // the C# DAP off for the program: kOS's grdTickK from here
    PARAMETER why.
    SET GRD_CS_ERR TO why.
    SET GRD_CS TO FALSE.
    SET grdCsOk TO 0.
    noteEvent("GRTLS DAP: kOS flies the ticks (the C# DAP off: " + why + ")").
}
FUNCTION grdCsSetup {                   // once, at the first tick: the addon and its GRDTICK
    LOCAL why IS "".
    IF NOT ADDONS:HASSUFFIX("KALS") { SET why TO "no KAL/S addon". }
    ELSE IF NOT ADDONS:KALS:AVAILABLE { SET why TO "the KAL/S addon is not available". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("GRDTICK") { SET why TO "the KAL/S addon has no GRDTICK (an older KalsCoproc.dll)". }
    ELSE IF NOT ADDONS:KALS:HASSUFFIX("GRDKB") {
        SET why TO "the KAL/S addon's GRDTICK wants the stick after kbAxis (an older KalsCoproc.dll)".
    }
    IF why <> "" { grdCsOff(why). RETURN. }
    SET grdCsOk TO 1.
    noteEvent("GRTLS DAP: the C# coprocessor flies the ticks").
}
FUNCTION grdCsPh {                      // the log row's phase (grdTickK's ph)
    IF DEFINED GR { IF GR:ISTYPE("Lexicon") { IF GR:HASKEY("iphase") { RETURN GR["iphase"]. } } }
    RETURN 0.
}
FUNCTION grdCsIn {                      // the tick's reads, in coproc/Grd.cs GrdIn's order
    LOCAL nn IS grdN + 1.               // the tick's grdN (Grd.cs counts it)
    LOCAL au IS 0.
    IF MOD(nn, GRD_AUTH_N) = 0 {        // the limits first
        grdOmsGmb().
        SET au TO grdAuthRead().
    }
    LOCAL fc IS SHIP:FACING.             // the stick raw: the addon applies the keyboard mode (kbAxis) on dKb
    RETURN LIST(TIME:SECONDS, fc:FOREVECTOR, fc:TOPVECTOR, fc:STARVECTOR, SHIP:VELOCITY:SURFACE, SHIP:ANGULARVEL,
        SHIP:UP:VECTOR, SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE), SHIP:DYNAMICPRESSURE,
        ADDONS:KALS:FBWPILOT(), au, grdAcIn(), grdBkIn(),
        CHOOSE ssLift() IF grdSs ELSE 0,
        CHOOSE grdCsPh() IF (grdCsv <> "" AND MOD(nn, GRD_LOG_EVERY) = 0) ELSE 0, SHIP:VELOCITY:ORBIT, grdGv()).
}
FUNCTION grdGv {                        // gravity here (m/s2, toward the body's centre)
    LOCAL rb IS SHIP:BODY:POSITION.
    RETURN rb:NORMALIZED * (SHIP:BODY:MU / rb:SQRMAGNITUDE).
}
FUNCTION grdBtnCss {                    // As in lib_dap: a forced CSS leaves the button as a click does: pressed, the CSS text, live
    PARAMETER pitch.
    IF pitch {
        IF DEFINED dBtnP { IF dBtnP:HASSUFFIX("ENABLED") { SET dBtnP:PRESSED TO TRUE. SET dBtnP:TEXT TO "PITCH  CSS". SET dBtnP:ENABLED TO TRUE. } }
    } ELSE {
        IF DEFINED dBtnR { IF dBtnR:HASSUFFIX("ENABLED") { SET dBtnR:PRESSED TO TRUE. SET dBtnR:TEXT TO "ROLL/YAW  CSS". SET dBtnR:ENABLED TO TRUE. } }
    }
}
FUNCTION grdCsAct {                     // the rare actions: the keyboard messages, the CSS buttons' text, the csv's LOG
    PARAMETER pa, px, pm.
    IF MOD(FLOOR(pa / 8), 2) = 1 { FOR km IN pm { addMsg(km). } }     // in kbAxis's order (pitch, roll, yaw), as grdTickK adds them
    IF MOD(FLOOR(pa / 16), 2) = 1 { grdBtnCss(TRUE). }     // The C# DAP's forced CSS (SW 01 ENTRY / SW 02): press the buttons
    IF MOD(FLOOR(pa / 32), 2) = 1 { grdBtnCss(FALSE). }
    IF MOD(pa, 2) = 1 {                 // the mode changes: grdTickK's events (lost on the C# path)
        noteEvent("GRTLS DAP: PITCH " + (CHOOSE "CSS" IF grdCssP ELSE "AUTO")).
        IF NOT dBtnP:ISTYPE("Scalar") { SET dBtnP:TEXT TO CHOOSE "PITCH  CSS" IF grdCssP ELSE "PITCH  AUTO". }
    }
    IF MOD(FLOOR(pa / 2), 2) = 1 {
        noteEvent("GRTLS DAP: ROLL/YAW " + (CHOOSE "CSS" IF grdCssR ELSE "AUTO")).
        IF NOT dBtnR:ISTYPE("Scalar") { SET dBtnR:TEXT TO CHOOSE "ROLL/YAW  CSS" IF grdCssR ELSE "ROLL/YAW  AUTO". }
    }
    IF MOD(FLOOR(pa / 4), 2) = 1 { LOG px TO grdCsv. }
}
FUNCTION grdCsTick {                    // TRUE: the addon flew this tick (the globals written, kOS applies the I/O)
    LOCAL co IS ADDONS:KALS:GRDTICK(grdCsIn()).
    IF co:ISTYPE("String") { grdCsOff("GRDTICK: " + co). RETURN FALSE. }
    SET GRD_CS_N TO GRD_CS_N + 1.
    ADDONS:KALS:FBW3(co[0], co[1], co[2]).
    IF co[3] > 0 { grdCsAct(co[3], co[4], co[5]). }
    RETURN TRUE.
}

// ONE PHYSICS TICK: the C# DAP's (GRD_CS), else kOS's grdTickK
FUNCTION grdTick {
    IF GRD_CS {
        IF grdCsOk < 0 { grdCsSetup(). }
        IF GRD_CS { IF grdCsTick() { RETURN. } }
    }
    grdTickK().
}

// ONE PHYSICS TICK in kOS (the C# DAP: coproc/Grd.cs)
FUNCTION grdTickK {
    LOCAL t IS TIME:SECONDS.
    LOCAL dtt IS MAX(t - grdT, 0.001).
    SET grdT TO t.
    SET grdN TO grdN + 1.
    LOCAL fv IS SHIP:FACING:FOREVECTOR.
    LOCAL tv IS SHIP:FACING:TOPVECTOR.
    LOCAL sv IS SHIP:FACING:STARVECTOR.
    LOCAL kp IS sv * -1.                              // the nose-up axis (ANGLEAXIS sense)
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL vh IS CHOOSE vs:NORMALIZED IF vs:MAG > 1 ELSE fv.
    LOCAL aoa IS ARCTAN2(-VDOT(vh, tv), VDOT(vh, fv)).
    LOCAL beta IS ARCSIN(MAX(-1, MIN(1, VDOT(vh, sv)))).   // + = the velocity to the right
    LOCAL w IS SHIP:ANGULARVEL * 57.2958.             // deg/s; w . -STAR = nose up, w . FORE = LEFT roll, w . TOP = nose right
    IF grdVhP:MAG > 0.5 {                             // the path's rotation (VCRS(v0, v1) / dt: the ANGLEAXIS sense)
        LOCAL pr IS VCRS(grdVhP, vh) * (57.2958 / dtt).
        IF pr:MAG < 30 { SET grdPath TO grdPath + (pr - grdPath) * MIN(1, dtt / PATH_TAU). }
    }
    SET grdVhP TO vh.
    LOCAL vo IS SHIP:VELOCITY:ORBIT.                  // the HUD's Nz: the sensed acceleration along the top
    IF grdVoP:MAG > 0.5 {
        LOCAL nz IS VDOT((vo - grdVoP) / dtt - grdGv(), tv) / 9.80665.
        IF ABS(nz) < 10 { SET grdNzM TO grdNzM + (nz - grdNzM) * MIN(1, dtt / PATH_TAU). }
    }
    SET grdVoP TO vo.
    LOCAL mach IS dapMach().
    IF MOD(grdN, GRD_AUTH_N) = 0 {                    // the limits first
        grdOmsGmb().
        SET grdAuth TO grdAuthRead().
        SET grdAk TO grdAuthK().
        SET grdAkR TO grdAuthK(GRD_AUTH_KR).
        SET grdYjr TO grdYjrAt().
    }
    LOCAL stk IS ADDONS:KALS:FBWPILOT().              // the pilot's p, r, y (+ = nose up, RIGHT roll, nose right)
    SET stk TO LIST(kbAxis(0, stk[0]), kbAxis(1, stk[1]), kbAxis(2, stk[2])).   // the keyboard mode (lib_dap)
    // SW 01 (on ENTRY) or SW 02 (ENTRY, past DAP_GD_LOST_S): the entry DAP's AUTO axes go CSS; RESTART SW gives AUTO back by the crew's press
    IF DEFINED FLFX_SWPROG {
        IF flfxSwAutoLost("ENTRY", "ENTRY") {
            IF NOT dReqP OR NOT dReqR { addMsg("AUTO DAP LOST: CSS ONLY"). }
            IF NOT dReqP { grdBtnCss(TRUE). }      // The buttons read CSS as a click leaves them (the C# twin: Grd.cs act 16 / 32)
            IF NOT dReqR { grdBtnCss(FALSE). }
            SET dReqP TO TRUE. SET dReqR TO TRUE.
        }
        IF flfxSwAlphaLost() { IF NOT dReqP { grdBtnCss(TRUE). } SET dReqP TO TRUE. }   // SW 02 ALPHA MOD (SimSup ALPHA FAIL): the pitch axis only
    }
    // the modes (lib_dap's buttons): each axis bumpless (the hold takes the attitude as it is)
    IF dReqP <> grdCssP {
        SET grdCssP TO dReqP.
        noteEvent("GRTLS DAP: PITCH " + (CHOOSE "CSS" IF grdCssP ELSE "AUTO")).
        SET grdHoldP TO FALSE.
        SET grdCapQT0 TO -1.
        IF NOT dBtnP:ISTYPE("Scalar") { SET dBtnP:TEXT TO CHOOSE "PITCH  CSS" IF grdCssP ELSE "PITCH  AUTO". }
    }
    IF dReqR <> grdCssR {
        SET grdCssR TO dReqR.
        noteEvent("GRTLS DAP: ROLL/YAW " + (CHOOSE "CSS" IF grdCssR ELSE "AUTO")).
        SET grdHoldR TO FALSE.
        SET grdCapT0 TO -1.
        IF NOT dBtnR:ISTYPE("Scalar") { SET dBtnR:TEXT TO CHOOSE "ROLL/YAW  CSS" IF grdCssR ELSE "ROLL/YAW  AUTO". }
    }
    // the commands: alpha and the lift (ramped between the guidance's passes)
    LOCAL ra IS grdRamp(grdRpA, grdAcIn(), t).
    LOCAL rb IS grdRamp(grdRpB, grdBkIn(), t).
    LOCAL qs IS 0.                                    // CSS: the stick's shaped rates (0 in the detent)
    LOCAL ps IS 0.
    IF grdCssP {
        SET qs TO STICK_P_SIGN * shapeP(stk[0], mach).
        IF qs <> 0 { SET grdHoldP TO FALSE. SET grdCapQT0 TO -1. }
        ELSE IF NOT grdHoldP {                          // in the detent: the alpha followed (the pitch damped), then held
            IF grdCapQT0 < 0 { SET grdCapQT0 TO t. }
            SET grdAHold TO aoa.
            IF ABS(VDOT(w - grdPath, kp)) < GRD_CAP_W OR t - grdCapQT0 > GRD_CAP_T { SET grdHoldP TO TRUE. SET grdCapQT0 TO -1. }
        }
    }
    LOCAL slP IS V(0, 0, 0).                          // SPLITS phase 8: ssLift across the velocity (the roll's reference)
    IF grdSs { SET slP TO VXCL(vh, ssLift()). }
    IF grdCssR {
        LOCAL gr IS grdStkR(stk[1]).
        SET ps TO STICK_R_SIGN * shapeR(gr, mach).      // + = LEFT (the kOS frame)
        IF ps <> 0 { SET ps TO ps + STICK_R_SIGN * cssRx(gr, mach). }   // lib_dap's, CSS_RMAX at full stick
        IF ps <> 0 { SET grdHoldR TO FALSE. SET grdCapT0 TO -1. }
        ELSE IF NOT grdHoldR {                          // in the detent: the bank followed (the roll damped), then held
            IF grdCapT0 < 0 { SET grdCapT0 TO t. }
            SET grdBHold TO CHOOSE grdSsRoll(vh, tv, slP) IF grdSs ELSE grdBankNow(vh, tv).
            IF ABS(VDOT(w, vh)) < GRD_CAP_W OR t - grdCapT0 > GRD_CAP_T { SET grdHoldR TO TRUE. SET grdCapT0 TO -1. }
        }
    }
    LOCAL ac IS CHOOSE grdAHold IF (grdCssP AND qs = 0) ELSE ra[0].
    LOCAL acd IS CHOOSE 0 IF grdCssP ELSE ra[1].
    LOCAL frzP IS FALSE.
    IF grdEnt AND GRD_AREF_TM > 0 AND NOT grdCssP {   // the entry's alpha reference model
        IF NOT grdAmOn { SET grdAm TO ac. SET grdAmOn TO TRUE. }
        LOCAL pf IS clampV(acd, GRD_AREF_FF).
        LOCAL da IS ac - grdAm.
        LOCAL ka IS MIN(1, dtt / GRD_AREF_TM).
        SET grdAm TO grdAm + pf * dtt + da * ka.
        SET acd TO pf + (da - da * ka) / GRD_AREF_TM.
        SET frzP TO ABS(acd - pf) > GRD_AREF_FZ.
        SET ac TO grdAm.
    } ELSE { SET grdAmOn TO FALSE. }
    LOCAL lt IS V(0, 0, 0).                           // the target lift (top) direction, perpendicular to the velocity
    LOCAL bkc IS rb[0].
    LOCAL bkd IS rb[1].
    IF NOT grdSs AND GRD_ENT_TAU > 0 {                // the bank command prefiltered, its rate the ff
        IF NOT grdBfOn { SET grdBf TO bkc. SET grdBfOn TO TRUE. }
        LOCAL db IS MOD(bkc - grdBf + 540, 360) - 180.
        SET grdBf TO grdBf + db * MIN(1, dtt / GRD_ENT_TAU).
        SET bkd TO (db - db * MIN(1, dtt / GRD_ENT_TAU)) / GRD_ENT_TAU.
        SET bkc TO grdBf.
    }
    IF grdCssR {
        SET bkc TO grdBHold.
        SET bkd TO 0.
        SET grdBfOn TO FALSE.                          // back to AUTO from the bank as it is
    }
    IF grdSs AND NOT grdCssR {
        SET lt TO slP.
    } ELSE IF grdSs {                                 // CSS in phase 8: the held roll from ssLift
        IF slP:MAG > 0.01 { SET lt TO ANGLEAXIS(bkc, vh) * slP:NORMALIZED. }
    } ELSE {
        LOCAL upP IS VXCL(vh, SHIP:UP:VECTOR).
        IF upP:MAG > 0.01 { SET lt TO ANGLEAXIS(bkc, vh) * upP:NORMALIZED. }
    }
    LOCAL topP IS VXCL(vh, tv).
    LOCAL eps IS 0.                                   // the roll about the velocity from the top to the lift, deg
    IF lt:MAG > 0.01 AND topP:MAG > 0.01 { SET eps TO ARCTAN2(VDOT(vh, VCRS(topP, lt)), VDOT(topP, lt)). }
    LOCAL kc IS MIN(1, GRD_WARP_KY * GRD_T_P / dtt).  // the yaw's warp cap: gain x tick (dtt / T) <= GRD_WARP_KY
    LOCAL kcw IS MIN(1, GRD_WARP_KT * GRD_T_P / dtt). // the pitch / roll loops' (1 to 0.045 s ticks), the outer
    LOCAL qa IS clampV(GRD_KA * kcw * (ac - aoa) + acd, GRD_QLIM).   //   loops scaled alike
    LOCAL rv IS clampV(GRD_KPHI * kcw * eps + bkd, GRD_PLIM).
    IF grdCssR AND ps <> 0 { SET rv TO ps. }
    LOCAL om IS kp * qa + vh * rv + tv * (GRD_KB * kcw * beta) + grdPath.
    LOCAL qc IS VDOT(om, kp).
    IF grdCssP AND qs <> 0 { SET qc TO qs. }          // CSS: the stick's body pitch rate
    LOCAL pc IS VDOT(om, fv).                         // + = LEFT
    LOCAL rc IS VDOT(om, tv).                         // + = nose right
    LOCAL wq IS VDOT(w, kp).
    LOCAL wp IS VDOT(w, fv).
    LOCAL wr IS VDOT(w, tv).
    SET grdWc TO LIST(0 - pc, qc, rc).               // the entry page's RATE arrows (+ = right roll)
    LOCAL cmdP IS grdPI(0, (qc - wq) / (GRD_T_P * MAX(grdAuth[0] * grdAk, GRD_A_MIN)), kcw, dtt, frzP).   // P + I
    LOCAL cmdR IS grdPI(1, -(pc - wp) / (GRD_T_R * MAX(grdAuth[1] * grdAkR, GRD_A_MIN)), kcw, dtt). // ctrl + = RIGHT
    LOCAL auY IS MAX(grdAuth[2] * grdAk, GRD_A_MIN).
    SET auY TO MAX(auY, GRD_YJA).                     // the yaw jets' floor
    LOCAL cmdY IS grdPI(2, (rc - wr) / (GRD_T_Y * auY), kc, dtt).
    IF NOT grdSs { SET cmdR TO clampV(cmdR + grdYjr * cmdY, 1). }   // the aileron takes out the yaw jets' roll
    SET grdU TO LIST(cmdP, cmdR, cmdY).
    ADDONS:KALS:FBW3(cmdP, cmdR, cmdY).
    IF grdCsv <> "" AND MOD(grdN, GRD_LOG_EVERY) = 0 {
        LOCAL ph IS 0.
        IF DEFINED GR { IF GR:ISTYPE("Lexicon") { IF GR:HASKEY("iphase") { SET ph TO GR["iphase"]. } } }
        SET grdBuf TO grdBuf + (CHOOSE "" IF grdBufN = 0 ELSE CHAR(10)) + ROUND(t, 2) + "," + ROUND(mach, 3) + ","
            + ROUND(SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA, 3) + "," + ph + "," + (CHOOSE 1 IF grdSs ELSE 0) + ","
            + (CHOOSE 1 IF grdCssP ELSE 0) + "," + (CHOOSE 1 IF grdCssR ELSE 0) + "," + (CHOOSE 1 IF grdHoldP ELSE 0) + ","
            + (CHOOSE 1 IF grdHoldR ELSE 0) + "," + ROUND(aoa, 3) + "," + ROUND(ac, 3) + "," + ROUND(acd, 3) + ","
            + ROUND(beta, 3) + "," + ROUND(grdBankNow(vh, tv), 2) + "," + ROUND(bkc, 2) + "," + ROUND(bkd, 3) + ","
            + ROUND(eps, 3) + "," + ROUND(qc, 3) + "," + ROUND(pc, 3) + "," + ROUND(rc, 3) + "," + ROUND(wq, 3) + ","
            + ROUND(wp, 3) + "," + ROUND(wr, 3) + "," + ROUND(cmdP, 4) + "," + ROUND(cmdR, 4) + "," + ROUND(cmdY, 4) + ","
            + ROUND(grdAuth[0], 3) + "," + ROUND(grdAuth[1], 3) + "," + ROUND(grdAuth[2], 3) + "," + ROUND(stk[0], 3)
            + "," + ROUND(stk[1], 3) + "," + ROUND(stk[2], 3) + "," + ROUND(grdPath:MAG, 3) + "," + ROUND(grdI[0], 4)
            + "," + ROUND(grdI[1], 4) + "," + ROUND(grdI[2], 4) + "," + ROUND(grdAk, 3) + "," + ROUND(grdNzM, 3).
        SET grdBufN TO grdBufN + 1.
        IF grdBufN >= GRD_FLUSH {
            LOG grdBuf TO grdCsv.
            SET grdBuf TO "".
            SET grdBufN TO 0.
        }
    }
}

// the roll stick past GRD_R_DB, rescaled onto lib_dap's detent: shapeR / cssRx start from 0 at GRD_R_DB and full
// stick stays full
FUNCTION grdStkR {
    PARAMETER g.
    LOCAL x IS ABS(g) * RHC_FULL.
    IF x <= GRD_R_DB { RETURN 0. }
    LOCAL y IS (R_DB + (x - GRD_R_DB) * (RHC_FULL - R_DB) / (RHC_FULL - GRD_R_DB)) / RHC_FULL.
    IF g < 0 { RETURN -y. }
    RETURN y.
}

// one axis's command: the P (e x kc) + the integral, clamped to +-1; the integral frozen while the sum is at the
// clamp and the error pushes further (no wind-up), held to +-GRD_I_MAX
FUNCTION grdPI {
    PARAMETER i, er, kc, dtt, frz IS FALSE.     // frz: the integral holds
    LOCAL uu IS er * kc + grdI[i].
    IF NOT frz AND NOT (ABS(uu) >= 1 AND uu * er > 0) { SET grdI[i] TO clampV(grdI[i] + er * kc * dtt / GRD_TI, GRD_I_MAX). }
    RETURN clampV(er * kc + grdI[i], 1).
}

// the yaw jets' roll as a share of the aileron's at the q now (GRD_YJR_Q / GRD_YJR_V, linear, held at the ends); in
// the FAR entry blended to GRD_YJR_EV by Mach
FUNCTION grdYjrAt {
    LOCAL qk IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA.
    LOCAL n IS GRD_YJR_Q:LENGTH.
    LOCAL sh IS GRD_YJR_V[n - 1].
    IF qk <= GRD_YJR_Q[0] { SET sh TO GRD_YJR_V[0]. }
    ELSE {
        FROM { LOCAL i IS 1. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
            IF qk < GRD_YJR_Q[i] {
                SET sh TO GRD_YJR_V[i - 1] + (GRD_YJR_V[i] - GRD_YJR_V[i - 1]) * (qk - GRD_YJR_Q[i - 1]) / (GRD_YJR_Q[i] - GRD_YJR_Q[i - 1]).
                BREAK.
            }
        }
    }
    IF (grdEnt OR NOT GRD_YJR_E_ENT) AND GRD_YJR_EM:LENGTH > 0 {
        LOCAL m IS dapMach().
        LOCAL w IS MAX(0, MIN(1, (m - GRD_YJR_EB[0]) / (GRD_YJR_EB[1] - GRD_YJR_EB[0]))).
        SET sh TO sh + (grdLinAt(GRD_YJR_EM, GRD_YJR_EV, m) - sh) * w.
    }
    RETURN sh.
}

// gy (a list) on gx (its knots, rising) at m: linear, held past the ends
FUNCTION grdLinAt {
    PARAMETER gx, gy, m.
    IF m <= gx[0] { RETURN gy[0]. }
    FROM { LOCAL i IS 1. } UNTIL i >= gx:LENGTH STEP { SET i TO i + 1. } DO {
        IF m <= gx[i] { RETURN gy[i - 1] + (gy[i] - gy[i - 1]) * (m - gx[i - 1]) / (gx[i] - gx[i - 1]). }
    }
    RETURN gy[gx:LENGTH - 1].
}

// FBWAUTH (deg/s2: pitch, roll, yaw; the stock entry's roll x GRD_AUTH_ALPHA_R); under FAR FBWAUTHS (GRD_AUTH_FAR_S
// FALSE, or FBWAUTHSON FALSE: SockFarTrim without FAR's members (grdAuthFb): FBWAUTH x GRD_AUTH_FAR). The kOS tick and
// the C# tick (GRDTICK's AUTH read, grdCsIn) both take it from here.
FUNCTION grdAuthRead {
    LOCAL x IS ADDONS:KALS:FBWAUTHX().   // [0-2] FBWAUTHS (stock: = FBWAUTH), [3-5] surfaces, [6-8] RCS, [9-11] the rest
    IF NOT ((DEFINED FAR_ON) AND FAR_ON) {
        LOCAL kr IS 1.
        IF grdEnt AND GRD_AUTH_ALPHA_R:LENGTH > 0 { SET kr TO grdTabAt(GRD_AUTH_ALPHA_R, grdAcIn()). }
        RETURN grdJets(LIST(x[0], x[1], x[2]), x, LIST(1, kr, 1)).
    }
    SET grdAuthFb TO NOT ADDONS:KALS:FBWAUTHSON().
    IF GRD_AUTH_FAR_S AND NOT grdAuthFb {
        LOCAL m IS dapMach().
        LOCAL kr IS 1.
        LOCAL kp IS grdTabAt(GRD_AUTH_FAR_P, m).
        IF grdEnt { SET kr TO grdTabAt(GRD_AUTH_FAR_R, m). SET kp TO kp * grdTabAt(GRD_AUTH_FAR_PL, m). }
        RETURN grdAuthSlew(grdJets(LIST(x[0], x[1], x[2]), x, LIST(kp, kr, 1)), m).
    }
    LOCAL ky IS 1 + (GRD_AUTH_FAR[2] - 1) * MAX(0, MIN(1, (dapMach() - GRD_AUTH_FAR_M[0]) / (GRD_AUTH_FAR_M[1] - GRD_AUTH_FAR_M[0]))).
    RETURN grdJets(LIST(x[3] + x[6] + x[9], x[4] + x[7] + x[10], x[5] + x[8] + x[11]), x, LIST(GRD_AUTH_FAR[0], GRD_AUTH_FAR[1], ky)).
}

// the read a (pitch, roll, yaw) x the tables' k, the RCS group's share (x[6-8]) swapped for GRD_RCS_A where it reads
FUNCTION grdJets {
    PARAMETER a, x, k.
    LOCAL o IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
        LOCAL au IS a[i] * k[i].
        IF GRD_RCS_A:LENGTH = 3 { IF GRD_RCS_A[i] > 0 AND x[6 + i] >= GRD_RCS_ON { SET au TO (a[i] - x[6 + i]) * k[i] + GRD_RCS_A[i]. } }
        o:ADD(au).
    }
    RETURN o.
}

// FBWAUTHS's read slew-limited (GRD_AUTH_SLEW above): each axis within the last value x / GRD_AUTH_SLEW ^ dt inside
// Mach GRD_AUTH_SLEW_M; the value kept for the next read
FUNCTION grdAuthSlew {
    PARAMETER a, m.
    LOCAL t IS TIME:SECONDS.
    IF m >= GRD_AUTH_SLEW_M[0] AND m <= GRD_AUTH_SLEW_M[1] AND grdAuS:LENGTH = 3 {
        LOCAL k IS GRD_AUTH_SLEW ^ MAX(0, t - grdAuST).
        FROM { LOCAL i IS 0. } UNTIL i > 2 STEP { SET i TO i + 1. } DO {
            IF a[i] > 0 AND grdAuS[i] > 0 { SET a[i] TO MAX(grdAuS[i] / k, MIN(grdAuS[i] * k, a[i])). }
        }
    }
    SET grdAuS TO a.
    SET grdAuST TO t.
    RETURN a.
}

// a LIST(LIST(x, v), ...) table at x: linear, held past the ends
FUNCTION grdTabAt {
    PARAMETER tb, x.
    IF x <= tb[0][0] { RETURN tb[0][1]. }
    FROM { LOCAL i IS 1. } UNTIL i >= tb:LENGTH STEP { SET i TO i + 1. } DO {
        IF x <= tb[i][0] { RETURN tb[i - 1][1] + (tb[i][1] - tb[i - 1][1]) * (x - tb[i - 1][0]) / (tb[i][0] - tb[i - 1][0]). }
    }
    RETURN tb[tb:LENGTH - 1][1].
}

// FBWAUTH's share the vehicle has: 1 below GRD_AUTH_Q0 kPa (RCS), kk from GRD_AUTH_Q1, linear between (kk: GRD_AUTH_K,
// the roll's GRD_AUTH_KR)
FUNCTION grdAuthK {
    PARAMETER kk IS GRD_AUTH_K.
    LOCAL qk IS SHIP:DYNAMICPRESSURE * CONSTANT:ATMTOKPA.
    RETURN 1 - (1 - kk) * MAX(0, MIN(1, (qk - GRD_AUTH_Q0) / (GRD_AUTH_Q1 - GRD_AUTH_Q0))).
}

// The OMS gimbals read the stick, so they are limited to GRD_OMS_LIM_OFF (they barely move); while an OMS engine fires
// (the dump) its gimbal needs its range. Every 0.1 s (and at the start) each OMS gimbal's limit follows its engine:
// GRD_OMS_LIM_ON while it burns (IGNITION, no flameout), GRD_OMS_LIM_OFF once it is off; written only on a change. The
// stick's readback (the addon's actuation, before the limit) reads the same either way; FBWAUTH counts a lit gimbal's
// torque.
// an engine ops2q failed (omsOutIs) found lit is shut down here
// again (an action group or a stray toggle may have lit it; noted once per 10 s) and its limit stays OFF.
FUNCTION grdOmsGmb {
    FOR o IN grdOms {
        LOCAL bad IS omsOutIs(o[0]).
        IF bad AND o[0]:IGNITION {
            o[0]:SHUTDOWN().
            IF TIME:SECONDS - o[3] > 10 {
                SET o[3] TO TIME:SECONDS.
                noteEvent("OMS " + o[0]:TITLE + " FAILED (1:/oms_out.txt) and found lit: shut down again").
            }
        }
        LOCAL lim IS CHOOSE GRD_OMS_LIM_ON IF (o[0]:IGNITION AND NOT o[0]:FLAMEOUT AND NOT bad) ELSE GRD_OMS_LIM_OFF.
        IF lim <> o[2] {
            IF o[1]:HASFIELD("gimbal limit") { o[1]:SETFIELD("gimbal limit", lim). }
            IF o[2] >= 0 { noteEvent("OMS gimbal " + lim + " %: " + o[0]:TITLE + (CHOOSE " lit" IF lim = GRD_OMS_LIM_ON ELSE " off")). }
            SET o[2] TO lim.
        }
    }
}

// SPDBK CSS in the GRTLS (AUTO = the entry's schedule, CSS = the throttle): lib_dap's lever law, armed at once with a
// live AFBW lever (dapLevLive), else once kOS reads the lever SB_LEVER_ARM from its start; until then the brake stays
// where it is. 0 % = open 98.6, 100 % = shut, capped above SB_SUPER_MACH at 2 x SB_SUPER_MAX (65: the whole GRTLS is
// above Mach 1.5). The writer: the entry's halves.
FUNCTION grdSbMan {
    LOCAL lev IS SHIP:CONTROL:PILOTMAINTHROTTLE.
    IF NOT grdSbLever AND (dapLevLive() OR ABS(lev - grdThr0) > SB_LEVER_ARM) {
        SET grdSbLever TO TRUE.
        noteEvent("SPDBK LEVER ARMED: kOS reads the throttle (" + ROUND(100 * lev) + " %); in CSS it is the brake").
    }
    IF NOT grdSbLever { RETURN. }
    LOCAL h IS 2 * RUD_HALF_LIM * (1 - MAX(0, MIN(1, lev))).
    IF dapMach() > SB_SUPER_MACH { SET h TO MIN(h, 2 * SB_SUPER_MAX). }
    IF ABS(h - ENTRY_SB_SET) < 0.5 { RETURN. }
    IF surfListRefind("sbrud") { ENTRY_SB_RUD:CLEAR(). }   // A splashdown's rebuild: found again below
    IF ENTRY_SB_RUD:LENGTH = 0 {
        FOR m IN SHIP:MODULESNAMED(SURF_MN) {
            IF m:PART:NAME:TOLOWER:CONTAINS("rudder") { ENTRY_SB_RUD:ADD(modReg(m, ENTRY_SB_RUD:LENGTH)). }
        }
        surfListMark("sbrud").
    }
    IF ENTRY_SB_RUD:LENGTH <> 2 { RETURN. }
    IF NOT (surfFrozen(ENTRY_SB_RUD[0]) OR surfFrozen(ENTRY_SB_RUD[1])) {      // A rudder half failed = no speedbrake (the good half is the rudder's)
        IF FAR_ON { surfSetAng(ENTRY_SB_RUD[0], h / 2). surfSetAng(ENTRY_SB_RUD[1], h / 2, -1). }
        ELSE { FOR m IN ENTRY_SB_RUD { IF modLive(m) AND NOT surfFrozen(m) { m:SETFIELD("deploy", TRUE). m:SETFIELD("deploy angle", h / 2). } } }
    }
    SET ENTRY_SB_SET TO h.
    SET sbThrottle TO 1 - h / 98.6.
}

// THE HUD IN THE GRTLS (toggleable, off by default): loaded on the first HUD / HUD CAM press (here, in the loop: a
// blocking file load the trigger flies through), then called every tick while shown (ops6q's loop; hdTick / hdgTick
// hold it to HD_MAX_HZ); the landing runway (RWY_NAME, SPLITS: ssPick's), no overlay in a BLUE.
// lib_hudg's symbols as TAEM's before PRFNL (hdFdMode: no velocity vector, the ladder about the frozen FD square): the
// diamond off the square by the bank error (the slewed bank in AUTO, the guidance's in CSS roll, as TAEM's; none in
// SPLITS phase 8) and the Nz error -- the GRTLS flies alpha, so the error is the alpha error x the model's Nz per deg
// there (grtlsNz, once a guidance cycle), held to GRD_HUD_NZE -- the measured G beside the square, the phase word
// (ALPREC / NZHOLD / ALPTRN or S-TURN / BAILOUT / SPLIT-S: the FSSR's phase 6 / 5 / 4, our 7 / 8) on the speedbrake's row
FUNCTION grdHudPass {
    IF dHudReq AND NOT hdOK {
        SET dHudReq TO FALSE.
        SET dHud TO hdInit().
        IF NOT dHud {
            noteEvent("*** GRTLS HUD: not loaded (" + HD_ARCH + ": see the terminal)").
            IF NOT dBtnHud:ISTYPE("Scalar") { SET dBtnHud:PRESSED TO FALSE. SET dBtnHud:TEXT TO "HUD OFF". }
            SET hdVis TO FALSE.
            SET dCamWant TO FALSE.
            IF NOT dBtnCam:ISTYPE("Scalar") { SET dBtnCam:PRESSED TO FALSE. SET dBtnCam:TEXT TO "HUD CAM OFF". }
            RETURN.
        }
        SET hdRwyAuto TO FALSE.
        SET hdFinalOn TO FALSE.
        SET grdHudRwy TO "".
        noteEvent("GRTLS HUD loaded (" + (CHOOSE "shown" IF hdVis ELSE "hidden") + ")").
    }
    IF NOT hdOK { RETURN. }
    IF NOT hdgOK {                                    // the guidance symbols (lib_hudg: re-entrant for landRun)
        IF hdgInit() { noteEvent("GRTLS HUD: the FD square, the guidance diamond and the G-meter (lib_hudg)"). }
        ELSE { noteEvent("*** GRTLS HUD: lib_hudg's sprites missing: the velocity vector as before"). }
    }
    IF dCamWant {
        SET dCamWant TO FALSE.
        IF hdCamSnap() {
            SET dBtnCam:TEXT TO "HUD CAM ON".
        } ELSE {
            SET dBtnCam:PRESSED TO FALSE.
            SET dBtnCam:TEXT TO "HUD CAM OFF".
        }
    }
    IF grdHudRwy <> RWY_NAME {
        SET grdHudRwy TO RWY_NAME.
        FROM { LOCAL k IS 0. } UNTIL k >= hdRwys:LENGTH STEP { SET k TO k + 1. } DO {
            IF hdRwys[k][1] = RWY_NAME { hdSelectRunway(k). }
        }
    }
    IF NOT grdEnt { IF GR["cont"] = 2 { SET hdRwyOn TO FALSE. } }   // a BLUE: no runway (the entry has no GR)
    SET hdCtlTxt TO CHOOSE "CSS" IF (grdCssP AND grdCssR) ELSE (CHOOSE "CSS P" IF grdCssP
        ELSE (CHOOSE "CSS R" IF grdCssR ELSE "AUTO")).
    SET hdSb TO H_SB_FULL * ENTRY_SB_SET / 2 / RUD_HALF_LIM.   // ENTRY_SB_SET: the total hinge (two halves)
    SET hdSbc TO hdSb.
    IF hdgOK { IF grdEnt { grdHudRecE(). } ELSE { grdHudRec(). } }   // the entry's or the GRTLS's
    hdTick().
    IF hdgOK { hdgTick(). }
}

// lib_hudg's record in the GRTLS (see grdHudPass)
FUNCTION grdHudRec {
    SET hdFdMode TO TRUE.
    SET hgDiaOff TO FALSE.
    SET hdgRec["vv"] TO FALSE.
    LOCAL ip IS GR["iphase"].
    SET hdgRec["phase"] TO CHOOSE "ALPREC" IF ip = 6 ELSE (CHOOSE "NZHOLD" IF ip = 5 ELSE (CHOOSE (CHOOSE "S-TURN"
        IF GR["istp4"] = 0 ELSE "ALPTRN") IF ip = 4 ELSE (CHOOSE "BAILOUT" IF ip = 7 ELSE (CHOOSE "SPLIT-S" IF ip = 8 ELSE "")))).
    SET hdgRec["css"] TO "".
    SET hdgRec["dm"] TO "".
    SET hdgRec["zoom"] TO FALSE.
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    IF grdSs {                                        // SPLITS phase 8: the roll error to ssLift (the bank now less it)
        LOCAL vhh IS CHOOSE vs:NORMALIZED IF vs:MAG > 1 ELSE SHIP:FACING:FOREVECTOR.
        LOCAL tvh IS SHIP:FACING:TOPVECTOR.
        SET hdgRec["bankDem"] TO 0 - (grdBankNow(vhh, tvh) - grdSsRoll(vhh, tvh, VXCL(vhh, ssLift()))).
    } ELSE {                                          // + = RIGHT (G4.9's); bankNow / bank_want + = LEFT
        SET hdgRec["bankDem"] TO 0 - (CHOOSE GR["bank_want"] IF grdCssR ELSE grdBkIn()).
    }
    LOCAL ac IS grdAcIn().
    IF GR["tnext"] <> grdNzTn {                       // the model's Nz per deg at the guidance's alpha, once a cycle
        SET grdNzTn TO GR["tnext"].
        LOCAL vr IS vs:MAG.
        SET grdNzSl TO MAX(0.005, (grtlsNz(ac + 1, ALTITUDE, vr) - grtlsNz(ac - 1, ALTITUDE, vr)) / 2).
    }
    SET hdgRec["nzm"] TO grdNzM.
    // in ALPREC and the split-S (phase 8 and its phase 5 pull-up) the alpha error itself at GRD_HUD_AR_K HUD deg a
    // degree, held to GRD_HUD_ENT_AMAX (the entry's way); the other phases the Nz error (the model's lift slope is
    // small at ALPREC's alpha, and the Nz error moves the split-S's diamond too little to fly to)
    IF ip = 6 OR grdSs OR (SS_ON AND ip = 5) { SET hdgRec["nzc"] TO grdNzM + clampV(ac - ldAlphaNow(), GRD_HUD_ENT_AMAX) * GRD_HUD_AR_K / hgDiaG. }
    ELSE { SET hdgRec["nzc"] TO grdNzM + clampV(grdNzSl * (ac - ldAlphaNow()), GRD_HUD_NZE). }
}

// THE ENTRY HUD: the GRTLS's symbols (grdHudRec) on the entry guidance (ops3q's, the AOA's too; ops6q's TAL), from EI,
// off by default. The phase word: PREENT until the guidance starts (EPR_GS_STARTED: the model drag reaches
// EPR_GUID_DRAG_INIT; the pre-entry bank / the TAL's 43 deg hold), DRAG while it tracks the family's drag, TRAN from
// EPR_AOA_HIGH_SPEED (eprAoA leaves its 40 deg; ops3q's AOA_HIGH_SPEED, sync_check pairs them), none on the fallback bank
// hold (no usable family). PREENT and TRAN are the FSSR's phases 1 and 5 (ISLECT); DRAG stands for its 2 / 3 / 4
// (temperature control, equilibrium glide, constant drag), which this one drag-tracking law does not split (USA005512
// 3.3.5 lists the HUD's words for TAEM and A/L only). The diamond: the bank error as the GRTLS's (the slewed bank in AUTO,
// the guidance's grdBkWant in CSS roll) and the Nz error = the alpha error x the lift's slope there (the measured lift
// FD_LIFT x the entry polar's dCL/dalpha / CL, every GRD_HUD_SL_S), held to GRD_HUD_NZE, as the GRTLS's (it flies alpha).
FUNCTION grdHudRecE {
    SET hdFdMode TO TRUE.
    SET hgDiaOff TO FALSE.
    SET hdgRec["vv"] TO FALSE.
    LOCAL vr IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL fb IS EPR_FAM_READY AND NOT EPR_FAM_OK.     // the fallback bank hold flies (ops3q / ops6q: no usable family;
    IF DEFINED GUID_SRC { IF GUID_SRC <> "epr" { SET fb TO TRUE. } }   //   the TAL's guidance runs while its build does)
    SET hdgRec["phase"] TO CHOOSE "" IF fb ELSE (CHOOSE "PREENT" IF NOT EPR_GS_STARTED
        ELSE (CHOOSE "TRAN" IF vr < EPR_AOA_HIGH_SPEED ELSE "DRAG")).
    SET hdgRec["css"] TO "".
    SET hdgRec["dm"] TO "".
    SET hdgRec["zoom"] TO FALSE.
    SET hdgRec["bankDem"] TO 0 - (CHOOSE grdBkWant IF grdCssR ELSE grdBkIn()).   // + = RIGHT (G4.9's)
    LOCAL ac IS grdAcIn().
    IF TIME:SECONDS - grdNzTe >= GRD_HUD_SL_S {
        SET grdNzTe TO TIME:SECONDS.
        LOCAL m IS eprMach(ALTITUDE, vr).
        LOCAL c0 IS eprCla(ac, m).
        LOCAL sl IS 0.
        IF c0 > 0.001 { SET sl TO FD_LIFT / EPR_G0 * (eprCla(ac + 1, m) - eprCla(ac - 1, m)) / 2 / c0. }
        SET grdNzSl TO MAX(0.005, sl).
    }
    SET hdgRec["nzm"] TO grdNzM.
    // the alpha error at GRD_HUD_ENT_K HUD deg a degree (lib_hudg draws hgDiaG HUD deg a g of nzc - nzm)
    SET hdgRec["nzc"] TO grdNzM + clampV(ac - ldAlphaNow(), GRD_HUD_ENT_AMAX) * GRD_HUD_ENT_K / hgDiaG.
}
