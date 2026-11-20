@LAZYGLOBAL OFF.
// THE PAD SEARCH CACHE (the pad's searches took ~90 s before every run): the pad's three searches
// (E TAL, the ARD's pad search, the BLUE / GREEN sweep on its path) fly the vehicle as weighed on the pad: the SRBs
// (asc_srb_meas), the core over the I-load's (asc["core_dm"]) and the ET's propellant at liftoff (asc["et_lo"],
// asc_core_meas), the I-loads where unweighed; in a frame of their own (a liftoff now: the same geometry at any time),
// so the same inputs give the same result (measured over four flights: the ARD's bit for bit, E TAL within 0.08 s).
// Once all three are done on the pad their states (asc["etl"], asc["ard"], asc["bgl"]) and the globals the sweep
// sets go to ASC_PADC_FILE under a key of the inputs the code reads at run time (the pad, the SRBs, the core and the
// ET as weighed, the target box, the site's I-loads by the pad, the sites, the searches' switches); the code itself
// by a copy of each source (ASC_PADC_SRC) beside the file, compared whole: any edit is a miss and a new search (then
// the file starts over). On the next pad with the same key and the same code the states come back at once (no search,
// no hold), the pad's log lines too. ASC_PADC_MAXN keys kept (the oldest out).
// kOS's JSON writes a Vector as its text: padc_enc tags each as LIST("$V", x, y, z), padc_dec builds it back; any type
// other than Lexicon / List / Vector / Scalar / String / Boolean: no save (its name in the log). Here the file's means
// only; ops1q's asc_padc_work / asc_padc_load / asc_padc_save / padc_key use them (a library loads what it uses).
GLOBAL ASC_PADC_ON IS TRUE.
GLOBAL ASC_PADC_DIR IS "0:/logs/padc/".
GLOBAL ASC_PADC_FILE IS ASC_PADC_DIR + "pad_cache.json".
GLOBAL ASC_PADC_MAXN IS 8.
GLOBAL ASC_PADC_SRC IS LIST("ops1q.ks", "lib/lib_ascent_iload.ks", "lib/lib_ascent_s1.ks", "lib/lib_ascent_peg.ks",
  "lib/lib_ascent_s2.ks", "lib/lib_ascent_rtls.ks", "lib/lib_ascent_abr.ks", "lib/lib_ascent_cnt.ks",
  "lib/lib_ascent_ard.ks", "lib/lib_ascent_etl.ks", "lib/lib_ascent_bgl.ks", "lib/lib_ascent_padc.ks",
  "lib/lib_ascent_padcs.ks").   // + the C# pad search's kOS side
GLOBAL padc_bad IS "".

FUNCTION padc_enc {
  PARAMETER x.
  IF x:ISTYPE("Vector") { RETURN LIST("$V", x:X, x:Y, x:Z). }
  IF x:ISTYPE("Lexicon") {
    LOCAL o IS LEXICON().
    FOR k IN x:KEYS { SET o[k] TO padc_enc(x[k]). }
    RETURN o.
  }
  IF x:ISTYPE("List") {
    LOCAL o IS LIST().
    FOR y IN x { o:ADD(padc_enc(y)). }
    RETURN o.
  }
  IF x:ISTYPE("Scalar") OR x:ISTYPE("String") OR x:ISTYPE("Boolean") { RETURN x. }
  SET padc_bad TO x:TYPENAME.
  RETURN 0.
}

FUNCTION padc_dec {
  PARAMETER x.
  IF x:ISTYPE("Lexicon") {
    LOCAL o IS LEXICON().
    FOR k IN x:KEYS { SET o[k] TO padc_dec(x[k]). }
    RETURN o.
  }
  IF x:ISTYPE("List") {
    IF x:LENGTH = 4 { IF x[0]:ISTYPE("String") { IF x[0] = "$V" { RETURN V(x[1], x[2], x[3]). } } }
    LOCAL o IS LIST().
    FOR y IN x { o:ADD(padc_dec(y)). }
    RETURN o.
  }
  RETURN x.
}

FUNCTION padc_copy_of {                     // the source f's copy beside the file
  PARAMETER f.
  RETURN ASC_PADC_DIR + "src_" + f:REPLACE("/", "_").
}

FUNCTION padc_same {                        // TRUE: every source as when the file's searches ran
  FOR f IN ASC_PADC_SRC {
    IF NOT EXISTS("0:/" + f) OR NOT EXISTS(padc_copy_of(f)) { RETURN FALSE. }
    IF OPEN("0:/" + f):READALL:STRING <> OPEN(padc_copy_of(f)):READALL:STRING { RETURN FALSE. }
  }
  RETURN TRUE.
}
