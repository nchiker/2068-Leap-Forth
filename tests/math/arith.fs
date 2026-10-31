\ 1+ 1- NEGATE MAX MIN including the 16-bit wrap and signed comparison edges
5 1+ .                                 \ expect: 6
5 1- .                                 \ expect: 4
32767 1+ .                             \ expect: -32768
-32768 1- .                            \ expect: 32767
5 NEGATE .                             \ expect: -5
-5 NEGATE .                            \ expect: 5
0 NEGATE .                             \ expect: 0
-32768 NEGATE .                        \ expect: -32768
5 3 MAX .                              \ expect: 5
3 5 MIN .                              \ expect: 3
-1 3 MAX .                             \ expect: 3
-5 -1 MAX .                            \ expect: -1
32767 -32768 MIN .                     \ expect: -32768
