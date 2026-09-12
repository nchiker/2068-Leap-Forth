; ============================================================================
; core/polygon.asm — POLYGON, an outline drawn through EXROM
;
; Builds on core/dict.asm, core/interp.asm, core/ts2068.asm (needs
; CURRENT_ATTR), kernel/bank/bank.asm (needs BANK_PAGE_EXROM_IN/OUT),
; and core/rectfill.asm specifically — that file owns the actual
; EXROM_CALL_SLOT trampoline and GRAPHICS_EXROM_MAGIC_ADDR/CALL_HL this
; file reuses (a real duplicate across this file, core/rectfill.asm,
; and core/sprite.asm was found and merged there — see that file's own
; EXROM_CALL_SLOT header). All of the above must be INCLUDEd first.
; This file's own first header chains through DICT_CHAIN_POINT.
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
    ld   hl, $A000 + (1 * 3)   ; slot 1 = POLY_DRAW_IMPL
    call EXROM_CALL_SLOT
.invalid:
    ret

DICT_LATEST_INIT_POLYGON EQU H_POLYGON   ; head of the dictionary once
                                         ; this file's own words are
                                         ; both included

    ENDIF
