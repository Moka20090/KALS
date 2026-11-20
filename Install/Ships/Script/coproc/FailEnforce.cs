// THE FAILURES ACT ON THE PARTS. FailVessel calls Apply every FixedUpdate of a loaded vessel:
// each failure in the list that is bound to parts (FailState.Bind: the kOS side says which engine / jets / surface it failed) is
// held on those parts, AFTER whatever the PAW, an action group, staging or a script just did to them. A script cannot undo what the
// DLL holds: it writes, the next tick writes back, and the write-back is counted (FailEntry.Corrections: the spike's "it holds").
//   MPS 01 / OMS 01   engine OUT        every ModuleEngines of the part: Shutdown() when it burns, allowRestart false, Activate / Shutdown
//                                       events and the activation actions hidden
//   MPS 02 / OMS 02   engine THRUST LOW thrustPercentage clamped to the value ("60 %"), the PAW slider hidden
//   MPS 03 / OMS 03   gimbal LOCKED     ModuleGimbal.gimbalLock true while the engine burns (an engine that is not burning is left to the
//                                       programs: the entry's stick reads an OMS gimbal and must see it move), the lock / limiter hidden
//   RCS 01            manifold valves   the jets of a POD (F / L / R) or one MANIFOLD of a pod are held out (the thruster GameObjects SetActive(false), the module lists stay whole; RcsJets.cs, RcsMap.cs: the real
//                                       Shuttle's pods and manifolds, jet names F3U / L2D / R4R; the old FWD / AFT targets are retired)
//   RCS 02            THRUST LOW        the same groups, the jets let fire on a duty of the physics ticks (50 % / 75 %): a ModuleRCS has one thrust limit for
//                                       all its jets and the pods share modules
//   FCS 01            surface FROZEN    FAR (reflection; FerramAerospaceResearch is never referenced): pitch / yaw / roll gains 0 and the flap
//                                       level held at what it was when the freeze began; stock ModuleControlSurface: the three ignore flags
//                                       true and the deploy angle held
//   OMS 04 / RCS 03   propellant LEAK   the tank parts' resource drained by the UT that passed (warp-proof): OMS 04 kg/s of LiquidFuel (FU) / Oxidizer (OX) / both from the
//                                       parts holding the OMS propellant, RCS 03 %/min of the MonoPropellant of the pod's part (the pod F / L / R; the aft part's one tank serves both pods, so a pod leaks its share of it)
//   RCS 04            SINGLE JET        one jet by its real name (F3U ...): STUCK OFF = its thruster GameObject inactive (active again on release),
//                                       STUCK ON = the force ModuleRCS itself would apply at full thrust (-(useZaxis ? forward : up) x thrusterPower x thrust %, Part.AddForceAtPosition)
//                                       and the monopropellant it burns. The LEAK value is gone (RCS 03 is the RCS leak).
//   OMS 04 / RCS 03 are bound by the DLL itself (SelfBind: the kOS side registers a handler so the code is flyable, it names no part): the parts resolved from the vessel at the first tick.
//   RCS 01 / 02 / 04 name no part at all (RcsPass: the jets come from the vessel's map every tick).
// NOT here (FCS 02 and PDR 01 are no longer in the catalog): the software and GPC
// failures (no part acts). A failure whose entry goes (a fix's timer ends, the latched flight ends) is released: what this file hid is shown
// again and allowRestart is put back; a limit it clamped stays where it was clamped (nothing to give back: the program sets it).
// Untested in the game until the spike (tests/fail_spike.ks); every KSP member used here is checked by the compile only.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    public sealed class FailEnforce
    {
        // one failure's give-backs: the objects it touched (once each) and what restores them
        sealed class Slot
        {
            public readonly List<Action> Undo = new List<Action>();
            public readonly List<object> Objs = new List<object>();
            readonly HashSet<object> all;
            public Slot(HashSet<object> a) { all = a; }
            public bool First(object o) { if (!all.Add(o)) return false; Objs.Add(o); return true; }
            public void Free() { foreach (object o in Objs) all.Remove(o); Objs.Clear(); }
        }
        readonly Dictionary<string, Slot> undo = new Dictionary<string, Slot>();                    // "code|target" -> its give-backs
        readonly HashSet<object> touched = new HashSet<object>();                                  // every object some Slot has touched
        readonly HashSet<string> seen = new HashSet<string>();
        readonly List<string> gone = new List<string>();
        readonly Dictionary<string, Part> partCache = new Dictionary<string, Part>();
        readonly Dictionary<PartModule, bool> heldDep = new Dictionary<PartModule, bool>();         // frozen stock surfaces: the deploy state at the freeze
        readonly Dictionary<PartModule, float> held = new Dictionary<PartModule, float>();         // frozen surfaces: the flap level / deploy angle at the freeze
        readonly HashSet<string> logged = new HashSet<string>();
        // The leaks' clocks (UT of the last drain per entry), the self-bind retry times, a jet's resolved transform, the leaks' running totals
        readonly Dictionary<string, double> lastUt = new Dictionary<string, double>();
        readonly Dictionary<string, double> nextBind = new Dictionary<string, double>();
        readonly RcsJets rcs = new RcsJets();                                                      // The jet map and the lists' hold
        public RcsJets Rcs { get { return rcs; } }
        readonly HashSet<string> rcsPrev = new HashSet<string>();                                  // the RCS 01 / 02 / 04 entries held last tick (for the "released" line)
        readonly Dictionary<string, double> drained = new Dictionary<string, double>();
        readonly Dictionary<string, double> drainLogAt = new Dictionary<string, double>();
        readonly Dictionary<string, float> jetLogAt = new Dictionary<string, float>();           // real time of a jet's last FAIL ON log line (1 per second)
        double curDt;                  // s of UT since this entry's last drain (0 for the entries that are not leaks, and the first time one is seen)
        int curN = 1;                  // how many parts the current entry is bound to

        // FAR's control surface, by reflection (the DLL serves both installs; the stock tree has no such type)
        static bool farInit;
        static FieldInfo fPitch, fYaw, fRoll, fFlap;
        static void FarInit(Type t)
        {
            if (farInit) return;
            farInit = true;
            try
            {
                BindingFlags bf = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
                fPitch = t.GetField("pitchaxis", bf); fYaw = t.GetField("yawaxis", bf); fRoll = t.GetField("rollaxis", bf);
                fFlap = t.GetField("flapDeflectionLevel", bf);
            }
            catch (Exception) { }
        }

        static void Log(string s) { Debug.Log("[KalsFail] " + s); }

        // ---- the entry point
        public void Apply(Vessel v, FailState st)
        {
            if (v == null || st == null) return;
            seen.Clear();
            for (int i = 0; i < st.List.Count; i++)
            {
                FailEntry e = st.List[i];
                if (e.Parts.Length == 0 && SelfBound(e.Code)) SelfBind(v, st, e);
                if (e.Parts.Length == 0) { e.Found = 0; continue; }
                string key = e.Code + "|" + e.Target;
                seen.Add(key);
                curDt = IsLeak(e) ? LeakDt(key) : 0;
                Slot u;
                if (!undo.TryGetValue(key, out u)) { u = new Slot(touched); undo[key] = u; }
                int found = 0;
                string[] tk = e.Tokens();
                curN = tk.Length;
                for (int k = 0; k < tk.Length; k++)
                {
                    string t = tk[k];
                    int q = t.IndexOf(':');
                    string uid = q < 0 ? t : t.Substring(0, q);
                    int mod = q < 0 ? -1 : ParseInt(t.Substring(q + 1));
                    Part p = FindPart(v, uid);
                    if (p == null) continue;
                    found++;
                    try { One(e, p, mod, u); }
                    catch (Exception ex) { LogOnce("hold " + key + " failed: " + ex.Message); }
                }
                e.Found = found;
                if (found == 0) LogOnce("no part of " + key + " on the vessel (" + e.Parts + ")");
            }
            if (undo.Count > seen.Count || NotAllSeen()) Release();
            try { RcsPass(v, st); }
            catch (Exception ex) { LogOnce("rcs hold failed: " + ex.Message); }
        }

        bool NotAllSeen()
        {
            foreach (string k in undo.Keys) if (!seen.Contains(k)) return true;
            return false;
        }

        // give back what entries that are gone had hidden
        void Release()
        {
            gone.Clear();
            foreach (string k in undo.Keys) if (!seen.Contains(k)) gone.Add(k);
            foreach (string k in gone)
            {
                Slot sl = undo[k];
                foreach (Action a in sl.Undo) { try { a(); } catch (Exception) { } }
                sl.Free();
                undo.Remove(k);
                lastUt.Remove(k); nextBind.Remove(k); drained.Remove(k); drainLogAt.Remove(k); jetLogAt.Remove(k);
                Log("released " + k);
            }
        }

        void LogOnce(string s) { if (logged.Add(s)) Log(s); }

        static int ParseInt(string s)
        {
            int v;
            return int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : -1;
        }

        // kOS's Part:UID is the part's flightID; persistentId is accepted too (as KalsAddon.OmsLine.cs does)
        Part FindPart(Vessel v, string uid)
        {
            Part p;
            if (partCache.TryGetValue(uid, out p) && p != null && p.vessel == v) return p;
            p = null;
            foreach (Part q in v.parts)
                if (q.flightID.ToString(CultureInfo.InvariantCulture) == uid || q.persistentId.ToString(CultureInfo.InvariantCulture) == uid) { p = q; break; }
            if (p == null) partCache.Remove(uid); else partCache[uid] = p;
            return p;
        }

        // ---- the hiding helpers: set it every tick (the game re-shows its own items), record the give-back once
        void HideField(BaseFieldList fl, string name, Slot u)
        {
            BaseField f = fl[name];
            if (f == null) return;
            if (u.First(f)) { bool g = f.guiActive, ge = f.guiActiveEditor; u.Undo.Add(() => { f.guiActive = g; f.guiActiveEditor = ge; }); }
            f.guiActive = false; f.guiActiveEditor = false;
        }
        void HideEvent(BaseEventList el, string name, Slot u)
        {
            BaseEvent b = el[name];
            if (b == null) return;
            if (u.First(b)) { bool a = b.active; u.Undo.Add(() => { b.active = a; }); }
            b.active = false;
        }
        void HideAction(BaseActionList al, string name, Slot u)
        {
            BaseAction b = al[name];
            if (b == null) return;
            if (u.First(b)) { bool a = b.active; u.Undo.Add(() => { b.active = a; }); }
            b.active = false;
        }

        // ---- one part, one failure
        void One(FailEntry e, Part p, int mod, Slot u)
        {
            switch (e.Code)
            {
                case "MPS 01": case "OMS 01": EngOut(e, p, u); break;
                case "MPS 02": case "OMS 02": EngCap(e, p, u); break;
                case "MPS 03": case "OMS 03": EngLock(e, p, u); break;
                case "FCS 01": Freeze(e, p, mod, u); break;
                case "OMS 04": OmsLeak(e, p); break;
                case "RCS 03": PctLeak(e, p, FailLeak.PctPerMin(e.Code, e.Value) * PodShare(e, p)); break;
            }
        }

        // ================================================================ THE LEAKS AND THE SINGLE JET
        static bool SelfBound(string code) { return code == "OMS 04" || code == "RCS 03"; }
        static bool IsLeak(FailEntry e) { return e.Code == "OMS 04" || e.Code == "RCS 03"; }
        static string Uid(Part q) { return q.flightID.ToString(CultureInfo.InvariantCulture); }
        static bool HasRcs(Part q) { foreach (PartModule pm in q.Modules) if (pm is ModuleRCS) return true; return false; }

        // the UT the entry's clock has run since the last drain (0 the first time, 0 for a clock that stepped back); the leak keeps running through a warp
        double LeakDt(string key)
        {
            double ut = Planetarium.GetUniversalTime(), last;
            double dt = lastUt.TryGetValue(key, out last) ? ut - last : 0;
            lastUt[key] = ut;
            return dt > 0 ? dt : 0;
        }

        // A vector on the ship's own axes, the kOS ones (SHIP:FACING: fore = ReferenceTransform.up, top = -forward, star = right), "(fore a, top b, star c)"
        static string Body(Vessel v, Vector3 d)
        {
            Transform rt = v.ReferenceTransform;
            return "(fore " + Vector3.Dot(d, rt.up).ToString("F2", CultureInfo.InvariantCulture) + ", top " + Vector3.Dot(d, -rt.forward).ToString("F2", CultureInfo.InvariantCulture)
                + ", star " + Vector3.Dot(d, rt.right).ToString("F2", CultureInfo.InvariantCulture) + ")";
        }

        // the kOS FWD / AFT rule (lib_flfx flfxRgrp): ahead of the centre of mass along the ship's forward = FWD, else AFT
        internal static bool IsFwd(Vessel v, Part q)
        {
            return Vector3.Dot(q.transform.position - v.CurrentCoM, v.ReferenceTransform.up) > 0f;
        }

        // the parts holding the OMS propellant: the ones with LiquidFuel + Oxidizer + MonoPropellant (the orbiter's aft fuselage); else any LF + Ox part without an engine
        static List<Part> OmsTanks(Vessel v)
        {
            var l = new List<Part>();
            foreach (Part q in v.parts)
                if (q.Resources["LiquidFuel"] != null && q.Resources["Oxidizer"] != null && q.Resources["MonoPropellant"] != null) l.Add(q);
            if (l.Count > 0) return l;
            foreach (Part q in v.parts)
            {
                if (q.Resources["LiquidFuel"] == null || q.Resources["Oxidizer"] == null) continue;
                bool eng = false;
                foreach (PartModule pm in q.Modules) if (pm is ModuleEngines) eng = true;
                if (!eng) l.Add(q);
            }
            return l;
        }

        // the DLL names the parts itself: once, at the first tick the vessel has them (retried every 2 s UT while it has none)
        void SelfBind(Vessel v, FailState st, FailEntry e)
        {
            string key = e.Code + "|" + e.Target;
            double ut = Planetarium.GetUniversalTime(), nx;
            if (nextBind.TryGetValue(key, out nx) && ut < nx) return;
            nextBind[key] = ut + 2.0;
            if (nextBind.Count > 64) nextBind.Clear();
            var toks = new List<string>();
            string why = "";
            if (e.Code == "OMS 04")
            {
                foreach (Part q in OmsTanks(v)) toks.Add(Uid(q));
                why = "OMS tank parts " + toks.Count;
            }
            else
            {
                // RCS 03: the parts holding the jets of the pod (F = the forward part, L / R = the aft part, which serves both)
                List<RcsGroup> gs = RcsMap.Groups(e.Target);
                if (gs == null) { LogOnce("self-bind " + key + ": not a pod (F, L, R)"); return; }
                foreach (Part q in v.parts)
                    if (HasRcs(q) && rcs.PartJets(v, q, gs) > 0) toks.Add(Uid(q));
                why = "RCS parts of pod " + e.Target + " " + toks.Count;
            }
            if (toks.Count == 0) { LogOnce("self-bind " + key + ": no parts (" + why + ")"); return; }
            string ans = st.Bind(e.Code, e.Target, string.Join(";", toks.ToArray()));
            Log("self-bind " + key + " -> " + string.Join(";", toks.ToArray()) + " (" + why + "): " + ans);
        }

        // take amount units out of a resource (never below 0)
        void Take(FailEntry e, PartResource r, double amount)
        {
            double d = Math.Min(amount, r.amount);
            if (d <= 0) return;
            r.amount -= d;
            string key = e.Code + "|" + e.Target;
            double tot;
            drained.TryGetValue(key, out tot);
            drained[key] = tot + d;
        }

        void LeakLog(FailEntry e, Part p, string res, double rate)
        {
            string key = e.Code + "|" + e.Target;
            double ut = Planetarium.GetUniversalTime(), last, tot;
            if (drainLogAt.TryGetValue(key, out last) && ut - last < 60) return;
            drainLogAt[key] = ut;
            drained.TryGetValue(key, out tot);
            Log("leak " + key + " " + res + " part " + (p.partInfo != null ? p.partInfo.name : "?") + " flight " + p.flightID + " rate " + rate.ToString("G4", CultureInfo.InvariantCulture)
                + " u/s, drained so far " + tot.ToString("F2", CultureInfo.InvariantCulture) + " u, left " + (p.Resources[res] != null ? p.Resources[res].amount : 0).ToString("F2", CultureInfo.InvariantCulture));
        }

        void OmsLeak(FailEntry e, Part p)
        {
            double kg = FailLeak.OmsKgPerS(e.Value) / Math.Max(1, curN);        // the leak's rate is shared by the tank parts
            foreach (string rn in FailLeak.OmsResources(e.Target))
            {
                PartResource r = p.Resources[rn];
                if (r == null) continue;
                double rate = FailLeak.UnitsPerS(kg, r.info != null ? r.info.density : 0.005);
                Take(e, r, rate * curDt);
                LeakLog(e, p, rn, rate);
            }
        }

        // pct %/min of every propellant an RCS module of the part uses (MonoPropellant)
        void PctLeak(FailEntry e, Part p, double pct)
        {
            var names = new List<string>();
            foreach (PartModule pm in p.Modules) { ModuleRCS r = pm as ModuleRCS; if (r != null && r.resourceName != null && !names.Contains(r.resourceName)) names.Add(r.resourceName); }
            if (names.Count == 0) names.Add("MonoPropellant");
            foreach (string rn in names)
            {
                PartResource r = p.Resources[rn];
                if (r == null) continue;
                double rate = FailLeak.PctUnitsPerS(pct, r.maxAmount);
                Take(e, r, rate * curDt);
                LeakLog(e, p, rn, rate);
            }
        }

        // ON: the jet burns at full thrust whatever the crew does (even RCS off): the force ModuleRCS applies, at the jet's position, from the module's own power and thrust limit
        void JetOn(FailEntry e, Part p, ModuleRCS r, Transform tr)
        {
            if (p.vessel == null || p.vessel.packed || p.Rigidbody == null) return;
            PartResource res = r.resourceName != null ? p.Resources[r.resourceName] : null;
            if (res == null || res.amount <= 0) return;
            float force = r.thrusterPower * r.thrustPercentage * 0.01f;
            if (force <= 0f) return;
            Vector3 dir = r.useZaxis ? tr.forward : tr.up;
            p.AddForceAtPosition(-dir * force, tr.position);
            float isp = r.atmosphereCurve != null ? r.atmosphereCurve.Evaluate(0f) : 0f;
            double use = FailLeak.JetUnitsPerS(force, isp, res.info != null ? res.info.density : 0.004) * TimeWarp.fixedDeltaTime;
            Take(e, res, use);
            e.Corrections++;
            // At most one line a second per jet (the old LogOnce line changed with every number, ~1 a second of play), and the torque the force makes about the CoM, on the ship's axes
            string lk = e.Code + "|" + e.Target;
            float now = Time.realtimeSinceStartup, last;
            if (jetLogAt.TryGetValue(lk, out last) && now - last < 1f && now >= last) return;
            jetLogAt[lk] = now;
            Vessel v = p.vessel;
            Vector3 arm = tr.position - v.CurrentCoM, f = -dir * force;
            Log("RCS 04 " + e.Target + " FAIL ON: " + force.ToString("F2", CultureInfo.InvariantCulture) + " kN at jet " + tr.name + " of part " + Uid(p) + ", the force goes along " + (-dir).ToString("F2")
                + " (useZaxis " + r.useZaxis + ", isp " + isp.ToString("F0", CultureInfo.InvariantCulture) + ", mono " + res.amount.ToString("F1", CultureInfo.InvariantCulture) + "); jet at " + Body(v, arm)
                + " m from the CoM, force on the ship " + Body(v, f) + " kN, torque r x F " + Body(v, Vector3.Cross(arm, f)) + " kN m (fore = roll, top = yaw, star = pitch; the sign of SHIP:ANGULARVEL dotted with the facing vectors)");
        }

        void EngOut(FailEntry e, Part p, Slot u)
        {
            foreach (PartModule pm in p.Modules)
            {
                ModuleEngines m = pm as ModuleEngines;
                if (m == null) continue;
                if (m.EngineIgnited) { m.Shutdown(); e.Corrections++; }
                if (u.First(m)) { bool r = m.allowRestart; u.Undo.Add(() => { m.allowRestart = r; }); }
                m.allowRestart = false;
                HideEvent(m.Events, "Activate", u);
                HideEvent(m.Events, "Shutdown", u);
                HideAction(m.Actions, "ActivateAction", u);
                HideAction(m.Actions, "ShutdownAction", u);
                HideAction(m.Actions, "OnAction", u);
            }
        }

        void EngCap(FailEntry e, Part p, Slot u)
        {
            float cap = FailState.Cap(e.Value);
            foreach (PartModule pm in p.Modules)
            {
                ModuleEngines m = pm as ModuleEngines;
                if (m == null) continue;
                if (m.thrustPercentage > cap + 0.01f) { m.thrustPercentage = cap; e.Corrections++; }
                HideField(m.Fields, "thrustPercentage", u);
            }
        }

        void EngLock(FailEntry e, Part p, Slot u)
        {
            bool burning = false;
            foreach (PartModule pm in p.Modules) { ModuleEngines m = pm as ModuleEngines; if (m != null && m.EngineIgnited) burning = true; }
            foreach (PartModule pm in p.Modules)
            {
                ModuleGimbal g = pm as ModuleGimbal;
                if (g == null) continue;
                if (burning && !g.gimbalLock) { g.gimbalLock = true; e.Corrections++; }
                if (burning)
                {
                    HideField(g.Fields, "gimbalLock", u);
                    HideField(g.Fields, "gimbalLimiter", u);
                }
            }
        }

        // The leak's share of the part's tank: the pod's jets of the part's jets (F 1, L / R 0.5: the aft part's one tank serves both pods)
        double PodShare(FailEntry e, Part p)
        {
            List<RcsGroup> gs = RcsMap.Groups(e.Target);
            if (gs == null || p.vessel == null) return 1.0;
            return RcsMap.LeakShare(rcs.PartJets(p.vessel, p, gs), rcs.PartJets(p.vessel, p, null));
        }

        // ================================================================ THE RCS JETS (RCS 01 / 02 / 04 act on the real pods / manifolds / jets)
        // Every tick: what the standing failures say about each jet (held out by a closed manifold or a stuck-off jet, capped to a duty, stuck on), then the modules'
        // lists made so (RcsJets.Hold). A failure that is gone simply stops saying it, and the jets come back.
        void RcsPass(Vessel v, FailState st)
        {
            bool want = false;
            foreach (FailEntry e in st.List) if (e.Code == "RCS 01" || e.Code == "RCS 02" || e.Code == "RCS 04") { want = true; break; }
            if (!want && !rcs.Active && rcsPrev.Count == 0) return;
            List<RcsJets.Jet> js = rcs.Map(v);
            var off = new HashSet<Transform>();
            var cap = new Dictionary<Transform, float>();
            var on = new List<KeyValuePair<FailEntry, RcsJets.Jet>>();
            var now = new HashSet<string>();
            FailEntry firstOff = null;
            foreach (FailEntry e in st.List)
            {
                if (e.Code == "RCS 01" || e.Code == "RCS 02")
                {
                    List<RcsGroup> gs = RcsMap.Groups(e.Target);
                    if (gs == null) { LogOnce(e.Code + " " + e.Target + ": not a pod / manifold target (F ALL, L MANIFOLD 3 ...): held nothing"); e.Found = 0; continue; }
                    now.Add(e.Code + "|" + e.Target);
                    float c = e.Code == "RCS 02" ? FailState.Cap(e.Value) / 100f : 0f;
                    int n = 0;
                    foreach (RcsJets.Jet j in js)
                    {
                        if (!RcsMap.InGroups(gs, j.Pod, j.Man)) continue;
                        n++;
                        if (e.Code == "RCS 01") off.Add(j.Tr);
                        else { float o; cap[j.Tr] = cap.TryGetValue(j.Tr, out o) ? Math.Min(o, c) : c; }
                    }
                    e.Found = n;
                    if (e.Code == "RCS 01" && firstOff == null) firstOff = e;
                    if (n == 0) LogOnce(e.Code + " " + e.Target + ": the vessel has no such jets");
                    else LogOnce(e.Code + " " + e.Target + " " + e.Value + ": " + n + " jets");
                }
                else if (e.Code == "RCS 04")
                {
                    if (!RcsMap.IsJetName(e.Target)) { LogOnce("RCS 04 " + e.Target + ": not a jet name (F1U .. R4R): held nothing"); e.Found = 0; continue; }
                    string nm = e.Target.Trim().ToUpperInvariant();
                    RcsJets.Jet jet = null;
                    foreach (RcsJets.Jet j in js) if (j.Name == nm) { jet = j; break; }
                    if (jet == null) { LogOnce("RCS 04 " + e.Target + ": the vessel has no such jet"); e.Found = 0; continue; }
                    e.Found = 1;
                    now.Add(e.Code + "|" + e.Target);
                    if (RcsMap.IsOn(e.Value)) on.Add(new KeyValuePair<FailEntry, RcsJets.Jet>(e, jet));
                    else { off.Add(jet.Tr); if (firstOff == null) firstOff = e; }
                    LogOnce("RCS 04 " + nm + " " + e.Value + ": part " + Uid(jet.Part) + " module " + jet.ModIdx + " jet " + jet.JetIdx + " (" + jet.Tr.name + ")");
                }
            }
            int removed = rcs.Hold(js, off, cap);
            if (removed > 0 && firstOff != null) firstOff.Corrections += removed;
            foreach (KeyValuePair<FailEntry, RcsJets.Jet> kv in on)
            {
                if (off.Contains(kv.Value.Tr)) continue;               // a jet whose manifold is closed has no propellant to burn
                curDt = 0;
                JetOn(kv.Key, kv.Value.Part, kv.Value.Mod, kv.Value.Tr);
            }
            foreach (string k in rcsPrev) if (!now.Contains(k)) Log("released " + k);
            rcsPrev.Clear();
            foreach (string k in now) rcsPrev.Add(k);
        }

        // A token "uid:n" holds the part's n-th surface module only (a rudder part has two, the halves, and one half frozen must leave the other
        // free); "uid" (an old save, an elevon, the body flap) holds every surface module of the part.
        void Freeze(FailEntry e, Part p, int mod, Slot u)
        {
            int n = -1;
            foreach (PartModule pm in p.Modules)
            {
                bool far = pm.moduleName == "FARControllableSurface";
                ModuleControlSurface cs = pm as ModuleControlSurface;
                if (!far && cs == null) continue;
                n++;
                if (mod >= 0 && n != mod) continue;
                if (far) { FreezeFar(e, pm, u); continue; }
                float a;
                if (!held.TryGetValue(pm, out a)) { a = cs.deployAngle; held[pm] = a; }
                bool dp;
                if (!heldDep.TryGetValue(pm, out dp)) { dp = cs.deploy; heldDep[pm] = dp; }
                if (cs.deploy != dp) { cs.deploy = dp; e.Corrections++; }       // An un-deployed frozen surface stays un-deployed (AG3 / a script's deploy would swing it to its stored angle)
                if (!cs.ignorePitch || !cs.ignoreYaw || !cs.ignoreRoll) { cs.ignorePitch = true; cs.ignoreYaw = true; cs.ignoreRoll = true; e.Corrections++; }
                if (Math.Abs(cs.deployAngle - a) > 0.05f) { cs.deployAngle = a; e.Corrections++; }
                HideField(cs.Fields, "deployAngle", u);
                HideField(cs.Fields, "ignorePitch", u);
                HideField(cs.Fields, "ignoreYaw", u);
                HideField(cs.Fields, "ignoreRoll", u);
            }
        }

        void FreezeFar(FailEntry e, PartModule pm, Slot u)
        {
            FarInit(pm.GetType());
            if (fFlap == null || fPitch == null) { LogOnce("FAR surface fields not found: FCS 01 not held"); return; }
            float lv;
            if (!held.TryGetValue(pm, out lv)) { lv = Convert.ToSingle(fFlap.GetValue(pm), CultureInfo.InvariantCulture); held[pm] = lv; }
            bool fix = false;
            foreach (FieldInfo f in new FieldInfo[] { fPitch, fYaw, fRoll })
            {
                if (f == null) continue;
                if (Math.Abs(Convert.ToSingle(f.GetValue(pm), CultureInfo.InvariantCulture)) > 1e-4f) { f.SetValue(pm, 0f); fix = true; }
            }
            if (Math.Abs(Convert.ToSingle(fFlap.GetValue(pm), CultureInfo.InvariantCulture) - lv) > 0.5f)
            {
                fFlap.SetValue(pm, fFlap.FieldType == typeof(int) ? (object)(int)Math.Round(lv) : (object)lv);
                fix = true;
            }
            if (fix) e.Corrections++;
            foreach (string nm in new string[] { "pitchaxis", "yawaxis", "rollaxis", "flapDeflectionLevel" }) HideField(pm.Fields, nm, u);
        }
    }
}
