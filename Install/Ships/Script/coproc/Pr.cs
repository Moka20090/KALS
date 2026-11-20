// Principia read by reflection (the probe; the PLAN guidance builds on it). Principia 2026101016-Lichnerowicz
// has NO ExternalInterface (no principia__External* export in principia.dll, no ExternalInterface type in the adapter):
// the one way in is ksp_plugin_adapter's own internal static class principia.ksp_plugin_adapter.Interface (each method a
// wrapper of a principia__* export, the plugin's IntPtr first) and PrincipiaPluginAdapter's internal Plugin().
// Principia CHECK-fails (= KSP dies) on a bad call, so every read here is guarded as the adapter guards its own:
//   the plugin running (IntPtr != 0); HasVessel before any vessel call (GetVessel is FindOrDie); FlightPlanExists before
//   any flight-plan call; a manoeuvre index < NumberOfManoeuvres - NumberOfAnomalousManoeuvres (GetManoeuvre CHECKs);
//   the rendered burn segment's index odd (2 i + 1, CHECK_EQ(1, index % 2)); IteratorAtEnd before an iterator read;
//   a body's state (CelestialWorldDegreesOfFreedom) only at a time inside the ephemeris's span (ContinuousTrajectory
//   CHECKs t_min <= t <= t_max: we allow [CurrentTime, a time a flight plan or the prediction has reached]) and with a
//   reference part PartIsTruthful says the plugin holds (BarycentricToWorld FindOrDies the part).
// FRAMES (renderer.cpp): a rendered point's POSITION is in World, mapped from the plotting frame by the transform at
// the CURRENT time (so, in the default BODY_CENTRED_NON_ROTATING frame of the main body, q - body.position = the
// body-relative position at the point's time, in today's world axes); its VELOCITY is NOT in World axes (the plotting
// frame's coordinates, x and y swapped, "Lasciate ogne speranza"): use its magnitude only.
// FlightPlanGetManoeuvreInitialPlottedVelocity gives the ignition velocity properly rotated into World.
using System;
using System.Collections.Generic;
using System.Reflection;

namespace KalsCoproc
{
    public static class Pr
    {
        public const string WRITTEN_FOR = "2026101016-Lichnerowicz";
        const BindingFlags SF = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        const BindingFlags IF = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        public static Type TIface, TAdapter, TXyz, TQp, TOrigin, TBoxedDouble;
        static UnityEngine.Object adapter;
        static readonly Dictionary<string, MethodInfo> methods = new Dictionary<string, MethodInfo>();
        public static string Err = "";

        // The adapter assembly's types; false (Err says why) when Principia is not in the game.
        public static bool Find()
        {
            if (TIface != null) return true;
            foreach (Assembly a in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type t = null;
                try { t = a.GetType("principia.ksp_plugin_adapter.Interface", false); } catch (Exception) { }
                if (t == null) continue;
                TAdapter = a.GetType("principia.ksp_plugin_adapter.PrincipiaPluginAdapter", false);
                TXyz = a.GetType("principia.ksp_plugin_adapter.XYZ", false);
                TQp = a.GetType("principia.ksp_plugin_adapter.QP", false);
                TOrigin = a.GetType("principia.ksp_plugin_adapter.Origin", false);
                TBoxedDouble = a.GetType("principia.ksp_plugin_adapter.BoxedDouble", false);
                if (TAdapter == null || TXyz == null || TQp == null || TOrigin == null)
                {
                    Err = "the adapter's types moved (written for " + WRITTEN_FOR + ")";
                    return false;
                }
                TIface = t;
                return true;
            }
            Err = "Principia's ksp_plugin_adapter is not loaded";
            return false;
        }

        // The running plugin's handle, IntPtr.Zero when there is none (Err says why).
        public static IntPtr Plugin()
        {
            if (!Find()) return IntPtr.Zero;
            if (adapter == null) adapter = UnityEngine.Object.FindObjectOfType(TAdapter);
            if (adapter == null) { Err = "no PrincipiaPluginAdapter in this scene"; return IntPtr.Zero; }
            MethodInfo m = TAdapter.GetMethod("Plugin", IF, null, Type.EmptyTypes, null);
            if (m == null) { Err = "PrincipiaPluginAdapter.Plugin() is gone"; return IntPtr.Zero; }
            IntPtr p = (IntPtr)m.Invoke(adapter, null);
            if (p == IntPtr.Zero) Err = "the Principia plugin is not running";
            return p;
        }

        public static object Adapter() { return adapter; }

        public static MethodInfo Method(string name)
        {
            MethodInfo m;
            if (methods.TryGetValue(name, out m)) return m;
            foreach (MethodInfo c in TIface.GetMethods(SF)) if (c.Name == name) { m = c; break; }
            methods[name] = m;
            return m;
        }

        // Interface.<name>(args). An out parameter comes back in args (pass the array itself).
        public static object Call(string name, params object[] args)
        {
            MethodInfo m = Method(name);
            if (m == null) throw new MissingMethodException("principia Interface." + name);
            try { return m.Invoke(null, args); }
            catch (TargetInvocationException e) { throw e.InnerException ?? e; }
        }

        public static object Get(object o, string field)
        {
            FieldInfo f = o.GetType().GetField(field, IF);
            if (f != null) return f.GetValue(o);
            PropertyInfo p = o.GetType().GetProperty(field, IF);
            if (p == null) throw new MissingFieldException(o.GetType().Name + "." + field);
            return p.GetValue(o, null);
        }

        static void Set(object box, string field, object value) { box.GetType().GetField(field, IF).SetValue(box, value); }

        public static Vector3d V(object xyz)
        {
            return new Vector3d((double)Get(xyz, "x"), (double)Get(xyz, "y"), (double)Get(xyz, "z"));
        }

        public static object Xyz(Vector3d v)
        {
            object o = Activator.CreateInstance(TXyz);
            Set(o, "x", v.x); Set(o, "y", v.y); Set(o, "z", v.z);
            return o;
        }

        // An Origin that places the main body's centre at bodyWorld (reference_part_is_at_origin false) and names a part
        // the plugin holds (BarycentricToWorld finds it or dies: check PartIsTruthful first).
        public static object Origin(Vector3d bodyWorld, uint partId)
        {
            object o = Activator.CreateInstance(TOrigin);
            Set(o, "reference_part_is_at_origin_", (byte)0);
            Set(o, "reference_part_is_unmoving_", (byte)0);
            Set(o, "reference_part_id", partId);
            Set(o, "main_body_centre_in_world", Xyz(bodyWorld));
            return o;
        }

        public static void Dispose(object it)
        {
            IDisposable d = it as IDisposable;
            if (d != null) d.Dispose();
        }

        // A DistinguishedPoints iterator read out: (time, q world, v as rendered), then disposed.
        public struct Pt { public double T; public Vector3d Q, P; }
        public static List<Pt> Points(object it)
        {
            var r = new List<Pt>();
            if (it == null) return r;
            try
            {
                while (!(bool)Call("IteratorAtEnd", it))
                {
                    double t = (double)Call("IteratorGetDistinguishedPointsTime", it);
                    object qp = Call("IteratorGetDistinguishedPointsQP", it);
                    r.Add(new Pt { T = t, Q = V(Get(qp, "q")), P = V(Get(qp, "p")) });
                    Call("IteratorIncrement", it);
                }
            }
            finally { Dispose(it); }
            return r;
        }

        public static bool HasVessel(IntPtr p, string guid) { return p != IntPtr.Zero && (bool)Call("HasVessel", p, guid); }

        public static bool HasPlan(IntPtr p, string guid) { return HasVessel(p, guid) && (bool)Call("FlightPlanExists", p, guid); }

        // The manoeuvres a caller may index (the anomalous tail excluded, as the adapter does); 0 without a plan.
        public static int Manoeuvres(IntPtr p, string guid)
        {
            if (!HasPlan(p, guid)) return 0;
            return (int)Call("FlightPlanNumberOfManoeuvres", p, guid) - (int)Call("FlightPlanNumberOfAnomalousManoeuvres", p, guid);
        }

        // Manoeuvre i's ignition (the start of its burn segment 2 i + 1): the time, the position less the main body's
        // world position (body-relative, world axes, in a body-centred plotting frame) and the velocity in World.
        // False when i is out of range or the point is outside the plotting frame's span.
        public static bool Ignition(IntPtr p, string guid, int i, Vector3d sunWorld, Vector3d bodyWorld,
                                    out double t, out Vector3d r, out Vector3d v)
        {
            t = 0; r = Vector3d.zero; v = Vector3d.zero;
            if (i < 0 || i >= Manoeuvres(p, guid)) return false;
            List<Pt> pts = Points(Call("FlightPlanRenderedManoeuvreInitialDegreesOfFreedom", p, guid, Xyz(sunWorld), 2 * i + 1));
            if (pts.Count == 0) return false;
            t = pts[0].T;
            r = pts[0].Q - bodyWorld;
            v = V(Call("FlightPlanGetManoeuvreInitialPlottedVelocity", p, guid, i));
            return true;
        }

    }
}
