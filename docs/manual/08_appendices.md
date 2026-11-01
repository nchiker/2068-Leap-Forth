# Appendices

## Appendix A: Messages and error codes

What Forth prints after a line:

| Message | When |
|---|---|
| `OK` | the line ran to its end without an error |
| *name* `?` | *name* is neither a word in the dictionary nor a number (code -13); also a compile-only word typed outside a definition (`IF ?`), and `EDIT` given a name with no definition in the line store |
| `STACK?` | after a word, a stack was below empty or past its top (codes -4 and -3); both stacks are emptied |
| a message from the table below | an error was `THROW`n and nothing caught it |
| `ERROR` *n* | the same, for a code not in the table (a program's own `THROW`) |
| nothing, and no `OK` | `ABORT` (code -1, both stacks emptied) or `QUIT` (code -56, stacks kept) |

An error stops the line, and the rest of it is not run. A definition that was being compiled is dropped. While `EDIT`
runs the lines you changed, an error message begins with `LINE` *n*, the number of the line in the store that caused it.

| Code | Message | Raised by |
|---:|---|---|
| -1 | (none) | `ABORT` |
| -3, -4 | `STACK?` | the stack check after each word: a stack past its top (-3) or below empty (-4) |
| -5 | `RETURN STACK FULL` | a word that calls itself (or others) too deeply: the machine stack is nearly full |
| -8 | `DICTIONARY FULL` | a definition, `ALLOT`, `,` or `SAVE-LIB` with no room left in the dictionary |
| -13 | `UNDEFINED WORD` | `'` or `[']` given a name that is not a word (typed alone, an unknown name prints *name* `?` instead) |
| -16 | `MISSING NAME` | a defining word, `'`, `FORGET`, `CHAR` ... with no name after it |
| -28 | `BREAK` | BREAK (CAPS SHIFT + SPACE) pressed while a word runs; SPACE during a tape command |
| -37 | `TAPE ERROR` | a tape that could not be read, failed its checksum, or (`VERIFY-`) differs; a library from another ROM |
| -42 | `DIVISION BY ZERO` | `F/` by zero; `TAN` where the cosine is 0 (integer `/` and `MOD` by zero give 0, not an error) |
| -43 | `OUT OF RANGE` | a typed number outside -32,768 to 65,535 or a decimal too large; a decimal result too large; `F>S` of a decimal that does not fit; `PLACES` outside 0 to 9; `SIN`, `COS` or `TAN` of more than about 102,940 |
| -46 | `INVALID ARGUMENT` | `FSQRT` of a negative number |
| -56 | (none) | `QUIT` |

The codes are the ones Forth-2012 gives these conditions, so a program can `CATCH` them and test the number. A program
may `THROW` any other number but 0; uncaught, it prints `ERROR` and the number.

Other messages:

| Message | When |
|---|---|
| `NO EXROM` | `EDIT`, `RECT`, `FILL`, `CIRCLE`, `POLYGON`, `POLYGON-FILL` or a sprite word, with no Leap-Forth EXROM in the machine. The word takes its arguments and does nothing; the line goes on |
| `STORE FULL` | the line store has no room for the line you typed (it still runs), or for a line changed in `EDIT` |
| `LONG LINE` | `EDIT` refused: a line in the store is too long for its view |
| `FORGET: NOT FOUND` | `FORGET` with a name that is not in the dictionary |
| `FORGET: BUILT-IN, REFUSED` | `FORGET` with the name of one of the ROM's words |
| `BAD PROGRAM` | a cartridge's program failed its check at switch-on (see [Part 6](06_libraries.md#at-switch-on)) |

## Appendix B: The character set and keys

### The character set

| Codes | Characters |
|---|---|
| 32 to 126 | the printable ASCII characters, from space to `~` |
| 128 to 143 | the block graphics: each code's bits 0 to 3 fill the top right, top left, bottom right and bottom left quarters of the cell |
| 144 to 164 | the 21 user-defined characters (see `UDG`) |
| 13 | `EMIT` moves to the start of the next row (`CR` does the same) |
| 0 to 31 (but 13), 127, 165 to 255 | no character: `EMIT` prints a space |

### The keyboard

Letters, digits and SPACE type themselves; a letter types in lower case, and CAPS SHIFT + a letter gives a capital.
Forth does not mind which: `dup` is `DUP`. SYMBOL SHIFT + a key gives the punctuation of the tables. The first eight are
Leap-Forth's own (the same as Leap-C's), because Forth needs them and the TS2068's keys do not give them; the rest are
the TS2068's.

| SYMBOL SHIFT + | Y | U | F | G | S | A | H | D |
|---|---|---|---|---|---|---|---|---|
| gives | `[` | `]` | `{` | `}` | `\|` | `~` | `^` | `\` |

| SYMBOL SHIFT + | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|
| gives | `!` | `@` | `#` | `$` | `%` | `&` | `'` | `(` | `)` | `_` |

| SYMBOL SHIFT + | P | O | Z | R | T | C | L | K | J | B | V | N | M |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gives | `"` | `;` | `:` | `<` | `>` | `?` | `=` | `+` | `-` | `*` | `/` | `,` | `.` |

SYMBOL SHIFT with Q, W, E, X or I types nothing; on the TS2068's own ROM they give keywords. The backtick (`` ` ``) has
no key. On a PC keyboard in an emulator, **Shift** is CAPS SHIFT and **Ctrl** is SYMBOL SHIFT.

The editing keys:

| Keys | At the prompt | In `EDIT`'s view | Code (`KEY`) |
|---|---|---|---:|
| ENTER | runs the line | ends the line, opens the next | 13 |
| CAPS SHIFT + 5 / 8 | cursor left / right | the same | 1 / 4 |
| CAPS SHIFT + 6 / 7 | | cursor down / up | 2 / 3 |
| CAPS SHIFT + 0 (DELETE) | deletes the character before the cursor | the same | 8 |
| CAPS SHIFT + ENTER | | inserts an empty line | 11 |
| CAPS SHIFT + 1 | | deletes the line | 15 |
| BREAK (CAPS SHIFT + SPACE) | stops a running word | leaves the view | |

`KEY` returns these codes, and the character's code for the others. BREAK is not returned: it stops the word (see
[BREAK](05_concepts.md#break)). The keys of `EDIT`'s view are in the concept
[The editor and the line store](05_concepts.md#the-editor-and-the-line-store).

## Appendix C: Limits

| What | Limit |
|---|---|
| a number (a cell) | -32,768 to 32,767; typed numbers may go to 65,535, read as unsigned (65,535 is -1) |
| a decimal | about ±1.7 × 10^38, about 9 significant digits; the smallest is about 2.9 × 10^-39 |
| the data stack | 896 cells |
| the float stack | 204 decimals |
| the dictionary (your words) | 16,128 bytes |
| the line store (your source) | 8,192 bytes |
| a line typed at the prompt | 128 characters |
| a word's name | 31 characters (a longer name keeps its first 31) |
| `DO` loops inside each other in one definition | 8 |
| `CATCH` inside `CATCH` | 8 |
| a tape name | 10 characters (a longer name keeps its first 10) |
| user-defined characters | 21 (codes 144 to 164) |
| sprites | 4, each 2 × 2 character cells |
| `POLYGON`, `POLYGON-FILL` | 3 to 12 corners |
| `PLACES` | 0 to 9 |

## Appendix D: Memory map

| Address | What is there |
|---|---|
| `$0000-$3FFF` | the HOME ROM (Leap-Forth) |
| `$4000-$5AFF` | the screen: its bitmap (`$4000`) and attributes (`$5800`) |
| `$5B00-$7FFF` | working space for `FILL`; in `HIRES`, the second display file at `$6000-$77FF` (where `FILL` does nothing) |
| `$8000-$8503` | the ROM's variables |
| `$8504-$88FF` | the float stack |
| `$8900-$8FFF` | the data stack |
| `$9000-$90FF` | a guard: a word that takes more from the data stack than it holds writes here, not over your words |
| `$9100-$CFFF` | the dictionary: your words, from `$9100` up (`HERE` is the next free byte) |
| `$D000-$EFFF` | the line store |
| `$F000-$F17F` | the sprites' images and backgrounds |
| `$F180-$F227` | the user-defined characters |
| `$F228-$F3C7` | free |
| `$F3C8-$FEFF` | the machine stack (return addresses), growing down from `$FF00` |

The EXROM (the extension ROM, 8 KB) appears at `$A000-$BFFF` only while one of its words runs, hiding that part of the
dictionary for the moment; you never see it from Forth.

## Appendix E: Hardware notes

* **Frames.** The TS2068 shows 60 frames a second, ZEsarUX and the other emulators here 50. Words that count frames
  (`BEEP`'s length, a wait) run 20% longer on the emulators.
* **The sound chip.** The TS2068's AY-3-8912 runs at 1.764 MHz, ZEsarUX's at 1.7734 MHz: a note is about 0.5% higher
  there.
* **The EXROM.** The TS2068 shows its EXROM in all eight 8 KB chunks; stock ZEsarUX 13.0 in two, which is why it needs
  the patch in the source (`patches/`) for the EXROM words. EightyOne 1.41 does not load the EXROM cartridge
  correctly, and TS-Pico has no EXROM slot.
* **Ports.** Leap-Forth uses port `$FE` (border, keyboard, tape), `$F4` (which memory chunks are ROM), `$FF` (the
  display mode and the EXROM), `$F5` and `$F6` (the sound chip), `$FB` (the printer), and `$BF3B`/`$FF3B` (ULAplus).
  `OUT` writes to any port and can change all of these: `$F4` can page the ROM or the RAM you are running in out of
  sight.
* **Untested on hardware.** Everything in this manual was checked on emulators. The real keyboard, cassette recorder,
  printer, joystick and cartridge port have not been tried with this ROM.

## Appendix F: Word index

Every word, by group. Parts 3 and 4 have the entries, in ASCII order.

| Group | Part | Words |
|---|---|---|
| **stack** | [3](03_language.md) | `DROP` `DUP` `SWAP` `OVER` `ROT` `2DUP` `2DROP` `?DUP` `PICK` |
| **arithmetic** | [3](03_language.md) | `+` `-` `*` `/` `MOD` `1+` `1-` `NEGATE` `ABS` `SGN` `MAX` `MIN` `SQRT` `RND` `RANDOMIZE` `AND` `OR` `XOR` `INVERT` `0=` `=` `<` `>` |
| **float** | [3](03_language.md) | `F+` `F-` `F*` `F/` `F.` `FS.` `PLACES` `S>F` `F>S` `FROUND` `FLOOR` `FSQRT` `FABS` `FNEGATE` `FMIN` `FMAX` `PI` `SIN` `COS` `TAN` `RAD` `DEG` `F<` `F>` `F=` `F0<` `F0=` `F@` `F!` `FVARIABLE` `FCONSTANT` `FDUP` `FDROP` `FSWAP` `FOVER` `FDEPTH` |
| **memory** | [3](03_language.md) | `@` `!` `C@` `C!` `HERE` `,` `C,` `ALLOT` `VARIABLE` `CONSTANT` `ARRAY` `CELLS` `FREE` |
| **strings** | [3](03_language.md) | `S"` `STRING` `PLACE` `COUNT` `LEN` `VAL` `STR` `CHR` `CODE` `UPPER` `LOWER` `LEFT` `RIGHT` `SEARCH` `CHAR` `[CHAR]` |
| **control** | [3](03_language.md) | `IF` `ELSE` `THEN` `BEGIN` `UNTIL` `WHILE` `REPEAT` `DO` `LOOP` `+LOOP` `LEAVE` `I` `J` `EXIT` `EXECUTE` |
| **dictionary** | [3](03_language.md) | `:` `;` `CREATE` `DOES>` `IMMEDIATE` `'` `[']` `[` `]` `LITERAL` `FORGET` `VLIST` `(` `\` `EDIT` `LIST-DEFS` |
| **errors** | [3](03_language.md) | `THROW` `CATCH` `ABORT` `QUIT` |
| **I/O** | [4](04_machine.md) | `.` `."` `EMIT` `CR` `SPACE` `SPACES` `TYPE` `AT-XY` `CLS` `KEY` `KEY?` `BREAK?` `ACCEPT` `INPUT` `STICK` `IN` `OUT` |
| **graphics** | [4](04_machine.md) | `INK` `PAPER` `BRIGHT` `FLASH` `BORDER` `PLOT` `LINE` `RECT` `FILL` `CIRCLE` `POLYGON` `POLYGON-FILL` `HIRES` `NORMAL` `UDG` `SPRITE-DEFINE` `SPRITE-SHOW` `SPRITE-HIDE` `ULAPLUS` `PALETTE` |
| **sound** | [4](04_machine.md) | `BEEP` `SOUND` `TONE` `VOLUME` `MIXER` `NOISE` `ENVELOPE` |
| **storage** | [4](04_machine.md) | `SAVE-TEXT` `VERIFY-TEXT` `LOAD-TEXT` `SAVE-LIB` `VERIFY-LIB` `LOAD-LIB` |
| **printer** | [4](04_machine.md) | `LPRINT` `LLIST` |

## Appendix G: How this manual was checked

* **Every example is a test.** Each box of Forth in this manual (` ```forth ` in its source) is typed, line by line,
  into a freshly switched-on Leap-Forth in the ZEsarUX emulator, and each line's output is compared with its
  `\ expect:` comment; a line without one must print nothing but `OK`. `tools/docexamples.py` turns the boxes into
  test files (`tests/doc/manual_*.fs`) and `make check` fails if they are out of step with the manual; `make test`
  runs them with the other tests. A line that draws is run but its picture is not compared. Boxes that use the tape
  cannot run this way; the tape words are tested on real tape signals by `make test`'s tape suite.
* **The manual names exactly the ROM's words.** `tools/manualcheck.py` (in `make check`) reads the dictionary from the
  ROM image and checks that Parts 3 and 4 have one entry for each of its words and no other, in order, each with its
  stack effect, its kind as the ROM has it (immediate, compile-only, defining, EXROM), its group and an example.
* **Emulators only.** The checks run on ZEsarUX 13.0; the tape words also on Fuse 1.9.1, the cartridge also on TSRun.
  Nothing has been checked on a physical TS2068.
