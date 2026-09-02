; ============================================================================
; rom/forth_smoke_p24.asm — Phase 24 smoke ROM: LEAVE and +LOOP
;
; THREE CHECKPOINTS:
;   1. : TESTLEAVE 10 0 DO I . I 3 = IF LEAVE THEN LOOP ; TESTLEAVE
;      -> prints "0 1 2 3 " (PRINT_COL advances by 8) -- LEAVE fires
;      the moment I reaches 3, skipping the remaining six passes (I
;      would otherwise run through 9) entirely.
;   2. : EVENS 10 0 DO I . 2 +LOOP ; EVENS
;      -> prints "0 2 4 6 8 " (PRINT_COL advances by 10) -- +LOOP steps
;      by 2 instead of 1, and correctly stops once the index CROSSES
;      10 (at index 10 itself, which is never printed) rather than
;      requiring an exact match.
;   3. : NEST2 3 0 DO 5 0 DO I . I 2 = IF LEAVE THEN LOOP LOOP ; NEST2
;      -> prints "0 1 2 0 1 2 0 1 2 " (PRINT_COL advances by 18) -- the
;      CRITICAL nested check: an inner loop's own LEAVE must exit only
;      the inner loop, leaving the outer loop's own limit/index
;      undisturbed underneath it, matching (and re-verifying) plain
;      DO/LOOP's own already-proven nested stack discipline
;      (rom/forth_smoke_p16.asm's own checkpoint 2) -- if LEAVE instead
;      corrupted the outer loop's control values, this would run only
;      once ("0 1 2 ") instead of three times.
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

    ld   hl, DICT_LATEST_INIT_DOLOOP
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   (LEAVE_DEPTH), a   ; core/doloop.asm's own LEAVE bookkeeping --
                            ; must start at 0, matching STATE/etc above

    call GFX_CLS

; ---- checkpoint 1: LEAVE ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   8
    jp   nz, FAIL_TEST

; ---- checkpoint 2: +LOOP ----
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
    cp   10
    jp   nz, FAIL_TEST

; ---- checkpoint 3: nested LEAVE stack discipline ----
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
    cp   18
    jp   nz, FAIL_TEST

    jp   PASS_TEST

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

SRC_CP1: DB ": TESTLEAVE 10 0 DO I . I 3 = IF LEAVE THEN LOOP ; TESTLEAVE "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB ": EVENS 10 0 DO I . 2 +LOOP ; EVENS "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB ": NEST2 3 0 DO 5 0 DO I . I 2 = IF LEAVE THEN LOOP LOOP ; NEST2 "
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
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/doloop.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p24_rom0.bin", $0000, $4000
