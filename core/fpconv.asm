; ============================================================================
; core/fpconv.asm — S>F, F>S, FROUND and FLOOR (step F, docs/V2/FLOAT_SPEC.md sections 8.1, 8.4)
;
; Builds on core/fpcore.asm and core/dict.asm (this file's first header chains through DICT_CHAIN_POINT).
;
;   S>F    ( n -- r )   exact: the signed 16-bit integer as a float
;   F>S    ( r -- n )   truncated toward 0 (-2.5 gives -2); the integer part must be in -32768..65535 (the range an
;                       integer literal has: 40000 comes back as -25536), else THROW -43
;   FROUND ( r1 -- r2 ) the nearest integral value, ties away from 0 (2.5 gives 3, -2.5 gives -3), still a float
;   FLOOR  ( r1 -- r2 ) the greatest integral value not above it (-2.5 gives -3, 2.5 gives 2), still a float
;
; FROUND works on the unpacked mantissa, never by adding 1/2 (which FPACK could round up across an integer): below 1
; in magnitude it gives +-1 for |x| >= 1/2 and 0 otherwise; from 2^31 up the value is already an integer; otherwise
; the integer bits are taken off the mantissa (FIPART), 1 is added when the first dropped bit is set, and the result
; is normalised. FINT is the routine behind it with a mode, so that FLOOR (toward minus infinity) is a header on the
; same code.
; ============================================================================

    IFNDEF CORE_FPCONV_ASM
    DEFINE CORE_FPCONV_ASM

; ============================================================================
; S>F ( n -- r )
; ============================================================================
H_STOF:
    DW   DICT_CHAIN_POINT   ; the including ROM sets this (DEFL) to the chain this file extends, just before INCLUDEing it
    DB   3, "S", ">", "F"
W_STOF:
    rst  RST_DPOP
    ld   a, h
    and  $80                           ; the sign (clears C)
    jr   z, .pos
    ex   de, hl
    ld   hl, 0
    sbc  hl, de                        ; the magnitude (-32768 stays $8000)
.pos:
    call FFROM
    ld   bc, -5
    add  iy, bc
    jp   FPACK

; ============================================================================
; F>S ( r -- n )
; ============================================================================
H_FTOS:
    DW   H_STOF
    DB   3, "F", ">", "S"
W_FTOS:
    call FPOP_FX
    call FTOI                          ; HL = the magnitude
    jp   c, F_RANGE
    ld   a, (FX + U_S)
    or   a
    jr   z, .push
    ld   a, h                          ; negative: the magnitude is 32768 at most
    cp   $80
    jr   c, .neg
    jp   nz, F_RANGE
    ld   a, l
    or   a
    jp   nz, F_RANGE
.neg:
    ex   de, hl
    ld   hl, 0
    or   a
    sbc  hl, de
.push:
    rst  RST_DPUSH
    ret

DICT_LATEST_INIT_FLOATCONV EQU H_FTOS   ; head of the dictionary as of S>F, F>S

; ============================================================================
; FINT -- (iy+0) = its integral value: A = 0 rounds half away from 0 (FROUND), A = 1 toward minus infinity (FLOOR)
; Destroys: AF, BC, DE, HL
; ============================================================================
FINT:
    ld   (FQ), a                       ; the mode (FQ is free here)
    push iy
    pop  hl
    ld   de, FX
    call FUNPK
    ld   a, (FX + U_E)
    or   a
    jr   z, .pack                      ; 0
    cp   129
    jr   c, .small                     ; |x| < 1
    cp   160
    jr   nc, .pack                     ; 2^31 or more: an integer already
    sub  128                           ; A = 1-31 integer bits
    call FIPART                        ; DE:HL = the integer, FX's mantissa = the fraction
    ld   a, (FQ)
    or   a
    jr   nz, .floor
    ld   a, (FX + U_M)
    rla
    jr   nc, .set                      ; under a half
    jr   .inc
.floor:
    ld   a, (FX + U_S)
    or   a
    jr   z, .set
    ld   bc, (FX + U_M)
    ld   a, b
    or   c
    ld   bc, (FX + U_M + 2)
    or   b
    or   c
    jr   z, .set                       ; no fraction: already integral
.inc:
    inc  hl
    ld   a, h
    or   l
    jr   nz, .set
    inc  de
.set:
    ld   a, d
    ld   (FX + U_M), a
    ld   a, e
    ld   (FX + U_M + 1), a
    ld   a, h
    ld   (FX + U_M + 2), a
    ld   a, l
    ld   (FX + U_M + 3), a
    ld   a, 160
    ld   (FX + U_E), a
    call FNORM                         ; (0 when the integer is 0)
.pack:
    jp   FPACK
.small:                                ; |x| < 1: round gives +-1 from 1/2 up, floor -1 for a negative x
    ld   c, a
    ld   a, (FQ)
    or   a
    jr   nz, .sfloor
    ld   a, c
    cp   128
    jr   nz, .zero
    jr   .one
.sfloor:
    ld   a, (FX + U_S)
    or   a
    jr   z, .zero
.one:
    ld   hl, 1
    ld   a, (FX + U_S)
    call FFROM
    jr   .pack
.zero:
    call FZEROX
    jr   .pack

; ============================================================================
; FROUND ( r1 -- r2 )
; ============================================================================
H_FROUND:
    DW   H_FTOS
    DB   6, "F", "R", "O", "U", "N", "D"
W_FROUND:
    xor  a
    jp   FINT

; ============================================================================
; FLOOR ( r1 -- r2 )  toward minus infinity (-2.5 gives -3, 2.5 gives 2)
; ============================================================================
H_FLOOR:
    DW   H_FROUND
    DB   5, "F", "L", "O", "O", "R"
W_FLOOR:
    ld   a, 1
    jp   FINT

DICT_LATEST_INIT_FROUND EQU H_FLOOR   ; head of the dictionary once this file is included (FROUND, FLOOR)

    ENDIF
