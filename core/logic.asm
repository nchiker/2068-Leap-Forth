; ============================================================================
; core/logic.asm -- AND, OR, XOR, INVERT: bitwise logic
;
; All 16 bits of each cell are combined. INVERT is the bitwise complement; 0= (core/control.asm) is the
; logical NOT of a flag, which is why this word is not called NOT.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_LOGIC_ASM
    DEFINE CORE_LOGIC_ASM

; ============================================================================
; AND ( a b -- a&b )
; ============================================================================
H_AND:
    DW   DICT_CHAIN_POINT
    DB   3, "A","N","D"
W_AND:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    and  (ix+0)
    ld   l, a
    ld   a, h
    and  (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; OR ( a b -- a|b )
; ============================================================================
H_OR:
    DW   H_AND
    DB   2, "O","R"
W_OR:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    or   (ix+0)
    ld   l, a
    ld   a, h
    or   (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; XOR ( a b -- a^b )
; ============================================================================
H_XOR:
    DW   H_OR
    DB   3, "X","O","R"
W_XOR:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    xor  (ix+0)
    ld   l, a
    ld   a, h
    xor  (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; INVERT ( a -- ~a ) -- bitwise one's complement
; ============================================================================
H_INVERT:
    DW   H_XOR
    DB   6, "I","N","V","E","R","T"
W_INVERT:
    ld   a, (ix+0)
    cpl
    ld   (ix+0), a
    ld   a, (ix+1)
    cpl
    ld   (ix+1), a
    ret


    ENDIF
