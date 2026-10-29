; ============================================================================
; rom/forth_smoke_p22.asm — Phase 22 smoke ROM: F. (print a float)
;
; Same testing approach as rom/forth_smoke_p8.asm/p18.asm/p19.asm: this
; ROM seeds the float stack directly via FPUSH_HL before interpreting a
; source string containing just "F. ", then checks PRINT_COL advanced by
; the exact expected character count (F. prints 4 decimals and a
; trailing space; the cold start here sets F_PLACES to 4 as the boot ROM
; does). Regenerated for the 5-byte Sinclair float format in step F
; (docs/V2/FLOAT_SPEC.md): the cells are 5-byte rows, the texts are
; tools/fpforth.py's fdot.
;
; THREE CHECKPOINTS:
;   1. 6.0 -> prints "6.0000 " (7 chars)
;   2. 0.25 -> prints "0.2500 " (7 chars)
;   3. -2.0 -> prints "-2.0000 " (8 chars), sign handling
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

    ld   hl, DICT_LATEST_INIT_FLOATPRINT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    ld   a, 4
    ld   (F_PLACES), a

    call GFX_CLS

; ---- checkpoint 1: 6.0 F. -> "6.0000 " (7 chars) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, C1_A
    call FPUSH_HL
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7                       ; len("6.0000") + the trailing space
    jp   nz, FAIL_TEST

; ---- checkpoint 2: 0.25 F. -> "0.2500 " (7 chars) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, C2_A
    call FPUSH_HL
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7                       ; len("0.2500") + the trailing space
    jp   nz, FAIL_TEST

; ---- checkpoint 3: -2.0 F. -> "-2.0000 " (8 chars) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, C3_A
    call FPUSH_HL
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   8                       ; len("-2.0000") + the trailing space
    jp   nz, FAIL_TEST

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

SRC_FDOT: DB "F. "
SRC_FDOT_LEN EQU $ - SRC_FDOT

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; the comment is the fpforth expression and the text its fdot (4 places)
C1_A:   DB   $83, $40, $00, $00, $00     ; enc(6.0)  ; fpforth: fdot -> '6.0000'
C2_A:   DB   $7F, $00, $00, $00, $00     ; enc(0.25)  ; fpforth: fdot -> '0.2500'
C3_A:   DB   $82, $80, $00, $00, $00     ; enc(-2.0)  ; fpforth: fdot -> '-2.0000'

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

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p22_rom0.bin", $0000, $4000
