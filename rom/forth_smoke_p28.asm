; ============================================================================
; rom/forth_smoke_p28.asm — Phase 28 smoke ROM: ACCEPT and INPUT
;
; Unlike rom/forth_smoke_p20.asm's own KEY test (a single simulated
; keypress, written directly into KBD_LASTK/KBD_KEYHIT before ONE
; INTERPRET_RUN call), ACCEPT's own internal loop calls IO_READ_KEY
; MANY times in a row without ever returning control to this file's
; own code in between -- there is no point to "step in" between each
; character the way a single-key test can. Real IM 1 interrupts (like
; rom/forth_smoke_p9.asm's own proof that RST 38 -> a real handler
; actually fires) are used instead: this ROM's own RST 38 handler
; feeds the NEXT character from a small scripted array into KBD_LASTK/
; KBD_KEYHIT on every real hardware tick (Fuse's own emulated ~50Hz
; frame interrupt, not a real keyboard), so ACCEPT's own busy-wait loop
; naturally picks up one new scripted character per tick, exactly as
; it would from a real keyboard's own repeated ISR ticks.
;
; TWO CHECKPOINTS:
;   1. ACCEPT into a 5-character buffer, scripted keys "HELLOX" then
;      DELETE then ENTER: the 6th character ('X') is silently ignored
;      (buffer already at its 5-character limit when it arrives), then
;      DELETE removes the 5th ('O'), leaving "HELL" -- ACCEPT must
;      return len=4, and the buffer's own first 4 bytes must read back
;      as "HELL" (checked by TYPE-ing them back, not just the length):
;      ACCEPT's own live echo prints "HELL" (4 chars, the 'O' visually
;      erased again by the scripted DELETE), then "4 " from `.`, then
;      "HELL" again from `TYPE` -- PRINT_COL advances by 10 in total.
;   2. INPUT with scripted keys "123" then ENTER -- must return 123 on
;      the data stack.
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number (never 4 -- see rom/forth_smoke_p27.asm's own
; header for why a checkpoint literally numbered 4 would collide with
; PASS_TEST's own green; both checkpoints here are 1/2, so this doesn't
; actually arise, but the fixed convention is followed anyway).
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
    call FEED_NEXT_SCRIPTED_KEY
    ei
    reti
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

; ============================================================================
; FEED_NEXT_SCRIPTED_KEY — this ROM's own fake keyboard ISR. Advances
; through whichever script SCRIPT_PTR/SCRIPT_END currently bracket,
; writing one character per real hardware tick into KBD_LASTK/
; KBD_KEYHIT -- exactly what a real key-scanning ISR tick would do,
; just from a canned array instead of the physical keyboard matrix.
; Stops (does nothing) once the script is exhausted, leaving
; KBD_KEYHIT clear so IO_READ_KEY's own busy-wait simply keeps waiting
; (harmless: by the time a script runs out, the checkpoint's own
; INTERPRET_RUN has already returned, since ENTER is always the last
; scripted character).
; ============================================================================
FEED_NEXT_SCRIPTED_KEY:
    ld   hl, (SCRIPT_PTR)
    ld   de, (SCRIPT_END)
    or   a
    sbc  hl, de
    ret  z                       ; SCRIPT_PTR == SCRIPT_END: exhausted
    add  hl, de                  ; hl = SCRIPT_PTR again (undo the sbc)
    ld   a, (hl)
    ld   (KBD_LASTK), a
    ld   a, 1
    ld   (KBD_KEYHIT), a
    inc  hl
    ld   (SCRIPT_PTR), hl
    ret

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_INPUT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: ACCEPT (typing past the limit, then DELETE) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SCRIPT1
    ld   (SCRIPT_PTR), hl
    ld   hl, SCRIPT1 + SCRIPT1_LEN
    ld   (SCRIPT_END), hl
    im   1
    ei
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    di
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   10
    jp   nz, FAIL_TEST

; ---- checkpoint 2: INPUT ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SCRIPT2
    ld   (SCRIPT_PTR), hl
    ld   hl, SCRIPT2 + SCRIPT2_LEN
    ld   (SCRIPT_END), hl
    im   1
    ei
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    di
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 123
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
SCRIPT_PTR     EQU $8801   ; 2 bytes: FEED_NEXT_SCRIPTED_KEY's own
                           ; scratch -- next scripted character
SCRIPT_END     EQU $8803   ; 2 bytes: one past the last scripted
                           ; character
DEST_BUF       EQU $8806   ; 5 bytes: ACCEPT's own destination for
                           ; checkpoint 1 -- 34822 decimal, embedded
                           ; directly as a literal in SRC_CP1 below
                           ; (Forth source text, not a Z80 operand, so
                           ; it has to be spelled out in decimal)

; checkpoint 1: ACCEPT into DEST_BUF (34822) with maxlen 5, print the
; returned length, then TYPE the buffer back out to confirm its actual
; contents, not just the length
SRC_CP1: DB "34822 5 ACCEPT DUP . 34822 SWAP TYPE "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "INPUT "
SRC_CP2_LEN EQU $ - SRC_CP2

SCRIPT1: DB "HELLOX", KEY_DELETE, KEY_ENTER
SCRIPT1_LEN EQU $ - SCRIPT1

SCRIPT2: DB "123", KEY_ENTER
SCRIPT2_LEN EQU $ - SCRIPT2

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/string.asm"
DICT_CHAIN_POINT DEFL H_VAL
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_KEY
    INCLUDE "core/input.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p28_rom0.bin", $0000, $4000
