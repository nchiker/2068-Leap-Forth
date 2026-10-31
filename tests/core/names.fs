\ a word that takes a name refuses a missing one (it made a nameless word, : even left the console compiling)
VARIABLE HS HERE HS !
:                                      \ expect: MISSING NAME
1 2 + .                                \ expect: 3
CREATE                                 \ expect: MISSING NAME
VARIABLE                               \ expect: MISSING NAME
5 CONSTANT                             \ expect: MISSING NAME
5 ARRAY                                \ expect: MISSING NAME
5 STRING                               \ expect: MISSING NAME
1.5 FCONSTANT                          \ expect: MISSING NAME
FVARIABLE                              \ expect: MISSING NAME
'                                      \ expect: MISSING NAME
CHAR                                   \ expect: MISSING NAME
FORGET                                 \ expect: MISSING NAME
HERE HS @ = .                          \ expect: -1
\ the defining words still work, sharing one header builder
5 ARRAY AR 3 STRING ST 7 CONSTANT SV CREATE CR1 9 , VARIABLE VV
AR 8 + @ . ST C@ . SV . CR1 @ . VV @ .         \ expect: 0 0 7 9 0
\ ARRAY keeps 2n data bytes and STRING n + 1: a word's data follows them, after its header (5) and code (6)
5 ARRAY A5 CREATE X1 X1 A5 - .         \ expect: 21
3 STRING S3 CREATE X2 X2 S3 - .        \ expect: 15
