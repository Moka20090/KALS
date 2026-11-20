// PAYLOAD RCS.
//   DETECT   The orbiter's own RCS is on its forward and aft fuselage parts only (benjee10_shuttle_forwardFuselage / _aftFuselage; the rule kOS's o2qPodScan /
//            cwsScan use, RcsMap.IsOrbiterRcsName). A vessel is the SHUTTLE when one of those parts is on it; on a shuttle vessel every OTHER part with a
//            ModuleRCS is PAYLOAD RCS (a satellite's thrusters in the bay, on the arm, docked). A vessel with no orbiter fuselage (the payload flying alone, any
//            other craft) has no payload RCS: nothing is detected, nothing is touched.
//   EXCLUDE  RcsJets.Map leaves a payload part out (so the jet counts RCSPOD / RCS JET, the failure groups, the C# DAP's lists see the orbiter's jets only);
//            the gimbal-mode scan (O2dGmScan) and the yaw-jet code (YawJet) skip it through the same IsPayload.
//   DISABLE  Tick (FailVessel.FixedUpdate, every loaded vessel): while a payload ModuleRCS is on the shuttle's vessel its rcsEnabled is held FALSE (a crew PAW
//            toggle is undone the next tick); the module's own state is saved first and given back as soon as the part is no longer on a shuttle vessel (released,
//            undocked, deployed: the part's new vessel has no orbiter fuselage, so its Tick finds the module in `saved` and restores it). A payload that is its own
//            vessel is never touched.
//   TRAP     The disabled state is what a save holds: a scene load with the payload still in the bay finds rcsEnabled FALSE and no `saved` entry. SavedEnable
//            then gives back the part PREFAB's own state (true for the stock RCS parts), so a payload saved in the bay never comes back dead (a deliberate "off" the
//            crew set BEFORE docking is lost across a save / load, said plainly). Waterfall's thruster indices are never touched: only the module's switch.
using System;
using System.Collections.Generic;
using UnityEngine;

namespace KalsCoproc
{
    public sealed class PayloadRcs
    {
        // modules we switched off -> the state to give back
        static readonly Dictionary<ModuleRCS, bool> saved = new Dictionary<ModuleRCS, bool>();

        // the orbiter's own RCS part: the forward / aft fuselage (partInfo.name, the kOS rule)
        public static bool IsOrbiterPart(Part p)
        {
            if (p == null) return false;
            string n = p.partInfo != null ? p.partInfo.name : p.name;
            return RcsMap.IsOrbiterRcsName(n);
        }

        // T1032: the part's pod side on a vessel (shuttle = IsShuttle(v), said once by the caller): by identity on a shuttle, by the c.g. otherwise
        public static bool IsFwdPart(bool shuttle, Vessel v, Part p)
        {
            string n = p.partInfo != null ? p.partInfo.name : p.name;
            return RcsMap.PodIsFwd(shuttle, n, !shuttle && FailEnforce.IsFwd(v, p));
        }

        static bool HasRcs(Part p)
        {
            foreach (PartModule pm in p.Modules) if (pm is ModuleRCS) return true;
            return false;
        }

        // a SHUTTLE vessel: one of the orbiter's fuselage parts (with its RCS) is on it
        public static bool IsShuttle(Vessel v)
        {
            if (v == null || v.parts == null) return false;
            foreach (Part p in v.parts) if (IsOrbiterPart(p) && HasRcs(p)) return true;
            return false;
        }

        // payload RCS: a part with a ModuleRCS that is not the orbiter's own, on a vessel that IS a shuttle. shuttle = IsShuttle(v), said once by the caller.
        public static bool IsPayload(bool shuttle, Part p)
        {
            return shuttle && p != null && !IsOrbiterPart(p) && HasRcs(p);
        }

        // the same, one call (the callers that scan every 100 ticks or once: O2dGmScan, YawJet)
        public static bool IsPayload(Vessel v, Part p)
        {
            return p != null && !IsOrbiterPart(p) && HasRcs(p) && IsShuttle(v);
        }

        // ---------------------------------------------------------------- per vessel (one instance in each FailVessel)
        Vessel built;
        int builtParts = -1, age;
        readonly List<ModuleRCS> held = new List<ModuleRCS>();         // the payload modules of this vessel (a shuttle's)
        public int Count { get { return held.Count; } }
        public string Names = "";

        public static bool PrefabEnable(ModuleRCS m)
        {
            try
            {
                Part pf = m.part.partInfo != null ? m.part.partInfo.partPrefab : null;
                if (pf == null) return true;
                int idx = 0;
                foreach (PartModule pm in m.part.Modules)
                {
                    if (pm is ModuleRCS) { if (pm == m) break; idx++; }
                }
                int i = 0;
                foreach (PartModule pm in pf.Modules)
                {
                    ModuleRCS r = pm as ModuleRCS;
                    if (r == null) continue;
                    if (i == idx) return r.rcsEnabled;
                    i++;
                }
            }
            catch (Exception) { }
            return true;
        }

        // the payload modules on this vessel, the modules we still hold off that are NOT payload here any more given back
        void Rescan(Vessel v)
        {
            built = v; builtParts = v.parts.Count; age = 0;
            held.Clear();
            bool shuttle = IsShuttle(v);
            var names = new System.Text.StringBuilder();
            foreach (Part p in v.parts)
                foreach (PartModule pm in p.Modules)
                {
                    ModuleRCS r = pm as ModuleRCS;
                    if (r == null) continue;
                    if (IsPayload(shuttle, p)) { held.Add(r); if (names.Length > 0) names.Append(", "); names.Append(p.partInfo != null ? p.partInfo.name : p.name); }
                    else
                    {
                        bool s;
                        if (saved.TryGetValue(r, out s)) { r.rcsEnabled = s; saved.Remove(r); FailVessel.Log("payload RCS back: " + (p.partInfo != null ? p.partInfo.name : p.name) + " (RCS " + (s ? "on" : "off") + ") on " + v.vesselName); }
                    }
                }
            foreach (ModuleRCS k in new List<ModuleRCS>(saved.Keys)) if (k == null) saved.Remove(k);       // a destroyed module: forget it
            string nm = names.ToString();
            if (nm != Names)
            {
                Names = nm;
                if (held.Count > 0) FailVessel.Log("payload RCS held off on " + v.vesselName + ": " + held.Count + " module(s): " + nm);
            }
        }

        public void Tick(Vessel v)
        {
            if (v == null || !v.loaded || v.parts == null) return;
            if (built != v || builtParts != v.parts.Count || ++age >= 100) Rescan(v);
            for (int i = 0; i < held.Count; i++)
            {
                ModuleRCS r = held[i];
                if (r == null) continue;
                if (!saved.ContainsKey(r)) saved[r] = RcsMap.SavedEnable(r.rcsEnabled, PrefabEnable(r));
                if (r.rcsEnabled) r.rcsEnabled = false;
            }
        }
    }
}
