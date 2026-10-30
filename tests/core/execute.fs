\ EXECUTE on a primitive and on a colon definition
5 3 ' + EXECUTE .                      \ expect: 8
: DOUBLE DUP + ;
21 ' DOUBLE EXECUTE .                  \ expect: 42
