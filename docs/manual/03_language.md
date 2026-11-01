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
