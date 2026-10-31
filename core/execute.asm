; ============================================================================
; core/execute.asm -- EXECUTE
;
; Needs core/dict.asm. Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets
; (DEFL) to the chain the word extends. Every word here may destroy all registers except IX, IY
; and SP.
;
; The Forth is subroutine-threaded: a code address (what FIND returns) is the routine itself,
; primitive or colon definition alike, so EXECUTE is a jump to it. The address is not validated.
; ============================================================================

    IFNDEF CORE_EXECUTE_ASM
    DEFINE CORE_EXECUTE_ASM

; ============================================================================
; EXECUTE ( xt -- ) -- run the code at xt
; ============================================================================
H_EXECUTE:
    DW   DICT_CHAIN_POINT
    DB   7, "E", "X", "E", "C", "U", "T", "E"
W_EXECUTE:
    rst RST_DPOP                       ; HL = xt
    jp   (hl)                          ; a jump, not a call: its RET returns to EXECUTE's caller


    ENDIF
