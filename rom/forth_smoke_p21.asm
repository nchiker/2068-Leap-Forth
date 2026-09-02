; ============================================================================
; rom/forth_smoke_p21.asm — Phase 21 smoke ROM: error feedback for an
; unknown word
;
; Replicates rom/forth_boot.asm's own real INTERPRET_UNKNOWN_WORD
; (print "?" + newline, then return) directly in this file, the same
; way every smoke ROM already defines its own independent
; INTERPRET_UNKNOWN_WORD hook -- there's no way to INCLUDE forth_boot's
; own hook without pulling in its whole COLD_START, so it's copied
; here verbatim, matching exactly what's in rom/forth_boot.asm.
;
; TWO CHECKPOINTS:
;   1. INTERPRET_RUN("BOGUSWORD ") -- an unrecognized word must land on
;      INTERPRET_UNKNOWN_WORD and print "?" then a newline: PRINT_ROW
;      advances to 1, PRINT_COL resets to 0.
;   2. A SEPARATE, later INTERPRET_RUN("5 BORDER ") must still execute
;      normally afterward -- proving the interpreter recovers rather
;      than being left in a broken state by the first checkpoint's
;      bare `ret`. Checked via PORT_FE_SHADOW's own low 3 bits (the
;      real border-color mirror GFX_SET_BORDER maintains), not just
;      "did it hang or not".
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number, UNLESS checkpoint 2 itself is what's under test
; (BORDER changes the border deliberately) -- checkpoint 2's own
; success is read from PORT_FE_SHADOW, then the border is forced green
; explicitly afterward so PASS/FAIL still reads correctly either way.
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

    ld   hl, DICT_LATEST_INIT_PRINT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: unknown word prints "?" + newline ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_BOGUS
    ld   de, SRC_BOGUS_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   0
    jp   nz, FAIL_TEST

; ---- checkpoint 2: interpreter still works afterward ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_BORDER
    ld   de, SRC_BORDER_LEN
    call INTERPRET_RUN
    ld   a, (PORT_FE_SHADOW)
    and  $07
    cp   5
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

; ---- replicated verbatim from rom/forth_boot.asm's own real hook ----
INTERPRET_UNKNOWN_WORD:
    ld   hl, "?"
    call DPUSH_HL
    call W_EMIT
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
    ret

CHECKPOINT_NUM EQU $8800

SRC_BOGUS: DB "BOGUSWORD "
SRC_BOGUS_LEN EQU $ - SRC_BOGUS

SRC_BORDER: DB "5 BORDER "
SRC_BORDER_LEN EQU $ - SRC_BORDER

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/print.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p21_rom0.bin", $0000, $4000
