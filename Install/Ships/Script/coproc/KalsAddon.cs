// THE KAL/S COPROCESSOR (+ the TAEM guidance, TGSETUP / TGCYCLE below), a kOS addon (the pattern of kOS-Addons/StockCamera's Addon.cs): ADDONS:KALS runs ops1q's
// fast-time abort flights (Fts.cs, a port of lib_ascent_ard.ks EXACT to ~1e-11 on the VM's jobs) on a worker thread, off
// KSP's main thread. kOS hands it the same job lexicon ard_new takes and polls the handle:
//     ADDONS:KALS:SETUP(LEXICON(... every ASC_* the sim reads, the air / Cd tables, the TAL site's I-loads ...)).
//     LOCAL h IS ADDONS:KALS:FTS(job).       // returns at once
//     ... later passes: IF h:DONE { PRINT h:MARGIN + " " + h:WHY. }
// THREADING: everything kOS hands over is copied into plain C# values on the main thread (in FTS()); the worker touches
// no Unity or kOS object; the handle's suffixes read plain fields (volatile 'done' written last). PROTOTYPE: compiled
// only, never run in game.
using System;
using System.Collections.Generic;
using System.Threading;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace KalsCoproc
{
    [kOS.AddOns.kOSAddon("KALS")]
    [KOSNomenclature("KALSAddon")]
    public partial class KalsAddon : kOS.Suffixed.Addon
    {
        FtsConsts consts;

        public KalsAddon(kOS.SharedObjects shared) : base(shared)
        {
            AddSuffix("SETUP", new OneArgsSuffix<Lexicon>(Setup));
            AddSuffix("FTS", new OneArgsSuffix<FtsHandle, Lexicon>(StartFts));
            AddSuffix("READY", new Suffix<BooleanValue>(() => consts != null));
            // the TAEM guidance (Taemg.cs, TaemgKos.cs), one synchronous pass per call
            AddSuffix("TGSETUP", new TwoArgsSuffix<BooleanValue, StringValue, StringValue>(TgSetup));
            AddSuffix("TGREADY", new Suffix<BooleanValue>(() => tgm != null));
            AddSuffix("TGERROR", new Suffix<StringValue>(() => tgErr));
            AddSuffix("TGCYCLE", new ThreeArgsSuffix<StringValue, Lexicon, Lexicon, ListValue>(TgCycle));
            // each further offload is its own file (KalsAddon.<part>.cs, a partial of this class) that adds its suffixes
            // here; a part left out of the build simply has no suffixes (C# drops an unimplemented partial method's call)
            RegisterAl(); RegisterFam(); RegisterDap(); RegisterPeg(); RegisterPad(); RegisterAoa(); RegisterDeorbit(); RegisterAd(); RegisterEntry(); RegisterGrtls(); RegisterTd(); RegisterRtls(); RegisterTj(); RegisterEd(); RegisterTraj(); RegisterCape(); RegisterFar(); RegisterYawJet(); RegisterEngInd(); RegisterHoHold(); RegisterGrd(); RegisterHoHud(); RegisterAscCss(); RegisterAscDap(); RegisterRcsDv(); RegisterRw(); RegisterAscHud(); RegisterLever(); RegisterArm(); RegisterKeys(); RegisterPr(); RegisterOd(); RegisterO2Dap(); RegisterRails(); RegisterOmsLine(); RegisterO2Burn(); RegisterSail(); RegisterSnd(); RegisterFail(); RegisterRcsMap(); RegisterPaint(); RegisterWApply(); RegisterHudWin(); RegisterAscMeco(); RegisterProx();
        }

        partial void RegisterAl();     // A/L guidance + the pitch loop (Alg.cs, Fcs.cs)
        partial void RegisterFam();    // the entry family build, a worker thread per member (Fam.cs)
        partial void RegisterDap();    // the DAP's per-tick math (Dap.cs)
        partial void RegisterPeg();    // ascent PEG, one synchronous pass per call (Peg.cs)
        partial void RegisterPad();    // the whole pad search (E TAL, stage 1, the ARD search, BLUE/GREEN) on worker threads (Pad*.cs)
        partial void RegisterAoa();    // the AOA solve (lib_aoa.ks aoaSolve) on worker threads (Aoa.cs)
        partial void RegisterDeorbit(); // the deorbit planner's burn solve + plan-check entries (DpCore.cs, DpSolve.cs)
        partial void RegisterAd();     // the ascent pages' math (lib_ascdisp; Ad.cs, AdKos.cs)
        partial void RegisterEntry();  // one entry guidance cycle, eprGuidStep / talGuidStep (EntryGuid.cs, EntryGuidKos.cs)
        partial void RegisterGrtls();  // the GRTLS Nz model + alpha slew, grtlsFcs / grtlsNz (GrtlsGuid.cs, GrtlsGuidKos.cs)
        partial void RegisterTd();     // the TAEM / GRTLS pages' math (lib_taemdisp; Td.cs, TdKos.cs)
        partial void RegisterRtls();   // the RTLS PPD prediction + the 2EO mode 2 hold (RtlsPpd.cs, CntM2.cs, RtlsKos.cs)
        partial void RegisterTj();     // the ENTRY TRAJ page's math (traj_display; Tj.cs, TjKos.cs)
        partial void RegisterEd();     // the entry page's math (lib_entdisp, HORIZ SIT in entry; Ed.cs, EdKos.cs)
        partial void RegisterCape();   // where the Katniss Cape is, CAPEGEO (KalsAddon.Cape.cs)
        partial void RegisterYawJet(); // the DAP's yaw jets under FAR, YAWJET / YAWJETAXES (KalsAddon.YawJet.cs)
        partial void RegisterEngInd(); // engines on their own throttle, ENGIND (KalsAddon.EngInd.cs)
        partial void RegisterGrd();    // the GRTLS / ECAL / entry DAP's tick, lib_grdap grdTick (Grd.cs, GrdKos.cs)
        partial void RegisterHoHud();  // the HUD kept live through the hand-off's gap, HOHUD (KalsAddon.HoHud.cs)
        partial void RegisterAscCss();  // the ascent CSS Law A tick, ASCCSSTICK (AscCss.cs, AscCssKos.cs)
        partial void RegisterAscDap();  // the ascent DAP from liftoff to MECO flown in C#, ASCDAP (KalsAddon.AscDap.cs, AscDap.cs)
        partial void RegisterAscHud();  // the OPS 1 HUD's inputs each tick, ascHudRec (AscHud.cs: ASCHUD)
        partial void RegisterRw();     // the vessel's reaction wheels off / on, RWHEELS (KalsAddon.Rw.cs)
        partial void RegisterLever();  // the AFBW throttle lever patched and live, LEVERLIVE (AfbwThrottle.cs)
        partial void RegisterArm();    // the Canadarm parts' autostrut, ASTRUT (KalsAddon.Arm.cs)
        partial void RegisterKeys();   // ops2q's keyboard: the STAGING / TYPE locks and the keys read, KEYLOCK / KEYS (KalsAddon.Keys.cs, KalsKeys.cs)
        partial void RegisterPr();     // Principia by reflection on its adapter, PRPROBE / PRREADY (KalsAddon.Pr.cs, Pr.cs, PrProbe.cs)
        partial void RegisterOd();     // ops2q's page draw and orbit view, O2SETUP / O2DRAW / O2VSETUP / O2VIEW (KalsAddon.Od.cs, Od.cs)
        partial void RegisterO2Dap();  // ops2q's DAP every physics tick, O2DAPSET / O2DAPCYC / O2DAPALIVE (KalsAddon.O2Dap.cs, O2Dap.cs)
        partial void RegisterRails();  // the exact rate set before a rails warp, its probe: RAILSARM / RAILSWATCH / RAILSINFO / RAILSMEMBERS (KalsAddon.Rails.cs, RailsCore.cs)
        partial void RegisterO2Burn();  // the burn tick of ops2q in C#, O2BURNARM / O2BURNSTEP ... (KalsAddon.O2Burn.cs, O2Burn.cs, O2BurnKos.cs)
        partial void RegisterOmsLine(); // the OMS thrust line, gimbal and c.g. trim included, OMSLINE (KalsAddon.OmsLine.cs, OmsLineCore.cs)
        partial void RegisterRcsDv();  // the RCS jets' summed velocity change, RCSDV (RcsDv.cs)
        partial void RegisterHoHold(); // the OPS 1 -> OPS 6 hand-off's gap flown in C#, HOHOLD (KalsAddon.HoHold.cs)
        partial void RegisterFar();    // FAR's forces on the vessel over a grid, FARSWEEP / FARINFO (KalsAddon.Far.cs)
        partial void RegisterTraj();   // the ENTRY TRAJ backgrounds drawn on a worker thread (gen_traj_bg; TrajBg.cs, TjPng.cs, TrajBgJob.cs, TrajBgKos.cs)
        partial void RegisterSail();   // the test harness: the command file's kOS side, SAILON / SAILCMD / SAILDONE / SAILSTAT (KalsAddon.Sail.cs, Sail.cs)
        partial void RegisterSnd();    // SOUND: SNDPLAY / SNDSTOP / SNDVOL, a sound file from GameData/KALS_CW/Sounds (KalsAddon.Snd.cs)
        partial void RegisterRcsMap(); // RCSPOD / RCSJETS, the RCS pods' jet counts and the jet map (KalsAddon.RcsMap.cs, RcsJets.cs, RcsMap.cs)
        partial void RegisterFail();   // THE FAILURE LIST: FAILSET / FAILFIX / FAILLIST / SIMSTATE / SIMLATCH / SIMPOINT, kept in the vessel (Fail.cs, FailVessel.cs, KalsAddon.Fail.cs)
        partial void RegisterPaint();  // The pages' slot labels drawn by C# in kOS's window, PAINTREG / PAINTMODE / PAINTSTATE / PAINTWORST / PAINTERR (Paint.cs, KalsAddon.Paint.cs)
        partial void RegisterWApply(); // The pages' widget writes from C#, TDHIDE / HDAPPLY / WAPPLYN + WApply.ShowHook (WApply.cs, KalsAddon.WApply.cs)
        partial void RegisterAscMeco(); // The ascent's AG4 manual MECO press + the backup 3 g limiter, ASCMECO / ASCMECOTAKE / ASCMECOSTATE (AscMeco.cs, KalsAddon.AscMeco.cs)
        partial void RegisterProx();   // PROX OPS: STKP, the target station-keeping (StationKeep.cs, KalsAddon.Prox.cs)
        partial void RegisterHudWin(); // The HUD window drawn by C#, HWREG / HWMODE / HWDRAW / HWSYNC / HWSHOW / HWSTATE (HudWin.cs, KalsAddon.HudWin.cs)

        // ---- the TAEM guidance. TGSETUP(the text of lib/taemg_const.ks, of lib/solq_atm_data.ks) -> TRUE when the
        // constants are read (FALSE: TGERROR says why). TGCYCLE(tg, st, globals) -> "" when the pass ran (tg updated in
        // place), else the error (tg untouched: kOS flies the pass). None of them throws into kOS.
        Taemg tgm;
        string tgErr = "";

        BooleanValue TgSetup(StringValue constText, StringValue atmText)
        {
            try
            {
                var c = KsConst.Parse(constText.ToString());
                foreach (var kv in KsConst.Parse(atmText.ToString())) c[kv.Key] = kv.Value;
                tgm = new Taemg(c);
                tgErr = "";
                return BooleanValue.True;
            }
            catch (Exception ex) { tgm = null; tgErr = ex.GetType().Name + ": " + ex.Message; return BooleanValue.False; }
        }

        StringValue TgCycle(Lexicon tg, Lexicon st, ListValue gl)
        {
            try
            {
                if (tgm == null) return new StringValue("TGSETUP first (" + tgErr + ")");
                TaemgKos.Cycle(tgm, tg, st, gl);
                return new StringValue("");
            }
            catch (Exception ex) { tgErr = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + tgErr); }
        }

        public override BooleanValue Available() { return BooleanValue.True; }

        static double D(Lexicon l, string k) { return Convert.ToDouble(((ScalarValue)l[new StringValue(k)]).GetDoubleValue()); }
        static double[] DL(Lexicon l, string k)
        {
            var li = (ListValue)l[new StringValue(k)];
            var a = new double[li.Count];
            for (int i = 0; i < li.Count; i++) a[i] = ((ScalarValue)li[i]).GetDoubleValue();
            return a;
        }
        static Vec3 VV(Structure s) { var v = ((kOS.Suffixed.Vector)s).ToVector3D(); return new Vec3(v.x, v.y, v.z); }

        // SETUP: the constants and tables, once a flight (the kOS globals stay the single source of truth)
        void Setup(Lexicon l)
        {
            try { Setup1(l); }
            catch (Exception) { consts = null; }     // READY stays FALSE; FTS then hands back "error" handles
        }

        void Setup1(Lexicon l)
        {
            var c = new FtsConsts();
            foreach (var f in typeof(FtsConsts).GetFields())
            {
                var key = new StringValue("ASC_" + f.Name);
                if (f.FieldType == typeof(double) && l.ContainsKey(key)) f.SetValue(c, D(l, "ASC_" + f.Name));
            }
            c.LNRHO = DL(l, "ASC_ARD_LNRHO"); c.AS = DL(l, "ASC_ARD_AS"); c.CDM = DL(l, "ASC_ARD_CDM");
            Peg.DTMAX = D(l, "ASC_DTMAX"); Peg.DTMIN = D(l, "ASC_DTMIN"); Peg.NSEG = D(l, "ASC_NSEG"); Peg.AL = D(l, "ASC_AL");
            Peg.ETB = D(l, "ASC_ETB"); Peg.KMISS = D(l, "ASC_KMISS"); Peg.RHOMAG = D(l, "ASC_RHOMAG");
            Peg.PHIDOT_MAX = D(l, "ASC_PHIDOT_MAX"); Peg.EPSTGO = D(l, "ASC_EPSTGO"); Peg.DTRD = D(l, "ASC_DTRD");
            consts = c;
        }

        // a TAL site lexicon (asc_tal_lex: ef, w, A, VMIN, VMAX, CRMAX, RDMAG, GAMD) -> a plain TalSite
        static TalSite Site(Lexicon tl)
        {
            return new TalSite { Ef = VV(tl[new StringValue("ef")]), W = D(tl, "w"), A = DL(tl, "A"), VMIN = D(tl, "VMIN"),
                VMAX = D(tl, "VMAX"), CRMAX = D(tl, "CRMAX"), RDMAG = D(tl, "RDMAG"), GAMD = D(tl, "GAMD") };
        }

        // FTS: ard_new's lexicon -> a handle; the flight runs on the thread pool
        // never throws into kOS: any failure comes back as a finished handle with WHY "error" (kOS then flies it itself)
        FtsHandle StartFts(Lexicon a)
        {
            var h = new FtsHandle();
            try { return StartFts1(a, h); }
            catch (Exception ex) { h.Fail(ex.Message); return h; }
        }

        FtsHandle StartFts1(Lexicon a, FtsHandle h)
        {
            if (consts == null) throw new InvalidOperationException("ADDONS:KALS:SETUP first");
            string md = a[new StringValue("md")].ToString();
            TalSite tl = md == "TAL" ? Site((Lexicon)a[new StringValue("tl")]) : null;
            var st = (ListValue)a[new StringValue("steer")];
            var o = (ListValue)a[new StringValue("o")];
            double[] dump = o.Count == 2 ? new double[] { ((ScalarValue)o[0]).GetDoubleValue(), ((ScalarValue)o[1]).GetDoubleValue() } : null;
            var m = (Lexicon)a[new StringValue("m")];
            var job = new FtsJob(consts, md, tl, (int)D(a, "e"), D(a, "K"), D(a, "t"), VV(a[new StringValue("r")]),
                VV(a[new StringValue("v")]), D(a, "et"), D(a, "mc"), D(a, "res"), VV(a[new StringValue("iy")]), VV(st[0]),
                VV(st[1]), ((ScalarValue)st[2]).GetDoubleValue(), dump, D(m, "f1"), D(m, "vex"));
            job.ts = D(a, "ts");
            if (a.ContainsKey(new StringValue("dt"))) job.hstep = D(a, "dt");
            if (a.ContainsKey(new StringValue("hf"))) job.hfloor = D(a, "hf");
            ThreadPool.QueueUserWorkItem(_ => h.Run(job));
            return h;
        }
    }

    [KOSNomenclature("KALSFtsJob")]
    public class FtsHandle : Structure
    {
        volatile bool done;
        double margin, t, et, om; string why = ""; Vec3 r, v; int n; string err = "";

        public FtsHandle()
        {
            AddSuffix("DONE", new Suffix<BooleanValue>(() => done));
            AddSuffix("MARGIN", new Suffix<ScalarValue>(() => margin));
            AddSuffix("WHY", new Suffix<StringValue>(() => why));
            AddSuffix("ERROR", new Suffix<StringValue>(() => err));
            AddSuffix("UNITS", new Suffix<ScalarValue>(() => n));
            AddSuffix("T", new Suffix<ScalarValue>(() => t));
            AddSuffix("ET", new Suffix<ScalarValue>(() => et));
            AddSuffix("OM", new Suffix<ScalarValue>(() => om));
            AddSuffix("R", new Suffix<kOS.Suffixed.Vector>(() => new kOS.Suffixed.Vector(r.X, r.Y, r.Z)));
            AddSuffix("V", new Suffix<kOS.Suffixed.Vector>(() => new kOS.Suffixed.Vector(v.X, v.Y, v.Z)));
        }

        public void Run(FtsJob j)
        {
            try
            {
                while (!j.Unit()) { }
                margin = j.Margin(); why = j.why; n = j.n; t = j.t; et = j.et; om = j.om; r = j.r; v = j.v;
            }
            catch (Exception ex) { err = ex.Message; why = "error"; }
            done = true;
        }

        public void Fail(string msg) { err = msg; why = "error"; margin = -1; done = true; }

        public override string ToString() { return done ? "KALSFtsJob(" + why + ", " + margin + ")" : "KALSFtsJob(running)"; }
    }
}
