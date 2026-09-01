; ============================================================================
; core/loop.asm — Phase 14: BEGIN/WHILE/REPEAT
;
; Builds on core/dict.asm, core/interp.asm, AND core/control.asm (all
; three must be INCLUDEd first, control.asm's BEGIN/UNTIL specifically
; — this file's own first header chains through DICT_CHAIN_POINT, and
; both words below directly reuse control.asm's own internal QBRANCH/
; BRANCH runtime routines, not dictionary words themselves but plain
; labels visible to anything assembled after them). core/control.asm
; itself is untouched — it's INCLUDEd by several smoke ROMs and
; rom/forth_boot.asm already, and this project's standing practice is
; to add a new, small file rather than widen the regression surface of
; an already-shared one for a later phase's convenience.
;
; WHAT THIS ADDS (the first half of docs/forth_tutorial.md's remaining
; "Counted loops" gap — BEGIN/UNTIL, from Phase 4, tests its condition
; only AFTER each pass; this adds the other standard Forth loop shape,
; which can also test it BEFORE the first pass, or exit partway
; through):
;   WHILE ( flag -- )  IMMEDIATE   inside a BEGIN ... WHILE ... REPEAT,
;             exits the loop immediately if flag is false, otherwise
;             continues into the loop body
;   REPEAT ( -- )      IMMEDIATE   closes a BEGIN ... WHILE ... REPEAT,
;             branching back to BEGIN
;
; `DO`/`LOOP` (a counted loop with a built-in index, comparable to
; BASIC's `FOR`/`NEXT`) is NOT this file, and remains open: it needs a
; place to keep the loop's own limit/index values across each pass, and
; this project's subroutine-threaded design already uses the Z80
; hardware stack (SP) for real CALL/RET return addresses — reusing it
; for loop control too, the way many real Forths do on a *separate*
; return stack, needs careful design this phase doesn't attempt.
;
; THE COMPILE-TIME STACK TRICK, continued: `BEGIN` (core/control.asm)
; pushes the loop-start address; `WHILE` pushes ITS OWN placeholder
; address ON TOP of that, using exactly `IF`'s own body — the two
; nest correctly on the borrowed data stack purely because `WHILE`
; never touches what's already below its own placeholder. `REPEAT` pops
; both, in the matching LIFO order (`WHILE`'s placeholder first, since
; it was pushed last; `BEGIN`'s loop-start second), compiles the
; unconditional branch back to the loop's start, then patches `WHILE`'s
; placeholder to land right there — the same "patch to HERE" step
; `ELSE`/`THEN` already established, just reused here instead of
; reinvented.
; ============================================================================

    IFNDEF CORE_LOOP_ASM
    DEFINE CORE_LOOP_ASM

; ============================================================================
; WHILE ( flag -- )  IMMEDIATE
; Identical in shape to IF (core/control.asm): compiles a call to
; QBRANCH followed by a placeholder, and leaves the placeholder's
; address on the (compile-time) stack — for REPEAT to patch, the same
; role THEN plays for IF. Does not touch whatever BEGIN already left
; below it on that same borrowed stack.
; ============================================================================
H_WHILE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   $85, "W", "H", "I", "L", "E"   ; length 5, IMMEDIATE
W_WHILE:
    ld   hl, QBRANCH
    call COMPILE_CALL
    ld   hl, (HERE)
    call DPUSH_HL
    ld   hl, 0
    call COMPILE_WORD
    ret

; ============================================================================
; REPEAT ( -- )  IMMEDIATE
; Compiles an unconditional branch back to BEGIN's remembered
; loop-start address, then patches WHILE's placeholder to land HERE
; (right after that branch) — so a false WHILE flag exits straight past
; the whole loop.
; ============================================================================
H_REPEAT:
    DW   H_WHILE
    DB   $86, "R", "E", "P", "E", "A", "T"   ; length 6, IMMEDIATE
W_REPEAT:
    call DPOP_HL                ; hl = WHILE's own placeholder address
    push hl                     ; stashed briefly on the Z80 hardware
                                 ; stack -- safe: symmetric push/pop
                                 ; within this one routine's own body,
                                 ; not crossing any CALL/RET boundary
                                 ; (core/control.asm's W_ELSE documents
                                 ; this same technique)
    ld   hl, BRANCH
    call COMPILE_CALL
    call DPOP_HL                ; hl = BEGIN's remembered loop-start
    call COMPILE_WORD
    pop  hl                     ; hl = WHILE's own placeholder address
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    ret

DICT_LATEST_INIT_LOOP EQU H_REPEAT   ; head of the dictionary once this
                                      ; file's own words are included

    ENDIF
