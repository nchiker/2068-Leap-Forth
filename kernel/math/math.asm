; ============================================================================
; kernel/math/math.asm -- 16-bit integer arithmetic
;
; Multiply, divide, remainder, compare, negate/abs/sign, integer square root and the random
; number step. The multiply, divide and random routines are Leap-C's (MIT, same author;
; src/runtime/helpers.asm RT_MUL/RT_UMUL/RT_UDIV/RT_SDIV, src/runtime/library.asm LIB_RAND) under this
; file's names and register contracts (docs/V2/FLOAT_SPEC.md section 11). They use registers only.
;
; Rules shared by the routines: results are 16 bits (wraparound, no overflow signal); division
; truncates toward zero; the remainder has the dividend's sign; a divisor of 0 gives 0;
; NEGATE16 and ABS16 of -32768 leave -32768.
; ============================================================================

    IFNDEF MATH_ASM
    DEFINE MATH_ASM

; ============================================================================
; MATH_MULTIPLY16 -- signed 16x16 -> 16 multiply
; The low 16 bits of a product are the same for signed and unsigned operands, so this is
; MATH_UMUL16 with HL moved into BC.
; In:  HL = multiplicand (signed), DE = multiplier (signed)
; Out: HL = product (signed, truncated to 16 bits)
; Destroys: AF, BC (DE is kept)
; ============================================================================
MATH_MULTIPLY16:
    ld   b, h
    ld   c, l                        ; BC = HL; falls into MATH_UMUL16

; ============================================================================
; MATH_UMUL16 -- unsigned 16x16 -> 16 multiply (Leap-C's RT_UMUL)
; Shift-and-add over the multiplier's bits from the top: 16 steps, registers only.
; In:  DE = multiplicand, BC = multiplier
; Out: HL = product (truncated to 16 bits)
; Destroys: AF, BC (DE is kept)
; ============================================================================
MATH_UMUL16:
    ld   hl, 0
    ld   a, 16
.bit:
    add  hl, hl                    ; partial product *= 2
    rl   c                           ; the multiplier's next bit, from the top, into carry
    rl   b
    jr   nc, .next
    add  hl, de                        ; product += multiplicand
.next:
    dec  a
    jr   nz, .bit
    ret

; ============================================================================
; MATH_UDIV16 -- unsigned 16-bit divide (Leap-C's RT_UDIV)
; Restoring division, 16 steps, registers only: HL shifts the dividend out at the top and the
; quotient in at the bottom; DE builds the remainder.
; In:  HL = dividend, BC = divisor (at most 32768, as MATH_SDIV16's: a larger one can carry out of the
;      remainder's ADC)
; Out: HL = quotient, DE = remainder; HL = DE = 0 if BC = 0
; Destroys: AF (BC is kept)
; ============================================================================
MATH_UDIV16:
    ld   a, b
    or   c
    jr   nz, .divide
    ld   h, a                      ; divide by zero: HL = DE = 0
    ld   l, a
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
    sbc  hl, bc                    ; try remainder - divisor (the carry from ADC is always 0)
    jr   nc, .one                  ; it fitted: keep the difference
    add  hl, bc                      ; it didn't: put the divisor back
    jr   .next
.one:
    inc  e                         ; set the quotient's bit (bit 0 is clear after the shift)
.next:
    ex   de, hl                    ; back: HL = dividend/quotient, DE = remainder
    dec  a
    jr   nz, .bit
    ret

; ============================================================================
; MATH_DIVIDE16 -- signed divide, truncating toward zero (-7 / 2 = -3)
; The quotient is negative iff exactly one operand is (the XOR of the sign bits); the work is
; MATH_SDIV16's.
; In:  HL = dividend (signed), DE = divisor (signed)
; Out: HL = quotient; HL = 0 if DE = 0
; Destroys: AF, BC, DE
; ============================================================================
MATH_DIVIDE16:
    ex   de, hl                    ; HL = divisor, DE = dividend (MATH_SDIV16's order)
    ld   a, h
    xor  d
    and  %10000000                 ; bit 7: the quotient's sign; bit 0 clear: the quotient
    jr   MATH_SDIV16

; ============================================================================
; MATH_MOD16 -- signed remainder, with the dividend's sign (-17 MOD 5 = -2, as C's %)
; The unsigned remainder is the division's DE, so one division pass serves.
; In:  HL = dividend (signed), DE = divisor (signed)
; Out: HL = remainder; HL = 0 if DE = 0
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_MOD16:
    ex   de, hl                    ; HL = divisor, DE = dividend
    ld   a, d
    and  %10000000                 ; bit 7: the dividend's sign
    inc  a                         ; bit 0 set: the remainder is wanted

; ============================================================================
; MATH_SDIV16 -- signed divide worker for MATH_DIVIDE16 and MATH_MOD16 (Leap-C's RT_SDIV)
; Divides the absolute values, then signs the wanted result. MATH_ABS16(-32768) leaves 32768, right
; as an unsigned magnitude.
; In:  HL = divisor, DE = dividend (both signed), A: bit 7 = the sign the result gets,
;      bit 0 = 1 for the remainder, 0 for the quotient (carry clear)
; Out: HL = the signed quotient or remainder (0 for a divisor of 0)
; Destroys: AF, BC, DE
; ============================================================================
MATH_SDIV16:
    push af                        ; keep the sign/select byte
    call MATH_ABS16
    ld   b, h
    ld   c, l                      ; BC = abs(divisor)
    ex   de, hl
    call MATH_ABS16                ; HL = abs(dividend)
    call MATH_UDIV16               ; HL = quotient, DE = remainder
    pop  af
    rra                            ; carry = bit 0, bit 7 -> bit 6
    jr   nc, .sign
    ex   de, hl                    ; the remainder was wanted
.sign:
    and  %01000000                 ; the sign to apply
    ret  z
    jr   MATH_NEGATE16

; ============================================================================
; MATH_NEGATE16 -- two's-complement negate
; In:  HL
; Out: HL = -HL (-32768 stays -32768)
; Destroys: AF
; ============================================================================
MATH_NEGATE16:
    xor  a
    sub  l
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
    ret

; ============================================================================
; MATH_ABS16 -- absolute value
; In:  HL
; Out: HL = |HL| (-32768 stays -32768)
; Destroys: AF
; ============================================================================
MATH_ABS16:
    ld   a, h
    or   a
    ret  p                  ; not negative: done
    jr   MATH_NEGATE16       ; negate and return from there

; ============================================================================
; MATH_SGN16 -- sign
; In:  HL
; Out: HL = -1 if HL < 0, 0 if HL = 0, 1 if HL > 0
; Destroys: AF
; ============================================================================
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
; MATH_SQRT16 -- integer square root, truncating (SQRT16(15) = 3, SQRT16(16) = 4)
; A negative input gives 0. The digit-by-digit binary method with a fixed 8-step loop from
; one = $4000; `one` stays in BC, so the step count is in SQRT_COUNTER (with SQRT_OP, SQRT_RES).
; In:  HL = n (signed; negative gives 0)
; Out: HL = the integer square root of n
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_SQRT16:
    ld   a, h                        ; negative: 0
    or   a
    jp   p, .nonneg
    ld   hl, 0
    ret
.nonneg:
    ld   (SQRT_OP), hl
    ld   hl, 0
    ld   (SQRT_RES), hl
    ld   bc, $4000                     ; `one` = 4^7, the highest power of 4 that fits
    ld   a, 8
    ld   (SQRT_COUNTER), a

.loop:
    ld   hl, (SQRT_RES)
    add  hl, bc                        ; HL = candidate = res + one
    ex   de, hl                          ; DE = candidate
    ld   hl, (SQRT_OP)                    ; HL = op
    or   a
    sbc  hl, de                            ; HL = op - candidate; carry if op < candidate
    jr   c, .no_update

    ; op >= candidate: op = op - candidate (already in HL), res += 2 * one
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
; MATH_RND16 -- pseudo-random integer in [0, x-1] for a positive x (the RND(n) convention)
; x <= 0 returns 0 without advancing the generator.
; The generator is Leap-C's 16-bit xorshift (LIB_RAND): x ^= x<<7, x ^= x>>9, x ^= x<<8. Period
; 65535; 0 is its one fixed point. RND_STATE = 0 means "never seeded" (cold start, or
; MATH_RND_SEED with 0): the first call seeds it from the Z80 R register, the low byte OR 1 so
; the seed is not 0.
; The result is the high word of state * x (floor(state * x / 65536), in 0..x-1), by a
; shift-right product loop: HL is the high half of the running product, BC starts as x and takes
; the low half in as it shifts out.
; In:  HL = x (signed; x<=0 returns 0)
; Out: HL = pseudo-random value in [0, x-1] (or 0 if x<=0)
; Destroys: AF, BC, DE, HL
; ============================================================================
MATH_RND16:
    ld   a, h
    or   a
    jp   m, .zero_result                ; x < 0
    or   l
    jr   z, .zero_result                  ; x = 0

    ld   b, h
    ld   c, l                              ; BC = x
    ld   hl, (RND_STATE)
    ld   a, h
    or   l
    jr   nz, .step

    ; never seeded: seed from the R register, nonzero via OR 1
    ld   a, r
    or   1
    ld   l, a
    ld   a, r                              ; a second read for the high byte
    ld   h, a
.step:                                      ; HL ^= HL<<7; HL ^= HL>>9; HL ^= HL<<8
    ld   a, h
    rra
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
    ld   hl, 0                                ; HL = the product's high half; carry is clear
    ld   a, 16
.mul:
    rr   h                                   ; shift (carry, HL, BC) right: the carry enters
    rr   l                                     ;   at the top, the multiplier's next bit
    rr   b                                       ;   leaves into carry
    rr   c
    jr   nc, .no_add
    add  hl, de                              ; a 1 bit: add the state
.no_add:
    dec  a
    jr   nz, .mul
    rr   h                                   ; the last add's carry and the final shift
    rr   l
    ret

.zero_result:
    ld   hl, 0
    ret

; ============================================================================
; MATH_RND_SEED -- set the random generator's state (RANDOMISE n)
; 0 puts MATH_RND16 back to "never seeded": its next call seeds from the R register. A nonzero
; HL is the new state, giving a reproducible sequence.
; In:  HL = new seed (0 = reset to unseeded)
; Out: none
; Destroys: none
; ============================================================================
MATH_RND_SEED:
    ld   (RND_STATE), hl
    ret

    ENDIF
