\ stack words ROT 2DUP 2DROP ?DUP PICK
1 2 3 ROT . . .                        \ expect: 1 3 2
5 6 2DUP . . . .                       \ expect: 6 5 6 5
7 8 9 10 2DROP . .                     \ expect: 8 7
5 ?DUP . .                             \ expect: 5 5
\ ?DUP must not duplicate a zero: the 7 stays on top after the DROP
7 0 ?DUP DROP .                        \ expect: 7
10 20 30 0 PICK . 2 PICK . . . .       \ expect: 30 10 30 20 10
