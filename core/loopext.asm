; ============================================================================
; core/loopext.asm -- EXIT and J
;
; Needs core/dict.asm, core/interp.asm (COMPILE_BYTE) and core/doloop.asm (LEAVE_DEPTH, and the
; loop frame layout DO_RT, LOOP_RT and I establish on the hardware stack: limit, then index on
; top). Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the
; chain the word extends. Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_LOOPEXT_ASM
    DEFINE CORE_LOOPEXT_ASM

; ============================================================================
; EXIT ( -- ) IMMEDIATE -- compile an early return from the definition being compiled (a RET, as
; `;` does, but STATE stays and compiling goes on)
;
; An open DO loop keeps its (limit, index) frame on the hardware stack above the return address,
; so a bare RET there would pop the index as the return address. LEAVE_DEPTH holds the number of
; DO loops open at this point of the definition; EXIT compiles that many pairs of POP HL ($E1),
; discarding every open frame, before the RET. BEGIN loops use no run-time stack: nothing to do.
; ============================================================================
H_EXIT:
    DW   DICT_CHAIN_POINT
    DB   $84, "E","X","I","T"
W_EXIT:
    call COMPILE_ONLY_CHECK            ; refuses at the prompt (STATE = 0)
    ld   a, (LEAVE_DEPTH)
    or   a
    jr   z, .compileret
    ld   b, a                          ; B = the open loop frames to unwind
    ld   a, $E1                        ; POP HL
.discardloop:
    push bc
    call COMPILE_BYTE                  ; discards this frame's index
    call COMPILE_BYTE                  ; and its limit
    pop  bc
    djnz .discardloop
.compileret:
    ld   a, $C9                        ; RET
    call COMPILE_BYTE
    ret

; ============================================================================
; J ( -- n ) -- the index of the loop enclosing the innermost one (I's counterpart, one frame out)
; ============================================================================
H_J:
    DW   H_EXIT
    DB   1, "J"
W_J:
    ld   hl, 0
    add  hl, sp
    ld   de, 6                         ; SP+0 is J's return address, then the innermost index and
    add  hl, de                        ; limit (4 bytes): SP+6 is the enclosing index
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    rst RST_DPUSH
    ret


    ENDIF
