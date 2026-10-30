; ============================================================================
; core/fpstack.asm -- the float stack words, comparisons and memory (docs/V2/FLOAT_SPEC.md 8.3)
;
; Needs core/fpcore.asm (FBIN, FCMP, FPUSH_HL, FPOP_DE, FNEG_TOP), core/fpparse.asm (COMPILE_FLOAT_LITERAL)
; and core/variable.asm (VAR_HEADER, VAR_END, VARIABLE_N). Included by rom/forth_boot.asm only. Chained from
; DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy all registers except IX
; (the data stack pointer), IY (the float stack pointer) and SP. Flags are -1 (true) and 0, as `<`.
;
;   FDUP ( r -- r r )   FDROP ( r -- )   FSWAP ( r1 r2 -- r2 r1 )   FOVER ( r1 r2 -- r1 r2 r1 )
;   FDEPTH ( -- n )     the floats on the float stack
;   FNEGATE ( r -- -r ) FABS ( r -- |r| )
;   F< F> F= ( r1 r2 -- flag )   F0< F0= ( r -- flag )   FMIN FMAX ( r1 r2 -- r3 )
;   F@ ( addr -- r )    F! ( r addr -- )
;   FVARIABLE ( "name" -- )   <name> ( -- addr ) of 5 zero bytes
;   FCONSTANT ( r "name" -- ) <name> ( -- r ), code: CALL DOFLIT, the 5 bytes, RET
;
; One compare path: FCMPA (FBIN, FCMP) leaves A = -1, 0, 1 for r1 <, =, > r2; each of F< F> F= turns that into Z for
; "true" and shares FFLAGZ; F0< F0= test the cell's bytes and share it too; FMIN and FMAX share FSEL. The engine's
; FSWAP is FX <-> FY; the word's code is W_FSWAP.
; ============================================================================

    IFNDEF CORE_FPSTACK_ASM
    DEFINE CORE_FPSTACK_ASM

; ============================================================================
; FDUP ( r -- r r ) -- the engine's FDUP (core/fpmath.asm)
; ============================================================================
H_FDUP:
    DW   DICT_CHAIN_POINT
    DB   4, "F", "D", "U", "P"
W_FDUP:
    jp   FDUP

; ============================================================================
; FDROP ( r -- ) -- drop the top float
; ============================================================================
H_FDROP:
    DW   H_FDUP
    DB   5, "F", "D", "R", "O", "P"
W_FDROP:
    ld   bc, 5
    add  iy, bc
    ret

; ============================================================================
; FSWAP ( r1 r2 -- r2 r1 ) -- exchange the top two floats (the engine's FSWAP is FX <-> FY)
; ============================================================================
H_FSWAP:
    DW   H_FDROP
    DB   5, "F", "S", "W", "A", "P"
W_FSWAP:
    push iy
    pop  de                            ; DE -> r2
    ld   hl, 5
    add  hl, de                        ; HL -> r1
    ld   b, 5
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
; FOVER ( r1 r2 -- r1 r2 r1 ) -- copy the second float to the top
; ============================================================================
H_FOVER:
    DW   H_FSWAP
    DB   5, "F", "O", "V", "E", "R"
W_FOVER:
    push iy
    pop  hl
    ld   de, 5
    add  hl, de
    jp   FPUSH_HL

; ============================================================================
; FDEPTH ( -- n ) -- the floats on the float stack: (FSTACK_TOP - IY) / 5, by counting the fives
; ============================================================================
H_FDEPTH:
    DW   H_FOVER
    DB   6, "F", "D", "E", "P", "T", "H"
W_FDEPTH:
    ld   hl, FSTACK_TOP
    push iy
    pop  de
    or   a
    sbc  hl, de                        ; 5 per cell
    ld   bc, -1
    ld   de, -5
.l:
    inc  bc
    add  hl, de
    jr   c, .l                         ; (carry while at least 5 remain)
    ld   h, b
    ld   l, c
    rst  RST_DPUSH
    ret

; ============================================================================
; FNEGATE ( r -- -r )   FABS ( r -- |r| ) -- change / clear the sign (a zero cell is all zero bytes: its sign bit is clear already)
; ============================================================================
H_FNEGATE:
    DW   H_FDEPTH
    DB   7, "F", "N", "E", "G", "A", "T", "E"
W_FNEGATE:
    jp   FNEG_TOP

H_FABS:
    DW   H_FNEGATE
    DB   4, "F", "A", "B", "S"
W_FABS:
    res  7, (iy+1)
    ret

; ============================================================================
; FCMPA -- compare the two top cells: both are unpacked (FBIN: the left operand r1 in FX, r2 in FY) and
;          one dropped, so IY -> r1
; Out: A = -1 for r1 < r2, 0 for equal, 1 for r1 > r2; r2 still lies below IY (FSEL uses it)
; Destroys: AF, BC, DE, HL, BC', DE', HL'
; FFLAGZ -- drop one cell and push the flag: -1 when Z (the caller's test of A), else 0
; Out: flag on the data stack. Destroys: AF, BC, HL
; ============================================================================
FCMPA:
    call FBIN
    call FCMP                          ; C: r1 < r2, Z: equal
    ld   a, 0
    ret  z
    sbc  a, a                          ; C: -1, else 0
    ret  c
    inc  a
    ret
FFLAGZ:
    call W_FDROP                       ; (keeps Z)
    ld   hl, 0
    jr   nz, .push
    dec  hl
.push:
    rst  RST_DPUSH
    ret

; ============================================================================
; F< F> F= ( r1 r2 -- flag ) -- r1 < r2, r1 > r2, r1 = r2
; ============================================================================
H_FLESS:
    DW   H_FABS
    DB   2, "F", "<"
W_FLESS:
    call FCMPA
    inc  a                             ; Z for -1
    jr   FFLAGZ

H_FGREATER:
    DW   H_FLESS
    DB   2, "F", ">"
W_FGREATER:
    call FCMPA
    dec  a                             ; Z for 1
    jr   FFLAGZ

H_FEQUAL:
    DW   H_FGREATER
    DB   2, "F", "="
W_FEQUAL:
    call FCMPA
    or   a                             ; Z for 0
    jr   FFLAGZ

; ============================================================================
; F0< F0= ( r -- flag ) -- r < 0 (the sign bit of the second byte) / r = 0 (the exponent byte is 0)
; ============================================================================
H_FZEROLESS:
    DW   H_FEQUAL
    DB   3, "F", "0", "<"
W_FZEROLESS:
    ld   a, (iy+1)
    cpl
    and  $80                           ; Z for a set sign bit (a zero cell has none)
    jr   FFLAGZ

H_FZEROEQ:
    DW   H_FZEROLESS
    DB   3, "F", "0", "="
W_FZEROEQ:
    ld   a, (iy+0)
    or   a
    jr   FFLAGZ

; ============================================================================
; FMIN FMAX ( r1 r2 -- r3 ) -- the lesser / the greater; for equal values the cells are the same bytes
; FSEL -- if Z, copy r2 (below IY after FCMPA) over r1, the result; otherwise r1 stays
; ============================================================================
H_FMIN:
    DW   H_FZEROEQ
    DB   4, "F", "M", "I", "N"
W_FMIN:
    call FCMPA
    dec  a                             ; Z for r1 > r2: r2 is the lesser
    jr   FSEL

H_FMAX:
    DW   H_FMIN
    DB   4, "F", "M", "A", "X"
W_FMAX:
    call FCMPA
    inc  a                             ; Z for r1 < r2: r2 is the greater
FSEL:
    ret  nz
    push iy
    pop  de                            ; DE -> r1
    ld   bc, -5
    add  iy, bc                        ; IY -> r2
    jp   FPOP_DE                       ; r2 over r1, IY -> r1 again

; ============================================================================
; F@ ( addr -- r )   F! ( r addr -- ) -- fetch / store the 5 bytes at addr
; ============================================================================
H_FFETCH:
    DW   H_FMAX
    DB   2, "F", "@"
W_FFETCH:
    rst  RST_DPOP
    jp   FPUSH_HL

H_FSTORE:
    DW   H_FFETCH
    DB   2, "F", "!"
W_FSTORE:
    rst  RST_DPOP
    ex   de, hl
    jp   FPOP_DE

; ============================================================================
; FVARIABLE ( "name" -- ) -- like VARIABLE with 5 zero data bytes: name ( -- addr )
; ============================================================================
H_FVARIABLE:
    DW   H_FSTORE
    DB   9, "F", "V", "A", "R", "I", "A", "B", "L", "E"
W_FVARIABLE:
    ld   a, 5
    jp   VARIABLE_N

; ============================================================================
; FCONSTANT ( r "name" -- ) -- name ( -- r ); its code is CALL DOFLIT, the 5 bytes, RET (what a float literal compiles to)
; ============================================================================
H_FCONSTANT:
    DW   H_FVARIABLE
    DB   9, "F", "C", "O", "N", "S", "T", "A", "N", "T"
W_FCONSTANT:
    call DICT_ROOM0
    call VAR_HEADER
    push iy
    pop  hl
    call COMPILE_FLOAT_LITERAL
    call W_FDROP
    jp   VAR_END


    ENDIF
