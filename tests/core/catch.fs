\ CATCH and THROW: normal return, a throw, nesting, THROW 0, an uncaught throw from three calls deep
: F42 42 ;
: THR 999 7 THROW 12345 ;
' THR CONSTANT KT
: NST KT CATCH 555 ;
: DEEP3 42 THROW ;
: DEEP2 DEEP3 ;
: DEEP1 DEEP2 ;
' F42 CATCH . .                        \ expect: 0 42
' THR CATCH .                          \ expect: 7
\ a THROW leaves the stack as it was below the xt, then the code
1 2 ' THR CATCH . . .                  \ expect: 7 2 1
' NST CATCH . . .                      \ expect: 0 555 7
4242 0 THROW . {CATCH_DEPTH} C@ .              \ expect: 4242 0
1.5 7 DEEP1                            \ expect: ERROR 42
FDEPTH .                               \ expect: 0
DROP                                   \ expect: STACK?
