; ============================================================================
; core/sound.asm -- SOUND: write an AY-3-8912 register
;
; core/soundext.asm is the channel-aware layer on top (TONE, VOLUME, MIXER, NOISE, ENVELOPE); it is a
; separate file so a ROM that only needs SOUND does not pay for it.
; SOUND ( register data -- ) writes data straight into a chip register: the register number goes to
; PORT_AY_REG unchanged (the real ROM's SOUND does no DEC A) and the data to PORT_AY_DATA. Registers 0-16
; are accepted (the chip has 0-15; 16 selects none, and is still accepted); 17 and above are ignored
; silently, with nothing written to either port. The semicolon-chained pair list of the BASIC SOUND is
; not supported. Needs include/hardware.inc only. Chained from DICT_CHAIN_POINT (set by the including ROM
; before the INCLUDE); every word may destroy all registers except IX (the data stack pointer), IY and SP.
;
; A clean tone needs three writes, not one (register 8 alone gave static: the mixer and period were left
; at the emulator's start values). Channel B at about 439 Hz (the AY clock is 1,764,000 Hz, period =
; clock / (16 * freq)):
;   2 251 SOUND   3 0 SOUND   7 253 SOUND   9 15 SOUND
; (B's period fine and coarse bytes; the mixer with only B's tone enabled; B's volume). The AY holds its
; registers indefinitely, so the tone goes on until `9 0 SOUND`.
; ============================================================================

    IFNDEF CORE_SOUND_ASM
    DEFINE CORE_SOUND_ASM

; ============================================================================
; SOUND_WRITE -- write one AY register (not a dictionary word)
; In:  B = register (0-16), C = data
; Out: nothing written if B >= 17
; Destroys: AF
; ============================================================================
SOUND_WRITE:
    ld   a, b
    cp   17
    ret  nc                   ; register >=17 -- out of range, ignore
    out  (PORT_AY_REG), a
    ld   a, c
    out  (PORT_AY_DATA), a
    ret

; ============================================================================
; SOUND ( register data -- ) -- write data to AY register 0-16; any other register number is ignored
; ============================================================================
H_SOUND:
    DW   DICT_CHAIN_POINT
    DB   5, "S", "O", "U", "N", "D"
W_SOUND:
    rst RST_DPOP          ; hl = data
    ld   c, l
    rst RST_DPOP          ; hl = register
    ld   a, h
    or   a
    ret  nz               ; 256 and up: ignored
    ld   b, l
    jp   SOUND_WRITE


    ENDIF
