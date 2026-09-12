; ============================================================================
; rom/test_sprite.asm — smoke ROM for SPRITE-DEFINE/SHOW/HIDE
;
; Mirrors rom/forth_boot.asm's own GRAPHICS_HOME_TABLE placement at
; $0100 exactly — see rom/test_rect.asm's own header for why.
;
; FOUR CHECKPOINTS:
;   1. Draw a 16x16 solid box (RECT) at (40,40)-(55,55) with INK 2,
;      SPRITE-DEFINE slot 0 from there, CLS (erasing it), then
;      SPRITE-SHOW slot 0 at row 10 col 10 (pixel 80,80) — the
;      captured shape must now appear THERE: pixel (85,85) [well
;      inside] must be SET with ink bits == 2, and a point outside the
;      16x16 box at that new position (100,100) must stay CLEAR.
;   2. SPRITE-HIDE slot 0 — pixel (85,85) must go back to CLEAR
;      (whatever CLS left it as), proving the background was actually
;      restored, not just left alone.
;   3. SPRITE-SHOW slot 0 again at the SAME position (row 10 col 10),
;      then SPRITE-SHOW slot 0 AGAIN without hiding first, then HIDE.
;      A single pixel check right after the second SHOW can't tell
;      "correctly refused" from "incorrectly ran again" apart — both
;      leave the pixel SET either way. The HIDE afterward can: if the
;      guard let the second SHOW run, it would have captured the
;      SPRITE'S OWN already-drawn pixels as the "background" (since
;      the sprite was already showing there), so HIDE would incorrectly
;      restore that instead of the true original blank background,
;      leaving the pixel SET when it should go CLEAR. So this
;      checkpoint asserts CLEAR after the HIDE.
;   4. Slot 0 SHOWN once more (checkpoint 3 ended with it hidden), then
;      SPRITE-HIDE on slot 1 (never DEFINEd or SHOWN at all) — must
;      refuse silently and leave slot 0's own sprite completely
;      unaffected, checked by confirming pixel (85,85) is still SET
;      afterward.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_SPRITE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

; ---- checkpoint 1: capture, clear, show elsewhere ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 85
    ld   c, 85
    call GFX_READ_PIXEL           ; must be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 10
    ld   c, 10
    call GFX_CELL_ATTR_ADDR       ; row 10 col 10 -> attribute address
    ld   a, (hl)
    and  $07
    cp   2                         ; ink must be 2
    jp   nz, FAIL_TEST
    ld   b, 100
    ld   c, 100
    call GFX_READ_PIXEL           ; well outside the sprite: CLEAR
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 2: hide restores the background ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 85
    ld   c, 85
    call GFX_READ_PIXEL           ; must be CLEAR again
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 3: show, show-again (must refuse), hide -- see this
; file's own header on why the HIDE is what actually proves the
; second SHOW was refused, not the SHOW itself ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   b, 85
    ld   c, 85
    call GFX_READ_PIXEL           ; must be CLEAR -- see header
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 4: hide on a never-defined slot refuses silently ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   b, 85
    ld   c, 85
    call GFX_READ_PIXEL           ; slot 0's own sprite must be
    or   a                        ; completely unaffected
    jp   z, FAIL_TEST

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

; checkpoint 1: solid 16x16 box (INK 2), captured into slot 0, screen
; cleared, then shown at row 10 col 10 (pixel 80,80)
SRC_CP1: DB "2 INK 40 40 55 55 RECT 0 5 5 SPRITE-DEFINE "
         DB "0 INK CLS 0 10 10 SPRITE-SHOW "
SRC_CP1_LEN EQU $ - SRC_CP1

; checkpoint 2: hide slot 0
SRC_CP2: DB "0 SPRITE-HIDE "
SRC_CP2_LEN EQU $ - SRC_CP2

; checkpoint 3: show slot 0 again at the same spot, try again (must
; refuse), then hide -- see this file's own header on why the pixel
; must be CLEAR afterward, not SET
SRC_CP3: DB "0 10 10 SPRITE-SHOW 0 10 10 SPRITE-SHOW 0 SPRITE-HIDE "
SRC_CP3_LEN EQU $ - SRC_CP3

; checkpoint 4: show slot 0 once more, then hide slot 1 -- never
; defined or shown at all -- must refuse and leave slot 0 untouched
SRC_CP4: DB "0 10 10 SPRITE-SHOW 1 SPRITE-HIDE "
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
    INCLUDE "core/polygon.asm"
DICT_CHAIN_POINT DEFL H_POLYGON
    INCLUDE "core/sprite.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_sprite_rom0.bin", $0000, $4000
