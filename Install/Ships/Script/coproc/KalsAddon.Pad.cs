// THE PAD SEARCH as one asynchronous suffix of ADDONS:KALS (a partial of KalsAddon: RegisterPad is called from its
// constructor). lib_ascent_padcs.ks / ops1q's asc_pad_cs_go hand it everything once:
//     LOCAL h IS ADDONS:KALS:PADSEARCH(LEXICON("c", padcs_consts(), "threads", n, "etl", .., "ard", .., "bgl", TRUE)).
//     ... later passes: IF h:DONE { IF h:ERROR = "" { h:ETL, h:ARD, h:BGL: the results (lexicons) } }
// The input is copied into plain C# here, on the main thread (a bad input: a finished handle with its ERROR); the search runs
// on its own thread with up to h:THREADS workers (below-normal priority) and touches no kOS / Unity object; the result
// lexicons are built on the main thread when kOS reads them. Never throws into kOS.
using System;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterPad()
        {
            AddSuffix("PADSEARCH", new OneArgsSuffix<PadHandle, Lexicon>(PadSearch));
        }

        PadHandle PadSearch(Lexicon l)
        {
            var h = new PadHandle();
            try
            {
                var inp = PadKos.From(l, "in") as KLex;
                if (inp == null) throw new InvalidCastException("the input is not a lexicon");
                h.Start(new PadJob(inp));
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }
    }

    [KOSNomenclature("KALSPadSearch")]
    public class PadHandle : Structure
    {
        volatile bool done;
        PadJob job; string err = "";
        Lexicon etl, ard, bgl;

        public PadHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => done));
            AddSuffix("ERROR", new Suffix<StringValue>(() => done ? err : ""));
            AddSuffix("THREADS", new Suffix<ScalarValue>(() => job == null ? 0 : job.threads));
            AddSuffix("MS", new Suffix<ScalarValue>(() => done && job != null ? job.msTotal : -1));
            AddSuffix("MSETL", new Suffix<ScalarValue>(() => done && job != null ? job.msEtl : -1));
            AddSuffix("MSARD", new Suffix<ScalarValue>(() => done && job != null ? job.msArd : -1));
            AddSuffix("MSBGL", new Suffix<ScalarValue>(() => done && job != null ? job.msBgl : -1));
            AddSuffix("ETL", new Suffix<Lexicon>(() => Res(ref etl, job == null ? null : job.etlRes)));
            AddSuffix("ARD", new Suffix<Lexicon>(() => Res(ref ard, job == null ? null : job.ardRes)));
            AddSuffix("BGL", new Suffix<Lexicon>(() => Res(ref bgl, job == null ? null : job.bglRes)));
        }

        // a result as a kOS lexicon (once; an empty one when that part did not run, before DONE or after an error)
        Lexicon Res(ref Lexicon cache, KLex r)
        {
            if (!done || err != "" || r == null) return new Lexicon();
            if (cache == null)
            {
                try { cache = (Lexicon)PadKos.To(r); }
                catch (Exception ex) { err = "result: " + ex.Message; return new Lexicon(); }
            }
            return cache;
        }

        public void Start(PadJob j)
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

        public override string ToString() { return done ? "KALSPadSearch(" + (err == "" ? "done" : err) + ")" : "KALSPadSearch(running)"; }
    }
}
