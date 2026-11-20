// lib/lib_ascent_css.ks's Law A tick
// (ascCssTickA with ascCssStick, ascCssKb, ascCssShape, ascCssCapOk, ascCssCatch, ascCssHeld, ascCssFrame, ascCssKind,
// ascCssFf, ascCssFm, ascCssHyCatch, ascCssHyRate, ascCssTg, ascCssErr, ascCssPI, ascCssPS, ascCssSh, ascCssShOff,
// ascCssClip and ascCssRow's Law A row; ascCss["tb"] / ["tb3"] / ["ks"] / ["dc"], ascCssCoup's, read only) in C#, line for
// line, with kOS's semantics
// (as Grd.cs: every number a double, MIN / MAX / ABS / MOD / ROUND as kOS's, a number in a string as kOS prints it):
//   - vectors through KSP's Vector3d as kOS's Vector does (VDOT / VCRS / VXCL / VANG / :MAG / + / - / * a scalar);
//   - DIRECTIONS as kOS.dll does them (read from its IL): a Direction is a UnityEngine.Quaternion; FOREVECTOR =
//     rotation * (Vector3)Vector3d.forward, TOPVECTOR = rotation * Vector3.up, STARVECTOR = rotation * Vector3.right
//     (each Vector3 back as doubles); Direction * Direction = Quaternion * Quaternion; :INVERSE = Quaternion.Inverse;
//     LOOKDIRUP(v, u) = Quaternion.LookRotation((Vector3)v, (Vector3)u); R(x, y, z) = Quaternion.Euler((Vector3)(x, y,
//     z)). The products are Unity's managed operators; Inverse, LookRotation and Euler (native in Unity) come through
//     the env (the addon passes Unity's own calls, the offline VM managed twins).
// THE STATE IS kOS's: the ascCss lexicon is read at the tick's start (Load) and every key the tick writes goes back at
// the end (Commit, in the order kOS first writes them; ascCss["i"] and the ascCss["kb"] lists element by element, in
// place, as kOS's SET ii[i] / SET s[k] do). Nothing is written before the end: an exception leaves kOS untouched and
// kOS's ascCssTickAK can fly any tick. The lexicon is case-insensitive, as kOS's: ascCssCapOk's "hpT" and ascCssHeld's
// "hpt" are one key (one field here, Hold.T).
// THE GAME I/O STAYS kOS's (lib_ascent_css.ks ascCsIn / ascCsTick): the reads come in as one list (AscIn); out come the
// three commands (kOS hands them to ADDONS:KALS:FBW3), an action code (1 the return's stop: kOS runs ascCssStop with the
// text; 2 kOS writes the tick's csv row after it (ascCssRow with the ten values); 4 the text to LOG to the csv).
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using UnityEngine;

namespace KalsCoproc
{
    public interface IAscEnv
    {
        Structure Get(string name);                         // a kOS global
        Vector3d Vec(Structure s);
        Structure MakeVec(Vector3d v);
        Quaternion Rot(Structure dir);                      // a Direction's rotation
        Structure MakeDir(Quaternion q);                    // a new Direction
        Quaternion Inverse(Quaternion q);
        Quaternion Look(Vector3d fwd, Vector3d up);         // LOOKDIRUP
        Quaternion Euler(Vector3d e);                       // R()
    }

    public static class AscIn       // the reads kOS passes, in this order (lib_ascent_css.ks ascCsIn)
    {
        public const int TIME = 0, FACING = 1, W = 2, VS = 3, VO = 4, UP = 5, PILOT = 6, AUTH = 7, MET = 8, DYNP = 9, N = 10;
    }

    public class AscCss
    {
        const double ATMTOKPA = 101.325;                // CONSTANT:ATMTOKPA

        // ------------------------------------------------------------ kOS's arithmetic (as Grd.cs)
        static double Min(double a, double b) { return Math.Min(a, b); }
        static double Max(double a, double b) { return Math.Max(a, b); }
        static double Abs(double a) { return Math.Abs(a); }
        static double Mod(double a, double b) { return a % b; }
        static double Round(double a, int n) { return Math.Round(a, n); }
        static double Vdot(Vector3d a, Vector3d b) { return Vector3d.Dot(a, b); }
        static Vector3d Vcrs(Vector3d a, Vector3d b) { return Vector3d.Cross(a, b); }
        static Vector3d Mul(Vector3d a, double d) { return new Vector3d(a.x * d, a.y * d, a.z * d); }
        static string KStr(double d) { return Grd.KStr(d); }
        static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue();
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value ? 1 : 0;
            throw new InvalidCastException("not a number: " + (s == null ? "null" : s.GetType().Name));
        }
        static bool Bool(Structure s)
        {
            var bv = s as BooleanValue;
            if (bv != null) return bv.Value;
            var sv = s as ScalarValue;
            if (sv != null) return sv.GetDoubleValue() != 0;
            throw new InvalidCastException("not a boolean: " + (s == null ? "null" : s.GetType().Name));
        }
        static double Fin(double x, string n)
        {
            if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("non-finite " + n);
            return x;
        }
        // a Direction's axes, as kOS.dll's suffixes
        static Vector3d V3(Vector3 r) { return new Vector3d(r.x, r.y, r.z); }
        static Vector3d Fore(Quaternion q) { return V3(q * (Vector3)Vector3d.forward); }
        static Vector3d Top(Quaternion q) { return V3(q * Vector3.up); }
        static Vector3d Star(Quaternion q) { return V3(q * Vector3.right); }

        // ------------------------------------------------------------ constants (lib_ascent_css's ASC_CSS_*)
        double RHC, DB, EXP, EXP2P, QMAX1, QMAX, YMAX1, YMAX, CAP_W, CAP_T, RMAX, KA, WAUTO, RET_DEG, RET_W, RET_T, T, TI, IMAX, AMIN,
            AUTH_K, AUTH_N, WARP_KT, FF_TAU, LOG_EVERY, FLUSH, KB_MODE, KB_FULL, KB_RISE, KB_MIN, KB_TAP, KB_STEPS, KB_STICK_T,
            GAM_MAX, V_MIN, AUTH_KS, TC, AF, TF, TG, HY_ON, HY_W, HY_VMIN;

        // ------------------------------------------------------------ the state (the ascCss lexicon's keys)
        public class Hold                   // "hp" / "hr": the hold, its frame kind, its timer, its frame's turn, its last target
        {
            public string h;
            public bool on, hasQ, hasK, hasT, hasW, hasD;
            public Quaternion q, d;
            public double k, T;
            public Vector3d w;
        }
        Lexicon lx;
        public double t, n, rt0, bufn;
        public bool s1, cp, cr, ret;
        public string law, csv, buf;
        public Structure authS;
        public readonly double[] authD = new double[3];
        public Quaternion tgt;
        public Vector3d wf;
        public readonly Hold hp = new Hold { h = "hp" }, hr = new Hold { h = "hr" };
        public readonly Hold hy = new Hold { h = "hy" }, fm = new Hold { h = "fm" };   // the roll hold in yaw; the frame's turn
        Structure iS;
        public readonly double[] iv = new double[3];
        public readonly bool[] iw = new bool[3];
        Structure shS;
        public readonly double[] sh = new double[15];       // ascCss["sh"]: the stick axes' references (ascCssSh)
        public readonly bool[] shw = new bool[15];
        Structure kbS;
        public readonly double[][] kb = { new double[8], new double[8], new double[8] };    // [0] the boolean as 1 / 0
        public readonly bool[][] kbw = { new bool[8], new bool[8], new bool[8] };
        public readonly double[] stk = new double[3], u = new double[3];
        public double tbC, tbS, dcRY, dcYR;                 // ascCss["tb"] (the stick's roll axis) and ["dc"] (the cross-coupling)
        public Vector3d tb3;                                // ascCss["tb3"]: that axis, body star / top / fore (the current roll's)
        public readonly double[] ks = new double[3];        // ascCss["ks"]: the stick axes' share of FBWAUTH
        public bool stop;                                   // the return's stop this tick (kOS runs ascCssStop)
        readonly List<string> wr = new List<string>();      // the keys written, in kOS's order of their first write
        readonly HashSet<string> wrs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        void W(string k) { if (wrs.Add(k)) wr.Add(k); }

        Structure K(string k) { return lx[new StringValue(k)]; }
        bool Has(string k) { return lx.ContainsKey(new StringValue(k)); }
        double G(IAscEnv e, string n) { return Num(e.Get(n)); }

        void LoadHold(IAscEnv e, Hold o)
        {
            o.on = Bool(K(o.h + "On"));
            o.hasQ = Has(o.h); if (o.hasQ) o.q = e.Rot(K(o.h));
            o.hasK = Has(o.h + "k"); if (o.hasK) o.k = Num(K(o.h + "k"));
            o.hasT = Has(o.h + "T"); if (o.hasT) o.T = Num(K(o.h + "T"));
            o.hasW = Has(o.h + "w"); if (o.hasW) o.w = e.Vec(K(o.h + "w"));
            o.hasD = Has(o.h + "d"); if (o.hasD) o.d = e.Rot(K(o.h + "d"));
        }

        public void Load(IAscEnv e)
        {
            RHC = G(e, "ASC_CSS_RHC"); DB = G(e, "ASC_CSS_DB"); EXP = G(e, "ASC_CSS_EXP"); QMAX1 = G(e, "ASC_CSS_QMAX1");
            EXP2P = G(e, "ASC_CSS_EXP2P");
            QMAX = G(e, "ASC_CSS_QMAX"); YMAX1 = G(e, "ASC_CSS_YMAX1"); YMAX = G(e, "ASC_CSS_YMAX"); CAP_W = G(e, "ASC_CSS_CAP_W");
            CAP_T = G(e, "ASC_CSS_CAP_T"); RMAX = G(e, "ASC_CSS_RMAX"); KA = G(e, "ASC_CSS_KA"); WAUTO = G(e, "ASC_CSS_WAUTO");
            RET_DEG = G(e, "ASC_CSS_RET_DEG"); RET_W = G(e, "ASC_CSS_RET_W"); RET_T = G(e, "ASC_CSS_RET_T"); T = G(e, "ASC_CSS_T");
            TI = G(e, "ASC_CSS_TI"); IMAX = G(e, "ASC_CSS_IMAX"); AMIN = G(e, "ASC_CSS_AMIN"); AUTH_K = G(e, "ASC_CSS_AUTH_K");
            AUTH_N = G(e, "ASC_CSS_AUTH_N"); WARP_KT = G(e, "ASC_CSS_WARP_KT"); FF_TAU = G(e, "ASC_CSS_FF_TAU");
            LOG_EVERY = G(e, "ASC_CSS_LOG_EVERY"); FLUSH = G(e, "ASC_CSS_FLUSH"); KB_MODE = G(e, "ASC_CSS_KB_MODE");
            KB_FULL = G(e, "ASC_CSS_KB_FULL"); KB_RISE = G(e, "ASC_CSS_KB_RISE"); KB_MIN = G(e, "ASC_CSS_KB_MIN");
            KB_TAP = G(e, "ASC_CSS_KB_TAP"); KB_STEPS = G(e, "ASC_CSS_KB_STEPS"); KB_STICK_T = G(e, "ASC_CSS_KB_STICK_T");
            GAM_MAX = G(e, "ASC_CSS_GAM_MAX"); V_MIN = G(e, "ASC_CSS_V_MIN");
            AUTH_KS = G(e, "ASC_CSS_AUTH_KS"); TC = G(e, "ASC_CSS_TC"); AF = G(e, "ASC_CSS_AF"); TF = G(e, "ASC_CSS_TF");
            TG = G(e, "ASC_CSS_TG");
            HY_ON = G(e, "ASC_CSS_HY_ON"); HY_W = G(e, "ASC_CSS_HY_W"); HY_VMIN = G(e, "ASC_CSS_HY_VMIN");

            lx = (Lexicon)e.Get("ascCss");
            wr.Clear(); wrs.Clear(); stop = false;
            t = Num(K("t")); n = Num(K("n")); rt0 = Num(K("rt0")); bufn = Num(K("bufn"));
            s1 = Bool(K("s1")); cp = Bool(K("cp")); cr = Bool(K("cr")); ret = Bool(K("ret"));
            law = K("law").ToString(); csv = K("csv").ToString(); buf = K("buf").ToString();
            authS = K("auth");
            var al = (ListValue)authS;
            for (int i = 0; i < 3; i++) authD[i] = Num(al[i]);
            tgt = e.Rot(K("tgt"));
            wf = e.Vec(K("wf"));
            LoadHold(e, hp); LoadHold(e, hr); LoadHold(e, hy); LoadHold(e, fm);
            iS = K("i");
            var il = (ListValue)iS;
            for (int i = 0; i < 3; i++) { iv[i] = Num(il[i]); iw[i] = false; }
            shS = K("sh");
            var hl = (ListValue)shS;
            if (hl.Count != 15) throw new ArgumentException("ascCss sh: " + hl.Count + " items, want 15");
            for (int i = 0; i < 15; i++) { sh[i] = Num(hl[i]); shw[i] = false; }
            kbS = K("kb");
            var kl = (ListValue)kbS;
            for (int i = 0; i < 3; i++)
            {
                var s = (ListValue)kl[i];
                kb[i][0] = Bool(s[0]) ? 1 : 0;
                for (int j = 1; j < 8; j++) kb[i][j] = Num(s[j]);
                for (int j = 0; j < 8; j++) kbw[i][j] = false;
            }
            var sl = (ListValue)K("stk");
            for (int i = 0; i < 3; i++) stk[i] = Num(sl[i]);
            var ul = (ListValue)K("u");
            for (int i = 0; i < 3; i++) u[i] = Num(ul[i]);
            var tl = Has("tb") ? (ListValue)K("tb") : null;
            tbC = tl != null ? Num(tl[0]) : 1; tbS = tl != null ? Num(tl[1]) : 0;
            var dl = Has("dc") ? (ListValue)K("dc") : null;
            dcRY = dl != null ? Num(dl[0]) : 0; dcYR = dl != null ? Num(dl[1]) : 0;
            tb3 = Has("tb3") ? e.Vec(K("tb3")) : new Vector3d(0, 0, 1);
            var kl3 = Has("ks") ? (ListValue)K("ks") : null;
            for (int i = 0; i < 3; i++) ks[i] = kl3 != null ? Num(kl3[i]) : AUTH_KS;
        }

        // ------------------------------------------------------------ the tick's reads
        double now, met, dynp;
        Quaternion fq;
        Vector3d wRaw, vs, vo, up;
        Structure pilotS, authIn;

        // ------------------------------------------------------------ lib_ascent_css.ks's functions
        static double Clip(double x, double m) { return Max(-m, Min(m, x)); }       // ascCssClip

        // ascCssErr: the rotation from the frame (fv, tv, sv) to d
        static Vector3d Err(Vector3d fv, Vector3d tv, Vector3d sv, Quaternion d)
        {
            return Mul(Vcrs(fv, Fore(d)) + Vcrs(tv, Top(d)) + Vcrs(sv, Star(d)), 0.5);
        }

        double Shape(double g, double mx, double ex)        // ascCssShape
        {
            double x = Abs(g) * RHC - DB;
            if (x <= 0) { return 0; }
            double s = mx * Math.Pow(Min(1, x / (RHC - DB)), ex);
            if (g < 0) { return -s; }
            return s;
        }

        Quaternion Frame(IAscEnv e, double k)               // ascCssFrame
        {
            if (k == 1) { return e.Look(vs, up); }
            if (k == 2) { return e.Look(Vector3d.Exclude(up, vo), up); }
            return e.Euler(new Vector3d(0, 0, 0));
        }

        double Kind()                                       // ascCssKind
        {
            if (!s1) { return 2; }
            if (vs.magnitude < V_MIN || Vector3d.Angle(vs, up) < 90 - GAM_MAX) { return 0; }
            return 1;
        }

        bool CapOk(Hold o, double wa)                       // ascCssCapOk(h + "T", wa)
        {
            if (!o.hasT) { o.T = -1; o.hasT = true; W(o.h + "T"); }
            if (o.T < 0) { o.T = now; W(o.h + "T"); }
            return wa < CAP_W || now - o.T > CAP_T;
        }

        void Catch(IAscEnv e, Hold o)                       // ascCssCatch
        {
            double k = Kind();
            o.q = e.Inverse(Frame(e, k)) * fq; o.hasQ = true; W(o.h);
            o.k = k; o.hasK = true; W(o.h + "k");
            o.T = 0; o.hasT = true; W(o.h + "T");
            o.w = fm.w; o.hasW = true; W(o.h + "w");   // the frame's turn, already learned (Fm)
        }

        Quaternion Held(IAscEnv e, Hold o)                  // ascCssHeld
        {
            double k = Kind();
            if (k != o.k)
            {
                Quaternion d0 = Frame(e, o.k) * o.q;
                o.q = e.Inverse(Frame(e, k)) * d0; W(o.h);
                o.k = k; W(o.h + "k");
            }
            Quaternion d = Frame(e, k) * o.q;
            double tt = now;
            if (o.T > 0 && tt > o.T)
            {
                double dt = tt - o.T;
                Quaternion p = o.d;
                Vector3d raw = Mul(Err(Fore(p), Top(p), Star(p), d), 57.2958 / dt);
                if (raw.magnitude < 20) { o.w = o.w + Mul(raw - o.w, Min(1, dt / FF_TAU)); W(o.h + "w"); }
            }
            if (tt > o.T)
            {
                o.d = d; o.hasD = true; W(o.h + "d");
                o.T = tt; W(o.h + "T");
            }
            return d;
        }

        double Ff(Hold o, Vector3d ax)                      // ascCssFf
        {
            if (!o.on) { return 0; }
            return Vdot(o.w, ax);
        }

        Vector3d Fm(IAscEnv e)                              // ascCssFm
        {
            double k = Kind();
            Quaternion d = Frame(e, k);
            double tt = now;
            if (k == fm.k && fm.T > 0 && tt > fm.T)
            {
                double dt = tt - fm.T;
                Quaternion p = fm.d;
                Vector3d raw = Mul(Err(Fore(p), Top(p), Star(p), d), 57.2958 / dt);
                if (raw.magnitude < 20) { fm.w = fm.w + Mul(raw - fm.w, Min(1, dt / FF_TAU)); W("fmw"); }
            }
            if (tt > fm.T)
            {
                fm.d = d; fm.hasD = true; W("fmd");
                fm.T = tt; W("fmT");
                fm.k = k; fm.hasK = true; W("fmk");
            }
            return fm.w;
        }

        void HyCatch(IAscEnv e)                             // ascCssHyCatch
        {
            hy.q = e.Inverse(e.Look(Fore(fq), up)) * fq; hy.hasQ = true; W("hy");
            hy.T = 0; hy.hasT = true; W("hyT");
            hy.w = new Vector3d(0, 0, 0); hy.hasW = true; W("hyw");
            hy.on = true; W("hyOn");
        }

        double HyRate(IAscEnv e, double kcw)                // ascCssHyRate
        {
            Vector3d fv = Fore(fq);
            if (Vector3d.Angle(fv, up) < HY_VMIN) { return 0; }
            Quaternion d = e.Look(fv, up) * hy.q;
            double tt = now;
            if (hy.T > 0 && tt > hy.T)
            {
                double dt = tt - hy.T;
                Quaternion p = hy.d;
                Vector3d raw = Mul(Err(Fore(p), Top(p), Star(p), d), 57.2958 / dt);
                if (raw.magnitude < 20) { hy.w = hy.w + Mul(raw - hy.w, Min(1, dt / FF_TAU)); W("hyw"); }
            }
            if (tt > hy.T)
            {
                hy.d = d; hy.hasD = true; W("hyd");
                hy.T = tt; W("hyT");
            }
            Vector3d er = Err(fv, Top(fq), Star(fq), d);
            return Clip(Vdot(er, fv) * 57.2958 * KA * kcw, WAUTO) + Vdot(hy.w, fv);
        }

        double[] Tg(IAscEnv e, double kcw)                  // ascCssTg
        {
            Vector3d fw = fm.w;
            double q = stk[0];
            if (q == 0) { q = Vdot(fw, Mul(Star(fq), -1)); }
            double p = 0 - stk[1];
            double r = stk[2];
            if (stk[1] == 0 && stk[2] == 0)
            {
                p = Vdot(fw, Fore(fq));
                r = Vdot(fw, Top(fq));
            }
            else if (stk[1] == 0 && hy.on)
            {
                p = HyRate(e, kcw);
            }
            return new double[] { q, p, r };
        }

        void KbW(int i, int j, double v) { kb[i][j] = v; kbw[i][j] = true; }
        double Kb(int i, double raw)                        // ascCssKb
        {
            if (KB_MODE == 0) { return raw; }
            double[] s = kb[i];
            double tn = now;
            double dt = 0;
            if (s[3] > 0) { dt = Max(0, Min(0.2, tn - s[3])); }
            KbW(i, 3, tn);
            double a = Abs(raw);
            bool atStop = a < 0.0001 || Abs(a - 1) < 0.0001;
            if (atStop && Abs(raw - s[2]) > 0.9) { KbW(i, 4, s[4] + 1); KbW(i, 5, 0); }
            if (!atStop) { KbW(i, 5, s[5] + dt); }
            KbW(i, 2, raw);
            if (KB_MODE == 1)
            {
                if (s[0] == 0 && s[4] >= KB_STEPS) { KbW(i, 0, 1); KbW(i, 5, 0); }
                if (s[0] != 0 && s[5] > KB_STICK_T) { KbW(i, 0, 0); KbW(i, 4, 0); KbW(i, 7, 0); KbW(i, 1, 0); }
                if (s[0] == 0)
                {
                    KbW(i, 5, Min(s[5], KB_STICK_T));
                    return raw;
                }
            }
            double sg = 0;
            if (a >= 0.5) { sg = raw > 0 ? 1 : -1; }
            if (sg != 0)
            {
                if (sg != s[7])
                {
                    KbW(i, 6, tn);
                    KbW(i, 7, sg);
                    KbW(i, 1, sg * KB_MIN);
                }
                else
                {
                    KbW(i, 1, sg * Min(KB_FULL, Abs(s[1]) + (KB_FULL - KB_MIN) / KB_RISE * dt));
                }
            }
            else if (s[7] == 0 || tn - s[6] >= KB_TAP)
            {
                KbW(i, 7, 0);
                KbW(i, 1, 0);
            }
            return s[1];
        }

        void Stick(IAscEnv e)                               // ascCssStick
        {
            var raw = (ListValue)pilotS;
            double qm = s1 ? QMAX1 : QMAX;
            double ym = s1 ? YMAX1 : YMAX;
            Vector3d w = Mul(wRaw, 57.2958);
            Vector3d wl = w - Fm(e);                       // the rates in the hold's frame
            double sq = 0, sr = 0, sy = 0;
            double gp = Kb(0, Num(raw[0]));
            double gr = Kb(1, Num(raw[1]));
            double gy = Kb(2, Num(raw[2]));
            if (cp)
            {
                sq = Shape(gp, qm, s1 ? EXP : EXP2P);
                if (sq != 0) { hp.on = false; W("hpOn"); hp.T = -1; hp.hasT = true; W("hpT"); }
                else if (!hp.on && CapOk(hp, Abs(Vdot(wl, Star(fq)))))
                {
                    hp.on = true; W("hpOn");
                    Catch(e, hp);
                }
            }
            if (cr)
            {
                sr = Shape(gr, RMAX, EXP);
                sy = Shape(gy, ym, EXP);
                if (sr != 0 || sy != 0)
                {
                    hr.on = false; W("hrOn");
                    hr.T = -1; hr.hasT = true; W("hrT");
                    if (sr != 0 || HY_ON == 0) { hy.on = false; W("hyOn"); }
                    else if (!hy.on && Abs(Vdot(w, Fore(fq))) < HY_W) { HyCatch(e); }
                }
                else
                {
                    hy.on = false; W("hyOn");
                    if (!hr.on && CapOk(hr, Max(Abs(Vdot(wl, Fore(fq))), Abs(Vdot(wl, Top(fq))))))
                    {
                        hr.on = true; W("hrOn");
                        Catch(e, hr);
                    }
                }
            }
            stk[0] = sq; stk[1] = sr; stk[2] = sy; W("stk");
        }

        double PI(int i, double er, double kc, double dt)   // ascCssPI
        {
            double uu = er * kc + iv[i];
            if (!(Abs(uu) >= 1 && uu * er > 0)) { iv[i] = Clip(iv[i] + er * kc * dt / TI, IMAX); iw[i] = true; }
            return Clip(er * kc + iv[i], 1);
        }

        double PS(int i, double x, double er, double kc, double dt)   // ascCssPS
        {
            double uu = x + iv[i];
            if (!(Abs(uu) >= 1 && uu * er > 0)) { iv[i] = Clip(iv[i] + er * kc * dt / TI, IMAX); iw[i] = true; }
            return Clip(x + iv[i], 1);
        }

        void ShW(int i, double v) { sh[i] = v; shw[i] = true; }
        double Sh(int j, double tg, double wn, double am, double dt)     // ascCssSh
        {
            int b = 5 * j;
            if (sh[b] == 0)
            {
                ShW(b, 1);
                ShW(b + 1, wn);
                ShW(b + 2, wn);
                ShW(b + 3, 0);
                ShW(b + 4, 0);
            }
            double ar = Clip((tg - sh[b + 1]) / TF, AF * am);
            ShW(b + 1, sh[b + 1] + ar * dt);
            ShW(b + 3, sh[b + 3] + (sh[b + 4] - sh[b + 3]) * Min(1, dt / TG));
            ShW(b + 4, ar);
            ShW(b + 2, sh[b + 2] + sh[b + 3] * dt);
            return ar;
        }
        void ShOff(int j)                                   // ascCssShOff
        {
            if (sh[5 * j] != 0) { ShW(5 * j, 0); }
        }

        // ------------------------------------------------------------ ONE TICK (ascCssTickA): the outputs, or it throws
        public double[] rowV = new double[10];
        public string stopMsg = "", logText = "";
        public int act;
        public double cmdP, cmdR, cmdY;

        public void Run(IAscEnv e, ListValue inp)
        {
            if (inp.Count != AscIn.N) throw new ArgumentException("ASCCSSTICK: " + inp.Count + " inputs, want " + AscIn.N);
            Load(e);
            if (law != "A") throw new InvalidOperationException("ASCCSSTICK: the law is '" + law + "', not A");
            now = Num(inp[AscIn.TIME]); fq = e.Rot(inp[AscIn.FACING]); wRaw = e.Vec(inp[AscIn.W]);
            vs = e.Vec(inp[AscIn.VS]); vo = e.Vec(inp[AscIn.VO]); up = e.Vec(inp[AscIn.UP]);
            pilotS = inp[AscIn.PILOT]; authIn = inp[AscIn.AUTH]; met = Num(inp[AscIn.MET]); dynp = Num(inp[AscIn.DYNP]);
            act = 0; stopMsg = ""; logText = "";

            double tt = now;
            double dt = Max(tt - t, 0.001);
            t = tt; W("t");
            n = n + 1; W("n");
            Vector3d fv = Fore(fq);
            Vector3d tv = Top(fq);
            Vector3d sv = Star(fq);
            Vector3d kp = Mul(sv, -1);                      // the nose-up axis
            Vector3d w = Mul(wRaw, 57.2958);
            if (Mod(n, AUTH_N) == 0)
            {
                var al = authIn as ListValue;
                if (al == null) throw new ArgumentException("ASCCSSTICK: no FBWAUTH on an authority tick (n " + KStr(n) + ")");
                authS = authIn; W("auth");
                for (int i = 0; i < 3; i++) authD[i] = Num(al[i]);
            }
            Stick(e);
            Vector3d eA = Err(fv, tv, sv, tgt);
            Vector3d eP = eA;
            Vector3d eR = eA;
            if (cp && hp.on) { eP = Err(fv, tv, sv, Held(e, hp)); }
            if (cr && hr.on) { eR = Err(fv, tv, sv, Held(e, hr)); }
            // AUTO pitch under ROLL/YAW CSS: the current roll (the turn taking the stick's roll axis onto the guidance's)
            bool pcr = cr && !cp;
            Vector3d tg3 = new Vector3d(0, 0, 0);
            if (pcr)
            {
                tg3 = Mul(Star(tgt), tb3.x) + Mul(Top(tgt), tb3.y) + Mul(Fore(tgt), tb3.z);
                eP = Vcrs(Mul(sv, tb3.x) + Mul(tv, tb3.y) + Mul(fv, tb3.z), tg3);
            }
            double kcw = Min(1, WARP_KT * T / dt);
            double kch = Min(1, WARP_KT * TC / dt);                     // a CSS axis's: the stick loop's gain, its warp cap alike
            double[] sht = Tg(e, kcw);
            // kOS's order: (kp x the error) x the gain (under warp the gain is not 1: kp x (the error x the gain) differed in the
            // last bits, and through kp . fv in the roll's command)
            Vector3d om = Mul(Mul(Mul(kp, pcr ? 0 : Vdot(eP, kp)), cp ? kch : kcw) + Mul(Mul(fv, Vdot(eR, fv)) + Mul(tv, Vdot(eR, tv)), cr ? kch : kcw), 57.2958 * KA);
            if (om.magnitude > WAUTO) { om = Mul(om, WAUTO / om.magnitude); }
            double qc = Vdot(om, kp) + (cp ? Ff(hp, kp) : Vdot(wf, kp));
            if (pcr) { qc = Clip(Vdot(eP, kp) * 57.2958 * KA * kcw, WAUTO) + Vdot(wf - Mul(tg3, Vdot(wf, tg3)), kp); }
            double pc = Vdot(om, fv) + (cr ? Ff(hr, fv) : Vdot(wf, fv));    // + = LEFT
            double rc = Vdot(om, tv) + (cr ? Ff(hr, tv) : Vdot(wf, tv));    // + = nose right
            if (cp && stk[0] != 0) { qc = stk[0]; }
            if (cp && stk[0] == 0 && !hp.on) { qc = 0; }
            if (cr && stk[1] == 0 && stk[2] == 0 && !hr.on) { pc = 0; rc = 0; }
            if (cr && (stk[1] != 0 || stk[2] != 0))
            {
                pc = 0 - stk[1];
                rc = stk[2];
            }
            double wq = Vdot(w, kp);
            double wp = Vdot(w, fv);
            double wr_ = Vdot(w, tv);
            // the stick axes (ascCssSh; the roll's in the LEFT sense, as pc); the csv's commands are the model's rates there
            bool shP = cp && (stk[0] != 0 || !hp.on);
            bool shR = cr && (stk[1] != 0 || stk[2] != 0 || !hr.on);
            if (shP)
            {
                double am = Max(authD[0] * ks[0], AMIN);
                double ar = Sh(0, sht[0], wq, am, dt);
                qc = sh[2];
                cmdP = PS(0, (ar + (qc - wq) * kcw / TC) / am, (qc - wq) / (TC * am), kch, dt);
            }
            else if (cp)                                                    // the hold: the stick loop's gain
            {
                ShOff(0);
                cmdP = PI(0, (qc - wq) / (TC * Max(authD[0] * ks[0], AMIN)), kch, dt);
            }
            else
            {
                ShOff(0);
                cmdP = PI(0, (qc - wq) / (T * Max(authD[0] * AUTH_K, AMIN)), kcw, dt);
            }
            if (shR)
            {
                // the references in the stick's axes (tbC / tbS: the roll about the thrust axis, the yaw across it)
                double am = Max(authD[1] * ks[1], AMIN);
                double ay = Max(authD[2] * ks[2], AMIN);
                double tpT = sht[1];
                double trT = sht[2];
                if (stk[1] == 0 && stk[2] == 0)                             // the frame's turn put on the stick's axes
                {
                    tpT = sht[1] * tbC + sht[2] * tbS;
                    trT = sht[2] * tbC - sht[1] * tbS;
                }
                double amT = Min(am / tbC, ay / Max(Abs(tbS), 0.000001));
                double ayT = Min(ay / tbC, am / Max(Abs(tbS), 0.000001));
                double ar = Sh(1, tpT, wp * tbC + wr_ * tbS, amT, dt);
                double ary = Sh(2, trT, wr_ * tbC - wp * tbS, ayT, dt);
                double pcT = sh[7];
                double rcT = sh[12];
                pc = tbC * pcT - tbS * rcT;
                rc = tbS * pcT + tbC * rcT;
                double arB = tbC * ar - tbS * ary;
                double aryB = tbS * ar + tbC * ary;
                cmdR = PS(1, 0 - (arB + (pc - wp) * kcw / TC) / am, 0 - (pc - wp) / (TC * am), kch, dt);     // ctrl + = RIGHT
                cmdY = PS(2, (aryB + (rc - wr_) * kcw / TC) / ay, (rc - wr_) / (TC * ay), kch, dt);
            }
            else if (cr)                                                    // the hold: the stick loop's gain
            {
                ShOff(1);
                ShOff(2);
                cmdR = PI(1, -(pc - wp) / (TC * Max(authD[1] * ks[1], AMIN)), kch, dt);   // ctrl + = RIGHT
                cmdY = PI(2, (rc - wr_) / (TC * Max(authD[2] * ks[2], AMIN)), kch, dt);
            }
            else
            {
                ShOff(1);
                ShOff(2);
                cmdR = PI(1, -(pc - wp) / (T * Max(authD[1] * AUTH_K, AMIN)), kcw, dt);   // ctrl + = RIGHT
                cmdY = PI(2, (rc - wr_) / (T * Max(authD[2] * AUTH_K, AMIN)), kcw, dt);
            }
            // the cross-coupling taken out (dcRY / dcYR): the commands that give the loops' roll (LEFT) and yaw accelerations
            if (dcRY != 0 || dcYR != 0)
            {
                double dcD = 1 - dcRY * dcYR;
                double dcX = (0 - cmdR - dcRY * cmdY) / dcD;
                double dcU = (cmdY + dcYR * cmdR) / dcD;
                cmdR = Clip(0 - dcX, 1);
                cmdY = Clip(dcU, 1);
            }
            Fin(cmdP, "cmdP"); Fin(cmdR, "cmdR"); Fin(cmdY, "cmdY");
            u[0] = cmdP; u[1] = cmdR; u[2] = cmdY; W("u");
            // the return: both axes AUTO, back on the guidance's attitude -> kOS's steering (kOS runs ascCssStop)
            if (ret)
            {
                double ed = eA.magnitude * 57.2958;
                double wd = (w - wf).magnitude;
                if ((ed < RET_DEG && wd < RET_W) || tt - rt0 > RET_T)
                {
                    stop = true;
                    act |= 1;
                    stopMsg = "AUTO: " + KStr(Round(ed, 2)) + " DEG, " + KStr(Round(wd, 2)) + " DEG/S";
                }
            }
            if (csv != "" && Mod(n, LOG_EVERY) == 0)
            {
                rowV[0] = tt; rowV[1] = qc; rowV[2] = pc; rowV[3] = rc; rowV[4] = wq; rowV[5] = wp; rowV[6] = wr_;
                rowV[7] = Vdot(eP, kp) * 57.2958; rowV[8] = Vdot(eR, fv) * 57.2958; rowV[9] = Vdot(eR, tv) * 57.2958;
                if (stop) { act |= 2; }                     // after ascCssStop: kOS writes the row (law "", the buffer flushed)
                else { Row(); }
            }
        }

        void Row()                                          // ascCssRow (Law A)
        {
            buf = buf + (bufn == 0 ? "" : "\n") + KStr(Round(rowV[0], 2)) + "," + KStr(Round(met, 2))
                + "," + law + "," + KStr(Round(dynp * ATMTOKPA, 2)) + "," + (cp ? "1" : "0")
                + "," + (cr ? "1" : "0") + "," + (hp.on ? "1" : "0") + "," + (hr.on ? "1" : "0")
                + "," + KStr(Round(stk[0], 3)) + "," + KStr(Round(stk[1], 3)) + "," + KStr(Round(stk[2], 3)) + "," + KStr(Round(rowV[1], 3))
                + "," + KStr(Round(rowV[2], 3)) + "," + KStr(Round(rowV[3], 3)) + "," + KStr(Round(rowV[4], 3)) + "," + KStr(Round(rowV[5], 3))
                + "," + KStr(Round(rowV[6], 3)) + "," + KStr(Round(rowV[7], 3)) + "," + KStr(Round(rowV[8], 3)) + "," + KStr(Round(rowV[9], 3))
                + "," + KStr(Round(u[0], 4)) + "," + KStr(Round(u[1], 4)) + "," + KStr(Round(u[2], 4)) + "," + KStr(Round(iv[0], 4)) + ","
                + KStr(Round(iv[1], 4)) + "," + KStr(Round(iv[2], 4)) + "," + KStr(Round(authD[0], 2)) + "," + KStr(Round(authD[1], 2)) + ","
                + KStr(Round(authD[2], 2)) + "," + (ret ? "1" : "0");
            W("buf");
            bufn = bufn + 1; W("bufn");
            if (bufn >= FLUSH)
            {
                act |= 4;
                logText = buf;
                buf = ""; bufn = 0;
            }
        }

        // ------------------------------------------------------------ the write-back (live only)
        static ListValue L3(double[] a)
        {
            var l = new ListValue();
            for (int i = 0; i < 3; i++) l.Add(ScalarValue.Create(a[i]));
            return l;
        }
        static bool Pre(string k, string p) { return k.StartsWith(p, StringComparison.OrdinalIgnoreCase); }
        Structure Val(IAscEnv e, string k)
        {
            switch (k)
            {
                case "t": return ScalarValue.Create(t);
                case "n": return ScalarValue.Create(n);
                case "auth": return authS;
                case "stk": return L3(stk);
                case "u": return L3(u);
                case "buf": return new StringValue(buf);
                case "bufn": return ScalarValue.Create(bufn);
            }
            Hold o = Pre(k, "hp") ? hp : Pre(k, "hr") ? hr : Pre(k, "hy") ? hy : Pre(k, "fm") ? fm : null;
            if (o == null) throw new InvalidOperationException("no key " + k);
            string s = k.Substring(2);
            if (s == "") return e.MakeDir(o.q);
            if (s == "On") return new BooleanValue(o.on);
            if (s == "k") return ScalarValue.Create(o.k);
            if (s == "T") return ScalarValue.Create(o.T);
            if (s == "w") return e.MakeVec(o.w);
            if (s == "d") return e.MakeDir(o.d);
            throw new InvalidOperationException("no key " + k);
        }
        public void Commit(IAscEnv e)
        {
            foreach (var k in wr) lx[new StringValue(k)] = Val(e, k);
            var il = (ListValue)iS;
            for (int i = 0; i < 3; i++) if (iw[i]) il[i] = ScalarValue.Create(iv[i]);
            var hl = (ListValue)shS;
            for (int i = 0; i < 15; i++) if (shw[i]) hl[i] = ScalarValue.Create(sh[i]);
            var kl = (ListValue)kbS;
            for (int i = 0; i < 3; i++)
            {
                var s = (ListValue)kl[i];
                for (int j = 0; j < 8; j++)
                {
                    if (!kbw[i][j]) continue;
                    s[j] = j == 0 ? (Structure)new BooleanValue(kb[i][0] != 0) : ScalarValue.Create(kb[i][j]);
                }
            }
        }

        // the outputs: LIST(cmdP, cmdR, cmdY, the action, the stop's text, the row's ten values, the text to LOG)
        public ListValue Out()
        {
            var o = new ListValue();
            o.Add(ScalarValue.Create(cmdP)); o.Add(ScalarValue.Create(cmdR)); o.Add(ScalarValue.Create(cmdY));
            o.Add(ScalarValue.Create(act)); o.Add(new StringValue(stopMsg));
            for (int i = 0; i < 10; i++) o.Add(ScalarValue.Create(rowV[i]));
            o.Add(new StringValue(logText));
            return o;
        }
    }
}
