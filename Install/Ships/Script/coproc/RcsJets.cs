// THE RCS JETS OF THE VESSEL: the part models' thrusters mapped to the real pods / manifolds / directions (RcsMap.cs, the pure part), and the
// HOLD that takes jets out of fire for the failures (FailEnforce.RcsPass):
//   HOW A JET IS TAKEN OUT: the lists are NEVER touched now. A held jet's thruster GameObject is
//   SetActive(false): ModuleRCS.FixedUpdate skips a thruster that is not activeInHierarchy (thrustForces[i] stays 0, no force, no FX power), and its plume
//   (a child of the thruster) is hidden. The list, thrustForces and the thrusterFX stay whole and in step, so Waterfall / the stock FX keep their indices.
//   RCS 01 manifold valves closed    the group's jets are held (inactive)
//   RCS 02 thrust low                a ModuleRCS has ONE thrust limit for all its jets and the pods share modules (the aft fuselage's 3 modules hold both
//                                    pods' 24 jets), so a pod / manifold cannot be capped by the module's limit: the group's jets are let fire on a duty
//                                    of the ticks (RcsMap.DutyStep: 50 % = every other physics tick, 75 % = three in four), the impulse the cap gives.
//                                    The duty is applied by a Harmony prefix on ModuleRCS.FixedUpdate (Pre), at the START of the module's tick: Hold
//                                    (FailVessel.FixedUpdate, no fixed order against the modules') switching the thruster AFTER the module's FixedUpdate cut
//                                    the plume of every firing tick before the render (FxOff + SetActive(false)): THRUST LOW jets showed no plume at all.
//   RCS 04 stuck off                 the one jet is held; stuck ON is FailEnforce.JetOn (the force ModuleRCS itself would apply)
// STATELESS: every tick each jet is made what the standing failures say; the jets WE deactivated are the set `deact` (a jet the model itself ships inactive is
// never touched), so a jet two entries hold (RCS 01 L MANIFOLD 3 + RCS 04 L3D stuck off) stays down until BOTH are gone, and a
// released failure gives its jets back.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    public sealed class RcsJets
    {
        public sealed class Jet
        {
            public char Pod, Dir;
            public int Man;
            public string Name;
            public Part Part;
            public ModuleRCS Mod;
            public int ModIdx, JetIdx;          // the part's n-th ModuleRCS, the place in its WHOLE list
            public Transform Tr;
        }

        readonly HashSet<Transform> deact = new HashSet<Transform>();       // the thrusters this class deactivated (to give back)
        readonly Dictionary<Transform, float> acc = new Dictionary<Transform, float>();
        readonly HashSet<Transform> off = new HashSet<Transform>();        // the jets the failures hold OFF now (not the duty's off ticks): what the page counts
        // The duty jets' word for the module's next tick (jet -> fires), applied by Pre() at the start of each ModuleRCS.FixedUpdate
        readonly Dictionary<Transform, bool> duty = new Dictionary<Transform, bool>();
        static readonly Dictionary<ModuleRCS, RcsJets> owner = new Dictionary<ModuleRCS, RcsJets>();
        static bool pfTried, pfOk;
        public static string PreError = "";
        List<Jet> jets = new List<Jet>();
        Vessel built;
        int builtParts = -1;
        public string MapText = "";

        public bool Active { get { return deact.Count > 0 || acc.Count > 0; } }

        // a module's whole list (the live list is always whole)
        static List<Transform> Full(ModuleRCS r)
        {
            return r.thrusterTransforms;
        }

        // the map of the vessel's jets (built once, again when its part count changes or it is another vessel)
        public List<Jet> Map(Vessel v)
        {
            if (v == null) return jets;
            if (built == v && builtParts == v.parts.Count) return jets;
            built = v; builtParts = v.parts.Count;
            jets = new List<Jet>();
            var parts = new List<Part>();
            bool shuttle = PayloadRcs.IsShuttle(v);                     // T1017: on a shuttle only the orbiter's own RCS parts make jets; a payload's thrusters are not the shuttle's
            foreach (Part p in v.parts)
            {
                if (PayloadRcs.IsPayload(shuttle, p)) continue;
                foreach (PartModule pm in p.Modules) if (pm is ModuleRCS) { parts.Add(p); break; }
            }
            parts.Sort((a, b) => a.flightID.CompareTo(b.flightID));
            Transform rt = v.ReferenceTransform;
            Vector3 com = v.CurrentCoM;
            var ins = new List<RcsJetIn>();
            foreach (Part p in parts)
            {
                bool fwd = PayloadRcs.IsFwdPart(shuttle, v, p);       // T1032: by the part's identity on a shuttle (a payload moves the c.g. aft of the aft fuselage's origin)
                int m = 0;
                foreach (PartModule pm in p.Modules)
                {
                    ModuleRCS r = pm as ModuleRCS;
                    if (r == null) continue;
                    List<Transform> f = Full(r);
                    for (int j = 0; j < f.Count; j++)
                    {
                        Transform t = f[j];
                        if (t == null) continue;
                        Vector3 d = r.useZaxis ? t.forward : t.up;          // the exhaust (the force on the ship is -d, FailEnforce.JetOn)
                        Vector3 pos = t.position - com;
                        var ji = new RcsJetIn();
                        ji.Fore = Vector3.Dot(pos, rt.up); ji.Top = Vector3.Dot(pos, -rt.forward); ji.Star = Vector3.Dot(pos, rt.right);
                        ji.DFore = Vector3.Dot(d, rt.up); ji.DTop = Vector3.Dot(d, -rt.forward); ji.DStar = Vector3.Dot(d, rt.right);
                        ji.PartKey = unchecked((int)p.flightID); ji.Module = m; ji.Jet = j; ji.Fwd = fwd;
                        ins.Add(ji);
                        var jt = new Jet(); jt.Part = p; jt.Mod = r; jt.ModIdx = m; jt.JetIdx = j; jt.Tr = t;
                        jets.Add(jt);
                    }
                    m++;
                }
            }
            RcsJetOut[] o = RcsMap.Deal(ins.ToArray());
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < o.Length; i++)
            {
                jets[i].Pod = o[i].Pod; jets[i].Man = o[i].Man; jets[i].Dir = o[i].Dir; jets[i].Name = o[i].Name;
                if (i < 200) sb.Append(o[i].Name).Append(" part ").Append(jets[i].Part.flightID.ToString(CultureInfo.InvariantCulture)).Append(" mod ").Append(jets[i].ModIdx).Append(" jet ").Append(jets[i].JetIdx)
                    .Append(" at (fore ").Append(ins[i].Fore.ToString("F2", CultureInfo.InvariantCulture)).Append(", top ").Append(ins[i].Top.ToString("F2", CultureInfo.InvariantCulture))
                    .Append(", star ").Append(ins[i].Star.ToString("F2", CultureInfo.InvariantCulture)).Append(") fires (").Append(ins[i].DFore.ToString("F2", CultureInfo.InvariantCulture)).Append(", ")
                    .Append(ins[i].DTop.ToString("F2", CultureInfo.InvariantCulture)).Append(", ").Append(ins[i].DStar.ToString("F2", CultureInfo.InvariantCulture)).Append("); ");
            }
            MapText = jets.Count + " jets: " + sb;
            if (jets.Count > 0) Debug.Log("[KalsFail] RCS jet map of " + v.vesselName + ": " + MapText);
            return jets;
        }

        // make the jets what the standing failures say: offNow = the jets held out (valves closed, stuck off), cap = a jet -> the fraction of the ticks it may
        // fire. Returns how many held jets had to be taken out this tick (the first tick of a hold).
        public int Hold(List<Jet> js, HashSet<Transform> offNow, Dictionary<Transform, float> cap)
        {
            int removed = 0;
            AudioGuard.Install();
            if (cap.Count > 0) InstallPrefix();
            off.Clear();
            duty.Clear();
            var dutyMods = new HashSet<ModuleRCS>();
            foreach (Transform t in offNow) off.Add(t);
            var mods = new List<ModuleRCS>();
            foreach (Jet j in js) if (j.Mod != null && !mods.Contains(j.Mod)) mods.Add(j.Mod);
            var seen = new HashSet<Transform>();
            foreach (ModuleRCS r in mods)
            {
                List<Transform> f = Full(r);
                if (f == null) continue;
                for (int ti = 0; ti < f.Count; ti++)
                {
                    Transform t = f[ti];
                    if (t == null) continue;
                    seen.Add(t);
                    bool hold = offNow.Contains(t);
                    float c;
                    if (!hold && cap.TryGetValue(t, out c))
                    {
                        float a;
                        acc.TryGetValue(t, out a);
                        bool on = RcsMap.DutyStep(ref a, c);
                        acc[t] = a;
                        if (pfOk) { duty[t] = on; dutyMods.Add(r); continue; }       // Pre() switches it at the start of the module's tick
                        if (!on) hold = true;                                         // (no prefix: the old switch after the module's tick, no plume)
                    }
                    GameObject go = t.gameObject;
                    if (hold)
                    {
                        if (go.activeSelf) { FxOff(r, ti); go.SetActive(false); deact.Add(t); if (offNow.Contains(t)) removed++; }
                    }
                    else if (deact.Remove(t)) go.SetActive(true);
                }
            }
            // a thruster we deactivated that is gone or no longer on a module of this vessel (a decoupled part): give it back / forget it
            foreach (Transform t in new List<Transform>(deact))
            {
                if (t == null) { deact.Remove(t); continue; }
                if (!seen.Contains(t)) { deact.Remove(t); t.gameObject.SetActive(true); }
            }
            foreach (Transform k in new List<Transform>(acc.Keys)) if (!cap.ContainsKey(k)) acc.Remove(k);
            foreach (ModuleRCS k in new List<ModuleRCS>(owner.Keys)) if (k == null || (owner[k] == this && !dutyMods.Contains(k))) owner.Remove(k);
            foreach (ModuleRCS k in dutyMods) owner[k] = this;
            return removed;
        }

        // THE DUTY AT THE START OF THE MODULE'S TICK. Harmony prefix on ModuleRCS.FixedUpdate (ModuleRCSFX too if it declares its own): the module's duty jets are
        // made what Hold said for this tick before the module reads its thrusters, so a firing jet is active when FixedUpdate sets the thrust, the force and the
        // plume, and stays so through the render; a jet off this tick has its FX zeroed (FxOff) and its thruster switched off, as before.
        static void InstallPrefix()
        {
            if (pfTried) return;
            pfTried = true;
            try
            {
                var h = new HarmonyLib.Harmony("kals.rcsduty");
                var pre = new HarmonyLib.HarmonyMethod(typeof(RcsJets).GetMethod("PreFixed", BindingFlags.Static | BindingFlags.NonPublic));
                int n = 0;
                foreach (Type ty in new Type[] { typeof(ModuleRCS), typeof(ModuleRCSFX) })
                {
                    MethodInfo mi = ty.GetMethod("FixedUpdate", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.DeclaredOnly);
                    if (mi == null) continue;
                    h.Patch(mi, prefix: pre);
                    n++;
                }
                if (n == 0) throw new Exception("no ModuleRCS.FixedUpdate");
                pfOk = true;
                Debug.Log("[KalsCoproc] T927 RCS duty prefix: " + n + " FixedUpdate method(s) patched (THRUST LOW switched at the start of the module's tick)");
            }
            catch (Exception ex) { PreError = ex.GetType().Name + ": " + ex.Message; Debug.Log("[KalsCoproc] T927 RCS duty prefix not installed: " + PreError + " (THRUST LOW by the old Hold switch, no plume)"); }
        }

        static void PreFixed(ModuleRCS __instance)
        {
            try
            {
                RcsJets o;
                if (__instance != null && owner.TryGetValue(__instance, out o)) o.Pre(__instance);
            }
            catch { }
        }

        void Pre(ModuleRCS r)
        {
            List<Transform> f = Full(r);
            if (f == null) return;
            for (int ti = 0; ti < f.Count; ti++)
            {
                Transform t = f[ti];
                bool fire;
                if (t == null || !duty.TryGetValue(t, out fire)) continue;
                GameObject go = t.gameObject;
                int d = RcsMap.DutyDecide(fire, go.activeSelf, deact.Contains(t));
                if (d == RcsMap.DutyOff) { FxOff(r, ti); go.SetActive(false); deact.Add(t); }
                else if (d == RcsMap.DutyOn) { deact.Remove(t); go.SetActive(true); }
            }
        }

        // ModuleRCS.FixedUpdate SKIPS a thruster that is not activeInHierarchy (no UpdatePowerFX for it), so the running sound's per-jet volume
        // (AudioMultiPooledFX.volumes[idx]) stays at whatever the jet last fired at. A module whose jets are all held then has stale volumes > 0 and
        // no active modelParent: the next DeactivateFX (RCS input 0) makes Play borrow a pooled source under an inactive parent, the source's CheckEnd
        // coroutine releases it INSIDE BorrowAndPlay (isPlaying false), and Play then stores the already released source in FX.source; every later
        // StopAndRelease runs Reset on it again, whose onRelease.Invoke() is null (KSPCommunityFixes nulls it after each Reset): a
        // NullReferenceException per module per physics tick. So the jet's sound and plume go to
        // power 0 while its thruster is still active (the effect finds its active parent), then the thruster is switched off.
        static void FxOff(ModuleRCS r, int idx)
        {
            try
            {
                ModuleRCSFX fx = r as ModuleRCSFX;
                if (fx != null && r.part != null && !string.IsNullOrEmpty(fx.runningEffectName)) r.part.Effect(fx.runningEffectName, 0f, idx);
                if (r.thrusterFX != null && idx >= 0 && idx < r.thrusterFX.Count && r.thrusterFX[idx] != null)
                {
                    r.thrusterFX[idx].setActive(false);
                    r.thrusterFX[idx].Power = 0f;
                }
            }
            catch (Exception ex) { Debug.Log("[KalsFail] RCS jet FX not zeroed: " + ex.GetType().Name + ": " + ex.Message); }
        }

        // the pods' jets: LIST of (total, working) for F, L, R: working = not held out by a failure and its module's RCS switched on
        public int[] Counts(Vessel v)
        {
            var c = new int[6];
            foreach (Jet j in Map(v))
            {
                int k = j.Pod == 'F' ? 0 : (j.Pod == 'L' ? 1 : 2);
                c[2 * k]++;
                if (!off.Contains(j.Tr) && j.Mod != null && j.Mod.rcsEnabled) c[2 * k + 1]++;
            }
            return c;
        }

        // the jets of a part in the pod(s) a leak names / all the part's jets
        public int PartJets(Vessel v, Part p, List<RcsGroup> gs)
        {
            int n = 0;
            foreach (Jet j in Map(v)) if (j.Part == p && (gs == null || RcsMap.InGroups(gs, j.Pod, j.Man))) n++;
            return n;
        }
    }
}
