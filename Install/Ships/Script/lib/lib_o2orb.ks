// lib_o2orb.ks -- ops2q's ORBIT MATHS (pure: vectors in, numbers out; no vessel, so the kOS VM runs it:
// tests/o2orb_selftest.ks): the conic from a state, a state on the conic, the time between two true anomalies, the
// shuttle's LVLH frame, the ORBIT / PTG and BRN PLN orbit view, and the BRN PLN burns (CIRC, HA, HP, PLANE).
// HANDEDNESS. KSP's frame is left-handed, and VCRS is the component formula, so VCRS(r, v) points against the physical
// angular momentum there. Everything here is built so it does not matter: the true north (the host's
// (LATLNG(90, 0):POSITION - BODY:POSITION):NORMALIZED) picks the ascending node (the node where the motion is north),
// VCRS(h, x) of an in-plane x is the direction of motion at x either way (BAC-CAB is component algebra), and the one
// place a physical sense is needed (LVLH +Y, the local east) reads O2_LH, which the host sets once from kOS's own
// ORBIT:INCLINATION (o2Handed). The VM tests run both senses.
// Angles are degrees (kOS's trig), anomalies of the conic too; times s, lengths m.

GLOBAL O2_LH IS TRUE.                        // TRUE = the vectors are KSP's (left-handed); o2Handed sets it
GLOBAL O2_EQ_INC IS 0.05.                    // deg: below this (or above 180 less it) the node line is the equinox's
GLOBAL O2_VIEW_ALT_X IS 5.                   // the orbit view draws altitudes this many times larger

FUNCTION o2Handed {                          // the host's once: VCRS(r, v)'s angle to north against kOS's inclination
    PARAMETER rv, vv, npole, incKos.
    LOCAL ang IS o2Ang(VCRS(rv, vv), npole).
    SET O2_LH TO ABS(ang - (180 - incKos)) < ABS(ang - incKos).
    RETURN O2_LH.
}

FUNCTION o2Ang {                             // VANG (the kOS VM has none): deg between a and b
    PARAMETER a, b.
    RETURN ARCCOS(MAX(-1, MIN(1, VDOT(a, b) / MAX(1E-30, a:MAG * b:MAG)))).
}
FUNCTION o2Unit { PARAMETER x. IF x:MAG < 1E-12 { RETURN V(0, 0, 0). } RETURN x / x:MAG. }

// the conic of (rv, vv) about a body of gravitational parameter mu: LEXICON(a, e, p, ra, rp, inc, argp, ta, period,
// n (rad/s; 0 when not bound), h (VCRS(rv, vv)), px (unit, to periapsis), qx (unit, the motion at periapsis; kOS keys are case-blind: p is taken), e1 (unit,
// to the ascending node; the equinox on an equatorial orbit), e2 (unit, the motion at e1), mu)
FUNCTION o2Els {
    PARAMETER rv, vv, mu, npole, eqx IS V(1, 0, 0).
    LOCAL rm IS rv:MAG.
    LOCAL hv IS VCRS(rv, vv).
    LOCAL ev IS VCRS(vv, hv) / mu - rv / rm.
    LOCAL e IS ev:MAG.
    LOCAL en IS vv:SQRMAGNITUDE / 2 - mu / rm.
    LOCAL a IS CHOOSE -mu / (2 * en) IF ABS(en) > 1E-9 ELSE 1E30.
    LOCAL p IS hv:SQRMAGNITUDE / mu.
    LOCAL pu IS CHOOSE ev / e IF e > 1E-9 ELSE rv / rm.    // a circle: the periapsis at the state (ta 0)
    LOCAL qu IS o2Unit(VCRS(hv, pu)).
    // the node line: VCRS(h, north) is in both planes; its sign makes the motion there northward
    LOCAL nd IS VCRS(hv, npole).
    LOCAL incF IS o2Ang(hv, npole).
    LOCAL inc IS CHOOSE 180 - incF IF O2_LH ELSE incF.
    LOCAL e1 IS V(0, 0, 0).
    IF nd:MAG > hv:MAG * SIN(O2_EQ_INC) {
        SET e1 TO nd:NORMALIZED.
        IF VDOT(VCRS(hv, e1), npole) < 0 { SET e1 TO -e1. }
    } ELSE {
        SET e1 TO o2Unit(eqx - hv * (VDOT(eqx, hv) / hv:SQRMAGNITUDE)).   // the equinox, in the plane
    }
    LOCAL e2 IS o2Unit(VCRS(hv, e1)).
    LOCAL argp IS MOD(ARCTAN2(VDOT(pu, e2), VDOT(pu, e1)) + 360, 360).
    LOCAL ta IS MOD(ARCTAN2(VDOT(rv, qu), VDOT(rv, pu)) + 360, 360).
    LOCAL nn IS CHOOSE SQRT(mu / a ^ 3) IF e < 1 AND a > 0 ELSE 0.
    LOCAL per IS CHOOSE 2 * CONSTANT:PI / nn IF nn > 0 ELSE 0.
    RETURN LEXICON("a", a, "e", e, "p", p, "ra", CHOOSE a * (1 + e) IF e < 1 ELSE 1E30, "rp", p / (1 + e),
        "inc", inc, "argp", argp, "ta", ta, "period", per, "n", nn, "h", hv, "px", pu, "qx", qu, "e1", e1, "e2", e2,
        "mu", mu).
}

FUNCTION o2AtTA {                            // LIST(r, v) on the conic at true anomaly nu (deg)
    PARAMETER el, nu.
    LOCAL rm IS el["p"] / (1 + el["e"] * COS(nu)).
    LOCAL rv IS (el["px"] * COS(nu) + el["qx"] * SIN(nu)) * rm.
    LOCAL k IS SQRT(el["mu"] / el["p"]).
    LOCAL vv IS (el["px"] * -SIN(nu) + el["qx"] * (el["e"] + COS(nu))) * k.
    RETURN LIST(rv, vv).
}

FUNCTION o2MofTA {                           // the mean anomaly (rad, 0 .. 2 pi) at nu, an ellipse
    PARAMETER e, nu.
    LOCAL ea IS 2 * ARCTAN2(SQRT(1 - e) * SIN(nu / 2), SQRT(1 + e) * COS(nu / 2)).   // deg
    LOCAL m IS ea * CONSTANT:PI / 180 - e * SIN(ea).
    IF m < 0 { SET m TO m + 2 * CONSTANT:PI. }
    RETURN m.
}

FUNCTION o2TAofM {                           // the true anomaly (deg) at mean anomaly m (rad), an ellipse (Newton)
    PARAMETER e, m.
    LOCAL ea IS m.
    IF e > 0.8 { SET ea TO CONSTANT:PI. }
    FROM { LOCAL i IS 0. } UNTIL i >= 30 STEP { SET i TO i + 1. } DO {
        LOCAL f IS ea - e * SIN(ea * 180 / CONSTANT:PI) - m.
        LOCAL d IS f / (1 - e * COS(ea * 180 / CONSTANT:PI)).
        SET ea TO ea - d.
        IF ABS(d) < 1E-12 { BREAK. }
    }
    LOCAL ed IS ea * 180 / CONSTANT:PI.
    RETURN MOD(2 * ARCTAN2(SQRT(1 + e) * SIN(ed / 2), SQRT(1 - e) * COS(ed / 2)) + 720, 360).
}

FUNCTION o2DtTA {                            // s from nu0 forward to nu1 on a bound conic (0 .. one period)
    PARAMETER el, nu0, nu1.
    IF el["n"] <= 0 { RETURN -1. }
    LOCAL dm IS o2MofTA(el["e"], nu1) - o2MofTA(el["e"], nu0).
    IF dm < 0 { SET dm TO dm + 2 * CONSTANT:PI. }
    RETURN dm / el["n"].
}

FUNCTION o2TAafter {                         // the true anomaly dt s after nu0 (a bound conic)
    PARAMETER el, nu0, dt.
    LOCAL m IS o2MofTA(el["e"], nu0) + el["n"] * dt.
    SET m TO m - 2 * CONSTANT:PI * FLOOR(m / (2 * CONSTANT:PI)).
    RETURN o2TAofM(el["e"], m).
}

FUNCTION o2TAof {                            // the anomaly of a WHEN on the conic: APO PERI AN DN (deg)
    PARAMETER el, wh.
    IF wh = "APO" { RETURN 180. }
    IF wh = "PERI" { RETURN 0. }
    IF wh = "AN" { RETURN MOD(360 - el["argp"], 360). }
    IF wh = "DN" { RETURN MOD(540 - el["argp"], 360). }
    RETURN 0.
}

// ---- the shuttle's LVLH: +Z down (to the body's centre), +Y against the orbit's angular momentum (right of the
// motion), +X = Y x Z (forward, horizontal). LIST(X, Y, Z), unit.
FUNCTION o2Lvlh {
    PARAMETER rv, vv.
    LOCAL zz IS -rv:NORMALIZED.
    LOCAL hf IS VCRS(rv, vv):NORMALIZED.     // KSP: right of the motion; a right-handed frame: left of it
    LOCAL yy IS CHOOSE hf IF O2_LH ELSE -hf.
    LOCAL xx IS o2Unit(vv - rv:NORMALIZED * VDOT(vv, rv:NORMALIZED)).
    RETURN LIST(xx, yy, zz).
}
FUNCTION o2ToLvlh { PARAMETER dv, fr. RETURN LIST(VDOT(dv, fr[0]), VDOT(dv, fr[1]), VDOT(dv, fr[2])). }
FUNCTION o2FromLvlh { PARAMETER dx, dy, dz, fr. RETURN fr[0] * dx + fr[1] * dy + fr[2] * dz. }

FUNCTION o2East {                            // the local east (unit) at rv
    PARAMETER rv, npole.
    LOCAL uu IS rv:NORMALIZED.
    RETURN o2Unit(CHOOSE VCRS(uu, npole) IF O2_LH ELSE VCRS(npole, uu)).
}

// ---- the BRN PLN burns at the state (rv, vv): each returns the dv vector (inertial, m/s)
FUNCTION o2Circ {                            // CIRC: the circle at r, the motion's own direction, horizontal
    PARAMETER rv, vv, mu.
    LOCAL fr IS o2Lvlh(rv, vv).
    RETURN fr[0] * SQRT(mu / rv:MAG) - vv.
}

FUNCTION o2Apsis {                           // HA / HP: a burn along the velocity to put the other apsis at rt (m)
    PARAMETER rv, vv, mu, npole, which, rt.  // which "HA" = the apoapsis, "HP" = the periapsis
    LOCAL u IS vv:NORMALIZED.
    LOCAL lo IS -vv:MAG * 0.5.
    LOCAL hi IS vv:MAG * 0.4.
    // the apsis grows with the prograde dv (both apses do): bisect for rt
    IF o2ApsisAt(rv, vv, u, lo, mu, npole, which) > rt OR o2ApsisAt(rv, vv, u, hi, mu, npole, which) < rt {
        RETURN LIST(FALSE, V(0, 0, 0)).
    }
    FROM { LOCAL i IS 0. } UNTIL i >= 60 STEP { SET i TO i + 1. } DO {
        LOCAL md IS (lo + hi) / 2.
        IF o2ApsisAt(rv, vv, u, md, mu, npole, which) < rt { SET lo TO md. } ELSE { SET hi TO md. }
        IF hi - lo < 1E-4 { BREAK. }
    }
    RETURN LIST(TRUE, u * ((lo + hi) / 2)).
}

FUNCTION o2ApsisAt {                         // o2Apsis's: the apsis after k m/s along u (1E30: not bound)
    PARAMETER rv, vv, u, k, mu, npole, which.
    LOCAL el IS o2Els(rv, vv + u * k, mu, npole).
    IF el["e"] >= 1 OR el["a"] <= 0 { RETURN 1E30. }
    RETURN CHOOSE el["ra"] IF which = "HA" ELSE el["rp"].
}

FUNCTION o2Plane {                           // PLANE: the inclination to it (deg) at a node; the speed kept
    PARAMETER rv, vv, npole, it.
    LOCAL uu IS rv:NORMALIZED.
    LOCAL vr IS VDOT(vv, uu).
    LOCAL vh IS vv - uu * vr.
    LOCAL nth IS o2Unit(npole - uu * VDOT(npole, uu)).
    LOCAL est IS o2East(rv, npole).
    LOCAL sg IS CHOOSE 1 IF VDOT(vh, nth) >= 0 ELSE -1.   // north (AN) or south (DN) bound
    LOCAL vn IS (est * COS(it) + nth * (sg * SIN(it))) * vh:MAG + uu * vr.
    RETURN vn - vv.
}

// ---- the orbit view (ORBIT / PTG, BRN PLN): seen from h, so the motion is always counterclockwise; the ascending
// node on the right; altitudes x O2_VIEW_ALT_X. A point's page offset from the Earth's centre
// in px (x right, y DOWN), at scale sc px per m of drawn radius.
FUNCTION o2ViewR { PARAMETER rm, rb. RETURN rb + O2_VIEW_ALT_X * (rm - rb). }
FUNCTION o2ViewXY {
    PARAMETER el, rvec, rb, sc.
    LOCAL rd IS o2ViewR(rvec:MAG, rb) * sc / rvec:MAG.
    RETURN LIST(VDOT(rvec, el["e1"]) * rd, -VDOT(rvec, el["e2"]) * rd).
}
FUNCTION o2ViewTA { PARAMETER el, nu, rb, sc. RETURN o2ViewXY(el, o2AtTA(el, nu)[0], rb, sc). }
FUNCTION o2ViewScale {                       // px per m so the largest drawn apoapsis of els fits rpx
    PARAMETER els, rb, rpx.
    LOCAL big IS rb.
    FOR el IN els { SET big TO MAX(big, o2ViewR(MIN(el["ra"], rb * 3), rb)). }
    RETURN rpx / big.
}
// the apsides caption ("NOW A .. P .. km" and, with a plan, "PLAN A .. P .. km") sits UNDER everything the view draws. The lowest
// pixel row any of the view's sprites reaches: the orbit's path is inside the radius r around the centre (x, cy); the lowest text is the TIG label
// at 1.18 r (the A / P labels sit at 1.13 r), drawn centred in an 18 px high box (9 px below its centre). The caption's lines are 16 px apart,
// the first (NOW) 15 px under that reach (a 6 px clear strip: the line's box starts 9 px above its centre). KalsCoproc's Od.cs CapY is this same arithmetic.
FUNCTION o2ViewReachY { PARAMETER cy, rad. RETURN cy + rad * 1.18 + 9. }
FUNCTION o2ViewCapY { PARAMETER cy, rad, row IS 0. RETURN FLOOR(o2ViewReachY(cy, rad)) + 15 + 16 * row. }
FUNCTION o2ViewPath {                        // the conic's drawn points above the surface: LIST(LIST(x, y)), n steps
    PARAMETER el, rb, sc, n, el0 IS LEXICON().   // el0: a conic whose view frame to use (the current orbit's); none = el's
    LOCAL fr IS CHOOSE el IF el0:LENGTH = 0 ELSE el0.
    LOCAL out IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
        LOCAL nu IS 360 * i / n.
        LOCAL rr IS o2AtTA(el, nu)[0].
        IF rr:MAG > rb AND el["p"] / (1 + el["e"] * COS(nu)) > 0 { out:ADD(o2ViewXY(fr, rr, rb, sc)). }
    }
    RETURN out.
}
