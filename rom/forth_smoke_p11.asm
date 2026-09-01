; ============================================================================
; rom/forth_smoke_p11.asm — Phase 11 smoke ROM: comparisons (=, <, >)
;
; No kernel/ dependency at all -- core/compare.asm is pure Z80 logic,
; like core/float.asm's F+/F- before it. Runs a series of two-number
; comparisons through INTERPRET_RUN and checks the resulting flag
; directly off the data stack (IX-relative), the same verification
; style rom/forth_smoke_p4.asm used for its own 0=.
;
; THREE CHECKPOINTS, each covering several cases so the checkpoint
; count stays small (this project's usual granularity) without losing
; coverage of the hand-verified edge cases from core/compare.asm's own
; header:
;   1. =  : 5=3 false, 3=3 true
;   2. <  : 5<3 false, 3<5 true, -1<1 true, 1<-1 false,
;           -32768<-1 true (same-sign extreme), -1<-32768 false
;   3. >  : 5>3 true, 3>5 false
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

    ld   hl, DICT_LATEST_INIT_COMPARE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: = ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_EQ1
    ld   de, SRC_EQ1_LEN
    call INTERPRET_RUN
    call EXPECT_FALSE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_EQ2
    ld   de, SRC_EQ2_LEN
    call INTERPRET_RUN
    call EXPECT_TRUE

; ---- checkpoint 2: < ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT1
    ld   de, SRC_LT1_LEN
    call INTERPRET_RUN
    call EXPECT_FALSE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT2
    ld   de, SRC_LT2_LEN
    call INTERPRET_RUN
    call EXPECT_TRUE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT3
    ld   de, SRC_LT3_LEN
    call INTERPRET_RUN
    call EXPECT_TRUE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT4
    ld   de, SRC_LT4_LEN
    call INTERPRET_RUN
    call EXPECT_FALSE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT5
    ld   de, SRC_LT5_LEN
    call INTERPRET_RUN
    call EXPECT_TRUE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_LT6
    ld   de, SRC_LT6_LEN
    call INTERPRET_RUN
    call EXPECT_FALSE

; ---- checkpoint 3: > ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_GT1
    ld   de, SRC_GT1_LEN
    call INTERPRET_RUN
    call EXPECT_TRUE
    ld   ix, DSTACK_TOP
    ld   hl, SRC_GT2
    ld   de, SRC_GT2_LEN
    call INTERPRET_RUN
    call EXPECT_FALSE

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
EXPECT_TRUE:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    inc  a                 ; h must be $FF -> inc makes it 0
    jr   nz, FAIL_TEST
    ld   a, l
    inc  a                 ; l must be $FF -> inc makes it 0
    jr   nz, FAIL_TEST
    ret

EXPECT_FALSE:
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

CHECKPOINT_NUM EQU $87D8

SRC_EQ1: DB "5 3 = "
SRC_EQ1_LEN EQU $ - SRC_EQ1
SRC_EQ2: DB "3 3 = "
SRC_EQ2_LEN EQU $ - SRC_EQ2

SRC_LT1: DB "5 3 < "
SRC_LT1_LEN EQU $ - SRC_LT1
SRC_LT2: DB "3 5 < "
SRC_LT2_LEN EQU $ - SRC_LT2
SRC_LT3: DB "-1 1 < "
SRC_LT3_LEN EQU $ - SRC_LT3
SRC_LT4: DB "1 -1 < "
SRC_LT4_LEN EQU $ - SRC_LT4
SRC_LT5: DB "-32768 -1 < "
SRC_LT5_LEN EQU $ - SRC_LT5
SRC_LT6: DB "-1 -32768 < "
SRC_LT6_LEN EQU $ - SRC_LT6

SRC_GT1: DB "5 3 > "
SRC_GT1_LEN EQU $ - SRC_GT1
SRC_GT2: DB "3 5 > "
SRC_GT2_LEN EQU $ - SRC_GT2

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/compare.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p11_rom0.bin", $0000, $4000
