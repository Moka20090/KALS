// the kOS side of Grd.cs -- the live env (the kOS CPU's globals, read with GetValue("$name") and written with
// SetGlobal; a list element written in place),
// and GrdHost, the calls the addon (KalsAddon.Grd.cs) and the offline VM's twin both make. kOS.Safe only: the vectors and
// kOS's ANGLEAXIS product come through delegates (the game's kOS.Suffixed.Vector and UnityEngine.Quaternion, the VM's
// Vec and its managed twin). No call throws into kOS: an error comes back as a string.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public class GrdLiveEnv : IGrdEnv
    {
        protected readonly ICpu cpu;
        readonly Func<Structure, Vector3d> vin;
        readonly Func<Vector3d, Structure> vout;
        readonly Func<double, Vector3d, Vector3d, Vector3d> aax;
        public GrdLiveEnv(ICpu c, Func<Structure, Vector3d> i, Func<Vector3d, Structure> o, Func<double, Vector3d, Vector3d, Vector3d> a)
        { cpu = c; vin = i; vout = o; aax = a; }
        public virtual Structure Get(string name) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + name, false)); }
        public virtual void Set(string name, Structure v) { cpu.SetGlobal("$" + name, v); }
        public virtual void ListSet(string name, Structure list, int i, Structure v) { ((ListValue)list)[i] = v; }
        public Vector3d Vec(Structure s) { return vin(s); }
        public Structure MakeVec(Vector3d v) { return vout(v); }
        public Vector3d AngleAxisMul(double deg, Vector3d axis, Vector3d u) { return aax(deg, axis, u); }
    }

    public class GrdHost
    {
        readonly Grd grd = new Grd();
        readonly Func<Structure, Vector3d> vin;
        readonly Func<Vector3d, Structure> vout;
        readonly Func<double, Vector3d, Vector3d, Vector3d> aax;
        public string Error = "";
        public int Ticks = 0;
        public GrdHost(Func<Structure, Vector3d> i, Func<Vector3d, Structure> o, Func<double, Vector3d, Vector3d, Vector3d> a)
        { vin = i; vout = o; aax = a; }

        // one tick: the outputs list (grdCsTick applies it), or a string when it failed (nothing written to kOS)
        public Structure Tick(ICpu cpu, ListValue inp)
        {
            try
            {
                var o = grd.Tick(new GrdLiveEnv(cpu, vin, vout, aax), inp);
                Ticks++;
                return o;
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + Error); }
        }
    }
}
