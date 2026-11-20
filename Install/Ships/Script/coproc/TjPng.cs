// a PNG writer in pure C# (mscorlib only: no System.Drawing, no System.IO.Compression, no Unity), so it runs on
// a worker thread under KSP's Mono. RGB 8-bit, one IDAT, per-row filter = the smallest sum of |bytes| among None / Sub /
// Up / Paeth, zlib = one deflate block with the fixed Huffman codes and an LZ77 hash chain (32 K window, matches 3..258).
using System;
using System.IO;

namespace KalsCoproc
{
    public static class TjPng
    {
        static readonly uint[] crcTab = MakeCrc();

        static uint[] MakeCrc()
        {
            var t = new uint[256];
            for (uint n = 0; n < 256; n++)
            {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                t[n] = c;
            }
            return t;
        }

        static uint Crc(byte[] b, int off, int len, uint c)
        {
            for (int i = 0; i < len; i++) c = crcTab[(c ^ b[off + i]) & 0xff] ^ (c >> 8);
            return c;
        }

        /// <summary>rgba: w*h*4 bytes, rows top first, straight (not premultiplied) alpha. Returns the PNG file's bytes.
        /// Filter 0 (None) on every row: a mostly transparent line image is zero runs the LZ77 matches whole, and the filter
        /// search is what costs here.</summary>
        public static byte[] EncodeRgba(byte[] rgba, int w, int h)
        {
            int stride = w * 4;
            var raw = new byte[(stride + 1) * h];
            for (int y = 0; y < h; y++) Buffer.BlockCopy(rgba, y * stride, raw, y * (stride + 1) + 1, stride);
            byte[] z = Zlib(raw);
            var ms = new MemoryStream(z.Length + 100);
            ms.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
            var ihdr = new byte[13];
            BE(ihdr, 0, (uint)w); BE(ihdr, 4, (uint)h);
            ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
            Chunk(ms, "IHDR", ihdr);
            Chunk(ms, "IDAT", z);
            Chunk(ms, "IEND", new byte[0]);
            return ms.ToArray();
        }

        static void BE(byte[] b, int o, uint v)
        {
            b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v;
        }

        static void Chunk(Stream s, string type, byte[] data)
        {
            var hdr = new byte[8];
            BE(hdr, 0, (uint)data.Length);
            for (int i = 0; i < 4; i++) hdr[4 + i] = (byte)type[i];
            s.Write(hdr, 0, 8);
            s.Write(data, 0, data.Length);
            uint c = Crc(hdr, 4, 4, 0xffffffffu);
            c = Crc(data, 0, data.Length, c) ^ 0xffffffffu;
            var cb = new byte[4]; BE(cb, 0, c);
            s.Write(cb, 0, 4);
        }

        // ---- zlib / deflate (RFC 1950 / 1951), fixed Huffman ----
        sealed class Bits
        {
            public byte[] buf = new byte[1 << 16]; public int n; ulong acc; int nb;
            public void Put(uint v, int len)
            {
                acc |= (ulong)v << nb; nb += len;
                while (nb >= 8) { if (n == buf.Length) Array.Resize(ref buf, buf.Length * 2); buf[n++] = (byte)acc; acc >>= 8; nb -= 8; }
            }
            public void Flush() { if (nb > 0) Put(0, 8 - nb); }
            public void Byte(byte b) { if (n == buf.Length) Array.Resize(ref buf, buf.Length * 2); buf[n++] = b; }
        }

        static uint Rev(uint code, int len) { uint r = 0; for (int i = 0; i < len; i++) { r = (r << 1) | (code & 1); code >>= 1; } return r; }

        static void Lit(Bits o, int v)
        {
            if (v < 144) o.Put(Rev((uint)(0x30 + v), 8), 8);
            else if (v < 256) o.Put(Rev((uint)(0x190 + v - 144), 9), 9);
            else if (v < 280) o.Put(Rev((uint)(v - 256), 7), 7);
            else o.Put(Rev((uint)(0xC0 + v - 280), 8), 8);
        }

        static readonly int[] lenBase = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
        static readonly int[] lenExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        static readonly int[] distBase = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        static readonly int[] distExtra = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

        static void Match(Bits o, int len, int dist)
        {
            int li = 28;
            while (lenBase[li] > len) li--;
            Lit(o, 257 + li);
            if (lenExtra[li] > 0) o.Put((uint)(len - lenBase[li]), lenExtra[li]);
            int di = 29;
            while (distBase[di] > dist) di--;
            o.Put(Rev((uint)di, 5), 5);
            if (distExtra[di] > 0) o.Put((uint)(dist - distBase[di]), distExtra[di]);
        }

        public static byte[] Zlib(byte[] d)
        {
            var o = new Bits();
            o.Byte(0x78); o.Byte(0x01);
            o.Put(1, 1); o.Put(1, 2);           // BFINAL, BTYPE = 01 (fixed Huffman)
            const int HB = 15, HS = 1 << HB, WIN = 32768, CHAIN = 48;
            var head = new int[HS];
            for (int i = 0; i < HS; i++) head[i] = -1;
            var prev = new int[WIN];
            int n = d.Length, p = 0;
            while (p < n)
            {
                int bestLen = 0, bestDist = 0;
                if (p + 2 < n)
                {
                    int hsh = ((d[p] << 10) ^ (d[p + 1] << 5) ^ d[p + 2]) & (HS - 1);
                    int c = head[hsh], chain = CHAIN;
                    int maxLen = Math.Min(258, n - p);
                    while (c >= 0 && p - c <= WIN && chain-- > 0)
                    {
                        if (d[c + bestLen] == d[p + bestLen] && d[c] == d[p])
                        {
                            int l = 0;
                            while (l < maxLen && d[c + l] == d[p + l]) l++;
                            if (l > bestLen) { bestLen = l; bestDist = p - c; if (l == maxLen) break; }
                        }
                        int pc = prev[c & (WIN - 1)];
                        if (pc >= c) break;
                        c = pc;
                    }
                }
                int adv = bestLen >= 3 ? bestLen : 1;
                if (bestLen >= 3) Match(o, bestLen, bestDist); else Lit(o, d[p]);
                for (int k = 0; k < adv; k++, p++)
                {
                    if (p + 2 < n)
                    {
                        int hsh = ((d[p] << 10) ^ (d[p + 1] << 5) ^ d[p + 2]) & (HS - 1);
                        prev[p & (WIN - 1)] = head[hsh];
                        head[hsh] = p;
                    }
                }
            }
            Lit(o, 256);
            o.Flush();
            uint s1 = 1, s2 = 0;
            for (int i = 0; i < n; i++) { s1 = (s1 + d[i]) % 65521; s2 = (s2 + s1) % 65521; }
            uint ad = (s2 << 16) | s1;
            o.Byte((byte)(ad >> 24)); o.Byte((byte)(ad >> 16)); o.Byte((byte)(ad >> 8)); o.Byte((byte)ad);
            var r = new byte[o.n];
            Buffer.BlockCopy(o.buf, 0, r, 0, o.n);
            return r;
        }
    }
}
