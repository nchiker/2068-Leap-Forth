; ============================================================================
; rom/forth_smoke_p40.asm — Phase 40 smoke ROM: CHR, STR, UPPER, LOWER,
; LEFT, RIGHT, SEARCH, CODE
;
; FOURTEEN HAND-VERIFIED CASES, grouped into SIX checkpoint numbers
; (0,1,2,3,5,6 -- deliberately not more): the border only has 8 real
; colors, PASS_TEST already claims color 4 (matching every other smoke
; ROM in this project), and INTERPRET_UNKNOWN_WORD's own "bug in this
; file's own test source" signal claims color 7 -- leaving only 6
; values that can never be confused with either of those two, or with
; each other. An earlier draft of this file tried to number all
; fourteen cases 1-14 directly and hit exactly that trap: checkpoint 12
; would have shown the SAME green as a genuine pass (12 truncates to
; color 4 once the ULA's own 3-bit border port drops everything above
; bit 2) -- caught before ever running this ROM, not after a false
; pass, by re-deriving the actual hardware constraint instead of
; assuming more than 8 distinguishable outcomes exist. Related cases
; for the same word share one checkpoint number, run back to back,
; each one still able to independently fail into that same color.
;   Checkpoint 1 (CHR, CODE — the two simplest single-operation words):
;     CHR(65) = (addr,1), byte at addr == 'A'; CODE(addr,len) on
;     "HELLO WORLD" = 'H' = 72.
;   Checkpoint 2 (STR, all three hand-derived cases): STR(42) = "42";
;     STR(-5) = "-5" (the negative-sign path); STR(0) = "0" (the
;     "nothing to extract" special case).
;   Checkpoint 3 (UPPER, LOWER — mirror-image logic): UPPER("Hello!")
;     in place -> "HELLO!" (non-letter `!` left untouched); LOWER of
;     that same now-uppercased buffer -> "hello!".
;   Checkpoint 5 (LEFT, both cases — SKIPPING 4, PASS_TEST's own
;     color): LEFT(addr,11,5) on "HELLO WORLD" -> len'=5, same addr,
;     first 5 bytes read back as "HELLO"; LEFT(addr,11,20) -> len'=11
;     unchanged (n >= len clamps to the whole string).
;   Checkpoint 6 (RIGHT, both cases): RIGHT(addr,11,5) on
;     "HELLO WORLD" -> addr'=addr+6, len'=5, those 5 bytes read back as
;     "WORLD"; RIGHT(addr,11,20) -> addr'/len' unchanged, same clamp as
;     checkpoint 5's own second case, the other direction.
;   Checkpoint 0 (SEARCH, all three cases — reusing color 0 rather than
;     another skip-4-style renumbering, since this project already has
;     real precedent for 0 as an ordinary checkpoint color, e.g.
;     rom/forth_smoke_p30.asm): SEARCH("HELLO WORLD","WORLD") finds
;     pos=6, addr3=addr1+6, len3=11-6=5, flag=true; SEARCH("HELLO",
;     "XYZ") -- not found, addr3=addr1, len3=5 (both unchanged),
;     flag=false; SEARCH with needle longer than haystack -- rejected
;     before the search loop ever runs (the maxpos subtraction itself
;     borrows).
;
; Border goes GREEN (4) if every case passes; otherwise it shows
; whichever checkpoint NUMBER (not a 1:1 case index — see above) the
; failing case belongs to.
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

    ld   hl, DICT_LATEST_INIT_STRINGEXT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1 (CHR + CODE, the two simplest single-operation
; words): CHR(65) = (addr,1), byte == 'A' ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 65
    call DPUSH_HL
    call W_CHR
    call DPOP_HL              ; hl = len
    ld   de, 1
    call CHECK_HL_DE
    call DPOP_HL              ; hl = addr
    ld   a, (hl)
    cp   "A"
    jp   nz, FAIL_TEST

; ---- checkpoint 1 continued: CODE(addr,len) on "HELLO WORLD" = 'H' = 72 ----
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    call W_CODE
    ld   de, 72
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2 (STR, all three hand-derived cases): STR(42)="42" ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 42
    call DPUSH_HL
    call W_STR
    call CHECK_STRTOP_LIT
    DB   2, "4", "2"

; ---- checkpoint 2 continued: STR(-5) = "-5" ----
    ld   hl, -5
    call DPUSH_HL
    call W_STR
    call CHECK_STRTOP_LIT
    DB   2, "-", "5"

; ---- checkpoint 2 continued: STR(0) = "0" ----
    ld   hl, 0
    call DPUSH_HL
    call W_STR
    call CHECK_STRTOP_LIT
    DB   1, "0"

; ---- checkpoint 3 (UPPER + LOWER, mirror-image logic): both mutate IN
; PLACE, so the target must be real RAM, not a ROM-embedded literal --
; see this file's own CASE_BUF and core/stringext.asm's own header on
; why (a real, if narrow, gotcha this checkpoint's own first draft
; caught by hand: UPPER/LOWER run against HELLO_BANG directly, a
; ROM-resident DB string, silently no-op -- writes to ROM don't take
; effect on this hardware, and neither UPPER nor CHECK_STRTOP_LIT has
; any way to detect that from the caller's side). UPPER("Hello!") in
; place -> "HELLO!" ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, HELLO_BANG
    ld   de, CASE_BUF
    ld   bc, 6
    ldir                          ; copy the ROM literal into real RAM
                                  ; first
    ld   hl, CASE_BUF
    call DPUSH_HL
    ld   hl, 6
    call DPUSH_HL
    call W_UPPER
    call CHECK_STRTOP_LIT
    DB   6, "H", "E", "L", "L", "O", "!"

; ---- checkpoint 3 continued: LOWER("HELLO!") in place -> "hello!" ----
    ld   hl, CASE_BUF           ; already uppercased just above, same
    call DPUSH_HL                ; RAM buffer
    ld   hl, 6
    call DPUSH_HL
    call W_LOWER
    call CHECK_STRTOP_LIT
    DB   6, "h", "e", "l", "l", "o", "!"

; ---- checkpoint 5 (LEFT, both hand-derived cases -- SKIPPING 4:
; PASS_TEST's own border color, see this file's own header):
; LEFT(addr,11,5) on "HELLO WORLD" -> "HELLO" ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    ld   hl, 5
    call DPUSH_HL
    call W_LEFT
    call CHECK_STRTOP_LIT
    DB   5, "H", "E", "L", "L", "O"
    call W_DROP2

; ---- checkpoint 5 continued: LEFT(addr,11,20) -> unchanged (n >= len) ----
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    ld   hl, 20
    call DPUSH_HL
    call W_LEFT
    ld   de, 11
    call CHECK_TOP
    call W_DROP2

; ---- checkpoint 6 (RIGHT, both cases): RIGHT(addr,11,5) on
; "HELLO WORLD" -> "WORLD" ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    ld   hl, 5
    call DPUSH_HL
    call W_RIGHT
    call CHECK_STRTOP_LIT
    DB   5, "W", "O", "R", "L", "D"
    call W_DROP2

; ---- checkpoint 6 continued: RIGHT(addr,11,20) -> unchanged (n >= len) ----
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    ld   hl, 20
    call DPUSH_HL
    call W_RIGHT
    ld   de, 11
    call CHECK_TOP              ; len' unchanged -- peek only, still
                                 ; on the stack for the next check
    ld   de, HELLO_WORLD
    call CHECK_TOP2              ; addr' unchanged -- peek only
    call W_DROP2

; ---- checkpoint 0 (SEARCH, all three cases -- using border color 0
; rather than another skip-4-style renumbering, since this project has
; real precedent for 0 as an ordinary checkpoint color, e.g.
; rom/forth_smoke_p30.asm): SEARCH("HELLO WORLD","WORLD") finds pos=6 ----
    xor  a
    ld   (CHECKPOINT_NUM), a
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    ld   hl, WORLD_ONLY
    call DPUSH_HL
    ld   hl, 5
    call DPUSH_HL
    call W_SEARCH
    ld   de, -1
    call CHECK_TOP              ; flag = true
    call W_DROP
    ld   de, 5
    call CHECK_TOP              ; len3 = 5
    call W_DROP
    ld   de, HELLO_WORLD + 6
    call CHECK_TOP              ; addr3 = addr1 + 6
    call W_DROP

; ---- checkpoint 0 continued: SEARCH("HELLO","XYZ") -- not found ----
    ld   hl, HELLO_WORLD        ; first 5 bytes are "HELLO"
    call DPUSH_HL
    ld   hl, 5
    call DPUSH_HL
    ld   hl, XYZ_STR
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    call W_SEARCH
    ld   de, 0
    call CHECK_TOP               ; flag = false
    call W_DROP
    ld   de, 5
    call CHECK_TOP               ; len3 = original len1
    call W_DROP
    ld   de, HELLO_WORLD
    call CHECK_TOP               ; addr3 = original addr1
    call W_DROP

; ---- checkpoint 0 continued: SEARCH, needle longer than haystack ----
    ld   hl, XYZ_STR
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    ld   hl, HELLO_WORLD
    call DPUSH_HL
    ld   hl, 11
    call DPUSH_HL
    call W_SEARCH
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    ld   de, 3
    call CHECK_TOP
    call W_DROP
    ld   de, XYZ_STR
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ============================================================================
; W_DROP2 ( a b -- )  drops two cells -- this test harness's own
; convenience, not a dictionary word.
; ============================================================================
W_DROP2:
    call W_DROP
    call W_DROP
    ret

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it.
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_TOP2 ( DE = expected -- )  checks the SECOND cell from the top
; (one below the top) WITHOUT popping anything.
; ============================================================================
CHECK_TOP2:
    ld   l, (ix+2)
    ld   h, (ix+3)
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

; ============================================================================
; CHECK_STRTOP_LIT ( -- )  the data stack must have (addr len) on top
; (len on top, addr below); compares that string against a literal
; immediately following this CALL's own return address (DB length,
; then that many characters), then skips past it -- self-modifying-
; return-address trick, but read-only (never writes), safe.
; ============================================================================
CHECK_STRTOP_LIT:
    ex   (sp), hl              ; hl = return address (-> the DB literal)
    push bc
    push de
    ld   b, (ix+0)              ; b = actual len (top of stack)
    ld   c, (hl)                 ; c = expected len (first byte of literal)
    ld   a, b
    cp   c
    jp   nz, FAIL_TEST
    inc  hl                       ; hl = first char of the literal
    ld   e, (ix+2)                 ; de = actual addr (below len on stack)
    ld   d, (ix+3)
    ld   a, b
    or   a
    jr   z, .lendone                ; zero-length: nothing to compare
.cmploop:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  de
    inc  hl
    djnz .cmploop
.lendone:
    pop  de
    pop  bc
    ex   (sp), hl                    ; restore hl, set return address
                                     ; past the literal
    call W_DROP2                      ; consume the checked (addr len)
    ret

PASS_TEST:
    ld   a, 4                    ; green: all fourteen checkpoints passed
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
CASE_BUF       EQU $8810   ; 6 bytes: real RAM copy for the UPPER/LOWER
                            ; in-place test -- see checkpoint 3's own
                            ; comment on why a ROM literal won't do

HELLO_BANG:   DB "Hello!"
HELLO_WORLD:  DB "HELLO WORLD"
WORLD_ONLY:   DB "WORLD"
XYZ_STR:      DB "XYZ"

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/string.asm"
DICT_CHAIN_POINT DEFL H_VAL
    INCLUDE "core/stringext.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p40_rom0.bin", $0000, $4000
