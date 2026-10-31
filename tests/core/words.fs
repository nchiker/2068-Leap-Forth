\ the dictionary is one chain, words work together, the 50 Hz interrupt runs
' SAVE-LIB DROP ' LOAD-LIB DROP ' F+ DROP ' F- DROP
' PLOT DROP ' LINE DROP ' BORDER DROP
CLS 0 0 AT-XY
: COMBOTEST 0= IF 111 ELSE 222 THEN ;
0 COMBOTEST 10 20 PLOT . 17473 C@ 32 AND .   \ expect: 111 32
: WF 0 {FRAMES} ! BEGIN {FRAMES} @ UNTIL {FRAMES} @ . ;
WF                                       \ expect: 1
