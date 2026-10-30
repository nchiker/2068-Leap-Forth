; ============================================================================
; core/shapes.asm -- FILL and CIRCLE, backed by the graphics EXROM (step O15)
;
; Builds on core/dict.asm, core/interp.asm, core/ts2068.asm (needs
; CURRENT_ATTR) and core/rectfill.asm (needs EXROM_CALL_SLOT); all must be
; INCLUDEd first. Chains through DICT_CHAIN_POINT like every core file.
;
;   FILL ( x y -- )   flood-fills the region 4-connected to (x, y) through
;           pixels of the seed pixel's value, with the current colour. x and
;           y are signed cells; a seed outside 0-255 / 0-191 does nothing, and
;           so does FILL in HIRES. The work is FILL_IMPL, slot 7 of rom/
;           graphics_exrom.asm (docs/V2/FILL_CIRCLE_SPEC.md section 4).
;   CIRCLE ( xc yc r -- )   the outline of the circle of radius r about
;           (xc, yc) in the current colour. Centre and radius are signed
;           16-bit cells: a circle partly or wholly off the screen is
;           clipped point by point; r < 0 draws nothing; r = 0 draws the
;           centre point. The work is CIRCLE_IMPL, slot 8 of rom/
;           graphics_exrom.asm (docs/V2/FILL_CIRCLE_SPEC.md sections 5-6).
;
; The words are stubs: each stages its arguments in the GFX_FILL_* /
; GFX_CIRCLE_* cells (include/sysvars.inc) and tail-jumps to EXROM_CALL_SLOT,
; whose RET returns to the inner interpreter. Without the EXROM (the HOME ROM
; fitted alone, or a cartridge without chunk 5) EXROM_CALL_SLOT's magic/ABI
; check fails and they do nothing, as RECT does. A ROM that does not include
; core/rectfill.asm has neither word (decision O15-9).
; ============================================================================

    IFNDEF CORE_SHAPES_ASM
    DEFINE CORE_SHAPES_ASM

H_FILL:
    DW   DICT_CHAIN_POINT   ; the including ROM sets this (DEFL) to the
                            ; chain this file extends
    DB   4, "F", "I", "L", "L"
W_FILL:
    rst RST_DPOP            ; hl = y
    ld   (GFX_FILL_Y), hl
    rst RST_DPOP            ; hl = x
    ld   (GFX_FILL_X), hl
    ld   a, (CURRENT_ATTR)
    ld   (GFX_FILL_ATTR), a
    ld   hl, $A000 + (7 * 3)   ; slot 7 = FILL_IMPL
    jp   EXROM_CALL_SLOT       ; tail jump: its RET returns to our caller

H_CIRCLE:
    DW   H_FILL
    DB   6, "C", "I", "R", "C", "L", "E"
W_CIRCLE:
    rst RST_DPOP            ; hl = r
    ld   (GFX_CIRCLE_R), hl
    rst RST_DPOP            ; hl = yc
    ld   (GFX_CIRCLE_YC), hl
    rst RST_DPOP            ; hl = xc
    ld   (GFX_CIRCLE_XC), hl
    ld   a, (CURRENT_ATTR)
    ld   (GFX_CIRCLE_ATTR), a
    ld   hl, $A000 + (8 * 3)   ; slot 8 = CIRCLE_IMPL
    jp   EXROM_CALL_SLOT       ; tail jump: its RET returns to our caller

DICT_LATEST_INIT_SHAPES EQU H_CIRCLE   ; head of the dictionary once this
                                       ; file's words are included

    ENDIF
