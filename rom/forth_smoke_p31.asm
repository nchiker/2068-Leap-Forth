; ============================================================================
; rom/forth_smoke_p31.asm — Phase 31 smoke ROM: BEEP, now on the AY-3-8912 (audit step A, O5)
;
; Replaces the first BEEP's checkpoints (which tested the old float pitch maths) with the oracle the specification
; asks for (docs/V2/AY_BEEP_SPEC.md). It reads the AY registers back (they are readable) and counts FRAMES with the
; real keyboard interrupt handler running, and checks against FORMULAS, not against core/beep.asm's table:
;   1. every n in -60..69 (130 notes): R0/R1 after `n BEEP` are within 1 count of the ideal period
;      round(110250 / (261.6256 * 2^(max(n,-39)/12))), R8 = 0 afterwards, R7 tone A on (bit 0 = 0), noise A off (bit 3 = 1);
;   2. frames: FRAMES advances by exactly round(60 * seconds): 0.5 s -> 30, 0.1 -> 6, 1/60 -> 1, 2.0 -> 120, and 0 for
;      0 s, 0.001 s, 0.008 s (under half a frame) and a negative duration; 0.009 s -> 1;
;   3. out of range (`70 BEEP`, `-61 BEEP` with 0.5 s): no sound, no wait, R0/R1 untouched;
;   4. R7's other bits and channels B and C (R2-R5, R9, R10) survive a BEEP;
;   5. interrupts are on after a BEEP called with them off, and the data and float stacks are balanced.
; Border GREEN (4) = pass, otherwise the failing checkpoint's colour: 1, 2, 3 for checkpoints 1-3, 5 for checkpoint 4
; and 6 for checkpoint 5 (never 4: that is the pass colour).
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    DS   $0008 - $, $FF
RST_08: ret
    DS   $0010 - $, $FF
RST_10: ret
    DS   $0018 - $, $FF
RST_18: ret
    DS   $0020 - $, $FF
RST_20: ret
    DS   $0028 - $, $FF
RST_28: ret
    DS   $0030 - $, $FF
RST_30: ret
    DS   $0038 - $, $FF
RST_38:
    call KBD_ISR_TICK
    ei
    reti
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    xor  a
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a
    call KBD_ISR_INIT
    im   1
    ei

; ---- checkpoint 1: all 130 notes ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, -60
    ld   de, IDEAL_TABLE
.note:
    push hl
    push de
    call DPUSH_HL
    ld   hl, DUR_ONE_FRAME_M
    ld   a, DUR_ONE_FRAME_E
    call FPUSH
    call W_BEEP
    ld   b, 0
    call AY_READ                  ; A = R0
    ld   l, a
    ld   b, 1
    call AY_READ
    ld   h, a                     ; HL = the period the note used
    pop  de
    ld   a, (de)
    ld   c, a
    inc  de
    ld   a, (de)
    ld   b, a
    inc  de                       ; BC = ideal period
    push de
    or   a
    sbc  hl, bc                   ; HL = actual - ideal
    ld   a, h
    or   a
    jr   z, .pos
    inc  a
    jp   nz, FAIL_TEST            ; |diff| > 255
    ld   a, l
    neg
    jr   .chk
.pos:
    ld   a, l
.chk:
    cp   2
    jp   nc, FAIL_TEST            ; more than 1 count off
    ld   b, 8
    call AY_READ
    or   a
    jp   nz, FAIL_TEST            ; channel A must be silent afterwards
    ld   b, 7
    call AY_READ
    and  %00001001
    cp   %00001000
    jp   nz, FAIL_TEST            ; tone A on (bit 0 = 0), noise A off (bit 3 = 1)
    pop  de
    pop  hl
    inc  hl
    ld   a, l
    cp   70
    jr   nz, .note                ; (HL is -60..69: only 70 ends it, h = 0)


; ---- checkpoint 2: durations in frames ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, DUR_TABLE
.dur:
    ld   c, (hl)
    inc  hl
    ld   b, (hl)
    inc  hl
    ld   a, (hl)
    inc  hl
    ld   e, (hl)                  ; E = expected frames (low byte; all under 256)
    inc  hl
    push hl
    push de
    ld   l, c
    ld   h, b                     ; HL = mantissa
    ld   d, a                     ; D = exponent
    push hl
    push de
    ld   hl, 0
    call DPUSH_HL                 ; n = 0, middle C
    pop  de
    pop  hl
    ld   a, d
    call FPUSH
    call INT_GET_FRAMES
    push hl
    call W_BEEP
    call INT_GET_FRAMES
    pop  de
    or   a
    sbc  hl, de                   ; HL = frames elapsed
    pop  de
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    or   a
    jp   nz, FAIL_TEST
    pop  hl
    ld   a, (hl)
    cp   $FF
    jr   nz, .dur

; ---- checkpoint 3: out-of-range pitch: no sound, no wait ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 70
    call OOR_CASE
    ld   hl, -61
    call OOR_CASE

; ---- checkpoint 4: the other mixer bits, channels B and C (border 5 on failure) ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   de, MIXER_CASES
.mix:
    ld   a, (de)
    inc  de
    ld   c, a                     ; C = R7 before
    ld   b, 7
    call AY_WRITE_C
    ld   hl, B_C_REGS
.pre:
    ld   b, (hl)
    inc  hl
    ld   c, (hl)
    inc  hl
    call AY_WRITE_C
    ld   a, b
    cp   10
    jr   nz, .pre
    push de
    ld   hl, 0
    call DPUSH_HL
    ld   hl, DUR_ONE_FRAME_M
    ld   a, DUR_ONE_FRAME_E
    call FPUSH
    call W_BEEP
    pop  de
    dec  de
    ld   a, (de)
    inc  de
    or   $08
    and  $FE
    ld   c, a                     ; expected R7 = (before & $FE) | $08
    ld   b, 7
    call AY_READ
    cp   c
    jp   nz, FAIL_TEST
    ld   hl, B_C_REGS
.post:
    ld   b, (hl)
    inc  hl
    ld   c, (hl)
    inc  hl
    push hl
    push bc
    call AY_READ
    pop  bc
    pop  hl
    cp   c
    jp   nz, FAIL_TEST
    ld   a, b
    cp   10
    jr   nz, .post
    ld   a, (de)
    cp   $FF
    jr   nz, .mix

; ---- checkpoint 5: interrupts on after BEEP called with them off; stacks balanced (border 6) ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   (SAVE_IX), ix
    ld   (SAVE_IY), iy
    ld   hl, 0
    call DPUSH_HL
    ld   hl, DUR_ONE_FRAME_M
    ld   a, DUR_ONE_FRAME_E
    call FPUSH
    di
    call W_BEEP
    ld   a, i                     ; P/V = IFF2
    jp   po, FAIL_TEST            ; (parity odd = P/V clear = interrupts off)
    ld   hl, (SAVE_IX)
    push ix
    pop  de
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ld   hl, (SAVE_IY)
    push iy
    pop  de
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST

PASS_TEST:
    ld   a, 4
    out  (PORT_ULA), a
    jr   PASS_TEST
FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

; AY_READ: B = register -> A = its value. Destroys A
AY_READ:
    ld   a, b
    out  (PORT_AY_REG), a
    in   a, (PORT_AY_DATA)
    ret
; AY_WRITE_C: B = register, C = value. Keeps B, C
AY_WRITE_C:
    ld   a, b
    out  (PORT_AY_REG), a
    ld   a, c
    out  (PORT_AY_DATA), a
    ret

; OOR_CASE: HL = out-of-range semitones; R0/R1 preset to a marker; 0.5 s; must not touch them and must not wait
OOR_CASE:
    push hl
    ld   b, 0
    ld   c, $12
    call AY_WRITE_C
    ld   b, 1
    ld   c, $03
    call AY_WRITE_C
    pop  hl
    call DPUSH_HL
    ld   hl, DUR_HALF_M
    ld   a, DUR_HALF_E
    call FPUSH
    call INT_GET_FRAMES
    push hl
    call W_BEEP
    call INT_GET_FRAMES
    pop  de
    or   a
    sbc  hl, de
    ld   a, h
    or   l
    jp   nz, FAIL_TEST            ; it waited
    ld   b, 0
    call AY_READ
    cp   $12
    jp   nz, FAIL_TEST
    ld   b, 1
    call AY_READ
    cp   $03
    jp   nz, FAIL_TEST
    ret

INTERPRET_UNKNOWN_WORD:
    ld   a, 7
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800
SAVE_IX EQU $8802
SAVE_IY EQU $8804

DUR_ONE_FRAME_M EQU 20972
DUR_ONE_FRAME_E EQU -20     ; 0.02 s = 1.2 frames -> 1

DUR_HALF_M EQU 16384
DUR_HALF_E EQU -15

; mantissa (DW), exponent (DB), expected frames (DB); $FF ends
DUR_TABLE:
    DW   16384
    DB   -15, 30     ; 0.5 s -> 30 frames
    DW   26214
    DB   -18, 6     ; 0.1 s -> 6 frames
    DW   17476
    DB   -20, 1     ; 0.016666666666666666 s -> 1 frames
    DW   0
    DB   0, 0     ; 0.0 s -> 0 frames
    DW   16777
    DB   -24, 0     ; 0.001 s -> 0 frames
    DW   -16384
    DB   -15, 0     ; -0.5 s -> 0 frames
    DW   16777
    DB   -21, 0     ; 0.008 s -> 0 frames
    DW   18874
    DB   -21, 1     ; 0.009 s -> 1 frames
    DW   16384
    DB   -13, 120     ; 2.0 s -> 120 frames
    DB   $FF

; R7 values before the call; B_C_REGS = (register, value) for R2-R5, R9, R10
MIXER_CASES: DB $FF, $00, $41, $FE, $FF
B_C_REGS:
    DB 2,$A5, 3,$05, 4,$5A, 5,$0A, 9,$07, 10,$03

; ideal AY period for n = -60..69: round(110250 / (261.6256 * 2^(max(n,-39)/12)))
IDEAL_TABLE:
    DW   4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009
    DW   4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009, 4009
    DW   4009, 4009, 3784, 3572, 3371, 3182, 3003, 2835, 2676, 2526
    DW   2384, 2250, 2124, 2005, 1892, 1786, 1686, 1591, 1502, 1417
    DW   1338, 1263, 1192, 1125, 1062, 1002, 946, 893, 843, 796
    DW   751, 709, 669, 631, 596, 563, 531, 501, 473, 446
    DW   421, 398, 375, 354, 334, 316, 298, 281, 265, 251
    DW   237, 223, 211, 199, 188, 177, 167, 158, 149, 141
    DW   133, 125, 118, 112, 105, 99, 94, 89, 84, 79
    DW   74, 70, 66, 63, 59, 56, 53, 50, 47, 44
    DW   42, 39, 37, 35, 33, 31, 30, 28, 26, 25
    DW   23, 22, 21, 20, 19, 18, 17, 16, 15, 14
    DW   13, 12, 12, 11, 10, 10, 9, 9, 8, 8

    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/float.asm"
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floatprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/beep.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p31_rom0.bin", $0000, $4000
