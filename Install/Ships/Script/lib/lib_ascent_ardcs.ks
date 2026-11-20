// lib_ascent_ardcs.ks -- THE IN-FLIGHT REFRESHES OF THE ABORT SEARCH IN THE KAL/S COPROCESSOR. Each refresh of the ARD's
// search in flight (asc_ard_snap's snapshot after a PEG pass: the path on the SSMEs running, every level not latched, the
// TAL sites' rank) and the BLUE / GREEN sweep on its path go to the pad search's own job, ADDONS:KALS:PADSEARCH, handed the
// ready snapshot (no E TAL, no stage 1: coproc/PadRun.cs flies the path from the snapshot's state), on worker threads;
// kOS polls DONE and writes the results into the very structures its own units leave (asc["ard"], asc["bgl"], the
// sweep's globals, the log lines), with lib_ascent_padcs's padcs_apply_ard / padcs_apply_bgl. Checked bit for bit
// against lib_ascent_ard / lib_ascent_bgl in kOS's VM (the dev tools). Vessel-free: ops1q's
// asc_live_cs_go / asc_live_cs_work use these.
@LAZYGLOBAL OFF.

// the ARD's input for a refresh in flight (padcs_in_ard's without the pad state: the snapshot a carries its state), after
// ard_srch_go(S, a, seed)
FUNCTION ardcs_in {
  PARAMETER S, a, seed.
  RETURN LEXICON("a", a, "seed", seed, "tls", S["tls"], "lv", S["lv"], "nrun", S["nrun"], "u", S["u"], "nref", S["nref"],
    "ok2", S["ok2"], "rtl", S["rtl"]).
}

// the levels latched as the job starts (their keys)
FUNCTION ardcs_lat {
  PARAMETER S.
  LOCAL l IS LIST().
  FOR x IN S["lv"] { IF x["lat"] { l:ADD(x["key"]). } }
  RETURN l.
}

// the result into S (padcs_apply_ard), except the levels the pages latched while the job ran (ard_apply_b: not in l0):
// those keep their state, as kOS's own refresh skips a level latched before its turn
FUNCTION ardcs_apply {
  PARAMETER S, cr, l0.
  LOCAL sv IS LEXICON().
  FOR x IN S["lv"] {
    IF x["lat"] AND NOT l0:CONTAINS(x["key"]) {
      SET sv[x["key"]] TO LIST(x["tb"], x["vb"], x["lat"], x["note"], x["nc"], x["bv"], x["nq"]).
    }
  }
  padcs_apply_ard(S, cr).
  FOR x IN S["lv"] {
    IF sv:HASKEY(x["key"]) {
      LOCAL kq IS sv[x["key"]].
      SET x["tb"] TO kq[0].
      SET x["vb"] TO kq[1].
      SET x["lat"] TO kq[2].
      SET x["note"] TO kq[3].
      SET x["nc"] TO kq[4].
      SET x["bv"] TO kq[5].
      SET x["nq"] TO kq[6].
    }
  }
  RETURN sv:LENGTH.
}
