// The Canadarm's autostrut (ARM-AS). A part's autostrut is a field of the Part itself (Part.autoStrutMode), not of a part
// module, so kOS 1.6 can neither read nor set it; the coprocessor does.
//     ADDONS:KALS:ASTRUT(part, mode)   mode "" only reads; Off / Root / Heaviest / Grandparent (the part menu's) or
//                                      ForceRoot / ForceHeaviest / ForceGrandparent (the game's own) sets it on that part
//                                      (shared.Vessel's parts only) and rebuilds the part's struts the way the part menu
//                                      does (Part.UpdateAutoStrut: Off releases them at once, a mode secures them over the
//                                      next frames). Returns the part's mode after the call, or "ERROR: <why>"; never throws.
// lib_arm (larAsOff / larAsStow) turns the arm's struts off before any joint drives and the end effector's and the
// elbow's back on at the stow pose (they wiggle in launch without it).
// the arm's joints driven every physics tick by C# (ArmDrive.cs, ArmDriveKsp.cs). kOS's chain order (shoulder out) throughout; angles in the servo's
// 'target angle' sense (deg), rates deg/s. Each call counts as kOS alive (the watchdog: ArmDriveKsp.WATCH).
//     ADDONS:KALS:ARMDRIVE(LIST(parts)) -> "" or "ERROR: <why>": the driver for these joints (one at a time).
//     ADDONS:KALS:ARMRATE(LIST(rates), tau) -> the state: the joints follow the rates through a two-stage filter of tau s.
//     ADDONS:KALS:ARMGOTO(LIST(goals), T, tb) -> the state: every joint to its goal in T s, arriving together: minimum jerk
//         (tb 0), or a cruise blended up and down over tb s (2 tb < T).
//     ADDONS:KALS:ARMSTATE -> LIST(on, LIST(command deg), LIST(rate deg/s), GOTO done, mode "RATE" / "GOTO", why it let go).
//     ADDONS:KALS:ARMALIVE -> on (kOS's pass: the watchdog fed).
//     ADDONS:KALS:ARMDAMP(zeta) -> LIST(one line a joint): the dampers for ratio zeta on the inertia outboard of each
//         joint (0: back to what the driver found); the lines for the arm log.
//     ADDONS:KALS:ARMFREE(why) -> "": the driver lets go (every field it changed back).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterArm()
        {
            AddSuffix("ASTRUT", new TwoArgsSuffix<StringValue, kOS.Suffixed.Part.PartValue, StringValue>(AsStrut));
            AddSuffix("ARMDRIVE", new OneArgsSuffix<StringValue, ListValue>(ArmDriveStart));
            AddSuffix("ARMRATE", new TwoArgsSuffix<ListValue, ListValue, ScalarValue>((l, t) => ArmCmd(l, t, false, null)));
            AddSuffix("ARMGOTO", new ThreeArgsSuffix<ListValue, ListValue, ScalarValue, ScalarValue>((l, t, b) => ArmCmd(l, t, true, b)));
            AddSuffix("ARMSTATE", new Suffix<ListValue>(() => ArmStateOf(true)));
            AddSuffix("ARMALIVE", new Suffix<BooleanValue>(() => { var d = ArmDriveKsp.Live; if (d != null) d.Alive(); return new BooleanValue(d != null); }));
            AddSuffix("ARMDAMP", new OneArgsSuffix<ListValue, ScalarValue>(ArmDamp));
            AddSuffix("ARMFREE", new OneArgsSuffix<StringValue, StringValue>(w => { var d = ArmDriveKsp.Live; if (d != null) d.Release("kOS: " + w); return new StringValue(""); }));
        }

        StringValue AsStrut(kOS.Suffixed.Part.PartValue pv, StringValue mode)
        {
            try
            {
                global::Part p = pv == null ? null : pv.Part;
                if (p == null) return new StringValue("ERROR: no part");
                if (shared.Vessel == null || p.vessel != shared.Vessel) return new StringValue("ERROR: not this vessel's part");
                string m = mode == null ? "" : mode.ToString().Trim();
                if (m.Length > 0)
                {
                    global::Part.AutoStrutMode want;
                    if (!Enum.TryParse(m, true, out want) || !Enum.IsDefined(typeof(global::Part.AutoStrutMode), want))
                        return new StringValue("ERROR: no autostrut mode '" + m + "'");
                    if (p.autoStrutMode != want) { p.autoStrutMode = want; p.UpdateAutoStrut(); }
                }
                return new StringValue(p.autoStrutMode.ToString());
            }
            catch (Exception e) { return new StringValue("ERROR: " + e.Message); }
        }


        StringValue ArmDriveStart(ListValue parts)
        {
            try
            {
                var l = new List<global::Part>();
                foreach (var x in parts)
                {
                    var pv = x as kOS.Suffixed.Part.PartValue;
                    if (pv == null || pv.Part == null) return new StringValue("ERROR: not a part");
                    l.Add(pv.Part);
                }
                string r = ArmDriveKsp.Start(shared.Vessel, l);
                return new StringValue(r);
            }
            catch (Exception e) { return new StringValue("ERROR: " + e.Message); }
        }

        static double[] ArmNums(ListValue l, int n)
        {
            var o = new double[n];
            for (int i = 0; i < n; i++) o[i] = (l != null && i < l.Count && l[i] is ScalarValue) ? ((ScalarValue)l[i]).GetDoubleValue() : double.NaN;
            return o;
        }

        ListValue ArmCmd(ListValue l, ScalarValue t, bool go, ScalarValue tb)
        {
            var d = ArmDriveKsp.Live;
            if (d == null) return ArmStateOf(false);
            try
            {
                d.Alive(); d.Sync();
                double v = t == null ? 0.3 : t.GetDoubleValue();
                if (go) d.C.Goto(ArmNums(l, d.C.N), v, tb == null ? 0 : tb.GetDoubleValue()); else d.C.SetRates(ArmNums(l, d.C.N), v);
            }
            catch (Exception e) { d.Release("error: " + e.Message); }
            return ArmStateOf(false);
        }

        static ListValue ArmStateOf(bool alive)
        {
            var d = ArmDriveKsp.Live;
            var o = new ListValue();
            var th = new ListValue(); var rt = new ListValue();
            if (d != null)
            {
                if (alive) { d.Alive(); d.Sync(); }
                for (int i = 0; i < d.C.N; i++) { th.Add(ScalarValue.Create(d.C.Th[i])); rt.Add(ScalarValue.Create(d.C.R2[i])); }
            }
            o.Add(new BooleanValue(d != null)); o.Add(th); o.Add(rt);
            o.Add(new BooleanValue(d != null && d.C.Mode == ArmDriveCore.GOTO && d.C.GDone));
            o.Add(new StringValue(d == null ? "" : (d.C.Mode == ArmDriveCore.GOTO ? "GOTO" : "RATE")));
            o.Add(new StringValue(d == null ? armWhyNow() : ""));
            return o;
        }
        static string armWhyNow() { return ArmDriveKsp.LastWhy; }

        ListValue ArmDamp(ScalarValue z)
        {
            var o = new ListValue();
            var d = ArmDriveKsp.Live;
            if (d == null) { o.Add(new StringValue("no arm drive")); return o; }
            try { d.Alive(); foreach (var s in d.Damp(z == null ? 0 : z.GetDoubleValue())) o.Add(new StringValue(s)); }
            catch (Exception e) { o.Add(new StringValue("ERROR: " + e.Message)); }
            return o;
        }
    }
}
