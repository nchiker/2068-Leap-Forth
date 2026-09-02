; ============================================================================
; core/floatconv.asm — Phase 34: S>F and F>S (integer/float conversion)
;
; Builds on core/dict.asm (DPUSH_HL/DPOP_HL) and core/float.asm
; (FPUSH/FPOP, F_SHRA, and this project's own float format — both must
; be INCLUDEd first; this file's own first header chains through
; DICT_CHAIN_POINT).
;
; WHAT THIS ADDS: standard ANS Forth's Floating-Point word set defines
; S>F ( n -- r ) and F>S ( r -- n ) for exactly this — converting a
; single-cell integer to/from a float. Until now, the only way to get
; an integer value onto the float stack at all was FPUSH'ing a raw
; (mantissa, exponent) pair by hand; there was no word for it, and no
; way back. (D>F/F>D, the double-cell half of the same standard word
; set, don't apply here — this project's integer stack is single-cell
; only.)
;
; S>F is exact and needs no thought: this project's float format is
; `mantissa * 2^exponent` (core/float.asm's own header) with NO
; required normalization, so mantissa=n, exponent=0 represents n
; exactly — n * 2^0 = n, bit for bit, positive or negative, every time.
;
; F>S TRUNCATES, per the user's own explicit choice (not ANS Forth's
; own default, which is implementation-defined but usually rounds to
; nearest) — the simplest option, matching this project's own established
; posture on approximation (F.'s and FSQRT's own truncating/lossy
; behavior, stated plainly rather than hidden). The exponent decides
; the direction: 0 needs no shift at all (already exact); a positive
; exponent shifts the mantissa LEFT (multiplies) via a new F_SHLA (the
; mirror image of core/float.asm's own F_SHRA, added here rather than
; there since nothing before this needed a left-shift-by-variable-count
; helper); a negative exponent shifts the mantissa RIGHT via the
; EXISTING F_SHRA, reused unchanged.
;
; A REAL CAVEAT, worth stating precisely rather than glossing over:
; reusing F_SHRA means F>S truncates via an ARITHMETIC (sign-
; preserving) right shift, which rounds toward NEGATIVE INFINITY for a
; negative fractional value, not toward zero the way C's `(int)` cast
; or many Forths' own F>S do. A whole-number float (any value with no
; fractional part at its own exponent, matching this file's own
; "exact" test cases below) is completely unaffected either way, since
; there's no remainder to round — this only shows up for a genuinely
; fractional NEGATIVE input. Reusing F_SHRA was a deliberate choice
; (one proven routine, not a second subtly-different shift), but the
; direction it truncates in is a real, user-visible behavior, not an
; implementation detail — see the -0.5 case below.
;
; A positive exponent's left shift has no equivalent guard anywhere in
; this project's floats (core/float.asm's own header: no overflow
; handling anywhere in this format) — a float whose true value doesn't
; fit in 16 bits silently loses its high bits, the same class of
; accepted limitation F+/F-'s own un-renormalized paths and this
; project's integer arithmetic in general already have.
;
; HAND-VERIFIED before trusting any of this:
;   S>F then F>S, n=42: mantissa=42, exponent=0. F>S sees exponent=0,
;     pushes 42 back unchanged. Exact round trip.
;   S>F then F>S, n=-17: mantissa=-17 (two's complement), exponent=0.
;     Same exact-round-trip path, negative numbers included for free —
;     nothing here special-cases sign.
;   F>S, 0.5 = (16384,-15): exponent<0, shift 16384 right (arithmetic)
;     15 times: 16384=$4000=0100000000000000b, shifting a POSITIVE
;     value right arithmetically is ordinary truncation-toward-zero, so
;     this lands on exactly 0 after the 15th shift. F>S(0.5) = 0 —
;     correct, unsurprising truncation.
;   F>S, -0.5 = (-16384,-15): same shift count, but starting from
;     -16384=$C000=1100000000000000b with the SIGN BIT preserved each
;     shift (arithmetic shift): after 14 shifts the value is -2, after
;     the 15th it's -1, NOT 0. F>S(-0.5) = -1 — this is the caveat
;     above made concrete: floor-style truncation (round toward
;     negative infinity), not toward zero.
;   F>S, -4.0 = (-16384,-12): a WHOLE number, so despite being
;     negative, -16384 is exactly divisible by 2^12 — no remainder
;     exists for the two truncation directions to disagree about.
;     Shifting arithmetically 12 times gives exactly -4, matching what
;     truncation-toward-zero would also give. Confirms the caveat above
;     is real but narrow: it only bites genuinely fractional negative
;     inputs, never whole numbers of either sign.
; ============================================================================

    IFNDEF CORE_FLOATCONV_ASM
    DEFINE CORE_FLOATCONV_ASM

; ============================================================================
; F_SHLA ( HL = value, B = count -- HL = value << count )
; Left shift, B times — the mirror image of core/float.asm's own
; F_SHRA. NOT a dictionary word.
; ============================================================================
F_SHLA:
    ld   a, b
    or   a
    ret  z
.loop:
    add  hl, hl
    djnz .loop
    ret

; ============================================================================
; S>F ( n -- r )  exact — see this file's own header.
; ============================================================================
H_STOF:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "S", ">", "F"
W_STOF:
    call DPOP_HL            ; hl = n
    xor  a                  ; exponent = 0 -- n * 2^0 = n, exactly
    call FPUSH
    ret

; ============================================================================
; F>S ( r -- n )  truncates — see this file's own header for exactly
; which direction, and why.
; ============================================================================
H_FTOS:
    DW   H_STOF
    DB   3, "F", ">", "S"
W_FTOS:
    call FPOP                ; hl = mantissa, a = exponent
    or   a
    jr   z, .push            ; exponent == 0 -- already exact
    jp   p, .positive_exp
    neg                       ; exponent < 0: shift mantissa right by
    ld   b, a                 ; -exponent (arithmetic, sign-preserving
    call F_SHRA                ; -- see this file's own header on the
    jr   .push                  ; truncation-direction caveat)
.positive_exp:
    ld   b, a
    call F_SHLA               ; exponent > 0: shift mantissa left by
                              ; exponent (can silently lose high bits
                              ; if the true value doesn't fit 16 bits
                              ; -- see this file's own header)
.push:
    call DPUSH_HL
    ret

DICT_LATEST_INIT_FLOATCONV EQU H_FTOS   ; head of the dictionary once
                                         ; this file's own words are
                                         ; included

    ENDIF
