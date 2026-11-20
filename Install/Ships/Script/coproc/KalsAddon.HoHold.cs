// The OPS 1 -> OPS 6 hand-off's gap (kOS loading ops6q: no kOS code
// runs) flown by C# in the fly-by-wire handler (KalsAddon.YawJet.cs YjFbw, every physics tick): lib_ascent_css's Law A
// (ascCssTickA, stage 2) on the hand-off attitude, the CSS axes from the stick, each axis's hold caught once the stick is
// back in the detent (ascCssCapOk's rule). Deviations from ascCssTickA: the holds are inertial (stage 2's horizon frame
// turns ~0.06 deg/s, nothing in a gap of seconds), no guidance rate fed forward (the hand-off target is fixed), no
// keyboard mode (the stick's readback is used as it comes).
//     ADDONS:KALS:HOHOLD(LIST(fly, tgt Direction, cssP, cssR, LIST(i0, i1, i2), LIST(the parameters, HoP's order),
//         kOS's error vector (ascCssErr), kOS's ANGULARVEL x 57.2958, log)) -> "" or "error ...". fly FALSE = the SHADOW:
//         computed and logged only (kOS's steering lock flies the gap; no stick is read, so a CSS axis
//         catches its hold at once).
//     ADDONS:KALS:HOHOLDOFF -> TRUE: the hold released (lib_grdap grdStart; FBW3, FBWOFF and YAWJETAXES(FALSE) release it
//         too; so does HoP.TMAX s), its log closed.
// Frames as kOS's (ildump kOS.dll): FACING = ReferenceTransform.rotation * Euler(-90, 0, 0), its FORE / TOP / STAR =
// rotation * forward / up / right; ANGULARVEL = FACING * (w.x, -w.z, w.y) of Vessel.angularVelocity.
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
        // the parameters, in the order kOS passes them (lib_ascent_css's ASC_CSS_* but TMAX, the hold's time limit)
        enum HoP { QMAX, YMAX, RMAX, T, KA, WAUTO, AMIN, AUTH_K, WARP_KT, TI, IMAX, RHC, DB, EXP, CAP_W, CAP_T, AUTH_N, TMAX, N }

        static bool hoOn, hoFly, hoCssP, hoCssR, hoHpOn, hoHrOn;
        static readonly double[] hoPar = new double[(int)HoP.N];
        static readonly double[] hoI = new double[3], hoAuth = new double[3];
        static Quaternion hoTgt, hoHp, hoHr;
        static double hoT, hoT0, hoHpT = -1, hoHrT = -1;
        static int hoN;
        static string hoWhy = "", hoLog;
        static readonly StringBuilder hoBuf = new StringBuilder();
        static int hoBufN;
        static Vector3d hoErrK, hoWK;

        partial void RegisterHoHold()
        {
            AddSuffix("HOHOLD", new OneArgsSuffix<StringValue, ListValue>(l => new StringValue(HoArm(shared.Vessel, l))));
            AddSuffix("HOHOLDOFF", new Suffix<BooleanValue>(() => { HoOff("HOHOLDOFF"); return new BooleanValue(true); }));
        }

        static double HoD(Structure s) { return ((ScalarValue)s).GetDoubleValue(); }

        static string HoArm(Vessel v, ListValue l)
        {
            try
            {
                if (v == null) return "error no vessel";
                if (hoOn) HoOff("re-armed");
                try { O2dOff("HAND-OFF HOLD ON"); } catch (Exception) { }   // As AsdArm
                try { PxOff("hand-off hold on"); } catch (Exception) { }
                var pl = (ListValue)l[5];
                if (pl.Count < (int)HoP.N) return "error " + pl.Count + " parameters, want " + (int)HoP.N;
                for (int k = 0; k < (int)HoP.N; k++) hoPar[k] = HoD(pl[k]);
                hoFly = ((BooleanValue)l[0]).Value;
                hoTgt = ((kOS.Suffixed.Direction)l[1]).Rotation;
                hoCssP = ((BooleanValue)l[2]).Value;
                hoCssR = ((BooleanValue)l[3]).Value;
                var il = (ListValue)l[4];
                for (int k = 0; k < 3; k++) { hoI[k] = Math.Max(-hoPar[(int)HoP.IMAX], Math.Min(hoPar[(int)HoP.IMAX], HoD(il[k]))); hoAuth[k] = 0; }
                hoErrK = ((kOS.Suffixed.Vector)l[6]).ToVector3D();
                hoWK = ((kOS.Suffixed.Vector)l[7]).ToVector3D();
                bool log = ((BooleanValue)l[8]).Value;
                hoHpOn = false; hoHrOn = false; hoHpT = -1; hoHrT = -1;
                hoN = 0; hoT = Planetarium.GetUniversalTime(); hoT0 = hoT; hoWhy = "";
                hoBuf.Length = 0; hoBufN = 0; hoLog = null;
                if (log)
                {
                    string dir = Path.Combine(KSPUtil.ApplicationRootPath, "Ships/Script/logs");
                    Directory.CreateDirectory(dir);
                    hoLog = Path.Combine(dir, "hohold_" + Math.Round(hoT).ToString("F0", CultureInfo.InvariantCulture) + ".csv");
                    File.WriteAllText(hoLog, "t,fly,css_p,css_r,hp_on,hr_on,e_p,e_r,e_y,q,p,r,qc,pc,rc,u_p,u_r,u_y,act_p,act_r,act_y,"
                        + "stk_p,stk_r,stk_y,auth_p,auth_r,auth_y,i_p,i_r,i_y\n");
                }
                // the handler on (YjSet's way); no axis is commanded until the first tick, and none at all in the shadow
                if (yjVessel != null && yjVessel != v) yjVessel.OnFlyByWire -= YjFbw;
                v.OnFlyByWire -= YjFbw;
                v.OnFlyByWire += YjFbw;
                yjVessel = v;
                hoOn = true;
                Debug.Log("[KalsCoproc] hand-off hold " + (hoFly ? "FLYING" : "SHADOW") + ": CSS pitch " + hoCssP + ", roll/yaw " + hoCssR);
                return "";
            }
            catch (Exception ex) { hoOn = false; return "error " + ex.GetType().Name + ": " + ex.Message; }
        }

        static void HoOff(string why)
        {
            if (!hoOn) return;
            hoOn = false;
            hoWhy = why;
            HoFlush();
            Debug.Log("[KalsCoproc] hand-off hold off (" + why + ") after " + hoN + " ticks, " + (hoT - hoT0).ToString("F2") + " s");
        }

        static void HoFlush()
        {
            if (hoLog == null || hoBuf.Length == 0) return;
            try { File.AppendAllText(hoLog, hoBuf.ToString()); } catch (Exception) { }
            hoBuf.Length = 0; hoBufN = 0;
        }

        // ascCssErr: the rotation from the frame to d (rad: the sine along the axis; the VCRS / ANGULARVEL sense)
        static Vector3d HoErr(Vector3d fv, Vector3d tv, Vector3d sv, Quaternion d)
        {
            Vector3d df = d * Vector3.forward, dt = d * Vector3.up, ds = d * Vector3.right;
            return (Vector3d.Cross(fv, df) + Vector3d.Cross(tv, dt) + Vector3d.Cross(sv, ds)) * 0.5;
        }

        static double HoShape(double g, double mx)   // ascCssShape
        {
            double x = Math.Abs(g) * hoPar[(int)HoP.RHC] - hoPar[(int)HoP.DB];
            if (x <= 0) return 0;
            double s = mx * Math.Pow(Math.Min(1, x / (hoPar[(int)HoP.RHC] - hoPar[(int)HoP.DB])), hoPar[(int)HoP.EXP]);
            return g < 0 ? -s : s;
        }

        static double HoPI(int i, double er, double kc, double dt)   // ascCssPI
        {
            double uu = er * kc + hoI[i];
            if (!(Math.Abs(uu) >= 1 && uu * er > 0))
                hoI[i] = Math.Max(-hoPar[(int)HoP.IMAX], Math.Min(hoPar[(int)HoP.IMAX], hoI[i] + er * kc * dt / hoPar[(int)HoP.TI]));
            return Math.Max(-1, Math.Min(1, er * kc + hoI[i]));
        }

        static string HoF(double x) { return x.ToString("0.####", CultureInfo.InvariantCulture); }

        // one physics tick (YjFbw, before the axes are applied): ascCssTickA
        static void HoTick(FlightCtrlState s, double now)
        {
            Vessel v = yjVessel;
            if (v == null) { HoOff("no vessel"); return; }
            if (now - hoT0 > hoPar[(int)HoP.TMAX]) { HoOff("timeout " + HoF(hoPar[(int)HoP.TMAX]) + " s"); return; }
            double dt = Math.Max(now - hoT, 0.001);
            hoT = now;
            hoN++;
            Quaternion F = v.ReferenceTransform.rotation * Quaternion.Euler(-90, 0, 0);
            Vector3d fv = F * Vector3.forward, tv = F * Vector3.up, sv = F * Vector3.right, kp = -sv;   // kp: the nose-up axis
            Vector3 wl = v.angularVelocity;
            Vector3d w = (Vector3d)(F * new Vector3(wl.x, -wl.z, wl.y)) * 57.2958;    // kOS's ANGULARVEL, deg/s
            if (hoN == 1 || hoN % Math.Max(1, (int)hoPar[(int)HoP.AUTH_N]) == 0)
            {
                ListValue a = FbAuth(v);
                for (int k = 0; k < 3; k++) hoAuth[k] = HoD(a[k]);
            }
            // the stick: last tick's readback (FbPitchRoll / YjFbw), only while this hold commands the axes
            double gp = hoFly ? fbPilot[0] : 0, gr = hoFly ? fbPilot[1] : 0, gy = hoFly ? yjPilot : 0;
            double sq = 0, sr = 0, sy = 0;
            if (hoCssP)
            {
                sq = HoShape(gp, hoPar[(int)HoP.QMAX]);
                if (sq != 0) { hoHpOn = false; hoHpT = -1; }
                else if (!hoHpOn)
                {
                    if (hoHpT < 0) hoHpT = now;
                    if (Math.Abs(Vector3d.Dot(w, sv)) < hoPar[(int)HoP.CAP_W] || now - hoHpT > hoPar[(int)HoP.CAP_T]) { hoHpOn = true; hoHp = F; }
                }
            }
            if (hoCssR)
            {
                sr = HoShape(gr, hoPar[(int)HoP.RMAX]);
                sy = HoShape(gy, hoPar[(int)HoP.YMAX]);
                if (sr != 0 || sy != 0) { hoHrOn = false; hoHrT = -1; }
                else if (!hoHrOn)
                {
                    if (hoHrT < 0) hoHrT = now;
                    if (Math.Max(Math.Abs(Vector3d.Dot(w, fv)), Math.Abs(Vector3d.Dot(w, tv))) < hoPar[(int)HoP.CAP_W]
                        || now - hoHrT > hoPar[(int)HoP.CAP_T]) { hoHrOn = true; hoHr = F; }
                }
            }
            Vector3d eA = HoErr(fv, tv, sv, hoTgt), eP = eA, eR = eA;
            if (hoCssP && hoHpOn) eP = HoErr(fv, tv, sv, hoHp);
            if (hoCssR && hoHrOn) eR = HoErr(fv, tv, sv, hoHr);
            double kcw = Math.Min(1, hoPar[(int)HoP.WARP_KT] * hoPar[(int)HoP.T] / dt);
            Vector3d om = (kp * Vector3d.Dot(eP, kp) + fv * Vector3d.Dot(eR, fv) + tv * Vector3d.Dot(eR, tv)) * (57.2958 * hoPar[(int)HoP.KA] * kcw);
            if (om.magnitude > hoPar[(int)HoP.WAUTO]) om = om * (hoPar[(int)HoP.WAUTO] / om.magnitude);
            double qc = Vector3d.Dot(om, kp), pc = Vector3d.Dot(om, fv), rc = Vector3d.Dot(om, tv);   // pc + = LEFT
            if (hoCssP && sq != 0) qc = sq;
            if (hoCssP && sq == 0 && !hoHpOn) qc = 0;                       // damped before the catch
            if (hoCssR && sr == 0 && sy == 0 && !hoHrOn) { pc = 0; rc = 0; }
            if (hoCssR && (sr != 0 || sy != 0)) { pc = -sr; rc = sy; }
            double wq = Vector3d.Dot(w, kp), wp = Vector3d.Dot(w, fv), wr = Vector3d.Dot(w, tv);
            double T = hoPar[(int)HoP.T], K = hoPar[(int)HoP.AUTH_K], AM = hoPar[(int)HoP.AMIN];
            double cP = HoPI(0, (qc - wq) / (T * Math.Max(hoAuth[0] * K, AM)), kcw, dt);
            double cR = HoPI(1, -(pc - wp) / (T * Math.Max(hoAuth[1] * K, AM)), kcw, dt);   // ctrl + = RIGHT
            double cY = HoPI(2, (rc - wr) / (T * Math.Max(hoAuth[2] * K, AM)), kcw, dt);
            if (hoFly)
            {
                fbCmd[0] = FbClamp(cP); fbCmd[1] = FbClamp(cR); fbT[0] = now; fbT[1] = now;
                yjCmd = FbClamp(cY); yjT = now;
            }
            if (hoLog != null && hoN % 2 == 1)
            {
                if (hoN == 1)
                    hoBuf.Append("#arm,kOS err ").Append(HoF(hoErrK.x)).Append(' ').Append(HoF(hoErrK.y)).Append(' ').Append(HoF(hoErrK.z))
                        .Append(" C# ").Append(HoF(eA.x)).Append(' ').Append(HoF(eA.y)).Append(' ').Append(HoF(eA.z))
                        .Append(",kOS w ").Append(HoF(hoWK.x)).Append(' ').Append(HoF(hoWK.y)).Append(' ').Append(HoF(hoWK.z))
                        .Append(" C# ").Append(HoF(w.x)).Append(' ').Append(HoF(w.y)).Append(' ').Append(HoF(w.z)).Append('\n');
                hoBuf.Append(HoF(now)).Append(',').Append(hoFly ? 1 : 0).Append(',').Append(hoCssP ? 1 : 0).Append(',').Append(hoCssR ? 1 : 0)
                    .Append(',').Append(hoHpOn ? 1 : 0).Append(',').Append(hoHrOn ? 1 : 0)
                    .Append(',').Append(HoF(Vector3d.Dot(eP, kp) * 57.2958)).Append(',').Append(HoF(Vector3d.Dot(eR, fv) * 57.2958))
                    .Append(',').Append(HoF(Vector3d.Dot(eR, tv) * 57.2958))
                    .Append(',').Append(HoF(wq)).Append(',').Append(HoF(wp)).Append(',').Append(HoF(wr))
                    .Append(',').Append(HoF(qc)).Append(',').Append(HoF(pc)).Append(',').Append(HoF(rc))
                    .Append(',').Append(HoF(cP)).Append(',').Append(HoF(cR)).Append(',').Append(HoF(cY))
                    .Append(',').Append(HoF(s.pitch)).Append(',').Append(HoF(s.roll)).Append(',').Append(HoF(s.yaw))
                    .Append(',').Append(HoF(gp)).Append(',').Append(HoF(gr)).Append(',').Append(HoF(gy))
                    .Append(',').Append(HoF(hoAuth[0])).Append(',').Append(HoF(hoAuth[1])).Append(',').Append(HoF(hoAuth[2]))
                    .Append(',').Append(HoF(hoI[0])).Append(',').Append(HoF(hoI[1])).Append(',').Append(HoF(hoI[2])).Append('\n');
                if (++hoBufN >= 25) HoFlush();
            }
        }
    }
}
