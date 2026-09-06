; ============================================================================
; rom/forth_smoke_p58.asm — Phase 58 smoke ROM: EDITOR_REDRAW64/
; WRAP_CALC64 (core/editor.asm), the real-64-column-TEXT stretch
; goal's Phase F -- editor integration, the last of the three planned
; phases
;
; Mirrors rom/forth_smoke_p33.asm's own approach exactly: feed
; EDITOR_PROCESS_KEY a canned key array via TYPE_NO_ENTER (no live
; X11 injection, which this project's own history shows can silently
; drop keystrokes), then inspect FWRAP_COUNT/START/LEN and
; EDIT_CURSOR_TO_ROWCOL directly. Mode switches call kernel/mode64's
; own GFX_SET_MODE/MODE64_ON directly (same technique
; rom/forth_smoke_p56.asm already used) rather than through Forth
; words, avoiding that file's own real dictionary-chain dependency
; chase entirely (core/mode64.asm's Forth wrapper needs core/float.asm
; needs core/throwcatch.asm, none of which this test needs).
;
; FOUR CHECKPOINTS:
;   1. 64-column mode, 40 "A"s (no spaces) typed via EDITOR_PROCESS_KEY:
;      FWRAP_COUNT must be 1 (fits entirely on one 64-column row) --
;      the same 40 characters would hard-break into 2 rows at width 32,
;      so this proves EDITOR_REDRAW64 is really calling WRAP_CALC64,
;      not the original WRAP_CALC.
;   2. 60 "A"s + space + 10 "B"s (71 characters): word-boundary wrap at
;      the space -> row 0 = 60 "A"s, row 1 = 10 "B"s (the space itself
;      consumed but never drawn) -- FWRAP_COUNT/START/LEN checked
;      directly, same convention as rom/forth_smoke_p33.asm's own
;      checkpoint 1, just at width 64.
;   3. Real rendering: after checkpoint 2, column 40 of row 0 (60 "A"s,
;      so column 40 is inside the Second Display File) must show 'A''s
;      real glyph bytes -- proves EDITOR_REDRAW64 actually called
;      MODE64_PUTCHAR, not just that its own row/column bookkeeping is
;      right.
;   4. Normal (32-column) mode regression: the SAME 40 "A"s from
;      checkpoint 1, typed again after switching back to Normal mode,
;      must now hard-break into 2 rows (FWRAP_COUNT=2, row 0 = 32
;      "A"s) -- proving EDITOR_REDRAW's own mode dispatch correctly
;      routes back to the ORIGINAL, untouched WRAP_CALC/EDITOR_REDRAW
;      when GFX_MODE is not 2.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_P3
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   a, 1
    ld   (FWRAP_OLD_COUNT), a

    call GFX_CLS

; ---- checkpoint 1: 64-column mode calls WRAP_CALC64, not WRAP_CALC ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call MODE64_ON
    call RESET_LINE
    ld   hl, TEST1_STR
    ld   b, TEST1_LEN
    call TYPE_NO_ENTER
    ld   a, (FWRAP_COUNT)
    cp   1
    jp   nz, FAIL_TEST

; ---- checkpoint 2: word-boundary wrap at column 64 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    call RESET_LINE
    ld   hl, TEST2_STR
    ld   b, TEST2_LEN
    call TYPE_NO_ENTER
    ld   a, (FWRAP_COUNT)
    cp   2
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_START
    ld   a, (hl)
    cp   0
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN
    ld   a, (hl)
    cp   60
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_START+1
    ld   a, (hl)
    cp   61
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN+1
    ld   a, (hl)
    cp   10
    jp   nz, FAIL_TEST

; ---- checkpoint 3: real rendering -- column 40 (Second Display File)
; of row 0 shows 'A' ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   a, "A"
    call GFX_CHAR_TO_FONT_OFFSET   ; hl = glyph ptr -- computed before
    push hl                        ; the DE-clobbering address math
                                   ; (same real bug class this project
                                   ; hit in rom/forth_smoke_p56.asm)
    ld   a, 22                     ; row 0 of a 2-row-wrapped input
                                   ; line anchored at EDIT_ROW (23) is
                                   ; screen row (23+1-2)+0 = 22
    call GFX_ROW_BASE_ADDR
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ld   a, l
    add  a, 8                      ; col 40 & 31 = 8
    ld   l, a
    jr   nc, .cp3_noc
    inc  h
.cp3_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 4: Normal mode regression -- same 40 "A"s now hard-
; break at column 32 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    call GFX_SET_MODE               ; back to Normal mode (0)
    call RESET_LINE
    ld   hl, TEST1_STR
    ld   b, TEST1_LEN
    call TYPE_NO_ENTER
    ld   a, (FWRAP_COUNT)
    cp   2
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN
    ld   a, (hl)
    cp   32
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
RESET_LINE:                      ; ( -- ) fresh empty line, same reset
                                  ; EDITOR_LOOP_LIVE does per line
    xor  a
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
    ret

TYPE_NO_ENTER:                   ; HL = key array, B = length; feeds
                                  ; every byte to EDITOR_PROCESS_KEY,
                                  ; no ENTER/INTERPRET_RUN -- this file
                                  ; only inspects wrap state/rendering
                                  ; directly
.loop:
    ld   a, (hl)
    push hl
    push bc
    call EDITOR_PROCESS_KEY
    pop  bc
    pop  hl
    inc  hl
    djnz .loop
    ret

COMPARE_GLYPH_AT:
    ld   b, 8
.loop:
    ld   a, (de)
    cp   (hl)
    jr   nz, .mismatch
    inc  hl
    ld   a, d
    inc  a
    ld   d, a
    djnz .loop
    xor  a
    ret
.mismatch:
    ld   a, 1
    or   a
    ret

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
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

CHECKPOINT_NUM EQU $8542         ; alongside core/interp.asm's own
                                  ; WORD_BUF -- see rom/forth_smoke_p3.asm

TEST1_STR: DB "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TEST1_LEN  EQU $ - TEST1_STR

TEST2_STR: DB "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA BBBBBBBBBB"
TEST2_LEN  EQU $ - TEST2_STR

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p58_rom0.bin", $0000, $4000
