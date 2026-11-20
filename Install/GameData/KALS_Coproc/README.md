# KALS_Coproc

The KAL/S coprocessor (KalsCoproc.dll): a kOS addon (`ADDONS:KALS`) that flies ops1q's fast-time abort flights (the abort-region
search's level and rank flights) on a worker thread, off KSP's main thread. Source and build script:
`Ships/Script/coproc/`. Switch: `ASC_ARD_CS` in `lib/lib_ascent_ard.ks` (FALSE = kOS flies everything, as before).
On any addon failure the switch turns itself off for the flight and kOS flies that job itself.

Since T61 (2026-10-18) it also carries the TAEM guidance (`coproc/Taemg.cs`, a port of `lib/taemg.ks`): `ADDONS:KALS:TGSETUP / TGCYCLE / TGDIFF`, one synchronous call per guidance pass. Switches in `lib/lib_land.ks`: `LD_TG_CS` (the addon flies TAEM) and `LD_TG_CS_CHECK` (kOS flies, the addon shadows and logs the worst difference). On any failure both turn off and kOS flies.

Since T62 (2026-10-18): the A/L guidance and the pitch loop (`Alg.cs`, `Fcs.cs`; `ALSTEP`, `FCTAEM`, `FCALALPHA` ...; switches `LD_AL_CS` / `LD_AL_CS_CHECK` in `lib/lib_land.ks`) and every ascent PEG pass (`PegKos.cs`; `PEGCYCLE`; `ASC_PEG_CS` / `ASC_PEG_CS_CHECK` in `lib/lib_ascent_peg.ks`). Each falls back to kOS by itself on any failure.

Since T62 pad (2026-10-18): the whole pad search (E TAL, the stage-1 predictor, the ARD search, the BLUE/GREEN sweep) as one job on worker threads (`PADSEARCH`; switch `ASC_PAD_CS` in `ops1q.ks`). `RUN sock_probe.` lists the suffixes.
- 2026-10-18 18:15 (old computer, GENERAL bccd8f2b): + FAMSTART / FAMDIFF / FAMERROR (the entry family build, T62 fam) + AOASOLVE (the AOA solve, T62 aoa); md5 b3aa0c97, 210944 bytes.
- 2026-10-18 18:21 (old computer, GENERAL bccd8f2b): + DPSOLVE / DPARC (the deorbit planner's burn solve and plan-check entries, T62 deorbit); md5 21d03f3e, 239616 bytes.
