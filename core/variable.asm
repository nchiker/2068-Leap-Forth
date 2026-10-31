; ============================================================================
; core/variable.asm -- VARIABLE and CONSTANT
;
; Needs core/dict.asm and core/interp.asm (COMPILE_LITERAL, COMPILE_BYTE, W_WORD, DICT_ROOM0).
; Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain
; the word extends. Every word here may destroy all registers except IX, IY and SP.
;
; Neither word uses CREATE / DOES>. The code of a VARIABLE is a compiled literal (the DOLIT idiom
; of core/interp.asm) pushing its cell's address, then a RET; a CONSTANT's is the same literal
; holding the value. The RET is needed because the code does not fall through into more compiled
; code: for a VARIABLE the next bytes are its data cell. VAR_HEADER and VAR_END are shared with
; FVARIABLE and FCONSTANT (core/fpstack.asm). They build the header with W_COLON's scratch cells
; (WORD_SRC_ADDR, NEW_HEADER_ADDR), never concurrently with `:`.
; ============================================================================

    IFNDEF CORE_VARIABLE_ASM
    DEFINE CORE_VARIABLE_ASM

; ============================================================================
; VAR_HEADER -- the header of a new word: parse the next word, build LINK + counted name at HERE.
; Does not touch LATEST (VAR_END does, once the body is compiled).
; Out: NEW_HEADER_ADDR = the header, HERE = past the name, where the code starts
; Destroys: AF, BC, DE, HL
; ============================================================================
VAR_HEADER:
    call W_WORD
    rst  RST_DPOP                 ; HL -> the counted name
    ex   de, hl                   ; DE -> the name
    ld   hl, (HERE)
    ld   (NEW_HEADER_ADDR), hl
    ld   bc, (LATEST)
    ld   (hl), c
    inc  hl
    ld   (hl), b
    inc  hl
    ex   de, hl                   ; HL -> the name, DE -> where it goes
    ld   c, (hl)
    ld   b, 0
    inc  bc                       ; the length byte and the name
    ldir
    ld   (HERE), de
    ret

; ============================================================================
; VAR_END -- compile the RET that ends the word's code and link the word in
; Out: LATEST = NEW_HEADER_ADDR
; Destroys: AF, HL
; ============================================================================
VAR_END:
    ld   a, $C9                   ; RET
    call COMPILE_BYTE
    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; VARIABLE ( "name" -- ) -- define name ( -- addr ), addr of a fresh zeroed 2-byte cell
; VARIABLE_N -- the same with A zeroed data bytes instead of 2 (FVARIABLE: 5)
; ============================================================================
H_VARIABLE:
    DW   DICT_CHAIN_POINT
    DB   8, "V", "A", "R", "I", "A", "B", "L", "E"
W_VARIABLE:
    ld   a, 2
VARIABLE_N:
    push af                       ; the data size: W_WORD and the header code use every register
    call DICT_ROOM0
    call VAR_HEADER
    ld   hl, (HERE)
    ld   de, 6                    ; the 5-byte literal (CALL DOLIT + target) and the RET: the data
    add  hl, de                   ; cell follows both
    call COMPILE_LITERAL          ; the address of the data cell
    call VAR_END
    pop  af
    ld   b, a
    ld   hl, (HERE)               ; HERE = the data cell
    xor  a
.zero:
    ld   (hl), a
    inc  hl
    djnz .zero
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
    push hl                        ; the value across the name parsing: W_WORD only touches the
                                   ; IX data stack, never SP
    call VAR_HEADER
    pop  hl
    call COMPILE_LITERAL
    jr   VAR_END


    ENDIF
