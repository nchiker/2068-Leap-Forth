; ============================================================================
; rom/test_shapes.asm — test ROM for CIRCLE (EXROM-resident, step O15 item 4)
;
; Mirrors rom/forth_boot.asm's own GRAPHICS_HOME_TABLE placement at $0100
; exactly (see rom/test_rect.asm's header): rom/graphics_exrom.asm calls
; through those fixed addresses (CIRCLE uses slot 0, GFX_WRITE_PIXEL, in
; HIRES only). Run with build/graphics_exrom.bin as ROM 1.
;
; FOUR CHECKPOINTS, numbered 1, 2, 3 and 5 because border 4 means PASS (the
; CIRCLE checks that used to live in rom/forth_smoke_p5.asm and rom/
; forth_smoke_p17.asm, plus new ones):
;   1. `150 100 20 CIRCLE` -- the four poles (150,80) (150,120) (130,100)
;      (170,100) are SET (was p5 checkpoint 3).
;   2. `50 50 20 CIRCLE 4 INK 50 50 FILL` -- the centre (50,50) is SET (an
;      outline alone does not fill its interior), the cell over it has
;      ink 4 (FILL picked up CURRENT_ATTR), (0,0) is CLEAR (the fill stayed
;      inside). Was p17 checkpoint 1. FILL is still the Home word in this
;      item, hence the include of core/moregfx.asm.
;   3. `-10 50 30 CIRCLE` -- a circle cut by the left edge: (20,50) SET,
;      (246,50) CLEAR (no wrap-around to the other edge).
;   5. After CLS, `100 150 0 CIRCLE` draws the centre point only and
;      `100 170 -3 CIRCLE` draws nothing: (100,150) SET, (100,170) CLEAR,
;      (97,170) CLEAR, and exactly one bitmap byte of the whole screen is
;      non-zero (found by the oracle: r = 0 once ran on past the centre).
; The mismatch path (no EXROM) is not a checkpoint, as in rom/test_rect.asm.
;
; Border goes GREEN (4) if all pass; otherwise it shows the failing
; checkpoint's number (1, 2, 3 or 5).
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

; ---- same fixed-address table rom/forth_boot.asm has -- see
; rom/test_rect.asm's header ----
GRAPHICS_HOME_TABLE:
    jp   GFX_WRITE_PIXEL
    jp   GFX_SET_ATTR
    jp   GFX_LINE
    jp   GFX_ROW_BASE_ADDR
    jp   GFX_CELL_ATTR_ADDR

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
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: the poles of a circle ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 150
    ld   c, 80
    call GFX_READ_PIXEL           ; top
    or   a
    jp   z, FAIL_TEST
    ld   b, 150
    ld   c, 120
    call GFX_READ_PIXEL           ; bottom
    or   a
    jp   z, FAIL_TEST
    ld   b, 130
    ld   c, 100
    call GFX_READ_PIXEL           ; left
    or   a
    jp   z, FAIL_TEST
    ld   b, 170
    ld   c, 100
    call GFX_READ_PIXEL           ; right
    or   a
    jp   z, FAIL_TEST

; ---- checkpoint 2: CIRCLE, then FILL of its interior ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 50
    ld   c, 50
    call GFX_READ_PIXEL           ; centre of the circle must now be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 6                     ; cell covering (50,50): row 50/8=6
    ld   c, 6                     ; col 50/8=6
    call GFX_CELL_ATTR_ADDR       ; (B=row, C=col here, unlike GFX_READ_PIXEL)
    ld   a, (hl)
    and  $07
    cp   4                        ; ink 4, set right before FILL
    jp   nz, FAIL_TEST
    ld   b, 0
    ld   c, 0
    call GFX_READ_PIXEL           ; far outside the circle: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 3: a circle cut by the left edge ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   b, 20
    ld   c, 50
    call GFX_READ_PIXEL           ; the rightmost point (-10+30, 50): SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 246
    ld   c, 50
    call GFX_READ_PIXEL           ; (-10 wrapped by 8 bits would land here)
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 5: r = 0 is the centre point, r < 0 draws nothing ----
    ld   a, 5                     ; (not 4: border 4 means PASS)
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   b, 100
    ld   c, 150
    call GFX_READ_PIXEL           ; r = 0: the centre
    or   a
    jp   z, FAIL_TEST
    ld   b, 100
    ld   c, 170
    call GFX_READ_PIXEL           ; r = -3: not even the centre
    or   a
    jp   nz, FAIL_TEST
    ld   b, 97
    ld   c, 170
    call GFX_READ_PIXEL           ; r = -3 read as 253 would reach here
    or   a
    jp   nz, FAIL_TEST
    ld   hl, $4000                ; and nothing else anywhere: exactly one
    ld   bc, $1800                ; bitmap byte is non-zero (a loop that
    ld   d, 0                     ; ran on past r = 0 draws far arcs)
.count:
    ld   a, (hl)
    or   a
    jr   z, .zero
    inc  d
.zero:
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, .count
    ld   a, d
    cp   1
    jp   nz, FAIL_TEST

    jp   PASS_TEST

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

SRC_CP1: DB "150 100 20 CIRCLE "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "50 50 20 CIRCLE 4 INK 50 50 FILL "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "-10 50 30 CIRCLE "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "CLS 100 150 0 CIRCLE 100 170 -3 CIRCLE "
SRC_CP4_LEN EQU $ - SRC_CP4

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/bank/bank.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_FLASH
    INCLUDE "core/rectfill.asm"
DICT_CHAIN_POINT DEFL H_RECT
    INCLUDE "core/shapes.asm"
DICT_CHAIN_POINT DEFL H_CIRCLE
    INCLUDE "core/moregfx.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_shapes_rom0.bin", $0000, $4000
