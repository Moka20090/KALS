// The ascent DAP's per-tick math (lib_ascent_dap.ks's ascDapTick, in C#), free of KSP types so it can be tested offline.
// The caller (KalsAddon.AscDap.cs) hands it the body frame each tick, the target's axes and rate, and B-hat / tau0-hat /
// I-hat; it returns the inputs (pitch, roll, yaw as KSP's ctrlState).
// Frames: the body x = STARVECTOR (pitch), y = FOREVECTOR (roll), z = -TOPVECTOR (yaw); every vector in one world frame.
// Per tick: the body rates from the frame's turn since the last tick; the attitude error to the target (rad: the sine of
// the angle along its axis); the wanted rates wd = ka e clipped as a vector at WMAX, plus the target's own rate; the
// wanted angular accelerations ad = kr (wd - w) + KI * the integral of (wd - w) (+ the target's acceleration when AFF);
// the torque td = I-hat ad; u = B-hat^-1 (td - tau0-hat). Saturated: the roll clipped, pitch and yaw solved with it and
// scaled together into -1..1, the integral held. kr = 2 zeta wn, ka = wn / (2 zeta).
using System;

namespace KalsCoproc
{
    public struct V3
    {
        public double x, y, z;
        public V3(double x, double y, double z) { this.x = x; this.y = y; this.z = z; }
        public static V3 operator +(V3 a, V3 b) { return new V3(a.x + b.x, a.y + b.y, a.z + b.z); }
        public static V3 operator -(V3 a, V3 b) { return new V3(a.x - b.x, a.y - b.y, a.z - b.z); }
        public static V3 operator -(V3 a) { return new V3(-a.x, -a.y, -a.z); }
        public static V3 operator *(V3 a, double k) { return new V3(a.x * k, a.y * k, a.z * k); }
        public static double Dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
        public static V3 Cross(V3 a, V3 b) { return new V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
        public double Mag { get { return Math.Sqrt(x * x + y * y + z * z); } }
    }

    public class AscDapCore
    {
        // the parameters (lib_ascent_dap's ASC_DAP_*)
        public double Wn = 1.0, Zeta = 0.8, WmaxDeg = 2.0, Ki = 0.3;
        public bool Aff = true;
        // the model: B-hat's columns (torque per unit pitch / roll / yaw input, body), tau0-hat (body), I-hat (Ixx, Iyy, Izz, Iyz)
        public V3 B0, B1, B2, T0;
        public double Ixx, Iyy, Izz, Iyz;
        public bool HaveModel;
        // the state
        public V3 Ex, Ey, Ez, Iw, U, E, W;
        public double T;
        public int Sat, Ticks;
        public bool Started;

        // the model from its parts; FALSE (the last one kept) when B-hat is singular (no engine running)
        public bool SetModel(V3 b0, V3 b1, V3 b2, V3 t0, double ixx, double iyy, double izz, double iyz)
        {
            double det = V3.Dot(b0, V3.Cross(b1, b2));
            if (Math.Abs(det) < 1) return false;
            B0 = b0; B1 = b1; B2 = b2; T0 = t0;
            Ixx = ixx; Iyy = iyy; Izz = izz; Iyz = iyz;
            HaveModel = true;
            return true;
        }

        public void Start(V3 ex, V3 ey, V3 ez, double t)
        {
            Ex = ex; Ey = ey; Ez = ez; T = t;
            Iw = new V3(0, 0, 0); U = new V3(0, 0, 0); E = new V3(0, 0, 0); W = new V3(0, 0, 0);
            Sat = 0; Ticks = 0; Started = true;
        }

        // one tick: the body frame now (world), the target's star / fore / -top (world), its rate and acceleration
        // (world, rad/s, rad/s2) -> the inputs (pitch, roll, yaw), or FALSE when no tick ran (no time passed, no model)
        // eff: the reference moved back by a ramped slew's lag (world, rad), taken off the error (lib_ascent_dap's "eff")
        public bool Tick(V3 ex, V3 ey, V3 ez, double t, V3 ts, V3 tf, V3 tz, V3 wff, V3 eff, V3 aff, out V3 u)
        {
            u = U;
            double dt = t - T;
            if (dt <= 0 || !Started) return false;
            V3 ph = (V3.Cross(Ex, ex) + V3.Cross(Ey, ey) + V3.Cross(Ez, ez)) * (0.5 / dt);
            Ex = ex; Ey = ey; Ez = ez; T = t;
            var w = new V3(V3.Dot(ph, ex), V3.Dot(ph, ey), V3.Dot(ph, ez));
            V3 er = (V3.Cross(ex, ts) + V3.Cross(ey, tf) + V3.Cross(ez, tz)) * 0.5 - eff;
            var ea = new V3(V3.Dot(er, ex), V3.Dot(er, ey), V3.Dot(er, ez));
            W = w; E = ea;
            if (!HaveModel) return false;
            Ticks++;
            double kr = 2 * Zeta * Wn, ka = Wn / (2 * Zeta), wm = WmaxDeg * Math.PI / 180;
            V3 wd = ea * ka;
            if (wd.Mag > wm) wd = wd * (wm / wd.Mag);             // clipped as a vector (the turn about the error's axis)
            wd = wd + new V3(V3.Dot(wff, ex), V3.Dot(wff, ey), V3.Dot(wff, ez));
            V3 ew = wd - w;
            V3 ad = ew * kr + Iw * Ki;
            if (Aff) ad = ad + new V3(V3.Dot(aff, ex), V3.Dot(aff, ey), V3.Dot(aff, ez));
            var td = new V3(Ixx * ad.x, Iyy * ad.y + Iyz * ad.z, Iyz * ad.y + Izz * ad.z);
            V3 rhs = td - T0;
            double det = V3.Dot(B0, V3.Cross(B1, B2));
            V3 r0 = V3.Cross(B1, B2) * (1 / det), r1 = V3.Cross(B2, B0) * (1 / det), r2 = V3.Cross(B0, B1) * (1 / det);
            u = new V3(V3.Dot(r0, rhs), V3.Dot(r1, rhs), V3.Dot(r2, rhs));
            if (Math.Max(Math.Abs(u.x), Math.Max(Math.Abs(u.y), Math.Abs(u.z))) > 1)
            {
                double ur = Math.Max(-1, Math.Min(1, u.y));
                double a0 = rhs.x - B1.x * ur, a2 = rhs.z - B1.z * ur;
                double d2 = B0.x * B2.z - B2.x * B0.z;
                double upi = 0, uy = 0;
                if (Math.Abs(d2) > 1)
                {
                    upi = (a0 * B2.z - B2.x * a2) / d2;
                    uy = (B0.x * a2 - a0 * B0.z) / d2;
                }
                double mx = Math.Max(Math.Abs(upi), Math.Abs(uy));
                if (mx > 1) { upi /= mx; uy /= mx; }
                u = new V3(upi, ur, uy);
                Sat++;
            }
            else Iw = Iw + ew * dt;                                 // no wind-up while saturated
            U = u;
            return true;
        }
    }
}
