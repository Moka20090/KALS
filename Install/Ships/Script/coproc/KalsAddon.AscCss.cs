// The ascent CSS's Law A tick (lib/lib_ascent_css.ks ascCssTickA) in C# -- AscCss.cs (the port), AscCssKos.cs (the
// env, AscHost). Synchronous, none throws into kOS:
//     ADDONS:KALS:ASCCSSTICK(LIST(the tick's 10 reads, lib_ascent_css's ascCsIn)) -> LIST(cmdP, cmdR, cmdY (kOS hands them
//         to FBW3), the action code (1 the return's stop: ascCssStop with the text; 2 the row after it: ascCssRow with
//         the ten values; 4 the text to LOG to the csv), the text, the ten values, the LOG text) with ascCss already
//         written; or a string ("error ...") with nothing written (kOS's ascCssTickAK then flies that tick and the rest).
//     ASCCSSERROR, ASCCSSN (the ticks flown).
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        AscHost ascHost;

        partial void RegisterAscCss()
        {
            // kOS.dll's Directions (read from its IL): Direction(Quaternion), .Rotation; LOOKDIRUP = Quaternion.LookRotation(
            // (Vector3)v, (Vector3)u); :INVERSE = Quaternion.Inverse; R(x, y, z) = Quaternion.Euler((Vector3)(x, y, z))
            ascHost = new AscHost(new AscEnvFns
            {
                Vin = s => ((kOS.Suffixed.Vector)s).ToVector3D(),
                Vout = v => new kOS.Suffixed.Vector(v),
                Din = s => ((kOS.Suffixed.Direction)s).Rotation,
                Dout = q => new kOS.Suffixed.Direction(q),
                Inv = q => Quaternion.Inverse(q),
                Look = (f, u) => Quaternion.LookRotation((Vector3)f, (Vector3)u),
                Euler = e => Quaternion.Euler((Vector3)e),
            });
            AddSuffix("ASCCSSTICK", new OneArgsSuffix<Structure, ListValue>(l => ascHost.Tick(shared.Cpu, l)));
            AddSuffix("ASCCSSERROR", new Suffix<StringValue>(() => new StringValue(ascHost.Error)));
            AddSuffix("ASCCSSN", new Suffix<ScalarValue>(() => ScalarValue.Create(ascHost.Ticks)));
        }
    }
}
