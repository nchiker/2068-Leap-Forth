; ============================================================================
; core/floatprint.asm — Phase 22: F. (print a float)
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm,
; core/floatmul.asm, core/floatdiv.asm, AND core/print.asm (all must be
; INCLUDEd first, in that order — this file's own first header chains
; through DICT_CHAIN_POINT, and reuses floatmul.asm's own F_UMUL32/
; F_PROD_HI/F_PROD_LO/F_MSIGN, floatdiv.asm's own F_UDIV32BY16/
; F_DIVID_HI/F_DIVID_LO/F_DIV_REM, and print.asm's own UDIV10/W_EMIT
; directly rather than duplicating any of it).
;
; WHAT THIS ADDS: F. ( f -- ), printing a float as a signed decimal
; number with a FIXED 4 digits after the decimal point (e.g. "6.0000",
; "0.2500", "-2.0000"), followed by a trailing space — the same
; trailing-space convention `.` (Phase 10) already established, so
; consecutive `F.`s read as separate, space-separated numbers.
;
; THE ALGORITHM: scale the float's magnitude up by exactly 10000 as an
; exact 32-bit integer (reusing floatmul.asm's own F_UMUL32, since it's
; already a proven unsigned 16x16->32 multiply — value*10000 fits
; comfortably in 32 bits for any 16-bit mantissa), then shift that
; scaled 32-bit value by the float's own exponent (right if negative,
; left if positive — a new pair of small helpers below, F_SHIFT32_LEFT/
; RIGHT, operating on F_PROD_HI/F_PROD_LO in place). What's left is
; round(magnitude*10000), truncated toward zero on any bit lost during
; the exponent shift. Dividing that by 10000 (reusing floatdiv.asm's
; own F_UDIV32BY16, and its newly-exposed F_DIV_REM) splits it cleanly
; into an integer part (the quotient) and a 4-digit fractional part
; (the remainder, always 0-9999) — printed via print.asm's own UDIV10,
; the exact same digit-collection idiom `.` already uses, just with a
; FIXED 4-iteration loop for the fraction (always exactly 4 digits,
; zero-padded) instead of `.`'s own variable-length one.
;
; A REAL, DOCUMENTED PRECISION LIMIT, NOT A BUG: the exponent shift
; TRUNCATES rather than rounds — any bits shifted off the bottom during
; a right-shift are simply discarded, so the displayed value is always
; the true value rounded TOWARD ZERO to 4 decimal digits, never rounded
; to nearest. This is the same class of accepted imprecision
; core/float.asm's own header already documents for its alignment
; step, not a new kind of inaccuracy introduced here.
;
; HAND-VERIFIED before trusting it, reusing the exact float values
; already proven in rom/forth_smoke_p18.asm/p19.asm:
;   (m=24576,e=-12) [6.0, from F*'s own 2.0*3.0 test] -> abs*10000 =
;     245760000 ($0EA60000); >>12 = 60000 ($0000EA60, HI clears);
;     60000/10000 = 6 remainder 0 -> prints "6.0000 "
;   (m=16384,e=-16) [0.25, from F*'s own 0.5*0.5 test] -> abs*10000 =
;     163840000; >>16 = 2500 (HI clears exactly, a 16-bit shift just
;     moves the high word down); 2500/10000 = 0 remainder 2500 ->
;     prints "0.2500 "
;   (m=-16384,e=-13) [-2.0, from F/'s own -6.0/3.0 test] -> abs*10000 =
;     163840000; >>13 = 20000; 20000/10000 = 2 remainder 0 -> prints
;     "-2.0000 ", exercising sign handling
; ============================================================================

    IFNDEF CORE_FLOATPRINT_ASM
    DEFINE CORE_FLOATPRINT_ASM

; ============================================================================
; F_SHIFT32_RIGHT / F_SHIFT32_LEFT (internal, not dictionary words) —
; shift the unsigned 32-bit magnitude in F_PROD_HI:F_PROD_LO (reusing
; core/floatmul.asm's own scratch — nothing else needs it at this
; point in F.'s own flow) in place by B bit positions. Bounded by
; whatever B holds (an exponent's absolute value, realistically small
; for this project's floats); B=0 is a safe no-op.
; ============================================================================
F_SHIFT32_RIGHT:
    ld   a, b
    or   a
    ret  z
.loop:
    ld   hl, (F_PROD_HI)
    srl  h
    rr   l
    ld   (F_PROD_HI), hl
    ld   hl, (F_PROD_LO)
    rr   h
    rr   l
    ld   (F_PROD_LO), hl
    djnz .loop
    ret

F_SHIFT32_LEFT:
    ld   a, b
    or   a
    ret  z
.loop:
    ld   hl, (F_PROD_LO)
    add  hl, hl
    ld   (F_PROD_LO), hl
    ld   hl, (F_PROD_HI)
    adc  hl, hl
    ld   (F_PROD_HI), hl
    djnz .loop
    ret

; ============================================================================
; PRINT_UDEC16 (internal) — HL = unsigned 16-bit value; prints it as
; decimal digits with no leading zeros (prints "0" for zero), no
; trailing space. The same digit-collection idiom core/print.asm's
; W_DOT uses for its own integer part, factored out here since F.
; needs the identical logic without W_DOT's own sign/trailing-space
; handling wrapped around it.
; ============================================================================
PRINT_UDEC16:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   hl, "0"
    call DPUSH_HL
    call W_EMIT
    ret
.hasdigits:
    ld   c, 0
.divloop:
    ld   a, h
    or   l
    jr   z, .printdigits
    call UDIV10
    push af
    inc  c
    jr   .divloop
.printdigits:
    ld   b, c
.printloop:
    pop  af
    add  a, "0"
    ld   l, a
    ld   h, 0
    push bc
    call DPUSH_HL
    call W_EMIT
    pop  bc
    djnz .printloop
    ret

; ============================================================================
; PRINT_UDEC16_PAD4 (internal) — HL = unsigned 16-bit value, 0-9999;
; prints it as EXACTLY 4 decimal digits, zero-padded (e.g. 5 -> "0005").
; Fixed 4-iteration loop rather than PRINT_UDEC16's variable-length one
; — F.'s own fractional part must always show 4 digits, leading zeros
; included.
;
; Uses C, not B, as the divloop's own counter — UDIV10 destroys B
; internally (its own 16-iteration bit loop, documented in its own
; header), so a counter sharing B with a loop that calls UDIV10 gets
; silently reset to 0 after the first call and then wraps to 255 on the
; next DJNZ instead of ever reaching zero. A real bug caught exactly
; this way on the first real Fuse run of rom/forth_smoke_p22.asm: the
; integer part and "." printed correctly, then execution hung
; completely inside this routine's own divloop — traced to this
; register conflict, not anything in the surrounding W_FDOT logic.
; ============================================================================
PRINT_UDEC16_PAD4:
    ld   c, 4
.divloop:
    call UDIV10
    push af
    dec  c
    jr   nz, .divloop
    ld   b, 4
.printloop:
    pop  af
    add  a, "0"
    ld   l, a
    ld   h, 0
    push bc
    call DPUSH_HL
    call W_EMIT
    pop  bc
    djnz .printloop
    ret

; ============================================================================
; F. ( f -- )
; ============================================================================
H_FDOT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "F", "."
W_FDOT:
    call FPOP
    push af                    ; stash the exponent across F_UMUL32
                               ; below (which destroys AF/BC/DE/HL) --
                               ; safe, symmetric push/pop within this
                               ; one routine's own body
    ld   a, h
    and  $80
    ld   (F_MSIGN), a
    call MATH_ABS16             ; hl = abs(mantissa)
    ex   de, hl                 ; de = abs(mantissa)
    ld   bc, 10000
    call F_UMUL32                ; F_PROD_HI:F_PROD_LO = abs(mantissa)*10000
    pop  af                      ; a = exponent
    or   a                       ; re-test its sign -- POP AF restored
                                 ; whatever flags were pushed, not
                                 ; flags reflecting A's current value
    jp   p, .shift_left
    neg
    ld   b, a
    call F_SHIFT32_RIGHT
    jr   .scaled
.shift_left:
    ld   b, a
    call F_SHIFT32_LEFT
.scaled:
    ld   a, (F_MSIGN)
    or   a
    jr   z, .nosign
    ld   hl, "-"
    call DPUSH_HL
    call W_EMIT
.nosign:
    ld   hl, (F_PROD_HI)
    ld   (F_DIVID_HI), hl
    ld   hl, (F_PROD_LO)
    ld   (F_DIVID_LO), hl
    ld   bc, 10000
    call F_UDIV32BY16             ; F_PROD_HI:F_PROD_LO = integer part
                                  ; (quotient); F_DIV_REM = fractional
                                  ; part, 0-9999 (the remainder)

    ld   hl, (F_PROD_LO)          ; the integer part -- realistically
    call PRINT_UDEC16             ; always fits in 16 bits for this
                                  ; project's floats; F_PROD_HI isn't
                                  ; checked (documented limit, not
                                  ; guarded, matching this project's
                                  ; standing "no error recovery" scope)
    ld   hl, "."
    call DPUSH_HL
    call W_EMIT
    ld   hl, (F_DIV_REM)
    call PRINT_UDEC16_PAD4
    ld   hl, " "
    call DPUSH_HL
    call W_EMIT
    ret

DICT_LATEST_INIT_FLOATPRINT EQU H_FDOT   ; head of the dictionary once
                                          ; this file's own word is
                                          ; included

    ENDIF
