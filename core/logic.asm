; ============================================================================
; core/logic.asm — Phase 46: AND, OR, XOR, INVERT
;
; Builds on core/dict.asm (DPOP_HL/DPUSH_HL) only — no kernel INCLUDE
; needed.
;
; WHAT THIS ADDS: bitwise logical operations, entirely absent from the
; dictionary until now (core/compare.asm's own `=`/`<`/`>` produce
; boolean flags but never combine them, and `0=` — core/control.asm,
; Phase 4 — is a boolean NOT of a flag, not a bitwise complement).
; These operate on all 16 bits of each cell, the standard ANS Forth
; contract — used both for genuine bit manipulation and, via TRUE/
; FALSE-style all-1s/all-0s flags, for combining boolean conditions.
;   AND    ( a b -- a&b  )
;   OR     ( a b -- a|b  )
;   XOR    ( a b -- a^b  )
;   INVERT ( a -- ~a )   bitwise one's-complement, the real ANS Forth
;             name for this — deliberately NOT called NOT (some older
;             Forths use that name, but this project already has `0=`
;             doing logical negation of a flag; a second, DIFFERENTLY
;             behaved word spelled NOT would be a real footgun next to
;             it, not a helpful synonym).
; ============================================================================

    IFNDEF CORE_LOGIC_ASM
    DEFINE CORE_LOGIC_ASM

; ============================================================================
; AND ( a b -- a&b )
; ============================================================================
H_AND:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "A","N","D"
W_AND:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    and  (ix+0)
    ld   l, a
    ld   a, h
    and  (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; OR ( a b -- a|b )
; ============================================================================
H_OR:
    DW   H_AND
    DB   2, "O","R"
W_OR:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    or   (ix+0)
    ld   l, a
    ld   a, h
    or   (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; XOR ( a b -- a^b )
; ============================================================================
H_XOR:
    DW   H_OR
    DB   3, "X","O","R"
W_XOR:
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = b
    inc  ix
    inc  ix
    ld   a, l
    xor  (ix+0)
    ld   l, a
    ld   a, h
    xor  (ix+1)
    ld   h, a
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; INVERT ( a -- ~a )
; ============================================================================
H_INVERT:
    DW   H_XOR
    DB   6, "I","N","V","E","R","T"
W_INVERT:
    ld   a, (ix+0)
    cpl
    ld   (ix+0), a
    ld   a, (ix+1)
    cpl
    ld   (ix+1), a
    ret

DICT_LATEST_INIT_LOGIC EQU H_INVERT   ; head of the dictionary once
                                       ; this file's own words are
                                       ; included

    ENDIF
