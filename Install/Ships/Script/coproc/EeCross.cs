// A plain white cross at the screen centre while the
// EE CAM view is on. Each arm's total length = 10 % of Screen.width (horizontal and vertical the same), 2 px thick, no fill, no text.
// kOS side (arm_body.ks, the EE CAM on / off): ADDONS:KALS:EECROSS(1) / (0) -> KalsAddon.Paint.cs's suffix sets EeCross.On.
// The OnGUI runs on the Repaint event only (the frame's own draw; no layout cost).
using System;
using UnityEngine;

namespace KalsCoproc
{
    public static class EeCross
    {
        public static bool On;
    }

    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public class EeCrossGui : MonoBehaviour
    {
        // T1022: the cross belongs to one flight view. This addon is made again in every flight scene (a revert, a load),
        // so a new one starts with the cross off; a vessel change and the addon going away turn it off too (the kOS side
        // only sends EECROSS(0) on its own camera exits, and a revert kills the script before that).
        void Awake() { EeCross.On = false; }
        void Start()
        {
            try { GameEvents.onVesselChange.Add(OnVesselChange); } catch (Exception) { }
        }
        void OnDestroy()
        {
            EeCross.On = false;
            try { GameEvents.onVesselChange.Remove(OnVesselChange); } catch (Exception) { }
        }
        void OnVesselChange(Vessel v) { EeCross.On = false; }
        void OnGUI()
        {
            try
            {
                if (!EeCross.On) { return; }
                if (Event.current == null || Event.current.type != EventType.Repaint) { return; }
                float len = Screen.width * 0.10f;   // the total length of each arm
                const float th = 2f;                  // the stroke, px
                float cx = Screen.width / 2f;
                float cy = Screen.height / 2f;
                GUI.color = Color.white;
                GUI.DrawTexture(new Rect(cx - len / 2f, cy - th / 2f, len, th), Texture2D.whiteTexture);
                GUI.DrawTexture(new Rect(cx - th / 2f, cy - len / 2f, th, len), Texture2D.whiteTexture);
            }
            catch (Exception) { }
        }
    }
}
