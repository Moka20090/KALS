// The OMS thrust line for the burn guidance (ops2q's o2pAim / o2pSense, shuttle_exec's steering and dV count): where the
// engines' thrust REALLY points, gimbal deflection included. The part's FACING:FOREVECTOR (all kOS gives) leaves the gimbal out,
// and the gimbal trims the thrust through the c.g. (the loadout's c.g. moves it by up to ~1.4 deg), so a burn that holds the
// body axis on the burn vector thrusts off it by the trim. The maths is OmsLineCore.cs (no Unity types, tested offline).
//     ADDONS:KALS:OMSLINE(uids, mode)   uids: LIST of the engines' part UIDs (kOS Part:UID, matched on flightID / persistentId);
//                                       mode "meas" (the thrust they give now), "trim" (before any thrust: each engine's thrust
//                                       turned by its gimbal through the c.g., clamped to the range; a locked gimbal stays
//                                       neutral), "auto" (meas when they give >= 0.1 kN, else trim).
//     returns LIST(fx, fy, fz, tx, ty, tz, flags, n, ttot): the force (kN) in the world axes kOS hands its vectors in, the torque
//     about the c.g. (kN m, the same forces at their gimbal pivots), flags (1 measured, 2 trim, 4 a trim clamped to the range,
//     8 a UID not on the vessel, 16 a gimbal locked in trim, 32 no data), n engines counted, ttot their thrust (kN).
// The gimbal's axes and neutral frame are read as KalsAddon.AscDap.cs AsdModel reads them (its q0 / lx / ly).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterOmsLine()
        {
            AddSuffix("OMSLINE", new TwoArgsSuffix<ListValue, ListValue, StringValue>((uids, mode) =>
                OlLine(shared.Vessel, uids, mode.ToString())));
        }

        static double[] OlD(Vector3d x) { return new double[] { x.x, x.y, x.z }; }

        static ListValue OlOut(double[] r, int flags, int n, double ttot)
        {
            var l = new ListValue();
            for (int i = 0; i < 6; i++) l.Add(ScalarValue.Create(r[i]));
            l.Add(ScalarValue.Create(flags));
            l.Add(ScalarValue.Create(n));
            l.Add(ScalarValue.Create(ttot));
            return l;
        }

        static ListValue OlLine(Vessel v, ListValue uids, string mode)
        {
            double[] zero = new double[6];
            if (v == null) return OlOut(zero, 32, 0, 0);
            var ids = new HashSet<string>();
            foreach (Structure s in uids) ids.Add(s.ToString());
            mode = (mode ?? "auto").ToLowerInvariant();
            Vector3d com = v.CurrentCoM;
            double[] cg = OlD(com);
            var pos = new List<double[]>();
            var live = new List<double[]>();
            var trim = new List<double[]>();
            var tm = new List<double>();          // the thrust each gave (kN), measured
            var tn = new List<double>();          // the thrust each can give (kN), for the trim
            int flags = 0, found = 0;
            double tfinal = 0;
            foreach (Part p in v.parts)
            {
                if (!ids.Contains(p.flightID.ToString()) && !ids.Contains(p.persistentId.ToString())) continue;
                ModuleGimbal g = null;
                foreach (PartModule m in p.Modules) { g = m as ModuleGimbal; if (g != null) break; }
                foreach (PartModule m in p.Modules)
                {
                    ModuleEngines e = m as ModuleEngines;
                    if (e == null || e.thrustTransforms == null || e.thrustTransforms.Count == 0) continue;
                    found++;
                    Vector3d fd = Vector3d.zero;
                    for (int i = 0; i < e.thrustTransforms.Count; i++)
                    {
                        double mu = e.thrustTransformMultipliers != null && i < e.thrustTransformMultipliers.Count ? e.thrustTransformMultipliers[i] : 1.0 / e.thrustTransforms.Count;
                        fd += -(Vector3d)e.thrustTransforms[i].forward * mu;
                    }
                    Vector3d ul = fd.normalized;
                    bool gim = g != null && g.moduleIsEnabled && g.gimbalTransforms != null && g.gimbalTransforms.Count > 0;
                    int ng = gim ? g.gimbalTransforms.Count : 1;
                    double fin = e.finalThrust, nom = e.maxThrust * e.thrustPercentage * 0.01;
                    for (int i = 0; i < ng; i++)
                    {
                        tfinal += fin / ng;
                        tm.Add(fin / ng);
                        tn.Add(nom / ng);
                        live.Add(OlD(ul));
                        if (!gim) { pos.Add(OlD((Vector3d)p.transform.position)); trim.Add(OlD(ul)); continue; }
                        Transform gt = g.gimbalTransforms[i];
                        pos.Add(OlD((Vector3d)gt.position));
                        if (g.gimbalLock) { flags |= 16; trim.Add(OlD(ul)); continue; }
                        Transform nt = gt.parent != null ? gt.parent : gt;
                        Quaternion q0 = nt.rotation * g.initRots[i];
                        Vector3d n = e.thrustTransforms[0].IsChildOf(gt) ? ((Vector3d)(q0 * Quaternion.Inverse(gt.rotation) * (Vector3)ul)).normalized : ul;
                        Vector3d lx = (Vector3d)(q0 * Vector3.right), ly = (Vector3d)(q0 * (g.flipYZ ? Vector3.forward : Vector3.up));
                        double rx = 0.5 * (g.gimbalRangeXP + g.gimbalRangeXN) * g.gimbalLimiter * 0.01 * Math.PI / 180 * g.xMult;
                        double ry = 0.5 * (g.gimbalRangeYP + g.gimbalRangeYN) * g.gimbalLimiter * 0.01 * Math.PI / 180 * g.yMult;
                        bool cl;
                        double[] d = OmsLineCore.TrimDir(OlD((Vector3d)gt.position), OlD(n), OlD(lx), OlD(ly), cg, rx, ry, out cl);
                        if (cl) flags |= 4;
                        trim.Add(d);
                    }
                }
            }
            if (found < ids.Count) flags |= 8;
            if (pos.Count == 0) return OlOut(zero, flags | 32, 0, 0);
            bool useMeas = mode == "meas" || (mode != "trim" && tfinal >= 0.1);
            if (useMeas && tfinal < 0.01) return OlOut(zero, flags | 32, found, 0);
            double[][] pa = pos.ToArray();
            double[][] da = (useMeas ? live : trim).ToArray();
            double[] ta = (useMeas ? tm : tn).ToArray();
            double tt = 0;
            for (int i = 0; i < ta.Length; i++) tt += ta[i];
            if (useMeas) flags &= ~(4 | 16);
            flags |= useMeas ? 1 : 2;
            return OlOut(OmsLineCore.Sum(pa, da, ta, cg), flags, found, tt);
        }
    }
}
