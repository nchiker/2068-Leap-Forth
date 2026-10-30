\ HERE , C, ALLOT move and fill the dictionary pointer
HERE {HERE} @ = .                       \ expect: -1
HERE 43981 , HERE SWAP - .             \ expect: 2
HERE 2 - @ .                           \ expect: -21555
HERE 66 C, HERE SWAP - .               \ expect: 1
HERE 1 - C@ .                          \ expect: 66
HERE 10 ALLOT HERE SWAP - .            \ expect: 10
HERE -4 ALLOT HERE SWAP - .            \ expect: -4
