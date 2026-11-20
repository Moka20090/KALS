// THE RCS JET MAP ("Use the jet-failure code to make it as realistic as possible, taking out jets that would (or did) fail together in real life").
// NO KSP or kOS type here (RcsJets.cs does the parts; tests/fail_offline runs this very file).
//   A JET NAME is the real Shuttle's: POD + MANIFOLD + FIRING DIRECTION, "F3U", "L2D", "R4R" (the letter is the way the jet fires = its exhaust):
//     pod  F forward, L left aft, R right aft;   manifold 1 .. 4 (primary only: the model has no vernier jets);
//     direction  F fore, A aft, U up (the ship's top), D down, L left (port), R right (starboard).
//   A GROUP is a pod (manifold 0 = the whole pod: the pod's He / propellant isolation) or one manifold of a pod. The failure targets:
//     "F ALL" "L ALL" "R ALL"  "F MANIFOLD 1" .. "R MANIFOLD 4"      (RCS 01 manifold valves closed, RCS 02 thrust low)
//     "F" "L" "R"                                                     (RCS 03 the pod's propellant leak)
//     "F3U"                                                           (RCS 04 one jet stuck off / on)
//   The old targets FWD 1 / FWD ALL / AFT 1 / AFT ALL / FWD / AFT are RETIRED from the window; Groups() still reads them (a save or a scenario row
//   of an older version): FWD * = pod F, AFT * = pods L + R (AFT 1 = manifold 1 of both).
// WHERE THE MODEL CANNOT MATCH THE REAL TABLE (said plainly): the part models give the jets their positions and directions, nothing else, so the manifold
//   of a jet is DEALT, not read: in each pod the jets are taken direction by direction (F A U D L R), each direction's jets in order of their place on the
//   ship (fore, top, starboard), and dealt to manifolds 1, 2, 3, 4, 1, 2 ... in one running count. That gives the real table's two properties (each
//   manifold feeds jets in several directions; the jets of one direction sit on DIFFERENT manifolds, so one manifold never takes a whole direction), and
//   a pod's manifolds hold 3 / 3 / 3 / 3 jets (the aft pods, 12 each) or 4 / 4 / 3 / 3 (the forward pod, 14). Which physical jet is on which real
//   manifold (L1A vs L3A) is NOT known from the model. The real forward jet count is 14 primary + 2 vernier: the 2 verniers are not modelled.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace KalsCoproc
{
    public struct RcsGroup
    {
        public char Pod;        // 'F' / 'L' / 'R'
        public int Man;         // 0 = the whole pod, 1 .. 4 = that manifold
        public RcsGroup(char p, int m) { Pod = p; Man = m; }
    }

    // one jet as the part model gives it (position and exhaust direction on the ship's axes: fore, top, starboard)
    public sealed class RcsJetIn
    {
        public double Fore, Top, Star;          // m from the centre of mass
        public double DFore, DTop, DStar;       // the exhaust direction (not normalised)
        public int PartKey;                     // the part (a flight id)
        public int Module, Jet;                 // the part's n-th RCS module, the jet's place in it
        public bool Fwd;                        // the part is forward of the centre of mass
    }

    public sealed class RcsJetOut
    {
        public char Pod, Dir;
        public int Man;
        public string Name;
    }

    public static class RcsMap
    {
        public const int Manifolds = 4;
        public const string DirOrder = "FAUDLR";
        public const double CentreEps = 0.02;   // m: a jet this close to the pod pair's centreline counts as the starboard one

        // the firing direction letter of an exhaust vector: the biggest component; a tie goes by DirOrder
        public static char DirOf(double fore, double top, double star)
        {
            double af = Math.Abs(fore), at = Math.Abs(top), asr = Math.Abs(star);
            if (af >= at && af >= asr) return fore >= 0 ? 'F' : 'A';
            if (at >= asr) return top >= 0 ? 'U' : 'D';
            return star >= 0 ? 'R' : 'L';
        }

        // the map: each jet's pod, manifold, direction and name, in the order of the input
        public static RcsJetOut[] Deal(RcsJetIn[] jets)
        {
            int n = jets.Length;
            var o = new RcsJetOut[n];
            // the pod: the forward part's jets are F; the others by their side of their part's mean starboard coordinate (the part sits on the centreline)
            var sum = new Dictionary<int, double>();
            var cnt = new Dictionary<int, int>();
            for (int i = 0; i < n; i++)
            {
                o[i] = new RcsJetOut();
                if (jets[i].Fwd) continue;
                double s; int c;
                sum.TryGetValue(jets[i].PartKey, out s); cnt.TryGetValue(jets[i].PartKey, out c);
                sum[jets[i].PartKey] = s + jets[i].Star; cnt[jets[i].PartKey] = c + 1;
            }
            for (int i = 0; i < n; i++)
            {
                RcsJetIn j = jets[i];
                if (j.Fwd) { o[i].Pod = 'F'; }
                else
                {
                    double mean = sum[j.PartKey] / cnt[j.PartKey];
                    o[i].Pod = j.Star < mean - CentreEps ? 'L' : 'R';
                }
                o[i].Dir = DirOf(j.DFore, j.DTop, j.DStar);
            }
            // the manifolds: per pod, direction by direction, in the order of the place, one running count
            var used = new HashSet<string>();
            foreach (char pod in "FLR")
            {
                int run = 0;
                foreach (char dir in DirOrder)
                {
                    var ix = new List<int>();
                    for (int i = 0; i < n; i++) if (o[i].Pod == pod && o[i].Dir == dir) ix.Add(i);
                    ix.Sort((a, b) => Cmp(jets[a], jets[b]));
                    foreach (int i in ix)
                    {
                        o[i].Man = (run % Manifolds) + 1;
                        run++;
                        string nm = "" + pod + o[i].Man.ToString(CultureInfo.InvariantCulture) + dir;
                        char sfx = 'B';
                        string t = nm;
                        while (!used.Add(t)) { t = nm + sfx; sfx++; }       // a 5th jet of one direction in a pod shares a manifold: F1U, F1UB
                        o[i].Name = t;
                    }
                }
            }
            return o;
        }

        static int Cmp(RcsJetIn a, RcsJetIn b)
        {
            int c = Math.Round(a.Fore, 3).CompareTo(Math.Round(b.Fore, 3));
            if (c != 0) return c;
            c = Math.Round(a.Top, 3).CompareTo(Math.Round(b.Top, 3));
            if (c != 0) return c;
            c = Math.Round(a.Star, 3).CompareTo(Math.Round(b.Star, 3));
            if (c != 0) return c;
            c = a.PartKey.CompareTo(b.PartKey);
            if (c != 0) return c;
            c = a.Module.CompareTo(b.Module);
            return c != 0 ? c : a.Jet.CompareTo(b.Jet);
        }

        static string N(string s) { return s == null ? "" : s.Trim().ToUpperInvariant(); }
        static bool PodCh(string s) { return s.Length == 1 && (s[0] == 'F' || s[0] == 'L' || s[0] == 'R'); }

        // a failure target -> the groups it names; null = not a group target. "F ALL", "L MANIFOLD 3", the bare pod "R"; the retired FWD / AFT names too.
        public static List<RcsGroup> Groups(string target)
        {
            string t = N(target);
            var l = new List<RcsGroup>();
            if (PodCh(t)) { l.Add(new RcsGroup(t[0], 0)); return l; }
            string[] w = t.Split(' ');
            if (w.Length == 2 && PodCh(w[0]) && w[1] == "ALL") { l.Add(new RcsGroup(w[0][0], 0)); return l; }
            if (w.Length == 3 && PodCh(w[0]) && w[1] == "MANIFOLD")
            {
                int m;
                if (int.TryParse(w[2], NumberStyles.None, CultureInfo.InvariantCulture, out m) && m >= 1 && m <= Manifolds) { l.Add(new RcsGroup(w[0][0], m)); return l; }
                return null;
            }
            // the retired names
            if (t == "FWD" || t == "FWD ALL") { l.Add(new RcsGroup('F', 0)); return l; }
            if (t == "AFT" || t == "AFT ALL") { l.Add(new RcsGroup('L', 0)); l.Add(new RcsGroup('R', 0)); return l; }
            if (w.Length == 2 && (w[0] == "FWD" || w[0] == "AFT"))
            {
                int m;
                if (!int.TryParse(w[1], NumberStyles.None, CultureInfo.InvariantCulture, out m) || m < 1 || m > Manifolds) return null;
                if (w[0] == "FWD") l.Add(new RcsGroup('F', m));
                else { l.Add(new RcsGroup('L', m)); l.Add(new RcsGroup('R', m)); }
                return l;
            }
            return null;
        }

        public static bool InGroups(List<RcsGroup> gs, char pod, int man)
        {
            foreach (RcsGroup g in gs) if (g.Pod == pod && (g.Man == 0 || g.Man == man)) return true;
            return false;
        }

        // "F3U" / "L2DB" -> true (the jet's name as Deal builds it); the numeric old names F<k> / A<k> are NOT real names (FailLeak.ParseJet)
        public static bool IsJetName(string target)
        {
            string t = N(target);
            if (t.Length < 3 || t.Length > 4) return false;
            if (!PodCh(t.Substring(0, 1))) return false;
            if (t[1] < '1' || t[1] > '0' + Manifolds) return false;
            if (DirOrder.IndexOf(t[2]) < 0) return false;
            if (t.Length == 4 && (t[3] < 'B' || t[3] > 'Z')) return false;
            return true;
        }

        // RCS 04's value: "STUCK ON" (the old "FAIL ON") holds the jet firing; anything else is stuck OFF
        public static bool IsOn(string value)
        {
            string v = N(value);
            return v == "STUCK ON" || v == "FAIL ON";
        }

        // THRUST LOW by duty: the fraction of the physics ticks a capped jet is let fire (a ModuleRCS has one thrust limit for all its jets, the
        // pods share modules): acc is the jet's running sum; true = the jet may fire this tick. 0.5 fires every other tick, 0.75 three in four.
        public static bool DutyStep(ref float acc, float frac)
        {
            if (frac >= 1f) { acc = 0f; return true; }
            if (frac <= 0f) { acc = 0f; return false; }
            acc += frac;
            if (acc >= 1f) { acc -= 1f; return true; }
            return false;
        }

        // What a duty jet's thruster must be made RIGHT BEFORE its module's FixedUpdate (RcsJets.Pre). The switch is done at the module's own start of the
        // tick, so a jet that fires is still active (its plume up, the FX power the module set) when the frame is drawn. Switched by the old Hold AFTER the
        // module's FixedUpdate, a firing tick was cut again before the render (50 %: every firing tick).
        // fire = the duty's word for this tick, active = the thruster GameObject's activeSelf, ours = we deactivated it (a jet the model ships inactive is never touched).
        public const int DutyKeep = 0, DutyOff = 1, DutyOn = 2;
        public static int DutyDecide(bool fire, bool active, bool ours)
        {
            if (!fire) return active ? DutyOff : DutyKeep;
            return (!active && ours) ? DutyOn : DutyKeep;
        }

        // T1017: PAYLOAD RCS. The orbiter's own RCS parts are its forward and aft fuselage (the rule kOS's o2qPodScan / cwsScan use: the part name holds
        // "forwardfuselage" / "aftfuselage", any case, any separator style: benjee10_shuttle_forwardFuselage, benjee10.shuttle.aftFuselage); every other part with a
        // ModuleRCS on a vessel that has one of them is a payload's (PayloadRcs.cs).
        public static bool IsOrbiterRcsName(string partName)
        {
            if (string.IsNullOrEmpty(partName)) return false;
            string n = partName.ToLowerInvariant();
            return n.Contains("forwardfuselage") || n.Contains("aftfuselage");
        }

        // T1032: WHICH POD SIDE A RCS PART IS ON. On a shuttle vessel it is the part's IDENTITY (the forward fuselage = pod F, the aft fuselage = pods L / R); the
        // old rule (ahead of the centre of mass, FailEnforce.IsFwd) moved with the payload: a payload in the bay puts the c.g. aft of the aft fuselage's origin,
        // so the aft fuselage's 24 jets were dealt to pod F (OMS/RCS page F 38 instead of 14, SAIL run 20261117_085358_stock). Off a shuttle vessel (no orbiter
        // fuselage on it) the c.g. rule stays: comFwd = the part is ahead of the c.g.
        public static bool PodIsFwd(bool shuttle, string partName, bool comFwd)
        {
            if (!shuttle) return comFwd;
            return !string.IsNullOrEmpty(partName) && partName.ToLowerInvariant().Contains("forwardfuselage");
        }

        // T1017: the enable state to give back when a payload module we switched off leaves the shuttle. current = the module's state at the moment we first
        // switched it off, prefab = the part prefab's own state. A module found already OFF has no memory of who switched it (a save written with the payload
        // in the bay holds our switch): it gets the prefab's state, so a saved payload never comes back dead.
        public static bool SavedEnable(bool current, bool prefab)
        {
            return current || prefab;
        }

        // the leak's share of the part's tank: the aft part's tank serves both pods (the model has one), so a pod's leak takes its share of the part's jets
        public static double LeakShare(int podJets, int partJets)
        {
            if (podJets <= 0 || partJets <= 0) return 1.0;
            return Math.Min(1.0, (double)podJets / partJets);
        }
    }
}
