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
; validation and the pop for both words. A vertex off the screen is moved to its nearest edge (x 0-255, y 0-191),
; as 2068-Leap-C's draw() and box() treat an off-screen coordinate: nothing wraps or is drawn off the screen, and
; a polygon with a corner off the screen is drawn through the moved corner.
; ============================================================================

    IFNDEF CORE_POLYGON_ASM
    DEFINE CORE_POLYGON_ASM

; ============================================================================
; POLY_POP_VERTICES -- pop n, validate it, pop that many (x,y) pairs into POLY_VERTS, each moved onto the screen
; In:  data stack ( x1 y1 x2 y2 ... xn yn n -- ), signed cells
; Out: carry set if n was out of range (only n popped); carry clear with POLY_COUNT and
;      POLY_VERTS staged (bytes, x 0-255, y 0-191) if n was 3..POLY_MAXPTS
; Destroys: AF, BC, DE, HL
; ============================================================================
POLY_POP_VERTICES:
    rst RST_DPOP            ; hl = n
    ld   a, h
    or   a
    jr   nz, .invalid         ; n > 255
    ld   a, l
    cp   3
    jr   c, .invalid          ; n < 3
    cp   POLY_MAXPTS + 1
    jr   nc, .invalid         ; n > POLY_MAXPTS
    ld   (POLY_COUNT), a
    ld   b, a                  ; B = n, the vertices to pop, last first
    add  a, a
    ld   l, a
    ld   h, 0
    ld   de, POLY_VERTS - 1
    add  hl, de                ; HL = the last vertex's y byte
.pop_loop:
    push hl
    rst RST_DPOP               ; hl = y_i
    ld   c, 191
    call .edge
    ld   d, a                  ; D = y_i (DPOP_HL and .edge never touch D or B)
    rst RST_DPOP               ; hl = x_i
    ld   c, 255
    call .edge                 ; A = x_i
    pop  hl
    ld   (hl), d               ; store y_i, then x_i below it
    dec  hl
    ld   (hl), a
    dec  hl
    djnz .pop_loop
    or   a                     ; carry clear: success (.edge's compare may have set it)
    ret
.invalid:
    scf
    ret
.edge:                         ; A = HL (signed) moved into 0..C
    xor  a
    bit  7, h
    ret  nz                    ; negative: 0
    or   h
    ld   a, c
    ret  nz                    ; 256 or more: C
    ld   a, l
    cp   c
    ret  c                     ; below C: as it is
    ld   a, c
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
