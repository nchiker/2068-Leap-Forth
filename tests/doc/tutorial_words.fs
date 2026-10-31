\ the examples of docs/forth_tutorial.md for comments, [ ] LITERAL, ['], CHAR and [CHAR] (section 2)
2 ( width ) 3 ( height ) * .           \ expect: 6
: SECONDS-PER-HOUR  [ 60 60 * ] LITERAL ;
SECONDS-PER-HOUR .                     \ expect: 3600
: DOUBLE  DUP + ;
: RUN-DOUBLE  ['] DOUBLE EXECUTE ;
5 RUN-DOUBLE .                         \ expect: 10
CHAR A . CHAR a .                      \ expect: 65 97
: STAR [CHAR] * EMIT ;
STAR                                   \ expect: *
