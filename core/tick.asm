; ============================================================================
; core/tick.asm -- ' (tick), the execution token of the next word
;
; Needs core/dict.asm, core/interp.asm (W_WORD, FIND) and core/throwcatch.asm (W_THROW). Link
; fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the
; word extends. Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_TICK_ASM
    DEFINE CORE_TICK_ASM

; ============================================================================
; ' ( "name" -- xt ) -- the code address of the next input word, not executed; an undefined
; word is THROW -13
; ============================================================================
H_TICK:
    DW   DICT_CHAIN_POINT
    DB   1, "'"
W_TICK:
    call W_WORD
    call FIND
    rst RST_DPOP                       ; HL = the found flag
    ld   a, h
    or   l
    jr   nz, .found
    call W_DROP                        ; FIND left the search address: drop it before throwing
    ld   hl, -13                       ; undefined word
    rst RST_DPUSH
    jp   W_THROW
.found:
    rst RST_DPOP                       ; discard the immediate flag: the code address stays
    ret


    ENDIF
