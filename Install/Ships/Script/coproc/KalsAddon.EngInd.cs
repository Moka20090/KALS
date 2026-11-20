// The OMS engines in an OMS dump fire at 100 % thrust whatever the SSME throttle, and the throttle shows the SSMEs':
// KSP 1.12's own independent throttle (ModuleEngines.independentThrottle / independentThrottlePercentage: UpdateThrottle
// then reads the engine's percentage instead of the vessel's main throttle; the part menu's "Throttle: Independent" under
// advanced tweakables). kOS 1.6 has no suffix for it and both fields are named "Throttle" in the menu, so SETFIELD cannot
// tell them apart. The vessel's throttle stays the SSMEs' command (the gauge shows it), the OMS engines fly their own.
//     ADDONS:KALS:ENGIND(sub, pct)   pct >= 0: every engine module of shared.Vessel's parts whose name contains sub flies
//                                    its own throttle at pct (0..100) from now; pct < 0: those engines back on the vessel's
//                                    throttle. Returns how many engine modules were set.
// A watchdog: an independent engine fires whatever the vessel's throttle says, so if the script stops calling (an error,
// a reboot) the engines go back to the vessel's throttle 0.5 s after the last call with pct >= 0 (the vessel's fly-by-wire
// handler checks each physics frame; KSP.log says so). The caller repeats its call every tick while it wants them.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        static readonly List<ModuleEngines> eiMods = new List<ModuleEngines>();
        static Vessel eiVessel;
        static double eiT = -1E9;

        partial void RegisterEngInd()
        {
            AddSuffix("ENGIND", new TwoArgsSuffix<ScalarValue, StringValue, ScalarValue>((s, p) =>
                ScalarValue.Create(EiSet(shared.Vessel, s.ToString(), p.GetDoubleValue()))));
            // ops2q's OMS interlock heartbeat (OmsHold.cs; the final-throttle zero runs in AfbwThrottle.Fin)
            AddSuffix("OMSHOLD", new OneArgsSuffix<BooleanValue, BooleanValue>(a => new BooleanValue(OmsHold.Set(a))));
            AddSuffix("OMSHOLDOFF", new Suffix<BooleanValue>(() => new BooleanValue(OmsHold.Off())));
        }

        static int EiSet(Vessel v, string sub, double pct)
        {
            if (v == null || string.IsNullOrEmpty(sub)) return 0;
            if (double.IsNaN(pct) || double.IsInfinity(pct)) pct = -1;
            if (pct < 0) return EiOff("off");
            float f = (float)Math.Min(100, pct);
            if (eiVessel != null && eiVessel != v) EiOff("vessel changed");
            int n = 0;
            foreach (Part p in v.parts)
            {
                if (p.name == null || p.name.IndexOf(sub, StringComparison.Ordinal) < 0) continue;
                foreach (PartModule m in p.Modules)
                {
                    ModuleEngines e = m as ModuleEngines;
                    if (e == null || e.throttleLocked) continue;
                    if (!e.independentThrottle) Debug.Log("[KalsCoproc] ENGIND: " + p.name + " on its own throttle at " + f + " %");
                    e.independentThrottle = true;
                    e.independentThrottlePercentage = f;
                    if (!eiMods.Contains(e)) eiMods.Add(e);
                    n++;
                }
            }
            eiT = Planetarium.GetUniversalTime();
            v.OnFlyByWire -= EiFbw;
            v.OnFlyByWire += EiFbw;
            eiVessel = v;
            return n;
        }

        static int EiOff(string why)
        {
            int n = 0;
            foreach (ModuleEngines e in eiMods)
            {
                if (e == null) continue;
                e.independentThrottle = false;
                n++;
            }
            if (n > 0) Debug.Log("[KalsCoproc] ENGIND: " + n + " engine(s) back on the vessel's throttle (" + why + ")");
            eiMods.Clear();
            if (eiVessel != null) eiVessel.OnFlyByWire -= EiFbw;
            eiVessel = null;
            return n;
        }

        static void EiFbw(FlightCtrlState st)
        {
            if (Planetarium.GetUniversalTime() - eiT > 0.5) EiOff("no call for 0.5 s");
        }
    }
}
