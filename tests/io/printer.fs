\ LPRINT fills the print-line buffer with the glyph rows; LLIST returns with the stack untouched
: G 8 0 DO OVER C@ . SWAP OVER + SWAP LOOP 2DROP ;
S" AB" LPRINT
{PRINT_LINE_BUF} 32 G                             \ expect: 32 80 136 136 248 136 136 0
{PRINT_LINE_BUF} 2 + 32 G                             \ expect: 0 0 0 0 0 0 0 0
\ the font glyph of "A" (FONT_TABLE + (65 - 32) * 8), which the buffer column 0 must equal
{FONT_TABLE} 264 + 1 G                 \ expect: 32 80 136 136 248 136 136 0
S" 0123456789012345678901234567890123456789" LPRINT
{PRINT_LINE_BUF} 32 G                             \ expect: 112 136 8 16 32 64 248 0
: FOO 1 ;
1 2 LLIST . .                          \ expect: 2 1
