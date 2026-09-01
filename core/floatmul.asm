; ============================================================================
; core/floatmul.asm — Phase 18: F* (float multiply)
;
; Builds on core/dict.asm, core/interp.asm, and core/float.asm (all
; must be INCLUDEd first — this file's own first header chains onto
; core/float.asm's own tail, H_FMINUS, and reuses its FPUSH/FPOP/
; F_M1/F_M2/F_E1/F_E2/F_RESULT_EXP plumbing directly). A new file
; rather than an addition to core/float.asm itself — that file is
; INCLUDEd by several smoke ROMs and rom/forth_boot.asm already, and
; this project's practice since Phase 12 is to add a small new file
; rather than widen an already-shared one's regression surface for a
; later addition that doesn't need to touch its existing code at all.
;
; ALSO NEEDS kernel/math/math.asm INCLUDEd (for MATH_ABS16/
; MATH_NEGATE16, ordinary sign-handling utilities, called as-is — not
; modified) — a real, new dependency core/float.asm's own F+/F- never
; needed ("Needs nothing from kernel/ — this is pure arithmetic," that
; file's own header says; not true of this one).
;
; WHAT THIS ADDS: F* ( f1 f2 -- f1*f2 ), the first half of the
; "decimal number... multiply, and divide" gap docs/forth_tutorial.md
; has named since Phase 8. F/ (division) is NOT this file — real,
; harder follow-up work, deliberately not rushed into the same phase.
;
; A REAL DESIGN MISTAKE CAUGHT BEFORE SHIPPING, NOT AFTER: the first
; draft took the HIGH 16 bits of the 32-bit mantissa product
; unconditionally (adding 16 to the exponent to compensate), reasoning
; that a product of two "reasonably scaled" mantissas would naturally
; be top-heavy. Hand-tracing 2.0*3.0 (mantissas 256 and 384, both from
; core/float.asm's own smoke-test convention) exposed the flaw: their
; product is 98304 ($00018000) — the high word is just 1, so taking it
; alone and discarding the low word ($8000, nearly half the true
; magnitude) gave 4.0, not 6.0. A fixed-position window is wrong
; whenever the product's significant bits don't happen to land in that
; exact window — which is most of the time for realistic inputs, not
; an edge case.
;
; THE ACTUAL ALGORITHM: kernel/math's own MATH_MULTIPLY16 only produces
; a 16-bit TRUNCATED product anyway (useless here for the same reason)
; so this file writes its own unsigned 32-bit widening multiply
; (F_UMUL32) AND a real normalization pass (F_NORMALIZE32) that finds
; where the product's significant bits actually are: it shifts the
; 32-bit magnitude right while it doesn't fit in 15 bits (bit 15 set,
; or the high word nonzero), then left while it's using less than 14
; bits (bit 14 clear) — landing the result in the same "positive,
; using close to its full 15-bit range" shape core/float.asm's own
; F+/F- test mantissas already use, and tracking the net shift to fold
; into the result's exponent. Both loops are bounded (a product of two
; 16-bit magnitudes is at most ~30 bits, so at most ~16 shrink
; iterations; a product as small as 1 needs at most ~14 grow
; iterations) — verified by hand against three cases before trusting
; it: 2.0*3.0=6.0 (needs 2 shrink steps), 0.5*0.5=0.25 (needs 2 shrink
; steps from a different starting shape), and 1.0*1.0=1.0 (needs 14
; grow steps from mantissa 1) — see F_NORMALIZE32's own header for the
; worked arithmetic.
;
; Since normalization guarantees the final magnitude fits in 15 bits
; (positive, bit 15 clear) BEFORE sign is reapplied, sign handling only
; ever needs a plain 16-bit negate (kernel/math's own MATH_NEGATE16) —
; no 32-bit negation is needed at all, unlike the discarded first
; draft. Sign itself is computed as the XOR of the two mantissas' own
; sign bits and applied to absolute values first, the same pattern
; kernel/math's own MATH_MULTIPLY16 already uses.
; ============================================================================

    IFNDEF CORE_FLOATMUL_ASM
    DEFINE CORE_FLOATMUL_ASM

; ---- Phase 18 RAM state — same probe-verified $8426-$8FFF gap as
; every other core/ file's own scratch (see core/float.asm's own
; header for the method). Placed right after core/float.asm's own
; F_RESULT_EXP ($87A6). ----
F_MCAND_LO   EQU $87A7   ; 2 bytes: F_UMUL32's own scratch (shifting
                         ; multiplicand, low 16 bits of a 32-bit value)
F_MCAND_HI   EQU $87A9   ; 2 bytes: multiplicand, high 16 bits
F_MULR       EQU $87AB   ; 2 bytes: shifting multiplier
F_PROD_LO    EQU $87AD   ; 2 bytes: 32-bit product, low 16 bits --
                         ; becomes the normalized magnitude once
                         ; F_NORMALIZE32 finishes (F_PROD_HI is then 0)
F_PROD_HI    EQU $87AF   ; 2 bytes: 32-bit product, high 16 bits
F_MUL_CNT    EQU $87B1   ; 1 byte:  F_UMUL32's own loop counter
F_MSIGN      EQU $87B2   ; 1 byte:  W_FSTAR's own scratch (0 or $80)
F_NORM_SHIFT EQU $87B3   ; 1 byte:  F_NORMALIZE32's own net right-shift
                         ; count (signed -- negative means a net left
                         ; shift was applied instead)

; ============================================================================
; F_UMUL32 (internal, not a dictionary word) — DE = multiplicand
; (unsigned 16-bit), BC = multiplier (unsigned 16-bit) -> F_PROD_HI:
; F_PROD_LO = 32-bit unsigned product. Classic 16-iteration
; shift-and-add, widened to a 32-bit accumulator and a 32-bit
; (zero-extended, then doubled each pass) multiplicand — the same
; shape kernel/math's own MATH_UMUL16 uses for a 16-bit result, just
; carried in memory instead of registers since a 32-bit accumulator
; plus a 32-bit multiplicand plus a shifting multiplier don't fit in
; the Z80's register file at once.
; Destroys: AF, BC, DE, HL
; ============================================================================
F_UMUL32:
    ld   (F_MCAND_LO), de
    ld   hl, 0
    ld   (F_MCAND_HI), hl
    ld   (F_MULR), bc
    ld   (F_PROD_LO), hl
    ld   (F_PROD_HI), hl
    ld   a, 16
    ld   (F_MUL_CNT), a
.loop:
    ld   hl, (F_MULR)
    ld   a, l
    rrca                     ; carry = current bit0 of the multiplier
    jr   nc, .noadd
    ld   hl, (F_PROD_LO)
    ld   de, (F_MCAND_LO)
    add  hl, de
    ld   (F_PROD_LO), hl
    ld   hl, (F_PROD_HI)
    ld   de, (F_MCAND_HI)
    adc  hl, de              ; carry-in from the low word's ADD above
    ld   (F_PROD_HI), hl
.noadd:
    ld   hl, (F_MCAND_LO)
    add  hl, hl               ; double the 32-bit multiplicand ...
    ld   (F_MCAND_LO), hl
    ld   hl, (F_MCAND_HI)
    adc  hl, hl                ; ... carrying out of the low word
    ld   (F_MCAND_HI), hl
    ld   hl, (F_MULR)
    srl  h
    rr   l                      ; halve the multiplier (unsigned)
    ld   (F_MULR), hl
    ld   a, (F_MUL_CNT)
    dec  a
    ld   (F_MUL_CNT), a
    jr   nz, .loop
    ret

; ============================================================================
; F_NORMALIZE32 (internal, not a dictionary word) — normalizes the
; unsigned 32-bit magnitude in F_PROD_HI:F_PROD_LO in place: shifts it
; right while it doesn't fit in 15 bits, then left while it's using
; fewer than 14 (skipped entirely if the value is exactly zero). On
; return, F_PROD_HI is always 0, F_PROD_LO holds the normalized
; magnitude (bit 15 clear, safe to treat as a positive signed 16-bit
; value), and F_NORM_SHIFT holds the net shift applied — ADD it to the
; result's exponent to keep the represented value unchanged.
;
; Hand-verified before trusting it (final exponent = e1+e2+F_NORM_SHIFT,
; applied by W_FSTAR, not by this routine):
;   256*384=98304 ($00018000) -> shrinks twice (18000 -> C000 -> 6000,
;     HI clears after the first shift) -> mantissa 24576 ($6000),
;     shift +2 -- for the 2.0*3.0 case (mantissas 256/384, both
;     exponent -7), final exponent = -7+-7+2 = -12; 24576*2^-12 = 6.0
;   256*256=65536 ($00010000) -> shrinks twice (10000 -> 8000 -> 4000)
;     -> mantissa 16384 ($4000), shift +2 -- for a 0.5*0.5 case
;     (mantissa 256, exponent -9 each), final exponent = -9+-9+2 = -16;
;     16384*2^-16 = 0.25
;   1*1=1 ($00000001) -> no shrink needed (already < 32768), grows 14
;     times (1 -> 2 -> 4 -> ... -> 16384) -> mantissa 16384, shift -14
;     -- for 1.0*1.0 (mantissa 1, exponent 0 each), final exponent =
;     0+0+-14 = -14; 16384*2^-14 = 1.0
; Destroys: AF, HL
; ============================================================================
F_NORMALIZE32:
    xor  a
    ld   (F_NORM_SHIFT), a
.shrink_check:
    ld   hl, (F_PROD_HI)
    ld   a, h
    or   l
    jr   nz, .do_shrink
    ld   a, (F_PROD_LO+1)     ; high byte of the F_PROD_LO word --
                              ; bit 7 of it is bit 15 overall
    and  $80
    jr   z, .shrink_done
.do_shrink:
    ld   hl, (F_PROD_HI)
    srl  h
    rr   l
    ld   (F_PROD_HI), hl
    ld   hl, (F_PROD_LO)
    rr   h                     ; carry-in from F_PROD_HI's own shift
                               ; above becomes the new bit 15
    rr   l
    ld   (F_PROD_LO), hl
    ld   a, (F_NORM_SHIFT)
    inc  a
    ld   (F_NORM_SHIFT), a
    jr   .shrink_check
.shrink_done:                 ; F_PROD_HI is now guaranteed 0
    ld   hl, (F_PROD_LO)
    ld   a, h
    or   l
    ret  z                     ; value is exactly zero -- nothing more
                               ; to do (any exponent is fine for 0)
.grow_check:
    ld   hl, (F_PROD_LO)
    bit  6, h                  ; bit 14 overall = bit 6 of the high byte
    ret  nz                    ; already using close to the full range
    add  hl, hl
    ld   (F_PROD_LO), hl
    ld   a, (F_NORM_SHIFT)
    dec  a
    ld   (F_NORM_SHIFT), a
    jr   .grow_check

; ============================================================================
; F* ( f1 f2 -- f1*f2 )
; ============================================================================
H_FSTAR:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file — NOT hardcoded to
                            ; H_FMINUS, unlike core/mode64.asm's own
                            ; H_64COL: both this file and that one
                            ; extend core/float.asm's tail, and a ROM
                            ; including both (rom/forth_boot.asm does)
                            ; would silently make one of them
                            ; unreachable by FIND if this one also
                            ; hardcoded the same anchor — exactly the
                            ; tree-vs-chain bug DICT_CHAIN_POINT itself
                            ; exists to prevent (see core/control.asm's
                            ; own header) — caught here before it ever
                            ; shipped, not discovered later
    DB   2, "F", "*"
W_FSTAR:
    call FPOP
    ld   (F_M2), hl
    ld   (F_E2), a
    call FPOP
    ld   (F_M1), hl
    ld   (F_E1), a

    ld   hl, (F_M1)
    ld   a, h
    ld   hl, (F_M2)
    xor  h
    and  $80
    ld   (F_MSIGN), a

    ld   hl, (F_M1)
    call MATH_ABS16
    ex   de, hl               ; de = abs(m1)
    ld   hl, (F_M2)
    call MATH_ABS16           ; hl = abs(m2)
    ld   b, h
    ld   c, l                 ; bc = abs(m2)
    call F_UMUL32              ; F_PROD_HI:F_PROD_LO = abs(m1)*abs(m2)
    call F_NORMALIZE32          ; -> F_PROD_LO = normalized magnitude,
                               ; F_NORM_SHIFT = exponent correction

    ld   hl, (F_PROD_LO)
    ld   a, (F_MSIGN)
    or   a
    jr   z, .done_sign
    call MATH_NEGATE16
.done_sign:
    push hl                    ; stash the (possibly negated) mantissa
                               ; while computing the exponent
    ld   a, (F_E1)
    ld   b, a
    ld   a, (F_E2)
    add  a, b
    ld   b, a
    ld   a, (F_NORM_SHIFT)
    add  a, b
    ld   (F_RESULT_EXP), a
    pop  hl
    ld   a, (F_RESULT_EXP)
    call FPUSH
    ret

DICT_LATEST_INIT_FLOATMUL EQU H_FSTAR   ; head of the dictionary once
                                         ; this file's own word is
                                         ; included

    ENDIF
