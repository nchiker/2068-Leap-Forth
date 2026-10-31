; ============================================================================
; include/graphics_exrom_abi.inc -- the shape of rom/graphics_exrom.asm's service table
;
; The one shared copy of the magic byte / ABI version pair that every Home-side caller
; (EXROM_CALL_SLOT in core/rectfill.asm) verifies before trusting a slot, the table's fixed
; slot count, and the address where the magic/ABI pair lands after the table. INCLUDEd by both
; core/rectfill.asm (which checks them) and rom/graphics_exrom.asm (which emits them and sizes
; its table), so the two cannot drift. The table is append-only (see rom/graphics_exrom.asm).
; ============================================================================

    IFNDEF INCLUDE_GRAPHICS_EXROM_ABI_INC
    DEFINE INCLUDE_GRAPHICS_EXROM_ABI_INC

GRAPHICS_EXROM_BASE      EQU $A000   ; where the EXROM image sits while paged in (chunk 5)
GRAPHICS_EXROM_MAGIC     EQU $F0
GRAPHICS_EXROM_ABI       EQU 2
GRAPHICS_EXROM_MAX_SLOTS EQU 16

; The table is GRAPHICS_EXROM_MAX_SLOTS slots of 3 bytes, then GRAPHICS_EXROM_UNIMPLEMENTED's
; 1-byte RET, then the magic/ABI pair.
GRAPHICS_EXROM_MAGIC_ADDR EQU GRAPHICS_EXROM_BASE + (GRAPHICS_EXROM_MAX_SLOTS * 3) + 1

    ENDIF
