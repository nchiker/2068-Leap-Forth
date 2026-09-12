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
; through instead. Keep both files' own copies of that table's layout
; in sync by hand until this project builds a real export-symbols tool
; (structured-basic-poc's tools/export_home_symbols.py is the proven
; model for that, not yet built here — a known, deliberate gap, not an
; oversight).
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $A000

    INCLUDE "include/sysvars.inc"

GRAPHICS_EXROM_MAGIC EQU $F0
GRAPHICS_EXROM_ABI   EQU 1

; ---- Home-side stable call targets (rom/forth_boot.asm, $0100) ----
; Must match that file's own GRAPHICS_HOME_TABLE layout exactly — see
; this file's own header on why these can't be derived automatically
; yet.
GRAPHICS_HOME_WRITE_PIXEL EQU $0100   ; slot 0 — B=x,C=y,A=attr,D=OVER
GRAPHICS_HOME_SET_ATTR    EQU $0103   ; slot 1 — A=attr,B=row,C=col
GRAPHICS_HOME_LINE        EQU $0106   ; slot 2 — no register args;
                                     ; reads GFX_LINE_X0/Y0/X1/Y1/
                                     ; ATTR/OVER
GRAPHICS_HOME_ROW_BASE_ADDR EQU $0109 ; slot 3 — A=row -> HL=bitmap
                                     ; base address (scanline 0)
GRAPHICS_HOME_CELL_ATTR_ADDR EQU $010C ; slot 4 — B=row,C=col -> HL=addr

; ============================================================================
; Service table — FIXED SIZE (GRAPHICS_EXROM_MAX_SLOTS slots, see this
; file's own header on why), each slot exactly one JP instruction (3
; bytes). Unfilled slots point at GRAPHICS_EXROM_UNIMPLEMENTED — a
; defensive stub, not expected to ever actually be reached, since a
; Home-side caller only ever calls a slot number it was built knowing
; about.
; ============================================================================
GRAPHICS_EXROM_MAX_SLOTS EQU 8
GRAPHICS_EXROM_TABLE:
    jp   RECT_FILL_IMPL              ; slot 0 ($A000) — RECT
    jp   POLY_DRAW_IMPL              ; slot 1 ($A003) — POLYGON (outline)
    jp   SPRITE_DEFINE_IMPL          ; slot 2 ($A006) — SPRITE-DEFINE
    jp   SPRITE_SHOW_IMPL            ; slot 3 ($A009) — SPRITE-SHOW
    jp   SPRITE_HIDE_IMPL            ; slot 4 ($A00C) — SPRITE-HIDE
    jp   GRAPHICS_EXROM_UNIMPLEMENTED ; slot 5 — reserved (POLYGON fill)
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
; corners inclusive, with RECT_ATTR — RECT's actual mechanism. Unlike
; GFX_FILL, this needs no exploration/stack/visited-tracking at all:
; the geometry is fully known upfront (two corners), so it's a plain
; bounded double loop over every pixel in the box, calling GFX_WRITE_
; PIXEL (via GRAPHICS_HOME_WRITE_PIXEL) once per pixel — same "always
; OR/set, never XOR" convention GFX_FILL's own header already
; documents and for the same reason (a clean repaint, not a toggle).
;
; Corners are normalized first (RECT_X0<=RECT_X1, RECT_Y0<=RECT_Y1) so
; the caller doesn't have to sort them — same convention this
; project's own GFX_LINE leaves to ITS caller today, but RECT's whole
; point is being the easy/fast primitive, so sorting here costs nothing
; and removes a footgun a caller would otherwise hit silently (an
; unsorted box would otherwise draw nothing at all, the loop below
; never running because X0>X1 or Y0>Y1 make its own bound check fail
; immediately).
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

    ld   a, (RECT_Y0)
    ld   (RECT_CUR_Y), a
.row_loop:
    ld   a, (RECT_X0)
    ld   (RECT_CUR_X), a
.col_loop:
    ld   a, (RECT_CUR_X)
    ld   b, a
    ld   a, (RECT_CUR_Y)
    ld   c, a
    ld   d, 0                        ; OVER=0 — always OR/set, see header
    ld   a, (RECT_ATTR)
    call GRAPHICS_HOME_WRITE_PIXEL

    ld   a, (RECT_CUR_X)
    ld   b, a
    ld   a, (RECT_X1)
    cp   b
    jr   z, .col_done
    ld   a, (RECT_CUR_X)
    inc  a
    ld   (RECT_CUR_X), a
    jr   .col_loop
.col_done:

    ld   a, (RECT_CUR_Y)
    ld   b, a
    ld   a, (RECT_Y1)
    cp   b
    jr   z, .row_done
    ld   a, (RECT_CUR_Y)
    inc  a
    ld   (RECT_CUR_Y), a
    jr   .row_loop
.row_done:
    ret

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

    DS   $C000 - $, $FF             ; pad to the end of this 8K image
                                    ; ($A000 + $2000) -- absolute ORG
                                    ; here, unlike rom/forth_boot.asm's
                                    ; own ORG $0000, so the pad target
                                    ; must be absolute too

    SAVEBIN "graphics_exrom.bin", $A000, $2000
