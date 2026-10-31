\ C! stores only the low byte, C@ reads a byte without a sign
HERE 300 OVER C! C@ .                    \ expect: 44
HERE 200 OVER C! C@ .                    \ expect: 200
HERE 65535 OVER ! DUP 0 SWAP C! @ .      \ expect: -256
