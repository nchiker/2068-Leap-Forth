; ============================================================================
; core/soundext.asm -- TONE, VOLUME, MIXER, NOISE, ENVELOPE: channel-aware AY words
;
; Shorthand for register writes SOUND could do by hand, so a caller need not remember the fine/coarse split,
; the channel-to-register map or the bit layouts. Needs core/sound.asm INCLUDEd first, with
; DICT_CHAIN_POINT left at H_SOUND before this INCLUDE; and include/hardware.inc. A separate file so a ROM
; that only needs SOUND does not pay for these. AY_WRITE here is native 0-15 numbering, not SOUND_WRITE's
; 0-16.
; AY-3-8912 registers used: 0/1, 2/3, 4/5 = channel A/B/C tone period fine/coarse (only the low 4 bits of
; a coarse register count); 6 = noise period (low 5 bits); 7 = mixer (see MIXER); 8/9/10 = channel A/B/C
; amplitude (low 4 bits = fixed volume, bit 4 = use the envelope generator); 11/12 = envelope period
; fine/coarse (all 16 bits count); 13 = envelope shape (low 4 bits).
; An out-of-range channel is ignored silently, nothing written to either port; only the low byte of the
; popped cell is checked. Chained from DICT_CHAIN_POINT; every word may destroy all registers except IX
; (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_SOUNDEXT_ASM
    DEFINE CORE_SOUNDEXT_ASM

; ============================================================================
; AY_WRITE -- write one AY register in native numbering (not a dictionary word)
; In:  B = register (0-15), C = data
; Out: nothing written if B >= 16
; Destroys: AF
; ============================================================================
AY_WRITE:
    ld   a, b
    cp   16
    ret  nc                   ; register >=16 -- out of range, ignore
    out  (PORT_AY_REG), a
    ld   a, c
    out  (PORT_AY_DATA), a
    ret

; ============================================================================
; TONE ( channel period -- ) -- channel 0=A, 1=B, 2=C; period 0-4095
; The fine byte goes to register channel*2, the top 4 bits of the period (the coarse nibble) to
; channel*2+1.
; ============================================================================
H_TONE:
    DW   DICT_CHAIN_POINT
    DB   4, "T", "O", "N", "E"
W_TONE:
    rst RST_DPOP              ; hl = period
    ld   a, h
    and  $0F                   ; coarse nibble -- top 4 bits of the
                                ; register are unused on real hardware
    ld   d, a
    ld   e, l                  ; e = fine byte
    rst RST_DPOP              ; hl = channel
    ld   a, l
    cp   3
    ret  nc                    ; channel not 0-2 -- ignore
    add  a, a                  ; a = channel*2 = fine-period register
    ld   b, a
    ld   c, e
    call AY_WRITE
    inc  b                     ; b = channel*2+1 = coarse-period register
    ld   c, d
    call AY_WRITE
    ret

; ============================================================================
; VOLUME ( channel level -- ) -- channel 0=A, 1=B, 2=C; level 0-15 (the low 4 bits of the cell)
; Sets a fixed volume: bit 4 of the amplitude register (use the envelope) is always cleared.
; ============================================================================
H_VOLUME:
    DW   H_TONE
    DB   6, "V", "O", "L", "U", "M", "E"
W_VOLUME:
    rst RST_DPOP              ; hl = level
    ld   a, l
    and  $0F
    ld   c, a
    rst RST_DPOP              ; hl = channel
    ld   a, l
    cp   3
    ret  nc                    ; channel not 0-2 -- ignore
    add  a, 8                  ; channel 0/1/2 -> register 8/9/10
    ld   b, a
    call AY_WRITE
    ret

; ============================================================================
; MIXER ( mask -- ) -- write mask unchanged to register 7
; Active low: bit = 0 enables a source. Bits 0-2 = tone A/B/C, bits 3-5 = noise A/B/C, bits 6-7 = I/O
; port direction (not sound). `253 MIXER` enables only channel B's tone.
; ============================================================================
H_MIXER:
    DW   H_VOLUME
    DB   5, "M", "I", "X", "E", "R"
W_MIXER:
    rst RST_DPOP               ; hl = mask
    ld   c, l
    ld   b, 7
    call AY_WRITE
    ret

; ============================================================================
; NOISE ( period -- ) -- write the low 5 bits of period to register 6 (the one shared noise generator)
; MIXER must route the noise onto a channel (bits 3-5) before it is audible.
; ============================================================================
H_NOISE:
    DW   H_MIXER
    DB   5, "N", "O", "I", "S", "E"
W_NOISE:
    rst RST_DPOP               ; hl = period
    ld   a, l
    and  $1F
    ld   c, a
    ld   b, 6
    call AY_WRITE
    ret

; ============================================================================
; ENVELOPE ( period shape -- ) -- period: 16 bits to registers 11/12; shape: low 4 bits to register 13
; (continue/attack/alternate/hold, passed through as they are)
; No channel is routed through the envelope: that is bit 4 of its amplitude register, which VOLUME always
; clears. Set it with a raw write, e.g. `8 16 SOUND` for channel A.
; ============================================================================
H_ENVELOPE:
    DW   H_NOISE
    DB   8, "E", "N", "V", "E", "L", "O", "P", "E"
W_ENVELOPE:
    rst RST_DPOP               ; hl = shape
    ld   a, l
    and  $0F
    ld   e, a                   ; e = shape byte -- survives the next
                                ; DPOP_HL (only IX/HL touched there)
                                ; and the AY_WRITE calls below (only AF)
    rst RST_DPOP                ; hl = period
    ld   b, 11
    ld   c, l                    ; fine byte
    call AY_WRITE
    ld   b, 12
    ld   c, h                    ; coarse byte -- full 8 bits significant
    call AY_WRITE
    ld   b, 13
    ld   c, e
    call AY_WRITE
    ret

DICT_LATEST_INIT_SOUNDEXT EQU H_ENVELOPE

    ENDIF
