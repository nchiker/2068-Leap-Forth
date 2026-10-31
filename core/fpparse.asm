; ============================================================================
; core/fpparse.asm -- the number parser: integers and floats, one routine (docs/V2/FLOAT_SPEC.md section 6)
;
; Needs core/fpcore.asm. core/interp.asm's NUMBER jumps here. No dictionary words.
;
; The grammar is Leap-C's XF_ATOF (src/runtime/fpcore.asm, MIT, same copyright holder) without its suffixes:
;   [-] digits [. digits] [E|e [+|-] digits]   or   [-] . digits [exponent]
; at least one digit, the whole token consumed ("+5" is not a number). A token with a point or an exponent is a
; float: its digits are accumulated in a 32-bit integer N (a digit that would overflow it is dropped, and counted in
; the decimal exponent when it lies before the point), N is normalised and packed, then multiplied or divided by
; exact powers of ten (10^1 .. 10^13 per step, rounded to nearest at each step), as tools/fpmodel.py's atof.
; Anything else is an integer: -32768..65535 (a 16-bit pattern: 40000 is -25536 as a signed number). An integer
; outside that range and a float beyond the float range are THROW -43; a float below the range is 0.
;
; NUMBER's contract: ( addr -- n 1 ) an integer, ( addr -- 2 ) a float (on the float stack), ( addr -- 0 0 ) not a
; number. The token is a counted string; a NUL is stored after its last character (WORD_BUF has the room).
; ============================================================================

    IFNDEF CORE_FPPARSE_ASM
    DEFINE CORE_FPPARSE_ASM

; ============================================================================
; NUMBER_PARSE -- parse a token as an integer or a float (jumped to by NUMBER, which has popped the address)
; In:  HL -> the counted token, A = its length (not 0)
; Out: as NUMBER above; a NUL stored after the token
; Errors: THROW -43 (an integer outside -32768..65535, a float beyond the range)
; Destroys: AF, BC, DE, HL, BC', DE', HL'
; ============================================================================
NUMBER_PARSE:
    ld   c, a
    ld   b, 0
    inc  hl
    push hl
    add  hl, bc
    ld   (hl), 0
    pop  hl
    xor  a
    ld   (NUM_NEG), a
    ld   a, (hl)
    cp   "-"
    jr   nz, .nosign
    ld   (NUM_NEG), a
    inc  hl
.nosign:
    push hl
    ld   hl, FQ                        ; N, the decimal exponent and the flags = 0
    ld   b, 8
    call FZERO
    pop  hl
.dig:
    ld   a, (hl)
    cp   "."
    jr   z, .dot
    sub  "0"
    cp   10
    jr   nc, .mant
    inc  hl
    push hl
    ld   c, a
    ld   hl, FFLAGS
    set  0, (hl)                       ; a digit
    ld   a, (FQ)
    cp   $19                           ; N x 10 + 9 still fits in 32 bits?
    jr   nc, .full
    ld   hl, FQ + 3
    ld   b, 4
    call FMUL10                        ; N = N x 10 + the digit
    ld   a, (FFLAGS)
    and  2
    jr   z, .next
    ld   hl, -1                        ; in the fraction: 10^-1 more
    jr   .exp
.full:                                 ; N is full: a digit before the point is 10^1 more, one after it is dropped
    ld   a, (FFLAGS)
    and  2
    jr   nz, .next
    ld   hl, 1
.exp:
    ld   de, (FDEXP)
    add  hl, de
    ld   (FDEXP), hl
.next:
    pop  hl
    jr   .dig
.dot:
    ld   a, (FFLAGS)
    bit  1, a
    jr   nz, .none                     ; a second point
    or   6                             ; after the point, a float
    ld   (FFLAGS), a
    inc  hl
    jr   .dig
.none:
    jp   NUMBER.fail
.mant:
    ld   a, (FFLAGS)
    rra
    jr   nc, .none                     ; no digit
    ld   a, (hl)
    or   $20
    cp   "e"
    jr   nz, .end
    ld   a, (FFLAGS)
    or   4
    ld   (FFLAGS), a
    inc  hl
    ld   c, 0                          ; the exponent's sign
    ld   a, (hl)
    cp   "+"
    jr   z, .esign
    cp   "-"
    jr   nz, .edig
    dec  c
.esign:
    inc  hl
.edig:
    ld   de, 0                         ; the exponent
    ld   b, d                          ; its digits
.ed:
    ld   a, (hl)
    sub  "0"
    cp   10
    jr   nc, .eend
    inc  hl
    inc  b
    push hl
    ld   h, d
    ld   l, e
    add  hl, hl
    add  hl, hl
    add  hl, de
    add  hl, hl                        ; x 10 ...
    ld   e, a
    ld   d, 0
    add  hl, de                        ; ... + the digit
    ex   de, hl
    pop  hl
    ld   a, d
    cp   4
    jr   c, .ed
    ld   de, 999                       ; (beyond 1023 the value is 0 or too large anyway)
    jr   .ed
.eend:
    inc  b
    dec  b
    jr   z, .none                      ; an exponent without digits
    ld   a, c
    or   a
    jr   z, .epos
    xor  a
    sub  e
    ld   e, a
    sbc  a, a
    sub  d
    ld   d, a
.epos:
    push hl
    ld   hl, (FDEXP)
    add  hl, de
    ld   (FDEXP), hl
    pop  hl
.end:
    ld   a, (hl)
    or   a
    jr   nz, .none                     ; something is left over
    ld   a, (FFLAGS)
    bit  2, a
    jr   nz, .float
    ld   hl, (FDEXP)                   ; an integer: digits dropped, or above 16 bits, is out of range
    ld   a, h
    or   l
    jr   nz, .range
    ld   hl, (FQ)
    ld   a, h
    or   l
    jr   nz, .range
    ld   a, (FQ + 2)
    ld   h, a
    ld   a, (FQ + 3)
    ld   l, a
    ld   a, (NUM_NEG)
    or   a
    jr   z, .push
    ld   a, h                          ; -32768 at most
    cp   $80
    jr   c, .negate
    jr   nz, .range
    ld   a, l
    or   a
    jr   nz, .range
.negate:
    ex   de, hl
    ld   hl, 0
    or   a
    sbc  hl, de
.push:
    rst  RST_DPUSH
    ld   hl, 1
    rst  RST_DPUSH
    ret
.range:
    jp   F_RANGE

.float:
    ld   hl, FQ                        ; FX = N, e = 160
    ld   de, FX + U_M
    ld   bc, 4
    ldir
    xor  a
    ld   (FX + U_S), a
    ld   (FX + U_G), a
    ld   a, 128 + 32
    ld   (FX + U_E), a
    call FNORM
    ld   bc, -5
    add  iy, bc
    call FPACK                         ; the float stack's top = N
.scale:                                ; x or / 10^k, k at most 13, until the decimal exponent is 0 (or the value is)
    ld   a, (iy+0)
    or   a
    jr   z, .sdone
    ld   hl, (FDEXP)
    ld   a, h
    or   l
    jr   z, .sdone
    ld   de, 13
    bit  7, h
    jr   nz, .down
    or   a
    sbc  hl, de
    jr   nc, .mul                      ; 13 or more left: k = 13
    add  hl, de
    ld   e, l                          ; k = what is left
    ld   hl, 0
.mul:
    ld   (FDEXP), hl
    call .pow
    call FMULP
    jr   .scale
.down:
    add  hl, de
    bit  7, h
    jr   nz, .div
    ld   a, h
    or   l
    jr   z, .div                       ; exactly -13
    ld   a, 13                         ; -12 .. -1 left: k = -exponent
    sub  l
    ld   e, a
    ld   hl, 0
.div:
    ld   (FDEXP), hl
    call .pow
    call FDIVP
    jr   .scale
.pow:                                  ; HL -> 10^E in POW10
    dec  e
    ld   l, e
    ld   h, 0
    ld   d, h
    add  hl, hl
    add  hl, hl
    add  hl, de
    ld   de, POW10
    add  hl, de
    ret
.sdone:
    ld   a, (NUM_NEG)
    or   a
    call nz, FNEG_TOP
    ld   hl, 2
    rst  RST_DPUSH
    ret

; ============================================================================
; DOFLIT -- the run-time half of a compiled float literal (not a dictionary word)
; In:  the return address -> the 5 bytes of the float (core/interp.asm's DOLIT idiom)
; Out: the float pushed on the float stack; returns past it
; Destroys: AF, BC, DE, HL
; ============================================================================
DOFLIT:
    pop  hl
    call FPUSH_HL
    jp   (hl)

; ============================================================================
; COMPILE_FLOAT_LITERAL -- compile CALL DOFLIT and the 5 bytes of a float at HERE (not a dictionary word)
; In:  HL -> the 5 bytes
; Out: HERE advanced
; Destroys: AF, BC, DE, HL
; ============================================================================
COMPILE_FLOAT_LITERAL:
    push hl
    ld   hl, DOFLIT
    call COMPILE_CALL                  ; (DE = HERE after it)
    pop  hl
    ld   bc, 5
    ldir
    ld   (HERE), de
    ret

    ENDIF
