// ============================================================
// flightlogger.ks -- flight parameter logger for kOS
// ============================================================
// Loaded by the mission script with RUNONCEPATH. kOS cannot evaluate a string such as "SHIP:ALTITUDE", so
// the script passes a LEXICON that maps each name to a zero-argument delegate returning the current
// value. A config file (default 0:/logconfig.txt, one key per line) chooses which of those keys are
// logged, so one large lexicon can serve several flight phases with different config files.
// Usage:
//   LOCAL params IS LEXICON(
//     "altitude",  { RETURN SHIP:ALTITUDE. },
//     "speed",     { RETURN SHIP:VELOCITY:SURFACE:MAG. },
//     "throttle",  { RETURN THROTTLE. }
//   ).
//   RUNONCEPATH("0:/lib/flightlogger.ks").
//   initLogFlight(0.5, params).                              // default config file
//   initLogFlight(0.5, params, "0:/logconfig_ops3q.txt").    // custom config file
//   UNTIL done { logFlight(). WAIT 0. }
// Output: 0:/logs/flight_<UT>.csv (UT in whole seconds). The first row is a header, UT,key1,key2,...;
// each following row is <UT>,<val1>,<val2>,... (older logs head the UT column MET).

// Module state.
RUNONCEPATH("0:/lib/lib_logsw.ks").   // SOCK_LOG: the logs on or off (0:/logging.txt)
RUNONCEPATH("0:/lib/lib_kmsg.ks").               // the terminal stays blank in flight (kmSay: the log + the window's MSG line)
GLOBAL _log_delegates   IS LEXICON(). // name -> delegate
GLOBAL _log_activeKeys  IS LIST().    // ordered keys to log (from the config file)
GLOBAL _log_dT          IS 0.  // minimum interval between rows, s
GLOBAL _log_lastTime    IS -1.  // TIME:SECONDS of the last row; -1 = none yet
GLOBAL _log_filePath    IS "".  // path of the CSV being written
GLOBAL _log_ready       IS FALSE.  // TRUE once initLogFlight has succeeded

// initLogFlight(dT, delegateLexicon [, cfgPath]): reads the config file and starts the CSV log.
//   dT: minimum logging interval, s. delegateLexicon: name -> zero-argument delegate returning the value.
//   cfgPath: config file listing the keys to log, one per line (default "0:/logconfig.txt").
FUNCTION initLogFlight {
  PARAMETER dT.
  PARAMETER delegateLexicon.
  PARAMETER cfgPath IS "0:/logconfig.txt".
  IF NOT SOCK_LOG { RETURN. }   // the logs off (lib_logsw): no file, and logFlight returns at once

  // Read the config file: one key per line, in log order. Blank lines are ignored; a key with no
  // delegate is skipped with a warning.
  IF NOT EXISTS(cfgPath) {
    kmSay("ERROR [flightlogger]: config not found at " + cfgPath, "C").
    RETURN.
  }

  LOCAL contents IS OPEN(cfgPath):READALL.
  SET _log_activeKeys TO LIST().

  FOR line IN contents {
    LOCAL key IS line:TRIM.
    IF key:LENGTH > 0 {
      IF delegateLexicon:HASKEY(key) {
        _log_activeKeys:ADD(key).
      } ELSE {
        kmSay("WARNING [flightlogger]: no delegate '" + key + "', skipped.", "C").
      }
    }
  }

  IF _log_activeKeys:LENGTH = 0 {
    kmSay("ERROR [flightlogger]: no valid keys in logconfig.", "C").
    RETURN.
  }

  SET _log_delegates TO delegateLexicon.

  // Output file in 0:/logs (created if missing); its name carries the start time in whole seconds.
  IF NOT EXISTS("0:/logs") { CREATEDIR("0:/logs"). }
  LOCAL t IS ROUND(TIME:SECONDS, 0).
  LOCAL base IS "0:/logs/flight_" + t.
  SET _log_filePath TO base + ".csv".
  // Runs repeated from one quicksave start at the same UT and would share a name: if the file
  // exists, append _2, _3, ... instead of overwriting it.
  LOCAL n IS 1.
  UNTIL NOT EXISTS(_log_filePath) {
    SET n TO n + 1.
    SET _log_filePath TO base + "_" + n + ".csv".
  }

  // Header row: the first column holds UT (TIME:SECONDS), then one column per active key, in config-file order.
  // Older logs head this column MET over the same UT values; the python readers take either.
  LOCAL header IS "UT".
  FOR key IN _log_activeKeys {
    SET header TO header + "," + key.
  }
  LOG header TO _log_filePath.

  SET _log_dT       TO dT.
  SET _log_lastTime TO -1.
  SET _log_ready    TO TRUE.

}

// logFlight(): call every loop iteration. Appends one CSV row (UT, val1, val2, ...), at most one per
// dT seconds.
FUNCTION logFlight {

  IF NOT _log_ready {
    IF SOCK_LOG { kmSay("WARNING [flightlogger]: initLogFlight() first.", "C"). }
    RETURN.
  }

  LOCAL now IS TIME:SECONDS.

  IF _log_lastTime >= 0 AND (now - _log_lastTime) < _log_dT {
    RETURN.
  }

  // Build the row: time rounded to 4 decimals, scalars to 6, other values as text.
  LOCAL row IS "" + ROUND(now, 4).

  FOR key IN _log_activeKeys {
    LOCAL val IS _log_delegates[key]:CALL().
    IF val:ISTYPE("Scalar") {
      SET row TO row + "," + ROUND(val, 6).
    } ELSE {
      SET row TO row + "," + val.
    }
  }

  LOG row TO _log_filePath.
  SET _log_lastTime TO now.
}
