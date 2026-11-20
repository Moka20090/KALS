// The fly-by-wire handler: the DAP's commands on the vessel's pitch, roll and yaw, and the pilot's own input read back.
// kOS's raw controls do not reach the vessel, so the addon subscribes Vessel.OnFlyByWire (re-subscribed at each call, so
// it runs after every other handler) and sets each commanded axis there, every physics tick.
// The command reaches the vessel as a trim: each tick the handler adds (command - what it was handed), so the vessel's
// axis is the DAP's command alone whatever the pilot or another mod put in. The pilot's input is read where every device
// and mod ends up: an unlocked gimbal's actuation (KSP's ModuleGimbal.actuation = vessel.ctrlState of the last update)
// less last tick's trim. KSP updates a gimbal's actuation only once its engine has been staged or activated
// (ModuleGimbal.gimbalActive, never cleared), so the readback prefers such a gimbal and otherwise switches one on (its
// engine stays unlit: no thrust, no torque); with no gimbal, or in the frame one is switched on, the input as handed
// (the same number: last frame's final input less last frame's trim). A reading past +-1.02 cannot come from a
// device and reads 0 (logged at most once a second).
// Each axis is dropped 0.5 s after its last command (the DAP stopped); it is then the pilot's again. No RCS axis is
// touched except by YAWJETAXES, which puts every RCS part on yaw only while the DAP flies the yaw jets.
// FBWXOFF holds the vessel's translation (X, Y, Z: the THC and its keys) at 0 in the same handler, so the pilot's
// translation reaches no jet while a program reads it (kOS's PILOTSTARBOARD / TOP / FORE read FlightInputHandler.state,
// which the handler does not touch); dropped 0.5 s after its last call, as an axis.
//     ADDONS:KALS:FBW3(p, r, y)      p, r, y (-1..1; + = nose up, roll right, nose right) replace the vessel's pitch, roll,
//                                    yaw from now (each axis dropped 0.5 s after its last call)
//     ADDONS:KALS:FBWPILOT           LIST(pitch, roll, yaw): the pilot's input at the handler's last call (0 when not read)
//     ADDONS:KALS:FBWOFF             every axis off and the handler removed (the RCS axes are not touched)
//     ADDONS:KALS:FBWAUTH            LIST(pitch, roll, yaw): the angular acceleration a full command gives now, deg/s2
//     (FBWAUTHX [0-2], "FBWAUTHS")  FBWAUTH as stock's estimate reads it: under FAR the FAR surfaces' share is SockFarTrim's
//                                    StockAuth (FAR's lift with stock's lever scale; SockFarTrim.cs 15.); without FAR = FBWAUTH;
//                                    FAR's own estimate when SockFarTrim lacks FAR's members (FBWAUTHSON FALSE)
//     ADDONS:KALS:FBWAUTHSON         TRUE: SockFarTrim computes StockAuth (FAR on, its members found)
//     ADDONS:KALS:FBWAUTHX           LIST of 12, deg/s2 (pitch, roll, yaw each): FBWAUTHS; the control surfaces' own
//                                    estimates (FAR's or stock's); the RCS; the rest (gimbals, wheels)
//     ADDONS:KALS:FBWCTRL            LIST(pitch, roll, yaw): the vessel's final controls of the last frame
//     ADDONS:KALS:YAWJET(u)          the yaw alone (-1..1, + = nose right), as FBW3's yaw
//     ADDONS:KALS:YAWJETAXES(on)     TRUE: every RCS part on yaw only (pitch, roll, translation off, each part's own kept);
//                                    FALSE: the jets off, the command 0, the handler removed, each part's own axes back
//     ADDONS:KALS:YAWJETPILOT        the pilot's yaw (-1..1, + = nose right) at the handler's last call
//     ADDONS:KALS:YAWJETGMB          TRUE: this DLL reads the pilot's input from the gimbal
//     ADDONS:KALS:FBWXOFF            the vessel's translation held at 0 from now (dropped 0.5 s after the last call);
//                                    TRUE
//     ADDONS:KALS:FBWXPILOT          LIST(starboard, top, fore): the translation the handler was handed at its last call
//                                    while FBWXOFF holds (kOS's PILOT* signs), else 0
// The ascent DAP (KalsAddon.AscDap.cs), the hand-off hold (KalsAddon.HoHold.cs) and ops2q's DAP (KalsAddon.O2Dap.cs)
// tick first in this handler while they are armed; FBW3, FBWOFF and YAWJETAXES(FALSE) release them (the next program's
// DAP has the axes).
// While an axis is commanded KSP.log gets the input's path once a second ("[KalsCoproc] input": KSP's reading of the devices, the
// input handed to this handler, the gimbals' actuation, the final input) and each hook's handlers once ("[KalsCoproc] hooks").
using System;
using System.Collections.Generic;
using System.Reflection;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        static Vessel yjVessel;
        static double yjCmd, yjT = -1E9, yjPilot, yjTrim;
        static double yjFixT = double.NaN;          // Time.fixedTime at the last handler call (NaN = none since the axes went on)
        internal static int YjQuiet;                // ticks the DAP stays quiet after a gap (the vessel was packed)
        static ModuleGimbal yjGmb;                      // the gimbal the pilot's yaw is read from
        static double yjLogT = -1E9;
        static int yjRejects;
        static bool yjOrderLogged;
        internal static double YjPilotYaw { get { return yjPilot; } }
        static readonly Dictionary<ModuleRCS, bool[]> yjSaved = new Dictionary<ModuleRCS, bool[]>();
        // pitch [0] and roll [1], as the yaw's
        static readonly double[] fbCmd = new double[2], fbPilot = new double[2], fbTrim = new double[2];
        static readonly double[] fbT = { -1E9, -1E9 };
        static ModuleGimbal fbGmb;                      // the gimbal the pilot's pitch and roll are read from
        static double fxT = -1E9;                       // FBWXOFF's last call: the translation held at 0 0.5 s from it
        static readonly double[] fxPilot = new double[3];   // the translation as handed (starboard, top, fore)

        partial void RegisterYawJet()
        {
            AddSuffix("FBW3", new ThreeArgsSuffix<ScalarValue, ScalarValue, ScalarValue, ScalarValue>((p, r, y) =>
            {
                FbSet(shared.Vessel, p.GetDoubleValue(), r.GetDoubleValue(), y.GetDoubleValue());
                return ScalarValue.Create(0);
            }));
            AddSuffix("FBWPILOT", new Suffix<ListValue>(() => FbList(fbPilot[0], fbPilot[1], yjPilot)));
            AddSuffix("FBWOFF", new Suffix<BooleanValue>(() => { FbOff(); return new BooleanValue(true); }));
            AddSuffix("FBWAUTH", new Suffix<ListValue>(() => FbAuth(shared.Vessel)));
            AddSuffix("FBWAUTHSON", new Suffix<BooleanValue>(() => new BooleanValue(FtStockOn(FarTrim(shared.Vessel)))));
            AddSuffix("FBWAUTHX", new Suffix<ListValue>(() =>
            {
                double[] g = FbAuthG(shared.Vessel);
                var l = new ListValue();
                foreach (double x in g) l.Add(ScalarValue.Create(x));
                return l;
            }));
            // the vessel's final pitch, roll, yaw of the last frame (what kOS's steering commanded): the ascent's CSS seeds
            // its integrators with it, so taking the axes over is bumpless
            AddSuffix("FBWCTRL", new Suffix<ListValue>(() => { Vessel v = shared.Vessel; return v == null ? FbList(0, 0, 0) : FbList(v.ctrlState.pitch, v.ctrlState.roll, v.ctrlState.yaw); }));
            AddSuffix("YAWJET", new OneArgsSuffix<ScalarValue, ScalarValue>(u => { YjSet(shared.Vessel, u.GetDoubleValue()); return u; }));
            AddSuffix("YAWJETAXES", new OneArgsSuffix<BooleanValue, BooleanValue>(b => { YjAxes(shared.Vessel, b.Value); return b; }));
            AddSuffix("YAWJETPILOT", new Suffix<ScalarValue>(() => ScalarValue.Create(yjPilot)));
            AddSuffix("YAWJETGMB", new Suffix<BooleanValue>(() => new BooleanValue(true)));
            AddSuffix("FBWXOFF", new Suffix<BooleanValue>(() => { FxSet(shared.Vessel); return new BooleanValue(true); }));
            AddSuffix("FBWXPILOT", new Suffix<ListValue>(() => FbList(fxPilot[0], fxPilot[1], fxPilot[2])));
        }

        static void YjSet(Vessel v, double u)
        {
            yjCmd = double.IsNaN(u) || double.IsInfinity(u) ? 0 : Math.Max(-1, Math.Min(1, u));
            yjT = Planetarium.GetUniversalTime();
            FbHook(v);
        }

        // the handler subscribed last on v (re-added at every call, so it runs after every other handler)
        static void FbHook(Vessel v)
        {
            if (v == null) return;
            if (yjVessel != null && yjVessel != v) yjVessel.OnFlyByWire -= YjFbw;
            v.OnFlyByWire -= YjFbw;
            v.OnFlyByWire += YjFbw;
            yjVessel = v;
        }

        // FBWXOFF: the translation held at 0 for 0.5 s from now
        static void FxSet(Vessel v)
        {
            fxT = Planetarium.GetUniversalTime();
            FbHook(v);
        }

        static double FbClamp(double u) { return double.IsNaN(u) || double.IsInfinity(u) ? 0 : Math.Max(-1, Math.Min(1, u)); }

        static ListValue FbList(double p, double r, double y)
        {
            var l = new ListValue();
            l.Add(ScalarValue.Create(p)); l.Add(ScalarValue.Create(r)); l.Add(ScalarValue.Create(y));
            return l;
        }

        // the three axes at once; the yaw goes through YjSet (which also puts the handler last)
        static void FbSet(Vessel v, double p, double r, double y)
        {
            HoOff("FBW3");                              // the next DAP flies
            AsdOff("FBW3");
            O2dOff("FBW3");
            double now = Planetarium.GetUniversalTime();
            fbCmd[0] = FbClamp(p); fbCmd[1] = FbClamp(r);
            fbT[0] = now; fbT[1] = now;
            YjSet(v, y);
        }

        // the authority a full command has now, LIST(pitch, roll, yaw) in deg/s2: every ITorqueProvider's potential
        // torque (RCS, wheels, the surfaces at today's q, lit gimbals; stock's and FAR's own estimates, as kOS's steering
        // reads them) over the vessel's moment of inertia, both in its control frame (x pitch, y roll, z yaw)
        static ListValue FbAuth(Vessel v)
        {
            if (v == null) return FbList(0, 0, 0);
            Vector3 pos = Vector3.zero, neg = Vector3.zero;
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ITorqueProvider tp = m as ITorqueProvider;
                    if (tp == null || !m.isEnabled) continue;
                    Vector3 a, b;
                    try { tp.GetPotentialTorque(out a, out b); } catch (Exception) { continue; }
                    pos += new Vector3(Math.Abs(a.x), Math.Abs(a.y), Math.Abs(a.z));
                    neg += new Vector3(Math.Abs(b.x), Math.Abs(b.y), Math.Abs(b.z));
                }
            Vector3 moi = v.MOI;
            double[] r = new double[3];
            for (int i = 0; i < 3; i++)
            {
                double t = 0.5 * (pos[i] + neg[i]), j = moi[i];
                r[i] = j > 1E-6 && !double.IsNaN(t) && !double.IsInfinity(t) ? t / j * 180.0 / Math.PI : 0;   // kN m / t m2
            }
            return FbList(r[0], r[1], r[2]);
        }

        // the vessel's SockFarTrim (null without FAR or without SOCK RealAero), by name: it is SOCK RealAero's
        // (Plugins/SockRealAero.dll), so this DLL loads and runs without it
        static PartModule FarTrim(Vessel v)
        {
            if (v == null) return null;
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                    if (m.GetType().Name == "SockFarTrim") return m;
            return null;
        }

        // a public no-argument method of SockFarTrim (StockAuth, StockAuthOn): its result, or null
        static object FtCall(PartModule ft, string name)
        {
            if (ft == null) return null;
            MethodInfo mi = ft.GetType().GetMethod(name, BindingFlags.Public | BindingFlags.Instance, null, Type.EmptyTypes, null);
            try { return mi != null ? mi.Invoke(ft, null) : null; } catch (Exception) { return null; }
        }

        // SockFarTrim.StockAuthOn: TRUE when it computes StockAuth
        static bool FtStockOn(PartModule ft)
        {
            object on = FtCall(ft, "StockAuthOn");
            return on is bool && (bool)on;
        }

        // FBWAUTHS and FBWAUTHX's groups (deg/s2): [0-2] FBWAUTHS, [3-5] the control surfaces' own estimates, [6-8] the
        // RCS, [9-11] the rest; under FAR FBWAUTHS = RCS + rest + SockFarTrim.StockAuth (its members found), else RCS +
        // rest + surfaces
        static double[] FbAuthG(Vessel v)
        {
            var r = new double[12];
            if (v == null) return r;
            Vector3d[] g = new Vector3d[3];
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ITorqueProvider tp = m as ITorqueProvider;
                    if (tp == null || !m.isEnabled) continue;
                    Vector3 a, b;
                    try { tp.GetPotentialTorque(out a, out b); } catch (Exception) { continue; }
                    string cn = m.GetType().Name;
                    int k = cn == "FARControllableSurface" || m is ModuleControlSurface ? 0 : m is ModuleRCS ? 1 : 2;
                    g[k] += 0.5 * new Vector3d(Math.Abs(a.x) + Math.Abs(b.x), Math.Abs(a.y) + Math.Abs(b.y), Math.Abs(a.z) + Math.Abs(b.z));
                }
            PartModule ft = FarTrim(v);
            object sa = FtStockOn(ft) ? FtCall(ft, "StockAuth") : null;
            Vector3d s = sa is Vector3d ? (Vector3d)sa : g[0];
            Vector3 moi = v.MOI;
            Vector3d[] all = { s + g[1] + g[2], g[0], g[1], g[2] };
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 3; i++)
                {
                    double t = all[j][i], mi = moi[i];
                    r[3 * j + i] = mi > 1E-6 && !double.IsNaN(t) && !double.IsInfinity(t) ? t / mi * 180.0 / Math.PI : 0;
                }
            return r;
        }

        // every axis off, the handler removed; the RCS axes are YAWJETAXES's and stay as they are
        static void FbOff()
        {
            HoOff("FBWOFF");
            AsdOff("FBWOFF");
            O2dOff("FBWOFF");
            PxOff("FBWOFF");
            yjCmd = 0; yjPilot = 0; yjTrim = 0; yjT = -1E9;
            for (int i = 0; i < 2; i++) { fbCmd[i] = 0; fbPilot[i] = 0; fbTrim[i] = 0; fbT[i] = -1E9; }
            fxT = -1E9; fxPilot[0] = 0; fxPilot[1] = 0; fxPilot[2] = 0;
            yjGmb = null; fbGmb = null;
            yjOrderLogged = false;
            if (yjVessel != null) yjVessel.OnFlyByWire -= YjFbw;
            yjVessel = null;
            Debug.Log("[KalsCoproc] fly-by-wire off: pitch, roll, yaw and translation back to the pilot");
        }

        static void YjFbw(FlightCtrlState s)
        {
            double now = Planetarium.GetUniversalTime();
            float hp = s.pitch, hr = s.roll, hy = s.yaw;
            YjFbwCore(s, now);
            InTrace(s, now, hp, hr, hy);
        }

        // the input's path, logged at most once a second while an axis is commanded: KSP's own reading of the devices
        // (FlightInputHandler.state, its trims included), the input this handler was handed (every earlier handler's work in
        // it), the gimbals' actuation (the vessel's final input at their last update), this handler's final input last tick
        // and now; each hook's handlers listed once per arming
        static double inTrT = -1E9;
        static Vector3 inFin;
        static bool inListed;

        static string InV3(double x, double y, double z)
        {
            return "(" + x.ToString("F3") + " " + y.ToString("F3") + " " + z.ToString("F3") + ")";
        }

        static string Hooks(Delegate d)
        {
            if (d == null) return "none";
            var names = new List<string>();
            foreach (Delegate h in d.GetInvocationList())
                names.Add((h.Method.DeclaringType != null ? h.Method.DeclaringType.Name + "." : "") + h.Method.Name);
            return string.Join(", ", names.ToArray());
        }

        // Diagnostic: once a second while an axis is commanded, what the command DID: our output and the DAP's
        // commands, the RCS modules that can act (enabled, per axis group) and the thrust they actually fire (ModuleRCS.thrustForces), and the
        // measured angular acceleration over the last second (vessel-local rates, the control frame's x pitch / y roll / z yaw as FbAuth reads it)
        // against u x au. A command that is handed on but fires no thruster = something after our handler rewrote it; thrust but no acceleration
        // = a torque that cancels; no enabled roll thruster = the jet selection.
        static Vector3 dgW; static double dgT = -1E9;
        static void DgTrace(Vessel v, FlightCtrlState s, double now)
        {
            if (v == null) return;
            int n = 0, en = 0, pe = 0, re = 0, ye = 0, fire = 0; double thr = 0;
            bool shuttle = PayloadRcs.IsShuttle(v);
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ModuleRCS r = m as ModuleRCS;
                    if (r == null || PayloadRcs.IsPayload(shuttle, p)) continue;          // T1017: the orbiter's jets only
                    n++;
                    if (!r.isEnabled || !r.rcsEnabled) continue;
                    en++;
                    if (r.enablePitch) pe++;
                    if (r.enableRoll) re++;
                    if (r.enableYaw) ye++;
                    if (r.thrustForces != null)
                        foreach (float f in r.thrustForces) if (f > 1e-4f) { fire++; thr += f; }
                }
            Vector3 w = v.angularVelocity;
            double dt = now - dgT;
            string acc = "n/a";
            if (dt > 0.2 && dt < 3)
            {
                Vector3 a = (w - dgW) * (float)(180.0 / Math.PI / dt);
                acc = InV3(a.x, a.y, a.z);
            }
            dgW = w; dgT = now;
            Debug.Log("[KalsCoproc] t794: out " + InV3(s.pitch, s.roll, s.yaw) + " dap cmd " + InV3(fbCmd[0], fbCmd[1], yjCmd) + " | rcs modules " + n + " enabled " + en
                      + " (pitch " + pe + " roll " + re + " yaw " + ye + "), firing " + fire + " thrusters " + thr.ToString("F4") + " kN | accel (p r y) " + acc
                      + " deg/s2 over " + dt.ToString("F2") + " s | u x au roll " + (fbCmd[1] * o2dAu.y).ToString("F4") + " pitch " + (fbCmd[0] * o2dAu.x).ToString("F4")
                      + " (au " + InV3(o2dAu.x, o2dAu.y, o2dAu.z) + ") | RCS " + v.ActionGroups[KSPActionGroup.RCS] + " SAS " + v.ActionGroups[KSPActionGroup.SAS]
                      + " mode " + v.Autopilot.Mode + " ctrlState " + InV3(v.ctrlState.pitch, v.ctrlState.roll, v.ctrlState.yaw));
        }

        static void InTrace(FlightCtrlState s, double now, float hp, float hr, float hy)
        {
            bool on = now - yjT <= 0.5 || now - fbT[0] <= 0.5 || now - fbT[1] <= 0.5;
            if (!on) inListed = false;
            else if (now - inTrT >= 1 || now < inTrT)        // a stamp ahead of now: a save from earlier in time
            {
                inTrT = now;
                FlightCtrlState k = FlightInputHandler.state;
                string dev = k == null ? "none" : InV3(k.pitch, k.roll, k.yaw) + " trim " + InV3(k.pitchTrim, k.rollTrim, k.yawTrim);
                string gf = fbGmb == null ? "none" : InV3(fbGmb.actuation.x, fbGmb.actuation.y, fbGmb.actuation.z)
                            + (fbGmb.gimbalActive ? "" : " inactive");
                string gy = yjGmb == null ? "none" : yjGmb.actuation.z.ToString("F3") + (yjGmb.gimbalActive ? "" : " inactive");
                Debug.Log("[KalsCoproc] input: devices " + dev + " handed " + InV3(hp, hr, hy) + " gimbal " + gf
                          + " yaw gimbal " + gy + " final last tick " + InV3(inFin.x, inFin.y, inFin.z)
                          + " final " + InV3(s.pitch, s.roll, s.yaw));
                DgTrace(yjVessel, s, now);
                if (!inListed && yjVessel != null)
                {
                    inListed = true;
                    Debug.Log("[KalsCoproc] hooks: pre-autopilot " + Hooks(yjVessel.OnPreAutopilotUpdate) + "; autopilot "
                              + Hooks(yjVessel.OnAutopilotUpdate) + "; post-autopilot " + Hooks(yjVessel.OnPostAutopilotUpdate)
                              + "; fly-by-wire " + Hooks(yjVessel.OnFlyByWire));
                }
            }
            inFin = new Vector3(s.pitch, s.roll, s.yaw);
        }

        static void YjFbwCore(FlightCtrlState s, double now)
        {
            // A gap in the physics ticks = the vessel was packed. Its first ticks read rate 0 and gimbal actuation 0 (the last pre-pack trim then looks like a pilot's
            // input of -0.05: RHC OUT OF DETENT), so the pilot readback restarts from zero and the DAP is quiet for RailsCore.QuietTicks ticks.
            double ft = Time.fixedTime;
            if (!double.IsNaN(yjFixT) && RailsCore.TickGap(yjFixT, ft, Time.fixedDeltaTime))
            {
                YjQuiet = RailsCore.QuietTicks;
                fbPilot[0] = 0; fbPilot[1] = 0; yjPilot = 0; fbTrim[0] = 0; fbTrim[1] = 0; yjTrim = 0;
            }
            yjFixT = ft;
            if (pxOn) PxPre(now);                       // STKP: the target read, its axes into the DAP's TGT frame
            if (asdOn) AsdTick(s, now);                 // the ascent DAP sets the axes' commands
            if (hoOn) HoTick(s, now);                   // the hand-off hold sets the axes' commands
            if (o2dOn) O2dTick(s, now);                 // ops2q's DAP sets the axes' commands
            if (now - fxT <= 0.5)                       // FBWXOFF: the translation read (kOS's signs), then held at 0
            {
                fxPilot[0] = -s.X; fxPilot[1] = s.Y; fxPilot[2] = -s.Z;
                s.X = 0; s.Y = 0; s.Z = 0;
            }
            else { fxPilot[0] = 0; fxPilot[1] = 0; fxPilot[2] = 0; }
            if (pxOn) PxTick(s, now);                   // STKP: the translation command (after FBWXOFF's zeroing)
            bool yOn = now - yjT <= 0.5;
            bool pOn = now - fbT[0] <= 0.5, rOn = now - fbT[1] <= 0.5;   // each axis its own timeout
            if (!yOn) { yjPilot = 0; yjTrim = 0; }
            if (!pOn) { fbPilot[0] = 0; fbTrim[0] = 0; }
            if (!rOn) { fbPilot[1] = 0; fbTrim[1] = 0; }
            if (pOn || rOn) FbPitchRoll(s, now, pOn, rOn);
            if (!yOn) return;
            if (!yjOrderLogged && yjVessel != null && yjVessel.OnFlyByWire != null)
            {
                yjOrderLogged = true;
                var names = new List<string>();
                foreach (Delegate h in yjVessel.OnFlyByWire.GetInvocationList())
                    names.Add((h.Method.DeclaringType != null ? h.Method.DeclaringType.Name + "." : "") + h.Method.Name);
                Debug.Log("[KalsCoproc] yaw jets: OnFlyByWire order " + string.Join(", ", names.ToArray()));
            }
            // the pilot's yaw = the OMS gimbal's yaw (the vessel's final yaw last frame) less last frame's trim
            double g;
            string why = null;
            bool haveY = YjGimbalYaw(out g);
            if (!haveY) why = "no reading yaw gimbal: the yaw as handed";
            {
                double p = haveY ? g - yjTrim : s.yaw;
                if (double.IsNaN(p) || Math.Abs(p) > 1.02) { yjRejects++; yjPilot = 0; why = "rejected " + p.ToString("F3"); }
                else yjPilot = Math.Max(-1, Math.Min(1, p));
            }
            if ((why != null || Math.Abs(s.yaw) > 1.0001) && (now - yjLogT > 1 || now < yjLogT))
            {
                yjLogT = now;
                Debug.Log("[KalsCoproc] yaw: handed " + s.yaw.ToString("F3") + " gimbal " + g.ToString("F3") + " trim "
                          + yjTrim.ToString("F3") + " pilot " + yjPilot.ToString("F3") + " (" + (why ?? "ok") + "; rejects "
                          + yjRejects + ")");
            }
            yjTrim = Mathf.Clamp((float)yjCmd, -1f, 1f) - s.yaw;   // the trim that leaves the DAP's command alone
            s.yaw = Mathf.Clamp(s.yaw + (float)yjTrim, -1f, 1f);
        }

        // pitch and roll as the yaw (the gimbal readback, the trim), each only while its axis is commanded
        static void FbPitchRoll(FlightCtrlState s, double now, bool pOn, bool rOn)
        {
            Vector3 a = Vector3.zero;
            bool have = FbGimbal(out a);
            string why = have ? null : "no reading 3-axis gimbal: the input as handed";
            for (int i = 0; i < 2; i++)
            {
                if (!(i == 0 ? pOn : rOn)) continue;
                double handed = i == 0 ? s.pitch : s.roll;
                {
                    double p = have ? (i == 0 ? a.x : a.y) - fbTrim[i] : handed;
                    if (double.IsNaN(p) || Math.Abs(p) > 1.02) { yjRejects++; fbPilot[i] = 0; why = (i == 0 ? "pitch" : "roll") + " rejected " + p.ToString("F3"); }
                    else fbPilot[i] = Math.Max(-1, Math.Min(1, p));
                }
                if ((why != null || Math.Abs(handed) > 1.0001) && (now - yjLogT > 1 || now < yjLogT))
                {
                    yjLogT = now;
                    Debug.Log("[KalsCoproc] " + (i == 0 ? "pitch" : "roll") + ": handed " + handed.ToString("F3") + " trim "
                              + fbTrim[i].ToString("F3") + " pilot " + fbPilot[i].ToString("F3") + " (" + (why ?? "ok")
                              + "; rejects " + yjRejects + ")");
                }
                fbTrim[i] = Mathf.Clamp((float)fbCmd[i], -1f, 1f) - handed;
                float u = Mathf.Clamp((float)(handed + fbTrim[i]), -1f, 1f);
                if (i == 0) s.pitch = u; else s.roll = u;
            }
        }

        // an unlocked, enabled gimbal on the vessel with pitch, roll and yaw (pr) or the yaw alone enabled
        static bool GmbFits(ModuleGimbal mg, bool pr)
        {
            return mg != null && mg.part != null && mg.vessel == yjVessel && !mg.gimbalLock && mg.moduleIsEnabled
                   && mg.enableYaw && (!pr || (mg.enablePitch && mg.enableRoll));
        }

        // the readback's gimbal: one that fits and reads (gimbalActive) first, else the first that fits, switched on
        static ModuleGimbal GmbFind(bool pr)
        {
            ModuleGimbal off = null;
            foreach (Part p in yjVessel.parts)
            {
                foreach (PartModule m in p.Modules)
                {
                    ModuleGimbal mg = m as ModuleGimbal;
                    if (!GmbFits(mg, pr)) continue;
                    if (mg.gimbalActive) return mg;
                    if (off == null) off = mg;
                }
            }
            return off;
        }

        // FALSE when the gimbal had to be switched on now (its actuation is from before: not a reading yet)
        static bool GmbReads(ModuleGimbal mg)
        {
            if (mg.gimbalActive) return true;
            mg.gimbalActive = true;
            Debug.Log("[KalsCoproc] fly-by-wire: the gimbal on " + mg.part.partInfo.title
                      + " switched on to read the pilot's input (its engine never activated)");
            return false;
        }

        // the pilot's pitch and roll gimbal (its actuation = vessel.ctrlState at its last update)
        static bool FbGimbal(out Vector3 a)
        {
            a = Vector3.zero;
            if (yjVessel == null) return false;
            if (!GmbFits(fbGmb, true))
            {
                fbGmb = GmbFind(true);
                if (fbGmb == null) return false;
                Debug.Log("[KalsCoproc] fly-by-wire: the pilot's pitch and roll from the gimbal on " + fbGmb.part.partInfo.title);
            }
            if (!GmbReads(fbGmb)) return false;
            a = fbGmb.actuation;
            return !(float.IsNaN(a.x) || float.IsNaN(a.y) || float.IsInfinity(a.x) || float.IsInfinity(a.y));
        }

        // the yaw of the pilot's yaw gimbal on the jets' vessel = vessel.ctrlState.yaw at its last update
        static bool YjGimbalYaw(out double g)
        {
            g = 0;
            if (yjVessel == null) return false;
            if (!GmbFits(yjGmb, false))
            {
                yjGmb = GmbFind(false);
                if (yjGmb == null) return false;
                Debug.Log("[KalsCoproc] yaw jets: the pilot's yaw from the gimbal on " + yjGmb.part.partInfo.title);
            }
            if (!GmbReads(yjGmb)) return false;
            g = yjGmb.actuation.z;
            return !(double.IsNaN(g) || double.IsInfinity(g));
        }

        static void YjAxes(Vessel v, bool on)
        {
            if (!on)
            {
                HoOff("YAWJETAXES");
                AsdOff("YAWJETAXES");
                O2dOff("YAWJETAXES");
                yjCmd = 0;
                yjPilot = 0;
                yjTrim = 0;
                yjGmb = null;
                for (int i = 0; i < 2; i++) { fbCmd[i] = 0; fbPilot[i] = 0; fbTrim[i] = 0; fbT[i] = -1E9; }
                fxT = -1E9; fxPilot[0] = 0; fxPilot[1] = 0; fxPilot[2] = 0;
                fbGmb = null;
                yjOrderLogged = false;
                yjFixT = double.NaN; YjQuiet = 0;
                if (yjVessel != null) yjVessel.OnFlyByWire -= YjFbw;
                yjVessel = null;
                foreach (var kv in yjSaved)
                {
                    if (kv.Key == null) continue;
                    ModuleRCS r = kv.Key; bool[] a = kv.Value;
                    r.enablePitch = a[0]; r.enableRoll = a[1]; r.enableX = a[2]; r.enableY = a[3]; r.enableZ = a[4];
                }
                Debug.Log("[KalsCoproc] yaw jets off: " + yjSaved.Count + " RCS parts' own axes back");
                yjSaved.Clear();
                return;
            }
            if (v == null) return;
            bool shuttle = PayloadRcs.IsShuttle(v);
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ModuleRCS r = m as ModuleRCS;
                    if (r == null || yjSaved.ContainsKey(r) || PayloadRcs.IsPayload(shuttle, p)) continue;     // A payload's axes are not ours to set
                    yjSaved[r] = new[] { r.enablePitch, r.enableRoll, r.enableX, r.enableY, r.enableZ };
                    r.enablePitch = false; r.enableRoll = false; r.enableX = false; r.enableY = false; r.enableZ = false;
                }
            Debug.Log("[KalsCoproc] yaw jets on: " + yjSaved.Count + " RCS parts on yaw only");
        }
    }
}
