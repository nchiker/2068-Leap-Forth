; ============================================================================
; core/abortquit.asm — Phase 50: ABORT and QUIT
;
; Builds on core/dict.asm (DSTACK_TOP), core/float.asm (FSTACK_TOP), and
; core/interp.asm INCLUDEd with THROW_CATCH_ENABLED defined (for
; THROW_ROOT_SP to exist — see that file's own header). Also needs
; core/doloop.asm (LEAVE_DEPTH) and core/throwcatch.asm (CATCH_DEPTH)
; INCLUDEd first for this file's own judgment-call reset of both (see
; below) — all must precede this file in the including ROM's own
; DICT_CHAIN_POINT sequence.
;
; WHAT THIS ADDS — both reset to a fresh top-level prompt, but NOT the
; same reset, per the task's own spec and the Jupiter Ace manual's own
; wording (cached docs/JA-Ace4000-Manual text, Appendix B): "QUIT...
; doesn't clear the stack. There is a word ABORT that is much the same
; as QUIT, except that it does clear the stack."
;   ABORT ( -- )   clears BOTH the data stack (IX) and the float stack
;             (IY), then returns to the prompt.
;   QUIT  ( -- )    resets the interpreter's own return-stack/compile
;             state and re-enters the input loop, but leaves the data
;             and float stacks' CONTENTS untouched.
;
; WHAT BOTH REUSE FROM THE EXISTING "UNCAUGHT ERROR" RESET PATH: NOT a
; literal call into rom/forth_boot.asm's own RUNTIME_ERROR_HOOK label
; (a judgment call, explained below) but the exact SAME unwind
; TECHNIQUE core/interp.asm's STACK_CHECK violation path and
; core/throwcatch.asm's own THROW .uncaught path already use and are
; already proven correct by: reload SP from THROW_ROOT_SP (the SP value
; core/interp.asm's own INTERPRET_RUN snapshotted at ITS entry, gated
; behind THROW_CATCH_ENABLED), which discards every nested CALL pushed
; since then in one step and lands exactly back at "INTERPRET_RUN's own
; caller" (EDITOR_LOOP_LIVE's `call INTERPRET_RUN`, in the real product
; ROM) — the identical "one entry" invariant RUNTIME_ERROR_HOOK's own
; documented contract already requires, reused here rather than
; reimplemented. A plain `ret` after reloading SP this way returns
; directly there, exactly like RUNTIME_ERROR_HOOK's own final `ret`
; does after STACK_CHECK/THROW have already done the same reload.
;
; JUDGMENT CALL 1 — why NOT literally `jp RUNTIME_ERROR_HOOK`: that
; label (defined per-ROM, not in any shared core/ file — every
; including ROM from Phase 38 onward supplies its own, e.g.
; rom/forth_boot.asm prints "STACK?") exists specifically to report a
; genuine runtime error. Jumping there from a deliberate, user-invoked
; ABORT/QUIT would print a stack-error message for an event that is not
; a stack error, which is actively misleading. What's reused instead is
; the RESET TECHNIQUE that hook's own callers already rely on
; (THROW_ROOT_SP + DSTACK_TOP/FSTACK_TOP + the "one entry" contract),
; not the hook's own message text. Neither ABORT nor QUIT prints
; anything by itself in this implementation — a real Forth/the Ace's own
; ABORT does print something ('ERROR' plus a byte, per the manual), but
; nothing in the task's own spec requires a specific message, and
; inventing new user-facing text felt like a bigger, less-obviously-
; correct addition than the reset mechanism itself; this is flagged here
; explicitly so it can be revisited.
;
; JUDGMENT CALL 2 — both also reset CATCH_DEPTH (core/throwcatch.asm)
; and LEAVE_DEPTH (core/doloop.asm) to 0, even though the existing
; THROW .uncaught path does NOT reset CATCH_DEPTH itself (a pre-existing
; quirk, not this phase's to fix, left untouched in core/throwcatch.asm
; itself). ABORT/QUIT's own SP reload discards every CATCH frame and
; every open DO...LOOP frame that existed on the now-abandoned portion
; of the hardware stack — leaving their own DEPTH counters pointing at
; stale, now-unreachable frames would make the NEXT CATCH or DO...LOOP
; after an ABORT/QUIT compute wrong frame-slot addresses, a real latent
; bug this project doesn't already have a test for. Zeroing both here
; costs two bytes and closes it for exactly the reset scenario this new
; code introduces.
;
; JUDGMENT CALL 3 — both set INTERP_ERROR_FLAG (core/interp.asm) to 1
; before returning, suppressing EDITOR_LOOP_LIVE's own "OK" print for
; the line that invoked ABORT/QUIT (in the real product ROM). Neither
; word actually failed, but "the rest of this line, and everything
; between here and the fresh prompt, was abandoned" is exactly the
; existing INTERP_ERROR_FLAG contract (core/interp.asm's own header:
; "successful line apart from one that errored out"), and printing "OK"
; after a deliberate abort-and-restart read as more confusing than
; printing nothing, in this implementer's judgment. Not testable via
; border-color/stack checkpoints in a smoke ROM the same way the other
; resets are, so rom/forth_smoke_p50.asm does not assert on it
; specifically.
; ============================================================================

    IFNDEF CORE_ABORTQUIT_ASM
    DEFINE CORE_ABORTQUIT_ASM

; ============================================================================
; ABORT ( -- )
; ============================================================================
H_ABORT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "A","B","O","R","T"
W_ABORT:
    ld   ix, DSTACK_TOP        ; clears the data stack -- the one thing
    ld   iy, FSTACK_TOP        ; that distinguishes ABORT from QUIT
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a       ; judgment call 2, see this file's own
    ld   (LEAVE_DEPTH), a        ; header
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a   ; judgment call 3
    ld   sp, (THROW_ROOT_SP)       ; discards every nested call back to
                                     ; "INTERPRET_RUN's own caller" --
                                     ; must be the LAST thing touched
                                     ; before the ret below
    ret

; ============================================================================
; QUIT ( -- )
; ============================================================================
H_QUIT:
    DW   H_ABORT
    DB   4, "Q","U","I","T"
W_QUIT:
    ; deliberately does NOT touch IX/IY -- see this file's own header
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a
    ld   (LEAVE_DEPTH), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a
    ld   sp, (THROW_ROOT_SP)
    ret

DICT_LATEST_INIT_ABORTQUIT EQU H_QUIT   ; head of the dictionary once
                                         ; this file's own words are
                                         ; included

    ENDIF
