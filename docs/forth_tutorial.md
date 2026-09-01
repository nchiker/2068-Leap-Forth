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

## 5. What's not here yet

A few things a Forth veteran would expect, and a BASIC programmer would
ask about, aren't part of 2068-Forth yet. Each will get its own section
here once it's real:

- **Control flow** — `IF`/`ELSE`/`THEN`, and loops (`BEGIN`/`UNTIL`,
  `DO`/`LOOP`). Right now every example in this document runs straight
  through with no branching or repetition.
- **Printing and input** — there's no `.` (print the top of the stack)
  or way to read a line you type yet, so none of this document's
  examples can be tried interactively at a prompt today; they describe
  what typing them *will* do once that exists.
- **Named variables** (`VARIABLE`) and constants (`CONSTANT`), built on
  top of the `@`/`!` in section 4.
- **Graphics and sound** — TS2068-specific words for pixels, lines,
  circles, and sound, comparable to BASIC's `PLOT`/`SOUND`/`BEEP`.
  Nothing like this exists yet.
- **Saving and loading your own definitions** to and from tape.

See [`PROJECT_PLAN.md`](PROJECT_PLAN.md) for the full order these are
planned to arrive in.
