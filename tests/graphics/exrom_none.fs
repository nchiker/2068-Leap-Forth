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
