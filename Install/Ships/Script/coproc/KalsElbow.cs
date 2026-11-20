// The KerboArm elbow's full 180 deg fold (ht_C1_elbow; kals_elbow.cfg adds this module after the part's hinge).
// ModuleRoboticServoHinge builds its hinge as a Unity ConfigurableJoint whose zero is the pose the moving transform has
// when PostStartInitJoint connects the joint: the model's straight pose, transform angle 0. The fold end, -180, is then
// 180 deg of twist from that zero, and Unity holds an angular limit to 177 deg at most, so the elbow stops near -176.5
// and the stowed arm opens into a V. Right after the hinge's own OnStartBeforePartAttachJoint (module order), this
// module moves the joint's zero to the middle of the travel: it turns the moving transform to midAngle, re-connects the
// joint (Unity takes the rest pose at the connect), sets the twist limits to the travel's ends (+-90 deg either side,
// the hinge's own OnJointInit formula with the zero's angle as its starting offset), and turns the transform back.
// The hinge sends every drive target through SetTargetRotationLocal(target, cachedStartingRotation), so that field
// becomes the mid pose and the drive follows the new zero.
// The angle wrap: the hinge reads its angle from the transform's Euler angle, -180 to 180, so a fold at the end can read
// +180. A drive angle taken from that reading (at load, unlock or motor engage) would walk 360 deg through the straight
// pose to reach the -180 target, so a drive angle past the travel's end, unlocked, is taken back by 360 deg.
// The check: should the re-connect leave the joint's zero where it was, the new +-90 limits would throw the folded
// elbow 90 deg open at the first physics tick. For the first CHECK_N ticks after the vessel unpacks, with no new drive
// command, an elbow that moves CHECK_DEG further off its drive angle than it was at the first tick puts the stock frame
// back (limits, starting rotation).
// KSP.log: "[KalsCoproc] elbow:" at the re-zero, and a warning if the check undid it.
using System;
using System.Reflection;
using Expansions.Serenity;
using UnityEngine;

namespace KalsCoproc
{
    public class KalsElbow : PartModule
    {
        [KSPField] public float midAngle = -90f;   // deg, the transform angle that becomes the joint's zero

        const int CHECK_N = 100;        // physics ticks after the unpack (2 s at 50 Hz)
        const float CHECK_DEG = 20f;    // deg off the drive angle: the zero did not move (the sag at the fold is ~4-10)
        const BindingFlags ANY = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        static FieldInfo fJoint, fMoving, fStart, fOffset, fTarget, fDrive, fLocked, fSoft, fMia, fMirror;

        ModuleRoboticServoHinge h;
        ConfigurableJoint jt;
        Transform mt;
        float jLo, jHi;   // deg, the drive angle's travel (target angle less modelInitialAngle)
        float soft0, soft1, mia, d0, off0;
        int checkLeft;

        static FieldInfo Fld(Type t, string n)
        {
            for (; t != null; t = t.BaseType) { FieldInfo f = t.GetField(n, ANY | BindingFlags.DeclaredOnly); if (f != null) return f; }
            throw new MissingFieldException("ModuleRoboticServoHinge", n);
        }

        static void Bind()
        {
            if (fJoint != null) return;
            Type t = typeof(ModuleRoboticServoHinge);
            fMoving = Fld(t, "movingPartObject"); fStart = Fld(t, "cachedStartingRotation");
            fOffset = Fld(t, "cachedStartingRotationOffset"); fTarget = Fld(t, "targetRotation");
            fDrive = Fld(t, "driveTargetAngle"); fLocked = Fld(t, "servoIsLocked"); fSoft = Fld(t, "softMinMaxAngles");
            fMia = Fld(t, "modelInitialAngle"); fMirror = Fld(t, "mirrorRotation");
            fJoint = Fld(t, "servoJoint");
        }

        public override void OnStartBeforePartAttachJoint(StartState state)
        {
            h = null;
            if (!HighLogic.LoadedSceneIsFlight || state == StartState.Editor) return;
            try { MidZero(); }
            catch (Exception e) { h = null; Debug.LogError("[KalsCoproc] elbow: " + part.partInfo.name + " left as built: " + e.Message); }
        }

        void MidZero()
        {
            Bind();
            ModuleRoboticServoHinge hg = part.FindModuleImplementing<ModuleRoboticServoHinge>();
            if (hg == null) throw new InvalidOperationException("no hinge");
            ConfigurableJoint j = fJoint.GetValue(hg) as ConfigurableJoint;
            GameObject mv = fMoving.GetValue(hg) as GameObject;
            if (j == null || mv == null || j.connectedBody == null) throw new InvalidOperationException("no servo joint");
            if ((bool)fMirror.GetValue(hg)) throw new InvalidOperationException("mirrored");
            Vector2 soft = (Vector2)fSoft.GetValue(hg); mia = (float)fMia.GetValue(hg);
            soft0 = soft.x; soft1 = soft.y; jLo = soft0 - mia; jHi = soft1 - mia;
            if (midAngle <= jLo || midAngle >= jHi) throw new InvalidOperationException("midAngle outside the travel");

            Transform t = mv.transform;
            Quaternion rNow = t.localRotation, rMid = Quaternion.AngleAxis(midAngle, j.axis);
            Rigidbody cb = j.connectedBody;
            t.localRotation = rMid; Physics.SyncTransforms();
            j.connectedBody = null; j.connectedBody = cb;
            t.localRotation = rNow; Physics.SyncTransforms();
            Frame(j, midAngle, rMid);

            h = hg; jt = j; mt = t; checkLeft = CHECK_N;
            float r = (float)fDrive.GetValue(hg); Unwrap(); d0 = (float)fDrive.GetValue(hg);
            Debug.Log("[KalsCoproc] elbow: " + part.partInfo.name + " joint zero at " + midAngle.ToString("F1") + " deg, twist "
                + j.lowAngularXLimit.limit.ToString("F1") + " to " + j.highAngularXLimit.limit.ToString("F1") + ", angle "
                + Angle().ToString("F2") + ", drive angle " + r.ToString("F2") + " -> " + d0.ToString("F2"));
        }

        // The hinge's frame for a joint zero at transform angle z: its OnJointInit limits with z as the starting offset,
        // the starting rotation, and the drive target re-sent against it.
        void Frame(ConfigurableJoint j, float z, Quaternion rz)
        {
            SoftJointLimit lo = j.lowAngularXLimit, hi = j.highAngularXLimit;
            hi.limit = z + Mathf.Abs(soft0 - mia); lo.limit = z - (soft1 - mia);
            j.highAngularXLimit = hi; j.lowAngularXLimit = lo;
            ModuleRoboticServoHinge hg = part.FindModuleImplementing<ModuleRoboticServoHinge>();
            fStart.SetValue(hg, rz); fOffset.SetValue(hg, z);
            j.SetTargetRotationLocal((Quaternion)fTarget.GetValue(hg), rz);
        }

        float Angle()   // deg, the moving transform's turn about the joint axis, -180 to 180
        {
            Quaternion q = mt.localRotation; Vector3 a = jt.axis.normalized;
            return Mathf.DeltaAngle(0f, 2f * Mathf.Rad2Deg * Mathf.Atan2(q.x * a.x + q.y * a.y + q.z * a.z, q.w));
        }

        void Unwrap()
        {
            float d = (float)fDrive.GetValue(h);
            if (d > jHi + 1f && d - 360f >= jLo - 1f) fDrive.SetValue(h, d - 360f);
            else if (d < jLo - 1f && d + 360f <= jHi + 1f) fDrive.SetValue(h, d + 360f);
        }

        void FixedUpdate()
        {
            if (h == null) return;
            if (!(bool)fLocked.GetValue(h)) Unwrap();
            if (checkLeft <= 0 || vessel == null || vessel.packed) return;
            float d = (float)fDrive.GetValue(h);
            if (Mathf.Abs(Mathf.DeltaAngle(d, d0)) > 1f) { checkLeft = 0; return; }   // a new command: the check ends
            float off = Mathf.Abs(Mathf.DeltaAngle(Angle(), d));
            if (checkLeft == CHECK_N) off0 = off;   // a part loaded off its drive angle (a dislocated arm) is not thrown
            if (off <= off0 + CHECK_DEG) { checkLeft--; return; }
            checkLeft = 0;
            Frame(jt, 0f, Quaternion.identity);
            Debug.LogWarning("[KalsCoproc] elbow: " + part.partInfo.name + " " + off.ToString("F1") + " deg off its drive angle "
                + d.ToString("F1") + " after the unpack: the joint kept its zero, the stock frame is back (stops near -177)");
        }
    }
}
