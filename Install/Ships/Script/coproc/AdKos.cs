// the kOS side of Ad.cs -- AdHost (the suffix bodies) and AdReg (registers them on ADDONS:KALS; the addon's
// KalsAddon.Ad.cs with kOS's Vector, the offline VM's vmsock.cs with its own). None of them throws into kOS:
//   ADSETUP() -> "" (after adInit: everything a draw reads is there) or "error ..."
//   ADDRAW(asc, LIST(the hook's reads: lib_ascdisp's adCsIn)) -> LIST(widget, code, value, ...) / "error ..."
//      one page update (adTick's body after its clock): the widget writes in the kOS code's order, codes 0 TEXT, 1 IMAGE,
//      2 STYLE:WIDTH, 3 STYLE:HEIGHT, 4 STYLE:MARGIN:H, 5 STYLE:MARGIN:V, 6 STYLE:ALIGN, 7 STYLE:BG. kOS's state (the slots'
//      bookkeeping, adBg, adHist, the freezes, adTmS) is written at the end, only when the whole call succeeded.
//   ADERROR, ADN (calls), ADMS (the mean ms per call).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public class AdHost
    {
        readonly kOS.Safe.Execution.ICpu cpu;
        readonly AdEnv env;
        readonly AdCalc calc;
        readonly Func<bool> failHook;
        bool ready;
        public string Error = "";
        public int N = 0;
        double ms = 0; int msN = 0;

        public AdHost(kOS.Safe.Execution.ICpu c, Func<Structure, Vector3d> vi, Func<bool> fail)
        {
            cpu = c; failHook = fail;
            env = new AdEnv(c);
            calc = new AdCalc(env, vi);
        }

        StringValue Err(Exception ex)
        {
            Error = ex.GetType().Name + ": " + ex.Message;
            env.Clear();
            return new StringValue("error " + Error);
        }
        static void Finite(Structure v, string what)
        {
            var s = v as ScalarValue;
            if (s != null) { double d = s.GetDoubleValue(); if (double.IsNaN(d) || double.IsInfinity(d)) throw new Exception(what + " not finite"); }
        }

        public StringValue Setup()
        {
            try { env.Clear(); calc.Setup(); env.Clear(); ready = true; Error = ""; return new StringValue(""); }
            catch (Exception ex) { ready = false; return Err(ex); }
        }

        public Structure Draw(Lexicon asc, ListValue inp)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (failHook != null && failHook()) throw new Exception("test failure (VMSOCKFAIL)");
                if (!ready) throw new Exception("ADSETUP not done");
                env.Clear();
                calc.Draw(asc, inp);
                foreach (var v in calc.Ops) Finite(v, "an op");
                foreach (var kv in env.Gw) Finite(kv.Value, kv.Key);
                foreach (var kv in env.Lw) foreach (var kv2 in kv.Value) Finite(kv2.Value, "a slot");
                foreach (var kv in env.Xw) foreach (var kv2 in kv.Value) Finite(kv2.Value, kv2.Key);
                // The writes applied here (WApply, as lib_ascdisp adCsApply), kOS gets an empty list
                var r = new ListValue();
                WApply.Ops(calc.Ops, false); env.Commit();
                ms += sw.Elapsed.TotalMilliseconds; msN++; N++;
                return r;
            }
            catch (Exception ex) { return Err(ex); }
        }

        public string Ms() { return msN == 0 ? "-" : (ms / msN).ToString("F4") + " ms/call over " + msN; }
    }

    public static class AdReg
    {
        public static AdHost Register(kOS.Safe.Execution.ICpu cpu, Action<string, ISuffix> add, Func<Structure, Vector3d> vin,
            Func<bool> fail)
        {
            var h = new AdHost(cpu, vin, fail);
            add("ADSETUP", new Suffix<StringValue>(() => h.Setup()));
            add("ADDRAW", new TwoArgsSuffix<Structure, Lexicon, ListValue>((a, l) => h.Draw(a, l)));
            add("ADERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("ADN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("ADMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            return h;
        }
    }
}
