\ stack primitives, + - @ !, colon definitions, IF/ELSE/THEN, BEGIN loops, DO/LOOP/LEAVE/+LOOP, VARIABLE, CONSTANT, ARRAY
5 3 + .                                  \ expect: 8
5 3 + 4 DUP + + .                        \ expect: 16
16 100 OVER - .                          \ expect: 84
16 100 OVER - DROP .                     \ expect: 16
1 2 SWAP .                               \ expect: 1
1 2 SWAP DROP .                          \ expect: 2
CLS 0 0 AT-XY
1234 HERE ! HERE @ .                     \ expect: 1234
: DOUBLE DUP + ;
4 DOUBLE .                               \ expect: 8
: IFTEST 0= IF 111 ELSE 222 THEN ;
0 IFTEST .                               \ expect: 111
5 IFTEST .                               \ expect: 222
CLS 0 0 AT-XY
: COUNTDOWN BEGIN 1 - DUP 0= UNTIL ;
5 COUNTDOWN .                            \ expect: 0
: COUNTDOWN2 BEGIN DUP 0 > WHILE 1 - REPEAT ;
5 COUNTDOWN2 .                           \ expect: 0
0 COUNTDOWN2 .                           \ expect: 0
: PRINTDOWN BEGIN DUP 0 > WHILE DUP . 1 - REPEAT DROP ;
CLS 0 0 AT-XY
3 PRINTDOWN                              \ expect: 3 2 1
: FIVETIMES 5 0 DO I . LOOP ;
FIVETIMES                                \ expect: 0 1 2 3 4
: NEST 3 0 DO 2 0 DO I . LOOP LOOP ;
NEST                                     \ expect: 0 1 0 1 0 1
VARIABLE SUM
CLS 0 0 AT-XY
0 SUM !
: DOSUM 5 0 DO I SUM @ + SUM ! LOOP ;
DOSUM SUM @ .                            \ expect: 10
: TESTLEAVE 10 0 DO I . I 3 = IF LEAVE THEN LOOP ;
TESTLEAVE                                \ expect: 0 1 2 3
: EVENS 10 0 DO I . 2 +LOOP ;
CLS 0 0 AT-XY
EVENS                                    \ expect: 0 2 4 6 8
: NEST2 3 0 DO 5 0 DO I . I 2 = IF LEAVE THEN LOOP LOOP ;
NEST2                                    \ expect: 0 1 2 0 1 2 0 1 2
VARIABLE FOO
42 FOO !
FOO @ .                                  \ expect: 42
CLS 0 0 AT-XY
100 CONSTANT BAR
BAR .                                    \ expect: 100
VARIABLE BAZ
7 BAZ !
BAZ @ .                                  \ expect: 7
FOO @ .                                  \ expect: 42
CLS 0 0 AT-XY
5 ARRAY NUMS
NUMS @ .                                 \ expect: 0
99 3 CELLS NUMS + !
3 CELLS NUMS + @ .                       \ expect: 99
0 CELLS NUMS + @ . 1 CELLS NUMS + @ . 2 CELLS NUMS + @ .   \ expect: 0 0 0
4 CELLS NUMS + @ .                       \ expect: 0
CLS 0 0 AT-XY
