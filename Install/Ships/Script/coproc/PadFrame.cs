// The launch platform and the moving frame. KSP's Krakensbane.SafeToEngage holds the velocity frame, and FloatingOrigin
// with it (its out flag), while any other loaded vessel is landed or below altThreshold radar altitude. The platform the
// launch clamps leave behind is such a vessel: KSP packs it at 350 m (MET ~10.5) but it stays loaded until it unloads
// 2.5 km away (MET ~27, near max q), and the frame then changes in one tick (~185 m/s and 2.5 km), which swings the tail
// parts. This addon leaves that platform out of the check while it is packed, so the frame can engage from the pack on,
// at a fraction of the q. Every other vessel, and the platform whenever it is unpacked, count as in stock.
// How: a Harmony prefix on SafeToEngage. While the packed platform is loaded it runs SafeToEngage's own code (KSP 1.12.5's
// IL) with that one vessel skipped and the original is not called; at any other time the original runs untouched. The
// platform is the vessel holding a part that sat in a launch clamp's subtree of the vessel on the pad (by persistentId).
// Without Harmony nothing is patched (the patch call is the only code that names Harmony's types). Every line in KSP.log
// starts with [KalsPadFrame].
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class PadFrame : MonoBehaviour
    {
        static bool tried;                                  // the patch was attempted (once per game)
        static readonly HashSet<uint> padParts = new HashSet<uint>();   // persistentIds of the clamps' subtrees on the pad
        static Vessel stack, pad;                           // the vessel on the pad; the platform once it is a vessel of its own
        static bool saidPacked, saidFree;

        static void Log(string s) { Debug.Log("[KalsPadFrame] " + s); }

        void Start()
        {
            padParts.Clear();
            stack = pad = null;
            saidPacked = saidFree = false;
            if (tried) return;
            tried = true;
            try { Patch(); Log("Krakensbane.SafeToEngage patched: a packed launch platform does not hold the frame"); }
            catch (Exception ex) { Log("not patched (stock frame hold): " + ex.GetType().Name + ": " + ex.Message); }
        }

        static void Patch()
        {
            MethodInfo m = typeof(Krakensbane).GetMethod("SafeToEngage", BindingFlags.Instance | BindingFlags.Public);
            MethodInfo pre = typeof(PadFrame).GetMethod("Prefix", BindingFlags.Static | BindingFlags.NonPublic);
            if (m == null || pre == null) throw new Exception("SafeToEngage or the prefix not found");
            new HarmonyLib.Harmony("kals.padframe").Patch(m, prefix: new HarmonyLib.HarmonyMethod(pre));
        }

        static void Subtree(Part p, HashSet<uint> into)
        {
            into.Add(p.persistentId);
            foreach (Part c in p.children) Subtree(c, into);
        }

        static bool HasPadPart(Vessel ves)
        {
            foreach (Part p in ves.parts) if (padParts.Contains(p.persistentId)) return true;
            return false;
        }

        void FixedUpdate()
        {
            Vessel a = FlightGlobals.ActiveVessel;
            if (a == null) return;
            if (a.situation == Vessel.Situations.PRELAUNCH && a != stack)
            {
                // the vessel on the pad: its clamps' subtrees (once per vessel)
                stack = a;
                padParts.Clear();
                foreach (Part p in a.parts)
                    foreach (PartModule pm in p.Modules)
                        if (pm is LaunchClamp) { Subtree(p, padParts); break; }
                if (padParts.Count > 0) Log(string.Format("{0}: {1} parts in its launch clamps' subtrees", a.vesselName, padParts.Count));
            }
            if (pad == null && padParts.Count > 0 && a == stack && a.situation != Vessel.Situations.PRELAUNCH)
                foreach (Vessel o in FlightGlobals.VesselsLoaded)
                    if (o != a && HasPadPart(o)) { pad = o; Log(string.Format("platform: {0} ({1} parts) at MET {2:F2}", o.vesselName, o.parts.Count, a.missionTime)); break; }
        }

        // Krakensbane.SafeToEngage (KSP 1.12.5) with the packed platform left out of the loaded-vessel loop; the original
        // whenever that platform is not loaded and packed or the vessel flying is not the one that left the pad
        static bool Prefix(Krakensbane __instance, ref bool __result, ref bool safeForFloatingOrigin, ref int ___loadedVesselsCount)
        {
            try
            {
                Vessel act = FlightGlobals.ActiveVessel;
                if (pad == null || act == null || act != stack || !pad.loaded || !pad.packed) return true;
                List<Vessel> vl = FlightGlobals.VesselsLoaded;
                safeForFloatingOrigin = false;
                ___loadedVesselsCount = vl.Count;
                if (act.state == Vessel.State.DEAD) { __result = false; return false; }
                safeForFloatingOrigin = true;
                for (int i = ___loadedVesselsCount; i-- > 0;)
                {
                    Vessel o = vl[i];
                    if (o != act && o != pad && (o.LandedOrSplashed || o.radarAltitude < __instance.altThreshold))
                    {
                        safeForFloatingOrigin = false;
                        __result = false;
                        return false;
                    }
                }
                if (!saidPacked)
                {
                    saidPacked = true;
                    Log(string.Format("platform packed and left out at MET {0:F2}: radar alt {1:F0} m, {2:F1} m/s, q {3:F2} kPa, {4:F0} m away",
                        act.missionTime, act.radarAltitude, act.srfSpeed, act.dynamicPressurekPa, (pad.GetWorldPos3D() - act.GetWorldPos3D()).magnitude));
                }
                if (act.LandedOrSplashed) { __result = false; return false; }
                double h = act.radarAltitude - __instance.extraAltOffsetForVel;
                if (Vector3d.Dot(act.velocityD, -act.upAxis) * Time.fixedDeltaTime > h) { __result = false; return false; }
                __result = !(h < (___loadedVesselsCount > 1 ? __instance.altThreshold : __instance.altThresholdAlone));
                if (__result && !saidFree)
                {
                    saidFree = true;
                    Log(string.Format("frame free with the platform loaded at MET {0:F2}: radar alt {1:F0} m, {2:F1} m/s, q {3:F2} kPa (Krakensbane MaxV {4:F0} m/s)",
                        act.missionTime, act.radarAltitude, act.srfSpeed, act.dynamicPressurekPa, __instance.MaxV));
                }
                return false;
            }
            catch (Exception) { return true; }
        }
    }
}
