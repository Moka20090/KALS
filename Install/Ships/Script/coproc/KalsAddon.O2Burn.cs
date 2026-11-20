// ADDONS:KALS:O2BURN* -- ops2q's burn tick in C# (O2Burn.cs the maths, O2BurnKos.cs the suffix bodies; the list
// layouts are documented in O2BurnKos.cs). Nothing calls them until the wiring step.
// REGISTRATION: KalsAddon.cs needs `partial void RegisterO2Burn();` beside the other declarations and `RegisterO2Burn();` at the end of the
// constructor's Register* line (two small edits, held until KalsAddon.cs is free).
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterO2Burn()
        {
            AddSuffix("O2BURNARM", new OneArgsSuffix<Structure, ListValue>(l => O2BurnKos.Arm(l)));
            AddSuffix("O2BURNSENSE", new OneArgsSuffix<Structure, ListValue>(l => O2BurnKos.Sense(l)));
            AddSuffix("O2BURNSETVGO", new OneArgsSuffix<Structure, ListValue>(l => O2BurnKos.SetVgo(l)));
            AddSuffix("O2BURNDECIDE", new Suffix<Structure>(() => O2BurnKos.Decide()));
            AddSuffix("O2BURNSTEP", new OneArgsSuffix<Structure, ListValue>(l => O2BurnKos.Step(l)));
            AddSuffix("O2BURNSTATE", new Suffix<Structure>(() => O2BurnKos.State()));
            AddSuffix("O2BURNDROP", new Suffix<Structure>(() => O2BurnKos.Drop()));
        }
    }
}
