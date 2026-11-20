// arm.ks -- the Canadarm controller's program. RUN arm alone prints 'use ops2q' and ends: the arm runs on
// ops2q's PDRS page (lib_o2arm.ks sets ARM_HOST TRUE and RUNPATHs this file; then the body, arm_body.ks, runs here).
@LAZYGLOBAL OFF.
IF NOT (DEFINED ARM_HOST) { GLOBAL ARM_HOST IS FALSE. }
IF ARM_HOST {
    RUNPATH("0:/arm_body.ks").
} ELSE {
    PRINT "arm: USE OPS2. The arm runs on ops2's PDRS page (RUN ops2q); arm alone does nothing.".
}
