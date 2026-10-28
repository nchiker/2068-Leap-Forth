; ============================================================================
; core/loadtext.asm -- SAVE-TEXT, VERIFY-TEXT, LOAD-TEXT: plain Forth source over tape
;
; Rebuilt in audit step S against docs/V2/STORAGE_SPEC.md (section 6). Source text is the
; portable format: it is re-parsed and compiled when loaded, so a tape loads into any ROM, unlike
; a LIB image (core/storage.asm). On tape (spec section 4): a type-0 header (parameter 1 =
; STORAGE_NO_AUTOSTART, parameter 2 = the length), then the text bytes (the format V1 used, which is
; not a requirement: spec D2) and the format tools/tape_gen_forth.py writes.
;
; LOAD-TEXT receives into LOADTEXT_BUF (the top LOADTEXT_MAX_LEN bytes below DICT_RAM_CEILING),
; which stays resident afterwards as core/recall.asm's workspace, and interprets it.
;
; Errors are THROWn as in core/storage.asm (-28 SPACE, -37 any other tape failure; core/tapeword.asm).
; Needs core/dict.asm, core/interp.asm (INTERPRET_RUN), core/throwcatch.asm and
; kernel/storage/storage.asm first.
; ============================================================================

    IFNDEF CORE_LOADTEXT_ASM
    DEFINE CORE_LOADTEXT_ASM

    INCLUDE "core/tapeword.asm"

; ---- Phase 64 (core/recall.asm) workspace-end tracking: here because W_LOADTEXT sets it;
; core/recall.asm, INCLUDEd after this file, reads it. In the $8426-$8FFF gap below core/float.asm's
; FSTACK_LIMIT ($8C00). ----
WORKSPACE_END EQU $8A74     ; 2 bytes: one past the last valid byte in LOADTEXT_BUF, the append
                            ; cursor of core/recall.asm's WORKSPACE_APPEND. Set after a successful
                            ; LOAD-TEXT; SAVE-TEXT and VERIFY-TEXT leave it alone

LOADTEXT_MAX_LEN EQU 8192
LOADTEXT_BUF     EQU DICT_RAM_CEILING - LOADTEXT_MAX_LEN   ; $D000 with today's $F000 ceiling

; ============================================================================
; SAVE-TEXT ( addr len "name" -- )
; ============================================================================
H_SAVETEXT:
    DW   DICT_CHAIN_POINT               ; the including ROM sets this (DEFL)
    DB   9, "S","A","V","E","-","T","E","X","T"
W_SAVETEXT:
    call STORAGE_PARSE_NAME
    call DPOP_HL                        ; len
    ld   d, h
    ld   e, l
    call DPOP_HL                        ; addr
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
    call DPOP_HL                        ; len
    ld   d, h
    ld   e, l
    call DPOP_HL                        ; addr
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
; LOAD-TEXT ( "name" -- ) -- load a text tape into LOADTEXT_BUF and interpret it
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
    ld   ix, LOADTEXT_BUF
    scf                                 ; load
    call STORAGE_LOAD_DATA
    jp   c, STORAGE_END
    pop  ix
    ei
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   hl, LOADTEXT_BUF               ; INTERPRET_RUN: HL = source, DE = length
    ; TRACK_WORKSPACE_END: only rom/forth_boot.asm DEFINEs it, the one ROM with core/recall.asm
    ; (WORKSPACE_END's only reader); other ROMs skip the bookkeeping.
    IFDEF TRACK_WORKSPACE_END
    push hl
    add  hl, de
    ld   (WORKSPACE_END), hl
    pop  hl
    ENDIF
    call INTERPRET_RUN
    ret

DICT_LATEST_INIT_LOADTEXT EQU H_LOADTEXT   ; head of the dictionary once this file is the last one
                                           ; INCLUDEd

    ENDIF
