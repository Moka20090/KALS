// the kOS side of the ENTRY TRAJ background job (KalsAddon.Traj.cs registers TJBG / TJBGFAM): the inputs
// copied into plain C# on the main thread (TjBgKos), and the handle the suffixes return (TjBgHandle). kOS.Safe only.
using System;
using System.Collections.Generic;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    public static class TjBgKos
    {
        public static TjBgHandle Start(string root, StringValue fam, StringValue side, StringValue tpl)
        {
            var h = new TjBgHandle();
            try
            {
                var job = new TjBgJob { Root = root, FamRel = fam.ToString(), SideRel = side.ToString(), TplRel = tpl.ToString() };
                h.Start(job);
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }

        public static TjBgHandle StartFam(string root, ListValue members, Lexicon opts)
        {
            var h = new TjBgHandle();
            try
            {
                var f = new TjFamily();
                foreach (var kv in opts)
                {
                    string k = kv.Key.ToString();
                    if (k == "side" || k == "tpl" || k == "dmax" || k == "pngdir") continue;
                    var sv = kv.Value as ScalarValue;
                    if (sv != null) f.Hdr[k] = sv.GetDoubleValue();
                    else f.Hdr[k] = kv.Value.ToString();
                }
                // famWrite's rounding (lib_fam.ks: bank 2, then the columns 2, 5, 3, 1, 2 decimals; kOS ROUND = Math.Round)
                var ms = new List<TjMember>();
                foreach (Structure s in members)
                {
                    var m = s as ListValue;
                    if (m == null || m.Count < 6) throw new InvalidCastException("a member is not LIST(bank, vs, ds, ss, rg, bk, ...)");
                    var cols = new ListValue[5];
                    for (int c = 0; c < 5; c++)
                    {
                        cols[c] = m[c + 1] as ListValue;
                        if (cols[c] == null) throw new InvalidCastException("a member's column " + (c + 1) + " is not a list");
                    }
                    int n = cols[0].Count;
                    if (n == 0) continue;                          // a member that never flew (a partial family)
                    var tm = new TjMember { Bank = Math.Round(Num(m[0]), 2) };
                    int[] dec = { 2, 5, 3, 1, 2 };
                    for (int k = 0; k < n; k++)
                    {
                        var r = new double[5];
                        for (int c = 0; c < 5; c++) r[c] = Math.Round(Num(cols[c][k]), dec[c]);
                        tm.Rows.Add(r);
                    }
                    ms.Add(tm);
                }
                ms.Sort((a, b) => a.Bank.CompareTo(b.Bank));       // List.Sort is not stable: banks are distinct
                f.M = ms;
                // the provenance keys gen_traj_bg's validate_family asks for but the drawing never reads
                f.Hdr["version"] = 1.0;
                f.Hdr["members"] = (double)ms.Count;
                foreach (string k in new[] { "tcoast", "geo_t0", "tbuild", "r0", "v0", "plan_burn_ut", "plan_aim" })
                    if (!f.Hdr.ContainsKey(k)) f.Hdr[k] = 0.0;
                if (!f.Hdr.ContainsKey("aero_ver")) throw new KeyNotFoundException("TJBGFAM: no \"aero_ver\"");
                var job = new TjBgJob { Root = root, Fam = f, SideRel = Str(opts, "side", null), TplRel = Str(opts, "tpl", null) };
                job.DMax = (int)Math.Round(NumKey(opts, "dmax", 50));
                string pd = Str(opts, "pngdir", null);
                if (pd != null) job.PngDir = pd;
                h.Start(job);
            }
            catch (Exception ex) { h.Fail(ex.GetType().Name + ": " + ex.Message); }
            return h;
        }

        static double Num(Structure s)
        {
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException("a family value is not a number");
            return sv.GetDoubleValue();
        }

        static string Str(Lexicon l, string k, string dflt)
        {
            Structure s;
            return l.TryGetValue(new StringValue(k), out s) ? s.ToString() : dflt;
        }

        static double NumKey(Lexicon l, string k, double dflt)
        {
            Structure s;
            if (!l.TryGetValue(new StringValue(k), out s)) return dflt;
            return Num(s);
        }
    }

    [KOSNomenclature("KALSTrajBg")]
    public class TjBgHandle : Structure
    {
        TjBgJob job;
        volatile bool failed;
        string err = "";

        public TjBgHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => failed || (job != null && job.Done)));
            AddSuffix("OK", new Suffix<BooleanValue>(() => !failed && job != null && job.Done && job.Ok));
            AddSuffix("WHY", new Suffix<StringValue>(() => failed ? err : (job == null || !job.Done ? "" : job.Why)));
            AddSuffix("UPTODATE", new Suffix<BooleanValue>(() => !failed && job != null && job.Done && job.UpToDate));
            AddSuffix("SIDE", new Suffix<StringValue>(() => job == null ? "" : job.SideRel.Replace('\\', '/').Replace("0:/", "").TrimStart('/')));
            AddSuffix("MS", new Suffix<ScalarValue>(() => job != null && job.Done ? job.Ms : -1));
        }

        public void Fail(string why) { err = why; failed = true; }

        public void Start(TjBgJob j)
        {
            if (j.SideRel == null || j.TplRel == null) { Fail("TJBG: no sidecar or template path"); return; }
            job = j;
            var t = new Thread(j.Run);
            t.IsBackground = true;
            t.Priority = ThreadPriority.BelowNormal;
            t.Start();
        }

        public override string ToString() { return "KALSTrajBg(" + (job == null ? "failed" : job.Done ? (job.Ok ? "ok" : "failed") : "running") + ")"; }
    }
}
