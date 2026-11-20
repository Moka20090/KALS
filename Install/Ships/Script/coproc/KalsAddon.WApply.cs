// The pages' widget writes from C# (WApply.cs), ADDONS:KALS:
//   TDHIDE(blank image path) -> "": the TD / ED C# draws apply tdVis's rule (a blank label hidden, any other shown);
//      "" = off (every written label shown). lib_taemdisp tdInit calls it (TD_CS_HIDE).
//   HDAPPLY(HUDRENDER's list, HD_CLEAR) -> "" / "error ...": lib_hud hdCsApply's 4 loops in C# (kOS then runs its own
//      loops on an error: HDAPPLY may have written part of the list, kOS writes all of it again).
//   WAPPLYN -> the writes applied so far (all hosts).
// Also sets WApply.ShowHook (kOS.dll's Widget.Show / Hide). None throws into kOS.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using KWidget = kOS.Suffixed.Widget.Widget;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterWApply()
        {
            WApply.ShowHook = (w, on) =>
            {
                var k = w as KWidget;
                if (k == null) throw new Exception("a " + (w == null ? "null" : w.GetType().Name) + ", not a widget");
                if (on) k.Show(); else k.Hide();
            };
            AddSuffix("TDHIDE", new OneArgsSuffix<StringValue, StringValue>(b =>
            {
                WApply.Blank = b == null ? "" : b.ToString();
                WApply.Hide = WApply.Blank.Length != 0;
                return new StringValue("");
            }));
            AddSuffix("HDAPPLY", new TwoArgsSuffix<StringValue, ListValue, StringValue>((rr, clr) =>
            {
                try
                {
                    if (rr == null || rr.Count < 4) return new StringValue("error HDAPPLY: not the 4 lists of HUDRENDER");
                    WApply.Hud(rr, clr == null ? "" : clr.ToString());
                    return new StringValue("");
                }
                catch (Exception ex) { return new StringValue("error HDAPPLY: " + ex.GetType().Name + ": " + ex.Message); }
            }));
#if !KALS_RELEASE
            AddSuffix("WAPPLYN", new Suffix<ScalarValue>(() => ScalarValue.Create(WApply.N)));   // the test harness's read
#endif
        }
    }
}
