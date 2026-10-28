; ============================================================================
; core/storage.asm -- SAVE-LIB, VERIFY-LIB, LOAD-LIB, and the helpers the six tape words share
;
; Rebuilt in audit step S against docs/V2/STORAGE_SPEC.md (decisions D2-D5, section 6).
;
; A LIB image is the compiled RAM dictionary, tied to the exact ROM that saved it: its words hold
; ROM addresses. On tape (spec section 4) it is a type-3 header carrying ROM_IDENTITY and LATEST,
; then a data block of the dictionary bytes FORTH_DICT_RAM..HERE-1 followed by their CRC-16 (low
; byte first). It is saved from and loaded into the dictionary in place, so the limit is the
; dictionary space (HERE + 2 <= DICT_RAM_CEILING), not a buffer. Source text (SAVE-TEXT,
; core/loadtext.asm) is the portable format: any new ROM makes older LIB tapes unloadable.
;
; Errors are THROWn: -28 when SPACE stopped the transfer, -37 for any other tape failure, -8 when
; SAVE-LIB's image does not fit (core/tapeword.asm, shared with core/loadtext.asm). Needs
; core/dict.asm, core/interp.asm, core/throwcatch.asm and kernel/storage/storage.asm first, and the including ROM to define DICT_LATEST_COLD (LATEST of
; an empty user dictionary: what a failed LOAD-LIB that had already written resets it to).
; ============================================================================

    IFNDEF CORE_STORAGE_ASM
    DEFINE CORE_STORAGE_ASM

; ============================================================================
; SAVE-LIB ( "name" -- )
; ============================================================================
H_SAVELIB:
    DW   DICT_CHAIN_POINT               ; the including ROM sets this (DEFL)
    DB   8, "S", "A", "V", "E", "-", "L", "I", "B"
W_SAVELIB:
    call STORAGE_PARSE_NAME
    ld   hl, (HERE)
    ld   de, DICT_RAM_CEILING - 1
    or   a
    sbc  hl, de                         ; carry: HERE + 2 <= DICT_RAM_CEILING, the CRC fits
    ld   hl, -8                         ; dictionary overflow
    jr   nc, STORAGE_THROW
    push ix
    call STORAGE_LIB_CRC
    ld   hl, (ROM_IDENTITY)
    ld   bc, (LATEST)
    ld   ix, FORTH_DICT_RAM
    ld   a, STORAGE_TYPE_LIB
    call STORAGE_SAVE
    jr   STORAGE_END

; ============================================================================
; VERIFY-LIB ( "name" -- ) -- compare a LIB tape with the dictionary; nothing is written
; (except the CRC at HERE, HERE + 1, which is free dictionary space)
; ============================================================================
H_VERIFYLIB:
    DW   H_SAVELIB
    DB   10, "V", "E", "R", "I", "F", "Y", "-", "L", "I", "B"
W_VERIFYLIB:
    call STORAGE_PARSE_NAME
    push ix
    call STORAGE_LIB_CRC
    push de                             ; the image length
    ld   a, STORAGE_TYPE_LIB
    call STORAGE_FIND
    pop  de
    jr   c, STORAGE_END
    call STORAGE_CHECK_ID
    jr   nz, STORAGE_REFUSED
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    sbc  hl, de                         ; (carry clear from STORAGE_CHECK_ID)
    jr   nz, STORAGE_REFUSED
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_PARAM2_OFF)
    ld   bc, (LATEST)
    sbc  hl, bc
    jr   nz, STORAGE_REFUSED
    ld   ix, FORTH_DICT_RAM             ; carry clear: verify
    call STORAGE_LOAD_DATA
    jr   STORAGE_END

    INCLUDE "core/tapeword.asm"        ; the shared tail, between the words so their jr reach it

; ============================================================================
; LOAD-LIB ( "name" -- ) -- replace the user dictionary with a LIB image. Refused before any
; data byte arrives (dictionary unchanged): another ROM's identity, a length outside 2 ..
; DICT_RAM_CEILING - FORTH_DICT_RAM. A failure after part of the image was written, or a CRC
; mismatch, leaves an empty user dictionary.
; ============================================================================
H_LOADLIB:
    DW   H_VERIFYLIB
    DB   8, "L", "O", "A", "D", "-", "L", "I", "B"
W_LOADLIB:
    call STORAGE_PARSE_NAME
    push ix
    ld   a, STORAGE_TYPE_LIB
    call STORAGE_FIND
    jr   c, STORAGE_END
    call STORAGE_CHECK_ID
    jr   nz, STORAGE_REFUSED
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   hl, DICT_RAM_CEILING - FORTH_DICT_RAM
    sbc  hl, de                         ; (carry clear from STORAGE_CHECK_ID)
    jr   c, STORAGE_REFUSED             ; longer than the dictionary space
    ld   a, d
    or   a
    jr   nz, .long_enough
    ld   a, e
    cp   2
    jr   c, STORAGE_REFUSED             ; shorter than the CRC
.long_enough:
    ld   ix, FORTH_DICT_RAM
    scf                                 ; load
    call STORAGE_LOAD_DATA
    jr   c, .failed
    ld   bc, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    dec  bc
    dec  bc
    ld   hl, FORTH_DICT_RAM
    call STORAGE_CRC                    ; DE = the CRC, HL = the image's end = the new HERE
    ld   a, e
    cp   (hl)
    jr   nz, .bad_crc
    inc  hl
    ld   a, d
    cp   (hl)
    dec  hl
    jr   nz, .bad_crc
    ld   (HERE), hl
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_PARAM2_OFF)
    ld   (LATEST), hl
    jp   STORAGE_END                    ; carry clear: the last cp was equal
.failed:
    jp   z, STORAGE_END                 ; nothing written: the dictionary is as it was
    jr   .empty
.bad_crc:
    ld   b, 0
.empty:
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    ld   hl, DICT_LATEST_COLD
    ld   (LATEST), hl
    scf
    jp   STORAGE_END

; Z (and carry clear) = the found header carries this ROM's identity. Destroys: AF, BC, HL
STORAGE_CHECK_ID:
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_PARAM1_OFF)
    ld   bc, (ROM_IDENTITY)
    or   a
    sbc  hl, bc
    ret

; The dictionary's CRC stored at HERE, HERE + 1 (low byte first).
; Out: DE = the image length (dictionary bytes + 2). Destroys: AF, BC, HL
STORAGE_LIB_CRC:
    ld   hl, (HERE)
    ld   bc, FORTH_DICT_RAM
    or   a
    sbc  hl, bc
    ld   b, h
    ld   c, l
    push bc
    ld   hl, FORTH_DICT_RAM
    call STORAGE_CRC                    ; DE = the CRC, HL = HERE
    ld   (hl), e
    inc  hl
    ld   (hl), d
    pop  de
    inc  de
    inc  de
    ret

    ENDIF
