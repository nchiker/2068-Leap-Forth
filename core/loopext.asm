; ============================================================================
; core/loopext.asm — Phase 49: EXIT, J
;
; Builds on core/dict.asm, core/interp.asm (COMPILE_BYTE, DPUSH_HL) AND
; core/doloop.asm specifically (LEAVE_DEPTH, and the hardware-stack loop
; frame layout DO_RT/LOOP_RT/I already establish) — all three must be
; INCLUDEd first. A new, small file rather than editing core/doloop.asm
; itself, matching this project's own standing practice (see that
; file's own header, and core/loop.asm's, on why a shared file already
; INCLUDEd by several ROMs is extended by addition, not edited).
;
; ============================================================================
; EXIT ( -- )  IMMEDIATE
;
; Compiles an early return from the CURRENTLY-COMPILING colon
; definition, exactly like `;` compiles its own closing RET
; (core/interp.asm's W_SEMICOLON) — except EXIT does NOT switch STATE
; back to interpret and does NOT end the header; the compiler keeps
; going right after it, so any code textually following EXIT still gets
; compiled, it's just dead: RET means everything after it in THIS
; definition's own straight-line CALL chain never runs.
;
; THE REAL SUBTLETY (the thing this file's own commit message was asked
; to investigate before writing a line of code): what if EXIT is
; compiled INSIDE a still-open DO...LOOP body? core/doloop.asm's own
; header explains DO_RT pushes the loop's (limit, index) pair onto the
; REAL Z80 hardware stack (SP) -- the same stack every CALL/RET in this
; whole subroutine-threaded project already uses for return addresses
; -- and LOOP_RT/+LOOP_RT/LEAVE_RT are the only three routines that ever
; pop them back off, always exactly once, always right before branching
; back to DO or falling through past the loop. A bare RET compiled
; mid-body, with an open loop's (limit, index) still sitting on top of
; the REAL return address underneath them, would NOT return to the
; caller -- it would pop the loop's own CURRENT INDEX off the hardware
; stack, misread it as a return address, and jump into garbage. This is
; exactly the same hazard core/doloop.asm's own header already
; documents LEAVE hit and fixed (LEAVE_RT explicitly discards the
; current loop's index/limit before branching) -- EXIT needs the exact
; same discipline, generalized: EXIT can fire from ANY nesting depth,
; so it must discard EVERY currently-open loop's (limit, index) pair
; between it and the definition's own entry point, not just the
; innermost one LEAVE_RT handles.
;
; THE FIX: at the moment EXIT is COMPILED (not run), LEAVE_DEPTH
; (core/doloop.asm) already holds exactly the count of DO loops open
; at that point in the definition being compiled -- DO increments it,
; LOOP/+LOOP decrement it back, so its value at any compile-time
; instant IS the current nesting depth. EXIT compiles LEAVE_DEPTH pairs
; of `POP HL` ($E1, discarding one 16-bit hardware-stack cell each,
; content irrelevant since it's being discarded either way -- unlike
; LEAVE_RT, EXIT never needs to READ what it's discarding) immediately
; before the closing RET, unwinding every open loop's own frame in one
; pass. BEGIN/UNTIL and BEGIN/WHILE/REPEAT (core/control.asm/core/
; loop.asm) need NO such handling: both compile only conditional/
; unconditional BRANCH sequences on the borrowed COMPILE-TIME (data)
; stack, never touching the real hardware stack at runtime, so nothing
; needs unwinding there regardless of how many are open.
;
; VERIFIED, not just reasoned about: rom/forth_smoke_p49.asm's own
; checkpoint fires EXIT from inside an open DO...LOOP one level deep and
; confirms both that the loop actually stopped early (the expected
; partial accumulator value) AND that control returned correctly to the
; caller (the checkpoint immediately after it still runs).
; ============================================================================

    IFNDEF CORE_LOOPEXT_ASM
    DEFINE CORE_LOOPEXT_ASM

H_EXIT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   $84, "E","X","I","T"   ; length 4, IMMEDIATE
W_EXIT:
    ld   a, (LEAVE_DEPTH)
    or   a
    jr   z, .compileret
    ld   b, a                    ; b = number of currently-open loop
                                   ; frames to unwind
    ld   a, $E1                   ; Z80 POP HL opcode -- discards one
                                   ; hardware-stack cell, value unused
.discardloop:
    push bc
    call COMPILE_BYTE             ; discards this loop's index
    call COMPILE_BYTE             ; discards this loop's limit
    pop  bc
    djnz .discardloop
.compileret:
    ld   a, $C9                   ; Z80 RET opcode -- same byte
                                   ; core/interp.asm's own W_SEMICOLON
                                   ; compiles to end a definition
    call COMPILE_BYTE
    ret

; ============================================================================
; J ( -- n )
;
; Like I (core/doloop.asm), but reaches the loop ONE LEVEL OUT: inside a
; nested DO...LOOP, I gives the innermost loop's own index. Found by
; reading DO_RT/LOOP_RT/I directly rather than guessing: each DO pushes
; (limit, index) as ONE 4-byte frame, index on top -- so at any point
; inside a loop's own body (before that body's own next CALL), the
; hardware stack top-down reads: [innermost index][innermost limit]
; [next-outer index][next-outer limit]... I's own comment already
; establishes the pattern for the innermost frame: at I's OWN entry
; (after the `call W_I` that reached it pushed a return address), SP+2/
; SP+3 is the innermost index, because SP+0/SP+1 is I's own return
; address. J needs the SAME thing one frame further out: skip I's own
; return address (2 bytes), skip the innermost loop's whole (index,
; limit) frame (4 bytes), landing on SP+6/SP+7 -- the enclosing loop's
; own index. Exactly ADD HL,SP then +6 instead of I's own +2, same
; "non-destructive peek" via ADD HL,SP (never disturbs SP itself).
;
; VERIFIED against a real 2-deep nested loop with DELIBERATELY UNEQUAL
; bounds (rom/forth_smoke_p49.asm) -- equal bounds on both loops would
; make I and J's own running sums coincidentally equal by symmetry, so
; that ROM's own checkpoint specifically avoids that trap (documented
; in its own header) and would catch J silently reading the SAME value
; as I (e.g. a wrong hardware-stack offset landing back on the inner
; frame instead of the outer one).
; ============================================================================
H_J:
    DW   H_EXIT
    DB   1, "J"
W_J:
    ld   hl, 0
    add  hl, sp
    ld   de, 6
    add  hl, de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    call DPUSH_HL
    ret

DICT_LATEST_INIT_LOOPEXT EQU H_J   ; head of the dictionary once this
                                    ; file's own words are included

    ENDIF
