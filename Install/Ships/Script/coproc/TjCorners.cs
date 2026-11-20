// The ENTRY TRAJ panels' screen frame, redrawn at the PNG write: a line-for-line C# port of tools/screen_corners.py
// (measure, _shape_cov, round_screen) for an OPAQUE RGB page. The panels are drawn at run time (TrajBg.cs, opaque RGB, square
// black corners); TrajBgJob.Work passes each one through Round() before TjPng.EncodeRgba. The drawing itself is not changed.
// Round() never throws: a page with no frame (or a sprite) comes back as the same pixels, opaque RGBA.
// Constants as the python: radius 14 (the rim's outer radius), SS 6 (supersampling), MIN_CONTENT 3.
using System;
using System.Collections.Generic;

namespace KalsCoproc
{
    public static class TjCorners
    {
        public const double Radius = 14.0;
        const int SS = 6;
        const int MinContent = 3;

        sealed class Measure
        {
            public double X0, X1, Y0, Y1, T;
            public double[] Rim = new double[3], Bg = new double[3];
        }

        /// rgb: w*h*3 bytes, row-major. Returns w*h*4 RGBA bytes (alpha 0 outside the rounded rim).
        public static byte[] Round(byte[] rgb, int w, int h, double radius = Radius)
        {
            var m = Measure1(rgb, w, h);
            if (m == null)
            {
                var plain = new byte[w * h * 4];
                for (int i = 0; i < w * h; i++)
                {
                    plain[i * 4] = rgb[i * 3]; plain[i * 4 + 1] = rgb[i * 3 + 1]; plain[i * 4 + 2] = rgb[i * 3 + 2]; plain[i * 4 + 3] = 255;
                }
                return plain;
            }
            double x0 = m.X0, x1 = m.X1, y0 = m.Y0, y1 = m.Y1, t = m.T;
            double[] rim = m.Rim, bg = m.Bg;
            float[] covO = ShapeCov(w, h, x0, y0, x1, y1, radius);
            float[] covI = ShapeCov(w, h, x0 + t, y0 + t, x1 - t, y1 - t, radius - t);
            float[] keep = ShapeCov(w, h, x0 + t + MinContent, y0 + t + MinContent, x1 - t - MinContent, y1 - t - MinContent,
                                    Math.Max(0.0, radius - t - MinContent));
            var outp = new byte[w * h * 4];
            for (int p = 0; p < w * h; p++)
            {
                bool k = keep[p] > 0.999f;
                float ring = covO[p] - covI[p];
                float al = covO[p];
                for (int c = 0; c < 3; c++)
                {
                    double basev = k ? rgb[p * 3 + c] : bg[c];
                    double pm = rim[c] * ring + basev * covI[p];
                    double v = al > 1e-4f ? pm / Math.Max(al, 1e-4f) : bg[c];
                    outp[p * 4 + c] = ClampByte(Math.Round(v, MidpointRounding.ToEven));
                }
                outp[p * 4 + 3] = ClampByte(Math.Round(al * 255.0, MidpointRounding.ToEven));
            }
            return outp;
        }

        static byte ClampByte(double v)
        {
            if (v < 0) return 0;
            if (v > 255) return 255;
            return (byte)v;
        }

        // python round(): half to even
        static double PyRound(double v)
        {
            return Math.Round(v, MidpointRounding.ToEven);
        }

        static double Median(List<double> v)
        {
            v.Sort();
            int n = v.Count;
            return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0;
        }

        // the most common value; ties go to the smallest (np.unique sorts, argmax takes the first)
        static int MostCommon(Dictionary<int, int> counts)
        {
            int best = -1, bestN = -1;
            foreach (var kv in counts)
            {
                if (kv.Value > bestN || (kv.Value == bestN && kv.Key < best)) { best = kv.Key; bestN = kv.Value; }
            }
            return best;
        }

        static int Pack(byte[] rgb, int p) { return (rgb[p * 3] << 16) | (rgb[p * 3 + 1] << 8) | rgb[p * 3 + 2]; }

        static double Cov(double col, double bgG, double rimG)
        {
            double v = (col - bgG) / (rimG - bgG);
            return v < 0 ? 0 : (v > 1 ? 1 : v);
        }

        // the first rim run along a line from the edge inwards: (outer edge offset, thickness); null when none
        static bool Run(double[] cov, out double outer, out double tot)
        {
            outer = 0; tot = 0;
            int n = cov.Length, i = 0;
            while (i < n && cov[i] < 0.02) i++;
            if (i >= n) return false;
            int j = i;
            double sum = 0;
            while (j < n && cov[j] >= 0.02) { sum += cov[j]; j++; }
            double lead = cov[i];
            outer = lead < 0.98 ? i + (1.0 - lead) : (double)i;
            tot = sum;
            return true;
        }

        static Measure Measure1(byte[] rgb, int w, int h)
        {
            if (w < 150 || h < 150) return null;
            // the page colour: the most common colour of every 7th pixel
            var cnt = new Dictionary<int, int>();
            for (int p = 0; p < w * h; p += 7)
            {
                int key = Pack(rgb, p);
                int v; cnt.TryGetValue(key, out v); cnt[key] = v + 1;
            }
            int bgKey = MostCommon(cnt);
            var bg = new double[] { (bgKey >> 16) & 255, (bgKey >> 8) & 255, bgKey & 255 };
            double bgG = bg[1];

            // the rim colour: the most common bright green within 16 px of the border, at its full green
            var cand = new List<int>();
            int maxG = -1;
            var candG = new List<int>();
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    bool ring = y < 16 || y >= h - 16 || x < 16 || x >= w - 16;
                    if (!ring) continue;
                    int p = y * w + x;
                    int g = rgb[p * 3 + 1];
                    if (g > 150) { candG.Add(g); if (g > maxG) maxG = g; cand.Add(Pack(rgb, p)); }
                }
            if (cand.Count == 0) return null;
            var rc = new Dictionary<int, int>();
            for (int i = 0; i < cand.Count; i++)
            {
                if (candG[i] < maxG - 1) continue;
                int v; rc.TryGetValue(cand[i], out v); rc[cand[i]] = v + 1;
            }
            int rimKey = MostCommon(rc);
            double rimG = (rimKey >> 8) & 255;
            var rim = new double[] { (rimKey >> 16) & 255, rimG, rimKey & 255 };

            int[] rows = { h / 3, h / 2, 2 * h / 3 };
            int[] cols = { w / 3, w / 2, 2 * w / 3 };
            var rA = new List<double>(); var rB = new List<double>();   // row lines: outer offsets from the left / right
            var rT = new List<double>();                                 // thicknesses (rows and columns)
            int nRes = 0;
            foreach (int r in rows)
            {
                var line = new double[w];
                for (int x = 0; x < w; x++) line[x] = Cov(rgb[(r * w + x) * 3 + 1], bgG, rimG);
                double oa, ta, ob, tb;
                bool a = Run(line, out oa, out ta);
                var rev = new double[w];
                for (int x = 0; x < w; x++) rev[x] = line[w - 1 - x];
                bool b = Run(rev, out ob, out tb);
                if (a && b) { rA.Add(oa); rB.Add(ob); rT.Add(ta); rT.Add(tb); nRes++; }
            }
            var cA = new List<double>(); var cB = new List<double>();
            foreach (int c in cols)
            {
                var line = new double[h];
                for (int y = 0; y < h; y++) line[y] = Cov(rgb[(y * w + c) * 3 + 1], bgG, rimG);
                double oa, ta, ob, tb;
                bool a = Run(line, out oa, out ta);
                var rev = new double[h];
                for (int y = 0; y < h; y++) rev[y] = line[h - 1 - y];
                bool b = Run(rev, out ob, out tb);
                if (a && b) { cA.Add(oa); cB.Add(ob); rT.Add(ta); rT.Add(tb); }
            }
            if (nRes == 0 || cA.Count == 0) return null;

            var m = new Measure();
            m.X0 = Median(new List<double>(rA));
            m.X1 = w - Median(new List<double>(rB));
            m.Y0 = Median(new List<double>(cA));
            m.Y1 = h - Median(new List<double>(cB));
            double t = Median(new List<double>(rT));
            t = PyRound(t * 2.0) / 2.0;

            Func<double, double> q = v => PyRound(v * SS) / SS;
            double lr = q((m.X0 + (w - m.X1)) / 2.0);
            if (Math.Abs(m.X0 - (w - m.X1)) < 1.0) { m.X0 = lr; m.X1 = w - lr; }
            m.X0 = q(m.X0); m.X1 = q(m.X1); m.Y0 = q(m.Y0); m.Y1 = q(m.Y1);
            m.T = t;
            m.Rim = rim; m.Bg = bg;
            return m;
        }

        // coverage (0..1) of a rounded rectangle on the w x h grid, SS x SS samples per pixel
        static float[] ShapeCov(int w, int h, double x0, double y0, double x1, double y1, double rad)
        {
            var outp = new float[w * h];
            if (x1 <= x0 || y1 <= y0) return outp;
            rad = Math.Max(0.0, Math.Min(rad, Math.Min((x1 - x0) / 2.0, (y1 - y0) / 2.0)));
            double cx = (x0 + x1) / 2.0, cy = (y0 + y1) / 2.0;
            double hw = (x1 - x0) / 2.0 - rad, hh = (y1 - y0) / 2.0 - rad;
            var off = new double[SS];
            for (int s = 0; s < SS; s++) off[s] = (s + 0.5) / SS;
            var dxs = new double[w * SS];
            for (int px = 0; px < w; px++)
                for (int s = 0; s < SS; s++)
                {
                    double xs = px + off[s];
                    dxs[px * SS + s] = Math.Max(Math.Abs(xs - cx) - hw, 0.0);
                }
            for (int py = 0; py < h; py++)
            {
                var dys = new double[SS];
                for (int s = 0; s < SS; s++)
                {
                    double ys = py + off[s];
                    dys[s] = Math.Max(Math.Abs(ys - cy) - hh, 0.0);
                }
                for (int px = 0; px < w; px++)
                {
                    int n = 0;
                    for (int sy = 0; sy < SS; sy++)
                        for (int sx = 0; sx < SS; sx++)
                        {
                            double dx = dxs[px * SS + sx], dy = dys[sy];
                            if (Math.Sqrt(dx * dx + dy * dy) <= rad) n++;
                        }
                    outp[py * w + px] = (float)n / (SS * SS);
                }
            }
            return outp;
        }
    }
}
