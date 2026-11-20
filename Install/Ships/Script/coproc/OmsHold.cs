// ops2q's OMS interlock. While ops2q's heartbeat is fresh and it says "nothing armed", the vessel's FINAL throttle is zeroed in the
// fly-by-wire handler AfbwThrottle.Fin (one call, OmsHold.Apply, after the kOS-lock guard). Nothing else is touched: no engine is shut
// down or thrust-limited (ops2q's failed-engine record and o2qOmsWatch read IGNITION), and PILOTMAINTHROTTLE (FlightInputHandler.state,
// the DAP's speedbrake lever) is not the final throttle, so it reads as before. An engine on its own throttle (ENGIND, the ascent OMS
// dump) does not follow the vessel's throttle and is not affected; ops1q / ops3q / shuttle_exec never publish the interlock.
//     ADDONS:KALS:OMSHOLD(armed)   the heartbeat: armed FALSE = the OMS is inert (final throttle 0), TRUE = the burn owns the throttle;
//                                  returns TRUE. A script that stops calling (an error, ops3q, a reboot) lets go by itself BEAT_S
//                                  after the last call, so the OMS is never left dead for a later program.
//     ADDONS:KALS:OMSHOLDOFF()     the interlock off at once (ops2q's exit). Returns TRUE.
// The beat is Time.realtimeSinceStartup (a warp does not stretch it). Log lines start with [KalsThrottle] (like the guard's).
using System;
using UnityEngine;

namespace KalsCoproc
{
    public static class OmsHold
    {
        const double BEAT_S = 3;        // s of real time the heartbeat holds the interlock
        const float EPS = 1E-4f;        // a final throttle above this is zeroed
        const double LINE_DT = 1;       // s between log lines

        static bool armed;
        static double beatT = -1E9;
        static bool inEp, epLogged;
        static double epT0, lineT = -1E9;
        static int epN;

        public static bool Set(bool a)
        {
            armed = a;
            beatT = Time.realtimeSinceStartup;
            return true;
        }

        public static bool Off()
        {
            beatT = -1E9;
            return true;
        }

        // the interlock is on: a fresh heartbeat that says nothing is armed
        public static bool Inert
        {
            get
            {
                double d = Time.realtimeSinceStartup - beatT;
                return d >= 0 && d <= BEAT_S && !armed;
            }
        }

        // called by AfbwThrottle.Fin on the final throttle of the active vessel
        public static void Apply(FlightCtrlState s, Vessel v)
        {
            if (s == null) return;
            bool over = Inert && s.mainThrottle > EPS;
            if (over)
            {
                double now = Time.realtimeSinceStartup;
                if (!inEp)
                {
                    inEp = true;
                    epT0 = now;
                    epN = 0;
                    epLogged = now - lineT >= LINE_DT || now < lineT;
                    if (epLogged)
                    {
                        lineT = now;
                        Debug.Log(string.Format("[KalsThrottle] OMS interlock: final throttle {0:F3} zeroed (nothing ARMed) at MET {1:F2}",
                            s.mainThrottle, v != null ? v.missionTime : 0));
                    }
                }
                epN++;
                s.mainThrottle = 0;
            }
            else if (inEp)
            {
                inEp = false;
                if (epLogged)
                    Debug.Log(string.Format("[KalsThrottle] OMS interlock: episode over ({0:F2} s, {1} ticks)", Time.realtimeSinceStartup - epT0, epN));
            }
        }
    }
}
