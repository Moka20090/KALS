// ops2q's MNVR EXEC page build in C#: ops2q.ks o2qPgMnvr + o2qP8Row + o2qHead + o2qMsgRow as a pure function of raw values.
// kOS keeps what needs the game / the guidance (o2qLoaded, o2qVgo, o2qEls, o2qAfter, the frames ...) and hands the results over as
// one LEXICON (O2MnvrIn.FromKos: the keys are the field names below); C# writes the SAME segments and cursor stops in the SAME order
// (the draw sorts a row's segments by column, insertion after the equal ones, so the order of the calls is part of the page).
// tests/o2mnvr_offline runs the VERBATIM kOS builder in the offline kOS VM on a set of states and compares this builder's Dump().
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class O2MnvrIn
    {
        public bool ld, ro, post, sh, p4, p8;     // loaded / frozen by its sequence / just ended / a burn to show / PEG 4 / PEG 8 (the guid selection read as loaded)
        public double met, now;                    // MISSIONTIME, TIME:SECONDS
        public double tigMet, tig;                 // o2Val["tig"] (met s), its UT (0 when no burn is shown)
        public double[] dv = new double[3];        // o2Val dvx / dvy / dvz
        public double tot;                         // o2qDvTot
        public double omsSel, guidSel;             // o2Val["oms"], o2Val["guid"]
        public bool omsOn;                         // NOT ro AND (a left or a right engine is available)
        public int[] omsDim = new int[0], gdim = new int[0];
        public string[] gwhy = new string[] { "", "", "" };
        public string burnTxt = "";                // row 3: the loaded burn's name (+ " (EDITED)"), or the last burn's tree after the cut
        public string[] srcNames = new string[0];  // the plan files (o2qSrcNames)
        public double massT;                       // SHIP:MASS (t)
        public string typ = "";                    // the loaded (or last) burn's TYPE
        public bool p8Ok; public double p8Aimt, p8Miss;   // row 4 while GUID = PEG 8: the shot (nres > 0), its aim UT, its miss (m)
        public double tvr;                         // o2Val["tvr"]
        public bool dapOn;                         // o2qDapOn
        public double attErr = double.NaN;         // ATT ERR deg (NaN = dashes)
        public double c1, c2, ht, tht; public bool p4NoSol;
        public string aiNext = ""; public bool p8NoSol; public string p8Why = ""; public double p8NRes, p8MissP;
        public double gt, tg; public bool burnt, gdl;      // the VGO block
        public double[] gb = new double[3];
        public double raT, rpT, raC, rpC;          // HA / HP target and current, km
        public bool rct; public double[] rb = new double[3];   // the RCS trim after the cut
        public bool armed;
        public string[] msgTxt = new string[0], msgCls = new string[0];

        static string S(Lexicon l, string k) { return l[new StringValue(k)].ToString(); }
        static double D(Lexicon l, string k) { return ((ScalarValue)l[new StringValue(k)]).GetDoubleValue(); }
        static bool B(Lexicon l, string k) { var v = l[new StringValue(k)]; var bv = v as BooleanValue; if (bv != null) return bv.Value; return ((ScalarValue)v).GetDoubleValue() != 0; }   // A 0 / 1 from kOS reads too
        static double[] DL(Lexicon l, string k)
        {
            var v = (ListValue)l[new StringValue(k)]; var o = new double[v.Count];
            for (int i = 0; i < o.Length; i++) o[i] = ((ScalarValue)v[i]).GetDoubleValue();
            return o;
        }
        static int[] IL(Lexicon l, string k) { var d = DL(l, k); var o = new int[d.Length]; for (int i = 0; i < o.Length; i++) o[i] = (int)Math.Round(d[i]); return o; }
        static string[] SL(Lexicon l, string k)
        {
            var v = (ListValue)l[new StringValue(k)]; var o = new string[v.Count];
            for (int i = 0; i < o.Length; i++) o[i] = v[i].ToString();
            return o;
        }

        // the hand-off from kOS: every key present (a missing key throws: the caller falls back to the kOS builder)
        public static O2MnvrIn FromKos(Lexicon l)
        {
            var o = new O2MnvrIn();
            o.ld = B(l, "ld"); o.ro = B(l, "ro"); o.post = B(l, "post"); o.sh = B(l, "sh"); o.p4 = B(l, "p4"); o.p8 = B(l, "p8");
            o.met = D(l, "met"); o.now = D(l, "now"); o.tigMet = D(l, "tigMet"); o.tig = D(l, "tig");
            o.dv = DL(l, "dv"); o.tot = D(l, "tot");
            o.omsSel = D(l, "omsSel"); o.guidSel = D(l, "guidSel"); o.omsOn = B(l, "omsOn");
            o.omsDim = IL(l, "omsDim"); o.gdim = IL(l, "gdim"); o.gwhy = SL(l, "gwhy");
            o.burnTxt = S(l, "burnTxt"); o.srcNames = SL(l, "srcNames"); o.massT = D(l, "massT"); o.typ = S(l, "typ");
            o.p8Ok = B(l, "p8Ok"); o.p8Aimt = D(l, "p8Aimt"); o.p8Miss = D(l, "p8Miss");
            o.tvr = D(l, "tvr"); o.dapOn = B(l, "dapOn"); o.attErr = D(l, "attErr"); if (o.attErr < -1e98) o.attErr = double.NaN;   // -1E99 = dashes
            o.c1 = D(l, "c1"); o.c2 = D(l, "c2"); o.ht = D(l, "ht"); o.tht = D(l, "tht"); o.p4NoSol = B(l, "p4NoSol");
            o.aiNext = S(l, "aiNext"); o.p8NoSol = B(l, "p8NoSol"); o.p8Why = S(l, "p8Why"); o.p8NRes = D(l, "p8NRes"); o.p8MissP = D(l, "p8MissP");
            o.gt = D(l, "gt"); o.tg = D(l, "tg"); o.burnt = B(l, "burnt"); o.gdl = B(l, "gdl"); o.gb = DL(l, "gb");
            o.raT = D(l, "raT"); o.rpT = D(l, "rpT"); o.raC = D(l, "raC"); o.rpC = D(l, "rpC");
            o.rct = B(l, "rct"); o.rb = DL(l, "rb"); o.armed = B(l, "armed");
            o.msgTxt = SL(l, "msgTxt"); o.msgCls = SL(l, "msgCls");
            return o;
        }
    }

    public static class O2Mnvr
    {
        static KeyValuePair<int, string> It(int c, string w) { return new KeyValuePair<int, string>(c, w); }
        static bool In(int[] a, int k) { foreach (var x in a) if (x == k) return true; return false; }

        // o2qPgMnvr; dvBar = o2DvBar(tot, gt) (null = LIST(): the slider is not drawn)
        public static O2Page Build(O2MnvrIn i, out double[] dvBar)
        {
            var pg = new O2Page();
            bool ld = i.ld, ro = i.ro, post = i.post, sh = i.sh, p4 = i.p4, p8 = i.p8;
            double tot = i.tot;
            // o2qHead(pg, "2021/", "MNVR EXEC", 0)
            pg.Seg(0, 1, "2021/");
            pg.Seg(0, 18, "MNVR EXEC");
            pg.Read(0, 64, O2Fmt.Met(i.met));
            // row 1: OMS | TIG
            pg.Seg(1, 1, "OMS");
            pg.Choice("oms", (int)Math.Round(i.omsSel), 1, new[] { It(8, "BOTH"), It(15, "L"), It(19, "R"), It(23, "RCS") }, i.omsOn, i.omsDim);
            pg.Seg(1, 42, "TIG");
            if (ld && !ro) pg.Num("tig", "T", 1, 49, O2Fmt.Met(i.tigMet));
            else if (sh) pg.Read(1, 49, O2Fmt.Met(i.tigMet));
            else pg.Read(1, 49, "---/--:--:--", "D");
            // row 2: GUID | the TIG countdown
            pg.Seg(2, 1, "GUID");
            pg.Choice("guid", (int)Math.Round(i.guidSel), 2, new[] { It(8, "PEG 4"), It(15, "PEG 7"), It(22, "PEG 8") }, !ro, i.gdim, i.gwhy);
            if (sh) pg.Read(2, 49, O2Fmt.Cd(i.tig - i.now));
            // row 3: BURN | WT
            pg.Seg(3, 1, "BURN");
            if (ld)
            {
                if (i.srcNames.Length > 1 && !ro) pg.DropDown("src", 3, 8, i.burnTxt, i.srcNames, true);
                else pg.Read(3, 8, i.burnTxt);
            }
            else if (post) pg.Read(3, 8, i.burnTxt);
            else if (i.srcNames.Length > 0 && !ro) pg.DropDown("src", 3, 8, "- NONE (SELECT)", i.srcNames, true);
            else pg.Read(3, 8, "- NONE (BRN PLN / DEORB)", "D");
            pg.Seg(3, 42, "WT"); pg.Read(3, 49, O2Fmt.F(i.massT * 1000, 5, 0)); pg.Seg(3, 55, "kg");
            // row 4: TYPE | AIM T+ / MISS (GUID = PEG 8 only)
            pg.Seg(4, 1, "TYPE");
            if (ld || post) pg.Read(4, 8, i.typ);
            else pg.Read(4, 8, "-", "D");
            if ((int)Math.Round(i.guidSel) == 2)
            {
                pg.Seg(4, 42, "AIM T+", i.p8Ok ? "L" : "D");
                if (i.p8Ok)
                {
                    double dt = Math.Max(0, i.p8Aimt - i.now);
                    pg.Read(4, 49, dt < 6000 ? O2Fmt.Ms(dt) : (O2Fmt.Str(Math.Floor(dt / 3600)) + "h" + O2Fmt.P2(Math.Floor((dt % 3600) / 60))));
                    pg.Seg(4, 56, "MISS"); pg.Read(4, 61, O2Fmt.F(i.p8Miss / 1000, 6, 2) + " km");
                }
                else { pg.Read(4, 49, "--:--", "D"); pg.Seg(4, 56, "MISS", "D"); pg.Read(4, 61, "  -.-- km", "D"); }
            }
            // rows 7-10: the DV block
            pg.Seg(7, 1, "PEG 7  LVLH  m/s");
            pg.Seg(7, 42, "BURN ATT");
            string[] nm = { "DVX", "DVY", "DVZ" }, id = { "dvx", "dvy", "dvz" };
            for (int k = 0; k < 3; k++)
            {
                pg.Seg(8 + k, 3, nm[k]);
                if (ld && !ro && !p4 && !p8) pg.Num(id[k], "N", 8 + k, 8, O2Fmt.Sg(i.dv[k], 6, 1));
                else if (sh) pg.Read(8 + k, 8, O2Fmt.Sg(i.dv[k], 6, 1));
                else pg.Read(8 + k, 8, "  ----", "D");
            }
            if (sh && tot > 0.01)
            {
                double pt = Math.Asin(Math.Max(-1, Math.Min(1, -i.dv[2] / tot))) * 180 / Math.PI;
                double yw = Math.Atan2(i.dv[1], i.dv[0]) * 180 / Math.PI;
                pg.Seg(8, 42, "R"); pg.Read(8, 44, O2Fmt.F(i.tvr, 5, 1));
                pg.Seg(8, 51, "P"); pg.Read(8, 53, O2Fmt.F(pt, 5, 1));
                pg.Seg(8, 60, "Y"); pg.Read(8, 62, O2Fmt.F(yw, 5, 1));
            }
            pg.Act("mnvr", 9, 42, "MNVR", ld && !ro && i.dapOn && tot > 0.01);
            pg.Seg(9, 51, "ATT ERR");
            if (!double.IsNaN(i.attErr)) pg.Read(9, 60, O2Fmt.F(i.attErr, 5, 1));
            else pg.Read(9, 60, "  -.-", "D");
            pg.Seg(10, 42, "TV ROLL");
            if (ld && !ro) pg.Num("tvr", "N", 10, 50, O2Fmt.F(i.tvr, 5, 1));
            else if (sh) pg.Read(10, 50, O2Fmt.F(i.tvr, 5, 1));
            else pg.Read(10, 50, "  ---", "D");
            pg.Seg(10, 56, "deg");
            // row 11: PEG 4's targets / PEG 8's aim
            if (p4)
            {
                pg.Seg(11, 1, "PEG 4"); pg.Seg(11, 8, "C1"); pg.Seg(11, 19, "C2"); pg.Seg(11, 31, "HT");
                pg.Seg(11, 42, "THETA T");
                string[] tx = { O2Fmt.Sg(i.c1, 7, 1), O2Fmt.Sg(i.c2, 7, 5), O2Fmt.F(i.ht, 7, 3), O2Fmt.F(i.tht, 7, 3) };
                string[] fi = { "c1", "c2", "ht", "tht" };
                int[] fc = { 11, 22, 34, 50 };
                for (int k = 0; k < 4; k++)
                {
                    if (ro) pg.Read(11, fc[k], tx[k]); else pg.Num(fi[k], "N", 11, fc[k], tx[k]);
                }
                if (!ro && i.p4NoSol) pg.Read(11, 58, "NO SOLUTION", "R");
            }
            else if (p8)
            {
                pg.Seg(11, 1, "PEG 8"); pg.Seg(11, 8, "AIM");
                pg.Read(11, 12, i.aiNext != "" ? ("BURN " + i.aiNext + " IGNITION") : "HALF AN ORBIT ON");
                if (i.p8NoSol) { string w = i.p8Why.ToUpperInvariant(); pg.Read(11, 42, w.Substring(0, Math.Min(30, w.Length)), "R"); }
                else if (i.p8NRes > 0) { pg.Seg(11, 42, "PEG 7 WOULD MISS"); pg.Read(11, 59, O2Fmt.F(i.p8MissP / 1000, 6, 2) + " km"); }
            }
            else { pg.Seg(11, 1, "PEG 4  C1 -----  C2 -----  HT ---.-", "D"); pg.Seg(11, 42, "THETA T  ----", "D"); }
            // rows 12-15: the VGO block
            if (sh)
            {
                pg.Seg(12, 1, "VGO"); pg.Seg(12, 8, "TOT"); pg.Read(12, 12, O2Fmt.F(i.gt, 5, 1)); pg.Seg(12, 18, "m/s");
                pg.Seg(12, 42, i.burnt ? "TGO" : "TBRN"); pg.Read(12, 49, (i.gdl && i.burnt) ? "-----" : O2Fmt.Ms(i.tg));
                string[] vn = { "VGX", "VGY", "VGZ" };
                for (int k = 0; k < 3; k++) { pg.Seg(13 + k, 3, vn[k]); pg.Read(13 + k, 8, i.gdl ? "------" : O2Fmt.Sv(i.gb[k], 5, 1)); }
                pg.Seg(13, 42, "HA"); pg.Seg(13, 49, "TGT"); pg.Read(13, 53, O2Fmt.F(i.raT, 5, 1));
                pg.Seg(13, 59, "CUR"); pg.Read(13, 63, O2Fmt.F(i.raC, 5, 1)); pg.Seg(13, 69, "km");
                pg.Seg(14, 42, "HP"); pg.Seg(14, 49, "TGT"); pg.Read(14, 53, O2Fmt.F(i.rpT, 5, 1));
                pg.Seg(14, 59, "CUR"); pg.Read(14, 63, O2Fmt.F(i.rpC, 5, 1)); pg.Seg(14, 69, "km");
                dvBar = tot < 0.05 ? null : new[] { tot, Math.Max(0, Math.Min(tot, tot - i.gt)) };
            }
            else dvBar = null;
            // row 16: the RCS trim after the cut
            if (i.rct)
            {
                pg.Seg(16, 1, "RCS    TRIM");
                pg.Seg(16, 18, "X"); pg.Read(16, 20, O2Fmt.Sg(i.rb[0], 5, 2));
                pg.Seg(16, 26, "Y"); pg.Read(16, 28, O2Fmt.Sg(i.rb[1], 5, 2));
                pg.Seg(16, 34, "Z"); pg.Read(16, 36, O2Fmt.Sg(i.rb[2], 5, 2));
            }
            // the action row
            int ar = i.rct ? 17 : 16;
            pg.Act("unld", ar, 0, "UNLD", ld && !ro);
            pg.Act("arm", ar, 8, "ARM", ld && !ro && tot > 0.01);
            if (i.armed && ld) pg.SetLastCls("S");
            pg.Act("exec", ar, 15, "EXEC", ld && !ro && i.armed);
            pg.Act("brn", ar, 23, "BRN PLN", true);
            pg.Act("tree", ar, 34, "FPLN TREE", true);
            // o2qMsgRow(pg, ar + 1)
            pg.Seg(ar + 1, 1, "MSG");
            for (int k = 0; k < i.msgTxt.Length; k++) pg.Read(ar + 1 + k, 8, i.msgTxt[k], i.msgCls[k]);
            return pg;
        }
    }
}
