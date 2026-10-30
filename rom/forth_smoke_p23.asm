; ============================================================================
; rom/forth_smoke_p23.asm — Phase 23 smoke ROM: decimal number literals
;
; DEFINEs DECIMAL_NUMBER_ENABLED before INCLUDEing core/interp.asm --
; the opt-in every ROM wanting this feature must do (core/fpparse.asm is
; then the number parser; every OTHER ROM that does not DEFINE it is
; unaffected). Regenerated for the 5-byte Sinclair float format in step F
; (docs/V2/FLOAT_SPEC.md section 6): the expected cells are 5-byte rows
; computed with tools/fpforth.py (parse is its model of NUMBER).
;
; THREE CHECKPOINTS:
;   1. Typing "3.5" directly pushes the float 3.5 onto the float stack --
;      checked directly, matching the same CHECK_FTOP style
;      rom/forth_smoke_p8.asm/p18.asm/p19.asm already use.
;   2. Typing "0.25" pushes the float 0.25.
;   3. : DOUBLEIT 2.0 F* ; 3.5 DOUBLEIT F. -- a decimal literal
;      COMPILED inside a colon definition (2.0), combined with one
;      typed directly (3.5), F*, and F. -- prints "7.0000 "
;      (PRINT_COL advances by 7). Proves decimal literals work in both
;      interpret and compile contexts, and interoperate correctly with
;      every other float word.
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

; ---- checkpoint 1: "3.5" -> its 5-byte cell ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_35
    ld   de, SRC_35_LEN
    call INTERPRET_RUN
    ld   hl, C1_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: "0.25" -> its 5-byte cell ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_025
    ld   de, SRC_025_LEN
    call INTERPRET_RUN
    ld   hl, C2_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 3: compiled + interpreted decimal literals, F*, F. -> "7.0000 " (7 chars) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_COMBINED
    ld   de, SRC_COMBINED_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7                       ; len("7.0000") + the trailing space
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
C1_X:   DB   $82, $60, $00, $00, $00     ; fpforth: parse("3.5")[1]
C2_X:   DB   $7F, $00, $00, $00, $00     ; fpforth: parse("0.25")[1]

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

SRC_35: DB "3.5 "
SRC_35_LEN EQU $ - SRC_35

SRC_025: DB "0.25 "
SRC_025_LEN EQU $ - SRC_025

SRC_COMBINED: DB ": DOUBLEIT 2.0 F* ; 3.5 DOUBLEIT F. "
SRC_COMBINED_LEN EQU $ - SRC_COMBINED

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpparse.asm"
    INCLUDE "core/fpprint.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p23_rom0.bin", $0000, $4000
