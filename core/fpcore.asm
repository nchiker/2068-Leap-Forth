; ============================================================================
; core/fpcore.asm — the float engine and F+ F- F* F/ (step F, docs/V2/FLOAT_SPEC.md sections 4, 5, 9)
;
; Floats are the Sinclair 5-byte format: [exponent][sign | mantissa bits 30-24][23-16][15-8][7-0], value
; 0.1m x 2^(exponent - 128) (the leading 1 implicit), 0 for exponent 0, always normalised. The float stack is
; IY, growing down from FSTACK_TOP: the top cell is (iy+0)..(iy+4), a push is iy -= 5. There are no infinities,
; NaN or negative zero; overflow and division by zero are errors (THROW -43, -42), underflow gives 0.
;
; ORIGIN: rebuilt from 2068-Leap-C's src/runtime/fpcore.asm (MIT, same copyright holder as this project): the
; unpacked working form [sign][exponent][m0..m3][guard] (a 40-bit mantissa), FUNPK/FPACK (round to nearest on the
; guard's top bit), FNORM, FADD (the larger magnitude first), FDONE, FSIGN, FCMP, FFROM, the byte helpers FSHL/
; FSHR/FADDN/FSUBN/FZERO/FMUL10 and the table of exact powers of ten, so that tools/fpmodel.py (Leap-C's bit-exact
; model, vendored) stays the oracle: every result here is byte-identical to tools/fpforth.py's. What differs:
;   - the accumulator is the float stack's top (FPACK writes (iy+0)), not a fixed cell; a binary word unpacks
;     (iy+5), the left operand, into FX and (iy+0), the right one, into FY, drops one cell and packs into the new top;
;   - the 32 multiply and 40 divide steps run in registers (FMUL_K, FDIV_K: shift-and-add and restoring division
;     with the partial product or remainder in HL, H'L', C' and the operand in DE, D'E'), not through the byte-loop
;     helpers: about 3.5 kT per F* and 4.5 kT per F/ instead of 19 and 34. They compute fpmodel.mul's and .div's
;     loops exactly (checked on 5,698 cases in tools/z80sim). They use EXX and never AF'; no interrupt routine of
;     this ROM or of the stock ROM serving the cartridge build changes BC', DE', HL' (FLOAT_SPEC section 5);
;   - FADD aligns by whole bytes first, then by bits (the same floor(y / 2^d), so the same results);
;   - errors leave through F_THROW (THROW with the ANS codes), not Leap-C's F_ERR.
;
; Exports for the other float files: the engine routines below, FPUSH_HL (push the 5 bytes at HL), FPOP_DE (copy the
; top to (DE) and drop it), FMULP/FDIVP/FADDP (top op a constant), FPOP_FX, FNEG_TOP, the error entries, POW10.
; ============================================================================

    IFNDEF CORE_FPCORE_ASM
    DEFINE CORE_FPCORE_ASM

FSTACK_TOP   EQU $9000   ; empty-stack value of IY; the first push lands at $8FFB
FSTACK_LIMIT EQU $8C04   ; lowest legal IY: 204 cells ($9000 - 204 * 5) in $8C00-$8FFF

; ---- RAM (docs/V2/FLOAT_SPEC.md section 9): $8594-$85D5, inside the cold start's zero fill ----
FP_RAM   EQU $8594
FX       EQU FP_RAM          ; 7 B unpacked: [sign $80/0][exponent][m0 m1 m2 m3][guard]
FY       EQU FP_RAM + 7      ; 7 B
FQ       EQU FP_RAM + 14     ; 5 B: a product or quotient being built (big-endian); N in ATOF; scratch elsewhere
FDEXP    EQU FP_RAM + 19     ; 2 B: ATOF's decimal exponent ...
FFLAGS   EQU FP_RAM + 21     ; 1 B: ... bit 0 a digit seen, bit 1 after the point, bit 2 a float
FMT      EQU FP_RAM + 20     ; 24 B: F.'s 128.64 fixed point, 16 integer bytes then 8 fraction bytes, big-endian
                             ; (overlaps FDEXP's second byte and FFLAGS: ATOF and F. are never live together)
FDIG     EQU FP_RAM + 44     ; 9 B: F.'s decimals, one digit per byte
FSQ_N    EQU FP_RAM + 53     ; 5 B: FSQRT's argument; SIN/COS keep k * pi's k and then r here
FTRIG_R2 EQU FP_RAM + 58     ; 5 B: r squared in the series
FTRIG_K  EQU FP_RAM + 63     ; 2 B: [k's low byte, its parity is the sign][1 for COS]
F_PLACES EQU FP_RAM + 65     ; 1 B: decimals F. prints (0-9; the cold start sets 4)
    ASSERT F_PLACES == $85D5 && FMT + 24 == FDIG && FDIG + 9 == FSQ_N && FQ + 8 == FFLAGS + 1   ; (FQ, FDEXP, FFLAGS: 8 bytes in a row)

U_S EQU 0                    ; offsets in an unpacked float
U_E EQU 1
U_M EQU 2                    ; m0, the most significant
U_G EQU 6                    ; the guard byte

; ============================================================================
; FUNPK -- unpack a float
; In:  HL -> 5 packed bytes, DE -> 7 bytes for it unpacked
; Out: HL -> its sign byte
; Destroys: AF, BC, DE
; ============================================================================
FUNPK:
    push de
    inc  de
    ld   bc, 5
    ldir                               ; [e][sign | m0][m1][m2][m3]
    xor  a
    ld   (de), a                       ; the guard
    pop  hl
    inc  hl
    or   (hl)                          ; A = e: Z for 0
    inc  hl
    jr   z, .zero
    ld   a, (hl)
    set  7, (hl)                       ; m0's leading 1
    and  $80
.zero:                                 ; (0: sign 0)
    dec  hl
    dec  hl
    ld   (hl), a
    ret

; ============================================================================
; FPACK -- (iy+0) = FX, rounded to nearest on the guard's top bit (a carry out of the mantissa raises the exponent)
; Errors: THROW -43 (the exponent passes 255)
; Destroys: AF, BC, DE, HL
; ============================================================================
FPACK:
    ld   hl, FX + U_G
    bit  7, (hl)
    jr   z, .pack
    ld   b, 4
.rnd:
    dec  hl
    inc  (hl)
    jr   nz, .pack
    djnz .rnd
    ld   (hl), $80                     ; 0.111...1 + 1 ulp = 1.000: the mantissa $80000000, e + 1
    dec  hl
    inc  (hl)
    jp   z, F_RANGE
.pack:
    push iy
    pop  de
    ld   hl, FX + U_E
    ld   a, (hl)
    or   a
    jr   z, .zero
    ld   bc, 5
    ldir                               ; e, m0 .. m3
    ld   a, (FX + U_S)
    or   $7F
    and  (iy+1)                        ; m0's top bit is 1: it becomes the sign
    ld   (iy+1), a
    ret
.zero:                                 ; (A = 0)
    ex   de, hl
    ld   b, 5
FZERO:                                 ; HL -> B bytes = 0. Destroys: AF, B, HL
    xor  a
.z:
    ld   (hl), a
    inc  hl
    djnz .z
    ret
FZEROX:                                ; FX = 0. Destroys: AF, B, HL
    ld   hl, FX
    ld   b, 7
    jr   FZERO

; ============================================================================
; Errors: one entry, F_THROW, with the ANS code in HL (a ROM without THROW/CATCH stops here)
; ============================================================================
F_RANGE:                               ; -43 floating-point result out of range
    ld   hl, -43
    jr   F_THROW
F_DIVZERO:                             ; -42 floating-point divide by zero
    ld   hl, -42
    jr   F_THROW
F_INVALID:                             ; -46 floating-point invalid argument
    ld   hl, -46
F_THROW:
    IFDEF THROW_CATCH_ENABLED
    rst  RST_DPUSH
    jp   W_THROW
    ELSE
    jr   $
    ENDIF

; ============================================================================
; FNORM -- FX normalised: the mantissa shifted left until its top bit is set, the exponent lowered; 0 when the
; mantissa is 0 or the exponent falls below 1
; Destroys: AF, BC, HL
; ============================================================================
FNORM:
    ld   hl, FX + U_M
    ld   b, 5
    xor  a
.t:
    or   (hl)
    inc  hl
    djnz .t
    jr   z, FZEROX
.l:
    ld   a, (FX + U_M)
    rla
    ret  c
    ld   hl, FX + U_E
    dec  (hl)
    jr   z, FZEROX
    ld   hl, FX + U_G
    ld   b, 5
    or   a
    call FSHL
    jr   .l

; ============================================================================
; Multi-byte helpers on big-endian numbers
; FSHL -- (HL) = the least significant byte of B bytes: shift them left one bit, carry in and out
; FSHR -- (HL) = the most significant byte of B bytes: shift them right one bit, carry in and out
; FADDN, FSUBN -- (DE) += / -= (HL), B bytes, HL and DE at the least significant bytes: C = the carry or borrow out
; Destroys: F, B, DE, HL (FADDN, FSUBN: and A)
; ============================================================================
FSHL:
    rl   (hl)
    dec  hl
    djnz FSHL
    ret
FSHR:
    rr   (hl)
    inc  hl
    djnz FSHR
    ret
FADDN:
    or   a
.l:
    ld   a, (de)
    adc  a, (hl)
    ld   (de), a
    dec  hl
    dec  de
    djnz .l
    ret
FSUBN:
    or   a
.l:
    ld   a, (de)
    sbc  a, (hl)
    ld   (de), a
    dec  hl
    dec  de
    djnz .l
    ret

; ============================================================================
; FADD -- FX += FY (signed magnitudes): the larger magnitude in FX, FY shifted right by the exponent difference
; (whole bytes, then bits), the two 40-bit mantissas added or subtracted
; Errors: THROW -43. Destroys: AF, BC, DE, HL
; ============================================================================
FADD:
    ld   a, (FY + U_E)
    or   a
    ret  z                             ; x + 0
    ld   a, (FX + U_E)
    or   a
    jr   nz, .go
    ld   hl, FY                        ; 0 + y
    ld   de, FX
    ld   bc, 7
    ldir
    ret
.go:
    ld   hl, FX + U_E                  ; the larger magnitude in FX
    ld   de, FY + U_E
    ld   b, 6
.c:
    ld   a, (de)
    cp   (hl)
    jr   nz, .cd
    inc  hl
    inc  de
    djnz .c
    jr   .al
.cd:
    call nc, FSWAP                     ; FY's is larger
.al:
    ld   a, (FY + U_E)
    ld   b, a
    ld   a, (FX + U_E)
    sub  b                             ; the exponents' difference
    cp   40
    ret  nc                            ; FY lies below the guard byte
    or   a
    jr   z, .same
    push af
    rrca
    rrca
    rrca
    and  7                             ; whole bytes
    jr   z, .bits
    ld   b, a
.byte:
    ld   hl, FY + U_G - 1
    ld   de, FY + U_G
    push bc
    ld   bc, 4
    lddr                               ; FY's mantissa and guard, one byte down
    pop  bc
    xor  a
    ld   (FY + U_M), a
    djnz .byte
.bits:
    pop  af
    and  7
    jr   z, .same
    ld   b, a
    ld   de, (FY + U_M)                ; E = m0, D = m1
    ld   hl, (FY + U_M + 2)            ; L = m2, H = m3
    ld   a, (FY + U_G)
    ld   c, a
.sh:
    srl  e
    rr   d
    rr   l
    rr   h
    rr   c
    djnz .sh
    ld   (FY + U_M), de
    ld   (FY + U_M + 2), hl
    ld   a, c
    ld   (FY + U_G), a
.same:
    ld   a, (FY + U_S)
    ld   hl, FX + U_S
    xor  (hl)
    ld   hl, FY + U_G
    ld   de, FX + U_G
    ld   b, 5
    jr   nz, .sub
    call FADDN
    ret  nc
    ld   hl, FX + U_M                  ; a carry: one bit more
    ld   b, 5
    call FSHR                          ; (the carry comes in at the top)
    ld   hl, FX + U_E
    inc  (hl)
    ret  nz
    jp   F_RANGE
.sub:
    call FSUBN
    jp   FNORM
FSWAP:                                 ; FX <-> FY
    ld   hl, FX
    ld   de, FY
    ld   b, 7
.s:
    ld   a, (de)
    ld   c, (hl)
    ld   (hl), a
    ld   a, c
    ld   (de), a
    inc  hl
    inc  de
    djnz .s
    ret

; ============================================================================
; FMUL -- FX *= FY: 32 x 32 bits, the product's top 40 bits
; FDIV -- FX /= FY: 40 quotient bits by restoring division
; Errors: THROW -43 (overflow); FDIV: -42 (FY = 0). Destroys: AF, BC, DE, HL, BC', DE', HL'
; ============================================================================
FMUL:
    ld   a, (FX + U_E)
    or   a
    ret  z
    ld   a, (FY + U_E)
    or   a
    jp   z, FZEROX
    call FSIGN
    add  hl, de
    push hl                            ; ex + ey
    call FMUL_K
    pop  hl
    ld   de, -128
    jr   FDONE
FDIV:
    ld   a, (FY + U_E)
    or   a
    jp   z, F_DIVZERO
    ld   a, (FX + U_E)
    or   a
    ret  z
    call FSIGN
    or   a
    sbc  hl, de
    push hl                            ; ex - ey
    call FDIV_K
    pop  hl
    ld   de, 129                       ; the first bit has the weight 2^0
FDONE:                                 ; FX's mantissa = FQ, exponent HL + DE
    add  hl, de
    push hl
    ld   hl, FQ
    ld   de, FX + U_M
    ld   bc, 5
    ldir
    pop  hl
    ld   a, (FX + U_M)                 ; at most one place to normalise
    rla
    jr   c, .n
    dec  hl
    push hl
    ld   hl, FX + U_G
    ld   b, 5
    or   a
    call FSHL
    pop  hl
.n:
    ld   a, h
    or   a
    jr   nz, .out
    or   l
    jp   z, FZEROX                     ; below the range: 0
    ld   (FX + U_E), a
    ret
.out:
    jp   m, FZEROX
    jp   F_RANGE
; FSIGN -- FX's sign = the product's or quotient's; HL = ex, DE = ey. Destroys: AF, DE, HL
FSIGN:
    ld   hl, FX + U_S
    ld   a, (FY + U_S)
    xor  (hl)
    ld   (hl), a
    ld   a, (FX + U_E)
    ld   l, a
    ld   h, 0
    ld   a, (FY + U_E)
    ld   e, a
    ld   d, h
    ret

; FMUL_K -- FQ = the top 40 bits of FX's mantissa x FY's (32 x 32 bits): fpmodel.mul's q, shift and add from the
; multiplier's lowest bit, the 40-bit partial product in H L (bits 39-24), H' L' (23-8) and C' (7-0), the
; multiplicand in D E (31-16) and D' E' (15-0). Destroys: AF, BC, DE, HL, BC', DE', HL'
FMUL_K:
    exx
    ld   hl, (FX + U_M + 2)
    ld   d, l
    ld   e, h                          ; DE' = m2 m3
    ld   hl, 0
    ld   c, l                          ; HL' C' = 0
    exx
    ld   hl, (FX + U_M)
    ld   d, l
    ld   e, h                          ; DE = m0 m1
    ld   hl, 0
    ld   a, (FY + U_M + 3)             ; the multiplier's bytes, the lowest first
    call .byte
    ld   a, (FY + U_M + 2)
    call .byte
    ld   a, (FY + U_M + 1)
    call .byte
    ld   a, (FY + U_M)
    call .byte
    ld   a, h
    ld   (FQ), a
    ld   a, l
    ld   (FQ + 1), a
    exx
    ld   a, h
    ld   (FQ + 2), a
    ld   a, l
    ld   (FQ + 3), a
    ld   a, c
    ld   (FQ + 4), a
    exx
    ret
.byte:
    ld   b, 8
.bit:
    srl  a                             ; C = the next multiplier bit
    jr   nc, .shift                    ; (NC: nothing added, nothing carried)
    exx
    add  hl, de
    exx
    adc  hl, de                        ; C = the carry out of bit 39
.shift:
    rr   h
    rr   l
    exx
    rr   h
    rr   l
    rr   c
    exx
    djnz .bit
    ret

; FDIV_K -- FQ = 40 quotient bits of FX's mantissa / FY's: fpmodel.div's restoring division with its 33rd
; remainder bit (the carry between steps), the remainder in H L (31-16) H' L' (15-0), the divisor in D E D' E',
; the quotient's byte being built in A. Destroys: AF, BC, DE, HL, BC', DE', HL'
FDIV_K:
    ld   hl, (FY + U_M + 2)
    ld   d, l
    ld   e, h                          ; DE (alternate after the exx) = the divisor's m2 m3
    ld   hl, (FX + U_M + 2)
    ld   a, l
    ld   l, h
    ld   h, a                          ; HL (alternate) = the dividend's m2 m3
    exx
    ld   hl, (FY + U_M)
    ld   d, l
    ld   e, h                          ; DE = the divisor's m0 m1
    ld   hl, (FX + U_M)
    ld   a, l
    ld   l, h
    ld   h, a                          ; HL = the dividend's m0 m1
    or   a                             ; the 33rd bit: 0
    call .byte
    ld   (FQ), a
    call .byte
    ld   (FQ + 1), a
    call .byte
    ld   (FQ + 2), a
    call .byte
    ld   (FQ + 3), a
    call .byte
    ld   (FQ + 4), a
    exx                                ; (the sets back as they were: the setup's exx above)
    ret
.byte:
    ld   b, 8
.bit:
    jr   c, .force                     ; R had a 33rd bit: R >= D
    exx
    sbc  hl, de                        ; (C is clear)
    exx
    sbc  hl, de
    jr   nc, .one
    exx
    add  hl, de
    exx
    adc  hl, de                        ; restored
    or   a                             ; this bit: 0
    jr   .q
.force:
    exx
    or   a
    sbc  hl, de
    exx
    sbc  hl, de
.one:
    scf
.q:
    rla                                ; the bit into the quotient byte
    exx
    add  hl, hl
    exx
    adc  hl, hl                        ; R <<= 1; C = its 33rd bit
    djnz .bit
    ret

; ============================================================================
; FCMP -- compare FX with FY
; Out: C = FX < FY, Z = equal, NC NZ = FX > FY. Destroys: AF, B, DE, HL
; ============================================================================
FCMP:
    ld   a, (FY + U_S)
    ld   hl, FX + U_S
    cp   (hl)
    ret  nz                            ; the signs differ: the negative one is smaller
    ld   de, FY + U_E
    inc  hl
    or   a
    jr   z, .c
    ex   de, hl                        ; both negative: the larger magnitude is the smaller value
.c:
    ld   b, 5
.byte:
    ld   a, (hl)
    ex   de, hl
    cp   (hl)
    ex   de, hl
    ret  nz
    inc  hl
    inc  de
    djnz .byte
    ret

; ============================================================================
; FMUL10 -- the B bytes big-endian ending at (HL) times 10, plus C
; Out: A = the carry out (the digit). Destroys: AF, BC, DE, HL
; ============================================================================
FMUL10:
    ld   a, (hl)
    push hl
    ld   l, a
    ld   h, 0
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, hl
    add  hl, de
    add  hl, hl                        ; the byte x 10 ...
    ld   e, c
    add  hl, de                        ; ... + the carry
    ld   c, h
    ld   a, l
    pop  hl
    ld   (hl), a
    dec  hl
    djnz FMUL10
    ld   a, c
    ret

; ============================================================================
; FFROM -- FX = the 16-bit magnitude HL with the sign A ($80 or 0), normalised
; FIPART -- DE:HL = the top A bits (1-32) of FX's mantissa, which are the integer part of the value when A is the
;           exponent - 128; FX's mantissa = the bits that remain, left-aligned (the guard is 0)
; FTOI -- HL = the magnitude of FX's integer part (0 for |FX| < 1); C if it needs more than 16 bits
; Destroys: AF, BC, DE, HL
; ============================================================================
FFROM:
    ld   (FX + U_S), a
    ld   a, h
    ld   (FX + U_M), a
    ld   a, l
    ld   (FX + U_M + 1), a
    xor  a
    ld   (FX + U_M + 2), a
    ld   (FX + U_M + 3), a
    ld   (FX + U_G), a
    ld   a, 128 + 16
    ld   (FX + U_E), a
    jp   FNORM
FIPART:
    ld   c, a
    ld   de, 0
    ld   hl, 0
.bit:
    push de
    push hl
    ld   hl, FX + U_M + 3
    ld   b, 4
    or   a
    call FSHL                          ; C = the next integer bit, the top one first
    pop  hl
    pop  de
    adc  hl, hl
    ex   de, hl
    adc  hl, hl
    ex   de, hl
    dec  c
    jr   nz, .bit
    ret
FTOI:
    ld   hl, 0
    ld   a, (FX + U_E)
    sub  128
    jr   z, .none
    jr   c, .none                      ; below 1 (and 0)
    cp   17
    jr   nc, .over
    call FIPART
.none:
    or   a
    ret
.over:
    scf
    ret

; ============================================================================
; Float stack plumbing (not dictionary words)
; FPUSH_HL -- push the 5 bytes at HL. Out: HL -> past them. Destroys: AF, BC, DE
; FCOPY_DE -- copy the top cell to (DE). FPOP_DE -- the same, and drop the cell
;      Out: DE -> past the copy. Destroys: AF, BC, HL
; FPOP_FX -- FX = the top cell unpacked, and drop it. Destroys: AF, BC, DE, HL
; FNEG_TOP -- negate the top cell (0 stays 0). Destroys: AF
; ============================================================================
FPUSH_HL:
    ld   bc, -5
    add  iy, bc
    push iy
    pop  de
    ld   bc, 5
    ldir
    ret
FCOPY_DE:
    push iy
    pop  hl
    ld   bc, 5
    ldir
    ret
FPOP_DE:
    call FCOPY_DE
    ld   c, 5
    add  iy, bc
    ret
FPOP_FX:
    push iy
    pop  hl
    ld   de, FX
    call FUNPK
    ld   bc, 5
    add  iy, bc
    ret
FNEG_TOP:
    ld   a, (iy+0)
    or   a
    ret  z
    ld   a, (iy+1)
    xor  $80
    ld   (iy+1), a
    ret

; ============================================================================
; FBIN -- the operands of a binary word: FX = (iy+5) unpacked (the left one), FY = (iy+0) (the right one), one cell
; dropped; the word packs its result into the new top
; FMULP, FDIVP, FADDP -- (iy+0) = (iy+0) * / + the constant at HL (FDIVP: top / constant). The sum and the product
;      are commutative bit for bit, so the constant is the left operand there
; Destroys: AF, BC, DE, HL, BC', DE', HL'
; ============================================================================
FBIN:
    push iy
    pop  hl
    ld   de, FY
    call FUNPK
    ld   bc, 5
    add  iy, bc
    push iy
    pop  hl
    ld   de, FX
    jp   FUNPK
FMULP:
    call FCONSTX
    call FMUL
    jp   FPACK
FADDP:
    call FCONSTX
    call FADD
    jp   FPACK
FDIVP:
    ld   de, FY
    call FUNPK
    push iy
    pop  hl
    ld   de, FX
    call FUNPK
    call FDIV
    jp   FPACK
FCONSTX:                               ; FX = the constant at HL, FY = the top cell
    ld   de, FX
    call FUNPK
    push iy
    pop  hl
    ld   de, FY
    jp   FUNPK

; ============================================================================
; F+ ( r1 r2 -- r1+r2 )
; ============================================================================
H_FPLUS:
    DW   DICT_CHAIN_POINT   ; the including ROM sets this (DEFL) to the chain this file extends, just before INCLUDEing it
    DB   2, "F", "+"
W_FPLUS:
    call FBIN
    call FADD
    jp   FPACK

; ============================================================================
; F- ( r1 r2 -- r1-r2 )
; ============================================================================
H_FMINUS:
    DW   H_FPLUS
    DB   2, "F", "-"
W_FMINUS:
    call FBIN
    ld   hl, FY + U_S
    ld   a, (hl)
    xor  $80
    ld   (hl), a
    call FADD
    jp   FPACK

; ============================================================================
; F* ( r1 r2 -- r1*r2 )
; ============================================================================
H_FSTAR:
    DW   H_FMINUS
    DB   2, "F", "*"
W_FSTAR:
    call FBIN
    call FMUL
    jp   FPACK

; ============================================================================
; F/ ( r1 r2 -- r1/r2 )
; ============================================================================
H_FSLASH:
    DW   H_FSTAR
    DB   2, "F", "/"
W_FSLASH:
    call FBIN
    call FDIV
    jp   FPACK

; 10^1 .. 10^13, exact (5^13 < 2^32): ATOF's and FS.'s scaling steps
POW10:
    DB   $84, $20, $00, $00, $00
    DB   $87, $48, $00, $00, $00
    DB   $8A, $7A, $00, $00, $00
    DB   $8E, $1C, $40, $00, $00
    DB   $91, $43, $50, $00, $00
    DB   $94, $74, $24, $00, $00
    DB   $98, $18, $96, $80, $00
    DB   $9B, $3E, $BC, $20, $00
    DB   $9E, $6E, $6B, $28, $00
    DB   $A2, $15, $02, $F9, $00
    DB   $A5, $3A, $43, $B7, $40
    DB   $A8, $68, $D4, $A5, $10
    DB   $AC, $11, $84, $E7, $2A

DICT_LATEST_INIT_P8       EQU H_FMINUS   ; heads of the dictionary once F+ F-, F*, F/ are included
DICT_LATEST_INIT_FLOATMUL EQU H_FSTAR
DICT_LATEST_INIT_FLOATDIV EQU H_FSLASH

    ENDIF
