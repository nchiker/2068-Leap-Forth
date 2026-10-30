; ============================================================================
; core/dictspace.asm -- HERE, , (comma), C, (c-comma), ALLOT
;
; Needs core/dict.asm (HERE) and core/interp.asm (COMPILE_WORD, COMPILE_BYTE, DICT_ROOM). Link
; fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the
; word extends. Every word here may destroy all registers except IX, IY and SP.
;
; `,` `C,` and a growing ALLOT call DICT_ROOM, which THROWs -8 if HERE plus the size would pass
; DICT_RAM_CEILING - 256, as the defining words do.
; ============================================================================

    IFNDEF CORE_DICTSPACE_ASM
    DEFINE CORE_DICTSPACE_ASM

; ============================================================================
; HERE ( -- addr ) -- the dictionary pointer
; ============================================================================
H_HERE:
    DW   DICT_CHAIN_POINT
    DB   4, "H","E","R","E"
W_HERE:
    ld   hl, (HERE)
    rst RST_DPUSH
    ret

; ============================================================================
; , ( n -- ) -- compile the cell n at HERE (raw, not a literal)
; ============================================================================
H_COMMA:
    DW   H_HERE
    DB   1, ","
W_COMMA:
    ld   hl, 2
    call DICT_ROOM
    rst RST_DPOP
    call COMPILE_WORD
    ret

; ============================================================================
; C, ( n -- ) -- compile the low byte of n at HERE
; ============================================================================
H_CCOMMA:
    DW   H_COMMA
    DB   2, "C", ","
W_CCOMMA:
    ld   hl, 1
    call DICT_ROOM
    rst RST_DPOP
    ld   a, l
    call COMPILE_BYTE
    ret

; ============================================================================
; ALLOT ( n -- ) -- advance HERE by n bytes, writing nothing; a negative n shrinks the dictionary
; ============================================================================
H_ALLOT:
    DW   H_CCOMMA
    DB   5, "A","L","L","O","T"
W_ALLOT:
    rst RST_DPOP                       ; HL = n
    bit  7, h
    call z, DICT_ROOM                  ; only a growing ALLOT is checked
    ld   de, (HERE)
    add  hl, de
    ld   (HERE), hl
    ret

DICT_LATEST_INIT_DICTSPACE EQU H_ALLOT ; the chain head when this is the last file included

    ENDIF
