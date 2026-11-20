// the entry reference-family build as ADDONS:KALS suffixes (a partial of KalsAddon: RegisterFam is called from
// its constructor): FAMSTART, FAMERROR -- registered by FamKos.Register (FamKos.cs, the kOS side; Fam.cs the
// build). Here only what needs the game: SHIP:BODY's pressure for the worker threads (kOS's ALTITUDEPRESSURE is
// CelestialBody.GetPressure(h) * KpaToAtm), the body captured on the main thread at FAMSTART.
using System;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterFam()
        {
            FamKos.Register(AddSuffix, () =>
            {
                // SHIP:BODY, tabulated on the main thread (GetPressure from the workers raced its curve's cache)
                return PresTab.Of(shared.Vessel.mainBody);
            });
        }
    }
}
