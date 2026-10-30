; ============================================================================
; core/outwords.asm -- CR, SPACE, SPACES: output shorthands
;
; Needs core/print.asm (W_EMIT). SPACES does not validate n: 0 prints nothing, a negative n counts down
; through about 65536 spaces.
; SPACES keeps its counter in memory (SPACES_COUNT), not in BC or HL: W_EMIT loads B and C for
; GFX_PUTCHAR and pops HL, so no register survives a call to W_SPACE.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_OUTWORDS_ASM
    DEFINE CORE_OUTWORDS_ASM

; ============================================================================
; CR ( -- ) -- 13 EMIT
; ============================================================================
H_CR:
    DW   DICT_CHAIN_POINT
    DB   2, "C","R"
W_CR:
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT
    ret

; ============================================================================
; SPACE ( -- ) -- 32 EMIT
; ============================================================================
H_SPACE:
    DW   H_CR
    DB   5, "S","P","A","C","E"
W_SPACE:
    ld   hl, 32
    rst RST_DPUSH
    call W_EMIT
    ret

; ============================================================================
; SPACES ( n -- ) -- print n spaces
; ============================================================================
H_SPACES:
    DW   H_SPACE
    DB   6, "S","P","A","C","E","S"
W_SPACES:
    rst RST_DPOP            ; hl = n
    ld   (SPACES_COUNT), hl
.loop:
    ld   hl, (SPACES_COUNT)
    ld   a, h
    or   l
    ret  z
    dec  hl
    ld   (SPACES_COUNT), hl   ; stored back before W_SPACE, which destroys HL
    call W_SPACE
    jr   .loop


    ENDIF
