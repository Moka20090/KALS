// one ENTRY TRAJ background job, the files side of TrajBg.cs: read the family (family.txt, or a family
// handed over in memory), draw the five panels, encode them (TjPng), write them and the sidecar. Pure managed code
// (mscorlib): it runs on a worker thread (KalsAddon.Traj.cs starts it) and touches no Unity or kOS object.
// Files (all under root = kOS's archive, Ships/Script; every path the caller names is relative to it):
//   * the PNGs: <pngDir>/traj<n>_w<written in ms>[_d100][_a<lo>-<hi>].png -- a new family is a new path, so kOS's image
//     cache (by path) never shows an old picture; the other traj*_w*.png in pngDir (older families) are deleted;
//   * the sidecar (sideRel): gen_traj_bg.py's text exactly, except each P line names its PNG as <pngDir>/<name>; written
//     last, through a temp file, so a reader never sees a sidecar whose PNGs are not all there.
// "Up to date": when the sidecar already names this family (its written line) and every PNG it lists exists, nothing is
// drawn (Why = "uptodate", Ok).
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace KalsCoproc
{
    public sealed class TjBgJob
    {
        public string Root, FamRel, SideRel, TplRel, PngDir = "traj_cs";
        public TjFamily Fam;                 // the family in memory (TJBGFAM), else read from FamRel
        public int DMax = 50;                // the drag strip's top: 50, or 100 (gen_traj_bg's $TRAJ_DMAX 100, the TAL pages)
        public volatile bool Done;
        public bool Ok; public string Why = "", Log = "";
        public double Ms = -1, DrawMs = -1, PngMs = -1;
        public bool UpToDate;

        /// A path under root from a caller's relative one ("0:/" and "/" prefixes allowed); null when it would leave root.
        public static string Under(string root, string rel)
        {
            if (rel == null) return null;
            string r = rel.Replace('\\', '/');
            if (r.StartsWith("0:")) r = r.Substring(2);
            r = r.TrimStart('/');
            if (r.Length == 0 || r.Contains("..") || r.Contains(":")) return null;
            return Path.Combine(root, r.Replace('/', Path.DirectorySeparatorChar));
        }

        public void Run()
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            try { Work(); }
            catch (Exception ex) { Ok = false; Why = ex.GetType().Name + ": " + ex.Message; }
            Ms = sw.Elapsed.TotalMilliseconds;
            Done = true;
        }

        void Work()
        {
            string side = Under(Root, SideRel), tpl = Under(Root, TplRel), pdir = Under(Root, PngDir);
            if (side == null || tpl == null || pdir == null) { Why = "a path is not under the archive"; return; }
            if (DMax != 50 && DMax != 100) { Why = "dmax must be 50 or 100"; return; }
            TjFamily f = Fam;
            if (f == null)
            {
                string fp = Under(Root, FamRel);
                if (fp == null) { Why = "the family path is not under the archive"; return; }
                if (!File.Exists(fp)) { Why = "no family file " + FamRel; return; }
                f = TjFamily.Read(fp);
            }
            if (!(f.Hdr.ContainsKey("written") && f.Hdr["written"] is double)) { Why = "the family has no written stamp"; return; }
            double written = (double)f.Hdr["written"];
            // "_r14" = the round-corner pass (TjCorners): families on disk from before it are redrawn (a new path)
            string stamp = "w" + TjPy.F(written * 1000.0, 0) + (DMax == 100 ? "_d100" : "") + "_r14";
            string pdirRel = PngDir.Replace('\\', '/').TrimEnd('/');
            if (pdirRel.StartsWith("0:")) pdirRel = pdirRel.Substring(2);
            pdirRel = pdirRel.TrimStart('/');

            if (Current(side, TjPy.F(written, 3), stamp)) { Ok = true; UpToDate = true; Why = "uptodate"; return; }

            var T = TjTemplate.LoadCached(tpl);
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var tb = new TrajBg(T);
            TjResult res = tb.Run(f, (n, name) => pdirRel + "/" + Stamped(name, stamp), DMax);
            DrawMs = sw.Elapsed.TotalMilliseconds;
            Log = res.Log;
            if (!res.Ok) { Why = res.Why; return; }
            sw.Reset(); sw.Start();
            Directory.CreateDirectory(pdir);
            var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var P in res.Panels)
            {
                string fn = Path.GetFileName(P.Name);
                keep.Add(fn);
                WriteAtomic(Path.Combine(pdir, fn), TjPng.EncodeRgba(TjCorners.Round(P.Rgb, T.W, T.H), T.W, T.H));
            }
            Directory.CreateDirectory(Path.GetDirectoryName(side));
            WriteAtomic(side, Encoding.ASCII.GetBytes(res.Sidecar));
            PngMs = sw.Elapsed.TotalMilliseconds;
            // the older families' pictures (the current ones were just written)
            try
            {
                foreach (string old in Directory.GetFiles(pdir, "traj*_w*.png"))
                    if (!keep.Contains(Path.GetFileName(old)))
                        try { File.Delete(old); } catch (Exception) { }
            }
            catch (Exception) { }
            Ok = true;
        }

        /// traj<n>.png -> traj<n>_<stamp>.png; traj<n>_a10-35.png -> traj<n>_<stamp>_a10-35.png
        static string Stamped(string name, string stamp)
        {
            string b = name.Substring(0, name.Length - 4);
            int u = b.IndexOf('_');
            return u < 0 ? b + "_" + stamp + ".png" : b.Substring(0, u) + "_" + stamp + b.Substring(u) + ".png";
        }

        static bool HasStamp(string name, string stamp)
        {
            return name.Contains("_" + stamp + ".png") || name.Contains("_" + stamp + "_a");
        }

        /// The sidecar names this family and drag strip, and each PNG it lists exists.
        bool Current(string side, string writtenTxt, string stamp)
        {
            if (!File.Exists(side)) return false;
            bool w = false; int np = 0;
            foreach (string raw in File.ReadAllLines(side))
            {
                string l = raw.Trim();
                if (l == "written " + writtenTxt) w = true;
                if (l.StartsWith("P "))
                {
                    string[] p = l.Split(' ');
                    if (p.Length != 12 || !HasStamp(p[7], stamp)) return false;
                    string png = Under(Root, p[7]);
                    if (png == null || !File.Exists(png)) return false;
                    np++;
                }
            }
            return w && np > 0;
        }

        static void WriteAtomic(string path, byte[] data)
        {
            string tmp = path + ".tmp";
            File.WriteAllBytes(tmp, data);
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
    }
}
