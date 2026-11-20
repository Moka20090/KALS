// The HUD window drawn by C#'s kOS side (HudWin.cs), ADDONS:KALS:
//   HWREG(LIST(window GUI, X, Y, blank image path, shown now), LIST(LIST(label, flow index), ...)) -> "" / "error ..."
//      every slot of lib_hud's hdOrd (a second call, after lib_hudg's slots, keeps the earlier labels' state)
//   HWMODE(mode) -> "" / error: 0 OFF (kOS draws), 2 WIN (C# draws)
//   HWDRAW(HUDRENDER's / HUDGTICK's 4 lists) -> "" / "error ...": the table (and, but in WIN, HDAPPLY's kOS writes)
//   HWSHOW(on) -> "": the HUD is wanted (the HUD button, MAPVIEW); C# shows / hides the kOS window itself
//   HWSTATE -> -1 failed (kOS draws), -2 not registered, else the mode;  HWERR -> the last failure
//   HWCLOSE -> "": the HUD is gone (hdClose)
// None throws into kOS. Needs in KalsAddon.cs: `partial void RegisterHudWin();` and the call `RegisterHudWin();`.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using KLabel = kOS.Suffixed.Widget.Label;
using KWidget = kOS.Suffixed.Widget.Widget;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterHudWin()
        {
            AddSuffix("HWREG", new TwoArgsSuffix<StringValue, ListValue, ListValue>((cfg, items) => HwReg(cfg, items)));
            AddSuffix("HWMODE", new OneArgsSuffix<StringValue, ScalarValue>(m => Str(HudWin.SetMode(m.GetIntValue()))));
            AddSuffix("HWDRAW", new OneArgsSuffix<StringValue, ListValue>(rr =>
            {
                if (rr == null || rr.Count < 4) return Str("error HWDRAW: not the 4 lists of HUDRENDER");
                return Str(HudWin.Draw(rr));
            }));
            AddSuffix("HWSHOW", new OneArgsSuffix<StringValue, BooleanValue>(b => { HudWin.SetWant(b.Value); return Str(""); }));
            AddSuffix("HWSTATE", new Suffix<ScalarValue>(() => ScalarValue.Create(HudWin.State())));
            AddSuffix("HWERR", new Suffix<StringValue>(() => Str(HudWin.Error)));
            AddSuffix("HWCLOSE", new Suffix<StringValue>(() => { HudWin.Drop(); return Str(""); }));
        }

        static StringValue HwReg(ListValue cfg, ListValue items)
        {
            try
            {
                if (cfg.Count < 5) return Str("the config needs (window, X, Y, blank image, shown)");
                var win = cfg[0] as KWidget;
                if (win == null) return Str("the window is not a widget");
                double x = ((ScalarValue)cfg[1]).GetDoubleValue(), y = ((ScalarValue)cfg[2]).GetDoubleValue();
                bool shown = ((BooleanValue)cfg[4]).Value;
                var ls = new List<KLabel>(items.Count);
                var fs = new List<int>(items.Count);
                for (int i = 0; i < items.Count; i++)
                {
                    var it = items[i] as ListValue;
                    if (it == null || it.Count < 2) return Str("item " + i + " is not LIST(label, flow index)");
                    var l = it[0] as KLabel;
                    if (l == null) return Str("item " + i + " is not a label");
                    ls.Add(l);
                    fs.Add(((ScalarValue)it[1]).GetIntValue());
                }
                return Str(HudWin.Register(win, x, y, cfg[3].ToString(), shown, ls, fs));
            }
            catch (Exception ex) { return Str("HWREG: " + ex.GetType().Name + ": " + ex.Message); }
        }
    }
}
