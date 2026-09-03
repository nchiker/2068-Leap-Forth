; ============================================================================
; core/arith.asm — Phase 49: 1+, 1-, NEGATE, MAX, MIN
;
; Builds on core/dict.asm (DPUSH_HL/DPOP_HL not even needed — these are
; all pure IX-relative stack ops, same idiom as core/dict.asm's own
; DUP/SWAP/OVER/+/- ) — only core/dict.asm and core/interp.asm (for
; DICT_CHAIN_POINT) need to be INCLUDEd first, same convention as every
; other core/ file.
;
; WHAT THIS ADDS — five of the "cheap tier" Jupiter Ace words a fresh
; audit found missing:
;   1+     ( n -- n+1 )
;   1-     ( n -- n-1 )
;   NEGATE ( n -- -n )        two's-complement negate; uses the exact
;              same "0 - n" idiom core/print.asm's own W_DOT already
;              uses to negate before printing (that file's own header
;              explains why this handles -32768 correctly: negating
;              $8000 in 16-bit two's complement gives back $8000, which
;              IS correct two's-complement behavior, not a bug)
;   MAX    ( a b -- max )     SIGNED comparison
;   MIN    ( a b -- min )     SIGNED comparison
;
; MAX/MIN'S SIGNED-COMPARE ALGORITHM: the Z80 has no single conditional
; jump for "signed less than" the way x86 does (it would need S XOR
; P/V, and the two flags aren't combinable in one jump). Instead of
; leaning on SBC HL,DE's overflow flag, this uses the simpler, easier to
; verify by hand two-case algorithm real hand-written Z80 code commonly
; uses instead:
;   - if a and b have DIFFERENT sign bits, the negative one is smaller
;     — no magnitude comparison needed at all.
;   - if a and b have the SAME sign bit, an ordinary UNSIGNED 16-bit
;     compare (SBC HL,DE, carry = a<b) gives the right answer directly:
;     obviously true when both are non-negative, and also true when
;     both are negative because two's complement preserves relative
;     order within a fixed sign region (e.g. -1 = $FFFF > -2 = $FFFE
;     as both signed AND unsigned values).
; Hand-verified against (5,3), (3,5), (-1,3), (3,-1), (-1,-5), (-5,-1)
; for both MAX and MIN before this was ever assembled.
; ============================================================================

    IFNDEF CORE_ARITH_ASM
    DEFINE CORE_ARITH_ASM

; ============================================================================
; 1+ ( n -- n+1 )
; ============================================================================
H_ONEPLUS:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
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
; NEGATE ( n -- -n )
; ============================================================================
H_NEGATE:
    DW   H_ONEMINUS
    DB   6, "N","E","G","A","T","E"
W_NEGATE:
    ld   l, (ix+0)
    ld   h, (ix+1)
    xor  a               ; same "0 - n" idiom core/print.asm's own
    sub  l                ; W_DOT already uses (see this file's own
    ld   l, a              ; header) -- correct even for n = $8000
    ld   a, 0
    sbc  a, h
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; MAX ( a b -- max )  signed comparison — see this file's own header
; for the two-case algorithm.
; ============================================================================
H_MAX:
    DW   H_NEGATE
    DB   3, "M","A","X"
W_MAX:
    ld   e, (ix+0)       ; de = b (top)
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   l, (ix+0)       ; hl = a (now the sole remaining cell -- the
    ld   h, (ix+1)        ; result lands back in this same slot)
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
    jr   nz, .b_wins        ; a negative (so b, the opposite sign, is
                             ; non-negative) -- b wins
    ret                      ; a non-negative, b negative -- a
                             ; (already at top) wins
.b_wins:
    ld   (ix+0), e
    ld   (ix+1), d
    ret

; ============================================================================
; MIN ( a b -- min )  signed comparison — mirror of MAX above, with
; both winner tests inverted.
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
    jr   z, .b_wins          ; a non-negative (so b, the opposite sign,
                              ; is negative) -- b is the min
    ret                       ; a negative -- a (already at top) is
                              ; the min
.b_wins:
    ld   (ix+0), e
    ld   (ix+1), d
    ret

DICT_LATEST_INIT_ARITH EQU H_MIN   ; head of the dictionary once this
                                    ; file's own words are included

    ENDIF
