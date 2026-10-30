; ============================================================================
; core/array.asm -- ARRAY and CELLS: arrays of cells
;
; Needs core/dict.asm and core/interp.asm (COMPILE_LITERAL, COMPILE_BYTE, W_WORD, HERE, LATEST). ARRAY
; builds its header the way VARIABLE and CONSTANT in core/variable.asm do; the steps are repeated here
; rather than factored out of that file.
; `10 ARRAY NUMS` makes a zeroed 10-cell (20-byte) array; `3 CELLS NUMS + @` reads element 3 and
; `99 3 CELLS NUMS + !` writes it. There is no bounds check.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_ARRAY_ASM
    DEFINE CORE_ARRAY_ASM

; ============================================================================
; ARRAY ( n "name" -- ) -- create name ( -- addr ), leaving the address of n zeroed cells
; The word's body is CALL DOLIT + the address of the elements, then RET; the elements follow it.
; Errors: DICT_ROOM refuses (the dictionary guard) when the elements would not fit
; ============================================================================
H_ARRAY:
    DW   DICT_CHAIN_POINT
    DB   5, "A", "R", "R", "A", "Y"
W_ARRAY:
    rst RST_DPOP           ; hl = n (cell count)
    push hl                 ; kept on the machine stack: only the IX data stack is touched until the pop
    add  hl, hl                  ; the elements (n * 2 bytes) must fit below the ceiling guard;
    sbc  a, a                     ; n * 2 past $FFFF (carry) forces the high byte to $FF, which
    or   h                        ; DICT_ROOM refuses whatever HERE is
    ld   h, a
    call DICT_ROOM
    call W_WORD
    rst RST_DPOP
    ld   (WORD_SRC_ADDR), hl

    ld   de, (HERE)
    ld   (NEW_HEADER_ADDR), de
    ld   hl, (LATEST)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (WORD_SRC_ADDR)
    ld   a, (hl)                  ; name length (W_WORD truncates at 32)
    ld   (de), a
    inc  de
    inc  hl                       ; hl -> first name char
    ld   b, a
    or   a
    jr   z, .namedone
.namecopy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .namecopy
.namedone:
    ld   (HERE), de                ; HERE = this word's body, where the literal below starts

    ld   hl, (HERE)
    ld   de, 6                     ; 5-byte literal (CALL DOLIT + 2-byte target) + 1-byte RET;
    add  hl, de                    ; the elements follow both: hl = their base address
    call COMPILE_LITERAL           ; compiles CALL DOLIT + that address
    ld   a, $C9                    ; Z80 RET opcode
    call COMPILE_BYTE

    pop  hl                        ; hl = n
    add  hl, hl                    ; hl = n*2 -- byte count to zero
    ld   b, h
    ld   c, l                      ; bc = byte count
    ld   hl, (HERE)                ; hl = the elements' base address
    ld   a, b
    or   c
    jr   z, .noinit                ; n=0 -- nothing to zero
.zeroloop:
    xor  a
    ld   (hl), a
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, .zeroloop
.noinit:
    ld   (HERE), hl

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; CELLS ( n -- n*2 ) -- a cell count as a byte offset (a cell is 2 bytes)
; ============================================================================
H_CELLS:
    DW   H_ARRAY
    DB   5, "C", "E", "L", "L", "S"
W_CELLS:
    rst RST_DPOP
    add  hl, hl
    rst RST_DPUSH
    ret


    ENDIF
