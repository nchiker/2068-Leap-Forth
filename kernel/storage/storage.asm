; ============================================================================
; kernel/storage/storage.asm -- tape SAVE/LOAD: the header layer over the block I/O
;
; Rebuilt in audit step S against docs/V2/STORAGE_SPEC.md (sections 3-5); 2068-Leap V2's
; kernel/storage/storage.asm was the reference for the header search's SPACE handling.
;
; STORAGE_SEND_BLOCK / STORAGE_RECEIVE_BLOCK are Leap-C's clean-room block I/O
; (kernel/storage/tapeblock.asm, adopted unchanged, spec D1 and section 3). Above it:
;   STORAGE_SAVE       a 17-byte header block, then the data block only if the header went out whole
;   STORAGE_FIND       the header search: the first header of a type (and name) on the tape
;   STORAGE_LOAD_DATA  the data block after a found header, loaded or verified
;   STORAGE_CRC        CRC-16/CCITT-FALSE, for the LIB image's trailer (spec D4)
; The wire format is the standard one, so tapes made by the stock ROM's routines still read
; (V1 compatibility is not a requirement, spec D2). The words are in core/storage.asm (LIB) and core/loadtext.asm (TEXT).
;
; Every routine here leaves interrupts off (the block I/O's `di`) except STORAGE_SAVE, which
; enables them; the words' common tail (STORAGE_END, core/storage.asm) enables them.
;
; Test hooks: a ROM that DEFINEs STORAGE_TEST_FAKE_SEND and/or STORAGE_TEST_FAKE_RECEIVE supplies
; STORAGE_TEST_SEND_BLOCK / STORAGE_TEST_RECEIVE_BLOCK with the section-3 contract (an in-RAM
; tape: rom/forth_smoke_p7.asm, p52).
; ============================================================================

STORAGE_TYPE_HEADER EQU $00         ; flag byte of a header block
STORAGE_TYPE_DATA   EQU $FF         ; flag byte of a data block
STORAGE_TYPE_TEXT   EQU 0           ; header types (spec section 4): SAVE-TEXT, as in V1
STORAGE_TYPE_LIB    EQU 3           ;   SAVE-LIB (V1 used 0, so V1 LIB tapes are not found)

STORAGE_HEADER_TYPE_OFF      EQU 0
STORAGE_HEADER_NAME_OFF      EQU 1
STORAGE_HEADER_LENGTH_OFF    EQU 11  ; the data block's length
STORAGE_HEADER_PARAM1_OFF    EQU 13  ; TEXT: STORAGE_NO_AUTOSTART; LIB: ROM_IDENTITY
STORAGE_HEADER_PARAM2_OFF    EQU 15  ; TEXT: the length again; LIB: LATEST
STORAGE_HEADER_PAYLOAD_LEN   EQU 17
STORAGE_HEADER_ATTEMPTS_MAX  EQU 15  ; headers refused before the search gives up
STORAGE_NO_AUTOSTART         EQU $8000
STORAGE_BLOCK_GAP_FRAMES     EQU 50      ; STORAGE_SAVE's pause between header and data

    ASSERT STORAGE_HEADER_NAME_OFF = STORAGE_HEADER_TYPE_OFF + 1
    ASSERT STORAGE_HEADER_NAME_OFF + STORAGE_HEADER_FILENAME_LEN = STORAGE_HEADER_LENGTH_OFF ; (include/forth_layout.inc)
    ASSERT STORAGE_HEADER_PARAM2_OFF + 2 = STORAGE_HEADER_PAYLOAD_LEN

    IFDEF STORAGE_TEST_FAKE_SEND
STORAGE_SEND_BLOCK EQU STORAGE_TEST_SEND_BLOCK
    ELSE
STORAGE_SEND_BLOCK EQU TAPE_SEND_BLOCK
    ENDIF
    IFDEF STORAGE_TEST_FAKE_RECEIVE
STORAGE_RECEIVE_BLOCK EQU STORAGE_TEST_RECEIVE_BLOCK
    ELSE
STORAGE_RECEIVE_BLOCK EQU TAPE_RECV_BLOCK
    ENDIF
    INCLUDE "kernel/storage/tapeblock.asm"

; The identity a LIB image carries (spec D3): $8000 | the CRC-16 of this ROM image with this
; cell zeroed, patched in after assembly by tools/rom_identity.py for the product images. An
; unpatched ROM (every test ROM) reads $0000, which is consistent within that ROM.
ROM_IDENTITY:
    DW   0

; ============================================================================
; STORAGE_SAVE -- save one file: the header block, then the data block
; In:  A = header type, HL = header parameter 1, BC = parameter 2, IX = data, DE = data length;
;      the name in STORAGE_NAME_BUF
; Out: carry clear = saved. Carry set = SPACE stopped it (no data block is sent after a stopped
;      header), B = $FF. Interrupts on
; Destroys: AF, AF', BC, DE, HL, IX
; ============================================================================
STORAGE_SAVE:
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_TYPE_OFF), a
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF), de
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_PARAM1_OFF), hl
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_PARAM2_OFF), bc
    push ix
    push de
    ld   hl, STORAGE_NAME_BUF
    ld   de, STORAGE_HEADER_BUF + STORAGE_HEADER_NAME_OFF
    ld   bc, STORAGE_HEADER_FILENAME_LEN
    ldir
    ld   ix, STORAGE_HEADER_BUF
    ld   de, STORAGE_HEADER_PAYLOAD_LEN
    xor  a                              ; STORAGE_TYPE_HEADER
    call STORAGE_SEND_BLOCK             ; carry set = sent whole
    pop  de
    pop  ix
    jr   nc, .stopped
    ei                                  ; the gap between the blocks: 50 frames (1 s at 50 Hz),
    ld   b, STORAGE_BLOCK_GAP_FRAMES    ;   as on a stock tape. Without it the data block's pilot
.gap:                                   ;   follows the header's closing edge by ~2,400 T, which
    halt                                ;   tape tools (tools/tapes.py's decoder among them) read
    djnz .gap                           ;   as more bits of the header
    ld   a, STORAGE_TYPE_DATA
    call STORAGE_SEND_BLOCK
.stopped:
    ld   b, $FF
    ccf
    ei
    ret

; ============================================================================
; STORAGE_FIND -- the header search
; In:  A = header type; STORAGE_NAME_BUF, STORAGE_NAME_LEN (0 = any name)
; Out: carry clear = found: the header in STORAGE_HEADER_BUF.
;      Carry set = not found: B = $FF if SPACE stopped it, else 0 (STORAGE_HEADER_ATTEMPTS_MAX
;      attempts failed: each a refused header or a receive that saw no signal for ~8.6 s, so
;      about 2 minutes with no tape). Interrupts off
; A header of another type or name is refused and the search goes on with the next one.
; Destroys: AF, AF', BC, DE, HL, IX
; ============================================================================
STORAGE_FIND:
    ld   (STORAGE_REQUEST_TYPE), a
    ld   b, STORAGE_HEADER_ATTEMPTS_MAX
.next:
    push bc
    ld   ix, STORAGE_HEADER_BUF
    ld   de, STORAGE_HEADER_PAYLOAD_LEN
    xor  a                              ; STORAGE_TYPE_HEADER
    scf                                 ; load
    call STORAGE_RECEIVE_BLOCK
    pop  bc
    jr   c, .failed
    ld   hl, STORAGE_HEADER_BUF + STORAGE_HEADER_TYPE_OFF
    ld   a, (STORAGE_REQUEST_TYPE)
    cp   (hl)
    jr   nz, .refused
    ld   a, (STORAGE_NAME_LEN)
    or   a
    ret  z                              ; any name
    ld   de, STORAGE_NAME_BUF
    ld   c, STORAGE_HEADER_FILENAME_LEN
.name:
    inc  hl
    ld   a, (de)
    cp   (hl)
    jr   nz, .refused
    inc  de
    dec  c
    jr   nz, .name
    ret                                 ; carry clear: the last cp was equal
.failed:                                ; a timeout counts as an attempt too, so the search
    call STORAGE_SPACE_HELD             ;   waits up to 15 x ~8.6 s for the user to press play
    jr   nc, STORAGE_STOPPED
.refused:
    djnz .next
    scf
    ret

STORAGE_STOPPED:
    ld   b, $FF
    scf
    ret

; Out: carry clear = SPACE is down. Destroys: AF
STORAGE_SPACE_HELD:
    ld   a, $7F
    in   a, (PORT_ULA)
    rra
    ret

; ============================================================================
; STORAGE_LOAD_DATA -- the data block that follows a found header
; In:  IX = destination, DE = length; carry set = load, clear = verify against the bytes at IX
; Out: carry clear = success. Carry set = failure: B = $FF if SPACE stopped it, else 0, and
;      Z set = nothing at IX was written. Interrupts off
; Destroys: AF, AF', BC, DE, HL, IX
; ============================================================================
STORAGE_LOAD_DATA:
    push de
    ld   a, STORAGE_TYPE_DATA
    call STORAGE_RECEIVE_BLOCK          ; carry passes through `ld` and `push`
    pop  hl
    ret  nc
    call STORAGE_SPACE_HELD
    sbc  a, a
    cpl
    ld   b, a                           ; $FF if SPACE is down
    or   a
    sbc  hl, de                         ; Z: DE is still the whole length, nothing was stored
    scf
    ret

; ============================================================================
; STORAGE_CRC -- CRC-16/CCITT-FALSE: polynomial $1021, initial value $FFFF, most significant bit
; first, no final XOR (check value: "123456789" gives $29B1)
; In:  HL = start, BC = count
; Out: DE = the CRC; HL = start + count; BC = 0
; Destroys: AF. About 400 T per byte
; ============================================================================
STORAGE_CRC:
    ld   de, $FFFF
.byte:
    ld   a, b
    or   c
    ret  z
    ld   a, (hl)
    inc  hl
    xor  d
    ld   d, a
    push bc
    ld   b, 8
.bit:
    sla  e
    rl   d
    jr   nc, .no_poly
    ld   a, d
    xor  $10
    ld   d, a
    ld   a, e
    xor  $21
    ld   e, a
.no_poly:
    djnz .bit
    pop  bc
    dec  bc
    jr   .byte
