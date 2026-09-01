; ============================================================================
; rom/forth_smoke_p15.asm — Phase 15 smoke ROM: INK and PAPER
;
; Verifies INK/PAPER by reading back the REAL screen attribute byte
; PLOT/LINE actually wrote (via kernel/graphics's own
; GFX_CELL_ATTR_ADDR), not just core/ts2068.asm's own CURRENT_ATTR
; state -- proving the color words have a real, visible effect, the
; same standard rom/forth_smoke_p5.asm's own GFX_READ_PIXEL readback
; already set for PLOT/LINE/CIRCLE themselves.
;
; THREE CHECKPOINTS:
;   1. 5 INK 0 0 PLOT  -> cell (row 0, col 0)'s attribute has ink bits
;      (low 3) == 5, paper bits (bits 3-5) still == 7 (INK alone must
;      not disturb paper)
;   2. 2 PAPER 8 8 PLOT  -> cell (row 1, col 1)'s attribute has paper
;      bits == 2, AND ink bits still == 5 (PRESERVED from checkpoint
;      1 -- proves PAPER is a read-modify-write, not a fresh byte that
;      would silently undo INK)
;   3. 0 INK 7 PAPER 16 16 20 16 LINE  -> resets back to the exact
;      original default (ink 0, paper 7); cell (row 2, col 2)'s
;      attribute must equal DEFAULT_ATTR exactly, proving LINE also
;      honors CURRENT_ATTR (not just PLOT) and that the bit arithmetic
;      round-trips exactly back to the starting byte
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

    ld   hl, DICT_LATEST_INIT_COLOR
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

; ---- checkpoint 1: 5 INK 0 0 PLOT ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 0
    ld   c, 0
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   5
    jp   nz, FAIL_TEST
    ld   b, 0
    ld   c, 0
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $38
    cp   $38
    jp   nz, FAIL_TEST

; ---- checkpoint 2: 2 PAPER 8 8 PLOT ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 1
    ld   c, 1
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   5
    jp   nz, FAIL_TEST
    ld   b, 1
    ld   c, 1
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $38
    cp   $10                     ; paper 2 -> bits 3-5 = 010 = $10
    jp   nz, FAIL_TEST

; ---- checkpoint 3: reset to default, LINE honors it too ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   b, 2
    ld   c, 2
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    cp   DEFAULT_ATTR
    jp   nz, FAIL_TEST

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

CHECKPOINT_NUM EQU $87F8

SRC_CP1: DB "5 INK 0 0 PLOT "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "2 PAPER 8 8 PLOT "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "0 INK 7 PAPER 16 16 20 16 LINE "
SRC_CP3_LEN EQU $ - SRC_CP3

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
    INCLUDE "core/color.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p15_rom0.bin", $0000, $4000
