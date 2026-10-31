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
; GFX_PIXEL_AT -- a pixel's bitmap address and bit mask
; In:  B = x (0-255), C = y (0-191; not checked)
; Out: HL = the bitmap byte's address, A = the bit mask (bit 7 = leftmost pixel)
; Destroys: F (BC and DE are kept)
; ============================================================================
GFX_PIXEL_AT:
    ld   a, c
    and  7
    ld   h, a
    ld   a, c
    rra
    rra
    rra
    and  $18
    or   h
    or   HIGH SCREEN_ADDR
    ld   h, a                       ; 010tt sss: the third, the scanline
    ld   a, c
    rla
    rla
    and  $E0
    ld   l, a
    ld   a, b
    rrca
    rrca
    rrca
    and  $1F
    or   l
    ld   l, a                       ; rrr ccccc: the row in the third, the column
    ld   a, b
    and  7
    push bc
    ld   b, a
    inc  b
    ld   a, 1
.mask:
    rrca
    djnz .mask
    pop  bc
    ret
    ASSERT LOW SCREEN_ADDR == 0

; ============================================================================
; GFX_LINE -- draw a line: the points of Bresenham's line from (X0, Y0) to (X1, Y1) on an unbounded
; plane, those on the screen (x 0-255, y 0-191)
; The major axis (the larger of |dx| and |dy|; x on a tie) steps at every point, the minor one when
; the error r (0 to dmaj - 1, from dmaj / 2) passes dmaj after adding dmin: the points the ROM's
; e2 form (err = dx - dy) drew before. Off the screen the line is walked without drawing; on it,
; drawn with its address and mask stepped from point to point, to the end point or the edge (a line
; that has left the screen never comes back).
; In:  GFX_LINE_X0/Y0/X1/Y1 (signed 16-bit), GFX_LINE_ATTR
; Out: none
; Destroys: AF, BC, DE, HL, BC', DE', HL'
; LINE's flags (C while walking, E while drawing): bit 0 y is the major axis, bit 1 x goes left,
; bit 2 y goes up, bit 3 HIRES, bit 4 the attribute pending. The alternate registers hold r (HL'),
; dmin (DE') and dmaj (BC').
; ============================================================================
GFX_LINE:
    ld   a, (GFX_MODE)
    ld   c, a                       ; becomes bit 3 after the three shifts below
    ld   hl, (GFX_LINE_Y1)
    ld   de, (GFX_LINE_Y0)
    call LINE_DELTA                 ; HL = |dy|, carry: up
    rl   c
    push hl
    ld   hl, (GFX_LINE_X1)
    ld   de, (GFX_LINE_X0)
    call LINE_DELTA                 ; HL = |dx|, carry: left
    rl   c
    pop  de
    or   a
    sbc  hl, de
    add  hl, de                     ; carry: |dx| < |dy|
    rl   c
    bit  0, c
    jr   z, .xmaj
    ex   de, hl                     ; HL = dmaj, DE = dmin
.xmaj:
    ld   (GFX_LINE_N), hl           ; the steps after the first point
    push hl
    push de
    srl  h
    rr   l
    push hl
    exx
    pop  hl                         ; r = dmaj / 2
    pop  de
    pop  bc
    exx
    ld   hl, (GFX_LINE_X0)
    ld   de, (GFX_LINE_Y0)
.walk:                              ; HL = x, DE = y
    ld   a, h
    or   d
    jr   nz, .off
    ld   a, e
    cp   192
    jr   c, .enter
.off:
    push hl
    ld   hl, (GFX_LINE_N)
    ld   a, h
    or   l
    dec  hl
    ld   (GFX_LINE_N), hl
    pop  hl
    ret  z                          ; the end point, off the screen
    call .wmaj
    call LINE_BRES
    call c, .wmin
    jr   .walk
.wmaj:
    bit  0, c
    jr   nz, .wy
.wx:
    bit  1, c
    inc  hl
    ret  z
    dec  hl
    dec  hl
    ret
.wmin:
    bit  0, c
    jr   nz, .wx
.wy:
    bit  2, c
    inc  de
    ret  z
    dec  de
    dec  de
    ret

.enter:                             ; L = x, E = y
    ld   b, l
    ld   a, c
    ld   c, e
    ld   d, e                       ; D = y
    ld   e, a                       ; E = the flags
    ld   hl, (GFX_LINE_N)
    ld   a, h
    or   a
    ld   a, l
    jr   z, .count
    ld   a, 255                     ; the edge comes first
.count:
    inc  a
    push af
    call GFX_PIXEL_AT
    ld   c, a                       ; C = the mask, HL = the address
    pop  af
    ld   b, a                       ; B = the points to draw at most (0: 256)
    set  4, e
.draw:
    bit  4, e
    call nz, LINE_ATTR
    ld   a, (hl)
    or   c
    ld   (hl), a
    call .major                     ; (a step after the last point changes registers only)
    ret  c                          ; off the screen
    exx                             ; LINE_BRES, in line
    add  hl, de
    jr   c, .over
    sbc  hl, bc
    jr   nc, .step
    add  hl, bc
    exx
    djnz .draw
    ret
.over:
    or   a
    sbc  hl, bc
.step:
    exx
    call .minor
    ret  c
    djnz .draw
    ret
.major:
    bit  0, e
    jr   nz, LINE_YSTEP
    jr   LINE_XSTEP
.minor:
    bit  0, e
    jr   nz, LINE_XSTEP
                                    ; fall into LINE_YSTEP

; ============================================================================
; LINE_XSTEP, LINE_YSTEP -- the address and mask one pixel on in x (left if E bit 1) or y (up if E
; bit 2); where the byte (HIRES) or the cell (Normal) changes, E bit 4: the attribute is written
; with the next pixel (a cell the line passes between its x and y steps keeps its colour)
; In:  HL = the address, C = the mask, D = y, E = LINE's flags
; Out: carry set if the pixel is off the screen (the line ends there)
; Destroys: AF
; ============================================================================
LINE_YSTEP:
    bit  2, e
    jr   nz, .up
    ld   a, d
    cp   191
    scf
    ret  z                          ; below the bottom row
    inc  d
    inc  h
    ld   a, h
    and  7
    jr   nz, LINE_PEND_HIRES        ; the same cell row
    ld   a, l
    add  a, 32
    ld   l, a
    jr   c, LINE_PEND               ; the next third (H already is)
    ld   a, h
    sub  8
    ld   h, a
    jr   LINE_PEND
.up:
    ld   a, d
    or   a
    scf
    ret  z                          ; above the top row
    dec  d
    ld   a, h
    dec  h
    and  7
    jr   nz, LINE_PEND_HIRES
    ld   a, l
    sub  32
    ld   l, a
    jr   c, LINE_PEND               ; the third above (H already is)
    ld   a, h
    add  a, 8
    ld   h, a
    jr   LINE_PEND
LINE_XSTEP:
    ld   a, l
    bit  1, e
    jr   nz, .left
    rrc  c
    ret  nc
    inc  l
    jr   .byte
.left:
    rlc  c
    ret  nc
    dec  l
.byte:
    xor  l
    and  $E0
    jr   z, LINE_PEND               ; the same row: the next byte
    scf                             ; column 31 to 0 or 0 to 31: off the screen
    ret
LINE_PEND_HIRES:
    bit  3, e
    ret  z                          ; (carry clear: AND 7)
LINE_PEND:
    set  4, e                       ; the attribute is written with the next pixel
    or   a
    ret

; ============================================================================
; GFX_WRITE_PIXEL -- set one pixel and colour it (PLOT, CIRCLE in HIRES through slot 0)
; Normal mode colours the pixel's 8x8 cell; HIRES its own 8x1 attribute byte at the bitmap byte +
; $2000. y >= 192 draws nothing.
; In:  B = x (0-255), C = y, A = attribute byte
; Out: GFX_LINE_ATTR = the attribute
; Destroys: AF, DE, HL (BC is kept)
; ============================================================================
GFX_WRITE_PIXEL:
    ld   (GFX_LINE_ATTR), a
    ld   a, c
    cp   192
    ret  nc
    ld   a, (GFX_MODE)
    add  a, a
    add  a, a
    add  a, a
    ld   e, a                       ; E bit 3: HIRES (LINE_ATTR's)
    call GFX_PIXEL_AT
    or   (hl)
    ld   (hl), a
                                    ; fall into LINE_ATTR

; ============================================================================
; LINE_ATTR -- colour the bitmap byte at HL with GFX_LINE_ATTR: Normal mode its cell's attribute,
; HIRES (E bit 3) its own attribute byte at HL + $2000
; In:  HL = the bitmap byte, E = LINE's flags
; Out: E bit 4 (the attribute pending) clear
; Destroys: AF
; ============================================================================
LINE_ATTR:
    res  4, e
    bit  3, e
    jr   nz, LINE_ATTR_BYTE
    push hl
    ld   a, h
    rrca
    rrca
    rrca
    and  3
    or   HIGH ATTR_ADDR
    ld   h, a                       ; the cell: ATTR_ADDR + the third * 256 + L
    ld   a, (GFX_LINE_ATTR)
    ld   (hl), a
    pop  hl
    ret
LINE_ATTR_BYTE:
    set  5, h
    ld   a, (GFX_LINE_ATTR)
    ld   (hl), a
    res  5, h
    ret
    ASSERT LOW ATTR_ADDR == 0 && SECOND_DISPLAY_ADDR == SCREEN_ADDR + $2000

; ============================================================================
; LINE_BRES -- one Bresenham step: r += dmin; carry if it passed dmaj (r -= dmaj): the minor axis
; steps. r, dmin, dmaj in HL', DE', BC' (r < dmaj, dmin <= dmaj: the sum's 17th bit is the carry).
; Destroys: F
; ============================================================================
LINE_BRES:
    exx
    add  hl, de
    jr   c, .over
    sbc  hl, bc
    jr   nc, .step
    add  hl, bc
    exx
    or   a
    ret
.over:
    or   a
    sbc  hl, bc
.step:
    exx
    scf
    ret

; LINE_DELTA -- HL = |HL - DE| (signed operands, 0-65535), carry if HL < DE. Destroys: AF, DE
LINE_DELTA:
    ld   a, h
    xor  $80
    ld   h, a
    ld   a, d
    xor  $80
    ld   d, a                       ; offset: the unsigned order is the signed one
    or   a
    sbc  hl, de
    ret  nc
    xor  a
    sub  l
    ld   l, a
    sbc  a, a
    sub  h
    ld   h, a
    scf
    ret

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
