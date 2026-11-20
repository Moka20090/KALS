// the GRTLS / ECAL / OPS 3 entry DAP's tick (lib/lib_grdap.ks grdTick) in C# -- Grd.cs (the port), GrdKos.cs (the
// envs, GrdHost). Synchronous, none throws into kOS:
//     ADDONS:KALS:GRDTICK(LIST(the tick's 17 reads, lib_grdap's grdCsIn)) -> LIST(cmdP, cmdR, cmdY (kOS hands them to FBW3),
//         the action code (1 PITCH's text, 2 ROLL/YAW's, 4 LOG, 8 messages), the text to LOG, the keyboard mode's messages
//         (kOS's addMsg each)) with the DAP's globals and lib_dap's dKb already written;
//         or a string ("error ...") with nothing written (kOS's grdTickK then flies that tick and the rest).
//     GRDERROR, GRDREADY, GRDN (the ticks flown), GRDKB (TRUE: GRDTICK takes FBWPILOT's raw stick and
//     applies the keyboard mode itself; a DLL without it wants the stick after kbAxis).
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        GrdHost grdHost;

        partial void RegisterGrd()
        {
            // kOS's ANGLEAXIS(deg, v) * u (kOS.dll, IL-read: Direction.AngleAxis = Quaternion.AngleAxis((float)deg, (Vector3)v);
            // Direction * Vector = Rotation * (Vector3)(Vector3d)u, the Vector3 back as doubles)
            grdHost = new GrdHost(s => ((kOS.Suffixed.Vector)s).ToVector3D(), v => new kOS.Suffixed.Vector(v),
                (deg, axis, u) => { Vector3 r = Quaternion.AngleAxis((float)deg, (Vector3)axis) * (Vector3)u; return new Vector3d(r.x, r.y, r.z); });
            AddSuffix("GRDTICK", new OneArgsSuffix<Structure, ListValue>(l => grdHost.Tick(shared.Cpu, l)));
            AddSuffix("GRDERROR", new Suffix<StringValue>(() => new StringValue(grdHost.Error)));
            AddSuffix("GRDREADY", new Suffix<BooleanValue>(() => BooleanValue.True));
            AddSuffix("GRDKB", new Suffix<BooleanValue>(() => BooleanValue.True));
            AddSuffix("GRDN", new Suffix<ScalarValue>(() => ScalarValue.Create(grdHost.Ticks)));
        }
    }
}
