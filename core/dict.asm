; ============================================================================
; core/dict.asm -- the dictionary format, the data stack and the primitives DROP DUP SWAP OVER + - @ !
;
; Language-layer code, not a kernel module: nothing here touches hardware or INCLUDEs kernel/ or
; include/ (but include/rst_vectors.inc must be in page zero: it holds DPOP_HL and DPUSH_HL).
;
; Subroutine threading: a word's code ends in RET, a colon definition is a list of CALLs, the Z80's
; CALL / RET is the inner interpreter and SP is the return stack. IX is the data stack pointer: it
; points at the top cell (low byte at (ix+0)), a push decrements IX by 2 first, a pop reads and
; then increments it. (Kernel calls use HL, DE, BC and AF only, so IX is free.)
;
; Dictionary header:
;   LINK     2 bytes, the previous entry's LINK field address; 0 for the first entry
;   LENFLAGS 1 byte: bits 0-4 the name length (0-31), bit 7 IMMEDIATE, bits 5-6 reserved (0)
;   NAME     LENFLAGS & $1F bytes, not terminated, no case folding here (FIND decides)
;   code     immediately after the name, no padding: the address is also the CALL target
; The ROM entries are hand-linked: LINK is the literal label of the previous header. LATEST starts at
; the last ROM entry but HERE at FORTH_DICT_RAM, since new headers are compiled into RAM; the chain
; crosses the ROM / RAM boundary as a plain address.
; ============================================================================

    IFNDEF CORE_DICT_ASM
    DEFINE CORE_DICT_ASM

    ASSERT LATEST + 4 <= DSTACK_LIMIT || LATEST >= DSTACK_TOP   ; LATEST stays off the data stack

; ============================================================================
; DROP ( n -- ) -- the first entry: LINK = 0
; ============================================================================
H_DROP:
    DW   0
    DB   4, "D","R","O","P"
W_DROP:
    inc  ix
    inc  ix
    ret

; ============================================================================
; DUP ( n -- n n )
; ============================================================================
H_DUP:
    DW   H_DROP
    DB   3, "D","U","P"
W_DUP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; SWAP ( a b -- b a )
; ============================================================================
H_SWAP:
    DW   H_DUP
    DB   4, "S","W","A","P"
W_SWAP:
    ld   l, (ix+0)     ; l,h = b (top)
    ld   h, (ix+1)
    ld   e, (ix+2)     ; e,d = a (second)
    ld   d, (ix+3)
    ld   (ix+0), e
    ld   (ix+1), d
    ld   (ix+2), l
    ld   (ix+3), h
    ret

; ============================================================================
; OVER ( a b -- a b a )
; ============================================================================
H_OVER:
    DW   H_SWAP
    DB   4, "O","V","E","R"
W_OVER:
    ld   l, (ix+2)     ; copy a (second cell) ...
    ld   h, (ix+3)
    dec  ix
    dec  ix
    ld   (ix+0), l     ; ... onto a new top
    ld   (ix+1), h
    ret

; ============================================================================
; + ( a b -- a+b )
; ============================================================================
H_PLUS:
    DW   H_OVER
    DB   1, "+"
W_PLUS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    add  hl, de        ; hl = a+b
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; - ( a b -- a-b )
; ============================================================================
H_MINUS:
    DW   H_PLUS
    DB   1, "-"
W_MINUS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    ex   de, hl        ; hl = a, de = b
    or   a             ; clear carry before sbc
    sbc  hl, de        ; hl = a-b
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; @ ( addr -- n ) -- fetch
; ============================================================================
H_FETCH:
    DW   H_MINUS
    DB   1, "@"
W_FETCH:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    ld   e, (hl)       ; de = cell at addr, low byte first
    inc  hl
    ld   d, (hl)
    ld   (ix+0), e
    ld   (ix+1), d
    ret

; ============================================================================
; ! ( n addr -- ) -- store
; ============================================================================
H_STORE:
    DW   H_FETCH
    DB   1, "!"
W_STORE:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = n
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   (hl), e
    inc  hl
    ld   (hl), d
    ret

DICT_LATEST_INIT EQU H_STORE       ; the value LATEST is seeded with at cold start

; DPUSH_HL and DPOP_HL (the data-stack push and pop for the larger routines: WORD, FIND, NUMBER,
; the compiler) live in page zero, include/rst_vectors.inc: RST_DPOP ($0008) and RST_DPUSH
; ($0018); the labels DPOP_HL and DPUSH_HL still resolve. The primitives above stay inlined.

    ENDIF
