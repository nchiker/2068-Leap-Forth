\ LIST-DEFS numbers every definition kept in the line store, with a preview of each
: AA DUP + ;
: BB DUP - ;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;
\ a ";" inside a word or a string does not end a definition: only the word ";" does
: CC ." A;B" ;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;|2: : CC ." A;B" ;
\ a ; or : inside a comment counts for nothing (a \ comment runs to the end of its line)
: DD ( a ; b ) 1 ;
1 DROP \ : EE ;
: FF 2 \ ;
;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;|2: : CC ." A;B" ;|3: : DD ( a ; b ) 1 ;|4: : FF 2 \ ;|;
