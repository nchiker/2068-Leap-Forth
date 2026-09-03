; ============================================================================
; core/throwcatch.asm — Phase 45: THROW and CATCH
;
; Builds on core/dict.asm (DPOP_HL/DPUSH_HL) only for its own dictionary
; plumbing, but needs core/interp.asm INCLUDEd first with
; THROW_CATCH_ENABLED defined (see that file's own INTERPRET_RUN
; header) for THROW_ROOT_SP to exist, and needs the including ROM to
; supply RUNTIME_ERROR_HOOK (exactly like Phase 38's own
; RUNTIME_ERROR_CHECK_ENABLED requires) — an uncaught THROW recovers
; through that same, already-established hook.
;
; This is the last of the user's own explicit 3-step plan from when
; Phase 38 was scoped: (1) runtime error detection [Phase 38], (2)
; code consolidation [Phase 39], (3) this — a PROGRAMMABLE recovery
; mechanism, letting a program intercept an error and keep running
; under its own control instead of the system always aborting to a
; fresh prompt.
;
; WHAT THIS ADDS — standard ANS Forth CATCH/THROW:
;   CATCH ( i*x xt -- j*x 0 | i*x n )   execute xt; 0 if it completed
;             normally, or the thrown n if it didn't (both integer and
;             float stacks restored to their CATCH-time depth first)
;   THROW ( n -- )   n=0 is a no-op; n<>0 unwinds to the most recent
;             active CATCH (or, if none, to the same top-level recovery
;             Phase 38's own stack-error detection already uses)
;
; HOW THIS WORKS on a SUBROUTINE-THREADED Forth (docs/PROJECT_PLAN.md
; Phase 1) — there is no separate software return stack to unwind, the
; real Z80 hardware stack (SP) IS the return stack, so THROW must
; unwind SP directly, exactly like a C setjmp/longjmp pair:
;   - CATCH snapshots SP/IX/IY (both data stacks) into a small BOUNDED
;     stack of catch frames (CATCH_MAX_DEPTH deep, matching this
;     project's own "bounded, not unbounded" convention — see
;     core/doloop.asm's own LEAVE_HEAD_TABLE for the same shape),
;     indexed by CATCH_DEPTH, THEN calls xt.
;   - If xt returns normally, CATCH pops its own frame (CATCH_DEPTH--)
;     and pushes 0. Ordinary CALL/RET, nothing exceptional happened.
;   - If a THROW executes anywhere inside xt's own call tree (however
;     deeply nested) with a nonzero n, THROW looks up the CURRENT
;     innermost frame (CATCH_DEPTH-1), restores SP/IX/IY from it
;     directly, pushes n onto the now-restored data stack, and does a
;     plain `ret`. Restoring SP to the value CATCH captured AT ITS OWN
;     ENTRY (before calling xt) discards every nested return address
;     pushed since then in one step, and naturally re-exposes CATCH's
;     OWN return address at the top of the (now-restored) stack — so
;     the final `ret` returns to CATCH's caller exactly as if CATCH's
;     own `call xt` had itself just returned, only with n pushed
;     instead of 0. Neither CATCH's own normal-completion code nor any
;     of the unwound intermediate calls' own cleanup ever runs — this
;     project's own established posture (STACK_CHECK's violation path,
;     INTERPRET_UNKNOWN_WORD) already treats "abandon whatever
;     in-flight state existed, don't try to preserve it" as correct
;     for an error path, not a shortcut taken only here.
;
; SP/IX/IY CANNOT BE STORED TO OR LOADED FROM A COMPUTED ADDRESS —
; `LD (nn),SP`/`LD (nn),IX`/`LD (nn),IY` (and their inverses) only take
; a FIXED, assembly-time address, never (HL) or any other indirect
; form. Since a catch frame's OWN address depends on CATCH_DEPTH (a
; runtime value), every save/restore goes through a small FIXED staging
; area (CATCH_TMP_SP/IX/IY) first: CATCH stages current SP/IX/IY into
; those fixed cells, then LDIRs them into the computed frame slot;
; THROW copies the computed frame slot's 6 bytes back into those same
; fixed cells (unrolled by hand, not LDIR — LDIR's own BC-as-counter
; requirement would clobber the thrown value n, which THROW needs kept
; safe in BC across this exact copy), then loads SP/IX/IY from the
; now-fixed addresses.
;
; UNCAUGHT THROW (CATCH_DEPTH already 0): there is no user CATCH frame
; to restore, but RUNTIME_ERROR_HOOK's own documented contract (see
; core/interp.asm's STACK_CHECK) requires the Z80 hardware stack
; already restored to "exactly one entry: INTERPRET_RUN's own caller"
; before it's reached — and THROW could be running arbitrarily deep
; inside nested word calls, not just one level down like STACK_CHECK's
; own single `pop hl`. THROW_ROOT_SP (core/interp.asm, gated behind the
; same THROW_CATCH_ENABLED this file needs anyway) solves this exactly
; the same way a user CATCH frame does: INTERPRET_RUN snapshots its own
; SP once, at its very entry (fixed for the whole call, since .loop's
; own dispatch always fully unwinds between words) — an uncaught THROW
; restores SP from THAT snapshot instead of a user frame, discarding
; every nested call in one step the same way, then resets both stacks
; to empty (matching STACK_CHECK's own "don't try to preserve
; in-flight state" posture) and jumps to RUNTIME_ERROR_HOOK exactly
; like a stack-depth violation already does. n itself is discarded —
; this project has no error-payload reporting yet, the same honestly
; stated limitation STACK_CHECK's own header already states.
;
; CATCH_MAX_DEPTH OVERFLOW (nesting CATCH deeper than the bound):
; graceful, not a crash, matching this project's own GFX_FILL_STACK
; precedent — that CATCH simply doesn't record a frame and runs xt
; unguarded. If xt completes normally, 0 is still pushed correctly
; (nothing exceptional happened). If something inside DOES throw, it
; escapes PAST this uncounted CATCH to whatever's next (an outer
; CATCH, or the uncaught path) — a real, documented limitation, not
; silent corruption.
; ============================================================================

    IFNDEF CORE_THROWCATCH_ASM
    DEFINE CORE_THROWCATCH_ASM

CATCH_MAX_DEPTH EQU 8            ; matches core/doloop.asm's own
                                  ; LEAVE_HEAD_TABLE bound
CATCH_TMP_SP    EQU $890F        ; 2 bytes: fixed staging cell (see
                                  ; this file's own header for why a
                                  ; computed frame address can't be
                                  ; used directly with SP/IX/IY)
CATCH_TMP_IX    EQU $8911        ; 2 bytes
CATCH_TMP_IY    EQU $8913        ; 2 bytes
CATCH_DEPTH     EQU $8915        ; 1 byte: 0 = no active CATCH. MUST be
                                  ; zeroed once by every including ROM's
                                  ; own COLD_START, same requirement
                                  ; core/doloop.asm's LEAVE_DEPTH states
CATCH_STACK     EQU $8916        ; CATCH_MAX_DEPTH x 6 bytes (SP,IX,IY
                                  ; per frame) = 48 bytes, through $8945

; ============================================================================
; JUMP_HL — NOT a dictionary word, shared plumbing local to this file
; (same convention as core/dict.asm's own DPUSH_HL/DPOP_HL). `call
; JUMP_HL` reaches xt's own code via `jp (hl)` without pushing anything
; beyond JUMP_HL's own return address, so xt's own `ret` returns
; straight back to whoever did `call JUMP_HL` — used instead of the
; real EXECUTE word (core/execute.asm) because that word does its own
; DPOP_HL, and CATCH already has xt sitting in HL, not back on the
; data stack.
; ============================================================================
JUMP_HL:
    jp   (hl)

; ============================================================================
; THROW ( n -- )
; ============================================================================
H_THROW:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                             ; not EQU) to whatever word chain this
                             ; file should extend, immediately before
                             ; INCLUDEing this file
    DB   5, "T","H","R","O","W"
W_THROW:
    call DPOP_HL             ; hl = n
    ld   a, h
    or   l
    ret  z                   ; n = 0: no-op, per THROW's own contract
    ld   b, h                ; bc = n, kept safe in BC across the
    ld   c, l                ; unrolled copy below (LDIR would need BC
                              ; as its own counter, clobbering it)
    ld   a, (CATCH_DEPTH)
    or   a
    jr   z, .uncaught
    dec  a
    ld   (CATCH_DEPTH), a
    ; hl = frame slot address = CATCH_STACK + a*6
    ld   l, a
    ld   h, 0
    add  hl, hl               ; a*2
    ld   d, h
    ld   e, l
    add  hl, hl               ; a*4
    add  hl, de                ; a*6
    ld   de, CATCH_STACK
    add  hl, de                ; hl = frame slot address (source)
    ld   a, (hl)
    ld   (CATCH_TMP_SP), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_SP+1), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IX), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IX+1), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IY), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IY+1), a
    ld   sp, (CATCH_TMP_SP)
    ld   ix, (CATCH_TMP_IX)
    ld   iy, (CATCH_TMP_IY)
    ld   h, b                 ; hl = n again
    ld   l, c
    call DPUSH_HL              ; push n onto the freshly-restored stack
    ret                        ; returns to CATCH's own caller -- SP now
                                ; points at CATCH's own original return
                                ; address, see this file's own header
.uncaught:
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    ld   sp, (THROW_ROOT_SP)    ; core/interp.asm — discards every
                                 ; nested call back to "one entry",
                                 ; exactly what RUNTIME_ERROR_HOOK's own
                                 ; contract requires (see this file's
                                 ; own header)
    jp   RUNTIME_ERROR_HOOK

; ============================================================================
; CATCH ( xt -- 0 | n )
; ============================================================================
H_CATCH:
    DW   H_THROW
    DB   5, "C","A","T","C","H"
W_CATCH:
    ld   a, (CATCH_DEPTH)
    cp   CATCH_MAX_DEPTH
    jr   nc, .no_room
    ld   (CATCH_TMP_SP), sp     ; stage current SP/IX/IY (see this
    ld   (CATCH_TMP_IX), ix     ; file's own header for why the
    ld   (CATCH_TMP_IY), iy     ; computed frame slot can't be written
                                 ; to directly)
    ld   l, a
    ld   h, 0
    add  hl, hl                 ; a*2
    ld   d, h
    ld   e, l
    add  hl, hl                 ; a*4
    add  hl, de                  ; a*6
    ld   de, CATCH_STACK
    add  hl, de                  ; hl = frame slot address (dest)
    ex   de, hl                  ; de = frame slot address (dest)
    ld   hl, CATCH_TMP_SP        ; hl = staged bytes (source)
    ld   bc, 6
    ldir                         ; copies SP,IX,IY into the frame slot
    ld   a, (CATCH_DEPTH)
    inc  a
    ld   (CATCH_DEPTH), a
    call DPOP_HL                 ; hl = xt
    call JUMP_HL                 ; runs xt; falls through here only if
                                  ; it returned normally (no throw)
    ld   a, (CATCH_DEPTH)
    dec  a
    ld   (CATCH_DEPTH), a
    ld   hl, 0
    call DPUSH_HL
    ret
.no_room:
    ; CATCH_MAX_DEPTH already reached: run xt WITHOUT recording a
    ; frame (see this file's own header for the full, deliberate
    ; degradation this implies) -- if xt still returns normally, that's
    ; still a genuine success, so 0 is pushed exactly like the counted
    ; path; a throw from inside simply isn't caught HERE
    call DPOP_HL
    call JUMP_HL
    ld   hl, 0
    call DPUSH_HL
    ret

DICT_LATEST_INIT_THROWCATCH EQU H_CATCH   ; head of the dictionary
                                           ; once this file's own words
                                           ; are included

    ENDIF
