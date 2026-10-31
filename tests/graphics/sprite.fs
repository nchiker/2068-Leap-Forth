\ SPRITE-DEFINE captures a 2x2-cell picture, SPRITE-SHOW draws it elsewhere, SPRITE-HIDE restores the background
: MASK 128 SWAP BEGIN DUP WHILE SWAP 2 / SWAP 1- REPEAT DROP ;
: ADR DUP 192 AND 32 * OVER 7 AND 256 * + SWAP 56 AND 4 * + SWAP 8 / + 16384 + ;
: PX 2DUP ADR C@ ROT 7 AND MASK AND SWAP DROP 0= 0= ;
: ATT 32 * + 22528 + C@ ;
\ capture a 16x16 box in ink 2 at row 5 col 5, clear the screen, show it at row 10 col 10 (pixel 80,80)
: S1 CLS 2 INK 40 40 55 55 RECT 0 5 5 SPRITE-DEFINE 0 INK CLS 0 13 AT-XY 0 10 10 SPRITE-SHOW ;
S1                                     \ draws
85 85 PX . 10 10 ATT 7 AND . 100 100 PX .      \ expect: -1 2 0
0 SPRITE-HIDE                          \ draws
85 85 PX .                             \ expect: 0
\ a second SHOW of a shown sprite is refused: the HIDE after it must still find a clean background
0 10 10 SPRITE-SHOW 0 10 10 SPRITE-SHOW 0 SPRITE-HIDE      \ draws
85 85 PX .                             \ expect: 0
\ hiding a slot that was never defined does nothing; the shown sprite stays
0 10 10 SPRITE-SHOW 1 SPRITE-HIDE      \ draws
85 85 PX .                             \ expect: -1
