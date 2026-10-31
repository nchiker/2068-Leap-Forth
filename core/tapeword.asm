; ============================================================================
; core/tapeword.asm -- what the six tape words (core/storage.asm, core/loadtext.asm) share
;
; INCLUDEd by both files (once, by the guard), so a ROM may have either set of words alone.
; Needs core/dict.asm, core/interp.asm, core/throwcatch.asm and kernel/storage/storage.asm.
; ============================================================================

    IFNDEF CORE_TAPEWORD_ASM
    DEFINE CORE_TAPEWORD_ASM

; ============================================================================
; STORAGE_END -- the tail the six words jump to (not call), with the word's own data-stack
; pointer pushed
; In:  carry clear = done; carry set = failed, B = $FF if SPACE stopped it
; Out: done: IX restored, interrupts enabled, returns; failed: THROW -28 (SPACE) or -37
; STORAGE_REFUSED -- the same for a refusal (a header this word will not take): -37
; STORAGE_THROW -- THROW the code in HL
; ============================================================================
STORAGE_REFUSED:
    ld   b, 0
    scf
STORAGE_END:
    pop  ix
    ei
    ret  nc
    ld   hl, -37                        ; file I/O exception
    inc  b
    jr   nz, STORAGE_THROW
    ld   hl, -28                        ; user interrupt
STORAGE_THROW:
    rst RST_DPUSH
    jp   W_THROW

; ============================================================================
; STORAGE_PARSE_NAME -- the next word of the input as the tape name: STORAGE_NAME_BUF, space-
; padded; STORAGE_NAME_LEN = its length, truncated to STORAGE_HEADER_FILENAME_LEN (0: no name)
; Destroys: AF, BC, DE, HL
; ============================================================================
STORAGE_PARSE_NAME:
    call W_WORD
    rst RST_DPOP                       ; HL = the counted string
    ld   a, (hl)
    cp   STORAGE_HEADER_FILENAME_LEN + 1
    jr   c, .len_ok
    ld   a, STORAGE_HEADER_FILENAME_LEN
.len_ok:
    ld   (STORAGE_NAME_LEN), a
    ld   c, a                           ; characters still to copy
    ld   de, STORAGE_NAME_BUF
    ld   b, STORAGE_HEADER_FILENAME_LEN
.char:
    inc  hl
    ld   a, c
    or   a
    ld   a, " "
    jr   z, .put
    ld   a, (hl)
    dec  c
.put:
    ld   (de), a
    inc  de
    djnz .char
    ret

    ENDIF
