\ EXIT leaves a definition early (also from inside a DO loop); J reads the outer loop index
: TEXIT1 1 EXIT 2 ;
7 TEXIT1 . .                           \ expect: 1 7
: TEXIT2 0 5 0 DO I 3 = IF EXIT THEN 1 + LOOP 999 ;
7 TEXIT2 . .                           \ expect: 3 7
: TESTJ 0 2 0 DO 3 0 DO I DUP + J + + LOOP LOOP ;
TESTJ .                                \ expect: 15
