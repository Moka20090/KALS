// ops2q's on-orbit DAP flown by C# every physics tick (the kOS loop was too slow and the pilot's inputs leaked through).
// O2Dap.cs is lib_o2dap's o2dTick ported 1:1; here it runs in the fly-by-wire
// handler (KalsAddon.YawJet.cs YjFbw, after the ascent DAP and the hand-off hold) and commands all three axes every
// tick, so none lapses back to the pilot (FBW3 drops an axis 0.5 s after its last call: ops2q called it once a cycle,
// 0.78 s in flight A, and the stick flew the orbiter between). kOS sets the mode, the hold, the reference, DB and RATE
// (O2DAPSET, after every crew action) and reads the state back once a cycle (O2DAPCYC) for the page and the log.
//     ADDONS:KALS:O2DAPSET(LIST(mode, hold, rf, act, fR, tR, ax, db, rate, tk[, k, tau, ki])) -> "" or "error ...": the DAP flies from
//         the next tick. The optional 11th..13th items are the hold's gains k (deg/s per deg, default O2Dap.K), tau (s, O2Dap.TAU)
//         and the integral trim ki (deg/s2 per deg.s, 0 = none): a list of 10 items = the defaults (an old DLL ignores the extras).
//         The optional 14th / 15th items are the pitch trim's SEED (deg/s2) and its counter: when the counter changes the pitch trim
//         ui.x is set to the seed and the sign guard (O2Dap.SEEDGT / SEEDGTH) watches it; O2DAPCYC's 18th item is 1 once the guard dropped it.
//         fR / tR the reference's FORE / TOP as world vectors (kOS's o2dOut of its ref), turned into this
//         DAP's own basis now; a new rf restarts the frame's rate (o2dFrame), tk FALSE zeroes the track's rate. Releases
//         the ascent DAP and the hand-off hold.
// The optional 16th item is the GIMBAL MODE (OmsGm.cs): 0 = off (today),
//         1 = the RCS group OFF while the lit engines give >= 80 % of their thrust (two engines: the gimbals and the wheels fly the
//         attitude), 2 = the same with the RCS roll jets kept (one engine: pitch / yaw jets disabled by ModuleRCS enablePitch /
//         enableYaw). The DAP's authority is read WITHOUT the RCS then (else its command would be sized for jets that do not fire).
//         The jets come back at the taper (< 50 % thrust), a locked gimbal, 3 s of error over 3 deg, an RCS switched on from outside,
//         the mode 0 (ops2q at the cut) or the watchdog. An old DLL ignores the item.
//     ADDONS:KALS:O2DAPCYC(LIST(stk, los)) -> LIST(on, mode, hold, act, e, ea, w, u, msg, fR, tR, au, tk, ticks, dtmax, why, ui, seeddrop, gm):
//         stk TRUE = the stick is the DAP's (ops2q's INPUT PAGE, not typing; FALSE in INPUT RHC: the stick moves the
//         cursor only and the DAP holds), los 0 = TRACK the Earth, 1 = the Sun. Returns the state as o2dTick leaves it
//         in kOS's lexicon (e, w deg / deg/s V(pitch, roll, yaw), u the jets), msg the event since the last call
//         (cleared), fR / tR the reference now (world), au FBWAUTH, the ticks flown and the longest tick since the last
//         call, why the DAP let go (when on is FALSE). The 19th item is the gimbal mode's state text (IDLE / ARMED / OFF / BACK: why).
//     ADDONS:KALS:O2DAPALIVE -> on: kOS is alive (ops2q's trigger, every tick).
// THE WATCHDOG: O2D_WATCH handler ticks without any of these calls (ops2q ended, crashed or rebooted) and the DAP lets
// go, the axes the pilot's again; a paused game or the rails run no tick, so they never trip it. FBW3, FBWOFF and
// YAWJETAXES(FALSE) release it too (another DAP flies, or the burn's kOS steering).
// The vessel's state as kOS reads it: FACING = ReferenceTransform.rotation * Euler(-90, 0, 0) (STAR / TOP / FORE its
// right / up / forward), ANGULARVEL = FACING * (w.x, -w.z, w.y) of Vessel.angularVelocity (rad/s), the position from the
// body's centre CoMD - body.position, SHIP:VELOCITY:ORBIT = obt_velocity, SOLARPRIMEVECTOR = Planetarium.right, the
// body's ANGULARVEL = angularVelocity, SUN:POSITION = the Sun's position - CoMD. The stick: last tick's readback
// (fbPilot, yjPilot: FBWPILOT's numbers).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        const int O2D_WATCH = 100;                      // handler ticks (2 s at 50 Hz) without a kOS call: let go
        const int O2D_VES_N = 5;                        // ... and only this many on another vessel than the one ops2q set it on
        const int O2D_AUTH_N = 50;                      // FBWAUTH read every this many ticks (kOS: once a second)
        static readonly O2Dap o2dC = new O2Dap();
        static bool o2dOn, o2dStk;
        static Vessel o2dVes;                           // The vessel O2DAPSET turned the DAP on for (the state is static: a revert leaves it on)
        static int o2dLos, o2dIdle, o2dN, o2dAuthN;
        static double o2dT = -1, o2dDtMax;
        static Vector3d o2dAu;
        static string o2dWhy = "";
        static double o2dSeedCnt = 0;                  // The seed counter last applied
        // The gimbal mode (OmsGm.cs)
        static readonly OmsGm o2dGm = new OmsGm();
        static int o2dGmMode;                          // O2DAPSET's 16th item
        static Vessel o2dGmV;                          // the vessel whose RCS we turned off (restored on any exit)
        static bool o2dGmOffGrp;                       // we switched the vessel's RCS group off (mode 1)
        static readonly List<ModuleEngines> o2dGmEng = new List<ModuleEngines>();
        static readonly List<ModuleRCS> o2dGmRcs = new List<ModuleRCS>();
        static readonly List<bool> o2dGmSavP = new List<bool>(), o2dGmSavY = new List<bool>();   // the per-axis enables we disabled (mode 2)
        static readonly List<ModuleRCS> o2dGmTouched = new List<ModuleRCS>();   // the modules whose enables we saved (parallel to the two lists)
        static int o2dGmScan;                          // ticks to the next part scan

        partial void RegisterO2Dap()
        {
            AddSuffix("O2DAPSET", new OneArgsSuffix<StringValue, ListValue>(l => new StringValue(O2dSet(shared.Vessel, l))));
            AddSuffix("O2DAPCYC", new OneArgsSuffix<ListValue, ListValue>(l => O2dCyc(shared.Vessel, l)));
            AddSuffix("O2DAPALIVE", new Suffix<BooleanValue>(() => { o2dIdle = 0; return new BooleanValue(o2dOn); }));
            O2wRegister();   // O2WAKE / O2WAKESET / O2TICK (KalsAddon.O2Wake.cs)
        }

        static Vector3d O2dV(Structure s) { return ((kOS.Suffixed.Vector)s).ToVector3D(); }
        static kOS.Suffixed.Vector O2dK(Vector3d v) { return new kOS.Suffixed.Vector(v); }

        // the geometry o2dTick takes: LIST(pB, vO, SOLARPRIMEVECTOR, the body's ANGULARVEL)
        static Vector3d[] O2dGeo(Vessel v)
        {
            CelestialBody b = v.mainBody;
            return new[] { v.CoMD - b.position, v.obt_velocity, Planetarium.right, b.angularVelocity };
        }

        static string O2dSet(Vessel v, ListValue l)
        {
            try
            {
                if (v == null) return "ERROR NO VESSEL";
                if (l.Count < 10) return "ERROR " + l.Count + " ITEMS, WANT 10";
                double kg = O2Dap.K, tg = O2Dap.TAU, kig = 0;     // The optional gains
                if (l.Count >= 11) kg = HoD(l[10]);
                if (l.Count >= 12) tg = HoD(l[11]);
                if (l.Count >= 13) kig = HoD(l[12]);
                if (!(kg >= 0.02 && kg <= 3) || !(tg >= 0.3 && tg <= 10) || !(kig >= 0 && kig <= 1)) return "ERROR GAINS K " + kg + " TAU " + tg + " KI " + kig;
                HoOff("O2DAPSET");
                AsdOff("O2DAPSET");
                string rf = l[2].ToString().ToUpperInvariant();
                if (pxOn) rf = pxTgtFrame ? "TGT" : "INRTL";     // STKP on: the DAP's frame is the target's (or inertial while it turns too fast)
                if (rf != o2dC.rf) { o2dC.bp = null; o2dC.wf = Vector3d.zero; o2dC.ui = Vector3d.zero; }   // o2dFrame: a new frame restarts its rate
                o2dC.mode = l[0].ToString().ToUpperInvariant();
                o2dC.hold = l[1].ToString().ToUpperInvariant();
                o2dC.rf = rf;
                o2dC.act = l[3].ToString().ToUpperInvariant();
                o2dC.ax = O2dV(l[6]);
                o2dC.db = HoD(l[7]);
                o2dC.rate = HoD(l[8]);
                o2dC.tk = ((BooleanValue)l[9]).Value;
                o2dC.kGain = kg; o2dC.tauGain = tg; o2dC.ki = kig;
                if (kig <= 0) o2dC.ui = Vector3d.zero;
                if (!o2dC.tk) o2dC.wt = Vector3d.zero;
                o2dC.RefSet(O2dV(l[4]), O2dV(l[5]), O2dGeo(v));
                if (!o2dOn) { o2dT = -1; o2dAuthN = 0; o2dN = 0; o2dDtMax = 0; o2dWhy = ""; o2dC.msg = ""; o2dC.ui = Vector3d.zero; }
                if (l.Count >= 15)                       // The seeded pitch trim (a changed counter applies it once)
                {
                    double sv = HoD(l[13]), cn = HoD(l[14]);
                    if (cn != o2dSeedCnt) { o2dSeedCnt = cn; if (kig > 0 && Math.Abs(sv) <= 1) o2dC.Seed(sv); }
                }
                o2dGmMode = l.Count >= 16 ? (int)HoD(l[15]) : 0;          // The gimbal mode (an older kOS sends 15 items: 0)
                o2dIdle = 0;
                o2dOn = true;
                o2dVes = v;
                FbHook(v);                              // the handler on, subscribed last
                return "";
            }
            catch (Exception ex) { return ("ERROR " + ex.GetType().Name + ": " + ex.Message).ToUpperInvariant(); }       // On screen = capitals
        }

        static ListValue O2dCyc(Vessel v, ListValue l)
        {
            o2dIdle = 0;
            if (l.Count >= 2) { o2dStk = ((BooleanValue)l[0]).Value; o2dLos = (int)HoD(l[1]); }
            var r = new ListValue();
            Vector3d[] g = v != null ? O2dGeo(v) : null;
            r.Add(new BooleanValue(o2dOn)); r.Add(new StringValue(o2dC.mode)); r.Add(new StringValue(o2dC.hold));
            r.Add(new StringValue(o2dC.act)); r.Add(O2dK(o2dC.e)); r.Add(ScalarValue.Create(o2dC.ea)); r.Add(O2dK(o2dC.w));
            r.Add(O2dK(o2dC.u)); r.Add(new StringValue(o2dC.msg));
            r.Add(O2dK(g != null ? o2dC.RefF(g) : Vector3d.zero)); r.Add(O2dK(g != null ? o2dC.RefT(g) : Vector3d.zero));
            r.Add(O2dK(o2dAu)); r.Add(new BooleanValue(o2dC.tk)); r.Add(ScalarValue.Create(o2dN)); r.Add(ScalarValue.Create(o2dDtMax));
            r.Add(new StringValue(o2dWhy));
            r.Add(O2dK(o2dC.ui));
            r.Add(ScalarValue.Create(o2dC.seedDrop));     // 1 once the sign guard dropped the seed
            r.Add(new StringValue(o2dGm.Text()));         // The gimbal mode's state
            o2dC.msg = ""; o2dN = 0; o2dDtMax = 0;
            return r;
        }

        // the DAP lets go: the axes back to the pilot at once (FBW3 / FBWOFF set their own right after)
        static void O2dOff(string why)
        {
            if (!o2dOn) return;
            o2dOn = false;
            o2dWhy = why;
            O2dGmDo(o2dGm.Abort("THE DAP LET GO: " + why));       // A dead script never leaves the RCS off
            o2dGmMode = 0;
            fbCmd[0] = 0; fbCmd[1] = 0; yjCmd = 0; fbT[0] = -1E9; fbT[1] = -1E9; yjT = -1E9;
            Debug.Log("[KalsCoproc] ops2q DAP off (" + why + ")");
        }

        // one physics tick (YjFbw, before the axes are applied): o2dTick, its command on all three axes
        static void O2dTick(FlightCtrlState s, double now)
        {
            Vessel v = yjVessel;
            if (v == null) { O2dOff("NO VESSEL"); return; }
            if (++o2dIdle > O2D_WATCH) { O2dOff("NO KOS CALL FOR " + O2D_WATCH + " TICKS: OPS2Q ENDED"); return; }
            // A DAP left on by a flight that ended (a revert from orbit to the pad) flew the new vessel's first 100 ticks
            if (v != o2dVes && o2dIdle > O2D_VES_N) { O2dOff("ANOTHER VESSEL, NO KOS CALL: LEFT ON BY A FLIGHT THAT ENDED"); return; }
            // No jets in a rails frame (the game integrates the RCS over the whole TimeScale x fixedDeltaTime step) nor in the first ticks after the vessel unpacks (rate 0 read)
            bool quietNow = RlDapQuiet();
            if (quietNow || YjQuiet > 0)
            {
                if (!quietNow) YjQuiet--;
                fbCmd[0] = 0; fbCmd[1] = 0; yjCmd = 0; fbT[0] = now; fbT[1] = now; yjT = now;
                o2dT = -1; o2dC.u = Vector3d.zero;
                return;
            }
            double dt = o2dT < 0 || now - o2dT > 2 || now < o2dT ? 0 : now - o2dT;   // kOS's: 0 after a gap
            o2dT = now;
            o2dN++;
            if (dt > o2dDtMax) o2dDtMax = dt;
            if (o2dGmMode != 0 || o2dGm.State != OmsGm.IDLE) O2dGmTick(v, dt);
            if (o2dAuthN <= 0)
            {
                if (o2dGm.State == OmsGm.ACTIVE) o2dAu = O2dAuthNoRcs(v, o2dGm.Mode == 2);   // The jets are off: the gimbals' and the wheels' authority
                else
                {
                    ListValue a = FbAuth(v);
                    o2dAu = new Vector3d(HoD(a[0]), HoD(a[1]), HoD(a[2]));
                }
                o2dAuthN = O2D_AUTH_N;
            }
            o2dAuthN--;
            Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
            Vector3d sv = (Vector3d)(F * Vector3.right), tv = (Vector3d)(F * Vector3.up), fv = (Vector3d)(F * Vector3.forward);
            Vector3 wl = v.angularVelocity;
            Vector3d w = (Vector3d)(F * new Vector3(wl.x, -wl.z, wl.y));
            Vector3d[] g = O2dGeo(v);
            Vector3d los = o2dC.hold == "TRACK" ? (o2dLos == 0 ? -g[0] : Planetarium.fetch.Sun.position - v.CoMD) : Vector3d.zero;
            Vector3d stick = PxStickForDap(o2dStk, new Vector3d(fbPilot[0], fbPilot[1], yjPilot), now);   // STKP + STICK ARM = no stick
            o2dC.SwLost = SwQuery.Lost(v, "SW 01", "ORBIT");     // The vessel's own failure list, no kOS global
            Vector3d u = o2dC.Tick(g, sv, tv, fv, w, o2dAu, dt, stick, los);
            fbCmd[0] = FbClamp(u.x); fbCmd[1] = FbClamp(u.y); fbT[0] = now; fbT[1] = now;
            yjCmd = FbClamp(u.z); yjT = now;
        }

        // ---- The gimbal mode on the vessel
        // the parts the mode reads: the engines and the RCS modules (every 100 ticks, and when the mode starts)
        static void O2dGmScan(Vessel v)
        {
            o2dGmEng.Clear(); o2dGmRcs.Clear();
            bool shuttle = PayloadRcs.IsShuttle(v);       // T1017: a payload's RCS modules are not the orbiter's: the mode never touches their axes
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ModuleEngines e = m as ModuleEngines;
                    if (e != null) o2dGmEng.Add(e);
                    ModuleRCS r = m as ModuleRCS;
                    if (r != null && !PayloadRcs.IsPayload(shuttle, p)) o2dGmRcs.Add(r);
                }
            o2dGmScan = 100;
        }

        // the lit engines' thrust over what they can give (their limiter counted), and whether one of them has its gimbal locked
        static double O2dGmFrac(out bool locked)
        {
            double num = 0, den = 0; locked = false;
            foreach (ModuleEngines e in o2dGmEng)
            {
                if (e == null || !e.EngineIgnited || e.flameout) continue;
                num += e.finalThrust;
                den += e.maxThrust * e.thrustPercentage * 0.01;
                ModuleGimbal g = e.part != null ? e.part.FindModuleImplementing<ModuleGimbal>() : null;
                if (g != null && g.gimbalLock) locked = true;
            }
            return den > 1E-3 ? num / den : 0;
        }

        static void O2dGmTick(Vessel v, double dt)
        {
            if (o2dGmV != null && o2dGmV != v) { O2dGmDo(o2dGm.Abort("THE VESSEL CHANGED")); }
            if (o2dGmMode != 0 && (--o2dGmScan <= 0 || o2dGm.State == OmsGm.IDLE)) O2dGmScan(v);
            bool locked = false;
            double f = 0;
            if (o2dGmMode != 0) f = O2dGmFrac(out locked);
            bool ext = o2dGm.State == OmsGm.ACTIVE && o2dGm.Mode == 1 && v.ActionGroups[KSPActionGroup.RCS];
            string was = o2dGm.Text();
            int act = o2dGm.Step(o2dGmMode, f, locked, ext, o2dC.ea, dt);
            if (act != 0) { o2dGmV = v; O2dGmDo(act); }
            if (was != o2dGm.Text()) Debug.Log("[KalsCoproc] ops2q gimbal mode " + o2dGmMode + ": " + was + " -> " + o2dGm.Text() + " (thrust " + Math.Round(f * 100) + " %)");
        }

        // 1 jets off (apply the mode), 2 jets back, 3 re-apply
        static void O2dGmDo(int act)
        {
            if (act == 0) return;
            Vessel v = o2dGmV;
            if (v == null) return;
            if (act == 2 || act == 3) O2dGmRestore(v);
            if (act == 1 || act == 3)
            {
                if (o2dGm.Mode == 1)
                {
                    if (v.ActionGroups[KSPActionGroup.RCS]) { v.ActionGroups.SetGroup(KSPActionGroup.RCS, false); o2dGmOffGrp = true; }
                }
                else
                {
                    o2dGmSavP.Clear(); o2dGmSavY.Clear(); o2dGmTouched.Clear();
                    foreach (ModuleRCS r in o2dGmRcs) { o2dGmTouched.Add(r); o2dGmSavP.Add(r.enablePitch); o2dGmSavY.Add(r.enableYaw); r.enablePitch = false; r.enableYaw = false; }
                }
            }
            o2dAuthN = 0;                                // the authority afresh at the next tick (the jets in or out of it)
        }

        // the RCS as it was before the mode: the group on again if we switched it off, the pitch / yaw enables back
        static void O2dGmRestore(Vessel v)
        {
            if (o2dGmOffGrp) { v.ActionGroups.SetGroup(KSPActionGroup.RCS, true); o2dGmOffGrp = false; }
            for (int i = 0; i < o2dGmSavP.Count && i < o2dGmTouched.Count; i++)
                if (o2dGmTouched[i] != null) { o2dGmTouched[i].enablePitch = o2dGmSavP[i]; o2dGmTouched[i].enableYaw = o2dGmSavY[i]; }
            o2dGmSavP.Clear(); o2dGmSavY.Clear(); o2dGmTouched.Clear();
        }

        // FBWAUTH as FbAuth sums it, with the RCS modules left out (keepRoll: their roll share stays: the one-engine burn's roll jets)
        static Vector3d O2dAuthNoRcs(Vessel v, bool keepRoll)
        {
            Vector3 pos = Vector3.zero, neg = Vector3.zero;
            bool shuttle = PayloadRcs.IsShuttle(v);
            foreach (Part p in v.parts)
                foreach (PartModule m in p.Modules)
                {
                    ITorqueProvider tp = m as ITorqueProvider;
                    if (tp == null || !m.isEnabled) continue;
                    Vector3 a, b;
                    try { tp.GetPotentialTorque(out a, out b); } catch (Exception) { continue; }
                    if (m is ModuleRCS)
                    {
                        if (!keepRoll || PayloadRcs.IsPayload(shuttle, p)) continue;     // T1017: a payload's roll jets are not the burn's
                        a = new Vector3(0, a.y, 0); b = new Vector3(0, b.y, 0);
                    }
                    pos += new Vector3(Math.Abs(a.x), Math.Abs(a.y), Math.Abs(a.z));
                    neg += new Vector3(Math.Abs(b.x), Math.Abs(b.y), Math.Abs(b.z));
                }
            Vector3 moi = v.MOI;
            double[] r = new double[3];
            for (int i = 0; i < 3; i++)
            {
                double tq = 0.5 * (pos[i] + neg[i]), j = moi[i];
                r[i] = j > 1E-6 && !double.IsNaN(tq) && !double.IsInfinity(tq) ? tq / j * 180.0 / Math.PI : 0;
            }
            return new Vector3d(r[0], r[1], r[2]);
        }
    }
}
