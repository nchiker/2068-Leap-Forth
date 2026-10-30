; ============================================================================
; kernel/memory/memory.asm -- the memory fill primitive
;
; MEM_FILL_ZERO and MEM_FILL clear or fill a RAM range. COLD_START uses them because power-on RAM
; is not guaranteed to be zero (only some emulators zero it): anything the system reads before it
; writes must be cleared explicitly.
; ============================================================================

    IFNDEF KERNEL_MEMORY_ASM
    DEFINE KERNEL_MEMORY_ASM

; ============================================================================
; MEM_FILL_ZERO -- zero BC bytes starting at HL (falls through into MEM_FILL with A = 0)
; MEM_FILL -- fill BC bytes starting at HL with A
; In:  HL = start address, BC = byte count (not 0: a count of 0 fills 65536 bytes), A = fill byte
;      (MEM_FILL only)
; Out: the range filled
; Destroys: AF, BC, DE, HL
; ============================================================================
MEM_FILL_ZERO:
    xor  a
MEM_FILL:
    ld   (hl), a
    ld   d, h
    ld   e, l
    inc  de
    dec  bc
    ld   a, b
    or   c
    ret  z                  ; BC was 1: the one byte is already written
    ldir                    ; copy the written byte forward over the rest
    ret

    ENDIF
