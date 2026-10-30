# Numeric model — integer core, floating point beside it

## Decision

2068-Leap-Forth's core language is **16-bit integer**, not floating point.
Floating point is an optional word set layered on top of the integer
core — not something the language is "based on." This matches Phase 1's
cell-size decision in `docs/PROJECT_PLAN.md`. It was added later, in
stages (Phase 8 onward) and rebuilt in audit step F on the 5-byte
format; "Floating point, as built" below describes what the dictionary
has today. Everything above that section is the reasoning for keeping
the two apart, and still holds.

## Why, concretely

- **ANS Forth itself draws this line.** The Core word set (`+ - * / DUP
  SWAP @ !` etc.) is integer-only; floating point is entirely contained
  in the separate, optional Floating-Point word set (`F+ F- F* F.` on a
  separate float stack). A Forth "based on" floating point wouldn't be
  a small deviation from the standard — it would be a different
  language wearing Forth's syntax. Nothing in Phase 2-7 needs it.
- **Jupiter Ace precedent.** The Ace's Forth was integer-only, full
  stop — no floating point at all, not even as an add-on. That was a
  real limitation contemporary reviewers noted, but it didn't stop the
  Ace from being a complete, usable Forth. It's evidence that a
  TS2068-class machine doesn't need floats to have a working language;
  it's evidence for *when* to add them (as a deliberate later choice),
  not that they're required from the start.
- **The kernel was already built for this.** `kernel/math/math.asm`'s
  `MATH_MULTIPLY16`/`MATH_DIVIDE16` are 16-bit signed multiply/divide —
  exactly `UM*`/`UM/MOD`'s primitive, and exactly what Phase 2's `+ - @
  !` etc. need. (Since step F they are 2068-Leap-C's register-only
  routines under the same names and contracts, so `*`, `/` and `MOD`
  give the same results as before, faster.) There is no equivalent ready-to-use 16-bit integer
  path if the core were float-based instead: every arithmetic op would
  route through the far more expensive 5-byte-float engine, for no
  benefit at the stage where the language doesn't have string/array/
  control-flow support yet to even use the extra range.
- **Subroutine threading wants small, fast primitives.** Phase 1
  already chose subroutine threading so `CALL`/`RET` do double duty as
  the inner interpreter and the return stack, specifically to keep
  Phase 2 small and provable. A float-based core would mean every
  primitive — including `DUP`/`SWAP`/`DROP`, which don't care about
  numeric representation at all, they just move cells — gets dragged
  into carrying 5-byte values instead of 2-byte ones, doubling data
  stack traffic for zero semantic gain in those words.

## What this means for Phase 2

- The data stack holds 16-bit cells. `DUP SWAP DROP OVER + - @ !` all
  operate on plain 2-byte values — no float representation decision
  needed anywhere in this phase.
- `NUMBER` (Phase 3) parses decimal integer literals into a 16-bit
  cell, full stop. No decimal-point handling, no exponent handling.
  (Phase 2-3 plan. Since step F one parser reads both kinds of literal;
  see "Number literals" below. A token without a `.` or an exponent is
  still a 16-bit integer.)
- Nothing here blocks floating point from arriving later, and it did:
  a float word set sitting *beside* the integer core the way ANS
  Forth's own float word set sits beside its integer Core, not
  underneath it. The engine is 2068-Leap-C's 5-byte-float `fpcore`
  (`core/fpcore.asm`), called directly, with the float stack as the
  separate stack that keeps the integer words untouched.

## Floating point, as built (audit step F)

The float word set is a separate, optional layer: its own stack, its
own words, nothing in the integer core depends on it. The details are in
`docs/V2/FLOAT_SPEC.md`; the user-facing account is section 4 of
`docs/forth_tutorial.md`.

- **Format.** The Sinclair 5-byte float, always normalised: one exponent
  byte (0 means the value 0), then a sign bit and 31 stored mantissa
  bits (the leading 1 is implicit, so 32 mantissa bits in all). About 9.6 digits; magnitudes from about
  2.9e-39 to about 1.7e38. No infinities, NaN or negative zero. Every
  operation rounds to nearest. The earlier format (a 3-byte cell, about
  4.5 digits, truncating, no overflow check) is gone, and so is any
  compatibility with it: a saved `SAVE-LIB` image holds compiled code
  for the ROM that saved it only.
- **The float stack.** Separate from the data stack, 204 cells of 5
  bytes (`IY`, growing down from `$9000`). Float literals compile as
  `DOFLIT` plus the 5 bytes.
- **Errors, not wrong answers.** Overflow, an integer or float literal
  out of range, `F>S` of a value that does not fit, `PLACES` outside 0-9
  and `SIN`/`COS`/`TAN` beyond about ±102,940 radians are `THROW -43`;
  division by zero (`F/`, and `TAN` where the cosine is 0) is `-42`;
  `FSQRT` of a negative number is `-46` (the ANS floating-point codes).
  Underflow gives 0. An uncaught `THROW` prints a message for these and
  for `-8`, `-13`, `-28` and `-37` (`OUT OF RANGE`, `DIVISION BY ZERO`,
  `INVALID ARGUMENT`, `DICTIONARY FULL`, `UNDEFINED WORD`, `BREAK`,
  `TAPE ERROR`), `ERROR n` for any other code, and `STACK?` only for a
  stack under- or overflow found between words.
- **Number literals.** One parser for both kinds. A token with a `.` or
  an `E`/`e` exponent is a float (`3.5`, `-0.25`, `.5`, `3.`, `1E3`,
  `2.5e-4`, `-1.5E+3`); otherwise it is a 16-bit integer, accepted from
  -32768 to 65535 (so addresses can be typed; `40000` is -25536 as a
  signed cell). An integer outside that range is `OUT OF RANGE`, not
  silently wrapped as before.
- **Words.** Arithmetic `F+ F- F* F/`; `FSQRT`; `SIN COS TAN` (radians,
  accurate to about 1e-9) with `PI RAD DEG`; conversion `S>F`, `F>S`
  (truncates toward 0, -32768..65535), `FROUND` (ties away from 0) and
  `FLOOR`; stack words `FDUP FDROP FSWAP FOVER FDEPTH`; `FNEGATE FABS
  FMIN FMAX`; comparison `F< F> F= F0< F0=` (flags on the data stack, -1
  or 0); memory `F@ F! FVARIABLE FCONSTANT`; output `F.`, `FS.` and
  `PLACES`.
- **Output.** `F.` prints `PLACES` decimals (0-9, 4 at start) of the
  value's exact binary digits, rounded half up (away from 0), with no
  `-` when every digit printed is 0. `FS.` prints `d.ddddEn`, the same
  number of decimals.
- **Integer words stay integer.** `*`, `/`, `MOD` and `RND` do not use
  the float engine. `RND` is a 16-bit xorshift with the range taken by a
  multiply (`n RND` is 0..n-1 without the modulo bias of the earlier
  generator); `RANDOMIZE` seeds as before.
- **Checking it.** `tools/fpmodel.py` (2068-Leap-C's bit-exact model of
  `fpcore`, vendored unchanged) and `tools/fpforth.py` (Forth's words
  composed of its operations) are the oracle: `make floattest` compares
  the ROM's results with them byte for byte in an emulator.

## Reversibility

This is a Phase-1/2 decision, not a permanent constraint on the
project — if a real need for native floats in the core surfaces later
(unlikely, given the precedent above), it's a Phase 8+ addition to
evaluate then, with actual Forth code and actual programs to justify
it, rather than a guess made before either exists. (The float word set
that followed stayed beside the core, as this section expected.)
