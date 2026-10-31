; ============================================================================
; core/arith.asm -- 1+, 1-, NEGATE, MAX, MIN
;
; Needs core/dict.asm and core/interp.asm. MAX and MIN compare signed by the operands' sign bits: if
; they differ the negative one is smaller; if they are equal an unsigned SBC HL,DE decides (two's
; complement keeps the order within one sign). Checked by hand against (5,3), (3,5), (-1,3), (3,-1),
; (-1,-5) and (-5,-1).
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_ARITH_ASM
    DEFINE CORE_ARITH_ASM

; ============================================================================
; 1+ ( n -- n+1 )
; ============================================================================
H_ONEPLUS:
    DW   DICT_CHAIN_POINT
    DB   2, "1","+"
W_ONEPLUS:
    ld   l, (ix+0)
    ld   h, (ix+1)
    inc  hl
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; 1- ( n -- n-1 )
; ============================================================================
H_ONEMINUS:
    DW   H_ONEPLUS
    DB   2, "1","-"
W_ONEMINUS:
    ld   l, (ix+0)
    ld   h, (ix+1)
    dec  hl
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; NEGATE ( n -- -n ) -- two's complement; -32768 stays -32768
; ============================================================================
H_NEGATE:
    DW   H_ONEMINUS
    DB   6, "N","E","G","A","T","E"
W_NEGATE:
    ld   l, (ix+0)
    ld   h, (ix+1)
    xor  a               ; 0 - n
    sub  l
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; MAX ( a b -- max ) -- signed
; ============================================================================
H_MAX:
    DW   H_NEGATE
    DB   3, "M","A","X"
W_MAX:
    ld   e, (ix+0)       ; de = b (top)
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   l, (ix+0)       ; hl = a (the cell the result lands in)
    ld   h, (ix+1)
    ld   a, h
    xor  d
    bit  7, a
    jr   nz, .diffsign
    ; same sign -- an unsigned magnitude compare settles it
    or   a
    sbc  hl, de           ; hl = a-b; carry set if a < b (unsigned)
    jr   c, .b_wins
    ret                    ; a >= b -- a (already at top) is the max
.diffsign:
    bit  7, h              ; test a's own sign bit
    jr   nz, .b_wins        ; a negative, so b is not: b wins
    ret                      ; a non-negative, b negative: a wins
.b_wins:
    ld   (ix+0), e
    ld   (ix+1), d
    ret

; ============================================================================
; MIN ( a b -- min ) -- signed
; ============================================================================
H_MIN:
    DW   H_MAX
    DB   3, "M","I","N"
W_MIN:
    ld   e, (ix+0)       ; de = b (top)
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   l, (ix+0)       ; hl = a
    ld   h, (ix+1)
    ld   a, h
    xor  d
    bit  7, a
    jr   nz, .diffsign
    or   a
    sbc  hl, de           ; carry set if a < b (unsigned)
    jr   nc, .b_wins        ; a >= b -- b is the min
    ret                      ; a < b -- a (already at top) is the min
.diffsign:
    bit  7, h
    jr   z, .b_wins          ; a non-negative, so b is negative: b is the min
    ret                       ; a negative: a is the min
.b_wins:
    ld   (ix+0), e
    ld   (ix+1), d
    ret


    ENDIF
