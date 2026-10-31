; ============================================================================
; core/ts2068.asm -- PLOT, LINE, BORDER, CLS: TS2068 screen words
;
; Thin wrappers over kernel/graphics/graphics.asm (which must be INCLUDEd), chained onto core/control.asm's
; H_UNTIL. Each argument cell contributes only its low byte (x 0-255, y 0-191, colour 0-7); there is no
; range checking. PLOT, LINE and the shapes draw with CURRENT_ATTR, which core/color.asm's INK, PAPER,
; BRIGHT and FLASH modify; the ROM must initialise it to DEFAULT_ATTR at cold start. CURRENT_ATTR's
; address comes from include/forth_layout.inc; check a new scratch byte there against the other users.
; Every word may destroy all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_TS2068_ASM
    DEFINE CORE_TS2068_ASM

DEFAULT_ATTR EQU $38   ; paper 7 (white), ink 0 (black), no bright/flash; CURRENT_ATTR's start value

; ============================================================================
; PLOT ( x y -- ) -- set the pixel (GFX_WRITE_PIXEL); nothing if x or y is above 255
; ============================================================================
H_PLOT:
    DW   H_UNTIL
    DB   4, "P", "L", "O", "T"
W_PLOT:
    rst RST_DPOP          ; hl = y
    ld   c, l
    ld   a, h
    rst RST_DPOP          ; hl = x (A kept)
    or   h
    ret  nz               ; x or y outside 0-255: nothing (y 192-255: GFX_WRITE_PIXEL)
    ld   b, l
    ld   a, (CURRENT_ATTR)
    ld   d, 0              ; OVER=0: set the pixel, don't XOR-toggle it
    jp   GFX_WRITE_PIXEL

; ============================================================================
; LINE ( x1 y1 x2 y2 -- ) -- draw a line (GFX_LINE, which reads its arguments from the GFX_LINE_* bytes)
; ============================================================================
H_LINE:
    DW   H_PLOT
    DB   4, "L", "I", "N", "E"
W_LINE:
    rst RST_DPOP          ; hl = y2
    ld   a, l
    ld   (GFX_LINE_Y1), a
    rst RST_DPOP          ; hl = x2
    ld   a, l
    ld   (GFX_LINE_X1), a
    rst RST_DPOP          ; hl = y1
    ld   a, l
    ld   (GFX_LINE_Y0), a
    rst RST_DPOP          ; hl = x1
    ld   a, l
    ld   (GFX_LINE_X0), a
    ld   a, (CURRENT_ATTR)
    ld   (GFX_LINE_ATTR), a
    xor  a
    ld   (GFX_LINE_OVER), a
    jp   GFX_LINE

; ============================================================================
; BORDER ( color -- ) -- set the border colour (GFX_SET_BORDER)
; ============================================================================
H_BORDER:
    DW   H_LINE
    DB   6, "B", "O", "R", "D", "E", "R"
W_BORDER:
    rst RST_DPOP
    ld   a, l
    jp   GFX_SET_BORDER


; ============================================================================
; CLS ( -- ) -- clear the screen, repaint the attributes with CURRENT_ATTR, home the print position
; GFX_CLS alone resets the attributes to ATTR_DEFAULT; CLS keeps the chosen colours, as BASIC's CLS does.
; ============================================================================
H_CLS:
    DW   H_BORDER
    DB   3, "C", "L", "S"
W_CLS:
    call GFX_CLS
    ld   a, (CURRENT_ATTR)
    call GFX_PAINT_ATTR

    ; In HIRES (GFX_MODE 1) the per-scanline attributes live in the Second Display File, which
    ; GFX_PAINT_ATTR does not touch: clear it to CURRENT_ATTR too.
    ld   a, (GFX_MODE)
    cp   1
    jr   nz, .not_hires
    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    ld   a, (CURRENT_ATTR)
    ld   (hl), a
    ldir
.not_hires:

    ld   hl, 0                  ; home the print position
    ld   (PRINT_ROW), hl
    ret
    ASSERT PRINT_COL == PRINT_ROW + 1


    ENDIF
