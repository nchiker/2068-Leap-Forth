; ============================================================================
; core/udg.asm -- UDG: the address of a user-defined graphic's bitmap
;
; UDG_TABLE (include/sysvars.inc) holds 21 slots of 8 bytes for the character codes 144-164;
; kernel/graphics/graphics.asm's GFX_CHAR_TO_FONT_OFFSET routes those codes there, so EMIT of 144-164
; draws whatever bytes the program has stored in the slot. The slot number is not range-checked: an
; out-of-range n gives an address that nothing reads as a UDG.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_UDG_ASM
    DEFINE CORE_UDG_ASM

; ============================================================================
; UDG ( n -- addr ) -- addr = UDG_TABLE + n*8, the bitmap of slot n (0-20)
; ============================================================================
H_UDG:
    DW   DICT_CHAIN_POINT
    DB   3, "U","D","G"
W_UDG:
    rst RST_DPOP
    add  hl, hl              ; n*2
    add  hl, hl              ; n*4
    add  hl, hl              ; n*8
    ld   de, UDG_TABLE
    add  hl, de               ; UDG_TABLE + n*8
    rst RST_DPUSH
    ret


    ENDIF
