\ [ and ] interpret inside a definition; LITERAL compiles what was computed there
: SIX [ 2 3 * ] LITERAL ;
SIX .                                  \ expect: 6
: SEVEN [ SIX 1+ ] LITERAL ;
SEVEN .                                \ expect: 7
\ ['] compiles the execution token of a word, an immediate one too
: FORTYTWO 42 ;
: XT ['] FORTYTWO ;
XT EXECUTE .                           \ expect: 42
: XIF ['] IF ;
XIF ' IF = .                           \ expect: -1
\ CHAR gives the first character as typed (a name is folded to upper case, a character is not); [CHAR] compiles it
CHAR a . CHAR A . CHAR [ . CHAR \ .    \ expect: 97 65 91 92
: CH [CHAR] z [CHAR] Hello ;
CH . .                                 \ expect: 72 122
\ at the prompt the compiling words are refused, as IF is, and leave nothing behind
VARIABLE HS HERE HS !
['] FORTYTWO                           \ expect: ['] ?
[CHAR] x                               \ expect: [CHAR] ?
5 LITERAL                              \ expect: LITERAL ?
HERE HS @ = .                          \ expect: -1
DROP                                   \ expect: STACK?
\ an unknown name after ['] is an error, and the console is interpreting again afterwards
: BAD ['] NOSUCHWORD ;                 \ expect: UNDEFINED WORD
1 2 + .                                \ expect: 3
