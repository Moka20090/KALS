// CAPEGEO = LIST(lat, lng) of the Katniss Cape's terrain mesh (the Kopernicus City2
// KCC_CapeCanaveral, a PQSCity2 in the home body's PQS, which the moved-Cape patch moves with the rest of the Cape),
// or an empty LIST when there is none. lib/lib_cape.ks compares it with the two known positions. The PQS mods are
// children of the body's PQS in every scene (inactive ones included), so this works in orbit as on the pad. Main thread
// (a suffix call).
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        const string CapeCity = "KCC_CapeCanaveral";

        partial void RegisterCape()
        {
            AddSuffix("CAPEGEO", new Suffix<ListValue>(CapeGeo));
        }

        static ListValue CapeGeo()
        {
            var l = new ListValue();
            CelestialBody home = FlightGlobals.GetHomeBody();
            if (home == null || home.pqsController == null) return l;
            foreach (PQSCity2 c in home.pqsController.GetComponentsInChildren<PQSCity2>(true))
            {
                if (c == null) continue;
                if (c.name == CapeCity || c.objectName == CapeCity)
                {
                    l.Add(ScalarValue.Create(c.lat));
                    l.Add(ScalarValue.Create(c.lon));
                    break;
                }
            }
            return l;
        }
    }
}
