; ============================================================================
; core/portio.asm -- IN and OUT: raw Z80 port access
;
; Both words load the port number into BC and use IN r,(C) / OUT (C),r, so the whole 16-bit port space is
; reachable, not just the low 256. Nothing is checked: the program can write any port, as in BASIC.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_PORTIO_ASM
    DEFINE CORE_PORTIO_ASM

; ============================================================================
; IN ( port -- value ) -- read one byte from a 16-bit port
; ============================================================================
H_IN:
    DW   DICT_CHAIN_POINT
    DB   2, "I","N"
W_IN:
    rst RST_DPOP            ; hl = port
    ld   b, h
    ld   c, l                 ; bc = port -- full 16-bit form
    in   a, (c)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    ret

; ============================================================================
; OUT ( value port -- ) -- write the low byte of value to a 16-bit port
; ============================================================================
H_OUT:
    DW   H_IN
    DB   3, "O","U","T"
W_OUT:
    rst RST_DPOP            ; hl = port
    ld   b, h
    ld   c, l                 ; bc = port
    rst RST_DPOP             ; hl = value
    ld   a, l
    out  (c), a
    ret


    ENDIF
