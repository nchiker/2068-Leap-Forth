# Learning Forth on 2068-Leap-Forth

## About This Manual

This manual teaches Forth from scratch. It assumes you are comfortable with classic BASIC (line numbers, `LET`, `PRINT`, `IF`, and standard variables), but requires **no prior experience with Forth**.

#### A Live Environment

Every example in this manual can be typed directly into a **2068-Leap-Forth** prompt.

When you turn on the machine, you will immediately be greeted by a startup banner, a brief audio cue, and an active, keyboard-driven prompt waiting for your input.

#### How to Read the Examples

To make the most of this manual, keep two conventions in mind before you start typing:

#### Understanding Comments (and Their Absence)

- Anything appearing after a `\` symbol in an example is an explanatory note for you, **not** part of the Forth code.

- **Important:** 2068-Leap-Forth does not include a built-in comment word (unlike larger Forth implementations that use `\` or parentheses). If you type a backslash and its note into the interpreter, it will treat `\` as a command, fail to find it, and return an error. **Type only the code that precedes the backslash.**

#### Sequential Learning

- **Builds in Order:** Each section builds directly on the previous one. When a later exercise relies on an earlier concept, the text provides a quick refresher so you won't need to constantly flip backward.

- **Linear Design:** The manual is structured in a strict learning progression. Reading out of order will make concepts harder to grasp than moving through them step by step.

---

## 1. What Forth Actually Is

In BASIC, every line is a **statement** governed by strict grammar (e.g., `LET X = 5+3`, `IF X > 3 THEN GOTO 100`). `LET` requires an equals sign; `IF` requires a `THEN`.

Forth has **no grammar at all**. A Forth program is simply a sequence of **words** separated by spaces, driven by one fundamental rule: *Read the next word, then either run it or compile it.

In Forth, spaces are strict required syntax rather than mere formatting. Because the interpreter splits everything on whitespace, a missing space silently glues two separate words together into a single, unrecognized token that the system cannot distinguish from a genuine typo.

### Words and the Dictionary

Everything in Forth—from arithmetic operators like `+` to stack manipulators like `DUP` and custom words you write yourself—lives in the **dictionary**, which is the complete list of every word the system currently knows.

- **Lookup Process:** When you type a word, Forth searches the dictionary by name.

- **Number Fallback:** If the dictionary lookup fails, Forth attempts to interpret the input as a plain number.

- **Error Handling:** If that also fails, Forth recognizes an undefined word or typo, prints a simple `?` on its own line, and returns you to a fresh prompt without crashing or failing silently.

#### Shadowing Existing Words

The dictionary is searched **newest-first**:

- **Redefining:** If you define a new word with the exact same name as an existing one, your version takes over for any new commands you type.

- **Old References:** The old definition remains intact deeper in the dictionary, meaning any existing code that already relied on it continues working unchanged.

- **Trade-off:** This behavior is occasionally useful for quickly fixing a mistake without restarting, but can occasionally be confusing if you accidentally shadow an existing word.

That single cycle—read a word, look it up in the dictionary, and run whatever it names—forms the foundation of the language. The next question is what running a word actually does, which brings us to the data stack.

#### The Stack, and Why `5 3 +` Means "5 + 3"

In BASIC, arithmetic is written **infix**—the operator sits right between its operands (`5 + 3`). Forth writes it **postfix** (or Reverse Polish Notation): operands first, operator last (`5 3 +`).

This isn't a stylistic quirk. Postfix notation is precisely what allows Forth's "read a word, run it" rule to work without any grammar rules or order-of-operations parsing.

### The Stack (The Index Card Analogy)

The engine behind Forth is a **data stack**: a LIFO (last-in, first-out) pile of numbers where you can only ever see, add to, or remove from the top.

Hold this mental picture:

- **The Pile:** Think of a stack of index cards.

- **Pushing a Number:** To remember a number, the machine writes it on a fresh card and drops it right on top of the pile.

- **Popping a Number:** To *use* a number, it takes the top card off, reads it, and discards it.

#### How Words Interact with the Stack

Every word in Forth does one of two things to that pile:

- **A Number:** Gets *pushed* onto the stack as a new card on top.

- **An Operator:** *Pops* however many cards it needs off the top, computes the result, and *pushes* a single new card back down with the answer.

#### The Recipe Rule

Forth's workflow follows the exact same logic as a kitchen recipe: **first gather your ingredients, then say what to do with them.**

The numbers (ingredients) go on the stack first; the word that acts on them (the action) comes last.

Let's trace how this works step by step with `5 3 +`:

```
you type   stack after (top is rightmost)
--------   ----------------------------
5          [5]           -- push 5
3          [5, 3]        -- push 3
+          [8]           -- pop 3 and 5, push their sum
```

### The Stack *Is* the Grammar

Because of this stack-based design, Forth needs **no parentheses, no operator precedence rules, and no complex parser**.

The `+` operator doesn't care whether `5` and `3` came from raw numbers, variables, or the results of previous calculations. It simply grabs the top two numbers waiting on the stack and adds them together.

### Typing and editing at the prompt

Everything so far has described *what happens* when a line of Forth runs. This section is about typing the line in the first place. While you're entering something at the keyboard, before you press Enter, a few keys behave specially rather than just adding a letter:

| Key                    | What it does                                 |
| ---------------------- | -------------------------------------------- |
| any ordinary character | Inserted at the cursor position              |
| Enter                  | Finishes the line and runs it                |
| Delete / backspace     | Removes the character just before the cursor |
| Cursor left / right    | Moves the cursor without changing anything   |

The habit worth noting is that **the cursor does not have to stay at the end of the line.** Type `13`, move the cursor left one position so it sits between the `1` and the `3`, and type `2`. The line becomes `123`—the `2` is inserted exactly where the cursor was, and everything following it shifts over to make room.

None of this changes what Forth actually reads. No matter how many times you insert, delete, or move the cursor around, Forth receives only the final, finished line, split on spaces exactly as described from the start—editing happens *before* reading, never during it.

### Seeing the Answer: The `.` (Dot) Word

- **Objective:** Understand how to reveal hidden stack data using the print operator and how Forth’s left-to-right execution flow replaces traditional nested expressions.

- **Core Concepts:**
  
  - **Invisible Stack:** Calculated values sit on the stack automatically, but nothing appears on screen without an explicit display command.
  
  - **The Dot Word (`.`):** Pronounced "dot," it acts like any other word by following the "ingredients first" rule—it pops and consumes the top number off the stack to print it.
  
  - **Destructive Output:** Because printing consumes the target value, executing `5 3 + .` leaves the stack completely empty after outputting `8`.

```forth
5 3 + .        \ prints 8
10 11 + 12 + . \ prints 33
```

- **Execution Breakdown (Tracing `10 11 + 12 + .`):**
  
  - `10` → `[10]` (Pushes initial starting value)
  
  - `11` → `[10, 11]` (Pushes second value)
  
  - `+` → `[21]` (Pops both, adds them, pushes result)
  
  - `12` → `[21, 12]` (Pushes next value)
  
  - `+` → `[33]` (Pops both, adds them, pushes result)
  
  - `.` → `[]` (Pops final value, prints it, empties stack)

- **Key Takeaways:**
  
  - **Left-to-Right Adjustments:** Expressions read as a series of incremental updates to the top of the stack (e.g., `11 +` means "add 11 to whatever is on top").
  
  - **Breaking the BASIC Habit:** Unlike nested expressions like `(5+3)-2`, Forth sequences operations directly as `5 3 + 2 -`, matching the exact chronological order the machine performs the work.

##### Order Matters — Even When You'd Swear It Didn't

While `+` is symmetric and treats its inputs equally (`5 3 +` and `3 5 +` both yield 8), subtraction is directional. The `-` operator subtracts the **top** of the stack from the value sitting directly **underneath** it:

Consider this contrast:

```forth
10 3 - .      \ prints 7
3 10 - .      \ prints -7
```

Rather than throwing an error or defaulting to a positive number, the second example is a perfectly valid subtraction running in reverse (`3 - 10`). Reading `10 3 -` aloud as "ten, three, subtract"—the exact order you would write it on paper as `10 - 3`—makes the mental pattern stick: the operands stay in the order you speak them, and only the operator moves to the end. 

### Rearranging the Stack

When a language has no variable names, getting values into the correct position is frequently the primary challenge. For instance, doubling a number by writing `5 5 +` only works because you manually typed the `5` twice. A custom word meant to double *whatever* sits on the stack must generate that second copy itself, since it cannot read a value without consuming it or stash a copy in a variable.

Stack-shuffling primitives exist precisely to solve this problem. They perform no math; they simply rearrange existing items so that the next word finds its ingredients waiting on top:

| **Word** | **Stack effect**   | **What it does**                 |
| -------- | ------------------ | -------------------------------- |
| `DUP`    | `( n -- n n )`     | Duplicate the top value          |
| `SWAP`   | `( a b -- b a )`   | Swap the top two values          |
| `DROP`   | `( n -- )`         | Discard the top value            |
| `OVER`   | `( a b -- a b a )` | Copy the second value to the top |

Doubling a number dynamically becomes `5 DUP +`. Tracing this out step-by-step shows how it works:

```
you type   stack after
--------   -----------
5          [5]          -- push 5
DUP        [5, 5]       -- copy the top card
+          [10]         -- pop both, push their sum
```

`OVER` reaches one level deeper than `DUP`: instead of copying the top value, it copies the *second* value to the top, leaving everything already there untouched underneath it:

```
you type   stack after
--------   -----------
10         [10]            -- push 10
20         [10, 20]        -- push 20
OVER       [10, 20, 10]    -- copy the second value (10) to the top
```

Running it twice in a row — `OVER OVER` — duplicates the entire pair, not just one value out of it:

```
you type   stack after
--------   -----------
10         [10]
20         [10, 20]
OVER       [10, 20, 10]
OVER       [10, 20, 10, 20]  -- the second OVER reaches the (now second) 20
```

The result, `[10, 20, 10, 20]`, is the original pair sitting on the stack twice — the exact habit worth reaching for whenever a later word is about to consume a value you still need again afterward: make the spare copy *before* it's gone, not after. This pattern comes up often enough that it earns its own name, `2DUP`, in the "Advanced Shuffling" table below.

#### Reading Stack Effect Shorthand

Writing out a card-by-card trace for every command quickly becomes tedious. Instead, Forth manuals use a concise one-line notation: **the stack just before execution, an arrow, and the stack just after**, with the top of the stack always positioned on the far right.

For example, `DUP`'s notation—`( n -- n n )`—indicates that one value was on top beforehand, and two identical copies remain afterward. This same shorthand describes every core word:

- A bare number `( -- n )` takes nothing and leaves one value.

- `+` `( a b -- a+b )` takes two values in and returns one sum.

- `-` `( a b -- a-b )` takes two values, where `a` is deeper, `b` is on top, and the result is `a` minus `b`.

- `.` `( n -- )` takes one value and leaves nothing behind, reflecting the fact that printing consumes its target.

Input and output counts do not need to match. `DROP` takes one value and leaves none `( n -- )`, while `DUP` takes one and leaves two `( n -- n n )`. Furthermore, letters like `a`, `b`, or `n` are merely readable placeholders; you should always read positions rather than attaching meaning to specific letters.

### Advanced Shuffling & Extended Primitives

When dealing with three or more values, or when you need to reach deeper into the stack without disturbing what rests above, a few additional words round out the set:

| **Word** | **Stack effect**     | **What it does**                                                 |
| -------- | -------------------- | ---------------------------------------------------------------- |
| `ROT`    | `( a b c -- b c a )` | Rotate the third value to the top                                |
| `2DUP`   | `( a b -- a b a b )` | Duplicate the top *pair*                                         |
| `2DROP`  | `( a b -- )`         | Discard the top *pair*                                           |
| `?DUP`   | `( n -- 0 \| n n )`  | Duplicate, but only if `n` isn't zero                            |
| `PICK`   | `( ... n -- ... x )` | Copy the $n$-th value from the top (`0` is `DUP`, `1` is `OVER`) |

`ROT` is notoriously tricky to visualize without a trace. When you run `1 2 3 ROT . . .`, it prints `1 3 2`:

```forth
you type    stack after
--------    -----------
1           [1]
2           [1, 2]
3           [1, 2, 3]
ROT         [2, 3, 1]    -- the THIRD value (1) moves to the top
.           [2, 3]       -- prints 1
.           [2]          -- prints 3
.           []           -- prints 2
```

Rather than merely being copied, the third value is completely removed from its original slot and reinserted on top, causing the values above it to slide down one slot to fill the gap.

Meanwhile, `?DUP` solves a very specific structural problem. Testing a value normally consumes it, meaning you would otherwise have to copy the value, test the copy, and clean up the extra item afterward. `?DUP` avoids this overhead by copying the value *only* if it is non-zero, making it ideal for conditional checks like `SOME-WORD ?DUP IF . THEN`.

```
10 20 2DUP + .        \ [10, 20, 10, 20] then prints 30, leaving [10, 20]
10 20 2DROP           \ [10, 20] then [] -- both gone in one word
```

That behavior won't fully click until you meet `IF` in section 7, which returns to `?DUP` and shows the same example written both ways—with and without it—so you can see exactly what it saves. For now, just note that the word exists and that its strange-looking `( n -- 0 | n n )` stack effect is entirely honest: it really does leave a different number of values depending on what it finds.

`PICK` generalizes `DUP` and `OVER` to reach deeper without requiring a chain of `ROT`s. `2 PICK` reaches the third value from the top—the exact same place `ROT` would bring up—but *copies* it rather than moving it:

```forth
10 20 30  2 PICK .    \ [10, 20, 30, 10] then prints 10, leaving [10, 20, 30]
```

`PICK` does no bounds checking on its own argument. Asking for a value
deeper than the stack actually holds reads whatever memory happens to
sit past it — not a crash, but not meaningful data either. 

###### Where You Are Now

That is the entire foundation, and it is worth stating compactly before building anything on top of it:

1. **Dictionary Execution:** A Forth program consists of words separated by spaces, running on a simple rule: *read the next word, look it up in the dictionary, and run it.*

2. **The Stack:** Words pass values to each other through a single shared pile. Numbers push values onto it, while other words pop what they need and push their results.

3. **Postfix Order:** Ingredients always come before the action—`5 3 +`, never `5 + 3`.

4. **Explicit Output:** Nothing prints automatically; `.` is how you ask the system to display a value.

5. **Stack Notation:** `( before -- after )` records a word's effect on the stack, with the top of the stack always positioned on the right.

Everything in the rest of this document is simply those five mechanics applied to progressively more interesting problems. If any of them still feels shaky, the exercises below are the place to fix that—they are well worth a few minutes at the keyboard now rather than later.

### Summary

- **Core Concepts:** Words and the dictionary, the stack, postfix notation (ingredients first, action last), and the `( before -- after )` stack-effect notation.

- **Forth Words:** `.`, `+`, `-`, `DUP`, `SWAP`, `DROP`, `OVER`, `ROT`, `2DUP`, `2DROP`, `?DUP`, and `PICK`.

### Exercises

1. Spend a few minutes just pushing numbers and printing them back.
   Push three numbers, then type `.` three times and watch them come
   off in the opposite order to the one you pushed them in. Then try
   `10 20 30 DROP . .` and predict what you'll see before you press
   Enter.

2. Work out on paper what `7 2 - 3 -` leaves, then check it. Now work
   out `7 2 3 - -` — the same four tokens in a different order — and
   check that too. They are not the same, and the reason is entirely
   the operand-order rule above.

3. Type `5 3 + .`, and then, on the next line, type just `.` again.
   There's nothing left on the stack for it to print, so `.` prints
   whatever nonsense number happens to be sitting just past the bottom
   of the stack — and *then* Forth notices what you did and answers
   `STACK?`. The check happens once the word has finished, not before
   it starts, which is why you see the nonsense number at all. It isn't
   a crash, and it doesn't lose any words you've defined; it just
   empties the stack and hands you a fresh prompt. Seeing that once
   now, deliberately, is much nicer than meeting it by accident later.
   ([Section 3](#3-understanding-system-feedback--errors) covers the
   error messages properly.)

4. `ROT` is the one word in the second table above whose effect is hard
   to hold in your head. Push `1 2 3`, run `ROT`, then print all three
   and check the result against the `( a b c -- b c a )` in the table.
   Now try `ROT ROT ROT` on a fresh `1 2 3` — three rotations of three
   values should bring you back exactly where you started. Confirm that
   it does.

5. Some Forths have a word `-ROT`, which moves the *top* value down to
   third place — `( a b c -- c a b )` — the opposite direction to
   `ROT`. This Forth doesn't. Using the previous exercise, work out
   which short sequence of the words you already have gives exactly
   that effect, and check it. (You do not need anything but `ROT`.)

---

## 2. Defining Your Own Words

Here is the part BASIC has no real equivalent for. In BASIC, you write a program, and the language itself remains fixed while you use it. In Forth, defining a word **extends the language**—your new word becomes just as usable as `+` or `DUP`, completely indistinguishable in kind.

```forth
: DOUBLE  DUP + ;
```

Reading this from left to right:

1. `:` is the word that starts a definition.

2. Immediately following it (separated by a space) is **the name** of the new word (`DOUBLE`).

3. The **body** consists of the sequence of already-existing words the new definition is made of (`DUP +`).

4. `;` ends the definition and hands you back the ordinary prompt.

That is the entire act of adding a word. You can confirm it happened by checking the dictionary directly:

```forth
VLIST
```

`VLIST` prints `DOUBLE` first—as the newest entry—before continuing through every word the system already knew. As covered previously, `DOUBLE` is a genuine, first-class member of the dictionary, sitting right alongside `+` and `DUP`.

### The Crucial Role of Spaces

**Every space in a definition is required syntax, not tidy formatting.** Because Forth splits everything on whitespace, a missing space silently glues two distinct words into a single unrecognized token, and the interpreter has no way to distinguish that from a genuine typo.

In a fixed-width terminal font, a single missing space is easy to overlook. `: DOUBLE DUP + ;` requires a space in **every** one of these four positions (marked with `·` here just to make them visible—do not type the dots):

```
:·DOUBLE·DUP·+·;
```

Typing `:DOUBLE` without a space after the colon causes the interpreter to read it as a single, unknown word. Likewise, gluing `DUP+` together causes a lookup failure. If a `?` appears immediately after defining a word, check your spacing first before suspecting the logic of the definition itself.

### Compiling vs. Executing

Nothing inside the definition has *run* yet—you have only taught Forth a new word. `DUP` did not duplicate anything, and `+` did not add anything; both were merely written down as part of what `DOUBLE` means. This distinction is the whole point of the `:` operator, and it is why you can safely put a word inside a definition that would be a disaster to type directly at the prompt.

You can verify this with a word that is immediately obvious when run. Typing `5 .` at the prompt prints `5` right away. But if you write:

```forth
: SHOW  . ;
```

prints nothing when you type it. The `.` in there was recorded, not
performed. It only prints when you later run `SHOW` yourself:

```forth
7 SHOW      \ prints 7
```

Keep whole definitions on one line, by the way. Everything from `:` to
`;` is best typed and entered together — that's how every example in
this document is written, and it avoids any question about what the
machine is doing between the two halves.

Now use `DOUBLE`:

```forth
4 DOUBLE .   \ prints 8
```

Here is what happens under the hood:

1. `4` is pushed (`[4]`).

2. `DOUBLE` is looked up, found, and run—which means running its inner body in order: `DUP` (`[4, 4]`), then `+` (`[8]`).

3. `.` prints the `8` and clears the stack.

Notice that `DOUBLE`'s stack effect works out to `( n -- n*2 )`. Nowhere did you explicitly declare that; it simply falls out of combining `DUP` `( n -- n n )` and `+` `( a b -- a+b )` end to end. Working out a word's stack effect by tracing its parts in order is a habit worth starting now, as it lets you verify a definition without running it.

### Building Larger Words from Smaller Pieces

A slightly bigger example puts that habit to work: a word that quadruples a number, built directly out of the word that doubles one:

```forth
: DOUBLE     DUP + ;
: QUADRUPLE  DOUBLE DOUBLE ;

3 QUADRUPLE .   \ prints 12
```

- `QUADRUPLE` is defined *using* `DOUBLE`. A definition may use any word that exists at the moment it is compiled, including one you wrote seconds earlier.

- Running `3 QUADRUPLE` pushes `3` (`[3]`), runs `QUADRUPLE`, which invokes `DOUBLE` twice: `[3]` → `[6]` → `[12]`.

`QUADRUPLE` never mentions the stack, arithmetic, or how `DOUBLE` works internally; it simply names a sequence of existing words. This is the normal shape of Forth programming: small, easily verifiable words combined into larger ones.

#### The Order of Definitions Matters

`QUADRUPLE`'s definition mentions `DOUBLE`, and `:` compiles definitions by looking each word up in the dictionary **as it reads it**. If `DOUBLE` does not exist yet, the lookup fails immediately and you receive a `DOUBLE ?` error right while typing. **Always define smaller pieces first and build upward.**

Conversely, once `QUADRUPLE` is compiled, it holds a reference to the `DOUBLE` that existed at that moment. Redefining `DOUBLE` afterward changes what you get when you type `DOUBLE` at the prompt, but leaves `QUADRUPLE` running the original version—a useful consequence of newest-first dictionary searching.

### Interpreting vs. Compiling: Why `;` Is Special

Forth handles identical inputs in two completely different ways depending on its internal mode, tracked by a flag called **`STATE`**:

- **Interpreting:** Run each word as it is read (the default prompt behavior).

- **Compiling:** Record each word as part of a definition under construction. `:` switches `STATE` to compiling; `;` switches it back.

This raises a vital question: *if everything between `:` and `;` gets recorded rather than run, how does `;` ever execute?*

It cannot, under the ordinary rule. If `;` were recorded like everything else, the definition would never close and you would compile forever. Therefore, `;` is exempt. It runs the instant it is read—even while compiling is active—and flips `STATE` back before the interpreter reads the next word. Words carrying this exemption are called **IMMEDIATE**.

`;` is not alone: `IF`, `ELSE`, `THEN`, `DO`, `LOOP`, `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `LEAVE`, `EXIT`, `."`, and `S"` are all immediate as well. When you reach control structures and loops, this explains how they work: words like `IF` do not get compiled into your definition to run later; they run *while you are typing*, shaping the code being built around them.

### Marking Your Own Words IMMEDIATE

You can make your own words immediate using the **`IMMEDIATE`** command, which modifies the word you defined most recently (the one whose `;` you just typed):

```forth
: FOO  42 ; IMMEDIATE
```

Now watch how behavior changes:

```forth
: BAR  FOO ;      \ prints nothing, but pushes 42 -- FOO RAN, here, now
BAR               \ does nothing at all: BAR's body is empty
```

Ordinarily, `: BAR FOO ;` would record a call to `FOO` to run later. Because `FOO` is immediate, it runs on the spot while `BAR` is being built, pushing `42` onto the stack right then and leaving `BAR` completely empty.

This is the whole difference between control words like `IF` and ordinary math words like `+`. Because `IMMEDIATE` always targets the newest dictionary entry, it must always be placed on the same line immediately following the `;` it applies to.

### Indirect Calls: `'` and `EXECUTE`

Every word encountered so far is called by typing its name directly. The tick mark (**`'`**) and **`EXECUTE`** allow a program to call a word whose name or identity is only known dynamically:

```forth
: DOUBLE  DUP + ;
' DOUBLE EXECUTE     \ runs DOUBLE, ( -- xt ) then ( xt -- ) →
                     \ leaves DOUBLE's own result, just like just
                     \ typing DOUBLE would have
```

- **`'` (tick):** Looks up a word in the dictionary without running it, pushing a single identifier called an **`xt`** (execution token) onto the stack.

- **`EXECUTE`:** Takes an `xt` off the stack and calls whatever word it represents.

Splitting finding and calling into two separate steps allows you to store word identities in variables, pass functions as arguments, or decide at runtime which routine to run.

### Summary

- **Extending the Language:** Defining new words grows the vocabulary so they are indistinguishable from built-in primitives.

- **Syntax Rule:** Strict whitespace is required around every token inside a definition.

- **State & Immediate Words:** `:` compiles words rather than running them, while `IMMEDIATE` words execute immediately during compilation to shape code.

- **Execution Tokens:** `'` (tick) and `EXECUTE` enable indirect, dynamic function calls via execution tokens (`xt`).

- **Key Words:** `:`, `;`, `IMMEDIATE`, `'`, `EXECUTE`.

### Exercises

1. Type `: QUADRUPLE DOUBLE DOUBLE ;` on a machine that has just been
   switched on, before defining `DOUBLE` at all. Note *when* the error
   appears — while you are still defining `QUADRUPLE`, not later when
   you try to run it — and note which word it names.

2. Deliberately break the spacing rule three different ways:
   `:DOUBLE DUP + ;`, then `: DOUBLE DUP+ ;`, then `: DOUBLE DUP + ;`
   with no space before the `;`. Each fails, and each names a different
   made-up word back at you. Getting used to reading that name is the
   fastest way to fix a real typo later.

3. Define `DOUBLE` and then `QUADRUPLE` in the correct order, and check
   `3 QUADRUPLE .` prints 12. Now *redefine* `DOUBLE` to triple its
   input instead: `: DOUBLE DUP DUP + + ;`. Predict what `3 DOUBLE .`
   and `3 QUADRUPLE .` each print now, then check. One of them changed
   and one didn't, for the reason given just above.

4. Build on the `FOO` example: with `: FOO 42 ; IMMEDIATE` still in
   place, type `: BAZ FOO FOO ;`. How many values are on the stack when
   you have finished typing that line, and what does running `BAZ`
   afterwards do? Check both.

5. `' DOUBLE EXECUTE` and plain `DOUBLE` do the same thing to the same
   input. Confirm that with `4` on the stack, both ways. Then try
   `' DOUBLE .` on its own — you'll print the execution token itself,
   which is just an ordinary number like any other.

## 3. Understanding System Feedback & Errors

What happens if you press **Enter** on a word that doesn't exist? A typo like `5 BRODER` instead of `5 BORDER` prints the unrecognized word followed by `?`, then drops you straight back to a fresh prompt:

![The word "BRODER ?" printed after typing an unrecognized word](images/typo_error.png)

```forth
5 BRODER
BRODER ?
```

This is the first thing to check whenever a `?` appears unexpectedly: read the exact text printed before it. Typos are often caused by a dropped space that silently glues two distinct words together, and printing the offending token makes that immediately obvious rather than leaving you guessing.

When a line runs successfully, **`OK`** prints on its own line, ensuring that every entered line receives visible confirmation rather than silence.

A second kind of mistake—such as popping from an empty stack or pushing past its reserved space (like executing `DROP` on an empty stack)—prints **`STACK?`** and resets both stacks to empty rather than leaving them in a corrupted state. Like the unrecognized-word prompt, this is a blunt, whole-line reset. *(See 
[Error handling: THROW and CATCH](#14-error-handling-throw-and-catch)
for a way to intercept an error like this yourself, from inside your
own program, instead of always falling back to this default reset.

### Seeing what words exist: `VLIST`

The other half of "was that word really a typo?" is being able to look.
`VLIST ( -- )` prints the name of every word the dictionary currently
holds:

```forth
: DOUBLE  DUP + ;
: TRIPLE  DUP DUP + + ;
VLIST
```

`VLIST` prints `TRIPLE`, then `DOUBLE`, and continues backward through every built-in word all the way to the oldest definition. Names are separated by single spaces and wrap across the screen using the same `EMIT` mechanism used for general printing. Expect several screens of output.

Because the dictionary is searched newest-first, `VLIST` follows that exact same lookup chain out loud. Your own definitions appear first, and any redefined name appears twice (with the active version preceding the shadowed one).

- **`VLIST`**: Prints everything to the screen to answer prompt questions like *"does this word exist and is it spelled right?"*

- **`LLIST`**: Walks the same chain but stops at the built-in words, sending its output to a physical printer to list *your program*.

### Fixing a typo after you've already pressed Enter: `LIST-DEFS` and `RECALL`

Everything above fixes a mistake *before* you press Enter — inserting,
deleting, moving the cursor. But what about a typo you don't notice
until afterwards? Say you define a word, use it, and only then spot
the bug:

```forth
: SQURE  DUP * ;
5 SQURE .    \ prints 25 -- it works, the name is just misspelled
```

`SQURE` runs fine; nothing about the typo stops it. The problem only
shows up later, when you (or someone reading your program) expects a
word called `SQUARE` and it isn't there. Retyping the whole definition
by hand works, but for anything longer than one line, that's tedious
and error-prone in its own right. `LIST-DEFS ( -- )` and
`RECALL ( n -- )` exist for exactly this: they let you pull a
definition you already entered back onto the input line, so you can
fix it with the same cursor-left/Delete editing from earlier in this
section instead of retyping it from scratch.

`LIST-DEFS` prints every colon definition you've entered so far this
session — whether typed live at the prompt or brought in with
`LOAD-TEXT` (see [section 12](#12-saving-and-loading-your-work)) —
numbered from 0, oldest first, each with a short preview of its source:

```forth
LIST-DEFS
```

```
0: : SQURE  DUP * ;
```

`RECALL` takes one of those numbers and copies that definition's
*entire* source — not just the preview — back onto the input line,
cursor at the end, ready to edit:

```forth
0 RECALL
```

The input line now reads `: SQURE  DUP * ;` exactly as you first typed
it. From here it's ordinary editing: move the cursor onto `SQURE`,
fix it to `SQUARE`, and press Enter. The corrected line runs — defining
`SQUARE`, which now shadows nothing since `SQURE` was never right in
the first place — and is also appended to the end of the workspace, so
a later `LIST-DEFS` shows it too.

#### Important Limits to Keep in Mind

- `RECALL` only handles complete `:`...`;` definitions, not arbitrary single lines typed outside a definition. It also cannot recall definitions longer than 128 characters or reach past the first 16 definitions found by `LIST-DEFS`.

- Recalling and re-entering a definition does not erase the old, mistyped version; it simply adds the corrected version after it in the workspace. Running `LIST-DEFS` again will show both `SQURE` and `SQUARE`, which is entirely harmless since the dictionary resolves names on a newest-wins basis.

### Summary

- **Editing Model:** Editing happens before reading; no matter how much you move the cursor around, Forth only sees the finished line upon pressing Enter.

- **Feedback Signals:** Lines provide visible feedback—`OK` on success, an unrecognized word followed by `?` on typos, and `STACK?` on stack underflow/overflow resets.

- **Dictionary Inspection & Recovery:** Use `VLIST` to inspect available words, `LIST-DEFS` to review past definitions, and `RECALL` to pull and fix definitions without retyping them from scratch.

- **Key Words:** `VLIST`, `LIST-DEFS`, `RECALL`.

### Exercises

1. Make each of the three messages appear on purpose. `5 BRODER` for
   the unrecognised-word `?`; `DROP` on an empty stack for `STACK?`;
   and any correct line at all for `OK`. Read what is printed *before*
   the `?` in the first case — that name is the whole diagnostic.

2. Define two words of your own and run `VLIST`. Your two appear first.
   Keep reading and find the point where your definitions stop and the
   built-in words begin — that boundary is where `LLIST` in section 15
   stops, and `VLIST` doesn't.

3. Redefine one of those two words, then run `VLIST` again. The name
   now appears twice: the live one first and the shadowed one further
   down. Confirm that, and then check that typing the name gets you the
   newer definition — which is the newest-first search from section 1,
   made visible.

4. Repeat the `SQURE`/`SQUARE` example above yourself: define `SQURE`,
   run `LIST-DEFS`, `RECALL` it, fix the name, and press Enter. Then
   run `LIST-DEFS` one more time and confirm both the old and the
   corrected definition are listed — the honest limit described above,
   seen directly rather than just taken on faith.

---

## 4. Numbers

This section covers every kind of number the system understands: whole
numbers and decimal numbers, the two separate stacks they occupy, the
words that convert between them, and the numeric operators — signed
arithmetic, bitwise logic, and randomness — built on top of them.

#### Whole Numbers

Whole numbers — `5`, `-12`, `0` — behave exactly as expected, negatives
included, via a leading `-`.

#### Decimal Numbers

2068-Leap-Forth also supports **decimal numbers**, written with a `.`:

```forth
3.5 2.5 F+ F.       \ prints 6.0000
6.0 2.5 F- F.       \ prints 3.5000
2.0 3.0 F* F.       \ prints 6.0000
1.0 4.0 F/ F.       \ prints 0.2500
```

- **Familiar Shape:** Structurally these are exactly the same shape as
  `5 3 + .` from section 1 — ingredients first, action last, then a
  word to print the result. Only the spellings changed.

### Two Stacks, and Why

A number with a `.` in it does **not** go on the stack used so far. It
goes on a second, entirely separate stack of its own.

- **Separate Storage:** A decimal number and a whole number can never
  sit on top of "the stack" at the same time, because they aren't on
  the same stack.

- **Dedicated Words:** This is why decimal arithmetic needs its own
  words — `F+ F- F* F/`, where the `F` prefix is the standard Forth
  convention for "floating-point" — rather than reusing the plain
  `+`/`-` from section 1. `+` looks at the whole-number stack; `F+`
  looks at the decimal one. Neither can ever see the other's values.

**Tracing the Separation:**

```
you type   whole-number stack   decimal stack
--------   ------------------   -------------
5          [5]                  []
3.5        [5]                  [3.5]
2.5        [5]                  [3.5, 2.5]
F+         [5]                  [6.0]
F.         [5]                  []              -- prints 6.0000
.          []                   []              -- prints 5
```

The `5` sits untouched through all of it. `F+` and `F.` have no way to
reach it even in principle, and the `.` at the end finds it exactly
where it was left.

- **Silent Stack Mismatches:** Using the wrong stack's word is usually
  not an error that gets reported. Typing `3.5 2.5 +` adds nothing —
  the two decimals are on the float stack, and `+` reaches for two
  whole numbers that were never placed there. The result is `STACK?`
  if the whole-number stack was empty, or a silently wrong answer
  computed from whatever *was* on it. When a calculation produces an
  unexpected result, checking that every word in it carries the
  correct `F` — or correctly lacks one — is the first thing to verify.

Plain integer `*` and `/` exist too (see the table in
[section 4's numeric words](#a-few-more-useful-numeric-words) below) —
they live on the whole-number stack, exactly like `+`/`-`, and are a
completely separate pair of words from `F*`/`F/` here. Use `*` and `/`
when both the ingredients and the answer are whole numbers; reach for
`F*`/`F/` only once a `.` (decimal point) is actually involved
somewhere in the calculation.

- **`F.` Precision:** `F.` prints a decimal result with exactly 4
  digits after the point (`6.0` prints as `"6.0000"`, not `"6"`), and
  rounds toward zero rather than to the nearest digit — small
  differences near the 4th digit can differ slightly from what a
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

#### Square Roots and Trigonometry

`FSQRT` is the decimal counterpart to whole-number `SQRT` (below):

```forth
9.0 FSQRT F.        \ prints 3.0000
2.0 FSQRT F.        \ prints 1.4141 -- an approximation, the standard
                    \ result for the square root of a number that
                    \ isn't a perfect square
```

Trigonometry follows the same pattern. `PI` pushes a decimal
approximation of π, and `SIN`/`COS` take an angle in radians:

```forth
PI F.               \ prints 3.1416
1.0 SIN F.          \ prints 0.8408
2.0 COS F.          \ prints -0.4156
```

- **Accuracy:** `SIN` and `COS` are computed from a lookup table with
  linear interpolation between entries, giving about 3-4 decimal
  digits of accuracy — matching the precision `F.` itself displays.

- **Valid Range:** Large angles are not reliable: beyond roughly ±1570
  radians (a couple hundred full turns), the internal range-reduction
  step no longer guarantees a correct result. Ordinary trigonometric
  usage stays comfortably inside that range.

Two more words convert between the two common angle units: `RAD` and
`DEG`, for situations where degrees are the more natural unit — a
compass heading, say:

```forth
90.0 RAD F.       \ prints 1.5707 -- 90 degrees in radians
PI 2.0 F/ DEG F.  \ prints 89.9960 -- half of PI back to degrees
                  \ (not exactly 90.0 -- the same small
                  \ approximation error every decimal calculation
                  \ here carries)
```

### Crossing Between the Two Stacks

Sooner or later, a value ends up on the wrong stack. Typing a number
with or without a `.` decides *where it starts*; `S>F` and `F>S` move
an already-computed value across afterward.

Their stack effects need a moment's explanation, since they are the
first words in this document that touch both stacks at once, and the
usual one-line notation cannot express that. Two groups are written
instead — the first for the whole-number stack, the second for the
decimal one:

| Word     | Whole-number stack | Decimal stack | What it does                             |
| -------- | ------------------ | ------------- | ---------------------------------------- |
| `S>F`    | `( n -- )`         | `( -- f )`    | Whole number to decimal (exact)          |
| `F>S`    | `( -- n )`         | `( f -- )`    | Decimal to whole number (see below)      |
| `FROUND` | —                  | `( f -- f' )` | Round to the nearest whole decimal value |

- **Reading `S>F`:** Takes a value off the whole-number stack, leaves
  one on the decimal stack. The name states the same thing — `S` for
  the standard Forth name for the ordinary stack, `>` for "to", `F`
  for float.

- **Reading `F>S`:** Runs the other direction.

- **`FROUND`:** Never leaves the decimal stack at all, which is why it
  has an ordinary single-group stack effect.

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

- **`F>S` Rounds Downward, Not Toward Zero:** `F>S` might be expected
  to simply discard the fractional part and hand back the whole-number
  part — that is what "convert to an integer" usually means elsewhere.
  It does not. It always rounds *downward*, toward negative infinity.
  For positive values those are the same operation, so `3.7 F>S` gives
  `3` either way. For negative values they diverge: `-0.5 F>S` gives
  `-1`, not `0`, because `-1` is the whole number below `-0.5`.

- **Getting Ordinary Rounding:** If ordinary rounding is what's wanted,
  `FROUND` first and `F>S` second achieves it, as the third line above
  shows. The order matters, because the two words perform different
  jobs: `FROUND` decides which whole value is *nearest*, and `F>S`
  merely moves the result to the other stack.

### A Few More Useful Numeric Words

A handful of ordinary whole-number words round out the basics:

| Word     | Stack effect         | What it does                    |
| -------- | -------------------- | -------------------------------- |
| `1+`     | `( n -- n+1 )`       | Add one                         |
| `1-`     | `( n -- n-1 )`       | Subtract one                    |
| `NEGATE` | `( n -- -n )`        | Change the sign                 |
| `*`      | `( a b -- a*b )`     | Multiply                        |
| `/`      | `( a b -- a/b )`     | Divide, truncating toward zero  |
| `ABS`    | `( n -- \|n\| )`     | Absolute value                  |
| `SGN`    | `( n -- -1\|0\|1 )`  | Sign of `n`                     |
| `MOD`    | `( a b -- a-mod-b )` | Remainder of `a / b`            |
| `SQRT`   | `( n -- isqrt(n) )`  | Integer square root, truncating |
| `MAX`    | `( a b -- max )`     | The larger of two values        |
| `MIN`    | `( a b -- min )`     | The smaller of two values       |

```forth
6 7 * .         \ prints 42
-17 5 / .       \ prints -3 -- truncates toward zero, not toward
                \ negative infinity (so -17 / 5 is -3, not -4)
-5 ABS .        \ prints 5
-8 SGN .        \ prints -1
5 5 - SGN .     \ prints 0
40 SGN .        \ prints 1 -- SGN only reports which side of zero
                \ a number is on, never its size
-17 5 MOD .     \ prints -2 -- the remainder takes the DIVIDEND's
                \ sign, not the divisor's (so -17 MOD 5 is -2, not 3)
16 SQRT .       \ prints 4
15 SQRT .       \ prints 3 -- truncated, not rounded: 15 isn't a
                \ perfect square, so this is the largest whole number
                \ whose square doesn't exceed it
```

- **Whole-Number Only:** Both `*` and `/` work only in whole numbers
  and give a whole-number answer — `7 2 /` is `3`, with the remainder
  discarded, not `3.5`.

- **Division by Zero:** Dividing by `0` does not raise an error; it
  quietly returns `0`, the same convention `MOD` above uses (both
  share the same underlying division).

Two more words shorten a common pattern rather than compute anything
new: `1+` and `1-`. `5 1+` does exactly what `5 1 +` does, in one word
instead of two:

```forth
5 1+ .          \ prints 6
5 1- .          \ prints 4
```

- **Why They Exist:** Adding or subtracting one is by far the most
  common arithmetic in real Forth code — stepping to the next memory
  slot, nudging a counter, adjusting an off-by-one — so it earns its
  own word purely to keep those lines short. [The next
  section](#5-reading-and-writing-memory-directly) introduces memory
  addresses, where this exact shorthand appears constantly.

The next word changes a value's sign directly: `NEGATE`, which
section 1's `-` can already do the long way round:

```forth
3 NEGATE .      \ prints -3
-3 NEGATE .     \ prints 3
0 NEGATE .      \ prints 0
```

- **`NEGATE` vs. `INVERT`:** Worth placing beside `INVERT` above, since
  the two look superficially similar and are not the same operation.
  `0 NEGATE` is `0`; `0 INVERT` is `-1`. `NEGATE` asks "what is the
  same distance from zero the other way?" and `INVERT` asks "what if
  every single bit were flipped?" — questions with neighboring answers
  (`INVERT` gives exactly one less than `NEGATE` for any input) but
  entirely different meanings.

Two more words each take two values and keep one: `MAX` and `MIN`:

```forth
5 3 MAX .       \ prints 5
5 3 MIN .       \ prints 3
-1 3 MAX .      \ prints 3
-5 -1 MIN .     \ prints -5
```

- **Signed Comparison:** The key property is that `MAX`/`MIN` compare
  the way values compare on paper, with negative numbers genuinely
  smaller than positive ones — the same convention `<` and `>` use in
  [the next-but-one section](#6-comparisons-and-truefalse), and the
  same one that makes `0 INVERT` print as `-1`. This matters because a
  comparison that ignored sign would rank `-32768` *above* `32767` —
  those two have the largest and second-largest bit patterns
  respectively — and it does not:

  ```forth
  32767 -32768 MAX .   \ prints 32767 -- the positive one, correctly
  ```

- **Order-Independent:** Unlike `-` and `<`, neither `MAX` nor `MIN`
  cares which order the two values are given in: `5 3 MAX` and
  `3 5 MAX` both give `5` — the same relaxed category as `+`, a
  contrast with section 1's own warnings about operand order.

The last two words in this table produce randomness rather than
computing from an input: `RND` and `RANDOMIZE`, which together give a
pseudo-random whole number:

```forth
100 RND .          \ prints something in 0..99
12345 RANDOMIZE    \ reseed with a fixed number, for a reproducible
                   \ sequence -- useful for testing
100 RND .          \ always the same value, right after that
                   \ specific RANDOMIZE
0 RANDOMIZE        \ back to unpredictable -- reseeds from a
                   \ hardware timing source on the next RND
```

- **Exclusive Upper Bound:** `RND`'s upper bound is exclusive:
  `100 RND` produces `0` through `99` and never `100` itself, matching
  the "n possible results" convention many BASICs use for their own
  `RND(n)`.

### Bitwise and Logical Operators

These act on all 16 bits of a value at once — real bit manipulation,
not the boolean `=`/`<`/`>` results covered in
[Comparisons and true/false](#6-comparisons-and-truefalse):

| Word     | Stack effect         | What it does                           |
| -------- | -------------------- | -------------------------------------- |
| `AND`    | `( a b -- a AND b )` | Bitwise AND                            |
| `OR`     | `( a b -- a OR b )`  | Bitwise OR                             |
| `XOR`    | `( a b -- a XOR b )` | Bitwise exclusive-OR                   |
| `INVERT` | `( a -- NOT a )`     | Bitwise complement — every bit flipped |

```forth
15 240 OR .     \ prints 255 -- 15 is 00001111, 240 is 11110000;
                \ OR-ed together, every one of those 8 bits is set
10 12 AND .     \ prints 8 -- 10 is 1010, 12 is 1100; AND keeps only
                \ the bits both share (1000)
10 12 XOR .     \ prints 6 -- 1010 XOR 1100 keeps only the bits that
                \ DIFFER between the two (0110); compare with the
                \ AND line above, same two inputs, different answer
0 INVERT .      \ prints -1 -- flipping every bit of 0 gives all
                \ ones, which prints as -1 (this project's own
                \ integers are signed, two's-complement, like most
                \ Forths)
```

- **Not Called `NOT`:** `INVERT` is deliberately not named `NOT`. This
  project's `0=` (next section) already performs *logical* negation of
  a true/false flag, and a second, differently-behaved word spelled
  `NOT` sitting beside it would invite confusion rather than add
  convenience. `INVERT` flips every bit; `0=` cares only whether its
  input was exactly zero.

### Summary

- **Core Concepts:** Whole numbers and decimal numbers, and the two
  separate stacks they live on. Signed 16-bit arithmetic. Bitwise
  operations on all 16 bits at once.

- **Forth Words:** `F+`, `F-`, `F*`, `F/`, `F.`, `FSQRT`, `PI`, `SIN`,
  `COS`, `RAD`, `DEG`, `S>F`, `F>S`, `FROUND`, `1+`, `1-`, `NEGATE`,
  `*`, `/`, `ABS`, `SGN`, `MOD`, `SQRT`, `MAX`, `MIN`, `RND`,
  `RANDOMIZE`, `AND`, `OR`, `XOR`, `INVERT`.

### Exercises

1. There is a limit to the size of whole number this Forth can hold,
   and it does not warn you when you reach it. A whole number occupies
   16 bits, which gives 65536 different values; used as signed numbers
   those run from `-32768` up to `32767`, and the two ends *join up*.
   Try
   
   ```forth
   32767 1+ .
   ```
   
   You get `-32768`. Counting up past the largest positive value wraps
   straight round to the most negative one, exactly as a car odometer
   rolls over. Try `32768 .` as well, and see what a number that can't
   fit in the range does when you merely type it.

2. The same ceiling causes most trouble with `*`, because it is easy to
   multiply two perfectly reasonable numbers and get a product that
   doesn't fit. Predict the answer to `256 256 *`, then run
   
   ```forth
   256 256 * .
   ```
   
   The true answer is 65536, which needs 17 bits. What you get is the
   bottom 16 of them. Nothing is reported; the number is simply wrong,
   which is why it is worth knowing about now rather than discovering
   inside a program.

3. `SGN` reports only which side of zero a number is on. Predict the
   three results, then check:
   
   ```forth
   -17 SGN .
   0 SGN .
   99 SGN .
   ```

4. `XOR` sets a bit where its two inputs *differ*. Write out 10 and 12
   as four bits each on paper, work out the result bit by bit, and only
   then run `10 12 XOR .` to check. (Compare it with the `10 12 AND .`
   above, which keeps the bits they share.)

5. `F-` is the one decimal operator without a worked example above.
   Work out what `5.5 2.25 F- F.` should print — remembering both the
   operand-order rule from section 1 and that `F.` always shows exactly
   four digits after the point — then run it.

6. Try `3.5 2.5 +` and then `.` on the next line. Neither decimal ever
   reaches the whole-number stack, so `+` reaches for two values that
   were never put there. This is the wrong-stack mistake described
   above, and it is worth causing on purpose once so you recognise the
   symptom.

---

## 5. Reading and writing memory directly

Everything so far has lived on the stack, which is a fine place for a
value about to be used and a poor one for a value meant to be kept. The
stack is a queue of things in flight; it isn't storage. This section
covers the machine's actual storage: raw memory, the words that read
and write it, named storage built on top of it, arrays, and strings.

#### The Memory Model

The picture to hold: the machine's memory is one very long street of
numbered slots — 65,536 of them, numbered 0 to 65535. That number is a
slot's **address**, exactly like a house number.

- **One Byte per Slot:** Each slot holds one byte. Two neighboring
  slots together hold one of the whole numbers already in use on the
  stack, since one byte on its own can only count from 0 to 255, and
  that isn't enough.

#### Fetch and Store: `@` and `!`

Two words reach into that street:

| Word                     | Stack effect    | What it does                    |
| ------------------------ | --------------- | ------------------------------- |
| `@` (pronounced "fetch") | `( addr -- n )` | Read the value stored at `addr` |
| `!` (pronounced "store") | `( n addr -- )` | Write `n` to `addr`             |

- **Operand Order for `!`:** The *value* goes on the stack first, then
  the *address*. Read it as "store `n` at `addr`," which matches the
  order the words appear when writing `n addr !`. One image helps:
  posting a parcel. The parcel is the value, and the address is
  written on top of it — contents first, address last, then handed
  over.

#### `VARIABLE` and `CONSTANT`

That's a much lower-level tool than BASIC's variables — no `DIM`, no
named storage, just addresses. `VARIABLE` builds named storage out of
exactly this:

```forth
VARIABLE SCORE
42 SCORE !
SCORE @ .        \ prints 42
```

- **What `VARIABLE` Creates:** `VARIABLE SCORE` creates a new word,
  `SCORE`, that pushes the address of its own private two-byte storage
  cell every time it runs — the cell starting out zero. The address
  never needs to be seen or remembered as a number; writing `SCORE`
  gets it, and `@`/`!` work on it exactly as on any other address. Same
  shape as BASIC's `LET SCORE = 42` and `PRINT SCORE`, just spelled
  with explicit `@`/`!` instead of an assignment operator.

`CONSTANT` is `VARIABLE`'s simpler sibling. It fixes a value
permanently at the moment it's defined: no cell, no way to change it
afterward.

```forth
100 CONSTANT MAXHEALTH
MAXHEALTH .      \ prints 100, every time, forever
```

- **The Real Difference:** Worth stating plainly, because the two look
  similar when defined and behave quite differently when used.
  `VARIABLE SCORE` gives a word that pushes an **address** — the value
  itself is one `@` away. `100 CONSTANT MAXHEALTH` gives a word that
  pushes the **value** directly, so no `@` is involved and no cell to
  fetch from:

  ```forth
  SCORE @ .        \ the @ is required -- SCORE gave an address
  MAXHEALTH .      \ no @ -- MAXHEALTH gave the number itself
  ```

- **A Common Mistake:** A stray or missing `@` between these two is a
  common early error, and it doesn't announce itself: `SCORE .` will
  happily print a number, just not the one intended — it prints where
  the cell *is*, not what's in it.

### Bytes: `C@` and `C!`

`@` and `!` always work on a full two-byte cell, matching the size of
the numbers already in use on the stack. `C@` and `C!` do the same job
one *byte* at a time — the natural pair for anything genuinely
byte-sized, text especially:

| Word | Stack effect       | What it does             |
| ---- | ------------------ | ------------------------ |
| `C@` | `( addr -- byte )` | Read one byte at `addr`  |
| `C!` | `( byte addr -- )` | Write one byte to `addr` |

To see the two-slots-per-number arrangement directly, store a number
whose two halves are easy to tell apart. 258 is 256 + 2, so its two
bytes are 1 and 2:

```forth
VARIABLE V
258 V !
V @ .           \ prints 258 -- the whole two-byte value
V C@ .          \ prints 2   -- just the first byte
V 1 + C@ .      \ prints 1   -- just the second byte
```

- **Addresses Are Ordinary Numbers:** `V 1 +` reaches the next slot
  along: an address is an ordinary number, so ordinary `+` moves
  through memory. This idiom recurs constantly.

- **Byte Order:** The low half of the number is stored *first*, in the
  lower-numbered slot — this processor's own convention, and worth
  noting since it's easy to expect the halves the other way round.

There's no `CELLS`-style helper for single bytes (`CELLS` itself
appears under [Arrays](#arrays) next), because for bytes the offset and
the count are already the same number.

`FREE ( -- n )` reports how much room is left for defining new words,
useful before starting a large program — the same spirit as BASIC's
own `FREE`:

```forth
FREE .      \ prints how many bytes are left for new definitions
```

- **What `FREE` Measures:** Dictionary space specifically — room for
  new word definitions, not total system memory. The stacks, the
  screen, and the system's own working storage sit in separate
  fixed-size regions that never compete with what `FREE` reports.

### Arrays

`ARRAY` is `VARIABLE` scaled up: instead of a single storage cell, it
reserves however many are requested, all zeroed to start.

```forth
5 ARRAY SCORES
```

- **Indexing:** `SCORES` pushes the address of the FIRST cell, exactly
  as `VARIABLE` does. To reach any other element, its index — times the
  size of a cell — is added to that base address before using `@`/`!`.
  `CELLS` performs that multiplication:

  ```forth
  99 3 CELLS SCORES + !     \ store 99 in element 3
  3 CELLS SCORES + @ .      \ prints 99
  0 CELLS SCORES + @ .      \ prints 0 -- element 0 is untouched
  ```

- **No Dedicated Indexing Word:** `index CELLS name +` is the whole
  idiom, exactly as real Forth systems handle it — read as one phrase,
  "the address `CELLS` past `name`."

`CELLS` is just `( n -- n*2 )`, and it is easy to be tempted to skip
it. This is the memory street from earlier in this section again:
`SCORES` gives a plain **byte** address, and each element occupies
**two** of those byte slots.

- **The `CELLS` Trap:** Writing `3 SCORES +` walks three bytes along,
  not three elements, landing halfway into element 1 — reading and
  writing one byte from each of two different elements at once.
  Nothing raises an error; the result is simply a number that
  corresponds to nothing at all.

Element 0 lives in byte offsets 0 and 1, element 1 in offsets 2 and 3,
element 2 in 4 and 5, element 3 in 6 and 7:

```
SCORES             ->  byte offset 0  ->  element 0            (correct)
3 CELLS SCORES +   ->  byte offset 6  ->  element 3            (correct)
3 SCORES +         ->  byte offset 3  ->  the second half of
                                          element 1            (WRONG)
```

`CELLS` is exactly the `index * 2` conversion that turns "element 3"
into "six bytes along," and writing it every time costs nothing.

### Strings

Forth has no string *type* the way BASIC does. A string is two
ordinary numbers on the stack: an **address** and a **length**. `S"`
(pronounced "S-quote") makes one.

```forth
S" HELLO WORLD" TYPE     \ prints HELLO WORLD
```

- **What `S"` and `TYPE` Do:** `S" text"` pushes the address and length
  of `text`, printing nothing by itself. `TYPE` takes an address and a
  length and prints exactly that many characters. Every other string
  word in this document works on the same address/length pair, so once
  `S"` has produced one, anything here can consume it.

That "two ordinary numbers" description is literal, not a figure of
speech, and it explains most of what follows.

- **Nothing Marks a String as Special:** After `S" HELLO WORLD"` the
  stack holds exactly two values — an address, and the number 11 — and
  nothing anywhere marks them as a string. Typing `. .` at that point
  prints 11 and then some address, in ordinary decimal, as the plain
  numbers they are. Certain words simply agree to interpret the pair
  that way.

- **Why Two Arguments:** This is also why `TYPE` takes *two* arguments,
  and why nearly every string word in this section does too. There is
  no length hidden anywhere for them to look up; it travels alongside
  the address instead.

A literal from `S"` is a one-off: fine for a piece of text about to be
printed or measured, and no use at all for something meant to be kept
or changed later. `STRING` reserves a real, named, mutable slot for
text, just as `VARIABLE` does for a single number:

```forth
20 STRING NAME
```

`NAME` now pushes the address of a buffer holding up to 20 characters,
currently empty. Fill it with `PLACE`, which takes an address/length
pair — from `S"`, say — and a destination:

```forth
S" ADA" NAME PLACE
```

`NAME`'s buffer now holds `"ADA"`. To retrieve it as an address/length
pair, for `TYPE` or anything else, use `COUNT`:

```forth
NAME COUNT TYPE      \ prints ADA
```

`COUNT` is the one word here whose necessity isn't immediately obvious,
so it's worth explaining why it exists.

- **How a `STRING` Buffer Is Laid Out:** A `STRING` buffer doesn't
  store a bare address/length pair — it stores its length in a single
  **count byte** at the very front, followed by the characters
  themselves. `NAME` pushes the address of that count byte, not of the
  text. So the buffer made by `20 STRING NAME`, holding `"ADA"`, looks
  like this in the memory street from earlier in this section:

  ```
  offset:   0    1    2    3    4  ...  20
          [ 3 ][ A ][ D ][ A ][ ? ] ... [ ? ]
            ^     ^
            |     `-- the characters start here (NAME 1 +)
            `-- the count byte: how many characters (NAME)
  ```

- **What `COUNT` Bridges:** `COUNT ( caddr -- addr len )` is exactly
  the conversion between the two representations: given the buffer's
  address, it returns "the address one byte further along" and "the
  number found in the count byte" — precisely the pair `TYPE` wants.

That also explains a line appearing later in this document: `NAME 1 +`
appears in the [`ACCEPT`](#reading-a-whole-line-accept-and-input)
example and means "skip the count byte, take the text area." It's the
same `+` on the same kind of byte address used earlier in this section
to walk from one slot to the next.

If only the length of the stored text is needed, `LEN` reaches it
directly without producing the full pair `COUNT` gives — it simply
reads that count byte:

```forth
NAME LEN .            \ prints 3
```

`VAL` goes the other direction, turning a string into a number:

```forth
S" 1234" VAL .        \ prints 1234
S" -17" VAL .         \ prints -17
S" NOTANUMBER" VAL .  \ prints 0 -- not a valid number, no error,
                      \ just a safe default, the same convention
                      \ dividing by zero uses in this project
```

- **Fixed Maximum Size:** A `STRING` buffer's maximum size is fixed at
  creation — `20 STRING NAME` above never holds more than 20
  characters — the same limitation BASIC's own string variables carry.

### More String Words

A further set covers the everyday BASIC string operations
(`CHR$`/`STR$`/`UPPER$`/`LOWER$`/`LEFT$`/`RIGHT$`/`INSTR` and similar)
under Forth-standard names, all still working on the same
address/length pairs:

| Word     | Stack effect                                   | What it does                                     |
| -------- | ----------------------------------------------- | ------------------------------------------------ |
| `CHR`    | `( code -- addr len )`                         | A one-character string from a character code     |
| `STR`    | `( n -- addr len )`                            | A number, as a string                            |
| `UPPER`  | `( addr len -- addr len )`                     | Uppercase, in place                              |
| `LOWER`  | `( addr len -- addr len )`                     | Lowercase, in place                              |
| `LEFT`   | `( addr len n -- addr len' )`                  | The first `n` characters                         |
| `RIGHT`  | `( addr len n -- addr' len' )`                 | The last `n` characters                          |
| `SEARCH` | `( addr1 len1 addr2 len2 -- addr3 len3 flag )` | Find string 2 inside string 1                    |
| `CODE`   | `( addr len -- code )`                         | The character code of a string's first character |

```forth
65 CHR TYPE                  \ prints A
42 STR TYPE                  \ prints 42
S" ADA" UPPER TYPE           \ prints ADA (already uppercase, unchanged)
S" hello" UPPER TYPE         \ prints HELLO
S" HELLO" LOWER TYPE         \ prints hello
S" HELLO WORLD" 5 LEFT TYPE  \ prints HELLO
S" HELLO WORLD" 5 RIGHT TYPE \ prints WORLD
```

- **`LEFT`/`RIGHT` Copy Nothing:** Neither word copies anything.
  `LEFT`'s result keeps the same `addr` and reports a shorter `len`;
  `RIGHT`'s keeps the same `len` and reports a later `addr`. This
  follows directly from "a string is just an address and a length" —
  a substring is simply a different *view* of memory already held, so
  there's nothing to copy. If `n` is larger than the string, both
  clamp to the whole string rather than reading past its end.

- **`UPPER`/`LOWER` Write in Place:** These two are the exception in
  the other direction: they change text **in place**. Every other word
  here only reads its `(addr len)`; these write back into it. Typed at
  the prompt, they behave exactly as the examples above show, because
  a string typed in lives in ordinary writable memory. The exception
  is text living in the machine's permanent, unchangeable storage —
  text built into the ROM itself. A write there is simply discarded:
  not a crash, not an error, just no visible effect, since this
  hardware has no way to signal that a write didn't take. If `UPPER`
  ever appears to do nothing, this is the first thing to check.

`SEARCH` looks for the second string inside the first and reports
whether, and where, it found it.

- **A Precaution With Two Literals on One Line:** `SEARCH` needs two
  string literals at once, which calls for care: two `S"` literals
  typed on the *same line at the prompt* share one piece of scratch
  memory, so the second one's text lands on top of the first one's,
  producing a result computed from something other than what was
  typed. Inside a colon definition, each literal gets its own permanent
  copy, and the problem doesn't arise. One `S"` per line is fine to
  type directly; two or more belong in a definition. This is the only
  place in this document where that matters, but it matters silently,
  which is why it's worth knowing.

```forth
: FOUND?  S" HELLO WORLD" S" WORLD" SEARCH ;
FOUND? .          \ prints -1 (true) -- found
```

- **Reading `SEARCH`'s Three Results:** `SEARCH` returns more than a
  yes/no. `flag` is true if the second string turned up anywhere
  inside the first. When it did, `addr3 len3` is the **rest of the
  text starting at the match** — not just the matched part, and not
  the original string. For `"HELLO WORLD"` searched for `"WORLD"`, the
  match is at the end, so "the rest from the match onward" happens to
  be exactly `"WORLD"`; searching for `"LO"` instead would return
  `"LO WORLD"`. When the flag is false, `addr3 len3` is the original
  string, unchanged.

The flag is what gets branched on, and the pair underneath it is what
gets carried on to search or print from:

```forth
: SHOWREST  S" HELLO WORLD" S" WORLD" SEARCH DROP TYPE ;
SHOWREST          \ prints WORLD
```

- **Why the `DROP`:** `DROP` discards the flag, leaving the
  `(addr len)` pair for `TYPE` — a small illustration of why `DROP`
  from section 1 turns up so often in real code.

- **Two Edge Cases Handled Automatically:** An empty search string
  never matches, and a search string longer than the text being
  searched can't match either — neither case needs to be special-cased
  by the caller.

### Summary

- **Core Concepts:** Memory as a numbered street of byte-sized slots.
  Addresses are ordinary numbers, so ordinary arithmetic moves through
  memory. Cells are two bytes; bytes are one. Named storage built on
  top of raw addresses. A string is an address and a length, carried
  separately.

- **Forth Words:** `@`, `!`, `C@`, `C!`, `VARIABLE`, `CONSTANT`,
  `FREE`, `ARRAY`, `CELLS`, `S"`, `TYPE`, `STRING`, `PLACE`, `COUNT`,
  `LEN`, `VAL`, `CHR`, `STR`, `UPPER`, `LOWER`, `LEFT`, `RIGHT`,
  `SEARCH`, `CODE`.

### Exercises

1. `2DUP` and `2DROP` from section 1 were introduced with no example,
   and an address/length pair is exactly what they are for — the pair
   *is* the "top two values" they act on. Predict what each of these
   prints, then run them:
   
   ```forth
   S" HELLO" 2DUP TYPE TYPE
   S" HELLO" 2DUP TYPE 2DROP
   ```
   
   The first prints the same text twice from one literal, because
   `2DUP` copied the whole pair before the first `TYPE` ate it. The
   second prints it once and leaves the stack clean.

2. `CODE` gives you the character code of a string's first character.
   Check that
   
   ```forth
   S" A" CODE .
   S" A" DROP C@ .
   ```
   
   print the same number, and work out why: `DROP` throws away the
   length, leaving just the address, and `C@` reads the byte there.
   `CODE` is that pair of words in one.

3. `UPPER` and `LOWER` change text in place, which means you can send
   the same buffer through both. Set up a `STRING`, `PLACE` some mixed-
   case text into it, and then print it three times — as stored, after
   `UPPER`, and after `LOWER` — using `COUNT` each time to get the pair.
   Remember that both words hand back the pair they were given, so
   `NAME COUNT UPPER TYPE` works as one phrase.

4. This is the `CELLS` trap from above, made visible. 258 is stored as
   the two bytes 2 and 1, which makes a wrong read easy to spot:
   
   ```forth
   5 ARRAY SCORES
   258 1 CELLS SCORES + !
   258 2 CELLS SCORES + !
   1 CELLS SCORES + @ .
   3 SCORES + @ .
   ```
   
   The fourth line prints 258, correctly. The fifth forgets the
   `CELLS`, so it lands three *bytes* along instead of three elements,
   reads the top half of one element and the bottom half of the next,
   and combines them into a number that corresponds to nothing — you
   should get 513. Nothing complains either time.

5. Define a `VARIABLE` and a `CONSTANT` holding the same number, then
   print each one both with and without a `@`. Three of those four
   lines print something; only one prints the number you meant. Work
   out which before you try it.

---

## 6. Comparisons and true/false

The next section covers making decisions, and before writing one it
helps to know what Forth considers a decision to *be*.

#### What a Comparison Actually Is

In BASIC, a condition is part of the `IF` statement: `IF X > 3 THEN`
combines the test and the branch in one piece of grammar. Forth has no
grammar, so it can't do that. The test has to be an ordinary word that
runs on its own, leaves an ordinary value on the stack, and finishes.
Whatever branches later reads that value.

- **A Comparison Is an Ordinary Word:** `>` is a word `( a b -- flag )`,
  just like `+` is a word `( a b -- a+b )`. It takes two numbers off
  the stack and leaves one behind. The only difference is what that
  one number means.

- **What a Flag Means:** Zero means false; anything else at all means
  true. There is no separate true/false type and no third kind of
  value — just a number on the same stack as all the others. A value
  used this way is called a **flag**.

| Word | Stack effect      | What it does                              |
| ---- | ----------------- | ------------------------------------------ |
| `0=` | `( n -- flag )`   | `flag` is true if `n` is exactly `0`      |
| `=`  | `( a b -- flag )` | `flag` is true if `a` and `b` are equal   |
| `<`  | `( a b -- flag )` | `flag` is true if `a` is less than `b`    |
| `>`  | `( a b -- flag )` | `flag` is true if `a` is greater than `b` |

A flag is a printable number like any other, so the results can be
seen directly:

```forth
5 3 > .    \ prints -1
5 3 = .    \ prints 0
3 5 > .    \ prints 0
0 0= .     \ prints -1
7 0= .     \ prints 0
```

- **A True Flag Prints as `-1`, Not `1`:** Most languages use `1` for
  true; Forth's convention is that true means *every bit set*, and a
  whole number with all sixteen bits set reads, in signed
  two's-complement, as `-1`. It's the same `-1` produced by `0 INVERT`
  in [Bitwise and logical operators](#bitwise-and-logical-operators),
  for the same reason. The number's actual value almost never matters
  — what matters is that it isn't zero.

- **Operand Order on `<` and `>`:** The same convention `-` uses in
  section 1 applies here. `5 3 >` asks "is 5 greater than 3?" — the
  deeper value first, the top value second, the order it would be said
  aloud. `3 5 >` asks the opposite question and correctly answers `0`.

#### `0=`: Testing for Zero and Inverting a Flag

`0=` is the odd one out in the table above, and it earns its keep
twice over.

- **Two Uses in One Word:** Read literally, `0=` tests "is this exactly
  zero?" But since zero is false and everything else is true, testing
  for zero is *also* how a flag gets inverted — feed it a true flag and
  the result is false; feed it false and the result is true. Both uses
  come up constantly:

  ```forth
  5 3 > 0= .    \ prints 0 -- "5 > 3" was true, so "NOT (5 > 3)" is false
  ```

- **Why Not Call It `NOT`:** This is also why `0=` isn't spelled `NOT`,
  and why the bitwise `INVERT` from [section 4](#4-numbers) isn't
  either. They perform genuinely different jobs: `INVERT` flips all
  sixteen bits of whatever it's given, while `0=` only ever asks one
  question and answers with a flag. On a proper `-1`/`0` flag they
  happen to agree; on any other number they don't. A single shared
  name would hide that difference.

#### Words Not Provided

A limit worth knowing in advance: there is no `<=` or `>=` in
2068-Leap-Forth, and no `<>`. Each is built from what's already
available — `<=` is `>` followed by `0=`, for instance, since "not
greater than" and "less than or equal" are the same question.

### Summary

- **Core Concepts:** Flags. Zero is false and anything else is true, so
  a flag is an ordinary number on the ordinary stack. A true flag
  produced by these words is `-1`, every bit set. A comparison is a
  plain word that runs on its own and leaves a flag behind.

- **Forth Words:** `0=`, `=`, `<`, `>`.

### Exercises

1. Define the three comparisons this Forth doesn't ship with:
   
   ```forth
   : <=  > 0= ;
   : >=  < 0= ;
   : <>  = 0= ;
   ```
   
   Each is a test followed by `0=` reversing its answer. Now check all
   three at the boundary, which is the case they exist for: try each
   with two *equal* numbers, and confirm `<=` and `>=` pass there while
   `<>` fails. Then check each one either side of the boundary too.

2. `0=` applied twice in a row turns any number at all into a proper
   `-1`/`0` flag. Predict and then check:
   
   ```forth
   7 0= 0= .
   0 0= 0= .
   ```
   
   This is occasionally useful when a value that is merely "nonzero"
   needs to become the specific number `-1`.

3. Set `INVERT` from [section 4](#4-numbers) beside `0=` on a value that
   is *not* already a flag. Run `5 INVERT .` and `5 0= .`. The answers
   have nothing in common, which is precisely why the two words have
   different names.

4. `=` compares two numbers, and a flag is a number. So a flag can be
   compared with a flag. Work out what `5 3 > 5 4 > = .` prints, and
   why, before running it.

---

## 7. Making decisions: `IF` `ELSE` `THEN`

Every word defined so far has been a plain list: run the first thing,
then the next, then the next, then stop. Useful, but it means each one
does the same thing every time. Real programs need words that behave
differently in different circumstances.

#### The Basic Shape

`IF`/`ELSE`/`THEN` is Forth's answer to BASIC's `IF...THEN...ELSE`,
with one difference worth stating up front: the condition comes from
the stack, computed *before* `IF` is reached, rather than being written
as part of `IF` itself.

- **A Direct Consequence of Section 6:** A test is an ordinary word
  that leaves a flag; `IF` is a separate ordinary word that reads one.

Starting with the smallest possible example, where the condition is
handed in directly:

```forth
: SIGNTEST  IF 111 ELSE 222 THEN ;

5 SIGNTEST .     \ prints 111 -- 5 is nonzero, so: true
0 SIGNTEST .     \ prints 222 -- 0 is false
```

- **Reading `SIGNTEST`:** When it runs, whatever's already on top of
  the stack is the condition. `IF` pops it — note that word, **pops**;
  the flag is consumed and gone — and checks it exactly the way
  section 6's comparisons produce it: zero false, anything else true.
  If true, everything up to the matching `ELSE` runs; if false, the
  part between `ELSE` and `THEN` runs instead. Either way, execution
  continues after `THEN`.

Set out as a table, since there are only two paths:

```
top of stack is 5  ->  nonzero  ->  IF takes the true path   ->  111
top of stack is 0  ->  zero     ->  IF takes the false path  ->  222
```

- **What `THEN` Actually Marks:** In BASIC, `THEN` introduces the thing
  to do. In Forth it does nothing of the kind: it marks the *end* of
  the branching, the point where the two paths join back up and normal
  execution resumes. Reading it as "and then carry on here" captures
  the intent. This is the single most common early point of confusion,
  worth expecting in advance.

`ELSE` is optional. Leaving it out, when there is nothing to do in the
false case, produces the shape `IF ... THEN` — run this part or don't,
then carry on either way:

```forth
: BONUS  IF 100 + THEN ;

50 -1 BONUS .   \ prints 150 -- flag was true, so 100 got added
50  0 BONUS .   \ prints 50  -- flag was false, nothing happened
```

The more common case is a condition that's *computed* rather than
handed in directly:

```forth
: BIGGER  > IF 111 ELSE 222 THEN ;

5 3 BIGGER .   \ prints 111 -- 5 3 > is true
3 5 BIGGER .   \ prints 222 -- 3 5 > is false
```

- **Nothing New Here:** `BIGGER` simply starts with the `>` from
  section 6, which turns the two numbers already on the stack into one
  flag, and from `IF` onward it's `SIGNTEST` again. Building a word by
  attaching a test to a decision this way is the everyday shape of
  Forth code.

### Printing from a Branch: `."`

A branch that leaves a number on the stack is useful, but often the
goal is to *say* something instead. `."` ("dot-quote") prints a fixed
piece of text.

- **`."` vs. `.`:** `."` is a different word from `.`, which prints a
  computed number — `.` reads the stack, `."` doesn't touch the stack
  at all; it emits the characters written directly into it.
  ([Printing](#9-printing) covers both properly.)

- **Two Syntax Rules:** Exactly one space is required right after `."`,
  and the text runs up to but not including the next `"`. `."` also
  only works inside a colon definition, the same restriction
  `IF`/`ELSE`/`THEN` themselves carry — the IMMEDIATE mechanism from
  [section 2](#interpreting-vs-compiling-why--is-special) showing up in
  practice, since a definition must be under construction for these
  words to build into.

```forth
: DESCRIBE  IF ." positive-ish" ELSE ." zero or negative" THEN ;

5 DESCRIBE     \ prints "positive-ish"
0 DESCRIBE     \ prints "zero or negative"
```

### Back to `?DUP`

[Section 1](#rearranging-the-stack) promised that `?DUP` would make
sense once `IF` had been covered — here is the payoff. The problem
`?DUP` solves: `IF` consumes the flag it tests, but often the value
tested *is* the value meant to be used afterward.

Consider a word that prints the top of the stack, but only if it isn't
zero. Written with the tools from this section alone, a copy has to be
made to test, then cleaned up on the branch where it went unused:

```forth
: ?PRINT  DUP IF . ELSE DROP THEN ;

7 ?PRINT      \ prints 7
0 ?PRINT      \ prints nothing
```

- **Tracing Both Paths:** `DUP` makes `[7, 7]`; `IF` consumes one,
  leaving `[7]` for `.` to print. But with `0`: `DUP` makes `[0, 0]`,
  `IF` consumes one and takes the false path, and the *other* `0` is
  still sitting there — hence the `DROP`, whose only job is discarding
  a copy that turned out to be unwanted.

`?DUP` exists to make that whole pattern unnecessary. It copies the
value **only if it's nonzero**, which is exactly the case where the
copy will be needed:

```forth
: ?PRINT  ?DUP IF . THEN ;

7 ?PRINT      \ prints 7
0 ?PRINT      \ prints nothing
```

- **Why This Works:** With `7`, `?DUP` gives `[7, 7]`, behaving as
  before. With `0`, `?DUP` leaves `[0]` untouched, `IF` consumes that
  single zero, takes the false path, and nothing is left over to clean
  up. The `ELSE DROP` disappears entirely. The `( n -- 0 | n n )` stack
  effect from section 1 was describing precisely this.

### Summary

- **Core Concepts:** Branching on a flag taken from the stack. `THEN`
  marks where the paths rejoin, not where the work begins. `ELSE` is
  optional. Printing fixed text from inside a branch. Why `?DUP`
  exists.

- **Forth Words:** `IF`, `ELSE`, `THEN`, `."`.

### Exercises

1. `BIGGER` above tests with `>`. Write the matching `SMALLER` using
   `<`, and a `SAME?` using `=`, and check each against two equal
   numbers as well as two different ones.

2. `."` requires exactly one space after it, and the text ends at the
   next `"`. Define a word with *two* spaces after the `."` and see
   what gets printed — the second space is part of the text, not part
   of the syntax. Then define one where you forget the closing `"`
   altogether and see what happens to the rest of the line.

3. Write a word `CLASSIFY` that prints `NEGATIVE`, `ZERO` or
   `POSITIVE` for the number on top of the stack, and leaves the stack
   empty afterwards whichever path it takes. (Hint: you need two tests,
   so one `IF ... ELSE ... THEN` nested inside the `ELSE` of another.
   `0 <` answers the first question and `0=` answers the second.
   Remember that each test consumes the flag but you still need the
   number for the *next* test, so a `DUP` goes before the first one —
   and whichever branch stops testing has to `DROP` what's left.)

4. Section 1's `?DUP` table entry said its stack effect really does
   leave a different number of values depending on what it finds. Prove
   it: run `7 ?DUP` and then `0 ?DUP`, and after each one count what's
   on the stack by typing `.` until you get `STACK?`.

5. `BONUS` above adds 100 only when its flag is true. Rewrite it so it
   adds 100 when the flag is *false* instead, without swapping the
   arguments at the call site. (There is a one-word answer, and it's in
   the previous section.)

---

## 8. Repeating yourself

A question worth answering before reading on: with everything covered
so far, can any part of a word's definition run more than once?

The answer is no. A definition runs strictly forwards, start to finish
— `IF` and `ELSE` can make it *skip* a stretch, but nothing so far
sends it backwards. Anything needed ten times has, so far, had to be
written out ten times.

This section fixes that. Forth has three loop shapes, together
covering the ground BASIC's `FOR`/`NEXT` and `WHILE`/`WEND` cover. All
three are, like `IF`, IMMEDIATE words that build the loop during
compilation, which is why all of them only work inside `:` and `;`.

### `BEGIN` `UNTIL` — the Simplest Loop

`BEGIN ... UNTIL` repeats the code between the two until the condition
just before `UNTIL` becomes true.

- **The Body Always Runs at Least Once:** Because the check happens at
  the *end*, this is the same shape as BASIC's `REPEAT...UNTIL`, where
  available, or `DO...LOOP UNTIL` in others.

Everything needed for it is already familiar. `UNTIL` reads a flag off
the stack exactly the way `IF` did in the last section, computed
exactly the same way too. The only new idea is the jump backwards.

```forth
: COUNTDOWN  BEGIN 1 - DUP 0= UNTIL ;

5 COUNTDOWN .    \ prints 0
```

- **Tracing `COUNTDOWN` with `5`:** `1 -` makes it `4`; `DUP 0=`
  duplicates it and asks "is the duplicate zero?" — no, so false; and
  `UNTIL`, seeing false, loops back to `BEGIN`. That repeats,
  `4→3→2→1→0`, and the moment the value hits `0`, `DUP 0=` finally
  answers true, `UNTIL` stops looping, and the loop's last computed
  value (`0`) is left on the stack.

Pass by pass:

```
pass   stack at BEGIN   after 1 -   after DUP 0=   UNTIL sees
----   --------------   ---------   ------------   ---------
1      [5]              [4]         [4, 0]         false -> loop
2      [4]              [3]         [3, 0]         false -> loop
3      [3]              [2]         [2, 0]         false -> loop
4      [2]              [1]         [1, 0]         false -> loop
5      [1]              [0]         [0, -1]        true  -> stop
```

- **Why the `DUP` Matters:** Without it, `0=` would consume the very
  number being counted down, leaving nothing for the second pass to
  subtract from. This is section 1's "make a spare copy before
  consuming anything" rule again, and in loops it comes up on nearly
  every line: the value being tested is almost always the value still
  needed.

- **The Stack *Is* the Loop Variable:** `UNTIL` consumes the flag but
  leaves everything underneath it alone, which is how the running
  value survives from one pass to the next.

- **No Built-In Counter:** `BEGIN`-style Forth loops have no built-in
  counter variable the way BASIC's `FOR I = 1 TO 5` does. Knowing how
  many times a loop has run, or counting up rather than down, requires
  building that from ordinary stack values — the way `COUNTDOWN`'s own
  value pulls double duty as both the thing being counted down *and*
  the loop's exit test. (`DO`/`LOOP`, further below, does keep a
  counter automatically.)

### `BEGIN` `WHILE` `REPEAT` — Check First, Not Last

`BEGIN`/`UNTIL` has one structural weakness: the test sits at the
*bottom*, so the body has already run by the time anything gets
checked. Usually harmless — occasionally wrong, if the correct answer
is "don't do this at all," which `BEGIN`/`UNTIL` has no way to express.

`BEGIN ... WHILE ... REPEAT` puts the test in the middle instead, so
the body can run zero times:

```forth
: COUNTDOWN2  BEGIN DUP 0 > WHILE 1 - REPEAT ;

5 COUNTDOWN2 .  \ prints 0, same as COUNTDOWN above
0 COUNTDOWN2 .  \ prints 0 too -- but the body never ran at all this
                \ time, since DUP 0 > was already false on the very
                \ first check
```

- **How `WHILE` Reads Its Flag:** `WHILE` pops a flag, computed the
  same way `IF`'s condition is. False exits the loop immediately,
  skipping everything up to `REPEAT`; true falls through into the
  body, which runs and then jumps back to `BEGIN` via `REPEAT`.

The two shapes differ in exactly two ways, and both are easy to get
backwards:

1. **They react to opposite answers.** `UNTIL` stops when it finds
   *true*; `WHILE` stops when it finds *false*. Same flag, opposite
   meaning. Comparing the two definitions above: `COUNTDOWN` tests
   `DUP 0=` ("have we reached zero yet?") while `COUNTDOWN2` tests
   `DUP 0 >` ("is there still something left?") — deliberately opposite
   tests, to get the same behavior out of the two shapes.

2. **`WHILE`'s body can be skipped entirely; `UNTIL`'s cannot.** There
   is no test at `BEGIN` for `UNTIL` to consult, so its body has
   already run before any decision gets made.

- **A Naming Crossover to Watch For:** This is BASIC's `WHILE`/`WEND`
  shape, and Forth's `UNTIL` is the `REPEAT...UNTIL` shape — but Forth
  spells the *end* of the `WHILE` loop `REPEAT`, exactly the keyword
  some BASICs use for the other kind entirely. Checking against the
  examples rather than reasoning from the keywords avoids the mix-up.

### `DO` `LOOP` `I` — a Real Counter

Both loops above require keeping the count manually, on the stack,
mixed in with whatever else is being worked with. `DO`/`LOOP` is
Forth's answer to BASIC's `FOR`/`NEXT`: it keeps the count off to one
side, and hands it back on request.

```forth
: FIVE  5 0 DO I . LOOP ;

FIVE     \ prints 0 1 2 3 4
```

Three pieces, taken one at a time.

- **`limit start DO`:** Starts a loop counting up from `start`,
  stopping just *before* it would reach `limit`. So `5 0 DO` runs for
  index values `0` through `4` — five passes, not six. The limit is
  where it stops, not where it ends up, the same "up to but not
  including" convention BASIC's `FOR I = 0 TO 4` writes the other way
  round.

- **`I`:** Pushes the current index onto the stack. It's an ordinary
  word with an ordinary stack effect, `( -- index )`, and nothing
  requires its use: a loop that just repeats something five times
  identically never mentions `I` at all.

- **`LOOP`:** Adds one to the index and jumps back to just after `DO`,
  unless the index has reached `limit`, in which case the loop ends.

- **Argument Order:** Worth double-checking every time, since it reads
  backwards from how it would be said aloud: **limit first, start
  second**. `5 0 DO` means "from 0 up to 5," not "from 5 down to 0" —
  the single most common `DO` mistake.

Something to actually watch happen, built the same way section 2 built
`QUADRUPLE` — a small word, then a word that uses it:

```forth
: STAR    42 EMIT ;
: STARS   0 DO STAR LOOP CR ;

5 STARS       \ prints *****
20 STARS      \ prints ********************
```

- **How `STARS` Works:** `STAR` prints a single asterisk (42 is `*`'s
  character code, and `EMIT` prints one character —
  [Printing](#9-printing) has the details). `STARS` supplies the `0`
  start itself and takes the limit from whatever was pushed before
  calling it, so `5 STARS` reaches `DO` with `[5, 0]` on the stack:
  limit 5, start 0. It then loops, and `CR` at the end moves to a
  fresh line. `STARS` never mentions `I`, since it doesn't care which
  pass it's on.

- **A Real Trap:** `DO` does not check whether `start` already equals
  `limit` before running the body the first time. So `0 STARS` does
  not print nothing: it reaches `0 0 DO`, runs the body anyway, and
  then `LOOP` — having just moved the index from `0` to `1` — compares
  against a limit of `0` and doesn't match. It won't match again until
  the index has wrapped all the way around through 65536 values. In
  practice this produces a near-infinite loop that looks like the
  machine has hung.

- **The Fix:** Never write a `DO` where `start` and `limit` might
  already be equal. If a count could legitimately be zero, guard it
  first, using the previous section's `IF`:

  ```forth
  : STARS   ?DUP IF 0 DO STAR LOOP CR THEN ;

  5 STARS       \ prints *****
  0 STARS       \ prints nothing, and returns safely
  ```

- **Why `?DUP` Again:** For exactly the reason section 7 gave. The
  count has to be tested, and it's also the value `DO` needs, so
  copying it only when it's nonzero is precisely right. When it *is*
  zero, `?DUP` leaves the single `0`, `IF` consumes it, the loop is
  skipped entirely, and the stack is left clean.

### `LEAVE` — Exiting a Loop Early

`LEAVE`, used inside a `DO` loop's body, ends the loop the moment it
runs, skipping the rest of the current pass and every remaining one.

- **Usually Written Inside `IF`:** Running `LEAVE` unconditionally
  would make the rest of the loop pointless:

  ```forth
  : FINDTHREE  10 0 DO I . I 3 = IF LEAVE THEN LOOP ;

  FINDTHREE     \ prints 0 1 2 3, then stops -- the remaining six
                \ passes (I = 4 through 9) never run
  ```

- **Scope:** `LEAVE` exits only the loop it is directly inside. With
  one `DO` loop nested in another, `LEAVE` exits the inner one and the
  outer loop keeps counting normally.

### `EXIT` — Returning from the Whole Word

`LEAVE` ends a loop. `EXIT ( -- )` ends the **definition**: it returns
immediately to whoever called the word, skipping everything after it —
the same relationship BASIC's `RETURN` has to the rest of a
subroutine, except that here it can appear anywhere in the body rather
than only at the end.

At its simplest, with no loop involved at all:

```forth
: TEXIT1  1 EXIT 2 ;

TEXIT1 .      \ prints 1 -- the 2 was compiled, and never runs
```

- **Why the `2` Never Runs:** The `2` really is part of the definition;
  `;` compiled it like anything else. It is simply unreachable, because
  `EXIT` returned before execution got that far. Like `IF` and `LEAVE`,
  `EXIT` is one of the IMMEDIATE words from
  [section 2](#interpreting-vs-compiling-why--is-special) and only
  makes sense inside a `:` definition — there's nothing to return from
  at the prompt.

That makes `EXIT` the natural partner of `IF` for an early bail-out,
which is nearly always how it gets written:

```forth
: ?PRINT-POS  DUP 0 < IF DROP EXIT THEN . ;

5 ?PRINT-POS      \ prints 5
-5 ?PRINT-POS     \ prints nothing, and leaves the stack clean
```

- **Comparing With `?PRINT`:** This is
  [section 7](#7-making-decisions-if-else-then)'s `?PRINT` shape with
  the guard turned around: `DUP` copies the value so the test can
  consume one, and when the test finds a negative the word tidies up
  its own copy with `DROP` and returns. Written without `EXIT`, an
  `ELSE` would be needed and the printing would have to move inside it;
  `EXIT` allows the unusual case to be handled first and left behind,
  leaving the normal path unindented at the end.

- **`EXIT` Inside a `DO` Loop:** `EXIT` also works from inside an open
  `DO` loop, which is worth stating plainly since the opposite would be
  a reasonable assumption. A loop keeps bookkeeping of its own while it
  runs — the counter `I` reads has to live somewhere — and leaving the
  word from inside the loop has to clean that up. `EXIT` does, at
  every level of nesting it happens to be inside:

  ```forth
  : TEXIT2  0 5 0 DO I 3 = IF EXIT THEN 1+ LOOP 999 ;

  TEXIT2 .      \ prints 3
  ```

- **Tracing `TEXIT2`:** `0` starts an accumulator on the stack, then
  the loop runs with `I` counting `0, 1, 2, ...`. Each pass that isn't
  the one being looked for adds one to the accumulator, so after `I`
  has been `0`, `1`, and `2` the accumulator holds `3`. On the pass
  where `I` is `3`, the `IF` fires and `EXIT` returns straight out of
  `TEXIT2` — before that pass's own `1+`, past every remaining pass,
  and past the trailing `999`, which never reaches the stack at all.

- **`EXIT` vs. `LEAVE`:** The two are easy to confuse, and the
  difference is exactly one word's worth of scope: `LEAVE` stops the
  loop and continues with the rest of the definition after it, so the
  `999` in `TEXIT2` *would* have been pushed. `EXIT` abandons the
  definition entirely.

### Loops Inside Loops

Nesting `DO` loops works, and needs no special ceremony — the inner
loop's counter simply sits on top of the outer one's and is gone again
by the time the outer `LOOP` looks at anything.

- **Which Index `I` Means:** `I` always gives the index of the
  innermost loop currently active. In the outer loop's own body, before
  the inner `DO` has started, that's the outer index; from the moment
  the inner `DO` runs, it's the inner one.

That's usually all that's needed, because the inner loop's *limit* gets
computed out in the outer body, where `I` is still the outer index:

```forth
: STAR   42 EMIT ;

: TRIANGLE
  5 0 DO
    I 1+ 0 DO             \ I here is the OUTER index -- the inner
      STAR                \ loop hasn't started yet
    LOOP
    CR
  LOOP ;

TRIANGLE
```

which prints

```
*
**
***
****
*****
```

- **Reading the Inner `DO` Line:** `I 1+` takes the outer index and
  adds one, giving the inner loop a limit of 1 on the first row, 2 on
  the second, and so on. (`1+` is [section 4](#4-numbers)'s shorthand
  for `1 +`; either spelling works.) The added one exists because `DO`
  stops *before* the limit — without it, row 0 would ask for `0 0 DO`
  and hit the near-infinite-loop trap described above.

### `J` — the Enclosing Loop's Index

`TRIANGLE` never needed the outer index once the inner loop was
actually running. Plenty of things do — a multiplication table, or
anything where each inner pass has to know which row it's on — and
inside the inner body `I` has stopped being any help. `J ( -- n )` is
the word for that: the same idea as `I`, one loop further out.

```forth
: DIGITS
  5 0 DO
    I 1+ 0 DO
      J 48 + EMIT         \ J is the OUTER index, even in here
    LOOP
    CR
  LOOP ;

DIGITS
```

which prints

```
0
11
222
3333
44444
```

- **Reading `48 + EMIT`:** The only unfamiliar part, and it's
  [section 9](#9-printing)'s `EMIT` doing exactly what `STAR` did — 48
  is the character code of `0`, so adding the row number to it gives
  the code of that row's digit, the same code-arithmetic idea
  `65 EMIT` printing `A` already showed. Everything else is `TRIANGLE`
  unchanged. Swapping `J` for `I` would print `0`, `01`, `012`, ...
  instead: the inner count, not the row.

- **A Real Limit:** `J` reaches one loop out directly; there's no `K`
  for a third level, so a three-deep nest that needs its outermost
  index falls back to saving it in a `VARIABLE` from
  [section 5](#5-reading-and-writing-memory-directly) by hand.

### `+LOOP` — Stepping by Something Other Than 1

`LOOP` always counts up by exactly 1. `+LOOP` takes a number off the
stack and steps by that much each pass — including a negative number,
to count downward:

```forth
: EVENS  10 0 DO I . 2 +LOOP ;

EVENS     \ prints 0 2 4 6 8
```

- **Where the Step Goes:** Look at where the `2` sits: *inside* the
  loop body, just before `+LOOP`. This isn't a formatting choice.
  `+LOOP` takes its step off the stack the same way every other word
  takes its arguments, which means the step has to be pushed on each
  pass, from inside the loop. Writing it outside would push it once
  and then leave `+LOOP` reaching for a value that isn't there on the
  second pass.

- **A Consequence Worth Noting:** Since the step is an ordinary value
  read fresh each time, it doesn't have to be the same value every
  pass. A computed step is perfectly legal, though rarely what's
  wanted.

`+LOOP` also has to end the loop differently from `LOOP`.

- **Why the Ending Differs:** Plain `LOOP` steps by exactly 1, so it
  can simply ask "did the index land on `limit`?" — with a step of 1 it
  can never skip past. `+LOOP` can. So it ends the loop once a step
  carries the index *at or past* `limit`, even if it jumps clean over
  it:

  ```forth
  : BY3  10 0 DO I . 3 +LOOP ;

  BY3     \ prints 0 3 6 9
  ```

  After printing `9`, the next step would land on `12` — past `10`,
  without ever equaling it — so the loop stops there. An "exact match"
  test would have sailed straight past and kept going.

### Summary

- **Core Concepts:** Three loop shapes. `BEGIN`/`UNTIL` tests at the
  bottom, so its body always runs once. `BEGIN`/`WHILE`/`REPEAT` tests
  in the middle, so its body can run no times at all. `DO`/`LOOP` keeps
  a counter automatically. Leaving a loop early, and leaving the whole
  word early. Loop indices, including one level out.

- **Forth Words:** `BEGIN`, `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`,
  `+LOOP`, `I`, `J`, `LEAVE`, `EXIT`.

### Exercises

1. The same job, written two ways. `FIVE` above prints 0 to 4 with
   `DO`/`LOOP`. Here it is again with no counter word at all:
   
   ```forth
   : FIVE2  0 BEGIN DUP . 1+ DUP 5 = UNTIL DROP ;
   ```
   
   Check that `FIVE2` prints the same thing `FIVE` does, then work out
   what each of `DUP`, `1+` and the final `DROP` is there for. Which
   version would you rather come back to in a month?

2. Now the other direction. `COUNTDOWN` counts *down* with
   `BEGIN`/`UNTIL`. Write `COUNTDOWN3` that counts down from 5 to 0
   printing each value, using `DO` and `+LOOP` instead. (Hint: `0 5 DO`
   starts at 5 with a limit of 0, and the step is `-1` — which, as
   above, goes inside the body just before the `+LOOP`.)

3. `BEGIN`/`WHILE`/`REPEAT` earns its keep when the body must be able
   to run zero times. Write `STARS-W`, which prints as many asterisks
   as the number on the stack asks for and prints nothing at all for
   `0` — using `WHILE`, and *without* the `?DUP IF ... THEN` guard that
   `STARS` needed. Check it with `3 STARS-W` and `0 STARS-W`.

4. `LEAVE` exits only the loop it is directly inside. Type
   
   ```forth
   : NEST  3 0 DO  3 0 DO  I 1 = IF LEAVE THEN  I .  LOOP  CR  LOOP ;
   ```
   
   and run `NEST`. Count the lines it prints and the numbers on each.
   If `LEAVE` escaped both loops you would get one line; if it escapes
   only the inner one you get three. Which happens?

5. Swap the `LEAVE` in `NEST` for `EXIT` and run it again. Explain the
   difference in terms of the `TEXIT2` discussion above.

6. `J` reaches the enclosing loop's index, which is exactly what a
   table needs. Type
   
   ```forth
   : TABLE  4 1 DO  4 1 DO  J I * .  LOOP  CR  LOOP ;
   ```
   
   and check that `TABLE` prints the 1-to-3 multiplication table, three
   numbers to a row. Then swap the `J` and the `I` and work out why the
   output changes the way it does.

7. [Section 5](#5-reading-and-writing-memory-directly)'s `ARRAY`
   example only ever fills and reads one element at a time by hand.
   Write `FILL-SCORES`, which uses a `DO` loop to store `I * 10` into
   each element of a five-element `ARRAY`, and `TOTAL-SCORES`, which
   uses a second `DO` loop to add all five elements together and leave
   the sum on the stack:
   
   ```forth
   5 ARRAY SCORES
   
   : FILL-SCORES   5 0 DO  I 10 * I CELLS SCORES + !  LOOP ;
   : TOTAL-SCORES  ( -- n )  0  5 0 DO  I CELLS SCORES + @ +  LOOP ;
   
   FILL-SCORES
   TOTAL-SCORES .    \ prints 100 -- 0+10+20+30+40
   ```
   
   `TOTAL-SCORES` starts by pushing `0` — the running total — *before*
   the loop begins, so there's always something underneath for the
   first `+` to add to. Each pass then adds one more element on top of
   whatever the running total already was, entirely on the stack, with
   no `VARIABLE` needed to hold it between passes.

---

## 9. Printing

A word like `+` leaves its answer sitting on the stack, and nothing
displays it until asked. `.` (pronounced "dot") is how that's done:

```forth
5 3 + .
```

- **What `.` Does:** Prints `8`, followed by a trailing space, so
  several `.`s in a row read as separate space-separated numbers
  instead of running together. It also removes the value from the
  stack on the way past — `.` both reads *and consumes* the top of the
  stack, unlike, say, `DUP`. Negative numbers print with a leading
  `-`, and zero prints as `0`. (`F.`, for printing a *decimal* number,
  is covered in [Numbers](#4-numbers).)

`EMIT` is the lower-level word underneath `.`. It takes a single
number off the stack and prints it as one character, at whatever
character code that number is: `65 EMIT` prints `A`, since 65 is
`A`'s character code.

- **Shared Printing Position:** `.` itself is built out of repeated
  `EMIT` calls, one per digit. Both share a single printing position,
  which wraps to a new line automatically past column 32 and scrolls
  the screen once it reaches the row just above the one being typed
  on, so printed output can never collide with the line currently
  being entered. `AT-XY` (see [Drawing and sound](#10-drawing-and-sound))
  moves that printing position directly, for output somewhere other
  than wherever the last thing printed left off.

Three small words exist purely for convenience, each a thin wrapper
around `EMIT` for a character that would otherwise require looking up
its code:

| Word     | Stack effect | What it does                                   |
| -------- | ------------ | ----------------------------------------------- |
| `CR`     | `( -- )`     | Move to the start of the next line — `13 EMIT` |
| `SPACE`  | `( -- )`     | Print one space — `32 EMIT`                    |
| `SPACES` | `( n -- )`   | Print `n` spaces                               |

```forth
." NAME:" SPACE ." FORTH" CR
." VERSION:" SPACE ." 1" CR
```

- **The Output:** Prints `NAME: FORTH`, then `VERSION: 1` on the line
  below — each lined up by hand with `SPACE`, no column-alignment word
  required.

### Putting `.`, `."`, and `SPACE` Together

None of this is new, only combined. Here is the same "label, `SPACE`,
value, `CR`" shape as the `NAME:`/`VERSION:` example above, with a
computed number in place of a fixed word:

```forth
." SCORE:" SPACE 42 . CR
." LEVEL:" SPACE 3 . CR
```

- **Reading the Result:** Prints `SCORE: 42` then `LEVEL: 3`
  underneath it. `."` and `.` do exactly what section 1 and this
  section already established — `."` prints fixed text and never
  touches the stack, `.` prints and consumes a number — the only new
  part is seeing them share a line.

### Summary

- **Core Concepts:** Printing a computed number, printing fixed text,
  and printing one character at a time. The shared printing position,
  its automatic wrap at column 32, and the scroll that keeps output
  clear of the line currently being typed. Three convenience wrappers
  around `EMIT`.

- **Forth Words:** `.`, `EMIT`, `CR`, `SPACE`, `SPACES`.

### Exercises

1. Section 8's `STARS` prints one character per pass with no idea where
   on the screen it is landing. Run
   
   ```forth
   40 STARS
   ```
   
   It prints 32 stars, wraps to a fresh line exactly where the
   paragraph above said it would, puts the remaining 8 on the second
   line, and then the `CR` already built into `STARS` moves past even
   those. Nothing about `STARS` changed to make that happen — the wrap
   is `EMIT`'s own behaviour, underneath every word that eventually
   calls it. `SPACES` shows the same thing with no definition at all:
   try `40 SPACES` followed by `42 EMIT` and see which line the
   asterisk lands on.

2. `EMIT` prints whatever character code it is given, and character
   codes run in order, so a loop can walk through them. Type
   
   ```forth
   : ALPHABET  91 65 DO I EMIT LOOP CR ;
   ```
   
   and run it. Work out why the limit is 91 rather than 90 before you
   look back at section 8's warning about `DO` stopping *before* its
   limit.

3. Numbers printed with `.` are left-aligned and separated by a single
   space, which makes a column of them ragged. Write a word `RJ` that
   prints one number right-justified in a field five characters wide,
   so that a column of them lines up on the right. (Hint: `STR` from
   section 5 turns a number into an address and a length — and the
   length is exactly how many characters it will take, so five minus
   that is how many `SPACES` to print first. `TYPE` then prints the
   number itself.) Test it with
   
   ```forth
   : COL  10 0 DO I I * RJ CR LOOP ;
   ```
   
   which should print the squares of 0 to 9 in a neat right-hand
   column.

4. `.` consumes what it prints, and this is easy to forget when you
   want to both use a value and see it. Print the top of the stack
   *without* losing it, using one extra word from section 1, and prove
   the value survived by printing it a second time.

---

## 10. Drawing and sound

2068-Leap-Forth's graphics and sound words are deliberately thin. Each is a
direct, single-purpose action, in the same spirit as BASIC's `PLOT`,
`CIRCLE`, and `BEEP`: there's no drawing "state" to set up first
beyond what each word's own arguments say.

| Word       | Stack effect                   | What it does                                                                                                                             |
| ---------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `PLOT`     | `( x y -- )`                   | Set the pixel at `(x, y)`                                                                                                                |
| `LINE`     | `( x1 y1 x2 y2 -- )`           | Draw a line from `(x1, y1)` to `(x2, y2)`                                                                                                |
| `CIRCLE`   | `( xc yc r -- )`               | Draw a circle outline centered at `(xc, yc)` with radius `r`                                                                             |
| `FILL`     | `( x y -- )`                   | Flood-fill the enclosed area touching `(x, y)` with the current color                                                                    |
| `CLS`      | `( -- )`                       | Clear the whole screen                                                                                                                   |
| `BORDER`   | `( color -- )`                 | Set the screen border to `color` (0-7, same numbering as BASIC's `BORDER`)                                                               |
| `INK`      | `( color -- )`                 | Set the foreground color `PLOT`/`LINE`/`CIRCLE`/`FILL` draw with, and printed text (`EMIT`/`.`/`."`/`TYPE`) prints in, from now on (0-7) |
| `PAPER`    | `( color -- )`                 | Set the background color the same way                                                                                                    |
| `BRIGHT`   | `( flag -- )`                  | `1` draws `INK`/`PAPER` in their high-intensity shade from now on; `0` returns to normal intensity                                       |
| `FLASH`    | `( flag -- )`                  | `1` makes `INK`/`PAPER` flash (hardware-blink) from now on; `0` returns to steady                                                        |
| `AT-XY`    | `( col row -- )`               | Move where the next `EMIT`/`.`/`."` prints to (column 0-31, row 0-22)                                                                    |
| `HIRES`    | `( -- )`                       | Switch to High Resolution Graphics mode                                                                                                  |
| `NORMAL`   | `( -- )`                       | Switch back to Normal mode                                                                                                               |
| `BEEP`     | `( n-semitones fduration -- )` | Produce a tone                                                                                                                           |
| `SOUND`    | `( register data -- )`         | Write directly to an AY-3-8912 sound-chip register                                                                                       |
| `TONE`     | `( channel period -- )`        | Set channel 0/1/2 (A/B/C)'s tone pitch                                                                                                   |
| `VOLUME`   | `( channel level -- )`         | Set channel 0/1/2's volume (0-15, fixed)                                                                                                 |
| `MIXER`    | `( mask -- )`                  | Choose which tones/noise generators are on                                                                                               |
| `NOISE`    | `( period -- )`                | Set the shared noise generator's pitch                                                                                                   |
| `ENVELOPE` | `( period shape -- )`          | Set the shared envelope generator's shape                                                                                                |

```forth
CLS
5 BORDER
2 INK  6 PAPER
128 96 40 CIRCLE
128 96 FILL
```

![A red, filled circle on a cyan-bordered screen](images/drawing_example.png)

- **Reading Order:** Left to right follows the same postfix habit as
  everything else here: for `LINE`, the coordinates go on the stack in
  the order you'd say them out loud ("from 60,5 to 100,45"), then the
  word that acts on all four at once. Nothing here is conceptually new
  over section 1 — these are words, exactly like `+` or `DUP`, that
  happen to affect the screen or the speaker instead of a number.

#### Persistent Color State: `INK`, `PAPER`, `BRIGHT`, `FLASH`

`INK` and `PAPER` set state that persists until changed. Every
`PLOT`/`LINE`/`CIRCLE` after `2 INK 6 PAPER` draws red-on-yellow, not
just the next one, until some later call changes it again. Calling
`INK` never disturbs whatever `PAPER` was last set to, and vice versa;
each touches only its own half of the color. `CLS` honors the current
`PAPER` as well — clearing the screen fills it with whatever
background color is set, not always black.

- **Text Shares the Same State:** This isn't limited to graphics.
  `EMIT` (and everything built on it — `.`, `."`, `TYPE`) stamps the
  current `INK`/`PAPER` into each character cell as it prints, the
  same way real Sinclair BASIC's `PRINT` does:

  ```forth
  2 INK  6 PAPER
  ." RED ON YELLOW"
  0 INK  7 PAPER
  ." BACK TO NORMAL"
  ```

  The first line prints in red on yellow; the second reverts to black
  on white. Only the cells actually written to change — printing a
  shorter line over a longer one leaves the old color sitting in
  whatever cells weren't touched, same as it leaves old characters
  sitting there too.

- **`BRIGHT` Is a Third, Independent Piece of State:** `BRIGHT` works
  the same way, alongside `INK` and `PAPER` rather than a color of its
  own — `1` makes whichever `INK`/`PAPER` are currently set draw in
  their lighter, high-intensity shade; `0` returns to the normal,
  darker shade. Like `INK` and `PAPER`, it persists until changed and
  never disturbs the other two:

  ```forth
  2 INK  1 BRIGHT
  ." BRIGHT RED"
  0 BRIGHT
  ." NORMAL RED"
  ```

  The first line prints in bright (light) red; the second prints the
  same ink color 2 (red) but back at normal intensity — `BRIGHT`'s own
  change to intensity didn't touch `INK`'s color, exactly as `INK`
  changing color never touches `PAPER`.

- **`FLASH` Is a Fourth:** `FLASH` works the same way again — `1`
  makes whichever `INK`/`PAPER` are currently set blink (the hardware
  does the actual blinking, in real time, with no CPU involvement once
  set); `0` returns to steady:

  ```forth
  2 INK  1 FLASH
  ." FLASHING RED"
  0 FLASH
  ." STEADY RED"
  ```

  Same shape as the `BRIGHT` example above: only the flash state
  changes between the two lines, not the color. `BRIGHT` and `FLASH`
  can be combined freely with each other and with `INK`/`PAPER`, since
  each occupies its own bit and none of the four words touch any bit
  but its own.

#### Moving the Printing Position: `AT-XY`

`AT-XY ( col row -- )` moves the shared printing position [section
9](#9-printing) described directly, instead of leaving it wherever the
last thing printed left off — column 0-31, row 0-22:

```forth
CLS
10 5 AT-XY  ." HELLO"
0 0 AT-XY   ." TOP LEFT"
```

`HELLO` appears starting at column 10 on row 5; `TOP LEFT` then
appears starting at the very top-left corner, even though it's printed
second — `AT-XY` jumps the position, it doesn't scroll or clear
anything on the way there.

### Drawing Many Things at Once

Nothing here is a new word — it's [section 8](#8-repeating-yourself)'s
`DO`/`LOOP` counting across `CIRCLE` instead of across `EMIT`. Five
evenly-spaced dots in a row:

```forth
: DOTS  200 20 DO I 96 8 CIRCLE 40 +LOOP ;

DOTS
```

- **Reading `DOTS`:** Read the body the way section 8 read `STARS`:
  this uses section 8's own `+LOOP` to step the index by 40 instead of
  1, so `I` counts the x coordinates directly — 20, 60, 100, 140, 180
  — with no arithmetic needed to turn it into one (2068-Leap-Forth does
  have plain integer `*` — see [Numbers](#4-numbers) — but `+LOOP`'s
  own step argument already does this particular job more directly).
  `I` feeds straight into `CIRCLE` as the x coordinate; `96` and `8`
  are a fixed y and radius, the same on every pass. `CIRCLE` then draws
  — `xc yc r`, in that order, exactly as the table above lists it.
  `CIRCLE` itself hasn't changed at all between this example and the
  one just above it; it's the loop wrapped around it that's new, and
  it's the identical loop `STARS` used, just feeding a different word
  each pass.

### `RECT`, `POLYGON`, and `POLYGON-FILL`: More Shapes, From a Second ROM

`PLOT`/`LINE`/`CIRCLE`/`FILL` above all live in the same 16K Home ROM as
everything else in this tutorial. Three more shape words — `RECT`,
`POLYGON`, and `POLYGON-FILL` — exist too, but they're dispatched
through a SECOND, separate 8K ROM plugged into the TS2068's own EXROM
socket, not the Home ROM.

- **This Matters Practically:** The placeholder EXROM most setups boot
  with has no real code in it, so these three words will each just
  silently do nothing (the same "refuse quietly rather than crash"
  behavior every word in this project already uses when something's
  missing) unless you've built and loaded the real `graphics_exrom.bin`
  image instead — see the main [README](../README.md)'s own "Try it"
  section for exactly how, or [`docs/eightyone_setup.md`](eightyone_setup.md)
  if you're running on EightyOne or TS-Pico.

| Word           | Stack effect                     | What it does                                                     |
| -------------- | ---------------------------------- | ----------------------------------------------------------------- |
| `RECT`         | `( x0 y0 x1 y1 -- )`               | Draw a FILLED rectangle between two opposite corners              |
| `POLYGON`      | `( x1 y1 x2 y2 ... xn yn n -- )`   | Draw the OUTLINE of a closed shape through `n` given vertices (3-12), the last edge closing back to the first vertex |
| `POLYGON-FILL` | `( x1 y1 x2 y2 ... xn yn n -- )`   | Fill that same shape's INTERIOR instead of outlining it (even-odd rule — a concave notch stays unfilled, correctly) |

```forth
2 INK 20 20 60 60 RECT
```

- **Corner Order Doesn't Matter:** Like `LINE`, `RECT`'s two corners
  can be given in any order — sorted, backwards, or a mix of the two —
  and it always fills the same box either way; it's the OPPOSITE two
  corners of the box that matter, not which one comes first on the
  stack.

`POLYGON` and `POLYGON-FILL` share the same argument shape: `n`
vertices, each an `(x y)` pair, then `n` itself last so the word knows
how many pairs to expect:

```forth
4 INK 100 40 140 40 100 80 3 POLYGON
```

- **Reading This Example:** Draws a red triangle outline through
  `(100,40)`, `(140,40)`, and `(100,80)` — three vertices, then the
  count `3`. `n` must be between 3 and 12; giving a count outside that
  range (including the two you'd naturally reach for by mistake, `0`
  or `1`) draws nothing at all rather than guessing which of the
  remaining stack values were meant for it.

`POLYGON-FILL` takes the exact same arguments and fills the interior
instead:

```forth
3 INK 50 50 90 70 50 90 65 70 4 POLYGON-FILL
```

- **Why the Notch Stays Empty:** Fills a concave arrow/chevron shape —
  the notch cut into its left side stays empty, correctly, because the
  fill uses the even-odd rule rather than just "fill everything
  between the leftmost and rightmost edge on each row." `POLYGON-FILL`
  never draws the outline itself; call `POLYGON` too, with the same
  vertices, if you want both.

### Sprites: Capturing and Moving a Shape

Three more words, from that same second EXROM: `SPRITE-DEFINE`,
`SPRITE-SHOW`, and `SPRITE-HIDE` — four numbered slots (0-3), each
holding one captured 16x16-pixel image plus whatever the screen looked
like where it was last shown, so hiding it again restores the original
background exactly rather than just erasing to blank.

| Word            | Stack effect          | What it does                                                                                          |
| --------------- | ----------------------- | ------------------------------------------------------------------------------------------------------ |
| `SPRITE-DEFINE` | `( slot row col -- )`  | Capture the 16x16-pixel block at character row/col into `slot` (0-3)                                   |
| `SPRITE-SHOW`   | `( slot row col -- )`  | Draw `slot`'s captured image at character row/col, first saving whatever was there so `SPRITE-HIDE` can restore it |
| `SPRITE-HIDE`   | `( slot -- )`          | Erase `slot`'s currently-shown image, restoring the exact background `SPRITE-SHOW` saved                |

```forth
2 INK 40 40 55 55 RECT      \ draw a 16x16 red box at row/col (5,5)
0 5 5 SPRITE-DEFINE         \ capture it into slot 0
CLS                         \ clear the whole screen
0 10 10 SPRITE-SHOW         \ redraw the captured box at row/col (10,10)
0 SPRITE-HIDE               \ remove it, restoring the (now blank) background
```

- **Coordinates Are Character Cells, Not Pixels:** Row/col here are
  the same 0-31/0-22 CHARACTER-cell coordinates `AT-XY` uses above,
  not raw pixels — a sprite is always exactly two character cells wide
  and two tall (16x16 pixels), positioned by its own top-left cell.
  `SPRITE-SHOW`ing a slot that's already showing elsewhere, or
  `SPRITE-HIDE`ing a slot that was never shown, both refuse quietly
  rather than doing anything unexpected — the same "silently do
  nothing on invalid input" convention `FILL`/`SOUND`/`STICK` already
  use elsewhere in this project.

#### `BEEP`: Simple Note Playback

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

### Sound: `BEEP` Limits and Direct Chip Access

While `BEEP` handles simple note playback, it operates under a few clear hardware boundaries:

- **Whole Semitones Only:** Unlike BASIC's `BEEP`, which accepts fractional pitches, this implementation supports whole semitones exclusively.

- **The 12.9 kHz Ceiling:** There is a strict physical ceiling around 12.9 kHz. Notes pushed past this threshold clamp to the ceiling rather than increasing further, as this represents the maximum toggle speed of the hardware speaker loop.

For ordinary musical use — spanning a few octaves around middle C — these limits are well out of reach.

### Direct Register Access: `SOUND`

For anything `BEEP` cannot achieve — such as a sustained tone, simultaneous multi-note playback, or precise volume control — **`SOUND ( register data -- )`** provides direct, register-level access to the machine's AY-3-8912 sound chip, mirroring authentic BASIC commands.

- **Stack Effect:** `( register data -- )`

- **What It Does:** Writes a raw byte into one of the chip's registers (`1–16`). Out-of-range values are silently ignored.

Because the chip isolates different properties across separate registers — such as pitch, active channels, and volume — producing a complete tone requires **three coordinated calls** rather than a single all-in-one command.

```forth
2 251 SOUND        \ channel B's tone pitch (fine byte)
3   0 SOUND        \ channel B's tone pitch (coarse byte)
7 253 SOUND        \ mixer: turn on ONLY channel B's tone
9  15 SOUND        \ channel B's volume -- THIS is what you'll hear
9   0 SOUND        \ silence it again
```

- **Why Four Calls Before Anything Sounds:** Nothing is audible until
  that fourth line; the first three only set up state the chip
  remembers, the way `INK`/`PAPER` persist until changed. `SOUND` has
  no idea what a "note" is, unlike `BEEP` — the 251 above is a raw
  chip register value, worked out from the machine's own sound-chip
  clock speed (1,764,000 Hz) and the formula
  `period = clock / (16 * frequency)` for a note near 439 Hz. A
  different pitch means recomputing that period yourself. There's no
  semitone convenience here on purpose: `SOUND` trades convenience for
  direct access to everything the chip can do — three tones, volume
  envelopes, noise — that `BEEP` was never meant to reach.

#### Shorthand Words: `TONE`, `VOLUME`, `MIXER`, `NOISE`, `ENVELOPE`

`TONE`, `VOLUME`, `MIXER`, `NOISE`, and `ENVELOPE` don't reach
anything `SOUND` couldn't already reach — they're shorthand for it,
so you don't have to remember which register pair belongs to which
channel or work out a fine/coarse split by hand every time:

| Word       | Stack effect            | What it does                               |
| ---------- | ------------------------ | -------------------------------------------- |
| `TONE`     | `( channel period -- )` | Set channel 0/1/2 (A/B/C)'s tone pitch     |
| `VOLUME`   | `( channel level -- )`  | Set channel 0/1/2's volume (0-15, fixed)   |
| `MIXER`    | `( mask -- )`           | Choose which tones/noise generators are on |
| `NOISE`    | `( period -- )`         | Set the shared noise generator's pitch     |
| `ENVELOPE` | `( period shape -- )`   | Set the shared envelope generator's shape  |

The four-line tone from above becomes:

```forth
1 251 TONE      \ channel B (1), same pitch as before
1  15 VOLUME    \ channel B, full volume -- THIS is what you'll hear
253 MIXER       \ only channel B's tone switched on
1   0 VOLUME    \ silence it again
```

- **A Real Gap Worth Knowing:** `SOUND` itself can never select chip
  register 0 (channel A's own tone pitch, low byte) — its 1-16
  numbering, copied faithfully from real BASIC's own `SOUND` command,
  simply has no value that lands there. `TONE` doesn't have that gap;
  `0 period TONE` reaches it directly.

- **`MIXER`'s Mask Is Inverted:** `MIXER`'s mask is the one place these
  words don't try to be friendlier than the chip itself: bit 0 is
  channel A's tone, bit 1 is B, bit 2 is C, bits 3-5 are the three
  noise generators — and confusingly, on this chip, a **0** bit means
  "on" and a **1** bit means "off." `253` above is `$FD`, every bit set
  except bit 1, which is exactly "everything off except channel B's
  tone."

`NOISE` sets the pitch of a hissing, unpitched sound shared by all
three channels — `MIXER` still has to switch it onto one of them
(bits 3-5) before anything comes out, the same "several separate
switches" reality `SOUND` already needs for an ordinary tone:

```forth
10 NOISE        \ noise generator's own pitch
247 MIXER       \ $F7 -- every bit set (off) except bit 3
                \ (channel A's own noise), which is clear (on)
0  15 VOLUME    \ channel A, full volume -- THIS is what you'll hear
0   0 VOLUME    \ silence it again
```

`ENVELOPE` sets up a rising-and-falling (or repeating, or one-shot)
volume shape shared by all three channels, but by itself it's
inaudible — a channel only follows the envelope if you also flip one
bit `VOLUME` never touches (bit 4 of that channel's own volume
register), which needs a raw `SOUND` call:

```forth
500 10 ENVELOPE   \ shape 10: a rising-then-falling triangle
8 16 SOUND        \ channel A's own volume register (8), bit 4 set --
                  \ "follow the envelope instead of a fixed level"
254 MIXER         \ $FE -- only channel A's tone switched on
0 0 VOLUME        \ silence it again -- also clears bit 4, back to
                  \ ordinary fixed-volume mode
```

### High Resolution Graphics: `HIRES` and `NORMAL`

Every example so far draws on **Normal** mode's screen, which colors
in blocks: one `INK`/`PAPER` pair per 8x8-pixel cell, the classic
Sinclair "color clash" you may already know from real Spectrum
software — two shapes that pass through the same cell are stuck
sharing its one color, whether you wanted that or not.

`HIRES` switches to a genuinely different color mechanism: the same
256x192 pixels, but one color pair per pixel *row* within a column,
not per 8x8 block. Two pixels one row apart, in the same column, can
now hold completely different colors with no clash at all:

```forth
HIRES
1 INK  10 20 PLOT
6 INK  10 21 PLOT
```

- **Comparing the Two Modes:** In Normal mode those two `PLOT`s would
  fight over one shared cell attribute — whichever `INK` ran last
  would silently win, and BOTH pixels would end up that color. In
  `HIRES`, they don't: pixel (10, 20) stays ink 1, pixel (10, 21) stays
  ink 6, because each pixel row now carries its own color memory.

`PLOT`, `LINE`, and `CIRCLE` all work exactly as before once `HIRES`
is active — nothing about calling them changes. `NORMAL` switches back:

```forth
NORMAL
```

Two things behave a little differently while `HIRES` is active, both
worth knowing before you hit them by surprise:

- **`FILL` refuses to run.** `HIRES`'s own per-row color memory lives
  in the same physical memory `FILL` borrows as scratch space while it
  works, so running both at once would let one corrupt the other's
  data. Rather than risk that, `FILL` simply does nothing — no crash,
  no error printed, just a silent no-op — for as long as `HIRES` is
  active. Switch back to `NORMAL` first if you need `FILL`.
- **`CLS` still clears the screen, colors included** — it resets every
  pixel row's color back to whatever `PAPER`/`INK` are currently set
  to, exactly like Normal mode's `CLS` already does for its own 8x8
  cells.

### Talking to the Hardware Directly: `IN` and `OUT`

There's one more level down, and `SOUND` is the perfect way in to it.
The machine's chips aren't reached through memory addresses like
[section 5](#5-reading-and-writing-memory-directly)'s `@` and `!`. They
sit on a separate set of numbered **ports**, and two words reach them:

| Word  | Stack effect        | What it does              |
| ----- | --------------------- | ---------------------------- |
| `IN`  | `( port -- value )` | Read one byte from `port` |
| `OUT` | `( value port -- )` | Write one byte to `port`  |

- **Argument Order:** Note `OUT`'s order — value first, then port —
  which is deliberately the same shape as `!`'s `( n addr -- )` from
  section 5, and remembered the same way: the parcel first, the
  address you're sending it to last.

Every word in the table at the top of this section is ultimately built
out of these. `SOUND` is barely more than two `OUT`s: the sound chip
listens on port 245 for "which register am I about to talk about" and
port 246 for the value itself, so

```forth
2 251 SOUND
```

and

```forth
2 245 OUT  251 246 OUT
```

do exactly the same thing to exactly the same chip. `IN` then reads
back what a register currently holds, which `SOUND` has no way to do at
all:

```forth
8 245 OUT      \ select the sound chip's register 8
12 246 OUT     \ write 12 into it
8 245 OUT      \ select register 8 again, ready to read
246 IN .       \ prints 12 -- the value really is in the chip
```

- **No Guard Rails:** These two are the sharpest tools here, and they
  have no guard rails whatsoever. There's no check on the port number,
  no list of ports that are off limits, and no way to undo a write:
  whatever the hardware does when it sees that byte is what happens.
  Writing to a port you haven't looked up can lock the machine up hard
  enough to need switching off. That's the same deal `@` and `!`
  already offer for memory, and the same one real BASIC's own `IN`/
  `OUT` offer on this machine — a deliberate choice to leave the
  hardware reachable rather than fenced off, on the understanding that
  you know which port you're poking.

### Custom Characters: `UDG`

Every character `EMIT` can print — letters, digits, punctuation — is a
fixed 8x8 pixel shape baked into the ROM. Codes 144 through 164 are
different: they're wired to 21 blank slots you can draw into yourself,
called **UDGs** ("user-defined graphics"), the same feature and the
same name real Sinclair BASIC offers.

`UDG ( n -- addr )` takes a slot number, 0-20, and gives you back the
address of that slot's 8 bytes — one byte per pixel row, top to bottom,
each bit a pixel across the row (leftmost bit is the leftmost pixel).
From there it's just `C!`, exactly like any other byte in memory from
[section 5](#5-reading-and-writing-memory-directly):

```forth
24  0 UDG        C!
60  0 UDG 1 +    C!
126 0 UDG 2 +    C!
255 0 UDG 3 +    C!
24  0 UDG 4 +    C!
24  0 UDG 5 +    C!
24  0 UDG 6 +    C!
24  0 UDG 7 +    C!

144 EMIT          \ prints an upward-pointing arrow
```

- **Reading the Bytes as a Shape:** Read those eight bytes as bits and
  the shape falls out: `24` is `00011000`, `60` is `00111100`, `126` is
  `01111110`, `255` is `11111111` — a triangle that widens row by row —
  then four more `24`s stack a narrow stem underneath it. Slot `0` maps
  to character code `144`, slot `1` to `145`, and so on up to slot `20`
  at `164`; once a slot is filled in, `EMIT`-ing its code prints it
  exactly like any built-in character, in whatever `INK`/`PAPER` are
  currently set, with no separate "graphics mode" to switch into.

- **No Range Check:** There's no check on `n` — asking for slot `25`
  computes an address past the real table and lets you read or write
  it anyway, the same trusting contract `@`/`!`/`C@`/`C!` already keep.
  Stay inside 0-20 and it's exactly as safe as poking any other array
  this document has shown you.

### Getting Input: `KEY`, `KEY?`, and `STICK`

`KEY` is `EMIT`'s opposite. Instead of printing a character, it waits
for you to press one key and leaves its code on the stack.

```forth
KEY .     \ waits for a keypress, then prints its character code
```

- **`KEY?` Checks Without Waiting:** The operative word above is
  **waits**: your program stops until you press something. For a game
  loop that has to keep moving whether or not a key is currently down,
  `KEY? ( -- flag )` checks without waiting, leaving a true/false flag
  instead of a character code:

  ```forth
  KEY? IF KEY . THEN     \ only reads (and prints) a key if one's ready
  ```

  Checking with `KEY?` never consumes the keypress the way `KEY` does.
  That's what makes this the standard idiom for "read a key only if
  one's waiting" — `KEY?` genuinely just peeks, so a key you check for
  is still there for `KEY` to read afterward.

`BREAK? ( -- flag )` checks for one specific combination instead of
any key: the real Sinclair CAPS SHIFT+SPACE BREAK keys. It's completely
independent of `KEY`/`KEY?` — checking it never consumes or disturbs
whatever those are tracking — so it's meant for a different job:
making your own long-running loop abortable, the same way pressing
BREAK stops a running BASIC program.

```forth
: COUNT-FOREVER  0 BEGIN 1+ DUP . BREAK? UNTIL ;
```

- **Why `BREAK?` Belongs in the Test:** Without the `BREAK?` in its
  `UNTIL` test, that loop would never stop on its own. With it,
  holding CAPS SHIFT+SPACE ends it on the next pass — the loop keeps
  counting exactly as before, and now has a way out.

Combine plain `KEY` with [section 8](#8-repeating-yourself)'s
`BEGIN`/`UNTIL` and you get the standard "wait for a specific key"
idiom — the keyboard equivalent of `COUNTDOWN`'s loop-until-zero:

```forth
: WAIT-FOR-Q  BEGIN KEY 81 = UNTIL ;

WAIT-FOR-Q     \ nothing else happens until you press Q
```

- **Reading `WAIT-FOR-Q`:** `KEY` blocks and hands back one character
  code each pass; `81` is `Q`'s character code (the same code-number
  idea `65 CHR` used for `A` back in
  [Strings](#5-reading-and-writing-memory-directly)); `=` turns that
  into a flag; and `UNTIL` loops for as long as the flag is false,
  exactly the way it did in `COUNTDOWN`. Only what's driving the loop
  has changed — a keypress instead of arithmetic — the loop machinery
  itself is identical.

`STICK ( device -- value )` reads a joystick, with `device` being 1 or
2. Device 1 reports a full 4-bit direction (which way, if any, is
pushed); device 2 reports a single on/off bit. With nothing connected
— true of every setup this has been tested against so far — both
always read `0`.

### Reading a Whole Line: `ACCEPT` and `INPUT`

`KEY` reads one keypress at a time, which is useful for reacting to
individual keys and tedious for something like "ask the player to type
their name." `ACCEPT` reads a whole LINE: give it a buffer address and
a maximum length, and it returns however many characters were actually
typed once you press Enter.

```forth
10 STRING NAME
NAME 1 + 10 ACCEPT NAME C!    \ waits for you to type, echoing as you
                              \ go; store the length in NAME's own
                              \ count byte once you press Enter
NAME COUNT TYPE               \ prints back whatever you typed
```

- **Where the Buffer Address Comes From:** `NAME 1 +` is `STRING`'s
  own data area, skipping past its count byte — see
  [Arrays](#5-reading-and-writing-memory-directly)'s own section on
  memory addresses for why `+` is how you get there. Delete and
  backspace work while typing, and typing past the buffer's limit is
  simply ignored rather than causing an error.

`INPUT` is a shortcut for the most common case, reading a single typed
number:

```forth
INPUT .    \ waits for you to type a number, then prints it back
```

- **What `INPUT` Does Underneath:** `INPUT` reads a line the way
  `ACCEPT` does, parses it with `VAL` (see
  [Strings](#5-reading-and-writing-memory-directly)), and leaves the
  result on the stack — exactly BASIC's `INPUT A` for a single numeric
  variable, spelled as a word instead of a statement.

Put both together and you have the standard small-program shape:
gather some text, gather a number, use both.

```forth
10 STRING NAME

." WHAT IS YOUR NAME? "
NAME 1 + 10 ACCEPT NAME C!
." HELLO, " NAME COUNT TYPE ." !" CR

." HOW OLD ARE YOU? "
INPUT 1 + .          \ next year's age
```

- **What's Actually New Here:** Nothing in there is new — `STRING`/
  `ACCEPT`/`COUNT`/`TYPE` are exactly the pattern shown just above, and
  `INPUT` behaves exactly as just described. What's new is only the
  shape: a real program almost always alternates asking for something
  and using what came back, rather than gathering all its input up
  front the way a first, isolated example tends to suggest.

### Summary

- **Core Concepts:** Graphics and sound words are thin, single-purpose
  actions with no drawing state to set up beyond their own arguments —
  except `INK`, `PAPER`, `BRIGHT`, and `FLASH`, which persist until
  changed and apply to printed text as well as to drawing. Four
  independent screen colour mechanisms, each its own bit, none
  disturbing the others. Ports as a separate numbered space from
  memory, reached with no guard rails at all. Characters you define
  yourself. Reading the keyboard one key at a time, without waiting,
  or a whole line at a time.

- **Forth Words:** `PLOT`, `LINE`, `CIRCLE`, `FILL`, `CLS`, `BORDER`,
  `INK`, `PAPER`, `BRIGHT`, `FLASH`, `AT-XY`, `HIRES`, `NORMAL`,
  `BEEP`, `SOUND`, `TONE`, `VOLUME`, `MIXER`, `NOISE`, `ENVELOPE`,
  `IN`, `OUT`, `UDG`, `KEY`, `KEY?`, `BREAK?`, `STICK`, `ACCEPT`,
  `INPUT`. `RECT`, `POLYGON`, `POLYGON-FILL`, `SPRITE-DEFINE`,
  `SPRITE-SHOW`, and `SPRITE-HIDE` too, dispatched through the
  separate EXROM.

### Exercises

1. Type the four-line `OUT`/`IN` sound-register round trip above,
   exactly as printed. It is the first thing in this document where you
   can *observe* a piece of hardware outside the processor remembering
   something for you. Then do it again with a different register and a
   different value — register 8 is channel A's volume, so anything from
   0 to 15 is a sensible thing to store there — and confirm you read
   back whatever you wrote.

2. Write a word `BAR` that clears the screen and then draws the eight
   available colours as eight blocks across the top row. (Hint:
   `AT-XY` moves the printing position, `PAPER` sets the background
   colour that the *next* thing printed will carry with it, and
   printing a single `SPACE` is enough to colour one cell. A `DO` loop
   supplies both the colour number and the column.) Then extend it so
   each colour is a block several rows deep rather than one cell.

3. `BEEP` takes a whole number of semitones and a decimal duration, so
   a loop can walk up a scale. Type
   
   ```forth
   : SCALE  13 0 DO  I 0.2 BEEP  LOOP ;
   ```
   
   and run it. That is a chromatic octave from middle C. Now change the
   `13 0` to `13 0 DO ... 2 +LOOP` and listen to what stepping by two
   semitones instead of one gives you.

4. `STICK` reads a joystick, and with nothing plugged in both devices
   read `0`. Run `1 STICK .` and `2 STICK .` and confirm that. Knowing
   what "nothing attached" looks like is what lets a program tell it
   apart from a stick that is attached but centred.

5. The `HIRES` section above says two pixels one row apart in the same
   column can hold different colours in `HIRES` and cannot in `NORMAL`.
   Run the two `PLOT`s from that example in `NORMAL` mode first, and
   look closely at the result before switching to `HIRES` and running
   them again. In `NORMAL` you should see both pixels take whichever
   `INK` ran last; that is the colour clash the section describes.

6. Design your own character in a `UDG` slot. Draw an 8x8 shape on
   squared paper, read each row off as an eight-bit number, and `C!`
   the eight values into slot 1 — which is character code 145. Then
   print it, and print it again after changing `INK`, to confirm a UDG
   is coloured exactly like any built-in character.

---

## 11. Variables, constants, and comparisons in combination

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

Trace `TICK` once, since it does two things in one line that are easy
to gloss over: `COUNT @ 1 +` reads the stored count and adds one — an
ordinary `VARIABLE` read, exactly like `SCORE @` in section 5 — and
then `DUP COUNT !` makes a spare copy *before* storing, the same
"copy before you consume it" habit as section 1's `OVER OVER` example,
because `!` would otherwise eat the very value `TICK` is supposed to
leave behind for whoever called it.

```
you type   stack after   COUNT afterward
--------   -----------   ---------------
TICK       [1]           1     -- COUNT @ was 0, +1, DUP'd, then stored
TICK       [2]           2
TICK       [3]           3
```

A second example puts the same pieces to slightly more realistic
use — remembering the best of several scores, rather than just
counting:

```forth
VARIABLE HIGH
0 HIGH !

: MAYBE-RECORD  ( score -- )  DUP HIGH @ > IF HIGH ! ELSE DROP THEN ;

50 MAYBE-RECORD   HIGH @ .    \ prints 50 -- beat the starting 0
30 MAYBE-RECORD   HIGH @ .    \ prints 50 still -- 30 didn't beat it
75 MAYBE-RECORD   HIGH @ .    \ prints 75 -- a new high score
```

This is the `?PRINT` shape from [section
7](#7-making-decisions-if-else-then) again: `DUP` makes a spare copy
of the score before `HIGH @ >` consumes one of them to test it, so if
the test passes, the *original* score is still there for `HIGH !` to
store. Skip the `DUP` and `MAYBE-RECORD` would have nothing left to
record with by the time it decided the score was worth keeping.

Worth writing out longhand once, because that combination of copying,
testing, branching and tidying up is the pattern half this document has
been building toward. But "keep the larger of two numbers" is common
enough to have its own word, and [section 4](#4-numbers)'s `MAX` does
the entire job in one:

```forth
: MAYBE-RECORD  ( score -- )  HIGH @ MAX HIGH ! ;
```

`HIGH @` puts the current record on top of the incoming score, `MAX`
throws away whichever of the two is smaller, and `HIGH !` stores what's
left. No `DUP`, no `IF`, no `DROP`, and nothing to get wrong on the
branch you weren't thinking about. Both versions behave identically on
the three lines above; the second is what you'd actually write.

### Choosing a word to run at runtime

[Section 2](#2-defining-your-own-words) introduced `'` and `EXECUTE`
with an example that deliberately did nothing more than call `DOUBLE`
indirectly — the same thing typing `DOUBLE` would have done, just to
show the mechanism working. Here's the case that actually motivates
them: picking *which* word to run based on a value, rather than always
running the same one.

```forth
: UP    1 + ;
: DOWN  1 - ;

VARIABLE OP

' UP OP !
5 OP @ EXECUTE .      \ prints 6 -- OP currently holds UP's xt

' DOWN OP !
5 OP @ EXECUTE .      \ prints 4 -- same line, OP now holds DOWN's xt
```

`OP` is an ordinary `VARIABLE`, storing an ordinary number — it just so
happens that the number is an execution token instead of a score or a
count. `' UP OP !` looks `UP` up and stores its `xt`; `OP @ EXECUTE`
reads that `xt` back and calls whatever it identifies. The line that
runs — `OP @ EXECUTE .` — never changes; what it *does* changes,
because what's sitting in `OP` changed underneath it. Compare that with
`MAYBE-RECORD` just above: there, an `IF` chose between two fixed
actions written directly into the definition. Here, the choice itself
is data, decided once (by whatever stores an `xt` into `OP`) and used
somewhere else entirely (by whatever later runs `OP @ EXECUTE`) — the
two don't have to be the same word, or even know about each other,
which is exactly what "pass a word around as a value" was promising
back in section 2.

### Summary

No new words except a reminder of `'` and `EXECUTE` from section 2.
`VARIABLE`, `@`, `!`, `DUP`, `+`, `>`, `MAX` and `IF`/`ELSE`/`THEN` from
earlier sections, combined the way a real program combines them. The
habit of copying a value before something consumes it, the habit of
looking for a word that does the whole job before writing the long
version, and storing an execution token in a `VARIABLE` to choose which
word runs at runtime instead of hard-coding the choice with `IF`.

### Exercises

1. Write `MAYBE-LOW`, the mirror of `MAYBE-RECORD`, that remembers the
   *smallest* score seen. Use `MIN`. Then work out why `0 LOW !` is the
   wrong way to start it off, and what to store instead. (Section 4's
   exercise about the range of a whole number is the clue.)

2. `TICK` and `DONE?` above are separate words. Write `TICK-LIMITED`,
   which ticks the counter only while `DONE?` is still false and does
   nothing once the limit is passed. Check that calling it ten times
   leaves `COUNT` at 6 rather than 10.

3. Add `RESET`, a word that puts `COUNT` back to zero, and confirm with
   `COUNT @ .` before and after. It is one line, and writing it makes
   the point that a `VARIABLE` is just a named address — nothing about
   it remembers that only `TICK` is supposed to change it.

4. Add a third word, `SAME  ( n -- n )`, that leaves its input
   unchanged, to the `UP`/`DOWN` example above. Store `' SAME` in `OP`
   and run `5 OP @ EXECUTE .` — it should print `5`. This is the same
   trick `?DUP` uses internally (do nothing on one branch, something on
   the other) but visible now as a word you can point `OP` at, rather
   than a decision buried inside `IF`.

5. `MAYBE-RECORD` throws the score away once it has compared it. Write
   a version that also counts how many scores have beaten the record so
   far, in a second `VARIABLE`. You will need the branching version
   rather than the `MAX` one — which is a fair illustration of why both
   spellings are worth knowing.

---

## 12. Saving and loading your work

Programs don't have to be retyped every time the machine starts.
`SAVE-LIB` and `LOAD-LIB` write your definitions to tape and read them
back.

```forth
: DOUBLER DUP + ;
SAVE-LIB MYPROG
```

`SAVE-LIB` takes the name that follows it — not a word to look up, but
a name, the same way `:` treats the name right after it as something
to define rather than run — and writes everything you've defined so
far to tape under it. Later, even after switching the machine off and
back on, which forgets everything you defined, you can get it back:

```forth
LOAD-LIB MYPROG
4 DOUBLER
```

`LOAD-LIB MYPROG` restores your definitions exactly as they were,
`DOUBLER` included, ready to use immediately as though you'd just
typed it in again. `LOAD-LIB` with no name at all loads whatever was
saved most recently, so you don't have to remember or retype the name.

There's no partial saving or loading of a single definition —
`SAVE-LIB` always writes everything defined up to that point, in one
piece.

That "up to that point" is worth seeing fail once, since it's obvious
in hindsight and easy to get bitten by in practice:

```forth
: DOUBLE  DUP + ;
: QUADRUPLE  DOUBLE DOUBLE ;
SAVE-LIB MYWORDS

: TRIPLE  DUP DUP + + ;      \ defined AFTER the SAVE-LIB above
3 TRIPLE .                   \ prints 9 -- works fine, right now
```

`TRIPLE` works perfectly well for the rest of this session — nothing
about defining it after a `SAVE-LIB` stops it running right now. But
`SAVE-LIB` had already finished by the time you typed it, so `TRIPLE`
was never written to tape. Switch the machine off, back on, and
`LOAD-LIB MYWORDS` back, and you'd get `DOUBLE` and `QUADRUPLE` again
exactly as saved — and no `TRIPLE` at all, because as far as that
particular tape is concerned, it doesn't exist. If you want your work
checkpointed at meaningful moments, that's a matter of when you choose
to run `SAVE-LIB` again — here, after defining `TRIPLE` too — not
something 2068-Leap-Forth tracks for you.

There's a real ceiling on how much `SAVE-LIB` can write in one piece:
8,190 bytes of compiled dictionary. Go past it and `SAVE-LIB` throws
error `-8` (ANS Forth's own standard "dictionary overflow" code —
see [section 14](#14-error-handling-throw-and-catch) for catching
errors like this yourself) rather than writing anything at all. That's
a deliberate, checked refusal, not an arbitrary inconvenience: an
earlier version of `SAVE-LIB` copied your whole dictionary into a
fixed-size scratch buffer with no such check, and would have silently
corrupted nearby memory instead of stopping cleanly, for anyone whose
programs grew past a much smaller, undocumented limit.

### `SAVE-TEXT` and `LOAD-TEXT`: saving the source itself

`SAVE-LIB`/`LOAD-LIB` save a **compiled dictionary image** — the actual
bytes `:` produced, tied to the exact ROM that compiled them. That's
fast, but it means a tape saved by one build of 2068-Leap-Forth isn't
promised to load correctly into a different one.

`SAVE-TEXT ( addr len "name" -- )` and `LOAD-TEXT ( "name" -- )` save
something different: the **plain source text** of a program, exactly
as you'd type it. Where `SAVE-LIB`/`LOAD-LIB` need no addresses at all
(they already know where the dictionary lives), `SAVE-TEXT` takes an
address and length on the stack — wherever your program's source text
already sits in memory — the same `( addr len -- )` shape
[section 5](#5-reading-and-writing-memory-directly)'s string words use:

```forth
S" : DOUBLER DUP + ;" SAVE-TEXT PROGTEXT
```

Loading it back doesn't just restore a dictionary snapshot — it
**re-runs the interpreter over the saved text**, exactly as if you'd
typed it at the prompt:

```forth
LOAD-TEXT PROGTEXT
4 DOUBLER .     \ prints 8
```

That re-parsing is the whole point: source text has no dependency on
which exact ROM build produced it, so it survives a rebuild of
2068-Leap-Forth itself in a way a `SAVE-LIB` image doesn't promise to. The
trade-off is speed and size — re-parsing and recompiling real source is
slower than restoring a ready-made binary image — which is why both
mechanisms exist side by side rather than one replacing the other.

### Summary

Two different things can be saved to tape: a compiled dictionary image,
which is fast but tied to the exact ROM that built it, and plain source
text, which is slower to load but survives a rebuild because loading it
simply re-runs the interpreter over it. Both take the name that follows
them rather than a value from the stack. `SAVE-LIB` always writes
everything defined up to that moment, and never part of it.

Forth words `SAVE-LIB`, `LOAD-LIB`, `SAVE-TEXT`, `LOAD-TEXT`.

### Exercises

1. Reproduce the `TRIPLE` trap above deliberately, and then fix it:
   define two words, `SAVE-LIB` them, define a third, and `SAVE-LIB`
   again under a *second* name. You now have two tapes that differ by
   one word. Loading either one tells you exactly what "everything
   defined up to that point" means.

2. `LOAD-LIB` with no name at all loads whatever was saved most
   recently. Try it, having saved something a moment before, and
   confirm you get your definitions back without retyping the name.

3. `SAVE-TEXT` saves whatever address and length you hand it, and a
   string literal is an address and a length. Save a source string
   containing *two* definitions at once —
   
   ```forth
   S" : DOUBLER DUP + ; : QUADER DOUBLER DOUBLER ;" SAVE-TEXT PROG2
   ```
   
   — then `LOAD-TEXT PROG2` and check that both words exist afterwards.
   This is the difference from `SAVE-LIB` in one line: what came back
   was recompiled from text, not restored from an image.

4. Run `FREE .` from section 5 before and after a `LOAD-LIB`. The
   number changes, and by roughly the size of what you loaded — which
   is a useful sanity check that a load actually did something.

---

## 13. A wider screen

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

`64COL` is also a genuinely wider **text** display now: `EMIT`, `.`,
`."`, and typing at the prompt itself all automatically wrap at column
64 instead of 32 while `64COL` is active, no separate word needed —
the same 8-pixel font, just drawn across twice the width:

```forth
64COL
." THIS LINE NOW WRAPS AT 64 COLUMNS INSTEAD OF 32, TWICE AS MUCH ROOM "
32COL
." BACK TO THE NORMAL 32-COLUMN WIDTH"
```

Typing at the prompt works the same way — a line you're typing wraps
at 64 columns instead of 32 while `64COL` is active, cursor included.
One real difference from the normal-width cursor: the 64-column
cursor is a solid block that stays **on** rather than blinking. Mode 6
(the hardware mode `64COL` switches to) has no per-cell color memory
at all — the normal cursor's blink comes from the real ULA hardware's
own FLASH bit, which lives in that per-cell color byte, so there's
nothing for a 64-column cursor to hook into. You'll always be able to
see where it is; it just won't flash.

`INK`/`PAPER` don't apply per-character in `64COL` mode either, for
the same reason — `PALETTE64` (above) is how `64COL` picks its one
shared color pair instead.

Because `PLOT64` is an ordinary word once `64COL` has switched modes,
[section 8](#8-repeating-yourself)'s `DO`/`LOOP` works on it exactly
as it did on `CIRCLE` in [section 10](#10-drawing-and-sound) — a row of ten points,
spaced out across the wider coordinate range this mode gives you:

```forth
64COL
3 PALETTE64
420 20 DO I 96 PLOT64 40 +LOOP
32COL
```

This is the same `+LOOP`-steps-the-index trick [Drawing and
sound](#10-drawing-and-sound)'s `DOTS` used, just reaching further along
the row — ten points, `I` running 20, 60, 100, ... up to 380,
comfortably inside `PLOT64`'s wider 0-511 range and well past what the
normal screen's own coordinates could reach.

### A Caveat on 64-Column Visual Rendering

While `PLOT64`'s underlying logic is completely solid—confirmed byte-for-byte across independent emulators like **Fuse** and **ZEsarUX**, which agree on exactly which bit in memory changes—its on-screen visual appearance comes with one important caveat:

- **Memory vs. Display:** Both emulators render 64-column mode's entire drawing area as a flat, uniform color rather than showing the individual pixels a real Timex Sinclair 2068 hardware would display.

- **The Reason:** Because 64-column mode was rarely utilized in 1980s software, neither emulator ever invested engineering effort into rendering it accurately. This is an emulator limitation, not an error in `PLOT64` itself.

Treat `64COL`'s visual on-screen appearance as **unverified**. However, everything else about its operation—such as which pixel gets set and at which memory address—is entirely reliable, functioning just as solidly as the standard-screen `PLOT`, `LINE`, and `CIRCLE` commands.

### Summary

A second screen mode, twice as wide. It is both a wider pixel display,
with x running to 511, and a wider text display, with `EMIT` and the
prompt itself wrapping at column 64 with no extra word needed. It has
no per-cell colour memory, so `INK`/`PAPER` don't apply and the cursor
doesn't blink; one shared colour pair is chosen with `PALETTE64`
instead.

Forth words `64COL`, `32COL`, `PALETTE64`, `PLOT64`.

### Exercises

1. Print the same long line of text twice, once in each mode, and count
   where each one wraps:
   
   ```forth
   32COL 60 SPACES 42 EMIT CR
   64COL 60 SPACES 42 EMIT CR
   32COL
   ```
   
   Nothing about the printing changed — only the width the same `EMIT`
   wraps at.

2. `PLOT64`'s x coordinate runs to 511, past anything the normal screen
   can address. Plot a point at x = 400 and satisfy yourself that it is
   accepted rather than refused or wrapped. (Remember the caveat above:
   what is confirmed is which pixel in memory changes, not necessarily
   what an emulator draws for you.)

3. Type a long line at the prompt itself while `64COL` is active, and
   watch where it wraps and what the cursor looks like. Compare with
   the same line typed after `32COL`. The cursor difference is the one
   described above, and it is a property of the hardware mode rather
   than of this Forth.

4. Try several values of `PALETTE64` with the same `PLOT64` point on
   screen, and confirm that the colour applies to the whole display at
   once rather than to the point you last drew — which is exactly what
   "no per-cell colour memory" means in practice.

---

## 14. Error handling: THROW and CATCH

[Section 3](#3-understanding-system-feedback--errors) covered the
defaults when something goes wrong: `?` for an unrecognized word,
`STACK?` for a stack mistake, both
abandoning the rest of the current line and dropping you at a fresh
prompt. That's the right behavior while you're typing interactively.
A real *program*, though, often wants to notice a problem itself and
keep running under its own control — trying something risky with a
planned fallback if it doesn't work out, rather than stopping
outright.

`THROW` and `CATCH` do exactly that:

| Word    | Stack effect       | What it does                                                                                                      |
| ------- | ------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `CATCH` | `( xt -- 0 \| n )` | Run the word `xt` identifies. `0` if it finished normally; the thrown value `n` if it `THROW`ed instead           |
| `THROW` | `( n -- )`         | `0` does nothing at all. Any other `n` abandons whatever's currently running and hands `n` to the nearest `CATCH` |

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

### A more realistic example: choosing to reject bad input

`RISKY` above always throws, which makes the mechanism easy to see but
isn't how `THROW` gets used in practice. More often, a word throws
only *sometimes*, guarding against one specific bad case while working
normally otherwise — the same `IF`-guarded shape [section
6](#7-making-decisions-if-else-then) built `?PRINT` out of.

Section 4's `SQRT` never complains about a negative input on its own —
its negative case just silently returns `0`, the same safe-default
convention `VAL` uses for unparseable text. Suppose your own program
wants that treated as a real mistake instead of quietly swept under
the rug. `THROW` lets you build exactly that policy on top of a word
that doesn't have it built in, without touching `SQRT` itself:

```forth
: STRICT-SQRT  ( n -- root )  DUP 0 < IF -1 THROW THEN  SQRT ;

: TRY-SQRT  ( n -- )
  ' STRICT-SQRT CATCH
  IF ." NEGATIVE -- REFUSING" CR DROP
  ELSE . THEN ;

16 TRY-SQRT      \ prints 4
-9 TRY-SQRT      \ prints NEGATIVE -- REFUSING -- plain SQRT would
                 \ have just handed back 0 here instead, no complaint
```

`STRICT-SQRT` is the `?PRINT` pattern again: `DUP` makes a spare copy
of `n` before testing it, so if the test finds nothing wrong, the
*original* is still sitting there for `SQRT` to use afterward. Only
when the test fails does anything unusual happen — a `THROW` that
unwinds straight past the rest of `STRICT-SQRT`, past `SQRT` itself
(which never runs at all in that case), and lands in `TRY-SQRT`'s
`CATCH`, exactly the way `CATCH`'s own description above said it
would.

`THROW`ing with no `CATCH` anywhere to reach falls back to the reset
this document already described: both stacks emptied, `STACK?`
printed, and you're back at a fresh prompt, exactly as with an actual
stack mistake. `CATCH` doesn't replace that default; it gives a
program the option to intercept an error *before* it reaches that
point, for whichever specific problems the program knows how to
recover from. Anything it doesn't catch still falls through to the
usual reset, same as always.

### Giving up on purpose: `ABORT` and `QUIT`

That fallback — abandon everything, come back to a fresh prompt — is
useful enough that you can ask for it deliberately, without an error
having happened at all.

| Word    | Stack effect | What it does                                                              |
| ------- | ------------ | ------------------------------------------------------------------------- |
| `ABORT` | `( -- )`     | Abandon everything and return to the prompt, **clearing both stacks**     |
| `QUIT`  | `( -- )`     | Abandon everything and return to the prompt, **leaving the stacks alone** |

Both stop the current line dead. Nothing after them runs, and nothing
that called them gets resumed — however many definitions deep you were,
you come straight back out to the prompt:

```forth
42 ABORT 99 .     \ the 99 is never pushed and the . never runs
```

The single difference between them is what happens to what you'd
already collected. `ABORT` empties both the ordinary stack and
[section 4](#4-numbers)'s separate decimal stack, so you're back to
genuinely nothing:

```forth
42 ABORT      \ afterwards the stack is empty -- the 42 is gone too
```

`QUIT` abandons the same amount of *execution* and none of the *data*:

```forth
42 QUIT       \ afterwards the stack still holds 42
42 QUIT .     \ the . never runs, so nothing prints -- but type . on
              \ the next line and you'll get your 42 back
```

Which one you want depends on why you're giving up. `ABORT` is the
bigger hammer, for "this went wrong enough that I don't trust anything I
was holding" — it's what the automatic reset behind `STACK?` amounts to,
available as a word. `QUIT` is for stopping cleanly when the data is
fine and only the *doing* needs to stop.

Neither prints anything, which is worth knowing so you're not left
waiting for a message. What you'll notice instead is the absence of the
usual `OK` from [section 3](#3-understanding-system-feedback--errors): a
line that ended in `ABORT` or `QUIT` didn't finish, so it doesn't get
told it did. If you want your program to say why it gave up, print
something yourself just before:

```forth
: CHECK-AGE  ( n -- n )
  DUP 0 < IF ." AGE CANNOT BE NEGATIVE" CR ABORT THEN ;
```

Set that beside `THROW` from earlier in this section, because they
answer two genuinely different questions. `THROW` gives the *caller* a
chance to deal with the problem — some `CATCH` further out may know
exactly what to do and carry on. `ABORT` and `QUIT` don't offer that
choice to anyone: they go all the way out, past every `CATCH`, and end
the line. Reach for `THROW` when a problem might be someone else's to
handle, and for these two when it plainly isn't.

### Summary

A program can intercept its own errors instead of always falling back
to the interpreter's reset. `CATCH` runs a word given as an execution
token and reports whether it finished or threw. `THROW` hands a value
to the nearest `CATCH`, unwinding everything in between; a `THROW` of
zero does nothing at all. `ABORT` and `QUIT` give up unconditionally,
past every `CATCH`, and differ only in what happens to your data.

Forth words `CATCH`, `THROW`, `ABORT`, `QUIT`.

### Exercises

1. Confirm both halves of `THROW`'s description at the prompt. `0
   THROW` on its own should do nothing whatsoever and leave you with
   the usual `OK`. `1 THROW`, with no `CATCH` anywhere to reach, should
   give you the same reset an actual stack mistake does.

2. Show the difference between `ABORT` and `QUIT` for yourself. Push
   two or three numbers, then run each in turn, and afterwards try to
   print what you pushed. One of them gives your numbers back and one
   doesn't.

3. `THROW` reaches the *nearest* `CATCH`, not the outermost one. Set up
   three words to prove it:
   
   ```forth
   : INNER   42 THROW ;
   : MIDDLE  ' INNER CATCH DROP ;
   : OUTER   ' MIDDLE CATCH . ;
   ```
   
   Predict what `OUTER` prints before running it. `MIDDLE` catches the
   throw and returns normally, so what does `OUTER`'s own `CATCH` see?

4. Section 4 noted that dividing by zero quietly returns `0` rather
   than complaining. Build the strict version, the same way
   `STRICT-SQRT` was built on top of `SQRT`: write `SAFE/` that throws
   when the divisor is zero and divides normally otherwise, and a
   `TRY/` that catches it and prints a message instead. (`-10` is the
   standard error number for division by zero, if you want to use a
   meaningful one.)

5. `CHECK-AGE` above prints its message before giving up, because
   `ABORT` prints nothing itself. Delete the `." ..."` from it and run
   it with a negative number. The word still refuses, but now you have
   no idea why — which is the whole argument for printing first.

---

## 15. Printing to a real printer: LPRINT and LLIST

BASIC's `LPRINT` and `LLIST` send output to an attached printer
instead of the screen. 2068-Leap-Forth has the same idea, adapted to the
way this Forth's dictionary works:

| Word     | Stack effect      | What it does                                                                                       |
| -------- | ----------------- | -------------------------------------------------------------------------------------------------- |
| `LPRINT` | `( addr len -- )` | Print a string to the printer, wrapping across multiple printed lines if it's longer than one line |
| `LLIST`  | `( -- )`          | Print the name of every word you've defined since the machine started, newest first                |

```forth
S" HELLO WORLD" LPRINT
```

`LLIST` deliberately does **not** print the 150 built-in words this
Forth ships with — only what you've personally defined, the same way
BASIC's `LLIST` only ever showed *your* program and never anything
built into the ROM. There's also no real equivalent of BASIC's
line-numbered program listing to reproduce in the first place: once a
word is compiled, its original source text isn't kept around, so
`LLIST` shows *what exists*, a list of names, rather than
re-displaying the exact lines you typed.

That "newest first" is worth seeing rather than just taking on faith,
and it's the identical order [section 1](#1-what-forth-actually-is)
already described for how a plain word lookup searches the dictionary
— `LLIST` isn't inventing a new ordering, it's just walking the same
chain out loud:

```forth
: DOUBLE  DUP + ;
: TRIPLE  DUP DUP + + ;
LLIST          \ prints TRIPLE, then DOUBLE -- most recently defined
               \ first, exactly the order a plain lookup of either
               \ name would find them in
```

`VLIST` from [section 3](#seeing-what-words-exist-vlist) is the
same walk sent to the screen instead, and without the stop at the
built-ins — `LLIST` for a paper record of your program, `VLIST` for a
look at the whole dictionary while you're working.

### Summary

The same idea as BASIC's printer words, adapted to a dictionary. A
string goes to the printer as an address and a length, exactly as it
goes to the screen. `LLIST` lists the names of *your* words only,
stopping at the built-ins, because a compiled word no longer has any
source text to reproduce.

Forth words `LPRINT`, `LLIST`.

### Exercises

These need a printer attached, or an emulator started with printer
support — see the status note above.

1. `LPRINT` a string longer than one printed line and confirm it wraps
   onto a second line rather than being cut off.

2. Run `LLIST` on a freshly started machine, before defining anything
   at all. It should print nothing, because you have defined nothing —
   the built-ins are exactly what it stops at.

3. Now define three words and run `LLIST` again. Check the order
   against the order you defined them in; it is reversed, for the
   reason given above.

4. `LPRINT` takes an address and a length, and `S"` is not the only
   thing that produces one. Set up a `STRING` buffer from section 5,
   `PLACE` some text into it, and print it with `COUNT LPRINT`. The
   printer neither knows nor cares where the pair came from.

---

## 16. ULAPlus: a bigger color palette

Every color word covered so far — `INK`, `PAPER`, `BORDER` — picks
from the same fixed 8 colors the hardware has always had. ULAPlus is
an extension that replaces those 8 with 64 colors *you* choose,
without changing how
`INK`/`PAPER`/`PLOT`/`LINE`/`CIRCLE`/`FILL` are used at all.

| Word      | Stack effect         | What it does                                                                |
| --------- | -------------------- | --------------------------------------------------------------------------- |
| `ULAPLUS` | `( flag -- )`        | Nonzero enables the extended palette; zero reverts to the standard 8 colors |
| `PALETTE` | `( index value -- )` | Program palette register `index` (0-63) with color `value`                  |

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

`ULAPLUS` and `PALETTE` are also independent of each other in a way
worth noticing — the same separation [Drawing and
sound](#10-drawing-and-sound) pointed out for `INK` and `PAPER`, where
each touches only its own half of the state. `ULAPLUS` writes only the
enable bit; the 64 palette registers `PALETTE` programs are a
completely separate part of the chip, and switching the enable bit off
and back on never touches them:

```forth
0 ULAPLUS         \ back to the standard 8 colors -- color 2 is
                  \ ordinary red again
1 ULAPLUS         \ switch the extended palette back on -- color 2 is
                  \ bright yellow again too, with no PALETTE call in
                  \ between: register 2 was never touched, only
                  \ whether the hardware is currently reading it
```

A stock, unmodified Timex Sinclair 2068 does not natively support **ULAplus**. Because ULAplus is a hardware specification rather than a built-in feature, it requires implementation either as a physical replacement chip for an existing ULA, inside an emulator, or via modern FPGA hardware like the ZX Spectrum Next.

Add-on hardware for the TS2068—such as the PicoVideo project—exists precisely because the stock machine lacks native support.

### Summary

An extension that replaces the fixed eight colours with 64 you choose,
without changing how any colour word is used. A palette value packs
green, red and blue into one byte as `GGGRRRBB`. Programming the
palette and enabling it are independent of each other. Registers 0 to 7
stand in for the standard eight colours everywhere they are used,
border included, and the swap happens at display time — already-drawn
shapes change colour without being redrawn.

Forth words `ULAPLUS`, `PALETTE`.

### Exercises

These need a ULAplus-capable emulator

1. Work out the palette values for pure red, pure green and pure blue
   from the `GGGRRRBB` layout. (White, with every bit set, is 255 —
   check that one first to confirm you have the packing the right way
   round.) Program each into register 1 in turn and look at the result.

2. Draw a filled circle in colour 2 *first*, and only then run the
   `PALETTE` and `ULAPLUS` lines. The circle should change colour where
   it already sits, with nothing redrawn — which is what "a display-time
   palette swap" means and is not something the standard eight colours
   can do.

3. Toggle `0 ULAPLUS` and `1 ULAPLUS` back and forth several times with
   no `PALETTE` call in between, and confirm your programmed colour
   comes back every time. The registers are not cleared by switching
   the extension off; only whether the hardware reads them changes.

4. Set the border to colour 2 with `BORDER`, then reprogram register 2.
   The border follows, because registers 0 to 7 replace those eight
   colours *everywhere*, not just for drawing.

---

## 17. Growing the dictionary yourself

[Section 2](#2-defining-your-own-words) made a claim worth revisiting
now that you've used the whole language: defining a word *extends the
language*, and your words are no different in kind from the ones Forth
shipped with. Everything since has taken that at face value. This
section makes it literally true, and it's the most genuinely
Forth-shaped idea in this document.

Start from something you've been using since section 5 without
questioning it. `VARIABLE SCORE` creates a word. So does `100 CONSTANT
MAXHEALTH`, and `5 ARRAY SCORES`, and `20 STRING NAME`. Each of them
takes the name that follows it and produces a brand-new word that
behaves in some particular way when you run it — an address for
`VARIABLE`, a value for `CONSTANT`. A word whose job is to make other
words is called a **defining word**, and up to now every one of them
has been built in and fixed.

The question this section answers is: what if the four you were given
aren't the four you want? Say your program is full of pairs of
coordinates, or of counters that always start at 1 rather than 0, or of
lookup tables. In most languages the answer is "write it out longhand
every time." In Forth the answer is to define your own defining word,
and it needs three things: somewhere to put the new word's data, a way
to make the word itself, and a way to say what it does when run.

### Where new words go: `HERE`, `,`, `C,`, and `ALLOT`

`FREE` back in [section 5](#5-reading-and-writing-memory-directly)
reported how much room was left for new definitions, which quietly
implies something this document hasn't said outright: the dictionary is
just a region of memory, and it grows upward, one definition after
another, into the free space above.

`HERE ( -- addr )` is the address of the first *unused* byte in that
region — the frontier, one past everything defined so far. It's an
ordinary address like any other from section 5, and it moves every time
you define anything.

| Word    | Stack effect  | What it does                                             |
| ------- | ------------- | -------------------------------------------------------- |
| `HERE`  | `( -- addr )` | The address of the first unused dictionary byte          |
| `,`     | `( n -- )`    | Write a two-byte cell at `HERE`, and advance `HERE` by 2 |
| `C,`    | `( n -- )`    | Write one byte at `HERE`, and advance `HERE` by 1        |
| `ALLOT` | `( n -- )`    | Advance `HERE` by `n` bytes without writing anything     |

`,` is pronounced "comma", and it is a real word — a lone comma, with
spaces around it like everything else. `C,` is "C-comma", the
byte-sized version, matching the `C@`/`C!` naming from section 5 for
exactly the same reason.

They're easiest to see all at once:

```forth
HERE            \ remember the frontier -- an address, on the stack
1234 ,          \ write 1234 there; HERE has now moved 2 bytes along
@ .             \ prints 1234 -- read back from the address we saved
```

Nothing there is new except the words. `HERE` pushed an address, `,`
wrote a cell at it, and `@` from section 5 read the cell back — the
same fetch you've used on every `VARIABLE` in this document. The only
difference is that nothing gave this cell a name.

`ALLOT` reserves space without filling it, which is what you want for a
buffer you're about to write into:

```forth
HERE            \ the address of what we're about to reserve
20 ALLOT        \ reserve 20 bytes -- HERE jumps 20 further along
```

A negative count legitimately runs the other way and gives space back:

```forth
-4 ALLOT        \ HERE moves back 4 bytes -- the dictionary shrinks
```

which is occasionally handy and worth using carefully, since anything
already defined in the space you just gave back is now in the path of
whatever gets defined next.

When working with low-level memory management primitives (`HERE`, `ALLOT`, and `,`), keep two important caveats in mind:

- **No Capacity Checks:** None of these words check whether there is actually room left in memory. `FREE` exists specifically so a program can check for available space before executing a large `ALLOT`. Otherwise, the system maintains the same strict "trust the caller" posture found in words like `PICK` and `!`.

- **Transient Targets (`HERE`):** The comma word (`,`) writes directly at `HERE`, which only lands where you expect if nothing else has moved `HERE` in the interim. These words are designed for building a definition *right now*, not for stashing data to come back to later.

### Making a word by hand: `CREATE`

`CREATE ( "name" -- )` takes the name that follows it, exactly as `:`
and `VARIABLE` do, and builds a dictionary entry for it. The word it
makes is the simplest one possible: run it, and it pushes the address
of its own data — the memory immediately after it, which is to say
whatever `HERE` was pointing at the moment `CREATE` finished.

`CREATE` reserves none of that data for you. It hands you the frontier
and leaves the filling to `,`, `C,` and `ALLOT`:

```forth
CREATE POINT  0 , 0 ,     \ a word with two cells of its own
5 POINT !                 \ store 5 in the first
7 POINT 2 + !             \ and 7 in the second
POINT @ .                 \ prints 5
POINT 2 + @ .             \ prints 7
```

Look at what that actually is: a two-cell `VARIABLE`, built by hand out
of pieces. `VARIABLE SCORE` and `CREATE SCORE 0 ,` produce words that
behave the same way — push an address, fetch with `@`, store with `!`.
(2068-Leap-Forth's own `VARIABLE` is written directly in machine code rather
than in terms of `CREATE`, for reasons of size; the point is that it
*could* be, and that in most Forths it is.)

Now put `CREATE` inside a colon definition and you have a defining word
of your own:

```forth
: T1  CREATE 1234 , ;

T1 T1FOO         \ makes a new word, T1FOO
T1FOO @ .        \ prints 1234
```

Read `T1` carefully, because two different times are involved and
keeping them apart is the whole skill here. `T1` is defined once. It
*runs* when you type `T1 T1FOO` — and while running, it creates
`T1FOO` and stores 1234 in it. `T1FOO` is what runs later, when you type
`T1FOO`, and all it does is push its own address.

### `DOES>` — saying what the new word should *do*

`T1FOO` pushes an address, and so does every other word `CREATE` makes.
That's the limitation. `CONSTANT` doesn't behave that way: `MAXHEALTH`
gives you the value itself, no `@` required, which was the whole
distinction section 5 drew between it and `VARIABLE`. With `CREATE`
alone you can't build that, because the `@` is left for the caller to
remember every single time.

`DOES>` ("does") removes exactly that limitation. Written inside a
defining word, it separates the part that builds the new word from the
part that says what the new word *does when it runs*:

```forth
: CONST  CREATE , DOES> @ ;

5 CONST FIVE
7 CONST SEVEN

FIVE .        \ prints 5
SEVEN .       \ prints 7
```

That is a working `CONSTANT`, in eleven characters of definition. Take
it apart in the two times again, because everything about `DOES>`
depends on them:

- **When `5 CONST FIVE` runs**: `CREATE` makes a word called `FIVE`;
  `,` writes the `5` that was on the stack into `FIVE`'s data; and
  `DOES>` attaches everything after it — the `@` — to `FIVE` as its
  behavior, then ends `CONST` on the spot.
- **When `FIVE` runs, later**: it pushes its own data address, exactly
  as any `CREATE`d word does, and then runs the `@`. What's left on the
  stack is `5`.

The part after `DOES>` never runs as part of `CONST` itself. It is
`FIVE`'s body, written in the middle of `CONST`'s. And it always starts
with the new word's own data address already on the stack, which is why
`@` on its own is a complete behavior — there's nothing for it to be
handed but that address.

Everything before `DOES>` runs once per new word. Everything after it
runs every time one of those new words is used. `CONST` was invoked
twice above and `FIVE` and `SEVEN` are genuinely separate words with
separate data; nothing is shared but the recipe.

The behavior can be as long as you like, and it doesn't have to ignore
the stack it's given. Here's an array-style defining word — the second
verified example this section is built from — that takes an index and
returns an element:

```forth
: ARR3  CREATE 10 , 20 , 30 , DOES> SWAP CELLS + @ ;

ARR3 NUMS

0 NUMS .      \ prints 10
1 NUMS .      \ prints 20
2 NUMS .      \ prints 30
```

`ARR3 NUMS` runs the three `,`s, so `NUMS` is born holding 10, 20 and
30 in consecutive cells. Then `1 NUMS` runs the behavior with two things
on the stack — the `1` you pushed, and `NUMS`'s own address underneath
it, pushed automatically:

```
you type   stack after
--------   -----------
1          [1]
NUMS       [1, addr]        -- the data address, pushed automatically
SWAP       [addr, 1]        -- put the index on top
CELLS      [addr, 2]        -- index 1 means 2 bytes along
+          [addr+2]         -- the address of element 1
@          [20]             -- and fetch it
```

`SWAP CELLS + @` is section 5's `index CELLS name +` idiom, in a
different order because of where the address arrives, doing precisely
what that section spelled out at length — including the `CELLS`, for
exactly the reason given there: elements are two bytes apart, so index 1
is byte 2. The difference is that here it's written **once**, inside the
defining word, instead of at every use. That's the practical payoff of
this entire section: `1 NUMS` where you'd otherwise write
`1 CELLS NUMS +  @`, and no chance of forgetting the `CELLS`.

### Taking words back: `FORGET`

`FORGET ( "name" -- )` is the eraser. It takes the name that follows
it, and removes that word **and everything defined after it**,
rewinding both the dictionary and `HERE` to exactly where they stood
before that word existed:

```forth
: ZZZ  111 ;
FORGET ZZZ
: ZZZ  222 ;
ZZZ .           \ prints 222
```

The space really is reclaimed, not merely hidden: the second `ZZZ`
lands on exactly the same bytes the first one occupied, and `FREE` from
section 5 reports the room back. That makes `FORGET` the tidy way to
retract a definition you're still iterating on, rather than piling
redefinitions up in memory the way [section
1](#1-what-forth-actually-is)'s newest-first shadowing does.

"And everything defined after it" is not a footnote — it's the main
thing to understand. The dictionary is a stack of definitions, and
`FORGET` pops back to a point, so anything you defined later goes too,
whether or not it had anything to do with the word you named:

```forth
: A  1 ;
: B  2 ;
: C  3 ;
FORGET B        \ B and C are both gone now; A survives
```

There is no way to remove `B` alone. If that matters, `VLIST` from
[section 3](#seeing-what-words-exist-vlist) is the way to see
what you've actually got left afterward.

One real safety behavior, which you'll meet the moment you aim `FORGET`
at the wrong thing. Naming one of this Forth's own built-in words gets
you a refusal rather than an obedient disaster:

```forth
FORGET DUP      \ prints FORGET: BUILT-IN, REFUSED, and changes nothing
5 DUP . .       \ prints 5 5 -- DUP is exactly as it was
```

The reason is worth a sentence, because it's a genuine hazard rather
than a fussy restriction. Built-in words live in ROM, which is
physically unchangeable, so forgetting one could not reclaim a single
byte. Worse, "everything defined after it" would then mean *every word
you have ever defined in this session* — a `FORGET DUP` typed by
mistake would silently wipe your entire program to no purpose at all.
Refusing costs nothing anybody legitimately wants and closes that trap
completely.

A name the dictionary doesn't have at all gets a different message —
`FORGET: NOT FOUND` — and likewise changes nothing. Both are ordinary
printed messages, not errors: the rest of your line carries on running
normally afterward, unlike the resets in section 14.

### Summary

The dictionary is a region of memory that grows upward, and `HERE` is
its frontier. Words that write into that frontier, and one that merely
reserves space in it. Defining words: `CREATE` makes a word that pushes
its own data address, and `DOES>` replaces that behaviour with one you
write, so that everything before `DOES>` runs once per new word and
everything after it runs every time one of those words is used. And an
eraser that rewinds the frontier to a named point.

Forth words `HERE`, `,`, `C,`, `ALLOT`, `CREATE`, `DOES>`, `FORGET`.

### Exercises

1. `C,` is the byte-sized counterpart of `,`, and a table of small
   numbers has no reason to waste two bytes on each. Type
   
   ```forth
   CREATE BYTES  1 C, 2 C, 3 C, 4 C,
   BYTES C@ .
   BYTES 1 + C@ .
   BYTES 3 + C@ .
   ```
   
   Note that the elements are one byte apart, so the offsets are the
   indices themselves and no `CELLS` is involved at all. Then work out
   how many bytes the same four values would have taken written with
   `,` instead, and check your answer with `HERE`.

2. Watch the frontier move. Run `HERE .`, define any small word, and
   run `HERE .` again. The difference is what that definition cost you.
   Do it once more with a longer definition and confirm the number
   grows by more.

3. The start of this section suggested counters that always begin at 1
   rather than 0. Write `ONECOUNTER`, a defining word such that
   `ONECOUNTER FOO` makes a word `FOO` behaving exactly like a
   `VARIABLE` whose cell already contains 1. (It is `CREATE` and one
   `,`.) Check with `FOO @ .`.

4. Now add `DOES> @` to the end of `ONECOUNTER` and define a second
   word with it. The new word pushes the *value* rather than the
   address, so `FOO .` works and `FOO @ .` no longer does. That one
   change is the whole difference between `VARIABLE` and `CONSTANT`,
   written by hand.

5. Define three words `A`, `B` and `C` in that order, run `VLIST` and
   note all three are there, then `FORGET B` and run `VLIST` again.
   Confirm that `C` went too, and that `A` survived. Then try
   `FORGET DUP` and confirm it refuses without changing anything.

---

## 18. A worked example: the Blackjack demo

Everything up to this point has been explored in small, isolated pieces—one new word at a time, each demonstrated with a brief two- or three-line example. **`demos/blackjack.fs`** is the opposite: a complete, fully functional single-deck Blackjack game written in a few hundred lines of ordinary Forth. It plays a full hand against a computer dealer complete with hit/stand logic, correct soft-ace scoring, a real shuffle, and a scored outcome every round.

Nothing in it is a special case built into the language; it is built entirely from the same words covered throughout this document, composed the way real programs are meant to be written.

#### What the Demo Pulls Together

Reading (or building and running) the demo serves as a comprehensive review, as it leans on a wide slice of the system all at once:

- **`VARIABLE`s and `ARRAY`s** (from Section 5) hold the deck and both hands.

- **`DO`/`LOOP`** (from Section 8) handles the shuffle and deal.

- **`IF`/`ELSE`/`THEN`** (from Section 7) scores hands and decides outcomes.

- **Small, single-purpose words** are built from smaller ones and named for what they mean (following Section 3's core design principle).

- **`INK`/`PAPER`/`BORDER`, custom graphics (`UDG`), and `BEEP`/`SOUND`** combine to draw the table and cards and cue each outcome—with card and table colors rendering correctly because `EMIT` respects active color attributes.

This composition is not new material. The value of examining the demo now is seeing familiar words asked to do real work together at a scale a single tutorial example cannot reach.

#### Real-World Testing: The `LOAD-TEXT` Test Payload

The game's source code also doubles as the real test payload for **`LOAD-TEXT`** (and `SAVE-TEXT`). Rather than a toy string, it is a full, real-world program round-tripped over the standard tape protocol used by `SAVE-LIB`/`LOAD-LIB`—including verification via a real cassette-tape round trip in the Fuse emulator (distinct from the automated fake-tape hooks used by the test suite; see `tools/run_realtape_test.sh` if you wish to reproduce that proof yourself).

To build the demo and review its instructions:

- **Build Command:** `make forth-demo-blackjack`

- **Execution:** Refer to the header comment inside `demos/blackjack.fs` for step-by-step instructions on running it in the Fuse emulator.

Here is how to load and play the real game directly from a live prompt, bypassing the standalone boot-straight-into-the-game shortcut:

1. Build the real product ROM (`make forth-boot`) and a real tape file
   containing `demos/blackjack.fs` under the name `BLACKJACK`:
   
   ```
   python3 tools/tape_gen_forth.py build/blackjack.tap BLACKJACK:demos/blackjack.fs
   ```

2. Start Fuse with that tape already inserted:
   
   ```
   fuse --machine ts2068 --detect-loader \
        --rom-ts2068-0 build/forth_boot_rom0.bin \
        --rom-ts2068-1 build/stock_shaped_exrom.bin \
        --tape build/blackjack.tap
   ```
   
   `--detect-loader` matters: some saved Fuse settings ship with
   automatic tape-loader detection turned off, in which case the tape
   never starts playing and `LOAD-TEXT` just waits — passing it
   explicitly here works regardless of what's saved.

3. Once the live prompt appears, type:
   
   ```
   LOAD-TEXT BLACKJACK
   ```
   
   and press Enter. The real leader tone, sync, and every data byte
   play back and get decoded at genuine cassette speed (tens of
   seconds, not instant) — exactly like loading a real BASIC program
   from real tape, just with this project's own native Forth source as
   the payload instead of tokenized BASIC. Once it finishes, the game
   compiles and starts automatically (the loaded text's own last line
   is `SETUP-GLYPHS MAIN`), ready to play with the real keyboard.

### Summary

No new words. A complete program built entirely from the ones this
document has covered, composed the way real Forth composes them: small
single-purpose definitions, each checkable by hand, named for what they
mean, stacked up until the last few read almost like a description of
the game.

### Exercises

These are reading exercises as much as typing ones. Open
`demos/blackjack.fs` beside them.

1. Find `X8` — it is three words long. Work out its stack effect by
   hand from `DUP` and `+` alone, then work out what it is *for* by
   looking at where `CARD-BOX` uses it. It multiplies by eight without
   using `*` at all; decide for yourself whether that was worth doing.

2. Find `GETR`. It is section 5's array idiom exactly — `index CELLS
   name +` followed by a fetch — given a name so that the rest of the
   program never has to write it out. Find `SETR` beside it and confirm
   it is the same phrase ending in `!` instead. Then count how many
   places in the file would have had to repeat that idiom if these two
   words didn't exist.

3. Find `CARDVAL` and work out how it uses `EXIT` to handle three cases
   without a single `ELSE`. Rewrite it on paper with `IF`/`ELSE`/`THEN`
   nesting instead and decide which you find easier to follow. This is
   the trade-off section 8 described when it introduced `EXIT`.

4. Find `PSCORE` and identify the `BEGIN`/`WHILE`/`REPEAT` loop at the
   end of it. That loop is what handles a soft ace — an ace counted as
   11 until doing so would bust the hand, then dropped to 1. Work out
   why the test needs `AND` and what would go wrong if it tested only
   the total.

5. Find `SHUFFLE` and note that it counts *downwards*, with `-1
   +LOOP` — exactly the shape section 8's exercises asked you to write.
   Work out why a shuffle wants to run down rather than up.

6. Load the game with `LOAD-TEXT`, play a round, and then — instead of
   playing again — run `VLIST`. Everything above `MAIN` is the program
   you just loaded, sitting in the same dictionary as `DUP` and `+`,
   exactly as section 3 promised on its first page.

---

## Appendix A: word reference

A quick-lookup table of every word covered in this document, grouped
by topic, in the style of a standard Forth word-set reference — see
[forth-standard.org](https://forth-standard.org/standard/words) for
the same convention applied to the full ANS Forth standard.

**Stack manipulation**

| Word    | Stack effect         |
| ------- | -------------------- |
| `DUP`   | `( n -- n n )`       |
| `SWAP`  | `( a b -- b a )`     |
| `DROP`  | `( n -- )`           |
| `OVER`  | `( a b -- a b a )`   |
| `ROT`   | `( a b c -- b c a )` |
| `2DUP`  | `( a b -- a b a b )` |
| `2DROP` | `( a b -- )`         |
| `?DUP`  | `( n -- 0 \| n n )`  |
| `PICK`  | `( ... n -- ... x )` |

**Arithmetic and comparison**

| Word        | Stack effect         |
| ----------- | -------------------- |
| `+`         | `( a b -- a+b )`     |
| `-`         | `( a b -- a-b )`     |
| `*`         | `( a b -- a*b )`     |
| `/`         | `( a b -- a/b )`     |
| `1+`        | `( n -- n+1 )`       |
| `1-`        | `( n -- n-1 )`       |
| `NEGATE`    | `( n -- -n )`        |
| `MAX`       | `( a b -- max )`     |
| `MIN`       | `( a b -- min )`     |
| `0=`        | `( n -- flag )`      |
| `=`         | `( a b -- flag )`    |
| `<`         | `( a b -- flag )`    |
| `>`         | `( a b -- flag )`    |
| `ABS`       | `( n -- \|n\| )`     |
| `SGN`       | `( n -- -1\|0\|1 )`  |
| `MOD`       | `( a b -- a-mod-b )` |
| `SQRT`      | `( n -- isqrt(n) )`  |
| `RND`       | `( x -- n )`         |
| `RANDOMIZE` | `( n -- )`           |
| `AND`       | `( a b -- a AND b )` |
| `OR`        | `( a b -- a OR b )`  |
| `XOR`       | `( a b -- a XOR b )` |
| `INVERT`    | `( a -- NOT a )`     |

**Decimal (floating-point) arithmetic** — own stack, see section 4

| Word     | Stack effect             |
| -------- | ------------------------ |
| `F+`     | `( f1 f2 -- f1+f2 )`     |
| `F-`     | `( f1 f2 -- f1-f2 )`     |
| `F*`     | `( f1 f2 -- f1*f2 )`     |
| `F/`     | `( f1 f2 -- f1/f2 )`     |
| `FSQRT`  | `( f -- sqrt(f) )`       |
| `FROUND` | `( f -- f' )`            |
| `PI`     | `( -- f )`               |
| `SIN`    | `( f -- sin(f) )`        |
| `COS`    | `( f -- cos(f) )`        |
| `RAD`    | `( degrees -- radians )` |
| `DEG`    | `( radians -- degrees )` |
| `S>F`    | `( n -- )` `( -- f )`    |
| `F>S`    | `( f -- )` `( -- n )`    |
| `F.`     | `( f -- )`               |

**Memory**

| Word       | Stack effect       |
| ---------- | ------------------ |
| `@`        | `( addr -- n )`    |
| `!`        | `( n addr -- )`    |
| `C@`       | `( addr -- byte )` |
| `C!`       | `( byte addr -- )` |
| `VARIABLE` | `( "name" -- )`    |
| `CONSTANT` | `( n "name" -- )`  |
| `ARRAY`    | `( n "name" -- )`  |
| `CELLS`    | `( n -- n*2 )`     |
| `FREE`     | `( -- n )`         |

**Strings**

| Word       | Stack effect                                   | Notes                                  |
| ---------- | ---------------------------------------------- | -------------------------------------- |
| `S" text"` | `( -- addr len )`                              | IMMEDIATE, a string literal            |
| `TYPE`     | `( addr len -- )`                              | print a string                         |
| `STRING`   | `( n "name" -- )`                              | a mutable buffer, up to `n` characters |
| `PLACE`    | `( addr len dest -- )`                         | store a string into a buffer           |
| `COUNT`    | `( caddr -- addr len )`                        | a buffer's contents as `(addr len)`    |
| `LEN`      | `( caddr -- n )`                               | a buffer's own length                  |
| `VAL`      | `( addr len -- n )`                            | parse a string as an integer           |
| `CHR`      | `( code -- addr len )`                         | a one-character string from a code     |
| `STR`      | `( n -- addr len )`                            | a number, as a string                  |
| `UPPER`    | `( addr len -- addr len )`                     | uppercase, in place                    |
| `LOWER`    | `( addr len -- addr len )`                     | lowercase, in place                    |
| `LEFT`     | `( addr len n -- addr len' )`                  | first `n` characters                   |
| `RIGHT`    | `( addr len n -- addr' len' )`                 | last `n` characters                    |
| `SEARCH`   | `( addr1 len1 addr2 len2 -- addr3 len3 flag )` | find string 2 inside string 1          |
| `CODE`     | `( addr len -- code )`                         | character code of the first character  |

**Defining and control flow**

| Word                             | Stack effect                         | Notes                                                                                     |
| -------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------- |
| `:` ... `;`                      | —                                    | define a new word                                                                         |
| `'`                              | `( -- xt )`                          | look up a word by name, without calling it                                                |
| `EXECUTE`                        | `( xt -- )`                          | call the word an `xt` identifies                                                          |
| `IF` ... `ELSE` ... `THEN`       | `( flag -- )`                        | IMMEDIATE, compile-only                                                                   |
| `BEGIN` ... `UNTIL`              | `( flag -- )`                        | IMMEDIATE, compile-only                                                                   |
| `BEGIN` ... `WHILE` ... `REPEAT` | `( flag -- )`                        | IMMEDIATE, compile-only                                                                   |
| `DO` ... `LOOP`                  | `( limit start -- )`                 | IMMEDIATE, compile-only                                                                   |
| `DO` ... `+LOOP`                 | `( limit start -- )` / `( step -- )` | IMMEDIATE, compile-only                                                                   |
| `LEAVE`                          | `( -- )`                             | IMMEDIATE, compile-only; exits the innermost `DO` loop                                    |
| `EXIT`                           | `( -- )`                             | IMMEDIATE, compile-only; returns from the whole definition, unwinding any open `DO` loops |
| `I`                              | `( -- index )`                       | innermost `DO` loop's index                                                               |
| `J`                              | `( -- n )`                           | the *enclosing* `DO` loop's index, one level out                                          |
| `IMMEDIATE`                      | `( -- )`                             | mark the most recently defined word immediate                                             |

**Dictionary space and defining words** — see
[section 17](#17-growing-the-dictionary-yourself)

| Word        | Stack effect    | Notes                                                                                                                              |
| ----------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `HERE`      | `( -- addr )`   | the first unused dictionary byte                                                                                                   |
| `,`         | `( n -- )`      | write a cell at `HERE`, advance it by 2                                                                                            |
| `C,`        | `( n -- )`      | write a byte at `HERE`, advance it by 1                                                                                            |
| `ALLOT`     | `( n -- )`      | advance `HERE` by `n` bytes (negative shrinks)                                                                                     |
| `CREATE`    | `( "name" -- )` | make a word that pushes its own data address                                                                                       |
| `DOES>`     | `( -- )`        | give a `CREATE`d word its behavior; the code after it runs with that address on the stack                                          |
| `FORGET`    | `( "name" -- )` | remove a word and everything defined after it; refuses built-ins                                                                   |
| `VLIST`     | `( -- )`        | print every word in the dictionary, newest first — see [section 3](#seeing-what-words-exist-vlist)                            |
| `LIST-DEFS` | `( -- )`        | list every colon definition entered so far, numbered, with a source preview — see [section 3](#fixing-a-typo-after-youve-already-pressed-enter-list-defs-and-recall) |
| `RECALL`    | `( n -- )`      | copy `LIST-DEFS` entry `n`'s full source onto the input line for editing — see [section 3](#fixing-a-typo-after-youve-already-pressed-enter-list-defs-and-recall)    |

**Error handling** — see [section 14](#14-error-handling-throw-and-catch)

| Word    | Stack effect       | Notes                                        |
| ------- | ------------------ | -------------------------------------------- |
| `CATCH` | `( xt -- 0 \| n )` |                                              |
| `THROW` | `( n -- )`         |                                              |
| `ABORT` | `( -- )`           | back to the prompt, clearing both stacks     |
| `QUIT`  | `( -- )`           | back to the prompt, leaving the stacks alone |

**Printing and input**

| Word         | Stack effect             |
| ------------ | ------------------------ |
| `.`          | `( n -- )`               |
| `."` text`"` | `( -- )` — compile-only  |
| `EMIT`       | `( char -- )`            |
| `CR`         | `( -- )`                 |
| `SPACE`      | `( -- )`                 |
| `SPACES`     | `( n -- )`               |
| `KEY`        | `( -- char )`            |
| `KEY?`       | `( -- flag )`            |
| `BREAK?`     | `( -- flag )`            |
| `STICK`      | `( device -- value )`    |
| `ACCEPT`     | `( dest maxlen -- len )` |
| `INPUT`      | `( -- n )`               |
| `AT-XY`      | `( col row -- )`         |

**Drawing and sound**

| Word              | Stack effect                                                                |
| ----------------- | --------------------------------------------------------------------------- |
| `PLOT`            | `( x y -- )`                                                                |
| `LINE`            | `( x1 y1 x2 y2 -- )`                                                        |
| `CIRCLE`          | `( xc yc r -- )`                                                            |
| `FILL`            | `( x y -- )`                                                                |
| `CLS`             | `( -- )`                                                                    |
| `BORDER`          | `( color -- )`                                                              |
| `INK`             | `( color -- )`                                                              |
| `PAPER`           | `( color -- )`                                                              |
| `BRIGHT`          | `( flag -- )`                                                               |
| `FLASH`           | `( flag -- )`                                                               |
| `HIRES`           | `( -- )`                                                                    |
| `NORMAL`          | `( -- )`                                                                    |
| `BEEP`            | `( n-semitones fduration -- )`                                              |
| `SOUND`           | `( register data -- )`                                                      |
| `TONE`            | `( channel period -- )`                                                     |
| `VOLUME`          | `( channel level -- )`                                                      |
| `MIXER`           | `( mask -- )`                                                               |
| `NOISE`           | `( period -- )`                                                             |
| `ENVELOPE`        | `( period shape -- )`                                                       |
| `UDG`             | `( n -- addr )`                                                             |
| `64COL` / `32COL` | `( -- )`                                                                    |
| `PALETTE64`       | `( n -- )`                                                                  |
| `PLOT64`          | `( x y -- )`                                                                |
| `ULAPLUS`         | `( flag -- )` — see [section 16](#16-ulaplus-a-bigger-color-palette)        |
| `PALETTE`         | `( index value -- )` — see [section 16](#16-ulaplus-a-bigger-color-palette) |

**EXROM graphics (RECT, POLYGON, sprites)** — see [section
10](#10-drawing-and-sound); needs the real `graphics_exrom.bin`
loaded, not the placeholder EXROM

| Word            | Stack effect                     |
| --------------- | --------------------------------- |
| `RECT`          | `( x0 y0 x1 y1 -- )`               |
| `POLYGON`       | `( x1 y1 ... xn yn n -- )`         |
| `POLYGON-FILL`  | `( x1 y1 ... xn yn n -- )`         |
| `SPRITE-DEFINE` | `( slot row col -- )`              |
| `SPRITE-SHOW`   | `( slot row col -- )`              |
| `SPRITE-HIDE`   | `( slot -- )`                      |

**Hardware ports** — see [section 10](#10-drawing-and-sound)

| Word  | Stack effect        |
| ----- | ------------------- |
| `IN`  | `( port -- value )` |
| `OUT` | `( value port -- )` |

**Storage**

| Word        | Stack effect             | Notes                                          |
| ----------- | ------------------------ | ---------------------------------------------- |
| `SAVE-LIB`  | `( "name" -- )`          | save the compiled dictionary as a binary image |
| `LOAD-LIB`  | `( "name" -- )`          | load a dictionary image back                   |
| `SAVE-TEXT` | `( addr len "name" -- )` | save plain Forth source text                   |
| `LOAD-TEXT` | `( "name" -- )`          | load and re-run saved source text              |

**Printer** — see [section 15](#15-printing-to-a-real-printer-lprint-and-llist)

| Word     | Stack effect      |
| -------- | ----------------- |
| `LPRINT` | `( addr len -- )` |
| `LLIST`  | `( -- )`          |
