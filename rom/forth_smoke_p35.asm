; ============================================================================
; rom/forth_smoke_p35.asm — Phase 35 smoke ROM: FROUND
;
; SIX CHECKPOINTS, the same hand-verified (Python-simulated first)
; cases core/floatconv.asm's own header derives:
;   1. FROUND(sqrt(2)~1.41421 = (23170,-14)) then F>S = 1 -- the
;      fraction (.41) is below .5, floors as before; FROUND and plain
;      F>S agree here.
;   2. FROUND(0.5 = (16384,-15)) then F>S = 1 -- a positive tie rounds
;      away from zero under round-half-up.
;   3. FROUND(-0.5 = (-16384,-15)) then F>S = 0, NOT -1 -- the
;      round-half-up rule made concrete: a negative tie rounds TOWARD
;      zero (both "up," i.e. toward positive infinity) -- genuinely
;      different from plain F>S's own -1 on this exact input (see
;      rom/forth_smoke_p34.asm's own checkpoint 4).
;   4. FROUND(2.5 = (20480,-13)) then F>S = 3 -- same rule at a larger
;      magnitude.
;   5. FROUND(-2.5 = (-20480,-13)) then F>S = -2, not -3.
;   6. FROUND(-4.0 = (-16384,-12)) then F>S = -4 -- a whole number
;      passes through unchanged, exponent >= 0 branch confirmed too by
;      round-tripping a value whose OWN exponent is already 0 after
;      checkpoint 1-5's own FROUND calls each leave it there.
;
; Border goes GREEN (4) if all six pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_FROUND
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: FROUND(sqrt(2)) then F>S = 1 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 23170
    ld   a, -14
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, 1
    call CHECK_ITOP

; ---- checkpoint 2: FROUND(0.5) then F>S = 1 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   a, -15
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, 1
    call CHECK_ITOP

; ---- checkpoint 3: FROUND(-0.5) then F>S = 0, NOT -1 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, -16384
    ld   a, -15
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, 0
    call CHECK_ITOP

; ---- checkpoint 4: FROUND(2.5) then F>S = 3 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, 20480
    ld   a, -13
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, 3
    call CHECK_ITOP

; ---- checkpoint 5: FROUND(-2.5) then F>S = -2, not -3 ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, -20480
    ld   a, -13
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, -2
    call CHECK_ITOP

; ---- checkpoint 6: FROUND(-4.0) then F>S = -4 -- whole number ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, -16384
    ld   a, -12
    call FPUSH
    call W_FROUND
    call W_FTOS
    ld   de, -4
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p34.asm's own CHECK_ITOP.
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
    ld   a, 4                    ; green: all six checkpoints passed
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

    SAVEBIN "forth_smoke_p35_rom0.bin", $0000, $4000
