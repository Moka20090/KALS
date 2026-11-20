// THE CANADARM'S JOINTS DRIVEN EVERY PHYSICS TICK (the core: plain C#, no Unity or KSP, so the offline test and the
// arm VM run this same code; ArmDriveKsp.cs binds it to the servos, KalsAddon.Arm.cs gives kOS its suffixes).
// Why (the arm needed damping, and MAN AUG's steps were coarse and jerky, with overshoot and ringing): kOS's SETFIELD rounds a servo's 'target angle' to its 1 deg slider step and writes
// it once a kOS tick (~6 a second under MAN AUG), and the servo itself slews its drive target at a constant 'traverse rate'
// (BaseServo OnFixedUpdate: MoveTowards(drive, target, traverseVelocity x dt)): every start and stop is a step in rate,
// which rings the arm's soft attach joints (arm_motion_75379: ~1.3 s, +-1.5 cm at the end effector for ~5 s).
// Here each joint's command is a double, moved on every physics tick and written to the servo unrounded, with no step in
// rate or in acceleration:
//   RATE  kOS hands the joint rates (deg/s); each passes two first-order stages of time constant Tau (the rate flown is the
//         second stage: continuous, its derivative continuous after the first tick), the command integrates it.
//   GOTO  kOS hands the goals and a time T: every joint follows the minimum-jerk profile s(u) = 10u^3 - 15u^4 + 6u^5
//         (u = t / T: no rate, no acceleration at either end), all on one straight joint-space line, arriving together;
//         with a blend time tb (2 tb < T) a cruise at the peak rate instead, its rate blended up and down over tb by the
//         smooth step 3x^2 - 2x^3 (no step in rate or in acceleration): a long AUTO leg takes its constant-rate time + tb,
//         where the minimum-jerk profile at the same peak rate would take 1.875 x it.
//   STOP  RATE with every rate 0 (the arm coasts to rest over ~3 Tau).
// The lead: a joint drive with damper c and spring k trails a steady rate w by w c / k (the damper's drag); the written
// target leads the command by that (Lead[i] = c / k s, set by ArmDriveKsp from the live drive), so the joint itself runs on
// the command. Held joints (locked by kOS) are not moved; Seed puts a joint's command where its drive is (at an unlock).
// The limits: a command is kept inside [Lo, Hi] (the servo's soft range); a joint that reaches one stops there (rate 0).
// THE DAMPING (Crit): the damper that damps a joint's own mode at the ratio zeta for the inertia I outboard of it about its
// axis and the drive's spring k: c = zeta x 2 sqrt(k I) (KSP's damper is linear in the part's 'damping' field, so
// ArmDriveKsp scales that field by c / c_now).
using System;

namespace KalsCoproc
{
    public class ArmDriveCore
    {
        public const int RATE = 0, GOTO = 1;
        public int N;
        public double[] Th, R1, R2, Rin, Lo, Hi, Lead, G0, G1;
        public bool[] Held;
        public int Mode = RATE;
        public double Tau = 0.3, GT = 1, Gt = 0, GB = 0;
        public bool GDone = true;

        public ArmDriveCore(int n)
        {
            N = n;
            Th = new double[n]; R1 = new double[n]; R2 = new double[n]; Rin = new double[n];
            Lo = new double[n]; Hi = new double[n]; Lead = new double[n]; G0 = new double[n]; G1 = new double[n];
            Held = new bool[n];
            for (int i = 0; i < n; i++) { Lo[i] = -1e9; Hi[i] = 1e9; }
        }

        public void Seed(int i, double th)                     // joint i's command where its drive is, at rest
        {
            Th[i] = th; R1[i] = 0; R2[i] = 0; Rin[i] = 0;
            if (Mode == GOTO && !GDone) G0[i] = th;            // a GOTO under way: the profile goes on from here to its goal
        }

        public void SetRates(double[] r, double tau)           // RATE: kOS's rates (deg/s), the filter's time constant (s)
        {
            if (Mode == GOTO) { for (int i = 0; i < N; i++) { R1[i] = R2[i]; } }   // from a profile: its rate carried on
            Mode = RATE; GDone = true;
            Tau = Math.Max(0.02, tau);
            for (int i = 0; i < N; i++) Rin[i] = (r != null && i < r.Length && !double.IsNaN(r[i])) ? r[i] : 0;
        }

        public const double GOTO_TMIN = 4;                     // s: the shortest profile (~3 periods of the arm's 1.3 s ring)
        public void Goto(double[] goal, double T) { Goto(goal, T, 0); }
        public void Goto(double[] goal, double T, double tb)   // GOTO: every joint to its goal in T s (at least GOTO_TMIN) on the
        {                                                      // minimum-jerk profile, or blended over tb (Profile)
            Mode = GOTO; GDone = false; Gt = 0; GT = Math.Max(GOTO_TMIN, T);
            GB = (tb > 0 && 2 * tb < GT) ? tb : 0;
            for (int i = 0; i < N; i++)
            {
                G0[i] = Th[i];
                G1[i] = (goal != null && i < goal.Length && !double.IsNaN(goal[i])) ? Clamp(goal[i], Lo[i], Hi[i]) : Th[i];
                Rin[i] = 0; R1[i] = 0; R2[i] = 0;
            }
        }

        public static double MinJerk(double u) { if (u <= 0) return 0; if (u >= 1) return 1; return u * u * u * (10 - 15 * u + 6 * u * u); }
        public static double MinJerkD(double u) { if (u <= 0 || u >= 1) return 0; double a = u * (1 - u); return 30 * a * a; }   // ds/du
        public static double GotoTime(double dq, double rmax) { return rmax <= 0 ? 0 : 1.875 * Math.Abs(dq) / rmax; }
        public static double Smooth(double x) { if (x <= 0) return 0; if (x >= 1) return 1; return x * x * (3 - 2 * x); }
        public static double SmoothI(double x) { if (x <= 0) return 0; if (x >= 1) return 0.5; return x * x * x * (1 - 0.5 * x); }   // its integral
        // the share s of the way at t of T (blend tb, 0: minimum jerk) and its rate ds/dt (1/s)
        public static void Profile(double t, double T, double tb, out double s, out double sd)
        {
            if (tb <= 0) { s = MinJerk(t / T); sd = MinJerkD(t / T) / T; return; }
            double V = 1 / (T - tb);
            if (t <= 0) { s = 0; sd = 0; }
            else if (t >= T) { s = 1; sd = 0; }
            else if (t < tb) { s = V * tb * SmoothI(t / tb); sd = V * Smooth(t / tb); }
            else if (t <= T - tb) { s = V * (tb / 2 + t - tb); sd = V; }
            else { s = 1 - V * tb * SmoothI((T - t) / tb); sd = V * Smooth((T - t) / tb); }
        }

        public void Tick(double dt)                             // one physics tick of dt s
        {
            if (dt <= 0) return;
            if (Mode == GOTO)
            {
                Gt += dt;
                double u = Gt / GT, s, sd;
                Profile(Gt, GT, GB, out s, out sd);
                for (int i = 0; i < N; i++)
                {
                    if (Held[i]) { R1[i] = 0; R2[i] = 0; continue; }
                    double dq = G1[i] - G0[i];
                    Th[i] = G0[i] + dq * s; R2[i] = dq * sd; R1[i] = R2[i];
                }
                if (u >= 1) GDone = true;
                return;
            }
            double a = Math.Exp(-dt / Tau);
            for (int i = 0; i < N; i++)
            {
                if (Held[i]) { R1[i] = 0; R2[i] = 0; continue; }
                double r1 = Rin[i] + (R1[i] - Rin[i]) * a;          // the first stage, exact for a held input
                R2[i] = r1 + (R2[i] - r1) * a;                       // the second (the input taken as r1 over the tick)
                R1[i] = r1;
                double th = Th[i] + R2[i] * dt;
                if (th <= Lo[i]) { th = Lo[i]; if (R2[i] < 0) { R1[i] = 0; R2[i] = 0; } }
                if (th >= Hi[i]) { th = Hi[i]; if (R2[i] > 0) { R1[i] = 0; R2[i] = 0; } }
                Th[i] = th;
            }
        }

        public double Target(int i) { return Clamp(Th[i] + R2[i] * Lead[i], Lo[i], Hi[i]); }   // what the servo is handed

        public bool AtRest(double eps)                           // every joint's flown rate and input below eps (deg/s)
        {
            if (Mode == GOTO) return GDone;
            for (int i = 0; i < N; i++) if (Math.Abs(R2[i]) > eps || Math.Abs(R1[i]) > eps || Math.Abs(Rin[i]) > eps) return false;
            return true;
        }

        public static double Clamp(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }

        // the damper for the ratio zeta on inertia I (t m2) with spring k (kN m / rad): kN m s / rad
        public static double Crit(double zeta, double k, double I) { return (k <= 0 || I <= 0) ? 0 : zeta * 2 * Math.Sqrt(k * I); }
        public static double Ratio(double c, double k, double I) { return (k <= 0 || I <= 0) ? 0 : c / (2 * Math.Sqrt(k * I)); }
    }
}
