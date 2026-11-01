# Part 7 -- Practical examples

Complete programs, each of which does something useful or amusing. Type one in, run it, then change it: that is the best way to learn.

**Every program in this part is a test.** The build types each one into a Leap-Forth that has just been switched on, a line at a time, and checks what it prints (see [Appendix G](08_appendices.md#appendix-g-how-this-manual-was-checked)). A comment on a line says what the test requires. `\ expect:` gives everything the line prints, with the rows of the screen joined by `|` and the `OK` left out. `\ draws` marks a line that draws a picture: the test checks that it runs, and you look at the picture. `\ keys:` before a line gives the keys the test presses while that line waits for the keyboard (`\r` is ENTER); when you type the program yourself, you press them. The comments are ignored by Forth, so you can type the lines with them or without.

Each program begins on a machine just switched on: it defines everything it uses. Type its lines one by one, in order. A definition may take several lines, since `:` goes on compiling until `;`; the lines are short so that they fit the row you type on. Programs that print a lot start with `CLS`, so that the output fits on the screen.

---

## 1. A multiplication table

Two loops: the outer one counts the rows, the inner one the columns. `CELL` puts a space before a number below 10 so that the columns line up.

```forth
: CELL ( n -- )
  DUP 10 < IF SPACE THEN . ;
: ROW ( n -- )
  6 1 DO DUP I * CELL LOOP
  DROP CR ;
: TABLE 6 1 DO I ROW LOOP ;
TABLE  \ expect:  1  2  3  4  5| 2  4  6  8 10| 3  6  9 12 15| 4  8 12 16 20| 5 10 15 20 25
```

**How it works.** `TABLE` calls `ROW` once for each row number, 1 to 5 (a `DO` loop stops before its limit, so `6 1 DO` counts 1 to 5). Inside `ROW`, `I` is the column number of its own loop, and `DUP I *` multiplies it by the row number that `ROW` was given. `.` prints a number and a space; `CR` ends the row.

**Things to try.**

* Change both 6s to 10 for a 9 by 9 table: a cell is three characters wide, so nine of them fit on a row.
* Print a heading row of the column numbers first.

## 2. Prime numbers

The sieve of Eratosthenes: cross out the multiples of each number, and what is left is prime. `ARRAY` makes the table of marks, all zero to start with.

```forth
100 ARRAY MARK
: MARKED ( n -- addr )
  CELLS MARK + ;
: CROSS 10 2 DO 100 I DUP + DO
  1 I MARKED ! J +LOOP LOOP ;
: .PRIMES 100 2 DO
  I MARKED @ 0= IF I . THEN
  LOOP ;
CROSS
.PRIMES  \ expect: 2 3 5 7 11 13 17 19 23 29 31 37|41 43 47 53 59 61 67 71 73 79 83| 89 97
```

**How it works.** `MARKED` gives the address of the element for the number *n*. In `CROSS` the outer loop takes *i* from 2 to 9 (any number up to 99 that is not prime has a factor below 10). The inner loop starts at *i* + *i* and steps by *i* up to 99 with `+LOOP`, marking each multiple; there `I` is the multiple and `J` is the outer loop's *i*. It crosses out the multiples of 4, 6 and 8 as well as those of the primes, which does no harm. `.PRIMES` prints each number whose mark is still 0.

**Things to try.**

* Find the primes below 200: make the array 200 long, change the three 100s to 200 and the 10 to 15 (any number below 200 that is not prime has a factor below 15).
* Count the primes instead of printing them: keep the count on the stack in `.PRIMES`.

## 3. Fibonacci numbers

Each number is the sum of the two before it. The program keeps the last two on the stack, under the loop.

```forth
: FIBS ( n -- ) 0 1 ROT 0 DO
  OVER . SWAP OVER +
  LOOP 2DROP ;
12 FIBS  \ expect: 0 1 1 2 3 5 8 13 21 34 55 89
```

**How it works.** `0 1 ROT 0 DO` leaves the first two numbers, 0 and 1, under the loop's limit and index. Each time round, `OVER .` prints the older of the pair, and `SWAP OVER +` turns the pair *a b* into *b* and *a* + *b*. `2DROP` removes the pair when the loop is done.

**Things to try.**

* Try `26 FIBS`: a number is 16 bits, so after 28657 the sum wraps around (the 25th number prints as -19168, not 46368).
* Start from 2 and 1 instead of 0 and 1 (`2 1 ROT 0 DO`): the sequence 2 1 3 4 7 11 18 ... of Lucas numbers.

## 4. Sorting

A bubble sort of eight numbers kept in an `ARRAY`. Each pass compares every pair of neighbours and swaps the pair if it is out of order.

```forth
8 ARRAY NUMS
: NUM ( i -- addr )
  CELLS NUMS + ;
: LOAD8 8 0 DO I NUM ! LOOP ;
: .NUMS 8 0 DO I NUM @ . LOOP ;
48 12 62 5 32 23 7 34 LOAD8
.NUMS  \ expect: 34 7 23 32 5 62 12 48
: ORDER ( i -- )
  DUP NUM @ OVER 1+ NUM @
  2DUP > IF 2 PICK NUM !
  SWAP 1+ NUM !
  ELSE 2DROP DROP THEN ;
: PASS 7 0 DO I ORDER LOOP ;
: SORT 8 0 DO PASS LOOP ;
SORT .NUMS  \ expect: 5 7 12 23 32 34 48 62
```

**How it works.** `NUM` gives the address of element *i*, for `@` and `!`. `LOAD8` stores the eight numbers on the stack into the array, the top one into element 0. `ORDER` fetches element *i* and element *i* + 1; if the first is the larger, `2 PICK` brings *i* up again to store the smaller one in element *i*, and the larger one goes to element *i* + 1 (`ELSE` drops what is left). `PASS` does this for the seven pairs, and `SORT` makes eight passes, more than the seven that are ever needed.

**Things to try.**

* Change `>` to `<` in `ORDER` to sort from the largest down.
* Sort 8 numbers made with `100 RND` (see program 6 for `RANDOMIZE`).

## 5. A secret code

A Caesar cipher: each capital letter is moved along the alphabet by a number of places, and other characters are left alone. The message is in a `STRING`, and the program changes it in place.

```forth
20 STRING MSG
S" HELLO WORLD" MSG PLACE
VARIABLE K
: LETTER? ( c -- flag )
  DUP 64 > SWAP 91 < AND ;
: SHIFT ( c -- c' )
  DUP LETTER? IF 65 - K @ +
  26 MOD 65 + THEN ;
: ENCODE ( n -- ) K !
  MSG COUNT 0 DO MSG 1+ I +
  DUP C@ SHIFT SWAP C! LOOP ;
3 ENCODE MSG COUNT TYPE   \ expect: KHOOR ZRUOG
23 ENCODE MSG COUNT TYPE  \ expect: HELLO WORLD
```

**How it works.** `PLACE` copies the text into `MSG`, which holds up to 20 characters. A character is its code, so `SHIFT` can do arithmetic on the alphabet: it takes 65 (the code of `A`) off a capital letter, adds the shift `K`, wraps at 26 with `MOD` and puts the 65 back. `ENCODE` goes through the characters of `MSG` (`COUNT` gives the address after the length byte and the length); the text of the string starts at `MSG 1+`. Shifting by 3 and then by 23 is a shift by 26, the whole alphabet, so the second line gives the message back.

**Things to try.**

* Use another shift, and decode with 26 minus that number.
* Put a message with small letters in `MSG` and turn it to capitals before encoding it: `MSG COUNT UPPER 2DROP`.

## 6. Guess the number

The computer thinks of a number from 0 to 99 and says whether each guess is too low or too high. `7 RANDOMIZE` starts the random numbers from a fixed place, so that the game is the same every time and the test can be repeated: without it, each switch-on gives a different game. The guesses typed here are 50, 75 and 52.

```forth
VARIABLE N
: HINT ( guess -- )
  N @ < IF ." TOO LOW"
  ELSE ." TOO HIGH" THEN ;
: CHECK ( guess -- flag )
  DUP N @ = IF DROP
  ." RIGHT" -1
  ELSE HINT 0 THEN ;
: GAME 100 RND N ! BEGIN
  ." ? " INPUT CR CHECK CR
  UNTIL ;
7 RANDOMIZE
\ keys: 50\r75\r52\r
GAME  \ expect: ? 50|TOO LOW|? 75|TOO HIGH|? 52|RIGHT
```

**How it works.** `100 RND` is a whole number from 0 to 99, kept in `N`. `INPUT` waits for a line of up to 8 characters, which you end with ENTER, and leaves it as a number; `CR` then moves to the next row. `CHECK` takes the guess: if it equals `N` it prints `RIGHT` and leaves true (-1) to end the `BEGIN ... UNTIL` loop; otherwise `HINT` prints which way the guess is wrong (it is too low if it is less than `N`) and `CHECK` leaves false (0), and the loop asks again.

**Things to try.**

* Count the guesses and print the count at the end.
* Leave out `7 RANDOMIZE` and play a different game each time. Binary search needs at most 7 guesses.

## 7. A menu

A menu shows the choices and runs the one you press. The actions are words, and a table holds their **execution tokens**, which `'` gives and `EXECUTE` runs, so adding a choice is adding a word and an entry.

```forth
: GREET ." HELLO" ;
: SQUARES 5 1 DO I I * . LOOP ;
: BYE ." GOODBYE" ;
CREATE ACTIONS
  ' GREET , ' SQUARES , ' BYE ,
: MENU ." 1 HELLO" CR
  ." 2 SQUARES" CR
  ." 3 BYE" CR ;
: CHOOSE KEY 49 -
  DUP 0 < OVER 2 > OR IF DROP
  ." NO SUCH CHOICE" ELSE
  CELLS ACTIONS + @
  EXECUTE THEN ;
MENU  \ expect: 1 HELLO|2 SQUARES|3 BYE
\ keys: 2
CHOOSE  \ expect: 1 4 9 16
\ keys: 9
CHOOSE  \ expect: NO SUCH CHOICE
```

**How it works.** `CREATE ACTIONS` starts a table, and `' GREET ,` compiles the execution token of `GREET` into it as one cell. `KEY` waits for a key and leaves its code; the code of `1` is 49, so `49 -` makes the choice a table number from 0. `0 <` and `2 >`, joined by `OR`, catch a key outside the menu. Otherwise `CELLS ACTIONS + @` fetches the token and `EXECUTE` runs the word.

**Things to try.**

* Add a fourth choice: define a word that beeps (`: TUNE 0 0.2 BEEP ;`) before `CREATE ACTIONS`, add `' TUNE ,` to the table, add a fourth line to `MENU`, and use `3 >` in place of `2 >`.
* Run the menu and the choice together with `: RUN MENU CHOOSE ;`.

## 8. A temperature table

Degrees Celsius to Fahrenheit, with decimals. A whole number is turned into a decimal with `S>F`, which goes on the float stack; `F.` prints a decimal with the number of places `PLACES` set.

```forth
1 PLACES
: C>F ( n -- ) ( F: -- f )
  S>F 9.0 F* 5.0 F/ 32.0 F+ ;
: ROW ( c -- ) DUP . ." C = "
  C>F F. ." F" CR ;
: TABLE 50 -10 DO I ROW
  10 +LOOP ;
TABLE  \ expect: -10 C = 14.0 F|0 C = 32.0 F|10 C = 50.0 F|20 C = 68.0 F|30 C = 86.0 F|40 C = 104.0 F
```

**How it works.** `C>F` takes a whole number off the data stack and leaves a decimal on the float stack; `F*`, `F/` and `F+` work on that stack and are the decimal forms of `*`, `/` and `+`. `ROW` prints the Celsius number with `.`, then the decimal with `F.`. `1 PLACES` shows one digit after the point. The loop goes from -10 to 40 in steps of 10 (`+LOOP` stops when the index reaches the limit 50).

**Things to try.**

* Try `3 PLACES`, or `0 PLACES`.
* Print the table for 36 to 40 degrees in steps of 1: `: NEAR 41 36 DO I ROW LOOP ;` (`DO` works only inside a definition). With `1 PLACES`, 37 degrees is 98.6.

## 9. Square roots

`FSQRT` takes the square root of a decimal. `PLACES` chooses how many digits to show: here two.

```forth
2 PLACES
: ROOT ( n -- )
  DUP . S>F FSQRT F. CR ;
: ROOTS 11 1 DO I ROOT LOOP ;
ROOTS  \ expect: 1 1.00|2 1.41|3 1.73|4 2.00|5 2.24|6 2.45|7 2.65|8 2.83|9 3.00|10 3.16
```

**How it works.** `ROOT` prints the number, turns a copy of it into a decimal with `S>F`, takes the root and prints it with `F.`. The roots of 1, 4 and 9 are exact; the others are rounded to two places when they are printed.

**Things to try.**

* Try `9 PLACES`, the most there is: the root of 2 is then 1.414213562. A decimal holds about nine digits.
* Print the root of a number with a fraction, such as `2.25 FSQRT F.` (1.50 at two places), or of a large one such as `10000.0`.

## 10. Counting in binary

The numbers 0 to 15 in binary: four bits each, with the bit worth 8 on the left.

```forth
: BIT ( n mask -- )
  AND IF 49 ELSE 48 THEN EMIT ;
: .BIN ( n -- )
  DUP 8 BIT DUP 4 BIT
  DUP 2 BIT 1 BIT ;
: BINARY CLS 16 0 DO
  I . ." = " I .BIN CR LOOP ;
BINARY  \ expect: 0 = 0000|1 = 0001|2 = 0010|3 = 0011|4 = 0100|5 = 0101|6 = 0110|7 = 0111|8 = 1000|9 = 1001|10 = 1010|11 = 1011|12 = 1100|13 = 1101|14 = 1110|15 = 1111
```

**How it works.** `AND` with a mask keeps just one bit of the number, so `BIT` finds out whether that bit is set: the result is not 0 when it is. `EMIT` prints a character by its code: 49 is `1` and 48 is `0`. `.BIN` tries the masks 8, 4, 2 and 1 in turn, keeping a copy of the number with `DUP` and using the last copy up in the final `BIT`. `BINARY` starts with `CLS` so that its 16 rows fit.

**Things to try.**

* Count to 31 with five bits: `DUP 16 BIT` at the start of `.BIN`, and `32 0 DO` in `BINARY`.
* Count down: `0 15 DO ... -1 +LOOP` prints 15 first and 0 last.

## 11. A spiral

A spiral drawn with `LINE`: each point is a little farther from the centre and a little farther round than the one before, and a line joins it to the last. `SIN` and `COS` work in radians.

```forth
VARIABLE X  VARIABLE Y
VARIABLE X2  VARIABLE Y2
: TO ( x y -- ) Y2 ! X2 !
  X @ Y @ X2 @ Y2 @ LINE
  X2 @ X ! Y2 @ Y ! ;
: PT ( i -- x y )
  S>F FDUP 0.6 F* FSWAP 0.2 F*
  FOVER FOVER COS F* F>S 128 +
  SIN F* F>S 96 + ;
: SPIRAL CLS 128 X ! 96 Y !
  150 1 DO I PT TO LOOP ;
SPIRAL  \ draws
```

**How it works.** `X` and `Y` hold the point the pen is at. `TO` draws a `LINE` from there to the new point (the four numbers `LINE` takes are the two points' x and y) and makes the new point the pen. `PT` computes point *i*: its distance from the centre is 0.6 *i* pixels and its angle 0.2 *i* radians, so after about 31 points the spiral has gone once round. Its x is 128 plus the distance times the cosine of the angle, its y is 96 plus the distance times the sine; `F>S` cuts each to a whole number of pixels. After the cosine, the distance and the angle are still on the float stack (`FOVER FOVER` copied them first) for the sine.

**Things to try.**

* Change 0.2 to 0.1 for a loose spiral with fewer turns.
* Draw it in colour: `2 INK` before `SPIRAL`, or a different ink for each turn.

## 12. A bullseye

Circles and flood fills in colour. `CIRCLE` draws the outline of a circle about a centre, and `FILL` floods the area round a point with the current ink, up to the first drawn pixels it meets. The program draws four rings and then fills the space inside and between them.

```forth
: RING ( r colour -- )
  INK 128 96 ROT CIRCLE ;
: BAND ( r colour -- )
  INK 128 + 96 FILL ;
: BULLSEYE CLS
  80 2 RING 60 4 RING
  40 1 RING 20 6 RING
  70 2 BAND 50 4 BAND
  30 1 BAND 10 6 BAND
  0 INK ;
BULLSEYE  \ draws
```

**How it works.** The colours are 2 red, 4 green, 1 blue and 6 yellow. `RING` sets the ink and draws a circle of the radius around the middle of the screen, (128, 96). `BAND` sets the ink and fills from the point *r* pixels to the right of the middle, a point between two rings (or inside the smallest one). The TS2068 colours each 8 by 8 character cell with a single ink, so a cell that holds pixels of two rings has just one colour, that of whatever was drawn into it last, and the edges between the colours are blocky. The last `0 INK` puts the ink back to black for the text.

**Things to try.**

* Use other colours (0 to 7), or more rings.
* Do a `BAND` before any `RING`: with nothing to stop it, the fill spreads over the whole screen.

## 13. A countdown

Numbers on the screen at a place of your choice, with a note for each. `AT-XY` moves the print position to a column and a row; `BEEP` plays a note of a number of semitones from middle C for a number of seconds.

```forth
: COUNTDOWN CLS 5 0 DO
  5 I - 15 10 AT-XY .
  0 0.1 BEEP LOOP
  15 10 AT-XY ." GO!"
  12 0.5 BEEP ;
COUNTDOWN  \ expect:                GO!
```

**How it works.** Each time round the loop, `5 I -` is the number to show, 5 down to 1, and `15 10 AT-XY` puts the print position at column 15 of row 10, so each number covers the one before. `0 0.1 BEEP` plays middle C for a tenth of a second, and waits until the note has finished. At the end `GO!` is printed at the same place and `12 0.5 BEEP` plays a note an octave higher for half a second. The test checks what is left on the screen: `GO!` at column 15.

**Things to try.**

* Make the notes rise by a semitone for each number: `I 0.1 BEEP` in place of `0 0.1 BEEP`.
* Print the numbers on a different row each time, so that the whole count stays on the screen.

## 14. A character of your own

The characters with codes 144 to 164 are drawn from eight bytes that you set. `0 UDG` is the address of the bytes for code 144, `1 UDG` for 145. Each byte is one row of the character, a bit for each of its 8 pixels, the leftmost the highest bit. This program draws two faces, one smiling and one not.

```forth
: UDEF ( b0 .. b7 slot -- )
  UDG 7 + 8 0 DO DUP ROT
  SWAP C! 1- LOOP DROP ;
60 66 165 129
165 153 66 60 0 UDEF
60 66 165 129
153 165 66 60 1 UDEF
1 UDG 4 + C@ .  \ expect: 153
: FACES CLS 6 0 DO
  144 EMIT 145 EMIT LOOP ;
FACES  \ draws
```

**How it works.** The faces are written as the bytes of their rows from the top, 60 (`00111100`) first, and the bytes wait on the stack across the lines until `UDEF` takes them. `UDEF` starts at the address of the last byte of the slot (`UDG 7 +`) and stores the bytes from the stack top, the last row first, one address lower each time. The two faces differ only in the order of their 5th and 6th rows, 165 and 153: the mouth turns up or down. Then `144 EMIT` and `145 EMIT` print them as they would print the letters, in the current ink.

**Things to try.**

* Draw your own on graph paper, 8 by 8 squares, and work out the byte of each row.
* Print a row of the first face in different inks: `: INKS 7 1 DO I INK 144 EMIT LOOP 0 INK ;`.

## 15. A sprite you move with the keys

A sprite is a small picture that can be moved over the screen without spoiling what is behind it. `SPRITE-DEFINE` captures 16 by 16 pixels from the screen, `SPRITE-SHOW` draws it at a row and column of character cells (saving what was there), and `SPRITE-HIDE` puts the background back. This program draws a red disc, captures it and moves it along row 10 with the cursor keys (CAPS SHIFT with 5 and 8 on the keyboard): left gives the key code 1 and right 4. The test presses right five times and left three times.

```forth
VARIABLE COL
: DISC 2 INK 48 48 7 CIRCLE
  48 48 FILL ;
: MAKE CLS DISC
  0 5 5 SPRITE-DEFINE
  CLS 0 INK ;
: MOVE ( dc -- ) 0 SPRITE-HIDE
  COL @ + 0 MAX 30 MIN COL !
  0 10 COL @ SPRITE-SHOW ;
: STEER KEY DUP 1 =
  IF DROP -1 ELSE 4 =
  IF 1 ELSE 0 THEN THEN MOVE ;
: PLAY MAKE 15 COL !
  0 10 15 SPRITE-SHOW
  8 0 DO STEER LOOP ;
\ keys: \x04\x04\x04\x04\x04\x01\x01\x01
PLAY  \ draws
COL @ .  \ expect: 17
```

**How it works.** `MAKE` draws the disc in the character cells at row 5, column 5 (pixels 40 to 55), captures those four cells into sprite slot 0 and clears the screen. `MOVE` hides the sprite, adds the step to the column (kept between 0 and 30, so the sprite stays on the screen) and shows it again at the new place. `STEER` waits for a key with `KEY` and turns it into a step: -1 for the code 1, +1 for 4, 0 for anything else. `PLAY` makes the sprite, shows it at column 15, and takes eight keys. It starts at column 15, moves right five and left three, so it ends at column 17.

**Things to try.**

* Add keys for up and down (the codes 3 and 2): keep the row in a variable too.
* Capture a sprite from a drawing of your own, or from user-defined characters (program 14).

---

## A larger program: Blackjack

`demos/blackjack.fs`, in the Leap-Forth source, is a whole game in about 150 short lines: you against the dealer, with the
cards drawn on a green table, a sound for each card and a count of rounds won, lost and pushed. It uses most of what
this part shows: arrays for the deck and the two hands (a hand is an `ARRAY` whose cell 0 is the number of cards),
`RND` to shuffle, `UDG` for the suits, `LINE` for the cards' edges, `KEY` for H, S, Y and N, and `BEEP`, `TONE`,
`NOISE` and `VOLUME` for the sounds. Its words are short and each says what it does: `SHUFFLE`, `DEAL`, `SCORE`
(counting an ace as 11, or 1 when that would go over 21), `PLAYER-TURN`, `DEALER-TURN` (draws to 17), `JUDGE`, `ROUND`.

The start word, `BLACKJACK`, shows the rules and waits for a key, and only then does `0 RANDOMIZE`: how long you take
to press the key decides the cards, so no two games are the same, even on a cartridge, which starts at the same moment
after every switch-on.

To play it on the release ROMs, put the file on a text tape and load it:

```text
python3 tools/tape_gen_forth.py bj.tap BLACKJACK:demos/blackjack.fs
LOAD-TEXT BLACKJACK
BLACKJACK
```

The first line is typed on the PC, the other two in the emulator once `bj.tap` is in its tape player. `make blackjack`
makes it a cartridge (see [Program cartridges](06_libraries.md#program-cartridges)).

---

That is all the programs. To keep one, remember that everything you type is kept in the line store, and `SAVE-TEXT` puts the store on tape: see [Part 4](04_machine.md) and [Tapes](05_concepts.md#tapes).
