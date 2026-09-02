; ============================================================================
; rom/forth_smoke_p27.asm — Phase 27 smoke ROM: S", TYPE, STRING,
; PLACE, COUNT, LEN, VAL
;
; FIVE CHECKPOINTS:
;   1. : GREET S" HI THERE" TYPE ; GREET   -> prints "HI THERE" (8
;      chars, PRINT_COL advances by 8) -- S" pushes (addr len) for a
;      literal, TYPE prints it.
;   2. 10 STRING BUF  BUF LEN .   -> prints "0 " (PRINT_COL advances by
;      2) -- a freshly-created STRING buffer starts empty (count byte
;      0), and LEN reads that directly.
;   3. S" HELLO" BUF PLACE  BUF LEN .   -> prints "5 " (PRINT_COL
;      advances by 2) -- PLACE copies a 5-character literal into BUF
;      and sets its count byte to 5, which LEN then reads back
;      correctly.
;   4. BUF COUNT TYPE   -> prints "HELLO" (5 chars, PRINT_COL advances
;      by 5) -- COUNT bridges BUF's own counted-string representation
;      to the (addr len) pair TYPE expects, and the text PLACE copied
;      in checkpoint 3 reads back correctly.
;   5. S" 1234" VAL . S" -17" VAL . S" " VAL .   -> prints "1234 -17 0 "
;      (PRINT_COL advances by 11) -- VAL parses a positive integer, a
;      negative one, and safely returns 0 for an empty string with no
;      error signal.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
; failing checkpoint's number (1, 2, 3, 5, or 6 -- deliberately never
; 4, which is reserved for PASS_TEST's own green; see checkpoint 4's
; own note below for a real instance of that exact collision).
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

    ld   hl, DICT_LATEST_INIT_STRING
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: S" + TYPE ----
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

; ---- checkpoint 2: STRING creates an empty buffer ----
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
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 3: PLACE + LEN ----
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
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 4: COUNT + TYPE ----
    ; NOTE: uses border color 5, not 4 -- CHECKPOINT_NUM's own value
    ; here is a FAIL-path color, and 4 is reserved for PASS_TEST's own
    ; green; a checkpoint literally numbered 4 would make its own
    ; failure color indistinguishable from genuine success. A real
    ; instance of exactly this collision was caught (not just reasoned
    ; about) during this phase's own Fuse verification -- see
    ; docs/PROJECT_PLAN.md's Phase 27 section.
    ld   a, 5
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
    cp   5
    jp   nz, FAIL_TEST

; ---- checkpoint 5: VAL ----
    ld   a, 6                    ; also not 4 -- see checkpoint 4's own
                                  ; note above
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP5
    ld   de, SRC_CP5_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   11
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
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

SRC_CP1: DB ": GREET S", '"', " HI THERE", '"', " TYPE ; GREET "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "10 STRING BUF BUF LEN . "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "S", '"', " HELLO", '"', " BUF PLACE BUF LEN . "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "BUF COUNT TYPE "
SRC_CP4_LEN EQU $ - SRC_CP4

SRC_CP5: DB "S", '"', " 1234", '"', " VAL . S", '"', " -17", '"', " VAL . S", '"', " ", '"', " VAL . "
SRC_CP5_LEN EQU $ - SRC_CP5

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/string.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p27_rom0.bin", $0000, $4000
