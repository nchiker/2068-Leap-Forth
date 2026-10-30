; ============================================================================
; core/beep.asm — BEEP on the AY-3-8912 (audit step A, item O5)
;
;   BEEP ( n-semitones fduration -- )   n = semitones from middle C (0 = middle C), fduration = seconds
;
; The specification is docs/V2/AY_BEEP_SPEC.md; the oracle is rom/forth_smoke_p31.asm. In short: the note sounds
; on AY channel A (R0/R1 = period, R7 tone A on / noise A off, R8 = 15), lasts round(60 * seconds) display
; frames waited with HALT (interrupts stay on, so FRAMES and the keyboard keep running), and ends with R8 = 0.
; Channels B and C, the noise period, the envelope and the I/O ports are not touched. Pitch -60..69 (below -39 plays
; A0, the lowest note a 12-bit period reaches); anything outside, or a duration under half a frame, does nothing.
;
; This replaces the first BEEP, which toggled the loudspeaker bit of port $FE with interrupts off for the whole
; note and needed float division for the pitch (about 440 B here, plus SOUND_BEEP's 55). That loudspeaker beeper is kept as an
; optional package, not in the product ROMs: kernel/sound/sound.asm (SOUND_BEEP) and core/rawbeep.asm (the
; raw-units word, tested by rom/forth_smoke_p5.asm).
;
; The period table and the shift-and-round scheme follow 2068-Leap's rom/v2_ay_beep.asm (MIT, same owner), rebuilt
; here against the specification; the 12 table values are 16 * 110250 / f for the notes from A0 (27.5 Hz).
;
; Builds on core/dict.asm, core/interp.asm and core/fpcore.asm (FMULP, FPOP_FX, FTOI); all must be INCLUDEd first,
; chaining through DICT_CHAIN_POINT as every other float file does. The duration is multiplied by 120 on the float
; engine (FLOAT_SPEC section 12): a product above 2^16 half-frames (exponent byte over 144) plays 32,768 frames, a
; negative or zero one nothing.
; ============================================================================

    IFNDEF CORE_BEEP_ASM
    DEFINE CORE_BEEP_ASM

BEEP_AY_LEVEL     EQU 15      ; channel A's fixed level while a note sounds
; seconds * 120 = half-frames (60 frames per second, doubled so the last bit can round)
K_120:
    DB   $87, $70, $00, $00, $00        ; 120.0

; 16 * 110250 / f for the 12 notes from A0 (semitone -39) to G#0
BEEP_TABLE:
    DW   64145, 60545, 57147, 53940, 50912, 48055, 45358, 42812, 40409, 38141, 36000, 33980

; ============================================================================
; BEEP_PLAY (internal) — In: HL = semitones (signed), DE = frames. Does nothing for DE = 0 or a pitch outside
; -60..69. Destroys: AF, BC, DE, HL
; ============================================================================
BEEP_PLAY:
    ld   a, d
    or   e
    ret  z                       ; under half a frame: nothing
    ld   bc, 60
    add  hl, bc                  ; HL = semitones + 60: 0..129 is the playable range
    ld   a, h
    or   a
    ret  nz
    ld   a, l
    cp   130
    ret  nc
    sub  21                      ; A = semitones + 39
    jr   nc, .in_range
    xor  a                       ; below the AY's lowest note: A0
.in_range:
    ld   b, 3
.octave:
    inc  b
    sub  12
    jr   nc, .octave             ; B = octave + 4, A = note - 12
    add  a, a                    ; A = 2 * note - 24, always negative: unsigned 232..254
    add  a, (BEEP_TABLE + 24) & $FF
    ld   l, a                    ; HL = BEEP_TABLE + 24 + (A - 256), whatever page the table is on:
    ld   a, ((BEEP_TABLE + 24) >> 8) - 1
    adc  a, 0                    ; the high byte takes the carry of the low add
    ld   h, a
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a                    ; HL = the note's table entry (16 * period, octave 0)
.shift:
    srl  h
    rr   l
    djnz .shift                  ; HL = entry / 2^(octave + 4); carry = the last bit shifted out
    jr   nc, .rounded
    inc  hl                      ; rounded to the nearest
.rounded:
    ei                           ; the wait below needs the frame interrupt; the first BEEP ended with EI too
    ld   c, PORT_AY_DATA
    xor  a
    out  (PORT_AY_REG), a
    out  (c), l                  ; R0 = period, fine byte
    inc  a
    out  (PORT_AY_REG), a
    out  (c), h                  ; R1 = period, coarse
    ld   a, 7
    out  (PORT_AY_REG), a
    in   a, (c)
    and  $FE                     ; tone A on
    or   $08                     ; noise A off; every other mixer bit as it was
    out  (c), a
    ld   a, 8
    out  (PORT_AY_REG), a
    ld   a, BEEP_AY_LEVEL
    out  (c), a                  ; R8 = fixed level
.wait:
    halt                         ; one display frame
    dec  de
    ld   a, d
    or   e
    jr   nz, .wait
    out  (c), a                  ; A = 0, R8 still selected: silent
    ret

; ============================================================================
; BEEP ( n-semitones fduration -- )
; ============================================================================
H_BEEP:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL, not EQU) to whatever word chain this file
                            ; should extend, immediately before INCLUDEing it
    DB   4, "B", "E", "E", "P"
W_BEEP:
    ld   hl, K_120
    call FMULP                   ; float stack: seconds * 120 = half-frames
    call FPOP_FX
    ld   hl, 0
    ld   a, (FX + U_S)
    or   a
    jr   nz, .half               ; a negative duration plays nothing
    ld   a, (FX + U_E)
    or   a
    jr   z, .half                ; neither does 0
    cp   145
    jr   c, .toi
    ld   hl, $FFFF               ; 65536 half-frames or more: play 32,768 frames
    jr   .half
.toi:
    call FTOI                    ; HL = half-frames, truncated (the exponent is 144 at most: 16 bits)
.half:
    srl  h
    rr   l
    jr   nc, .frames
    inc  hl                      ; frames = half-frames / 2, rounded to the nearest
.frames:
    push hl
    rst RST_DPOP                ; HL = semitones
    pop  de                      ; DE = frames
    jp   BEEP_PLAY

DICT_LATEST_INIT_BEEP EQU H_BEEP   ; head of the dictionary once this file's own word is included

    ENDIF
