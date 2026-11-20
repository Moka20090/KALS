// page 2: the kOS-facing end of the ORBIT / PTG page build in C# (O2Orbit.cs). ADDONS:KALS:O2ORBIT(LEXICON from lib_o2orbin.ks's o2qOrbitIn())
// -> LEXICON("page", the page lexicon (seg, fld: what o2PgNew builds)) on success, or a STRING "error <why>" (a missing key, any exception):
// ops2q.ks then builds the page with its own o2qPgOrbit (the kOS path stays the fallback). O2ORBITERROR = the last error ("" = none),
// O2ORBITN = builds done, O2ORBITMS = the mean ms a build. Nothing here throws into kOS.
using System;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class O2OrbitHost
    {
        public string Error = "";
        public int N;
        double ms;

        public Structure Build(Lexicon l)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                var pg = O2Orbit.Build(O2OrbitIn.FromKos(l));
                var r = new Lexicon();
                r[new StringValue("page")] = pg.ToKos();
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
