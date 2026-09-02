; ============================================================================
; rom/forth_smoke_p23.asm — Phase 23 smoke ROM: decimal number literals
;
; DEFINEs DECIMAL_NUMBER_ENABLED before INCLUDEing core/interp.asm --
; the opt-in every ROM wanting this feature must do (see
; core/decimal.asm's own header for why every OTHER ROM in this
; project is unaffected).
;
; THREE CHECKPOINTS, the exact two parsing cases hand-verified in
; core/decimal.asm's own header, plus a combined end-to-end test:
;   1. Typing "3.5" directly pushes (m=28672,e=-13) onto the float
;      stack -- checked directly, matching the same CHECK_FTOP style
;      rom/forth_smoke_p8.asm/p18.asm/p19.asm already use.
;   2. Typing "0.25" pushes (m=16384,e=-16) -- the SAME representation
;      already hand-picked for "0.25" in three earlier smoke ROMs, a
;      real cross-check that this parser's output matches.
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

    ld   hl, DICT_LATEST_INIT_FLOATPRINT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: "3.5" -> (28672,-13) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_35
    ld   de, SRC_35_LEN
    call INTERPRET_RUN
    ld   hl, 28672
    ld   a, -13
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: "0.25" -> (16384,-16) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_025
    ld   de, SRC_025_LEN
    call INTERPRET_RUN
    ld   hl, 16384
    ld   a, -16
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 3: compiled + interpreted decimal literals, F*, F. ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_COMBINED
    ld   de, SRC_COMBINED_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FTOP:                      ; HL = expected mantissa, A = expected
                                  ; exponent; float stack NOT popped
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
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floatprint.asm"
    INCLUDE "core/decimal.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p23_rom0.bin", $0000, $4000
