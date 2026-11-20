// the kOS side of EntryGuid.cs -- the live env (the kOS CPU's globals: GetValue("$name") / SetGlobal), EgHost
// (the suffix bodies) and EgReg.Register (used by KalsAddon.Entry.cs in the game and by the offline VM's ADDONS stand-in,
// vm/vmsock.cs). kOS.Safe only: the vectors come through two delegates. No call throws into kOS: an error comes back as
// the string "error ..." and nothing has been written.
//   EGSETUP(LIST(CONSTANT:E, CONSTANT:DEGTORAD, CONSTANT:RADTODEG)) -> "" / "error ..."
//   EGSTEP(LIST(the 12 inputs, EgIn)) -> the signed bank (a number) with the cycle's globals written, or "error ..." (none)
//   EGERROR, EGN (cycles flown in C#), EGMS (the mean C# time of a cycle, ms)
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public class EgLiveEnv : IEgEnv
    {
        readonly ICpu cpu;
        readonly Func<Structure, Vector3d> vin;
        public EgLiveEnv(ICpu c, Func<Structure, Vector3d> i) { cpu = c; vin = i; }
        public Structure Get(string name) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + name, false)); }
        public void Set(string name, Structure v) { cpu.SetGlobal("$" + name, v); }
        public Vector3d Vec(Structure s) { return vin(s); }
    }

    public class EgHost
    {
        readonly ICpu cpu;
        readonly Func<Structure, Vector3d> vin;
        readonly Func<bool> fail;
        readonly EgCache cache = new EgCache();
        double ce = double.NaN, d2r, r2d;
        public string Error = "";
        public int N = 0;
        double msSum = 0;

        public EgHost(ICpu c, Func<Structure, Vector3d> i, Func<bool> f) { cpu = c; vin = i; fail = f; }

        string Err(Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return "error " + Error; }

        public StringValue Setup(ListValue l)
        {
            try
            {
                ce = EntryGuid.Num(l[0]); d2r = EntryGuid.Num(l[1]); r2d = EntryGuid.Num(l[2]);
                return new StringValue("");
            }
            catch (Exception ex) { return new StringValue(Err(ex)); }
        }

        // the inputs: tal, rv, vv as vectors; the rest as doubles (by EgIn's index)
        void Parse(ListValue l, out bool tal, out Vector3d rv, out Vector3d vv, out double[] d)
        {
            if (l.Count != EgIn.N) throw new ArgumentException("EG input list has " + l.Count + " items, not " + EgIn.N);
            tal = EntryGuid.Bool(l[EgIn.TAL]);
            rv = vin(l[EgIn.RV]);
            vv = vin(l[EgIn.VV]);
            d = new double[EgIn.N];
            for (int i = EgIn.TLAT; i < EgIn.N; i++) d[i] = EntryGuid.Num(l[i]);
        }
        EntryGuid Fresh(bool tal, IEgEnv env)
        {
            if (double.IsNaN(ce)) throw new InvalidOperationException("EGSETUP not called");
            var g = new EntryGuid();
            g.CE = ce; g.DEGTORAD = d2r; g.RADTODEG = r2d;
            g.Load(env, cache, tal);
            return g;
        }
        static double Run(EntryGuid g, Vector3d rv, Vector3d vv, double[] d, double now2)
        {
            return g.Run(rv, vv, d[EgIn.TLAT], d[EgIn.TLNG], d[EgIn.TROT], d[EgIn.DT], d[EgIn.DMEAS], d[EgIn.AOA], d[EgIn.FDN],
                         d[EgIn.NOW], now2, d[EgIn.PS]);
        }

        public Structure Step(ListValue l)
        {
            try
            {
                if (fail != null && fail()) throw new InvalidOperationException("the VM's failure test");
                var t0 = System.Diagnostics.Stopwatch.GetTimestamp();
                bool tal; Vector3d rv, vv; double[] d;
                Parse(l, out tal, out rv, out vv, out d);
                var env = new EgLiveEnv(cpu, vin);
                var g = Fresh(tal, env);
                double b = Run(g, rv, vv, d, d[EgIn.NOW]);
                if (double.IsNaN(b) || double.IsInfinity(b)) throw new ArithmeticException("non-finite bank");
                g.Commit(env);
                N++;
                msSum += (System.Diagnostics.Stopwatch.GetTimestamp() - t0) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                return ScalarValue.Create(b);
            }
            catch (Exception ex) { return new StringValue(Err(ex)); }
        }

        public string Ms() { return N > 0 ? (msSum / N).ToString("0.000") : "-"; }
    }

    public static class EgReg
    {
        public static EgHost Register(ICpu cpu, Action<string, ISuffix> add, Func<Structure, Vector3d> vin,
            Func<Vector3d, Structure> vout, Func<bool> fail)
        {
            var h = new EgHost(cpu, vin, fail);
            add("EGSETUP", new OneArgsSuffix<StringValue, ListValue>(l => h.Setup(l)));
            add("EGSTEP", new OneArgsSuffix<Structure, ListValue>(l => h.Step(l)));
            add("EGERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("EGN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("EGMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            return h;
        }
    }
}
