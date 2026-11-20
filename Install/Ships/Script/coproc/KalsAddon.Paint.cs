// The painter's kOS side (Paint.cs), ADDONS:KALS:
//   PAINTREG(name, LIST(placeholder label, its flow index, the page box), LIST(LIST(label, flow index), ...)) -> "" / error
//   PAINTMODE(name, mode) -> "" / error: 0 OFF (kOS draws), 2 PAINT
//   PAINTSTATE(name) -> the mode, -1 failed (kOS draws again, the boxes shown), -2 no such group
//   PAINTERR -> the last failure ("" none)
// None throws into kOS. Needs in KalsAddon.cs: `partial void RegisterPaint();` and the call `RegisterPaint();`.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using KLabel = kOS.Suffixed.Widget.Label;
using KBox = kOS.Suffixed.Widget.Box;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterPaint()
        {
            AddSuffix("PAINTREG", new ThreeArgsSuffix<StringValue, StringValue, ListValue, ListValue>((n, ph, items) => PaintReg(n, ph, items)));
            AddSuffix("PAINTMODE", new TwoArgsSuffix<StringValue, StringValue, ScalarValue>((n, m) => Str(Painter.SetMode(n.ToString(), m.GetIntValue()))));
            AddSuffix("PAINTSTATE", new OneArgsSuffix<ScalarValue, StringValue>(n => ScalarValue.Create(Painter.State(n.ToString()))));
            AddSuffix("PAINTERR", new Suffix<StringValue>(() => new StringValue(Painter.Error)));
            // The EE CAM cross on (1) / off (0): EeCross.cs draws it while On
            AddSuffix("EECROSS", new OneArgsSuffix<ScalarValue, ScalarValue>(v => { EeCross.On = v.GetIntValue() != 0; return ScalarValue.Create(0); }));
        }

        static StringValue Str(string s) { return new StringValue(s ?? ""); }

        static StringValue PaintReg(StringValue name, ListValue ph, ListValue items)
        {
            try
            {
                if (ph.Count < 3) return Str("the placeholder list needs (label, flow index, page box)");
                var pl = ph[0] as KLabel;
                var page = ph[2] as KBox;
                if (pl == null) return Str("the placeholder is not a label");
                if (page == null) return Str("the page box is not a box");
                int pf = ((ScalarValue)ph[1]).GetIntValue();
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
                return Str(Painter.Register(name.ToString(), pl, pf, ls, fs, page));
            }
            catch (Exception ex) { return Str("PAINTREG: " + ex.GetType().Name + ": " + ex.Message); }
        }
    }
}
