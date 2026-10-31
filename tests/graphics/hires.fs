\ HIRES clears the second display file, colours each pixel row on its own, CLS repaints it, NORMAL returns
HIRES
24576 C@ .                             \ expect: 68
1 INK 10 100 PLOT 6 INK 10 101 PLOT
27777 C@ 7 AND . 28033 C@ 7 AND .      \ expect: 1 6
2 INK CLS
27777 C@ . {CURRENT_ATTR} C@ .                  \ expect: 66 66
NORMAL 3 INK 100 100 PLOT
{GFX_MODE} C@ . 22924 C@ 7 AND .            \ expect: 0 3
