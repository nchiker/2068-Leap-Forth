\ \ is a comment to the end of the line, ( a comment to the next )
1 2 \ 3 4
+ .                                    \ expect: 3
1 ( 2 3 ) 4 + .                        \ expect: 5
: C1 1 ( one ) 2 \ 3 ;
+ ;
C1 .                                   \ expect: 3
\ \ ending its line, and an unclosed ( which runs to the end of the line
5 \
6 ( 7 8
+ .                                    \ expect: 11
