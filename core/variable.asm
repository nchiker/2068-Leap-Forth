; ============================================================================
; core/variable.asm -- VARIABLE and CONSTANT
;
; Needs core/dict.asm and core/interp.asm (COMPILE_LITERAL, DICT_ROOM, HEADER_BUILD, HEADER_END).
; Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain
; the word extends. Every word here may destroy all registers except IX, IY and SP.
;
; Neither word uses CREATE / DOES>. The code of a VARIABLE is a compiled literal (the DOLIT idiom
; of core/interp.asm) pushing its data's address, then a RET; a CONSTANT's is the same literal
; holding the value. The RET is needed because the code does not fall through into more compiled
; code: for a VARIABLE the next bytes are its data. VARIABLE_N is also FVARIABLE (core/fpstack.asm),
; ARRAY (core/array.asm) and STRING (core/string.asm), with their data sizes.
; ============================================================================

    IFNDEF CORE_VARIABLE_ASM
    DEFINE CORE_VARIABLE_ASM

; ============================================================================
; VARIABLE ( "name" -- ) -- define name ( -- addr ), addr of a fresh zeroed 2-byte cell
; VARIABLE_N -- the same with BC zeroed data bytes (FVARIABLE 5, ARRAY 2n, STRING n + 1); the data
; must fit below the dictionary's ceiling guard (DICT_ROOM; a caller saturates a size that wrapped)
; ============================================================================
H_VARIABLE:
    DW   DICT_CHAIN_POINT
    DB   8, "V", "A", "R", "I", "A", "B", "L", "E"
W_VARIABLE:
    ld   bc, 2
VARIABLE_N:
    ld   h, b
    ld   l, c
    call DICT_ROOM
    push hl                       ; the data size: the header code uses every register
    call HEADER_BUILD
    ld   hl, (HERE)
    ld   de, 6                    ; the 5-byte literal (CALL DOLIT + target) and the RET: the data
    add  hl, de                   ; follows both
    call COMPILE_LITERAL          ; the address of the data
    call HEADER_END
    pop  bc
    ld   hl, (HERE)               ; HERE = the data
.zero:
    ld   a, b
    or   c
    jr   z, .done
    ld   (hl), 0
    inc  hl
    dec  bc
    jr   .zero
.done:
    ld   (HERE), hl
    ret

; ============================================================================
; CONSTANT ( n "name" -- ) -- define name ( -- n )
; ============================================================================
H_CONSTANT:
    DW   H_VARIABLE
    DB   8, "C", "O", "N", "S", "T", "A", "N", "T"
W_CONSTANT:
    call DICT_ROOM0
    rst RST_DPOP
    push hl                        ; the value across the name parsing: WORD_NAME only touches the
                                   ; IX data stack, never SP
    call HEADER_BUILD
    pop  hl
    call COMPILE_LITERAL
    jp   HEADER_END


    ENDIF
