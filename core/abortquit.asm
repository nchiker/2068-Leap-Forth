; ============================================================================
; core/abortquit.asm -- ABORT and QUIT
;
; Needs core/dict.asm (DSTACK_TOP), the float stack (FSTACK_TOP) and the including ROM's
; REPORT_INTERP_ERROR. Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets
; (DEFL) to the chain the word extends. Every word here may destroy all registers except IX, IY and
; SP.
;
; Both return to a fresh prompt the way an uncaught THROW does: SP is reloaded from
; THROW_ROOT_SP, which INTERPRET_RUN saved on entry, discarding every nested call, and the final
; RET returns to INTERPRET_RUN's caller: they end in REPORT_INTERP_ERROR (rom/forth_boot.asm), with
; LAST_ERROR -1 (ABORT) or -56 (QUIT), as ANS numbers them. Neither prints anything. CATCH_DEPTH goes
; to 0 there, and INTERP_ERROR_FLAG to 1, so the line that ran them prints no "OK" and the console
; closes what it left open (COLON_DROP: LEAVE_DEPTH, the `:` definition). They differ only in the
; stacks: ABORT empties the data and float stacks, QUIT leaves them.
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
    ld   hl, -1
    jp   REPORT_INTERP_ERROR

; ============================================================================
; QUIT ( -- ) -- return to the prompt, leaving the stacks as they are
; ============================================================================
H_QUIT:
    DW   H_ABORT
    DB   4, "Q","U","I","T"
W_QUIT:
    ld   hl, -56
    jp   REPORT_INTERP_ERROR


    ENDIF
