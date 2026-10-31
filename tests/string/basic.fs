\ S" TYPE STRING PLACE COUNT LEN VAL
: GREET S" HI THERE" TYPE ;
GREET SPACE                              \ expect: HI THERE
10 STRING BUF
BUF LEN .                                \ expect: 0
S" HELLO" BUF PLACE
BUF LEN .                                \ expect: 5
BUF COUNT TYPE SPACE                    \ expect: HELLO
S" 1234" VAL . S" -17" VAL . S" " VAL .  \ expect: 1234 -17 0
\ an empty string leaves only its 0
7 S" " VAL . .                         \ expect: 0 7
