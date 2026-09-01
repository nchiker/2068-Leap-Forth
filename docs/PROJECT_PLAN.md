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

**Status: done, as of Phase 9.** Captured 2026-09-01; resolved the same
day. `rom/forth_boot.asm` is the first real, live, bootable ROM: it
boots, plays a startup tone via `BEEP` (`SOUND_BEEP`, still raw
hardware-timing numbers, not a deliberately composed musical tone — a
real, smaller, still-open follow-up, not the blocking dependency this
requirement was tracking), and hands off to a genuinely interactive
prompt. The bigger dependency this requirement was actually tracking —
wiring `RST $0038` to `kernel/interrupt`'s `KBD_ISR_TICK`, IM 1, and
`EI` before calling `core/editor.asm`'s `EDITOR_LOOP_LIVE` — is done
and confirmed working by a human typing at the running system. See
Phase 9's own section for the full story, including two real bugs
found only once that live prompt actually existed to type into.

## Phase 6 — line editing

**Status: `EDITOR_PROCESS_KEY` proven; `EDITOR_LOOP_LIVE` written but
not yet usable.** `core/editor.asm` + `rom/forth_smoke_p6.asm` add a
single-line input buffer (`EDIT_BUF`, 32 bytes, one screen row) with
insert, backspace-delete, and left/right cursor movement, redrawn in
full on every keystroke (simple and correct, not fast — no need for
2068-Leap's own incremental/fast-scroll redraw work at this scale).
Confirmed passing under real Fuse on the first attempt: three canned
key sequences (plain typing; typing then cursor-left then a mid-buffer
insert; typing then cursor-left, delete, cursor-right) each committed
via `INTERPRET_RUN` and checked against the correct final numeric
result — proof that insert/delete/cursor composition ends at exactly
the right buffer content, not just that each operation works in
isolation. As planned, this reads `rom/exrom_editor.asm`'s cursor
arithmetic as reference only — no EXROM/Home split, no redraw hooks, no
label table adopted from it.

Deliberately no dictionary words added. A line editor is the shell that
reads a line and hands it to `INTERPRET_RUN` — the same relationship
`INTERPRET_RUN` itself has to `WORD`/`FIND`/`NUMBER`, sitting outside
the language rather than inside it. `EMIT`/`KEY` as real, callable
Forth words remain deliberately out of scope for this phase even though
the underlying calls (`GFX_PUTCHAR`, `IO_READ_KEY`) are used
internally — Phase 6 was scoped as "line editing," not "line editing
plus new dictionary words," and bundling them in silently would blur
what this phase actually proved.

**A real, previously-undocumented precondition surfaced while writing
this phase, not discovered by testing (the automated test doesn't hit
it) but by reading `kernel/io/io.asm` closely enough to write
`EDITOR_LOOP_LIVE`:** `IO_READ_KEY` no longer scans the keyboard matrix
itself — it only reads a key already latched by `kernel/interrupt`'s
`KBD_ISR_TICK`, which runs solely on a real IM 1 interrupt. Every smoke
ROM in this project so far (including this one) boots with interrupts
permanently disabled, matching `rom/main.asm`'s own original Milestone
0 design. That means `EDITOR_LOOP_LIVE` — the actual live, interactive
entry point — would hang forever at its very first keypress if called
as-is right now: nothing ever sets up `RST $0038` to vector to
`KBD_ISR_TICK`, enables IM 1, or executes `EI`. This is now documented
directly in `EDITOR_LOOP_LIVE`'s own header rather than left as a
silent landmine. Whatever ROM first boots to a live interactive prompt
(implied by the still-open "Product requirement — startup screen plays
a startup sound," above) needs to do that setup — a real, sizable piece
of follow-up work this phase deliberately didn't try to absorb, to keep
"line editing" itself provable on its own.

**Update, Phase 9:** that follow-up work is done — `rom/forth_boot.asm`
does exactly this setup and `EDITOR_LOOP_LIVE` is confirmed working
against a real human at a real keyboard. Getting there also surfaced
two real bugs in this phase's own `EDITOR_REDRAW` and in
`core/interp.asm`'s `W_WORD` that this phase's own canned-key-array
test structurally could not have caught — see Phase 9's own section.

## Phase 7 — storage

**Status: `SAVE`/`LOAD` proven against a fake tape transport; real
emulator tape round-trip is a real, separate, still-open gap.**
`core/storage.asm` + `rom/forth_smoke_p7.asm` add `SAVE`/`LOAD` as
whole-dictionary-image blobs, Jupiter-Ace-style: `SAVE "name"` and
`LOAD "name"` (or `LOAD` alone for a wildcard) call `STORAGE_SAVE`/
`STORAGE_LOAD` directly on the compiled RAM dictionary
(`FORTH_DICT_RAM` through `HERE`), no tokenizing, no per-line format —
a categorically simpler contract than BASIC's, matching the original
plan for this phase.

**Design constraint that shaped everything here, from an explicit user
warning before any code was written:** 2068-Leap's own hard-won
experience is that the tape/storage wire format is fragile — deviate
from it even slightly and LOAD stops working in real emulators. An
early draft of this phase considered smuggling `LATEST` (the
dictionary-head pointer SAVE needs to persist alongside the raw
dictionary bytes, since headers only link backward — there's no way to
walk forward from `FORTH_DICT_RAM` to find "the last one" without
already knowing where it is) through the tape header's own "autostart"
field. That idea was dropped before being written, not caught by
testing afterward, because it would have meant reading/writing
`kernel/storage`'s own internal `STORAGE_HEADER_BUF` layout directly —
outside the documented public contract this project's own
`include/kernel_api.inc` says nothing beyond `kernel/` is allowed to
touch. The actual design: `LATEST` travels as the first 2 bytes of
*this project's own* data payload (built in a scratch buffer,
`SAVE_LOAD_TEMP_BUF`), which `STORAGE_SAVE`/`LOAD` transport completely
opaquely — invisible to and unconstrained by the real wire format.

**Two real bugs found getting this working, both written up in full in
this project's own memory for reuse in either project**
(`2068forth_storage_api_gotchas`, captured 2026-09-01):

1. `STORAGE_SAVE`/`STORAGE_LOAD` (via `STORAGE_SEND_BLOCK`/
   `RECEIVE_BLOCK`) destroy `IX` — which is 2068-Forth's own data stack
   pointer. `W_SAVE`/`W_LOAD` must `PUSH IX` before and `POP IX` after
   every call, or the data stack pointer is left corrupted afterward.
2. `STORAGE_LOAD`'s filename match always compares a fixed
   `STORAGE_HEADER_FILENAME_LEN`-byte (10) span, space-padded on the
   saved side — NOT bounded by the caller's supplied length, which is
   only ever checked for zero (wildcard). Passing a raw, shorter,
   unpadded buffer (an early draft's mistake) reads past the real name
   into whatever garbage follows it, which essentially never matches a
   name that IS really on the tape. `W_LOAD` now builds its own
   space-padded, exactly-10-byte buffer before every non-wildcard call.

Both were found by a real Fuse run reporting "unknown word" for a word
that had genuinely just been saved and reloaded — not predicted by
reading the code — then traced by temporarily rerouting the smoke ROM's
existing checkpoint-color failure signal to show a disposable debug
flag set immediately after the `STORAGE_LOAD` call, the same
diagnostic technique this project has used since Phase 2, applied one
level deeper than usual. Confirmed passing under real Fuse afterward:
an explicit-filename round-trip (define a word, `SAVE` it, simulate a
fresh boot, `LOAD` it back by exact name, call it) and a wildcard
round-trip (same, but `LOAD` with no name given), both on the same fake
tape in sequence.

**What this does NOT prove, stated plainly rather than glossed over:**
`STORAGE_TEST_FAKE_SEND`/`STORAGE_TEST_FAKE_RECEIVE` (conditional-
compilation hooks already present in `kernel/storage/storage.asm`,
unused until this phase) swap in an in-memory fake transport with no
real cassette timing, supplied by `rom/forth_smoke_p7.asm` itself. This
proves this phase's own wiring — filename handling, the payload format,
`HERE`/`LATEST` restoration — but does NOT prove the real tape wire
format actually round-trips correctly in a real emulator, which is
exactly the risk the design constraint above exists to manage. A real
Fuse tape-based round-trip (a genuine virtual cassette file, real
timing) remains real, open, deferred follow-up work — the user was
asked directly whether to build that now or defer it, and chose to
defer it in favor of the faster fake-transport proof for this pass.

## Phase 8 — stretch goals

**Status: floating point (F+, F-) and 64-column display both proven as
a first slice.** Both scoping questions below were put to the user
directly before writing any code, since each had a large fidelity/cost
fork.

### Floating point

`core/float.asm` + `rom/forth_smoke_p8.asm` add `F+`/`F-` as a small,
self-contained, native Forth float implementation — NOT a port of
2068-Leap's real `rom/exrom_calc.asm`. That engine is the classic
Sinclair `RST $28` design (the caller does `RST $28` followed by an
inline literal-bytecode stream; the engine reads its own return address
to find it), and porting it faithfully would also mean EXROM paging
around every call, the real Sinclair float-literal bit encoding, and a
bridge between its own calculator stack and this project's integer data
stack — assessed as a multi-session undertaking, not a stretch-goal-
sized first slice, and this project's own charter already grants full
freedom to diverge from 2068-Leap's conventions rather than stay
compatible with them.

The format instead: 3 bytes per float (16-bit signed mantissa, 8-bit
signed exponent, value = mantissa × 2^exponent) — not IEEE-754, no
normalization, a real and stated limitation that aligning two very
different exponents can lose precision or shift a mantissa to zero.
Floats live on their own stack, addressed by `IY` (confirmed by
grepping the whole `kernel/`+`core/` tree to be completely unused
anywhere else, the same way `IX` was free for the integer stack in
Phase 2), placed just below `DSTACK_LIMIT` so it can never collide with
it even at full depth. Confirmed passing under real Fuse on the first
attempt: three checkpoints, each testing `F+`/`F-` as genuine
dictionary words (found via `FIND`, not called directly as assembly),
with hand-picked values that align without losing any bits, exercising
all three branches of the shared alignment logic (`e1<e2`, `e1=e2`,
`e1>e2`). `F*`/`F/` (need a wider multiply this project's `kernel/math`
doesn't have yet) and `F.` (needs `EMIT`, itself not a Forth word yet)
remain real follow-up work, not folded into this slice.

### 64-column display

**A real find while researching this, worth remembering:** the ROM
disassembly ("Timex Sinclair 2068 ROM Disassembly," David Anderson,
2023) documents port `$FF`'s bits individually (bit 1 = ultra-high-res,
bit 2 = 64-column) in a way that reads as if bit 2 alone enables
64-column mode. It does not. The user's own suggestion to check
`~/Backup` for pre-git snapshots turned up real, working, once-shipped
2068-Leap code (`~/Backup/ts2068rom.tar.gz "with full graphics"`,
predating a 2026-08-20 removal for that project's own ROM-budget
reasons — no trace survives in 2068-Leap's own git history, confirmed
by `git log -S"64-Column"` finding only the post-removal baseline
commit) proving 64-column mode actually needs bits 1 AND 2 set
*together* (video byte bits 0-2 = `%110`, with bits 3-5 as an ink/paper
palette 0-7). This project's own first draft of
`kernel/mode64/mode64.asm`, written from the disassembly alone before
that backup was checked, had exactly the wrong bit pattern — a real bug
that would have shipped if the user hadn't asked to check the backups
first, and never caught by static checks or z80sim, since the code was
internally consistent, just aimed at the wrong port value.

`kernel/mode64/mode64.asm` ports the recovered code (mode switch,
palette select, pixel plot/read for the wide 512×192 coordinate space)
into a **new** kernel/ module rather than modifying the inherited
`kernel/graphics/graphics.asm` (which stays exactly as inherited) —
matching the user's own chosen scope ("2068-Forth's own kernel-adjacent
code, diverging from 2068-Leap"). `core/mode64.asm` adds four real
dictionary words: `64COL`, `32COL`, `PALETTE64`, `PLOT64`.
`rom/forth_smoke_p8b.asm` confirmed all three checkpoints passing under
real Fuse on the first attempt once the correct bit pattern was in
place: a plotted pixel reads back at exactly the right coordinate (and
nowhere else), a selected palette shows up correctly in port `$FF`'s
shadow, and returning to Normal mode clears the mode bits.

**A genuine, unexplained empirical observation, recorded rather than
guessed at:** screenshotting Fuse while still in 64-column mode (a
separate, throwaway build that freezes right after entering it, not
part of the committed smoke ROM) showed the *entire* visible area,
including where the border normally renders, as a uniform light color,
with the plotted pixel visible as a small dark mark at approximately
the expected position. The dot is real, positive evidence the
pixel-level wiring is correct. The uniform full-field color instead of
a distinct border was not predicted by anything confirmed above and is
not further explained here — real hardware behavior, a genuine Fuse
emulation gap for this specific SCLD mode, or something about the
default palette's color mapping are all plausible and none has been
checked. Follow-up work, not resolved by this phase.

### Still open

- `F*`/`F/`/`F.` (floating point), line/circle/fill equivalents for
  64-column mode, and the unexplained rendering observation above.
- A second dictionary segment in EXROM via the already-proven
  `kernel/bank` trampoline, if the Home-resident dictionary gets tight.
- Block/screen-style source loading from tape, as an alternative or
  complement to the Ace-style whole-image `SAVE`/`LOAD` from Phase 7.

## Phase 9 — a real, live, bootable system

**Status: done.** `rom/forth_boot.asm` boots, prints a banner, plays
the startup sound tracked as an open product requirement since Phase 4
("Product requirement — startup screen plays a startup sound," above —
now resolved), and hands off to `core/editor.asm`'s `EDITOR_LOOP_LIVE`
for real, live, keyboard-driven use. Confirmed working by a human
actually typing `5 BORDER` and pressing Enter at the running system and
watching the border turn cyan — the first genuine end-to-end proof in
this entire project that doesn't depend on a fixed test string or a
canned key array. Getting there required one real structural fix and
surfaced two real bugs that no automated test in this project, across
eight earlier smoke ROMs, had ever been positioned to catch.

### The structural fix: one dictionary chain, not a tree

`core/control.asm`, `core/storage.asm`, and `core/float.asm` were each
independently written to chain their own first dictionary entry
directly onto `core/interp.asm`'s `H_SEMICOLON` — correct and
deliberate, since it let each phase's own smoke ROM stay minimal and
self-contained. The unintended consequence: the three of them are
siblings of a tree rooted at `H_SEMICOLON`, not links in one chain, so
a single `LATEST` pointer can only ever reach ONE of those three
branches (plus whatever hangs off it — `core/ts2068.asm` off
`core/control.asm`, `core/mode64.asm` off `core/float.asm`). A ROM
assembling more than one of them together — exactly what a real,
complete product needs — would silently make the others' words
unreachable by `FIND`, with no assembly error to reveal it.

Fixed by making each of those three files' first header link through
`DICT_CHAIN_POINT` — a `DEFL` (redefinable, unlike `EQU` — confirmed
`sjasmplus` supports this before relying on it) that the including ROM
sets immediately before each `INCLUDE`, splicing the tree into one
line in whatever order that ROM actually wants:
`dict → interp → control → ts2068 → storage → float → mode64`.
Every existing smoke ROM (Phases 4/5/7/8/8b) was updated to set
`DICT_CHAIN_POINT = H_SEMICOLON` right before its own single relevant
`INCLUDE`, preserving their exact prior behavior exactly — rebuilt and
re-confirmed passing under real Fuse after the change, not assumed
unaffected. `rom/forth_smoke_p9.asm` proves the fully-spliced chain
directly: `FIND` locates `SAVE`, `LOAD`, `F+`, `F-`, `64COL`, `32COL`,
`PALETTE64`, and `PLOT64` — one word from each branch — from a single
`LATEST`.

### Real interrupts, confirmed against 2068-Leap's own working code

`kernel/io`'s `IO_READ_KEY` (and therefore `core/editor.asm`'s
`EDITOR_LOOP_LIVE`, since Phase 6) only ever consumes a key already
latched by `kernel/interrupt`'s `KBD_ISR_TICK`, which needs a real IM 1
interrupt actually running — a precondition documented as a real,
unmet gap since Phase 6, since every smoke ROM up to and including
Phase 8 deliberately keeps interrupts off throughout. `rom/forth_boot.asm`
and `rom/forth_smoke_p9.asm` both wire it for real: `RST $0038: call
KBD_ISR_TICK / ei / reti`, `KBD_ISR_INIT` called before `EI`, then
`IM 1` / `EI` — the exact sequence confirmed by reading 2068-Leap's own
working ROM files (`rom/test_arr3.asm`'s own `RST_38` and
`COLD_START`), not guessed. `rom/forth_smoke_p9.asm`'s own checkpoint 3
confirms `FRAMES` actually increments after this setup — proof a real
maskable interrupt fired, not just that the vector table has
plausible-looking bytes in it.

### Two real bugs, found only by a human typing at a live keyboard

Both were invisible to every automated test in this project up to this
point, for the same underlying reason: every earlier smoke ROM checks
*final* state after a fixed, hand-written source string runs with
interrupts off. Neither bug is about final correctness of a fixed
input — one is about what the *screen* shows while typing is in
progress, the other is about what a *real keyboard* actually produces
for a letter key, and no test before Phase 9 exercised either.

**Bug 1 — accumulating inverted text.** A user reported (2026-09-01,
via this project's own Fuse session, not simulated): typing at the live
prompt showed every character in reverse video, and pressing Enter left
the whole line as solid black blocks instead of clearing. Root cause,
confirmed by reading `GFX_PUTCHAR`'s own documented contract rather
than assumed: it only plots bitmap pixels, it never touches a cell's
attribute (color) byte. `core/editor.asm`'s `EDITOR_REDRAW` used
`GFX_INVERT_ATTR_STATIC` to mark the cursor cell (a real, permanent
attribute *swap*, not a temporary highlight) but never explicitly reset
a cell's attribute back to normal when printing an ordinary character
over it — so every cell the cursor had ever visited stayed inverted
forever, and printing a blank (space) onto an already-inverted cell
renders as a solid block (a space has no foreground pixels, so an
inverted blank cell shows entirely in what was the "ink" color). Fixed
by calling `GFX_SET_ATTR` (sets outright, confirmed via its own header)
to explicitly normalize every printed and blanked cell before the
single current cursor cell gets inverted at the very end of
`EDITOR_REDRAW`. Re-verified against Phase 6's own smoke ROM afterward
— unaffected, as expected, since that test only ever checks final
buffer content, never what the screen showed along the way.

**Bug 2 — case folding.** After bug 1 was fixed, `5 BORDER` typed
correctly (confirmed by literally reading it back off the screen) but
still didn't change the border — instead landing on
`INTERPRET_UNKNOWN_WORD`. A **Fuse memory-dump snapshot** (a raw 64KB
`debug.bin`, saved by the user directly from the running emulator —
the same "get a debug.bin, don't guess" technique 2068-Leap's own real
ROM comments describe using for exactly this class of problem) settled
it immediately: `WORD_BUF` held `06 62 6f 72 64 65 72` — count 6, then
**lowercase** `border`. Every dictionary header this project has ever
written is uppercase (`DB 6, "B", "O", "R", "D", "E", "R"`), and `FIND`
is case-sensitive by design — a decision `core/interp.asm`'s own header
flagged explicitly back in Phase 3 as needing a real answer "once a
live REPL will need to decide a case-folding policy," never revisited
until a live REPL actually existed to expose it. `kernel/io`'s real
keyboard-to-ASCII translation produces lowercase letters for unshifted
keys; every previous test's source was a hand-written ROM `DB` string,
already uppercase, so this was structurally invisible until a human
typed a letter for the first time. Fixed in `core/interp.asm`'s
`W_WORD`: fold `a`-`z` to `A`-`Z` while copying into `WORD_BUF`, once,
at the one place all parsed tokens already pass through — simpler than
making `FIND` case-insensitive (would repeat the fold on every
comparison) or changing `kernel/io` (inherited, hardware-facing, not
this project's layer to encode a language-level policy into).

**Both fixes were rebuilt and re-verified against all eight existing
smoke ROMs under real Fuse before being trusted** — same standing
discipline as every earlier phase's shared-file change, not skipped
because the fix "looked obviously right."

### What this makes possible, and what's still not resolved

A real, typed Forth session now works end to end: keyboard → interrupt
→ debounce → line buffer → `WORD`/`FIND`/`NUMBER` → dictionary
dispatch → a visible hardware effect. `INTERPRET_UNKNOWN_WORD` still
has zero visible error feedback (a genuine typo silently discards the
line with no indication anything happened) — real, open follow-up
work, not hidden. `EMIT`/`KEY` as real Forth words, `.` for printing,
and named variables (`VARIABLE`/`CONSTANT`) remain exactly as absent as
`docs/forth_tutorial.md` has said throughout — this phase made the
existing words interactive, it didn't add new ones.

## Phase 10 — EMIT and . (print)

**Status: done.** `core/print.asm` adds `EMIT ( char -- )` and
`. ( n -- )`, the first words in this project that can actually show a
computed value on screen rather than only affecting the stack or
hardware state. Both maintain their own output cursor
(`PRINT_ROW`/`PRINT_COL`), independent of `core/editor.asm`'s
`EDIT_CURSOR` (the input line's own cursor, pinned to row 23) —
confining `EMIT`'s output to rows 0-22 means it can never collide with
the input line, wrapping at column 32 and scrolling
(`kernel/graphics`'s `GFX_SCROLL_TEXT_UP`) at row 22.

`.` needed an unsigned divide-by-10 that `kernel/math`'s
`MATH_DIVIDE16` doesn't provide (it's signed, which would misread the
magnitude of any value above 32767 — including `-32768` itself: its
magnitude, 32768, doesn't fit in a signed 16-bit value at all). Written
as `UDIV10`, a private helper local to `core/print.asm` rather than
added to `kernel/math`, matching this project's standing rule of never
modifying an inherited `kernel/` file. The `-32768` edge case is
handled correctly by a real property of two's-complement negation, not
by luck: negating `$8000` (`-32768`) in 16-bit arithmetic yields `$8000`
back — which read as an *unsigned* value is exactly 32768, the correct
magnitude to print after the `-` sign. `rom/forth_smoke_p10.asm` proves
this directly as one of its five checkpoints, alongside positive
multi-digit numbers, zero, `EMIT`'s pixel output (verified via
`GFX_READ_PIXEL` readback, not just cursor-position bookkeeping), and
the column-wrap arithmetic at exactly column 32 — all confirmed passing
under real Fuse.

**A real, live bug found wiring this into `rom/forth_boot.asm`, not in
`core/print.asm` itself.** `core/print.asm`'s own header is explicit
that `PRINT_ROW`/`PRINT_COL` must be initialized by whatever ROM uses
it — no assumed default. `rom/forth_boot.asm`'s `COLD_START` zeroed both
to `(0, 0)` without accounting for the fact that `(0, 0)` is exactly
where `GFX_PRINT_STRING` had just drawn the boot banner (`2068-FORTH`).
Typing `65 EMIT` at the live prompt silently overwrote the banner's own
`2` with `A` instead of appearing as new output — reported live by the
user as "border is... the banner is in the way" after a screenshot
showed `A068-FORTH`. A deterministic, headless diagnostic (replicating
`forth_boot.asm`'s exact full dictionary-chain include order, running
`5 3 + .` through `INTERPRET_RUN` directly — no keyboard needed) proved
`core/print.asm`'s own logic was correct before touching anything,
isolating the bug to `COLD_START`'s cursor initialization alone. Fixed
by starting `PRINT_ROW`/`PRINT_COL` at `(1, 0)` — the row right under
the one-line banner — instead of `(0, 0)`. Confirmed both ways: a
second live keyboard session showed two separate `65 EMIT` calls each
producing a new, separate `A` below the banner rather than overwriting
it or each other, and a saved `debug.bin` memory-dump snapshot (the
same technique from Phase 9's bug 2) independently confirmed
`PRINT_ROW`/`PRINT_COL` at `(1, 2)` and the data stack correctly holding
`8` after `5 3 +` was typed with no trailing `.` — a case that
correctly produces no visible output at all, not a bug, since `+` alone
never prints anything.

`INTERPRET_UNKNOWN_WORD`'s complete lack of error feedback (flagged as
open at the end of Phase 9) is now fixable in principle — `EMIT`/`.`
exist — but wiring an actual `?` or error message into that hook is
still real, open follow-up work, not done here. `KEY` (reading a
keystroke as a Forth value) and named variables (`VARIABLE`/`CONSTANT`)
remain absent.

## Phase 11 — comparisons (=, <, >)

**Status: done.** `core/compare.asm` adds `= ( a b -- flag )`,
`< ( a b -- flag )`, and `> ( a b -- flag )` — the exact gap
`docs/forth_tutorial.md`'s "What's not here yet" section had named
since Phase 4 ("only `0=` exists so far"). TRUE/FALSE match
`core/control.asm`'s own `0=` convention (`-1`/`0`, the ANS Forth TRUE
— all bits set), not `1`/`0`. No `kernel/` dependency at all — like
`core/float.asm` before it, this is pure Z80 logic.

Signed `<`/`>` are both built on one internal helper, `CMP_LESS_HL_DE`,
using a sign-bit case split rather than trusting the Z80's own P/V
(overflow) flag after `SBC HL, DE`: two numbers with the *same* sign
can never overflow the signed 16-bit range when subtracted, so that
subtraction's own result sign directly answers the comparison; two
numbers with *different* signs can be answered from their own sign
bits alone, with no subtraction needed at all. The only subtraction
this file ever performs is therefore one that is structurally
guaranteed not to overflow — verified by hand against six cases,
including both 16-bit extremes (`-32768 < -1` and `-1 < -32768`), the
same rigor `core/print.asm`'s `UDIV10` used for its own `-32768` edge
case. `>` reuses the same helper by swapping which operand plays which
role (`a > b` is exactly the same question as `b < a`) rather than
duplicating the sign-bit logic.

`rom/forth_smoke_p11.asm` proves all three under real Fuse (three
checkpoints covering ten total comparisons, including every hand-
verified edge case) with no `kernel/` include at all. Wired into
`rom/forth_boot.asm`'s full dictionary chain right after `core/print.asm`
(`DICT_CHAIN_POINT DEFL H_DOT`); re-verified with the same deterministic
full-chain-replica diagnostic technique Phase 10 introduced — `5 3 > .`
correctly prints `-1` — rather than relying on live keyboard testing
for this phase.

## Phase 12 — VARIABLE and CONSTANT

**Status: done.** `core/variable.asm` adds `VARIABLE ( "name" -- )` and
`CONSTANT ( n "name" -- )`, the exact gap `docs/forth_tutorial.md`'s
"What's not here yet" section had named since Phase 4 ("built on top of
the `@`/`!` in section 4"). `VARIABLE FOO` creates `FOO` such that
`FOO ( -- addr )` pushes the address of a fresh, zero-initialized
2-byte cell, readable/writable with Phase 2's `@`/`!`. `CONSTANT` is
simpler: `100 CONSTANT BAR` creates `BAR` such that `BAR ( -- n )`
always pushes `100` — no data cell, no way to change it afterward.

Neither is built on a real `CREATE`/`DOES>` — this project doesn't have
one (`core/dict.asm`'s own comments flagged "Phase 3's CREATE" as
future work, never actually built). Instead, both reuse
`core/interp.asm`'s own `DOLIT` compiled-literal idiom — the same
mechanism a typed number compiles to inside a colon definition —
followed by a compiled `RET`: `VARIABLE`'s runtime is a compiled
literal pushing the cell's own address; `CONSTANT`'s is the identical
compiled literal pushing the value directly. The trailing `RET` matters
specifically because a compiled literal is ordinarily followed by more
code it falls through into once its own 2 inline bytes are consumed —
here there isn't any, so without the `RET`, execution would fall
straight into `VARIABLE`'s own 2-byte data cell and try to run its
*value* as code.

Both words duplicate `:` (`core/interp.asm`'s `W_COLON`)'s own
header-construction steps (parse a name, link a new header at `HERE`,
update `LATEST`) rather than factoring them into a shared helper —
`core/interp.asm` is INCLUDEd by every smoke ROM in this entire
project, and this project's standing practice is to accept a little
duplication rather than widen the regression surface of an
already-stable, heavily shared file for a later phase's convenience.

`rom/forth_smoke_p12.asm` proves both under real Fuse (three
checkpoints: define-store-fetch a variable, define-and-read a constant,
and a second independent variable proving separate cells aren't
aliased). Wired into `rom/forth_boot.asm`'s full chain right after
`core/compare.asm`; re-verified with the same full-chain-replica
diagnostic technique — `VARIABLE FOO 42 FOO ! FOO @ .` correctly prints
`42` — and a fresh boot screenshot confirming no regression.

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
