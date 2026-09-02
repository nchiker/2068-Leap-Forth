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

## Phase 13 — `."` (print a literal string)

**Status: done.** `core/dotquote.asm` adds `." text" ( -- )`, IMMEDIATE
— the last item on `docs/forth_tutorial.md`'s "What's not here yet"
list: printing a fixed piece of text the way BASIC's `PRINT "hello"`
does, distinct from `.`'s printing of a *computed* number. Like
`IF`/`ELSE`/`THEN`/`BEGIN`/`UNTIL` (`core/control.asm`), `."` is
compile-time only — meaningless outside a colon definition, and this
project doesn't support typing it directly at the interpreter prompt.

The runtime mechanism generalizes `core/interp.asm`'s own `DOLIT`
inline-data idiom from a fixed 2-byte numeric literal to a
variable-length string: `."` compiles `CALL DOSTR` followed by a length
byte and the string's own raw bytes; `DOSTR` reads those off its own
return address, prints each character via `core/print.asm`'s `W_EMIT`,
then corrects the return address to skip past all of it before
returning — exactly `DOLIT`'s own trick, generalized.

**A real design mistake caught before assembling, not after.** The
first draft had `W_DOTQUOTE` explicitly skip one leading space after
`."` before scanning for the string. That space is already consumed —
`W_WORD` (`core/interp.asm`) always eats whatever space terminated the
word it just finished reading, and `."` itself is read as an ordinary
word by the same `W_WORD`. The extra skip would have silently eaten the
string's own first real character. Caught by tracing the mechanism by
hand before ever assembling it, the same discipline this project has
applied to every inline-data trick since `DOLIT` itself.

`rom/forth_smoke_p13.asm` proves it under real Fuse (three checkpoints:
a plain string, the empty-string edge case — where the one required
delimiting space IS the entire gap between the opening and closing
quotes — and `."` combined with `IF`/`ELSE`/`THEN`, matching
`docs/forth_tutorial.md`'s own section 5 example almost verbatim).
Wired into `rom/forth_boot.asm`'s full chain right after
`core/variable.asm`; re-verified with the same full-chain-replica
diagnostic technique (`: GREET ." HI" ; GREET` correctly prints `HI`)
and a fresh boot screenshot confirming no regression.

With this phase, every item `docs/forth_tutorial.md`'s "What's not here
yet" section had named since Phase 4 except counted loops
(`DO`/`LOOP`, `BEGIN`/`WHILE`/`REPEAT`), more graphics/sound
(`FILL`/`AT-XY`/hi-res/`INK`/`PAPER`), and decimal-number
multiply/divide is now done.

## Phase 14 — BEGIN/WHILE/REPEAT

**Status: done.** `core/loop.asm` adds `WHILE ( flag -- )` and
`REPEAT ( -- )`, both IMMEDIATE — the first half of the remaining
"Counted loops" gap: `BEGIN`/`UNTIL` (Phase 4) tests its condition only
*after* each pass, so the loop body always runs at least once;
`BEGIN ... WHILE ... REPEAT` can test *before* the first pass too, or
exit partway through. `DO`/`LOOP` — a real counted loop with a
built-in index, comparable to BASIC's `FOR`/`NEXT` — remains open: it
needs its own place to keep a loop's limit/index across each pass, and
this project's subroutine-threaded design already uses the Z80
hardware stack (SP) for real `CALL`/`RET` return addresses, so reusing
it for loop control too needs careful design this phase didn't
attempt.

`WHILE`/`REPEAT` reuse `core/control.asm`'s own internal `QBRANCH`/
`BRANCH` runtime routines directly rather than modifying that
already-shared file (INCLUDEd by several smoke ROMs and
`rom/forth_boot.asm` already) — a new small file, not a change to a
proven one, matching this project's practice since Phase 12. `WHILE`
is literally `IF`'s own body (compile `QBRANCH` + a placeholder, push
the placeholder) reused verbatim — the placeholder nests correctly on
top of whatever `BEGIN` already pushed, on the same borrowed data stack
this project has used for every compile-time bookkeeping trick since
Phase 4. `REPEAT` pops both placeholders in the matching LIFO order,
compiles the unconditional branch back to `BEGIN`'s own loop-start, and
patches `WHILE`'s placeholder to land right after it.

`rom/forth_smoke_p14.asm` proves it under real Fuse with three
checkpoints, the second being the crucial one: `0 COUNTDOWN2` (where
`COUNTDOWN2` is `BEGIN DUP 0 > WHILE 1 - REPEAT`) must leave `0`
*unchanged* — the loop body must never run at all, which is exactly the
semantic difference from `BEGIN`/`UNTIL`'s own always-run-once shape.
The third checkpoint combines `WHILE`/`REPEAT` with Phase 10's `.`
(`3 PRINTDOWN` prints `"3 2 1 "`). Wired into `rom/forth_boot.asm`'s
full chain right after `core/dotquote.asm`; re-verified with the same
full-chain-replica diagnostic technique and a fresh boot screenshot
confirming no regression.

## Phase 15 — INK and PAPER

**Status: done.** `core/color.asm` adds `INK ( n -- )` and
`PAPER ( n -- )`, 0-7, the color half of the remaining "More graphics
and sound" gap. Unlike every phase since 12, this one genuinely
required editing an already-shared file: `core/ts2068.asm`'s
`PLOT`/`LINE`/`CIRCLE` previously drew with a hardcoded compile-time
constant (`DEFAULT_ATTR`) with no way to change it — for `INK`/`PAPER`
to have any visible effect at all, those three words had to start
reading their attribute byte from a new, settable RAM cell
(`CURRENT_ATTR`, `$87CB`, placed by inspecting `forth_boot.sym` for a
free byte, not guessed) instead.

**This is a real, deliberate exception to the "add a new file, don't
touch a shared one" practice this project has followed since Phase
12** — there was no way around it here, since the whole point is for
existing PLOT/LINE/CIRCLE calls to pick up a color set *earlier*, not
just for new words to exist alongside them. The cost was accepted
consciously, with the mitigation that always applies to a shared-file
change in this project: everything that already includes
`core/ts2068.asm` (`rom/forth_smoke_p5.asm`, `rom/forth_smoke_p9.asm`,
`rom/forth_boot.asm`) needed a new one-line `COLD_START` addition
(`CURRENT_ATTR` initialized to `DEFAULT_ATTR`, exactly like
`core/print.asm`'s own `PRINT_ROW`/`PRINT_COL` convention), and all
three were rebuilt and re-verified passing under real Fuse — Phase 5's
own dot/line/circle screenshot and Phase 9's own three checkpoints,
both unchanged — before trusting the change.

`INK`/`PAPER` are each a read-modify-write against whatever
`CURRENT_ATTR` already holds (ink is bits 0-2, paper is bits 3-5 of the
standard Spectrum-family attribute byte) — calling one never disturbs
the other. `rom/forth_smoke_p15.asm` proves this under real Fuse by
reading back the REAL screen attribute byte `PLOT`/`LINE` wrote (via
`kernel/graphics`'s own `GFX_CELL_ATTR_ADDR`), not just
`core/color.asm`'s own internal state: setting ink then plotting one
cell, setting paper then plotting a different cell (confirming the
first cell's ink survived), and finally resetting both back to their
original values and confirming the resulting byte exactly equals
`DEFAULT_ATTR` again — round-tripping the bit arithmetic exactly, and
proving `LINE` (not just `PLOT`) honors `CURRENT_ATTR` too. Wired into
`rom/forth_boot.asm`'s full chain right after `core/loop.asm`;
re-verified with the same full-chain-replica diagnostic technique and a
fresh boot screenshot.

`FILL` (`kernel/graphics`'s own `GFX_FILL`, a proven flood-fill
routine, already inherited and unused by this project) and hi-res mode
remain the rest of the "More graphics and sound" gap, along with
decimal-number multiply/divide and `DO`/`LOOP` — all still open.

## Phase 16 — DO/LOOP and I

**Status: done.** `core/doloop.asm` adds `DO ( limit start -- )`,
`LOOP ( -- )` (both IMMEDIATE), and `I ( -- index )` — the counted loop
this project deferred since Phase 4, comparable to BASIC's `FOR`/
`NEXT`. This was the item repeatedly flagged as the hardest remaining
one, across Phase 14's own header and the Phase 14/15 sections above,
because of a real, specific design question: where does a loop's own
limit/index live, in a subroutine-threaded design that already uses
the Z80 hardware stack (`SP`) for real `CALL`/`RET` return addresses?

**The answer, once stated plainly, turned out not to need new
machinery at all: this project's hardware stack already IS a return
stack, by construction, since Phase 2.** Real Forth systems keep
`DO`/`LOOP` state on a *separate* return stack specifically because
ordinary `CALL`/`RET` execution always pushes and pops its own return
addresses in balanced pairs, never touching what's underneath — and
that exact property has held for every dictionary word in this project
without exception since the very first primitives. So `DO_RT` just
pushes `(limit, index)` onto the SAME hardware stack, underneath
whatever the loop body's own calls do on top of them, and `LOOP_RT`
finds them again exactly where it left them once the body's calls have
all balanced back out. `I` reads the innermost loop's index directly
off the stack (`ADD HL, SP` copies `SP` into `HL` non-destructively, no
push/pop peek needed). Both `DO_RT` and `LOOP_RT` pop and re-push their
own return address around this, exactly like `DOLIT`/`DOSTR` already do
around their own inline data — the same established idiom, not a new
one.

**A real bug caught in the test, not the implementation.** The first
draft of `rom/forth_smoke_p16.asm`'s third checkpoint tried
`5 0 DO I SUM @ + SUM ! LOOP` directly at the top level, outside any
colon definition — and it failed, printing a garbage sum (`374`, not
`10`). Tracing it by hand rather than guessing: `DO`/`LOOP` are
IMMEDIATE, so at top level they *execute* their own `W_DO`/`W_LOOP`
code — which only *compiles* `CALL DO_RT`/`CALL LOOP_RT` bytes into
`HERE`, never actually runs them. With no colon definition to later
call those compiled bytes, `DO_RT`/`LOOP_RT` never ran at all, and `I`
(executed immediately too, since interpret state runs everything
regardless of the immediate flag) read whatever unrelated bytes
happened to be sitting on the hardware stack. Fixed by wrapping the
loop in its own colon definition (`: DOSUM 5 0 DO I SUM @ + SUM ! LOOP
;` then `DOSUM`) — `DO`/`LOOP`, like `IF`/`ELSE`/`THEN`/`BEGIN`/`WHILE`/
`REPEAT` before them, only work compiled into a real definition, never
at the top level.

**A real, known Forth gotcha, documented rather than "fixed" away:**
plain `DO` (this project has no `?DO`) never checks whether `start`
already equals `limit` before running the body once — if they're equal
going in, `LOOP`'s own index increments past `limit` and won't match it
again until a full 65536-count wraparound. Standard, well-documented
Forth behavior, not a defect; `core/doloop.asm`'s own header flags it
so nobody rediscovers it as a mystery bug later. No `LEAVE` (early
exit) and no `+LOOP` (custom step) either — the smallest provable
slice, matching every earlier phase's own scope discipline.

`rom/forth_smoke_p16.asm` proves it under real Fuse with three
checkpoints: basic correctness (`5 0 DO I . LOOP` prints `"0 1 2 3
4 "`), the CRITICAL nested-loop case (`3 0 DO 2 0 DO I . LOOP LOOP`
prints `"0 1 0 1 0 1 "` — proving an outer loop's own limit/index
survive correctly underneath an inner loop's, and are found again once
the inner loop's own `LOOP` has fully removed its own), and full
combined-phase integration (`DO`/`LOOP` + `VARIABLE` + arithmetic +
`.`, summing `0+1+2+3+4` to `10`). Wired into `rom/forth_boot.asm`'s
full chain right after `core/color.asm`; re-verified with the same
full-chain-replica diagnostic technique and a fresh boot screenshot.

With this phase, `DO`/`LOOP` is no longer on the open list — `FILL`,
hi-res mode, and decimal-number multiply/divide remain, along with the
tracked-but-unscheduled 64-column text mode stretch goal below.

## Phase 17 — FILL and AT-XY

**Status: done.** `core/moregfx.asm` adds `FILL ( x y -- )` and
`AT-XY ( col row -- )` — the rest of the "More graphics" gap short of
hi-res mode, which remains a bigger undertaking, left open. `FILL`
wraps `kernel/graphics`'s own `GFX_FILL` (a proven flood-fill routine,
already inherited and unused by this project until now), picking up
`CURRENT_ATTR` the same way `PLOT`/`LINE`/`CIRCLE` have since Phase 15
— setting `INK` before a `FILL` colors it, exactly like it colors a
shape. `AT-XY` moves `core/print.asm`'s own `PRINT_ROW`/`PRINT_COL`
directly, so the next `EMIT`/`.`/`."` lands wherever it's pointed
instead of wherever printing last left off.

**A real bug caught in the test, not the implementation — the same
discipline that caught Phase 16's own test bug.** The first draft of
`rom/forth_smoke_p17.asm`'s `AT-XY` checkpoint used the wrong argument
order calling `kernel/graphics`'s `GFX_READ_PIXEL` to verify a pixel
had actually been drawn: that routine's real contract is `B = x (pixel
column), C = y (pixel row)`, but the checkpoint's own helper had
conflated it with `GFX_CELL_ATTR_ADDR`'s *different* convention
(`B = row, C = column`, in cell units) used earlier in the same file —
two genuinely different coordinate systems with genuinely different
argument orders, easy to mix up. The checkpoint failed with the
character visibly drawn in the right place on screen, which is exactly
what made this worth tracking down rather than dismissing — confirmed
by reading `GFX_READ_PIXEL`'s own documented header rather than
guessing, then fixed by swapping which loop variable feeds `B` versus
`C`.

`rom/forth_smoke_p17.asm` proves both under real Fuse with three
checkpoints: `FILL` (draw a `CIRCLE` outline, set `INK`, `FILL` its
interior — verifying a pixel inside is now set, the covering cell's
attribute has the new ink color, and a pixel far outside stays clear,
proving the fill stayed bounded), `AT-XY` + `EMIT` (verifying both
`PRINT_ROW`/`PRINT_COL` land correctly and a real pixel was drawn in
that exact screen cell), and `AT-XY` positioned right at the
column-31 wrap boundary (proving it doesn't disturb `core/print.asm`'s
own existing wrap logic). Wired into `rom/forth_boot.asm`'s full chain
right after `core/doloop.asm`; re-verified with the same
full-chain-replica diagnostic technique and a fresh boot screenshot.

Hi-res graphics mode and decimal-number multiply/divide are the only
items left on the original gap list, along with the
tracked-but-unscheduled 64-column text mode stretch goal below.

## Phase 18 — F* (float multiply)

**Status: done.** `core/floatmul.asm` adds `F* ( f1 f2 -- f1*f2 )` —
the first half of the "decimal number... multiply, and divide" gap.
`F/` (division) is deliberately not this phase — a 32-bit dividend /
16-bit divisor routine is real, harder follow-up work with its own
edge cases, not rushed in alongside `F*`.

**A real design mistake caught by hand-tracing, before ever
assembling it, not after.** `kernel/math`'s own `MATH_MULTIPLY16` only
produces a 16-bit truncated product — useless for a float multiply,
which needs the FULL 32-bit product of two 16-bit mantissas to
normalize correctly. The first draft wrote a private 32-bit widening
multiply (`F_UMUL32`) but then took its high 16 bits unconditionally,
reasoning that "reasonably scaled" mantissas would naturally be
top-heavy. Hand-tracing `2.0*3.0` (mantissas 256 and 384, from
`core/float.asm`'s own smoke-test convention) exposed the flaw before
any of it was ever run: their product is 98304 (`$00018000`) — the
high word is just 1, and discarding the low word (`$8000`, nearly half
the true magnitude) gave 4.0, not 6.0. A fixed-position window is wrong
whenever the product's significant bits don't land in that exact
window, which is most of the time for realistic inputs, not a rare
edge case.

**The real fix: proper normalization.** `F_NORMALIZE32` shifts the
32-bit product right while it doesn't fit in 15 bits, then left while
it's using fewer than 14 — landing the result in the same
"positive, near-full-range" shape `core/float.asm`'s own test mantissas
already use, tracking the net shift to fold into the result's
exponent. Both loops are bounded (at most ~16 shrink iterations for
the largest possible product; at most ~14 grow iterations for the
smallest). Hand-verified against three cases before trusting it —
`2.0*3.0=6.0` (2 shrink steps), `0.5*0.5=0.25` (2 shrink steps, a
different starting shape), and `1.0*1.0=1.0` (14 grow steps, the
opposite direction entirely) — see `core/floatmul.asm`'s own header
for the full worked arithmetic. Since normalization guarantees the
final magnitude fits in 15 bits before sign is reapplied, sign handling
only ever needs a plain 16-bit negate (`kernel/math`'s own
`MATH_NEGATE16`) — no 32-bit negation needed at all, simpler than the
discarded first draft.

**A second real structural bug caught before it shipped: a hardcoded
dictionary-chain anchor that would have collided with
`core/mode64.asm`.** The first draft's `H_FSTAR` hardcoded
`DW H_FMINUS` (core/float.asm's own tail) instead of chaining through
`DICT_CHAIN_POINT` — but `core/mode64.asm`'s own `H_64COL` *already*
hardcodes onto that exact same anchor, and `rom/forth_boot.asm`
includes both. Two words hardcoded onto the same tail are exactly the
tree-vs-chain bug `DICT_CHAIN_POINT` was invented to prevent back in
Phase 9 — caught here by recognizing the pattern before ever wiring it
into `forth_boot.asm`, not discovered later as a mysteriously
unreachable word. Fixed by chaining `H_FSTAR` through
`DICT_CHAIN_POINT` like every other addition since Phase 10, and
splicing `core/floatmul.asm`'s own inclusion between `core/mode64.asm`
and `core/print.asm` in `rom/forth_boot.asm`.

`rom/forth_smoke_p18.asm` proves `F*` under real Fuse with all four
hand-verified cases (the three normalization cases above, plus
`-2.0*3.0=-6.0` for sign handling). Wired into `rom/forth_boot.asm`'s
full chain; re-verified with a deterministic full-chain diagnostic
that checks both `F*`'s own correctness AND that `64COL` (from
`core/mode64.asm`, spliced right before `core/floatmul.asm` in the
chain) is still `FIND`-able — confirming the chain-anchor fix actually
worked, not just that it compiled — plus a fresh boot screenshot.

## Phase 19 — F/ (float divide)

**Status: done.** `core/floatdiv.asm` adds `F/ ( f1 f2 -- f1/f2 )`,
completing the decimal multiply/divide gap. This is the harder of the
two — division's own version of the exact problem `F*` already solved,
approached from the opposite direction.

**Derived by direct analogy to `F*`'s already-solved normalization
problem, then hand-verified before trusting it — not designed from
scratch by trial and error.** Dividing two mantissas directly
(`abs(m1)/abs(m2)`, plain 16-bit integer division) would truncate to 0
almost every time a realistic `abs(m1) < abs(m2)` — the same
"naive truncation destroys the precision" failure `core/floatmul.asm`'s
own header already describes for its discarded first draft. The fix is
`F*`'s mirror image: scale the *dividend* up by 2^16 before dividing
(representing `abs(m1)` as a 32-bit value with `abs(m1)` itself in the
high word and 0 in the low word), divide that by `abs(m2)` via a new
32-bit-dividend/16-bit-divisor restoring division
(`F_UDIV32BY16`, the same shape as `kernel/math`'s own `MATH_UDIV16`,
widened), and hand the raw 32-bit quotient to `F_NORMALIZE32` — reusing
Phase 18's own routine completely unchanged, not a second copy of the
same shrink/grow logic. The exponent formula was worked out
algebraically (`e1-e2-16+F_NORM_SHIFT`) and then checked against three
hand-traced cases before ever assembling any of it: `6.0/3.0=2.0` (the
shrink path, 8 iterations), `1.0/1.0=1.0` (the shrink path again, a
much shorter run), and `1.0/4.0=0.25` (the grow path — a quotient small
enough to need shifting up instead of down). These three between them
exercise `F_NORMALIZE32`'s shrink path, its boundary case, and its grow
path — confirming the *shared* routine behaves correctly when called
from a second, independent caller, not just re-proving `F*`'s own
already-verified behavior.

Divide by zero matches `kernel/math`'s own `MATH_UDIV16` convention: a
safe `(mantissa 0, exponent 0)` result rather than looping forever or
producing garbage.

`rom/forth_smoke_p19.asm` proves `F/` under real Fuse with all four
hand-verified cases (the three normalization cases above, plus
`-6.0/3.0=-2.0` for sign handling) — all four passed on the first real
Fuse run, no bugs found needing a fix this time, a real payoff of the
careful hand-verification discipline this project has applied
consistently since Phase 11. Wired into `rom/forth_boot.asm`'s full
chain (spliced between `core/floatmul.asm` and `core/print.asm`, using
`DICT_CHAIN_POINT` correctly from the start this time — Phase 18's own
hardcoded-anchor mistake wasn't repeated); re-verified with a
deterministic full-chain diagnostic that also confirms `64COL` is still
`FIND`-able, plus a fresh boot screenshot.

With this phase, decimal multiply and divide are both done.

## Phase 20 — KEY

**Status: done.** `core/key.asm` adds `KEY ( -- char )`, the input
counterpart to `EMIT` (Phase 10) — deferred since Phase 2 ("`EMIT`/
`KEY` were deliberately deferred... to keep it minimal"), never
revisited until now. A thin wrapper over `kernel/io`'s own
`IO_READ_KEY`: blocks until a real key is pressed (needs the same real
IM 1 interrupt precondition `core/editor.asm`'s `EDITOR_LOOP_LIVE` has
always had — `IO_READ_KEY` only consumes a key already latched by
`kernel/interrupt`'s `KBD_ISR_TICK`, it doesn't scan the matrix
itself), then pushes the translated code.

`rom/forth_smoke_p20.asm` proves it under real Fuse without needing a
live interrupt at all: simulating a keypress by writing
`KBD_LASTK`/`KBD_KEYHIT` directly (the same sysvars a real ISR tick
would latch) tests `KEY`'s own wrapper code in isolation, the same way
`core/editor.asm`'s own Phase 6 smoke ROM tested key handling with
canned codes instead of a live keyboard. Two checkpoints, two different
simulated keys, confirming `KEY` re-reads state each time rather than
caching. Wired into `rom/forth_boot.asm`'s full chain; re-verified with
a boot screenshot.

## Phase 21 — error feedback for an unknown word

**Status: done.** `rom/forth_boot.asm`'s own `INTERPRET_UNKNOWN_WORD`
hook — silent since Phase 9, flagged as open the whole time — now
prints `"?"` followed by a newline (via `core/print.asm`'s own `W_EMIT`,
called directly) before returning to `EDITOR_LOOP_LIVE` for a fresh
prompt. A genuine typo now looks visibly different from one that
happened to be typed slightly differently and got silently discarded.

Tested via `rom/forth_smoke_p21.asm`, which replicates
`rom/forth_boot.asm`'s own real hook verbatim (there's no way to
`INCLUDE` just that one hook without pulling in the whole
`COLD_START`, so it's copied, matching how every smoke ROM already
defines its own independent `INTERPRET_UNKNOWN_WORD`). Two checkpoints:
an unknown word prints `"?"` and a newline (`PRINT_ROW`/`PRINT_COL`
checked directly), and — the more important check — a SEPARATE, later
`INTERPRET_RUN` call still executes normally afterward, proving the
interpreter recovers rather than being left broken by the first
checkpoint's `ret`. Re-verified against the real, complete dictionary
chain (not just the isolated replica) with a deterministic diagnostic,
plus a fresh boot screenshot.

Still real, open follow-up work, not done here: no distinction between
"unknown word" and any other possible failure (there's only one kind
right now), and the rest of the current line is simply abandoned
rather than reporting which word specifically wasn't understood.

Hi-res graphics mode remains the only item left on the original gap
list, along with the tracked-but-unscheduled 64-column text mode
stretch goal below — plus `LEAVE`/`+LOOP` (deferred since Phase 16),
`F.` (printing a float — blocked on `EMIT` until Phase 10, unblocked
since but not yet built), decimal number literal parsing (so
`F+`/`F-`/`F*`/`F/` become actually typeable), and AY-3-8912 `SOUND`
(real register-level sound access, distinct from the existing simple
`BEEP` — exists and works in the sibling `ts2068rom` BASIC project via
ports `$F5`/`$F6`, never ported here), tracked as its own future phase
per the user's own request 2026-09-01.

## Future stretch goal — a real 64-column TEXT mode in the editor

**Not yet scheduled as a numbered phase — tracked here so it isn't
lost, to pick up whenever convenient.** User request, 2026-09-01,
after a live investigation (prompted by a genuine question — "can the
editor switch between 64-column and 32-column mode?") turned up an
important distinction worth recording:

**What exists today (`64COL`/`32COL`, Phase 8) is a PIXEL graphics
mode, not a text mode.** `core/print.asm`'s `EMIT`/`.`/`."` (and
therefore the whole editor) call `kernel/graphics`'s `GFX_PUTCHAR`,
which never checks `GFX_MODE` at all — text always draws the normal
8-pixel-wide font glyph into the Primary Display File, always wrapping
at column 32 (`core/print.asm`'s own hardcoded `cp 32`), regardless of
whether `64COL` is active. Confirmed directly, not just reasoned about:
a live Fuse session had the real editor render `test` perfectly legibly
on the input line while `64COL` was active, and a headless diagnostic
confirmed printed text and the screen fully recovering after switching
back to `32COL`. The only real visual effect of toggling `64COL` today
is the whole screen's background/border going to one uniform color —
and even that observation carries a caveat: **this session's Fuse
binary is patched for ULAPlus**, so port `$FF` writes (exactly what
`MODE64_ON` does) may be getting reinterpreted by that patch rather
than emulated as genuine TS2068/SCLD hardware behavior. Not yet
resolved — cross-checking in ZEsarUX (unpatched, with native ULAPlus
support) is the planned next step before trusting any further
conclusions about the *visual* side effects of `64COL`.

**Real TS2068 hardware genuinely could do 64-column text**, confirmed
via web research (not this project's own emulation): connected to a
monitor via the TS2068's separate RGB/monitor jack (a standard TV's
bandwidth can't cleanly resolve 64 columns), the machine could show 24
lines × 64 characters — but this was never a built-in ROM feature.
Third-party software provided it on top of the same underlying pixel
mode this project already ports the plotting half of: **TASWIDE**
(Tasman Software, a BASIC utility), **OS-64** (Zebra Systems, a
cartridge ROM, "fully compatible with 32 column commands and
functions"), and a program by Wes Brzozowski published in SINCUS,
October 1985. ZEsarUX's own documentation names the underlying hardware
mode "Mode 6: 512×192 monochrome" — the exact same mode
`kernel/mode64.asm`'s `MODE64_ON` already sets up (SCLD port `$FF` bits
0-2 = `%110`). The historical 64-column text tools were a **software
layer of narrower (roughly 4-pixel-wide) font glyphs drawn onto that
same 512-pixel bitmap** — not a separate hardware text mode.

**What building this for real would require, roughly scoped (not yet
designed in detail):**
- A new narrow-glyph font and a character-drawing routine to draw it
  (`kernel/graphics`'s `GFX_PUTCHAR` draws the existing 8-pixel font
  only — this needs to be new code, not a mode-aware branch inside it,
  matching this project's "never modify an inherited kernel/ file"
  practice).
- A mode-aware print/column-wrap layer (today's `PRINT_COL` wraps at a
  hardcoded 32; a real 64-column mode needs its own wrap point, and a
  decision on whether `EMIT`/`.`/`."` become mode-aware themselves or
  a parallel set of words exists instead).
- Editor integration: `core/editor.asm`'s `EDIT_BUF` is a fixed 32
  bytes today. Making 64-column mode actually *useful* for editing
  (not just cosmetically narrower glyphs showing the same 32
  characters) means growing the input line's own capacity too, not
  only how it's drawn.

This is real, multi-file design work — not a quick wrapper the way
`INK`/`PAPER` was. Sequence it whenever convenient relative to the
still-open items above (hi-res mode, `KEY`, error feedback,
`LEAVE`/`+LOOP`, `F.`, decimal literals); nothing currently planned
depends on it, and it doesn't block anything currently planned either.

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
