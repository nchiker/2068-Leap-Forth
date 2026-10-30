\ LIST-DEFS numbers every definition kept in the line store, with a preview of each
: AA DUP + ;
: BB DUP - ;
LIST-DEFS                              \ expect: 0: : AA DUP + ;|1: : BB DUP - ;
