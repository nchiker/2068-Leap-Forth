; ============================================================================
; core/does.asm -- DOES>
;
; Needs core/dict.asm (LATEST) and core/create.asm: DOES> patches the 6-byte `CALL DODOES / JP
; CREATE_DEFAULT_RET` shape that CREATE compiles. Link fields: a word's DW is DICT_CHAIN_POINT,
; which the including ROM sets (DEFL) to the chain the word extends. Every word here may destroy
; all registers except IX, IY and SP.
;
; DOES> is a plain, non-immediate word, compiled into a defining word's body:
;     : CONST CREATE , DOES> @ ;      5 CONST FIVE      FIVE . prints 5
; It runs when CONST runs, not when FIVE does, and patches the word CREATE just built (LATEST).
; ============================================================================

    IFNDEF CORE_DOES_ASM
    DEFINE CORE_DOES_ASM

; ============================================================================
; DOES> ( -- ) -- make the latest CREATEd word run the code after DOES> in the defining word, and
; end the defining word there
;
; The CALL to DOES> pushed the address of the code that follows it (the action), which is popped
; into BC. The patch site is the JP's operand in the new word's code: header + 3 + name length
; (the code address, as FIND computes it) + 4 (CALL DODOES, 3, and the JP opcode). Then the
; defining word's own return address is popped and jumped to: the action part is for the new
; word's later runs, never for the defining word's.
; ============================================================================
H_DOES:
    DW   DICT_CHAIN_POINT
    DB   5, "D","O","E","S",">"
W_DOES:
    pop  bc                       ; BC = the action address
    ld   hl, (LATEST)
    ld   de, 2
    add  hl, de                   ; HL -> LENFLAGS
    ld   a, (hl)
    and  $1F                      ; the name length (bit 7 is IMMEDIATE)
    inc  hl                       ; HL -> the first name character, header + 3
    ld   e, a
    ld   d, 0
    add  hl, de                   ; HL = the code address
    ld   de, 4
    add  hl, de                   ; the JP's operand
    ld   (hl), c
    inc  hl
    ld   (hl), b
    pop  hl                       ; HL = the defining word's return address
    jp   (hl)

DICT_LATEST_INIT_DOES EQU H_DOES       ; the chain head when this is the last file included

    ENDIF
