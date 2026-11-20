// The ascent's BACKUP G-LIMITER (pure math; the KSP side, the AG4 press and the suffixes are KalsAddon.AscMeco.cs).
// The orbiter's guidance throttles the SSMEs down to hold 3 g (kOS lib_ascent_s2 asc_glim, ASC_AL 29.108 m/s2 = 95.5 ft/s2).
// With guidance not throttling (SW 02 GUIDANCE LOST holds the last command; a hand throttle) nothing held the accel. This
// limiter works on the vessel's FINAL throttle (the main throttle the engines on it follow), only DOWN: final = min(cmd, Cap),
// Cap never below the SSME floor (67 PL %), never above 1.
// THE LAW: the thrust of the engines on the main throttle is affine in the throttle, F(t) = F0 + S (t - t0), with S the slope
// (kN per unit throttle) the KSP side sums from the engines themselves (so a minimum thrust does not spiral). The engines off
// the main throttle (an OMS on its own throttle, solids) add FOther. The throttle that holds ALimit is
//     allowed = t0 + (ALimit m - F0 - FOther) / S
// (Newton on the linear model, exact for the SSMEs). Cap follows clamp(allowed, Floor, 1), down at RateDn, up at RateUp
// (units of throttle per second), so a throttle command that rises later meets a Cap already tracking the limit.
// The Cap keeps TRACKING always, but the
// FINAL throttle is cut only while Gate is TRUE (kOS sets it, ops1q asc_am_poll: the ascent guidance is down, SW 02 GUIDANCE LOST / a
// DPS 04 / DPS 05 hold with the BFS not engaged). Gate FALSE (the default, and after every Reset): final = command, Limiting FALSE.
using System;

namespace KalsCoproc
{
    public class AscMecoCore
    {
        public const double G0 = 9.80665;
        public const double KSP_PER_PL = 0.9560439560439561;    // lib_ascent_iload ASC_PL_TO_KSP: KSP throttle per PL % / 100
        public double ALimit = 3.0 * G0;                        // m/s2: the project owner's 3 g
        public double Floor = 0.67 * KSP_PER_PL;                // the SSME floor, 67 PL % (ASC_KMIN)
        public double RateDn = 0.20 * KSP_PER_PL;               // throttle / s down (20 PL % / s)
        public double RateUp = 0.10 * KSP_PER_PL;               // throttle / s up (10 PL % / s)

        public double Cap = 1;          // the ceiling on the main throttle now
        public double Allowed = 1;      // the throttle that holds ALimit, last computed
        public double ANow;             // the accel before this step's cut, m/s2
        public bool Limiting;           // the final throttle was cut below the command
        public bool AtFloor;            // the limit asks for less than the floor: the floor holds, the accel is above the limit
        public bool Gate;               // T1001: the guidance has failed (set by kOS): only then the final throttle is cut

        public void Reset() { Cap = 1; Allowed = 1; ANow = 0; Limiting = false; AtFloor = false; Gate = false; }

        // cmd: the main throttle commanded 0..1; fMain kN of the engines on it now, thrNow their throttle now, slope kN per unit
        // throttle (<= 0: no model, the cap holds), fOther kN of the rest, mass t, dt s. Returns the final throttle.
        public double Step(double cmd, double fMain, double thrNow, double slope, double fOther, double mass, double dt)
        {
            if (double.IsNaN(cmd)) cmd = 0;
            if (cmd < 0) cmd = 0;
            if (cmd > 1) cmd = 1;
            ANow = mass > 0.001 ? (fMain + fOther) / mass : 0;
            if (mass > 0.001 && slope > 1E-6 && !double.IsNaN(fMain) && !double.IsNaN(slope))
                Allowed = thrNow + (ALimit * mass - fMain - fOther) / slope;
            double tgt = Math.Min(1, Math.Max(Floor, Allowed));
            AtFloor = Allowed < Floor;
            if (dt < 0 || dt > 1) dt = 0.02;
            if (tgt < Cap) Cap = Math.Max(tgt, Cap - RateDn * dt);
            else Cap = Math.Min(tgt, Cap + RateUp * dt);
            if (!Gate) { Limiting = false; return cmd; }     // T1001: the guidance is throttling: the backup never touches the throttle
            double fin = Math.Min(cmd, Cap);
            Limiting = fin < cmd - 1E-4;
            return fin;
        }
    }
}
