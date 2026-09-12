; ============================================================================
; include/graphics_exrom_abi.inc — the ONE shared copy of the constants
; that describe rom/graphics_exrom.asm's own service-table shape:
; the magic byte / ABI version pair every Home-side caller (core/
; rectfill.asm's own EXROM_CALL_SLOT) verifies before trusting any
; slot, the table's own fixed slot count, and the computed address
; where the magic/ABI pair actually lands right after that table.
;
; INCLUDEd by BOTH core/rectfill.asm (which only NEEDS the magic/ABI
; values and the computed address, to check against) and rom/
; graphics_exrom.asm (which needs the same magic/ABI values to actually
; emit, and the slot count to size its own table) — two independently
; assembled files that used to each hand-type their own separate copy
; of these same numbers, a real, confirmed drift risk (found during an
; audit pass): nothing enforced that a change to one file's copy also
; reached the other, and this exact class of bug (a service-table
; offset silently drifting between these two files) already shipped
; twice earlier in this project's history. A single shared EQU file
; makes that drift structurally impossible instead of merely
; documented against — growing the table is still append-only (see
; rom/graphics_exrom.asm's own header on why), but now it's a
; one-line, one-file change instead of two hand-kept-in-sync ones.
; ============================================================================

    IFNDEF INCLUDE_GRAPHICS_EXROM_ABI_INC
    DEFINE INCLUDE_GRAPHICS_EXROM_ABI_INC

GRAPHICS_EXROM_MAGIC     EQU $F0
GRAPHICS_EXROM_ABI       EQU 1
GRAPHICS_EXROM_MAX_SLOTS EQU 8

; Computed, not hand-typed: rom/graphics_exrom.asm's own service table
; is GRAPHICS_EXROM_MAX_SLOTS slots of 3 bytes each, immediately
; followed by GRAPHICS_EXROM_UNIMPLEMENTED's own 1-byte RET, THEN the
; magic/ABI pair — this exact formula shipped once with that trailing
; RET byte forgotten (a real off-by-one, caught by re-running the
; RECT/POLYGON smoke ROMs under real ZEsarUX after the table was
; fixed-sized, not by re-deriving the number by eye a second time).
GRAPHICS_EXROM_MAGIC_ADDR EQU $A000 + (GRAPHICS_EXROM_MAX_SLOTS * 3) + 1

    ENDIF
