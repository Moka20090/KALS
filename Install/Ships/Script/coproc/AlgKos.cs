// the bridge between kOS and the C# A/L guidance (Alg.cs) and pitch loop (Fcs.cs), for KalsAddon.Al.cs's suffixes.
// Every call is SYNCHRONOUS (no thread: one pass per call on the main thread, as kOS's own functions). kOS's lexicons
// are read into plain Lex values (ags and nav whole; tg / fc only the keys the pitch loop reads), the C# runs on the
// copies, and only then are the keys it changed written back into kOS's lexicons (the same objects: lib_land, the log,
// the HUD read them as before). Every value is converted (and checked finite) BEFORE the first write, for all the
// lexicons a call touches: a failure anywhere (a key missing, a NaN, a bug) throws before any write -- the lexicons are
// untouched and the caller flies kOS's own function. Numbers keep kOS's type: a key kOS held as an integer stays one
// while it is whole (p_mode, f_mode, sb_mode, the counters, nz_sat, the binds). ag["ret_log"] (a kOS LIST) gets the
// retract entries alg_speedbrake would :ADD, as new kOS lexicons, after the write-back.
// AlCoproc holds the C# state (the constants) and the suffix bodies, none of which throws into kOS: a failure comes back
// as an error string or, for the calls that return a number, AlCoproc.FAIL (-99999) with ALERROR saying why. Register()
// adds the suffixes to any kOS Structure (KalsAddon's RegisterAl; the offline VM's test host).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public static class AlgKos
    {
        // ---------------------------------------------------------------- kOS -> C#
        public static object FromKos(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) { if (sv.IsInt) return sv.GetIntValue(); return sv.GetDoubleValue(); }
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            var str = s as StringValue;
            if (str != null) return str.ToString();
            return s;                                   // opaque (a list, a lexicon, ...): carried, never read
        }

        public static Lex All(Lexicon l)                // every key (values as FromKos)
        {
            var d = new Lex();
            foreach (KeyValuePair<Structure, Structure> kv in l) d[kv.Key.ToString()] = FromKos(kv.Value);
            return d;
        }

        public static Lex Pick(Lexicon l, string[] keys)   // only these keys, those the lexicon has (HASKEY kept)
        {
            var d = new Lex();
            foreach (string k in keys)
            {
                Structure v;
                if (l.TryGetValue(new StringValue(k), out v)) d[k] = FromKos(v);
            }
            return d;
        }

        public static double Num(Structure s)           // a kOS number argument
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
            return sv.GetDoubleValue();
        }

        public static double Finite(double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("not a finite number");
            return d;
        }

        // ---------------------------------------------------------------- C# -> kOS
        static Structure ToKos(object v, Structure old)
        {
            if (v is int) return new ScalarIntValue((int)v);
            if (v is double)
            {
                double d = Finite((double)v);
                var os = old as ScalarValue;
                if (os != null && os.IsInt && d == Math.Floor(d) && Math.Abs(d) < 2147483647.0) return new ScalarIntValue((int)d);
                return new ScalarDoubleValue(d);
            }
            if (v is bool) return new BooleanValue((bool)v);
            if (v is string) return new StringValue((string)v);
            var lx = v as Lex;
            if (lx != null)
            {
                var l = new Lexicon();
                foreach (var kv in lx)
                {
                    if (kv.Value is Structure) l[new StringValue(kv.Key)] = (Structure)kv.Value;
                    else l[new StringValue(kv.Key)] = ToKos(kv.Value, null);
                }
                return l;
            }
            throw new InvalidCastException("no kOS value for " + (v == null ? "null" : v.GetType().Name));
        }

        static bool Same(object a, object b)
        {
            if (a is double && b is double)             // bit for bit (a -0 is a change)
                return BitConverter.DoubleToInt64Bits((double)a) == BitConverter.DoubleToInt64Bits((double)b);
            if ((a is int || a is double) && (b is int || b is double)) return Lex.Num(a) == Lex.Num(b);
            if (a is string && b is string) return string.Equals((string)a, (string)b, StringComparison.Ordinal);
            if (a is bool && b is bool) return (bool)a == (bool)b;
            return ReferenceEquals(a, b);
        }

        // the writes a pass makes into one kOS lexicon, every value built (and checked) before Commit writes any
        public class Pending
        {
            Lexicon dst; List<StringValue> keys = new List<StringValue>(); List<Structure> vals = new List<Structure>();
            public Pending(Lexicon dst, Lex before, Lex after)
            {
                this.dst = dst;
                foreach (var kv in after)
                {
                    if (kv.Value is Structure) continue;
                    object b;
                    bool had = before.TryGetValue(kv.Key, out b);
                    if (had && Same(b, kv.Value)) continue;
                    var key = new StringValue(kv.Key);
                    Structure old = null;
                    if (had) dst.TryGetValue(key, out old);
                    keys.Add(key);
                    vals.Add(ToKos(kv.Value, old));
                }
            }
            public void Commit() { for (int i = 0; i < keys.Count; i++) dst[keys[i]] = vals[i]; }
            public int Count { get { return keys.Count; } }
        }

        // ---------------------------------------------------------------- the calls
        static readonly string[] FC_STEP = { "bank", "bank_rate" };
        static readonly string[] TG_PITCH = { "nz_total", "nzl_trim", "qbref", "alpha_rl", "alpha_rl_bind", "nz_sat", "alpha_ff", "alpha_lim_hi" };
        static readonly string[] TG_WINDOW = { "nz_total", "nzl_trim", "alpha_rl_bind", "nz_sat" };
        static readonly string[] TG_SEED = { "nzl_trim", "alpha_rl" };
        static readonly string[] ST_PITCH = { "qbar", "mach" };
        static readonly string[] FC_ALPHA = { "trim", "alpha_rl", "nz_sat", "alpha_ff", "rl_bind" };
        static readonly string[] FC_TRIM = { "trim", "nz_sat", "rl_bind", "nz_err" };

        static void AppendRetLog(Alg A, Lexicon ags, List<Lexicon> adds)
        {
            if (adds.Count == 0) return;
            Structure rl;
            if (!ags.TryGetValue(new StringValue("ret_log"), out rl)) return;
            var li = rl as ListValue;
            if (li == null) return;
            foreach (var x in adds) li.Add(x);
        }

        static List<Lexicon> RetLexicons(Alg A)         // built before any write (ToKos checks every number)
        {
            var o = new List<Lexicon>();
            foreach (var e in A.RetAdds) o.Add((Lexicon)ToKos(e, null));
            return o;
        }

        // one A/L pass: alg_cycle(ags, nav), then lib_land's bank slew on fc (taemg_roll_lim at nav's Mach,
        // taemg_bank_slew over AL_DT toward ags["phic_al"]) -> alg_nz_total(ags["nzc"], nav["gamma"], fc["bank"])
        public static double Step(Alg A, Taemg T, Lexicon ags, Lexicon nav, Lexicon fc)
        {
            A.RetAdds.Clear();
            Lex before = All(ags);
            Lex work = new Lex(before);
            Lex nv = All(nav);
            Lex f0 = Pick(fc, FC_STEP);
            Lex f1 = new Lex(f0);
            A.alg_cycle(work, nv);
            double rate, accel;
            T.taemg_roll_lim(nv.N("mach"), out rate, out accel);
            double bank, brate;
            Taemg.taemg_bank_slew(f1.N("bank"), work.N("phic_al"), f1.N("bank_rate"), A.AL_DT, rate, accel, out bank, out brate);
            f1["bank"] = bank;
            f1["bank_rate"] = brate;
            double nzt = Finite(A.alg_nz_total(work.N("nzc"), nv.N("gamma"), f1.N("bank")));
            var pa = new Pending(ags, before, work);
            var pf = new Pending(fc, f0, f1);
            var rl = RetLexicons(A);
            pa.Commit(); pf.Commit(); AppendRetLog(A, ags, rl);
            A.RetAdds.Clear();
            return nzt;
        }

        public static void Cycle(Alg A, Lexicon ags, Lexicon nav)   // alg_cycle alone
        {
            A.RetAdds.Clear();
            Lex before = All(ags);
            Lex work = new Lex(before);
            A.alg_cycle(work, All(nav));
            var pa = new Pending(ags, before, work);
            var rl = RetLexicons(A);
            pa.Commit(); AppendRetLog(A, ags, rl);
            A.RetAdds.Clear();
        }

        // TAEM's pitch update: cmd = MIN(fcs_alpha_cmd(tg, st), ceiling); fcs_alpha_slew(tg, cmd, dt,
        // taemg_alpha_rate(st["mach"])) -> cmd (the slewed alpha is tg["alpha_rl"])
        public static double Taem(Fcs F, Taemg T, Lexicon tg, Lexicon st, double dt, double ceiling)
        {
            Lex t0 = Pick(tg, TG_PITCH);
            Lex t1 = new Lex(t0);
            Lex s = Pick(st, ST_PITCH);
            double cmd = F.fcs_alpha_cmd(t1, s);
            if (ceiling < 1e8) cmd = Math.Min(cmd, ceiling);   // lib_land: the bailout's ceiling (1E9: none)
            F.fcs_alpha_slew(t1, cmd, dt, T.taemg_alpha_rate(s.N("mach")));
            Finite(cmd);
            var p = new Pending(tg, t0, t1);
            p.Commit();
            return cmd;
        }

        public static void Window(Fcs F, Lexicon tg, double nz_meas, double qbar)   // fcs_window_end
        {
            Lex t0 = Pick(tg, TG_WINDOW);
            Lex t1 = new Lex(t0);
            F.fcs_window_end(t1, nz_meas, qbar);
            var p = new Pending(tg, t0, t1);
            p.Commit();
        }

        public static void Seed(Fcs F, Lexicon tg, double a_ent, double nz0, double qbar, double mach)   // fcs_trim_seed
        {
            Lex t0 = Pick(tg, TG_SEED);
            Lex t1 = new Lex(t0);
            F.fcs_trim_seed(t1, a_ent, nz0, qbar, mach);
            var p = new Pending(tg, t0, t1);
            p.Commit();
        }

        // A/L's pitch update: fcs_al_alpha(fc, nz_total, qbar, mach, dt, taemg_alpha_rate(mach), amax) -> the alpha
        public static double AlAlpha(Fcs F, Taemg T, Lexicon fc, double nz_total, double qbar, double mach, double dt, double amax)
        {
            Lex f0 = Pick(fc, FC_ALPHA);
            Lex f1 = new Lex(f0);
            double a = Finite(F.fcs_al_alpha(f1, nz_total, qbar, mach, dt, T.taemg_alpha_rate(mach), amax));
            var p = new Pending(fc, f0, f1);
            p.Commit();
            return a;
        }

        public static void AlTrim(Fcs F, Lexicon fc, double nz_cmd, double nz_meas, double qbar, double dt)   // fcs_al_trim
        {
            Lex f0 = Pick(fc, FC_TRIM);
            Lex f1 = new Lex(f0);
            F.fcs_al_trim(f1, nz_cmd, nz_meas, qbar, dt);
            var p = new Pending(fc, f0, f1);
            p.Commit();
        }
    }

    // ---------------------------------------------------------------- the state and the suffix bodies
    public class AlCoproc
    {
        public const double FAIL = -99999;
        public Alg A; public Fcs F; public Taemg T;
        public string Err = "";
        public bool TestBreak = false;                  // the offline VM's test host only: the next call throws
        public double LastMs = 0;                       // the last call's time (ALMS), ms
        System.Diagnostics.Stopwatch sw = new System.Diagnostics.Stopwatch();

        void Brk() { if (TestBreak) { TestBreak = false; throw new InvalidOperationException("TestBreak (the VM's forced failure)"); } }
        void Need() { if (A == null) throw new InvalidOperationException("ALSETUP first (" + Err + ")"); }
        void T0() { sw.Reset(); sw.Start(); }
        void T1() { sw.Stop(); LastMs = sw.Elapsed.TotalMilliseconds; }
        string Fail(Exception ex) { T1(); Err = ex.GetType().Name + ": " + ex.Message; return "error " + Err; }

        // ALSETUP(the text of lib/alg_const.ks, of lib/taemg_const.ks, of lib/solq_atm_data.ks) -> TRUE when read
        public BooleanValue Setup(StringValue alConst, StringValue tgConst, StringValue atm)
        {
            try
            {
                var ca = KsConst.Parse(alConst.ToString());
                var ct = KsConst.Parse(tgConst.ToString());
                var cs = KsConst.Parse(atm.ToString());
                var tc = new Dictionary<string, object>(ct, StringComparer.OrdinalIgnoreCase);
                foreach (var kv in cs) tc[kv.Key] = kv.Value;
                var ac = new Dictionary<string, object>(ca, StringComparer.OrdinalIgnoreCase);
                foreach (var kv in ct) if (!ac.ContainsKey(kv.Key)) ac[kv.Key] = kv.Value;
                var t = new Taemg(tc); var f = new Fcs(ct); var a = new Alg(ac);
                T = t; F = f; A = a;
                Err = "";
                return BooleanValue.True;
            }
            catch (Exception ex) { A = null; F = null; T = null; Err = ex.GetType().Name + ": " + ex.Message; return BooleanValue.False; }
        }

        public ScalarValue Step(Lexicon ags, Lexicon nav, Lexicon fc)
        {
            try { T0(); Need(); Brk(); double r = AlgKos.Step(A, T, ags, nav, fc); T1(); return new ScalarDoubleValue(r); }
            catch (Exception ex) { Fail(ex); return new ScalarDoubleValue(FAIL); }
        }

        public StringValue Cycle(Lexicon ags, Lexicon nav)
        {
            try { T0(); Need(); Brk(); AlgKos.Cycle(A, ags, nav); T1(); return new StringValue(""); }
            catch (Exception ex) { return new StringValue(Fail(ex)); }
        }

        // FCTAEM(tg, st, dt, ceiling) -> the alpha command (before the slew; the slewed one is tg["alpha_rl"])
        public ScalarValue FcTaem(params Structure[] a)
        {
            try
            {
                T0(); Need(); Brk(); Args(a, 4, "FCTAEM(tg, st, dt, ceiling)");
                double r = AlgKos.Taem(F, T, (Lexicon)a[0], (Lexicon)a[1], AlgKos.Num(a[2]), AlgKos.Num(a[3]));
                T1(); return new ScalarDoubleValue(r);
            }
            catch (Exception ex) { Fail(ex); return new ScalarDoubleValue(FAIL); }
        }

        public StringValue FcWindow(Lexicon tg, ScalarValue nz_meas, ScalarValue qbar)
        {
            try { T0(); Need(); Brk(); AlgKos.Window(F, tg, nz_meas.GetDoubleValue(), qbar.GetDoubleValue()); T1(); return new StringValue(""); }
            catch (Exception ex) { return new StringValue(Fail(ex)); }
        }

        // FCSEED(tg, a_ent, nz0, qbar, mach)
        public StringValue FcSeed(params Structure[] a)
        {
            try
            {
                T0(); Need(); Brk(); Args(a, 5, "FCSEED(tg, a_ent, nz0, qbar, mach)");
                AlgKos.Seed(F, (Lexicon)a[0], AlgKos.Num(a[1]), AlgKos.Num(a[2]), AlgKos.Num(a[3]), AlgKos.Num(a[4]));
                T1(); return new StringValue("");
            }
            catch (Exception ex) { return new StringValue(Fail(ex)); }
        }

        // FCALALPHA(fc, nz_total, qbar, mach, dt, amax) -> the alpha (= fc["alpha_rl"])
        public ScalarValue FcAlAlpha(params Structure[] a)
        {
            try
            {
                T0(); Need(); Brk(); Args(a, 6, "FCALALPHA(fc, nz_total, qbar, mach, dt, amax)");
                double r = AlgKos.AlAlpha(F, T, (Lexicon)a[0], AlgKos.Num(a[1]), AlgKos.Num(a[2]), AlgKos.Num(a[3]),
                                          AlgKos.Num(a[4]), AlgKos.Num(a[5]));
                T1(); return new ScalarDoubleValue(r);
            }
            catch (Exception ex) { Fail(ex); return new ScalarDoubleValue(FAIL); }
        }

        // FCALTRIM(fc, nz_cmd, nz_meas, qbar, dt)
        public StringValue FcAlTrim(params Structure[] a)
        {
            try
            {
                T0(); Need(); Brk(); Args(a, 5, "FCALTRIM(fc, nz_cmd, nz_meas, qbar, dt)");
                AlgKos.AlTrim(F, (Lexicon)a[0], AlgKos.Num(a[1]), AlgKos.Num(a[2]), AlgKos.Num(a[3]), AlgKos.Num(a[4]));
                T1(); return new StringValue("");
            }
            catch (Exception ex) { return new StringValue(Fail(ex)); }
        }

        // FCALPHAFF(nz, qbar, mach) -> fcs_alpha_ff(...)[0]
        public ScalarValue FcAlphaFf(ScalarValue nz, ScalarValue qbar, ScalarValue mach)
        {
            try
            {
                T0(); Need(); Brk();
                double r = AlgKos.Finite(F.fcs_alpha_ff(nz.GetDoubleValue(), qbar.GetDoubleValue(), mach.GetDoubleValue()));
                T1(); return new ScalarDoubleValue(r);
            }
            catch (Exception ex) { Fail(ex); return new ScalarDoubleValue(FAIL); }
        }

        static void Args(Structure[] a, int n, string usage)
        {
            if (a == null || a.Length != n) throw new ArgumentException(usage + ": " + (a == null ? 0 : a.Length) + " arguments");
        }

        // the suffixes, onto any kOS Structure (add = its AddSuffix)
        public static void Register(AlCoproc c, Action<string, ISuffix> add)
        {
            add("ALSETUP", new ThreeArgsSuffix<BooleanValue, StringValue, StringValue, StringValue>(c.Setup));
            add("ALREADY", new Suffix<BooleanValue>(() => c.A != null));
            add("ALERROR", new Suffix<StringValue>(() => c.Err));
            add("ALMS", new Suffix<ScalarValue>(() => c.LastMs));
            add("ALSTEP", new ThreeArgsSuffix<ScalarValue, Lexicon, Lexicon, Lexicon>(c.Step));
            add("ALCYCLE", new TwoArgsSuffix<StringValue, Lexicon, Lexicon>(c.Cycle));
            add("FCTAEM", new VarArgsSuffix<ScalarValue, Structure>(c.FcTaem));
            add("FCWINDOW", new ThreeArgsSuffix<StringValue, Lexicon, ScalarValue, ScalarValue>(c.FcWindow));
            add("FCSEED", new VarArgsSuffix<StringValue, Structure>(c.FcSeed));
            add("FCALALPHA", new VarArgsSuffix<ScalarValue, Structure>(c.FcAlAlpha));
            add("FCALTRIM", new VarArgsSuffix<StringValue, Structure>(c.FcAlTrim));
            add("FCALPHAFF", new ThreeArgsSuffix<ScalarValue, ScalarValue, ScalarValue, ScalarValue>(c.FcAlphaFf));
        }
    }
}
