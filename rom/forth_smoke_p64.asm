; ============================================================================
; rom/forth_smoke_p64.asm — Phase 64 smoke ROM: LIST-DEFS / RECALL
; (core/recall.asm)
;
; Tests core/recall.asm's own logic in isolation from LOAD-TEXT's real
; tape wiring (already proven by rom/forth_smoke_p52.asm) and from
; core/editor.asm's live keyboard loop (an honest gap for the same
; reason rom/forth_smoke_p62.asm's own header names: EDITOR_LOOP_LIVE
; needs a live or injected keyboard, genuinely out of reach for an
; automated border-color smoke ROM). Deliberately does NOT INCLUDE
; core/loadtext.asm or core/editor.asm — LOADTEXT_BUF/LOADTEXT_MAX_LEN/
; WORKSPACE_END and EDIT_BUF/EDIT_LEN/EDIT_CURSOR/EDIT_MAX_LEN are
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
; SIX CHECKPOINTS:
;   1. SCAN_DEFS over the test payload finds exactly 2 definitions.
;   2. GET_DEF_SPAN(0) reports the correct offset/length.
;   3. GET_DEF_SPAN(1) reports the correct offset/length.
;   4. RECALL(0) copies the full 12-byte span into EDIT_BUF, sets
;      EDIT_LEN/EDIT_CURSOR to 12, and sets RECALL_PENDING.
;   5. RECALL(2) -- out of range (DEF_COUNT is 2) -- is a no-op: EDIT_LEN
;      is unchanged from a poisoned sentinel value.
;   6. WORKSPACE_APPEND: appending to an empty workspace adds no
;      separator; appending again DOES insert exactly one separating
;      space, and WORKSPACE_END advances correctly both times.
;
; Border goes GREEN (4) if all six pass; otherwise it shows the failing
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

; ---- same literal values core/loadtext.asm and core/editor.asm use --
; see this file's own header on why they're redeclared, not INCLUDEd.
LOADTEXT_BUF     EQU $D000
LOADTEXT_MAX_LEN EQU 8192
WORKSPACE_END    EQU $8A74
EDIT_BUF         EQU $8860
EDIT_LEN         EQU $88E0
EDIT_CURSOR      EQU $88E1
EDIT_MAX_LEN     EQU 128

PRINT_UDEC16:
    ret                          ; stub -- see this file's own header

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
    ld   (WORKSPACE_END), hl

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

; ---- checkpoint 4: RECALL(0) copies the span, sets EDIT_LEN/CURSOR/
; RECALL_PENDING ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (RECALL_PENDING), a
    ld   hl, 0
    call DPUSH_HL
    call W_RECALL
    ld   a, (EDIT_LEN)
    cp   12
    jp   nz, FAIL_TEST
    ld   a, (EDIT_CURSOR)
    cp   12
    jp   nz, FAIL_TEST
    ld   a, (RECALL_PENDING)
    cp   1
    jp   nz, FAIL_TEST
    ld   hl, EDIT_BUF
    ld   de, TESTSRC
    ld   b, 12
.cmploop:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  hl
    inc  de
    djnz .cmploop

; ---- checkpoint 5: RECALL(2) is out of range (DEF_COUNT is 2) --
; no-op, EDIT_LEN stays at the poisoned sentinel ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   a, 99
    ld   (EDIT_LEN), a
    ld   hl, 2
    call DPUSH_HL
    call W_RECALL
    ld   a, (EDIT_LEN)
    cp   99
    jp   nz, FAIL_TEST

; ---- checkpoint 6: WORKSPACE_APPEND -- no separator into an empty
; workspace, exactly one separator on the next append ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, LOADTEXT_BUF
    ld   (WORKSPACE_END), hl
    ld   hl, APPEND_X
    ld   b, 1
    call WORKSPACE_APPEND
    ld   hl, (WORKSPACE_END)
    ld   de, LOADTEXT_BUF + 1
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF)
    cp   "X"
    jp   nz, FAIL_TEST

    ld   hl, APPEND_Y
    ld   b, 1
    call WORKSPACE_APPEND
    ld   hl, (WORKSPACE_END)
    ld   de, LOADTEXT_BUF + 3
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF + 1)
    cp   " "
    jp   nz, FAIL_TEST
    ld   a, (LOADTEXT_BUF + 2)
    cp   "Y"
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
