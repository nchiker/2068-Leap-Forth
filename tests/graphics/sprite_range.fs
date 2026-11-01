\ SPRITE-DEFINE and SPRITE-SHOW refuse a position whose 2x2 cells are not all on the screen (row 0-22, col 0-30)
\ and a value above 255 (they took its low byte: row 258 was row 2), as they refuse a slot above 3
: AT 22528 + SWAP 32 * + C@ ;
: RED 2 INK 0 SWAP AT-XY ." AB" 0 INK ;
CLS 2 RED 0 258 0 SPRITE-DEFINE 0 10 0 SPRITE-SHOW 10 0 AT .       \ expect-end: 56
CLS 3 RED 31 3 AT-XY 2 INK 88 EMIT 0 INK 1 3 31 SPRITE-DEFINE 1 10 4 SPRITE-SHOW 10 4 AT .  \ expect-end: 56
CLS 4 RED 2 4 0 SPRITE-DEFINE 2 23 0 SPRITE-SHOW 2 10 0 SPRITE-SHOW 10 0 AT .  \ expect-end: 58
