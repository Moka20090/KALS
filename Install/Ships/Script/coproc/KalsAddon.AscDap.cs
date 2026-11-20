// The ascent DAP (lib_ascent_dap.ks's ascDapTick; the math in AscDap.cs) flown in the fly-by-wire handler
// (KalsAddon.YawJet.cs YjFbw, every physics tick) in place of kOS's cooked steering. ops1q hands it the target each main
// loop pass; the model is built here from the vessel itself:
//   B-hat (the torque per unit pitch / roll / yaw input) every BDT s from every running engine with an unlocked gimbal:
//   KSP's gimbal law (ModuleGimbal.FixedUpdate / GimbalRotation, IL-read) linearized per gimbal transform: the input in
//   the control part's frame (ReferenceTransform: x right = pitch, y up = the nose = roll, z forward = yaw), pitch and yaw
//   flipped when the gimbal is forward of the CoM, the roll added to x and z by the side of the control axis the gimbal
//   is on (beyond its minRollOffset), each axis gated by its switch; into the gimbal's neutral frame, x and y kept (z
//   turns nothing), times the range (the mean of the + and - ranges) x the limiter; the nozzle's turn theta (world) gives
//   the torque (pivot - CoM) x (theta x F), F = the engine's thrust along its thrust transforms (KSP's -forward), split
//   over the gimbal's transforms. The thrust point lies on the thrust axis through the pivot, so the pivot is the lever
//   arm (the SRB's is ~10.6 m below its part origin). tau0-hat = sum (pivot - CoM) x F, F along each
//   nozzle's neutral axis (the deflection is the inputs' own torque, in B-hat).
//   I-hat (refreshed with B-hat) = the vessel's own inertia tensor about the CoM, summed from its rigid bodies as KSP sums
//   Vessel.MOI (VesselPrecalculate.CalculatePhysicsStats, IL-read), with the off-diagonal Iyz that Vessel.MOI drops;
//   the polynomials in the vessel's mass that ops1q hands it (stage 1 / stage 2 sets) are the fallback: no rigid body,
//   a non-finite tensor, a diagonal term outside 0.5 .. 1.5 x its polynomial, or Iyz of the other sign.
//   The log marks which flew ("#ihat,live,Ixx,Iyy,Izz,Iyz" / "#ihat,fallback,<why>" at each change) and adds a row each
//   second: "#bhat,t, B-hat's columns (9), the live tensor (Ixx Iyy Izz Iyz Ixy Ixz), the polynomials (Ixx Iyy Izz Iyz)".
//     ADDONS:KALS:ASCDAP(LIST(LIST(WN, ZETA, WMAX deg/s, KI, BDT s, AFF 0/1, TGT_TMAX s), LIST(IXX c2 c1 c0, IYY .., IZZ ..,
//         IYZ ..), log)) -> "" or "error ...". The first call starts it (frames now, the integral 0); a call while it flies
//         changes the parameters and I-hat only (the state kept: bumpless at SRB separation).
//     ADDONS:KALS:ASCDAPTGT(Direction, LIST(wff, eff, aff)) -> 0: the target (kOS's raw frame) and its rate (rad/s), the
//         ramp's lag (rad) and its acceleration (rad/s2), raw vectors. With no target for TGT_TMAX s the DAP lets go.
//     ADDONS:KALS:ASCDAPOFF -> TRUE: released (FBW3, FBWOFF and YAWJETAXES(FALSE) release it too), its log closed.
//     ADDONS:KALS:ASCDAPSTATE -> LIST(on, engines, saturated ticks, error deg (pitch, roll, yaw), rate deg/s, the inputs,
//         ticks, why released, mass t).
//     ADDONS:KALS:ASCIHAT(LIST(Ixx, Iyy, Izz, Iyz)) -> LIST(Ixx, Iyy, Izz, Iyz, why): kOS's vessel's live tensor in this
//         DAP's frame (t m^2) and "", or, where the guard above refuses it, the polynomial values passed in and why
//         (lib_ascent_dap's engine-out DAP, every B-hat update).
using System;
using System.Globalization;
using System.IO;
using System.Text;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using UnityEngine;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        enum AsdP { WN, ZETA, WMAX, KI, BDT, AFF, TGT_TMAX, N }

        static bool asdOn;
        static readonly AscDapCore asd = new AscDapCore();
        static readonly double[] asdPar = new double[(int)AsdP.N];
        static readonly double[] asdPoly = new double[12];
        static Quaternion asdTgt;
        static V3 asdWff, asdEff, asdAff;
        static double asdTgtT, asdTb, asdT0, asdMass;
        static int asdEng;
        static string asdWhy = "", asdLog;
        static readonly StringBuilder asdBuf = new StringBuilder();
        static int asdBufN;
        static V3 asdD;         // the last B-hat's diagonal (log)
        static readonly double[] asdI = new double[6];  // the live tensor (body: xx yy zz yz xy xz), t m^2
        static readonly double[] asdIk = new double[6]; // ASCIHAT's (kOS's DAP)
        static int asdIState;   // 0 none yet, 1 live, 2 the polynomials (log at each change)
        static double asdBhT;   // the next #bhat row

        partial void RegisterAscDap()
        {
            AddSuffix("ASCDAP", new OneArgsSuffix<StringValue, ListValue>(l => new StringValue(AsdArm(shared.Vessel, l))));
            AddSuffix("ASCDAPTGT", new TwoArgsSuffix<ScalarValue, kOS.Suffixed.Direction, ListValue>((d, l) =>
            {
                asdTgt = d.Rotation;
                asdWff = AsdV(l, 0); asdEff = AsdV(l, 1); asdAff = AsdV(l, 2);
                asdTgtT = Planetarium.GetUniversalTime();
                return ScalarValue.Create(0);
            }));
            AddSuffix("ASCDAPOFF", new Suffix<BooleanValue>(() => { AsdOff("ASCDAPOFF"); return new BooleanValue(true); }));
            AddSuffix("ASCIHAT", new OneArgsSuffix<ListValue, ListValue>(l => AsdIhat(shared.Vessel, l)));
            AddSuffix("ASCDAPSTATE", new Suffix<ListValue>(() =>
            {
                var l = new ListValue();
                l.Add(new BooleanValue(asdOn)); l.Add(ScalarValue.Create(asdEng)); l.Add(ScalarValue.Create(asd.Sat));
                l.Add(new kOS.Suffixed.Vector(asd.E.x * 57.2958, asd.E.y * 57.2958, asd.E.z * 57.2958));
                l.Add(new kOS.Suffixed.Vector(asd.W.x * 57.2958, asd.W.y * 57.2958, asd.W.z * 57.2958));
                l.Add(new kOS.Suffixed.Vector(asd.U.x, asd.U.y, asd.U.z));
                l.Add(ScalarValue.Create(asd.Ticks)); l.Add(new StringValue(asdWhy)); l.Add(ScalarValue.Create(asdMass));
                return l;
            }));
        }

        static V3 AsdV(ListValue l, int i)
        {
            if (l == null || l.Count <= i) return new V3(0, 0, 0);
            Vector3d v = ((kOS.Suffixed.Vector)l[i]).ToVector3D();
            return new V3(v.x, v.y, v.z);
        }

        static V3 AsdV3(Vector3d v) { return new V3(v.x, v.y, v.z); }

        static string AsdArm(Vessel v, ListValue l)
        {
            try
            {
                if (v == null) return "error no vessel";
                var pl = (ListValue)l[0];
                if (pl.Count < (int)AsdP.N) return "error " + pl.Count + " parameters, want " + (int)AsdP.N;
                var il = (ListValue)l[1];
                if (il.Count < 12) return "error " + il.Count + " I-hat coefficients, want 12";
                for (int k = 0; k < (int)AsdP.N; k++) asdPar[k] = HoD(pl[k]);
                for (int k = 0; k < 12; k++) asdPoly[k] = HoD(il[k]);
                asd.Wn = asdPar[(int)AsdP.WN]; asd.Zeta = asdPar[(int)AsdP.ZETA]; asd.WmaxDeg = asdPar[(int)AsdP.WMAX];
                asd.Ki = asdPar[(int)AsdP.KI]; asd.Aff = asdPar[(int)AsdP.AFF] != 0;
                double now = Planetarium.GetUniversalTime();
                asdTb = now;                                    // the model at the next tick
                if (asdOn && yjVessel != v) AsdOff("new vessel");   // left on by a flight that ended (a revert, a pad loss)
                if (asdOn)
                {
                    Debug.Log("[KalsCoproc] ascent DAP re-armed: WN " + HoF(asd.Wn) + ", mass " + HoF(v.totalMass) + " t");
                    if (asdLog != null) asdBuf.Append("#rearm wn ").Append(HoF(asd.Wn)).Append('\n');
                    return "";
                }
                // ops2q's DAP / STKP left on by a revert from orbit (static state) would override this DAP for 100 ticks
                try { O2dOff("ASCENT DAP ON"); } catch (Exception) { }
                try { PxOff("ascent DAP on"); } catch (Exception) { }
                bool log = ((BooleanValue)l[2]).Value;
                Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
                asdTgt = F; asdWff = new V3(0, 0, 0); asdEff = asdWff; asdAff = asdWff; asdTgtT = now;
                asd.HaveModel = false;
                asd.Start(AsdV3(F * Vector3.right), AsdV3(F * Vector3.forward), -AsdV3(F * Vector3.up), now);
                asdT0 = now; asdWhy = ""; asdEng = 0; asdIState = 0; asdBhT = 0;
                asdBuf.Length = 0; asdBufN = 0; asdLog = null;
                if (log)
                {
                    string dir = Path.Combine(KSPUtil.ApplicationRootPath, "Ships/Script/logs");
                    Directory.CreateDirectory(dir);
                    // never over an existing file (the flight id repeats when one save is reloaded). The id kOS gives (ops1q:
                    // l[3], the same as its ascent_peg_<id>.csv) when it is a plain <ut>[_<k>] and free; else the first free <ut>, <ut>_2 ...
                    string idBase = Math.Round(now).ToString("F0", CultureInfo.InvariantCulture);
                    string idGive = (l.Count > 3 && l[3] is StringValue) ? ((StringValue)l[3]).ToString() : "";
                    bool idOk = idGive.Length > 0 && idGive.Length < 24;
                    foreach (char ch in idGive) if (!((ch >= '0' && ch <= '9') || ch == '_')) idOk = false;
                    asdLog = Path.Combine(dir, "ascdap_" + (idOk ? idGive : idBase) + ".csv");
                    for (int idK = 2; File.Exists(asdLog) && idK < 1000; idK++) asdLog = Path.Combine(dir, "ascdap_" + idBase + "_" + idK + ".csv");
                    File.WriteAllText(asdLog, "t,n,mass,e_p,e_r,e_y,w_p,w_r,w_y,u_p,u_r,u_y,sat,b_pp,b_rr,b_yy,t0_p,t0_r,t0_y,"
                        + "i_xx,i_yy,i_zz,i_yz,moi_x,moi_y,moi_z,wff_p,wff_r,wff_y,ctl_p,ctl_r,ctl_y\n");
                }
                if (yjVessel != null && yjVessel != v) yjVessel.OnFlyByWire -= YjFbw;
                v.OnFlyByWire -= YjFbw;
                v.OnFlyByWire += YjFbw;
                yjVessel = v;
                asdOn = true;
                Debug.Log("[KalsCoproc] ascent DAP on: WN " + HoF(asd.Wn) + ", mass " + HoF(v.totalMass) + " t");
                return "";
            }
            catch (Exception ex) { asdOn = false; return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        static void AsdOff(string why)
        {
            if (!asdOn) return;
            asdOn = false;
            asdWhy = why;
            // the axes back at once, not after the handler's 0.5 s (FBW3 sets its own right after)
            for (int i = 0; i < 2; i++) { fbCmd[i] = 0; fbT[i] = -1E9; }
            yjCmd = 0; yjT = -1E9;
            if (asdLog != null) asdBuf.Append("#off ").Append(why).Append('\n');
            AsdFlush();
            Debug.Log("[KalsCoproc] ascent DAP off (" + why + ") after " + asd.Ticks + " ticks, " + asd.Sat + " saturated");
        }

        static void AsdFlush()
        {
            if (asdLog == null || asdBuf.Length == 0) return;
            try { File.AppendAllText(asdLog, asdBuf.ToString()); } catch (Exception) { }
            asdBuf.Length = 0; asdBufN = 0;
        }

        static double AsdPoly(int k, double m) { return (asdPoly[3 * k] * m + asdPoly[3 * k + 1]) * m + asdPoly[3 * k + 2]; }

        // the inertia tensor about the CoM into o (body: xx yy zz yz xy xz, t m^2): each rigid body's principal tensor
        // turned into the world (the part's rotation x inertiaTensorRotation, as Vessel.MOI) plus m (|d|^2 1 - d d^T), d
        // from the CoM to the body's own CoM (the point its tensor is about; Vessel.MOI takes rb.position); the bodies counted
        static int AsdInertia(Vessel v, V3 ex, V3 ey, V3 ez, double[] o)
        {
            var w = new double[3, 3];
            Vector3d com = v.CurrentCoM;
            int n = 0;
            foreach (Part p in v.parts)
            {
                Rigidbody rb = p.rb;
                if (rb == null) continue;
                n++;
                Quaternion q = p.transform.rotation * rb.inertiaTensorRotation;
                Vector3 it = rb.inertiaTensor, a0 = q * Vector3.right, a1 = q * Vector3.up, a2 = q * Vector3.forward;
                Vector3d d = (Vector3d)rb.worldCenterOfMass - com;
                double m = rb.mass, dd = Vector3d.Dot(d, d);
                for (int i = 0; i < 3; i++)
                    for (int j = 0; j < 3; j++)
                        w[i, j] += it.x * a0[i] * a0[j] + it.y * a1[i] * a1[j] + it.z * a2[i] * a2[j] + m * ((i == j ? dd : 0) - d[i] * d[j]);
            }
            V3[] e = { ex, ey, ez };
            int[,] ab = { { 0, 0 }, { 1, 1 }, { 2, 2 }, { 1, 2 }, { 0, 1 }, { 0, 2 } };
            for (int k = 0; k < 6; k++)
            {
                V3 a = e[ab[k, 0]], b = e[ab[k, 1]];
                double[] av = { a.x, a.y, a.z }, bv = { b.x, b.y, b.z };
                double s = 0;
                for (int i = 0; i < 3; i++)
                    for (int j = 0; j < 3; j++) s += av[i] * w[i, j] * bv[j];
                o[k] = s;
            }
            return n;
        }

        // why the live tensor it (AsdInertia's) can't fly this refresh (null: it can), against the polynomials pi (xx yy zz yz)
        static string AsdIWhy(int nrb, double[] it, double[] pi)
        {
            if (nrb == 0) return "no rigid bodies";
            for (int k = 0; k < 6; k++) if (double.IsNaN(it[k]) || double.IsInfinity(it[k])) return "non-finite";
            string[] nm = { "Ixx", "Iyy", "Izz" };
            for (int k = 0; k < 3; k++)
                if (!(it[k] >= 0.5 * pi[k] && it[k] <= 1.5 * pi[k])) return nm[k] + " " + HoF(it[k]) + " vs polynomial " + HoF(pi[k]);
            if (Math.Abs(it[3]) > 100 && Math.Abs(pi[3]) > 100 && Math.Sign(it[3]) != Math.Sign(pi[3]))
                return "Iyz " + HoF(it[3]) + " vs polynomial " + HoF(pi[3]);
            return null;
        }

        // ASCIHAT: kOS's vessel's live tensor in the DAP's frame, or the polynomial values pi it passed and why
        static ListValue AsdIhat(Vessel v, ListValue l)
        {
            var pi = new double[4];
            string why;
            try
            {
                for (int k = 0; k < 4; k++) pi[k] = HoD(l[k]);
                if (v == null) why = "no vessel";
                else
                {
                    Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
                    int n = AsdInertia(v, AsdV3(F * Vector3.right), AsdV3(F * Vector3.forward), -AsdV3(F * Vector3.up), asdIk);
                    why = AsdIWhy(n, asdIk, pi);
                }
            }
            catch (Exception ex) { why = "error " + ex.GetType().Name + ": " + ex.Message; }
            var r = new ListValue();
            for (int k = 0; k < 4; k++) r.Add(ScalarValue.Create(why == null ? asdIk[k] : pi[k]));
            r.Add(new StringValue(why ?? ""));
            return r;
        }

        // B-hat (columns, body), tau0-hat (body) from the running engines' gimbals; the engines counted
        static int AsdModel(Vessel v, V3 ex, V3 ey, V3 ez, out V3 b0, out V3 b1, out V3 b2, out V3 t0)
        {
            Vector3d c0 = Vector3d.zero, c1 = Vector3d.zero, c2 = Vector3d.zero, tz = Vector3d.zero;
            Transform rt = v.ReferenceTransform;
            Vector3d com = v.CurrentCoM;
            Vector3 lcom = rt.InverseTransformPoint(v.CurrentCoM);
            int n = 0;
            foreach (Part p in v.parts)
            {
                ModuleGimbal g = null;
                foreach (PartModule m in p.Modules) { g = m as ModuleGimbal; if (g != null) break; }
                foreach (PartModule m in p.Modules)
                {
                    ModuleEngines e = m as ModuleEngines;
                    if (e == null || !e.EngineIgnited || !e.isOperational || e.finalThrust < 0.1f || e.thrustTransforms == null || e.thrustTransforms.Count == 0) continue;
                    Vector3d fd = Vector3d.zero;
                    for (int i = 0; i < e.thrustTransforms.Count; i++)
                    {
                        double mu = e.thrustTransformMultipliers != null && i < e.thrustTransformMultipliers.Count ? e.thrustTransformMultipliers[i] : 1.0 / e.thrustTransforms.Count;
                        fd += -(Vector3d)e.thrustTransforms[i].forward * mu;
                    }
                    Vector3d F = fd * e.finalThrust;                          // kN
                    bool gim = g != null && g.moduleIsEnabled && !g.gimbalLock && g.gimbalTransforms != null && g.gimbalTransforms.Count > 0;
                    if (!gim) { tz += Vector3d.Cross((Vector3d)p.transform.position - com, F); continue; }
                    n++;
                    double rg = 0.5 * (g.gimbalRangeXP + g.gimbalRangeXN) * g.gimbalLimiter * 0.01 * Math.PI / 180;
                    double rgy = 0.5 * (g.gimbalRangeYP + g.gimbalRangeYN) * g.gimbalLimiter * 0.01 * Math.PI / 180;
                    int ng = g.gimbalTransforms.Count;
                    Vector3d Fi = F / ng;
                    for (int i = 0; i < ng; i++)
                    {
                        Transform gt = g.gimbalTransforms[i];
                        Vector3 pos = rt.InverseTransformPoint(gt.position);
                        Vector3d r = (Vector3d)gt.position - com;
                        // the gimbal's neutral frame: the rotation already set back to initRots by KSP each tick is not
                        // ours to read, so the neutral axes are the gimbal transform's parent's x / y (z the thrust)
                        Transform nt = gt.parent != null ? gt.parent : gt;
                        Quaternion q0 = nt.rotation * g.initRots[i];
                        // the thrust along the nozzle's neutral axis: the live thrust transforms turn with the gimbal,
                        // and a tau0-hat with today's deflection in it takes the DAP's own last input back out at each
                        // refresh (the inputs then swing at 1 / (2 BDT))
                        Vector3d Fn = e.thrustTransforms[0].IsChildOf(gt) ? (Vector3d)(q0 * Quaternion.Inverse(gt.rotation) * (Vector3)Fi) : Fi;
                        tz += Vector3d.Cross(r, Fn);
                        float sg = lcom.y < pos.y ? -1f : 1f;
                        for (int j = 0; j < 3; j++)
                        {
                            Vector3 a = Vector3.zero;
                            if (j == 0 && g.enablePitch) a.x = sg;
                            if (j == 2 && g.enableYaw) a.z = sg;
                            if (j == 1 && g.enableRoll)
                            {
                                a.y = 1;
                                if (pos.x > g.minRollOffset) a.x += 1; else if (pos.x < -g.minRollOffset) a.x -= 1;
                                if (pos.z > g.minRollOffset) a.z += 1; else if (pos.z < -g.minRollOffset) a.z -= 1;
                            }
                            Vector3 w = rt.TransformDirection(a);
                            Vector3 lx = q0 * Vector3.right, ly = q0 * (g.flipYZ ? Vector3.forward : Vector3.up);
                            Vector3 l = Quaternion.Inverse(q0) * w;
                            Vector3d th = (Vector3d)lx * (l.x * rg * g.xMult) + (Vector3d)ly * (l.y * rgy * g.yMult);
                            Vector3d c = Vector3d.Cross(r, Vector3d.Cross(th, Fn));
                            if (j == 0) c0 += c; else if (j == 1) c1 += c; else c2 += c;
                        }
                    }
                }
            }
            Func<Vector3d, V3> body = x => new V3(Vector3d.Dot(x, new Vector3d(ex.x, ex.y, ex.z)), Vector3d.Dot(x, new Vector3d(ey.x, ey.y, ey.z)), Vector3d.Dot(x, new Vector3d(ez.x, ez.y, ez.z)));
            b0 = body(c0); b1 = body(c1); b2 = body(c2); t0 = body(tz);
            return n;
        }

        // one physics tick (YjFbw, before the axes are applied)
        static void AsdTick(FlightCtrlState s, double now)
        {
            Vessel v = yjVessel;
            if (v == null) { AsdOff("no vessel"); return; }
            if (SwQuery.Lost(v, "SW 01", "ASCENT")) { AsdOff("SW 01 AUTO DAP LOST"); return; }   // The axes back to the pilot at once (ops1q keeps kOS steering off)
            if (now - asdTgtT > asdPar[(int)AsdP.TGT_TMAX]) { AsdOff("no target for " + HoF(asdPar[(int)AsdP.TGT_TMAX]) + " s"); return; }
            Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
            V3 ex = AsdV3(F * Vector3.right), ey = AsdV3(F * Vector3.forward), ez = -AsdV3(F * Vector3.up);
            if (now >= asdTb)
            {
                V3 b0, b1, b2, t0;
                asdEng = AsdModel(v, ex, ey, ez, out b0, out b1, out b2, out t0);
                asdMass = v.totalMass;
                double m = asdMass;
                double[] pi = { AsdPoly(0, m), AsdPoly(1, m), AsdPoly(2, m), AsdPoly(3, m) };
                string why = AsdIWhy(AsdInertia(v, ex, ey, ez, asdI), asdI, pi);
                bool live = why == null;
                if ((live ? 1 : 2) != asdIState)
                {
                    asdIState = live ? 1 : 2;
                    string row = live ? "live," + HoF(asdI[0]) + "," + HoF(asdI[1]) + "," + HoF(asdI[2]) + "," + HoF(asdI[3]) : "fallback," + why;
                    if (asdLog != null) asdBuf.Append("#ihat,").Append(row).Append('\n');
                    Debug.Log("[KalsCoproc] ascent DAP I-hat " + row + " (mass " + HoF(m) + " t)");
                }
                if (live) asd.SetModel(b0, b1, b2, t0, asdI[0], asdI[1], asdI[2], asdI[3]);
                else asd.SetModel(b0, b1, b2, t0, pi[0], pi[1], pi[2], pi[3]);
                asdD = new V3(b0.x, b1.y, b2.z);
                asdTb = now + asdPar[(int)AsdP.BDT];
                if (asdLog != null && now >= asdBhT)
                {
                    asdBhT = now + 1;
                    asdBuf.Append("#bhat,").Append(HoF(now - asdT0));
                    foreach (V3 c in new[] { b0, b1, b2 }) asdBuf.Append(',').Append(HoF(c.x)).Append(',').Append(HoF(c.y)).Append(',').Append(HoF(c.z));
                    for (int k = 0; k < 6; k++) asdBuf.Append(',').Append(HoF(asdI[k]));
                    for (int k = 0; k < 4; k++) asdBuf.Append(',').Append(HoF(pi[k]));
                    asdBuf.Append('\n');
                }
            }
            V3 ts = AsdV3(asdTgt * Vector3.right), tf = AsdV3(asdTgt * Vector3.forward), tz = -AsdV3(asdTgt * Vector3.up);
            V3 u;
            bool ran = asd.Tick(ex, ey, ez, now, ts, tf, tz, asdWff, asdEff, asdAff, out u);
            if (!asd.HaveModel) return;                         // no engine yet: the axes left alone
            fbCmd[0] = FbClamp(u.x); fbCmd[1] = FbClamp(u.y); fbT[0] = now; fbT[1] = now;
            yjCmd = FbClamp(u.z); yjT = now;
            if (ran && asdLog != null && asd.Ticks % 5 == 1)
            {
                Vector3 moi = v.MOI;
                asdBuf.Append(HoF(now - asdT0)).Append(',').Append(asdEng).Append(',').Append(HoF(asdMass))
                    .Append(',').Append(HoF(asd.E.x * 57.2958)).Append(',').Append(HoF(asd.E.y * 57.2958)).Append(',').Append(HoF(asd.E.z * 57.2958))
                    .Append(',').Append(HoF(asd.W.x * 57.2958)).Append(',').Append(HoF(asd.W.y * 57.2958)).Append(',').Append(HoF(asd.W.z * 57.2958))
                    .Append(',').Append(HoF(u.x)).Append(',').Append(HoF(u.y)).Append(',').Append(HoF(u.z)).Append(',').Append(asd.Sat)
                    .Append(',').Append(HoF(asdD.x)).Append(',').Append(HoF(asdD.y)).Append(',').Append(HoF(asdD.z))
                    .Append(',').Append(HoF(asd.T0.x)).Append(',').Append(HoF(asd.T0.y)).Append(',').Append(HoF(asd.T0.z))
                    .Append(',').Append(HoF(asd.Ixx)).Append(',').Append(HoF(asd.Iyy)).Append(',').Append(HoF(asd.Izz)).Append(',').Append(HoF(asd.Iyz))
                    .Append(',').Append(HoF(moi.x)).Append(',').Append(HoF(moi.y)).Append(',').Append(HoF(moi.z))
                    .Append(',').Append(HoF(V3.Dot(asdWff, ex) * 57.2958)).Append(',').Append(HoF(V3.Dot(asdWff, ey) * 57.2958)).Append(',').Append(HoF(V3.Dot(asdWff, ez) * 57.2958))
                    .Append(',').Append(HoF(v.ctrlState.pitch)).Append(',').Append(HoF(v.ctrlState.roll)).Append(',').Append(HoF(v.ctrlState.yaw)).Append('\n');
                if (++asdBufN >= 25) AsdFlush();
            }
        }
    }
}
