; ============================================================================
; core/string.asm -- S", TYPE, STRING, PLACE, COUNT, LEN, VAL: string handling
;
; Strings are (addr len) pairs on the stack, or counted strings (a length byte then the characters, as
; WORD_BUF and the dictionary names are). Needs core/dict.asm, core/interp.asm and core/print.asm
; (W_EMIT). Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may
; destroy all registers except IX (the data stack pointer), IY and SP.
; STRING buffers are fixed-size and nothing is bounds-checked: PLACE of more than n characters into an
; n-character STRING overruns it. Lengths are one byte. CHR$, STR$, UPPER$/LOWER$, LEFT$/RIGHT$ and INSTR
; are not provided.
; ============================================================================

    IFNDEF CORE_STRING_ASM
    DEFINE CORE_STRING_ASM

; ============================================================================
; DOSSTR -- the run-time half of a compiled S" (not a dictionary word)
; In:  the return address -> a length byte, then that many characters (core/dotquote.asm's DOSTR idiom)
; Out: addr (the inline characters, not copied: valid as long as the compiled code is) and len pushed on
;      the data stack; returns to the byte after the last character
; Destroys: AF, DE, HL
; ============================================================================
DOSSTR:
    pop  hl                   ; hl = address of the length byte
    ld   a, (hl)
    ld   (DOSSTR_LEN), a
    inc  hl                    ; hl = the string's own address (first
                                ; char)
    ld   (DOSSTR_ADDR), hl
    ld   e, a
    ld   d, 0
    add  hl, de                 ; hl = continuation address (string
                                 ; address + length)
    push hl                      ; restore as the real return address
    ld   hl, (DOSSTR_ADDR)
    rst RST_DPUSH                ; push addr
    ld   a, (DOSSTR_LEN)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH                 ; push len
    ret

; ============================================================================
; S" ( -- addr len ) IMMEDIATE -- a string literal, text up to the closing "
; Compiling: compiles CALL DOSSTR + length + characters (the scan is core/dotquote.asm's).
; Interpreting: pushes addr and len itself and gives the compiled bytes back (HERE rolled back).
; ============================================================================
H_SQUOTE:
    DW   DICT_CHAIN_POINT
    DB   $82, "S", '"'       ; length 2, IMMEDIATE (bit 7 set)
W_SQUOTE:
    ld   hl, (HERE)
    ld   (SQUOTE_CODE_ADDR), hl   ; where "CALL DOSSTR" starts, to roll HERE back when interpreting
    ld   hl, DOSSTR
    call COMPILE_CALL

    ; no leading-space skip: W_WORD already consumed it
    ld   de, (HERE)
    push de                    ; the length byte's address
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
    pop  hl                    ; hl = the length byte's own address
    ld   (hl), b
    ld   (HERE), de

    ld   a, (STATE)
    or   a
    ret  nz                     ; compiling: the compiled bytes stay for the definition to run

    ; Interpreting: push (addr len) here rather than running the compiled CALL DOSSTR: DOSSTR returns to
    ; the code after its inline data, and at the prompt that is blank dictionary space.
    inc  hl                     ; hl = the characters (hl was the length byte's address)
    rst RST_DPUSH               ; push addr
    ld   a, b                    ; len (B untouched since the scan)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH                ; push len

    ; give back the dictionary space of the CALL DOSSTR and the string
    ld   hl, (SQUOTE_CODE_ADDR)
    ld   (HERE), hl
    ret

; ============================================================================
; TYPE ( addr len -- ) -- print the string (len is taken as a byte)
; ============================================================================
H_TYPE:
    DW   H_SQUOTE
    DB   4, "T", "Y", "P", "E"
W_TYPE:
    rst RST_DPOP             ; hl = len
    ld   a, l
    rst RST_DPOP               ; hl = addr
    ld   b, a                  ; b = len
    or   a
    ret  z                       ; empty string -- nothing to print
.loop:
    ld   a, (hl)
    push hl                      ; W_EMIT (via GFX_PUTCHAR) destroys HL and BC:
    push bc                      ; keep the string pointer and the counter
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .loop
    ret

; ============================================================================
; STRING ( n "name" -- ) -- create name ( -- caddr ): a zeroed counted-string buffer of n characters
; The word's body is CALL DOLIT + the buffer address, then RET; the buffer (count byte + n) follows.
; Errors: DICT_ROOM refuses (the dictionary guard) when the buffer would not fit
; ============================================================================
H_STRING:
    DW   H_TYPE
    DB   6, "S", "T", "R", "I", "N", "G"
W_STRING:
    rst RST_DPOP                  ; HL = n (max characters)
    inc  hl                       ; and the count byte
    ld   a, h
    or   l
    jr   nz, .sized
    dec  hl                       ; n = 65535: $FFFF, which DICT_ROOM refuses whatever HERE is
.sized:
    ld   b, h
    ld   c, l
    jp   VARIABLE_N              ; a STRING is a VARIABLE with n + 1 data bytes

; ============================================================================
; PLACE ( addr len dest -- ) -- copy len bytes from addr to dest's data and set dest's count byte to len
; ============================================================================
H_PLACE:
    DW   H_STRING
    DB   5, "P", "L", "A", "C", "E"
W_PLACE:
    rst RST_DPOP             ; hl = dest
    push hl                    ; kept on the machine stack
    rst RST_DPOP                ; hl = len
    ld   a, l
    push af                       ; len, likewise (it fits a byte)
    rst RST_DPOP                   ; hl = addr (source)
    pop  af
    ld   b, a                        ; b = len
    pop  de                           ; de = dest
    ld   a, b
    ld   (de), a                       ; dest's own count byte = len
    inc  de                             ; de -> dest's own data area
    ld   a, b
    or   a
    ret  z                                ; len=0 -- nothing more to copy
.copyloop:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .copyloop
    ret

; ============================================================================
; COUNT ( caddr -- addr len ) -- a counted string as an (addr len) pair
; ============================================================================
H_COUNT:
    DW   H_PLACE
    DB   5, "C", "O", "U", "N", "T"
W_COUNT:
    rst RST_DPOP             ; hl = caddr
    ld   a, (hl)                ; a = the count byte (RST_DPUSH keeps AF)
    inc  hl                      ; hl = the data address
    rst RST_DPUSH                ; push addr
    ld   l, a
    ld   h, 0
    rst RST_DPUSH                 ; push len
    ret

; ============================================================================
; LEN ( caddr -- n ) -- the count byte of a counted string
; ============================================================================
H_LEN:
    DW   H_COUNT
    DB   3, "L", "E", "N"
W_LEN:
    rst RST_DPOP
    ld   a, (hl)
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    ret

; ============================================================================
; VAL ( addr len -- n ) -- parse a signed decimal integer; an empty string, a lone "-" or any non-digit gives 0
; core/interp.asm's NUMBER accumulates digits the same way (*10 + digit); it is repeated here, not shared,
; so that file stays untouched. Unlike NUMBER, VAL does no dictionary lookup.
; ============================================================================
H_VAL:
    DW   H_LEN
    DB   3, "V", "A", "L"
W_VAL:
    rst RST_DPOP             ; hl = len
    ld   a, l
    rst RST_DPOP                 ; hl = addr (popped before any exit)
    or   a
    jr   z, .fail               ; empty string -- 0
    ld   (VAL_COUNT), a
    ld   (VAL_PTR), hl
    xor  a
    ld   (VAL_NEG), a
    ld   a, (hl)
    cp   "-"
    jr   nz, .noneg
    ld   a, 1
    ld   (VAL_NEG), a
    inc  hl
    ld   (VAL_PTR), hl
    ld   a, (VAL_COUNT)
    dec  a
    ld   (VAL_COUNT), a
    jr   z, .fail                ; lone "-" is not a number
.noneg:
    ld   de, 0                    ; de = running magnitude
.digitloop:
    ld   a, (VAL_COUNT)
    or   a
    jr   z, .donedigits
    dec  a
    ld   (VAL_COUNT), a
    ld   hl, (VAL_PTR)
    ld   a, (hl)
    inc  hl
    ld   (VAL_PTR), hl
    cp   "0"
    jr   c, .fail
    cp   "9"+1
    jr   nc, .fail
    sub  "0"                      ; a = this digit, 0-9
    ld   l, a
    ld   h, 0
    push hl                       ; save the digit
    ld   h, d
    ld   l, e                     ; hl = old magnitude
    add  hl, hl                   ; *2
    ld   b, h
    ld   c, l                     ; bc = magnitude*2
    add  hl, hl                   ; *4
    add  hl, hl                   ; *8
    add  hl, bc                   ; magnitude*10
    pop  bc                       ; bc = digit
    add  hl, bc                   ; + digit
    ex   de, hl                   ; de = new magnitude
    jr   .digitloop
.donedigits:
    ld   a, (VAL_NEG)
    or   a
    jr   z, .positive
    ex   de, hl
    call MATH_NEGATE16
    jr   .pushresult
.positive:
    ex   de, hl                   ; hl = result
.pushresult:
    rst RST_DPUSH
    ret
.fail:
    ld   hl, 0
    rst RST_DPUSH
    ret


    ENDIF
