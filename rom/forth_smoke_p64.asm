; ============================================================================
; rom/forth_smoke_p64.asm — Phase 64 smoke ROM: LIST-DEFS and the store
; append (core/recall.asm; RECALL and its checkpoints 4 and 5 retired at
; step E item 7 -- checkpoint 6 keeps its number, since border 4 is PASS)
;
; Tests core/recall.asm's own logic in isolation from LOAD-TEXT's real
; tape wiring (already proven by rom/forth_smoke_p52.asm) and from
; core/editor.asm's live keyboard loop (an honest gap for the same
; reason rom/forth_smoke_p62.asm's own header names: EDITOR_LOOP_LIVE
; needs a live or injected keyboard, genuinely out of reach for an
; automated border-color smoke ROM). Deliberately does NOT INCLUDE
; core/loadtext.asm or core/editor.asm — LOADTEXT_BUF/LOADTEXT_MAX_LEN/
; STORE_END and EDIT_BUF/EDIT_LEN/EDIT_CURSOR/EDIT_MAX_LEN are
; redeclared here as the SAME literal values those files use (confirmed
; by direct comparison, not guessed), avoiding kernel/storage's own
; fake-tape harness and core/editor.asm's kernel/io dependency entirely
; for a test that doesn't need either.
;
; PRINT_UDEC16 is stubbed to a bare `ret` -- W_LISTDEFS references it
; (so core/recall.asm can't assemble without SOME definition existing),
; but this smoke ROM's own checkpoints never call W_LISTDEFS: its output
; is screen text, not a boolean pass/fail condition, the same honest-gap
; class as rom/mode64_visual_check.asm (no PASS/FAIL, reviewed by eye
; only) -- W_LISTDEFS was manually reviewed running under the real
; rom/forth_boot.asm build instead. GET_DEF_SPAN and SCAN_DEFS, the
; logic W_LISTDEFS is actually built on, ARE fully checked below.
;
; TEST PAYLOAD: ": AA DUP + ; : BB DUP - ;" (25 bytes), hand-indexed:
;   span 0: offset 0,  length 12 (": AA DUP + ;")
;   span 1: offset 13, length 12 (": BB DUP - ;")
; (offset 12 is the single space between the two definitions)
;
; FOUR CHECKPOINTS (1-3 and 6):
;   1. SCAN_DEFS over the test payload finds exactly 2 definitions.
;   2. GET_DEF_SPAN(0) reports the correct offset/length.
;   3. GET_DEF_SPAN(1) reports the correct offset/length.
;   6. STORE_APPEND: each append is the text plus one CR (no separating space),
;      STORE_END advances by length + 1 each time, and an empty line appends nothing.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the failing
; checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    INCLUDE "include/rst_vectors.inc"
RST_38:
    ei
    ret
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

; ---- same literal values core/loadtext.asm and core/editor.asm use --
; see this file's own header on why they're redeclared, not INCLUDEd.
LOADTEXT_BUF     EQU $D000
LOADTEXT_MAX_LEN EQU 8192
STORE_START      EQU LOADTEXT_BUF
STORE_LIMIT      EQU STORE_START + LOADTEXT_MAX_LEN
STORE_END        EQU $8A74
EDIT_BUF         EQU $8860
EDIT_LEN         EQU $88E0
EDIT_CURSOR      EQU $88E1
EDIT_MAX_LEN     EQU 128

PRINT_UDEC16:
    ret                          ; stub -- see this file's own header
FORGET_PRINT_MSG:
    ret                          ; stub: STORE_APPEND's STORE FULL path is not exercised here
                                 ; (tools/edtest.py case 12 covers it on the product ROM)

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, TESTSRC
    ld   de, LOADTEXT_BUF
    ld   bc, TESTSRC_LEN
    ldir
    ld   hl, LOADTEXT_BUF
    ld   de, TESTSRC_LEN
    add  hl, de
    ld   (STORE_END), hl

; ---- checkpoint 1: SCAN_DEFS finds exactly 2 definitions ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call SCAN_DEFS
    ld   a, (DEF_COUNT)
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 2: GET_DEF_SPAN(0) == (offset 0, length 12) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   c, 0
    call GET_DEF_SPAN
    ld   a, d
    or   e
    jp   nz, FAIL_TEST            ; expected de == 0
    ld   a, h
    or   a
    jp   nz, FAIL_TEST
    ld   a, l
    cp   12
    jp   nz, FAIL_TEST

; ---- checkpoint 3: GET_DEF_SPAN(1) == (offset 13, length 12) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   c, 1
    call GET_DEF_SPAN
    ld   a, d
    or   a
    jp   nz, FAIL_TEST
    ld   a, e
    cp   13
    jp   nz, FAIL_TEST
    ld   a, h
    or   a
    jp   nz, FAIL_TEST
    ld   a, l
    cp   12
    jp   nz, FAIL_TEST

; ---- checkpoint 6: STORE_APPEND -- text + CR, no separator; an empty line appends nothing ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, LOADTEXT_BUF
    ld   (STORE_END), hl
    ld   hl, APPEND_X
    ld   b, 1
    call STORE_APPEND
    ld   hl, (STORE_END)
    ld   de, LOADTEXT_BUF + 2
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF)
    cp   "X"
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF + 1)
    cp   13
    jp   nz, FAIL_TEST

    ld   hl, APPEND_Y
    ld   b, 1
    call STORE_APPEND
    ld   hl, (STORE_END)
    ld   de, LOADTEXT_BUF + 4
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF + 2)
    cp   "Y"
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF + 3)
    cp   13
    jp   nz, FAIL_TEST

    ld   hl, APPEND_Y
    ld   b, 0
    call STORE_APPEND
    ld   hl, (STORE_END)
    ld   de, LOADTEXT_BUF + 4
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all six checkpoints passed
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

CHECKPOINT_NUM  EQU $8800
APPEND_X:       DB "X"
APPEND_Y:       DB "Y"
TESTSRC:        DB ": AA DUP + ; : BB DUP - ;"
TESTSRC_LEN     EQU $ - TESTSRC

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_EMIT
    INCLUDE "core/recall.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p64_rom0.bin", $0000, $4000
