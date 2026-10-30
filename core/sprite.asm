; ============================================================================
; core/sprite.asm -- SPRITE-DEFINE, SPRITE-SHOW, SPRITE-HIDE
;
; A small sprite system: four numbered slots (0-3) of 16x16 pixels (2x2 character cells),
; backed by the EXROM's service slots 2-4 (rom/graphics_exrom.asm). Needs core/dict.asm,
; core/interp.asm, kernel/bank/bank.asm and core/rectfill.asm (EXROM_CALL_SLOT) INCLUDEd first.
; The including ROM sets DICT_CHAIN_POINT (DEFL). Dictionary words destroy every register
; except IX/IY/SP.
;
; The words only stage SPRITE_OP_* and call the slot; the arguments are validated EXROM-side
; (SPRITE_DEFINE_IMPL, SPRITE_SHOW_IMPL, SPRITE_HIDE_IMPL) to keep the Home ROM small.
; ============================================================================

    IFNDEF CORE_SPRITE_ASM
    DEFINE CORE_SPRITE_ASM

; ============================================================================
; SPRITE-DEFINE ( slot row col -- ) -- capture the screen's 2x2 character cells at (row, col)
; as the slot's image
; ============================================================================
H_SPRITEDEFINE:
    DW   DICT_CHAIN_POINT
    DB   13, "S", "P", "R", "I", "T", "E", "-", "D", "E", "F", "I", "N", "E"
W_SPRITEDEFINE:
    rst RST_DPOP             ; hl = col
    ld   a, l
    ld   (SPRITE_OP_COL), a
    rst RST_DPOP             ; hl = row
    ld   a, l
    ld   (SPRITE_OP_ROW), a
    rst RST_DPOP             ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, GRAPHICS_EXROM_BASE + (2 * 3)   ; slot 2 = SPRITE_DEFINE_IMPL
    call EXROM_CALL_SLOT
    ret

; ============================================================================
; SPRITE-SHOW ( slot row col -- ) -- save the screen at (row, col) as the slot's background,
; then draw the slot's image there; does nothing if the slot was never defined or is shown
; ============================================================================
H_SPRITESHOW:
    DW   H_SPRITEDEFINE
    DB   11, "S", "P", "R", "I", "T", "E", "-", "S", "H", "O", "W"
W_SPRITESHOW:
    rst RST_DPOP             ; hl = col
    ld   a, l
    ld   (SPRITE_OP_COL), a
    rst RST_DPOP             ; hl = row
    ld   a, l
    ld   (SPRITE_OP_ROW), a
    rst RST_DPOP             ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, GRAPHICS_EXROM_BASE + (3 * 3)   ; slot 3 = SPRITE_SHOW_IMPL
    call EXROM_CALL_SLOT
    ret

; ============================================================================
; SPRITE-HIDE ( slot -- ) -- restore the slot's saved background over where it was shown;
; does nothing if the slot is not shown
; ============================================================================
H_SPRITEHIDE:
    DW   H_SPRITESHOW
    DB   11, "S", "P", "R", "I", "T", "E", "-", "H", "I", "D", "E"
W_SPRITEHIDE:
    rst RST_DPOP             ; hl = slot
    ld   a, l
    ld   (SPRITE_OP_SLOT), a
    ld   hl, GRAPHICS_EXROM_BASE + (4 * 3)   ; slot 4 = SPRITE_HIDE_IMPL
    call EXROM_CALL_SLOT
    ret

DICT_LATEST_INIT_SPRITE EQU H_SPRITEHIDE   ; the chain head once this file is included

    ENDIF
