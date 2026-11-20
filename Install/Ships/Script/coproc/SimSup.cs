// SIMSUP MODE + RAND: the planner that picks the failures of a SimSup flight, the
// CAPABILITY ACCOUNT that keeps a SimSup flight survivable, and RAND's hazard table for every flyable failure code. NO KSP or kOS
// type here: FailState (Fail.cs) holds one SimSup, FailVessel saves it with the vessel, KalsAddon.Fail.cs is the kOS face, and
// tests/simsup_offline runs this very file.
//
// THE OWNER'S WORDS: "Also, we kind of forgot about SimSup mode. I want that in by Friday."
//   "And random failures can be any of the failure items, right?" / "And random failure should be able to make a flight
//   unflyable, that's the point." / "SimSup should be survivable, not RAND".
//   -> SIMSUP: scripted, seeded, hidden picks that ALWAYS pass the survivability floors. RAND: every flyable code, NO floors.
//
// HOW A SIMSUP FLIGHT RUNS (the latch is FailState.Latch; nothing here runs unless it is latched)
//   * Host(prog, codes): the program flying now ("OPS1" ascent, "OPS2" orbit, "OPS3" entry, "OPS6" RTLS / TAL entry) and the
//     codes it has a handler for (lib_fail's FL_HAND keys). Only those codes are ever picked.
//   * Point(name, edgeUt, now): a DECISION POINT (the Points table: abort edges, MECO, a burn's TIG, EI, TAEM, the HAC ...). The
//     planner may schedule a hidden pick before the edge (lead = the difficulty's) or start a SCRIPT TEMPLATE (several picks).
//   * Tick(now, tig, phase, randOk, dt): random-time picks (a fraction of RAND x1's hazard) and the due pick. Returns the pick to
//     fire ("code|target|value|mode") or "". The host fires it with flFire(..., "SIMSUP") and answers Result(code, target, res):
//     "OK" confirms it (a CHAINED pick may follow from its backup list), "DEFER" offers it again next tick, a refusal drops it.
//   * Every pick goes through Check (the floors) and Workload (unresolved count, spacing, the burn's quiet time) when it is due.
//     A pick that breaks a floor is NOT fired (a PT code first tries its transient mode); the hazard clock keeps running.
//   * SEEDED + HIDDEN: every choice is Draw() = SplitMix64(seed, counter); the state is (seed, counter) + the pending picks, all
//     saved with the vessel; nothing returns a pending pick before it is due.
// RAND (outside SimSup): Rand(prog, codes, scale, dt, phase) draws from the same hazard table with NO floors.
// THE FLOORS ARE CONSERVATIVE FIRST VALUES (the offline capability tables from the sims come after the release; the project owner
// tunes the rates and the difficulty numbers). Check() with level HARD is the "miserable but not impossible" line the window's
// RTN IMPSBLE warning uses on a player's own row.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace KalsCoproc
{
    public sealed class SimPick
    {
        public string Code, Target, Value, Mode, Src;
        public double Due, Expire;
        public bool Offered;
        public int Dbl;                         // the DOUBLE-UP draw (Workload): 0 not drawn yet, 1 allowed, 2 refused
        public double Gap = -1;                 // This pick's own NO PILOT gap (s), drawn once on its first Workload (SimSup.NoPilotGapOf); -1 = not drawn yet
        public int Opt;                         // The scenario step's Check options (SimSup.Opt*), 0 = none
        public string Wait = "";                // A scenario step that waits for a decision point ("TAEM"): not due until Point(Wait) releases it
        public SimPick Copy() { return (SimPick)MemberwiseClone(); }
    }

    // one step of a script template / SCENARIO: at the scenario's start + Offset (+ a seeded 0..Spread s) fail Code on Target with Value / Mode.
    // Target: "A/B" = one drawn; "=k" the target step k (0-based) drew; "~k" another target than step k's; "*" any now. Fluent options:
    //   Lv(n) the step exists only at level n and up; Soft() a step the floors may refuse without sinking the scenario (it is just dropped);
    //   Op(o) the Check options (SimSup.Opt*); After(p) the step waits for decision point p (then at that point's edge + Offset).
    public sealed class SimStep
    {
        public double Offset, Spread;
        public string Code, Target, Value, Mode, WaitPoint = "";
        public int MinLevel, Opt;
        public bool IsSoft;
        public SimStep(double o, string c, string t, string v, string m) { Offset = o; Code = c; Target = t; Value = v; Mode = m; }
        public SimStep Sp(double sp) { Spread = sp; return this; }
        public SimStep Lv(int lv) { MinLevel = lv; return this; }
        public SimStep Soft() { IsSoft = true; return this; }
        public SimStep Op(int o) { Opt = o; return this; }
        public SimStep After(string p) { WaitPoint = p; return this; }
    }

    // a script template (the old ones) or a SCENARIO: Point = the anchor(s) (' '-joined decision points; "*" = no point: it starts on a random-clock
    // pick, its offsets from that moment); Progs overrides the point's programs ("" = the point's); Rev = the ROLL_REV count it needs (0 = any, 1 = the first reversal,
    // 2 = the second); OrbitOnly = only on a flight the backbone draws as ORBIT (the ascent's engines are the backbone's: a scenario that touches an SSME leaves it alone)
    public sealed class SimTemplate
    {
        public string Name, Point, Trains, Progs = "";
        public int MinLevel, Rev;
        public bool OrbitOnly;
        public SimStep[] Steps;
        public SimTemplate(string n, string p, int lv, string trains, params SimStep[] s) { Name = n; Point = p; MinLevel = lv; Trains = trains; Steps = s; }
        public SimTemplate In(string progs) { Progs = progs; return this; }
        public SimTemplate Revs(int r) { Rev = r; return this; }
        public SimTemplate Orbit() { OrbitOnly = true; return this; }
        public bool At(string point) { return (" " + Point + " ").IndexOf(" " + point + " ", StringComparison.Ordinal) >= 0; }
    }

    public sealed class SimPointDef
    {
        public string Name, Progs;              // Progs: ' '-joined programs the point belongs to
        public int MinLevel;                    // the lowest difficulty that may use it
        public double Shift;                    // added to the edge (s): a pick AFTER the edge (EI + 60 s ...) has a positive shift
        public string[] Cands;                  // "code@targets" ('/'-joined targets; "*" = the code's own list now)
        public SimPointDef(string n, string p, int lv, double sh, params string[] c) { Name = n; Progs = p; MinLevel = lv; Shift = sh; Cands = c; }
    }

    public sealed class SimSup
    {
        // ---------------------------------------------------------------- difficulty (1 EASY, 2 NORMAL, 3 HARD, 4 BRUTAL)
        public const int Easy = 1, Normal = 2, Hard = 3, Brutal = 4;
        // BRUTAL:
        // a code that can be either goes permanent 75 % of the time (50 % below), and a permanent SW 01 / SW 02 may hit ASCENT / ENTRY guidance (below BRUTAL it never does)
        public const double BrutalPermShare = 0.75;
        // NoPilot (a permanent SW 01 AUTO DAP LOST ASCENT with nobody on the stick climbs straight up, the
        // RTLS guidance has no trajectory to work on): the host sets it from SailBus.On (KalsAddon.Fail.cs) while the automated test flight has the vessel, which has no pilot.
        // A permanent SW 01 / SW 02 is manual flight (the stick flies it); with no pilot it leaves no landing, so it is refused (the pick goes transient).
        public static bool NoPilot = false;
        // A permanent FCS 01 FROZEN SURFACE seldom lands (in the automated test flights 3 of 27 reached the runway, and every abort arrival with one but one sank):
        // NoCodes = failure codes the host never wants drawn (static like NoPilot; SIMNOCODE sets it, "" clears; the clean-flight tickets: FL_SIMNOCODE "FCS 01"). Check refuses them
        // for every pick, scripted, backbone or manual alike. AbortArr (set by ChkI from the flight's own outcome) = the flight is an ABORT ARRIVAL (a drawn / forced RTLS, TAL, ATO,
        // AOA, GREEN, BLUE or splits outcome): GUARD A below refuses a PERMANENT FCS 01 there while NoPilot (automated test flight); nominal-entry flights, pilot flights and transient picks keep theirs.
        public static readonly HashSet<string> NoCodes = new HashSet<string>();
        public static bool AbortArr = false;
        // A frozen RUDDER half (FCS 01
        // RUDDER L / RUDDER R: the split rudder IS the speedbrake) takes the speedbrake away. NO PILOT never draws one (Check refuses a permanent one on ANY flight, nominal entries too;
        // FCS 01 is the only code that touches the speedbrake); a flight WITH a pilot draws it only on BRUTAL (RudderOk), and when an FCS 01
        // surface is drawn there the two halves together take RudderShare (5 %) of the weight, the other five surfaces share the rest (every draw: random, point, scenario, chain).
        // The crew's own manual pick (the FAILURES window, Check at HARD+) is not a draw: below BRUTAL it stays open to a pilot.
        public const double RudderShare = 0.05;
        public static bool RudderOk(int level) { return !NoPilot && level >= Brutal; }
        // Temporary freezes are fair game: the rule is for a PERMANENT freeze (FCS 01 is permanent-only in the catalog today: a transient one, if it ever exists, keeps every draw)
        public static bool RudderRule(string code) { return code == "FCS 01" && ModesOf(code).IndexOf('P') >= 0; }
        public static bool IsRudder(string target) { return target == "RUDDER L" || target == "RUDDER R"; }
        static bool RudderOnly(string spec) { if (spec.Length == 0) return false; foreach (string t in spec.Split('/')) if (!IsRudder(t)) return false; return true; }
        // A draw among targets with the rudder halves together at RudderShare (one Draw, like Pick); only when both kinds are present
        static string PickRudderW(string[] a, double u)
        {
            var r = new List<string>(); var o = new List<string>();
            foreach (string t in a) { if (IsRudder(t)) r.Add(t); else o.Add(t); }
            if (r.Count == 0 || o.Count == 0) return Pick(a, u);
            return u < RudderShare ? Pick(r.ToArray(), u / RudderShare) : Pick(o.ToArray(), (u - RudderShare) / (1.0 - RudderShare));
        }
        // A permanent SW 02 (GUIDANCE LOST) is wanted in about 15-25 % of BRUTAL flights: a pure function of the seed, so the
        // same flight always decides the same; only those flights may lose the guidance of a phase for good (SW 01 AUTO DAP LOST is not limited)
        public static readonly double[] Sw02PermPhase = { 0.21, 0.15, 0.24 };       // per PHASE
        static int Sw02PhaseOf(string tg) { return tg == "ASCENT" ? PhAscent : (tg == "ORBIT BURN" ? PhOrbit : PhEntry); }
        static bool Sw02PermStanding(FailState s, int ph) { foreach (FailEntry e in s.List) if (e.Code == "SW 02" && e.Mode == "P" && Sw02PhaseOf(e.Target) == ph) return true; return false; }       // at most one permanent GUIDANCE LOST per phase
        public static bool Sw02PermOf(long seed, int ph) { return U(seed ^ (0x5DEECE66DL * (ph + 1)), 60221 + ph) < Sw02PermPhase[ph]; }
        public const double BrutalTransientW = 0.3, BrutalPermW = 1.5;       // BRUTAL's draw weights of the transient-only codes (DPS 02, SW 03 ...) and of the codes that can go permanent
        public static readonly string[] LevelName = { "", "EASY", "NORMAL", "HARD", "BRUTAL" };
        // THE FAILURE COUNT IS PER PHASE: ASCENT = OPS1, ORBIT = OPS2, ENTRY = OPS3 / OPS6
        // (an RTLS / TAL flight has no orbit phase). Each phase draws its own budget from the seed in [BudLo, BudHi] (BudgetOf: a pure
        // function of (seed, level, phase), nothing saved); BRUTAL has no count cap (NoCap), only the limits below (the slot clock, Unresolved,
        // the burn's quiet time, the double-up) and the survivable floors stop it. An unfired pick does not carry into the next phase.
        public const int PhAscent = 0, PhOrbit = 1, PhEntry = 2;
        public const int NoCap = 99;
        // BRUTAL's random clock is a SLOT
        // CLOCK. The phase's random-clock time (PhaseT) is cut into slots of BrutalSlot[phase] s and each slot holds ONE random try at a random moment inside it
        // (the old catch-up was a Poisson stream at 0.1 / s: clumps and gaps). So the tries are even on average (gap = slot x (1 + u' - u), 0 .. 2 slots) and
        // random, and a pair a few seconds apart still happens (the late try of one slot next to the early try of the next). The slots are s of the pick clock:
        // game s in the ascent / orbit, VIRTUAL s in the entry (see VClock), so the entry slots follow the blended clock. First values, the project owner tunes them.
        public static readonly double[] BrutalSlot = { 30, 150, 40 };
        public const int BrutalBacklog = 2;        // a slot's try is skipped while this many picks (the backbone's apart) are DUE and still wait: a refused / unresolved crew cannot pile them up
        // While NoPilot (the automated test flight: nobody restarts a software row inside 10 s), two BRUTAL picks are never closer than NoPilotGap (no double-up draw either).
        // The gap is NOT a
        // constant any more: each pick draws its own, NoPilotGap + NoPilotSpan x u^2 (15 .. 75 s, mean 35 s, a quarter of the picks inside 30 s), once, on its first Workload. A pick
        // waiting behind the last fire still fires at its own gap, so the spacing stays random even when picks queue.
        public const double NoPilotGap = 15, NoPilotSpan = 60;
        public static double NoPilotGapOf(double u) { return NoPilotGap + NoPilotSpan * u * u; }
        static readonly int[] BudLo = { 0, 1, 3, 5, NoCap }, BudHi = { 0, 2, 4, 6, NoCap };
        // the s of random-clock time (a host's randOk: liftoff .. MECO, a burn in orbit, the whole entry) the catch-up spreads a phase's
        // missing picks over (Pace): the planner reaches its budget even when the decision points were not used
        static readonly double[] PhaseSpan = { 420, 5400, 1400 };
        static readonly double[] LeadLo = { 0, 60, 30, 10, 5 }, LeadHi = { 0, 120, 60, 30, 15 };
        static readonly double[] ChainP = { 0, 0, 0.25, 0.50, 0.75 };
        static readonly double[] ChainLo = { 0, 0, 60, 30, 15 }, ChainHi = { 0, 0, 120, 60, 30 };
        static readonly double[] RandFrac = { 0, 0.10, 0.25, 0.40, 0.50 };     // random-time picks: a fraction of RAND x1
        static readonly double[] PointP = { 0, 0.50, 0.60, 0.70, 0.80 };      // the chance a decision point is used (was 0.25 .. 0.70: a phase has few points)
        static readonly int[] Unresolved = { 0, 1, 2, 3, 4 };
        static readonly double[] Spacing = { 0, 120, 60, 30, 0 };              // s between two SimSup failures (BRUTAL: none)
        // THE DOUBLE-UP (HARD / BRUTAL: SimSup may double up failures on harder
        // difficulties, failing two things in a short span): inside the spacing, a pick may still fire when it is within DoubleWin s
        // of the last fire, with the seeded chance DoubleP (drawn ONCE per pick, stored on it); never a triple (DblOpen). EASY and
        // NORMAL have no double-up and draw nothing. NOTE: BRUTAL's spacing (15 s) is shorter than its window (30 s), so there the
        // spacing bounds the double-up window: a BRUTAL double-up is a pick within 15 s of the last.
        static readonly double[] DoubleWin = { 0, 0, 0, 20, 30 };
        static readonly double[] DoubleP = { 0, 0, 0, 0.35, 0.60 };
        // ORBIT: the minimum gap between two
        // SimSup failures in the orbit phase is OrbitGap x the level's Spacing (BRUTAL has none: its slot clock spaces them); the orbit's random clock runs on GAME time over the
        // whole phase (PhaseSpan 5400 s), not only inside a burn; the OMS codes are NEVER drawn on the random clock: they are picked at the burns'
        // decision points (OMS1_TIG / OMS2_TIG / BURN_TIG / DEORBIT_TIG) and land at the burn's TIG - lead (before) or TIG + OrbitInLo .. + OrbitInHi (inside)
        public const double OrbitGap = 3, OrbitInLo = 25, OrbitInHi = 65;
        static readonly double[] Settle = { 0, 120, 90, 60, 45 };              // s a PERMANENT failure counts as unresolved
        public const double BurnQuiet = 20;                                    // no SimSup failure within this of a burn's ignition
        public const double NoTig = -1000000;                                  // lib_fail FL_NOTIG
        public const double PickLife = 600;                                    // s a due pick may wait (workload) before it is dropped

        public static int Clamp(int lv) { return lv < Easy ? Normal : (lv > Brutal ? Brutal : lv); }
        // ---------------------------------------------------------------- SCENARIOS
        // "Let's give each scenario a 20% chance of firing IF a failure is going to happen. So 20% scenario 80% random fail." / "Count inside, no debrief."
        // At every failure pick (a decision point used, a random-clock pick, the backbone's engine out) the planner rolls ONCE: ScenarioShare = a SCENARIO (one drawn from
        // the scenarios eligible at that point / phase / level, Templates below), else today's single random failure. No eligible scenario, or one a floor would refuse
        // = the random failure, so the failure count is unchanged. A scenario COUNTS INSIDE the phase's budget (each step = one failure of that phase; one that would
        // overrun the room left does not start; BRUTAL has no cap) and starts at most once a flight. Its steps keep their script's times: no burn quiet time, no spacing,
        // no unresolved cap (the floors in Check still decide each step; the automated test flight's no-pilot gap stays). No debrief line.
        public const double ScenarioShare = 0.20;
        // Check options a scenario step may carry (the scripted exceptions; each is named in the report):
        public const int OptSamePart = 1;      // an escalation of a part already failed in the script (DPS 02 then DPS 01 on one GPC, a thin RCS pair): the part rule is skipped
        public const int OptSwPerm = 2;        // a scripted PERMANENT SW 01 / SW 02 (BLIND MECO) at HARD+ even on the ASCENT / ENTRY target (a NO PILOT flight still refuses it)
        public const int OptGimbalCtl = 4;     // MPS 03 (a locked gimbal) costs control, not thrust: it does not count against the thrust account (COMPOUND OUT)
        public const int OptPair = 8;          // the scripted pair at EASY / NORMAL: a second OMS engine degraded (TIRED PAIR), a second aft RCS failure (THIN AFT)
        public const int OptPilotOnly = 32;    // A scripted step that exists only on a flight WITH a pilot (a NO PILOT flight drops it: Active), the landing-window losses the project owner allows a human
        public const int OptThird = 16;        // The backbone's THIRD SSME out of a 3EO outcome (Check: the floor lets it through with landOk)
        // ---------------------------------------------------------------- THE OUTCOME BACKBONE
        // The seed decides the WHOLE ascent outcome up front (OutcomeOf, a pure function, nothing saved): ORBIT (nominal or ATO) with
        // OrbitP by level, else one abort mode from AbortMix. The planner then fires the engine out(s) INSIDE the window that makes
        // that mode the one left open (the marks the host feeds as decision points: ABORT_TAL = TAL opens, ABORT_ATO = ATO opens,
        // ABORT_RTLS = RTLS closes (negative return), GREEN_2EO / GREEN_2EO_END = the 2EO GREEN window). The per-phase counts are the
        // OTHER failures (the spice): they never include an SSME (MPS) code in ascent, so they can never change the drawn outcome.
        // Force (ForceAbort) overrides the draw: SimSup.Force = an Oc* value (-1 = the draw). A second SSME out is the ONE floor
        // exception (Check landOk): allowed when the flight can still end in a landing, which the planner states by planning it in a 2EO window (TAL_2EO / GREEN).
        // The backbone covers EVERY ascent mode ops1q flies. His exception to "fair game if landable": BLUE
        // (no ELS runway in reach = the bailout) is a drawn outcome now, a small share. The modes the ladder flies by the engines out and when:
        //   stage 1 (before the SRB sep): a 2nd / 3rd SSME out = SPLITS (2EO SPLITS, 3EO SPLITS); stage 2: 2EO TAL / ATO / PRESS (1EO line) or the contingency GREEN / BLUE;
        //   3EO = ATO (VI >= 3500), TAL (VI >= 2750, KSC only), GREEN (the 3EO footprint), BLUE, RTLS 3EO (GREEN in the pitchdown, else BLUE).
        // The backbone plans the engine out TIMES; the mode the ladder then flies is the flight's own (an FC item per new mode: SimForce(name) flies it at will).
        public const int OcOrbit = 0, OcRtls = 1, OcTal1 = 2, OcTal2 = 3, OcAoa = 4, OcGreen = 5,
                         OcBlue2 = 6, OcBlue3 = 7, OcGreen3 = 8, OcTal3 = 9, OcAto3 = 10, OcRtls3 = 11, OcSplit3 = 12, OcSplit2 = 13,
                         OcRtls2G = 14, OcRtls2B = 15;
        public static readonly string[] OcName = { "ORBIT", "RTLS", "1EO TAL", "2EO TAL", "AOA", "2EO GREEN",
                                                   "2EO BLUE", "3EO BLUE", "3EO GREEN", "3EO TAL", "3EO ATO", "3EO RTLS", "3EO SPLITS", "2EO SPLITS",
                                                   "RTLS 2EO GREEN", "RTLS 2EO BLUE" };
        static readonly double[] OrbitP = { 0, 0.80, 0.70, 0.50, 0.35 };
        // THE ABORT MIX, in percent of the flights that are not ORBIT. THE OWNER TWEAKS THESE (index = Oc*, index 0 unused; only the ratios count: the sum need not be 100).
        // The old five x 0.9 (RTLS 33 / 1EO TAL 25 / 2EO TAL 12 / AOA 10 / 2EO GREEN 20), the new 10 %: 2EO BLUE 3, 3EO BLUE 2, the landable 3EO modes 1 each (5), 2EO SPLITS off.
        public static readonly double[] AbortMix = { 0,
            29.7,    // RTLS
            22.5,    // 1EO TAL
            10.8,    // 2EO TAL
            9.0,     // AOA
            18.0,    // 2EO GREEN
            3.0,     // 2EO BLUE
            2.0,     // 3EO BLUE
            1.0,     // 3EO GREEN
            1.0,     // 3EO TAL
            1.0,     // 3EO ATO
            1.0,     // 3EO RTLS
            1.0,     // 3EO SPLITS
            0.0,     // 2EO SPLITS (a stage-1 second out; in no spec: off until the project owner turns it on)
            0.0,     // RTLS 2EO GREEN (never drawn on its own: a SPLIT of 2EO GREEN, Rtls2Share)
            0.0 };   // RTLS 2EO BLUE (the same, a split of 2EO BLUE)
        // The 2EO GREEN and 2EO BLUE outcomes each have an RTLS variant (OcRtls2G / OcRtls2B): out 1 before TAL opens (as OcRtls: the abort the 1EO auto picks is the RTLS),
        // out 2 INSIDE the RTLS while the RTLS 2EO line is the variant's colour (ops1q feeds the real crossings, RTLS_2EO_GREEN / RTLS_2EO_BLUE). The percentages above stay: the variants are drawn
        // out of their parent's share, Rtls2Share of it (THE OWNER TWEAKS IT: 0 = the classic 2EOs only, 1 = every 2EO GREEN / BLUE flight is an RTLS one). The plain RTLS (29.7) stays a 1EO RTLS.
        // The classic fallback: a variant is drawn only when the host's SIMREACH lists its name (ops1q lists them; an older host, or a flight with no RTLS, draws the classic 2EO).
        public static double Rtls2Share = 0.5;
        // The draw is 2..8 s, NOT 2..10, because the
        // host's own latency lands on top of it: a kOS tick at the test-run warp (~3.6x) is ~0.3-0.5 s of game time, the offer -> answer -> SSME shutdown path another tick or two, and ops1q feeds a mark at the first
        // asc_simPts tick AFTER asc_rtls_step set the word (0.1-1.7 s late). 8 + <= 2 s of latency stays <= 10 s.
        public const double Rtls2Off1 = 2, Rtls2Off2 = 8;       // s: out 2 after the RTLS colour mark (the host adds its tick / feed latency, <= 10 s in all)
        public const int ReachAll = (1 << 16) - 1;                                      // bit k = outcome k may be drawn (the host narrows it)

        public static int OutcomeOf(long seed, int lv, int reach = ReachAll)
        {
            lv = Clamp(lv);
            long sd = seed ^ 0x3C6EF372FE94F82BL;
            if (U(sd, 31337) < OrbitP[lv]) return OcOrbit;
            double tot = 0;
            for (int k = 1; k < OcName.Length; k++) if ((reach & (1 << k)) != 0) tot += AbortMix[k];
            if (tot <= 0) return OcOrbit;                                               // nothing reachable: the nominal ascent
            double x = U(sd, 31338) * tot;
            int last = OcOrbit;
            for (int k = 1; k < OcName.Length; k++)
            {
                if ((reach & (1 << k)) == 0 || AbortMix[k] <= 0) continue;
                last = k;
                x -= AbortMix[k];
                if (x < 0) return Rtls2Variant(sd, k, reach);
            }
            return Rtls2Variant(sd, last, reach);
        }
        // A 2EO GREEN / 2EO BLUE draw becomes its RTLS variant with Rtls2Share (a pure function of the seed, its own stream), when the host's reach has the variant's name
        static int Rtls2Variant(long sd, int oc, int reach)
        {
            int v = oc == OcGreen ? OcRtls2G : (oc == OcBlue2 ? OcRtls2B : -1);
            if (v < 0 || (reach & (1 << v)) == 0 || Rtls2Share <= 0) return oc;
            return U(sd, 31339) < Rtls2Share ? v : oc;
        }
        // the SSMEs the outcome takes out (the Check's floor: a 2nd only on a 2EO / 3EO outcome, a 3rd only on a 3EO one)
        public static int EoOf(int oc)
        {
            switch (oc)
            {
                case OcOrbit: return 0;
                case OcTal2: case OcGreen: case OcBlue2: case OcSplit2: case OcRtls2G: case OcRtls2B: return 2;
                case OcBlue3: case OcGreen3: case OcTal3: case OcAto3: case OcRtls3: case OcSplit3: return 3;
                default: return 1;
            }
        }
        public static bool Is2eo(int oc) { return EoOf(oc) == 2; }

        public static int PhaseOf(string prog) { return prog == "OPS1" ? PhAscent : (prog == "OPS2" ? PhOrbit : PhEntry); }
        public static string PhaseName(int ph) { return ph == PhAscent ? "ASCENT" : (ph == PhOrbit ? "ORBIT" : "ENTRY"); }
        // the phase's budget for this seed + level (a pure function: the same flight always draws the same numbers)
        public static int BudgetOf(long seed, int lv, int ph)
        {
            lv = Clamp(lv);
            if (lv >= Brutal) return NoCap;
            int n = BudHi[lv] - BudLo[lv] + 1;
            int k = (int)(U(seed ^ (0x2545F4914F6CDD1DL * (ph + 1)), 7919 + ph) * n);
            return BudLo[lv] + (k >= n ? n - 1 : k);
        }
        public int Budget(FailState s) { return BudgetOf(s.SeedHash, s.Difficulty, Ph); }
        public int Ph { get { return PhaseOf(Prog); } }
        public int PhasePicked { get { return PickedPh[Ph]; } }
        // the pace of the catch-up: picks per s of random-clock time the phase still needs (BRUTAL has no catch-up: its slot clock)
        double Pace(FailState s, int lv)
        {
            return Math.Max(0, Room(s)) / Math.Max(30.0, PhaseSpan[Ph] - PhaseT[Ph]);
        }

        // ---------------------------------------------------------------- the catalog's targets / values (lib_fail.ks FL_CAT)
        static readonly string[] Ssme = { "L", "C", "R" }, Oms = { "L", "R" }, Gpc = { "G1", "G2", "G3", "G4", "G5" }, GpcPass = { "G1", "G2", "G3", "G4" }, SplitTg = { "2-2" }, PassAllTg = { "G1-G4" };   // DPS 03 / DPS 06 take a PASS GPC only (the BFS is not in the redundant set)
        // The real RCS groups: pods F (forward) / L / R (aft, port / starboard), manifolds 1-4 (no verniers: the model has none); RCS 04 names a jet (pod + manifold + direction)
        static readonly string[] Rcs1 = { "F ALL", "L ALL", "R ALL", "F MANIFOLD 1", "F MANIFOLD 2", "F MANIFOLD 3", "F MANIFOLD 4", "L MANIFOLD 1", "L MANIFOLD 2", "L MANIFOLD 3", "L MANIFOLD 4", "R MANIFOLD 1", "R MANIFOLD 2", "R MANIFOLD 3", "R MANIFOLD 4" },
            Rcs2 = { "F ALL", "L ALL", "R ALL" }, Rcs3 = { "F", "L", "R" };
        // OMS 04's tank(s) and RCS 04's JET NAMES (the real names, RcsMap.cs: pod + manifold + exhaust direction; the manifolds are dealt per pod, so the first fore jets of the forward pod are F1F .. F4F and the first aft jets of an aft pod L1A, L2A / R1A, R2A; a name the ship lacks is refused by the host)
        static readonly string[] OmsLeak = { "FU", "OX", "BOTH" };
        // RCS 04 picks only jets the vessel HAS. The map is dealt (RcsMap.Deal: per pod, direction by direction, one running count), so the forward pod of the orbiter has
        // THREE fore jets F1F F2F F3F (no F4F: the vessel has no such jet). JetCand = the fore / aft jets SimSup draws from;
        // JetNames = the host's real map (KalsAddon.Fail.cs SimTick, null = not known yet): a candidate the map lacks is never drawn; a map that has none of them hands out its own names.
        static readonly string[] JetCand = { "F1F", "F2F", "F3F", "L1A", "L2A", "R1A", "R2A" };
        public static string[] JetNames = null;
        public static string[] Jets()
        {
            string[] m = JetNames;
            if (m == null) return JetCand;
            var o = new List<string>();
            foreach (string c in JetCand) if (Array.IndexOf(m, c) >= 0) o.Add(c);
            return o.Count > 0 ? o.ToArray() : m;
        }
        static readonly string[] Surf = { "ELEVON 1", "ELEVON 2", "ELEVON 3", "ELEVON 4", "BODY FLAP", "RUDDER L", "RUDDER R" };

        public static string Scope(string prog)
        {
            if (prog == "OPS1") return "ASCENT";
            if (prog == "OPS2") return "ORBIT";
            return "ENTRY";
        }

        // the targets a code may take NOW in this program (phase = the host's guidance phase for SW 02); empty = not pickable
        public static string[] Targets(string prog, string code, string phase)
        {
            switch (code)
            {
                case "MPS 01": case "MPS 02": case "MPS 03": return prog == "OPS1" ? Ssme : new string[0];
                case "OMS 01": case "OMS 02": case "OMS 03": return prog == "OPS2" ? Oms : new string[0];
                case "RCS 01": return prog == "OPS1" ? new string[0] : Rcs1;
                case "RCS 02": return prog == "OPS1" ? new string[0] : Rcs2;
                case "OMS 04": return prog == "OPS2" ? OmsLeak : new string[0];                   // The OMS tanks only leak in the orbit program
                case "RCS 03": return prog == "OPS1" ? new string[0] : Rcs3;
                case "RCS 04": return prog == "OPS1" ? new string[0] : Jets();
                case "FCS 01": return prog == "OPS3" || prog == "OPS6" ? Surf : new string[0];
                case "DPS 01": case "DPS 02": return Gpc;
                case "DPS 03": case "DPS 06": return GpcPass;       // DPS 03 FAIL TO SYNC, DPS 06 OUTPUT BAD
                case "DPS 04": return prog == "OPS2" ? new string[0] : SplitTg;       // REDUNDANT SET SPLIT 2-2 (ascent / entry only: orbit runs 2 GNC + 1 SM GPCs, no 4-GPC PASS set)
                case "DPS 05": return prog == "OPS2" ? new string[0] : PassAllTg;     // PASS GENERIC SOFTWARE FAIL (all four PASS GPCs; the BFS flies)
                case "SW 01": return new string[] { Scope(prog) };
                case "SW 02":
                    if (prog == "OPS1") return new string[] { "ASCENT" };
                    if (prog == "OPS2") return new string[0];     // No SW 02 in orbit (ORBIT BURN is not a failure target for v1.0)
                    return new string[] { phase == "TAEM" || phase == "A/L" ? phase : "ENTRY" };
                case "SW 03": return new string[] { "PAGE" };
            }
            return new string[0];                    // FCS 02, PDR 01, SW 04 / 05 are not in the catalog any more (no handler); every other catalog code is above
        }

        public static string[] Values(string code)
        {
            switch (code)
            {
                case "MPS 02": return new string[] { "60 %", "75 %" };
                case "OMS 02": return new string[] { "70 %", "85 %" };
                case "RCS 02": return new string[] { "50 %", "75 %" };
                case "SW 03": return new string[] { "FROZEN", "BLANK" };
                case "OMS 04": return new string[] { "0.05 KG/S", "0.2 KG/S" };
                case "RCS 03": return new string[] { "1 %/MIN", "5 %/MIN" };
                case "RCS 04": return new string[] { "STUCK OFF", "STUCK ON" };                  // The leak is RCS 03's
            }
            return new string[] { "" };
        }

        // the stated WORKAROUND of each pickable code (plan section 6: every picked line has one); a code without one is never picked
        public static readonly Dictionary<string, string> Workaround = new Dictionary<string, string>
        {
            { "MPS 01", "ABORT MODE ON THE ENGINES LEFT" }, { "MPS 02", "PRESS / ABORT ON THE LOW THRUST" }, { "MPS 03", "THE OTHER GIMBALS STEER" },
            { "OMS 01", "THE OTHER OMS ENGINE / RCS BURN" }, { "OMS 02", "LONGER BURN / THE OTHER ENGINE" }, { "OMS 03", "THE OTHER GIMBAL / RCS STEERS" },
            { "RCS 01", "MANIFOLD RE-OPEN / THE OTHER POD" }, { "RCS 02", "THE OTHER JETS / LONGER FIRINGS" }, { "FCS 01", "THE OTHER SURFACES TRIM" },
            { "DPS 01", "RE-ASSIGN THE DISPLAY / SPARE" }, { "DPS 02", "RESTART THE GPC" },
            { "DPS 03", "HALT THE GPC, RE-ASSIGN THE DISPLAY / RESTART" }, { "DPS 06", "THE OTHER GPCS VOTE IT OUT, RE-ASSIGN / RESTART" }, { "DPS 04", "PICK THE GOOD PAIR / BFS ENGAGE" }, { "DPS 05", "BFS ENGAGE" },  { "SW 01", "CSS (MANUAL) / RESTART SW" },      // DPS 03 / DPS 06
            { "SW 02", "RAW-DATA FLYING / RESTART SW" }, { "SW 03", "RE-SELECT THE PAGE" },
            { "OMS 04", "ISOLATE THE TANK / BURN ON THE OTHER" }, { "RCS 03", "MANIFOLD CLOSE / THE OTHER POD" }, { "RCS 04", "MANIFOLD CLOSE / DESELECT THE JET" },
        };

        // the CATALOG's modes (Fail.cs FailState.Table)
        static string ModesOf(string code) { FailCode fc = FailState.Find(code); return fc == null ? "" : fc.Modes; }

        // ---------------------------------------------------------------- RAND's hazard table: % per second per target at x1
        // (project owner 00:31 / 00:32: every failure item, no floors). ops1q draws liftoff .. MECO, ops2q in a burn, ops3q / ops6q the
        // whole program (the hosts' randOk). MPS 01 0.08 and OMS 01 0.05 are today's lib_fail FL_HAZ.
        public static double Hazard(string prog, string code)
        {
            if (prog == "OPS1")
                switch (code)
                {
                    case "MPS 01": return 0.08; case "MPS 02": return 0.02; case "MPS 03": return 0.01;
                    case "DPS 01": return 0.005; case "DPS 02": return 0.01; case "DPS 03": return 0.004; case "DPS 06": return 0.003; case "DPS 04": return 0.012; case "DPS 05": return 0.003;      // HARD+ / BRUTAL by Check
                    case "SW 01": return 0.005; case "SW 02": return 0.005; case "SW 03": return 0.01;
                }
            else if (prog == "OPS2")
                switch (code)
                {
                    case "OMS 01": return 0.05; case "OMS 02": return 0.03; case "OMS 03": return 0.03;
                    case "RCS 01": return 0.003; case "RCS 02": return 0.007;                                  // Per target, the old 0.01 spread over the 15 / 3 targets now
                    case "OMS 04": return 0.01; case "RCS 03": return 0.003; case "RCS 04": return 0.002;      // Per target; RCS 04 has 8 jet names
                    case "DPS 01": return 0.005; case "DPS 02": return 0.01; case "DPS 03": return 0.004; case "DPS 06": return 0.003;
                    case "SW 01": return 0.005; case "SW 02": return 0.01; case "SW 03": return 0.01;
                }
            else if (prog == "OPS3" || prog == "OPS6")
                switch (code)
                {
                    case "RCS 01": return 0.0008; case "RCS 02": return 0.0015; case "FCS 01": return 0.002;
                    case "RCS 03": return 0.0007; case "RCS 04": return 0.0005;
                    case "DPS 01": return 0.001; case "DPS 02": return 0.002; case "DPS 03": return 0.0008; case "DPS 06": return 0.0006; case "DPS 04": return 0.004; case "DPS 05": return 0.0008;
                    case "SW 01": return 0.001; case "SW 02": return 0.002; case "SW 03": return 0.003;
                }
            return 0;
        }

        // ---------------------------------------------------------------- decision points (the hosts call slPoint(name, edgeUt))
        public static readonly SimPointDef[] Points = new SimPointDef[]
        {
            new SimPointDef("ABORT_RTLS", "OPS1", Easy, 0, "MPS 01@*", "MPS 02@*", "MPS 03@*"),
            new SimPointDef("ABORT_TAL",  "OPS1", Easy, 0, "MPS 01@*", "MPS 02@*", "MPS 03@*"),
            new SimPointDef("ABORT_ATO",  "OPS1", Easy, 0, "MPS 01@*", "MPS 02@*"),
            new SimPointDef("MECO",       "OPS1", Easy, 0, "MPS 02@*", "MPS 03@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*"),
            new SimPointDef("OMS1_TIG",   "OPS1 OPS2", Normal, 0, "OMS 01@*", "OMS 02@*", "OMS 03@*", "RCS 02@*", "OMS 04@FU/OX"),
            new SimPointDef("OMS2_TIG",   "OPS1 OPS2", Easy, 0, "OMS 01@*", "OMS 02@*", "OMS 03@*", "RCS 01@F MANIFOLD 1/L MANIFOLD 1/R MANIFOLD 1", "RCS 02@*", "OMS 04@FU/OX"),
            new SimPointDef("BURN_TIG",   "OPS2", Easy, 0, "OMS 01@*", "OMS 02@*", "OMS 03@*", "RCS 01@F MANIFOLD 1/L MANIFOLD 1/R MANIFOLD 1", "RCS 02@*", "SW 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "SW 03@*", "OMS 04@FU/OX", "RCS 03@*", "RCS 04@*"),
            new SimPointDef("DEORBIT_TIG","OPS2", Easy, 0, "OMS 01@*", "OMS 02@*", "OMS 03@*", "RCS 01@F MANIFOLD 1/L MANIFOLD 1/R MANIFOLD 1", "RCS 02@*", "SW 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "SW 03@*", "OMS 04@FU/OX", "RCS 03@*", "RCS 04@*"),
            new SimPointDef("EI",         "OPS3 OPS6", Easy, 60, "RCS 01@F MANIFOLD 1/L MANIFOLD 1/R MANIFOLD 1/F ALL", "RCS 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 01@*", "SW 02@*", "SW 03@*", "RCS 03@*", "RCS 04@*"),
            new SimPointDef("ROLL_REV",   "OPS3 OPS6", Normal, 0, "RCS 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "FCS 01@ELEVON 1/ELEVON 2/ELEVON 3/ELEVON 4", "SW 03@*"),
            new SimPointDef("TAEM",       "OPS3 OPS6", Easy, 0, "FCS 01@*", "SW 02@*", "DPS 01@G1/G2/G3/G4", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*"),
            new SimPointDef("HAC",        "OPS3 OPS6", Normal, 0, "SW 01@*", "SW 02@*", "FCS 01@BODY FLAP/RUDDER L/RUDDER R"),
            new SimPointDef("PREFLARE",   "OPS3 OPS6", Hard, 0, "SW 02@*", "FCS 01@BODY FLAP"),
            // The design's "quiet period from mid-ascent to mid-entry" + the scenarios' anchors: fed by the hosts (lib_failui fuiSimPt / fuiSimWatch / fuiSimBank, ops1q, ops6q)
            new SimPointDef("PPA",        "OPS1", Easy, 0, "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*"),                                // RTLS powered pitch-around starts (ops1q)
            new SimPointDef("ET_SEP",     "OPS1", Normal, 20, "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*"),                             // the ET separation (ops1q)
            new SimPointDef("GUID_INIT",  "OPS6", Easy, 0, "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*", "RCS 02@*"),                    // OPS 6 guidance initiate (ops6q)
            new SimPointDef("COAST",      "OPS6", Normal, 20, "RCS 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*", "RCS 01@F MANIFOLD 1/L MANIFOLD 1/R MANIFOLD 1"),       // the entry programs' coast starts (fuiSimWatch)
            new SimPointDef("ROLL_FIRST", "OPS3 OPS6", Normal, 20, "RCS 02@*", "DPS 02@G1/G2/G3/G4", "DPS 03@G1/G2/G3/G4", "DPS 06@G1/G2/G3/G4", "DPS 04@2-2", "DPS 05@G1-G4", "SW 03@*", "FCS 01@ELEVON 1/ELEVON 2/ELEVON 3/ELEVON 4"),   // the first bank command (fuiSimBank)
        };

        // ---------------------------------------------------------------- the SCRIPT LIBRARY (the first 10, then the SCENARIOS)
        // a template / scenario needs every step's code flyable when it starts (no scenario sleeps any more, THE SILENT SLIP / SW 04 is gone with the code)
        // Offsets are s of the pick clock from the anchor's edge (virtual s in the entry); "=k" / "~k" = the target step k drew / another; Sp(n) adds a seeded 0..n s;
        // Lv(n) = the step only at level n and up; Soft() = dropped, not fatal, when a floor refuses it; After(p) = waits for decision point p; Op(..) = Check options.
        // SINGLE-ENGINE PRESS is RETIRED.
        public static readonly SimTemplate[] Templates = new SimTemplate[]
        {
            new SimTemplate("OMS CASCADE", "DEORBIT_TIG", Hard, "THE OMS-TO-RCS FALLBACK GONE",           // was NORMAL; its both-aft-pods steps are a HARD+ floor (EASY / NORMAL refuse it), so below HARD it was a plain OMS out
                new SimStep(-30, "OMS 01", "L/R", "", "P"), new SimStep(90, "RCS 01", "L ALL", "", "T"), new SimStep(90, "RCS 01", "R ALL", "", "T")),      // AFT ALL = both aft pods
            new SimTemplate("THE LONG LEAK", "BURN_TIG", Normal, "THE OPRP CHECK, THEN THE ENGINE",
                new SimStep(-300, "OMS 04", "FU/OX", "0.05 KG/S", "P"), new SimStep(0, "OMS 01", "L/R", "", "P")),
            new SimTemplate("DEAD DISPLAY", "DEORBIT_TIG", Easy, "RE-ASSIGN THE GNC DISPLAY",
                new SimStep(-600, "DPS 01", "G1", "", "P")),
            new SimTemplate("THE HALF-BLIND ENTRY", "EI", Normal, "RAW-DATA FLYING, THEN A GPC",
                new SimStep(60, "SW 02", "ENTRY", "", "T"), new SimStep(180, "DPS 02", "G2", "", "T")),
            new SimTemplate("STUCK JET", "BURN_TIG", Normal, "DESELECT A JET FAILED ON",
                new SimStep(-30, "RCS 04", "*", "STUCK ON", "T")),
            new SimTemplate("DOUBLE VOTE", "EI", Hard, "TWO GPCS DOWN, THE DISPLAYS MOVED",
                new SimStep(120, "DPS 02", "G1", "", "T"), new SimStep(240, "DPS 01", "G2", "", "P")),
            new SimTemplate("FROZEN FLAP", "TAEM", Easy, "TRIM WITHOUT THE BODY FLAP",
                new SimStep(0, "FCS 01", "BODY FLAP", "", "P")),
            // AUTO LOST ON FINAL is back for a flight WITH a pilot (OptPilotOnly: a NO PILOT flight drops the step, so the scenario never starts there; the final-approach guard stays for the automated test flight)
            new SimTemplate("AUTO LOST ON FINAL", "HAC", Normal, "CSS TO TOUCHDOWN",
                new SimStep(0, "SW 01", "ENTRY", "", "T").Op(OptPilotOnly)),
            // ---- ASCENT (the SSME scenarios touch an engine only on a flight the backbone draws as ORBIT; DYING ENGINE / COMPOUND OUT dress the backbone's own out: DressBackbone)
            new SimTemplate("LOST IN THE FLYBACK", "PPA", Hard, "RTLS GUIDANCE LOST AT THE PITCH-AROUND",
                new SimStep(0, "SW 02", "ASCENT", "", "T")),
            new SimTemplate("SICK GPC ON THE CLIMB", "ABORT_TAL ABORT_ATO", Hard, "A GPC SICK, THEN DEAD, AT THE BOUNDARY",
                new SimStep(-30, "DPS 02", "G1/G2/G3/G4", "", "T"), new SimStep(30, "DPS 01", "=0", "", "P").Op(OptSamePart)),
            new SimTemplate("BLIND MECO", "MECO", Hard, "THE CREW CUTS OFF BY HAND",
                new SimStep(-30, "SW 02", "ASCENT", "", "P").Sp(10).Op(OptSwPerm)),
            new SimTemplate("THE BAD BOUNDARY", "ABORT_TAL ABORT_ATO", Normal, "A LOW ENGINE AT THE ABORT BOUNDARY",
                new SimStep(-20, "MPS 02", "L/C/R", "75 %", "P").Sp(10)).Orbit(),
            new SimTemplate("ATO SQUEEZE", "ABORT_ATO", Hard, "A LOW ENGINE JUST AFTER ATO OPENS",
                new SimStep(30, "MPS 02", "L/C/R", "75 %", "P")).Orbit(),
            // ---- ORBIT
            new SimTemplate("TIRED PAIR", "BURN_TIG", Normal, "ONE ENGINE LOW, THE OTHER ENGINE GIMBAL LOCKED",
                new SimStep(-60, "OMS 02", "L/R", "70 %", "P").Op(OptPair), new SimStep(0, "OMS 03", "~0", "", "P").Op(OptPair)),
            new SimTemplate("GIMBAL AT TIG", "OMS1_TIG OMS2_TIG BURN_TIG DEORBIT_TIG", Easy, "A LOCKED GIMBAL JUST BEFORE THE BURN",
                new SimStep(-60, "OMS 03", "L/R", "", "P")),
            new SimTemplate("THE WRONG PAGE", "DEORBIT_TIG", Normal, "THE BURN PAGE FROZEN, THEN FROZEN AGAIN",
                new SimStep(-120, "SW 03", "PAGE", "FROZEN", "T"),
                new SimStep(-10, "SW 03", "PAGE", "FROZEN", "T").Lv(Hard).Soft()),
            new SimTemplate("GPC SHUFFLE", "DEORBIT_TIG", Hard, "A GPC RESTARTS, THEN ANOTHER, AT IGNITION",
                new SimStep(-20, "DPS 02", "G1/G2/G3/G4", "", "T"), new SimStep(0, "DPS 02", "~0", "", "T")),
            new SimTemplate("THE DRIP BEFORE DEORBIT", "DEORBIT_TIG", Hard, "AN OMS LEAK, ISOLATE THE TANK",
                new SimStep(-900, "OMS 04", "OX", "0.2 KG/S", "T")),
            new SimTemplate("LEAKY POD", "*", Normal, "A LEAKING POD, THEN A MODULE OFF",
                new SimStep(0, "RCS 03", "L", "5 %/MIN", "T").Op(OptPair), new SimStep(600, "RCS 01", "L MANIFOLD 3", "", "P").Op(OptPair | OptSamePart)).In("OPS2"),
            // ---- ENTRY
            new SimTemplate("THIN AFT", "EI", Normal, "THE AFT JETS THIN",
                new SimStep(60, "RCS 01", "L MANIFOLD 1", "", "P").Op(OptPair | OptSamePart), new SimStep(300, "RCS 02", "L ALL", "75 %", "P").Op(OptPair | OptSamePart)),
            new SimTemplate("HOT JET ON ENTRY", "EI", Hard, "DESELECT AN AFT JET FAILED ON",
                new SimStep(120, "RCS 04", "L1A/L2A/R1A/R2A", "STUCK ON", "T")),
            new SimTemplate("ALPHA FAIL", "EI", Normal, "THE ALPHA LOOP FAILS: PITCH TO CSS",
                new SimStep(90, "SW 02", "ALPHA MOD", "", "")),
            new SimTemplate("TAL TROUBLE", "GUID_INIT", Normal, "A GPC AND THE TRAJECTORY PAGE AT GUIDANCE INITIATE",
                new SimStep(0, "DPS 02", "G1/G2/G3/G4", "", "T"), new SimStep(4, "SW 03", "PAGE", "FROZEN", "T")),
            new SimTemplate("REVERSAL SURPRISE", "ROLL_REV", Hard, "THE DAP DROPS AS THE FIRST REVERSAL STARTS",
                new SimStep(0, "SW 01", "ENTRY", "", "T"), new SimStep(60, "FCS 01", "ELEVON 1/ELEVON 2/ELEVON 3/ELEVON 4", "", "P")).Revs(1),
            new SimTemplate("STIFF ELEVON", "ROLL_REV", Hard, "AN ELEVON STIFF, THEN A RUDDER AT TAEM",
                new SimStep(0, "FCS 01", "ELEVON 1/ELEVON 2/ELEVON 3/ELEVON 4", "", "P"), new SimStep(0, "FCS 01", "RUDDER L/RUDDER R", "", "P").After("TAEM")).Revs(1),
            new SimTemplate("LATE REVERSAL", "ROLL_REV", Hard, "GUIDANCE DROPS AT THE SECOND REVERSAL",
                new SimStep(0, "SW 02", "ENTRY", "", "T")).Revs(2),
            new SimTemplate("HANDOVER HAZE", "TAEM", Normal, "TAEM GUIDANCE DROPS, THE HORIZ SIT FREEZES",
                new SimStep(0, "SW 02", "TAEM", "", "T"), new SimStep(6, "SW 03", "PAGE", "FROZEN", "T")),
            new SimTemplate("SPEEDBRAKE HALF", "TAEM", Hard, "ONE RUDDER HALF FROZEN: UNEVEN DRAG, YAW TRIM",
                new SimStep(0, "FCS 01", "RUDDER L/RUDDER R", "", "P")),
            new SimTemplate("LATE SURPRISE", "PREFLARE", Hard, "THE BODY FLAP FROZEN, GUIDANCE GONE FOR GOOD",      // The permanent SW 02 step is back for a flight WITH a pilot only (OptPilotOnly); NO PILOT plays the body flap alone
                new SimStep(0, "FCS 01", "BODY FLAP", "", "P"), new SimStep(8, "SW 02", "*", "", "P").Op(OptSwPerm | OptPilotOnly)),
            // ---- ANYWHERE (a random-clock pick starts it; ascent, entry: the display scripts, ops2q has one display)
            new SimTemplate("DARK DECK", "*", Normal, "ONE DISPLAY GPC GONE, THE OTHER DISPLAY BLANK",
                new SimStep(0, "DPS 01", "G1/G2", "", "P"), new SimStep(3, "SW 03", "PAGE", "BLANK", "T")).In("OPS1 OPS3 OPS6"),
        };

        // ---------------------------------------------------------------- the BACKUP LISTS (chaining: what the crew falls back on)
        // "code@target" with "=" = the first failure's own target, "~" = another target of the same kind
        static string[] Backups(string code)
        {
            switch (code)
            {
                case "MPS 01": return new string[] { "MPS 02@~", "MPS 03@~" };
                case "MPS 02": case "MPS 03": return new string[] { "MPS 03@~", "MPS 02@~" };
                case "OMS 01": return new string[] { "OMS 02@~", "OMS 03@~", "RCS 02@L ALL", "RCS 01@L MANIFOLD 1" };
                case "OMS 02": case "OMS 03": return new string[] { "OMS 01@=", "RCS 01@L MANIFOLD 1", "RCS 02@L ALL" };
                case "RCS 01": return new string[] { "RCS 02@L ALL", "RCS 02@F ALL", "OMS 03@L", "OMS 03@R" };
                case "RCS 02": return new string[] { "RCS 01@F MANIFOLD 1", "RCS 01@L MANIFOLD 1" };
                case "FCS 01": return new string[] { "FCS 01@~", "RCS 02@L ALL" };
                case "DPS 01": case "DPS 02": case "DPS 03": case "DPS 06": case "DPS 04": case "DPS 05": return new string[] { "DPS 02@~", "SW 03@PAGE" };
                case "SW 01": return new string[] { "SW 03@PAGE", "DPS 02@~" };
                case "SW 02": return new string[] { "SW 01@*", "SW 03@PAGE" };
                case "SW 03": return new string[] { "DPS 02@~" };
            }
            return new string[0];
        }

        // ---------------------------------------------------------------- the generator: SplitMix64 of (seed, counter)
        public static double U(long seed, long counter)
        {
            unchecked
            {
                ulong z = (ulong)seed + 0x9E3779B97F4A7C15UL * (ulong)(counter + 1);
                z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                z ^= z >> 31;
                return (z >> 11) * (1.0 / 9007199254740992.0);      // [0, 1)
            }
        }

        // ---------------------------------------------------------------- state (saved: Draws, Picked, LastFire, Acc, E, Pending)
        public long Draws;
        public int Picked;                      // the picks of the whole flight (the log); the budget works on PickedPh
        public readonly int[] PickedPh = new int[3];        // the picks confirmed per phase (saved as ss.pp, ';'-joined: the SIM record is comma-separated)
        public readonly double[] PhaseT = new double[3];    // the random-clock seconds spent in each phase (saved as ss.pt)
        public double LastFire = -1e9;
        public bool DblOpen;                    // a double-up has fired since the last full spacing gap: no triple (saved as ss.dbl)
        public double Acc, E = -1;
        public double SlotAt = -1;              // BRUTAL's slot clock: the PhaseT at which the next random try is due (-1 = draw it); saved as ss.sa
        public readonly Dictionary<string, int> Fired = new Dictionary<string, int>();      // fires per "code|target" this flight (saved as ss.rep); BRUTAL caps it at MaxRepeat
        public const int MaxRepeat = 15;                                                      // at most 5 times, x3 for the failure TYPE repeating = 15
        public int Force = -1;                  // ForceAbort: an Oc* value overrides the drawn outcome (-1 = the draw); saved as ss.force
        public int Bb;                          // the backbone: 0 not planned yet, 1 planned (or nothing to plan); saved as ss.bb
        public int Reach = ReachAll;            // runtime: the outcomes the host says this flight can reach
        public int RevSeen;                     // The ROLL_REV points seen this flight (the first / second reversal scenarios); saved as ss.rv
        public readonly HashSet<string> Started = new HashSet<string>();     // The scenarios already started this flight (each at most once); saved as ss.sc
        // ENTRY ON VR: in the ENTRY / TAEM guidance phases the planner's
        // PICK clock is a VIRTUAL clock that runs on the relative velocity (m/s, the host feeds Vr each tick: SIMVR) instead of seconds: the
        // random clock steps, the points' lead / offsets, the chain delays, a pick's Due / Expire are all in virtual seconds, VrK virtual
        // seconds per m/s lost, so the whole entry (VR at the first tick down to VrEnd = the TAEM interface) spans PhaseSpan virtual seconds
        // whatever the real duration or the time warp. A/L (and every other phase, and a host that feeds no Vr) keeps real time; the virtual clock
        // is continuous at every hand-over. The crew-workload rules (spacing, settle, unresolved) stay in REAL seconds: the crew's time.
        public double Vr = -1;                  // the relative velocity now (m/s), fed by SIMVR before the Tick; <= 0 = none
        public const double VrEnd = 760, VrSpanMin = 300;
        // OPS 3 fires NOTHING before the entry interface. The host feeds the
        // altitude (m, SIMTICK's host: KalsAddon.Fail.cs); while Prog is OPS3 and the altitude is above EiAlt (the EI line, lib_failui fuiSimEiUt's 121920 m) and EI has not been seen,
        // Tick draws no random try, offers no pick, and holds the waiting picks' Due / Expire at their distance (the clock they run on is the planner's: after EI they fall due as planned).
        // Alt <= 0 (no feed: the offline tests, an older host) = not gated. OPS 6 (a TAL / RTLS entry) is NOT gated: its points stay as they are.
        public const double EiAlt = 121920;
        public double Alt = -1;                 // the altitude now (m), fed before the Tick; <= 0 = none
        bool eiSeen;                            // runtime: OPS 3 has been seen at or below EiAlt (the gate never closes again in this flight)
        public bool PreEi { get { return Prog == "OPS3" && Alt > EiAlt && !eiSeen; } }

        // The whole
        // guard below is for a flight with NO PILOT only; with a pilot InFinal is always false: SW 01 / SW 02 / DPS 04 / DPS 05 are drawn, scheduled and fired on the final
        // approach like anywhere else, AUTO LOST ON FINAL and LATE SURPRISE's SW 02 step are back (OptPilotOnly: a NO PILOT flight drops those steps).
        // THE FINAL-APPROACH LANDABILITY GUARD: from the A/L phase (the host's phase word) or, when the host feeds the altitude, from FinalAlt (m, above sea
        // level) down in OPS 3 / OPS 6, SimSup draws, schedules and fires NOTHING that takes the auto DAP or the guidance away: SW 01, SW 02 (any mode, any target), and DPS 04 / DPS 05
        // (they hold the host like SW 02: the DAP goes CSS, then a BFS engage and a crew re-select). The project owner's rule: a failure is fair game only while a landing can still come
        // out of it; with no seconds left to restart the software there is none. Manual picks (Check from the failure window) are not touched; a pick already standing keeps its restart.
        public const double FinalAlt = 6000;
        // With NO PILOT (the automated test flight: nobody restarts the software inside 10-25 s, nobody flies CSS) the whole TAEM phase is the final too: from the
        // TAEM phase word or from FinalAltNoPilot (m ASL: TAEM starts near 23 km) down. A flight with a pilot keeps FinalAlt (the pilot flies CSS / the restart himself).
        public const double FinalAltNoPilot = 25000;
        // The LATE STAGE 2 of an ascent that lands from its MECO is a final too, with NO PILOT.
        // The host feeds the mark S2_LATE (ops1q asc_simPts: a TAL, declared or hidden, with PEG's TGO <= ASC_SIM_LATE_TGO 100 s); from it to the end of OPS 1 the final-approach guard holds
        // (no SW 01 / SW 02 / DPS 04 / DPS 05 drawn, scheduled or fired; a due pick dropped). A python sim of such a flight finds a
        // 38-45 s no-pilot outage unlandable from ~85 s before MECO and harmless before ~100 s (holds at MET 110-254 recovered). A pilot keeps them.
        public static bool FinalBlocked(string code) { return code == "SW 01" || code == "SW 02" || code == "DPS 04" || code == "DPS 05"; }
        public bool InFinal(string prog, string phase)
        {
            if (!NoPilot) return false;                         // A human pilot flies CSS / restarts the software himself: the whole landing-window guard is for NO PILOT only
            if (prog == "OPS1") return edgeLate > 0;            // The late stage 2 of a TAL (the host's S2_LATE mark) to the end of OPS 1
            string ph = (phase ?? "").Trim().ToUpperInvariant();
            if (ph == "A/L") return true;
            if (prog != "OPS3" && prog != "OPS6") return false;
            if (ph == "TAEM") return true;
            return Alt > 0 && Alt <= FinalAltNoPilot;
        }
        // THE BLENDED ENTRY CLOCK. The old clock was v = vA + (vr0 - Vr) x vK, held by max(): while VR held or rose (the OPS 3 / OPS 6 coast, the
        // first minutes of the entry) the clock stood still and every early pick waited, and the first tick's VR was the zero of it. Now the clock is INTEGRATED per call:
        //     dv = dtGame x max(ClockKt, vK x dec)        dec = the smoothed deceleration (m/s2, EMA with time constant DecelTau, never below 0)
        //     vK = (PhaseSpan - (v - vStart)) / max(VrSpanMin, Vr - VrEnd)     = the virtual s still to spend per m/s still to lose
        // so it is TIME-LIKE while the orbiter is not decelerating (ClockKt virtual s per game s: never stopped, never back, a rising VR changes nothing), follows VR
        // once the deceleration is real (the VR part dominates), and vK re-aims at every call so the clock reaches vStart + PhaseSpan as VR reaches VrEnd (the TAEM
        // interface) whatever the coast spent. WARP: both parts are per GAME second (the time part is linear in dt, the EMA's weight is 1 - exp(-dt / tau)), so a 4x warp
        // in the coast spends the same virtual seconds as the 1x flight. A/L (and a host that feeds no Vr) keeps the real time 1:1; the clock is continuous at every
        // hand-over. Saved as ss.vc (7 fields; an old 5-field save restores with the new ones at their start values).
        public const double ClockKt = 0.3, DecelTau = 8;
        double vr0 = -1, vA, vK, vNow = -1, vReal, lastVn = -1;     // saved as ss.vc: the clock's start flag (the first VR), its virtual start, vK, the virtual now, the real time of it
        double vrPrev = -1, vrDec;                                   // saved as ss.vc: the previous VR sample and the smoothed deceleration (m/s2)
        bool vrLive;                                                 // runtime: the last VClock call ran the blended clock (ENTRY / TAEM with a VR), not the 1:1 real one
        public bool VrClock { get { return vrLive; } }               // the entry clock is the blended one now (a VR was fed in ENTRY / TAEM)
        public double ClockRate { get { return vrLive ? Math.Max(ClockKt, vK * Math.Max(vrDec, 0)) : 1; } }     // virtual s per game s now
        public double VStart { get { return vA; } }
        public double VClock(double now, string phase)
        {
            if (vNow < 0) { vNow = now; vReal = now; }
            double dtG = Math.Max(now - vReal, 0);
            double v = vNow + dtG;                                               // no VR clock: the virtual time keeps pace with the real one
            if (Ph == PhEntry && Vr > 0 && phase != "A/L")
            {
                if (vr0 < 0) { vr0 = Vr; vA = v; vK = PhaseSpan[PhEntry] / Math.Max(VrSpanMin, vr0 - VrEnd); vrPrev = Vr; vrDec = 0; }
                else if (vrPrev < 0) vrPrev = Vr;                          // back from a stretch without the VR clock (A/L): no jump
                else if (dtG > 0)
                {
                    double inst = (vrPrev - Vr) / dtG;                           // + = losing speed
                    vrDec += (1 - Math.Exp(-dtG / DecelTau)) * (inst - vrDec);
                    vrPrev = Vr;
                }
                vK = Math.Max(0, PhaseSpan[PhEntry] - (vNow - vA)) / Math.Max(VrSpanMin, Vr - VrEnd);
                v = vNow + dtG * Math.Max(ClockKt, vK * Math.Max(vrDec, 0));     // never back: both terms are >= 0
                vrLive = true;
            }
            else { vrPrev = -1; vrLive = false; }
            vNow = v; vReal = now;
            return v;
        }
        double lastTickNow = -1;                // runtime: the game time of the last Tick (the orbit's clock)
        double edgeTal = -1, edgeAto = -1, edgeRtn = -1, greenLo = -1, greenHi = -1, edgeSrb = -1, edgeT2 = -1, edgeV3T = -1, edgeV3A = -1, edgeTo = -1, edgeAo = -1, edgeGo = -1, edgeG3 = -1, edgeMn = -1, edgeLate = -1, edgeR2G = -1, edgeR2B = -1;   // runtime: the fed marks' UTs (SRB_SEP = the stage 1 / 2 boundary, TAL_2EO = the 2EO TAL boundary)
        public readonly List<SimPick> Pending = new List<SimPick>();
        // runtime only
        public string Prog = "";
        public readonly HashSet<string> Codes = new HashSet<string>();
        long randSeed = DateTime.UtcNow.Ticks, randDraws;
        double randAcc, randE = -1;
        public string LastWhy = "";                 // the last refusal of Check / Workload (the offline test and the log)
        public bool LastWasDouble;                  // the last fire was a DOUBLE-UP (inside its spacing); LastGap = s since the fire before it
        public double LastGap;

        public void Reset()
        {
            Draws = 0; Picked = 0; PickedPh[0] = PickedPh[1] = PickedPh[2] = 0; PhaseT[0] = PhaseT[1] = PhaseT[2] = 0; LastFire = -1e9; Acc = 0; E = -1; Pending.Clear(); Fired.Clear(); FiredPh.Clear(); PhRound.Clear(); Recent.Clear(); LastWhy = ""; DblOpen = false; LastWasDouble = false; Force = -1; Bb = 0; OcLabel = ""; vr0 = -1; vNow = -1; lastVn = -1; Vr = -1; vrPrev = -1; vrDec = 0; vrLive = false; SlotAt = -1; RevSeen = 0; Started.Clear(); edgeTal = edgeAto = edgeRtn = greenLo = greenHi = edgeSrb = edgeT2 = edgeV3T = edgeV3A = edgeTo = edgeAo = edgeGo = edgeG3 = edgeMn = edgeLate = edgeR2G = edgeR2B = -1;
        }

        public void Host(string prog, string codes)
        {
            string np = (prog ?? "").Trim().ToUpperInvariant();
            // a PHASE hand-over drops the old phase's unfired picks (they were that phase's budget; the first Host after a load has no old phase)
            if (Prog.Length > 0 && np.Length > 0 && PhaseOf(np) != PhaseOf(Prog)) Pending.Clear();
            if (Prog != np) { lastTickNow = -1; vr0 = -1; lastVn = -1; vrPrev = -1; vrDec = 0; SlotAt = -1; eiSeen = false; }
            Prog = np;
            Codes.Clear();
            foreach (string c in (codes ?? "").Split(';')) { string t = c.Trim().ToUpperInvariant(); if (t.Length > 0) Codes.Add(t); }
        }

        double Draw(FailState s) { return U(s.SeedHash, Draws++); }
        static T Pick<T>(T[] a, double u) { int i = (int)(u * a.Length); return a[i >= a.Length ? a.Length - 1 : i]; }

        // ================================================================ THE CAPABILITY ACCOUNT
        // the failures as (code, target, mode) that count: the list (fixed ones are gone from it) + the candidate
        struct F { public string C, T, M, V; public double At; public bool Fixing; }
        static List<F> Account(FailState s, string code, string target, string mode, double now, string value = "")
        {
            var l = new List<F>();
            foreach (FailEntry e in s.List) l.Add(new F { C = e.Code, T = e.Target, M = e.Mode, V = e.Value, At = e.At, Fixing = e.HealAt >= 0 });
            if (code != null) l.Add(new F { C = code, T = target, M = mode, V = value ?? "", At = now, Fixing = false });
            return l;
        }
        static bool StuckOn(string v) { return v == "STUCK ON" || v == "FAIL ON"; }          // RCS 04's value (the old "FAIL ON" still reads in an old save)
        static bool Has(List<F> l, string c, string t) { foreach (F f in l) if (f.C == c && f.T == t) return true; return false; }
        static int Count(List<F> l, string c) { int n = 0; foreach (F f in l) if (f.C == c) n++; return n; }
        // The four GPC codes. DOWN = out of the redundant set by any of them; PERM = out for good (DPS 01 hardware, DPS 03 permanent)
        public static bool IsGpcCode(string c) { return c == "DPS 01" || c == "DPS 02" || c == "DPS 03" || c == "DPS 06"; }
        static bool GpcDown(List<F> l, string g) { foreach (F f in l) if (f.T == g && IsGpcCode(f.C)) return true; return false; }
        static bool GpcPerm(List<F> l, string g) { foreach (F f in l) if (f.T == g && (f.C == "DPS 01" || (f.C == "DPS 03" && f.M == "P"))) return true; return false; }

        // the PART a failure acts on: the jets of one end, one OMS engine, one SSME, one GPC, one surface; "" = no shared part
        public static string PartKey(string code, string target)
        {
            if (code == "RCS 01" || code == "RCS 02" || code == "RCS 03") return "RCS " + (target.Length > 0 ? target.Substring(0, 1) : "");        // The POD (F / L / R) is the part
            if (code == "RCS 04") return "JET " + target;                                      // One jet is its own part (a stuck jet does not block the group's RCS 01 / 02)
            if (code == "OMS 04") return "OMSTANK " + target;                                  // A tank leak is not an engine failure
            if (code == "OMS 01" || code == "OMS 02" || code == "OMS 03") return "OMS " + target;
            if (code == "MPS 01" || code == "MPS 02" || code == "MPS 03") return "MPS " + target;
            if (code == "DPS 01" || code == "DPS 02" || code == "DPS 03" || code == "DPS 06") return "GPC " + target;
            if (code == "FCS 01") return "FCS " + target;
            return "";
        }


        // ---------------------------------------------------------------- THE LANDING CHAIN GUARD (BRUTAL)
        // Each system's floors above keep THAT system survivable (one OMS engine, two SSMEs, two GPCs, one rudder, ...). What they do not see is the SUM: a BRUTAL flight that also
        // holds the guidance, the auto DAP, the jets and the surfaces for good has the pilot hand-flying the whole entry on what is left. LandUnits counts the PERMANENT failures
        // (not healing) that each take away one way to land: a frozen surface, the entry's SW 01 / SW 02 (the auto DAP, the guidance), an aft RCS pod / the forward jets off, an RCS leak, a
        // jet stuck on, an OMS engine out, an OMS tank leak. A pick that would push the total over LandCap is refused ("LANDING (TOO MANY PERMANENT FAILURES)"), so the draw takes another.
        public const int LandCap = 10;
        public static bool LandGuardOn = true;                 // the offline test switches it off to measure what the floors alone let through
        static int LandUnits(List<F> l)
        {
            int u = 0; var pods = new HashSet<string>();
            foreach (F f in l)
            {
                if (f.M != "P" || f.Fixing) continue;
                switch (f.C)
                {
                    case "FCS 01": u++; break;
                    case "SW 01": if (f.T == "ENTRY") u++; break;
                    case "SW 02": if (f.T == "ENTRY" || f.T == "TAEM" || f.T == "A/L") u++; break;
                    case "RCS 01": case "RCS 02": { string pod = f.T.Length > 0 ? f.T.Substring(0, 1) : ""; if (pods.Add(pod)) u++; break; }
                    case "RCS 03": u++; break;
                    case "RCS 04": if (StuckOn(f.V)) u++; break;
                    case "OMS 01": u++; break;
                    case "OMS 04": u++; break;
                }
            }
            return u;
        }
        public static int LandUnits(FailState s) { return LandUnits(Account(s, null, null, null, 0)); }

        // "" = survivable at this level, else the floor it breaks (the window's "RTN IMPSBLE: <floor>")
        public static string Check(FailState s, string prog, string code, string target, string mode, int level, double now, bool landOk = false, int opt = 0, string value = "")
        {
            if (NoCodes.Contains(code)) return "EXCLUDED BY THE HOST (NO CODES)";
            level = Clamp(level);
            if (Has(Account(s, null, null, null, now), code, target)) return "ALREADY FAILED";
            List<F> l = Account(s, code, target, mode, now, value);
            bool hardUp = level >= Hard;

            // ASCENT THRUST + CONTROL: SSME units (out 0, low / locked 0.5, healthy 1) >= 2; at most 1 locked gimbal
            if (code.StartsWith("MPS", StringComparison.Ordinal))
            {
                if (code != "MPS 01" && Has(l, "MPS 01", target)) return "THAT SSME IS OUT";
                int outs = Count(l, "MPS 01");
                var deg = new HashSet<string>(); int locks = 0;
                foreach (F f in l)
                {
                    if ((f.C == "MPS 02" || (f.C == "MPS 03" && (opt & OptGimbalCtl) == 0)) && !Has(l, "MPS 01", f.T)) deg.Add(f.T);
                    if (f.C == "MPS 03" && !Has(l, "MPS 01", f.T)) locks++;
                }
                if (3.0 - outs - 0.5 * deg.Count < 2.0)
                {   // the ONE exception: a planned 2EO (landOk) takes the second SSME out; the third only on a planned 3EO (OptThird)
                    if (!(landOk && code == "MPS 01" && (outs == 2 || (outs == 3 && (opt & OptThird) != 0)) && deg.Count == 0)) return "ASCENT THRUST (ONE ABORT MODE OPEN)";
                }
                if (locks > 1) return "ASCENT CONTROL (ONE LOCKED GIMBAL)";
                // With two SSMEs running and one
                // not gimballing the stack has no control. A locked gimbal NEVER stands with another SSME out, whatever the opt (COMPOUND OUT / BRUTAL's coverage draw used OptGimbalCtl for it),
                // and an SSME out never joins a locked gimbal on ANOTHER engine (the lock's own engine going out is fine: the lock is gone with it).
                if (code == "MPS 03") { foreach (F f in l) if (f.C == "MPS 01" && f.T != target) return "ASCENT CONTROL (A LOCKED GIMBAL WITH ANOTHER SSME OUT)"; }
                if (code == "MPS 01") { foreach (F f in l) if (f.C == "MPS 03" && f.T != target && !Has(l, "MPS 01", f.T)) return "ASCENT CONTROL (AN SSME OUT WITH ANOTHER GIMBAL LOCKED)"; }
            }
            // DEORBIT: one OMS engine always works; EASY / NORMAL at most one OMS engine failed in any way
            if (code.StartsWith("OMS", StringComparison.Ordinal) && code != "OMS 04")      // OMS 04 is a tank leak, its floors are below
            {
                if (code != "OMS 01" && Has(l, "OMS 01", target)) return "THAT OMS ENGINE IS OUT";
                var any = new HashSet<string>();
                foreach (F f in l) if (f.C == "OMS 01" || f.C == "OMS 02" || f.C == "OMS 03") any.Add(f.T);
                if (Count(l, "OMS 01") > 1) return "DEORBIT (ONE OMS ENGINE)";
                if (!hardUp && any.Count > 1 && !((opt & OptPair) != 0 && Count(l, "OMS 01") == 0)) return "DEORBIT (EASY / NORMAL: ONE OMS ENGINE FAILED)";      // OptPair (TIRED PAIR): two engines DEGRADED, never one out + one degraded
            }
            // ORBIT ATTITUDE / ENTRY CONTROL: the aft jets stay (BOTH aft pods ALL = the old AFT ALL: permanent never, transient HARD+); F ALL permanent HARD+
            if (code == "RCS 01" || code == "RCS 02")
            {
                bool podL = false, podR = false, aftPerm = false;
                foreach (F f in l)
                {
                    if (f.C != "RCS 01") continue;
                    if (f.T == "L ALL") { podL = true; if (f.M == "P") aftPerm = true; }
                    if (f.T == "R ALL") { podR = true; if (f.M == "P") aftPerm = true; }
                    if (f.T == "F ALL" && f.M == "P" && !hardUp) return "ORBIT ATTITUDE (EASY / NORMAL: FWD JETS)";
                }
                if (podL && podR)
                {
                    if (aftPerm) return "ENTRY CONTROL (AFT JETS)";
                    if (!hardUp) return "ENTRY CONTROL (EASY / NORMAL: AFT JETS)";
                }
                string podAll = (target.Length > 0 ? target.Substring(0, 1) : "") + " ALL";
                if (code == "RCS 02" && Has(l, "RCS 01", podAll)) return "THOSE JETS ARE OFF";
                if (code == "RCS 01" && target != podAll && Has(l, "RCS 01", podAll)) return "THOSE JETS ARE OFF";
                int aft = 0;
                foreach (F f in l) if ((f.C == "RCS 01" || f.C == "RCS 02") && (f.T.StartsWith("L", StringComparison.Ordinal) || f.T.StartsWith("R", StringComparison.Ordinal))) aft++;
                if (!hardUp && aft > 1 && (opt & OptPair) == 0) return "ENTRY CONTROL (EASY / NORMAL: ONE AFT RCS FAILURE)";
            }
            // THE LEAKS AND THE SINGLE JET (the three codes the DLL holds from now: OMS 04 / RCS 03 leaks drain a tank the crew can still shut off with the fix,
            // RCS 04 puts one jet off, stuck on or leaking). What stands for good stays survivable at each level (the candidate's own VALUE counts: value = "" is the mildest):
            //   OMS 04: one leak at a time (two at HARD+, never BOTH with a single tank); a PERMANENT 0.2 kg/s leak HARD+ on one tank, BOTH only at BRUTAL; a PERMANENT 0.05
            //   BOTH HARD+; a transient BOTH not at EASY.  RCS 03: one leak at a time (two at HARD+); PERMANENT only HARD+ at 1 %/MIN, 5 %/MIN never on an aft pod (L / R) and
            //   BRUTAL only on the F one; one permanent leak only.  RCS 04: one jet at a time (three at HARD+); STUCK ON permanent BRUTAL only, two jets ON BRUTAL only.
            if (code == "OMS 04")
            {
                bool big = value.StartsWith("0.2", StringComparison.Ordinal);
                int n = 0; bool both = false, single = false;
                foreach (F f in l) if (f.C == "OMS 04" && !f.Fixing) { n++; if (f.T == "BOTH") both = true; else single = true; }
                if (n > (hardUp ? 2 : 1)) return "DEORBIT (OMS PROPELLANT: ONE LEAK)";
                if (both && single) return "DEORBIT (OMS PROPELLANT: THE TANKS ARE LEAKING)";
                if (mode == "P" && (target == "BOTH" ? (big ? level < Brutal : !hardUp) : (big && !hardUp))) return "DEORBIT (OMS PROPELLANT: A PERMANENT LEAK)";
                if (mode != "P" && target == "BOTH" && level < Normal) return "DEORBIT (EASY: ONE TANK LEAKS)";
            }
            if (code == "RCS 03")
            {
                bool big = value.StartsWith("5", StringComparison.Ordinal);
                int n = 0, perm = 0;
                foreach (F f in l) if (f.C == "RCS 03" && !f.Fixing) { n++; if (f.M == "P") perm++; }
                if (n > (hardUp ? 2 : 1)) return "ORBIT / ENTRY (RCS PROPELLANT: ONE LEAK)";
                if (perm > 1) return "ENTRY CONTROL (RCS PROPELLANT: ONE PERMANENT LEAK)";
                if (mode == "P")
                {
                    if (!hardUp) return "ENTRY CONTROL (EASY / NORMAL: RCS PROPELLANT MUST BE SHUT OFF)";
                    if (big && (level < Brutal || target != "F")) return "ENTRY CONTROL (RCS PROPELLANT: A PERMANENT 5 %/MIN LEAK)";
                }
            }
            if (code == "RCS 04")
            {
                int n = 0, on = 0;
                foreach (F f in l) if (f.C == "RCS 04" && !f.Fixing) { n++; if (StuckOn(f.V)) on++; }
                if (n > (hardUp ? 3 : 1)) return "CONTROL (SINGLE JETS: ONE AT A TIME)";
                if (StuckOn(value) && mode == "P" && level < Brutal) return "CONTROL (A JET STUCK ON FOR GOOD)";
                if (on > (level >= Brutal ? 2 : 1)) return "CONTROL (TWO JETS STUCK ON)";
            }
            // LANDING: frozen surfaces: 1 (EASY / NORMAL), 2 (HARD+), never two elevons one side (1-2 left, 3-4 right), never both rudders
            if (code == "FCS 01")
            {
                if (mode == "P" && NoPilot && IsRudder(target)) return "LANDING (NO PILOT: NO SPEEDBRAKE TO LAND WITH)";        // Any flight, nominal entries too
                if (mode == "P" && NoPilot && AbortArr) return "LANDING (NO PILOT: A FROZEN SURFACE ON AN ABORT ARRIVAL)";        // Guard A
                int n = Count(l, "FCS 01");
                if (n > (hardUp ? 2 : 1)) return "LANDING (FROZEN SURFACES)";
                if (Has(l, "FCS 01", "ELEVON 1") && Has(l, "FCS 01", "ELEVON 2") || Has(l, "FCS 01", "ELEVON 3") && Has(l, "FCS 01", "ELEVON 4"))
                    return "LANDING (TWO ELEVONS ONE SIDE)";
                if (Has(l, "FCS 01", "RUDDER L") && Has(l, "FCS 01", "RUDDER R")) return "LANDING (BOTH RUDDERS)";
            }
            // The PASS SET as a whole. DPS 04 REDUNDANT SET SPLIT (2-2, the guidance holds until the crew picks the right pair or engages the BFS) HARD and above;
            // DPS 05 PASS GENERIC SOFTWARE FAIL (all four PASS GPCs, the BFS flies the rest with one display) BRUTAL only, and never with G5 down; never both at once (never two splits);
            // never in orbit (2 GNC + 1 SM GPCs, no 4-GPC set); a split needs all four PASS GPCs good (a 2-2 split of three is no split)
            if (code == "DPS 04" || code == "DPS 05")
            {
                if (prog == "OPS2") return "COMMON SET (NO PASS SET IN ORBIT)";
                if (code == "DPS 04" && !hardUp) return "COMMON SET (SPLIT: HARD AND ABOVE)";
                if (code == "DPS 05" && level < Brutal) return "COMMON SET (PASS FAIL: BRUTAL ONLY)";
                if (Count(l, "DPS 04") + Count(l, "DPS 05") > 1) return "COMMON SET (ONE AT A TIME)";
                if (code == "DPS 05" && GpcDown(l, "G5")) return "COMMON SET (NO BFS: G5 DOWN)";
                if (code == "DPS 04")
                    foreach (string g in new string[] { "G1", "G2", "G3", "G4" }) if (GpcDown(l, g)) return "COMMON SET (A PASS GPC IS DOWN: NO 2-2 TO SPLIT)";
            }
            // DISPLAYS: good PASS GPCs (G1-G4) >= 3 (EASY / NORMAL) / 2 (HARD+); never both of the program's display GPCs dead
            // DPS 03 (FAIL TO SYNC) and DPS 06 (OUTPUT BAD) take a GPC out of the set like DPS 01 / 02: GpcDown counts all four codes; a PERMANENT out (DPS 01, DPS 03 P) is GpcPerm
            if (IsGpcCode(code))
            {
                if (Count(l, "DPS 04") + Count(l, "DPS 05") > 0) return "DISPLAYS (SET SPLIT / PASS FAILED)";      // No single GPC pick while the set stands split or the PASS set is down
                int bad = 0;
                foreach (string g in new string[] { "G1", "G2", "G3", "G4" }) if (GpcDown(l, g)) bad++;
                // A TRANSIENT pick (DPS 02, DPS 06, DPS 03 T) on BRUTAL may leave one good
                // PASS GPC (a restart brings it back); a permanent one (DPS 01 hardware, DPS 03 P) keeps 2 at HARD+, 3 below; the display-GPC rules below stay
                bool transGpc = code == "DPS 02" || code == "DPS 06" || (code == "DPS 03" && mode == "T");
                int gpcFloor = transGpc && level >= Brutal ? 1 : (hardUp ? 2 : 3);
                if (4 - bad < gpcFloor) return "DISPLAYS (GOOD PASS GPCS)";
                string d2 = prog == "OPS2" ? "G4" : "G2";
                if (GpcPerm(l, "G1") && GpcPerm(l, d2)) return "DISPLAYS (BOTH DISPLAY GPCS)";
                if (!hardUp && GpcDown(l, "G1") && GpcDown(l, d2))
                    return "DISPLAYS (EASY / NORMAL: BOTH DISPLAY GPCS)";
            }
            // MANUAL FLIGHT: SW 01 / 02 permanent only at HARD+ and never in ASCENT / ENTRY guidance; one of them at a time at EASY / NORMAL
            if (code == "SW 01" || code == "SW 02")
            {
                if (mode == "P" && NoPilot) return "MANUAL FLIGHT (NO PILOT: SAIL FLIES)";
                if (mode == "P" && (!hardUp || (level < Brutal && (target == "ASCENT" || target == "ENTRY") && (opt & OptSwPerm) == 0))) return "MANUAL FLIGHT (" + target + " SOFTWARE MUST RESTART)";
                int sw = 0;
                foreach (F f in l) if ((f.C == "SW 01" || f.C == "SW 02") && !f.Fixing) sw++;
                if (!hardUp && sw > 1) return "MANUAL FLIGHT (EASY / NORMAL: ONE SOFTWARE LOSS)";
            }
            // After the specific floors (their words stay): a part with a standing failure (a permanent one, or a transient not yet cleared)
            // takes no second failure of any mode (a flight: a permanent forward RCS failure, then the same jets failed transiently)
            string pk = PartKey(code, target);
            if (pk.Length > 0 && (opt & OptSamePart) == 0)
                foreach (FailEntry e in s.List)
                    if (PartKey(e.Code, e.Target) == pk) return e.Mode == "P" ? "THAT PART IS DOWN FOR GOOD" : "THAT PART IS ALREADY FAILED";
            // The SUM of the permanent landing failures (LandUnits): BRUTAL only (below it the single-system floors are the whole rule)
            if (level >= Brutal && LandGuardOn && mode == "P" && LandUnits(l) > LandCap) return "LANDING (TOO MANY PERMANENT FAILURES)";
            return "";
        }

        // the minimum gap before this pick: the level's Spacing, OrbitGap x it in the orbit phase (a burn-point OMS failure keeps its TIG window: the plain spacing)
        double SpacingOf(int lv, SimPick p)
        {
            bool omsPt = p != null && p.Code != null && p.Code.StartsWith("OMS", StringComparison.Ordinal) && p.Src != null && p.Src.StartsWith("POINT", StringComparison.Ordinal);
            return Spacing[lv] * (Prog == "OPS2" && !omsPt ? OrbitGap : 1);
        }

        // the WORKLOAD rules (SimSup only): the burn's quiet time, spacing (with the DOUBLE-UP, HARD / BRUTAL), unresolved count;
        // "" = it may fire now. p = the pick (its double-up draw is stored on it); null = no double-up (the plain rules)
        public string Workload(FailState s, int level, double now, double tig, SimPick p = null)
        {
            level = Clamp(level);
            if (p != null && IsScen(p))
            {   // A scenario step keeps its script's times (TIG - 20 s, TIG + 0): no burn quiet time, no spacing, no unresolved cap; the automated test flight's no-pilot gap stays
                if (NoPilot && level >= Brutal && now - LastFire < PickGap(s, p)) return "SPACING";
                return "";
            }
            if (tig > NoTig / 2 && tig > -BurnQuiet && tig < BurnQuiet) return "BURN QUIET TIME";
            if (p != null && IsBb(p)) return "";                           // the backbone's engine outs keep their window (only the burn's quiet time above)
            double gap = now - LastFire;
            double spacing = SpacingOf(level, p);
            bool npg = NoPilot && level >= Brutal;                         // The automated test flight, BRUTAL: a gap between any two picks, no double-up (nobody restarts a row inside 10 s)
            if (npg) spacing = Math.Max(spacing, PickGap(s, p));
            if (gap < spacing)
            {
                // THE DOUBLE-UP: only inside DoubleWin of the last fire, never with one already open, and only if the pick's draw won
                if (npg || p == null || gap < 0 || gap > DoubleWin[level] || DoubleWin[level] <= 0 || DblOpen || p.Dbl == 2) return "SPACING";
                if (p.Dbl == 0) p.Dbl = Draw(s) < DoubleP[level] ? 1 : 2;
                if (p.Dbl != 1) return "SPACING";
            }
            int un = 0;
            foreach (FailEntry e in s.List)
            {
                if (e.HealAt >= 0) continue;                                 // a fix is under way: worked
                if (e.Mode == "T" || now - e.At < Settle[level]) un++;
            }
            if (un >= Unresolved[level]) return "UNRESOLVED";
            return "";
        }

        // A pick's NO PILOT gap, drawn once from the seeded stream (NoPilot only: a human's flight draws nothing here); no pick = the floor
        double PickGap(FailState s, SimPick p)
        {
            if (p == null) return NoPilotGap;
            if (p.Gap < 0) p.Gap = NoPilotGapOf(Draw(s));
            return p.Gap;
        }

        // ================================================================ THE PLANNER
        bool Flyable(string code) { return Codes.Contains(code) && Workaround.ContainsKey(code); }

        // a concrete (target, value, mode) for code from a target spec ("*" = all now, "a/b" = one of, "=" own, "~" another of the kind)
        // The targets only a scenario may name (the random draws never see them): SW 02 ALPHA MOD (the entry's alpha modulation loop, before TAEM)
        public static string[] ScenTargets(string prog, string code, string phase)
        {
            string[] t = Targets(prog, code, phase);
            if (code == "SW 02" && (prog == "OPS3" || prog == "OPS6") && t.Length == 1 && t[0] == "ENTRY") return new string[] { "ENTRY", "ALPHA MOD" };
            return t;
        }
        bool Resolve(FailState s, string code, string spec, string own, string phase, out string tg, out string vl, out string md, bool scen = false)
        {
            tg = vl = md = "";
            if (FinalBlocked(code) && InFinal(Prog, phase)) return false;                  // No DAP / guidance loss on the final approach, by any path (random, point, scenario)
            string[] all = scen ? ScenTargets(Prog, code, phase) : Targets(Prog, code, phase);
            if (all.Length == 0) return false;
            string[] opts;
            if (spec == "*") opts = all;
            else if (spec == "=") opts = new string[] { own };
            else if (spec == "~") { var o = new List<string>(); foreach (string t in all) if (t != own) o.Add(t); opts = o.ToArray(); }
            else opts = spec.Split('/');
            var ok = new List<string>();
            foreach (string t in opts) if (Array.IndexOf(all, t) >= 0 && s.IndexOf(code, t) < 0 && !AtRepeatCap(s, code, t) && (scen || !AtPhaseCap(code, t))) ok.Add(t);
            if (RudderRule(code) && !RudderOk(Clamp(s.Difficulty))) ok.RemoveAll(IsRudder);       // A rudder half is drawn only on BRUTAL with a pilot
            if (ok.Count == 0) return false;
            tg = RudderRule(code) ? PickRudderW(ok.ToArray(), Draw(s)) : Pick(ok.ToArray(), Draw(s));      // The halves together 5 % of the surfaces
            vl = Pick(Values(code), Draw(s));
            string m = ModesOf(code);
            md = m == "PT" ? (Draw(s) < (Clamp(s.Difficulty) >= Brutal ? BrutalPermShare : 0.5) ? "P" : "T") : (m.Length > 0 ? m.Substring(0, 1) : "P");
            return true;
        }

        bool AtRepeatCap(FailState s, string code, string tg)
        {
            int n;
            return Clamp(s.Difficulty) >= Brutal && Fired.TryGetValue(code + "|" + tg, out n) && n >= MaxRepeat;
        }

        // a DRAWN pick (random / point / chain; never a scenario step or a backbone out) may not repeat one code + target more than MaxPhaseRepeat times in one phase
        // (ASCENT / ORBIT / ENTRY / TAEM / A/L), and SW 03 (the display page: a transient that costs nothing) not more than Sw03FlightMax times a flight. The draw then
        // walks the catalog (the unfired-first weight + these caps) instead of re-picking the codes the floors leave it. EVERY level: the budgets of EASY .. HARD are small, it rarely binds.
        // ROUNDS: when a random try finds NOTHING left only because of the cap (the catalog of that phase is walked once: the floors and the standing failures took the rest), the phase
        // opens a new round (the limit grows by MaxPhaseRepeat), so a long phase never goes silent ("the quiet period") and still walks the whole catalog before it repeats.
        // A round opens only after QuietRound game seconds without ANY fire (the caps hold the repeat rate down: once the catalog is walked, a failure at most every ~2 minutes).
        // The same for a CODE as a whole (MaxCodePhase, the family's targets together: DPS 02 has five GPCs, so 2 per target alone would let the transients that restart fill an exhausted phase).
        public const int MaxPhaseRepeat = 2, MaxCodePhase = 4, Sw03FlightMax = 3;
        public const double QuietRound = 90;
        public readonly Dictionary<string, int> FiredPh = new Dictionary<string, int>();       // fires per "PHASE|code|target" (saved as ss.rph)
        public readonly Dictionary<string, int> PhRound = new Dictionary<string, int>();       // the rounds opened per phase key (saved as ss.rnd)
        string phNow = "";                     // runtime: the host's phase of the last Tick / Point / Result call (the phase key of the caps)
        string PhKey(string phase)
        {
            string ph = (phase ?? "").Trim().ToUpperInvariant();
            return ph == "TAEM" || ph == "A/L" ? ph : PhaseName(Ph);
        }
        bool AtPhaseCap(string code, string tg)
        {
            int n;
            string pk = PhKey(phNow); int rd;
            int k = 1 + (PhRound.TryGetValue(pk, out rd) ? rd : 0);
            if (FiredPh.TryGetValue(pk + "|" + code + "|" + tg, out n) && n >= MaxPhaseRepeat * k) return true;
            string cp = pk + "|" + code + "|"; int nc = 0;
            foreach (KeyValuePair<string, int> kv in FiredPh) if (kv.Key.StartsWith(cp, StringComparison.Ordinal)) nc += kv.Value;
            if (nc >= MaxCodePhase * k) return true;
            return code == "SW 03" && FiresOf(code) >= Sw03FlightMax;
        }
        static bool IsBb(SimPick p) { return p.Src != null && p.Src.StartsWith("BACKBONE", StringComparison.Ordinal); }
        int DueSpice(double vn) { int n = 0; foreach (SimPick p in Pending) if (!IsBb(p) && p.Due <= vn) n++; return n; }      // The picks that are DUE and still wait (a planned template step ahead is no backlog)
        int SpicePending() { int n = 0; foreach (SimPick p in Pending) if (!IsBb(p)) n++; return n; }
        public int Room(FailState s) { return Budget(s) - PickedPh[Ph] - SpicePending(); }

        // The flight is an abort arrival: a forced outcome (Force >= 0) other than ORBIT, else the drawn one once the backbone has been planned (Bb != 0 even outside OPS 1: the save keeps it)
        public bool IsAbortArrival(FailState s) { return Force >= 0 ? Force != OcOrbit : Bb != 0 && Outcome(s) != OcOrbit; }
        // Check with this flight's abort-arrival flag set first (the static Check cannot see the instance)
        public string ChkI(FailState s, string prog, string code, string target, string mode, int level, double now, bool landOk = false, int opt = 0, string value = "")
        { AbortArr = IsAbortArrival(s); return Check(s, prog, code, target, mode, level, now, landOk, opt, value); }
        public int Outcome(FailState s) { return Force >= 0 && Force < OcName.Length ? Force : OutcomeOf(s.SeedHash, s.Difficulty, Reach); }
        // The name the host LOGS: an engage after the ascent (OPS 2 / 3, nothing planned) has no ascent left to fly = ORBIT (the drawn mode steers nothing there)
        public string OutcomeName(FailState s) { if (Prog != "OPS1" && Bb == 0 && Force < 0) return OcName[OcOrbit]; int oc = Outcome(s); return oc == OcAto3 && OcLabel.Length > 0 ? OcLabel : OcName[oc]; }
        public void SetReach(string list)       // "RTLS;1EO TAL;..." (OcName): the outcomes this flight can reach; "" = all
        {
            int m = 1;
            foreach (string t in (list ?? "").Split(';'))
                for (int k = 1; k < OcName.Length; k++) if (OcName[k] == t.Trim().ToUpperInvariant()) m |= 1 << k;
            Reach = (list ?? "").Trim().Length == 0 ? ReachAll : m;
        }

        // the window [lo, hi] (UT) for a backbone engine out: never before now + 3 s; a window that closed is pushed to a short one
        static void Win(ref double lo, ref double hi, double now)
        {
            if (lo < now + 3) lo = now + 3;
            if (hi < lo + 5) hi = lo + 5;
        }

        void AddBb(FailState s, string src, double lo, double hi, string notThis)
        {
            if (!Flyable("MPS 01")) return;
            var ok = new List<string>();
            foreach (string t in Ssme) if (t != notThis && s.IndexOf("MPS 01", t) < 0) ok.Add(t);
            if (ok.Count == 0) return;
            string tg = Pick(ok.ToArray(), Draw(s));
            double due = lo + Draw(s) * (hi - lo);
            Pending.Add(new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = due, Expire = due + PickLife, Src = src });
        }

        // plan the backbone once every mark its outcome needs has been fed (Point calls them); ORBIT plans nothing
        // The outs of the 3EO outcomes and of 2EO BLUE / SPLITS. Marks: SRB_SEP (stage 1 ends), TAL_2EO (the 2EO TAL boundary), and V3_TAL / V3_ATO (VI 2750 / 3500, fed
        // by the host only within ~20 s of their crossing: the third out of a 3EO TAL / ATO WAITS for them, a pick released at the crossing + its offset).
        public const double V3AtoOff1 = 0.5, V3AtoOff2 = 1.5;   // s: the 3EO ATO's third out after the VI 3500 crossing (the window between 3500 and MECO is ~4 s)
        public static bool IsBackboneMark(string n)
        {
            switch (n) { case "ABORT_TAL": case "ABORT_ATO": case "ABORT_RTLS": case "GREEN_2EO": case "GREEN_2EO_END": case "SRB_SEP": case "TAL_2EO": case "V3_TAL": case "V3_ATO": case "TAL_OPEN": case "ATO_OPEN": case "GREEN_OPEN": case "GREEN3_OPEN": case "RTLS_2EO_GREEN": case "RTLS_2EO_BLUE": case "MECO": case "MECO_NEAR": case "S2_LATE": return true; }
            return false;
        }
        public const double V3Gap = 8;                       // s: the shortest gap between the outs of one backbone (the planner's own pacing; the 1st -> 2nd of the old modes is 20+)
        public const double Green2Off2 = 18;                 // The longest offset (s) of the 2EO GREEN's out 2 after GREEN_OPEN
        public const double BlueSpread = 8;                  // s of spread on the stage 2 floor of a BLUE outcome
        public const double Green3Off1 = 1, Green3Off2 = 3, Green3SuddenShare = 0.5;      // The 3EO GREEN's out 2 after GREEN_OPEN (s) and the share of flights whose out 3 follows it at once (a sudden 2 of 3)
        void TryPlan(FailState s, double now)
        {
            if (Bb != 0 || Prog != "OPS1") return;
            int oc = Outcome(s);
            if (oc == OcOrbit) { Bb = 1; return; }
            if (oc >= OcBlue2) { PlanMulti(s, oc, now); return; }
            // The abort marks the host feeds from the PAD (ABORT_TAL / ABORT_ATO / ABORT_RTLS, GREEN_2EO) are
            // predictions (mark - vi) / ac, 3-5x too early. A window planned as "TAL open + 2 s" from one fires BEFORE the real TAL opens, a window after "ATO open" before ATO opens, and so on.
            // An out that must come AFTER a boundary now waits for the REAL crossing (TAL_OPEN / ATO_OPEN / TAL_2EO / GREEN_OPEN, fed by the host at the crossing); the planned (early) edges only
            // size its offset window (a window shorter than the real one is the safe error). An out that must come BEFORE a boundary (the RTLS's) keeps the early prediction: early is safe there.
            double lo1 = 0, hi1 = 0, o1 = 0, o2 = 0;
            string mk1 = "";
            switch (oc)
            {
                case OcRtls:                                    // TAL still closed: RTLS is the only mode open (before a boundary: the early prediction is the safe error)
                    if (edgeTal <= 0) return;
                    lo1 = now; hi1 = edgeTal - 15; break;
                case OcAoa:                                     // just after ATO opens (the low-energy end of its window)
                    if (edgeAto <= 0 || edgeRtn <= 0) return;
                    mk1 = "ATO_OPEN"; o1 = 5; o2 = Math.Max(10, 0.3 * (edgeRtn - edgeAto)); break;
                case OcGreen:                                   // the first engine out after TAL opens and before the window; the second inside it
                    if (edgeTal <= 0 || greenLo <= 0 || greenHi <= 0) return;
                    mk1 = "TAL_OPEN"; o1 = 2; o2 = Math.Max(6, greenLo - 40 - edgeTal); break;
                default:                                        // OcTal1 / OcTal2: TAL open, ATO not yet (the auto waits 15 s for TAL)
                    if (edgeTal <= 0 || edgeAto <= 0) return;
                    mk1 = "TAL_OPEN"; o1 = 2;
                    // (edgeAto - edgeTal) is the pad's prediction, 3-5x short of the real TAL window (~60 s: TAL open MET 18,
                    // ATO open ~79): the offset window is 3x it, capped at 45 s, so the out is spread inside the window, not just after the mark
                    o2 = Math.Min(45, Math.Max(6, 3 * (edgeAto - edgeTal) - 15)); break;
            }
            string src = "BACKBONE " + (Is2eo(oc) ? "2EO " : "1EO ") + OcName[oc];
            int b0 = Pending.Count;
            if (mk1.Length == 0)
            {
                Win(ref lo1, ref hi1, now);
                AddBb(s, src, lo1, hi1, "");
                DressBackbone(s, oc, b0, lo1, hi1, now);
            }
            else
            {
                AddBbOff(s, src, o1, o2, "");                   // drawn in OFFSET space (s after the mark): the dressing moves inside [o1, o2] the same way, then AnchorTo makes waits of them
                DressBackbone(s, oc, b0, o1, o2, 0, true);
                AnchorTo(b0, mk1, now);
            }
            if (Is2eo(oc))
            {
                string first = Pending.Count > b0 ? Pending[b0].Target : "";
                int b1 = Pending.Count;
                string mk2 = oc == OcGreen ? "GREEN_OPEN" : "TAL_2EO";                                // the second: inside the GREEN window / after the 2EO TAL boundary, both REAL crossings
                // The 2EO GREEN's out 2 stays well inside the window the host kept >= 60 m/s ahead (<= 18 s after the mark
                // = <= 54 m/s at 3 m/s2; the old pad-sized 5..156 s could land after the window closed)
                double p1 = oc == OcGreen ? 3 : 2, p2 = oc == OcGreen ? Math.Min(Green2Off2, Math.Max(10, greenHi - greenLo - 10)) : 15;
                if (Pending.Count > b0) { AddBbOff(s, src, p1, p2, first); AnchorTo(b1, mk2, now); }
            }
            Bb = 1;
        }

        // The backbone outs drawn in OFFSET space (Due = s after a mark) turned into real dues (the mark already crossed) or waits (Point(mark) releases them at the crossing + offset)
        double AddBbOff(FailState s, string src, double o1, double o2, string notThis)
        {
            if (!Flyable("MPS 01")) return -1;
            var ok = new List<string>();
            foreach (string t in Ssme) if (t != notThis && s.IndexOf("MPS 01", t) < 0) ok.Add(t);
            if (ok.Count == 0) return -1;
            string tg = Pick(ok.ToArray(), Draw(s));
            double off = o1 + Draw(s) * (o2 - o1);
            Pending.Add(new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = off, Expire = off + PickLife, Src = src });
            return off;
        }
        void AnchorTo(int b0, string mark, double now)
        {
            double ed = EdgeOf(mark);
            for (int k = b0; k < Pending.Count; k++)
            {
                SimPick p = Pending[k];
                double off = p.Due;
                if (ed > 0) { p.Due = Math.Max(now + 3, ed + off); p.Expire = p.Due + PickLife; }
                else { p.Wait = mark + ":" + D(off); p.Due = p.Expire = 1e18; }
            }
        }
        // an engine out that follows the one before it (the earlier backbone MPS 01 still pending) by off1..off2 s, and not before notBefore (UT, 0 = none): "AFTER:off:notBefore", released in Due()
        void AddOutChain(FailState s, string src, double off1, double off2, double notBefore, List<string> excl, int opt, double now)
        {
            if (!Flyable("MPS 01")) return;
            var ok = new List<string>();
            foreach (string t in Ssme) if (!excl.Contains(t) && s.IndexOf("MPS 01", t) < 0) ok.Add(t);
            if (ok.Count == 0) return;
            string tg = Pick(ok.ToArray(), Draw(s));
            double off = off1 + Draw(s) * (off2 - off1);
            Pending.Add(new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = 1e18, Expire = 1e18, Src = src, Opt = opt, Wait = "AFTER:" + D(off) + ":" + D(notBefore) });
            excl.Add(tg);
        }

        // one engine out of a multi-out outcome: the SSME not in excl and not out yet, due in [lo, hi] (>= minDue); returns its due (-1 = none left)
        double AddOut(FailState s, string src, double lo, double hi, List<string> excl, double minDue, int opt, double now)
        {
            if (!Flyable("MPS 01")) return -1;
            var ok = new List<string>();
            foreach (string t in Ssme) if (!excl.Contains(t) && s.IndexOf("MPS 01", t) < 0) ok.Add(t);
            if (ok.Count == 0) return -1;
            if (lo < minDue) lo = minDue;
            Win(ref lo, ref hi, now);
            string tg = Pick(ok.ToArray(), Draw(s));
            double due = lo + Draw(s) * (hi - lo);
            Pending.Add(new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = due, Expire = due + PickLife, Src = src, Opt = opt });
            excl.Add(tg);
            return due;
        }
        // an out that waits for a mark the host feeds near its crossing (TAL_2EO, V3_TAL / V3_ATO): released at the crossing + off1..off2 s (a mark already fed: due at once, fixed)
        // TAL_OPEN / ATO_OPEN = the ACTUAL crossing of the TAL / ATO mark (the host feeds them when the VI passes it): the first out of a 3EO TAL / ATO waits for it
        double EdgeOf(string mark) { return mark == "TAL_2EO" ? edgeT2 : (mark == "V3_TAL" ? edgeV3T : (mark == "V3_ATO" ? EdgeAtoOut() : (mark == "TAL_OPEN" ? edgeTo : (mark == "ATO_OPEN" ? edgeAo : (mark == "GREEN_OPEN" ? edgeGo : (mark == "GREEN3_OPEN" ? edgeG3 : (mark == "RTLS_2EO_GREEN" ? edgeR2G : (mark == "RTLS_2EO_BLUE" ? edgeR2B : -1)))))))); }
        // The ATO's third out
        // also waits for MECO_NEAR (the host feeds it ~40 m/s of VI before the flight's OWN MECO target, ops1q asc_simPts), so it lands before MECO on any 2EO TAL. The
        // earlier of the two marks releases it (a flight to VI >= 3548 crosses 3500 first).
        // A forced 3EO ATO whose 2EO TAL cuts off under VI 3500 (the third out released by MECO_NEAR, V3_ATO never crossed) is flown as a 3EO TAL: the outcome name
        // (SIMOUTCOME) and the picks' Src say so. Once.
        public string OcLabel = "";
        void Relabel3EoAto()
        {
            if (OcLabel.Length > 0) return;
            OcLabel = OcName[OcTal3];
            foreach (SimPick q in Pending) if (q.Src != null) q.Src = q.Src.Replace(OcName[OcAto3], OcName[OcTal3]);
        }
        double EdgeAtoOut() { return edgeV3A > 0 && edgeMn > 0 ? Math.Min(edgeV3A, edgeMn) : Math.Max(edgeV3A, edgeMn); }
        void AddOutWait(FailState s, string src, string mark, double off1, double off2, List<string> excl, int opt, double now)
        {
            if (!Flyable("MPS 01")) return;
            var ok = new List<string>();
            foreach (string t in Ssme) if (!excl.Contains(t) && s.IndexOf("MPS 01", t) < 0) ok.Add(t);
            if (ok.Count == 0) return;
            string tg = Pick(ok.ToArray(), Draw(s));
            double off = off1 + Draw(s) * (off2 - off1);
            double ed = EdgeOf(mark);
            SimPick p;
            if (ed > 0)
            {
                double due = Math.Max(now + 3, ed + off);
                p = new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = due, Expire = due + PickLife, Src = src, Opt = opt };
            }
            else p = new SimPick { Code = "MPS 01", Target = tg, Value = "", Mode = "P", Due = 1e18, Expire = 1e18, Src = src, Opt = opt, Wait = mark + ":" + D(off) };
            Pending.Add(p);
            excl.Add(tg);
        }

        // 2EO BLUE / SPLITS and every 3EO outcome. The windows come from the marks; a mark that never arrives (an older host) leaves the plan unmade (the host's SIMREACH keeps such an outcome off).
        void PlanMulti(FailState s, int oc, double now)
        {
            if (edgeSrb <= 0) return;                                           // every one of these needs the stage 1 / 2 boundary
            int n = EoOf(oc);
            string src = "BACKBONE " + n + "EO " + OcName[oc];
            var ex = new List<string>();
            double lo1, hi1, t1, t2;
            switch (oc)
            {
                case OcSplit2:
                case OcSplit3:                                                  // every out inside stage 1: the second (and third) out before the SRB sep = SPLITS
                    lo1 = now; hi1 = edgeSrb - V3Gap * (n + 1) - 6;
                    t1 = AddOut(s, src, lo1, hi1, ex, 0, 0, now);
                    if (t1 < 0) { Bb = 1; return; }
                    t2 = AddOut(s, src, t1 + V3Gap, Math.Max(t1 + V3Gap + 5, edgeSrb - V3Gap * (n - 1) - 4), ex, 0, 0, now);
                    if (n == 3 && t2 >= 0) AddOut(s, src, t2 + V3Gap, Math.Max(t2 + V3Gap + 5, edgeSrb - 4), ex, 0, OptThird, now);
                    break;
                case OcBlue2:                                                   // TAL open, the second out in stage 2 before any 2EO mode opens (the GREEN window / the 2EO TAL boundary)
                case OcBlue3:                                                   // the same for all three, close together
                    {
                        // out 1 waits for the REAL TAL open (TAL_OPEN +2..12; the pad's ABORT_TAL is 3-5x early: out 1 came at MET 12 in the SRB burn). Out 2 follows out 1 by 15..30 s (3EO: 12..20 and the third
                        // 8..16 s later) and not before the SRB sep + 3 (stage 2); the GREEN window / 2EO TAL boundary are far later than that (the planner's old caps were the early predictions). No TAL mark (a
                        // launch with none): the old stage 1 / 2 anchored out 1.
                        double b3lo = edgeSrb + 3;
                        int pb = Pending.Count;
                        if (edgeTal > 0) AddOutWait(s, src, "TAL_OPEN", 2, 12, ex, 0, now);
                        else
                        {
                            lo1 = Math.Max(now, edgeSrb + 2); hi1 = lo1 + 10;
                            AddOut(s, src, lo1, hi1, ex, 0, 0, now);
                        }
                        if (Pending.Count == pb) { Bb = 1; return; }
                        // out 1 (+15..30 s) lands before the SRB sep, so out 2 sat on the stage 2 floor (SRB sep + 3); the floor is now spread over 0..8 s
                        // (the BLUE zone ends where the first 2EO mode opens, ~MET 95-100, 15 s after the sep)
                        AddOutChain(s, src, n == 3 ? 12 : 15, n == 3 ? 20 : 30, b3lo + Draw(s) * BlueSpread, ex, 0, now);
                        if (n == 3) AddOutChain(s, src, V3Gap, V3Gap + 8, 0, ex, OptThird, now);
                        break;
                    }
                case OcRtls2G:                                                  // The RTLS variants of 2EO GREEN / 2EO BLUE: out 1 before TAL opens (the 1EO auto picks the RTLS), out 2 INSIDE the RTLS
                case OcRtls2B:                                                  // while the RTLS 2EO line shows the variant's colour: ops1q feeds RTLS_2EO_GREEN (the pitcharound and the flyback: a runway is made) /
                    {                                                           // RTLS_2EO_BLUE (the fuel dissipation: the contingency's mode 2 from the far side, no runway end) at the window's true start
                        if (edgeTal <= 0) return;
                        lo1 = now; hi1 = edgeTal - 15;
                        Win(ref lo1, ref hi1, now);
                        t1 = AddOut(s, src, lo1, hi1, ex, 0, 0, now);
                        if (t1 < 0) { Bb = 1; return; }
                        AddOutWait(s, src, oc == OcRtls2G ? "RTLS_2EO_GREEN" : "RTLS_2EO_BLUE", Rtls2Off1, Rtls2Off2, ex, 0, now);
                        break;
                    }
                case OcRtls3:                                                   // RTLS selected early (the first out before TAL opens), the 2nd and 3rd inside the RTLS (stage 2, before negative return)
                    {
                        if (edgeTal <= 0) return;
                        double cap = edgeRtn > 0 ? edgeRtn - 12 : edgeSrb + 80;
                        lo1 = now; hi1 = edgeTal - 15;
                        Win(ref lo1, ref hi1, now);
                        t1 = AddOut(s, src, lo1, hi1, ex, 0, 0, now);
                        if (t1 < 0) { Bb = 1; return; }
                        double lo2 = Math.Max(edgeSrb + 3, t1 + 20);
                        t2 = AddOut(s, src, lo2, Math.Min(cap - 12, lo2 + 25), ex, 0, 0, now);
                        if (t2 >= 0) AddOut(s, src, t2 + 10, Math.Min(cap, t2 + 30), ex, 0, OptThird, now);
                        break;
                    }
                case OcGreen3:                                                  // out 1 after TAL opens, out 2 and out 3 INSIDE the window
                    {
                        if (edgeTal <= 0 || greenLo <= 0 || greenHi <= 0) return;
                        // out 1 waits for the REAL TAL open (+2..), the early pad edges only size the offsets.
                        // out 2 was chained 15..30 s after out 1 with only the SRB sep floor, so it
                        // came at SRB sep + 10 (MET 90, VI 834) BEFORE the window opened: 2EO CONT MODE 1 BLUE, no GREEN. THE OWNER 11-14: "Wait for GREEN, or do a sudden 2/3 engine out at the 3EO GREEN
                        // line. Be aware that the 3EO GREEN boundary is optimistic, so SimSup should schedule it so you can really make it back." Now out 2 waits for GREEN_OPEN (+Green3Off1..2: a few s
                        // inside the window, the host feeds the mark 10 m/s inside it with >= 60 m/s ahead), and out 3 is either chained 8..12 s later ("wait for GREEN": the 2EO flies a moment) or
                        // follows it within 0.3..1.5 s (a SUDDEN 2 of 3: out 2 and out 3 at the line). The whole thing ends <= 15 s after the mark = <= 45 m/s at 3 m/s2 of the >= 60 m/s kept ahead.
                        int pb = Pending.Count;
                        AddOutWait(s, src, "TAL_OPEN", 2, Math.Max(8, greenLo - 60 - edgeTal), ex, 0, now);
                        if (Pending.Count == pb) { Bb = 1; return; }
                        // . THE OWNER 11-14: "the 3EO GREEN
                        // boundary is optimistic, so SimSup should schedule it so you can really make it back." Out 2 now waits for GREEN3_OPEN: the host (ops1q) feeds it at the crossing of the first EARLY-MECO
                        // window + ASC_SIM_GREEN3_IN m/s (65), never closer than ASC_SIM_GREEN3_END m/s (50) to the window's end.
                        AddOutWait(s, src, "GREEN3_OPEN", Green3Off1, Green3Off2, ex, 0, now);
                        bool sudden = Draw(s) < Green3SuddenShare;
                        if (sudden) AddOutChain(s, src, 0.3, 1.5, 0, ex, OptThird, now);
                        else AddOutChain(s, src, V3Gap, V3Gap + 4, 0, ex, OptThird, now);
                        break;
                    }
                case OcTal3:                                                    // TAL open: the 1st in the TAL window, the 2nd waits for the 2EO TAL boundary (TAL_2EO), the 3rd for VI 2750 (V3_TAL)
                case OcAto3:                                                    // ATO open: the 1st in the ATO window, the 2nd waits for TAL_2EO, the 3rd for VI 3500 (V3_ATO)
                    {
                        if (edgeTal <= 0 || edgeAto <= 0) return;
                        if (oc == OcAto3 && edgeRtn <= 0) return;
                        // The pad's edge predictions (ac at liftoff,
                        // 5x the real speed gain) put the TAL window far too early. The 1st out now waits for the ACTUAL crossing of the TAL mark (TAL_OPEN: TAL open, ATO not yet)
                        // or the ATO mark (ATO_OPEN), +2..20 / +5..25 s, fed by the host when the VI passes it
                        int pb = Pending.Count;
                        AddOutWait(s, src, oc == OcTal3 ? "TAL_OPEN" : "ATO_OPEN", oc == OcTal3 ? 2 : 5, oc == OcTal3 ? 20 : 25, ex, 0, now);
                        if (Pending.Count == pb) { Bb = 1; return; }
                        AddOutWait(s, src, "TAL_2EO", 3, 20, ex, 0, now);                                  // the second waits for the 2EO TAL boundary (the host feeds it near its crossing: early predictions are poor)
                        // VI 3500 is crossed only ~4 s before MECO (one engine, MECO at v_orb 3548: 3500 at MET 508.8, MECO 512.5),
                        // so the old crossing + 4..25 s landed after MECO and the flight was a 2EO TAL. The ATO's third out now follows its crossing by 0.5..1.5 s; the TAL's (VI 2750, minutes of burn left) keeps 3..18 s.
                        AddOutWait(s, src, oc == OcTal3 ? "V3_TAL" : "V3_ATO", oc == OcTal3 ? 3 : V3AtoOff1, oc == OcTal3 ? 18 : V3AtoOff2, ex, OptThird, now);
                        break;
                    }
                default: Bb = 1; return;
            }
            Bb = 1;                                                              // no DYING ENGINE / COMPOUND OUT dressing on these (the outs are already close together)
        }

        void Add(string code, string tg, string vl, string md, double due, string src)
        {
            Pending.Add(new SimPick { Code = code, Target = tg, Value = vl, Mode = md, Due = due, Expire = due + PickLife, Src = src, Opt = Prog == "OPS1" && code == "MPS 03" ? OptGimbalCtl : 0 });
        }

        // ================================================================ SCENARIOS
        static bool IsScen(SimPick p) { return p.Src != null && p.Src.StartsWith("SCENARIO", StringComparison.Ordinal); }
        static List<SimStep> Active(SimTemplate t, int lv) { var l = new List<SimStep>(); foreach (SimStep st in t.Steps) if (lv >= st.MinLevel && !(NoPilot && (st.Opt & OptPilotOnly) != 0) && !(st.Code == "FCS 01" && st.Mode != "T" && RudderOnly(st.Target) && !RudderOk(lv))) l.Add(st); return l; }     // A step that can only freeze a rudder half is not played below BRUTAL / with no pilot (SPEEDBRAKE HALF has no step left = never starts; STIFF ELEVON keeps its elevon)     // OptPilotOnly steps are not played with no pilot
        double MapEdge(double edgeUt, double now, double vn) { return VrClock ? vn + (edgeUt - now) * ClockRate : edgeUt + vn - now; }

        // can t start at this anchor now? (cheap filters; StartScenario's floor preview is the rest)
        bool ScenEligible(FailState s, SimTemplate t, string anchor, string phase, int lv)
        {
            if (!t.At(anchor) || lv < t.MinLevel || Started.Contains(t.Name)) return false;
            if (t.Progs.Length > 0 && (" " + t.Progs + " ").IndexOf(" " + Prog + " ", StringComparison.Ordinal) < 0) return false;
            if (t.Rev > 0 && RevSeen != t.Rev) return false;
            if (t.OrbitOnly && (Prog != "OPS1" || Outcome(s) != OcOrbit)) return false;
            List<SimStep> act = Active(t, lv);
            if (act.Count == 0 || act.Count > Room(s)) return false;
            int sw3 = 0;                                       // SW 03 stays <= Sw03FlightMax a flight, the scripted ones too (the fires + the picks waiting + this script's steps)
            foreach (SimStep st in act) if (st.Code == "SW 03") sw3++;
            if (sw3 > 0) { foreach (SimPick q in Pending) if (q.Code == "SW 03") sw3++; if (FiresOf("SW 03") + sw3 > Sw03FlightMax) return false; }
            foreach (SimStep st in act)
                if (!Flyable(st.Code) || ScenTargets(Prog, st.Code, phase).Length == 0 || (FinalBlocked(st.Code) && InFinal(Prog, phase))) return false;
            return true;
        }

        // start t: resolve every step, preview the floors in order (a refused step sinks the scenario unless it is Soft), then schedule. Returns the picks added (0 = not started).
        int StartScenario(FailState s, SimTemplate t, double vn, double edgeUt, string phase, int lv, double now)
        {
            List<SimStep> act = Active(t, lv);
            int m = act.Count;
            var tgs = new string[m]; var vls = new string[m]; var mds = new string[m]; var offs = new double[m];
            // pass 1: the targets, values and modes (against the real list only)
            for (int i = 0; i < m; i++)
            {
                SimStep st = act[i];
                tgs[i] = vls[i] = mds[i] = "";
                string spec = st.Target, own = "", tg, vl, md;
                if (spec.Length == 2 && (spec[0] == '=' || spec[0] == '~'))
                {
                    int k = spec[1] - '0';
                    own = k >= 0 && k < i ? tgs[k] : "";
                    spec = spec.Substring(0, 1);
                    if (own.Length == 0) { if (st.IsSoft) continue; return 0; }
                }
                if (!Resolve(s, st.Code, spec, own, phase, out tg, out vl, out md, true)) { if (st.IsSoft) continue; return 0; }
                if (st.Value.Length > 0) vl = st.Value;
                if (st.Mode.Length > 0 && ModesOf(st.Code).IndexOf(st.Mode, StringComparison.Ordinal) >= 0) md = st.Mode;
                tgs[i] = tg; vls[i] = vl; mds[i] = md;
                offs[i] = st.Offset + (st.Spread > 0 ? Draw(s) * st.Spread : 0);
            }
            // pass 2: the floors, in script order, each step on top of the ones before it (a Soft step is decided when it fires: it may repeat a step the crew will have fixed by then)
            var added = new List<FailEntry>();
            bool ok = true;
            try
            {
                for (int i = 0; i < m && ok; i++)
                {
                    SimStep st = act[i];
                    if (st.IsSoft || tgs[i].Length == 0) continue;
                    string why = ChkI(s, Prog, st.Code, tgs[i], mds[i], lv, now, false, st.Opt, vls[i]);
                    if (why.Length > 0 && mds[i] == "P" && ModesOf(st.Code) == "PT" && st.Mode.Length == 0 && ChkI(s, Prog, st.Code, tgs[i], "T", lv, now, false, st.Opt, vls[i]).Length == 0) { mds[i] = "T"; why = ""; }
                    if (why.Length > 0) { LastWhy = "SCENARIO " + t.Name + ": " + why; ok = false; break; }
                    var fe = new FailEntry { Code = st.Code, Target = tgs[i], Value = vls[i], Mode = mds[i], At = now, HealAt = -1, Via = "" };
                    s.List.Add(fe); added.Add(fe);
                }
            }
            finally { foreach (FailEntry fe in added) s.List.Remove(fe); }
            if (!ok) return 0;
            int n = 0;
            for (int i = 0; i < m; i++)
            {
                if (tgs[i].Length == 0) continue;
                SimStep st = act[i];
                var p = new SimPick { Code = st.Code, Target = tgs[i], Value = vls[i], Mode = mds[i], Src = "SCENARIO " + t.Name, Opt = st.Opt };
                if (st.WaitPoint.Length > 0) { p.Wait = st.WaitPoint + ":" + D(offs[i]); p.Due = p.Expire = 1e18; }
                else { p.Due = Math.Max(vn, edgeUt + offs[i]); p.Expire = p.Due + PickLife; }
                Pending.Add(p);
                n++;
            }
            if (n > 0) Started.Add(t.Name);
            return n;
        }

        // the 20 % roll at a decision point (anchor = its name) or on the random clock (anchor "*"): returns the picks of the scenario it started, 0 = none (the caller picks a random failure)
        int TryScenario(FailState s, string anchor, double vn, double edgeUt, string phase, int lv, double now)
        {
            var ts = new List<SimTemplate>();
            foreach (SimTemplate t in Templates) if (ScenEligible(s, t, anchor, phase, lv)) ts.Add(t);
            if (ts.Count == 0) return 0;                       // nothing eligible: no roll, the random failure
            if (Draw(s) >= ScenarioShare) return 0;
            while (ts.Count > 0)                               // the first drawn scenario the floors would not refuse (as the single picks do); none = the random failure
            {
                SimTemplate t = Pick(ts.ToArray(), Draw(s));
                ts.Remove(t);
                int n = StartScenario(s, t, vn, edgeUt, phase, lv, now);
                if (n > 0) return n;
            }
            return 0;
        }

        // the scenario `name` started at its anchor without the 20 % roll (the offline tests, a host that forces one): the picks scheduled, 0 = not eligible now / a floor refuses it
        public int StartNamed(FailState s, string name, double edgeUt, double now, string phase)
        {
            if (!s.Latched || Prog.Length == 0) return 0;
            int lv = Clamp(s.Difficulty);
            phase = (phase ?? "").Trim().ToUpperInvariant();
            foreach (SimTemplate t in Templates)
            {
                if (t.Name != name) continue;
                if (!ScenEligible(s, t, t.Point.Split(' ')[0], phase, lv)) return 0;
                double vn = VClock(now, phase);
                return StartScenario(s, t, vn, t.Point == "*" ? vn : MapEdge(edgeUt <= 0 ? now : edgeUt, now, vn), phase, lv, now);
            }
            return 0;
        }

        // the backbone's engine out(s) planned (TryPlan): the 20 % roll dresses the FIRST out. DYING ENGINE (NORMAL+): the SSME fails gradually, a low-thrust line and a locked gimbal in random order
        // over 20-30 s, then the backbone's out on the SAME engine (the out keeps the backbone's window: it is moved only INSIDE [lo, hi], never past hi). COMPOUND OUT (HARD+, a one-engine
        // outcome only: the thrust floor has no room for it after a second out): the backbone's out, then a locked gimbal on ANOTHER SSME 20-40 s later (OptGimbalCtl: it costs control,
        // not thrust). The lead-ins / the follow-up are the backbone's own picks (Src BACKBONE: no spacing, no count of the phase's budget, no chain).
        void DressBackbone(FailState s, int oc, int b0, double lo, double hi, double now, bool anch = false)
        {
            int lv = Clamp(s.Difficulty);
            if (Pending.Count <= b0) return;
            var cand = new List<string>();
            if (lv >= DyingMin && Flyable("MPS 02") && Flyable("MPS 03") && !Started.Contains("DYING ENGINE")) cand.Add("DYING ENGINE");
            // COMPOUND OUT (a locked gimbal on another SSME after the out) is retired: an out plus a lock loses the stack's control (Check refuses the pair); the branch below stays dead
            if (cand.Count == 0) return;
            if (Draw(s) >= ScenarioShare) return;
            string name = Pick(cand.ToArray(), Draw(s));
            SimPick o = Pending[b0];
            if (name == "DYING ENGINE")
            {
                double len = 20 + 10 * Draw(s);                                     // the whole failure takes 20-30 s
                double a = Math.Max(lo, now + len + 3);
                // A window anchored to a REAL mark is in offset space and sized from the pad's early
                // predictions (3-5x short), so the 20-30 s lead-in never fitted; the real windows after the mark are >= AnchorRealMin s (TAL open -> ATO open ~60 s, ATO / GREEN longer), so the
                // lead-ins begin >= 3 s after the mark and the out may land up to len + 8 s (<= AnchorRealMin) after it
                if (anch && hi < len + 8) hi = Math.Min(AnchorRealMin, len + 8);
                if (hi - a < 3) return;                                              // no room before the window closes: the plain out
                double d = a + Draw(s) * (hi - a);
                bool lowFirst = Draw(s) < 0.5;
                string v = Pick(Values("MPS 02"), Draw(s));
                o.Due = d; o.Expire = d + PickLife; o.Opt |= OptSamePart; o.Src += " DYING ENGINE";
                Pending.Add(new SimPick { Code = lowFirst ? "MPS 02" : "MPS 03", Target = o.Target, Value = lowFirst ? v : "", Mode = "P", Due = d - len, Expire = d - len + PickLife, Src = "BACKBONE DYING ENGINE", Opt = OptSamePart | OptGimbalCtl });
                Pending.Add(new SimPick { Code = lowFirst ? "MPS 03" : "MPS 02", Target = o.Target, Value = lowFirst ? "" : v, Mode = "P", Due = d - 0.4 * len, Expire = d - 0.4 * len + PickLife, Src = "BACKBONE DYING ENGINE", Opt = OptSamePart | OptGimbalCtl });
            }
            else
            {
                var ok = new List<string>();
                foreach (string t in Ssme) if (t != o.Target && s.IndexOf("MPS 03", t) < 0) ok.Add(t);
                if (ok.Count == 0) return;
                double d = o.Due + 20 + 20 * Draw(s);
                o.Src += " COMPOUND OUT";
                Pending.Add(new SimPick { Code = "MPS 03", Target = Pick(ok.ToArray(), Draw(s)), Value = "", Mode = "P", Due = d, Expire = d + PickLife, Src = "BACKBONE COMPOUND OUT", Opt = OptGimbalCtl });
            }
            Started.Add(name);
        }
        public const int DyingMin = Normal, CompoundMin = Hard;
        public const double AnchorRealMin = 40;               // The shortest real window (s) after a TAL_OPEN / ATO_OPEN mark that a backbone out may use

        // a decision point: maybe schedule a pick (or a template) before / after the edge. Returns how many picks it scheduled.
        public int Point(FailState s, string name, double edgeUt, double now, string phase)
        {
            if (!s.Latched || Prog.Length == 0) return 0;
            int lv = Clamp(s.Difficulty);
            name = (name ?? "").Trim().ToUpperInvariant();
            phNow = (phase ?? "").Trim().ToUpperInvariant();
            if (Prog == "OPS1")                                 // the backbone's marks (UT): recorded, then the plan is tried
            {
                double ut = edgeUt > 0 ? edgeUt : now;
                if (name == "ABORT_TAL") edgeTal = ut;
                else if (name == "ABORT_ATO") edgeAto = ut;
                else if (name == "ABORT_RTLS") edgeRtn = ut;
                else if (name == "GREEN_2EO") greenLo = ut;
                else if (name == "GREEN_2EO_END") greenHi = ut;
                else if (name == "SRB_SEP") edgeSrb = ut;
                else if (name == "TAL_2EO") edgeT2 = ut;
                else if (name == "V3_TAL") edgeV3T = ut;
                else if (name == "V3_ATO") edgeV3A = ut;
                else if (name == "MECO_NEAR") edgeMn = ut;
                else if (name == "TAL_OPEN") edgeTo = ut;
                else if (name == "ATO_OPEN") edgeAo = ut;
                else if (name == "GREEN_OPEN") edgeGo = ut;
                else if (name == "GREEN3_OPEN") edgeG3 = ut;
                else if (name == "RTLS_2EO_GREEN") edgeR2G = ut;     // The RTLS 2EO line's colour crossings (ops1q: the live word)
                else if (name == "RTLS_2EO_BLUE") edgeR2B = ut;
                else if (name == "S2_LATE") edgeLate = ut;       // The late stage 2 of an ascent that lands from MECO (InFinal)
                if (name == "ABORT_TAL" || name == "ABORT_ATO" || name == "ABORT_RTLS" || name == "GREEN_2EO" || name == "GREEN_2EO_END" || name == "SRB_SEP" || name == "TAL_2EO") TryPlan(s, now);
            }
            if (name == "ROLL_REV") RevSeen++;                                    // The first / second reversal scenarios count them
            bool anyWait = false;
            foreach (SimPick w in Pending) if (w.Wait.Length > 0) anyWait = true;
            if (anyWait)
            {   // A scenario step waiting for this point (STIFF ELEVON's rudder at TAEM) is released: due at the edge + its offset
                double vw = VClock(now, phase);
                double ew = MapEdge(edgeUt > 0 ? edgeUt : now, now, vw);
                foreach (SimPick w in Pending)
                    if (w.Wait.StartsWith(name + ":", StringComparison.Ordinal) || (name == "MECO_NEAR" && w.Wait.StartsWith("V3_ATO:", StringComparison.Ordinal)))
                    {
                        double off; double.TryParse(w.Wait.Substring(w.Wait.IndexOf(':') + 1), NumberStyles.Float, CultureInfo.InvariantCulture, out off);
                        w.Due = Math.Max(vw, ew + off); w.Expire = w.Due + PickLife; w.Wait = "";
                        if (name == "MECO_NEAR" && edgeV3A <= 0) Relabel3EoAto();      // VI 3500 was never crossed: the flight is a 3EO TAL
                    }
            }
            SimPointDef p = null;
            foreach (SimPointDef q in Points) if (q.Name == name) p = q;
            if (p == null || lv < p.MinLevel || (" " + p.Progs + " ").IndexOf(" " + Prog + " ", StringComparison.Ordinal) < 0) return 0;
            if (Room(s) <= 0) return 0;
            if (edgeUt <= 0) edgeUt = now;
            double vn = VClock(now, phase);                                       // the pick clock; the edge keeps its distance from now on it
            edgeUt = MapEdge(edgeUt, now, vn);                                    // A future edge (EI, predicted) is mapped at the clock's rate now (the time part before EI), not 1:1
            if (Draw(s) >= PointP[lv]) return 0;
            // The 20 % roll: a SCENARIO anchored here (else the single random failure below)
            int ns = TryScenario(s, name, vn, edgeUt, phase, lv, now);
            if (ns > 0) return ns;
            // one pick from the point's candidates
            var cs = new List<string>();
            foreach (string c in p.Cands) { int a = c.IndexOf('@'); if (Flyable(c.Substring(0, a))) cs.Add(c); }
            string code = "", tgt = "", val = "", mod = "";
            bool got = false;
            while (cs.Count > 0 && !got)                       // The first drawn candidate the floors would not refuse
            {
                var pool = cs;                                 // On BRUTAL the candidates whose code has not fired yet come first
                if (lv >= Brutal && VarietyOn)
                {
                    var fresh = cs.FindAll(x => FiresOf(x.Substring(0, x.IndexOf('@'))) == 0);
                    if (fresh.Count > 0)
                    {
                        pool = fresh;
                        if (CoverMpsOn) { var scarce = fresh.FindAll(x => Prog == "OPS2" && x.StartsWith("OMS", StringComparison.Ordinal)); if (scarce.Count > 0) pool = scarce; }     // Only a point can draw them
                    }
                    else { var other = cs.FindAll(x => RecentW(x.Substring(0, x.IndexOf('@'))) == 1); if (other.Count > 0) pool = other; }     // none fresh: one that is not among the last fires
                }
                string cand = Pick(pool.ToArray(), Draw(s));
                cs.Remove(cand);
                int at = cand.IndexOf('@');
                code = cand.Substring(0, at);
                if (Resolve(s, code, cand.Substring(at + 1), "", phase, out tgt, out val, out mod) && Feasible(s, code, tgt, lv, now)) got = true;
            }
            if (!got) return 0;
            double lead = LeadLo[lv] + Draw(s) * (LeadHi[lv] - LeadLo[lv]);
            double due = p.Shift > 0 ? edgeUt + p.Shift + lead : edgeUt - lead;
            if (Prog == "OPS2" && p.Shift == 0 && code.StartsWith("OMS", StringComparison.Ordinal) && Draw(s) < 0.5)
                due = edgeUt + OrbitInLo + Draw(s) * (OrbitInHi - OrbitInLo);                 // inside the burn, x s after its TIG (after the quiet time)
            Add(code, tgt, val, mod, Math.Max(vn, due), "POINT " + name);
            return 1;
        }

        // can (code, target) be picked right now? (some mode of it passes the floors at this level; the pick's own Check at fire time still decides)
        bool Feasible(FailState s, string code, string tg, int lv, double now)
        {
            if (Prog == "OPS1" && code.StartsWith("MPS", StringComparison.Ordinal) && !CoverMps(s, code, lv)) return false;     // the backbone owns the engines (but see CoverMps)
            if (AtRepeatCap(s, code, tg) || AtPhaseCap(code, tg)) return false;

            string ms = ModesOf(code);
            if (ms.Length == 0) ms = "P";
            int fo = Prog == "OPS1" && code == "MPS 03" ? OptGimbalCtl : 0;                  // A drawn locked gimbal costs control, not thrust (as COMPOUND OUT's)
            foreach (char m in ms) if (ChkI(s, Prog, code, tg, m.ToString(), lv, now, false, fo).Length == 0) return true;
            return false;
        }

        // The measured gap was the ascent engines
        // (MPS 02 in 15 % of the BRUTAL flights, MPS 03 in 11 %: the random draw never took an SSME, the backbone owns them). A BRUTAL draw may now take a SSME that costs NO planned
        // out: MPS 02 (a throttle limit: thrust units 2.5, one more allowed) only on a flight the backbone draws as ORBIT (no out planned: the planned 2EO / 3EO needs every other
        // engine at full), MPS 03 (a locked gimbal, OptGimbalCtl: control, not thrust, one lock at most) on a flight with no out planned, or with ONE planned once that out stands (a lock
        // before it makes the planned out's own Check refuse it: the standing lock counts as a degraded engine). The planned out may still pick the degraded engine (its own out supersedes the degrade).
        public static bool CoverMpsOn = true;                 // the offline test switches it off to measure the old reach
        bool CoverMps(FailState s, string code, int lv)
        {
            if (!CoverMpsOn || lv < Brutal || !VarietyOn || code == "MPS 01") return false;
            int eo = EoOf(Outcome(s));
            if (eo == 0) return true;
            return false;                                           // A lock never goes with an out (Check), so MPS 03 only on a flight with no out planned (was: also a planned 1EO once its out stood)
        }

        // A BRUTAL draw favours the
        // codes that have not fired this flight (x VarietyNew) and tires of the ones that keep firing (1 / (1 + n / 2))
        public static double VarietyNew = 6;
        // The code that fired LAST is drawn at x VarietyLast, the other two of the last
        // VarietyMem fires at x VarietyRecent, whatever its count (the 1 / (1 + n / 2) tiredness is slow when only 3-4 codes are flyable, as on the ascent and in the entry)
        public const int VarietyMem = 3;
        public const double VarietyLast = 0.15, VarietyRecent = 0.5;
        public readonly List<string> Recent = new List<string>();      // runtime: the codes of the last VarietyMem fires (the backbone's apart), oldest first
        public static bool VarietyOn = true;       // the offline test switches it off to measure what the uniform draw gave
        int FiresOf(string code)
        {
            int n = 0;
            foreach (KeyValuePair<string, int> kv in Fired) if (kv.Key.StartsWith(code + "|", StringComparison.Ordinal)) n += kv.Value;
            return n;
        }
        double RecentW(string code)
        {
            int k = Recent.LastIndexOf(code);
            if (k < 0) return 1;
            return k == Recent.Count - 1 ? VarietyLast : VarietyRecent;
        }
        double VarietyW(string code) { if (!VarietyOn) return 1; int n = FiresOf(code); return (n == 0 ? VarietyNew : 1.0 / (1 + 0.5 * n)) * RecentW(code); }

        // the total hazard (per s, at x1) of the codes flyable now and the (code, target) it lands on for a draw u in [0, 1)
        double HazardNow(FailState s, string prog, HashSet<string> codes, string phase, double u, out string code, out string tg, int floorLv = 0, double now = 0)
        {
            code = tg = "";
            double tot = 0;
            var cs = new List<string>(); var ts = new List<string>(); var ws = new List<double>();
            foreach (FailCode fc in FailState.Table)
            {
                if (!codes.Contains(fc.Code)) continue;
                double h = Hazard(prog, fc.Code) / 100.0;
                if (floorLv >= Brutal) h *= (fc.Modes == "T" ? BrutalTransientW : (fc.Modes.IndexOf('P') >= 0 ? BrutalPermW : 1)) * VarietyW(fc.Code);     // BRUTAL: fewer transient-only codes, more of those that can be permanent; the codes not yet fired first
                if (h <= 0) continue;
                string[] tl = FinalBlocked(fc.Code) && InFinal(prog, phase) ? new string[0] : Targets(prog, fc.Code, phase);     // nothing that takes the DAP / guidance on the final
                double hc = floorLv >= Brutal && VarietyOn && tl.Length > 1 ? h / tl.Length : h;     // BRUTAL weighs a CODE, not its targets (DPS 02 has five GPCs, SW 03 one page)
                int c0n = cs.Count; double rw = 0, ow = 0;       // This code's entries (the FCS 01 weights are re-split below)
                foreach (string t in tl)
                {
                    h = hc;
                    if (s.IndexOf(fc.Code, t) >= 0) continue;
                    if (RudderRule(fc.Code) && IsRudder(t) && !RudderOk(floorLv > 0 ? floorLv : Clamp(s.Difficulty))) continue;       // No rudder half below BRUTAL / with no pilot
                    if (floorLv > 0 && prog == "OPS2" && fc.Code.StartsWith("OMS", StringComparison.Ordinal)) continue;     // the burns' points own the OMS engines
                    if (floorLv > 0 && !Feasible(s, fc.Code, t, floorLv, now)) continue;       // SimSup's own draws skip what the floors would refuse
                    cs.Add(fc.Code); ts.Add(t); ws.Add(h); tot += h;
                }
                if (RudderRule(fc.Code))      // With rudder halves in the list (BRUTAL, a pilot) they take RudderShare of this code's weight together, the surfaces the rest (the code's total is unchanged)
                {
                    for (int i = c0n; i < ws.Count; i++) { if (IsRudder(ts[i])) rw += ws[i]; else ow += ws[i]; }
                    if (rw > 0 && ow > 0)
                        for (int i = c0n; i < ws.Count; i++) ws[i] *= IsRudder(ts[i]) ? RudderShare * (rw + ow) / rw : (1.0 - RudderShare) * (rw + ow) / ow;
                }
            }
            if (u >= 0 && tot > 0)
            {
                double x = u * tot;
                for (int i = 0; i < ws.Count; i++) { x -= ws[i]; if (x < 0 || i == ws.Count - 1) { code = cs[i]; tg = ts[i]; break; } }
            }
            return tot;
        }

        // The random draw; nothing drawn only because of the phase cap = a new round for this phase (the same u, no extra draw), kept only if it frees something
        void DrawRand(FailState s, HashSet<string> fly, string phase, int lv, double now, out string c0, out string t0)
        {
            double u = Draw(s);
            HazardNow(s, Prog, fly, phase, u, out c0, out t0, lv, now);
            if (c0.Length > 0 || now - LastFire < QuietRound) return;
            string pk = PhKey(phase); int rd; PhRound.TryGetValue(pk, out rd);
            PhRound[pk] = rd + 1;
            HazardNow(s, Prog, fly, phase, u, out c0, out t0, lv, now);
            if (c0.Length == 0) { if (rd == 0) PhRound.Remove(pk); else PhRound[pk] = rd; }
        }

        // each host tick while latched: the random-time clock, then the first due pick that passes. "" or "code|target|value|mode".
        public string Tick(FailState s, double now, double tig, string phase, bool randOk, double dt)
        {
            if (!s.Latched || Prog.Length == 0) return "";
            int lv = Clamp(s.Difficulty);
            phase = (phase ?? "").Trim().ToUpperInvariant();
            phNow = phase;
            // random-time picks (plan section 6: a fraction of RAND x1, always below it)
            double step0 = lastTickNow > 0 ? Math.Min(Math.Max(now - lastTickNow, 0), 300) : 0;
            lastTickNow = now;
            double vn = VClock(now, phase);                                       // the pick clock (= now outside the VR-keyed entry)
            double vstep = lastVn >= 0 ? Math.Min(Math.Max(vn - lastVn, 0), 60) : 0;
            lastVn = vn;
            if (Prog == "OPS3" && Alt > 0 && Alt <= EiAlt) eiSeen = true;         // EI reached
            if (PreEi)
            {   // Before EI nothing fires: no random try, no offer; the waiting picks keep their distance on the clock (they fall due after EI as planned)
                foreach (SimPick w in Pending) if (w.Wait.Length == 0) { w.Due += vstep; w.Expire += vstep; }
                return "";
            }
            if ((randOk || Ph == PhOrbit) && dt > 0 && Room(s) > 0)
            {
                string c0, t0;
                var fly = new HashSet<string>();
                foreach (string c in Codes) if (Workaround.ContainsKey(c)) fly.Add(c);
                double step = Ph == PhOrbit ? step0 : (Ph == PhEntry && vr0 > 0 ? vstep : Math.Min(dt, 5));     // orbit: game seconds since the last tick (a warp counts); entry: virtual (blended-clock) seconds
                if (lv >= Brutal)
                {   // The SLOT CLOCK: one try per BrutalSlot of the phase's random-clock time, at a random moment of its slot (even on average, random, double-ups possible)
                    PhaseT[Ph] += step;
                    double slot = BrutalSlot[Ph];
                    if (SlotAt < 0)
                    {
                        double u0 = Draw(s); double k0 = Math.Floor(PhaseT[Ph] / slot);
                        SlotAt = (k0 + u0) * slot;
                        if (SlotAt <= PhaseT[Ph]) SlotAt = (k0 + 1 + u0) * slot;
                    }
                    if (PhaseT[Ph] >= SlotAt)
                    {
                        SlotAt = (Math.Floor(SlotAt / slot) + 1 + Draw(s)) * slot;
                        if (DueSpice(vn) < BrutalBacklog)
                        {
                            if (TryScenario(s, "*", vn, vn, phase, lv, now) == 0)       // 20 % a scenario anywhere (DARK DECK, LEAKY POD), else the random failure
                            {
                            DrawRand(s, fly, phase, lv, now, out c0, out t0);
                            string tg, vl, md;
                            if (c0.Length > 0 && Resolve(s, c0, t0, "", phase, out tg, out vl, out md)) Add(c0, tg, vl, md, vn, "RANDOM");
                            }
                        }
                    }
                }
                else
                {
                if (E <= 0) E = -Math.Log(1.0 - Draw(s));
                Acc += Math.Max(HazardNow(s, Prog, fly, phase, -1, out c0, out t0, lv, now) * RandFrac[lv], Pace(s, lv)) * step;
                PhaseT[Ph] += step;
                if (Acc >= E)
                {
                    Acc = 0; E = -Math.Log(1.0 - Draw(s));
                    if (TryScenario(s, "*", vn, vn, phase, lv, now) == 0)               // 20 % a scenario anywhere, else the random failure
                    {
                    DrawRand(s, fly, phase, lv, now, out c0, out t0);
                    string tg, vl, md;
                    if (c0.Length > 0 && Resolve(s, c0, t0, "", phase, out tg, out vl, out md)) Add(c0, tg, vl, md, vn, "RANDOM");
                    }
                }
                }
            }
            // the due picks, oldest first
            for (int pass = 0; pass < 2; pass++)                   // The backbone's engine outs first, so a refused spice pick never blocks them
            for (int i = 0; i < Pending.Count; i++)
            {
                SimPick p = Pending[i];
                if (IsBb(p) != (pass == 0)) continue;
                if (p.Wait.StartsWith("AFTER:", StringComparison.Ordinal))
                {                                                         // A chained engine out: released (due the offset from now) once no earlier backbone out is pending
                    bool prior = false;
                    for (int k = 0; k < i; k++) if (Pending[k].Code == "MPS 01" && IsBb(Pending[k])) prior = true;
                    if (prior) continue;
                    string[] af = p.Wait.Split(':'); double ao = 0, nbu = 0;
                    double.TryParse(af[1], NumberStyles.Float, CultureInfo.InvariantCulture, out ao);
                    if (af.Length > 2) double.TryParse(af[2], NumberStyles.Float, CultureInfo.InvariantCulture, out nbu);
                    p.Due = vn + ao;
                    if (nbu > 0) p.Due = Math.Max(p.Due, MapEdge(nbu, now, vn));
                    p.Expire = p.Due + PickLife; p.Wait = "";
                }
                if (p.Wait.Length > 0 || p.Due > vn) continue;
                if (vn > p.Expire) { Pending.RemoveAt(i); i--; LastWhy = "EXPIRED " + p.Code; continue; }
                if (FinalBlocked(p.Code) && InFinal(Prog, phase)) { Pending.RemoveAt(i); i--; LastWhy = "FINAL APPROACH " + p.Code; continue; }     // A pick that falls due on the final is dropped, never fired
                if (s.IndexOf(p.Code, p.Target) >= 0)
                {                                                         // in the list: an offered pick the host fired without answering = confirmed
                    if (p.Offered) Confirm(s, i, now, phase); else { Pending.RemoveAt(i); LastWhy = "ALREADY FAILED " + p.Code; }
                    i--; continue;
                }
                if (!Flyable(p.Code) || Targets(Prog, p.Code, phase).Length == 0)
                {                                                         // another program's pick: it waits a minute for the hand-over, then goes
                    if (p.Offered || vn > p.Due + 60) { Pending.RemoveAt(i); i--; LastWhy = "NOT FLYABLE " + p.Code; }
                    continue;
                }
                if (AtRepeatCap(s, p.Code, p.Target)) { Pending.RemoveAt(i); i--; LastWhy = "REPEAT LIMIT " + p.Code; continue; }
                if (!IsScen(p) && !IsBb(p) && AtPhaseCap(p.Code, p.Target)) { Pending.RemoveAt(i); i--; LastWhy = "PHASE LIMIT " + p.Code; continue; }
                // every offer passes the same gates, a DEFER offered again too (the old DEFER shortcut here skipped the workload)
                string w = Workload(s, lv, now, tig, p);
                if (w.Length > 0) { LastWhy = w; return ""; }
                string f = ChkI(s, Prog, p.Code, p.Target, p.Mode, lv, now, IsBb(p) && (p.Src.IndexOf("2EO", StringComparison.Ordinal) >= 0 || p.Src.IndexOf("3EO", StringComparison.Ordinal) >= 0), p.Opt, p.Value);
                if (p.Code == "SW 02" && p.Mode == "P" && lv >= Brutal && (p.Opt & OptSwPerm) == 0 && (!Sw02PermOf(s.SeedHash, Ph) || Sw02PermStanding(s, Ph))) p.Mode = "T";     // BRUTAL: only a fraction of the flights lose the guidance for good
                if (f.Length > 0 && p.Mode == "P" && ModesOf(p.Code) == "PT" && ChkI(s, Prog, p.Code, p.Target, "T", lv, now, false, p.Opt, p.Value).Length == 0)
                { p.Mode = "T"; f = ""; }
                if (f.Length > 0) { Pending.RemoveAt(i); i--; LastWhy = "FLOOR " + f; continue; }
                p.Offered = true;
                return Text(p);
            }
            return "";
        }
        static string Text(SimPick p) { return p.Code + "|" + p.Target + "|" + p.Value + "|" + p.Mode; }

        // the host's answer to an offered pick: "OK" (or "OK:<target>") confirms, "DEFER" keeps it, anything else drops it
        public string Result(FailState s, string code, string target, string res, double now, string phase)
        {
            code = (code ?? "").Trim().ToUpperInvariant(); target = (target ?? "").Trim().ToUpperInvariant(); res = (res ?? "").Trim().ToUpperInvariant();
            int i = -1;
            for (int k = 0; k < Pending.Count; k++) if (Pending[k].Offered && Pending[k].Code == code && Pending[k].Target == target) { i = k; break; }
            if (i < 0) return "NONE";
            if (res.StartsWith("DEFER", StringComparison.Ordinal)) return "KEPT";
            if (!res.StartsWith("OK", StringComparison.Ordinal)) { Pending.RemoveAt(i); LastWhy = "REFUSED " + res; return "DROPPED"; }
            Confirm(s, i, now, phase);
            return "CONFIRMED";
        }

        void Confirm(FailState s, int i, double now, string phase)
        {
            SimPick p = Pending[i];
            Pending.RemoveAt(i);
            string code = p.Code, target = p.Target;
            int lv = Clamp(s.Difficulty);
            LastGap = now - LastFire;
            if (IsBb(p)) { LastWasDouble = false; Picked++; LastFire = now; string bk = p.Code + "|" + p.Target; int bn; Fired[bk] = Fired.TryGetValue(bk, out bn) ? bn + 1 : 1; return; }   // a backbone engine out: not a double-up, not in the phase's count, no chain
            LastWasDouble = !IsScen(p) && LastGap < SpacingOf(lv, p);                // inside the spacing = a double-up (Workload let it through); a scenario step is scripted, not a double-up
            if (!IsScen(p)) DblOpen = LastWasDouble;                              // open until a full spacing gap: no triple
            Picked++; LastFire = now;
            PickedPh[Ph]++;
            Recent.Add(code); while (Recent.Count > VarietyMem) Recent.RemoveAt(0);
            string fk = code + "|" + target; int fn; Fired[fk] = Fired.TryGetValue(fk, out fn) ? fn + 1 : 1;
            string pk3 = PhKey(phase) + "|" + fk; int pn3; FiredPh[pk3] = FiredPh.TryGetValue(pk3, out pn3) ? pn3 + 1 : 1;
            // CHAINING: a pick from this failure's backup list after a delay
            // On BRUTAL a chain starts only while fewer than BrutalBacklog picks wait (a queue of chains behind the workload rules starved the slot clock: no scenario roll, no
            // fresh draw), and only a backup that has NOT fired yet, else one not among the last fires, and that the floors would let through (the 2-3 entry lists kept repeating SW 03 / SW 01)
            bool chainOk = lv < Brutal || !VarietyOn || SpicePending() < BrutalBacklog;
            if (!IsScen(p) && Room(s) > 0 && chainOk && Draw(s) < ChainP[lv])
            {
                var bs = new List<string>();
                foreach (string b in Backups(code)) { int a = b.IndexOf('@'); if (Flyable(b.Substring(0, a))) bs.Add(b); }
                if (bs.Count > 0)
                {
                    List<string> bpool = bs;                              // On BRUTAL the backups whose code has not fired yet come first
                    if (lv >= Brutal && VarietyOn)     // those first, else the ones not among the last fires (a chain of the same two codes was the repeat), else none
                    {
                        bpool = bs.FindAll(x => FiresOf(x.Substring(0, x.IndexOf('@'))) == 0);
                        if (bpool.Count == 0) bpool = bs.FindAll(x => RecentW(x.Substring(0, x.IndexOf('@'))) == 1);
                    }
                    while (bpool.Count > 0)
                    {
                        string b = Pick(bpool.ToArray(), Draw(s));
                        bpool.Remove(b);
                        int a = b.IndexOf('@');
                        string tg, vl, md;
                        if (!Resolve(s, b.Substring(0, a), b.Substring(a + 1), target, phase, out tg, out vl, out md)) { if (lv >= Brutal && VarietyOn) continue; break; }     // below BRUTAL one try, as before
                        if (lv >= Brutal && VarietyOn && !Feasible(s, b.Substring(0, a), tg, lv, now)) continue;
                        Add(b.Substring(0, a), tg, vl, md, (vNow >= 0 ? vNow : now) + ChainLo[lv] + Draw(s) * (ChainHi[lv] - ChainLo[lv]), "CHAIN " + code);
                        break;
                    }
                }
            }
        }

        // ================================================================ RAND (not latched): every flyable code, NO floors
        public string Rand(FailState s, string prog, string codes, double scale, double dt, string phase)
        {
            if (s.Latched || dt <= 0 || scale <= 0) return "";
            prog = (prog ?? "").Trim().ToUpperInvariant(); phase = (phase ?? "").Trim().ToUpperInvariant();
            var fly = new HashSet<string>();
            foreach (string c in (codes ?? "").Split(';')) { string t = c.Trim().ToUpperInvariant(); if (t.Length > 0) fly.Add(t); }
            if (randE <= 0) randE = -Math.Log(1.0 - U(randSeed, randDraws++));
            string c0, t0;
            randAcc += HazardNow(s, prog, fly, phase, -1, out c0, out t0) * scale * Math.Min(dt, 5);
            if (randAcc < randE) return "";
            randAcc = 0; randE = -Math.Log(1.0 - U(randSeed, randDraws++));
            HazardNow(s, prog, fly, phase, U(randSeed, randDraws++), out c0, out t0);
            if (c0.Length == 0) return "";
            string vl = Pick(Values(c0), U(randSeed, randDraws++));
            string m = ModesOf(c0);
            string md = m == "PT" ? (U(randSeed, randDraws++) < 0.5 ? "P" : "T") : m.Substring(0, 1);
            return c0 + "|" + t0 + "|" + vl + "|" + md;
        }
        public void RandSeed(long seed) { randSeed = seed; randDraws = 0; randAcc = 0; randE = -1; }

        // ================================================================ the save (keys "ss.*" inside FailState's SIM record)
        static string D(double v) { return v.ToString("R", CultureInfo.InvariantCulture); }
        public void Record(Dictionary<string, string> d)
        {
            d["ss.draws"] = Draws.ToString(CultureInfo.InvariantCulture);
            d["ss.picked"] = Picked.ToString(CultureInfo.InvariantCulture);
            d["ss.pp"] = PickedPh[0].ToString(CultureInfo.InvariantCulture) + ";" + PickedPh[1].ToString(CultureInfo.InvariantCulture) + ";" + PickedPh[2].ToString(CultureInfo.InvariantCulture);
            var rb = new StringBuilder();
            foreach (KeyValuePair<string, int> kv in Fired) { if (rb.Length > 0) rb.Append(';'); rb.Append(kv.Key).Append('|').Append(kv.Value.ToString(CultureInfo.InvariantCulture)); }
            d["ss.rep"] = rb.ToString();
            var rq = new StringBuilder();                                   // The per-phase counts ("PHASE|code|target|n")
            foreach (KeyValuePair<string, int> kv in FiredPh) { if (rq.Length > 0) rq.Append(';'); rq.Append(kv.Key).Append('|').Append(kv.Value.ToString(CultureInfo.InvariantCulture)); }
            d["ss.rph"] = rq.ToString();
            var rn2 = new StringBuilder();
            foreach (KeyValuePair<string, int> kv in PhRound) { if (rn2.Length > 0) rn2.Append(';'); rn2.Append(kv.Key).Append('|').Append(kv.Value.ToString(CultureInfo.InvariantCulture)); }
            d["ss.rnd"] = rn2.ToString();
            d["ss.vc"] = D(vr0) + ";" + D(vA) + ";" + D(vK) + ";" + D(vNow) + ";" + D(vReal) + ";" + D(vrPrev) + ";" + D(vrDec);
            d["ss.sa"] = D(SlotAt);
            d["ss.force"] = Force.ToString(CultureInfo.InvariantCulture);
            d["ss.bb"] = Bb.ToString(CultureInfo.InvariantCulture);
            d["ss.pt"] = D(PhaseT[0]) + ";" + D(PhaseT[1]) + ";" + D(PhaseT[2]);
            d["ss.last"] = D(LastFire);
            d["ss.acc"] = D(Acc);
            d["ss.e"] = D(E);
            d["ss.dbl"] = DblOpen ? "1" : "0";
            d["ss.rv"] = RevSeen.ToString(CultureInfo.InvariantCulture);
            d["ss.sc"] = string.Join(";", new List<string>(Started).ToArray());
            var sb = new StringBuilder();
            foreach (SimPick p in Pending)
            {
                if (sb.Length > 0) sb.Append(';');
                sb.Append(p.Code).Append('|').Append(p.Target).Append('|').Append(p.Value).Append('|').Append(p.Mode).Append('|')
                  .Append(D(p.Due)).Append('|').Append(D(p.Expire)).Append('|').Append(p.Src).Append('|').Append(p.Offered ? "1" : "0")
                  .Append('|').Append(p.Dbl.ToString(CultureInfo.InvariantCulture))
                  .Append('|').Append(p.Opt.ToString(CultureInfo.InvariantCulture)).Append('|').Append(p.Wait);
            }
            d["ss.picks"] = sb.ToString();
        }
        static double Pd(Dictionary<string, string> d, string k, double dflt)
        {
            string s; double v;
            return d.TryGetValue(k, out s) && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : dflt;
        }
        public void Restore(Dictionary<string, string> d)
        {
            Reset();
            if (d == null) return;
            Draws = (long)Pd(d, "ss.draws", 0);
            Picked = (int)Pd(d, "ss.picked", 0);
            string rp;
            if (d.TryGetValue("ss.rep", out rp) && rp.Length > 0)
                foreach (string r0 in rp.Split(';'))
                {
                    string[] rf = r0.Split('|'); int rn;
                    if (rf.Length == 3 && int.TryParse(rf[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out rn) && rn > 0) Fired[rf[0] + "|" + rf[1]] = rn;
                }
            string rq0;                                                 // A save from before it has none (the phase counts start at 0)
            if (d.TryGetValue("ss.rph", out rq0) && rq0.Length > 0)
                foreach (string r0 in rq0.Split(';'))
                {
                    string[] rf = r0.Split('|'); int rn;
                    if (rf.Length == 4 && int.TryParse(rf[3], NumberStyles.Integer, CultureInfo.InvariantCulture, out rn) && rn > 0) FiredPh[rf[0] + "|" + rf[1] + "|" + rf[2]] = rn;
                }
            string rn0;
            if (d.TryGetValue("ss.rnd", out rn0) && rn0.Length > 0)
                foreach (string r0 in rn0.Split(';'))
                {
                    string[] rf = r0.Split('|'); int rn;
                    if (rf.Length == 2 && int.TryParse(rf[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out rn) && rn > 0) PhRound[rf[0]] = rn;
                }
            string vc;
            if (d.TryGetValue("ss.vc", out vc))
            {
                string[] vf = vc.Split(';'); double x0, x1, x2, x3, x4;
                double x5 = -1, x6 = 0;
                if (vf.Length == 7) { double.TryParse(vf[5], NumberStyles.Float, CultureInfo.InvariantCulture, out x5); double.TryParse(vf[6], NumberStyles.Float, CultureInfo.InvariantCulture, out x6); }
                if ((vf.Length == 5 || vf.Length == 7) && double.TryParse(vf[0], NumberStyles.Float, CultureInfo.InvariantCulture, out x0) && double.TryParse(vf[1], NumberStyles.Float, CultureInfo.InvariantCulture, out x1)
                    && double.TryParse(vf[2], NumberStyles.Float, CultureInfo.InvariantCulture, out x2) && double.TryParse(vf[3], NumberStyles.Float, CultureInfo.InvariantCulture, out x3)
                    && double.TryParse(vf[4], NumberStyles.Float, CultureInfo.InvariantCulture, out x4)) { vr0 = x0; vA = x1; vK = x2; vNow = x3; vReal = x4; vrPrev = x5; vrDec = x6; }
            }
            Force = (int)Pd(d, "ss.force", -1);
            Bb = (int)Pd(d, "ss.bb", 0);
            string pp, pt;                                          // Per phase; a save from before it has neither (the counts start at 0)
            if (d.TryGetValue("ss.pp", out pp))
            {
                string[] a = pp.Split(';');
                for (int k = 0; k < 3 && k < a.Length; k++) { int v; if (int.TryParse(a[k], NumberStyles.Integer, CultureInfo.InvariantCulture, out v) && v >= 0) PickedPh[k] = v; }
            }
            if (d.TryGetValue("ss.pt", out pt))
            {
                string[] a = pt.Split(';');
                for (int k = 0; k < 3 && k < a.Length; k++) { double v; if (double.TryParse(a[k], NumberStyles.Float, CultureInfo.InvariantCulture, out v) && v >= 0) PhaseT[k] = v; }
            }
            LastFire = Pd(d, "ss.last", -1e9);
            Acc = Pd(d, "ss.acc", 0);
            SlotAt = Pd(d, "ss.sa", -1);
            E = Pd(d, "ss.e", -1);
            DblOpen = Pd(d, "ss.dbl", 0) != 0;
            RevSeen = (int)Pd(d, "ss.rv", 0);
            string sc;
            if (d.TryGetValue("ss.sc", out sc) && sc.Length > 0) foreach (string n0 in sc.Split(';')) if (n0.Length > 0) Started.Add(n0);
            string ps;
            if (!d.TryGetValue("ss.picks", out ps) || string.IsNullOrEmpty(ps)) return;
            foreach (string r in ps.Split(';'))
            {
                string[] f = r.Split('|');
                // 8 fields = an old save (no double-up draw yet); 9 = with the draw; 11 = + the scenario step's Check options and the point it waits for
                if ((f.Length != 8 && f.Length != 9 && f.Length != 11) || FailState.Find(f[0]) == null || Pending.Count >= FailState.MaxEntries) continue;
                double due, exp;
                if (!double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out due)) continue;
                if (!double.TryParse(f[5], NumberStyles.Float, CultureInfo.InvariantCulture, out exp)) continue;
                int dbl = f.Length >= 9 ? (f[8] == "1" ? 1 : (f[8] == "2" ? 2 : 0)) : 0;
                int opt = 0; string wt = "";
                if (f.Length == 11) { int.TryParse(f[9], NumberStyles.Integer, CultureInfo.InvariantCulture, out opt); wt = f[10]; }
                Pending.Add(new SimPick { Code = f[0], Target = f[1], Value = f[2], Mode = f[3], Due = due, Expire = exp, Src = f[6], Offered = f[7] == "1", Dbl = dbl, Opt = opt, Wait = wt });
            }
        }
    }
}
