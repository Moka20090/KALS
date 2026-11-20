// the rate an on-rails warp should start with (pure math + the arm's state; no KSP types, so the offline test
// compiles it as it is).
// WHY: Principia carries a vessel's rotation through a rails warp (it comes with its own persistent
// rotation), so whatever angular rate the vessel has the moment it packs is what it turns
// at for the whole warp: flight 4's rate null left 0.10 deg/s and the burn attitude was 25.9 deg off after the final warp.
// KalsAddon.Rails.cs sets the rate EXACTLY in the last physics frame before the vessel packs; this file says which rate.
//   mode ZERO  the rate 0 in the world (non-rotating) frame: the attitude stays inertially fixed (a burn's aim, INRTL).
//   mode VEC   kOS gives the world rate (rad/s, a kOS vector = the world axes, as O2DAPSET's vectors).
//   mode HOLD  derived from ops2q's DAP hold: INRTL 0, LVLH the orbit rate (r x v) / |r|^2, TRACK the Earth the same (the
//              line of sight to the body's centre turns at the orbit rate), TRACK the Sun 0 (the Earth's own rate round
//              the Sun, 2e-7 rad/s, is ignored), FREE none (the pilot's: nothing is set).
//   In a left-handed frame (Unity's) the formula dr/dt = w x r keeps its component form, so w = r x v / |r|^2 is the
//   rate at which the radius vector turns whichever handedness the axes have.
using System;

namespace KalsCoproc
{
    public static class RailsCore
    {
        public const double TTL = 120;           // real s: an arm lapses (kOS died / ops2q ended) so a stale arm never sets a later warp

        // the hold's world rate (rad/s) from the state (r = position from the body's centre, v = orbital velocity, world
        // axes), null = set nothing (FREE or an unknown hold). los: 0 the Earth (the body), 1 the Sun.
        public static double[] HoldRate(string hold, int los, double[] r, double[] v)
        {
            string h = (hold ?? "").ToUpperInvariant();
            if (h == "INRTL") return new double[] { 0, 0, 0 };
            if (h == "LVLH" || (h == "TRACK" && los == 0))
            {
                double r2 = r[0] * r[0] + r[1] * r[1] + r[2] * r[2];
                if (r2 < 1) return null;
                return new[] { (r[1] * v[2] - r[2] * v[1]) / r2, (r[2] * v[0] - r[0] * v[2]) / r2, (r[0] * v[1] - r[1] * v[0]) / r2 };
            }
            if (h == "TRACK") return new double[] { 0, 0, 0 };
            return null;
        }

        // THE ANGULAR MOMENTUM A PACKED VESSEL CARRIES. Principia keeps a vessel's rotation as the angular momentum of its
        // pile-up and rewrites every part's rigid-body rate from it in each physics frame, so setting the parts' rates does not stick
        // (the pack line showed the 0.23 deg/s back at the pack, a frame after a set to 0, and the vessel turned 35 deg in the warp).
        // What changes the pile-up's angular momentum is a part torque (Part.AddTorque -> part.torque, which Principia reads as an
        // intrinsic torque and integrates over the frame's step). This is the maths: the angular momentum to add so that the body
        // has the angular velocity wT (pure maths, world axes, no KSP types).
        public class PartBody
        {
            public double M;                                 // mass (t)
            public double[] P = new double[3];               // the part's centre of mass (world)
            public double[] V = new double[3];               // its velocity
            public double[] W = new double[3];               // its angular velocity (rad/s)
            public double[] I = new double[9];               // its inertia tensor about its own centre of mass, world axes, row-major (t m2)
        }

        // dL = I_tot wT - L; L = sum(I_p w_p + m_p d_p x (v_p - V)), I_tot = sum(I_p + m_p (d.d E - d d^T)), d = p - the centre of mass.
        // false (nothing set) with no mass or a number not finite.
        public static bool MomentumChange(PartBody[] parts, double[] wT, out double[] dL, out double[] L, out double[] iTot, out double mass)
        {
            dL = new double[3]; L = new double[3]; iTot = new double[9]; mass = 0;
            if (parts == null || parts.Length == 0 || wT == null || wT.Length != 3) return false;
            double m = 0;
            double[] c = new double[3], vc = new double[3];
            foreach (PartBody p in parts)
            {
                m += p.M;
                for (int i = 0; i < 3; i++) { c[i] += p.M * p.P[i]; vc[i] += p.M * p.V[i]; }
            }
            if (!(m > 0)) return false;
            for (int i = 0; i < 3; i++) { c[i] /= m; vc[i] /= m; }
            foreach (PartBody p in parts)
            {
                double[] d = { p.P[0] - c[0], p.P[1] - c[1], p.P[2] - c[2] };
                double[] dv = { p.V[0] - vc[0], p.V[1] - vc[1], p.V[2] - vc[2] };
                double d2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
                for (int i = 0; i < 3; i++)
                    for (int j = 0; j < 3; j++)
                    {
                        L[i] += p.I[3 * i + j] * p.W[j];
                        iTot[3 * i + j] += p.I[3 * i + j] + p.M * ((i == j ? d2 : 0) - d[i] * d[j]);
                    }
                L[0] += p.M * (d[1] * dv[2] - d[2] * dv[1]);
                L[1] += p.M * (d[2] * dv[0] - d[0] * dv[2]);
                L[2] += p.M * (d[0] * dv[1] - d[1] * dv[0]);
            }
            for (int i = 0; i < 3; i++)
                dL[i] = iTot[3 * i] * wT[0] + iTot[3 * i + 1] * wT[1] + iTot[3 * i + 2] * wT[2] - L[i];
            mass = m;
            foreach (double x in dL) if (double.IsNaN(x) || double.IsInfinity(x)) return false;
            return true;
        }

        // The change of angular momentum dL as a RIGID acceleration of every part: the whole body's angular velocity changes by
        // u = I_tot^-1 dL, part p gets the torque I_p u / dt and the force m_p (u x d_p) / dt (d_p from the centre of mass), so each part moves
        // as the rigid body does (no joint is strained) and sum(tau_p + d_p x F_p) = I_tot u / dt = dL / dt, sum F_p = 0.
        // (F3 gave every part a mass share of dL / dt: the part's own inertia is tiny, the parts spun against each other, and the
        // inertia was summed over the PARENT's body again for each part without a body of its own: 2x too big.)
        public static bool RigidShares(PartBody[] parts, double[] dL, double dt, out double[] u, out double[][] tau, out double[][] force)
        {
            u = new double[3]; tau = null; force = null;
            if (parts == null || parts.Length == 0 || dL == null || dL.Length != 3 || !(dt > 0)) return false;
            double[] dl2, l, it; double m;
            if (!MomentumChange(parts, new double[] { 0, 0, 0 }, out dl2, out l, out it, out m)) return false;
            double[] c = new double[3];
            foreach (PartBody p in parts) for (int i = 0; i < 3; i++) c[i] += p.M * p.P[i];
            for (int i = 0; i < 3; i++) c[i] /= m;
            double det = it[0] * (it[4] * it[8] - it[5] * it[7]) - it[1] * (it[3] * it[8] - it[5] * it[6]) + it[2] * (it[3] * it[7] - it[4] * it[6]);
            if (!(Math.Abs(det) > 1e-12)) return false;
            double[] inv = {
                (it[4] * it[8] - it[5] * it[7]) / det, (it[2] * it[7] - it[1] * it[8]) / det, (it[1] * it[5] - it[2] * it[4]) / det,
                (it[5] * it[6] - it[3] * it[8]) / det, (it[0] * it[8] - it[2] * it[6]) / det, (it[2] * it[3] - it[0] * it[5]) / det,
                (it[3] * it[7] - it[4] * it[6]) / det, (it[1] * it[6] - it[0] * it[7]) / det, (it[0] * it[4] - it[1] * it[3]) / det };
            for (int i = 0; i < 3; i++) u[i] = inv[3 * i] * dL[0] + inv[3 * i + 1] * dL[1] + inv[3 * i + 2] * dL[2];
            tau = new double[parts.Length][]; force = new double[parts.Length][];
            for (int k = 0; k < parts.Length; k++)
            {
                PartBody p = parts[k];
                double[] d = { p.P[0] - c[0], p.P[1] - c[1], p.P[2] - c[2] };
                tau[k] = new double[3]; force[k] = new double[3];
                for (int i = 0; i < 3; i++) tau[k][i] = (p.I[3 * i] * u[0] + p.I[3 * i + 1] * u[1] + p.I[3 * i + 2] * u[2]) / dt;
                force[k][0] = p.M * (u[1] * d[2] - u[2] * d[1]) / dt;
                force[k][1] = p.M * (u[2] * d[0] - u[0] * d[2]) / dt;
                force[k][2] = p.M * (u[0] * d[1] - u[1] * d[0]) / dt;
                for (int i = 0; i < 3; i++) if (double.IsNaN(tau[k][i] + force[k][i]) || double.IsInfinity(tau[k][i] + force[k][i])) return false;
            }
            return true;
        }

        // THE SETTLE. The F3b torque impulse of the warp request needs a
        // physics frame between it and the vessel's pack to reach Principia's pile-up, and the test-harness logs show the pack in the SAME frame as the request (rates index 3 x4) or
        // BEFORE the request event (the second warp): the impulse never integrates, the pack's angular momentum stays (0.19 / 0.26 / 1.43 t m2/s) and the vessel turns 0.014 ..
        // 0.09 deg/s through the whole warp (41 deg in 2920 s, 17 deg in 190 s). A one-shot that does land leaves ~1 % (0.001 deg/s = 0.25 deg in 220 s). So the rate is taken
        // to the armed one in a CLOSED LOOP, before the warp is asked for: each physics frame the error (the rate change the held momentum still needs, deg/s) is read; over
        // ErrOk an impulse goes in (at most one per GapFrames frames: Principia reads part.torque in the next frame, so the error read after it is the new one); under it for
        // QuietFrames frames in a row the settle is done. Pure state machine (no KSP types).
        public class Settle
        {
            public const double ErrOk = 0.0002;      // deg/s
            public const int QuietFrames = 3, GapFrames = 3, MaxImpulses = 8;
            public const double MaxReal = 3;         // real s
            public int Impulses, Quiet, Since = 99, Frames;
            public double T0, LastErr = -1;
            public bool Done;
            public string Why = "";
            public void Start(double now) { Impulses = 0; Quiet = 0; Since = 99; Frames = 0; T0 = now; LastErr = -1; Done = false; Why = ""; }
            public void Finish(string why) { Done = true; Why = why; }
            // one physics frame with the error read: 1 = add an impulse now, 0 = wait, -1 = done (Why says how)
            public int Step(double errDegS, double now)
            {
                if (Done) return -1;
                Frames++; Since++; LastErr = errDegS;
                if (now - T0 > MaxReal) { Finish("TIMEOUT"); return -1; }
                if (Since < GapFrames) { Quiet = 0; return 0; }
                if (errDegS <= ErrOk) { Quiet++; if (Quiet >= QuietFrames) { Finish("SETTLED"); return -1; } return 0; }
                Quiet = 0;
                if (Impulses >= MaxImpulses) { Finish("GAVE UP"); return -1; }
                Impulses++; Since = 0;
                return 1;
            }
        }

        // A warp the PILOT starts has no kOS settle before it,
        // so the DLL holds the request (Harmony prefix on TimeWarp.SetRate, KalsAddon.Rails.cs) while the settle takes the vessel's rate to the hold's, then asks the
        // game for the warp itself. Pure state (no KSP types): what is held, and when it is let go.
        public class WarpGate
        {
            public const double MaxReal = 6;         // real s: a held request is let go at the latest after this (the settle's own limit is 3)
            public bool Pending;
            public int Index;
            public bool Instant, Post;
            public double T0;
            // a request is worth holding: the DLL is armed HOLD and the hold gives a rate, the warp mode is rails (HIGH), the warp is at 1x now and the request is a rails rate
            public static bool Wants(bool armHold, bool holdRate, bool railsMode, int curIndex, int reqIndex)
            {
                return armHold && holdRate && railsMode && curIndex == 0 && reqIndex > 0;
            }
            public void Hold(int idx, bool instant, bool post, double now) { if (!Pending) T0 = now; Pending = true; Index = idx; Instant = instant; Post = post; }
            public void Cancel() { Pending = false; }
            // true = let the held request go now: the settle is over (any way), or the hold has lasted MaxReal
            public bool Due(bool settling, double now) { return Pending && (!settling || now - T0 > MaxReal); }
        }

        // . Two frame facts the DAP code did not know:
        //  1. A rails frame is TimeScale x fixedDeltaTime long (2 s at x100): whatever the RCS is commanded in the frame the request or the pack lands in, the game integrates over
        //     the whole step (the log: pitch command 0.025 in the 2.04 s frame, the vessel's rate 0.1213 -> 0.0567 deg/s at the pack). So the DAP's jets are zero from the settle on.
        //  2. A vessel that unpacks gives rate 0 and an actuation 0 for its first frame(s) (the log: 'rate now 0 deg/s', gimbal 0.000), so the DAP's first ticks after a gap read a
        //     false rate error (a -0.493 pitch command) and the pilot readback (gimbal actuation less the last trim) read -0.052 = out of detent (DET 0.05): CSS.
        // DapQuiet: the DAP commands nothing while a rails warp is on (or asked for: the gate / a settle running). TickGap: a gap in the vessel's physics ticks (Time.fixedTime,
        // NOT UT: a 100x frame is 2 s of UT but still one fixed step), i.e. the vessel was packed; step = Time.fixedDeltaTime. QuietTicks: ticks the DAP stays quiet after a gap.
        public const int QuietTicks = 5;
        public static bool DapQuiet(bool railsWarp, bool settling, bool gatePending) { return railsWarp || settling || gatePending; }
        public static bool TickGap(double prevFixed, double nowFixed, double step)
        {
            if (!(step > 0)) step = 0.02;
            return nowFixed < prevFixed || nowFixed - prevFixed > 2.5 * step;
        }

        // the arm: mode + the rate for VEC, and when it lapses (real time)
        public class Arm
        {
            public bool On;
            public string Mode = "";
            public double[] W = { 0, 0, 0 };
            public double Until;                 // real time
            public int Sets;                     // how many times a rate was set under this arm (a warp's pack events)

            public string Set(string mode, double[] w, double now)
            {
                string m = (mode ?? "").ToUpperInvariant();
                if (m == "OFF") { On = false; Mode = ""; return ""; }
                if (m != "ZERO" && m != "VEC" && m != "HOLD") return "error mode " + m + " (ZERO VEC HOLD OFF)";
                if (m == "VEC" && (w == null || w.Length != 3 || double.IsNaN(w[0] + w[1] + w[2]) || double.IsInfinity(w[0] + w[1] + w[2]))) return "error VEC needs a finite vector";
                if (m == "VEC" && Math.Sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) > 0.5) return "error VEC over 0.5 rad/s";
                On = true; Mode = m; Until = now + TTL; Sets = 0;
                W = m == "VEC" ? new[] { w[0], w[1], w[2] } : new double[] { 0, 0, 0 };
                return "";
            }

            // the rate to set now, null = none (not armed, lapsed, or the HOLD gives none)
            public double[] Take(double now, string hold, int los, double[] r, double[] v)
            {
                if (!On) return null;
                if (now > Until) { On = false; return null; }
                if (Mode == "HOLD") return HoldRate(hold, los, r, v);
                return new[] { W[0], W[1], W[2] };
            }
        }
    }
}
