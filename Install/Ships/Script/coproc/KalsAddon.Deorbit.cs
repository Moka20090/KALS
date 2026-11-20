// THE DEORBIT PLANNER'S SOLVE as asynchronous suffixes of ADDONS:KALS (a partial of KalsAddon: RegisterDeorbit is
// called from its constructor). lib_dpcs.ks hands a job everything at once and polls the handle:
//     LOCAL h IS ADDONS:KALS:DPSOLVE(LEXICON("c", dpcs_consts(), "g", dpcs_g(), "el", .., "aimLat", .., ...)).   // dpSolveBurn
//     LOCAL h IS ADDONS:KALS:DPARC(LEXICON("c", .., "g", .., "rei", .., "vei", .., "tRot", .., "bank", .., ...)).  // dpArcAt
//     ... later passes: IF h:DONE { IF h:ERROR = "" { h:RES: the result (a lexicon) } }
// The input is copied into plain C# here, on the main thread (a bad input: a finished handle with its ERROR); the job runs on
// its own thread (below-normal priority; the scan on up to RES["threads"] workers) and touches no kOS / Unity object except
// SHIP:BODY's pressure curve (CelestialBody.GetPressure, as kOS's ALTITUDEPRESSURE: the body captured here); the result
// lexicon is built on the main thread when kOS reads it. Never throws into kOS.
using System;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterDeorbit()
        {
            AddSuffix("DPSOLVE", new OneArgsSuffix<DpHandle, Lexicon>(l => DpStart(l, "solve")));
            AddSuffix("DPARC", new OneArgsSuffix<DpHandle, Lexicon>(l => DpStart(l, "arc")));
        }

        DpHandle DpStart(Lexicon l, string kind)
        {
            var h = new DpHandle();
            try
            {
                var inp = PadKos.From(l, "in") as KLex;
                if (inp == null) throw new InvalidCastException("the input is not a lexicon");
                // kOS's ALTITUDEPRESSURE of SHIP:BODY, tabulated here on the main thread (PresTab.cs: the solver's
                // workers calling CelestialBody.GetPressure raced its curve's cache)
                Func<double, double> pres = PresTab.Of(shared.Vessel.mainBody);
                h.Start(new DpJob(inp, kind, pres));
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }
    }

    [KOSNomenclature("KALSDeorbit")]
    public class DpHandle : Structure
    {
        volatile bool done;
        DpJob job; string err = "";
        Lexicon res;

        public DpHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => done));
            AddSuffix("ERROR", new Suffix<StringValue>(() => done ? err : ""));
            AddSuffix("THREADS", new Suffix<ScalarValue>(() => job == null ? 0 : job.threads));
            AddSuffix("MS", new Suffix<ScalarValue>(() => done && job != null ? job.ms : -1));
            AddSuffix("RES", new Suffix<Lexicon>(Res));
        }

        // the result as a kOS lexicon (once; an empty one before DONE or after an error)
        Lexicon Res()
        {
            if (!done || err != "" || job == null || job.res == null) return new Lexicon();
            if (res == null)
            {
                try { res = (Lexicon)PadKos.To(job.res); }
                catch (Exception ex) { err = "result: " + ex.Message; return new Lexicon(); }
            }
            return res;
        }

        public void Start(DpJob j)
        {
            job = j;
            var t = new Thread(() =>
            {
                try { job.Run(); err = job.err; }
                catch (Exception ex) { err = ex.GetType().Name + ": " + ex.Message; }
                done = true;
            });
            t.IsBackground = true;
            t.Priority = ThreadPriority.BelowNormal;
            t.Start();
        }

        public void Fail(string msg) { err = msg; done = true; }

        public override string ToString() { return done ? "KALSDeorbit(" + (err == "" ? "done" : err) + ")" : "KALSDeorbit(running)"; }
    }
}
