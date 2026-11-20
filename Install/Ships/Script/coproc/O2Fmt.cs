// ops2q's number / time formatters in C#: lib_o2ui.ks o2Fx, o2F, o2Sv, o2Sg, o2P2, o2Met, o2Cd, o2Ms,
// the same text for the same number (kOS's ROUND is Math.Round, banker's, on the scaled value; its number-to-text is
// ScalarValue's own). The page builders in C# (O2Mnvr.cs ...) use these so a row a kOS builder writes and a row a C# builder
// writes are the same characters. tests/o2page_offline compares every one against kOS's own output (recorded in the kOS VM).
// Pure functions, nothing here touches the game or throws for a finite number.
using System;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class O2Fmt
    {
        static string KStr(double x) { return ScalarValue.Create(x).ToString(); }
        public static string Str(double x) { return KStr(x); }       // "" + x in kOS

        // o2Fx: x with d decimals, always shown (no sign for x >= 0; "-" only when the rounded value is not 0)
        public static string Fx(double x, int d)
        {
            double m = Math.Pow(10, d);
            double a = Math.Round(Math.Abs(x) * m);
            double ip = Math.Floor(a / m);
            string s = KStr(ip);
            if (d > 0) s = s + "." + KStr(a - ip * m).PadLeft(d).Replace(" ", "0");
            if (x < 0 && a > 0) s = "-" + s;
            return s;
        }

        // o2F: Fx right-aligned in w
        public static string F(double x, int w, int d) { return Fx(x, d).PadLeft(w); }

        // o2Sv: a sign only when the rounded value is not 0: "+41.6", "  0.0", " -2.1"
        public static string Sv(double x, int w, int d)
        {
            if (Math.Round(Math.Abs(x) * Math.Pow(10, d)) == 0) return Fx(0, d).PadLeft(w);
            return ((x < 0 ? "-" : "+") + Fx(Math.Abs(x), d)).PadLeft(w);
        }

        // o2Sg: the sign in front, the number right-aligned after it: "+ 41.6", "-  2.1"
        public static string Sg(double x, int w, int d)
        {
            string a = Fx(Math.Abs(x), d);
            string sg = (x < 0 && Math.Round(Math.Abs(x) * Math.Pow(10, d)) > 0) ? "-" : "+";
            return sg + a.PadLeft(w - 1);
        }

        // o2P2: two digits, zero padded
        public static string P2(double n) { return KStr(n).PadLeft(2).Replace(" ", "0"); }

        // o2Met: DDD/HH:MM:SS
        public static string Met(double t)
        {
            double s = Math.Floor(Math.Max(0, t) + 0.5);
            double d = Math.Floor(s / 86400);
            s = s - d * 86400;
            double h = Math.Floor(s / 3600);
            s = s - h * 3600;
            double mi = Math.Floor(s / 60);
            return KStr(d).PadLeft(3).Replace(" ", "0") + "/" + P2(h) + ":" + P2(mi) + ":" + P2(s - mi * 60);
        }

        // o2Cd: a countdown, -HH:MM:SS before, +HH:MM:SS after
        public static string Cd(double t)
        {
            double s = Math.Floor(Math.Abs(t) + 0.5);
            double h = Math.Floor(s / 3600);
            s = s - h * 3600;
            double mi = Math.Floor(s / 60);
            return (t > 0 ? "-" : "+") + P2(h) + ":" + P2(mi) + ":" + P2(s - mi * 60);
        }

        // o2Ms: m:ss (kOS MOD(s, 60) on a whole number)
        public static string Ms(double t)
        {
            double s = Math.Floor(Math.Max(0, t) + 0.5);
            return KStr(Math.Floor(s / 60)) + ":" + P2(s % 60);
        }
    }
}
