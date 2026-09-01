; ============================================================================
; core/compare.asm — Phase 11: comparisons (=, <, >)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as core/control.asm/core/storage.asm/core/float.asm/
; core/print.asm — see core/control.asm's own header for the full
; reasoning).
;
; WHAT THIS ADDS (the exact gap docs/forth_tutorial.md's "What's not
; here yet" section has named since Phase 4: "only 0= exists so far"):
;   =  ( a b -- flag )   -1 (TRUE) if a and b are bit-for-bit equal,
;                        else 0 (FALSE)
;   <  ( a b -- flag )   -1 if a < b, SIGNED, else 0
;   >  ( a b -- flag )   -1 if a > b, SIGNED, else 0
;
; TRUE/FALSE match core/control.asm's own 0= convention (-1/0, the ANS
; Forth TRUE — all bits set), not 1/0.
;
; SIGNED COMPARISON BY SIGN-BIT CASE SPLIT, NOT BY TRUSTING THE Z80'S
; OWN P/V (OVERFLOW) FLAG AFTER SBC: a subtraction of two numbers with
; the SAME sign can never overflow the signed 16-bit range, so that
; result's own sign bit directly answers "which was smaller" with no
; further care needed; a pair with DIFFERENT signs can be answered from
; the operands' own sign bits alone, with no subtraction at all — so
; the only subtraction this file ever performs is one that is
; structurally guaranteed not to overflow. See CMP_LESS_HL_DE's own
; header below for the six cases (including both 16-bit extremes)
; checked by hand before trusting this, the same discipline
; core/print.asm's UDIV10 used for its own -32768 edge case.
; ============================================================================

    IFNDEF CORE_COMPARE_ASM
    DEFINE CORE_COMPARE_ASM

; ============================================================================
; CMP_LESS_HL_DE (internal, not a dictionary word — nothing FINDs it by
; name) — HL < DE ? (signed). Returns HL = -1 (true) or 0 (false).
; Destroys AF.
;
; Hand-verified cases (a=HL, b=DE, expect a<b):
;   5 < 3            -> false (same sign, positive)
;   3 < 5            -> true  (same sign, positive)
;   -1 < 1           -> true  (different signs)
;   1 < -1           -> false (different signs)
;   -32768 < -1      -> true  (same sign, negative, extreme)
;   -1 < -32768      -> false (same sign, negative, extreme)
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
    sbc  hl, de              ; same sign: this subtraction cannot overflow
                             ; the signed 16-bit range -- the result's own
                             ; sign bit is the whole answer
    bit  7, h
    jr   nz, .true
.false:
    ld   hl, 0
    ret
.true:
    ld   hl, -1
    ret

; ============================================================================
; = ( a b -- flag )
; ============================================================================
H_EQUALS:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL, not
                            ; EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file -- see
                            ; core/control.asm's own header
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
; < ( a b -- flag )   signed
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
; > ( a b -- flag )   signed
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
    ld   d, (ix+1)     ; hl = b, de = a -- a>b is exactly the same
                       ; question as b<a
    call CMP_LESS_HL_DE
    ld   (ix+0), l
    ld   (ix+1), h
    ret

DICT_LATEST_INIT_COMPARE EQU H_GREATER   ; head of the dictionary once
                                          ; this file's own words are
                                          ; included

    ENDIF
