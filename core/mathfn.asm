; ============================================================================
; core/mathfn.asm — Phase 25: integer math functions (ABS, SGN, MOD,
; SQRT, RND, RANDOMIZE); Phase 54 added *, / (plain integer multiply
; and divide)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as every other core/ file) AND kernel/math/math.asm
; (already INCLUDEd by every ROM in this project for other reasons —
; see rom/forth_boot.asm's own INCLUDE list).
;
; WHAT THIS ADDS — a real gap found by a direct audit of 2068-Leap's own
; BASIC ROM (`~/ts2068rom`) against this project's dictionary: BASIC's
; ABS/SGN/MOD/SQR/RND/RANDOMISE had no Forth equivalent at all. Every
; one of these is a THIN WRAPPER around an already-existing,
; already-verified kernel/math/math.asm routine — no new algorithm
; written here, matching this project's own established practice of
; reusing kernel/ primitives rather than reinventing them (core/
; ts2068.asm's own PLOT/LINE/CIRCLE/BEEP do the identical thing for
; kernel/graphics/kernel/sound). See each kernel routine's own header
; in kernel/math/math.asm for the real algorithm, verification history,
; and edge-case behavior (e.g. ABS(-32768) stays -32768; MOD's
; remainder takes the DIVIDEND's sign; RND(x) seeds itself from the Z80
; R register the first time it's ever called; divide/mod-by-zero
; return 0, no error signal) — none of that is repeated here.
;
;   ABS        ( n -- |n| )              MATH_ABS16
;   SGN        ( n -- -1|0|1 )           MATH_SGN16
;   MOD        ( a b -- a mod b )        MATH_MOD16
;   SQRT       ( n -- isqrt(n) )         MATH_SQRT16 (integer square
;              root, truncating; BASIC's own SQR operates on its float
;              type instead — see core/floatsqrt.asm, a later phase,
;              for the float version)
;   RND        ( x -- n )                MATH_RND16 -- n in [0, x-1]
;              for a positive x, matching BASIC's own RND(x) convention
;   RANDOMIZE  ( n -- )                  MATH_RND_SEED -- n=0 resets to
;              "reseed from R on next RND", matching BASIC's own
;              RANDOMISE 0
;
; All six operate on the plain INTEGER data stack (IX) — this project's
; float stack (IY) has its own, separate `F+`/`F-`/`F*`/`F/` words
; (core/float.asm etc.) by deliberate design (see docs/numeric_model.md);
; these six mirror kernel/math's own integer-only scope, not an
; oversight.
; ============================================================================

    IFNDEF CORE_MATHFN_ASM
    DEFINE CORE_MATHFN_ASM

; ============================================================================
; ABS ( n -- |n| )
; ============================================================================
H_ABS:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "A", "B", "S"
W_ABS:
    call DPOP_HL
    call MATH_ABS16
    call DPUSH_HL
    ret

; ============================================================================
; SGN ( n -- -1|0|1 )
; ============================================================================
H_SGN:
    DW   H_ABS
    DB   3, "S", "G", "N"
W_SGN:
    call DPOP_HL
    call MATH_SGN16
    call DPUSH_HL
    ret

; ============================================================================
; MOD ( a b -- a-mod-b )
; ============================================================================
H_MOD:
    DW   H_SGN
    DB   3, "M", "O", "D"
W_MOD:
    call DPOP_HL           ; hl = b (divisor)
    ex   de, hl             ; de = b
    call DPOP_HL             ; hl = a (dividend)
    call MATH_MOD16
    call DPUSH_HL
    ret

; ============================================================================
; SQRT ( n -- isqrt(n) )
; ============================================================================
H_SQRT:
    DW   H_MOD
    DB   4, "S", "Q", "R", "T"
W_SQRT:
    call DPOP_HL
    call MATH_SQRT16
    call DPUSH_HL
    ret

; ============================================================================
; RND ( x -- n )
; ============================================================================
H_RND:
    DW   H_SQRT
    DB   3, "R", "N", "D"
W_RND:
    call DPOP_HL
    call MATH_RND16
    call DPUSH_HL
    ret

; ============================================================================
; RANDOMIZE ( n -- )
; ============================================================================
H_RANDOMIZE:
    DW   H_RND
    DB   9, "R", "A", "N", "D", "O", "M", "I", "Z", "E"
W_RANDOMIZE:
    call DPOP_HL
    call MATH_RND_SEED
    ret

; ============================================================================
; * ( a b -- a*b )  Phase 54: thin wrapper around
; kernel/math/math.asm's own MATH_MULTIPLY16 — same signed,
; 16-bit-truncated-result contract as that routine's own header
; documents (verified there via 32,720 Python-simulated cases, not
; re-verified here).
; ============================================================================
H_STAR:
    DW   H_RANDOMIZE
    DB   1, "*"
W_STAR:
    call DPOP_HL           ; hl = b
    ex   de, hl             ; de = b
    call DPOP_HL             ; hl = a
    call MATH_MULTIPLY16      ; hl = a*b
    call DPUSH_HL
    ret

; ============================================================================
; / ( a b -- a/b )  Phase 54: thin wrapper around
; kernel/math/math.asm's own MATH_DIVIDE16 — truncates toward zero;
; b=0 returns 0 (no error signal), matching MOD's own divide-by-zero
; behavior above since both share the same underlying MATH_UDIV16.
; ============================================================================
H_SLASH:
    DW   H_STAR
    DB   1, "/"
W_SLASH:
    call DPOP_HL           ; hl = b (divisor)
    ex   de, hl             ; de = b
    call DPOP_HL             ; hl = a (dividend)
    call MATH_DIVIDE16        ; hl = a/b, truncated toward zero
    call DPUSH_HL
    ret

DICT_LATEST_INIT_MATHFN EQU H_SLASH       ; head of the dictionary once
                                           ; this file's own words are
                                           ; included

    ENDIF
