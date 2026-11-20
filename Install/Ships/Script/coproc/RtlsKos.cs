// the kOS side of RtlsPpd.cs and CntM2.cs. ADDONS:KALS:RTPPD(LIST(15 numbers: RtlsPpd's order)) -> LIST(dV,
// dgam, dx); ADDONS:KALS:RTM2(LIST(26 items: CntM2's order, below)) -> LIST(e2, th2, law_k, wrote, law_x, law_d,
// law_rel, ret); either: or the string "error ..." (nothing in kOS is touched either way, every result finite-checked);
// RTERROR (the last error), RTN (calls), RTMS (the C# time, ms per call). None throws into kOS. The addon
// (KalsAddon.Rtls.cs) and the offline VM (vmsock.cs) register the same suffixes through RtReg.Register.
using System;
using System.Diagnostics;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public class RtHost
    {
        readonly Func<bool> fail;
        public string Error = "";
        public int N = 0;
        double msSum = 0;

        public RtHost(Func<bool> f) { fail = f; }

        static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new ArgumentException("not a number: " + (s == null ? "null" : s.GetType().Name));
            return sv.GetDoubleValue();
        }

        public Structure Ppd(ListValue l)
        {
            try
            {
                if (fail != null && fail()) throw new InvalidOperationException("VMSOCKFAIL");
                if (l.Count != RtlsPpd.N) throw new ArgumentException("RTPPD input list has " + l.Count + " items, not " + RtlsPpd.N);
                var a = new double[RtlsPpd.N];
                for (int i = 0; i < RtlsPpd.N; i++)
                {
                    a[i] = Num(l[i]);
                    if (double.IsNaN(a[i]) || double.IsInfinity(a[i])) throw new ArgumentException("RTPPD input " + i + " is not finite");
                }
                var sw = Stopwatch.StartNew();
                double[] r = RtlsPpd.Predict(a);
                sw.Stop();
                for (int i = 0; i < r.Length; i++)
                    if (double.IsNaN(r[i]) || double.IsInfinity(r[i])) throw new ArithmeticException("RTPPD result " + i + " is not finite");
                N++;
                msSum += sw.Elapsed.TotalMilliseconds;
                var o = new ListValue();
                for (int i = 0; i < r.Length; i++) o.Add(ScalarValue.Create(r[i]));
                return o;
            }
            catch (Exception ex)
            {
                Error = ex.GetType().Name + ": " + ex.Message;
                return new StringValue("error " + Error);
            }
        }

        static bool Bool(Structure s)
        {
            var b = s as BooleanValue;
            if (b == null) throw new ArgumentException("not a boolean: " + (s == null ? "null" : s.GetType().Name));
            return b.Value;
        }

        static double Fin(double x, string what)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException(what + " is not finite");
            return x;
        }

        public const int M2N = 26;
        // the inputs: rr, vv, ix, iy, iz, acc, abo, law_x, eps (LIST of vectors), ASC_MU, ASC_R, ASC_CNT_THETA_MODE2,
        // ASC_CNT_CANT, _M2_FLAT, _M2_EGATE, _M2_EFIX, _M2_HCAP, _M2_EMIN, _M2_HT, _M2_HDMIN, _M2_KH, _M2_K, _LAW, _LAW_VIPK,
        // _LAW_K (LIST of 7), _LAW_HO
        public Structure M2(ListValue l, Func<Structure, Vector3d> vin)
        {
            try
            {
                if (fail != null && fail()) throw new InvalidOperationException("VMSOCKFAIL");
                if (l.Count != M2N) throw new ArgumentException("RTM2 input list has " + l.Count + " items, not " + M2N);
                var c = new CntM2In();
                c.rr = vin(l[0]); c.vv = vin(l[1]); c.ix = vin(l[2]); c.iy = vin(l[3]); c.iz = vin(l[4]);
                c.acc = Num(l[5]); c.abo = Num(l[6]); c.law_x = Num(l[7]);
                var el = l[8] as ListValue;
                if (el == null) throw new ArgumentException("RTM2: eps is not a list");
                c.eps = new Vector3d[el.Count];
                for (int i = 0; i < el.Count; i++) c.eps[i] = vin(el[i]);
                c.MU = Num(l[9]); c.R = Num(l[10]); c.THETA_MODE2 = Num(l[11]); c.CANT = Num(l[12]); c.M2_FLAT = Bool(l[13]);
                c.M2_EGATE = Num(l[14]); c.M2_EFIX = Num(l[15]); c.M2_HCAP = Num(l[16]); c.M2_EMIN = Num(l[17]);
                c.M2_HT = Num(l[18]); c.M2_HDMIN = Num(l[19]); c.M2_KH = Num(l[20]); c.M2_K = Num(l[21]); c.LAW = Bool(l[22]);
                c.LAW_VIPK = Num(l[23]);
                var kl = l[24] as ListValue;
                if (kl == null || kl.Count != 7) throw new ArgumentException("RTM2: LAW_K is not a list of 7");
                c.LAW_K = new double[7];
                for (int i = 0; i < 7; i++) c.LAW_K[i] = Num(kl[i]);
                c.LAW_HO = Num(l[25]);
                var sw = Stopwatch.StartNew();
                CntM2Out o = CntM2.Pass(c);
                sw.Stop();
                var r = new ListValue();
                r.Add(ScalarValue.Create(Fin(o.e2, "e2"))); r.Add(ScalarValue.Create(Fin(o.th2, "th2")));
                r.Add(ScalarValue.Create((int)o.law_k)); r.Add((o.wrote ? BooleanValue.True : BooleanValue.False));
                if (o.wrote)
                {
                    r.Add(ScalarValue.Create(Fin(o.law_x, "law_x"))); r.Add(ScalarValue.Create(Fin(o.law_d, "law_d")));
                    r.Add(ScalarValue.Create(Fin(o.law_rel, "law_rel")));
                }
                else { r.Add(ScalarValue.Create(0)); r.Add(ScalarValue.Create(0)); r.Add(ScalarValue.Create(0)); }
                r.Add((o.ret ? BooleanValue.True : BooleanValue.False));
                N++;
                msSum += sw.Elapsed.TotalMilliseconds;
                return r;
            }
            catch (Exception ex)
            {
                Error = ex.GetType().Name + ": " + ex.Message;
                return new StringValue("error " + Error);
            }
        }

        public string Ms() { return N > 0 ? (msSum / N).ToString("R") : "0"; }
    }

    public static class RtReg
    {
        // the same signature as EgReg.Register (vin: RTM2's vectors; vout unused)
        public static RtHost Register(ICpu cpu, Action<string, ISuffix> add, Func<Structure, Vector3d> vin,
            Func<Vector3d, Structure> vout, Func<bool> fail)
        {
            var h = new RtHost(fail);
            add("RTPPD", new OneArgsSuffix<Structure, ListValue>(l => h.Ppd(l)));
            add("RTM2", new OneArgsSuffix<Structure, ListValue>(l => h.M2(l, vin)));
            add("RTERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("RTN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            add("RTMS", new Suffix<StringValue>(() => new StringValue(h.Ms())));
            return h;
        }
    }
}
