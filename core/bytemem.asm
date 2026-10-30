; ============================================================================
; core/bytemem.asm -- C@ and C!: byte-sized memory access
;
; The byte counterparts of @ and ! in core/dict.asm (which must be INCLUDEd first).
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_BYTEMEM_ASM
    DEFINE CORE_BYTEMEM_ASM

; ============================================================================
; C@ ( addr -- byte ) -- fetch one byte, zero-extended into the cell
; ============================================================================
H_CFETCH:
    DW   DICT_CHAIN_POINT
    DB   2, "C", "@"
W_CFETCH:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    ld   a, (hl)       ; a = the byte at addr
    ld   (ix+0), a
    xor  a
    ld   (ix+1), a     ; zero-extend into the cell
    ret

; ============================================================================
; C! ( byte addr -- ) -- store the low byte of the value at addr (its high byte is dropped)
; ============================================================================
H_CSTORE:
    DW   H_CFETCH
    DB   2, "C", "!"
W_CSTORE:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   a, (ix+0)     ; a = low byte of the value to store
    inc  ix
    inc  ix
    ld   (hl), a
    ret


    ENDIF
