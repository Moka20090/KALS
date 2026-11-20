// The manual MECO and the backup 3 g limiter of the ascent, flown in C# (the math: AscMeco.cs).
//   THE PRESS: AG4's state is watched every physics tick (AfbwThrottle.Fin calls AscMecoTick); a CHANGE is a press (ops2q's
//     convention; the baseline is read at the first tick after a reset and carried on, so a stray AG4 from earlier is no press).
//     mode 0 (idle: before SRB sep) a press is counted as EARLY; mode 1 (armed: from SRB sep to MECO) a press with an SSME lit
//     is the MECO press (latched until kOS takes it); mode 2 (done: after MECO) nothing. The press only latches: ops1q's
//     asc_stage2 takes it and runs the one MECO path (asc_meco: throttle 0, the SSMEs shut down, gimbals locked, ET SEP).
//   THE LIMITER: armed (mode 1) the final throttle is min(command, cap) after kOS's lock and AfbwThrottle's guard (the last
//     thing Fin does), the cap holding the sensed accel (the engines' thrust / mass) at the limit, never below the SSME floor.
//     ADDONS:KALS:ASCMECO(LIST(mode[, limit m/s2])) -> "": mode 3 reset to idle (the limit back to 3 g, the baseline re-read),
//         1 arm, 0 done (limiter and press off). The limit (optional, with mode 1) is for a test only.
//         T1001: mode 4 with (LIST(4, g)) sets the GATE: g > 0 = the ascent guidance has failed (the limiter may cut), 0 = it is throttling
//         (the limiter never changes the throttle). Every reset / arm / done (modes 3 / 1 / 0) clears the gate; kOS (asc_am_poll) sets it
//         again on change. The cap tracks the limit with the gate off too, so it is ready at a failure.
//     ADDONS:KALS:ASCMECOTAKE -> 0 nothing, 1 the MECO press, 2 an early press (one each call, the MECO press first).
//     ADDONS:KALS:ASCMECOSTATE -> LIST(mode, limiting, cap, allowed, accel m/s2, the final throttle, limited ticks, at floor,
//         the limit, the gate (T1001)).
// KSP.log lines start with [KalsAscMeco].
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        const double AMC_REFRESH = 0.5;      // s of real time between engine list rebuilds

        static readonly AscMecoCore amc = new AscMecoCore();
        static int amcMode;                  // 0 idle, 1 armed, 2 done
        static bool amcHaveBase, amcAg;      // AG4's last state
        static int amcPress, amcEarly;       // latched presses
        static Vessel amcVessel;
        static readonly List<ModuleEngines> amcEng = new List<ModuleEngines>();
        static double amcRefreshT = -1E9;
        static int amcLimitedTicks;
        static double amcFinal;
        static bool amcWasLimiting;

        partial void RegisterAscMeco()
        {
            AddSuffix("ASCMECO", new OneArgsSuffix<StringValue, ListValue>(l => new StringValue(AmcSet(l))));
            AddSuffix("ASCMECOTAKE", new Suffix<ScalarValue>(() =>
            {
                if (amcPress > 0) { amcPress = 0; return ScalarValue.Create(1); }
                if (amcEarly > 0) { amcEarly--; return ScalarValue.Create(2); }
                return ScalarValue.Create(0);
            }));
            AddSuffix("ASCMECOSTATE", new Suffix<ListValue>(() =>
            {
                var l = new ListValue();
                l.Add(ScalarValue.Create(amcMode)); l.Add(new BooleanValue(amc.Limiting)); l.Add(ScalarValue.Create(amc.Cap));
                l.Add(ScalarValue.Create(amc.Allowed)); l.Add(ScalarValue.Create(amc.ANow)); l.Add(ScalarValue.Create(amcFinal));
                l.Add(ScalarValue.Create(amcLimitedTicks)); l.Add(new BooleanValue(amc.AtFloor)); l.Add(ScalarValue.Create(amc.ALimit));
                l.Add(new BooleanValue(amc.Gate));
                return l;
            }));
        }

        static string AmcSet(ListValue l)
        {
            try
            {
                if (l == null || l.Count < 1) return "error no mode";
                int m = (int)Math.Round(HoD(l[0]));
                if (m == 3)
                {
                    amcMode = 0; amcHaveBase = false; amcPress = 0; amcEarly = 0;
                    amc.Reset(); amc.ALimit = 3.0 * AscMecoCore.G0; amcLimitedTicks = 0; amcWasLimiting = false;
                    Debug.Log("[KalsAscMeco] reset: idle, limit " + (amc.ALimit / AscMecoCore.G0).ToString("F2") + " g");
                    return "";
                }
                if (m == 1)
                {
                    if (l.Count > 1)
                    {
                        double lim = HoD(l[1]);
                        if (lim > 5 && lim < 100) amc.ALimit = lim;
                    }
                    amc.Reset();
                    amcMode = 1;
                    Debug.Log("[KalsAscMeco] armed: limit " + amc.ALimit.ToString("F2") + " m/s2 (" + (amc.ALimit / AscMecoCore.G0).ToString("F2") + " g), floor "
                        + amc.Floor.ToString("F3"));
                    return "";
                }
                if (m == 0)
                {
                    if (amcMode != 2) Debug.Log("[KalsAscMeco] done (MECO): limiter and press off, " + amcLimitedTicks + " limited ticks");
                    amcMode = 2; amcPress = 0; amc.Reset(); amcWasLimiting = false;
                    return "";
                }
                if (m == 4)
                {
                    bool g = l.Count > 1 && HoD(l[1]) > 0.5;
                    if (g != amc.Gate) Debug.Log("[KalsAscMeco] gate " + (g ? "ON: the ascent guidance failed, the limiter may cut" : "OFF: the guidance is throttling, the limiter never cuts") + " (mode " + amcMode + ")");
                    amc.Gate = g;
                    return "";
                }
                return "error mode " + m;
            }
            catch (Exception ex) { return "error " + ex.Message; }
        }

        // engines that can matter: lit, not flamed out; refreshed every AMC_REFRESH s
        static void AmcEngines(Vessel v)
        {
            double now = Time.realtimeSinceStartup;
            if (v == amcVessel && now - amcRefreshT < AMC_REFRESH) return;
            amcVessel = v;
            amcRefreshT = now;
            amcEng.Clear();
            foreach (Part p in v.parts)
                foreach (PartModule pm in p.Modules)
                {
                    ModuleEngines e = pm as ModuleEngines;
                    if (e != null) amcEng.Add(e);
                }
        }

        // an engine on the vessel's main throttle that is running: the SSMEs here
        static bool AmcMain(ModuleEngines e) { return e != null && e.EngineIgnited && !e.flameout && !e.throttleLocked && !e.independentThrottle; }

        static bool AmcSsmeLit(Vessel v)
        {
            AmcEngines(v);
            foreach (ModuleEngines e in amcEng) if (AmcMain(e) && e.finalThrust > 0) return true;
            return false;
        }

        // every physics tick, the last thing of AfbwThrottle.Fin: the AG4 press, then the limiter on the final throttle
        internal static void AscMecoTick(Vessel v, FlightCtrlState s)
        {
            try
            {
                if (v == null || s == null) return;
                bool ag = v.ActionGroups[KSPActionGroup.Custom04];
                if (!amcHaveBase) { amcAg = ag; amcHaveBase = true; }
                else if (ag != amcAg)
                {
                    amcAg = ag;
                    if (amcMode == 0) { amcEarly++; Debug.Log("[KalsAscMeco] AG4 press before SRB sep (MET " + v.missionTime.ToString("F1") + "): not armed"); }
                    else if (amcMode == 1)
                    {
                        if (AmcSsmeLit(v)) { amcPress++; Debug.Log("[KalsAscMeco] AG4 press: manual MECO latched (MET " + v.missionTime.ToString("F1") + ")"); }
                        else Debug.Log("[KalsAscMeco] AG4 press with no SSME lit: ignored");
                    }
                }
                if (amcMode != 1) return;
                AmcEngines(v);
                double fMain = 0, fOther = 0, slope = 0, wThr = 0;
                foreach (ModuleEngines e in amcEng)
                {
                    if (e == null || !e.EngineIgnited || e.flameout) continue;
                    double ft = e.finalThrust;
                    if (!AmcMain(e)) { fOther += ft; continue; }
                    fMain += ft;
                    wThr += ft * e.currentThrottle;
                    double den = e.minThrust + (e.maxThrust - e.minThrust) * e.currentThrottle;
                    double span = e.maxThrust - e.minThrust;
                    slope += den > 1E-6 ? ft * span / den : span * e.thrustPercentage / 100.0;
                }
                double thrNow = fMain > 1E-6 ? wThr / fMain : s.mainThrottle;
                double dt = Time.fixedDeltaTime;
                double fin = amc.Step(s.mainThrottle, fMain, thrNow, slope, fOther, v.totalMass, dt);
                amcFinal = fin;
                if (amc.Limiting)
                {
                    amcLimitedTicks++;
                    if (!amcWasLimiting)
                        Debug.Log("[KalsAscMeco] limiting at MET " + v.missionTime.ToString("F1") + ": accel " + amc.ANow.ToString("F2") + " m/s2, command "
                            + s.mainThrottle.ToString("F3") + " -> " + fin.ToString("F3") + (amc.AtFloor ? " (AT THE FLOOR)" : ""));
                    s.mainThrottle = (float)fin;
                }
                else if (amcWasLimiting)
                    Debug.Log("[KalsAscMeco] limit released at MET " + v.missionTime.ToString("F1") + " after " + amcLimitedTicks + " limited ticks");
                amcWasLimiting = amc.Limiting;
            }
            catch (Exception ex) { Debug.Log("[KalsAscMeco] tick error: " + ex.GetType().Name + ": " + ex.Message); }
        }
    }
}
