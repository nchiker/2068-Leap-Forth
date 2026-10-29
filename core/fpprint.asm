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
    jr   z, .space
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
.space:
    ld   a, " "
    jp   FEMIT

DICT_LATEST_INIT_FLOATPRINT EQU H_FDOT   ; head of the dictionary once this file is included

    ENDIF
