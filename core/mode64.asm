; ============================================================================
; core/mode64.asm — Phase 8 (stretch goal): 64-column display, Forth words
;
; Builds on core/dict.asm, core/interp.asm, and core/float.asm (all
; must be INCLUDEd first — chains onto core/float.asm's H_FMINUS) and
; kernel/mode64/mode64.asm — see that file's own header for the real
; provenance of the underlying routines (recovered, tested 2068-Leap
; code, not written from scratch here).
;
; WHAT THIS ADDS — thin wrappers, exactly the same shape as Phase 5's
; core/ts2068.asm:
;   64COL      ( -- )        MODE64_ON
;   32COL      ( -- )        MODE64_OFF
;   PALETTE64  ( n -- )      MODE64_SET_PALETTE
;   PLOT64     ( x y -- )    MODE64_WRITE_PIXEL (OVER=0, always set)
; ============================================================================

    IFNDEF CORE_MODE64_ASM
    DEFINE CORE_MODE64_ASM

; ============================================================================
; 64COL ( -- )
; ============================================================================
H_64COL:
    DW   H_FMINUS
    DB   5, "6", "4", "C", "O", "L"
W_64COL:
    call MODE64_ON
    ret

; ============================================================================
; 32COL ( -- )
; ============================================================================
H_32COL:
    DW   H_64COL
    DB   5, "3", "2", "C", "O", "L"
W_32COL:
    call MODE64_OFF
    ret

; ============================================================================
; PALETTE64 ( n -- )
; ============================================================================
H_PALETTE64:
    DW   H_32COL
    DB   9, "P", "A", "L", "E", "T", "T", "E", "6", "4"
W_PALETTE64:
    call DPOP_HL
    ld   a, l
    call MODE64_SET_PALETTE
    ret

; ============================================================================
; PLOT64 ( x y -- )  x is 0-511, y is 0-191
; ============================================================================
H_PLOT64:
    DW   H_PALETTE64
    DB   6, "P", "L", "O", "T", "6", "4"
W_PLOT64:
    call DPOP_HL           ; hl = y
    ld   c, l
    call DPOP_HL           ; hl = x (full 16-bit — 0-511 doesn't fit a byte)
    ld   d, 0               ; OVER=0: set, don't XOR-toggle
    call MODE64_WRITE_PIXEL
    ret

DICT_LATEST_INIT_P8B EQU H_PLOT64   ; head of the dictionary as of
                                    ; Phase 8's 64-column addition

    ENDIF
