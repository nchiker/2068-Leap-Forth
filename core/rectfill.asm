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
; MAGIC+ABI CHECK, not blind trust: EXROM_CALL_SLOT below (shared by
; every word this project backs with rom/graphics_exrom.asm — see its
; own header) verifies that file's own magic byte ($F0) and ABI
; version (1) immediately after paging chunk 5 in, before calling
; anything in its service table. A real cartridge socket can hold
; something else entirely, or nothing — this project's own EXROM
; placeholder history (tools/make_exrom_placeholder.sh) already
; established that an empty/wrong image is a real, reachable case, not
; a hypothetical one. A mismatch pages back out and returns with carry
; SET; RECT then silently does nothing, matching this project's own
; established "silently do nothing on unavailable/out-of-range"
; convention (SOUND, STICK, FILL's own 64-column guard) rather than a
; new error path.
; ============================================================================

    IFNDEF CORE_RECTFILL_ASM
    DEFINE CORE_RECTFILL_ASM

; ============================================================================
; EXROM_CALL_SLOT (internal — not in kernel_api.inc)
; Pages chunk 5 to EXROM, verifies rom/graphics_exrom.asm's own magic+
; ABI byte pair, calls the given service-table slot if and only if
; that check passes, then always pages back out (even on a mismatch)
; before returning. Shared by every word backed by rom/graphics_
; exrom.asm — RECT, POLYGON, and all three SPRITE-* words each used to
; carry their own copy of this exact sequence (core/polygon.asm's own
; EXROM_CALL_POLY_DRAW, core/sprite.asm's own EXROM_CALL_SPRITE);
; consolidated here once real duplication was confirmed across all
; three (same shape, differing only in which slot address gets
; called) — 95 bytes of near-identical Home ROM code down to one
; ~30-byte routine plus a handful of 5-byte call sites, found and
; fixed the same session the Home ROM budget got tight enough (49
; bytes free) that it actually mattered.
; In:  HL = absolute address of the service-table slot to call
;      ($A000 + slot*3); whatever RECT_*/POLY_*/SPRITE_OP_* state the
;      caller has already staged
; Out: carry SET if the paged image didn't match (nothing ran); carry
;      CLEAR if the slot actually ran
; Destroys: AF, BC, DE, HL
; ============================================================================
EXROM_CALL_SLOT:
    push hl                          ; the slot address survives the
                                     ; page-in call (BANK_PAGE_EXROM_IN
                                     ; only destroys AF per its own
                                     ; contract, but stack is simplest
                                     ; and matches this project's own
                                     ; "don't trust a register to
                                     ; survive a call" convention)
    call BANK_PAGE_EXROM_IN
    pop  hl

    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR)
    cp   GRAPHICS_EXROM_MAGIC
    jr   nz, .mismatch
    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR + 1)
    cp   GRAPHICS_EXROM_ABI
    jr   nz, .mismatch

    call CALL_HL                     ; see CALL_HL's own header —
                                     ; a genuine nested CALL (not a
                                     ; tail JUMP), so control returns
                                     ; here afterward and BANK_PAGE_
                                     ; EXROM_OUT below still runs
    call BANK_PAGE_EXROM_OUT
    or   a                           ; carry clear: ran successfully
    ret

.mismatch:
    call BANK_PAGE_EXROM_OUT
    scf
    ret

; ============================================================================
; CALL_HL (internal — not in kernel_api.inc)
; `call (hl)` isn't a real Z80 instruction — this is the standard
; workaround (push the target, then RET jumps to it). Genuinely a
; nested call, not a tail jump: EXROM_CALL_SLOT's own `call CALL_HL`
; already pushed a return address before this runs, and `push hl` here
; pushes the slot address ON TOP of that — so THIS routine's own `ret`
; consumes the slot address (jumping there), and the slot's own
; eventual `ret` is what actually consumes EXROM_CALL_SLOT's original
; return address, landing control back there once the slot is done.
; In:  HL = address to call
; Out: whatever the called code returns
; Destroys: whatever the called code destroys
; ============================================================================
CALL_HL:
    push hl
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
    ld   hl, $A000 + (0 * 3)   ; slot 0 = RECT_FILL_IMPL
    call EXROM_CALL_SLOT
    ret

DICT_LATEST_INIT_RECTFILL EQU H_RECT   ; head of the dictionary once
                                       ; this file's own words are
                                       ; both included

    ENDIF
