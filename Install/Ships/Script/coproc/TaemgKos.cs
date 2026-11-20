// the bridge between kOS and the C# TAEM guidance (Taemg.cs), for KalsAddon's TGSETUP / TGCYCLE.
// The cycle is SYNCHRONOUS (no thread: one guidance pass per call, on the main thread, as kOS's own taemg_cycle):
// kOS's tg / st lexicons are copied into plain Lex values, the C# cycle runs on the copy, and only then are the keys it
// changed written back into kOS's tg (the same lexicon object, so lib_land and the displays read it as before). A failure
// anywhere (a key missing, a NaN, a bug) throws before any write-back: tg is untouched and the caller flies kOS's cycle.
// Numbers keep kOS's type: a key kOS held as an integer stays one while it is whole (iphase, the counters, bind_*).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class TaemgKos
    {
        // ---------------------------------------------------------------- kOS -> C#
        static object FromKos(Structure s, bool nest)
        {
            var sv = s as ScalarValue;
            if (sv != null) { if (sv.IsInt) return sv.GetIntValue(); return sv.GetDoubleValue(); }
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            var str = s as StringValue;
            if (str != null) return str.ToString();
            var lx = s as Lexicon;
            if (lx != null && nest) return LexFrom(lx, false);
            return s;                                   // opaque (a list, a vector, ...): carried, never read
        }

        public static Lex LexFrom(Lexicon l, bool nest)
        {
            var d = new Lex();
            foreach (KeyValuePair<Structure, Structure> kv in l) d[kv.Key.ToString()] = FromKos(kv.Value, nest);
            return d;
        }

        // ---------------------------------------------------------------- C# -> kOS
        static Structure ToKos(object v, Structure old)
        {
            if (v is int) return new ScalarIntValue((int)v);
            if (v is double)
            {
                double d = (double)v;
                if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("not a finite number");
                var os = old as ScalarValue;
                if (os != null && os.IsInt && d == Math.Floor(d) && Math.Abs(d) < 2147483647.0) return new ScalarIntValue((int)d);
                return new ScalarDoubleValue(d);
            }
            if (v is bool) return new BooleanValue((bool)v);
            if (v is string) return new StringValue((string)v);
            var lx = v as Lex;
            if (lx != null)
            {
                var l = new Lexicon();
                foreach (var kv in lx)
                {
                    if (kv.Value is Structure) l[new StringValue(kv.Key)] = (Structure)kv.Value;
                    else l[new StringValue(kv.Key)] = ToKos(kv.Value, null);
                }
                return l;
            }
            throw new InvalidCastException("no kOS value for " + (v == null ? "null" : v.GetType().Name));
        }

        static bool Same(object a, object b)
        {
            if (a is Lex || b is Lex) return ReferenceEquals(a, b);
            if (a is double && b is double)             // bit for bit (a -0 is a change)
                return BitConverter.DoubleToInt64Bits((double)a) == BitConverter.DoubleToInt64Bits((double)b);
            if ((a is int || a is double) && (b is int || b is double)) return Lex.Num(a) == Lex.Num(b);
            if (a is string && b is string) return string.Equals((string)a, (string)b, StringComparison.Ordinal);
            if (a is bool && b is bool) return (bool)a == (bool)b;
            return ReferenceEquals(a, b);
        }

        // the keys the cycle changed (after vs before) into kOS's lexicon: every value built first, then written
        public static void WriteBack(Lexicon dst, Lex before, Lex after)
        {
            var keys = new List<StringValue>();
            var vals = new List<Structure>();
            foreach (var kv in after)
            {
                object b;
                bool had = before.TryGetValue(kv.Key, out b);
                if (kv.Value is Structure) continue;
                if (had && Same(b, kv.Value)) continue;
                var key = new StringValue(kv.Key);
                Structure old = null;
                if (had) dst.TryGetValue(key, out old);
                keys.Add(key);
                vals.Add(ToKos(kv.Value, old));
            }
            for (int i = 0; i < keys.Count; i++) dst[keys[i]] = vals[i];
        }

        // ---------------------------------------------------------------- one cycle
        // gl = LIST(TG_X_AIM, TG_XALI_X, TG_R2MAX, tgDsbMax, TG_DSBSUP, TG_DSBLIM, TG_DSBNOM, TG_DOWNMODE_POLICY): the globals
        // taemg.ks reads that lib_land / taemg_set_aim set in flight
        public static void Cycle(Taemg T, Lexicon tg, Lexicon st, ListValue gl)
        {
            Globals(T, gl);
            Lex before = LexFrom(tg, true);
            Lex work = new Lex(before);
            Lex sl = LexFrom(st, false);
            T.taemg_cycle(work, sl);
            WriteBack(tg, before, work);
        }

        static void Globals(Taemg T, ListValue gl)
        {
            if (gl.Count != 8) throw new ArgumentException("TGCYCLE: the globals list needs 8 items, has " + gl.Count);
            T.TG_X_AIM = ((ScalarValue)gl[0]).GetDoubleValue();
            T.TG_XALI_X = ((ScalarValue)gl[1]).GetDoubleValue();
            T.TG_R2MAX = ((ScalarValue)gl[2]).GetDoubleValue();
            T.tgDsbMax = ((ScalarValue)gl[3]).GetDoubleValue();
            T.TG_DSBSUP = ((ScalarValue)gl[4]).GetDoubleValue();
            T.TG_DSBLIM = ((ScalarValue)gl[5]).GetDoubleValue();
            T.TG_DSBNOM = ((ScalarValue)gl[6]).GetDoubleValue();
            T.TG_DOWNMODE_POLICY = gl[7].ToString();
        }

        // ---------------------------------------------------------------- the GRTLS's TAEM display (Taemg.taemg_grtls)
        // a = LIST(mode, GR, st, globals, bank, brate, ecal, hdot, TG_OVERHEAD_DEFAULT, GR_ECOMPG): one call in place of
        // lib_grtls's grtlsTgPre ("pre") or phase 4's pass ("p4"), each with grtlsTgDm. Everything is built before anything
        // is written; then tg (in place, or a new GR["tg"] with GR["tgon"] 1), GR["ysgn"] and GR["dmcrew"] (a press taken),
        // GR["gpd"]. -> LEXICON("gp", the GTP lexicon (GR["gpd"]), "ev", "" / "ok" / "rej", "req", the press)
        public static Lexicon Grtls(Taemg T, ListValue a)
        {
            if (a.Count != 10) throw new ArgumentException("GRTG: the list needs 10 items, has " + a.Count);
            string mode = a[0].ToString();
            var GR = (Lexicon)a[1];
            var st = (Lexicon)a[2];
            Globals(T, (ListValue)a[3]);
            double bank = ((ScalarValue)a[4]).GetDoubleValue(), brate = ((ScalarValue)a[5]).GetDoubleValue();
            bool ecal = ((BooleanValue)a[6]).Value;
            double hdot = ((ScalarValue)a[7]).GetDoubleValue();
            bool ovhd = ((BooleanValue)a[8]).Value;
            double ecompg = ((ScalarValue)a[9]).GetDoubleValue();
            var kTgon = new StringValue("tgon");
            bool fresh = mode == "pre" && ((ScalarValue)GR[kTgon]).GetDoubleValue() == 0;
            if (mode != "pre" && mode != "p4") throw new ArgumentException("GRTG: no mode " + mode);
            Lexicon tgK = fresh ? null : (Lexicon)GR[new StringValue("tg")];
            Lex before = fresh ? null : LexFrom(tgK, true);
            Lex work = fresh ? null : new Lex(before);
            var kYs = new StringValue("ysgn");
            Lex res = T.taemg_grtls(mode, work, LexFrom(st, false), ((ScalarValue)GR[kYs]).GetDoubleValue(), bank, brate, ecal,
                                    hdot, ovhd, ecompg);
            work = (Lex)res["tg"];
            Structure gp = ToKos(res["gp"], null);
            Structure tgNew = fresh ? ToKos(work, null) : null;
            Structure ys = res.ContainsKey("ysgn") ? ToKos(res["ysgn"], GR[kYs]) : null;
            if (fresh)
            {
                GR[new StringValue("tg")] = tgNew;
                GR[kTgon] = new ScalarIntValue(1);
            }
            else WriteBack(tgK, before, work);
            if (ys != null)
            {
                GR[kYs] = ys;
                GR[new StringValue("dmcrew")] = BooleanValue.True;
            }
            GR[new StringValue("gpd")] = gp;
            var r = new Lexicon();
            r[new StringValue("gp")] = gp;
            r[new StringValue("ev")] = new StringValue((string)res["ev"]);
            r[new StringValue("req")] = new StringValue((string)res["req"]);
            return r;
        }

        // a = LIST(st, globals, ysgn, psha): lib_grtls's grtlsRcE5 (range control's EOW - EN in phase 5). -> the number;
        // nothing written
        public static double GrtlsE5(Taemg T, ListValue a)
        {
            if (a.Count != 4) throw new ArgumentException("GRTGE5: the list needs 4 items, has " + a.Count);
            var st = (Lexicon)a[0];
            Globals(T, (ListValue)a[1]);
            double ys = ((ScalarValue)a[2]).GetDoubleValue(), psha = ((ScalarValue)a[3]).GetDoubleValue();
            return T.taemg_grtls_e5(LexFrom(st, false), ys, psha);
        }
    }
}
