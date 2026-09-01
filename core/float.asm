; ============================================================================
; core/float.asm — Phase 8 (stretch goal): floating point
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — chains its own dictionary entries onto core/interp.asm's
; H_SEMICOLON). Needs nothing from kernel/ — this is pure arithmetic.
;
; DESIGN DECISION, made with the user directly before any code was
; written: this is a small, SELF-CONTAINED, native Forth float
; implementation, not a port of 2068-Leap's real rom/exrom_calc.asm
; calculator. That engine is the classic Sinclair RST $28 design: the
; caller does `RST $28` followed by an inline literal-bytecode stream,
; and the engine reads its own return address to find it. Porting it
; faithfully would also mean EXROM paging around every call (it's
; designed to live in a separate 8K bank), the real Sinclair
; float-literal bit encoding, and a bridge between its own calculator
; stack and this project's integer data stack — a multi-session
; undertaking, not a stretch-goal-sized first slice, and this project's
; own charter is explicit that 2068-Forth is free to diverge from
; 2068-Leap's conventions rather than stay compatible with them.
;
; THE FORMAT: NOT IEEE-754. Each float is 3 bytes: a 16-bit signed
; mantissa and an 8-bit signed exponent, value = mantissa * 2^exponent.
; No normalization, no implicit leading bit, no NaN/Infinity handling.
; This is deliberately the simplest representation that still needs a
; real alignment step to add two differently-scaled values correctly —
; enough to prove the mechanism, not a considered final numeric design.
; A real, known, stated limitation: shifting a mantissa to align
; exponents can silently lose low bits (ordinary floating-point
; rounding), and very different exponents can shift a mantissa to zero
; entirely. Neither is guarded against yet.
;
; A SEPARATE STACK: floats live on their own stack, addressed by IY
; (confirmed, by grepping the whole kernel/ and core/ tree, to be
; completely unused anywhere else in this project before this file —
; the same way IX was free for the integer data stack in Phase 2).
; Growing downward from FSTACK_TOP, one 3-byte cell per float, mirroring
; IX/DSTACK_TOP/core/dict.asm's own convention exactly. Placed just
; below DSTACK_LIMIT ($9000) so it can never collide with the integer
; stack even at full depth, and confirmed via the same $8426-$8FFF
; probe-verified empty range Phase 5 established — see that phase's
; own PROJECT_PLAN.md section for the method.
;
; SCOPE OF THIS FIRST SLICE: F+ and F- only, plus the FPUSH/FPOP
; plumbing a test harness (or a later phase) needs to get values onto
; and off of the float stack directly, since there is no float literal
; syntax yet — NUMBER (core/interp.asm) only parses signed integers.
; F* and F/ need a wider (32-bit) multiply this project's kernel/math
; doesn't have yet; F. (print) needs EMIT, which doesn't exist as a
; Forth word yet either (Phase 6's own scope note). Both are real
; follow-up work, not silently absorbed into this slice.
; ============================================================================

    IFNDEF CORE_FLOAT_ASM
    DEFINE CORE_FLOAT_ASM

FSTACK_TOP   EQU $9000   ; empty-stack value for IY; first push lands at $8FFD
FSTACK_LIMIT EQU $8C00   ; lowest legal float-stack address — 1024 bytes
                         ; (341 cells); no overflow check yet, matching
                         ; core/dict.asm's own DSTACK_LIMIT precedent

; ---- Phase 8 RAM state — same probe-verified $8426-$8FFF gap as every
; other core/ file's own scratch (see this file's own header). ----
F_M1          EQU $87A0   ; 2 bytes: F+/F-'s own scratch (first operand's mantissa)
F_E1          EQU $87A2   ; 1 byte:  first operand's exponent
F_M2          EQU $87A3   ; 2 bytes: second operand's mantissa
F_E2          EQU $87A5   ; 1 byte:  second operand's exponent
F_RESULT_EXP  EQU $87A6   ; 1 byte:  the aligned result's exponent

; ============================================================================
; FPUSH ( HL = mantissa, A = exponent -- )  push one float onto the
; float stack. NOT a dictionary word — internal plumbing, exactly like
; core/dict.asm's DPUSH_HL.
; ============================================================================
FPUSH:
    dec  iy
    dec  iy
    dec  iy
    ld   (iy+0), l
    ld   (iy+1), h
    ld   (iy+2), a
    ret

; ============================================================================
; FPOP ( -- HL = mantissa, A = exponent )  pop one float off the float
; stack. NOT a dictionary word.
; ============================================================================
FPOP:
    ld   l, (iy+0)
    ld   h, (iy+1)
    ld   a, (iy+2)
    inc  iy
    inc  iy
    inc  iy
    ret

; ============================================================================
; F_SHRA ( HL = value, B = count -- HL = value >> count, arithmetic )
; Sign-preserving right shift, B times. NOT a dictionary word.
; ============================================================================
F_SHRA:
    ld   a, b
    or   a
    ret  z
.loop:
    sra  h
    rr   l
    djnz .loop
    ret

; ============================================================================
; F_ALIGN ( -- )  shared by F+ and F-. Reads F_M1/F_E1/F_M2/F_E2
; (already populated by the caller), shifts whichever mantissa has the
; smaller exponent right until both exponents match, updating that
; operand's F_Mn in place, and leaves the common exponent in
; F_RESULT_EXP. NOT a dictionary word.
; ============================================================================
F_ALIGN:
    ld   a, (F_E1)
    ld   b, a
    ld   a, (F_E2)
    ld   c, a
    ld   a, b
    cp   c
    jr   z, .same_exp
    jr   c, .e1_less
    ; e1 > e2: shift F_M2 right by (e1 - e2); result exponent = e1
    ld   a, b
    sub  c
    ld   b, a
    ld   hl, (F_M2)
    call F_SHRA
    ld   (F_M2), hl
    ld   a, (F_E1)
    ld   (F_RESULT_EXP), a
    ret
.e1_less:
    ; e2 > e1: shift F_M1 right by (e2 - e1); result exponent = e2
    ld   a, c
    sub  b
    ld   b, a
    ld   hl, (F_M1)
    call F_SHRA
    ld   (F_M1), hl
    ld   a, (F_E2)
    ld   (F_RESULT_EXP), a
    ret
.same_exp:
    ld   a, (F_E1)
    ld   (F_RESULT_EXP), a
    ret

; ============================================================================
; F+ ( f1 f2 -- f1+f2 )
; ============================================================================
H_FPLUS:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL) to
                            ; whatever word chain this file should
                            ; extend, immediately before INCLUDEing
                            ; this file — see core/control.asm's own
                            ; header for the full reasoning
    DB   2, "F", "+"
W_FPLUS:
    call FPOP
    ld   (F_M2), hl
    ld   (F_E2), a
    call FPOP
    ld   (F_M1), hl
    ld   (F_E1), a
    call F_ALIGN
    ld   hl, (F_M1)
    ld   de, (F_M2)
    add  hl, de
    ld   a, (F_RESULT_EXP)
    call FPUSH
    ret

; ============================================================================
; F- ( f1 f2 -- f1-f2 )
; ============================================================================
H_FMINUS:
    DW   H_FPLUS
    DB   2, "F", "-"
W_FMINUS:
    call FPOP
    ld   (F_M2), hl
    ld   (F_E2), a
    call FPOP
    ld   (F_M1), hl
    ld   (F_E1), a
    call F_ALIGN
    ld   hl, (F_M1)
    ld   de, (F_M2)
    or   a
    sbc  hl, de
    ld   a, (F_RESULT_EXP)
    call FPUSH
    ret

DICT_LATEST_INIT_P8 EQU H_FMINUS   ; head of the dictionary as of Phase 8

    ENDIF
