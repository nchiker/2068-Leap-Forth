\ TYPE of a 32-character line, 100 times at the top of the screen: EMIT's drawing (letters, digits, punctuation)
100 CONSTANT REPS
: LINE S" Text: 0123, [a-z] {A|Z} 1.0 l.0;" ;
: BENCH REPS 0 DO 0 0 AT-XY LINE TYPE LOOP ;
CLS
\ bench: text
BENCH                  \ draws
CLS LINE DROP 5 TYPE   \ expect: Text:
