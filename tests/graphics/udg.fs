\ UDG slot addresses, writing a slot with C!, and EMIT 144 drawing slot 0 into the bitmap
0 UDG . 1 UDG . 20 UDG .               \ expect: -3712 -3704 -3552
1 UDG 0 UDG - . 20 UDG 0 UDG - .       \ expect: 8 160
24 0 UDG C! 60 0 UDG 1 + C! 126 0 UDG 2 + C! 255 0 UDG 3 + C!
255 0 UDG 4 + C! 60 0 UDG 5 + C! 24 0 UDG 6 + C! 60 0 UDG 7 + C!
0 UDG C@ . 0 UDG 1 + C@ . 0 UDG 2 + C@ . 0 UDG 3 + C@ .       \ expect: 24 60 126 255
0 UDG 4 + C@ . 0 UDG 5 + C@ . 0 UDG 6 + C@ . 0 UDG 7 + C@ .   \ expect: 255 60 24 60
CLS 0 0 AT-XY 144 EMIT                    \ draws
16384 C@ . 16640 C@ . 16896 C@ . 17152 C@ .                    \ expect: 24 60 126 255
17408 C@ . 17664 C@ . 17920 C@ . 18176 C@ .                    \ expect: 255 60 24 60
