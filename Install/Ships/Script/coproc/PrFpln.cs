// Principia's flight plans, read for ops2q's FPLN tree (READ ONLY: nothing here changes a plan; the one write is the
// selection of the plan being read, put back before the call returns). Built on Pr.cs (reflection into the adapter's Interface).
// Principia keeps ONE plan "selected" and answers every FlightPlan* call about that one; to read plan k the selection is moved
// to k and restored in the same call (the main thread: no frame, so no draw of the planner's window, sees the moved selection).
// What is read of a manoeuvre (Principia's own numbers):
//   ignition time     burn.initial_time
//   half-dV time      time_of_half_delta_v           (the impulse's time: ops2q's burn point)
//   burn duration     duration
//   dV magnitude      the rocket equation of the burn's own masses and Isp (Principia's duration IS this equation)
//   dV direction      FlightPlanGetGuidance (World axes; the direction the burn points at, normalised)
//   ignition state    the rendered burn segment's first point (position less the main body's) and the ignition velocity
// The dV vector = the magnitude along the guidance direction at ignition: exact for a burn fixed in inertial space, an
// approximation for one that turns with the Frenet frame (the direction at the ignition, not along the whole burn).
using System;
using System.Collections.Generic;
using System.Text;

namespace KalsCoproc
{
    public sealed class PrBurn
    {
        public int Plan, Index;
        public double Ig, Tc, Tb;                  // ignition UT, the half-dV impulse UT, the duration (s)
        public Vector3d R, V, Dv;                  // the ignition state (body-relative, World axes), the burn's dV vector (World axes, m/s)
    }

    public static class PrFpln
    {
        public const double G0 = 9.80665;
        public const int MaxPlans = 10;            // Principia's own cap on a vessel's flight plans

        static string D(double x) { return x.ToString("R", System.Globalization.CultureInfo.InvariantCulture); }

        // A cheap text that changes when the SELECTED plan or the plan count / selection changes: the poll reads this once a
        // second and reads every plan only when it differs ("novessel" / "noplan" when there is none).
        public static string Signature(IntPtr p, string guid)
        {
            if (!Pr.HasVessel(p, guid)) return "novessel";
            if (!(bool)Pr.Call("FlightPlanExists", p, guid)) return "noplan";
            var s = new StringBuilder();
            s.Append((int)Pr.Call("FlightPlanCount", p, guid)).Append('/').Append((int)Pr.Call("FlightPlanSelected", p, guid)).Append('/');
            int n = Pr.Manoeuvres(p, guid);
            s.Append(n).Append('/').Append(D((double)Pr.Call("FlightPlanGetInitialTime", p, guid)));
            for (int i = 0; i < n; i++)
            {
                object m = Pr.Call("FlightPlanGetManoeuvre", p, guid, i);
                object b = Pr.Get(m, "burn");
                Vector3d g = Pr.V(Pr.Call("FlightPlanGetGuidance", p, guid, i));
                s.Append('|').Append(D((double)Pr.Get(b, "initial_time"))).Append(',').Append(D((double)Pr.Get(m, "duration"))).Append(',')
                 .Append(D((double)Pr.Get(m, "initial_mass_in_tonnes"))).Append(',').Append(D((double)Pr.Get(m, "final_mass_in_tonnes"))).Append(',')
                 .Append(D(g.x)).Append(',').Append(D(g.y)).Append(',').Append(D(g.z));
            }
            return s.ToString();
        }

        // The burns of the SELECTED plan (plan index k), in order; stops at the first one whose ignition state is not readable
        // (past the plotting frame's span): the ones after it have no state to plan from.
        public static List<PrBurn> ReadSelected(IntPtr p, string guid, int k, Vector3d sun, Vector3d body)
        {
            var r = new List<PrBurn>();
            int n = Pr.Manoeuvres(p, guid);
            for (int i = 0; i < n; i++)
            {
                object m = Pr.Call("FlightPlanGetManoeuvre", p, guid, i);
                object b = Pr.Get(m, "burn");
                double t; Vector3d rr, vv;
                if (!Pr.Ignition(p, guid, i, sun, body, out t, out rr, out vv)) break;
                double mi = (double)Pr.Get(m, "initial_mass_in_tonnes"), mf = (double)Pr.Get(m, "final_mass_in_tonnes");
                double isp = (double)Pr.Get(b, "specific_impulse_in_seconds_g0");
                double dv = mi > mf && mf > 0 && isp > 0 ? isp * G0 * Math.Log(mi / mf) : 0;
                Vector3d g = Pr.V(Pr.Call("FlightPlanGetGuidance", p, guid, i));
                double gm = g.magnitude;
                Vector3d dvw = gm > 0 ? g * (dv / gm) : Vector3d.zero;
                r.Add(new PrBurn { Plan = k, Index = i, Ig = t, Tc = (double)Pr.Get(m, "time_of_half_delta_v"), Tb = (double)Pr.Get(m, "duration"),
                                   R = rr, V = vv, Dv = dvw });
            }
            return r;
        }

        // Every plan (up to max): result[k] = plan k's burns. The selected plan is read where it stands, the selection is moved to each
        // other plan in turn and put back (also when a read throws): a vessel with N plans costs N - 1 moves out and one back. count / sel: Principia's plan count and the selected index; no plan: an empty list, count 0.
        public static List<List<PrBurn>> ReadAll(IntPtr p, string guid, Vector3d sun, Vector3d body, int max, out int count, out int sel)
        {
            count = 0; sel = 0;
            var res = new List<List<PrBurn>>();
            if (!Pr.HasVessel(p, guid) || !(bool)Pr.Call("FlightPlanExists", p, guid)) return res;
            count = (int)Pr.Call("FlightPlanCount", p, guid);
            sel = (int)Pr.Call("FlightPlanSelected", p, guid);
            int cur = sel, n = Math.Min(count, max);
            for (int k = 0; k < n; k++) res.Add(null);
            try
            {
                if (sel < n) res[sel] = ReadSelected(p, guid, sel, sun, body);   // the selected plan first: no move at all for it
                for (int k = 0; k < n; k++)
                {
                    if (k == sel) continue;
                    Pr.Call("FlightPlanSelect", p, guid, k); cur = k;
                    res[k] = ReadSelected(p, guid, k, sun, body);
                }
            }
            finally
            {
                if (cur != sel) Pr.Call("FlightPlanSelect", p, guid, sel);
            }
            return res;
        }
    }
}
