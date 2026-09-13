; ============================================================================
; rom/test_poly_fill.asm — smoke ROM for POLYGON-FILL (EXROM-resident,
; even-odd scanline fill)
;
; Mirrors rom/forth_boot.asm's own GRAPHICS_HOME_TABLE placement at
; $0100 exactly, same as rom/test_polygon.asm — see that file's own
; header for why.
;
; TWO CHECKPOINTS (test points confirmed against an exact-math even-odd
; reference in Python before writing this file — see the scratchpad
; verify_poly_fill.py history):
;   1. The same right triangle test_polygon.asm uses, (100,40) (140,40)
;      (100,80), via "100 40 140 40 100 80 3 POLYGON-FILL". (110,50) is
;      well inside and must be SET; (135,50) [outside, near the
;      hypotenuse], (10,10) [far outside], and (105,75) [outside, just
;      past the hypotenuse near the bottom] must all stay CLEAR.
;   2. A concave chevron, (50,50) (90,70) (50,90) (65,70), via "50 50 90
;      70 50 90 65 70 4 POLYGON-FILL" — the shape most likely to expose
;      an even-odd bug, since a naive "between min-x and max-x" fill
;      would wrongly fill the notch. (70,70) and (80,70) [inside the
;      solid right-hand mass] and (52,52) [inside the thin upper arm,
;      near the tip] must be SET; (55,60) and (55,80) [inside the
;      notch, symmetric above/below the middle] must stay CLEAR.
;
; Border goes GREEN (4) if both checkpoints pass; otherwise it shows
; the failing checkpoint's number.
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

; ---- same fixed-address table rom/forth_boot.asm has -- see this
; file's own header ----
GRAPHICS_HOME_TABLE:
    jp   GFX_WRITE_PIXEL
    jp   GFX_SET_ATTR
    jp   GFX_LINE

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_POLYGON
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

; ---- checkpoint 1: right triangle, even-odd interior vs exterior ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 110
    ld   c, 50
    call GFX_READ_PIXEL           ; well inside: must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 135
    ld   c, 50
    call GFX_READ_PIXEL           ; outside, near hypotenuse: CLEAR
    or   a
    jp   nz, FAIL_TEST
    ld   b, 10
    ld   c, 10
    call GFX_READ_PIXEL           ; far outside: CLEAR
    or   a
    jp   nz, FAIL_TEST
    ld   b, 105
    ld   c, 75
    call GFX_READ_PIXEL           ; outside, past hypotenuse near bottom: CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 2: concave chevron, notch must stay unfilled ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 70
    ld   c, 70
    call GFX_READ_PIXEL           ; solid mass: must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 80
    ld   c, 70
    call GFX_READ_PIXEL           ; solid mass: must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 52
    ld   c, 52
    call GFX_READ_PIXEL           ; thin upper arm near the tip: must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 55
    ld   c, 60
    call GFX_READ_PIXEL           ; inside the notch: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST
    ld   b, 55
    ld   c, 80
    call GFX_READ_PIXEL           ; inside the notch: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

    jp   PASS_TEST

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

; checkpoint 1: right triangle (100,40) (140,40) (100,80)
SRC_CP1: DB "100 40 140 40 100 80 3 POLYGON-FILL "
SRC_CP1_LEN EQU $ - SRC_CP1

; checkpoint 2: concave chevron (50,50) (90,70) (50,90) (65,70)
SRC_CP2: DB "50 50 90 70 50 90 65 70 4 POLYGON-FILL "
SRC_CP2_LEN EQU $ - SRC_CP2

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
    INCLUDE "core/polygon.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_poly_fill_rom0.bin", $0000, $4000
