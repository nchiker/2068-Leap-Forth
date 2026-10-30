; ============================================================================
; core/stick.asm -- STICK: read a joystick
;
; A thin word over kernel/io/io.asm's STICK_READ, which must be INCLUDEd too. The device number is not
; validated (STICK_READ trusts its caller): a value other than 1 or 2 goes to the hardware as it is.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_STICK_ASM
    DEFINE CORE_STICK_ASM

; ============================================================================
; STICK ( device -- value ) -- device 1: a 4-bit direction nibble; device 2: a single bit (0 or 1)
; See STICK_READ in kernel/io/io.asm for the bit meanings.
; ============================================================================
H_STICK:
    DW   DICT_CHAIN_POINT
    DB   5, "S", "T", "I", "C", "K"
W_STICK:
    rst RST_DPOP          ; hl = device
    call STICK_READ        ; hl = value
    rst RST_DPUSH
    ret


    ENDIF
