; ============================================================================
; rom/forth_smoke_p19.asm — Phase 19 smoke ROM: F/ (float divide)
;
; Same testing approach as rom/forth_smoke_p8.asm/p18.asm: this ROM seeds
; the float stack directly via FPUSH_HL before interpreting a source
; string containing just "F/ ", then compares the top cell with the
; expected 5 bytes via CHECK_FTOP.
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md); each expected row's comment is the tools/fpforth.py
; expression that produced it (enc = fpmodel.encode).
;
; FOUR CHECKPOINTS:
;   1. 6.0 / 3.0 = 2.0.
;   2. 1.0 / 1.0 = 1.0.
;   3. 1.0 / 4.0 = 0.25 (a quotient that must be normalised up).
;   4. -6.0 / 3.0 = -2.0. Sign handling.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_FLOATDIV
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: 6.0 / 3.0 = 2.0 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, C1_A
    call FPUSH_HL
    ld   hl, C1_B
    call FPUSH_HL
    ld   hl, SRC_FSLASH
    ld   de, SRC_FSLASH_LEN
    call INTERPRET_RUN
    ld   hl, C1_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: 1.0 / 1.0 = 1.0 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, C2_A
    call FPUSH_HL
    ld   hl, C2_B
    call FPUSH_HL
    ld   hl, SRC_FSLASH
    ld   de, SRC_FSLASH_LEN
    call INTERPRET_RUN
    ld   hl, C2_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 3: 1.0 / 4.0 = 0.25 (a quotient that needs normalising up) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, C3_A
    call FPUSH_HL
    ld   hl, C3_B
    call FPUSH_HL
    ld   hl, SRC_FSLASH
    ld   de, SRC_FSLASH_LEN
    call INTERPRET_RUN
    ld   hl, C3_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 4: -6.0 / 3.0 = -2.0 (sign handling) ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, C4_A
    call FPUSH_HL
    ld   hl, C4_B
    call FPUSH_HL
    ld   hl, SRC_FSLASH
    ld   de, SRC_FSLASH_LEN
    call INTERPRET_RUN
    ld   hl, C4_X
    call CHECK_FTOP
    call FDROP_T

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

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; each comment is the fpforth expression (enc = fpmodel.encode)
C1_A:   DB   $83, $40, $00, $00, $00     ; enc(6.0)
C1_B:   DB   $82, $40, $00, $00, $00     ; enc(3.0)
C1_X:   DB   $82, $00, $00, $00, $00     ; fpforth: div(enc(6.0), enc(3.0))
C2_A:   DB   $81, $00, $00, $00, $00     ; enc(1.0)
C2_B:   DB   $81, $00, $00, $00, $00     ; enc(1.0)
C2_X:   DB   $81, $00, $00, $00, $00     ; fpforth: div(enc(1.0), enc(1.0))
C3_A:   DB   $81, $00, $00, $00, $00     ; enc(1.0)
C3_B:   DB   $83, $00, $00, $00, $00     ; enc(4.0)
C3_X:   DB   $7F, $00, $00, $00, $00     ; fpforth: div(enc(1.0), enc(4.0))
C4_A:   DB   $83, $C0, $00, $00, $00     ; enc(-6.0)
C4_B:   DB   $82, $40, $00, $00, $00     ; enc(3.0)
C4_X:   DB   $82, $80, $00, $00, $00     ; fpforth: div(enc(-6.0), enc(3.0))

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
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

SRC_FSLASH: DB "F/ "
SRC_FSLASH_LEN EQU $ - SRC_FSLASH

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/fpcore.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p19_rom0.bin", $0000, $4000
