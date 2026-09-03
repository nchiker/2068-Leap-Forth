; ============================================================================
; core/moregfx.asm — Phase 17: FILL and AT-XY
;
; Builds on core/dict.asm, core/interp.asm, core/ts2068.asm (needs
; CURRENT_ATTR, Phase 15), and core/print.asm (needs PRINT_ROW/
; PRINT_COL, Phase 10) — all must be INCLUDEd first. This file's own
; first header chains through DICT_CHAIN_POINT, same convention as
; every phase since core/control.asm.
;
; WHAT THIS ADDS — the rest of docs/forth_tutorial.md's "More graphics"
; gap (hi-res mode is not attempted here — a bigger undertaking, left
; open):
;   FILL   ( x y -- )   flood-fills the enclosed region containing
;             (x, y) with the current color (CURRENT_ATTR, same state
;             INK/PAPER set — Phase 15), using kernel/graphics's own
;             proven GFX_FILL
;   AT-XY  ( col row -- )   moves EMIT/./."'s own print position
;             (PRINT_COL/PRINT_ROW, core/print.asm) directly, so the
;             next character printed lands at (col, row) instead of
;             wherever printing last left off
;
; FILL sets only GFX_FILL_X/GFX_FILL_Y/GFX_FILL_ATTR before calling
; GFX_FILL — that routine reads the seed pixel's own current state
; itself (GFX_FILL_TARGET) rather than needing it supplied. No range
; checking on AT-XY's col/row (0-31/0-22) — matching every earlier
; phase's own "no error recovery yet" scope note; writing an
; out-of-range position just means the next EMIT/./."-drawn character
; lands somewhere unintended, not a crash.
;
; FILL REFUSES TO RUN IN 64-COLUMN MODE (added Phase 44 — see
; include/sysvars.inc's own GFX_FILL_VISITED header for the full
; writeup): to raise the dictionary's own ceiling (core/free.asm),
; GFX_FILL's scratch buffers were relocated into the idle video-RAM
; pool at $5B00-$7FFF — the same physical range 64-column mode's
; second display file lives in ($6000-$77FF, hardware-fixed). Running
; FILL while 64COL mode is active would corrupt whichever one runs
; second. Checked via GFX_MODE (2 = 64-column, set by MODE64_ON in
; kernel/mode64/mode64.asm) before calling GFX_FILL; if active, FILL
; still consumes its (x y) arguments (this project's established
; convention — SOUND/STICK do the same for out-of-range input) but
; silently does nothing instead of running.
; ============================================================================

    IFNDEF CORE_MOREGFX_ASM
    DEFINE CORE_MOREGFX_ASM

; ============================================================================
; FILL ( x y -- )
; ============================================================================
H_FILL:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   4, "F", "I", "L", "L"
W_FILL:
    call DPOP_HL           ; hl = y
    ld   a, l
    ld   (GFX_FILL_Y), a
    call DPOP_HL           ; hl = x
    ld   a, l
    ld   (GFX_FILL_X), a
    ld   a, (GFX_MODE)
    cp   2                  ; 2 = 64-column mode active (kernel/mode64's
                             ; MODE64_ON) -- FILL's own relocated
                             ; scratch overlaps its second display file,
                             ; see this file's own header
    ret  z                  ; arguments already consumed above; silently
                             ; do nothing, matching this project's own
                             ; established out-of-range convention
    ld   a, (CURRENT_ATTR)
    ld   (GFX_FILL_ATTR), a
    call GFX_FILL
    ret

; ============================================================================
; AT-XY ( col row -- )
; ============================================================================
H_ATXY:
    DW   H_FILL
    DB   5, "A", "T", "-", "X", "Y"
W_ATXY:
    call DPOP_HL           ; hl = row
    ld   a, l
    ld   (PRINT_ROW), a
    call DPOP_HL           ; hl = col
    ld   a, l
    ld   (PRINT_COL), a
    ret

DICT_LATEST_INIT_MOREGFX EQU H_ATXY   ; head of the dictionary once
                                       ; this file's own words are
                                       ; included

    ENDIF
