// lib_ascdisp.ks's page math (the ascent displays: TRAJ 1 / 2, RTLS TRAJ 2, OMS/MPS) in C# (Ad.cs, AdKos.cs):
// ADDONS:KALS:ADSETUP, ADDRAW (+ ADERROR, ADN, ADMS). Synchronous; none throws
// into kOS; the widgets stay kOS's (ADDRAW returns the widget writes as ops).
// Needs in KalsAddon.cs: `partial void RegisterAd();` and the call `RegisterAd();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        AdHost adHost;

        partial void RegisterAd()
        {
            adHost = AdReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), o => ((kOS.Suffixed.Vector)o).ToVector3D(), null);
        }
    }
}
