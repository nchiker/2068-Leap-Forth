\ PLACE and STR, 400 times (benchmarks/forth/string.fs): 12 for "TS2068-BENCH" + 3 digits of 399
400 CONSTANT REPS
32 STRING BUF
VARIABLE LASTLEN
: BENCH REPS 0 DO
S" TS2068-BENCH" BUF PLACE
I STR LASTLEN ! DROP
LOOP BUF C@ LASTLEN @ + . ;
\ bench: string
BENCH                  \ expect: 15
