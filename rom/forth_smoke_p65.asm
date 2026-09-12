; ============================================================================
; rom/forth_smoke_p65.asm — smoke ROM for the scanline/span FILL rewrite
;
; kernel/graphics/graphics.asm's GFX_FILL was rewritten from a per-PIXEL
; 4-connected flood fill (one stack entry per pixel, 1664 entries/3328
; bytes) to a per-SPAN (scanline) one (one stack entry per contiguous
; row-run, 512 entries/1024 bytes) — see include/sysvars.inc's own
; GFX_FILL_STACK header for the RAM accounting and the Python
; verification (against a reference breadth-first flood fill, across
; 12 shapes including this exact recolor case) the algorithm itself
; already went through before any Z80 was written. This ROM exists to
; close the ONE gap that Python verification can't: whether the actual
; hand-written Z80 — real register clobbers, real branch conditions —
; runs correctly on a real machine/emulator, not just in the abstract.
;
; FOUR CHECKPOINTS:
;   1. Baseline: FILL a small enclosed blank square — proves ordinary
;      fill-and-stop-at-the-boundary still works, and that fill did
;      NOT leak past its own boundary (a point well outside stays
;      pixel-clear) — the exact class of bug an earlier Python draft
;      of this same algorithm caught and this ROM re-confirms in Z80.
;   2. A second square, filled solid with INK 2 — sets up checkpoint 3.
;   3. RECOLOR: the same already-solid square, FILLed again with
;      INK 6 (no LINE redraw in between). This is the historically
;      tricky path (GFX_FILL_TARGET == 1 means a freshly-filled pixel
;      reads back as target-matching again — GFX_FILL_VISITED exists
;      specifically for this) — checks the new ink actually reached
;      BOTH the seed's own cell AND a far corner, proving the whole
;      region was recolored, not just partially.
;   4. CONCAVE: an L-shaped enclosed region (a single straight-line
;      boundary, six segments, one genuine concave corner) — seeded
;      from the wide top bar, checks the fill correctly turned the
;      concave corner into the narrower bottom-left bar (a real test
;      of the row-above/below scan finding a narrower span than the
;      one it came from), and that a point in the notched-out area
;      just outside the L stayed unfilled.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
; failing checkpoint's number. White (7) means a bug in this file's
; own test source (an unrecognized word), not a real checkpoint.
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

; ---- checkpoint 1: baseline fill + leak containment ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   b, 30
    ld   c, 30
    call GFX_READ_PIXEL          ; interior must now be SET
    or   a
    jp   z, FAIL_TEST
    ld   b, 5
    ld   c, 5
    call GFX_READ_PIXEL          ; well outside the square: must stay
    or   a                       ; CLEAR -- no leak past the boundary
    jp   nz, FAIL_TEST
    ld   b, 60
    ld   c, 60
    call GFX_READ_PIXEL          ; just past the square on the far
    or   a                       ; side: same leak-containment check
    jp   nz, FAIL_TEST

; ---- checkpoint 2: a second square, filled solid with INK 2 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 11                   ; row 11 = pixel y 88-95 (seed y=90)
    ld   c, 11                   ; col 11 = pixel x 88-95 (seed x=90)
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   2
    jp   nz, FAIL_TEST
    ld   b, 8                    ; row 8 = pixel y 64-71 (corner 71,71)
    ld   c, 8
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   2
    jp   nz, FAIL_TEST
    ld   b, 13                   ; row 13 = pixel y 104-111 (corner 109,109)
    ld   c, 13
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   2
    jp   nz, FAIL_TEST

; ---- checkpoint 3: RECOLOR the same already-solid square with INK 6 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   b, 11
    ld   c, 11
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   6
    jp   nz, FAIL_TEST
    ld   b, 8
    ld   c, 8
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   6
    jp   nz, FAIL_TEST
    ld   b, 13
    ld   c, 13
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   6
    jp   nz, FAIL_TEST

; ---- checkpoint 4: concave L-shaped region ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   b, 180                  ; the seed itself: must be SET
    ld   c, 155
    call GFX_READ_PIXEL
    or   a
    jp   z, FAIL_TEST
    ld   b, 155                  ; far corner of the narrower
    ld   c, 185                  ; bottom-left bar, reachable only by
    call GFX_READ_PIXEL          ; turning the concave corner: must
    or   a                       ; also be SET
    jp   z, FAIL_TEST
    ld   b, 180                  ; inside the notched-out area (NOT
    ld   c, 185                  ; part of the L): must stay CLEAR --
    call GFX_READ_PIXEL          ; proves the fill respected the
    or   a                       ; concave boundary rather than leaking
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

; checkpoint 1: enclosed square (10,10)-(50,50), seed (30,30)
SRC_CP1: DB "10 10 50 10 LINE 50 10 50 50 LINE 50 50 10 50 LINE 10 50 10 10 LINE 30 30 FILL "
SRC_CP1_LEN EQU $ - SRC_CP1

; checkpoint 2: enclosed square (70,70)-(110,110), INK 2, seed (90,90)
SRC_CP2: DB "2 INK 70 70 110 70 LINE 110 70 110 110 LINE 110 110 70 110 LINE 70 110 70 70 LINE 90 90 FILL "
SRC_CP2_LEN EQU $ - SRC_CP2

; checkpoint 3: same square, no redraw -- just INK 6, FILL again from
; the same seed (now a solid region: the historically tricky recolor
; path)
SRC_CP3: DB "6 INK 90 90 FILL "
SRC_CP3_LEN EQU $ - SRC_CP3

; checkpoint 4: L-shaped boundary -- a 40x20 top bar (150-190,150-170)
; with a 20x20 bottom-left bar (150-170,170-190) attached, one real
; concave corner at (170,170). Seeded from the top bar (180,155).
SRC_CP4: DB "150 150 190 150 LINE 190 150 190 190 LINE 190 190 170 190 LINE 170 190 170 170 LINE "
         DB "170 170 150 170 LINE 150 170 150 150 LINE 180 155 FILL "
SRC_CP4_LEN EQU $ - SRC_CP4

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
DICT_CHAIN_POINT DEFL H_FLASH
    INCLUDE "core/moregfx.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p65_rom0.bin", $0000, $4000
