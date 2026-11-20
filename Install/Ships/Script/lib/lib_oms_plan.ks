// lib_oms_plan.ks -- the OMS plans' one writer and the ATO's OMS-2 from the actual orbit. One ATO button replaces the
// AOA and ATO aborts; the decision to press to orbit or come back is a window after OMS-1. The run path: ops1q (an
// engine fails, abort ATO, plans OMS-1) --> shuttle_exec (flies OMS-1, asks AOA / ATO, plans the OMS-2 on the orbit
// OMS-1 left, unless OMS-1 is skipped) --> shuttle_exec again (flies OMS-2) --> fam_build --> ops3q (an AOA: the
// pre-entry bank and the alpha ramp).
// Loaded by ops1q.ks and shuttle_exec.ks; lib_aoa.ks writes the AOA's OMS-2 through omsPlanWrite (one
// format). Needs lib_ascent_iload.ks (ASC_ATO_H, ASC_OMS_ISP). The plan file = lib_plan.ks's planRead format, version
// 1, one "key value" per line; "tag" names the burn: "OMS-2" (the nominal), "ATO OMS-1", "ATO OMS-2", "AOA OMS-2".
@LAZYGLOBAL OFF.

// THE RADIAL PART'S INTERLOCK: TRUE = shuttle_exec.ks flies a plan's "dvr" (m/s, + = radial out: KSP's node
// RADIALOUT; absent = 0) as the burn's radial part, "dv" / "dir" the prograde part; lib_aoa.ks writes a radial AOA
// OMS-2 only when this is defined and TRUE, so neither half flies without the other.
GLOBAL OMS_PLAN_DVR IS TRUE.

// The plan file f in lib_plan.ks's format, so its planRead takes it (every value a number but the vessel, the runway
// and the tag; the deorbit's fields neutral): written at ut, the burn centred on tb (shuttle_exec centres it there and
// counts the dv from the thrust), dv m/s (>= 0) along the velocity, dr 1 = prograde (any other: retrograde), tag the
// burn's name. written_real_days = the real-world time (shuttle_exec flies the plan written last). An old f is replaced.
FUNCTION omsPlanWrite {
  PARAMETER f, ut, tb, dv, dr, tag.
  IF EXISTS(f) { DELETEPATH(f). }
  LOG "version 1" TO f.
  LOG "vessel " + SHIP:NAME TO f.
  LOG "written " + ROUND(ut, 3) TO f.
  LOG "written_real_days " + ROUND(KUNIVERSE:REALWORLDTIME / 86400, 7) TO f.
  LOG "epoch " + ROUND(ut, 3) TO f.
  LOG "burn_ut " + ROUND(tb, 3) TO f.
  LOG "rot_ut " + ROUND(tb, 3) TO f.
  LOG "runway none" TO f.
  LOG "aim_lat 0" TO f.
  LOG "aim_lng 0" TO f.
  LOG "fpa 0" TO f.
  LOG "bank 0" TO f.
  LOG "t_burn " + ROUND(tb - ut, 3) TO f.
  LOG "t_rot " + ROUND(tb - ut, 3) TO f.
  LOG "dv " + ROUND(dv, 4) TO f.
  LOG "dir " + dr TO f.
  LOG "ap_km " + ROUND(SHIP:APOAPSIS / 1000, 3) TO f.
  LOG "pe_km " + ROUND(SHIP:PERIAPSIS / 1000, 3) TO f.
  LOG "tag " + tag TO f.
}

// The ATO's OMS-2 from the actual orbit: at the apoapsis to the circle at ASC_ATO_H (at the apoapsis when that lies
// lower), dv = sqrt(mu (2/ra - 2/(ra + rt))) - v_a, prograde when > 0. LIST(now, the apoapsis' UT, dv m/s signed);
// LIST() with no apoapsis ahead.
FUNCTION omsAto {
  LOCAL ut IS TIME:SECONDS.
  IF SHIP:ORBIT:ECCENTRICITY >= 1 OR SHIP:APOAPSIS <= 0 OR ETA:APOAPSIS <= 0 { RETURN LIST(). }
  LOCAL ra IS BODY:RADIUS + SHIP:APOAPSIS.
  LOCAL rt IS MIN(BODY:RADIUS + ASC_ATO_H, ra).
  LOCAL va IS SQRT(BODY:MU * (2 / ra - 1 / SHIP:ORBIT:SEMIMAJORAXIS)).
  RETURN LIST(ut, ut + ETA:APOAPSIS, SQRT(BODY:MU * (2 / ra - 2 / (ra + rt))) - va).
}

// PRESS TO ORBIT: the ATO's OMS-2 plan to f, tagged "ATO OMS-2"; its dv (m/s, signed), 0 with nothing written (no
// apoapsis ahead).
FUNCTION omsPlanAto {
  PARAMETER f.
  LOCAL a IS omsAto().
  IF a:LENGTH = 0 { RETURN 0. }
  omsPlanWrite(f, a[0], a[1], ABS(a[2]), CHOOSE 1 IF a[2] >= 0 ELSE -1, "ATO OMS-2").
  RETURN a[2].
}

// m/s: the OMS propellant the AJ10s can burn (one AJ10's CONSUMEDRESOURCES at the mixture ratio, as ops1q's
// asc_burnable; the fuel cell's own tank is out of their reach) at ASC_OMS_ISP; 0 without an AJ10.
FUNCTION omsDvOnBoard {
  LOCAL mo IS 0.
  FOR en IN SHIP:ENGINES {
    IF mo = 0 AND en:NAME:CONTAINS("AJ10") {
      LOCAL n IS -1.
      LOCAL mm IS 0.
      FOR cr IN en:CONSUMEDRESOURCES:VALUES {
        IF cr:RATIO > 0 {
          LOCAL k IS cr:AMOUNT / cr:RATIO.
          IF n < 0 OR k < n { SET n TO k. }
          SET mm TO mm + cr:RATIO * cr:DENSITY.
        }
      }
      SET mo TO MAX(n, 0) * mm.
    }
  }
  IF mo <= 0 OR mo >= SHIP:MASS { RETURN 0. }
  RETURN ASC_OMS_ISP * CONSTANT:G0 * LN(SHIP:MASS / (SHIP:MASS - mo)).
}
