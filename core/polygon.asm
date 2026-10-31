; ============================================================================
; core/polygon.asm -- POLYGON and POLYGON-FILL, drawn through the EXROM
;
; Needs core/dict.asm, core/interp.asm, core/ts2068.asm (CURRENT_ATTR), kernel/bank/bank.asm and
; core/rectfill.asm (EXROM_CALL_SLOT, CALL_HL) INCLUDEd first. The including ROM sets
; DICT_CHAIN_POINT (DEFL). Dictionary words destroy every register except IX/IY/SP.
;
; n is validated before any vertex is popped: the argument count depends on n, so for an
; out-of-range n (below 3 or above POLY_MAXPTS) the word cannot know how many cells were meant
; for it. It refuses and leaves the rest of the stack as it found it. POLY_POP_VERTICES does the
; validation and the pop for both words.
; ============================================================================

    IFNDEF CORE_POLYGON_ASM
    DEFINE CORE_POLYGON_ASM

; ============================================================================
; POLY_POP_VERTICES -- pop n, validate it, pop that many (x,y) pairs into POLY_VERTS
; In:  data stack ( x1 y1 x2 y2 ... xn yn n -- )
; Out: carry set if n was out of range (only n popped); carry clear with POLY_COUNT and
;      POLY_VERTS staged if n was 3..POLY_MAXPTS
; Destroys: AF, BC, DE, HL (writes POLY_IDX too)
; ============================================================================
POLY_POP_VERTICES:
    rst RST_DPOP            ; hl = n
    ld   a, l
    cp   3
    jr   c, .invalid          ; n < 3
    cp   POLY_MAXPTS + 1
    jr   nc, .invalid         ; n > POLY_MAXPTS
    ld   (POLY_COUNT), a

    dec  a
    ld   (POLY_IDX), a        ; i = n-1, counting down as we pop
.pop_loop:
    rst RST_DPOP             ; hl = y_i
    ld   d, l                 ; stash y_i (DPOP_HL never touches D)
    rst RST_DPOP             ; hl = x_i
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
; POLYGON ( x1 y1 x2 y2 ... xn yn n -- ) -- draw the closed outline through the n vertices
; (3..POLY_MAXPTS), each edge a GFX_LINE and the last back to the first, in CURRENT_ATTR's
; colour (EXROM service slot 1, POLY_DRAW_IMPL); an out-of-range n draws nothing
; ============================================================================
H_POLYGON:
    DW   DICT_CHAIN_POINT
    DB   7, "P", "O", "L", "Y", "G", "O", "N"
W_POLYGON:
    call POLY_POP_VERTICES
    ret  c                     ; n was out of range: already refused

    ld   a, (CURRENT_ATTR)
    ld   (POLY_ATTR), a
    ld   hl, GRAPHICS_EXROM_BASE + (1 * 3)   ; slot 1 = POLY_DRAW_IMPL
    jp   EXROM_CALL_SLOT

; ============================================================================
; POLYGON-FILL ( x1 y1 x2 y2 ... xn yn n -- ) -- fill the polygon's interior (even-odd rule),
; same arguments as POLYGON; no outline is drawn (EXROM service slot 5, POLY_FILL_IMPL)
; ============================================================================
H_POLYGONFILL:
    DW   H_POLYGON
    DB   12, "P", "O", "L", "Y", "G", "O", "N", "-", "F", "I", "L", "L"
W_POLYGONFILL:
    call POLY_POP_VERTICES
    ret  c

    ld   a, (CURRENT_ATTR)
    ld   (POLY_ATTR), a
    ld   hl, GRAPHICS_EXROM_BASE + (5 * 3)   ; slot 5 = POLY_FILL_IMPL
    jp   EXROM_CALL_SLOT


    ENDIF
