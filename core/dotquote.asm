; ============================================================================
; core/dotquote.asm — Phase 13: ." (print a literal string)
;
; Builds on core/dict.asm, core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as core/control.asm and the rest), and core/print.asm
; (needs W_EMIT).
;
; WHAT THIS ADDS (the last remaining gap docs/forth_tutorial.md's "What's
; not here yet" section named: "there's no `."` yet for printing a fixed
; piece of text"):
;   ." text"  ( -- )  IMMEDIATE   compiles code that prints "text"
;             literally when the surrounding definition runs. Exactly
;             one space is required right after `."`, consumed by
;             W_WORD itself as the ordinary delimiter that ends the
;             `."` token (not printed, and not re-consumed here — see
;             W_DOTQUOTE's own note below); the string ends at the next
;             `"` (consumed here, not printed).
;
; COMPILE-TIME ONLY, like IF/ELSE/THEN/BEGIN/UNTIL (core/control.asm) —
; `."` is meaningless outside a colon definition (there is nowhere for
; "compiled code" to go), and this project doesn't support typing it
; directly at the interpreter prompt, matching the scope IF/ELSE/THEN
; already established.
;
; RUNTIME MECHANISM: the same inline-data idiom core/interp.asm's own
; DOLIT established for numeric literals, generalized to a
; variable-length string instead of a fixed 2-byte value. `."` compiles
; "CALL DOSTR" followed by a length byte and the string's own raw
; bytes; DOSTR reads those off its own return address, prints each
; character via core/print.asm's W_EMIT, then corrects the return
; address to skip past all of it (the length byte and every string
; byte) before returning — exactly DOLIT's own trick, just for a
; variable amount of inline data instead of a fixed 2 bytes.
; ============================================================================

    IFNDEF CORE_DOTQUOTE_ASM
    DEFINE CORE_DOTQUOTE_ASM

; ============================================================================
; DOSTR — NOT a dictionary word. Runtime half of a compiled ." string:
; reads a length byte and that many characters off its own return
; address, prints them via W_EMIT, then returns to right after the
; last string byte. Destroys AF, BC, DE, HL (through W_EMIT).
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
    push hl                   ; W_EMIT (via GFX_PUTCHAR) destroys HL --
                              ; preserve our own string pointer
    push bc                   ; ... and BC, our own djnz counter (same
                              ; precaution core/print.asm's W_DOT
                              ; already documents around its own W_EMIT
                              ; calls)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .printloop
.donestr:
    push hl                   ; hl = the real continuation address --
                              ; push it so this ret lands there,
                              ; exactly DOLIT's own idiom
    ret

; ============================================================================
; ." ( -- )  IMMEDIATE
; ============================================================================
H_DOTQUOTE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   $82, ".", '"'       ; length 2, IMMEDIATE (bit 7 set)
W_DOTQUOTE:
    ld   hl, DOSTR
    call COMPILE_CALL

    ; No leading-space skip needed here: W_WORD already consumed the
    ; one delimiting space between "." and the string's own text when
    ; it finished parsing "." as its own token (W_WORD always consumes
    ; whatever space terminated the word it just read) -- SRC_PTR
    ; already points at the string's first real character. Caught by
    ; tracing this by hand before assembling: an extra skip here would
    ; have silently eaten the string's own first character instead.
    ld   de, (HERE)
    push de                    ; stash the length byte's own address --
                               ; its value isn't known until the scan
                               ; below finishes
    inc  de                    ; leave room for it; string chars start
                               ; right after
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
    jr   z, .scandone          ; ran off the end of source with no
                               ; closing '"' -- safety net, not
                               ; expected in well-formed source
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
    ret

DICT_LATEST_INIT_DOTQUOTE EQU H_DOTQUOTE   ; head of the dictionary
                                            ; once this file's own word
                                            ; is included

    ENDIF
