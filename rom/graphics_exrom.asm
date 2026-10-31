; ============================================================================
; rom/graphics_exrom.asm -- the EXROM image: graphics, shapes, sprites and the EDIT view
;
; A standalone 8K image (chunk 5, $A000-$BFFF once paged in), assembled and saved apart from
; rom/forth_boot.asm. It is reached only through the Home-side stubs in core/*.asm, which page
; chunk 5 in (kernel/bank/bank.asm), verify the magic+ABI pair after the service table, dispatch
; through the table, and page out again.
;
; The service table is append-only and fixed in size (GRAPHICS_EXROM_MAX_SLOTS slots, all
; reserved up front), so a Home-side caller built against an older image still finds each
; service at the same slot, and the magic+ABI pair after the table never moves.
;
; This image cannot call the Home graphics routines by address: they move whenever the Home
; dictionary changes. It calls them through GRAPHICS_HOME_TABLE (rom/forth_boot.asm, fixed at
; $0100), whose layout tools/export_home_symbols.py writes to build/graphics_home_table.inc, which
; is INCLUDEd below. The Makefile's graphics-exrom target regenerates it; never edit it.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $A000

    INCLUDE "include/forth_layout.inc"
    INCLUDE "include/graphics_exrom_abi.inc"

; ---- Home-side stable call targets (rom/forth_boot.asm, $0100), generated ----
    INCLUDE "build/graphics_home_table.inc"

; ============================================================================
; Service table -- GRAPHICS_EXROM_MAX_SLOTS slots, each one JP (3 bytes). Unfilled slots point
; at GRAPHICS_EXROM_UNIMPLEMENTED, which a Home-side caller never reaches
; ============================================================================
GRAPHICS_EXROM_TABLE:
    jp   RECT_FILL_IMPL              ; slot 0 ($A000) — RECT
    jp   POLY_DRAW_IMPL              ; slot 1 ($A003) — POLYGON (outline)
    jp   SPRITE_DEFINE_IMPL          ; slot 2 ($A006) — SPRITE-DEFINE
    jp   SPRITE_SHOW_IMPL            ; slot 3 ($A009) — SPRITE-SHOW
    jp   SPRITE_HIDE_IMPL            ; slot 4 ($A00C) — SPRITE-HIDE
    jp   POLY_FILL_IMPL               ; slot 5 ($A00F) — POLYGON-FILL
    jp   VIEW_SESSION                ; slot 6 ($A012) — VIEW_SESSION (EDIT's full-screen view)
    jp   FILL_IMPL                   ; slot 7 ($A015) -- FILL
    jp   CIRCLE_IMPL                 ; slot 8 ($A018) -- CIRCLE
    jp   GRAPHICS_EXROM_UNIMPLEMENTED ; slots 9-15 reserved
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    jp   GRAPHICS_EXROM_UNIMPLEMENTED
    ASSERT $ - GRAPHICS_EXROM_TABLE == GRAPHICS_EXROM_MAX_SLOTS * 3

GRAPHICS_EXROM_UNIMPLEMENTED:
    ret

; ============================================================================
; The magic + ABI version pair, right after the fixed-size table. The Home-side caller
; (EXROM_CALL_SLOT, core/rectfill.asm) verifies it after paging in; a mismatch (no cartridge, or
; another one) makes it page out without calling anything.
; ============================================================================
    DB   GRAPHICS_EXROM_MAGIC
    DB   GRAPHICS_EXROM_ABI

; ============================================================================
; RECT_FILL_IMPL -- fill the rectangle (RECT_X0,RECT_Y0)-(RECT_X1,RECT_Y1), corners inclusive,
; with RECT_ATTR
; In:  RECT_X0/Y0/X1/Y1 (0-255 / 0-191), RECT_ATTR, staged by the Home-side RECT word
; Out: none
; Destroys: AF, BC, DE, HL
; The corners are sorted first. The pixels are always set (OR), never toggled. Each scanline's
; row base comes from one GRAPHICS_HOME_ROW_BASE_ADDR call and the span is written as at most
; three byte writes: a left partial mask, $FF for the middle bytes (propagated with LDIR;
; setting is equivalent to OR-ing $FF), and a right partial mask, or one masked byte if the span
; fits in a byte. The attribute pass then stamps each covered attribute cell once
; (GRAPHICS_HOME_CELL_ATTR_ADDR). The masks are RECT_LEFTMASK_TABLE[bit] = $FF >> bit and
; RECT_RIGHTMASK_TABLE[bit] = ($FF << (7 - bit)) & $FF.
; Y is not bounds-checked (0-191); the attribute pass skips a cell GRAPHICS_HOME_CELL_ATTR_ADDR
; reports out of range.
; ============================================================================
RECT_FILL_IMPL:
    ; ---- sort X: RECT_X0 <= RECT_X1 ----
    ld   a, (RECT_X0)
    ld   b, a
    ld   a, (RECT_X1)
    cp   b
    jr   nc, .x_ok                  ; X1 >= X0 already
    ld   (RECT_X0), a               ; swap
    ld   a, b
    ld   (RECT_X1), a
.x_ok:

    ; ---- sort Y: RECT_Y0 <= RECT_Y1 ----
    ld   a, (RECT_Y0)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jr   nc, .y_ok
    ld   (RECT_Y0), a
    ld   a, b
    ld   (RECT_Y1), a
.y_ok:

    ; ---- col0/bit0, col1/bit1 from the sorted X0/X1 ----
    ld   a, (RECT_X0)
    ld   b, a
    and  %00000111
    ld   (RECT_BIT0), a
    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111
    ld   (RECT_COL0), a

    ld   a, (RECT_X1)
    ld   b, a
    and  %00000111
    ld   (RECT_BIT1), a
    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111
    ld   (RECT_COL1), a

    ; ---- bitmap pass: one scanline at a time, Y0..Y1 ----
    ld   a, (RECT_Y0)
    ld   (RECT_CUR_Y), a
.bmp_row_loop:
    ld   a, (RECT_CUR_Y)
    ld   b, a
    and  %00000111
    ld   c, a                        ; C = scanline (0-7) in its char row; the call keeps BC
    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111                   ; a = char_row (0-23)
    call GRAPHICS_HOME_ROW_BASE_ADDR ; HL = the char row's bitmap base, at scanline 0
    ld   a, h
    add  a, c                        ; a scanline down is +256
    ld   h, a                        ; HL = ROWBASE, this scanline's column-0 byte
    ld   (RECT_ROWBASE), hl

    ; ---- first (possibly only) byte: ROWBASE + col0 ----
    ld   hl, (RECT_ROWBASE)
    ld   a, (RECT_COL0)
    add  a, l
    ld   l, a
    jr   nc, .no_carry_first
    inc  h
.no_carry_first:
    ld   a, (RECT_COL0)
    ld   b, a
    ld   a, (RECT_COL1)
    cp   b
    jr   nz, .multi_byte

    ; ---- single byte: mask = LEFTMASK[bit0] & RIGHTMASK[bit1] ----
    push hl                          ; HL = the target byte; the mask lookups destroy HL
    ld   a, (RECT_BIT0)
    call RECT_LEFTMASK
    ld   b, a
    ld   a, (RECT_BIT1)
    call RECT_RIGHTMASK
    and  b
    ld   b, a
    pop  hl
    ld   a, (hl)
    or   b
    ld   (hl), a
    jr   .bmp_row_done

.multi_byte:
    ; ---- left partial byte: OR LEFTMASK[bit0] into (hl) ----
    push hl
    ld   a, (RECT_BIT0)
    call RECT_LEFTMASK
    ld   b, a
    pop  hl
    ld   a, (hl)
    or   b
    ld   (hl), a

    ; ---- middle full bytes, if any: col0+1 .. col1-1, all $FF ----
    ld   a, (RECT_COL1)
    ld   b, a
    ld   a, (RECT_COL0)
    neg
    add  a, b                        ; A = col1 - col0, >= 1 here (X0 <= X1 and col1 != col0)
    dec  a                           ; A = the full middle bytes, col1 - col0 - 1; 0: none
    ld   b, a
    or   a
    jr   z, .no_middle

    ld   hl, (RECT_ROWBASE)
    ld   b, a                        ; B = the middle count (A is reused below)
    ld   a, (RECT_COL0)
    inc  a
    add  a, l                        ; HL = ROWBASE + col0 + 1, the first middle byte
    ld   l, a
    jr   nc, .no_carry_mid
    inc  h
.no_carry_mid:
    ld   (hl), $FF                   ; seed the first middle byte
    ld   a, b
    dec  a
    jr   z, .no_middle                ; one middle byte only: nothing to propagate
    ld   c, a
    ld   b, 0                        ; BC = the remaining middle bytes
    push hl
    pop  de
    inc  de                          ; DE = HL + 1: LDIR copies the seeded $FF forward
    ldir
.no_middle:

    ; ---- right partial byte: ROWBASE + col1, recomputed (HL/DE are past the LDIR) ----
    ld   hl, (RECT_ROWBASE)
    ld   a, (RECT_COL1)
    add  a, l
    ld   l, a
    jr   nc, .no_carry_last
    inc  h
.no_carry_last:
    push hl
    ld   a, (RECT_BIT1)
    call RECT_RIGHTMASK
    ld   b, a
    pop  hl
    ld   a, (hl)
    or   b
    ld   (hl), a

.bmp_row_done:
    ld   a, (RECT_CUR_Y)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jr   z, .attr_pass
    ld   a, (RECT_CUR_Y)
    inc  a
    ld   (RECT_CUR_Y), a
    jp   .bmp_row_loop

    ; ---- attribute pass: each covered cell once; char rows Y0>>3..Y1>>3, columns COL0..COL1 ----
.attr_pass:
    ld   a, (RECT_Y0)
    rrca
    rrca
    rrca
    and  %00011111
    ld   (RECT_ATTR_ROW), a
    ld   a, (RECT_Y1)
    rrca
    rrca
    rrca
    and  %00011111
    ld   (RECT_ATTR_ROW1), a
.attr_row_loop:
    ld   a, (RECT_COL0)
    ld   (RECT_ATTR_COL), a
.attr_col_loop:
    ld   a, (RECT_ATTR_ROW)
    ld   b, a
    ld   a, (RECT_ATTR_COL)
    ld   c, a
    call GRAPHICS_HOME_CELL_ATTR_ADDR  ; HL = the attribute address; carry: out of range
    jr   c, .attr_col_next
    ld   a, (RECT_ATTR)
    ld   (hl), a
.attr_col_next:
    ld   a, (RECT_ATTR_COL)
    ld   b, a
    ld   a, (RECT_COL1)
    cp   b
    jr   z, .attr_col_done
    ld   a, (RECT_ATTR_COL)
    inc  a
    ld   (RECT_ATTR_COL), a
    jr   .attr_col_loop
.attr_col_done:
    ld   a, (RECT_ATTR_ROW)
    ld   b, a
    ld   a, (RECT_ATTR_ROW1)
    cp   b
    jr   z, .attr_row_done
    ld   a, (RECT_ATTR_ROW)
    inc  a
    ld   (RECT_ATTR_ROW), a
    jr   .attr_row_loop
.attr_row_done:
    ret

; ============================================================================
; RECT_LEFTMASK / RECT_RIGHTMASK -- the partial-byte masks of RECT_FILL_IMPL, by table lookup
; In:  A = bit position (0-7)
; Out: A = RECT_LEFTMASK_TABLE[A] (the pixels A..7) / RECT_RIGHTMASK_TABLE[A] (the pixels 0..A)
; Destroys: AF, DE, HL
; ============================================================================
RECT_LEFTMASK:
    ld   e, a
    ld   d, 0
    ld   hl, RECT_LEFTMASK_TABLE
    add  hl, de
    ld   a, (hl)
    ret

RECT_RIGHTMASK:
    ld   e, a
    ld   d, 0
    ld   hl, RECT_RIGHTMASK_TABLE
    add  hl, de
    ld   a, (hl)
    ret

RECT_LEFTMASK_TABLE:
    DB   %11111111, %01111111, %00111111, %00011111
    DB   %00001111, %00000111, %00000011, %00000001
RECT_RIGHTMASK_TABLE:
    DB   %10000000, %11000000, %11100000, %11110000
    DB   %11111000, %11111100, %11111110, %11111111

; ============================================================================
; POLY_DRAW_IMPL -- draw the closed outline through the POLY_COUNT vertices of POLY_VERTS
; In:  POLY_COUNT (3-POLY_MAXPTS), POLY_VERTS (that many (x,y) pairs), POLY_ATTR, staged by the
;      Home-side POLYGON word
; Out: none; a POLY_COUNT out of range draws nothing
; Destroys: AF, BC, DE, HL
; One GFX_LINE (GRAPHICS_HOME_LINE) per edge, vertex i to i+1, the last back to vertex 0.
; ============================================================================
POLY_DRAW_IMPL:
    ld   a, (POLY_COUNT)
    cp   3
    jp   c, .done                   ; fewer than 3 points: nothing to draw
    cp   POLY_MAXPTS + 1
    jp   nc, .done                  ; too many points: nothing

    xor  a
    ld   (POLY_IDX), a               ; i = 0
.edge_loop:
    ; ---- vertex i -> GFX_LINE_X0/Y0 ----
    ld   a, (POLY_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_VERTS
    add  hl, de
    add  hl, de                      ; hl = POLY_VERTS + 2*i
    ld   a, (hl)
    ld   (GFX_LINE_X0), a
    inc  hl
    ld   a, (hl)
    ld   (GFX_LINE_Y0), a

    ; ---- vertex j = (i+1), wrapping to 0 at POLY_COUNT -> GFX_LINE_X1/Y1 ----
    ld   a, (POLY_IDX)
    inc  a
    ld   b, a
    ld   a, (POLY_COUNT)
    cp   b
    jr   nz, .no_wrap
    ld   b, 0                        ; i+1 == count: wrap to vertex 0
.no_wrap:
    ld   a, b
    ld   e, a
    ld   d, 0
    ld   hl, POLY_VERTS
    add  hl, de
    add  hl, de                      ; hl = POLY_VERTS + 2*j
    ld   a, (hl)
    ld   (GFX_LINE_X1), a
    inc  hl
    ld   a, (hl)
    ld   (GFX_LINE_Y1), a

    ld   a, (POLY_ATTR)
    ld   (GFX_LINE_ATTR), a
    xor  a
    ld   (GFX_LINE_OVER), a
    call GRAPHICS_HOME_LINE

    ld   a, (POLY_IDX)
    inc  a
    ld   (POLY_IDX), a
    ld   b, a
    ld   a, (POLY_COUNT)
    cp   b
    jr   nz, .edge_loop              ; i < count: draw the next edge
.done:
    ret

; ============================================================================
; SPRITE_TRANSFER_IMPL -- copy the SPRITE_CELLS x SPRITE_CELLS cells between the screen and a buffer
; In:  SPRITE_OP_ROW/COL (the top-left character position, 0-23 / 0-31; the caller keeps +1 in
;      range, nothing is checked), SPRITE_OP_BUF (the buffer), SPRITE_OP_DIR (0 = screen ->
;      buffer, nonzero = buffer -> screen)
; Out: none
; Destroys: AF, BC, DE, HL (writes SPRITE_OP_PTR/CELL, SPRITE_CELL_ROW/COL)
; Each cell is a raw copy of 9 bytes (8 bitmap scanlines + the attribute byte; see
; SPRITE_SLOT_BYTES in include/forth_layout.inc). The cell offsets come from SPRITE_CELL_OFFSETS. The
; Home veneers destroy DE, so SPRITE_OP_PTR is reloaded from memory after each call.
; ============================================================================
SPRITE_TRANSFER_IMPL:
    ld   hl, (SPRITE_OP_BUF)
    ld   (SPRITE_OP_PTR), hl
    xor  a
    ld   (SPRITE_OP_CELL), a
.cell_loop:
    ld   a, (SPRITE_OP_CELL)
    ld   l, a
    ld   h, 0
    add  hl, hl                      ; hl = cell*2 (2 bytes/table entry)
    ld   de, SPRITE_CELL_OFFSETS
    add  hl, de
    ld   a, (hl)                     ; row offset
    ld   d, a
    inc  hl
    ld   a, (hl)                     ; col offset
    ld   e, a                        ; D = row offset, E = col offset

    ld   a, (SPRITE_OP_ROW)
    add  a, d
    ld   (SPRITE_CELL_ROW), a
    ld   a, (SPRITE_OP_COL)
    add  a, e
    ld   (SPRITE_CELL_COL), a

    ; ---- this cell's bitmap address, scanline 0 ----
    ld   a, (SPRITE_CELL_ROW)
    call GRAPHICS_HOME_ROW_BASE_ADDR ; hl = row base (destroys DE)
    ld   a, (SPRITE_CELL_COL)
    ld   e, a
    ld   d, 0
    add  hl, de                      ; hl = bitmap address, scanline 0

    ld   b, 8                        ; 8 scanlines/cell
.scan_loop:
    ld   de, (SPRITE_OP_PTR)         ; reloaded fresh every iteration
    ld   a, (SPRITE_OP_DIR)
    or   a
    jr   nz, .blit_scan
    ld   a, (hl)                     ; capture: screen -> buffer
    ld   (de), a
    jr   .scan_done
.blit_scan:
    ld   a, (de)                     ; blit: buffer -> screen
    ld   (hl), a
.scan_done:
    inc  de
    ld   (SPRITE_OP_PTR), de
    inc  h                           ; next scanline: +256
    djnz .scan_loop

    ; ---- attribute byte, 9th byte of this cell ----
    ld   a, (SPRITE_CELL_ROW)
    ld   b, a
    ld   a, (SPRITE_CELL_COL)
    ld   c, a
    call GRAPHICS_HOME_CELL_ATTR_ADDR ; hl = attr address (destroys DE)
    ld   de, (SPRITE_OP_PTR)          ; reloaded: the call destroyed DE
    ld   a, (SPRITE_OP_DIR)
    or   a
    jr   nz, .blit_attr
    ld   a, (hl)
    ld   (de), a
    jr   .attr_done
.blit_attr:
    ld   a, (de)
    ld   (hl), a
.attr_done:
    inc  de
    ld   (SPRITE_OP_PTR), de

    ld   a, (SPRITE_OP_CELL)
    inc  a
    ld   (SPRITE_OP_CELL), a
    cp   SPRITE_CELLS * SPRITE_CELLS
    jr   c, .cell_loop
    ret

SPRITE_CELL_OFFSETS: DB 0,0, 0,1, 1,0, 1,1

; ============================================================================
; SPRITE_DEFINE_IMPL -- capture the screen area at (SPRITE_OP_ROW, SPRITE_OP_COL) into the
; slot's image buffer
; In:  SPRITE_OP_SLOT (0-SPRITE_SLOT_MAX-1), SPRITE_OP_ROW/COL, staged by the Home-side word
; Out: the slot's SPRITE_SLOT_DEFINED flag set; an out-of-range slot does nothing
; Destroys: AF, BC, DE, HL
; ============================================================================
SPRITE_DEFINE_IMPL:
    ld   a, (SPRITE_OP_SLOT)
    cp   SPRITE_SLOT_MAX
    ret  nc                          ; out-of-range slot: nothing
    call SPRITE_BUF_ADDR_IMG         ; hl = this slot's own image buffer
    ld   (SPRITE_OP_BUF), hl
    xor  a
    ld   (SPRITE_OP_DIR), a          ; 0 = capture
    call SPRITE_TRANSFER_IMPL

    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_DEFINED
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   (hl), 1
    ret

; ============================================================================
; SPRITE_SHOW_IMPL -- save the screen at (SPRITE_OP_ROW, SPRITE_OP_COL) as the slot's background,
; then draw the slot's image over it
; In:  SPRITE_OP_SLOT, SPRITE_OP_ROW/COL, staged by the Home-side word
; Out: the slot's position recorded, its SPRITE_SLOT_SHOWN flag set. Nothing happens for an
;      out-of-range slot, one never defined, or one already shown (HIDE then SHOW to move it)
; Destroys: AF, BC, DE, HL
; ============================================================================
SPRITE_SHOW_IMPL:
    ld   a, (SPRITE_OP_SLOT)
    cp   SPRITE_SLOT_MAX
    ret  nc

    call SPRITE_FLAG_ADDR_DEFINED
    ld   a, (hl)
    or   a
    ret  z                           ; never DEFINEd: refuse

    call SPRITE_FLAG_ADDR_SHOWN
    ld   a, (hl)
    or   a
    ret  nz                          ; already SHOWN: refuse

    ; ---- save background ----
    call SPRITE_BUF_ADDR_BG
    ld   (SPRITE_OP_BUF), hl
    xor  a
    ld   (SPRITE_OP_DIR), a          ; 0 = capture
    call SPRITE_TRANSFER_IMPL

    ; ---- blit the sprite's own image on top ----
    call SPRITE_BUF_ADDR_IMG
    ld   (SPRITE_OP_BUF), hl
    ld   a, 1
    ld   (SPRITE_OP_DIR), a          ; nonzero = blit
    call SPRITE_TRANSFER_IMPL

    ; ---- remember where, and mark shown ----
    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_ROW
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (SPRITE_OP_ROW)
    ld   (hl), a
    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_COL
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (SPRITE_OP_COL)
    ld   (hl), a

    call SPRITE_FLAG_ADDR_SHOWN
    ld   (hl), 1
    ret

; ============================================================================
; SPRITE_HIDE_IMPL -- restore the slot's saved background over where it was shown
; In:  SPRITE_OP_SLOT, staged by the Home-side word (the position is the one SHOW recorded)
; Out: the slot's SPRITE_SLOT_SHOWN flag cleared. Nothing happens for an out-of-range slot or one
;      not shown
; Destroys: AF, BC, DE, HL
; ============================================================================
SPRITE_HIDE_IMPL:
    ld   a, (SPRITE_OP_SLOT)
    cp   SPRITE_SLOT_MAX
    ret  nc

    call SPRITE_FLAG_ADDR_SHOWN
    ld   a, (hl)
    or   a
    ret  z                           ; not currently SHOWN: refuse

    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_ROW
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (hl)
    ld   (SPRITE_OP_ROW), a
    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_COL
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (hl)
    ld   (SPRITE_OP_COL), a

    call SPRITE_BUF_ADDR_BG
    ld   (SPRITE_OP_BUF), hl
    ld   a, 1
    ld   (SPRITE_OP_DIR), a          ; nonzero = blit (restore)
    call SPRITE_TRANSFER_IMPL

    call SPRITE_FLAG_ADDR_SHOWN
    xor  a
    ld   (hl), a
    ret

; ============================================================================
; SPRITE_BUF_ADDR_IMG / SPRITE_BUF_ADDR_BG / SPRITE_FLAG_ADDR_DEFINED /
; SPRITE_FLAG_ADDR_SHOWN -- the address of SPRITE_OP_SLOT's image buffer, background buffer,
; defined flag, shown flag
; In:  SPRITE_OP_SLOT
; Out: HL = the address
; Destroys: AF, DE, HL
; ============================================================================
SPRITE_BUF_ADDR_IMG:
    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_BYTES
    call SPRITE_MUL_A_HL
    ld   de, SPRITE_SLOT_IMG_BUF
    add  hl, de
    ret

SPRITE_BUF_ADDR_BG:
    ld   a, (SPRITE_OP_SLOT)
    ld   hl, SPRITE_SLOT_BYTES
    call SPRITE_MUL_A_HL
    ld   de, SPRITE_SLOT_BG_BUF
    add  hl, de
    ret

SPRITE_FLAG_ADDR_DEFINED:
    ld   a, (SPRITE_OP_SLOT)
    ld   e, a
    ld   d, 0
    ld   hl, SPRITE_SLOT_DEFINED
    add  hl, de
    ret

SPRITE_FLAG_ADDR_SHOWN:
    ld   a, (SPRITE_OP_SLOT)
    ld   e, a
    ld   d, 0
    ld   hl, SPRITE_SLOT_SHOWN
    add  hl, de
    ret

; ============================================================================
; SPRITE_MUL_A_HL -- HL = A * HL, by repeated addition (A is a slot number, at most 3)
; In:  A = the multiplier, HL = the multiplicand (SPRITE_SLOT_BYTES)
; Out: HL = A * HL
; Destroys: AF, DE
; ============================================================================
SPRITE_MUL_A_HL:
    ld   e, l
    ld   d, h                        ; DE = the multiplicand
    ld   hl, 0                       ; HL = the running total
    or   a
    ret  z                           ; A = 0: HL = 0
.loop:
    add  hl, de
    dec  a
    jr   nz, .loop
    ret

; ============================================================================
; POLY_FILL_IMPL -- fill the interior of the polygon (POLY_VERTS / POLY_COUNT), even-odd rule
; In:  POLY_VERTS, POLY_COUNT, POLY_ATTR, staged by the Home-side POLYGON-FILL word
; Out: none
; Destroys: AF, BC, DE, HL
; An active-edge scanline fill: a table of the non-horizontal edges is built, then for each
; scanline every active edge's current x is a crossing, the crossings are sorted, and the span
; between each pair (1st-2nd, 3rd-4th, ...) is filled. The crossings come from the vertex
; coordinates, not from reading drawn pixels, so the fill cannot leak through a diagonal gap in
; a Bresenham outline. Concave shapes with non-integer edge ratios can be a pixel off near a
; concave vertex (the error accumulator rounds rows differently); the outline hides it.
; The edge table (POLY_FILL_EDGE_*, include/forth_layout.inc) is RAM, not scratch inside this image:
; chunk 5 is this ROM while it is paged in.
; ============================================================================
POLY_FILL_IMPL:
    ; ---- build the edge table ----
    xor  a
    ld   (POLY_FILL_NEDGES), a
    ld   a, 255
    ld   (POLY_FILL_YMIN), a
    xor  a
    ld   (POLY_FILL_YMAX), a
    ld   (POLY_IDX), a               ; i = 0 (vertex loop index)

.build_loop:
    ; ---- vertex i -> RECT_X0/RECT_Y0 (scratch: RECT never runs with POLYGON-FILL) ----
    ld   a, (POLY_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_VERTS
    add  hl, de
    add  hl, de                      ; hl = POLY_VERTS + 2*i
    ld   a, (hl)
    ld   (RECT_X0), a
    inc  hl
    ld   a, (hl)
    ld   (RECT_Y0), a

    ; ---- vertex j = (i+1) wrapping to 0 -> RECT_X1/RECT_Y1 ----
    ld   a, (POLY_IDX)
    inc  a
    ld   b, a
    ld   a, (POLY_COUNT)
    cp   b
    jr   nz, .no_wrap
    ld   b, 0
.no_wrap:
    ld   a, b
    ld   e, a
    ld   d, 0
    ld   hl, POLY_VERTS
    add  hl, de
    add  hl, de
    ld   a, (hl)
    ld   (RECT_X1), a
    inc  hl
    ld   a, (hl)
    ld   (RECT_Y1), a

    ; ---- skip horizontal edges (y0 == y1: no crossings) ----
    ld   a, (RECT_Y0)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jp   z, .build_next

    ; ---- sort so Y0 < Y1, swapping X together with Y ----
    ld   a, (RECT_Y0)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jr   nc, .y_ordered              ; Y1 >= Y0: already correctly ordered
    ld   (RECT_Y0), a                ; A = old Y1 -> new Y0
    ld   a, b
    ld   (RECT_Y1), a                ; B = old Y0 -> new Y1
    ld   a, (RECT_X0)
    ld   b, a
    ld   a, (RECT_X1)
    ld   (RECT_X0), a
    ld   a, b
    ld   (RECT_X1), a
.y_ordered:

    ; ---- store this edge's Y0/Y1/X (=X0)/DX/DY/SX/ERR=0 ----
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_Y0
    add  hl, de
    ld   a, (RECT_Y0)
    ld   (hl), a

    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_Y1
    add  hl, de
    ld   a, (RECT_Y1)
    ld   (hl), a

    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_X
    add  hl, de
    ld   a, (RECT_X0)
    ld   (hl), a

    ; dy = Y1-Y0 (always >=1: horizontal already skipped, now sorted)
    ld   a, (RECT_Y1)
    ld   b, a
    ld   a, (RECT_Y0)
    ld   c, a
    ld   a, b
    sub  c                           ; a = dy
    ld   b, a                        ; stash dy in B across the address calc
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_DY
    add  hl, de
    ld   (hl), b

    ; dx = |X1-X0|, sx = sign
    ld   a, (RECT_X1)
    ld   b, a
    ld   a, (RECT_X0)
    ld   c, a
    ld   a, b
    sub  c                           ; A = X1 - X0
    jr   nc, .dx_pos                 ; X1 >= X0
    neg                              ; |dx|
    ld   b, a                        ; B = dx
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_SX
    add  hl, de
    ld   (hl), $FF                   ; sx = -1
    jr   .dx_store
.dx_pos:
    ld   b, a                        ; B = dx
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_SX
    add  hl, de
    ld   (hl), 1                     ; sx = +1
.dx_store:
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_DX
    add  hl, de
    ld   (hl), b

    ; err = 0 (2 bytes)
    ld   a, (POLY_FILL_NEDGES)
    add  a, a                        ; ERR is 2 bytes per entry
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_ERR
    add  hl, de
    ld   (hl), 0
    inc  hl
    ld   (hl), 0

    ; ---- track ymin/ymax, advance nedges ----
    ld   a, (RECT_Y0)
    ld   hl, POLY_FILL_YMIN
    cp   (hl)
    jr   nc, .ymin_done
    ld   (hl), a
.ymin_done:
    ld   a, (RECT_Y1)
    ld   hl, POLY_FILL_YMAX
    cp   (hl)
    jr   c, .ymax_done
    ld   (hl), a
.ymax_done:
    ld   a, (POLY_FILL_NEDGES)
    inc  a
    ld   (POLY_FILL_NEDGES), a

.build_next:
    ld   a, (POLY_IDX)
    inc  a
    ld   (POLY_IDX), a
    ld   b, a
    ld   a, (POLY_COUNT)
    cp   b
    jp   nz, .build_loop

    ; ---- degenerate: no non-horizontal edges at all -- nothing to fill ----
    ld   a, (POLY_FILL_NEDGES)
    or   a
    ret  z

    ; ---- for each scanline y = YMIN to YMAX-1 (half-open) ----
    ld   a, (POLY_FILL_YMIN)
    ld   (POLY_FILL_Y), a
.row_loop:
    xor  a
    ld   (POLY_FILL_NCROSS), a
    xor  a
    ld   (POLY_FILL_I), a            ; edge loop index

.edge_loop:
    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_Y0
    add  hl, de
    ld   a, (hl)                     ; a = this edge's Y0
    ld   b, a
    ld   a, (POLY_FILL_Y)
    cp   b
    jp   c, .edge_not_active         ; y < Y0: not active yet

    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_Y1
    add  hl, de
    ld   a, (hl)                     ; a = this edge's Y1
    ld   b, a
    ld   a, (POLY_FILL_Y)
    cp   b
    jp   nc, .edge_not_active        ; y >= Y1: no longer active (half-open)

    ; ---- active: record this edge's current X as a crossing ----
    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_X
    add  hl, de
    ld   a, (hl)                     ; a = this edge's current x
    ld   c, a                        ; stash the crossing value in C
    ld   a, (POLY_FILL_NCROSS)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_CROSSINGS
    add  hl, de
    ld   (hl), c
    ld   a, (POLY_FILL_NCROSS)
    inc  a
    ld   (POLY_FILL_NCROSS), a

    ; ---- advance this edge's x for the next scanline (Bresenham, y-major):
    ; err += dx; while 2*err >= dy: x += sx, err -= dy ----
    ld   a, (POLY_FILL_I)
    add  a, a                        ; ERR is 2 bytes per entry
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_ERR
    add  hl, de                      ; HL = &ERR[i]
    ld   (POLY_FILL_ERR_ADDR), hl    ; kept for the write-back
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                     ; de = err (16-bit)

    ld   a, (POLY_FILL_I)
    ld   l, a
    ld   h, 0
    ld   bc, POLY_FILL_EDGE_DX
    add  hl, bc
    ld   a, (hl)                     ; a = dx
    ld   l, a
    ld   h, 0                        ; hl = dx, zero-extended
    add  hl, de                      ; HL = err + dx: all 16 bits (up to 191 + 255 before it is
                                     ; normalized back down)

    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    push hl                          ; save err+dx across the DY lookup
    ld   hl, POLY_FILL_EDGE_DY
    add  hl, de
    ld   a, (hl)                     ; a = dy
    pop  hl                          ; hl = err+dx again
    ld   b, 0
    ld   c, a                        ; bc = dy, zero-extended

.step_loop:
    push hl                          ; save err
    add  hl, hl                      ; HL = 2*err, SIGNED: err goes negative whenever dx is not a
                                     ; multiple of dy, and a negative 2*err would read as a huge
                                     ; unsigned value in the carry test below. So test the sign
                                     ; first: negative always means stop (dy >= 1)
    bit  7, h
    jr   nz, .step_stop              ; 2*err negative: definitely < dy
    or   a
    sbc  hl, bc                      ; carry iff 2*err < dy (both operands non-negative here)
    pop  hl                          ; restore err (un-doubled) either way
    jr   c, .step_done               ; 2*err < dy: normalization complete

    push bc                          ; save dy across the X update
    push hl                          ; save err across the X update
    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_SX
    add  hl, de
    ld   a, (hl)                     ; A = sx, +1 or -1: the add below wraps correctly
    ld   c, a
    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_X
    add  hl, de
    ld   a, (hl)
    add  a, c                        ; x += sx
    ld   (hl), a
    pop  hl                          ; restore err
    pop  bc                          ; restore dy

    or   a
    sbc  hl, bc                      ; err -= dy
    jr   .step_loop

.step_stop:
    pop  hl                          ; restore err, as on the carry path
.step_done:
    ld   a, l
    ld   de, (POLY_FILL_ERR_ADDR)
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a

.edge_not_active:
    ld   a, (POLY_FILL_I)
    inc  a
    ld   (POLY_FILL_I), a
    ld   b, a
    ld   a, (POLY_FILL_NEDGES)
    cp   b
    jp   nz, .edge_loop

    ; ---- every edge checked for this row: sort the crossings (bubble sort; at most
    ; POLY_MAXPTS of them) ----
    ld   a, (POLY_FILL_NCROSS)
    cp   2
    jp   c, .row_done                ; fewer than 2 crossings: nothing to fill
    dec  a
    ld   (POLY_FILL_PASS), a         ; passes remaining = NCROSS-1
.sort_pass:
    ld   a, (POLY_FILL_PASS)
    or   a
    jp   z, .sort_done
    xor  a
    ld   (POLY_FILL_J), a
.sort_inner:
    ld   a, (POLY_FILL_NCROSS)
    dec  a
    ld   b, a                        ; B = NCROSS - 1: j runs 0 .. NCROSS - 2
    ld   a, (POLY_FILL_J)
    cp   b
    jp   nc, .sort_inner_done        ; j >= NCROSS - 1: no j+1 left

    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_CROSSINGS
    add  hl, de
    ld   a, (hl)                     ; a = CROSSINGS[j]
    inc  hl
    ld   b, (hl)                     ; b = CROSSINGS[j+1]; hl -> [j+1]
    cp   b
    jr   c, .no_swap                 ; [j] < [j+1]: already ordered
    jr   z, .no_swap                 ; equal: nothing to do either
    ld   (hl), a                     ; [j+1] = old [j]
    dec  hl
    ld   (hl), b                     ; [j] = old [j+1]
.no_swap:
    ld   a, (POLY_FILL_J)
    inc  a
    ld   (POLY_FILL_J), a
    jp   .sort_inner
.sort_inner_done:
    ld   a, (POLY_FILL_PASS)
    dec  a
    ld   (POLY_FILL_PASS), a
    jp   .sort_pass
.sort_done:

    ; ---- fill spans: the pairs (crossings[0], [1]), ([2], [3]), ..., each half-open [x0, x1) ----
    xor  a
    ld   (POLY_FILL_I), a
.span_loop:
    ld   a, (POLY_FILL_I)
    add  a, 2
    ld   b, a                        ; b = i+2
    ld   a, (POLY_FILL_NCROSS)
    cp   b
    jp   c, .row_done                ; NCROSS < i+2: no full pair left

    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_CROSSINGS
    add  hl, de
    ld   a, (hl)
    ld   (RECT_CUR_X), a             ; RECT_CUR_X: the span-fill cursor (RECT is idle here)
    inc  hl
    ld   a, (hl)
    ld   (RECT_X1), a                ; RECT_X1: the span's exclusive right bound

.pixel_loop:
    ld   a, (RECT_X1)
    ld   b, a                        ; b = x1 (bound)
    ld   a, (RECT_CUR_X)             ; a = cur
    cp   b                           ; carry set iff cur < x1 (continue)
    jp   nc, .span_done              ; cur >= x1: this span is done

    ld   b, a                        ; b = cur (x)
    ld   a, (POLY_FILL_Y)
    ld   c, a                        ; c = y
    ld   d, 0                        ; OVER = 0: always set, never toggle
    ld   a, (POLY_ATTR)
    call GRAPHICS_HOME_WRITE_PIXEL

    ld   a, (RECT_CUR_X)
    inc  a
    ld   (RECT_CUR_X), a
    jp   .pixel_loop
.span_done:
    ld   a, (POLY_FILL_I)
    add  a, 2
    ld   (POLY_FILL_I), a
    jp   .span_loop

.row_done:
    ld   a, (POLY_FILL_Y)
    ld   b, a
    ld   a, (POLY_FILL_YMAX)
    dec  a                           ; last valid row = YMAX-1
    cp   b
    jp   z, .all_rows_done           ; just finished the last row
    ld   a, (POLY_FILL_Y)
    inc  a
    ld   (POLY_FILL_Y), a
    jp   .row_loop
.all_rows_done:
    ret

; ============================================================================
; The line store for the full-screen view (docs/V2/EDITOR_SPEC.md
; sections 3 and 5.1). Lines are text + one terminator, STORE_START up to
; STORE_END (HOME cell); a terminator is $0D, or $8D for a line changed in
; the view (bit 7 is ignored when scanning). Lines are numbered from 0 here
; (the status row shows n + 1). Every routine below destroys the registers its
; header does not list as Out; none touches IX or IY.
; ============================================================================

; HOME's values of these two, which tools/check_ram_layout.py compares with HOME's symbols.
EDIT_MAX_LEN       EQU 128      ; core/editor.asm: the edit line's capacity
ATTR_DEFAULT       EQU $44      ; kernel/graphics/graphics.asm

; ============================================================================
; STORE_NEXT -- the line at HL.
; In:  HL = the line's address (a terminated line: the store ends with one)
; Out: DE = the line's address, HL = the next line's address, BC = its text
;      length (terminator not counted)
; Destroys: AF
; ============================================================================
STORE_NEXT:
    ld   d, h
    ld   e, l
.scan:
    ld   a, (hl)
    inc  hl
    and  $7F
    cp   13
    jr   nz, .scan
    push hl
    dec  hl
    or   a
    sbc  hl, de
    ld   b, h
    ld   c, l
    pop  hl
    ret

; ============================================================================
; STORE_LINE -- line n.
; In:  DE = n (0 to the line count; the count itself is the end of the store)
; Out: HL = the line's address (STORE_END for n = count), BC = its length (0)
; Destroys: AF, DE
; ============================================================================
STORE_LINE:
    ld   hl, STORE_START
.skip:
    ld   a, d
    or   e
    jr   z, .here
    push de
    call STORE_NEXT
    pop  de
    dec  de
    jr   .skip
.here:
    ld   bc, 0
    ld   de, (STORE_END)
    or   a
    sbc  hl, de
    add  hl, de
    ret  z                          ; the end of the store: an empty line
    push hl
    call STORE_NEXT
    pop  hl
    ret

; ============================================================================
; STORE_ROOM -- does the store take DELTA more bytes?
; In:  DE = delta (signed)
; Out: carry set if STORE_END + delta would pass STORE_LIMIT; HL = room
; Destroys: AF, BC, HL
; ============================================================================
STORE_ROOM:
    ld   a, d
    rla
    ccf
    ret  nc                         ; negative: always fits
    ld   hl, STORE_LIMIT
    ld   bc, (STORE_END)
    or   a
    sbc  hl, bc                     ; room (STORE_END never passes STORE_LIMIT)
    or   a
    sbc  hl, de                     ; carry if delta > room
    ret

; ============================================================================
; STORE_GAP -- open or close a gap: the bytes from POS to STORE_END move by
; DELTA and STORE_END follows. The one routine every change is built on.
; In:  HL = position (STORE_START to STORE_END), DE = delta (signed): positive
;      opens a gap of that size at POS; negative removes the bytes
;      [POS + delta, POS)
; Out: carry set if there is no room (STORE_END + delta > STORE_LIMIT):
;      nothing changed; else carry clear
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_GAP:
    ld   a, d
    or   e
    ret  z                          ; no change
    ld   (VIEW_T1), hl
    ld   (VIEW_T2), de
    call STORE_ROOM
    ret  c
    ld   hl, (STORE_END)
    ld   de, (VIEW_T1)
    or   a
    sbc  hl, de
    ld   b, h
    ld   c, l                       ; bc = bytes to move
    ld   hl, (VIEW_T1)              ; closing: from POS
    ld   de, (VIEW_T2)
    ld   a, d
    rla
    jr   c, .go
    ld   hl, (STORE_END)            ; opening: from the last byte down
    dec  hl
.go:
    push hl
    add  hl, de
    ex   de, hl                     ; de = the destination
    pop  hl                         ; hl = the source
    ld   a, b
    or   c
    jr   z, .end                    ; nothing to move
    ld   a, (VIEW_T2 + 1)
    rla
    jr   c, .down
    lddr
    jr   .end
.down:
    ldir
.end:
    ld   hl, (STORE_END)
    ld   de, (VIEW_T2)
    add  hl, de
    ld   (STORE_END), hl
    or   a
    ret

; ============================================================================
; STORE_REPLACE -- replace a line's text by EDIT_BUF (EDIT_LEN bytes) and mark
; it ($8D). Unconditional: the caller decides whether the line changed.
; In:  HL = the line's address, BC = its text length
; Out: carry set if the new text does not fit: nothing changed; else clear
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_REPLACE:
    push hl
    add  hl, bc                     ; the terminator
    ld   a, (EDIT_LEN)
    ld   e, a
    ld   d, 0
    ex   de, hl                     ; hl = new length, de = the terminator
    or   a
    sbc  hl, bc                     ; hl = delta
    ex   de, hl                     ; hl = the terminator, de = delta
    call STORE_GAP
    pop  de
    ret  c
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   c, a
    ld   b, 0
    or   a
    jr   z, .mark
    ldir
.mark:
    ld   a, $8D
    ld   (de), a
    or   a
    ret

; ============================================================================
; STORE_INSERT -- a new empty line, marked ($8D), at an address.
; In:  HL = the address (a line's, or STORE_END for a new last line)
; Out: carry set if there is no room: nothing changed; else clear
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_INSERT:
    push hl
    ld   de, 1
    call STORE_GAP
    pop  hl
    ret  c
    ld   (hl), $8D
    ret

; ============================================================================
; STORE_DELETE -- remove a line, terminator included.
; In:  HL = the line's address, BC = its text length
; Out: carry clear
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_DELETE:
    ld   a, c
    cpl
    ld   e, a
    ld   a, b
    cpl
    ld   d, a                       ; de = -(length + 1)
    add  hl, bc
    inc  hl                         ; the next line
    jp   STORE_GAP

; ============================================================================
; The full-screen view (docs/V2/EDITOR_SPEC.md section 5.1).
; Home's EDIT (core/edit.asm) calls VIEW_SESSION through service slot 6; the
; session runs here, with this image paged in, until BREAK. The cursor line is
; copied to EDIT_BUF and edited by the console's own engine (Home, through the
; GRAPHICS_HOME_TABLE veneers); every other line is drawn in place from the
; store. Home draws nothing, the console's keys are Home's; this file owns the
; layout, the redraw and the keys the engine does not know (UP, DOWN, ENTER,
; insert-line, delete-line, BREAK, DELETE at column 0).
; Result (VIEW_RESULT, set to 0 by Home before the call): 1 name not found,
; 2 refused (the message is printed), 3 session done.
; ============================================================================
    INCLUDE "include/keys.inc"

VIEW_MSG_LONG:     DB "LONG LINE", 13, 0
VIEW_MSG_FULL:     DB "STORE FULL", 13, 0      ; also the status row's text (10)
VIEW_COLON:        DB 1, ":"                   ; counted, like WORD_BUF

; ============================================================================
; VIEW_SESSION (service slot 6)
; In:  WORD_BUF = the name after EDIT (count 0: bare EDIT); the console's line
;      is still in EDIT_BUF/EDIT_LEN
; Out: VIEW_RESULT
; Refusals, in this order, change nothing: an unterminated tail, a line over
; EDIT_MAX_LEN or needing a 5th row (LONG LINE), no `: name` line (result 1,
; Home prints `name ?`). Bare EDIT adds an empty marked line after the last
; (no room: STORE FULL).
; ============================================================================
VIEW_SESSION:
    ld   hl, (STORE_END)
    ld   de, STORE_START
    or   a
    sbc  hl, de
    add  hl, de
    jr   z, .counting               ; an empty store
    dec  hl
    ld   a, (hl)
    and  $7F
    cp   13
    jr   nz, .long                  ; the last line has no terminator
.counting:
    ld   hl, 0
    ld   (VIEW_COUNT), hl
    ld   (VIEW_FOUND), hl
    ld   hl, STORE_START
    ld   (VIEW_PTR), hl
.scan:
    ld   hl, (VIEW_PTR)
    ld   de, (STORE_END)
    or   a
    sbc  hl, de
    jr   z, .scanned
    add  hl, de
    call STORE_NEXT                 ; de = line, hl = next, bc = length
    ld   (VIEW_PTR), hl
    ld   (VIEW_T1), de
    ld   a, b
    or   a
    jr   nz, .long
    ld   a, c
    cp   EDIT_MAX_LEN + 1
    jr   nc, .long
    ld   (VIEW_T2), a
    ex   de, hl
    ld   c, $FF
    call GRAPHICS_HOME_WRAP_CALC_AT
    ld   a, (FWRAP_OVERFLOW)
    or   a
    jr   nz, .long                  ; needs a 5th row
    ld   a, (WORD_BUF)
    or   a
    jr   z, .counted
    ld   hl, (VIEW_T1)
    ld   a, (VIEW_T2)
    ld   c, a
    call VIEW_MATCH
.counted:
    ld   hl, (VIEW_COUNT)
    inc  hl
    ld   (VIEW_COUNT), hl
    jr   .scan
.long:
    ld   hl, VIEW_MSG_LONG
.refuse:
    call GRAPHICS_HOME_FORGET_PRINT_MSG
    ld   a, 2
    ld   (VIEW_RESULT), a
    ret
.scanned:
    ld   a, (WORD_BUF)
    or   a
    jr   z, .bare
    ld   hl, (VIEW_FOUND)
    ld   a, h
    or   l
    jr   nz, .named
    inc  a                          ; a = 1: not found
    ld   (VIEW_RESULT), a
    ret
.named:
    dec  hl
    ld   (VIEW_CUR), hl
    jr   .open
.bare:
    ld   hl, (STORE_END)
    call STORE_INSERT
    ld   hl, VIEW_MSG_FULL
    jr   c, .refuse
    ld   hl, (VIEW_COUNT)
    ld   (VIEW_CUR), hl
    inc  hl
    ld   (VIEW_COUNT), hl
.open:
    ld   hl, (VIEW_CUR)
    ld   de, 22
    or   a
    sbc  hl, de
    jr   nc, .top
    ld   hl, 0
.top:
    ld   (VIEW_TOP), hl             ; room for the cursor line above is found by VIEW_FIT
    ld   hl, 0
    ld   (VIEW_CELL), hl
    xor  a
    ld   (VIEW_MSG), a
    ld   (VIEW_OLDMSG), a
    call VIEW_LOAD
    call VIEW_FIT
    call VIEW_REDRAW_ALL
.key:
    call GRAPHICS_HOME_IO_READ_KEY
    call VIEW_KEY
    jr   nc, .key
    ld   a, 3
    ld   (VIEW_RESULT), a
    ret

; ============================================================================
; VIEW_WORD_EQ -- a word of a stored line against a counted name, without case.
; In:  DE = the word (bytes above space), C = its length, HL = counted string
;      (upper case: WORD_BUF, VIEW_COLON)
; Out: Z if equal
; Destroys: AF, HL (BC, DE kept)
; ============================================================================
VIEW_WORD_EQ:
    push bc
    push de
    ld   a, (hl)
    cp   c
    jr   nz, .out
    inc  hl
.char:
    ld   a, (de)
    cp   "a"
    jr   c, .cmp
    cp   "z" + 1
    jr   nc, .cmp
    sub  "a" - "A"
.cmp:
    cp   (hl)
    jr   nz, .out
    inc  hl
    inc  de
    dec  c
    jr   nz, .char
.out:
    pop  de
    pop  bc
    ret

; ============================================================================
; VIEW_MATCH -- does a stored line hold the words `:` and WORD_BUF's name next
; to each other? (words are runs of bytes above space)
; In:  HL = the line's text, C = its length, VIEW_COUNT = the line's index
; Out: VIEW_FOUND = index + 1 if it does (else unchanged)
; Destroys: AF, BC, DE, HL, VIEW_FLAG
; ============================================================================
VIEW_MATCH:
    ld   b, c
    xor  a
    ld   (VIEW_FLAG), a             ; the word before was `:`
.next:
    ld   a, b
    or   a
    ret  z
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .word
    inc  hl
    dec  b
    jr   .next
.word:
    ld   d, h
    ld   e, l
    ld   c, 0
.len:
    inc  c
    inc  hl
    dec  b
    jr   z, .end
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .len
.end:
    push hl
    push bc
    ld   a, (VIEW_FLAG)
    or   a
    jr   z, .colon
    ld   hl, WORD_BUF
    call VIEW_WORD_EQ
    jr   z, .hit
.colon:
    ld   hl, VIEW_COLON
    call VIEW_WORD_EQ
    ld   a, 0
    jr   nz, .set
    inc  a
.set:
    ld   (VIEW_FLAG), a
    pop  bc
    pop  hl
    jr   .next
.hit:
    pop  bc
    pop  hl
    ld   hl, (VIEW_COUNT)
    inc  hl
    ld   (VIEW_FOUND), hl
    ret

; ============================================================================
; VIEW_LOAD -- the cursor line into the engine's edit line, cursor at 0.
; In:  VIEW_CUR
; Out: EDIT_BUF, EDIT_LEN, EDIT_CURSOR
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_LOAD:
    ld   de, (VIEW_CUR)
    call STORE_LINE
    ld   a, c
    ld   (EDIT_LEN), a
    ld   de, EDIT_BUF
    or   a
    jr   z, .done
    ldir
.done:
    xor  a
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; VIEW_LEAVE -- write the cursor line back to the store if it changed (it is
; marked $8D), after checking that the caller's EXTRA bytes fit too: all or
; nothing, so a refused ENTER changes nothing.
; In:  A = bytes the caller adds to the store right after (0 or 1)
; Out: carry set if there is no room: VIEW_MSG set, nothing changed; else clear
; Destroys: AF, BC, DE, HL, VIEW_PTR, VIEW_T1, VIEW_FLAG
; ============================================================================
VIEW_LEAVE:
    ld   (VIEW_EXTRA), a
    xor  a
    ld   (VIEW_FLAG), a             ; 1: the text differs from the store's
    ld   de, (VIEW_CUR)
    call STORE_LINE
    ld   (VIEW_PTR), hl
    ld   (VIEW_T1), bc              ; the stored length
    ld   a, (EDIT_LEN)
    cp   c
    jr   nz, .changed
    or   a
    jr   z, .room
    ld   b, a
    ld   de, EDIT_BUF
.cmp:
    ld   a, (de)
    cp   (hl)
    jr   nz, .changed
    inc  hl
    inc  de
    djnz .cmp
    jr   .room
.changed:
    ld   a, 1
    ld   (VIEW_FLAG), a
.room:
    ld   hl, 0
    ld   a, (VIEW_FLAG)
    or   a
    jr   z, .extra
    ld   a, (EDIT_LEN)
    ld   l, a
    ld   bc, (VIEW_T1)
    or   a
    sbc  hl, bc                     ; the write-back's delta
.extra:
    ld   a, (VIEW_EXTRA)
    ld   e, a
    ld   d, 0
    add  hl, de
    ex   de, hl
    call STORE_ROOM
    jr   c, .full
    ld   a, (VIEW_FLAG)
    or   a
    ret  z
    ld   hl, (VIEW_PTR)
    ld   bc, (VIEW_T1)
    jp   STORE_REPLACE
.full:
    ld   a, 1
    ld   (VIEW_MSG), a
    scf
    ret

; ============================================================================
; VIEW_DEC -- a number as decimal text, no leading zeros.
; In:  HL = number (0-9999), DE = where to write (inside one 256-byte page)
; Out: DE = past the last digit
; Destroys: AF, BC, HL, VIEW_T1
; ============================================================================
VIEW_DEC:
    ld   a, e
    ld   (VIEW_T1), a               ; nothing written yet while E is this
    ld   bc, -1000
    call .digit
    ld   bc, -100
    call .digit
    ld   bc, -10
    call .digit
    ld   a, l
    add  a, "0"
    ld   (de), a
    inc  de
    ret
.digit:
    ld   a, "0" - 1
.sub:
    inc  a
    add  hl, bc
    jr   c, .sub
    sbc  hl, bc
    cp   "0"
    jr   nz, .put
    ld   a, (VIEW_T1)
    cp   e
    ret  z                          ; a leading zero
    ld   a, "0"
.put:
    ld   (de), a
    inc  de
    ret

; ============================================================================
; VIEW_STATUS -- row 23: `LINE n/m` (cursor line, line count), or STORE FULL
; while VIEW_MSG is set.
; Destroys: AF, BC, DE, HL, VIEW_T1
; ============================================================================
VIEW_STATUS:
    ld   a, (VIEW_MSG)
    or   a
    ld   hl, VIEW_MSG_FULL
    ld   d, 10
    jr   nz, .draw
    ld   de, VIEW_TEXT
    ld   hl, .line
    ld   bc, 5
    ldir
    ld   hl, (VIEW_CUR)
    inc  hl
    call VIEW_DEC
    ld   a, "/"
    ld   (de), a
    inc  de
    ld   hl, (VIEW_COUNT)
    call VIEW_DEC
    ld   a, e
    sub  VIEW_TEXT & $FF
    ld   d, a
    ld   hl, VIEW_TEXT
.draw:
    ld   b, 23
    jp   ED_ROW_JP
.line:
    DB   "LINE "

; ============================================================================
; VIEW_CURSOR -- take the cursor off the cell it was drawn on (VIEW_CELL) and
; draw it at the edit line's cursor, whose first row is VIEW_CROW.
; Destroys: AF, BC, DE, HL, the wrap table
; ============================================================================
VIEW_CURSOR:
    ld   a, ATTR_DEFAULT
    ld   bc, (VIEW_CELL)
    call GRAPHICS_HOME_SET_ATTR
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (VIEW_CROW)
    ld   (FWRAP_TOP), a
    call GRAPHICS_HOME_EDIT_CURSOR_TO_ROWCOL
    ld   (VIEW_CELL), bc
    jp   GRAPHICS_HOME_ED_DRAW_CURSOR

; ============================================================================
; The row shadow (docs/V2/EDITOR_SPEC.md section 5.4): for each of rows 0-22
; the line shown there and the row within it, so a redraw draws only the rows
; whose record differs from what the screen is known to hold. A record is the
; line index (2 bytes; $FFFF a blank row, $FFFE unknown) and the row (1).
; ============================================================================

; ============================================================================
; VIEW_SH_REC -- a screen row's shadow record.
; In:  A = row (0-22)
; Out: HL = its address
; Destroys: AF
; ============================================================================
VIEW_SH_REC:
    ld   l, a
    add  a, a
    add  a, l
    add  a, VIEW_SH & $FF
    ld   l, a
    ld   a, VIEW_SH >> 8
    adc  a, 0
    ld   h, a
    ret

; ============================================================================
; VIEW_SH_UNK -- records become unknown.
; In:  DE = the first record, B = how many (1-23)
; Out: DE = past the last
; Destroys: AF, B
; ============================================================================
VIEW_SH_UNK:
    ld   a, $FE
    ld   (de), a
    inc  de
    ld   a, $FF
    ld   (de), a
    inc  de
    inc  de
    djnz VIEW_SH_UNK
    ret

; ============================================================================
; VIEW_SH_MAP -- keep the shadow true when the store's lines change under it.
; In:  DE = line k, A = 0: line k's text changed (its records become unknown);
;      1: a line was inserted at k (records of k and above move up one);
;      $FF: line k was deleted (its records become unknown, those above k
;      move down one)
; Destroys: AF, BC, DE, HL, VIEW_T2
; ============================================================================
VIEW_SH_MAP:
    ld   (VIEW_T2), de
    ld   c, a
    ld   hl, VIEW_SH
    ld   b, 23
.rec:
    push hl
    ld   de, (VIEW_T2)
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a                       ; hl = the record's line
    inc  h
    jr   z, .skip                   ; blank or unknown: $FFxx
    dec  h
    or   a
    sbc  hl, de
    jr   c, .skip                   ; below k
    add  hl, de                     ; (ADD HL leaves Z)
    jr   z, .same
    ld   a, c
    or   a
    jr   z, .skip
    dec  a
    jr   z, .up
    dec  hl                         ; a line was deleted below it
    jr   .put
.up:
    inc  hl
    jr   .put
.same:
    ld   a, c
    dec  a
    jr   nz, .unk
    inc  hl                         ; inserted at k: it is k + 1 now
    jr   .put
.unk:
    ld   hl, $FFFE
.put:
    pop  de
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    inc  de
    ex   de, hl
    djnz .rec
    ret
.skip:
    pop  hl
    inc  hl
    inc  hl
    inc  hl
    djnz .rec
    ret

; ============================================================================
; VIEW_COPY_ROW -- the 8 scanlines of one screen row onto another row (the
; attributes stay: every cell but the cursor's is ATTR_DEFAULT, and
; VIEW_CURSOR resets that one).
; In:  B = source row, C = destination row
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_COPY_ROW:
    ld   a, c
    push bc
    call GRAPHICS_HOME_ROW_BASE_ADDR
    pop  bc
    push hl
    ld   a, b
    call GRAPHICS_HOME_ROW_BASE_ADDR
    pop  de
    ld   a, 8
.line:
    REPT 32
    ldi
    ENDR
    ld   bc, 224
    add  hl, bc                     ; the next scanline is 256 on
    ex   de, hl
    add  hl, bc
    ex   de, hl
    dec  a
    jr   nz, .line
    ret

; ============================================================================
; VIEW_BLANK_ROW -- a screen row blank without drawing its 32 blank cells: the
; 8 scanlines filled with zero, the attributes with ATTR_DEFAULT (what ED_ROW32
; leaves for D = 0, at a sixth of the cost).
; In:  B = row
; Out: B kept
; Destroys: AF, C, DE, HL
; ============================================================================
VIEW_BLANK_ROW:
    push bc
    ld   a, b
    call GRAPHICS_HOME_ROW_BASE_ADDR
    ld   a, 8
.line:
    push hl
    ld   (hl), 0
    ld   d, h
    ld   e, l
    inc  de
    ld   bc, 31
    ldir
    pop  hl
    inc  h                          ; the next scanline is 256 on
    dec  a
    jr   nz, .line
    pop  bc
    push bc
    ld   c, 0
    call GRAPHICS_HOME_CELL_ATTR_ADDR
    ld   (hl), ATTR_DEFAULT
    ld   d, h
    ld   e, l
    inc  de
    ld   bc, 31
    ldir
    pop  bc
    ret

; ============================================================================
; VIEW_MOVE_ROWS -- copy E rows of the screen from row B to row C, the end
; the rows move toward first.
; In:  B = first source row, C = first destination row, E = count (1-22)
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_MOVE_ROWS:
    ld   d, 1
    ld   a, c
    cp   b
    jr   c, .go                     ; up: the top row first
    ld   d, $FF                     ; down: the bottom row first
    ld   a, b
    add  a, e
    dec  a
    ld   b, a
    ld   a, c
    add  a, e
    dec  a
    ld   c, a
.go:
    push bc
    push de
    call VIEW_COPY_ROW
    pop  de
    pop  bc
    ld   a, b
    add  a, d
    ld   b, a
    ld   a, c
    add  a, d
    ld   c, a
    dec  e
    jr   nz, .go
    ret

; ============================================================================
; VIEW_SHIFT -- the top line moved: carry what the screen already holds with
; it. Moved down: the old shadow is searched for the new top line's first row,
; and the rows from there up are copied to the top of the screen; moved up by
; lines whose rows total e (at most 22): rows 0 to 22 - e are copied down by e.
; The shadow moves with the pixels; the rows vacated become unknown. Nothing
; is moved when the new top is not on the screen (down), or e is too large.
; Then the walk to draw starts at the upper of the old and new cursor lines
; (the lines above it are unchanged, so what the move carried is true), unless
; that line is off the screen; else at the top.
; In:  VIEW_TOP, VIEW_OLDTOP (different), VIEW_CUR, VIEW_OLDCUR, VIEW_CROW,
;      VIEW_OLDROW, VIEW_COUNT, the shadow
; Out: screen and shadow moved; DE = the first line to render, B = its row,
;      VIEW_STOP (never after a move down: the rows vacated at the bottom are
;      unknown)
; Destroys: AF, BC, DE, HL, VIEW_IDX, VIEW_T1, VIEW_T2, the wrap table
; ============================================================================
VIEW_SHIFT:
    ld   de, (VIEW_TOP)
    ld   hl, (VIEW_OLDTOP)
    or   a
    sbc  hl, de
    jr   nc, .up
    ld   hl, VIEW_SH
    ld   b, 0
.find:
    ld   a, (hl)
    cp   e
    jr   nz, .skip1
    inc  hl
    ld   a, (hl)
    cp   d
    jr   nz, .skip2
    inc  hl
    ld   a, (hl)
    or   a
    jr   z, .found                  ; b = the row of the new top line's first
    jr   .skip3
.skip1:
    inc  hl
.skip2:
    inc  hl
.skip3:
    inc  hl
    inc  b
    ld   a, b
    cp   23
    jr   c, .find
    jp   .whole
.found:
    ld   a, b
    or   a
    jp   z, .whole
    ld   (VIEW_T1), a               ; d: the rows the content moves up
    neg
    ld   (VIEW_T2), a               ; the rows it moves down
    ld   c, 0
    ld   a, 23
    sub  b
    ld   e, a
    call VIEW_MOVE_ROWS
    ld   a, (VIEW_T1)
    call VIEW_SH_REC                ; the records from row d ...
    ld   de, VIEW_SH_END
    ex   de, hl
    or   a
    sbc  hl, de
    ld   b, h
    ld   c, l                       ; ... to the end
    ex   de, hl
    ld   de, VIEW_SH
    ldir                            ; ... to the top; de = the first vacated
    ld   a, (VIEW_T1)
    ld   b, a
    call VIEW_SH_UNK
    jr   .start
.up:
    ld   de, (VIEW_TOP)
    ld   (VIEW_IDX), de
    xor  a
    ld   (VIEW_T1), a               ; e: the rows of the lines that came in above
.sum:
    ld   de, (VIEW_IDX)
    call VIEW_ROWS
    ld   hl, VIEW_T1
    add  a, (hl)
    ld   (hl), a
    cp   23
    jp   nc, .whole                 ; more than the screen: nothing to keep
    ld   hl, (VIEW_IDX)
    inc  hl
    ld   (VIEW_IDX), hl
    ld   de, (VIEW_OLDTOP)
    or   a
    sbc  hl, de
    jr   nz, .sum
    ld   a, (VIEW_T1)
    ld   c, a
    ld   b, 0
    ld   a, 23
    sub  c
    ld   e, a
    call VIEW_MOVE_ROWS             ; rows 0 to 22 - e down by e
    ld   a, (VIEW_T1)
    ld   c, a
    ld   a, 23
    sub  c
    call VIEW_SH_REC                ; the end of the records that move
    push hl
    ld   de, VIEW_SH
    or   a
    sbc  hl, de
    ld   b, h
    ld   c, l
    pop  hl
    dec  hl
    ld   de, VIEW_SH_END - 1
    lddr
    ld   de, VIEW_SH
    ld   a, (VIEW_T1)
    ld   (VIEW_T2), a
    ld   b, a
    call VIEW_SH_UNK
.start:
    ld   hl, (VIEW_CUR)
    ld   de, (VIEW_OLDCUR)
    or   a
    sbc  hl, de
    ld   a, (VIEW_CROW)
    jr   c, .upper
    jr   z, .upper
    ld   a, (VIEW_T2)               ; the old cursor line is the upper: its row now
    ld   hl, VIEW_OLDROW
    add  a, (hl)
    cp   23
    jr   nc, .whole
    ld   hl, (VIEW_CUR)
    jr   .stop
.upper:
    ld   de, (VIEW_CUR)
    ld   hl, (VIEW_OLDCUR)
.stop:
    ld   b, a
    ld   a, (VIEW_T2)
    rla
    jr   nc, .set
    ld   hl, $FFFF                  ; moved down: the rows vacated below are unknown
    jr   .set
.whole:
    ld   hl, $FFFF
    ld   de, (VIEW_TOP)
    ld   b, 0
.set:
    ld   (VIEW_STOP), hl
    ret

; ============================================================================
; VIEW_RENDER -- draw the lines from one line down, only the rows whose
; shadow record differs from (line, row), and update the record. Each line is
; wrapped once: the cursor line by WRAP_CALC from EDIT_BUF (E10's row
; included), the others by WRAP_CALC_AT from the store; a last line that does
; not fit is cut at row 22. After the last line the blank rows are drawn
; where the shadow does not already say blank. The walk stops early, after a
; line past VIEW_STOP, when the shadow shows the next line's first row where
; the walk has reached (the rows below are then what they were). Sets
; VIEW_CROW/VIEW_CROWS when it passes the cursor line.
; In:  DE = the first line's index, B = its screen row, VIEW_STOP
; Destroys: AF, BC, DE, HL, VIEW_PTR, VIEW_IDX, VIEW_ROW, VIEW_T1, VIEW_T2,
;      VIEW_FLAG, the wrap table
; ============================================================================
VIEW_RENDER:
    ld   a, b
    ld   (VIEW_ROW), a
    ld   (VIEW_IDX), de
    call STORE_LINE
    ld   (VIEW_PTR), hl
.line:
    ld   a, (VIEW_ROW)
    cp   23
    ret  nc
    ld   hl, (VIEW_IDX)
    ld   de, (VIEW_COUNT)
    or   a
    sbc  hl, de
    jp   z, .blank                  ; past the last line
    ld   hl, (VIEW_STOP)
    ld   de, (VIEW_IDX)
    or   a
    sbc  hl, de
    jr   nc, .wrap
    ld   a, (VIEW_ROW)              ; past VIEW_STOP: in step already?
    call VIEW_SH_REC
    ld   a, (hl)
    cp   e
    jr   nz, .wrap
    inc  hl
    ld   a, (hl)
    cp   d
    jr   nz, .wrap
    inc  hl
    ld   a, (hl)
    or   a
    ret  z
.wrap:
    ld   hl, (VIEW_PTR)
    call STORE_NEXT                 ; de = the text, hl = the next line, bc = its length
    ld   (VIEW_PTR), hl
    ld   (VIEW_T1), de
    ld   hl, (VIEW_IDX)
    ld   de, (VIEW_CUR)
    or   a
    sbc  hl, de                     ; Z: the cursor line
    ld   hl, (VIEW_T1)
    ld   a, c
    jr   nz, .stored
    ld   hl, EDIT_BUF
    ld   (VIEW_T1), hl
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (VIEW_ROW)
    ld   (VIEW_CROW), a
    ld   a, (FWRAP_COUNT)
    ld   (VIEW_CROWS), a
    jr   .count
.stored:
    ld   c, $FF
    call GRAPHICS_HOME_WRAP_CALC_AT
.count:
    ld   a, (VIEW_ROW)
    ld   c, a
    ld   a, 23
    sub  c                          ; rows left above the status row
    ld   hl, FWRAP_COUNT
    cp   (hl)
    jr   c, .cut
    ld   a, (hl)
.cut:
    ld   (VIEW_T2), a               ; the rows to show
    xor  a
    ld   (VIEW_FLAG), a             ; the row within the line
.row:
    ld   a, (VIEW_FLAG)
    ld   hl, VIEW_T2
    cp   (hl)
    jr   nc, .next
    ld   hl, VIEW_ROW
    add  a, (hl)
    ld   b, a                       ; the screen row
    call VIEW_SH_REC
    ld   de, (VIEW_IDX)
    ld   a, (hl)
    cp   e
    jr   nz, .diff
    inc  hl
    ld   a, (hl)
    cp   d
    jr   nz, .diff
    inc  hl
    ld   a, (VIEW_FLAG)
    cp   (hl)
    jr   z, .step
.diff:
    ld   a, b
    call VIEW_SH_REC
    ld   (hl), e
    inc  hl
    ld   (hl), d
    inc  hl
    ld   a, (VIEW_FLAG)
    ld   (hl), a
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   c, (hl)                    ; this row's length
    ld   hl, FWRAP_START
    add  hl, de
    ld   e, (hl)
    ld   hl, (VIEW_T1)
    add  hl, de                     ; d is still 0
    ld   d, c
    ld   a, c
    or   a
    jr   nz, .text
    call VIEW_BLANK_ROW
    jr   .step
.text:
    call ED_ROW_JP                  ; keeps B
.step:
    ld   hl, VIEW_FLAG
    inc  (hl)
    jr   .row
.next:
    ld   a, (VIEW_ROW)
    ld   hl, VIEW_T2
    add  a, (hl)
    ld   (VIEW_ROW), a
    ld   hl, (VIEW_IDX)
    inc  hl
    ld   (VIEW_IDX), hl
    jp   .line
.blank:
    ld   a, (VIEW_ROW)
.brow:
    cp   23
    ret  nc
    ld   b, a
    call VIEW_SH_REC
    ld   a, (hl)
    inc  hl
    and  (hl)
    inc  a
    jr   z, .bnext                  ; $FFFF: blank already
    ld   (hl), $FF
    dec  hl
    ld   (hl), $FF
    call VIEW_BLANK_ROW
.bnext:
    ld   a, b
    inc  a
    jr   .brow

; ============================================================================
; VIEW_FIT -- the cursor line whole on screen: VIEW_TOP is moved up to the
; cursor line if it is below it, then down a line at a time until the rows
; from the top line to the cursor line, E10's row included, are 23 or fewer.
; In:  VIEW_CUR, VIEW_TOP, EDIT_BUF/EDIT_LEN/EDIT_CURSOR
; Out: VIEW_TOP, VIEW_CROW (the cursor line's first screen row), VIEW_CROWS
; Destroys: AF, BC, DE, HL, VIEW_PTR, VIEW_IDX, VIEW_ROW, the wrap table
; ============================================================================
VIEW_FIT:
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (FWRAP_COUNT)
    ld   (VIEW_CROWS), a
    ld   hl, (VIEW_TOP)
    ld   de, (VIEW_CUR)
    or   a
    sbc  hl, de
    jr   c, .again
    ld   (VIEW_TOP), de
.again:
    ld   de, (VIEW_TOP)
    ld   (VIEW_IDX), de
    call STORE_LINE
    ld   (VIEW_PTR), hl
    xor  a
    ld   (VIEW_ROW), a              ; rows from the top line so far
.walk:
    ld   hl, (VIEW_IDX)
    ld   de, (VIEW_CUR)
    or   a
    sbc  hl, de
    jr   z, .done
    ld   hl, (VIEW_PTR)
    call STORE_NEXT
    ld   (VIEW_PTR), hl
    ex   de, hl
    ld   a, c
    ld   c, $FF
    call GRAPHICS_HOME_WRAP_CALC_AT
    ld   a, (VIEW_ROW)
    ld   hl, FWRAP_COUNT
    add  a, (hl)
    ld   (VIEW_ROW), a
    ld   hl, (VIEW_IDX)
    inc  hl
    ld   (VIEW_IDX), hl
    ld   a, (VIEW_CROWS)
    ld   hl, VIEW_ROW
    add  a, (hl)
    cp   24
    jr   c, .walk
    ld   hl, (VIEW_TOP)             ; too tall: the top line goes
    inc  hl
    ld   (VIEW_TOP), hl
    jr   .again
.done:
    ld   a, (VIEW_ROW)
    ld   (VIEW_CROW), a
    ret

; ============================================================================
; VIEW_ROWS -- the rows a stored line takes.
; In:  DE = the line's index
; Out: A = its rows (no cursor row)
; Destroys: BC, DE, HL, the wrap table
; ============================================================================
VIEW_ROWS:
    call STORE_LINE
    ld   a, c
    ld   c, $FF
    call GRAPHICS_HOME_WRAP_CALC_AT
    ld   a, (FWRAP_COUNT)
    ret

; ============================================================================
; VIEW_FIT_KEY -- VIEW_FIT after a key, without the walk from the top line.
; The lines above the old cursor line are unchanged and the cursor moved at
; most one line, so the new cursor line's first row is the old one's
; (VIEW_OLDROW) plus the rows of the line stepped over (or less those of the
; line stepped onto); then the top lines go, one at a time, until the cursor
; line is whole. The same top as VIEW_FIT's: the least scroll. Further away
; than one line (never after a key): VIEW_FIT.
; In:  VIEW_CUR, VIEW_OLDCUR, VIEW_OLDROW, VIEW_TOP, EDIT_BUF/EDIT_LEN/EDIT_CURSOR
; Out: VIEW_TOP, VIEW_CROW, VIEW_CROWS
; Destroys: AF, BC, DE, HL, VIEW_PTR, VIEW_ROW, VIEW_IDX, the wrap table
; ============================================================================
VIEW_FIT_KEY:
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (FWRAP_COUNT)
    ld   (VIEW_CROWS), a
    ld   hl, (VIEW_CUR)
    ld   de, (VIEW_OLDCUR)
    or   a
    sbc  hl, de                     ; cur - oldcur
    ld   a, (VIEW_OLDROW)
    jr   z, .have
    dec  hl
    ld   a, h
    or   l
    jr   z, .down
    inc  hl
    inc  hl
    ld   a, h
    or   l
    jp   nz, VIEW_FIT               ; not next to it
    ld   de, (VIEW_CUR)             ; one up: the line stepped onto comes off
    call VIEW_ROWS
    neg
    jr   .add
.down:
    call VIEW_ROWS                  ; one down: the old cursor line (de) is passed
.add:
    ld   hl, VIEW_OLDROW
    add  a, (hl)
.have:
    ld   (VIEW_ROW), a              ; the cursor line's first row (signed)
    add  a, a
    jr   nc, .chk
    ld   hl, (VIEW_CUR)             ; above the top line: it becomes the top
    ld   (VIEW_TOP), hl
    xor  a
    ld   (VIEW_ROW), a
.chk:
    ld   a, (VIEW_ROW)
    ld   hl, VIEW_CROWS
    add  a, (hl)
    cp   24
    jr   c, .done                   ; whole
    ld   de, (VIEW_TOP)
    ld   hl, (VIEW_CUR)
    or   a
    sbc  hl, de
    jr   z, .done
    call VIEW_ROWS                  ; the top line goes
    ld   c, a
    ld   a, (VIEW_ROW)
    sub  c
    ld   (VIEW_ROW), a
    ld   hl, (VIEW_TOP)
    inc  hl
    ld   (VIEW_TOP), hl
    jr   .chk
.done:
    ld   a, (VIEW_ROW)
    ld   (VIEW_CROW), a
    ret

; ============================================================================
; VIEW_REDRAW_ALL -- rows 0-22 from the top line, the cursor and the status
; row, from the view's state alone: every shadow record unknown, then
; VIEW_RENDER (the oracle, tools/edtest.py N9, calls this at the key wait onto
; a blank screen and compares).
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_REDRAW_ALL:
    ld   de, VIEW_SH
    ld   b, 23
    call VIEW_SH_UNK
    ld   hl, $FFFF
    ld   (VIEW_STOP), hl
    ld   de, (VIEW_TOP)
    ld   b, 0
    call VIEW_RENDER
    call VIEW_CURSOR
    jp   VIEW_STATUS

; ============================================================================
; VIEW_ROW_POS -- put the cursor on a row of the edit line at a column, or at
; the row's end if it is shorter.
; In:  B = row index in the wrap table, C = column
; Out: EDIT_CURSOR
; Destroys: AF, C, DE, HL
; ============================================================================
VIEW_ROW_POS:
    ld   e, b
    ld   d, 0
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   a, (hl)
    cp   c
    jr   nc, .col
    ld   c, a
.col:
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (hl)
    add  a, c
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; VIEW_KEY -- one key.
; In:  A = key code
; Out: carry set if the view is to be left (BREAK), else clear. The screen is
;      up to date.
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_KEY:
    ld   (VIEW_KEYCODE), a
    ld   hl, (VIEW_CUR)
    ld   (VIEW_OLDCUR), hl
    ld   hl, (VIEW_TOP)
    ld   (VIEW_OLDTOP), hl
    ld   a, (VIEW_CROW)
    ld   (VIEW_OLDROW), a
    ld   a, (VIEW_MSG)
    ld   (VIEW_OLDMSG), a
    xor  a
    ld   (VIEW_MSG), a
    ld   (VIEW_LEVEL), a
    ld   a, (VIEW_KEYCODE)
    cp   KEY_ENTER
    jr   z, .enter
    cp   KEY_CURSOR_UP
    jp   z, .updown
    cp   KEY_CURSOR_DOWN
    jp   z, .updown
    cp   KEY_INSERT_LINE
    jr   z, .insline
    cp   KEY_DELETE_LINE
    jr   z, .delline
    cp   KEY_BREAK
    jr   z, .break
    cp   KEY_DELETE
    jr   nz, .edit
    ld   a, (EDIT_CURSOR)
    or   a
    jr   nz, .edit
    ld   a, (EDIT_LEN)
    or   a
    jr   z, .delline                ; DELETE on an empty line deletes the line
    jr   .post                      ; at column 0 of a line with text: nothing
.edit:
    ld   a, (VIEW_KEYCODE)
    call GRAPHICS_HOME_EDITOR_EDIT_KEY
    jr   z, .post                   ; nothing changed
    ld   c, 2                       ; the text changed ...
    ld   a, (VIEW_KEYCODE)
    cp   KEY_CURSOR_LEFT
    jr   z, .moved
    cp   KEY_CURSOR_RIGHT
    jr   nz, .level
.moved:
    dec  c                          ; ... or only the cursor moved
.level:
    ld   a, c
    ld   (VIEW_LEVEL), a
.post:
    call VIEW_POST
    or   a
    ret
.break:
    xor  a
    call VIEW_LEAVE
    jr   c, .post                   ; no room for the write-back: stay
    scf
    ret
.enter:
    ld   a, 1
    call VIEW_LEAVE
    jr   c, .post
    ld   hl, (VIEW_CUR)
    inc  hl
    ld   (VIEW_CUR), hl
    ex   de, hl
    call STORE_LINE                 ; the line after: the new line goes before it
    jr   .insert
.insline:
    ld   a, 1
    call VIEW_LEAVE
    jr   c, .post
    ld   de, (VIEW_CUR)
    call STORE_LINE
.insert:
    call STORE_INSERT
    ld   hl, (VIEW_COUNT)
    inc  hl
    ld   (VIEW_COUNT), hl
    ld   de, (VIEW_CUR)             ; the new line's index
    ld   a, 1
    call VIEW_SH_MAP
    call VIEW_LOAD
    jr   .lines
.delline:
    ld   hl, (VIEW_COUNT)
    dec  hl
    ld   a, h
    or   l
    jr   z, .only
    ld   de, (VIEW_CUR)
    call STORE_LINE
    call STORE_DELETE
    ld   de, (VIEW_CUR)
    ld   a, $FF
    call VIEW_SH_MAP
    ld   hl, (VIEW_COUNT)
    dec  hl
    ld   (VIEW_COUNT), hl
    ld   de, (VIEW_CUR)
    or   a
    sbc  hl, de
    jr   nz, .reload
    dec  de                         ; it was the last line
    ld   (VIEW_CUR), de
.reload:
    call VIEW_LOAD
    jr   .lines
.only:
    xor  a                          ; the only line is emptied (and marked)
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
    ld   de, 0
    call STORE_LINE
    call STORE_REPLACE
    ld   de, 0
    xor  a
    call VIEW_SH_MAP                ; the line's text changed
.lines:
    ld   a, 3
    ld   (VIEW_LEVEL), a
    jp   .post

    ; UP, DOWN: a row of the wrapped line, else the previous or next line
.up_post:
    jp   .post
.updown:
    call GRAPHICS_HOME_WRAP_CALC
    xor  a
    ld   (FWRAP_TOP), a
    call GRAPHICS_HOME_EDIT_CURSOR_TO_ROWCOL    ; b = row in the line, c = column
    ld   a, (VIEW_KEYCODE)
    cp   KEY_CURSOR_UP
    jr   nz, .down
    ld   a, b
    or   a
    jr   z, .upline
    dec  b
    jr   .inrow
.down:
    inc  b
    ld   a, (FWRAP_COUNT)
    cp   b
    jr   z, .downline
.inrow:
    call VIEW_ROW_POS
    ld   a, 1
    ld   (VIEW_LEVEL), a
    jr   .up_post
.upline:
    ld   hl, (VIEW_CUR)
    ld   a, h
    or   l
    jr   z, .up_post                   ; line 1: nothing above
    ld   a, c
    ld   (VIEW_COL), a
    xor  a
    call VIEW_LEAVE
    jr   c, .up_post
    ld   hl, (VIEW_CUR)
    dec  hl
    ld   (VIEW_CUR), hl
    call VIEW_LOAD
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (FWRAP_COUNT)
    dec  a
    ld   b, a                       ; the previous line's last row
    jr   .arrive
.downline:
    ld   hl, (VIEW_CUR)
    inc  hl
    ld   de, (VIEW_COUNT)
    or   a
    sbc  hl, de
    jr   z, .up_post                   ; the last line: nothing below
    ld   a, c
    ld   (VIEW_COL), a
    xor  a
    call VIEW_LEAVE
    jr   c, .up_post
    ld   hl, (VIEW_CUR)
    inc  hl
    ld   (VIEW_CUR), hl
    call VIEW_LOAD
    call GRAPHICS_HOME_WRAP_CALC
    ld   b, 0                       ; the next line's first row
.arrive:
    ld   a, (VIEW_COL)
    ld   c, a
    call VIEW_ROW_POS
    jp   .lines

; ============================================================================
; VIEW_POST -- bring the screen up to date after a key. VIEW_LEVEL says what
; the key changed: 0 nothing, 1 the cursor, 2 the cursor line's text, 3 the
; cursor line or the set of lines. A change of the cursor line's row count
; counts as 3 (the rows of a line whose text changed become unknown in the
; shadow first). Levels 0-2 draw at most the cursor line's rows. Level 3:
; when the top line moved, the screen and shadow are shifted (VIEW_SHIFT) and
; everything is rendered from the top; else from the upper of the old and new
; cursor lines, stopping after the lower once the shadow is in step. The
; status row when the line numbers or the message changed.
; In:  VIEW_OLDCUR / VIEW_OLDTOP / VIEW_OLDROW / VIEW_OLDMSG, VIEW_LEVEL
; Destroys: AF, BC, DE, HL
; ============================================================================
VIEW_POST:
    ld   a, (VIEW_LEVEL)
    or   a
    jr   z, .status
    cp   3
    jr   z, .refit
    call GRAPHICS_HOME_WRAP_CALC
    ld   a, (FWRAP_COUNT)
    ld   hl, VIEW_CROWS
    cp   (hl)
    jr   nz, .recount
    ld   a, (VIEW_CROW)
    ld   (FWRAP_TOP), a
    ld   a, (VIEW_LEVEL)
    cp   2
    call z, GRAPHICS_HOME_ED_DRAW_ROWS
    call VIEW_CURSOR
    jr   .status
.recount:
    ld   de, (VIEW_CUR)
    ld   a, (VIEW_LEVEL)
    cp   2
    ld   a, 0
    call z, VIEW_SH_MAP             ; the text changed: its rows are not what the shadow says
.refit:
    call VIEW_FIT_KEY
    ld   hl, (VIEW_TOP)
    ld   de, (VIEW_OLDTOP)
    or   a
    sbc  hl, de
    jr   z, .same_top
    call VIEW_SHIFT
    jr   .draw
.same_top:
    ld   hl, (VIEW_CUR)
    ld   de, (VIEW_OLDCUR)
    or   a
    sbc  hl, de
    ld   a, (VIEW_CROW)
    jr   c, .cur                    ; the cursor moved up, or stayed:
    jr   z, .cur                    ; from the cursor line
    ld   hl, (VIEW_CUR)             ; moved down: from the old cursor line
    ld   (VIEW_STOP), hl
    ld   a, (VIEW_OLDROW)
    jr   .from
.cur:
    ld   hl, (VIEW_OLDCUR)
    ld   (VIEW_STOP), hl
    ld   de, (VIEW_CUR)
.from:
    ld   b, a
.draw:
    call VIEW_RENDER
    call VIEW_CURSOR
.status:
    ld   a, (VIEW_LEVEL)
    cp   3
    jr   z, .show
    ld   a, (VIEW_MSG)
    ld   hl, VIEW_OLDMSG
    cp   (hl)
    ret  z
.show:
    jp   VIEW_STATUS

; ============================================================================
; CIRCLE_IMPL (slot 8; docs/V2/FILL_CIRCLE_SPEC.md section 5)
; Draws the outline of the circle of radius GFX_CIRCLE_R about
; (GFX_CIRCLE_XC, GFX_CIRCLE_YC) in attribute GFX_CIRCLE_ATTR. The three
; numbers are signed 16-bit, staged by core/shapes.asm's CIRCLE.
;   r < 0   nothing is drawn.        r = 0   the centre point only.
; The midpoint loop of 2068-Leap-C's `circle` (libs/shapes.asm), which this is
; a port of: px = r, py = 0, err = 1 - r; while py <= px { plot the
; symmetric set; py += 1; if err < 0 { err += 2 py + 1 } else { px -= 1;
; err += 2 (py - px) + 1 } }. The symmetric set draws each point once
; (p_sym: the four points (cx +- px, cy +- py), then, unless px = py, the four
; of (py, px); p_four leaves out the second of a pair whose offset is 0), so
; a later XOR mode can use it unchanged. A point is drawn only if
; 0 <= x <= 255 and 0 <= y <= 191 as a 16-bit signed sum (the sum wraps at
; 16 bits, as Leap-C's does).
;
; The plot is here, not in HOME, for speed: in normal mode the bitmap byte is
; ORed with the pixel's mask and the attribute cell is set, straight to the
; screen. In HIRES (GFX_MODE nonzero) the point goes through the slot 0 veneer
; (GFX_WRITE_PIXEL), which already knows HIRES's per-scanline attributes.
;
; The cells GFX_CIRCLE_R, _PY and _ERR double as the loop's px, py and err;
; the loop is on 16-bit values, so r up to 32767 works (a very large radius
; costs time, not safety: each point is range-tested before it is drawn).
; Destroys: AF, BC, DE, HL
; ============================================================================
CIRCLE_IMPL:
    ld   hl, (GFX_CIRCLE_R)
    bit  7, h
    ret  nz                          ; r < 0: nothing
    ld   de, 0
    ld   (GFX_CIRCLE_PY), de         ; py = 0
    inc  de
    ex   de, hl
    or   a
    sbc  hl, de                      ; 1 - r  (carry cleared above)
    ld   (GFX_CIRCLE_ERR), hl
.loop:
    ld   hl, (GFX_CIRCLE_R)
    ld   de, (GFX_CIRCLE_PY)
    or   a
    sbc  hl, de
    ret  m                           ; px - py < 0 (signed: px reaches -1
                                     ; for r = 0, so not the carry): done
    call CIRCLE_SYM
    ld   hl, (GFX_CIRCLE_PY)
    inc  hl
    ld   (GFX_CIRCLE_PY), hl         ; py += 1
    ld   de, (GFX_CIRCLE_ERR)
    bit  7, d
    jr   nz, .inside                 ; err < 0: HL = py
    ld   hl, (GFX_CIRCLE_R)
    dec  hl
    ld   (GFX_CIRCLE_R), hl          ; px -= 1
    ex   de, hl                      ; DE = px, HL = err
    ld   hl, (GFX_CIRCLE_PY)
    or   a
    sbc  hl, de                      ; HL = py - px
.inside:
    add  hl, hl
    inc  hl                          ; 2 py + 1  or  2 (py - px) + 1
    ld   de, (GFX_CIRCLE_ERR)
    add  hl, de
    ld   (GFX_CIRCLE_ERR), hl
    jr   .loop

; CIRCLE_SYM: the points (cx +- px, cy +- py), and unless px = py also
; (cx +- py, cy +- px), each once.
CIRCLE_SYM:
    ld   hl, (GFX_CIRCLE_R)
    ld   de, (GFX_CIRCLE_PY)
    call CIRCLE_FOUR
    ld   hl, (GFX_CIRCLE_R)
    ld   de, (GFX_CIRCLE_PY)
    or   a
    sbc  hl, de
    ret  z                           ; px = py: the same four points
    ld   hl, (GFX_CIRCLE_PY)
    ld   de, (GFX_CIRCLE_R)
                                     ; fall into CIRCLE_FOUR

; CIRCLE_FOUR: (cx +- HL, cy +- DE), each once. HL = ox, DE = oy.
CIRCLE_FOUR:
    push hl
    push de
    call CIRCLE_PAIR                 ; x = cx + ox
    pop  de
    pop  hl
    ld   a, h
    or   l
    ret  z                           ; ox = 0: a single column
    xor  a
    sub  l
    ld   l, a
    sbc  a, a
    sub  h
    ld   h, a                        ; HL = -ox
                                     ; fall into CIRCLE_PAIR

; CIRCLE_PAIR: (cx + HL, cy + DE) and, unless DE = 0, (cx + HL, cy - DE).
CIRCLE_PAIR:
    ld   bc, (GFX_CIRCLE_XC)
    add  hl, bc                      ; HL = x
    ld   a, h
    or   a
    ret  nz                          ; x outside 0-255: both points
    ld   b, l                        ; B = x
    push de
    ld   hl, (GFX_CIRCLE_YC)
    add  hl, de                      ; cy + oy
    call CIRCLE_PLOT_Y
    pop  de
    ld   a, d
    or   e
    ret  z                           ; oy = 0: a single row
    ld   hl, (GFX_CIRCLE_YC)
    or   a
    sbc  hl, de                      ; cy - oy
                                     ; fall into CIRCLE_PLOT_Y

; CIRCLE_PLOT_Y: B = x (0-255), HL = signed y: plot if 0 <= y <= 191.
CIRCLE_PLOT_Y:
    ld   a, h
    or   a
    ret  nz
    ld   a, l
    cp   192
    ret  nc
    ld   c, a                        ; C = y
                                     ; fall into CIRCLE_PLOT

; CIRCLE_PLOT: B = x, C = y (in range). Keeps BC; destroys AF, DE, HL.
CIRCLE_PLOT:
    ld   a, (GFX_MODE)
    or   a
    jr   z, .normal
    push bc                          ; HIRES: the slot 0 veneer, which
    ld   a, (GFX_CIRCLE_ATTR)        ; handles its per-scanline attributes
    ld   d, 0                        ; D = OVER 0
    call GRAPHICS_HOME_WRITE_PIXEL
    pop  bc
    ret
.normal:
    ld   a, b
    and  7
    or   low CIRCLE_MASK_TABLE
    ld   e, a
    ld   d, high CIRCLE_MASK_TABLE
    ld   a, (de)
    ld   e, a                        ; E = the pixel's mask
    ld   a, c
    and  7
    ld   h, a                        ; H = y & 7
    ld   a, c
    rra
    rra
    rra
    and  $18
    or   h
    or   $40
    ld   h, a                        ; H = $40 | (y >> 3) & $18 | y & 7
    ld   a, c
    add  a, a
    add  a, a
    and  $E0
    ld   l, a                        ; L = (y << 2) & $E0
    ld   a, b
    rra
    rra
    rra
    and  $1F
    or   l
    ld   l, a                        ; L |= x >> 3
    ld   a, (hl)
    or   e
    ld   (hl), a                     ; set the pixel
    ld   a, c
    rlca
    rlca
    and  3
    or   $58
    ld   h, a                        ; the attribute cell: $58 | y >> 6, same L
    ld   a, (GFX_CIRCLE_ATTR)
    ld   (hl), a
    ret

; ============================================================================
; FILL_IMPL (slot 7; docs/V2/FILL_CIRCLE_SPEC.md section 4)
; Flood fill from the seed (GFX_FILL_X, GFX_FILL_Y: signed 16-bit) with
; attribute GFX_FILL_ATTR, 4-connected, through pixels equal to the seed pixel.
; Does nothing in HIRES (the planes overlap its attribute file) or for a seed
; outside 0-255 / 0-191. Model: docs/V2/evidence/o15_fill_model.py.
;
; Two planes in the screen's layout, shadow = screen + $1B00. The work plane A
; has 0 = fillable, 1 = not; painting sets A's bits, so seed 0 paints the screen
; itself and seed 1 (a recolour) paints the shadow = NOT screen, leaving the
; bitmap alone. B is the other plane, read only by the recovery sweep:
; painted = A AND (B XOR K), K = $FF (seed 0) or $00 (seed 1).
;   seed 0: A = screen, B = shadow = copy of screen.   AOFF = 0
;   seed 1: A = shadow = NOT screen, B = screen.        AOFF = $1B (pages)
; The seed stack ($7300-$7FFF, 1,664 x/y byte pairs) holds one seed per run.
; A pop is discarded if A already has the pixel; else the span is walked (whole
; $00 bytes 8 pixels at a time), painted with edge masks, its attribute cells
; stamped, and rows y-1 and y+1 scanned over the span for run starts. A push on
; a full stack drops the seed and sets GFX_FILL_OVF; when the stack empties with
; OVF set, FILL_SWEEP re-seeds every unpainted pixel above or below a painted
; one, and the drain repeats until a sweep seeds nothing.
; Destroys: AF, BC, DE, HL
; ============================================================================
FILL_IMPL:
    ld   a, (GFX_MODE)
    or   a
    ret  nz                          ; HIRES: nothing
    ld   hl, (GFX_FILL_X)
    ld   a, h
    or   a
    ret  nz                          ; x outside 0-255
    ld   b, l                        ; B = seed x
    ld   hl, (GFX_FILL_Y)
    ld   a, h
    or   a
    ret  nz
    ld   a, l
    cp   192
    ret  nc                          ; y outside 0-191
    ld   c, a                        ; C = seed y
    push bc
    call FILL_ROW                    ; HL = screen row base
    ld   a, b
    rrca
    rrca
    rrca
    and  $1F
    or   l
    ld   l, a                        ; HL = the seed's screen byte
    ld   a, b
    and  7
    or   low CIRCLE_MASK_TABLE
    ld   e, a
    ld   d, high CIRCLE_MASK_TABLE
    ld   a, (de)
    and  (hl)                        ; nonzero: the seed pixel is set
    ld   hl, SCREEN_ADDR
    ld   de, GFX_FILL_SHADOW
    jr   nz, .set
    xor  a
    ld   (GFX_FILL_AOFF), a          ; seed 0: shadow = copy of the screen
    ld   bc, 6144
    ldir
    jr   .planes
.set:
    ld   a, $1B
    ld   (GFX_FILL_AOFF), a          ; seed 1: shadow = NOT screen
    ld   c, 24                       ; 24 pages of 256
.page:
    ld   b, 0
.byte:
    ld   a, (hl)
    cpl
    ld   (de), a
    inc  l
    inc  e
    djnz .byte
    inc  h
    inc  d
    dec  c
    jr   nz, .page
.planes:
    xor  a
    ld   (GFX_FILL_OVF), a
    ld   hl, GFX_FILL_STACK
    ld   (GFX_FILL_SP), hl
    pop  bc
    ld   e, c
    ld   c, b
    call FILL_PUSH                   ; the seed (x = C, y = E)

; ---- drain: pop a seed, fill its span ----
.pop:
    ld   hl, (GFX_FILL_SP)
    ld   a, h
    xor  high GFX_FILL_STACK
    or   l
    jp   z, .empty
    dec  hl
    ld   c, (hl)                     ; y
    dec  hl
    ld   b, (hl)                     ; x
    ld   (GFX_FILL_SP), hl
    ld   a, c
    ld   (GFX_FILL_SY), a
    call FILL_ROW
    ld   a, (GFX_FILL_AOFF)
    add  a, h
    ld   h, a                        ; HL = work plane row base
    ld   a, b
    rrca
    rrca
    rrca
    and  $1F
    or   l
    ld   l, a                        ; HL = the seed's byte
    ld   a, b
    and  7
    or   low CIRCLE_MASK_TABLE
    ld   e, a
    ld   d, high CIRCLE_MASK_TABLE
    ld   a, (de)
    ld   c, a                        ; C = the seed pixel's mask
    ld   b, (hl)                     ; B = its byte
    and  b
    jr   nz, .pop                    ; already painted: stale seed
    push hl
    push bc

    ; ---- walk left over clear pixels: HL byte, B its value, C pixel mask ----
.lw:
    ld   a, c
    cp   $80
    jr   z, .lpre                    ; at the byte's leftmost pixel
    add  a, a
    ld   e, a
    and  b
    jr   nz, .ldone                  ; the pixel to the left is set
    ld   c, e
    jr   .lw
.lpre:
    ld   a, l
    and  $1F
    jr   z, .ldone                   ; column 0
    dec  hl
    ld   a, (hl)
    or   a
    jr   z, .lzero                   ; a whole clear byte: C stays $80
    ld   b, a
    rrca
    jr   c, .lundo                   ; its pixel 7 is set
    ld   c, 1
    jr   .lw
.lzero:
    ld   b, a
    jr   .lw
.lundo:
    inc  hl
.ldone:
    ld   (GFX_FILL_LPTR), hl
    ld   a, c
    add  a, a
    dec  a                           ; the left edge byte's mask: 2m - 1
    ld   (GFX_FILL_EL), a
    pop  bc
    pop  hl

    ; ---- walk right ----
.rw:
    ld   a, c
    cp   1
    jr   z, .rnext                   ; at the byte's rightmost pixel
    rrca
    ld   e, a
    and  b
    jr   nz, .rdone
    ld   c, e
    jr   .rw
.rnext:
    ld   a, l
    and  $1F
    cp   $1F
    jr   z, .rdone                   ; column 31
    inc  hl
    ld   a, (hl)
    or   a
    jr   z, .rzero
    ld   b, a
    rlca
    jr   c, .rundo                   ; its pixel 0 is set
    ld   c, $80
    jr   .rw
.rzero:
    ld   b, a                        ; C stays 1
    jr   .rw
.rundo:
    dec  hl
.rdone:
    ld   a, c
    neg                              ; the right edge byte's mask: -m
    ld   (GFX_FILL_ER), a

    ; ---- paint: HL = right byte; A = bytes after the first ----
    ld   de, (GFX_FILL_LPTR)
    ld   a, l
    sub  e
    ld   (GFX_FILL_SN), a
    jr   nz, .multi
    ld   a, (GFX_FILL_EL)
    ld   b, a
    ld   a, (GFX_FILL_ER)
    and  b
    or   (hl)
    ld   (hl), a
    jr   .painted
.multi:
    ld   b, a
    ld   a, (GFX_FILL_ER)
    or   (hl)
    ld   (hl), a
    dec  b
    jr   z, .first
.mid:
    dec  hl
    ld   (hl), $FF
    djnz .mid
.first:
    dec  hl
    ld   a, (GFX_FILL_EL)
    or   (hl)
    ld   (hl), a
.painted:

    ; ---- stamp the attribute cells of the span ----
    ld   a, (GFX_FILL_SY)
    rlca
    rlca
    and  3
    or   $58
    ld   h, a                        ; $58 | y >> 6
    ld   a, (GFX_FILL_LPTR)
    ld   l, a                        ; same L as the bitmap byte
    ld   a, (GFX_FILL_SN)
    inc  a
    ld   b, a
    ld   a, (GFX_FILL_ATTR)
.cell:
    ld   (hl), a
    inc  l
    djnz .cell

    ; ---- seeds from the rows above and below ----
    ld   a, (GFX_FILL_SY)
    or   a
    jr   z, .below
    dec  a
    ld   c, a
    call FILL_SCANROW
.below:
    ld   a, (GFX_FILL_SY)
    cp   191
    jp   nc, .pop
    inc  a
    ld   c, a
    call FILL_SCANROW
    jp   .pop

.empty:
    ld   a, (GFX_FILL_OVF)
    or   a
    ret  z                           ; stack empty, nothing was dropped: done
    xor  a
    ld   (GFX_FILL_OVF), a
    call FILL_SWEEP
    jp   .pop

; FILL_ROW: C = y (0-191) -> HL = screen address of column 0 of row y.
; Destroys A.
FILL_ROW:
    ld   a, c
    and  7
    ld   h, a
    ld   a, c
    rra
    rra
    rra
    and  $18
    or   h
    or   $40
    ld   h, a                        ; $40 | (y >> 3) & $18 | y & 7
    ld   a, c
    add  a, a
    add  a, a
    and  $E0
    ld   l, a                        ; (y << 2) & $E0
    ret

; FILL_PUSH: push the seed (x = C, y = E). A full stack drops it and sets
; GFX_FILL_OVF. Destroys A, HL.
FILL_PUSH:
    ld   hl, (GFX_FILL_SP)
    bit  7, h
    jr   nz, .full                   ; SP = GFX_FILL_STACK_END ($8000)
    ld   (hl), c
    inc  hl
    ld   (hl), e
    inc  hl
    ld   (GFX_FILL_SP), hl
    ret
.full:
    ld   a, 1
    ld   (GFX_FILL_OVF), a
    ret

; FILL_RUNS: A = F (fillable pixels of one byte, nonzero), C = 0 or $80 (the
; previous byte's pixel 7 in bit 7), HL = a byte of the row (column = L & 31),
; E = the row's y. Pushes one seed per run start: F AND NOT (F >> 1 | C).
; Out: C = this byte's pixel 7 in bit 7. Keeps HL, B, E; destroys A, D.
FILL_RUNS:
    ld   d, a
    srl  a
    or   c
    cpl
    and  d                           ; A = run starts
    ld   c, d                        ; C = F
    jr   z, .carry
    push hl
    push bc
    ld   d, a                        ; D = run starts, pixel 0 in bit 7
    ld   a, l
    add  a, a
    add  a, a
    add  a, a                        ; (L & 31) * 8
    ld   c, a                        ; C = x of pixel 0
.bit:
    sla  d
    jr   nc, .no
    call FILL_PUSH
.no:
    inc  c
    ld   a, d
    or   a
    jr   nz, .bit
    pop  bc
    pop  hl
.carry:
    ld   a, c
    rrca
    and  $80
    ld   c, a
    ret

; FILL_SCANROW: C = y of a row next to the span: scan it over the span's bytes
; (GFX_FILL_LPTR's column, GFX_FILL_SN + 1 bytes) with the edge masks EL, ER.
; FILL_SCAN: HL = work plane byte at the span's first column, E = row y,
; B = bytes after the first. Pushes a seed per run of fillable pixels.
FILL_SCANROW:
    call FILL_ROW
    ld   a, (GFX_FILL_AOFF)
    add  a, h
    ld   h, a
    ld   a, (GFX_FILL_LPTR)
    and  $1F
    or   l
    ld   l, a
    ld   e, c
    ld   a, (GFX_FILL_SN)
    ld   b, a
FILL_SCAN:
    ld   c, 0
    ld   a, (GFX_FILL_EL)
    ld   d, a                        ; first byte's mask
    ld   a, b
    or   a
    jr   nz, .first
    ld   a, (GFX_FILL_ER)
    and  d
    ld   d, a                        ; a one-byte span: EL AND ER
.first:
    ld   a, (hl)
    cpl
    and  d
    call nz, FILL_RUNS
    ld   a, b
    or   a
    ret  z
.next:
    inc  hl
    ld   a, (hl)
    dec  b
    jr   z, .last
    inc  a
    jr   z, .full                    ; $FF: nothing fillable
    neg                              ; NOT the byte
    call FILL_RUNS
    jr   .next
.full:
    ld   c, 0
    jr   .next
.last:
    cpl
    ld   d, a
    ld   a, (GFX_FILL_ER)
    and  d
    ret  z
    jp   FILL_RUNS

; FILL_PROW: C = y, DE = a 32-byte buffer: P[y] = A AND (B XOR K), the painted
; pixels of row y (zeros if y is outside 0-191). DE ends 32 bytes on.
; Destroys AF, BC, HL.
FILL_PROW:
    ld   a, c
    cp   192
    jr   nc, .zero
    call FILL_ROW                    ; HL = screen row base
    ld   b, h
    ld   c, l                        ; BC = the screen row
    ld   a, (GFX_FILL_AOFF)
    or   a
    ld   a, h
    jr   z, .seed0
    add  a, $1B
    ld   h, a                        ; HL = shadow row = A, BC = screen = B
.l1:
    ld   a, (bc)
    and  (hl)                        ; K = 0: P = A AND B
    ld   (de), a
    inc  de
    inc  l
    inc  c
    ld   a, l
    and  $1F
    jr   nz, .l1
    ret
.seed0:
    add  a, $1B
    ld   b, a                        ; HL = screen row = A, BC = shadow = B
.l0:
    ld   a, (bc)
    cpl
    and  (hl)                        ; K = $FF: P = A AND NOT B
    ld   (de), a
    inc  de
    inc  l
    inc  c
    ld   a, l
    and  $1F
    jr   nz, .l0
    ret
.zero:
    ld   b, 32
    xor  a
.z:
    ld   (de), a
    inc  de
    djnz .z
    ret

; FILL_SWEEP: the stack is empty and seeds were dropped. For every row y, every
; unpainted pixel with a painted pixel above or below is a candidate; push a seed
; at each run start of the candidates. Stops after the row where a push fails
; (GFX_FILL_OVF set). Two 32-byte row buffers live on the machine stack.
; Destroys AF, BC, DE, HL.
FILL_SWEEP:
    ld   hl, -64
    add  hl, sp
    ld   sp, hl
    xor  a
    ld   (GFX_FILL_SY), a            ; y = 0
.row:
    ld   hl, 0
    add  hl, sp
    ex   de, hl                      ; DE = the buffers
    ld   a, (GFX_FILL_SY)
    dec  a
    ld   c, a
    call FILL_PROW                   ; buffer 0 = painted row y - 1
    ld   a, (GFX_FILL_SY)
    inc  a
    ld   c, a
    call FILL_PROW                   ; buffer 1 = painted row y + 1
    ld   hl, 0
    add  hl, sp
    ld   de, 32
    add  hl, de
    ex   de, hl                      ; DE = buffer 1
    ld   hl, 0
    add  hl, sp                      ; HL = buffer 0
    ld   b, 32
.merge:
    ld   a, (de)
    or   (hl)
    ld   (hl), a                     ; buffer 0 = above OR below
    inc  hl
    inc  de
    djnz .merge
    ld   hl, 0
    add  hl, sp
    ex   de, hl                      ; DE = buffer 0
    ld   a, (GFX_FILL_SY)
    ld   c, a
    call FILL_ROW
    ld   a, (GFX_FILL_AOFF)
    add  a, h
    ld   h, a                        ; HL = work plane row y
    ld   c, 0
.col:
    ld   a, (de)
    or   a
    jr   z, .none
    or   (hl)
    xor  (hl)                        ; candidates: above/below AND NOT A
    jr   z, .none
    push de
    ld   d, a
    ld   a, (GFX_FILL_SY)
    ld   e, a
    ld   a, d
    call FILL_RUNS
    pop  de
    jr   .adv
.none:
    ld   c, 0
.adv:
    inc  de
    inc  l
    ld   a, l
    and  $1F
    jr   nz, .col
    ld   a, (GFX_FILL_OVF)
    or   a
    jr   nz, .end                    ; the stack filled: drain first
    ld   a, (GFX_FILL_SY)
    inc  a
    ld   (GFX_FILL_SY), a
    cp   192
    jp   nz, .row
.end:
    ld   hl, 64
    add  hl, sp
    ld   sp, hl
    ret

    ALIGN 8
CIRCLE_MASK_TABLE:
    DB   $80, $40, $20, $10, $08, $04, $02, $01

    DS   $C000 - $, $FF             ; pad to the end of this 8K image
                                    ; ($A000 + $2000) -- absolute ORG
                                    ; here, unlike rom/forth_boot.asm's
                                    ; own ORG $0000, so the pad target
                                    ; must be absolute too

    SAVEBIN "graphics_exrom.bin", $A000, $2000
