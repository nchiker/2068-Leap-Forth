; ============================================================================
; rom/forth_smoke_p20.asm — Phase 20 smoke ROM: KEY
;
; No real IM 1 interrupt/live keyboard needed for this test -- KEY's
; own code (W_KEY) just calls kernel/io's IO_READ_KEY, which is a thin
; consumer of KBD_LASTK/KBD_KEYHIT (normally latched by the real ISR,
; kernel/interrupt's KBD_ISR_TICK). Simulating a keypress by writing
; those two sysvars directly, the same values a real ISR tick would
; have latched, tests KEY's own wrapper code without needing a real
; interrupt running at all -- matching core/editor.asm's own Phase 6
; precedent of testing EDITOR_PROCESS_KEY with canned key codes rather
; than a live keyboard.
;
; TWO CHECKPOINTS:
;   1. Simulate an ASCII 'A' (65) keypress; KEY must push 65.
;   2. Simulate a second, different keypress (ASCII '5', 53); KEY must
;      push 53 -- proving KEY correctly re-reads state rather than
;      caching the first result.
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number.
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

    ld   hl, DICT_LATEST_INIT_KEY
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: simulate 'A' (65) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   a, 65
    ld   (KBD_LASTK), a
    ld   a, 1
    ld   (KBD_KEYHIT), a
    ld   hl, SRC_KEY
    ld   de, SRC_KEY_LEN
    call INTERPRET_RUN
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 65
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST

; ---- checkpoint 2: simulate '5' (53) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   a, 53
    ld   (KBD_LASTK), a
    ld   a, 1
    ld   (KBD_KEYHIT), a
    ld   hl, SRC_KEY
    ld   de, SRC_KEY_LEN
    call INTERPRET_RUN
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 53
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: both checkpoints passed
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

SRC_KEY: DB "KEY "
SRC_KEY_LEN EQU $ - SRC_KEY

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/io/io.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/key.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p20_rom0.bin", $0000, $4000
