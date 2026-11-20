// the kOS side of the entry reference-family build (coproc/Fam.cs): the suffixes (FamKos.Register, called by
// KalsAddon.Fam.cs's RegisterFam), kOS values in and out (FamKos), and the handle FAMSTART returns (FamHandle).
//     LOCAL h IS ADDONS:KALS:FAMSTART(LEXICON("rv", rv, "vv", vv, "tal", LIST() or LIST(TAL_A0, TAL_VALPD1, TAL_VALPD2),
//                                             "R", EPR_R, "MU", EPR_MU, ... every EPR_* the build reads, named without EPR_)).
//     -> a handle at once: the coast is done (h:R0, h:V0, h:TCOAST = EPR_FAM_R0 / V0 / TCOAST), the eight members run on
//        worker threads, one each. Poll h:DONE (h:PREFIX = the members done in build order), then h:MEMBER(k) is
//        eprFamStoreMember's LIST(bank, vs, ds, ss, rg, bk, alts), h:TRACE(k) the member's EPR_TR_* (V, D, S, A, ARC, BK),
//        h:END(k) its end state (the integrator's globals). h:ERROR <> "": kOS builds it itself.
// The pressure: SHIP:BODY's own CelestialBody.GetPressure, tabulated on the main thread (PresTab.cs) for the workers (kOS's ALTITUDEPRESSURE: the same call
// times KpaToAtm; KalsAddon.Fam.cs hands the body over), or a "pres" curve (sqa_curve keys, kPa) when the lexicon has one
// (the offline checks). Nothing throws into kOS: FAMSTART's failures come back as a handle with ERROR set.
// KOSVM (the offline kOS VM's build): kOS's vector is kosrunv's Vec (vec.cs), as kOS.dll
// is absent there; in the game it is kOS.Suffixed.Vector. Nothing else differs.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
#if KOSVM
using KVec = global::Vec;
#else
using KVec = kOS.Suffixed.Vector;
#endif

namespace KalsCoproc
{
    // the kOS side of the build: kOS values in, kOS values out (main thread only)
    public static class FamKos
    {
        static string famErr = "";

        // the suffixes, as KalsAddon.Fam.cs registers them (add = the Structure's AddSuffix); bodyPres: called on the main
        // thread at FAMSTART when the lexicon has no "pres" curve, returns the pressure (atm) of SHIP:BODY at an altitude
        public static void Register(Action<string, ISuffix> add, Func<Func<double, double>> bodyPres)
        {
            add("FAMSTART", new OneArgsSuffix<FamHandle, Lexicon>(l => FamStart(l, bodyPres)));
            add("FAMERROR", new Suffix<StringValue>(() => famErr));
        }

        static FamHandle FamStart(Lexicon l, Func<Func<double, double>> bodyPres)
        {
            var h = new FamHandle();
            try
            {
                Func<double, double> pres = null;
                if (!l.ContainsKey(new StringValue("pres"))) pres = bodyPres();     // SHIP:BODY, captured on the main thread
                Start(h, l, pres, true);
                famErr = "";
            }
            catch (Exception ex) { famErr = ex.GetType().Name + ": " + ex.Message; h.Fail(famErr); }
            return h;
        }

        static Structure Get(Lexicon l, string k)
        {
            Structure s;
            if (!l.TryGetValue(new StringValue(k), out s)) throw new KeyNotFoundException("FAMSTART: no key \"" + k + "\"");
            return s;
        }
        static double Num(Structure s, string k)
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException("FAMSTART: " + k + " is not a number");
            return sv.GetDoubleValue();
        }
        static Vec3 Vec(Structure s, string k)
        {
            var v = s as KVec;
            if (v == null) throw new InvalidCastException("FAMSTART: " + k + " is not a vector");
            return new Vec3(v.X, v.Y, v.Z);
        }
        static double[] Row(Structure s, string k)
        {
            var li = s as ListValue;
            if (li == null) throw new InvalidCastException("FAMSTART: " + k + " is not a list");
            var a = new double[li.Count];
            for (int i = 0; i < li.Count; i++) a[i] = Num(li[i], k);
            return a;
        }
        static double[][] Table(Structure s, string k)
        {
            var li = s as ListValue;
            if (li == null) throw new InvalidCastException("FAMSTART: " + k + " is not a list");
            var a = new double[li.Count][];
            for (int i = 0; i < li.Count; i++) a[i] = Row(li[i], k);
            if (a.Length == 0) throw new ArgumentException("FAMSTART: " + k + " is empty");
            return a;
        }

        public static void Start(FamHandle h, Lexicon l, Func<double, double> pres, bool threaded)
        {
            var c = new FamConsts();
            foreach (var n in FamConsts.Names())
            {
                var s = Get(l, n);
                var f = typeof(FamConsts).GetField(n);
                if (f.FieldType == typeof(double)) c.Set(n, Num(s, n));
                else if (f.FieldType == typeof(bool))
                {
                    var b = s as BooleanValue;
                    if (b == null) throw new InvalidCastException("FAMSTART: " + n + " is not a boolean");
                    c.Set(n, b.Value);
                }
                else if (f.FieldType == typeof(Vec3)) c.Set(n, Vec(s, n));
                else if (f.FieldType == typeof(double[])) c.Set(n, Row(s, n));
                else c.Set(n, Table(s, n));
            }
            var tal = Row(Get(l, "tal"), "tal");
            if (tal.Length == 3) { c.TAL = true; c.TAL_A0 = tal[0]; c.TAL_VALPD1 = tal[1]; c.TAL_VALPD2 = tal[2]; }
            else if (tal.Length != 0) throw new ArgumentException("FAMSTART: tal wants LIST() or LIST(TAL_A0, TAL_VALPD1, TAL_VALPD2)");
            if (l.ContainsKey(new StringValue("pres")))
            {
                var keys = Table(Get(l, "pres"), "pres");
                pres = x => FamConsts.SqaCurve(keys, x) * 0.0098692326671601278;
            }
            if (pres == null) throw new ArgumentException("FAMSTART: no pressure");
            c.AltPres = pres;
            var banks = (ListValue)Get(l, "FAM_BANKS");
            h.Banks = new Structure[banks.Count];
            for (int i = 0; i < banks.Count; i++) h.Banks[i] = banks[i];
            var job = new FamJob(c);
            h.Job = job;
            job.Start(Vec(Get(l, "rv"), "rv"), Vec(Get(l, "vv"), "vv"), threaded);
        }

        static ListValue L(double[] a)
        {
            var li = new ListValue();
            foreach (var x in a) li.Add(ScalarValue.Create(x));
            return li;
        }
        static ListValue L(List<double> a) { return L(a.ToArray()); }
        public static KVec V(Vec3 v) { return new KVec(v.X, v.Y, v.Z); }

        public static ListValue Member(FamHandle h, int k)
        {
            var m = h.Job.M[k];
            if (!m.Done || m.Error != "") throw new InvalidOperationException("member " + k + " is not done");
            var li = new ListValue();
            li.Add(h.Banks[(int)h.Job.C.FAM_ORDER[k]]);
            li.Add(L(m.VS)); li.Add(L(m.DS)); li.Add(L(m.SS)); li.Add(L(m.RG)); li.Add(L(m.BK)); li.Add(L(m.ALTS));
            return li;
        }

        public static ListValue Trace(FamHandle h, int k)
        {
            var m = h.Job.M[k];
            if (!m.Done) throw new InvalidOperationException("member " + k + " is not done");
            var li = new ListValue();
            li.Add(L(m.TR_V)); li.Add(L(m.TR_D)); li.Add(L(m.TR_S)); li.Add(L(m.TR_A)); li.Add(L(m.TR_ARC)); li.Add(L(m.TR_BK));
            return li;
        }

        public static Lexicon End(FamHandle h, int k)
        {
            var m = h.Job.M[k];
            if (!m.Done) throw new InvalidOperationException("member " + k + " is not done");
            var e = new Lexicon();
            Action<string, Structure> a = (n, s) => e.Add(new StringValue(n), s);
            a("IR", V(m.IR)); a("IV", V(m.IV)); a("PR", V(m.PR)); a("PV", V(m.PV));
            a("IT", ScalarValue.Create(m.IT)); a("IARC", ScalarValue.Create(m.IARC)); a("IBK", h.Banks[(int)h.Job.C.FAM_ORDER[k]]);
            a("PT", ScalarValue.Create(m.PT)); a("PA", ScalarValue.Create(m.PA)); a("PVR", ScalarValue.Create(m.PVR));
            a("PARC", ScalarValue.Create(m.PARC)); a("FAM_ARC", ScalarValue.Create(m.FAM_ARC));
            a("BANK_NOW", ScalarValue.Create(m.BANK_NOW)); a("BANK_PRE", ScalarValue.Create(m.BANK_PRE));
            a("MEMBER_BANK", h.Banks[(int)h.Job.C.FAM_ORDER[k]]); a("TRACE_K", ScalarValue.Create(m.TRACE_K));
            a("TERM_ALT", ScalarValue.Create(m.TERM_ALT)); a("TERM_VEL", ScalarValue.Create(m.TERM_VEL));
            a("TERM_WHY", new StringValue(m.TERM_WHY)); a("HINT_RHO", ScalarValue.Create(m.HINT_RHO));
            a("TAL_FAM_VI", ScalarValue.Create(m.TAL_FAM_VI)); a("STEPS", ScalarValue.Create((double)m.Steps));
            a("IOK", new BooleanValue(m.IOK)); a("IDONE", new BooleanValue(m.IDONE));
            a("HAVEPREV", new BooleanValue(m.HAVEPREV)); a("STARTED", new BooleanValue(m.STARTED));
            return e;
        }

    }

    [kOS.Safe.Utilities.KOSNomenclature("KALSFamJob")]
    public class FamHandle : Structure
    {
        public FamJob Job;
        public Structure[] Banks;
        string err = "";

        public FamHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => err != "" || (Job != null && Job.Done)));
            AddSuffix("OK", new Suffix<BooleanValue>(() => err == "" && Job != null && Job.Error == ""));
            AddSuffix("ERROR", new Suffix<StringValue>(() => err != "" ? err : (Job == null ? "no job" : Job.Error)));
            AddSuffix("PREFIX", new Suffix<ScalarValue>(() => Job == null ? 0 : Job.Prefix));
            AddSuffix("N", new Suffix<ScalarValue>(() => Job == null || Job.M == null ? 0 : Job.M.Length));
            AddSuffix("R0", new Suffix<KVec>(() => Job == null ? new KVec(0, 0, 0) : FamKos.V(Job.R0)));
            AddSuffix("V0", new Suffix<KVec>(() => Job == null ? new KVec(0, 0, 0) : FamKos.V(Job.V0)));
            AddSuffix("TCOAST", new Suffix<ScalarValue>(() => Job == null ? 0 : Job.TCOAST));
            AddSuffix("MS", new Suffix<ScalarValue>(() => Job == null ? -1 : Job.WallMs));
            AddSuffix("MEMBER", new OneArgsSuffix<ListValue, ScalarValue>(k => { try { return FamKos.Member(this, k.GetIntValue()); } catch (Exception) { return new ListValue(); } }));
            AddSuffix("TRACE", new OneArgsSuffix<ListValue, ScalarValue>(k => { try { return FamKos.Trace(this, k.GetIntValue()); } catch (Exception) { return new ListValue(); } }));
            AddSuffix("END", new OneArgsSuffix<Lexicon, ScalarValue>(k => { try { return FamKos.End(this, k.GetIntValue()); } catch (Exception) { return new Lexicon(); } }));
        }

        public void Fail(string msg) { err = msg == "" ? "error" : msg; }

        public override string ToString()
        {
            if (err != "") return "KALSFamJob(error " + err + ")";
            return Job != null && Job.Done ? "KALSFamJob(done)" : "KALSFamJob(running)";
        }
    }
}
