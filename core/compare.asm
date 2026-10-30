; ============================================================================
; core/compare.asm -- =, <, >: comparisons
;
; Flags are -1 (true, all bits set) and 0, as for 0= in core/control.asm. < and > are signed. The
; comparison splits on the operands' sign bits instead of trusting the overflow flag after SBC: operands
; of different signs are decided by their sign bits alone, and a subtraction of operands of the same
; sign cannot overflow, so its sign bit says which is smaller.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_COMPARE_ASM
    DEFINE CORE_COMPARE_ASM

; ============================================================================
; CMP_LESS_HL_DE -- HL < DE, signed (not a dictionary word)
; In:  HL, DE
; Out: HL = -1 if HL < DE, else 0
; Destroys: AF, HL
; Cases checked by hand (a=HL, b=DE): 5<3 false, 3<5 true, -1<1 true, 1<-1 false, -32768<-1 true,
; -1<-32768 false.
; ============================================================================
CMP_LESS_HL_DE:
    ld   a, h
    xor  d
    bit  7, a
    jr   z, .samesign
    bit  7, h               ; different signs: a<b iff a itself is negative
    jr   nz, .true
    jr   .false
.samesign:
    or   a                  ; clear carry before sbc
    sbc  hl, de              ; same sign: cannot overflow, so the result's sign bit is the answer
    bit  7, h
    jr   nz, .true
.false:
    ld   hl, 0
    ret
.true:
    ld   hl, -1
    ret

; ============================================================================
; = ( a b -- flag ) -- -1 if a and b are equal, else 0
; ============================================================================
H_EQUALS:
    DW   DICT_CHAIN_POINT
    DB   1, "="
W_EQUALS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    ld   a, h
    cp   d
    jr   nz, .false
    ld   a, l
    cp   e
    jr   nz, .false
    ld   hl, -1
    jr   .store
.false:
    ld   hl, 0
.store:
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; < ( a b -- flag ) -- -1 if a < b (signed), else 0
; ============================================================================
H_LESS:
    DW   H_EQUALS
    DB   1, "<"
W_LESS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    ex   de, hl        ; hl = a, de = b -- testing a<b
    call CMP_LESS_HL_DE
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; > ( a b -- flag ) -- -1 if a > b (signed), else 0
; ============================================================================
H_GREATER:
    DW   H_LESS
    DB   1, ">"
W_GREATER:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)     ; hl = b, de = a: a>b is b<a
    call CMP_LESS_HL_DE
    ld   (ix+0), l
    ld   (ix+1), h
    ret

DICT_LATEST_INIT_COMPARE EQU H_GREATER

    ENDIF
