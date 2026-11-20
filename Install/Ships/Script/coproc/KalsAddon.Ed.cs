// lib_entdisp.ks's page math (the entry page, HORIZ SIT in entry) in C# (Ed.cs, EdKos.cs): ADDONS:KALS:EDSETUP,
// EDDRAW (+ EDERROR, EDN, EDMS). Synchronous; none throws into kOS; the
// widgets stay kOS's (EDDRAW returns the widget writes as ops).
// Needs in KalsAddon.cs: `partial void RegisterEd();` and the call `RegisterEd();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        EdHost edHost;

        partial void RegisterEd()
        {
            edHost = EdReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), null);
        }
    }
}
