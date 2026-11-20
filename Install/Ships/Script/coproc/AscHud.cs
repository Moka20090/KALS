// ops1q.ks's ascHudRec and asc_hud_pl (the OPS 1 HUD's inputs each tick: the diamond and yaw line off the errors to the
// guidance's attitude, the launch-azimuth horizon, the thrust's g, the phase word, the speed tape, the SSME throttle on
// the speedbrake's slider) in C#, line for line with kOS's semantics (trig in degrees, MOD = %, vectors through KSP's
// Vector3d as kOS's Vector does, string '=' case-insensitive). kOS keeps the guidance (asc_view_dir's attitude comes in),
// the game reads (the facing, the velocities, the VHH site's position, the pad's engine list) and HEADING: ASCHUD returns
// the horizon's heading and kOS makes hdAzN of it. The engines' THRUST, IGNITION, FLAMEOUT and AVAILABLETHRUST are read
// through their kOS suffixes. kOS.Safe only (the offline VM builds it); nothing is written unless the whole call
// succeeded; no call throws into kOS.
//   ASCHUD(LIST(asc, facing fore, top, star, the guidance's fore, top, SHIP:UP:VECTOR, UP:VECTOR, NORTH:VECTOR,
//       SHIP:VELOCITY:SURFACE, SHIP:VELOCITY:ORBIT:MAG, SHIP:ALTITUDE, SHIP:MASS, CONSTANT:G0, the VHH site's position
//       (0 without the VHH tape), asc_hud_pl's engines)) -> the horizon's heading (deg; kOS sets hdAzN when hdAzOn),
//       or "error ..." with nothing written
//   ASCHUDERROR, ASCHUDN (the calls flown in C#)
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Execution;

namespace KalsCoproc
{
    public class AscHudHost
    {
        const int ASC = 0, FF = 1, FT = 2, FS = 3, VF = 4, VT = 5, SUP = 6, UP = 7, NORTH = 8, VS = 9, VO = 10, ALT = 11,
            MASS = 12, G0 = 13, SITE = 14, PL = 15, N_IN = 16;
        // what ascHudRec writes: hdgRec's keys ("hdgRec:" + key), then the globals
        static readonly string[] KEYS = { "hdgRec:diaDx", "hdgRec:diaDy", "hdgRec:yaw", "hdgRec:nzm", "hdgRec:phase",
            "hdAzOn", "hdAzPit", "hdAzRoll", "asc_hud_pi", "asc_hud_x", "hdSpdMode", "hdTapeKK", "hdSpdV", "hdSb", "hdSbc" };
        const string REC = "hdgRec:";

        readonly Func<Structure, Vector3d> vin;
        public string Error = "";
        public int N = 0;

        public AscHudHost(Func<Structure, Vector3d> v) { vin = v; }

        static Structure G(ICpu cpu, string n) { return Structure.FromPrimitiveWithAssert(cpu.GetValue("$" + n, false)); }
        static double D(Structure s) { return Adm.D(s); }
        static bool B(Structure s) { return Adm.B(s); }
        static bool SEq(string a, string b) { return Adm.SEq(a, b); }
        static Lexicon Lx(Structure s) { var l = s as Lexicon; if (l == null) throw new Exception("not a LEXICON"); return l; }
        static ListValue Ls(Structure s) { var l = s as ListValue; if (l == null) throw new Exception("not a LIST"); return l; }
        static Structure K(Lexicon l, string k) { return l[new StringValue(k)]; }
        static bool Has(Lexicon l, string k) { return l.ContainsKey(new StringValue(k)); }
        static Structure Suf(Structure s, string n) { return s.GetSuffix(n).Value; }
        static double[] Tab(ICpu cpu, string n)
        {
            var l = Ls(G(cpu, n));
            var d = new double[l.Count];
            for (int i = 0; i < d.Length; i++) d[i] = D(l[i]);
            return d;
        }

        static double Tan(double d) { return Math.Tan(d * Math.PI / 180.0); }
        static double Atan(double x) { return Math.Atan(x) * 180.0 / Math.PI; }

        // asc_vref, asc_tab (lib_ascent_s1.ks)
        static double Vref(ICpu cpu, double vrel, double hgt)
        {
            double sssl = D(G(cpu, "ASC_SSSL"));
            return vrel * sssl / (sssl - D(G(cpu, "ASC_DSSA")) * Math.Min(Math.Max(hgt, 0), D(G(cpu, "ASC_ALTSS"))));
        }
        static double AscTab(double[] P, double[] Y, int i, double x)
        {
            double y0 = Tan(Y[i] / 4);
            double y1 = Tan(Y[i + 1] / 4);
            return 4 * Atan(y0 + (y1 - y0) / (P[i + 1] - P[i]) * (x - P[i]));
        }

        // ascHudRec's values for every key (written or as they stand), and the horizon's heading
        Dictionary<string, Structure> Run(ICpu cpu, ListValue a, out double az)
        {
            if (a.Count != N_IN) throw new ArgumentException("ASCHUD wants " + N_IN + " items, got " + a.Count);
            var asc = Lx(a[ASC]);
            var w = new Dictionary<string, Structure>(StringComparer.OrdinalIgnoreCase);
            double[] er = AdCalc.RpyErr(vin(a[FF]), vin(a[FT]), vin(a[FS]), vin(a[VF]), vin(a[VT]));
            w[REC + "diaDx"] = ScalarValue.Create(D(G(cpu, "ASC_HUD_DIA_ROLL")) * er[0]);
            w[REC + "diaDy"] = ScalarValue.Create(D(G(cpu, "ASC_HUD_DIA_PIT")) * er[1]);
            w[REC + "yaw"] = ScalarValue.Create(er[2]);
            string ph = Adm.T(K(asc, "phase"));
            bool s1 = SEq(ph, "PAD") || SEq(ph, "STAGE1") || SEq(ph, "SRBSEP");
            string ab = Adm.T(K(asc, "abort"));
            bool ss = SEq(ab, "SPLITS");
            w["hdAzOn"] = (s1 || ss) ? BooleanValue.True : BooleanValue.False;
            Vector3d vs = vin(a[VS]);
            az = 0;
            if (ss || s1)
            {
                if (ss) w["hdAzRoll"] = BooleanValue.True;
                else if (!B(G(cpu, "hdAzRoll")) && B(K(Lx(K(asc, "s1")), "clear")) && !B(K(asc, "slew"))) w["hdAzRoll"] = BooleanValue.True;
                // asc_hud_pit, then asc_hud_az on the segment and point it read (a split-S: the loft's plane, its line at 0)
                double[] P = Tab(cpu, "ASC_PPOLY");
                double x = Vref(cpu, vs.magnitude, D(a[ALT]));
                int i = (int)D(G(cpu, "asc_hud_pi"));
                while (!(i >= P.Length - 2 || x < P[i + 1])) i = i + 1;
                w["asc_hud_x"] = ScalarValue.Create(x);
                w["asc_hud_pi"] = ScalarValue.Create(i);
                w["hdAzPit"] = ScalarValue.Create(ss ? 0 : AscTab(P, Tab(cpu, "ASC_THET"), i, x));
                double ps = AscTab(P, Tab(cpu, "ASC_PSI"), i, x) + D(G(cpu, "ASC_HDG_DELTA"));
                if (D(G(cpu, "ASC_LAUNCH_DIR")) < 0) ps = 180 - ps;
                az = ps;
            }
            double f = 0;
            foreach (Structure en in Ls(K(asc, "ssme"))) f = f + D(Suf(en, "THRUST"));
            if (SEq(ph, "PAD") || SEq(ph, "STAGE1")) foreach (Structure en in Ls(K(asc, "srbs"))) f = f + D(Suf(en, "THRUST"));
            if (Has(asc, "oms")) foreach (Structure en in Ls(K(asc, "oms"))) f = f + D(Suf(en, "THRUST"));
            w[REC + "nzm"] = ScalarValue.Create(f / (D(a[MASS]) * D(a[G0])));
            w[REC + "phase"] = new StringValue(ss ? "SPLIT-S" : ab != "" ? ab : SEq(ph, "PAD") ? "" : s1 ? "STG 1" : "STG 2");
            // the speed tape: 0 KEAS, 2 VHH, else 1 VI
            int m = 1;
            if (s1 || SEq(ab, "CONT") || ss) m = 0;
            else if (SEq(ab, "RTLS") && Lx(K(asc, "rl")).Count > 0) m = 2;
            if (m != D(G(cpu, "hdSpdMode")))
            {
                w["hdSpdMode"] = ScalarValue.Create(m);
                w["hdTapeKK"] = ScalarValue.Create(-99999);
            }
            if (m == 2) w["hdSpdV"] = ScalarValue.Create(-Vector3d.Dot(vs, Vector3d.Exclude(vin(a[SUP]), vin(a[SITE])).normalized));
            else w["hdSpdV"] = ScalarValue.Create(D(a[VO]));
            // asc_hud_pl: the running SSMEs' mean power level, actual and commanded
            double s = 0;
            int n = 0;
            foreach (Structure en in Ls(a[PL]))
            {
                if (B(Suf(en, "IGNITION")) && !B(Suf(en, "FLAMEOUT")) && D(Suf(en, "AVAILABLETHRUST")) > 0)
                {
                    s = s + D(Suf(en, "THRUST")) / D(Suf(en, "AVAILABLETHRUST"));
                    n = n + 1;
                }
            }
            double pl0 = 0, pl1 = 0;
            if (n > 0)
            {
                double k = D(G(cpu, "ASC_PL_TO_KSP"));
                pl0 = s / n * 100 / k;
                pl1 = D(G(cpu, "asc_thr")) * 100 / k;
            }
            double sbf = D(G(cpu, "H_SB_FULL"));
            double plf = D(G(cpu, "ASC_HUD_PL_FULL"));
            w["hdSb"] = ScalarValue.Create(sbf * pl0 / plf);
            w["hdSbc"] = ScalarValue.Create(sbf * pl1 / plf);
            foreach (var k in KEYS) if (!w.ContainsKey(k)) w[k] = Now(cpu, k);
            return w;
        }

        static Structure Now(ICpu cpu, string k)
        {
            if (!k.StartsWith(REC, StringComparison.Ordinal)) return G(cpu, k);
            var r = Lx(G(cpu, "hdgRec"));
            string rk = k.Substring(REC.Length);
            return Has(r, rk) ? K(r, rk) : null;
        }

        string Err(Exception ex) { Error = ex.GetType().Name + ": " + ex.Message; return "error " + Error; }

        public Structure Rec(ICpu cpu, ListValue a)
        {
            try
            {
                double az;
                var w = Run(cpu, a, out az);
                var r = Lx(G(cpu, "hdgRec"));
                foreach (var kv in w)
                {
                    if (kv.Key.StartsWith(REC, StringComparison.Ordinal)) r[new StringValue(kv.Key.Substring(REC.Length))] = kv.Value;
                    else cpu.SetGlobal("$" + kv.Key, kv.Value);
                }
                N++;
                return ScalarValue.Create(az);
            }
            catch (Exception ex) { return new StringValue(Err(ex)); }
        }

    }

    public static class AscHudReg
    {
        public static AscHudHost Register(ICpu cpu, Action<string, ISuffix> add, Func<Structure, Vector3d> vin)
        {
            var h = new AscHudHost(vin);
            add("ASCHUD", new OneArgsSuffix<Structure, ListValue>(l => h.Rec(cpu, l)));
            add("ASCHUDERROR", new Suffix<StringValue>(() => new StringValue(h.Error)));
            add("ASCHUDN", new Suffix<ScalarValue>(() => ScalarValue.Create(h.N)));
            return h;
        }
    }
}
