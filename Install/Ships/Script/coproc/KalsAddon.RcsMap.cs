// THE RCS POD JETS: what the page and the C&W check read. ADDONS:KALS:
//     RCSPOD()    LIST of 3 rows (pods F, L, R): LIST(pod letter, jets in the pod, jets working), working = the jet is not held out by a failure (a closed
//                 manifold, a stuck-off jet) and its module's RCS is on. [] without a vessel / RCS. Counts come from the real jets (RcsJets.cs).
//     RCSJETS()   LIST of the jets, one text each: "NAME pod manifold direction part module jet" (the map the failures use; RCS 04's targets are the names)
//     PAYLOADRCS() T1017: LIST(the payload RCS modules held off on the active vessel, their part names comma-joined): [0, ""] when none (a payload's RCS is held off
//                 and out of the jet map while it is on the shuttle's vessel; PayloadRcs.cs)
// Never throws; acts on the active vessel.
using System;
using System.Globalization;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterRcsMap()
        {
            AddSuffix("RCSPOD", new Suffix<ListValue>(RcsPod));
            AddSuffix("RCSJETS", new Suffix<ListValue>(RcsJetList));
            AddSuffix("PAYLOADRCS", new Suffix<ListValue>(PayloadRcsList));
        }

        ListValue RcsPod()
        {
            var o = new ListValue();
            try
            {
                FailVessel m = FailMod();
                if (m == null || shared == null || shared.Vessel == null) return o;
                int[] c = m.Enforcer.Rcs.Counts(shared.Vessel);
                if (c[0] + c[2] + c[4] == 0) return o;
                string pods = "FLR";
                for (int k = 0; k < 3; k++)
                {
                    var r = new ListValue();
                    r.Add(new StringValue(pods.Substring(k, 1))); r.Add(ScalarValue.Create(c[2 * k])); r.Add(ScalarValue.Create(c[2 * k + 1]));
                    o.Add(r);
                }
            }
            catch (Exception) { }
            return o;
        }

        ListValue PayloadRcsList()
        {
            var o = new ListValue();
            int n = 0; string nm = "";
            try
            {
                FailVessel m = FailMod();
                if (m != null && shared != null && shared.Vessel != null) { n = m.Payload.Count; nm = m.Payload.Names; }
            }
            catch (Exception) { }
            o.Add(ScalarValue.Create(n)); o.Add(new StringValue(nm));
            return o;
        }

        ListValue RcsJetList()
        {
            var o = new ListValue();
            try
            {
                FailVessel m = FailMod();
                if (m == null || shared == null || shared.Vessel == null) return o;
                foreach (RcsJets.Jet j in m.Enforcer.Rcs.Map(shared.Vessel))
                    o.Add(new StringValue(j.Name + " " + j.Pod + " " + j.Man.ToString(CultureInfo.InvariantCulture) + " " + j.Dir + " " + j.Part.flightID.ToString(CultureInfo.InvariantCulture)
                        + " " + j.ModIdx.ToString(CultureInfo.InvariantCulture) + " " + j.JetIdx.ToString(CultureInfo.InvariantCulture)));
            }
            catch (Exception) { }
            return o;
        }
    }
}
