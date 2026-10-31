; ============================================================================
; core/create.asm -- CREATE
;
; Needs core/dict.asm, core/interp.asm (W_WORD, WORD_SRC_ADDR, NEW_HEADER_ADDR, COMPILE_CALL,
; COMPILE_BYTE, DICT_ROOM0). Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM
; sets (DEFL) to the chain the word extends. Every word here may destroy all registers except IX,
; IY and SP. Its header building repeats core/variable.asm's.
;
; CREATE compiles a patchable 6-byte run time at the new word's code address:
;     CALL DODOES              ; $CD, DODOES
;     JP   CREATE_DEFAULT_RET  ; $C3, target
;   <data field starts here>
; CALL pushed the address of the JP (JP_ADDR). DODOES pushes JP_ADDR + 3, the data field, on the
; data stack and then enters `jp (hl)` at JP_ADDR, so the CPU executes whatever JP is there now
; without DODOES reading its operand. Until DOES> (core/does.asm) rewrites those 2 operand bytes,
; the JP goes to CREATE_DEFAULT_RET, a RET: the word just pushes its data field. Nothing is
; ALLOTted; the caller reserves the field with ALLOT or `,`.
; ============================================================================

    IFNDEF CORE_CREATE_ASM
    DEFINE CORE_CREATE_ASM

; ============================================================================
; CREATE_DEFAULT_RET -- not a dictionary word: where every fresh CREATEd word's JP goes until
; DOES> repoints it (DODOES has already pushed the data field)
; ============================================================================
CREATE_DEFAULT_RET:
    ret

; ============================================================================
; DODOES -- not a dictionary word: what the CALL in a CREATEd word's run time calls
; In:  the return address = JP_ADDR, the address of the JP that follows the CALL
; Out: ( -- data field ), then continues at the JP at JP_ADDR
; Destroys: AF, DE, HL
; ============================================================================
DODOES:
    pop  hl                  ; HL = JP_ADDR
    push hl                   ; kept while HL is reused
    ld   de, 3
    add  hl, de                 ; the data field, after the 3-byte JP
    rst RST_DPUSH
    pop  hl                         ; JP_ADDR again
    jp   (hl)                        ; execute the JP in place (a jump to HL, not a memory read)

; ============================================================================
; CREATE ( "name" -- ) -- define name ( -- addr ), addr of its data field (the bytes at HERE)
; ============================================================================
H_CREATE:
    DW   DICT_CHAIN_POINT
    DB   6, "C","R","E","A","T","E"
W_CREATE:
    call DICT_ROOM0
    call W_WORD
    rst RST_DPOP
    ld   (WORD_SRC_ADDR), hl

    ld   de, (HERE)
    ld   (NEW_HEADER_ADDR), de
    ld   hl, (LATEST)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (WORD_SRC_ADDR)
    ld   a, (hl)                  ; the name length
    ld   (de), a
    inc  de
    inc  hl                       ; HL -> the first character
    ld   b, a
    ld   a, b
    or   a
    jr   z, .namedone
.namecopy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .namecopy
.namedone:
    ld   (HERE), de                ; the code address

    ld   hl, DODOES
    call COMPILE_CALL               ; CALL DODOES
    ld   a, $C3                      ; JP
    call COMPILE_BYTE
    ld   hl, CREATE_DEFAULT_RET
    ld   a, l
    call COMPILE_BYTE
    ld   hl, CREATE_DEFAULT_RET      ; reloaded: COMPILE_BYTE destroys HL
    ld   a, h
    call COMPILE_BYTE                ; HERE is now the data field

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret


    ENDIF
