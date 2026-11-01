# Part 5 -- Concepts

The ideas behind Leap-Forth, in alphabetical order. Each concept says how a part of the system works and points to the
words that use it ([Part 3](03_language.md), [Part 4](04_machine.md)). The examples are typed at the prompt, as in
Parts 3 and 4.

## BREAK

**BREAK** is CAPS SHIFT + SPACE. It stops whatever word is running, at any moment: a loop that never ends, a long
drawing, a word waiting for a key. The line stops with the message `BREAK`, both stacks are emptied, and the prompt
returns. Your words and the line store are kept.

BREAK is an error like any other (code -28), so a program can catch it: `' MAIN CATCH` gives -28 when MAIN was stopped
by BREAK, and the program can tidy up (put the colours back, say) before it ends. During a tape command SPACE alone
stops it, with the same code.

A few things are not stopped half-way, because stopping them there would leave memory half changed: the sprite words
and the switch between display modes finish first, and BREAK takes effect as they end. At the prompt and in `EDIT`'s
view BREAK is a key: at the prompt it does nothing, and in the view it leaves the view. `BREAK?` lets a program look at
the key without being stopped.

A word that calls itself without end is stopped too, before it fills memory: `RETURN STACK FULL` (code -5).

## Characters and keys

Characters are ASCII: 32 is a space, 65 is `A`, 97 is `a`. Codes 128 to 143 are the TS2068's block graphics and 144
to 164 the user-defined characters (`UDG`). `EMIT` prints a character by its code, `KEY` waits for a key and gives its
code, `CHAR` and `[CHAR]` give the code of a character you type after them.

```forth
CHAR A . CHAR a .        \ expect: 65 97
65 EMIT 66 EMIT          \ expect: AB
```

Forth's names are not case-sensitive: `dup`, `Dup` and `DUP` are the same word. The text of strings keeps its case.
The table of characters, the punctuation keys and the codes `KEY` gives are in
[Appendix B](08_appendices.md#appendix-b-the-character-set-and-keys).

## Compiling and interpreting

Forth reads a line one **word** at a time; a word is anything between spaces. For each one it:

1. looks for the name in the dictionary, newest word first; if it is there, Forth **runs** it, or, between `:` and
   `;`, **compiles** it into the word being defined;
2. otherwise reads it as a number (a whole number, or a decimal if it has a `.` or an exponent), and puts it on the
   stack, or compiles it;
3. otherwise stops the line with the name and `?`.

`:` switches from interpreting to compiling, and `;` back. Some words are **immediate**: they run even while Forth is
compiling, because their work is to build the definition (`IF`, `DO`, `."`, `(`). `[` and `]` switch to interpreting
and back inside a definition, and `LITERAL` compiles a number worked out there:

```forth
: SECS [ 60 60 * ] LITERAL ;
SECS .                   \ expect: 3600
```

Compiling makes **machine code**. A definition becomes a list of Z80 `CALL`s to the words it uses, and a number in it
an instruction that puts the number on the stack; `;` compiles a `RET`. This is called *subroutine threading*, and it
is why a word you define runs as fast as the ROM's own words call each other. A definition is in the dictionary from
its `:`, so it can call itself by name; a definition that ends in an error is removed.

## Defining words

A **defining word** makes a new word, taking its name from the line: `:`, `VARIABLE`, `CONSTANT`, `ARRAY`, `STRING`,
`FVARIABLE`, `FCONSTANT` and `CREATE`. A missing name is the error `MISSING NAME`. A name is up to 31 characters (a
longer one keeps its first 31) and may hold any character but a space.

`CREATE` makes a word that gives the address of the bytes after it, which `,`, `C,` and `ALLOT` then fill. `DOES>`
gives words made by a defining word of your own something to do with that address:

```forth
: TABLE CREATE , , DOES> @ ;
3 7 TABLE T
T .                      \ expect: 7
```

Defining the same name again makes a new word that hides the old one from then on. Words compiled before go on using
the old one.

## Differences from standard Forth

Leap-Forth follows Forth-2012 where it can. The differences:

| Leap-Forth | Forth-2012 |
|---|---|
| 16-bit cells; true is -1 | the same (the standard allows wider cells) |
| decimal only: no `BASE`, `HEX`, `DECIMAL` | `BASE` sets the number base |
| `3.5` and `1E3` are decimals on the float stack | a number with `.` is a double cell; floats need an exponent |
| `/` and `MOD` round toward zero | the rounding is the system's choice |
| a definition can be found from its `:` (it calls itself by name) | hidden until `;`; `RECURSE` calls itself |
| `."`, `IF`, `DO` and the other control words are refused outside a definition | interpreting them is undefined |
| no double-cell words (`D+`, `M*`, `UM/MOD`), no `*/`, `/MOD` | in the Core word set |
| no `>R`, `R>`, `R@` | the return stack words |
| no `?DO`, `UNLOOP`, `CASE`, `POSTPONE`, `COMPILE,`, `RECURSE`, `WORD`, `FIND`, `MOVE`, `FILL` (bytes), `.S`, `DEPTH`, `WORDS` | in the Core and Tools word sets |
| `VLIST` lists the words; `FILL` floods an area of the screen | `WORDS`; `FILL` sets bytes |
| `SIN`, `COS`, `TAN` | `FSIN`, `FCOS`, `FTAN` |
| `PLACES` sets the decimals `F.` prints | `SET-PRECISION` sets significant digits |
| strings: `S"` at the prompt as well as in definitions; `STRING`, `LEN`, `LEFT`, `VAL` ... from Sinclair BASIC | `S"` and the String word set |
| an unknown word prints *name* `?`; an uncaught `THROW` prints a message | the same idea |

The words that are here behave as the standard says unless their entry says otherwise.

## Errors

When something goes wrong, the line stops and Forth prints a message instead of `OK`: the name and `?` for a word it
does not know, `STACK?` for a stack that ran dry, or a message such as `DIVISION BY ZERO`. Both stacks are emptied,
a definition left half-made is removed, and the prompt returns. Nothing else is lost: your words, the line store and
the screen stay as they were. The messages and their codes are in
[Appendix A](08_appendices.md#appendix-a-messages-and-error-codes).

Every error except an unknown word typed at the prompt and `STACK?` is a **`THROW`** of a code, and a program can catch
it. `CATCH` runs a word (by its execution token) and gives 0 if it ended normally, or the code if something was thrown,
with the stacks back to their depth before the word ran:

```forth
: HALF 2 / ;
10 ' HALF CATCH . .      \ expect: 0 5
: CHECK 0= IF -99 THROW THEN ;
0 ' CHECK CATCH .        \ expect: -99
```

Your own codes can be any number except 0; a code nothing catches prints `ERROR` and the number. `ABORT` and `QUIT`
end the line at once without a message. `CATCH` can be inside another `CATCH` up to eight deep.

## Flags

A comparison gives a **flag**: -1 for true, 0 for false. `IF`, `UNTIL` and `WHILE` take a flag and treat any number
but 0 as true.

```forth
3 4 < . 4 3 < .          \ expect: -1 0
5 0= . 0 0= .            \ expect: 0 -1
```

Because true is -1, all its bits are set, so `AND`, `OR`, `XOR` and `INVERT` work on flags as logical operations and on
other numbers bit by bit: `-1 5 AND` is 5, and `0 INVERT` is -1.

## Floating point

Decimals (floating-point numbers) are a separate kind of number with a stack of their own, the **float stack**, which
holds 204 of them. A number with a decimal point or an exponent goes there: `3.5`, `-0.25`, `.5`, `1E3`, `2.5E-4`.
Whole numbers stay on the data stack. The float words begin with F (`F+`, `F.`, `FDUP`) or are the mathematical
functions (`SIN`, `FSQRT`, `PI`); `S>F` and `F>S` move a number from one stack to the other.

```forth
1.5 2.25 F+ F.           \ expect: 3.7500
7 S>F 2.0 F/ F.          \ expect: 3.5000
```

A decimal is the Sinclair 5-byte format: about 9 significant digits, from about 2.9 × 10^-39 to about 1.7 × 10^38,
with every result rounded to the nearest. A result too small becomes 0; a result too large is `OUT OF RANGE`, and
dividing by zero is `DIVISION BY ZERO`, so a calculation stops with a message instead of going on with a wrong number.
`F.` prints 4 decimal places to begin with (`PLACES` changes it) and `FS.` prints in the form `1.2345E6`.

The integer words stay integer: `*`, `/` and `MOD` work on whole numbers, are much faster than the float words, and
never round. Use decimals where you need fractions, and whole numbers everywhere else.

## Graphics

The screen is 256 pixels across and 192 down. Pixel coordinates count from the **top left**: *x* from 0 at the left,
*y* from 0 at the top, as text rows do (Sinclair BASIC counts *y* up from the bottom). Coordinates are signed numbers:
a point, line, rectangle or circle partly off the screen is drawn as far as it is on it, and the part off it is
skipped without an error. `POLYGON` and `POLYGON-FILL` are the exception: their corners must be on the screen (a
corner off it is taken modulo 256, so the shape is drawn wrongly).

`PLOT` sets a pixel, `LINE` draws a line, `RECT` fills a rectangle, `CIRCLE` draws a circle, `FILL` floods an area,
`POLYGON` and `POLYGON-FILL` draw a shape of up to 12 corners. They draw in the current ink, and a pixel's colour is
its character cell's: the TS2068 colours each 8 × 8 cell with one ink and one paper, so two inks cannot meet inside a
cell. `HIRES` switches to the 2068's mode with a colour for every 8 × 1 strip instead, and `NORMAL` back.

`RECT`, `FILL`, `CIRCLE`, `POLYGON`, `POLYGON-FILL` and the sprite words are done by the EXROM. With another EXROM in
the machine they print `NO EXROM` and draw nothing.

## Memory

The TS2068 has 48 KB of RAM, from `$4000` up; the screen takes its first 6,912 bytes. Leap-Forth's use of the rest is
the map in [Appendix D](08_appendices.md#appendix-d-memory-map). What matters to a program:

* **The dictionary** holds your words, from `$9100` up to `$CFFF`: 16,128 bytes. `HERE` is the address of its next
  free byte and `FREE` the number of bytes left. Variables, arrays and strings live there too.
* **The line store** holds your source text, 8,192 bytes from `$D000`.
* `@` and `!` read and write a cell (2 bytes, low byte first), `C@` and `C!` a byte, at any address. Nothing checks
  the address: a `!` into the ROM's variables, the stacks or the line store can stop the machine, and only switching
  off brings it back.

A cell is two bytes, so the *n*-th cell of an array is *n* `CELLS` (2 *n*) bytes from its start.

## Numbers

A number on the data stack is one **cell**: 16 bits, -32,768 to 32,767. You may type numbers up to 65,535; one above
32,767 is stored as the same 16 bits, so `65535` is -1 and `40000` is -25,536 (useful for addresses). A typed number
beyond that is `OUT OF RANGE`.

Arithmetic **wraps around**: `32767 1 +` is -32768. `*` keeps the low 16 bits of the product. `/` and `MOD` round
toward zero, and dividing by zero gives 0, not an error.

```forth
32767 1 + .              \ expect: -32768
-7 2 / . -7 2 MOD .      \ expect: -3 -1
```

A number with a `.` or an exponent is a decimal (see [Floating point](#floating-point)). There are no other number
forms: no hexadecimal, no binary, no double cells.

## Screen

The screen has 24 rows of 32 characters. Output uses rows 0 to 22; row 23 is the line you type on, and the version
shows there from switch-on until the first key. Printing starts at the *print position*, which `AT-XY` sets and
`CLS` puts back at the top left; output below row 22 scrolls the rows above up by one.

Every character cell has its own ink and paper colour, bright and flash; `INK`, `PAPER`, `BRIGHT` and `FLASH` set
those that printing and drawing use next, and `BORDER` the border. `CLS` clears the screen to the current colours.
Text and graphics share the screen: a character printed over a drawing replaces that cell's 8 × 8 pixels.

## Sound

The TS2068 has an AY-3-8912 sound chip with three tone channels (A, B and C), a noise generator and an envelope.
`BEEP` plays a note on channel A, by its pitch in semitones from middle C and its length in seconds (a decimal), and
waits until it ends:

```forth
0 0.25 BEEP  12 0.25 BEEP
```

The other sound words set the chip's parts directly and return at once, so the sound goes on while the program
runs: `TONE` sets a channel's pitch, `VOLUME` its loudness, `MIXER` which channels play tone and noise, `NOISE` the
noise's pitch, `ENVELOPE` the shape of the sound over time, and `SOUND` any one of the chip's registers.

## Speed

Leap-Forth compiles to machine code, so a definition runs much faster than the same thing typed at the prompt each
time, and much faster than Sinclair BASIC. On a TS2068 (3.5 MHz), measured on ZEsarUX:

| Program | Time |
|---|---|
| the sieve of Eratosthenes over 2,000 numbers | about 4 seconds a pass |
| a 32-character line printed with `TYPE` | about 9 ms |
| `PLOT` of a point chosen at random, with the arithmetic to choose it | about 3 ms |
| a loop of about 60 decimal operations (`F*`, `F/`, `F+`) | about 0.13 s |
| compiling a definition of 20 numbers | about 0.16 s |

Whole-number arithmetic is the fastest: `*` and `/` are about three times as fast as `F*` and `F/`, and `+` far
faster again. Keep decimals for where you need them, and work in pixels and whole numbers where you can.

## Strings

A string is a run of characters in memory, given on the stack as two numbers: its address and its length (*addr len*).
`S"` makes one, `TYPE` prints one:

```forth
S" HELLO" TYPE           \ expect: HELLO
S" HELLO" . DROP         \ expect: 5
```

A string you want to keep or change goes in a **string variable**, made by `STRING` with room for a number of
characters; `PLACE` copies a string into it and `COUNT` gives it back as *addr len*. The words borrowed from Sinclair
BASIC work on *addr len* pairs: `LEN`, `LEFT`, `RIGHT`, `VAL` (a string to a number), `STR` (a number to a string),
`CHR`, `CODE`, `UPPER`, `LOWER` and `SEARCH`.

## Tapes

Forth saves to and loads from **cassette tape** in the TS2068's standard format, and so to a tape file (`.tap`, `.tzx`)
in an emulator. Two kinds of thing go on tape:

* **source text**: the line store, by `SAVE-TEXT name`; `LOAD-TEXT name` puts it back and runs it, so your words are
  compiled again, on any Leap-Forth ROM;
* **a library**: your compiled words, by `SAVE-LIB name`; `LOAD-LIB name` puts them back at once, on the same ROM only
  (see [Part 6](06_libraries.md)).

Start the recorder before pressing ENTER on a save. A load searches the tape for its name, skipping other files, and a
load with no name takes the first file of its kind. `VERIFY-TEXT` and `VERIFY-LIB` compare a tape with memory and change
nothing. SPACE stops a tape command (`BREAK`); a tape that cannot be read, or does not match, is `TAPE ERROR`. Both can
be caught with `CATCH`. A name is up to 10 characters.

## The dictionary

The **dictionary** is the list of every word Forth knows: the ROM's 184, then yours. Forth searches it newest first,
so a new word with an old name hides the old one. `VLIST` prints the names, newest first; `FREE` says how many bytes
are left for new words; `'` gives a word's execution token, which `EXECUTE` runs.

```forth
: GREET ." HI" ;
' GREET EXECUTE          \ expect: HI
```

`FORGET name` removes the word *name* and every word defined after it, and gives their memory back. The ROM's own words
cannot be forgotten. Your words are lost when the machine is switched off: save them (see [Tapes](#tapes)).

## The editor and the line store

Every line you type at the prompt is kept in the **line store**, 8,192 bytes of source text, before it runs. So your
program's source is always there, in the order you typed it, mistakes and all.

`LIST-DEFS` prints the definitions in the store. `EDIT name` opens the full-screen editor on the last line in the store
that begins the definition of *name* (`: name`); `EDIT` alone opens it after the last line. In the editor:

| Key | Does |
|---|---|
| a character, cursor left and right, DELETE | edit the line, as at the prompt |
| cursor up and down | move between lines (and the rows of a long line) |
| ENTER | end the line and open a new one after it |
| CAPS SHIFT + ENTER | insert an empty line before this one |
| CAPS SHIFT + 1 | delete the line |
| DELETE on an empty line | delete it |
| BREAK | leave the editor |

The bottom row shows `LINE n/m`: the line the cursor is on and the number of lines. When you leave, the screen is
cleared and **every line you changed or added is run**, in order. So a changed definition is compiled again, and from
then on the new one is found. An error stops it, with `LINE n` before the message.

`SAVE-TEXT` saves the store, and `LOAD-TEXT` replaces it with a tape's text and runs it. The lines that hold
`SAVE-TEXT`, `VERIFY-TEXT`, `LOAD-TEXT` and `EDIT` themselves are not kept in the store. When the store is full, a typed
line still runs and `STORE FULL` is printed; the editor refuses a change that does not fit. A line is up to 128
characters; the editor refuses to open while a longer line (from an old tape) is in the store (`LONG LINE`).

## The printer

`LPRINT` and `LLIST` send output to a printer on the TS2068's printer port (`$FB`): the TS2040 or an interface that
behaves like it. See their entries in [Part 4](04_machine.md). On an emulator without a printer, they do what the
emulator's printer does; nothing has been tried on a real printer.

## The stacks

Forth works on a **data stack** of numbers. A number you type goes on top; a word takes its numbers from the top and
leaves its results there. The data stack holds 896 cells. Decimals have their own **float stack** of 204 (see
[Floating point](#floating-point)). A third stack, the Z80's own, holds the return addresses of the words that are
running; Forth has no words for it.

```forth
1 2 3 . . .              \ expect: 3 2 1
```

After each word you type, Forth checks both stacks. If one is below empty or past its top, the line stops with
`STACK?` and both are emptied. The check sees only where a stack ends up: `5 +` takes two numbers from a stack of one
and leaves one, so it passes, and the next word that takes a number stops with `STACK?`. Words that rearrange the stack
in place (`SWAP`, `DUP`) report nothing on an empty stack and leave a meaningless number. A word inside a definition is
checked when the definition returns, and the 256 bytes above the data stack are kept free so that such a word cannot
harm the dictionary.

## ULAplus

ULAplus is an extension of the Spectrum family's display chip that gives 64 colours on screen from a palette of 256.
`ULAPLUS` turns it on and off, and `PALETTE` sets a palette entry. A TS2068 needs ULAplus hardware fitted for these
to do anything; of the emulators, ZEsarUX has it and Fuse does not for Timex machines. Without it, the words do
nothing and the screen keeps the 2068's own colours.
