// The HUD kept live through
// the OPS 1 -> OPS 6 hand-off's gap (kOS loading ops6q: no kOS code runs; kOS compiles on a thread, so the game's Update
// goes on). Armed with the hand-off hold (ops1q asc_ho_hold), a MonoBehaviour runs lib_hud's update in C# at the HUD's
// rate: HoloHud's HudHost.State on kOS's last inputs (lib_hud hdCsIn at the arm) with the vessel's and the camera's parts read now,
// HudHost.Render on the runway's points from their geopositions, lib_hudg's GTick, and the widget writes kOS's
// hdCsApply would make, made here. The first HUD call kOS makes itself (HudHost.N moved: OPS 6's hdTick) ends it; so do
// an error, a missing widget and HoP.TMAX's time. lib_hud's hdFinalSwitch (the runway switch) is not run: the
// runway stays the one at the arm.
//     ADDONS:KALS:HOHUD(LIST(hdCam (or 0), lib_hud hdCsIn(), LIST(the runway's 7 GeoCoordinates) or LIST(), LIST(their 7
//         heights, m), HD_MAX_HZ, the time limit s, lib_hudg on)) -> "" or "error ..."
// The bounds' bottoms (hdCsIn's bm / bmr / bnr) move with the altitude and the radar altitude from their values at the arm.
using System;
using HoloHud;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        class HoHudDriver : MonoBehaviour
        {
            void Update() { HhFrame(); }
        }

        static bool hhOn, hhG, hhBs;
        static HudHost hhHost;
        // the HUD's C# is HoloHud.dll's (ADDONS:HOLO); this asks it for the host of this kOS CPU. A separate method that is never
        // inlined, so a missing HoloHud.dll fails HERE (caught: null = no HUD host) and not when HhArm is compiled.
        [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
        static HudHost HoloHost(kOS.Safe.Execution.ICpu cpu)
        {
            try { return HoloHud.HoloAddon.HostFor(cpu); } catch (System.Exception) { return null; }
        }
        static kOS.Safe.Execution.ICpu hhCpu;
        static Vessel hhVessel;
        static Structure hhCam;
        static ListValue hhIn;
        static double[] hhLat, hhLng, hhAlt;
        static double hhHz, hhTmax, hhT0, hhNext, hhAlt0, hhRad0;
        static double[] hhBm, hhBmr, hhBnr;
        static int hhN, hhFrames;
        static string hhWhy = "";
        static GameObject hhGo;

        partial void RegisterHoHud()
        {
            AddSuffix("HOHUD", new OneArgsSuffix<StringValue, ListValue>(l => new StringValue(HhArm(this, l))));
        }

        static double[] HhNums(Structure s)
        {
            var l = s as ListValue;
            if (l == null) return new double[0];
            var r = new double[l.Count];
            for (int k = 0; k < l.Count; k++) r[k] = HoD(l[k]);
            return r;
        }

        static string HhArm(KalsAddon a, ListValue l)
        {
            try
            {
                if (hhOn) HhOff("re-armed");
                Vessel v = a.shared.Vessel;
                if (v == null) return "error no vessel";
                HudHost hudHost = HoloHost(a.shared.Cpu);
                if (hudHost == null) return "error no HUD host";
                hhIn = (ListValue)l[1];
                if (hhIn.Count < 13) return "error hdCsIn has " + hhIn.Count + " items, want 13";
                hhBs = ((BooleanValue)hhIn[0]).Value;
                hhCam = hhBs ? l[0] : null;
                var geo = (ListValue)l[2];
                var hts = HhNums(l[3]);
                int ng = geo.Count;
                hhLat = new double[ng]; hhLng = new double[ng]; hhAlt = new double[ng];
                for (int k = 0; k < ng; k++)
                {
                    var g = (kOS.Suffixed.GeoCoordinates)geo[k];
                    hhLat[k] = g.Latitude; hhLng[k] = g.Longitude; hhAlt[k] = k < hts.Length ? hts[k] : 0;
                }
                hhHz = Math.Max(1, HoD(l[4]));
                hhTmax = HoD(l[5]);
                hhG = ((BooleanValue)l[6]).Value;
                hhBm = HhNums(hhIn[10]); hhBmr = HhNums(hhIn[11]); hhBnr = HhNums(hhIn[12]);
                hhAlt0 = v.altitude; hhRad0 = v.radarAltitude;
                hhHost = hudHost; hhCpu = a.shared.Cpu; hhVessel = v;
                hhN = hhHost.N; hhFrames = 0; hhWhy = ""; hhT0 = Planetarium.GetUniversalTime(); hhNext = 0;
                if (hhGo == null) { hhGo = new GameObject("KALS_HoHud"); hhGo.AddComponent<HoHudDriver>(); }
                hhOn = true;
                Debug.Log("[KalsCoproc] hand-off HUD coast on: camera " + hhBs + ", runway points " + ng + ", hudg " + hhG);
                return "";
            }
            catch (Exception ex) { hhOn = false; return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        static void HhOff(string why)
        {
            if (hhGo != null) { UnityEngine.Object.Destroy(hhGo); hhGo = null; }
            if (!hhOn) return;
            hhOn = false;
            hhWhy = why;
            hhCam = null; hhIn = null; hhHost = null; hhCpu = null; hhVessel = null;
            Debug.Log("[KalsCoproc] hand-off HUD coast off (" + why + ") after " + hhFrames + " frames");
        }

        static Structure HhSuf(Structure s, string n) { return s.GetSuffix(n).Value; }

        // lib_hud hdCsApply: LIST(img: widget, path ..., size: widget, px ..., margin: widget, H, V ..., text: widget, text ...)
        static void HhApply(ListValue rr)
        {
            var o = (ListValue)rr[0];
            for (int k = 0; k + 1 < o.Count; k += 2) o[k].SetSuffix("IMAGE", o[k + 1]);
            o = (ListValue)rr[1];
            for (int k = 0; k + 1 < o.Count; k += 2)
            {
                Structure st = HhSuf(o[k], "STYLE");
                st.SetSuffix("WIDTH", o[k + 1]);
                st.SetSuffix("HEIGHT", o[k + 1]);
            }
            o = (ListValue)rr[2];
            for (int k = 0; k + 2 < o.Count; k += 3)
            {
                Structure mg = HhSuf(HhSuf(o[k], "STYLE"), "MARGIN");
                mg.SetSuffix("H", o[k + 1]);
                mg.SetSuffix("V", o[k + 2]);
            }
            o = (ListValue)rr[3];
            for (int k = 0; k + 1 < o.Count; k += 2) o[k].SetSuffix("TEXT", o[k + 1]);
        }

        static ListValue HhShift(double[] a, double d)
        {
            var l = new ListValue();
            foreach (double x in a) l.Add(ScalarValue.Create(x + d));
            return l;
        }

        static void HhFrame()
        {
            if (!hhOn) return;
            try
            {
                if (hhHost.N != hhN) { HhOff("kOS's HUD update"); return; }
                Vessel v = hhVessel;
                if (v == null || !v.loaded || v != FlightGlobals.ActiveVessel) { HhOff("vessel"); return; }
                double ut = Planetarium.GetUniversalTime();
                if (ut - hhT0 > hhTmax) { HhOff("timeout " + HoF(hhTmax) + " s"); return; }
                double now = Time.realtimeSinceStartup;
                if (now < hhNext - 0.002) return;
                hhNext = Math.Max(hhNext, now - 1 / hhHz) + 1 / hhHz;
                if (MapView.MapIsEnabled) return;                       // lib_hud hides the HUD in the map
                Vector3d com = v.CoMD;
                Vector3d up = (com - v.mainBody.position).normalized;
                Vector3d vs = v.srf_velocity;
                var inp = new ListValue();
                inp.Add(new BooleanValue(hhBs));
                if (hhBs)
                {
                    Quaternion cr = ((kOS.Suffixed.Direction)HhSuf(hhCam, "FACING")).Rotation;
                    inp.Add(new kOS.Suffixed.Vector(cr * Vector3d.forward)); inp.Add(new kOS.Suffixed.Vector(cr * Vector3d.up));
                    inp.Add(new kOS.Suffixed.Vector(cr * Vector3d.right)); inp.Add(HhSuf(hhCam, "POSITION"));
                }
                else for (int k = 0; k < 4; k++) inp.Add(ScalarValue.Create(0));
                inp.Add(new kOS.Suffixed.Vector(up)); inp.Add(new kOS.Suffixed.Vector(vs));
                inp.Add(ScalarValue.Create(v.dynamicPressurekPa / 101.325));   // SHIP:Q, atm
                inp.Add(ScalarValue.Create(v.horizontalSrfSpeed));             // SHIP:GROUNDSPEED
                inp.Add(ScalarValue.Create(ut));
                double da = v.altitude - hhAlt0, dr = v.radarAltitude - hhRad0;
                inp.Add(HhShift(hhBm, da)); inp.Add(HhShift(hhBmr, dr)); inp.Add(HhShift(hhBnr, dr));
                StringValue er = hhHost.State(inp);
                if (er.ToString() != "") { HhOff("HUDSTATE: " + er); return; }
                var pos = new ListValue();
                if (hhBs)
                    for (int k = 0; k < hhLat.Length; k++)
                        pos.Add(new kOS.Suffixed.Vector(v.mainBody.GetWorldSurfacePosition(hhLat[k], hhLng[k], hhAlt[k]) - com));
                Structure rr = hhHost.Render(pos);
                if (!(rr is ListValue)) { HhOff("HUDRENDER: " + rr); return; }
                HhApply((ListValue)rr);
                if (hhG)
                {
                    hhCpu.SetGlobal("$hdgLit", new BooleanValue(Math.Floor(now * 4) % 2 == 0));   // lib_hudg's 2 Hz flash
                    Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
                    var gin = new ListValue();
                    gin.Add(new kOS.Suffixed.Vector(vs)); gin.Add(new kOS.Suffixed.Vector(up)); gin.Add(new kOS.Suffixed.Vector(F * Vector3d.up));
                    Structure rg = hhHost.GTick(gin);
                    if (!(rg is ListValue)) { HhOff("HUDGTICK: " + rg); return; }
                    HhApply((ListValue)rg);
                }
                hhN = hhHost.N;
                hhFrames++;
            }
            catch (Exception ex) { HhOff(ex.GetType().Name + ": " + ex.Message); }
        }
    }
}
