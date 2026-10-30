; ============================================================================
; rom/forth_smoke_p35.asm — Phase 35 smoke ROM: FROUND
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md section 8.1: FROUND is the nearest integral value, ties
; away from 0). The expected integers are tools/fpforth.py's
; ftos(fround(x)), each in a comment next to its input cell.
;
; SIX CHECKPOINTS:
;   1. FROUND(1.41418) then F>S = 1 -- the fraction (.41) is below .5.
;   2. FROUND(0.5) then F>S = 1 -- a positive tie rounds away from zero.
;   3. FROUND(-0.5) then F>S = -1 -- a negative tie rounds away from
;      zero too (the 3-byte format's round-half-up gave 0).
;   4. FROUND(2.5) then F>S = 3 -- same rule at a larger magnitude.
;   5. FROUND(-2.5) then F>S = -3 (the 3-byte format gave -2).
;   6. FROUND(-4.0) then F>S = -4 -- a whole number passes through
;      unchanged.
;
; Border goes GREEN (4) if all six pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_FROUND
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: FROUND(1.41418) then F>S = 1 -- the fraction (.41) is below .5 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, C1_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, 1                   ; fpforth: ftos(fround(enc(23170/16384))) = 1
    call CHECK_ITOP

; ---- checkpoint 2: FROUND(0.5) then F>S = 1 -- a tie rounds away from zero ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, C2_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, 1                   ; fpforth: ftos(fround(enc(0.5))) = 1
    call CHECK_ITOP

; ---- checkpoint 3: FROUND(-0.5) then F>S = -1 -- a negative tie also rounds away from zero (the 3-byte format gave 0) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, C3_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, -1                   ; fpforth: ftos(fround(enc(-0.5))) = 65535
    call CHECK_ITOP

; ---- checkpoint 4: FROUND(2.5) then F>S = 3 -- same rule at a larger magnitude ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, C4_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, 3                   ; fpforth: ftos(fround(enc(2.5))) = 3
    call CHECK_ITOP

; ---- checkpoint 5: FROUND(-2.5) then F>S = -3 (the 3-byte format gave -2) ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, C5_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, -3                   ; fpforth: ftos(fround(enc(-2.5))) = 65533
    call CHECK_ITOP

; ---- checkpoint 6: FROUND(-4.0) then F>S = -4 -- a whole number ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, C6_A
    call FPUSH_HL
    call W_FROUND
    call W_FTOS
    ld   de, -4                   ; fpforth: ftos(fround(enc(-4.0))) = 65532
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p34.asm's own CHECK_ITOP.
; ============================================================================
CHECK_ITOP:
    rst RST_DPOP
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    cp   d
    jp   nz, FAIL_TEST
    ret

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; the comment is the fpforth expression (enc = fpmodel.encode)
C1_A:   DB   $81, $35, $04, $00, $00     ; enc(23170/16384)
C2_A:   DB   $80, $00, $00, $00, $00     ; enc(0.5)
C3_A:   DB   $80, $80, $00, $00, $00     ; enc(-0.5)
C4_A:   DB   $82, $20, $00, $00, $00     ; enc(2.5)
C5_A:   DB   $82, $A0, $00, $00, $00     ; enc(-2.5)
C6_A:   DB   $83, $80, $00, $00, $00     ; enc(-4.0)
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
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpconv.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p35_rom0.bin", $0000, $4000
