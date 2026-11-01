\ LAST_ERROR: the code the last console line ended with (0 after OK), read here by the next line; the Leap IDE reads it
1 2 + .                                \ expect: 3
{LAST_ERROR} @ .                       \ expect: 0
NOSUCHWORD                             \ expect: NOSUCHWORD ?
{LAST_ERROR} @ .                       \ expect: -13
-42 THROW                              \ expect: DIVISION BY ZERO
{LAST_ERROR} @ .                       \ expect: -42
7 THROW                                \ expect: ERROR 7
{LAST_ERROR} @ .                       \ expect: 7
\ STACK? is -4 when a stack ran under, -3 when one ran over (ANS numbers); -3 and -4 THROWn print STACK? too
DROP                                   \ expect: STACK?
{LAST_ERROR} @ .                       \ expect: -4
FDROP                                  \ expect: STACK?
{LAST_ERROR} @ .                       \ expect: -4
: PUSHES 0 DO 1 LOOP ;
1100 PUSHES                            \ expect: STACK?
{LAST_ERROR} @ .                       \ expect: -3
-3 THROW                               \ expect: STACK?
-4 THROW                               \ expect: STACK?
\ IF at the prompt reports as an unknown word
IF                                     \ expect: IF ?
{LAST_ERROR} @ .                       \ expect: -13
ABORT
{LAST_ERROR} @ .                       \ expect: -1
QUIT
{LAST_ERROR} @ .                       \ expect: -56
: BAD 1 FOO ;                          \ expect: FOO ?
{LAST_ERROR} @ . {LAST_ERROR} @ .      \ expect: -13 -13
{LAST_ERROR} @ .                       \ expect: 0
