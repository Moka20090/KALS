// The SW 01 / SW 02 software failures in the C# twins. kOS publishes the mask (lib/lib_flfx.ks FLFX_SWMASK,
// flfxSwPub, from the ACTIVE list at every flfxTick pass and at a reapply / reset); each twin reads it through its own env's Get
// and gates on its bits. A missing global reads as 0 (no failure): an old script or an old DLL behaves as before.
using System;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class SwGate
    {
        public const int SW01_ASCENT = 1, SW01_ORBIT = 2, SW01_ENTRY = 4, SW02_ASCENT = 8, SW02_ORBIT = 16, SW02_ENTRY = 32,
            SW02_TAEM = 64, SW02_AL = 128, SW02_ALPHA = 256;   // SW02_ALPHA = ALPHA MOD (SimSup's ALPHA FAIL: the DAP's pitch axis only goes CSS)
        public const int SW02_PHASES_DAP = SW02_ENTRY | SW02_TAEM | SW02_AL;   // the guidance phases whose DAP falls to CSS after the hold

        // the mask as kOS publishes it; 0 when the global is not there (or is not a number)
        public static int Read(Func<string, Structure> get)
        {
            try { return (int)Num(get("FLFX_SWMASK")); }
            catch (Exception) { return 0; }
        }

        // DAP_GD_LOST_S (lib_flfx.ks, 3 s): the game time a SW 02 loss is followed before the AUTO axes go CSS
        public static double GdLostS(Func<string, Structure> get)
        {
            try { return Num(get("DAP_GD_LOST_S")); }
            catch (Exception) { return 3.0; }
        }

        static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue();
            throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
        }
    }
}
