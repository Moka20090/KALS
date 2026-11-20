// FAR from kOS, by reflection only (this DLL loads and runs without FAR): FARINFO returns one line (FAR found, voxels valid,
// ref area, length; the atmosphere is FAR's default unless another mod replaces it, which FARINFO reports); FARCHUTE and
// FTGROUNDCOLS (below) are log-only reads for the flight logs.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterFar()
        {
            AddSuffix("FARINFO", new Suffix<StringValue>(() => new StringValue(FarInfo())));
            AddSuffix("FARCHUTE", new Suffix<StringValue>(() => new StringValue(FarChute(shared.Vessel))));
            AddSuffix("FTGROUNDCOLS", new Suffix<StringValue>(() => new StringValue(FtGroundCols(shared.Vessel))));
        }

        // ---- FAR by reflection
        static bool farLooked;
        static MethodInfo farCalc, farRefArea, farVoxValid, farRe, farCf;
        static Type farVesselAeroType;
        static PropertyInfo farLength, farIsCustom;

        static bool FarFind()
        {
            if (farLooked) return farCalc != null;
            farLooked = true;
            foreach (var la in AssemblyLoader.loadedAssemblies)
            {
                if (la.assembly == null || la.assembly.GetName().Name != "FerramAerospaceResearch") continue;
                Assembly a = la.assembly;
                Type api = a.GetType("FerramAerospaceResearch.FARAPI");
                Type util = a.GetType("FerramAerospaceResearch.FARAeroUtil");
                Type atm = a.GetType("FerramAerospaceResearch.FARAtmosphere");
                farVesselAeroType = a.GetType("FerramAerospaceResearch.FARAeroComponents.FARVesselAero");
                if (api == null) return false;
                farCalc = api.GetMethod("CalculateVesselAeroForces", BindingFlags.Public | BindingFlags.Static);
                farRefArea = api.GetMethod("VesselRefArea", BindingFlags.Public | BindingFlags.Static);
                farVoxValid = api.GetMethod("VesselVoxelizationCompletedAndValid", BindingFlags.Public | BindingFlags.Static);
                if (util != null)
                {
                    farRe = util.GetMethod("CalculateReynoldsNumber", BindingFlags.Public | BindingFlags.Static, null,
                        new[] { typeof(double), typeof(double), typeof(double), typeof(double), typeof(double), typeof(double) }, null);
                    farCf = util.GetMethod("SkinFrictionDrag", BindingFlags.Public | BindingFlags.Static, null,
                        new[] { typeof(double), typeof(double) }, null);
                }
                if (farVesselAeroType != null) farLength = farVesselAeroType.GetProperty("Length");
                if (atm != null) farIsCustom = atm.GetProperty("IsCustom", BindingFlags.Public | BindingFlags.Static);
                break;
            }
            return farCalc != null;
        }

        double FarLength(Vessel v)
        {
            if (farVesselAeroType == null || farLength == null) return 0;
            Component c = v.GetComponent(farVesselAeroType);
            if (c == null) return 0;
            try { return Convert.ToDouble(farLength.GetValue(c, null)); } catch { return 0; }
        }

        static double Inv(MethodInfo m, params object[] a)
        {
            if (m == null) return double.NaN;
            try { return Convert.ToDouble(m.Invoke(null, a)); } catch { return double.NaN; }
        }

        string FarInfo()
        {
            if (!FarFind()) return "FAR NOT FOUND";
            Vessel v = shared.Vessel;
            bool custom = false;
            try { if (farIsCustom != null) custom = (bool)farIsCustom.GetValue(null, null); } catch { }
            bool vox = false;
            try { vox = (bool)farVoxValid.Invoke(null, new object[] { v }); } catch { }
            return string.Format(CultureInfo.InvariantCulture, "FAR FOUND voxels {0} refArea {1:0.###} m2 length {2:0.###} m{3}",
                vox ? "VALID" : "NOT VALID", Inv(farRefArea, v), FarLength(v), custom ? " ATMOSPHERE REPLACED BY A MOD" : "");
        }

        // FARCHUTE (log only): the vessel's first RealChuteFAR as one line, "" without one: its state, its area (m2), the
        // height it compares with deployAltitude (trueAlt: the part's altitude less the terrain's), deployAltitude, the
        // time on its drag timer against the reef's 1 / semiDeploymentSpeed, armed, staged. RealChuteFAR.FixedUpdate takes
        // PREDEPLOYED to DEPLOYED once trueAlt <= deployAltitude and the timer is past the reef's time.
        static string FarChute(Vessel v)
        {
            if (v == null) return "";
            try
            {
                const BindingFlags I = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
                foreach (Part p in v.parts)
                    foreach (PartModule m in p.Modules)
                    {
                        Type t = m.GetType();
                        if (t.Name != "RealChuteFAR") continue;
                        Func<string, object> fld = n => { FieldInfo fi = t.GetField(n, I); return fi != null ? fi.GetValue(m) : null; };
                        PropertyInfo ds = t.GetProperty("DeploymentState", I);
                        object dt = fld("dragTimer");
                        PropertyInfo el = dt != null ? dt.GetType().GetProperty("Elapsed") : null;
                        object ts = el != null ? el.GetValue(dt, null) : null;
                        double semi = ObjNum(fld("semiDeploymentSpeed"));
                        return string.Format(CultureInfo.InvariantCulture,
                            "{0}: state {1}, area {2:0.00} m2, trueAlt {3:0.0} m (asl {4:0.0}, terrain {5:0.0}), deployAltitude {6:0}, "
                            + "timer {7:0.0} s (reef {8:0.0} s), armed {9}, staged {10}, landed {11}",
                            p.partInfo != null ? p.partInfo.name : p.name, ds != null ? ds.GetValue(m, null) : "?",
                            ObjNum(fld("currentArea")), ObjNum(fld("trueAlt")), ObjNum(fld("asl")), v.pqsAltitude,
                            ObjNum(fld("deployAltitude")), ts is TimeSpan ? ((TimeSpan)ts).TotalSeconds : double.NaN,
                            semi > 0 ? 1 / semi : double.NaN, fld("armed"), fld("staged"), v.LandedOrSplashed);
                    }
            }
            catch (Exception ex) { return "error " + ex.GetType().Name + ": " + ex.Message; }
            return "";
        }

        static double ObjNum(object o)
        {
            try { return o == null ? double.NaN : Convert.ToDouble(o, CultureInfo.InvariantCulture); }
            catch (Exception) { return double.NaN; }
        }

        // FTGROUNDCOLS (log only): SockFarTrim's terms of the last tick as the land DAP's csv columns ft_dm .. ft_ep, each
        // ",x" (kN m / kN, SockFarTrim's signs): dM (its moment rows + the brake's), dL (its lift), the sub elevator, colFix,
        // the gear's drag and lift, the elevon fix's pitch; seven empty columns without SockFarTrim. One string for both
        // DAPs (lib_dap's row and Dap.cs's), so the two rows stay equal.
        static readonly string[] ftGroundF = { "lastDM", "lastDL", "lastSE", "lastCol", "lastGD", "lastGL", "lastEP" };
        static readonly double[] ftGroundK = { 1e-3, 1e-3, 1e-3, 1e-3, 1, 1, 1e-3 };

        internal static string FtGroundCols(Vessel v)
        {
            PartModule ft = FarTrim(v);
            if (ft == null) return Dap.FT_NONE;
            var sb = new StringBuilder();
            Type t = ft.GetType();
            for (int i = 0; i < ftGroundF.Length; i++)
            {
                FieldInfo fi = t.GetField(ftGroundF[i], BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                if (fi == null) return Dap.FT_NONE;
                sb.Append(",").Append(Dap.KStr(Math.Round(ObjNum(fi.GetValue(ft)) * ftGroundK[i], 3)));
            }
            return sb.ToString();
        }
    }
}
