// THE KEYBOARD FOR ops2q: KSP's keys held off the ship while ops2q runs, and
// the keys ops2q wants read here and handed to kOS (kOS cannot read a key outside its own terminal).
//     STAGE   (all of ops2q): KSP's STAGING lock (the stage key never stages), and the stage key (GameSettings.LAUNCH_STAGES,
//             Space by default) is ENT. Every other key works as always (AG4, WASD, the warp keys ...).
//     TYPE    (while a TYPE box is open): EVERY key-driven control locked (ControlTypes.KEYBOARDINPUT: staging, the action
//             groups, abort, time warp, SAS / RCS / gear / brakes / lights, the map, quicksave / quickload, pause, the
//             flight controls) except the camera, so the mouse still turns the camera and clicks the window; the keys
//             0-9 (the main row and the keypad) . - + Backspace Enter Esc and the stage key are read: digits . - + edit,
//             Backspace = BKSP, Enter / the stage key = ENT, Esc = CAN; every other key does nothing.
//     OFF     no lock, nothing read.
// kOS asks for a mode every tick (ADDONS:KALS:KEYLOCK, KalsAddon.Keys.cs); THE WATCHDOG: a mode not asked for again within
// KEY_WATCHDOG s of real time drops to OFF (a kOS crash, a reboot or Ctrl+C can never leave the ship deaf to the keyboard).
// while the program that asked still runs (its kOS context current, the core on, its vessel active) the mode holds
// with no ask at all, so a long solve or the pause menu never lets the stage key STAGE; the 2 s count once it is gone.
// The locks also go when the flight scene ends.
// Nothing is read while kOS's terminal or a kOS GUI text field has the keyboard (their own locks kOSTerminal /
// kOSGUIWindow), nor while the game is paused. KSP.log: "[KalsKeys] mode A -> B (why)".
using System;
using System.Collections.Generic;
using UnityEngine;

namespace KalsCoproc
{
    public static class KalsKeys
    {
        public const double KEY_WATCHDOG = 2;      // s of real time without a KEYLOCK call: back to OFF
        public const int KEY_QUEUE = 64;           // keys held for kOS at most (the oldest dropped)
        public const string LOCK_STAGE = "kals_stage";
        public const string LOCK_TYPE = "kals_type";
        // TYPE's lock: every keyboard control but the camera's (ControlTypes.CAMERACONTROLS also holds the mouse's camera)
        public const ulong TYPE_MASK = (ulong)ControlTypes.KEYBOARDINPUT & ~(ulong)ControlTypes.CAMERACONTROLS;

        static string want = "OFF";               // the mode kOS asked for last
        static double wantT = -1E9;               // when (real time, s)
        static string mode = "OFF";               // the mode in force (the locks set)
        static readonly List<string> queue = new List<string>();

        public static string Mode { get { return mode; } }

        // the name kOS uses for a mode, or null for a word that is not one
        public static string Norm(string m)
        {
            string u = m == null ? "" : m.Trim().ToUpperInvariant();
            if (u == "" || u == "OFF") return "OFF";
            if (u == "STAGE" || u == "TYPE") return u;
            return null;
        }

        // The staging lock must never lapse during a long solve or the pause menu (Space would
        // STAGE): the program that asked holds the mode for as long as it still runs. holder (from KEYLOCK, KalsAddon.Keys.cs) says
        // whether it does: the same kOS program context still current, the core powered, its vessel the active one. While it
        // does, every frame refreshes the watchdog (a solve of many seconds, the pause menu: kOS stopped, the program not gone);
        // once it does not (Ctrl+C, a crash, a reboot, the core off, another vessel), it is dropped for good and the 2 s of real
        // time count from its last good frame, as before. A holder that throws counts as gone.
        static Func<bool> holder;

        // kOS's call: the mode wanted at real time now (a refresh of the watchdog); alive: the asking program's check (null: none)
        public static void Ask(string m, double now) { Ask(m, now, null); }
        public static void Ask(string m, double now, Func<bool> alive) { want = m; wantT = now; holder = m == "OFF" ? null : alive; }

        public static bool Held { get { return holder != null; } }

        // the asking program still runs (the holder is dropped the first time it does not)
        static bool HolderAlive()
        {
            if (holder == null) return false;
            bool ok;
            try { ok = holder(); } catch (Exception) { ok = false; }
            if (!ok) holder = null;
            return ok;
        }

        // the mode that should be in force at real time now: the one asked for while its program runs, else unless the
        // watchdog ran out
        public static string Due(double now)
        {
            if (want == "OFF") return "OFF";
            if (HolderAlive()) { wantT = now; return want; }
            if (now - wantT > KEY_WATCHDOG || now < wantT - 1) return "OFF";   // stale, or a clock that went back
            return want;
        }

        // the mode now in force (KalsKeyPad applied the locks); leaving TYPE drops the keys still held
        public static void Set(string m) { if (m != "TYPE") queue.Clear(); mode = m; }

        public static void Push(string k)
        {
            if (k == null) return;
            if (queue.Count >= KEY_QUEUE) queue.RemoveAt(0);
            queue.Add(k);
        }

        public static List<string> Drain() { var r = new List<string>(queue); queue.Clear(); return r; }

        public static void Reset() { want = "OFF"; wantT = -1E9; mode = "OFF"; holder = null; queue.Clear(); }

        // a key pressed in TYPE -> its name for ops2q (lib_o2ui o2Key: "0".."9" "." "-" "+" BKSP ENT CAN), else null.
        // shift = a Shift key held (Shift + = is '+'; a shifted digit or minus is a symbol: nothing)
        public static string TypeKey(KeyCode k, bool shift)
        {
            if (k >= KeyCode.Keypad0 && k <= KeyCode.Keypad9) return ((int)(k - KeyCode.Keypad0)).ToString();
            if (k >= KeyCode.Alpha0 && k <= KeyCode.Alpha9) return shift ? null : ((int)(k - KeyCode.Alpha0)).ToString();
            switch (k)
            {
                case KeyCode.KeypadPeriod: return ".";
                case KeyCode.Period: return shift ? null : ".";
                case KeyCode.KeypadMinus: return "-";
                case KeyCode.Minus: return shift ? null : "-";
                case KeyCode.KeypadPlus: return "+";
                case KeyCode.Plus: return "+";
                case KeyCode.Equals: return shift ? "+" : null;
                case KeyCode.Backspace: return "BKSP";
                case KeyCode.Return: case KeyCode.KeypadEnter: return "ENT";
                case KeyCode.Escape: return "CAN";
            }
            return null;
        }

        // the keys TYPE reads, in the order they are checked each frame
        public static readonly KeyCode[] TYPE_KEYS = {
            KeyCode.Alpha0, KeyCode.Alpha1, KeyCode.Alpha2, KeyCode.Alpha3, KeyCode.Alpha4, KeyCode.Alpha5, KeyCode.Alpha6,
            KeyCode.Alpha7, KeyCode.Alpha8, KeyCode.Alpha9, KeyCode.Keypad0, KeyCode.Keypad1, KeyCode.Keypad2,
            KeyCode.Keypad3, KeyCode.Keypad4, KeyCode.Keypad5, KeyCode.Keypad6, KeyCode.Keypad7, KeyCode.Keypad8,
            KeyCode.Keypad9, KeyCode.Period, KeyCode.KeypadPeriod, KeyCode.Minus, KeyCode.KeypadMinus, KeyCode.Plus,
            KeyCode.KeypadPlus, KeyCode.Equals, KeyCode.Backspace, KeyCode.Return, KeyCode.KeypadEnter, KeyCode.Escape };
    }

    // holds the locks for the mode due and reads the keys, once a frame in flight
    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class KalsKeyPad : MonoBehaviour
    {
        void Start() { KalsKeys.Reset(); Drop(); }

        void OnDestroy() { Drop(); KalsKeys.Reset(); }

        static void Drop()
        {
            InputLockManager.RemoveControlLock(KalsKeys.LOCK_STAGE);
            InputLockManager.RemoveControlLock(KalsKeys.LOCK_TYPE);
        }

        // the locks for mode m (called from Update and from KEYLOCK, both on the main thread)
        public static void Apply(string m, string why)
        {
            string was = KalsKeys.Mode;
            if (m == was) return;
            if (m == "OFF") Drop();
            else
            {
                InputLockManager.SetControlLock(ControlTypes.STAGING, KalsKeys.LOCK_STAGE);
                if (m == "TYPE") InputLockManager.SetControlLock((ControlTypes)KalsKeys.TYPE_MASK, KalsKeys.LOCK_TYPE);
                else InputLockManager.RemoveControlLock(KalsKeys.LOCK_TYPE);
            }
            KalsKeys.Set(m);
            Debug.Log("[KalsKeys] mode " + was + " -> " + m + " (" + why + ")");
        }

        static bool KosHasKeys()
        {
            return InputLockManager.GetControlLock("kOSTerminal") != ControlTypes.None
                || InputLockManager.GetControlLock("kOSGUIWindow") != ControlTypes.None;
        }

        void Update()
        {
            string due = KalsKeys.Due(Time.unscaledTime);
            if (due != KalsKeys.Mode) Apply(due, due == "OFF" ? "no KEYLOCK for " + KalsKeys.KEY_WATCHDOG + " s, or OFF" : "KEYLOCK");
            string m = KalsKeys.Mode;
            if (m == "OFF" || FlightDriver.Pause || KosHasKeys()) return;
            bool stg = GameSettings.LAUNCH_STAGES.GetKeyDown(true);   // true: read through our own STAGING lock
            if (m == "STAGE") { if (stg) KalsKeys.Push("ENT"); return; }
            bool shift = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
            foreach (KeyCode k in KalsKeys.TYPE_KEYS)
                if (Input.GetKeyDown(k)) KalsKeys.Push(KalsKeys.TypeKey(k, shift));
            // the stage key is ENT too, unless it is one of the keys just read (then it was read once already)
            if (stg && Array.IndexOf(KalsKeys.TYPE_KEYS, GameSettings.LAUNCH_STAGES.primary.code) < 0) KalsKeys.Push("ENT");
        }
    }
}
