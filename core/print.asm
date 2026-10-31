; ============================================================================
; core/print.asm -- EMIT and . : print a character, print a number
;
; Needs core/dict.asm, core/interp.asm and kernel/graphics/graphics.asm. Chained from DICT_CHAIN_POINT
; (set by the including ROM before the INCLUDE); every word may destroy all registers except IX (the data
; stack pointer), IY and SP.
; The output position is PRINT_ROW/PRINT_COL, separate from core/editor.asm's EDIT_CURSOR (the input line,
; row 23). The ROM must initialise both (0, 0 is the natural start). EMIT stays in rows 0-22: reaching row
; 23 scrolls the screen up one row (GFX_SCROLL_TEXT_UP) and continues at row 22. Column 32 wraps. CR ($0D)
; starts a new line instead of printing a glyph; no other control character is special.
; If core/ts2068.asm is INCLUDEd (CORE_TS2068_ASM defined), EMIT also stamps CURRENT_ATTR into the cell.
; `.` needs an unsigned divide by 10, which kernel/math lacks (MATH_DIVIDE16 is signed and would misread
; magnitudes above 32767, including that of -32768): UDIV10 is the private helper. Negating $8000 gives
; $8000, which read as unsigned is the right magnitude 32768.
; ============================================================================

    IFNDEF CORE_PRINT_ASM
    DEFINE CORE_PRINT_ASM

; ============================================================================
; UDIV10 -- unsigned divide by 10, 16 shift-and-subtract steps (not a dictionary word)
; In:  HL = value (0-65535)
; Out: HL = value / 10, A = value mod 10 (0-9)
; Destroys: AF, B
; ============================================================================
UDIV10:
    xor  a
    ld   b, 16
.loop:
    add  hl, hl
    rla
    cp   10
    jr   c, .skip
    sub  10
    inc  l
.skip:
    djnz .loop
    ret

; ============================================================================
; EMIT ( char -- ) -- print one character at the output position and advance it
; ============================================================================
H_EMIT:
    DW   DICT_CHAIN_POINT
    DB   4, "E", "M", "I", "T"
W_EMIT:
    rst RST_DPOP
    ld   a, l
    cp   13                    ; CR: move to a new line instead of printing
    jr   z, .newline

    ld   (EMIT_CHAR_TMP), a    ; stash the character while B/C load row/col

    ld   a, (PRINT_ROW)
    ld   b, a
    ld   a, (PRINT_COL)
    ld   c, a
    ld   a, (EMIT_CHAR_TMP)
    call GFX_PUTCHAR            ; A=char, B=row, C=column

    ld   a, (PRINT_ROW)          ; GFX_PUTCHAR destroys BC: reload row/col from memory
    ld   b, a
    ld   a, (PRINT_COL)
    ld   c, a
    ld   a, (CURRENT_ATTR)
    call GFX_SET_ATTR            ; stamp the current INK/PAPER attribute into the cell
    jr   .advance

.newline:
    xor  a
    ld   (PRINT_COL), a
    jr   .nextrow

.advance:
    ld   a, (PRINT_COL)
    inc  a
    cp   32
    jr   c, .storecol
    xor  a
    ld   (PRINT_COL), a
    jr   .nextrow
.storecol:
    ld   (PRINT_COL), a
    ret

.nextrow:
    ld   a, (PRINT_ROW)
    inc  a
    cp   23                     ; row 23 is core/editor.asm's EDIT_ROW -- EMIT's output never goes there
    jr   c, .storerow
    call GFX_SCROLL_TEXT_UP
    ld   b, 22
    call GFX_CLEAR_ROW           ; GFX_SCROLL_TEXT_UP leaves row 22 for the caller to draw
    ld   a, 22
.storerow:
    ld   (PRINT_ROW), a
    ret

; ============================================================================
; . ( n -- ) -- print n as a signed decimal number followed by a space
; ============================================================================
H_DOT:
    DW   H_EMIT
    DB   1, "."
W_DOT:
    rst RST_DPOP
    ld   a, h
    and  $80
    jr   z, .positive
    push hl
    ld   hl, "-"
    rst RST_DPUSH
    call W_EMIT
    pop  hl
    xor  a                       ; negate hl -- correct even for $8000
    sub  l
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
.positive:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   hl, "0"
    rst RST_DPUSH
    call W_EMIT
    jr   .donedigits
.hasdigits:
    ld   c, 0                    ; digit count; the digits wait on the machine stack (UDIV10 keeps C)
.divloop:
    ld   a, h
    or   l
    jr   z, .printdigits
    call UDIV10                  ; hl = hl/10, a = digit (0-9)
    push af
    inc  c
    jr   .divloop
.printdigits:
    ld   b, c
.printloop:
    pop  af
    add  a, "0"
    ld   l, a
    ld   h, 0
    push bc                       ; W_EMIT destroys BC: keep the djnz counter
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    djnz .printloop
.donedigits:
    ld   hl, " "
    rst RST_DPUSH
    jp   W_EMIT

; ============================================================================
; PRINT_UDEC16 -- print an unsigned number in decimal, no leading zeros, no trailing space
; In:  HL = value
; Out: "0" for zero; printed through W_EMIT (core/recall.asm's LIST-DEFS uses it)
; Destroys: AF, BC, DE, HL
; ============================================================================
PRINT_UDEC16:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   hl, "0"
    rst RST_DPUSH
    jp   W_EMIT
.hasdigits:
    ld   c, 0
.divloop:
    ld   a, h
    or   l
    jr   z, .printdigits
    call UDIV10
    push af
    inc  c
    jr   .divloop
.printdigits:
    ld   b, c
.printloop:
    pop  af
    add  a, "0"
    ld   l, a
    ld   h, 0
    push bc
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    djnz .printloop
    ret


    ENDIF
