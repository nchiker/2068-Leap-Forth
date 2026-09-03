; ============================================================================
; rom/forth_smoke_p49.asm — Phase 49 smoke ROM: 1+/1-/NEGATE/MAX/MIN
; (core/arith.asm), VLIST (core/vlist.asm), EXIT/J (core/loopext.asm)
;
; SIX checkpoint NUMBERS (0,1,2,3,5,6 -- skipping 4 and 7 on purpose,
; matching rom/forth_smoke_p46.asm's own precedent): PORT_ULA's border
; only decodes 3 bits, 4 is this project's own reserved PASS color, and
; 7 is the reserved "bug in this file's own test source" signal, so 8
; raw checkpoints would collide. Related assertions are grouped under
; one shared number the same way Phase 46 already did:
;   0.  1+ / 1-: a few values including the $7FFF/$8000 wrap boundary.
;   1.  NEGATE: positive, negative, zero, and the $8000 edge case (see
;       core/arith.asm's own header on why that one stays $8000).
;   2.  MAX / MIN: signed comparisons, including mixed-sign pairs where
;       an UNSIGNED compare would give the wrong answer ($7FFF vs
;       $8000 -- unsigned that's 32767 < 32768, signed it's 32767 >
;       -32768, exactly the case this checkpoint exists to catch).
;   3.  VLIST: defines two fresh words of deliberately different name
;       lengths, calls VLIST, and reads back real pixels to confirm
;       the dictionary walk prints the newest entry FIRST with the
;       LENFLAGS-derived length actually bounding each name (not
;       running into the next one) -- see core/vlist.asm's own header.
;       Also confirms VLIST leaves the data stack exactly where it
;       found it (IX unchanged).
;   5.  EXIT: (a) mid-definition at top level -- code after EXIT never
;       runs; (b) firing from inside an open DO...LOOP -- the loop
;       stops early AND control returns correctly to the caller (see
;       core/loopext.asm's own header on why a bare RET would
;       otherwise misread the loop's own index off the hardware stack).
;   6.  J: a real 2-deep nested DO...LOOP with DELIBERATELY UNEQUAL
;       bounds (2 outer x 3 inner) -- see core/loopext.asm's own header
;       on why equal bounds would let a J-returns-I bug hide behind a
;       coincidentally-correct sum.
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

    ld   hl, DICT_LATEST_INIT_VLIST
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a   ; core/doloop.asm's own LEAVE bookkeeping --
                             ; must start at 0
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 0: 1+ / 1- ----
    ld   a, 0
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    call W_ONEPLUS
    ld   de, 6
    call CHECK_TOP
    call W_DROP

    ld   hl, 5
    call DPUSH_HL
    call W_ONEMINUS
    ld   de, 4
    call CHECK_TOP
    call W_DROP

    ld   hl, $7FFF          ; 1+ across the signed-wrap boundary
    call DPUSH_HL
    call W_ONEPLUS
    ld   de, $8000
    call CHECK_TOP
    call W_DROP

    ld   hl, $8000           ; 1- back across the same boundary
    call DPUSH_HL
    call W_ONEMINUS
    ld   de, $7FFF
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 1: NEGATE ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    call W_NEGATE
    ld   de, -5
    call CHECK_TOP
    call W_DROP

    ld   hl, -5
    call DPUSH_HL
    call W_NEGATE
    ld   de, 5
    call CHECK_TOP
    call W_DROP

    ld   hl, 0
    call DPUSH_HL
    call W_NEGATE
    ld   de, 0
    call CHECK_TOP
    call W_DROP

    ld   hl, $8000            ; -32768 -- two's complement wrap, see
    call DPUSH_HL              ; core/arith.asm's own header
    call W_NEGATE
    ld   de, $8000
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: MAX / MIN ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    call W_MAX
    ld   de, 5
    call CHECK_TOP
    call W_DROP

    ld   hl, 3
    call DPUSH_HL
    ld   hl, 5
    call DPUSH_HL
    call W_MIN
    ld   de, 3
    call CHECK_TOP
    call W_DROP

    ld   hl, -1               ; mixed sign -- MAX(-1,3) = 3
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    call W_MAX
    ld   de, 3
    call CHECK_TOP
    call W_DROP

    ld   hl, -5                ; both negative -- MAX(-5,-1) = -1
    call DPUSH_HL
    ld   hl, -1
    call DPUSH_HL
    call W_MAX
    ld   de, -1
    call CHECK_TOP
    call W_DROP

    ld   hl, $7FFF              ; the real reason this is signed, not
    call DPUSH_HL                ; unsigned: unsigned, $7FFF < $8000;
    ld   hl, $8000                ; signed, $7FFF (32767) > $8000
    call DPUSH_HL                  ; (-32768). MIN must pick $8000.
    call W_MIN
    ld   de, $8000
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: VLIST -- dictionary walk + name-length bounding ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_VLIST_DEFS
    ld   de, SRC_VLIST_DEFS_LEN
    call INTERPRET_RUN         ; defines Q (len 1) then WWWW (len 4) --
                                ; WWWW becomes LATEST, so VLIST prints
                                ; "WWWW " first, then "Q " -- see this
                                ; file's own header

    push ix                     ; remember IX before VLIST -- checked
    pop  de                     ; against IX after, below
    ld   (VLIST_IX_BEFORE), de

    call W_VLIST

    push ix
    pop  hl
    ld   de, (VLIST_IX_BEFORE)
    call CHECK_HL_DE             ; VLIST must leave the data stack
                                  ; exactly where it found it

    ld   b, 0                    ; cell (0,0): "W" of "WWWW"
    ld   c, 0
    call ANY_PIXEL_SET_IN_CELL
    jp   z, FAIL_TEST
    ld   b, 24                    ; cell (3,0): the 4th "W"
    ld   c, 0
    call ANY_PIXEL_SET_IN_CELL
    jp   z, FAIL_TEST
    ld   b, 32                     ; cell (4,0): the SPACE separator
    ld   c, 0                       ; after "WWWW" -- must be blank
    call ANY_PIXEL_SET_IN_CELL
    jp   nz, FAIL_TEST
    ld   b, 40                      ; cell (5,0): "Q" -- proves WWWW's
    ld   c, 0                        ; own length (4) didn't overrun
    call ANY_PIXEL_SET_IN_CELL       ; into what should be Q's slot
    jp   z, FAIL_TEST
    ld   b, 48                       ; cell (6,0): the SPACE separator
    ld   c, 0                         ; after "Q" -- must be blank
    call ANY_PIXEL_SET_IN_CELL
    jp   nz, FAIL_TEST

; ---- checkpoint 5: EXIT -- top-level, then from inside a loop ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a

    push ix
    pop  de
    ld   (VLIST_IX_BEFORE), de    ; reused scratch cell -- IX depth
                                    ; check for TEXIT1 below

    ld   hl, SRC_TEXIT1
    ld   de, SRC_TEXIT1_LEN
    call INTERPRET_RUN             ; : TEXIT1 1 EXIT 2 ; TEXIT1
    ld   de, 1
    call CHECK_TOP                  ; only the 1 -- the 2 after EXIT
                                     ; must never have been pushed
    call W_DROP

    push ix
    pop  hl
    ld   de, (VLIST_IX_BEFORE)
    call CHECK_HL_DE                 ; exactly one cell was pushed and
                                      ; popped -- no leftover garbage

    ld   hl, SRC_TEXIT2
    ld   de, SRC_TEXIT2_LEN
    call INTERPRET_RUN                ; see this file's own header --
                                       ; expected result 3 (I=0,1,2 each
                                       ; add 1 to the accumulator; I=3
                                       ; triggers EXIT before adding,
                                       ; and 999 never gets pushed)
    ld   de, 3
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 6: J -- 2-deep nested loop, deliberately unequal
;      bounds (2 outer x 3 inner) -- see this file's own header ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_TESTJ
    ld   de, SRC_TESTJ_LEN
    call INTERPRET_RUN
    ld   de, 15
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ============================================================================
; ANY_PIXEL_SET_IN_CELL ( B = pixel x of cell's left column, C = pixel
; y of cell's top row -- Z flag set if EVERY pixel in the 8x8 cell is
; clear, reset if at least one is set ) -- copied verbatim from
; rom/forth_smoke_p46.asm's own already-proven version, including its
; own note on why BOTH bc and de must be saved around every
; GFX_READ_PIXEL call, not just bc.
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
    xor  a
    ret
.found:
    pop  de
    pop  bc
    pop  de
    pop  bc
    or   1
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

CHECKPOINT_NUM   EQU $8900
VLIST_IX_BEFORE  EQU $8902   ; 2 bytes: scratch, reused across checkpoints

; WWWW becomes LATEST (defined second) -- VLIST prints it FIRST.
SRC_VLIST_DEFS: DB ": Q 1 ; : WWWW 2 ; "
SRC_VLIST_DEFS_LEN EQU $ - SRC_VLIST_DEFS

SRC_TEXIT1: DB ": TEXIT1 1 EXIT 2 ; TEXIT1 "
SRC_TEXIT1_LEN EQU $ - SRC_TEXIT1

; 0 (acc) ; DO I=0..4 START=0 LIMIT=5 ; I=3 -> EXIT with acc=3 on the
; stack, before "1 +" runs and before the trailing 999 is ever reached.
SRC_TEXIT2: DB ": TEXIT2 0 5 0 DO I 3 = IF EXIT THEN 1 + LOOP 999 ; TEXIT2 "
SRC_TEXIT2_LEN EQU $ - SRC_TEXIT2

; Outer loop ("2 0 DO") is J's own range -- 0,1 (2 passes). Inner loop
; ("3 0 DO") is I's own range -- 0,1,2 (3 passes per outer pass).
; Accumulates 2*I+J each of the 6 (outer,inner) combinations:
;   J=0: I=0,1,2 -> 0,2,4  (sum 6)
;   J=1: I=0,1,2 -> 1,3,5  (sum 9)
; Hand-enumerated expected total: 15 -- cross-checked against two
; simpler standalone probes before trusting it (sum of J alone over
; all 6 passes = 3; sum of I alone over all 6 passes = 6; combined
; total = 2*6 + 3 = 15). An EARLIER draft of this comment mis-derived
; 12 by swapping which loop was the 2-pass one and which was the
; 3-pass one -- a bug in this file's own hand math, not in J or the
; nested-loop implementation, caught by exactly those two standalone
; probes before this ROM was ever called done.
SRC_TESTJ: DB ": TESTJ 0 2 0 DO 3 0 DO I DUP + J + + LOOP LOOP ; TESTJ "
SRC_TESTJ_LEN EQU $ - SRC_TESTJ

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/outwords.asm"
DICT_CHAIN_POINT DEFL H_SPACES
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/loopext.asm"
DICT_CHAIN_POINT DEFL H_J
    INCLUDE "core/arith.asm"
DICT_CHAIN_POINT DEFL H_MIN
    INCLUDE "core/vlist.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p49_rom0.bin", $0000, $4000
