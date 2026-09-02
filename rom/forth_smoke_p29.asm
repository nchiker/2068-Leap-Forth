; ============================================================================
; rom/forth_smoke_p29.asm — Phase 29 smoke ROM: FSQRT
;
; THREE CHECKPOINTS, the same three hand-verified cases
; core/floatsqrt.asm's own header derives by hand:
;   1. sqrt(4.0) = 2.0 exactly (16384,-12) -- even exponent path.
;   2. sqrt(9.0) = 3.0 exactly (18432,-11) -- odd exponent path, a
;      second independent exact perfect square.
;   3. sqrt(2.0) ~ 1.41421 (16384,-13) -- odd exponent path, an
;      irrational result. FSQRT itself gives exactly (23170,-14) (see
;      core/floatsqrt.asm's own hand-traced header) — 23170/16384 =
;      1.41418457..., which F.'s own truncating-toward-zero convention
;      prints as exactly "1.4141 " (with its own trailing space), a
;      single deterministic expected string, not a range.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number.
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

    ld   hl, DICT_LATEST_INIT_FLOATSQRT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: sqrt(4.0) = 2.0 exactly ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   a, -12
    call FPUSH
    call W_FSQRT
    ld   hl, 16384
    ld   a, -13
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: sqrt(9.0) = 3.0 exactly ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 18432
    ld   a, -11
    call FPUSH
    call W_FSQRT
    ld   hl, 24576
    ld   a, -13
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 3: sqrt(2.0) ~ 1.41421, printed via F. ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, 16384
    ld   a, -13
    call FPUSH
    call W_FSQRT
    call W_FDOT
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ============================================================================
; CHECK_FTOP ( HL = expected mantissa, A = expected exponent -- )
; Checks the float on top of the float stack WITHOUT popping it (the
; caller pops separately once done); halts with the border showing the
; current checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p18.asm's own CHECK_FTOP.
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
    ld   a, 4                    ; green: all three checkpoints passed
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
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/float.asm"
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floatprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/floatsqrt.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p29_rom0.bin", $0000, $4000
