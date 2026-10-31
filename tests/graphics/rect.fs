\ RECT fills the rectangle between two corners given in either order (pixels read from the bitmap; text goes to row 18 and below)
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
CLS 0 18 AT-XY 20 20 60 60 RECT        \ draws
40 40 PX . 5 5 PX .                    \ expect: -1 0
20 20 PX . 60 60 PX . 61 61 PX . 19 40 PX .     \ expect: -1 -1 0 0
CLS 0 18 AT-XY 150 120 110 90 RECT     \ draws
130 105 PX . 111 91 PX .               \ expect: -1 -1
