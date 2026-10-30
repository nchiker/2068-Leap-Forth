\ the examples of README.md's "Try it"
5 3 + .                          \ expect: 8
: GREET ." HI" ; GREET           \ expect: HI
: FIVE 5 0 DO I . LOOP ; FIVE    \ expect: 0 1 2 3 4
VARIABLE FOO 42 FOO ! FOO @ .    \ expect: 42
3.5 2.5 F+ F.                    \ expect: 6.0000
9 PLACES PI F.                   \ expect: 3.141592653
1.0 0.0 F/                       \ expect: DIVISION BY ZERO
2 INK 100 100 30 CIRCLE 100 100 FILL  \ draws
4 INK 100 40 140 40 100 80 3 POLYGON  \ draws
