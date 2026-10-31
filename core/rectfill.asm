; ============================================================================
; core/rectfill.asm -- RECT, a rectangle fill backed by the EXROM, and EXROM_CALL_SLOT
;
; Needs core/dict.asm, core/interp.asm, core/ts2068.asm (CURRENT_ATTR) and kernel/bank/bank.asm
; INCLUDEd first. The including ROM sets DICT_CHAIN_POINT (DEFL) to the chain this file extends.
; Dictionary words destroy every register except IX/IY/SP.
;
; RECT is EXROM-resident (rom/graphics_exrom.asm, RECT_FILL_IMPL) because the Home ROM has too
; little room for the graphics words.
;
; EXROM_CALL_SLOT is shared by every word the EXROM backs (RECT, POLYGON, the SPRITE-* words).
; It checks the image's magic byte and ABI version right after paging chunk 5 in, because a
; cartridge socket can hold something else or nothing. On a mismatch it pages out and returns
; with carry set, and the word silently does nothing (as SOUND, STICK and FILL's HIRES guard do).
; ============================================================================

    IFNDEF CORE_RECTFILL_ASM
    DEFINE CORE_RECTFILL_ASM

; ============================================================================
; EXROM_CALL_SLOT -- page the EXROM in, verify its magic+ABI pair, call a service-table slot
; In:  HL = absolute address of the slot ($A000 + slot*3); the RECT_*/POLY_*/SPRITE_OP_* state
;      the caller has staged
; Out: carry set if the image did not match (nothing ran); carry clear if the slot ran. The
;      EXROM is paged out again either way
; Destroys: AF, BC, DE, HL
; ============================================================================
EXROM_CALL_SLOT:
    push hl                          ; the slot address survives the page-in call
    call BANK_PAGE_EXROM_IN
    pop  hl

    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR)
    cp   GRAPHICS_EXROM_MAGIC
    jr   nz, .mismatch
    ld   a, (GRAPHICS_EXROM_MAGIC_ADDR + 1)
    cp   GRAPHICS_EXROM_ABI
    jr   nz, .mismatch

    call CALL_HL                     ; a nested call: control returns here to page out
    call BANK_PAGE_EXROM_OUT
    or   a                           ; carry clear: ran successfully
    ret

.mismatch:
    call BANK_PAGE_EXROM_OUT
    scf
    ret

; ============================================================================
; CALL_HL -- call the code at HL (there is no `call (hl)`)
; In:  HL = address to call
; Out: whatever the called code returns
; Destroys: whatever the called code destroys
; The caller's `call CALL_HL` already pushed its return address; the push here goes on top of
; it, so this RET jumps to HL and the callee's own RET returns to the caller.
; ============================================================================
CALL_HL:
    push hl
    ret

    INCLUDE "include/graphics_exrom_abi.inc"

; ============================================================================
; RECT ( x0 y0 x1 y1 -- ) -- fill the rectangle between two corners (any order, inclusive)
; with the current colour (CURRENT_ATTR), via the EXROM's RECT_FILL_IMPL; out-of-range or no
; EXROM: nothing is drawn
; ============================================================================
H_RECT:
    DW   DICT_CHAIN_POINT
    DB   4, "R", "E", "C", "T"
W_RECT:
    rst RST_DPOP           ; hl = y1
    ld   a, l
    ld   (RECT_Y1), a
    rst RST_DPOP           ; hl = x1
    ld   a, l
    ld   (RECT_X1), a
    rst RST_DPOP           ; hl = y0
    ld   a, l
    ld   (RECT_Y0), a
    rst RST_DPOP           ; hl = x0
    ld   a, l
    ld   (RECT_X0), a
    ld   a, (CURRENT_ATTR)
    ld   (RECT_ATTR), a
    ld   hl, GRAPHICS_EXROM_BASE + (0 * 3)   ; slot 0 = RECT_FILL_IMPL
    jp   EXROM_CALL_SLOT


    ENDIF
