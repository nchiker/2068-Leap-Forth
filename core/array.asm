; ============================================================================
; core/array.asm -- ARRAY and CELLS: arrays of cells
;
; Needs core/variable.asm (VARIABLE_N): an ARRAY is a VARIABLE with 2n data bytes.
; `10 ARRAY NUMS` makes a zeroed 10-cell (20-byte) array; `3 CELLS NUMS + @` reads element 3 and
; `99 3 CELLS NUMS + !` writes it. There is no bounds check.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_ARRAY_ASM
    DEFINE CORE_ARRAY_ASM

; ============================================================================
; ARRAY ( n "name" -- ) -- create name ( -- addr ), leaving the address of n zeroed cells
; The word's body is CALL DOLIT + the address of the elements, then RET; the elements follow it.
; Errors: DICT_ROOM refuses (the dictionary guard) when the elements would not fit
; ============================================================================
H_ARRAY:
    DW   DICT_CHAIN_POINT
    DB   5, "A", "R", "R", "A", "Y"
W_ARRAY:
    rst RST_DPOP                  ; HL = n (cell count)
    add  hl, hl                   ; the elements: n * 2 bytes; past $FFFF (carry) the high byte is
    sbc  a, a                     ; forced to $FF, which DICT_ROOM refuses whatever HERE is
    or   h
    ld   b, a
    ld   c, l
    jp   VARIABLE_N

; ============================================================================
; CELLS ( n -- n*2 ) -- a cell count as a byte offset (a cell is 2 bytes)
; ============================================================================
H_CELLS:
    DW   H_ARRAY
    DB   5, "C", "E", "L", "L", "S"
W_CELLS:
    rst RST_DPOP
    add  hl, hl
    rst RST_DPUSH
    ret


    ENDIF
