; ============================================================================
; rom/forth_smoke_p60.asm — Phase 60 smoke ROM: BRIGHT
;
; Same verification strategy as rom/forth_smoke_p15.asm (INK/PAPER):
; reads back the REAL screen attribute byte PLOT/LINE actually wrote
; (via kernel/graphics's own GFX_CELL_ATTR_ADDR), not just
; core/ts2068.asm's own CURRENT_ATTR state.
;
; THREE CHECKPOINTS:
;   1. 5 INK 1 BRIGHT 0 0 PLOT  -> cell (row 0, col 0)'s attribute has
;      ink bits (low 3) == 5, bright bit (bit 6) set, AND paper bits
;      (bits 3-5) still == 7 (BRIGHT alone must not disturb paper, and
;      setting it alongside INK must not disturb ink either)
;   2. 0 BRIGHT 8 8 PLOT  -> cell (row 1, col 1)'s attribute has bright
;      bit clear, AND ink bits still == 5, AND paper bits still == 7
;      (PRESERVED from checkpoint 1 -- proves BRIGHT is a read-modify-
;      write against bit 6 only, not a fresh byte that would silently
;      undo INK/PAPER, mirroring PAPER's own proof in Phase 15)
;   3. 0 INK 7 PAPER 0 BRIGHT 16 16 20 16 LINE  -> resets back to the
;      exact original default (ink 0, paper 7, bright 0); cell
;      (row 2, col 2)'s attribute must equal DEFAULT_ATTR exactly,
;      proving LINE also honors CURRENT_ATTR's bright bit (not just
;      PLOT) and that the bit arithmetic round-trips exactly back to
;      the starting byte
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

    ld   hl, DICT_LATEST_INIT_COLOR
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

; ---- checkpoint 1: 5 INK 1 BRIGHT 0 0 PLOT ----
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
    and  $40
    cp   $40
    jp   nz, FAIL_TEST
    ld   b, 0
    ld   c, 0
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $38
    cp   $38
    jp   nz, FAIL_TEST

; ---- checkpoint 2: 0 BRIGHT 8 8 PLOT ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 1
    ld   c, 1
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $40
    jp   nz, FAIL_TEST
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
    cp   $38
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

SRC_CP1: DB "5 INK 1 BRIGHT 0 0 PLOT "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "0 BRIGHT 8 8 PLOT "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "0 INK 7 PAPER 0 BRIGHT 16 16 20 16 LINE "
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

    SAVEBIN "forth_smoke_p60_rom0.bin", $0000, $4000
