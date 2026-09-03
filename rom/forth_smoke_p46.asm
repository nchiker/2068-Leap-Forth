; ============================================================================
; rom/forth_smoke_p46.asm — Phase 46 smoke ROM: ROT, 2DUP, 2DROP, ?DUP,
; PICK (core/stackops.asm); AND, OR, XOR, INVERT (core/logic.asm);
; CR, SPACE, SPACES (core/outwords.asm); ' TICK (core/tick.asm)
;
; NINE assertions grouped under SIX checkpoint NUMBERS (0,1,2,3,5,6 --
; skipping 4 and 7 on purpose): PORT_ULA's border only decodes 3 bits,
; and this project has hit the resulting collision before (Phase 40) —
; 8 or 9 raw checkpoint numbers would alias to colors 0/1, and 4/7 are
; already this project's own reserved PASS/"bug in test source"
; signals. Grouping related assertions under one shared number, the
; same fix Phase 40 used, avoids all of that:
;   0.  ROT: (1 2 3) -> top=1, then 3, then 2 (bottom).
;       2DUP: (5 6) -> top-down 6,5,6,5.
;   1.  2DROP: (7 8 9 10) 2DROP -> top-down 8,7 remain.
;       ?DUP with a nonzero top: duplicates (5 5 stays, extra 5 added).
;       ?DUP with a zero top: stack unchanged (still just one 0).
;   2.  PICK: (10 20 30) 0 PICK = 30 (DUP), (10 20 30) 2 PICK = 10.
;   3.  AND/OR/XOR: exact bit patterns, not just truthy/falsy.
;       INVERT: $0F0F -> $F0F0 exactly (bitwise, not boolean).
;   5.  CR/SPACE/SPACES: draws real pixels at the expected screen
;       positions (SPACE at the pre-CR column, then CR moves to column
;       0 of the next row, then 3 SPACES draw 3 blank cells before the
;       next real character) -- readback via GFX_READ_PIXEL, matching
;       Phase 10's own established verification strategy for EMIT/.
;       rather than trusting PRINT_ROW/PRINT_COL alone.
;   6.  ' (TICK): looks up a real, freshly-compiled word (`: FORTYTWO
;       42 ; ' FORTYTWO EXECUTE`) and confirms EXECUTE via that xt
;       produces 42; then CATCHes `' NOSUCHWORD` and confirms it throws
;       exactly -13 (ANS Forth's own "undefined word" code), proving
;       TICK's own error path reaches THROW correctly, not just that
;       it doesn't crash.
;
; Border goes GREEN (4) if everything passes; otherwise it shows the
; failing checkpoint's number (0,1,2,3,5, or 6).
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

    ld   hl, DICT_LATEST_INIT_TICK
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 0a: ROT ----
    ld   a, 0
    ld   (CHECKPOINT_NUM), a
    ld   hl, 1
    call DPUSH_HL
    ld   hl, 2
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    call W_ROT
    ld   de, 1
    call CHECK_TOP
    call W_DROP
    ld   de, 3
    call CHECK_TOP
    call W_DROP
    ld   de, 2
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 0b: 2DUP ----
    ld   a, 0
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    ld   hl, 6
    call DPUSH_HL
    call W_2DUP
    ld   de, 6
    call CHECK_TOP
    call W_DROP
    ld   de, 5
    call CHECK_TOP
    call W_DROP
    ld   de, 6
    call CHECK_TOP
    call W_DROP
    ld   de, 5
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 1a: 2DROP ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 7
    call DPUSH_HL
    ld   hl, 8
    call DPUSH_HL
    ld   hl, 9
    call DPUSH_HL
    ld   hl, 10
    call DPUSH_HL
    call W_2DROP
    ld   de, 8
    call CHECK_TOP
    call W_DROP
    ld   de, 7
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 1b: ?DUP ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    call W_QDUP
    ld   de, 5
    call CHECK_TOP
    call W_DROP
    ld   de, 5
    call CHECK_TOP
    call W_DROP
    ld   hl, 0
    call DPUSH_HL
    call W_QDUP
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    push ix                    ; confirm ?DUP(0) pushed nothing extra
    pop  hl                     ; -- IX must be back at DSTACK_TOP
    ld   de, DSTACK_TOP
    call CHECK_HL_DE

; ---- checkpoint 2: PICK ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 10
    call DPUSH_HL
    ld   hl, 20
    call DPUSH_HL
    ld   hl, 30
    call DPUSH_HL
    ld   hl, 0
    call DPUSH_HL
    call W_PICK                 ; 0 PICK = DUP
    ld   de, 30
    call CHECK_TOP
    call W_DROP
    ld   hl, 2
    call DPUSH_HL
    call W_PICK                  ; 2 PICK -- stack is (10 20 30), so
                                   ; depth 2 from top is 10
    ld   de, 10
    call CHECK_TOP
    call W_DROP
    call W_DROP
    call W_DROP
    call W_DROP

; ---- checkpoint 3a: AND / OR / XOR, exact bit patterns ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, $0FF0
    call DPUSH_HL
    ld   hl, $FF00
    call DPUSH_HL
    call W_AND
    ld   de, $0F00
    call CHECK_TOP
    call W_DROP
    ld   hl, $0FF0
    call DPUSH_HL
    ld   hl, $FF00
    call DPUSH_HL
    call W_OR
    ld   de, $FFF0
    call CHECK_TOP
    call W_DROP
    ld   hl, $0FF0
    call DPUSH_HL
    ld   hl, $FF00
    call DPUSH_HL
    call W_XOR
    ld   de, $F0F0
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3b: INVERT ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, $0F0F
    call DPUSH_HL
    call W_INVERT
    ld   de, $F0F0
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 5: CR / SPACE / SPACES draw real pixels ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    call W_SPACE                 ; column 0 -> column 1, cell (0,0)
                                   ; stays blank (a space draws nothing)
    ld   hl, "X"
    call DPUSH_HL
    call W_EMIT                   ; column 1 -> a real glyph at (1,0)
    call W_CR                     ; row 0 -> row 1, column back to 0
    ld   hl, 3
    call DPUSH_HL
    call W_SPACES                 ; columns 0-2 stay blank on row 1
    ld   hl, "Y"
    call DPUSH_HL
    call W_EMIT                    ; column 3 -> a real glyph at (3,1)
    ld   b, 0                       ; cell (0,0): pixel column 0-7
    ld   c, 0
    call ANY_PIXEL_SET_IN_CELL
    jp   nz, FAIL_TEST               ; must be BLANK (SPACE, not EMIT)
    ld   b, 8                        ; cell (1,0): the "X"
    ld   c, 0
    call ANY_PIXEL_SET_IN_CELL
    jp   z, FAIL_TEST
    ld   b, 0                        ; row 1 starts at pixel row 8;
    ld   c, 8                        ; cell (0,1): first SPACES cell
    call ANY_PIXEL_SET_IN_CELL
    jp   nz, FAIL_TEST
    ld   b, 24                       ; cell (3,1): the "Y"
    ld   c, 8
    call ANY_PIXEL_SET_IN_CELL
    jp   z, FAIL_TEST

; ---- checkpoint 6: ' (TICK) -- found and not-found paths ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_DEFINE
    ld   de, SRC_DEFINE_LEN
    call INTERPRET_RUN
    ld   hl, SRC_TICK_OK
    ld   de, SRC_TICK_OK_LEN
    call INTERPRET_RUN
    ld   de, 42
    call CHECK_TOP
    call W_DROP
    ld   hl, TEST_XT_TICK_BAD
    call DPUSH_HL
    call W_CATCH
    ld   de, -13
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ============================================================================
; TEST_XT_TICK_BAD -- a raw "xt" (see core/throwcatch.asm's own header
; for why any code address ending in `ret` qualifies) that parses a
; deliberately undefined word via ' and lets its own -13 THROW escape
; up to the CATCH in checkpoint 9 above.
; ============================================================================
TEST_XT_TICK_BAD:
    ld   hl, SRC_TICK_BAD
    ld   de, SRC_TICK_BAD_LEN
    call INTERPRET_RUN
    ret

; ============================================================================
; ANY_PIXEL_SET_IN_CELL ( B = pixel x of cell's left column, C = pixel
; y of cell's top row -- Z flag set if EVERY pixel in the 8x8 cell is
; clear, reset if at least one is set )
;
; GFX_READ_PIXEL's own header states it destroys AF, BC, DE, HL --
; this loop uses D/E as its own column/row counters, so BOTH bc and de
; are pushed around every call, not just bc (an earlier draft caught
; here, before ever running it, missed the DE clobber and would have
; corrupted its own loop bounds after the very first pixel read).
; ============================================================================
ANY_PIXEL_SET_IN_CELL:
    push bc
    push de
    ld   e, 8
.rowloop:
    push bc
    push de
    ld   d, 8
.colloop:
    push bc
    push de
    call GFX_READ_PIXEL
    or   a
    pop  de
    pop  bc
    jr   nz, .found
    inc  b
    dec  d
    jr   nz, .colloop
    pop  de
    pop  bc
    inc  c
    dec  e
    jr   nz, .rowloop
    pop  de
    pop  bc
    xor  a                    ; nothing found: Z set
    ret
.found:
    pop  de
    pop  bc
    pop  de
    pop  bc
    or   1                     ; NZ
    ret

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it (the caller drops separately once done).
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_HL_DE ( HL DE -- )  halts with the border showing the current
; checkpoint number if HL != DE.
; ============================================================================
CHECK_HL_DE:
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
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

; ============================================================================
; RUNTIME_ERROR_HOOK -- required by THROW_CATCH_ENABLED (core/interp.asm)
; for an UNCAUGHT throw. Nothing in this test should ever reach this:
; checkpoint 9's own -13 throw is always wrapped in an active CATCH.
; Reaching it at all means something escaped a CATCH that should have
; absorbed it -- a real bug in the words under test, not this file's
; own harness -- so it uses the same white "something's wrong" signal
; INTERPRET_UNKNOWN_WORD does, not a numbered checkpoint.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   a, 7
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

SRC_DEFINE: DB ": FORTYTWO 42 ; "
SRC_DEFINE_LEN EQU $ - SRC_DEFINE

SRC_TICK_OK: DB "' FORTYTWO EXECUTE "
SRC_TICK_OK_LEN EQU $ - SRC_TICK_OK

SRC_TICK_BAD: DB "' NOSUCHWORD "
SRC_TICK_BAD_LEN EQU $ - SRC_TICK_BAD

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    DEFINE THROW_CATCH_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/execute.asm"
DICT_CHAIN_POINT DEFL H_EXECUTE
    INCLUDE "core/throwcatch.asm"
DICT_CHAIN_POINT DEFL H_CATCH
    INCLUDE "core/stackops.asm"
DICT_CHAIN_POINT DEFL H_PICK
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/outwords.asm"
DICT_CHAIN_POINT DEFL H_SPACES
    INCLUDE "core/tick.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p46_rom0.bin", $0000, $4000
