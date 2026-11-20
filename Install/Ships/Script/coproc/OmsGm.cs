// OMS burns on the gimbals only. The pure state machine (the KSP side, the RCS group, the per-axis enables, the authority read and the
// thrust / gimbal reads are KalsAddon.O2Dap.cs). ops2q sets the MODE with O2DAPSET's 16th item at the ignition and 0 after the cut:
//     0 IDLE (today: the DAP's one command drives the jets, the gimbals and the wheels)
//     1 RCS OFF (two engines: the gimbals + the wheels fly the attitude)
//     2 RCS ROLL ONLY (one engine: its gimbal has pitch + yaw only; the pitch and yaw jets are disabled, the roll jets stay: the real
//       orbiter's TVC DAP did the same)
// The states: IDLE (mode 0), ARMED (mode set, the engines not at thrust yet: the jets still fly), ACTIVE (the jets off), BACK (the jets
// on again, latched until the mode is 0 again). ARMED -> ACTIVE when the lit engines give >= ON_FRAC of their available thrust.
// ACTIVE -> BACK when the thrust falls under OFF_FRAC (the cut's taper: the gimbal's authority goes with the thrust), a gimbal is
// locked (OMS 03), the attitude error stays over ERR_MAX for ERR_T s (the gimbal alone does not hold: the jets back), or the RCS
// was switched on from outside (mode 1). Step returns what the KSP side does: 0 nothing, 1 jets off (apply the mode), 2 jets back
// (restore), 3 re-apply (the mode changed 2 -> 1 while ACTIVE).
// An engine lost mid-burn (the mode 1 -> 2 while ACTIVE) moves the thrust line to the one
// engine's: the aim jumps 11 deg at once, and the lone gimbal + wheels (jets off) took 3.4 s of it before the 3 deg / 3 s fallback.
// Now the mode 1 -> 2 while ACTIVE is a TRANS state: the jets back at once (return 2, pitch + yaw jets on) for the turn, then ACTIVE
// in mode 2 (return 1: pitch / yaw jets off again) once the error has stayed under TRANS_ERR for TRANS_HOLD s; BACK (latched) if
// that has not happened in TRANS_MAX s, the gimbal is locked or the thrust is in the cut's taper. TRANS_ERR 0 = the old behaviour.
using System;

namespace KalsCoproc
{
    public class OmsGm
    {
        public const double ON_FRAC = 0.8, OFF_FRAC = 0.5, ERR_MAX = 3.0, ERR_T = 3.0;
        public const int IDLE = 0, ARMED = 1, ACTIVE = 2, BACK = 3, TRANS = 4;
        public static double TRANS_ERR = 0.5, TRANS_HOLD = 0.5, TRANS_MAX = 15.0;     // TRANS_ERR 0 = an engine loss re-applies at once
        public int Mode, State;
        public string Why = "";
        public double ErrT, TransT, SettleT;

        public int Step(int mode, double frac, bool locked, bool extOn, double ea, double dt)
        {
            if (mode < 0 || mode > 2) mode = 0;
            if (mode != Mode)
            {
                int old = Mode;
                Mode = mode;
                if (mode == 0)
                {
                    int act0 = State == ACTIVE ? 2 : 0;
                    State = IDLE; Why = ""; ErrT = 0; TransT = 0; SettleT = 0;
                    return act0;
                }
                if (State == IDLE) { State = ARMED; Why = ""; ErrT = 0; }
                else if (State == ACTIVE && old != 0)
                {
                    if (old == 1 && mode == 2 && TRANS_ERR > 0)
                    {
                        State = TRANS; Why = "ENGINE LOST: JETS ON FOR THE TURN"; TransT = 0; SettleT = 0; ErrT = 0;
                        return 2;
                    }
                    return 3;
                }
            }
            if (State == ARMED)
            {
                if (locked) { State = BACK; Why = "GIMBAL LOCKED"; return 0; }
                if (frac >= ON_FRAC) { State = ACTIVE; ErrT = 0; return 1; }
                return 0;
            }
            if (State == TRANS)
            {
                if (locked) { State = BACK; Why = "GIMBAL LOCKED"; return 0; }
                if (frac < OFF_FRAC) { State = BACK; Why = "THRUST " + Math.Round(frac * 100) + " % (THE TAPER)"; return 0; }
                TransT += dt;
                if (ea < TRANS_ERR) SettleT += dt; else SettleT = 0;
                if (SettleT >= TRANS_HOLD) { State = ACTIVE; Why = ""; ErrT = 0; return 1; }
                if (TransT >= TRANS_MAX) { State = BACK; Why = "ENGINE-LOSS TURN NOT SETTLED IN " + TRANS_MAX + " S"; return 0; }
                return 0;
            }
            if (State == ACTIVE)
            {
                if (locked) { State = BACK; Why = "GIMBAL LOCKED"; return 2; }
                if (frac < OFF_FRAC) { State = BACK; Why = "THRUST " + Math.Round(frac * 100) + " % (THE TAPER)"; return 2; }
                if (extOn && Mode == 1) { State = BACK; Why = "RCS SWITCHED ON FROM OUTSIDE"; return 2; }
                if (ea > ERR_MAX) ErrT += dt; else ErrT = Math.Max(0, ErrT - dt);
                if (ErrT >= ERR_T) { State = BACK; Why = "ATTITUDE ERROR " + Math.Round(ea, 1) + " DEG FOR " + ERR_T + " S"; return 2; }
            }
            return 0;
        }

        // the DAP let go (the watchdog, FBW3, a vessel change): what to do now, and the machine reset
        public int Abort(string why)
        {
            int act = State == ACTIVE ? 2 : 0;
            Mode = 0; State = IDLE; Why = why; ErrT = 0; TransT = 0; SettleT = 0;
            return act;
        }

        public string Text()
        {
            switch (State)
            {
                case ARMED: return "ARMED";
                case ACTIVE: return Mode == 2 ? "OFF (ROLL JETS ONLY)" : "OFF";
                case TRANS: return "ENGINE LOST: JETS ON FOR THE TURN";
                case BACK: return "BACK: " + Why;
                default: return Why.Length > 0 ? "IDLE: " + Why : "IDLE";
            }
        }
    }
}
