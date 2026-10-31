\ ' finds a freshly compiled word and throws -13 for an unknown one
: FORTYTWO 42 ;
' FORTYTWO EXECUTE .                   \ expect: 42
' ' CATCH NOSUCHWORD .                 \ expect: -13
