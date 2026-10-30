\ LIST-DEFS numbers every definition kept in the line store, with a preview of each
: AA DUP + ;
: BB DUP - ;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;
\ a ";" inside a word or a string does not end a definition: only the word ";" does
: CC ." A;B" ;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;|2: : CC ." A;B" ;
