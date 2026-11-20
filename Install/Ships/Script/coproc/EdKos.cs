// the kOS side of Ed.cs -- EdHost (the suffix bodies) and EdReg (registers them on ADDONS:KALS; the addon's
// KalsAddon.Ed.cs, the offline VM's vmsock.cs). TdKos.cs's pattern; none of them throws into kOS:
//   EDSETUP() -> "" (after edInit: everything a draw reads is there) or "error ..."
//   EDDRAW(LIST(the hook's reads: lib_entdisp's edCsIn)) -> LIST(widget, code, value, ...) / "error ..."
//      one draw of the entry page (edTickK's body); the widget writes in the kOS code's order (TdKos.cs's codes). kOS's
//      state (the slots' bookkeeping, edRgKey, edDbA) is written at the end, only when the whole call succeeded.
//   EDERROR, EDN (calls), EDMS (the mean ms a call).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public class EdHost
    {
        readonly TdEnv env;
        readonly EdCalc calc;
        readonly Func<bool> failHook;
        bool ready;
        public string Error = "";
        public int N = 0;
        double ms = 0; int msN = 0;

        public EdHost(kOS.Safe.Execution.ICpu c, Func<bool> fail)
        {
            failHook = fail;
            env = new TdEnv(c);
            calc = new EdCalc(env);
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
            var l = v as ListValue;
            if (l != null) foreach (var x in l) Finite(x, what);
        }

        public StringValue Setup()
        {
            try { env.Clear(); calc.Setup(); env.Clear(); ready = true; Error = ""; return new StringValue(""); }
            catch (Exception ex) { ready = false; return Err(ex); }
        }

        public Structure Draw(ListValue inp)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (failHook != null && failHook()) throw new Exception("test failure (VMSOCKFAIL)");
                if (!ready) throw new Exception("EDSETUP not done");
                if (inp.Count != 33 && inp.Count != 34) throw new Exception("EDDRAW: " + inp.Count + " reads, not 33 or 34");     // The 34th = SW 02 GUIDANCE LOST
                env.Clear();
                calc.Draw(inp);
                foreach (var v in calc.Ops) Finite(v, "an op");
                foreach (var kv in env.Gw) Finite(kv.Value, kv.Key);
                foreach (var kv in env.Lw) foreach (var kv2 in kv.Value) Finite(kv2.Value, "a slot");
                // The writes applied here (WApply, with lib_taemdisp tdCsApply's tdVis), kOS gets an empty list
                var r = new ListValue();
                WApply.Ops(calc.Ops, true); env.Commit();
                ms += sw.Elapsed.TotalMilliseconds; msN++; N++;
                return r;
            }
            catch (Exception ex) { return Err(ex); }
        }

        public string Ms() { return msN == 0 ? "-" : (ms / msN).ToString("F4") + " ms/call over " + msN; }
    }

    public static class EdReg
    {
        public static EdHost Register(kOS.Safe.Execution.ICpu cpu, Action<string, ISuffix> add, Func<bool> fail)
        {
            var h = new EdHost(cpu, fail);
            add("EDSETUP", new Suffix<StringValue>(() => h.Setup()));
            add("EDDRAW", new OneArgsSuffix<Structure, ListValue>(l => h.Draw(l)));
            add("EDERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("EDGDL", new Suffix<ScalarValue>(() => ScalarValue.Create(1)));       // marks a DLL whose EDDRAW takes the 34th item (the guidance-lost flag)
            add("EDN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("EDMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            return h;
        }
    }
}
