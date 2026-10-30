; ============================================================================
; core/fpprint.asm — F. (step F, docs/V2/FLOAT_SPEC.md section 7)
;
; Builds on core/fpcore.asm, core/print.asm (EMIT) and core/dict.asm.
;
;   F. ( r -- )   prints every integer digit, then "." and F_PLACES decimals (none and no point when F_PLACES is 0;
;                 the cold start sets 4), a "-" for a negative value unless every printed digit is 0, then a space.
;
; The decimals are the value's exact binary digits rounded half up (away from 0 in magnitude), so 0.25 with 1 place
; prints 0.3 and 0.03125 with 4 places 0.0313 (Leap-C's XF_FTOA rounds exact ties down and loses small values at
; 9 places; this rebuild differs there, tools/fpforth.py's fdot is its model). The value is laid out as 128.64 fixed
; point in FMT (16 integer bytes, 8 fraction bytes, big-endian): the mantissa is copied to its byte position and
; shifted by the remaining bits. A value below 2^-32 is left as 0: it rounds to 0 at every one of the 0-9 places,
; as fpforth's _fixed, which keeps 64 fraction bits, finds. The decimals come from multiplying the fraction by 10
; into FDIG, the rest of the fraction decides the rounding (its top bit), the carry runs back through FDIG and into
; the integer part; the integer digits come from dividing the 16 bytes by 10 (leading zero bytes skipped) and wait on
; the machine stack (39 at most) until the sign has been printed.
; ============================================================================

    IFNDEF CORE_FPPRINT_ASM
    DEFINE CORE_FPPRINT_ASM

; ============================================================================
; FDIV10 -- the B bytes big-endian from (HL) divided by 10 (Leap-C's)
; Out: A = the remainder. Destroys: AF, BC, HL
; ============================================================================
FDIV10:
    xor  a
.byte:
    push bc
    ld   c, (hl)
    ld   b, 8
.bit:
    sla  c
    rla
    cp   10
    jr   c, .z
    sub  10
    inc  c
.z:
    djnz .bit
    ld   (hl), c
    inc  hl
    pop  bc
    djnz .byte
    ret

; FEMIT -- print the character A, keeping BC and HL
FEMIT:
    push bc
    push hl
    ld   l, a
    ld   h, 0
    rst  RST_DPUSH
    call W_EMIT
    pop  hl
    pop  bc
    ret

; ============================================================================
; F. ( r -- )
; ============================================================================
H_FDOT:
    DW   DICT_CHAIN_POINT   ; the including ROM sets this (DEFL) to the chain this file extends, just before INCLUDEing it
    DB   2, "F", "."
W_FDOT:
    call FPOP_FX
    call FDCALC
    call FDPRINT
    ld   a, " "
    jp   FEMIT

; FDCALC -- FX (unpacked, a sign and a value) as 128.64 fixed point in FMT, the PLACES decimals in FDIG, rounded
; Destroys: AF, BC, DE, HL
FDCALC:
    ld   hl, FMT
    ld   b, 24
    call FZERO
    ld   a, (FX + U_E)
    or   a
    jr   z, .fixed
    sub  128
    jr   c, .right
    push af                            ; 2^n or more: the mantissa moves up n / 8 bytes, then n mod 8 bits
    rrca
    rrca
    rrca
    and  31
    ld   e, a
    ld   d, 0
    ld   hl, FMT + 16
    or   a
    sbc  hl, de
    ex   de, hl
    ld   hl, FX + U_M
    ld   bc, 4
    ldir
    dec  de
    ex   de, hl                        ; HL -> the last of the 5 bytes (one above the mantissa to take the bits)
    pop  af
    and  7
    jr   z, .fixed
    ld   c, a
.shl:
    push hl
    ld   b, 5
    or   a
    call FSHL
    pop  hl
    dec  c
    jr   nz, .shl
    jr   .fixed
.right:                                ; below 2^0: m = 128 - e places to the right
    neg
    cp   32
    jr   nc, .fixed                    ; 2^-32 or less: it prints as 0
    push af
    rrca
    rrca
    rrca
    and  31
    ld   e, a
    ld   d, 0
    ld   hl, FMT + 16
    add  hl, de
    ex   de, hl
    push de
    ld   hl, FX + U_M
    ld   bc, 4
    ldir
    pop  hl                            ; HL -> the mantissa's first byte; the 5th byte takes the bits
    pop  af
    and  7
    jr   z, .fixed
    ld   c, a
.shr:
    push hl
    ld   b, 5
    or   a
    call FSHR
    pop  hl
    dec  c
    jr   nz, .shr
.fixed:                                ; the decimals: the fraction x 10, the carry out is the digit
    ld   a, (F_PLACES)
    or   a
    ld   b, a
    ld   de, FDIG
    jr   z, .round
.dec:
    push bc
    push de
    ld   hl, FMT + 23
    ld   b, 8
    ld   c, 0
    call FMUL10
    pop  de
    pop  bc
    ld   (de), a
    inc  de
    djnz .dec
.round:
    ld   a, (FMT + 16)                 ; the rest of the fraction: half or more rounds up
    rla
    jr   nc, .rounded
    ld   a, (F_PLACES)
    ld   b, a
    ld   e, a
    ld   d, 0
    ld   hl, FDIG
    add  hl, de
.up:
    ld   a, b
    or   a
    jr   z, .intup                     ; out of digits: the carry goes into the integer part
    dec  hl
    dec  b
    inc  (hl)
    ld   a, (hl)
    cp   10
    jr   c, .rounded
    ld   (hl), 0
    jr   .up
.intup:
    ld   hl, FMT + 15
    ld   b, 16
.ip:
    inc  (hl)
    jr   nz, .rounded
    dec  hl
    djnz .ip
.rounded:
    ret

; FDPRINT -- prints FDCALC's result: "-" for a negative FX unless every printed digit is 0, the integer digits, and
; "." and the decimals (none and no point when PLACES is 0)
; Destroys: AF, BC, DE, HL
FDPRINT:
    ld   a, (FX + U_S)                 ; "-" for a negative value unless every printed digit is 0
    or   a
    jr   z, .digits
    ld   hl, FMT
    ld   b, 16
    xor  a
.o:
    or   (hl)
    inc  hl
    djnz .o
    ld   c, a
    ld   a, (F_PLACES)
    or   a
    ld   b, a
    ld   a, c
    jr   z, .nz
    ld   hl, FDIG
.d:
    or   (hl)
    inc  hl
    djnz .d
.nz:
    or   a
    jr   z, .digits
    ld   a, "-"
    call FEMIT
.digits:                               ; the integer digits, right to left, a 0 byte under them on the stack
    xor  a
    push af
.id:
    ld   hl, FMT
    ld   b, 16
.skip:
    ld   a, (hl)
    or   a
    jr   nz, .div
    inc  hl
    djnz .skip
    dec  hl                            ; all zero: the last byte alone, its digit is 0
    inc  b
.div:
    call FDIV10
    add  a, "0"
    push af
    ld   hl, FMT
    ld   b, 16
    xor  a
.z:
    or   (hl)
    inc  hl
    djnz .z
    jr   nz, .id
.pr:
    pop  af
    or   a
    jr   z, .point
    call FEMIT
    jr   .pr
.point:
    ld   a, (F_PLACES)
    or   a
    ret  z
    ld   b, a
    ld   a, "."
    call FEMIT
    ld   hl, FDIG
.pd:
    ld   a, (hl)
    add  a, "0"
    call FEMIT
    inc  hl
    djnz .pd
    ret

; ============================================================================
; PLACES ( n -- )  the decimals F. and FS. print, 0-9; another n: THROW -43
; ============================================================================
H_PLACES:
    DW   H_FDOT
    DB   6, "P", "L", "A", "C", "E", "S"
W_PLACES:
    rst  RST_DPOP
    ld   a, h
    or   a
    jp   nz, F_RANGE
    ld   a, l
    cp   10
    jp   nc, F_RANGE
    ld   (F_PLACES), a
    ret

; ============================================================================
; FS. ( r -- )  scientific notation: [-]d.ddddEn and a space (PLACES decimals, n in decimal, no "+").
; tools/fpforth.py's fsdot, step for step (FLOAT_SPEC section 7): a = |x|; n = ((e - 129) x 77) >> 8 (arithmetic) from
; the exponent byte e; a = a / 10^n in steps of POW10 entries of at most 13 (n > 0 divides, n < 0 multiplies); one
; more step if a >= 10 (a / 10, n + 1) or a < 1 (a x 10, n - 1); the digits are F.'s for a; a rounding carry makes
; the integer part 10, which is printed as 1 with n + 1 (the decimals are all 0 then). 0 prints 0, the decimals, E0.
; READING: the "-" is printed first, before the scaling (nothing between can fail or print); FDEXP's first byte, free
; (ATOF is not live), holds the exponent still to be scaled; n waits on the machine stack as a 16-bit number and
; the E and n are printed by W_DOT (which adds the space).
; ============================================================================
H_FSDOT:
    DW   H_PLACES
    DB   3, "F", "S", "."
W_FSDOT:
    ld   hl, 0                         ; n for 0
    ld   a, (iy+0)
    or   a
    jp   z, .digits
    bit  7, (iy+1)
    jr   z, .sign
    res  7, (iy+1)                     ; a = |x|
    ld   a, "-"
    call FEMIT
    ld   a, (iy+0)
.sign:
    sub  129                           ; e - 129: -128 to 126
    ld   l, a
    rla
    sbc  a, a
    ld   h, a
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, de                        ; 9x
    add  hl, hl
    add  hl, de                        ; 19x
    add  hl, hl
    add  hl, hl
    add  hl, de                        ; 77x
    ld   l, h                          ; >> 8, sign extended
    ld   a, h
    rla
    sbc  a, a
    ld   h, a
    ld   a, l
    ld   (FDEXP), a                    ; the exponent still to scale
.scale:
    push hl                            ; n
    ld   a, (FDEXP)
    or   a
    jr   z, .scaled
    ld   b, a
    jp   p, .k
    neg
.k:
    cp   14
    jr   c, .step
    ld   a, 13                         ; k = min(|d|, 13)
.step:
    ld   c, a
    ld   a, b                          ; d -= k (d > 0) or d += k (d < 0)
    bit  7, b
    jr   nz, .up
    sub  c
    jr   .set
.up:
    add  a, c
.set:
    ld   (FDEXP), a
    ld   a, c
    ld   l, a
    ld   h, 0
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, hl
    add  hl, de                        ; 5k
    ld   de, POW10 - 5
    add  hl, de                        ; -> POW10[k]
    bit  7, b
    jr   nz, .mul
    call FDIVP
    jr   .again
.mul:
    call FMULP
.again:
    pop  hl
    jr   .scale
.scaled:                               ; (n is on the stack)
    ld   hl, POW10
    call FCONSTX                       ; FX = 10, FY = a
    call FCMP
    jr   c, .big
    jr   nz, .small
.big:                                  ; 10 <= a
    ld   hl, POW10
    call FDIVP
    pop  hl
    inc  hl
    jr   .digits
.small:
    pop  hl
    ld   a, (iy+0)
    cp   129
    jr   nc, .digits                   ; 1 <= a < 10
    push hl
    ld   hl, POW10
    call FMULP
    pop  hl
    dec  hl
.digits:
    push hl                            ; n
    call FPOP_FX
    call FDCALC
    ld   hl, FMT + 15
    ld   a, (hl)
    cp   10
    jr   nz, .print
    ld   (hl), 1                       ; 10.0000 printed as 1.0000, n + 1
    pop  hl
    inc  hl
    push hl
.print:
    call FDPRINT
    ld   a, "E"
    call FEMIT
    pop  hl
    rst  RST_DPUSH
    jp   W_DOT

DICT_LATEST_INIT_FLOATPRINT EQU H_FSDOT   ; head of the dictionary once this file is included

    ENDIF
