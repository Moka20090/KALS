// THE ARD SEARCH, line for line lib/lib_ascent_ard.ks (ard_srch_go / ard_srch_unit's path and levels, ard_lv_k0s,
// ard_lv_next, ard_lv_job, ard_sa_job, ard_seek, ard_pe_next, ard_bis_start, ard_bis_next, ard_lv_open / never / end, the
// rank ard_rk_go / ard_rk_unit), the flights Fts.cs's FtsJob / RtJob. Each level is its own context (LvRun: the search's
// per-level fields of S), so the levels run in parallel; kOS's units (S["u"]) are counted per level and summed in kOS's
// order (the soonest seek start first, the list's order on a tie), so every log line's unit count is kOS's.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    // ard_lv_new's level
    public class ArdLv
    {
        public string key, dk, md, site; public int e; public TalSite tl;
        public double tb = -1, vb = -1, bv = -1; public bool lat; public string note = ""; public int nc, nq;
    }

    // a finished level's or the rank's log entry (kOS builds the text: ard_lv_end's / ard_rk_unit's)
    public class ArdEv { public string kind, key, note, site; public double tb, vb, m; public int k0, npts, u, e; }

    // a flight: FtsJob or RtJob (ard_unit / ard_margin)
    public class ArdJob
    {
        public FtsJob f; public RtJob r; public bool rtNew;
        public bool Unit() { return f != null ? f.Unit() : r.Unit(); }
        public double Margin() { return f != null ? f.Margin() : r.Margin(); }
        public int St { get { return f != null ? f.st : r.st; } }
    }

    // the snapshot (ard_new's lexicon a)
    public class ArdSnap
    {
        public string md; public TalSite tl; public int e; public double K, t, et, mc, res, f1, vex, tlamc;
        public Vec3 r, v, iy, lamc, lamdc, rs; public double[] o; public KLex sh;
    }

    public class ArdSrch
    {
        public PadC C; public ArdSnap sn; public KLex seed; public List<ArdLv> lv = new List<ArdLv>();
        public List<string> tlsKeys = new List<string>(); public Dictionary<string, TalSite> tls = new Dictionary<string, TalSite>();
        public int nrun, u0, nref; public bool ok2;
        public double[] rtlLine; public double rtlMbo; public bool rtlHas;      // S["rtl"]: the PPD line by MBO
        public List<FtsPt> pts; public int pathUnits;
        public Dictionary<string, int> k0 = new Dictionary<string, int>(); public Dictionary<string, bool> qk = new Dictionary<string, bool>();
        public List<LvRun> runs = new List<LvRun>();
        public List<RkRun> rk = new List<RkRun>();
        public List<ArdEv> ev = new List<ArdEv>(); public List<string> dn = new List<string>();
        public int u; public bool nopath; public bool rank;
        public double tRef;

        public ArdSrch(PadC c) { C = c; }

        // the path (ph 1): the selected mode on the running SSMEs at the flown throttle, its trace
        public void Path()
        {
            var j = new FtsJob(C.F, sn.md, sn.tl, sn.e, sn.K, sn.t, sn.r, sn.v, sn.et, sn.mc, sn.res, sn.iy, sn.lamc, sn.lamdc, sn.tlamc,
                sn.o, sn.f1, sn.vex);
            j.tr = true; j.ts = -1;
            tRef = sn.t;
            int nn = 0;
            while (true) { nn++; if (j.Unit()) break; }
            pathUnits = nn;
            pts = j.pts;
            nopath = pts.Count < 2;
        }

        // ard_lv_k0s
        public void K0s()
        {
            int n = pts.Count;
            var pv = new double[n];
            for (int k = 0; k < n; k++) pv[k] = pts[k].v.Mag;
            foreach (var x in lv)
            {
                int kk0 = n - 2; bool q = false; double vs = -1;
                if (string.Equals(x.note, "never", StringComparison.OrdinalIgnoreCase))
                {
                    if (x.md == "TAL" && x.bv >= 0 && x.nq < C.ARD_NEVER_Q)
                    {
                        q = true;
                        kk0 = 0;
                        for (int k = 1; k < n; k++) if (Math.Abs(pv[k] - x.bv) < Math.Abs(pv[kk0] - x.bv)) kk0 = k;
                    }
                }
                else if (x.vb >= 0 && x.vb < C.ARD_NEVER / 2)
                {
                    vs = x.vb;
                    if (sn.sh != null && sn.sh.Has(x.dk)) vs = vs + sn.sh.D(x.dk);
                }
                else if (seed.Has(x.dk)) vs = seed.D(x.dk);
                if (vs >= 0)
                {
                    kk0 = n - 1;
                    for (int k = 0; k < n; k++) if (pv[k] >= vs) { kk0 = k - 1; break; }
                    kk0 = (int)Math.Max(0, Math.Min(kk0, n - 2));
                }
                k0[x.key] = kk0; qk[x.key] = q;
            }
        }

        // the levels in kOS's order (ard_lv_next: the least seek start not latched, the list's order on a tie)
        public List<int> Order()
        {
            var o = new List<int>();
            var done = new HashSet<int>();
            while (true)
            {
                int bi = -1, bk = 0;
                for (int i = 0; i < lv.Count; i++)
                {
                    if (!lv[i].lat && !done.Contains(i) && k0.ContainsKey(lv[i].key))
                        if (bi < 0 || k0[lv[i].key] < bk) { bi = i; bk = k0[lv[i].key]; }
                }
                if (bi < 0) return o;
                done.Add(bi); o.Add(bi);
            }
        }

        // ard_lv_job: the level's abort from path point P
        public ArdJob LvJob(ArdLv l, FtsPt P)
        {
            if (l.md == "RTLS")
            {
                var rj = new RtJob(C.F, sn.mc, sn.res, sn.f1, sn.vex, sn.rs, l.e, P.t, P.r, P.v, P.et, P.om, P.iy,
                    rtlHas ? rtlLine : null, rtlMbo);
                return new ArdJob { r = rj, rtNew = rj.st == 0 };
            }
            double[] o = P.o;
            if (o.Length == 0 && l.md == "TAL" && C.TAL_DUMP > 0)
                o = new double[] { P.t + C.TAL_OMS_DELAY, P.t + C.TAL_OMS_DELAY + C.TAL_DUMP / C.ARD_MDO };
            var j = new FtsJob(C.F, l.md, l.tl, l.e, C.KMAX_ABORT, P.t, P.r, P.v, P.et, sn.mc - P.om, sn.res, P.iy, P.lamc, P.lamdc,
                P.tlamc, o.Length == 2 ? o : null, sn.f1, sn.vex);
            j.ts = -1;
            return new ArdJob { f = j };
        }

        // ard_sa_job: the path's flight from P, stopped at tm
        public FtsJob SaJob(FtsPt P, double tm)
        {
            var j = new FtsJob(C.F, sn.md, sn.tl, sn.e, sn.K, P.t, P.r, P.v, P.et, sn.mc - P.om, sn.res, P.iy, P.lamc, P.lamdc, P.tlamc,
                P.o.Length == 2 ? P.o : null, sn.f1, sn.vex);
            j.tr = true; j.ts = tm;
            return j;
        }

        // the levels' results in kOS's order, the units, the rank's
        public void Finish()
        {
            u = u0 + pathUnits;
            if (nopath) return;
            u = u + 1;                                // the seek starts' unit (fk "k0")
            foreach (int i in Order())
            {
                var lr = runs[i];
                dn.Add(lv[i].key);
                u = u + lr.units;
                lr.ev.u = u;
                ev.Add(lr.ev);
            }
            nref = nref + 1;
            if (nrun == 2) ok2 = true;
            rank = C.ARD_RANK_ON && tlsKeys.Count > 0 && pts.Count > 0;
            if (!rank) return;
            foreach (var r in rk)
            {
                u = u + 1 + r.units;
                ev.Add(new ArdEv { kind = "RK", site = r.site, m = r.m, e = r.e, u = u });
            }
            u = u + 1;
            ev.Add(new ArdEv { kind = "RKEND", u = u });
        }
    }

    // one rank site (ard_rk_unit's flight): a TAL on MIN(nrun, 2) SSMEs from the path's first point
    public class RkRun
    {
        public string site; public int e, units; public double m;
        public void Run(ArdSrch S)
        {
            var l = new ArdLv { key = "TAL_RK_" + site, dk = "TAL_RK", e = e, md = "TAL", site = site, tl = S.tls[site] };
            var j = S.LvJob(l, S.pts[0]);
            int nn = 0;
            while (true) { nn++; if (j.Unit()) break; }
            units = nn;
            m = j.Margin();
        }
    }

    // ONE LEVEL's seek (the search's per-level fields of S; ard_srch_unit's ph 2 branch, a call = a unit)
    public class LvRun
    {
        ArdSrch S; ArdLv lv;
        ArdJob fj; FtsJob fs;                           // the job in hand (fs: a state-at job)
        string fk; int kk, k0, dir, nb, plo, phi, pit; bool rescan, q1; double nbm, pb, ma, mb;
        List<int> msK = new List<int>(); Dictionary<int, double> ms = new Dictionary<int, double>();
        Dictionary<int, double[]> pe = new Dictionary<int, double[]>();
        FtsPt Pa, Pb, Pm;
        public int units; public bool ended; public ArdEv ev; public bool rtNew; public double[] rtLine; public double rtMbo;

        public LvRun(ArdSrch s, ArdLv l) { S = s; lv = l; }

        // ard_lv_next's tail for this level
        public void Run()
        {
            k0 = S.k0[lv.key]; kk = k0; dir = 0; rescan = false; q1 = S.qk[lv.key];
            MsClear();
            fk = "m";
            string ky = lv.key;
            if (S.C.ARD_COARSE && !q1 && (S.C.ARD_PE_B.Has(ky) || ky == "ATO" || (ky == "ATO_2EO" && S.nrun == 3)))
            {
                pe = new Dictionary<int, double[]>();
                plo = -1; phi = -1; pit = 0;
                if (S.C.ARD_PE_B.Has(ky)) pb = S.C.ARD_PE_B.D(ky);
                else pb = 0 - S.sn.vex * Math.Log(1 + S.sn.res / (S.sn.mc - S.pts[k0].om));
                fk = "pe";
            }
            while (!ended) Unit();
        }

        void MsClear() { msK = new List<int>(); ms = new Dictionary<int, double>(); }
        void MsSet(int k, double m) { if (!ms.ContainsKey(k)) msK.Add(k); ms[k] = m; }

        void Unit()
        {
            units++;
            if (fj == null && fs == null)
            {
                if (fk == "sa") fs = S.SaJob(Pa, 0.5 * (Pa.t + Pb.t));
                else
                {
                    if (fk == "mb") fj = S.LvJob(lv, Pm); else fj = S.LvJob(lv, S.pts[kk]);
                    if (lv.md != "RTLS") fj.f.hstep = lv.e >= 2 ? S.C.ARD_JDT : S.C.ARD_JDT1;
                    if (fj.rtNew) rtNew = true;
                }
                return;
            }
            if (fk == "pe")
            {
                fj.Unit();
                FtsJob jp = fj.f;
                if (jp.st == 0) return;
                fj = null;
                bool cv = jp.st == 1 && jp.p.SCONV;
                double est = -1E9;
                if (cv)
                {
                    double M = jp.mc - jp.om + jp.et;
                    double left = jp.et - jp.res;
                    double dva = 0;
                    if (left > 0 && left < M) dva = jp.vex * Math.Log(M / (M - left));
                    est = dva - jp.p.vgo.Mag;
                }
                pe[kk] = new double[] { est, cv ? 1 : 0 };
                PeNext();
                return;
            }
            if (fs != null)
            {
                if (!fs.Unit()) return;
                var j0 = fs; fs = null;
                var pm = j0.pts[j0.pts.Count - 1].Copy();
                pm.om = pm.om + Pa.om;
                Pm = pm;
                fk = "mb";
                return;
            }
            if (!fj.Unit()) return;
            var j = fj; fj = null;
            if (j.r != null && j.rtNew && j.r.st != 0) { rtLine = j.r.line; rtMbo = j.r.MBO; S.rtlHas = true; S.rtlLine = rtLine; S.rtlMbo = rtMbo; }
            double m = j.Margin();
            if (fk == "mb")
            {
                nb = nb + 1;
                if (m < 0) { Pa = Pm; ma = m; } else { Pb = Pm; mb = m; }
                BisNext();
                return;
            }
            MsSet(kk, m);
            Seek(m);
        }

        void Seek(double m)
        {
            int n = S.pts.Count;
            while (true)
            {
                int k = kk;
                if (dir == 0 && q1 && m < 0) { Never(); return; }
                if (dir == 0) { if (m < 0) dir = 1; else dir = -1; }
                if (dir > 0)
                {
                    if (m >= 0)
                    {
                        if (k == 0) { Open(); return; }
                        BisStart(k - 1, k);
                        return;
                    }
                    if (k >= n - 1)
                    {
                        if (k0 > 0 && !rescan && lv.md == "TAL") { rescan = true; kk = 0; dir = 0; }
                        else { Never(); return; }
                    }
                    else kk = k + 1;
                }
                else
                {
                    if (m < 0) { BisStart(k, k + 1); return; }
                    if (k == 0) { Open(); return; }
                    kk = k - 1;
                }
                if (!ms.ContainsKey(kk)) { fk = "m"; return; }
                m = ms[kk];
            }
        }

        void PeNext()
        {
            int n = S.pts.Count;
            double B = pb;
            double sd = S.C.ARD_PE_SD.D(lv.key);
            int k = kk;
            while (pit < S.C.ARD_PE_IT)
            {
                if (!pe.ContainsKey(k)) { kk = k; return; }
                double pev = pe[k][0];
                bool cv = pe[k][1] != 0;
                if (!cv || pev < B)
                {
                    plo = k;
                    if (k >= n - 1) { Never(); return; }
                    double jj = 1;
                    if (cv) jj = Math.Max(1, Math.Min(4, KM.Round((B - pev) / (sd * 8))));
                    k = (int)Math.Min(n - 1, k + jj);
                }
                else
                {
                    phi = k;
                    if (k == 0) { Open(); return; }
                    k = (int)Math.Max(0, k - Math.Max(1, Math.Min(4, KM.Round((pev - B) / (sd * 8)))));
                }
                pit = pit + 1;
                if (plo >= 0 && phi >= 0)
                {
                    if (phi - plo == 1) break;
                    k = (int)Math.Floor((plo + phi) / 2.0);
                }
            }
            int lo = plo, hi = phi;
            if (lo < 0 || hi < 0 || hi - lo != 1 || pe[lo][1] == 0)
            {
                kk = hi > 0 ? hi - 1 : Math.Max(0, lo);
                dir = 0;
                MsClear();
                fk = "m";
                return;
            }
            FtsPt pa = S.pts[lo], pbb = S.pts[hi];
            double f = (B - pe[lo][0]) / (pe[hi][0] - pe[lo][0]);
            double sh = 0;
            if (S.C.ARD_PE_TB.Has(lv.key)) sh = S.C.ARD_PE_TB.D(lv.key) / (pbb.t - pa.t);
            lv.tb = pa.t + (f + sh) * (pbb.t - pa.t);
            lv.vb = pa.v.Mag + (f + sh) * (pbb.v.Mag - pa.v.Mag);
            k0 = lo;
            End("");
        }

        void BisStart(int ka, int kb)
        {
            Pa = S.pts[ka]; Pb = S.pts[kb];
            ma = ms[ka]; mb = ms[kb];
            nb = 0;
            nbm = Pa.t - S.pts[0].t < S.C.ARD_NEAR ? S.C.ARD_NBIS_NEAR : S.C.ARD_NBIS;
            BisNext();
        }

        void BisNext()
        {
            if (nb < nbm && lv.md != "RTLS") { fk = "sa"; return; }
            double f = ma / (ma - mb);
            lv.tb = Pa.t + f * (Pb.t - Pa.t);
            lv.vb = Pa.v.Mag + f * (Pb.v.Mag - Pa.v.Mag);
            End("");
        }

        void Open()
        {
            lv.tb = S.pts[0].t;
            lv.vb = S.pts[0].v.Mag;
            lv.lat = true;
            End("open");
        }

        void Never()
        {
            lv.tb = -1;
            lv.vb = S.C.ARD_NEVER;
            if (q1) lv.nq = lv.nq + 1;
            else if (msK.Count > 0)
            {
                int kb = 0; double mx = -1E30;
                foreach (int k in msK) if (ms[k] > mx) { mx = ms[k]; kb = k; }
                lv.bv = S.pts[kb].v.Mag;
                lv.nq = 0;
            }
            End("never");
        }

        void End(string nt)
        {
            lv.note = nt;
            lv.nc = lv.nc + 1;
            ev = new ArdEv { kind = "L", key = lv.key, tb = lv.tb, vb = lv.vb, note = nt, k0 = k0, npts = S.pts.Count };
            ended = true;
        }
    }
}
