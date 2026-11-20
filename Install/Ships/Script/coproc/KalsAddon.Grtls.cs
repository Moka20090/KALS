// the GRTLS's Nz model and alpha slew (lib_grtls.ks grtlsFcs / grtlsNz) in C# (GrtlsGuid.cs, GrtlsGuidKos.cs):
// ADDONS:KALS:GRSETUP, GRFCS, GRNZ (+ GRERROR, GRN, GRMS).
// Synchronous; none throws into kOS; the game reads (the pressure, ALT:RADAR, the state) stay kOS's.
// Needs in KalsAddon.cs: `partial void RegisterGrtls();` and the call `RegisterGrtls();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        GrHost grHost;

        partial void RegisterGrtls()
        {
            grHost = GrReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), null);
        }
    }
}
