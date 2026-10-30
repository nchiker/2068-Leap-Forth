; ============================================================================
; core/loadtext.asm -- SAVE-TEXT, VERIFY-TEXT, LOAD-TEXT: plain Forth source over tape
;
; Rebuilt in audit step S against docs/V2/STORAGE_SPEC.md (section 6). Source text is the
; portable format: it is re-parsed and compiled when loaded, so a tape loads into any ROM, unlike
; a LIB image (core/storage.asm). On tape (spec section 4): a type-0 header (parameter 1 =
; STORAGE_NO_AUTOSTART, parameter 2 = the length), then the text bytes (the format V1 used, which is
; not a requirement: spec D2) and the format tools/tape_gen_forth.py writes.
;
; LOAD-TEXT receives into STORE_START = LOADTEXT_BUF (LOADTEXT_MAX_LEN bytes from DICT_RAM_CEILING up),
; which stays resident afterwards as the line store (core/recall.asm), and interprets it.
;
; Errors are THROWn as in core/storage.asm (-28 SPACE, -37 any other tape failure; core/tapeword.asm).
; Needs core/dict.asm, core/interp.asm (INTERPRET_RUN), core/throwcatch.asm and
; kernel/storage/storage.asm first.
; ============================================================================

    IFNDEF CORE_LOADTEXT_ASM
    DEFINE CORE_LOADTEXT_ASM

    INCLUDE "core/tapeword.asm"

; ---- The line store (audit step E, docs/V2/EDITOR_SPEC.md section 3): plain text, every line ended by CR. ----
LOADTEXT_MAX_LEN EQU STORE_LIMIT - STORE_START
    ASSERT (STORE_LIMIT & $FF) == 0   ; LOAD-TEXT's room test below looks at the high byte only

; ============================================================================
; STORE_TRIMMED_LEN -- STORE_TRIM (core/recall.asm: the console line holding the command is not source), then
; BC = DE = the store's length. A ROM without core/recall.asm defines STORE_TRIM as a bare RET.
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
; SAVE-TEXT ( "name" -- ) -- the line store to tape (EDITOR_SPEC.md section 3: the store is the one source;
; the console line holding this command is trimmed off first, STORE_TRIM)
; ============================================================================
H_SAVETEXT:
    DW   DICT_CHAIN_POINT               ; the including ROM sets this (DEFL)
    DB   9, "S","A","V","E","-","T","E","X","T"
W_SAVETEXT:
    call STORAGE_PARSE_NAME
    call STORE_TRIMMED_LEN              ; bc = the store's length
    push ix
    ld   ix, STORE_START
    ld   hl, STORAGE_NO_AUTOSTART       ; parameter 1; parameter 2 (bc): the length, as V1 wrote it
    xor  a                              ; STORAGE_TYPE_TEXT
    call STORAGE_SAVE
    jp   STORAGE_END

; ============================================================================
; VERIFY-TEXT ( "name" -- ) -- compare a text tape with the line store (its length must be the store's)
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
; Product build (TRACK_STORE_END): STORE_END = start + length, then a CR is added if the last byte is not
; CR and there is room. The text is interpreted by INTERPRET_NESTED (core/interp.asm), so THROW_ROOT_SP
; stays the outer run's: an error in the loaded text (unknown word, uncaught THROW, ABORT) unwinds, past
; this routine, to the outermost caller after printing its usual message -- the rest of the console line
; is abandoned with it. On success the outer run's SRC_PTR/SRC_END (just past the name) are restored and
; the rest of the line goes on.
; ============================================================================
H_LOADTEXT:
    DW   H_VERIFYTEXT
    DB   9, "L","O","A","D","-","T","E","X","T"
W_LOADTEXT:
    call STORAGE_PARSE_NAME
    call STORE_TRIM                     ; the command line is not source (core/recall.asm)
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
    ; TRACK_STORE_END: only rom/forth_boot.asm DEFINEs it, the one ROM with core/recall.asm
    ; (STORE_END's only reader); other ROMs skip the bookkeeping.
    IFDEF TRACK_STORE_END
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
    ENDIF
    call INTERPRET_NESTED
    pop  hl
    ld   (SRC_PTR), hl
    pop  hl
    ld   (SRC_END), hl
    ret

DICT_LATEST_INIT_LOADTEXT EQU H_LOADTEXT   ; head of the dictionary once this file is the last one
                                           ; INCLUDEd

    ENDIF
