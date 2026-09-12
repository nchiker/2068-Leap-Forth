; ============================================================================
; rom/test_polygon.asm — smoke ROM for POLYGON (EXROM-resident outline)
;
; Mirrors rom/forth_boot.asm's own GRAPHICS_HOME_TABLE placement at
; $0100 exactly, same as rom/test_rect.asm — see that file's own
; header for why.
;
; TWO CHECKPOINTS:
;   1. A right triangle, vertices (100,40) (140,40) (100,80), drawn via
;      "100 40 140 40 100 80 3 POLYGON". Deliberately chosen so every
;      edge has a point GUARANTEED to land exactly on it, not just
;      approximately: the top edge is horizontal (120,40 is on it),
;      the left edge is vertical (100,60 is on it), and the closing
;      (hypotenuse) edge is a perfect 45-degree diagonal from (140,40)
;      to (100,80) (120,60 is its exact midpoint) — so checking all
;      three confirms all three edges actually drew, including the
;      CLOSING edge specifically (the one edge that only exists
;      because POLY_DRAW_IMPL wraps back to vertex 0, not just walks
;      forward). A point well outside the triangle (10,10) must stay
;      CLEAR.
;   2. n=2 (below the 3-vertex minimum) via "10 10 20 20 2 POLYGON" —
;      must draw nothing at all: a point that a 2-point "line" would
;      have covered if n's own validation were skipped (15,15) must
;      stay CLEAR.
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

; ---- checkpoint 1: right triangle, all three edges + closing edge ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 120
    ld   c, 40
    call GFX_READ_PIXEL           ; top edge
    or   a
    jp   z, FAIL_TEST
    ld   b, 100
    ld   c, 60
    call GFX_READ_PIXEL           ; left edge
    or   a
    jp   z, FAIL_TEST
    ld   b, 120
    ld   c, 60
    call GFX_READ_PIXEL           ; closing (hypotenuse) edge
    or   a
    jp   z, FAIL_TEST
    ld   b, 10
    ld   c, 10
    call GFX_READ_PIXEL           ; well outside: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 2: n=2, below the 3-vertex minimum -- must draw nothing ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 15
    ld   c, 15
    call GFX_READ_PIXEL
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
SRC_CP1: DB "100 40 140 40 100 80 3 POLYGON "
SRC_CP1_LEN EQU $ - SRC_CP1

; checkpoint 2: n=2, invalid
SRC_CP2: DB "10 10 20 20 2 POLYGON "
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

    SAVEBIN "test_polygon_rom0.bin", $0000, $4000
