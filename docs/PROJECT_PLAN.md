# 2068-Forth — project plan

## What this is

A from-scratch Forth for the Timex Sinclair 2068, built on the hardware
kernel proven out by the **2068-Leap** project (`~/ts2068rom`, a separate
repo, structured-BASIC ROM by the same author). This is not a fork or a
branch of that project and does not track it — no obligation to stay in
sync, no shared build, no shared release process. It starts from a copy
of 2068-Leap's `kernel/` modules and a handful of its build/test tools
because those are genuinely hardware-facing and BASIC-independent, not
because this project intends to follow BASIC's design anywhere else.
2068-Leap itself is untouched by this work — everything here was created
by copying files out of it read-only.

Both projects are MIT-licensed under the same author, so there's no
attribution complexity in either direction; treat 2068-Forth as free to
diverge from 2068-Leap's conventions (memory map, module boundaries,
naming) the moment doing so serves Forth better than staying similar.

## What was inherited, and why each piece qualifies

2068-Leap's own architecture rule — "`basic/` calls kernel/ APIs only,
never hardware; kernel modules stay reusable" — is what makes this port
possible at all. Everything below is the hardware-facing half of that
split; the BASIC-facing half (`basic/`, `rom/exrom_*.asm`) was left
behind entirely.

| Copied | From | Why it's generic, not BASIC-specific |
|---|---|---|
| `kernel/math/math.asm` | 2068-Leap | `MATH_MULTIPLY16`/`MATH_DIVIDE16` are exactly Forth's `UM*`/`UM/MOD` primitive — 16-bit signed multiply/divide, Python-verified against tens of thousands of cases, with no BASIC concept anywhere in it. |
| `kernel/io/io.asm`, `kernel/interrupt/interrupt.asm` | 2068-Leap | Keyboard matrix scan, debounce, two-key-rollover handling, and a free-running frame counter. `KEY`/`KEY?` and Forth's `MS`/timing words sit directly on top. |
| `kernel/graphics/graphics.asm` | 2068-Leap | Text `PUTCHAR`, pixel plot/read, line/circle/flood-fill, hi-res mode switch — a full TS2068 graphics word set's worth of primitives, addressed by row/column or x/y, no BASIC token involved. |
| `kernel/sound/sound.asm` | 2068-Leap | AY/beeper tone generation — `BEEP` as a one-line CODE word. |
| `kernel/storage/storage.asm` | 2068-Leap | `STORAGE_SAVE`/`STORAGE_LOAD` take a raw pointer + length + name and do TS2068-real-ROM-compatible tape framing. Nothing about the payload's structure is assumed — this is a strictly better fit for Forth's Jupiter-Ace-style whole-dictionary-image SAVE than it ever was for BASIC's tokenized-line programs, which needed extra machinery this project can skip. |
| `kernel/bank/bank.asm` | 2068-Leap | Hardware-confirmed EXROM (chunk 6, $C000-$DFFF) paging trampoline. A second 8K dictionary/vocabulary segment, proven safe, for free. |
| `include/hardware.inc`, `include/keys.inc` | 2068-Leap | Port addresses, keyboard matrix layout — physical facts about the machine, not design choices. |
| `include/sysvars.inc` (as a starting point, see Phase 0 below) | 2068-Leap | Contains the working RAM addresses the copied kernel modules actually reference (port shadows, graphics/pixel-plot scratch, storage buffers, frame counter, EXROM nesting depth). Also contains ~2,000 lines of BASIC-only sysvars this project doesn't need — see Phase 0. |
| `include/kernel_api.inc` | 2068-Leap | The `EXTERN` contract for all of the above. Kept as the starting document of record; will grow its own Forth-side entries and can drop the doc comments that only made sense next to `basic/`. |
| `docs/hardware_notes.md` | 2068-Leap | Confirmed-not-guessed hardware facts (keyboard matrix, BREAK key, etc.) — true regardless of what runs on top. |
| `rom/main.asm` | 2068-Leap | Milestone 0 boot stub: RST vector table, stack init, border-cycle smoke test, zero dependencies. Reused verbatim as this project's own Milestone 0 — already assembles standalone in this repo (`make boot`), which is the whole point of starting from it. |
| `tools/sjasmplus_strict.sh`, `tools/check_asm.py`, `tools/check_z80_opcodes.py`, `tools/z80sim/*` | 2068-Leap | Build wrapper (refuses truncated/overflowed images) and static/simulated Z80 checks. All take explicit file arguments and know nothing about BASIC. |
| `LICENSE` | 2068-Leap | Identical MIT terms, same copyright holder. |

## What was deliberately left behind, and why

- **`basic/basic.asm`, `rom/exrom_checker.asm`, `KEYWORD_HILITE_TABLE`.**
  A static syntax checker and keyword highlighter exist because a
  line-oriented BASIC editor needs to validate a statement before it can
  run correctly. A Forth REPL has no equivalent need — a word either
  resolves in the dictionary or it doesn't, at the moment it's used. This
  is the single largest piece of inherited complexity avoided, not a gap
  to fill in later.
- **`kernel/memory/memory.asm`'s label table (`MEM_LABEL_*`) and
  line-storage format (`MEM_LINE_*`).** These exist to support
  name-based `GOTO`/`GOSUB` over a sequence of statements with no line
  numbers — a BASIC program model. A Forth dictionary is a singly-linked
  list of named definitions with a `HERE`/`LATEST` pointer, structurally
  different enough that reusing this format would fight the design
  rather than help it. `MEM_FILL_ZERO`/`MEM_FILL`/`MEM_SHIFT_UP`/
  `MEM_SHIFT_DOWN` (the generic primitives underneath) are still worth
  keeping; `MEM_LINE_*`/`MEM_LABEL_*` are not carried forward as
  APIs — see Phase 0.
- **The loadable-extension ABI** (`docs/loadable_basic_extensions.md`'s
  registry, service-ABI version byte, fixed 512-byte module window).
  This exists solely because BASIC has a closed, fixed statement set and
  needs a side channel to add one more. In Forth, adding a word *is* the
  normal way the language works — no registry, no ABI version, no fixed
  window. Nothing to port; the capability comes free with the dictionary
  design in Phase 2.
- **`rom/exrom_editor.asm`** (the full-screen program editor). Deeply
  coupled to BASIC's program-as-labeled-statements model (block delete
  with reference scanning, keyword-highlighted redraw hooks, an
  EXROM/Home split sized for an 918-line editor). `kernel/editor/
  editor.asm` in 2068-Leap is only a 24-line compatibility shim that
  `INCLUDE`s this file — copying the shim without the file it wraps
  would just be dead code, so neither was brought over. 2068-Forth needs
  a much smaller input primitive (see Phase 6) and will mine specific
  cursor/insert/delete arithmetic from `exrom_editor.asm` as a read-only
  reference if useful, not as code to include.
- **`rom/exrom_calc.asm`** (the 5-byte-float RST $28 calculator). Not
  discarded on principle — its `CALC_STACK`-in-RAM, jump-table-dispatch
  design is structurally close to what a Forth floating-point word set
  wants, and it's a real candidate to bring over once the integer core
  is solid (Phase 8). Left out of the initial scaffold to keep Milestone
  0 dependency-free, matching `main.asm`'s own stated design principle.

## Phase 0 — kernel audit (before any Forth-specific code)

**Status: still not formally done** — items 1-3 below remain open. What
changed as of Phase 5: item 2's exact risk ("don't treat its untrimmed
contents as this project's actual RAM map") stopped being theoretical
and actually bit this project once `kernel/graphics`/`kernel/sound`
were first assembled alongside `core/` — see Phase 5's own section for
the real collision found and fixed, and the probe method used to find
it. That method (assemble every needed `kernel/` module with every
`core/` file in a throwaway build, inspect the `.sym` file for the
address range in question) is the concrete version of this item 2 that
should have been run before Phase 3 ever picked an address, not after
Phase 5 forced the question. Still worth doing formally — the fix so
far has been "relocate our own scratch out of the way," not "trim the
inherited file," which is what item 2 actually asks for.

Do this first, not as later cleanup, because everything in Phase 1
onward assumes a memory map that's actually this project's own:

1. Write a fresh `docs/memory_map.md` for 2068-Forth. Don't inherit
   2068-Leap's — its $8000+ layout is sized around a BASIC program/array/
   scalar pool this project doesn't have. Physical constraints from
   `docs/hardware_notes.md` and the ROM/screen/attribute regions in
   `include/hardware.inc` still apply; everything above $8000 is a clean
   slate.
2. Trim `include/sysvars.inc` down to the equates the copied kernel
   modules actually reference (grep each `kernel/*/*.asm` for every
   symbol it uses from this file, keep exactly those plus their
   assembler-computed dependencies, drop the rest). Until this is done,
   the file is safe to build against as-is (it's git history from a
   working project, not experimental) — just don't treat its untrimmed
   contents as this project's actual RAM map.
3. Decide what happens to `kernel/memory/memory.asm`'s `MEM_LINE_*`/
   `MEM_LABEL_*` routines: delete them from this project's copy once the
   dictionary module (Phase 2) supersedes them, rather than letting dead
   BASIC-program-model code sit next to the kernel indefinitely.
4. Re-run `make check` after each trim and keep it clean (the one
   pre-existing `check_z80_opcodes.py` warning on `GFX_LINE`'s `.loop`
   displacement estimate is inherited unchanged from 2068-Leap itself,
   not introduced by this port — confirmed by running the same checker
   against 2068-Leap's own copy of the file; leave it alone unless that
   routine grows).

## Phase 1 — design decisions to lock in early

- **Cell size: 16 bits.** Matches `MATH_MULTIPLY16`/`MATH_DIVIDE16`
  exactly; no reason to fight the Z80's native word size.
- **Threading model: subroutine threading**, not indirect/direct
  threading. On Z80, `CALL`/`RET` are cheap and well-understood, and
  subroutine threading means the hardware return stack (`SP`) *is* the
  Forth return stack for free — no hand-written `NEXT` dispatcher, no
  separate R-stack pointer to maintain. This is the highest-leverage
  simplification available for a first working core; revisit only if
  profiling later shows a real speed problem indirect threading would
  fix.
- **Data stack:** a dedicated RAM pointer (not `SP`, which subroutine
  threading needs for the return stack). One register pair (candidate:
  `IX`, unused elsewhere in the copied kernel's public API) held as the
  data stack pointer across word calls.
- **Dictionary layout:** link pointer, length+flags byte, name, code
  field, parameter field — the standard shape, singly-linked from a
  `LATEST` sysvar, growing from `HERE`. Deliberately not
  `MEM_LINE_*`'s length-prefixed sequential format (see Phase 0.3).

## Phase 2 — minimal inner interpreter + dictionary

**Status: core proven.** `core/dict.asm` (dictionary header format,
`LATEST`/`HERE`, the IX-based data stack) and `rom/forth_smoke.asm` (a
smoke ROM in the exact spirit of `rom/main.asm`) exist, assemble clean
under `check_asm.py`/`check_z80_opcodes.py`, and pass a self-checking
sequence of `DUP SWAP DROP OVER + - @ !` calls under real Fuse (border
goes green; a failing checkpoint shows its own 1-7 number on the border
instead, so a future regression identifies itself without a debugger).
`EMIT`/`KEY` were deliberately deferred out of this ROM to keep it
dependency-free like `main.asm` itself — see the note below.

Two real lessons from getting the smoke ROM to actually pass, worth
remembering for every ROM file after this one:

1. **Include order matters when an INCLUDE emits real code.**
   `core/dict.asm` must be `INCLUDE`d *after* `DEVICE`/`ORG $0000` and
   the fixed RST vector table, not before either exists — the first
   attempt at `forth_smoke.asm` included it at the top of the file,
   before any `ORG` was set, so the dictionary's first bytes landed at
   address 0 and were then silently overwritten by the RST vector
   table's own `DS ...,$FF` padding. `include/hardware.inc` (constants
   only, no code) is fine to include early; anything that emits actual
   bytes is not.
2. **z80sim proved the arithmetic correct while the real ROM still
   failed** — because z80sim was driven starting at `COLD_START`
   directly, skipping the real boot chain (`RST_00`/vector table)
   entirely, so it couldn't see the corruption bug above. This doesn't
   make z80sim wrong for what it's actually for (see its own README);
   it means "z80sim passed" only clears the routines actually exercised
   from the actual entry point real hardware uses, not the file's
   layout as a whole. Fuse (or real hardware) remains the only thing
   that validates the whole ROM image, per the testing-discipline
   section below.

An unrelated environment gotcha surfaced during the same bring-up and
is recorded in `rom/forth_smoke.asm`'s own header rather than here:
running `main.asm` and this smoke ROM under this project's Fuse
1.9.1/`--machine ts2068` setup with a content-free (all-`$FF`) 8K
`--rom-ts2068-1` placeholder produced visibly different behavior than
using a real EXROM image, even for ROMs that never page EXROM in at
all. Root cause not isolated; treat a blank EXROM placeholder as
untrustworthy for this machine type until it is.

Remaining Phase 2 scope (not yet done): none — `CREATE`, a real
colon-compiler, and `FIND`/`WORD`/`NUMBER` belong to Phase 3, not this
phase; `LATEST`/`HERE` are seeded correctly for Phase 3 to consume but
nothing yet appends to them at runtime.

## Phase 3 — outer interpreter

**Status: core proven.** `core/interp.asm` + `rom/forth_smoke_p3.asm`
add `W_WORD` (parse a blank-delimited token), `FIND` (dictionary search,
also reporting the IMMEDIATE bit), `NUMBER` (signed decimal literal
parsing), `DOLIT` (runtime support for a compiled literal), `STATE`,
and real dictionary words `:` and `;` (`;` is IMMEDIATE) — a working
colon compiler. Confirmed passing under real Fuse on the first attempt
(the include-ordering lesson from Phase 2 was applied from the start,
not rediscovered): `rom/forth_smoke_p3.asm` runs `"5 3 + "` through
`INTERPRET_RUN` (proving WORD/NUMBER/FIND/execute cooperate with
nothing compiled), then `": DOUBLE DUP + ; 4 DOUBLE "` (proving the
colon compiler builds a real, callable dictionary entry that `FIND`
locates like any other word — `DOUBLE` isn't special-cased anywhere).

Deliberately still scoped down, matching Phase 2's own "smallest
provable step" discipline rather than building everything Phase 3
could eventually mean in one pass:

- **Input is a fixed in-memory buffer, not a live keyboard.**
  `INTERPRET_RUN` takes an address and length and runs until exhausted,
  batch-style — it is not a REPL yet. Wiring it to `kernel/io`'s
  `IO_READ_KEY` for live interactive use is follow-up work, not done
  here. (Phase 2's own `EMIT`/`KEY` deferral for the same reason still
  stands, too.)
- **One delimiter (space), one error path (fatal).** No tabs/CR
  handling, no error recovery — an unrecognized token halts via a
  ROM-level hook (`INTERPRET_UNKNOWN_WORD`) rather than reporting an
  error and continuing. Both are fine for a fixed, hand-written test
  source; both need real answers before this is interactive.
- **Case-sensitive `FIND`.** Every header this project writes and every
  test source string is already uppercase, so this hasn't mattered yet;
  a live REPL will need to decide a case-folding policy.
- **IMMEDIATE has exactly one user (`;`).** Enough to prove the
  mechanism (a bit in `LENFLAGS`, read by `FIND`, acted on only in
  `INTERPRET_RUN`) generalizes to Phase 4's `IF`/`ELSE`/`THEN` and
  friends, without building more of it than one real user justifies yet.
- 2068-Leap's own expression-evaluator numeric-literal scanning in
  `basic.asm` was NOT consulted as a reference for this pass (`NUMBER`
  here is a plain unsigned-run-with-optional-leading-minus scanner) —
  worth a look before hardening `NUMBER` further (overflow behavior,
  `$`/`%` radix prefixes, etc.), but not needed to get a first working
  version passing.

## Phase 4 — control flow

**Status: `IF`/`ELSE`/`THEN` and `BEGIN`/`UNTIL` proven.**
`core/control.asm` + `rom/forth_smoke_p4.asm` add `QBRANCH`/`BRANCH`
(runtime branch primitives, not dictionary words themselves — compiled
to directly, the same way `DOLIT` is) and four real, `IMMEDIATE`
dictionary words built on them: `IF`, `ELSE`, `THEN`, `BEGIN`, `UNTIL`.
Also adds `0=` (needed because nothing before Phase 4 produced a
correctly-signed boolean flag — plain subtraction is 0 exactly when two
values are *equal*, which is backwards for a "loop until true" idiom).
Confirmed passing under real Fuse on the first attempt: defines a word
using `IF`/`ELSE`/`THEN` and checks both branches, then defines a
`BEGIN`/`UNTIL` loop and confirms it iterates exactly the right number
of times (a wrong iteration count would leave the wrong final value on
the stack, not just fail to terminate).

Implementation note worth keeping for the next control-flow word
(`WHILE`/`REPEAT`, `DO`/`LOOP`): `IF`/`ELSE`/`THEN`/`BEGIN`/`UNTIL` all
need to remember an address between compile-time steps — where a
branch's target hole is, or where a loop starts. Rather than a third
stack, they reuse the ordinary data stack for this, which is safe
specifically because nothing else touches it while a definition is
being compiled (every non-`IMMEDIATE` word gets compiled, not run, so
it never pushes/pops at compile time). This is a well-established real
Forth technique, not a shortcut specific to this project, and it
generalizes directly to whatever Phase 4 adds next.

One structural lesson from getting `0=` chained in correctly: it does
NOT live in `core/dict.asm` next to Phase 2's other primitives, even
though it's arithmetic rather than control flow. `core/interp.asm`
already hardcodes `H_COLON`'s `LINK` field as `DW H_STORE` (core/dict.asm's
own tail) — inserting a new dictionary word between them in
`core/dict.asm` would silently orphan Phase 3's whole chain (`FIND`
walks backward from `LATEST` following `LINK` pointers; a word not
reachable that way might as well not exist, even if it assembles fine).
`0=` chains onto `H_SEMICOLON` (Phase 3's actual tail) inside
`core/control.asm` instead — extend the chain forward from wherever the
previous phase actually left it, never splice into the middle of an
earlier phase's file.

`BEGIN`/`WHILE`/`REPEAT` and `DO`/`LOOP`/`+LOOP`/`I`/`J`/`LEAVE` remain
for a follow-up pass — not done in this slice, matching every earlier
phase's practice of proving the smallest meaningful piece first rather
than building everything a phase could eventually mean in one attempt.
No runtime statement-boundary scanning of the kind `basic.asm` does for
`ELSEIF`/`ELSE`/`END IF` is needed here — Forth compiles the jump once,
unlike line-oriented BASIC re-parsing structure on every pass.

## Phase 5 — TS2068 vocabulary

**Status: `PLOT`, `LINE`, `CIRCLE`, `BEEP`, `BORDER` proven.**
`core/ts2068.asm` + `rom/forth_smoke_p5.asm` add five thin `CODE` words
wrapping the kernel almost 1:1, matching `include/kernel_api.inc`
closely: `PLOT` (`GFX_WRITE_PIXEL`), `LINE` (`GFX_LINE`), `CIRCLE`
(`GFX_CIRCLE`), `BEEP` (`SOUND_BEEP`), `BORDER` (`GFX_SET_BORDER`).
Confirmed passing under real Fuse on the first attempt, verified two
ways: `GFX_READ_PIXEL` readback confirms `PLOT`/`LINE`/`CIRCLE` set
exactly the pixels they should (and nothing they shouldn't) — this
tests THIS project's own coordinate wiring, not `kernel/graphics`'s own
drawing algorithms, which are already proven 2068-Leap code — and a
saved screenshot showing a real dot, line, and circle exactly where
expected, as an independent visual confirmation beyond the automated
check. `BORDER` is verified by reading back `PORT_FE_SHADOW` rather
than the border color itself, since this smoke ROM's own pass/fail
signal *is* the border color. `BEEP` has no way to verify actual sound
in this environment — checked for data-stack hygiene (a sentinel value
survives intact across the call) instead, a real but narrower check,
documented as such rather than silently passed off as "tested."

`FILL`, `AT-XY`, and hi-res `MODE` remain for a follow-up pass — this
slice matches the five words actually requested, not the full word list
this phase's description originally sketched.

**The real finding of this phase wasn't a Forth bug — it was in the
inherited kernel plumbing.** This is the first ROM in the project to
actually assemble `kernel/graphics` and `kernel/sound` together with
`core/`'s own files, because Phases 2-4 were deliberately kernel-free.
Doing that for the first time immediately surfaced the Phase 0 audit
risk this document had been flagging since Phase 2 and deferring every
phase since: `include/sysvars.inc` (2068-Leap's own, inherited
untrimmed) declares real, actively-used RAM addresses densely packed
across `$8000`-`$8425` — and `core/interp.asm`'s own Phase 3 scratch
cells (`SRC_PTR` through `WORD_BUF`, originally `$8100`-`$8141`) sat
right in the middle of that range, aliasing real kernel state
(`EDITOR_REDRAW_HOOK`, several `HILITE_*` cells, `PORT_FE_SHADOW`, and
more) that this project would have started silently corrupting the
moment a Forth program actually used both `WORD`/`FIND`/`NUMBER` and
any graphics/sound word in the same session. Invisible through Phase 3
and 4 because neither of those phases' smoke ROMs ever included a
kernel/ module that pulls `sysvars.inc` in at all.

**Method used to find and fix it, worth repeating for any future
addition that needs its own RAM state:** assemble every `kernel/`
module the ROM actually needs together with every `core/` file, in one
throwaway probe build, then inspect the resulting `.sym` file for the
address range in question — don't reason about a gap being "probably
empty" from reading `sysvars.inc`'s section comments alone (the file's
own layout is provisional and its comments describe history, not
necessarily current addresses — see its own header). That probe
confirmed `$8426` (2068-Leap's own `PROG_AREA_START`, the start of
*its* dynamic BASIC pool, never written to by anything this project
calls) through `$8FFF` is genuinely empty, and separately confirmed
this project's own `DSTACK_LIMIT`-through-`DSTACK_TOP` (`$9000`-`$9800`)
and `FORTH_DICT_RAM` (`$A000`+) had been safe all along by pure luck,
not by having been checked. `core/interp.asm`'s scratch was relocated
to `$8500`, inside the confirmed-empty gap, and Phase 3/4's own smoke
ROMs were rebuilt and re-confirmed passing under Fuse afterward (they
were never actually broken — they don't include the colliding kernel
modules — but re-verifying rather than assuming is the same discipline
this whole project has followed since Phase 2's own first bug).

## Product requirement — startup screen plays a startup sound

Captured 2026-09-01, not yet implemented: when 2068-Forth boots to its
first user-visible screen (the live interactive front end — not any of
the current smoke ROMs, which a real user will never see), that
startup screen must play a startup sound. Depends on Phase 5's `BEEP`/
`SOUND` (built on `kernel/sound`, already inherited and proven by
2068-Leap) and on wiring `INTERPRET_RUN` to live keyboard input (the
"not a live REPL yet" limitation Phase 3 and Phase 4 both still carry).
No sound design decided yet (tone, duration, whether it's the same
kernel/sound `SOUND_BEEP` primitive 2068-Leap's own `BEEP` statement
uses) — just the requirement that a startup screen without one is
incomplete.

## Phase 6 — line editing

New work, deliberately small: single-line (then multi-line, if needed)
input buffer with insert/delete/cursor, sized for editing one Forth
definition or command line at a time — not a full-program editor with
label/reference tracking. Read `rom/exrom_editor.asm` in 2068-Leap for
its cursor-position and insert/delete arithmetic as a reference only;
do not adopt its EXROM/Home split or its redraw-hook architecture, both
of which exist to serve BASIC's multi-line program-with-labels model.

## Phase 7 — storage

`SAVE`/`LOAD` as whole-dictionary-image blobs (name + pointer + length)
directly on `STORAGE_SAVE`/`STORAGE_LOAD`, Jupiter-Ace-style: no
tokenizing, no per-line format, no filename-corruption bug class of the
kind 2068-Leap had to fix for named BASIC `LOAD` — the payload here is
just "everything from `DICT_START` to `HERE`," which is a categorically
simpler contract than BASIC's.

## Phase 8 — stretch goals

- Floating-point word set (`F+ F- F* F/ F.` etc.) over a ported
  `exrom_calc.asm`, once the integer core is solid.
- A second dictionary segment in EXROM via the already-proven
  `kernel/bank` trampoline, if the Home-resident dictionary gets tight.
- Block/screen-style source loading from tape, as an alternative or
  complement to the Ace-style whole-image `SAVE`/`LOAD` from Phase 7.

## Testing discipline

Carry forward the validated order from 2068-Leap, applied to Forth
words instead of BASIC fixtures: `tools/z80sim` first (fast, catches
logic bugs early, but — per its own header comment — doesn't validate
real Z80 opcode encodings), then `check_z80_opcodes.py` (catches the
class of bug z80sim structurally can't), then real `sjasmplus` via
`tools/sjasmplus_strict.sh`, then Fuse for anything timing- or
hardware-visible. A per-word test-fixture convention (this project's
answer to 2068-Leap's `tests/` BASIC fixtures) should exist by the end
of Phase 2, not be deferred until the word count grows unmanageable.
