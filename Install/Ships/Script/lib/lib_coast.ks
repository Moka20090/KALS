// lib_coast.ks -- THE COAST TABLE AND THE HEADING TOWARD THE COAST for any user (the TAEM bailout's coast steering):
// lib_grtls's BLUE TOWARD THE COAST functions (grtlsCoastLoad / grtlsCoastNear / grtlsCoastSeg / grtlsShoreHdg /
// grtlsTrk and its midval /
// res180, rtls/grtls.py's _shore_hdg, the table blue/coast_kos.py's) copied with their arithmetic unchanged, renamed,
// the shore state passed in (cs) instead of lib_grtls's GR. lib_grtls keeps its own copy (unchanged); lib_land's
// bailout hold uses this one (ldBailCoast).
@LAZYGLOBAL OFF.

GLOBAL CST_FILE IS "0:/grtls_bg/coast_blue.txt".   // the coast table (GR_COAST_FILE's): the Atlantic's (lat 15..60, lng -85..5)
GLOBAL CST_FILE_W IS "0:/grtls_bg/coast_blue_w.txt".   // the Pacific's (California, Baja: lat 20..45, lng -135..-110)
FUNCTION cstFileHere {                // the table for where the orbiter is now: the Pacific's west of 100 W, else CST_FILE
    RETURN CHOOSE CST_FILE_W IF SHIP:GEOPOSITION:LNG < -100 ELSE CST_FILE.
}
GLOBAL CST IS LEXICON("ok", FALSE).   // cstLoad: the table ("ok" FALSE: none)
GLOBAL CST_DOFF IS 5000.0.            // m: the line off the coast (GR_BLUE_DOFF)
GLOBAL CST_KL IS 45.0.                // deg per turn radius: the lean toward that line (GR_BLUE_KL)
GLOBAL CST_TSEL IS 1.0.               // s between the coast searches (GR_BLUE_TSEL)
GLOBAL CST_PHILM IS 45.0.             // deg: the turn radius's bank (GR_BLUE_PHILM)

FUNCTION cstMid {
    PARAMETER a, b, c.
    RETURN MAX(MIN(a, MAX(b, c)), MIN(b, c)).
}

FUNCTION cstRes180 {
    PARAMETER x.
    UNTIL x <= 180.0 { SET x TO x - 360.0. }
    UNTIL x > -180.0 { SET x TO x + 360.0. }
    RETURN x.
}

FUNCTION cstShoreHdg {                    // the heading (deg) toward the line CST_DOFF off the nearest coast
    PARAMETER cs, sn.                       //   (rtls/grtls.py _shore_hdg); -1 off the table: wings level. cs: the
    //                                           user's state (sh_t -1, sh LIST(), sh_side 0); sn: t, lat, lng, sea,
    //                                           vr, gam, trk
    IF cs["sh_t"] < 0 OR sn["t"] - cs["sh_t"] >= CST_TSEL - 1E-9 {   // the search every CST_TSEL s
        LOCAL cn IS cstNear(sn["lat"], sn["lng"]).
        IF cn:LENGTH = 0 { SET cs["sh"] TO LIST(). } ELSE { SET cs["sh"] TO LIST(cn[0] * 1000, cn[1], cn[2], sn["sea"]). }
        SET cs["sh_t"] TO sn["t"].
    }
    IF cs["sh"]:LENGTH = 0 { RETURN -1. }
    LOCAL dm IS cs["sh"][0].
    LOCAL tang IS cs["sh"][1].
    LOCAL brg IS cs["sh"][2].
    LOCAL vh IS sn["vr"] * COS(sn["gam"]).
    LOCAL rt IS MAX(vh * vh / (9.80665 * TAN(CST_PHILM)), 1.0).
    LOCAL lean IS CST_KL * (CHOOSE (dm - CST_DOFF) IF cs["sh"][3] ELSE (dm + CST_DOFF)) / rt.
    IF lean >= 90.0 { RETURN brg. }         // far off: straight for the coast's nearest point
    LOCAL side0 IS CHOOSE 1 IF cstRes180(brg - tang) > 0.0 ELSE -1.   // the coast right (+1) / left of its direction
    IF cs["sh_side"] = 0 {                  // the side picked once: the coast's direction nearer the ground track's
        SET cs["sh_side"] TO CHOOSE side0 IF ABS(cstRes180(tang - sn["trk"])) <= 90.0 ELSE 0 - side0.
    }
    LOCAL tau IS CHOOSE tang IF side0 = cs["sh_side"] ELSE MOD(tang + 180.0, 360).
    RETURN MOD(tau + cs["sh_side"] * MAX(lean, -90.0) + 360.0, 360).
}

FUNCTION cstSeg {                    // coast segment k from (la, lo) deg: LIST(d km, dx, dy, cx, cy): the ends in a
    PARAMETER k, la, lo.                    //   local plane (x east = dlng cos(the mean latitude) R, y north = dlat R), c
    LOCAL sq IS CST["s"][k].           //   = the nearest point (rtls/coast.py's metric, in degrees)
    LOCAL pa IS CST["pa"].
    LOCAL po IS CST["po"].
    LOCAL rdk IS CST["rd"].
    LOCAL ax IS (po[sq] - lo) * COS(0.5 * (pa[sq] + la)) * rdk.
    LOCAL ay IS (pa[sq] - la) * rdk.
    LOCAL dx IS (po[sq + 1] - lo) * COS(0.5 * (pa[sq + 1] + la)) * rdk - ax.
    LOCAL dy IS (pa[sq + 1] - la) * rdk - ay.
    LOCAL l2 IS dx * dx + dy * dy.
    LOCAL u IS 0.0.
    IF l2 > 0 { SET u TO MAX(0.0, MIN(1.0, (0 - (ax * dx + ay * dy)) / l2)). }
    LOCAL cx IS ax + u * dx.
    LOCAL cy IS ay + u * dy.
    RETURN LIST(SQRT(cx * cx + cy * cy), dx, dy, cx, cy).
}

FUNCTION cstNear {                   // the nearest coast segment to (la, lo) deg among its cell's candidates:
    PARAMETER la, lo.                       //   LIST(d km, its heading a -> b deg, the bearing to its nearest point deg);
    LOCAL ci IS FLOOR((la - CST["lat0"]) / CST["dc"]).   //   LIST() off the table. A tie: the lowest index
    LOCAL cj IS FLOOR((lo - CST["lng0"]) / CST["dc"]).   //   within 1E-9 km (rtls/coast.py's TIE_KM)
    IF ci < 0 OR ci >= CST["nla"] OR cj < 0 OR cj >= CST["nlo"] { RETURN LIST(). }
    LOCAL tk IS CST["L"][3 + ci * CST["nlo"] + cj]:SPLIT(" ").
    LOCAL kc IS LIST().
    LOCAL ds IS LIST().
    LOCAL dmin IS 1E30.
    LOCAL n IS 0.
    UNTIL n + 1 >= tk:LENGTH {              // the runs a0 b0 a1 b1 ..
        LOCAL k IS tk[n]:TONUMBER(0).
        LOCAL kb IS tk[n + 1]:TONUMBER(0).
        UNTIL k > kb {
            LOCAL dk IS cstSeg(k, la, lo)[0].
            kc:ADD(k).
            ds:ADD(dk).
            IF dk < dmin { SET dmin TO dk. }
            SET k TO k + 1.
        }
        SET n TO n + 2.
    }
    IF kc:LENGTH = 0 { RETURN LIST(). }
    LOCAL qi IS 0.
    UNTIL ds[qi] <= dmin + 1E-9 { SET qi TO qi + 1. }
    LOCAL sg IS cstSeg(kc[qi], la, lo).
    RETURN LIST(sg[0], MOD(ARCTAN2(sg[1], sg[2]) + 360, 360), MOD(ARCTAN2(sg[3], sg[4]) + 360, 360)).
}

FUNCTION cstLoad {                   // the coast table (blue/coast_kos.py's text file; kOS's READJSON needs its own
    PARAMETER cpath.                        //   format): TRUE when read whole. Line 0 "COAST lat0 lng0 dc nla nlo R_KM
    SET CST TO LEXICON("ok", FALSE).   //   npts nseg", 1 "P lat lng ..", 2 "S k0 k1 ..", then the cells' runs (kept
    IF NOT EXISTS(cpath) { RETURN FALSE. }  //   as text, split at the search)
    LOCAL lns IS OPEN(cpath):READALL:STRING:REPLACE(CHAR(13), ""):SPLIT(CHAR(10)).
    IF lns:LENGTH < 3 { RETURN FALSE. }
    LOCAL hd IS lns[0]:SPLIT(" ").
    IF hd:LENGTH < 9 { RETURN FALSE. }
    IF hd[0] <> "COAST" { RETURN FALSE. }
    LOCAL nla IS hd[4]:TONUMBER(0).
    LOCAL nlo IS hd[5]:TONUMBER(0).
    IF lns:LENGTH < 3 + nla * nlo { RETURN FALSE. }
    LOCAL pt IS lns[1]:SPLIT(" ").
    LOCAL pa IS LIST().
    LOCAL po IS LIST().
    LOCAL n IS 1.
    UNTIL n + 1 >= pt:LENGTH {
        pa:ADD(pt[n]:TONUMBER(0)).
        po:ADD(pt[n + 1]:TONUMBER(0)).
        SET n TO n + 2.
    }
    LOCAL sx IS lns[2]:SPLIT(" ").
    LOCAL sl IS LIST().
    SET n TO 1.
    UNTIL n >= sx:LENGTH {
        sl:ADD(sx[n]:TONUMBER(0)).
        SET n TO n + 1.
    }
    IF pa:LENGTH <> hd[7]:TONUMBER(0) OR sl:LENGTH <> hd[8]:TONUMBER(0) { RETURN FALSE. }
    SET CST TO LEXICON("ok", TRUE, "L", lns, "lat0", hd[1]:TONUMBER(0), "lng0", hd[2]:TONUMBER(0),
                            "dc", hd[3]:TONUMBER(0), "nla", nla, "nlo", nlo, "rd", hd[6]:TONUMBER(0) * CONSTANT:PI / 180,
                            "pa", pa, "po", po, "s", sl).
    RETURN TRUE.
}

FUNCTION cstTrk {                         // the ground track's heading (deg, 0 = north, 90 = east), as ssSet's
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL vs IS SHIP:VELOCITY:SURFACE.
    LOCAL vh IS vs - VDOT(vs, upv) * upv.
    RETURN MOD(ARCTAN2(VDOT(vh, VCRS(upv, SHIP:NORTH:VECTOR)), VDOT(vh, SHIP:NORTH:VECTOR)) + 360, 360).
}
