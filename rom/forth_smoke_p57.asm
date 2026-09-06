; ============================================================================
; rom/forth_smoke_p57.asm — Phase 57 smoke ROM: mode-aware EMIT
; (core/print.asm), the real-64-column-TEXT stretch goal's Phase E
;
; FOUR CHECKPOINTS, all through real Forth words (64COL/32COL/EMIT/
; DO/LOOP/INK) — Phase 56 already proved the underlying kernel
; primitives directly; this proves EMIT actually reaches them. This
; ROM's own dictionary chain deliberately stops at core/doloop.asm
; (mirroring rom/forth_boot.asm's own real chain up to that point,
; needed after this file's own first draft got a DICT_CHAIN_POINT
; wrong by hand and orphaned words -- see the chain comment near the
; INCLUDEs below) -- it does NOT include core/moregfx.asm, so AT-XY
; is not available here; checkpoints reset PRINT_ROW/PRINT_COL with a
; direct poke instead (this file's own first draft used AT-XY, hit a
; real "unknown word" as a result, and was fixed by removing the
; dependency rather than adding another file to the chain):
;   1. 64COL, then EMIT 64 characters via DO/LOOP: PRINT_COL must wrap
;      at 64 (not 32) -- PRINT_ROW/COL end at (1, 0) -- and the
;      character actually drawn at column 40 (Second Display File)
;      must match its real glyph bytes, proving EMIT truly called
;      MODE64_PUTCHAR, not just that the row/col counters moved.
;   2. Continue for 1,408 more characters (exactly 22 more full 64-
;      column rows) -- enough to force EMIT's own scroll trigger
;      exactly once. PRINT_ROW/COL must settle at (22, 0) (never
;      higher, per MODE64_SCROLL_TEXT_UP's own contract); row 21 (what
;      row 22's own just-typed content scrolled UP into) must show the
;      right glyph in BOTH display files, proving the scroll moved
;      both together; and row 22 itself (left for the caller to draw
;      into, same contract as GFX_SCROLL_TEXT_UP) must now be BLANK.
;   3. Reset PRINT_ROW/COL to (0,0), 32COL, then EMIT 32 characters via
;      DO/LOOP:
;      PRINT_ROW/COL must end at (1, 0) -- the ORIGINAL 32-column wrap,
;      completely unaffected by any of the 64-column code above
;      (regression, not just new behavior).
;   4. 64COL again; poke a sentinel byte into the Normal attribute cell
;      EMIT is about to draw into, then EMIT one character there with
;      INK set to a different color: the sentinel must be UNCHANGED
;      afterward, proving EMIT's 64-column path genuinely skips
;      CURRENT_ATTR stamping (Mode 6 has no per-cell attribute at all)
;      rather than merely not being tested.
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
    ld   iy, FSTACK_TOP           ; this ROM includes core/float.asm
                                  ; (mode64.asm's own hardcoded chain
                                  ; dependency) with RUNTIME_ERROR_CHECK_
                                  ; ENABLED defined -- STACK_CHECK
                                  ; validates IY against FSTACK_TOP/
                                  ; LIMIT on every word, and an
                                  ; uninitialized IY spuriously failed
                                  ; that check on the very first word,
                                  ; landing in RUNTIME_ERROR_HOOK -- a
                                  ; real bug this checkpoint's own first
                                  ; draft had, found by distinguishing
                                  ; which debugger breakpoint actually
                                  ; fired (RUNTIME_ERROR_HOOK, not
                                  ; INTERPRET_UNKNOWN_WORD as first
                                  ; assumed), not by inspection

    ld   hl, DICT_LATEST_INIT_P57
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

; ---- checkpoint 1: 64COL wraps EMIT at column 64, reaches Second file ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    or   a
    jp   nz, FAIL_TEST

    ld   a, "X"
    call GFX_CHAR_TO_FONT_OFFSET   ; hl = glyph ptr -- MUST run before
    push hl                        ; the DE-clobbering address math
    ld   a, 0
    call GFX_ROW_BASE_ADDR         ; hl = row 0's base, Primary-relative
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de                    ; hl = row 0's base, Second-file
    ld   a, l
    add  a, 8                      ; col 40 & 31 = 8
    ld   l, a
    jr   nc, .cp1_noc
    inc  h
.cp1_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 2: 1,408 more chars force a real scroll ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   22
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    or   a
    jp   nz, FAIL_TEST

    ; MODE64_SCROLL_TEXT_UP's own contract (mirrors GFX_SCROLL_TEXT_UP
    ; exactly): row 21's content becomes row 22's -- wait, the other
    ; way: scrolling UP moves row 22's content to row 21, and leaves
    ; row 22 ITSELF cleared for the caller to draw into (which nothing
    ; does here, since CP2's own 1408 characters were the last thing
    ; printed) -- so the just-scrolled 'Y' content now lives at row
    ; 21, and row 22 must be BLANK. This checkpoint's own first draft
    ; checked row 22 for 'Y' and failed -- a real bug in the TEST's own
    ; expectation, not in MODE64_SCROLL_TEXT_UP (already directly
    ; verified correct by rom/forth_smoke_p56.asm's own checkpoint 3),
    ; found by isolating exactly which sub-check failed via a temporary
    ; distinct CHECKPOINT_NUM marker, not by inspection.
    ld   a, "Y"
    call GFX_CHAR_TO_FONT_OFFSET
    push hl
    ld   a, 21
    call GFX_ROW_BASE_ADDR         ; row 21, Primary file, col 5
    ld   a, l
    add  a, 5
    ld   l, a
    jr   nc, .cp2a_noc
    inc  h
.cp2a_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, "Y"
    call GFX_CHAR_TO_FONT_OFFSET
    push hl
    ld   a, 21
    call GFX_ROW_BASE_ADDR         ; row 21, Second file, col 40
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ld   a, l
    add  a, 8
    ld   l, a
    jr   nc, .cp2b_noc
    inc  h
.cp2b_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ; row 22 itself must now be BLANK (MODE64_CLEAR_ROW's own doing,
    ; right after the scroll) -- spot-check one column of each file
    ld   a, " "
    call GFX_CHAR_TO_FONT_OFFSET
    push hl
    ld   a, 22
    call GFX_ROW_BASE_ADDR
    ld   a, l
    add  a, 5
    ld   l, a
    jr   nc, .cp2c_noc
    inc  h
.cp2c_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 3: 32COL still wraps at 32 (regression) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a                         ; reset the print position directly --
    ld   (PRINT_ROW), a            ; this ROM doesn't include core/
    ld   (PRINT_COL), a            ; moregfx.asm (AT-XY), only the
                                   ; narrow chain checkpoints 1-2 needed
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   1
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 4: 64-column EMIT skips CURRENT_ATTR stamping ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   a, $99
    ld   (ATTR_ADDR), a            ; sentinel at row 0, col 0's own
                                   ; Normal-mode attribute cell
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   a, (ATTR_ADDR)
    cp   $99                       ; must be UNCHANGED -- real GFX_SET_
    jp   nz, FAIL_TEST             ; ATTR would have overwritten this

    jp   PASS_TEST

; ---- test-harness-only helper: NOT a dictionary word ----
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

; RUNTIME_ERROR_HOOK -- required by THROW_CATCH_ENABLED/core/storage.asm's
; own unconditional W_THROW call on dictionary overflow (never actually
; exercised by this test). Nothing in this test should ever reach this;
; same minimal "something's wrong" signal as INTERPRET_UNKNOWN_WORD,
; matching rom/forth_smoke_p46.asm's own precedent for this exact
; dependency in a narrow smoke ROM.
RUNTIME_ERROR_HOOK:
    ld   a, 7
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

; DO/LOOP are IMMEDIATE words that always compile (core/doloop.asm's
; own header: "DO/LOOP themselves MUST" be used inside a colon
; definition) -- typed bare at the top level they compile into
; whatever HERE happens to be and are never actually executed, which
; is exactly the real bug this smoke ROM's own first draft had (an
; apparent hang, root-caused via a direct Fuse breakpoint/memory-peek
; session, not by inspection). Every checkpoint below wraps its DO/LOOP
; in a real colon definition, matching every other DO/LOOP smoke ROM's
; own established convention (rom/forth_smoke_p16.asm's own header).
SRC_CP1: DB "64COL : REP1 64 0 DO 88 EMIT LOOP ; REP1 "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB ": REP2 1408 0 DO 89 EMIT LOOP ; REP2 "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "32COL : REP3 32 0 DO 90 EMIT LOOP ; REP3 "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "64COL 5 INK 88 EMIT "
SRC_CP4_LEN EQU $ - SRC_CP4

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000. This mirrors
; rom/forth_boot.asm's own real include/DICT_CHAIN_POINT order exactly
; up through core/doloop.asm (needed for DO/LOOP/I) -- copied
; deliberately rather than hand-picking a minimal subset, after this
; same session already found two real dictionary-orphaning bugs from
; getting a DICT_CHAIN_POINT wrong by hand (Phase 54, and this file's
; own sibling rom/forth_smoke_p55.asm). core/mode64.asm's own H_64COL
; header hardcodes its LINK to H_FMINUS (core/float.asm's own tail),
; not DICT_CHAIN_POINT -- another reason to mirror the proven order
; rather than reorder anything.
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    DEFINE RUNTIME_ERROR_CHECK_ENABLED
    DEFINE THROW_CATCH_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOADLIB
    INCLUDE "core/throwcatch.asm"   ; core/storage.asm's own dictionary-
                                    ; overflow path unconditionally
                                    ; calls W_THROW -- needed here even
                                    ; though this ROM never uses CATCH/
                                    ; THROW as dictionary words itself
DICT_CHAIN_POINT DEFL H_CATCH
    INCLUDE "core/float.asm"
    INCLUDE "core/mode64.asm"
DICT_CHAIN_POINT DEFL H_PLOT64
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/decimal.asm"
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/floatprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/floatsqrt.asm"
DICT_CHAIN_POINT DEFL H_FSQRT
    INCLUDE "core/floatconv.asm"
DICT_CHAIN_POINT DEFL H_FROUND
    INCLUDE "core/floattrig.asm"
DICT_CHAIN_POINT DEFL H_DEG
    INCLUDE "core/beep.asm"
DICT_CHAIN_POINT DEFL H_BEEP
    INCLUDE "core/sound.asm"
DICT_CHAIN_POINT DEFL H_SOUND
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/variable.asm"
DICT_CHAIN_POINT DEFL H_CONSTANT
    INCLUDE "core/dotquote.asm"
DICT_CHAIN_POINT DEFL H_DOTQUOTE
    INCLUDE "core/loop.asm"
DICT_CHAIN_POINT DEFL H_REPEAT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/doloop.asm"

DICT_LATEST_INIT_P57 EQU H_I   ; head of the dictionary once this ROM's
                                ; own chain (through core/doloop.asm)
                                ; is included

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p57_rom0.bin", $0000, $4000
