; ============================================================================
; include/exrom_home_ram.inc -- the Home ROM's RAM cells and constants that the
; graphics EXROM's full-screen view (rom/graphics_exrom.asm, VIEW_SESSION) reads
; and writes. The EXROM is assembled on its own and cannot see the Home
; symbols, so these are copies; tools/audit_layout.py compares every line here
; with the symbol of the same name in build/forth_boot.sym (make check), so a
; Home change that moves one fails the build instead of the editor.
; Not INCLUDEd by Home: Home defines each of these where it lives (core/
; editor.asm, core/interp.asm, core/loadtext.asm, core/edit.asm,
; kernel/graphics/graphics.asm).
; ============================================================================

    IFNDEF INCLUDE_EXROM_HOME_RAM_INC
    DEFINE INCLUDE_EXROM_HOME_RAM_INC

EDIT_MAX_LEN       EQU 128      ; core/editor.asm: the edit line's capacity
EDIT_BUF           EQU $8860    ; the edit line (the view's cursor line)
EDIT_LEN           EQU $88E0
EDIT_CURSOR        EQU $88E1
FWRAP_COUNT        EQU $88E4    ; the wrap table (WRAP_CALC / WRAP_CALC_AT)
FWRAP_START        EQU $88E5    ; 4 bytes
FWRAP_LEN          EQU $88E9    ; 4 bytes
FWRAP_OVERFLOW     EQU $88F5
FWRAP_TOP          EQU $88F8    ; screen row of the table's first row
ED_ROW_JP          EQU $88FC    ; RAM `JP` to the row drawer for the width
WORD_BUF           EQU $8520    ; core/interp.asm: counted name, upper case
STORE_END          EQU $8A74    ; core/loadtext.asm: the line store
STORE_START        EQU $D000
STORE_LIMIT        EQU $F000
ATTR_DEFAULT       EQU $44      ; kernel/graphics/graphics.asm

    ENDIF
