\ exrom: stock
\ with no graphics EXROM fitted the EXROM words draw nothing, consume their arguments and the console goes on
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
CLS 0 18 AT-XY 20 20 60 60 RECT        \ draws
20 20 PX . 40 40 PX . 60 60 PX .       \ expect: 0 0 0
DROP                                   \ expect: STACK?
CLS 0 18 AT-XY 100 40 140 40 100 80 3 POLYGON-FILL     \ draws
110 50 PX .                            \ expect: 0
DROP                                   \ expect: STACK?
\ each EXROM word says NO EXROM (as EDIT does), takes its arguments, and the line goes on
CLS 20 20 60 60 RECT 1 .               \ expect: NO EXROM|1
CLS 9 9 FILL 100 100 30 CIRCLE 2 .     \ expect: NO EXROM|NO EXROM|2
CLS 9 9 50 9 9 50 3 POLYGON 3 .        \ expect: NO EXROM|3
CLS 9 9 50 9 9 50 3 POLYGON-FILL 4 .   \ expect: NO EXROM|4
CLS 0 5 5 SPRITE-DEFINE 0 5 5 SPRITE-SHOW 0 SPRITE-HIDE  \ expect: NO EXROM|NO EXROM|NO EXROM
CLS EDIT FOO 5 .                       \ expect: NO EXROM|5
