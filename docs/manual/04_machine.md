# Part 4 -- Words of the machine

The words that work the TS2068 itself, in ASCII order of their name: printing and the keyboard, colour and graphics,
the AY sound chip, the tape and the printer. The words of the language are in [Part 3](03_language.md), which also
says [how to read an entry](03_language.md#how-to-read-an-entry): the stack effects, kinds and examples here are
written the same way.

**The screen.** Text has 24 rows of 32 columns; row 0 is the top, column 0 the left. Rows 0 to 22 are for output and
row 23 is the line you type on. Printing starts at the *print position*, which moves one column right after each
character and to the next row after column 31; printing below row 22 scrolls the output up a row. Pixels have *x*
from 0 (left) to 255 and *y* from 0 (**top**) to 191, counted from the top left as text is (not as in Sinclair BASIC,
where *y* counts up from the bottom). A point off the screen is not drawn and is not an error. See
[Screen](05_concepts.md#screen) and [Graphics](05_concepts.md#graphics).

**Colours** are the TS2068's eight: 0 black, 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white. At
switch-on the ink is 0 and the paper 7, with bright and flash off.

**Frames.** A *frame* is one display refresh: 1/60 second on a TS2068, 1/50 second on ZEsarUX. Words that wait or
play for a time count frames.

## Summary

| Group | Words |
|---|---|
| **I/O** | `.` `."` `EMIT` `CR` `SPACE` `SPACES` `TYPE` `AT-XY` `CLS` `KEY` `KEY?` `BREAK?` `ACCEPT` `INPUT` `STICK` `IN` `OUT` |
| **graphics** | `INK` `PAPER` `BRIGHT` `FLASH` `BORDER` `PLOT` `LINE` `RECT` `FILL` `CIRCLE` `POLYGON` `POLYGON-FILL` `HIRES` `NORMAL` `UDG` `SPRITE-DEFINE` `SPRITE-SHOW` `SPRITE-HIDE` `ULAPLUS` `PALETTE` |
| **sound** | `BEEP` `SOUND` `TONE` `VOLUME` `MIXER` `NOISE` `ENVELOPE` |
| **storage** | `SAVE-TEXT` `VERIFY-TEXT` `LOAD-TEXT` `SAVE-LIB` `VERIFY-LIB` `LOAD-LIB` |
| **printer** | `LPRINT` `LLIST` |

---

## .

`( n -- )` -- **word**, I/O

Prints *n* as a signed decimal number, with a minus sign if it is negative, followed by one space, at the print position. A cell is 16 bits, so a number above 32,767 that was meant as unsigned prints as a negative one: `65535 .` prints -1.

```forth
42 .                     \ expect: 42
-7 .  0 .  32767 .       \ expect: -7 0 32767
65535 .                  \ expect: -1
```

**Notes.**

* The trailing space is why `1 . 2 .` prints `1 2`: the numbers do not run together.
* To print a decimal (floating-point) number use `F.` or `FS.`.

**Errors.**

| Mistake | What happens |
|---|---|
| an empty stack | `STACK?` |

**See also** `EMIT`, `F.`, `STR`, [Numbers](05_concepts.md#numbers).

---

## ."

`( -- )` -- **compile-only word**, I/O

Used inside a definition: `." text"` compiles the characters after the space that follows `."`, up to the closing `"`, into the definition. When the definition runs, it prints them at the print position. There is no way to put a `"` inside the text.

```forth
: HELLO ." HELLO, WORLD" CR ;
HELLO                    \ expect: HELLO, WORLD
: AB ." A" ." B" ;
AB                       \ expect: AB
```

**Notes.**

* The text is part of the definition, so a long text uses dictionary space (`FREE` says how much is left).
* To print text at the prompt, or text that is not fixed, use `S"` and `TYPE`.
* A line that ends before the closing `"` takes the rest of the line as the text.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt, outside a definition | `."` followed by ` ?`, and nothing is compiled |

```forth
." HI"                   \ expect: ." ?
```

**See also** `TYPE`, `S"`, `EMIT`, `CR`.

---

## ACCEPT

`( addr n -- len )` -- **word**, I/O

Reads a line from the keyboard into memory at *addr* and leaves the number of characters typed, *len*. Each character is stored as it is typed and shown at the print position. ENTER ends the line (it is not stored and not shown). DELETE (CAPS SHIFT and 0) takes back the last character. Once *n* characters are in, further keys are ignored until ENTER or DELETE.

```forth
CREATE BUF 20 ALLOT
\ keys: HELLO\r
BUF 20 ACCEPT SPACE .    \ expect: HELLO 5
BUF 5 TYPE               \ expect: HELLO
\ keys: ABCDEFG\r
BUF 3 ACCEPT SPACE .     \ expect: ABC 3
\ keys: ABC\b\r
BUF 20 ACCEPT CR .       \ expect: AB|2
```

**Notes.**

* The text is stored without a count and without an end mark: use *len* to say how long it is. Make the buffer at least *n* characters long.
* *n* is taken as a byte: 256 counts as 0, and with *n* = 0 every key but ENTER is ignored.
* Any key other than ENTER and DELETE is stored as its code, including the cursor keys (codes 1 to 4), which show as blanks.
* DELETE moves back along the row, and does not go back past column 0 onto the row above: on a line that has wrapped, the screen is not repaired.
* The `\ keys:` lines of the examples give the test the keys to press; at a real keyboard you type them.
* BREAK ends the wait with the BREAK message.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |
| *n* more than the room at *addr* | nothing: the characters are stored over whatever follows |

**See also** `INPUT`, `KEY`, `TYPE`, [Characters and keys](05_concepts.md#characters-and-keys), [Break](05_concepts.md#break).

---

## AT-XY

`( col row -- )` -- **word**, I/O

Moves the print position to column *col* (0 is the left, 31 the right) and row *row* (0 is the top, 22 the last row for output). The next `EMIT`, `.`, `."` or `TYPE` prints there.

```forth
CLS 10 0 AT-XY 65 EMIT   \ expect:           A
0 2 AT-XY 66 EMIT        \ expect: |B
```

**Notes.**

* The column comes first, as *x* before *y*. Sinclair BASIC's `AT` takes the row first.
* Neither number is checked. A position off the 32-column grid draws nothing; the character after it moves printing on to the start of the next row. Row 23 is the line you type on: print only in rows 0 to 22.

**See also** `EMIT`, `CLS`, [Screen](05_concepts.md#screen).

---

## BEEP

`( n -- ) ( F: seconds -- )` -- **word**, sound

Plays a note on channel A of the AY sound chip and waits until it ends. *n* is the pitch in semitones from middle C: 0 is middle C, 12 the C above it, -12 the C below. The length is *seconds*, a decimal on the float stack, so write it with a decimal point: `0 0.5 BEEP` plays middle C for half a second.

```forth
0 0.25 BEEP  4 0.25 BEEP         \ C, E
7 0.25 BEEP                              \ G
: AY@ 245 OUT 246 IN ;
0 0.02 BEEP  0 AY@ . 1 AY@ .             \ expect: 165 1
12 0.02 BEEP  0 AY@ . 1 AY@ .            \ expect: 211 0
70 0.02 BEEP                             \ nothing: out of range
```

The note is the chip's tone period in registers 0 and 1: 165 + 256 * 1 = 421 for middle C, and 211 (half as much) for the C above it.

**Notes.**

* *n* may be -60 to 69. The chip cannot play below 27.5 Hz (semitone -39), so -60 to -40 all play that note. Any other *n* plays nothing, and is not an error.
* The length is rounded to whole frames: 60 a second. A duration under half a frame, zero or negative plays nothing. Above 546 seconds it plays 32,768 frames.
* A frame is 1/60 second on a TS2068 and 1/50 second on ZEsarUX; `BEEP` counts 60 frames to the second, so on ZEsarUX a note is about 20% longer than asked.
* `BEEP` uses channel A only. It sets channel A's volume to 15, turns its tone on and its noise off, leaving the other bits of the mixer alone, and sets the volume to 0 when the note ends. Channels B and C, the noise and the envelope are not touched.
* BREAK ends a long note and silences the chip.
* The loudspeaker is not used: the sound comes from the AY chip.

**Errors.**

| Mistake | What happens |
|---|---|
| no decimal for the length (`1 BEEP`, or `0 1 BEEP`) | `STACK?`: write `1.0` |
| *n* below -60 or above 69 | nothing: no note, no message |

**See also** `SOUND`, `TONE`, `VOLUME`, [Sound](05_concepts.md#sound), [Floating point](05_concepts.md#floating-point).

---

## BORDER

`( n -- )` -- **word**, graphics

Sets the border colour to *n*, 0 to 7 (see the colours at the head of this part). Only the low three bits of *n* count: 9 gives blue, as 1 does. The border takes the colour at once and keeps it until the next `BORDER`.

```forth
2 BORDER                 \ red border
0 BORDER                 \ black
```

**Notes.**

* `BORDER` does not change the colours of the cells (`INK`, `PAPER`), and `CLS` does not change the border.
* The tape words stripe the border while they work and put it back as it was.

**See also** `INK`, `PAPER`, `CLS`.

---

## BREAK?

`( -- flag )` -- **word**, I/O

Leaves true (-1) while CAPS SHIFT and SPACE are held down, false (0) otherwise. It reads the keyboard itself, so it does not use up the key that `KEY?` and `KEY` see. A program that checks `BREAK?` can finish what it is doing before it stops; otherwise BREAK stops it at once.

```forth
BREAK? .                 \ expect: 0
: WAIT BEGIN BREAK? UNTIL ;
\ break: after 30000
WAIT 5 .                 \ expect: 5
```

**Notes.**

* The `\ break:` line is for the test, which holds the keys down for you after 30,000 instructions; at the keyboard you hold CAPS SHIFT and SPACE.
* BREAK itself is acted on about two frames after the keys go down, so a loop that checks `BREAK?` ends first, with `OK` and not the BREAK message.

**See also** `KEY?`, `CATCH`, [Break](05_concepts.md#break).

---

## BRIGHT

`( n -- )` -- **word**, graphics

Chooses bright (1) or normal (0) colours for what is drawn and printed from now on. Only bit 0 of *n* counts: 2 is 0 and 3 is 1. It does not change the other colour settings, nor what is already on the screen.

```forth
1 BRIGHT CLS 22528 C@ .  \ expect: 120
0 BRIGHT CLS 22528 C@ .  \ expect: 56
```

**Notes.**

* The attribute of a cell is `INK` + 8 * `PAPER` + 64 * `BRIGHT` + 128 * `FLASH`; 56 is black ink on white paper, the colours at switch-on, and bright adds 64.

**See also** `INK`, `PAPER`, `FLASH`, `CLS`.

---

## CIRCLE

`( x y r -- )` -- **EXROM word**, graphics

Draws the outline of a circle of radius *r* pixels with its centre at pixel (*x*, *y*), in the current ink, paper, bright and flash. The part of the circle that is off the screen is not drawn: *x*, *y* and *r* are signed numbers, so the centre may be off the screen. A radius of 0 draws the centre point. A negative radius draws nothing.

```forth
CLS 0 18 AT-XY                           \ draws
100 100 30 CIRCLE                       \ draws
19600 C@ .                               \ expect: 32
```

The second line reads the byte of the bitmap that holds the circle's right-most point, pixel (130, 100): bit 5 of the byte at 19600.

**Notes.**

* Each cell the circle touches takes the current colours, as `PLOT` does.
* To colour the inside of a circle, `FILL` it.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and draws nothing. That is a message, not an error: the line goes on, `OK` follows, and the three numbers are taken from the stack as usual.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than three numbers on the stack | `STACK?` |
| a radius below 0 | nothing: nothing is drawn and there is no message |

**See also** `FILL`, `PLOT`, `LINE`, `POLYGON`, [Graphics](05_concepts.md#graphics).

---

## CLS

`( -- )` -- **word**, I/O

Clears the screen to the current paper colour and ink, and moves the print position to column 0 of row 0. The bitmap is cleared and every attribute cell is set to the colours chosen by `INK`, `PAPER`, `BRIGHT` and `FLASH`, so `CLS` keeps the colours you chose, as Sinclair BASIC's does. The border is not changed. In `HIRES` mode the second display file is cleared to the same colours.

```forth
2 INK 3 PAPER CLS 22528 C@ .   \ expect: 26
```

**Notes.**

* Sprites that were shown are forgotten: a `SPRITE-HIDE` after `CLS` does not restore anything.
* The attribute byte is `INK` + 8 * `PAPER` + 64 * `BRIGHT` + 128 * `FLASH`; 22528 is the attribute of the top left cell.

**See also** `INK`, `PAPER`, `AT-XY`, [Screen](05_concepts.md#screen).

---

## CR

`( -- )` -- **word**, I/O

Moves the print position to column 0 of the next row. It is `13 EMIT`. Below row 22 the output scrolls up one row, and the new bottom row is cleared to the current colours.

```forth
65 EMIT CR 66 EMIT       \ expect: A|B
```

**See also** `EMIT`, `SPACE`, `AT-XY`.

---

## EMIT

`( c -- )` -- **word**, I/O

Prints the character with code *c* at the print position, in the current ink, paper, bright and flash, and moves the position one column to the right. After column 31 it moves to the start of the next row. Code 13 starts a new line instead of printing a glyph (see `CR`). Printing below row 22 scrolls the output up a row.

```forth
72 EMIT 73 EMIT          \ expect: HI
CLS 0 0 AT-XY 143 EMIT   \ draws
16384 C@ . 16640 C@ .    \ expect: 255 255
```

**Notes.**

* *c* is taken as a byte: 321 prints the same as 65.
* The glyphs: codes 32 to 126 are the ASCII characters; 128 to 143 are the 16 block graphics (the low four bits of the code choose the quarters of the cell: bit 0 top right, bit 1 top left, bit 2 bottom right, bit 3 bottom left); 144 to 164 are the 21 user-defined graphics (see `UDG`). Every other code (0 to 31 other than 13, 127, 165 to 255) prints a blank and moves on.
* `EMIT` writes the cell's attribute with the glyph; `PLOT` and `LINE` colour cells in the same way.

**Errors.**

| Mistake | What happens |
|---|---|
| an empty stack | `STACK?` |

**See also** `.`, `TYPE`, `CR`, `UDG`, [Characters and keys](05_concepts.md#characters-and-keys), [Screen](05_concepts.md#screen).

---

## ENVELOPE

`( period shape -- )` -- **word**, sound

Sets the AY chip's envelope generator: *period* (16 bits) goes to registers 11 and 12 and *shape* (the low four bits) to register 13. The envelope changes a channel's volume over time, and has effect only for a channel whose volume register has bit 4 set; `VOLUME` always clears that bit, so switch it on with `SOUND`: `8 16 SOUND` for channel A.

```forth
: AY@ 245 OUT 246 IN ;
1000 14 ENVELOPE
11 AY@ . 12 AY@ . 13 AY@ .       \ expect: 232 3 14
8 16 SOUND  254 MIXER               \ channel A follows it
0 400 TONE
8 0 SOUND                          \ silent again
```

**Notes.**

* *shape* is passed through as the chip's four bits (continue, attack, alternate, hold).

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |

**See also** `SOUND`, `VOLUME`, `TONE`, [Sound](05_concepts.md#sound).

---

## FILL

`( x y -- )` -- **EXROM word**, graphics

Floods the region of the screen that contains pixel (*x*, *y*): every pixel joined to it, up, down, left or right, through pixels with the same value as it (all set, or all clear), is set, and the cells they fall in take the current ink, paper, bright and flash. Used inside a closed outline, it fills the shape. Used on the empty screen, it fills the whole screen.

```forth
CLS 0 18 AT-XY 50 50 20 CIRCLE           \ draws
2 INK 50 50 FILL                         \ draws
17094 C@ . 16384 C@ .                    \ expect: 255 0
22726 C@ .                               \ expect: 58
```

The circle is closed, so the fill stays inside it: the byte at 17094 (pixels 48 to 55 of row 50) is all set and the byte at 16384 (the top left corner) is clear. 22726 is the attribute of the cell at row 6, column 6, inside the circle: ink 2 on white paper.

**Notes.**

* A seed off the screen (*x* not 0 to 255, or *y* not 0 to 191) does nothing, and so does `FILL` in `HIRES` mode.
* The fill always completes, however complicated the shape, and BREAK stops it.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and draws nothing. That is a message, not an error: the line goes on, `OK` follows, and the two numbers are taken from the stack as usual.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |

**See also** `CIRCLE`, `POLYGON-FILL`, `RECT`, `HIRES`, [Graphics](05_concepts.md#graphics).

---

## FLASH

`( n -- )` -- **word**, graphics

Chooses flashing (1) or steady (0) colours for what is drawn and printed from now on. Only bit 0 of *n* counts. A flashing cell swaps its ink and paper in turn. It does not change the other colour settings, nor what is already on the screen.

```forth
1 FLASH CLS 22528 C@ .   \ expect: 184
0 FLASH CLS 22528 C@ .   \ expect: 56
```

**Notes.**

* Flash adds 128 to a cell's attribute byte: 184 is 56 + 128.

**See also** `BRIGHT`, `INK`, `PAPER`, `CLS`.

---

## HIRES

`( -- )` -- **word**, graphics

Switches the screen to high-resolution colour: the same 256 by 192 pixels, but each row of 8 pixels has its own ink and paper, instead of one pair for each 8 by 8 cell. The colours of a row of 8 pixels are kept in the second display file, which `HIRES` clears to white paper and black ink. The bitmap is not changed. `NORMAL` goes back.

```forth
HIRES
1 INK 10 100 PLOT
6 INK 10 101 PLOT
27777 C@ 7 AND .             \ expect: 1
28033 C@ 7 AND .             \ expect: 6
NORMAL
```

The two pixels are in the same 8 by 8 cell but on different pixel rows, and have different inks: 27777 and 28033 are their colour bytes in the second display file.

**Notes.**

* `PLOT`, `LINE`, `CIRCLE` and `POLYGON` colour the row of 8 pixels they draw in. `FILL` does nothing in `HIRES`.
* `CLS` in `HIRES` mode clears the second display file to the current colours.
* A mode change forgets which sprites are shown.
* The mode change is not interrupted by BREAK: it finishes first.

**See also** `NORMAL`, `PLOT`, `CLS`, [Graphics](05_concepts.md#graphics).

---

## IN

`( port -- c )` -- **word**, I/O

Reads one byte from the Z80 port numbered *port* and leaves it, 0 to 255. All 16 bits of *port* go to the processor, so the high byte can select a keyboard half-row as it does in Sinclair BASIC's `IN`.

```forth
8 245 OUT 12 246 OUT     \ the sound chip: register 8 gets 12
8 245 OUT 246 IN .       \ expect: 12
32766 IN 31 AND .        \ expect: 31
```

**Notes.**

* Port 245 selects a sound chip register, port 246 reads and writes it. The second example reads back what the first wrote.
* 32766 reads the keyboard row of SPACE, M, N, B (and SYMBOL SHIFT); bits 0 to 4 are 0 for a key held down. With nothing pressed they are all 1, so the last example prints 31. This is what the emulator gives with no key down.
* Nothing is checked: any port can be read, and reading some ports has effects.

**See also** `OUT`, `KEY`, `STICK`.

---

## INK

`( n -- )` -- **word**, graphics

Chooses the ink colour, 0 to 7, for what is drawn and printed from now on: `EMIT`, `PLOT`, `LINE` and the shapes use it. Only the low three bits of *n* count: 9 is the same as 1. It does not change the paper, bright or flash settings, nor anything already on the screen.

```forth
2 INK CLS 22528 C@ .     \ expect: 58
9 INK CLS 22528 C@ .     \ expect: 57
0 INK
```

**Notes.**

* Ink 0 is black and 7 is white. `CLS` sets every cell to the colours chosen.

**See also** `PAPER`, `BRIGHT`, `FLASH`, `CLS`, `BORDER`.

---

## INPUT

`( -- n )` -- **word**, I/O

Reads a line of at most eight characters from the keyboard as `ACCEPT` does, and leaves its value as a decimal integer, as `VAL` reads it. A line that is empty, or has anything but digits and a leading minus sign in it, gives 0. A value that does not fit in a cell wraps round: `40000` gives -25536.

```forth
\ keys: 123\r
INPUT 2 * .              \ expect: 123246
\ keys: ABC\r
INPUT .                  \ expect: ABC0
\ keys: 40000\r
INPUT .                  \ expect: 40000-25536
```

**Notes.**

* The characters you type are shown at the print position, as with `ACCEPT`. A ninth character is ignored.
* ENTER does not move printing to a new row: `CR` after `INPUT` starts the next output on the row below.
* A number with a decimal point is not a number to `INPUT`: `12.5` gives 0.

**See also** `ACCEPT`, `VAL`, `KEY`.

---

## KEY

`( -- c )` -- **word**, I/O

Waits for a key and leaves its code. The key is not shown. Letters give their lower-case ASCII codes unless CAPS SHIFT is held; ENTER gives 13, DELETE (CAPS SHIFT and 0) gives 8, and the cursor keys (CAPS SHIFT and 5, 6, 7, 8) give 1 (left), 2 (down), 3 (up) and 4 (right).

```forth
: ASK ." KEY: " KEY . ;
\ keys: A
ASK                      \ expect: KEY: 65
\ keys: \r
KEY .                    \ expect: 13
```

**Notes.**

* A key that was pressed before `KEY` ran and not yet read is the one `KEY` gives; `KEY?` says whether there is one.
* A key that has no meaning on the TS2068 keyboard gives 0.
* BREAK (CAPS SHIFT and SPACE) is never given to the program: it stops the wait with the BREAK message.
* The `\ keys:` lines give the test the key to press.

**See also** `KEY?`, `ACCEPT`, `BREAK?`, [Characters and keys](05_concepts.md#characters-and-keys).

---

## KEY?

`( -- flag )` -- **word**, I/O

Leaves true (-1) if a key has been pressed and not yet read, false (0) if not. It does not wait and does not use the key up, so `KEY? IF KEY ... THEN` reads it.

```forth
KEY? .                   \ expect: 0
: G KEY? IF KEY ELSE 0 THEN ;
G .                      \ expect: 0
```

**See also** `KEY`, `BREAK?`, [Characters and keys](05_concepts.md#characters-and-keys).

---

## LINE

`( x1 y1 x2 y2 -- )` -- **word**, graphics

Draws a straight line from pixel (*x1*, *y1*) to pixel (*x2*, *y2*), both end points included, in the current ink, paper, bright and flash. The numbers are signed, and only the part of the line that is on the screen is drawn: the line from (0, 0) to (510, 382) is the diagonal of the screen.

```forth
CLS 0 5 AT-XY 0 0 31 0 LINE              \ draws
16384 C@ . 16387 C@ .            \ expect: 255 255
16388 C@ .                       \ expect: 0
-10 1 300 1 LINE                         \ draws
16640 C@ . 16671 C@ .                    \ expect: 255 255
```

The first line draws along the top row of pixels: the bytes at 16384 to 16387 are the first 32 pixels, all set, and 16388 is clear. The second is clipped to the screen and fills the second row of pixels, from its first byte (16640) to its last (16671).

**Notes.**

* Each cell the line touches takes the current colours.
* The pixels are set, never toggled: a line drawn twice looks the same.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than four numbers on the stack | `STACK?` |

**See also** `PLOT`, `RECT`, `POLYGON`, `CIRCLE`, [Graphics](05_concepts.md#graphics).

---

## LLIST

`( -- )` -- **word**, printer

Prints on the ZX Printer the names of the words you have defined, one name to a line, the newest first. The ROM's own words are not listed. With nothing defined it prints nothing.

```forth
: SQUARE DUP * ;
: CUBE DUP SQUARE * ;
LLIST
```

**Notes.**

* Only the names are printed, not the definitions.
* With no printer attached the word returns at once and prints nothing; there is no error. This is what happens in the emulator the ROM is tested in.
* The characters are drawn from the same font as the screen.

**See also** `LPRINT`, `LIST-DEFS`, `VLIST`, [The printer](05_concepts.md#the-printer).

---

## LOAD-LIB

`( "name" -- )` -- **word**, storage

Loads the dictionary image that `SAVE-LIB` wrote to tape under *name*, and **replaces** your whole dictionary with it. Without a name, it loads the first dictionary image on the tape. The tape is searched from where it is playing: other tapes and images, and images with other names, are skipped. Type it at the prompt, not in a definition: it overwrites the dictionary, including the definition that called it.

```text
LOAD-LIB DEMO            start the tape playing, then press ENTER
4 DOUBLER .              the words saved are there: 8
```

The tape is not there in the forth tests, so the test shows what `LOAD-LIB` does without one: it keeps looking until BREAK stops it, which `CATCH` reports as -28 (the keys are pressed by the test's `\ break:` line; at a keyboard you hold CAPS SHIFT and SPACE).

```forth
: DOUBLER DUP + ;
\ break: after 300000
' LOAD-LIB CATCH DEMO .  \ expect: -28
4 DOUBLER .              \ expect: 8
```

The name follows `CATCH`, because that is where `LOAD-LIB` runs and reads it. The failed load changed nothing, so `DOUBLER` is still there.

**Notes.**

* An image is tied to the exact ROM that saved it: it holds ROM addresses. A tape from another version of the ROM is refused before anything is read, as `TAPE ERROR`. Source text (`SAVE-TEXT`) is the format that outlives a new ROM. The image saved by a cartridge build loads into the Home ROM of the same release, and the other way round.
* A tape that is refused at the header (another ROM, too long for the dictionary) leaves the dictionary as it was. A tape that fails after the data began to arrive, or whose check value (CRC) is wrong, leaves an empty dictionary: your own words are gone, the ROM's are not.
* The name is cut to 10 characters. With no tape playing the search gives up after about two minutes with `TAPE ERROR`.
* SPACE (BREAK) stops the load promptly: `BREAK`, or -28 under `CATCH`.
* `SAVE-LIB` does not save the user-defined graphics (`UDG`).

**Errors.**

| Mistake | What happens |
|---|---|
| no matching tape, a damaged tape, or an image of another ROM | `TAPE ERROR` (-37) |
| SPACE or BREAK pressed | `BREAK` (-28) |

**See also** `SAVE-LIB`, `VERIFY-LIB`, `LOAD-TEXT`, `CATCH`, [Tapes](05_concepts.md#tapes), [Errors](05_concepts.md#errors).

---

## LOAD-TEXT

`( "name" -- )` -- **word**, storage

Loads the source text that `SAVE-TEXT` wrote to tape under *name* into the line store, replacing what it held, and then interprets it as if you had typed it at the prompt: its definitions are compiled and its other lines run. Without a name, it loads the first text on the tape. When the text has run, the rest of the line you typed goes on.

```text
LOAD-TEXT DEMO           start the tape playing, then press ENTER
```

With no tape, the load keeps looking for about two minutes, then reports `TAPE ERROR`:

```forth
LOAD-TEXT DEMO           \ expect: TAPE ERROR
```

BREAK stops it at once, and under `CATCH` that is -28:

```forth
\ break: after 300000
' LOAD-TEXT CATCH DEMO . \ expect: -28
```

**Notes.**

* A text tape holds the lines of the line store, each ended by a carriage return (13); the whole text is at most 8,192 bytes, and a longer one is refused as `TAPE ERROR`. If the last byte is not a return, one is added.
* An error in the loaded text (an unknown word, an uncaught `THROW`, `ABORT`) prints its message and stops the load, and the rest of your line is not run. What was compiled before it stays.
* The line you type to run `LOAD-TEXT` is not part of the text. The text now in the store is what `EDIT` shows and `SAVE-TEXT` saves.
* Text is not tied to the ROM: a text tape loads into any version.
* The name is cut to 10 characters.

**Errors.**

| Mistake | What happens |
|---|---|
| no matching tape, a damaged tape, or a text over 8,192 bytes | `TAPE ERROR` (-37) |
| SPACE or BREAK pressed | `BREAK` (-28) |
| a mistake in the loaded text | its own message, as if typed |

**See also** `SAVE-TEXT`, `VERIFY-TEXT`, `EDIT`, `LOAD-LIB`, [The editor and the line store](05_concepts.md#the-editor-and-the-line-store), [Tapes](05_concepts.md#tapes).

---

## LPRINT

`( addr len -- )` -- **word**, printer

Prints the *len* characters at *addr* on the ZX Printer, 32 to a line: a longer text goes on over as many lines as it needs, and the last line is padded with spaces. *len* = 0 prints one blank line. Characters with no glyph (control codes) print as blanks.

```forth
S" HELLO, PRINTER" LPRINT
CREATE LINE 5 ALLOT
72 LINE C!  73 LINE 1+ C!
LINE 2 LPRINT
```

**Notes.**

* With no printer attached the word returns at once and prints nothing; there is no error. This is what happens in the emulator the ROM is tested in.
* *len* is a full cell, not a byte, so a text of any length can be printed.

**See also** `LLIST`, `TYPE`, `S"`, [The printer](05_concepts.md#the-printer).

---

## MIXER

`( mask -- )` -- **word**, sound

Writes *mask* to the AY chip's mixer, register 7, which chooses what each channel plays. A 0 bit switches a source on: bits 0, 1 and 2 are the tones of channels A, B and C, bits 3, 4 and 5 their noise. Bits 6 and 7 are not sound (the chip's I/O port direction); leave them 1. `253 MIXER` plays channel B's tone only; `255 MIXER` plays nothing.

```forth
: AY@ 245 OUT 246 IN ;
253 MIXER  7 AY@ .       \ expect: 253
-1 MIXER   7 AY@ .       \ expect: 255
```

**Notes.**

* The mask is written as it is, low byte only.
* `BEEP` changes only the bits for channel A.

**See also** `TONE`, `VOLUME`, `NOISE`, `SOUND`, [Sound](05_concepts.md#sound).

---

## NOISE

`( period -- )` -- **word**, sound

Sets the period of the AY chip's noise generator, 0 to 31 (the low five bits of *period* go to register 6). There is one noise generator, shared by all three channels; `MIXER` switches it onto a channel.

```forth
: AY@ 245 OUT 246 IN ;
15 NOISE  6 AY@ .        \ expect: 15
33 NOISE  6 AY@ .        \ expect: 1
```

**Notes.**

* The noise is heard only when the mixer has the noise bit of a channel at 0, and that channel's volume is above 0. For a burst of noise on channel A: `247 MIXER  0 15 VOLUME`, then `0 0 VOLUME` to stop.

**See also** `MIXER`, `VOLUME`, `SOUND`, [Sound](05_concepts.md#sound).

---

## NORMAL

`( -- )` -- **word**, graphics

Switches the screen back to the ordinary mode after `HIRES`: one ink and paper for each 8 by 8 cell. The bitmap is not changed.

```forth
HIRES NORMAL
3 INK 100 100 PLOT
22924 C@ 7 AND .        \ expect: 3
```

22924 is the attribute of the cell that holds pixel (100, 100).

**Notes.**

* Shown sprites are forgotten, as with `HIRES`.

**See also** `HIRES`, `CLS`.

---

## OUT

`( c port -- )` -- **word**, I/O

Writes the low byte of *c* to the Z80 port numbered *port*. All 16 bits of *port* go to the processor.

```forth
8 245 OUT 12 246 OUT     \ sound chip register 8 (channel A volume) gets 12
8 245 OUT 246 IN .       \ expect: 12
8 245 OUT 0 246 OUT     \ and back to 0: silent
```

**Notes.**

* Nothing is checked: any port can be written, as in Sinclair BASIC's `OUT`.
* Port 245 selects a sound chip register and port 246 reads or writes it; `SOUND` does the same with the register number checked. Port 254 holds the border colour in its bits 0 to 2; `BORDER` is the word for that.

**See also** `IN`, `SOUND`, `BORDER`.

---

## PALETTE

`( index value -- )` -- **word**, graphics

Sets entry *index* (0 to 63) of the ULAplus palette to *value*, a colour packed as `GGGRRRBB`: three bits of green, three of red, two of blue. It takes effect when ULAplus is on (see `ULAPLUS`), and changes every cell that uses that entry at once, with no need to redraw.

```forth
2 252 PALETTE            \ entry 2: green 7, red 7, blue 0 (yellow)
1 ULAPLUS
0 ULAPLUS
```

**Notes.**

* Neither number is checked: they go to the ULAplus ports as they are, and *index* above 63 is not an entry.
* ULAplus is not part of the stock TS2068. The words write to the ULAplus ports, which on a machine without it do nothing. The emulators the ROM is tested in provide it. See [ULAplus](05_concepts.md#ulaplus) for which entry each ink and paper colour uses.
* The entry cannot be read back, so the example prints nothing.

**See also** `ULAPLUS`, `INK`, `PAPER`, [ULAplus](05_concepts.md#ulaplus).

---

## PAPER

`( n -- )` -- **word**, graphics

Chooses the paper colour, 0 to 7, for what is drawn and printed from now on. Only the low three bits of *n* count: 9 is the same as 1. It does not change the ink, bright or flash settings, nor anything already on the screen.

```forth
5 PAPER 0 INK CLS 22528 C@ .             \ expect: 40
7 PAPER CLS 22528 C@ .                   \ expect: 56
```

**Notes.**

* The paper adds 8 times its number to a cell's attribute byte: cyan paper (5) and black ink gives 40.

**See also** `INK`, `BRIGHT`, `FLASH`, `CLS`, `BORDER`.

---

## PLOT

`( x y -- )` -- **word**, graphics

Sets the pixel at column *x* (0 to 255, from the left) and row *y* (0 to 191, from the **top**), and gives the cell that holds it the current ink, paper, bright and flash. A pixel is only set, never cleared: plotting a set pixel changes nothing but the cell's colours. A point off the screen is not drawn, and is not an error.

```forth
CLS 0 5 AT-XY 0 0 PLOT                   \ draws
16384 C@ .                               \ expect: 128
255 191 PLOT  22527 C@ .                 \ expect: 1
300 0 PLOT  16389 C@ .                   \ expect: 0
```

The first pixel is the top left corner, the leftmost bit of the byte at 16384. The second is the bottom right corner, the last bit of the byte at 22527. The third, with *x* above 255, draws nothing (a wrapped *x* of 44 would have set a bit in the byte at 16389).

**Notes.**

* Sinclair BASIC's `PLOT` counts *y* up from the bottom of the screen; here it counts down from the top.
* There is no word that clears a single pixel: `CLS` clears them all.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |
| *x* or *y* off the screen | nothing: no pixel, no message |

**See also** `LINE`, `RECT`, `INK`, `PAPER`, [Graphics](05_concepts.md#graphics).

---

## POLYGON

`( x1 y1 x2 y2 ... xn yn n -- )` -- **EXROM word**, graphics

Draws the outline of a closed shape with *n* corners, 3 to 12, at the pixels (*x1*, *y1*) to (*xn*, *yn*): a line from each corner to the next and from the last back to the first, in the current ink, paper, bright and flash. The first pair is deepest on the stack, the count *n* on top. An *n* below 3 or above 12 draws nothing and takes only *n* from the stack.

```forth
CLS 0 18 AT-XY                           \ draws
: TRI 100 40 140 40 100 80 3 ;
TRI POLYGON                              \ draws
16559 C@ .                               \ expect: 255
10 10 20 20 2 POLYGON  . . . .           \ expect: 20 20 10 10
```

The triangle's top edge runs along row 40, from x = 100 to 140; 16559 is the byte of that row that holds pixels 120 to 127, all set. The second line gives `POLYGON` two corners: it refuses, and the four numbers are still on the stack for the four `.`.

**Notes.**

* Each corner is a pair of bytes, kept as the low 8 bits of its numbers: a number above 255 or below 0 wraps (300 is 44), where `LINE` clips.
* Each edge is drawn as `LINE` draws it.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and draws nothing. That is a message, not an error: the line goes on, `OK` follows, and the numbers are taken from the stack as usual.

**Errors.**

| Mistake | What happens |
|---|---|
| *n* below 3 or above 12 | nothing is drawn; only *n* is taken from the stack |
| fewer numbers than 2 * *n* + 1 on the stack | `STACK?` |

**See also** `POLYGON-FILL`, `LINE`, `RECT`, [Graphics](05_concepts.md#graphics).

---

## POLYGON-FILL

`( x1 y1 x2 y2 ... xn yn n -- )` -- **EXROM word**, graphics

Fills the inside of the shape whose corners are (*x1*, *y1*) to (*xn*, *yn*), 3 to 12 corners, in the current ink, paper, bright and flash. Its arguments are those of `POLYGON`, but no outline is drawn. A point is inside if a line from it crosses the edges an odd number of times (the even-odd rule), so a shape whose edges cross itself has holes.

```forth
CLS 0 18 AT-XY                           \ draws
: TRI 100 40 140 40 100 80 3 ;
TRI POLYGON-FILL                         \ draws
17101 C@ . 17105 C@ .                    \ expect: 255 0
```

The triangle is 41 pixels wide at row 40 and narrows to a point at row 80. At row 50 it spans pixels 100 to 130: the byte at 17101 (pixels 104 to 111) is all set and the byte at 17105 (pixels 136 to 143) is clear.

**Notes.**

* Corners are bytes, as for `POLYGON`. An *n* outside 3 to 12 draws nothing and takes only *n* from the stack.
* A shape with an angle that is not convex may be a pixel out near that angle.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and draws nothing. That is a message, not an error: the line goes on, `OK` follows, and the numbers are taken from the stack as usual.

**Errors.**

| Mistake | What happens |
|---|---|
| *n* below 3 or above 12 | nothing is drawn; only *n* is taken from the stack |
| fewer numbers than 2 * *n* + 1 on the stack | `STACK?` |

**See also** `POLYGON`, `FILL`, `RECT`, [Graphics](05_concepts.md#graphics).

---

## RECT

`( x0 y0 x1 y1 -- )` -- **EXROM word**, graphics

Fills the rectangle whose opposite corners are pixels (*x0*, *y0*) and (*x1*, *y1*), both corners included and given in either order, with ink, and gives the cells it covers the current ink, paper, bright and flash. Pixels are set, never cleared. The corners may be off the screen: the part of the rectangle on it is drawn, and one wholly off it draws nothing.

```forth
CLS 0 10 AT-XY 8 0 15 1 RECT             \ draws
16385 C@ . 16641 C@ .            \ expect: 255 255
16897 C@ .                       \ expect: 0
-8 0 3 0 RECT                            \ draws
16384 C@ .                               \ expect: 240
300 0 310 7 RECT                         \ draws
16389 C@ .                               \ expect: 0
```

The first rectangle is the 8 pixels from x = 8 to 15 on rows 0 and 1: one whole byte on each of two pixel rows (16385 and 16641), and nothing on row 2 (16897). The second runs from x = -8 to 3, so only x = 0 to 3 is drawn: the left half of the first byte (240). The third is wholly off the screen, and draws nothing.

**Notes.**

* The rectangle is solid ink: its pixels are set. `RECT` does not clear an area; `CLS` does.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and draws nothing. That is a message, not an error: the line goes on, `OK` follows, and the four numbers are taken from the stack as usual.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than four numbers on the stack | `STACK?` |
| a corner off the screen | not an error: the part on the screen is drawn |

**See also** `LINE`, `FILL`, `PLOT`, `POLYGON-FILL`, [Graphics](05_concepts.md#graphics).

---

## SAVE-LIB

`( "name" -- )` -- **word**, storage

Writes your whole dictionary, everything you have defined since switch-on or the last `LOAD-LIB`, to tape as a dictionary image under *name* (up to 10 characters; longer names are cut). The ROM's own words are not written. Later `LOAD-LIB` brings the words back, ready to run, much faster than `SAVE-TEXT`'s source can be compiled.

```text
SAVE-LIB DEMO            start the recorder, then press ENTER
VERIFY-LIB DEMO          rewind the tape, play it, then press ENTER: no error means it is good
```

The test has no tape; it saves into the void, which finishes, and shows the BREAK of a save:

```forth
: DOUBLER DUP + ;
SAVE-LIB DEMO
' SAVE-LIB CATCH DEMO .  \ expect: 0
\ break: after 300000
' SAVE-LIB CATCH DEMO .  \ expect: -28
```

**Notes.**

* The tape holds a header, a gap of one second and then the dictionary, at standard Spectrum speed: the longer your dictionary, the longer the tape.
* The image is tied to the exact ROM that saved it (see `LOAD-LIB`). Only a few bytes after the end of the dictionary are used, as working space.
* Anything you define after `SAVE-LIB` is not on the tape.
* SPACE (BREAK) stops the save before the data block is sent: `BREAK`, or -28 under `CATCH`.
* `SAVE-LIB` does not save the user-defined graphics (`UDG`): define them in the program.

**Errors.**

| Mistake | What happens |
|---|---|
| SPACE or BREAK pressed | `BREAK` (-28) |
| the dictionary is so full that the image's check value does not fit | `DICTIONARY FULL` (-8), nothing is sent |

**See also** `LOAD-LIB`, `VERIFY-LIB`, `SAVE-TEXT`, `CATCH`, [Tapes](05_concepts.md#tapes), [The dictionary](05_concepts.md#the-dictionary).

---

## SAVE-TEXT

`( "name" -- )` -- **word**, storage

Writes the line store, the source lines you have typed and committed (see `EDIT`), to tape under *name* (up to 10 characters; longer names are cut), one carriage-return-ended line after another. The line holding the `SAVE-TEXT` command is not part of it. `LOAD-TEXT` brings the text back and runs it; it loads into any version of the ROM.

```text
SAVE-TEXT DEMO           start the recorder, then press ENTER
VERIFY-TEXT DEMO         rewind the tape, play it, then press ENTER: no error means it is good
```

The test has no tape; it saves into the void, which finishes, and shows the BREAK of a save:

```forth
: SQUARE DUP * ;
SAVE-TEXT DEMO
' SAVE-TEXT CATCH DEMO . \ expect: 0
\ break: after 300000
' SAVE-TEXT CATCH DEMO . \ expect: -28
```

**Notes.**

* Everything you committed is in the store, not only definitions: a line such as `5 SQUARE .` is saved and runs again when the tape is loaded. Use `EDIT` to take such lines out before you save.
* After the save, every line you type joins the store, so a `VERIFY-TEXT` needs the store as it was at the save; run it straight after.
* SPACE (BREAK) stops the save before the data block is sent.

**Errors.**

| Mistake | What happens |
|---|---|
| SPACE or BREAK pressed | `BREAK` (-28) |

**See also** `LOAD-TEXT`, `VERIFY-TEXT`, `EDIT`, `SAVE-LIB`, [The editor and the line store](05_concepts.md#the-editor-and-the-line-store), [Tapes](05_concepts.md#tapes).

---

## SOUND

`( register value -- )` -- **word**, sound

Writes *value* (its low byte) to register *register* of the AY-3-8912 sound chip, numbered as the chip numbers them, 0 to 15. The chip keeps what it is given until you change it, so a tone goes on after the word that started it has ended. A *register* of 17 or more is ignored: nothing is written.

```forth
: AY@ 245 OUT 246 IN ;
1 7 SOUND  1 AY@ .       \ expect: 7
2 300 SOUND  2 AY@ .     \ expect: 44
17 5 SOUND  256 33 SOUND \ ignored
2 251 SOUND  3 0 SOUND           \ channel B, 439 Hz
7 253 SOUND  9 15 SOUND
9 0 SOUND                \ silent
```

The last two lines play a tone with three writes: channel B's period (251, from `110250 / 439`), the mixer with only B's tone on, and B's volume 15. `9 0 SOUND` ends it.

**Notes.**

* The registers: 0-1, 2-3 and 4-5 are the tone periods of channels A, B and C (low byte, then the top four bits); 6 the noise period; 7 the mixer; 8, 9 and 10 the volumes; 11-12 and 13 the envelope. `TONE`, `VOLUME`, `MIXER`, `NOISE` and `ENVELOPE` do these writes for you.
* The chip's clock makes the tone frequency 110,250 / *period* Hz.
* Register 16 is accepted and selects none of the chip's registers.
* The pair lists of Sinclair BASIC's `SOUND` are not supported: one register and one value at a time.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |
| *register* 17 or more | nothing: nothing is written |

**See also** `TONE`, `VOLUME`, `MIXER`, `NOISE`, `ENVELOPE`, `BEEP`, [Sound](05_concepts.md#sound).

---

## SPACE

`( -- )` -- **word**, I/O

Prints one space at the print position. It is `32 EMIT`.

```forth
65 EMIT SPACE 66 EMIT    \ expect: A B
```

**See also** `SPACES`, `EMIT`, `CR`.

---

## SPACES

`( n -- )` -- **word**, I/O

Prints *n* spaces. With *n* = 0 it prints nothing.

```forth
65 EMIT 3 SPACES 66 EMIT \ expect: A   B
0 SPACES                 \ prints nothing
```

**Notes.**

* A space is drawn like any character: it blanks the cell and gives it the current colours, so `SPACES` paints a bar of paper colour.
* *n* is not checked as positive: a negative *n* is read as a large unsigned number and prints about 65,000 spaces, scrolling the screen as it goes. BREAK stops it.

**Errors.**

| Mistake | What happens |
|---|---|
| an empty stack | `STACK?` |

**See also** `SPACE`, `EMIT`, `AT-XY`.

---

## SPRITE-DEFINE

`( slot row col -- )` -- **EXROM word**, graphics

Captures the picture on the screen at text row *row*, column *col* as the image of sprite *slot* (0 to 3). A sprite is 2 by 2 character cells, 16 by 16 pixels: the cells at (*row*, *col*), (*row*, *col* + 1), (*row* + 1, *col*) and (*row* + 1, *col* + 1), with their colours. Draw the picture on the screen with `EMIT`, `PLOT`, `RECT` or anything else, define it, and show it anywhere with `SPRITE-SHOW`.

```forth
: BOX 143 EMIT 143 EMIT ;
CLS 5 5 AT-XY BOX                        \ draws
5 6 AT-XY BOX                             \ draws
0 5 5 SPRITE-DEFINE
CLS 0 18 AT-XY                           \ draws
0 10 10 SPRITE-SHOW                      \ draws
18506 C@ .                              \ expect: 255
0 SPRITE-HIDE                            \ draws
18506 C@ .                              \ expect: 0
```

The picture is four block-graphic cells, all ink (code 143). The sprite is shown at row 10, column 10; 18506 is the first byte of that cell. Hiding it puts back the empty screen.

**Notes.**

* *slot* above 3 does nothing, and so does a position whose four cells are not all on the screen: *row* above 22 or *col* above 30 (or a negative one).
* The sprite is a copy of the screen, cells and colours, not a mask: showing it replaces what is under it, and hiding it puts that back.
* `SPRITE-DEFINE` may be used again on a slot to replace its image.
* BREAK is held off until the word has finished.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and does nothing. That is a message, not an error: the line goes on, `OK` follows, and the three numbers are taken from the stack as usual.

**See also** `SPRITE-SHOW`, `SPRITE-HIDE`, `CLS`, [Graphics](05_concepts.md#graphics).

---

## SPRITE-HIDE

`( slot -- )` -- **EXROM word**, graphics

Puts back the picture that `SPRITE-SHOW` covered with the sprite in *slot*, at the place it was shown. After this the sprite is no longer shown. It does nothing if the slot is not shown, or is more than 3.

```forth
CLS 5 5 AT-XY 143 EMIT                                           \ draws
0 5 5 SPRITE-DEFINE
CLS 0 18 AT-XY                           \ draws
0 10 10 SPRITE-SHOW                      \ draws
18506 C@ .                              \ expect: 255
0 SPRITE-HIDE                            \ draws
18506 C@ .                              \ expect: 0
0 SPRITE-HIDE                                                    \ nothing: it is hidden
```

**Notes.**

* To move a sprite, hide it and show it at the new place.
* `CLS`, `HIRES` and `NORMAL` forget that sprites are shown: a `SPRITE-HIDE` after them restores nothing, because the screen they changed is not what the sprite covered.
* BREAK is held off until the word has finished.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and does nothing. That is a message, not an error: the line goes on, `OK` follows, and the number is taken from the stack as usual.

**See also** `SPRITE-SHOW`, `SPRITE-DEFINE`.

---

## SPRITE-SHOW

`( slot row col -- )` -- **EXROM word**, graphics

Shows the sprite in *slot* (0 to 3) with its top left cell at text row *row*, column *col*: the screen under it is saved, and the sprite's picture and colours are drawn over it. It does nothing if the slot has no image (see `SPRITE-DEFINE`), if it is already shown, or if *slot* is above 3.

```forth
: BOX 143 EMIT 143 EMIT ;
CLS 5 5 AT-XY BOX                        \ draws
5 6 AT-XY BOX                             \ draws
0 5 5 SPRITE-DEFINE
CLS 0 18 AT-XY                           \ draws
0 10 10 SPRITE-SHOW                      \ draws
18506 C@ .                              \ expect: 255
0 20 20 SPRITE-SHOW                                              \ nothing: slot 0 is shown
0 SPRITE-HIDE                            \ draws
18506 C@ .                              \ expect: 0
```

**Notes.**

* A sprite is shown in one place at a time: `SPRITE-HIDE` it before `SPRITE-SHOW` at another place.
* *row* above 22 or *col* above 30 (or a negative one) does nothing: all four cells must be on the screen.
* BREAK is held off until the word has finished.
* With another EXROM in the machine in place of the graphics one, the word prints `NO EXROM` and does nothing. That is a message, not an error: the line goes on, `OK` follows, and the three numbers are taken from the stack as usual.

**See also** `SPRITE-HIDE`, `SPRITE-DEFINE`, [Graphics](05_concepts.md#graphics).

---

## STICK

`( device -- value )` -- **word**, I/O

Reads a joystick. *device* 1 gives a number from 0 to 15, one bit for each of the four direction lines, with the bit set while that direction is pushed; 0 means none. *device* 2 gives 0 or 1, the state of one line. With no joystick connected both give 0.

```forth
1 STICK .                \ expect: 0
2 STICK .                \ expect: 0
```

**Notes.**

* The joystick lines are the bits of the sound chip's port A (its register 14), read and inverted. If all four direction lines read as pushed at once, which is what an open port gives, device 1 gives 0.
* *device* is not checked: any value other than 1 is read as device 2.
* The emulator the ROM is tested in has no joystick, so the examples show the empty case.

**See also** `KEY`, `IN`, `BREAK?`.

---

## TONE

`( channel period -- )` -- **word**, sound

Sets the pitch of channel *channel* (0 is A, 1 is B, 2 is C) of the AY chip to *period*, 0 to 4095. The note is 110,250 / *period* Hz: `0 251 TONE` is about 439 Hz. A larger period is a lower note. The channel makes no sound until its volume is above 0 (`VOLUME`) and the mixer has its tone on (`MIXER`).

```forth
: AY@ 245 OUT 246 IN ;
0 4095 TONE  0 AY@ . 1 AY@ .             \ expect: 255 15
254 MIXER  0 251 TONE             \ pitch 439 Hz
0 15 VOLUME                              \ A plays
0 0 VOLUME                               \ silent
```

**Notes.**

* Only the low 12 bits of *period* count: 5000 sounds as 904. A *channel* other than 0, 1 or 2 is ignored and nothing is written.

**See also** `VOLUME`, `MIXER`, `SOUND`, `BEEP`, [Sound](05_concepts.md#sound).

---

## TYPE

`( addr len -- )` -- **word**, I/O

Prints the *len* characters that start at *addr*, as if each was given to `EMIT`. *len* is taken as a byte: 0 and 256 print nothing.

```forth
S" HELLO" TYPE           \ expect: HELLO
S" HELLO" DROP 3 TYPE    \ expect: HEL
```

**Notes.**

* `S"` leaves the address and length of its text, which is exactly what `TYPE` takes; so does `COUNT` for a counted string.
* A text with a code that has no glyph prints blanks for it, as `EMIT` does.

**See also** `EMIT`, `S"`, `COUNT`, `."`.

---

## UDG

`( n -- addr )` -- **word**, graphics

Leaves the address of the 8 bytes that draw user-defined graphic *n* (0 to 20). Store the pattern there, one byte for each pixel row from the top, and `EMIT` the code 144 + *n* to draw it.

```forth
255 0 UDG C!  129 0 UDG 1 + C!
255 0 UDG 2 + C!
CLS 0 0 AT-XY 144 EMIT                   \ draws
16384 C@ . 16640 C@ .            \ expect: 255 129
16896 C@ .                       \ expect: 255
1 UDG 0 UDG - .                          \ expect: 8
```

**Notes.**

* The 21 patterns are in RAM: they are blank at switch-on, and they stay until you change them. `SAVE-LIB` does not save them.
* *n* is not checked: 21 and above give an address that nothing draws.

**See also** `EMIT`, `C!`, [Characters and keys](05_concepts.md#characters-and-keys).

---

## ULAPLUS

`( flag -- )` -- **word**, graphics

Turns the ULAplus palette on (when bit 0 of *flag* is 1) or off (when it is 0). With it on, the ink, paper, bright and flash of every cell choose one of 64 colours that `PALETTE` has set, instead of the eight of the ordinary hardware. The colour words and drawing words work as before.

```forth
2 252 PALETTE
1 ULAPLUS                \ on
0 ULAPLUS                \ off: the ordinary eight colours
```

**Notes.**

* ULAplus is not part of the stock TS2068. On a machine without it, the word writes to ports nothing reads and there is no message. The emulators the ROM is tested in provide it.
* Turning it off and on again keeps the palette: the 64 entries are only changed by `PALETTE`.
* The state cannot be read back, so the example prints nothing.

**See also** `PALETTE`, `INK`, `PAPER`, [ULAplus](05_concepts.md#ulaplus).

---

## VERIFY-LIB

`( "name" -- )` -- **word**, storage

Compares the dictionary image on tape named *name* with your dictionary and changes nothing: it finishes quietly if they are the same, and gives `TAPE ERROR` if not. Without a name it checks the first dictionary image on the tape. Run it straight after `SAVE-LIB`, before defining anything else, to know the tape is good: a dictionary that has grown since no longer matches.

```text
SAVE-LIB DEMO            record
VERIFY-LIB DEMO          rewind, play, ENTER: nothing printed means a good tape
```

With no tape, BREAK stops the search, and under `CATCH` that is -28:

```forth
: DOUBLER DUP + ;
\ break: after 300000
' VERIFY-LIB CATCH DEMO .  \ expect: -28
```

**Notes.**

* The image must have the identity of this ROM, the length of your dictionary and the same newest word; any difference is `TAPE ERROR`, even a byte-for-byte good tape of a different dictionary.
* With no tape playing the search gives up after about two minutes with `TAPE ERROR`.
* A few bytes after the end of the dictionary are used as working space.

**Errors.**

| Mistake | What happens |
|---|---|
| no matching tape, a damaged tape, a different dictionary or another ROM's image | `TAPE ERROR` (-37) |
| SPACE or BREAK pressed | `BREAK` (-28) |

**See also** `SAVE-LIB`, `LOAD-LIB`, `VERIFY-TEXT`, [Tapes](05_concepts.md#tapes).

---

## VERIFY-TEXT

`( "name" -- )` -- **word**, storage

Compares the text on tape named *name* with the line store and changes nothing: it finishes quietly if they are the same, and gives `TAPE ERROR` if not. The command line itself is not counted in the store. Without a name it checks the first text on the tape. A tape of a different length is a mismatch.

```text
SAVE-TEXT DEMO           record
VERIFY-TEXT DEMO         rewind, play, ENTER: nothing printed means a good tape
```

With no tape, BREAK stops the search, and under `CATCH` that is -28:

```forth
\ break: after 300000
' VERIFY-TEXT CATCH DEMO . \ expect: -28
```

**Notes.**

* Every line you type after the save joins the store and makes a later verify fail; verify straight after saving.
* With no tape playing the search gives up after about two minutes with `TAPE ERROR`.

**Errors.**

| Mistake | What happens |
|---|---|
| no matching tape, a damaged tape, a text of another length or content | `TAPE ERROR` (-37) |
| SPACE or BREAK pressed | `BREAK` (-28) |

**See also** `SAVE-TEXT`, `LOAD-TEXT`, `VERIFY-LIB`, [Tapes](05_concepts.md#tapes).

---

## VOLUME

`( channel level -- )` -- **word**, sound

Sets the volume of channel *channel* (0 is A, 1 is B, 2 is C) of the AY chip to *level*, 0 (silent) to 15 (loudest). Only the low four bits of *level* count. The volume is fixed: the channel does not follow the envelope.

```forth
: AY@ 245 OUT 246 IN ;
2 15 VOLUME  10 AY@ .    \ expect: 15
2 20 VOLUME  10 AY@ .    \ expect: 4
2 0 VOLUME
```

**Notes.**

* A *channel* other than 0, 1 or 2 is ignored and nothing is written.
* A channel sounds only when the mixer has its tone (or noise) on: `MIXER`.

**See also** `TONE`, `MIXER`, `ENVELOPE`, `SOUND`, [Sound](05_concepts.md#sound).

---
