// ops1q.ks's ascHudRec (the OPS 1 HUD's inputs each tick) in C# (AscHud.cs): ADDONS:KALS:ASCHUD (+ ASCHUDERROR, ASCHUDN). Synchronous; none throws into kOS.
// Needs in KalsAddon.cs: `partial void RegisterAscHud();` and the call `RegisterAscHud();` in the constructor.
namespace KalsCoproc
{
    public partial class KalsAddon
    {
        AscHudHost ascHudHost;

        partial void RegisterAscHud()
        {
            ascHudHost = AscHudReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), o => ((kOS.Suffixed.Vector)o).ToVector3D());
        }
    }
}
