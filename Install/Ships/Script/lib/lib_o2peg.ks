// lib_o2peg.ks -- ops2q's BURN GUIDANCE, PEG 7 and PEG 4 (pure: vectors in, numbers out; no vessel, so the kOS VM runs it:
// tests/o2peg_selftest.ks flies it closed loop on a point mass with two OMS engines). Needs lib_o2orb.ks (o2Lvlh,
// o2FromLvlh, o2Unit) loaded first.
// PEG 7 (the real orbiter's external dV guidance): the burn's dV is given in LVLH (DVX forward, DVY right of the
// motion, DVZ down) and turned ONCE into an inertial vector, VGO, the velocity still to be gained. Through the burn VGO
// is decremented by the SENSED dV, the engines' thrust over the mass integrated each physics tick (gravity is not
// sensed, as the orbiter's IMU's accelerometers do not sense it), and the thrust is steered along VGO. Cutoff when
// what is left along the steering direction falls under O2P_CUT; the rest of VGO is the RCS trim residual.
// The LVLH frame is the one at the burn's CENTRE (TIG + TGO / 2): the plan files' dV are impulses there (lib_plan's
// burn_ut, BRN PLN's solve), and a finite burn held on that inertial direction, centred on it, delivers the impulse to
// second order. The real orbiter's frame was the one at TIG, for targets computed for TIG.
// The thrust line: the engines' summed thrust direction (each one's thrust along its own axis; the OMS toe in) need not
// be the control point's fore axis (one engine out: 11.8 deg off it). The steering rotates the control point so that the
// THRUST lies along VGO (o2pAim), the rule for the 2-to-1 downmode.
// The throttle tapers on what is left (shuttle_exec's law, O2P_TAPER_S), so the cut lands within O2P_CUT; below
// O2P_HOLD_DV (or O2P_HOLD_TGO s to go) the steering holds its last direction (VGO's own direction is noise by then).

GLOBAL O2P_CUT IS 0.01.                      // m/s left along the steering direction: the cut (shuttle_exec EXEC_PLAN_CUT)
GLOBAL O2P_TAPER_S IS 0.25.                  // s: the throttle = what is left over (the full acceleration x this)
GLOBAL O2P_TAPER_DT_K IS 12.                 // The taper is at least this x the physics tick (the peak of the last ~1 s, o2pSense's pg["dtm"]): the
                                             // engines answer a throttle ~3 TICKS late (a frame lag, not seconds), so at 0.08 s ticks the 0.25 s taper cut
                                             // 0.065 m/s of along too late (4x warp legs); 12 ticks keep the loop gain under 1
                                             // (0.25 s from a tick of 0.0208 s or less: the 50 Hz flights are unchanged)
GLOBAL O2P_DTM_DECAY IS 0.97.                // The held peak tick falls by this per tick
GLOBAL O2P_HOLD_DV IS 1.                     // m/s: with this little VGO left, the steering holds its direction
GLOBAL O2P_HOLD_TGO IS 1.5.                  // s: ... or this little time to go at the full acceleration (a VGO under ~5 m/s
                                             // turns fast under any thrust off it, a steering that chases it diverges)
GLOBAL O2P_GUARD_K IS 1.5.                   // the time guard: the burn ends at this x its expected length + O2P_GUARD_S
GLOBAL O2P_GUARD_S IS 5.
GLOBAL O2P_TTG_TAIL IS 0.755.                // the taper's tail in the TGO (shuttle_exec EXEC_TTG_TAIL)
GLOBAL O2P_AXIS_MIN IS 0.9.                  // one second in: the engines' axes must give this much of their thrust

// rotate x by the rotation that takes the direction a onto the direction b (Rodrigues; a and b need not be unit).
// The component cross product makes it hold in either handedness: the result for x = a is b's direction.
FUNCTION o2pRot {
    PARAMETER x, a, b.
    LOCAL au IS o2Unit(a). LOCAL bu IS o2Unit(b).
    LOCAL k IS VCRS(au, bu).
    LOCAL s IS k:MAG.
    LOCAL c IS VDOT(au, bu).
    IF s < 1E-9 { RETURN x. }                // parallel (antiparallel never comes: the steering errs by degrees)
    SET k TO k / s.
    RETURN x * c + VCRS(k, x) * s + k * (VDOT(k, x) * (1 - c)).
}

// a new burn: the LVLH dv LIST(x, y, z) m/s in the frame fr (o2Lvlh at the burn's centre)
FUNCTION o2pNew {
    PARAMETER dv, fr.
    LOCAL g IS o2FromLvlh(dv[0], dv[1], dv[2], fr).
    RETURN LEXICON("vgo", g, "vgo0", g, "dv", dv:COPY, "tot", g:MAG, "sens", V(0, 0, 0),
        "tprev", -1, "dtm", 0, "hold", FALSE, "hdir", V(0, 0, 0), "t0", -1, "end", "").
}
// before ignition: the same dv in a fresher frame (the live state's conic); nothing sensed yet
FUNCTION o2pRefresh {
    PARAMETER pg, fr.
    LOCAL dv IS pg["dv"].
    LOCAL g IS o2FromLvlh(dv[0], dv[1], dv[2], fr).
    SET pg["vgo"] TO g. SET pg["vgo0"] TO g. SET pg["tot"] TO g:MAG.
}
// one sensed sample: the engines' acceleration a (vector, m/s2, inertial) read at the time t (s). An engine's THRUST
// is what it gave over the last physics tick, so the sample holds back to the one before (a rectangle; shuttle_exec's
// trapezoid lags by half a tick at every throttle change). The first sample starts the count (and the clock t0).
FUNCTION o2pSense {
    PARAMETER pg, a, t.
    IF pg["tprev"] >= 0 {
        LOCAL d IS a * (t - pg["tprev"]).
        IF pg:HASKEY("dtm") { SET pg["dtm"] TO MAX(t - pg["tprev"], pg["dtm"] * O2P_DTM_DECAY). }   // The peak physics tick, held
        SET pg["vgo"] TO pg["vgo"] - d.
        SET pg["sens"] TO pg["sens"] + d.
    } ELSE { SET pg["t0"] TO t. }
    SET pg["tprev"] TO t.
}
// the steering direction (unit): along VGO, held once VGO is under O2P_HOLD_DV or O2P_HOLD_TGO s at the full acceleration
// (pg["aav"], set by o2pEnd from the first sample on)
FUNCTION o2pDir {
    PARAMETER pg.
    IF pg["hold"] { RETURN pg["hdir"]. }
    LOCAL g IS pg["vgo"].
    LOCAL lim IS O2P_HOLD_DV.
    IF pg:HASKEY("aav") { SET lim TO MAX(lim, O2P_HOLD_TGO * pg["aav"]). }
    IF g:MAG <= lim AND pg["tprev"] >= 0 {
        SET pg["hold"] TO TRUE.
        SET pg["hdir"] TO o2Unit(g).
        RETURN pg["hdir"].
    }
    RETURN o2Unit(g).
}
FUNCTION o2pAlong { PARAMETER pg. RETURN VDOT(pg["vgo"], o2pDir(pg)). }   // m/s left along the steering direction
// the taper (s) for this burn: O2P_TAPER_S, or O2P_TAPER_DT_K x the peak physics tick when that is longer
FUNCTION o2pTaper {
    PARAMETER pg.
    IF NOT pg:HASKEY("dtm") { RETURN O2P_TAPER_S. }
    RETURN MAX(O2P_TAPER_S, O2P_TAPER_DT_K * pg["dtm"]).
}
// the throttle for what is left along (m/s) at the full acceleration aMax (m/s2): 1, tapering (over tap s), 0 at the cut
FUNCTION o2pThr {
    PARAMETER along, aMax.
    PARAMETER tap IS O2P_TAPER_S.
    IF along < O2P_CUT { RETURN 0. }
    RETURN MIN(1, along / MAX(aMax * tap, 0.001)).
}
// the control point's fore axis to steer to so that the thrust line thr (vector) lies along the direction u, the
// control point's fore axis being fore now (o2pRot(fore) of the turn thr -> u)
FUNCTION o2pAim {
    PARAMETER u, thr, fore.
    RETURN o2Unit(o2pRot(fore, thr, u)).
}
// the burn's end, or "": the cut (CUT), no thrust 2 s in (THRUST), the time guard (GUARD). tb = the expected burn s at
// ignition; the guard is set at the first sample to O2P_GUARD_K x tb + O2P_GUARD_S, and set again from what is left
// when the available acceleration aAvail (m/s2) drops under 0.9 of the last (an engine out: a longer burn, no guard).
FUNCTION o2pEnd {
    PARAMETER pg, t, aAvail, tb.
    IF pg["t0"] < 0 { RETURN "". }
    LOCAL al IS o2pAlong(pg).
    IF al < O2P_CUT { RETURN "CUT". }
    IF t - pg["t0"] > 2 AND aAvail < 0.001 { RETURN "THRUST". }
    IF NOT pg:HASKEY("tguard") {
        SET pg["tguard"] TO pg["t0"] + O2P_GUARD_K * tb + O2P_GUARD_S.
        SET pg["aav"] TO aAvail.
    } ELSE IF aAvail > 0.001 AND aAvail < 0.9 * pg["aav"] {
        SET pg["tguard"] TO MAX(pg["tguard"], t + O2P_GUARD_K * al / aAvail + O2P_GUARD_S).
        SET pg["aav"] TO aAvail.
    }
    IF t > pg["tguard"] { RETURN "GUARD". }
    RETURN "".
}
// the time to go (s) for vgo m/s left at the full acceleration aFull (m/s2) and the exhaust speed vex (m/s): the
// rocket equation down to the taper's start, then the taper's tail (shuttle_exec exTTG); -1 with no thrust
FUNCTION o2pTgo {
    PARAMETER vgo, aFull, vex.
    IF aFull <= 0.0001 OR vex <= 1 { RETURN -1. }
    LOCAL dvTap IS MAX(aFull * O2P_TAPER_S, O2P_CUT).
    LOCAL tTail IS O2P_TAPER_S * O2P_TTG_TAIL * LN(MAX(MIN(vgo, dvTap), O2P_CUT) / O2P_CUT).
    IF vgo <= dvTap { RETURN tTail. }
    RETURN vex / aFull * (1 - CONSTANT:E ^ ((dvTap - vgo) / vex)) + tTail.
}
// a vector in the orbiter's body axes: LIST(X forward (the nose), Y right, Z down) from the body's fore / star / top
FUNCTION o2pBody {
    PARAMETER x, fore, star, top.
    RETURN LIST(VDOT(x, fore), VDOT(x, star), -VDOT(x, top)).
}

// ---- the OMS RM: the real orbiter's OMS redundancy management, one out flag per engine
// whatever the cause ("L(R) OMS Pc FAIL (Pc < 80%)", "Loss of acceleration", "L(R) OMS ENG - OFF": SCOM App. C), then
// guidance downmodes 2 OMS to 1 with the target unchanged (FSSR STS 83-0002-34 p. 119). The owner's calls 11-03 09:51:
// 80 % (C1 a), both out = the burn ends with the dV left (C2 a), never relit (C4 a).
GLOBAL O2P_PC_FAIL IS 0.8.                   // Pc FAIL: the thrust under this x the commanded (throttle x available) ...
GLOBAL O2P_PC_T IS 0.48.                     // ... for this long (s; the ascent's SSME persistence)
GLOBAL O2P_PC_THR IS 0.1.                    // the Pc test runs only at a throttle of at least this (the taper's tail is noise)
GLOBAL O2P_LIVE_T IS 0.5.                    // s after ignition: the burning tests start (the start-up transient)

// one engine's test: on = it is meant to be lit (seen lit, not shut down by ops2q), live = it is meant to be burning
// (lit, O2P_LIVE_T s past ignition, before the cut), ign / flame = its IGNITION / FLAMEOUT, thr = the throttle commanded
// for the tick its THRUST thrust (kN) was given over, avail = its AVAILABLETHRUST (kN: the thrust limiter in, so a
// limited engine flies on), tlow = the Pc test's time under so far, dt = s since the last test. Returns LIST(why, tlow):
// why "" (good), "SHUTDOWN" (not lit while meant lit), "FLAMEOUT" (while burning), "PC LOW" (O2P_PC_T s under 80 %).
FUNCTION o2pEoWhy {
    PARAMETER on, live, ign, flame, thr, avail, thrust, tlow, dt.
    IF on AND NOT ign { RETURN LIST("SHUTDOWN", 0). }
    IF NOT live { RETURN LIST("", 0). }
    IF flame { RETURN LIST("FLAMEOUT", 0). }
    IF thr < O2P_PC_THR OR avail <= 0 { RETURN LIST("", 0). }
    IF thrust >= O2P_PC_FAIL * thr * avail { RETURN LIST("", 0). }
    LOCAL tl IS tlow + dt.
    IF tl >= O2P_PC_T - 1E-6 { RETURN LIST("PC LOW", tl). }
    RETURN LIST("", tl).
}
// an engine out before ignition: the burn re-planned on what is left, centred where it was (the plan's impulse point;
// "the TIG is selected to protect for one OMS engine failure", SCOM 7.3): the new TIG for the burn length tb1 (s) in
// place of tb0 at the TIG ig, never before tmin (UT: now and a moment)
FUNCTION o2pReTig {
    PARAMETER ig, tb0, tb1, tmin.
    RETURN MAX(tmin, ig + tb0 / 2 - tb1 / 2).
}

// ---- PEG 4: the real orbiter's guidance for the OMS-1, OMS-2 and deorbit burns (FSSR STS 83-0002-34
// 4.8.1 desired velocity subtask 16 + 4.8.4 LTVCON TSK). The targets: a point HT above the surface, THETA T ahead of
// the orbiter's position at TIG in the orbit plane ("the THETA target must be adjusted if TIG is changed (in OPS 3)
// or an REI miss will result", the DPS dictionary), and a line the velocity there must lie on: VRADIAL = C1 + C2
// VHORIZONTAL (C1 m/s, C2 none). Each cycle the conic velocity v' from the orbiter's position to the target point
// that meets the line is solved in closed form (LTVCON's quadratic), the target point projected onto the orbit plane
// now (PEG 4 flies in the plane), and VGO = v' - v; the thrust is steered along it as PEG 7's. Under O2P_HOLD_DV left
// the steering holds (o2pDir) and VGO stops being re-solved: the sensed count flies the rest to the cut. A late
// ignition, a weak engine or one out are flown out.
// THE J2 AIM (ours): Principia flies the real Earth's J2 on Sol's quarter Earth, and the coast from a conic-targeted
// cut misses the J2 interface by 3.5-9 km (lead/t492/d1/j2fly.py). So the targets are the J2 coast's (o2p4FromImp:
// the plan impulse's interface under J2, as deorbit_plan plans it) and the conic aims at a point and a line turned by
// offsets (aoff deg along the plane, goff deg of flight path angle) that a J2 coast of v' corrects, one fixed-point
// step every O2P4_AIM_DT s (o2p4AimStep: the coast of v' to the target's radius, the offsets less its misses). With no
// J2 (stock gravity) the offsets stay 0: the conic PEG 4. Our deorbit's targets: deorbit_plan's impulse's interface at
// O2P4_EI_ALT going down, C1 0 and C2 the tangent of the flight path angle there (deorbit_plan targets one angle, not
// the orbiter's angle-velocity line). The cut's 0.01 m/s left (O2P_CUT) is ~0.5 km of interface range here.
GLOBAL O2P4_EPS IS 1E-6.                     // LTVCON's EP_TRANSFER: a transfer angle near zero has no solution
GLOBAL O2P4_EI_ALT IS 80000.                 // m: the deorbit's target altitude (deorbit_plan DP_GEO_EI_ALT, deorbit_sim ATM)
GLOBAL O2P4_J2 IS 0.0010826358191967033.     // Principia's Earth J2 and its reference radius (entry_predict EPR_J2 / EPR_R_J2)
GLOBAL O2P4_RJ2 IS 1594534.075.
GLOBAL O2P4_J2_H IS 30.                      // s: the J2 coast's RK4 step (entry_predict eprJ2ToEI's)
GLOBAL O2P4_AIM_DT IS 1.                     // s between the J2 aim's steps
GLOBAL O2P4_AIM_N IS 3.                      // the aim's steps at a new burn

// deg from a to b about the unit normal nh (0 .. 360), a projected onto the plane
FUNCTION o2p4Ang {
    PARAMETER a, b, nh.
    LOCAL u IS o2Unit(a - nh * VDOT(a, nh)).
    RETURN MOD(ARCTAN2(VDOT(b, VCRS(nh, u)), VDOT(b, u)) + 360, 360).
}
FUNCTION o2p4Sgn { PARAMETER a. IF a > 180 { RETURN a - 360. } RETURN a. }   // 0 .. 360 -> -180 .. 180
// LTVCON: the conic velocity at rc to reach rt with VRADIAL = c1 + c2 VHORIZONTAL there, the transfer in the plane of
// the unit normal nh (VCRS(r, v)'s; the FSSR's I< is its negative). V(0, 0, 0): no solution (the angle near zero, or
// the quadratic's discriminant below zero). The component algebra holds in either handedness.
FUNCTION o2p4Ltv {
    PARAMETER rc, rt, nh, c1, c2, mu.
    LOCAL rm IS rc:MAG.
    LOCAL r1 IS rt:MAG.
    LOCAL kk IS (r1 - rm) / rm.
    LOCAL lz IS rm * r1 - VDOT(rc, rt).
    IF lz <= rm * r1 * O2P4_EPS { RETURN V(0, 0, 0). }
    LOCAL w IS VDOT(VCRS(rc, rt), nh) / lz.  // the cotangent of half the transfer angle
    LOCAL la IS kk * (1 + w ^ 2) + 2 * (1 - c2 * w).
    LOCAL lb IS c1 * w.
    LOCAL lc IS 2 * mu / r1.
    LOCAL ld IS lb ^ 2 + la * lc.
    IF ld < 0 { RETURN V(0, 0, 0). }
    LOCAL dn IS SQRT(ld) - lb.
    IF dn <= 0 { RETURN V(0, 0, 0). }
    LOCAL vh1 IS lc / dn.                    // the horizontal speed at the target
    LOCAL vr1 IS c1 + c2 * vh1.
    RETURN (rc * (kk * w * vh1 - vr1) + VCRS(nh, rc) * ((1 + kk) * vh1)) / rm.
}
// the required velocity at (rq, vq): LTVCON to the target rt projected onto the plane of the motion; V(0, 0, 0) none
FUNCTION o2p4Req {
    PARAMETER rq, vq, rt, c1, c2, mu.
    LOCAL nh IS o2Unit(VCRS(rq, vq)).
    RETURN o2p4Ltv(rq, rt - nh * VDOT(rt, nh), nh, c1, c2, mu).
}
// the target point (inertial) from HT (m) and THETA T (deg) ahead of the TIG position rig in the plane of nh
FUNCTION o2p4Tgt {
    PARAMETER rig, nh, ht, th, rb.
    LOCAL u IS o2Unit(rig - nh * VDOT(rig, nh)).
    RETURN (u * COS(th) + VCRS(nh, u) * SIN(th)) * (rb + ht).
}

// the gravity: LEXICON(mu, j2 (0: a point mass), rj2, ax (the body's axis, either sign: z enters squared and as ax z))
FUNCTION o2p4Grav { PARAMETER mu, j2, ax. RETURN LEXICON("mu", mu, "j2", j2, "rj2", O2P4_RJ2, "ax", o2Unit(ax)). }
FUNCTION o2p4G {                             // the acceleration at rq (entry_predict eprJ2Grav's)
    PARAMETER rq, gv.
    LOCAL rm IS rq:MAG.
    LOCAL a IS rq * (-gv["mu"] / rm ^ 3).
    IF gv["j2"] = 0 { RETURN a. }
    LOCAL z IS VDOT(rq, gv["ax"]).
    LOCAL k IS -1.5 * gv["j2"] * gv["mu"] * gv["rj2"] ^ 2 / rm ^ 5.
    RETURN a + (rq * (1 - 5 * z * z / (rm * rm)) + gv["ax"] * (2 * z)) * k.
}
FUNCTION o2p4Step {                          // one RK4 step of the coast: LIST(r, v)
    PARAMETER rq, vq, h, gv.
    LOCAL a1 IS o2p4G(rq, gv).
    LOCAL r2 IS rq + vq * (h / 2). LOCAL v2 IS vq + a1 * (h / 2).
    LOCAL a2 IS o2p4G(r2, gv).
    LOCAL r3 IS rq + v2 * (h / 2). LOCAL v3 IS vq + a2 * (h / 2).
    LOCAL a3 IS o2p4G(r3, gv).
    LOCAL r4 IS rq + v3 * h. LOCAL v4 IS vq + a3 * h.
    LOCAL a4 IS o2p4G(r4, gv).
    RETURN LIST(rq + (vq + v2 * 2 + v3 * 2 + v4) * (h / 6), vq + (a1 + a2 * 2 + a3 * 2 + a4) * (h / 6)).
}
// the coast to the radius rr going down (RK4 at O2P4_J2_H s, the crossing by bisection: entry_predict eprJ2ToEI's):
// LIST(r, v, ok)
FUNCTION o2p4To {
    PARAMETER rq, vq, rr, gv.
    LOCAL t IS 0.
    LOCAL h IS O2P4_J2_H.
    UNTIL t > 20000 {
        LOCAL st IS o2p4Step(rq, vq, h, gv).
        IF st[0]:MAG <= rr {
            LOCAL lo IS 0. LOCAL hi IS h.
            FROM { LOCAL k IS 0. } UNTIL k >= 20 STEP { SET k TO k + 1. } DO {
                LOCAL mid IS 0.5 * (lo + hi).
                IF o2p4Step(rq, vq, mid, gv)[0]:MAG > rr { SET lo TO mid. } ELSE { SET hi TO mid. }
            }
            LOCAL fin IS o2p4Step(rq, vq, hi, gv).
            RETURN LIST(fin[0], fin[1], TRUE).
        }
        SET rq TO st[0]. SET vq TO st[1]. SET t TO t + h.
    }
    RETURN LIST(rq, vq, FALSE).
}
// the coast's crossing of the radius rr going down: under J2 o2p4To, else the conic's (closed form): LIST(r, v, ok)
FUNCTION o2p4Cross {
    PARAMETER rq, vq, rr, gv.
    LOCAL el IS o2Els(rq, vq, gv["mu"], V(0, 0, 1)).
    IF el["e"] < 1E-9 OR el["rp"] >= rr OR el["ra"] <= rr { RETURN LIST(rq, vq, FALSE). }
    IF gv["j2"] <> 0 { RETURN o2p4To(rq, vq, rr, gv). }
    LOCAL st IS o2AtTA(el, 360 - ARCCOS((el["p"] / rr - 1) / el["e"])).
    RETURN LIST(st[0], st[1], TRUE).
}
FUNCTION o2p4Vh {                            // LIST(the radial, the horizontal speed) of vq at rq
    PARAMETER rq, vq.
    LOCAL vr IS VDOT(vq, o2Unit(rq)).
    RETURN LIST(vr, SQRT(MAX(1E-9, vq:SQRMAGNITUDE - vr ^ 2))).
}
// the targets of an impulse: at rb the velocity after it va, the TIG position rig: LIST(HT m, THETA T deg, C1, C2) at
// the coast's crossing of O2P4_EI_ALT going down (a deorbit; under gv's J2 the J2 coast's), else at the conic's point
// half an orbit on (C1 0, C2 the tangent of the flight path angle there)
FUNCTION o2p4FromImp {
    PARAMETER rb, va, rig, gv, rbody.
    LOCAL cr IS o2p4Cross(rb, va, rbody + O2P4_EI_ALT, gv).
    LOCAL st IS LIST(cr[0], cr[1]).
    IF NOT cr[2] {
        LOCAL el IS o2Els(rb, va, gv["mu"], V(0, 0, 1)).
        SET st TO o2AtTA(el, MOD(el["ta"] + 180, 360)).
    }
    LOCAL rh IS o2p4Vh(st[0], st[1]).
    RETURN LIST(st[0]:MAG - rbody, o2p4Ang(rig, st[0], o2Unit(VCRS(rb, va))), 0, rh[0] / rh[1]).
}
// PEG 4 is the deorbit's guidance: a burn is PEG 4's only when its coast from (rb, va) (the impulse's state after
// it; for a PEG 4 burn, v' at the centre) comes down through O2P4_EI_ALT (under gv's J2 the J2 coast's): TRUE. A raise,
// or a lowering that keeps the perigee above it, never reaches the interface: o2p4FromImp would aim it at a point half
// an orbit on, and a J2 burn's aim coasts to a radius the burn point is already under.
FUNCTION o2p4Reach {
    PARAMETER rb, va, gv, rbody.
    RETURN o2p4Cross(rb, va, rbody + O2P4_EI_ALT, gv)[2].
}

// a PEG 4 burn: the target point rt, the line c1 / c2, the gravity gv; the aim (O2P4_AIM_N steps) and VGO at (rq, vq)
// (the burn's centre on the conic before it). pg["nosol"]: no solution there
FUNCTION o2p4New {
    PARAMETER rt, c1, c2, gv, rq, vq.
    LOCAL pg IS o2pNew(LIST(0, 0, 0), LIST(V(1, 0, 0), V(0, 1, 0), V(0, 0, 1))).
    SET pg["rt"] TO rt. SET pg["c1"] TO c1. SET pg["c2"] TO c2. SET pg["gv"] TO gv.
    SET pg["aoff"] TO 0. SET pg["goff"] TO 0. SET pg["taim"] TO -1E9.
    SET pg["nosol"] TO FALSE. SET pg["nres"] TO 0. SET pg["naim"] TO 0. SET pg["amiss"] TO LIST(0, 0).
    FROM { LOCAL i IS 0. } UNTIL i >= O2P4_AIM_N STEP { SET i TO i + 1. } DO { o2p4AimStep(pg, rq, vq). }
    o2p4Solve(pg, rq, vq).
    RETURN pg.
}
FUNCTION o2p4Vreq {                          // v' at (rq, vq) for the aim: the target turned by aoff, the line by goff
    PARAMETER pg, rq, vq.
    LOCAL nh IS o2Unit(VCRS(rq, vq)).
    LOCAL rt IS pg["rt"].
    RETURN o2p4Ltv(rq, o2p4Tgt(rt, nh, 0, pg["aoff"], rt:MAG), nh, pg["c1"], TAN(ARCTAN(pg["c2"]) + pg["goff"]), pg["gv"]["mu"]).
}
// one step of the J2 aim at (rq, vq): v''s J2 coast to the target's radius, the offsets less its misses (the angle past
// the target, the flight path angle over the line's). pg["amiss"]: LIST(those misses, deg) before the step
FUNCTION o2p4AimStep {
    PARAMETER pg, rq, vq.
    IF pg["gv"]["j2"] = 0 { RETURN. }
    LOCAL vw IS o2p4Vreq(pg, rq, vq).
    IF vw:MAG = 0 { RETURN. }
    LOCAL got IS o2p4To(rq, vw, pg["rt"]:MAG, pg["gv"]).
    IF NOT got[2] { RETURN. }
    LOCAL da IS o2p4Sgn(o2p4Ang(pg["rt"], got[0], o2Unit(VCRS(rq, vq)))).
    LOCAL rh IS o2p4Vh(got[0], got[1]).
    LOCAL dg IS ARCTAN2(rh[0], rh[1]) - ARCTAN2(pg["c1"] + pg["c2"] * rh[1], rh[1]).
    SET pg["aoff"] TO pg["aoff"] - da.
    SET pg["goff"] TO pg["goff"] - dg.
    SET pg["amiss"] TO LIST(da, dg).
    SET pg["naim"] TO pg["naim"] + 1.
}
FUNCTION o2p4Solve {                         // VGO at (rq, vq) afresh (before ignition)
    PARAMETER pg, rq, vq.
    LOCAL vw IS o2p4Vreq(pg, rq, vq).
    SET pg["nosol"] TO vw:MAG = 0.
    IF pg["nosol"] { RETURN. }
    SET pg["vgo"] TO vw - vq. SET pg["vgo0"] TO pg["vgo"]. SET pg["tot"] TO pg["vgo"]:MAG.
}
// before ignition, each cycle: the target point rt afresh (from the TIG point's latest prediction; V(0, 0, 0) keeps
// it), an aim step each O2P4_AIM_DT s (now, s), VGO at (rq, vq) (the burn's centre)
FUNCTION o2p4Pre {
    PARAMETER pg, rt, rq, vq, now.
    IF rt:MAG > 0 { SET pg["rt"] TO rt. }
    IF now >= pg["taim"] { o2p4AimStep(pg, rq, vq). SET pg["taim"] TO now + O2P4_AIM_DT. }
    o2p4Solve(pg, rq, vq).
}
// in the burn, the main loop: an aim step each O2P4_AIM_DT s at the state (rq, vq) until the steering holds
FUNCTION o2p4Aim {
    PARAMETER pg, rq, vq, now.
    IF pg["hold"] OR now < pg["taim"] { RETURN. }
    o2p4AimStep(pg, rq, vq).
    SET pg["taim"] TO now + O2P4_AIM_DT.
}
// in the burn, each tick after o2pSense: VGO re-solved from the state (rq, vq) until the steering holds; no solution:
// the sensed count flies on
FUNCTION o2p4Cycle {
    PARAMETER pg, rq, vq.
    IF pg["hold"] { RETURN. }
    LOCAL vw IS o2p4Vreq(pg, rq, vq).
    IF vw:MAG = 0 { RETURN. }
    SET pg["vgo"] TO vw - vq.
    SET pg["nres"] TO pg["nres"] + 1.
}
// how the coast from (rq, vq) (gv's gravity) meets the target rt and its line: LIST(the range miss m (along the
// target's radius, + = past it), the flight path angle there less the line's (deg), TRUE when it comes down through
// the target's radius (else the first two are 0))
FUNCTION o2p4Miss {
    PARAMETER rq, vq, rt, c1, c2, gv.
    LOCAL cr IS o2p4Cross(rq, vq, rt:MAG, gv).
    IF NOT cr[2] { RETURN LIST(0, 0, FALSE). }
    LOCAL agl IS o2p4Sgn(o2p4Ang(rt, cr[0], o2Unit(VCRS(rq, vq)))).
    LOCAL rh IS o2p4Vh(cr[0], cr[1]).
    RETURN LIST(agl * CONSTANT:DEGTORAD * rt:MAG, ARCTAN2(rh[0], rh[1]) - ARCTAN2(c1 + c2 * rh[1], rh[1]), TRUE).
}
// the conic from (rq, vq) at the target's angle: its radius less the target's (m)
FUNCTION o2p4Dr {
    PARAMETER rq, vq, rt, mu.
    LOCAL el IS o2Els(rq, vq, mu, V(0, 0, 1)).
    RETURN o2AtTA(el, el["ta"] + o2p4Ang(rq, rt, o2Unit(VCRS(rq, vq))))[0]:MAG - rt:MAG.
}
