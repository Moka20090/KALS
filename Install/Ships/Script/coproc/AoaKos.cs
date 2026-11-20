// the bridge between kOS and the AOA solve (Aoa.cs) and the handle kOS polls. In: on the main thread, kOS's input
// lexicon (lib_aoa.ks aoaCsIn: "c" the constants by their kOS names, "rv", "vv", "tGeo", "slat", "slng", "dvMax", "radial",
// "spent", "threads") copied into plain C# (a missing key, a wrong type or a number not finite: a finished handle with its
// ERROR, before any work). The solve runs on its own thread (below normal) with its workers and touches no kOS / Unity
// object. Out: RESULT, a fresh kOS lexicon built on the main thread when kOS reads it: "found", "x" (aoaSolve's LEXICON, its
// keys in kOS's order; numbers through kOS's own ScalarValue.Create), "xtOnly" (-1 = unchanged), "whyk", "tHi", "gam0",
// "evals", "evalsR". Never throws into kOS. Built twice: into the addon (kOS.dll's Vector) and, with -define:KOSVM, into the
// offline VM (its Vec), so the staged kOS hook runs against this very code in the VM.
using System;
using System.Collections.Generic;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;
#if KOSVM
using KVec = Vec;
#else
using KVec = kOS.Suffixed.Vector;
#endif

namespace KalsCoproc
{
    public static class AoaKos
    {
        static Structure Get(Lexicon l, string k)
        {
            var key = new StringValue(k);
            if (!l.ContainsKey(key)) throw new KeyNotFoundException("key " + k + " missing");
            return l[key];
        }

        static double Dbl(Structure s, string k)
        {
            var sc = s as ScalarValue;
            if (sc == null) throw new InvalidCastException(k + " is not a number");
            double d = sc.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException(k + " is not finite");
            return d;
        }

        static bool Bool(Structure s, string k)
        {
            var b = s as BooleanValue;
            if (b == null) throw new InvalidCastException(k + " is not a boolean");
            return b.Value;
        }

        static Vec3 Vec(Structure s, string k)
        {
            var v = s as KVec;
            if (v == null) throw new InvalidCastException(k + " is not a vector");
            return new Vec3(v.X, v.Y, v.Z);
        }

        static double[] Arr(Structure s, string k)
        {
            var li = s as ListValue;
            if (li == null) throw new InvalidCastException(k + " is not a list");
            var a = new double[li.Count];
            int i = 0;
            foreach (Structure x in li) { a[i] = Dbl(x, k + "[" + i + "]"); i++; }
            return a;
        }

        static object Conv(Structure s, string k, Type t)
        {
            if (t == typeof(double)) return Dbl(s, k);
            if (t == typeof(bool)) return Bool(s, k);
            if (t == typeof(Vec3)) return Vec(s, k);
            if (t == typeof(double[])) return Arr(s, k);
            throw new InvalidCastException(k + ": no conversion to " + t.Name);
        }

        public static AoaIn In(Lexicon l)
        {
            var cs = Get(l, "c") as Lexicon;
            if (cs == null) throw new InvalidCastException("c is not a lexicon");
            var i = new AoaIn();
            i.c = AoaC.From((k, t) => Conv(Get(cs, k), k, t));
            i.rv = Vec(Get(l, "rv"), "rv");
            i.vv = Vec(Get(l, "vv"), "vv");
            i.tGeo = Dbl(Get(l, "tGeo"), "tGeo");
            i.slat = Dbl(Get(l, "slat"), "slat");
            i.slng = Dbl(Get(l, "slng"), "slng");
            i.dvMax = Dbl(Get(l, "dvMax"), "dvMax");
            i.radial = Bool(Get(l, "radial"), "radial");
            i.spent = Dbl(Get(l, "spent"), "spent");
            i.threads = (int)Math.Round(Dbl(Get(l, "threads"), "threads"));
            return i;
        }

        static Structure Num(double d) { return ScalarValue.Create(d); }

        public static Lexicon Out(AoaRes r)
        {
            var l = new Lexicon();
            l[new StringValue("found")] = new BooleanValue(r.x != null);
            if (r.x != null)
            {
                var x = new Lexicon();
                foreach (var kv in r.x.Pairs())
                {
                    Structure v;
                    if (kv.Value is bool) v = new BooleanValue((bool)kv.Value);
                    else
                    {
                        double d = (double)kv.Value;
                        if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("x." + kv.Key + " is not finite");
                        v = Num(d);
                    }
                    x[new StringValue(kv.Key)] = v;
                }
                l[new StringValue("x")] = x;
            }
            l[new StringValue("xtOnly")] = Num(r.xtOnly);
            l[new StringValue("whyk")] = Num(r.whyk);
            l[new StringValue("tHi")] = Num(r.tHi);
            l[new StringValue("gam0")] = Num(r.gam0);
            l[new StringValue("evals")] = Num(r.evals);
            l[new StringValue("evalsR")] = Num(r.evalsR);
            return l;
        }
    }

    [KOSNomenclature("KALSAoaSolve")]
    public class AoaHandle : Structure
    {
        volatile bool done;
        AoaJob job;
        string err = "";
        Lexicon res;

        public AoaHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => done));
            AddSuffix("ERROR", new Suffix<StringValue>(() => done ? err : ""));
            AddSuffix("OK", new Suffix<BooleanValue>(() => done && err == ""));
            AddSuffix("THREADS", new Suffix<ScalarValue>(() => job == null ? 0 : job.threads));
            AddSuffix("MS", new Suffix<ScalarValue>(() => done && err == "" && job.res != null ? job.res.ms : -1));
            AddSuffix("RESULT", new Suffix<Lexicon>(Result));
        }

        Lexicon Result()
        {
            if (!done || err != "" || job == null || job.res == null) return new Lexicon();
            if (res == null)
            {
                try { res = AoaKos.Out(job.res); }
                catch (Exception ex) { err = "result: " + ex.Message; return new Lexicon(); }
            }
            return res;
        }

        // the input copied here (kOS's main thread); the solve on its own thread
        public static AoaHandle Start(Lexicon l)
        {
            var h = new AoaHandle();
            try
            {
                h.job = new AoaJob(AoaKos.In(l));
                var t = new Thread(() =>
                {
                    try { h.job.Run(); }
                    catch (Exception ex) { h.err = ex.GetType().Name + ": " + ex.Message; }
                    h.done = true;
                });
                t.IsBackground = true;
                t.Priority = ThreadPriority.BelowNormal;
                t.Start();
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }

        public void Fail(string msg) { err = msg; done = true; }

        public override string ToString() { return done ? "KALSAoaSolve(" + (err == "" ? "done" : err) + ")" : "KALSAoaSolve(running)"; }
    }
}
