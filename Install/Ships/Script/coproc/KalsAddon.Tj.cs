// lib/traj_display.ks's page math (the ENTRY TRAJ page: trajUpdate) in C# (Tj.cs, TjKos.cs):
// ADDONS:KALS:TJSETUP, TJDRAW (+ TJFORGET, TJERROR, TJN, TJMS, TJSKIP).
// Synchronous; none throws into kOS; the widgets stay kOS's (TJDRAW returns the widget writes as ops).
// Needs in KalsAddon.cs: `partial void RegisterTj();` and the call `RegisterTj();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        TjHost tjHost;

        partial void RegisterTj()
        {
            tjHost = TjReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), null);
        }
    }
}
