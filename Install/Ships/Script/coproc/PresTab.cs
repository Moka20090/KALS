// SHIP:BODY's pressure for the worker threads (the family build, Fam.cs; the deorbit solver, DpSolve.cs), as a table
// taken on the main thread. CelestialBody.GetPressure evaluates the body's pressureCurve, a Unity AnimationCurve that caches
// its last segment: called from the family's eight workers at once, and alongside KSP's own physics, it returned garbage now
// and then. Every family.txt had one-sample drag spikes of 2.5x (the drag at Mach 0: a pressure of 0 mid-atmosphere) and
// smaller ones (a wrong Mach), in most members. The table is GetPressure itself every 10 m, read log-linearly (2.6e-7 at
// worst on Sol's curve, below the curve's own float32); a worker touches no Unity object.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    public static class PresTab
    {
        const double KPA_TO_ATM = 0.0098692326671601278;   // kOS.dll's constant (ALTITUDEPRESSURE = GetPressure x this)
        const double STEP = 10;                            // m
        static readonly Dictionary<string, Func<double, double>> cache = new Dictionary<string, Func<double, double>>();

        // the pressure (atm) at an altitude, as kOS's ALTITUDEPRESSURE; main thread only (the returned function is not)
        public static Func<double, double> Of(CelestialBody body)
        {
            string key = body.bodyName + "|" + body.atmosphereDepth.ToString("R");
            Func<double, double> f;
            if (cache.TryGetValue(key, out f)) return f;
            if (!body.atmosphere || body.atmosphereDepth <= 0) f = x => 0;
            else
            {
                double top = body.atmosphereDepth;
                int n = (int)Math.Ceiling(top / STEP) + 1;
                var p = new double[n];
                var lp = new double[n];
                for (int i = 0; i < n; i++)
                {
                    p[i] = body.GetPressure(Math.Min(i * STEP, top)) * KPA_TO_ATM;
                    lp[i] = p[i] > 0 ? Math.Log(p[i]) : 0;
                }
                f = x =>
                {
                    if (x >= top) return 0;                    // GetPressure: none at and above the atmosphere's top
                    if (x <= 0) return p[0];                   // the callers clamp at 0
                    double u = x / STEP;
                    int i = (int)u;
                    if (i >= n - 1) return p[n - 1];
                    double w = u - i;
                    if (p[i] > 0 && p[i + 1] > 0) return Math.Exp(lp[i] + w * (lp[i + 1] - lp[i]));
                    return p[i] + w * (p[i + 1] - p[i]);
                };
            }
            cache[key] = f;
            return f;
        }
    }
}
