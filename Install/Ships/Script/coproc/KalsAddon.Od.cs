// ops2q's page draw and orbit view in C# (Od.cs): ADDONS:KALS:O2SETUP, O2DRAW (+ O2ERROR, O2N, O2MS) and O2VSETUP,
// O2VIEW (+ O2VERROR, O2VN, O2VMS). Synchronous; none throws into kOS; the writes are the kOS code's own (kOS draws itself
// when they are missing or fail). Needs in KalsAddon.cs: `partial void RegisterOd();` and the call `RegisterOd();` in the constructor.
namespace KalsCoproc
{
    public partial class KalsAddon
    {
        OdHost odHost;

        partial void RegisterOd()
        {
            odHost = OdReg.Register((n, s) => AddSuffix(n, s));
        }
    }
}
