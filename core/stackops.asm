; ============================================================================
; core/stackops.asm — Phase 46: ROT, 2DUP, 2DROP, ?DUP, PICK
;
; Builds on core/dict.asm (DPUSH_HL/DPOP_HL, W_DROP, W_DUP) only — no
; kernel INCLUDE needed.
;
; WHAT THIS ADDS: the rest of the standard stack-shuffling vocabulary
; Phase 2 didn't cover (that phase only needed DROP/DUP/SWAP/OVER for
; its own bring-up). Real, idiomatic Forth code leans on these
; constantly; their total absence was a genuine gap, not a deliberate
; scope cut — flagged directly by the user after a fresh audit of
; what's actually in the dictionary today.
;   ROT   ( a b c -- b c a )
;   2DUP  ( a b -- a b a b )
;   2DROP ( a b -- )            reuses W_DROP twice rather than
;                                reimplementing the same effect
;   ?DUP  ( x -- 0 | x x )      duplicates only if x is nonzero,
;                                matching the real ANS Forth contract
;                                exactly (a bare `0=`-then-`IF` guard
;                                this project already has doesn't
;                                replace this — ?DUP is about NOT
;                                consuming x yet, common right before
;                                an IF that wants to test and keep it)
;   PICK  ( x_u ... x_0 u -- x_u ... x_0 x_u )
;                                0 PICK = DUP, 1 PICK = OVER. NO bounds
;                                checking on u, matching this project's
;                                established SOUND/STICK convention —
;                                an out-of-range u reads whatever
;                                memory that computes to, not guarded.
; ============================================================================

    IFNDEF CORE_STACKOPS_ASM
    DEFINE CORE_STACKOPS_ASM

; ============================================================================
; ROT ( a b c -- b c a )
; ============================================================================
H_ROT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "R","O","T"
W_ROT:
    ld   c, (ix+4)
    ld   b, (ix+5)          ; bc = a
    ld   e, (ix+2)
    ld   d, (ix+3)          ; de = b
    ld   l, (ix+0)
    ld   h, (ix+1)          ; hl = c
    ld   (ix+4), e
    ld   (ix+5), d          ; a's old slot now holds b
    ld   (ix+2), l
    ld   (ix+3), h          ; b's old slot now holds c
    ld   (ix+0), c
    ld   (ix+1), b          ; c's old slot (top) now holds a
    ret

; ============================================================================
; 2DUP ( a b -- a b a b )
; ============================================================================
H_2DUP:
    DW   H_ROT
    DB   4, "2","D","U","P"
W_2DUP:
    ld   e, (ix+0)
    ld   d, (ix+1)          ; de = b (top)
    ld   l, (ix+2)
    ld   h, (ix+3)          ; hl = a
    call DPUSH_HL           ; push a-copy first (ends up 2nd from top)
    ex   de, hl
    call DPUSH_HL           ; push b-copy (ends up on top)
    ret

; ============================================================================
; 2DROP ( a b -- )
; ============================================================================
H_2DROP:
    DW   H_2DUP
    DB   5, "2","D","R","O","P"
W_2DROP:
    call W_DROP
    call W_DROP
    ret

; ============================================================================
; ?DUP ( x -- 0 | x x )
; ============================================================================
H_QDUP:
    DW   H_2DROP
    DB   4, "?","D","U","P"
W_QDUP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    or   l
    ret  z                   ; x = 0: leave the single 0 exactly as is
    call W_DUP
    ret

; ============================================================================
; PICK ( x_u ... x_0 u -- x_u ... x_0 x_u )
; ============================================================================
H_PICK:
    DW   H_QDUP
    DB   4, "P","I","C","K"
W_PICK:
    call DPOP_HL             ; hl = u
    add  hl, hl               ; hl = u*2 (byte offset)
    push ix
    pop  de                    ; de = ix (already past u's own cell)
    add  hl, de                ; hl = address of the picked item
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                ; de = the picked value
    ex   de, hl
    call DPUSH_HL
    ret

DICT_LATEST_INIT_STACKOPS EQU H_PICK   ; head of the dictionary once
                                        ; this file's own words are
                                        ; included

    ENDIF
