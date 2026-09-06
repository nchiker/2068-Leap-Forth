; ============================================================================
; rom/hires_visual_check.asm — NOT a smoke ROM. Companion to
; rom/mode64_visual_check.asm: same idea (two solid blocks, wide gap
; between them, real per-scanline attribute set on each), but for
; HIRES (GFX_MODE=1, port $FF bits %010) instead of 64COL (%110), to
; separately check that hardware mode's own visual rendering.
;
; Left block: (50,80)-(69,99), ink 2. Right block: (200,80)-(219,99),
; ink 5. Both fully inside the NORMAL 256-pixel-wide bitmap (HIRES
; doesn't widen the screen, only sharpens per-scanline color), so a
; correct rendering should show two distinctly colored solid squares
; with a gap between them, each colored per its own INK, not a single
; flat wash.
;
; RESULT (already run — see docs/PROJECT_PLAN.md's "Future stretch
; goal" section for the full writeup): renders CORRECTLY in ZEsarUX --
; both blocks appear as real, distinctly colored solid squares, unlike
; this file's own rom/mode64_visual_check.asm companion (64COL), which
; renders as one flat rectangle regardless of its own bitmap content.
; See rom/mode64_visual_check.asm's own header for the exact ZEsarUX
; invocation (--romfile format, ZRCP commands) -- identical for this
; file, just point --romfile at THIS binary's own concatenated image.
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

COLD_START:
    ld   sp, $FF00
    ld   a, 1
    call GFX_SET_MODE        ; HIRES

    ld   a, 50
    ld   (BLOCK_X0), a
    ld   a, 2
    ld   (BLOCK_INK), a
    call DRAW_BLOCK

    ld   a, 200
    ld   (BLOCK_X0), a
    ld   a, 5
    ld   (BLOCK_INK), a
    call DRAW_BLOCK

.hang:
    jr   .hang

; ---- DRAW_BLOCK: fills a 20x20 solid block at (BLOCK_X0, 80) with
; ink BLOCK_INK (paper 0) ----
DRAW_BLOCK:
    ld   a, 80
    ld   (CURRENT_Y), a
    ld   b, 20              ; 20 rows
.row_loop:
    push bc
    ld   a, (BLOCK_X0)
    ld   (CURRENT_X), a
    ld   b, 20              ; 20 columns
.col_loop:
    push bc
    ld   a, (CURRENT_X)
    ld   b, a
    ld   a, (CURRENT_Y)
    ld   c, a
    ld   a, (BLOCK_INK)
    ld   d, 0               ; OVER=0
    call GFX_WRITE_PIXEL    ; B=x, C=y, A=attr, D=over -- destroys
                            ; AF,BC,DE,HL
    ld   a, (CURRENT_X)
    inc  a
    ld   (CURRENT_X), a
    pop  bc
    djnz .col_loop
    ld   a, (CURRENT_Y)
    inc  a
    ld   (CURRENT_Y), a
    pop  bc
    djnz .row_loop
    ret

BLOCK_X0  EQU $8800   ; 1 byte
BLOCK_INK EQU $8801   ; 1 byte
CURRENT_X EQU $8802   ; 1 byte
CURRENT_Y EQU $8803   ; 1 byte

    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"

    DS   $4000 - $, $FF

    SAVEBIN "hires_visual_check_rom0.bin", $0000, $4000
