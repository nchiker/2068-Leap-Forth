; ============================================================================
; rom/forth_smoke_p34.asm — Phase 34 smoke ROM: S>F and F>S
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md section 8.1); expected cells and integers come from
; tools/fpforth.py (fri, enc = fpmodel.encode, ftos), each in a comment.
;
; FIVE CHECKPOINTS:
;   1. S>F(42) lands on the float stack as exactly the cell for 42.0 --
;      checked directly before converting back -- then F>S round-trips it
;      to exactly 42 on the integer stack.
;   2. S>F(-17) then F>S round-trips to exactly -17 -- negative
;      integers need no special-casing anywhere in either word.
;   3. F>S(0.5) = 0 -- ordinary truncation toward zero for a positive
;      fractional value.
;   4. F>S(-0.5) = 0 -- F>S truncates toward zero, so a negative
;      fractional value also gives 0 (the 3-byte format floored it to
;      -1; spec section 8.1).
;   5. F>S(-4.0) = -4 -- a WHOLE negative number is unaffected, since
;      there is no fractional remainder to truncate.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_FLOATCONV
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: S>F(42) = 42.0 exactly (the 5-byte cell), then F>S round-trips to 42 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 42
    rst RST_DPUSH
    call W_STOF
    ld   hl, C1_X
    call CHECK_FTOP
    call W_FTOS
    ld   de, 42                   ; fpforth: ftos(fri(42)) = 42
    call CHECK_ITOP

; ---- checkpoint 2: S>F(-17) then F>S round-trips to -17 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, -17
    rst RST_DPUSH
    call W_STOF
    call W_FTOS
    ld   de, -17                  ; fpforth: ftos(fri(-17)) = 65519 = -17
    call CHECK_ITOP

; ---- checkpoint 3: F>S(0.5) = 0 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, C3_A
    call FPUSH_HL
    call W_FTOS
    ld   de, 0                   ; fpforth: ftos(enc(0.5)) = 0
    call CHECK_ITOP

; ---- checkpoint 4: F>S(-0.5) = 0 -- truncation toward 0 (the 3-byte format gave -1) ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, C4_A
    call FPUSH_HL
    call W_FTOS
    ld   de, 0                   ; fpforth: ftos(enc(-0.5)) = 0
    call CHECK_ITOP

; ---- checkpoint 5: F>S(-4.0) = -4 -- a whole number ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, C5_A
    call FPUSH_HL
    call W_FTOS
    ld   de, -4                   ; fpforth: ftos(enc(-4.0)) = 65532
    call CHECK_ITOP

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

; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch.
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
C1_X:   DB   $86, $28, $00, $00, $00     ; fpforth: fri(42)
C3_A:   DB   $80, $00, $00, $00, $00     ; enc(0.5)
C4_A:   DB   $80, $80, $00, $00, $00     ; enc(-0.5)
C5_A:   DB   $83, $80, $00, $00, $00     ; enc(-4.0)

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
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

    SAVEBIN "forth_smoke_p34_rom0.bin", $0000, $4000
