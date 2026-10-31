; ============================================================================
; core/mathfn.asm -- ABS, SGN, MOD, SQRT, RND, RANDOMIZE, *, /: integer math words
;
; Each word is a thin wrapper that pops its operands from the integer data stack (IX), calls the matching
; kernel/math/math.asm routine and pushes the result; that file's headers give the algorithms and edge
; cases (ABS of -32768 stays -32768, the MOD remainder takes the dividend's sign, RND(x) seeds itself
; from the Z80 R register on first use, division or MOD by zero gives 0). Needs kernel/math/math.asm.
; The float words (F+ F- F* F/ ...) work on the separate float stack (IY).
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_MATHFN_ASM
    DEFINE CORE_MATHFN_ASM

; ============================================================================
; ABS ( n -- |n| ) -- MATH_ABS16
; ============================================================================
H_ABS:
    DW   DICT_CHAIN_POINT
    DB   3, "A", "B", "S"
W_ABS:
    rst RST_DPOP
    call MATH_ABS16
    rst RST_DPUSH
    ret

; ============================================================================
; SGN ( n -- -1|0|1 ) -- MATH_SGN16
; ============================================================================
H_SGN:
    DW   H_ABS
    DB   3, "S", "G", "N"
W_SGN:
    rst RST_DPOP
    call MATH_SGN16
    rst RST_DPUSH
    ret

; ============================================================================
; MOD ( a b -- a-mod-b ) -- MATH_MOD16
; ============================================================================
H_MOD:
    DW   H_SGN
    DB   3, "M", "O", "D"
W_MOD:
    rst RST_DPOP          ; hl = b (divisor)
    ex   de, hl             ; de = b
    rst RST_DPOP            ; hl = a (dividend)
    call MATH_MOD16
    rst RST_DPUSH
    ret

; ============================================================================
; SQRT ( n -- isqrt(n) ) -- MATH_SQRT16, the truncated integer square root
; ============================================================================
H_SQRT:
    DW   H_MOD
    DB   4, "S", "Q", "R", "T"
W_SQRT:
    rst RST_DPOP
    call MATH_SQRT16
    rst RST_DPUSH
    ret

; ============================================================================
; RND ( x -- n ) -- MATH_RND16, n in [0, x-1] for a positive x
; ============================================================================
H_RND:
    DW   H_SQRT
    DB   3, "R", "N", "D"
W_RND:
    rst RST_DPOP
    call MATH_RND16
    rst RST_DPUSH
    ret

; ============================================================================
; RANDOMIZE ( n -- ) -- MATH_RND_SEED; 0 reseeds from R on the next RND
; ============================================================================
H_RANDOMIZE:
    DW   H_RND
    DB   9, "R", "A", "N", "D", "O", "M", "I", "Z", "E"
W_RANDOMIZE:
    rst RST_DPOP
    jp   MATH_RND_SEED

; ============================================================================
; * ( a b -- a*b ) -- MATH_MULTIPLY16, signed, the result truncated to 16 bits
; ============================================================================
H_STAR:
    DW   H_RANDOMIZE
    DB   1, "*"
W_STAR:
    rst RST_DPOP          ; hl = b
    ex   de, hl             ; de = b
    rst RST_DPOP            ; hl = a
    call MATH_MULTIPLY16      ; hl = a*b
    rst RST_DPUSH
    ret

; ============================================================================
; / ( a b -- a/b ) -- MATH_DIVIDE16, truncated toward zero; b = 0 gives 0
; ============================================================================
H_SLASH:
    DW   H_STAR
    DB   1, "/"
W_SLASH:
    rst RST_DPOP          ; hl = b (divisor)
    ex   de, hl             ; de = b
    rst RST_DPOP            ; hl = a (dividend)
    call MATH_DIVIDE16        ; hl = a/b, truncated toward zero
    rst RST_DPUSH
    ret


    ENDIF
