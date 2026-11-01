\ a line that ends in an error removes the : definition it left open (COLON_DROP): HERE and LATEST
\ go back, so the half-compiled word is never found or run, and its open DO loops are closed (LEAVE_DEPTH);
\ a definition over several lines stays open
VARIABLE H  HERE H !
: X 1 FOO ;                              \ expect: FOO ?
HERE H @ - .                             \ expect: 0
X                                        \ expect: X ?
: Y 1
2 + ;
Y .                                      \ expect: 3
HERE H !
: Z 1 [ -42 THROW ] ;                    \ expect: DIVISION BY ZERO
HERE H @ - .   ' Y DROP                  \ expect: 0
: W [ ABORT ]
W                                        \ expect: W ?
{COLON_HDR} @ .                          \ expect: 0
: L 10 0 DO FOO LOOP ;                   \ expect: FOO ?
{LEAVE_DEPTH} C@ .                       \ expect: 0
: E 1 EXIT ;
E .                                      \ expect: 1
