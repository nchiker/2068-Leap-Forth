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
