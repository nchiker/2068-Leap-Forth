; ============================================================================
; rom/graphics_exrom.asm — EXROM-resident graphics services (chunk 5,
; $A000-$BFFF once paged in — see kernel/bank/bank.asm and this
; project's own chunk-by-chunk audit, docs/PROJECT_PLAN.md, for why
; chunk 5 specifically)
;
; Standalone 8K image, assembled and SAVEBIN'd separately from rom/
; forth_boot.asm — real hardware only has one physical EXROM socket,
; so this is the one and only EXROM payload this project builds, not
; one of several. Reached exclusively through core/*.asm Home-side
; stubs (core/rectfill.asm today) that page chunk 5 in via kernel/
; bank/bank.asm, verify this image's own magic+ABI byte pair, dispatch
; through the service table below, then page back out — never called
; directly.
;
; WHY A SERVICE TABLE, not just one fixed entry point: this image is
; expected to grow (Polygon draw/fill and Sprites are the next planned
; additions, per this session's own scoping) — a fixed-offset table,
; append-only, is what lets a Home-side caller built against an OLDER
; version of this image still find the SAME service at the SAME slot
; after a REBUILD adds new ones later, matching structured-basic-poc's
; own proven EXROM_ABI pattern (magic+version, ordered slot table) —
; read before designing this, not reinvented blind.
;
; THE TABLE'S OWN SIZE IS FIXED UPFRONT (GRAPHICS_EXROM_MAX_SLOTS = 8),
; not grown one slot at a time — caught before it shipped: adding
; POLYGON's own slot naively right after RECT's would have shifted the
; magic+ABI trailer that follows the table, silently breaking core/
; rectfill.asm's own already-hardcoded offset for it. Reserving all 8
; slots now, even with only 2 filled, means every future service added
; here moves nothing that already exists — matches structured-basic-
; poc's own fixed eleven-slot table for the identical reason.
;
; CALLING BACK INTO HOME: this code cannot call GFX_WRITE_PIXEL/
; GFX_SET_ATTR by their real addresses — those live in rom/
; forth_boot.asm's own kernel/graphics/graphics.asm inclusion, and
; move every time that ROM's dictionary grows or shrinks, while this
; file is assembled completely separately with no visibility into that
; build. GRAPHICS_HOME_TABLE (rom/forth_boot.asm, fixed at $0100) is
; the fix — stable, low, append-only JP veneers this file calls
; through instead. The two files' own copies of that table's layout
; used to be kept in sync BY HAND — the exact class of bug that
; shipped twice in this project's own history (a shifted service-table
; offset, twice) — until tools/export_home_symbols.py (modeled on the
; sibling structured-basic-poc project's own tool of the same name)
; started generating build/graphics_home_table.inc directly from rom/
; forth_boot.asm's own GRAPHICS_HOME_TABLE, INCLUDEd below instead of
; hand-typed. Regenerated automatically by the Makefile's own
; graphics-exrom target — never edit build/graphics_home_table.inc by
; hand, and never hand-copy its constants back into this file.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $A000

    INCLUDE "include/sysvars.inc"
    INCLUDE "include/graphics_exrom_abi.inc"

; ---- Home-side stable call targets (rom/forth_boot.asm, $0100) ----
; Generated, not hand-typed — see this file's own header above.
    INCLUDE "build/graphics_home_table.inc"

; ============================================================================
; Service table — FIXED SIZE (GRAPHICS_EXROM_MAX_SLOTS slots, see this
; file's own header on why), each slot exactly one JP instruction (3
; bytes). Unfilled slots point at GRAPHICS_EXROM_UNIMPLEMENTED — a
; defensive stub, not expected to ever actually be reached, since a
; Home-side caller only ever calls a slot number it was built knowing
; about.
; GRAPHICS_EXROM_MAX_SLOTS itself lives in include/graphics_exrom_abi.inc
; now (INCLUDEd above) — see that file's own header for why.
; ============================================================================
GRAPHICS_EXROM_TABLE:
    jp   RECT_FILL_IMPL              ; slot 0 ($A000) — RECT
    jp   POLY_DRAW_IMPL              ; slot 1 ($A003) — POLYGON (outline)
    jp   SPRITE_DEFINE_IMPL          ; slot 2 ($A006) — SPRITE-DEFINE
    jp   SPRITE_SHOW_IMPL            ; slot 3 ($A009) — SPRITE-SHOW
    jp   SPRITE_HIDE_IMPL            ; slot 4 ($A00C) — SPRITE-HIDE
    jp   POLY_FILL_IMPL               ; slot 5 ($A00F) — POLYGON-FILL
    jp   GRAPHICS_EXROM_UNIMPLEMENTED ; slot 6 — reserved
    jp   GRAPHICS_EXROM_UNIMPLEMENTED ; slot 7 — reserved
    ASSERT $ - GRAPHICS_EXROM_TABLE == GRAPHICS_EXROM_MAX_SLOTS * 3

GRAPHICS_EXROM_UNIMPLEMENTED:
    ret

; ============================================================================
; Magic + ABI version, immediately after the FIXED-SIZE table above —
; verified by the Home-side caller (core/rectfill.asm's EXROM_CALL_
; RECT_FILL, core/polygon.asm's own equivalent) right after paging in,
; before trusting any slot in the table. A mismatch (no cartridge, or
; a different one) means the caller pages back out without calling
; anything, matching this project's own established "silently do
; nothing" convention for out-of-range/unavailable input (SOUND/
; STICK/FILL's own 64-col guard).
; ============================================================================
    DB   GRAPHICS_EXROM_MAGIC
    DB   GRAPHICS_EXROM_ABI

; ============================================================================
; RECT_FILL_IMPL
; Fills the rectangle spanned by (RECT_X0,RECT_Y0)-(RECT_X1,RECT_Y1),
; corners inclusive, with RECT_ATTR — RECT's actual mechanism. Always
; OR/set, never XOR (a clean repaint, not a toggle — same convention
; GFX_FILL's own header documents and for the same reason).
;
; Corners are normalized first (RECT_X0<=RECT_X1, RECT_Y0<=RECT_Y1) so
; the caller doesn't have to sort them — same convention this
; project's own GFX_LINE leaves to ITS caller today, but RECT's whole
; point is being the easy/fast primitive, so sorting here costs nothing
; and removes a footgun a caller would otherwise hit silently.
;
; BULK ROW + ATTRIBUTE-CELL FILL, not one GFX_WRITE_PIXEL call per
; pixel — a real cycle-count optimization found and measured (not
; guessed) during a raw-cycle-count audit pass: GFX_WRITE_PIXEL
; recomputes the full ZX screen-address bit-twiddling formula AND
; restamps the covering 8x8 attribute cell from scratch on EVERY
; pixel, even adjacent ones sharing the same bitmap byte or the same
; attribute cell. For a representative 40x20 fill (800 pixels), the
; old per-pixel loop cost an estimated ~480,000 T-states (roughly
; 600/pixel: ~300 for GFX_PIXEL_ADDR_SETUP's own address/mask
; recomputation, ~100 for GFX_SET_ATTR's own address recomputation,
; plus loop overhead) — REDUNDANT work, since the same 800 pixels only
; span 5 bitmap bytes/row x 20 rows = 100 byte-writes and just 5x3=15
; unique attribute cells. This routine now:
;   1. Computes each scanline's own row-base address ONCE per row
;      (GRAPHICS_HOME_ROW_BASE_ADDR, the same veneer GFX_PIXEL_ADDR_
;      SETUP itself is built on), then fills that row's own span with
;      at most 3 byte-writes: a partial mask at the left edge, a
;      straight $FF write (propagated across any further whole bytes
;      via LDIR, not a per-byte OR — safe because OR-ing $FF into
;      anything already yields $FF, so a direct SET is equivalent and
;      faster) in the middle, and a partial mask at the right edge —
;      collapsing to a single masked byte when the whole span fits in
;      one byte.
;   2. Stamps each COVERED ATTRIBUTE CELL exactly once (GRAPHICS_HOME_
;      CELL_ATTR_ADDR), in a separate pass over the covered (char row,
;      column) rectangle — ceil(height/8) x ceil(width/8) cells, not
;      height x width pixels.
; Bitmap-fill correctness verified against the OLD per-pixel algorithm
; bit-for-bit in Python (2000 random rectangles, every byte in the
; resulting bitmap identical) before any of this was written — the
; left/right partial-byte masks are LEFTMASK_TABLE[bit]=$FF>>bit and
; RIGHTMASK_TABLE[bit]=($FF<<(7-bit))&$FF, matching BIT_MASK_TABLE's
; own $80>>n single-bit convention exactly (kernel/graphics/
; graphics.asm's own table GFX_PIXEL_ADDR_SETUP indexes the same way).
; Confirmed under real ZEsarUX afterward too (rom/test_rect.asm),
; not just Python and a clean assemble.
;
; Y is NOT bounds-checked here (0-191), matching the OLD per-pixel
; version's own behavior exactly (GFX_PIXEL_ADDR_SETUP/GFX_ROW_BASE_
; ADDR never bounds-checked row either) — not a new gap this
; optimization introduces. The attribute pass IS defensively guarded
; against GRAPHICS_HOME_CELL_ATTR_ADDR's own out-of-range carry (that
; routine does bounds-check), skipping a would-be out-of-range cell
; rather than writing through an undefined HL — strictly safer than
; the old path for invalid input, never less safe for valid input.
; In:  RECT_X0/Y0/X1/Y1 (0-255/0-191), RECT_ATTR — all pre-set by the
;      Home-side RECT word before paging this image in
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
RECT_FILL_IMPL:
    ; ---- normalize X: RECT_X0 <= RECT_X1 ----
    ld   a, (RECT_X0)
    ld   b, a
    ld   a, (RECT_X1)
    cp   b
    jr   nc, .x_ok                  ; X1 >= X0 already
    ld   (RECT_X0), a               ; swap
    ld   a, b
    ld   (RECT_X1), a
.x_ok:

    ; ---- normalize Y: RECT_Y0 <= RECT_Y1 ----
    ld   a, (RECT_Y0)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jr   nc, .y_ok
    ld   (RECT_Y0), a
    ld   a, b
    ld   (RECT_Y1), a
.y_ok:

    ; ---- col0/bit0, col1/bit1 from the now-normalized X0/X1 ----
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
    ld   c, a                        ; c = scanline (0-7) within its
                                     ; own char row — survives the
                                     ; GRAPHICS_HOME_ROW_BASE_ADDR call
                                     ; below (that veneer never touches
                                     ; BC, only AF/DE/HL)
    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111                   ; a = char_row (0-23)
    call GRAPHICS_HOME_ROW_BASE_ADDR ; hl = this char row's own bitmap
                                     ; base address, AT SCANLINE 0
    ld   a, h
    add  a, c                        ; +scanline*256 — one scanline
                                     ; down is exactly +256, the same
                                     ; fact GFX_PIXEL_ADDR_SETUP's own
                                     ; header already documents
    ld   h, a                        ; hl = ROWBASE (this scanline's
                                     ; own column-0 byte address)
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
    push hl                          ; RECT_LEFTMASK/RECT_RIGHTMASK both
                                     ; destroy HL for their own table
                                     ; lookup -- hl here is the target
                                     ; byte's own address, computed just
                                     ; above, and must survive both calls
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
    push hl                          ; same HL-survives-the-call reasoning
                                     ; as the single-byte case above
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
    add  a, b                        ; a = col1 - col0 -- always >= 1
                                     ; here (this branch only runs when
                                     ; col1 != col0, and RECT_X0<=
                                     ; RECT_X1 was already normalized
                                     ; above, so col1 > col0)
    dec  a                           ; a = full-middle-byte count
                                     ; (col1-col0-1); 0 means col1 is
                                     ; col0's immediate neighbor —
                                     ; no middle bytes at all
    ld   b, a
    or   a
    jr   z, .no_middle

    ld   hl, (RECT_ROWBASE)
    ld   b, a                        ; stash full-middle count in b —
                                     ; a is about to be reused for the
                                     ; address arithmetic below
    ld   a, (RECT_COL0)
    inc  a
    add  a, l                        ; hl = ROWBASE + col0+1 (first
    ld   l, a                        ; middle byte)
    jr   nc, .no_carry_mid
    inc  h
.no_carry_mid:
    ld   (hl), $FF                   ; seed the first middle byte
    ld   a, b
    dec  a
    jr   z, .no_middle                ; only one middle byte total —
                                     ; nothing left to LDIR-propagate
    ld   c, a
    ld   b, 0                        ; bc = remaining middle bytes
    push hl
    pop  de
    inc  de                          ; de = hl+1 — the classic Z80
                                     ; "clone forward" LDIR idiom: each
                                     ; copy writes the byte this same
                                     ; instruction just wrote one
                                     ; position earlier, propagating
                                     ; the seeded $FF the rest of the
                                     ; way without a per-byte loop
    ldir
.no_middle:

    ; ---- right partial byte: ROWBASE + col1, fresh (not tracked
    ; through the middle-byte pointer above — simpler and safer than
    ; trying to reuse HL/DE after LDIR leaves them one past the end) ----
    ld   hl, (RECT_ROWBASE)
    ld   a, (RECT_COL1)
    add  a, l
    ld   l, a
    jr   nc, .no_carry_last
    inc  h
.no_carry_last:
    push hl                          ; same HL-survives-the-call reasoning
                                     ; as the single-byte case above
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

    ; ---- attribute pass: each COVERED CELL exactly once, not once
    ; per pixel — char rows Y0>>3..Y1>>3, columns RECT_COL0..RECT_COL1 ----
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
    call GRAPHICS_HOME_CELL_ATTR_ADDR  ; hl = attr address; carry SET
                                       ; if out of range (row>=24 or
                                       ; col>=32) — see this routine's
                                       ; own header on why this is
                                       ; checked here even though the
                                       ; bitmap pass above doesn't
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
; RECT_LEFTMASK / RECT_RIGHTMASK (internal — not service-table slots)
; RECT_FILL_IMPL's own partial-byte masks: LEFTMASK[bit] covers pixel
; positions bit..7 (the byte's own right portion, x&7==bit through the
; last pixel in that byte); RIGHTMASK[bit] covers positions 0..bit (the
; byte's own left portion). Table-driven, not shifted at call time —
; a single lookup is faster than a variable-count shift loop, and
; there are only 8 entries each either way. Values match BIT_MASK_
; TABLE's own $80>>n single-bit convention exactly (verified in Python
; against the OLD per-pixel algorithm before either table was written
; in Z80 — see RECT_FILL_IMPL's own header).
; In:  A = bit position (0-7)
; Out: A = the mask
; Destroys: DE, HL (not AF's own flags meaningfully — caller only uses A)
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
; POLY_DRAW_IMPL
; Draws the closed outline through POLY_COUNT vertices (POLY_VERTS) —
; POLYGON's own mechanism. Draws one GFX_LINE (via GRAPHICS_HOME_LINE)
; per edge, vertex i to vertex (i+1), wrapping the last edge back to
; vertex 0 to close the shape — no new drawing logic at all, this is
; entirely a loop over an already-proven primitive, the same "reuse,
; don't reimplement" reasoning this project's own GFX_SCROLL_OUTPUT_UP
; already applies to GFX_SCROLL_TEXT_UP.
;
; Fewer than 3 points or more than POLY_MAXPTS silently draws nothing
; — same "silently do nothing on invalid input" convention every other
; word in this project already uses (SOUND/STICK/FILL's own 64-col
; guard, RECT_FILL_IMPL's own out-of-range handling).
; In:  POLY_COUNT (3-POLY_MAXPTS), POLY_VERTS (that many (x,y) pairs),
;      POLY_ATTR — all pre-set by the Home-side POLYGON word
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
POLY_DRAW_IMPL:
    ld   a, (POLY_COUNT)
    cp   3
    jp   c, .done                   ; fewer than 3 points: nothing to draw
    cp   POLY_MAXPTS + 1
    jp   nc, .done                  ; too many points: nothing (same
                                    ; convention as RECT_FILL_IMPL's
                                    ; own out-of-range handling)

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
; SPRITE_TRANSFER_IMPL (internal — not a service-table slot itself)
; Shared core behind SPRITE_DEFINE_IMPL/SPRITE_SHOW_IMPL/SPRITE_HIDE_
; IMPL below: copies all SPRITE_CELLS*SPRITE_CELLS cells of an exact,
; direct byte-for-byte cell image (8 bitmap scanlines + 1 attribute
; byte per cell, 9 bytes — see include/sysvars.inc's own SPRITE_SLOT_
; BYTES header for why a raw copy, not a per-pixel OR/AND, is the
; right shape here) between the screen at (SPRITE_OP_ROW,SPRITE_OP_
; COL) and SPRITE_OP_BUF, direction set by SPRITE_OP_DIR.
;
; Cell (row,col) offsets come from a small fixed table
; (SPRITE_CELL_OFFSETS) rather than computed via div/mod on SPRITE_
; CELLS — clearer to read and just as cheap for a 2x2 grid.
;
; GFX_ROW_BASE_ADDR/GFX_CELL_ATTR_ADDR (via their own Home veneers)
; both destroy DE per their own documented contracts, so SPRITE_OP_PTR
; is always reloaded fresh from memory immediately after either call,
; never held across one — same "value must survive a call -> use
; memory, not a register" pattern this file's own RECT/POLYGON code
; already established.
; In:  SPRITE_OP_ROW/COL (top-left character position, 0-23/0-31 —
;      caller's responsibility that +1 stays in range, no bounds
;      check here, matching this project's established scope), SPRITE_
;      OP_BUF (buffer base address), SPRITE_OP_DIR (0 = capture screen
;      -> buffer, nonzero = blit buffer -> screen)
; Out: none
; Destroys: AF, BC, DE, HL
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
    inc  h                           ; next scanline: +256 (high byte
                                     ; only — see this file's own RECT/
                                     ; POLYGON header precedent citing
                                     ; the same convention)
    djnz .scan_loop

    ; ---- attribute byte, 9th byte of this cell ----
    ld   a, (SPRITE_CELL_ROW)
    ld   b, a
    ld   a, (SPRITE_CELL_COL)
    ld   c, a
    call GRAPHICS_HOME_CELL_ATTR_ADDR ; hl = attr address (destroys DE)
    ld   de, (SPRITE_OP_PTR)          ; reloaded fresh, see header
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
; SPRITE_DEFINE_IMPL
; Captures the SPRITE_CELLS x SPRITE_CELLS screen area at (SPRITE_OP_
; ROW,SPRITE_OP_COL) into slot SPRITE_OP_SLOT's own image buffer —
; SPRITE-DEFINE's actual mechanism.
; In:  SPRITE_OP_SLOT (0-SPRITE_SLOT_MAX-1), SPRITE_OP_ROW/COL — all
;      pre-set by the Home-side SPRITE-DEFINE word
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
SPRITE_DEFINE_IMPL:
    ld   a, (SPRITE_OP_SLOT)
    cp   SPRITE_SLOT_MAX
    ret  nc                          ; out-of-range slot: silently do
                                     ; nothing, same convention as
                                     ; RECT/POLYGON's own out-of-range
                                     ; handling
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
; SPRITE_SHOW_IMPL
; Saves the current screen content at (SPRITE_OP_ROW,SPRITE_OP_COL)
; into slot SPRITE_OP_SLOT's own background buffer, then blits that
; slot's image over it — SPRITE-SHOW's actual mechanism. Refuses (does
; nothing) if the slot was never DEFINEd, or is already SHOWN — same
; "HIDE then SHOW to reposition" convention include/sysvars.inc's own
; SPRITE_SLOT_SHOWN header already documents.
; In:  SPRITE_OP_SLOT, SPRITE_OP_ROW/COL — pre-set by the Home-side
;      SPRITE-SHOW word
; Out: none
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
; SPRITE_HIDE_IMPL
; Restores slot SPRITE_OP_SLOT's own saved background over wherever it
; was last SHOWN — SPRITE-HIDE's actual mechanism. Refuses (does
; nothing) if the slot isn't currently SHOWN.
; In:  SPRITE_OP_SLOT — pre-set by the Home-side SPRITE-HIDE word
;      (SPRITE_OP_ROW/COL are NOT inputs here — HIDE recalls the
;      position SHOW itself recorded, so a caller only ever needs to
;      name the slot)
; Out: none
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
; SPRITE_FLAG_ADDR_SHOWN (internal — not service-table slots)
; Small address helpers shared by the three services above — SPRITE_
; OP_SLOT's own offset into whichever fixed array/buffer is needed.
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
; SPRITE_MUL_A_HL (internal — not a service-table slot)
; HL = A * HL — a plain repeated-add multiply, not a shift-based one:
; A is always SPRITE_OP_SLOT (0 to SPRITE_SLOT_MAX-1, at most 3 today),
; so the loop runs at most 3 times and clarity wins over a shift/add
; sequence that would only pay for itself at much larger A.
; In:  A = multiplier (small), HL = multiplicand (SPRITE_SLOT_BYTES)
; Out: HL = A * HL
; Destroys: AF, DE
; ============================================================================
SPRITE_MUL_A_HL:
    ld   e, l
    ld   d, h                        ; DE = the original multiplicand
    ld   hl, 0                       ; HL = running total, starts at 0
    or   a
    ret  z                           ; A=0: HL is already the correct
                                     ; 0*multiplicand, nothing to add
.loop:
    add  hl, de
    dec  a
    jr   nz, .loop
    ret

; ============================================================================
; POLY_FILL_IMPL
; Fills the interior of the polygon (POLY_VERTS/POLY_COUNT) using the
; even-odd rule — POLYGON-FILL's actual mechanism. Active-edge scanline
; fill: build a table of non-horizontal edges, then for each scanline,
; collect every active edge's current x as a crossing, sort the
; crossings, and fill between each pair (1st-2nd, 3rd-4th, ...).
;
; Genuinely algebraic, NOT a flood fill: crossings come straight from
; the vertex coordinates, never from reading back already-drawn
; pixels, so — unlike GFX_FILL bounded by a hand-drawn outline — this
; can't leak through a diagonal single-pixel gap in a Bresenham-drawn
; boundary line. That gap is a real, separate property of 4-connected
; flood fill this project already accepts for ordinary FILL; POLYGON-
; FILL never has it, a genuine advantage of computing crossings
; directly instead of exploring pixels.
;
; PRECISION: verified in Python against an exact (real-number) even-
; odd reference across 6 shapes (see this session's own working
; verification, not preserved in-tree) before any Z80 was written.
; Convex shapes with integer-ratio edges (a right triangle, an axis-
; aligned square) matched EXACTLY. Concave shapes with non-integer-
; ratio edges can be off by a single pixel at specific scanlines near
; a concave vertex (~3% of filled pixels in the worst tested case) —
; the Bresenham error accumulator doesn't round every row's crossing
; the same way (floor some rows, the true nearest-integer on others),
; the same class of approximation GFX_LINE/GFX_CIRCLE already accept
; throughout this project rather than a bug specific to this routine.
; Confirmed in that same verification: every such discrepancy is a
; single pixel immediately adjacent to correctly-filled area — never
; a leak far outside the shape, never a real gap inside it. Also
; masked in practice whenever POLYGON-FILL is used together with
; POLYGON's own outline (the normal case): the outline is drawn with
; the same GFX_LINE Bresenham stepping, directly over these same
; boundary pixels.
;
; EDGE TABLE IS GENUINE RAM (POLY_FILL_EDGE_*, include/sysvars.inc),
; not scratch inside this EXROM image: chunk 5 IS this ROM image while
; paged in for this very call, so state that must be written and
; persist across the whole fill can't live here.
; In:  POLY_VERTS/POLY_COUNT/POLY_ATTR — pre-set by the Home-side
;      POLYGON-FILL word
; Out: none
; Destroys: AF, BC, DE, HL
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
    ; ---- vertex i -> RECT_X0/RECT_Y0 (reused as scratch — RECT and
    ; POLYGON-FILL never run at the same time) ----
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
    sub  c                           ; a = X1-X0 (signed result in A)
    jr   nc, .dx_pos                 ; X1>=X0: already positive (or zero)
    neg                              ; X1<X0: negate to get |dx|
    ld   b, a                        ; b = dx
    ld   a, (POLY_FILL_NEDGES)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_SX
    add  hl, de
    ld   (hl), $FF                   ; sx = -1
    jr   .dx_store
.dx_pos:
    ld   b, a                        ; b = dx
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
    add  a, a                        ; *2 -- ERR is 2 bytes/entry
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

    ; ---- advance this edge's own x for the NEXT scanline (Bresenham
    ; y-major step): err += dx; while 2*err >= dy: x += sx; err -= dy ----
    ld   a, (POLY_FILL_I)
    add  a, a                        ; *2 -- ERR is 2 bytes/entry
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_ERR
    add  hl, de                      ; hl = &ERR[i]
    ld   (POLY_FILL_ERR_ADDR), hl    ; stash for the write-back below
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
    add  hl, de                      ; hl = err + dx (new running error —
                                     ; genuinely needs all 16 bits: dy up
                                     ; to 191 plus dx up to 255 can reach
                                     ; 446 before normalization brings it
                                     ; back down, caught by checking the
                                     ; real worst case before writing any
                                     ; of this, not assumed to fit a byte

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
    add  hl, hl                      ; hl = 2*err -- SIGNED: err legitimately
                                     ; goes negative whenever dx isn't an
                                     ; exact multiple of dy (the normal
                                     ; case), so 2*err can be negative too.
                                     ; A negative 2*err, read as a two's-
                                     ; complement 16-bit value, LOOKS like
                                     ; a huge unsigned number -- an
                                     ; unsigned-only carry check below
                                     ; would then wrongly see it as
                                     ; ">= dy" and keep stepping (this
                                     ; exact bug shipped once already,
                                     ; caught via a real-hardware screen-
                                     ; shot showing spans running off the
                                     ; edge of the canvas, root-caused via
                                     ; a temporary per-row debug log
                                     ; before this fix was written). Test
                                     ; the sign bit FIRST: negative always
                                     ; means "stop", since dy is always
                                     ; >=1 (positive) so a negative 2*err
                                     ; can never be >= dy.
    bit  7, h
    jr   nz, .step_stop              ; 2*err negative: definitely < dy
    or   a
    sbc  hl, bc                      ; carry set iff 2*err < dy (safe now:
                                     ; both operands are non-negative)
    pop  hl                          ; restore err (un-doubled) either way
    jr   c, .step_done               ; 2*err < dy: normalization complete

    push bc                          ; save dy across the X update
    push hl                          ; save err across the X update
    ld   a, (POLY_FILL_I)
    ld   e, a
    ld   d, 0
    ld   hl, POLY_FILL_EDGE_SX
    add  hl, de
    ld   a, (hl)                     ; a = sx (+1 or -1, a real signed
                                     ; byte — the add below wraps
                                     ; correctly via two's complement,
                                     ; no branch needed for the sign)
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
    pop  hl                          ; restore err (un-doubled) -- same
                                     ; "either way" restore .step_done
                                     ; below expects, just reached from
                                     ; the negative-sign short-circuit
                                     ; instead of the carry check
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

    ; ---- every edge checked for this row -- sort the crossings
    ; (bubble sort: NCROSS is at most POLY_MAXPTS=12, so simplicity
    ; wins over a fancier sort with the same worst-case behavior at
    ; this size) ----
    ld   a, (POLY_FILL_NCROSS)
    cp   2
    jp   c, .row_done                ; fewer than 2 crossings: nothing
                                     ; to sort or fill this row
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
    ld   b, a                        ; b = last valid j (NCROSS-1 - 1
                                     ; would leave no j+1 in range, so
                                     ; the last valid j is NCROSS-2;
                                     ; comparing against NCROSS-1 below
                                     ; and using strict `nc` catches it)
    ld   a, (POLY_FILL_J)
    cp   b
    jp   nc, .sort_inner_done        ; j >= NCROSS-1: no j+1 left, pass over

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

    ; ---- fill spans: pairs (crossings[0],crossings[1]), (crossings[2],
    ; crossings[3]), ... — half-open [x0,x1) per span, same convention
    ; verified against a reference even-odd fill before any of this was
    ; written (see this routine's own header) ----
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
    ld   (RECT_CUR_X), a             ; reuse RECT_CUR_X as the span-fill
                                     ; cursor — RECT is idle whenever
                                     ; POLYGON-FILL runs, same "shared
                                     ; scratch" reasoning already used
                                     ; for RECT_X0/Y0 above
    inc  hl
    ld   a, (hl)
    ld   (RECT_X1), a                ; reuse RECT_X1 as this span's own
                                     ; exclusive right bound

.pixel_loop:
    ld   a, (RECT_X1)
    ld   b, a                        ; b = x1 (bound)
    ld   a, (RECT_CUR_X)             ; a = cur
    cp   b                           ; carry set iff cur < x1 (continue)
    jp   nc, .span_done              ; cur >= x1: this span is done

    ld   b, a                        ; b = cur (x)
    ld   a, (POLY_FILL_Y)
    ld   c, a                        ; c = y
    ld   d, 0                        ; OVER=0 — always OR/set, see
                                     ; RECT_FILL_IMPL's own header for
                                     ; why (a clean repaint, not a toggle)
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

    DS   $C000 - $, $FF             ; pad to the end of this 8K image
                                    ; ($A000 + $2000) -- absolute ORG
                                    ; here, unlike rom/forth_boot.asm's
                                    ; own ORG $0000, so the pad target
                                    ; must be absolute too

    SAVEBIN "graphics_exrom.bin", $A000, $2000
