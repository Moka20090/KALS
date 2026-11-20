// PROX OPS, STKP in the game: the target station-keeping (StationKeep.cs, plain C#, tested offline in tests/proxops_offline) fed from the
// game and flown in the fly-by-wire handler every physics tick (KalsAddon.YawJet.cs YjFbwCore: PxPre before the DAPs, PxTick after the FBWXOFF block).
//     ADDONS:KALS:PROXSET(mode) -> "" or "error ...":  0 = off; 1 = STKP, 2 = STKP + CSS NORM, 3 = STKP + CSS PULSE (CSS: the pilot's THC moves the hold point, see
//         StationKeep.cs; the mode changes without a new engage while STKP is on); 1.. = engage on the TARGET (FlightGlobals.fetch.VesselTarget: a vessel or one of its docking
//         ports): NULL the relative velocity, then HOLD the point we are at (fixed in the target's frame, inside a box). A refusal says why (range over
//         200 m, closing over 1 m/s, no target / not in physics range).
//     ADDONS:KALS:PROXCYC -> LIST(on, phase, msg, target name, range m, closing rate m/s (+ = closing), |position error| m, |velocity error| m/s,
//         firing, authority x, y, z (m/s2 at command 1, learned), attitude in INRTL (target too fast), target valid, CSS mode 0 / 1 NORM / 2 PULSE): the keep-alive (kOS calls it
//         every cycle) + the state; msg = the event since the last call (cleared).
//     THE WATCHDOG: PX_WATCH handler ticks without a PROXSET / PROXCYC (kOS ended or crashed) = STKP lets go; FBWOFF lets go too.
// THE ATTITUDE: while STKP is on and the ops2q DAP (KalsAddon.O2Dap.cs) is on, its reference frame is the TARGET's body axes (O2Dap.Basis "TGT", the
//     static O2Dap.TgtBasis set here every tick): an attitude hold keeps the same attitude relative to a turning target. A target turning faster than the
//     attitude can follow (StationKeep.AttInrtl) puts the frame back to INRTL until it slows. O2DAPSET's rf is ignored while STKP is on (the reference
//     itself is kept in world axes at the set).
// THE JETS: the translation goes into the flight control state (s.X = -star, s.Y = top, s.Z = -fore: the inverse of FBWXPILOT's (-s.X, s.Y, -s.Z)),
//     replacing the pilot's THC (CSS = step 3). The signs are proved in flight only (test harness); the RCS group must be on.
// Frames: every vector is in the game's world axes (inertial: obt_velocity, CoMD). r, v = the orbiter's CoM relative to the target point (the vessel's
//     CoM, or the docking port's transform); v = our obt_velocity - (the target's obt_velocity + wT x (point - the target's CoM)).
// Real Shuttle: the real orbiter had no automatic translation station-keeping (prox ops were flown by hand): STKP is a KAL/S aid.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        const int PX_WATCH = 100;                       // handler ticks (2 s at 50 Hz) without a kOS call: let go
        static readonly StationKeep pxC = new StationKeep();
        static bool pxOn, pxTgtFrame, pxValid, pxOrb;   // pxOrb: STICK ORB, pushed by kOS on every change (PROXSTICK)
        static int pxIdle, pxMsgSeen;
        static double pxT = -1;
        static string pxMsg = "", pxName = "";
        static SkV pxR, pxV, pxWT;
        static SkM pxB, pxBd;

        partial void RegisterProx()
        {
            AddSuffix("PROXSET", new OneArgsSuffix<StringValue, ScalarValue>(m => new StringValue(PxSet(shared.Vessel, m.GetDoubleValue()))));
            AddSuffix("PROXCYC", new Suffix<ListValue>(() => PxCyc()));
            AddSuffix("PROXSTICK", new OneArgsSuffix<StringValue, BooleanValue>(b => { pxOrb = b.Value; return new StringValue(""); }));   // TRUE = STICK ORB (the RHC is the DAP's), FALSE = STICK ARM (the RHC is the arm's: while STKP is on the DAP sees none)
        }

        static SkV PxSk(Vector3d a) { return new SkV(a.x, a.y, a.z); }
        static Vector3d PxV3(SkV a) { return new Vector3d(a.X, a.Y, a.Z); }

        // a vessel's body axes (star, top, fore) and its turn rate, all in world axes (as O2dTick reads the orbiter's)
        static void PxAxes(Vessel x, out SkM basis, out SkV w)
        {
            Quaternion F = x.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
            Vector3 wl = x.angularVelocity;
            Vector3 ww = F * new Vector3(wl.x, -wl.z, wl.y);
            basis = new SkM(PxSk((Vector3d)(F * Vector3.right)), PxSk((Vector3d)(F * Vector3.up)), PxSk((Vector3d)(F * Vector3.forward)));
            w = new SkV(ww.x, ww.y, ww.z);
        }

        // the target and the orbiter now; false = no usable target (none, not loaded, packed, this vessel)
        static bool PxRead(Vessel v, out SkV r, out SkV vel, out SkM B, out SkV wT, out SkM Bd, out string name)
        {
            r = vel = wT = new SkV(0, 0, 0); B = Bd = SkM.Identity; name = "";
            ITargetable tg = FlightGlobals.fetch != null ? FlightGlobals.fetch.VesselTarget : null;
            if (v == null || tg == null) return false;
            Vessel tv = tg.GetVessel();
            if (tv == null || tv == v || !tv.loaded || tv.packed || tv.ReferenceTransform == null || v.ReferenceTransform == null) return false;
            ModuleDockingNode dn = tg as ModuleDockingNode;
            Vector3d pT = dn != null && dn.nodeTransform != null ? (Vector3d)dn.nodeTransform.position : tv.CoMD;
            SkV wTv;
            PxAxes(tv, out B, out wTv);
            wT = wTv;
            SkV dummy;
            PxAxes(v, out Bd, out dummy);
            SkV pointV = PxSk(tv.obt_velocity) + wTv.Cross(PxSk(pT - tv.CoMD));
            r = PxSk(v.CoMD - pT);
            vel = PxSk(v.obt_velocity) - pointV;
            name = dn != null ? tv.vesselName + " " + (dn.part != null ? dn.part.partInfo.title : "port") : tv.vesselName;
            return true;
        }

        static string PxSet(Vessel v, double mode)
        {
            try
            {
                if (mode <= 0) { PxOff("PROXSET 0"); return ""; }
                if (v == null) return "error no vessel";
                int cm = mode >= 3 ? 2 : (mode >= 2 ? 1 : 0);
                if (pxOn) { pxC.CssMode = cm; pxIdle = 0; return ""; }              // already on: only the stick mode
                SkV r, vel, wT; SkM B, Bd; string nm;
                if (!PxRead(v, out r, out vel, out B, out wT, out Bd, out nm)) return "error no target in physics range";
                O2Dap.TgtBasis = new[] { PxV3(B.C0), PxV3(B.C1), PxV3(B.C2) };
                if (!pxC.Engage(r, vel, B, wT)) return "error " + StationKeep.MsgText(pxC.Msg);
                pxOn = true; pxIdle = 0; pxT = -1; pxName = nm; pxValid = true;
                pxVes = v;
                pxC.CssMode = cm;
                pxR = r; pxV = vel; pxWT = wT; pxB = B; pxBd = Bd;
                pxMsgSeen = pxC.Msg; pxMsg = StationKeep.MsgText(pxC.Msg);
                PxFrame(v, !pxC.AttInrtl);
                FbHook(v);
                Debug.Log("[KalsCoproc] STKP on: target " + nm + " range " + r.Mag.ToString("F1") + " m rate " + vel.Mag.ToString("F3") + " m/s, tgt turn " + (wT.Mag * 180 / Math.PI).ToString("F2") + " deg/s");
                return "";
            }
            catch (Exception ex) { return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        static ListValue PxCyc()
        {
            pxIdle = 0;
            var l = new ListValue();
            l.Add(new BooleanValue(pxOn)); l.Add(ScalarValue.Create(pxC.Phase)); l.Add(new StringValue(pxMsg)); l.Add(new StringValue(pxName));
            l.Add(ScalarValue.Create(pxC.Range)); l.Add(ScalarValue.Create(-pxC.RDot));
            l.Add(ScalarValue.Create(pxC.ErrP.Mag)); l.Add(ScalarValue.Create(pxC.ErrV.Mag)); l.Add(new BooleanValue(pxC.Firing));
            l.Add(ScalarValue.Create(pxC.Auth[0])); l.Add(ScalarValue.Create(pxC.Auth[1])); l.Add(ScalarValue.Create(pxC.Auth[2]));
            l.Add(new BooleanValue(pxC.AttInrtl)); l.Add(new BooleanValue(pxValid)); l.Add(ScalarValue.Create(pxC.CssMode));
            // Diagnostics (appended, kOS reads only items 0-14): [15-17] position error, [18-20] velocity error, in the orbiter's body axes (star, top, fore);
            // [21-23] the DELIVERED command (after the dither), [24-26] the learned disturbance acceleration, [27] the dither floor
            for (int i = 0; i < 3; i++) l.Add(ScalarValue.Create(pxC.ErrPb[i]));
            for (int i = 0; i < 3; i++) l.Add(ScalarValue.Create(pxC.ErrVb[i]));
            for (int i = 0; i < 3; i++) l.Add(ScalarValue.Create(pxC.LastU[i]));
            for (int i = 0; i < 3; i++) l.Add(ScalarValue.Create(pxC.Dist[i]));
            l.Add(ScalarValue.Create(pxC.Floor));
            pxMsg = "";
            return l;
        }

        // the ops2q DAP's frame: the target's axes (tgt) or inertial; the reference attitude kept in the world axes across the switch
        static void PxFrame(Vessel v, bool tgt)
        {
            pxTgtFrame = tgt;
            if (!o2dOn || v == null) return;
            string want = tgt ? "TGT" : "INRTL";
            if (o2dC.rf == want) return;
            Vector3d[] g = O2dGeo(v);
            Vector3d f = o2dC.RefF(g), t = o2dC.RefT(g);               // in the old frame
            o2dC.rf = want; o2dC.bp = null; o2dC.wf = Vector3d.zero; o2dC.ui = Vector3d.zero;
            o2dC.RefSet(f, t, g);
        }

        // The RHC the DAP sees this frame (O2dTick): zero while STKP is on with STICK ARM (the stick is the arm's), else as kOS's stk says; one log line a
        // second while a deflection is withheld
        static double pxGateT = -1E9;
        static Vector3d PxStickForDap(bool stk, Vector3d raw, double now)
        {
            if (StationKeep.StickToDap(pxOn, pxOrb, stk)) return raw;
            if (stk && pxOn && Math.Max(Math.Abs(raw.x), Math.Max(Math.Abs(raw.y), Math.Abs(raw.z))) > 0.1 && (now - pxGateT > 1 || now < pxGateT))
            {
                pxGateT = now;
                Debug.Log("[KalsCoproc] STKP: the RHC withheld from the DAP (STICK ARM): raw " + raw.x.ToString("F2") + " " + raw.y.ToString("F2") + " " + raw.z.ToString("F2"));
            }
            return Vector3d.zero;
        }

        static Vessel pxVes;                            // The vessel PROXSET engaged on

        static void PxOff(string why)
        {
            if (!pxOn) return;
            Vessel v = yjVessel;
            if (o2dOn && o2dC.rf == "TGT") PxFrame(v, false);          // before TgtBasis goes
            pxOn = false; pxTgtFrame = false; pxC.Disengage();
            O2Dap.TgtBasis = null;
            Debug.Log("[KalsCoproc] STKP off (" + why + ")");
        }

        // YjFbwCore, BEFORE the DAPs: the target and the orbiter now, the target's axes handed to the DAP's TGT frame
        static void PxPre(double now)
        {
            Vessel v = yjVessel;
            if (v == null) { PxOff("no vessel"); return; }
            if (++pxIdle > PX_WATCH) { PxOff("no kOS call for " + PX_WATCH + " ticks"); return; }
            if (v != pxVes && pxIdle > 5) { PxOff("another vessel, no kOS call: left on by a flight that ended"); return; }
            pxValid = PxRead(v, out pxR, out pxV, out pxB, out pxWT, out pxBd, out pxName);
            if (pxValid) O2Dap.TgtBasis = new[] { PxV3(pxB.C0), PxV3(pxB.C1), PxV3(pxB.C2) };
        }

        // YjFbwCore, AFTER the FBWXOFF block (which zeroes s.X / Y / Z): the translation command
        static void PxTick(FlightCtrlState s, double now)
        {
            Vessel v = yjVessel;
            double dt = pxT < 0 || now - pxT > 2 || now < pxT ? 0 : now - pxT;   // 0 after a gap
            pxT = now;
            // the pilot's THC in the orbiter's body axes (star, top, fore), as FBWXPILOT reads it: (-s.X, s.Y, -s.Z) as handed (FBWXOFF has moved it to fxPilot)
            SkV thc = now - fxT <= 0.5 ? new SkV(fxPilot[0], fxPilot[1], fxPilot[2]) : new SkV(-s.X, s.Y, -s.Z);
            SkV u = pxC.Tick(dt, pxValid, pxR, pxV, pxB, pxWT, pxBd, thc);
            if (pxC.Msg != pxMsgSeen)
            {
                pxMsgSeen = pxC.Msg;
                pxMsg = StationKeep.MsgText(pxC.Msg);
                Debug.Log("[KalsCoproc] STKP: " + pxMsg);
            }
            if (pxC.Phase == StationKeep.OFF) { PxOff("the core let go: " + pxMsg); return; }
            if (pxC.AttInrtl == pxTgtFrame) PxFrame(v, !pxC.AttInrtl);          // the target too fast / slow again: the DAP's frame follows next tick
            s.X = (float)FbClamp(-u.X); s.Y = (float)FbClamp(u.Y); s.Z = (float)FbClamp(-u.Z);
        }
    }
}
