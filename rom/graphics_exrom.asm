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

; ============================================================================
; Service table — fixed offsets, append-only. Each slot is exactly one
; JP instruction (3 bytes); a Home-side caller built against an older
; image still finds an existing slot at the same offset after a rebuild
; adds new ones past it.
; ============================================================================
    jp   RECT_FILL_IMPL       ; slot 0 ($A000) — RECT's own service

; ============================================================================
; Magic + ABI version, immediately after the table — verified by the
; Home-side caller (core/rectfill.asm's EXROM_CALL_RECT_FILL) right
; after paging in, before trusting any slot in the table above. A
; mismatch (no cartridge, or a different one) means the caller pages
; back out without calling anything, matching this project's own
; established "silently do nothing" convention for out-of-range/
; unavailable input (SOUND/STICK/FILL's own 64-col guard).
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

    DS   $C000 - $, $FF             ; pad to the end of this 8K image
                                    ; ($A000 + $2000) -- absolute ORG
                                    ; here, unlike rom/forth_boot.asm's
                                    ; own ORG $0000, so the pad target
                                    ; must be absolute too

    SAVEBIN "graphics_exrom.bin", $A000, $2000
