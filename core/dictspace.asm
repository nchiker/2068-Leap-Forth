; ============================================================================
; core/dictspace.asm — Phase 50: HERE, , (COMMA), C, (CCOMMA), ALLOT
;
; Builds on core/dict.asm (HERE, DPUSH_HL, DPOP_HL) and core/interp.asm
; (COMPILE_WORD, COMPILE_BYTE) — both must be INCLUDEd first, same
; convention as every other core/ file that extends the chain via
; DICT_CHAIN_POINT.
;
; WHAT THIS ADDS — the first of the "architectural tier" words from the
; Jupiter Ace audit (see rom/forth_boot.asm's own header for the full
; word list this phase adds): the primitive dictionary-space-growing
; words every later CREATE/DOES> word in this same phase is built out
; of, exactly the way real Forth systems layer CREATE on top of these.
;   HERE  ( -- addr )   the CURRENT value of core/dict.asm's own HERE
;             cell — nothing new is invented here; HERE the word simply
;             exposes HERE the RAM cell that `:`/VARIABLE/CONSTANT/
;             ARRAY have all been reading and writing internally since
;             Phase 3/12/26.
;   ,     ( n -- )       compiles one 16-bit cell at HERE, advancing it
;             by 2 — reuses core/interp.asm's own COMPILE_WORD exactly
;             as core/control.asm's IF/ELSE/THEN/UNTIL already do for
;             branch targets; COMMA's own ANS Forth contract ("write the
;             raw value, not a literal-with-CALL-DOLIT wrapper") is
;             precisely what COMPILE_WORD already does and COMPILE_LITERAL
;             does NOT, so COMPILE_WORD is the correct existing primitive
;             to reuse here, not COMPILE_LITERAL.
;   C,    ( n -- )       compiles one byte at HERE, advancing it by 1 —
;             reuses COMPILE_BYTE (the same routine `;` already uses to
;             compile a bare RET).
;   ALLOT ( n -- )       advances HERE by n bytes without writing
;             anything — reserves raw space for a CREATE'd word's own
;             data field (see core/create.asm, this same phase). A
;             negative n legitimately SHRINKS the dictionary instead
;             (16-bit two's-complement ADD HL,DE handles this for free,
;             no special-casing needed) — not required by this phase's
;             own test plan, but a correct, harmless side effect of the
;             most direct implementation, not a deliberately added
;             feature.
;
; NO RANGE CHECKING against core/free.asm's own DICT_RAM_CEILING for any
; of these — matching every other HERE-advancing word in this project
; (`:`, VARIABLE, CONSTANT, ARRAY): FREE ( -- n ) already exists for a
; program to check headroom itself before a large ALLOT/CREATE if it
; cares, and adding an automatic check here that none of those earlier,
; already-shipped words have would be a wider, inconsistent behavior
; change this phase has no mandate to make.
; ============================================================================

    IFNDEF CORE_DICTSPACE_ASM
    DEFINE CORE_DICTSPACE_ASM

; ============================================================================
; HERE ( -- addr )
; ============================================================================
H_HERE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   4, "H","E","R","E"
W_HERE:
    ld   hl, (HERE)
    call DPUSH_HL
    ret

; ============================================================================
; , ( n -- )  "comma"
; ============================================================================
H_COMMA:
    DW   H_HERE
    DB   1, ","
W_COMMA:
    call DPOP_HL
    call COMPILE_WORD
    ret

; ============================================================================
; C, ( n -- )
; ============================================================================
H_CCOMMA:
    DW   H_COMMA
    DB   2, "C", ","
W_CCOMMA:
    call DPOP_HL
    ld   a, l
    call COMPILE_BYTE
    ret

; ============================================================================
; ALLOT ( n -- )
; ============================================================================
H_ALLOT:
    DW   H_CCOMMA
    DB   5, "A","L","L","O","T"
W_ALLOT:
    call DPOP_HL             ; hl = n
    ld   de, (HERE)
    add  hl, de               ; hl = HERE + n (two's complement handles
                                ; a negative n correctly with no special
                                ; case -- see this file's own header)
    ld   (HERE), hl
    ret

DICT_LATEST_INIT_DICTSPACE EQU H_ALLOT   ; head of the dictionary once
                                          ; this file's own words are
                                          ; included

    ENDIF
