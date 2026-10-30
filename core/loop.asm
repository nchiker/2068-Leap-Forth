; ============================================================================
; core/loop.asm -- WHILE and REPEAT
;
; Needs core/dict.asm, core/interp.asm and core/control.asm (QBRANCH, BRANCH, and BEGIN, which
; leaves the loop-start address on the compile-time stack under WHILE's placeholder). Link fields:
; a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the word
; extends. Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_LOOP_ASM
    DEFINE CORE_LOOP_ASM

; ============================================================================
; WHILE ( flag -- ) IMMEDIATE -- compile QBRANCH and a placeholder, whose address is left on the
; compile-time stack above BEGIN's, for REPEAT to patch (as IF does for THEN)
; ============================================================================
H_WHILE:
    DW   DICT_CHAIN_POINT
    DB   $85, "W", "H", "I", "L", "E"
W_WHILE:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK            ; refuses at the prompt (STATE = 0)
    ENDIF
    ld   hl, QBRANCH
    call COMPILE_CALL
    ld   hl, (HERE)
    rst RST_DPUSH
    ld   hl, 0
    call COMPILE_WORD
    ret

; ============================================================================
; REPEAT ( -- ) IMMEDIATE -- compile a branch back to BEGIN's address, then patch WHILE's
; placeholder to land after it
; ============================================================================
H_REPEAT:
    DW   H_WHILE
    DB   $86, "R", "E", "P", "E", "A", "T"
W_REPEAT:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    rst RST_DPOP                       ; HL = WHILE's placeholder address
    push hl
    ld   hl, BRANCH
    call COMPILE_CALL
    rst RST_DPOP                       ; HL = BEGIN's loop-start
    call COMPILE_WORD
    pop  hl
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    ret

DICT_LATEST_INIT_LOOP EQU H_REPEAT     ; the chain head when this is the last file included

    ENDIF
