\ a line that ends in an error removes the : definition it left open (COLON_DROP): HERE and LATEST
\ go back, so the half-compiled word is never found or run; a definition over several lines stays open
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
