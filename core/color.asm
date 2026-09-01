; ============================================================================
; core/color.asm — Phase 15: INK and PAPER
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
;
; ATTRIBUTE BYTE LAYOUT (standard Spectrum-family: bits 0-2 = ink,
; bits 3-5 = paper, bit 6 = bright, bit 7 = flash — core/ts2068.asm's
; own DEFAULT_ATTR, $38, is paper 7/ink 0 in this same layout). INK
; replaces bits 0-2 of CURRENT_ATTR, leaving every other bit (including
; paper) untouched; PAPER replaces bits 3-5, leaving ink (and
; bright/flash) untouched — each is a read-modify-write against
; whatever CURRENT_ATTR already holds, not a fresh byte, so calling one
; never undoes the other. Neither touches bright or flash — this
; project has no words for those yet.
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
    call DPOP_HL
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
    call DPOP_HL
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

DICT_LATEST_INIT_COLOR EQU H_PAPER   ; head of the dictionary once this
                                      ; file's own words are included

    ENDIF
