\ VLIST prints every word, newest first, and leaves the stack alone (the screen shows the oldest words at the end)
: Q 1 ; : WWWW 2 ;
1 2 VLIST . .                          \ expect-end: DROP 2 1
