; ============================================================================
; core/print.asm — EMIT and . (print)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's first header chains through DICT_CHAIN_POINT,
; same convention as core/control.asm/core/storage.asm/core/float.asm —
; see core/control.asm's own header for the full reasoning) and needs
; kernel/graphics/graphics.asm INCLUDEd alongside it.
;
; WHAT THIS ADDS:
;   EMIT ( char -- )   print one character at the current output
;                      position, advancing it (wrapping at column 32,
;                      scrolling at row 22 — see below)
;   .    ( n -- )      print n as a signed decimal number, followed by
;                      a space (the standard Forth convention, so
;                      consecutive `.`s read as space-separated numbers)
;
; OUTPUT POSITION: PRINT_ROW/PRINT_COL, own state, separate from
; core/editor.asm's EDIT_CURSOR (that's the INPUT line's cursor, on its
; own fixed row, EDIT_ROW = 23; this is where the NEXT character EMIT
; writes goes, anywhere in rows 0-22). Confining EMIT's own output to
; rows 0-22 means it can never overwrite the input line — reaching row
; 23 instead scrolls everything up one row (kernel/graphics's own
; GFX_SCROLL_TEXT_UP, built for exactly this row split) and continues
; at row 22. Both cells must be initialized by whatever ROM uses this
; file (0, 0 is the natural starting position) — this file doesn't
; assume a default, matching every other core/ file's own RAM-state
; convention (core/dict.asm's DSTACK_TOP, etc.).
;
; A CR CHARACTER ($0D) MOVES TO A NEW LINE rather than being printed as
; a glyph — the one piece of "control character" handling EMIT does;
; nothing else (tab, backspace, ...) is interpreted specially yet.
;
; `.` NEEDS AN UNSIGNED DIVIDE BY 10 that kernel/math doesn't provide
; (MATH_DIVIDE16 is signed, which would misread magnitudes above 32767
; — including the magnitude of -32768 itself, a real edge case this
; file's own UDIV10 gets right: negating $8000 in 16-bit two's
; complement gives back $8000, which is exactly 32768 read as
; unsigned — correct, not a coincidence, verified by hand before
; writing UDIV10 the way it's written below). UDIV10 is a private
; helper, not added to kernel/math, matching this project's practice of
; never modifying an inherited kernel/ file — kernel/math stays exactly
; as inherited.
; ============================================================================

    IFNDEF CORE_PRINT_ASM
    DEFINE CORE_PRINT_ASM

PRINT_ROW     EQU $87C8   ; 1 byte: next EMIT's row (0-22)
PRINT_COL     EQU $87C9   ; 1 byte: next EMIT's column (0-31)
EMIT_CHAR_TMP EQU $87CA   ; 1 byte: EMIT's own scratch (the character,
                          ; held across loading row/col into B/C)

; ============================================================================
; UDIV10 (internal, not a dictionary word) — HL = value (0-65535) ->
; HL = value/10, A = value MOD 10 (0-9). Classic 16-iteration
; shift-and-subtract restoring division, specialized for divisor 10.
; Destroys: AF, B
; ============================================================================
UDIV10:
    xor  a
    ld   b, 16
.loop:
    add  hl, hl
    rla
    cp   10
    jr   c, .skip
    sub  10
    inc  l
.skip:
    djnz .loop
    ret

; ============================================================================
; EMIT ( char -- )
; ============================================================================
H_EMIT:
    DW   DICT_CHAIN_POINT
    DB   4, "E", "M", "I", "T"
W_EMIT:
    call DPOP_HL
    ld   a, l
    cp   13                    ; CR: move to a new line instead of printing
    jr   z, .newline

    ld   (EMIT_CHAR_TMP), a    ; stash the character while B/C load row/col
    ld   a, (PRINT_ROW)
    ld   b, a
    ld   a, (PRINT_COL)
    ld   c, a
    ld   a, (EMIT_CHAR_TMP)
    call GFX_PUTCHAR            ; A=char, B=row, C=column
    jr   .advance

.newline:
    xor  a
    ld   (PRINT_COL), a
    jr   .nextrow

.advance:
    ld   a, (PRINT_COL)
    inc  a
    cp   32
    jr   c, .storecol
    xor  a
    ld   (PRINT_COL), a
    jr   .nextrow
.storecol:
    ld   (PRINT_COL), a
    ret

.nextrow:
    ld   a, (PRINT_ROW)
    inc  a
    cp   23                     ; row 23 is core/editor.asm's own
                                ; EDIT_ROW -- EMIT's output never goes
                                ; there
    jr   c, .storerow
    call GFX_SCROLL_TEXT_UP
    ld   b, 22
    call GFX_CLEAR_ROW           ; GFX_SCROLL_TEXT_UP's own contract:
                                 ; "row 22 left for the caller to draw"
    ld   a, 22
.storerow:
    ld   (PRINT_ROW), a
    ret

; ============================================================================
; . ( n -- )
; Prints n as a signed decimal number, followed by a space.
; ============================================================================
H_DOT:
    DW   H_EMIT
    DB   1, "."
W_DOT:
    call DPOP_HL
    ld   a, h
    and  $80
    jr   z, .positive
    push hl
    ld   hl, "-"
    call DPUSH_HL
    call W_EMIT
    pop  hl
    xor  a                       ; negate hl -- correct even for $8000,
    sub  l                       ; see this file's own header
    ld   l, a
    ld   a, 0
    sbc  a, h
    ld   h, a
.positive:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   hl, "0"
    call DPUSH_HL
    call W_EMIT
    jr   .donedigits
.hasdigits:
    ld   c, 0                    ; digit count, collected on the Z80
                                 ; hardware stack below -- UDIV10 never
                                 ; touches C, confirmed by reading it
.divloop:
    ld   a, h
    or   l
    jr   z, .printdigits
    call UDIV10                  ; hl = hl/10, a = digit (0-9)
    push af
    inc  c
    jr   .divloop
.printdigits:
    ld   b, c
.printloop:
    pop  af
    add  a, "0"
    ld   l, a
    ld   h, 0
    push bc                       ; W_EMIT (via GFX_PUTCHAR) destroys BC
                                  ; -- preserve our own djnz counter
                                  ; around the call
    call DPUSH_HL
    call W_EMIT
    pop  bc
    djnz .printloop
.donedigits:
    ld   hl, " "
    call DPUSH_HL
    call W_EMIT
    ret

DICT_LATEST_INIT_PRINT EQU H_DOT   ; head of the dictionary once this
                                   ; file's own words are included

    ENDIF
