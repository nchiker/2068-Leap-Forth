; ============================================================================
; core/loadtext.asm -- SAVE-TEXT, VERIFY-TEXT, LOAD-TEXT: plain Forth source over tape
;
; Rebuilt in audit step S against docs/V2/STORAGE_SPEC.md (section 6). Source text is the
; portable format: it is re-parsed and compiled when loaded, so a tape loads into any ROM, unlike
; a LIB image (core/storage.asm). On tape (spec section 4): a type-0 header (parameter 1 =
; STORAGE_NO_AUTOSTART, parameter 2 = the length), then the text bytes (the format V1 used, which is
; not a requirement: spec D2) and the format tools/tape_gen_forth.py writes.
;
; LOAD-TEXT receives into STORE_START = LOADTEXT_BUF (the top LOADTEXT_MAX_LEN bytes below DICT_RAM_CEILING),
; which stays resident afterwards as the line store (core/recall.asm), and interprets it.
;
; Errors are THROWn as in core/storage.asm (-28 SPACE, -37 any other tape failure; core/tapeword.asm).
; Needs core/dict.asm, core/interp.asm (INTERPRET_RUN), core/throwcatch.asm and
; kernel/storage/storage.asm first.
; ============================================================================

    IFNDEF CORE_LOADTEXT_ASM
    DEFINE CORE_LOADTEXT_ASM

    INCLUDE "core/tapeword.asm"

; ---- The line store (audit step E, docs/V2/EDITOR_SPEC.md section 3): $D000-$EFFF, plain text, every line
; ended by CR. STORE_END is the Phase 64 workspace-end cell under its new name (same address); it is in the
; $8426-$8FFF gap below core/float.asm's FSTACK_LIMIT ($8C00). ----
STORE_END EQU $8A74         ; 2 bytes: one past the last valid byte in the store, the append cursor of
                            ; core/recall.asm's STORE_APPEND. Set by LOAD-TEXT; SAVE-TEXT and VERIFY-TEXT
                            ; leave it alone

LOADTEXT_MAX_LEN EQU 8192
LOADTEXT_BUF     EQU DICT_RAM_CEILING - LOADTEXT_MAX_LEN   ; $D000 with today's $F000 ceiling
STORE_START      EQU LOADTEXT_BUF
STORE_LIMIT      EQU STORE_START + LOADTEXT_MAX_LEN        ; $F000: the store never writes at or above it
    ASSERT (STORE_LIMIT & $FF) == 0   ; LOAD-TEXT's room test below looks at the high byte only

; ============================================================================
; SAVE-TEXT ( addr len "name" -- )
; ============================================================================
H_SAVETEXT:
    DW   DICT_CHAIN_POINT               ; the including ROM sets this (DEFL)
    DB   9, "S","A","V","E","-","T","E","X","T"
W_SAVETEXT:
    call STORAGE_PARSE_NAME
    rst RST_DPOP                       ; len
    ld   d, h
    ld   e, l
    rst RST_DPOP                       ; addr
    push ix
    push hl
    pop  ix
    ld   b, d
    ld   c, e                           ; parameter 2: the length, as V1 wrote it
    ld   hl, STORAGE_NO_AUTOSTART       ; parameter 1
    xor  a                              ; STORAGE_TYPE_TEXT
    call STORAGE_SAVE
    jp   STORAGE_END

; ============================================================================
; VERIFY-TEXT ( addr len "name" -- ) -- compare a text tape of exactly len bytes with addr
; ============================================================================
H_VERIFYTEXT:
    DW   H_SAVETEXT
    DB   11, "V","E","R","I","F","Y","-","T","E","X","T"
W_VERIFYTEXT:
    call STORAGE_PARSE_NAME
    rst RST_DPOP                       ; len
    ld   d, h
    ld   e, l
    rst RST_DPOP                       ; addr
    push ix
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
