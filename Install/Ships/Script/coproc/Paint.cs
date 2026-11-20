// THE PAINTER. kOS's IMGUI lays out and draws every shown widget of a page in every GUI event (a slot = a 1x1 VLAYOUT
// box + a Label: BeginVertical / EndVertical, GetControlID, Int32.ToString, SetNextControlName, GUILayout.Label). Here a
// page's slot labels are drawn by C# instead, in kOS's own window, at the place in kOS's draw order of one PLACEHOLDER
// label (the page box's last child):
//   - in the Repaint event only, each registered label that is Shown (lib_taemdisp tdVis: it has something to draw) is
//     drawn with GUI.Label(rect, its own content, its own style): the primitive GUILayout.Label ends in, with the same
//     texture / font / colour / rich text; the rect is the one kOS's layout gives it: x = X0 + margin.left,
//     y = Y0 + flow index + margin.top, its fixed width / height (X0, Y0 from the placeholder's own layout rect);
//   - the slots' boxes (their 1x1 VLAYOUTs and the nested boxes holding them) are HIDDEN while painting, so kOS
//     neither lays them out nor draws them; they are shown again for any other mode, or on any failure.
// Modes: 0 OFF (kOS draws, as before), 2 PAINT. Mode switches happen in Update or in kOS's FixedUpdate (never between an
// OnGUI's Layout and Repaint).
// Nothing here throws into kOS: an exception switches that page back to kOS's drawing (boxes shown), PAINTERR says why.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.CompilerServices;
using UnityEngine;
using KLabel = kOS.Suffixed.Widget.Label;
using KWidget = kOS.Suffixed.Widget.Widget;
using KBox = kOS.Suffixed.Widget.Box;

namespace KalsCoproc
{
    sealed class RefEq : IEqualityComparer<object>
    {
        public new bool Equals(object a, object b) { return ReferenceEquals(a, b); }
        public int GetHashCode(object o) { return RuntimeHelpers.GetHashCode(o); }
    }

    public class PaintGroup
    {
        public string Name;
        public KLabel Ph;                           // the placeholder (the page box's last child)
        public int PhFl;                            // its flow index (its pixel row when every slot box is shown)
        public KLabel[] L;                          // the slots' labels, in creation (= kOS's draw) order
        public int[] Fl;                            // their flow indices (lib_taemdisp sl[1])
        public KWidget[] Bx; public KWidget PhBx;    // Each label's own box (its padding clamps the margin)
        public int Mode;                            // asked: 0 off, 2 paint
        public bool Painting;                       // now: the boxes hidden, C# draws
        public bool Failed;
        public readonly List<KWidget> Boxes = new List<KWidget>();   // the slots' boxes (hidden while painting)
        public long PaintTicks, PaintN;
    }

    public static class Painter
    {
        public const double PAINT_LOG_S = 5.0;      // PAINT: the KSP.log line's period (s of real time)
        static readonly Dictionary<string, PaintGroup> byName = new Dictionary<string, PaintGroup>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<object, PaintGroup> byPh = new Dictionary<object, PaintGroup>(new RefEq());
        static readonly Dictionary<object, KeyValuePair<PaintGroup, int>> byItem = new Dictionary<object, KeyValuePair<PaintGroup, int>>(new RefEq());
        static Func<KLabel, GUIContent> getContent;
        static bool patched, patchTried;
        public static string Error = "";
        static double logT;

        // ---- set up (kOS's thread: FixedUpdate)
        public static string Patch()
        {
            if (patched) return "";
            if (patchTried) return Error == "" ? "the Label.DoGUI patch failed" : Error;
            patchTried = true;
            try
            {
                MethodInfo gc = typeof(KLabel).GetMethod("get_content_visible", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
                if (gc == null) throw new Exception("kOS Label has no content_visible");
                getContent = (Func<KLabel, GUIContent>)Delegate.CreateDelegate(typeof(Func<KLabel, GUIContent>), gc);
                MethodInfo dg = typeof(KLabel).GetMethod("DoGUI", BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly);
                if (dg == null) throw new Exception("kOS Label has no DoGUI");
                var h = new HarmonyLib.Harmony("kals.painter");
                h.Patch(dg, postfix: new HarmonyLib.HarmonyMethod(typeof(Painter).GetMethod("Post", BindingFlags.Static | BindingFlags.NonPublic)));
                patched = true;
                return "";
            }
            catch (Exception ex) { Error = "patch: " + ex.GetType().Name + ": " + ex.Message; return Error; }
        }

        // a page's group: name, the placeholder and its flow index, the labels and theirs. Replaces a group of that name.
        public static string Register(string name, KLabel ph, int phFl, List<KLabel> labels, List<int> fls, KBox page)
        {
            string e = Patch();
            if (e != "") return e;
            try
            {
                Drop(name);
                var g = new PaintGroup { Name = name, Ph = ph, PhFl = phFl, L = labels.ToArray(), Fl = fls.ToArray() };
                g.Bx = new KWidget[g.L.Length];
                var seen = new HashSet<object>(new RefEq());
                for (int i = 0; i < g.L.Length; i++)
                {
                    if (g.L[i] == null || ReferenceEquals(g.L[i], ph)) throw new Exception("slot " + i + " is not a label of its own");
                    if (byItem.ContainsKey(g.L[i])) throw new Exception("slot " + i + " is in another group");
                    KWidget w = g.L[i].GetParent();      // its 1x1 box, then the nested box (if any), up to the page box
                    g.Bx[i] = w;
                    int up = 0;
                    while (w != null && !ReferenceEquals(w, page))
                    {
                        if (seen.Add(w)) g.Boxes.Add(w);
                        w = w.GetParent();
                        if (++up > 8) throw new Exception("slot " + i + " is not inside the page box");
                    }
                    if (w == null) throw new Exception("slot " + i + " is not inside the page box");
                }
                KBox pb = ph.GetParent();
                g.PhBx = pb;
                if (pb == null || !ReferenceEquals(pb.GetParent(), page))
                    throw new Exception("the placeholder's box is not a child of the page box");
                if (seen.Contains(ph.GetParent())) throw new Exception("the placeholder shares a box with a slot");
                byName[name] = g;
                byPh[ph] = g;
                for (int i = 0; i < g.L.Length; i++) byItem[g.L[i]] = new KeyValuePair<PaintGroup, int>(g, i);
                Log(name + ": " + g.L.Length + " labels, " + g.Boxes.Count + " boxes, placeholder at flow " + phFl);
                return "";
            }
            catch (Exception ex) { return "register " + name + ": " + ex.GetType().Name + ": " + ex.Message; }
        }

        public static void Drop(string name)
        {
            PaintGroup g;
            if (!byName.TryGetValue(name, out g)) return;
            SetPainting(g, false);
            byName.Remove(name);
            byPh.Remove(g.Ph);
            foreach (var l in g.L) byItem.Remove(l);
        }

        public static void DropAll()
        {
            foreach (var n in new List<string>(byName.Keys)) Drop(n);
        }

        // mode 0 off, 2 paint: the boxes follow at once (kOS's FixedUpdate is outside OnGUI)
        public static string SetMode(string name, int mode)
        {
            PaintGroup g;
            if (!byName.TryGetValue(name, out g)) return "no group " + name;
            if (g.Failed) return "failed: " + Error;
            if (mode != 0 && mode != 2) return "mode " + mode + " is not 0 or 2";
            g.Mode = mode;
            SetPainting(g, mode == 2);
            Log(name + ": mode " + ModeName(mode));
            return "";
        }

        // what kOS reads each draw: -1 failed (kOS draws; its boxes are shown), else the mode asked
        public static int State(string name)
        {
            PaintGroup g;
            if (!byName.TryGetValue(name, out g)) return -2;
            return g.Failed ? -1 : g.Mode;
        }

        static string ModeName(int m) { return m == 0 ? "OFF" : "PAINT"; }

        static void SetPainting(PaintGroup g, bool on)
        {
            if (g.Painting == on) return;
            try { foreach (var b in g.Boxes) { if (on) b.Hide(); else b.Show(); } g.Painting = on; }
            catch (Exception ex) { Fail(g, "boxes: " + ex.Message); }
        }

        static void Fail(PaintGroup g, string why)
        {
            if (g.Failed) return;
            g.Failed = true;
            Error = g.Name + ": " + why;
            Log("FAILED " + Error + " -- kOS draws this page");
            try { foreach (var b in g.Boxes) b.Show(); } catch (Exception) { }
            g.Painting = false;
            g.Mode = 0;
        }

        static void Log(string s) { UnityEngine.Debug.Log("[KalsPaint] " + s); }

        // ---- Update (PaintTick): the KSP.log lines
        public static void Tick()
        {
            if (byName.Count == 0) return;
            double now = Time.realtimeSinceStartup;
            if (now - logT < PAINT_LOG_S) return;
            logT = now;
            foreach (var g in byName.Values)
            {
                if (g.Failed || g.Mode == 0) continue;
                string s = g.Name + ": " + ModeName(g.Mode);
                if (g.PaintN > 0) s += string.Format("; paint {0:F3} ms a Repaint over {1}", g.PaintTicks * 1000.0 / Stopwatch.Frequency / g.PaintN, g.PaintN);
                Log(s);
                g.PaintTicks = 0; g.PaintN = 0;
            }
        }

        // ---- the Label.DoGUI postfix (inside kOS's window callback)
        static void Post(KLabel __instance)
        {
            if (byPh.Count == 0) return;
            try
            {
                if (Event.current == null || Event.current.type != EventType.Repaint) return;
                PaintGroup g;
                if (byPh.TryGetValue(__instance, out g)) AtPh(g, GUILayoutUtility.GetLastRect());
            }
            catch (Exception ex)
            {
                PaintGroup g;
                if (byPh.TryGetValue(__instance, out g)) Fail(g, "postfix: " + ex.GetType().Name + ": " + ex.Message);
                else if (Error == "") Error = "postfix: " + ex.Message;
            }
        }

        static Rect RectOf(PaintGroup g, int i, float x0, float y0)
        {
            GUIStyle st = g.L[i].ReadOnlyStyle;
            float w = st.fixedWidth, h = st.fixedHeight;
            if (w <= 0 || h <= 0)
            {
                // ENTRY TRAJ's markers: a width, no height: GUILayout's own size of a label, CalcSize (CalcHeight
                // at the width when it wraps)
                GUIContent c = getContent(g.L[i]);
                Vector2 sz = st.CalcSize(c);
                if (w <= 0) w = sz.x;
                if (h <= 0) h = st.wordWrap ? st.CalcHeight(c, w) : sz.y;
            }
            // Unity's vertical group places its child at Max(padding, margin) (GUILayoutGroup.SetVertical /
            // SetHorizontal): a negative margin draws at the box's edge (p12: TJ's clock, margin -2)
            RectOffset bp = PadOf(g.Bx[i]);
            return new Rect(x0 + Mathf.Max(bp.left, st.margin.left), y0 + g.Fl[i] + Mathf.Max(bp.top, st.margin.top), w, h);
        }

        static readonly RectOffset NoPad = new RectOffset();
        static RectOffset PadOf(KWidget b)
        {
            if (b == null) return NoPad;
            GUIStyle s = b.ReadOnlyStyle;
            return s == null ? NoPad : s.padding;
        }

        static void AtPh(PaintGroup g, Rect p)
        {
            if (g.Failed || !g.Painting) return;
            GUIStyle ps = g.Ph.ReadOnlyStyle;
            RectOffset pp = PadOf(g.PhBx);
            float x0 = p.x - Mathf.Max(pp.left, ps.margin.left);
            // every slot box hidden: the placeholder's box is the page box's first shown child (its flow row 0)
            float y0 = p.y - Mathf.Max(pp.top, ps.margin.top);
            long t = Stopwatch.GetTimestamp();
            for (int i = 0; i < g.L.Length; i++)
            {
                KLabel l = g.L[i];
                if (!l.Shown) continue;
                GUI.Label(RectOf(g, i, x0, y0), getContent(l), l.ReadOnlyStyle);
            }
            g.PaintTicks += Stopwatch.GetTimestamp() - t; g.PaintN++;
        }
    }

    // Update for the painter (the log lines); every group dropped when the flight scene ends
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class PaintTick : MonoBehaviour
    {
        void Update() { try { Painter.Tick(); } catch (Exception) { } }
        void OnDestroy() { try { Painter.DropAll(); } catch (Exception) { } }
    }
}
