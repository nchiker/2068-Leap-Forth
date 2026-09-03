; ============================================================================
; rom/forth_smoke_p44.asm — Phase 44 smoke ROM: dictionary-ceiling
; reclaim (FILL's relocated scratch + its new 64-column guard)
;
; Phase 43's FILL correctness itself is NOT re-tested here from
; scratch — rom/forth_smoke_p17.asm (rebuilt against the relocated
; GFX_FILL_VISITED/GFX_FILL_STACK addresses) already proves that, and
; was re-run in real Fuse as part of this phase's own verification
; (see docs/PROJECT_PLAN.md). This file is specifically about what's
; NEW in Phase 44: the 64-column guard core/moregfx.asm's FILL now has.
;
; THREE CHECKPOINTS, GFX_MODE poked directly rather than going through
; the real 64COL/32COL words (core/mode64.asm) — the guard only reads
; that one byte, and pulling in core/mode64.asm's own prerequisite
; chain (core/float.asm) here would test nothing extra:
;   1. Baseline, GFX_MODE=0 (normal mode): FILL a small enclosed square
;      -- the seed pixel and its interior must be SET afterward,
;      proving FILL still works correctly at its new addresses.
;   2. GFX_MODE=2 (64-column mode simulated): FILL a DIFFERENT enclosed
;      square -- its interior must stay CLEAR, proving the guard
;      refused to run (not that FILL happened to fail for some other
;      reason -- checkpoint 1 already proved it works when unguarded).
;   3. GFX_MODE restored to 0: FILL the same square from checkpoint 2
;      again -- it must now fill correctly, proving the guard only
;      blocks while 64-column mode is actually active, not permanently.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_MOREGFX
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (GFX_MODE), a

    call GFX_CLS

; ---- checkpoint 1: baseline FILL, GFX_MODE=0 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_SQUARE1
    ld   de, SRC_SQUARE1_LEN
    call INTERPRET_RUN
    ld   hl, 20
    call DPUSH_HL
    ld   hl, 20
    call DPUSH_HL
    call W_FILL
    ld   b, 20
    ld   c, 20
    call GFX_READ_PIXEL          ; interior of square 1 must now be SET
    or   a
    jp   z, FAIL_TEST

; ---- checkpoint 2: GFX_MODE=2 (64-column simulated) -- FILL refuses ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   a, 2
    ld   (GFX_MODE), a
    ld   hl, SRC_SQUARE2
    ld   de, SRC_SQUARE2_LEN
    call INTERPRET_RUN
    ld   hl, 120
    call DPUSH_HL
    ld   hl, 120
    call DPUSH_HL
    call W_FILL
    ld   b, 120
    ld   c, 120
    call GFX_READ_PIXEL          ; interior of square 2 must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 3: GFX_MODE restored to 0 -- FILL works again ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (GFX_MODE), a
    ld   hl, 120
    call DPUSH_HL
    ld   hl, 120
    call DPUSH_HL
    call W_FILL
    ld   b, 120
    ld   c, 120
    call GFX_READ_PIXEL          ; interior of square 2 must now be SET
    or   a
    jp   z, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all three checkpoints passed
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

; small enclosed squares drawn via LINE, far enough apart not to
; interfere with each other's fill
SRC_SQUARE1: DB "10 10 30 10 LINE 30 10 30 30 LINE 30 30 10 30 LINE 10 30 10 10 LINE "
SRC_SQUARE1_LEN EQU $ - SRC_SQUARE1

SRC_SQUARE2: DB "110 110 130 110 LINE 130 110 130 130 LINE 130 130 110 130 LINE 110 130 110 110 LINE "
SRC_SQUARE2_LEN EQU $ - SRC_SQUARE2

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/moregfx.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p44_rom0.bin", $0000, $4000
