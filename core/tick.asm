; ============================================================================
; core/tick.asm -- ' (tick) and CHAR, their compiling forms ['] and [CHAR], LITERAL, [ and ]
;
; Needs core/dict.asm, core/interp.asm (WORD_SKIP, WORD_NAME, FIND, COMPILE_LITERAL,
; COMPILE_ONLY_CHECK, STATE) and core/throwcatch.asm (W_THROW). Link fields: a word's DW is
; DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the word extends. Every word
; here may destroy all registers except IX, IY and SP.
;
; [ and ] switch STATE inside a definition: `: X [ 2 3 * ] LITERAL ;` computes 6 once, while X is
; compiled, and compiles it as a literal. ['] [CHAR] LITERAL are immediate and compile-only (at the
; prompt they report `name ?`, as IF does).
; ============================================================================

    IFNDEF CORE_TICK_ASM
    DEFINE CORE_TICK_ASM

; ============================================================================
; ' ( "name" -- xt ) -- the code address of the next input word, not executed; an undefined
; word is THROW -13
; ============================================================================
H_TICK:
    DW   DICT_CHAIN_POINT
    DB   1, "'"
W_TICK:
    call WORD_NAME
    call FIND
    rst RST_DPOP                       ; HL = the found flag
    ld   a, h
    or   l
    jr   nz, .found
    call W_DROP                        ; FIND left the search address: drop it before throwing
    ld   hl, -13                       ; undefined word
    rst RST_DPUSH
    jp   W_THROW
.found:
    rst RST_DPOP                       ; discard the immediate flag: the code address stays
    ret

; ============================================================================
; ['] ( "name" -- ) IMMEDIATE, compile-only -- compile the execution token of name as a literal
; ============================================================================
H_BRACKTICK:
    DW   H_TICK
    DB   $83, "[", "'", "]"
W_BRACKTICK:
    call COMPILE_ONLY_CHECK
    call W_TICK
    jr   LITERAL_TOP

; ============================================================================
; CHAR ( "name" -- c ) -- the first character of the next word, as typed: CHAR a gives 97 (a name
; is folded to upper case, a character is not); no word is THROW -16
; ============================================================================
H_CHAR:
    DW   H_BRACKTICK
    DB   4, "C", "H", "A", "R"
W_CHAR:
    call WORD_SKIP                     ; A = the next word's first character
    push af
    call WORD_NAME                     ; past the word
    rst  RST_DPOP
    pop  af
    ld   l, a
    ld   h, 0
    rst  RST_DPUSH
    ret

; ============================================================================
; [CHAR] ( "name" -- ) IMMEDIATE, compile-only -- compile CHAR's value as a literal
; ============================================================================
H_BRACKCHAR:
    DW   H_CHAR
    DB   $86, "[", "C", "H", "A", "R", "]"
W_BRACKCHAR:
    call COMPILE_ONLY_CHECK
    call W_CHAR
    jr   LITERAL_TOP

; ============================================================================
; LITERAL ( n -- ) IMMEDIATE, compile-only -- compile n as a literal, as a number typed in a
; definition is: the definition pushes n when it runs
; ============================================================================
H_LITERAL:
    DW   H_BRACKCHAR
    DB   $87, "L", "I", "T", "E", "R", "A", "L"
W_LITERAL:
    call COMPILE_ONLY_CHECK
LITERAL_TOP:
    rst  RST_DPOP
    jp   COMPILE_LITERAL

; ============================================================================
; [ ( -- ) IMMEDIATE -- interpret: STATE = 0, so the words after it run inside a definition
; ============================================================================
H_LBRACKET:
    DW   H_LITERAL
    DB   $81, "["
W_LBRACKET:
    xor  a
    ld   (STATE), a
    ret

; ============================================================================
; ] ( -- ) -- compile: STATE = 1 (after [, back into the definition)
; ============================================================================
H_RBRACKET:
    DW   H_LBRACKET
    DB   1, "]"
W_RBRACKET:
    ld   a, 1
    ld   (STATE), a
    ret


    ENDIF
