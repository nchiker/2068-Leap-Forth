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
\ a corner off the screen is moved to the nearest edge, as 2068-Leap-C's draw() and box() do (it took the low byte:
\ -20 was x 236); a count above 255 is refused (259 was 3)
CLS 0 18 AT-XY -20 10 40 10 40 50 3 POLYGON        \ draws
20 10 PX . 100 10 PX . 0 10 PX .                   \ expect: -1 0 -1
CLS 0 18 AT-XY -20 10 40 10 40 50 3 POLYGON-FILL   \ draws
30 15 PX . 100 12 PX .                             \ expect: -1 0
CLS 0 18 AT-XY 10 -50 60 -50 35 30 3 POLYGON-FILL  \ draws
35 5 PX . 35 40 PX .                               \ expect: -1 0
CLS 0 18 AT-XY 10 10 20 20 30 10 259 POLYGON      \ draws
15 15 PX . . . . . . .                             \ expect: 0 10 30 20 20 10 10
