; ============================================================================
; core/comment.asm -- the comments \ and (
;
; Needs core/dict.asm (SRC_PTR, SRC_END). Link fields: a word's DW is DICT_CHAIN_POINT, which the
; including ROM sets (DEFL) to the chain the word extends. Every word here may destroy all registers
; except IX, IY and SP.
;
; Both are immediate, so they work at the prompt and inside a definition. The interpreter has
; already consumed the delimiter after the word itself: a space, or the CR that ends a line of
; LOAD-TEXT's or EDIT's text. A ( comment can run over several such lines.
; ============================================================================

    IFNDEF CORE_COMMENT_ASM
    DEFINE CORE_COMMENT_ASM

; ============================================================================
; \ ( -- ) IMMEDIATE -- a comment to the end of the line: the input is skipped past the next CR,
; or to its end
; ============================================================================
H_BACKSLASH:
    DW   DICT_CHAIN_POINT
    DB   $81, $5C
W_BACKSLASH:
    ld   hl, (SRC_PTR)
    dec  hl
    ld   a, (hl)
    cp   13
    ret  z                        ; \ ended its line: the comment is empty
    ld   c, 13
    jr   SKIP_PAST

; ============================================================================
; ( ( -- ) IMMEDIATE -- a comment to the next ): the input is skipped past it, or to its end
; ============================================================================
H_PAREN:
    DW   H_BACKSLASH
    DB   $81, "("
W_PAREN:
    ld   c, ")"
; SKIP_PAST -- advance SRC_PTR past the next byte C, or to SRC_END if there is none
; Destroys: AF, DE, HL
SKIP_PAST:
    ld   hl, (SRC_PTR)
    ld   de, (SRC_END)
.loop:
    ld   a, h
    cp   d
    jr   nz, .more
    ld   a, l
    cp   e
    jr   z, .done
.more:
    ld   a, (hl)
    inc  hl
    cp   c
    jr   nz, .loop
.done:
    ld   (SRC_PTR), hl
    ret


    ENDIF
