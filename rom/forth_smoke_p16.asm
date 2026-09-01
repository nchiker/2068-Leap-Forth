; ============================================================================
; rom/forth_smoke_p16.asm — Phase 16 smoke ROM: DO/LOOP and I
;
; THREE CHECKPOINTS:
;   1. : FIVETIMES 5 0 DO I . LOOP ; FIVETIMES
;      -> prints "0 1 2 3 4 " (PRINT_COL advances by 10) -- basic
;      correctness: exactly 5 iterations, indices 0-4, limit itself
;      excluded
;   2. : NEST 3 0 DO 2 0 DO I . LOOP LOOP ; NEST
;      -> prints "0 1 0 1 0 1 " (PRINT_COL advances by 12) -- the
;      CRITICAL nested-loop stack-discipline check: an outer loop's own
;      limit/index must survive underneath an inner loop's own, fully
;      restored once the inner loop finishes and removes its own
;   3. VARIABLE SUM  0 SUM !  : DOSUM 5 0 DO I SUM @ + SUM ! LOOP ;
;      DOSUM  SUM @ .
;      -> prints "10 " (PRINT_COL advances by 3) -- combined-phase
;      integration: DO/LOOP + VARIABLE (Phase 12) + arithmetic +
;      printing (Phase 10), summing 0+1+2+3+4. DO/LOOP themselves MUST
;      be used inside a colon definition (like IF/ELSE/THEN/BEGIN/
;      WHILE/REPEAT) -- VARIABLE, like `:` itself, stays at the top
;      level instead, matching its own Phase 12 scope.
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

    call GFX_CLS

; ---- checkpoint 1: basic DO/LOOP/I ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   10
    jp   nz, FAIL_TEST

; ---- checkpoint 2: nested DO/LOOP stack discipline ----
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
    cp   12
    jp   nz, FAIL_TEST

; ---- checkpoint 3: DO/LOOP + VARIABLE + arithmetic + printing ----
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
    cp   3
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

SRC_CP1: DB ": FIVETIMES 5 0 DO I . LOOP ; FIVETIMES "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB ": NEST 3 0 DO 2 0 DO I . LOOP LOOP ; NEST "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "VARIABLE SUM 0 SUM ! : DOSUM 5 0 DO I SUM @ + SUM ! LOOP ; DOSUM SUM @ . "
SRC_CP3_LEN EQU $ - SRC_CP3

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/variable.asm"
DICT_CHAIN_POINT DEFL H_CONSTANT
    INCLUDE "core/doloop.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p16_rom0.bin", $0000, $4000
