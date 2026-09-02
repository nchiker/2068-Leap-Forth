; ============================================================================
; rom/forth_smoke_p30.asm — Phase 30 smoke ROM: PI, SIN, COS
;
; SIX CHECKPOINTS, each hand-derived by a bit-exact Python model of the
; real Z80 algorithm (core/floattrig.asm's own header) before ever
; assembling anything — not guessed, and not a naive floating-point
; simulation either: the model reproduces F_ALIGN's own real unsigned-
; comparison quirk, F+/F-'s own (now-fixed) overflow handling, and
; F*/F_UDIV32BY16's exact integer arithmetic bit-for-bit, sanity-checked
; against core/floatprint.asm's own three hand-verified F. examples
; before being trusted for anything new:
;   1. PI ( -- f ) pushes exactly (25736,-13).
;   2. SIN(0.0) = 0.0 exactly (0,0) — the ordinary case.
;   3. COS(0.0) = 1.0 exactly (16384,-14) — THE important one: COS(x) =
;      SIN(x+HALF_PI), so COS(0.0) computes 0.0+HALF_PI internally,
;      putting a genuine EXACT-ZERO operand through F_ALIGN. This only
;      comes out right BECAUSE of F_ALIGN's own unsigned-comparison
;      quirk (see core/floattrig.asm's own header and the
;      2068forth-float-align-signed-cmp-quirk memory note) — a
;      "corrected" F_ALIGN would silently destroy HALF_PI's own
;      mantissa here instead. If this checkpoint ever starts failing
;      after some future F_ALIGN change, that's exactly the regression
;      to suspect.
;   4. SIN(HALF_PI exactly, pushed directly as (25736,-14) — NOT a typed
;      decimal literal, which would round independently and land
;      slightly off the true boundary) = 1.0 exactly (16384,-14) — the
;      table's own upper boundary (idx=16 exactly, frac=0).
;   5. SIN(1.0) printed via F. -> "0.8408 " (7 characters).
;   6. COS(2.0) printed via F. -> "-0.4156 " (8 characters, exercising
;      negative-sign printing too).
;
; Border goes GREEN (4) if all six pass; otherwise it shows the failing
; checkpoint's number (1,2,3,5,6 — NOT 4, which is PASS_TEST's own
; green; checkpoint 4 uses border color 6 on failure, following
; rom/forth_smoke_p27.asm's own color-collision fix).
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

    ld   hl, DICT_LATEST_INIT_FLOATTRIG
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: PI ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call W_PI
    ld   hl, 25736
    ld   a, -13
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: SIN(0.0) = 0.0 exactly. Checks ONLY the mantissa
; (not the exponent) -- SIN(0.0)'s own internal arithmetic can
; legitimately leave a nonzero exponent alongside a zero mantissa
; (e.g. (0,-16) here), which this project's own convention already
; treats as an equally-valid representation of exact zero (see
; core/floatmul.asm's own F_NORMALIZE32 header: "value is exactly
; zero -- nothing more to do (any exponent is fine for 0)") -- an
; exact (mantissa, exponent) CHECK_FTOP match would be over-strict and
; was caught failing this way on the very first real Fuse run, not a
; genuine SIN bug. ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 0
    ld   a, 0
    call FPUSH
    call W_SIN
    ld   a, (iy+0)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (iy+1)
    or   a
    jp   nz, FAIL_TEST
    call FPOP

; ---- checkpoint 3: COS(0.0) = 1.0 exactly -- the F_ALIGN
; zero-quirk-dependency regression case, see this file's own header ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 0
    ld   a, 0
    call FPUSH
    call W_COS
    ld   hl, 16384
    ld   a, -14
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 4 (border color 6, not 4 -- see this file's own
; header): SIN(HALF_PI exactly) = 1.0 exactly, the table's own upper
; boundary ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, 25736
    ld   a, -14
    call FPUSH
    call W_SIN
    ld   hl, 16384
    ld   a, -14
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 5: SIN(1.0) printed via F. -> "0.8408 " ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, 16384
    ld   a, -14
    call FPUSH
    call W_SIN
    call W_FDOT
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 6: COS(2.0) printed via F. -> "-0.4156 ". Printed on
; row 1, not row 0 -- otherwise it would overwrite checkpoint 5's own
; printed text at the same screen position, the same class of cursor-
; reuse issue Phase 10's own banner-overlap bug hit (harmless for the
; automated pass/fail check, which only reads cursor position, but it
; would make a screenshot unable to show both checkpoints' real output
; at once). ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   a, 1
    ld   (PRINT_ROW), a
    xor  a
    ld   (PRINT_COL), a
    ld   hl, 16384
    ld   a, -13
    call FPUSH
    call W_COS
    call W_FDOT
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   8
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ============================================================================
; CHECK_FTOP ( HL = expected mantissa, A = expected exponent -- )
; Identical to rom/forth_smoke_p18.asm/p29.asm's own CHECK_FTOP.
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
    ld   a, 4                    ; green: all six checkpoints passed
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
DICT_CHAIN_POINT DEFL H_FSQRT
    INCLUDE "core/floattrig.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p30_rom0.bin", $0000, $4000
