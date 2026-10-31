\ integer ABS SGN SQRT
-5 ABS .                                 \ expect: 5
5 ABS . 0 ABS .                          \ expect: 5 0
-5 SGN . 0 SGN . 5 SGN .                 \ expect: -1 0 1
16 SQRT . 15 SQRT .                      \ expect: 4 3
0 SQRT . 1 SQRT . 10000 SQRT .           \ expect: 0 1 100
