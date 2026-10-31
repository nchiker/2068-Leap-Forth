\ IF, DO and ." typed at the prompt are refused without leaving anything behind; inside a definition they work
VARIABLE HS HERE HS !
1 IF THEN                              \ expect: IF ?
HERE HS @ = .                          \ expect: -1
DROP                                   \ expect: STACK?
5 0 DO LOOP                            \ expect: DO ?
HERE HS @ = .                          \ expect: -1
DROP                                   \ expect: STACK?
." X"                                  \ expect: ." ?
HERE HS @ = .                          \ expect: -1
DROP                                   \ expect: STACK?
: DEMO 3 0 DO I . LOOP 1 IF ." Y " ELSE ." N" THEN ;
DEMO                                   \ expect: 0 1 2 Y
