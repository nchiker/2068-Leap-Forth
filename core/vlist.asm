; ============================================================================
; core/vlist.asm -- VLIST, every word name in the dictionary
;
; Needs core/dict.asm (LATEST), core/print.asm and core/outwords.asm (W_EMIT, W_SPACE). Link
; fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the
; word extends. Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_VLIST_ASM
    DEFINE CORE_VLIST_ASM

; ============================================================================
; VLIST ( -- ) -- print every name, newest first, to the oldest ROM word (LINK = 0), each
; followed by a space; W_EMIT does the wrapping
; ============================================================================
H_VLIST:
    DW   DICT_CHAIN_POINT
    DB   5, "V","L","I","S","T"
W_VLIST:
    ld   hl, (LATEST)
.wordloop:
    ld   a, h
    or   l
    ret  z                             ; past the oldest entry
    push hl                            ; this entry (its LINK field is the first word)
    ld   de, 2
    add  hl, de                        ; HL -> LENFLAGS
    ld   a, (hl)
    and  $1F                           ; the name length (bit 7 is IMMEDIATE)
    ld   b, a                          ; never 0: DJNZ below runs at least once
    inc  hl                            ; HL -> the first character
.charloop:
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .charloop
    call W_SPACE
    pop  hl                            ; this entry again
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                       ; DE = LINK, the next older entry
    ex   de, hl
    jr   .wordloop


    ENDIF
