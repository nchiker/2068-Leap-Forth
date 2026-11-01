\ a word that takes more than the data stack holds writes past its top (SWAP and ROT in place, . the digits it
\ pushes for EMIT) before the check after it (SWAP and ROT leave the depth as it was, so the check sees nothing): those
\ writes must land in the guard above the stack, never in the dictionary
: X 1 ;
SWAP
X .                                      \ expect: 1
ROT
X .                                      \ expect: 1
.                                        \ expect-end: STACK?
X .                                      \ expect: 1
: SHOW . . . . ;
5 SHOW                                   \ expect-end: STACK?
X 2 + .                                  \ expect: 3
