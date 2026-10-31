; ============================================================================
; core/moregfx.asm -- AT-XY: move the print position
;
; Needs core/print.asm (PRINT_ROW, PRINT_COL). Neither coordinate is range-checked (0-31, 0-22): an
; out-of-range position makes the next character land somewhere unintended.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_MOREGFX_ASM
    DEFINE CORE_MOREGFX_ASM

; ============================================================================
; AT-XY ( col row -- ) -- set the position EMIT, . and ." print at next
; ============================================================================
H_ATXY:
    DW   DICT_CHAIN_POINT
    DB   5, "A", "T", "-", "X", "Y"
W_ATXY:
    rst RST_DPOP          ; hl = row
    ld   a, l
    ld   (PRINT_ROW), a
    rst RST_DPOP          ; hl = col
    ld   a, l
    ld   (PRINT_COL), a
    ret


    ENDIF
