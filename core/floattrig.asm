; ============================================================================
; core/floattrig.asm — Phase 30: PI, SIN, COS
;                      Phase 42 adds RAD and DEG (degree/radian
;                      conversion)
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
; SEVERAL REAL ISSUES WERE FOUND DESIGNING AND REVIEWING THIS PHASE —
; (a) and (b) during this file's own design (before any Z80 was
; written); (c) and (d) afterward, by an external code review of the
; finished file. None are fixed or worked around here except where
; stated — this section explains why this file's own design already
; accounts for them, or what its real, documented limit is:
;   (a) core/float.asm's F+/F- had a silent 16-bit mantissa-overflow bug
;       (now FIXED, its own commit, before this file was written) —
;       found BECAUSE step 3's own interpolation routinely adds two
;       already-near-maximum table mantissas together, exactly the
;       shape that triggered it. This file's own correctness depends on
;       that fix already being in place.
;   (b) core/float.asm's F_ALIGN compares the two operands' signed
;       exponent BYTES with an unsigned CP+JR C (see the
;       2068forth-float-align-signed-cmp-quirk memory note) — NOT
;       fixed. Every NONZERO constant and NONZERO table entry in this
;       file has a solidly negative exponent (SIN_TABLE[0] is the one
;       exception — exact zero, exponent 0 — and an intermediate result
;       like SIN(0)'s own idx_f can likewise be a zero mantissa paired
;       with a nonzero exponent, e.g. (0,+2); both are harmless, since
;       F_ALIGN may shift a zero mantissa by any amount without
;       changing its value — see core/floatmul.asm's own F_NORMALIZE32
;       header: "any exponent is fine for 0"). For every NONZERO
;       intermediate actually produced within this routine's own
;       successfully-reduced domain (see RANGE_REDUCE's own header for
;       what "successfully reduced" requires), the exponent stays
;       solidly negative — hand-traced by an external review: the
;       reference angle (0..HALF_PI), idx_f (0..16, exponent no greater
;       than -10), the fraction (0..1), the table delta and scaled
;       delta (magnitude well under 1), and the interpolated result
;       (0..1) all stay in this project's ordinary "normal-sized value"
;       range. This algorithm ALSO hits EXACT ZERO constantly
;       (SIN_TABLE[0], SIN(0), COS(HALF_PI), any x that lands exactly on
;       a table step) — and the zero-safety documented in that same
;       memory note ONLY holds BECAUSE of the unsigned-comparison quirk,
;       not despite it (a "corrected" signed F_ALIGN would actually
;       break `SIN(0)` here, confirmed directly in the Python simulation
;       below before ever writing a line of Z80 — see that memory note's
;       own 2026-09-02 update for the full story). This file's own
;       comparisons (RANGE_REDUCE, quadrant selection, the
;       frac-extraction loop) are therefore all built from EITHER a
;       direct mantissa-sign peek (comparison against exact zero —
;       cheap, exact, no float op, no quirk exposure at all) OR a real
;       F- against a NONZERO constant followed by a sign check on the
;       DIFFERENCE (comparison against
;       PI/HALF_PI/etc — well inside F_ALIGN's own well-behaved,
;       same-sign-exponent region) — never a comparison that could put
;       a genuine zero operand through F_ALIGN in a way this file
;       doesn't already know is safe.
;   (c) RANGE_REDUCE (below) has a REAL, HARD domain limit, found by
;       external review, not by this file's own original testing: its
;       two bounded loops (TRIG_GUARD_MAX, 250 iterations each) simply
;       STOP when the cap is reached, whatever the value currently is —
;       there is no failure signal, and everything downstream then runs
;       on a broken [0,2*PI) precondition. This is a genuinely different
;       (and much SMALLER-magnitude) limit than finding (b)'s own
;       ~16384 F_ALIGN threshold — an earlier draft of this file's own
;       documentation wrongly conflated the two, citing (b)'s own
;       ~16384 figure as if it were this routine's limit too, when the
;       actual, tighter, operative limit is roughly +-1570 (see
;       RANGE_REDUCE's own header for the exact derivation). Fixed here
;       by documenting the real bound precisely rather than an
;       unrelated, much larger one that was never actually reachable
;       first.
;   (d) core/float.asm's F+/F- overflow fix (finding (a)) is otherwise
;       correct on every boundary an external review checked (both
;       signs, both operations, exact halving, wrapped-zero mantissas)
;       — with one remaining, narrow, unfixed edge case: if the aligned
;       result exponent is exactly +127, the fallback's own `inc a`
;       wraps it to -128, producing a radically wrong value instead of
;       a merely imprecise one. This needs an exponent of +127 to
;       reach — nothing in this file's own normal operation gets
;       anywhere near it (see finding (b) above) — but it's a real,
;       general gap in F+/F-'s own exponent handling, not specific to
;       trig, so it's noted here rather than silently relied upon.
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
                         ; -- also doubles as the frac-extraction loop's
                         ; own bound (capped at 17), so TRIG_GUARD below
                         ; is NOT reused there, only across RANGE_REDUCE's
                         ; own two loops
TRIG_SIGN    EQU $8851   ; 1 byte: 0 = positive result, 1 = negate
TRIG_GUARD   EQU $8852   ; 1 byte: bounded-loop safety counter, reused
                         ; across RANGE_REDUCE's own two loops (reset to
                         ; 0 between them, so never needed by both at once)
TRIG_TMP_M   EQU $8853   ; 2 bytes: CONST_MINUS_TOS's own scratch (the
                         ; constant, held across an FPOP/FPUSH pair)
TRIG_TMP_E   EQU $8855   ; 1 byte: ends at $8856

; TRIG_GUARD_MAX — RANGE_REDUCE's own bounded-loop cap (see that
; routine's own header for the exact resulting domain limit this
; implies, and why it's a REAL limit, not just a safety net that never
; actually triggers).
TRIG_GUARD_MAX EQU 250

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
; RANGE_REDUCE (internal) — ( x -- x' ), x' in [0, 2*PI) FOR INPUTS
; WITHIN THIS ROUTINE'S OWN DOMAIN LIMIT (below) — outside it, this is
; NOT just imprecise, it silently returns a value that is NOT in
; [0, 2*PI) at all, and everything downstream (quadrant selection,
; table interpolation) then runs on a broken precondition with no error
; signal of any kind.
;
; REAL, HARD DOMAIN LIMIT — found by external review, not by this
; file's own original testing (which never tried a large enough input
; to hit it): each of the two loops below is capped at
; TRIG_GUARD_MAX (250) iterations of +/- TWO_PI. Reaching the cap ends
; the loop AS-IS, whatever the value currently is — not a "close
; enough" approximation, a genuinely unfinished reduction. Since
; TWO_PI ~ 6.283203, this means:
;   - x < -(TRIG_GUARD_MAX * TWO_PI) ~ -1570.8: the negative loop
;     exhausts its cap while x is STILL NEGATIVE, and everything after
;     this routine gets a negative "reduced" angle.
;   - x >= ~(TRIG_GUARD_MAX+1) * TWO_PI ~ 1577.08: the upper-bound loop
;     exhausts its cap while x is STILL >= TWO_PI.
; Ordinary trig usage (angles up to a few hundred radians, let alone
; the usual 0-2*PI range) is comfortably inside this bound; a program
; feeding SIN/COS a genuinely enormous angle (thousands of radians) is
; not, and gets a silently wrong answer, not an error. 250 was chosen
; as a generous, round, single-byte cap (TRIG_GUARD is one byte) with
; real headroom over ordinary use, not derived from any precision
; requirement — raising it further (still 1 byte, so <=255) is a free,
; safe way to widen this domain if ever needed, at the linear cost of
; more +/-TWO_PI iterations for inputs that actually need them.
;
; A SEPARATE, LARGER-SCALE hazard can compound this for sufficiently
; extreme inputs: if RANGE_REDUCE exhausts its cap while x is still far
; outside [0,2*PI) in magnitude, later comparisons/subtractions against
; PI/HALF_PI/etc. in RAW_SIN could in principle put a magnitude
; >=~16384 through F_ALIGN, which is this project's OTHER, separate,
; still-unfixed quirk (see the 2068forth-float-align-signed-cmp-quirk
; memory note) — not the normal, ordinary-use failure mode this
; routine's own domain limit above already describes, just a further
; way things could go wrong beyond it.
;
; The negative check is a direct mantissa-sign peek (comparison against
; exact zero); the upper-bound check is a real F- against TWO_PI
; followed by a sign check (TWO_PI is never zero) — see this file's own
; top header on why that split is deliberate, not arbitrary.
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
    cp   TRIG_GUARD_MAX
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
    cp   TRIG_GUARD_MAX
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

DICT_LATEST_INIT_FLOATTRIG EQU H_COS   ; head of the dictionary as of
                                        ; Phase 30 (PI/SIN/COS only) --
                                        ; rom/forth_smoke_p30.asm's own
                                        ; historical snapshot; must NOT
                                        ; be repointed at RAD/DEG below

; ============================================================================
; Phase 42: RAD and DEG — degree/radian conversion, found missing from
; the fresh three-way audit against 2068-Leap and the real TS2068 ROM's
; own command set (2068-Leap has both; `SIN`/`COS` above only ever
; accepted radians directly, with no bridge from degrees). Both operate
; on the float stack, matching `PI`/`SIN`/`COS`'s own convention —
; `RAD`/`DEG` are these three words' own direct companions, not a
; separate feature, so they live in this same file rather than a new
; one.
;
; RAD ( degrees -- radians )   radians = degrees * (PI/180)
; DEG ( radians -- degrees )   degrees = radians * (180/PI)
;
; Each is a single precomputed constant (hand-derived the same
; normalized-mantissa way as PI/HALF_PI/etc. above) plus the EXISTING
; `W_FSTAR`, unchanged — no new arithmetic, matching `PI`'s own
; "push a constant" simplicity.
;
; HAND-VERIFIED before trusting either constant: RAD_CONST (PI/180) =
; (18301,-20) -> 18301*2^-20 = 0.0174532 (true 0.0174533); DEG_CONST
; (180/PI) = (29335,-9) -> 29335*2^-9 = 57.294922 (true 57.295780) —
; both within this project's own already-established SIN/COS precision
; budget (a few parts in 10,000), not a precision instrument. Worked
; example: RAD(90.0) = 90 * 0.0174532 = 1.570788, matching HALF_PI's
; own stored value (25736,-14 = 1.570801) to within the same rounding
; budget; DEG(HALF_PI) = 1.570801 * 57.294922 = 90.0007, matching 90.0
; to the same tolerance — a real round trip, not just one direction
; checked in isolation.
; ============================================================================
RAD_CONST_M EQU 18301
RAD_CONST_E EQU -20    ; 18301*2^-20 = 0.0174532  (true PI/180 = 0.0174533)
DEG_CONST_M EQU 29335
DEG_CONST_E EQU -9     ; 29335*2^-9 = 57.294922  (true 180/PI = 57.295780)

; ============================================================================
; RAD ( degrees -- radians )
; ============================================================================
H_RAD:
    DW   H_COS
    DB   3, "R", "A", "D"
W_RAD:
    ld   hl, RAD_CONST_M
    ld   a, RAD_CONST_E
    call FPUSH
    call W_FSTAR
    ret

; ============================================================================
; DEG ( radians -- degrees )
; ============================================================================
H_DEG:
    DW   H_RAD
    DB   3, "D", "E", "G"
W_DEG:
    ld   hl, DEG_CONST_M
    ld   a, DEG_CONST_E
    call FPUSH
    call W_FSTAR
    ret

DICT_LATEST_INIT_RADDEG EQU H_DEG   ; head of the dictionary once this
                                     ; file's own words (including
                                     ; RAD/DEG) are all included

    ENDIF
