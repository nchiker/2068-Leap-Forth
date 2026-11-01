\ the glyphs of g, p and q have their bowl on the x-height (rows 2-5) and the descender in rows 6-7, as y does;
\ before Leap-C's delta D24 they sat a row high and p read as P (nchiker/2068-Leap-Forth#18)
: ROWS 8 0 DO DUP I + C@ . LOOP DROP ;
: GLYPH 32 - 8 * {FONT_TABLE} + ;
CHAR p GLYPH ROWS                        \ expect: 0 0 240 136 136 240 128 128
CHAR q GLYPH ROWS                        \ expect: 0 0 120 136 136 120 8 8
CHAR g GLYPH ROWS                        \ expect: 0 0 120 136 136 120 8 112
CHAR y GLYPH ROWS                        \ expect: 0 0 136 136 136 120 8 112
