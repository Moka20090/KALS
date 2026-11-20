// PROX OPS, STKP: THE TARGET STATION-KEEPING CORE (plain C#, no Unity or KSP: the offline test tests/proxops_offline runs this same
// source; KalsAddon.Prox.cs reads the target and the orbiter from the game, calls Tick every physics tick and writes the translation
// into the flight control state).
// What it does:
//   NULL  the relative velocity (and, for a rotating target, the velocity of the point we are at) is driven to ~0 with the translation jets;
//   HOLD  the relative position at the END of NULL is kept, fixed in the TARGET's body frame (a tumbling target is followed), inside a box:
//         the jets fire only while the position is outside BOX_FIRE or the rate above V_FIRE, until both are back inside BOX_STOP / VDB.
//         (A null-only hold drifts by orbital mechanics; this one fires a few short pulses a minute instead of a continuous correction.)
// The setpoint is captured at the end of NULL, not at engage (the plan said engage): the null burn moves us, and holding the engage point
// would pull back against it (more fuel); say so in the report.
// Frames: every vector is in ONE inertial-aligned frame W (the game's world axes). B = the target's body basis (columns = its axes in W), Bd = the
// orbiter's (columns star, top, fore in W); the returned command is in the orbiter's BODY axes (star, top, fore), -1..1 per axis.
// The translation authority (m/s2 at full command) is learned per axis from the velocity change seen while a command above 0.3 is held.
// CSS: the crew moves the HOLD POINT, not the jets. THC (the pilot's translation in the orbiter's body axes) in NORM moves the point at
// NormRate x the stick while it is out of detent; in PULSE each tap (the stick out of detent after it was in) steps the point PulseStep along the
// largest stick axis. Released = hold there (the box controller). The hold stays fixed in the target's frame.
// The jets
// do nothing for a small command (the first burst and both pulse taps stopped their speed at a command of ~0.067, a lateral error of 0.11 m asked
// 0.07 and never moved), and the old estimator needed a command above 0.3 to learn, which a hold from rest never gives. Now: (1) a command under
// Floor (0.10) is DITHERED per axis (a sigma-delta accumulator fires Floor for one tick when the accumulated command reaches it: the average
// thrust is the command, every pulse is above the floor); (2) the authority is learned over 2 s windows from any mean command above 0.03, the
// disturbance acceleration (drift) taken from the quiet windows and removed, no response at all = Auth x 0.7 (the command rises until the
// jets answer); (3) after a PULSE tap Tau is 4 s for 12 s (the step reached 50 % in 10 s; Tau 5 / TauV 1.5 for the whole hold doubled its fuel).
// Real Shuttle note: the real orbiter had no automatic translation station-keeping (prox ops were flown by hand): STKP is a KAL/S aid.
using System;

namespace KalsCoproc
{
    public struct SkV
    {
        public double X, Y, Z;
        public SkV(double x, double y, double z) { X = x; Y = y; Z = z; }
        public static SkV operator +(SkV a, SkV b) { return new SkV(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
        public static SkV operator -(SkV a, SkV b) { return new SkV(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
        public static SkV operator -(SkV a) { return new SkV(-a.X, -a.Y, -a.Z); }
        public static SkV operator *(SkV a, double k) { return new SkV(a.X * k, a.Y * k, a.Z * k); }
        public double Dot(SkV b) { return X * b.X + Y * b.Y + Z * b.Z; }
        public SkV Cross(SkV b) { return new SkV(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X); }
        public double Mag { get { return Math.Sqrt(X * X + Y * Y + Z * Z); } }
        public double this[int i] { get { return i == 0 ? X : (i == 1 ? Y : Z); } }
    }

    // a rotation / basis: the columns are the axes
    public struct SkM
    {
        public SkV C0, C1, C2;
        public SkM(SkV c0, SkV c1, SkV c2) { C0 = c0; C1 = c1; C2 = c2; }
        public static SkM Identity { get { return new SkM(new SkV(1, 0, 0), new SkV(0, 1, 0), new SkV(0, 0, 1)); } }
        public SkV Mul(SkV v) { return C0 * v.X + C1 * v.Y + C2 * v.Z; }               // local -> W
        public SkV MulT(SkV w) { return new SkV(C0.Dot(w), C1.Dot(w), C2.Dot(w)); }     // W -> local
        public SkV Col(int i) { return i == 0 ? C0 : (i == 1 ? C1 : C2); }
    }

    public class StationKeep
    {
        public const int OFF = 0, NULL = 1, HOLD = 2;
        public const int M_NONE = 0, M_RANGE = 1, M_CLOSING = 2, M_TUMBLE = 3, M_LOST = 4, M_HOLD = 5, M_STEADY = 6;
        // first guesses (constants; the plan says so)
        public double RangeMax = 200, ClosingMax = 1.0;                 // engage gates, m, m/s
        public double RateMaxDeg = 0.5, RateBackDeg = 0.4;              // the target's rate the attitude can follow; back under this the frame is followed again
        public double BoxFire = 0.2, BoxStop = 0.05, BoxMax = 0.3;      // m: fire above BoxFire, stop inside BoxStop; BoxMax = the promised box (test)
        public double VFire = 0.01, VDb = 0.004, VStop = 0.0015;                        // m/s
        public double Tau = 8.0, VMax = 0.15, TauV = 2.0, TauN = 2.0;   // position time constant s, max closing speed m/s, velocity loops s
        public double TauMove = 4.0, MoveTime = 12.0;                    // After a PULSE tap the position time constant is TauMove for MoveTime s (the step arrives, the hold keeps its fuel)
        public double Floor = 0.10;                                     // A command under this is dithered per axis (0 = off, the one-place revert of the dither)
        public double LearnWin = 2.0, LearnMinU = 0.03, QuietU = 0.005; // s window, mean command to learn from, mean command of a quiet window
        public double NullHold = 3.0, UMinOut = 0.004;                   // s the velocity must stay in VDb before HOLD; command below this is 0
        public double NormRate = 0.05, PulseStep = 0.25, StickDet = 0.05;   // CSS: m/s at full stick (NORM), m per tap (PULSE), the detent
        public int CssMode;                                             // 0 = STKP alone, 1 = CSS NORM, 2 = CSS PULSE
        public SkV SetVel;                                              // the hold point's velocity in the target's frame (CSS NORM moving it)
        bool pulseArm = true;
        public double[] Auth = { 0.1, 0.1, 0.1 };                       // m/s2 at command 1 per body axis (learned)
        public double AuthLo = 0.005, AuthHi = 2.0;

        public int Phase = OFF, Msg = M_NONE;
        public bool AttInrtl;                                           // the target turns faster than the attitude can follow: hold INRTL, the position setpoint frozen in W
        public bool Firing;                                             // HOLD: the box controller is active
        public SkV SetLocal, SetW;                                       // the hold point in the target frame / frozen in W
        public SkV ErrP, ErrV;                                           // last tick, W
        public double Range, RDot;
        public double[] LastU = new double[3];                          // the DELIVERED command (after the dither), body axes
        public SkV ErrPb, ErrVb;                                        // the errors in the orbiter's body axes (star, top, fore), last tick (flight diagnostics)
        public double[] Dist = new double[3];                           // the learned disturbance acceleration per body axis, m/s2

        double nullT, moveT;
        SkV prevV; bool havePrev; double[] prevU = new double[3]; SkM prevBd;
        double[] lrnDv = new double[3], lrnU = new double[3], ditAcc = new double[3];
        double lrnT;
        public int AuthN;                                               // learning windows closed (test)

        // Who gets the RHC. While STKP is on the stick is the DAP's (CSS) only when
        // STICK ORB is chosen (orb) and the page's INPUT is the stick's (dapStk); with STICK ARM the RHC goes to the arm alone (its readback), never to the orbiter.
        // Decided in C# every physics frame; kOS only pushes orb on a change (PROXSTICK) and dapStk each cycle (O2DAPCYC).
        public static bool StickToDap(bool stkpOn, bool orb, bool dapStk) { return dapStk && (!stkpOn || orb); }

        public static string MsgText(int m)
        {
            switch (m)
            {
                case M_RANGE: return "STKP: TGT OUT OF RANGE";
                case M_CLOSING: return "STKP: CLOSING TOO FAST";
                case M_TUMBLE: return "STKP: TGT RATE HIGH, ATT INRTL";
                case M_LOST: return "STKP: TGT LOST";
                case M_HOLD: return "STKP: HOLD";
                case M_STEADY: return "STKP: ATT TGT FRAME";
                default: return "";
            }
        }

        public bool Engage(SkV r, SkV v, SkM B, SkV wT)
        {
            double rg = r.Mag;
            if (rg > RangeMax) { Msg = M_RANGE; return false; }
            double closing = rg > 1e-6 ? -r.Dot(v) / rg : 0;
            if (closing > ClosingMax) { Msg = M_CLOSING; return false; }
            Phase = NULL; Msg = M_NONE; nullT = 0; moveT = 0; Firing = false; havePrev = false;
            AttInrtl = wT.Mag * 180 / Math.PI > RateMaxDeg;
            if (AttInrtl) Msg = M_TUMBLE;
            SetLocal = B.MulT(r); SetW = r;
            lrnT = 0;
            for (int i = 0; i < 3; i++) { lrnDv[i] = lrnU[i] = ditAcc[i] = 0; LastU[i] = 0; prevU[i] = 0; Dist[i] = 0; }
            return true;
        }

        public void Disengage() { Phase = OFF; Firing = false; AttInrtl = false; for (int i = 0; i < 3; i++) { LastU[i] = 0; ditAcc[i] = 0; } }

        // one physics tick: r, v = the orbiter relative to the target (W), B = the target's basis, wT its angular velocity (W), Bd = the orbiter's.
        // Returns the translation command in the orbiter's body axes.
        public SkV Tick(double dt, bool valid, SkV r, SkV v, SkM B, SkV wT, SkM Bd)
        {
            return Tick(dt, valid, r, v, B, wT, Bd, new SkV(0, 0, 0));
        }

        // thc = the pilot's translation in the orbiter's body axes (star, top, fore), -1..1; used only with CssMode != 0 in HOLD
        public SkV Tick(double dt, bool valid, SkV r, SkV v, SkM B, SkV wT, SkM Bd, SkV thc)
        {
            if (Phase == OFF) return new SkV(0, 0, 0);
            if (!valid) { Disengage(); Msg = M_LOST; return new SkV(0, 0, 0); }
            Range = r.Mag; RDot = Range > 1e-9 ? r.Dot(v) / Range : 0;
            Learn(dt, v);
            // the target's rate: past RateMax the attitude drops to INRTL and the hold point is frozen in W (back under RateBack it is followed again)
            double rate = wT.Mag * 180 / Math.PI;
            if (!AttInrtl && rate > RateMaxDeg) { AttInrtl = true; SetW = B.Mul(SetLocal); Msg = M_TUMBLE; }
            else if (AttInrtl && rate < RateBackDeg) { AttInrtl = false; SetLocal = B.MulT(SetW); Msg = M_STEADY; }
            SkV w = AttInrtl ? new SkV(0, 0, 0) : wT;
            SkV acc;
            if (Phase == NULL)
            {
                SkV ve = v - w.Cross(r);                                 // the velocity of the target-fixed point we are at
                ErrV = ve; ErrP = new SkV(0, 0, 0);
                acc = ve * (-1.0 / TauN);
                if (ve.Mag < VDb) nullT += dt; else nullT = 0;
                if (nullT >= NullHold)
                {
                    Phase = HOLD; Msg = M_HOLD; Firing = false;
                    SetLocal = B.MulT(r); SetW = r;
                }
            }
            else
            {
                // CSS: the stick moves the hold point (NORM: at NormRate x stick, PULSE: PulseStep per tap along the largest axis), the point's own velocity
                // SetVel is fed forward below; released: SetVel 0 and the box controller holds the new point
                SetVel = new SkV(0, 0, 0);
                if (CssMode != 0)
                {
                    double sm = Math.Max(Math.Abs(thc.X), Math.Max(Math.Abs(thc.Y), Math.Abs(thc.Z)));
                    bool sOut = sm > StickDet;
                    SkV dW = new SkV(0, 0, 0);
                    if (CssMode == 1 && sOut)
                    {
                        SkV vW = Bd.Mul(thc * NormRate);
                        SetVel = vW; dW = vW * dt; Firing = true;
                    }
                    else if (CssMode == 2)
                    {
                        if (sOut && pulseArm)
                        {
                            int ax = 0; double best = Math.Abs(thc.X);
                            if (Math.Abs(thc.Y) > best) { ax = 1; best = Math.Abs(thc.Y); }
                            if (Math.Abs(thc.Z) > best) { ax = 2; }
                            dW = Bd.Col(ax) * (thc[ax] > 0 ? PulseStep : -PulseStep);
                            Firing = true; moveT = MoveTime;
                        }
                        pulseArm = !sOut;
                    }
                    if (dW.Mag > 0)
                    {
                        if (AttInrtl) SetW = SetW + dW; else SetLocal = SetLocal + B.MulT(dW);
                    }
                }
                if (moveT > 0) moveT -= dt;
                SkV sp = AttInrtl ? SetW : B.Mul(SetLocal);
                SkV e = r - sp;
                SkV ve = v - w.Cross(sp);
                ErrP = e; ErrV = ve;
                SkV vrel = ve - SetVel;
                if (!Firing) { if (e.Mag > BoxFire || ve.Mag > VFire) Firing = true; }
                else if (e.Mag < BoxStop && vrel.Mag < VStop) Firing = false;
                if (Firing)
                {
                    SkV vd = e * (-1.0 / (moveT > 0 ? TauMove : Tau));
                    double m = vd.Mag;
                    if (m > VMax) vd = vd * (VMax / m);
                    vd = vd + SetVel;
                    acc = (vd - ve) * (1.0 / TauV) + w.Cross(w.Cross(sp));     // + the setpoint's centripetal acceleration (a turning target)
                }
                else acc = new SkV(0, 0, 0);
            }
            // to the orbiter's body axes, over the learned authority
            SkV u = new SkV(0, 0, 0);
            double[] ui = new double[3];
            double dte = dt > 0 ? dt : 0.02;
            for (int i = 0; i < 3; i++)
            {
                double a = Bd.Col(i).Dot(acc);
                double k = a / Auth[i];
                if (k > 1) k = 1; else if (k < -1) k = -1;
                if (Math.Abs(k) < UMinOut) { k = 0; ditAcc[i] = 0; }
                else if (Floor > 0 && Math.Abs(k) < Floor)
                {
                    // sigma-delta: the accumulated (signed) command fires +-Floor for one tick when it reaches Floor x dt; the average delivered = the command
                    if (ditAcc[i] * k < 0) ditAcc[i] = 0;
                    ditAcc[i] += k * dte;
                    if (Math.Abs(ditAcc[i]) >= Floor * dte) { double sg = ditAcc[i] > 0 ? 1 : -1; ditAcc[i] -= sg * Floor * dte; k = sg * Floor; }
                    else k = 0;
                }
                else ditAcc[i] = 0;
                ui[i] = k;
            }
            u = new SkV(ui[0], ui[1], ui[2]);
            ErrPb = Bd.MulT(ErrP); ErrVb = Bd.MulT(ErrV);
            for (int i = 0; i < 3; i++) { LastU[i] = ui[i]; prevU[i] = ui[i]; }
            prevBd = Bd; prevV = v; havePrev = true;
            return u;
        }

        // the authority: over windows of LearnWin s the mean acceleration along each body axis against the mean DELIVERED command (signed, so the
        // dither's pulses count as they are); the disturbance (the acceleration of a window with no command) is taken out; a window with a command and no
        // response lowers Auth (the command rises until the jets answer)
        void Learn(double dt, SkV v)
        {
            if (!havePrev || dt <= 0) { lrnT = 0; for (int i = 0; i < 3; i++) lrnDv[i] = lrnU[i] = 0; return; }
            SkV dv = v - prevV;
            lrnT += dt;
            for (int i = 0; i < 3; i++) { lrnDv[i] += dv.Dot(prevBd.Col(i)); lrnU[i] += prevU[i] * dt; }
            if (lrnT < LearnWin) return;
            for (int i = 0; i < 3; i++)
            {
                double mu = lrnU[i] / lrnT, ma = lrnDv[i] / lrnT;
                if (Math.Abs(mu) < QuietU) Dist[i] = 0.5 * Dist[i] + 0.5 * ma;
                else if (Math.Abs(mu) >= LearnMinU)
                {
                    double est = (ma - Dist[i]) / mu;
                    double n = est > 0 ? 0.5 * Auth[i] + 0.5 * est : 0.7 * Auth[i];
                    Auth[i] = Math.Max(AuthLo, Math.Min(AuthHi, n));
                    AuthN++;
                }
                lrnDv[i] = lrnU[i] = 0;
            }
            lrnT = 0;
        }
    }
}
