\ EMIT . ." and AT-XY: what they draw and where the print position is left (PRINT_COL 34761, PRINT_ROW 34760)
: ANY? 0 SWAP 8 0 DO DUP C@ ROT OR SWAP 256 + LOOP DROP ;
CLS 0 0 AT-XY
65 EMIT {PRINT_COL} C@ {PRINT_ROW} C@ 16416 ANY? 0= . . .   \ expect: A0 1 1
123 . {PRINT_COL} C@ .                         \ expect: 123 4
-32768 . {PRINT_COL} C@ .                      \ expect: -32768 7
0 . {PRINT_COL} C@ .                           \ expect: 0 2
: X33 33 0 DO 88 EMIT LOOP ;
CLS 0 0 AT-XY
X33 {PRINT_COL} C@ {PRINT_ROW} C@ . .                \ expect: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX|X2 1
: GREET ." HI" ;
: EMPTY ." " ;
: DESCRIBE IF ." pos" ELSE ." neg" THEN ;
CLS 0 0 AT-XY
GREET {PRINT_COL} C@ {PRINT_ROW} C@ . .              \ expect: HI1 2
EMPTY {PRINT_COL} C@ {PRINT_ROW} C@ . .              \ expect: 2 0
5 DESCRIBE {PRINT_COL} C@ {PRINT_ROW} C@ . .         \ expect: pos3 3
0 DESCRIBE {PRINT_COL} C@ {PRINT_ROW} C@ . .         \ expect: neg4 3
CLS 0 0 AT-XY
10 5 AT-XY 65 EMIT {PRINT_COL} C@ {PRINT_ROW} C@ 16554 ANY? 0= . . .   \ expect-end: A0 5 11
CLS 0 0 AT-XY
31 10 AT-XY 65 EMIT 66 EMIT {PRINT_COL} C@ {PRINT_ROW} C@ . .   \ expect-end: A|B11 1
