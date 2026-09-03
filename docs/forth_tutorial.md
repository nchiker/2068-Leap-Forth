# Learning Forth on 2068-Forth

This document teaches Forth from scratch. It assumes you're comfortable
with BASIC — line numbers, `LET`/`PRINT`/`IF`, variables — but *not*
with Forth. That's a deliberate distinction: the two languages think
about programs so differently that BASIC experience mostly doesn't
transfer, and nothing here relies on it. No assembly language is
assumed either, and nothing about how this project is built; that's a
separate audience, served by [`PROJECT_PLAN.md`](PROJECT_PLAN.md) and
the source itself.

The sections run in the order you'd want to *learn* the language — the
stack first, then defining your own words, then control flow, data,
and finally the screen and keyboard — rather than the order any of it
happened to get built. Every example is something you can type at a
real, live 2068-Forth prompt today, not a preview of something still
under construction. A short appendix at the end lists the handful of
things that genuinely aren't here yet, so that gap doesn't have to be
repeated throughout the main text.

And the prompt really is live: turn the machine on and you get a
banner, a short startup sound, and a keyboard-driven prompt waiting for
you.

![2068-Forth boot screen, showing the banner and `5 3 + .` printing `8`](images/boot_and_arithmetic.png)

---

## 1. What Forth actually is

In BASIC, every line is a *statement*: `LET X = 5+3`, `PRINT X`,
`IF X > 3 THEN GOTO 100`. The language has grammar. `LET` needs its
`=`; `IF` needs its `THEN`.

Forth has no grammar at all. A Forth program is a sequence of **words**
separated by spaces, and the whole language runs on a single rule:
*read the next word, then either run it or compile it.* That rule,
repeated, is everything.

### The stack, and why `5 3 +` means "5 + 3"

BASIC writes arithmetic *infix* — the operator sits between its
operands, `5 + 3`. Forth writes it **postfix**: operands first,
operator last, `5 3 +`. That isn't a stylistic quirk. It's precisely
what lets "read a word, run it" work with no grammar to lean on.

The mechanism is a **stack**: a pile of numbers, like a stack of
plates, where you can only ever see or remove the top one. Every word
does one of two things to it.

- A **number** gets *pushed* onto the top.
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

No parentheses, no operator precedence, no parsing whatsoever — the
stack *is* the grammar. `+` never needs to know whether `5` and `3`
came from literals, from variables, or from other words; it takes the
top two numbers, whatever put them there.

This is also why Forth reads differently. A BASIC expression like
`(5+3)*2` nests outward from its innermost operation, while the Forth
equivalent, `5 3 + 2 *`, reads left to right in the exact order the
machine does the work: push 5, push 3, add, push 2, multiply. Once that
clicks, you stop translating BASIC expressions in your head and start
thinking in the order operations actually happen.

### Rearranging the stack

With no variable names anywhere, getting a value into the right
position *is* frequently the whole problem — so a handful of words
exist purely to shuffle the stack:

| Word | Stack effect | What it does |
|---|---|---|
| `DUP` | `( n -- n n )` | Duplicate the top value |
| `SWAP` | `( a b -- b a )` | Swap the top two values |
| `DROP` | `( n -- )` | Discard the top value |
| `OVER` | `( a b -- a b a )` | Copy the second value to the top |

That `( n -- n n )` notation is standard Forth shorthand: the stack
just before the word runs, an arrow, then the stack just after, with
the top of stack always rightmost in each group. It turns up
everywhere in Forth documentation — including this project's source
code and the reference table at the end of this document — so it's
worth getting comfortable reading now.

Doubling a number with no variable to hold it in, for instance, is
`5 DUP +`: push 5, duplicate it (`[5, 5]`), add (`[10]`).

Or, computing both differences of a subtraction by swapping the
operands:

```forth
10 3 OVER OVER -    \ [10, 3, 10, 3] then [10, 3, 7]
SWAP -              \ [3, 10] then [-7]
```

A few more round out the set, for when three or more values need
rearranging, or when something further down needs reaching without
disturbing what sits above it:

| Word | Stack effect | What it does |
|---|---|---|
| `ROT` | `( a b c -- b c a )` | Rotate the third value to the top |
| `2DUP` | `( a b -- a b a b )` | Duplicate the top *pair* |
| `2DROP` | `( a b -- )` | Discard the top *pair* |
| `?DUP` | `( n -- 0 \| n n )` | Duplicate, but only if `n` isn't zero |
| `PICK` | `( ... n -- ... x )` | Copy the `n`th value from the top (0 = same as `DUP`, 1 = same as `OVER`) |

`?DUP` exists for one specific, common pattern: testing a value with
`IF` while still wanting to *use* it afterward if it turned out
nonzero, without computing it twice.

```forth
SOME-WORD ?DUP IF . THEN     \ prints the result, but only if nonzero
```

`PICK` generalizes `DUP` and `OVER` to reach deeper without a chain of
`ROT`s. `2 PICK` reaches the third value from the top — the same place
`ROT` would bring up — but *copies* it rather than moving it:

```forth
10 20 30  2 PICK .    \ [10, 20, 30, 10] then prints 10, leaving [10, 20, 30]
```

`PICK` does no bounds checking on its own argument. Asking for a value
deeper than the stack actually holds reads whatever memory happens to
sit past it — not a crash, but not meaningful data either. That's the
same "trust the caller" posture most of this project's lower-level
words take; the honest-limits notes throughout this document flag the
others, `BEEP`'s among them (see
[Drawing and sound](#9-drawing-and-sound)).

### Words and the dictionary

Everything in Forth — `+`, `DUP`, a word you wrote yourself — lives in
the **dictionary**, the complete list of every word the system
currently knows. Type a word and Forth looks it up there by name. If
the lookup fails, Forth tries to read it as a plain number instead. If
*that* fails, you've hit a typo or an undefined word, and Forth prints
`?` on its own line and returns you to a fresh prompt rather than
doing nothing visible or crashing (see
[Typing and editing at the prompt](#13-typing-and-editing-at-the-prompt)
for more).

The dictionary is searched **newest-first**. Define a word with the
same name as an existing one and your version takes over for anything
you type *after* that point; the old one still exists deeper in the
dictionary, so anything that already used it keeps working unchanged
— it's simply no longer what a plain lookup finds by that name. That's
occasionally useful (redefining a word to fix a mistake without
restarting) and occasionally confusing (forgetting you shadowed
something), which makes it worth knowing either way.

---

## 2. Defining your own words

Here's the part BASIC has no real equivalent for. In BASIC you write a
program, and the language itself doesn't grow while you use it. In
Forth, defining a word **extends the language** — your word becomes as
usable as `+` or `DUP`, no different in kind.

```forth
: DOUBLE  DUP + ;
```

Left to right: `:` says "define a new word named `DOUBLE`, out of
everything up to the next `;`." Each word inside the definition — here
`DUP` and `+` — is remembered as part of what `DOUBLE` does rather
than run on the spot. `;` ends the definition.

**Every space above is required syntax, not tidy formatting.** Forth
splits everything on whitespace (see
[section 1](#1-what-forth-actually-is)), so a missing space silently
glues two words into one that doesn't exist, and the ROM has no way to
distinguish that from a genuine typo. In a real screen's fixed-width
font, one missing space is easy to miss by eye. `: DOUBLE DUP + ;`
needs a space in **every** one of these 4 places (marked with `·` here
just to make them visible — don't type the dots):

```
:·DOUBLE·DUP·+·;
```

Type `:DOUBLE` with no space after the `:` and the interpreter reads
`:DOUBLE` as a single word — not found, not defined, just an
unrecognized token. `DUP+` with no space before the `+` does the same
thing to `DUP+`. So if a `?` appears right after you define a word,
check this first, before suspecting the definition itself: retype it
slowly, one character at a time, confirming a space lands between
every pair of words before you press Enter.

Nothing has *run* yet, incidentally — you've only taught Forth a new
word. Now use it:

```forth
4 DOUBLE   \ leaves 8
```

`4` is pushed (`[4]`). `DOUBLE` is looked up, found, and run — and
running it means running what's inside it, in order: `DUP` (`[4, 4]`),
then `+` (`[8]`). The result, `8`, sits on top of the stack.

This is worth sitting with. `DOUBLE` isn't a macro, and it isn't a
subroutine call in some special sense. Once defined it is a word, full
stop, exactly as first-class as anything Forth shipped with. A real
Forth program is mostly a sequence of small definitions like this,
each built from the ones before it, until the last few read almost
like plain English describing what the program does.

A slightly bigger example puts that habit to work — a word that
quadruples a number, built out of a word that doubles one:

```forth
: DOUBLE     DUP + ;
: QUADRUPLE  DOUBLE DOUBLE ;

3 QUADRUPLE   \ leaves 12
```

- `QUADRUPLE` is defined *using* `DOUBLE`, which is completely
  ordinary: a definition may use any word that exists at the moment
  it's defined, including one you wrote seconds earlier.
- `3 QUADRUPLE` pushes `3` (`[3]`), then runs `QUADRUPLE`, which runs
  `DOUBLE` twice: `[3]` → `[6]` → `[12]`.

Notice that `QUADRUPLE` never mentions the stack, arithmetic, or how
`DOUBLE` works inside. It just names a sequence of existing words.
That's the normal shape of Forth programming: small words, each
trivially checkable by hand, combined into larger ones.

### Interpreting vs. compiling — why `;` is special

Forth keeps an internal flag, conventionally called **STATE**. It's
either "interpreting" — run each word as you type it, everything in
section 1 — or "compiling", meaning remember each word as part of a
definition instead, which is what happens between `:` and `;`.

`;` has to flip that flag back to "interpreting" the *instant* it's
read, or compiling would never stop. So `;` can't follow the usual
rule of getting remembered as part of the definition; it has to act
immediately, even while compiling is otherwise in effect. A word that
always runs immediately like this, mid-definition or not, is called
**IMMEDIATE**. Ordinary Forth programming won't have you defining your
own IMMEDIATE words, but the concept is worth knowing, because it's
also how `IF`, `ELSE`, and the loop words later in this document work.
Those aren't ordinary words compiled into a definition's body — they
are IMMEDIATE words that shape *how* the surrounding definition gets
compiled.

### Indirect calls: `'` and `EXECUTE`

Every word so far has been called by typing its name. `'` (pronounced
"tick") and `EXECUTE` let a program call a word it only learned the
*name* of at some earlier point — useful for passing a word around as
a value, the way another language might pass a function as an
argument.

```forth
: DOUBLE  DUP + ;
' DOUBLE EXECUTE     \ runs DOUBLE, ( -- xt ) then ( xt -- ) →
                     \ leaves DOUBLE's own result, just like just
                     \ typing DOUBLE would have
```

`' DOUBLE` doesn't run `DOUBLE`. It looks `DOUBLE` up in the
dictionary and pushes a single number identifying it — an **`xt`**,
short for "execution token" — without calling it. `EXECUTE` then takes
that `xt` off the stack and calls whatever it identifies. Splitting
"find" and "call" into two steps is what makes it possible to store a
word's identity in a variable, hand it to another word as an ordinary
argument, or decide *at runtime* which of several words to call. Just
typing a name can do none of that, since it only ever means "call it
right now."

`'` resolves its name the moment it runs, exactly as the outer prompt
resolves anything else you type, so asking for a name that doesn't
exist is an error — see
[Error handling: THROW and CATCH](#14-error-handling-throw-and-catch)
for what that actually does.

---

## 3. Numbers

Whole numbers — `5`, `-12`, `0` — behave exactly as you'd expect,
negatives included, via a leading `-`.

2068-Forth also supports **decimal numbers**, written with a `.`:

```forth
3.5 2.5 F+ F.       \ prints 6.0000
2.0 3.0 F* F.       \ prints 6.0000
1.0 4.0 F/ F.       \ prints 0.2500
```

The moment a typed number contains a `.`, it's treated as a decimal
value rather than a whole one and pushed onto its *own*, separate
stack. Decimal arithmetic then uses its own words — `F+ F- F* F/`,
where the `F` prefix is the standard Forth convention for
"floating-point" — not the plain `+`/`-` from section 1. There is no
plain integer `*` or `/` in 2068-Forth at all yet; only these decimal
versions exist. `F.` prints a decimal result, always with exactly 4
digits after the point (`6.0` prints as `"6.0000"`, not `"6"`), and
rounds toward zero rather than to the nearest digit — so very small
differences near the 4th digit can look slightly off from what a
calculator would show for the same expression.

Decimal literals work inside colon definitions too, compiled in
exactly the way a whole-number literal would be:

```forth
: HALVE  2.0 F/ ;
5.0 HALVE F.        \ prints 2.5000
```

Two separate stacks, with different words for each, is a deliberate
and standard Forth design — not a limitation particular to this
implementation. [`numeric_model.md`](numeric_model.md) has the fuller
reasoning.

`FSQRT` is the decimal counterpart to whole-number `SQRT` (below):

```forth
9.0 FSQRT F.        \ prints 3.0000
2.0 FSQRT F.        \ prints 1.4141 -- an approximation, like any
                    \ computer's square root of an irrational number
```

Trigonometry follows the same pattern. `PI` pushes a decimal
approximation of π, and `SIN`/`COS` take an angle in radians:

```forth
PI F.               \ prints 3.1416
1.0 SIN F.          \ prints 0.8408
2.0 COS F.          \ prints -0.4156
```

`SIN` and `COS` come from a lookup table with linear interpolation
between entries rather than a series expansion, giving about 3-4
decimal digits of accuracy — which is all `F.` shows anyway. There's
no `TAN` yet; it wouldn't be hard to build from `SIN`/`COS`, it just
hasn't come up. Large angles aren't reliable either: roughly beyond
±1570 radians, a couple hundred full turns, the internal
range-reduction step gives up silently rather than erroring. Ordinary
trig usage stays comfortably inside that range.

`RAD` and `DEG` convert between the two common angle units, for when
degrees are the more natural way to say something — a compass heading,
say:

```forth
90.0 RAD F.       \ prints 1.5707 -- 90 degrees in radians
PI 2.0 F/ DEG F.  \ prints 89.9960 -- half of PI back to degrees
                  \ (not exactly 90.0 -- the same small
                  \ approximation error every decimal calculation
                  \ here carries)
```

Moving a value between the whole-number stack and the decimal stack
takes its own words, since the two really are separate. Typing a
number with or without a `.` decides *where it starts*; `S>F` and
`F>S` move an already-computed value across afterward:

| Word | Stack effect | What it does |
|---|---|---|
| `S>F` | `( n -- )` `( -- f )` | Whole number to decimal (exact) |
| `F>S` | `( f -- )` `( -- n )` | Decimal to whole number (see below) |
| `FROUND` | `( f -- )` `( -- f' )` | Round to the nearest whole decimal value |

```forth
42 S>F F.          \ prints 42.0000
3.7 F>S .          \ prints 3 -- truncated toward negative infinity,
                   \ not rounded and not toward zero: plain F>S on
                   \ -0.5 gives -1, not 0
-0.5 FROUND F>S .  \ prints 0 -- FROUND rounds -0.5 to the nearest
                   \ whole value FIRST (half rounds up, so -0.5
                   \ becomes 0, not -1), and only THEN does F>S
                   \ convert it — the order matters
```

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
12345 RANDOMIZE    \ reseed with a fixed number, for a reproducible
                   \ sequence -- useful for testing
100 RND .          \ always the same value, right after that
                   \ specific RANDOMIZE
0 RANDOMIZE        \ back to unpredictable -- reseeds from a
                   \ hardware timing source on the next RND
```

`RND`'s upper bound is exclusive: `100 RND` produces `0` through `99`
and never `100` itself, matching the "n possible results" convention
plenty of other BASICs use for their own `RND(n)`.

### Bitwise and logical operators

These act on all 16 bits of a value at once — real bit manipulation,
not the boolean `=`/`<`/`>` results covered in
[Comparisons and true/false](#5-comparisons-and-truefalse):

| Word | Stack effect | What it does |
|---|---|---|
| `AND` | `( a b -- a AND b )` | Bitwise AND |
| `OR` | `( a b -- a OR b )` | Bitwise OR |
| `XOR` | `( a b -- a XOR b )` | Bitwise exclusive-OR |
| `INVERT` | `( a -- NOT a )` | Bitwise complement — every bit flipped |

```forth
15 240 OR .     \ prints 255 -- 15 is 00001111, 240 is 11110000;
                \ OR-ed together, every one of those 8 bits is set
10 12 AND .     \ prints 8 -- 10 is 1010, 12 is 1100; AND keeps only
                \ the bits both share (1000)
0 INVERT .      \ prints -1 -- flipping every bit of 0 gives all
                \ ones, which prints as -1 (this project's own
                \ integers are signed, two's-complement, like most
                \ Forths)
```

`INVERT` is deliberately not called `NOT`. This project's `0=` (next
section) already performs *logical* negation of a true/false flag, and
a second, differently-behaved word spelled `NOT` sitting right beside
it would be a trap rather than a convenience. `INVERT` flips every
bit; `0=` cares only whether its input was exactly zero.

---

## 4. Reading and writing memory directly

Forth hands you direct access to memory through two words:

| Word | Stack effect | What it does |
|---|---|---|
| `@` (pronounced "fetch") | `( addr -- n )` | Read the value stored at `addr` |
| `!` (pronounced "store") | `( n addr -- )` | Write `n` to `addr` |

Watch the order for `!`: the *value* goes on the stack first, then the
*address*. Read it as "store `n` at `addr`," which matches the order
the words appear when you write `n addr !`. This trips up nearly
everyone the first time, and there's no trick to it beyond the
mnemonic.

That's a much lower-level tool than BASIC's variables — no `DIM`, no
named storage, just addresses. `VARIABLE` builds named storage out of
exactly this:

```forth
VARIABLE SCORE
42 SCORE !
SCORE @ .        \ prints 42
```

`VARIABLE SCORE` creates a new word, `SCORE`, that pushes the address
of its own private two-byte storage cell every time you run it — the
cell starting out zero. You never have to see or remember that address
as a number; you write `SCORE`, get it, and then use `@`/`!` on it
exactly as with any other address. Same shape as BASIC's
`LET SCORE = 42` and `PRINT SCORE`, just spelled with explicit `@`/`!`
instead of an assignment operator.

`CONSTANT` is `VARIABLE`'s simpler sibling. It fixes a value
permanently at the moment you define it: no cell, no way to change it
afterward.

```forth
100 CONSTANT MAXHEALTH
MAXHEALTH .      \ prints 100, every time, forever
```

`@` and `!` always work on a full two-byte cell. `C@` and `C!` do the
same job one *byte* at a time — the natural pair to reach for with
text (a string's own bytes) or anything else that's naturally
byte-sized rather than a whole number:

| Word | Stack effect | What it does |
|---|---|---|
| `C@` | `( addr -- byte )` | Read one byte at `addr` |
| `C!` | `( byte addr -- )` | Write one byte to `addr` |

```forth
20 STRING NAME
S" ADA" NAME PLACE
NAME 1 + C@ .        \ prints 65 -- 'A', the first character of "ADA"
```

Reach whichever character you want by adding your own offset to a
buffer's address before `C@`. There's no `CELLS`-style helper for
single bytes, because for bytes the offset and the count are already
the same number.

`FREE ( -- n )` reports how much room is left for defining new words,
which is handy before starting a big program — the same spirit as
BASIC's own `FREE`:

```forth
FREE .      \ prints how many bytes are left for new definitions
```

It measures dictionary space specifically, meaning room for new word
definitions, not total system memory. The stacks, the screen, and the
system's own working storage sit in separate fixed-size regions that
never compete with what `FREE` reports.

### Arrays

`ARRAY` is `VARIABLE` scaled up: instead of a single storage cell, it
reserves however many you ask for, all zeroed to start.

```forth
5 ARRAY SCORES
```

`SCORES` now pushes the address of the FIRST cell, exactly as
`VARIABLE` does. To reach any other element, add its index — times the
size of a cell — to that base address before using `@`/`!`. `CELLS`
does that multiplication for you:

```forth
99 3 CELLS SCORES + !     \ store 99 in element 3
3 CELLS SCORES + @ .      \ prints 99
0 CELLS SCORES + @ .      \ prints 0 -- element 0 is untouched
```

There's no special array-indexing word; `index CELLS name +` is the
whole idiom, exactly as real Forth systems handle it. Read it as one
phrase — "the address `CELLS` past `name`." Dropping `CELLS` and
writing plain `3 SCORES +` is a real mistake rather than a shortcut:
`SCORES` gives you a plain BYTE address and each cell here is 2 bytes
wide, so `3 SCORES +` doesn't land on element 3 at all — it lands one
byte INTO element 1. `CELLS` is exactly the `index * 2` conversion
that gets you to the right place.

### Strings

Forth has no string *type* the way BASIC does. A string is two
ordinary numbers on the stack: an **address** and a **length**. `S"`
(pronounced "S-quote") makes one.

```forth
S" HELLO WORLD" TYPE     \ prints HELLO WORLD
```

`S" text"` pushes the address and length of `text`, and prints nothing
by itself. `TYPE` takes an address and a length and prints exactly
that many characters. Every other string word in this document works
on the same address/length pair, so once `S"` has handed you one,
anything here can consume it.

A literal from `S"` is read-only and disappears once you move on —
fine for a one-off piece of text, useless for something you want to
build up or change. `STRING` reserves a real, mutable slot for text,
just as `VARIABLE` does for a single number:

```forth
20 STRING NAME
```

`NAME` now pushes the address of a buffer holding up to 20 characters,
currently empty. Fill it with `PLACE`, which takes an address/length
pair — from `S"`, say — and a destination:

```forth
S" ADA" NAME PLACE
```

`NAME`'s buffer now holds `"ADA"`. To get it back out as an
address/length pair, for `TYPE` or anything else, use `COUNT`:

```forth
NAME COUNT TYPE      \ prints ADA
```

If all you want is the length of the stored text, `LEN` skips straight
to it without producing the full pair `COUNT` gives you:

```forth
NAME LEN .            \ prints 3
```

`VAL` goes the other direction, turning a string into a number:

```forth
S" 1234" VAL .        \ prints 1234
S" -17" VAL .         \ prints -17
S" NOTANUMBER" VAL .  \ prints 0 -- not a valid number, no error,
                      \ just a safe default (the same convention
                      \ dividing by zero already uses in this project)
```

A `STRING` buffer's maximum size is fixed when you create it —
`20 STRING NAME` above never holds more than 20 characters — the same
limitation BASIC's own string variables carry.

### More string words

A further set covers the everyday BASIC string operations
(`CHR$`/`STR$`/`UPPER$`/`LOWER$`/`LEFT$`/`RIGHT$`/`INSTR` and friends)
under Forth-standard names, all still working on the same
address/length pairs:

| Word | Stack effect | What it does |
|---|---|---|
| `CHR` | `( code -- addr len )` | A one-character string from a character code |
| `STR` | `( n -- addr len )` | A number, as a string |
| `UPPER` | `( addr len -- addr len )` | Uppercase, in place |
| `LOWER` | `( addr len -- addr len )` | Lowercase, in place |
| `LEFT` | `( addr len n -- addr len' )` | The first `n` characters |
| `RIGHT` | `( addr len n -- addr' len' )` | The last `n` characters |
| `SEARCH` | `( addr1 len1 addr2 len2 -- addr3 len3 flag )` | Find string 2 inside string 1 |
| `CODE` | `( addr len -- code )` | The character code of a string's first character |

```forth
65 CHR TYPE                  \ prints A
42 STR TYPE                  \ prints 42
S" ADA" UPPER TYPE           \ prints ADA (already uppercase, unchanged)
S" hello" UPPER TYPE         \ prints HELLO
S" HELLO WORLD" 5 LEFT TYPE  \ prints HELLO
S" HELLO WORLD" 5 RIGHT TYPE \ prints WORLD
```

`UPPER` and `LOWER` change text **in place**. Unlike every other word
here, which only reads its `(addr len)` argument, these two write back
into it — so the string has to be real, writable memory, from
`STRING`, not a literal from `S"`. A literal's characters live in the
program's permanent, read-only storage, and a write there silently
does nothing: not a crash, just no visible effect, since this hardware
has no way to signal "that write didn't take."

`SEARCH` looks for the second string inside the first and reports
where it found it:

```forth
S" HELLO WORLD" S" WORLD" SEARCH .   \ prints -1 (true) -- found
                                     \ DROP TYPE would show the
                                     \ match itself: "WORLD"
```

`flag` is true if the second string turned up anywhere inside the
first, and `addr3 len3` then point at the match itself rather than the
whole original string. An empty search string never matches, and a
search string longer than the text being searched can't match either
— both handled without special-case code in your own program.

---

## 5. Comparisons and true/false

Before `IF`, it helps to know how Forth represents "true" and "false".
They're just numbers, like everything else on the stack: **zero means
false; anything else means true.** `0=`, `=`, `<`, and `>` each turn
an ordinary comparison into one of these flags.

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

A true flag prints as `-1`, not `1`. That's the standard Forth
convention — every bit set — rather than a bug. It simply looks
unfamiliar coming from BASIC or most other languages, where true is
usually `1`.

---

## 6. Making decisions: `IF` `ELSE` `THEN`

`IF`/`ELSE`/`THEN` is Forth's answer to BASIC's `IF...THEN...ELSE`,
with one difference worth stating up front: the condition comes from
the stack, computed *before* you reach `IF`, rather than being written
as part of the `IF` itself.

```forth
: SIGNTEST  IF 111 ELSE 222 THEN ;

5 SIGNTEST     \ pushes 5 (true-ish), runs SIGNTEST: leaves 111
0 SIGNTEST     \ pushes 0 (false), runs SIGNTEST: leaves 222
```

Reading `SIGNTEST`: when it runs, whatever's already on top of the
stack is the condition. `IF` pops it and checks it exactly the way
section 5's comparisons produce it — zero false, anything else true.
If true, everything up to the matching `ELSE` runs (or up to `THEN`,
if there's no `ELSE`); if false, the `ELSE` part runs instead, or
nothing at all when there's no `ELSE`. `THEN` does *not* mean "then do
this" the way BASIC's does; it only marks where the `IF`/`ELSE`
branching ends and normal execution resumes. That naming is a common
early stumbling block for BASIC programmers precisely because the word
looks so familiar and means something else.

Combined with section 5's comparisons:

```forth
: BIGGER  > IF 111 ELSE 222 THEN ;

5 3 BIGGER   \ 5 3 > sees 5>3 -> true -> 111
3 5 BIGGER   \ 3 5 > sees 3>5 -> false -> 222
```

A branch can also print text directly, using `."` ("dot-quote"), which
prints a literal piece of text — a different feature from `.`'s
printing of a *computed* number, covered fully in
[Printing](#8-printing). `."` only works inside a colon definition,
the same restriction `IF`/`ELSE`/`THEN` themselves carry. Exactly one
space is required right after `."`, and the text runs up to (but not
including) the next `"`:

```forth
: DESCRIBE  IF ." positive-ish" ELSE ." zero or negative" THEN ;

5 DESCRIBE     \ prints "positive-ish"
0 DESCRIBE     \ prints "zero or negative"
```

---

## 7. Repeating yourself

Forth has three loop shapes, covering between them the ground BASIC's
`FOR`/`NEXT` and `WHILE`/`WEND` cover.

### `BEGIN` `UNTIL` — the simplest loop

`BEGIN ... UNTIL` repeats the code between the two until the condition
just before `UNTIL` becomes true. Because the check happens at the
*end*, the body always runs at least once — the same shape as BASIC's
`REPEAT...UNTIL`, if you've used a dialect with one, or `DO...LOOP
UNTIL` in some others.

```forth
: COUNTDOWN  BEGIN 1 - DUP 0= UNTIL ;

5 COUNTDOWN     \ leaves 0
```

Trace `COUNTDOWN` with `5` on the stack. `1 -` makes it `4`; `DUP 0=`
duplicates it and asks "is the duplicate zero?" — no, so false; and
`UNTIL`, seeing false, loops back to `BEGIN`. That repeats,
`4→3→2→1→0`, and the moment the value hits `0`, `DUP 0=` finally
answers true, `UNTIL` stops looping, and the loop's last computed
value (`0`) is left on the stack.

One habit worth noticing early: **Forth loops have no built-in counter
variable the way BASIC's `FOR I = 1 TO 5` does.** If you need to know
how many times you've looped, or to count up rather than down, you
build that yourself out of ordinary stack values — the way
`COUNTDOWN`'s own value pulls double duty as both the thing being
counted down *and* the loop's exit test.

### `BEGIN` `WHILE` `REPEAT` — check first, not last

Since `BEGIN`/`UNTIL` checks at the end, its body always runs at least
once. `BEGIN ... WHILE ... REPEAT` checks *before* each pass instead,
so the body can run zero times:

```forth
: COUNTDOWN2  BEGIN DUP 0 > WHILE 1 - REPEAT ;

5 COUNTDOWN2    \ leaves 0, same as COUNTDOWN above
0 COUNTDOWN2    \ leaves 0 too -- but the body never ran at all this
                \ time, since DUP 0 > was already false on the very
                \ first check
```

`WHILE` pops a flag, computed the same way `IF`'s condition is. False
exits the loop immediately, skipping everything up to `REPEAT`; true
falls through into the body, which runs and then jumps back to `BEGIN`
via `REPEAT`. This is BASIC's `WHILE`/`WEND` shape, not its
`REPEAT`/`UNTIL` one — despite Forth's own `UNTIL` keyword suggesting
the opposite pairing, which is why it's worth checking against the
examples above rather than guessing from the keyword names.

### `DO` `LOOP` `I` — a real counter

Neither loop above counts for you. `DO`/`LOOP` is Forth's answer to
BASIC's `FOR`/`NEXT`, keeping the count itself instead of making you
track it on the stack:

```forth
: FIVE  5 0 DO I . LOOP ;

FIVE     \ prints 0 1 2 3 4
```

`limit start DO` starts a loop counting up from `start` and stopping
just *before* it would reach `limit` — so `5 0 DO` runs for index
values `0` through `4`, five passes, not six. `I` pushes the current
index. `LOOP` adds one to it and jumps back to `DO` unless it has just
reached `limit`, in which case the loop ends and execution continues
after `LOOP`.

One real trap, worth knowing before it bites: **`DO` doesn't check
whether `start` already equals `limit` before running the body the
first time.** `3 3 DO ... LOOP` runs the body once regardless, and
`LOOP`'s counter, having just gone from `3` to `4`, won't match
`limit` (`3`) again until it wraps all the way around through 65536
values — an accidental near-infinite loop, in practice. Never write a
`DO` where `start` and `limit` might already be equal.

### `LEAVE` — exiting a loop early

`LEAVE`, used inside a `DO` loop's body, ends the loop the moment it
runs, skipping the rest of the current pass and every remaining one.
It's almost always written inside an `IF`, since running it
unconditionally would make the rest of the loop pointless:

```forth
: FINDTHREE  10 0 DO I . I 3 = IF LEAVE THEN LOOP ;

FINDTHREE     \ prints 0 1 2 3, then stops -- the remaining six
              \ passes (I = 4 through 9) never run
```

`LEAVE` exits only the loop it's directly inside. With one `DO` loop
nested in another, `LEAVE` exits the inner one and the outer loop
keeps counting normally.

### `+LOOP` — stepping by something other than 1

`LOOP` always counts up by exactly 1. `+LOOP` takes a number off the
stack and steps by that much each pass — including a negative number,
to count downward:

```forth
: EVENS  10 0 DO I . 2 +LOOP ;

EVENS     \ prints 0 2 4 6 8
```

`+LOOP` ends the loop once a step would carry the index at or past
`limit`, even if it jumps clean over it: `10 0 DO ... 3 +LOOP` stops
after index `9`, since the next step would land on `12`, past `10`,
without ever landing on `10` exactly. That's why `+LOOP` can't simply
check for an exact match the way plain `LOOP` does.

---

## 8. Printing

A word like `+` leaves its answer sitting on the stack, and nothing
shows it to you unless you ask. `.` (pronounced "dot") is how you ask:

```forth
5 3 + .
```

prints `8`, followed by a trailing space, so that several `.`s in a
row read as separate space-separated numbers instead of running
together. It also removes the value from the stack on the way past —
`.` both reads *and consumes* the top of the stack, unlike, say,
`DUP`. Negative numbers print with a leading `-`, and zero prints as
`0`. (`F.`, for printing a *decimal* number, is covered in
[Numbers](#3-numbers).)

`EMIT` is the lower-level word underneath `.`. It takes a single
number off the stack and prints it as one character, at whatever
character code that number is: `65 EMIT` prints `A`, since 65 is
`A`'s character code. `.` itself is built out of repeated `EMIT`
calls, one per digit. Both share a single printing position, which
wraps to a new line automatically past column 32 and scrolls the
screen once it reaches the row just above where you're typing, so
printed output can never collide with the line you're currently
entering. `AT-XY` (see [Drawing and sound](#9-drawing-and-sound))
moves that printing position directly, for output somewhere other than
wherever the last thing printed left off.

Three small words exist purely for convenience, each a thin wrapper
around `EMIT` for a character you'd otherwise have to look the code up
for:

| Word | Stack effect | What it does |
|---|---|---|
| `CR` | `( -- )` | Move to the start of the next line — `13 EMIT` |
| `SPACE` | `( -- )` | Print one space — `32 EMIT` |
| `SPACES` | `( n -- )` | Print `n` spaces |

```forth
." NAME:" SPACE ." FORTH" CR
." VERSION:" SPACE ." 1" CR
```

prints `NAME: FORTH`, then `VERSION: 1` on the line below — each lined
up by hand with `SPACE`, no column-alignment word required.

---

## 9. Drawing and sound

2068-Forth's graphics and sound words are deliberately thin. Each is a
direct, single-purpose action, in the same spirit as BASIC's `PLOT`,
`CIRCLE`, and `BEEP`: there's no drawing "state" to set up first
beyond what each word's own arguments say.

| Word | Stack effect | What it does |
|---|---|---|
| `PLOT` | `( x y -- )` | Set the pixel at `(x, y)` |
| `LINE` | `( x1 y1 x2 y2 -- )` | Draw a line from `(x1, y1)` to `(x2, y2)` |
| `CIRCLE` | `( xc yc r -- )` | Draw a circle outline centered at `(xc, yc)` with radius `r` |
| `FILL` | `( x y -- )` | Flood-fill the enclosed area touching `(x, y)` with the current color |
| `CLS` | `( -- )` | Clear the whole screen |
| `BORDER` | `( color -- )` | Set the screen border to `color` (0-7, same numbering as BASIC's `BORDER`) |
| `INK` | `( color -- )` | Set the foreground color `PLOT`/`LINE`/`CIRCLE`/`FILL` draw with from now on (0-7) |
| `PAPER` | `( color -- )` | Set the background color the same way |
| `AT-XY` | `( col row -- )` | Move where the next `EMIT`/`.`/`."` prints to (column 0-31, row 0-22) |
| `BEEP` | `( n-semitones fduration -- )` | Produce a tone |
| `SOUND` | `( register data -- )` | Write directly to an AY-3-8912 sound-chip register |

```forth
5 BORDER
2 INK  6 PAPER
128 96 40 CIRCLE
128 96 FILL
```

![A red, filled circle on a cyan-bordered screen](images/drawing_example.png)

Reading these left to right follows the same postfix habit as
everything else here: for `LINE`, the coordinates go on the stack in
the order you'd say them out loud ("from 60,5 to 100,45"), then the
word that acts on all four at once. Nothing is conceptually new over
section 1 — these are words, exactly like `+` or `DUP`, that happen to
affect the screen or the speaker instead of a number.

`INK` and `PAPER` set state that persists until changed. Every
`PLOT`/`LINE`/`CIRCLE` after `2 INK 6 PAPER` draws red-on-yellow, not
just the next one, until some later call changes it again. Calling
`INK` never disturbs whatever `PAPER` was last set to, and vice versa;
each touches only its own half of the color. `CLS` honors the current
`PAPER` as well — clearing the screen fills it with whatever
background color is set, not always black.

`BEEP` takes real musical units, exactly as BASIC's own `BEEP` does:
an INTEGER number of semitones (0 = middle C, positive up, negative
down — the data stack's job, since a semitone count is a whole number)
and a decimal DURATION in seconds (the float stack's job, since
durations are naturally fractional):

```forth
0 1.0 BEEP        \ middle C for one second
12 0.5 BEEP       \ one octave above middle C, half a second
-12 0.5 BEEP      \ one octave below middle C, half a second
```

Two honest limits are worth knowing. Only WHOLE semitones are
supported — BASIC's `BEEP` accepts a fractional pitch; this one
doesn't — and there's a real, physical ceiling around 12.9 kHz, above
which a note clamps to the ceiling rather than actually going higher,
since that's as fast as this hardware loop can toggle the speaker.
Ordinary musical use, a few octaves around middle C, is nowhere near
either limit.

For anything `BEEP` can't do — a sustained tone, more than one note at
once, precise volume control — `SOUND ( register data -- )` gives
direct, register-level access to the machine's AY-3-8912 sound chip,
the same authentic command real BASIC has. It writes one raw byte into
one of the chip's registers (1-16; out-of-range values are silently
ignored) and does nothing else. Getting an actual tone out of it takes
THREE coordinated calls rather than one, because the chip's registers
each control a different piece: a tone's pitch, which channels are
switched on, and how loud.

```forth
2 251 SOUND        \ channel B's tone pitch (fine byte)
3   0 SOUND        \ channel B's tone pitch (coarse byte)
7 253 SOUND        \ mixer: turn on ONLY channel B's tone
9  15 SOUND        \ channel B's volume -- THIS is what you'll hear
9   0 SOUND        \ silence it again
```

Nothing is audible until that fourth line; the first three only set up
state the chip remembers, the way `INK`/`PAPER` persist until changed.
`SOUND` has no idea what a "note" is, unlike `BEEP` — the 251 above is
a raw chip register value, worked out from the machine's own
sound-chip clock speed (1,764,000 Hz) and the formula
`period = clock / (16 * frequency)` for a note near 439 Hz. A
different pitch means recomputing that period yourself. There's no
semitone convenience here on purpose: `SOUND` trades convenience for
direct access to everything the chip can do — three tones, volume
envelopes, noise — that `BEEP` was never meant to reach.

### Getting input: `KEY`, `KEY?`, and `STICK`

`KEY` is `EMIT`'s opposite. Instead of printing a character, it waits
for you to press one key and leaves its code on the stack.

```forth
KEY .     \ waits for a keypress, then prints its character code
```

The operative word is **waits**: your program stops until you press
something. For a game loop that has to keep moving whether or not a
key is currently down, `KEY? ( -- flag )` checks without waiting,
leaving a true/false flag instead of a character code:

```forth
KEY? IF KEY . THEN     \ only reads (and prints) a key if one's ready
```

Checking with `KEY?` never consumes the keypress the way `KEY` does.
That's what makes this the standard idiom for "read a key only if
one's waiting" — `KEY?` genuinely just peeks, so a key you check for
is still there for `KEY` to read afterward.

`STICK ( device -- value )` reads a joystick, with `device` being 1 or
2. Device 1 reports a full 4-bit direction (which way, if any, is
pushed); device 2 reports a single on/off bit. With nothing connected
— true of every setup this has been tested against so far — both
always read `0`.

### Reading a whole line: `ACCEPT` and `INPUT`

`KEY` reads one keypress at a time, which is useful for reacting to
individual keys and tedious for something like "ask the player to type
their name." `ACCEPT` reads a whole LINE: give it a buffer address and
a maximum length, and it returns however many characters were actually
typed once you press Enter.

```forth
10 STRING NAME
NAME 1 + 10 ACCEPT NAME !     \ waits for you to type, echoing as you
                              \ go; store the length in NAME's own
                              \ count byte once you press Enter
NAME COUNT TYPE               \ prints back whatever you typed
```

(`NAME 1 +` is `STRING`'s own data area, skipping past its count byte
— see [Arrays](#4-reading-and-writing-memory-directly)'s own section
on memory addresses for why `+` is how you get there.) Delete and
backspace work while typing, and typing past the buffer's limit is
simply ignored rather than causing an error.

`INPUT` is a shortcut for the most common case, reading a single typed
number:

```forth
INPUT .    \ waits for you to type a number, then prints it back
```

`INPUT` reads a line the way `ACCEPT` does, parses it with `VAL` (see
[Strings](#4-reading-and-writing-memory-directly)), and leaves the
result on the stack — exactly BASIC's `INPUT A` for a single numeric
variable, spelled as a word instead of a statement.

---

## 10. Variables, constants, and comparisons in combination

Sections 4 and 5 introduced `VARIABLE`/`CONSTANT` and the comparison
words separately. Here's a slightly larger example putting several
pieces together: a simple counter that stops at a limit.

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

Nothing here is a new word. It's the same `VARIABLE`, `@`, `!`, `+`,
`>`, and `.` from earlier sections, combined the way a real program
would combine them.

---

## 11. Saving and loading your work

Programs don't have to be retyped every time the machine starts.
`SAVE` and `LOAD` write your definitions to tape and read them back.

```forth
: DOUBLER DUP + ;
SAVE MYPROG
```

`SAVE` takes the name that follows it — not a word to look up, but a
name, the same way `:` treats the name right after it as something to
define rather than run — and writes everything you've defined so far
to tape under it. Later, even after switching the machine off and back
on, which forgets everything you defined, you can get it back:

```forth
LOAD MYPROG
4 DOUBLER
```

`LOAD MYPROG` restores your definitions exactly as they were,
`DOUBLER` included, ready to use immediately as though you'd just
typed it in again. `LOAD` with no name at all loads whatever was saved
most recently, so you don't have to remember or retype the name.

There's no partial saving or loading of a single definition — `SAVE`
always writes everything defined up to that point, in one piece. If
you want your work checkpointed at meaningful moments, that's a matter
of when you choose to run `SAVE`, not something 2068-Forth tracks for
you.

One honest gap: what's proven so far is 2068-Forth's own bookkeeping —
what gets saved, how it's found again, and restoring your definitions
so they're immediately usable. Real tape behavior on real hardware, or
a real emulator's actual cassette playback, remains separately
unverified. Don't yet treat this as proof that a real recorded tape
will load back correctly on real hardware.

---

## 12. A wider screen

`64COL` switches to a 64-column *pixel graphics* display — twice the
normal horizontal resolution — and `32COL` switches back. `PALETTE64`
picks a color pair, and `PLOT64` sets a point on it, with `x` from 0
to 511 and `y` from 0 to 191, wider than the normal screen's
coordinate range. All four are real, working words:

```forth
64COL
3 PALETTE64
100 50 PLOT64
32COL
```

This is a **pixel graphics mode**, not a wider *text* display: typed
text and `EMIT`/`.`/`."` output are unaffected either way, still
always 32 columns wide.

What isn't yet resolved is `64COL`'s own visual behavior on real
hardware, which hasn't been fully characterized — testing showed the
screen rendering somewhat differently than expected, in ways not yet
explained. Treat this as the least mature word group in this document.
It works at the level that's been checked, but "what you'll actually
see on a real screen" isn't the settled answer it is for section 9's
normal-screen `PLOT`/`LINE`/`CIRCLE`.

---

## 13. Typing and editing at the prompt

Everything so far has described *what happens* when a line of Forth
runs. This section is about typing the line in the first place. While
you're entering something at the keyboard, before you press Enter, a
few keys behave specially rather than just adding a letter:

| Key | What it does |
|---|---|
| any ordinary character | Inserted at the cursor position |
| Enter | Finishes the line and runs it |
| Delete / backspace | Removes the character just before the cursor |
| Cursor left / right | Moves the cursor without changing anything |

The habit worth noticing: **the cursor doesn't have to be at the end
of the line.** Type `13`, move the cursor left one position so it sits
between the `1` and the `3`, type `2`, and the line becomes `123` —
the `2` was inserted exactly where the cursor was, and everything
after it shifted over to make room:

![The input line reading "123" with the cursor positioned before the final digit](images/live_editing.png)

The same works in reverse for fixing a typo: move the cursor past the
wrong character, hit Delete to remove the one *before* the cursor,
then keep typing or press Enter. None of this is specific to Forth —
it's the editing model of practically any text field — but it's worth
stating plainly, since BASIC on this same family of machines
historically handled line editing rather differently.

So what happens if you press Enter on a word that doesn't exist? A
typo like `5 BRODER` instead of `5 BORDER` prints the actual word it
didn't recognize, followed by `?`, then drops you right back at a
fresh prompt:

![The word "BRODER ?" printed after typing an unrecognized word](images/typo_error.png)

That's the first thing to check whenever `?` appears unexpectedly:
read exactly what's printed before it. It's often not the word you
think you typed — a dropped space silently glues two words together
(see the space-by-space breakdown in
[Defining your own words](#2-defining-your-own-words)) — and the
printed word makes that obvious instead of leaving you guessing.

When a line runs successfully, `OK` prints on its own line, so every
line you enter gets *some* visible confirmation one way or the other,
never silence.

A second kind of mistake — popping from an empty stack, or pushing
past its reserved space, as `DROP` with nothing on the stack would —
prints `STACK?` instead, and resets both stacks to empty rather than
leaving them in whatever corrupted state caused the problem. Like the
unrecognized-word `?`, this is a blunt, whole-line reset, not a
word-by-word explanation of what went wrong. See
[Error handling: THROW and CATCH](#14-error-handling-throw-and-catch)
for a way to intercept an error like this yourself, from inside your
own program, instead of always falling back to this default reset.

---

## 14. Error handling: THROW and CATCH

The previous section covered the defaults when something goes wrong:
`?` for an unrecognized word, `STACK?` for a stack mistake, both
abandoning the rest of the current line and dropping you at a fresh
prompt. That's the right behavior while you're typing interactively.
A real *program*, though, often wants to notice a problem itself and
keep running under its own control — trying something risky with a
planned fallback if it doesn't work out, rather than stopping
outright.

`THROW` and `CATCH` do exactly that:

| Word | Stack effect | What it does |
|---|---|---|
| `CATCH` | `( xt -- 0 \| n )` | Run the word `xt` identifies. `0` if it finished normally; the thrown value `n` if it `THROW`ed instead |
| `THROW` | `( n -- )` | `0` does nothing at all. Any other `n` abandons whatever's currently running and hands `n` to the nearest `CATCH` |

```forth
: RISKY   42 THROW ;         \ always throws 42
' RISKY CATCH .              \ prints 42
```

`' RISKY` gets `RISKY`'s own `xt` (see
[Indirect calls: ' and EXECUTE](#indirect-calls--and-execute) if that
part looks unfamiliar), and `CATCH` runs it. Since `RISKY` throws
rather than finishing normally, `CATCH` doesn't push `0` — it pushes
the thrown value, `42`. Nothing after the `THROW` inside `RISKY` ever
runs, and neither does anything else that was mid-call underneath it:
`CATCH` unwinds all of it automatically, restoring the stack to
exactly how it looked just before `CATCH` started, then adding the
thrown value on top.

A word that finishes normally, with no `THROW` anywhere inside, makes
`CATCH` push a plain `0`:

```forth
: SAFE   5 3 + ;
' SAFE CATCH .    \ prints 0 -- SAFE finished normally
DROP              \ SAFE's own result (8) is still sitting there,
                  \ underneath the 0 -- CATCH never touches what the
                  \ word itself pushed, only whether it THREW
```

Which gives the pattern for actually using `CATCH`: check whether the
top of the stack is `0`, and only then trust whatever the risky word
left underneath it.

```forth
' RISKY CATCH IF ." SOMETHING WENT WRONG: " . CR
ELSE DROP ." OK: " . CR
THEN
```

`THROW`ing with no `CATCH` anywhere to reach falls back to the reset
this document already described: both stacks emptied, `STACK?`
printed, and you're back at a fresh prompt, exactly as with an actual
stack mistake. `CATCH` doesn't replace that default; it gives a
program the option to intercept an error *before* it reaches that
point, for whichever specific problems the program knows how to
recover from. Anything it doesn't catch still falls through to the
usual reset, same as always.

---

## 15. Printing to a real printer: LPRINT and LLIST

BASIC's `LPRINT` and `LLIST` send output to an attached printer
instead of the screen. 2068-Forth has the same idea, adapted to the
way this Forth's dictionary works:

| Word | Stack effect | What it does |
|---|---|---|
| `LPRINT` | `( addr len -- )` | Print a string to the printer, wrapping across multiple printed lines if it's longer than one line |
| `LLIST` | `( -- )` | Print the name of every word you've defined since the machine started, newest first |

```forth
S" HELLO WORLD" LPRINT
```

`LLIST` deliberately does **not** print the ~100 built-in words this
Forth ships with — only what you've personally defined, the same way
BASIC's `LLIST` only ever showed *your* program and never anything
built into the ROM. There's also no real equivalent of BASIC's
line-numbered program listing to reproduce in the first place: once a
word is compiled, its original source text isn't kept around, so
`LLIST` shows *what exists*, a list of names, rather than
re-displaying the exact lines you typed.

**Status**: confirmed working against a real printer-capable Fuse
(`--printer --zxprinter`). `LPRINT` of a short string, and `LLIST`
after defining two words, both produced correct, legible printouts,
with `LLIST` in the documented newest-first order. A small amount of
pixel drift can appear in the raw printed dots; that traces to a Fuse
printer-emulation timing quirk — its virtual print head doesn't reset
position between the 8 raster rows of one character line — which the
real, unmodified 48K BASIC ROM reproduces too under the same setup. So
it isn't a bug in this project's code, and isn't necessarily something
real hardware would exhibit. See
[`PROJECT_PLAN.md`](PROJECT_PLAN.md)'s Phase 47 section for the full
verification history.

---

## 16. ULAPlus: a bigger color palette

Every color word covered so far — `INK`, `PAPER`, `BORDER` — picks
from the same fixed 8 colors the hardware has always had. ULAPlus is
an extension that replaces those 8 with 64 colors *you* choose,
without changing how
`INK`/`PAPER`/`PLOT`/`LINE`/`CIRCLE`/`FILL` are used at all.

| Word | Stack effect | What it does |
|---|---|---|
| `ULAPLUS` | `( flag -- )` | Nonzero enables the extended palette; zero reverts to the standard 8 colors |
| `PALETTE` | `( index value -- )` | Program palette register `index` (0-63) with color `value` |

A palette value packs green, red, and blue into one number,
`GGGRRRBB` — 3 bits of green, 3 of red, 2 of blue:

```forth
2 252 PALETTE     \ register 2 = 252 (11111100): green=7, red=7,
                  \ blue=0 -- yellow
1 ULAPLUS         \ turn the extended palette on
2 INK             \ INK still just says "color 2" -- ULAPLUS is
                  \ what decides color 2 now MEANS bright yellow
                  \ instead of the standard red
100 100 30 CIRCLE
100 100 FILL
```

Registers 0 through 7 replace the same 8 colors `INK`/`PAPER`/`BORDER`
already use, in the same order, so programming register 2 changes what
color 2 looks like everywhere that number is used — the screen border
included. This is a genuine, confirmed-working display-time palette
swap: a shape already drawn with `INK 2` changes color the moment
`PALETTE 2,...` and `ULAPLUS 1` run, with no need to redraw it.

**Honest limit worth knowing**: the real Timex Sinclair 2068 almost
certainly never had genuine ULAPlus hardware. It's a modern extension
designed for later Sinclair-compatible machines, made available here
through an emulator patch. What's confirmed is that this project's own
port-level code matches the documented real protocol and visibly works
in that patched emulator; whether it would behave identically on
unpatched, genuinely original TS2068 hardware remains an open
question — the same honest caveat this project's 64-column mode
carries in [A wider screen](#12-a-wider-screen).

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
| `ROT` | `( a b c -- b c a )` |
| `2DUP` | `( a b -- a b a b )` |
| `2DROP` | `( a b -- )` |
| `?DUP` | `( n -- 0 \| n n )` |
| `PICK` | `( ... n -- ... x )` |

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
| `AND` | `( a b -- a AND b )` |
| `OR` | `( a b -- a OR b )` |
| `XOR` | `( a b -- a XOR b )` |
| `INVERT` | `( a -- NOT a )` |

**Decimal (floating-point) arithmetic** — own stack, see section 3

| Word | Stack effect |
|---|---|
| `F+` | `( f1 f2 -- f1+f2 )` |
| `F-` | `( f1 f2 -- f1-f2 )` |
| `F*` | `( f1 f2 -- f1*f2 )` |
| `F/` | `( f1 f2 -- f1/f2 )` |
| `FSQRT` | `( f -- sqrt(f) )` |
| `FROUND` | `( f -- f' )` |
| `PI` | `( -- f )` |
| `SIN` | `( f -- sin(f) )` |
| `COS` | `( f -- cos(f) )` |
| `RAD` | `( degrees -- radians )` |
| `DEG` | `( radians -- degrees )` |
| `S>F` | `( n -- )` `( -- f )` |
| `F>S` | `( f -- )` `( -- n )` |
| `F.` | `( f -- )` |

**Memory**

| Word | Stack effect |
|---|---|
| `@` | `( addr -- n )` |
| `!` | `( n addr -- )` |
| `C@` | `( addr -- byte )` |
| `C!` | `( byte addr -- )` |
| `VARIABLE` | `( "name" -- )` |
| `CONSTANT` | `( n "name" -- )` |
| `ARRAY` | `( n "name" -- )` |
| `CELLS` | `( n -- n*2 )` |
| `FREE` | `( -- n )` |

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
| `CHR` | `( code -- addr len )` | a one-character string from a code |
| `STR` | `( n -- addr len )` | a number, as a string |
| `UPPER` | `( addr len -- addr len )` | uppercase, in place |
| `LOWER` | `( addr len -- addr len )` | lowercase, in place |
| `LEFT` | `( addr len n -- addr len' )` | first `n` characters |
| `RIGHT` | `( addr len n -- addr' len' )` | last `n` characters |
| `SEARCH` | `( addr1 len1 addr2 len2 -- addr3 len3 flag )` | find string 2 inside string 1 |
| `CODE` | `( addr len -- code )` | character code of the first character |

**Defining and control flow**

| Word | Stack effect | Notes |
|---|---|---|
| `:` ... `;` | — | define a new word |
| `'` | `( -- xt )` | look up a word by name, without calling it |
| `EXECUTE` | `( xt -- )` | call the word an `xt` identifies |
| `IF` ... `ELSE` ... `THEN` | `( flag -- )` | IMMEDIATE, compile-only |
| `BEGIN` ... `UNTIL` | `( flag -- )` | IMMEDIATE, compile-only |
| `BEGIN` ... `WHILE` ... `REPEAT` | `( flag -- )` | IMMEDIATE, compile-only |
| `DO` ... `LOOP` | `( limit start -- )` | IMMEDIATE, compile-only |
| `DO` ... `+LOOP` | `( limit start -- )` / `( step -- )` | IMMEDIATE, compile-only |
| `LEAVE` | `( -- )` | IMMEDIATE, compile-only; exits the innermost `DO` loop |
| `I` | `( -- index )` | innermost `DO` loop's index |

**Error handling** — see [section 14](#14-error-handling-throw-and-catch)

| Word | Stack effect |
|---|---|
| `CATCH` | `( xt -- 0 \| n )` |
| `THROW` | `( n -- )` |

**Printing and input**

| Word | Stack effect |
|---|---|
| `.` | `( n -- )` |
| `."` text`"` | `( -- )` — compile-only |
| `EMIT` | `( char -- )` |
| `CR` | `( -- )` |
| `SPACE` | `( -- )` |
| `SPACES` | `( n -- )` |
| `KEY` | `( -- char )` |
| `KEY?` | `( -- flag )` |
| `STICK` | `( device -- value )` |
| `ACCEPT` | `( dest maxlen -- len )` |
| `INPUT` | `( -- n )` |
| `AT-XY` | `( col row -- )` |

**Drawing and sound**

| Word | Stack effect |
|---|---|
| `PLOT` | `( x y -- )` |
| `LINE` | `( x1 y1 x2 y2 -- )` |
| `CIRCLE` | `( xc yc r -- )` |
| `FILL` | `( x y -- )` |
| `CLS` | `( -- )` |
| `BORDER` | `( color -- )` |
| `INK` | `( color -- )` |
| `PAPER` | `( color -- )` |
| `BEEP` | `( n-semitones fduration -- )` |
| `SOUND` | `( register data -- )` |
| `64COL` / `32COL` | `( -- )` |
| `PALETTE64` | `( n -- )` |
| `PLOT64` | `( x y -- )` |
| `ULAPLUS` | `( flag -- )` — see [section 16](#16-ulaplus-a-bigger-color-palette) |
| `PALETTE` | `( index value -- )` — see [section 16](#16-ulaplus-a-bigger-color-palette) |

**Storage**

| Word | Stack effect |
|---|---|
| `SAVE` | `( "name" -- )` |
| `LOAD` | `( "name" -- )` |

**Printer** — see [section 15](#15-printing-to-a-real-printer-lprint-and-llist)

| Word | Stack effect |
|---|---|
| `LPRINT` | `( addr len -- )` |
| `LLIST` | `( -- )` |

---

## Appendix B: what's not here yet

A few things a Forth veteran would expect, and a BASIC programmer
would ask about, aren't part of 2068-Forth yet:

- **Hi-res graphics mode** — beyond the normal-resolution words in
  section 9 and the experimental 64-column pixel mode in section 12.
- **Plain integer `*` and `/`** — only the decimal versions, `F*`/`F/`
  (section 3), exist so far.

See [`PROJECT_PLAN.md`](PROJECT_PLAN.md) for this project's own build
history and phased development order, if you're curious how 2068-Forth
was actually put together rather than just how to use it.
