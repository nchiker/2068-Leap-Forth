; ============================================================================
; rom/forth_smoke_p6.asm — Phase 6 smoke ROM: line editing
;
; Proves core/editor.asm's EDITOR_PROCESS_KEY (insert, delete, cursor
; movement, ENTER detection) by feeding it a canned sequence of key
; codes from ROM data instead of live keyboard input — deterministic,
; no Fuse keystroke injection needed. See core/editor.asm's own header
; for why EDITOR_LOOP_LIVE (the real interactive entry point) is NOT
; exercised here, and what real precondition it has that this ROM
; deliberately doesn't set up (interrupts stay disabled, same as every
; earlier smoke ROM in this project).
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only kernel/math,
; kernel/io, and kernel/graphics are needed — not kernel/sound or
; core/control.asm/core/ts2068.asm, since this test never uses BEEP,
; PLOT, IF, or any other word from those files; LATEST is seeded to
; core/interp.asm's own DICT_LATEST_INIT_P3 (Phase 3's tail — DUP
; SWAP DROP OVER + - @ ! and : ; are all this test needs).
;
; SELF-TEST, three canned key sequences, each ending in KEY_ENTER, each
; fed to EDITOR_PROCESS_KEY one byte at a time and then committed via
; INTERPRET_RUN once ENTER's carry is seen:
;   1. "5 3 +" ENTER -> plain typing, no editing -> top of stack 8.
;   2. "13" LEFT "2" ENTER -> typing "13", moving the cursor back one
;      position, then inserting "2" in the middle -> the buffer becomes
;      "123" -> top of stack 123. Proves LEFT and mid-buffer insert.
;   3. "1x3" LEFT DELETE RIGHT ENTER -> typing "1x3", moving left once
;      (cursor between 'x' and '3'), deleting the character before the
;      cursor (the stray 'x'), then moving right (back to the end) ->
;      the buffer becomes "13" -> top of stack 13. Proves DELETE and
;      RIGHT, and that a mid-buffer delete correctly finishes at the
;      right final content.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number (1-3), matching every earlier smoke ROM's
; convention.
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/keys.inc"

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
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

    ld   hl, DICT_LATEST_INIT_P3
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: plain typing, no editing ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, KEYS_1
    ld   b, KEYS_1_LEN
    call TYPE_KEYS
    ld   de, 8
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: LEFT + mid-buffer insert ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, KEYS_2
    ld   b, KEYS_2_LEN
    call TYPE_KEYS
    ld   de, 123
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: DELETE + RIGHT ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, KEYS_3
    ld   b, KEYS_3_LEN
    call TYPE_KEYS
    ld   de, 13
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
TYPE_KEYS:                       ; HL = canned key array, B = length
                                  ; (last byte must be KEY_ENTER); feeds
                                  ; every byte to EDITOR_PROCESS_KEY,
                                  ; then commits the resulting line via
                                  ; INTERPRET_RUN
    xor  a
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
.loop:
    ld   a, (hl)
    push hl
    push bc
    call EDITOR_PROCESS_KEY
    pop  bc
    pop  hl
    inc  hl
    djnz .loop
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   d, 0
    ld   e, a
    call INTERPRET_RUN
    ret

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

FAIL_TEST:                       ; border shows which checkpoint (1-3) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8574         ; 1 byte, right after core/editor.asm's
                                  ; own scratch (see that file)

KEYS_1:     DB "5", " ", "3", " ", "+", KEY_ENTER
KEYS_1_LEN  EQU $ - KEYS_1
KEYS_2:     DB "1", "3", KEY_CURSOR_LEFT, "2", KEY_ENTER
KEYS_2_LEN  EQU $ - KEYS_2
KEYS_3:     DB "1", "x", "3", KEY_CURSOR_LEFT, KEY_DELETE, KEY_CURSOR_RIGHT, KEY_ENTER
KEYS_3_LEN  EQU $ - KEYS_3

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p6_rom0.bin", $0000, $4000
