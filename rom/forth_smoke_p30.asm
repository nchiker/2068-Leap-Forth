; ============================================================================
; rom/forth_smoke_p30.asm — Phase 30 smoke ROM: PI, SIN, COS
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md section 8.2): every expected row and text is computed
; with tools/fpforth.py (fsin, fcos, PI, HALF_PI, fdot; each row's
; comment is the expression). The cold start sets F_PLACES to 4 as the
; boot ROM does.
;
; SIX CHECKPOINTS:
;   1. PI ( -- f ) pushes the constant PI.
;   2. SIN(0.0) = 0.0 exactly -- the ordinary case; all 5 bytes are
;      compared (the canonical zero is exponent byte 0).
;   3. COS(0.0) = 1.0 exactly -- COS(x) reduces x - k pi and adds
;      HALF_PI, so this puts a genuine EXACT-ZERO operand through the
;      argument reduction and the add.
;   4. SIN(HALF_PI exactly, pushed directly -- NOT a typed decimal
;      literal, which would round independently and land slightly off
;      the true boundary) = 1.0 exactly.
;   5. SIN(1.0) printed via F. -> "0.8415 " (7 characters; the old
;      3-byte format printed "0.8408 ").
;   6. COS(2.0) printed via F. -> "-0.4161 " (8 characters, exercising
;      negative-sign printing too; the old format printed "-0.4156 ").
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

    ld   hl, DICT_LATEST_INIT_FLOATTRIG
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    ld   a, 4
    ld   (F_PLACES), a

    call GFX_CLS

; ---- checkpoint 1: PI ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call W_PI
    ld   hl, C1_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: SIN(0.0) = 0.0 exactly (the canonical zero: exponent byte 0, all 5 bytes compared) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, C2_A
    call FPUSH_HL
    call W_SIN
    ld   hl, C2_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 3: COS(0.0) = 1.0 exactly -- an exact-zero operand through the argument reduction and the add of HALF_PI ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, C3_A
    call FPUSH_HL
    call W_COS
    ld   hl, C3_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 4 (border color 6, not 4 -- see this file's own header): SIN(HALF_PI exactly) = 1.0 exactly ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, C4_A
    call FPUSH_HL
    call W_SIN
    ld   hl, C4_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 5: SIN(1.0) printed via F. -> "0.8415 " (7 chars) ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, C5_A
    call FPUSH_HL
    call W_SIN
    call W_FDOT
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7                       ; len("0.8415") + the trailing space
    jp   nz, FAIL_TEST

; ---- checkpoint 6: COS(2.0) printed via F. -> "-0.4161 " (8 chars). Printed on
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
    ld   hl, C6_A
    call FPUSH_HL
    call W_COS
    call W_FDOT
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   8                       ; len("-0.4161") + the trailing space
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

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; the comment is the fpforth expression (enc = fpmodel.encode; ZERO, HALF_PI, PI are fpforth's)
C1_X:   DB   $82, $49, $0F, $DA, $A2     ; fpforth: PI
C2_A:   DB   $00, $00, $00, $00, $00     ; ZERO
C2_X:   DB   $00, $00, $00, $00, $00     ; fpforth: fsin(ZERO)
C3_A:   DB   $00, $00, $00, $00, $00     ; ZERO
C3_X:   DB   $81, $00, $00, $00, $00     ; fpforth: fcos(ZERO)
C4_A:   DB   $81, $49, $0F, $DA, $A2     ; HALF_PI
C4_X:   DB   $81, $00, $00, $00, $00     ; fpforth: fsin(HALF_PI)
C5_A:   DB   $81, $00, $00, $00, $00     ; enc(1.0); fpforth: fdot(fsin(enc(1.0))) = '0.8415'
C6_A:   DB   $82, $00, $00, $00, $00     ; enc(2.0); fpforth: fdot(fcos(enc(2.0))) = '-0.4161'

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
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/fpconv.asm"
DICT_CHAIN_POINT DEFL H_FROUND
    INCLUDE "core/fpmath.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p30_rom0.bin", $0000, $4000
