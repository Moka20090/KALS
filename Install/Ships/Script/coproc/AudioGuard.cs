// A STALE POOLED-AUDIO SOURCE MUST NOT LOOP AS AN EXCEPTION.
// Stock AudioMultiPooledFX keeps ONE pooled source (field `source`); the release callback it passes to PooledAudioSource.BorrowAndPlay nulls that field
// when the source is released (Reset invokes onRelease). KSPCommunityFixes' PooledAudioSource_Reset_Postfix then sets onRelease = null after every Reset
// (a leak fix). If the FX ever holds a source that was ALREADY released (Play assigns the result of BorrowAndPlay after the CheckEnd coroutine released
// it inside the call: a source borrowed under an inactive parent never plays, isPlaying is false at the coroutine's first step), the next StopAndRelease
// runs Reset again and onRelease.Invoke() throws a NullReferenceException that never clears the field: one exception per module per physics tick for the
// rest of the flight. RcsJets.FxOff removes OUR cause (a held jet's stale volume); this prefix
// is the backstop for any cause: at the first touch of a stale FX (Play / OnDisable / OnDestroy / OnGamePause) the field is cleared, which is exactly
// what the lost onRelease would have done. A live source always has onRelease set, so nothing healthy is touched. Installed by RcsJets.Hold's first call.
using System;
using System.Reflection;
using UnityEngine;

namespace KalsCoproc
{
    public static class AudioGuard
    {
        static bool tried;
        static FieldInfo fSource, fOnRelease;
        static int healed;
        public static string Error = "";

        public static void Install()
        {
            if (tried) return;
            tried = true;
            try
            {
                Type fx = typeof(Part).Assembly.GetType("AudioMultiPooledFX", false);
                if (fx == null) throw new Exception("no AudioMultiPooledFX");
                Type ps = fx.GetNestedType("PooledAudioSource", BindingFlags.NonPublic | BindingFlags.Public);
                if (ps == null) throw new Exception("no PooledAudioSource");
                BindingFlags bf = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
                fSource = fx.GetField("source", bf);
                fOnRelease = ps.GetField("onRelease", bf);
                if (fSource == null || fOnRelease == null) throw new Exception("fields source / onRelease not found");
                MethodInfo pre = typeof(AudioGuard).GetMethod("Pre", BindingFlags.Static | BindingFlags.NonPublic);
                var h = new HarmonyLib.Harmony("kals.audioguard");
                int n = 0;
                foreach (string m in new[] { "Play", "OnDisable", "OnDestroy", "OnGamePause" })
                {
                    MethodInfo mi = fx.GetMethod(m, bf | BindingFlags.DeclaredOnly);
                    if (mi == null) continue;
                    h.Patch(mi, prefix: new HarmonyLib.HarmonyMethod(pre));
                    n++;
                }
                Debug.Log("[KalsCoproc] T898 AudioGuard: " + n + " AudioMultiPooledFX methods guarded against a stale pooled source");
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; Debug.Log("[KalsCoproc] T898 AudioGuard not installed: " + Error); }
        }

        // the stale test: the FX holds a source whose onRelease is gone = already released to the pool
        static void Pre(object __instance)
        {
            try
            {
                object s = fSource.GetValue(__instance);
                if (s == null || fOnRelease.GetValue(s) != null) return;
                fSource.SetValue(__instance, null);
                healed++;
                if (healed <= 5 || healed % 1000 == 0) Debug.Log("[KalsCoproc] T898 AudioGuard: a stale pooled audio source cleared (" + healed + ")");
            }
            catch { }
        }
    }
}
