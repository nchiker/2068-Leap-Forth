\ KEY reads the key code, KEY? says whether one is latched (KBD_LASTK 33436, KBD_KEYHIT 33437), STICK, ACCEPT and INPUT
\ keys: A
KEY .                                    \ expect: 65
\ keys: 5
KEY .                                    \ expect: 53
0 {KBD_KEYHIT} C! KEY? .                        \ expect: 0
1 {KBD_KEYHIT} C! 88 {KBD_LASTK} C! KEY? . KEY? .     \ expect: -1 -1
\ keys: X
1 {KBD_KEYHIT} C! 88 {KBD_LASTK} C! KEY . KEY? .      \ expect: 88 0
4242 1 STICK . .                         \ expect: 0 4242
4242 2 STICK . .                         \ expect: 0 4242
CREATE B 5 ALLOT
\ keys: HELLOX\b\r
B 5 ACCEPT DUP . B SWAP TYPE SPACE       \ expect: HELL4 HELL
\ keys: 123\r
INPUT .                                  \ expect: 123123
