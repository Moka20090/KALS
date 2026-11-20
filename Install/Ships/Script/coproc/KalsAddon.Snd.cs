// SOUND: ADDONS:KALS plays a short sound file from GameData/KALS_CW/Sounds (the C&W tones; the failure sounds reuse it).
//     ADDONS:KALS:SNDPLAY(name, loop)   start <name>.wav (restarts it if playing); loop TRUE = until SNDSTOP. TRUE when playing,
//                                       FALSE when the clip is missing (the caller keeps its kOS voice fallback).
//     ADDONS:KALS:SNDSTOP(name)         stop it (TRUE when it was playing).
//     ADDONS:KALS:SNDVOL(v)             the level multiplier 0..1 for every file sound (default 0.5; KSP's master and UI sliders apply on top).
// volume = Level x GameSettings.MASTER_VOLUME x UI_VOLUME, applied here (ignoreListenerVolume, so never counted twice) and
// refreshed 5 times a second; every source stops when the scene changes (revert, quickload, KSC, flight) or the active vessel
// changes, and pauses with the game (onGamePause / onGameUnpause, and Time.timeScale 0 as a poll).
// The clip comes from KSP's own GameDatabase (".wav" files in GameData become AudioClips at game start: url "KALS_CW/Sounds/<name>");
// if that has none, the file is read here (16 bit PCM WAV, mono or stereo). One AudioSource per name on one root object.
using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public static class KalsSnd
    {
        public const string Dir = "KALS_CW/Sounds/";
        static GameObject root;
        static readonly Dictionary<string, AudioSource> src = new Dictionary<string, AudioSource>();
        static readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>();
        // The level multiplier, default 0.5; kOS trims it with SNDVOL(v), also while a sound plays.
        // The project owner heard the alarm with the master slider down: AudioListener.volume did not carry it (the earlier model was wrong
        // for these sources). Now Vol() = Level x MASTER_VOLUME x UI_VOLUME and every source has ignoreListenerVolume, so exactly
        // one application of each slider (with both sliders at 1, Level 0.5 = the earlier loudness).
        public static float Level = 0.5f;
        static readonly HashSet<string> active = new HashSet<string>();   // names started and not stopped
        static bool hooked, evPaused, curPaused;
        static float lastVol = -1f;

        public static void SetLevel(float v)
        {
            Level = Mathf.Clamp01(v);
            Refresh();
        }

        static float Vol()
        {
            float m = 1f, u = 1f;
            try { m = Mathf.Clamp01(GameSettings.MASTER_VOLUME); u = Mathf.Clamp01(GameSettings.UI_VOLUME); } catch (Exception) { m = 1f; u = 1f; }
            return Mathf.Clamp01(Level) * m * u;
        }

        // every source's volume = Vol() (a source that is stopped or paused too: it plays at the right level when it resumes)
        public static void Refresh()
        {
            float v = Vol();
            if (Mathf.Abs(v - lastVol) < 1e-4f) return;
            lastVol = v;
            foreach (KeyValuePair<string, AudioSource> kv in src)
                try { if (kv.Value != null) kv.Value.volume = v; } catch (Exception) { }
        }

        public static void StopAll()
        {
            foreach (KeyValuePair<string, AudioSource> kv in src)
                try { if (kv.Value != null) { kv.Value.UnPause(); kv.Value.Stop(); } } catch (Exception) { }
            active.Clear();
            curPaused = evPaused || Time.timeScale <= 0f;   // T1009: consistent after the stop (Play pauses a new sound only while the game is)
        }

        static void SetPaused(bool p)
        {
            if (p == curPaused) return;
            curPaused = p;
            foreach (KeyValuePair<string, AudioSource> kv in src)
                try
                {
                    if (kv.Value == null || !active.Contains(kv.Key)) continue;   // T1009: a stopped sound is never resumed
                    if (p) kv.Value.Pause(); else kv.Value.UnPause();
                }
                catch (Exception) { }
        }

        static void OnScene(GameScenes g) { StopAll(); }
        static void OnVessel(Vessel v) { StopAll(); }
        static void OnPause() { evPaused = true; SetPaused(true); }
        static void OnUnpause() { evPaused = false; SetPaused(Time.timeScale <= 0f); }

        // the poll (5 Hz, real time): the volume sliders and a pause the events missed (Time.timeScale 0)
        public static void Poll()
        {
            Refresh();
            SetPaused(evPaused || Time.timeScale <= 0f);
        }

        static void Hook()
        {
            if (hooked) return;
            hooked = true;
            try { GameEvents.onGameSceneLoadRequested.Add(OnScene); } catch (Exception) { }
            try { GameEvents.onVesselChange.Add(OnVessel); } catch (Exception) { }
            try { GameEvents.onGamePause.Add(OnPause); } catch (Exception) { }
            try { GameEvents.onGameUnpause.Add(OnUnpause); } catch (Exception) { }
        }

        public static AudioClip Clip(string name)
        {
            AudioClip c;
            if (clips.TryGetValue(name, out c) && c != null) return c;
            c = null;
            try { if (GameDatabase.Instance != null) c = GameDatabase.Instance.GetAudioClip(Dir + name); } catch (Exception) { c = null; }
            if (c == null) c = ReadWav(name);
            if (c != null) clips[name] = c;
            return c;
        }

        // 16 bit PCM WAV from GameData/KALS_CW/Sounds/<name>.wav (the fallback when KSP's loader has not made a clip of it)
        static AudioClip ReadWav(string name)
        {
            try
            {
                string path = Path.Combine(KSPUtil.ApplicationRootPath, "GameData/" + Dir + name + ".wav");
                if (!File.Exists(path)) return null;
                byte[] d = File.ReadAllBytes(path);
                if (d.Length < 44 || d[0] != 'R' || d[1] != 'I' || d[2] != 'F' || d[3] != 'F') return null;
                int pos = 12, ch = 1, rate = 44100, bits = 16, off = -1, len = 0;
                while (pos + 8 <= d.Length)
                {
                    string id = "" + (char)d[pos] + (char)d[pos + 1] + (char)d[pos + 2] + (char)d[pos + 3];
                    int sz = BitConverter.ToInt32(d, pos + 4);
                    if (id == "fmt ") { ch = BitConverter.ToInt16(d, pos + 10); rate = BitConverter.ToInt32(d, pos + 12); bits = BitConverter.ToInt16(d, pos + 22); }
                    else if (id == "data") { off = pos + 8; len = Math.Min(sz, d.Length - off); break; }
                    pos += 8 + sz + (sz & 1);
                }
                if (off < 0 || bits != 16 || ch < 1 || ch > 2) return null;
                int n = len / 2;
                float[] f = new float[n];
                for (int i = 0; i < n; i++) f[i] = BitConverter.ToInt16(d, off + 2 * i) / 32768f;
                AudioClip c = AudioClip.Create(name, n / ch, ch, rate, false);
                c.SetData(f, 0);
                return c;
            }
            catch (Exception) { return null; }
        }

        static AudioSource Source(string name)
        {
            if (root == null)
            {
                root = new GameObject("KalsSnd");
                UnityEngine.Object.DontDestroyOnLoad(root);
                src.Clear(); active.Clear();
                root.AddComponent<KalsSndTick>();
                Hook();
            }
            AudioSource s;
            if (!src.TryGetValue(name, out s) || s == null)
            {
                s = root.AddComponent<AudioSource>();
                s.playOnAwake = false;
                s.spatialBlend = 0f;
                s.ignoreListenerVolume = true;                   // The sliders are applied in Vol(), once
                src[name] = s;
            }
            return s;
        }

        public static bool Play(string name, bool loop)
        {
            try
            {
                if (string.IsNullOrEmpty(name)) return false;
                AudioClip c = Clip(name);
                if (c == null) return false;
                AudioSource s = Source(name);
                s.UnPause();                                     // T1009: clear Unity's paused flag before the stop
                s.Stop();
                lastVol = -1f;
                s.clip = c; s.loop = loop; s.volume = Vol();
                s.Play();
                active.Add(name);
                Poll();                                          // a sound started while the game is paused starts paused
                if (curPaused) s.Pause();
                return true;
            }
            catch (Exception) { return false; }
        }

        public static bool Stop(string name)
        {
            try
            {
                AudioSource s;
                if (name == null || !src.TryGetValue(name, out s) || s == null) return false;
                bool was = s.isPlaying || (curPaused && active.Contains(name));
                s.UnPause();                                     // T1009
                s.Stop();
                active.Remove(name);
                return was;
            }
            catch (Exception) { return false; }
        }
    }

    public class KalsSndTick : MonoBehaviour
    {
        float next;
        void Update()
        {
            if (Time.unscaledTime < next) return;
            next = Time.unscaledTime + 0.2f;
            KalsSnd.Poll();
        }
    }

    public partial class KalsAddon
    {
        partial void RegisterSnd()
        {
            AddSuffix("SNDPLAY", new TwoArgsSuffix<BooleanValue, StringValue, BooleanValue>((n, lp) => new BooleanValue(KalsSnd.Play(n == null ? "" : n.ToString(), lp != null && (bool)lp))));
            AddSuffix("SNDSTOP", new OneArgsSuffix<BooleanValue, StringValue>(n => new BooleanValue(KalsSnd.Stop(n == null ? null : n.ToString()))));
            AddSuffix("SNDVOL", new OneArgsSuffix<BooleanValue, ScalarValue>(v => { KalsSnd.SetLevel((float)v.GetDoubleValue()); return BooleanValue.True; }));
        }
    }
}
