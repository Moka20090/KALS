// ops2q's per-tick polls in ONE call each (the kOS loop paid ~100 opcodes + several suffix chains every physics tick):
//   ADDONS:KALS:O2WAKESET(passT, passRate, dt): once per ops2q pass (where it sets o2qPassT / o2qPassRate): the due test's inputs.
//   ADDONS:KALS:O2WAKE(ag4, ag6, ag7) -> TRUE when the wait is over for the cheap reasons, every tick:
//        UT - passT >= dt * MAX(1, MIN(passRate, the game's warp rate))      (ops2q.ks o2qDue)
//     or the vessel's action groups 4 / 6 / 7 differ from the values the caller holds (a pilot press: o2qAg4 / o2qAg6 / o2qAg7).
//     The keyboard (KEYS, which drains), the window's presses, the arm and the RHC stay in ops2q.ks o2qInWait (they follow it, as before).
//   ADDONS:KALS:O2TICK(hold, dapFeed) -> BOOLEAN: the OMS interlock heartbeat OMSHOLD(hold) AND, when dapFeed, the DAP watchdog
//     feed O2DAPALIVE (returns the DAP's on state; FALSE when not fed). One call and one trigger instead of two (ops2q.ks).
// ops2q.ks uses them only when ADDONS:KALS:HASSUFFIX says so and O2Q_WAKE_CS is TRUE (the kOS polls stay as the fallback).
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        void O2wRegister()
        {
            AddSuffix("O2WAKESET", new ThreeArgsSuffix<BooleanValue, ScalarValue, ScalarValue, ScalarValue>((passT, passRate, dt) =>
            {
                o2wT = passT.GetDoubleValue(); o2wRate = passRate.GetDoubleValue(); o2wDt = dt.GetDoubleValue();
                return new BooleanValue(true);
            }));
            AddSuffix("O2WAKE", new ThreeArgsSuffix<BooleanValue, BooleanValue, BooleanValue, BooleanValue>(
                (a4, a6, a7) => new BooleanValue(O2wWake(shared.Vessel, a4.Value, a6.Value, a7.Value))));
            AddSuffix("O2TICK", new TwoArgsSuffix<BooleanValue, BooleanValue, BooleanValue>((hold, feed) =>
            {
                OmsHold.Set(hold.Value);
                if (feed.Value) { o2dIdle = 0; return new BooleanValue(o2dOn); }
                return new BooleanValue(false);
            }));
        }

        // true = wake. A failed read of the game (no vessel, an exception) wakes the loop: the loop then runs every tick, as the WAIT did before
        static double o2wT = -1e9, o2wRate = 1, o2wDt = 0.1;

        static bool O2wWake(Vessel v, bool a4, bool a6, bool a7)
        {
            try
            {
                double w = Math.Max(1.0, Math.Min(o2wRate, (double)TimeWarp.CurrentRate));
                if (Planetarium.GetUniversalTime() - o2wT >= o2wDt * w) return true;
                if (v == null) return true;
                var g = v.ActionGroups;
                if (g[KSPActionGroup.Custom04] != a4) return true;
                if (g[KSPActionGroup.Custom06] != a6 || g[KSPActionGroup.Custom07] != a7) return true;
                return false;
            }
            catch (Exception) { return true; }
        }
    }
}
