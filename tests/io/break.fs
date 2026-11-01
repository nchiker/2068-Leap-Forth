\ BREAK? is false with no key held and leaves KEY?'s latched key alone
BREAK? .                               \ expect: 0
\ keys: X
1 {KBD_KEYHIT} C! 88 {KBD_LASTK} C! BREAK? DROP KEY? . KEY .                \ expect: -1 88
\ BREAK (CAPS SHIFT + SPACE) while a word runs throws -28 there (core/throwcatch.asm): uncaught, the
\ console prints BREAK and the rest of the line is dropped; CATCH gets -28
: L BEGIN 0 UNTIL ;
\ break: after 30000
L 1 .                                  \ expect: BREAK
{LAST_ERROR} @ .                       \ expect: -28
1 .                                    \ expect: 1
: C ['] L CATCH . 2 . ;
\ break: after 30000
C                                      \ expect: -28 2
\ a word waiting for a key, or for a BEEP's note: the wait ends, and BREAK silences the AY
\ break: at IO_READ_KEY
KEY .                                  \ expect: BREAK
CREATE B 20 ALLOT
\ break: at IO_READ_KEY
B 20 ACCEPT .                          \ expect: BREAK
\ break: after 30000
0 60.0 BEEP 3 .                        \ expect: BREAK
8 245 OUT 246 IN .                     \ expect: 0
{KBD_KEYHIT} C@ . {BRK_PEND} C@ . {NOBRK} C@ .        \ expect: 0 0 0
\ FILL in the EXROM stops at once, and the EXROM is paged out again
CLS 0 18 AT-XY 50 50 20 CIRCLE         \ draws
\ break: at FILL_IMPL.pop 3
50 50 FILL 4 .                         \ expect-end: OK|BREAK
{BANK_EXROM_DEPTH} C@ .                \ expect: 0
\ a display mode change and SPRITE-SHOW finish first (NOBRK), then stop
\ break: at GFX_SET_MODE
HIRES 5 .                              \ expect: BREAK
{GFX_MODE} C@ . {PORT_FF_SHADOW} C@ 7 AND .           \ expect: 1 2
NORMAL CLS 0 18 AT-XY
0 0 0 SPRITE-DEFINE                    \ draws
\ (SPRITE-SHOW is shorter than BREAK's debounce: a BREAK left pending in it stops at its end)
1 {BRK_PEND} C!  0 10 10 SPRITE-SHOW 6 .                \ expect: BREAK
{SPRITE_SLOT_SHOWN} C@ 0= 0= .         \ expect: -1
0 SPRITE-HIDE {SPRITE_SLOT_SHOWN} C@ . \ expect: 0
\ the tutorial's example (section 13, Catching BREAK): the program tidies up and says why it stopped
CLS 0 0 AT-XY
: SPIN   BEGIN 1 BORDER 2 BORDER 0 UNTIL ;
: RUN    ['] SPIN CATCH  7 BORDER  -28 = IF ." STOPPED" CR THEN ;
\ break: after 30000
RUN {PORT_FE_SHADOW} C@ 7 AND .        \ expect: STOPPED|7
