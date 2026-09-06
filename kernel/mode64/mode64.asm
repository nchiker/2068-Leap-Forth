; ============================================================================
; kernel/mode64/mode64.asm — 64-column display mode
;
; Phase 8 stretch goal. PROVENANCE, stated plainly: this is NOT
; original-to-2068-Forth code, and it is NOT simply "inherited from
; 2068-Leap" the way the rest of kernel/ is either — it is real,
; working, once-shipped 2068-Leap code that was later REMOVED from
; that project (kernel/graphics/graphics.asm's own current comment:
; "Mode 2 (64-Column) was removed 2026-08-20 — real overhead vs. value
; trade-off"), for that project's own ROM-budget reasons, not because
; it didn't work. No trace of it survives in 2068-Leap's own git
; history (checked directly: `git log -S"64-Column"` on that repo
; finds only the baseline commit that already carries the removal
; comment). It was recovered from an OLDER pre-git backup tarball
; (~/Backup/ts2068rom.tar.gz "with full graphics", dated before the
; 2026-08-20 removal) at the user's own suggestion to check there
; before writing this from scratch — good thing: this project's own
; first attempt at this file, before that backup was found, had the
; wrong bit pattern (bit 2 alone, going only off the ROM disassembly's
; per-bit description) — the real, tested code below sets bits 1 AND 2
; together, which the disassembly's own bit-by-bit listing doesn't
; make obvious on its own.
;
; Ported here (not into kernel/graphics/graphics.asm, which stays
; exactly as inherited) with sysvars renumbered into this project's own
; probe-verified-empty $8426-$8FFF range (docs/PROJECT_PLAN.md's Phase
; 5 section) rather than the old backup's own addresses, which belong
; to a memory layout this project never had.
;
; HARDWARE FACT (real, tested, from the recovered code's own comments,
; itself checked against "the manual's own table" — cross-consistent
; with this project's own independent check against "Timex Sinclair
; 2068 ROM Disassembly," David Anderson 2023, which documents the same
; port $FF bit meanings without spelling out that 64-column mode needs
; BOTH bit 1 and bit 2 set together, not bit 2 alone):
;   port $FF (PORT_SCLD, the SCLD's Display Enhancement Control
;   Register) bits 0-2 = %110 is the 64-column mode marker; bits 3-5
;   hold an ink/paper palette (0-7); bits 6-7 are keyboard-interrupt-
;   disable and EXROM-enable, shared with kernel/bank and
;   kernel/interrupt — never touched here, only preserved, via the
;   same PORT_FF_SHADOW read-modify-write discipline kernel/graphics's
;   own GFX_SET_MODE/GFX_SET_BORDER already established.
;
; 64-column mode has no per-cell or per-pixel color the way normal
; mode's attribute bytes give it — the whole screen shares one
; ink/paper pair, chosen by MODE64_SET_PALETTE, not per shape or word.
;
; SMALLEST PROVABLE SLICE for this phase: MODE64_ON/OFF (the mode
; switch itself) and MODE64_WRITE_PIXEL/MODE64_READ_PIXEL (so
; rom/forth_smoke_p8b.asm can prove a pixel plotted in this mode is
; readable back at exactly the coordinate it was plotted at, the same
; GFX_READ_PIXEL-based verification technique Phase 5 already
; established for normal-mode PLOT). MODE64_SET_PALETTE is included
; since GFX_WRITE_PIXEL64's own real behavior depends on GFX_MODE being
; set correctly by SOME mode-select path, but line/circle/fill
; equivalents for this mode are not ported — real, further follow-up
; work, not silently folded into this slice.
; ============================================================================

    IFNDEF KERNEL_MODE64_ASM
    DEFINE KERNEL_MODE64_ASM

    INCLUDE "include/hardware.inc"
    INCLUDE "include/sysvars.inc"

SECOND_DISPLAY_DELTA_M64 EQU $2000   ; SECOND_DISPLAY_ADDR - SCREEN_ADDR;
                                     ; a plain constant (not a sysvar),
                                     ; safe to recompute locally rather
                                     ; than depend on the old backup's
                                     ; own include/hardware.inc entry

; ---- Phase 8 RAM state — same probe-verified $8426-$8FFF gap as every
; other core/ or kernel-addition file's own scratch (docs/PROJECT_PLAN.md
; Phase 5). The old backup's own addresses ($84AF+) belonged to a
; memory layout this project doesn't have and were not reused.
;
; RENUMBERED (code-consolidation pass, post-Phase-38): the original
; $87B0-$87B4 here byte-for-byte overlapped core/floatmul.asm's own
; F_PROD_HI/F_MUL_CNT/F_MSIGN/F_NORM_SHIFT and core/floatdiv.asm's own
; F_DIVID_LO — a real collision in the actual shipped rom/forth_boot.asm
; (both files are INCLUDEd there), found by a fresh grep-every-EQU pass
; across the whole tree, the same discipline every earlier phase's own
; scratch placement already used, just never re-run against everything
; ADDED since. Confirmed dormant, not an active bug: MODE64_WRITE_PIXEL
; and F_UMUL32/F_NORMALIZE32/F_UDIV32BY16 are never nested (neither
; PLOT64 nor MODE64_WRITE_PIXEL does any float arithmetic internally,
; confirmed by grepping this file and core/mode64.asm for any call to
; either float routine — none), and this is single-threaded Z80 code
; with no interrupt-handler involvement in either region — but a real,
; latent trap for a future word that combines the two, and a genuine
; violation of this project's own address-map invariant regardless of
; whether anything has tripped over it yet. Moved to $87BF-$87C3, a
; verified-free 9-byte gap between core/decimal.asm's own DIVISOR10
; ($87BD-$87BE) and core/print.asm's own PRINT_ROW ($87C8) — reverified
; by the same whole-tree grep before picking it, not assumed free. ----
GFX_PALETTE64          EQU $87BF   ; 1 byte: 0-7, persists across mode switches
GFX_PIXEL64_MASK       EQU $87C0   ; 1 byte: GFX_PIXEL64_ADDR_SETUP's own scratch
GFX_PIXEL64_WHICH_FILE EQU $87C1   ; 1 byte: 0 = Primary Display File, 1 = Second
GFX_PIXEL64_BYTECOL    EQU $87C2   ; 1 byte: real byte-column within the row
GFX_PIXEL64_OVER       EQU $87C3   ; 1 byte: MODE64_WRITE_PIXEL's own scratch

; ============================================================================
; MODE64_ON ( -- )
; Enters 64-column mode: sets port $FF bits 0-2 to %110 (preserving
; bits 3-7, but bits 3-5 are then immediately set to the current
; palette by the same write), sets GFX_MODE = 2 (kernel/graphics's own
; inherited sysvar; other inherited routines that check GFX_MODE will
; now see it), and clears the Second Display File's bitmap to zero
; (raw zero, not ATTR_DEFAULT — this is pixel data, not an attribute
; byte; leaving old attribute bytes or power-on garbage there would
; show as speckling the moment this mode is entered).
; ============================================================================
MODE64_ON:
    ld   a, 2
    ld   (GFX_MODE), a

    ld   a, (GFX_PALETTE64)
    add  a, a
    add  a, a
    add  a, a
    or   6
    ld   b, a                    ; b = new bits 0-5 combined
    ld   a, (PORT_FF_SHADOW)
    and  %11000000               ; keep only bits 6-7 (EXROM enable,
                                  ; keyboard-interrupt disable) — this
                                  ; mode's own bits occupy 0-5 entirely
    or   b
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    xor  a
    ld   (hl), a
    ldir
    ret

; ============================================================================
; MODE64_OFF ( -- )
; Returns to Normal mode — delegates to kernel/graphics's own inherited
; GFX_SET_MODE(0), which is completely unchanged from 2068-Leap and
; still handles Normal mode correctly; no need to duplicate that path.
; ============================================================================
MODE64_OFF:
    xor  a
    jp   GFX_SET_MODE

; ============================================================================
; MODE64_SET_PALETTE ( A = palette 0-7 -- )
; Selects the ink/paper pair. Stores the choice regardless of the
; currently active mode (so entering 64-column mode later remembers
; the last palette picked), and updates the port immediately too if
; 64-column mode is already active.
; ============================================================================
MODE64_SET_PALETTE:
    and  %00000111
    ld   (GFX_PALETTE64), a

    ld   a, (GFX_MODE)
    cp   2
    ret  nz

    ld   a, (GFX_PALETTE64)
    add  a, a
    add  a, a
    add  a, a
    or   6
    ld   b, a
    ld   a, (PORT_FF_SHADOW)
    and  %11000000
    or   b
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a
    ret

; ============================================================================
; GFX_PIXEL64_ADDR_SETUP (internal, not a public entry point) — shared
; address computation for MODE64_WRITE_PIXEL/MODE64_READ_PIXEL. Reuses
; kernel/graphics's own already-verified BIT_MASK_TABLE/ROW_BASE_TABLE
; and GFX_PIXEL_ROW/GFX_PIXEL_SCANLINE scratch for the row/scanline
; part — identical to the single-file case, only the column math and
; the choice of which display file differ.
; In:  HL = x (0-511, caller masks/clamps), C = y (0-191, caller clamps)
; Out: HL = bitmap byte address, A = bit mask (bit7 = leftmost)
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PIXEL64_ADDR_SETUP:
    ld   a, l
    and  7
    ld   e, a
    ld   d, 0
    push hl
    ld   hl, BIT_MASK_TABLE
    add  hl, de
    ld   a, (hl)
    ld   (GFX_PIXEL64_MASK), a
    pop  hl

    srl  h
    rr   l
    srl  h
    rr   l
    srl  h
    rr   l

    ld   a, l
    and  1
    ld   (GFX_PIXEL64_WHICH_FILE), a

    srl  l
    ld   a, l
    ld   (GFX_PIXEL64_BYTECOL), a

    ld   a, c
    and  7
    ld   (GFX_PIXEL_SCANLINE), a
    ld   a, c
    rrca
    rrca
    rrca
    and  %00011111
    ld   (GFX_PIXEL_ROW), a

    ld   a, (GFX_PIXEL_ROW)
    ld   l, a
    ld   h, 0
    add  hl, hl
    ld   de, ROW_BASE_TABLE
    add  hl, de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ld   a, (GFX_PIXEL64_BYTECOL)
    add  a, e
    ld   e, a
    jr   nc, .no_col_carry
    inc  d
.no_col_carry:
    ld   a, (GFX_PIXEL_SCANLINE)
    add  a, d
    ld   d, a

    ld   h, d
    ld   l, e
    ld   a, (GFX_PIXEL64_WHICH_FILE)
    or   a
    jr   z, .no_delta
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
.no_delta:
    ld   a, (GFX_PIXEL64_MASK)
    ret

; ============================================================================
; MODE64_WRITE_PIXEL ( HL = x 0-511, C = y 0-191, D = OVER flag -- )
; Sets or XOR-toggles one pixel in 64-column mode. No attribute step —
; see this file's own header on the single shared palette.
; ============================================================================
MODE64_WRITE_PIXEL:
    ld   a, d
    ld   (GFX_PIXEL64_OVER), a
    call GFX_PIXEL64_ADDR_SETUP
    ld   b, a
    ld   a, (GFX_PIXEL64_OVER)
    or   a
    jr   z, .set
    ld   a, (hl)
    xor  b
    jr   .write
.set:
    ld   a, (hl)
    or   b
.write:
    ld   (hl), a
    ret

; ============================================================================
; MODE64_READ_PIXEL ( HL = x 0-511, C = y 0-191 -- A = 1 or 0 )
; ============================================================================
MODE64_READ_PIXEL:
    call GFX_PIXEL64_ADDR_SETUP
    ld   b, a
    ld   a, (hl)
    and  b
    ret  z
    ld   a, 1
    ret

; ============================================================================
; Real 64-column TEXT mode (stretch goal, tracked since 2026-09-01 in
; docs/PROJECT_PLAN.md; scoped and planned before writing any of this).
;
; KEY DESIGN CHOICE, worth stating plainly: these routines draw the
; SAME 8x8 font glyphs GFX_PUTCHAR already uses, completely unchanged —
; no new font data anywhere. The 512-pixel-wide Mode 6 bitmap this file
; already splits into two 256-wide display files (GFX_PIXEL64_ADDR_
; SETUP above) gives exactly 64 real text columns (32+32) for free once
; 8-pixel-wide glyphs are drawn across BOTH files instead of one — no
; narrower glyph shape needed at all, unlike third-party tools like
; TASWIDE, which apparently drew genuinely narrower (~4px) glyphs (see
; docs/PROJECT_PLAN.md's own research). This project's version is
; mathematically exact (32+32=64) rather than "roughly" anything, and
; costs zero new ROM bytes for font data.
;
; Every routine below is modeled directly on an already-verified
; kernel/graphics/graphics.asm counterpart (GFX_PUTCHAR/_OVER,
; GFX_COPY_ROW_BITMAP, GFX_SCROLL_TEXT_UP, GFX_CLEAR_ROW) — same
; algorithm, adapted only for "which of the two display files" and "no
; per-cell attribute byte to move" (Mode 6 has none — see this file's
; own header on the single shared palette).
; ============================================================================

; ============================================================================
; MODE64_CHAR_ADDR_SETUP (internal — not a public entry point)
; Shared address computation for MODE64_PUTCHAR/_XOR. Mirrors GFX_CHAR_
; SETUP's own row/column addressing exactly (GFX_ROW_BASE_ADDR + column
; is a Primary-Display-File-relative bitmap address), except the column
; here is 0-63: columns 0-31 land in the Primary Display File exactly
; as GFX_CHAR_SETUP's own column already would, and columns 32-63 land
; at the SAME relative offset (col-32) in the Second Display File
; instead — `col & 31` gives that offset either way (32-63 wraps to
; 0-31 in exactly the range needed), and `col >= 32` selects which
; file, the same bit-3-of-the-byte-column split GFX_PIXEL64_ADDR_SETUP
; already uses for pixels above, just at character-column granularity
; instead of pixel granularity.
; In:  A = ASCII character, B = row (0-23), C = column (0-63)
; Out: carry clear + HL = pointer to the glyph's 8 font bytes, DE =
;      bitmap address of the character cell's top-left pixel (in
;      whichever display file col selects); carry set (HL/DE
;      undefined) if row>=24 or col>=64 — caller must not draw
; Destroys: AF, BC
; ============================================================================
MODE64_CHAR_ADDR_SETUP:
    ld   d, a                      ; stash the character (GFX_CHAR_
                                   ; SETUP's own reasoning: A is about
                                   ; to be scratch for the bounds check)
    ld   a, b
    cp   24
    jr   nc, .out_of_range
    ld   a, c
    cp   64
    jr   nc, .out_of_range
    ld   a, d                      ; restore the character
    push bc                        ; preserve row/col -- GFX_CHAR_TO_
                                   ; FONT_OFFSET's own punctuation-table
                                   ; scan uses B as its loop counter
                                   ; internally (the exact clobber
                                   ; GFX_CHAR_SETUP's own header already
                                   ; documents and guards against)
    call GFX_CHAR_TO_FONT_OFFSET
    jr   nc, .have_offset
    ld   hl, FONT_TABLE             ; unmapped character -> render as
                                    ; space, same convention as
                                    ; GFX_CHAR_SETUP
.have_offset:
    pop  bc                          ; restore row/col
    push hl                            ; save glyph pointer

    ld   a, b
    call GFX_ROW_BASE_ADDR             ; hl = row base, Primary-relative
    ex   de, hl                        ; de = row base

    ld   a, c
    and  31                            ; byte-column within whichever
                                       ; file (0-31 either way)
    add  a, e
    ld   e, a
    jr   nc, .no_col_carry
    inc  d
.no_col_carry:                         ; de = row base + byte-column,
                                       ; still Primary-relative

    ld   a, c
    cp   32
    jr   c, .primary_file
    ld   hl, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ex   de, hl                        ; de = Second-Display-File address
.primary_file:
    pop  hl                                ; hl = glyph pointer
    or   a                                ; clear carry -- success
    ret

.out_of_range:
    scf
    ret

; ============================================================================
; MODE64_PUTCHAR
; Plots one character at a 64-column character-grid position. Mirrors
; GFX_PUTCHAR's own scanline blit exactly (see that routine's header).
; In:  A = ASCII character, B = row (0-23), C = column (0-63)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_PUTCHAR:
    call MODE64_CHAR_ADDR_SETUP
    ret  c
    ld   b, 8
.scanline_loop:
    ld   a, (hl)
    ex   de, hl
    ld   (hl), a
    inc  h
    ex   de, hl
    inc  hl
    djnz .scanline_loop
    ret

; ============================================================================
; MODE64_PUTCHAR_XOR
; Same addressing as MODE64_PUTCHAR, XOR-blitted instead of overwritten
; (mirrors GFX_PUTCHAR_OVER exactly) -- self-inverting, so calling this
; twice at the same position restores the original bits. Used only for
; the 64-column editor's own cursor block (core/editor.asm): Mode 6 has
; no per-cell attribute byte to invert the way the 32-column cursor
; does (GFX_INVERT_ATTR) or to blink via the ULA's own hardware FLASH
; bit, so the 64-column cursor is a STATIC (non-blinking) inverted
; block instead -- drawn by XOR-ing the glyph already there with a
; solid block shape, one call per redraw, never toggled by a timer.
; In:  B = row (0-23), C = column (0-63)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_PUTCHAR_XOR:
    ld   a, " "                    ; any always-mapped character drives
                                   ; MODE64_CHAR_ADDR_SETUP's address
                                   ; math correctly -- its own glyph
                                   ; pointer (HL) is simply never read
                                   ; below, since every scanline here
                                   ; draws a solid block ($FF) instead
                                   ; of a real glyph byte
    call MODE64_CHAR_ADDR_SETUP    ; DE = screen address, HL = glyph
                                   ; pointer (unused)
    ret  c
    ex   de, hl                    ; hl = screen address
    ld   b, 8
.scanline_loop:
    ld   a, (hl)
    xor  $FF                       ; solid block, every pixel set
    ld   (hl), a
    inc  h                         ; screen address += 256 (next
                                   ; scanline)
    djnz .scanline_loop
    ret

; ============================================================================
; MODE64_COPY_ROW_BITMAP (internal — not a public entry point)
; Mirrors GFX_COPY_ROW_BITMAP exactly, except each scanline's 32 bytes
; are copied in BOTH display files (Primary AND Second) instead of
; just one -- Mode 6 has no attribute byte to move separately the way
; GFX_SCROLL_TEXT_UP's own attribute LDIR does, so there is nothing
; else this routine needs to touch.
; In:  (GFX_SCROLL_DST_ROW), (GFX_SCROLL_SRC_ROW) already set by the
;      caller -- same shared scratch cells GFX_COPY_ROW_BITMAP uses,
;      safe to reuse since this project is single-threaded and the two
;      video modes are never scrolled concurrently
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_COPY_ROW_BITMAP:
    ld   a, (GFX_SCROLL_DST_ROW)
    call GFX_ROW_BASE_ADDR          ; hl = dst row base (Primary-relative)
    push hl
    ld   a, (GFX_SCROLL_SRC_ROW)
    call GFX_ROW_BASE_ADDR          ; hl = src row base (Primary-relative)
    pop  de                         ; de = dst row base
    ld   b, 8                       ; 8 scanlines per text row
.scanline_loop:
    push bc
    push hl
    push de
    ld   bc, 32
    ldir                            ; Primary Display File
    pop  de
    pop  hl
    push hl
    push de
    ld   bc, SECOND_DISPLAY_DELTA_M64
    add  hl, bc
    ex   de, hl
    add  hl, bc
    ex   de, hl                     ; hl = src+delta, de = dst+delta
    push bc
    ld   bc, 32
    ldir                            ; Second Display File
    pop  bc
    pop  de
    pop  hl                         ; restore PRE-delta bases for the
                                    ; scanline-advance step below
    ld   a, h
    inc  a
    ld   h, a
    ld   a, d
    inc  a
    ld   d, a
    pop  bc
    djnz .scanline_loop
    ret

; ============================================================================
; MODE64_SCROLL_TEXT_UP
; Mirrors GFX_SCROLL_TEXT_UP exactly (same 23-row program-listing
; window, same row-22-left-for-the-caller-to-draw contract), scrolling
; BOTH display files via MODE64_COPY_ROW_BITMAP instead of one via
; GFX_COPY_ROW_BITMAP -- no attribute LDIR step at all, since Mode 6
; has none.
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_SCROLL_TEXT_UP:
    xor  a
    ld   (GFX_SCROLL_DST_ROW), a
.row_loop:
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_SRC_ROW), a
    call MODE64_COPY_ROW_BITMAP
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_DST_ROW), a
    cp   22
    jr   c, .row_loop
    ret

; ============================================================================
; MODE64_CLEAR_ROW
; Clears one 64-column text row (both display files) to blank. Mirrors
; GFX_CLEAR_ROW, minus its attribute-clear half (nothing to clear).
; In:  B = row (0-23)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_CLEAR_ROW:
    ld   c, 0
.loop:
    push bc
    ld   a, " "
    call MODE64_PUTCHAR
    pop  bc
    inc  c
    ld   a, c
    cp   64
    jr   c, .loop
    ret

; ============================================================================
; MODE64_SCROLL_OUTPUT_UP
; Mirrors GFX_SCROLL_OUTPUT_UP exactly (scroll all 24 rows, not just
; the 23-row program-listing window MODE64_SCROLL_TEXT_UP protects) --
; needed by core/editor.asm's own EDITOR_REDRAW when a wrapped input
; line grows onto a screen row that still holds recent output. No
; attribute LDIR step (Mode 6 has none).
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MODE64_SCROLL_OUTPUT_UP:
    call MODE64_SCROLL_TEXT_UP
    ld   a, 22
    ld   (GFX_SCROLL_DST_ROW), a
    ld   a, 23
    ld   (GFX_SCROLL_SRC_ROW), a
    call MODE64_COPY_ROW_BITMAP
    ld   b, 23
    jp   MODE64_CLEAR_ROW

    ENDIF
