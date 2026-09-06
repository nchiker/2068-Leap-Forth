; ============================================================================
; rom/forth_smoke_p54.asm — Phase 54 smoke ROM: * and / (plain integer
; multiply and divide), added to core/mathfn.asm as thin wrappers
; around kernel/math/math.asm's own already-verified MATH_MULTIPLY16
; and MATH_DIVIDE16 -- see that file's own header for why no new
; algorithm was written here.
;
; FOUR CHECKPOINTS:
;   1. 6 7 * . -6 7 * .           -> prints "42 -42 " (PRINT_COL
;      advances by 7: "42 " is 3 chars, "-42 " is 4) -- sign handling
;      for *.
;   2. 300 300 * .                -> prints "24464 " (PRINT_COL
;      advances by 6) -- 300*300 = 90000, which truncates to 16 bits
;      as 24464 (90000 - 65536), proving MATH_MULTIPLY16's documented
;      truncate-to-16-bits contract rather than a saturating or
;      wraparound-avoiding one.
;   3. 17 5 / . -17 5 / .         -> prints "3 -3 " (PRINT_COL advances
;      by 5) -- truncates toward zero (-17/5 = -3, not -4), per
;      MATH_DIVIDE16's own header.
;   4. 5 0 / .                    -> prints "0 " (PRINT_COL advances by
;      2) -- divide by zero returns 0, same no-error-signal convention
;      as MOD's own divide-by-zero case (both share MATH_UDIV16).
;
; Border goes GREEN (4) if all checkpoints pass; otherwise it shows the
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

COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_MATHFN
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: * sign handling ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 2: * truncates to 16 bits on overflow ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   6
    jp   nz, FAIL_TEST

; ---- checkpoint 3: / truncates toward zero ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   5
    jp   nz, FAIL_TEST

; ---- checkpoint 4: / by zero returns 0 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   2
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
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

SRC_CP1: DB "6 7 * . -6 7 * . "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "300 300 * . "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "17 5 / . -17 5 / . "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "5 0 / . "
SRC_CP4_LEN EQU $ - SRC_CP4

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/mathfn.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p54_rom0.bin", $0000, $4000
