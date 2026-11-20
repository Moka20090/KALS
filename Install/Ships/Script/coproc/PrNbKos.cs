// ADDONS:KALS:NBSOLVE(lexicon) -> a handle (DONE / ERROR / RESULT / MS) of ONE n-body solve (PrNb.cs) running on its own thread,
// below-normal priority, touching no kOS / Unity object (the third-body positions are sampled on the main thread here, before the thread
// starts, by NbReg.Bodies which KalsAddon.Pr.cs sets from KSP's bodies; the Kerbal-less kOS VM test leaves it null). Never throws into kOS:
// a bad input is a finished handle with its ERROR. The input is plain kOS numbers: LIST(x, y, z) for every vector.
//   t0, r, v, ut          the state and the Kepler solve's burn point (UT)
//   type, when            0 CIRC 1 HA 2 HP 3 PLANE 4 DV; 0 APO 1 PERI 2 AN 3 DN 4 TIME 5 T+   (ops2q's btype / bwhen)
//   rt (m) / inc (deg)    the HA / HP radius, the PLANE inclination;   dvl LIST(x, y, z)  the DV burn's LVLH dv;  nodv  TRUE: the Kepler solve had nothing to do
//   mu, j2, rj2, pole     the main body's GM, its J2 and the reference radius (0 = a point mass), its north (unit);  lh  TRUE: left-handed vectors (O2_LH)
// RESULT (when DONE and ERROR is ""): ut (the burn point on the n-body coast), dt (ut - the input ut), ev (1: re-found), r / v (the state at ut,
// before the burn), dv (the world vector), ra / rp (the max / min radius over one period after the burn), per, k (the prograde dv of HA / HP,
// the speed of CIRC), ms, evals.
using System;
using System.Collections.Generic;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    [KOSNomenclature("KALSNbSolve")]
    public class NbHandle : Structure
    {
        volatile bool done;
        NbJob job; string err = "";
        Lexicon res;

        public NbHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => done));
            AddSuffix("ERROR", new Suffix<StringValue>(() => done ? err : ""));
            AddSuffix("MS", new Suffix<ScalarValue>(() => done && job != null ? job.Ms : -1));
            AddSuffix("RESULT", new Suffix<Lexicon>(Result));
        }

        static ListValue L3(double[] a)
        {
            var l = new ListValue();
            for (int i = 0; i < 3; i++) l.Add(new ScalarDoubleValue(a[i]));
            return l;
        }

        Lexicon Result()
        {
            if (!done || err != "" || job == null) return new Lexicon();
            if (res == null)
            {
                var k = new Lexicon();
                k[new StringValue("ut")] = new ScalarDoubleValue(job.OutUt);
                k[new StringValue("dt")] = new ScalarDoubleValue(job.OutUt - job.Ut);
                k[new StringValue("ev")] = new ScalarIntValue(job.Ev);
                k[new StringValue("r")] = L3(job.OutR);
                k[new StringValue("v")] = L3(job.OutV);
                k[new StringValue("dv")] = L3(job.OutDv);
                k[new StringValue("ra")] = new ScalarDoubleValue(job.Ra);
                k[new StringValue("rp")] = new ScalarDoubleValue(job.Rp);
                k[new StringValue("per")] = new ScalarDoubleValue(job.Per);
                k[new StringValue("k")] = new ScalarDoubleValue(job.K);
                k[new StringValue("ms")] = new ScalarDoubleValue(job.Ms);
                k[new StringValue("evals")] = new ScalarDoubleValue(job.Evals);
                res = k;
            }
            return res;
        }

        public void Fail(string why) { err = why; done = true; }

        public void Start(NbJob j)
        {
            job = j;
            var t = new Thread(() =>
            {
                try { if (!job.Run()) err = job.Err == "" ? "N-BODY FAILED" : job.Err; }
                catch (Exception ex) { err = ex.GetType().Name + ": " + ex.Message; }
                done = true;
            });
            t.IsBackground = true;
            t.Priority = ThreadPriority.BelowNormal;
            t.Start();
        }
    }

    public static class NbReg
    {
        // set by the addon: the third bodies' relative positions, sampled on the main thread: (t0, t1, step) -> bodies, null = none
        public static Func<double, double, double, NbBodies> Bodies;

        static double Num(Lexicon l, string key)
        {
            Structure s = l[new StringValue(key)];
            var sc = s as ScalarValue;
            if (sc == null) throw new InvalidCastException(key + " is not a number");
            double d = sc.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException(key + " is not finite");
            return d;
        }
        static double[] Vec(Lexicon l, string key)
        {
            var li = l[new StringValue(key)] as ListValue;
            if (li == null || li.Count != 3) throw new InvalidCastException(key + " is not a list of three numbers");
            var a = new double[3];
            int i = 0;
            foreach (Structure s in li)
            {
                var sc = s as ScalarValue;
                if (sc == null) throw new InvalidCastException(key + " has a non-number");
                a[i] = sc.GetDoubleValue();
                if (double.IsNaN(a[i]) || double.IsInfinity(a[i])) throw new ArithmeticException(key + " is not finite");
                i++;
            }
            return a;
        }
        static bool Has(Lexicon l, string key) { return l.ContainsKey(new StringValue(key)); }
        static bool Flag(Lexicon l, string key)
        {
            if (!Has(l, key)) return false;
            var b = l[new StringValue(key)] as BooleanValue;
            return b != null && b.Value;
        }

        public static NbHandle Solve(Lexicon l)
        {
            var h = new NbHandle();
            try
            {
                var j = new NbJob();
                j.Mu = Num(l, "mu"); j.J2 = Has(l, "j2") ? Num(l, "j2") : 0; j.Rj2 = Has(l, "rj2") ? Num(l, "rj2") : 0;
                j.Pole = Vec(l, "pole"); j.T0 = Num(l, "t0"); j.R0 = Vec(l, "r"); j.V0 = Vec(l, "v"); j.Ut = Num(l, "ut");
                j.Type = (int)Math.Round(Num(l, "type")); j.When = (int)Math.Round(Num(l, "when"));
                j.Rt = Has(l, "rt") ? Num(l, "rt") : 0; j.IncT = Has(l, "inc") ? Num(l, "inc") : 0;
                j.Dvl = Has(l, "dvl") ? Vec(l, "dvl") : new double[3];
                j.Lh = !Has(l, "lh") || Flag(l, "lh"); j.NoDv = Flag(l, "nodv");
                if (j.Mu <= 0 || j.Type < 0 || j.Type > 4) throw new ArgumentException("a bad type or mu");
                if (Bodies != null && j.Ut > j.T0)
                    j.Bodies = Bodies(j.T0, Math.Min(j.Ut, j.T0 + 3 * 86400) + 86400, 600);
                h.Start(j);
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }

        public static void Register(Action<string, ISuffix> add)
        {
            add("NBSOLVE", new OneArgsSuffix<NbHandle, Lexicon>(Solve));
        }
    }
}
