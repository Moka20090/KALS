// The failure list of the failure system (lib/lib_fail.ks's catalog), held in C# so a script cannot undo it. NO KSP or kOS
// type here: FailVessel.cs keeps one FailState per vessel (saved with the vessel), KalsAddon.Fail.cs is the kOS face, and
// tests/fail_offline runs this very file against its own checks.
//
// WHAT IT HOLDS
//   * the FAILURES: code ("MPS 01" ...), target ("L", "G3", a jet name), value ("75 %"), mode ("P" permanent / "T" transient),
//     the time it happened (UT) and, once a real fix is under way, the time it ends (HealAt, UT) and the fix's name (Via).
//   * the SPARE GPC (one per flight; a hardware GPC fail is swapped for it, SWAP SPARE).
//   * the SIMSUP LATCH: latched, difficulty, seed hash, counter (decision points passed) and fired (failures injected since the
//     latch). The seed hash goes in and out of the save only; nothing in the kOS face returns it.
//   * the flight watch: when a latched flight ends (the vessel has landed and sat still, having been airborne in this
//     flight), the list and the latch are dropped.
// WHAT IT REFUSES (every answer is "OK" or "REFUSE: <text>", the words the kOS window shows)
//   Set:  unknown code, a mode the code does not offer, a second failure of the same (code, target), a full list, a target /
//         value with a comma or a control character (the save is comma-free text).
//   Bind: no such failure, a failure already bound, a parts list that is not "uid[:n];..." or is empty.
//   Fix:  no such failure, a fix already under way, a PERMANENT failure (the one exception: a GPC hardware fail may be
//         SWAPped for the spare), a code with no fix, the wrong fix for the code, a GPC RESTART before its 5 s STBY is over,
//         a second SWAP SPARE.
//   There is no call that removes a failure except a fix's own timer (Tick), and none that unlatches except the flight watch.
// THE SIMSUP PLANNER + RAND's table are SimSup.cs; FailState holds one (Sup) and saves it in the SIM record while latched.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace KalsCoproc
{
    public sealed class FailEntry
    {
        public string Code, Target, Value, Mode, Via;
        public double At;                       // UT it was injected
        public double HealAt = -1;              // UT its fix ends, -1 = no fix under way
        // THE PARTS IT ACTS ON: ';'-joined tokens "uid" (the whole part) or "uid:n" (its n-th module of the kind), bound once by
        // FailState.Bind and saved with the vessel. "" = not bound: the entry is held in the list but acts on no part.
        public string Parts = "";
        // runtime only (FailEnforce writes them, never saved): the parts found on the vessel last tick, and how many times the enforcement
        // had to undo something (an engine re-lit, a limit raised, a jet switched on ...): the spike's measure of "it holds".
        public int Found, Corrections;
        string[] tok;

        public string[] Tokens()
        {
            if (tok == null) tok = Parts.Length == 0 ? new string[0] : Parts.Split(';');
            return tok;
        }
        public void SetParts(string p) { Parts = p ?? ""; tok = null; }

        public FailEntry Copy() { return (FailEntry)MemberwiseClone(); }
    }

    public sealed class FailCode
    {
        public string Code, Modes, Fix;         // modes "P" / "PT" / "T"; Fix = the real fix's name, "" = none
        public double Delay;                    // the fix's time in s
        public FailCode(string c, string m, string f, double d) { Code = c; Modes = m; Fix = f; Delay = d; }
    }

    public sealed class FailState
    {
        public const int MaxEntries = 32;
        public const double RestartStby = 5;    // s a transient GPC fail must sit in STBY before RESTART
        public const double LandedHold = 60;    // s the landed vessel must sit still before a latched flight ends
        public const double StillSpeed = 0.5;   // m/s: "sitting still"
        public const string SwapSpare = "SWAP SPARE";
        public const int Version = 1;

        // the same table as lib_fail.ks's catalog (code, modes, real fix, delay); targets and values are the kOS side's to check
        public static readonly FailCode[] Table = new FailCode[]
        {
            new FailCode("MPS 01", "P",  "",                        0),
            new FailCode("MPS 02", "P",  "",                        0),
            new FailCode("MPS 03", "P",  "",                        0),
            new FailCode("OMS 01", "P",  "",                        0),
            new FailCode("OMS 02", "P",  "",                        0),
            new FailCode("OMS 03", "P",  "",                        0),
            new FailCode("OMS 04", "PT", "ISOLATE TANK",            5),
            new FailCode("RCS 01", "PT", "MANIFOLD VALVES RE-OPEN", 5),
            new FailCode("RCS 02", "P",  "",                        0),
            new FailCode("RCS 03", "PT", "MANIFOLD CLOSE",          5),
            new FailCode("RCS 04", "PT", "MANIFOLD CLOSE",          5),
            new FailCode("FCS 01", "P",  "",                        0),
            new FailCode("DPS 01", "P",  "",                        0),
            new FailCode("DPS 02", "T",  "RESTART",                 65),
            new FailCode("DPS 03", "PT", "RESTART",                 65),     // GPC FAIL TO SYNC (dropped out of the redundant set; a transient one restarts, a permanent one only has its displays moved)
            new FailCode("DPS 06", "T",  "RESTART",                 65),     // GPC OUTPUT BAD (a short bad-command spell, then out of the set like DPS 03)
            new FailCode("DPS 04", "T",  "PICK PAIR",               3),      // REDUNDANT SET SPLIT 2-2 (the guidance holds until the crew picks the right pair; the kOS side refuses the wrong pair and the plain FIX)
            new FailCode("DPS 05", "T",  "RE-IPL PASS",             20),     // PASS GENERIC SOFTWARE FAIL (the BFS flies the rest; the PASS set is loaded again at the OPS 2 start)
            new FailCode("SW 01",  "PT", "RESTART SW",              10),
            new FailCode("SW 02",  "PT", "RESTART SW",              10),
            new FailCode("SW 03",  "T",  "RE-SELECT PAGE",          2),
        };
        public const double SpareDelay = 3600;  // SWAP SPARE: a 60-minute task

        public const int MaxParts = 256;        // tokens in one Parts string

        // a failure's VALUE as a thrust limit: "60 %" -> 60; 100 (no cap) for anything else
        public static float Cap(string value)
        {
            if (string.IsNullOrEmpty(value)) return 100f;
            string w = value.Trim().Split(' ')[0];
            float f;
            return float.TryParse(w, NumberStyles.Float, CultureInfo.InvariantCulture, out f) && f >= 0f && f <= 100f ? f : 100f;
        }

        public static FailCode Find(string code)
        {
            foreach (FailCode c in Table) if (c.Code == code) return c;
            return null;
        }

        public readonly List<FailEntry> List = new List<FailEntry>();
        public bool SpareUsed;
        public bool Latched;
        public int Difficulty;
        public long SeedHash;
        public int Counter, Fired;
        public bool WasAirborne;
        public double SlowSince = -1;
        // THE SIMSUP PLANNER (SimSup.cs): its counter, picks made and the hidden pending picks are saved in the SIM record ("ss.*")
        public readonly SimSup Sup = new SimSup();

        static bool Clean(string s)
        {
            if (s == null) return true;
            foreach (char ch in s) if (ch == ',' || ch == '\n' || ch == '\r' || ch == '=' || ch < 32) return false;
            return true;
        }
        static string N(string s) { return s == null ? "" : s.Trim().ToUpperInvariant(); }

        public int IndexOf(string code, string target)
        {
            for (int i = 0; i < List.Count; i++) if (List[i].Code == code && List[i].Target == target) return i;
            return -1;
        }

        // ---- inject
        public string Set(string code, string target, string value, string mode, double now)
        {
            code = N(code); target = N(target); value = N(value); mode = N(mode);
            FailCode fc = Find(code);
            if (fc == null) return "REFUSE: UNKNOWN CODE " + code;
            if (mode != "P" && mode != "T") return "REFUSE: BAD MODE " + mode;
            if (fc.Modes.IndexOf(mode, StringComparison.Ordinal) < 0) return "REFUSE: MODE " + mode + " NOT OFFERED";
            if (!Clean(target) || !Clean(value)) return "REFUSE: BAD TEXT";
            if (IndexOf(code, target) >= 0) return "REFUSE: ALREADY FAILED";
            if (List.Count >= MaxEntries) return "REFUSE: FAILURE LIST FULL";
            List.Add(new FailEntry { Code = code, Target = target, Value = value, Mode = mode, At = now, HealAt = -1, Via = "" });
            if (Latched) Fired++;
            return "OK";
        }

        // ---- a real fix
        public string Fix(string code, string target, string via, double now)
        {
            code = N(code); target = N(target); via = N(via);
            int i = IndexOf(code, target);
            if (i < 0) return "REFUSE: NO SUCH FAILURE";
            FailEntry e = List[i];
            if (e.HealAt >= 0) return "REFUSE: FIX UNDER WAY";
            FailCode fc = Find(code);
            string want = fc.Fix;
            double delay = fc.Delay;
            if (code == "DPS 01" && e.Mode == "P")
            {                                   // the one permanent failure with a fix: the spare GPC
                if (via != SwapSpare) return "REFUSE: HARDWARE FAIL: ONLY " + SwapSpare;
                if (SpareUsed) return "REFUSE: THE SPARE IS USED";
                want = SwapSpare; delay = SpareDelay;
            }
            else
            {
                if (e.Mode != "T" || want.Length == 0) return "REFUSE: NO FIX";
                if (via != want) return "REFUSE: WRONG FIX " + via + " (" + want + ")";
                if ((code == "DPS 02" || code == "DPS 03" || code == "DPS 06") && now - e.At < RestartStby)
                    return "REFUSE: STBY " + Math.Ceiling(RestartStby - (now - e.At)).ToString(CultureInfo.InvariantCulture) + " S";
            }
            if (code == "DPS 01") SpareUsed = true;
            e.HealAt = now + delay;
            e.Via = want;
            return "OK";
        }

        // the parts a failure acts on: "uid[:n];uid[:n]..." -> the same normalised ("" never; null = not a valid list)
        public static string NormParts(string s)
        {
            if (s == null) return null;
            var seen = new HashSet<string>();
            var sb = new StringBuilder();
            foreach (string t0 in s.Split(';'))
            {
                string t = t0.Trim();
                if (t.Length == 0) continue;
                int q = t.IndexOf(':');
                string u = q < 0 ? t : t.Substring(0, q);
                string m = q < 0 ? "" : t.Substring(q + 1);
                if (u.Length == 0 || u.Length > 12 || (q >= 0 && (m.Length == 0 || m.Length > 3))) return null;
                foreach (char c in u) if (c < '0' || c > '9') return null;
                foreach (char c in m) if (c < '0' || c > '9') return null;
                if (!seen.Add(t)) continue;
                if (seen.Count > MaxParts) return null;
                if (sb.Length > 0) sb.Append(';');
                sb.Append(t);
            }
            return sb.ToString();
        }

        // ---- bind a failure to its parts, ONCE (the kOS side knows which engine / jets / surface it failed; the DLL holds them to it)
        public string Bind(string code, string target, string parts)
        {
            code = N(code); target = N(target);
            int i = IndexOf(code, target);
            if (i < 0) return "REFUSE: NO SUCH FAILURE";
            if (List[i].Parts.Length > 0) return "REFUSE: ALREADY BOUND";
            string norm = NormParts(parts);
            if (norm == null) return "REFUSE: BAD PARTS";
            if (norm.Length == 0) return "REFUSE: NO PARTS";
            List[i].SetParts(norm);
            return "OK";
        }

        // fixes whose time is over: the entry goes. Returns how many went.
        public int Tick(double now) { return Tick(now, null); }
        public int Tick(double now, List<FailEntry> gone)
        {
            int n = 0;
            for (int i = List.Count - 1; i >= 0; i--)
                if (List[i].HealAt >= 0 && now >= List[i].HealAt) { if (gone != null) gone.Add(List[i]); List.RemoveAt(i); n++; }
            return n;
        }

        // ---- the SimSup latch
        // TRUE the first time only
        public bool Latch(int difficulty, long seedHash)
        {
            if (Latched) return false;
            Latched = true; Difficulty = difficulty; SeedHash = seedHash; Counter = 0; Fired = 0;
            Sup.Reset();
            return true;
        }
        // a decision point passed (only counts while latched); returns the counter
        public int Point() { if (Latched) Counter++; return Counter; }

        // ---- the flight watch: called each tick with the vessel's facts; TRUE when it dropped the list and the latch
        public bool Watch(double now, bool airborne, bool landed, double speed)
        {
            if (!Latched) { SlowSince = -1; return false; }
            if (airborne) { WasAirborne = true; SlowSince = -1; return false; }
            if (landed && WasAirborne && speed < StillSpeed)
            {
                if (SlowSince < 0) SlowSince = now;
                if (now - SlowSince >= LandedHold) { EndFlight(); return true; }
            }
            else SlowSince = -1;
            return false;
        }
        public void EndFlight()
        {
            List.Clear();
            Latched = false; Difficulty = 0; SeedHash = 0; Counter = 0; Fired = 0;
            SpareUsed = false; WasAirborne = false; SlowSince = -1;
            Sup.Reset();
        }

        // ---- the save: plain text records (FailVessel turns them into a ConfigNode, the offline test into one text block)
        static string D(double v) { return v.ToString("R", CultureInfo.InvariantCulture); }
        static double Pd(string s, double dflt)
        {
            double v;
            return s != null && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : dflt;
        }
        static long Pl(string s, long dflt)
        {
            long v;
            return s != null && long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : dflt;
        }

        public Dictionary<string, string> SimRecord()
        {
            var d = new Dictionary<string, string>();
            d["version"] = Version.ToString(CultureInfo.InvariantCulture);
            d["latched"] = Latched ? "1" : "0";
            d["difficulty"] = Difficulty.ToString(CultureInfo.InvariantCulture);
            d["seedHash"] = SeedHash.ToString(CultureInfo.InvariantCulture);
            d["counter"] = Counter.ToString(CultureInfo.InvariantCulture);
            d["fired"] = Fired.ToString(CultureInfo.InvariantCulture);
            d["spareUsed"] = SpareUsed ? "1" : "0";
            d["wasAirborne"] = WasAirborne ? "1" : "0";
            d["slowSince"] = D(SlowSince);
            if (Latched) Sup.Record(d);
            return d;
        }
        public List<Dictionary<string, string>> FailRecords()
        {
            var r = new List<Dictionary<string, string>>();
            foreach (FailEntry e in List)
            {
                var d = new Dictionary<string, string>();
                d["code"] = e.Code; d["target"] = e.Target; d["value"] = e.Value; d["mode"] = e.Mode;
                d["at"] = D(e.At); d["healAt"] = D(e.HealAt); d["via"] = e.Via; d["parts"] = e.Parts;
                r.Add(d);
            }
            return r;
        }
        // replaces the whole state; a record that is not a valid failure is dropped (a damaged save never throws)
        public void Restore(Dictionary<string, string> sim, List<Dictionary<string, string>> fails)
        {
            List.Clear();
            Latched = false; Difficulty = 0; SeedHash = 0; Counter = 0; Fired = 0; SpareUsed = false; WasAirborne = false; SlowSince = -1;
            if (sim != null)
            {
                string s;
                Latched = sim.TryGetValue("latched", out s) && s == "1";
                Difficulty = (int)Pl(sim.TryGetValue("difficulty", out s) ? s : null, 0);
                SeedHash = Pl(sim.TryGetValue("seedHash", out s) ? s : null, 0);
                Counter = (int)Pl(sim.TryGetValue("counter", out s) ? s : null, 0);
                Fired = (int)Pl(sim.TryGetValue("fired", out s) ? s : null, 0);
                SpareUsed = sim.TryGetValue("spareUsed", out s) && s == "1";
                WasAirborne = sim.TryGetValue("wasAirborne", out s) && s == "1";
                SlowSince = Pd(sim.TryGetValue("slowSince", out s) ? s : null, -1);
            }
            Sup.Restore(Latched ? sim : null);
            if (fails == null) return;
            foreach (Dictionary<string, string> d in fails)
            {
                string code, tg, vl, md, at, ha, via, pa;
                d.TryGetValue("parts", out pa);
                d.TryGetValue("code", out code); d.TryGetValue("target", out tg); d.TryGetValue("value", out vl);
                d.TryGetValue("mode", out md); d.TryGetValue("at", out at); d.TryGetValue("healAt", out ha); d.TryGetValue("via", out via);
                FailCode fc = Find(code);
                if (fc == null || (md != "P" && md != "T") || List.Count >= MaxEntries || IndexOf(code, tg ?? "") >= 0) continue;
                var fe = new FailEntry { Code = code, Target = tg ?? "", Value = vl ?? "", Mode = md, At = Pd(at, 0), HealAt = Pd(ha, -1), Via = via ?? "" };
                fe.SetParts(NormParts(pa) ?? "");           // a damaged parts string is dropped, the failure stays
                List.Add(fe);
            }
        }

        // the same records as one text block (the offline test's round trip, and a readable dump for the log)
        public string Serialize()
        {
            var sb = new StringBuilder();
            sb.Append("SIM");
            foreach (var kv in SimRecord()) sb.Append(',').Append(kv.Key).Append('=').Append(kv.Value);
            sb.Append('\n');
            foreach (var d in FailRecords())
            {
                sb.Append("FAIL");
                foreach (var kv in d) sb.Append(',').Append(kv.Key).Append('=').Append(kv.Value);
                sb.Append('\n');
            }
            return sb.ToString();
        }
        public static FailState Parse(string text)
        {
            var st = new FailState();
            Dictionary<string, string> sim = null;
            var fails = new List<Dictionary<string, string>>();
            foreach (string ln in (text ?? "").Split('\n'))
            {
                string[] f = ln.Trim().Split(',');
                if (f.Length == 0 || (f[0] != "SIM" && f[0] != "FAIL")) continue;
                var d = new Dictionary<string, string>();
                for (int i = 1; i < f.Length; i++) { int q = f[i].IndexOf('='); if (q > 0) d[f[i].Substring(0, q)] = f[i].Substring(q + 1); }
                if (f[0] == "SIM") sim = d; else fails.Add(d);
            }
            st.Restore(sim, fails);
            return st;
        }
    }
}
