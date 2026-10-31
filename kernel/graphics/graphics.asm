; ============================================================================
; kernel/graphics/graphics.asm -- text-mode screen output, attributes, scrolling, pixels and lines
;
; The screen is the standard 256x192 bitmap at SCREEN_ADDR (interleaved by thirds) with the 32x24
; attribute area at ATTR_ADDR. ROW_BASE_TABLE gives the bitmap address of (row, column 0,
; scanline 0); a column adds 1 and a scanline down adds 256. Characters are 8-byte glyphs from
; FONT_TABLE (kernel/graphics/font.asm), which holds printable ASCII (32-126) in code order; codes
; 128-143 are block graphics built into BLOCK_GFX_SCRATCH and 144-164 the UDGs (UDG_TABLE).
;
; A row or column off the grid is clipped, not written: the routines return carry set (or do
; nothing) rather than spill into the neighbouring row. Pixel colour is the hardware's: PLOT sets
; the covering attribute cell. FILL and CIRCLE are in the EXROM (rom/graphics_exrom.asm).
; ============================================================================

    INCLUDE "include/hardware.inc"

; ---- character grid ----
GFX_COLS   EQU 32          ; ATTR_DEFAULT (GFX_CLS, GFX_CLEAR_ROW) is in include/hardware.inc

; ============================================================================
; GFX_CLS -- clear the bitmap and paint every attribute ATTR_DEFAULT
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_CLS:
    call GFX_SPRITE_INVALIDATE
    ld   hl, SCREEN_ADDR
    ld   de, SCREEN_ADDR + 1
    ld   bc, 6144 - 1           ; the bitmap, $4000-$57FF
    xor  a
    ld   (hl), a
    ldir

    ld   a, ATTR_DEFAULT           ; falls into GFX_PAINT_ATTR
; ============================================================================
; GFX_PAINT_ATTR -- paint all 768 attribute cells with one byte (the bitmap is untouched)
; GFX_CLS falls into this with A = ATTR_DEFAULT.
; In:  A = attribute byte
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PAINT_ATTR:
    ld   hl, ATTR_ADDR
    ld   de, ATTR_ADDR + 1
    ld   bc, 768 - 1
    ld   (hl), a
    ldir
    ret

; ============================================================================
; GFX_SPRITE_INVALIDATE -- forget the sprites' shown state before a global screen change (CLS,
; mode switch)
; The screen no longer shows what a slot saved, so a later SPRITE-HIDE must not restore it; the
; captured images (SPRITE_SLOT_DEFINED) stay defined.
; In:  none
; Out: SPRITE_SLOT_SHOWN[0..SPRITE_SLOT_MAX-1] = 0
; Destroys: AF, B, HL
; ============================================================================
GFX_SPRITE_INVALIDATE:
    xor  a
    ld   hl, SPRITE_SLOT_SHOWN
    ld   b, SPRITE_SLOT_MAX
.loop:
    ld   (hl), a
    inc  hl
    djnz .loop
    ret

; ============================================================================
; GFX_ROW_BASE_ADDR -- a text row's bitmap base address (scanline 0, column 0)
; In:  A = row (0-23; not checked)
; Out: HL = the address
; Destroys: AF, DE
; ============================================================================
GFX_ROW_BASE_ADDR:
    ld   h, 0
    ld   l, a
    add  hl, hl                    ; row * 2 (2 bytes per table entry)
    ld   de, ROW_BASE_TABLE
    add  hl, de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    ret

; ============================================================================
; GFX_SCROLL_TEXT_UP -- scroll rows 1-22 up one row (row 23 is not touched; row 22 is left as it was)
; Moves the bitmap and the attributes; the caller draws the new row 22.
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_TEXT_UP:
    ld   a, 6                       ; rows 17-22 of the last third
    jr   GFX_SCROLL_ROWS

; ============================================================================
; GFX_SCROLL_OUTPUT_UP -- scroll all 24 rows up one row and clear the new row 23
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_OUTPUT_UP:
    ld   a, 7                       ; rows 17-23 of the last third
    call GFX_SCROLL_ROWS
    ld   b, 23
    jp   GFX_CLEAR_ROW

; ============================================================================
; GFX_SCROLL_ROWS -- rows 1 to 16 + A move up one row, bitmap and attributes
; A scanline of a third holds its 8 rows' bytes in a run, so each scanline of the first two thirds
; is two copies (rows 1-7 to 0-6, the next third's row 0 to row 7) and of the last third one (its
; rows 1 to A to 0 to A - 1), in 32-byte blocks (GFX_LDI_BLOCKS).
; In:  A = the rows moved within the last third (6 or 7)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_ROWS:
    push af
    call GFX_SPRITE_INVALIDATE
    pop  af
    push af
    add  a, 16                      ; the attributes: one block a row
    ld   hl, ATTR_ADDR + 32
    ld   de, ATTR_ADDR
    call GFX_LDI_BLOCKS
    ld   de, SCREEN_ADDR            ; scanline 0 of the first third
.scanline:
    ld   h, d
    ld   l, 32                      ; HL = the same scanline of row 1
    ld   a, d
    cp   HIGH SCREEN_ADDR + $10
    jr   nc, .last
    ld   a, 7
    call GFX_LDI_BLOCKS             ; rows 1-7 to 0-6
    ld   a, h
    add  a, 7
    ld   h, a                       ; the next third's row 0
    ld   a, 1
    call GFX_LDI_BLOCKS             ; to row 7; DE = the next scanline (or third)
    jr   .scanline
.last:
    pop  af
    push af
    call GFX_LDI_BLOCKS
    ld   e, a                       ; A = 0
    inc  d                          ; the next scanline
    ld   a, d
    cp   HIGH SCREEN_ADDR + $18
    jr   c, .scanline
    pop  af
    ret
    ASSERT LOW SCREEN_ADDR == 0 && LOW ATTR_ADDR == 0

; ============================================================================
; GFX_LDI_BLOCKS -- copy A blocks of 32 bytes (unrolled LDI: 16 T a byte, LDIR's 21)
; In:  HL = source, DE = destination, A = blocks (1-255)
; Out: HL, DE past the blocks, A = 0
; Destroys: F, BC
; ============================================================================
GFX_LDI_BLOCKS:
    REPT 32
    ldi
    ENDR
    dec  a
    jr   nz, GFX_LDI_BLOCKS
    ret

; ============================================================================
; GFX_SET_BORDER -- set the border colour
; Only port $FE bits 0-2 are the colour; EAR/MIC (bits 3-4) are kept from PORT_FE_SHADOW, which
; the tape routines also update.
; In:  A = colour (low 3 bits used)
; Out: none
; Destroys: AF, B
; ============================================================================
GFX_SET_BORDER:
    and  $07                     ; the colour bits only: nothing from the caller reaches EAR/MIC
    ld   b, a
    ld   a, (PORT_FE_SHADOW)
    and  $F8                     ; keep EAR/MIC as they were
    or   b
    ld   (PORT_FE_SHADOW), a
    out  (PORT_ULA), a
    ret

; ============================================================================
; GFX_CHAR_TO_FONT_OFFSET -- the glyph pointer for a character code
; Despite the name this returns an absolute address: FONT_TABLE + (code - 32) * 8 for printable
; ASCII, BLOCK_GFX_SCRATCH (built here) for codes 128-143, UDG_TABLE + offset for 144-164.
; In:  A = character code
; Out: carry clear + HL = the 8-byte glyph; carry set if the code has no glyph (0-31, 127, 165 up;
;      GFX_PUTCHAR draws a space)
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_CHAR_TO_FONT_OFFSET:
    sub  " "
    cp   "~" - " " + 1
    jr   nc, .not_ascii
    ld   de, FONT_TABLE
.scale:                             ; HL = DE + A * 8 (A <= 94: A * 2 fits a byte)
    add  a, a
    ld   l, a
    ld   h, 0
    add  hl, hl
    add  hl, hl
    add  hl, de                     ; carry clear: no overflow
    ret

.not_ascii:
    add  a, " "                     ; A = the code again
    cp   128
    ret  c                          ; 0-31 and 127: carry set, no glyph
    sub  UDG_CODE_BASE              ; 144
    jr   c, .is_block_graphics      ; 128-143
    cp   UDG_COUNT
    ccf
    ret  c                          ; 165 up: no glyph
    ld   de, UDG_TABLE              ; 144-164: UDG_TABLE + (code - 144) * 8; the UDGs are RAM
    jr   .scale

.is_block_graphics:
    ; Codes 128-143 (A = code - 144): the glyph is built in BLOCK_GFX_SCRATCH from the code's low
    ; nibble (bit0 = top-right, bit1 = top-left, bit2 = bottom-right, bit3 = bottom-left; each a
    ; solid 4x4 block). Each half is four identical rows: the low bit of its pair selects the right
    ; nibble ($0F), the next the left ($F0); E shifts down two bits between halves (top, then
    ; bottom). Leap-C's block-graphics routine (2068-Leap-C delta D21, clean-room from the screen
    ; format).
    push bc
    ld   e, a                        ; the low nibble is the code's
    ld   hl, BLOCK_GFX_SCRATCH
    ld   b, 2                        ; two halves
.bg_half:
    ld   a, e
    rra                              ; carry = right quarter
    sbc  a, a                        ; $FF if ink, else $00
    and  $0F
    ld   c, a                        ; right nibble
    ld   a, e
    rra
    rra                              ; carry = left quarter
    sbc  a, a
    and  $F0
    or   c                           ; A = row pattern for this half
    ld   c, 4
.bg_row:
    ld   (hl), a
    inc  hl
    dec  c
    jr   nz, .bg_row
    srl  e
    srl  e                           ; next pair of quarters
    djnz .bg_half
    pop  bc
    ld   hl, BLOCK_GFX_SCRATCH
    or   a                           ; carry clear = success
    ret

; ============================================================================
; GFX_PUTCHAR -- draw one character in the grid (bitmap only; the attribute is not touched)
; In:  A = character code, B = row (0-23), C = column (0-31)
; Out: carry set if the position is off the grid (nothing drawn); else carry clear and DE = the
;      cell's top-left bitmap address + 8 scanlines (D + 8: GFX_PUTCHAR_ATTR's input)
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_PUTCHAR:
    ld   d, a                       ; the character; A is scratch for the checks
    ld   a, b
    cp   24
    ccf
    ret  c
    ld   a, c
    cp   32
    ccf
    ret  c
    ld   a, d
    call GFX_CHAR_TO_FONT_OFFSET    ; keeps BC
    jr   nc, .have_glyph
    ld   hl, FONT_TABLE              ; no glyph: a space
.have_glyph:
    ; the cell's address: 010tt000 rrrccccc (tt = row / 8, rrr = row MOD 8, ccccc = column)
    ld   a, b
    and  $18
    or   HIGH SCREEN_ADDR
    ld   d, a
    ld   a, b
    rrca
    rrca
    rrca
    and  $E0
    add  a, c                       ; carry clear: rrr00000 + column < 256
    ld   e, a
    REPT 7                          ; the 8 scanlines, 256 bytes apart
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  d
    ENDR
    ld   a, (hl)
    ld   (de), a
    inc  d
    ret
    ASSERT LOW SCREEN_ADDR == 0 && (HIGH SCREEN_ADDR & $1F) == 0

; ============================================================================
; GFX_PUTCHAR_ATTR -- draw one character and set its cell's attribute (EMIT, the console)
; In:  A = character code, B = row (0-23), C = column (0-31), E = the attribute
; Out: carry set if the position is off the grid (nothing drawn or set)
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_PUTCHAR_ATTR:
    push de
    call GFX_PUTCHAR
    pop  hl                         ; L = the attribute
    ret  c
    ld   a, d                       ; 010tt000 + 8: bits 3-4 hold tt + 1, bits 0-2 are 0
    rrca
    rrca
    rrca                            ; 9 + tt
    add  a, HIGH ATTR_ADDR - 9
    ld   d, a                       ; DE = ATTR_ADDR + row * 32 + column
    ld   a, l
    ld   (de), a
    ret
    ASSERT LOW ATTR_ADDR == 0 && HIGH ATTR_ADDR == HIGH SCREEN_ADDR + $18

; ============================================================================
; GFX_PRINT_STRING -- draw a zero-terminated string, one column per character
; No wrapping or scrolling: characters past column 31 are clipped.
; In:  HL = string, B = row, C = column
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PRINT_STRING:
.loop:
    ld   a, (hl)
    or   a
    ret  z
    push hl
    call GFX_PUTCHAR
    pop  hl
    inc  hl
    inc  c
    jr   .loop

; ============================================================================
; GFX_ATTR_SWAP -- a cell's attribute address and its ink/paper-swapped value (for GFX_INVERT_ATTR)
; In:  B = row (0-23), C = column (0-31)
; Out: carry clear + HL = the attribute byte's address, A = the attribute with ink and paper
;      swapped, FLASH/BRIGHT unchanged; carry set (HL/A undefined) if off the grid
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_ATTR_SWAP:
    call GFX_CELL_ATTR_ADDR
    ret  c

    ld   a, (hl)
    ld   b, a                     ; B = original attribute byte

    and  %00000111                 ; the ink bits
    rlca
    rlca
    rlca                             ; into paper's position
    ld   c, a

    ld   a, b
    and  %00111000                     ; the paper bits
    rrca
    rrca
    rrca                                 ; into ink's position
    or   c
    ld   c, a                              ; C = the swapped colours (bits 5-0)

    ld   a, b
    and  %11000000                          ; FLASH/BRIGHT unchanged
    or   c
    or   a                                    ; carry clear: success
    ret

; ============================================================================
; GFX_INVERT_ATTR -- swap ink and paper in a cell and set its FLASH bit (the editor's cursor)
; In:  B = row (0-23), C = column (0-31)
; Out: carry set if off the grid (nothing written)
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_INVERT_ATTR:
    call GFX_ATTR_SWAP
    ret  c                                    ; off the grid: nothing to write
    or   %10000000                            ; FLASH on: the ULA blinks the cell itself
    ld   (hl), a
    ret

; ============================================================================
; GFX_SET_ATTR -- set one cell's attribute byte
; Off the grid it does nothing.
; In:  A = attribute, B = row (0-23), C = column (0-31)
; Out: none
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_SET_ATTR:
    push af
    call GFX_CELL_ATTR_ADDR
    jr   c, .discard_attr
    pop  af
    ld   (hl), a
    ret
.discard_attr:
    pop  af
    ret

; ============================================================================
; GFX_SET_MODE -- switch the video mode through port $FF (PORT_SCLD)
; Only the mode bits (0-2) change, merged into PORT_FF_SHADOW; the rest of the port is kept. The
; sprites are invalidated; entering HIRES clears the second display file's attributes (6144 bytes
; at SECOND_DISPLAY_ADDR) to ATTR_DEFAULT, because that memory is otherwise unused and its
; power-on content could make the first pixels invisible. The mode is kept in GFX_MODE.
; In:  A = mode (0 = Normal, 1 = High Resolution; the caller validates)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SET_MODE:
    push af
    call GFX_SPRITE_INVALIDATE
    pop  af
    ld   (GFX_MODE), a
    ld   c, a
    ld   a, (PORT_FF_SHADOW)
    and  %11111000                 ; keep bits 3-7 (ink/paper select, INTEN, EXROM)
    dec  c
    jr   nz, .write_port           ; Normal (0, or any value but 1): video mode bits 0-2 clear
    or   2                         ; High Resolution
.write_port:
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a
    ld   a, c
    or   a
    ret  nz
    ; High Resolution: clear the second display file's attributes to ATTR_DEFAULT
    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    ld   a, ATTR_DEFAULT
    ld   (hl), a
    ldir
    ret

; ============================================================================
; GFX_STATUS_BAR -- paint row 23's attributes as the status bar (Leap V2's): columns 0-28 white on
; black, then a red, a green and a blue cell; the bitmap is not touched
; In:  none
; Out: none
; Destroys: AF, B, HL
; ============================================================================
GFX_STATUS_BAR:
    ld   hl, ATTR_ADDR + 23 * 32
    ld   b, 29
.bar:
    ld   (hl), ATTR_STATUS_BAR
    inc  l
    djnz .bar
    ld   (hl), ATTR_SWATCH_RED
    inc  l
    ld   (hl), ATTR_SWATCH_GREEN
    inc  l
    ld   (hl), ATTR_SWATCH_BLUE
    ret

; ============================================================================
; GFX_CLEAR_ROW -- clear one text row (bitmap and attributes) to blank / ATTR_DEFAULT
; The bytes 32 spaces would leave (the space glyph is 8 zero bytes), written directly: Leap V2's
; GFX_CLEAR_ROW (audit item O4).
; In:  B = row (0-23)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_CLEAR_ROW:
    ld   c, 0
    call GFX_CELL_ATTR_ADDR         ; HL = the row's first attribute (BC kept)
    ld   a, ATTR_DEFAULT
    ld   c, GFX_COLS
.attr:
    ld   (hl), a
    inc  l                          ; (a row's 32 attributes never cross a page)
    dec  c
    jr   nz, .attr
    ld   a, b
    call GFX_ROW_BASE_ADDR          ; HL = scanline 0, column 0
    ld   e, l
    xor  a
    ld   c, 8
.scan:
    ld   b, GFX_COLS
.byte:
    ld   (hl), a
    inc  l
    djnz .byte
    ld   l, e                       ; column 0,
    inc  h                          ; the next scanline
    dec  c
    jr   nz, .scan
    ret

; ============================================================================
; GFX_PIXEL_ADDR_SETUP -- the bitmap address and bit mask of a pixel (shared by the pixel routines)
; In:  B = x (0-255), C = y (0-191; not checked)
; Out: HL = the bitmap byte's address, A = the bit mask (bit 7 = leftmost pixel); GFX_PIXEL_ROW and
;      GFX_PIXEL_COL = the pixel's character row and column
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PIXEL_ADDR_SETUP:
    ld   a, c
    and  %00000111                 ; scanline = y & 7
    ld   (GFX_PIXEL_SCANLINE), a

    ld   a, c
    rrca
    rrca
    rrca
    and  %00011111                 ; char_row = y >> 3
    ld   (GFX_PIXEL_ROW), a

    ld   a, b
    and  %00000111                 ; bit_in_byte = x & 7
    ld   e, a
    ld   d, 0
    ld   hl, BIT_MASK_TABLE
    add  hl, de
    ld   a, (hl)
    ld   (GFX_PIXEL_MASK), a

    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111                 ; col = x >> 3
    ld   (GFX_PIXEL_COL), a

    ; bitmap address = ROW_BASE_TABLE[char_row] + col + scanline * 256
    ld   a, (GFX_PIXEL_ROW)
    call GFX_ROW_BASE_ADDR
    ex   de, hl                   ; DE = ROW_BASE_TABLE[char_row]
    ld   a, (GFX_PIXEL_COL)
    add  a, e
    ld   e, a
    jr   nc, .no_col_carry
    inc  d
.no_col_carry:
    ld   a, (GFX_PIXEL_SCANLINE)
    add  a, d
    ld   d, a                      ; DE = final bitmap byte address
    ld   h, d
    ld   l, e
    ld   a, (GFX_PIXEL_MASK)
    ret

; ============================================================================
; GFX_WRITE_PIXEL -- set (OVER 0) or XOR (OVER 1) one pixel and colour it
; Normal mode colours the pixel's 8x8 cell (GFX_SET_ATTR); HIRES colours its own 8x1 attribute byte
; at the bitmap byte + $2000. y >= 192 draws nothing.
; In:  B = x (0-255), C = y, A = attribute byte, D = OVER flag
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_WRITE_PIXEL:
    ld   (GFX_PIXEL_ATTR), a
    ld   a, c
    cp   192
    ret  nc                        ; below the screen: nothing
    ld   a, d
    ld   (GFX_PIXEL_OVER), a

    call GFX_PIXEL_ADDR_SETUP      ; HL = bitmap byte address, A = mask
    ld   b, a                      ; B = mask
    ld   a, (GFX_PIXEL_OVER)
    or   a
    jr   z, .plot_set
    ld   a, (hl)
    xor  b
    jr   .plot_write
.plot_set:
    ld   a, (hl)
    or   b
.plot_write:
    ld   (hl), a

    ; colour it: Normal mode its 8x8 cell, HIRES its own 8x1 attribute byte
    ld   a, (GFX_MODE)
    or   a
    jr   nz, .ext_attr

    ld   a, (GFX_PIXEL_ROW)
    ld   b, a
    ld   a, (GFX_PIXEL_COL)
    ld   c, a
    ld   a, (GFX_PIXEL_ATTR)
    jp GFX_SET_ATTR

.ext_attr:
    ld   a, h
    add  a, $20
    ld   h, a                      ; HL = the bitmap byte + $2000: its 8x1 attribute
    ld   a, (GFX_PIXEL_ATTR)
    ld   (hl), a
    ret

; ============================================================================
; GFX_LINE -- draw a line between two points (Bresenham; absolute coordinates for both ends)
; The inputs are in memory, not registers: the loop calls GFX_WRITE_PIXEL and MATH_COMPARE16,
; which destroy registers.
; In:  GFX_LINE_X0/Y0/X1/Y1/ATTR/OVER set by the caller
; Out: GFX_LINE_X0/Y0 = the end point
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_LINE:
    ; dx = abs(x1-x0), sx = sign
    ld   a, (GFX_LINE_X1)
    ld   b, a
    ld   a, (GFX_LINE_X0)
    ld   c, a
    sub  b                        ; A = x0 - x1; carry set means x0 < x1
    jr   nc, .x0_ge_x1
    ld   a, b
    sub  c                        ; A = x1 - x0
    ld   (GFX_LINE_DX), a
    ld   a, 1
    ld   (GFX_LINE_SX), a
    jr   .dx_done
.x0_ge_x1:
    ld   (GFX_LINE_DX), a         ; A = x0 - x1 already
    ld   a, $FF                   ; -1 (two's complement)
    ld   (GFX_LINE_SX), a
.dx_done:

    ; dy_abs = abs(y1-y0), sy = sign
    ld   a, (GFX_LINE_Y1)
    ld   b, a
    ld   a, (GFX_LINE_Y0)
    ld   c, a
    sub  b
    jr   nc, .y0_ge_y1
    ld   a, b
    sub  c
    ld   (GFX_LINE_DY_ABS), a
    ld   a, 1
    ld   (GFX_LINE_SY), a
    jr   .dy_done
.y0_ge_y1:
    ld   (GFX_LINE_DY_ABS), a
    ld   a, $FF
    ld   (GFX_LINE_SY), a
.dy_done:

    ; err = dx - dy_abs (16-bit; both are zero-extended bytes, so the subtract is exact)
    ld   a, (GFX_LINE_DX)
    ld   l, a
    ld   h, 0
    ld   a, (GFX_LINE_DY_ABS)
    ld   e, a
    ld   d, 0
    or   a
    sbc  hl, de
    ld   (GFX_LINE_ERR), hl

.loop:
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_Y0)
    ld   c, a
    ld   a, (GFX_LINE_OVER)
    ld   d, a
    ld   a, (GFX_LINE_ATTR)
    call GFX_WRITE_PIXEL

    ; done when the current point is the end point
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_X1)
    cp   b
    jr   nz, .not_done
    ld   a, (GFX_LINE_Y0)
    ld   b, a
    ld   a, (GFX_LINE_Y1)
    cp   b
    jr   nz, .not_done
    ret
.not_done:

    ; e2 = err * 2, kept in memory: both tests below need it and MATH_COMPARE16 destroys HL
    ld   hl, (GFX_LINE_ERR)
    add  hl, hl
    ld   (GFX_LINE_E2), hl

    ; if e2 >= -dy_abs: err += -dy_abs; x0 += sx
    ld   a, (GFX_LINE_DY_ABS)
    ld   l, a
    ld   h, 0
    call MATH_NEGATE16             ; HL = -dy_abs
    ex   de, hl                    ; DE = -dy_abs (MATH_COMPARE16 leaves DE alone)
    ld   hl, (GFX_LINE_E2)
    call MATH_COMPARE16            ; A: 0 if equal, 1 if e2>DE, $FF if e2<DE
    cp   $FF
    jr   z, .skip_x_step           ; e2 < -dy_abs
    ld   hl, (GFX_LINE_ERR)
    add  hl, de                    ; DE still = -dy_abs
    ld   (GFX_LINE_ERR), hl
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_SX)
    add  a, b
    ld   (GFX_LINE_X0), a
.skip_x_step:

    ; if e2 <= dx: err += dx; y0 += sy
    ld   a, (GFX_LINE_DX)
    ld   e, a
    ld   d, 0
    ld   hl, (GFX_LINE_E2)
    call MATH_COMPARE16             ; A: 0 if equal, 1 if e2>dx, $FF if e2<dx
    cp   1
    jr   z, .skip_y_step            ; e2 > dx
    ld   hl, (GFX_LINE_ERR)
    ld   a, (GFX_LINE_DX)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   (GFX_LINE_ERR), hl
    ld   a, (GFX_LINE_Y0)
    ld   b, a
    ld   a, (GFX_LINE_SY)
    add  a, b
    ld   (GFX_LINE_Y0), a
.skip_y_step:

    jp   .loop                     ; JP: the loop is within 2 bytes of JR's -128 limit

BIT_MASK_TABLE:
    DB   %10000000, %01000000, %00100000, %00010000
    DB   %00001000, %00000100, %00000010, %00000001

; the first UDG character code (UDGs are 144 to 144 + UDG_COUNT - 1; block graphics are 128-143)
UDG_CODE_BASE EQU 144

; the bitmap address of each text row (scanline 0, column 0)
ROW_BASE_TABLE:
    DW   $4000, $4020, $4040, $4060, $4080, $40A0, $40C0, $40E0
    DW   $4800, $4820, $4840, $4860, $4880, $48A0, $48C0, $48E0
    DW   $5000, $5020, $5040, $5060, $5080, $50A0, $50C0, $50E0

; ============================================================================
; GFX_CELL_ATTR_ADDR -- a cell's attribute byte address (bounds checked)
; Shared by GFX_ATTR_SWAP, GFX_SET_ATTR and the sprite code.
; In:  B = row (0-23), C = column (0-31)
; Out: carry clear + HL = ATTR_ADDR + row * 32 + column; carry set if off the grid
; Destroys: AF, DE, HL
; ============================================================================
GFX_CELL_ATTR_ADDR:
    ld   a, b
    cp   24
    ccf
    ret  c
    ld   a, c
    cp   32
    ccf
    ret  c
    ld   a, b
    rrca
    rrca
    rrca                             ; rrr000tt: row * 32's low byte in bits 5-7, its high byte in 0-1
    ld   h, a
    and  $E0
    or   c
    ld   l, a                        ; L = (row * 32 + column) & $FF
    ld   a, h
    and  $03
    or   HIGH ATTR_ADDR
    ld   h, a                        ; HL = ATTR_ADDR + row * 32 + column; carry clear (OR)
    ret
