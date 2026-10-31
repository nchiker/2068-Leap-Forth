; ============================================================================
; core/stringext.asm -- CHR, STR, UPPER, LOWER, LEFT, RIGHT, SEARCH, CODE: string functions
;
; BASIC's CHR$, STR$, UPPER$/LOWER$, LEFT$/RIGHT$, INSTR and CODE, without the `$`; INSTR is ANS Forth's
; SEARCH. Needs core/string.asm (chained onto its tail, H_VAL) and core/print.asm (UDIV10). Strings are
; (addr len) pairs; lengths are one byte (the high byte is ignored). Chained from DICT_CHAIN_POINT; every
; word may destroy all registers except IX (the data stack pointer), IY and SP.
; UPPER and LOWER change the string in place, so addr must be writable RAM (a STRING buffer or a PLACE
; destination): a write to ROM is silently discarded. The other words only read.
; LEFT and RIGHT return a view into the same memory, not a copy; n >= len leaves the string whole.
; STR formats into a fixed 6-byte buffer (sign + 5 digits, "-32768" at most) with W_DOT's digit loop.
; Checked by hand: STR(42) = "42", STR(-5) = "-5", STR(0) = "0"; RIGHT of addr $8000, len 10, n 3 gives
; $8007, 3; SEARCH("HELLO WORLD","WORLD") gives pos 6, addr1+6, len 5, true; SEARCH("HELLO","XYZ") tries
; positions 0-2 and gives false; a needle longer than the haystack is rejected by the borrow in
; len1 - len2 before any comparison.
; ============================================================================

    IFNDEF CORE_STRINGEXT_ASM
    DEFINE CORE_STRINGEXT_ASM

; ============================================================================
; CHR ( code -- addr len ) -- the low byte of code as a 1-character string in the fixed buffer CHR_BUF
; ============================================================================
H_CHR:
    DW   DICT_CHAIN_POINT
    DB   3, "C", "H", "R"
W_CHR:
    rst RST_DPOP            ; hl = code
    ld   a, l
    ld   (CHR_BUF), a
    ld   hl, CHR_BUF
    rst RST_DPUSH
    ld   hl, 1
    rst RST_DPUSH
    ret

; ============================================================================
; STR ( n -- addr len ) -- n as a signed decimal string in the fixed buffer STR_BUF
; ============================================================================
H_STR:
    DW   H_CHR
    DB   3, "S", "T", "R"
W_STR:
    rst RST_DPOP             ; hl = n
    ld   de, STR_BUF
    ld   a, h
    and  $80
    jr   z, .positive
    ld   a, "-"
    ld   (de), a
    inc  de
    call MATH_NEGATE16           ; -32768 stays -32768
.positive:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   a, "0"
    ld   (de), a
    inc  de
    jr   .done
.hasdigits:
    ld   c, 0
.divloop:
    ld   a, h
    or   l
    jr   z, .writedigits
    call UDIV10                ; hl = hl/10, a = digit (0-9)
    push af
    inc  c
    jr   .divloop
.writedigits:
    ld   b, c
.writeloop:
    pop  af
    add  a, "0"
    ld   (de), a
    inc  de
    djnz .writeloop
.done:
    ld   hl, STR_BUF
    rst RST_DPUSH
    ex   de, hl                 ; hl = one past the last byte written
    ld   de, STR_BUF
    or   a
    sbc  hl, de                  ; hl = length = end - start
    rst RST_DPUSH
    ret

; ============================================================================
; UPPER ( addr len -- addr len ) -- lower case to upper case in place (the cells are peeked, not popped)
; ============================================================================
H_UPPER:
    DW   H_STR
    DB   5, "U", "P", "P", "E", "R"
W_UPPER:
    ld   bc, "a" * 256 + (-32 & $FF)   ; B = the first letter changed, C = what is added to it
    jr   W_LOWER.map

; ============================================================================
; LOWER ( addr len -- addr len ) -- upper case to lower case in place
; ============================================================================
H_LOWER:
    DW   H_UPPER
    DB   5, "L", "O", "W", "E", "R"
W_LOWER:
    ld   bc, "A" * 256 + 32
.map:
    ld   e, (ix+0)
    ld   d, (ix+1)                     ; DE = len
    ld   l, (ix+2)
    ld   h, (ix+3)
.loop:
    ld   a, d
    or   e
    ret  z
    dec  de
    ld   a, (hl)
    sub  b
    cp   26
    jr   nc, .skip                     ; not one of the 26 letters
    add  a, b
    add  a, c
    ld   (hl), a
.skip:
    inc  hl
    jr   .loop

; ============================================================================
; LEFT ( addr len n -- addr len' ) -- the first n characters (the whole string if n >= len, or n < 0)
; ============================================================================
H_LEFT:
    DW   H_LOWER
    DB   4, "L", "E", "F", "T"
W_LEFT:
    rst RST_DPOP               ; hl = n
    inc  h
    dec  h
    ret  nz                     ; n >= 256 (or negative): the whole string
    ld   a, l
    ld   d, (ix+0)               ; d = current len (low byte)
    cp   d
    jr   nc, .keep                ; n >= len -- keep len as-is
    ld   (ix+0), a                 ; n < len -- new len = n
    ld   (ix+1), 0
.keep:
    ret

; ============================================================================
; RIGHT ( addr len n -- addr' len' ) -- the last n characters (the whole string if n >= len, or n < 0)
; ============================================================================
H_RIGHT:
    DW   H_LEFT
    DB   5, "R", "I", "G", "H", "T"
W_RIGHT:
    rst RST_DPOP                ; hl = n
    inc  h
    dec  h
    ret  nz                      ; n >= 256 (or negative): the whole string
    ld   a, l
    ld   c, (ix+0)                ; c = current len (low byte)
    cp   c
    jr   nc, .keep                  ; n >= len -- keep addr/len as-is
    ld   b, a                        ; b = n (kept for the len write below)
    ld   a, c
    sub  b                            ; a = len - n = how far to advance
    ld   l, (ix+2)                     ; hl = current addr
    ld   h, (ix+3)
    ld   d, 0
    ld   e, a
    add  hl, de                         ; hl = addr + (len-n)
    ld   (ix+2), l
    ld   (ix+3), h
    ld   (ix+0), b                       ; len = n
    ld   (ix+1), 0
.keep:
    ret

; ============================================================================
; SEARCH ( addr1 len1 addr2 len2 -- addr3 len3 flag ) -- find the string 2 (needle) in the string 1
; Found: addr3/len3 is the rest of string 1 from the match, flag true (-1).
; Not found: addr3/len3 is addr1/len1 unchanged, flag false (0). An empty needle is never found.
; ============================================================================
H_SEARCH:
    DW   H_RIGHT
    DB   6, "S", "E", "A", "R", "C", "H"
W_SEARCH:
    rst RST_DPOP
    ld   b, h
    ld   c, l                          ; BC = len2
    rst RST_DPOP
    ex   de, hl                        ; DE = addr2
    ld   a, b
    or   c
    jr   z, .notfound                  ; an empty needle
    ld   l, (ix+0)
    ld   h, (ix+1)                     ; HL = len1 (addr1 and len1 stay on the stack)
    or   a
    sbc  hl, bc
    jr   c, .notfound                  ; the needle is longer than the haystack
    inc  hl
    push hl                            ; the number of places to try
    ld   l, (ix+2)
    ld   h, (ix+3)                     ; HL = the place in string 1
.outer:
    push hl
    push de
    push bc
.inner:
    ld   a, (de)
    cp   (hl)
    jr   nz, .differ
    inc  hl
    inc  de
    dec  bc
    ld   a, b
    or   c
    jr   nz, .inner
    pop  bc
    pop  de
    pop  de                            ; DE = the match
    pop  hl                            ; (the count)
    ld   l, (ix+2)
    ld   h, (ix+3)
    ld   c, (ix+0)
    ld   b, (ix+1)
    add  hl, bc
    or   a
    sbc  hl, de                        ; len3 = addr1 + len1 - the match
    ld   (ix+0), l
    ld   (ix+1), h
    ld   (ix+2), e
    ld   (ix+3), d
    ld   hl, -1
    rst RST_DPUSH
    ret
.differ:
    pop  bc
    pop  de
    pop  hl
    inc  hl
    ex   (sp), hl
    dec  hl
    ld   a, h
    or   l
    ex   (sp), hl
    jr   nz, .outer
    pop  hl
.notfound:
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; CODE ( addr len -- code ) -- the first character's code (the same as `DROP C@`)
; ============================================================================
H_CODE:
    DW   H_SEARCH
    DB   4, "C", "O", "D", "E"
W_CODE:
    rst RST_DPOP                ; hl = len (discarded)
    rst RST_DPOP                 ; hl = addr
    ld   a, (hl)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    ret


    ENDIF
