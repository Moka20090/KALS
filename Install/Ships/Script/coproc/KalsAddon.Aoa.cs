// THE AOA SOLVE as one asynchronous suffix of ADDONS:KALS (a partial of KalsAddon: RegisterAoa is called from its
// constructor). lib_aoa.ks's aoaSolve hands it everything once:
//     LOCAL h IS ADDONS:KALS:AOASOLVE(aoaCsIn(rv, vv, tGeo, s, dvMax)).
//     ... UNTIL h:DONE { WAIT 0. }   IF h:OK { h:RESULT: the solve (a lexicon) } ELSE { h:ERROR, kOS solves }
// The input is copied on the main thread; the solve runs on its own thread with up to h:THREADS workers (below normal priority)
// and touches no kOS / Unity object; RESULT is built on the main thread when kOS reads it. Never throws into kOS.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterAoa()
        {
            AddSuffix("AOASOLVE", new OneArgsSuffix<AoaHandle, Lexicon>(AoaSolveStart));
        }

        AoaHandle AoaSolveStart(Lexicon l)
        {
            try { return AoaHandle.Start(l); }
            catch (Exception ex) { var h = new AoaHandle(); h.Fail(ex.GetType().Name + ": " + ex.Message); return h; }
        }
    }
}
