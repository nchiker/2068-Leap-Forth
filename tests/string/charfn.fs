\ string functions CHR STR CODE UPPER LOWER LEFT RIGHT SEARCH on text kept in the dictionary
: HW S" HELLO WORLD" ;
HW DROP CONSTANT A1
: WD S" WORLD" ;
: XY S" XYZ" ;
: BUF S" Hello!" ;
65 CHR . C@ .                          \ expect: 1 65
HW CODE .                              \ expect: 72
42 STR 2DUP TYPE SPACE . DROP          \ expect: 42 2
-5 STR 2DUP TYPE SPACE . DROP          \ expect: -5 2
0 STR 2DUP TYPE SPACE . DROP           \ expect: 0 1
\ UPPER and LOWER work in place; the second runs on the already upper-cased text
BUF UPPER TYPE SPACE                   \ expect: HELLO!
BUF LOWER TYPE SPACE                   \ expect: hello!
HW 5 LEFT TYPE SPACE                   \ expect: HELLO
HW 20 LEFT . DROP                      \ expect: 11
HW 5 RIGHT TYPE SPACE                  \ expect: WORLD
HW 20 RIGHT . A1 - .                   \ expect: 11 0
HW 256 LEFT . DROP HW 256 RIGHT . A1 - .   \ expect: 11 11 0
\ SEARCH ( addr1 len1 addr2 len2 -- addr3 len3 flag ): found, not found, needle longer than the haystack
HW WD SEARCH . . A1 - .                \ expect: -1 5 6
HW DROP 5 XY SEARCH . . A1 - .         \ expect: 0 5 0
XY HW SEARCH . . XY DROP - .           \ expect: 0 3 0
CLS 0 0 AT-XY
\ a buffer of 300 bytes made by hand: UPPER, LOWER and SEARCH take the whole 16-bit length
CREATE B3 300 ALLOT
: FB 300 0 DO DUP B3 I + C! LOOP DROP ;
: NE S" XY" ;
: NZ S" XZ" ;
97 FB B3 300 UPPER 2DROP B3 C@ . B3 299 + C@ .    \ expect: 65 65
65 FB B3 300 LOWER 2DROP B3 C@ . B3 299 + C@ .    \ expect: 97 97
88 B3 298 + C! 89 B3 299 + C!
B3 300 NE SEARCH . . B3 - .              \ expect: -1 2 298
B3 300 NZ SEARCH . . B3 - .              \ expect: 0 300 0
B3 300 B3 300 SEARCH . . B3 - .          \ expect: -1 300 0
