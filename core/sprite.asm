; ============================================================================
; core/sprite.asm — SPRITE-DEFINE, SPRITE-SHOW, SPRITE-HIDE
;
; Builds on core/dict.asm, core/interp.asm, kernel/bank/bank.asm, and
; core/rectfill.asm specifically (needs EXROM_CALL_SLOT/GRAPHICS_
; EXROM_MAGIC_ADDR/CALL_HL — that file owns all three, reused here
; rather than each word carrying its own copy of the same trampoline;
; see that file's own EXROM_CALL_SLOT header for the duplication this
; replaced). All of the above must be INCLUDEd first. This file's own
; first header chains through DICT_CHAIN_POINT.
;
; WHAT THIS ADDS — a small, fixed-size (16x16 pixel, four numbered
; slots) sprite system, backed by rom/graphics_exrom.asm's service
; slots 2-4:
;   SPRITE-DEFINE ( slot row col -- )   captures the current screen's
;             2x2-character-cell area at (row,col) into the given
;             slot's own image (0-3)
;   SPRITE-SHOW ( slot row col -- )     saves the screen at (row,col)
;             as that slot's background, then draws the slot's own
;             image there. Refuses (does nothing) if the slot was
;             never DEFINEd, or is already SHOWN
;   SPRITE-HIDE ( slot -- )             restores the slot's own saved
;             background over wherever it was last SHOWN. Refuses if
;             the slot isn't currently SHOWN
;
; REBUILT FRESH, not reusing 2068-Leap's own inherited GRAB/SHOW/HIDE
; design — see include/sysvars.inc's own "Sprites, rebuilt fresh for
; 2068-Forth" header for why (that scaffolding was confirmed unused by
; every ROM in this project and removed rather than adapted).
;
; ARGUMENT VALIDATION happens EXROM-side (rom/graphics_exrom.asm's own
; SPRITE_DEFINE_IMPL/SPRITE_SHOW_IMPL/SPRITE_HIDE_IMPL) rather than
; here, to keep this file's own Home ROM cost small — the pattern this
; project settled on once ROM budget got tight this session (RECT/
; POLYGON's own bulk logic lives EXROM-side for the same reason).
; ============================================================================

    IFNDEF CORE_SPRITE_ASM
    DEFINE CORE_SPRITE_ASM

; ============================================================================
; SPRITE-DEFINE ( slot row col -- )
; ============================================================================
H_SPRITEDEFINE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   13, "S", "P", "R", "I", "T", "E", "-", "D", "E", "F", "I", "N", "E"
W_SPRITEDEFINE:
    call DPOP_HL              ; hl = col
    ld   a, l
    ld   (SPRITE_OP_COL), a
    call DPOP_HL              ; hl = row
    ld   a, l
    ld   (SPRITE_OP_ROW), a
    call DPOP_HL              ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, $A000 + (2 * 3)   ; slot 2 = SPRITE_DEFINE_IMPL
    call EXROM_CALL_SLOT
    ret

; ============================================================================
; SPRITE-SHOW ( slot row col -- )
; ============================================================================
H_SPRITESHOW:
    DW   H_SPRITEDEFINE
    DB   11, "S", "P", "R", "I", "T", "E", "-", "S", "H", "O", "W"
W_SPRITESHOW:
    call DPOP_HL              ; hl = col
    ld   a, l
    ld   (SPRITE_OP_COL), a
    call DPOP_HL              ; hl = row
    ld   a, l
    ld   (SPRITE_OP_ROW), a
    call DPOP_HL              ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, $A000 + (3 * 3)   ; slot 3 = SPRITE_SHOW_IMPL
    call EXROM_CALL_SLOT
    ret

; ============================================================================
; SPRITE-HIDE ( slot -- )
; ============================================================================
H_SPRITEHIDE:
    DW   H_SPRITESHOW
    DB   11, "S", "P", "R", "I", "T", "E", "-", "H", "I", "D", "E"
W_SPRITEHIDE:
    call DPOP_HL              ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, $A000 + (4 * 3)   ; slot 4 = SPRITE_HIDE_IMPL
    call EXROM_CALL_SLOT
    ret

DICT_LATEST_INIT_SPRITE EQU H_SPRITEHIDE   ; head of the dictionary
                                           ; once this file's own words
                                           ; are all included

    ENDIF
