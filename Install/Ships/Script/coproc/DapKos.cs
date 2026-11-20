// the kOS side of Dap.cs -- the live env (the kOS CPU's globals, read with GetValue("$name") and written with
// SetGlobal), and DapHost, the three calls the
// addon (KalsAddon.Dap.cs) and the offline VM's twin (vm/vmsock.cs) both make. kOS.Safe only: the vectors come through
// two delegates (the game's kOS.Suffixed.Vector, the VM's Vec). No call throws into kOS: an error comes back as a string.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public delegate Vector3d DapVecIn(Structure s);
    public delegate Structure DapVecOut(Vector3d v);

    public class DapLiveEnv : IDapEnv
    {
        protected readonly ICpu cpu;
        readonly DapVecIn vin;
        readonly DapVecOut vout;
        public DapLiveEnv(ICpu c, DapVecIn i, DapVecOut o) { cpu = c; vin = i; vout = o; }
        public virtual Structure Get(string name) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + name, false)); }
        public virtual void Set(string name, Structure v) { cpu.SetGlobal("$" + name, v); }
        public Vector3d Vec(Structure s) { return vin(s); }
        public Structure MakeVec(Vector3d v) { return vout(v); }
        public virtual void LexSet(Structure lex, string key, Structure v) { ((Lexicon)lex)[new StringValue(key)] = v; }
        public virtual void ListAdd(Structure list, Structure v) { ((ListValue)list).Add(v); }
    }

    public class DapHost
    {
        readonly Dap dap = new Dap();
        readonly DapVecIn vin;
        readonly DapVecOut vout;
        public string Error = "";
        public int Ticks = 0;
        public DapHost(DapVecIn i, DapVecOut o) { vin = i; vout = o; }
        public Func<string> FtCols { set { dap.ftCols = value; } }     // the csv's SockFarTrim columns (KalsAddon.Far.cs)

        // one tick: the outputs list (dapCsTick applies it), or a string when it failed (nothing written to kOS)
        public Structure Tick(ICpu cpu, ListValue inp)
        {
            try
            {
                var o = dap.Tick(new DapLiveEnv(cpu, vin, vout), inp);
                Ticks++;
                return o;
            }
            catch (Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + Error); }
        }
    }
}
