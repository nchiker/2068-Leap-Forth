\ CIRCLE (poles, a centre off the left edge, radius 0 and a negative radius) and FILL of a circle's inside
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
: ATT 32 * + 22528 + C@ ;
CLS 0 18 AT-XY 150 100 20 CIRCLE       \ draws
150 80 PX . 150 120 PX . 130 100 PX . 170 100 PX .      \ expect: -1 -1 -1 -1
150 100 PX . 150 90 PX .               \ expect: 0 0
\ the circle closes its inside: FILL (ink 2) colours the cells within it and not the corner, which keeps the boot ink 0
CLS 0 18 AT-XY 50 50 20 CIRCLE 2 INK 50 50 FILL        \ draws
50 50 PX . 6 6 ATT 7 AND . 0 0 PX .    \ expect: -1 2 0
0 0 ATT 7 AND .                        \ expect: 0
CLS 0 18 AT-XY -10 50 30 CIRCLE        \ draws
20 50 PX . 246 50 PX .                 \ expect: -1 0
CLS 0 2 AT-XY 100 150 0 CIRCLE 100 170 -3 CIRCLE       \ draws
100 150 PX . 99 150 PX . 101 150 PX . 100 149 PX . 100 151 PX .       \ expect: -1 0 0 0 0
100 170 PX . 97 170 PX . 103 170 PX . 100 167 PX . 100 173 PX .       \ expect: 0 0 0 0 0
