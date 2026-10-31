; ============================================================================
; core/shapes.asm -- FILL and CIRCLE, backed by the graphics EXROM
;
; Needs core/dict.asm, core/interp.asm, core/ts2068.asm (CURRENT_ATTR) and core/rectfill.asm
; (EXROM_CALL_SLOT) INCLUDEd first. The including ROM sets DICT_CHAIN_POINT (DEFL).
; Dictionary words destroy every register except IX/IY/SP.
;
; Each word stages its arguments in the GFX_FILL_* / GFX_CIRCLE_* cells (include/forth_layout.inc)
; and tail-jumps to EXROM_CALL_SLOT, whose RET returns to the inner interpreter. Without the
; EXROM, its magic/ABI check fails and they do nothing, as RECT does. A ROM that does not
; include core/rectfill.asm has neither word.
; ============================================================================

    IFNDEF CORE_SHAPES_ASM
    DEFINE CORE_SHAPES_ASM

; ============================================================================
; FILL ( x y -- ) -- flood-fill the region 4-connected to (x, y) through pixels of the seed
; pixel's value, with the current colour. x and y are signed cells; a seed outside 0-255 /
; 0-191 does nothing, and so does FILL in HIRES (EXROM slot 7, FILL_IMPL)
; ============================================================================
H_FILL:
    DW   DICT_CHAIN_POINT
    DB   4, "F", "I", "L", "L"
W_FILL:
    rst RST_DPOP            ; hl = y
    ld   (GFX_FILL_Y), hl
    rst RST_DPOP            ; hl = x
    ld   (GFX_FILL_X), hl
    ld   a, (CURRENT_ATTR)
    ld   (GFX_FILL_ATTR), a
    ld   hl, GRAPHICS_EXROM_BASE + (7 * 3)   ; slot 7 = FILL_IMPL
    jp   EXROM_CALL_SLOT       ; tail jump: its RET returns to our caller

; ============================================================================
; CIRCLE ( xc yc r -- ) -- draw the outline of the circle of radius r about (xc, yc) in the
; current colour. Signed 16-bit cells; off-screen points are clipped, r < 0 draws nothing,
; r = 0 draws the centre point (EXROM slot 8, CIRCLE_IMPL)
; ============================================================================
H_CIRCLE:
    DW   H_FILL
    DB   6, "C", "I", "R", "C", "L", "E"
W_CIRCLE:
    rst RST_DPOP            ; hl = r
    ld   (GFX_CIRCLE_R), hl
    rst RST_DPOP            ; hl = yc
    ld   (GFX_CIRCLE_YC), hl
    rst RST_DPOP            ; hl = xc
    ld   (GFX_CIRCLE_XC), hl
    ld   a, (CURRENT_ATTR)
    ld   (GFX_CIRCLE_ATTR), a
    ld   hl, GRAPHICS_EXROM_BASE + (8 * 3)   ; slot 8 = CIRCLE_IMPL
    jp   EXROM_CALL_SLOT       ; tail jump: its RET returns to our caller


    ENDIF
