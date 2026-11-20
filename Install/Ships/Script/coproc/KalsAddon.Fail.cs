// THE FAILURE LIST (Fail.cs, FailVessel.cs): the failures live in the vessel, not in a script. ADDONS:KALS:
//     FAILSET(code, target, value, mode)  inject a failure ("OMS 01", "L", "", "P"): "OK" or "REFUSE: <why>"
//     FAILFIX(code, target, via)          start the REAL fix of one ("RESTART", "SWAP SPARE", ...): "OK" or "REFUSE: <why>"; the
//                                         DLL checks the failure's mode, the fix's name and its preconditions, and removes the
//                                         failure itself when the fix's time is over
//     FAILBIND(code, target, parts)       say which parts a failure acts on, ONCE ("uid;uid:2;..." = part UIDs, "uid:n" = the part's n-th
//                                         module of the kind): "OK" or "REFUSE: <why>"; the DLL then holds those parts to the failure
//                                         (FailEnforce.cs); a second bind of the same failure is refused
//     FAILSTAT()                          LIST of LIST(code, target, parts bound, parts found on the vessel, corrections made so far):
//                                         the enforcement's read-back (a correction = something undid the failure and was put back)
//     FAILLIST()                          LIST of LIST(code, target, value, mode, UT it happened, UT its fix ends or -1, fix name)
//     SIMSTATE()                          LIST(latched, difficulty, counter, fired, spare used); the seed is never returned
//     SIMLATCH(difficulty, seedHash)      latch the SimSup flight: TRUE the first time, FALSE after
//     SIMPOINT()                          a decision point passed (counts only while latched): returns the counter
//     SIMPOINT(name, edgeUt[, phase])     the same, at a NAMED decision point (SimSup.cs Points: "ABORT_TAL", "BURN_TIG", "EI", ...)
//                                         whose edge is at edgeUt: the planner may schedule a hidden pick around it
//     SIMHOST(prog, codes)                the program flying ("OPS1" / "OPS2" / "OPS3" / "OPS6") and its flyable codes (';'-joined
//                                         FL_HAND keys); call at the program's start: "OK"
//     SIMVR(vr)                           the relative velocity (m/s), fed each tick (OPS 3 / 6): the ENTRY / TAEM pick clock runs on it (SimSup.cs VClock)
//     SIMTICK(tig, phase, randOk, dt)     each host tick while latched: "" or the SimSup pick due now, "code|target|value|mode"
//                                         (the host fires it with flFire(..., "SIMSUP") and answers SIMRES)
//     SIMRES(code, target, res)           flFire's answer to an offered pick: "OK..." confirms, "DEFER..." offers it again, else dropped
//     SIMRAND(scale, dt, phase)           RAND (not latched): "" or a pick "code|target|value|mode" from every flyable code, NO floors
//     SIMFORCE(name)                      ForceAbort: "NONE" / "RTLS" / "1EO TAL" / "2EO TAL" / "AOA" / "2EO GREEN" / "2EO BLUE" / "3EO BLUE" / "3EO GREEN" / "3EO TAL" / "3EO ATO" / "3EO RTLS" / "3EO SPLITS" / "2EO SPLITS" / "RTLS 2EO GREEN" / "RTLS 2EO BLUE" / "ORBIT": the
//                                         ascent's drawn outcome is overridden (call after SIMLATCH; a latch clears it): "OK" / "REFUSE: <why>"
//     SIMNOCODE(list)                     the failure codes never drawn (';'-joined, "FCS 01;RCS 04"; "" = clear): SimSup.NoCodes, static (kOS: FL_SIMNOCODE, sent at ENGAGE): "OK"
//     SIMREACH(list)                      the outcomes this flight can reach (';'-joined names, "" = all): a drawn mode outside it is redrawn
//     SIMOUTCOME()   (dev DLL only)       the ascent's outcome (drawn or forced) as a name, "" unlatched: for the LOG only, never a display
//     SIMCHECK(code, target, mode)        "" or "RTN IMPSBLE: <floor>": the survivability floors at HARD (the latched level if harder)
//                                         for a player's own row; SimSup's picks pass the latched level's floors themselves
// There is no suffix that clears a failure, un-latches or edits the list; only a fix's own timer and the end of a latched
// flight (landed and still) remove entries. Every call acts on the active vessel and never throws ("REFUSE: ..." / FALSE).
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        partial void RegisterFail()
        {
            AddSuffix("FAILSET", new VarArgsSuffix<StringValue, Structure>(FailSet));
            AddSuffix("FAILFIX", new ThreeArgsSuffix<StringValue, StringValue, StringValue, StringValue>(FailFix));
            AddSuffix("FAILLIST", new Suffix<ListValue>(FailList));
            AddSuffix("FAILBIND", new ThreeArgsSuffix<StringValue, StringValue, StringValue, StringValue>(FailBind));
            AddSuffix("FAILSTAT", new Suffix<ListValue>(FailStat));
            AddSuffix("SIMSTATE", new Suffix<ListValue>(SimState));
            AddSuffix("SIMLATCH", new TwoArgsSuffix<BooleanValue, ScalarValue, ScalarValue>(SimLatch));
            AddSuffix("SIMPOINT", new VarArgsSuffix<ScalarValue, Structure>(SimPoint));
            AddSuffix("SIMHOST", new TwoArgsSuffix<StringValue, StringValue, StringValue>(SimHost));
            AddSuffix("SIMTICK", new VarArgsSuffix<StringValue, Structure>(SimTick));
            AddSuffix("SIMVR", new OneArgsSuffix<StringValue, ScalarValue>(SimVr));
            AddSuffix("SIMRES", new ThreeArgsSuffix<StringValue, StringValue, StringValue, StringValue>(SimRes));
            AddSuffix("SIMRAND", new VarArgsSuffix<StringValue, Structure>(SimRand));
            AddSuffix("SIMFORCE", new OneArgsSuffix<StringValue, StringValue>(SimForce));
            AddSuffix("SIMREACH", new OneArgsSuffix<StringValue, StringValue>(SimReach));
            AddSuffix("SIMNOCODE", new OneArgsSuffix<StringValue, StringValue>(SimNoCode));
#if !KALS_RELEASE
            AddSuffix("SIMOUTCOME", new Suffix<StringValue>(SimOutcome));   // the test harness's read
#endif
            AddSuffix("SIMCHECK", new ThreeArgsSuffix<StringValue, StringValue, StringValue, StringValue>(SimCheck));
            AddSuffix("GPCKICK", new ThreeArgsSuffix<StringValue, StringValue, ScalarValue, ScalarValue>(GpcKickCall));   // DPS 06 GPC OUTPUT BAD's control transient (KalsAddon.GpcKick.cs)
        }

        FailVessel FailMod() { return FailVessel.Of(shared == null ? null : shared.Vessel); }
        static string Txt(Structure s) { return s == null ? "" : s.ToString(); }

        StringValue FailSet(params Structure[] a)
        {
            try
            {
                if (a == null || a.Length != 4) return new StringValue("REFUSE: FAILSET(code, target, value, mode)");
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                return new StringValue(m.S.Set(Txt(a[0]), Txt(a[1]), Txt(a[2]), Txt(a[3]), FailVessel.Now()));
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        StringValue FailFix(StringValue code, StringValue target, StringValue via)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                return new StringValue(m.S.Fix(Txt(code), Txt(target), Txt(via), FailVessel.Now()));
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        StringValue FailBind(StringValue code, StringValue target, StringValue parts)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                return new StringValue(m.S.Bind(Txt(code), Txt(target), Txt(parts)));
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        ListValue FailStat()
        {
            var o = new ListValue();
            try
            {
                FailVessel m = FailMod();
                if (m == null) return o;
                foreach (FailEntry e in m.S.List)
                {
                    var r = new ListValue();
                    r.Add(new StringValue(e.Code)); r.Add(new StringValue(e.Target));
                    r.Add(ScalarValue.Create(e.Tokens().Length)); r.Add(ScalarValue.Create(e.Found)); r.Add(ScalarValue.Create(e.Corrections));
                    o.Add(r);
                }
            }
            catch (Exception) { }
            return o;
        }

        ListValue FailList()
        {
            var o = new ListValue();
            try
            {
                FailVessel m = FailMod();
                if (m == null) return o;
                foreach (FailEntry e in m.S.List)
                {
                    var r = new ListValue();
                    r.Add(new StringValue(e.Code)); r.Add(new StringValue(e.Target)); r.Add(new StringValue(e.Value)); r.Add(new StringValue(e.Mode));
                    r.Add(ScalarValue.Create(e.At)); r.Add(ScalarValue.Create(e.HealAt)); r.Add(new StringValue(e.Via));
                    o.Add(r);
                }
            }
            catch (Exception) { }
            return o;
        }

        ListValue SimState()
        {
            var o = new ListValue();
            try
            {
                FailVessel m = FailMod();
                FailState s = m == null ? null : m.S;
                o.Add(new BooleanValue(s != null && s.Latched));
                o.Add(ScalarValue.Create(s == null ? 0 : s.Difficulty));
                o.Add(ScalarValue.Create(s == null ? 0 : s.Counter));
                o.Add(ScalarValue.Create(s == null ? 0 : s.Fired));
                o.Add(new BooleanValue(s != null && s.SpareUsed));
            }
            catch (Exception) { }
            return o;
        }

        BooleanValue SimLatch(ScalarValue difficulty, ScalarValue seedHash)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new BooleanValue(false);
                return new BooleanValue(m.S.Latch((int)AlgKos.Num(difficulty), (long)AlgKos.Num(seedHash)));
            }
            catch (Exception) { return new BooleanValue(false); }
        }

        ScalarValue SimPoint(params Structure[] a)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return ScalarValue.Create(0);
                SimSup.NoPilot = SailBus.On;        // The test harness flies with no pilot (no permanent SW 01 / SW 02)
                int n = m.S.Point();
                if (a != null && a.Length >= 2 && m.S.Latched)
                {
                    int bb0 = m.S.Sup.Bb;
                    int k = m.S.Sup.Point(m.S, Txt(a[0]), EntryGuid.Num(a[1]), FailVessel.Now(), a.Length >= 3 ? Txt(a[2]) : "");
                    if (k > 0) FailVessel.Log("SIMSUP point " + n + " planned " + k);   // what was planned stays hidden
                    // The abort marks' crossings by name (the test harness judges the outs against them: TAL_OPEN / ATO_OPEN / TAL_2EO / V3_ATO ... were never logged); edge = the UT the host fed
                    string mkn = Txt(a[0]).Trim().ToUpperInvariant();
                    if (SimSup.IsBackboneMark(mkn)) FailVessel.Log("SIMSUP mark " + mkn + " edge UT " + EntryGuid.Num(a[1]).ToString("F1", System.Globalization.CultureInfo.InvariantCulture) + " now UT " + FailVessel.Now().ToString("F1", System.Globalization.CultureInfo.InvariantCulture));
                    if (bb0 == 0 && m.S.Sup.Bb == 1) FailVessel.Log("SIMSUP outcome " + SimSup.OcName[m.S.Sup.Outcome(m.S)] + (m.S.Sup.Force >= 0 ? " (forced)" : " (drawn)"));
                }
                return ScalarValue.Create(n);
            }
            catch (Exception) { return ScalarValue.Create(0); }
        }

        StringValue SimForce(StringValue name)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                if (!m.S.Latched) return new StringValue("REFUSE: NOT LATCHED");
                string n = Txt(name).Trim().ToUpperInvariant();
                if (n.Length == 0 || n == "NONE") { m.S.Sup.Force = -1; return new StringValue("OK"); }
                for (int k = 0; k < SimSup.OcName.Length; k++) if (SimSup.OcName[k] == n) { m.S.Sup.Force = k; return new StringValue("OK"); }
                return new StringValue("REFUSE: NO SUCH OUTCOME");
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        StringValue SimNoCode(StringValue list)          // SimSup.NoCodes = the codes in the list (never drawn); "" clears
        {
            try
            {
                SimSup.NoCodes.Clear();
                foreach (string c in Txt(list).Split(';')) { string t = c.Trim().ToUpperInvariant(); if (t.Length > 0) SimSup.NoCodes.Add(t); }
                return new StringValue("OK");
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        StringValue SimReach(StringValue list)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                m.S.Sup.SetReach(Txt(list));
                return new StringValue("OK");
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

#if !KALS_RELEASE
        StringValue SimOutcome()
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null || !m.S.Latched) return new StringValue("");
                return new StringValue(m.S.Sup.OutcomeName(m.S));
            }
            catch (Exception) { return new StringValue(""); }
        }
#endif

        StringValue SimHost(StringValue prog, StringValue codes)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("REFUSE: NO VESSEL");
                m.S.Sup.Host(Txt(prog), Txt(codes));
                return new StringValue("OK");
            }
            catch (Exception e) { return new StringValue("REFUSE: " + e.Message); }
        }

        // The relative velocity (m/s) the planner's ENTRY / TAEM pick clock runs on; fed before each SIMTICK / SIMPOINT
        StringValue SimVr(ScalarValue vr)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("");
                m.S.Sup.Vr = AlgKos.Num(vr);
                return new StringValue("OK");
            }
            catch (Exception) { return new StringValue(""); }
        }

        // The names of the vessel's real RCS jets (RcsJets.Map, cached per vessel / part count); null = no vessel or no jets yet (SimSup keeps its own fore / aft names)
        string[] SimJetNames()
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null || shared == null || shared.Vessel == null) return null;
                var js = m.Enforcer.Rcs.Map(shared.Vessel);
                if (js == null || js.Count == 0) return null;
                var o = new string[js.Count];
                for (int i = 0; i < o.Length; i++) o[i] = js[i].Name;
                return o;
            }
            catch (Exception) { return null; }
        }

        StringValue SimTick(params Structure[] a)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null || a == null || a.Length != 4) return new StringValue("");
                SimSup.NoPilot = SailBus.On;
                SimSup.JetNames = SimJetNames();        // RCS 04 picks only jets the vessel's map has
                m.S.Sup.Alt = shared != null && shared.Vessel != null ? shared.Vessel.altitude : -1;     // OPS 3 fires nothing above the entry interface
                return new StringValue(m.S.Sup.Tick(m.S, FailVessel.Now(), EntryGuid.Num(a[0]), Txt(a[1]), EntryGuid.Bool(a[2]), EntryGuid.Num(a[3])));
            }
            catch (Exception) { return new StringValue(""); }
        }

        StringValue SimRes(StringValue code, StringValue target, StringValue res)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("NONE");
                string r = m.S.Sup.Result(m.S, Txt(code), Txt(target), Txt(res), FailVessel.Now(), "");
                if (r == "CONFIRMED") FailVessel.Log("SIMSUP fired " + Txt(code) + " " + Txt(target) + " (" + SimSup.PhaseName(m.S.Sup.Ph) + " " + m.S.Sup.PhasePicked + " of " + (m.S.Sup.Budget(m.S) >= SimSup.NoCap ? "no cap" : m.S.Sup.Budget(m.S).ToString()) + ")");
                return new StringValue(r);
            }
            catch (Exception) { return new StringValue("NONE"); }
        }

        StringValue SimRand(params Structure[] a)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null || a == null || a.Length != 3) return new StringValue("");
                SimSup u = m.S.Sup;
                return new StringValue(u.Rand(m.S, u.Prog, string.Join(";", new System.Collections.Generic.List<string>(u.Codes).ToArray()),
                                              EntryGuid.Num(a[0]), EntryGuid.Num(a[1]), Txt(a[2])));
            }
            catch (Exception) { return new StringValue(""); }
        }

        StringValue SimCheck(StringValue code, StringValue target, StringValue mode)
        {
            try
            {
                FailVessel m = FailMod();
                if (m == null) return new StringValue("");
                SimSup.NoPilot = SailBus.On;
                int lv = m.S.Latched ? Math.Max(SimSup.Hard, SimSup.Clamp(m.S.Difficulty)) : SimSup.Hard;
                string c = Txt(code).Trim().ToUpperInvariant(), t = Txt(target).Trim().ToUpperInvariant(), md = Txt(mode).Trim().ToUpperInvariant();
                string f = m.S.Sup.ChkI(m.S, m.S.Sup.Prog, c, t, md, lv, FailVessel.Now());
                return new StringValue(f.Length == 0 || f == "ALREADY FAILED" ? "" : "RTN IMPSBLE: " + f);
            }
            catch (Exception) { return new StringValue(""); }
        }
    }
}
