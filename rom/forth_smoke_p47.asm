; ============================================================================
; rom/forth_smoke_p47.asm — Phase 47 smoke ROM: LPRINT, LLIST
;
; UNVERIFIED IN THIS EMULATION ENVIRONMENT, stated plainly (see
; core/printer.asm's own header for the full writeup): Fuse 1.9.1's
; CLI has no printer-emulation flag, so nothing here can confirm real
; printed dots. What CAN be confirmed, and is: LPRINT's text-to-raster
; RENDERING is correct (checked by direct memory comparison against
; the same font lookup the renderer itself uses, not a hardcoded
; guess at glyph shapes), multi-line wrapping picks the right
; characters for line 2, and both words run to completion without
; hanging (Fuse's own disabled-printer read handler returns $FF, whose
; bit 0 is already 1 — "ready" — so the protocol's own poll loop
; succeeds immediately rather than blocking forever).
;
; FOUR CHECKPOINTS:
;   1. LPRINT("AB", 2): PRINT_LINE_BUF's column 0 (all 8 rows) must
;      exactly match GFX_CHAR_TO_FONT_OFFSET('A')'s own glyph bytes,
;      fetched independently by this test, not assumed.
;   2. Same call: PRINT_LINE_BUF's column 2 (past "AB"'s own 2
;      characters, into the padding) must exactly match
;      GFX_CHAR_TO_FONT_OFFSET(' ')'s own glyph bytes -- proving
;      padding uses the real space glyph, not silently reading
;      garbage.
;   3. LPRINT of a 40-character string ("0123456789" x4) wraps to two
;      printed lines; after the whole call returns, PRINT_LINE_BUF
;      (now holding the LAST line rendered) must show the character at
;      source index 32 ('2', since 32 mod 10 = 2) in column 0 -- proof
;      the second chunk started at the right offset, not a guess that
;      wrapping merely "didn't crash".
;   4. LLIST, with exactly one real user word compiled first, must
;      return normally (reach the next instruction) without hanging --
;      proving the RAM/ROM boundary check in core/printer.asm's own
;      W_LLIST terminates correctly rather than running off into the
;      ROM-resident chain or looping forever.
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

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_PRINTER
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoints 1-2: LPRINT("AB",2) renders correctly ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_AB
    call DPUSH_HL
    ld   hl, 2
    call DPUSH_HL
    call W_LPRINT

    ld   a, "A"
    call GFX_CHAR_TO_FONT_OFFSET
    ld   (EXPECT_PTR), hl
    ld   hl, PRINT_LINE_BUF          ; column 0
    ld   (ACTUAL_PTR), hl
    call COMPARE_8_STRIDE32
    jp   nz, FAIL_TEST

    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   a, " "
    call GFX_CHAR_TO_FONT_OFFSET
    ld   (EXPECT_PTR), hl
    ld   hl, PRINT_LINE_BUF + 2       ; column 2 (past "AB")
    ld   (ACTUAL_PTR), hl
    call COMPARE_8_STRIDE32
    jp   nz, FAIL_TEST

; ---- checkpoint 5: 40-char LPRINT wraps, second chunk starts right ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_40
    call DPUSH_HL
    ld   hl, 40
    call DPUSH_HL
    call W_LPRINT
    ld   a, "2"                        ; index 32 of "0123..9" x4
    call GFX_CHAR_TO_FONT_OFFSET
    ld   (EXPECT_PTR), hl
    ld   hl, PRINT_LINE_BUF             ; column 0 of the LAST rendered
                                          ; line (buffer is reused/
                                          ; overwritten per line)
    ld   (ACTUAL_PTR), hl
    call COMPARE_8_STRIDE32
    jp   nz, FAIL_TEST

; ---- checkpoint 6: LLIST terminates cleanly with one real user word ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_DEFINE
    ld   de, SRC_DEFINE_LEN
    call INTERPRET_RUN
    ld   hl, (LATEST)
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de
    jp   c, FAIL_TEST                  ; LATEST should now be a RAM
                                         ; address -- bug in this
                                         ; test's own source if not
    call W_LLIST
    ; reaching here at all (not hung) is most of the proof; also
    ; confirm the stack is exactly as clean as before the call --
    ; W_LLIST takes no arguments and returns none
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE

    jp   PASS_TEST

; ============================================================================
; COMPARE_8_STRIDE32 ( (EXPECT_PTR) = 8 contiguous bytes,
;                       (ACTUAL_PTR) = 8 bytes at stride 32 -- )
; Z flag set if all 8 match, reset otherwise.
; ============================================================================
COMPARE_8_STRIDE32:
    ld   hl, (EXPECT_PTR)
    ld   de, (ACTUAL_PTR)
    ld   b, 8
.loop:
    ld   a, (de)
    cp   (hl)
    ret  nz
    inc  hl
    push hl
    ex   de, hl
    ld   de, 32
    add  hl, de                 ; advance the ACTUAL pointer by the
    ex   de, hl                  ; 32-byte row stride (EXPECT stays
    pop  hl                       ; contiguous, already advanced above)
    djnz .loop
    xor  a
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

CHECKPOINT_NUM EQU $8800
EXPECT_PTR     EQU $8802
ACTUAL_PTR     EQU $8804

SRC_AB: DB "AB"

SRC_40: DB "0123456789012345678901234567890123456789"

SRC_DEFINE: DB ": FOO 1 ; "
SRC_DEFINE_LEN EQU $ - SRC_DEFINE

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/printer.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p47_rom0.bin", $0000, $4000
