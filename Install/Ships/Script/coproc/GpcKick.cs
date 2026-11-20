// DPS 06 GPC OUTPUT BAD. For a short spell (1-3 s) one GPC's commands are wrong: the DAP's control output
// carries a BIAS on ONE axis (pitch, yaw or roll) that rises and falls in a half sine, sized to be felt and always recoverable. After the spell the other GPCs vote it out
// (lib_gpc.ks: the GPC is an out-of-set GPC like DPS 03). NO KSP or kOS type here: KalsAddon.GpcKick.cs is the face (GPCKICK + the fly-by-wire hook), tests/simsup_offline runs
// the envelope. The bias is added to the FINAL control state (Vessel.OnFlyByWire runs after every autopilot: kOS cooked steering, the C# DAPs, SAS), so it works under whatever flies.
using System;

namespace KalsCoproc
{
    public static class GpcKick
    {
        public const double AmpMax = 0.22;        // the peak bias as a control fraction (-1..1): about a fifth of the stick, a felt transient, never a departure
        public const double DurMin = 1, DurMax = 3;
        public const double QRef = 12;            // kPa: the bias falls as 1 / (1 + q / QRef) (a felt kick in space and on the climb, a small one at entry's and the landing's high q)

        public static bool On;
        public static int Axis;                   // 0 pitch, 1 yaw, 2 roll
        public static double Sign = 1, T0, Dur;

        public static string AxisName(int a) { return a == 0 ? "PITCH" : a == 1 ? "YAW" : "ROLL"; }
        public static int AxisOf(string s)
        {
            s = (s ?? "").Trim().ToUpperInvariant();
            if (s == "PITCH") return 0;
            if (s == "YAW") return 1;
            if (s == "ROLL") return 2;
            return -1;
        }

        // start a spell (a second call replaces the first); "OK" or the refusal
        public static string Start(string axis, double sign, double dur, double now)
        {
            int a = AxisOf(axis);
            if (a < 0) return "REFUSE: BAD AXIS " + axis;
            if (double.IsNaN(sign) || double.IsNaN(dur) || double.IsInfinity(dur)) return "REFUSE: BAD NUMBER";
            Axis = a; Sign = sign < 0 ? -1 : 1; Dur = Math.Max(DurMin, Math.Min(DurMax, dur)); T0 = now; On = true;
            return "OK";
        }

        // the bias NOW (a control fraction, signed) at dynamic pressure q (kPa); 0 outside the spell. Ends the spell (On = false) once it is over.
        public static double Level(double now, double qKpa)
        {
            if (!On) return 0;
            double x = (now - T0) / Dur;
            if (x >= 1) { On = false; return 0; }
            if (x < 0) return 0;
            double q = double.IsNaN(qKpa) || qKpa < 0 ? 0 : qKpa;
            return Sign * AmpMax * Math.Sin(Math.PI * x) / (1 + q / QRef);
        }

        public static void Cancel() { On = false; }
    }
}
