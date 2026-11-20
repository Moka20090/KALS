// THE HUD WINDOW DRAWN BY C#.
// Until now the HUD's slots were kOS widgets: every HUD update wrote their IMAGE / TEXT / STYLE through kOS (HDAPPLY,
// in C# but still on kOS's widgets), and kOS laid out and drew the whole hdHud window in every GUI event (the
// painter removed only the layout). Here C# keeps ONE slot table (the truth) and draws it itself, in its own OnGUI pass,
// with no kOS window and no widget write per update:
//   - HWREG registers the slots (lib_hud's hdOrd: LIST(label, flow index)), the window's origin and the blank image;
//   - HWDRAW(HUDRENDER's / HUDGTICK's 4 op lists) updates the table; in every mode but WIN it also makes HDAPPLY's kOS
//     writes (the kOS twin stays current: instant fallback, and the A/B partner);
//   - modes: 0 OFF (kOS draws), 2 WIN (C# draws; the kOS window is hidden; no kOS writes);
//   - leaving WIN writes the whole table to the kOS widgets (Sync) before the kOS window shows again;
//   - any exception: state -1, the table is synced, kOS draws (HWERR says why).
// A slot's place, as kOS's layout gives it (Paint.cs RectOf): x = window X + Max(its box's padding.left, margin H),
// y = window Y + flow index + Max(its box's padding.top, margin V); size = the sprite's px (image slot: the size op), or the
// style's fixed width / height (text slot). Textures: kOS's own Widget.GetTexture (same loader, same cache), kept here by path.
// The window widget's Show / Hide belong to C# once registered (HWSHOW says whether the HUD is wanted: the HUD button,
// MAPVIEW). Mode switches happen in Update or in kOS's FixedUpdate, never inside an OnGUI.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using UnityEngine;
using kOS.Safe.Encapsulation;
using KLabel = kOS.Suffixed.Widget.Label;
using KWidget = kOS.Suffixed.Widget.Widget;

namespace KalsCoproc
{
    sealed class HwSlot
    {
        public KLabel L;
        public int Fl;                              // its flow index (hdOrd)
        public float BpL, BpT;                      // its 1x1 box's padding (Unity places a child at Max(padding, margin))
        public int Kind;                            // 0 never written, 1 image, 2 text
        public string Path = "";                    // the last img op
        public Texture2D Tex;
        public bool Shown;
        public double Size = 4, H, V;
        public string Text = "";
        public readonly GUIContent C = new GUIContent();
    }

    public static class HudWin
    {
        public const double LOG_S = 5.0;            // the KSP.log line's period
        public const int DEPTH = 1;                 // GUI.depth: a little behind kOS's own windows
        static List<HwSlot> slots = new List<HwSlot>();
        static readonly Dictionary<object, HwSlot> byLabel = new Dictionary<object, HwSlot>(new RefEq());
        static readonly Dictionary<string, Texture2D> tex = new Dictionary<string, Texture2D>(StringComparer.OrdinalIgnoreCase);
        static readonly HashSet<string> missing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        static KWidget win;                         // the kOS window (GUI): shown / hidden from here
        static bool winShown;                       // what we last told it
        static float winX, winY;
        static string clr = "";
        static int mode;                            // asked: 0 OFF, 2 WIN
        static bool want = true;                    // the HUD is wanted (HWSHOW)
        static bool registered, failed;
        static double logT;
        static Func<string, Texture2D> getTex;
        public static string Error = "";
        // draw cost
        static long drawTicks, drawN;

        static bool Drawing { get { return registered && !failed && want && mode == 2; } }

        static void Log(string s) { UnityEngine.Debug.Log("[KalsHudWin] " + s); }

        // ---- set up (kOS's FixedUpdate)
        // cfg = LIST(window, X, Y, blank image path, shown now); items = LIST(LIST(label, flow index), ...), every slot made so
        // far (a second call, after lib_hudg's slots, keeps the state of the labels it already knew)
        public static string Register(KWidget window, double x, double y, string blank, bool shown, List<KLabel> labels, List<int> fls)
        {
            try
            {
                if (getTex == null)
                {
                    MethodInfo gt = typeof(KWidget).GetMethod("GetTexture", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
                    if (gt == null) return "kOS Widget has no GetTexture";
                    getTex = (Func<string, Texture2D>)Delegate.CreateDelegate(typeof(Func<string, Texture2D>), gt);
                }
                var ns = new List<HwSlot>(labels.Count);
                var seen = new HashSet<object>(new RefEq());
                for (int i = 0; i < labels.Count; i++)
                {
                    KLabel l = labels[i];
                    if (l == null) return "slot " + i + " is not a label";
                    if (!seen.Add(l)) return "slot " + i + " is listed twice";
                    HwSlot s;
                    if (!byLabel.TryGetValue(l, out s)) s = new HwSlot { L = l };
                    s.Fl = fls[i];
                    KWidget bx = l.GetParent();
                    RectOffset p = (bx == null || bx.ReadOnlyStyle == null) ? null : bx.ReadOnlyStyle.padding;
                    s.BpL = p == null ? 0 : p.left; s.BpT = p == null ? 0 : p.top;
                    ns.Add(s);
                }
                byLabel.Clear();
                foreach (var s in ns) byLabel[s.L] = s;
                slots = ns;
                win = window; winX = (float)x; winY = (float)y; clr = blank ?? "";
                if (!registered) { want = shown; winShown = shown; }
                registered = true; failed = false; Error = "";
                Log("registered " + slots.Count + " slots, window at (" + winX + ", " + winY + ")");
                return "";
            }
            catch (Exception ex) { return "HWREG: " + ex.GetType().Name + ": " + ex.Message; }
        }

        // the HUD is gone (hdClose): forget everything, show nothing of ours
        public static void Drop()
        {
            if (!registered) return;
            mode = 0; registered = false;
            slots = new List<HwSlot>(); byLabel.Clear(); win = null;
        }

        // ---- the table (kOS's FixedUpdate): the same 4 lists as HDAPPLY
        static HwSlot Slot(Structure l)
        {
            HwSlot s;
            if (!byLabel.TryGetValue(l, out s)) throw new Exception("a label that is not a registered slot");
            return s;
        }

        static bool Eq(string a, string b) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }

        public static string Draw(ListValue rr)
        {
            if (!registered) return "error HWDRAW: not registered";
            if (failed) return "error HWDRAW: failed: " + Error;
            try
            {
                var o = (ListValue)rr[0];
                for (int k = 0; k + 1 < o.Count; k += 2)
                {
                    HwSlot s = Slot(o[k]);
                    string p = o[k + 1].ToString();
                    s.Kind = 1; s.Path = p;
                    if (Eq(p, clr)) { s.Tex = null; s.Shown = false; s.C.image = null; }
                    else { s.Tex = Tex(p); s.Shown = true; s.C.image = s.Tex; s.C.text = ""; }
                }
                o = (ListValue)rr[1];
                for (int k = 0; k + 1 < o.Count; k += 2) Slot(o[k]).Size = ((ScalarValue)o[k + 1]).GetDoubleValue();
                o = (ListValue)rr[2];
                for (int k = 0; k + 2 < o.Count; k += 3)
                {
                    HwSlot s = Slot(o[k]);
                    // Slot 79: kOS's margin is a whole pixel (RectOffset int; it rounds half to even), the text slots' margins
                    // are x.5 (HD_OFF_X / HD_OFF_Y 2.5): the table keeps what kOS would have laid out, else a .5 px offset
                    s.H = Math.Round(((ScalarValue)o[k + 1]).GetDoubleValue(), MidpointRounding.ToEven);
                    s.V = Math.Round(((ScalarValue)o[k + 2]).GetDoubleValue(), MidpointRounding.ToEven);
                }
                o = (ListValue)rr[3];
                for (int k = 0; k + 1 < o.Count; k += 2)
                {
                    HwSlot s = Slot(o[k]);
                    string t = o[k + 1].ToString();
                    s.Kind = 2; s.Text = t; s.Shown = t.Length != 0; s.C.image = null; s.C.text = t;
                }
                if (mode != 2) WApply.Hud(rr, clr);     // the kOS twin stays current (OFF)
                return "";
            }
            catch (Exception ex)
            {
                string why = "HWDRAW: " + ex.GetType().Name + ": " + ex.Message;
                FailNow(why);
                return "error " + why;
            }
        }

        static Texture2D Tex(string path)
        {
            Texture2D t;
            if (tex.TryGetValue(path, out t)) return t;
            t = getTex(path);
            if (t == null || t.width < 2)
            {
                if (missing.Add(path)) Log("texture missing: " + path);
                t = null;
            }
            tex[path] = t;
            return t;
        }

        // the whole table to the kOS widgets (leaving WIN, a failure)
        public static string Sync()
        {
            try
            {
                var img = new List<Structure>(); var siz = new List<Structure>(); var mar = new List<Structure>(); var txt = new List<Structure>();
                foreach (var s in slots)
                {
                    if (s.Kind == 0) continue;
                    if (s.Kind == 1) { img.Add(s.L); img.Add(new StringValue(s.Path)); siz.Add(s.L); siz.Add(ScalarValue.Create(s.Size)); }
                    mar.Add(s.L); mar.Add(ScalarValue.Create(s.H)); mar.Add(ScalarValue.Create(s.V));
                    if (s.Kind == 2) { txt.Add(s.L); txt.Add(new StringValue(s.Text)); }
                }
                var rr = new ListValue();
                rr.Add(new ListValue(img)); rr.Add(new ListValue(siz)); rr.Add(new ListValue(mar)); rr.Add(new ListValue(txt));
                WApply.Hud(rr, clr);
                return "";
            }
            catch (Exception ex) { return "sync: " + ex.GetType().Name + ": " + ex.Message; }
        }

        // ---- modes
        public static string SetMode(int m)
        {
            if (!registered) return "not registered";
            if (failed) return "failed: " + Error;
            if (m != 0 && m != 2) return "mode " + m + " is not 0 or 2";
            if (mode == 2 && m != 2) { string e = Sync(); if (e != "") { FailNow(e); return e; } }
            mode = m;
            ApplyWin();
            Log("mode " + ModeName(m));
            return "";
        }

        static string ModeName(int m) { return m == 0 ? "OFF" : "WIN"; }

        // the HUD is wanted or not (the HUD button, MAPVIEW): C# shows / hides the kOS window as the mode needs
        public static void SetWant(bool on)
        {
            want = on;
            ApplyWin();
        }

        // -1 failed, -2 not registered, else the mode asked
        public static int State() { return !registered ? -2 : failed ? -1 : mode; }

        // kOS's window visible exactly when the HUD is wanted and C# is not drawing it
        static void ApplyWin()
        {
            if (win == null) return;
            bool kosShow = want && !Drawing;
            if (kosShow == winShown) return;
            try { if (kosShow) win.Show(); else win.Hide(); winShown = kosShow; }
            catch (Exception ex) { FailNow("window: " + ex.Message); }
        }

        static void FailNow(string why)
        {
            if (failed) return;
            failed = true; Error = why;
            Log("FAILED " + why + " -- kOS draws the HUD");
            try { Sync(); } catch (Exception) { }
            mode = 0;
            try { if (win != null) { win.Show(); winShown = true; } } catch (Exception) { }
        }

        // ---- the draw (OnGUI, Repaint)
        static Rect RectOf(HwSlot s, GUIStyle st)
        {
            float w, h;
            if (s.Kind == 2) { w = st.fixedWidth; h = st.fixedHeight; } else { w = h = (float)s.Size; }
            return new Rect(winX + Mathf.Max(s.BpL, (float)s.H), winY + s.Fl + Mathf.Max(s.BpT, (float)s.V), w, h);
        }

        public static void OnGui()
        {
            if (!registered || failed) return;
            Event e = Event.current;
            if (e == null || e.type != EventType.Repaint) return;
            if (!Drawing) return;
            try
            {
                GUI.depth = DEPTH;
                long t0 = Stopwatch.GetTimestamp();
                for (int i = 0; i < slots.Count; i++)
                {
                    HwSlot s = slots[i];
                    if (!s.Shown) continue;
                    if (s.Kind == 1 && s.Tex == null) continue;
                    GUIStyle st = s.L.ReadOnlyStyle;
                    if (st == null) continue;
                    GUI.Label(RectOf(s, st), s.C, st);
                }
                drawTicks += Stopwatch.GetTimestamp() - t0; drawN++;
            }
            catch (Exception ex) { FailNow("OnGUI: " + ex.GetType().Name + ": " + ex.Message); }
        }

        // ---- Update (HudWinGui): the KSP.log line
        public static void Tick()
        {
            if (!registered || failed) return;
            double now = Time.realtimeSinceStartup;
            if (now - logT < LOG_S) return;
            logT = now;
            if (mode == 0) return;
            string s = "mode " + ModeName(mode);
            if (drawN > 0) s += string.Format("; draw {0:F3} ms a Repaint over {1}", drawTicks * 1000.0 / Stopwatch.Frequency / drawN, drawN);
            Log(s);
            drawTicks = 0; drawN = 0;
        }
    }

    // Update + OnGUI for the HUD window; everything dropped when the flight scene ends
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class HudWinGui : MonoBehaviour
    {
        void Update() { try { HudWin.Tick(); } catch (Exception) { } }
        void OnGUI() { try { HudWin.OnGui(); } catch (Exception) { } }
        void OnDestroy() { try { HudWin.Drop(); } catch (Exception) { } }
    }
}
