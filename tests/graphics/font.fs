\ the font is printable ASCII in code order: [ \ ] ^ ` { | } ~ have glyphs (they drew as spaces before)
91 EMIT 92 EMIT 93 EMIT 94 EMIT 96 EMIT 123 EMIT 124 EMIT 125 EMIT 126 EMIT          \ expect: [\]^`{|}~
\ the glyph of a code is FONT_TABLE + (code - 32) * 8
: G 8 0 DO DUP C@ . 1+ LOOP DROP ;
{FONT_TABLE} G                         \ expect: 0 0 0 0 0 0 0 0
{FONT_TABLE} 264 + G                   \ expect: 32 80 136 136 248 136 136 0
{FONT_TABLE} 752 + G                   \ expect: 0 0 64 168 16 0 0 0
\ 1 has a flag and a full base, l a tail and no base (they differed in two pixels, so l.0 read as 1.0)
{FONT_TABLE} 136 + G                   \ expect: 32 96 160 32 32 32 248 0
{FONT_TABLE} 608 + G                   \ expect: 96 32 32 32 32 32 24 0
\ a code with no glyph draws a space: below 32, 127, 165 and up
CLS 0 0 AT-XY 65 EMIT 1 EMIT 127 EMIT 165 EMIT 255 EMIT 66 EMIT          \ expect: A    B
\ EMIT keeps the INK and PAPER attribute of each cell it draws, in every third of the screen
CLS 0 0 AT-XY 2 INK 65 EMIT 0 8 AT-XY 66 EMIT 31 16 AT-XY 67 EMIT 4 INK          \ draws
22528 C@ . 22784 C@ . 23071 C@ . 22529 C@ .          \ expect: 66 66 66 68
