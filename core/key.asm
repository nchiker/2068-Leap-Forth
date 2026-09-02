; ============================================================================
; core/key.asm — Phase 20: KEY
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT)
; and needs kernel/io/io.asm INCLUDEd alongside it. Also needs a real
; IM 1 interrupt actually running (RST $0038 -> KBD_ISR_TICK, IM 1, EI
; — the same precondition core/editor.asm's own EDITOR_LOOP_LIVE has
; documented since Phase 6) — without it, KEY blocks forever, since
; IO_READ_KEY only ever consumes a key already latched by that
; interrupt; it doesn't scan the keyboard matrix itself.
;
; WHAT THIS ADDS: KEY ( -- char ), the input counterpart to EMIT
; (Phase 10) — deferred since Phase 2 ("EMIT/KEY were deliberately
; deferred... to keep it [the ROM] minimal," docs/PROJECT_PLAN.md's own
; words), never revisited until now. Blocks until a real key is
; pressed, then pushes its translated code (kernel/io's own
; IO_READ_KEY: ordinary ASCII for a letter/digit/symbol key, or one of
; KEY_CURSOR_*/KEY_DELETE/etc for a special key — see that routine's
; own header for the complete list). No case-folding here — that's
; core/interp.asm's own W_WORD job for a parsed word, not this word's;
; KEY hands back exactly what IO_READ_KEY decoded.
; ============================================================================

    IFNDEF CORE_KEY_ASM
    DEFINE CORE_KEY_ASM

; ============================================================================
; KEY ( -- char )
; ============================================================================
H_KEY:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "K", "E", "Y"
W_KEY:
    call IO_READ_KEY
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret

DICT_LATEST_INIT_KEY EQU H_KEY   ; head of the dictionary once this
                                  ; file's own word is included

    ENDIF
