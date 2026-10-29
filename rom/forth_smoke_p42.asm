; ============================================================================
; rom/forth_smoke_p42.asm — Phase 42 smoke ROM: RAD, DEG
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md section 8.3); the expected cells are tools/fpforth.py's
; frad and fdeg (each row's comment is the expression; HALF_PI is
; fpforth's pi/2 constant, enc = fpmodel.encode).
;
; TWO CHECKPOINTS:
;   1. RAD(90.0) = 90.0 * pi/180: the cell nearest pi/2 (1.5707963...).
;   2. DEG(HALF_PI) = HALF_PI * 180/pi = 90.0 exactly -- a real round
;      trip (radians back to degrees), not just one direction checked
;      in isolation.
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    INCLUDE "include/rst_vectors.inc"
RST_38:
    ei
    ret
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_RADDEG
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: RAD(90.0) = 90.0 * pi/180 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, C1_A
    call FPUSH_HL
    call W_RAD
    ld   hl, C1_X
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: DEG(HALF_PI) = 90.0 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, C2_A
    call FPUSH_HL
    call W_DEG
    ld   hl, C2_X
    call CHECK_FTOP
    call FDROP_T

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FTOP:                      ; HL -> 5 expected bytes; float stack NOT popped
    push iy
    pop  de
    ld   b, 5
.cmp:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  de
    inc  hl
    djnz .cmp
    ret

FDROP_T:                         ; drop the top float cell
    ld   bc, 5
    add  iy, bc
    ret

; ---- 5-byte cells [exponent][sign | m0][m1][m2][m3]; each comment is the fpforth expression (enc = fpmodel.encode)
C1_A:   DB   $87, $34, $00, $00, $00     ; enc(90.0)
C1_X:   DB   $81, $49, $0F, $DA, $A3     ; fpforth: frad(enc(90.0))
C2_A:   DB   $81, $49, $0F, $DA, $A2     ; HALF_PI
C2_X:   DB   $87, $34, $00, $00, $00     ; fpforth: fdeg(HALF_PI)

PASS_TEST:
    ld   a, 4                    ; green: both checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpconv.asm"    ; (fpmath.asm's FINT)
DICT_CHAIN_POINT DEFL H_FROUND
    INCLUDE "core/fpmath.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p42_rom0.bin", $0000, $4000
