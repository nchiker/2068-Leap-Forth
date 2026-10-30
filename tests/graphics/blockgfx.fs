\ block graphics 128-143: EMIT builds each glyph from the code's four low bits (top four pixel rows from bits 0-1, bottom four from bits 2-3)
\ BAD draws code 128+n and counts the bytes of its glyph scratch (33545) that differ from that rule
: TOP DUP 2 AND IF 240 ELSE 0 THEN SWAP 1 AND IF 15 ELSE 0 THEN OR ;
: BOT 2 / 2 / TOP ;
: BAD DUP 128 + EMIT 0 4 0 DO OVER TOP {BLOCK_GFX_SCRATCH} I + C@ XOR OR OVER BOT {BLOCK_GFX_SCRATCH} 4 + I + C@ XOR OR LOOP SWAP DROP ;
\ ascending then descending, so a glyph left over from the previous code cannot pass
: BGALL 0 16 0 DO I BAD OR LOOP ;
: BRALL 0 16 0 DO 15 I - BAD OR LOOP ;
CLS 0 2 AT-XY BGALL                    \ draws
.                                      \ expect: 0
CLS 0 2 AT-XY BRALL                    \ draws
.                                      \ expect: 0
\ spot checks with literal values: codes 129, 132, 138, 143
129 EMIT                               \ draws
{BLOCK_GFX_SCRATCH} C@ . {BLOCK_GFX_SCRATCH} 4 + C@ .                  \ expect: 15 0
132 EMIT                               \ draws
{BLOCK_GFX_SCRATCH} C@ . {BLOCK_GFX_SCRATCH} 4 + C@ .                  \ expect: 0 15
138 EMIT                               \ draws
{BLOCK_GFX_SCRATCH} C@ . {BLOCK_GFX_SCRATCH} 4 + C@ .                  \ expect: 240 240
143 EMIT                               \ draws
{BLOCK_GFX_SCRATCH} C@ . {BLOCK_GFX_SCRATCH} 4 + C@ .                  \ expect: 255 255
\ and the glyph reaches the screen bitmap
CLS 0 0 AT-XY 139 EMIT                 \ draws
16384 C@ . 16896 C@ . 17152 C@ . 17408 C@ . 18176 C@ .       \ expect: 255 255 255 240 240
