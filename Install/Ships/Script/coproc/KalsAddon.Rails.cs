// ops2q through an on-rails warp. Principia carries a vessel's rotation through a rails warp, so the rate
// the vessel has the moment it packs is the rate it keeps for the whole warp (RailsCore.cs). The rate is set EXACTLY
// in the last physics frame before the vessel packs; the probe says what the game does with it.
//     ADDONS:KALS:RAILSARM(mode, vec) -> "" or "error ...": arm the set for the NEXT rails warp(s), for RailsCore.TTL real
//         seconds (re-arm to keep it). mode ZERO (the world rate 0), VEC (vec = the world rate in rad/s), HOLD (derived
//         from ops2q's DAP hold, KalsAddon.O2Dap.cs: INRTL 0, LVLH / TRACK-Earth the orbit rate, TRACK-Sun 0, FREE none),
//         OFF. Every pack under the arm sets every part's angular velocity (and the velocity change a rigid turn about the
//         centre of mass makes, so no joint is strained); it is set at the warp request (onTimeWarpRateChanged, rails mode)
//         and again at the vessel's pack event (onVesselGoOnRails), idempotent.
//     ADDONS:KALS:RAILSWATCH(on) -> on: log every pack / unpack of the active vessel even with nothing armed (the probe).
//     ADDONS:KALS:RAILSINFO -> LEXICON(armed, mode, sets, packs, unpacks, log): log = LIST of the lines since the last call
//         (cleared): each pack (UT, the part rigid rate, the vessel's rate, the attitude), each set (where, from, to), each
//         unpack (the UT jump, the angle turned, the mean rate, the rate now). kOS writes them to its own log.
//     ADDONS:KALS:RAILSSETTLE(on) -> "" or "error ...": while ZERO / VEC is armed and the vessel is unpacked, a closed loop (RailsCore.Settle) takes the
//         vessel's angular momentum to the armed rate's in the physics frames BEFORE the warp is asked for (the request's own impulse has no frame to land in when the
//         pack comes in the same frame): ADDONS:KALS:RAILSSETTLING -> TRUE while it runs (kOS waits on it, WAIT 0), RAILSINFO also gives settling / settleErr (deg/s) /
//         settleImpulses. The lines 'RAILS settle: start' / 'RAILS torque: ...' per impulse / 'RAILS settle: SETTLED | TIMEOUT | GAVE UP | PACKED ...' go to the log. The
//         warp request and the pack stop it. A HOLD arm is not settled (the DAP's jets would fight it).
//     A rails warp the PILOT starts (any rate, the keys, the test harness's warp verb) while ADDONS:KALS:RAILSARM HOLD is armed (ops2q O2Q_RAILS_HOLD, the DAP flying a hold) is HELD: a Harmony
//         prefix on TimeWarp.SetRate (only the 1x -> rails request; a cancel or a rate change on rails passes) starts the settle against the hold's rate (RailsCore.WarpGate), and the FixedUpdate
//         that sees the settle over (SETTLED, TIMEOUT, GAVE UP, a stop) asks the game for the warp itself. No Principia, a hold that gives no rate or a refused settle: the request passes at once.
// setting the parts' rates does NOT stop the vessel's turn through the warp: Principia keeps the rotation as the angular
//     momentum of its pile-up and rewrites the parts' rates from it every physics frame (the pack line shows the rate back a frame after
//     a set to 0). At the warp request (the last physics frame in which the vessel is unpacked) the armed set therefore also adds the
//     torque impulse that takes the pile-up's angular momentum to the armed rate's: a RIGID acceleration of every body (F3b: Part.AddTorque I_p u / dt +
//     Part.AddForce m_p (u x d_p) / dt, u = I_tot^-1 (I_tot w - L); F3's mass shares made the parts spin against each other and the inertia was summed twice
//     over the parent's body: Part.Rigidbody is the PARENT's body for a part without one, the field rb is the part's own), the channel the reaction wheels use (Principia reads part.torque as an intrinsic torque and integrates it over
//     the frame's step, dt = Planetarium.TimeScale x fixedDeltaTime). One "RAILS torque" line per request says L, the target and the torque.
// Every call is guarded: a throw never reaches kOS, a bad rate is refused, a handler that fails logs and sets nothing.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        static readonly RailsCore.Arm rlArm = new RailsCore.Arm();
        static readonly List<string> rlLog = new List<string>();
        static bool rlSub, rlWatch, rlHavePack;
        static RlEvents rlEvents;
        static int rlPacks, rlUnpacks;
        static double rlPackUT, rlPackRT;
        static Quaternion rlPackRot;
        static readonly CultureInfo rlIC = CultureInfo.InvariantCulture;
        static readonly RailsCore.Settle rlSet = new RailsCore.Settle();
        static bool rlSettleOn;
        static readonly RailsCore.WarpGate rlGate = new RailsCore.WarpGate();
        static bool rlGateBypass, rlGateTried;
        static int rlTraceN;                                                    // frames of 'RAILS trace' lines still to write

        partial void RegisterRails()
        {
            AddSuffix("RAILSARM", new TwoArgsSuffix<StringValue, StringValue, Structure>((m, w) => new StringValue(RlArm(m == null ? "" : m.ToString(), w))));
            AddSuffix("RAILSWATCH", new OneArgsSuffix<BooleanValue, BooleanValue>(on => { rlWatch = on != null && on.Value; if (rlWatch) RlSubscribe(); else if (!rlArm.On) RlUnsubscribe(); return new BooleanValue(rlWatch); }));
            AddSuffix("RAILSINFO", new Suffix<Lexicon>(() => RlInfo()));
            AddSuffix("RAILSSETTLE", new OneArgsSuffix<StringValue, BooleanValue>(on => new StringValue(RlSettle(on != null && on.Value))));
            AddSuffix("RAILSSETTLING", new Suffix<BooleanValue>(() => new BooleanValue(rlSettleOn)));
        }

        static string RlF(double x) { return x.ToString("0.#####", rlIC); }
        static string RlV(Vector3 v) { return "(" + RlF(v.x) + ", " + RlF(v.y) + ", " + RlF(v.z) + ")"; }

        static void RlNote(string s)
        {
            double ut = 0;
            try { ut = Planetarium.GetUniversalTime(); } catch (Exception) { }
            if (rlLog.Count >= 400) rlLog.RemoveAt(0);
            rlLog.Add("UT " + ut.ToString("0.00", rlIC) + " " + s);
        }

        static string RlArm(string mode, Structure w)
        {
            try
            {
                if (mode.ToUpperInvariant() != "OFF") RlSubscribe(); else RlSettleStop("DISARMED");
                double[] vec = null;
                if (mode.ToUpperInvariant() == "VEC")
                {
                    var kv = w as kOS.Suffixed.Vector;
                    if (kv == null) return "error VEC wants a vector";
                    Vector3d d = kv.ToVector3D();
                    vec = new[] { d.x, d.y, d.z };
                }
                string r = rlArm.Set(mode, vec, Time.realtimeSinceStartup);
                if (r == "") RlNote("RAILS arm " + (rlArm.On ? rlArm.Mode + (rlArm.Mode == "VEC" ? " " + RlF(vec[0]) + ", " + RlF(vec[1]) + ", " + RlF(vec[2]) : "") : "OFF"));
                if (r == "" && !rlArm.On && !rlWatch) RlUnsubscribe();
                return r;
            }
            catch (Exception ex) { return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        // KSP's EvtDelegate reads the delegate's Target, so a STATIC method (no target) as a GameEvents handler throws a NullReferenceException
        // in Add. The handlers are instance methods of one live object, subscribed once and unsubscribed from that same object;
        // the object and the flag are static, so a scene load never subscribes twice. They read the static state and do nothing
        // when nothing is armed or watched.
        sealed class RlEvents
        {
            public void OnRate() { RlOnRate(); }
            public void OnPack(Vessel v) { RlOnPack(v); }
            public void OnUnpack(Vessel v) { RlOnUnpack(v); }
        }

        static void RlSubscribe()
        {
            if (rlSub) return;
            var h = new RlEvents();
            try
            {
                GameEvents.onTimeWarpRateChanged.Add(h.OnRate);
                GameEvents.onVesselGoOnRails.Add(h.OnPack);
                GameEvents.onVesselGoOffRails.Add(h.OnUnpack);
            }
            catch (Exception ex)
            {
                RlDetach(h);
                RlNote("RAILS subscribe failed: " + ex.GetType().Name + ": " + ex.Message);
                return;
            }
            rlEvents = h;
            rlSub = true;
        }

        static void RlUnsubscribe()
        {
            if (!rlSub) return;
            RlDetach(rlEvents);
            rlEvents = null;
            rlSub = false;
        }

        static void RlDetach(RlEvents h)
        {
            if (h == null) return;
            try { GameEvents.onTimeWarpRateChanged.Remove(h.OnRate); } catch (Exception) { }
            try { GameEvents.onVesselGoOnRails.Remove(h.OnPack); } catch (Exception) { }
            try { GameEvents.onVesselGoOffRails.Remove(h.OnUnpack); } catch (Exception) { }
        }

        static bool RlRails()
        {
            return TimeWarp.WarpMode == TimeWarp.Modes.HIGH && TimeWarp.CurrentRateIndex > 0;
        }

        static void RlOnRate()
        {
            try { if (rlArm.On && RlRails()) { rlTraceN = 14; RlSettleStop("STOPPED BY THE WARP REQUEST"); RlApply("warp request"); } }
            catch (Exception ex) { RlNote("RAILS warp request handler: " + ex.GetType().Name + ": " + ex.Message); }
        }

        static void RlOnPack(Vessel v)
        {
            try
            {
                if (v == null || v != FlightGlobals.ActiveVessel) return;
                RlSettleStop("STOPPED BY THE PACK");
                if (rlArm.On) RlApply("pack");
                if (!rlWatch && !rlArm.On) return;
                rlPacks++;
                rlHavePack = true;
                rlPackUT = Planetarium.GetUniversalTime();
                rlPackRT = Time.realtimeSinceStartup;
                rlPackRot = v.ReferenceTransform != null ? v.ReferenceTransform.rotation : Quaternion.identity;
                Vector3 pw = Vector3.zero; int n = 0;
                foreach (Part p in v.parts) if (p != null && p.rb != null) { pw += p.rb.angularVelocity; n++; }
                if (n > 0) pw /= n;
                Vector3d pf = Vector3d.zero, pt = Vector3d.zero;
                foreach (Part p in v.parts) if (p != null) { pf += p.force; pt += p.torque; }
                RlNote("RAILS pack: pending part force " + RlF(pf.magnitude) + " kN, torque " + RlF(pt.magnitude) + " kN m, DAP quiet " + RlDapQuiet() + ", DAP cmd (" + RlF(fbCmd[0]) + ", " + RlF(fbCmd[1]) + ", " + RlF(yjCmd) + ")");
                RlNote("RAILS pack: rate of the parts (world) " + RlV(pw) + " rad/s = " + RlF(pw.magnitude * Mathf.Rad2Deg) + " deg/s, v.angularVelocity " + RlV(v.angularVelocity)
                    + ", v.angularMomentum " + RlV(v.angularMomentum) + ", rates index " + TimeWarp.CurrentRateIndex + " x" + RlF(TimeWarp.CurrentRate) + ", attitude (world) " + rlPackRot.ToString("F4"));
            }
            catch (Exception ex) { RlNote("RAILS pack handler: " + ex.GetType().Name + ": " + ex.Message); }
        }

        static void RlOnUnpack(Vessel v)
        {
            try
            {
                if (v == null || v != FlightGlobals.ActiveVessel || !rlHavePack) return;
                rlHavePack = false;
                rlUnpacks++;
                rlTraceN = 14;
                double ut = Planetarium.GetUniversalTime();
                Quaternion q = v.ReferenceTransform != null ? v.ReferenceTransform.rotation : Quaternion.identity;
                double ang = Quaternion.Angle(rlPackRot, q), dut = ut - rlPackUT;
                Vector3 pw = Vector3.zero; int n = 0;
                foreach (Part p in v.parts) if (p != null && p.rb != null) { pw += p.rb.angularVelocity; n++; }
                if (n > 0) pw /= n;
                RlNote("RAILS unpack: " + RlF(dut) + " s of UT (" + RlF(Time.realtimeSinceStartup - rlPackRT) + " s real), turned " + RlF(ang) + " deg = mean " + RlF(dut > 0 ? ang / dut : 0)
                    + " deg/s, rate now " + RlF(pw.magnitude * Mathf.Rad2Deg) + " deg/s " + RlV(pw) + ", v.angularVelocity " + RlV(v.angularVelocity) + ", attitude (world) " + q.ToString("F4"));
            }
            catch (Exception ex) { RlNote("RAILS unpack handler: " + ex.GetType().Name + ": " + ex.Message); }
        }

        // The torque impulse that takes the vessel's angular momentum (the one Principia carries) to I w_target, from the parts' state
        // as it is now (before the rate set). Only with Principia running: without it the rate set stands alone (the bodies keep it).
        // apply FALSE = measure only (errDegS = the rate change the impulse would make, deg/s; the settle's frame read); log FALSE = no lines. false = nothing could be computed.
        static bool RlTorque(Vessel v, Vector3 wn, bool apply, bool log, out double errDegS)
        {
            errDegS = -1;
            try
            {
                if (!Pr.Find() || Pr.Plugin() == IntPtr.Zero) { if (log) RlNote("RAILS torque: none (no Principia running: " + Pr.Err + ")"); return false; }
                double dt = Planetarium.TimeScale * Planetarium.fetch.fixedDeltaTime;
                if (!(dt > 1e-4 && dt < 1)) { if (log) RlNote("RAILS torque: none (the frame step " + RlF(dt) + " s is out of range)"); return false; }
                var bodies = new List<RailsCore.PartBody>();
                var parts = new List<Part>();
                foreach (Part p in v.parts)
                {
                    Rigidbody b = p != null ? p.rb : null;
                    if (b == null || !(b.mass > 0)) continue;
                    var pb = new RailsCore.PartBody();
                    pb.M = b.mass;
                    Vector3 c = b.worldCenterOfMass, vel = b.velocity, av = b.angularVelocity, it = b.inertiaTensor;
                    for (int i = 0; i < 3; i++) { pb.P[i] = c[i]; pb.V[i] = vel[i]; pb.W[i] = av[i]; }
                    Quaternion q = b.rotation * b.inertiaTensorRotation;
                    Vector3[] ax = { q * Vector3.right, q * Vector3.up, q * Vector3.forward };
                    for (int k = 0; k < 3; k++)
                        for (int i = 0; i < 3; i++)
                            for (int j = 0; j < 3; j++) pb.I[3 * i + j] += it[k] * ax[k][i] * ax[k][j];
                    bodies.Add(pb); parts.Add(p);
                }
                double[] dL, L, iTot; double mass;
                if (!RailsCore.MomentumChange(bodies.ToArray(), new double[] { wn.x, wn.y, wn.z }, out dL, out L, out iTot, out mass)) { if (log) RlNote("RAILS torque: none (no mass or a bad number)"); return false; }
                double dlm = Math.Sqrt(dL[0] * dL[0] + dL[1] * dL[1] + dL[2] * dL[2]), lm = Math.Sqrt(L[0] * L[0] + L[1] * L[1] + L[2] * L[2]);
                double tm = dlm / dt;
                string head = "RAILS torque: L (world) (" + RlF(L[0]) + ", " + RlF(L[1]) + ", " + RlF(L[2]) + ") = " + RlF(lm) + " t m2/s (stock v.angularMomentum " + RlF(v.angularMomentum.magnitude)
                    + "), mass " + RlF(mass) + " t, target rate " + RlV(wn) + " rad/s, dL (" + RlF(dL[0]) + ", " + RlF(dL[1]) + ", " + RlF(dL[2]) + ") = " + RlF(dlm) + ", step " + RlF(dt) + " s -> torque " + RlF(tm) + " kN m";
                double[] u; double[][] tau, force;
                if (!RailsCore.RigidShares(bodies.ToArray(), dL, dt, out u, out tau, out force)) { if (log) RlNote(head + ": REFUSED, no rigid shares (singular inertia or a bad number)"); return false; }
                errDegS = Math.Sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2]) * Mathf.Rad2Deg;
                if (!apply) return true;
                if (dlm < 1e-6) { if (log) RlNote(head + ": nothing to add"); return true; }
                if (tm > 5e4) { if (log) RlNote(head + ": REFUSED, over 50000 kN m"); return false; }
                for (int i = 0; i < parts.Count; i++)
                {
                    parts[i].AddTorque(new Vector3d(tau[i][0], tau[i][1], tau[i][2]));
                    parts[i].AddForce(new Vector3d(force[i][0], force[i][1], force[i][2]));
                }
                if (log) RlNote(head + ": rate change " + RlF(errDegS) + " deg/s intended (" + RlV(new Vector3((float)u[0], (float)u[1], (float)u[2])) + " rad/s), on "
                    + parts.Count + " bodies (Part.AddTorque + Part.AddForce, a rigid acceleration)");
                return true;
            }
            catch (Exception ex) { errDegS = -1; if (log) RlNote("RAILS torque: " + ex.GetType().Name + ": " + ex.Message); return false; }
        }

        // The settle (RailsCore.Settle): started by kOS (RAILSSETTLE) after the DAP is free, run by RailsSettleTick's FixedUpdate until the rate is within ErrOk
        static string RlSettle(bool on, bool allowHold = false)
        {
            try
            {
                if (!on) { RlSettleStop("OFF"); return ""; }
                if (!rlArm.On) return "error not armed (RAILSARM first)";
                if (rlArm.Mode == "HOLD" && !allowHold) return "error HOLD is not settled (the DAP's jets would fight it)";   // Only the gate's own settle (the pilot's warp) runs under a HOLD
                Vessel v = FlightGlobals.ActiveVessel;
                if (v == null) return "error no active vessel";
                if (v.packed) return "error the vessel is packed";
                if (!Pr.Find() || Pr.Plugin() == IntPtr.Zero) return "error no Principia running: " + Pr.Err;
                rlSet.Start(Time.realtimeSinceStartup);
                rlSettleOn = true;
                RlNote("RAILS settle: start, mode " + rlArm.Mode);
                return "";
            }
            catch (Exception ex) { return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        static void RlSettleStop(string why)
        {
            if (!rlSettleOn) return;
            rlSettleOn = false;
            rlSet.Finish(why);
            RlNote("RAILS settle: " + why + " after " + rlSet.Impulses + " impulses, " + rlSet.Frames + " frames, rate error " + RlF(rlSet.LastErr) + " deg/s");
        }

        // The rate the arm gives now, from the world state (HOLD: the DAP's hold and the orbit); null = none
        static double[] RlTake(Vessel v)
        {
            if (rlArm.Mode != "HOLD") return rlArm.Take(Time.realtimeSinceStartup, "", 0, null, null);
            Vector3d pr = v.CoMD - v.mainBody.position, ov = v.obt_velocity;
            return rlArm.Take(Time.realtimeSinceStartup, o2dOn ? o2dC.hold : "", o2dLos, new[] { pr.x, pr.y, pr.z }, new[] { ov.x, ov.y, ov.z });
        }

        internal static void RlSettleTick()
        {
            RlSettleStep();
            RlGateRelease();
            RlTraceStep();
        }

        // The DAP commands nothing while a rails warp is on or being asked for (a rails frame is TimeScale x fixedDeltaTime long: the RCS is integrated over all of it)
        internal static bool RlDapQuiet()
        {
            try { return RailsCore.DapQuiet(RlRails(), rlSettleOn, rlGate.Pending); }
            catch (Exception) { return false; }
        }

        // The frames around a rails request / unpack, one line each: what the vessel's rate, the part forces and the DAP are doing in them
        static void RlTraceStep()
        {
            if (rlTraceN <= 0) return;
            rlTraceN--;
            try
            {
                Vessel v = FlightGlobals.ActiveVessel;
                if (v == null) return;
                Vector3 pw = Vector3.zero; int n = 0;
                Vector3d pf = Vector3d.zero, pt = Vector3d.zero;
                foreach (Part p in v.parts)
                {
                    if (p == null) continue;
                    if (p.rb != null) { pw += p.rb.angularVelocity; n++; }
                    pf += p.force; pt += p.torque;
                }
                if (n > 0) pw /= n;
                Vector3 va = v.angularVelocity;
                RlNote("RAILS trace: step " + RlF(Planetarium.TimeScale * Planetarium.fetch.fixedDeltaTime) + " s x" + RlF(TimeWarp.CurrentRate) + " idx " + TimeWarp.CurrentRateIndex + (v.packed ? " PACKED" : "")
                    + ", parts' rate " + RlF(pw.magnitude * Mathf.Rad2Deg) + " deg/s, v.angularVelocity " + RlF(va.magnitude * Mathf.Rad2Deg) + " deg/s " + RlV(va) + ", pending force " + RlF(pf.magnitude) + " kN torque "
                    + RlF(pt.magnitude) + " kN m, DAP quiet " + RlDapQuiet() + " cmd (" + RlF(fbCmd[0]) + ", " + RlF(fbCmd[1]) + ", " + RlF(yjCmd) + ")");
            }
            catch (Exception ex) { RlNote("RAILS trace: " + ex.GetType().Name + ": " + ex.Message); }
        }

        // The pilot's warp request, held for the settle (TimeWarp.SetRate prefix): false = the game's SetRate does not run now
        internal static bool RlGatePrefix(int rateIndex, bool instant, bool post)
        {
            try
            {
                if (rlGateBypass) return true;
                if (rateIndex <= 0)
                {
                    if (rlGate.Pending) { rlGate.Cancel(); RlSettleStop("CANCELLED"); RlNote("RAILS warp request cancelled while held"); }
                    return true;
                }
                if (rlGate.Pending) { rlGate.Hold(rateIndex, instant, post, Time.realtimeSinceStartup); return false; }
                Vessel v = FlightGlobals.ActiveVessel;
                if (!rlArm.On || v == null || v.packed) return true;
                if (!RailsCore.WarpGate.Wants(rlArm.Mode == "HOLD", rlArm.Mode == "HOLD" && RlTake(v) != null, TimeWarp.WarpMode == TimeWarp.Modes.HIGH, TimeWarp.CurrentRateIndex, rateIndex)) return true;
                string r = RlSettle(true, true);
                if (r != "") { RlNote("RAILS hold settle not run: " + r + " (the warp goes on)"); return true; }
                rlGate.Hold(rateIndex, instant, post, Time.realtimeSinceStartup);
                RlNote("RAILS warp request (index " + rateIndex + ") held for the settle to the hold's rate");
                return false;
            }
            catch (Exception ex) { RlNote("RAILS warp gate: " + ex.GetType().Name + ": " + ex.Message); return true; }
        }

        // The held request goes to the game once the settle is over (or after WarpGate.MaxReal)
        static void RlGateRelease()
        {
            if (!rlGate.Pending) return;
            try
            {
                if (!rlGate.Due(rlSettleOn, Time.realtimeSinceStartup)) return;
                int idx = rlGate.Index; bool ins = rlGate.Instant, post = rlGate.Post;
                rlGate.Cancel();
                RlSettleStop("RELEASED AT THE GATE LIMIT");
                rlGateBypass = true;
                rlTraceN = 14;
                try { TimeWarp.SetRate(idx, ins, post); }
                finally { rlGateBypass = false; }
                RlNote("RAILS warp request (index " + idx + ") released after the settle (" + rlSet.Why + ", rate error " + RlF(rlSet.LastErr) + " deg/s)");
            }
            catch (Exception ex) { rlGate.Cancel(); RlNote("RAILS gate release: " + ex.GetType().Name + ": " + ex.Message); }
        }

        internal static void RlGateReset() { rlGate.Cancel(); rlGateBypass = false; }

        // The Harmony prefix on TimeWarp.SetRate, once per game (the only code that names HarmonyLib; without it the pilot's warp is not held and the rest of KalsCoproc loads)
        internal static void RlGatePatch()
        {
            if (rlGateTried) return;
            rlGateTried = true;
            try
            {
                MethodInfo m = typeof(TimeWarp).GetMethod("SetRate", BindingFlags.Static | BindingFlags.Public);
                MethodInfo pre = typeof(RlGateHook).GetMethod("Prefix", BindingFlags.Static | BindingFlags.Public);
                if (m == null || pre == null) throw new Exception("SetRate or the prefix not found");
                new HarmonyLib.Harmony("kals.railsgate").Patch(m, prefix: new HarmonyLib.HarmonyMethod(pre));
                RlNote("RAILS gate: TimeWarp.SetRate patched (a pilot's rails warp under a HOLD arm waits for the settle)");
            }
            catch (Exception ex) { RlNote("RAILS gate not patched (the pilot's warp is not held): " + ex.GetType().Name + ": " + ex.Message); }
        }

        static void RlSettleStep()
        {
            if (!rlSettleOn) return;
            try
            {
                Vessel v = FlightGlobals.ActiveVessel;
                if (v == null || v.packed) { RlSettleStop("PACKED"); return; }
                double[] w = RlTake(v);   // HOLD too (the gate's settle)
                if (w == null) { RlSettleStop("DISARMED"); return; }
                var wn = new Vector3((float)w[0], (float)w[1], (float)w[2]);
                double err;
                if (!RlTorque(v, wn, false, false, out err)) { RlSettleStop("NO MEASURE"); return; }
                int a = rlSet.Step(err, Time.realtimeSinceStartup);
                if (a > 0) { double e2; RlTorque(v, wn, true, true, out e2); }
                else if (a < 0)
                {
                    rlSettleOn = false;
                    RlNote("RAILS settle: " + rlSet.Why + " after " + rlSet.Impulses + " impulses, " + rlSet.Frames + " frames, rate error " + RlF(rlSet.LastErr) + " deg/s");
                }
            }
            catch (Exception ex) { rlSettleOn = false; RlNote("RAILS settle handler: " + ex.GetType().Name + ": " + ex.Message); }
        }

        // the rate set: every part's angular velocity to w, each part's velocity changed by the rigid turn about the centre of mass
        static void RlApply(string where)
        {
            Vessel v = FlightGlobals.ActiveVessel;
            if (v == null) { RlNote("RAILS set (" + where + "): no active vessel"); return; }
            if (v.packed) { RlNote("RAILS set (" + where + "): already packed, the parts' bodies are not ours"); return; }
            double[] r = null, vo = null;
            string hold = ""; int los = 0;
            if (rlArm.Mode == "HOLD")
            {
                hold = o2dOn ? o2dC.hold : ""; los = o2dLos;
                Vector3d pr = v.CoMD - v.mainBody.position, ov = v.obt_velocity;
                r = new[] { pr.x, pr.y, pr.z }; vo = new[] { ov.x, ov.y, ov.z };
            }
            double[] w = rlArm.Take(Time.realtimeSinceStartup, hold, los, r, vo);
            if (w == null) { RlNote("RAILS set (" + where + "): nothing to set (" + (rlArm.On ? "the hold " + (hold == "" ? "is off" : hold) + " gives none" : "the arm lapsed") + ")"); return; }
            var wn = new Vector3((float)w[0], (float)w[1], (float)w[2]);
            if (where == "warp request") { double e0; RlTorque(v, wn, true, true, out e0); }
            Vector3 com = v.CoMD, wOld = Vector3.zero;
            int n = 0;
            foreach (Part p in v.parts) if (p != null && p.rb != null) { wOld += p.rb.angularVelocity; n++; }
            if (n == 0) { RlNote("RAILS set (" + where + "): no part bodies"); return; }
            wOld /= n;
            Vector3 dw = wn - wOld;
            foreach (Part p in v.parts)
            {
                Rigidbody b = p != null ? p.rb : null;
                if (b == null) continue;
                b.velocity += Vector3.Cross(dw, b.worldCenterOfMass - com);
                b.angularVelocity = wn;
            }
            rlArm.Sets++;
            RlNote("RAILS set (" + where + ", " + rlArm.Mode + (hold != "" ? " " + hold : "") + "): " + RlV(wOld) + " rad/s (" + RlF(wOld.magnitude * Mathf.Rad2Deg) + " deg/s) -> " + RlV(wn)
                + " rad/s (" + RlF(wn.magnitude * Mathf.Rad2Deg) + " deg/s) on " + n + " parts");
        }

        static Lexicon RlInfo()
        {
            var k = new KLex();
            k["armed"] = rlArm.On; k["mode"] = rlArm.Mode; k["sets"] = rlArm.Sets; k["packs"] = rlPacks; k["unpacks"] = rlUnpacks;
            k["settling"] = rlSettleOn; k["settleErr"] = rlSet.LastErr; k["settleImpulses"] = rlSet.Impulses;
            var l = new List<object>();
            foreach (string s in rlLog) l.Add(s);
            rlLog.Clear();
            k["log"] = l;
            return (Lexicon)PadKos.To(k);
        }

    }

    // The settle's physics-frame hook (KalsAddon.RlSettleTick does nothing while no settle runs)
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class RailsSettleTick : MonoBehaviour
    {
        void Start() { KalsAddon.RlGateReset(); KalsAddon.RlGatePatch(); }
        void FixedUpdate() { KalsAddon.RlSettleTick(); }
    }

    // The Harmony prefix's home (parameter names are the game's: rate_index, instant, postScreenMessage)
    public static class RlGateHook
    {
        public static bool Prefix(int rate_index, bool instant, bool postScreenMessage) { return KalsAddon.RlGatePrefix(rate_index, instant, postScreenMessage); }
    }
}
