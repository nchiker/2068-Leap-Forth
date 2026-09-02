; ============================================================================
; rom/forth_smoke_p33.asm — Phase 33 smoke ROM: real multi-row word wrap
;
; Proves core/editor.asm's rewritten WRAP_CALC/EDIT_CURSOR_TO_ROWCOL —
; the user asked directly for real multi-row word wrap in the editor,
; replacing the original single-row, 31-character, silently-drops-
; extra-keystrokes behavior rom/forth_smoke_p6.asm still separately
; proves is unaffected by this rewrite.
;
; Every expected value below was hand-derived by a Python simulation of
; the EXACT algorithm before this file was written (mirroring the same
; discipline every earlier phase in this project has used for its own
; hand-verified test cases), including the real overflow-detection bug
; that simulation itself caught before any Z80 was trusted — see
; core/editor.asm's own FWRAP_OVERFLOW comment for that story.
;
; FOUR CHECKPOINTS:
;   1. Word-boundary wrap: 29 "A"s + a space + 10 "B"s (40 characters)
;      breaks at the space (not mid-word) -> 2 rows, row 0 = 29 "A"s,
;      row 1 = 10 "B"s (the space itself is consumed but never drawn).
;      Also checks the cursor lands at (row 22, col 29) when sitting
;      exactly on the consumed space, and (row 23, col 0) one position
;      later — the "boundary" case core/editor.asm's own
;      EDIT_CURSOR_TO_ROWCOL header describes.
;   2. Hard-break wrap: 35 "X"s (no spaces anywhere) has no word
;      boundary to break at, so row 0 hard-breaks at exactly 32 -> 2
;      rows, row 0 = 32 "X"s, row 1 = 3 "X"s. Also checks the cursor
;      rolls forward to (row 23, col 0) rather than landing on the
;      out-of-range column 32, for a cursor sitting exactly at the end
;      of the full hard-wrapped row 0.
;   3. Capacity cap: typing four complete 20-character words ("C"*19 +
;      space, four times = 80 characters) plus 12 more "C"s (92
;      characters total) fits EXACTLY into the 4-row cap with no
;      leftover (row 3 hard-breaks at exactly 32, using up the last of
;      the buffer) — confirms the cap is EXACT, not overly
;      conservative.
;   4. Capacity cap, one character further: typing one more "C" after
;      checkpoint 3's own 92 characters would need a genuine 5th row —
;      confirmed REJECTED (EDIT_LEN stays at 92), proving
;      FWRAP_OVERFLOW's own detection actually engages.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
; failing checkpoint's number (1-4).
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/keys.inc"

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

    ld   hl, DICT_LATEST_INIT_P3
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a           ; 0 -- always below the input area's
    ld   (PRINT_COL), a           ; own top row (20-23), so growth
                                  ; never spuriously scrolls in this
                                  ; test
    ld   a, 1
    ld   (FWRAP_OLD_COUNT), a

    call GFX_CLS

; ---- checkpoint 1: word-boundary wrap (40 chars: 29 A's, space, 10 B's) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call RESET_LINE
    ld   hl, TEST1_STR
    ld   b, TEST1_LEN
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
    cp   29
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_START+1
    ld   a, (hl)
    cp   30
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN+1
    ld   a, (hl)
    cp   10
    jp   nz, FAIL_TEST
    ld   a, 29
    ld   (EDIT_CURSOR), a
    call EDIT_CURSOR_TO_ROWCOL
    ld   a, b
    cp   22
    jp   nz, FAIL_TEST
    ld   a, c
    cp   29
    jp   nz, FAIL_TEST
    ld   a, 30
    ld   (EDIT_CURSOR), a
    call EDIT_CURSOR_TO_ROWCOL
    ld   a, b
    cp   23
    jp   nz, FAIL_TEST
    ld   a, c
    cp   0
    jp   nz, FAIL_TEST

; ---- checkpoint 2: hard-break wrap (35 X's, no spaces) ----
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
    cp   32
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_START+1
    ld   a, (hl)
    cp   32
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN+1
    ld   a, (hl)
    cp   3
    jp   nz, FAIL_TEST
    ld   a, 31
    ld   (EDIT_CURSOR), a
    call EDIT_CURSOR_TO_ROWCOL
    ld   a, b
    cp   22
    jp   nz, FAIL_TEST
    ld   a, c
    cp   31
    jp   nz, FAIL_TEST
    ld   a, 32
    ld   (EDIT_CURSOR), a
    call EDIT_CURSOR_TO_ROWCOL
    ld   a, b
    cp   23
    jp   nz, FAIL_TEST
    ld   a, c
    cp   0
    jp   nz, FAIL_TEST

; ---- checkpoint 3: capacity cap, EXACT fit (92 chars) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    call RESET_LINE
    ld   hl, TEST3_STR
    ld   b, TEST3_LEN
    call TYPE_NO_ENTER
    ld   a, (EDIT_LEN)
    cp   92
    jp   nz, FAIL_TEST
    ld   a, (FWRAP_COUNT)
    cp   4
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_START+3
    ld   a, (hl)
    cp   60
    jp   nz, FAIL_TEST
    ld   hl, FWRAP_LEN+3
    ld   a, (hl)
    cp   32
    jp   nz, FAIL_TEST

; ---- checkpoint 4 (border color 5, not 4 -- see rom/forth_smoke_p27.asm's
; own header for why): one more character genuinely overflows FWRAP_MAX_ROWS
; and must be rejected ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   a, "C"
    call EDITOR_PROCESS_KEY
    ld   a, (EDIT_LEN)
    cp   92
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
                                  ; only inspects wrap state directly
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

TEST1_STR: DB "AAAAAAAAAAAAAAAAAAAAAAAAAAAAA BBBBBBBBBB"
TEST1_LEN  EQU $ - TEST1_STR
TEST2_STR: DB "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
TEST2_LEN  EQU $ - TEST2_STR
TEST3_STR: DB "CCCCCCCCCCCCCCCCCCC CCCCCCCCCCCCCCCCCCC CCCCCCCCCCCCCCCCCCC CCCCCCCCCCCCCCCCCCC CCCCCCCCCCCC"
TEST3_LEN  EQU $ - TEST3_STR

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p33_rom0.bin", $0000, $4000
