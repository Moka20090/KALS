// The kOS-facing end of the MNVR page build in C# (O2Mnvr.cs). ADDONS:KALS:O2MNVR(LEXICON from lib_o2mnvr.ks's o2qMnvrIn())
// -> LEXICON("page", the page lexicon (seg, fld: what o2PgNew builds), "dv", LIST(total, gained) or LIST()) on success, or a STRING
// "error <why>" (a missing key, any exception): ops2q.ks then builds the page with its own o2qPgMnvr (the kOS path stays the fallback).
// O2MNVRERROR = the last error ("" = none), O2MNVRN = builds done, O2MNVRMS = the mean ms a build (a Stopwatch round the C# part only).
// Nothing here throws into kOS. Pure kOS.Safe + O2Mnvr.cs / O2Page.cs, so tests/o2mnvr_offline compiles it too.
using System;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class O2MnvrHost
    {
        public string Error = "";
        public int N;
        double ms;

        public Structure Build(Lexicon l)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                var inp = O2MnvrIn.FromKos(l);
                double[] bar;
                var pg = O2Mnvr.Build(inp, out bar);
                var r = new Lexicon();
                r[new StringValue("page")] = pg.ToKos();
                var dv = new ListValue();
                if (bar != null) { dv.Add(ScalarValue.Create(bar[0])); dv.Add(ScalarValue.Create(bar[1])); }
                r[new StringValue("dv")] = dv;
                N++;
                ms += sw.Elapsed.TotalMilliseconds;
                return r;
            }
            catch (Exception e)
            {
                Error = e.GetType().Name + ": " + e.Message;
                return new StringValue("error " + Error);
            }
        }

        public string Ms() { return N == 0 ? "-" : (ms / N).ToString("F4") + " ms/call over " + N; }
    }
}
