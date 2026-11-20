// The software failures SW 01 / SW 02 as the C# twins that run in the physics tick see them.
// Those twins (O2Dap, AscDap) are driven by the fly-by-wire handler, with no kOS call in the loop, so they cannot read a kOS
// global. The truth they read is the vessel's OWN failure list (FailVessel.S, the list kOS adopts: lib_fail's flDllAdopt, and
// mirrors into at once: flDllSet), by (code, scope): the entry's Target is the scope string kOS stored (ASCENT / ORBIT /
// ENTRY, TAEM, A/L). A twin knows its own scope, so no program state is needed and no script can change the answer.
// Read only: nothing here writes the list. No FailVessel (an old save, no module, no vessel) reads as "not failed".
// Main thread only (FailVessel.FixedUpdate, the FBW handlers and the kOS suffixes all run there).
using System;
using UnityEngine;

namespace KalsCoproc
{
    public static class SwQuery
    {
        static Vessel cv;
        static FailVessel cf;

        static FailState State(Vessel v)
        {
            if (v == null) return null;
            if (!object.ReferenceEquals(v, cv) || cf == null)
            {
                cv = v;
                cf = FailVessel.Of(v);
            }
            return cf == null ? null : cf.S;
        }

        // TRUE while the vessel's failure list holds (code, scope), e.g. ("SW 01", "ORBIT")
        public static bool Lost(Vessel v, string code, string scope)
        {
            try
            {
                FailState s = State(v);
                return s != null && s.IndexOf(code, scope) >= 0;
            }
            catch (Exception) { cf = null; return false; }
        }

        // the UT the entry happened, -1 when it is not held (for a later hold-then-CSS rule)
        public static double Since(Vessel v, string code, string scope)
        {
            try
            {
                FailState s = State(v);
                if (s == null) return -1;
                int i = s.IndexOf(code, scope);
                return i < 0 ? -1 : s.List[i].At;
            }
            catch (Exception) { cf = null; return -1; }
        }
    }
}
