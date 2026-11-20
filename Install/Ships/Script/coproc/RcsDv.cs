// The RCS jets' velocity change on the active vessel, summed every physics tick, so the entry's measured drag (lib_vehicle
// fdSample: the change in orbital velocity over a window, less gravity) can take the jets' push out of what it calls aero.
// Each tick: for every ModuleRCS (ModuleRCSFX too) on the vessel that is enabled and not just for show, each thruster's
// force as ModuleRCS.FixedUpdate applies it (IL-read: Part.AddForceAtPosition(-(useZaxis ? forward : up) x
// thrustForces[i]), kN on a vessel in tonnes), / the vessel's mass x the tick. The sum is a world-axes vector, the axes kOS
// hands its vectors in; a window's part is the difference of two readings, so the frame's turn below the inverse-rotation
// altitude (w dt ~ 1e-4 rad per second) is far below the jets' own scatter. thrustForces is the tick's own value or the
// last tick's, whichever ran first: one tick at each end of a window.
//     ADDONS:KALS:RCSDV      LIST(x, y, z, ticks): the sum so far (m/s), and the physics ticks it covers; it restarts
//                            from 0 on another active vessel
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class RcsDv : MonoBehaviour
    {
        internal static Vector3d Sum;
        internal static int Ticks;
        static Vessel sumVessel;

        void FixedUpdate()
        {
            Vessel v = FlightGlobals.ActiveVessel;
            if (v == null || v.packed) return;
            if (v != sumVessel) { sumVessel = v; Sum = Vector3d.zero; Ticks = 0; }
            double m = v.totalMass;
            if (m <= 0) return;
            Vector3d f = Vector3d.zero;
            List<ModuleRCS> rcs = v.FindPartModulesImplementing<ModuleRCS>();
            for (int k = 0; k < rcs.Count; k++)
            {
                ModuleRCS r = rcs[k];
                if (r == null || !r.moduleIsEnabled || r.isJustForShow || r.thrustForces == null || r.thrusterTransforms == null) continue;
                int n = Mathf.Min(r.thrustForces.Length, r.thrusterTransforms.Count);
                for (int i = 0; i < n; i++)
                {
                    float t = r.thrustForces[i];
                    Transform x = r.thrusterTransforms[i];
                    if (t <= 0 || x == null) continue;
                    f -= (Vector3d)((r.useZaxis ? x.forward : x.up) * t);
                }
            }
            Sum += f * (TimeWarp.fixedDeltaTime / m);
            Ticks++;
        }
    }

    public partial class KalsAddon
    {
        partial void RegisterRcsDv()
        {
            AddSuffix("RCSDV", new Suffix<ListValue>(() =>
            {
                var l = new ListValue();
                l.Add(ScalarValue.Create(RcsDv.Sum.x));
                l.Add(ScalarValue.Create(RcsDv.Sum.y));
                l.Add(ScalarValue.Create(RcsDv.Sum.z));
                l.Add(ScalarValue.Create(RcsDv.Ticks));
                return l;
            }));
        }
    }
}
