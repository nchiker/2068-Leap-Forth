\ SOUND writes the AY register it names, rejects a register above 15, and leaves the stack balanced (read back through the AY ports)
0 245 OUT 0 246 OUT 0 165 SOUND 0 245 OUT 246 IN .       \ expect: 165
0 90 SOUND 0 245 OUT 246 IN .          \ expect: 90
1 7 SOUND 1 245 OUT 246 IN .           \ expect: 7
4242 17 200 SOUND . 0 245 OUT 246 IN . \ expect: 4242 90
256 33 SOUND 0 245 OUT 246 IN .        \ expect: 90
