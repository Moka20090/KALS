// DPS 06 GPC OUTPUT BAD's control transient (GpcKick.cs holds the envelope). lib_gpc.ks calls
//     ADDONS:KALS:GPCKICK(axis, sign, seconds)   axis "PITCH" / "YAW" / "ROLL", sign +1 / -1, seconds 1..3 (clamped): from now the vessel's final control state carries a bias
//                                                on that axis (a half sine of 0.22 at most, smaller at high dynamic pressure); returns "OK" or "REFUSE: text".
// Registered from RegisterFail (KalsAddon.Fail.cs). The hook stays on the vessel only while a spell runs (it takes itself off when the spell is over).
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        static Vessel gkVessel;

        StringValue GpcKickCall(StringValue axis, ScalarValue sign, ScalarValue secs)
        {
            Vessel v = shared.Vessel;
            if (v == null) return new StringValue("REFUSE: NO VESSEL");
            string r = GpcKick.Start(axis.ToString(), sign.GetDoubleValue(), secs.GetDoubleValue(), Planetarium.GetUniversalTime());
            if (r != "OK") return new StringValue(r);
            if (gkVessel != null) gkVessel.OnFlyByWire -= GkFbw;
            v.OnFlyByWire -= GkFbw;
            v.OnFlyByWire += GkFbw;
            gkVessel = v;
            Debug.Log("[KalsCoproc] GPCKICK: " + GpcKick.AxisName(GpcKick.Axis) + " " + (GpcKick.Sign > 0 ? "+" : "-") + " for " + GpcKick.Dur.ToString("0.0") + " s");
            return new StringValue("OK");
        }

        static void GkFbw(FlightCtrlState st)
        {
            Vessel v = gkVessel;
            double b = GpcKick.Level(Planetarium.GetUniversalTime(), v == null ? 0 : v.dynamicPressurekPa);
            if (!GpcKick.On)
            {
                if (v != null) v.OnFlyByWire -= GkFbw;
                gkVessel = null;
            }
            if (b == 0) return;
            float f = (float)b;
            switch (GpcKick.Axis)
            {
                case 0: st.pitch = Mathf.Clamp(st.pitch + f, -1f, 1f); break;
                case 1: st.yaw = Mathf.Clamp(st.yaw + f, -1f, 1f); break;
                default: st.roll = Mathf.Clamp(st.roll + f, -1f, 1f); break;
            }
        }
    }
}
