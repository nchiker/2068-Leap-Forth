; ============================================================================
; rom/forth_smoke_p17.asm — Phase 17 smoke ROM: FILL and AT-XY
;
; THREE CHECKPOINTS:
;   1. FILL: draw a CIRCLE outline, set INK, FILL its interior --
;      verify (a) a pixel inside the circle is now SET (it wasn't
;      before -- an outline alone doesn't fill its own interior),
;      (b) the covering cell's attribute has the new ink color (proving
;      FILL picked up CURRENT_ATTR, like PLOT/LINE/CIRCLE since
;      Phase 15), (c) a pixel far outside the circle stays CLEAR
;      (proving the fill stayed bounded, not spilling everywhere)
;   2. AT-XY + EMIT: 10 5 AT-XY then EMIT -- verify PRINT_ROW/PRINT_COL
;      land exactly there AND a real pixel was drawn in that exact
;      screen cell (not just internal state)
;   3. AT-XY near the column-31 wrap boundary, then two EMITs -- proves
;      AT-XY doesn't disturb core/print.asm's own existing wrap logic
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
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: FILL ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 50
    ld   c, 50
    call GFX_READ_PIXEL          ; center of the circle must now be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 6                     ; cell covering (50,50): row 50/8=6
    ld   c, 6                     ; col 50/8=6
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   4                        ; ink 4, set right before FILL
    jp   nz, FAIL_TEST
    ld   b, 0
    ld   c, 0
    call GFX_READ_PIXEL          ; far outside the circle: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 2: AT-XY + EMIT ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   5
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   11
    jp   nz, FAIL_TEST
    call CHECK_CELL_HAS_PIXEL_R5C10

; ---- checkpoint 3: AT-XY near the wrap boundary ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    cp   11
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   1
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
; GFX_READ_PIXEL's real contract is B=x (pixel column), C=y (pixel
; row) -- a different convention from GFX_CELL_ATTR_ADDR's B=row/C=col
; used above in checkpoint 1; conflating the two was a real bug caught
; here before trusting this checkpoint.
CHECK_CELL_HAS_PIXEL_R5C10:        ; checks row 5, col 10 (pixel x
                                    ; 80-87, pixel y 40-47) for at
                                    ; least one set pixel
    ld   c, 40
.rowloop:
    push bc
    ld   b, 80
.colloop:
    push bc
    call GFX_READ_PIXEL
    pop  bc
    or   a
    jr   nz, .found
    inc  b
    ld   a, b
    cp   88
    jr   c, .colloop
    pop  bc
    inc  c
    ld   a, c
    cp   48
    jr   c, .rowloop
    jp   FAIL_TEST
.found:
    pop  bc
    ret

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

CHECKPOINT_NUM EQU $8808

SRC_CP1: DB "50 50 20 CIRCLE 4 INK 50 50 FILL "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "10 5 AT-XY 65 EMIT "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "31 10 AT-XY 65 EMIT 66 EMIT "
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
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/moregfx.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p17_rom0.bin", $0000, $4000
