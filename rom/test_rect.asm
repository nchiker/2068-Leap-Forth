; ============================================================================
; rom/test_rect.asm — smoke ROM for RECT (EXROM-resident rectangle fill)
;
; Mirrors rom/forth_boot.asm's own GRAPHICS_HOME_TABLE placement at
; $0100 exactly — rom/graphics_exrom.asm's service table calls through
; those fixed addresses, so ANY Home ROM exercising it (this one
; included) must place the same veneers at the same fixed spot.
;
; THREE CHECKPOINTS:
;   1. RECT 20,20 to 60,60 (already-sorted corners) — interior pixel
;      (40,40) must be SET afterward, and a point well outside the box
;      (5,5) must stay CLEAR.
;   2. RECT 150,120 to 110,90 (corners given BACKWARDS — x1<x0 AND
;      y1<y0) — same box as checkpoint 1's shape, different position,
;      deliberately unsorted to prove RECT_FILL_IMPL's own corner-
;      normalization actually runs. Interior pixel (130,105) must be
;      SET, and the box's own far corner (111,91, one pixel inside
;      each edge) must ALSO be set, proving the whole box filled, not
;      just the seed corner.
; The magic/ABI mismatch path (EXROM_CALL_RECT_FILL must refuse to
; draw when the paged image doesn't check out) is deliberately NOT a
; checkpoint here — EXROM is real ROM, so nothing running from it can
; corrupt its own header at runtime to simulate a mismatch. That path
; is instead verified by running this exact same Home image against a
; deliberately-wrong EXROM binary as a separate run (see the project's
; own build notes for this test) — the pixel at RECT's own seed
; position must stay CLEAR when run that way.
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
    jp   GFX_ROW_BASE_ADDR
    jp   GFX_CELL_ATTR_ADDR

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_RECTFILL
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

; ---- checkpoint 1: sorted corners ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 40
    ld   c, 40
    call GFX_READ_PIXEL           ; interior must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 5
    ld   c, 5
    call GFX_READ_PIXEL           ; well outside: must stay CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 2: corners given backwards ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 130
    ld   c, 105
    call GFX_READ_PIXEL           ; interior must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 111
    ld   c, 91
    call GFX_READ_PIXEL           ; far corner (one px inside each
    or   a                        ; edge): must ALSO be SET -- proves
    jp   z, FAIL_TEST             ; the whole box filled

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

; checkpoint 1: sorted corners (20,20)-(60,60)
SRC_CP1: DB "20 20 60 60 RECT "
SRC_CP1_LEN EQU $ - SRC_CP1

; checkpoint 2: backwards corners -- (150,120) to (110,90), same
; 40x30 shape as checkpoint 1, different spot, deliberately unsorted
SRC_CP2: DB "150 120 110 90 RECT "
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

    DS   $4000 - $, $FF

    SAVEBIN "test_rect_rom0.bin", $0000, $4000
