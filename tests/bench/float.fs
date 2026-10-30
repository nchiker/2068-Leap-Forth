\ Taylor-series SIN terms summed 300 times (benchmarks/forth/float.fs); the exact sum is -0.1453125
300 CONSTANT REPS
VARIABLE IDX
: FX IDX @ 150 - S>F 50.0 F/ ;
: TERM2 FX FX F* FX F* -6.0 F/ ;
: TERM3 FX FX F* FX F* FX F* FX F* 120.0 F/ ;
: TERM4 FX FX F* FX F* FX F* FX F* FX F* FX F* -5040.0 F/ ;
: FACT9 9.0 8.0 F* 7.0 F* 6.0 F* 5.0 F* 4.0 F* 3.0 F* 2.0 F* ;
: TERM5 FX FX F* FX F* FX F* FX F* FX F* FX F* FX F* FX F* FACT9 F/ ;
: BENCH 0.0 REPS 0 DO
I IDX ! FX TERM2 F+ TERM3 F+ TERM4 F+ TERM5 F+ F+
LOOP F. ;
\ bench: float
BENCH                  \ expect: -0.1453
