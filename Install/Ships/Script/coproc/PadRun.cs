// THE PAD SEARCH JOB. From one input lexicon (the constants, E TAL's start, the ARD's pad state and levels, the
// sweep's switch) it runs, on up to N worker threads (below-normal priority): E TAL (one task: its sites in order, each seeds
// the next) || the stage-1 predictor + the path, then every level, every rank site and the sweep (independent tasks). The
// worker touches no kOS / Unity object: everything is plain C# (KLex) in and out; kOS polls DONE and writes the results.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

namespace KalsCoproc
{
    // a fixed set of worker threads over one queue; a task may add tasks; Run returns when all are done
    public class WorkQ
    {
        readonly Queue<Action> q = new Queue<Action>();
        readonly object lk = new object();
        int pending;
        public Exception Err;
        public void Add(Action a) { lock (lk) { pending++; q.Enqueue(a); Monitor.PulseAll(lk); } }
        void Worker()
        {
            while (true)
            {
                Action a;
                lock (lk)
                {
                    while (q.Count == 0 && pending > 0) Monitor.Wait(lk);
                    if (q.Count == 0) { Monitor.PulseAll(lk); return; }
                    a = q.Dequeue();
                }
                try { a(); }
                catch (Exception ex) { lock (lk) { if (Err == null) Err = ex; } }
                lock (lk) { pending--; if (pending == 0) Monitor.PulseAll(lk); }
            }
        }
        public void Run(int n)
        {
            var th = new List<Thread>();
            for (int i = 0; i < n; i++)
            {
                var t = new Thread(Worker);
                t.IsBackground = true;
                t.Priority = ThreadPriority.BelowNormal;
                th.Add(t);
                t.Start();
            }
            foreach (var t in th) t.Join();
        }
    }

    public class PadJob
    {
        public KLex inp; public int threads = 2;
        public KLex etlRes, ardRes, bglRes;
        public double msTotal, msEtl, msArd, msBgl;
        public string err = "";
        PadC C; Etal E; ArdSrch S; Bgl G;

        public PadJob(KLex input)
        {
            inp = input;
            int ncpu = Environment.ProcessorCount;
            threads = Math.Max(1, Math.Min(4, ncpu - 1));
            if (inp.Has("threads") && inp.D("threads") >= 1) threads = (int)Math.Min(16, inp.D("threads"));
            // everything that can fail on bad input is read here, on the caller's thread
            var c = inp.L("c");
            C = new PadC(c, inp.Has("etl"), inp.Has("ard"), inp.Has("bgl") && inp.Has("ard"));
            PadC.SetPeg(c);
            if (inp.Has("etl")) E = new Etal(C, inp.L("etl"));
            if (inp.Has("ard")) S = Ard(inp.L("ard"));
        }

        ArdSrch Ard(KLex a)
        {
            var s = new ArdSrch(C);
            var t = a.L("a");
            var sn = new ArdSnap();
            sn.md = t.S("md"); sn.e = t.I("e"); sn.K = t.D("K"); sn.mc = t.D("mc"); sn.res = t.D("res"); sn.iy = t.V("iy");
            sn.f1 = t.L("m").D("f1"); sn.vex = t.L("m").D("vex"); sn.rs = t.V("rs");
            var o = t.A("o"); sn.o = o.Count == 2 ? new double[] { KLex.Num(o[0], "o"), KLex.Num(o[1], "o") } : null;
            if (sn.md == "TAL") sn.tl = PadC.Site(t.L("tl"));
            if (t.Has("sh")) sn.sh = t.L("sh");
            if (t.Has("t"))
            {
                sn.t = t.D("t"); sn.r = t.V("r"); sn.v = t.V("v"); sn.et = t.D("et");
                var st = t.A("steer"); sn.lamc = (Vec3)st[0]; sn.lamdc = (Vec3)st[1]; sn.tlamc = KLex.Num(st[2], "steer");
            }
            s.sn = sn;
            s.seed = a.L("seed");
            var tl = a.L("tls");
            foreach (var k in tl.Keys) { s.tlsKeys.Add(k); s.tls[k] = PadC.Site(tl.L(k)); }
            foreach (var x in a.A("lv"))
            {
                var l = (KLex)x;
                var v = new ArdLv { key = l.S("key"), dk = l.S("dk"), e = l.I("e"), md = l.S("md"), site = l.S("site"), tb = l.D("tb"),
                    vb = l.D("vb"), lat = l.B("lat"), note = l.S("note"), nc = l.I("nc"), bv = l.D("bv"), nq = l.I("nq") };
                if (v.md == "TAL") v.tl = PadC.Site(l.L("tl"));
                s.lv.Add(v);
            }
            s.nrun = a.I("nrun"); s.u0 = a.I("u"); s.nref = a.I("nref"); s.ok2 = a.B("ok2");
            var rl = a.L("rtl");
            if (rl.Has("mbo")) { s.rtlHas = true; s.rtlMbo = rl.D("mbo"); s.rtlLine = rl.DA("line"); }
            return s;
        }

        double s1t, s1et; Vec3 s1r, s1v; int s1n;
        bool s1po;                            // the stage-1 start past the tower clear (the result's "s1po": p0[5] read)

        // the pad's stage 1 to the separation (asc_ard_pad: ard_et_s1(p0, -1, vh), ard_s1_step until done, ard_et_sep), then the
        // (or a state in flight's: p0 with its tower clear and tail-off tangent)
        // snapshot's state and steering (the horizontal speed's direction, PEG cold)
        void ArdStage1(KLex a)
        {
            if (!a.Has("p0")) return;
            var p0 = a.A("p0");
            var v = a.L("vh");
            var vh = new S1Veh { mc = v.D("mc"), sdry = v.D("sdry"), ssmd = v.D("ssmd"), knom = v.D("knom"), kabt = v.D("kabt"),
                dpsi = v.D("dpsi"), south = v.B("south") };
            bool po = false; double tc = -99;     // a state in flight carries p0[5], p0[6] (ard_et_s1)
            if (p0.Count > 6) { po = S1Pred.PoOf(p0[5]); tc = KLex.Num(p0[6], "p0"); }
            var s1 = new S1Pred(C, KLex.Num(p0[0], "p0"), (Vec3)p0[1], (Vec3)p0[2], KLex.Num(p0[3], "p0"), KLex.Num(p0[4], "p0"), po, tc, -1, 2, vh);
            while (!s1.Step()) { }
            s1n = s1.n;
            s1po = po;
            s1.Sep(out s1t, out s1r, out s1v, out s1et);
            var sn = S.sn;
            sn.t = s1t; sn.r = s1r; sn.v = s1v; sn.et = s1et;
            Vec3 ru = s1r.Normalized;
            sn.lamc = (s1v - Vec3.Dot(s1v, ru) * ru).Normalized; sn.lamdc = Vec3.Zero; sn.tlamc = s1t;
        }

        public void Run()
        {
            var sw = Stopwatch.StartNew();
            try
            {
                var Q = new WorkQ();
                if (E != null) Q.Add(delegate { var w = Stopwatch.StartNew(); E.Run(); etlRes = E.Result(); msEtl = w.Elapsed.TotalMilliseconds; });
                if (S != null)
                {
                    bool bgl = inp.Has("bgl");
                    Q.Add(delegate
                    {
                        var w = Stopwatch.StartNew();
                        ArdStage1(inp.L("ard"));
                        S.Path();
                        if (S.nopath) return;
                        S.K0s();
                        foreach (var l in S.lv) S.runs.Add(new LvRun(S, l));
                        foreach (int i in S.Order()) { var r = S.runs[i]; Q.Add(delegate { r.Run(); }); }
                        if (C.ARD_RANK_ON && S.tlsKeys.Count > 0 && S.pts.Count > 0)
                            foreach (var k in S.tlsKeys) { var r = new RkRun { site = k, e = Math.Min(S.nrun, 2) }; S.rk.Add(r); Q.Add(delegate { r.Run(S); }); }
                        if (bgl) Q.Add(delegate { var wb = Stopwatch.StartNew(); G = new Bgl(C, S.pts, S.sn); G.Run(); bglRes = G.Result(); msBgl = wb.Elapsed.TotalMilliseconds; });
                        msArd = w.Elapsed.TotalMilliseconds;   // the path's (the levels' run on)
                    });
                }
                Q.Run(threads);
                if (Q.Err != null) throw Q.Err;
                if (S != null) { S.Finish(); ardRes = ArdResult(); }
            }
            catch (Exception ex) { err = ex.GetType().Name + ": " + ex.Message; }
            msTotal = sw.Elapsed.TotalMilliseconds;
        }

        static List<object> VL(params object[] x) { return new List<object>(x); }

        KLex ArdResult()
        {
            var r = new KLex();
            r["sp"] = VL(s1t, s1r, s1v, s1et);
            r["s1n"] = s1n;
            r["s1po"] = s1po;                     // the in-flight start understood (ops1q checks the key)
            r["nopath"] = S.nopath;
            var pl = new List<object>();
            foreach (var p in S.pts)
            {
                var x = new KLex();
                x["t"] = p.t; x["r"] = p.r; x["v"] = p.v; x["et"] = p.et; x["om"] = p.om;
                x["steer"] = VL(p.lamc, p.lamdc, p.tlamc); x["iy"] = p.iy;
                var o = new List<object>(); foreach (var d in p.o) o.Add(d); x["o"] = o;
                pl.Add(x);
            }
            r["pts"] = pl;
            var lv = new List<object>();
            foreach (var l in S.lv)
            {
                var x = new KLex();
                x["key"] = l.key; x["tb"] = l.tb; x["vb"] = l.vb; x["lat"] = l.lat; x["note"] = l.note; x["nc"] = l.nc; x["bv"] = l.bv; x["nq"] = l.nq;
                lv.Add(x);
            }
            r["lv"] = lv;
            var ev = new List<object>();
            foreach (var e in S.ev)
            {
                if (e.kind == "L") ev.Add(VL("L", e.key, e.tb, e.vb, e.note, e.k0, e.npts, e.u));
                else if (e.kind == "RK") ev.Add(VL("RK", e.site, e.m, e.e, e.u));
                else ev.Add(VL("RKEND", e.u));
            }
            r["ev"] = ev;
            r["u"] = S.u; r["nref"] = S.nref; r["ok2"] = S.ok2; r["rank"] = S.rank; r["path_u"] = S.pathUnits;
            var rk = new KLex();
            foreach (var x in S.rk) rk[x.site] = VL(x.m, S.tRef, x.e);
            r["rk"] = rk;
            var k0 = new KLex();
            foreach (var l in S.lv) if (S.k0.ContainsKey(l.key)) k0[l.key] = VL(S.k0[l.key], S.qk[l.key]);
            r["k0s"] = k0;
            var dn = new List<object>(); foreach (var k in S.dn) dn.Add(k); r["dn"] = dn;
            var rt = new KLex();
            if (S.rtlHas) { rt["mbo"] = S.rtlMbo; var ln = new List<object>(); foreach (var d in S.rtlLine) ln.Add(d); rt["line"] = ln; }
            r["rtl"] = rt;
            return r;
        }
    }
}
