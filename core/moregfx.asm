; ============================================================================
; core/moregfx.asm — Phase 17: AT-XY (FILL moved to core/shapes.asm, step O15)
;
; Builds on core/dict.asm, core/interp.asm and core/print.asm (needs
; PRINT_ROW/PRINT_COL, Phase 10) — all must be INCLUDEd first. This file's own
; first header chains through DICT_CHAIN_POINT, same convention as every phase
; since core/control.asm.
;
;   AT-XY  ( col row -- )   moves EMIT/./."'s own print position
;             (PRINT_COL/PRINT_ROW, core/print.asm) directly, so the
;             next character printed lands at (col, row) instead of
;             wherever printing last left off
;
; No range checking on AT-XY's col/row (0-31/0-22) — matching every earlier
; phase's own "no error recovery yet" scope note; writing an out-of-range
; position just means the next EMIT/./."-drawn character lands somewhere
; unintended, not a crash.
; ============================================================================

    IFNDEF CORE_MOREGFX_ASM
    DEFINE CORE_MOREGFX_ASM

; ============================================================================
; AT-XY ( col row -- )
; ============================================================================
H_ATXY:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "A", "T", "-", "X", "Y"
W_ATXY:
    rst RST_DPOP          ; hl = row
    ld   a, l
    ld   (PRINT_ROW), a
    rst RST_DPOP          ; hl = col
    ld   a, l
    ld   (PRINT_COL), a
    ret

DICT_LATEST_INIT_MOREGFX EQU H_ATXY   ; head of the dictionary once
                                       ; this file's own words are
                                       ; included

    ENDIF
