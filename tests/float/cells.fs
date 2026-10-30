\ exact 5-byte results of F+ F- F* F/ FSQRT and PI, read back through F! and C@
FVARIABLE R
: DUMP5 5 0 DO DUP I + C@ . LOOP DROP ;
5.0 2.0 F- R F! R DUMP5                  \ expect: 130 64 0 0 0
4.0 1.0 F+ R F! R DUMP5                  \ expect: 131 32 0 0 0
-2.0 3.0 F* R F! R DUMP5                 \ expect: 131 192 0 0 0
6.0 3.0 F/ R F! R DUMP5                  \ expect: 130 0 0 0 0
1.0 4.0 F/ R F! R DUMP5                  \ expect: 127 0 0 0 0
9.0 FSQRT R F! R DUMP5                   \ expect: 130 64 0 0 0
PI R F! R DUMP5                          \ expect: 130 73 15 218 162
\ a carry out of the 32-bit mantissa sum, from exact cells
FVARIABLE FA
FVARIABLE FB
127 FA C! 113 FA 1+ C! 90 FA 2 + C! 0 FA 3 + C! 0 FA 4 + C!
125 FB C! 20 FB 1+ C! 12 FB 2 + C! 0 FB 3 + C! 0 FB 4 + C!
FA F@ FB F@ F+ R F! R DUMP5             \ expect: 128 11 46 128 0
