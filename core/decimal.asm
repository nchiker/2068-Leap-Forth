; ============================================================================
; core/decimal.asm — Phase 23: decimal number literals
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm,
; core/floatmul.asm, AND core/floatdiv.asm (all must be INCLUDEd
; first — this file's own routines are called from inside
; core/interp.asm's own NUMBER/INTERPRET_RUN, gated behind
; `DECIMAL_NUMBER_ENABLED`, defined below). Reuses
; core/floatdiv.asm's own F_UDIV32BY16 and core/floatmul.asm's own
; F_NORMALIZE32/F_PROD_HI/F_PROD_LO completely unchanged.
;
; WHAT THIS ADDS: typing a decimal number literal (e.g. `3.5`) now
; pushes a real float onto the float stack, the same way typing a
; plain integer pushes one onto the data stack — completing the
; "decimal number literal parsing" gap that's kept every `F+`/`F-`/
; `F*`/`F/`/`F.` word (Phases 8/18/19/22) reachable only by feeding the
; float stack directly via FPUSH, never by typing an expression.
;
; ============================================================================
; HOW THIS HOOKS INTO core/interp.asm WITHOUT RISKING EVERY OTHER ROM
; IN THE PROJECT: core/interp.asm is INCLUDEd by every single smoke ROM
; and rom/forth_boot.asm — the single most shared file here. Rather
; than changing its NUMBER/INTERPRET_RUN unconditionally, both call
; sites are wrapped in `IFDEF DECIMAL_NUMBER_ENABLED` / `ENDIF`. The
; including ROM must `DEFINE DECIMAL_NUMBER_ENABLED` BEFORE INCLUDEing
; core/interp.asm to opt in. Any ROM that doesn't (every existing
; smoke ROM, unchanged) gets core/interp.asm's compiled bytes
; byte-for-byte IDENTICAL to before this phase — confirmed directly,
; not just reasoned about, by re-assembling rom/forth_smoke_p3.asm
; (which doesn't even INCLUDE core/float.asm, so an ungated reference
; to a float routine from dead code would have been a hard assembly
; error, not just an unreachable branch) and diffing its output binary
; before and after this change: identical.
;
; THE ALGORITHM, hand-verified against two cases before ever assembling
; any of it:
;   1. Accumulate the token's digits into one running integer,
;      ignoring the decimal point itself but counting how many digits
;      followed it (FRAC_DIGITS) — the exact same *10+digit technique
;      core/interp.asm's own NUMBER already uses for plain integers,
;      just with the dot skipped over instead of rejected.
;   2. Compute 10^FRAC_DIGITS.
;   3. Widen the integer by 2^16 (place it in the high word of a
;      32-bit value, zero in the low word) and divide by 10^FRAC_DIGITS
;      via core/floatdiv.asm's own F_UDIV32BY16 — this is exactly F/'s
;      own "scale the dividend up, then divide" trick, reused verbatim
;      because it's solving the identical problem: converting a ratio
;      into a well-scaled fixed-point value without losing precision
;      to premature truncation.
;   4. Normalize the 32-bit quotient via core/floatmul.asm's own
;      F_NORMALIZE32 (also reused unchanged) to get a clean 15-bit
;      mantissa magnitude and a shift correction.
;   5. Final exponent = F_NORM_SHIFT - 16 (compensating for step 3's
;      own +16 scale-up, the same -16 term F/ itself applies).
;
;   "3.5" -> digits accumulate to 35, FRAC_DIGITS=1; divisor=10;
;     widened dividend = 35*65536 = 2293760; /10 = 229376 exactly;
;     F_NORMALIZE32 shrinks it 3 times to mantissa 28672; final
;     exponent = 3-16 = -13; 28672*2^-13 = 3.5 exactly.
;   "0.25" -> digits accumulate to 25, FRAC_DIGITS=2; divisor=100;
;     widened dividend = 25*65536 = 1638400; /100 = 16384 exactly
;     (already normalized, F_NORM_SHIFT=0); final exponent = 0-16=-16;
;     16384*2^-16 = 0.25 exactly — the SAME (mantissa, exponent) pair
;     already used by hand in rom/forth_smoke_p18.asm/p19.asm/p22.asm's
;     own "0.25" test cases, a real cross-check that this parser
;     produces the same internal representation a human already picked
;     by hand for the same value.
; ============================================================================

    IFNDEF CORE_DECIMAL_ASM
    DEFINE CORE_DECIMAL_ASM

; ---- Phase 23 RAM state — same probe-verified $8426-$8FFF gap as
; every other core/ file's own scratch. Placed right after
; core/floatdiv.asm's own F_DIV_REM ($87B9, 2 bytes -> ends at
; $87BA). ----
FRAC_DIGITS EQU $87BB   ; 1 byte: count of digits seen after the '.'
SEEN_DOT    EQU $87BC   ; 1 byte: 0 until the '.' is consumed, then 1
DIVISOR10   EQU $87BD   ; 2 bytes: 10^FRAC_DIGITS, computed once digit
                        ; scanning finishes

; ============================================================================
; CHECK_FOR_DOT (internal) — non-destructively scans NUM_COUNT
; characters starting at NUM_PTR (core/interp.asm's own NUMBER
; scratch, already populated by the time this is called) for a '.'.
; Out: A = 1 if found, 0 if not. Does not modify NUM_PTR/NUM_COUNT —
; NUMBER's own existing integer-parsing code must see them completely
; unchanged if no dot is found.
; Destroys: AF, BC, HL
; ============================================================================
CHECK_FOR_DOT:
    ld   hl, (NUM_PTR)
    ld   a, (NUM_COUNT)
    ld   b, a
    or   a
    ret  z                     ; empty token -- no dot possible
.loop:
    ld   a, (hl)
    cp   "."
    jr   z, .found
    inc  hl
    djnz .loop
    xor  a
    ret
.found:
    ld   a, 1
    ret

; ============================================================================
; DECIMAL_PARSE_AND_PUSH (internal) — reached via NUMBER's own `jp`
; once CHECK_FOR_DOT confirms a '.' is present. Starts from NUM_PTR/
; NUM_COUNT exactly as NUMBER itself first set them (before NUMBER's
; own sign-stripping step, which this routine redoes independently
; since it never runs for a decimal token). Parses the whole token
; (sign, integer digits, the dot, fractional digits) and pushes the
; resulting float directly onto the float stack via FPUSH, then
; signals success to NUMBER's own caller with flag=2 on the data stack
; (matching NUMBER's own flag convention: 0=fail, 1=integer already on
; the data stack, 2=float already on the float stack, nothing on the
; data stack for it). Returns straight to INTERPRET_RUN — never back
; into NUMBER's own remaining integer-only code.
; ============================================================================
DECIMAL_PARSE_AND_PUSH:
    xor  a
    ld   (NUM_NEG), a
    ld   hl, (NUM_PTR)
    ld   a, (hl)
    cp   "-"
    jr   nz, .nosign
    ld   a, 1
    ld   (NUM_NEG), a
    inc  hl
    ld   (NUM_PTR), hl
    ld   a, (NUM_COUNT)
    dec  a
    ld   (NUM_COUNT), a
.nosign:
    ld   de, 0                  ; running magnitude, dot ignored
    xor  a
    ld   (FRAC_DIGITS), a
    ld   (SEEN_DOT), a
.digitloop:
    ld   a, (NUM_COUNT)
    or   a
    jr   z, .donedigits
    dec  a
    ld   (NUM_COUNT), a
    ld   hl, (NUM_PTR)
    ld   a, (hl)
    inc  hl
    ld   (NUM_PTR), hl
    cp   "."
    jr   nz, .notdot
    ld   a, 1
    ld   (SEEN_DOT), a
    jr   .digitloop
.notdot:
    cp   "0"
    jr   c, .fail                ; not a valid decimal number --
    cp   "9"+1                   ; NUMBER's own caller (INTERPRET_RUN)
    jr   nc, .fail                ; treats flag=0 as "try FIND failed,
                                  ; NUMBER failed too -- unknown word"
    sub  "0"
    ld   l, a
    ld   h, 0
    push hl                       ; save the digit
    ld   h, d
    ld   l, e                     ; hl = old magnitude
    add  hl, hl                   ; *2
    ld   b, h
    ld   c, l                     ; bc = magnitude*2
    add  hl, hl                   ; *4
    add  hl, hl                   ; *8
    add  hl, bc                   ; magnitude*10
    pop  bc                       ; bc = digit
    add  hl, bc                   ; + digit
    ex   de, hl                   ; de = new magnitude
    ld   a, (SEEN_DOT)
    or   a
    jr   z, .digitloop
    ld   a, (FRAC_DIGITS)
    inc  a
    ld   (FRAC_DIGITS), a
    jr   .digitloop
.donedigits:
    push de                        ; stash integer_value across the
                                   ; power-of-10 computation below
    ld   hl, 1
    ld   a, (FRAC_DIGITS)
    or   a
    jr   z, .havedivisor
    ld   c, a
.powloop:
    add  hl, hl                    ; hl*2
    ld   d, h
    ld   e, l                       ; de = hl*2
    add  hl, hl                     ; hl*4
    add  hl, hl                      ; hl*8
    add  hl, de                      ; hl*8 + hl*2 = hl*10
    dec  c
    jr   nz, .powloop
.havedivisor:
    ld   (DIVISOR10), hl
    pop  de                          ; de = integer_value again
    ld   (F_DIVID_HI), de
    ld   hl, 0
    ld   (F_DIVID_LO), hl            ; 32-bit dividend = integer_value << 16
    ld   hl, (DIVISOR10)
    ld   b, h
    ld   c, l
    call F_UDIV32BY16                 ; F_PROD_HI:F_PROD_LO = quotient
    call F_NORMALIZE32                 ; -> F_PROD_LO = mantissa
                                       ; magnitude, F_NORM_SHIFT set
    ld   a, (F_NORM_SHIFT)
    sub  16                            ; compensate for the *2^16
                                       ; scale-up above, same as F/
    push af                            ; stash the final exponent
    ld   hl, (F_PROD_LO)
    ld   a, (NUM_NEG)
    or   a
    jr   z, .dopositive
    call MATH_NEGATE16
.dopositive:
    pop  af                             ; a = final exponent
    call FPUSH
    ld   hl, 2                           ; flag=2: float, already pushed
    call DPUSH_HL
    ret
.fail:
    ld   hl, 0
    call DPUSH_HL
    ret

; ============================================================================
; DOFLIT (internal) — runtime half of a compiled decimal literal,
; exactly core/interp.asm's own DOLIT idiom widened from a 2-byte
; integer to a 3-byte float (2-byte mantissa + 1-byte exponent): reads
; those 3 bytes off its own return address, FPUSHes the float, then
; corrects the return address to skip past them before returning.
; ============================================================================
DOFLIT:
    pop  hl                    ; hl = address of the inline 3-byte
                               ; float literal
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                ; de = mantissa
    inc  hl
    ld   a, (hl)                 ; a = exponent
    inc  hl                       ; hl = real continuation address
    push hl
    push af
    ex   de, hl                   ; hl = mantissa
    pop  af                        ; a = exponent
    call FPUSH
    ret

; ============================================================================
; COMPILE_FLOAT_LITERAL ( HL = mantissa, A = exponent -- ) compiles a
; 6-byte inline float literal (CALL DOFLIT, then the 3-byte value) at
; HERE — core/interp.asm's own COMPILE_LITERAL, widened the same way
; DOFLIT widens DOLIT.
; ============================================================================
COMPILE_FLOAT_LITERAL:
    push af
    push hl
    ld   hl, DOFLIT
    call COMPILE_CALL
    pop  hl
    ld   de, (HERE)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    pop  af
    ld   (de), a
    inc  de
    ld   (HERE), de
    ret

    ENDIF
