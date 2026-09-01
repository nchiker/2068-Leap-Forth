; ============================================================================
; rom/forth_smoke_p14.asm — Phase 14 smoke ROM: BEGIN/WHILE/REPEAT
;
; THREE CHECKPOINTS:
;   1. : COUNTDOWN2 BEGIN DUP 0 > WHILE 1 - REPEAT ; 5 COUNTDOWN2
;      -> leaves 0 (a decrement-based loop is naturally sensitive to
;      running the wrong number of times, so landing on exactly 0
;      proves correct iteration -- same rigor as
;      docs/forth_tutorial.md's own BEGIN/UNTIL COUNTDOWN example)
;   2. 0 COUNTDOWN2 -> leaves 0 UNCHANGED: the crucial case that
;      distinguishes WHILE's pre-test loop from BEGIN/UNTIL's
;      post-test one -- the body must never run at all when the
;      condition is false from the very first check
;   3. : PRINTDOWN BEGIN DUP 0 > WHILE DUP . 1 - REPEAT DROP ;
;      3 PRINTDOWN -- combines WHILE/REPEAT with Phase 10's own `.`:
;      prints "3 2 1 " (PRINT_COL advances by 6)
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

    ld   hl, DICT_LATEST_INIT_LOOP
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: 5 COUNTDOWN2 -> 0 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    call EXPECT_TOP_ZERO

; ---- checkpoint 2: 0 COUNTDOWN2 -> 0 (loop body never runs) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    call EXPECT_TOP_ZERO

; ---- checkpoint 3: 3 PRINTDOWN -> prints "3 2 1 " ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   6
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
EXPECT_TOP_ZERO:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    or   l
    jr   nz, FAIL_TEST
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

CHECKPOINT_NUM EQU $87F0

SRC_CP1: DB ": COUNTDOWN2 BEGIN DUP 0 > WHILE 1 - REPEAT ; 5 COUNTDOWN2 "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "0 COUNTDOWN2 "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB ": PRINTDOWN BEGIN DUP 0 > WHILE DUP . 1 - REPEAT DROP ; 3 PRINTDOWN "
SRC_CP3_LEN EQU $ - SRC_CP3

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/loop.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p14_rom0.bin", $0000, $4000
