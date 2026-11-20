// ops2q's on-orbit DAP in C#, so it flies every physics tick in the fly-by-wire handler (KalsAddon.O2Dap.cs)
// instead of once a kOS cycle. A 1:1 port of lib/lib_o2dap.ks's o2dTick and its helpers (the same names, the same order
// of operations, kOS's degree trigonometry: COS(x) = Math.Cos(x * PI / 180), ARCTAN2 = Math.Atan2 * 180 / PI), the state
// the fields of kOS's o2qDap lexicon. Pure: vectors in, the jets' command out (no vessel), so the kOS VM checks it call by
// call against the kOS twin (every o2dTick of tests/o2dap_selftest.ks run through both).
// lib_o2dap.ks stays the reference and the fallback (a DLL without O2DAPSET: kOS flies the DAP itself, once a cycle).
// the CSS stick released: Tick brakes the rate to nothing (act RATE until within BRK of rest), then holds the attitude it
// stopped at (lib_o2dap.ks's o2dTick, the same order of operations).
using System;

namespace KalsCoproc
{
    public class O2Dap
    {
        public const double D2R = Math.PI / 180;     // O2D_D2R
        public const double K = 0.15, RMIN = 0.04, RDB = 0.02, TAU = 1.5, ACC = 2, WF = 1, EIG = 2, DET = 0.05, BRK = 0.03, TINY = 1E-9;
        public const double UIMAX = 0.4;             // O2D_UIMAX: the integral trim's cap, deg/s2
        public const double SEEDGT = 2.0;            // O2D_SEEDGT: s after a seeded trim in which the sign guard watches the pitch error
        public const double SEEDGTH = 0.05;          // O2D_SEEDGTH: deg: the seed is dropped when the pitch error grew this much in the seed's direction
        public const double KIFLOOR = 0.02;          // O2D_KIFLOOR: the integral sees the error past this floor, deg (past the deadband)

        // the state (lib_o2dap o2dNew): strings upper case as kOS's
        public string mode = "AUTO", hold = "FREE", rf = "INRTL", act = "FREE", msg = "";
        public Vector3d ref0 = new Vector3d(0, 0, 1), ref1 = new Vector3d(0, 1, 0);   // st["ref"]: fore, top in the basis
        public Vector3d[] bp;                                                         // st["bp"]: null = LIST()
        public Vector3d wf, wt, ax = new Vector3d(0, 0, 1), e, w, u;
        public bool tk;
        public double db = 1.0, rate = 0.5, ea;
        // The hold's gains and integral trim (lib_o2dap st["k" / "tau" / "ki" / "ui"]); ki 0 = no trim, ui in deg/s2 per axis
        public double kGain = K, tauGain = TAU, ki = 0;
        public Vector3d ui;
        // The seeded trim's sign guard: lib_o2dap st["seedt" / "seedsg" / "seede0" / "seeds" / "seeddrop"])
        public double seedT = 0, seedSg = 1, seedE0 = 0, seedDrop = 0;
        public bool seedS = false;
        // o2dSeed: the pitch trim ui.x = v (at most UIMAX) at the ignition; the guard watches it for SEEDGT s
        public void Seed(double v)
        {
            double x = Math.Max(-UIMAX, Math.Min(UIMAX, v));
            ui = new Vector3d(x, ui.y, ui.z);
            seedT = x != 0 ? SEEDGT : 0;
            seedSg = x > 0 ? 1 : -1;
            seedS = false;
            seedDrop = 0;
        }

        static double Cos(double deg) { return Math.Cos(deg * Math.PI / 180); }
        static double Sin(double deg) { return Math.Sin(deg * Math.PI / 180); }
        static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180 / Math.PI; }
        static Vector3d Cr(Vector3d a, Vector3d b) { return Vector3d.Cross(a, b); }
        static double Dt(Vector3d a, Vector3d b) { return Vector3d.Dot(a, b); }
        static double Sg(double x) { return x > 0 ? 1 : -1; }

        // The PROX OPS target's body axes (KalsAddon.Prox.cs sets it every tick while STKP is on): the frame "TGT"; null = INRTL's basis
        public static Vector3d[] TgtBasis;

        // ---- the geometry: g = (pB, vO, the prime vector, the body's spin axis)
        public static Vector3d[] Basis(string md, Vector3d[] g)
        {
            if (md == "TGT" && TgtBasis != null) return TgtBasis;
            Vector3d pB = g[0], vO = g[1];
            if (md == "LVLH")
            {
                Vector3d eu = pB.normalized;
                Vector3d en = Cr(pB, vO).normalized;
                return new[] { eu, Cr(en, eu), en };
            }
            Vector3d sp = g[3];
            Vector3d ez = sp.magnitude > TINY ? sp.normalized : Cr(pB, vO).normalized;
            Vector3d ex = (g[2] - ez * Dt(g[2], ez)).normalized;
            return new[] { ex, Cr(ez, ex), ez };
        }
        public static Vector3d In(Vector3d[] b, Vector3d x) { return new Vector3d(Dt(x, b[0]), Dt(x, b[1]), Dt(x, b[2])); }
        public static Vector3d Out(Vector3d[] b, Vector3d c) { return b[0] * c.x + b[1] * c.y + b[2] * c.z; }
        public static Vector3d Turn(Vector3d x, Vector3d qv)
        {
            double a = qv.magnitude;
            if (a < TINY) return x;
            Vector3d k = qv / a;
            double ad = a / D2R;
            return x * Cos(ad) + Cr(k, x) * Sin(ad) + k * (Dt(k, x) * (1 - Cos(ad)));
        }
        public static Vector3d RotAB(Vector3d a, Vector3d b)
        {
            Vector3d au = a.normalized, bu = b.normalized;
            Vector3d k = Cr(au, bu);
            double sn = k.magnitude, cs = Dt(au, bu);
            if (sn < TINY)
            {
                if (cs > 0) return Vector3d.zero;
                Vector3d pp = Cr(au, new Vector3d(1, 0, 0));
                if (pp.magnitude < 0.1) pp = Cr(au, new Vector3d(0, 1, 0));
                return pp.normalized * Math.PI;
            }
            return k / sn * (Atan2(sn, cs) * D2R);
        }
        public static Vector3d RotV(Vector3d f, Vector3d t, Vector3d fR, Vector3d tR)
        {
            Vector3d n = Cr(t, f), nR = Cr(tR, fR);
            Vector3d sv = 0.5 * (Cr(f, fR) + Cr(t, tR) + Cr(n, nR));
            double cs = (Dt(f, fR) + Dt(t, tR) + Dt(n, nR) - 1) / 2;
            double sn = sv.magnitude;
            if (sn < 1E-7)
            {
                if (cs > 0) return sv;
                Vector3d k = f + fR;
                if (k.magnitude < 0.1) k = t + tR;
                if (k.magnitude < 0.1) k = n + nR;
                return k.normalized * Math.PI;
            }
            return sv / sn * (Atan2(sn, cs) * D2R);
        }
        public static Vector3d Pry(Vector3d w, Vector3d s, Vector3d t, Vector3d f) { return new Vector3d(-Dt(w, s), -Dt(w, f), Dt(w, t)); }

        // ---- one axis, the three as one, the rate back
        public static double Jet(double dw, double au, double tau = TAU)
        {
            if (Math.Abs(dw) <= RDB || au <= TINY) return 0;
            double um = Math.Min(1, ACC / au);
            return Math.Max(-um, Math.Min(um, (dw - RDB * Sg(dw)) / (tau * au)));
        }
        static double JetU(double d, double au, double tau = TAU) { return au <= TINY ? 0 : d / (tau * au); }
        static double JetK(double u, double au) { return au <= TINY ? 0 : Math.Abs(u) / Math.Min(1, ACC / au); }
        public static Vector3d JetV(Vector3d dw, Vector3d au, double tau = TAU)
        {
            double m = dw.magnitude;
            if (m <= RDB) return Vector3d.zero;
            Vector3d dr = dw * (1 - RDB / m);
            Vector3d u = new Vector3d(JetU(dr.x, au.x, tau), JetU(dr.y, au.y, tau), JetU(dr.z, au.z, tau));
            double k = Math.Max(JetK(u.x, au.x), Math.Max(JetK(u.y, au.y), JetK(u.z, au.z)));
            if (k > 1) return u / k;
            return u;
        }
        public static double Back(double e, double db, double rmax, double k = K)
        {
            if (Math.Abs(e) <= db) return 0;
            return Math.Min(rmax, RMIN + k * (Math.Abs(e) - db)) * Sg(e);
        }

        // The hold's INTEGRAL TRIM (lib_o2dap o2dTrim, the same order of operations): per axis, in acceleration space,
        // ui += ki x (the error past DB) x dt (at most UIMAX; no step when that axis's command is at its cap and the error pushes
        // the same way), the trim ui / au added to the command and capped as the law's
        Vector3d Trim(Vector3d e1, Vector3d uu, Vector3d au, double dt)
        {
            double[] ev = { e1.x, e1.y, e1.z }, ua = { uu.x, uu.y, uu.z }, aa = { au.x, au.y, au.z }, ia = { ui.x, ui.y, ui.z };
            for (int i = 0; i < 3; i++)
            {
                if (aa[i] <= TINY) { ia[i] = 0; continue; }
                double um = Math.Min(1, ACC / aa[i]);
                double ed = 0;
                if (Math.Abs(ev[i]) > KIFLOOR) ed = (Math.Abs(ev[i]) - KIFLOOR) * Sg(ev[i]);     // The full error, inside the deadband too
                bool sat = Math.Abs(ua[i]) >= um - 1E-9 && ed * ua[i] > 0;
                if (!sat && dt > 0) ia[i] = Math.Max(-UIMAX, Math.Min(UIMAX, ia[i] + ki * ed * dt));
                ua[i] = Math.Max(-um, Math.Min(um, ua[i] + ia[i] / aa[i]));
            }
            ui = new Vector3d(ia[0], ia[1], ia[2]);
            return new Vector3d(ua[0], ua[1], ua[2]);
        }

        // ---- the crew's reference (world vectors at the moment of the set) into the frame's basis now
        public void RefSet(Vector3d f, Vector3d t, Vector3d[] g)
        {
            Vector3d[] b = Basis(rf, g);
            ref0 = In(b, f); ref1 = In(b, t);
        }
        public Vector3d RefF(Vector3d[] g) { return Out(Basis(rf, g), ref0); }
        public Vector3d RefT(Vector3d[] g) { return Out(Basis(rf, g), ref1); }

        // ---- one tick (o2dTick): g, the orbiter's axes s, t, f (its control point's STAR / TOP / FORE), its turn rate w
        // (rad/s, VCRS sense), the authority au V(pitch, roll, yaw) deg/s2, dt s, the stick V(pitch, roll, yaw) -1..1, the
        // line of sight los (TRACK; zero = none) -> the jets V(pitch, roll, yaw) -1..1
        public bool SwLost;     // SW 01 AUTO DAP LOST (ORBIT) is on the vessel's failure list (the driver sets it each tick)
        public Vector3d Tick(Vector3d[] g, Vector3d s, Vector3d t, Vector3d f, Vector3d wv, Vector3d au, double dt, Vector3d stick, Vector3d los)
        {
            bool outd = Math.Max(Math.Abs(stick.x), Math.Max(Math.Abs(stick.y), Math.Abs(stick.z))) > DET;
            bool dn = false;
            if (SwLost && mode == "AUTO") { mode = "CSS"; msg = "AUTO DAP LOST: CSS"; dn = true; }   // the stick-out branch's twin: CSS until the crew presses AUTO after the fix
            if (outd && mode == "AUTO") { mode = "CSS"; msg = "RHC OUT OF DETENT: CSS"; dn = true; }
            if (mode == "CSS" && hold == "TRACK")
            {   // CSS and TRACK never both: the hold becomes LVLH on the attitude now (o2dHold)
                hold = "LVLH";
                if (rf != "LVLH") { rf = "LVLH"; bp = null; wf = Vector3d.zero; }
                wt = Vector3d.zero;
                RefSet(f, t, g);
                act = "HOLD";
                if (!dn) msg = "";   // The "CSS: TRACK OFF, HOLD LVLH" texts are deleted; the AUTO DAP LOST / RHC OUT OF DETENT text stays as set above
            }
            Vector3d[] b = Basis(rf, g);
            if (dt > 0 && bp != null)
                wf = wf + (RotV(bp[0], bp[1], b[0], b[1]) / dt - wf) * Math.Min(1, dt / WF);
            bp = b;
            Vector3d wr = wf;
            Vector3d uu = Vector3d.zero;
            if (mode == "CSS" && outd)
            {
                ref0 = In(b, f); ref1 = In(b, t);
                act = "RATE";
                Vector3d wl0 = Pry(wv - wr, s, t, f) / D2R;
                Vector3d wc0 = stick * rate;
                uu = JetV(wc0 - wl0, au, tauGain);
                ui = Vector3d.zero;
                e = Vector3d.zero; ea = 0; w = wl0; u = uu;
                return uu;
            }
            if (act == "RATE")
            {
                if (hold == "FREE" || hold == "TRACK") act = hold == "FREE" ? "FREE" : "TRK";
                else
                {   // the stick released: the rate braked to nothing, the attitude it stops at held
                    Vector3d wb = Pry(wv - wr, s, t, f) / D2R;
                    ref0 = In(b, f); ref1 = In(b, t);
                    if (wb.magnitude > BRK)
                    {
                        uu = JetV(-wb, au, tauGain);
                        ui = Vector3d.zero;
                        e = Vector3d.zero; ea = 0; w = wb; u = uu;
                        return uu;
                    }
                    act = "HOLD";
                }
            }
            if (hold == "FREE")
            {
                act = "FREE";
                ui = Vector3d.zero;
                e = Vector3d.zero; ea = 0; w = Pry(wv - wr, s, t, f) / D2R; u = uu;
                return uu;
            }
            Vector3d fR = Out(b, ref0), tR = Out(b, ref1);
            if (hold == "TRACK" && los.magnitude > TINY)
            {
                Vector3d aR = Cr(tR, fR) * ax.x + tR * ax.y + fR * ax.z;
                Vector3d qv = RotAB(aR, los);
                fR = Turn(fR, qv);
                tR = Turn(tR, qv);
                ref0 = In(b, fR); ref1 = In(b, tR);
                if (dt > 0 && tk) wt = wt + (qv / dt - wt) * Math.Min(1, dt / WF);
                tk = true;
                wr = wr + wt;
            }
            Vector3d ev = RotV(f, t, fR, tR);
            double ea1 = ev.magnitude / D2R;
            Vector3d e1 = Pry(ev, s, t, f) / D2R;
            Vector3d wl = Pry(wv - wr, s, t, f) / D2R;
            bool wasMnvr = act == "MNVR";                  // A tick that starts in a MNVR has no trim
            if (act == "MNVR" && ea1 <= db) { act = "HOLD"; msg = "MNVR COMPLETE"; }
            if (act == "MNVR" || ea1 > EIG * db)
                uu = JetV(e1 * (Math.Abs(Back(ea1, db, rate, kGain)) / Math.Max(ea1, TINY)) - wl, au, tauGain);
            else
            {
                Vector3d wc = new Vector3d(Back(e1.x, db, rate, kGain), Back(e1.y, db, rate, kGain), Back(e1.z, db, rate, kGain));
                uu = new Vector3d(Jet(wc.x - wl.x, au.x, tauGain), Jet(wc.y - wl.y, au.y, tauGain), Jet(wc.z - wl.z, au.z, tauGain));
            }
            if (ki > 0 && !wasMnvr && act == "HOLD" && mode == "AUTO")
            {
                if (seedT > 0)                                              // The seed's sign guard
                {
                    if (!seedS) { seedE0 = e1.x; seedS = true; }
                    if ((e1.x - seedE0) * seedSg < -SEEDGTH) { ui = new Vector3d(0, ui.y, ui.z); seedT = 0; seedDrop = 1; }
                    else seedT -= dt;
                }
                uu = Trim(e1, uu, au, dt);
            }
            else { ui = Vector3d.zero; seedT = 0; }
            e = e1; ea = ea1; w = wl; u = uu;
            return uu;
        }
    }
}
