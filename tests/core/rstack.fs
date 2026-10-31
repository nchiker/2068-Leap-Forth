\ recursion stops at MACHINE_STACK_GUARD with RETURN STACK FULL (THROW -5, STK_GUARD) before the machine stack runs
\ into the RAM below it: a definition calling itself, EXECUTE and CATCH; the dictionary and the line store survive
VARIABLE V  1234 V !
: R R ;
R                                      \ expect: RETURN STACK FULL
V @ .                                  \ expect: 1234
: R2 ['] R2 EXECUTE ;
R2                                     \ expect: RETURN STACK FULL
: R3 ['] R3 CATCH ;
R3 .                                   \ expect: 0
: R4 ['] R ;
R4 CATCH .                             \ expect: -5
\ a recursion that ends is untouched
: FAC DUP 1 > IF DUP 1- FAC * THEN ;
7 FAC .                                \ expect: 5040
