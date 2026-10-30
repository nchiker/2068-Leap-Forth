; ============================================================================
; core/free.asm -- FREE, the dictionary space remaining
;
; Needs core/dict.asm (HERE, DICT_RAM_CEILING). Link fields: a word's DW is DICT_CHAIN_POINT, which
; the including ROM sets (DEFL) to the chain the word extends. Every word here may destroy all
; registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_FREE_ASM
    DEFINE CORE_FREE_ASM

; ============================================================================
; FREE ( -- n ) -- the bytes remaining before HERE reaches DICT_RAM_CEILING
; ============================================================================
H_FREE:
    DW   DICT_CHAIN_POINT
    DB   4, "F","R","E","E"
W_FREE:
    ld   hl, DICT_RAM_CEILING
    ld   de, (HERE)
    or   a
    sbc  hl, de                        ; HL = ceiling - HERE
    rst RST_DPUSH
    ret

DICT_LATEST_INIT_FREE EQU H_FREE       ; the chain head when this is the last file included

    ENDIF
