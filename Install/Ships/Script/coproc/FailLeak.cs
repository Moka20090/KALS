// THE LEAKS AND THE SINGLE JET: the pure maths and names of OMS 04 / RCS 03 / RCS 04. NO KSP or kOS type here: FailEnforce.cs
// does the parts, tests/fail_offline runs this very file.
//   OMS 04 OMS PROPELLANT LEAK  target FU / OX / BOTH, value "0.05 KG/S" / "0.2 KG/S"   (fix ISOLATE TANK, 5 s)
//   RCS 03 RCS PROPELLANT LEAK  target FWD / AFT,       value "1 %/MIN" / "5 %/MIN"       (fix MANIFOLD CLOSE, 5 s)
//   RCS 04 RCS SINGLE JET       target a JET NAME,      value "FAIL OFF" / "FAIL ON" / "LEAK" (fix MANIFOLD CLOSE, 5 s)
// A JET NAME is "F<k>" (the k-th thruster of the FORWARD RCS group) or "A<k>" (of the AFT group), k = 1 .. 99: the thrusters of a
// group counted in order of part flight id, module, thruster (stable across loads); a k past the group's last jet wraps round.
using System;
using System.Globalization;

namespace KalsCoproc
{
    public static class FailLeak
    {
        public const double G0 = 9.80665;
        public const double JetLeakPctMin = 0.5;        // RCS 04 LEAK: % of the group's tank per minute
        public const double DefaultIsp = 240;           // s, when a module gives none

        static double Num(string s, double dflt)
        {
            if (string.IsNullOrEmpty(s)) return dflt;
            string w = s.Trim().Split(' ')[0];
            double v;
            return double.TryParse(w, NumberStyles.Float, CultureInfo.InvariantCulture, out v) && v >= 0 ? v : dflt;
        }

        // OMS 04's value "0.2 KG/S" -> 0.2 (kg/s); 0.05 for anything else
        public static double OmsKgPerS(string value) { return Num(value, 0.05); }

        // RCS 03's value "5 %/MIN" -> 5; RCS 04 LEAK -> JetLeakPctMin; 1 for anything else
        public static double PctPerMin(string code, string value)
        {
            if (code == "RCS 04") return JetLeakPctMin;
            return Num(value, 1);
        }

        // the resources OMS 04 drains by its target: FU = LiquidFuel, OX = Oxidizer, BOTH = both
        public static string[] OmsResources(string target)
        {
            switch ((target ?? "").Trim().ToUpperInvariant())
            {
                case "FU": return new string[] { "LiquidFuel" };
                case "OX": return new string[] { "Oxidizer" };
                case "BOTH": return new string[] { "LiquidFuel", "Oxidizer" };
            }
            return new string[0];
        }

        // kg/s of one propellant -> units/s of the tank, from the resource's density in t per unit (KSP: LiquidFuel / Oxidizer 0.005)
        public static double UnitsPerS(double kgPerS, double densityTPerUnit)
        {
            return densityTPerUnit > 1e-9 ? kgPerS / (densityTPerUnit * 1000.0) : 0;
        }

        // %/min of a tank of maxAmount units -> units per s
        public static double PctUnitsPerS(double pctPerMin, double maxAmount) { return maxAmount * pctPerMin / 100.0 / 60.0; }

        // a jet held ON: the monopropellant it burns, units/s = F kN / (Isp g0) t/s / density t per unit
        public static double JetUnitsPerS(double forceKn, double isp, double densityTPerUnit)
        {
            if (isp < 1) isp = DefaultIsp;
            return densityTPerUnit > 1e-9 ? forceKn / (isp * G0) / densityTPerUnit : 0;
        }

        // what a leak takes in dt s from a tank holding have units: never below 0, never negative (a clock that stepped back drains nothing)
        public static double Drained(double unitsPerS, double dt, double have)
        {
            if (dt <= 0 || unitsPerS <= 0 || have <= 0) return 0;
            double d = unitsPerS * dt;
            return d > have ? have : d;
        }

        // "F3" -> forward group, 3; "A12" -> aft, 12; anything else false
        public static bool ParseJet(string target, out bool forward, out int k)
        {
            forward = false; k = 0;
            string t = (target ?? "").Trim().ToUpperInvariant();
            if (t.Length < 2 || t.Length > 3) return false;
            if (t[0] != 'F' && t[0] != 'A') return false;
            int v;
            if (!int.TryParse(t.Substring(1), NumberStyles.None, CultureInfo.InvariantCulture, out v) || v < 1 || v > 99) return false;
            forward = t[0] == 'F'; k = v;
            return true;
        }

        // the 0-based place in a group of total jets that name number k (1-based) means: wraps round, -1 = no jets
        public static int Wrap(int k, int total)
        {
            if (total <= 0 || k < 1) return -1;
            return (k - 1) % total;
        }

        // the bound-parts token of a jet (FailState.NormParts allows "uid:digits", at most 3): module * 100 + jet, so a module 0 .. 9, a jet 0 .. 99
        public static string Token(string uid, int module, int jet)
        {
            if (module < 0 || module > 9 || jet < 0 || jet > 99) return null;
            return uid + ":" + (module * 100 + jet).ToString(CultureInfo.InvariantCulture);
        }
        public static void Untoken(int n, out int module, out int jet)
        {
            if (n < 0) { module = 0; jet = 0; return; }
            module = n / 100; jet = n % 100;
        }
    }
}
