; ============================================================================
; core/floatdiv.asm — Phase 19: F/ (float divide)
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm, AND
; core/floatmul.asm (all must be INCLUDEd first, floatmul.asm
; specifically — this file's own first header chains through
; DICT_CHAIN_POINT, and reuses floatmul.asm's own F_PROD_LO/F_PROD_HI/
; F_MSIGN/F_NORM_SHIFT scratch and its F_NORMALIZE32 routine directly,
; rather than duplicating that logic — F/ needs the exact same
; "reduce a raw magnitude to a normalized 15-bit mantissa, tracking the
; shift" step F* already solved).
;
; WHAT THIS ADDS: F/ ( f1 f2 -- f1/f2 ), completing the "decimal
; number... multiply, and divide" gap docs/forth_tutorial.md has named
; since Phase 8.
;
; THE ALGORITHM, DERIVED THE SAME CAREFUL WAY F*'S OWN NORMALIZATION
; WAS: dividing two mantissas directly (abs(m1)/abs(m2), plain 16-bit
; integer division) would usually truncate to 0 whenever abs(m1) <
; abs(m2) — nearly always, for realistic inputs — the exact same
; "naive truncation destroys almost all the precision" failure mode
; core/floatmul.asm's own header describes for its first, discarded F*
; draft. The fix is the mirror image: scale the DIVIDEND up by 2^16
; BEFORE dividing (representing abs(m1) as a 32-bit value with abs(m1)
; itself in the high word and 0 in the low word, i.e. abs(m1)*65536),
; divide that by abs(m2) to get a quotient that can itself be up to 32
; bits wide, then hand the raw 32-bit quotient to F_NORMALIZE32 exactly
; as F* does — reusing it unchanged rather than writing a second
; version of the same shrink/grow logic.
;
; THE EXPONENT FORMULA, worked out algebraically and then checked
; against three hand-traced cases before trusting it: true value =
; (m1*2^e1)/(m2*2^e2) = (m1/m2)*2^(e1-e2). The computed quotient
; approximates (abs(m1)/abs(m2))*65536, i.e. quotient*2^-16 ≈
; abs(m1)/abs(m2) — so true value ≈ quotient * 2^(e1-e2-16). Once
; F_NORMALIZE32 re-expresses quotient as (mantissa, F_NORM_SHIFT) via
; quotient = mantissa * 2^F_NORM_SHIFT, the final result exponent is
; e1-e2-16+F_NORM_SHIFT.
;
; HAND-VERIFIED before trusting it:
;   6.0/3.0=2.0: (m=24576,e=-12) / (m=384,e=-7). Widened dividend =
;     24576*65536 = 1610612736; quotient = that/384 = 4194304
;     ($00400000). F_NORMALIZE32 shrinks it 8 times to mantissa 16384
;     ($4000). Final exponent = -12-(-7)-16+8 = -13; 16384*2^-13 = 2.0.
;   1.0/1.0=1.0: (m=1,e=0) / (m=1,e=0). Widened dividend = 65536;
;     quotient = 65536 ($00010000). Shrinks twice to mantissa 16384.
;     Final exponent = 0-0-16+2 = -14; 16384*2^-14 = 1.0.
;   1.0/4.0=0.25: (m=1,e=0) / (m=256,e=-6). Widened dividend = 65536;
;     quotient = 65536/256 = 256 ($0100), already under 32768 so no
;     shrinking needed — GROWS instead, 6 times, to mantissa 16384.
;     Final exponent = 0-(-6)-16+(-6) = -16; 16384*2^-16 = 0.25.
; These three between them exercise F_NORMALIZE32's shrink path, its
; boundary case, and its grow path — the same three shapes
; core/floatmul.asm's own header verified for F*, confirming the
; shared routine behaves correctly from both callers.
;
; DIVIDE BY ZERO: matches kernel/math's own MATH_UDIV16 convention
; ("divide by zero" returns a safe 0 rather than a nonsense result) —
; f1 F/ 0.0 pushes (mantissa 0, exponent 0) rather than looping forever
; or producing garbage.
;
; UPDATE, PHASE 22: F_UDIV32BY16 also exposes its final remainder now
; (F_DIV_REM), added purely so core/floatprint.asm's own F. can reuse
; this same 32-bit division engine for splitting a scaled value into
; integer and fractional decimal digits — F/ itself never reads
; F_DIV_REM, so this is a backward-compatible addition, not a behavior
; change.
; ============================================================================

    IFNDEF CORE_FLOATDIV_ASM
    DEFINE CORE_FLOATDIV_ASM

; ---- Phase 19 RAM state — same probe-verified $8426-$8FFF gap as
; every other core/ file's own scratch. Placed right after
; core/floatmul.asm's own F_NORM_SHIFT ($87B3). ----
F_DIVID_LO EQU $87B4   ; 2 bytes: F_UDIV32BY16's own scratch (the
                       ; widened dividend, low 16 bits -- always 0 on
                       ; entry, consumed/shifted during the division)
F_DIVID_HI EQU $87B6   ; 2 bytes: dividend, high 16 bits (starts as
                       ; abs(m1) itself)
F_DIV_CNT  EQU $87B8   ; 1 byte:  loop counter
F_DIV_REM  EQU $87B9   ; 2 bytes: the final 16-bit remainder, exposed
                       ; for core/floatprint.asm's own use (Phase 22) --
                       ; F/ itself never reads this

; ============================================================================
; F_UDIV32BY16 (internal, not a dictionary word) — F_DIVID_HI:
; F_DIVID_LO (32-bit unsigned dividend) / BC (16-bit unsigned divisor,
; caller guarantees nonzero) -> core/floatmul.asm's own F_PROD_HI:
; F_PROD_LO (32-bit unsigned quotient). Classic 32-iteration
; shift-compare-subtract restoring division, the same shape
; kernel/math's own MATH_UDIV16 uses for a 16-bit dividend, widened to
; a 32-bit dividend and a 32-bit quotient-in-progress (the remainder
; itself stays 16 bits, same as MATH_UDIV16, since it's always kept
; smaller than the 16-bit divisor).
; Destroys: AF, DE, HL
; ============================================================================
F_UDIV32BY16:
    ld   hl, 0
    ld   (F_PROD_LO), hl
    ld   (F_PROD_HI), hl
    ld   de, 0                ; de = remainder-in-progress
    ld   a, 32
    ld   (F_DIV_CNT), a
.loop:
    ld   hl, (F_DIVID_LO)
    add  hl, hl                ; shift the 32-bit dividend left by 1 ...
    ld   (F_DIVID_LO), hl
    ld   hl, (F_DIVID_HI)
    adc  hl, hl                 ; ... carrying into the high word, whose
                                ; own carry-out is the bit this
                                ; iteration feeds into the remainder
    ld   (F_DIVID_HI), hl
    rl   e
    rl   d                       ; shift that bit into the 16-bit
                                 ; remainder DE
    ld   hl, (F_PROD_LO)
    add  hl, hl                 ; shift the 32-bit quotient-in-progress
    ld   (F_PROD_LO), hl         ; left too, making room for this
    ld   hl, (F_PROD_HI)         ; iteration's bit
    adc  hl, hl
    ld   (F_PROD_HI), hl
    push de                      ; copy the remainder into HL for the
    pop  hl                      ; comparison below, without destroying
                                 ; DE (push/pop copies, unlike EX DE,HL)
    or   a
    sbc  hl, bc                  ; hl = remainder - divisor; carry set
                                 ; iff remainder < divisor
    jr   c, .no_sub
    ex   de, hl                   ; de = new (reduced) remainder
    ld   hl, (F_PROD_LO)
    inc  hl                        ; set the quotient's LSB -- safe:
                                   ; the shift above guarantees bit 0
                                   ; is currently 0, same reasoning as
                                   ; MATH_UDIV16's own "inc hl is safe"
    ld   (F_PROD_LO), hl
.no_sub:
    ld   a, (F_DIV_CNT)
    dec  a
    ld   (F_DIV_CNT), a
    jr   nz, .loop
    ld   (F_DIV_REM), de     ; expose the final remainder too -- F/
                             ; itself never reads this, but Phase 22's
                             ; F. (core/floatprint.asm) needs it for
                             ; splitting a scaled value into integer
                             ; and fractional decimal digits; a
                             ; backward-compatible addition, not a
                             ; behavior change for F/
    ret

; ============================================================================
; F/ ( f1 f2 -- f1/f2 )
; ============================================================================
H_FSLASH:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "F", "/"
W_FSLASH:
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

    ld   hl, (F_M2)
    call MATH_ABS16
    ld   a, h
    or   l
    jr   nz, .divisor_ok
    ld   hl, 0                  ; divide by zero -- safe default,
    xor  a                      ; matching kernel/math's own MATH_UDIV16
    call FPUSH
    ret
.divisor_ok:
    ld   b, h
    ld   c, l                   ; bc = abs(m2)

    ld   hl, (F_M1)
    call MATH_ABS16              ; hl = abs(m1)
    ld   (F_DIVID_HI), hl
    ld   hl, 0
    ld   (F_DIVID_LO), hl        ; 32-bit dividend = abs(m1) << 16

    call F_UDIV32BY16             ; -> F_PROD_HI:F_PROD_LO = quotient
    call F_NORMALIZE32             ; -> F_PROD_LO = normalized
                                   ; magnitude, F_NORM_SHIFT set
                                   ; (core/floatmul.asm)

    ld   hl, (F_PROD_LO)
    ld   a, (F_MSIGN)
    or   a
    jr   z, .done_sign
    call MATH_NEGATE16
.done_sign:
    push hl                       ; stash the (possibly negated)
                                  ; mantissa while computing the
                                  ; exponent
    ld   a, (F_E1)
    ld   b, a
    ld   a, (F_E2)
    ld   c, a
    ld   a, b
    sub  c                        ; a = e1 - e2
    sub  16                       ; a = e1 - e2 - 16
    ld   b, a
    ld   a, (F_NORM_SHIFT)
    add  a, b
    ld   (F_RESULT_EXP), a
    pop  hl
    ld   a, (F_RESULT_EXP)
    call FPUSH
    ret

DICT_LATEST_INIT_FLOATDIV EQU H_FSLASH   ; head of the dictionary once
                                          ; this file's own word is
                                          ; included

    ENDIF
