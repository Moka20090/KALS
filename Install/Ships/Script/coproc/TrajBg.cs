// The ENTRY TRAJ backgrounds (traj1..5.png + the sidecar traj_bg.txt) drawn in C#, so no python runs at
// flight time. A line-for-line port of gen_traj_bg.py (read_family, validate_family, aoa_schedule, panel_bands, row_at,
// family_lines, drag_ladder, drag_loci, LabelSpace, draw_panel, _verify, _verify_strip_labels, main) in python's float
// semantics (CPython 3.12+ sum(), %-format rounding of the exact binary value, round() half to even).
// What matplotlib draws, the C# reproduces this way:
//   * the family-independent under-layer of each panel (frame, header, strips, readout labels) is a TEMPLATE drawn by
//     gen_traj_bg's own code (gen_traj_tpl.py -> traj_tpl/tpl_<scale>.bin, RGB run-length coded); so are gen_traj_bg's
//     module constants (never retyped here), a glyph atlas and the label strings' layout, both measured from matplotlib;
//   * the lines: Agg's geometry (stroke width lw * dpi / 72, round joins, projecting caps on solid lines, butt caps on
//     dashes and the notch, dashes DASH * lw restarting at each sub-path, the path clipped to the canvas + 1 px, the
//     field clip box rounded to pixels), its coverage by 16 x 16 supersampling (Agg: exact area, 8-bit), its blender
//     (fixed_blender_rgba_plain) exactly;
//   * the text: each glyph from the atlas at the nearest of 8 x 8 sub-pixel phases (matplotlib: 1/64 px), the label's
//     background box snapped to pixels as Agg snaps a rectilinear path.
// Pure managed code (mscorlib): it runs on a worker thread and touches no Unity or kOS object.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace KalsCoproc
{
    // ---------------------------------------------------------------- python number semantics
    public static class TjPy
    {
        /// python float(s) for the decimal strings kOS writes: Clinger's exact fast path (<= 15 digits and |exp| <= 22 is
        /// one correctly rounded IEEE operation), else the runtime's parser.
        public static double Float(string s)
        {
            int i = 0, n = s.Length;
            bool neg = false;
            if (i < n && (s[i] == '+' || s[i] == '-')) { neg = s[i] == '-'; i++; }
            ulong m = 0; int digits = 0, exp10 = 0; bool any = false, dot = false, ok = true;
            for (; i < n; i++)
            {
                char c = s[i];
                if (c >= '0' && c <= '9')
                {
                    any = true;
                    if (m == 0 && c == '0') { if (dot) exp10--; continue; }
                    if (digits >= 18) { ok = false; break; }
                    m = m * 10 + (ulong)(c - '0'); digits++;
                    if (dot) exp10--;
                }
                else if (c == '.' && !dot) dot = true;
                else break;
            }
            if (ok && any && i < n && (s[i] == 'e' || s[i] == 'E'))
            {
                i++;
                bool en = false;
                if (i < n && (s[i] == '+' || s[i] == '-')) { en = s[i] == '-'; i++; }
                int e = 0; bool ed = false;
                for (; i < n && s[i] >= '0' && s[i] <= '9'; i++) { ed = true; if (e < 10000) e = e * 10 + (s[i] - '0'); }
                if (!ed) ok = false;
                exp10 += en ? -e : e;
            }
            if (ok && any && i == n && m <= (1UL << 53) && exp10 >= -22 && exp10 <= 22)
            {
                double v = m;
                if (exp10 < 0) v /= Pow10(-exp10); else if (exp10 > 0) v *= Pow10(exp10);
                return neg ? -v : v;
            }
            return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        static double Pow10(int k) { double p = 1; for (int j = 0; j < k; j++) p *= 10; return p; }    // exact to 1e22

        /// python '%.<nd>f' % x: the exact binary value rounded half to even (nd 0..3).
        public static string F(double x, int nd)
        {
            if (double.IsNaN(x)) return "nan";
            if (double.IsInfinity(x)) return x > 0 ? "inf" : "-inf";
            long bits = BitConverter.DoubleToInt64Bits(x);
            bool neg = bits < 0;
            int ex = (int)((bits >> 52) & 0x7ff);
            ulong frac = (ulong)bits & ((1UL << 52) - 1);
            ulong mant; int e;
            if (ex == 0) { mant = frac; e = -1074; } else { mant = frac | (1UL << 52); e = ex - 1075; }
            ulong p10 = 1; for (int k = 0; k < nd; k++) p10 *= 10;
            string digits;
            if (e >= 0)
            {
                double ax = Math.Abs(x);
                if (ax >= 1.8e19) return x.ToString("R", CultureInfo.InvariantCulture);  // never here
                digits = ((ulong)ax).ToString(CultureInfo.InvariantCulture) + new string('0', nd);
            }
            else
            {
                ulong N = mant * p10;                    // < 2^53 * 1000 < 2^63
                int k = -e;
                ulong q, rem, half;
                if (k >= 64) { q = 0; rem = N; half = ulong.MaxValue; }       // N < 2^63 <= half: rounds to 0
                else
                {
                    q = N >> k; rem = N - (q << k); half = 1UL << (k - 1);
                    if (rem > half || (rem == half && (q & 1) == 1)) q++;
                }
                digits = q.ToString(CultureInfo.InvariantCulture);
            }
            if (nd > 0)
            {
                if (digits.Length <= nd) digits = new string('0', nd - digits.Length + 1) + digits;
                digits = digits.Substring(0, digits.Length - nd) + "." + digits.Substring(digits.Length - nd);
            }
            return (neg ? "-" : "") + digits;
        }

        /// python round(x) -> int: half to even.
        public static long Round(double x) { return (long)Math.Round(x, MidpointRounding.ToEven); }

        /// CPython 3.12+ builtin sum() over floats (Neumaier-compensated), start 0.
        public static double Sum(List<double> xs)
        {
            if (xs.Count == 0) return 0;
            double f = 0.0, c = 0.0;
            bool first = true;
            foreach (double x in xs)
            {
                if (first) { f = x; first = false; continue; }      // 0 + x0 is x0: the int start turns into the first float
                double t = f + x;
                if (Math.Abs(f) >= Math.Abs(x)) c += (f - t) + x; else c += (x - t) + f;
                f = t;
            }
            if (c != 0.0 && !double.IsInfinity(c) && !double.IsNaN(c)) f += c;
            return f;
        }

        /// python '%g' for the integer-valued tick numbers.
        public static string G(double x)
        {
            if (x == Math.Floor(x) && Math.Abs(x) < 1e6) return ((long)x).ToString(CultureInfo.InvariantCulture);
            return x.ToString("G6", CultureInfo.InvariantCulture);
        }
    }

    // ---------------------------------------------------------------- the family (read_family / validate_family)
    public sealed class TjMember
    {
        public double Bank;
        public List<double[]> Rows = new List<double[]>();      // (vrel m/s, drag m/s2, sink, range m, flown bank deg)
    }

    public sealed class TjFamily
    {
        public Dictionary<string, object> Hdr = new Dictionary<string, object>();   // double, double[] or string (vessel)
        public List<TjMember> M = new List<TjMember>();

        public static TjFamily Read(string path) { return Parse(File.ReadAllText(path)); }

        public static TjFamily Parse(string text)
        {
            var f = new TjFamily();
            TjMember cur = null;
            foreach (string line in text.Split('\n'))
            {
                string raw = line.Trim();
                if (raw.Length == 0) continue;
                string[] parts = raw.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
                if (parts[0] == "M")
                {
                    if (cur != null) f.M.Add(cur);
                    cur = new TjMember { Bank = TjPy.Float(parts[2]) };
                }
                else if (cur != null && parts.Length >= 5)
                {
                    var r = new double[5];
                    for (int k = 0; k < 5; k++) r[k] = TjPy.Float(parts[k]);
                    cur.Rows.Add(r);
                }
                else if (parts.Length >= 2)
                {
                    if (parts[0] == "vessel") f.Hdr["vessel"] = string.Join(" ", parts, 1, parts.Length - 1);
                    else if (parts.Length == 2) f.Hdr[parts[0]] = TjPy.Float(parts[1]);
                    else
                    {
                        var v = new double[parts.Length - 1];
                        for (int k = 1; k < parts.Length; k++) v[k - 1] = TjPy.Float(parts[k]);
                        f.Hdr[parts[0]] = v;
                    }
                }
            }
            if (cur != null) f.M.Add(cur);
            return f;
        }

        public bool Has(string k) { return Hdr.ContainsKey(k); }
        public double Num(string k) { return (double)Hdr[k]; }

        public string Validate(double version)
        {
            object v;
            if (!Hdr.TryGetValue("version", out v) || !(v is double) || (double)v != version) return "unknown version";
            foreach (string k in new[] { "tcoast", "geo_t0", "tbuild", "r0", "v0", "plan_burn_ut", "plan_aim", "members", "aero_ver" })
                if (!Hdr.ContainsKey(k)) return "missing key " + k;
            if (M.Count < 2) return "only " + M.Count + " member(s)";
            if (!(Hdr["members"] is double)) return "header members is not a number";
            if (M.Count != (int)Num("members")) return "header says " + (int)Num("members") + " members, found " + M.Count;
            for (int i = 1; i < M.Count; i++) if (M[i].Bank < M[i - 1].Bank) return "members not in bank order";
            foreach (var m in M) if (m.Rows.Count == 0) return "a member has no rows";   // python: an IndexError later
            return "";
        }
    }

    // ---------------------------------------------------------------- the template file (gen_traj_tpl.py)
    public sealed class TjGlyph { public int Left, Top, W, H; public byte[] A; }

    public sealed class TjStr
    {
        public double Size, Pad, Ox, Oy, Bx0, By0, Bx1, By1;
        public string S;
        public char[] Ch; public double[] Dx, Dy;
    }

    public sealed class TjTemplate
    {
        public double Scale, Dpi, FigH;
        public int W, H, Nph;
        public Dictionary<int, byte[]> Panel = new Dictionary<int, byte[]>();     // RGB, by PKey(n, drag strip top)
        public Dictionary<int, double[]> PanelTicks = new Dictionary<int, double[]>();   // alpha (lo, hi)
        public Dictionary<int, double[]> PanelDTicks = new Dictionary<int, double[]>();  // drag (lo, hi)
        public static int PKey(int n, int dHi) { return n * 10000 + dHi; }
        public Dictionary<string, double[]> C = new Dictionary<string, double[]>();
        public List<double> Sizes = new List<double>();
        public Dictionary<double, Dictionary<char, TjGlyph[]>> Glyphs = new Dictionary<double, Dictionary<char, TjGlyph[]>>();
        public Dictionary<string, TjStr> Strs = new Dictionary<string, TjStr>();
        public List<TjStr> StrList = new List<TjStr>();

        public double K(string name) { return C[name][0]; }
        public double[] KA(string name) { return C[name]; }

        static readonly object cacheLock = new object();
        static string cachePath; static DateTime cacheTime; static TjTemplate cached;

        /// The template at path, parsed once per file version (thread-safe).
        public static TjTemplate LoadCached(string path)
        {
            DateTime t = File.GetLastWriteTimeUtc(path);
            lock (cacheLock)
            {
                if (cached != null && cachePath == path && cacheTime == t) return cached;
            }
            var tp = Load(path);
            lock (cacheLock) { cached = tp; cachePath = path; cacheTime = t; }
            return tp;
        }

        public static TjTemplate Load(string path)
        {
            var t = new TjTemplate();
            using (var br = new BinaryReader(new MemoryStream(File.ReadAllBytes(path))))
            {
                string magic = Encoding.ASCII.GetString(br.ReadBytes(8));
                if (magic != "TJTPL002") throw new InvalidDataException("not a TJTPL002 template: " + path);
                t.Scale = br.ReadDouble(); t.Dpi = br.ReadDouble(); t.FigH = br.ReadDouble();
                t.W = br.ReadInt32(); t.H = br.ReadInt32();
                int np = br.ReadInt32();
                for (int p = 0; p < np; p++)
                {
                    int n = br.ReadInt32(); int lo = br.ReadInt32(), hi = br.ReadInt32();
                    int dlo = br.ReadInt32(), dhi = br.ReadInt32(); int runs = br.ReadInt32();
                    var rgb = new byte[t.W * t.H * 3];
                    int o = 0;
                    for (int r = 0; r < runs; r++)
                    {
                        int c = br.ReadInt32(); byte R = br.ReadByte(), G = br.ReadByte(), B = br.ReadByte();
                        for (int k = 0; k < c; k++) { rgb[o++] = R; rgb[o++] = G; rgb[o++] = B; }
                    }
                    if (o != rgb.Length) throw new InvalidDataException("template panel " + n + ": " + o + " bytes");
                    int key = PKey(n, dhi);
                    t.Panel[key] = rgb; t.PanelTicks[key] = new double[] { lo, hi }; t.PanelDTicks[key] = new double[] { dlo, dhi };
                }
                int ns = br.ReadInt32(); t.Nph = br.ReadInt32();
                for (int s = 0; s < ns; s++)
                {
                    double size = br.ReadDouble(); int ng = br.ReadInt32();
                    var d = new Dictionary<char, TjGlyph[]>();
                    for (int gI = 0; gI < ng; gI++)
                    {
                        char ch = (char)br.ReadInt32(); br.ReadInt32();
                        var ph = new TjGlyph[t.Nph * t.Nph];
                        for (int k = 0; k < t.Nph * t.Nph; k++)
                        {
                            int px = br.ReadInt32(), py = br.ReadInt32();
                            var g = new TjGlyph { Left = br.ReadInt32(), Top = br.ReadInt32(), W = br.ReadInt32(), H = br.ReadInt32() };
                            g.A = br.ReadBytes(g.W * g.H);
                            ph[py * t.Nph + px] = g;
                        }
                        d[ch] = ph;
                    }
                    t.Sizes.Add(size); t.Glyphs[size] = d;
                }
                int nc = br.ReadInt32();
                for (int k = 0; k < nc; k++)
                {
                    int ln = br.ReadInt32(), nv = br.ReadInt32();
                    string name = Encoding.ASCII.GetString(br.ReadBytes(ln));
                    var v = new double[nv];
                    for (int j = 0; j < nv; j++) v[j] = br.ReadDouble();
                    t.C[name] = v;
                }
                int nstr = br.ReadInt32();
                for (int k = 0; k < nstr; k++)
                {
                    var s = new TjStr();
                    s.Size = br.ReadDouble(); s.Pad = br.ReadDouble();
                    s.S = Encoding.ASCII.GetString(br.ReadBytes(br.ReadInt32()));
                    s.Ox = br.ReadDouble(); s.Oy = br.ReadDouble();
                    int ng = br.ReadInt32();
                    s.Ch = new char[ng]; s.Dx = new double[ng]; s.Dy = new double[ng];
                    for (int j = 0; j < ng; j++) { s.Ch[j] = (char)br.ReadInt32(); s.Dx[j] = br.ReadDouble(); s.Dy[j] = br.ReadDouble(); }
                    s.Bx0 = br.ReadDouble(); s.By0 = br.ReadDouble(); s.Bx1 = br.ReadDouble(); s.By1 = br.ReadDouble();
                    t.Strs[Key(s.Size, s.Pad, s.S)] = s; t.StrList.Add(s);
                }
            }
            return t;
        }

        public static string Key(double size, double pad, string s)
        {
            return size.ToString("R", CultureInfo.InvariantCulture) + "|" + pad.ToString("R", CultureInfo.InvariantCulture) + "|" + s;
        }

        /// The layout of s at (size, pad): measured, else that of a measured string of the same length (the font is
        /// monospaced: the same advances and box), with s's glyphs; null when there is none.
        public TjStr Str(double size, double pad, string s)
        {
            TjStr r;
            if (Strs.TryGetValue(Key(size, pad, s), out r)) return r;
            foreach (var c in StrList)
                if (c.Size == size && c.Pad == pad && c.S.Length == s.Length)
                {
                    var g = Glyphs[size];
                    foreach (char ch in s) if (!g.ContainsKey(ch)) return null;
                    return new TjStr { Size = size, Pad = pad, S = s, Ox = c.Ox, Oy = c.Oy, Ch = s.ToCharArray(), Dx = c.Dx, Dy = c.Dy,
                                       Bx0 = c.Bx0, By0 = c.By0, Bx1 = c.Bx1, By1 = c.By1 };
                }
            return null;
        }
    }

    // ---------------------------------------------------------------- the raster: Agg's coverage and blender
    public sealed class TjRaster
    {
        public readonly int W, H;
        public readonly byte[] Rgb;
        const int SS = 16;                       // samples per pixel side (256: Agg's 8-bit coverage)
        const int WPP = SS * SS / 64;
        readonly ulong[] mask;
        readonly List<int> touched = new List<int>();
        readonly bool[] isTouched;
        int cx0, cy0, cx1, cy1;                  // clip box, pixels [cx0, cx1) x [cy0, cy1)

        public TjRaster(byte[] rgb, int w, int h)
        {
            W = w; H = h; Rgb = rgb;
            mask = new ulong[w * h * WPP];
            isTouched = new bool[w * h];
            NoClip();
        }

        public void NoClip() { cx0 = 0; cy0 = 0; cx1 = W; cy1 = H; }
        public void Clip(int x0, int y0, int x1, int y1)
        {
            cx0 = Math.Max(x0, 0); cy0 = Math.Max(y0, 0); cx1 = Math.Min(x1, W); cy1 = Math.Min(y1, H);
        }

        /// Agg fixed_blender_rgba_plain::blend_pix on an opaque pixel, alpha = multiply(255, cover) = cover.
        public void Blend(int x, int y, byte r, byte g, byte b, int cover)
        {
            if (cover <= 0) return;
            int i = (y * W + x) * 3;
            if (cover >= 255) { Rgb[i] = r; Rgb[i + 1] = g; Rgb[i + 2] = b; return; }
            long alpha = cover;
            long a = alpha + 65280;                 // ((alpha + 255) << 8) - alpha * 255
            Rgb[i] = Bl(Rgb[i], r, alpha, a);
            Rgb[i + 1] = Bl(Rgb[i + 1], g, alpha, a);
            Rgb[i + 2] = Bl(Rgb[i + 2], b, alpha, a);
        }

        static byte Bl(byte p, byte c, long alpha, long a)
        {
            long pr = (long)p * 255;
            return (byte)(((((long)c << 8) - pr) * alpha + (pr << 8)) / a);
        }

        // ---- one path = the union of its primitives (Agg's nonzero fill of one stroked path)
        void Touch(int pix) { if (!isTouched[pix]) { isTouched[pix] = true; touched.Add(pix); } }

        /// A stroked segment a->b, half width hw, extended by e0 before a and e1 past b (projecting caps).
        public void Seg(double ax, double ay, double bx, double by, double hw, double e0, double e1)
        {
            double dx = bx - ax, dy = by - ay, L = Math.Sqrt(dx * dx + dy * dy);
            if (L <= 1e-12) return;
            double ux = dx / L, uy = dy / L;
            double s0 = -e0, s1 = L + e1;
            // the rectangle's corners
            double[] qx = { ax + ux * s0 - uy * hw, ax + ux * s1 - uy * hw, ax + ux * s1 + uy * hw, ax + ux * s0 + uy * hw };
            double[] qy = { ay + uy * s0 + ux * hw, ay + uy * s1 + ux * hw, ay + uy * s1 - ux * hw, ay + uy * s0 - ux * hw };
            double ymin = Math.Min(Math.Min(qy[0], qy[1]), Math.Min(qy[2], qy[3]));
            double ymax = Math.Max(Math.Max(qy[0], qy[1]), Math.Max(qy[2], qy[3]));
            int py0 = Math.Max(cy0, (int)Math.Floor(ymin)), py1 = Math.Min(cy1 - 1, (int)Math.Floor(ymax));
            for (int py = py0; py <= py1; py++)
            {
                double xmin, xmax;
                if (!RowSpan(qx, qy, py, py + 1, out xmin, out xmax)) continue;
                int px0 = Math.Max(cx0, (int)Math.Floor(xmin)), px1 = Math.Min(cx1 - 1, (int)Math.Floor(xmax));
                for (int px = px0; px <= px1; px++)
                {
                    int pix = py * W + px; bool any = false;
                    for (int j = 0; j < SS; j++)
                    {
                        double sy = py + (j + 0.5) / SS - ay;
                        for (int i = 0; i < SS; i++)
                        {
                            double sx = px + (i + 0.5) / SS - ax;
                            double al = sx * ux + sy * uy;
                            if (al < s0 || al > s1) continue;
                            double pe = sx * uy - sy * ux;
                            if (pe > hw || pe < -hw) continue;
                            int bit = j * SS + i;
                            mask[pix * WPP + (bit >> 6)] |= 1UL << (bit & 63);
                            any = true;
                        }
                    }
                    if (any) Touch(pix);
                }
            }
        }

        static bool RowSpan(double[] qx, double[] qy, double y0, double y1, out double xmin, out double xmax)
        {
            // the convex quad clipped to the band y0 <= y <= y1: its x extent
            xmin = double.MaxValue; xmax = double.MinValue;
            for (int k = 0; k < 4; k++)
            {
                double ax = qx[k], ay = qy[k], bx = qx[(k + 1) & 3], by = qy[(k + 1) & 3];
                if (ay >= y0 && ay <= y1) { xmin = Math.Min(xmin, ax); xmax = Math.Max(xmax, ax); }
                double lo = Math.Min(ay, by), hi = Math.Max(ay, by);
                if (hi > lo)
                    foreach (double yy in new[] { y0, y1 })
                        if (yy >= lo && yy <= hi)
                        {
                            double x = ax + (bx - ax) * (yy - ay) / (by - ay);
                            xmin = Math.Min(xmin, x); xmax = Math.Max(xmax, x);
                        }
            }
            return xmax >= xmin;
        }

        /// A disc (a round join).
        public void Disc(double cx, double cy, double r)
        {
            int py0 = Math.Max(cy0, (int)Math.Floor(cy - r)), py1 = Math.Min(cy1 - 1, (int)Math.Floor(cy + r));
            int px0 = Math.Max(cx0, (int)Math.Floor(cx - r)), px1 = Math.Min(cx1 - 1, (int)Math.Floor(cx + r));
            double r2 = r * r;
            for (int py = py0; py <= py1; py++)
                for (int px = px0; px <= px1; px++)
                {
                    int pix = py * W + px; bool any = false;
                    for (int j = 0; j < SS; j++)
                    {
                        double sy = py + (j + 0.5) / SS - cy;
                        for (int i = 0; i < SS; i++)
                        {
                            double sx = px + (i + 0.5) / SS - cx;
                            if (sx * sx + sy * sy > r2) continue;
                            int bit = j * SS + i;
                            mask[pix * WPP + (bit >> 6)] |= 1UL << (bit & 63);
                            any = true;
                        }
                    }
                    if (any) Touch(pix);
                }
        }

        static int Pop(ulong v)
        {
            v = v - ((v >> 1) & 0x5555555555555555UL);
            v = (v & 0x3333333333333333UL) + ((v >> 2) & 0x3333333333333333UL);
            v = (v + (v >> 4)) & 0x0F0F0F0F0F0F0F0FUL;
            return (int)((v * 0x0101010101010101UL) >> 56);
        }

        /// Ends the path: blends its coverage in the color and clears the masks.
        public void Fill(byte r, byte g, byte b)
        {
            foreach (int pix in touched)
            {
                int cnt = 0;
                for (int k = 0; k < WPP; k++) { cnt += Pop(mask[pix * WPP + k]); mask[pix * WPP + k] = 0; }
                isTouched[pix] = false;
                int cover = cnt * 256 / (SS * SS);
                if (cover > 255) cover = 255;
                Blend(pix % W, pix / W, r, g, b, cover);
            }
            touched.Clear();
        }

        /// A polyline (pixel coordinates, y down) stroked as Agg strokes it: half width hw, round joins, caps
        /// projecting (cap = true) or butt.
        public void Polyline(List<double[]> p, double hw, bool cap)
        {
            int n = p.Count;
            if (n < 2) return;
            for (int k = 0; k + 1 < n; k++)
                Seg(p[k][0], p[k][1], p[k + 1][0], p[k + 1][1], hw, (cap && k == 0) ? hw : 0, (cap && k + 2 == n) ? hw : 0);
            for (int k = 1; k + 1 < n; k++) Disc(p[k][0], p[k][1], hw);
        }
    }

    // ---------------------------------------------------------------- the panels (gen_traj_bg.py)
    public sealed class TjPanelOut { public int N; public double Vhi, Vlo, X0, X1; public string Drawn, Name; public double[] Asc, Dsc; public byte[] Rgb; }

    public sealed class TjResult
    {
        public bool Ok; public string Why = "";
        public List<TjPanelOut> Panels = new List<TjPanelOut>();
        public string Sidecar;                   // the sidecar's text (python's '\n'.join(out) + '\n')
        public double Ms;
        public string Log = "";
    }

    public sealed class TrajBg
    {
        // gen_traj_bg.py's V_PAD_PX: the velocity boundaries padded by the orbiter bug's height plus a little, so the
        // bug is never off-screen at a panel switch. px at scale 1 the band sits inside the field's top and bottom, so the bug clears the page's offscale inset
        // at a panel switch. A constant, not a template key: the template (traj_tpl/) is unchanged.
        const double V_PAD_PX = 30.0;
        static double VPad(double vhi, double vlo, double ph, double pad) { return pad / (ph - 2.0 * pad) * (vhi - vlo); }
        readonly TjTemplate T;
        readonly double FIG_W, FIG_H, BASE_DPI, FS, SLO, SHI, A_STRIP_X, D_STRIP_X, A_LAB_OFF, TL_RIGHT, BR_RIGHT, CLOCK_RIGHT, CLOCK_TOP,
            PHASE_34_V, PREENTRY_GUARD, AOA_HIGH, AOA_LOW, AOA_HIGH_SPEED, AOA_LOW_SPEED, FAMILY_VERSION;
        readonly int LINE_STEPS, N_DRAG_LINES;
        readonly double[] FIELD, PANEL_FRACS, ZOOM_X1, ZOOM_X0, TL_Y, BR_Y, DEFAULT_ASCALE;
        readonly byte[] BGc, FGc;

        public TrajBg(TjTemplate t)
        {
            T = t;
            FIG_W = t.K("FIG_W"); FIG_H = t.K("FIG_H"); BASE_DPI = t.K("BASE_DPI"); FS = t.K("FS"); SLO = t.K("SLO"); SHI = t.K("SHI");
            A_STRIP_X = t.K("A_STRIP_X"); D_STRIP_X = t.K("D_STRIP_X"); A_LAB_OFF = t.K("A_LAB_OFF"); TL_RIGHT = t.K("TL_RIGHT");
            BR_RIGHT = t.K("BR_RIGHT"); CLOCK_RIGHT = t.K("CLOCK_RIGHT"); CLOCK_TOP = t.K("CLOCK_TOP"); PHASE_34_V = t.K("PHASE_34_V");
            PREENTRY_GUARD = t.K("PREENTRY_GUARD"); AOA_HIGH = t.K("AOA_HIGH"); AOA_LOW = t.K("AOA_LOW");
            AOA_HIGH_SPEED = t.K("AOA_HIGH_SPEED"); AOA_LOW_SPEED = t.K("AOA_LOW_SPEED"); FAMILY_VERSION = t.K("FAMILY_VERSION");
            LINE_STEPS = (int)t.K("LINE_STEPS"); N_DRAG_LINES = (int)t.K("N_DRAG_LINES");
            FIELD = t.KA("FIELD"); PANEL_FRACS = t.KA("PANEL_FRACS"); ZOOM_X1 = t.KA("ZOOM_X1"); ZOOM_X0 = t.KA("ZOOM_X0");
            TL_Y = t.KA("TL_Y"); BR_Y = t.KA("BR_Y"); DEFAULT_ASCALE = t.KA("DEFAULT_ASCALE");
            var bg = t.KA("BG"); var fg = t.KA("FG");
            BGc = new[] { (byte)bg[0], (byte)bg[1], (byte)bg[2] }; FGc = new[] { (byte)fg[0], (byte)fg[1], (byte)fg[2] };
            // the displays' common style (font / stroke: the bank and drag curves 2.4 px, the frame and strips 3.1 px):
            // gen_traj_bg's strokes, dash and line-label size from the template; an older template has none of them and
            // gets the old look whole
            bool styled = t.C.ContainsKey("CURVE_LW");
            LW = styled ? t.K("LW") : 1.5;
            CURVE_LW = styled ? t.K("CURVE_LW") : 0.9;
            DRAG_LW = styled ? CURVE_LW : 0.7;
            DASH = styled ? t.KA("DASH") : new[] { 4.0, 4.0 };
            LINE_FS = styled ? t.K("LINE_FS") : 10.0;
            LIM_LW = styled ? CURVE_LW : 1.5;
        }
        readonly double LW, CURVE_LW, DRAG_LW, LIM_LW, LINE_FS;   // the notch, the bank lines, the drag lines, the two limit lines
        readonly double[] DASH;                                   //   (pt); the line labels' base size; the drag dash (x lw)

        double Fsz(double b) { return b * FS; }
        // every label one size (gen_traj_bg.py TXT_FS); the line labels at LINE_FS (TAEM's 7.5), from the template

        // the indices 0..n-1 from k0 outward (gen_traj_bg.outward)
        static List<int> Outward(int k0, int n)
        {
            var o = new List<int> { k0 };
            for (int d = 1; d < n; d++) { if (k0 + d < n) o.Add(k0 + d); if (k0 - d >= 0) o.Add(k0 - d); }
            return o;
        }

        // ---- the family math, as in python
        public double AoaSchedule(double v)
        {
            if (v >= AOA_HIGH_SPEED) return AOA_HIGH;
            double frac = Math.Min(Math.Max((v - AOA_LOW_SPEED) / (AOA_HIGH_SPEED - AOA_LOW_SPEED), 0.0), 1.0);
            return AOA_LOW + (AOA_HIGH - AOA_LOW) * frac;
        }

        static double PyMax(double a, double b) { return b > a ? b : a; }   // python max(a, b): a unless b > a
        static double PyMin(double a, double b) { return b < a ? b : a; }

        public List<double[]> PanelBands(double vInit, double vTaem)
        {
            double span = vInit - vTaem;
            double[] fr = PANEL_FRACS;
            if (span > 0)
            {
                double target = (vInit - PHASE_34_V) / span;
                double old34 = PANEL_FRACS[3];
                if (0.0 < target && target < 1.0)
                {
                    fr = new double[PANEL_FRACS.Length];
                    for (int k = 0; k < fr.Length; k++)
                    {
                        double f = PANEL_FRACS[k];
                        fr[k] = f <= old34 ? f * target / old34 : target + (f - old34) * (1.0 - target) / (1.0 - old34);
                    }
                }
            }
            var o = new List<double[]>();
            for (int n = 0; n < 5; n++) o.Add(new[] { vInit - fr[n] * span, vInit - fr[n + 1] * span });
            return o;
        }

        public static double RowAt(List<double[]> rows, double v, int col)
        {
            if (v >= rows[0][0]) return rows[0][col];
            if (v <= rows[rows.Count - 1][0]) return rows[rows.Count - 1][col];
            for (int i = 1; i < rows.Count; i++)
                if (rows[i][0] <= v)
                {
                    double[] a = rows[i - 1], b = rows[i];
                    double f = (a[0] - v) / PyMax(a[0] - b[0], 1e-9);
                    return a[col] + (b[col] - a[col]) * f;
                }
            return rows[rows.Count - 1][col];
        }

        public sealed class Line { public double Bank; public List<double[]> Pts = new List<double[]>(); }   // (v, range m)

        public List<Line> FamilyLines(List<TjMember> fam, double vlo)
        {
            var o = new List<Line>();
            foreach (var m in fam)
            {
                double top = double.NaN, mn = double.NaN;
                foreach (var r in m.Rows) { top = double.IsNaN(top) ? r[0] : PyMax(top, r[0]); mn = double.IsNaN(mn) ? r[0] : PyMin(mn, r[0]); }
                double lo = PyMax(vlo, mn);
                var L = new Line { Bank = m.Bank };
                for (int i = 0; i <= LINE_STEPS; i++)
                {
                    double v = top + (lo - top) * i / LINE_STEPS;
                    L.Pts.Add(new[] { v, RowAt(m.Rows, v, 3) });
                }
                o.Add(L);
            }
            return o;
        }

        public List<double> DragLadder(List<TjMember> fam, double vhi, double vlo)
        {
            double vmid = 0.5 * (vhi + vlo);
            double lo = double.NaN, hi = double.NaN;
            foreach (var m in fam)
            {
                double val = RowAt(m.Rows, vmid, 1) * 3.28084;
                lo = double.IsNaN(lo) ? val : PyMin(lo, val); hi = double.IsNaN(hi) ? val : PyMax(hi, val);
            }
            lo = lo * 1.12; hi = hi * 0.94;
            var o = new List<double>();
            if (hi <= lo) return o;
            for (int k = 0; k < N_DRAG_LINES; k++) o.Add(lo * Math.Pow(hi / lo, (double)k / (N_DRAG_LINES - 1)));
            return o;
        }

        public List<KeyValuePair<double, List<double[]>>> DragLoci(List<TjMember> fam, List<double> dragsFt, double vlo, double vhi)
        {
            const double step = 20.0;
            var o = new List<KeyValuePair<double, List<double[]>>>();
            foreach (double dtFt in dragsFt)
            {
                double dt = dtFt / 3.28084;
                var pts = new List<double[]>();
                double v = vhi;
                while (v > vlo)
                {
                    var col = new List<double[]>();
                    foreach (var m in fam) col.Add(new[] { RowAt(m.Rows, v, 1), RowAt(m.Rows, v, 3) });
                    double dmin = col[0][0], dmax = col[0][0];
                    foreach (var c in col) { dmin = PyMin(dmin, c[0]); dmax = PyMax(dmax, c[0]); }
                    if (dmin + 1e-3 < dt && dt < dmax - 1e-3)
                    {
                        bool has = false; double hit = 0;
                        for (int i = 1; i < col.Count; i++)
                        {
                            double d0 = col[i - 1][0], r0 = col[i - 1][1], d1 = col[i][0], r1 = col[i][1];
                            if ((d0 - dt) * (d1 - dt) <= 0 && Math.Abs(d1 - d0) > 1e-6) { hit = r0 + (dt - d0) / (d1 - d0) * (r1 - r0); has = true; }
                        }
                        if (has) pts.Add(new[] { v, hit });
                    }
                    v -= step;
                }
                if (pts.Count >= 3)
                {
                    int at = o.FindIndex(kv => kv.Key == dtFt);         // a python dict: a repeated key keeps its place
                    if (at >= 0) o[at] = new KeyValuePair<double, List<double[]>>(dtFt, pts);
                    else o.Add(new KeyValuePair<double, List<double[]>>(dtFt, pts));
                }
            }
            return o;
        }

        // ---- LabelSpace
        sealed class LabelSpace
        {
            public double X0, X1, Y0, Y1, WPt, HPt;
            public List<double[]> Boxes = new List<double[]>();
            public List<List<double[]>> Polys = new List<List<double[]>>();

            public void Frac(double x, double y, out double xf, out double yf) { xf = (x - X0) / (X1 - X0); yf = (y - Y0) / (Y1 - Y0); }
            public void TextSize(string txt, double fs, out double w, out double h) { w = (txt.Length + 1.2) * fs * 0.62 / WPt; h = fs * 1.55 / HPt; }
            public void ReserveBox(double xf, double yf, double w, double h) { Boxes.Add(new[] { xf - w / 2, yf - h / 2, xf + w / 2, yf + h / 2 }); }
            public void ReserveRect(double a, double b, double c, double d) { Boxes.Add(new[] { a, b, c, d }); }
            public void ReservePoly(List<double[]> pts)
            {
                var p = new List<double[]>();
                foreach (var q in pts) { double xf, yf; Frac(q[0], q[1], out xf, out yf); p.Add(new[] { xf, yf }); }
                Polys.Add(p);
            }
            bool HitsBox(double[] b)
            {
                foreach (var o in Boxes) if (!(b[2] < o[0] || b[0] > o[2] || b[3] < o[1] || b[1] > o[3])) return true;
                return false;
            }
            bool HitsPoly(double[] b)
            {
                foreach (var poly in Polys)
                    for (int i = 1; i < poly.Count; i++)
                    {
                        double ax = poly[i - 1][0], ay = poly[i - 1][1], bx = poly[i][0], by = poly[i][1];
                        if ((b[0] <= ax && ax <= b[2] && b[1] <= ay && ay <= b[3]) || (b[0] <= bx && bx <= b[2] && b[1] <= by && by <= b[3])) return true;
                        if (Math.Min(ax, bx) <= b[2] && Math.Max(ax, bx) >= b[0] && Math.Min(ay, by) <= b[3] && Math.Max(ay, by) >= b[1])
                        {
                            double mx = 0.5 * (ax + bx), my = 0.5 * (ay + by);
                            if (b[0] <= mx && mx <= b[2] && b[1] <= my && my <= b[3]) return true;
                        }
                    }
                return false;
            }
            public double[] Place(string txt, List<double[]> cands, double fs)
            {
                double w, h; TextSize(txt, fs, out w, out h);
                double[] fb = null;
                foreach (var c in cands)
                {
                    double xf, yf; Frac(c[0], c[1], out xf, out yf);
                    xf += c[2] / WPt; yf += c[3] / HPt;
                    if (!(0.0 <= xf && xf <= 1.0 && 0.0 <= yf && yf <= 1.0)) continue;
                    var box = new[] { xf - w / 2, yf - h / 2, xf + w / 2, yf + h / 2 };
                    if (HitsBox(box)) continue;
                    if (HitsPoly(box)) { if (fb == null) fb = new[] { c[0], c[1], c[2], c[3], xf, yf }; continue; }
                    ReserveBox(xf, yf, w, h);
                    return c;
                }
                if (fb != null) { ReserveBox(fb[4], fb[5], w, h); return new[] { fb[0], fb[1], fb[2], fb[3] }; }
                return cands[0];
            }
        }

        // ---- the drawing context of one panel: data -> display (y up) -> image (y down, height = the canvas's int H)
        sealed class Ctx
        {
            public double Dpi, Bx0, By0, Bw, Bh, X0, X1, Y0, Y1; public int H;
            public double DX(double x) { return Bx0 + (x - X0) / (X1 - X0) * Bw; }
            public double DY(double y) { return By0 + (y - Y0) / (Y1 - Y0) * Bh; }
        }

        // the canvas-clip (Agg PathClipper: the canvas + 1 px), sub-paths split where the path leaves it
        static List<List<double[]>> ClipToCanvas(List<double[]> p, int W, int H)
        {
            double xmin = -1.0, ymin = -1.0, xmax = W + 1.0, ymax = H + 1.0;
            var outp = new List<List<double[]>>();
            List<double[]> cur = null;
            for (int k = 0; k + 1 < p.Count; k++)
            {
                double x0 = p[k][0], y0 = p[k][1], x1 = p[k + 1][0], y1 = p[k + 1][1];
                double t0 = 0, t1 = 1, dx = x1 - x0, dy = y1 - y0;
                bool vis = Lb(-dx, x0 - xmin, ref t0, ref t1) && Lb(dx, xmax - x0, ref t0, ref t1) &&
                           Lb(-dy, y0 - ymin, ref t0, ref t1) && Lb(dy, ymax - y0, ref t0, ref t1);
                if (!vis) { cur = null; continue; }
                var a = new[] { x0 + t0 * dx, y0 + t0 * dy };
                var b = new[] { x0 + t1 * dx, y0 + t1 * dy };
                if (cur == null || t0 > 0) { cur = new List<double[]> { a }; outp.Add(cur); }
                cur.Add(b);
                if (t1 < 1) cur = null;
            }
            return outp;
        }

        static bool Lb(double pp, double q, ref double t0, ref double t1)
        {
            if (pp == 0) return q >= 0;
            double r = q / pp;
            if (pp < 0) { if (r > t1) return false; if (r > t0) t0 = r; }
            else { if (r < t0) return false; if (r < t1) t1 = r; }
            return true;
        }

        // Agg's dash generator over one sub-path: (on, off) from the start, a new dash = a new sub-path
        static List<List<double[]>> Dash(List<double[]> p, double on, double off)
        {
            var outp = new List<List<double[]>>();
            double[] pat = { on, off };
            int di = 0; double rest = pat[0];
            List<double[]> cur = new List<double[]> { p[0] };
            for (int k = 0; k + 1 < p.Count; k++)
            {
                double x0 = p[k][0], y0 = p[k][1], x1 = p[k + 1][0], y1 = p[k + 1][1];
                double L = Math.Sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)), s = 0;
                if (L <= 1e-14) continue;
                while (L - s > rest)
                {
                    s += rest;
                    var q = new[] { x0 + (x1 - x0) * s / L, y0 + (y1 - y0) * s / L };
                    if (di == 0) { cur.Add(q); outp.Add(cur); cur = null; }
                    else cur = new List<double[]> { q };
                    di ^= 1; rest = pat[di];
                }
                rest -= L - s;
                if (di == 0) cur.Add(p[k + 1]);
            }
            if (di == 0 && cur != null && cur.Count >= 2) outp.Add(cur);
            return outp;
        }

        void StrokeData(TjRaster ras, Ctx c, List<double[]> xy, double lwPt, bool dashed, bool butt)
        {
            var pix = new List<double[]>();
            foreach (var q in xy) pix.Add(new[] { c.DX(q[0]), c.H - c.DY(q[1]) });
            double lw = lwPt * c.Dpi / 72.0, hw = lw / 2;
            foreach (var sp in ClipToCanvas(pix, ras.W, c.H))
            {
                if (dashed)
                {
                    double on = DASH[0] * lwPt * c.Dpi / 72.0, off = DASH[1] * lwPt * c.Dpi / 72.0;   // matplotlib's dash x lw
                    foreach (var piece in Dash(sp, on, off)) ras.Polyline(piece, hw, false);
                }
                else ras.Polyline(sp, hw, !butt);
            }
            ras.Fill(FGc[0], FGc[1], FGc[2]);
        }

        // matplotlib Axes.contains_point(xy) for an annotation's xy: the field box, + 0.5 px (radius 1.0)
        bool InField(Ctx c, double x, double y)
        {
            double dx = c.DX(x), dy = c.DY(y);
            return dx >= c.Bx0 - 0.5 && dx <= c.Bx0 + c.Bw + 0.5 && dy >= c.By0 - 0.5 && dy <= c.By0 + c.Bh + 0.5;
        }

        public string MissingLabels = "";
        public StringBuilder LabelLog = new StringBuilder();    // "n:text " per label drawn (the checks)
        int curPanel;

        void Label(TjRaster ras, Ctx c, string s, double x, double y, double dxPt, double dyPt, double size, double pad)
        {
            if (!InField(c, x, y)) return;                     // annotation_clip: xycoords 'data' outside the axes
            LabelLog.Append(curPanel).Append(':').Append(s).Append(' ');
            var L = T.Str(size, pad, s);
            if (L == null) { MissingLabels += (MissingLabels.Length > 0 ? " " : "") + s; return; }
            double axd = c.DX(x) + dxPt * (c.Dpi / 72.0), ayd = c.DY(y) + dyPt * (c.Dpi / 72.0);
            // the background box: a rectilinear path, so Agg snaps its corners to pixel boundaries
            ras.NoClip();
            int bx0 = (int)Math.Floor(axd + L.Bx0 + 0.5), bx1 = (int)Math.Floor(axd + L.Bx1 + 0.5);
            int by0 = (int)Math.Floor(c.H - (ayd + L.By1) + 0.5), by1 = (int)Math.Floor(c.H - (ayd + L.By0) + 0.5);
            for (int py = Math.Max(0, by0); py < Math.Min(ras.H, by1); py++)
                for (int px = Math.Max(0, bx0); px < Math.Min(ras.W, bx1); px++) ras.Blend(px, py, BGc[0], BGc[1], BGc[2], 255);
            // the glyphs, each at its 1/64 px position, from the atlas phase nearest to it
            double tx = axd + L.Ox, ty = ayd + L.Oy;
            var gl = T.Glyphs[size];
            int step = 64 / T.Nph;
            for (int k = 0; k < L.Ch.Length; k++)
            {
                long TX = TjPy.Round(64 * (tx + L.Dx[k])), TY = TjPy.Round(64 * (ty + L.Dy[k]));
                long qx = (long)Math.Round((double)TX / step, MidpointRounding.ToEven) * step;
                long qy = (long)Math.Round((double)TY / step, MidpointRounding.ToEven) * step;
                long kx = FloorDiv(qx, 64), ky = FloorDiv(qy, 64);
                int phx = (int)((qx - kx * 64) / step), phy = (int)((qy - ky * 64) / step);
                TjGlyph g = gl[L.Ch[k]][phy * T.Nph + phx];
                int left = g.Left + (int)kx, top = g.Top + (int)ky;
                int row0 = c.H - top;
                for (int j = 0; j < g.H; j++)
                {
                    int py = row0 + j; if (py < 0 || py >= ras.H) continue;
                    for (int i = 0; i < g.W; i++)
                    {
                        int px = left + i; if (px < 0 || px >= ras.W) continue;
                        ras.Blend(px, py, FGc[0], FGc[1], FGc[2], g.A[j * g.W + i]);
                    }
                }
            }
        }

        static long FloorDiv(long a, long b) { long q = a / b; if ((a % b != 0) && ((a < 0) != (b < 0))) q--; return q; }

        static string BankText(double bank) { return ((long)bank).ToString(CultureInfo.InvariantCulture); }   // '%d' % float

        /// draw_panel: the panel's RGB; x0, x1 (km) out.
        public byte[] DrawPanel(List<TjMember> fam, List<Line> lines, double vhi, double vlo, int panel, double dpi, double arrestV, bool hasArrest,
                                int dmax, double vpad, out double x0, out double x1, out double[] asc, out double[] dsc)
        {
            byte[] tpl;
            int key = TjTemplate.PKey(panel, dmax);
            if (!T.Panel.TryGetValue(key, out tpl)) throw new InvalidDataException("the template has no panel " + panel + " with the drag strip to " + dmax);
            var rgb = (byte[])tpl.Clone();
            curPanel = panel;
            asc = T.PanelTicks[key]; dsc = T.PanelDTicks[key];
            var ras = new TjRaster(rgb, T.W, T.H);
            double PW = FIG_W * dpi, PH = FIG_H * dpi;

            double vMin = double.NaN, vMax = double.NaN;
            foreach (var L in lines) foreach (var q in L.Pts) { vMin = double.IsNaN(vMin) ? q[0] : PyMin(vMin, q[0]); vMax = double.IsNaN(vMax) ? q[0] : PyMax(vMax, q[0]); }
            Func<double, double[]> span = v =>
            {
                v = PyMin(PyMax(v, vMin), vMax);
                var rs = new List<double>();
                foreach (var L in lines)
                {
                    var near = new List<double>();
                    foreach (var q in L.Pts) if (Math.Abs(q[0] - v) < 45) near.Add(q[1]);
                    if (near.Count > 0) rs.Add(TjPy.Sum(near) / near.Count);
                }
                if (rs.Count == 0)
                    foreach (var L in lines)
                    {
                        double[] best = null; double bd = 0;
                        foreach (var q in L.Pts) { double d = Math.Abs(q[0] - v); if (best == null || d < bd) { best = q; bd = d; } }
                        rs.Add(best[1]);
                    }
                double mn = rs[0], mx = rs[0];
                foreach (double r in rs) { mn = PyMin(mn, r); mx = PyMax(mx, r); }
                return new[] { mn, mx };
            };
            // so the bug follows its line to the handover instead of drifting across the lines: the last panel's left edge at the field's bottom (vlo - vpad), not
            // moved in (gen_traj_bg.py draw_panel's)
            bool last = panel == 5;
            x0 = PyMax(0.0, span(last ? vlo - vpad : vlo)[0] / 1000.0 * 0.88);
            x1 = span(vhi)[1] / 1000.0 * 1.04;
            double w = x1 - x0;
            x1 = x0 + w * ZOOM_X1[panel - 1];
            x0 = PyMax(0.0, x0 - w * ZOOM_X0[panel - 1]);
            foreach (double keep in new[] { 0.70, 0.95, 0.95 }) x1 = x0 + (x1 - x0) * keep;
            if (!last) x0 = x0 + (x1 - x0) * 0.05;
            double ylo = vlo - vpad, yhi = vhi + vpad;   // the band inset by the pad
            double xl0 = x0, xl1 = x1, yl0 = ylo, yl1 = yhi;

            var c = new Ctx { Dpi = dpi, H = T.H, Bx0 = FIELD[0] * PW, By0 = FIELD[1] * PH, Bw = FIELD[2] * PW, Bh = FIELD[3] * PH, X0 = x0, X1 = x1, Y0 = ylo, Y1 = yhi };
            // the field's clip box, rounded as Agg's set_clipbox rounds it
            int clx0 = (int)Math.Floor(c.Bx0 + 0.5), clx1 = (int)Math.Floor(c.Bx0 + c.Bw + 0.5);
            int cly0 = (int)Math.Floor(T.H - (c.By0 + c.Bh) + 0.5), cly1 = (int)Math.Floor(T.H - c.By0 + 0.5);

            var ls = new LabelSpace { X0 = x0, X1 = x1, Y0 = ylo, Y1 = yhi, WPt = FIELD[2] * FIG_W * 72.0, HPt = FIELD[3] * FIG_H * 72.0 };
            ls.ReserveRect(-0.05, 0.80, 0.30, 1.05);
            ls.ReserveRect(0.70, -0.05, 1.05, 0.46);
            foreach (var L in lines)
            {
                var seg = new List<double[]>();
                foreach (var q in L.Pts) if (ylo <= q[0] && q[0] <= yhi) seg.Add(new[] { q[1] / 1000.0, q[0] });
                if (seg.Count >= 2) ls.ReservePoly(seg);
            }

            // zorder 3: the dashed drag lines; zorder 4: their labels (placed in the same pass, drawn after every line)
            var dragLabels = new List<object[]>();
            foreach (var kv in DragLoci(fam, DragLadder(fam, vhi, vlo), ylo, yhi))
            {
                double dv = kv.Key;
                var seg = new List<double[]>();
                foreach (var q in kv.Value) if (ylo <= q[0] && q[0] <= yhi) seg.Add(q);
                if (seg.Count < 3) continue;
                var xy = new List<double[]>();
                foreach (var q in seg) xy.Add(new[] { q[1] / 1000, q[0] });
                ras.Clip(clx0, cly0, clx1, cly1);
                StrokeData(ras, c, xy, DRAG_LW, true, true);
                var ordered = new List<double[]>(seg);
                StableSortDesc(ordered);
                var cands = new List<double[]>();
                foreach (double frac in new[] { 0.0, 0.06, 0.13, 0.22, 0.32, 0.45, 0.60, 0.78 })
                {
                    int k = Math.Min(ordered.Count - 1, (int)(frac * ordered.Count));
                    double lx = ordered[k][1] / 1000.0, ly = ordered[k][0];
                    foreach (var d in new[] { new[] { 14.0, 9 }, new[] { 14.0, 20 }, new[] { -14.0, 9 }, new[] { 14.0, -10 }, new[] { -14.0, -10 } })
                        cands.Add(new[] { lx, ly, d[0], d[1] });
                }
                string txt = TjPy.F(dv, 0) + "D";
                var pl = ls.Place(txt, cands, Fsz(LINE_FS));
                dragLabels.Add(new object[] { txt, pl });
            }
            foreach (var dl in dragLabels)
            {
                var pl = (double[])dl[1];
                Label(ras, c, (string)dl[0], pl[0], pl[1], pl[2], pl[3], Fsz(LINE_FS), 0.6);
            }

            // zorder 5: the bank lines; zorder 6 (in insertion order): their labels, the max-bank line's two and its notch
            var z6 = new List<Action>();
            for (int i = 0; i < lines.Count; i++)
            {
                var L = lines[i];
                double bank = L.Bank;
                var seg = new List<double[]>();
                foreach (var q in L.Pts) if (ylo <= q[0] && q[0] <= yhi) seg.Add(q);
                if (seg.Count < 3) continue;
                bool lim = i == 0 || i == lines.Count - 1;
                var xy = new List<double[]>();
                foreach (var q in seg) xy.Add(new[] { q[1] / 1000, q[0] });
                ras.Clip(clx0, cly0, clx1, cly1);
                StrokeData(ras, c, xy, lim ? LIM_LW : CURVE_LW, false, false);
                if (i == lines.Count - 1 && hasArrest)
                {
                    var bankSeg = new List<double[]>(); var glimSeg = new List<double[]>();
                    foreach (var q in seg) { if (q[0] >= arrestV) bankSeg.Add(q); if (q[0] < arrestV) glimSeg.Add(q); }
                    foreach (var pr in new[] { new object[] { bankSeg, BankText(bank) }, new object[] { glimSeg, "G-LIM" } })
                    {
                        var sg = (List<double[]>)pr[0]; string txt = (string)pr[1];
                        if (sg.Count >= 3)
                        {
                            var mc = new List<double[]>();   // from the middle point outward
                            foreach (int k in Outward(sg.Count / 2, sg.Count)) mc.Add(new[] { sg[k][1] / 1000, sg[k][0], -19.0, -7.0 });
                            var at = ls.Place(txt, mc, Fsz(LINE_FS));
                            z6.Add(() => Label(ras, c, txt, at[0], at[1], at[2], at[3], Fsz(LINE_FS), 1.0));
                        }
                    }
                    if (bankSeg.Count > 0 && glimSeg.Count > 0)
                    {
                        double[] pa = bankSeg[0], pb = glimSeg[0];
                        foreach (var q in bankSeg) if (q[0] < pa[0]) pa = q;
                        foreach (var q in glimSeg) if (q[0] > pb[0]) pb = q;
                        double dxn = ((pa[1] - pb[1]) / 1000.0) / (xl1 - xl0);
                        double dyn = (pa[0] - pb[0]) / (yl1 - yl0);
                        double mag = Math.Sqrt(dxn * dxn + dyn * dyn);
                        if (mag > 1e-9)
                        {
                            const double half = 0.016;
                            double nx = -dyn / mag, ny = dxn / mag;
                            double cx = 0.5 * (pa[1] + pb[1]) / 1000.0, cy = 0.5 * (pa[0] + pb[0]);
                            var nxy = new List<double[]> {
                                new[] { cx - nx * half * (xl1 - xl0), cy - ny * half * (yl1 - yl0) },
                                new[] { cx + nx * half * (xl1 - xl0), cy + ny * half * (yl1 - yl0) } };
                            z6.Add(() => { ras.Clip(clx0, cly0, clx1, cly1); StrokeData(ras, c, nxy, LW, false, true); });
                        }
                    }
                    continue;
                }
                var vis = new List<double[]>();
                foreach (var q in seg) if (xl0 <= q[1] / 1000 && q[1] / 1000 <= xl1) vis.Add(q);
                if (vis.Count == 0) continue;
                double fr = (double)i / Math.Max(1, lines.Count - 1);
                double vtarget = vhi - (vhi - vlo) * (0.78 - 0.56 * fr);
                int pick = -1; double pd = 0;
                for (int k = 0; k < vis.Count; k++) { double d = Math.Abs(vis[k][0] - vtarget); if (pick < 0 || d < pd) { pick = k; pd = d; } }
                string bt = BankText(bank);
                var bc = new List<double[]>();   // that spot first, then the line's points outward, clear of the blocks
                foreach (int k in Outward(pick, vis.Count)) bc.Add(new[] { vis[k][1] / 1000, vis[k][0], 0.0, 0.0 });
                var pk = ls.Place(bt, bc, Fsz(LINE_FS));
                z6.Add(() => Label(ras, c, bt, pk[0], pk[1], 0, 0, Fsz(LINE_FS), 1.0));
            }
            foreach (var a in z6) a();
            // the bottom-right readouts' box (gen_traj_bg _draw_readouts): the template's pixels copied back over the lines
            if (T.C.ContainsKey("BR_BOX"))
            {
                int[] bx = BoxPx(dpi);
                int c0 = Math.Max(0, bx[0]), c1 = Math.Min(T.W, bx[2]);
                for (int r = Math.Max(0, T.H - bx[3]); r < Math.Min(T.H, T.H - bx[1]); r++)
                    if (c1 > c0) Buffer.BlockCopy(tpl, (r * T.W + c0) * 3, rgb, (r * T.W + c0) * 3, (c1 - c0) * 3);
            }
            return rgb;
        }

        /// gen_traj_bg._box_px: BR_BOX in whole pixels at dpi (x0, y0, x1, y1 display px from the bottom left; rows
        /// T.H - y1 .. T.H - y0 - 1 of the image)
        int[] BoxPx(double dpi)
        {
            var f = T.KA("BR_BOX");
            double pw = FIG_W * dpi, ph = FIG_H * dpi;
            var s = new[] { pw, ph, pw, ph };
            var o = new int[4];
            for (int k = 0; k < 4; k++) o[k] = (int)Math.Round(f[k] * s[k], MidpointRounding.ToEven);   // python round()
            return o;
        }

        static void StableSortDesc(List<double[]> l)
        {
            // python sorted(seg, key=lambda p: -p[0]): stable
            var idx = new List<KeyValuePair<int, double[]>>();
            for (int i = 0; i < l.Count; i++) idx.Add(new KeyValuePair<int, double[]>(i, l[i]));
            idx.Sort((a, b) => { int c = (-a.Value[0]).CompareTo(-b.Value[0]); return c != 0 ? c : a.Key.CompareTo(b.Key); });
            for (int i = 0; i < l.Count; i++) l[i] = idx[i].Value;
        }

        // ---- _verify / _verify_strip_labels on the rasters
        string Verify(List<TjMember> fam, List<TjPanelOut> panels, double px, double py, double pw, double ph, double tol, double pad)
        {
            foreach (var P in panels)
            {
                // (gen_traj_bg.py's _verify): three rows; a member refused only when missing on more than one of
                // the rows it crosses (a label's box blanks a line on at most one)
                var seen = new SortedDictionary<int, int[]>();
                var why = new Dictionary<int, string>();
                foreach (double frac in new double[] { 0.15, 0.21, 0.27 })
                {
                    int row = (int)TjPy.Round(py + frac * ph);
                    double vp = VPad(P.Vhi, P.Vlo, ph, pad);   // the field's rows span the padded band
                    double v = (P.Vhi + vp) - frac * ((P.Vhi + vp) - (P.Vlo - vp));
                    var xs = new List<int>();
                    for (int x = (int)px + 15; x < T.W; x++) if (P.Rgb[(row * T.W + x) * 3 + 1] > 40) xs.Add(x);
                    var grp = new List<List<int>>();
                    foreach (int x in xs)
                    {
                        if (grp.Count > 0 && x - grp[grp.Count - 1][grp[grp.Count - 1].Count - 1] <= 2) grp[grp.Count - 1].Add(x);
                        else grp.Add(new List<int> { x });
                    }
                    var drawn = new List<double>();
                    foreach (var gp in grp) drawn.Add((gp[0] + gp[gp.Count - 1]) / 2.0);
                    if (drawn.Count == 0) return "panel " + P.N + ": nothing drawn at row " + row;
                    foreach (var m in fam)
                    {
                        if ((int)m.Bank == 12) continue;
                        double r = RowAt(m.Rows, v, 3) / 1000.0;
                        if (!(P.X0 <= r && r <= P.X1)) continue;
                        double want = px + ((r - P.X0) / (P.X1 - P.X0)) * pw;
                             double best = double.MaxValue;
                        foreach (double d in drawn) best = Math.Min(best, Math.Abs(want - d));
                        foreach (var gp in grp) if (gp[0] <= want && want <= gp[gp.Count - 1]) best = 0;   // inside a run: crossing lines join
                        int b = (int)m.Bank;
                        if (!seen.ContainsKey(b)) seen[b] = new int[2];
                        seen[b][0]++;
                        if (best > tol)
                        {
                            seen[b][1]++;
                            if (!why.ContainsKey(b))
                                why[b] = "panel " + P.N + ": bank " + b + " should be at x " + TjPy.F(want, 0) + " (row " + row + ") but no line is within " + TjPy.F(tol, 0) + " px";
                        }
                    }
                }
                foreach (var kv in seen)
                    if (kv.Value[1] > 1 || (kv.Value[1] == 1 && kv.Value[0] == 1)) return why[kv.Key];
            }
            return "";
        }

        string VerifyStripLabels(List<TjPanelOut> panels)
        {
            int W = T.W, H = T.H;
            int xHi = (int)((A_STRIP_X - A_LAB_OFF + 0.002) * W);
            int xLo = Math.Max(0, xHi - (int)(0.046 * W));
            int yLo = (int)(0.10 * H), yHi = (int)(0.95 * H);
            Func<TjPanelOut, byte[]> crop = P =>
            {
                var o = new byte[(yHi - yLo) * (xHi - xLo)]; int k = 0;
                for (int y = yLo; y < yHi; y++)
                    for (int x = xLo; x < xHi; x++)
                    {
                        int i = (y * W + x) * 3;
                        o[k++] = (byte)((P.Rgb[i] * 19595 + P.Rgb[i + 1] * 38470 + P.Rgb[i + 2] * 7471 + 0x8000) >> 16);   // PIL 'L'
                    }
                return o;
            };
            var sorted = new List<TjPanelOut>(panels);
            sorted.Sort((a, b) => a.N.CompareTo(b.N));
            var crops = new Dictionary<int, byte[]>();
            foreach (var P in sorted) crops[P.N] = crop(P);
            foreach (var P in sorted)
                foreach (var Q in sorted)
                {
                    if (Q.N <= P.N) continue;
                    bool samePix = true; var a = crops[P.N]; var b = crops[Q.N];
                    for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) { samePix = false; break; }
                    bool sameScale = P.Asc[0] == Q.Asc[0] && P.Asc[1] == Q.Asc[1];
                    if (sameScale && !samePix) return "panels " + P.N + " and " + Q.N + " claim the same alpha scale but their labels differ";
                    if (!sameScale && samePix) return "panels " + P.N + " and " + Q.N + " claim different alpha scales but their labels are PIXEL-IDENTICAL";
                }
            return "";
        }

        /// main(): the panels and the sidecar text for a family. pngName(n, defaultName) gives each panel's file name as
        /// the sidecar lists it (python: traj<n>.png, or traj<n>_a<lo>-<hi>.png off the default alpha scale).
        /// dmax: the drag strip's top, 50 (the deorbit pages) or 100 (gen_traj_bg's $TRAJ_DMAX 100: the TAL pages).
        public TjResult Run(TjFamily f, Func<int, string, string> pngName, int dmax)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var res = new TjResult();
            string why = f.Validate(FAMILY_VERSION);
            if (why != "") { res.Why = "REFUSING: " + why; return res; }
            var fam = f.M;
            double vinit = double.NaN;
            foreach (var m in fam) foreach (var r in m.Rows) vinit = double.IsNaN(vinit) ? r[0] : PyMax(vinit, r[0]);
            double vtaem = f.Has("taem_vel") && f.Hdr["taem_vel"] is double ? f.Num("taem_vel") : 762.0;
            double scale = T.Scale;
            double dpi = BASE_DPI * scale;
            if (dpi != T.Dpi) { res.Why = "template dpi " + T.Dpi + " is not BASE_DPI * scale " + dpi; return res; }

            var top = fam[fam.Count - 1];
            double bankTop = top.Bank; bool hasArrest = false; double arrestV = 0;
            foreach (var r in top.Rows)
                if (PREENTRY_GUARD < r[4] && r[4] < bankTop - 0.1) { arrestV = hasArrest ? PyMax(arrestV, r[0]) : r[0]; hasArrest = true; }

            double PW = FIG_W * dpi, PH = FIG_H * dpi;
            double px = FIELD[0] * PW, pw = FIELD[2] * PW, ph = FIELD[3] * PH;
            double pad = double.Parse(TjPy.F(V_PAD_PX * scale, 1), System.Globalization.CultureInfo.InvariantCulture);   // as printed
            double py = (1.0 - FIELD[1] - FIELD[3]) * PH;
            object vs;
            string vessel = f.Hdr.TryGetValue("vessel", out vs) && vs is string ? (string)vs : "?";
            if (!(f.Hdr.ContainsKey("written") && f.Hdr["written"] is double)) { res.Why = "the family has no written stamp"; return res; }
            var o = new List<string> {
                "version 2", "vessel " + vessel, "written " + TjPy.F(f.Num("written"), 3), "aero_ver " + TjPy.F(f.Num("aero_ver"), 1),
                "v_init " + TjPy.F(vinit, 2), "v_taem " + TjPy.F(vtaem, 2), "png_w " + (int)PW, "png_h " + (int)PH,
                "# the plot field inside the PNG, pixels, MARGIN:V measured from the top",
                "field_px " + TjPy.F(px, 1) + " " + TjPy.F(py, 1) + " " + TjPy.F(pw, 1) + " " + TjPy.F(ph, 1),
                "# the band is drawn this many px inside the field's top and bottom",
                "v_pad_px " + TjPy.F(pad, 1),
                "# per panel: n  vhi  vlo  x0_km  x1_km  arrest_v  png  aLo aHi  dLo dHi" };
            var bands = PanelBands(vinit, vtaem);
            for (int n = 1; n <= 5; n++)
            {
                double vhi = bands[n - 1][0], vlo = bands[n - 1][1];
                var lines = new List<Line>();
                double vpad = VPad(vhi, vlo, ph, pad);
                foreach (var L in FamilyLines(fam, (vlo - vpad) * 0.96)) if ((int)L.Bank != 12) lines.Add(L);
                if (lines.Count == 0) { res.Log += "panel " + n + ": no members in band -- skipped\n"; continue; }
                double x0, x1; double[] asc, dsc;
                byte[] rgb = DrawPanel(fam, lines, vhi, vlo, n, dpi, arrestV, hasArrest, dmax, vpad, out x0, out x1, out asc, out dsc);
                string drawn = "traj" + n + ".png", name = drawn;
                if (!(asc[0] == DEFAULT_ASCALE[0] && asc[1] == DEFAULT_ASCALE[1])) name = "traj" + n + "_a" + TjPy.G(asc[0]) + "-" + TjPy.G(asc[1]) + ".png";
                name = pngName(n, name);
                o.Add("P " + n + " " + TjPy.F(vhi, 2) + " " + TjPy.F(vlo, 2) + " " + TjPy.F(x0, 3) + " " + TjPy.F(x1, 3) + " " +
                      TjPy.F(hasArrest && arrestV != 0 ? arrestV : -1, 2) + " " + name + " " + TjPy.G(asc[0]) + " " + TjPy.G(asc[1]) + " " +
                      TjPy.G(dsc[0]) + " " + TjPy.G(dsc[1]));
                res.Panels.Add(new TjPanelOut { N = n, Vhi = vhi, Vlo = vlo, X0 = x0, X1 = x1, Drawn = drawn, Name = name, Asc = asc, Dsc = dsc, Rgb = rgb });
            }
            if (res.Panels.Count == 0) { res.Why = "no panel has members"; return res; }
            int W = T.W, H = T.H;
            o.Add("# readout value rows, pixels from the top, and the right edge to align to");
            var sb = new StringBuilder("tl_rows");
            foreach (double y in TL_Y) sb.Append(" " + TjPy.F((1.0 - y) * FIG_H * dpi, 1));
            o.Add(sb.ToString());
            o.Add("tl_right " + TjPy.F(TL_RIGHT * PW, 1));
            sb = new StringBuilder("br_rows");
            foreach (double y in BR_Y) sb.Append(" " + TjPy.F((1.0 - y) * FIG_H * dpi, 1));
            o.Add(sb.ToString());
            o.Add("br_right " + TjPy.F(BR_RIGHT * PW, 1));
            o.Add("# the MET clock: right edge and baseline row, drawn live by kOS");
            o.Add("clock_px " + TjPy.F(CLOCK_RIGHT * PW, 1) + " " + TjPy.F(CLOCK_TOP * PH, 1));
            o.Add("# the two strip scales: x centre, and the pixel row of the scale ends");
            o.Add("strip_a " + TjPy.F(A_STRIP_X * W, 1) + " " + TjPy.F(H * (1.0 - SHI), 1) + " " + TjPy.F(H * (1.0 - SLO), 1));
            o.Add("strip_d " + TjPy.F(D_STRIP_X * W, 1) + " " + TjPy.F(H * (1.0 - SHI), 1) + " " + TjPy.F(H * (1.0 - SLO), 1));

            string bad = Verify(fam, res.Panels, px, py, pw, ph, 6.0, pad);
            if (bad != "") { res.Why = "SIDECAR DOES NOT MATCH THE PANELS: " + bad; return res; }
            foreach (var P in res.Panels)
                foreach (double v in new[] { P.Vhi, P.Vlo })
                {
                    double a = AoaSchedule(v);
                    if (!(P.Asc[0] + 1.0 <= a && a <= P.Asc[1] - 1.0))
                    { res.Why = "PANEL " + P.N + " SHOWS AoA " + TjPy.F(a, 2) + " AT " + TjPy.F(v, 0) + " m/s, OUTSIDE ITS STRIP"; return res; }
                }
            bad = VerifyStripLabels(res.Panels);
            if (bad != "") { res.Why = "STRIP LABELS DO NOT MATCH THE SCALES: " + bad; return res; }
            res.Sidecar = string.Join("\n", o.ToArray()) + "\n";
            res.Ok = true;
            if (MissingLabels != "") res.Log += "labels not in the atlas (not drawn): " + MissingLabels + "\n";
            res.Ms = sw.Elapsed.TotalMilliseconds;
            return res;
        }
    }
}
