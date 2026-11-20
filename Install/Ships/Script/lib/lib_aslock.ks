// lib_aslock.ks: the Canadarm's autostrut lock for the entry, without loading lib_arm.
// asLockArm() sets the autostrut to AS_LOCK_MODE on every arm part named in AS_LOCK_PARTS (the end effector, the elbow and
// both booms) through ADDONS:KALS:ASTRUT and returns what it did as one line of text. It is the backstop for a run that
// never drove the arm: arm.ks turns the arm's autostrut off for a drive and larAsStow puts the end effector's and the
// elbow's back on at the stow pose (lib_arm), and the craft file carries the same setting for a fresh launch. An arm left
// free at the entry interface is thrown out of the bay for a few seconds (flights: the end effector 12 m off its pose with
// the autostrut off, 0.06 m with the end effector and the elbow locked).
GLOBAL AS_LOCK_PARTS IS LIST("LEE", "elbow", "boom").   // a part whose NAME contains "C1" and one of these is locked
GLOBAL AS_LOCK_MODE IS "Heaviest".
FUNCTION asLockArm {
    IF NOT ADDONS:HASSUFFIX("KALS") { RETURN "autostrut lock: no KAL/S addon". }
    IF NOT ADDONS:KALS:AVAILABLE { RETURN "autostrut lock: the KAL/S addon is not available". }
    IF NOT ADDONS:KALS:HASSUFFIX("ASTRUT") { RETURN "autostrut lock: an older KalsCoproc.dll". }
    LOCAL s IS "autostrut lock:". LOCAL n IS 0.
    FOR pt IN SHIP:PARTS {
        LOCAL nm IS pt:NAME.
        IF nm:CONTAINS("C1") {
            LOCAL hit IS FALSE.
            FOR k IN AS_LOCK_PARTS { IF nm:CONTAINS(k) { SET hit TO TRUE. } }
            IF hit {
                LOCAL was IS ADDONS:KALS:ASTRUT(pt, "").
                IF was <> AS_LOCK_MODE {
                    SET s TO s + " " + nm + " " + was + " -> " + ADDONS:KALS:ASTRUT(pt, AS_LOCK_MODE) + ";".
                    SET n TO n + 1.
                }
            }
        }
    }
    IF n = 0 { SET s TO s + " all set already (or no arm)". }
    RETURN s.
}
