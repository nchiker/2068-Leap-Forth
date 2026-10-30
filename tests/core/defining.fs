\ CREATE, DOES> and IMMEDIATE
: T1 CREATE 1234 , ;
T1 T1FOO
T1FOO @ .                              \ expect: 1234
: CONST CREATE , DOES> @ ;
5 CONST FIVE
FIVE .                                 \ expect: 5
7 CONST SEVEN
SEVEN .                                \ expect: 7
FIVE .                                 \ expect: 5
: ARR3 CREATE 10 , 20 , 30 , DOES> SWAP CELLS + @ ;
ARR3 NUMS
0 NUMS . 1 NUMS . 2 NUMS .             \ expect: 10 20 30
\ an immediate word runs while BAR is compiled, so BAR itself is empty
: FOO 42 ; IMMEDIATE
: BAR FOO ;
.                                      \ expect: 42
7 BAR .                                \ expect: 7
\ a name longer than 31 characters keeps its first 31 (a header's length field holds 0-31); the rest of the token is skipped
: ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456 5 ;
ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456 .     \ expect: 5
