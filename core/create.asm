; ============================================================================
; core/create.asm -- CREATE
;
; Needs core/dict.asm, core/interp.asm (HEADER_BUILD, HEADER_LINK, COMPILE_CALL, COMPILE_BYTE,
; COMPILE_WORD, DICT_ROOM0). Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM
; sets (DEFL) to the chain the word extends. Every word here may destroy all registers except IX,
; IY and SP.
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
    call HEADER_BUILD
    ld   hl, DODOES
    call COMPILE_CALL               ; CALL DODOES
    ld   a, $C3                      ; JP
    call COMPILE_BYTE
    ld   hl, CREATE_DEFAULT_RET
    call COMPILE_WORD               ; HERE is now the data field
    jp   HEADER_LINK


    ENDIF
