\ an unknown word does not stop the interpreter; a stack overflow or underflow prints STACK? and resets the stack
BOGUSWORD                                \ expect: BOGUSWORD ?
5 BORDER {PORT_FE_SHADOW} C@ 7 AND .                \ expect: 5
DROP                                     \ expect: STACK?
1 .                                      \ expect: 1
FDROP                                    \ expect: STACK?
1.5 F. FDEPTH .                          \ expect: 1.5000 0
CLS 0 0 AT-XY
: D1 1024 0 DO I LOOP ;
: U 1024 0 DO DROP LOOP ;
: D2 1025 0 DO I LOOP ;
D1
U
D2                                       \ expect: STACK?
1 .                                      \ expect: 1
