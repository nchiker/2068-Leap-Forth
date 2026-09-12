; ============================================================================
; core/rectfill.asm — RECT, a fast rectangle fill backed by EXROM
;
; Builds on core/dict.asm, core/interp.asm, core/ts2068.asm (needs
; CURRENT_ATTR), and kernel/bank/bank.asm (needs BANK_PAGE_EXROM_IN/
; OUT) — all must be INCLUDEd first. This file's own first header
; chains through DICT_CHAIN_POINT, same convention as every phase
; since core/control.asm.
;
; WHAT THIS ADDS:
;   RECT ( x0 y0 x1 y1 -- )   fills the rectangle spanned by the two
;             given corners (any order — the EXROM side sorts them),
;             corners inclusive, with the current color (CURRENT_ATTR,
;             same state INK/PAPER set), via rom/graphics_exrom.asm's
;             own RECT_FILL_IMPL
;
; WHY THIS IS EXROM-RESIDENT rather than a plain Home word like FILL:
; the Home ROM had 444 bytes free at the time this was scoped — not
; enough headroom for this AND the two other new graphics words this
; project has planned (Polygon draw/fill, Sprites), so all three are
; going into the one physical EXROM socket this hardware has, not
; competing for Home's own shrinking budget. See docs/PROJECT_PLAN.md's
; chunk-by-chunk audit for why chunk 5 specifically, and kernel/bank/
; bank.asm's own header for the paging mechanics.
;
; MAGIC+ABI CHECK, not blind trust: EXROM_CALL_RECT_FILL below verifies
; rom/graphics_exrom.asm's own magic byte ($F0) and ABI version (1)
; immediately after paging chunk 5 in, before calling anything in its
; service table. A real cartridge socket can hold something else
; entirely, or nothing — this project's own EXROM placeholder history
; (tools/make_exrom_placeholder.sh) already established that an empty/
; wrong image is a real, reachable case, not a hypothetical one. A
; mismatch pages back out and returns with carry SET; RECT then
; silently does nothing, matching this project's own established
; "silently do nothing on unavailable/out-of-range" convention (SOUND,
; STICK, FILL's own 64-column guard) rather than a new error path.
; ============================================================================

    IFNDEF CORE_RECTFILL_ASM
    DEFINE CORE_RECTFILL_ASM

; ============================================================================
; EXROM_CALL_RECT_FILL (internal — not in kernel_api.inc)
; Pages chunk 5 to EXROM, verifies rom/graphics_exrom.asm's own magic+
; ABI byte pair, calls its service-table slot 0 (RECT_FILL_IMPL) if
; and only if that check passes, then always pages back out (even on
; a mismatch) before returning.
; In:  RECT_X0/Y0/X1/Y1/RECT_ATTR — pre-set by W_RECT below
; Out: carry SET if the paged image didn't match (nothing was drawn);
;      carry CLEAR if RECT_FILL_IMPL actually ran
; Destroys: AF, BC, DE, HL
; ============================================================================
EXROM_CALL_RECT_FILL:
    call BANK_PAGE_EXROM_IN

    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR)
    cp   GRAPHICS_EXROM_MAGIC
    jr   nz, .mismatch
    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR + 1)
    cp   GRAPHICS_EXROM_ABI
    jr   nz, .mismatch

    call $A000                       ; slot 0 = RECT_FILL_IMPL
    call BANK_PAGE_EXROM_OUT
    or   a                           ; carry clear: ran successfully
    ret

.mismatch:
    call BANK_PAGE_EXROM_OUT
    scf
    ret

GRAPHICS_EXROM_MAGIC EQU $F0          ; must match rom/graphics_exrom.
GRAPHICS_EXROM_ABI   EQU 1            ; asm's own copy of these exactly

; Computed, not hand-typed: must exactly match where rom/graphics_
; exrom.asm's own DB GRAPHICS_EXROM_MAGIC actually lands. That file's
; own service table is GRAPHICS_EXROM_MAX_SLOTS (8) slots of 3 bytes
; each, immediately followed by GRAPHICS_EXROM_UNIMPLEMENTED's own
; 1-byte RET, THEN the magic/ABI pair -- this exact formula shipped
; once with that trailing RET byte forgotten (a real off-by-one,
; caught by re-running the RECT/POLYGON smoke ROMs under real ZEsarUX
; after the table was fixed-sized, not by re-deriving the number by
; eye a second time). If rom/graphics_exrom.asm's own table size or
; GRAPHICS_EXROM_UNIMPLEMENTED's own body ever changes, this formula
; must change with it -- there is no shared build-time symbol export
; between these two separately-assembled files yet (a known,
; deliberate gap — see rom/graphics_exrom.asm's own header).
GRAPHICS_EXROM_TABLE_SLOTS   EQU 8
GRAPHICS_EXROM_MAGIC_ADDR    EQU $A000 + (GRAPHICS_EXROM_TABLE_SLOTS * 3) + 1

; ============================================================================
; RECT ( x0 y0 x1 y1 -- )
; ============================================================================
H_RECT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   4, "R", "E", "C", "T"
W_RECT:
    call DPOP_HL            ; hl = y1
    ld   a, l
    ld   (RECT_Y1), a
    call DPOP_HL            ; hl = x1
    ld   a, l
    ld   (RECT_X1), a
    call DPOP_HL            ; hl = y0
    ld   a, l
    ld   (RECT_Y0), a
    call DPOP_HL            ; hl = x0
    ld   a, l
    ld   (RECT_X0), a
    ld   a, (CURRENT_ATTR)
    ld   (RECT_ATTR), a
    call EXROM_CALL_RECT_FILL
    ret

DICT_LATEST_INIT_RECTFILL EQU H_RECT   ; head of the dictionary once
                                       ; this file's own words are
                                       ; both included

    ENDIF
