# Numeric model — integer core, floating point deferred

## Decision

2068-Forth's core language is **16-bit integer**, not floating point.
Floating point is an optional, later word set layered on top once the
integer core works — not something the language is "based on." This
matches Phase 1's cell-size decision in `docs/PROJECT_PLAN.md` and is
worth stating explicitly now that Phase 2 is actual code, not just plan.

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
  !` etc. need. There is no equivalent ready-to-use 16-bit integer
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
- Nothing here blocks floating point from arriving later. `exrom_calc.asm`
  in 2068-Leap (a 5-byte-float engine with its own RAM operand stack and
  jump-table dispatch — read-only reference, not yet copied into this
  project) remains the leading candidate to back an `F+ F- F* F.` word
  set as a Phase 8 stretch goal, sitting *beside* the integer core the
  way ANS Forth's own float word set sits beside its integer Core, not
  underneath it.

## Reversibility

This is a Phase-1/2 decision, not a permanent constraint on the
project — if a real need for native floats in the core surfaces later
(unlikely, given the precedent above), it's a Phase 8+ addition to
evaluate then, with actual Forth code and actual programs to justify
it, rather than a guess made before either exists.
