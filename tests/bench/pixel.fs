\ Chaos-game attractor, 3000 PLOTs (benchmarks/forth/pixel.fs); the result depends on RND's sequence
3000 CONSTANT REPS
3 ARRAY XV
3 ARRAY YV
VARIABLE AX
VARIABLE BY
: SETUP
128 0 CELLS XV + ! 8 0 CELLS YV + !
16 1 CELLS XV + ! 184 1 CELLS YV + !
240 2 CELLS XV + ! 184 2 CELLS YV + !
128 AX ! 96 BY ! ;
: RUN-PIXEL REPS 0 DO
3 RND
DUP CELLS XV + @ AX @ + 2 / AX !
DUP CELLS YV + @ BY @ + 2 / BY !
1+ INK AX @ BY @ PLOT
LOOP ;
26725 RANDOMIZE SETUP CLS
: BENCH RUN-PIXEL 0 INK ;
\ bench: pixel
BENCH                  \ draws
CLS AX @ BY @ + .      \ expect: 302
