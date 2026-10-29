; ============================================================================
; kernel/graphics/font.asm -- the font (FONT_TABLE), split out of kernel/graphics/graphics.asm so a ROM can place it
; elsewhere: graphics.asm includes it unless the ROM defines FONT_PLACED_LATER and includes this file itself.
; rom/forth_boot.asm does, after kernel/storage, so that the font covers $11F8 (see the ASSERT there).
; ============================================================================

; ---- font: space, 0-9, A-Z (37 glyphs, 8 bytes each). See file header
; re: confidence level — designed and visually reviewed, not from a
; recalled ROM dump, needs YOUR visual confirmation once assembled. ----
FONT_TABLE:
    ; ' '
    DB   $00, $00, $00, $00, $00, $00, $00, $00
    ; '0'
    DB   $70, $88, $98, $A8, $C8, $88, $70, $00
    ; '1'
    DB   $20, $60, $20, $20, $20, $20, $70, $00
    ; '2'
    DB   $70, $88, $08, $10, $20, $40, $F8, $00
    ; '3'
    DB   $F0, $08, $10, $30, $08, $88, $70, $00
    ; '4'
    DB   $10, $30, $50, $90, $F8, $10, $10, $00
    ; '5'
    DB   $F8, $80, $F0, $08, $08, $88, $70, $00
    ; '6'
    DB   $30, $40, $80, $F0, $88, $88, $70, $00
    ; '7'
    DB   $F8, $08, $10, $20, $40, $40, $40, $00
    ; '8'
    DB   $70, $88, $88, $70, $88, $88, $70, $00
    ; '9'
    DB   $70, $88, $88, $78, $08, $10, $60, $00
    ; 'A'
    DB   $20, $50, $88, $88, $F8, $88, $88, $00
    ; 'B'
    DB   $F0, $88, $88, $F0, $88, $88, $F0, $00
    ; 'C'
    DB   $70, $88, $80, $80, $80, $88, $70, $00
    ; 'D'
    DB   $F0, $88, $88, $88, $88, $88, $F0, $00
    ; 'E'
    DB   $F8, $80, $80, $F0, $80, $80, $F8, $00
    ; 'F'
    DB   $F8, $80, $80, $F0, $80, $80, $80, $00
    ; 'G'
    DB   $70, $88, $80, $B8, $88, $88, $70, $00
    ; 'H'
    DB   $88, $88, $88, $F8, $88, $88, $88, $00
    ; 'I'
    DB   $70, $20, $20, $20, $20, $20, $70, $00
    ; 'J'
    DB   $08, $08, $08, $08, $08, $88, $70, $00
    ; 'K'
    DB   $88, $90, $A0, $C0, $A0, $90, $88, $00
    ; 'L'
    DB   $80, $80, $80, $80, $80, $80, $F8, $00
    ; 'M'
    DB   $88, $D8, $A8, $88, $88, $88, $88, $00
    ; 'N'
    DB   $88, $C8, $A8, $98, $88, $88, $88, $00
    ; 'O'
    DB   $70, $88, $88, $88, $88, $88, $70, $00
    ; 'P'
    DB   $F0, $88, $88, $F0, $80, $80, $80, $00
    ; 'Q'
    DB   $70, $88, $88, $88, $A8, $90, $68, $00
    ; 'R'
    DB   $F0, $88, $88, $F0, $A0, $90, $88, $00
    ; 'S'
    DB   $70, $88, $80, $70, $08, $88, $70, $00
    ; 'T'
    DB   $F8, $20, $20, $20, $20, $20, $20, $00
    ; 'U'
    DB   $88, $88, $88, $88, $88, $88, $70, $00
    ; 'V'
    DB   $88, $88, $88, $88, $88, $50, $20, $00
    ; 'W'
    DB   $88, $88, $88, $A8, $A8, $D8, $88, $00
    ; 'X'
    DB   $88, $50, $20, $20, $20, $50, $88, $00
    ; 'Y'
    DB   $88, $50, $20, $20, $20, $20, $20, $00
    ; 'Z'
    DB   $F8, $08, $10, $20, $40, $80, $F8, $00
    ; ---- lowercase a-z appended below, same design/review discipline
    ; as the uppercase set above ----
    ; 'a'
    DB   $00, $00, $70, $08, $78, $88, $78, $00
    ; 'b'
    DB   $80, $80, $B0, $C8, $88, $88, $F0, $00
    ; 'c'
    DB   $00, $00, $70, $88, $80, $88, $70, $00
    ; 'd'
    DB   $08, $08, $68, $98, $88, $88, $78, $00
    ; 'e'
    DB   $00, $00, $70, $88, $F8, $80, $70, $00
    ; 'f'
    DB   $30, $40, $F0, $40, $40, $40, $40, $00
    ; 'g'
    DB   $00, $78, $88, $88, $78, $08, $70, $00
    ; 'h'
    DB   $80, $80, $B0, $C8, $88, $88, $88, $00
    ; 'i'
    DB   $20, $00, $60, $20, $20, $20, $70, $00
    ; 'j'
    DB   $10, $00, $30, $10, $10, $10, $90, $60
    ; 'k'
    DB   $80, $80, $90, $A0, $C0, $A0, $90, $00
    ; 'l'
    DB   $60, $20, $20, $20, $20, $20, $70, $00
    ; 'm'
    DB   $00, $00, $D0, $A8, $A8, $88, $88, $00
    ; 'n'
    DB   $00, $00, $B0, $C8, $88, $88, $88, $00
    ; 'o'
    DB   $00, $00, $70, $88, $88, $88, $70, $00
    ; 'p'
    DB   $00, $F0, $88, $88, $F0, $80, $80, $80
    ; 'q'
    DB   $00, $78, $88, $88, $78, $08, $08, $08
    ; 'r'
    DB   $00, $00, $B0, $C8, $80, $80, $80, $00
    ; 's'
    DB   $00, $00, $78, $80, $70, $08, $F0, $00
    ; 't'
    DB   $40, $40, $F0, $40, $40, $48, $30, $00
    ; 'u'
    DB   $00, $00, $88, $88, $88, $98, $68, $00
    ; 'v'
    DB   $00, $00, $88, $88, $88, $50, $20, $00
    ; 'w'
    DB   $00, $00, $88, $88, $A8, $A8, $50, $00
    ; 'x'
    DB   $00, $00, $88, $50, $20, $50, $88, $00
    ; 'y'
    DB   $00, $00, $88, $88, $88, $78, $08, $70
    ; 'z'
    DB   $00, $00, $F8, $10, $20, $40, $F8, $00
    ; ---- punctuation, added as needed rather than up front — '"' was
    ; needed the moment PRINT "..." string literals became typeable,
    ; see kernel/io's SYMBOL SHIFT+P addition ----
    ; '"'
    DB   $50, $50, $00, $00, $00, $00, $00, $00
    ; ---- more punctuation: the confirmed-confidence subset of
    ; SYMBOL SHIFT's table (see kernel/io.asm's header — the real
    ; table is more complex than this, some keys give BASIC keyword
    ; tokens rather than symbols, some differ between plain SYMBOL
    ; SHIFT and a separate "extended mode"; only what's independently
    ; confirmed is implemented) ----
    ; '!'
    DB   $20, $20, $20, $20, $20, $00, $20, $00
    ; '@'
    DB   $70, $88, $B0, $B0, $80, $88, $70, $00
    ; '#'
    DB   $50, $50, $F8, $50, $F8, $50, $50, $00
    ; '$'
    DB   $20, $78, $A0, $70, $28, $F0, $20, $00
    ; '%'
    DB   $88, $10, $20, $20, $40, $88, $00, $00
    ; '&'
    DB   $60, $90, $60, $68, $90, $98, $68, $00
    ; '''
    DB   $20, $20, $00, $00, $00, $00, $00, $00
    ; '('
    DB   $10, $20, $40, $40, $40, $20, $10, $00
    ; ')'
    DB   $40, $20, $10, $10, $10, $20, $40, $00
    ; '_'
    DB   $00, $00, $00, $00, $00, $00, $F8, $00
    ; ':'
    DB   $00, $20, $00, $00, $20, $00, $00, $00
    ; '.'
    DB   $00, $00, $00, $00, $00, $00, $20, $00
    ; ','
    DB   $00, $00, $00, $00, $00, $20, $20, $40
    ; '='
    DB   $00, $00, $F8, $00, $F8, $00, $00, $00
    ; '+'
    DB   $00, $20, $20, $F8, $20, $20, $00, $00
    ; '-'
    DB   $00, $00, $00, $F8, $00, $00, $00, $00
    ; ';'
    DB   $00, $20, $00, $00, $20, $20, $40, $00
    ; '/' — diagonal stroke, lower-left to upper-right. Designed and
    ; visually reviewed as ASCII art before committing (see this
    ; project's established discipline for glyphs — needed once V=/
    ; was added for basic/'s division operator)
    DB   $00, $04, $08, $10, $20, $40, $00, $00
    ; '*' — vertical spine + diagonal rays converging at center,
    ; six-pointed asterisk. Same review discipline (needed once B=*
    ; was added for basic/'s multiplication operator)
    DB   $00, $10, $54, $38, $54, $10, $00, $00
    ; '<' — simple angle-bracket chevron, apex pointing left, single-
    ; pixel diagonal strokes converging on the left edge (column 0)
    ; and opening back out to column 3 top/bottom — stays within the
    ; same column range ($80-$08) every letter/digit glyph already
    ; uses, unlike '/' which intentionally reaches further right.
    ; Needed once basic/'s new IF condition relational operators
    ; (kernel/io's SYMBOL SHIFT+R) made '<' a real, typeable character
    ; rather than only usable via LOAD/hand-edited program text.
    ; Visually reviewed as ASCII art before committing, same discipline
    ; as every other glyph here.
    DB   $10, $20, $40, $80, $40, $20, $10, $00
    ; '>' — exact horizontal mirror of '<' within the same column
    ; range, apex pointing right toward column 4 instead of column 0.
    ; Needed alongside '<' for the same reason (kernel/io's SYMBOL
    ; SHIFT+T).
    DB   $40, $20, $10, $08, $10, $20, $40, $00
    ; '?' — top hook reuses '2''s exact top-curve shape (rows 0-2:
    ; arc, then right-hand downstroke), tapering to a single point at
    ; row 4 instead of '2''s full-width bottom bar, then a blank row
    ; and a centered dot — same gap-then-dot closing shape already
    ; established by '!' elsewhere in this table. Designed and
    ; visually reviewed as ASCII art before committing, same
    ; discipline as every other glyph here — not transcribed from any
    ; real ROM's font. Needed once kernel/io's SYMBOL SHIFT+C mapping
    ; was added (see that table's header) — mapping and glyph always
    ; ship together per this project's established rule.
    DB   $70, $88, $08, $10, $20, $00, $20, $00

FONT_TABLE_END:
