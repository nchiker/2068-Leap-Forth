; ============================================================================
; core/loadtext.asm -- SAVE-TEXT, VERIFY-TEXT, LOAD-TEXT: plain Forth source over tape
;
; Source text is the portable format (docs/V2/STORAGE_SPEC.md section 6): it is re-parsed and
; compiled when loaded, so a tape loads into any ROM, unlike a LIB image (core/storage.asm). On
; tape (spec section 4): a type-0 header (parameter 1 = STORAGE_NO_AUTOSTART, parameter 2 = the
; length), then the text bytes; tools/tape_gen_forth.py writes the same format.
;
; LOAD-TEXT receives into STORE_START (LOADTEXT_MAX_LEN bytes), which stays resident afterwards as
; the line store (core/recall.asm), and interprets it.
;
; Errors are THROWn as in core/storage.asm (-28 SPACE, -37 any other tape failure; core/tapeword.asm).
; Needs core/dict.asm, core/interp.asm (INTERPRET_NESTED), core/throwcatch.asm, core/recall.asm
; (STORE_TRIM) and kernel/storage/storage.asm. Link fields: a word's DW is DICT_CHAIN_POINT, which the
; including ROM sets (DEFL). Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_LOADTEXT_ASM
    DEFINE CORE_LOADTEXT_ASM

    INCLUDE "core/tapeword.asm"

; The line store (docs/V2/EDITOR_SPEC.md section 3) is plain text, every line ended by CR.
LOADTEXT_MAX_LEN EQU STORE_LIMIT - STORE_START
    ASSERT (STORE_LIMIT & $FF) == 0      ; the room test below looks at the high byte only

; ============================================================================
; STORE_TRIMMED_LEN -- STORE_TRIM (the console line holding the command is not source), then the
; store's length
; Out: BC = DE = the store's length
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_TRIMMED_LEN:
    call STORE_TRIM
    ld   hl, (STORE_END)
    ld   de, -STORE_START
    add  hl, de
    ld   b, h
    ld   c, l
    ld   d, h
    ld   e, l
    ret

; ============================================================================
; SAVE-TEXT ( "name" -- ) -- the line store to tape, less the console line holding this command
; ============================================================================
H_SAVETEXT:
    DW   DICT_CHAIN_POINT
    DB   9, "S","A","V","E","-","T","E","X","T"
W_SAVETEXT:
    call STORAGE_PARSE_NAME
    call STORE_TRIMMED_LEN              ; bc = the store's length
    push ix
    ld   ix, STORE_START
    ld   hl, STORAGE_NO_AUTOSTART       ; parameter 1; parameter 2 (BC) = the length
    xor  a                              ; STORAGE_TYPE_TEXT
    call STORAGE_SAVE
    jp   STORAGE_END

; ============================================================================
; VERIFY-TEXT ( "name" -- ) -- compare a text tape with the line store; the lengths must match
; ============================================================================
H_VERIFYTEXT:
    DW   H_SAVETEXT
    DB   11, "V","E","R","I","F","Y","-","T","E","X","T"
W_VERIFYTEXT:
    call STORAGE_PARSE_NAME
    call STORE_TRIMMED_LEN              ; de = the store's length
    push ix
    ld   hl, STORE_START
    push hl
    push de
    xor  a                              ; STORAGE_TYPE_TEXT
    call STORAGE_FIND
    pop  de
    pop  ix
    jp   c, STORAGE_END
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    or   a
    sbc  hl, de
    jp   nz, STORAGE_REFUSED
    call STORAGE_LOAD_DATA              ; carry clear: verify
    jp   STORAGE_END

; ============================================================================
; LOAD-TEXT ( "name" -- ) -- load a text tape into the store and interpret it
;
; STORE_END = start + length, and a CR is added if the last byte is not CR
; and there is room. INTERPRET_NESTED keeps THROW_ROOT_SP the outer run's, so an error in the loaded
; text (unknown word, uncaught THROW, ABORT) prints its message and unwinds past this routine,
; abandoning the rest of the console line. On success the outer run's SRC_PTR and SRC_END are
; restored and the rest of the line goes on.
; ============================================================================
H_LOADTEXT:
    DW   H_VERIFYTEXT
    DB   9, "L","O","A","D","-","T","E","X","T"
W_LOADTEXT:
    call STORAGE_PARSE_NAME
    call STORE_TRIM                     ; the command line is not source
    push ix
    xor  a                              ; STORAGE_TYPE_TEXT
    call STORAGE_FIND
    jp   c, STORAGE_END
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   hl, LOADTEXT_MAX_LEN
    or   a
    sbc  hl, de
    jp   c, STORAGE_REFUSED
    ld   ix, STORE_START
    scf                                 ; load
    call STORAGE_LOAD_DATA
    jp   c, STORAGE_END
    pop  ix
    ei
    ld   hl, (SRC_END)                  ; the outer run's source pointers survive the nested run
    push hl
    ld   hl, (SRC_PTR)
    push hl
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   hl, STORE_START                ; INTERPRET_NESTED: HL = source, DE = length
    push hl
    add  hl, de                         ; hl = end of the text
    ld   a, d
    or   e
    jr   z, .store_end                  ; an empty tape: nothing to end
    dec  hl
    ld   a, (hl)
    inc  hl
    cp   13
    jr   z, .store_end
    ld   a, h
    cp   STORE_LIMIT / 256
    jr   nc, .store_end                 ; no room for the CR
    ld   (hl), 13
    inc  hl
.store_end:
    ld   (STORE_END), hl
    pop  hl
    call INTERPRET_NESTED
    pop  hl
    ld   (SRC_PTR), hl
    pop  hl
    ld   (SRC_END), hl
    ret


    ENDIF
