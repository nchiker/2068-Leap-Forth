; ============================================================================
; core/color.asm -- INK, PAPER, BRIGHT, FLASH: the drawing colour
;
; Each word is a read-modify-write of its own bits of CURRENT_ATTR (core/ts2068.asm; must be INCLUDEd,
; and initialised at run time), so calling one never undoes another. Attribute layout: bits 0-2 ink,
; 3-5 paper, 6 bright, 7 flash (DEFAULT_ATTR $38 is paper 7, ink 0). The arguments are masked, not
; range-checked. The flashing cursor sets bit 7 of its own screen cell, not of CURRENT_ATTR.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_COLOR_ASM
    DEFINE CORE_COLOR_ASM

; ============================================================================
; INK ( n -- ) -- set the ink colour (low 3 bits of n) that PLOT, LINE and CIRCLE draw with
; ============================================================================
H_INK:
    DW   DICT_CHAIN_POINT
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
; PAPER ( n -- ) -- set the paper colour (low 3 bits of n)
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
; BRIGHT ( n -- ) -- bit 0 of n: 1 = high intensity, 0 = normal
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
; FLASH ( n -- ) -- bit 0 of n: 1 = flashing ink/paper, 0 = steady
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


    ENDIF
