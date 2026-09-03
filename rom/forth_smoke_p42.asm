; ============================================================================
; rom/forth_smoke_p42.asm — Phase 42 smoke ROM: RAD, DEG
;
; TWO CHECKPOINTS, exact-mantissa cases hand-derived by simulating the
; REAL F_UMUL32/F_NORMALIZE32 algorithm in Python first (this project's
; own established discipline — see core/floattrig.asm's own header for
; the same treatment of PI/SIN/COS), not guessed from the ideal
; mathematical values:
;   1. RAD(90.0) = 90.0 * (18301,-20) -- Python-simulated
;      F_UMUL32/F_NORMALIZE32 gives EXACTLY (25735,-14) = 1.57073974...,
;      close to true PI/2 (1.5707963...) within this project's own
;      already-established SIN/COS precision budget, not a coincidence.
;   2. DEG(HALF_PI) = (25736,-14) * (29335,-9) -- same simulation gives
;      EXACTLY (23039,-8) = 89.99609375, close to true 90.0 within the
;      same budget -- a real round trip (radians back to degrees), not
;      just one direction checked in isolation.
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    DS   $0008 - $, $FF
RST_08: ret
    DS   $0010 - $, $FF
RST_10: ret
    DS   $0018 - $, $FF
RST_18: ret
    DS   $0020 - $, $FF
RST_20: ret
    DS   $0028 - $, $FF
RST_28: ret
    DS   $0030 - $, $FF
RST_30: ret
    DS   $0038 - $, $FF
RST_38:
    ei
    ret
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_RADDEG
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: RAD(90.0) = (25735,-14) exactly ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 23040
    ld   a, -8
    call FPUSH
    call W_RAD
    ld   hl, 25735
    ld   a, -14
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: DEG(HALF_PI) = (23039,-8) exactly ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 25736
    ld   a, -14
    call FPUSH
    call W_DEG
    ld   hl, 23039
    ld   a, -8
    call CHECK_FTOP
    call FPOP

    jp   PASS_TEST

; ============================================================================
; CHECK_FTOP ( HL = expected mantissa, A = expected exponent -- )
; Checks the float on top of the float stack WITHOUT popping it.
; Identical to rom/forth_smoke_p30.asm's own CHECK_FTOP.
; ============================================================================
CHECK_FTOP:
    push af
    ld   a, (iy+0)
    cp   l
    jp   nz, FAIL_TEST
    ld   a, (iy+1)
    cp   h
    jp   nz, FAIL_TEST
    pop  af
    ld   l, a
    ld   a, (iy+2)
    cp   l
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: both checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floattrig.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p42_rom0.bin", $0000, $4000
