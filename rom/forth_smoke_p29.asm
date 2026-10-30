; ============================================================================
; rom/forth_smoke_p29.asm — Phase 29 smoke ROM: FSQRT
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md section 8.1); every expected row's comment is the
; tools/fpforth.py expression that produced it (enc = fpmodel.encode).
;
; THREE CHECKPOINTS:
;   1. sqrt(4.0) = 2.0 exactly -- even exponent path.
;   2. sqrt(9.0) = 3.0 exactly -- odd exponent path, a second
;      independent exact perfect square.
;   3. sqrt(2.0) ~ 1.41421, an irrational result, printed with F.: the
;      5-byte FSQRT result is 1.41421356..., F. rounds half up at 4
;      places and prints exactly "1.4142 " (with its own trailing
;      space; the old 3-byte format gave "1.4141 "), a single
;      deterministic expected string, not a range. The cold start here
;      sets F_PLACES to 4 as the boot ROM does.
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
    INCLUDE "include/rst_vectors.inc"
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

    ld   a, 4
    ld   (F_PLACES), a

    call GFX_CLS

; ---- checkpoint 1: sqrt(4.0) = 2.0 exactly ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, C1_A
    call FPUSH_HL
    call W_FSQRT
    ld   hl, C1_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: sqrt(9.0) = 3.0 exactly ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, C2_A
    call FPUSH_HL
    call W_FSQRT
    ld   hl, C2_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 3: sqrt(2.0) ~ 1.41421, printed via F. -> "1.4142 " (7 chars) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, C3_A
    call FPUSH_HL
    call W_FSQRT
    call W_FDOT
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7                       ; len("1.4142") + the trailing space
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FTOP:                      ; HL -> 5 expected bytes; float stack NOT popped
    push iy
    pop  de
    ld   b, 5
.cmp:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  de
    inc  hl
    djnz .cmp
    ret

FDROP_T:                         ; drop the top float cell
    ld   bc, 5
    add  iy, bc
    ret

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; the comment is the fpforth expression (enc = fpmodel.encode)
C1_A:   DB   $83, $00, $00, $00, $00     ; enc(4.0)
C1_X:   DB   $82, $00, $00, $00, $00     ; fpforth: fsqrt(enc(4.0))
C2_A:   DB   $84, $10, $00, $00, $00     ; enc(9.0)
C2_X:   DB   $82, $40, $00, $00, $00     ; fpforth: fsqrt(enc(9.0))
C3_A:   DB   $82, $00, $00, $00, $00     ; enc(2.0); fpforth: fdot(fsqrt(enc(2.0))) = '1.4142'

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
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/fpconv.asm"    ; (fpmath.asm's FINT)
DICT_CHAIN_POINT DEFL H_FROUND
    INCLUDE "core/fpmath.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p29_rom0.bin", $0000, $4000
