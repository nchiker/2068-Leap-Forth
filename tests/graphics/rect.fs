\ RECT fills the rectangle between two corners given in either order (pixels read from the bitmap; text goes to row 18 and below)
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
CLS 0 18 AT-XY 20 20 60 60 RECT        \ draws
40 40 PX . 5 5 PX .                    \ expect: -1 0
20 20 PX . 60 60 PX . 61 61 PX . 19 40 PX .     \ expect: -1 -1 0 0
CLS 0 18 AT-XY 150 120 110 90 RECT     \ draws
130 105 PX . 111 91 PX .               \ expect: -1 -1
\ the corners are signed cells (as LINE's and CIRCLE's): the part on the screen is drawn, a rectangle wholly off it
\ draws nothing (they took their low bytes: -5 was 251, 300 was 44)
CLS 0 18 AT-XY -5 30 3 40 RECT         \ draws
0 35 PX . 3 35 PX . 4 35 PX . 251 35 PX .        \ expect: -1 -1 0 0
CLS 0 18 AT-XY 300 30 310 40 RECT      \ draws
44 35 PX . 54 35 PX . 255 35 PX .      \ expect: 0 0 0
CLS 0 18 AT-XY 10 170 20 300 RECT      \ draws
15 175 PX . 15 169 PX . 15 50 PX .     \ expect: -1 0 0
CLS 0 18 AT-XY 10 -400 20 -1 RECT      \ draws
15 0 PX . 15 100 PX .                  \ expect: 0 0
