// The
// pages' widget writes set from C#, in the kOS code's order. The draw hosts (TdKos, EdKos, AdKos, TjKos) call Ops at the
// end of a successful draw and hand kOS back an EMPTY list, so kOS's tdCsApply / adCsApply / tjCsApply loops (about 50
// opcodes a write) run over nothing. The codes are TDDRAW's: 0 TEXT, 1 IMAGE, 2 STYLE:WIDTH, 3 STYLE:HEIGHT,
// 4 STYLE:MARGIN:H, 5 STYLE:MARGIN:V, 6 STYLE:ALIGN, 7 STYLE:BG.
// vis TRUE (TD and ED, whose kOS loop is lib_taemdisp's tdCsApply): after a TEXT / IMAGE write, tdVis's rule: with Hide
// on (ADDONS:KALS:TDHIDE(TD_BLANK_IMG), set by tdInit when TD_CS_HIDE) a blank label (the blank image, " ", "<b> </b>",
// "", "<b></b>") is HIDDEN and any other SHOWN; with Hide off every written label is SHOWN (tdNoHide). The
// compares are case-blind, as kOS's "=". ShowHook is set by KalsAddon (kOS.dll's Widget.Show / Hide); in a build
// without it (the offline VM) nothing is shown or hidden.
// kOS.Safe only. Throws on a bad widget: the caller's catch turns it into its "error ..." (kOS then draws that draw).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class WApply
    {
        public static Action<Structure, bool> ShowHook;
        public static bool Hide;
        public static string Blank = "";
        public static int N;                    // writes applied (all hosts), for a probe

        static bool Eq(string a, string b) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }

        static bool BlankText(string s)
        {
            return Eq(s, " ") || Eq(s, "<b> </b>") || s.Length == 0 || Eq(s, "<b></b>");
        }

        static void Vis(Structure w, int c, Structure x)
        {
            var h = ShowHook;
            if (h == null) return;
            if (!Hide) { h(w, true); return; }
            string s = x.ToString();
            h(w, c == 1 ? !Eq(s, Blank) : !BlankText(s));
        }

        static Structure Sty(Structure w) { return w.GetSuffix("STYLE").Value; }

        public static void Ops(List<Structure> ops, bool vis)
        {
            for (int i = 0; i + 2 < ops.Count; i += 3)
            {
                Structure w = ops[i];
                int c = (int)((ScalarValue)ops[i + 1]).GetDoubleValue();
                Structure x = ops[i + 2];
                switch (c)
                {
                    case 0: w.SetSuffix("TEXT", x); if (vis) Vis(w, 0, x); break;
                    case 1: w.SetSuffix("IMAGE", x); if (vis) Vis(w, 1, x); break;
                    case 2: Sty(w).SetSuffix("WIDTH", x); break;
                    case 3: Sty(w).SetSuffix("HEIGHT", x); break;
                    case 4: Sty(w).GetSuffix("MARGIN").Value.SetSuffix("H", x); break;
                    case 5: Sty(w).GetSuffix("MARGIN").Value.SetSuffix("V", x); break;
                    case 6: Sty(w).SetSuffix("ALIGN", x); break;
                    default: Sty(w).SetSuffix("BG", x); break;
                }
                N++;
            }
        }

        // the HUD (lib_hud hdCsApply's 4 loops): HUDRENDER's LIST(img: label, path ..., size: label, px ...,
        // margin: label, H, V ..., text: label, text ...); an image = clr or a text "" hides its label, any other shows it
        public static void Hud(ListValue rr, string clr)
        {
            var h = ShowHook;
            var o = (ListValue)rr[0];
            for (int k = 0; k + 1 < o.Count; k += 2)
            {
                o[k].SetSuffix("IMAGE", o[k + 1]);
                if (h != null) h(o[k], !Eq(o[k + 1].ToString(), clr));
                N++;
            }
            o = (ListValue)rr[1];
            for (int k = 0; k + 1 < o.Count; k += 2)
            {
                var st = Sty(o[k]);
                st.SetSuffix("WIDTH", o[k + 1]);
                st.SetSuffix("HEIGHT", o[k + 1]);
                N++;
            }
            o = (ListValue)rr[2];
            for (int k = 0; k + 2 < o.Count; k += 3)
            {
                var m = Sty(o[k]).GetSuffix("MARGIN").Value;
                m.SetSuffix("H", o[k + 1]);
                m.SetSuffix("V", o[k + 2]);
                N++;
            }
            o = (ListValue)rr[3];
            for (int k = 0; k + 1 < o.Count; k += 2)
            {
                o[k].SetSuffix("TEXT", o[k + 1]);
                if (h != null) h(o[k], o[k + 1].ToString().Length != 0);
                N++;
            }
        }
    }
}
