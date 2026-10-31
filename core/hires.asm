; ============================================================================
; core/hires.asm -- HIRES and NORMAL: switch the screen mode
;
; Over kernel/graphics/graphics.asm's GFX_SET_MODE, which must be INCLUDEd (as must core/ts2068.asm).
; HIRES gives the same 256x192 bitmap as Normal mode with one attribute byte per 8-pixel bitmap byte (at
; the bitmap byte + $2000, the Second Display File) instead of one per 8x8 cell. GFX_WRITE_PIXEL and
; GFX_READ_PIXEL branch on GFX_MODE, so PLOT, LINE and CIRCLE follow the mode with no code here.
; The words take no argument, so there is no mode number to validate.
; While GFX_MODE is 1 the Second Display File shares RAM ($6000-$77FF) with FILL's shadow plane (see
; include/forth_layout.inc): the EXROM's FILL refuses any nonzero mode, and CLS (core/ts2068.asm) also
; clears the Second Display File to CURRENT_ATTR.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_HIRES_ASM
    DEFINE CORE_HIRES_ASM

; ============================================================================
; HIRES ( -- ) -- switch to High Resolution Graphics mode (GFX_MODE 1)
; ============================================================================
H_HIRES:
    DW   DICT_CHAIN_POINT
    DB   5, "H", "I", "R", "E", "S"
W_HIRES:
    ld   a, 1
    jp   GFX_SET_MODE

; ============================================================================
; NORMAL ( -- ) -- switch back to Normal mode (GFX_MODE 0)
; ============================================================================
H_NORMAL:
    DW   H_HIRES
    DB   6, "N", "O", "R", "M", "A", "L"
W_NORMAL:
    xor  a
    jp   GFX_SET_MODE


    ENDIF
