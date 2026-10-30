\ SAVE-LIB with the dictionary full throws -8 and does not touch the byte at HERE
VARIABLE SV
: LL SAVE-LIB ;
HERE SV !
{DICT_RAM_CEILING} 1- {HERE} ! 66 {DICT_RAM_CEILING} 1- C! ' LL CATCH TOOBIG . {DICT_RAM_CEILING} 1- C@ . SV @ {HERE} !   \ expect: -8 66
SV @ HERE = .                            \ expect: -1
