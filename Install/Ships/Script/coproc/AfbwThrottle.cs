// The throttle lever under Advanced Fly-By-Wire (AFBW 1.8.4.5), and a guard on kOS's throttle lock.
// AFBW flies its Throttle axis as an offset it adds to the vessel's final throttle (UpdateFlightProperties: mainThrottle
// + m_Throttle; EvaluateContinuousAction(Throttle) sets the offset to lever - the incoming throttle, and UpdateAxes calls
// it only when the lever's reading changes). So the lever never reaches FlightInputHandler.state (kOS's
// PILOTMAINTHROTTLE: the DAP's speedbrake lever read 0 while the gauge, the vessel's final throttle, moved), a stale offset
// rides on kOS's LOCK THROTTLE, and any lever change takes the engines from kOS.
// THE PATCH (Harmony, by name; no reference to AFBW's assembly) makes the lever what a stock throttle axis is, the
// pilot's throttle in FlightInputHandler.state:
//   EvaluateContinuousAction, action Throttle: FlightInputHandler.state.mainThrottle = Clamp01(the lever) (AFBW's own
//     mapping: its final was clamp(throttle + lever - throttle)); the original is skipped. Every other action: untouched.
//   UpdateFlightProperties: the incoming mainThrottle is put back after it (AFBW adds nothing to the vessel's throttle).
//   UpdateAxes: last_m_throttle = NaN first, so the Throttle axis is read every tick, moved or not.
// Then kOS's LOCK THROTTLE keeps the engines (kOS writes the vessel's throttle after FlightInputHandler's copy), the lever
// is PILOTMAINTHROTTLE at every tick, and with no lock the engines fly the lever (one tick late), as with a stock axis.
// THE LEVER STARTS AT 0: until the Throttle axis has reported something real, the lever reads 0. SDL gives an axis no
// event has touched yet the raw value 0; the pilot's STS throttle is mapped Left (-32768) .. Identity (32767), so raw 0 is
// the middle of the travel and the lever read 0.5 at every scene load (flight B: PILOTMAINTHROTTLE 0.50 from the pad to MECO)
// until it was moved. A reading within NODATA_TOL of 0.5 that has not moved since the scene's first one is that no-data value
// and is put to 0; the first reading that is anywhere else, or that moves, is the real lever and passes (a lever left exactly
// at the middle of its travel reads 0 until it moves). Reset at each flight scene.
// While a controller with a Throttle binding is enabled the lever overwrites the keyboard's throttle and kOS's SET
// PILOTMAINTHROTTLE each tick. ADDONS:KALS:LEVERLIVE is TRUE while the patched Throttle axis was read in the last 0.5 s.
// Without AFBW, with another AFBW whose methods / field / enum differ, or without Harmony nothing is patched (one line).
// THE GUARD (with or without AFBW): while kOS holds the active vessel's throttle lock, a final throttle that differs from
// what kOS left after the autopilot stage (a fly-by-wire handler wrote it) is put back to kOS's. Both handlers are re-added
// each physics tick so they run late in their lists (a handler added after ours each tick still runs after it). One line per
// episode at most once a second, and one when it ends. Every line in KSP.log starts with [KalsThrottle].
using System;
using System.Reflection;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class AfbwThrottle : MonoBehaviour
    {
        const string FM = "KSPAdvancedFlyByWire.FlightManager";
        const int THROTTLE = 16;            // ContinuousAction.Throttle (UpdateAxes compares with 16 itself)
        const double LIVE_DT = 0.5;         // s: LEVERLIVE while the Throttle axis was read this recently
        const float GUARD_EPS = 1E-4f;      // a final throttle this far from kOS's is overridden
        const double GUARD_DT = 1;          // s between guard lines
        const float NODATA = 0.5f;          // an untouched SDL axis (raw 0) on the Left..Identity throttle mapping
        const float NODATA_TOL = 0.02f;     // how near 0.5 a reading is the no-data value
        const float MOVE_EPS = 0.0005f;     // how far from the first reading is a move

        static bool tried, patched;
        static bool leverReal;              // the Throttle axis has reported a real position since the scene's start
        static float leverFirst = float.NaN;
        static double leverT = -1E9;        // Time.fixedTime of the last Throttle evaluation
        static bool sailLogged;             // the test-harness line (the lever's value, ignored) was written in this scene
        static float sailRaw = float.NaN;   // the lever's last raw reading under a test-harness ticket
        static double sailLineT = -1E9;     // Time.realtimeSinceStartup of the last test-harness lever line
        public static bool LeverLive { get { return patched && Time.fixedTime - leverT <= LIVE_DT && Time.fixedTime >= leverT; } }

        Vessel v;
        float kosThr;                       // the vessel's throttle after the autopilot stage (kOS's while it holds the lock)
        bool havePost;
        bool inEp, epLogged;                // an override episode is running; its start was logged
        double epT0, lineT = -1E9;
        int epN;

        static void Log(string s) { Debug.Log("[KalsThrottle] " + s); }

        void Start()
        {
            leverReal = false;
            leverFirst = float.NaN;
            sailLogged = false;
            sailRaw = float.NaN;
            if (SailBus.On)
            {
                leverT = -1E9;      // LEVERLIVE FALSE from the first tick of a test-harness scene
                Log("SAIL ticket active at the flight scene's start: the Throttle lever is ignored, kOS's PILOTMAINTHROTTLE holds (LEVERLIVE FALSE)");
            }
            if (tried) return;
            tried = true;
            MethodInfo ev, ufp, ua;
            string ver, why = Find(out ev, out ufp, out ua, out ver);
            if (why != "") { Log(why + ": nothing patched"); return; }
            try
            {
                Patch(ev, ufp, ua);
                patched = true;
                Log("AFBW " + ver + ": throttle patched (the lever is the pilot's throttle every tick; AFBW adds nothing to the vessel's)");
            }
            catch (Exception ex) { Log("AFBW " + ver + ": not patched (" + ex.GetType().Name + ": " + ex.Message + ")"); }
        }

        // AFBW's FlightManager and the three methods, the field and the enum value the patch binds; "" when all are as in 1.8.4.5
        static string Find(out MethodInfo ev, out MethodInfo ufp, out MethodInfo ua, out string ver)
        {
            ev = ufp = ua = null;
            ver = "?";
            Type fm = null;
            foreach (AssemblyLoader.LoadedAssembly la in AssemblyLoader.loadedAssemblies)
            {
                try { fm = la.assembly.GetType(FM, false); } catch (Exception) { fm = null; }
                if (fm != null) { ver = la.assembly.GetName().Version.ToString(); break; }
            }
            if (fm == null) return "AFBW not found";
            const BindingFlags bf = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
            foreach (MethodInfo m in fm.GetMethods(bf))
            {
                ParameterInfo[] p = m.GetParameters();
                if (m.Name == "EvaluateContinuousAction" && p.Length == 4 && p[1].ParameterType.IsEnum
                    && p[2].ParameterType == typeof(float) && p[3].ParameterType == typeof(FlightCtrlState)) ev = m;
                else if (m.Name == "UpdateFlightProperties" && p.Length == 1 && p[0].ParameterType == typeof(FlightCtrlState)) ufp = m;
                else if (m.Name == "UpdateAxes" && p.Length == 2 && p[1].ParameterType == typeof(FlightCtrlState)) ua = m;
            }
            string pre = "AFBW " + ver + ": ";
            if (ev == null) return pre + "EvaluateContinuousAction(config, action, float, FlightCtrlState) missing";
            if (ufp == null) return pre + "UpdateFlightProperties(FlightCtrlState) missing";
            if (ua == null) return pre + "UpdateAxes(config, FlightCtrlState) missing";
            FieldInfo f = fm.GetField("last_m_throttle", bf);
            if (f == null || f.FieldType != typeof(float)) return pre + "the float last_m_throttle missing";
            Type act = ev.GetParameters()[1].ParameterType;
            if (!Enum.IsDefined(act, "Throttle") || Convert.ToInt32(Enum.Parse(act, "Throttle")) != THROTTLE)
                return pre + "ContinuousAction.Throttle is not " + THROTTLE;
            return "";
        }

        // the only code that names Harmony's types: without Harmony it throws here, caught in Start
        static void Patch(MethodInfo ev, MethodInfo ufp, MethodInfo ua)
        {
            const BindingFlags bs = BindingFlags.Static | BindingFlags.NonPublic;
            var h = new HarmonyLib.Harmony("kals.afbwthrottle");
            h.Patch(ev, prefix: new HarmonyLib.HarmonyMethod(typeof(AfbwThrottle).GetMethod("EvalPrefix", bs)));
            h.Patch(ufp, prefix: new HarmonyLib.HarmonyMethod(typeof(AfbwThrottle).GetMethod("UfpPrefix", bs)),
                postfix: new HarmonyLib.HarmonyMethod(typeof(AfbwThrottle).GetMethod("UfpPostfix", bs)));
            h.Patch(ua, prefix: new HarmonyLib.HarmonyMethod(typeof(AfbwThrottle).GetMethod("UaPrefix", bs)));
        }

        // the lever as the pilot's throttle: 0 until the axis has reported a real position (see THE LEVER STARTS AT 0)
        static float LeverRead(float v)
        {
            v = Mathf.Clamp01(v);
            if (leverReal) return v;
            if (float.IsNaN(leverFirst)) leverFirst = v;
            if (Mathf.Abs(v - NODATA) > NODATA_TOL || Mathf.Abs(v - leverFirst) > MOVE_EPS)
            {
                leverReal = true;
                return v;
            }
            return 0;
        }

        // EvaluateContinuousAction(config, action, value, state): the Throttle axis into the pilot's throttle
        static bool EvalPrefix(object[] __args)
        {
            try
            {
                if (Convert.ToInt32(__args[1]) != THROTTLE) return true;
                if (SailBus.On) { SailLever((float)__args[2]); return false; }   // A test-harness session flies without the project owner's lever
                bool was = leverReal;
                FlightInputHandler.state.mainThrottle = LeverRead((float)__args[2]);
                if (leverReal && !was) Log("the Throttle axis reports a real position (" + FlightInputHandler.state.mainThrottle.ToString("F3") + "): the lever is read from here");
                leverT = Time.fixedTime;
                return false;
            }
            catch (Exception) { return true; }
        }

        // under a test-harness ticket the Throttle axis is read for the log only: nothing is written to FlightInputHandler.state (the
        // owner's physical lever, at 1.000 or 0.000 whatever it was left at, overwrote kOS's SET PILOTMAINTHROTTLE every tick: the 1x
        // ascents of 11-08 17:2x fired the OMS after ops1q's end), the original is skipped (AFBW adds nothing), leverT stays unset
        // (LEVERLIVE FALSE). One line at the first reading, one at each move of more than 0.05, at most one a second.
        static void SailLever(float raw)
        {
            double now = Time.realtimeSinceStartup;
            bool first = !sailLogged;
            bool moved = !first && Mathf.Abs(raw - sailRaw) > 0.05f && now - sailLineT >= 1;
            if (!first && !moved) return;
            sailLogged = true;
            sailRaw = raw;
            sailLineT = now;
            Log(string.Format("SAIL ticket: the Throttle lever reads {0:F3}{1}: ignored, LEVERLIVE FALSE, kOS's PILOTMAINTHROTTLE is the pilot's throttle ({2:F3})",
                raw, first ? "" : " (it moved)", FlightInputHandler.state.mainThrottle));
        }

        // UpdateFlightProperties(state): the vessel's throttle as it came in
        static void UfpPrefix(FlightCtrlState __0, out float __state) { __state = __0 != null ? __0.mainThrottle : 0; }
        static void UfpPostfix(FlightCtrlState __0, float __state) { if (__0 != null) __0.mainThrottle = __state; }

        // UpdateAxes: the Throttle axis read every tick (NaN never equals the reading)
        static void UaPrefix(ref float ___last_m_throttle) { ___last_m_throttle = float.NaN; }

        // ---- the guard
        static bool KosThrottleLock(Vessel ves)
        {
            try
            {
                kOS.Module.kOSVesselModule km = kOS.Module.kOSVesselModule.GetInstance(ves);
                return km != null && km.GetFlightControlParameter("throttle").Enabled;
            }
            catch (Exception) { return false; }
        }

        void Post(FlightCtrlState s) { kosThr = s.mainThrottle; havePost = true; }

        void Fin(FlightCtrlState s)
        {
            if (!havePost) return;
            havePost = false;
            double now = Planetarium.GetUniversalTime();
            bool over = Mathf.Abs(s.mainThrottle - kosThr) > GUARD_EPS && KosThrottleLock(v);
            if (over)
            {
                if (!inEp)
                {
                    inEp = true;
                    epT0 = now;
                    epN = 0;
                    epLogged = now - lineT >= GUARD_DT || now < lineT;
                    if (epLogged)
                    {
                        lineT = now;
                        Log(string.Format("guard: final {0:F3} vs kOS {1:F3} at MET {2:F2}, kept kOS's; fly-by-wire {3}",
                            s.mainThrottle, kosThr, v.missionTime, Hooks(v.OnFlyByWire)));
                    }
                }
                epN++;
                s.mainThrottle = kosThr;
            }
            else if (inEp)
            {
                inEp = false;
                if (epLogged) Log(string.Format("guard: episode over at MET {0:F2} ({1:F2} s, {2} ticks)", v.missionTime, now - epT0, epN));
            }
            OmsHold.Apply(s, v);             // ops2q's OMS interlock: nothing ARMed = the final throttle 0 (zero first, then min)
            KalsAddon.AscMecoTick(v, s);     // The AG4 press and the ascent's backup 3 g limiter, after kOS's lock and the guard
        }

        static string Hooks(Delegate d)
        {
            if (d == null) return "none";
            var names = new System.Collections.Generic.List<string>();
            foreach (Delegate h in d.GetInvocationList())
                names.Add((h.Method.DeclaringType != null ? h.Method.DeclaringType.Name + "." : "") + h.Method.Name);
            return string.Join(", ", names.ToArray());
        }

        void FixedUpdate()
        {
            Vessel a = FlightGlobals.ActiveVessel;
            if (a != v) { Unhook(); v = a; havePost = false; inEp = false; }
            if (v == null) return;
            Unhook();                  // re-added each tick: each one late in its own list
            v.OnPostAutopilotUpdate += Post;
            v.OnFlyByWire += Fin;
        }

        void Unhook()
        {
            if (v == null) return;
            v.OnPostAutopilotUpdate -= Post;
            v.OnFlyByWire -= Fin;
        }

        void OnDestroy() { Unhook(); }
    }

    public partial class KalsAddon
    {
        // ADDONS:KALS:LEVERLIVE: TRUE while AFBW's Throttle axis is patched and was read in the last 0.5 s (AfbwThrottle.cs)
        partial void RegisterLever()
        {
            AddSuffix("LEVERLIVE", new Suffix<BooleanValue>(() => new BooleanValue(AfbwThrottle.LeverLive)));
        }
    }
}
