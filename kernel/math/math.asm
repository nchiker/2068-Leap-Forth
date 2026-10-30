; ============================================================================
; kernel/math/math.asm — general-purpose 16-bit integer arithmetic
;
; CURRENT STATUS: assembled into the working ROM and exercised under
; ZEsarUX by the automated math and language regression tests.
;
; ORIGIN OF THE MULTIPLY, DIVIDE AND RANDOM ROUTINES: rebuilt from
; 2068-Leap-C (MIT, same copyright holder as this project) —
; src/runtime/helpers.asm (RT_MUL/RT_UMUL, RT_UDIV and the one shared
; sign routine RT_SDIV behind RT_DIVS/RT_MODS) and src/runtime/
; library.asm (LIB_RAND, the xorshift step) — under this file's own
; names and register contracts (FLOAT_SPEC.md section 11). They
; replace the earlier shift-and-add multiply and the divide that kept
; its dividend, quotient and loop counter in RAM: these use registers
; only. The old RAM cells (DIV_DIVIDEND, DIV_QUOT, DIV_COUNTER,
; MATH_SIGN in include/sysvars.inc) are no longer used by any code.
; The results are unchanged: 16-bit wraparound, quotient truncated
; toward 0, remainder with the dividend's sign, divisor 0 giving 0.
; They were checked against Python on tens of thousands of operand
; pairs, edge values included, see docs/V2/FLOAT_SPEC.md section 11.
;
; Owns: multiply and divide, which Z80 has no hardware instructions
; for. Built specifically to support basic/'s expression evaluator,
; but deliberately kept general-purpose and free of any BASIC-specific
; assumptions — this project's own stated principle is that kernel
; modules should be reusable by other future assembly-language
; software, and 16-bit multiply/divide is exactly that kind of
; genuinely generic building block, not something that belongs buried
; inside basic/basic.asm.
;
; basic/'s own DIV10 (division by 10 specifically, for decimal-to-
; string conversion) stays where it is, unchanged — it's a different,
; narrower routine (fixed divisor, combined quotient+remainder output
; tuned for repeated-digit-extraction) serving a different purpose,
; not something this module's MATH_UDIV16 replaces.
;
; Result on overflow: both multiply and divide simply truncate to 16
; bits, matching how this project's other integer arithmetic already
; behaves (BASIC_NUM_TO_STRING, DIV10) — no overflow flag or error
; signal, consistent with there being no error-reporting mechanism
; anywhere else in this codebase yet either.
;
; Divide by zero: MATH_DIVIDE16 and MATH_MOD16 return 0 rather than
; the nonsense result the bare division loop would otherwise produce
; (a divisor of 0 means "remainder >= divisor" is trivially true every
; iteration, giving a quotient of all 1-bits, i.e. -1) — a deliberate,
; safe default given there's no error-reporting mechanism to surface a
; real error through yet, not an oversight. MATH_UDIV16 checks for it
; explicitly up front.
; ============================================================================

    IFNDEF MATH_ASM
    DEFINE MATH_ASM


; ============================================================================
; MATH_MULTIPLY16
; Signed 16x16->16 multiply. The low 16 bits of a product are the same
; for signed and unsigned operands (two's complement), so this is
; MATH_UMUL16 with the multiplier moved into BC and nothing else: the
; negative operands wrap around exactly as the signed result needs.
; In:  HL = multiplicand (signed), DE = multiplier (signed)
; Out: HL = product (signed, truncated to 16 bits)
; Destroys: AF, BC (DE is kept)
; ============================================================================
MATH_MULTIPLY16:
    ld   b, h
    ld   c, l                        ; BC = HL; falls into the routine
                                    ; below, which scans BC's bits and
                                    ; adds DE (the product is the same
                                    ; whichever factor is scanned)

; ============================================================================
; MATH_UMUL16
; Unsigned 16x16->16 multiply via shift-and-add (Z80 has no hardware
; multiply), from Leap-C's RT_UMUL: the multiplier's bits are taken
; from the top, one per step, so the partial product is doubled each
; step and DE is added for every 1 bit — registers only, 16 steps.
; In:  DE = multiplicand, BC = multiplier
; Out: HL = product (truncated to 16 bits)
; Destroys: AF, BC (DE is kept)
; ============================================================================
MATH_UMUL16:
    ld   hl, 0
    ld   a, 16
.bit:
    add  hl, hl                    ; partial product *= 2
    rl   c                           ; next multiplier bit, from the
    rl   b                             ; top, into carry
    jr   nc, .next
    add  hl, de                        ; product += multiplicand
.next:
    dec  a
    jr   nz, .bit
    ret

; ============================================================================
; MATH_UDIV16
; Unsigned 16-bit divide via 16-iteration shift-and-subtract (restoring
; division), from Leap-C's RT_UDIV — generalizes basic/'s own DIV10 to
; an arbitrary runtime divisor. Registers only: HL starts as the
; dividend and shifts its bits out at the top while the quotient
; shifts in at the bottom, DE builds the remainder (it needs no 17th
; bit: before step i it is below 2^(i-1), so 16 bits hold it).
; In:  HL = dividend, BC = divisor
; Out: HL = quotient, DE = remainder; if BC = 0 (divide by zero), HL =
;      DE = 0 rather than the nonsense all-1s quotient the algorithm
;      would otherwise produce — checked explicitly up front
; Destroys: AF (BC is kept)
; ============================================================================
MATH_UDIV16:
    ld   a, b
    or   c
    jr   nz, .divide
    ld   h, a                      ; divide by zero — safe default,
    ld   l, a                        ; see this file's header
    ld   d, a
    ld   e, a
    ret
.divide:
    ld   de, 0                     ; DE = the remainder
    ld   a, 16
.bit:
    add  hl, hl                    ; dividend's next bit out (carry)
    ex   de, hl                    ; HL = remainder, DE = dividend/quotient
    adc  hl, hl                    ; remainder = remainder*2 + that bit
    sbc  hl, bc                    ; try remainder - divisor (the carry
                                  ; from ADC above is always 0 here)
    jr   nc, .one                  ; it fitted: keep the difference
    add  hl, bc                      ; it didn't: put the divisor back
    jr   .next
.one:
    inc  e                         ; set the quotient's bit — safe, the
                                  ; shift above left bit 0 clear
.next:
    ex   de, hl                    ; back: HL = dividend/quotient,
    dec  a                           ; DE = remainder
    jr   nz, .bit
    ret

; ============================================================================
; MATH_DIVIDE16
; Signed wrapper around MATH_UDIV16, sharing MATH_SDIV16's sign-then-
; magnitude steps with MATH_MOD16. Truncates toward zero (matching
; typical integer BASIC division — e.g. -7/2 = -3, not -4), since the
; unsigned division works on absolute values and the sign is applied
; to the truncated magnitude afterward. The quotient is negative iff
; exactly one operand is (the XOR of their sign bits).
; In:  HL = dividend (signed), DE = divisor (signed)
; Out: HL = quotient (signed, truncated toward zero); HL = 0 if DE = 0
;      (divide by zero — see this file's header)
; Destroys: AF, BC, DE
; ============================================================================
MATH_DIVIDE16:
    ex   de, hl                    ; HL = divisor, DE = dividend (the
                                  ; order MATH_SDIV16 works in)
    ld   a, h
    xor  d
    and  %10000000                 ; bit 7: the quotient's sign; bit 0
                                  ; clear: the quotient is wanted
    jr   MATH_SDIV16

; ============================================================================
; MATH_MOD16
; Signed 16-bit remainder, matching MATH_DIVIDE16's own truncating-
; toward-zero convention: the remainder takes the DIVIDEND's sign (or
; 0), not the divisor's — e.g. -17 MOD 5 = -2, not 3 (a flooring-
; division language like Python's bare % would give 3; this matches
; C's %, and this project's own -17/5=-3 truncating quotient: -3*5 +
; (-2) = -17, consistent). Unlike MATH_DIVIDE16's XOR of the two
; signs, only the dividend's sign matters here — the divisor's sign
; doesn't flip the remainder's sign, only its magnitude range
; (|remainder| < |divisor|). The unsigned remainder is the division's
; DE, so no second division pass is needed.
; In:  HL = dividend (signed), DE = divisor (signed)
; Out: HL = remainder (signed; sign matches the dividend, or 0); HL = 0
;      if DE = 0 (matches MATH_DIVIDE16's own divide-by-zero default —
;      see kernel/math/math.asm's file header)
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_MOD16:
    ex   de, hl                    ; HL = divisor, DE = dividend
    ld   a, d
    and  %10000000                 ; bit 7: the DIVIDEND's sign (not
                                  ; XORed with the divisor's)
    inc  a                         ; bit 0 set: the remainder is wanted

; ----------------------------------------------------------------------
; MATH_SDIV16 (internal; reached from MATH_DIVIDE16 and MATH_MOD16)
; Leap-C's RT_SDIV: divide the absolute values, then give the wanted
; result its sign. MATH_ABS16(-32768) leaves 32768, which is right as
; an unsigned magnitude here.
; In:  HL = divisor, DE = dividend (both signed), A: bit 7 = the sign
;      the result gets, bit 0 = 1 for the remainder, 0 for the quotient
;      (carry clear)
; Out: HL = the signed quotient or remainder (0 for a divisor of 0)
; Destroys: AF, BC, DE
; ----------------------------------------------------------------------
MATH_SDIV16:
    push af                        ; keep the sign/select byte
    call MATH_ABS16
    ld   b, h
    ld   c, l                      ; BC = abs(divisor)
    ex   de, hl
    call MATH_ABS16                ; HL = abs(dividend)
    call MATH_UDIV16               ; HL = quotient, DE = remainder
    pop  af
    rra                            ; carry (clear) in: carry = bit 0,
                                  ; bit 7 -> bit 6
    jr   nc, .sign
    ex   de, hl                    ; the remainder was wanted
.sign:
    and  %01000000                 ; the sign to apply
    ret  z
    jp   MATH_NEGATE16

; ============================================================================
; MATH_COMPARE16
; Signed 16-bit comparison, built specifically to support basic/'s new
; IF/ELSEIF relational operators (=, <>, <, >, <=, >=) but kept as
; general-purpose as MATH_MULTIPLY16/DIVIDE16 — no BASIC-specific
; assumptions here either.
;
; Z80 has no signed-comparison instruction, only SBC HL,DE (an
; unsigned-magnitude subtract that still sets the P/V flag as a
; signed-overflow indicator). The standard technique: after "OR A" /
; "SBC HL,DE", the result's sign flag tells you HL-DE's true sign
; UNLESS a signed overflow occurred (P/V set), in which case the sign
; flag is backwards and must be inverted. Overflow only happens when
; HL and DE have different signs and the subtraction result's sign
; matches HL's own original sign the "wrong" way — verified via a
; Python simulation of this exact flag logic (sign-of-HL, sign-of-DE,
; sign-of-result, overflow-if-signs-differ-and-result-doesn't-match)
; against all pairs from a set of edge values (0, ±1, ±5, ±32767,
; ±32768) plus 200,000 random signed pairs, zero failures, before any
; Z80 was written — same discipline as this file's multiply/divide.
; In:  HL = left operand (signed), DE = right operand (signed)
; Out: A = 0 if HL = DE, 1 if HL > DE, $FF if HL < DE
; Destroys: AF, HL (DE is only read, never written, by SBC HL,DE)
; ============================================================================
MATH_COMPARE16:
    or   a
    sbc  hl, de
    jr   z, .equal
    jp   po, .no_overflow           ; P/V clear (parity odd) = no signed
                                    ; overflow — the sign flag already
                                    ; tells the truth
    jp   m, .greater                 ; overflow occurred: sign flag is
                                     ; backwards, so a "negative" result
                                     ; here actually means HL > DE
    jr   .less
.no_overflow:
    jp   m, .less
    jr   .greater
.equal:
    xor  a
    ret
.less:
    ld   a, $FF
    ret
.greater:
    ld   a, 1
    ret

; ============================================================================
; MATH_NEGATE16 / MATH_ABS16 / MATH_SGN16
;
; Formalizes arithmetic that basic/'s evaluator (and any future caller)
; was previously doing as hand-rolled two's-complement negation
; wherever it came up — no behavior change from what already existed
; ad hoc, just a single documented call site instead of the same few
; instructions retyped in multiple places (same duplication concern
; that motivated the KEYWORD_HILITE_TABLE unification).
;
; MATH_ADD16/MATH_SUB16 originally lived here too (thin wrappers
; around a bare `ADD HL,DE`/`SBC HL,DE`), formalized alongside these
; three for the same reason — but never gained a second call site the
; way NEGATE16/ABS16/SGN16 did (this project's own `+`/`-` words use
; the bare instructions directly), so they sat as genuine dead code
; and were removed.
;
; All verified via Python simulation (50,011 values: every edge case —
; 0, +-1, +-32767, -32768 — plus 50,000 random signed 16-bit values)
; before any Z80 was written, same discipline as this file's
; multiply/divide/compare. Truncates on overflow, same as MATH_
; MULTIPLY16/MATH_DIVIDE16 — no overflow flag, consistent with there
; being no error-reporting mechanism at this layer.
;
; The one genuine edge case: NEGATE16(-32768) and ABS16(-32768) both
; return -32768 unchanged, NOT 32768 — the positive equivalent has no
; representation in signed 16-bit two's complement, so the value
; silently doesn't change sign at that single boundary. Confirmed via
; the same Python simulation, not just reasoned about; matches the
; well-known behavior of two's-complement negation everywhere else
; (Z80, x86, etc.), not a bug specific to this implementation.
; ============================================================================

; ----------------------------------------------------------------------
; MATH_NEGATE16
; Two's-complement negate. The sign step of MATH_SDIV16 (and, before
; step F, of the earlier multiply and divide wrappers) — a documented,
; reusable routine of its own.
; In:  HL
; Out: HL = -HL (truncated; -32768 stays -32768 — see file header)
; Destroys: AF
; ----------------------------------------------------------------------
MATH_NEGATE16:
    xor  a
    sub  l
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
    ret

; ----------------------------------------------------------------------
; MATH_ABS16
; In:  HL
; Out: HL = absolute value of HL (truncated; ABS(-32768) = -32768 —
;      see file header)
; Destroys: AF
; ----------------------------------------------------------------------
MATH_ABS16:
    ld   a, h
    or   a
    ret  p                  ; sign bit clear (positive or zero) —
                            ; already correct, nothing to do
    jr   MATH_NEGATE16       ; tail-call: negate and return directly
                            ; from there

; ----------------------------------------------------------------------
; MATH_SGN16
; In:  HL
; Out: HL = -1 if HL < 0, 0 if HL = 0, 1 if HL > 0
; Destroys: AF
; ----------------------------------------------------------------------
MATH_SGN16:
    ld   a, h
    or   l
    jr   z, .zero
    ld   a, h
    or   a
    jp   p, .positive
    ld   hl, -1
    ret
.positive:
    ld   hl, 1
    ret
.zero:
    ld   hl, 0
    ret

; ============================================================================
; MATH_SQRT16
; Signed 16-bit integer square root, truncating (SQRT16(n) is the
; largest R such that R*R <= n — e.g. SQRT16(15)=3, SQRT16(16)=4).
; Negative input is treated as 0 — no error-reporting mechanism exists
; at this layer, matching this file's own established safe-default
; convention (see MATH_DIVIDE16's own divide-by-zero handling in this
; file's header) — and matching every OTHER routine in kernel/math
; being signed (basic/'s values are all signed 16-bit integers; there
; is no unsigned type at the BASIC level), rather than making this the
; one unsigned exception.
;
; Classic "digit by digit" binary integer square root (see e.g.
; Wikipedia's algorithm of the same name) — the same iterative
; shift/compare/subtract shape as this file's own MATH_UDIV16, just
; extracting result bits 2 input-bits at a time instead of 1. Uses a
; FIXED 8-iteration loop starting from `one=$4000` rather than the
; textbook version's own variable-length leading "shrink `one` until
; it's <= input" loop — Python-verified to be exactly equivalent
; (early iterations naturally contribute nothing when the input is
; small, instead of being skipped), and a fixed trip count is
; considerably simpler to implement as a Z80 loop.
;
; Verified via Python simulation before any Z80 was written, in two
; passes: first the core shift/compare/subtract algorithm alone
; against Python's own math.isqrt for all 65,536 possible UNSIGNED
; 16-bit magnitudes (zero mismatches) — this caught nothing, but did
; NOT by itself verify the actual routine's real behavior, since it
; didn't yet include the negative-input handling below. Combining the
; negative check with the core algorithm and re-verifying the ACTUAL
; end-to-end design against all 65,536 SIGNED 16-bit inputs (negative
; -> 0 expected, non-negative -> its own square root expected) is what
; this routine's real contract needs — done, zero mismatches. (An
; earlier version of this routine's own header claimed the SIGNED
; input was "unsigned," which very nearly shipped as a real, wrong
; sign-check — caught only because tools/z80sim's own broad random
; sample happened to include values with bit 15 set and flagged 243
; failures immediately; see this file's own established practice of
; verifying the ACTUAL combined behavior, not just the core algorithm
; in isolation.) Also checked the largest intermediate values the
; algorithm reaches (max 20,480 for `res+one`, max 65,535 for the
; shrinking working copy) to confirm they fit a 16-bit register.
;
; Uses SQRT_OP/SQRT_RES/SQRT_COUNTER scratch (kernel/math's own, same
; "needs a copy in HL for the compare, but HL is also busy with other
; work that same iteration" reasoning as MATH_UDIV16's own former DIV_
; DIVIDEND/DIV_QUOT/DIV_COUNTER scratch, now unused — see those sysvars'
; header in include/sysvars.inc). `one` stays in BC the whole loop, so
; the usual DJNZ-in-B trick isn't available for the loop counter,
; hence SQRT_COUNTER instead.
; In:  HL = n (signed; negative treated as 0 — see this header)
; Out: HL = the integer square root of n
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_SQRT16:
    ld   a, h                        ; negative (as signed) — treat
    or   a                             ; as 0, no error signal at this
    jp   p, .nonneg                      ; layer (see this routine's
    ld   hl, 0                             ; own header) — same sign-
    ret                                     ; check idiom as MATH_ABS16
                                          ; above, not BIT (kept
                                          ; consistent with the rest of
                                          ; this file's style)
.nonneg:
    ld   (SQRT_OP), hl
    ld   hl, 0
    ld   (SQRT_RES), hl
    ld   bc, $4000                     ; 'one' — the highest even
                                      ; power of 4 that fits a 16-bit
                                      ; input (4^7 = 16384)
    ld   a, 8
    ld   (SQRT_COUNTER), a

.loop:
    ld   hl, (SQRT_RES)
    add  hl, bc                        ; HL = candidate = res + one
    ex   de, hl                          ; DE = candidate
    ld   hl, (SQRT_OP)                    ; HL = op
    or   a
    sbc  hl, de                            ; HL = op - candidate;
                                          ; carry set if op < candidate
    jr   c, .no_update                      ; op < candidate — this
                                            ; iteration contributes
                                            ; nothing

    ; op >= candidate: commit the subtraction (HL already holds the
    ; correct new op from the SBC above — no need to recompute it) and
    ; add 2*one to res
    ld   (SQRT_OP), hl
    ld   hl, (SQRT_RES)
    add  hl, bc
    add  hl, bc
    ld   (SQRT_RES), hl

.no_update:
    ld   hl, (SQRT_RES)                    ; res >>= 1
    srl  h
    rr   l
    ld   (SQRT_RES), hl

    srl  b                                   ; one >>= 2
    rr   c
    srl  b
    rr   c

    ld   a, (SQRT_COUNTER)
    dec  a
    ld   (SQRT_COUNTER), a
    jr   nz, .loop

    ld   hl, (SQRT_RES)
    ret

; ============================================================================
; MATH_RND16
; Pseudo-random integer in [0, x-1] for a positive x (matches the
; common BASIC RND(n) convention of "n possible results, 0 to n-1").
; x<=0 (signed) returns 0 without advancing the generator — no error
; mechanism at this layer, same safe-default convention as
; MATH_DIVIDE16's divide-by-zero.
;
; Generator: Leap-C's 16-bit xorshift (src/runtime/library.asm
; LIB_RAND; MIT, same copyright holder): x ^= x<<7, x ^= x>>9,
; x ^= x<<8, all 16-bit. Period 65535 — every nonzero state is visited
; once; 0 is the one fixed point, so the state is never 0 while the
; generator runs. (The earlier LFSR moved one bit per call, so each
; value was the previous one shifted — consecutive results were
; strongly related, and a MOD of the 15 low bits favoured small
; results.)
;
; RND_STATE (a persistent sysvar, not a register — must survive
; between separate BASIC statements) reading as 0 doubles as "never
; seeded yet" (MEM_INIT zeroes all of RAM at cold start, and
; MATH_RND_SEED with 0 puts it back): the first RND(x) call seeds it
; from the Z80 R register (the classic technique: R increments on
; every instruction fetch, so its value at the moment of the call
; depends on how many instructions have executed since reset —
; unpredictable from a BASIC program's perspective, though NOT
; cryptographically random), the low byte OR'd with 1 so the seed
; isn't 0. This seeding step is hardware-timing-dependent and can't be
; meaningfully verified by tools/z80sim (no timing model); only the
; deterministic step and the scaling below were verified.
;
; Range-scaling: the result is the high word of the 16x16 unsigned
; product state * x, i.e. floor(state * x / 65536), which lies in
; 0..x-1 for any state in 0..65535 and uses all 16 bits of the state
; (a MOD of it would favour small results unless x divides 65536).
; The high word is built by the shift-right product loop: HL is the
; high half of the running product, BC starts as the multiplier x and
; takes the low half in as it shifts out.
; In:  HL = x (signed; x<=0 returns 0)
; Out: HL = pseudo-random value in [0, x-1] (or 0 if x<=0)
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_RND16:
    ld   a, h
    or   a
    jp   m, .zero_result                ; x negative -> 0
    or   l
    jr   z, .zero_result                  ; x = 0 -> 0

    ld   b, h
    ld   c, l                              ; BC = x
    ld   hl, (RND_STATE)
    ld   a, h
    or   l
    jr   nz, .step

    ; never seeded (still 0, from MEM_INIT's cold-start zeroing) —
    ; seed from the R register, guaranteed nonzero via OR 1
    ld   a, r
    or   1
    ld   l, a
    ld   a, r                              ; a second read for the high
    ld   h, a                                ; byte too, for more spread
                                            ; than R's own 128-value
                                            ; cycle alone would give
.step:                                      ; HL ^= HL<<7; HL ^= HL>>9;
    ld   a, h                               ; HL ^= HL<<8 (Leap-C's
    rra                                       ; sequence, unchanged)
    ld   a, l
    rra
    xor  h
    ld   h, a
    ld   a, l
    rra
    ld   a, h
    rra
    xor  l
    ld   l, a
    xor  h
    ld   h, a
    ld   (RND_STATE), hl                    ; commit the new state

    ex   de, hl                              ; DE = state (multiplicand)
    ld   hl, 0                                ; HL = the product's high
    ld   a, 16                                  ; half; carry is clear
.mul:
    rr   h                                   ; shift (carry, HL, BC)
    rr   l                                     ; right: the previous
    rr   b                                       ; step's carry enters
    rr   c                                         ; at the top, the
    jr   nc, .no_add                                 ; multiplier's next
    add  hl, de                                      ; bit leaves: add
.no_add:                                             ; the state for 1
    dec  a
    jr   nz, .mul
    rr   h                                   ; the last add's carry and
    rr   l                                     ; the final shift
    ret

.zero_result:
    ld   hl, 0
    ret

; ============================================================================
; MATH_RND_SEED
; Explicitly (re)seeds MATH_RND16's LFSR. HL=0 resets RND_STATE back to
; MATH_RND16's own "never seeded yet" sentinel — the cold-boot value
; MEM_INIT's zeroing already leaves it at — so the very next RND() call
; reseeds from the Z80 R register exactly as it would on a fresh boot,
; not a plain no-op (a genuine LFSR state of 0 is a degenerate fixed
; point that never advances, which is exactly why MATH_RND16 already
; special-cases it — this routine deliberately reuses that same
; special case rather than inventing a second "unseeded" convention). A
; nonzero HL becomes the new deterministic seed directly, in the exact
; state format MATH_RND16's own LFSR step advances — useful for
; reproducible "random" sequences (e.g. testing). Backs BASIC's
; RANDOMISE <n>.
; In:  HL = new seed (0 = reset to unseeded)
; Out: none
; Destroys: none
; ============================================================================
MATH_RND_SEED:
    ld   (RND_STATE), hl
    ret

    ENDIF
