// ArmDriveCore (ArmDrive.cs) bound to the Canadarm's Breaking Ground servos: a MonoBehaviour of its own that, every
// physics tick, hands each driven joint its command unrounded (the servo's targetAngle field, a float that kOS's SETFIELD
// could only set in whole degrees) and lets the servo's own slew pass it through (traverseVelocity = the part's own top
// rate, so MoveTowards reaches the command each tick). One driver at a time (Live), for the active vessel's arm.
//   Joints locked by kOS are not driven (KSP holds them at lockAngle); at an unlock the joint's command is put where its
//   drive is (driveTargetAngle = lockAngle while locked), turned back into the field's sense: the hinge's drive angle is
//   s x clamp(target) - modelInitialAngle, the rotation servo's s x clamp(target) (s = -1 mirrored, and again inverted).
//   THE DAMPING (Damp): per joint the inertia outboard of it about its axis (every rigidbody of the parts under the
//   servo, the servo's moving body, a docked payload's parts) -> the damper for the ratio zeta on the live drive's spring;
//   the part's hingeDamping field scaled by c / c_now (KSP's damper is linear in it) and the drive rebuilt by the servo's
//   own OnModifyServo (BaseServo has no ModifyServo() without an argument); the lead (c / k) taken from the live drive afterwards. Put back as found at Release.
//   THE MOUNT DAMPER: the arm's own free mode is its whole body tilting on the orbiter's mount (0.5 Hz, +-0.1..0.25 deg
//   at MAN AUG's K = 0, damping ratio ~0.1); no servo drive reaches it (they are overdamped and hold their own joints). Every
//   physics tick every rigidbody of the arm (the base servo's part, every part below it, every servo's moving body, a grappled
//   payload) is pulled toward the velocity the orbiter's control part's frame gives at its own point: a = -MountG x (v - v_ref)
//   (1/s; ForceMode.Acceleration: a damper of ratio ~MountG / 2 w0 on the mode, w0 = 3 rad/s), and the reaction (m a, at the
//   body's centre) goes to the control part's body, so no momentum is made. Passive (it only ever opposes the relative velocity)
//   and the same in every arm mode, MAN AUG / OPR CMD / SINGLE alike; on from Init (MountG, 0 = off).
//   THE WATCHDOG: kOS calls ARMALIVE (or any ARM suffix) every pass; WATCH physics ticks without one (arm.ks ended or
//   crashed) and the joints are stopped smoothly, then the driver lets go (Release): every field it changed back.
//   Lets go too when the vessel is no longer the active one, a part is gone, or the scene changes.
// KSP.log: "[KalsCoproc] arm drive:" lines at the start, every damping change and the release.
using System;
using System.Collections.Generic;
using System.Reflection;
using Expansions.Serenity;
using UnityEngine;

namespace KalsCoproc
{
    public class ArmDriveKsp : MonoBehaviour
    {
        public static ArmDriveKsp Live;
        public static string LastWhy = "";      // why the last driver let go
        public const int WATCH = 50;                     // physics ticks (1 s at 50 Hz) without a kOS call: stop, then let go
        const BindingFlags ANY = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        static FieldInfo fJoint, fMovingRb, fMotorOut;
        static MethodInfo mModify;

        public Vessel V;
        public BaseServo[] S;
        public Part[] P;
        public ArmDriveCore C;
        float[] trav0, damp0, travMax;
        public double[] Inert, Spring, Damper;           // per joint: t m2 outboard, the drive's spring and damper now
        public int Idle, Ticks;
        public bool Lapsed;
        public string Why = "";
        public double MountG = 4.0;                      // 1/s: the mount damper's rate; 0 = off
        public const double MountDvMax = 0.5;            // m/s: the relative velocity the damper uses at most
        Rigidbody[] mb = new Rigidbody[0];               // the arm's bodies and the frame body they are damped against
        Rigidbody refRb;
        public string MountInfo = "";

        static FieldInfo Fld(Type t, string n)
        {
            for (; t != null; t = t.BaseType) { FieldInfo f = t.GetField(n, ANY | BindingFlags.DeclaredOnly); if (f != null) return f; }
            throw new MissingFieldException("BaseServo", n);
        }
        static void Bind()
        {
            if (fJoint != null) return;
            Type t = typeof(BaseServo);
            fMovingRb = Fld(t, "movingPartRB"); fMotorOut = Fld(t, "motorOutput");
            for (Type u = t; u != null && mModify == null; u = u.BaseType) mModify = u.GetMethod("OnModifyServo", ANY | BindingFlags.DeclaredOnly, null, Type.EmptyTypes, null);
            if (mModify == null) throw new MissingMethodException("BaseServo", "OnModifyServo");
            fJoint = Fld(t, "servoJoint");
        }

        // ---- the servo's fields by its type (the hinge and the rotation servo declare their own)
        static ModuleRoboticServoHinge H(BaseServo s) { return s as ModuleRoboticServoHinge; }
        static ModuleRoboticRotationServo R(BaseServo s) { return s as ModuleRoboticRotationServo; }
        public static float TargetOf(BaseServo s) { var h = H(s); if (h != null) return h.targetAngle; var r = R(s); return r != null ? r.targetAngle : 0f; }
        static void SetTarget(BaseServo s, float v) { var h = H(s); if (h != null) { h.targetAngle = v; return; } var r = R(s); if (r != null) r.targetAngle = v; }
        static float TravOf(BaseServo s) { var h = H(s); if (h != null) return h.traverseVelocity; var r = R(s); return r != null ? r.traverseVelocity : 0f; }
        static void SetTrav(BaseServo s, float v) { var h = H(s); if (h != null) { h.traverseVelocity = v; return; } var r = R(s); if (r != null) r.traverseVelocity = v; }
        public static float DampOf(BaseServo s) { var h = H(s); if (h != null) return h.hingeDamping; var r = R(s); return r != null ? r.hingeDamping : 0f; }
        static void SetDamp(BaseServo s, float v) { var h = H(s); if (h != null) { h.hingeDamping = v; return; } var r = R(s); if (r != null) r.hingeDamping = v; }
        static Vector2 SoftOf(BaseServo s) { var h = H(s); if (h != null) return h.softMinMaxAngles; var r = R(s); return r != null ? r.softMinMaxAngles : new Vector2(-180, 180); }
        static float DriveOf(BaseServo s) { var h = H(s); if (h != null) return h.driveTargetAngle; var r = R(s); return r != null ? r.driveTargetAngle : 0f; }
        public static double FieldOfDrive(BaseServo s, float d)   // the drive angle back in the target field's sense
        {
            var h = H(s);
            if (h != null) { double sg = h.mirrorRotation ? -1 : 1; return sg * (d + h.modelInitialAngle); }
            var r = R(s);
            if (r != null) { double sg = (r.mirrorRotation ? -1 : 1) * (r.inverted ? -1 : 1); return sg * d; }
            return d;
        }
        // the same angle (mod 360) as f that lies nearest the servo's own field value: a locked hinge at -180 reports its drive angle as
        // +180 once it unlocks, and a command to -175 would then sweep the long way round
        static double NearField(BaseServo s, double f)
        {
            double r = TargetOf(s), d = (f - r) % 360.0;
            if (d > 180.0) d -= 360.0; else if (d < -180.0) d += 360.0;
            return r + d;
        }
        static float DdmOf(BaseServo s) { var h = H(s); if (h != null) return h.driveDampingMutliplier; var r = R(s); return r != null ? r.driveDampingMutliplier : 0f; }
        static ConfigurableJoint JointOf(BaseServo s) { return fJoint.GetValue(s) as ConfigurableJoint; }

        // ---- start: the parts of kOS's chain (shoulder out), each with one servo
        public static string Start(Vessel v, List<Part> parts)
        {
            try
            {
                Bind();
                if (v == null) return "ERROR: no vessel";
                if (FlightGlobals.ActiveVessel != v) return "ERROR: NOT THE ACTIVE VESSEL";     // The kOS side tries again when it is
                if (parts == null || parts.Count == 0) return "ERROR: no joints";
                var ss = new BaseServo[parts.Count];
                for (int i = 0; i < parts.Count; i++)
                {
                    Part p = parts[i];
                    if (p == null || p.vessel != v) return "ERROR: joint " + i + " is not this vessel's part";
                    ss[i] = p.FindModuleImplementing<BaseServo>();
                    if (ss[i] == null || (H(ss[i]) == null && R(ss[i]) == null)) return "ERROR: " + p.partInfo.title + " has no hinge or rotation servo";
                    if (JointOf(ss[i]) == null) return "ERROR: " + p.partInfo.title + " has no servo joint yet";
                }
                if (Live != null) Live.Release("a new start");
                var go = new GameObject("KALS arm drive");
                var d = go.AddComponent<ArmDriveKsp>();
                d.Init(v, parts.ToArray(), ss);
                Live = d;
                return "";
            }
            catch (Exception e) { return "ERROR: " + e.Message; }
        }

        void Init(Vessel v, Part[] p, BaseServo[] s)
        {
            V = v; P = p; S = s; int n = s.Length;
            C = new ArmDriveCore(n);
            trav0 = new float[n]; damp0 = new float[n]; travMax = new float[n];
            Inert = new double[n]; Spring = new double[n]; Damper = new double[n];
            for (int i = 0; i < n; i++)
            {
                trav0[i] = TravOf(s[i]); damp0[i] = DampOf(s[i]);
                travMax[i] = Mathf.Max(s[i].traverseVelocityLimits.y, 1f);
                Vector2 sm = SoftOf(s[i]); C.Lo[i] = sm.x; C.Hi[i] = sm.y;
                C.Held[i] = s[i].servoIsLocked;
                C.Seed(i, s[i].servoIsLocked ? NearField(s[i], FieldOfDrive(s[i], DriveOf(s[i]))) : TargetOf(s[i]));
                ReadDrive(i);
            }
            GameEvents.onGameSceneLoadRequested.Add(OnScene);
            Debug.Log("[KalsCoproc] arm drive: " + n + " joints on '" + v.vesselName + "'");
        }

        void OnScene(GameScenes g) { Release("the scene changes"); }

        void ReadDrive(int i)                            // the live drive's spring and damper, the lead c / k
        {
            ConfigurableJoint j = JointOf(S[i]);
            if (j == null) return;
            JointDrive dr = j.angularXDrive;
            Spring[i] = dr.positionSpring; Damper[i] = dr.positionDamper;
            C.Lead[i] = Spring[i] > 1e-6 ? Math.Min(2.0, Damper[i] / Spring[i]) : 0;
        }

        // the lock states read now: a joint just unlocked is seeded where its drive is (call before every command)
        public void Sync()
        {
            for (int i = 0; i < S.Length; i++)
            {
                bool lk = S[i].servoIsLocked;
                if (C.Held[i] && !lk) { C.Held[i] = false; C.Seed(i, NearField(S[i], FieldOfDrive(S[i], DriveOf(S[i])))); Write(i); }
                else if (!C.Held[i] && lk) { C.Held[i] = true; }
            }
        }

        void Write(int i)
        {
            SetTarget(S[i], (float)C.Target(i));
            if (TravOf(S[i]) != travMax[i]) SetTrav(S[i], travMax[i]);
        }

        // "" while the arm's vessel is there and active; else why not. The kOS side re-binds only on "NOT THE ACTIVE VESSEL" (an EVA, a
        // vessel switch); a real loss (the vessel gone, a joint part on another vessel: an undock split) stays on the kOS path.
        public string GoneWhy()
        {
            if (V == null) return "the arm's vessel is gone";
            if (FlightGlobals.ActiveVessel != V)
            {
                Vessel a = FlightGlobals.ActiveVessel;
                return "NOT THE ACTIVE VESSEL (the arm's vessel is not the active one; active now: " + (a == null ? "none" : a.vesselName) + ")";
            }
            for (int i = 0; i < S.Length; i++)
            {
                if (S[i] == null) return "joint " + i + "'s servo is gone";
                if (P[i] == null) return "joint " + i + "'s part is gone";
                if (P[i].vessel != V) return "joint " + i + "'s part is on another vessel now (an undock split?)";
            }
            return "";
        }

        void FixedUpdate()
        {
            if (Live != this) return;
            try
            {
                string gw = GoneWhy();
                if (gw != "") { Release(gw); return; }
                if (V.packed) return;                     // on rails: no physics, no command moves
                Sync();
                Idle++; Ticks++;
                if (Idle > WATCH && !Lapsed) { Lapsed = true; C.SetRates(null, 0.3); Debug.LogWarning("[KalsCoproc] arm drive: no kOS call for " + WATCH + " ticks: stopping"); }
                if (Lapsed && Idle > 3 * WATCH && C.AtRest(0.01)) { Release("kOS stopped calling (arm.ks ended?)"); return; }
                C.Tick(TimeWarp.fixedDeltaTime);
                if (MountG > 0 && !Lapsed) MountDamp();
                for (int i = 0; i < S.Length; i++) if (!C.Held[i]) Write(i);
            }
            catch (Exception e) { Release("error: " + e.Message); }
        }

        public void Alive() { Idle = 0; Lapsed = false; }

        // ---- the mount damper
        void MountScan()
        {
            var l = new List<Rigidbody>(); var seen = new HashSet<Rigidbody>();
            Part rp = V.GetReferenceTransformPart(); if (rp == null) rp = V.rootPart;
            refRb = rp != null ? rp.rb : null;
            if (refRb != null) seen.Add(refRb);
            if (P[0].rb != null && seen.Add(P[0].rb)) l.Add(P[0].rb);
            Rigidbody m0 = fMovingRb.GetValue(S[0]) as Rigidbody; if (m0 != null && seen.Add(m0)) l.Add(m0);
            var st = new Stack<Part>();
            foreach (Part c in P[0].children) st.Push(c);
            while (st.Count > 0)
            {
                Part q = st.Pop();
                if (q.rb != null && seen.Add(q.rb)) l.Add(q.rb);
                BaseServo qs = q.FindModuleImplementing<BaseServo>();
                if (qs != null) { Rigidbody qm = fMovingRb.GetValue(qs) as Rigidbody; if (qm != null && seen.Add(qm)) l.Add(qm); }
                foreach (Part c in q.children) st.Push(c);
            }
            mb = l.ToArray();
            double m = 0, it = 0; Vector3 pv = P[0].rb != null ? P[0].rb.worldCenterOfMass : P[0].transform.position;
            foreach (Rigidbody b in mb) { m += b.mass; it += b.mass * (b.worldCenterOfMass - pv).sqrMagnitude; }
            MountInfo = "MOUNT g " + MountG.ToString("G4") + " /s: " + mb.Length + " bodies " + m.ToString("F3") + " t, I about the base ~" + it.ToString("F1")
                + " t m2, frame body '" + (rp != null ? rp.partInfo.title : "none") + "' " + (refRb != null ? refRb.mass.ToString("F1") + " t" : "no rb")
                + ", base part's parent '" + (P[0].parent != null ? P[0].parent.partInfo.title : "none") + "'";
        }

        void MountDamp()
        {
            if (mb.Length == 0 || Ticks % 50 == 1) MountScan();
            if (refRb == null || mb.Length == 0) return;
            Vector3 vr = refRb.velocity, wr = refRb.angularVelocity, cr = refRb.worldCenterOfMass;
            float g = (float)MountG;
            for (int i = 0; i < mb.Length; i++)
            {
                Rigidbody b = mb[i];
                if (b == null) continue;
                Vector3 pt = b.worldCenterOfMass;
                Vector3 dv = b.velocity - (vr + Vector3.Cross(wr, pt - cr));
                float mag = dv.magnitude;
                if (mag > (float)MountDvMax) dv *= (float)MountDvMax / mag;
                Vector3 acc = -g * dv;
                b.AddForce(acc, ForceMode.Acceleration);
                refRb.AddForceAtPosition(-acc * b.mass, pt, ForceMode.Force);
            }
        }

        // ---- the damping: zeta <= 0 puts the found values back
        public List<string> Damp(double zeta)
        {
            var o = new List<string>();
            for (int i = 0; i < S.Length; i++)
            {
                BaseServo s = S[i];
                ConfigurableJoint j = JointOf(s);
                if (j == null) { o.Add(P[i].partInfo.title + ": no joint"); continue; }
                ReadDrive(i);
                double I = Inertia(i), k = Spring[i], c0 = Damper[i];
                float hd0 = DampOf(s), hd = damp0[i];
                if (zeta > 0)
                {
                    double c = ArmDriveCore.Crit(zeta, k, I);
                    double h = c0 > 1e-9 ? hd0 * c / c0 : c / Math.Max(1e-9, DdmOf(s) * s.maxMotorOutput * s.servoMotorSize * 1e-4);
                    hd = (float)Math.Min(1e6, Math.Max(damp0[i], h));
                }
                if (hd != hd0) { SetDamp(s, hd); mModify.Invoke(s, null); }
                ReadDrive(i);
                o.Add(P[i].partInfo.title + ": I " + I.ToString("G4") + " t m2, k " + k.ToString("G4") + ", c " + c0.ToString("G4") + " -> "
                    + Damper[i].ToString("G4") + " (damping " + hd0.ToString("G4") + " -> " + hd.ToString("G4") + ", ratio "
                    + ArmDriveCore.Ratio(c0, k, I).ToString("F3") + " -> " + ArmDriveCore.Ratio(Damper[i], k, I).ToString("F3")
                    + "), lead " + C.Lead[i].ToString("F3") + " s");
            }
            return o;
        }

        // the inertia (t m2) about joint i's axis of everything that turns with it
        public double Inertia(int i)
        {
            ConfigurableJoint j = JointOf(S[i]);
            Vector3 a = j.transform.TransformDirection(j.axis).normalized;
            Vector3 pv = j.transform.TransformPoint(j.anchor);
            Inert[i] = 0;
            var seen = new HashSet<Rigidbody>();
            Rigidbody mrb = fMovingRb.GetValue(S[i]) as Rigidbody;
            if (mrb != null) { Inert[i] += RbI(mrb, a, pv); seen.Add(mrb); }
            var st = new Stack<Part>();
            foreach (Part c in P[i].children) st.Push(c);
            while (st.Count > 0)
            {
                Part q = st.Pop();
                if (q.rb != null && seen.Add(q.rb)) Inert[i] += RbI(q.rb, a, pv);
                BaseServo qs = q.FindModuleImplementing<BaseServo>();
                if (qs != null) { Rigidbody qm = fMovingRb.GetValue(qs) as Rigidbody; if (qm != null && seen.Add(qm)) Inert[i] += RbI(qm, a, pv); }
                foreach (Part c in q.children) st.Push(c);
            }
            return Inert[i];
        }

        static double RbI(Rigidbody rb, Vector3 a, Vector3 pv)
        {
            Vector3 r = rb.worldCenterOfMass - pv;
            double perp = Vector3.Cross(r, a).sqrMagnitude;
            Quaternion q = rb.rotation * rb.inertiaTensorRotation;
            Vector3 it = rb.inertiaTensor;
            double ax = Vector3.Dot(a, q * Vector3.right), ay = Vector3.Dot(a, q * Vector3.up), az = Vector3.Dot(a, q * Vector3.forward);
            return rb.mass * perp + it.x * ax * ax + it.y * ay * ay + it.z * az * az;
        }

        public void Release(string why)
        {
            if (Live == this) Live = null;
            Why = why; LastWhy = why;
            try
            {
                GameEvents.onGameSceneLoadRequested.Remove(OnScene);
                if (S != null)
                    for (int i = 0; i < S.Length; i++)
                    {
                        BaseServo s = S[i];
                        if (s == null) continue;
                        if (!s.servoIsLocked) SetTarget(s, (float)C.Th[i]);
                        SetTrav(s, trav0[i]);
                        if (DampOf(s) != damp0[i]) { SetDamp(s, damp0[i]); mModify.Invoke(s, null); }
                    }
            }
            catch (Exception e) { Debug.LogError("[KalsCoproc] arm drive: release: " + e.Message); }
            Debug.Log("[KalsCoproc] arm drive: let go: " + why);
            Destroy(gameObject);
        }
    }
}
