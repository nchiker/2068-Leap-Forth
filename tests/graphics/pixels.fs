\ LINE end points set pixels; PLOT and LINE paint the cell attribute from INK and PAPER (bytes at 22528 + 32 * row + col)
0 FLASH 0 BRIGHT 0 INK 7 PAPER
CLS 0 0 AT-XY
60 105 100 145 LINE 18855 C@ 8 AND . 20812 C@ 8 AND .   \ expect: 8 8
5 INK 200 100 PLOT 22937 C@ . 22938 C@ .   \ expect: 61 56
2 PAPER 100 80 PLOT 22860 C@ .           \ expect: 21
1 INK 3 PAPER 160 160 180 160 LINE 23188 C@ . 23190 C@ . 23191 C@ .   \ expect: 25 25 56
