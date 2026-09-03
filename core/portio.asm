; ============================================================================
; core/portio.asm — Phase 50: IN and OUT
;
; Builds on core/dict.asm (DPUSH_HL, DPOP_HL) only — no other core/
; dependency.
;
; WHAT THIS ADDS — raw Z80 hardware port I/O, matching the sibling
; ts2068rom BASIC clone's own IN/OUT convention (read-only reference,
; ~/ts2068rom/docs/user_manual.md and hardware_notes.md: "OUT
; port,data... performing native Z80 output to a 16-bit port with byte
; data") and the Jupiter Ace manual's own stack order (cached docs text,
; Appendix B: "IN (address -- byte)... OUT (byte, address -- )"):
;   IN  ( port -- value )   reads one byte from the given 16-bit port.
;   OUT ( value port -- )    writes one byte to the given 16-bit port.
;
; FULL 16-BIT PORT FORM, NOT THE 8-BIT `IN A,(n)`/`OUT (n),A` FORM: both
; words load the port number into BC and use `IN r,(C)`/`OUT (C),r`, so
; the entire 65536-port space is reachable, not just the low 256 -- this
; matters concretely on this hardware, since e.g. the AY sound chip's
; own two ports (core/sound.asm's own PORT_AY_REG=$F5/PORT_AY_DATA=$F6)
; happen to fit in 8 bits here, but there is no reason a future port
; this project doesn't already know about would, and the task's own
; spec calls for the full form regardless.
;
; A GENUINE "THE USER CAN DO DANGEROUS THINGS WITH IT" WORD BY DESIGN,
; same as real hardware BASIC's own IN/OUT on this same machine
; (~/ts2068rom's own docs say so explicitly: "OUT is shipped as a
; loadable extension because direct port access is powerful... A BASIC
; error cannot undo a hardware write") -- no range checking, no
; forbidden-port list, matching every other memory- or hardware-facing
; word already in this project (@, !, core/bytemem.asm's C@/C!). This is
; intentional, not a bug to fix.
; ============================================================================

    IFNDEF CORE_PORTIO_ASM
    DEFINE CORE_PORTIO_ASM

; ============================================================================
; IN ( port -- value )
; ============================================================================
H_IN:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "I","N"
W_IN:
    call DPOP_HL             ; hl = port
    ld   b, h
    ld   c, l                 ; bc = port -- full 16-bit form
    in   a, (c)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret

; ============================================================================
; OUT ( value port -- )
; ============================================================================
H_OUT:
    DW   H_IN
    DB   3, "O","U","T"
W_OUT:
    call DPOP_HL             ; hl = port
    ld   b, h
    ld   c, l                 ; bc = port
    call DPOP_HL              ; hl = value
    ld   a, l
    out  (c), a
    ret

DICT_LATEST_INIT_PORTIO EQU H_OUT   ; head of the dictionary once this
                                     ; file's own words are included

    ENDIF
