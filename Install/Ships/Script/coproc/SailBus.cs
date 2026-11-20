// SailBus: what the test harness's host (Sail.cs, dev DLL only) shares with kOS (KalsAddon.Sail.cs) and with the flight code
// (AfbwThrottle's lever hand-off and KalsAddon.Fail's SimSup.NoPilot read On). Its own file, so the release build
// (-define:KALS_RELEASE) compiles with Sail.cs / SailFixture.cs / KalsAddon.Sail.cs left out of the package; there On is const false.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
#if !KALS_RELEASE
    // what the host shares with kOS (KalsAddon.Sail.cs: SAILON / SAILCMD / SAILDONE / SAILSTAT)
    public static class SailBus
    {
        public static volatile bool On;                                          // a valid ticket is running this session
        public static readonly Queue<string> Kos = new Queue<string>();          // "<seq>|PRESS|name" / "<seq>|KOS|line", for kOS
        public static readonly Dictionary<string, string> Stat = new Dictionary<string, string>();
        public static Action<long, string> Ack;                                  // set by the host
        public static string Next() { return Kos.Count > 0 ? Kos.Dequeue() : ""; }
    }
#else
    // the release DLL: no test harness, so no session is ever a test run
    public static class SailBus
    {
        public const bool On = false;
    }
#endif
}
