// The kOS side of AscCss.cs -- the env (the kOS CPU's globals read with GetValue("$name"); the vectors and the
// Directions through delegates: the game's kOS.Suffixed.Vector / Direction and Unity's native Quaternion calls, the
// offline VM's twins) and AscHost, the calls the addon (KalsAddon.AscCss.cs) and the VM's twin both make. kOS.Safe and
// UnityEngine.CoreModule only. No call throws into kOS: an error comes back as a string.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Execution;
using UnityEngine;

namespace KalsCoproc
{
    public class AscEnvFns
    {
        public Func<Structure, Vector3d> Vin;
        public Func<Vector3d, Structure> Vout;
        public Func<Structure, Quaternion> Din;
        public Func<Quaternion, Structure> Dout;
        public Func<Quaternion, Quaternion> Inv;
        public Func<Vector3d, Vector3d, Quaternion> Look;
        public Func<Vector3d, Quaternion> Euler;
    }

    public class AscLiveEnv : IAscEnv
    {
        readonly ICpu cpu;
        readonly AscEnvFns f;
        public AscLiveEnv(ICpu c, AscEnvFns fns) { cpu = c; f = fns; }
        public Structure Get(string name) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + name, false)); }
        public Vector3d Vec(Structure s) { return f.Vin(s); }
        public Structure MakeVec(Vector3d v) { return f.Vout(v); }
        public Quaternion Rot(Structure d) { return f.Din(d); }
        public Structure MakeDir(Quaternion q) { return f.Dout(q); }
        public Quaternion Inverse(Quaternion q) { return f.Inv(q); }
        public Quaternion Look(Vector3d fwd, Vector3d up) { return f.Look(fwd, up); }
        public Quaternion Euler(Vector3d e) { return f.Euler(e); }
    }

    public class AscHost
    {
        readonly AscCss live = new AscCss();
        readonly AscEnvFns fns;
        public string Error = "";
        public int Ticks = 0;
        public AscHost(AscEnvFns f) { fns = f; }

        // one tick: the outputs list (kOS's ascCsTick applies it), or a string when it failed (nothing written to kOS)
        public Structure Tick(ICpu cpu, ListValue inp)
        {
            try
            {
                var e = new AscLiveEnv(cpu, fns);
                live.Run(e, inp);
                live.Commit(e);
                Ticks++;
                return live.Out();
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + Error); }
        }
    }
}
