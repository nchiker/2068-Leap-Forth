; ============================================================================
; kernel/bank/bank.asm -- the EXROM paging primitives
;
; The Home bank is capped at 16K; the EXROM adds 8K, paged into chunk 5 ($A000-$BFFF) only.
; Chunk 5 is the one chunk nothing else in the memory map claims (not the machine or CPU stacks,
; which are chunk 4; not video RAM; not a fixed buffer; nothing KBD_ISR_TICK touches). Only
; dictionary content can live there, and paging only hides the RAM for a while, so this holds
; however far the dictionary has grown into chunk 5. Chunk N = bit N of PORT_BANK_HOME.
;
; Interrupts are NOT disabled anywhere in these routines: the frame interrupt stays asserted
; for only 32 T, so a DI window of about 120 T lost frames. That is safe because the interrupt
; handler touches none of the banking state (BANK_EXROM_DEPTH, PORT_FF_SHADOW, ports $F4/$FF):
; it runs from chunk 0 with its sysvars and stack in chunk 4, and chunk 5 is the only chunk
; paged. If the handler ever touches chunk 5, the banking state or those ports, this needs
; re-deriving. Both routines end with EI.
;
; The EXROM's entry convention: execution starts at the first byte of the 8K image ($A000 once
; paged in), as a ROM's reset vector. Services are reached through the service table there
; (rom/graphics_exrom.asm), not through these primitives.
; ============================================================================

    IFNDEF KERNEL_BANK_ASM
    DEFINE KERNEL_BANK_ASM

; ============================================================================
; BANK_PAGE_EXROM_IN -- page chunk 5 ($A000-$BFFF) to EXROM; every other chunk stays Home
; In:  none
; Out: interrupts enabled
; Destroys: AF
; Nesting-safe through BANK_EXROM_DEPTH: the port writes happen only on the 0->1 transition, so
; a call from code already running inside the EXROM just bumps the counter.
; ============================================================================
BANK_PAGE_EXROM_IN:
    ld   a, (BANK_EXROM_DEPTH)
    inc  a
    ld   (BANK_EXROM_DEPTH), a
    cp   1
    jr   nz, .already_paged_in       ; an outer caller already paged it in
    ld   a, (PORT_FF_SHADOW)
    or   %10000000                   ; bit 7 only (EXROM, not Dock); bits 0-6 (video mode,
                                     ; INTEN) are not this routine's to touch
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   a, %00100000                ; bit 5 = chunk 5 only; the rest stay Home
    out  (PORT_BANK_HOME), a
.already_paged_in:
    ei
    ret

; ============================================================================
; BANK_PAGE_EXROM_OUT -- restore chunk 5 to Home, once BANK_EXROM_DEPTH is back to 0
; In:  none
; Out: interrupts enabled
; Destroys: AF
; PORT_SCLD bit 7 is left as BANK_PAGE_EXROM_IN set it: with every chunk Home it is moot, and
; clearing it would cost a read-modify-write through PORT_FF_SHADOW for no effect.
; ============================================================================
BANK_PAGE_EXROM_OUT:
    ld   a, (BANK_EXROM_DEPTH)
    or   a
    jr   z, .depth_already_zero       ; an unbalanced OUT: don't underflow the counter
    dec  a
    ld   (BANK_EXROM_DEPTH), a
    jr   nz, .still_nested             ; an outer caller still needs chunk 5 paged in
    out  (PORT_BANK_HOME), a         ; A = 0 (the depth): every chunk back to Home
.still_nested:
.depth_already_zero:
    ei
    ret

    ENDIF
