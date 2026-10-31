\ FORGET of a dictionary word rewinds HERE and LATEST; a built-in word is refused
{LATEST} @
: ZZZ 111 ;
{LATEST} @
FORGET ZZZ
HERE OVER = .                          \ expect: -1
{LATEST} @ ROT = .                        \ expect: -1
: ZZZ 222 ; {LATEST} @ = .                \ expect: -1
ZZZ .                                  \ expect: 222
HERE {LATEST} @ FORGET DUP                \ expect: FORGET: BUILT-IN, REFUSED
{LATEST} @ = . HERE = .                   \ expect: -1 -1
5 DUP . .                              \ expect: 5 5
