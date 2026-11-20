// one entry guidance cycle (entry_predict.ks eprGuidStep / lib_tal.ks talGuidStep) in C# (EntryGuid.cs,
// EntryGuidKos.cs): ADDONS:KALS:EGSETUP, EGSTEP (+ EGERROR, EGN, EGMS).
// Synchronous; none throws into kOS; the game reads (TIME:SECONDS, the pressure, the state) stay kOS's.
// Needs in KalsAddon.cs: `partial void RegisterEntry();` and the call `RegisterEntry();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        EgHost egHost;

        partial void RegisterEntry()
        {
            egHost = EgReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), o => ((kOS.Suffixed.Vector)o).ToVector3D(),
                v => new kOS.Suffixed.Vector(v), null);
        }
    }
}
