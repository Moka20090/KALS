// the kOS side of Tj.cs -- TjHost (the suffix bodies) and TjReg (registers them on ADDONS:KALS; the addon's
// KalsAddon.Tj.cs, the offline VM's vmsock.cs). None of them throws into kOS:
//   TJSETUP() -> "" (after trajInit: everything a draw reads is there) or "error ..."
//   TJDRAW(LIST(args, now, bxr, uiDispOn(), count)) -> LIST(widget, code, value, ...) / "error ..."
//      one ENTRY TRAJ update (trajUpdate's body after its guard; count 0 = a redraw between guidance cycles: tjCycle, the
//      flash phase, stays): the widget writes in the kOS code's order, codes 0 TEXT, 1 IMAGE, 4 STYLE:MARGIN:H,
//      5 STYLE:MARGIN:V, 7 STYLE:BG. kOS's state (tjCycle, tjPanel, the crumbs, the readout caches) is written at the end,
//      only when the whole call succeeded and every number is finite.
//   TJFORGET() -> "": TJ_CS_SKIP's memory of the last values set dropped. TJERROR, TJN (calls), TJMS (mean ms per call),
//   TJSKIP (ops dropped by TJ_CS_SKIP / ops made).
//   TJFAMBANK(bank, vr) = entry_predict's eprTrajBankRange, TJGENBANK(bank, vr) = lib_tal's talGenBankRange, TJTALRANGE(vr,
//   rng) = lib_tal's talTrajRange (the box's range on the nominal / TAL lines, the TAL bug's range among the generic lines):
//   a number, or "error ..." (kOS's own function then); TJNLOOK counts them.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public class TjHost
    {
        readonly TjEnv env;
        readonly TjCalc calc;
        readonly TjFam famc;
        readonly Func<bool> failHook;
        bool ready;
        public string Error = "";
        public int N = 0;
        double ms = 0; int msN = 0;

        public TjHost(kOS.Safe.Execution.ICpu c, Func<bool> fail)
        {
            failHook = fail;
            env = new TjEnv(c);
            calc = new TjCalc(env);
            famc = new TjFam(env);
        }

        StringValue Err(Exception ex)
        {
            Error = ex.GetType().Name + ": " + ex.Message;
            env.Clear(); calc.Pend.Clear();
            return new StringValue("error " + Error);
        }
        static void Finite(Structure v, string what)
        {
            var s = v as ScalarValue;
            if (s != null) { double d = s.GetDoubleValue(); if (double.IsNaN(d) || double.IsInfinity(d)) throw new Exception(what + " not finite"); }
        }

        public StringValue Setup()
        {
            try { env.Clear(); calc.Setup(); env.Clear(); calc.Last.Clear(); calc.Pend.Clear(); ready = true; Error = ""; return new StringValue(""); }
            catch (Exception ex) { ready = false; return Err(ex); }
        }

        public Structure Draw(ListValue inp)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                if (failHook != null && failHook()) throw new Exception("test failure (VMSOCKFAIL)");
                if (!ready) throw new Exception("TJSETUP not done");
                env.Clear();
                calc.Draw(inp);
                foreach (var v in calc.Ops) Finite(v, "an op");
                foreach (var kv in env.Gw) Finite(kv.Value, kv.Key);
                foreach (var kv in env.Lw) foreach (var kv2 in kv.Value) Finite(kv2.Value, "a list element");
                // The writes applied here (WApply, as traj_display tjCsApply), kOS gets an empty list
                var r = new ListValue();
                WApply.Ops(calc.Ops, false); env.Commit(); calc.CommitLast();
                ms += sw.Elapsed.TotalMilliseconds; msN++; N++;
                return r;
            }
            catch (Exception ex) { return Err(ex); }
        }

        public StringValue Forget()
        {
            calc.Last.Clear(); calc.Pend.Clear(); return new StringValue("");
        }

        // the family lookups: a number, or "error ..." (kOS then looks it up itself)
        public int NLook = 0;
        Structure Look(Func<double> f)
        {
            try
            {
                if (failHook != null && failHook()) throw new Exception("test failure (VMSOCKFAIL)");
                double r = f();
                if (double.IsNaN(r) || double.IsInfinity(r)) throw new Exception("the range is not finite");
                NLook++;
                return ScalarValue.Create(r);
            }
            catch (Exception ex) { return Err(ex); }
        }
        public Structure FamBank(ScalarValue bank, ScalarValue vr)
        {
            return Look(() => { famc.LoadFam(); return famc.TrajBankRange(Tjm.D(bank), Tjm.D(vr)); });
        }
        public Structure GenBank(ScalarValue bank, ScalarValue vr)
        {
            return Look(() => { famc.LoadGen(); return famc.GenBankRange(Tjm.D(bank), Tjm.D(vr)); });
        }
        public Structure TalRange(ScalarValue vr, ScalarValue rng)
        {
            return Look(() => { famc.LoadFam(); famc.LoadGen(); return famc.TalTrajRange(Tjm.D(vr), Tjm.D(rng)); });
        }

        public string Ms() { return msN == 0 ? "-" : (ms / msN).ToString("F4") + " ms/call over " + msN; }
        public string Skip() { return calc.NSkip + " / " + calc.NOps; }
    }

    public static class TjReg
    {
        public static TjHost Register(kOS.Safe.Execution.ICpu cpu, Action<string, ISuffix> add, Func<bool> fail)
        {
            var h = new TjHost(cpu, fail);
            add("TJSETUP", new Suffix<StringValue>(() => h.Setup()));
            add("TJDRAW", new OneArgsSuffix<Structure, ListValue>(l => h.Draw(l)));
            add("TJFORGET", new Suffix<StringValue>(() => h.Forget()));
            add("TJERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("TJN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("TJMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            add("TJFAMBANK", new TwoArgsSuffix<Structure, ScalarValue, ScalarValue>((b, v) => h.FamBank(b, v)));
            add("TJGENBANK", new TwoArgsSuffix<Structure, ScalarValue, ScalarValue>((b, v) => h.GenBank(b, v)));
            add("TJTALRANGE", new TwoArgsSuffix<Structure, ScalarValue, ScalarValue>((v, r) => h.TalRange(v, r)));
            add("TJNLOOK", new Suffix<ScalarValue>(() => ScalarValue.Create(h.NLook)));
            add("TJSKIP", new Suffix<StringValue>(() => new StringValue(h.Skip())));
            return h;
        }
    }
}
