// The kOS side of O2Burn.cs -- the suffix bodies (KalsAddon.O2Burn.cs registers them on ADDONS:KALS; the offline VM's o2bworld.cs
// registers the same bodies, so tests/o2burn_offline runs these exact functions). kOS types only (no Unity), none of them throws into kOS:
// a bad list makes the call return a STRING "error ..." (or FALSE for Arm), and the kOS wrapper (lib_o2burn.ks) takes that as 'C# not there'.
//   O2BURNARM(cfg LIST) -> TRUE | "error ..."     a new burn at the ignition; cfg: [0..2] VGO (m/s, inertial), [3] tot, [4] tb (s), [5] the ignition UT,
//        [6..14] O2P_CUT, O2P_TAPER_S, O2P_TAPER_DT_K, O2P_DTM_DECAY, O2P_HOLD_DV, O2P_HOLD_TGO, O2P_GUARD_K, O2P_GUARD_S, O2P_AXIS_MIN,
//        [15..18] O2Q_AIM_FREEZE_V, O2Q_FRZ_MEAS (0/1), O2Q_FRZ_MEAS_V, O2Q_FRZ_MEAS_MAX, [19] O2Q_FFO (0/1), [20] O2Q_LOG_TICKS
//   O2BURNSENSE(in LIST(23)) -> LIST(scalar event 0/1, the axes' ratio, hold 0/1, VGO xyz)      the count of this tick (o2pSense + the 1 s axis check)
//   O2BURNSETVGO(LIST(x, y, z)) -> TRUE        PEG 4's / PEG 8's re-solved VGO, between the Sense and the Decide
//   O2BURNDECIDE() -> LIST(23)                 the end, the throttle, the steering line, the aim, the freeze (see Out below)
//   O2BURNSTEP(in) -> LIST(23)                 O2BURNSENSE + O2BURNDECIDE in one call (PEG 7: no re-solve in between)
//   O2BURNSTATE() -> LIST(19)                  the log's numbers: VGO xyz, sensed xyz, tot, dtm, hold, tguard, aav, t0, along (o2pAlong), ticks,
//        tprev, has-guard (0/1), the held direction xyz
// in (O2Burn.IN_N = 23): see O2Burn.cs. Out of Decide / Step: [0] why ("" / CUT / THRUST / GUARD / OMS / CREW), [1] throttle, [2] along,
// [3..5] the aim direction (valid with event 32), [6..8] the steering line tl (the trim line, or the engines' own when scalar), [9] the event word
// (1 taper stretched, 2 trim-vs-measured check, 4 aim frozen now, 8 ... with the measured line, 16 the early bias wanted, 32 aim the DAP on
// [3..5], 64 a log row, 128 the burn ends), [10] the taper s, [11] the peak tick, [12] ticks, [13] along at the freeze, [14] the measured line's
// angle off the frozen direction, [15] tl's angle off it, [16..18] the frozen direction, [19] the available acceleration, [20..22] the Sense's.
using System;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class O2BurnKos
    {
        static readonly O2Burn B = new O2Burn();
        static int sense;
        static double senseRatio;

        static double D(Structure s)
        {
            var sc = s as ScalarValue;
            if (sc == null) throw new Exception("not a number");
            double d = sc.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new Exception("not finite");
            return d;
        }
        static double[] Take(ListValue l, int n)
        {
            if (l == null || l.Count < n) throw new Exception("the list has " + (l == null ? 0 : l.Count) + " items, wants " + n);
            var x = new double[n];
            int i = 0;
            foreach (Structure s in l) { if (i >= n) break; x[i++] = D(s); }
            return x;
        }
        static ListValue Mk(params object[] v)
        {
            var l = new ListValue();
            foreach (object o in v)
            {
                if (o is string) l.Add(new StringValue((string)o));
                else if (o is bool) l.Add(new BooleanValue((bool)o));
                else l.Add(ScalarValue.Create(Convert.ToDouble(o)));
            }
            return l;
        }

        public static Structure Arm(ListValue l)
        {
            try
            {
                double[] c = Take(l, 21);
                B.Cut = c[6]; B.TaperS = c[7]; B.TaperDtK = c[8]; B.DtmDecay = c[9]; B.HoldDv = c[10]; B.HoldTgo = c[11]; B.GuardK = c[12]; B.GuardS = c[13]; B.AxisMin = c[14];
                B.AimFreezeV = c[15]; B.FrzMeas = c[16] != 0; B.FrzMeasV = c[17]; B.FrzMeasMax = c[18]; B.Ffo = c[19] != 0; B.LogTicks = (int)Math.Round(c[20]);
                if (B.LogTicks < 1) B.LogTicks = 1;
                B.Arm(new double[] { c[0], c[1], c[2] }, c[3], c[4], c[5]);
                sense = 0; senseRatio = 0;
                return BooleanValue.True;
            }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        static ListValue SenseOut() { return Mk(sense, senseRatio, B.Hold ? 1 : 0, B.Vgo[0], B.Vgo[1], B.Vgo[2]); }

        public static Structure Sense(ListValue l)
        {
            try
            {
                if (!B.Armed) return new StringValue("error not armed");
                sense = B.Sense(Take(l, O2Burn.IN_N));
                senseRatio = B.ScalarRatio;
                return SenseOut();
            }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        public static Structure SetVgo(ListValue l)
        {
            try { B.SetVgo(Take(l, 3)); return BooleanValue.True; }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        static ListValue Out()
        {
            return Mk(B.Why, B.Thr, B.Along, B.AimDir[0], B.AimDir[1], B.AimDir[2], B.Tl[0], B.Tl[1], B.Tl[2], B.Events, B.Tpr, B.Dtm, B.N,
                B.FrzAlong, B.AngOl, B.AngTl, B.DirF[0], B.DirF[1], B.DirF[2], B.AAv, sense, senseRatio, B.Hold ? 1 : 0);
        }

        public static Structure Decide()
        {
            try
            {
                if (!B.Armed) return new StringValue("error not armed");
                B.Decide();
                return Out();
            }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        public static Structure Step(ListValue l)
        {
            try
            {
                if (!B.Armed) return new StringValue("error not armed");
                sense = B.Sense(Take(l, O2Burn.IN_N));
                senseRatio = B.ScalarRatio;
                B.Decide();
                return Out();
            }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        public static Structure State()
        {
            try
            {
                if (!B.Armed) return new StringValue("error not armed");
                double al = B.AlongNow();                       // o2pAlong: the same Dir() call the kOS log's own o2pAlong makes
                return Mk(B.Vgo[0], B.Vgo[1], B.Vgo[2], B.Sens[0], B.Sens[1], B.Sens[2], B.Tot, B.Dtm, B.Hold ? 1 : 0, B.Tguard, B.Aav, B.T0, al, B.N,
                    B.Tprev, B.HasGuard ? 1 : 0, B.Hdir[0], B.Hdir[1], B.Hdir[2]);
            }
            catch (Exception ex) { return new StringValue("error " + ex.GetType().Name + ": " + ex.Message); }
        }

        // the burn is over / dropped: the next Step says 'not armed' until the next Arm
        public static Structure Drop() { B.Armed = false; return BooleanValue.True; }
    }
}
