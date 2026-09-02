; ============================================================================
; rom/forth_smoke_p34.asm — Phase 34 smoke ROM: S>F and F>S
;
; FIVE CHECKPOINTS, the same hand-verified cases core/floatconv.asm's
; own header derives by hand:
;   1. S>F(42) lands on the float stack as exactly (42, 0) -- checked
;      directly before converting back -- then F>S round-trips it to
;      exactly 42 on the integer stack.
;   2. S>F(-17) then F>S round-trips to exactly -17 -- negative
;      integers need no special-casing anywhere in either word.
;   3. F>S(0.5) = F>S(16384,-15) = 0 -- ordinary truncation-toward-zero
;      for a positive fractional value.
;   4. F>S(-0.5) = F>S(-16384,-15) = -1, NOT 0 -- the documented
;      caveat made concrete: F>S truncates via an arithmetic (sign-
;      preserving) right shift, which floors a negative fractional
;      value (rounds toward negative infinity) rather than truncating
;      toward zero.
;   5. F>S(-4.0) = F>S(-16384,-12) = -4 -- a WHOLE negative number is
;      unaffected by the checkpoint-4 caveat, since there's no
;      fractional remainder for the two truncation directions to
;      disagree about.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
; failing checkpoint's number.
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

    ld   hl, DICT_LATEST_INIT_FLOATCONV
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: S>F(42) = (42,0) exactly, then F>S round-trips to 42 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 42
    call DPUSH_HL
    call W_STOF
    ld   hl, 42
    xor  a
    call CHECK_FTOP
    call W_FTOS
    ld   de, 42
    call CHECK_ITOP

; ---- checkpoint 2: S>F(-17) then F>S round-trips to -17 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, -17
    call DPUSH_HL
    call W_STOF
    call W_FTOS
    ld   de, -17
    call CHECK_ITOP

; ---- checkpoint 3: F>S(0.5) = 0 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   a, -15
    call FPUSH
    call W_FTOS
    ld   de, 0
    call CHECK_ITOP

; ---- checkpoint 4: F>S(-0.5) = -1, not 0 -- the documented caveat ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, -16384
    ld   a, -15
    call FPUSH
    call W_FTOS
    ld   de, -1
    call CHECK_ITOP

; ---- checkpoint 5: F>S(-4.0) = -4 -- a whole number, unaffected ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, -16384
    ld   a, -12
    call FPUSH
    call W_FTOS
    ld   de, -4
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_FTOP ( HL = expected mantissa, A = expected exponent -- )
; Checks the float on top of the float stack WITHOUT popping it.
; Identical to rom/forth_smoke_p18.asm's own CHECK_FTOP.
; ============================================================================
CHECK_FTOP:
    push af
    ld   a, (iy+0)
    cp   l
    jp   nz, FAIL_TEST
    ld   a, (iy+1)
    cp   h
    jp   nz, FAIL_TEST
    pop  af
    ld   l, a
    ld   a, (iy+2)
    cp   l
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch.
; ============================================================================
CHECK_ITOP:
    call DPOP_HL
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    cp   d
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
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
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatconv.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p34_rom0.bin", $0000, $4000
