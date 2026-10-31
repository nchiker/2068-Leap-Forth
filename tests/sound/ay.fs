\ BEEP pitch, duration and register hygiene, and SOUND, read back from the AY registers (select 245, data 246)
: AY@ 245 OUT 246 IN ;
: AY! 245 OUT 246 OUT ;
: PER 0 AY@ 1 AY@ 256 * + ;
CREATE TB
4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 ,
4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 , 4009 ,
4009 , 4009 , 3784 , 3572 , 3371 , 3182 , 3003 , 2835 , 2676 , 2526 ,
2384 , 2250 , 2124 , 2005 , 1892 , 1786 , 1686 , 1591 , 1502 , 1417 ,
1338 , 1263 , 1192 , 1125 , 1062 , 1002 , 946 , 893 , 843 , 796 ,
751 , 709 , 669 , 631 , 596 , 563 , 531 , 501 , 473 , 446 ,
421 , 398 , 375 , 354 , 334 , 316 , 298 , 281 , 265 , 251 ,
237 , 223 , 211 , 199 , 188 , 177 , 167 , 158 , 149 , 141 ,
133 , 125 , 118 , 112 , 105 , 99 , 94 , 89 , 84 , 79 ,
74 , 70 , 66 , 63 , 59 , 56 , 53 , 50 , 47 , 44 ,
42 , 39 , 37 , 35 , 33 , 31 , 30 , 28 , 26 , 25 ,
23 , 22 , 21 , 20 , 19 , 18 , 17 , 16 , 15 , 14 ,
13 , 12 , 12 , 11 , 10 , 10 , 9 , 9 , 8 , 8 ,
: CHK DUP 60 + 2 * TB + @ SWAP 0.02 BEEP PER SWAP - ABS 2 < ;
: OK8 8 AY@ 0 = 7 AY@ 9 AND 8 = AND ;
: ALL 70 -60 DO I CHK OK8 AND 0= IF I . THEN LOOP ;
\ every note from -60 to 69 is within one count of the ideal period, channel A silent and in tone mode afterwards
ALL
CLS 0 0 AT-XY
0 0.02 BEEP PER 421 - ABS 2 < .          \ expect: -1
12 0.02 BEEP PER 211 - ABS 2 < .         \ expect: -1
\ the time BEEP takes, in 50 Hz frames (typed in a definition so that parsing the line does not add frames)
: BT {FRAMES} @ 0 BEEP {FRAMES} @ SWAP - ;
0.5 BT .                                 \ expect: 30
0.1 BT .                                 \ expect: 6
0.0166667 BT .                           \ expect: 1
0.009 BT .                               \ expect: 1
2.0 BT .                                 \ expect: 120
CLS 0 0 AT-XY
\ under half a frame waits for nothing (the count may be off by the one tick the call itself can straddle)
0.0 BT 2 < .                             \ expect: -1
0.001 BT 2 < .                           \ expect: -1
-0.5 BT 2 < .                            \ expect: -1
0.008 BT 2 < .                           \ expect: -1
\ an out-of-range pitch plays nothing and does not wait
: OOR 18 0 AY! 3 1 AY! {FRAMES} @ SWAP BEEP {FRAMES} @ SWAP - 2 < . 0 AY@ . 1 AY@ . ;
0.5 70 OOR                               \ expect: -1 18 3
0.5 -61 OOR                              \ expect: -1 18 3
\ the other mixer bits and channels B and C are left alone
: SETUP 7 AY! 165 2 AY! 5 3 AY! 90 4 AY! 10 5 AY! 7 9 AY! 3 10 AY! ;
: AFTER 0 0.02 BEEP 7 AY@ . 2 AY@ . 3 AY@ . 4 AY@ . 5 AY@ . 9 AY@ . 10 AY@ . ;
255 SETUP AFTER                          \ expect: 254 165 5 90 10 7 3
0 SETUP AFTER                            \ expect: 8 165 5 90 10 7 3
65 SETUP AFTER                           \ expect: 72 165 5 90 10 7 3
254 SETUP AFTER                          \ expect: 254 165 5 90 10 7 3
\ the data and float stacks are balanced
4242 0 0.02 BEEP . FDEPTH .              \ expect: 4242 0
CLS 0 0 AT-XY
4242 8 15 SOUND .                        \ expect: 4242
8 15 SOUND 8 AY@ .                       \ expect: 15
4242 0 200 SOUND .                       \ expect: 4242
0 200 SOUND 0 AY@ .                      \ expect: 200
4242 17 200 SOUND .                      \ expect: 4242
0 99 SOUND 17 200 SOUND 0 AY@ .          \ expect: 99
