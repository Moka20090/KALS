// The KAL/S coprocessor's A/L part: the A/L guidance (Alg.cs, a port of lib/alg.ks) and the pitch loop
// (Fcs.cs, of lib/fcs_pitch.ks), bridged by AlgKos.cs. Each suffix is one SYNCHRONOUS pass (no thread) and none throws
// into kOS (AlCoproc: an error string, or -99999 for the calls that return a number; ALERROR says why):
//     ADDONS:KALS:ALSETUP(alg_const text, taemg_const text, solq_atm_data text) -> TRUE / FALSE
//     ADDONS:KALS:ALSTEP(ags, nav, fc) -> nzt: alg_cycle + lib_land's bank slew on fc + alg_nz_total (one A/L cycle)
//     ADDONS:KALS:ALCYCLE(ags, nav) -> "": alg_cycle alone
//     ADDONS:KALS:FCTAEM(tg, st, dt, ceiling) -> cmd: fcs_alpha_cmd, MIN ceiling, fcs_alpha_slew (TAEM's pitch update)
//     ADDONS:KALS:FCWINDOW(tg, nz_meas, qbar) -> "": fcs_window_end;  FCSEED(tg, a_ent, nz0, qbar, mach) -> "": fcs_trim_seed
//     ADDONS:KALS:FCALALPHA(fc, nzt, qbar, mach, dt, amax) -> alpha: fcs_al_alpha;  FCALTRIM(fc, nzc, nzm, qbar, dt) -> ""
//     ADDONS:KALS:FCALPHAFF(nz, qbar, mach) -> fcs_alpha_ff(...)[0]
//     ADDONS:KALS:ALREADY, ALERROR, ALMS (the last call's time, ms)
namespace KalsCoproc
{
    public partial class KalsAddon
    {
        AlCoproc alc;

        partial void RegisterAl()
        {
            alc = new AlCoproc();
            AlCoproc.Register(alc, AddSuffix);
        }
    }
}
