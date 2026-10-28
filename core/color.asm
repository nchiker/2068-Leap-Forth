; ============================================================================
; core/color.asm — Phase 15: INK and PAPER; Phase 60: BRIGHT; Phase 61: FLASH
;
; Builds on core/dict.asm, core/interp.asm, and core/ts2068.asm (all
; must be INCLUDEd first — this file's own first header chains through
; DICT_CHAIN_POINT; needs core/ts2068.asm specifically for
; CURRENT_ATTR, which that file's own header now documents as a
; required runtime initialization since this phase).
;
; WHAT THIS ADDS — the color half of docs/forth_tutorial.md's "More
; graphics and sound" gap:
;   INK   ( n -- )   sets the ink (foreground) color PLOT/LINE/CIRCLE
;             draw with from now on, 0-7 (only the low 3 bits of n are
;             used — no range checking, matching every earlier phase's
;             "no error recovery yet" scope note)
;   PAPER ( n -- )   sets the paper (background) color the same way
;   BRIGHT ( n -- )  1 = high-intensity INK/PAPER from now on, 0 =
;             normal intensity (only bit 0 of n is meaningful, same
;             "no range checking" scope as INK/PAPER). Added Phase 60,
;             well after INK/PAPER — CURRENT_ATTR's bit 6 always
;             existed and was always left untouched by INK/PAPER
;             (see layout note below), but nothing set it until now.
;   FLASH ( n -- )   1 = INK/PAPER flash (hardware-blinks) from now on,
;             0 = steady. Added Phase 61, same session as BRIGHT and
;             the same reasoning: bit 7 always existed, was always
;             left untouched by every word above, but nothing set it
;             from user code until now. The flashing CURSOR (Phase 33)
;             is unrelated — it sets bit 7 directly via
;             GFX_INVERT_ATTR on its own screen cell, not through
;             CURRENT_ATTR, and is unaffected by this word either way.
;
; ATTRIBUTE BYTE LAYOUT (standard Spectrum-family: bits 0-2 = ink,
; bits 3-5 = paper, bit 6 = bright, bit 7 = flash — core/ts2068.asm's
; own DEFAULT_ATTR, $38, is paper 7/ink 0 in this same layout, bright
; and flash both off). INK replaces bits 0-2 of CURRENT_ATTR, leaving
; every other bit untouched; PAPER replaces bits 3-5 the same way;
; BRIGHT replaces bit 6 the same way; FLASH replaces bit 7 the same
; way — each is a read-modify-write against whatever CURRENT_ATTR
; already holds, not a fresh byte, so calling one never undoes another.
; ============================================================================

    IFNDEF CORE_COLOR_ASM
    DEFINE CORE_COLOR_ASM

; ============================================================================
; INK ( n -- )
; ============================================================================
H_INK:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "I", "N", "K"
W_INK:
    rst RST_DPOP
    ld   a, l
    and  $07                    ; only the low 3 bits are meaningful
    ld   b, a
    ld   a, (CURRENT_ATTR)
    and  $F8                    ; clear the existing ink bits, keep
                                ; paper/bright/flash untouched
    or   b
    ld   (CURRENT_ATTR), a
    ret

; ============================================================================
; PAPER ( n -- )
; ============================================================================
H_PAPER:
    DW   H_INK
    DB   5, "P", "A", "P", "E", "R"
W_PAPER:
    rst RST_DPOP
    ld   a, l
    and  $07
    add  a, a
    add  a, a
    add  a, a                   ; a = n << 3 (paper occupies bits 3-5)
    ld   b, a
    ld   a, (CURRENT_ATTR)
    and  $C7                    ; clear the existing paper bits, keep
                                ; ink/bright/flash untouched
    or   b
    ld   (CURRENT_ATTR), a
    ret

; ============================================================================
; BRIGHT ( n -- )
; ============================================================================
H_BRIGHT:
    DW   H_PAPER
    DB   6, "B", "R", "I", "G", "H", "T"
W_BRIGHT:
    rst RST_DPOP
    ld   a, l
    and  $01                    ; only bit 0 is meaningful
    add  a, a
    add  a, a
    add  a, a
    add  a, a
    add  a, a
    add  a, a                   ; a = n << 6 (bright occupies bit 6)
    ld   b, a
    ld   a, (CURRENT_ATTR)
    and  $BF                    ; clear the existing bright bit, keep
                                ; ink/paper/flash untouched
    or   b
    ld   (CURRENT_ATTR), a
    ret

; ============================================================================
; FLASH ( n -- )
; ============================================================================
H_FLASH:
    DW   H_BRIGHT
    DB   5, "F", "L", "A", "S", "H"
W_FLASH:
    rst RST_DPOP
    ld   a, l
    and  $01                    ; only bit 0 is meaningful
    add  a, a
    add  a, a
    add  a, a
    add  a, a
    add  a, a
    add  a, a
    add  a, a                   ; a = n << 7 (flash occupies bit 7)
    ld   b, a
    ld   a, (CURRENT_ATTR)
    and  $7F                    ; clear the existing flash bit, keep
                                ; ink/paper/bright untouched
    or   b
    ld   (CURRENT_ATTR), a
    ret

DICT_LATEST_INIT_COLOR EQU H_FLASH   ; head of the dictionary once this
                                      ; file's own words are included

    ENDIF
