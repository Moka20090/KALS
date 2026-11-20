// the DAP's tick (lib/lib_dap.ks dapTick) in C# -- Dap.cs (the port), DapState.cs (its globals), DapKos.cs
// (the envs, DapHost). Synchronous, none throws into kOS:
//     ADDONS:KALS:DAPTICK(LIST(the tick's 23 reads, lib_dap's dapCsIn)) -> LIST(E0, E1, E2, E3, F, R0, R1 angles
//         (-1E9 = no write), LIST(actions)) with the DAP's globals already written; or a string ("error ...") with
//         nothing written (kOS's dapTickK then flies that tick).
//     DAPERROR, DAPREADY, DAPN (the ticks flown).
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        DapHost dapHost;

        partial void RegisterDap()
        {
            dapHost = new DapHost(s => ((kOS.Suffixed.Vector)s).ToVector3D(), v => new kOS.Suffixed.Vector(v));
            dapHost.FtCols = () => FtGroundCols(shared.Vessel);
            AddSuffix("DAPTICK", new OneArgsSuffix<Structure, ListValue>(l => dapHost.Tick(shared.Cpu, l)));
            AddSuffix("DAPERROR", new Suffix<StringValue>(() => new StringValue(dapHost.Error)));
            AddSuffix("DAPREADY", new Suffix<BooleanValue>(() => BooleanValue.True));
            AddSuffix("DAPN", new Suffix<ScalarValue>(() => ScalarValue.Create(dapHost.Ticks)));
        }
    }
}
