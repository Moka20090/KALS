// The kOS side of GrtlsGuid.cs -- the live env (the kOS CPU's globals: GetValue("$name") / SetGlobal), GrHost
// (the suffix bodies) and GrReg.Register (used by KalsAddon.Grtls.cs in the game and by the offline VM's ADDONS stand-in,
// vm/vmsock.cs). kOS.Safe only. No call throws into kOS: an error comes back as the string "error ..." and nothing has
// been written.
//   GRSETUP(LIST(CONSTANT:E)) -> "" / "error ..."
//   GRFCS(LIST(dt, altm, vrel, gam, bank, dit, radar, ps), GrIn) -> the new GR["acmd"] (a number), written with
//       EPR_HINT_RHO / EPR_PR_REF; or "error ..." (none written)
//   GRNZ(LIST(aoa, altm, vrel, ps)) -> grtlsNz's Nz (a number; EPR_HINT_RHO / EPR_PR_REF written), or "error ..."
//   GRAFN(LIST(nzt, altm, vrel, lo, hi, ps)) -> grtlsAfn's alpha (ECAL's ALPHA_UL; EPR_HINT_RHO / EPR_PR_REF written),
//       or "error ..."
//   GRERROR, GRN (calls flown in C#), GRMS (the mean C# time of a call, ms)
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public class GrLiveEnv : IGrEnv
    {
        readonly ICpu cpu;
        public GrLiveEnv(ICpu c) { cpu = c; }
        public Structure Get(string name) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + name, false)); }
        public void Set(string name, Structure v) { cpu.SetGlobal("$" + name, v); }
    }

    public class GrHost
    {
        readonly ICpu cpu;
        readonly Func<bool> fail;
        readonly GrCache cache = new GrCache();
        double ce = double.NaN;
        public string Error = "";
        public int N = 0;
        double msSum = 0;

        public GrHost(ICpu c, Func<bool> f) { cpu = c; fail = f; }

        // the TAEM display's state in a GRTLS (lib_grtls grtlsTgCs): GRTGSETUP(the text of lib/taemg_const.ks, of
        // lib/solq_atm_data.ks) -> TRUE when read (FALSE: GRTGERROR says why); GRTG(TaemgKos.Grtls's list) -> its lexicon,
        // or "error ..." with nothing written; GRTGE5(TaemgKos.GrtlsE5's list) -> range control's EOW - EN in phase 5, or
        // "error ..."
        Taemg tgm;
        public string TgError = "";

        public BooleanValue TgSetup(StringValue constText, StringValue atmText)
        {
            try
            {
                var c = KsConst.Parse(constText.ToString());
                foreach (var kv in KsConst.Parse(atmText.ToString())) c[kv.Key] = kv.Value;
                tgm = new Taemg(c);
                TgError = "";
                return BooleanValue.True;
            }
            catch (Exception ex) { tgm = null; TgError = ex.GetType().Name + ": " + ex.Message; return BooleanValue.False; }
        }

        public Structure Tg(ListValue a)
        {
            try
            {
                if (fail()) throw new InvalidOperationException("the VM's failure switch");
                if (tgm == null) throw new InvalidOperationException("GRTGSETUP first (" + TgError + ")");
                return TaemgKos.Grtls(tgm, a);
            }
            catch (Exception ex) { TgError = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + TgError); }
        }

        public Structure TgE5(ListValue a)
        {
            try
            {
                if (fail()) throw new InvalidOperationException("the VM's failure switch");
                if (tgm == null) throw new InvalidOperationException("GRTGSETUP first (" + TgError + ")");
                return ScalarValue.Create(GrtlsGuid.Fin(TaemgKos.GrtlsE5(tgm, a), "GRTGE5"));
            }
            catch (Exception ex) { TgError = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + TgError); }
        }

        string Err(Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return "error " + Error; }

        public StringValue Setup(ListValue l)
        {
            try { ce = GrtlsGuid.Num(l[0]); return new StringValue(""); }
            catch (Exception ex) { return new StringValue(Err(ex)); }
        }

        static readonly string[] NAME = { "GRNZ", "GRFCS", "GRAFN" };
        static double[] Parse(ListValue l, int mode)
        {
            bool isFcs = mode == GrIn.MODE_FCS;
            int n = isFcs ? GrIn.N : mode == GrIn.MODE_AFN ? GrIn.AFN_N : GrIn.NZ_N;
            if (l.Count != n) throw new ArgumentException(NAME[mode] + " input list has " + l.Count + " items, not " + n);
            var d = new double[n];
            for (int i = 0; i < n; i++)
                d[i] = (isFcs && i == GrIn.DIT) ? (GrtlsGuid.Bool(l[i]) ? 1 : 0) : GrtlsGuid.Num(l[i]);
            return d;
        }
        GrtlsGuid Fresh(int mode, IGrEnv env)
        {
            if (double.IsNaN(ce)) throw new InvalidOperationException("GRSETUP not called");
            var g = new GrtlsGuid();
            g.CE = ce;
            g.Load(env, cache, mode);
            return g;
        }

        static readonly string[] RET = { "nz", "acmd", "alpha" };
        Structure Call(ListValue l, int mode)
        {
            try
            {
                if (fail != null && fail()) throw new InvalidOperationException("the VM's failure test");
                var t0 = System.Diagnostics.Stopwatch.GetTimestamp();
                var d = Parse(l, mode);
                var env = new GrLiveEnv(cpu);
                var g = Fresh(mode, env);
                double r = GrtlsGuid.Fin(g.Run(mode, d), RET[mode]);
                g.Commit(env);
                N++;
                msSum += (System.Diagnostics.Stopwatch.GetTimestamp() - t0) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                return ScalarValue.Create(r);
            }
            catch (Exception ex) { return new StringValue(Err(ex)); }
        }
        public Structure Fcs(ListValue l) { return Call(l, GrIn.MODE_FCS); }
        public Structure Nz(ListValue l) { return Call(l, GrIn.MODE_NZ); }
        public Structure Afn(ListValue l) { return Call(l, GrIn.MODE_AFN); }

        public string Ms() { return N > 0 ? (msSum / N).ToString("0.000") : "-"; }
    }

    public static class GrReg
    {
        public static GrHost Register(ICpu cpu, Action<string, ISuffix> add, Func<bool> fail)
        {
            var h = new GrHost(cpu, fail);
            add("GRSETUP", new OneArgsSuffix<StringValue, ListValue>(l => h.Setup(l)));
            add("GRFCS", new OneArgsSuffix<Structure, ListValue>(l => h.Fcs(l)));
            add("GRNZ", new OneArgsSuffix<Structure, ListValue>(l => h.Nz(l)));
            add("GRAFN", new OneArgsSuffix<Structure, ListValue>(l => h.Afn(l)));
            add("GRERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("GRN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("GRMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            add("GRTGSETUP", new TwoArgsSuffix<BooleanValue, StringValue, StringValue>((c, t) => h.TgSetup(c, t)));
            add("GRTG", new OneArgsSuffix<Structure, ListValue>(l => h.Tg(l)));
            add("GRTGE5", new OneArgsSuffix<Structure, ListValue>(l => h.TgE5(l)));
            add("GRTGERROR", new Suffix<StringValue>(() => new StringValue(h.TgError)));
            return h;
        }
    }
}
