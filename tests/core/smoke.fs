\ the runner's own check: arithmetic, a definition, an unknown word, scrolling past the bottom row
3 4 + .                \ expect: 7
: SQ DUP * ;
5 SQ .                 \ expect: 25
FOO                    \ expect: FOO ?
1 . 2 . 3 .            \ expect: 1 2 3
: ROWS 0 DO I . CR LOOP ;
15 ROWS                \ expect: 0|1|2|3|4|5|6|7|8|9|10|11|12|13|14
7 .                    \ expect: 7
