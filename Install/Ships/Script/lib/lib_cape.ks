// ============================================================================
//  LIB_CAPE.KS  --  WHERE THE KATNISS CAPE IS (moved or as published)
// ============================================================================
//  The scripts work with both the moved and the published KatnissCapeCanaveral. The moved install has the whole Cape
//  2.42 km west and 1.00 km south (a GameData patch); a player with the published mod has it where it was. Everything
//  at the Cape the scripts use is the SLF: its two thresholds (hud/hud_runways.txt) and its midpoint (TAL / RTLS / AOA
//  site).
//  CAPE_MOVED is decided once, when this file loads:
//    CAPE_SET "MOVED" / "ORIG" before the run forces it; "AUTO" (the default) asks the KAL/S addon where the Cape's
//    terrain mesh is (ADDONS:KALS:CAPEGEO, the City2 KCC_CapeCanaveral) and takes the nearer of its two known places
//    (within CAPE_TOL_DEG). With no addon, an older DLL, no Cape found, or a Cape at neither place: the published
//    place (what a player installs). CAPE_WHY says which and why (kals_test prints it).
//  hud/hud_runways.txt: rows "R" for every runway, and for the SLF "RM" (the moved Cape) and "RO" (the published
//  one); capeLine turns the matching set into "R" rows and blanks the other, so every reader goes on reading "R".
//  capeSlfMid: the SLF's midpoint (the thresholds' midpoint) for the Cape in place.

IF NOT (DEFINED CAPE_SET) { GLOBAL CAPE_SET IS "AUTO". }
GLOBAL CAPE_CITY_ORIG IS LIST(28.5857702, -80.6507262).        // KCC_CapeCanaveral as published (Patches/EarthPatch.cfg)
GLOBAL CAPE_CITY_MOVED IS LIST(28.549797392, -80.749848315).   // after the shift (the moved install)
GLOBAL CAPE_SLF_MID_ORIG IS LIST(28.669502, -80.775375).       // the SLF's midpoint as published
GLOBAL CAPE_SLF_MID_MOVED IS LIST(28.633529, -80.874386).      // after the shift (as KK places it)
GLOBAL CAPE_TOL_DEG IS 0.01.                                    // deg (~280 m on the quarter Earth): "at" a known place
GLOBAL CAPE_WHY IS "".

FUNCTION capeDeg {                          // deg between two LIST(lat, lng), longitude scaled by cos(lat)
    PARAMETER a, b.
    LOCAL dn IS a[0] - b[0].
    LOCAL de IS (a[1] - b[1]) * COS(b[0]).
    RETURN SQRT(dn * dn + de * de).
}

FUNCTION capeDetect {
    IF CAPE_SET = "MOVED" { SET CAPE_WHY TO "MOVED (CAPE_SET)". RETURN TRUE. }
    IF CAPE_SET = "ORIG" { SET CAPE_WHY TO "AS PUBLISHED (CAPE_SET)". RETURN FALSE. }
    IF NOT ADDONS:HASSUFFIX("KALS") { SET CAPE_WHY TO "AS PUBLISHED (assumed: no KAL/S addon)". RETURN FALSE. }
    IF NOT ADDONS:KALS:AVAILABLE { SET CAPE_WHY TO "AS PUBLISHED (assumed: KAL/S not available)". RETURN FALSE. }
    IF NOT ADDONS:KALS:HASSUFFIX("CAPEGEO") { SET CAPE_WHY TO "AS PUBLISHED (assumed: an older KalsCoproc.dll)". RETURN FALSE. }
    LOCAL g IS ADDONS:KALS:CAPEGEO.
    IF g:LENGTH < 2 { SET CAPE_WHY TO "AS PUBLISHED (assumed: no KCC_CapeCanaveral found)". RETURN FALSE. }
    LOCAL at IS ROUND(g[0], 5) + ", " + ROUND(g[1], 5).
    LOCAL dO IS capeDeg(g, CAPE_CITY_ORIG).
    LOCAL dM IS capeDeg(g, CAPE_CITY_MOVED).
    IF MIN(dO, dM) > CAPE_TOL_DEG { SET CAPE_WHY TO "AS PUBLISHED (assumed: the Cape is at " + at + ", neither place)". RETURN FALSE. }
    IF dM < dO { SET CAPE_WHY TO "MOVED (KCC_CapeCanaveral at " + at + ")". RETURN TRUE. }
    SET CAPE_WHY TO "AS PUBLISHED (KCC_CapeCanaveral at " + at + ")".
    RETURN FALSE.
}

GLOBAL CAPE_MOVED IS capeDetect().

// A hud_runways.txt line for the Cape in place: "RM ..." / "RO ..." -> "R ..." when it is the Cape's, "" when not;
// any other line as it is.
FUNCTION capeLine {
    PARAMETER lin.
    IF lin:STARTSWITH("RM ") { RETURN CHOOSE ("R " + lin:SUBSTRING(3, lin:LENGTH - 3)) IF CAPE_MOVED ELSE "". }
    IF lin:STARTSWITH("RO ") { RETURN CHOOSE "" IF CAPE_MOVED ELSE ("R " + lin:SUBSTRING(3, lin:LENGTH - 3)). }
    RETURN lin.
}

FUNCTION capeSlfMid {                       // the SLF's midpoint, LIST(lat, lng)
    RETURN CHOOSE CAPE_SLF_MID_MOVED IF CAPE_MOVED ELSE CAPE_SLF_MID_ORIG.
}
