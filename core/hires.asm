; ============================================================================
; core/hires.asm — Phase 55: HIRES and NORMAL (High Resolution Graphics
; mode)
;
; Builds on core/dict.asm, core/interp.asm, and core/ts2068.asm (needs
; CURRENT_ATTR) — all must be INCLUDEd first. This file's own first
; header chains through DICT_CHAIN_POINT, same convention as every
; phase since core/control.asm. Also needs kernel/graphics/graphics.asm
; (already INCLUDEd by every ROM this file matters to) for GFX_SET_MODE
; and GFX_MODE.
;
; WHAT THIS ADDS — closes docs/forth_tutorial.md's Appendix B gap,
; "Hi-res graphics mode", the only item left on that list:
;   HIRES  ( -- )   switches to High Resolution Graphics mode
;   NORMAL ( -- )   switches back to Normal mode
;
; NOT a new algorithm: kernel/graphics/graphics.asm's own GFX_SET_MODE
; already implements real TS2068 High Resolution Graphics mode
; (inherited from 2068-Leap, unused by this project until now) — same
; 256x192 pixel bitmap as Normal mode, but color resolution of one
; attribute byte per SCANLINE per column (GFX_SET_ATTR_EXT, backed by
; the Second Display File at SECOND_DISPLAY_ADDR) instead of one per
; 8x8 character cell. GFX_WRITE_PIXEL/GFX_READ_PIXEL already branch on
; GFX_MODE internally, so PLOT/LINE/CIRCLE (core/ts2068.asm) all become
; mode-aware for free — nothing in this file touches them.
;
; WORD CHOICE: TS2068 BASIC's own statement is `MODE n` (0/1/2), with
; the caller responsible for validating `n` first (see GFX_SET_MODE's
; own header). This project's mode64 stretch goal (Phase 8) already
; departed from that shape in favor of zero-argument flag words (64COL/
; 32COL) rather than a validated-argument MODE, and HIRES/NORMAL follow
; that same established precedent — no invalid-mode-number case to
; guard against at all, since neither word takes a stack argument.
;
; TWO REAL HAZARDS FOUND AND FIXED WHILE WIRING THIS IN (both because
; GFX_MODE=1 was UNREACHABLE from any Forth word before this phase, so
; neither one had ever actually triggered in a shipped ROM):
;
;   1. core/moregfx.asm's FILL only ever guarded against GFX_MODE=2
;      (64-column mode) sharing its relocated scratch RAM with the
;      Second Display File — HIRES's GFX_MODE=1 shares the exact same
;      RAM ($6000-$77FF) for the exact same reason (real per-scanline
;      attribute data instead of 64-column's second bitmap plane) and
;      was NOT guarded against. Widened that check from `cp 2` to
;      `or a` (any nonzero mode) — see that file's own header and
;      include/sysvars.inc's GFX_FILL_VISITED comment.
;
;   2. core/ts2068.asm's CLS (`W_CLS`) repaints the NORMAL attribute
;      area (GFX_PAINT_ATTR) but never touched the Second Display File.
;      GFX_SET_MODE's own one-time mode-ENTRY transition already clears
;      it to ATTR_DEFAULT, but a CLS called *while already in HIRES* (a
;      completely ordinary thing to do mid-program, to clear the screen
;      for a fresh drawing) left every stale per-scanline attribute byte
;      in place. Extended W_CLS to also clear the Second Display File
;      to CURRENT_ATTR whenever GFX_MODE=1 — see that file's own W_CLS
;      for the actual fix, applied there (not here) since CLS itself
;      lives in core/ts2068.asm, not this file.
; ============================================================================

    IFNDEF CORE_HIRES_ASM
    DEFINE CORE_HIRES_ASM

; ============================================================================
; HIRES ( -- )
; ============================================================================
H_HIRES:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "H", "I", "R", "E", "S"
W_HIRES:
    ld   a, 1
    call GFX_SET_MODE
    ret

; ============================================================================
; NORMAL ( -- )
; ============================================================================
H_NORMAL:
    DW   H_HIRES
    DB   6, "N", "O", "R", "M", "A", "L"
W_NORMAL:
    xor  a
    call GFX_SET_MODE
    ret

DICT_LATEST_INIT_HIRES EQU H_NORMAL   ; head of the dictionary once
                                       ; this file's own words are
                                       ; included

    ENDIF
