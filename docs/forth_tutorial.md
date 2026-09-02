# Learning Forth on 2068-Forth

This document teaches Forth itself to someone who has never used it
before. It assumes you're comfortable with BASIC (line numbers,
`LET`/`PRINT`/`IF`, variables) but *not* with Forth — the two languages
think about programs so differently that BASIC experience mostly
doesn't transfer, and this document doesn't assume it does. It does
not assume you know assembly language or anything about how this
project is built; that's a separate audience covered by
[`PROJECT_PLAN.md`](PROJECT_PLAN.md) and the source code itself.

Sections are ordered the way you'd want to *learn* the language —
starting from the stack, through defining your own words, to control
flow, data, and finally the screen and keyboard — not the order any of
it happened to get built in. Every example here is something you can
actually type at a real, live 2068-Forth prompt right now, not a
preview of something still being built. A short appendix at the very
end lists the handful of things that genuinely aren't here yet, so
that gap doesn't need repeating throughout the main text.

A live prompt genuinely exists: turning the machine on shows a banner,
plays a short startup sound, and drops you at a real, keyboard-driven
prompt.

![2068-Forth boot screen, showing the banner and `5 3 + .` printing `8`](images/boot_and_arithmetic.png)

---

## 1. What Forth actually is

If you've written BASIC, every line is a *statement*: `LET X = 5+3`,
`PRINT X`, `IF X > 3 THEN GOTO 100`. The language has grammar — `LET`
needs an `=`, `IF` needs a `THEN`.

Forth has no grammar like that. A Forth program is just a sequence of
**words** separated by spaces. There is no statement syntax, because
there's only one rule for the whole language: *read the next word, then
either run it or compile it.* That's it. That one rule, repeated, is
the entire language.

### The stack, and why `5 3 +` means "5 + 3"

BASIC writes arithmetic *infix*: the operator sits between its operands
(`5 + 3`). Forth writes it **postfix**: the operands come first, the
operator comes last (`5 3 +`). This isn't an arbitrary stylistic choice
— it's what makes the "read a word, run it" rule work with no grammar
at all.

Here's the mechanism. Forth keeps a **stack**: a pile of numbers, like
a stack of plates, where you can only ever look at or remove the top
one. Every word does one of two things to it:

- A **number** gets *pushed* onto the top of the stack.
- An **operator** *pops* however many numbers it needs off the top,
  computes something, and pushes the result back.

Trace `5 3 +` one word at a time:

```
you type   stack after (top is rightmost)
--------   ----------------------------
5          [5]           -- push 5
3          [5, 3]        -- push 3
+          [8]           -- pop 3 and 5, push their sum
```

No parentheses, no operator precedence, no parsing at all — the stack
*is* the grammar. `+` doesn't need to know whether `5` and `3` came
from literals, variables, or the results of other words; it just takes
the top two numbers, whatever put them there.

This is also why Forth feels different to *read*: a BASIC expression
like `(5+3)*2` nests outward from the innermost operation, while its
Forth equivalent, `5 3 + 2 *`, reads left to right in the exact order
the machine will actually do the work — push 5, push 3, add them, push
2, multiply. Once this clicks, you're no longer "translating" BASIC
expressions into Forth in your head; you're thinking in the order
operations actually happen.

### Rearranging the stack

A handful of words exist just to rearrange the stack itself, since with
no variable names, getting a value into the right position *is* often
the whole problem:

| Word | Stack effect | What it does |
|---|---|---|
| `DUP` | `( n -- n n )` | Duplicate the top value |
| `SWAP` | `( a b -- b a )` | Swap the top two values |
| `DROP` | `( n -- )` | Discard the top value |
| `OVER` | `( a b -- a b a )` | Copy the second value to the top |

That `( n -- n n )` notation is standard Forth shorthand: what the
stack looks like right before the word runs, an arrow, then right
after — top of stack is always the rightmost item in each group. You'll
see it throughout Forth documentation (including this project's own
source code, and the reference table at the very end of this document)
and it's worth getting comfortable reading it now.

For example, doubling a number without a variable to hold it in:
`5 DUP +` — push 5, duplicate it (`[5, 5]`), add (`[10]`).

Or swapping two values to compute both differences of a subtraction:

```forth
10 3 OVER OVER -    \ [10, 3, 10, 3] then [10, 3, 7]
SWAP -              \ [3, 10] then [-7]
```

### Words and the dictionary

Everything in Forth — `+`, `DUP`, a word you define yourself — lives in
the **dictionary**: the complete list of every word the system
currently knows. When you type a word, Forth looks it up in the
dictionary by name. If it's not found, Forth tries to read it as a
plain number instead. If that fails too, you've made a typo or used an
undefined word, and Forth prints `?` on its own line and gives you a
fresh prompt rather than doing nothing visible or crashing (more on
this in [Typing and editing at the prompt](#13-typing-and-editing-at-the-prompt)).

The dictionary is searched **newest-first**. If you define a word with
the same name as an existing one, your new definition takes over for
anything you type *after* that point — the old one still exists deeper
in the dictionary (anything that already used it keeps working
unchanged), it's just no longer what a plain lookup finds by that name.
This is occasionally useful (redefining a word to fix a mistake without
restarting) and occasionally a source of confusion (forgetting you
shadowed something) — worth knowing about either way.

---

## 2. Defining your own words

This is the part of Forth that BASIC has no real equivalent for. In
BASIC, you write a program; the language itself doesn't grow while
you're using it. In Forth, defining a new word **extends the
language** — your word becomes exactly as usable as `+` or `DUP` from
that point on, no different in kind.

```forth
: DOUBLE  DUP + ;
```

Reading this left to right: `:` says "define a new word, named
`DOUBLE`, from everything up to the next `;`." Each word inside the
definition — here, `DUP` and `+` — gets remembered as part of what
`DOUBLE` does, rather than run immediately. `;` ends the definition.

Nothing has actually *run* yet at this point — you've just taught Forth
a new word. Now use it:

```forth
4 DOUBLE   \ leaves 8
```

`4` is pushed (`[4]`). `DOUBLE` is looked up, found, and run: running it
means running what's inside it, in order — `DUP` (`[4, 4]`), then `+`
(`[8]`). The result, `8`, is sitting on top of the stack.

This is worth sitting with for a moment: `DOUBLE` is not a macro or a
subroutine call in some special sense — once defined, it is a word,
full stop, exactly as first-class as anything Forth shipped with. A
real Forth program is mostly a sequence of small definitions like this,
each built out of the ones before it, until the last few definitions
read almost like plain English of what the program does.

Here's a slightly bigger example putting that habit into practice: a
word that squares a number, built out of a word that doubles one.

```forth
: DOUBLE     DUP + ;
: QUADRUPLE  DOUBLE DOUBLE ;

3 QUADRUPLE   \ leaves 12
```

- `QUADRUPLE` is defined *using* `DOUBLE` — this is completely ordinary;
  a word's definition can use any word that exists at the time it's
  defined, including one you just wrote yourself a moment ago.
- `3 QUADRUPLE` pushes `3` (`[3]`), then runs `QUADRUPLE`, which runs
  `DOUBLE` twice: `[3]` → `[6]` → `[12]`.

Notice that `QUADRUPLE` never mentions the stack, arithmetic, or how
`DOUBLE` works internally — it just names a sequence of existing words.
This is the normal shape of Forth programming: small words, each
trivially checkable by hand, combined into larger ones.

### Interpreting vs. compiling — why `;` is special

There's a flag Forth keeps internally, usually just called **STATE**:
it's either "interpreting" (run each word as you type it — everything
in section 1) or "compiling" (remember each word as part of a
definition instead — what happens between `:` and `;`).

`;` has to flip that flag back to "interpreting" the *moment* it's
read, or compiling would never stop. That means `;` can't follow the
normal rule of "get remembered as part of the definition" — it has to
act immediately, even while compiling is otherwise in effect. A word
that always runs immediately like this, even in the middle of a
definition, is called **IMMEDIATE**. You won't need to define your own
IMMEDIATE words for ordinary Forth programming, but it's worth knowing
the concept exists — it's also how `IF`, `ELSE`, and the loop words
later in this document work: they aren't ordinary words that get
compiled into a definition's body, they're IMMEDIATE words that shape
*how* the surrounding definition gets compiled.

---

## 3. Numbers

Whole numbers — `5`, `-12`, `0` — work exactly as you'd expect,
including negative numbers via a leading `-`.

2068-Forth also supports **decimal numbers**, written with a `.`:

```forth
3.5 2.5 F+ F.       \ prints 6.0000
2.0 3.0 F* F.       \ prints 6.0000
1.0 4.0 F/ F.       \ prints 0.2500
```

The moment a typed number contains a `.`, it's treated as a decimal
value instead of a whole one, and pushed onto its *own*, separate
stack — decimal arithmetic uses its own words, `F+ F- F* F/` (the `F`
prefix is the standard Forth convention for "floating-point"), not the
plain `+`/`-` from section 1. There's no plain integer `*` or `/` at
all in 2068-Forth yet — only these decimal versions. `F.` prints a
decimal result, always showing exactly 4 digits after the point
(`6.0` prints as `"6.0000"`, not `"6"`), rounded toward zero rather
than to the nearest digit, so very small differences near the 4th
digit can look slightly off from what a calculator would show for the
same expression.

Decimal literals work inside colon definitions too, compiled in
exactly like a whole-number literal would be:

```forth
: HALVE  2.0 F/ ;
5.0 HALVE F.        \ prints 2.5000
```

Keeping whole numbers and decimal numbers on two separate stacks,
using different words for each, is a deliberate, standard Forth design
— not a limitation specific to this implementation. See
[`numeric_model.md`](numeric_model.md) for the fuller reasoning.

### A few more useful numeric words

A handful of ordinary whole-number words round out the basics:

| Word | Stack effect | What it does |
|---|---|---|
| `ABS` | `( n -- \|n\| )` | Absolute value |
| `SGN` | `( n -- -1\|0\|1 )` | Sign of `n` |
| `MOD` | `( a b -- a-mod-b )` | Remainder of `a / b` |
| `SQRT` | `( n -- isqrt(n) )` | Integer square root, truncating |

```forth
-5 ABS .        \ prints 5
-17 5 MOD .     \ prints -2 -- the remainder takes the DIVIDEND's
                \ sign, not the divisor's (so -17 MOD 5 is -2, not 3)
16 SQRT .       \ prints 4
15 SQRT .       \ prints 3 -- truncated, not rounded: 15 isn't a
                \ perfect square, so this is the largest whole number
                \ whose square doesn't exceed it
```

`RND` and `RANDOMIZE` give you a pseudo-random whole number:

```forth
100 RND .          \ prints something in 0..99
12345 RANDOMIZE     \ reseed with a fixed number, for a reproducible
                     \ sequence -- useful for testing
100 RND .            \ always the same value, right after that
                      \ specific RANDOMIZE
0 RANDOMIZE          \ back to unpredictable -- reseeds from a
                      \ hardware timing source on the next RND
```

`RND`'s upper bound is exclusive — `100 RND` can produce `0` through
`99`, never `100` itself, matching the "n possible results" convention
plenty of other BASICs use for their own `RND(n)`.

---

## 4. Reading and writing memory directly

Forth gives you direct access to memory as two words:

| Word | Stack effect | What it does |
|---|---|---|
| `@` (pronounced "fetch") | `( addr -- n )` | Read the value stored at `addr` |
| `!` (pronounced "store") | `( n addr -- )` | Write `n` to `addr` |

Note the order for `!`: the *value* goes on the stack first, then the
*address* — read it as "store `n` at `addr`," matching the order the
words appear when you write `n addr !`. This trips up almost everyone
the first time; there's no trick to it beyond remembering the mnemonic.

This is a much lower-level tool than BASIC's variables — there's no
`DIM`, no named storage, just addresses. `VARIABLE` builds named
storage out of exactly this:

```forth
VARIABLE SCORE
42 SCORE !
SCORE @ .        \ prints 42
```

`VARIABLE SCORE` creates a new word, `SCORE`, that — every time you run
it — pushes the address of its own private two-byte storage cell
(starting out zero). You never see that address as a number you have
to remember; you just write `SCORE` and get it, then use `@`/`!`
exactly like with any other address. This is the same shape as BASIC's
`LET SCORE = 42` and `PRINT SCORE`, just spelled with explicit
`@`/`!` instead of an assignment operator.

`CONSTANT` is `VARIABLE`'s simpler sibling: it fixes a value
permanently at the moment you define it, with no cell and no way to
change it afterward.

```forth
100 CONSTANT MAXHEALTH
MAXHEALTH .      \ prints 100, every time, forever
```

### Arrays

`ARRAY` is `VARIABLE` scaled up: instead of one storage cell, it
reserves however many you ask for, all zeroed out to start:

```forth
5 ARRAY SCORES
```

`SCORES` now pushes the address of the FIRST cell, exactly like
`VARIABLE` does. To reach a different element, add its index (times
the size of a cell) to that base address before using `@`/`!`. `CELLS`
does that multiplication for you:

```forth
99 3 CELLS SCORES + !     \ store 99 in element 3
3 CELLS SCORES + @ .       \ prints 99
0 CELLS SCORES + @ .        \ prints 0 -- element 0 is untouched
```

There's no special "array-indexing" word — `index CELLS name +` is the
whole idiom, the same way real Forth systems handle it. Read it as one
phrase: "the address `CELLS` past `name`." Skipping `CELLS` and writing
plain `3 SCORES +` is a real mistake, not a shortcut: `SCORES` gives
you a plain BYTE address, and each cell here is 2 bytes wide, so
`3 SCORES +` doesn't land on element 3 at all — it lands one byte
INTO element 1. `CELLS` is exactly the `index * 2` conversion that
gets you to the right place.

### Strings

Forth doesn't have a string *type* the way BASIC does — instead, a
string is just two ordinary numbers on the stack: an **address** and a
**length**. `S"` (pronounced "S-quote") makes one:

```forth
S" HELLO WORLD" TYPE     \ prints HELLO WORLD
```

`S" text"` pushes the address and length of `text` — nothing prints on
its own. `TYPE` takes an address and a length and prints exactly that
many characters. Every other string word in this document works with
the same address/length pair, so once you have one from `S"`, anything
here can use it.

A literal from `S"` is read-only and disappears once you move on —
useful for a one-off piece of text, but not for something you want to
build up or change. `STRING` reserves a real, mutable slot for text,
the same way `VARIABLE` does for a single number:

```forth
20 STRING NAME
```

`NAME` now pushes the address of a buffer that can hold up to 20
characters, currently empty. Fill it with `PLACE`, which takes an
address/length pair (from `S"`, say) and a destination:

```forth
S" ADA" NAME PLACE
```

`NAME`'s own buffer now holds `"ADA"`. To get it back out as an
address/length pair for `TYPE` or anything else, use `COUNT`:

```forth
NAME COUNT TYPE      \ prints ADA
```

If all you want is how long the stored text is, `LEN` is a shortcut
that skips straight to that, without needing the full address/length
pair `COUNT` gives you:

```forth
NAME LEN .            \ prints 3
```

Finally, `VAL` goes the other direction — turning a string into a
number:

```forth
S" 1234" VAL .        \ prints 1234
S" -17" VAL .          \ prints -17
S" NOTANUMBER" VAL .    \ prints 0 -- not a valid number, no error,
                         \ just a safe default (the same convention
                         \ dividing by zero already uses in this project)
```

`STRING`'s own buffer has a fixed maximum size, decided when you create
it (`20 STRING NAME` above never holds more than 20 characters) — the
same limitation BASIC's own string variables have.

---

## 5. Comparisons and true/false

Before looking at `IF`, it helps to know how Forth represents "true"
and "false" — they're just numbers, like everything else on the stack.
**Zero means false; anything else means true.** `0=`, `=`, `<`, and
`>` all turn an ordinary comparison into one of these flags:

| Word | Stack effect | What it does |
|---|---|---|
| `0=` | `( n -- flag )` | `flag` is true if `n` is exactly `0` |
| `=`  | `( a b -- flag )` | `flag` is true if `a` and `b` are equal |
| `<`  | `( a b -- flag )` | `flag` is true if `a` is less than `b` |
| `>`  | `( a b -- flag )` | `flag` is true if `a` is greater than `b` |

```forth
5 3 > .    \ prints -1
5 3 = .    \ prints 0
```

A true flag prints as `-1`, not `1` — this is the standard Forth
convention (every bit set), not a bug; it just looks unfamiliar coming
from BASIC or most other languages, where "true" is usually `1`.

---

## 6. Making decisions: `IF` `ELSE` `THEN`

`IF`/`ELSE`/`THEN` is Forth's equivalent of BASIC's
`IF...THEN...ELSE`, with one difference worth calling out up front: the
condition comes from the stack, checked *before* you reach `IF`, not
written as part of the `IF` itself.

```forth
: SIGNTEST  IF 111 ELSE 222 THEN ;

5 SIGNTEST     \ pushes 5 (true-ish), runs SIGNTEST: leaves 111
0 SIGNTEST     \ pushes 0 (false), runs SIGNTEST: leaves 222
```

Reading `SIGNTEST`: when it runs, whatever's already on top of the
stack is treated as the condition. `IF` pops it and checks it the same
way section 5's comparisons produce it — zero means false, anything
else means true. If true, everything up to the matching `ELSE` (or
`THEN`, if there's no `ELSE`) runs; if false, the `ELSE` part runs
instead (or nothing, if there's no `ELSE`). `THEN` doesn't mean "then
do this" the way it does in BASIC — it just marks where the
`IF`/`ELSE` branching ends and normal execution continues. This naming
is a common early stumbling block for BASIC programmers specifically
because the word is so familiar-looking and means something different.

Combining this with section 5's own comparisons:

```forth
: BIGGER  > IF 111 ELSE 222 THEN ;

5 3 BIGGER   \ 5 3 > sees 5>3 -> true -> 111
3 5 BIGGER   \ 3 5 > sees 3>5 -> false -> 222
```

`IF`/`ELSE`/`THEN` can also print text directly, using `."`
("dot-quote"), which prints a literal piece of text — a different
feature from `.`'s printing of a *computed* number (covered fully in
[Printing](#8-printing)). It only works inside a colon definition, the
same restriction `IF`/`ELSE`/`THEN` themselves have. Exactly one space
is required right after `."`, and the text runs up to (but not
including) the next `"`:

```forth
: DESCRIBE  IF ." positive-ish" ELSE ." zero or negative" THEN ;

5 DESCRIBE     \ prints "positive-ish"
0 DESCRIBE     \ prints "zero or negative"
```

---

## 7. Repeating yourself

Forth has three loop shapes, covering the same ground as BASIC's
`FOR`/`NEXT` and `WHILE`/`WEND` between them.

### `BEGIN` `UNTIL` — the simplest loop

`BEGIN ... UNTIL` repeats the code between `BEGIN` and `UNTIL` until
the condition just before `UNTIL` becomes true. Since the check happens
at the *end*, the loop body always runs at least once — the same shape
as BASIC's `REPEAT...UNTIL`, if you've used a dialect with one, or
`DO...LOOP UNTIL` in some others.

```forth
: COUNTDOWN  BEGIN 1 - DUP 0= UNTIL ;

5 COUNTDOWN     \ leaves 0
```

Tracing `COUNTDOWN` with `5` on the stack: `1 -` makes it `4`; `DUP 0=`
duplicates it and asks "is the duplicate zero?" (no, so false); `UNTIL`
sees false and loops back to `BEGIN`. This repeats — `4→3→2→1→0` — and
the moment the value becomes `0`, `DUP 0=` finally answers true,
`UNTIL` stops looping, and the loop's last computed value (`0`) is left
on the stack.

This is a good habit to notice early: **Forth loops don't have a
built-in counter variable the way BASIC's `FOR I = 1 TO 5` does** — if
you need to know how many times you've looped, or count up rather than
down, you build that yourself out of ordinary stack values, the way
`COUNTDOWN`'s own value does double duty as both the thing being
counted down *and* the loop's exit test.

### `BEGIN` `WHILE` `REPEAT` — check first, not last

`BEGIN`/`UNTIL` always runs its body at least once, since the check
happens at the end. `BEGIN ... WHILE ... REPEAT` checks *before* each
pass instead, so the body can run zero times:

```forth
: COUNTDOWN2  BEGIN DUP 0 > WHILE 1 - REPEAT ;

5 COUNTDOWN2    \ leaves 0, same as COUNTDOWN above
0 COUNTDOWN2    \ leaves 0 too -- but the body never ran at all this
                \ time, since DUP 0 > was already false on the very
                \ first check
```

`WHILE` pops a flag (computed the same way `IF`'s condition is): false
exits the loop immediately, skipping everything up to `REPEAT`; true
falls through into the loop body, which runs and then jumps back to
`BEGIN` via `REPEAT`. This is BASIC's `WHILE`/`WEND` shape, not its
`REPEAT`/`UNTIL` one, despite Forth's own `UNTIL` keyword suggesting
the opposite pairing — worth double-checking against the examples above
rather than guessing from the keyword names alone.

### `DO` `LOOP` `I` — a real counter

Neither loop above has a built-in counter — `DO`/`LOOP` is Forth's
answer to BASIC's `FOR`/`NEXT`, counting for you instead of making you
track it on the stack yourself:

```forth
: FIVE  5 0 DO I . LOOP ;

FIVE     \ prints 0 1 2 3 4
```

`limit start DO` starts a loop counting up from `start`, stopping just
*before* it would reach `limit` (so `5 0 DO` runs for index values `0`
through `4` — five passes, not six). `I` pushes the current index;
`LOOP` adds one to it and jumps back to `DO` unless it just reached
`limit`, in which case the loop ends and execution continues normally
after `LOOP`.

One real trap worth knowing before it bites you: **`DO` doesn't check
whether `start` already equals `limit` before running the body the
first time.** `3 3 DO ... LOOP` runs the body once regardless, and then
`LOOP`'s own counter, having just gone from `3` to `4`, won't match
`limit` (`3`) again until it wraps all the way around through 65536
values — in practice, an accidental near-infinite loop. Never write a
`DO` where `start` and `limit` might already be equal.

### `LEAVE` — exiting a loop early

`LEAVE`, used inside a `DO` loop's body, ends the loop immediately —
skipping the rest of the current pass and any remaining ones — the
moment it runs. It's almost always written inside an `IF`, since
running unconditionally would make the rest of the loop pointless:

```forth
: FINDTHREE  10 0 DO I . I 3 = IF LEAVE THEN LOOP ;

FINDTHREE     \ prints 0 1 2 3, then stops -- the remaining six
              \ passes (I = 4 through 9) never run
```

`LEAVE` only exits the loop it's directly inside — if one `DO` loop is
nested inside another, `LEAVE` exits just the inner one, and the outer
loop keeps counting normally.

### `+LOOP` — stepping by something other than 1

`LOOP` always counts up by exactly 1. `+LOOP` takes a number off the
stack instead and steps by that many each pass — including a negative
number, to count downward:

```forth
: EVENS  10 0 DO I . 2 +LOOP ;

EVENS     \ prints 0 2 4 6 8
```

`+LOOP` ends the loop once stepping would carry the index at or past
`limit`, even if it jumps clean over it — `10 0 DO ... 3 +LOOP` stops
after index `9` (the next step would land on `12`, past `10`) without
ever landing on `10` exactly. This is why `+LOOP` can't just check for
an exact match the way plain `LOOP` does.

---

## 8. Printing

A word like `+` leaves its answer sitting on the stack — nothing shows
it to you unless you ask. `.` (pronounced "dot") does exactly that:

```forth
5 3 + .
```

prints `8` (followed by a trailing space, so several `.`s in a row read
as separate, space-separated numbers rather than running together) and
removes the value from the stack in the process — `.` both reads *and
consumes* the top of the stack, unlike, say, `DUP`. Negative numbers
print with a leading `-`, and zero prints as `0`. (`F.`, for printing
a *decimal* number, is covered in [Numbers](#3-numbers).)

`EMIT` is the lower-level word underneath `.`: it takes a single
number off the stack and prints it as one character, at whatever
character code that number is. `65 EMIT` prints `A` (65 is `A`'s
character code); `.` itself is built out of repeated `EMIT` calls, one
per digit. Both `.` and `EMIT` share one printing position — text wraps
to a new line automatically past column 32, and scrolls the screen once
it reaches the row just above where you're typing, so printed output
can never collide with the line you're currently entering. `AT-XY`
(covered in [Drawing and sound](#9-drawing-and-sound)) moves that
printing position directly, if you want output somewhere other than
wherever the last thing printed left off.

---

## 9. Drawing and sound

2068-Forth's graphics and sound words are deliberately thin: each one
is a direct, single-purpose action, the same way BASIC's `PLOT`,
`CIRCLE`, and `BEEP` are — there's no drawing "state" to set up first
beyond what each word's own arguments say.

| Word | Stack effect | What it does |
|---|---|---|
| `PLOT` | `( x y -- )` | Set the pixel at `(x, y)` |
| `LINE` | `( x1 y1 x2 y2 -- )` | Draw a line from `(x1, y1)` to `(x2, y2)` |
| `CIRCLE` | `( xc yc r -- )` | Draw a circle outline centered at `(xc, yc)` with radius `r` |
| `FILL` | `( x y -- )` | Flood-fill the enclosed area touching `(x, y)` with the current color |
| `BORDER` | `( color -- )` | Set the screen border to `color` (0-7, same numbering as BASIC's `BORDER`) |
| `INK` | `( color -- )` | Set the foreground color `PLOT`/`LINE`/`CIRCLE`/`FILL` draw with from now on (0-7) |
| `PAPER` | `( color -- )` | Set the background color the same way |
| `AT-XY` | `( col row -- )` | Move where the next `EMIT`/`.`/`."` prints to (column 0-31, row 0-22) |
| `BEEP` | `( pitch duration -- )` | Produce a tone |

```forth
5 BORDER
2 INK  6 PAPER
128 96 40 CIRCLE
128 96 FILL
```

![A red, filled circle on a cyan-bordered screen](images/drawing_example.png)

Reading these left to right follows the same postfix habit as
everything else in this document: for `LINE`, the coordinates go on the
stack in the order you'd say them out loud ("from 60,5 to 100,45"),
then the word that acts on all four at once. Nothing here is
conceptually new over section 1 — these are just words, exactly like
`+` or `DUP`, that happen to affect the screen or speaker instead of a
number.

`INK`/`PAPER` set state that persists until changed again — every
`PLOT`/`LINE`/`CIRCLE` after `2 INK 6 PAPER` draws red-on-yellow, not
just the next one, until some later call changes it again. Calling
`INK` never disturbs whatever `PAPER` was last set to, and vice versa —
each only touches its own half of the color.

One honest limit worth knowing now rather than discovering by
surprise: **`BEEP`'s two numbers aren't musical.** BASIC's `BEEP`
typically takes a duration in seconds and a pitch as a semitone offset;
2068-Forth's `BEEP` takes lower-level, hardware-timing numbers instead,
with no conversion between the two yet. Getting a specific, predictable
musical note or duration out of it isn't straightforward today, and
there's no access yet to the machine's AY-3-8912 sound chip beyond this
simple tone — see the appendix.

### Getting input: `KEY`

`KEY` is `EMIT`'s opposite: instead of printing a character, it waits
for you to press one key and leaves its code on the stack.

```forth
KEY .     \ waits for a keypress, then prints its character code
```

---

## 10. Variables, constants, and comparisons in combination

Sections 4 and 5 introduced `VARIABLE`/`CONSTANT` and the comparison
words separately; here's a slightly larger example putting several
pieces together — a simple counter that stops at a limit:

```forth
VARIABLE COUNT
0 COUNT !

: TICK  COUNT @ 1 + DUP COUNT ! ;
: DONE?  COUNT @ 5 > ;

TICK TICK TICK
DONE? .          \ prints 0 (false) -- only ticked 3 times
TICK TICK TICK
DONE? .          \ prints -1 (true) -- now ticked 6 times, past 5
```

Nothing here is a new word — it's the same `VARIABLE`, `@`, `!`, `+`,
`>`, and `.` from earlier sections, combined the way a real program
would.

---

## 11. Saving and loading your work

Programs don't need to be re-typed every time the machine starts —
`SAVE` and `LOAD` write your definitions to tape and read them back.

```forth
: DOUBLER DUP + ;
SAVE MYPROG
```

`SAVE` takes the name that follows it (not a word to look up — the same
way `:` treats the name right after it as something to define, not run)
and writes everything you've defined so far to tape under that name.
Later — even after switching the machine off and back on, which forgets
everything you defined — get it back:

```forth
LOAD MYPROG
4 DOUBLER
```

`LOAD MYPROG` restores your definitions exactly as they were, including
`DOUBLER`, which you can then use immediately, precisely as if you'd
just typed it in again. `LOAD` with no name at all loads whatever was
saved most recently, without needing to remember or retype its name.

There's no partial saving or loading of just one definition — `SAVE`
always writes everything you've defined up to that point, in one piece.
If you want to save your work at a meaningful checkpoint, that's a
matter of when you choose to run `SAVE`, not something 2068-Forth
tracks for you.

One honest gap: what's proven so far is 2068-Forth's own bookkeeping
(what gets saved, how it's found again, restoring your definitions so
they're immediately usable) — real tape behavior on real hardware or a
real emulator's actual cassette playback remains separately unverified.
Don't yet treat this as proof that a real recorded tape will load back
correctly on real hardware.

---

## 12. A wider screen

`64COL` switches to a 64-column *pixel graphics* display — twice the
normal horizontal resolution — `32COL` switches back, `PALETTE64`
picks a color pair, and `PLOT64` sets a point on it (`x` 0-511, `y`
0-191, wider than the normal screen's own coordinate range). All four
are real, working words:

```forth
64COL
3 PALETTE64
100 50 PLOT64
32COL
```

This is a **pixel graphics mode**, not a wider *text* display — typed
text and `EMIT`/`.`/`."` output are unaffected by it either way, still
always 32 columns wide. What isn't yet resolved: `64COL`'s own visual
behavior hasn't been fully characterized on real hardware — testing it
showed the screen rendering somewhat differently than expected, in
ways not yet explained. Treat this one as the least mature word group
in this document; it works at the level that's been checked, but
"what you'll actually see on a real screen" isn't yet a settled answer
the way it is for section 9's normal-screen `PLOT`/`LINE`/`CIRCLE`.

---

## 13. Typing and editing at the prompt

Everything so far in this document has described *what happens* when a
line of Forth runs — this section is about *typing the line itself*.
When you're entering something at the keyboard, before you press
Enter, a few keys behave specially rather than just adding a letter:

| Key | What it does |
|---|---|
| any ordinary character | Inserted at the cursor position |
| Enter | Finishes the line and runs it |
| Delete / backspace | Removes the character just before the cursor |
| Cursor left / right | Moves the cursor without changing anything |

The important habit to notice: **the cursor doesn't have to be at the
end of the line.** You can type `13`, move the cursor left one position
(now sitting between the `1` and the `3`), type `2`, and the line
becomes `123` — the `2` was inserted exactly where the cursor was, and
everything after it shifted over to make room:

![The input line reading "123" with the cursor positioned before the final digit](images/live_editing.png)

The same works in reverse for fixing a typo: move the cursor past a
wrong character, hit Delete to remove the one *before* the cursor,
then keep typing or press Enter. Nothing about this is specific to
Forth — it's the same editing model as typing into practically any
text field — but it's worth stating plainly since BASIC on this same
family of machines historically handled line editing somewhat
differently.

What happens if you press Enter on a word that doesn't exist? A typo —
`5 BRODER` instead of `5 BORDER`, say — prints a `?` on its own line
and drops you right back at a fresh prompt, rather than doing nothing
visible or crashing:

![A "?" printed after typing an unrecognized word](images/typo_error.png)

It's minimal (it doesn't say *which* word wasn't recognized, or why),
but a real mistake now looks different from nothing having happened at
all.

---

## Appendix A: word reference

A quick-lookup table of every word covered in this document, grouped
by topic, in the style of a standard Forth word-set reference — see
[forth-standard.org](https://forth-standard.org/standard/words) for
the same convention applied to the full ANS Forth standard.

**Stack manipulation**

| Word | Stack effect |
|---|---|
| `DUP` | `( n -- n n )` |
| `SWAP` | `( a b -- b a )` |
| `DROP` | `( n -- )` |
| `OVER` | `( a b -- a b a )` |

**Arithmetic and comparison**

| Word | Stack effect |
|---|---|
| `+` | `( a b -- a+b )` |
| `-` | `( a b -- a-b )` |
| `0=` | `( n -- flag )` |
| `=` | `( a b -- flag )` |
| `<` | `( a b -- flag )` |
| `>` | `( a b -- flag )` |
| `ABS` | `( n -- \|n\| )` |
| `SGN` | `( n -- -1\|0\|1 )` |
| `MOD` | `( a b -- a-mod-b )` |
| `SQRT` | `( n -- isqrt(n) )` |
| `RND` | `( x -- n )` |
| `RANDOMIZE` | `( n -- )` |

**Decimal (floating-point) arithmetic** — own stack, see section 3

| Word | Stack effect |
|---|---|
| `F+` | `( f1 f2 -- f1+f2 )` |
| `F-` | `( f1 f2 -- f1-f2 )` |
| `F*` | `( f1 f2 -- f1*f2 )` |
| `F/` | `( f1 f2 -- f1/f2 )` |
| `F.` | `( f -- )` |

**Memory**

| Word | Stack effect |
|---|---|
| `@` | `( addr -- n )` |
| `!` | `( n addr -- )` |
| `VARIABLE` | `( "name" -- )` |
| `CONSTANT` | `( n "name" -- )` |
| `ARRAY` | `( n "name" -- )` |
| `CELLS` | `( n -- n*2 )` |

**Strings**

| Word | Stack effect | Notes |
|---|---|---|
| `S" text"` | `( -- addr len )` | IMMEDIATE, a string literal |
| `TYPE` | `( addr len -- )` | print a string |
| `STRING` | `( n "name" -- )` | a mutable buffer, up to `n` characters |
| `PLACE` | `( addr len dest -- )` | store a string into a buffer |
| `COUNT` | `( caddr -- addr len )` | a buffer's contents as `(addr len)` |
| `LEN` | `( caddr -- n )` | a buffer's own length |
| `VAL` | `( addr len -- n )` | parse a string as an integer |

**Defining and control flow**

| Word | Stack effect | Notes |
|---|---|---|
| `:` ... `;` | — | define a new word |
| `IF` ... `ELSE` ... `THEN` | `( flag -- )` | IMMEDIATE, compile-only |
| `BEGIN` ... `UNTIL` | `( flag -- )` | IMMEDIATE, compile-only |
| `BEGIN` ... `WHILE` ... `REPEAT` | `( flag -- )` | IMMEDIATE, compile-only |
| `DO` ... `LOOP` | `( limit start -- )` | IMMEDIATE, compile-only |
| `DO` ... `+LOOP` | `( limit start -- )` / `( step -- )` | IMMEDIATE, compile-only |
| `LEAVE` | `( -- )` | IMMEDIATE, compile-only; exits the innermost `DO` loop |
| `I` | `( -- index )` | innermost `DO` loop's index |

**Printing and input**

| Word | Stack effect |
|---|---|
| `.` | `( n -- )` |
| `."` text`"` | `( -- )` — compile-only |
| `EMIT` | `( char -- )` |
| `KEY` | `( -- char )` |
| `AT-XY` | `( col row -- )` |

**Drawing and sound**

| Word | Stack effect |
|---|---|
| `PLOT` | `( x y -- )` |
| `LINE` | `( x1 y1 x2 y2 -- )` |
| `CIRCLE` | `( xc yc r -- )` |
| `FILL` | `( x y -- )` |
| `BORDER` | `( color -- )` |
| `INK` | `( color -- )` |
| `PAPER` | `( color -- )` |
| `BEEP` | `( pitch duration -- )` |
| `64COL` / `32COL` | `( -- )` |
| `PALETTE64` | `( n -- )` |
| `PLOT64` | `( x y -- )` |

**Storage**

| Word | Stack effect |
|---|---|
| `SAVE` | `( "name" -- )` |
| `LOAD` | `( "name" -- )` |

---

## Appendix B: what's not here yet

A few things a Forth veteran would expect, and a BASIC programmer
would ask about, aren't part of 2068-Forth yet:

- **Hi-res graphics mode** — beyond the normal-resolution words in
  section 9 and the experimental 64-column pixel mode in section 12.
- **Real AY-3-8912 sound** — `BEEP` (section 9) only toggles a simple
  tone; the sound chip's own richer tone/volume/noise controls aren't
  exposed yet.
- **Plain integer `*` and `/`** — only the decimal versions, `F*`/`F/`
  (section 3), exist so far.

See [`PROJECT_PLAN.md`](PROJECT_PLAN.md) for this project's own
build history and phased development order, if you're curious how
2068-Forth was actually put together rather than just how to use it.
