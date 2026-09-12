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
;   POLYGON-FILL ( x1 y1 x2 y2 ... xn yn n -- )   fills the polygon's
;             interior (even-odd rule) instead of outlining it — via
;             rom/graphics_exrom.asm's own POLY_FILL_IMPL (service
;             slot 5). Same vertex argument shape as POLYGON; does NOT
;             also draw the outline — call POLYGON too (same vertices)
;             if both are wanted, matching this project's own "small
;             composable primitives" convention rather than a hidden
;             combined behavior
;
; n IS VALIDATED BEFORE ANY VERTEX IS POPPED, deliberately: unlike
; FILL/RECT's fixed argument count, POLYGON's own argument count
; depends on n itself, so an out-of-range n (fewer than 3, or more
; than POLY_MAXPTS) means this word has no reliable way to know how
; many stack cells were actually meant for it — refusing immediately,
; leaving the rest of the stack exactly as the caller left it, is the
; only safe response; silently popping a guessed number of cells could
; consume values that belong to something else entirely. POLY_POP_
; VERTICES below does this validation-and-pop once, shared by both
; words, rather than each carrying its own copy — the exact class of
; duplication this project already merged once this session (core/
; rectfill.asm's own EXROM_CALL_SLOT header has the full story).
; ============================================================================

    IFNDEF CORE_POLYGON_ASM
    DEFINE CORE_POLYGON_ASM

; ============================================================================
; POLY_POP_VERTICES (internal — not in kernel_api.inc)
; Pops n, validates it, then pops that many (x,y) pairs into POLY_
; VERTS — the shared argument-handling core of POLYGON and POLYGON-
; FILL below. See this file's own header on why n is checked before
; anything else is popped.
; In:  ( x1 y1 x2 y2 ... xn yn n -- ), same stack shape either caller
;      pops from
; Out: carry SET if n was out of range (nothing further popped, stack
;      otherwise untouched); carry CLEAR and POLY_COUNT/POLY_VERTS
;      staged if n was valid (3-POLY_MAXPTS)
; Destroys: AF, BC, DE, HL
; ============================================================================
POLY_POP_VERTICES:
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
    or   a                     ; carry clear: success
    ret
.invalid:
    scf
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
    call POLY_POP_VERTICES
    ret  c                     ; n was out of range: already refused

    ld   a, (CURRENT_ATTR)
    ld   (POLY_ATTR), a
    ld   hl, $A000 + (1 * 3)   ; slot 1 = POLY_DRAW_IMPL
    call EXROM_CALL_SLOT
    ret

; ============================================================================
; POLYGON-FILL ( x1 y1 x2 y2 ... xn yn n -- )
; ============================================================================
H_POLYGONFILL:
    DW   H_POLYGON
    DB   12, "P", "O", "L", "Y", "G", "O", "N", "-", "F", "I", "L", "L"
W_POLYGONFILL:
    call POLY_POP_VERTICES
    ret  c

    ld   a, (CURRENT_ATTR)
    ld   (POLY_ATTR), a
    ld   hl, $A000 + (5 * 3)   ; slot 5 = POLY_FILL_IMPL
    call EXROM_CALL_SLOT
    ret

DICT_LATEST_INIT_POLYGON EQU H_POLYGONFILL   ; head of the dictionary
                                             ; once this file's own
                                             ; words are all included

    ENDIF
