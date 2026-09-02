; ============================================================================
; rom/forth_smoke_p31.asm — Phase 31 smoke ROM: real BEEP
;
; FOUR CHECKPOINTS, each hand-derived by the same bit-exact Python model
; core/floattrig.asm's own Phase 30 used (reusing that model's already-
; proven F+/F-/F*/F_UDIV32BY16 arithmetic unchanged), verifying
; core/beep.asm's own BEEP_COMPUTE — NOT SOUND_BEEP itself, which
; actually toggles the speaker port and can't be checked in this
; environment (see kernel/sound/sound.asm's own header). This proves
; the MATH (semitone decomposition, octave-doubling, the T-state-
; calibrated pitch_param/cycle_count formulas) is exactly what was hand
; derived, the same "check the inputs to the unverifiable hardware
; call, not the hardware effect itself" strategy
; rom/forth_smoke_p5.asm's own original BEEP checkpoint already used.
;
; Duration values are pushed directly as exact (mantissa,exponent)
; pairs matching the Python model precisely — not typed decimal
; literals — so this smoke ROM's own checkpoints don't depend on
; core/decimal.asm's own independent parser being bit-exact to the
; Python model too (that cross-check is done separately, live, the
; same way Phase 30's own SIN/COS was: typing a real decimal duration
; at rom/forth_boot.asm's own real prompt).
;
;   1. Pitch 0 (middle C), duration 1.0 exactly -> pitch_param=255,
;      cycle_count=261.
;   2. Pitch 12 (one octave above middle C), duration 0.5 exactly ->
;      pitch_param=125, cycle_count=261 -- the SAME cycle_count as
;      checkpoint 1 is not a coincidence: 523.25 Hz * 0.5s =
;      261.625 Hz * 1.0s exactly, since pitch 12 is exactly double
;      pitch 0's own frequency (the octave-doubling identity, verified
;      here as an exact match, not merely "close").
;   3. Pitch -60 (5 octaves below middle C — this file's own
;      BEEP_DECOMPOSE puts -60 at octave=-5, note=0, not the real ROM's
;      own "6 octaves below" internal bookkeeping, a harmless
;      difference in EXPONENT CONVENTION only, not a different musical
;      result), duration 2.0 exactly -> pitch_param=8293,
;      cycle_count=16.
;   4. Pitch 69 (the real ROM's own highest valid note, ~14080 Hz —
;      well past this project's own SOUND_BEEP's real, documented
;      ceiling of ~12876 Hz), duration ~0.1 (float_of(0.1), NOT an
;      exact power of two) -> pitch_param CLAMPED to 1 (the minimum,
;      not the unclamped ~0.5494), cycle_count=1407 -- proving the
;      high-pitch clamp actually engages, not just exists in the code.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
; failing checkpoint's number (1-3, or 5 for checkpoint 4 -- see
; rom/forth_smoke_p27.asm's own header for why checkpoint 4 itself must
; never use color 4, PASS_TEST's own green).
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

    ld   hl, DICT_LATEST_INIT_BEEP
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: pitch 0 (middle C), duration 1.0 exactly ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   (BEEP_DUR_M), hl
    ld   a, -14
    ld   (BEEP_DUR_E), a
    ld   hl, 0
    call BEEP_COMPUTE
    ld   hl, 255
    call CHECK_PITCH_PARAM
    ld   hl, 261
    call CHECK_CYCLE_COUNT

; ---- checkpoint 2: pitch 12 (one octave up), duration 0.5 exactly --
; SAME cycle_count as checkpoint 1, see this file's own header ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   (BEEP_DUR_M), hl
    ld   a, -15
    ld   (BEEP_DUR_E), a
    ld   hl, 12
    call BEEP_COMPUTE
    ld   hl, 125
    call CHECK_PITCH_PARAM
    ld   hl, 261
    call CHECK_CYCLE_COUNT

; ---- checkpoint 3: pitch -60, duration 2.0 exactly ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 16384
    ld   (BEEP_DUR_M), hl
    ld   a, -13
    ld   (BEEP_DUR_E), a
    ld   hl, -60
    call BEEP_COMPUTE
    ld   hl, 8293
    call CHECK_PITCH_PARAM
    ld   hl, 16
    call CHECK_CYCLE_COUNT

; ---- checkpoint 4 (border color 5, not 4 -- see this file's own
; header): pitch 69, duration float_of(0.1) -- proves the pitch_param
; clamp-to-1 actually engages ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, 26214
    ld   (BEEP_DUR_M), hl
    ld   a, -18
    ld   (BEEP_DUR_E), a
    ld   hl, 69
    call BEEP_COMPUTE
    ld   hl, 1
    call CHECK_PITCH_PARAM
    ld   hl, 1407
    call CHECK_CYCLE_COUNT

    jp   PASS_TEST

; ============================================================================
; CHECK_PITCH_PARAM ( HL = expected -- )  compares against BC (the
; pitch_param BEEP_COMPUTE just returned); halts showing the current
; checkpoint's border color on mismatch.
; ============================================================================
CHECK_PITCH_PARAM:
    ld   a, b
    cp   h
    jp   nz, FAIL_TEST
    ld   a, c
    cp   l
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_CYCLE_COUNT ( HL = expected -- )  compares against DE (the
; cycle_count BEEP_COMPUTE just returned).
; ============================================================================
CHECK_CYCLE_COUNT:
    ld   a, d
    cp   h
    jp   nz, FAIL_TEST
    ld   a, e
    cp   l
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
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
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/float.asm"
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floatprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/beep.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p31_rom0.bin", $0000, $4000
