\ BRIGHT and FLASH set and clear only their own attribute bit, for PLOT and for LINE
\ each line clears the screen and homes the cursor first, so the console's text stays clear of the plotted cells
CLS 0 0 AT-XY 7 PAPER 5 INK 0 BRIGHT 100 100 PLOT
22924 C@ 7 AND . 22924 C@ 64 AND . 22924 C@ 56 AND .           \ expect: 5 0 56
CLS 0 0 AT-XY 1 BRIGHT 60 60 PLOT
22759 C@ 64 AND . 22759 C@ 7 AND . 22759 C@ 56 AND .           \ expect: 64 5 56
CLS 0 0 AT-XY 0 BRIGHT 60 60 PLOT
22759 C@ 64 AND . 22759 C@ 7 AND . 22759 C@ 56 AND .           \ expect: 0 5 56
CLS 0 0 AT-XY 1 BRIGHT 128 132 132 132 LINE
23056 C@ .                             \ expect: 125
CLS 0 0 AT-XY 0 INK 7 PAPER 0 BRIGHT 128 132 132 132 LINE
23056 C@ .                             \ expect: 56
CLS 0 0 AT-XY 5 INK 1 FLASH 100 100 PLOT
22924 C@ 7 AND . 22924 C@ 128 AND . 22924 C@ 56 AND .          \ expect: 5 128 56
CLS 0 0 AT-XY 0 FLASH 60 60 PLOT
22759 C@ 128 AND . 22759 C@ 7 AND . 22759 C@ 56 AND .          \ expect: 0 5 56
CLS 0 0 AT-XY 1 FLASH 128 132 132 132 LINE
23056 C@ .                             \ expect: 189
CLS 0 0 AT-XY 0 INK 7 PAPER 0 FLASH 128 132 132 132 LINE
23056 C@ .                             \ expect: 56
