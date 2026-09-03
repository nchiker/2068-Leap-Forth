; ============================================================================
; core/tick.asm — Phase 46: ' (TICK)
;
; Builds on core/dict.asm (DPOP_HL/DPUSH_HL, W_DROP), core/interp.asm
; (needs W_WORD/FIND, Phase 3), and core/throwcatch.asm (needs
; W_THROW, Phase 45) — all three must be INCLUDEd first.
;
; WHAT THIS ADDS: ' ( -- xt ), parses the next word from the input
; source (exactly like INTERPRET_RUN's own .loop does for every normal
; token) and pushes its code address as an xt, without executing it.
; Closes a real gap EXECUTE (Phase 41) left open: EXECUTE has always
; needed an xt from somewhere, but until now the only way to get one
; from Forth source was Phase 41's own smoke-ROM trick of walking FIND
; by hand at the assembly level — there was no Forth-visible way to
; write `' SOMEWORD EXECUTE` at all.
;
; AN UNDEFINED WORD THROWS -13 — this project's first user-facing use
; of Phase 45's own THROW/CATCH for something other than its own
; smoke-test stubs, and a real, meaningful choice now that the
; mechanism exists: -13 is the actual ANS Forth standard exception
; code for "undefined word," not a number picked at random. Requires
; core/throwcatch.asm INCLUDEd first — a real new dependency this file
; adds, stated plainly rather than silently assumed.
; ============================================================================

    IFNDEF CORE_TICK_ASM
    DEFINE CORE_TICK_ASM

; ============================================================================
; ' ( -- xt )
; ============================================================================
H_TICK:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   1, "'"
W_TICK:
    call W_WORD
    call FIND
    call DPOP_HL             ; hl = found flag
    ld   a, h
    or   l
    jr   nz, .found
    call W_DROP               ; FIND's own "not found" contract leaves
                                ; the search addr pushed back unchanged
                                ; -- drop it before throwing
    ld   hl, -13               ; ANS Forth's own "undefined word" code
    call DPUSH_HL
    call W_THROW
    ret                         ; unreachable if uncaught (THROW jumps
                                 ; away); reached only if some active
                                 ; CATCH unwinds past this call anyway
.found:
    call DPOP_HL               ; hl = immediate flag, discard -- ' has
                                 ; no use for it, only EXECUTE cares
                                 ; whether it's about to run compiled
                                 ; or interpreted code, and ' does
                                 ; neither
    ret                          ; code_addr is already the only thing
                                  ; left on the stack -- the xt itself

DICT_LATEST_INIT_TICK EQU H_TICK   ; head of the dictionary once this
                                    ; file is the last one INCLUDEd

    ENDIF
