// The pad break-up on the first launch of a KSP run: Raymarched Plume Trails 1.0.0 builds its cube mesh, the first time
// it needs one, from GameObject.CreatePrimitive(Cube) and drops the primitive with Object.Destroy, which takes effect
// only at the end of the frame. CapsuleTrail.Ensure does that inside LaunchSmokeController.FixedUpdate at SRB ignition,
// so the primitive's 1 m BoxCollider (layer 0, the parts' layer) sits at the world origin, which FlightDriver puts on
// the new vessel at a launch, through that physics tick, and the push tears the stack apart at the clamp release. The
// mesh is cached in a static field, so the later launches of the same run never build it again and fly.
// This addon fills those caches (CapsuleTrail's and FluidBlast's) once, at the main menu, where nothing can be hit, with
// the same built-in cube mesh, so the mod never builds the primitive in flight. It does nothing when the mod is absent,
// when a cache is already filled, or when a field is not where it is in 1.0.0.
using System;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.MainMenu, true)]
    public class PlumeTrailsCube : MonoBehaviour
    {
        const string PT_ASM = "RaymarchedPlumeTrails";
        static readonly string[] PT_TYPES = { "RaymarchedPlumeTrails.CapsuleTrail", "RaymarchedPlumeTrails.FluidBlast" };

        static void Log(string s) { Debug.Log("[KalsPlumeTrailsCube] " + s); }

        void Start()
        {
            Mesh cube = null;
            foreach (AssemblyLoader.LoadedAssembly a in AssemblyLoader.loadedAssemblies)
            {
                if (a.assembly == null || a.assembly.GetName().Name != PT_ASM) continue;
                foreach (string tn in PT_TYPES)
                {
                    Type t = a.assembly.GetType(tn);
                    FieldInfo f = t == null ? null
                        : t.GetField("cubeMesh", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
                    if (f == null || f.FieldType != typeof(Mesh)) { Log(tn + ".cubeMesh not found: left alone"); continue; }
                    if (f.GetValue(null) != null) { Log(tn + ".cubeMesh already set"); continue; }
                    if (cube == null)
                    {
                        GameObject g = GameObject.CreatePrimitive(PrimitiveType.Cube);
                        cube = g.GetComponent<MeshFilter>().sharedMesh;
                        DestroyImmediate(g);
                    }
                    f.SetValue(null, cube);
                    Log(tn + ".cubeMesh filled at the main menu");
                }
            }
        }
    }
}
