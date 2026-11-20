// The bridge between kOS and the C# PEG (Peg.cs), for KalsAddon's PEGCYCLE.
// kOS's asc_peg_cycle(p, t, rr, vv, dvs, M, VEX, ATR) mutates the lexicon p in place; the C# Peg keeps its state in plain
// fields. One call = FromKos (p's inputs -> a fresh Peg) -> Peg.Cycle -> ToKos (what the pass changed -> p, IN PLACE).
// THE KEY RULES (mirroring lib_ascent_peg.ks's SETs one by one):
//   * the lists TB / TGOA / TAU / VEXA / LA / SA / QA keep their ListValue objects (kOS code aliases them): elements are
//     written in place, and only where the value changed; the nested lexicons p["TAL"], p["RTLS"] likewise (read only,
//     except RTLS's RTHETA / close / VGOD / ERR / ERR_C / K / iy_save);
//   * a key kOS creates only later is created only when kOS would have created it (the "lazy" keys: rbias .. on the
//     first pass, TGOP / TP every pass, S / L / J / Q / JOL / QPRIME / lam / lamd / LAMDMAG / TLAM / rthrust / vthrust
//     only when the pass got past A-6's early RETURN, rd / ix / vd / vmiss when the target (asc_peg_tgt) ran, tal_* on a
//     TAL target); a sentinel (double.MinValue) in Peg's write-only fields tells "this pass set it";
//   * ints (N, KPHASE, npass, unconv) are ScalarIntValue; a number kOS held as an integer stays one while it is whole;
//     vectors are new kOS Vectors; tnow / rnow / vnow / Mnow / VEXnow / ATRnow / TPRIME are the call's own argument objects
//     (kOS's SET stores the reference);
//   * ALL outputs are built first and written last: any exception (a key missing, a type wrong, a NaN / Infinity in the
//     result) leaves p untouched and the caller flies the pass in kOS.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class PegKos
    {
        public const double NOSET = double.MinValue;     // "this write-only field was not set by the pass"

        // ------------------------------------------------------------------ reading kOS values
        static StringValue Key(string k) { return new StringValue(k); }

        static Structure Get(Lexicon l, string k)
        {
            Structure s;
            if (!l.TryGetValue(Key(k), out s)) throw new KeyNotFoundException("p[\"" + k + "\"] missing");
            return s;
        }

        static bool Has(Lexicon l, string k) { return l.ContainsKey(Key(k)); }

        static double Dd(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException("a number was expected, not " + (s == null ? "null" : s.GetType().Name));
            double d = sv.GetDoubleValue();
            // a NaN / Infinity in p could make Peg.Coast's UNTIL loop endless, and this runs on KSP's main thread
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("a number in p is not finite");
            return d;
        }

        static int Ii(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException("an integer was expected, not " + (s == null ? "null" : s.GetType().Name));
            double d = sv.GetDoubleValue();
            if (d != Math.Floor(d) || Math.Abs(d) > 2147483647.0) throw new InvalidCastException("not an integer: " + d);
            return (int)d;
        }

        static bool Bb(Structure s)
        {
            var bv = s as BooleanValue;
            if (bv == null) throw new InvalidCastException("a boolean was expected, not " + (s == null ? "null" : s.GetType().Name));
            return bv.Value;
        }

        static Vec3 Vc(Structure s)
        {
            var v = s as kOS.Suffixed.Vector;
            if (v == null) throw new InvalidCastException("a vector was expected, not " + (s == null ? "null" : s.GetType().Name));
            var w = v.ToVector3D();
            return new Vec3(w.x, w.y, w.z);
        }

        static double Dk(Lexicon l, string k) { return Dd(Get(l, k)); }
        static Vec3 Vk(Lexicon l, string k) { return Vc(Get(l, k)); }

        static ListValue Lst(Lexicon l, string k, int n)
        {
            var lv = Get(l, k) as ListValue;
            if (lv == null) throw new InvalidCastException("p[\"" + k + "\"] is not a list");
            if (lv.Count != n) throw new ArgumentException("p[\"" + k + "\"] has " + lv.Count + " items, needs " + n);
            return lv;
        }

        static double[] Arr(Lexicon l, string k, int n)
        {
            var lv = Lst(l, k, n);
            var a = new double[n];
            for (int i = 0; i < n; i++) a[i] = Dd(lv[i]);
            return a;
        }

        // ------------------------------------------------------------------ the writes (collected, then applied)
        class Writes
        {
            public List<Lexicon> LexT = new List<Lexicon>();
            public List<StringValue> LexK = new List<StringValue>();
            public List<Structure> LexV = new List<Structure>();
            public List<ListValue> ListT = new List<ListValue>();
            public List<int> ListI = new List<int>();
            public List<Structure> ListV = new List<Structure>();

            static void Finite(double d, string k)
            {
                if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException("p[\"" + k + "\"] would not be a finite number");
            }

            // a number: kOS keeps an integer an integer while the value stays whole
            static Structure Num(double v, Structure cur)
            {
                var cs = cur as ScalarValue;
                if (cs != null && cs.IsInt && v == Math.Floor(v) && Math.Abs(v) < 2147483647.0) return new ScalarIntValue((int)v);
                return new ScalarDoubleValue(v);
            }

            void Put(Lexicon l, StringValue k, Structure v) { LexT.Add(l); LexK.Add(k); LexV.Add(v); }

            // create: the key may be made when it does not exist yet (a "lazy" key kOS would have SET this pass)
            public void D(Lexicon l, string k, double v, bool create)
            {
                Finite(v, k);
                var key = Key(k);
                Structure cur;
                if (!l.TryGetValue(key, out cur)) { if (create) Put(l, key, new ScalarDoubleValue(v)); return; }
                var cs = cur as ScalarValue;
                if (cs != null && cs.GetDoubleValue() == v) return;
                Put(l, key, Num(v, cur));
            }

            public void I(Lexicon l, string k, int v)
            {
                var key = Key(k);
                Structure cur;
                if (l.TryGetValue(key, out cur))
                {
                    var cs = cur as ScalarValue;
                    if (cs != null && cs.IsInt && cs.GetIntValue() == v) return;
                }
                Put(l, key, new ScalarIntValue(v));
            }

            public void B(Lexicon l, string k, bool v, bool create)
            {
                var key = Key(k);
                Structure cur;
                if (!l.TryGetValue(key, out cur)) { if (create) Put(l, key, new BooleanValue(v)); return; }
                var cb = cur as BooleanValue;
                if (cb != null && cb.Value == v) return;
                Put(l, key, new BooleanValue(v));
            }

            public void V(Lexicon l, string k, Vec3 v, bool create)
            {
                Finite(v.X, k); Finite(v.Y, k); Finite(v.Z, k);
                var key = Key(k);
                Structure cur;
                if (!l.TryGetValue(key, out cur)) { if (create) Put(l, key, new kOS.Suffixed.Vector(v.X, v.Y, v.Z)); return; }
                var cv = cur as kOS.Suffixed.Vector;
                if (cv != null)
                {
                    var w = cv.ToVector3D();
                    if (w.x == v.X && w.y == v.Y && w.z == v.Z) return;
                }
                Put(l, key, new kOS.Suffixed.Vector(v.X, v.Y, v.Z));
            }

            public void S(Lexicon l, string k, Structure v) { Put(l, Key(k), v); }     // unconditional (the call's own objects)

            public void Elem(ListValue lv, int i, double v)
            {
                Finite(v, "list item " + i);
                var cs = lv[i] as ScalarValue;
                if (cs != null && cs.GetDoubleValue() == v) return;
                ListT.Add(lv); ListI.Add(i); ListV.Add(Num(v, lv[i]));
            }

            public void List(ListValue lv, double[] a, int from)
            {
                for (int i = from; i < a.Length; i++) Elem(lv, i, a[i]);
            }

            public void Apply()
            {
                for (int i = 0; i < LexT.Count; i++) LexT[i][LexK[i]] = LexV[i];
                for (int i = 0; i < ListT.Count; i++) ListT[i][ListI[i]] = ListV[i];
            }
        }

        // ------------------------------------------------------------------ one pass
        // a = LIST(t, rr, vv, dvs, M, VEX, ATR); p is updated in place; throws (p untouched) on any failure
        public static void Cycle(Lexicon p, ListValue a)
        {
            if (a.Count != 7) throw new ArgumentException("PEGCYCLE: the argument list needs 7 items (t, rr, vv, dvs, M, VEX, ATR), has " + a.Count);
            Structure tS = a[0], rrS = a[1], vvS = a[2], MS = a[4], VEXS = a[5], ATRS = a[6];
            double t = Dd(tS), M = Dd(MS), VEX = Dd(VEXS), ATR = Dd(ATRS);
            Vec3 rr = Vc(rrS), vv = Vc(vvS), dvs = Vc(a[3]);
            foreach (double x in new double[] { t, M, VEX, ATR, rr.X, rr.Y, rr.Z, vv.X, vv.Y, vv.Z, dvs.X, dvs.Y, dvs.Z })
                if (double.IsNaN(x) || double.IsInfinity(x)) throw new ArithmeticException("PEGCYCLE: an argument is not a finite number");
            // Peg.Coast runs for TGO s in about NSEG steps whatever TGO is, as long as it is a number: a zero / tiny ATR or an
            // overflow would make TGO NaN and its UNTIL loop endless (here on KSP's main thread), so those are refused (kOS flies the pass)
            if (!(M > 0 && VEX > 0 && ATR > 0 && VEX / ATR < 1.0e9)) throw new ArithmeticException("PEGCYCLE: M, VEX, ATR out of range (" + M + ", " + VEX + ", " + ATR + ")");

            var pg = new Peg(Dk(p, "RDMAG"), Dk(p, "GAMD"), Dk(p, "VDMAG"), Vk(p, "IYD"), Dk(p, "MASS_MIN"), Dk(p, "mu"));
            bool firstp = Bb(Get(p, "S_INIT"));
            pg.S_INIT = firstp;
            pg.S_GDRDY = Bb(Get(p, "S_GDRDY")); pg.SCONV = Bb(Get(p, "SCONV")); pg.low_tw = Bb(Get(p, "low_tw"));
            pg.SALT = Bb(Get(p, "SALT")); pg.SPLANE = Bb(Get(p, "SPLANE"));
            pg.N = Ii(Get(p, "N")); pg.KPHASE = Ii(Get(p, "KPHASE")); pg.npass = Ii(Get(p, "npass")); pg.unconv = Ii(Get(p, "unconv"));
            if (pg.N != 2) throw new ArgumentException("PEGCYCLE: N is " + pg.N + ", the port flies N = 2");
            if (pg.KPHASE < 1 || pg.KPHASE > 2) throw new ArgumentException("PEGCYCLE: KPHASE " + pg.KPHASE);
            ListValue tbL = Lst(p, "TB", 3), tgoaL = Lst(p, "TGOA", 3), tauL = Lst(p, "TAU", 3), vexaL = Lst(p, "VEXA", 3),
                laL = Lst(p, "LA", 3), saL = Lst(p, "SA", 3), qaL = Lst(p, "QA", 3);
            for (int i = 0; i < 3; i++)
            {
                pg.TB[i] = Dd(tbL[i]); pg.TGOA[i] = Dd(tgoaL[i]); pg.TAU[i] = Dd(tauL[i]); pg.VEXA[i] = Dd(vexaL[i]);
                pg.LA[i] = Dd(laL[i]); pg.SA[i] = Dd(saL[i]); pg.QA[i] = Dd(qaL[i]);
            }
            pg.lamc = Vk(p, "lamc"); pg.lamdc = Vk(p, "lamdc"); pg.vgo = Vk(p, "vgo");
            if (!((pg.vgo - dvs).Mag < 1.0e12)) throw new ArithmeticException("PEGCYCLE: |vgo| is not a sane number");
            pg.tlamc = Dk(p, "tlamc"); pg.TGO = Dk(p, "TGO"); pg.PHI = Dk(p, "PHI");
            if (!firstp)                                      // read before this pass sets them: must exist (kOS would stop otherwise)
            {
                pg.rbias = Vk(p, "rbias"); pg.omega = Vk(p, "omega"); pg.rgrav = Vk(p, "rgrav");
                pg.TPRIME = Dk(p, "TPRIME"); pg.TPREV = Dk(p, "TPREV"); pg.iy = Vk(p, "iy");
                pg.rp = Vk(p, "rp"); pg.vp = Vk(p, "vp");
                pg.rd = Vk(p, "rd"); pg.ix = Vk(p, "ix");          // A-6 reads the last pass's target position and plane axis
            }
            else
            {
                if (Has(p, "rbias")) pg.rbias = Vk(p, "rbias");
                if (Has(p, "rgrav")) pg.rgrav = Vk(p, "rgrav");
                if (Has(p, "rd")) pg.rd = Vk(p, "rd");
                if (Has(p, "ix")) pg.ix = Vk(p, "ix");
            }
            pg.TP = Has(p, "TP") ? Dk(p, "TP") : double.NaN;      // kOS: p:HASKEY("TP")
            if (Has(p, "lam")) pg.lam = Vk(p, "lam");
            if (Has(p, "lamd")) pg.lamd = Vk(p, "lamd");
            // the write-only fields: the sentinel says "not set by this pass"
            var nov = new Vec3(NOSET, NOSET, NOSET);
            pg.vd = nov; pg.vmiss = nov; pg.rthrust = nov; pg.vthrust = nov;
            pg.S = NOSET; pg.L = NOSET; pg.J = NOSET; pg.Q = NOSET; pg.JOL = NOSET; pg.QPRIME = NOSET;
            pg.LAMDMAG = NOSET; pg.TLAM = NOSET; pg.TGOP = NOSET;
            pg.tal_rth = NOSET; pg.tal_cr = NOSET; pg.tal_tca = NOSET;

            var tlx = Get(p, "TAL") as Lexicon;
            var rlx = Get(p, "RTLS") as Lexicon;
            if (tlx == null || rlx == null) throw new InvalidCastException("p[\"TAL\"] / p[\"RTLS\"] must be lexicons");
            if (tlx.Count > 0)
            {
                var ts = new TalSite { Ef = Vk(tlx, "ef"), W = Dk(tlx, "w"), A = Arr(tlx, "A", 4), VMIN = Dk(tlx, "VMIN"),
                    VMAX = Dk(tlx, "VMAX"), CRMAX = Dk(tlx, "CRMAX") };
                if (Has(tlx, "RDMAG")) ts.RDMAG = Dk(tlx, "RDMAG");
                if (Has(tlx, "GAMD")) ts.GAMD = Dk(tlx, "GAMD");
                if (Has(tlx, "hold")) ts.Hold = true;           // kOS's tl:HASKEY("hold") (the key's value is not read)
                if (Has(tlx, "iyef")) { ts.Iyef = Vk(tlx, "iyef"); ts.HasIyef = true; }
                pg.Tal = ts;                                  // not SetTal: p's own RDMAG / GAMD stay as they are
            }
            RtlsData rd = null;
            if (rlx.Count > 0)
            {
                rd = new RtlsData { Ef = Vk(rlx, "ef"), W = Dk(rlx, "w"), A = Arr(rlx, "A", 2), RTMAG = Dk(rlx, "RTMAG"),
                    iy_save = Vk(rlx, "iy_save"), K = Dk(rlx, "K"), K_CMD = Dk(rlx, "K_CMD"), STHROT = Bb(Get(rlx, "STHROT")),
                    MBO = Dk(rlx, "MBO"), MDOT = Dk(rlx, "MDOT"), KMIN = Dk(rlx, "KMIN"), KMAX = Dk(rlx, "KMAX"),
                    DELK_MAX = Dk(rlx, "DELK_MAX"), KMISS = Dk(rlx, "KMISS"), RNG_TURN_PRED = Dk(rlx, "RNG_TURN_PRED") };
                rd.RTHETA = NOSET; rd.VGOD = NOSET; rd.ERR = NOSET; rd.ERR_C = NOSET;
                pg.Rtls = rd;
            }

            pg.Cycle(t, rr, vv, dvs, M, VEX, ATR);

            // ---------------------------------------------------------- what the pass set: built first, written last
            bool reached = pg.QPRIME != NOSET;                // got past A-6's early RETURN
            bool tgt = firstp || reached;                     // asc_peg_tgt ran
            var w = new Writes();
            // the pass's own SETs at its start (all keys exist from asc_peg_new)
            w.I(p, "npass", pg.npass);
            w.B(p, "upd", pg.upd, true); w.B(p, "tp_ok", pg.tp_ok, true); w.B(p, "mass_ok", pg.mass_ok, true); w.B(p, "first", pg.first, true);
            w.S(p, "tnow", tS); w.S(p, "rnow", rrS); w.S(p, "vnow", vvS);
            w.S(p, "Mnow", MS); w.S(p, "VEXnow", VEXS); w.S(p, "ATRnow", ATRS);
            w.S(p, "TPRIME", tS);
            // state that exists from asc_peg_new: written where it changed
            w.B(p, "S_INIT", pg.S_INIT, true); w.B(p, "S_GDRDY", pg.S_GDRDY, true); w.B(p, "SCONV", pg.SCONV, true);
            w.B(p, "low_tw", pg.low_tw, true); w.B(p, "SALT", pg.SALT, true); w.B(p, "SPLANE", pg.SPLANE, true);
            w.I(p, "KPHASE", pg.KPHASE); w.I(p, "unconv", pg.unconv);
            w.D(p, "TGO", pg.TGO, true); w.D(p, "PHI", pg.PHI, true); w.D(p, "tlamc", pg.tlamc, true); w.D(p, "VDMAG", pg.VDMAG, true);
            w.V(p, "vgo", pg.vgo, true); w.V(p, "lamc", pg.lamc, true); w.V(p, "lamdc", pg.lamdc, true);
            // the lists, in place
            w.List(tbL, pg.TB, 0); w.List(tgoaL, pg.TGOA, 0); w.List(tauL, pg.TAU, 0); w.List(vexaL, pg.VEXA, 0);
            w.List(laL, pg.LA, 0); w.List(saL, pg.SA, 0); w.List(qaL, pg.QA, 0);
            // keys kOS creates at the first pass (and updates later)
            w.V(p, "rbias", pg.rbias, firstp); w.V(p, "omega", pg.omega, firstp); w.V(p, "rgrav", pg.rgrav, firstp);
            w.D(p, "TPREV", pg.TPREV, firstp); w.V(p, "iy", pg.iy, firstp); w.V(p, "rp", pg.rp, firstp); w.V(p, "vp", pg.vp, firstp);
            // every pass: TGOP, TP
            w.D(p, "TGOP", pg.TGOP, true); w.D(p, "TP", pg.TP, true);
            // the target (asc_peg_tgt)
            if (tgt) { w.V(p, "rd", pg.rd, true); w.V(p, "ix", pg.ix, true); }
            if (pg.vd.X != NOSET) w.V(p, "vd", pg.vd, true);
            if (pg.vmiss.X != NOSET) w.V(p, "vmiss", pg.vmiss, true);
            if (pg.tal_rth != NOSET)
            {
                w.D(p, "tal_rth", pg.tal_rth, true); w.D(p, "tal_cr", pg.tal_cr, true); w.D(p, "tal_tca", pg.tal_tca, true);
            }
            // past the early RETURN
            if (reached)
            {
                w.D(p, "S", pg.S, true); w.D(p, "L", pg.L, true); w.D(p, "J", pg.J, true); w.D(p, "Q", pg.Q, true);
                w.D(p, "JOL", pg.JOL, true); w.D(p, "QPRIME", pg.QPRIME, true);
                w.V(p, "lam", pg.lam, true); w.V(p, "lamd", pg.lamd, true);
                w.D(p, "LAMDMAG", pg.LAMDMAG, true); w.D(p, "TLAM", pg.TLAM, true);
                w.V(p, "rthrust", pg.rthrust, true); w.V(p, "vthrust", pg.vthrust, true);
            }
            // PEG's own RTLS results
            if (rd != null && tgt)
            {
                if (rd.RTHETA != NOSET) { w.D(rlx, "RTHETA", rd.RTHETA, true); w.B(rlx, "close", rd.close, true); }
                if (rd.VGOD != NOSET) w.D(rlx, "VGOD", rd.VGOD, true);
                if (rd.ERR != NOSET) w.D(rlx, "ERR", rd.ERR, true);
                if (rd.ERR_C != NOSET) w.D(rlx, "ERR_C", rd.ERR_C, true);
                w.D(rlx, "K", rd.K, true);
                w.V(rlx, "iy_save", rd.iy_save, true);
            }
            w.Apply();
        }
    }
}
