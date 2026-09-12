; ============================================================================
; core/sprite.asm — SPRITE-DEFINE, SPRITE-SHOW, SPRITE-HIDE
;
; Builds on core/dict.asm, core/interp.asm, kernel/bank/bank.asm, and
; core/rectfill.asm/core/polygon.asm (needs GRAPHICS_EXROM_MAGIC_ADDR
; and CALL_HL — both must be INCLUDEd first, same prerequisites those
; two files already have). This file's own first header chains through
; DICT_CHAIN_POINT.
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
; EXROM_CALL_SPRITE (internal — not in kernel_api.inc)
; Pages chunk 5 to EXROM, verifies rom/graphics_exrom.asm's own magic+
; ABI byte pair (same check core/rectfill.asm's own EXROM_CALL_
; RECT_FILL and core/polygon.asm's own EXROM_CALL_POLY_DRAW already
; make), calls the given service-table slot if and only if that check
; passes, then always pages back out.
; In:  HL = absolute address of the service-table slot to call
;      ($A000 + slot*3); SPRITE_OP_SLOT/ROW/COL — pre-set by whichever
;      word below is calling this
; Out: carry SET if the paged image didn't match (nothing ran); carry
;      CLEAR if the slot actually ran
; Destroys: AF, BC, DE, HL
; ============================================================================
EXROM_CALL_SPRITE:
    push hl                          ; the slot address survives the
                                     ; page-in call (BANK_PAGE_EXROM_IN
                                     ; only destroys AF per its own
                                     ; contract, but stack is simplest
                                     ; and matches this project's own
                                     ; "don't trust a register to
                                     ; survive a call" convention)
    call BANK_PAGE_EXROM_IN
    pop  hl

    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR)
    cp   GRAPHICS_EXROM_MAGIC
    jr   nz, .mismatch
    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR + 1)
    cp   GRAPHICS_EXROM_ABI
    jr   nz, .mismatch

    call CALL_HL                     ; core/polygon.asm's own helper
    call BANK_PAGE_EXROM_OUT
    or   a
    ret

.mismatch:
    call BANK_PAGE_EXROM_OUT
    scf
    ret

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
    call EXROM_CALL_SPRITE
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
    call EXROM_CALL_SPRITE
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
    call EXROM_CALL_SPRITE
    ret

DICT_LATEST_INIT_SPRITE EQU H_SPRITEHIDE   ; head of the dictionary
                                           ; once this file's own words
                                           ; are all included

    ENDIF
