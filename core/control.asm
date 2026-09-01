; ============================================================================
; core/control.asm — Phase 4: control flow (IF/ELSE/THEN, BEGIN/UNTIL)
;
; Builds on core/dict.asm AND core/interp.asm (both must be INCLUDEd
; first — this file chains its own dictionary entries onto
; core/interp.asm's H_SEMICOLON, and uses DPUSH_HL/DPOP_HL,
; COMPILE_CALL, and COMPILE_WORD from those files).
;
; WHAT THIS ADDS:
;   0=          ( n -- flag )  a proper boolean flag, needed because
;               nothing before Phase 4 produced one — see 0='s own
;               header below for why plain subtraction doesn't work.
;   QBRANCH     runtime support for a conditional compiled branch
;   BRANCH      runtime support for an unconditional compiled branch
;   IF/ELSE/THEN  IMMEDIATE compiling words built on QBRANCH/BRANCH
;   BEGIN/UNTIL   IMMEDIATE compiling words for a post-tested loop
;
; THE COMPILE-TIME STACK TRICK: IF/ELSE/THEN/BEGIN/UNTIL all need to
; remember an address between compile-time steps (where a branch's
; target hole is, so a later word can patch it; or where a loop starts,
; so UNTIL knows where to branch back to). Real Forths -- this project
; included -- reuse the ordinary DATA stack for this bookkeeping rather
; than inventing a third stack. This is safe specifically because
; nothing else touches the data stack while a definition is being
; compiled: every ordinary (non-IMMEDIATE) word between `:` and `;` gets
; COMPILED, not run, so it never pushes or pops anything at compile
; time -- only IMMEDIATE words (these ones, and `;`) ever do, and each
; pushes/pops in a balanced way as long as IF/THEN/BEGIN/UNTIL are
; correctly nested. There's no check that they ARE correctly nested
; (an unmatched IF or UNTIL will leave a stray address on the data
; stack, corrupting whatever real values show up once the surrounding
; definition actually runs) -- see this project's own "no error
; recovery yet" scope note from Phase 3, which still applies here.
;
; HOW A COMPILED BRANCH WORKS: QBRANCH and BRANCH both use the exact
; inline-data idiom core/interp.asm's DOLIT already established: the
; 2-byte branch target is compiled directly after "CALL QBRANCH" (or
; "CALL BRANCH"), and the routine reads it off its OWN return address,
; then corrects that return address before RETurning -- either to just
; past the target (falling through, for QBRANCH's "true" case) or to
; the target itself (branching, for QBRANCH's "false" case, and always
; for BRANCH). See DOLIT's own header in core/interp.asm for the first,
; fuller explanation of this mechanism; nothing about it changes here
; beyond adding the conditional choice of destination.
; ============================================================================

    IFNDEF CORE_CONTROL_ASM
    DEFINE CORE_CONTROL_ASM

; ============================================================================
; 0= ( n -- flag )
; flag is -1 (all bits set, the ANS Forth TRUE convention) if n is
; exactly 0, else 0 (FALSE). Needed because IF and UNTIL both test a
; flag, and nothing before Phase 4 produced a properly-signed one:
; plain subtraction (`a b -`) is 0 exactly when a and b are EQUAL, which
; is backwards from what a "loop until this becomes true" idiom needs.
; ============================================================================
H_ZEROEQUALS:
    DW   H_SEMICOLON
    DB   2, "0", "="
W_ZEROEQUALS:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    or   l
    jr   nz, .nonzero
    ld   hl, -1
    jr   .done
.nonzero:
    ld   hl, 0
.done:
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; QBRANCH — NOT a dictionary word (nothing FINDs it by name; IF/UNTIL
; compile a CALL to it directly, the same way COMPILE_LITERAL compiles
; a CALL to DOLIT). Pops a flag off the DATA stack; if it's 0 (false),
; branches to the 2-byte target compiled right after the CALL that
; reached here; if nonzero (true), falls through to whatever follows
; that 2-byte target instead.
; ============================================================================
QBRANCH:
    pop  hl                   ; hl = address of the inline 2-byte target
    ld   e, (ix+0)
    ld   d, (ix+1)
    inc  ix
    inc  ix                   ; de = the flag, now popped off the data stack
    ld   a, d
    or   e
    jr   nz, .true
    ld   e, (hl)
    inc  hl
    ld   d, (hl)               ; de = the target address
    push de
    ret
.true:
    inc  hl
    inc  hl                   ; skip past the inline target -- fall through
    push hl
    ret

; ============================================================================
; BRANCH — NOT a dictionary word. Unconditional version of QBRANCH:
; always branches to the inline 2-byte target. Used by ELSE to skip
; over the false-branch's code once the true-branch has finished.
; ============================================================================
BRANCH:
    pop  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    push de
    ret

; ============================================================================
; IF ( flag -- )  IMMEDIATE
; Compiles a call to QBRANCH followed by a placeholder target, and
; leaves the placeholder's address on the (compile-time, borrowed data)
; stack for ELSE or THEN to patch once the real target is known.
; ============================================================================
H_IF:
    DW   H_ZEROEQUALS
    DB   $82, "I", "F"        ; length 2, IMMEDIATE
W_IF:
    ld   hl, QBRANCH
    call COMPILE_CALL
    ld   hl, (HERE)            ; address of the placeholder about to be written
    call DPUSH_HL
    ld   hl, 0
    call COMPILE_WORD
    ret

; ============================================================================
; ELSE ( -- )  IMMEDIATE
; Compiles the unconditional branch that skips the false-branch once
; the true-branch finishes, patches IF's placeholder to land HERE (the
; start of the false-branch), and leaves the NEW placeholder (the one
; just compiled) for THEN to patch instead.
; ============================================================================
H_ELSE:
    DW   H_IF
    DB   $84, "E", "L", "S", "E"   ; length 4, IMMEDIATE
W_ELSE:
    ld   hl, BRANCH
    call COMPILE_CALL
    ld   hl, (HERE)             ; this BRANCH's own placeholder address
    push hl                     ; stashed briefly on the Z80 hardware
                                 ; stack -- safe: symmetric push/pop
                                 ; within this one routine's own body,
                                 ; not crossing any CALL/RET boundary
    ld   hl, 0
    call COMPILE_WORD
    call DPOP_HL                ; hl = IF's placeholder address
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    pop  hl                     ; hl = this BRANCH's placeholder address
    call DPUSH_HL                ; leave it for THEN
    ret

; ============================================================================
; THEN ( -- )  IMMEDIATE
; Patches whichever placeholder is on top of the (compile-time) stack
; -- IF's own, if there was no ELSE, or ELSE's -- to land HERE.
; ============================================================================
H_THEN:
    DW   H_ELSE
    DB   $84, "T", "H", "E", "N"   ; length 4, IMMEDIATE
W_THEN:
    call DPOP_HL
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    ret

; ============================================================================
; BEGIN ( -- )  IMMEDIATE
; Remembers HERE (the loop's start) on the (compile-time) stack, for
; UNTIL to compile a branch back to.
; ============================================================================
H_BEGIN:
    DW   H_THEN
    DB   $85, "B", "E", "G", "I", "N"   ; length 5, IMMEDIATE
W_BEGIN:
    ld   hl, (HERE)
    call DPUSH_HL
    ret

; ============================================================================
; UNTIL ( flag -- )  IMMEDIATE
; Compiles a call to QBRANCH targeting the address BEGIN remembered:
; at runtime, if the flag is false, that's a branch back (loop again);
; if true, QBRANCH falls through (the loop ends).
; ============================================================================
H_UNTIL:
    DW   H_BEGIN
    DB   $85, "U", "N", "T", "I", "L"   ; length 5, IMMEDIATE
W_UNTIL:
    ld   hl, QBRANCH
    call COMPILE_CALL
    call DPOP_HL                ; hl = BEGIN's remembered loop-start address
    call COMPILE_WORD
    ret

DICT_LATEST_INIT_P4 EQU H_UNTIL   ; head of the dictionary as of Phase 4;
                                  ; core/interp.asm's own DICT_LATEST_INIT_P3
                                  ; (H_SEMICOLON) stays correct for Phase 3's
                                  ; own smoke ROM, unmodified

    ENDIF
