\ tools/tapetest.py case 2: demos/blackjack.fs, unchanged, goes on
\ the tape in place of the line DEMO below. KEY is defined before
\ it, so the demo's GETKEY takes the keys of KEYS, over and over.
\ RUN plays 8 rounds from seed 15785 and leaves, for each, the
\ player's total + 32 * the dealer's + 1024 * OUTCOME, then WON
\ LOST PUSHED. tapetest's model of the game gives the same.
VARIABLE KIDX
: KEYS S" hhs" ;
: KEY KEYS KIDX @ SWAP MOD + C@ KIDX @ 1+ KIDX ! ;
\ DEMO
: LOG ROUND PLAYER SCORE DEALER SCORE 32 * + OUTCOME @ 1024 * + ;
: RUN 15785 RANDOMIZE 0 WON ! 0 LOST ! 0 PUSHED ! GLYPHS
  8 0 DO LOG LOOP WON @ LOST @ PUSHED @ ;
RUN
