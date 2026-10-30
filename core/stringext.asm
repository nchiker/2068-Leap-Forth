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
    xor  a                     ; negate hl -- correct even for $8000
    sub  l
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
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
    ld   a, (ix+0)
    or   (ix+1)
    ret  z                      ; len == 0 -- nothing to do (also
                                 ; avoids DJNZ's own "0 means 256" trap)
    ld   b, (ix+0)
    ld   l, (ix+2)
    ld   h, (ix+3)
.loop:
    ld   a, (hl)
    cp   "a"
    jr   c, .skip
    cp   "z" + 1
    jr   nc, .skip
    sub  32                      ; lowercase -> uppercase
    ld   (hl), a
.skip:
    inc  hl
    djnz .loop
    ret

; ============================================================================
; LOWER ( addr len -- addr len ) -- upper case to lower case in place
; ============================================================================
H_LOWER:
    DW   H_UPPER
    DB   5, "L", "O", "W", "E", "R"
W_LOWER:
    ld   a, (ix+0)
    or   (ix+1)
    ret  z
    ld   b, (ix+0)
    ld   l, (ix+2)
    ld   h, (ix+3)
.loop:
    ld   a, (hl)
    cp   "A"
    jr   c, .skip
    cp   "Z" + 1
    jr   nc, .skip
    add  a, 32                   ; uppercase -> lowercase
    ld   (hl), a
.skip:
    inc  hl
    djnz .loop
    ret

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
    rst RST_DPOP                 ; hl = len2
    ld   a, l
    ld   (SRCH_LEN2), a
    rst RST_DPOP                  ; hl = addr2
    ld   (SRCH_ADDR2), hl
    ld   a, (ix+0)                  ; peek len1: addr1/len1 stay on the stack,
    ld   (SRCH_LEN1), a              ; popped once the result is known
    ld   l, (ix+2)
    ld   h, (ix+3)
    ld   (SRCH_ADDR1), hl

    ld   a, (SRCH_LEN2)
    or   a
    jr   z, .notfound                   ; empty needle

    ld   a, (SRCH_LEN1)
    ld   b, a
    ld   a, (SRCH_LEN2)
    ld   c, a
    ld   a, b
    sub  c                                ; a = len1 - len2
    jr   c, .notfound                      ; borrow: the needle is longer than the haystack
    ld   (SRCH_MAXPOS), a
    xor  a
    ld   (SRCH_POS), a
.outer:
    ld   a, (SRCH_POS)
    ld   b, a
    ld   a, (SRCH_MAXPOS)
    cp   b
    jr   c, .notfound                       ; pos > maxpos -- exhausted
    ld   hl, (SRCH_ADDR1)
    ld   a, (SRCH_POS)
    ld   d, 0
    ld   e, a
    add  hl, de                              ; hl = addr1 + pos
    ld   de, (SRCH_ADDR2)
    ld   a, (SRCH_LEN2)
    ld   b, a
.inner:
    ld   a, (de)
    cp   (hl)
    jr   nz, .nomatch
    inc  hl
    inc  de
    djnz .inner
    jr   .found                                ; all len2 bytes matched
.nomatch:
    ld   a, (SRCH_POS)
    inc  a
    ld   (SRCH_POS), a
    jr   .outer
.found:
    rst RST_DPOP                               ; discard len1
    rst RST_DPOP                                ; and addr1 (both are in SRCH_*)
    ld   hl, (SRCH_ADDR1)
    ld   a, (SRCH_POS)
    ld   d, 0
    ld   e, a
    add  hl, de
    rst RST_DPUSH                                ; addr3
    ld   a, (SRCH_LEN1)
    sub  e                                          ; len3 = len1 - pos (E = pos; RST_DPUSH keeps DE)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH                                   ; len3
    ld   hl, -1
    rst RST_DPUSH                                    ; flag = true
    ret
.notfound:
    rst RST_DPOP                                      ; discard len1
    rst RST_DPOP                                       ; discard addr1
    ld   hl, (SRCH_ADDR1)
    rst RST_DPUSH                                        ; addr3 = addr1
    ld   a, (SRCH_LEN1)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH                                          ; len3 = len1
    ld   hl, 0
    rst RST_DPUSH                                           ; flag = false
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

DICT_LATEST_INIT_STRINGEXT EQU H_CODE

    ENDIF
