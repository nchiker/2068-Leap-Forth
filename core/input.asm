; ============================================================================
; core/input.asm -- ACCEPT and INPUT, line input
;
; Needs core/dict.asm, core/interp.asm, core/print.asm (W_EMIT), core/string.asm (W_VAL) and
; kernel/io/io.asm (IO_READ_KEY; KEY_ENTER and KEY_DELETE from include/keys.inc). Link fields: a
; word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the word
; extends. Every word here may destroy all registers except IX, IY and SP.
;
; ACCEPT's DELETE moves the print cursor back one column, blanks it and moves back again. It is
; not row-aware: at column 0 it does nothing on screen, so a line that wrapped cannot be deleted
; back across the wrap visually (core/editor.asm's EDITOR_PROCESS_KEY has the same limit).
; ============================================================================

    IFNDEF CORE_INPUT_ASM
    DEFINE CORE_INPUT_ASM

; ============================================================================
; ACCEPT ( dest maxlen -- len ) -- read a line from the keyboard into dest, echoing, until ENTER;
; len is the number of characters typed. DELETE removes the last one; a key past maxlen is ignored
; ============================================================================
H_ACCEPT:
    DW   DICT_CHAIN_POINT
    DB   6, "A", "C", "C", "E", "P", "T"
W_ACCEPT:
    rst RST_DPOP                  ; HL = maxlen
    ld   a, l
    ld   (ACCEPT_MAX), a
    rst RST_DPOP                  ; HL = dest
    ld   (ACCEPT_DEST), hl
    xor  a
    ld   (ACCEPT_LEN), a
.loop:
    call IO_READ_KEY              ; A = the next key (blocks)
    cp   KEY_ENTER
    jr   z, .done
    cp   KEY_DELETE
    jr   z, .del

    ld   (ACCEPT_CHAR), a
    ld   a, (ACCEPT_LEN)
    ld   b, a
    ld   a, (ACCEPT_MAX)
    cp   b
    jr   z, .loop                 ; at the limit: the key is ignored

    ld   hl, (ACCEPT_DEST)
    ld   a, (ACCEPT_LEN)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (ACCEPT_CHAR)
    ld   (hl), a

    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT                   ; echo it

    ld   a, (ACCEPT_LEN)
    inc  a
    ld   (ACCEPT_LEN), a
    jr   .loop

.del:
    ld   a, (ACCEPT_LEN)
    or   a
    jr   z, .loop                 ; nothing typed
    dec  a
    ld   (ACCEPT_LEN), a

    ld   a, (PRINT_COL)
    or   a
    jr   z, .loop                 ; column 0: not row-aware (file header)
    dec  a
    ld   (PRINT_COL), a
    ld   hl, ' '
    rst RST_DPUSH
    call W_EMIT                   ; blank it; W_EMIT leaves PRINT_COL one past, corrected below
    ld   a, (PRINT_COL)
    dec  a
    ld   (PRINT_COL), a
    jr   .loop

.done:
    ld   a, (ACCEPT_LEN)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    ret

; ============================================================================
; INPUT ( -- n ) -- read a line of up to 8 characters through ACCEPT and return its VAL
; ============================================================================
H_INPUT:
    DW   H_ACCEPT
    DB   5, "I", "N", "P", "U", "T"
W_INPUT:
    ld   hl, FINPUT_BUF
    rst RST_DPUSH
    ld   hl, 8
    rst RST_DPUSH
    call W_ACCEPT                 ; ( -- len )
    rst RST_DPOP
    push hl                       ; len, while the address goes under it
    ld   hl, FINPUT_BUF
    rst RST_DPUSH
    pop  hl
    rst RST_DPUSH                 ; ( addr len ), as W_VAL expects
    call W_VAL
    ret

DICT_LATEST_INIT_INPUT EQU H_INPUT     ; the chain head when this is the last file included

    ENDIF
