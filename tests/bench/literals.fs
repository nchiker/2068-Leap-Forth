\ Parsing integer literals: a definition with 20 of them, timed from ENTER (the compile)
\ bench: literals
: LITS 1 22 333 4444 5555 66 777 8888 9 10 11 12 13 14 15 16 17 18 19 -20 ;
LITS . . . 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP .   \ expect: -20 19 18 1
