; ============================================================================
; rom/forth_smoke_p25.asm — Phase 25 smoke ROM: ABS, SGN, MOD, SQRT,
; RND, RANDOMIZE
;
; FIVE CHECKPOINTS:
;   1. -5 ABS .          -> prints "5 " (PRINT_COL advances by 2)
;   2. -5 SGN . 0 SGN . 5 SGN .   -> prints "-1 0 1 " (PRINT_COL
;      advances by 7: "-1 " is 3 chars, "0 " is 2, "1 " is 2)
;   3. 17 5 MOD . -17 5 MOD .     -> prints "2 -2 " (PRINT_COL advances
;      by 5) -- remainder takes the DIVIDEND's sign, per
;      kernel/math/math.asm's own MATH_MOD16 header
;   4. 16 SQRT . 15 SQRT .        -> prints "4 3 " (PRINT_COL advances
;      by 4) -- truncating integer square root
;   5. 12345 RANDOMIZE, then ten calls to "100 RND ." -- RANDOMIZE with
;      a fixed nonzero seed makes the whole LFSR sequence deterministic
;      (see kernel/math/math.asm's own MATH_RND_SEED header), so the
;      exact ten results are known in advance (independently simulated
;      in Python from MATH_RND16's own documented algorithm: 72, 70,
;      35, 67, 33, 0, 84, 92, 96, 32) and therefore so is the exact
;      printed width (PRINT_COL advances by 29: nine 2-digit results
;      plus one 1-digit result, "0", each with a trailing space).
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

; ---- checkpoint 1: ABS ----
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

; ---- checkpoint 2: SGN ----
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
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 3: MOD ----
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

; ---- checkpoint 4: SQRT ----
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
    cp   4
    jp   nz, FAIL_TEST

; ---- checkpoint 5: RND stays in [0,100) across 10 calls, plus
; RANDOMIZE doesn't crash ----
    ld   a, 5
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
    cp   29
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

SRC_CP1: DB "-5 ABS . "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "-5 SGN . 0 SGN . 5 SGN . "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "17 5 MOD . -17 5 MOD . "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "16 SQRT . 15 SQRT . "
SRC_CP4_LEN EQU $ - SRC_CP4

SRC_CP5: DB "12345 RANDOMIZE 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . 100 RND . "
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
    INCLUDE "core/mathfn.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p25_rom0.bin", $0000, $4000
