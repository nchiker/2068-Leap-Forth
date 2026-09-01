; ============================================================================
; rom/forth_smoke_p10.asm — Phase 10 smoke ROM: EMIT and . (print)
;
; Proves core/print.asm's EMIT and . both as real dictionary words and
; as correct output-position bookkeeping. Verification strategy mirrors
; Phase 5's own PLOT check: since there's no way to "read back" printed
; text as text, this checks (a) PRINT_ROW/PRINT_COL advanced by exactly
; the expected amount for each case, and (b) for EMIT specifically,
; that a real pixel was actually drawn in the target cell, via
; GFX_READ_PIXEL — not just that the position bookkeeping moved.
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only
; kernel/math and kernel/graphics are needed.
;
; SELF-TEST, five checkpoints:
;   1. EMIT one character; PRINT_COL/ROW advance by exactly one column,
;      and at least one pixel is set somewhere in that character cell.
;   2. "123 . " (positive, multi-digit): PRINT_COL advances by 4
;      (3 digits + trailing space).
;   3. "-32768 . " (negative, including the signed 16-bit edge case
;      whose magnitude doesn't fit in a positive 16-bit value —
;      see core/print.asm's own header on why this is handled
;      correctly, not by luck): PRINT_COL advances by 7 (minus sign +
;      5 digits + trailing space).
;   4. "0 . ": PRINT_COL advances by 2 ("0" + trailing space).
;   5. 33 direct EMIT calls (ROM-level, not through Forth source text —
;      this checkpoint is about EMIT's own column-wrap arithmetic, not
;      about re-proving Forth text parsing) of the same character:
;      confirms wrapping from column 31 back to column 0 on a new row
;      happens at exactly the 32nd character, landing at row 1, column
;      1 after the 33rd.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
; failing checkpoint's number (1-5).
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
RST_00:
    di
    jp   COLD_START

    DS   $0008 - $, $FF
RST_08:
    ret

    DS   $0010 - $, $FF
RST_10:
    ret

    DS   $0018 - $, $FF
RST_18:
    ret

    DS   $0020 - $, $FF
RST_20:
    ret

    DS   $0028 - $, $FF
RST_28:
    ret

    DS   $0030 - $, $FF
RST_30:
    ret

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

    ld   hl, DICT_LATEST_INIT_PRINT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: EMIT one character ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_EMIT
    ld   de, SRC_EMIT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   1
    jp   nz, FAIL_TEST
    call CHECK_ANY_PIXEL_SET      ; B=row 0, C=col 0 set by the macro below

; ---- checkpoint 2: . with a positive multi-digit number ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_DOT_POS
    ld   de, SRC_DOT_POS_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_COL)
    cp   4
    jp   nz, FAIL_TEST

; ---- checkpoint 3: . with -32768 (the signed-magnitude edge case) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_DOT_MINEG
    ld   de, SRC_DOT_MINEG_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 4: . with 0 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_DOT_ZERO
    ld   de, SRC_DOT_ZERO_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_COL)
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 5: EMIT column-wrap arithmetic (direct calls) ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   b, 33
.emitloop:
    push bc
    ld   hl, "X"
    call DPUSH_HL
    call W_EMIT
    pop  bc
    djnz .emitloop
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   1
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_ANY_PIXEL_SET:              ; checks row 0, columns 0-7 (the
                                   ; character cell EMIT just drew) for
                                   ; at least one set pixel
    ld   b, 0
.pixelloop:
    push bc
    ld   c, 0
.rowloop:
    push bc
    ld   h, 0
    ld   l, b
    call GFX_READ_PIXEL
    pop  bc
    or   a
    jr   nz, .found
    inc  c
    ld   a, c
    cp   8
    jr   c, .rowloop
    pop  bc
    inc  b
    ld   a, b
    cp   8
    jr   c, .pixelloop
    jp   FAIL_TEST                 ; no pixel found anywhere in the cell
.found:
    pop  bc
    ret

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-5) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $87D0

SRC_EMIT:        DB "65 EMIT "
SRC_EMIT_LEN     EQU $ - SRC_EMIT
SRC_DOT_POS:     DB "123 . "
SRC_DOT_POS_LEN  EQU $ - SRC_DOT_POS
SRC_DOT_MINEG:   DB "-32768 . "
SRC_DOT_MINEG_LEN EQU $ - SRC_DOT_MINEG
SRC_DOT_ZERO:    DB "0 . "
SRC_DOT_ZERO_LEN EQU $ - SRC_DOT_ZERO

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p10_rom0.bin", $0000, $4000
