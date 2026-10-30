; ============================================================================
; core/dotquote.asm -- ." : print a literal string
;
; Needs core/interp.asm and core/print.asm (W_EMIT). ." is IMMEDIATE and compile-only. One space after
; ." is the delimiter W_WORD already consumed; the string runs to the next " (consumed, not printed).
; With COMPILE_ONLY_CHECK_ENABLED defined (rom/forth_boot.asm), typing ." at the prompt is refused
; with the "WORD ?" error through COMPILE_ONLY_CHECK before anything is compiled.
; It compiles CALL DOSTR followed by a length byte and the characters: DOSTR prints them from its own
; return address, then returns past them (DOLIT's idiom for variable-length inline data).
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_DOTQUOTE_ASM
    DEFINE CORE_DOTQUOTE_ASM

; ============================================================================
; DOSTR -- print the inline string after the CALL (not a dictionary word)
; In:  the return address -> a length byte, then that many characters
; Out: returns to the byte after the last character
; Destroys: AF, BC, DE, HL (through W_EMIT)
; ============================================================================
DOSTR:
    pop  hl                  ; hl = address of the length byte
    ld   b, (hl)              ; b = string length
    inc  hl                   ; hl -> first char (or the continuation
                              ; address, if the string is empty)
    ld   a, b
    or   a
    jr   z, .donestr
.printloop:
    ld   a, (hl)
    push hl                   ; W_EMIT (via GFX_PUTCHAR) destroys HL and BC:
    push bc                   ; keep the string pointer and the djnz counter
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .printloop
.donestr:
    push hl                   ; hl = the continuation address; the ret lands there
    ret

; ============================================================================
; ." ( -- ) IMMEDIATE -- compile CALL DOSTR + length + the characters up to the closing "
; ============================================================================
H_DOTQUOTE:
    DW   DICT_CHAIN_POINT
    DB   $82, ".", '"'       ; length 2, IMMEDIATE (bit 7 set)
W_DOTQUOTE:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK    ; refuse cleanly if typed at the prompt (STATE=0)
    ENDIF
    ld   hl, DOSTR
    call COMPILE_CALL

    ; No leading-space skip: W_WORD consumed the space after ." , so SRC_PTR is at the first character.
    ld   de, (HERE)
    push de                    ; the length byte's address; its value is known after the scan
    inc  de                    ; the characters start after it
    ld   b, 0                  ; running character count
.scan:
    ld   hl, (SRC_END)
    ld   a, h
    ld   c, l
    ld   hl, (SRC_PTR)
    cp   h
    jr   nz, .scan_continue
    ld   a, c
    cp   l
    jr   z, .scandone          ; end of source with no closing '"': stop
.scan_continue:
    ld   a, (hl)
    cp   '"'
    jr   z, .scandone_consume
    ld   (de), a
    inc  hl
    ld   (SRC_PTR), hl
    inc  de
    inc  b
    jr   .scan
.scandone_consume:
    inc  hl
    ld   (SRC_PTR), hl         ; consume the closing '"'
.scandone:
    pop  hl                    ; hl = the length byte's address
    ld   (hl), b
    ld   (HERE), de
    ret

DICT_LATEST_INIT_DOTQUOTE EQU H_DOTQUOTE

    ENDIF
