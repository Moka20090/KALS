// ADDONS:KALS:PEG8SOLVE(lexicon) -> LEXICON(ok, why, ...) of ONE PEG 8 shot (PrShoot.cs), SYNCHRONOUS: the shot is a few 3 x 3 Newton steps on a
// fixed-step RK4 coast (0.1 - 2 ms for an aim an orbit ahead, 15 ms for a day), so it runs on kOS's own thread in the call; the third bodies are sampled here
// by NbReg.Bodies (as NBSOLVE's). Never throws into kOS: a bad input is ok FALSE with its why. The input is plain kOS numbers, LIST(x, y, z) for every vector:
//   mu, j2, rj2, pole     the main body's GM, its J2 and the reference radius (0 = a point mass), its north (unit)
//   t0, r, v              the state now (UT, body-relative)
//   tc                    the impulse UT (>= t0): the burn's centre before ignition, t0 in the burn
//   dvg                   the planned dV as an inertial vector at tc (the guess)
//   at, ar                the aim: a UT and a position (Principia's planned position at the next burn's ignition) ...
//   pt, pr, pv            ... or the plan's state after the burn (UT pt) and at (0 = half an osculating period after pt): the aim = its n-body coast to at
// RESULT (ok TRUE): vreq (the velocity to be at after the burn, at tc), dv (the VGO: vreq - the coast's velocity at tc), rc / vc (the n-body coast's state at tc),
// aimr, aimt, miss0 (m: the planned dV as an impulse misses the aim by), misscut (m: cut now), resid (m: the shot's own), it, ms, evals.
// ok FALSE: why (the Err text), and resid / it / dv when the shot ran.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public static class ShootReg
    {
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
        static ListValue L3(double[] a)
        {
            var l = new ListValue();
            for (int i = 0; i < 3; i++) l.Add(new ScalarDoubleValue(a[i]));
            return l;
        }
        static void Put(Lexicon k, string key, Structure v) { k[new StringValue(key)] = v; }

        public static Lexicon Solve(Lexicon l)
        {
            var k = new Lexicon();
            Put(k, "ok", BooleanValue.False); Put(k, "why", new StringValue(""));
            try
            {
                var j = new ShootJob();
                j.Mu = Num(l, "mu"); j.J2 = Has(l, "j2") ? Num(l, "j2") : 0; j.Rj2 = Has(l, "rj2") ? Num(l, "rj2") : 0;
                j.Pole = Vec(l, "pole"); j.T0 = Num(l, "t0"); j.R0 = Vec(l, "r"); j.V0 = Vec(l, "v"); j.Tc = Num(l, "tc");
                j.Dvg = Has(l, "dvg") ? Vec(l, "dvg") : new double[3];
                j.At = Has(l, "at") ? Num(l, "at") : 0;
                if (Has(l, "ar")) j.Ar = Vec(l, "ar");
                if (Has(l, "pr")) { j.Pr = Vec(l, "pr"); j.Pv = Vec(l, "pv"); j.Pt = Num(l, "pt"); }
                if (j.Mu <= 0) throw new ArgumentException("a bad mu");
                if (j.Ar != null && !(j.At > 0)) throw new ArgumentException("an aim position needs its time");
                double ta = ShootJob.AimTime(j.Mu, j.At, j.Pt, j.Pr, j.Pv);
                if (NbReg.Bodies != null && ta > j.T0)
                    j.Bodies = NbReg.Bodies(j.T0, Math.Min(ta, j.T0 + 3 * 86400) + 86400, 600);
                bool ok = j.Run();
                Put(k, "ms", new ScalarDoubleValue(j.Ms)); Put(k, "evals", new ScalarDoubleValue(j.Evals));
                Put(k, "resid", new ScalarDoubleValue(j.Resid)); Put(k, "it", new ScalarIntValue(j.Iters));
                if (j.HaveMiss) { Put(k, "miss0", new ScalarDoubleValue(j.Miss0)); Put(k, "misscut", new ScalarDoubleValue(j.MissCut)); }
                if (!ok) { Put(k, "why", new StringValue(j.Err == "" ? "SHOT FAILED" : j.Err)); return k; }
                Put(k, "vreq", L3(j.Vreq)); Put(k, "dv", L3(j.Dv)); Put(k, "rc", L3(j.Rc)); Put(k, "vc", L3(j.Vc));
                Put(k, "aimr", L3(j.AimR)); Put(k, "aimt", new ScalarDoubleValue(j.AimT));
                Put(k, "miss0", new ScalarDoubleValue(j.Miss0)); Put(k, "misscut", new ScalarDoubleValue(j.MissCut));
                Put(k, "ok", BooleanValue.True);
            }
            catch (Exception ex) { Put(k, "why", new StringValue(ex.GetType().Name + ": " + ex.Message)); }
            return k;
        }

        public static void Register(Action<string, ISuffix> add)
        {
            add("PEG8SOLVE", new OneArgsSuffix<Lexicon, Lexicon>(Solve));
        }
    }
}
