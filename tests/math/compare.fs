\ integer comparisons = < > give -1 for true and 0 for false, including the sign edge cases
5 3 = . 3 3 = .                          \ expect: 0 -1
5 3 < . 3 5 < . -1 1 < . 1 -1 < .        \ expect: 0 -1 -1 0
-32768 -1 < . -1 -32768 < .              \ expect: -1 0
5 3 > . 3 5 > .                          \ expect: -1 0
-1 1 > . 1 -1 > . -1 -32768 > .          \ expect: 0 -1 -1
3 3 < . 3 3 > .                          \ expect: 0 0
