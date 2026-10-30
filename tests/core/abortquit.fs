\ ABORT clears both stacks and prints no OK; QUIT keeps them; both reset the CATCH and LEAVE depth counters
1.5 42 ABORT 99
FDEPTH .                               \ expect: 0
DROP                                   \ expect: STACK?
2.5 42 QUIT 99
. FDEPTH .                             \ expect: 42 1
F.                                     \ expect: 2.5000
DROP                                   \ expect: STACK?
3 {CATCH_DEPTH} C! 2 {LEAVE_DEPTH} C! ABORT
{CATCH_DEPTH} C@ . {LEAVE_DEPTH} C@ .                  \ expect: 0 0
4 {CATCH_DEPTH} C! 1 {LEAVE_DEPTH} C! QUIT
{CATCH_DEPTH} C@ . {LEAVE_DEPTH} C@ .                  \ expect: 0 0
