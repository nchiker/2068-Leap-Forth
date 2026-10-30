; ============================================================================
; kernel/graphics/graphics.asm -- text-mode screen output, attributes, scrolling, pixels and lines
;
; The screen is the standard 256x192 bitmap at SCREEN_ADDR (interleaved by thirds) with the 32x24
; attribute area at ATTR_ADDR. ROW_BASE_TABLE gives the bitmap address of (row, column 0,
; scanline 0); a column adds 1 and a scanline down adds 256. Characters are 8-byte glyphs from
; FONT_TABLE (kernel/graphics/font.asm); PUNCT_CHAR_TABLE maps punctuation to font indexes; codes
; 128-143 are block graphics built into BLOCK_GFX_SCRATCH and 144-164 the UDGs (UDG_TABLE).
;
; A row or column off the grid is clipped, not written: the routines return carry set (or do
; nothing) rather than spill into the neighbouring row. Pixel colour is the hardware's: PLOT sets
; the covering attribute cell. FILL and CIRCLE are in the EXROM (rom/graphics_exrom.asm).
; ============================================================================

    INCLUDE "include/hardware.inc"

; ---- character grid ----
GFX_ROWS   EQU 24
GFX_COLS   EQU 32
ATTR_DEFAULT EQU $44     ; PAPER 0 (black), INK 4 (green), BRIGHT 1: GFX_CLS, GFX_CLEAR_ROW
ATTR_STATUS_BAR EQU $07   ; PAPER 0, INK 7 (white); not used by the Forth code

; solid-colour cell attributes (PAPER only; they are applied to blank cells)
ATTR_SWATCH_RED   EQU $10   ; PAPER 2 (red),   INK 0
ATTR_SWATCH_GREEN EQU $20   ; PAPER 4 (green), INK 0
ATTR_SWATCH_BLUE  EQU $08   ; PAPER 1 (blue),  INK 0

BORDER_DEFAULT  EQU 7     ; white; not applied anywhere (GFX_CLS leaves the border alone)

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
; GFX_COPY_ROW_BITMAP -- copy one text row's 8 scanlines (256 bytes) to another row
; The scanlines of a row are 256 bytes apart, so this is 8 block copies of 32 bytes.
; In:  GFX_SCROLL_DST_ROW, GFX_SCROLL_SRC_ROW set by the caller
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_COPY_ROW_BITMAP:
    ld   a, (GFX_SCROLL_DST_ROW)
    call GFX_ROW_BASE_ADDR          ; HL = dst row base
    push hl
    ld   a, (GFX_SCROLL_SRC_ROW)
    call GFX_ROW_BASE_ADDR          ; HL = src row base
    pop  de                         ; DE = dst row base
    ld   b, 8                       ; 8 scanlines per text row
.scanline_loop:
    push bc
    push hl
    push de
    ld   bc, 32
    ldir
    pop  de
    pop  hl
    ld   a, h                       ; both bases += 256 (one scanline), from the
    inc  a                          ;   pre-ldir values popped above
    ld   h, a
    ld   a, d
    inc  a
    ld   d, a
    pop  bc
    djnz .scanline_loop
    ret

; ============================================================================
; GFX_SCROLL_TEXT_UP -- scroll rows 1-22 up one row (row 23 is not touched; row 22 is left as it was)
; Moves the bitmap and the attributes; the caller draws the new row 22. Rows are copied in
; ascending destination order, so each source is read before it is overwritten.
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_TEXT_UP:
    call GFX_SPRITE_INVALIDATE
    ld   hl, ATTR_ADDR + 32          ; attributes are linear: rows 1-22 move up in one ldir
    ld   de, ATTR_ADDR
    ld   bc, 22*32
    ldir

    xor  a
    ld   (GFX_SCROLL_DST_ROW), a
.row_loop:
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_SRC_ROW), a
    call GFX_COPY_ROW_BITMAP
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_DST_ROW), a
    cp   22
    jr   c, .row_loop
    ret

; ============================================================================
; GFX_SCROLL_OUTPUT_UP -- scroll all 24 rows up one row and clear the new row 23
; Rows 0-21 by GFX_SCROLL_TEXT_UP, then row 23 is copied to row 22 and row 23 cleared.
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_OUTPUT_UP:
    call GFX_SCROLL_TEXT_UP
    ld   a, 22
    ld   (GFX_SCROLL_DST_ROW), a
    ld   a, 23
    ld   (GFX_SCROLL_SRC_ROW), a
    call GFX_COPY_ROW_BITMAP
    ld   hl, ATTR_ADDR + 23*32
    ld   de, ATTR_ADDR + 22*32
    ld   bc, 32
    ldir
    ld   b, 23
    jp   GFX_CLEAR_ROW

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
; Despite the name this returns an absolute address: FONT_TABLE + index * 8 for the font and
; punctuation, BLOCK_GFX_SCRATCH (built here) for codes 128-143, UDG_TABLE + offset for 144-164.
; In:  A = character code
; Out: carry clear + HL = the 8-byte glyph; carry set if the code has no glyph (GFX_CHAR_SETUP
;      draws a space)
; Destroys: AF, BC, DE, HL (E holds the code throughout; the punctuation scan counts in B)
; ============================================================================
GFX_CHAR_TO_FONT_OFFSET:
    ld   e, a                      ; E = the character, kept through the scans below
    cp   " "
    jr   z, .is_space
    cp   "0"
    jr   c, .try_punct             ; below the digits
    cp   "9" + 1
    jr   c, .is_digit
    cp   "A"
    jr   c, .try_punct              ; between the digits and the letters
    cp   "Z" + 1
    jr   c, .is_upper
    cp   "a"
    jr   c, .try_punct               ; between the cases
    cp   "z" + 1
    jr   c, .is_lower
    ; above 'z': 128-143 block graphics and 144-164 UDGs are taken here; the rest is scanned
    cp   128
    jr   c, .try_punct
    cp   UDG_CODE_BASE                  ; 144
    jr   c, .is_block_graphics
    cp   UDG_CODE_BASE + UDG_COUNT      ; 165
    jr   c, .is_udg
    ; 165+: not in the table either, so .not_found

.try_punct:
    ; linear scan of PUNCT_CHAR_TABLE's (char, index) pairs
    ld   hl, PUNCT_CHAR_TABLE
    ld   b, PUNCT_CHAR_COUNT
.punct_loop:
    ld   a, (hl)
    cp   e
    jr   z, .punct_found
    inc  hl
    inc  hl                          ; 2 bytes per entry
    djnz .punct_loop
    jr   .not_found

.punct_found:
    inc  hl
    ld   a, (hl)                      ; A = this character's font index
    jr   .to_offset

.is_space:
    ld   hl, FONT_TABLE                ; glyph 0
    or   a
    ret
.is_digit:
    sub  "0"
    add  a, 1                      ; index 0 is space; digits start at 1
    jr   .to_offset
.is_upper:
    sub  "A"
    add  a, 11                      ; index 0=space, 1-10=digits, 11-36=upper
    jr   .to_offset
.is_lower:
    sub  "a"
    add  a, 37                       ; 37-62=lowercase
.to_offset:
    ; glyph pointer = FONT_TABLE + index * 8
    ld   l, a
    ld   h, 0
    add  hl, hl                      ; x2
    add  hl, hl                      ; x4
    add  hl, hl                      ; x8
    ld   bc, FONT_TABLE
    add  hl, bc
    or   a
    ret

.is_block_graphics:
    ; Codes 128-143: the glyph is built in BLOCK_GFX_SCRATCH from the code's low nibble (bit0 =
    ; top-right, bit1 = top-left, bit2 = bottom-right, bit3 = bottom-left; each a solid 4x4 block).
    ; Each half is four identical rows: the low bit of its pair selects the right nibble ($0F),
    ; the next the left ($F0); E shifts down two bits between halves (top, then bottom).
    ; Leap-C's block-graphics routine (2068-Leap-C delta D21, clean-room from the screen format).
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
    ld   hl, BLOCK_GFX_SCRATCH
    or   a                           ; carry clear = success
    ret

.is_udg:
    ; Codes 144-164: UDG_TABLE + (code - UDG_CODE_BASE) * 8; the UDGs are RAM
    ld   a, e
    sub  UDG_CODE_BASE
    ld   l, a
    ld   h, 0
    add  hl, hl                        ; x2
    add  hl, hl                        ; x4
    add  hl, hl                        ; x8
    ld   bc, UDG_TABLE
    add  hl, bc
    or   a
    ret

.not_found:
    scf
    ret

; ============================================================================
; GFX_CHAR_SETUP -- glyph pointer and screen address for a character cell (shared by GFX_PUTCHAR)
; In:  A = character code, B = row (0-23), C = column (0-31)
; Out: carry clear + HL = the glyph's 8 bytes, DE = the cell's top-left screen address; carry set
;      (HL/DE undefined) if row >= 24 or column >= 32
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_CHAR_SETUP:
    ld   d, a                      ; the character; A is scratch for the checks
    ld   a, b
    cp   24
    jr   nc, .out_of_range
    ld   a, c
    cp   32
    jr   nc, .out_of_range
    ld   a, d                      ; restore the character
    push bc                        ; GFX_CHAR_TO_FONT_OFFSET destroys B
    call GFX_CHAR_TO_FONT_OFFSET
    jr   nc, .have_offset
    ld   hl, FONT_TABLE             ; no glyph: a space
.have_offset:
    pop  bc
    push hl                            ; the glyph pointer

    ld   a, b
    call GFX_ROW_BASE_ADDR
    ex   de, hl                       ; DE = row_base
    ld   a, c
    add  a, e
    ld   e, a
    jr   nc, .no_carry
    inc  d
.no_carry:                             ; DE = row_base + column

    pop  hl                                ; HL = the glyph
    or   a                                ; carry clear: success
    ret

.out_of_range:
    scf
    ret

; ============================================================================
; GFX_PUTCHAR -- draw one character in the grid (bitmap only; the attribute is not touched)
; In:  A = character code, B = row (0-23), C = column (0-31)
; Out: carry set if the position is off the grid (nothing drawn), else clear
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PUTCHAR:
    call GFX_CHAR_SETUP
    ret  c                                 ; off the grid: nothing drawn
    ld   b, 8                              ; 8 scanlines
.scanline_loop:
    ld   a, (hl)                            ; A = this scanline's font byte
    ex   de, hl                              ; HL = screen address, DE = font ptr
    ld   (hl), a                              ; write font byte to screen
    inc  h                                     ; next scanline: screen address += 256
    ex   de, hl                                ; HL = font ptr, DE = screen address
    inc  hl                                    ; next font byte
    djnz .scanline_loop
    ret

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
    push bc                  ; GFX_PUTCHAR destroys BC
    call GFX_PUTCHAR
    pop  bc
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
    cp   1
    jr   z, .highres

    ; Normal (0, or any value but 1): video mode bits 0-2 clear
    ld   a, (PORT_FF_SHADOW)
    and  %11111000
    jr   .write_port

.highres:
    ld   a, (PORT_FF_SHADOW)
    and  %11111000                 ; keep bits 3-7 (ink/paper select, INTEN, EXROM)
    or   2

.write_port:
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   a, (GFX_MODE)
    cp   1
    jr   z, .clear_highres
    ret

.clear_highres:
    ; first entry: clear the second display file's attributes to ATTR_DEFAULT
    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    ld   a, ATTR_DEFAULT
    ld   (hl), a
    ldir
    ret

; ============================================================================
; GFX_CLEAR_ROW -- clear one text row (bitmap and attributes) to blank / ATTR_DEFAULT
; In:  B = row (0-23)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_CLEAR_ROW:
    ld   c, 0
.loop:
    push bc
    ld   a, " "
    call GFX_PUTCHAR
    pop  bc

    push bc
    ld   a, ATTR_DEFAULT
    call GFX_SET_ATTR
    pop  bc

    inc  c
    ld   a, c
    cp   GFX_COLS
    jr   c, .loop
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

; the glyph index for each punctuation character (FONT_TABLE order)
PUNCT_CHAR_TABLE:
    DB   '"', 63
    DB   "!", 64
    DB   "@", 65
    DB   "#", 66
    DB   "$", 67
    DB   "%", 68
    DB   "&", 69
    DB   "'", 70
    DB   "(", 71
    DB   ")", 72
    DB   "_", 73
    DB   ":", 74
    DB   ".", 75
    DB   ",", 76
    DB   "=", 77
    DB   "+", 78
    DB   "-", 79
    DB   ";", 80
    DB   "/", 81
    DB   "*", 82
    DB   "<", 83
    DB   ">", 84
    DB   "?", 85
PUNCT_CHAR_COUNT EQU 23

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
    jr   nc, .out_of_range
    ld   a, c
    cp   32
    jr   nc, .out_of_range
    ld   h, 0
    ld   l, b
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl                      ; row * 32
    ld   de, ATTR_ADDR
    add  hl, de
    ld   d, 0
    ld   e, c
    add  hl, de                       ; HL = ATTR_ADDR + row*32 + col
    ret
.out_of_range:
    scf
    ret
