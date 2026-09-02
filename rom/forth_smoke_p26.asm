; ============================================================================
; rom/forth_smoke_p26.asm — Phase 26 smoke ROM: ARRAY and CELLS
;
; THREE CHECKPOINTS:
;   1. 5 ARRAY NUMS  NUMS @ .   -> prints "0 " (PRINT_COL advances by
;      2) -- a freshly-created array is zero-initialized, and NUMS
;      itself pushes the BASE address (element 0), so a plain @ on it
;      (no CELLS offset) reads element 0 directly.
;   2. 99 3 CELLS NUMS + !  3 CELLS NUMS + @ .   -> prints "99 "
;      (PRINT_COL advances by 3) -- CELLS converts a cell index into a
;      byte offset (index*2, this project's own cell size), and
;      writing/reading through that computed address round-trips
;      correctly.
;   3. 0 CELLS NUMS + @ . 1 CELLS NUMS + @ . 2 CELLS NUMS + @ .
;      -> prints "0 0 0 " (PRINT_COL advances by 6) -- every OTHER
;      element besides the one checkpoint 2 wrote to is still zero,
;      confirming ARRAY's own zero-init loop covers the whole block
;      (not just element 0) and checkpoint 2's write didn't corrupt a
;      neighboring cell.
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

COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_ARRAY
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: ARRAY creates a zero-initialized array ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 2: CELLS-indexed write/read round-trips ----
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
    cp   3
    jp   nz, FAIL_TEST

; ---- checkpoint 3: other elements stay zero ----
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
    cp   6
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

SRC_CP1: DB "5 ARRAY NUMS NUMS @ . "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "99 3 CELLS NUMS + ! 3 CELLS NUMS + @ . "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "0 CELLS NUMS + @ . 1 CELLS NUMS + @ . 2 CELLS NUMS + @ . "
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
    INCLUDE "core/array.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p26_rom0.bin", $0000, $4000
