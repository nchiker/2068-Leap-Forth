# Learning Forth on 2068-Forth

This document teaches Forth itself to someone who has never used it
before. It assumes you're comfortable with BASIC (line numbers,
`LET`/`PRINT`/`IF`, variables) but *not* with Forth — the two languages
think about programs so differently that BASIC experience mostly
doesn't transfer, and this document doesn't assume it does. It does
not assume you know assembly language or anything about how this
project is built; that's a separate audience covered by
[`PROJECT_PLAN.md`](PROJECT_PLAN.md) and the source code itself.

**This document teaches the language, not this project's construction
of it.** Everything below describes what you, typing at a 2068-Forth
prompt, would see and do. Sections are added as each part of the
language becomes real and usable — see the status note at the end of
each section for exactly what's true right now versus still to come.

**A live prompt genuinely exists.** Turning the machine on shows a
banner, plays a short startup sound, and drops you at a real,
keyboard-driven prompt — every example in this document, including `.`
(section 9), can actually be typed in and run, not just read about.

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

### 1.1 The stack, and why `5 3 +` means "5 + 3"

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

A handful of words exist just to rearrange the stack itself, since with
no variable names, getting a value into the right position *is* often
the whole problem:

| Word | Effect | What it does |
|---|---|---|
| `DUP` | `( n -- n n )` | Duplicate the top value |
| `SWAP` | `( a b -- b a )` | Swap the top two values |
| `DROP` | `( n -- )` | Discard the top value |
| `OVER` | `( a b -- a b a )` | Copy the second value to the top |

That `( n -- n n )` notation is standard Forth shorthand: what the
stack looks like right before the word runs, an arrow, then right
after — top of stack is always the rightmost item in each group. You'll
see it throughout Forth documentation (including this project's own
source code) and it's worth getting comfortable reading it now.

For example, doubling a number without a variable to hold it in:
`5 DUP +` — push 5, duplicate it (`[5, 5]`), add (`[10]`).

**Status:** `DUP`, `SWAP`, `DROP`, `OVER`, `+`, `-`, and the fetch/store
words `@`/`!` (covered in section 4) all exist and work in 2068-Forth
today, exactly as described above.

### 1.2 Words and the dictionary

Everything in Forth — `+`, `DUP`, a word you define yourself — lives in
the **dictionary**: the complete list of every word the system
currently knows. When you type a word, Forth looks it up in the
dictionary by name. If it's not found, Forth tries to read it as a
plain number instead. If that fails too, you've made a typo or used an
undefined word, and Forth reports an error.

The dictionary is searched **newest-first**. If you define a word with
the same name as an existing one, your new definition takes over for
anything you type *after* that point — the old one still exists deeper
in the dictionary (anything that already used it keeps working
unchanged), it's just no longer what a plain lookup finds by that name.
This is occasionally useful (redefining a word to fix a mistake without
restarting) and occasionally a source of confusion (forgetting you
shadowed something) — worth knowing about either way.

**Status:** the dictionary and name lookup work today.

### 1.3 Defining your own words

This is the part of Forth that BASIC has no real equivalent for. In
BASIC, you write a program; the language itself doesn't grow while
you're using it. In Forth, defining a new word **extends the
language** — your word becomes exactly as usable as `+` or `DUP` from
that point on, no different in kind.

```forth
: DOUBLE DUP + ;
```

Reading this left to right: `:` says "define a new word, named
`DOUBLE`, from everything up to the next `;`." Each word inside the
definition — here, `DUP` and `+` — gets remembered as part of what
`DOUBLE` does, rather than run immediately. `;` ends the definition.

Nothing has actually *run* yet at this point — you've just taught Forth
a new word. Now use it:

```forth
4 DOUBLE
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

**Status:** `:` and `;` both work today — you can define new words
built out of any word 2068-Forth currently knows, and immediately use
your new word by name, exactly as shown above.

### 1.4 Interpreting vs. compiling — why `;` is special

There's a flag Forth keeps internally, usually just called **STATE**:
it's either "interpreting" (run each word as you type it — everything
in section 1.1) or "compiling" (remember each word as part of a
definition instead — what happens between `:` and `;`).

`;` has to flip that flag back to "interpreting" the *moment* it's
read, or compiling would never stop. That means `;` can't follow the
normal rule of "get remembered as part of the definition" — it has to
act immediately, even while compiling is otherwise in effect. A word
that always runs immediately like this, even in the middle of a
definition, is called **IMMEDIATE**.

You won't need to define your own IMMEDIATE words for ordinary Forth
programming, but it's worth knowing the concept exists, because it's
also how words like `IF` and `ELSE` behave (once available — see
section 5): they aren't ordinary words that get compiled into a
definition's body, they're IMMEDIATE words that shape *how* the
surrounding definition gets compiled.

**Status:** interpreting vs. compiling, and `;` as the one IMMEDIATE
word, both work today. Nothing else IMMEDIATE exists yet.

---

## 2. A complete worked example

Putting the last two sections together, here's a small but complete
piece of Forth: a word that squares a number, built out of a word that
doubles one.

```forth
: DOUBLE DUP + ;
: QUADRUPLE DOUBLE DOUBLE ;

3 QUADRUPLE
```

- `DOUBLE` is defined as before.
- `QUADRUPLE` is defined *using* `DOUBLE` — this is completely ordinary;
  a word's definition can use any word that exists at the time it's
  defined, including one you just wrote yourself a moment ago.
- `3 QUADRUPLE` pushes `3` (`[3]`), then runs `QUADRUPLE`, which runs
  `DOUBLE` twice: `[3]` → `[6]` → `[12]`.

Notice that `QUADRUPLE` never mentions the stack, arithmetic, or how
`DOUBLE` works internally — it just names a sequence of existing words.
This is the normal shape of Forth programming: small words, each
trivially checkable by hand, combined into larger ones.

---

## 3. Numbers

2068-Forth's numbers are whole numbers only — no decimal points. `5`,
`-12`, and `0` are all valid; `3.14` is not (yet — see
[`numeric_model.md`](numeric_model.md) for why this was a deliberate
choice rather than an oversight, and what it would take to add decimal
numbers later). If you're used to BASIC letting you write `3.14`
anywhere a number goes, this is the one place 2068-Forth will feel more
restrictive than what you're used to.

**Status:** whole numbers, including negative numbers (a leading `-`),
work today.

---

## 4. Reading and writing memory directly

Forth gives you direct access to memory as two words:

| Word | Effect | What it does |
|---|---|---|
| `@` (read "fetch") | `( addr -- n )` | Read the value stored at `addr` |
| `!` (read "store") | `( n addr -- )` | Write `n` to `addr` |

Note the order for `!`: the *value* goes on the stack first, then the
*address* — read it as "store `n` at `addr`," matching the order the
words appear when you write `n addr !`. This trips up almost everyone
the first time; there's no trick to it beyond remembering the mnemonic.

This is a much lower-level tool than BASIC's variables — there's no
`DIM`, no named storage, just addresses. A full introduction to
building your own named variables out of this (Forth's `VARIABLE` word)
belongs in a later section, once that word exists in 2068-Forth.

**Status:** `@` and `!` work today. `VARIABLE` and other conveniences
built on top of them do not exist yet.

---

## 5. Making decisions: `IF` `ELSE` `THEN`

Every example so far has run straight through, top to bottom, with no
branching. `IF`/`ELSE`/`THEN` is Forth's equivalent of BASIC's
`IF...THEN...ELSE`, with one difference worth calling out up front: the
condition comes from the stack, checked *before* you reach `IF`, not
written as part of the `IF` itself.

```forth
: DESCRIBE  IF ." positive-ish" ELSE ." zero or negative" THEN ;
```

*(That example uses `."`, which prints a literal string of text — a
different, still-not-built feature from `.`'s printing of a computed
number (section 9); see section 12 — so treat it as a preview of the
shape rather than something to try today. Here's the same idea using
only what actually works right now:)*

```forth
: SIGNTEST  IF 111 ELSE 222 THEN ;

5 SIGNTEST     \ pushes 5 (true-ish), runs SIGNTEST: leaves 111
0 SIGNTEST     \ pushes 0 (false), runs SIGNTEST: leaves 222
```

Reading `SIGNTEST`: when it runs, whatever's already on top of the
stack is treated as the condition. `IF` pops it and checks: **zero
means false**, anything else means true. If true, everything up to the
matching `ELSE` (or `THEN`, if there's no `ELSE`) runs; if false, the
`ELSE` part runs instead (or nothing, if there's no `ELSE`). `THEN`
doesn't mean "then do this" the way it does in BASIC — it just marks
where the `IF`/`ELSE` branching ends and normal execution continues.
This naming is a common early stumbling block for BASIC programmers
specifically because the word is so familiar-looking and means
something different.

Since "zero means false" is how every condition in Forth works, you
often need a word that turns an ordinary calculation into a proper
true/false answer. `0=` does exactly that:

| Word | Effect | What it does |
|---|---|---|
| `0=` | `( n -- flag )` | `flag` is true if `n` is exactly `0`, false otherwise |

```forth
: ISZERO  0= IF 111 ELSE 222 THEN ;

0 ISZERO     \ 0= sees 0 -> true -> 111
5 ISZERO     \ 0= sees 5 -> false -> 222
```

**Status:** `IF`, `ELSE`, `THEN`, and `0=` all work today, exactly as
shown above (the `."` example is the only preview in this section).

## 6. Repeating yourself: `BEGIN` `UNTIL`

BASIC has several looping constructs (`FOR`/`NEXT`, `WHILE`/`WEND`).
2068-Forth currently has the simplest one Forth offers: `BEGIN ...
UNTIL`, which repeats the code between `BEGIN` and `UNTIL` until the
condition just before `UNTIL` becomes true. Since the check happens at
the *end*, the loop body always runs at least once — the same shape as
BASIC's `REPEAT...UNTIL`, if you've used a dialect with one, or
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
counted down *and* the loop's exit test. A loop with a proper built-in
counter (BASIC's `FOR`/`NEXT`, Forth's own `DO`/`LOOP`) is planned but
not built yet — see section 12.

**Status:** `BEGIN` and `UNTIL` work today, exactly as shown above.

---

## 7. Drawing and sound

2068-Forth's graphics and sound words are deliberately thin: each one
is a direct, single-purpose action, the same way BASIC's `PLOT`,
`CIRCLE`, and `BEEP` are — there's no drawing "state" to set up first
beyond what each word's own arguments say.

| Word | Effect | What it does |
|---|---|---|
| `PLOT` | `( x y -- )` | Set the pixel at `(x, y)` |
| `LINE` | `( x1 y1 x2 y2 -- )` | Draw a line from `(x1, y1)` to `(x2, y2)` |
| `CIRCLE` | `( xc yc r -- )` | Draw a circle outline centered at `(xc, yc)` with radius `r` |
| `BORDER` | `( color -- )` | Set the screen border to `color` (0-7, same numbering as BASIC's `BORDER`) |
| `BEEP` | `( pitch duration -- )` | Produce a tone |

```forth
10 20 PLOT              \ a single dot
60 5 100 45 LINE         \ a diagonal line
150 100 20 CIRCLE        \ a circle, radius 20, centered at (150,100)
5 BORDER                 \ cyan border
```

Reading these left to right follows the same postfix habit as
everything else in this document: for `LINE`, the coordinates go on the
stack in the order you'd say them out loud ("from 60,5 to 100,45"),
then the word that acts on all four at once. Nothing here is
conceptually new over section 1 — these are just words, exactly like
`+` or `DUP`, that happen to affect the screen or speaker instead of a
number.

Two honest limits worth knowing now rather than discovering by
surprise:

- **No color choice yet.** Every shape draws in a fixed default (black
  on white) — there's no `INK`/`PAPER` equivalent to pick a different
  color per shape, the way BASIC's `INK`/`PAPER` statements do.
- **`BEEP`'s two numbers aren't musical.** BASIC's `BEEP` typically
  takes a duration in seconds and a pitch as a semitone offset;
  2068-Forth's `BEEP` takes lower-level, hardware-timing numbers
  instead, with no conversion between the two yet. Getting a specific,
  predictable musical note or duration out of it isn't straightforward
  today.

**Status:** `PLOT`, `LINE`, `CIRCLE`, `BORDER`, and `BEEP` all work
today, exactly as shown above. `FILL` (flood-fill an area), `AT-XY`
(position text), hi-res graphics mode, and any color/`INK`/`PAPER`
words do not exist yet.

---

## 8. Typing and editing a line

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
everything after it shifted over to make room. The same works in
reverse for fixing a typo: move the cursor past a wrong character, hit
Delete to remove the one *before* the cursor, then keep typing or press
Enter. Nothing about this is specific to Forth — it's the same editing
model as typing into practically any text field — but it's worth
stating plainly since BASIC on this same family of machines historically
handled line editing somewhat differently.

**Status:** all of it — insert, delete, cursor movement, and a real,
live, keyboard-driven prompt to try them at — works today. This
section's own `13`→`123` example is something you can actually type
and watch happen now, not just a description of intended behavior.

---

## 9. Printing

A word like `+` leaves its answer sitting on the stack — nothing shows
it to you unless you ask. `.` (pronounced "dot") does exactly that:

```
5 3 + .
```

prints `8` (followed by a trailing space, so several `.`s in a row read
as separate, space-separated numbers rather than running together) and
removes the value from the stack in the process — `.` both reads *and
consumes* the top of the stack, unlike, say, `DUP`. Negative numbers
print with a leading `-`, and zero prints as `0`.

`EMIT` is the lower-level word underneath `.`: it takes a single
number off the stack and prints it as one character, at whatever
character code that number is. `65 EMIT` prints `A` (65 is `A`'s
character code); `. ` itself is built out of repeated `EMIT` calls, one
per digit. Both `.` and `EMIT` share one printing position — text wraps
to a new line automatically past column 32, and scrolls the screen once
it reaches the row just above where you're typing, so printed output
can never collide with the line you're currently entering.

**Status:** both exist and work — see
[`PROJECT_PLAN.md`](PROJECT_PLAN.md)'s Phase 10 for the underlying
implementation, including a real bug (found live, by typing at the
keyboard) where the very first thing printed after booting silently
overwrote part of the startup banner, since fixed.

---

## 10. Saving and loading your work

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

**Status:** `SAVE` and `LOAD` both work today, including loading by an
exact name and loading with no name given. What's genuinely still
unverified is real tape behavior on real hardware or in a real
emulator's actual cassette playback — what's been proven so far is that
2068-Forth's own bookkeeping (what gets saved, how it's found again,
restoring your definitions so they're immediately usable) is correct,
using a stand-in for the real tape transport during testing. This
distinction matters if you're testing this yourself: don't yet treat a
passing automated check as proof that a real recorded tape will load
back correctly — that's real, honest, still-open work, not something
quietly assumed to be fine.

---

## 11. Stretch goals: decimal numbers and a wider screen

Two experimental pieces exist outside the main, planned path through
this document — early, incomplete, and worth knowing about mainly so
you don't mistake their gaps for something more finished being broken.

**Decimal numbers.** `F+` and `F-` add and subtract numbers with a
fractional part — the ordinary `+`/`-` from section 1 only ever work on
whole numbers. There's no way to *write* a decimal number yet (`NUMBER`
only understands whole numbers, section 3), so these two words can't
actually be reached by typing an expression today — they exist and
work, proven by feeding them values directly rather than through typed
text, but they're not yet reachable the way `+` is. Only addition and
subtraction exist; multiplying or dividing decimal numbers doesn't yet,
and `.` (section 9) only knows how to print whole numbers.

**A wider screen.** `64COL` switches to a 64-column display — twice the
normal text width — `32COL` switches back, `PALETTE64` picks a color
pair, and `PLOT64` sets a point on it (`x` 0-511, `y` 0-191, wider than
the normal screen's own coordinate range). All four are real, working
words. What isn't yet resolved: this mode's visual behavior hasn't been
fully characterized — testing it showed the screen rendering somewhat
differently than expected in ways not yet explained. Treat this one as
the least mature of everything in this document; it works at the level
that's been checked, but "what you'll actually see on a real screen"
isn't yet a settled answer the way it is for section 7's normal-screen
`PLOT`/`LINE`/`CIRCLE`.

**Status:** `F+`, `F-`, `64COL`, `32COL`, `PALETTE64`, and `PLOT64` all
exist and do what's described above. Both are explicitly experimental,
unlike every other section in this document — see
[`PROJECT_PLAN.md`](PROJECT_PLAN.md)'s Phase 8 for the full detail.

---

## 12. What's not here yet

A few things a Forth veteran would expect, and a BASIC programmer would
ask about, aren't part of 2068-Forth yet. Each will get its own section
here once it's real:

- **Counted loops** — Forth's `DO`/`LOOP` (comparable to BASIC's
  `FOR`/`NEXT`, complete with a built-in loop counter, unlike
  `BEGIN`/`UNTIL` in section 6) and `BEGIN`/`WHILE`/`REPEAT` (a
  loop that can check its condition *before* each pass, not just after).
- **More comparisons** — only `0=` (section 5) exists so far. Ordinary
  `=`, `<`, and `>` between two arbitrary numbers don't exist yet.
- **Printing literal text** — `.` (section 9) prints a *computed
  number*; there's no `."` yet for printing a fixed piece of text
  (`." hello"`) the way BASIC's `PRINT "hello"` does.
- **Named variables** (`VARIABLE`) and constants (`CONSTANT`), built on
  top of the `@`/`!` in section 4.
- **More graphics and sound** — `FILL`, `AT-XY`, hi-res mode, and
  color/`INK`/`PAPER` words (see section 7's own status note).
- **Decimal number literals, multiply, and divide** — see section 11.

See [`PROJECT_PLAN.md`](PROJECT_PLAN.md) for the full order these are
planned to arrive in.
