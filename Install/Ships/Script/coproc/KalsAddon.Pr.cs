// Principia from kOS (Pr.cs reaches Principia):
//     ADDONS:KALS:NBSOLVE(lex)    ONE n-body solve of a BRN PLN burn on its own thread (PrNb.cs; the input and the handle's DONE / ERROR / RESULT /
//                                 MS are in PrNbKos.cs's header); the third bodies' positions are sampled here (NbBodiesFromKsp) before it starts.
//     ADDONS:KALS:PEG8SOLVE(lex)  ONE PEG 8 shot, SYNCHRONOUS (PrShoot.cs / PrShootKos.cs: the cutoff velocity whose n-body coast meets the aim
//                                 position; the input and the result's keys are in PrShootKos.cs's header); the third bodies are sampled by NbBodiesFromKsp.
//     ADDONS:KALS:PRFPLN(full)    READ ONLY: LEXICON(ok, why, sig [, n, sel, plans]). full FALSE: the signature of the selected
//                                 flight plan (a text that changes when the plan, the plan count or the selection does). full TRUE:
//                                 also every plan, plans[k] = LIST of burns LEXICON(p, i, ig (ignition UT), tc (half-dV UT), tb (s),
//                                 r (body-relative, ignition), v, dv (dV vector), all World axes = kOS vectors). The plans are read
//                                 by selecting each in turn; the selection is put back (PrFpln.cs). ok FALSE: why says.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterPr()
        {
            AddSuffix("PRFPLN", new OneArgsSuffix<Lexicon, BooleanValue>(full => PrFplnRead(full != null && full.Value)));
            NbReg.Register((n, sx) => AddSuffix(n, sx));      // NBSOLVE (PrNb.cs / PrNbKos.cs)
            NbReg.Bodies = NbBodiesFromKsp;
            ShootReg.Register((n, sx) => AddSuffix(n, sx));   // PEG8SOLVE (PrShoot.cs / PrShootKos.cs; uses NbReg.Bodies)
        }

        // the third bodies' positions relative to the main body (world axes), sampled on the main thread
        // every `step` s from t0 to t1 for NBSOLVE's thread; null = no third bodies (no vessel / any failure: the solve runs on J2 alone).
        static NbBodies NbBodiesFromKsp(double t0, double t1, double step)
        {
            try
            {
                Vessel ves = FlightGlobals.ActiveVessel;
                if (ves == null) return null;
                CelestialBody body = ves.mainBody;
                var th = new List<CelestialBody>();
                foreach (CelestialBody c in FlightGlobals.Bodies)
                    if (c != body && (c.referenceBody == body || c == Planetarium.fetch.Sun)) th.Add(c);
                if (th.Count == 0) return null;
                int n = (int)Math.Ceiling((t1 - t0) / step) + 2;
                if (n < 2 || n > 20000) return null;
                var b = new NbBodies { T0 = t0, Step = step, Mu = new double[th.Count], Pos = new double[th.Count][][] };
                for (int k = 0; k < th.Count; k++)
                {
                    b.Mu[k] = th[k].gravParameter;
                    b.Pos[k] = new double[n][];
                    for (int i = 0; i < n; i++)
                    {
                        double t = t0 + i * step;
                        Vector3d d = th[k].getPositionAtUT(t) - body.getPositionAtUT(t);
                        b.Pos[k][i] = new[] { d.x, d.y, d.z };
                    }
                }
                return b;
            }
            catch (Exception) { return null; }
        }

        // see the header. Never throws into kOS: any failure is ok FALSE with the reason.
        static Lexicon PrFplnRead(bool full)
        {
            var k = new KLex();
            k["ok"] = false; k["why"] = ""; k["sig"] = "";
            try
            {
                IntPtr p = Pr.Plugin();
                if (p == IntPtr.Zero) { k["why"] = Pr.Err; return (Lexicon)PadKos.To(k); }
                Vessel ves = FlightGlobals.ActiveVessel;
                if (ves == null) { k["why"] = "no active vessel"; return (Lexicon)PadKos.To(k); }
                string guid = ves.id.ToString();
                k["sig"] = PrFpln.Signature(p, guid);
                if (!full) { k["ok"] = true; return (Lexicon)PadKos.To(k); }
                string fw = PrFplnFrame(ves.mainBody);
                if (fw != "") { k["why"] = fw; return (Lexicon)PadKos.To(k); }
                int count, sel;
                List<List<PrBurn>> plans = PrFpln.ReadAll(p, guid, Planetarium.fetch.Sun.position, ves.mainBody.position, PrFpln.MaxPlans, out count, out sel);
                var pl = new List<object>();
                int nbad = 0;                      // burns with a non-finite number (no thrust: duration / mass flow 0/0 or x/0) are left out and counted
                foreach (List<PrBurn> plan in plans)
                {
                    var bl = new List<object>();
                    foreach (PrBurn b in plan)
                    {
                        if (!PrFplnFinite(b)) { nbad++; continue; }
                        var o = new KLex();
                        o["p"] = b.Plan; o["i"] = b.Index; o["ig"] = b.Ig; o["tc"] = b.Tc; o["tb"] = b.Tb;
                        o["r"] = new Vec3(b.R.x, b.R.y, b.R.z); o["v"] = new Vec3(b.V.x, b.V.y, b.V.z); o["dv"] = new Vec3(b.Dv.x, b.Dv.y, b.Dv.z);
                        bl.Add(o);
                    }
                    pl.Add(bl);
                }
                k["n"] = count; k["sel"] = sel; k["plans"] = pl; k["nbad"] = nbad;
                k["sig"] = PrFpln.Signature(p, guid);
                k["ok"] = true;
            }
            catch (Exception e)
            {
                k["ok"] = false;
                k["why"] = "Principia read: " + (e.InnerException != null ? e.InnerException.Message : e.Message);
            }
            return (Lexicon)PadKos.To(k);
        }

        // kOS halts on
        // a NaN / Infinity it is handed and no kOS code can read one first, so every number of a burn is checked here before it crosses.
        static bool PrFin(double d) { return !double.IsNaN(d) && !double.IsInfinity(d); }
        static bool PrFin(Vector3d v) { return PrFin(v.x) && PrFin(v.y) && PrFin(v.z); }
        internal static bool PrFplnFinite(PrBurn b)
        {
            return PrFin(b.Ig) && PrFin(b.Tc) && PrFin(b.Tb) && PrFin(b.R) && PrFin(b.V) && PrFin(b.Dv);
        }

        // The positions of a flight plan's points are body-relative only in the plotting frame "body-centred, non-rotating" of the main
        // body; "" when it is, else what to set.
        static string PrFplnFrame(CelestialBody body)
        {
            object fsel = null;
            try { fsel = Pr.Get(Pr.Adapter(), "plotting_frame_selector_"); } catch (Exception) { }
            if (fsel == null) return "";           // the adapter's field moved: nothing to check against, the positions are then taken as valid
            string ft = "?", fc = "?";
            try { ft = Pr.Get(fsel, "frame_type").ToString(); } catch (Exception) { }
            try { fc = ((CelestialBody)Pr.Get(fsel, "selected_celestial")).bodyName; } catch (Exception) { }
            if (ft == "BODY_CENTRED_NON_ROTATING" && fc == body.bodyName) return "";
            return "set Principia's plotting frame to " + body.bodyName + ", non-rotating";
        }
    }
}
