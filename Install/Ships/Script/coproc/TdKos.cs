// the kOS side of Td.cs -- TdHost (the suffix bodies) and TdReg (registers them on ADDONS:KALS; the addon's
// KalsAddon.Td.cs, the offline VM's vmsock.cs). None of them throws into kOS:
//   TDSETUP() -> "" (after tdInit: everything a draw reads is there) or "error ..."
//   TDDRAW(a, b, LIST(the hook's reads: lib_taemdisp's tdCsIn)) -> LIST() (the writes applied here, WApply.Ops)
//      / "error ..."
//      one draw: inp[0] 0 = tdTick's body (a = tg, b = st), 1 = tdGrTick's (a = gr, b = st); the widget writes in the kOS
//      code's order, codes 0 TEXT, 1 IMAGE, 2 STYLE:WIDTH, 3 STYLE:HEIGHT, 4 STYLE:MARGIN:H, 5 STYLE:MARGIN:V, 6 STYLE:ALIGN,
//      7 STYLE:BG. kOS's state (the slots' bookkeeping, the draw's globals) is written at the end, only when the whole
//      call succeeded (every number finite).
//   TDERROR, TDN (calls), TDMS (the mean ms a call).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public class TdHost
    {
        readonly TdEnv env;
        readonly TdCalc calc;
        readonly Func<bool> failHook;
        bool ready;
        public string Error = "";
        public int N = 0;
        double ms = 0; int msN = 0;

        public TdHost(kOS.Safe.Execution.ICpu c, Func<bool> fail)
        {
            failHook = fail;
            env = new TdEnv(c);
            calc = new TdCalc(env);
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

        public Structure Draw(Lexicon a, Lexicon b, ListValue inp)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (failHook != null && failHook()) throw new Exception("test failure (VMSOCKFAIL)");
                if (!ready) throw new Exception("TDSETUP not done");
                env.Clear();
                calc.Draw(a, b, inp);
                foreach (var v in calc.Ops) Finite(v, "an op");
                foreach (var kv in env.Gw) Finite(kv.Value, kv.Key);
                foreach (var kv in env.Lw) foreach (var kv2 in kv.Value) Finite(kv2.Value, "a slot");
                var r = new ListValue();
                // the widget writes are applied here, in the kOS code's order (kOS's tdCsApply loop cost ~50 opcodes a write,
                // 5400 opcodes a draw in track up: the page redrew far below 10 Hz); the list handed back is empty
                Apply(calc.Ops);
                env.Commit();
                ms += sw.Elapsed.TotalMilliseconds; msN++; N++;
                return r;
            }
            catch (Exception ex) { return Err(ex); }
        }

        // the widget writes of one draw: LIST(widget, code, value ...) as lib_taemdisp tdCsApply reads it, with its tdVis
        // (WApply.cs; the C# shows / hides the labels it writes, as kOS's tdVis does)
        static void Apply(List<Structure> ops) { WApply.Ops(ops, true); }

        public string Ms() { return msN == 0 ? "-" : (ms / msN).ToString("F4") + " ms/call over " + msN; }
    }

    public static class TdReg
    {
        public static TdHost Register(kOS.Safe.Execution.ICpu cpu, Action<string, ISuffix> add, Func<bool> fail)
        {
            var h = new TdHost(cpu, fail);
            add("TDSETUP", new Suffix<StringValue>(() => h.Setup()));
            add("TDDRAW", new ThreeArgsSuffix<Structure, Lexicon, Lexicon, ListValue>((a, b, l) => h.Draw(a, b, l)));
            add("TDERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("TDGPC", new Suffix<ScalarValue>(() => ScalarValue.Create(1)));       // marks a DLL whose TDDRAW takes the 24th / 25th items (the windows whose GPC lives)
            add("TDN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("TDMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            return h;
        }
    }
}
