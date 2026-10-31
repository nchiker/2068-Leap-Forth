\ RAD and DEG on exact 5-byte float cells (read back byte by byte)
FVARIABLE X
: B5 5 0 DO DUP I + C@ . LOOP DROP ;
90.0 RAD X F! X B5                     \ expect: 129 73 15 218 163
PI 2.0 F/ DEG X F! X B5                \ expect: 135 52 0 0 0
