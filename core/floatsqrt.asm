; ============================================================================
; core/floatsqrt.asm — Phase 29: FSQRT (float square root)
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm, AND
; core/floatmul.asm (all must be INCLUDEd first, floatmul.asm
; specifically — this file's own first header chains through
; DICT_CHAIN_POINT, and reuses floatmul.asm's own F_NORMALIZE32 AND
; its F_PROD_LO/F_PROD_HI scratch directly as this file's own internal
; "result accumulator," described below) and kernel/math/math.asm
; (needs nothing from it directly, but every ROM in this project
; already includes it).
;
; WHAT THIS ADDS: FSQRT ( f -- sqrt(f) ) — the float-side counterpart
; to Phase 25's own integer `SQRT`, following up on that phase's own
; "float versions of some of these... are a natural later addition"
; note. Negative input returns 0 (mantissa 0, exponent 0) — no error
; signal, matching kernel/math's own MATH_SQRT16 convention for a
; negative input exactly (and, transitively, Phase 25's own integer
; `SQRT`).
;
; THE ALGORITHM: value = M * 2^E (this project's own float
; representation — see core/float.asm's own header). We want
; sqrt(M * 2^E) = sqrt(M) * 2^(E/2), which only works cleanly when E is
; EVEN; when E is odd, first rewrite M * 2^E as (M*2) * 2^(E-1) — an
; exact, lossless rewrite (M is at most 32767, so M*2 is at most 65534,
; comfortably inside a 16-bit unsigned register) — making the new
; exponent even. From there, sqrt(M) itself is computed with far more
; precision than M's own ~15 bits would give directly by first scaling
; M up by exactly 2^16 (an exact power-of-2 scale, so it loses no
; precision, the same "widen before dividing" trick core/floatdiv.asm's
; own header describes for F/) into a 32-bit value, taking ITS integer
; square root with a new 32-bit-input, 16-bit-output routine
; (F_SQRT32, below — kernel/math's own MATH_SQRT16 widened exactly the
; way core/floatmul.asm's own F_UMUL32 widened MATH_UMUL16, and
; core/floatdiv.asm's own F_UDIV32BY16 widened MATH_UDIV16), then
; running THAT raw integer result through core/floatmul.asm's own
; F_NORMALIZE32 (reused unchanged) to land it in this project's usual
; "positive, close to the full 15-bit range" mantissa shape. Since
; sqrt(M * 2^16) = sqrt(M) * 2^8, the final exponent works out to
; (E/2) - 8 + F_NORM_SHIFT (F_NORM_SHIFT being F_NORMALIZE32's own
; correction, exactly as core/floatmul.asm/core/floatdiv.asm already
; use it). E/2 is a plain arithmetic right shift (Z80's SRA), exact
; because E is guaranteed even by this point — no rounding ambiguity.
;
; HAND-VERIFIED against three cases before trusting it, covering both
; the even- and odd-exponent paths and both an exact and an
; approximate result:
;   sqrt(4.0)=2.0: input (16384,-12) [see docs/numeric_model.md-style
;     normalized form: mantissa in [16384,32767]]. E=-12 is already
;     even. Widened input to F_SQRT32 = 16384*2^16 = $40000000;
;     F_SQRT32 gives exactly 32768 ($8000, a perfect square — this
;     exponent's own worked example is exact by construction).
;     F_NORMALIZE32 shrinks once to 16384, F_NORM_SHIFT=1. Final
;     exponent = -12/2 - 8 + 1 = -13. Result (16384,-13):
;     16384*2^-13 = 2.0 exactly.
;   sqrt(2.0)≈1.41421: input (16384,-13). E=-13 is odd, so M doubles to
;     32768 and E becomes -14. Widened input = 32768*2^16 = $80000000;
;     F_SQRT32 gives 46340 (floor of the true irrational root).
;     F_NORMALIZE32 shrinks once to 23170, F_NORM_SHIFT=1. Final
;     exponent = -14/2 - 8 + 1 = -14. Result (23170,-14):
;     23170*2^-14 ≈ 1.41418 — correctly close to the true
;     sqrt(2)=1.41421356..., off only by ordinary integer-sqrt
;     truncation, the same class of approximation this project's own
;     `SQRT` (Phase 25) already accepts.
;   sqrt(9.0)=3.0: input (18432,-11). E=-11 is odd, so M doubles to
;     36864 and E becomes -12. Widened input = 36864*2^16 = $90000000;
;     F_SQRT32 gives EXACTLY 49152 (36864*2^16 is a perfect square
;     here too: 49152^2 = 9*16384^2). F_NORMALIZE32 shrinks once to
;     24576, F_NORM_SHIFT=1. Final exponent = -12/2 - 8 + 1 = -13.
;     Result (24576,-13): 24576*2^-13 = 3.0 exactly.
; These three between them exercise the even-exponent path, the
; odd-exponent path twice (once exact, once approximate), and two
; independent exact perfect-square cases — not just one.
; ============================================================================

    IFNDEF CORE_FLOATSQRT_ASM
    DEFINE CORE_FLOATSQRT_ASM

; ---- Phase 29 RAM state. Placed at $8840, NOT immediately after
; core/input.asm's own FINPUT_BUF ($87F7-$87FE) the way every earlier
; phase's scratch followed the previous one — that next byte, $87FF,
; is one byte short of $8800, which every rom/forth_smoke_p*.asm file
; in this project informally treats as ITS OWN local scratch
; (CHECKPOINT_NUM and friends — see e.g. rom/forth_smoke_p28.asm).
; core/*.asm's own scratch has never needed to share that page before
; now (float.asm and doloop.asm's own long-simmering scratch grew
; large enough this phase to actually reach it), so this phase starts
; fresh at $8840 instead — comfortably past every existing smoke ROM's
; own local scratch (verified by grepping every existing "EQU $88.."
; across core/ and rom/ first: nothing claims past $8808), and
; comfortably below core/float.asm's own FSTACK_LIMIT ($8C00). ----
FSQ_OP_LO   EQU $8840   ; 2 bytes: F_SQRT32's own scratch (the
                        ; shrinking 32-bit "remaining value")
FSQ_OP_HI   EQU $8842   ; 2 bytes
FSQ_ONE_LO  EQU $8844   ; 2 bytes: F_SQRT32's own scratch (the
                        ; shrinking 32-bit "candidate bit weight" --
                        ; starts at 2^30, shrinks by 4 each pass)
FSQ_ONE_HI  EQU $8846   ; 2 bytes
FSQ_CAND_LO EQU $8848   ; 2 bytes: F_SQRT32's own scratch (res+one,
                        ; recomputed each pass)
FSQ_CAND_HI EQU $884A   ; 2 bytes
FSQ_DIFF_LO EQU $884C   ; 2 bytes: F_SQRT32's own scratch (op-candidate,
                        ; held here until the borrow outcome is known,
                        ; since the low word's own subtraction result
                        ; can't be committed to FSQ_OP_LO until the
                        ; high word's own SBC resolves whether this
                        ; pass's subtraction is kept at all)
FSQ_COUNTER EQU $884E   ; 1 byte: F_SQRT32's own loop counter
F_SQRT_EXP  EQU $884F   ; 1 byte: W_FSQRT's own scratch -- the
                        ; exponent, held here across the whole
                        ; computation since A gets reused for many
                        ; other things along the way -- ends at $8850

; ============================================================================
; F_SQRT32 (internal, not a dictionary word) — FSQ_OP_HI:FSQ_OP_LO
; (32-bit unsigned, caller-populated) -> core/floatmul.asm's own
; F_PROD_HI:F_PROD_LO = the integer square root (F_PROD_HI always ends
; up 0, since a 32-bit input's own root fits in 16 bits) -- landing the
; raw result exactly where F_NORMALIZE32 already expects its own input,
; the same handoff core/floatmul.asm's F_UMUL32 and
; core/floatdiv.asm's F_UDIV32BY16 already use it for. Classic "digit
; by digit" binary square root (see kernel/math/math.asm's own
; MATH_SQRT16 header for the algorithm's own name and shape), widened
; from a 16-bit input/8-iteration form to a 32-bit input/16-iteration
; one exactly the way core/floatmul.asm's own F_UMUL32 widened
; kernel/math's MATH_UMUL16, and core/floatdiv.asm's own F_UDIV32BY16
; widened MATH_UDIV16 -- the THIRD time this exact "take an
; already-proven 16-bit kernel/math routine and widen it the same way"
; move has been made in this project, not a new technique invented
; here.
; Destroys: AF, BC, DE, HL
; ============================================================================
F_SQRT32:
    ld   hl, 0
    ld   (F_PROD_LO), hl        ; res = 0 (core/floatmul.asm's own
    ld   (F_PROD_HI), hl        ; scratch, reused as this routine's
                                 ; own "res" -- see this file's header)
    ld   hl, 0
    ld   (FSQ_ONE_LO), hl
    ld   hl, $4000
    ld   (FSQ_ONE_HI), hl        ; one = $40000000 -- the highest even
                                  ; power of 4 fitting a 32-bit input
                                  ; (4^15 = 2^30), the same reasoning
                                  ; MATH_SQRT16's own header gives for
                                  ; its 16-bit "$4000" (4^7 = 2^14)
    ld   a, 16                    ; 32 bits / 2 bits extracted per pass
    ld   (FSQ_COUNTER), a
.loop:
    ; candidate = res + one
    ld   hl, (F_PROD_LO)
    ld   de, (FSQ_ONE_LO)
    add  hl, de
    ld   (FSQ_CAND_LO), hl
    ld   hl, (F_PROD_HI)
    ld   de, (FSQ_ONE_HI)
    adc  hl, de
    ld   (FSQ_CAND_HI), hl

    ; diff = op - candidate (unsigned 32-bit); borrow -> op < candidate
    ld   hl, (FSQ_OP_LO)
    ld   de, (FSQ_CAND_LO)
    or   a
    sbc  hl, de
    ld   (FSQ_DIFF_LO), hl
    ld   hl, (FSQ_OP_HI)
    ld   de, (FSQ_CAND_HI)
    sbc  hl, de
    jr   c, .no_commit           ; op < candidate this pass -- 0 bit,
                                  ; nothing to commit

    ; op >= candidate: commit the subtraction (hl already holds the
    ; correct new op-high from the SBC above) and add 2*one to res
    ld   (FSQ_OP_HI), hl
    ld   hl, (FSQ_DIFF_LO)
    ld   (FSQ_OP_LO), hl

    ld   hl, (F_PROD_LO)
    ld   de, (FSQ_ONE_LO)
    add  hl, de
    ld   (F_PROD_LO), hl
    ld   hl, (F_PROD_HI)
    ld   de, (FSQ_ONE_HI)
    adc  hl, de
    ld   (F_PROD_HI), hl

    ld   hl, (F_PROD_LO)
    ld   de, (FSQ_ONE_LO)
    add  hl, de
    ld   (F_PROD_LO), hl
    ld   hl, (F_PROD_HI)
    ld   de, (FSQ_ONE_HI)
    adc  hl, de
    ld   (F_PROD_HI), hl

.no_commit:
    ; res >>= 1 (32-bit logical shift, carry-chained high word into low)
    ld   hl, (F_PROD_HI)
    srl  h
    rr   l
    ld   (F_PROD_HI), hl
    ld   hl, (F_PROD_LO)
    rr   h
    rr   l
    ld   (F_PROD_LO), hl

    ; one >>= 2 (two carry-chained 32-bit shifts, same shape as above)
    ld   hl, (FSQ_ONE_HI)
    srl  h
    rr   l
    ld   (FSQ_ONE_HI), hl
    ld   hl, (FSQ_ONE_LO)
    rr   h
    rr   l
    ld   (FSQ_ONE_LO), hl

    ld   hl, (FSQ_ONE_HI)
    srl  h
    rr   l
    ld   (FSQ_ONE_HI), hl
    ld   hl, (FSQ_ONE_LO)
    rr   h
    rr   l
    ld   (FSQ_ONE_LO), hl

    ld   a, (FSQ_COUNTER)
    dec  a
    ld   (FSQ_COUNTER), a
    jp   nz, .loop                ; JP, not JR -- the loop body is too
                                   ; long for JR's +-127-byte range
                                   ; (caught by tools/check_z80_opcodes.py,
                                   ; not by running anything)
    ret

; ============================================================================
; FSQRT ( f -- sqrt(f) )
; ============================================================================
H_FSQRT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "F", "S", "Q", "R", "T"
W_FSQRT:
    call FPOP                 ; hl = mantissa, a = exponent
    ld   (F_SQRT_EXP), a
    ld   a, h
    or   a
    jp   m, .negative           ; sign bit of the mantissa set
    ld   a, h
    or   l
    jr   z, .zero                ; mantissa == 0

    ld   a, (F_SQRT_EXP)
    and  1
    jr   z, .even_exp
    add  hl, hl                   ; odd exponent: M *= 2 (exact, safe --
                                   ; see this file's own header)
    ld   a, (F_SQRT_EXP)
    dec  a
    ld   (F_SQRT_EXP), a
.even_exp:
    ld   (FSQ_OP_HI), hl            ; widen: 32-bit input = M * 2^16
    ld   hl, 0
    ld   (FSQ_OP_LO), hl
    call F_SQRT32                     ; -> F_PROD_HI:F_PROD_LO = isqrt
    call F_NORMALIZE32                  ; -> F_PROD_LO = normalized
                                         ; mantissa, F_NORM_SHIFT set
                                         ; (core/floatmul.asm)

    ld   a, (F_SQRT_EXP)
    sra  a                                ; /2 -- exact, E is even here
    sub  8                                 ; compensate the *2^16 widen
    ld   b, a
    ld   a, (F_NORM_SHIFT)
    add  a, b
    ld   (F_RESULT_EXP), a

    ld   hl, (F_PROD_LO)
    ld   a, (F_RESULT_EXP)
    call FPUSH
    ret
.negative:
.zero:
    ld   hl, 0                    ; safe default -- see this file's own
    xor  a                        ; header (matches kernel/math's own
    call FPUSH                    ; MATH_SQRT16 convention)
    ret

DICT_LATEST_INIT_FLOATSQRT EQU H_FSQRT   ; head of the dictionary once
                                           ; this file's own word is
                                           ; included

    ENDIF
