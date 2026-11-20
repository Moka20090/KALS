// THE WHOLE PAD
// SEARCH in the KAL/S coprocessor -- E TAL (lib_ascent_etl.ks: the stage-1 predictor and the TAL search), the ARD's pad search
// (lib_ascent_ard.ks: the path, the levels, the rank) and the BLUE / GREEN sweep (lib_ascent_bgl.ks), line for line, kOS
// semantics (trig in degrees as kOS.Safe computes it, kOS's VANG = Vector3d.Angle, MIN / MAX / ROUND / FLOOR / MOD, ^ =
// Math.Pow), on worker threads. This file: the plain value tree the worker reads (KLex: kOS's Lexicon copied on the main
// thread), the constants (every ASC_* the code reads, handed by kOS at each search: the runtime ones too), kOS's math.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    // a kOS Lexicon as plain C#: keys case-insensitive (kOS's), in kOS's insertion order; values double / int / bool / string /
    // Vec3 / List<object> / KLex
    public class KLex
    {
        public readonly List<string> Keys = new List<string>();
        readonly Dictionary<string, object> d = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        public object this[string k]
        {
            get { object o; if (!d.TryGetValue(k, out o)) throw new KeyNotFoundException("key " + k + " missing"); return o; }
            set { if (!d.ContainsKey(k)) Keys.Add(k); d[k] = value; }
        }
        public bool Has(string k) { return d.ContainsKey(k); }
        public int Count { get { return Keys.Count; } }
        public double D(string k) { return Num(this[k], k); }
        public int I(string k) { return (int)Math.Round(D(k)); }
        public bool B(string k) { object o = this[k]; if (o is bool) return (bool)o; return Num(o, k) != 0; }
        public string S(string k) { object o = this[k]; if (o is string) return (string)o; throw new InvalidCastException(k + " is not a string"); }
        public Vec3 V(string k) { object o = this[k]; if (o is Vec3) return (Vec3)o; throw new InvalidCastException(k + " is not a vector"); }
        public KLex L(string k) { object o = this[k]; if (o is KLex) return (KLex)o; throw new InvalidCastException(k + " is not a lexicon"); }
        public List<object> A(string k) { object o = this[k]; if (o is List<object>) return (List<object>)o; throw new InvalidCastException(k + " is not a list"); }
        public double[] DA(string k) { return Dbl(A(k), k); }
        public static double Num(object o, string what)
        {
            if (o is double) return (double)o;
            if (o is int) return (int)o;
            if (o is bool) return (bool)o ? 1 : 0;
            throw new InvalidCastException(what + " is not a number");
        }
        public static double[] Dbl(List<object> l, string what)
        {
            var a = new double[l.Count];
            for (int i = 0; i < l.Count; i++) a[i] = Num(l[i], what);
            return a;
        }
    }

    // kOS.Safe's own math (IL-checked by t62/dap and t62/peg; VANG by t62/pad/cs/AngTest.cs)
    public static class KM
    {
        public static double Sin(double x) { return Math.Sin(x * Math.PI / 180.0); }
        public static double Cos(double x) { return Math.Cos(x * Math.PI / 180.0); }
        public static double Tan(double x) { return Math.Tan(x * Math.PI / 180.0); }
        public static double Asin(double x) { return Math.Asin(x) * 180.0 / Math.PI; }
        public static double Acos(double x) { return Math.Acos(x) * 180.0 / Math.PI; }
        public static double Atan(double x) { return Math.Atan(x) * 180.0 / Math.PI; }
        public static double Atan2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        public static double Vang(Vec3 a, Vec3 b) { return Math.Acos(Math.Min(Math.Max(Vec3.Dot(a.Normalized, b.Normalized), -1), 1)) * 57.29577951308232; }
        public static double Round(double x) { return Math.Round(x); }
        public static double Mod(double a, double b) { return a % b; }
        // asc_grav (lib_ascent_s2.ks): J2 gravity
        public static Vec3 Grav(PadC C, Vec3 rr)
        {
            double r2 = rr.SqrMag;
            double rm = Math.Sqrt(r2);
            double gm = -C.MU / (r2 * rm);
            double k = -1.5 * C.J2 * C.MU * C.R_J2 * C.R_J2 / (r2 * r2 * rm);
            double zz = 5 * rr.Z * rr.Z / r2;
            return new Vec3(gm * rr.X + k * rr.X * (1 - zz), gm * rr.Y + k * rr.Y * (1 - zz), gm * rr.Z + k * rr.Z * (3 - zz));
        }
    }

    // the constants: kOS's ASC_* globals by name (the lexicon lib_ascent_padcs.ks builds at each search)
    public class PadC
    {
        public FtsConsts F = new FtsConsts();        // the fast-time flights' (Fts.cs)
        public double R, MU, J2, R_J2, PL_TO_KSP, ARD_W, KMAX_ABORT, ARD_MDO, ARD_DT, ARD_NEVER;
        // stage 1 (lib_ascent_etl's ASC_S1P_*, the boost tables)
        public double[][] S1P_SRB_C, S1P_SRB_I, S1P_SS_I;
        public double S1P_SRB_MD, S1P_SRB_CAP, S1P_NSRB, S1P_AREF, S1P_ATM_PER_PA;
        public double[] S1P_CDM, S1P_ATM, S1P_B, PPOLY, THET, PSI, QPOLY, THROT;
        public double T_CNS_PITCH_RATE, THETC_DOT_NOM_RAD, SSSL, DSSA, ALTSS;
        // E TAL
        public double ETAL_HF, ETAL_HI, ETAL_TOL, ETAL_SEED_DT, ETAL_DT, TAL_OMS_DELAY, TAL_DUMP; public bool ETAL_SEED_ON;
        // the ARD search
        public double ARD_NBIS, ARD_NBIS_NEAR, ARD_NEAR, ARD_JDT, ARD_JDT1, ARD_NEVER_Q, ARD_PE_IT; public bool ARD_COARSE, ARD_RANK_ON;
        public KLex ARD_PE_SD, ARD_PE_B, ARD_PE_TB;
        public List<string> TAL_SITES = new List<string>();
        // BLUE / GREEN
        public List<object> BGL_SITES, BGL_FP; public double[] BGL_REL, BGL_HB_N, BGL_MG, BGL_YAWS; public double[][] BGL_MT;
        public double BGL_MXK, BGL_MU, BGL_HB0, BGL_HB1, BGL_PUSH, BGL_RELPUSH, BGL_VIPUSH, BGL_RKM, BGL_RAD, BGL_NONE,
            BGL_Y20_PREF, BGL_V2, CNT_DCO, CNT_HDOT_MODE1, CNT_VI_MIN_DROOP;
        public bool BGL_HOLD, CNT_LATE_M2; public double BGL_PUSH2, CNT_LATE_M2_VI; public CntHold.K HOLD;
        public bool BGL_OUTER;

        static double[][] Rows(List<object> l, string what)
        {
            var a = new double[l.Count][];
            for (int i = 0; i < l.Count; i++)
            {
                var r = l[i] as List<object>;
                if (r == null) throw new InvalidCastException(what + " row " + i + " is not a list");
                a[i] = KLex.Dbl(r, what);
            }
            return a;
        }

        // c: the constants lexicon; parts: which parts will run (their constants must be there)
        public PadC(KLex c, bool etl, bool ard, bool bgl)
        {
            foreach (var f in typeof(FtsConsts).GetFields())
            {
                if (f.IsLiteral || f.FieldType != typeof(double)) continue;
                string k = "ASC_" + f.Name;
                if (!c.Has(k)) throw new KeyNotFoundException(k + " missing");
                f.SetValue(F, c.D(k));
            }
            F.LNRHO = c.DA("ASC_ARD_LNRHO"); F.AS = c.DA("ASC_ARD_AS"); F.CDM = c.DA("ASC_ARD_CDM"); F.RTLS_A_MECO = c.DA("ASC_RTLS_A_MECO");
            F.RTLS_THETA_PPD0 = c.D("asc_rtls_th0");     // the RTLS's PPD start pitch (asc_rtls_th0: THETA_PPD0, or the 3-engine one)
            R = c.D("ASC_R"); MU = c.D("ASC_MU"); J2 = c.D("ASC_J2"); R_J2 = c.D("ASC_R_J2"); PL_TO_KSP = c.D("ASC_PL_TO_KSP");
            ARD_W = c.D("ASC_ARD_W"); KMAX_ABORT = c.D("ASC_KMAX_ABORT"); ARD_MDO = c.D("ASC_ARD_MDO"); ARD_DT = c.D("ASC_ARD_DT");
            ARD_NEVER = c.D("ASC_ARD_NEVER");
            TAL_OMS_DELAY = c.D("ASC_TAL_OMS_DELAY"); TAL_DUMP = c.D("ASC_TAL_DUMP");
            foreach (var s in c.A("ASC_TAL_SITES")) TAL_SITES.Add((string)s);
            if (etl || ard)
            {
                S1P_SRB_C = Rows(c.A("ASC_S1P_SRB_C"), "SRB_C"); S1P_SRB_I = Rows(c.A("ASC_S1P_SRB_I"), "SRB_I");
                S1P_SS_I = Rows(c.A("ASC_S1P_SS_I"), "SS_I");
                S1P_SRB_MD = c.D("ASC_S1P_SRB_MD"); S1P_SRB_CAP = c.D("ASC_S1P_SRB_CAP"); S1P_NSRB = c.D("ASC_S1P_NSRB");
                S1P_AREF = c.D("ASC_S1P_AREF"); S1P_ATM_PER_PA = c.D("ASC_S1P_ATM_PER_PA");
                S1P_CDM = c.DA("ASC_S1P_CDM"); S1P_ATM = c.DA("ASC_S1P_ATM"); S1P_B = c.DA("ASC_S1P_B");
                PPOLY = c.DA("ASC_PPOLY"); THET = c.DA("ASC_THET"); PSI = c.DA("ASC_PSI"); QPOLY = c.DA("ASC_QPOLY");
                THROT = c.DA("ASC_THROT"); T_CNS_PITCH_RATE = c.D("ASC_T_CNS_PITCH_RATE");
                THETC_DOT_NOM_RAD = c.D("ASC_THETC_DOT_NOM_RAD"); SSSL = c.D("ASC_SSSL"); DSSA = c.D("ASC_DSSA"); ALTSS = c.D("ASC_ALTSS");
            }
            if (etl)
            {
                ETAL_HF = c.D("ASC_ETAL_HF"); ETAL_HI = c.D("ASC_ETAL_HI"); ETAL_TOL = c.D("ASC_ETAL_TOL");
                ETAL_SEED_ON = c.B("ASC_ETAL_SEED_ON"); ETAL_SEED_DT = c.D("ASC_ETAL_SEED_DT"); ETAL_DT = c.D("ASC_ETAL_DT");
            }
            if (ard)
            {
                ARD_NBIS = c.D("ASC_ARD_NBIS"); ARD_NBIS_NEAR = c.D("ASC_ARD_NBIS_NEAR"); ARD_NEAR = c.D("ASC_ARD_NEAR");
                ARD_JDT = c.D("ASC_ARD_JDT"); ARD_JDT1 = c.D("ASC_ARD_JDT1"); ARD_NEVER_Q = c.D("ASC_ARD_NEVER_Q");
                ARD_PE_IT = c.D("ASC_ARD_PE_IT"); ARD_COARSE = c.B("ASC_ARD_COARSE"); ARD_RANK_ON = c.B("ASC_ARD_RANK_ON");
                ARD_PE_SD = c.L("ASC_ARD_PE_SD"); ARD_PE_B = c.L("ASC_ARD_PE_B"); ARD_PE_TB = c.L("ASC_ARD_PE_TB");
            }
            if (bgl)
            {
                BGL_SITES = c.A("ASC_BGL_SITES"); BGL_FP = c.A("ASC_BGL_FP"); BGL_REL = c.DA("ASC_BGL_REL");
                var hb = c.A("ASC_BGL_HB");
                BGL_HB0 = KLex.Num(hb[0], "HB"); BGL_HB1 = KLex.Num(hb[1], "HB"); BGL_HB_N = KLex.Dbl((List<object>)hb[2], "HB");
                BGL_MG = c.DA("ASC_BGL_MG"); BGL_MT = Rows(c.A("ASC_BGL_MT"), "MT"); BGL_YAWS = c.DA("ASC_BGL_YAWS");
                BGL_MXK = c.D("ASC_BGL_MXK"); BGL_MU = c.D("ASC_BGL_MU"); BGL_PUSH = c.D("ASC_BGL_PUSH");
                BGL_RELPUSH = c.D("ASC_BGL_RELPUSH"); BGL_VIPUSH = c.D("ASC_BGL_VIPUSH"); BGL_OUTER = c.B("ASC_BGL_OUTER");
                BGL_RKM = c.D("ASC_BGL_RKM"); BGL_RAD = c.D("ASC_BGL_RAD"); BGL_NONE = c.D("ASC_BGL_NONE");
                BGL_Y20_PREF = c.D("ASC_BGL_Y20_PREF"); BGL_V2 = c.D("ASC_BGL_V2"); CNT_DCO = c.D("ASC_CNT_DCO");
                CNT_HDOT_MODE1 = c.D("ASC_CNT_HDOT_MODE1"); CNT_VI_MIN_DROOP = c.D("ASC_CNT_VI_MIN_DROOP");
                if (c.Has("ASC_BGL_HOLD") && c.B("ASC_BGL_HOLD"))   // The mode-2 hold predictor (an older kOS lib: the table)
                {
                    BGL_HOLD = true; BGL_PUSH2 = c.D("ASC_BGL_PUSH2");
                    HOLD = new CntHold.K(c.DA("ASC_BGL_HOLD_K"), c.DA("ASC_CNT_LAW_K"), c.A("ASC_CNT_LAW_ENDS"), R);
                    CNT_LATE_M2 = c.B("ASC_CNT_LATE_M2"); CNT_LATE_M2_VI = c.D("ASC_CNT_LATE_M2_VI");
                }
            }
        }

        // the Peg statics (PEG's I-loads; the same values as PEGSETUP / SETUP give them): set on the main thread
        public static void SetPeg(KLex c)
        {
            double dtmax = c.D("ASC_DTMAX"), dtmin = c.D("ASC_DTMIN"), nseg = c.D("ASC_NSEG"), al = c.D("ASC_AL"), etb = c.D("ASC_ETB"),
                kmiss = c.D("ASC_KMISS"), rhomag = c.D("ASC_RHOMAG"), phidot = c.D("ASC_PHIDOT_MAX"), rtphi = c.D("ASC_RTLS_PHIDOT_MAX"),
                epstgo = c.D("ASC_EPSTGO"), dtrd = c.D("ASC_DTRD");
            Peg.DTMAX = dtmax; Peg.DTMIN = dtmin; Peg.NSEG = nseg; Peg.AL = al; Peg.ETB = etb; Peg.KMISS = kmiss; Peg.RHOMAG = rhomag;
            Peg.PHIDOT_MAX = phidot; Peg.RTLS_PHIDOT_MAX = rtphi; Peg.EPSTGO = epstgo; Peg.DTRD = dtrd;
        }

        // a TAL site lexicon (asc_tal_lex) -> TalSite
        public static TalSite Site(KLex tl)
        {
            return new TalSite { Ef = tl.V("ef"), W = tl.D("w"), A = tl.DA("A"), VMIN = tl.D("VMIN"), VMAX = tl.D("VMAX"),
                CRMAX = tl.D("CRMAX"), RDMAG = tl.D("RDMAG"), GAMD = tl.D("GAMD") };
        }
    }
}
