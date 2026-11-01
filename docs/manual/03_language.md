# Part 3 -- Words of the language

Every word of the language itself, in ASCII order of its name: the stack, arithmetic, decimals (floating point),
memory, strings, control, the dictionary and errors. The words that work the machine (the screen, the keyboard,
graphics, sound, the tape and the printer) are in [Part 4](04_machine.md). The two parts together are every word in the
ROM; [Appendix F](08_appendices.md#appendix-f-word-index) lists them all by group.

## How to read an entry

Each entry gives the word's **stack effect**, its **kind** and **group**, a description, a tested example and, where
they matter, notes, the errors it can cause, and related entries.

A stack effect shows what the word takes from the stack and what it leaves there, the top of the stack on the right:
`( n1 n2 -- n3 )` takes two numbers, *n2* the top one, and leaves one. Decimals live on a stack of their own, shown
after `F:`; a word that uses both stacks shows both: `( n -- ) ( F: -- f )`.

| Notation | Meaning |
|---|---|
| *n*, *n1*, *n2* | a number, -32,768 to 32,767 (one cell, 16 bits) |
| *u* | a number taken as unsigned, 0 to 65,535 |
| *x* | any cell: what it means does not matter to the word |
| *flag* | true or false: a word that gives one gives -1 for true and 0 for false; a word that takes one counts any number but 0 as true |
| *addr* | an address in memory |
| *c* | a character code (a byte, 0 to 255) |
| *addr len* | a string: the address of its first character and its length |
| *xt* | an execution token: what `'` gives for a word, and `EXECUTE` runs |
| *f* | a decimal, on the float stack (5 bytes) |
| `"name"` | the word reads the next name from the line you typed, not from the stack |

The **kinds** are:

| Kind | What it means |
|---|---|
| **word** | runs when it is typed, and is compiled into a definition when it is inside one |
| **immediate word** | runs at once even inside a definition (a comment, `;`, `S"`) |
| **compile-only word** | used only inside a definition (`IF`, `DO`, `."`); typed at the prompt it is refused, as `IF ?` |
| **defining word** | makes a new word, named by the name that follows it (`:`, `VARIABLE`, `CREATE`) |
| **EXROM word** | its work is done by the second ROM, the EXROM; with another EXROM in the machine it does nothing |

The **group** is the word's place in the summary below and in the Leap IDE's help.

**The examples are typed at the prompt**, a line at a time. Forth does not show the line you typed again: what it
prints appears on the screen, then `OK`. The part of a line after `\` is a comment, which Forth skips, so you can type
an example with or without it. Each `\ expect:` comment states what that line prints, without the `OK`, and the build
types every example into the ROM and checks it (see [Appendix G](08_appendices.md#appendix-g-how-this-manual-was-checked)).
A line with no `\ expect:` prints nothing but `OK`. An error prints its message, or the word with ` ?` after it, and no
`OK`: the rest of that line is not run.

Every example begins on a machine just switched on, so it defines whatever it uses.

**Two things matter everywhere:**

* **The stack is checked after every word you type.** If the word left it below empty, the line stops with `STACK?`
  and both stacks are emptied. A word inside a definition is checked when the definition returns. The check sees only
  where the stack ends up: `5 +` takes two numbers from a stack of one and leaves one, so it passes, and the next word
  that takes a number stops with `STACK?` (see [The stacks](05_concepts.md#the-stacks)).
* **Numbers wrap around.** A cell is 16 bits: `32767 1 +` is -32768. Decimals do not wrap; they have their own words
  (`F+`, `F*` ...) and their own stack.

## Summary

| Group | Words |
|---|---|
| **stack** | `DROP` `DUP` `SWAP` `OVER` `ROT` `2DUP` `2DROP` `?DUP` `PICK` |
| **arithmetic** | `+` `-` `*` `/` `MOD` `1+` `1-` `NEGATE` `ABS` `SGN` `MAX` `MIN` `SQRT` `RND` `RANDOMIZE` `AND` `OR` `XOR` `INVERT` `0=` `=` `<` `>` |
| **float** | `F+` `F-` `F*` `F/` `F.` `FS.` `PLACES` `S>F` `F>S` `FROUND` `FLOOR` `FSQRT` `FABS` `FNEGATE` `FMIN` `FMAX` `PI` `SIN` `COS` `TAN` `RAD` `DEG` `F<` `F>` `F=` `F0<` `F0=` `F@` `F!` `FVARIABLE` `FCONSTANT` `FDUP` `FDROP` `FSWAP` `FOVER` `FDEPTH` |
| **memory** | `@` `!` `C@` `C!` `HERE` `,` `C,` `ALLOT` `VARIABLE` `CONSTANT` `ARRAY` `CELLS` `FREE` |
| **strings** | `S"` `STRING` `PLACE` `COUNT` `LEN` `VAL` `STR` `CHR` `CODE` `UPPER` `LOWER` `LEFT` `RIGHT` `SEARCH` `CHAR` `[CHAR]` |
| **control** | `IF` `ELSE` `THEN` `BEGIN` `UNTIL` `WHILE` `REPEAT` `DO` `LOOP` `+LOOP` `LEAVE` `I` `J` `EXIT` `EXECUTE` |
| **dictionary** | `:` `;` `CREATE` `DOES>` `IMMEDIATE` `'` `[']` `[` `]` `LITERAL` `FORGET` `VLIST` `(` `\` `EDIT` `LIST-DEFS` |
| **errors** | `THROW` `CATCH` `ABORT` `QUIT` |

---

## !

`( x addr -- )` -- **word**, memory

Stores the cell *x* at *addr*: the low byte at *addr*, the high byte at *addr*+1. The address is not checked. A store into the ROM (addresses below 16,384) is ignored; anywhere else it overwrites whatever is there, the dictionary and the system variables included.

```forth
VARIABLE V
1234 V !
V @ .                      \ expect: 1234
258 V !  V C@ . V 1+ C@ .  \ expect: 2 1
```

**Notes.**

* The low byte comes first in memory: after `258 V !`, `V C@` is 2 and `V 1+ C@` is 1.
* *addr* may be odd. To store one byte use `C!`.

**See also** `@`, `C!`, `VARIABLE`, [Memory](05_concepts.md#memory).

---

## '

`( "name" -- xt )` -- **word**, dictionary

Reads the next word from the line and leaves its execution token *xt*, the address of its code, without running it. `EXECUTE` runs an *xt*. Upper and lower case do not matter. It finds immediate words (`' IF`) as well as ordinary ones.

```forth
: SQ DUP * ;
5 ' SQ EXECUTE .         \ expect: 25
' NOSUCH                 \ expect: UNDEFINED WORD
```

**Notes.**

* Inside a definition `'` is compiled like any word and reads its name each time the definition runs, from whatever is typed then. To look the word up while compiling, use `[']`.
* A word that is not in the dictionary throws -13 (`UNDEFINED WORD`), so `CATCH` can catch it.

**Errors.**

| Mistake | What happens |
|---|---|
| a name that is not a word | `UNDEFINED WORD` |
| nothing after `'` on the line | `MISSING NAME` |

**See also** `[']`, `EXECUTE`, `CATCH`, [The dictionary](05_concepts.md#the-dictionary).

---

## (

`( -- )` -- **immediate word**, dictionary

Starts a comment that ends at the next `)`. If there is no `)` on the line, the rest of the line is the comment. It works at the prompt and inside a definition. Put a space after `(`: `(x` is not a comment.

```forth
1 ( the first ) 2 + .    \ expect: 3
: SHOW 5 ( a note ) . ;
SHOW                     \ expect: 5
```

**Notes.**

* A comment does not go on to the next line.
* The comment cannot contain a `)`. For a comment to the end of the line use `\`.
* By custom a comment after a word's name gives its stack effect: `: SQ ( n -- n*n ) DUP * ;`.

**See also** `\`.

---

## *

`( n1 n2 -- n3 )` -- **word**, arithmetic

Multiplies *n1* by *n2*. Only the low 16 bits of the product are kept, so a product that does not fit wraps around,
with no error.

```forth
6 7 * .                  \ expect: 42
-3 4 * .                 \ expect: -12
200 200 * .              \ expect: -25536
```

**Notes.**

* 200 times 200 is 40000, which a cell holds as -25536. The 16 bits are right: taken as an unsigned number they are 40000.
* `*` runs in the processor's registers and is much faster than `F*`. Use `F*` only when a decimal is involved.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `*` or after the next word that takes a number |

**See also** `/`, `MOD`, `F*`, [Numbers](05_concepts.md#numbers).

---

## +

`( n1 n2 -- n3 )` -- **word**, arithmetic

Adds *n1* and *n2*. The sum wraps around if it does not fit in a cell.

```forth
3 4 + .                  \ expect: 7
32767 1 + .              \ expect: -32768
```

**Notes.**

* For decimals use `F+`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `+` or after the next word that takes a number |

**See also** `-`, `1+`, `F+`, [Numbers](05_concepts.md#numbers).

---

## +LOOP

`( step -- )` -- **compile-only word**, control

Closes a `DO` loop like `LOOP`, but adds *step* to the index instead of 1. Counting up, the loop ends when the index reaches or passes the limit. Counting down (a negative *step*), it ends when the index goes below the limit, so the last pass has the index equal to the limit. At run time `+LOOP` takes *step* from the stack.

```forth
: UP 10 0 DO I . 3 +LOOP ;
: DOWN 0 10 DO I . -4 +LOOP ;
: ZERO 0 10 DO I . -5 +LOOP ;
UP                       \ expect: 0 3 6 9
DOWN                     \ expect: 10 6 2
ZERO                     \ expect: 10 5 0
```

**Notes.**

* The end is found when the sign of *index* minus *limit* changes, so a step larger than the distance to the limit simply ends the loop.
* A step of 0 never ends the loop.
* The body always runs once before the first test, as for `LOOP`.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `+LOOP ?` |

**See also** `DO`, `LOOP`, `LEAVE`, `I`.

---

## ,

`( x -- )` -- **word**, memory

Compiles the cell *x* at `HERE` and moves `HERE` on by 2. The value is stored as it is, not as a literal. Use it after `CREATE` to fill a table.

```forth
CREATE TBL 10 , 20 , 30 ,
TBL @ .                  \ expect: 10
TBL 2 CELLS + @ .        \ expect: 30
```

**Errors.**

| Mistake | What happens |
|---|---|
| less than 2 bytes of room (see `FREE`) | `DICTIONARY FULL`, nothing is stored |

**See also** `C,`, `ALLOT`, `HERE`, `CREATE`, [Memory](05_concepts.md#memory).

---

## -

`( n1 n2 -- n3 )` -- **word**, arithmetic

Subtracts *n2* from *n1*. The difference wraps around if it does not fit in a cell.

```forth
10 3 - .  3 10 - .       \ expect: 7 -7
-32768 1 - .             \ expect: 32767
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `-` or after the next word that takes a number |

**See also** `+`, `1-`, `NEGATE`, `F-`.

---

## /

`( n1 n2 -- n3 )` -- **word**, arithmetic

Divides *n1* by *n2* and leaves the quotient *n3*, cut toward zero: `-17 5 /` is -3, not -4. The remainder is
`MOD`'s. Dividing by zero is not an error: the quotient is 0.

```forth
17 5 / .                 \ expect: 3
-17 5 / .  17 -5 / .     \ expect: -3 -3
17 0 / .                 \ expect: 0
```

**Notes.**

* Standard Forth leaves the rounding of `/` to each system. Here it is always toward zero, as in Leap-C, and `MOD`
  takes the sign of *n1*, so `n1 n2 / n2 * n1 n2 MOD +` gives *n1* back.
* `-32768 -1 /` is -32768: the true answer, 32768, does not fit in a cell.
* For a quotient with a fraction, divide decimals with `F/` (see [Floating point](05_concepts.md#floating-point)).

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `/` or after the next word that takes a number |

**See also** `*`, `MOD`, `F/`, [Numbers](05_concepts.md#numbers).

---

## 0=

`( n -- flag )` -- **word**, arithmetic

Leaves -1 (true) if *n* is 0, and 0 (false) for any other number. Applied to a flag, it gives the opposite flag.

```forth
0 0= . 5 0= . -1 0= .    \ expect: -1 0 0
5 5 - 0= .               \ expect: -1
3 0= 0= .                \ expect: -1
```

**Notes.**

* `0= 0=` makes any non-zero number the flag -1.

**See also** `=`, `INVERT`, [Flags](05_concepts.md#flags).

---

## 1+

`( n1 -- n2 )` -- **word**, arithmetic

Adds 1 to *n1*. The same as `1 +`, in one word. 32767 becomes -32768.

```forth
5 1+ .                   \ expect: 6
32767 1+ .               \ expect: -32768
```

**See also** `1-`, `+`.

---

## 1-

`( n1 -- n2 )` -- **word**, arithmetic

Subtracts 1 from *n1*. The same as `1 -`, in one word. -32768 becomes 32767.

```forth
5 1- .                   \ expect: 4
-32768 1- .              \ expect: 32767
```

**See also** `1+`, `-`.

---

## 2DROP

`( x1 x2 -- )` -- **word**, stack

Removes the top two numbers from the stack.

```forth
1 2 3 4 2DROP . .        \ expect: 2 1
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?` |

**See also** `DROP`, `2DUP`.

---

## 2DUP

`( x1 x2 -- x1 x2 x1 x2 )` -- **word**, stack

Copies the top two numbers, as a pair.

```forth
3 4 2DUP + . . .         \ expect: 7 4 3
```

**See also** `DUP`, `2DROP`, `OVER`.

---

## :

`( "name" -- )` -- **defining word**, dictionary

Starts a definition: reads *name* and makes it a new word, then compiles the words that follow instead of running them, until `;`. The name is known as soon as it is read, so a definition can call itself. Only the first 31 characters of a name count, and lower case is folded to upper.

```forth
: SQUARE DUP * ;
5 SQUARE .               \ expect: 25
: SUM DUP 0= IF EXIT THEN
DUP 1- SUM + ;
5 SUM .                  \ expect: 15
: BAD 1 NOSUCH ;         \ expect: NOSUCH ?
BAD                      \ expect: BAD ?
```

**Notes.**

* A definition can run over several lines; the console goes on compiling until it meets `;`.
* A line that ends in an error removes the definition it left open (the last two lines above): a word with half its code is never found.
* A name already in use is not changed. Definitions made afterwards use the new word; those made before keep calling the old one.
* A number can be a name (`: 7 ... ;`) and then takes the place of the number.
* A word that calls itself without end stops with `RETURN STACK FULL` before the machine runs out of stack.
* `:` inside a definition is not supported.

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `:` | `MISSING NAME` |
| an unknown word in the definition | `NOSUCH ?` (the word's name); the definition is dropped |
| no room | `DICTIONARY FULL` |

**See also** `;`, `CREATE`, `FORGET`, `IMMEDIATE`, [Defining words](05_concepts.md#defining-words), [Compiling and interpreting](05_concepts.md#compiling-and-interpreting).

---

## ;

`( -- )` -- **immediate word**, dictionary

Ends the definition that `:` began: compiles a return, makes the word complete and goes back to running what you type. It is immediate, so it runs even while a definition is being compiled.

```forth
: TWICE DUP + ;
4 TWICE .                \ expect: 8
```

**Notes.**

* `;` typed with no definition open compiles one stray return byte at `HERE` and does nothing else.

**See also** `:`, `EXIT`, `IMMEDIATE`.

---

## <

`( n1 n2 -- flag )` -- **word**, arithmetic

Leaves -1 (true) if *n1* is less than *n2*, comparing them as signed numbers, and 0 (false) if it is not.

```forth
3 4 < . 4 3 < . 3 3 < .  \ expect: -1 0 0
```

**Notes.**

* A number typed above 32767 is negative, so `40000 1 <` is -1. For decimals use `F<`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `<` or after the next word that takes a number |

**See also** `>`, `=`, `F<`, [Flags](05_concepts.md#flags).

---

## =

`( x1 x2 -- flag )` -- **word**, arithmetic

Leaves -1 (true) if *x1* and *x2* are the same cell, and 0 (false) if they are not.

```forth
3 3 = . 3 4 = .          \ expect: -1 0
65535 -1 = .             \ expect: -1
```

**Notes.**

* `=` compares the 16 bits, so 65535 and -1 are equal. For decimals use `F=`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `=` or after the next word that takes a number |

**See also** `<`, `>`, `0=`, `F=`, [Flags](05_concepts.md#flags).

---

## >

`( n1 n2 -- flag )` -- **word**, arithmetic

Leaves -1 (true) if *n1* is greater than *n2*, comparing them as signed numbers, and 0 (false) if it is not.

```forth
4 3 > . 3 4 > . 3 3 > .  \ expect: -1 0 0
```

**Notes.**

* A number typed above 32767 is negative, so `65535 1 >` is 0. For decimals use `F>`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `>` or after the next word that takes a number |

**See also** `<`, `=`, `F>`, [Flags](05_concepts.md#flags).

---

## ?DUP

`( x -- 0 | x x )` -- **word**, stack

Copies the top number only if it is not 0; a 0 is left as it is, once. Before `IF`, it leaves the number for the test
to use up and a copy for the code after it, but only when the number is not 0, so the false branch has nothing to drop.

```forth
5 ?DUP . .               \ expect: 5 5
0 ?DUP .                 \ expect: 0
: ?PRINT ?DUP IF . THEN ;
7 ?PRINT                 \ expect: 7
0 ?PRINT
```

**See also** `DUP`, `IF`.

---

## @

`( addr -- x )` -- **word**, memory

Leaves the cell stored at *addr*: the byte at *addr* is the low half, the byte at *addr*+1 the high half. The cell is signed, so a stored 65535 is fetched as -1.

```forth
VARIABLE V
99 V !
V @ .                    \ expect: 99
65535 V !  V @ .         \ expect: -1
```

**Notes.**

* The address is not checked: any 16-bit number is read, the ROM included. To fetch one byte use `C@`.

**See also** `!`, `C@`, `VARIABLE`, [Memory](05_concepts.md#memory).

---

## ABORT

`( -- )` -- **word**, errors

Gives up: empties both stacks, stops everything that is running, however deep, and returns to the prompt. Nothing after it on the line runs, and no `OK` is printed. Nothing is printed by `ABORT` itself; print your reason first.

```forth
1.5 42 ABORT 99 .
FDEPTH .                 \ expect: 0
DROP                     \ expect: STACK?
```

**Notes.**

* The number stack and the float stack are both emptied; after `ABORT` both are empty, which `FDEPTH` and the `DROP` show.
* `ABORT` goes past every `CATCH`: nothing can catch it. (Standard Forth defines `ABORT` as `-1 THROW`; here `-1 THROW` is a different thing, an ordinary throw that prints `ERROR -1` if nothing catches it.)
* If a definition is open when it runs (inside `[` and `]`), the definition is dropped.
* To stop but keep the stacks, use `QUIT`.

**See also** `QUIT`, `THROW`, `CATCH`, [Errors](05_concepts.md#errors).

---

## ABS

`( n1 -- n2 )` -- **word**, arithmetic

Leaves the size of *n1* without its sign. `-32768` has no positive partner in a cell, so it stays -32768.

```forth
-5 ABS . 5 ABS .         \ expect: 5 5
-32768 ABS .             \ expect: -32768
```

**See also** `SGN`, `NEGATE`, `FABS`.

---

## ALLOT

`( n -- )` -- **word**, memory

Moves `HERE` by *n* bytes and writes nothing. A positive *n* reserves room, usually for the data field of a word just made with `CREATE`; a negative *n* gives room back. The reserved bytes are not cleared.

```forth
CREATE BUF 10 ALLOT
HERE BUF - .             \ expect: 10
-4 ALLOT
HERE BUF - .             \ expect: 6
```

**Notes.**

* The most you can reserve is `FREE` minus 256: the last 256 bytes are kept so that a definition in progress can finish.
* A negative *n* is not checked. Taking back more than you reserved moves `HERE` into words already defined.

**Errors.**

| Mistake | What happens |
|---|---|
| a positive *n* larger than `FREE` minus 256 | `DICTIONARY FULL`, `HERE` does not move |

**See also** `HERE`, `FREE`, `CREATE`, `,`, [Memory](05_concepts.md#memory).

---

## AND

`( n1 n2 -- n3 )` -- **word**, arithmetic

Combines *n1* and *n2* bit by bit: a bit of the result is 1 only where both have a 1. Because a true flag is -1 (every
bit set) and a false flag is 0, `AND` also joins two flags.

```forth
10 12 AND .              \ expect: 8
-1 255 AND .             \ expect: 255
3 4 < 4 5 < AND .        \ expect: -1
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `AND` or after the next word that takes a number |

**See also** `OR`, `XOR`, `INVERT`, [Flags](05_concepts.md#flags).

---

## ARRAY

`( n "name" -- )` -- **defining word**, memory

Defines *name* as an array of *n* cells, all 0. Executing *name* leaves the address of its first cell; the address of element *i*, counting from 0, is `i CELLS name +`. Nothing checks the index.

```forth
5 ARRAY NUMS
99 3 CELLS NUMS + !
3 CELLS NUMS + @ .       \ expect: 99
0 CELLS NUMS + @ .       \ expect: 0
```

**Notes.**

* The array takes 2*n* bytes, after the word's header and code.
* A negative *n*, or one too large to fit, is `DICTIONARY FULL`.

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `ARRAY` | `MISSING NAME` |
| not enough room for the elements | `DICTIONARY FULL`, nothing is defined |
| an index outside 0 to *n*-1 | nothing: it reads or overwrites the memory beside the array |

**See also** `CELLS`, `VARIABLE`, `STRING`, [Memory](05_concepts.md#memory).

---

## BEGIN

`( -- )` -- **compile-only word**, control

Marks the start of a loop that `UNTIL` or `REPEAT` closes. It compiles nothing and does nothing when the loop runs.

```forth
: COUNTDOWN 3 BEGIN DUP .
1- DUP 0= UNTIL DROP ;
COUNTDOWN                \ expect: 3 2 1
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `BEGIN ?` |
| no `UNTIL` or `REPEAT` to close it | nothing is noticed; see `IF` |

**See also** `UNTIL`, `WHILE`, `REPEAT`, [Compiling and interpreting](05_concepts.md#compiling-and-interpreting).

---

## C!

`( c addr -- )` -- **word**, memory

Stores the low byte of *c* at *addr*. The high byte of *c* is dropped.

```forth
VARIABLE V
-1 V !
0 V C!
V @ .                    \ expect: -256
300 V C!  V C@ .         \ expect: 44
```

**Notes.**

* `-1 V !` sets both bytes to 255; `0 V C!` clears the low one, which leaves 65280, printed as -256. 300 is 256 + 44, so only 44 is stored.
* A store into the ROM is ignored.

**See also** `C@`, `C,`, `!`, [Memory](05_concepts.md#memory).

---

## C,

`( c -- )` -- **word**, memory

Compiles the low byte of *c* at `HERE` and moves `HERE` on by 1.

```forth
CREATE B 3 C, 4 C, 5 C,
B C@ .                   \ expect: 3
B 2 + C@ .               \ expect: 5
```

**Errors.**

| Mistake | What happens |
|---|---|
| no room (see `FREE`) | `DICTIONARY FULL`, nothing is stored |

**See also** `,`, `C!`, `ALLOT`, [Memory](05_concepts.md#memory).

---

## C@

`( addr -- c )` -- **word**, memory

Leaves the byte at *addr*, 0 to 255. It is never negative.

```forth
VARIABLE V
200 V C!
V C@ .                   \ expect: 200
```

**Notes.**

* The address is not checked.

**See also** `C!`, `@`, [Memory](05_concepts.md#memory).

---

## CATCH

`( xt -- 0 | n )` -- **word**, errors

Runs the word whose execution token is *xt*. If it finishes, `CATCH` leaves what it left and then 0. If a `THROW` happens inside it, however deep, the stacks go back to the depth they had when `CATCH` began (less *xt*) and `CATCH` leaves the thrown number *n*. Nothing in between runs.

```forth
: SAFE 5 3 + ;
: RISKY 42 THROW ;
' SAFE CATCH . .         \ expect: 0 8
' RISKY CATCH .          \ expect: 42
1 2 ' RISKY CATCH . . .  \ expect: 42 2 1
```

**Notes.**

* `CATCH` catches only a `THROW`: the ones you write, `BREAK` (-28), and those the ROM raises itself, such as `DICTIONARY FULL` and `UNDEFINED WORD`. It cannot catch `STACK?`, which is found after the word has finished, nor `ABORT` and `QUIT`.
* `CATCH` can be nested 8 deep. A ninth `CATCH` runs its word without a net: a `THROW` inside goes to the next one out.
* After a caught throw the line goes on. Use `0=` or `IF` on the result.
* *xt* comes from `'` or `[']`. Inside a definition write `['] WORD CATCH`; `' WORD` there would look for the name in the line when it runs.
* The float stack is restored as well as the number stack.

**Errors.**

| Mistake | What happens |
|---|---|
| a word that recurses too deep inside `CATCH` | `RETURN STACK FULL`, which `CATCH` catches as -5 |

**See also** `THROW`, `'`, `[']`, `ABORT`, [Errors](05_concepts.md#errors), [BREAK](05_concepts.md#break).

---

## CELLS

`( n1 -- n2 )` -- **word**, memory

Leaves *n2*, twice *n1*: the number of bytes in *n1* cells. Use it to turn an element number into an offset: `3 CELLS ARR +` is the address of element 3.

```forth
3 CELLS .                \ expect: 6
40000 CELLS .            \ expect: 14464
```

**Notes.**

* It is a multiplication by 2 and wraps like any other: 80,000 does not fit in 16 bits, and 14,464 is what is left.

**See also** `ARRAY`, `!`, `@`, [Memory](05_concepts.md#memory).

---

## CHAR

`( "name" -- c )` -- **word**, strings

Reads the next word from the line and leaves the code of its first character, exactly as typed: `CHAR a` is 97 and `CHAR A` is 65.

```forth
CHAR A .                 \ expect: 65
CHAR a .                 \ expect: 97
CHAR hello .             \ expect: 104
```

**Notes.**

* Inside a definition `CHAR` is compiled like any word and reads its character each time the definition runs, from whatever is typed then. To fix the character while compiling, use `[CHAR]`.

**Errors.**

| Mistake | What happens |
|---|---|
| nothing after `CHAR` on the line | `MISSING NAME` |

**See also** `[CHAR]`, `CHR`, `CODE`, [Characters and keys](05_concepts.md#characters-and-keys).

---

## CHR

`( c -- addr len )` -- **word**, strings

Makes a string of one character, the low byte of *c*, and leaves its address and length (always 1). The character is kept in a single buffer that every `CHR` uses, so the string lasts only until the next `CHR`.

```forth
65 CHR TYPE              \ expect: A
321 CHR TYPE             \ expect: A
```

**Notes.**

* Only the low byte counts: 321 is 256 + 65.
* This is BASIC's `CHR$`. To build a longer string, copy the character with `PLACE` before the next `CHR`.

**See also** `CODE`, `STR`, `CHAR`, [Strings](05_concepts.md#strings).

---

## CODE

`( addr len -- c )` -- **word**, strings

Leaves the code of the first character of the string. It is `DROP C@`: the length is not looked at, so for an empty string it is the byte at *addr*.

```forth
S" A" CODE .             \ expect: 65
S" ABC" CODE .           \ expect: 65
```

**Notes.**

* This is BASIC's `CODE`. Test the length first if the string may be empty.

**See also** `CHR`, `CHAR`, `C@`, [Strings](05_concepts.md#strings).

---

## CONSTANT

`( x "name" -- )` -- **defining word**, memory

Defines *name* as a word that leaves *x*. The value is fixed when *name* is made; to keep a number that changes use `VARIABLE`.

```forth
100 CONSTANT LIMIT
LIMIT .                  \ expect: 100
LIMIT 1+ .               \ expect: 101
```

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `CONSTANT` | `MISSING NAME` |
| no room | `DICTIONARY FULL` |

**See also** `VARIABLE`, `ARRAY`, `FCONSTANT`, [Defining words](05_concepts.md#defining-words).

---

## COS

`( F: f1 -- f2 )` -- **word**, float

Leaves the cosine of the angle *f1*, given in radians. It is accurate to about 9 decimal places.

```forth
0.0 COS F.               \ expect: 1.0000
2.0 COS F.               \ expect: -0.4161
60.0 RAD COS F.          \ expect: 0.5000
```

**Notes.**

* An angle beyond about 102,940 radians in size is refused.
* Standard Forth calls this `FCOS`.

**Errors.**

| Mistake | What happens |
|---|---|
| the angle is beyond about 102,940 radians, either way | `OUT OF RANGE` |

**See also** `SIN`, `TAN`, `RAD`.

---

## COUNT

`( caddr -- addr len )` -- **word**, strings

Turns a counted string into an address and a length. A counted string is a length byte followed by the characters, as `STRING` makes and `PLACE` fills; *caddr* is the address of the length byte. *addr* is *caddr*+1 and *len* is the length byte.

```forth
10 STRING NAME
S" ADA" NAME PLACE
NAME COUNT TYPE          \ expect: ADA
NAME COUNT . DROP        \ expect: 3
```

**See also** `STRING`, `PLACE`, `LEN`, [Strings](05_concepts.md#strings).

---

## CREATE

`( "name" -- )` -- **defining word**, dictionary

Defines *name* as a word that leaves the address of its data field, the first byte after the word, which is where `HERE` stands just after `CREATE`. It reserves nothing: follow it with `,` `C,` or `ALLOT` to fill or reserve the data. With `DOES>` a defining word can give its words behaviour of their own.

```forth
CREATE PRIMES 2 , 3 , 5 , 7 ,
PRIMES 2 CELLS + @ .     \ expect: 5
CREATE FLAGS 8 ALLOT
HERE FLAGS - .           \ expect: 8
```

**Notes.**

* `VARIABLE`, `ARRAY` and `STRING` are `CREATE` and a reservation in one word, and zero what they reserve. `CREATE` does not.

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `CREATE` | `MISSING NAME` |
| no room | `DICTIONARY FULL` |

**See also** `DOES>`, `,`, `ALLOT`, `HERE`, [Defining words](05_concepts.md#defining-words).

---

## DEG

`( F: f1 -- f2 )` -- **word**, float

Turns an angle in radians into degrees: it multiplies by 180/pi.

```forth
PI DEG F.                \ expect: 180.0000
PI 2.0 F/ DEG F.         \ expect: 90.0000
```

**See also** `RAD`, `PI`.

---

## DO

`( limit start -- )` -- **compile-only word**, control

Starts a counted loop that `LOOP` or `+LOOP` closes. When the loop runs, `DO` takes *limit* and *start* from the stack; the body runs with the index at *start*, then *start*+1, and so on, until the index reaches *limit*. `I` gives the index.

```forth
: FIVE 5 0 DO I . LOOP ;
FIVE                     \ expect: 0 1 2 3 4
: ONCE 3 3 DO I . LEAVE LOOP ;
ONCE                     \ expect: 3
```

**Notes.**

* The body always runs at least once: *start* is not compared with *limit* first. When they are equal the body runs 65,536 times, the index going all the way round before it meets the limit again, and a *start* above *limit* counts up through 65,535 to 0 and on to the limit. Check before `DO`, or end the loop with `LEAVE`.
* The index and limit are kept on the machine stack, below anything the body calls. Inside the body `I` and `J` read them; a word called from the body cannot see them.
* Loops can be nested 8 deep in one definition (the table `LEAVE` uses has 8 slots). A deeper nesting is not checked.
* Standard Forth has `?DO`, which skips the loop when *start* equals *limit*. This Forth does not.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `DO ?` |
| no `LOOP` to close it | nothing is noticed; see `IF` |

**See also** `LOOP`, `+LOOP`, `LEAVE`, `I`, `J`, `EXIT`.

---

## DOES>

`( -- )` -- **word**, dictionary

Used in a defining word, after `CREATE`. When the defining word runs, `DOES>` changes the word `CREATE` just made, so that when *it* runs it first leaves its data-field address and then runs the words that follow `DOES>`. `DOES>` also ends the defining word's own run there: the words after it belong to the new words only.

```forth
: CONST CREATE , DOES> @ ;
5 CONST FIVE
FIVE .                   \ expect: 5
: TABLE CREATE 10 , 20 , 30 ,
DOES> SWAP CELLS + @ ;
TABLE NUMS
1 NUMS .                 \ expect: 20
```

**Notes.**

* `DOES>` changes the newest word in the dictionary, so use it right after `CREATE`, with no other definition between.
* The words after `DOES>` start with the data-field address on the stack, under whatever the caller pushed: in `TABLE`, `1 NUMS` is `1 addr`.
* There is no `;CODE` or other way to give the new words machine code.

**See also** `CREATE`, `:`, `IMMEDIATE`, [Defining words](05_concepts.md#defining-words).

---

## DROP

`( x -- )` -- **word**, stack

Removes the top number from the stack.

```forth
1 2 3 DROP . .           \ expect: 2 1
```

**Errors.**

| Mistake | What happens |
|---|---|
| the stack is empty | `STACK?` |

**See also** `2DROP`, `DUP`, [The stacks](05_concepts.md#the-stacks).

---

## DUP

`( x -- x x )` -- **word**, stack

Copies the top number, so that the stack holds it twice.

```forth
7 DUP . .                \ expect: 7 7
5 DUP * .                \ expect: 25
```

**Errors.**

| Mistake | What happens |
|---|---|
| the stack is empty | nothing is reported: `DUP` copies the cell beneath the bottom of the stack and leaves one meaningless number |

**See also** `?DUP`, `2DUP`, `OVER`, `PICK`.

---

## EDIT

`( "name" -- )` -- **EXROM word**, dictionary

Opens the full-screen editor on the line store, the lines you have typed. `EDIT name` puts the cursor on the newest line in which `:` is followed directly by *name*; a bare `EDIT` opens a new empty line at the end. BREAK (CAPS SHIFT + SPACE) leaves the editor, clears the screen and runs the lines you changed or added, in order.

```forth
: SQ DUP + ;
\ keys: \x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x08*\x10
EDIT SQ
5 SQ .                   \ expect: 25
```

The `\ keys:` line stands for the keys pressed in the editor: RIGHT ten times, to just after the `+`; DELETE, to remove it; `*`; then BREAK. (The test writes keys as `\xNN` codes: `\x04` is RIGHT, `\x08` DELETE, `\x10` BREAK.) The line becomes `: SQ DUP * ;`, runs on leaving, and defines `SQ` again.

**Keys.**

| Key | What it does |
|---|---|
| characters, LEFT, RIGHT | edit the cursor line, as at the prompt |
| UP, DOWN | to the previous or next row of a wrapped line, then to the previous or next line, at the same column |
| DELETE | deletes the character left of the cursor; at column 0 of an empty line, deletes the line |
| ENTER | keeps the line and opens a new empty line after it; nothing runs yet |
| CAPS SHIFT + 1 | deletes the cursor line |
| CAPS SHIFT + ENTER | inserts an empty line above the cursor line |
| BREAK | leaves the editor |

**Notes.**

* The editor shows the store 32 columns wide: rows 0 to 22 hold the lines, each wrapped as at the prompt, and row 23 shows `LINE n/m`, the cursor line and the number of lines.
* Only lines you changed or added in the visit run. If one raises an error the message is printed after `LINE n`, and the changed lines after it do not run.
* A line is at most 128 characters and 4 rows. The store holds 8,192 characters: a change that would overflow it is refused and `STORE FULL` shows on row 23 until the next key.
* The `EDIT` line itself is not kept in the store.
* Editing a definition defines the word again; it does not remove the old one (see `FORGET`).

**Errors.**

| Mistake | What happens |
|---|---|
| no line with `:` and that name | `name ?`, as for an unknown word |
| a line in the store has more than 128 characters or needs more than 4 rows | `LONG LINE`, the editor does not open |
| no graphics EXROM fitted | `NO EXROM` |

**See also** `LIST-DEFS`, `FORGET`, [The editor and the line store](05_concepts.md#the-editor-and-the-line-store).

---

## ELSE

`( -- )` -- **compile-only word**, control

Used between `IF` and `THEN`. The words before it run if the flag given to `IF` was true; the words after it run if it was false. At run time, `ELSE` jumps over the words that follow it, to `THEN`.

```forth
: SIGN? 0 < IF 1 ELSE 2
THEN . ;
-5 SIGN?                 \ expect: 1
5 SIGN?                  \ expect: 2
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `ELSE ?` |
| no `IF` before it, or no `THEN` after | nothing is noticed; see `IF` |

**See also** `IF`, `THEN`.

---

## EXECUTE

`( xt -- )` -- **word**, control

Runs the word whose execution token *xt* is on the stack. `'` and `[']` give an *xt*. `EXECUTE` is the same as naming the word, except that the word is chosen while the program runs.

```forth
: SQ DUP * ;
5 ' SQ EXECUTE .         \ expect: 25
3 4 ' + EXECUTE .        \ expect: 7
```

**Notes.**

* *xt* is not checked. A number that is not the code address of a word runs whatever is at that address, and that can crash the machine.
* Recursion through `EXECUTE` is guarded: a word that keeps executing itself ends with `RETURN STACK FULL`.

**See also** `'`, `[']`, `CATCH`.

---

## EXIT

`( -- )` -- **compile-only word**, control

Leaves the definition at once: the rest of the word after `EXIT` is not run, and control returns to the caller. It compiles a return in place. Inside a `DO` loop the loop is discarded properly, so `EXIT` is safe there.

```forth
: FIRST5 10 0 DO I 5 = IF
I EXIT THEN LOOP -1 ;
FIRST5 .                 \ expect: 5
: SUM DUP 0= IF EXIT THEN
DUP 1- SUM + ;
5 SUM .                  \ expect: 15
```

**Notes.**

* `EXIT` does not end the definition; the `;` still has to come.
* Unlike `LEAVE`, it leaves the whole word, not just the loop.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `EXIT ?` |

**See also** `LEAVE`, `;`.

---

## F!

`( addr -- ) ( F: f -- )` -- **word**, float

Takes a decimal off the float stack and stores it, in 5 bytes, at *addr*.

```forth
FVARIABLE X
1.5 X F!
2.25 X F!
X F@ F.                  \ expect: 2.2500
```

**Notes.**

* Decimals stored one after another are 5 bytes apart, not 2: after `X`, the next is `X 5 +`.

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | `STACK?` |

**See also** `F@`, `FVARIABLE`, `!`.

---

## F*

`( F: f1 f2 -- f3 )` -- **word**, float

Multiplies *f1* by *f2* and leaves the product.

```forth
2.0 3.0 F* F.            \ expect: 6.0000
1.5 FDUP F* F.           \ expect: 2.2500
1E38 10.0 F*             \ expect: OUT OF RANGE
```

**Notes.**

* A product too small to hold becomes 0, with no error.
* For whole numbers `*` is much faster.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?`, after `F*` or after the next word that takes a decimal |
| the product is beyond about 1.7E38 | `OUT OF RANGE` |

**See also** `F/`, `F+`, `*`.

---

## F+

`( F: f1 f2 -- f3 )` -- **word**, float

Adds the top two decimals and leaves their sum. A decimal is a number with a fraction; it lives on its own stack, the float
stack, so `F+` does not touch the stack the whole numbers are on.

```forth
3.5 2.5 F+ F.            \ expect: 6.0000
0.1 0.2 F+ F.            \ expect: 0.3000
```

**Notes.**

* **How a decimal is written.** A number with a point (`3.5`, `.5`, `3.`) or an exponent (`1E3`, `2.5e-4`, `-1.5E+3`) is a
  decimal: typed, or inside a definition, it goes on the float stack. Any other number is a whole number and goes on the
  data stack, so `1.5 2` puts 1.5 on one stack and 2 on the other. `+5` is not a number.
* **What a decimal holds.** About 9 significant digits, with a size from about 2.9E-39 to 1.7E38, positive or negative.
  Every result is rounded to the nearest value that fits. A result too big is `OUT OF RANGE`; one too small becomes 0.
  The float stack holds 204 decimals. Part 5 gives the details
  ([Floating point](05_concepts.md#floating-point)).
* The words that work only on decimals start with `F`, as `F+`, `F-`, `F*`, `F/`. A whole number given to them is not
  seen: `3 4 F+` stops with `STACK?`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?`, after `F+` or after the next word that takes a decimal |
| the sum is beyond about 1.7E38 | `OUT OF RANGE` |

**See also** `F-`, `F*`, `F.`, `+`, [Floating point](05_concepts.md#floating-point).

---

## F-

`( F: f1 f2 -- f3 )` -- **word**, float

Subtracts *f2* from *f1* and leaves the difference.

```forth
6.0 2.5 F- F.            \ expect: 3.5000
2.5 6.0 F- F.            \ expect: -3.5000
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?`, after `F-` or after the next word that takes a decimal |
| the difference is beyond about 1.7E38 in size | `OUT OF RANGE` |

**See also** `F+`, `FNEGATE`, `-`.

---

## F.

`( F: f -- )` -- **word**, float

Prints the decimal *f* with a fixed number of digits after the point, then a space. The number of digits is the one `PLACES`
set, 4 when the machine is switched on. With 0 places the point is left out.

```forth
2.5 F.                   \ expect: 2.5000
-0.25 F.                 \ expect: -0.2500
1.0 3.0 F/ F.            \ expect: 0.3333
-0.00001 F.              \ expect: 0.0000
```

**Notes.**

* The digits are rounded, not cut, and a value exactly half way goes away from zero: with 0 places, 2.5 prints as 3 and
  -2.5 as -3. The rounding is of the number the machine actually holds, which for a number like 2.675 is a hair below
  what you typed (2.675 has no exact form in binary), so `2 PLACES 2.675 F.` prints 2.67.
* A value that rounds to zero prints as 0.0000 with no minus sign.
* Every digit before the point is printed, and digits past the ninth or tenth significant one are not meaningful:
  `1E10 F.` prints 10000000000.0000, and `1E38 F.` prints a long row of digits. For very large or small values use
  `FS.`.

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty (a whole number given to `F.` is on the other stack) | a meaningless number is printed, then `STACK?` |

**See also** `PLACES`, `FS.`, `.`, [Floating point](05_concepts.md#floating-point).

---

## F/

`( F: f1 f2 -- f3 )` -- **word**, float

Divides *f1* by *f2* and leaves the quotient.

```forth
1.0 4.0 F/ F.            \ expect: 0.2500
1.0 3.0 F/ F.            \ expect: 0.3333
1.0 0.0 F/               \ expect: DIVISION BY ZERO
```

**Notes.**

* Division by zero is an error here, unlike the whole-number `/`, where it gives 0.
* `F/` does not cut the quotient. To divide whole numbers and keep the fraction, turn them into decimals first:
  `7 S>F 2 S>F F/` is 3.5.

**Errors.**

| Mistake | What happens |
|---|---|
| *f2* is 0 | `DIVISION BY ZERO` |
| the quotient is beyond about 1.7E38 | `OUT OF RANGE` |
| fewer than two decimals on the float stack | `STACK?`, after `F/` or after the next word that takes a decimal |

**See also** `F*`, `S>F`, `/`.

---

## F0<

`( -- flag ) ( F: f -- )` -- **word**, float

Leaves -1 (true) on the data stack if the decimal is below zero, and 0 (false) if it is zero or above. The decimal is
removed.

```forth
-3.0 F0< .               \ expect: -1
3.0 F0< . 0.0 F0< .      \ expect: 0 0
```

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | `STACK?` |

**See also** `F0=`, `F<`.

---

## F0=

`( -- flag ) ( F: f -- )` -- **word**, float

Leaves -1 (true) on the data stack if the decimal is zero, and 0 (false) if it is not. The decimal is removed.

```forth
0.0 F0= .                \ expect: -1
1.0 F0= .                \ expect: 0
```

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | `STACK?` |

**See also** `F0<`, `F=`, `0=`.

---

## F<

`( -- flag ) ( F: f1 f2 -- )` -- **word**, float

Compares two decimals and leaves -1 (true) on the data stack if *f1* is less than *f2*, and 0 (false) if it is not. The
decimals are removed.

```forth
1.5 2.5 F< .             \ expect: -1
2.5 1.5 F< .             \ expect: 0
2.5 2.5 F< .             \ expect: 0
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?` |

**See also** `F>`, `F=`, `<`, [Flags](05_concepts.md#flags).

---

## F=

`( -- flag ) ( F: f1 f2 -- )` -- **word**, float

Compares two decimals and leaves -1 (true) on the data stack if they are exactly equal, and 0 (false) if they are not.
The decimals are removed.

```forth
2.5 2.5 F= .             \ expect: -1
2.5 1.5 F= .             \ expect: 0
```

**Notes.**

* The test is exact. The result of a calculation can differ in its last digit from the number you expect, so to ask
  whether two results are the same, ask whether their difference is small: `F- FABS 0.0001 F<`.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?` |

**See also** `F<`, `F>`, `F0=`, `=`, [Flags](05_concepts.md#flags).

---

## F>

`( -- flag ) ( F: f1 f2 -- )` -- **word**, float

Compares two decimals and leaves -1 (true) on the data stack if *f1* is greater than *f2*, and 0 (false) if it is not.
The decimals are removed.

```forth
2.5 1.5 F> .             \ expect: -1
1.5 2.5 F> .             \ expect: 0
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?` |

**See also** `F<`, `F=`, `>`, [Flags](05_concepts.md#flags).

---

## F>S

`( -- n ) ( F: f -- )` -- **word**, float

Turns the decimal *f* into a whole number by cutting off its fraction (toward zero, so -3.7 gives -3). The whole part
must be from -32768 to 65535, the range a whole number can be typed in; above 32767 it is a negative cell, as it is when typed.

```forth
3.7 F>S .                \ expect: 3
-3.7 F>S .               \ expect: -3
40000.0 F>S .            \ expect: -25536
70000.0 F>S              \ expect: OUT OF RANGE
```

**Notes.**

* To round to the nearest whole number first, use `FROUND`: `3.7 FROUND F>S` is 4.

**Errors.**

| Mistake | What happens |
|---|---|
| the whole part is below -32768 or above 65535 | `OUT OF RANGE` |
| the float stack is empty | `STACK?` |

**See also** `S>F`, `FROUND`, `FLOOR`.

---

## F@

`( addr -- ) ( F: -- f )` -- **word**, float

Fetches the decimal stored at *addr* and puts it on the float stack. A decimal takes 5 bytes of memory.

```forth
FVARIABLE X
2.5 X F!
X F@ X F@ F* F.          \ expect: 6.2500
```

**Notes.**

* `F@` does not check *addr*: any five bytes are read as a decimal.

**See also** `F!`, `FVARIABLE`, `@`.

---

## FABS

`( F: f1 -- f2 )` -- **word**, float

Leaves the size of the decimal *f1* without its sign.

```forth
-1.5 FABS F.             \ expect: 1.5000
1.5 FABS F.              \ expect: 1.5000
```

**See also** `FNEGATE`, `ABS`.

---

## FCONSTANT

`( "name" -- ) ( F: f -- )` -- **defining word**, float

Makes a constant named *name* with the value of the decimal *f*, which is taken off the float stack. Typing *name* later
puts that value on the float stack.

```forth
PI 2.0 F* FCONSTANT TAU
TAU F.                   \ expect: 6.2832
2.5 FCONSTANT RATE
: COST S>F RATE F* ;
4 COST F.                \ expect: 10.0000
```

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | `STACK?` |

**See also** `FVARIABLE`, `CONSTANT`.

---

## FDEPTH

`( -- n )` -- **word**, float

Leaves, on the data stack, the number of decimals now on the float stack.

```forth
FDEPTH .                 \ expect: 0
1.5 2.5 FDEPTH .         \ expect: 2
FDROP FDROP FDEPTH .     \ expect: 0
```

**See also** `FDUP`, `FDROP`, [The stacks](05_concepts.md#the-stacks).

---

## FDROP

`( F: f -- )` -- **word**, float

Removes the top decimal from the float stack.

```forth
1.5 2.5 FDROP F.         \ expect: 1.5000
```

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | `STACK?` |

**See also** `FDUP`, `DROP`.

---

## FDUP

`( F: f -- f f )` -- **word**, float

Copies the top decimal.

```forth
1.5 FDUP F* F.           \ expect: 2.2500
```

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | nothing is reported: a meaningless decimal is left |

**See also** `FDROP`, `FOVER`, `DUP`.

---

## FLOOR

`( F: f1 -- f2 )` -- **word**, float

Rounds the decimal down, to the greatest whole value not above it. The result is still a decimal.

```forth
3.7 FLOOR F.             \ expect: 3.0000
-3.7 FLOOR F.            \ expect: -4.0000
-0.5 FLOOR F.            \ expect: -1.0000
```

**Notes.**

* For a negative value this differs from `F>S`, which cuts toward zero: `-3.7 F>S` is -3.

**See also** `FROUND`, `F>S`.

---

## FMAX

`( F: f1 f2 -- f3 )` -- **word**, float

Leaves the greater of the two decimals.

```forth
1.5 2.5 FMAX F.          \ expect: 2.5000
-1.5 -2.5 FMAX F.        \ expect: -1.5000
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?`, after `FMAX` or after the next word that takes a decimal |

**See also** `FMIN`, `MAX`.

---

## FMIN

`( F: f1 f2 -- f3 )` -- **word**, float

Leaves the lesser of the two decimals.

```forth
1.5 2.5 FMIN F.          \ expect: 1.5000
-1.5 -2.5 FMIN F.        \ expect: -2.5000
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two decimals on the float stack | `STACK?`, after `FMIN` or after the next word that takes a decimal |

**See also** `FMAX`, `MIN`.

---

## FNEGATE

`( F: f1 -- f2 )` -- **word**, float

Changes the sign of the decimal *f1*. Zero stays zero.

```forth
1.5 FNEGATE F.           \ expect: -1.5000
0.0 FNEGATE F.           \ expect: 0.0000
```

**See also** `FABS`, `NEGATE`.

---

## FORGET

`( "name" -- )` -- **word**, dictionary

Removes the word *name* and every word defined after it, and gives their memory back: `HERE` goes back to where *name* began. Words defined before it are untouched.

```forth
: A 1 ;  : B 2 ;  : C 3 ;
FORGET B
A .                      \ expect: 1
B                        \ expect: B ?
C                        \ expect: C ?
FORGET DUP               \ expect: FORGET: BUILT-IN, REFUSED
FORGET NOSUCH            \ expect: FORGET: NOT FOUND
```

**Notes.**

* The words of the ROM cannot be forgotten.
* The two messages are printed, not thrown: they are not errors, and the rest of the line goes on.
* The line store is not changed, so `LIST-DEFS` still lists the lines of forgotten words.
* Addresses you kept from the forgotten words (an *xt* from `'`, the address of a variable) point at memory that new definitions will reuse.

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `FORGET` | `MISSING NAME` |
| *name* is not in the dictionary | `FORGET: NOT FOUND` |
| *name* is a ROM word | `FORGET: BUILT-IN, REFUSED` |

**See also** `:`, `FREE`, `HERE`, [The dictionary](05_concepts.md#the-dictionary).

---

## FOVER

`( F: f1 f2 -- f1 f2 f1 )` -- **word**, float

Copies the second decimal from the top onto the top.

```forth
1.5 2.5 FOVER F. F. F.   \ expect: 1.5000 2.5000 1.5000
```

**See also** `FDUP`, `FSWAP`, `OVER`.

---

## FREE

`( -- n )` -- **word**, memory

Leaves the number of bytes between `HERE` and the top of the dictionary (address 53,248). It shrinks as you define words and use `,` `C,` and `ALLOT`.

```forth
FREE 100 ALLOT FREE - .  \ expect: 100
```

**Notes.**

* The last 256 bytes are kept so that a definition in progress can finish: a definition, `,`, `C,` or `ALLOT` that would reach them stops with `DICTIONARY FULL`. The most you can reserve with `ALLOT` is `FREE` minus 256.
* The line store (where `EDIT` keeps your typed lines) is above the dictionary and not counted.

**See also** `HERE`, `ALLOT`, [The dictionary](05_concepts.md#the-dictionary), [Memory](05_concepts.md#memory).

---

## FROUND

`( F: f1 -- f2 )` -- **word**, float

Rounds the decimal to the nearest whole value. A value exactly half way goes away from zero. The result is still a
decimal.

```forth
3.7 FROUND F.                \ expect: 4.0000
2.5 FROUND F. -2.5 FROUND F. \ expect: 3.0000 -3.0000
2.4 FROUND F.                \ expect: 2.0000
```

**Notes.**

* `FROUND F>S` gives the nearest whole number as a whole number.

**See also** `FLOOR`, `F>S`.

---

## FS.

`( F: f -- )` -- **word**, float

Prints the decimal *f* in scientific notation: one digit, a point, the digits after it, `E` and the power of ten, then a
space. The number of digits after the point is the one `PLACES` set.

```forth
12345.678 FS.            \ expect: 1.2346E4
-12345.678 FS.           \ expect: -1.2346E4
1E-6 FS.                 \ expect: 1.0000E-6
0.0 FS.                  \ expect: 0.0000E0
2 PLACES 12345.678 FS.   \ expect: 1.23E4
```

**Notes.**

* The power of ten is written in ordinary digits, with a `-` when it is negative and no `+`.
* The digits are rounded as `F.` rounds them; when the rounding reaches 10 the result is 1 and the power goes up one.
* Use it for results whose size matters more than their digits: `PI SIN FS.` prints `1.2154E-10`, the small amount by
  which the machine's PI differs from the true one.

**Errors.**

| Mistake | What happens |
|---|---|
| the float stack is empty | a meaningless number is printed, then `STACK?` |

**See also** `F.`, `PLACES`.

---

## FSQRT

`( F: f1 -- f2 )` -- **word**, float

Leaves the square root of the decimal *f1*. The root of 0 is 0.

```forth
9.0 FSQRT F.             \ expect: 3.0000
2.0 FSQRT F.             \ expect: 1.4142
-1.0 FSQRT               \ expect: INVALID ARGUMENT
```

**Notes.**

* For the square root of a whole number, cut to a whole number, use `SQRT`.

**Errors.**

| Mistake | What happens |
|---|---|
| *f1* is below 0 | `INVALID ARGUMENT` |

**See also** `SQRT`.

---

## FSWAP

`( F: f1 f2 -- f2 f1 )` -- **word**, float

Exchanges the top two decimals.

```forth
1.5 2.5 FSWAP F. F.      \ expect: 1.5000 2.5000
```

**See also** `FOVER`, `SWAP`.

---

## FVARIABLE

`( "name" -- )` -- **defining word**, float

Makes a variable named *name* that holds a decimal, and sets it to 0. Typing *name* later puts its address on the
stack, as `VARIABLE` does; use `F@` and `F!` to read and write it.

```forth
FVARIABLE TOTAL
TOTAL F@ F.              \ expect: 0.0000
1.5 TOTAL F!
TOTAL F@ 2.25 F+ TOTAL F!
TOTAL F@ F.              \ expect: 3.7500
```

**Notes.**

* The variable holds 5 bytes, in the dictionary after its name.

**Errors.**

| Mistake | What happens |
|---|---|
| no name follows | `MISSING NAME` |

**See also** `F@`, `F!`, `FCONSTANT`, `VARIABLE`.

---

## HERE

`( -- addr )` -- **word**, memory

Leaves the address of the next free byte of the dictionary. Every new word, and every `,` `C,` and `ALLOT`, moves it up.

```forth
HERE 2 ALLOT HERE SWAP - .  \ expect: 2
CREATE PT 7 ,
HERE PT - .                 \ expect: 2
```

**Notes.**

* `HERE` is the address a `CREATE`d word gives, until you reserve something after it.

**See also** `ALLOT`, `,`, `FREE`, `CREATE`, [The dictionary](05_concepts.md#the-dictionary).

---

## I

`( -- n )` -- **word**, control

Leaves the index of the innermost `DO` loop.

```forth
: THREE 3 0 DO I . LOOP ;
THREE                    \ expect: 0 1 2
: FROM2 4 2 DO I . LOOP ;
FROM2                    \ expect: 2 3
```

**Notes.**

* `I` reads the loop's values from the machine stack right under its own return address, so it works only in the word that holds the `DO`. In a word called from the loop body it gives a meaningless number.
* Outside any loop `I` also gives a meaningless number, and no error.

**See also** `J`, `DO`, `LOOP`.

---

## IF

`( flag -- )` -- **compile-only word**, control

Takes a flag. If it is not 0, the words up to `ELSE` or `THEN` run; if it is 0 they are skipped (and the words after `ELSE` run instead). Any number but 0 counts as true.

```forth
: TEST IF 1 ELSE 2 THEN . ;
5 TEST                   \ expect: 1
0 TEST                   \ expect: 2
: AFTER IF 11 . THEN 12 . ;
0 AFTER                  \ expect: 12
-1 AFTER                 \ expect: 11 12
```

**Notes.**

* `IF` structures can be nested.
* Control words are not checked against each other. An `IF` with no `THEN`, a `THEN` with no `IF`, or a `BEGIN` closed by a `THEN` is compiled without complaint and does something strange when it runs.
* A flag from `=` `<` `>` `0=` is -1 or 0; any other number works as well.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `IF ?`, and nothing is compiled |
| no flag on the stack | `STACK?`, after the word or after the next word that takes a number |

**See also** `ELSE`, `THEN`, `0=`, [Flags](05_concepts.md#flags).

---

## IMMEDIATE

`( -- )` -- **word**, dictionary

Marks the newest word immediate: from now on it runs at once even inside a definition, instead of being compiled. Put it straight after the `;` of the definition.

```forth
: HI ." hi " ; IMMEDIATE
: T HI ." there" ;       \ expect: hi
T                        \ expect: there
```

**Notes.**

* `HI` printed while `T` was compiled, not when `T` runs. `T` itself holds only `there`.
* Typed inside a definition, `IMMEDIATE` is compiled, not run; use it after the `;`.
* The words `IF`, `DO`, `;` and others of the language are immediate or compile-only in this way. `[']` and `[CHAR]` are too.

**See also** `:`, `;`, `[`, [Compiling and interpreting](05_concepts.md#compiling-and-interpreting).

---

## INVERT

`( n1 -- n2 )` -- **word**, arithmetic

Flips every one of the 16 bits of *n1*. The result is -*n1* - 1.

```forth
0 INVERT .               \ expect: -1
5 INVERT .               \ expect: -6
```

**Notes.**

* There is no `NOT`. `0=` turns a flag into its opposite; `INVERT` flips the bits of any number, and `1 INVERT` is
  -2, which is not a flag.

**See also** `0=`, `AND`, `NEGATE`.

---

## J

`( -- n )` -- **word**, control

Leaves the index of the loop around the innermost one: in a `DO` loop inside another, `I` is the inner index and `J` the outer.

```forth
: GRID 2 0 DO 2 0 DO
J . I . LOOP LOOP ;
GRID                     \ expect: 0 0 0 1 1 0 1 1
```

**Notes.**

* Outside two nested loops `J` gives a meaningless number, with no error. Like `I`, it works only in the word that holds the loops.

**See also** `I`, `DO`, `LOOP`.

---

## LEAVE

`( -- )` -- **compile-only word**, control

Ends the innermost `DO` loop at once: the words between `LEAVE` and `LOOP` are skipped, and the program carries on after `LOOP`. A loop can hold any number of `LEAVE`s, usually inside an `IF`.

```forth
: UPTO3 10 0 DO I 3 =
IF LEAVE THEN I . LOOP 99 . ;
UPTO3                    \ expect: 0 1 2 99
```

**Notes.**

* Only the innermost loop ends. In a loop inside a loop, the outer one goes on.
* `LEAVE` belongs inside a `DO` loop; its use anywhere else is not checked.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `LEAVE ?` |

**See also** `DO`, `LOOP`, `EXIT`.

---

## LEFT

`( addr len n -- addr len2 )` -- **word**, strings

Leaves the first *n* characters of the string: the same address, and *len2* the smaller of *n* and *len*. Nothing is copied. If *n* is *len* or more, or more than 255, or negative, the string is left whole.

```forth
: HAY S" HELLO WORLD" ;
HAY 5 LEFT TYPE          \ expect: HELLO
HAY 99 LEFT TYPE         \ expect: HELLO WORLD
HAY 0 LEFT . DROP        \ expect: 0
```

**Notes.**

* This is BASIC's `LEFT$`. The result is a view of the same memory, so changing it (with `UPPER`, say) changes the original.

**See also** `RIGHT`, `SEARCH`, [Strings](05_concepts.md#strings).

---

## LEN

`( caddr -- n )` -- **word**, strings

Leaves the length byte of a counted string, the kind `STRING` makes: *n* is how many characters it holds now.

```forth
10 STRING NAME
NAME LEN .               \ expect: 0
S" ADA" NAME PLACE
NAME LEN .               \ expect: 3
```

**Notes.**

* Unlike BASIC's `LEN`, this takes the address of a counted string, not an address and a length. For the pair that `S"` or `STR` leaves, the length is already on top: `DUP .` or `SWAP DROP`.

**See also** `COUNT`, `STRING`, `PLACE`, [Strings](05_concepts.md#strings).

---

## LIST-DEFS

`( -- )` -- **word**, dictionary

Lists the colon definitions in the line store, oldest first, each on its own row: its number from 0, then `:` and the first 20 characters of its source. It lists only the first 16.

```forth
: AA DUP + ;
: BB DUP - ;
: LONG-ONE 1 2 3 4 5 + + + + ;
LIST-DEFS                \ expect: 0: : AA DUP + ;|1: : BB DUP - ;|2: : LONG-ONE 1 2 3 4 5
```

**Notes.**

* The store holds each line you entered (or loaded with `LOAD-TEXT`), including those that failed. A definition is found from its `:` to the `;`; a `;` inside a string, a `(` comment or after a `\` does not end it.
* Redefine a word with `EDIT` and the line is replaced in the store; redefine it by typing and both lines are listed.

**See also** `EDIT`, `FORGET`, [The editor and the line store](05_concepts.md#the-editor-and-the-line-store).

---

## LITERAL

`( n -- )` -- **compile-only word**, dictionary

Used inside a definition, with `[` and `]`: compiles *n* as a number in the definition, so that when the definition runs it leaves *n*. It is how a value worked out while compiling goes into the definition.

```forth
: SEVEN [ 3 4 + ] LITERAL ;
SEVEN .                  \ expect: 7
5 LITERAL                \ expect: LITERAL ?
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `LITERAL ?` |

**See also** `[`, `]`, `[']`, `[CHAR]`, [Compiling and interpreting](05_concepts.md#compiling-and-interpreting).

---

## LOOP

`( -- )` -- **compile-only word**, control

Closes a `DO` loop. At run time it adds 1 to the index; if the index has not reached the limit, the program goes back to the first word after `DO`, otherwise it carries on after `LOOP`.

```forth
: ROW 4 1 DO I . LOOP ;
ROW                      \ expect: 1 2 3
```

**Notes.**

* The index runs from *start* to *limit* minus 1. To count in other steps use `+LOOP`.

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `LOOP ?` |

**See also** `DO`, `+LOOP`, `LEAVE`, `I`.

---

## LOWER

`( addr len -- addr len )` -- **word**, strings

Changes the letters A to Z of the string to a to z, in place, and leaves the string. Other characters are unchanged.

```forth
: GREETING S" Hello, World" ;
GREETING LOWER TYPE      \ expect: hello, world
```

**Notes.**

* The string must be in RAM; a string in the ROM is not changed and no error is shown.
* This is BASIC's `LOWER$`, except that it works on the string itself instead of making a copy. A string from `S"` inside a definition is changed for good.

**See also** `UPPER`, [Strings](05_concepts.md#strings).

---

## MAX

`( n1 n2 -- n3 )` -- **word**, arithmetic

Leaves the greater of *n1* and *n2*, comparing them as signed numbers.

```forth
5 3 MAX .                \ expect: 5
-5 -1 MAX .              \ expect: -1
32767 -32768 MAX .       \ expect: 32767
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `MAX` or after the next word that takes a number |

**See also** `MIN`, `FMAX`.

---

## MIN

`( n1 n2 -- n3 )` -- **word**, arithmetic

Leaves the lesser of *n1* and *n2*, comparing them as signed numbers.

```forth
5 3 MIN .                \ expect: 3
-5 -1 MIN .              \ expect: -5
32767 -32768 MIN .       \ expect: -32768
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `MIN` or after the next word that takes a number |

**See also** `MAX`, `FMIN`.

---

## MOD

`( n1 n2 -- n3 )` -- **word**, arithmetic

Leaves the remainder of *n1* divided by *n2*. The remainder has the sign of *n1*. Dividing by zero is not an error:
the remainder is 0.

```forth
17 5 MOD .               \ expect: 2
-17 5 MOD . 17 -5 MOD .  \ expect: -2 2
17 0 MOD .               \ expect: 0
```

**Notes.**

* Standard Forth leaves the sign of the remainder to each system. Here it follows `/`, which cuts toward zero, so
  `n1 n2 / n2 * n1 n2 MOD +` gives *n1* back. This is also what C's `%` does.
* `-32768 -1 MOD` is 0.

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `MOD` or after the next word that takes a number |

**See also** `/`, `*`.

---

## NEGATE

`( n1 -- n2 )` -- **word**, arithmetic

Changes the sign of *n1*. `-32768` has no positive partner in a cell, so it stays -32768.

```forth
5 NEGATE . -5 NEGATE .   \ expect: -5 5
-32768 NEGATE .          \ expect: -32768
```

**Notes.**

* `NEGATE` is the arithmetic opposite; `INVERT` flips every bit and gives one less: `5 INVERT` is -6.

**See also** `ABS`, `INVERT`, `FNEGATE`.

---

## OR

`( n1 n2 -- n3 )` -- **word**, arithmetic

Combines *n1* and *n2* bit by bit: a bit of the result is 1 where either has a 1. It also joins two flags.

```forth
15 240 OR .              \ expect: 255
0 -1 OR .                \ expect: -1
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `OR` or after the next word that takes a number |

**See also** `AND`, `XOR`, [Flags](05_concepts.md#flags).

---

## OVER

`( x1 x2 -- x1 x2 x1 )` -- **word**, stack

Copies the second number from the top onto the top.

```forth
1 2 OVER . . .           \ expect: 1 2 1
```

**See also** `DUP`, `PICK`, `2DUP`.

---

## PI

`( F: -- f )` -- **word**, float

Puts the decimal nearest to pi, 3.14159265347, on the float stack. It is a little under the true pi, which is
3.14159265359.

```forth
PI F.                    \ expect: 3.1416
PI 2.0 F* F.             \ expect: 6.2832
```

**Notes.**

* Because the stored pi is not exact, `PI SIN` is not 0 but 1.2154E-10.

**See also** `RAD`, `DEG`, `SIN`.

---

## PICK

`( xu ... x1 x0 u -- xu ... x1 x0 xu )` -- **word**, stack

Copies the *u*-th number down the stack to the top, counting the top number (just under *u*) as number 0: `0 PICK` is
`DUP` and `1 PICK` is `OVER`.

```forth
10 20 30 2 PICK . . . .  \ expect: 10 30 20 10
7 8 1 PICK . . .         \ expect: 7 8 7
```

**Notes.**

* *u* is taken as unsigned and is not checked. When it reaches beyond the numbers you put on the stack, `PICK` copies
  whatever is in memory there.

**See also** `DUP`, `OVER`, `ROT`.

---

## PLACE

`( addr len dest -- )` -- **word**, strings

Copies the *len* characters at *addr* into the counted string *dest* and sets its length byte to *len*. *dest* is usually a `STRING` buffer.

```forth
10 STRING NAME
S" HELLO" NAME PLACE
NAME COUNT TYPE          \ expect: HELLO
S" HI" NAME PLACE
NAME COUNT TYPE          \ expect: HI
```

**Notes.**

* Nothing checks that *dest* is big enough. `PLACE` of more than *n* characters into an *n*-character `STRING` overwrites the memory that follows it. *len* is one byte: only its low 8 bits count.

**See also** `STRING`, `COUNT`, `S"`, [Strings](05_concepts.md#strings).

---

## PLACES

`( n -- )` -- **word**, float

Sets the number of digits after the point that `F.` and `FS.` print: 0 to 9. The machine starts with 4. The setting stays
until the next `PLACES`.

```forth
PI F.                    \ expect: 3.1416
2 PLACES PI F.           \ expect: 3.14
0 PLACES PI F.           \ expect: 3
9 PLACES PI F.           \ expect: 3.141592653
10 PLACES                \ expect: OUT OF RANGE
```

**Notes.**

* A decimal holds about 9 significant digits, so a large number of places shows digits that mean nothing. The last
  digit of `9 PLACES PI F.` is already 3 where the true pi rounds to 4.
* Standard Forth has no `PLACES`; it sets the number of significant digits with `SET-PRECISION`.

**Errors.**

| Mistake | What happens |
|---|---|
| *n* is below 0 or above 9 | `OUT OF RANGE`, and the setting is as it was |

**See also** `F.`, `FS.`.

---

## QUIT

`( -- )` -- **word**, errors

Gives up like `ABORT` but keeps the stacks as they are: stops everything that is running, however deep, and returns to the prompt. Nothing after it on the line runs, and no `OK` is printed.

```forth
5 QUIT 6 .
.                        \ expect: 5
```

**Notes.**

* Like `ABORT` it goes past every `CATCH`.
* If a definition is open when it runs, the definition is dropped.

**See also** `ABORT`, `THROW`, `CATCH`, [Errors](05_concepts.md#errors).

---

## RAD

`( F: f1 -- f2 )` -- **word**, float

Turns an angle in degrees into radians: it multiplies by pi/180.

```forth
90.0 RAD F.              \ expect: 1.5708
45.0 RAD SIN F.          \ expect: 0.7071
```

**See also** `DEG`, `SIN`, `COS`, `TAN`.

---

## RANDOMIZE

`( n -- )` -- **word**, arithmetic

Sets where the random numbers of `RND` start. The same *n* (not 0) always gives the same run of numbers. 0 means no
fixed start: the next `RND` takes one from the processor's refresh counter, which differs from run to run.

```forth
7 RANDOMIZE 6 RND .      \ expect: 3
7 RANDOMIZE 6 RND .      \ expect: 3
6 RND .                  \ expect: 5
```

**Notes.**

* The machine starts with no fixed seed, so a program that wants the same numbers each time begins with `n RANDOMIZE`.
  A program that wants different numbers each time need do nothing.
* *n* is the generator's whole state; any 16-bit value but 0 is a valid start.

**Errors.**

| Mistake | What happens |
|---|---|
| the stack is empty | `STACK?` |

**See also** `RND`.

---

## REPEAT

`( -- )` -- **compile-only word**, control

Closes a `BEGIN ... WHILE ... REPEAT` loop: at run time it jumps back to `BEGIN`. The loop ends when `WHILE` finds a 0 flag.

```forth
: SMALLER 0 BEGIN DUP 3 <
WHILE DUP . 1+ REPEAT DROP ;
SMALLER                  \ expect: 0 1 2
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `REPEAT ?` |

**See also** `BEGIN`, `WHILE`, `UNTIL`.

---

## RIGHT

`( addr len n -- addr2 len2 )` -- **word**, strings

Leaves the last *n* characters of the string: *len2* the smaller of *n* and *len*, and *addr2* the address of the first of them. Nothing is copied. If *n* is *len* or more, or more than 255, or negative, the string is left whole.

```forth
: HAY S" HELLO WORLD" ;
HAY 5 RIGHT TYPE         \ expect: WORLD
HAY 99 RIGHT TYPE        \ expect: HELLO WORLD
HAY 0 RIGHT . DROP       \ expect: 0
```

**Notes.**

* This is BASIC's `RIGHT$`. The result is a view of the same memory.

**See also** `LEFT`, `SEARCH`, [Strings](05_concepts.md#strings).

---

## RND

`( n1 -- n2 )` -- **word**, arithmetic

Leaves a random whole number from 0 up to *n1* - 1: `6 RND` is 0 to 5, each about equally likely. If *n1* is 0 or negative
the result is 0.

```forth
42 RANDOMIZE 10 RND .    \ expect: 2
10 RND .                 \ expect: 8
0 RND . -5 RND .         \ expect: 0 0
```

**Notes.**

* The sequence is fixed by the seed. After `n RANDOMIZE`, with *n* not 0, the same calls give the same numbers every
  time, on every machine with this ROM: the first two lines above always print 2 and 8. With no `RANDOMIZE` (or after `0 RANDOMIZE`) the first `RND` starts from the processor's refresh counter,
  which depends on the moment, so each run is different.
* The generator is a 16-bit xorshift, which cycles through 65,535 values before it repeats. The result is the
  generator's value scaled to the range (not its remainder), so the small numbers are not favoured.
* A call with *n1* of 0 or less does not advance the generator.
* A number typed above 32767 is negative: `40000 RND` is 0.
* Not standard Forth. It does the work of Sinclair BASIC's `INT (RND*n1)`.

**See also** `RANDOMIZE`, [Numbers](05_concepts.md#numbers).

---

## ROT

`( x1 x2 x3 -- x2 x3 x1 )` -- **word**, stack

Moves the third number from the top to the top.

```forth
1 2 3 ROT . . .          \ expect: 1 3 2
```

**See also** `SWAP`, `PICK`.

---

## S"

`( -- addr len )` -- **immediate word**, strings

Reads text up to the next `"` and makes it a string. Inside a definition it compiles the text into the definition, and when the definition runs it leaves the address and length of that text. At the prompt it leaves the address and length at once. Write one space after `S"`; the text starts at the next character and is kept as typed, upper and lower case alike.

```forth
: HI S" Hello" TYPE ;
HI                       \ expect: Hello
S" abc" . DROP           \ expect: 3
```

**Notes.**

* At the prompt the text is not kept anywhere safe: it sits in free dictionary space above `HERE`, and the next definition, `,` or `S"` overwrites it. Two `S"` on one line therefore overwrite each other; put the second in a definition. A string inside a definition is part of it and stays.
* The length is kept in one byte, so a string of more than 255 characters is not supported.
* A line with no closing `"` takes the rest of the line as the text; there is no error.
* The address and length are not a counted string. To keep the text, copy it with `PLACE`.

**See also** `TYPE`, `PLACE`, `COUNT`, `STRING`, [Strings](05_concepts.md#strings).

---

## S>F

`( n -- ) ( F: -- f )` -- **word**, float

Turns the whole number *n* into the same value as a decimal. It is exact. The decimal is put on the float stack.

```forth
42 S>F F.                \ expect: 42.0000
-7 S>F F.                \ expect: -7.0000
7 S>F 2 S>F F/ F.        \ expect: 3.5000
```

**Notes.**

* A whole number typed above 32767 is a negative cell, so `40000 S>F` is -25536.
* The other way is `F>S`.

**Errors.**

| Mistake | What happens |
|---|---|
| the data stack is empty | `STACK?` |

**See also** `F>S`, [Floating point](05_concepts.md#floating-point).

---

## SEARCH

`( addr1 len1 addr2 len2 -- addr3 len3 flag )` -- **word**, strings

Looks for the second string in the first. If it is found, *addr3 len3* is the rest of the first string from the match on, and *flag* is true (-1). If not, *addr3 len3* is the first string unchanged and *flag* is false (0). An empty second string is never found.

```forth
: HAY S" HELLO WORLD" ;
: W S" WORLD" ;
: LO S" LO" ;
: NO S" XYZ" ;
HAY W SEARCH . TYPE      \ expect: -1 WORLD
HAY LO SEARCH . TYPE     \ expect: -1 LO WORLD
HAY NO SEARCH . TYPE     \ expect: 0 HELLO WORLD
```

**Notes.**

* This is BASIC's `INSTR`, with the answer as the rest of the string instead of a position. To get the position, subtract: the match starts `addr3 addr1 -` characters in (take the addresses before dropping the pair).
* The first match is found. A second string longer than the first is simply not found.
* Put each `S"` in a definition, as above: two `S"` typed on one line at the prompt overwrite each other.

**See also** `LEFT`, `RIGHT`, `S"`, [Strings](05_concepts.md#strings).

---

## SGN

`( n1 -- n2 )` -- **word**, arithmetic

Leaves -1 if *n1* is below zero, 0 if it is zero, and 1 if it is above zero.

```forth
-8 SGN . 0 SGN . 40 SGN . \ expect: -1 0 1
```

**Notes.**

* A number typed above 32767 is a negative cell: `40000 SGN` is -1.
* Not standard Forth. The name and the result are Sinclair BASIC's `SGN`.

**See also** `ABS`, `0=`.

---

## SIN

`( F: f1 -- f2 )` -- **word**, float

Leaves the sine of the angle *f1*, given in radians (pi radians is 180 degrees; for degrees use `RAD` first). It is
accurate to about 9 decimal places.

```forth
0.0 SIN F.               \ expect: 0.0000
1.0 SIN F.               \ expect: 0.8415
30.0 RAD SIN F.          \ expect: 0.5000
PI SIN FS.               \ expect: 1.2154E-10
```

**Notes.**

* An angle beyond about 102,940 radians in size (some 16,000 turns) is refused.
* Standard Forth calls this `FSIN`.

**Errors.**

| Mistake | What happens |
|---|---|
| the angle is beyond about 102,940 radians, either way | `OUT OF RANGE` |

**See also** `COS`, `TAN`, `RAD`, `PI`.

---

## SQRT

`( n1 -- n2 )` -- **word**, arithmetic

Leaves the square root of *n1*, with the fraction cut off: the greatest whole number whose square is not above *n1*. A
negative *n1* gives 0, with no error.

```forth
16 SQRT . 15 SQRT .      \ expect: 4 3
32767 SQRT .             \ expect: 181
-4 SQRT .                \ expect: 0
```

**Notes.**

* Not standard Forth. For the square root of a decimal use `FSQRT`.

**See also** `FSQRT`.

---

## STR

`( n -- addr len )` -- **word**, strings

Makes the decimal text of *n*, as `.` would print it but without the trailing space, and leaves its address and length. A negative number starts with `-`; the longest is `-32768`, six characters. The text is kept in one buffer that every `STR` uses, so it lasts only until the next `STR`.

```forth
-42 STR TYPE             \ expect: -42
1234 STR . DROP          \ expect: 4
0 STR TYPE               \ expect: 0
```

**Notes.**

* This is BASIC's `STR$`. To keep the text, copy it with `PLACE`.

**See also** `VAL`, `CHR`, `.`, [Strings](05_concepts.md#strings).

---

## STRING

`( n "name" -- )` -- **defining word**, strings

Defines *name* as a counted-string buffer that can hold up to *n* characters, empty to start with. Executing *name* leaves its address. The buffer is a length byte followed by *n* bytes, so it takes *n*+1 bytes. Fill it with `PLACE`; read it with `COUNT` or `LEN`.

```forth
10 STRING NAME
NAME LEN .               \ expect: 0
S" ADA" NAME PLACE
NAME COUNT TYPE          \ expect: ADA
```

**Notes.**

* The length byte holds 0 to 255, so *n* above 255 makes a buffer that `PLACE` and `LEN` cannot fill or read fully.
* The size is not checked later: see `PLACE`.

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `STRING` | `MISSING NAME` |
| no room | `DICTIONARY FULL` |

**See also** `PLACE`, `COUNT`, `LEN`, `VARIABLE`, [Strings](05_concepts.md#strings).

---

## SWAP

`( x1 x2 -- x2 x1 )` -- **word**, stack

Exchanges the top two numbers.

```forth
1 2 SWAP . .             \ expect: 1 2
10 3 SWAP - .            \ expect: -7
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | nothing is reported at `SWAP`: it uses cells beneath the bottom of the stack, so the number it leaves there is meaningless |

**See also** `OVER`, `ROT`.

---

## TAN

`( F: f1 -- f2 )` -- **word**, float

Leaves the tangent of the angle *f1*, given in radians: the sine divided by the cosine.

```forth
1.0 TAN F.               \ expect: 1.5574
PI 4.0 F/ TAN F.         \ expect: 1.0000
PI 2.0 F/ TAN            \ expect: DIVISION BY ZERO
```

**Notes.**

* A right angle has no tangent. The machine's pi divided by two gives a cosine of exactly 0, so `PI 2.0 F/ TAN` is the
  error shown.
* An angle beyond about 102,940 radians in size is refused.
* Standard Forth calls this `FTAN`.

**Errors.**

| Mistake | What happens |
|---|---|
| the cosine of the angle is exactly 0 | `DIVISION BY ZERO` |
| the angle is beyond about 102,940 radians, either way | `OUT OF RANGE` |

**See also** `SIN`, `COS`, `RAD`.

---

## THEN

`( -- )` -- **compile-only word**, control

Ends an `IF` (or `IF ... ELSE`): the program carries on here, whichever way the flag went. It compiles nothing; it only settles where `IF` and `ELSE` jump to.

```forth
: AFTER IF 11 . THEN 12 . ;
0 AFTER                  \ expect: 12
7 AFTER                  \ expect: 11 12
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `THEN ?` |
| no `IF` before it | nothing is noticed; see `IF` |

**See also** `IF`, `ELSE`.

---

## THROW

`( n -- )` -- **word**, errors

If *n* is 0, does nothing. Otherwise stops everything that is running and goes back to the nearest `CATCH`, which leaves *n*. With no `CATCH`, both stacks are emptied, a message for *n* is printed in place of `OK`, and the prompt returns.

```forth
: FAIL 42 THROW 1 . ;
' FAIL CATCH .           \ expect: 42
0 THROW  5 .             \ expect: 5
-28 THROW                \ expect: BREAK
7 THROW                  \ expect: ERROR 7
```

**Notes.**

* The ROM throws these: -5 `RETURN STACK FULL`, -8 `DICTIONARY FULL`, -13 `UNDEFINED WORD`, -16 `MISSING NAME`, -28 `BREAK`, -37 `TAPE ERROR`, -42 `DIVISION BY ZERO`, -43 `OUT OF RANGE`, -46 `INVALID ARGUMENT`. Any other number prints `ERROR` and the number. -3 and -4 print `STACK?`. All are in [Appendix A](08_appendices.md#appendix-a-messages-and-error-codes).
* BREAK pressed while a word runs is `-28 THROW`, wherever the word was. A program can catch it, tidy up and go on.
* Standard Forth keeps -1 to -255 for the system, so use positive numbers for your own codes.

**Errors.**

| Mistake | What happens |
|---|---|
| no number on the stack | `STACK?`, after the word or after the next word that takes a number |

**See also** `CATCH`, `ABORT`, `QUIT`, [Errors](05_concepts.md#errors), [BREAK](05_concepts.md#break).

---

## UNTIL

`( flag -- )` -- **compile-only word**, control

Closes a `BEGIN ... UNTIL` loop. At run time it takes a flag: if it is 0 the program goes back to `BEGIN`, otherwise it carries on after `UNTIL`. The body runs at least once.

```forth
: TO3 0 BEGIN 1+ DUP .
DUP 3 = UNTIL DROP ;
TO3                      \ expect: 1 2 3
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `UNTIL ?` |

**See also** `BEGIN`, `WHILE`, `REPEAT`, `0=`.

---

## UPPER

`( addr len -- addr len )` -- **word**, strings

Changes the letters a to z of the string to A to Z, in place, and leaves the string. Other characters are unchanged.

```forth
: GREETING S" Hello, World" ;
GREETING UPPER TYPE      \ expect: HELLO, WORLD
GREETING TYPE            \ expect: HELLO, WORLD
```

**Notes.**

* The second line shows that the text inside the definition itself was changed, not a copy. Each time `GREETING` runs, its text is as it was left.
* The string must be in RAM; a string in the ROM is not changed and no error is shown.
* This is BASIC's `UPPER$`, except that it works on the string itself.

**See also** `LOWER`, [Strings](05_concepts.md#strings).

---

## VAL

`( addr len -- n )` -- **word**, strings

Converts the decimal text of the string to a number. The text is digits with an optional `-` first. A string that is empty, is a lone `-`, or has any other character (a space, a `+`, a letter, a decimal point) gives 0, with no error.

```forth
S" 1234" VAL .           \ expect: 1234
S" -17" VAL .            \ expect: -17
S" 12abc" VAL .          \ expect: 0
```

**Notes.**

* The result wraps at 16 bits like any other whole-number arithmetic: `S" 99999"` gives -31073.
* `VAL` does not look words up and does not read decimals; for a fraction use the float words.

**See also** `STR`, [Strings](05_concepts.md#strings), [Numbers](05_concepts.md#numbers).

---

## VARIABLE

`( "name" -- )` -- **defining word**, memory

Defines *name* as a variable: a cell of memory, set to 0. Executing *name* leaves the cell's address; `@` reads it and `!` changes it.

```forth
VARIABLE COUNT-ME
COUNT-ME @ .             \ expect: 0
5 COUNT-ME !
COUNT-ME @ 1+ COUNT-ME !
COUNT-ME @ .             \ expect: 6
```

**Errors.**

| Mistake | What happens |
|---|---|
| no name after `VARIABLE` | `MISSING NAME` |
| no room | `DICTIONARY FULL` |

**See also** `@`, `!`, `CONSTANT`, `ARRAY`, `FVARIABLE`, [Defining words](05_concepts.md#defining-words).

---

## VLIST

`( -- )` -- **word**, dictionary

Prints the name of every word in the dictionary, newest first, each followed by a space, ending with the oldest word of the ROM. The names wrap at the screen's edge and scroll; there are several screens of them.

```forth
: Q 1 ;
VLIST                    \ expect-end: DUP DROP
```

**Notes.**

* Your own words come first. A word defined twice is listed twice, the newer first.
* The stack is not changed.

**See also** `FORGET`, `'`, [The dictionary](05_concepts.md#the-dictionary).

---

## WHILE

`( flag -- )` -- **compile-only word**, control

Used in `BEGIN ... WHILE ... REPEAT`. At run time it takes a flag: if it is not 0 the words up to `REPEAT` run; if it is 0 the loop ends and the program carries on after `REPEAT`. The test comes first, so the body may run no times.

```forth
: UPTO 0 BEGIN DUP 3 <
WHILE DUP . 1+ REPEAT DROP ;
UPTO                     \ expect: 0 1 2
: NONE 5 BEGIN DUP 3 <
WHILE 1+ REPEAT . ;
NONE                     \ expect: 5
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `WHILE ?` |

**See also** `BEGIN`, `REPEAT`, `UNTIL`.

---

## XOR

`( n1 n2 -- n3 )` -- **word**, arithmetic

Combines *n1* and *n2* bit by bit: a bit of the result is 1 where exactly one of them has a 1. `XOR` with the same
number twice gives the first number back.

```forth
10 12 XOR .              \ expect: 6
10 12 XOR 12 XOR .       \ expect: 10
```

**Errors.**

| Mistake | What happens |
|---|---|
| fewer than two numbers on the stack | `STACK?`, after `XOR` or after the next word that takes a number |

**See also** `AND`, `OR`, `INVERT`.

---

## [

`( -- )` -- **immediate word**, dictionary

Used inside a definition: switches from compiling to running. The words after `[` run at once, up to `]`, and their results can go into the definition with `LITERAL`.

```forth
: SIX [ 2 3 * ] LITERAL ;
SIX .                    \ expect: 6
```

**Notes.**

* Typed at the prompt, `[` has no effect: the console is already running what you type.

**See also** `]`, `LITERAL`, [Compiling and interpreting](05_concepts.md#compiling-and-interpreting).

---

## [']

`( "name" -- )` -- **compile-only word**, dictionary

Used inside a definition: reads the next word from the line and compiles its execution token as a number. When the definition runs it leaves that *xt* (the run-time effect is `( -- xt )`). It is `'` done once, while compiling, instead of every time the word runs.

```forth
: SQ DUP * ;
: RUN ['] SQ EXECUTE ;
5 RUN .                  \ expect: 25
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `['] ?`, nothing is compiled |
| a name that is not a word | `UNDEFINED WORD`; the definition is dropped |

**See also** `'`, `EXECUTE`, `CATCH`, `LITERAL`.

---

## [CHAR]

`( "name" -- )` -- **compile-only word**, strings

Used inside a definition: reads the next word from the line, as `CHAR` does, and compiles the code of its first character as a literal. When the definition runs it leaves that code. At run time the stack effect is `( -- c )`.

```forth
: STAR [CHAR] * ;
STAR .                   \ expect: 42
: LETTER [CHAR] hello ;
LETTER .                 \ expect: 104
```

**Errors.**

| Mistake | What happens |
|---|---|
| typed at the prompt | `[CHAR] ?`, nothing is compiled |
| nothing after `[CHAR]` on the line | `MISSING NAME`; the definition is dropped |

**See also** `CHAR`, `LITERAL`, [Characters and keys](05_concepts.md#characters-and-keys).

---

## \

`( -- )` -- **immediate word**, dictionary

Starts a comment that runs to the end of the line. It works at the prompt and inside a definition. Put a space after `\`.

```forth
1 2 + .  \ not read: 3 4 + .  \ expect: 3
: SHOW 5 \ five
. ;
SHOW                          \ expect: 5
```

**Notes.**

* A `\` at the very end of a line is an empty comment.
* The comment ends at the end of the line, so it also ends a `;` or `)` hidden in it: `: F 2 \ ;` leaves the definition open.

**See also** `(`.

---

## ]

`( -- )` -- **word**, dictionary

Switches to compiling: the words after it are compiled, not run, until `;` or `[`. Used inside a definition after `[` to go back to compiling.

```forth
: SIX [ 2 3 * ] LITERAL ;
: SEVEN [ SIX 1+ ] LITERAL ;
SEVEN .                  \ expect: 7
```

**Notes.**

* Typed at the prompt, `]` starts compiling into the dictionary at `HERE` with no definition open. What you type next is compiled, with no `OK`, until you type `[`. Do not do this.

**See also** `[`, `LITERAL`, `:`.

---
