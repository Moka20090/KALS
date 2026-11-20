// the RTLS selection's pitchdown prediction (lib_ascent_rtls.ks asc_rtls_ppd_predict) in C# (RtlsPpd.cs,
// RtlsKos.cs): ADDONS:KALS:RTPPD (+ RTERROR, RTN, RTMS). Synchronous, pure; none throws into kOS.
// Needs in KalsAddon.cs: `partial void RegisterRtls();` and the call `RegisterRtls();` in the constructor.
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        RtHost rtHost;

        partial void RegisterRtls()
        {
            rtHost = RtReg.Register(shared.Cpu, (n, s) => AddSuffix(n, s), o => ((kOS.Suffixed.Vector)o).ToVector3D(),
                v => new kOS.Suffixed.Vector(v), null);
        }
    }
}
