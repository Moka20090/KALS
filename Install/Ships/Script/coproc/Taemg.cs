// The C# coprocessor's TAEM
// guidance, a line-for-line port of lib/taemg.ks (FSSR G4.9) and the Sol reference atmosphere it reads
// (lib/lib_solq_atm.ks's sqa_density). kOS semantics kept: the state is three lexicons (tg, st, g: Lex, case-insensitive
// keys as kOS's LEXICON), SIN / COS / TAN / ARCTAN2 / ARCCOS in degrees, MIDVAL = MAX(MIN(a, b), MIN(MAX(a, b), c)),
// string '=' case-insensitive, '^' = Math.Pow. The constants are NOT typed here: Setup reads the generated kOS files
// (lib/taemg_const.ks, lib/solq_atm_data.ks: GLOBAL NAME IS <literal>.) into the TG_* / SQA_* fields, so a regenerated
// constant file needs no C# change; the globals lib_land sets in flight (the aim, the speedbrake limits, the downmode
// policy) come with each call (KalsAddon TGCYCLE). Checked against taemg_vectors.txt by TaemgCheck.cs.
// Compiles with the .NET Framework's csc (C# 5).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;

namespace KalsCoproc
{
    // a kOS LEXICON: case-insensitive keys; values double / int / bool / string / Lex (or an opaque kOS value)
    public class Lex : Dictionary<string, object>
    {
        public Lex() : base(StringComparer.OrdinalIgnoreCase) { }
        public Lex(Lex o) : base(o, StringComparer.OrdinalIgnoreCase) { }
        public double N(string k) { return Num(Get(k)); }
        public bool B(string k) { return (bool)Get(k); }
        public string S(string k) { return (string)Get(k); }
        public Lex L(string k) { return (Lex)Get(k); }
        object Get(string k)                            // as kOS: a missing key is an error (named here)
        {
            object v;
            if (!TryGetValue(k, out v)) throw new KeyNotFoundException("the lexicon has no key \"" + k + "\"");
            return v;
        }
        public bool Has(string k) { return ContainsKey(k); }
        public static double Num(object o)
        {
            if (o is double) return (double)o;
            if (o is int) return (int)o;
            throw new InvalidCastException("not a number: " + (o == null ? "null" : o.GetType().Name));
        }
    }

    // the generated kOS constant files: GLOBAL NAME IS <number | TRUE | FALSE | "text" | LIST(...) | LEXICON(k, v, ...)>.
    public static class KsConst
    {
        public static Dictionary<string, object> Parse(string text)
        {
            var d = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            foreach (string raw in text.Split('\n'))
            {
                string ln = raw.Trim();
                if (!ln.StartsWith("GLOBAL ", StringComparison.OrdinalIgnoreCase)) continue;
                int isAt = ln.IndexOf(" IS ", StringComparison.OrdinalIgnoreCase);
                string name = ln.Substring(7, isAt - 7).Trim();
                int p = isAt + 4;
                object v = Val(ln, ref p);
                d[name] = v;
            }
            return d;
        }

        static void Ws(string s, ref int p) { while (p < s.Length && s[p] == ' ') p++; }

        static object Val(string s, ref int p)
        {
            Ws(s, ref p);
            if (s[p] == '"') { int e = s.IndexOf('"', p + 1); string r = s.Substring(p + 1, e - p - 1); p = e + 1; return r; }
            if (Kw(s, ref p, "TRUE")) return true;
            if (Kw(s, ref p, "FALSE")) return false;
            if (Kw(s, ref p, "LIST(")) { var l = new List<object>(); Items(s, ref p, l); return l; }
            if (Kw(s, ref p, "LEXICON("))
            {
                var l = new List<object>(); Items(s, ref p, l);
                var x = new Lex();
                for (int i = 0; i + 1 < l.Count; i += 2) x[(string)l[i]] = l[i + 1];
                return x;
            }
            int b = p;
            if (s[p] == '-' || s[p] == '+') p++;
            while (p < s.Length && (char.IsDigit(s[p]) || s[p] == 'e' || s[p] == 'E'
                   || ((s[p] == '-' || s[p] == '+') && (s[p - 1] == 'e' || s[p - 1] == 'E'))
                   || (s[p] == '.' && p + 1 < s.Length && char.IsDigit(s[p + 1])))) p++;
            return double.Parse(s.Substring(b, p - b), NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        static bool Kw(string s, ref int p, string k)
        {
            if (string.Compare(s, p, k, 0, k.Length, StringComparison.OrdinalIgnoreCase) != 0) return false;
            p += k.Length; return true;
        }

        static void Items(string s, ref int p, List<object> l)
        {
            Ws(s, ref p);
            if (s[p] == ')') { p++; return; }
            while (true)
            {
                l.Add(Val(s, ref p));
                Ws(s, ref p);
                if (s[p] == ',') { p++; continue; }
                if (s[p] == ')') { p++; return; }
                throw new FormatException("constant list at " + p + ": " + s.Substring(0, Math.Min(s.Length, 60)));
            }
        }
    }

    public class Taemg
    {
        // ---------------------------------------------------------------- kOS's built-ins (degrees)
        static double SIN(double d) { return Math.Sin(d * Math.PI / 180.0); }
        static double COS(double d) { return Math.Cos(d * Math.PI / 180.0); }
        static double TAN(double d) { return Math.Tan(d * Math.PI / 180.0); }
        static double ARCTAN2(double y, double x) { return Math.Atan2(y, x) * 180.0 / Math.PI; }
        static double ARCCOS(double x) { return Math.Acos(x) * 180.0 / Math.PI; }
        static double MIN(double a, double b) { return Math.Min(a, b); }
        static double MAX(double a, double b) { return Math.Max(a, b); }
        static double ABS(double a) { return Math.Abs(a); }
        static double SQRT(double a) { return Math.Sqrt(a); }
        static double POW(double a, double b) { return Math.Pow(a, b); }
        static bool EQ(string a, string b) { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
        static string ROUNDS(double x)                 // "" + ROUND(x): a whole number (python's str(round(x)))
        {
            double r = Math.Round(x);
            return ((long)r).ToString(CultureInfo.InvariantCulture);
        }

        // ---------------------------------------------------------------- the constants (taemg_const.ks, solq_atm_data.ks)
#pragma warning disable 0649
        public double TG_ALPHA_LIM_MAX, TG_CQG, TG_CSS_DEMAX, TG_CSS_KDEMLIN, TG_CSS_PKQ, TG_CSS_P_DB, TG_CSS_RHC_FULL,
            TG_CSS_R_DB, TG_CUBIC_C3, TG_CUBIC_C4, TG_D2R, TG_DALT_STEP, TG_DEL_H1, TG_DEL_H2, TG_DHOH1, TG_DHOH2, TG_DHOH3,
            TG_DM_AFTER_MAX, TG_DM_AFTER_MIN, TG_DM_FORCE_T, TG_DM_GAIN_MIN, TG_DM_PERSIST_CYC, TG_DM_STRT_STURN_MARGIN,
            TG_DM_T_HAC_MEP, TG_DM_T_HAC_STRT, TG_DNZCDL, TG_DNZCG, TG_DR2K, TG_DR3, TG_DR4, TG_DRFK, TG_DSBCM, TG_DSBDTG,
            TG_DSBIL, TG_DSBLIM, TG_DSBLLS, TG_DSBMAX, TG_DSBNOM, TG_DSBSUP, TG_DTG, TG_EDOTSBG, TG_EDSMGAN, TG_EMAX_DELTA,
            TG_EMEP_GAP_M, TG_EMIN_DELTA, TG_EMOH_C1, TG_EMOH_C2, TG_EN_HD_DB, TG_EN_KIN_MAX, TG_EN_SLOPE_FAR, TG_EOWSBG,
            TG_ESHFMX, TG_EST_BAND, TG_EST_LEAD_CAP, TG_EST_LEAD_K, TG_EST_LEAD_MAX, TG_EST_LEAD_T, TG_EST_T, TG_FT,
            TG_GAMMA_COEF1, TG_GAMMA_COEF2, TG_GDHLL, TG_GDHUL, TG_GDH_H_REF, TG_GEOM_SCALE, TG_GE_LL, TG_GE_UL, TG_GO,
            TG_GPHI, TG_GQB, TG_GQBD, TG_GR, TG_GRDOT, TG_GSBE, TG_GSBI, TG_GS_STEEP_DEG, TG_GY, TG_GYDOT, TG_HALI, TG_HBLEND,
            TG_HDREQG, TG_HGAINSB, TG_HMIN3, TG_H_HAC_MEP, TG_H_HAC_NEP, TG_H_REF1, TG_IPH_ACQ, TG_IPH_HDG, TG_IPH_PREFINAL,
            TG_IPH_STURN, TG_NMI, TG_NZL_ALPHA_RATE, TG_NZ_CMD_LIM, TG_NZ_QB_BAND, TG_NZ_ROLL_MAX, TG_NZ_TOTAL_LIM,
            TG_P2TRNC1, TG_PBGC, TG_PBHC, TG_PBRC, TG_PBRCQ, TG_PHAVGC, TG_PHAVGLL, TG_PHAVGS, TG_PHAVGUL, TG_PHI2C1,
            TG_PHI2C2, TG_PHILM0, TG_PHILM1, TG_PHILM2, TG_PHILM3, TG_PHILM4, TG_PHILMSUP, TG_PHILR1, TG_PHILR2, TG_PHILS,
            TG_PHIM, TG_PSHA3, TG_PSHA_MAX, TG_PSHA_UNWRAP_MIN, TG_PSOHAL, TG_PSRF, TG_PSSTRN, TG_QBARDL, TG_QBC1, TG_QBD_CDEQD, TG_QBD_CQDG, TG_QBC2,
            TG_QBRLL, TG_QBRML, TG_QBRUL, TG_QB_ERROR2, TG_R1, TG_R2, TG_R2MX, TG_RERRLM, TG_RFMN, TG_RFMX, TG_RFTC,
            TG_RMINST, TG_RMOH, TG_ROLL_ACCEL, TG_ROLL_RATE, TG_RTD, TG_SB_AOA_FALLBACK, TG_STN_NZ_DE, TG_STN_NZ_MAX,
            TG_STN_PHI_MAX, TG_STURN_DELTA, TG_TGGS,
            TG_X_AIM_BASE, TG_X_AIM_NOM, TG_YERRLM, TG_Y_RANGE1, TG_Y_RANGE2, TG_ZOOM_DPSAC_GATE, TG_ZOOM_ENERGY_M,
            TG_ZOOM_MACH_BAND, TG_ZOOM_MACH_MIN, TG_ZOOM_NZ, TG_ZOOM_QBAR_BAND, TG_ZOOM_QBAR_MIN, TG_ZOOM_TAPER_M,
            TG_ZOOM_TURN_RATIO;
        public bool TG_CSS_RATE_LIMITS, TG_DM_MEP_SELECTABLE, TG_EN_HD_FLOOR, TG_HDG_CSS_OVERBANK, TG_IS_SOLQ, TG_ROLL_SLEW,
            TG_SB_BLEND_ON, TG_STN_NZ_SCHED;
        public string TG_DM_MSG_MEP, TG_DM_MSG_STRT, TG_DOWNMODE_POLICY;
        public double[] TG_CSS_P_GAIN, TG_CSS_R_DMAX, TG_CSS_R_GAIN, TG_CSS_R_KL, TG_CSS_R_KP, TG_DALT_DH;
        public double[][] TG_FIG317_MEP, TG_FIG317_STRT;
        public double SQA_R_GAS, SQA_MOLAR, SQA_ATM_TOP, SQA_LAT_NOMINAL, SQA_DAY_NOMINAL, SQA_AXBIAS_MEAN;
        public double[][] SQA_PRESS, SQA_TEMP, SQA_TSUN, SQA_LATBIAS, SQA_LATSUN, SQA_AXMULT;
#pragma warning restore 0649

        // the globals taemg.ks keeps (taemg_set_aim's, lib_land's ldSbCap's) and lib_solq_atm.ks's
        public double TG_X_AIM, TG_XALI_X, TG_R2MAX, tgDsbMax;
        public double SQA_TOFF_NOM;
        public bool SQA_ONE_T;
        int sqaLo = 0;

        // Setup: every TG_* / SQA_* field from the parsed constant files (a field missing in them is an error)
        public Taemg(Dictionary<string, object> c)
        {
            foreach (FieldInfo f in typeof(Taemg).GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (!(f.Name.StartsWith("TG_") || f.Name.StartsWith("SQA_"))) continue;
                if (f.Name == "TG_X_AIM" || f.Name == "TG_XALI_X" || f.Name == "TG_R2MAX" || f.Name == "SQA_TOFF_NOM"
                    || f.Name == "SQA_ONE_T") continue;
                if (!c.ContainsKey(f.Name)) throw new KeyNotFoundException("constant " + f.Name + " not in the files");
                object v = c[f.Name];
                if (f.FieldType == typeof(double)) f.SetValue(this, Lex.Num(v));
                else if (f.FieldType == typeof(bool)) f.SetValue(this, (bool)v);
                else if (f.FieldType == typeof(string)) f.SetValue(this, (string)v);
                else if (f.FieldType == typeof(double[])) f.SetValue(this, Arr(v));
                else if (f.FieldType == typeof(double[][]))
                {
                    var l = (List<object>)v; var a = new double[l.Count][];
                    for (int i = 0; i < l.Count; i++) a[i] = Arr(l[i]);
                    f.SetValue(this, a);
                }
                else if (f.FieldType == typeof(Lex)) f.SetValue(this, (Lex)v);
            }
            TG_X_AIM = TG_X_AIM_NOM;
            TG_XALI_X = TG_X_AIM - TG_HALI / TG_TGGS;
            TG_R2MAX = 130000.0 * TG_FT + (TG_X_AIM_BASE - TG_X_AIM);
            tgDsbMax = TG_DSBMAX;
            SQA_TOFF_NOM = sqa_temperature_offset(SQA_LAT_NOMINAL, SQA_DAY_NOMINAL);
            SQA_ONE_T = sqaOneT();
        }

        static double[] Arr(object v)
        {
            var l = (List<object>)v; var a = new double[l.Count];
            for (int i = 0; i < l.Count; i++) a[i] = Lex.Num(l[i]);
            return a;
        }

        // ---------------------------------------------------------------- lib_solq_atm.ks
        static double sqa_curve(double[][] keys, double x)
        {
            int n = keys.Length;
            if (x <= keys[0][0]) return keys[0][1];
            if (x >= keys[n - 1][0]) return keys[n - 1][1];
            int lo = 0;
            int hi = n - 1;
            while (!(hi - lo <= 1))
            {
                int mid = (lo + hi) / 2;
                if (keys[mid][0] <= x) lo = mid; else hi = mid;
            }
            double t1 = keys[lo][0];
            double v1 = keys[lo][1];
            double m1 = keys[lo][3];
            double t2 = keys[hi][0];
            double v2 = keys[hi][1];
            double m2 = keys[hi][2];
            double dt = t2 - t1;
            double t = (x - t1) / dt;
            double tt = t * t;
            double ttt = tt * t;
            return ((2 * ttt - 3 * tt + 1) * v1 + (ttt - 2 * tt + t) * dt * m1
                    + (-2 * ttt + 3 * tt) * v2 + (ttt - tt) * dt * m2);
        }

        double sqa_temperature_offset(double lat, double day)
        {
            double la = ABS(lat);
            double ax = SQA_AXBIAS_MEAN;
            return sqa_curve(SQA_LATBIAS, la) + sqa_curve(SQA_LATSUN, la) * day + ax * sqa_curve(SQA_AXMULT, la);
        }

        double sqa_pressure(double h)
        {
            if (h >= SQA_ATM_TOP) return 0.0;
            return sqa_curve(SQA_PRESS, h) * 1000.0;
        }

        double sqa_temperature(double h)
        {
            return sqa_curve(SQA_TEMP, h) + sqa_curve(SQA_TSUN, h) * SQA_TOFF_NOM;
        }

        bool sqaOneT()
        {
            int n = SQA_PRESS.Length;
            if (n < 2 || SQA_TEMP.Length != n || SQA_TSUN.Length != n) return false;
            for (int i = 0; i < n; i++)
                if (SQA_TEMP[i][0] != SQA_PRESS[i][0] || SQA_TSUN[i][0] != SQA_PRESS[i][0]) return false;
            return true;
        }

        int sqaBr(double x)
        {
            int n = SQA_PRESS.Length;
            if (x <= SQA_PRESS[0][0]) return -1;
            if (x >= SQA_PRESS[n - 1][0]) return n - 1;
            if (SQA_PRESS[sqaLo][0] <= x && x < SQA_PRESS[sqaLo + 1][0]) return sqaLo;
            int lo = 0;
            int hi = n - 1;
            while (!(hi - lo <= 1))
            {
                int mid = (lo + hi) / 2;
                if (SQA_PRESS[mid][0] <= x) lo = mid; else hi = mid;
            }
            sqaLo = lo;
            return lo;
        }

        static double sqaAt(double[][] keys, int b, double x)
        {
            if (b < 0) return keys[0][1];
            if (b >= keys.Length - 1) return keys[keys.Length - 1][1];
            double t1 = keys[b][0];
            double v1 = keys[b][1];
            double m1 = keys[b][3];
            double t2 = keys[b + 1][0];
            double v2 = keys[b + 1][1];
            double m2 = keys[b + 1][2];
            double dt = t2 - t1;
            double t = (x - t1) / dt;
            double tt = t * t;
            double ttt = tt * t;
            return ((2 * ttt - 3 * tt + 1) * v1 + (ttt - 2 * tt + t) * dt * m1
                    + (-2 * ttt + 3 * tt) * v2 + (ttt - tt) * dt * m2);
        }

        public double sqa_density(double h)
        {
            if (!SQA_ONE_T)
            {
                double t0 = sqa_temperature(h);
                if (t0 <= 0.0) return 0.0;
                return sqa_pressure(h) * SQA_MOLAR / (SQA_R_GAS * t0);
            }
            int b = sqaBr(h);
            double t = sqaAt(SQA_TEMP, b, h) + sqaAt(SQA_TSUN, b, h) * SQA_TOFF_NOM;
            if (t <= 0.0) return 0.0;
            double p = 0.0;
            if (h < SQA_ATM_TOP) p = sqaAt(SQA_PRESS, b, h) * 1000.0;
            return p * SQA_MOLAR / (SQA_R_GAS * t);
        }

        // ---------------------------------------------------------------- helpers
        public static double taemg_midval(double a, double b, double c)
        {
            return MAX(MIN(a, b), MIN(MAX(a, b), c));
        }

        static int taemg_bind_of(double x, double lo, double hi)
        {
            double blo = MIN(lo, hi);
            double bhi = MAX(lo, hi);
            if (x < blo) return -1;
            if (x > bhi) return 1;
            return 0;
        }

        public static double taemg_norm180(double x)
        {
            while (!(x <= 180.0)) x = x - 360.0;
            while (!(x > -180.0)) x = x + 360.0;
            return x;
        }

        // ---------------------------------------------------------------- the reference profile
        double taemg_href_jnsq(double drpred)
        {
            if (drpred <= 0.0) return TG_HALI + TG_TGGS * drpred;
            if (drpred >= TG_PBRC) return TG_PBHC + TG_PBGC * (drpred - TG_PBRC);
            return TG_HALI + (TG_TGGS + (TG_CUBIC_C3 + drpred * TG_CUBIC_C4) * drpred) * drpred;
        }

        double taemg_dhdrrf_jnsq(double drpred)
        {
            if (drpred <= 0.0) return TG_TGGS;
            if (drpred >= TG_PBRC) return TG_PBGC;
            return taemg_midval(TG_TGGS + drpred * (2.0 * TG_CUBIC_C3 + 3.0 * TG_CUBIC_C4 * drpred), TG_PBGC, TG_TGGS);
        }

        void taemg_dalt_dh(double h, out double dh, out double slope)
        {
            int n = TG_DALT_DH.Length;
            if (h <= 0.0) { dh = TG_DALT_DH[0]; slope = 0.0; return; }
            if (h >= TG_DALT_STEP * (n - 1)) { dh = TG_DALT_DH[n - 1]; slope = 0.0; return; }
            int k = (int)Math.Floor(h / TG_DALT_STEP);
            double f = (h - TG_DALT_STEP * k) / TG_DALT_STEP;
            dh = TG_DALT_DH[k] + (TG_DALT_DH[k + 1] - TG_DALT_DH[k]) * f;
            slope = (TG_DALT_DH[k + 1] - TG_DALT_DH[k]) / TG_DALT_STEP;
        }

        double taemg_href(double drpred)
        {
            double h = taemg_href_jnsq(drpred);
            if (!TG_IS_SOLQ) return h;
            double dh, sl;
            taemg_dalt_dh(h, out dh, out sl);
            return h - dh;
        }

        double taemg_dhdrrf(double drpred)
        {
            if (!TG_IS_SOLQ) return taemg_dhdrrf_jnsq(drpred);
            double dh, sl;
            taemg_dalt_dh(taemg_href_jnsq(drpred), out dh, out sl);
            return taemg_dhdrrf_jnsq(drpred) * (1.0 - sl);
        }

        double taemg_qbref(double drpred)
        {
            if (drpred >= TG_PBRCQ) return taemg_midval(TG_QBRLL + TG_QBC1 * (drpred - TG_PBRCQ), TG_QBRLL, TG_QBRML);
            return taemg_midval(TG_QBRUL + TG_QBC2 * drpred, TG_QBRLL, TG_QBRUL);
        }

        double taemg_en_of(double drpred)
        {
            double h = taemg_href(drpred);
            double rho = sqa_density(h);
            if (rho <= 0.0) return h + TG_EN_KIN_MAX;
            return h + MIN(taemg_qbref(drpred) / (rho * TG_GO), TG_EN_KIN_MAX);
        }

        double taemg_en_slope(double drpred)
        {
            return (taemg_en_of(drpred + 200.0) - taemg_en_of(drpred - 200.0)) / (2.0 * 200.0);
        }

        double taemg_xhac_of(bool nep)
        {
            double h = nep ? TG_H_HAC_NEP : TG_H_HAC_MEP;
            return TG_X_AIM - h / TG_TGGS;
        }

        double taemg_drpred_of(double rpred)
        {
            return rpred + TG_XALI_X;
        }

        double taemg_rturn_of(double psha, double rf, double r2)
        {
            return rf + TG_R1 * psha + r2 * psha * psha;
        }

        double taemg_rpred2_of(double psha, double rf, double xhac, double r2)
        {
            double arc = (rf * psha + 0.5 * TG_R1 * psha * psha + (1.0 / 3.0) * r2 * POW(psha, 3));
            return arc * TG_D2R - xhac;
        }

        // ---------------------------------------------------------------- GTP: the geometry
        public Lex taemg_gtp(Lex st, double ysgn, double iphase, double rf, double psha_prev, bool nep, double r2, bool seed = true)
        {
            double xhac = taemg_xhac_of(nep);
            double x = st.N("x");
            double y = st.N("y");
            double xcir = xhac - x;
            double signy = y >= 0 ? 1.0 : -1.0;
            if (iphase == 3 && xcir < TG_DR4)
            {
                double rpred0 = SQRT(x * x + y * y);
                var r0 = new Lex();
                r0["rpred"] = rpred0; r0["dpsac"] = 0.0; r0["psha"] = 0.0; r0["rturn"] = rf; r0["rcir"] = 0.0;
                r0["xcir"] = xcir; r0["ycir"] = 0.0; r0["rtan"] = 0.0; r0["rpred2"] = rpred0; r0["xhac"] = xhac;
                return r0;
            }
            double ycir = ysgn * rf - y;
            double rcir = SQRT(xcir * xcir + ycir * ycir);
            double rturn = taemg_rturn_of(psha_prev, rf, r2);
            double rtan = rcir > rturn ? SQRT(rcir * rcir - rturn * rturn) : 0.0;
            double pst = ARCTAN2(ycir, xcir) - ysgn * ARCTAN2(rturn, rtan);
            pst = taemg_norm180(pst);
            double dpsac = taemg_norm180(pst - st.N("psd"));
            double pshan = -pst * ysgn;
            bool at_tangency = (psha_prev > 0.0) && (psha_prev <= TG_PSHA3);
            // the overhead's wrap needs a fresh start or a turn past TG_PSHA_UNWRAP_MIN (lib/taemg.ks)
            bool wrap_ok = seed || psha_prev > TG_PSHA_UNWRAP_MIN;
            if (((!at_tangency) && wrap_ok && (pshan < -1.0 || ysgn != signy)) || (psha_prev > TG_PSHA_UNWRAP_MIN && pshan < psha_prev - 180.0))
            {
                pshan = pshan + 360.0;
            }
            double psha = taemg_midval(pshan, 0.0, TG_PSHA_MAX);
            rturn = taemg_rturn_of(psha, rf, r2);
            double rpred2 = taemg_rpred2_of(psha, rf, xhac, r2);
            if (iphase < 2)
            {
                double mach = st.N("mach");
                double phavg = taemg_midval(TG_PHAVGC - TG_PHAVGS * mach, TG_PHAVGLL, TG_PHAVGUL);
                double rtac = st.N("vh") * st.N("surfv") / (TG_GO * TAN(phavg));
                double arcac = rtac * ABS(dpsac * TG_D2R);
                double a = rtac * (1.0 - COS(dpsac));
                double b = rtan - rtac * ABS(SIN(dpsac));
                double rc = SQRT(a * a + b * b);
                if (rc > rtan) rc = rtan;           // G4.204's Eq 4.4 clamp (the RTLS GTP), not G4.9's; see taem_sim
                rtan = arcac + rc;
            }
            var r = new Lex();
            r["rpred"] = rpred2 + rtan; r["rpred2"] = rpred2; r["rtan"] = rtan; r["dpsac"] = dpsac; r["psha"] = psha;
            r["rturn"] = rturn; r["rcir"] = rcir; r["xcir"] = xcir; r["ycir"] = ycir; r["xhac"] = xhac; r["pst"] = pst;
            return r;
        }

        // ---------------------------------------------------------------- the bank limits
        double taemg_philim_of(double mach, double phase_lim)
        {
            return MIN(MAX(TG_PHILMSUP + TG_PHILS * (mach - TG_PHIM), TG_PHILMSUP), phase_lim);
        }

        double taemg_philim_cap(Lex tg, Lex st)
        {
            double philimit = taemg_philim_of(st.N("mach"), tg.N("philim"));
            if (TG_HDG_CSS_OVERBANK && tg.N("iphase") == TG_IPH_HDG) philimit = tg.N("philim");
            return philimit;
        }

        double taemg_fig317_saving(double psha, string which)
        {
            double nmi = 0;
            if (EQ(which, "mep"))
            {
                double x0 = TG_FIG317_MEP[0][0]; double y0 = TG_FIG317_MEP[0][1];
                double x1 = TG_FIG317_MEP[1][0]; double y1 = TG_FIG317_MEP[1][1];
                double ps = taemg_midval(psha, MIN(x0, x1), MAX(x0, x1));
                nmi = y0 + (y1 - y0) * (x0 - ps) / (x0 - x1);
            }
            else
            {
                double[][] t = TG_FIG317_STRT;
                int n = t.Length;
                if (psha <= t[0][0]) nmi = t[0][1];
                else if (psha >= t[n - 1][0]) nmi = t[n - 1][1];
                else
                {
                    nmi = t[n - 1][1];
                    for (int i = 0; !(i >= n - 1); i = i + 1)
                    {
                        if ((psha >= t[i][0]) && (psha <= t[i + 1][0]))
                        {
                            nmi = (t[i][1] + (t[i + 1][1] - t[i][1]) * (psha - t[i][0]) / (t[i + 1][0] - t[i][0]));
                            break;
                        }
                    }
                }
            }
            return MAX(nmi, 0.0) * TG_NMI * TG_GEOM_SCALE * TG_EN_SLOPE_FAR;
        }

        // ---------------------------------------------------------------- TGINIT
        public Lex taemg_init(Lex st, double ysgn, double rf, double psha0, double phic0, double phic_rate0)
        {
            double qb = 0.0;
            if (st.Has("qbar")) qb = st.N("qbar");
            var tg = new Lex();
            tg["iphase"] = (int)TG_IPH_ACQ; tg["tg_end"] = false; tg["itran"] = false;
            tg["ysgn"] = ysgn; tg["ysturn"] = 0.0; tg["rf"] = rf; tg["r2"] = TG_R2;
            tg["philim"] = TG_PHILM1; tg["philimit"] = TG_PHILM1; tg["phic"] = 0.0; tg["phic_at"] = phic0; tg["isr"] = 0;
            tg["phic_dem"] = phic0; tg["phic_rate"] = phic_rate0;
            tg["css"] = ""; tg["css_why"] = "";
            tg["nzc"] = 0.0; tg["dsbc"] = TG_DSBSUP; tg["dsbi"] = 0.0;
            tg["qbarf"] = qb; tg["qbard"] = 0.0; tg["qbd"] = 0.0;
            tg["psha_prev"] = psha0; tg["first"] = true;
            tg["eow"] = 0.0; tg["en"] = 0.0; tg["en_of_dr"] = 0.0; tg["es"] = 0.0; tg["esturn"] = 0.0;
            tg["est_live"] = 0.0;
            tg["emep"] = 0.0; tg["emax"] = 0.0;
            tg["emin"] = 0.0; tg["est"] = 0.0; tg["eowerror"] = 0.0; tg["deowerr"] = 0.0;
            tg["sturn_peak"] = -1e9; tg["had_sturn"] = false;
            tg["emoh"] = 0.0; tg["ohalrt"] = false;
            tg["bind_en"] = 0; tg["bind_qb"] = 0; tg["bind_rate"] = 0; tg["bind_cmd"] = 0;
            tg["nz_roll_clamped"] = 0;
            tg["alpha_lim_hi"] = TG_ALPHA_LIM_MAX;
            tg["en_xed"] = 0;
            tg["href"] = 0.0; tg["herror"] = 0.0; tg["hdref"] = 0.0; tg["qbref"] = 0.0;
            tg["philim_mach"] = TG_PHILMSUP; tg["rerrc"] = 0.0; tg["rerrc_valid"] = false;
            tg["hac_fallback"] = false;
            tg["qberr"] = 0.0; tg["drpred"] = 0.0; tg["rpred"] = 0.0; tg["mep"] = false;
            tg["alpha_prev"] = TG_SB_AOA_FALLBACK;
            tg["nzl_trim"] = 0.0; tg["nz_err"] = 0.0;
            tg["alpha_rl_bind"] = 0;
            tg["nep"] = true; tg["strt"] = false; tg["dm_why"] = ""; tg["dm_msg"] = "";
            tg["dm_crew"] = "";
            tg["emep_ref"] = 0.0;
            tg["dm_rej"] = ""; tg["drpred_strt"] = 0.0;
            tg["rwy_sw"] = false;
            tg["rwy_strt0"] = false;
            tg["dm_msg0"] = "";
            tg["eowerr_mep"] = 0.0; tg["eowerr_strt"] = 0.0;
            tg["en_mep"] = 0.0; tg["en_strt"] = 0.0;
            tg["mep_avail"] = false; tg["strt_avail"] = false;
            tg["dpsha_mep"] = 0.0; tg["dpsha_strt"] = 0.0; tg["t_to_hac"] = 0.0;
            tg["mep_cyc"] = 0; tg["ohalrt_cyc"] = 0; tg["below_emep_run"] = 0;
            tg["ohalrt_run"] = 0; tg["probe_valid"] = false; tg["ndm"] = 0;
            tg["mep_ever"] = false;
            tg["sb_extrap"] = "";
            return tg;
        }

        // ---------------------------------------------------------------- TGCOMP
        public void taemg_comp(Lex tg, Lex st, Lex g)
        {
            double dr = taemg_drpred_of(g.N("rpred"));
            tg["drpred"] = dr;
            double eow = st.N("h") + POW(st.N("surfv"), 2) / (2.0 * TG_GO);
            tg["eow"] = eow;
            double sh = taemg_midval(TG_EN_SLOPE_FAR * (g.N("rpred2") - TG_R2MAX), 0.0, TG_ESHFMX);
            tg["en_shift"] = sh;
            double en0 = taemg_en_of(dr);
            tg["en_of_dr"] = en0;
            double en = en0 - sh;
            tg["en"] = en;
            tg["es"] = en + TG_STURN_DELTA;
            tg["esturn"] = en + TG_STURN_DELTA;
            if (tg.B("probe_valid")) tg["emep"] = tg["en_mep"];
            else tg["emep"] = en - TG_EMEP_GAP_M;
            tg["emep_ref"] = en - taemg_fig317_saving(g.N("psha"), "mep");
            tg["emax"] = en + TG_EMAX_DELTA;
            tg["emin"] = en - TG_EMIN_DELTA;
            if (tg.B("probe_valid")) tg["emoh"] = tg["en_strt"];
            else tg["emoh"] = tg.N("emep") - (TG_EMOH_C1 + TG_EMOH_C2 * dr);
            tg["emoh_ref"] = en - taemg_fig317_saving(g.N("psha"), "strt");
            tg["mep_avail"] = tg.N("emep") < en;
            tg["strt_avail"] = tg.N("emoh") < en;
            double err_prev = tg.N("eowerror");
            tg["eowerror"] = eow - en;
            if (tg.B("first"))
            {
                tg["deowerr"] = 0.0;
                tg["first"] = false;
            }
            else
            {
                tg["deowerr"] = (tg.N("eowerror") - err_prev) / TG_DTG;
            }
            tg["est_live"] = MAX(en - TG_EST_T * tg.N("deowerr"), en);
            tg["est"] = en + MAX(TG_STURN_DELTA - TG_EST_BAND, 0.0);
            if (tg.N("iphase") == TG_IPH_STURN)
            {
                tg["sturn_peak"] = MAX(tg.N("sturn_peak"), tg.N("eowerror"));
                double lead_max = taemg_midval(TG_EST_LEAD_K * (tg.N("sturn_peak") - TG_STURN_DELTA), TG_EST_LEAD_MAX, TG_EST_LEAD_CAP);
                tg["est"] = tg.N("est") + MIN(MAX(-tg.N("deowerr") * TG_EST_LEAD_T, 0.0), lead_max);
            }
            tg["href"] = taemg_href(dr);
            tg["herror"] = tg.N("href") - st.N("h");
            tg["hdref"] = -st.N("vh") * taemg_dhdrrf(dr);
            tg["qbref"] = taemg_qbref(dr);
            if (tg.N("iphase") == TG_IPH_HDG && g.N("psha") > TG_PSRF)
            {
                double hrefoh = tg.N("href") - taemg_midval(TG_DHOH1 * (dr - TG_DHOH2), 0.0, TG_DHOH3);
                double drf = TG_DRFK * (hrefoh - st.N("h")) / (g.N("psha") * TG_D2R);
                double rflim = ABS(st.N("vh")) * TG_DTG / MAX(g.N("psha") * TG_D2R, 1e-9);
                tg["rf"] = taemg_midval(tg.N("rf") + taemg_midval(drf, -rflim, rflim), TG_RFMN, TG_RFMX);
                double dr2 = TG_DR2K * (tg.N("href") - st.N("h")) / ((g.N("psha") * TG_D2R) * g.N("psha") * g.N("psha"));
                double darc = MAX((POW(g.N("psha"), 3) / 3.0) * TG_D2R, POW(g.N("psha"), 2));
                double lim = ABS(st.N("vh")) * TG_DTG / MAX(darc, 1e-9);
                tg["r2"] = taemg_midval(tg.N("r2") + taemg_midval(dr2, -lim, lim), TG_R2, TG_R2MX);
            }
            double qbard = taemg_midval(TG_CQG * (st.N("qbar") - tg.N("qbarf")), -TG_QBARDL, TG_QBARDL);
            tg["qbarf"] = tg.N("qbarf") + qbard * TG_DTG;
            tg["qbard"] = qbard;
            tg["qbd"] = TG_QBD_CDEQD * tg.N("qbd") + TG_QBD_CQDG * qbard;     // the reference's QBD
            tg["qberr"] = tg.N("qbref") - tg.N("qbarf");
        }

        // ---------------------------------------------------------------- the downmodes (the probe, the automatic choice)
        void taemg_probe(Lex tg, Lex st, Lex g)
        {
            double eow = tg.N("eow");
            Lex gm = taemg_gtp(st, tg.N("ysgn"), tg.N("iphase"), tg.N("rf"), tg.N("psha_prev"), false, tg.N("r2"), tg.B("first"));
            tg["en_mep"] = taemg_en_of(taemg_drpred_of(gm.N("rpred")));
            tg["eowerr_mep"] = eow - tg.N("en_mep");
            tg["dpsha_mep"] = gm.N("psha") - g.N("psha");
            double ys = -tg.N("ysgn");
            Lex gs1 = taemg_gtp(st, ys, tg.N("iphase"), tg.N("rf"), 0.0, tg.B("nep"), tg.N("r2"));
            Lex gs = taemg_gtp(st, ys, tg.N("iphase"), tg.N("rf"), gs1.N("psha"), tg.B("nep"), tg.N("r2"));
            tg["en_strt"] = taemg_en_of(taemg_drpred_of(gs.N("rpred")));
            tg["eowerr_strt"] = eow - tg.N("en_strt");
            tg["dpsha_strt"] = gs.N("psha") - g.N("psha");
            tg["drpred_strt"] = taemg_drpred_of(gs.N("rpred"));
            tg["t_to_hac"] = g.N("rtan") / MAX(st.N("vh"), 1.0);
            tg["probe_valid"] = true;
        }

        bool taemg_dm_accept(Lex tg, string which, List<string> rej)
        {
            if (EQ(which, "mep") && !TG_DM_MEP_SELECTABLE) { rej.Add(which + ":not-selectable"); return false; }
            if (EQ(TG_DOWNMODE_POLICY, "alert")) return true;
            if (!tg.B("probe_valid")) { rej.Add(which + ":stale"); return false; }
            double runc = EQ(which, "strt") ? tg.N("ohalrt_run") : tg.N("below_emep_run");
            if (runc < TG_DM_PERSIST_CYC) { rej.Add(which + ":persist"); return false; }
            double after = EQ(which, "strt") ? tg.N("eowerr_strt") : tg.N("eowerr_mep");
            if (after - tg.N("eowerror") <= TG_DM_GAIN_MIN) { rej.Add(which + ":gain"); return false; }
            if (!EQ(which, "strt") && after < TG_DM_AFTER_MIN) { rej.Add(which + ":insufficient"); return false; }
            if (!EQ(which, "strt") && after > TG_DM_AFTER_MAX) { rej.Add(which + ":overshoot"); return false; }
            double tmin = EQ(which, "strt") ? TG_DM_T_HAC_STRT : TG_DM_T_HAC_MEP;
            if (tg.N("t_to_hac") < tmin) { rej.Add(which + ":timing"); return false; }
            if (EQ(which, "strt") && tg.N("drpred_strt") < TG_RMINST + TG_DM_STRT_STURN_MARGIN) { rej.Add(which + ":no-sturn-room"); return false; }
            return true;
        }

        static string taemg_dm_why(string tag, double h, double psha)
        {
            return tag + " h" + ROUNDS(h) + " psha" + ROUNDS(psha);
        }

        void taemg_crew_act(Lex tg, Lex st, Lex g)
        {
            string req = tg.S("dm_crew");
            tg["dm_crew"] = "";
            if (EQ(req, "strt"))
            {
                if (tg.B("strt"))   // no 'ladder-closed' under MEP
                {
                    tg["strt"] = false;
                    tg["ysgn"] = -tg.N("ysgn");
                    tg["psha_prev"] = 0.0;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("crew:ovhd", st.N("h"), g.N("psha"));
                    tg["dm_msg"] = "";
                    tg["dm_rej"] = "";
                }
                else if (tg.N("iphase") != TG_IPH_ACQ && tg.N("iphase") != TG_IPH_STURN) tg["dm_rej"] = "crew-strt:phase";
                else if (!tg.B("strt_avail")) tg["dm_rej"] = "crew-strt:unavail";
                else
                {
                    tg["strt"] = true;
                    tg["ysgn"] = -tg.N("ysgn");
                    tg["psha_prev"] = 0.0;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("crew:strt", st.N("h"), g.N("psha"));
                    tg["dm_msg"] = TG_DM_MSG_STRT;
                    tg["dm_rej"] = "";
                }
            }
            else if (EQ(req, "mep"))
            {
                if (!tg.B("nep"))
                {
                    tg["nep"] = true;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("crew:nep", st.N("h"), g.N("psha"));
                    tg["dm_msg"] = tg["dm_msg0"];
                    tg["dm_rej"] = "";
                }
                else if (tg.N("iphase") != TG_IPH_ACQ && tg.N("iphase") != TG_IPH_STURN) tg["dm_rej"] = "crew-mep:phase";
                else if (!tg.B("mep_avail")) tg["dm_rej"] = "crew-mep:unavail";
                else
                {
                    tg["nep"] = false;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("crew:mep", st.N("h"), g.N("psha"));
                    tg["dm_msg0"] = tg["dm_msg"];
                    tg["dm_msg"] = TG_DM_MSG_MEP;
                    tg["dm_rej"] = "";
                }
            }
            else
            {
                tg["dm_rej"] = "crew:unknown";
            }
        }

        void taemg_dm_act(Lex tg, Lex st, Lex g)
        {
            if (tg.S("dm_crew") != "") { taemg_crew_act(tg, st, g); return; }
            if (EQ(TG_DOWNMODE_POLICY, "off")) { tg["dm_rej"] = ""; return; }
            if (!tg.B("nep")) { tg["dm_rej"] = "ladder-closed"; return; }
            if (EQ(TG_DOWNMODE_POLICY, "force_mep") || EQ(TG_DOWNMODE_POLICY, "force_strt") || EQ(TG_DOWNMODE_POLICY, "force_both"))
            {
                if (tg.N("ndm") * TG_DTG < TG_DM_FORCE_T) return;
                if (EQ(TG_DOWNMODE_POLICY, "force_both"))
                {
                    if (!tg.B("strt"))
                    {
                        tg["strt"] = true;
                        tg["ysgn"] = -tg.N("ysgn");
                        tg["psha_prev"] = 0.0;
                        tg["first"] = true;
                        tg["dm_why"] = taemg_dm_why("FORCEboth:strt", st.N("h"), g.N("psha"));
                        tg["dm_msg"] = TG_DM_MSG_STRT;
                    }
                    else if (tg.B("nep"))
                    {
                        tg["nep"] = false;
                        tg["first"] = true;
                        tg["dm_why"] = taemg_dm_why("FORCEboth:mep", st.N("h"), g.N("psha"));
                        tg["dm_msg0"] = tg["dm_msg"];
                        tg["dm_msg"] = TG_DM_MSG_MEP;
                    }
                    return;
                }
                if (EQ(TG_DOWNMODE_POLICY, "force_strt"))
                {
                    if (tg.B("strt")) return;
                    tg["strt"] = true;
                    tg["ysgn"] = -tg.N("ysgn");
                    tg["psha_prev"] = 0.0;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("FORCEstrt", st.N("h"), g.N("psha"));
                    tg["dm_msg"] = TG_DM_MSG_STRT;
                }
                else
                {
                    tg["nep"] = false;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("FORCEmep", st.N("h"), g.N("psha"));
                    tg["dm_msg0"] = tg["dm_msg"];
                    tg["dm_msg"] = TG_DM_MSG_MEP;
                }
                return;
            }
            var rej = new List<string>();
            tg["dm_rej"] = "";
            if (tg.N("ohalrt_run") <= 0 && tg.N("below_emep_run") <= 0) { tg["dm_rej"] = "no-alert"; return; }
            if (tg.B("strt")) rej.Add("strt:already");
            else if (!tg.B("ohalrt"))
            {
                if (tg.N("eow") >= tg.N("emoh")) rej.Add("strt:energy");
                else if (!tg.B("strt_avail")) rej.Add("strt:unavail");
                else if (g.N("psha") <= TG_PSOHAL) rej.Add("strt:psha");
                else rej.Add("strt:rpred");
            }
            if ((!tg.B("strt")) && tg.B("ohalrt"))
            {
                if (taemg_dm_accept(tg, "strt", rej))
                {
                    tg["strt"] = true;
                    tg["ysgn"] = -tg.N("ysgn");
                    tg["psha_prev"] = 0.0;
                    tg["first"] = true;
                    tg["dm_why"] = taemg_dm_why("strt", st.N("h"), g.N("psha"));
                    tg["dm_msg"] = TG_DM_MSG_STRT;
                    return;
                }
            }
            if (!tg.B("strt")) rej.Add("mep:no-strt");
            else if (taemg_dm_accept(tg, "mep", rej))
            {
                tg["nep"] = false;
                tg["first"] = true;
                tg["dm_why"] = taemg_dm_why("mep", st.N("h"), g.N("psha"));
                tg["dm_msg0"] = tg["dm_msg"];
                tg["dm_msg"] = TG_DM_MSG_MEP;
                tg["dm_rej"] = string.Join(" ", rej.ToArray());
                return;
            }
            tg["dm_rej"] = string.Join(" ", rej.ToArray());
        }

        // ---------------------------------------------------------------- TGTRAN
        public void taemg_tran(Lex tg, Lex st, Lex g)
        {
            tg["itran"] = false;
            if (tg.N("iphase") == TG_IPH_STURN) tg["had_sturn"] = true;
            if (tg.N("iphase") != TG_IPH_ACQ)
            {
                tg["mep"] = false;
                tg["ohalrt"] = false;
                tg["dm_rej"] = "";
                if (tg.N("iphase") != TG_IPH_STURN) tg["dm_crew"] = "";
            }
            tg["probe_valid"] = false;
            tg["ndm"] = Inc(tg["ndm"]);
            if (tg.B("tg_end")) return;
            if (tg.N("iphase") == TG_IPH_STURN || tg.N("iphase") == TG_IPH_ACQ || tg.N("iphase") == TG_IPH_HDG) taemg_probe(tg, st, g);
            if (tg.N("iphase") == TG_IPH_PREFINAL)
            {
                bool gates = (st.N("h") <= TG_HALI
                              && ABS(tg.N("herror")) < st.N("h") * TG_DEL_H1 - TG_DEL_H2
                              && ABS(st.N("y")) < st.N("h") * TG_Y_RANGE1 - TG_Y_RANGE2
                              && ABS(st.N("gam") - TG_GS_STEEP_DEG) < st.N("h") * TG_GAMMA_COEF1 - TG_GAMMA_COEF2
                              && ABS(tg.N("qberr")) < TG_QB_ERROR2);
                if (gates || st.N("h") < TG_H_REF1)
                {
                    tg["tg_end"] = true;
                    tg["itran"] = true;
                    tg["why_end"] = gates ? "gates" : "forced h<H_REF1";
                }
                return;
            }
            if ((tg.N("iphase") == TG_IPH_HDG && g.N("rpred") < -taemg_xhac_of(tg.B("nep")) + TG_DR3 && ABS(g.N("psha")) < TG_PSHA3)
                    || st.N("h") < TG_HMIN3)
            {
                tg["iphase"] = TG_IPH_PREFINAL;
                tg["itran"] = true;
                tg["philim"] = TG_PHILM3;
                tg["phic"] = tg["phic_at"];
                tg["isr"] = Math.Ceiling(TG_RFTC / TG_DTG);
                return;
            }
            if (tg.N("iphase") == TG_IPH_STURN)
            {
                if (tg.S("dm_crew") != "") taemg_crew_act(tg, st, g);
                if (tg.N("eow") <= tg.N("est"))
                {
                    tg["iphase"] = TG_IPH_ACQ;
                    tg["itran"] = true;
                    tg["philim"] = TG_PHILM1;
                }
                return;
            }
            if (tg.N("iphase") == TG_IPH_ACQ)
            {
                if (tg.N("drpred") > TG_RMINST && g.N("psha") < TG_PSSTRN && tg.N("eow") > tg.N("en") + TG_STURN_DELTA
                        && !(tg.B("had_sturn") && tg.N("deowerr") < 0.0))
                {
                    tg["iphase"] = TG_IPH_STURN;
                    tg["itran"] = true;
                    tg["philim"] = TG_PHILM0;
                    tg["ysturn"] = -tg.N("ysgn");
                    if (tg.N("ysturn") * taemg_norm180(st.N("psd")) < 0.0 && g.N("psha") < 90.0) tg["ysturn"] = -tg.N("ysturn");
                    return;
                }
                tg["mep"] = (tg.N("eow") < tg.N("emep") && tg.B("nep") && tg.B("mep_avail"));
                if (tg.B("mep"))
                {
                    tg["mep_ever"] = true;
                    tg["mep_cyc"] = Inc(tg["mep_cyc"]);
                    tg["below_emep_run"] = Inc(tg["below_emep_run"]);
                }
                else
                {
                    tg["below_emep_run"] = 0;
                }
                tg["ohalrt"] = (tg.N("eow") < tg.N("emoh") && tg.B("strt_avail") && g.N("psha") > TG_PSOHAL && g.N("rpred") > TG_RMOH);
                if (tg.B("ohalrt"))
                {
                    tg["ohalrt_cyc"] = Inc(tg["ohalrt_cyc"]);
                    tg["ohalrt_run"] = Inc(tg["ohalrt_run"]);
                }
                else
                {
                    tg["ohalrt_run"] = 0;
                }
                taemg_dm_act(tg, st, g);
                if (g.N("rcir") < TG_P2TRNC1 * g.N("rturn"))
                {
                    tg["iphase"] = TG_IPH_HDG;
                    tg["itran"] = true;
                    tg["philim"] = TG_PHILM2;
                }
                return;
            }
        }

        static object Inc(object o)                    // x + 1 as kOS: an integer stays an integer
        {
            if (o is int) return (int)o + 1;
            return Lex.Num(o) + 1;
        }

        // ---------------------------------------------------------------- TGNZC: the normal-acceleration command
        bool taemg_zoom_active(Lex tg, Lex st, double nz_cmd, out string why)
        {
            if (!tg.Has("g")) { why = "no geometry"; return false; }
            if (tg.N("iphase") == TG_IPH_STURN) { why = "s-turn"; return false; }   // no ZOOM in the S-turn
            Lex g = tg.L("g");
            bool zoom_on = false;
            if (tg.Has("zoom")) zoom_on = tg.N("zoom") != 0;
            double mach_min = zoom_on ? TG_ZOOM_MACH_MIN : TG_ZOOM_MACH_MIN + TG_ZOOM_MACH_BAND;
            if (st.N("mach") <= mach_min)
            {
                why = "mach"; return false;
            }
            if (tg.N("eow") - tg.N("en") <= TG_ZOOM_ENERGY_M) { why = "energy"; return false; }
            double phi = MAX(taemg_philim_cap(tg, st), 1e-3);
            double r_level = POW(st.N("surfv"), 2) / (TG_GO * TAN(phi));
            double r_need = taemg_rturn_of(g.N("psha"), tg.N("rf"), tg.N("r2"));
            double r_have = r_level;
            if (r_have < TG_ZOOM_TURN_RATIO * r_need) { why = "turn ok"; return false; }
            double qmin = zoom_on ? TG_ZOOM_QBAR_MIN : TG_ZOOM_QBAR_MIN + TG_ZOOM_QBAR_BAND;
            if (st.N("qbar") < qmin) { why = "qbar"; return false; }
            if (ABS(g.N("dpsac")) < TG_ZOOM_DPSAC_GATE) { why = "dpsac"; return false; }
            why = "";
            return true;
        }

        public double taemg_nzc(Lex tg, Lex st)
        {
            double gdh = taemg_midval(TG_GDHUL - (TG_GDHUL - TG_GDHLL) * MIN(st.N("h") / MAX(TG_GDH_H_REF, 1.0), 1.0), TG_GDHLL, TG_GDHUL);
            double hderr = tg.N("hdref") - st.N("hdot");
            double hderrc = hderr + gdh * TG_HDREQG * tg.N("herror");
            double nz = hderrc * gdh * TG_DNZCG;
            double nz_before = nz;
            double enlo = 0;
            double enhi = 0;
            if (tg.N("iphase") <= TG_IPH_HDG)
            {
                enlo = TG_GE_LL * (tg.N("emin") - tg.N("eow"));
                enhi = TG_GE_UL * (tg.N("emax") - tg.N("eow"));
                enhi = enhi + gdh * TG_DNZCG * MAX(hderr - TG_EN_HD_DB, 0.0);
                if (TG_EN_HD_FLOOR) enlo = enlo + gdh * TG_DNZCG * MIN(hderr + TG_EN_HD_DB, 0.0);   // off since 10-18
                if (enlo > enhi)
                {
                    tg["en_xed"] = 1;
                    nz = MAX(nz, enlo);
                }
                else
                {
                    tg["en_xed"] = 0;
                    nz = taemg_midval(nz, enlo, enhi);
                }
            }
            else
            {
                tg["en_xed"] = 0;
            }
            if (tg.N("iphase") > TG_IPH_HDG) tg["bind_en"] = 0;
            else if (tg.N("en_xed") != 0) tg["bind_en"] = nz_before < enlo ? -1 : 0;
            else tg["bind_en"] = taemg_bind_of(nz_before, enlo, enhi);
            double qb_nz = TG_GQB * (tg.N("qbarf") - tg.N("qbref")) + TG_GQBD * tg.N("qbd");     // + G4.9's rate term
            nz_before = nz;
            nz = taemg_midval(nz, qb_nz - TG_NZ_QB_BAND, qb_nz + TG_NZ_QB_BAND);
            tg["bind_qb"] = taemg_bind_of(nz_before, qb_nz - TG_NZ_QB_BAND, qb_nz + TG_NZ_QB_BAND);
            nz_before = nz;
            string zwhy;
            bool za = taemg_zoom_active(tg, st, nz, out zwhy);
            tg["zoom"] = za ? 1 : 0;
            tg["zoom_why"] = zwhy;
            if (za)
            {
                double frac = 1.0;
                if (TG_ZOOM_TAPER_M > 0.0) frac = taemg_midval((tg.N("eowerror") - TG_ZOOM_ENERGY_M) / TG_ZOOM_TAPER_M, 0.0, 1.0);
                nz = MAX(nz, nz + frac * (TG_ZOOM_NZ - nz));
                tg["zoom_frac"] = frac;
            }
            else
            {
                tg["zoom_frac"] = 0.0;
            }
            tg["bind_zoom"] = nz > nz_before ? -1 : 0;
            double dnzcd_raw = (nz - tg.N("nzc")) * TG_CQG;
            double dnzcd = taemg_midval(dnzcd_raw, -TG_DNZCDL, TG_DNZCDL);
            tg["bind_rate"] = taemg_bind_of(dnzcd_raw, -TG_DNZCDL, TG_DNZCDL);
            double nzc_raw = tg.N("nzc") + dnzcd * TG_DTG;
            tg["nzc"] = taemg_midval(nzc_raw, -TG_NZ_CMD_LIM, TG_NZ_CMD_LIM);
            tg["bind_cmd"] = taemg_bind_of(nzc_raw, -TG_NZ_CMD_LIM, TG_NZ_CMD_LIM);
            tg["gdh"] = gdh;
            return tg.N("nzc");
        }

        // ---------------------------------------------------------------- TGSBC: the speedbrake command
        public double taemg_sbc(Lex tg, Lex st)
        {
            double dsbcll = taemg_midval(TG_DSBSUP + TG_DSBLLS * (st.N("mach") - TG_DSBCM), 0.0, TG_DSBSUP);
            double dsbcul = MAX(TG_DSBSUP, tgDsbMax);
            double blend = 0.0;
            double dsbc = 0.0;
            if (st.N("mach") > TG_DSBCM)
            {
                dsbc = TG_DSBSUP;
            }
            else if (tg.N("iphase") == TG_IPH_STURN)
            {
                dsbc = TG_DSBLIM;
            }
            else
            {
                double dsbe = TG_GSBE * tg.N("qberr");
                if (TG_SB_BLEND_ON) blend = taemg_midval(TG_HGAINSB * (st.N("h") - TG_HBLEND), 0.0, 1.0);
                double accd = 0.0;
                if (st.Has("acc_drag")) accd = st.N("acc_drag");
                double edteri = st.N("surfv") * (taemg_en_slope(tg.N("drpred")) - accd / TG_GO);
                if (!tg.Has("edtero")) tg["edtero"] = edteri;
                tg["edtero"] = (1.0 - TG_EDSMGAN) * tg.N("edtero") + TG_EDSMGAN * edteri;
                double e_leg = TG_EOWSBG * (tg.N("eow") - tg.N("en")) + TG_EDOTSBG * tg.N("edtero");
                double raw = 0;
                if (blend > 0.0) raw = TG_DSBNOM + blend * e_leg - (1.0 - blend) * (dsbe + tg.N("dsbi"));
                else raw = TG_DSBNOM - dsbe - tg.N("dsbi");
                if ((raw > dsbcll) && (raw < dsbcul))
                {
                    tg["dsbi"] = taemg_midval(tg.N("dsbi") + TG_GSBI * tg.N("qberr") * TG_DTG, -TG_DSBIL, TG_DSBIL);
                }
                if (blend > 0.0) dsbc = (TG_DSBNOM + blend * e_leg - (1.0 - blend) * (dsbe + tg.N("dsbi")));
                else dsbc = TG_DSBNOM - dsbe - tg.N("dsbi");
            }
            tg["sb_blend"] = blend;
            double step_lim = TG_DSBDTG * TG_DTG;
            dsbc = tg.N("dsbc") + taemg_midval(dsbc - tg.N("dsbc"), -step_lim, step_lim);
            tg["dsbc"] = taemg_midval(dsbc, dsbcll, dsbcul);
            return tg.N("dsbc");
        }

        // ---------------------------------------------------------------- TGPHIC: the bank command
        public double taemg_phic(Lex tg, Lex st, Lex g)
        {
            double philimit = taemg_philim_cap(tg, st);
            tg["philim_mach"] = philimit;
            double phi0 = tg.N("phic");
            tg["hac_fallback"] = false;
            tg["rerrc"] = g.N("rcir") - g.N("rturn");
            tg["rerrc_valid"] = (tg.N("iphase") == TG_IPH_HDG);
            if (tg.N("iphase") == TG_IPH_STURN)
            {
                tg["phic"] = tg.N("ysturn") * philimit;
            }
            else if (tg.N("iphase") == TG_IPH_ACQ)
            {
                tg["phic"] = TG_GPHI * g.N("dpsac");
            }
            else if (tg.N("iphase") == TG_IPH_HDG)
            {
                double rerrc = tg.N("rerrc");
                if (rerrc > TG_RERRLM)
                {
                    tg["hac_fallback"] = true;
                    philimit = MIN(philimit, TG_PHILM1);
                    tg["phic"] = TG_GPHI * g.N("dpsac");
                }
                else
                {
                    double rdot = -(g.N("xcir") * st.N("xdot") + g.N("ycir") * st.N("ydot")) / g.N("rcir");
                    double phip2c = ((POW(st.N("vh"), 2) - POW(rdot, 2)) * TG_RTD / (TG_GO * MAX(g.N("rturn"), 1.0)));
                    phip2c = phip2c * (TG_PHI2C1 - TG_PHI2C2 * phip2c);
                    double rdotrf = (-st.N("vh") * (TG_R1 + 2.0 * tg.N("r2") * g.N("psha")) * TG_RTD / MAX(g.N("rturn"), 1.0));
                    tg["phic"] = tg.N("ysgn") * MAX(phip2c + TG_GR * rerrc + TG_GRDOT * (rdot - rdotrf), 0.0);
                }
            }
            else if (tg.N("iphase") == TG_IPH_PREFINAL)
            {
                double yerrc = -TG_GY * taemg_midval(st.N("y"), -TG_YERRLM, TG_YERRLM);
                tg["phic"] = yerrc - TG_GYDOT * st.N("ydot");
                if (tg.N("isr") > 0)
                {
                    tg["phic"] = phi0 + (tg.N("phic") - phi0) / tg.N("isr");
                    tg["isr"] = Dec(tg["isr"]);
                }
                tg["philim"] = taemg_midval(TG_PHILM3, TG_PHILM4, TG_PHILR1 * ABS(tg.N("phic")) + TG_PHILR2);
            }
            double arg = st.N("costh") / MAX(TG_NZ_ROLL_MAX - tg.N("nzc"), 1e-3);
            tg["nz_roll_clamped"] = ABS(arg) > 1.0 ? 1 : 0;
            double phinzlim = ARCCOS(MAX(-1.0, MIN(1.0, arg)));
            philimit = MIN(philimit, phinzlim);
            tg["philimit"] = philimit;
            tg["phic_at"] = taemg_midval(tg.N("phic"), -philimit, philimit);
            if (tg.N("iphase") == TG_IPH_STURN && TG_STN_NZ_SCHED)
            {   // the S-turn as a brake: the bank that holds the normal law's vertical lift at the scheduled load
                double vz = st.N("costh") + tg.N("nzc") * COS(philimit);
                double c = MAX(MIN(vz / taemg_stn_nz(tg), 1.0), COS(TG_STN_PHI_MAX));
                tg["phic_at"] = tg.N("ysturn") * ARCCOS(c);
            }
            return tg.N("phic_at");
        }

        // the S-turn's total load, g: 1 at EST, TG_STN_NZ_MAX at TG_STN_NZ_DE above it
        public double taemg_stn_nz(Lex tg)
        {
            return 1.0 + (TG_STN_NZ_MAX - 1.0) * taemg_midval((tg.N("eow") - tg.N("est")) / TG_STN_NZ_DE, 0.0, 1.0);
        }

        static object Dec(object o)
        {
            if (o is int) return (int)o - 1;
            return Lex.Num(o) - 1;
        }

        public double taemg_nz_total(Lex tg, Lex st)
        {
            double cosphi = MAX(MAX(COS(tg.N("phic_at")), 0.20), COS(tg.N("philimit")));     // no hold beyond the limit
            double nz_total = taemg_midval(st.N("costh") / cosphi + tg.N("nzc"), -TG_NZ_TOTAL_LIM, TG_NZ_TOTAL_LIM);
            if (tg.N("iphase") == TG_IPH_STURN && TG_STN_NZ_SCHED)    // the S-turn's scheduled load (taemg_phic's bank)
                nz_total = taemg_midval(taemg_stn_nz(tg), -TG_NZ_TOTAL_LIM, TG_NZ_TOTAL_LIM);
            tg["nz_total"] = nz_total;
            return nz_total;
        }

        public static void taemg_bank_slew(double cur, double tgt, double rate, double dt, double rate_lim, double accel_lim,
                                           out double bank, out double rateOut)
        {
            double err = tgt - cur;
            double want = err / MAX(dt, 0.001);
            want = MAX(-rate_lim, MIN(rate_lim, want));
            double vmax = SQRT(2.0 * accel_lim * ABS(err));
            want = MAX(-vmax, MIN(vmax, want));
            want = MAX(rate - accel_lim * dt, MIN(rate + accel_lim * dt, want));
            bank = cur + want * dt;
            rateOut = want;
        }

        static double taemg_css_lin(double x, double[] sch)
        {
            if (x <= sch[0]) return sch[1];
            if (x >= sch[2]) return sch[3];
            return sch[1] + (sch[3] - sch[1]) * (x - sch[0]) / (sch[2] - sch[0]);
        }
        double taemg_css_pitch(double mach)
        {
            double x = TG_CSS_RHC_FULL - TG_CSS_P_DB;
            return MIN(TG_CSS_DEMAX, (TG_CSS_KDEMLIN + TG_CSS_PKQ * x) * x) * taemg_css_lin(mach, TG_CSS_P_GAIN);
        }
        double taemg_css_roll(double mach)
        {
            double x = TG_CSS_RHC_FULL - TG_CSS_R_DB;
            double shp = MIN(taemg_css_lin(mach, TG_CSS_R_DMAX),
                             (taemg_css_lin(mach, TG_CSS_R_KL) + taemg_css_lin(mach, TG_CSS_R_KP) * x) * x);
            return shp * taemg_css_lin(mach, TG_CSS_R_GAIN);
        }
        public void taemg_roll_lim(double mach, out double rate, out double accel)
        {
            if (!TG_CSS_RATE_LIMITS) { rate = TG_ROLL_RATE; accel = TG_ROLL_ACCEL; return; }
            double rt = MIN(TG_ROLL_RATE, taemg_css_roll(mach));
            rate = rt; accel = TG_ROLL_ACCEL * rt / TG_ROLL_RATE;
        }
        public double taemg_alpha_rate(double mach)
        {
            if (!TG_CSS_RATE_LIMITS) return TG_NZL_ALPHA_RATE;
            return MIN(TG_NZL_ALPHA_RATE, taemg_css_pitch(mach));
        }

        // ---------------------------------------------------------------- one guidance pass
        // ---------------------------------------------------------------- the GRTLS's TAEM display (lib_grtls.ks)
        // TAEM's state on the display's HAC before TAEM flies, one call a GRTLS pass: mode "pre" = grtlsTgPre (phases 6 / 5:
        // the state built at the first call, tg null), "p4" = phase 4's pass (GTP, TGCOMP, ECAL's TGCOMP 2.1.1), each then
        // grtlsTgDm (the probe, the MEP and OHALRT lines, a crew press). -> tg, gp, ev ("" / "ok" / "rej": the press taken or
        // refused), req (the press), ysgn (GR's HAC side when a press took)
        public Lex taemg_grtls(string mode, Lex tg, Lex st, double grYsgn, double bank, double brate, bool ecal, double hdot,
                               bool ovhd, double ecompg)
        {
            var res = new Lex();
            Lex g;
            double eadj = 0.0;
            if (EQ(mode, "pre"))
            {
                double same = st.N("y") >= 0.0 ? 1.0 : -1.0;
                double ys = ovhd ? -same : same;               // phase 4's rule until a side is set
                if (grYsgn != 0) ys = grYsgn;
                if (tg == null)
                {
                    double p0 = taemg_gtp(st, ys, TG_IPH_ACQ, TG_RFMX, 0.0, true, TG_R2).N("psha");
                    tg = taemg_init(st, ys, TG_RFMX, taemg_gtp(st, ys, TG_IPH_ACQ, TG_RFMX, p0, true, TG_R2).N("psha"), -bank, -brate);
                }
                if (tg.N("ysgn") != ys)                        // the rule's side moved with y's sign: the HAC turn afresh
                {
                    tg["ysgn"] = ys;
                    tg["psha_prev"] = 0.0;
                }
                g = taemg_gtp(st, tg.N("ysgn"), TG_IPH_ACQ, tg.N("rf"), tg.N("psha_prev"), tg.B("nep"), tg.N("r2"));
                tg["psha_prev"] = g.N("psha");
                taemg_comp(tg, st, g);
                tg["ecompk"] = 0.0;                            // the raw EOW (no TGCOMP 2.1.1 before phase 4)
            }
            else
            {
                g = taemg_gtp(st, tg.N("ysgn"), TG_IPH_ACQ, tg.N("rf"), tg.N("psha_prev"), tg.B("nep"), tg.N("r2"));
                tg["psha_prev"] = g.N("psha");
                taemg_comp(tg, st, g);
                if (ecal) tg["eow"] = tg.N("eow") + ecompg * tg.N("eow") * hdot;   // TGCOMP 2.1.1 (ECAL)
                tg["ecompk"] = ecal ? ecompg : 0.0;
                eadj = ecal ? hdot : 0.0;
            }
            taemg_probe(tg, st, g);
            tg["mep"] = tg.N("eow") < tg.N("emep") && tg.B("nep") && tg.B("mep_avail");
            tg["ohalrt"] = tg.N("eow") < tg.N("emoh") && tg.B("strt_avail") && g.N("psha") > TG_PSOHAL && g.N("rpred") > TG_RMOH;
            res["ev"] = "";
            res["req"] = "";
            if (tg.S("dm_crew") != "")
            {
                res["req"] = tg.S("dm_crew");
                taemg_crew_act(tg, st, g);
                if (tg.S("dm_rej") == "")
                {
                    res["ysgn"] = tg.N("ysgn");
                    g = taemg_gtp(st, tg.N("ysgn"), TG_IPH_ACQ, tg.N("rf"), tg.N("psha_prev"), tg.B("nep"), tg.N("r2"));
                    tg["psha_prev"] = g.N("psha");
                    taemg_comp(tg, st, g);
                    if (eadj != 0) tg["eow"] = tg.N("eow") + ecompg * tg.N("eow") * eadj;
                    taemg_probe(tg, st, g);
                    res["ev"] = "ok";
                }
                else res["ev"] = "rej";
            }
            res["tg"] = tg;
            res["gp"] = g;
            return res;
        }

        // range control's EOW - EN in phase 5 (lib_grtls grtlsRcE5): a throwaway TGINIT + GTP + TGCOMP on phase 5's HAC
        // (side ys, its psha); nothing kept
        public double taemg_grtls_e5(Lex st, double ys, double psha)
        {
            Lex tg = taemg_init(st, ys, TG_RFMX, psha, 0.0, 0.0);
            Lex g = taemg_gtp(st, ys, TG_IPH_ACQ, tg.N("rf"), psha, tg.B("nep"), tg.N("r2"));
            taemg_comp(tg, st, g);
            return tg.N("eow") - tg.N("en");
        }

        public Lex taemg_cycle(Lex tg, Lex st)
        {
            Lex g = taemg_gtp(st, tg.N("ysgn"), tg.N("iphase"), tg.N("rf"), tg.N("psha_prev"), tg.B("nep"), tg.N("r2"), tg.B("first"));
            tg["psha_prev"] = g["psha"];
            tg["g"] = g;
            taemg_comp(tg, st, g);
            taemg_tran(tg, st, g);
            taemg_nzc(tg, st);
            taemg_sbc(tg, st);
            double phic_prev = tg.N("phic_at");
            taemg_phic(tg, st, g);
            tg["phic_dem"] = tg["phic_at"];
            if (TG_ROLL_SLEW)
            {
                double rl0, rl1;
                taemg_roll_lim(st.N("mach"), out rl0, out rl1);
                double b, r;
                taemg_bank_slew(phic_prev, tg.N("phic_dem"), tg.N("phic_rate"), TG_DTG, rl0, rl1, out b, out r);
                tg["phic_at"] = b;
                tg["phic_rate"] = r;
            }
            else
            {
                tg["phic_rate"] = (tg.N("phic_at") - phic_prev) / TG_DTG;
            }
            taemg_nz_total(tg, st);
            return g;
        }
    }
}
