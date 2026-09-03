; ============================================================================
; core/outwords.asm — Phase 46: CR, SPACE, SPACES
;
; Builds on core/dict.asm (DPUSH_HL) and core/print.asm (needs W_EMIT,
; Phase 10) — both must be INCLUDEd first.
;
; WHAT THIS ADDS: the output ergonomics every other Forth-visible EMIT
; user has had to hand-roll until now (`13 EMIT` for a newline, `32
; EMIT` for a space) — real, felt friction, not a missing feature
; anyone had actually needed for anything beyond convenience, which is
; exactly why it was skipped this long.
;   CR     ( -- )    13 EMIT
;   SPACE  ( -- )    32 EMIT
;   SPACES ( n -- )   n spaces. NO input validation on n (matching this
;             project's own SOUND/STICK convention) — n=0 does nothing;
;             a negative n loops close to 65536 times before it
;             naturally hits zero as an unsigned counter, not guarded
;             against, exactly as candid about that as this project's
;             other unchecked-input words already are.
;
; SPACES' OWN COUNTER LIVES IN MEMORY (SPACES_COUNT), NOT A REGISTER
; PAIR — a real bug caught here before ever running it made it into a
; first draft that kept the count in BC across each call to W_SPACE:
; W_EMIT (core/print.asm) explicitly loads B=row and C=column before
; calling GFX_PUTCHAR, so BC does not survive being used as a loop
; counter across a W_SPACE/W_EMIT call, the exact same class of bug
; already caught once this same phase in rom/forth_smoke_p46.asm's own
; ANY_PIXEL_SET_IN_CELL helper (GFX_READ_PIXEL clobbering DE there).
; ============================================================================

    IFNDEF CORE_OUTWORDS_ASM
    DEFINE CORE_OUTWORDS_ASM

SPACES_COUNT EQU $8940   ; 2 bytes: SPACES' own remaining-count scratch

; ============================================================================
; CR ( -- )
; ============================================================================
H_CR:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "C","R"
W_CR:
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
    ret

; ============================================================================
; SPACE ( -- )
; ============================================================================
H_SPACE:
    DW   H_CR
    DB   5, "S","P","A","C","E"
W_SPACE:
    ld   hl, 32
    call DPUSH_HL
    call W_EMIT
    ret

; ============================================================================
; SPACES ( n -- )
; ============================================================================
H_SPACES:
    DW   H_SPACE
    DB   6, "S","P","A","C","E","S"
W_SPACES:
    call DPOP_HL             ; hl = n
    ld   (SPACES_COUNT), hl
.loop:
    ld   hl, (SPACES_COUNT)
    ld   a, h
    or   l
    ret  z
    dec  hl
    ld   (SPACES_COUNT), hl   ; stored back BEFORE calling W_SPACE --
                               ; see this file's own header on why HL
                               ; can't just stay loaded across that
                               ; call either (W_EMIT's own DPOP_HL
                               ; would clobber it same as BC)
    call W_SPACE
    jr   .loop

DICT_LATEST_INIT_OUTWORDS EQU H_SPACES   ; head of the dictionary once
                                          ; this file's own words are
                                          ; included

    ENDIF
