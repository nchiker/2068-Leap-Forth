\ POLYGON draws an outline and refuses fewer than three vertices; POLYGON-FILL fills even-odd (pixels read from the bitmap)
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
CLS 0 18 AT-XY 100 40 140 40 100 80 3 POLYGON     \ draws
120 40 PX . 100 60 PX . 120 60 PX . 10 10 PX .      \ expect: -1 -1 -1 0
110 50 PX .                            \ expect: 0
\ two vertices are refused after popping only the count, so the four coordinates stay on the stack
CLS 0 18 AT-XY 10 10 20 20 2 POLYGON   \ draws
15 15 PX . . . . .                     \ expect: 0 20 20 10 10
CLS 0 18 AT-XY 100 40 140 40 100 80 3 POLYGON-FILL     \ draws
110 50 PX . 135 50 PX . 10 10 PX . 105 75 PX .       \ expect: -1 0 0 0
CLS 0 18 AT-XY 50 50 90 70 50 90 65 70 4 POLYGON-FILL  \ draws
70 70 PX . 80 70 PX . 52 52 PX . 55 60 PX . 55 80 PX .    \ expect: -1 -1 -1 0 0
