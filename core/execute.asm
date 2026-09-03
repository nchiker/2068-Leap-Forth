; ============================================================================
; core/execute.asm — Phase 41: EXECUTE
;
; Builds on core/dict.asm (DPOP_HL) — must be INCLUDEd first; this
; file's own first header chains through DICT_CHAIN_POINT.
;
; WHAT THIS ADDS: standard ANS Forth's EXECUTE ( xt -- ) — the real
; ROM's own audit finding, described there as "standard Forth's own
; counterpart to BASIC's USR(addr): jump into arbitrary code from an
; address already on the data stack." Genuinely nothing in 2068-Forth
; did this before now.
;
; TRIVIAL IN THIS PROJECT'S OWN THREADING MODEL, and worth saying why
; rather than leaving it looking like an accident: this is a
; SUBROUTINE-threaded Forth (core/dict.asm's own header) — a colon
; definition compiles directly to a sequence of real Z80 `CALL`
; instructions ending in `RET`, and a primitive's own code IS the
; routine FIND already returns as its "code address." There is no
; separate indirection layer (no token table, no `DOCOL`-style inner
; interpreter) standing between an execution token and real, directly
; jumpable machine code — for either kind of word. So EXECUTE doesn't
; need to know or care whether the address it's given is a primitive or
; a user-defined colon word: `JP (HL)` to either one behaves correctly,
; because `EXECUTE` was itself reached via an ordinary `CALL` (from
; whatever compiled or interpreted code invoked it) — the return
; address already sitting on the Z80 hardware stack belongs to THAT
; caller, untouched by the plain jump below, so the target's own `RET`
; naturally returns to wherever `EXECUTE` itself would have. Two
; instructions is the whole word, not a simplification of something
; bigger.
;
; NO ADDRESS VALIDATION, matching BASIC's own `USR(addr)` (which also
; just jumps to whatever address it's given) and this project's
; established no-error-mechanism convention (`SOUND`'s own header
; states the same posture explicitly): a garbage address does whatever
; jumping to garbage memory does on real hardware, not guarded against.
;
; SCOPE NOTE: this project has no `'` (tick) word to look up an
; existing dictionary word's own execution token by name from typed
; source — EXECUTE here serves the `USR(addr)`-shaped use case the
; audit named (a numeric address computed or already known, e.g. from
; a VARIABLE or CREATE'd buffer holding raw machine code), not "call
; any word in the dictionary by name." Adding a lookup word is a
; separate, not-yet-requested feature.
; ============================================================================

    IFNDEF CORE_EXECUTE_ASM
    DEFINE CORE_EXECUTE_ASM

; ============================================================================
; EXECUTE ( xt -- )
; ============================================================================
H_EXECUTE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   7, "E", "X", "E", "C", "U", "T", "E"
W_EXECUTE:
    call DPOP_HL            ; hl = xt (a code address)
    jp   (hl)                ; NOT a call -- see this file's own header

DICT_LATEST_INIT_EXECUTE EQU H_EXECUTE   ; head of the dictionary once
                                           ; this file's own word is
                                           ; included

    ENDIF
