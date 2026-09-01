; ============================================================================
; rom/forth_smoke_p12.asm — Phase 12 smoke ROM: VARIABLE and CONSTANT
;
; No kernel/ dependency (like core/compare.asm before it) -- pure
; dictionary/compiler logic. Runs source strings through INTERPRET_RUN
; and checks the resulting data-stack top directly (IX-relative), the
; same verification style rom/forth_smoke_p11.asm used.
;
; THREE CHECKPOINTS:
;   1. VARIABLE FOO, store 42, fetch it back -> 42
;   2. 100 CONSTANT BAR, run BAR -> 100
;   3. A second, independent VARIABLE BAZ, store 7, fetch -> 7, AND
;      FOO's own cell still reads back 42 (proves separate data cells,
;      not aliased)
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

    ld   hl, DICT_LATEST_INIT_VARIABLE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: VARIABLE, store, fetch ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_VAR1
    ld   de, SRC_VAR1_LEN
    call INTERPRET_RUN
    call EXPECT_42

; ---- checkpoint 2: CONSTANT ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_CONST1
    ld   de, SRC_CONST1_LEN
    call INTERPRET_RUN
    call EXPECT_100

; ---- checkpoint 3: a second, independent VARIABLE, plus re-checking
; the first one's cell wasn't aliased ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   hl, SRC_VAR2
    ld   de, SRC_VAR2_LEN
    call INTERPRET_RUN
    call EXPECT_7
    ld   ix, DSTACK_TOP
    ld   hl, SRC_FOO_RECHECK
    ld   de, SRC_FOO_RECHECK_LEN
    call INTERPRET_RUN
    call EXPECT_42

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
EXPECT_42:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 42
    or   a
    sbc  hl, de
    jr   nz, FAIL_TEST
    ret

EXPECT_100:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 100
    or   a
    sbc  hl, de
    jr   nz, FAIL_TEST
    ret

EXPECT_7:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 7
    or   a
    sbc  hl, de
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

CHECKPOINT_NUM EQU $87E0

SRC_VAR1: DB "VARIABLE FOO 42 FOO ! FOO @ "
SRC_VAR1_LEN EQU $ - SRC_VAR1

SRC_CONST1: DB "100 CONSTANT BAR BAR "
SRC_CONST1_LEN EQU $ - SRC_CONST1

SRC_VAR2: DB "VARIABLE BAZ 7 BAZ ! BAZ @ "
SRC_VAR2_LEN EQU $ - SRC_VAR2

SRC_FOO_RECHECK: DB "FOO @ "
SRC_FOO_RECHECK_LEN EQU $ - SRC_FOO_RECHECK

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/variable.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p12_rom0.bin", $0000, $4000
