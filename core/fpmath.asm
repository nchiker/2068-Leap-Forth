; ============================================================================
; core/fpmath.asm -- FSQRT, PI, SIN, COS, TAN, RAD, DEG (docs/V2/FLOAT_SPEC.md sections 8.1, 8.2)
;
; Needs core/fpcore.asm and core/dict.asm. Every word is a sequence of fpcore operations in the order
; tools/fpforth.py follows, so the ROM matches it byte for byte. Chained from DICT_CHAIN_POINT (set by the
; including ROM before the INCLUDE); every word may destroy all registers except IX (the data stack pointer), IY
; (the float stack pointer) and SP.
;
;   FSQRT ( r -- sqrt r )  Newton's method as Leap V2's SQR (rom/exrom_v2_vm_core.asm, MIT, same copyright holder):
;           5 steps of x = (x + n / x) / 2, the halving done by decrementing the exponent byte (exact: x is far above
;           2^-127). The first guess is 0.5 x 2^(e' - 128) with e' = (e + 130) >> 1 from n's exponent byte e, the
;           9-bit sum kept by the carry. 0 gives 0, a negative number THROW -46.
;   PI    ( -- r )         the 5-byte pi
;   SIN COS ( r -- r )     radians. t = x / pi (COS: + 1/2), k = t rounded half away from 0 (|k| > 32767, that is
;           |x| above about 102,940: THROW -43), r = (x - k P1) - k P2 with P1 = pi to 17 bits (k P1 is exact) and
;           P2 = pi - P1 (Cody-Waite; COS adds pi/2 to the small r), then Leap V2's series on r (rom/
;           exrom_v2_float_fn.asm 5.10, relative error 4.8e-11 for |r| <= 91 degrees): s = r + r^3 (c3 + r^2 (c5 +
;           r^2 (c7 + r^2 (c9 + r^2 c11)))); odd k negates it. COS shifts inside the reduction rather than as
;           SIN(x + pi/2), which would round x first.
;   TAN ( r -- r )        SIN x / COS x (tools/fpforth.py's ftan); a cosine of exactly 0: THROW -42
;   RAD DEG ( r -- r )     x pi/180, x 180/pi
; The constants are tools/fpforth.py's (PI, HALF_PI, INV_PI, P1, P2, DEG_K, SIN_COEFFS, HALF), each a DB row.
; ============================================================================

    IFNDEF CORE_FPMATH_ASM
    DEFINE CORE_FPMATH_ASM

K_PI:      DB $82, $49, $0F, $DA, $A2   ; 3.14159265347         pi
K_HALF_PI: DB $81, $49, $0F, $DA, $A2   ; 1.57079632673         pi / 2
K_INV_PI:  DB $7F, $22, $F9, $83, $6E   ; 0.318309886198        1 / pi
K_P1:      DB $82, $49, $10, $00, $00   ; 3.1416015625          pi to 17 significant bits
K_P2:      DB $70, $95, $77, $7A, $5D   ; -8.90891020688e-06    pi - P1
K_HALF:    DB $80, $00, $00, $00, $00   ; 0.5
K_RAD:     DB $7B, $0E, $FA, $35, $13   ; 0.0174532925229       pi / 180
K_DEG:     DB $86, $65, $2E, $E0, $D3   ; 57.2957795113          180 / pi
K_SERIES:  DB $67, $CC, $FD, $BB, $92   ; c11   (Leap V2 SIN_COEFFS, the highest first)
           DB $6E, $38, $B6, $AF, $CD   ; c9
           DB $74, $D0, $0B, $EA, $79   ; c7
           DB $7A, $08, $88, $86, $4C   ; c5
           DB $7E, $AA, $AA, $AA, $A5   ; c3 (about 1/6)

; ============================================================================
; FDUP -- push a copy of the top float (not a dictionary word)
; Out: the float stack one cell deeper
; Destroys: AF, BC, DE, HL
; ============================================================================
FDUP:
    push iy
    pop  hl
    jp   FPUSH_HL

; ============================================================================
; FSQRT ( r -- sqrt r ) -- square root by Newton's method (see the header); 0 gives 0, a negative number THROW -46
; ============================================================================
H_FSQRT:
    DW   DICT_CHAIN_POINT
    DB   5, "F", "S", "Q", "R", "T"
W_FSQRT:
    ld   a, (iy+0)
    or   a
    ret  z                             ; sqrt 0 = 0
    bit  7, (iy+1)
    jp   nz, F_INVALID
    ld   de, FSQ_N
    call FCOPY_DE                      ; FSQ_N = n
    add  a, 130                        ; (e + 130) >> 1, the 9th bit through the carry
    rra
    ld   (iy+0), a
    xor  a
    ld   (iy+1), a
    ld   (iy+2), a
    ld   (iy+3), a
    ld   (iy+4), a                     ; x = the guess
    ld   b, 4                          ; (the guess is within a factor of sqrt 2: 4 steps reach 2^-40)
.step:
    push bc
    ld   hl, FSQ_N
    ld   de, FX
    call FUNPK
    push iy
    pop  hl
    ld   de, FY
    call FUNPK
    call FDIV                          ; n / x, packed (rounded) before the sum, as the model's div
    ld   bc, -5
    add  iy, bc
    call FPACK                         ; [x q]
    call W_FPLUS                       ; [x + q]
    dec  (iy+0)                        ; / 2
    pop  bc
    djnz .step
    ret


; ============================================================================
; PI ( -- r ) -- the 5-byte pi
; ============================================================================
H_PI:
    DW   H_FSQRT
    DB   2, "P", "I"
W_PI:
    ld   hl, K_PI
    jp   FPUSH_HL

; ============================================================================
; FSINCOS -- the shared body of SIN and COS (not a dictionary word)
; In:  A = 0 for SIN, 1 for COS; the angle in radians on the float stack
; Out: the result replaces it; FTRIG_K holds k, FTRIG_R2 r^2 and FSQ_N r as scratch
; Errors: THROW -43 when |k| > 32767
; Destroys: AF, BC, DE, HL, BC', DE', HL'
; ============================================================================
FSINCOS:
    ld   (FTRIG_K + 1), a
    call FDUP                          ; [x x]
    ld   hl, K_INV_PI
    call FMULP                         ; [x t]
    ld   a, (FTRIG_K + 1)
    or   a
    ld   hl, K_HALF
    call nz, FADDP                     ; COS: t + 1/2
    xor  a
    call FINT                          ; [x kf]: k, rounded half away from 0
    push iy
    pop  hl
    ld   de, FX
    call FUNPK
    call FTOI
    jp   c, F_RANGE
    bit  7, h
    jp   nz, F_RANGE                   ; |k| above 32767
    ld   a, l
    ld   (FTRIG_K), a                  ; k's parity is the sign
    ld   de, FSQ_N
    call FPOP_DE                       ; FSQ_N = kf; [x]
    ld   hl, FSQ_N
    call FPUSH_HL
    ld   hl, K_P1
    call FMULP
    call W_FMINUS                      ; [x - kf P1]
    ld   hl, FSQ_N
    call FPUSH_HL
    ld   hl, K_P2
    call FMULP
    call W_FMINUS                      ; [r]
    ld   a, (FTRIG_K + 1)
    or   a
    ld   hl, K_HALF_PI
    call nz, FADDP                     ; COS: r + pi/2
    ld   de, FSQ_N
    call FCOPY_DE                      ; FSQ_N = r
    call FDUP
    call W_FSTAR                       ; [r^2]
    ld   de, FTRIG_R2
    call FCOPY_DE
    ld   hl, FSQ_N
    call FPUSH_HL
    call W_FSTAR                       ; [r^3]
    ld   hl, K_SERIES
    call FPUSH_HL                      ; [r^3 p], p = c11; HL -> c9
    ld   b, 4
.ser:                                  ; p = c + p r^2
    push bc
    push hl
    ld   hl, FTRIG_R2
    call FPUSH_HL
    call W_FSTAR
    pop  hl
    push hl
    call FADDP
    pop  hl
    ld   de, 5
    add  hl, de
    pop  bc
    djnz .ser
    call W_FSTAR                       ; [r^3 p]
    ld   hl, FSQ_N
    call FPUSH_HL
    call W_FPLUS                       ; [r + r^3 p]
    ld   a, (FTRIG_K)
    rra
    ret  nc
    jp   FNEG_TOP

; ============================================================================
; SIN ( r -- r ) -- sine of an angle in radians
; ============================================================================
H_SIN:
    DW   H_PI
    DB   3, "S", "I", "N"
W_SIN:
    xor  a
    jp   FSINCOS

; ============================================================================
; COS ( r -- r ) -- cosine of an angle in radians
; ============================================================================
H_COS:
    DW   H_SIN
    DB   3, "C", "O", "S"
W_COS:
    ld   a, 1
    jp   FSINCOS


; ============================================================================
; TAN ( r -- r ) -- tangent of an angle in radians: SIN x / COS x, the sine kept in FMT (F.'s buffer, free here)
; while COS runs
; Errors: THROW -42 for a cosine of exactly 0 (FDIV's), -43 as SIN's
; ============================================================================
H_TAN:
    DW   H_COS
    DB   3, "T", "A", "N"
W_TAN:
    call FDUP                          ; [x x]
    call W_SIN                         ; [x s]
    ld   de, FMT
    call FPOP_DE                       ; FMT = s; [x]
    call W_COS                         ; [c]
    ld   hl, FMT
    call FCONSTX                       ; FX = s, FY = c
    call FDIV
    jp   FPACK

; ============================================================================
; RAD ( degrees -- radians ) -- x pi/180
; ============================================================================
H_RAD:
    DW   H_TAN
    DB   3, "R", "A", "D"
W_RAD:
    ld   hl, K_RAD
    jp   FMULP

; ============================================================================
; DEG ( radians -- degrees ) -- x 180/pi
; ============================================================================
H_DEG:
    DW   H_RAD
    DB   3, "D", "E", "G"
W_DEG:
    ld   hl, K_DEG
    jp   FMULP


    ENDIF
