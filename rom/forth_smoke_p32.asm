; ============================================================================
; rom/forth_smoke_p32.asm — Phase 32 smoke ROM: SOUND
;
; THREE CHECKPOINTS, all data-stack-hygiene checks — see core/sound.asm's
; own header for why (no way to verify actual AY-3-8912 output in this
; environment, and this project keeps no software shadow of the AY
; ports to read back either, unlike BORDER):
;   1. A valid register/data pair (8, 15 — the real ROM's own
;      documented example) runs to completion and leaves a sentinel
;      value correctly in place.
;   2. Register 0 (the real ROM's own low boundary — rejected) is
;      silently ignored; sentinel survives.
;   3. Register 17 (the real ROM's own high boundary — rejected) is
;      silently ignored; sentinel survives.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number (1-3).
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

    ld   hl, DICT_LATEST_INIT_SOUND
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: valid register/data (8, 15) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, TEST_SRC_VALID
    ld   de, TEST_SRC_VALID_LEN
    call INTERPRET_RUN
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: register 0 (rejected, low boundary) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, TEST_SRC_LOW
    ld   de, TEST_SRC_LOW_LEN
    call INTERPRET_RUN
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: register 17 (rejected, high boundary) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, TEST_SRC_HIGH
    ld   de, TEST_SRC_HIGH_LEN
    call INTERPRET_RUN
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_TOP:                       ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
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

CHECKPOINT_NUM EQU $8800

TEST_SRC_VALID: DB "8 15 SOUND "
TEST_SRC_VALID_LEN EQU $ - TEST_SRC_VALID
TEST_SRC_LOW:   DB "0 200 SOUND "
TEST_SRC_LOW_LEN EQU $ - TEST_SRC_LOW
TEST_SRC_HIGH:  DB "17 200 SOUND "
TEST_SRC_HIGH_LEN EQU $ - TEST_SRC_HIGH

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/sound.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p32_rom0.bin", $0000, $4000
