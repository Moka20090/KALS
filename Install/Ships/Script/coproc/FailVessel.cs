// The failure list of one vessel (Fail.cs's FailState) kept with the vessel itself: a VesselModule, so KSP creates one per
// vessel, loaded or not, and writes it into the vessel's own save data (a ConfigNode KALSFAIL inside the module's node).
// The list therefore survives a scene change, a reload of the flight and a kOS reboot or a change of kOS program; a quickload
// brings back whatever the earlier save held, which is KSP's own doing and stays.
//   Tick (FixedUpdate, loaded vessels): completes fixes whose time is over and runs the flight watch (the latched flight ends
//   when the vessel has landed and sat still; a recovered vessel is gone with its module).
//   Enforcement: FailEnforce.Apply holds the parts of every bound failure each tick (engine out / thrust low / gimbal
//   locked, RCS off / thrust low, a surface frozen); this module holds the truth the parts are made to obey.
// The kOS face is KalsAddon.Fail.cs (FAILSET / FAILFIX / FAILLIST / SIMSTATE / SIMLATCH / SIMPOINT). Log lines start [KalsFail].
using System;
using System.Collections.Generic;
using UnityEngine;

namespace KalsCoproc
{
    public class FailVessel : VesselModule
    {
        public const string NodeName = "KALSFAIL";
        public readonly FailState S = new FailState();
        readonly FailEnforce enforce = new FailEnforce();
        public FailEnforce Enforcer { get { return enforce; } }          // The RCS jet map (RCSPOD)
        readonly PayloadRcs payload = new PayloadRcs();
        public PayloadRcs Payload { get { return payload; } }             // T1017: the payload's RCS held off while it is on the shuttle (PAYLOADRCS)
        readonly System.Collections.Generic.List<FailEntry> gone = new System.Collections.Generic.List<FailEntry>();

        public static void Log(string s) { Debug.Log("[KalsFail] " + s); }

        public static FailVessel Of(Vessel v)
        {
            if (v == null) return null;
            try { return v.FindVesselModuleImplementing<FailVessel>(); }
            catch (Exception) { return null; }
        }

        // loaded and unloaded vessels, every scene: the state must be saved whatever the game is showing
        public override Activation GetActivation() { return Activation.Always; }

        public static double Now() { return Planetarium.GetUniversalTime(); }

        protected override void OnSave(ConfigNode node)
        {
            try
            {
                if (S.List.Count == 0 && !S.Latched && !S.SpareUsed) return;        // nothing to keep: no node, no clutter in the save
                ConfigNode n = node.AddNode(NodeName);
                foreach (var kv in S.SimRecord()) n.AddValue(kv.Key, kv.Value);
                foreach (var d in S.FailRecords())
                {
                    ConfigNode f = n.AddNode("FAIL");
                    foreach (var kv in d) f.AddValue(kv.Key, kv.Value);
                }
            }
            catch (Exception e) { Log("save failed: " + e.Message); }
        }

        protected override void OnLoad(ConfigNode node)
        {
            try
            {
                ConfigNode n = node == null ? null : node.GetNode(NodeName);
                if (n == null) { S.Restore(null, null); return; }
                var sim = new Dictionary<string, string>();
                foreach (ConfigNode.Value v in n.values) sim[v.name] = v.value;
                var fails = new List<Dictionary<string, string>>();
                foreach (ConfigNode f in n.GetNodes("FAIL"))
                {
                    var d = new Dictionary<string, string>();
                    foreach (ConfigNode.Value v in f.values) d[v.name] = v.value;
                    fails.Add(d);
                }
                S.Restore(sim, fails);
                if (S.List.Count > 0 || S.Latched) Log("restored " + S.List.Count + " failure(s), latched " + S.Latched + " on " + (vessel != null ? vessel.vesselName : "?"));
            }
            catch (Exception e) { Log("load failed: " + e.Message); }
        }

        void FixedUpdate()
        {
            try
            {
                if (vessel == null || !vessel.loaded) return;
                double now = Now();
                gone.Clear();
                int n = S.Tick(now, gone);
                if (n > 0) Log(n + " fix(es) done, " + S.List.Count + " failure(s) left");
                enforce.Apply(vessel, S);                   // after the fixes (a fixed failure is released) and before anything else this tick
                payload.Tick(vessel);                       // T1017: a payload's RCS is held off while it is on the shuttle's vessel, given back when it is not
                if (S.Latched)
                {
                    Vessel.Situations sit = vessel.situation;
                    bool landed = sit == Vessel.Situations.LANDED || sit == Vessel.Situations.SPLASHED;
                    bool air = sit == Vessel.Situations.FLYING || sit == Vessel.Situations.SUB_ORBITAL
                            || sit == Vessel.Situations.ORBITING || sit == Vessel.Situations.ESCAPING;
                    if (S.Watch(now, air, landed, vessel.srfSpeed)) { Log("the flight is over (landed and still): failures and latch dropped"); enforce.Apply(vessel, S); }
                }
            }
            catch (Exception e) { Log("tick failed: " + e.Message); }
        }
    }
}
