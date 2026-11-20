// THE GRTLS's NZ MODEL AND ITS ALPHA SLEW IN C# -- a line-for-line port of lib/lib_grtls.ks's grtlsFcs (every
// pass of OPS 6's RTLS loop: the alpha command slewed toward ALPCMD, the Nz hold's / the bailout hold's / the ditch's /
// the split-S's alpha by bisection, limiter A) with grtlsAlphaForNz / grtlsNzAt, and of grtlsNz (grtlsSense's Nz, the
// display's, GREEN's / BLUE's phase-5 bank limit), with the entry_predict.ks functions they call: eprRho / eprLogInterp,
// eprMach / eprMachFrom (the pressure from kOS), eprPrMult / eprPrRef / eprHermite, eprCla / eprCda / eprCdaEntry /
// eprPolar / eprBracket / eprHermAt / eprCdFix / eprSbFrac, and lib_grtls's grtlsAeroFix (GR_AERO_FIX). These aero
// functions are the same code as coproc/EntryGuid.cs's (proven there), copied: EntryGuid keeps its own private.
// kOS semantics (EntryGuid's): trig in degrees, CONSTANT:E ^ x = Math.Pow(E, x), LN = Math.Log, MIN / MAX = Math.Min /
// Max, the same order of operations; a value written back through ScalarValue.Create (an int when whole, as kOS).
// THE STATE STAYS kOS's: Load reads every global it uses (the I-loads, the tables, EPR_HINT_RHO / EPR_PR_REF, GR's keys)
// at each call; Commit writes back what the call SET (EPR_HINT_RHO, EPR_PR_REF, GR["acmd"]), finite-checked first: an
// exception leaves kOS untouched. The game reads stay kOS's: the pressure eprPres(altm), ALT:RADAR (the ditch), and the
// ditch's latch grtlsDitch itself (an event + GR writes), whose answer comes in.
// + grtlsAfn (GRAFN): grtlsAlphaForNz on its own, for ECAL's
// ALPHA_UL (FSSR GRALPC 3.4 / 4.1, here from the model): LIST(nzt, altm, vrel, lo, hi, ps) -> the alpha.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public interface IGrEnv
    {
        Structure Get(string name);
        void Set(string name, Structure v);
    }

    public static class GrIn     // GRFCS's input list (the staged lib_grtls.ks's grtlsFcs), and GRNZ's
    {
        public const int DT = 0, ALT = 1, VREL = 2, GAM = 3, BANK = 4, DIT = 5, RADAR = 6, PS = 7, N = 8;
        public const int NZ_AOA = 0, NZ_ALT = 1, NZ_VREL = 2, NZ_PS = 3, NZ_N = 4;
        public const int AFN_NZT = 0, AFN_ALT = 1, AFN_VREL = 2, AFN_LO = 3, AFN_HI = 4, AFN_PS = 5, AFN_N = 6;   // GRAFN's
        public const int MODE_NZ = 0, MODE_FCS = 1, MODE_AFN = 2;
    }

    public class GrCache
    {
        public readonly Dictionary<string, object[]> Tabs = new Dictionary<string, object[]>(StringComparer.OrdinalIgnoreCase);
    }

    public class GrtlsGuid
    {
        public double CE;          // CONSTANT:E (GRSETUP)

        // ---- read every call: constants (entry_predict's model) ----
        double ATM, G0, GAMMA, MASS_K, K_LIFT, K_PAR, PAR_W_WING, PAR_W_FUS, PAR_W_CTL, PAR_SHIFT, PR_SHARE, SB_V, SB_V_FULL;
        bool SB_ON;
        double[][] LIFT_CURVE, LIFT_MACH, WING_PAR_A, WING_PAR_M, FUS_PAR_A, FUS_PAR_M, CTL_PAR_A, CTL_PAR_M, CD_FIX, SB_FRAC,
            PSEUDORE, RHO;
        // ---- lib_grtls's I-loads ----
        bool SS_ON, GR_NZ_ALIM_RTLS, GR_AERO_FIX_ON;
        double GR_NZK = 1;
        double[][] GR_AERO_FIX;
        double SS_NZ, SS_ALPHA, SS_ALPHA_LO, GR_NZ_ITERS, GR_ALPHA_RATE, GR_ALPHA_NZ_LO, GR_DITCH_HDTD, GR_DITCH_TAU, GR_DITCH_K,
            GR_DITCH_ALPMAX, GR_BAIL_ALPMAX, GR_NZ_ALIM;
        // ---- the state (written back when SET) ----
        double HINT_RHO, PR_REF;
        // GR's keys (grtlsFcs): read; acmd written
        public Lexicon GR;
        double G_ALPCMD, G_IPHASE, G_CONT, G_NZC, G_ALPREC, G_ACMD;
        bool fcs, afn;
        double ps;                 // the pressure kOS read, eprPres(altm) at the call's altitude

        public List<string> Dirty = new List<string>();
        HashSet<string> dirtySet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // ================================================================== kOS semantics
        static double Sin(double d) { return Math.Sin(d * Math.PI / 180); }
        static double Cos(double d) { return Math.Cos(d * Math.PI / 180); }
        static double Tan(double d) { return Math.Tan(d * Math.PI / 180); }
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        static double Sqrt(double a) { return Math.Sqrt(a); }
        static double Midval(double a, double b, double c) { return Max(Min(a, Max(b, c)), Min(b, c)); }   // cstMid / grtlsMidval

        public static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue();
            throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
        }
        public static bool Bool(Structure s)
        {
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            throw new InvalidCastException("not a boolean: " + (s == null ? "null" : s.GetType().Name));
        }
        public static double Fin(double x, string n)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("non-finite " + n);
            return x;
        }
        void W(string n) { if (dirtySet.Add(n)) Dirty.Add(n); }

        // ================================================================== Load / Commit
        static double[][] Tab(IGrEnv e, GrCache c, string name)
        {
            var l = e.Get(name) as ListValue;
            if (l == null) throw new InvalidCastException(name + " is not a list");
            object[] hit;
            if (c.Tabs.TryGetValue(name, out hit) && ReferenceEquals(hit[0], l) && (int)hit[1] == l.Count) return (double[][])hit[2];
            var t = new double[l.Count][];
            for (int i = 0; i < l.Count; i++)
            {
                var row = (ListValue)l[i];
                t[i] = new double[row.Count];
                for (int j = 0; j < row.Count; j++) t[i][j] = Num(row[j]);
            }
            c.Tabs[name] = new object[] { l, l.Count, t };
            return t;
        }
        static Structure Key(Lexicon l, string k)
        {
            var key = new StringValue(k);
            if (!l.ContainsKey(key)) throw new KeyNotFoundException("GR has no " + k);
            return l[key];
        }

        public void Load(IGrEnv e, GrCache c, int mode)
        {
            fcs = mode == GrIn.MODE_FCS;
            afn = mode == GrIn.MODE_AFN;
            Func<string, double> N = n => Num(e.Get(n));
            Func<string, bool> B = n => Bool(e.Get(n));
            ATM = N("EPR_ATM"); G0 = N("EPR_G0"); GAMMA = N("EPR_GAMMA"); MASS_K = N("EPR_MASS_K"); K_LIFT = N("EPR_K_LIFT");
            K_PAR = N("EPR_K_PAR"); PAR_W_WING = N("EPR_PAR_W_WING"); PAR_W_FUS = N("EPR_PAR_W_FUS"); PAR_W_CTL = N("EPR_PAR_W_CTL");
            PAR_SHIFT = N("EPR_PAR_SHIFT"); PR_SHARE = N("EPR_PR_SHARE"); SB_V = N("EPR_SB_V"); SB_V_FULL = N("EPR_SB_V_FULL");
            SB_ON = B("EPR_SB_ON");
            LIFT_CURVE = Tab(e, c, "EPR_LIFT_CURVE"); LIFT_MACH = Tab(e, c, "EPR_LIFT_MACH"); WING_PAR_A = Tab(e, c, "EPR_WING_PAR_A");
            WING_PAR_M = Tab(e, c, "EPR_WING_PAR_M"); FUS_PAR_A = Tab(e, c, "EPR_FUS_PAR_A"); FUS_PAR_M = Tab(e, c, "EPR_FUS_PAR_M");
            CTL_PAR_A = Tab(e, c, "EPR_CTL_PAR_A"); CTL_PAR_M = Tab(e, c, "EPR_CTL_PAR_M"); CD_FIX = Tab(e, c, "EPR_CD_FIX");
            SB_FRAC = Tab(e, c, "EPR_SB_FRAC"); PSEUDORE = Tab(e, c, "EPR_PSEUDORE"); RHO = Tab(e, c, "EPR_RHO");
            HINT_RHO = N("EPR_HINT_RHO"); PR_REF = N("EPR_PR_REF");
            SS_ON = B("SS_ON");
            GR_NZK = N("GR_NZK");
            GR_AERO_FIX_ON = B("GR_AERO_FIX_ON"); GR_AERO_FIX = Tab(e, c, "GR_AERO_FIX");
            if (afn) { GR_NZ_ITERS = N("GR_NZ_ITERS"); return; }   // grtlsAlphaForNz's own reads
            if (!fcs) return;
            SS_NZ = N("SS_NZ"); SS_ALPHA = N("SS_ALPHA"); SS_ALPHA_LO = N("SS_ALPHA_LO"); GR_NZ_ITERS = N("GR_NZ_ITERS");
            GR_ALPHA_RATE = N("GR_ALPHA_RATE"); GR_ALPHA_NZ_LO = N("GR_ALPHA_NZ_LO"); GR_DITCH_HDTD = N("GR_DITCH_HDTD");
            GR_DITCH_TAU = N("GR_DITCH_TAU"); GR_DITCH_K = N("GR_DITCH_K"); GR_DITCH_ALPMAX = N("GR_DITCH_ALPMAX");
            GR_BAIL_ALPMAX = N("GR_BAIL_ALPMAX"); GR_NZ_ALIM = N("GR_NZ_ALIM"); GR_NZ_ALIM_RTLS = B("GR_NZ_ALIM_RTLS");
            GR = e.Get("GR") as Lexicon;
            if (GR == null) throw new InvalidCastException("GR is not a lexicon");
            G_ALPCMD = Num(Key(GR, "alpcmd")); G_IPHASE = Num(Key(GR, "iphase")); G_CONT = Num(Key(GR, "cont"));
            G_NZC = Num(Key(GR, "nzc")); G_ALPREC = Num(Key(GR, "alprec")); G_ACMD = Num(Key(GR, "acmd"));
        }

        public Structure Out(string n)     // a written value as kOS holds it
        {
            switch (n.ToUpperInvariant())
            {
                case "EPR_HINT_RHO": return ScalarValue.Create(Fin(HINT_RHO, n));
                case "EPR_PR_REF": return ScalarValue.Create(Fin(PR_REF, n));
                case "GR[ACMD]": return ScalarValue.Create(Fin(G_ACMD, n));
            }
            throw new ArgumentException("not a written value: " + n);
        }

        // every value first (a non-finite one throws here, before any write), then the writes
        public void Commit(IGrEnv e)
        {
            var vals = new List<Structure>(Dirty.Count);
            foreach (var n in Dirty) vals.Add(Out(n));
            for (int i = 0; i < Dirty.Count; i++)
            {
                if (Dirty[i] == "GR[acmd]") GR[new StringValue("acmd")] = vals[i];
                else e.Set(Dirty[i], vals[i]);
            }
        }

        // ================================================================== entry_predict's air / aero model
        double LogInterpE(double[][] tab, double x, double hint, out double iout)
        {
            int n = tab.Length;
            if (x <= tab[0][0]) { iout = 0; return tab[0][1]; }
            if (x >= tab[n - 1][0]) { iout = n - 2; return 0; }
            double i = Max(0, Min(hint, n - 2));
            while (!(i <= 0 || tab[(int)i][0] <= x)) i = i - 1;
            while (!(i >= n - 2 || tab[(int)i + 1][0] >= x)) i = i + 1;
            double a0 = tab[(int)i][0]; double a1 = tab[(int)i + 1][0];
            double y0 = tab[(int)i][1]; double y1 = tab[(int)i + 1][1];
            iout = i;
            if (y0 <= 0 || y1 <= 0) return 0;
            double f = (x - a0) / (a1 - a0);
            return Math.Pow(CE, Math.Log(y0) + f * (Math.Log(y1) - Math.Log(y0)));
        }
        double Rho(double altm)
        {
            double i;
            double r = LogInterpE(RHO, altm, HINT_RHO, out i);
            HINT_RHO = i; W("EPR_HINT_RHO");
            return r;
        }
        double MachFrom(double altm, double vrel, double rh)
        {
            double p = ps;        // kOS: eprPres(altm), read by the hook at the same altm
            if (p <= 0 || rh <= 0) return 0;
            return vrel / Sqrt(GAMMA * p / rh);
        }
        double Mach(double altm, double vrel) { return MachFrom(altm, vrel, Rho(altm)); }
        static double Hermite(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            for (int i = 1; i < n; i++)
            {
                if (keys[i][0] >= x)
                {
                    double x0 = keys[i - 1][0]; double y0 = keys[i - 1][1];
                    double x1 = keys[i][0]; double y1 = keys[i][1];
                    double sp = x1 - x0;
                    double t = (x - x0) / sp;
                    double m0 = keys[i - 1][3] * sp;
                    double m1 = keys[i][2] * sp;
                    double t2 = t * t; double t3 = t2 * t;
                    return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                           + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
                }
            }
            return keys[n - 1][1];
        }
        double PrRef()
        {
            if (PR_REF < 0) { PR_REF = Hermite(PSEUDORE, 1); W("EPR_PR_REF"); }
            return PR_REF;
        }
        double PrMult(double rhov)
        {
            double pr = Hermite(PSEUDORE, rhov) / PrRef();
            if (pr <= 1) return pr;
            return 1 + PR_SHARE * (pr - 1);
        }
        static int Bracket(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return 0;
            if (x >= keys[n - 1][0]) return n;
            for (int i = 1; i < n; i++) if (keys[i][0] >= x) return i;
            return n;
        }
        static double HermAt(double[][] keys, double x, double id)
        {
            if (id <= 0) return keys[0][1];
            int n = keys.Length;
            if (id >= n) return keys[n - 1][1];
            int i = (int)id;
            double x0 = keys[i - 1][0]; double y0 = keys[i - 1][1];
            double x1 = keys[i][0]; double y1 = keys[i][1];
            double sp = x1 - x0;
            double t = (x - x0) / sp;
            double m0 = keys[i - 1][3] * sp;
            double m1 = keys[i][2] * sp;
            double t2 = t * t; double t3 = t2 * t;
            return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                   + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1;
        }
        double[] Polar(double aoa, double mach)
        {
            double a = Max(0, Min(89, aoa));
            double s = Sin(Max(0, Min(90, aoa)));
            double ia = Bracket(LIFT_CURVE, s);
            double im = Bracket(LIFT_MACH, mach);
            double ip = Max(0, ia - PAR_SHIFT);
            double cl = K_LIFT * HermAt(LIFT_CURVE, s, ia) * HermAt(LIFT_MACH, mach, im);
            double pa = K_PAR * (
                PAR_W_WING * HermAt(WING_PAR_A, s, ip) * HermAt(WING_PAR_M, mach, im) +
                PAR_W_FUS * HermAt(FUS_PAR_A, s, ip) * HermAt(FUS_PAR_M, mach, im) +
                PAR_W_CTL * HermAt(CTL_PAR_A, s, ip) * HermAt(CTL_PAR_M, mach, im));
            return new double[] { cl * MASS_K, (cl * Tan(a) + pa) * MASS_K };
        }
        double Cla(double aoa, double mach) { return Polar(aoa, mach)[0]; }
        double Cda(double aoa, double mach) { return Polar(aoa, mach)[1]; }
        double SbFrac(double mach, double spd)
        {
            if (!SB_ON || spd >= SB_V) return 0;
            double ramp = Min(1, (SB_V - spd) / (SB_V - SB_V_FULL));
            var t = SB_FRAC;
            double fr = t[t.Length - 1][1];
            if (mach <= t[0][0])
            {
                fr = t[0][1];
            }
            else if (mach < t[t.Length - 1][0])
            {
                for (int i = 1; i < t.Length; i++)
                {
                    if (mach <= t[i][0])
                    {
                        fr = t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (mach - t[i - 1][0]) / (t[i][0] - t[i - 1][0]);
                        break;
                    }
                }
            }
            return fr * ramp;
        }
        double CdFix(double mach)
        {
            var t = CD_FIX;
            int n = t.Length;
            if (mach <= t[0][0]) return t[0][1];
            if (mach >= t[n - 1][0]) return t[n - 1][1];
            int i = (int)Min(Math.Floor((mach - t[0][0]) / (t[1][0] - t[0][0])), n - 2);
            return t[i][1] + (t[i + 1][1] - t[i][1]) * (mach - t[i][0]) / (t[i + 1][0] - t[i][0]);
        }
        double CdaEntry(double aoa, double mach, double spd)
        {
            return Cda(aoa, mach) * (1 + CdFix(mach)) * (1 + SbFrac(mach, spd));
        }

        // ================================================================== lib_grtls
        // grtlsAeroFix: GR_AERO_FIX's factor at alpha (j 1 = the lift's, 2 = the drag's)
        double AeroFix(double aoa, int j)
        {
            var t = GR_AERO_FIX;
            int n = t.Length;
            if (aoa <= t[0][0]) return t[0][j];
            if (aoa >= t[n - 1][0]) return t[n - 1][j];
            int i = (int)Min(Math.Floor((aoa - t[0][0]) / (t[1][0] - t[0][0])), n - 2);
            return t[i][j] + (t[i + 1][j] - t[i][j]) * (aoa - t[i][0]) / (t[i + 1][0] - t[i][0]);
        }
        // grtlsNzAt: the model's body-normal Nz (g) at alpha, the alpha-free terms given
        double NzAt(double aoa, double mach, double vrel, double pr, double qb)
        {
            double cdv = 0;
            if (SS_ON)
            {
                cdv = Cda(aoa, mach) * (1 + CdFix(mach));
            }
            else
            {
                cdv = CdaEntry(aoa, mach, vrel);
            }
            double cl = Cla(aoa, mach);
            if (GR_AERO_FIX_ON)                 // the GRTLS's measured aero (GR_AERO_FIX)
            {
                cl = cl * AeroFix(aoa, 1);
                cdv = cdv * AeroFix(aoa, 2);
            }
            return (cl * Cos(aoa) + cdv * pr * Sin(aoa)) * qb / G0;
        }
        // grtlsNz (grtls.py's nz_of)
        double NzK(double aoa, double altm, double vrel)
        {
            if (altm >= ATM) return 0.0;
            double rho = Rho(altm);
            double mach = Mach(altm, vrel);
            double pr = PrMult(rho * vrel);
            return NzAt(aoa, mach, vrel, pr, 0.5 * rho * vrel * vrel) * GR_NZK;
        }
        // grtlsAlphaForNz: the alpha in [lo, hi] whose Nz is nzt; hi / lo out of reach
        double AlphaForNz(double nzt, double altm, double vrel, double lo, double hi)
        {
            if (altm >= ATM) return hi;
            nzt = nzt / GR_NZK;                 // the model x GR_NZK reads nzt
            double rho = Rho(altm);
            double mach = Mach(altm, vrel);
            double pr = PrMult(rho * vrel);
            double qb = 0.5 * rho * vrel * vrel;
            if (NzAt(hi, mach, vrel, pr, qb) <= nzt) return hi;
            if (NzAt(lo, mach, vrel, pr, qb) >= nzt) return lo;
            double k = 0;
            while (!(k >= GR_NZ_ITERS))
            {
                double mid = 0.5 * (lo + hi);
                if (NzAt(mid, mach, vrel, pr, qb) > nzt) { hi = mid; } else { lo = mid; }
                k = k + 1;
            }
            return 0.5 * (lo + hi);
        }
        // grtlsFcs: the alpha command slewed toward ALPCMD (6, 4) or the Nz's alpha (5, 7, the ditch, the split-S's 8 / 5).
        // dit: kOS's grtlsDitch(vrel, gam) when its branch is reached (FALSE otherwise); radar: ALT:RADAR when dit
        void FcsK(double dt, double altm, double vrel, double gam, double bank, bool dit, double radar)
        {
            double tgt = G_ALPCMD;
            if (SS_ON && (G_IPHASE == 8 || G_IPHASE == 5))
            {
                tgt = AlphaForNz(SS_NZ, altm, vrel, SS_ALPHA_LO, SS_ALPHA);
            }
            else if (G_IPHASE == 7 && dit)
            {
                double hdc = 0 - Max(GR_DITCH_HDTD, radar / GR_DITCH_TAU);
                tgt = AlphaForNz(Cos(gam) / Cos(bank) + GR_DITCH_K * (hdc - vrel * Sin(gam)) / 9.80665, altm, vrel,
                                 GR_ALPHA_NZ_LO, GR_DITCH_ALPMAX);
            }
            else if (G_IPHASE == 5 || G_IPHASE == 7)
            {
                double amax = GR_BAIL_ALPMAX;
                if (G_IPHASE == 5) { amax = G_ALPREC; }
                tgt = AlphaForNz(G_NZC + Cos(gam) / Cos(bank), altm, vrel, GR_ALPHA_NZ_LO, amax);
            }
            else if (GR_NZ_ALIM > 0 && (G_CONT > 0 || (GR_NZ_ALIM_RTLS && !SS_ON))
                     && (G_IPHASE == 4 || G_IPHASE == 6))
            {
                tgt = Min(tgt, AlphaForNz(GR_NZ_ALIM, altm, vrel, GR_ALPHA_NZ_LO, Max(tgt, GR_ALPHA_NZ_LO)));
            }
            G_ACMD = G_ACMD + Midval(tgt - G_ACMD, -GR_ALPHA_RATE * dt, GR_ALPHA_RATE * dt);
            W("GR[acmd]");
        }

        // ================================================================== the entries
        public double Fcs(double[] d)
        {
            if (!fcs) throw new InvalidOperationException("loaded without GRFCS's state");
            ps = d[GrIn.PS];
            FcsK(d[GrIn.DT], d[GrIn.ALT], d[GrIn.VREL], d[GrIn.GAM], d[GrIn.BANK], d[GrIn.DIT] != 0, d[GrIn.RADAR]);
            return G_ACMD;
        }
        public double Nz(double[] d)
        {
            ps = d[GrIn.NZ_PS];
            return NzK(d[GrIn.NZ_AOA], d[GrIn.NZ_ALT], d[GrIn.NZ_VREL]);
        }
        public double Afn(double[] d)      // lib_grtls's grtlsAfn = grtlsAlphaForNz
        {
            if (!afn) throw new InvalidOperationException("loaded without GRAFN's state");
            ps = d[GrIn.AFN_PS];
            return AlphaForNz(d[GrIn.AFN_NZT], d[GrIn.AFN_ALT], d[GrIn.AFN_VREL], d[GrIn.AFN_LO], d[GrIn.AFN_HI]);
        }
        public double Run(int mode, double[] d)
        {
            return mode == GrIn.MODE_FCS ? Fcs(d) : mode == GrIn.MODE_AFN ? Afn(d) : Nz(d);
        }
    }
}
