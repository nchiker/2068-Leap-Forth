\ TONE VOLUME MIXER NOISE ENVELOPE: they take exactly their arguments, write the right AY registers, and ignore a bad channel
: AYW 245 OUT 246 OUT ;
: AYR 245 OUT 246 IN . ;
4242 1 2736 TONE .                     \ expect: 4242
2 AYR 3 AYR                            \ expect: 176 10
4242 2 15 VOLUME .                     \ expect: 4242
10 AYR                                 \ expect: 15
4242 253 MIXER .                       \ expect: 4242
7 AYR                                  \ expect: 253
4242 31 NOISE .                        \ expect: 4242
6 AYR                                  \ expect: 31
4242 1000 14 ENVELOPE .                \ expect: 4242
11 AYR 12 AYR 13 AYR                   \ expect: 232 3 14
\ a channel outside 0-2 leaves the registers it would have hit (6, 7, 11) alone
5 6 AYW 6 7 AYW 7 11 AYW
4242 3 2736 TONE .                     \ expect: 4242
4242 3 15 VOLUME .                     \ expect: 4242
4242 200 15 VOLUME .                   \ expect: 4242
6 AYR 7 AYR 11 AYR                     \ expect: 5 6 7
