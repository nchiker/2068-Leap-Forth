\ CR, SPACE and SPACES move the print position and EMIT draws at it (read back from the bitmap)
: CELLOR 0 SWAP 8 0 DO DUP C@ ROT OR SWAP 256 + LOOP DROP ;
: Z? CELLOR 0= . ;
CLS 0 0 AT-XY SPACE 88 EMIT CR 3 SPACES 89 EMIT      \ draws
16384 Z? 16385 Z? 16416 Z? 16419 Z?    \ expect: -1 0 -1 0
