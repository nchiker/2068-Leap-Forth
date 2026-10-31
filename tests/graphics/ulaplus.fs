\ PALETTE and ULAPLUS leave the attribute bytes of drawn lines alone (the palette change itself is only visible on screen)
CLS 2 INK 100 70 130 100 LINE 130 100 100 130 LINE 100 130 70 100 LINE 70 100 100 70 LINE      \ draws
22796 C@ .                             \ expect: 58
2 252 PALETTE 1 ULAPLUS
22796 C@ .                             \ expect: 58
0 ULAPLUS
