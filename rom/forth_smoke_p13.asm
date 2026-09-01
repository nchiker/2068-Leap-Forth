; ============================================================================
; rom/forth_smoke_p13.asm — Phase 13 smoke ROM: ." (print a literal string)
;
; Needs kernel/graphics (core/print.asm's own W_EMIT dependency) but no
; other kernel/ module. Runs colon definitions using ." through
; INTERPRET_RUN and checks PRINT_COL/PRINT_ROW afterward -- the same
; verification style rom/forth_smoke_p10.asm used for EMIT/. itself.
;
; THREE CHECKPOINTS:
;   1. : GREET ." HI" ; GREET   -> PRINT_COL advances by 2 ("HI", no
;      trailing space, unlike `.`)
;   2. : EMPTY ." " ; EMPTY     -> PRINT_COL stays 0 (the empty-string
;      edge case: the one required space between ." and the closing "
;      IS the delimiter W_WORD consumes, leaving zero real characters)
;   3. : DESCRIBE IF ." pos" ELSE ." neg" THEN ; -- combined with
;      existing control flow, matching docs/forth_tutorial.md's own
;      section 5 example: 5 DESCRIBE prints "pos" (3), 0 DESCRIBE
;      prints "neg" (3)
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

    ld   hl, DICT_LATEST_INIT_DOTQUOTE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: GREET ----
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

; ---- checkpoint 2: EMPTY string ----
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
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 3: DESCRIBE combined with IF/ELSE/THEN ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP3A
    ld   de, SRC_CP3A_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   3
    jp   nz, FAIL_TEST
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP3B
    ld   de, SRC_CP3B_LEN
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

CHECKPOINT_NUM EQU $87E8

SRC_CP1: DB ": GREET .", '"', " HI", '"', " ; GREET "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB ": EMPTY .", '"', " ", '"', " ; EMPTY "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3A: DB ": DESCRIBE IF .", '"', " pos", '"', " ELSE .", '"', " neg", '"', " THEN ; 5 DESCRIBE "
SRC_CP3A_LEN EQU $ - SRC_CP3A

SRC_CP3B: DB "0 DESCRIBE "
SRC_CP3B_LEN EQU $ - SRC_CP3B

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
    INCLUDE "core/dotquote.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p13_rom0.bin", $0000, $4000
