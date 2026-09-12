; ============================================================================
; core/key.asm — Phase 20: KEY; Phase 62: BREAK?
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
;
; BREAK? ( -- flag ), added Phase 62: real Sinclair CAPS SHIFT+SPACE
; abort-combo detection, backed by kernel/io's own IO_CHECK_BREAK — a
; real keyboard-matrix scan (not a buffered read; does its own scan
; each call, no interaction with KEY/KEY?'s own latched-key state).
; Lets a user's own loop become abortable: `BEGIN ... BREAK? UNTIL`.
; Found idle in the inherited kernel (used internally by the sibling
; BASIC project's own program-run loop) with no Forth word exposing it
; — same shape of gap BRIGHT/FLASH closed for CURRENT_ATTR's own
; unclaimed bits.
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

DICT_LATEST_INIT_KEY EQU H_KEY   ; head of the dictionary as of Phase
                                  ; 20 (KEY only) -- rom/forth_smoke_p20.asm's
                                  ; own historical snapshot; must NOT be
                                  ; repointed at KEY? below

; ============================================================================
; KEY? ( -- flag )  Phase 36. Standard Forth's own non-destructive
; lookahead: TRUE (-1) if a key is currently waiting, FALSE (0)
; otherwise -- crucially, does NOT consume it, so `KEY? IF KEY ... THEN`
; is the correct idiom, exactly like every other Forth's KEY?/KEY pair.
; Backed by kernel/io's own IO_KEY_AVAILABLE (added alongside this
; word) -- a consuming non-blocking read (matching BASIC's own INKEY$)
; would silently make KEY? swallow the very key a following KEY expects
; to see, which is exactly why this project never built KEY? on one.
; See kernel/io/io.asm's own IO_KEY_AVAILABLE header for the full
; story.
; ============================================================================
H_KEYQ:
    DW   H_KEY
    DB   4, "K", "E", "Y", "?"
W_KEYQ:
    call IO_KEY_AVAILABLE
    or   a
    jr   z, .false
    ld   hl, -1
    call DPUSH_HL
    ret
.false:
    ld   hl, 0
    call DPUSH_HL
    ret

; ============================================================================
; BREAK? ( -- flag )  Phase 62. TRUE (-1) if CAPS SHIFT+SPACE is
; currently held, FALSE (0) otherwise. Does its own keyboard scan each
; call (kernel/io's own IO_CHECK_BREAK) -- independent of KEY/KEY?'s
; latched-key state, so checking it never consumes or disturbs a
; pending KEY.
; ============================================================================
H_BREAKQ:
    DW   H_KEYQ
    DB   6, "B", "R", "E", "A", "K", "?"
W_BREAKQ:
    call IO_CHECK_BREAK
    ld   hl, 0
    jr   nc, .push
    ld   hl, -1
.push:
    call DPUSH_HL
    ret

DICT_LATEST_INIT_KEYQ EQU H_BREAKQ   ; head of the dictionary once this
                                    ; file's own words (KEY, KEY?, and
                                    ; BREAK?) are all included

    ENDIF
