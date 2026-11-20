// The vessel's reaction wheels (the capsule's torque) off or back on. kOS 1.6 reaches a wheel only through its part menu
// (the action names are the game's localized strings), so the coprocessor sets ModuleReactionWheel.State itself.
//     ADDONS:KALS:RWHEELS(on)   every ModuleReactionWheel of shared.Vessel's parts Active (on) or Disabled; a broken one
//                               stays broken. Returns how many were changed.
// landRun turns them off at the TAEM start: the orbiter flies on its surfaces and jets, and no input the vessel takes as
// the stick can run the battery down through the wheels.
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterRw()
        {
            AddSuffix("RWHEELS", new OneArgsSuffix<ScalarValue, BooleanValue>(on => ScalarValue.Create(RwSet(shared.Vessel, on.Value))));
        }

        static int RwSet(Vessel v, bool on)
        {
            if (v == null) return 0;
            int n = 0;
            foreach (Part p in v.parts)
            {
                foreach (PartModule m in p.Modules)
                {
                    var rw = m as ModuleReactionWheel;
                    if (rw == null) continue;
                    if (on && rw.State == ModuleReactionWheel.WheelState.Disabled) { rw.State = ModuleReactionWheel.WheelState.Active; n++; }
                    else if (!on && rw.State == ModuleReactionWheel.WheelState.Active) { rw.State = ModuleReactionWheel.WheelState.Disabled; n++; }
                }
            }
            return n;
        }
    }
}
