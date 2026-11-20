// lib_taemdisp.ks's page math (the TAEM pages VERT SIT / HORIZ SIT, MM 603, and the GRTLS's MM 602) in C#
// (Td.cs, TdKos.cs): ADDONS:KALS:TDSETUP, TDDRAW (+ TDERROR, TDN, TDMS).
// Synchronous; none throws into kOS; the widgets stay kOS's (TDDRAW returns the widget writes as ops).
// Needs in KalsAddon.cs: `partial void RegisterTd();` and the call `RegisterTd();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        TdHost tdHost;

        partial void RegisterTd()
        {
            tdHost = TdReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), null);
        }
    }
}
