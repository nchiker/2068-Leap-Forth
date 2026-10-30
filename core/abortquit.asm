; ============================================================================
; core/abortquit.asm -- ABORT and QUIT
;
; Needs core/dict.asm (DSTACK_TOP), core/interp.asm with THROW_CATCH_ENABLED (THROW_ROOT_SP,
; INTERP_ERROR_FLAG), the float stack (FSTACK_TOP), core/doloop.asm (LEAVE_DEPTH) and
; core/throwcatch.asm (CATCH_DEPTH). Link fields: a word's DW is DICT_CHAIN_POINT, which the
; including ROM sets (DEFL) to the chain the word extends. Every word here may destroy all
; registers except IX, IY and SP.
;
; Both return to a fresh prompt the way an uncaught THROW does: SP is reloaded from
; THROW_ROOT_SP, which INTERPRET_RUN saved on entry, discarding every nested call, and the final
; RET returns to INTERPRET_RUN's caller. Neither prints anything. They also zero CATCH_DEPTH and
; LEAVE_DEPTH, whose frames the SP reload has discarded (stale counts would put the next CATCH or
; DO loop in the wrong frame slot), and set INTERP_ERROR_FLAG, so the line that ran them prints no
; "OK". They differ only in the stacks: ABORT empties the data and float stacks, QUIT leaves them.
; ============================================================================

    IFNDEF CORE_ABORTQUIT_ASM
    DEFINE CORE_ABORTQUIT_ASM

; ============================================================================
; ABORT ( -- ) -- empty both stacks and return to the prompt
; ============================================================================
H_ABORT:
    DW   DICT_CHAIN_POINT
    DB   5, "A","B","O","R","T"
W_ABORT:
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a
    ld   (LEAVE_DEPTH), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a
    ld   sp, (THROW_ROOT_SP)           ; the last change before the RET
    ret

; ============================================================================
; QUIT ( -- ) -- return to the prompt, leaving the stacks as they are
; ============================================================================
H_QUIT:
    DW   H_ABORT
    DB   4, "Q","U","I","T"
W_QUIT:
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a
    ld   (LEAVE_DEPTH), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a
    ld   sp, (THROW_ROOT_SP)
    ret

DICT_LATEST_INIT_ABORTQUIT EQU H_QUIT  ; the chain head when this is the last file included

    ENDIF
