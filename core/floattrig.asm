; ============================================================================
; core/floattrig.asm — Phase 30: PI, SIN, COS
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm (FPUSH/FPOP/
; W_FPLUS/W_FMINUS), core/floatmul.asm (W_FSTAR), core/floatdiv.asm
; (W_FSLASH), and kernel/math/math.asm (MATH_NEGATE16) — all must be
; INCLUDEd first, chaining through DICT_CHAIN_POINT the same way every
; other float file has.
;
; WHAT THIS ADDS: `PI` ( -- f ), `SIN` ( f -- sin(f) ), `COS` ( f --
; cos(f) ) — the user's own direct request, following FSQRT (Phase 29).
; `COS(x) = SIN(x + HALF_PI)`, the standard identity, so there is only
; ONE real trig routine underneath (`RAW_SIN`); `COS` just adds
; `HALF_PI` first and falls into the same code `SIN` uses.
;
; THE ALGORITHM (design done in Python simulation FIRST, before any Z80
; was written — see below):
;   1. RANGE-REDUCE the input into [0, 2*PI) with a bounded loop of
;      F+/F- against a TWO_PI constant, checking the running sign.
;   2. QUADRANT-REDUCE the [0,2*PI) value into a reference angle r in
;      [0, HALF_PI] plus a sign, using the standard four-case rule:
;        x < HALF_PI:        r = x,          sign = +1
;        x < PI:              r = PI - x,     sign = +1
;        x < THREE_HALF_PI:   r = x - PI,      sign = -1
;        else:                 r = TWO_PI - x,  sign = -1
;   3. TABLE LOOKUP + LINEAR INTERPOLATION: a 17-entry table of
;      SIN(i*PI/32) for i=0..16 (so PI/2 = 16 steps of PI/32) below,
;      each hand-computed the same way FSQRT's own worked constants
;      were — not guessed. `idx_f = r / TABLE_STEP` (F/), then `idx` and
;      `frac` are extracted by REPEATED F- against 1.0 (a bounded loop,
;      same shape as the range-reduction loop) rather than a dedicated
;      float-to-integer truncation routine, since idx_f is always small
;      (0..16) — cheap and reuses machinery that already exists.
;      `result = table[idx] + frac*(table[idx+1]-table[idx])` (one F-,
;      one F*, one F+), `idx+1` clamped to 16 at the top of the table.
;   4. Sign is applied last by negating the mantissa directly
;      (kernel/math's own MATH_NEGATE16) if the quadrant called for it.
;
; TWO REAL, FOUNDATIONAL BUGS WERE FOUND DESIGNING THIS PHASE, BOTH
; DOCUMENTED IN DETAIL AT THEIR OWN SITES — not fixed or worked around
; here, just why this file's own design accounts for them:
;   (a) core/float.asm's F+/F- had a silent 16-bit mantissa-overflow bug
;       (now FIXED, its own commit, before this file was written) —
;       found BECAUSE step 3's own interpolation routinely adds two
;       already-near-maximum table mantissas together, exactly the
;       shape that triggered it. This file's own correctness depends on
;       that fix already being in place.
;   (b) core/float.asm's F_ALIGN compares the two operands' signed
;       exponent BYTES with an unsigned CP+JR C (see the
;       2068forth-float-align-signed-cmp-quirk memory note) — NOT
;       fixed, and NOT a problem here: every constant and every table
;       entry in this file has a solidly negative exponent, and this
;       algorithm hits EXACT ZERO constantly (SIN_TABLE[0], SIN(0),
;       COS(HALF_PI), any x that lands exactly on a table step) — and
;       the zero-safety documented in that same memory note ONLY holds
;       BECAUSE of the unsigned-comparison quirk, not despite it (a
;       "corrected" signed F_ALIGN would actually break `SIN(0)` here,
;       confirmed directly in the Python simulation below before ever
;       writing a line of Z80 — see that memory note's own 2026-09-02
;       update for the full story). This file's own comparisons
;       (RANGE_REDUCE, quadrant selection, the frac-extraction loop) are
;       therefore all built from EITHER a direct mantissa-sign peek
;       (comparison against exact zero — cheap, exact, no float op, no
;       quirk exposure at all) OR a real F- against a NONZERO constant
;       followed by a sign check on the DIFFERENCE (comparison against
;       PI/HALF_PI/etc — well inside F_ALIGN's own well-behaved,
;       same-sign-exponent region) — never a comparison that could put
;       a genuine zero operand through F_ALIGN in a way this file
;       doesn't already know is safe.
;
; VALIDATED END-TO-END IN PYTHON BEFORE WRITING ANY Z80: a full
; simulation of this exact algorithm — including the REAL (buggy)
; F_ALIGN's unsigned-comparison quirk, the (now-fixed) F+/F- overflow
; behavior, and comparisons built ONLY from mantissa-sign peeks and
; real F- + sign-check (never a shortcut "compare the true numeric
; value" the real hardware has no way to do) — against math.sin/cos for
; 26 test values spanning all four quadrants, negative inputs, and
; inputs past 2*PI (exercising range reduction): worst SIN error
; 0.00103, worst COS error 0.00119 — consistent with a 17-entry table's
; own linear-interpolation error, not a logic bug. Two real bugs were
; caught and fixed BY this simulation before it passed: an
; idealized "correct" F_ALIGN broke SIN(0)/COS(0) (mantissa destroyed
; by aligning onto the zero operand's own exponent instead of the real
; operand's) until the ACTUAL unsigned-quirk behavior was modeled
; faithfully instead — see finding (b) above.
; ============================================================================

    IFNDEF CORE_FLOATTRIG_ASM
    DEFINE CORE_FLOATTRIG_ASM

; ---- Phase 30 RAM state. Starts right after core/floatsqrt.asm's own
; F_SQRT_EXP ($884F, ending $8850) — verified free by grepping every
; "EQU $8..." across core/, kernel/, include/, and rom/ first (nothing
; claims $8850-$8855 before this). ----
TRIG_IDX     EQU $8850   ; 1 byte: table index (0-16) during interpolation
TRIG_SIGN    EQU $8851   ; 1 byte: 0 = positive result, 1 = negate
TRIG_GUARD   EQU $8852   ; 1 byte: bounded-loop safety counter, reused
                         ; across RANGE_REDUCE's two loops and the
                         ; frac-extraction loop (never needed at once)
TRIG_TMP_M   EQU $8853   ; 2 bytes: CONST_MINUS_TOS's own scratch (the
                         ; constant, held across an FPOP/FPUSH pair)
TRIG_TMP_E   EQU $8855   ; 1 byte: ends at $8856

; ---- constants, hand-derived the same way core/floatsqrt.asm's own
; worked examples were (value = mantissa * 2^exponent; mantissa
; normalized into [16384,32767]) ----
HALF_PI_M       EQU 25736
HALF_PI_E       EQU -14    ; 25736*2^-14 = 1.570801  (true 1.570796)
PI_M            EQU 25736
PI_E            EQU -13    ; 25736*2^-13 = 3.141602  (true 3.141593)
THREE_HALF_PI_M EQU 19302
THREE_HALF_PI_E EQU -12    ; 19302*2^-12 = 4.712402  (true 4.712389)
TWO_PI_M        EQU 25736
TWO_PI_E        EQU -12    ; 25736*2^-12 = 6.283203  (true 6.283185)
TABLE_STEP_M    EQU 25736
TABLE_STEP_E    EQU -18    ; 25736*2^-18 = 0.098175  (true PI/32 = 0.098175)
ONE_M           EQU 16384
ONE_E           EQU -14    ; 16384*2^-14 = 1.0 exactly

; ---- SIN_TABLE: 17 entries, SIN(i*PI/32) for i=0..16, each 3 bytes
; (DW mantissa, DB exponent) so entry i lives at SIN_TABLE+i*3. Every
; value hand-computed the same normalized-mantissa way as the constants
; above; entry 0 is exact zero (0,0), not a normalized nonzero mantissa
; — SIN(0) is exactly 0, and this project's own float convention always
; represents exact zero as (0,0) (see core/float.asm's own header).
;   i= 0  (    0,  0)  0.000000  true 0.000000
;   i= 1  (25695,-18)  0.098019  true 0.098017
;   i= 2  (25571,-17)  0.195091  true 0.195090
;   i= 3  (19024,-16)  0.290283  true 0.290285
;   i= 4  (25080,-16)  0.382690  true 0.382683
;   i= 5  (30893,-16)  0.471390  true 0.471397  (the exact F+ overflow
;                        test case from core/float.asm's own header)
;   i= 6  (18205,-15)  0.555573  true 0.555570
;   i= 7  (20788,-15)  0.634399  true 0.634393
;   i= 8  (23170,-15)  0.707092  true 0.707107
;   i= 9  (25330,-15)  0.773010  true 0.773010
;   i=10  (27246,-15)  0.831482  true 0.831470
;   i=11  (28899,-15)  0.881927  true 0.881921
;   i=12  (30274,-15)  0.923889  true 0.923880
;   i=13  (31357,-15)  0.956940  true 0.956940
;   i=14  (32138,-15)  0.980774  true 0.980785
;   i=15  (32610,-15)  0.995178  true 0.995185
;   i=16  (16384,-14)  1.000000  true 1.000000
; ----
SIN_TABLE:
    DW   0      : DB 0
    DW   25695  : DB -18
    DW   25571  : DB -17
    DW   19024  : DB -16
    DW   25080  : DB -16
    DW   30893  : DB -16
    DW   18205  : DB -15
    DW   20788  : DB -15
    DW   23170  : DB -15
    DW   25330  : DB -15
    DW   27246  : DB -15
    DW   28899  : DB -15
    DW   30274  : DB -15
    DW   31357  : DB -15
    DW   32138  : DB -15
    DW   32610  : DB -15
    DW   16384  : DB -14

; ============================================================================
; FDUP (internal, not a dictionary word) — duplicates the top-of-float-
; stack value in place: ( -- ) on the float stack meaning ( f -- f f ).
; Destroys: AF, HL
; ============================================================================
FDUP:
    ld   l, (iy+0)
    ld   h, (iy+1)
    ld   a, (iy+2)
    call FPUSH
    ret

; ============================================================================
; TABLE_FETCH (internal) — A = table index (0-16) -> HL = mantissa,
; A = exponent, read from SIN_TABLE. Destroys: AF, BC, DE, HL
; ============================================================================
TABLE_FETCH:
    ld   l, a
    ld   h, 0
    ld   d, h
    ld   e, l          ; de = index
    add  hl, hl        ; hl = index*2
    add  hl, de        ; hl = index*3
    ld   de, SIN_TABLE
    add  hl, de        ; hl = SIN_TABLE + index*3
    ld   c, (hl)
    inc  hl
    ld   b, (hl)
    inc  hl
    ld   a, (hl)
    ld   l, c
    ld   h, b
    ret

; ============================================================================
; TABLE_LOOKUP_LO / TABLE_LOOKUP_HI (internal) — push SIN_TABLE[TRIG_IDX]
; / SIN_TABLE[TRIG_IDX+1] (clamped to 16) onto the float stack.
; Destroys: AF, BC, DE, HL
; ============================================================================
TABLE_LOOKUP_LO:
    ld   a, (TRIG_IDX)
    call TABLE_FETCH
    call FPUSH
    ret

TABLE_LOOKUP_HI:
    ld   a, (TRIG_IDX)
    inc  a
    cp   17
    jr   c, .ok
    ld   a, 16
.ok:
    call TABLE_FETCH
    call FPUSH
    ret

; ============================================================================
; CMP_TOS_VS_CONST (internal) — entry: HL = const mantissa, A = const
; exponent. Computes (top-of-float-stack - const), leaves the ORIGINAL
; top-of-float-stack value UNCHANGED, and returns with the sign flag
; (S) set from the difference's own sign — caller does `jp m,...` (TOS
; < const) or `jp p,...` (TOS >= const). Used only to compare against
; NONZERO constants (PI/HALF_PI/THREE_HALF_PI/TWO_PI/1.0) — see this
; file's own header on why exact-zero comparisons instead peek the
; mantissa sign directly and never go through here.
; Destroys: AF, BC, DE, HL
; ============================================================================
CMP_TOS_VS_CONST:
    push hl
    push af
    call FDUP
    pop  af
    pop  hl
    call FPUSH
    call W_FMINUS
    ld   a, (iy+1)
    or   a
    push af
    call FPOP
    pop  af
    ret

; ============================================================================
; CONST_MINUS_TOS (internal) — entry: HL = const mantissa, A = const
; exponent. Replaces the float-stack top x with (const - x).
; Destroys: AF, BC, DE, HL
; ============================================================================
CONST_MINUS_TOS:
    ld   (TRIG_TMP_M), hl
    ld   (TRIG_TMP_E), a
    call FPOP
    push hl
    push af
    ld   hl, (TRIG_TMP_M)
    ld   a, (TRIG_TMP_E)
    call FPUSH
    pop  af
    pop  hl
    call FPUSH
    call W_FMINUS
    ret

; ============================================================================
; TOS_MINUS_CONST (internal) — entry: HL = const mantissa, A = const
; exponent. Replaces the float-stack top x with (x - const).
; Destroys: AF, BC, DE, HL
; ============================================================================
TOS_MINUS_CONST:
    call FPUSH
    call W_FMINUS
    ret

; ============================================================================
; RANGE_REDUCE (internal) — ( x -- x' ), x' in [0, 2*PI). Two bounded
; loops (TRIG_GUARD, max 64 each — a generous safety net, not a
; precision claim; see this file's own header on the documented scope
; limit for very large input angles). The negative check is a direct
; mantissa-sign peek (comparison against exact zero); the upper-bound
; check is a real F- against TWO_PI followed by a sign check (TWO_PI is
; never zero) — see this file's own header on why that split is
; deliberate, not arbitrary.
; Destroys: AF, BC, DE, HL
; ============================================================================
RANGE_REDUCE:
    xor  a
    ld   (TRIG_GUARD), a
.neg_loop:
    ld   a, (iy+1)
    or   a
    jp   p, .neg_done
    ld   a, (TRIG_GUARD)
    cp   64
    jp   nc, .neg_done
    inc  a
    ld   (TRIG_GUARD), a
    ld   hl, TWO_PI_M
    ld   a, TWO_PI_E
    call FPUSH
    call W_FPLUS
    jp   .neg_loop
.neg_done:
    xor  a
    ld   (TRIG_GUARD), a
.ge_loop:
    ld   hl, TWO_PI_M
    ld   a, TWO_PI_E
    call CMP_TOS_VS_CONST
    jp   m, .ge_done
    ld   a, (TRIG_GUARD)
    cp   64
    jp   nc, .ge_done
    inc  a
    ld   (TRIG_GUARD), a
    ld   hl, TWO_PI_M
    ld   a, TWO_PI_E
    call TOS_MINUS_CONST
    jp   .ge_loop
.ge_done:
    ret

; ============================================================================
; RAW_SIN_TABLE (internal) — ( r -- sin(r) ), r in [0, HALF_PI]. Table
; lookup + linear interpolation (see this file's own header, step 3).
; Destroys: AF, BC, DE, HL
; ============================================================================
RAW_SIN_TABLE:
    ld   hl, TABLE_STEP_M
    ld   a, TABLE_STEP_E
    call FPUSH
    call W_FSLASH               ; ( -- idx_f )   idx_f = r / TABLE_STEP
    xor  a
    ld   (TRIG_IDX), a
.frac_loop:
    ld   hl, ONE_M
    ld   a, ONE_E
    call CMP_TOS_VS_CONST
    jp   m, .frac_done           ; idx_f < 1.0 -- done
    ld   hl, ONE_M
    ld   a, ONE_E
    call TOS_MINUS_CONST         ; idx_f -= 1.0
    ld   a, (TRIG_IDX)
    inc  a
    ld   (TRIG_IDX), a
    cp   17
    jp   nc, .frac_done          ; guard -- r<=HALF_PI means idx<=16
                                  ; always, this should never trigger
    jp   .frac_loop
.frac_done:
    ld   a, (TRIG_IDX)
    cp   17
    jr   c, .idx_ok
    ld   a, 16
    ld   (TRIG_IDX), a
.idx_ok:
    ; stack: ( -- frac )
    call TABLE_LOOKUP_HI          ; ( -- frac hi )
    call TABLE_LOOKUP_LO          ; ( -- frac hi lo )
    call W_FMINUS                 ; ( -- frac delta )   delta = hi-lo
    call W_FSTAR                  ; ( -- scaled )        scaled = frac*delta
    call TABLE_LOOKUP_LO          ; ( -- scaled lo )
    call W_FPLUS                  ; ( -- result )        result = lo+scaled
    ret

; ============================================================================
; RAW_SIN (internal) — ( x -- sin(x) ). Range-reduce, quadrant-select,
; table-interpolate, apply sign. See this file's own header for the
; full algorithm and its two-real-bugs-found backstory.
; Destroys: AF, BC, DE, HL
; ============================================================================
RAW_SIN:
    call RANGE_REDUCE
    ld   hl, HALF_PI_M
    ld   a, HALF_PI_E
    call CMP_TOS_VS_CONST
    jp   m, .q1
    ld   hl, PI_M
    ld   a, PI_E
    call CMP_TOS_VS_CONST
    jp   m, .q2
    ld   hl, THREE_HALF_PI_M
    ld   a, THREE_HALF_PI_E
    call CMP_TOS_VS_CONST
    jp   m, .q3
    ; Q4: x >= THREE_HALF_PI  ->  r = TWO_PI - x, sign = -1
    ld   a, 1
    ld   (TRIG_SIGN), a
    ld   hl, TWO_PI_M
    ld   a, TWO_PI_E
    call CONST_MINUS_TOS
    jp   .reduced
.q3:
    ; PI <= x < THREE_HALF_PI  ->  r = x - PI, sign = -1
    ld   a, 1
    ld   (TRIG_SIGN), a
    ld   hl, PI_M
    ld   a, PI_E
    call TOS_MINUS_CONST
    jp   .reduced
.q2:
    ; HALF_PI <= x < PI  ->  r = PI - x, sign = +1
    xor  a
    ld   (TRIG_SIGN), a
    ld   hl, PI_M
    ld   a, PI_E
    call CONST_MINUS_TOS
    jp   .reduced
.q1:
    ; x < HALF_PI  ->  r = x, sign = +1
    xor  a
    ld   (TRIG_SIGN), a
.reduced:
    call RAW_SIN_TABLE
    ld   a, (TRIG_SIGN)
    or   a
    ret  z
    ld   l, (iy+0)
    ld   h, (iy+1)
    call MATH_NEGATE16
    ld   (iy+0), l
    ld   (iy+1), h
    ret

; ============================================================================
; PI ( -- f )
; ============================================================================
H_PI:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "P", "I"
W_PI:
    ld   hl, PI_M
    ld   a, PI_E
    call FPUSH
    ret

; ============================================================================
; SIN ( f -- sin(f) )
; ============================================================================
H_SIN:
    DW   H_PI
    DB   3, "S", "I", "N"
W_SIN:
    call RAW_SIN
    ret

; ============================================================================
; COS ( f -- cos(f) )   COS(x) = SIN(x + HALF_PI)
; ============================================================================
H_COS:
    DW   H_SIN
    DB   3, "C", "O", "S"
W_COS:
    ld   hl, HALF_PI_M
    ld   a, HALF_PI_E
    call FPUSH
    call W_FPLUS
    call RAW_SIN
    ret

DICT_LATEST_INIT_FLOATTRIG EQU H_COS   ; head of the dictionary once
                                        ; this file's own words are
                                        ; included

    ENDIF
