; ============================================================================
; core/polygon.asm — POLYGON, an outline drawn through EXROM
;
; Builds on core/dict.asm, core/interp.asm, core/ts2068.asm (needs
; CURRENT_ATTR), and kernel/bank/bank.asm (needs BANK_PAGE_EXROM_IN/
; OUT) — all must be INCLUDEd first, same prerequisites core/
; rectfill.asm already has (this file follows its exact shape). This
; file's own first header chains through DICT_CHAIN_POINT.
;
; WHAT THIS ADDS:
;   POLYGON ( x1 y1 x2 y2 ... xn yn n -- )   draws the closed outline
;             through the n given vertices (3-12), each edge a GFX_
;             LINE, the last edge closing back to the first vertex,
;             all in the current color (CURRENT_ATTR) — via rom/
;             graphics_exrom.asm's own POLY_DRAW_IMPL (service slot 1)
;
; n IS VALIDATED BEFORE ANY VERTEX IS POPPED, deliberately: unlike
; FILL/RECT's fixed argument count, POLYGON's own argument count
; depends on n itself, so an out-of-range n (fewer than 3, or more
; than POLY_MAXPTS) means this word has no reliable way to know how
; many stack cells were actually meant for it — refusing immediately,
; leaving the rest of the stack exactly as the caller left it, is the
; only safe response; silently popping a guessed number of cells could
; consume values that belong to something else entirely.
;
; NOT YET IMPLEMENTED: filling the polygon's interior (only the
; outline draws today) — POLYGON-FILL is reserved as service slot 2 in
; rom/graphics_exrom.asm's own table, a planned follow-on, not
; forgotten.
; ============================================================================

    IFNDEF CORE_POLYGON_ASM
    DEFINE CORE_POLYGON_ASM

; ============================================================================
; EXROM_CALL_POLY_DRAW (internal — not in kernel_api.inc)
; Pages chunk 5 to EXROM, verifies rom/graphics_exrom.asm's own magic+
; ABI byte pair (same check core/rectfill.asm's own EXROM_CALL_
; RECT_FILL already makes — see that routine's own header for why this
; isn't blind trust), calls service-table slot 1 (POLY_DRAW_IMPL) if
; and only if that check passes, then always pages back out.
; In:  POLY_COUNT/POLY_VERTS/POLY_ATTR — pre-set by W_POLYGON below
; Out: carry SET if the paged image didn't match (nothing was drawn);
;      carry CLEAR if POLY_DRAW_IMPL actually ran
; Destroys: AF, BC, DE, HL
; ============================================================================
EXROM_CALL_POLY_DRAW:
    call BANK_PAGE_EXROM_IN

    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR)   ; same computed offset
    cp   GRAPHICS_EXROM_MAGIC             ; core/rectfill.asm's own
    jr   nz, .mismatch                    ; EXROM_CALL_RECT_FILL uses —
    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR + 1) ; see that file's own
    cp   GRAPHICS_EXROM_ABI               ; comment on why this is
    jr   nz, .mismatch                    ; computed, not hand-typed

    ld   hl, $A003                   ; slot 1 = POLY_DRAW_IMPL
    call CALL_HL
    call BANK_PAGE_EXROM_OUT
    or   a
    ret

.mismatch:
    call BANK_PAGE_EXROM_OUT
    scf
    ret

; ============================================================================
; CALL_HL (internal — not in kernel_api.inc)
; `call (hl)` isn't a real Z80 instruction — this is the standard
; workaround (push the target, then RET jumps to it), needed here
; because EXROM_CALL_POLY_DRAW's own call target (slot 1, $A003) isn't
; a compile-time constant name the way RECT's own `call $A000` is (it
; genuinely could be, but spelling it through HL keeps this routine
; obviously reusable for whichever slot number a future caller in this
; same file needs, without repeating this same push/ret trick inline
; each time).
; In:  HL = address to call
; Out: whatever the called code returns
; Destroys: whatever the called code destroys
; ============================================================================
CALL_HL:
    push hl
    ret

; ============================================================================
; POLYGON ( x1 y1 x2 y2 ... xn yn n -- )
; ============================================================================
H_POLYGON:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   7, "P", "O", "L", "Y", "G", "O", "N"
W_POLYGON:
    call DPOP_HL             ; hl = n
    ld   a, l
    cp   3
    jr   c, .invalid          ; n<3: refuse, touch nothing else
    cp   POLY_MAXPTS + 1
    jr   nc, .invalid         ; n>POLY_MAXPTS: refuse, touch nothing else
    ld   (POLY_COUNT), a

    dec  a
    ld   (POLY_IDX), a        ; i = n-1, counting down as we pop
.pop_loop:
    call DPOP_HL              ; hl = y_i
    ld   d, l                 ; stash y_i (DPOP_HL never touches D)
    call DPOP_HL              ; hl = x_i
    ld   e, l                 ; E = x_i, D = y_i

    ld   a, (POLY_IDX)
    ld   l, a
    ld   h, 0
    add  hl, hl                ; hl = 2*i
    ld   bc, POLY_VERTS
    add  hl, bc                ; hl = POLY_VERTS + 2*i
    ld   (hl), e                ; store x_i
    inc  hl
    ld   (hl), d                ; store y_i

    ld   a, (POLY_IDX)
    or   a
    jr   z, .pop_done          ; i reached 0: every vertex staged
    dec  a
    ld   (POLY_IDX), a
    jr   .pop_loop
.pop_done:

    ld   a, (CURRENT_ATTR)
    ld   (POLY_ATTR), a
    call EXROM_CALL_POLY_DRAW
.invalid:
    ret

DICT_LATEST_INIT_POLYGON EQU H_POLYGON   ; head of the dictionary once
                                         ; this file's own words are
                                         ; both included

    ENDIF
