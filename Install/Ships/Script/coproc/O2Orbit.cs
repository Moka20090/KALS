// ops2q's ORBIT / PTG page build in C# (page 2): ops2q.ks o2qPgOrbit as a pure function of raw values, the pattern of O2Mnvr.cs.
// O2OrbitIn.FromKos(Lexicon) reads the values lib_o2orbin.ks o2qOrbitIn() gathers (a missing key throws: the caller keeps the kOS builder).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class O2OrbitIn
    {
        public double met;                         // MISSIONTIME (o2qHead)
        public double raKm, rpKm, inc, per;        // o2qKm(el["ra"]), o2qKm(el["rp"]), el["inc"], el["period"]
        public double altKm, spd;                  // SHIP:ALTITUDE / 1000, SHIP:VELOCITY:ORBIT:MAG
        public double etaA, etaP;                  // ETA:APOAPSIS, ETA:PERIAPSIS
        public bool dp;                            // o2qDapOn
        public int hold, tax, ttg, dmode;          // ROUND(o2Val[...]) of the choices
        public string[] taxWords = new string[0], ttgWords = new string[0];
        public double tom, tr, tp, ty, ddb, drate; // o2Val
        public double[] at = new double[3];        // o2qAtt()
        public double[] tg = new double[0];        // o2qDapTgt(): 3 or none
        public double[] ec = new double[0];        // the error (roll, pitch, yaw order of the rows), 3 when tg is
        public double rate;                        // SHIP:ANGULARVEL:MAG * 180 / PI
        public string dapAct = "";                 // O2Q_DAP_ACT[o2qDap["act"]] (dp only)
        public double dapEa; public bool jets;     // o2qDap["ea"], o2qDap["u"]:MAG > 0 (dp only)
        public bool seqOn;                         // o2qSeq <> ""
        public string[] msgTxt = new string[0], msgCls = new string[0];

        static string S(Lexicon l, string k) { return l[new StringValue(k)].ToString(); }
        static double D(Lexicon l, string k) { return ((ScalarValue)l[new StringValue(k)]).GetDoubleValue(); }
        static bool B(Lexicon l, string k) { var v = l[new StringValue(k)]; var bv = v as BooleanValue; if (bv != null) return bv.Value; return ((ScalarValue)v).GetDoubleValue() != 0; }
        static double[] DL(Lexicon l, string k)
        {
            var v = (ListValue)l[new StringValue(k)]; var o = new double[v.Count];
            for (int i = 0; i < o.Length; i++) o[i] = ((ScalarValue)v[i]).GetDoubleValue();
            return o;
        }
        static string[] SL(Lexicon l, string k)
        {
            var v = (ListValue)l[new StringValue(k)]; var o = new string[v.Count];
            for (int i = 0; i < o.Length; i++) o[i] = v[i].ToString();
            return o;
        }

        public static O2OrbitIn FromKos(Lexicon l)
        {
            var o = new O2OrbitIn();
            o.met = D(l, "met"); o.raKm = D(l, "raKm"); o.rpKm = D(l, "rpKm"); o.inc = D(l, "inc"); o.per = D(l, "per");
            o.altKm = D(l, "altKm"); o.spd = D(l, "spd"); o.etaA = D(l, "etaA"); o.etaP = D(l, "etaP");
            o.dp = B(l, "dp");
            o.hold = (int)Math.Round(D(l, "hold")); o.tax = (int)Math.Round(D(l, "tax")); o.ttg = (int)Math.Round(D(l, "ttg")); o.dmode = (int)Math.Round(D(l, "dmode"));
            o.taxWords = SL(l, "taxWords"); o.ttgWords = SL(l, "ttgWords");
            o.tom = D(l, "tom"); o.tr = D(l, "tr"); o.tp = D(l, "tp"); o.ty = D(l, "ty"); o.ddb = D(l, "ddb"); o.drate = D(l, "drate");
            o.at = DL(l, "at"); o.tg = DL(l, "tg"); o.ec = DL(l, "ec");
            o.rate = D(l, "rate"); o.dapAct = S(l, "dapAct"); o.dapEa = D(l, "dapEa"); o.jets = B(l, "jets"); o.seqOn = B(l, "seqOn");
            o.msgTxt = SL(l, "msgTxt"); o.msgCls = SL(l, "msgCls");
            if (o.at.Length != 3 || (o.tg.Length != 0 && (o.tg.Length != 3 || o.ec.Length != 3))) throw new Exception("bad vector lengths");
            return o;
        }
    }

    public static class O2Orbit
    {
        static KeyValuePair<int, string> It(int c, string w) { return new KeyValuePair<int, string>(c, w); }

        public static O2Page Build(O2OrbitIn i)
        {
            var pg = new O2Page();
            // o2qHead(pg, "2011/", "ORBIT / PTG", 0)
            pg.Seg(0, 1, "2011/"); pg.Seg(0, 18, "ORBIT / PTG"); pg.Read(0, 64, O2Fmt.Met(i.met));
            pg.Seg(2, 1, "ORBIT  HA"); pg.Read(2, 12, O2Fmt.F(i.raKm, 5, 1)); pg.Seg(2, 18, "km  HP");
            pg.Read(2, 25, O2Fmt.F(i.rpKm, 5, 1)); pg.Seg(2, 31, "km  INC"); pg.Read(2, 39, O2Fmt.F(i.inc, 5, 1));
            pg.Seg(2, 45, "deg");
            pg.Seg(3, 8, "H"); pg.Read(3, 12, O2Fmt.F(i.altKm, 5, 1)); pg.Seg(3, 18, "km  V");
            pg.Read(3, 25, O2Fmt.F(i.spd, 5, 0)); pg.Seg(3, 31, "m/s");
            pg.Seg(4, 8, "PER"); pg.Read(4, 12, O2Fmt.Ms(i.per));
            pg.Seg(4, 22, "TTA"); pg.Read(4, 26, O2Fmt.Ms(i.etaA).PadLeft(5));
            pg.Seg(4, 36, "TTP"); pg.Read(4, 40, O2Fmt.Ms(i.etaP).PadLeft(5));
            bool dp = i.dp;
            pg.Seg(6, 1, "HOLD");
            pg.Choice("hold", i.hold, 6, new[] { It(8, "INRTL"), It(16, "LVLH"), It(24, "TRACK"), It(32, "FREE") }, dp);
            pg.Seg(7, 1, "TRACK  BODY");
            pg.DropDown("tax", 7, 13, i.taxWords[i.tax], i.taxWords, dp);
            pg.Seg(7, 18, "TO");
            pg.DropDown("ttg", 7, 22, i.ttgWords[i.ttg], i.ttgWords, dp);
            pg.Seg(7, 30, "OMICRON"); pg.Num("tom", "N", 7, 38, O2Fmt.F(i.tom, 5, 1), dp);
            pg.Seg(9, 14, "CUR       MNVR      TGT       ERR");
            string[] nm = { "ROLL", "PITCH", "YAW" }, tid = { "tr", "tp", "ty" };
            double[] tv = { i.tr, i.tp, i.ty };
            for (int k = 0; k < 3; k++)
            {
                pg.Seg(10 + k, 1, nm[k]);
                pg.Read(10 + k, 12, O2Fmt.F(i.at[k], 5, 1));
                pg.Num(tid[k], "N", 10 + k, 22, O2Fmt.F(tv[k], 5, 1), dp);
                if (i.tg.Length == 3)
                {
                    pg.Read(10 + k, 32, O2Fmt.F(i.tg[k], 5, 1));
                    pg.Read(10 + k, 42, O2Fmt.F(i.ec[k], 6, 2));
                }
                else
                {
                    pg.Read(10 + k, 32, "  ---", "D");
                    pg.Read(10 + k, 42, "   ---", "D");
                }
            }
            pg.Seg(13, 1, "RATE"); pg.Read(13, 12, O2Fmt.F(i.rate, 5, 2)); pg.Seg(13, 18, "deg/s");
            pg.Seg(13, 28, "DAP");
            if (dp)
            {
                pg.Read(13, 32, i.dapAct);
                pg.Seg(13, 44, "ERR"); pg.Read(13, 48, O2Fmt.F(i.dapEa, 5, 2)); pg.Seg(13, 54, "deg");
                if (i.jets) pg.Read(13, 60, "JETS");
            }
            else if (i.seqOn) pg.Read(13, 32, "BURN: KOS STEERING", "Y");
            else pg.Read(13, 32, "N/A: NO KALSCOPROC FLY-BY-WIRE", "Y");
            pg.Seg(14, 1, "DAP");
            pg.Choice("dmode", i.dmode, 14, new[] { It(8, "AUTO"), It(16, "CSS") }, dp);
            pg.Seg(14, 25, "DB"); pg.Num("ddb", "N", 14, 28, O2Fmt.F(i.ddb, 5, 2), dp); pg.Seg(14, 34, "deg");
            pg.Seg(14, 39, "RATE"); pg.Num("drate", "N", 14, 44, O2Fmt.F(i.drate, 4, 2), dp); pg.Seg(14, 49, "deg/s");
            pg.Act("omnvr", 17, 8, "MNVR", dp);
            pg.Act("ostop", 17, 16, "STOP", dp);
            pg.Act("brn", 17, 24, "BRN PLN", true);
            // o2qMsgRow(pg, 18)
            pg.Seg(18, 1, "MSG");
            for (int k = 0; k < i.msgTxt.Length; k++) pg.Read(18 + k, 8, i.msgTxt[k], i.msgCls[k]);
            return pg;
        }
    }
}
