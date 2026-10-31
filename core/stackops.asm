; ============================================================================
; core/stackops.asm -- ROT, 2DUP, 2DROP, ?DUP, PICK: more stack words
;
; Needs core/dict.asm (W_DROP, W_DUP). PICK does not bounds-check u: an out-of-range u reads whatever
; memory that address is.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_STACKOPS_ASM
    DEFINE CORE_STACKOPS_ASM

; ============================================================================
; ROT ( a b c -- b c a )
; ============================================================================
H_ROT:
    DW   DICT_CHAIN_POINT
    DB   3, "R","O","T"
W_ROT:
    ld   c, (ix+4)
    ld   b, (ix+5)          ; bc = a
    ld   e, (ix+2)
    ld   d, (ix+3)          ; de = b
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = c
    ld   (ix+4), e
    ld   (ix+5), d          ; a's old slot now holds b
    ld   (ix+2), l
    ld   (ix+3), h          ; b's old slot now holds c
    ld   (ix+0), c
    ld   (ix+1), b          ; c's old slot (top) now holds a
    ret

; ============================================================================
; 2DUP ( a b -- a b a b )
; ============================================================================
H_2DUP:
    DW   H_ROT
    DB   4, "2","D","U","P"
W_2DUP:
    ld   e, (ix+0)
    ld   d, (ix+1)          ; de = b (top)
    ld   l, (ix+2)
    ld   h, (ix+3)          ; hl = a
    rst RST_DPUSH          ; push a-copy first (ends up 2nd from top)
    ex   de, hl
    rst RST_DPUSH          ; push b-copy (ends up on top)
    ret

; ============================================================================
; 2DROP ( a b -- ) -- W_DROP twice
; ============================================================================
H_2DROP:
    DW   H_2DUP
    DB   5, "2","D","R","O","P"
W_2DROP:
    call W_DROP
    jp   W_DROP

; ============================================================================
; ?DUP ( x -- 0 | x x ) -- duplicate x only if it is nonzero
; ============================================================================
H_QDUP:
    DW   H_2DROP
    DB   4, "?","D","U","P"
W_QDUP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    or   l
    ret  z                   ; x = 0: leave the single 0 exactly as is
    jp   W_DUP

; ============================================================================
; PICK ( x_u ... x_0 u -- x_u ... x_0 x_u ) -- copy the u-th item to the top (0 PICK = DUP, 1 PICK = OVER)
; ============================================================================
H_PICK:
    DW   H_QDUP
    DB   4, "P","I","C","K"
W_PICK:
    rst RST_DPOP            ; hl = u
    add  hl, hl               ; hl = u*2 (byte offset)
    push ix
    pop  de                    ; de = ix (already past u's own cell)
    add  hl, de                ; hl = address of the picked item
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                ; de = the picked value
    ex   de, hl
    rst RST_DPUSH
    ret


    ENDIF
