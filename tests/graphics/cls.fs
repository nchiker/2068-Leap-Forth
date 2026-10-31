\ CLS repaints the whole attribute area with the current INK and PAPER
2 INK 6 PAPER 255 22528 C! CLS 22528 C@ .   \ expect: 114
22896 C@ .                         \ expect: 114
255 22528 C! 255 22896 C! CLS 22528 C@ {CURRENT_ATTR} C@ - . 22896 C@ {CURRENT_ATTR} C@ - .   \ expect: 0 0
\ CLS homes the print position
5 5 AT-XY CLS {PRINT_COL} C@ {PRINT_ROW} C@ . . 9 .   \ expect: 0 0 9
