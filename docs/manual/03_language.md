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

## ABS

`( n1 -- n2 )` -- **word**, arithmetic

Leaves the size of *n1* without its sign. `-32768` has no positive partner in a cell, so it stays -32768.

```forth
-5 ABS . 5 ABS .         \ expect: 5 5
-32768 ABS .             \ expect: -32768
```

**See also** `SGN`, `NEGATE`, `FABS`.

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

## DEG

`( F: f1 -- f2 )` -- **word**, float

Turns an angle in radians into degrees: it multiplies by 180/pi.

```forth
PI DEG F.                \ expect: 180.0000
PI 2.0 F/ DEG F.         \ expect: 90.0000
```

**See also** `RAD`, `PI`.

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

## FOVER

`( F: f1 f2 -- f1 f2 f1 )` -- **word**, float

Copies the second decimal from the top onto the top.

```forth
1.5 2.5 FOVER F. F. F.   \ expect: 1.5000 2.5000 1.5000
```

**See also** `FDUP`, `FSWAP`, `OVER`.

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
