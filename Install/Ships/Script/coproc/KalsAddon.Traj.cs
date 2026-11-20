// The ENTRY TRAJ backgrounds (gen_traj_bg.py's traj1..5.png + traj_bg.txt) drawn by the addon
// on a worker thread (TrajBg.cs: the drawing; TjPng.cs: the PNG writer; TrajBgJob.cs: the files), so no python watcher runs.
//     LOCAL h IS ADDONS:KALS:TJBG("family.txt", "traj_cs/traj_bg.txt", "traj_tpl/tpl_0.667.bin").    // returns at once
//     LOCAL h IS ADDONS:KALS:TJBGFAM(EPR_FAM, LEXICON("side", "traj_cs/ops6/traj_bg.txt", "tpl", "traj_tpl/tpl_0.667.bin",
//                "pngdir", "traj_cs/ops6", "dmax", 100, "vessel", SHIP:NAME, "written", ROUND(TIME:SECONDS, 3), "aero_ver", EPR_AERO_VER,
//                "taem_vel", EPR_TAEM_VEL)).              // the family in memory (OPS 6): each member LIST(bank, vs, ds,
//                                                          // ss, rg, bk, ...), rounded as lib_fam's famWrite rounds them
//     ... later passes: IF h:DONE { IF h:OK { SET TJ_SIDE TO "0:/" + h:SIDE. } ELSE { h:WHY } }
// Paths are relative to the archive (Ships/Script; a "0:/" prefix is allowed, ".." is not). The PNGs go to traj_cs/ under
// names stamped with the family's written time (kOS caches images by path). The inputs are copied into plain C# here on
// the main thread; the worker touches no kOS / Unity object. Never throws into kOS: a failure is a finished handle with
// OK FALSE and WHY.
// The kOS side (the inputs, the handle) is TrajBgKos.cs (kOS.Safe only: the offline VM builds it too).
// Needs in KalsAddon.cs: `partial void RegisterTraj();` and the call `RegisterTraj();` in the constructor.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterTraj()
        {
            AddSuffix("TJBG", new ThreeArgsSuffix<TjBgHandle, StringValue, StringValue, StringValue>(TjBgStart));
            AddSuffix("TJBGFAM", new TwoArgsSuffix<TjBgHandle, ListValue, Lexicon>(TjBgFamStart));
        }

        TjBgHandle TjBgStart(StringValue fam, StringValue side, StringValue tpl) { return TjBgKos.Start(SafeHouse.ArchiveFolder, fam, side, tpl); }
        TjBgHandle TjBgFamStart(ListValue members, Lexicon opts) { return TjBgKos.StartFam(SafeHouse.ArchiveFolder, members, opts); }
    }
}
