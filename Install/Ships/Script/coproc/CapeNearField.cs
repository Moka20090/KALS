// The Katniss Cape water. Mirage draws Earth's ground from its own height tiles past the PQS
// material's _NearFieldEnd (blended over _BlendWidth) from the camera, which drops every PQS mod after MirageTerrain,
// the KK map decals (KALS_CapeWater) included. Sol ships 1000 / 500 m (250 / 125 on the Quarter scale), so the Cape's sunk
// ground showed only within a few hundred metres of the camera. Widening it everywhere (a global cfg) costs the distant terrain's detail on all of Earth,
// so this addon widens it only while the camera is near the Cape: within onKm of the decal's centre it sets Earth's PQS
// materials to nearFieldEnd / blendWidth, beyond offKm (hysteresis) it puts back the values it read from each material
// before its first write (Sol's, not hard-coded; 250 / 125 m on the Quarter scale). The check runs about once a second.
// Flight and Space Center scenes only. Runtime-proved 11-03 in the Space Center (the property takes: the Cape water draws at
// the same camera with 60000, not with 250; ON / OFF / the hysteresis logged at 100 .. 200 km).
// ON only where GameData holds a KALS_CAPE_NEARFIELD node (GameData/KALS_CapeWater/KALS_CapeNearField.cfg, stock tree);
// no node = this addon does nothing. The node:
//   KALS_CAPE_NEARFIELD { body = Earth, decal = KALS_CapeWater (the KK_MapDecal Name: its Latitude / Longitude are the
//   centre; latitude / longitude here when there is no such decal), onKm = 150, offKm = 175, nearFieldEnd = 60000,
//   blendWidth = 20000 }
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public class CapeNearField : MonoBehaviour
    {
        const string NodeName = "KALS_CAPE_NEARFIELD";
        const string PropEnd = "_NearFieldEnd", PropBlend = "_BlendWidth";

        string bodyName = "Earth";
        double lat, lon, onM, offM;
        float nfe, bw;
        bool on;
        string lastErr;
        readonly Dictionary<Material, float[]> orig = new Dictionary<Material, float[]>();
        List<Material> mats = new List<Material>();

        static void Log(string s) { Debug.Log("[KalsCapeNearField] " + s); }

        static double Num(ConfigNode n, string key, double dflt)
        {
            double v;
            return n.HasValue(key) && double.TryParse(n.GetValue(key), NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : dflt;
        }

        bool armed, retired;

        void Start() { DontDestroyOnLoad(gameObject); StartCoroutine(Loop()); }

        // the GameDatabase is not ready at Instantly: read the node on the first tick after it is
        void Arm()
        {
            ConfigNode[] nodes = GameDatabase.Instance.GetConfigNodes(NodeName);
            if (nodes == null || nodes.Length == 0) { Log("no " + NodeName + " node in GameData: off"); retired = true; return; }
            ConfigNode n = nodes[0];
            if (n.HasValue("body")) bodyName = n.GetValue("body");
            lat = Num(n, "latitude", double.NaN); lon = Num(n, "longitude", double.NaN);
            string decal = n.HasValue("decal") ? n.GetValue("decal") : null;
            if (decal != null)
                foreach (ConfigNode d in GameDatabase.Instance.GetConfigNodes("KK_MapDecal"))
                    if (d.GetValue("Name") == decal)
                    {
                        lat = Num(d, "Latitude", lat); lon = Num(d, "Longitude", lon);
                        Log("centre from the KK_MapDecal " + decal);
                        break;
                    }
            if (double.IsNaN(lat) || double.IsNaN(lon)) { Log("no centre (no KK_MapDecal '" + decal + "', no latitude / longitude): off"); retired = true; return; }
            onM = Num(n, "onKm", 150) * 1000.0; offM = Math.Max(Num(n, "offKm", 175) * 1000.0, onM);
            nfe = (float)Num(n, "nearFieldEnd", 60000); bw = (float)Num(n, "blendWidth", 20000);
            Log("armed: " + bodyName + " centre " + lat.ToString("F4", CultureInfo.InvariantCulture) + " " + lon.ToString("F4", CultureInfo.InvariantCulture)
                + ", on within " + (onM / 1000.0) + " km, off beyond " + (offM / 1000.0) + " km, " + PropEnd + " " + nfe + " " + PropBlend + " " + bw);
            armed = true;
        }

        IEnumerator Loop()
        {
            while (!retired)
            {
                yield return new WaitForSecondsRealtime(1f);
                try { Tick(); }
                catch (Exception e)
                {
                    string m = e.GetType().Name + " " + e.Message;
                    if (m != lastErr) { lastErr = m; Log("tick failed: " + m); }
                }
            }
        }

        static Camera ViewCamera()
        {
            if (HighLogic.LoadedScene == GameScenes.FLIGHT && FlightCamera.fetch != null && FlightCamera.fetch.mainCamera != null)
                return FlightCamera.fetch.mainCamera;
            return Camera.main;
        }

        // every Material field of the body's PQS that carries the near-field property, once each
        List<Material> Materials(PQS p)
        {
            var l = new List<Material>();
            foreach (FieldInfo f in typeof(PQS).GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            {
                if (f.FieldType != typeof(Material)) continue;
                Material m = f.GetValue(p) as Material;
                if (m != null && m.HasProperty(PropEnd) && !l.Contains(m)) l.Add(m);
            }
            return l;
        }

        void Tick()
        {
            if (!armed)
            {
                if (GameDatabase.Instance != null && GameDatabase.Instance.IsReady()) Arm();
                return;
            }
            // FlightGlobals.Bodies reads a field of FlightGlobals.fetch, which is null from the start-up until the first scene that
            // has a FlightGlobals object (a NullReferenceException 'tick failed' once at KSP start, caught and retried each second):
            // wait for it instead
            if (FlightGlobals.fetch == null) return;
            CelestialBody b = FlightGlobals.Bodies == null ? null : FlightGlobals.Bodies.Find(x => x != null && x.name == bodyName);
            if (b == null || b.pqsController == null) return;
            mats = Materials(b.pqsController);
            foreach (Material m in mats)
                if (!orig.ContainsKey(m))
                {
                    orig[m] = new float[] { m.GetFloat(PropEnd), m.HasProperty(PropBlend) ? m.GetFloat(PropBlend) : 0f };
                    Log("read " + bodyName + " material '" + m.name + "': " + PropEnd + " " + orig[m][0] + " " + PropBlend + " " + orig[m][1]);
                }

            double d = double.PositiveInfinity;
            Camera cam = ViewCamera();
            if (cam != null && (HighLogic.LoadedScene == GameScenes.FLIGHT || HighLogic.LoadedScene == GameScenes.SPACECENTER))
            {
                Vector3d c = b.GetWorldSurfacePosition(lat, lon, 0.0);
                Vector3 p = cam.transform.position;
                d = (c - new Vector3d(p.x, p.y, p.z)).magnitude;
            }
            if (!on && d < onM) { on = true; Log("ON: camera " + (d / 1000.0).ToString("F1", CultureInfo.InvariantCulture) + " km from the centre, " + Describe(nfe, bw)); }
            else if (on && d > offM)
            {
                on = false;
                Log("OFF: " + (double.IsInfinity(d) ? "no Flight / Space Center camera" : "camera " + (d / 1000.0).ToString("F1", CultureInfo.InvariantCulture) + " km from the centre") + ", restoring the values read at load");
            }
            foreach (Material m in mats)
            {
                float[] o = orig[m];
                float e = on ? nfe : o[0], w = on ? bw : o[1];
                if (m.GetFloat(PropEnd) != e) m.SetFloat(PropEnd, e);
                if (m.HasProperty(PropBlend) && m.GetFloat(PropBlend) != w) m.SetFloat(PropBlend, w);
            }
        }

        string Describe(float e, float w) { return mats.Count + " material(s): " + PropEnd + " " + e + " " + PropBlend + " " + w; }
    }
}
