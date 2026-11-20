// ops2q's keyboard (KalsKeys.cs holds the locks and reads the keys):
//     ADDONS:KALS:KEYLOCK(mode)   "STAGE" / "TYPE" / "OFF" ("" = OFF): the mode wanted, asked for EVERY tick (the
//                                 watchdog drops a mode not asked for again within 2 s, counted only once the asking
//                                 program has stopped running). Returns the mode now in force,
//                                 or "ERROR: <why>" for a word that is not a mode; never throws.
//     ADDONS:KALS:KEYS            the keys read since the last call, oldest first, as ops2q's key names ("0".."9" "."
//                                 "-" "+" BKSP ENT CAN), and empties the list.
// ops2q (o2qKeys) reads KEYS first, hands each key to o2qKey (the path of the window's own pad), then asks for TYPE while
// its TYPE box is open, else STAGE; OFF when it ends.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterKeys()
        {
            AddSuffix("KEYLOCK", new OneArgsSuffix<StringValue, StringValue>(KeyLock));
            AddSuffix("KEYS", new Suffix<ListValue>(KeyList));
        }

        StringValue KeyLock(StringValue m)
        {
            try
            {
                string n = KalsKeys.Norm(m == null ? "" : m.ToString());
                if (n == null) return new StringValue("ERROR: NO KEY MODE '" + m + "' (STAGE / TYPE / OFF)");
                KalsKeys.Ask(n, Time.unscaledTime, n == "OFF" ? null : KeyHolder());
                KalsKeyPad.Apply(n, "KEYLOCK");
                return new StringValue(KalsKeys.Mode);
            }
            catch (Exception e) { return new StringValue("ERROR: " + e.Message); }
        }

        // the asking program's check, made at the KEYLOCK call: true while that same kOS program context is the core's
        // current one, the core is powered (READY) and its vessel is the active vessel; null (the 2 s watchdog alone) when
        // any of it cannot be read
        Func<bool> KeyHolder()
        {
            try
            {
                kOS.SharedObjects sh = shared;
                if (sh == null || sh.Cpu == null) return null;
                object ctx = sh.Cpu.GetCurrentContext();
                var proc = sh.Processor as kOS.Module.kOSProcessor;
                Vessel ves = sh.Vessel;
                if (ctx == null || proc == null || ves == null) return null;
                return () => sh.Cpu != null && ReferenceEquals(sh.Cpu.GetCurrentContext(), ctx)
                    && proc != null && proc.ProcessorMode == kOS.Safe.Module.ProcessorModes.READY
                    && ves != null && sh.Vessel == ves && FlightGlobals.ActiveVessel == ves;
            }
            catch (Exception) { return null; }
        }

        ListValue KeyList()
        {
            var r = new ListValue();
            try { foreach (string k in KalsKeys.Drain()) r.Add(new StringValue(k)); }
            catch (Exception) { }
            return r;
        }
    }
}
