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

**UPDATE, Phase 31**: `BEEP`'s own raw-hardware-units behavior
described above was later replaced by a real, semitone/seconds `BEEP`
— see that phase's own section, far below. The original word still
exists, unchanged, as `core/rawbeep.asm`, purely so this phase's own
smoke ROM (`rom/forth_smoke_p5.asm`) keeps testing exactly what it
always tested; `core/ts2068.asm` itself no longer defines `BEEP` at
all.

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

**Status: `SAVE`/`LOAD` proven against a fake tape transport, AND (as of
`rom/forth_smoke_p53_realtape.asm`) against a real .TAP file under real
Fuse pulse-level tape emulation — the "never a real emulator round-trip"
gap this section used to describe is closed.** `STORAGE_RECEIVE_BLOCK`
(no `STORAGE_TEST_FAKE_RECEIVE` hook — the genuine LD-BYTES-derived
routine) decoded a real `.TAP` file (built by `tools/tape_gen_forth.py`,
which needed no hand-tuned pulse widths at all — this project's own
protocol already IS the stock Sinclair format, unlike 2068-Leap/
ts2068rom's own from-scratch one) and reproduced the exact same
Blackjack ground truth `rom/forth_smoke_p52.asm`'s own fake-tape
checkpoint established, byte for byte. Two real environment gotchas
found getting a headless run working at all, both now handled by
`tools/run_realtape_test.sh`: Fuse fully block-buffers stdout when it
isn't a real terminal (silently losing every debugger `print` on a
killed process — worked around with `script`, which allocates a real
pty), and this machine's own saved `~/.fuserc` has `detectloader`
turned off, so the emulated tape never started playing at all until
`--detect-loader` was passed explicitly on the command line. The SAVE
side (`STORAGE_SEND_BLOCK`) was not driven through Fuse's own tape
*recording* — that's a GUI-menu-only action (`Media, Tape, Record
Start`) with no CLI or debugger-command equivalent — but was judged
lower-risk anyway (no receiver-side timing ambiguity) and is separately
verified byte-for-byte against the real ROM's own SA-BYTES; the receive
side is what every past real SAVE/LOAD bug in this project actually
came from, and that's what this test exercises for real.
`core/storage.asm` + `rom/forth_smoke_p7.asm` add `SAVE`/`LOAD` as
whole-dictionary-image blobs, Jupiter-Ace-style: `SAVE "name"` and
`LOAD "name"` (or `LOAD` alone for a wildcard) call `STORAGE_SAVE`/
`STORAGE_LOAD` directly on the compiled RAM dictionary
(`FORTH_DICT_RAM` through `HERE`), no tokenizing, no per-line format —
a categorically simpler contract than BASIC's, matching the original
plan for this phase.

**Later update:** `SAVE`/`LOAD` were renamed `SAVE-LIB`/`LOAD-LIB` once
Phase 52 introduced `SAVE-TEXT`/`LOAD-TEXT`, to keep the two mechanisms
identifiable by name. That same pass also found and fixed a real,
unguarded buffer-overflow bug (`SAVE-LIB` used to `LDIR` the whole
compiled dictionary into a fixed 512-byte scratch buffer with no bounds
check at all) and replaced the old 512-byte provisional ceiling with a
researched 8190-byte one, backed by a real `THROW -8` refusal instead
of silent corruption — see `core/storage.asm`'s own header for the full
RAM-budget accounting.

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

## Phase 22 — F. (print a float)

**Status: done.** `core/floatprint.asm` adds `F. ( f -- )`, printing a
float as a signed decimal number with a fixed 4 digits after the
decimal point (e.g. `"6.0000"`, `"0.2500"`, `"-2.0000"`) — blocked on
`EMIT` existing at all until Phase 10, unblocked since but not built
until now.

**The algorithm**: scale the float's magnitude up by exactly 10000 as
an exact 32-bit integer (reusing `core/floatmul.asm`'s own `F_UMUL32`
— already a proven unsigned widening multiply), shift that scaled
value by the float's own exponent (a new small pair of helpers,
`F_SHIFT32_LEFT`/`RIGHT`), then divide by 10000 (reusing
`core/floatdiv.asm`'s own `F_UDIV32BY16`) to split cleanly into an
integer part (the quotient) and a 4-digit fractional part (the
remainder — `F_UDIV32BY16` was extended to expose it, a
backward-compatible addition `F/` itself never reads). Digits print via
`core/print.asm`'s own `UDIV10`, the same idiom `.` already uses.
Hand-verified against three cases — reusing the exact float values
already proven in Phases 18/19 — before ever assembling any of it:
`6.0` (from `F*`'s own `2.0*3.0` test), `0.25` (from `F*`'s own
`0.5*0.5` test), and `-2.0` (from `F/`'s own `-6.0/3.0` test, exercising
sign handling).

**A real register-clobbering bug caught on the very first real Fuse
run, not by hand-tracing this time** — the arithmetic itself was
correct, but a genuinely different class of mistake slipped through
review: the first draft's `PRINT_UDEC16_PAD4` (the fixed-4-digit
fractional-part printer) used register `B` as its own outer loop
counter *while calling* `UDIV10` inside that same loop — but `UDIV10`
destroys `B` internally (its own documented contract, already known,
just not cross-checked against this new caller). After the first
`UDIV10` call, `B` got silently reset, and the outer `DJNZ` then
wrapped to 255 instead of ever reaching zero — a real, live hang: the
integer part and `"."` printed correctly on screen, then execution
froze completely, confirmed by two screenshots several seconds apart
showing identical, unchanging state. Fixed by using `C` instead (which
`UDIV10` never touches, confirmed by re-reading its own header) for the
outer counter, matching the same register discipline
`core/print.asm`'s own `W_DOT` already uses in its analogous loop. All
four checkpoints passed cleanly once fixed.

`rom/forth_smoke_p22.asm` proves `F.` under real Fuse with the three
hand-verified cases above. Wired into `rom/forth_boot.asm`'s full chain
right after `core/print.asm`; re-verified with a deterministic
full-chain diagnostic that also confirms `KEY` is still `FIND`-able,
plus a fresh boot screenshot.

## Phase 23 — decimal number literal parsing

**Status: done.** Typing a decimal number literal like `3.5` now
pushes a real float directly, in both interpret and compile contexts —
the last piece keeping `F+`/`F-`/`F*`/`F/`/`F.` (Phases 8/18/19/22)
reachable only by feeding the float stack directly via `FPUSH`, never
by typing an expression.

**The real risk, and how it was managed**: `core/interp.asm`'s `NUMBER`
and `INTERPRET_RUN` are the single most shared routines in this
project — every smoke ROM and `rom/forth_boot.asm` depends on them.
Rather than changing them unconditionally, both call sites are wrapped
in `IFDEF DECIMAL_NUMBER_ENABLED` / `ENDIF` (`core/decimal.asm`'s own
new file). The including ROM must `DEFINE DECIMAL_NUMBER_ENABLED`
before `INCLUDE`ing `core/interp.asm` to opt in; any ROM that doesn't —
every existing smoke ROM, unchanged — gets `core/interp.asm`'s compiled
bytes byte-for-byte IDENTICAL to before this phase. This was verified
directly, not just reasoned about: `rom/forth_smoke_p3.asm` (which
doesn't even `INCLUDE core/float.asm`, so an ungated reference to a
float routine from dead code would have been a hard assembly error,
not just an unreachable branch), `rom/forth_smoke_p9.asm`, and
`rom/forth_smoke_p16.asm` were all rebuilt and diffed byte-for-byte
against their prior output — identical in every case.

**The algorithm**, reusing Phase 18/19's own machinery rather than
inventing a new one: accumulate the token's digits into one running
integer (the exact `*10+digit` technique `NUMBER` already uses for
plain integers, dot skipped over instead of rejected), counting how
many digits followed the decimal point; widen that integer by 2^16 and
divide by 10^(digit count after the point) via `core/floatdiv.asm`'s
own `F_UDIV32BY16` — exactly `F/`'s own "scale the dividend up, then
divide" trick, reused verbatim because it's the identical problem;
normalize the 32-bit quotient via `core/floatmul.asm`'s own
`F_NORMALIZE32` (also reused unchanged); final exponent =
`F_NORM_SHIFT - 16`. Hand-verified against two cases before ever
assembling any of it: `"3.5"` → mantissa 28672, exponent -13 (exactly
3.5), and `"0.25"` → mantissa 16384, exponent -16 — the SAME
representation already hand-picked by a human for "0.25" in three
earlier smoke ROMs (Phases 18/19/22), a genuine cross-check that this
parser's output matches independently-chosen values for the same
number.

Compiling a decimal literal inside a colon definition needed its own
small addition: `DOFLIT` (`core/interp.asm`'s own `DOLIT` idiom widened
from a 2-byte integer to a 3-byte float) and `COMPILE_FLOAT_LITERAL`
(the analogous widening of `COMPILE_LITERAL`) — both in
`core/decimal.asm`, mirroring established patterns rather than
inventing new ones.

**A real, timely warning caught and fixed along the way**: adding the
new `IFDEF` block to `NUMBER` made the routine longer, pushing an
*existing*, unrelated `jr z, .fail` within 10 bytes of `JR`'s ±127-byte
range limit — flagged by `tools/check_z80_opcodes.py`, whose own
documentation says exactly this is worth a second look when a routine
grows. Fixed by converting that one jump to `JP` (unlimited range) —
gated behind the same `IFDEF`, so a ROM that never opts in keeps its
original `JR` untouched, preserving its own byte-identical guarantee.

`rom/forth_smoke_p23.asm` proves it under real Fuse with three
checkpoints: the two hand-verified parsing cases above, plus a full
combined test (`: DOUBLEIT 2.0 F* ; 3.5 DOUBLEIT F.`) exercising a
decimal literal typed directly, one compiled inside a word definition,
`F*`, and `F.` together — printing `"7.0000"` correctly on the very
first real Fuse run. Wired into `rom/forth_boot.asm`'s full chain;
re-verified with a deterministic full-chain diagnostic (also confirming
`KEY` is still `FIND`-able) plus a fresh boot screenshot.

Hi-res graphics mode remains the only item left on the original gap
list, along with the tracked-but-unscheduled 64-column text mode
stretch goal below — plus `LEAVE`/`+LOOP` (deferred since Phase 16,
picked up next as Phase 24) and AY-3-8912 `SOUND` (real register-level
sound access, distinct from the existing simple `BEEP` — exists and
works in the sibling `ts2068rom` BASIC project via ports `$F5`/`$F6`,
never ported here), tracked as its own future phase per the user's own
request 2026-09-01.

## Phase 24 — LEAVE and +LOOP

**Status: done.** `core/doloop.asm` (Phase 16) gains `LEAVE` (exit a
`DO` loop early) and `+LOOP` (step by something other than 1, including
negative) — the two items deferred from Phase 16 as "the smallest
provable slice."

**`+LOOP`'s own algorithm**: plain `LOOP` (Phase 16) can test for EXACT
equality between the incremented index and `limit`, because stepping by
1 can never jump past `limit` without landing on it first. `+LOOP`'s
step can be any value, including negative, so the index can cross
`limit` cleanly without ever equaling it — the standard fix (used by
real Forth systems for the same reason) is to compare the SIGN of
`(index - limit)` before and after adding the step; once that sign
flips, the boundary has been crossed. Hand-verified against three cases
before trusting it: ascending step 1 (`limit=3, start=0` — 3 passes,
matching plain `LOOP`'s own known-correct behavior exactly), ascending
step 2 (`limit=10, start=0` — the crossing lands one step FROM 8 to 10,
never touching 9), and descending step -1 (`limit=0, start=5` — 6
passes, `I` = 5 down to 0 inclusive).

**`LEAVE`'s own design question, and a real bug caught along the way,
not just reasoned past**: `LEAVE` must compile an unconditional branch
to wherever the loop ends, but it's always compiled BEFORE that address
is known — the same forward-reference problem `IF`/`WHILE`
(core/control.asm, core/loop.asm) already solve by leaving a
placeholder address on the borrowed compile-time (data) stack for a
later word to patch. The FIRST implementation reused that exact
mechanism for `LEAVE` too (a linked list of placeholders, threaded
through their own still-blank inline bytes, with the list's head kept
on the same borrowed stack `DO` already uses for its own loop-start
address) — and it was wrong, caught by a genuinely erratic real Fuse
run (garbage `PRINT_ROW`, no output at all), not by review: `LEAVE` is
essentially always written as `IF LEAVE THEN`, and at the exact moment
`LEAVE` compiles, `IF`'s own not-yet-patched placeholder — not the
loop's own head — is what's actually sitting on top of that shared
stack, since `IF` hasn't reached its own `THEN` yet. `LEAVE` was
silently corrupting `IF`'s own bookkeeping instead of reading the
loop's.

**The fix**: a dedicated side table, `LEAVE_HEAD_TABLE`, indexed by
loop nesting depth (`LEAVE_DEPTH`) rather than by stack position —
immune to whatever `IF`/`BEGIN` placeholders happen to be live on the
shared stack at the time. `DO` increments `LEAVE_DEPTH` and clears its
new slot; `LEAVE` reads/writes only the slot for the CURRENT depth,
regardless of anything else mid-compile around it; `LOOP`/`+LOOP` patch
that slot's whole chain once the true exit address is finally known,
then decrement `LEAVE_DEPTH` — since an outer loop's own slot is never
touched while an inner one is open, this "restores" the outer loop's
own pending chain with no explicit save/restore step. `DO`'s own
loop-start address stays on the ordinary borrowed stack unchanged —
that value was never the problem, since `IF`/`THEN` always fully closes
before `LOOP` is reached in well-formed code; only `LEAVE`'s own
bookkeeping needed to move out. `LEAVE_DEPTH` must start at 0 —
`rom/forth_boot.asm`, `rom/forth_smoke_p16.asm`, and
`rom/forth_smoke_p24.asm`'s own `COLD_START` each gained the one extra
zeroing line this required, alongside `STATE`/`LATEST`/etc.

**A second real bug, also Fuse-reproduced**: after fixing the above,
`LEAVE` compiled but jumped to garbage. Root cause: `LOOP`/`+LOOP`'s own
compile-time code read `DE = (HERE)` (the real loop-exit address) and
THEN called the shared `LEAVE_SLOT_ADDR_CALC` helper — which clobbers
`DE` internally as part of its own table-address arithmetic. By the
time the loop's pending `LEAVE` chain got patched, `DE` held
`LEAVE_HEAD_TABLE`'s own constant address instead of the real exit
address, so every `LEAVE` jumped into raw RAM data. Fixed by reordering
both `W_LOOP` and `W_PLUSLOOP` to call `LEAVE_SLOT_ADDR_CALC` FIRST,
reading `(HERE)` only afterward (safe, since nothing in between changes
`HERE`).

**A third, much smaller bug, caught by the static checker before ever
running anything**: `W_LEAVE`'s own chain-linking code used
`ld (de), l` / `ld (de), h` to write the new head into the table slot —
neither is a real Z80 opcode (only `(DE)`/`(BC)` indirect stores via
`A` exist). `tools/check_z80_opcodes.py` flagged both immediately;
fixed by swapping which register held the address vs. the value being
stored.

**A fourth bug, from an overly hasty scratch-address choice**: `+LOOP`'s
own new scratch RAM was placed by extending Phase 23's own block
(`core/decimal.asm`'s `DIVISOR10`) forward by a few bytes — without
checking whether OTHER files also claim addresses in that range. They
did: `core/print.asm`'s `PRINT_ROW`/`PRINT_COL` sit exactly there. Two
of the float/mode64 scratch blocks earlier in this same `$87xx` range
already legitimately overlap each other (safe only because those
features never run interleaved with one another) — but `+LOOP` almost
always shares a loop body with `.`, so the two ARE live at the same
time, and every `+LOOP` pass was silently corrupting the print
cursor. Root-caused via a purpose-built diagnostic ROM that captured
`PRINT_ROW`/`PRINT_COL` as raw hex digits on a separate screen row
after each isolated test, rather than relying on the smoke ROM's own
pass/fail border color (which turned out to be actively misleading
here — see below). Fixed by grepping every existing `EQU $87..` across
`core/`, `kernel/`, and `include/` first, then picking the genuinely
free range starting right after the last claimed byte
(`core/ts2068.asm`'s own `CURRENT_ATTR`).

**A verification-methodology lesson worth keeping**: the smoke ROM's
own checkpoints reset `PRINT_ROW`/`PRINT_COL` to 0 between checkpoints
WITHOUT clearing the screen (established, working convention since
Phase 16) — so a LATER checkpoint's output can fully overwrite an
EARLIER one's on screen, and a border-color failure code can reflect a
DIFFERENT checkpoint than whichever one's text is still visible. Several
early debugging screenshots were misread for exactly this reason before
switching to isolated, single-checkpoint diagnostic ROMs (one word under
test at a time, real captured `PRINT_ROW`/`PRINT_COL` values rendered
as hex, no pass/fail coloring to misinterpret) — the technique that
actually found all three bugs above. Once each of `LEAVE`, `+LOOP`, and
nested `LEAVE` were separately confirmed correct in isolation, the
combined three-checkpoint `rom/forth_smoke_p24.asm` passed on its very
first run afterward.

`rom/forth_smoke_p24.asm` proves it under real Fuse: `LEAVE` firing
partway through a loop (`10 0 DO I . I 3 = IF LEAVE THEN LOOP` prints
`"0 1 2 3"`), `+LOOP` stepping by 2 (`"0 2 4 6 8"`), and — the critical
nested-safety check, re-verifying Phase 16's own already-proven nested
`DO`/`LOOP` stack discipline still holds with `LEAVE` added — an inner
loop's `LEAVE` exiting only the inner loop three separate times while
the outer loop keeps counting (`"0 1 2 0 1 2 0 1 2"`), not just once.
Also re-verified: `rom/forth_smoke_p16.asm` (plain `DO`/`LOOP`/`I`,
no `LEAVE`/`+LOOP` in its own source) still passes unchanged after the
`LEAVE_DEPTH` addition, and `rom/forth_boot.asm` assembles and boots
cleanly with the extended dictionary.

## Phase 25 — ABS, SGN, MOD, SQRT, RND, RANDOMIZE

**Status: done.** The first phase driven by a direct, read-only audit
comparing 2068-Leap's own BASIC ROM (`~/ts2068rom`) against this
project's dictionary, run to find real feature gaps rather than
guessing. The audit found six BASIC features with genuinely no Forth
equivalent, ranked by real-world impact: `RND`/`RANDOMISE`, string
handling, arrays/`DIM`, line-input, math functions, and `DEF FN`. This
phase covers the math-function half of that list; the rest (string
handling, arrays, line-input) follow as later phases. `DEF FN` was
deliberately NOT implemented as a separate word — ANS Forth itself has
no equivalent either, because `:` already does that job, more
generally; adding a redundant synonym word would be busywork with no
real capability behind it.

**A pleasant surprise cutting the actual work way down**: `kernel/math/
math.asm` (inherited read-only from 2068-Leap, already `INCLUDE`d by
every ROM in this project for other reasons) already contains
`MATH_ABS16`, `MATH_SGN16`, `MATH_MOD16`, `MATH_SQRT16`, `MATH_RND16`,
and `MATH_RND_SEED` — fully implemented, documented, and independently
verified (each routine's own header in that file describes real
verification work: exhaustive 65,536-case checks for `MATH_SQRT16`,
a systematic LFSR tap search for `MATH_RND16`, 6,048 Python-simulated
cases for `MATH_MOD16`). `core/mathfn.asm` (new) is nothing more than
six THIN WRAPPERS exposing these as Forth words — `ABS`, `SGN`, `MOD`,
`SQRT`, `RND`, `RANDOMIZE` — no new algorithm written, the same
"reuse kernel/, don't reinvent it" pattern `core/ts2068.asm`'s own
`PLOT`/`LINE`/`CIRCLE`/`BEEP` already established for
`kernel/graphics`/`kernel/sound`. All six operate on the plain integer
data stack (IX), matching `kernel/math`'s own integer-only scope — this
project's separate float stack (IY) has its own `F+`/`F-`/`F*`/`F/`
words by deliberate design (`docs/numeric_model.md`); float versions of
some of these (starting with a float square root) are a natural later
addition, not attempted here.

`rom/forth_smoke_p25.asm` proves all six under real Fuse, five
checkpoints: `ABS`, `SGN` (all three cases: negative/zero/positive),
`MOD` (both dividend-sign cases, matching `MATH_MOD16`'s own documented
convention), `SQRT` (two truncating cases), and — the most interesting
check — `RND` seeded deterministically (`12345 RANDOMIZE`) then called
ten times, with the EXACT expected sequence (`72 70 35 67 33 0 84 92 96
32`) independently derived by hand-simulating `MATH_RND16`'s own
documented LFSR algorithm in Python *before* ever running the real ROM
— a genuine cross-check, not just "it printed something plausible."
The real Fuse run matched the Python simulation exactly on the first
try.

**A real, previously-undetected bug found and fixed along the way, in
the single most shared routine in the whole project**: while building a
diagnostic to verify the full dictionary chain (`rom/forth_boot.asm`,
which — unlike this phase's own smoke ROM — has `DECIMAL_NUMBER_ENABLED`
turned on), typing a negative integer literal like `-5 ABS .` failed
with "unknown word," even though positive integers, and positive
decimal literals, both worked fine. Root cause, found by bisecting down
to the smallest possible reproduction (a 6-file ROM: `dict.asm`,
`interp.asm` with the define, `print.asm`, `float.asm`, `floatmul.asm`,
`floatdiv.asm`, `decimal.asm`): `core/decimal.asm`'s own
`CHECK_FOR_DOT` (added in Phase 23) is explicitly documented as
"Destroys: AF, BC, HL" — it walks its own copy of `HL` across the whole
token scanning for a `.`. But `core/interp.asm`'s `NUMBER`, right after
calling it, reads `(HL)` again to check for a leading `-`, silently
assuming `HL` still pointed at the token's first character. It didn't —
`CHECK_FOR_DOT` had walked it all the way to the token's end. For a
negative token, this stale read almost never equals `-`, so `NUMBER`
took the "not negative" branch without consuming the `-` character;
the digit-parsing loop then correctly failed on the unconsumed `-`
itself (not a valid digit), and `NUMBER` reported failure, triggering
`INTERPRET_UNKNOWN_WORD`. Positive integers were never affected: the
same stale-`HL` read happens for them too, but its wrong answer just
happens not to matter (the "not negative" branch is the CORRECT branch
for a positive token regardless of what triggered it) — pure
coincidence, not a sign the rest of the code was more careful there.
This bug had shipped silently since Phase 23 landed (2026-09-01/02)
because no smoke ROM before now ever combined `DECIMAL_NUMBER_ENABLED`
with a negative WHOLE number (Phase 23's own checkpoints only used
positive decimals like `3.5`/`0.25`; Phase 24's `LEAVE`/`+LOOP` smoke
ROM never defines `DECIMAL_NUMBER_ENABLED` at all).

Fixed with a one-line `ld hl, (NUM_PTR)` reload, added inside the same
`IFDEF DECIMAL_NUMBER_ENABLED` block that made the bug possible in the
first place — so a ROM that never opts into decimal literals never
compiles this line either, and stays byte-for-byte identical to
before, the same discipline Phase 23 itself established. Verified
directly, not just reasoned about: `forth_smoke_p3`, `forth_smoke_p9`,
and `forth_smoke_p16` (none of which define
`DECIMAL_NUMBER_ENABLED`) were rebuilt and diffed byte-for-byte against
their pre-fix output — identical in every case. `forth_smoke_p23`
(decimal literals) and `forth_smoke_p24` (`LEAVE`/`+LOOP`) were both
re-run under real Fuse and still pass. `rom/forth_boot.asm` was
rebuilt and the same minimal reproduction, now fixed, was re-confirmed
under Fuse, alongside the full `-5 ABS . 12345 RANDOMIZE 100 RND .`
combined check.

`core/mathfn.asm` is wired into `rom/forth_boot.asm`'s own dictionary
chain right after `core/key.asm` (before `core/editor.asm`, which adds
no dictionary words of its own and must stay last).

## Phase 26 — ARRAY and CELLS

**Status: done.** The second phase closing a real gap from the
BASIC-vs-Forth audit (Phase 25's own header): BASIC's `DIM` (numeric
arrays) had no Forth equivalent. `core/array.asm` adds:

- `ARRAY ( n "name" -- )` — creates `<name>` such that
  `<name> ( -- addr )` pushes the address of a fresh, zero-initialized
  block of `n` 2-byte cells.
- `CELLS ( n -- n*2 )` — converts a cell count into a byte offset
  (just a left shift, since this project's cell size is 2 bytes) —
  named for intent (`3 CELLS name +` reads clearer than `3 2 * name
  +`), matching how real Forth code writes array access, not a
  meaningfully different computation.

**Design choice, and why**: neither a dedicated indexing word nor a
real `CREATE`/`ALLOT` pair (this project doesn't have one — the same
gap `core/variable.asm`'s own header already notes for `VARIABLE`/
`CONSTANT`) — `ARRAY`'s own runtime is the identical compiled-literal-
then-RET idiom those two already established, just with `n*2` reserved
bytes after it instead of a fixed 2, and elements are addressed with
plain `@`/`!` at `index CELLS name +`. This is not a simplification for
this project's own sake — it's the SAME idiom real, ANS-conformant
Forth systems use for `CREATE`-based arrays; there is no special array-
indexing operator in standard Forth either. A single combined `ARRAY`
word (rather than separate `CREATE`+`ALLOT` primitives) was chosen as
the more direct, appropriately-scoped translation of `DIM`'s own single-
statement shape, and because `VARIABLE`/`CONSTANT` already established
the "one word, one header-building routine" pattern this reuses almost
line-for-line. A generic `CREATE`/`ALLOT` remains a reasonable future
generalization (strings, a later phase, will need their own memory-
reservation primitive) but wasn't necessary to close this specific,
concrete gap.

`rom/forth_smoke_p26.asm` proves it under real Fuse, three checkpoints:
a freshly-created array reads back as zero at element 0; a
`CELLS`-indexed write (`99 3 CELLS NUMS + !`) and read round-trip
correctly; and — the check that actually exercises the zero-init loop's
own correctness, not just its first iteration — every OTHER element
(0, 1, 2) still reads as zero after that write to element 3, confirming
the loop covers the WHOLE block and the write didn't corrupt a
neighboring cell. All three passed on the first real Fuse run. Also
re-verified end-to-end with a full-chain diagnostic against
`rom/forth_boot.asm` (`10 ARRAY A 99 3 CELLS A + ! 3 CELLS A + @ .`),
learning from Phase 25's own lesson that a phase's isolated smoke ROM
passing doesn't guarantee the real product ROM's full dictionary chain
does too. `core/array.asm` is wired in right after `core/mathfn.asm`
(before `core/editor.asm`, same reasoning as Phase 25).

## Phase 27 — string handling (S", TYPE, STRING, PLACE, COUNT, LEN, VAL)

**Status: done.** The biggest single gap named by the BASIC-vs-Forth
audit: 2068-Forth had NO string handling at all before this phase.
`core/string.asm` adds a deliberately scoped slice of it — `S"`
(string literal), `TYPE` (print an addr/len string), `STRING` (a named
mutable buffer), `PLACE` (fill a buffer from an addr/len string),
`COUNT` (bridge a counted string to addr/len), `LEN` (a counted
string's own length), and `VAL` (parse an addr/len string as an
integer) — while deliberately NOT including `CHR$`/`STR$`/`UPPER$`/
`LOWER$`/`LEFT$`/`RIGHT$`/`INSTR`/`CODE`. The six words landed turn "no
string handling at all" into "hold text in a variable, print it,
measure it, read a number out of it" — the part of the gap that
actually blocked real programs; the rest are conveniences layered on
the SAME `(addr len)`/counted-string foundation, better added once real
programs reveal which are actually missed.

**Representation, and why**: strings are the standard Forth
`(addr len)` pair on the stack (addr deeper, len on top, matching ANS
Forth's own convention) for anything TRANSIENT (a literal, a slice),
plus a COUNTED string (1 length byte + data) for anything PERSISTENT
(a named `STRING` buffer) — not a new convention invented for this
project: counted strings are exactly what this project's own
`WORD_BUF` (core/interp.asm) and every dictionary name field already
use internally. `COUNT` is the standard bridge between the two.
`VAL` duplicates `NUMBER`'s own digit-accumulation algorithm rather
than sharing it, for the same reason `core/variable.asm`'s own header
already gives for duplicating header-building code: never modify an
already-stable, widely-shared file (`core/interp.asm`) for a later
phase's convenience.

**A real bug found and fixed, in two attempts, not one** — this is the
most instructive verification story in the project so far:

1. The FIRST version of `S"` compiled `CALL DOSSTR` plus the string's
   own bytes and simply returned, exactly matching `."`'s own established
   shape. This is correct ONLY inside a colon definition, where the
   surrounding word's own later execution eventually reaches and runs
   that compiled code. Every planned use of `S"` in this phase's own
   docs and smoke-ROM design — `S" HELLO" BUF PLACE`, `S" 1234" VAL .`
   — is written directly at the top level, outside any `:`/`;`. Used
   that way, NOTHING ever calls the freshly-compiled bytes, so NOTHING
   is pushed. Caught by literally measuring the data stack pointer's
   own depth before and after `S" AB"` at top level in a real Fuse
   run: zero change, not the expected 4 bytes.
2. The FIRST fix made `W_SQUOTE` check `STATE` and, when interpreting,
   `jp` straight into the just-compiled `CALL DOSSTR`, reasoning that
   "`DOSSTR` pushes `(addr len)` and returns correctly no matter who
   called it." True in isolation — DOSSTR's own contract is real — but
   wrong in this context: DOSSTR returns to whatever code FOLLOWS its
   inline string data, which is the next compiled word when embedded in
   a colon definition, but is just blank, uninitialized dictionary
   space at the top level. A real Fuse run hung completely (not a clean
   failure — a wild jump into garbage), caught by the SAME smoke ROM
   that was supposed to prove the feature worked.
3. The actual fix: `W_SQUOTE`, when interpreting, pushes `(addr len)`
   onto the data stack ITSELF — the same two values `DOSSTR` would have
   — and returns normally, never invoking `DOSSTR` or relying on its
   "return to what follows" assumption at all. It also rolls `HERE`
   back to reclaim the dictionary bytes used in this case, since none
   of them are needed once the values are already on the stack.
   Verified directly: a purpose-built diagnostic confirmed the stack
   depth changes by exactly 4 bytes now, then the full smoke ROM, then
   several consecutive top-level uses AND one nested inside a colon
   definition together in one source string, to prove neither case
   broke the other.

**A separate, real methodology bug found while investigating the
above** — this smoke ROM's own first draft reported a false all-green
pass while checkpoint 4 (`COUNT`+`TYPE`) was silently failing
underneath it: `FAIL_TEST` writes whatever's in `CHECKPOINT_NUM`
directly as the border color, and `PASS_TEST` also uses border color
`4` (green) for "everything passed" — a checkpoint literally numbered 4
makes its own failure color INDISTINGUISHABLE from genuine success.
Caught only by switching from trusting the border color to checking
the actual printed text with a width-and-content check, not just a
column count (an earlier width-only check had already been fooled once
this same phase: `"0 "` and `"5 "` are both 2 characters, so a broken
`PLACE` leaving a buffer's length at 0 "passed" a check meant to catch
`5`). Fixed by renumbering `forth_smoke_p27.asm`'s own checkpoint
colors to skip `4` entirely (1, 2, 3, 5, 6). Given this is a real,
previously-shipped-and-undetected class of bug, every other smoke ROM
with 4 or more checkpoints was audited: `forth_smoke_p10.asm` and
`forth_smoke_p25.asm` (5 checkpoints each) are safe by construction —
checkpoint 5 in each is a DIFFERENT, independently distinguishable
result, so its own successful completion is itself proof checkpoint 4
already passed for real (the sequential jump-to-`FAIL_TEST`-on-mismatch
structure means checkpoint 5 never runs at all if checkpoint 4 failed).
`forth_smoke_p18.asm` and `forth_smoke_p19.asm` (F*/F/, exactly 4
checkpoints each, the highest-risk case with no later checkpoint to
serve as a witness) were each re-verified directly: temporarily
relabeling checkpoint 4's own border color away from `4` and re-running
under real Fuse confirmed a genuine, unambiguous green pass in both —
both are correct in practice, this was a real blind spot in the
verification method, not a real defect in either feature.

`rom/forth_smoke_p27.asm` proves the whole phase under real Fuse, five
checkpoints (numbered 1, 2, 3, 5, 6 — see above): `S"`+`TYPE` inside a
colon definition, `STRING` creating an empty buffer, `PLACE`+`LEN`
round-tripping a value, `COUNT`+`TYPE` reading it back as text, and
`VAL` parsing a positive integer, a negative one, and an empty string
(returning 0, no error signal). Also re-verified end-to-end against
`rom/forth_boot.asm`'s own full dictionary chain with several
combined-word diagnostics, including multiple consecutive top-level
`S"` uses and one nested inside a colon definition in the same source
string. `core/string.asm` is wired in right after `core/array.asm`
(before `core/editor.asm`, same reasoning as Phases 25 and 26).

## Phase 28 — ACCEPT and INPUT (line input)

**Status: done.** The last of the six real gaps found by the
BASIC-vs-Forth audit (Phase 25's own header): `KEY` (Phase 20) reads a
single raw keypress, but there was no way to read a whole LINE of
typed text, the way BASIC's own `INPUT` statement does. `core/
input.asm` adds `ACCEPT ( dest maxlen -- len )` — the standard ANS
Forth line-input word, not a name invented for this project — and
`INPUT ( -- n )`, a BASIC-style convenience built on top of it that
reads a line into a small internal buffer and parses it with Phase
27's own `VAL`, matching the exact shape of BASIC's `INPUT A` for a
numeric variable.

**A real verification problem this phase's own smoke ROM had to solve,
different from every earlier phase**: `KEY`'s own Phase 20 smoke ROM
tested a single simulated keypress by writing `KBD_LASTK`/`KBD_KEYHIT`
directly before one `INTERPRET_RUN` call — sufficient because `KEY`
itself only ever reads ONE key per call. `ACCEPT`'s own internal loop
calls the same underlying read routine MANY times in a row with no
point for outside test code to "step in" between characters — the
single-write trick has nothing to attach to. The fix: real `IM 1`
interrupts, the same wiring `rom/forth_smoke_p9.asm` first proved
against 2068-Leap's own working ROM files, but with this smoke ROM's
own `RST 38` handler replaced by a scripted fake keyboard ISR that
feeds the NEXT character from a small canned array into `KBD_LASTK`/
`KBD_KEYHIT` on every real hardware tick (Fuse's own emulated ~50Hz
frame interrupt) — exactly what a real keyboard-scanning ISR does on
every tick, just from a script instead of the physical keyboard
matrix. `ACCEPT`'s own busy-wait loop picks up one new character per
tick automatically, with no changes needed to `ACCEPT` itself to make
it testable this way.

**A real, if minor, bug caught immediately by the assembler, not by
running anything**: the first draft named `INPUT`'s own internal
buffer `INPUT_BUF` — sjasmplus rejected it outright with "Duplicate
label," because `include/sysvars.inc` (inherited read-only from
2068-Leap) already has its own, completely unrelated `INPUT_BUF` (8
bytes of raw digit-accumulation scratch for BASIC's own numeric input
routines). Renamed to `FINPUT_BUF` (an `F` for "Forth," distinguishing
it from the inherited kernel's own name) — a small, one-line fix, but
a real instance of the same class of collision this project has hit
before with ADDRESSES (Phase 24's own `+LOOP` scratch colliding with
`PRINT_ROW`/`PRINT_COL`) — this time with a NAME instead, caught
immediately because sjasmplus itself flagged it as a hard error rather
than silently aliasing two different runtime values the way an address
collision would have.

`rom/forth_smoke_p28.asm` proves both words under real Fuse with two
checkpoints: `ACCEPT` into a 5-character buffer, scripted to type
`"HELLOX"` then `DELETE` then `ENTER` — the 6th character is silently
ignored (buffer already at its limit when it arrives, matching this
project's own "no error signal, safe default" convention), then
`DELETE` removes the 5th, leaving `"HELL"` (length 4) — confirmed by
`TYPE`-ing the buffer's own contents back out, not just checking the
returned length (the same "check the real content, not just a
coincidentally-matching width" discipline Phase 27's own verification
story established); and `INPUT`, scripted to type `"123"` then
`ENTER`, correctly returning `123` on the data stack. Also re-verified
end-to-end against `rom/forth_boot.asm`'s own full dictionary chain
with the same scripted-interrupt technique (typing `"42"` then `ENTER`
into `INPUT .`). `core/input.asm` is wired in right after `core/
string.asm` (before `core/editor.asm`, same reasoning as every phase
since 25).

With this phase, ALL SIX real gaps found by the original BASIC-vs-Forth
audit are closed: `RND`/`RANDOMIZE` (Phase 25), math functions (Phase
25), arrays (Phase 26), string handling (Phase 27), and line input
(this phase) are all done; `DEF FN` was deliberately skipped (Phase
25's own header explains why: `:` already does that job, more
generally). The lower-priority bucket from that same audit (sprites,
hi-res `MODE`, real AY-3-8912 `SOUND`, `CALL`) remains open and
unscheduled, as the user originally scoped it.

## Phase 29 — FSQRT (float square root)

**Status: done.** Beyond the original BASIC-vs-Forth audit's own six
gaps (all closed as of Phase 28), the user asked directly for float
math functions next: `FSQRT`, `SIN`, `COS`. This phase is the first of
those — `SIN`/`COS` are real, separate follow-up work (their own
phase), needing angle range reduction and a lookup table that `FSQRT`
doesn't. `core/floatsqrt.asm` adds `FSQRT ( f -- sqrt(f) )`, following
up on Phase 25's own note that "float versions of some of these...
[are] a natural later addition" (that phase's own `SQRT` is
integer-only).

**The algorithm**: `value = M * 2^E` (this project's own float
representation). `sqrt(M * 2^E) = sqrt(M) * 2^(E/2)` only works
cleanly when `E` is even; an odd `E` is first rewritten as
`(M*2) * 2^(E-1)` — an EXACT, lossless rewrite, since `M` is at most
32767 and `M*2` is at most 65534, comfortably inside a 16-bit unsigned
register — making the new exponent even with no precision cost. From
there, `sqrt(M)` itself needs far more precision than `M`'s own ~15
bits directly give, so `M` is scaled up by exactly `2^16` (an exact
power-of-2 scale, losing nothing — the same "widen before dividing"
trick `core/floatdiv.asm`'s own header describes for `F/`) into a
32-bit value, and ITS integer square root is taken with a new routine,
`F_SQRT32` — `kernel/math`'s own `MATH_SQRT16` widened from a 16-bit
input/8-iteration form to a 32-bit input/16-iteration one, exactly the
way `core/floatmul.asm`'s own `F_UMUL32` already widened
`MATH_UMUL16`, and `core/floatdiv.asm`'s own `F_UDIV32BY16` already
widened `MATH_UDIV16` — the THIRD time this exact "take an
already-proven 16-bit kernel/math routine and widen it the same way"
move has been made in this project. `F_SQRT32`'s own raw integer result
is then run through `core/floatmul.asm`'s own `F_NORMALIZE32`
(reused unchanged, the same routine `F*`/`F/` already share) to land it
in this project's usual normalized mantissa shape. Since
`sqrt(M * 2^16) = sqrt(M) * 2^8`, the final exponent works out to
`(E/2) - 8 + F_NORM_SHIFT`; `E/2` is a single Z80 `SRA` (arithmetic
right shift), exact because `E` is guaranteed even by this point — no
rounding ambiguity. A neat implementation detail: `F_SQRT32`'s own
running "result" accumulator IS `core/floatmul.asm`'s own
`F_PROD_LO`/`F_PROD_HI` scratch, not a separate pair — so the moment
`F_SQRT32` finishes, its raw result is already sitting exactly where
`F_NORMALIZE32` expects its own input, with no copy step needed (the
same handoff shape `F_UMUL32`→`F_NORMALIZE32` and
`F_UDIV32BY16`→`F_NORMALIZE32` already use). Negative input returns 0,
matching `MATH_SQRT16`'s own convention (and, by extension, Phase 25's
own integer `SQRT`).

**Hand-verified against three cases before ever assembling anything**,
covering the even-exponent path, the odd-exponent path twice (once
exact, once approximate), and two independently exact perfect squares:
`sqrt(4.0)=2.0` exactly (even exponent, `(16384,-12)` → `(16384,-13)`);
`sqrt(9.0)=3.0` exactly (odd exponent, `(18432,-11)` → `(24576,-13)`,
`36864²·2¹⁶` happening to be a perfect square too); and
`sqrt(2.0)≈1.41421` (odd exponent, `(16384,-13)` → `(23170,-14)`,
`23170/16384 = 1.41418457...`, which `F.`'s own truncating-toward-zero
convention prints as exactly `"1.4141"` — a single deterministic
expected string worked out by hand, not a guessed range). All three
matched exactly on the very first real Fuse run — see
`core/floatsqrt.asm`'s own header for the full worked arithmetic.

**A real, if minor, bug caught by the static checker, not by running
anything**: `F_SQRT32`'s own 16-iteration loop ended up too long for a
plain `JR` back-edge (`tools/check_z80_opcodes.py` flagged the exact
displacement, not a guess) — fixed by switching that one jump to `JP`,
the same class of fix Phase 23's own `NUMBER` growth needed.

`rom/forth_smoke_p29.asm` proves the three hand-verified cases under
real Fuse — the `sqrt(2.0)` case checked by actually printing it with
`F.` and comparing the real screen text against the hand-derived
`"1.4141"`, not just checking a stack value, since an approximate
result needs to be checked against its OWN precisely-predicted
approximation, not an exact match against the mathematically true
irrational value. Also re-verified end-to-end against
`rom/forth_boot.asm`'s own full dictionary chain using a REAL typed
decimal literal (`9.0 FSQRT F.` → `"3.0000"` exactly) — using the
decimal-literal parser's own independently-computed normalized
representation of 9.0, not the hand-picked test value, confirming the
algorithm generalizes correctly rather than only working for the
specific inputs it was hand-verified against. `core/floatsqrt.asm` is
wired in right after `core/floatprint.asm` (before `core/compare.asm`,
which now chains from `H_FSQRT` instead of `H_FDOT`).

## Foundational fix — F+/F- silent mantissa-overflow bug

**Status: done, its own commit, separate from Phase 30.** Found while
designing Phase 30 (`SIN`/`COS`), before any Z80 trig code was written:
a Python simulation of the planned table-interpolation step (adding two
already-normalized mantissas each close to the 15-bit ceiling, exactly
the shape `SIN`'s own lookup table produces) turned up a genuine bug in
`core/float.asm`'s `W_FPLUS`/`W_FMINUS` that has existed, unnoticed,
since Phase 8: after `F_ALIGN` shifts the two mantissas onto a common
exponent, the actual `ADD HL,DE` (or `SBC HL,DE` for `F-`) is a plain
16-bit op with no overflow check. Two same-sign mantissas that are each
already normalized toward the ~32767 ceiling — the everyday case for
table-driven interpolation, not a contrived edge case — can sum past
32767 and silently wrap into a wrong-signed result. Concretely:
`(30893,-16) + (18950,-18)` aligns to `(30893,-16) + (4737,-16)`; the
direct sum `35630` overflows a signed 16-bit range and wraps to
`-29906` — a large NEGATIVE result from adding two positive numbers,
with no error, no flag, nothing to signal it happened.

**The fix**: standard signed-overflow detection, applied after the
add/subtract rather than trying to predict it beforehand. For `F+`:
compute `HL+DE` as before; if the two input mantissas had DIFFERENT
signs, overflow is mathematically impossible (the true sum's magnitude
can only shrink), so the fast path is left untouched. If they had the
SAME sign, compare that sign against the result's own sign — a flip
means overflow happened — and only then redo the add from the ORIGINAL
aligned mantissas, each halved by one arithmetic-shift-right (`SRA`
into `RR`, preserving sign) first, with the result exponent bumped by
one to compensate. `F-` mirrors this exactly (matching signs can never
overflow a subtraction; differing signs can, checked the same way).
The fallback trades exactly one bit of precision only on the rare
inputs that actually need it — the common case (Phase 8's own three
original checkpoints, none of which are anywhere near the overflow
boundary) is bit-for-bit unchanged.

Re-verified with a new fourth checkpoint added to
`rom/forth_smoke_p8.asm` (border color 5 for its failure case, not 4 —
see that file's own Phase 27 color-collision note) proving the exact
overflow case above now correctly returns `(17814,-15)` (≈0.5436, close
to the true ≈0.5440, not a wrapped negative value) under real Fuse, and
the original three checkpoints re-run unchanged (still green) to
confirm no regression. `core/float.asm`, `kernel/math`'s own routines,
and every other smoke ROM in the chain (`p18`/`p19`/`p29`,
`rom/forth_boot.asm`'s full dictionary) were rebuilt clean with no
assembly errors; `rom/forth_boot.asm` re-verified booting to its normal
banner under real Fuse with no visible regression.

**A separate, narrower, NOT-yet-fixed quirk was found and ruled out
during the same investigation** (see the
`2068forth-float-align-signed-cmp-quirk` memory note for the full
story): `F_ALIGN` itself compares the two operand exponents with plain
`CP`/`JR C` — an unsigned comparison applied to signed exponent bytes.
Confirmed benign for the common "add exact zero" case (`X + 0.0` and
`0.0 + X` both still return `X` exactly, verified on real Fuse), but
flagged as a real risk, not yet exercised or fixed, for any future
calculation mixing a very-large-magnitude operand (≳16384, needing a
non-negative exponent) with a normal small one — out of scope for
`SIN`/`COS`'s own bounded-range inputs, but worth remembering before
trusting `F+`/`F-` more broadly.

## Phase 30 — PI, SIN, COS

**Status: done.** The user's own direct follow-up to Phase 29 (FSQRT):
"lets do SQRT, SIN, COS 0 is PI already done?" `core/floattrig.asm`
adds `PI ( -- f )`, `SIN ( f -- sin(f) )`, and `COS ( f -- cos(f) )`.
`COS(x) = SIN(x + HALF_PI)`, so there is only one real trig routine
underneath (`RAW_SIN`) — `COS` just adds `HALF_PI` first and falls into
the same code `SIN` uses.

**The algorithm, designed in a Python simulation BEFORE any Z80 was
written** (following this project's own established discipline of
hand-deriving expected values first): range-reduce the input into
`[0, 2*PI)` with a bounded loop of `F+`/`F-` against a `TWO_PI`
constant; quadrant-reduce that into a reference angle `r` in
`[0, HALF_PI]` plus a sign, using the standard four-case rule
(`x < HALF_PI` → `r=x`; `x < PI` → `r=PI-x`; `x < THREE_HALF_PI` →
`r=x-PI, sign=-1`; else → `r=TWO_PI-x, sign=-1`); look `r` up in a
17-entry table of `SIN(i*PI/32)` for `i=0..16` and linearly interpolate
between the two nearest entries (`idx_f = r/TABLE_STEP` via `F/`, then
`idx`/`frac` extracted by repeated `F-` against `1.0` rather than a
dedicated float-to-integer routine, since `idx_f` is always small);
apply the sign last via a plain mantissa negate.

**THIS PHASE IS WHY the F+/F- overflow bug (above) was found at all**:
designing the interpolation step's own Python simulation first (before
writing any Z80) is what surfaced it — table entries are all
normalized close to the mantissa ceiling, exactly the shape that
triggers the bug. The fix for that had to land, its own commit, before
this phase's own code could be trusted.

**A second real design lesson, caught the same way — by simulating
first, not by guessing**: an early version of the Python simulation
used an "idealized," CORRECTED signed comparison for `F_ALIGN` (reasoning
that the real unsigned-CP quirk was just a bug to route around), and it
broke `SIN(0.0)`/`COS(0.0)` — aligning onto the zero operand's own
exponent (0) instead of the real operand's, destroying the real
operand's mantissa. Only after modeling the REAL (buggy) F_ALIGN
faithfully did the simulation start giving correct answers. This means
the zero-safety documented in the `2068forth-float-align-signed-cmp-quirk`
memory note is not incidental to this phase — `SIN`/`COS` actively
depend on it (`SIN_TABLE[0]` is exact zero, `SIN(0)` and `COS(HALF_PI)`
are exact zero, and any input landing exactly on a table step produces
an exact-zero fractional part) — so `core/floattrig.asm`'s own
comparisons are deliberately built ONLY from a direct mantissa-sign
peek (comparing against exact zero — no float op, no quirk exposure at
all) or a real `F-` against a NONZERO constant followed by a sign check
(comparing against `PI`/`HALF_PI`/etc — squarely inside `F_ALIGN`'s own
well-behaved, same-sign-exponent region) — never a comparison that
would put a genuine zero operand through `F_ALIGN` in a way this file
doesn't already know is safe.

**Validated end-to-end in Python, bit-exact, before writing any Z80**:
not just an idealized floating-point simulation — the model reproduces
`F_ALIGN`'s own real unsigned-comparison quirk, `F+`/`F-`'s (now-fixed)
overflow handling, and `F*`/`F_UDIV32BY16`'s exact integer arithmetic,
sanity-checked against `core/floatprint.asm`'s own three hand-verified
`F.` examples before being trusted for anything new. Across 26 test
values spanning all four quadrants, negative inputs, and inputs past
`2*PI` (exercising range reduction): worst `SIN` error 0.00103, worst
`COS` error 0.00119 — consistent with a 17-entry table's own
linear-interpolation error, not a logic bug.

**Confirmed under real Fuse, twice — once in isolation, once live**:
`rom/forth_smoke_p30.asm`'s six checkpoints (PI's exact constant;
`SIN(0.0)`; `COS(0.0)` — the F_ALIGN zero-quirk-dependency case;
`SIN(HALF_PI)` at the table's own upper boundary; `SIN(1.0)` and
`COS(2.0)` printed via `F.`) all pass — border green, and the two
printed values (`"0.8408 "`, `"-0.4156 "`) read correctly off a real
screenshot, matching the bit-exact Python model exactly, not just
approximately. One checkpoint (`SIN(0.0)`) needed a fix on the very
first real run: it originally demanded an exact `(0,0)` match, but
`SIN(0.0)`'s own internal arithmetic legitimately leaves a nonzero
exponent alongside a zero mantissa (e.g. `(0,-16)`) — this project's
own established convention already treats that as an equally valid
zero (see `core/floatmul.asm`'s own `F_NORMALIZE32` header: "any
exponent is fine for 0"), so the checkpoint was too strict, not the
code under test. Also re-verified live: typing `1.0 SIN F.`,
`PI F.`, and `2.0 COS F.` at `rom/forth_boot.asm`'s own real
keyboard-driven prompt printed `0.8408`, `3.1416`, and `-0.4156`
respectively — proving `PI`/`SIN`/`COS` are genuinely reachable via
`FIND`/`INTERPRET_RUN`, not just callable as raw subroutines from a
smoke ROM, and that the decimal-literal parser's own independently-
rounded values feed correctly into the same algorithm.

**UPDATE, external code review**: an outside review of this phase's
finished code (not caught by this phase's own original design/testing)
found four things worth recording, three of them documentation fixes
and one a real, narrow, unfixed edge case:

1. **A real, hard domain limit in `RANGE_REDUCE`, and the ORIGINAL
   version of this scope-limit note cited the WRONG figure for it.**
   `RANGE_REDUCE`'s two bounded loops each cap out after
   `TRIG_GUARD_MAX` (250) iterations of `+`/`-TWO_PI`; reaching the cap
   silently returns an UNREDUCED value (not just imprecise — genuinely
   outside `[0,2*PI)`), and every step downstream then runs on a broken
   precondition with no error signal. This note originally (wrongly)
   cited the SEPARATE `F_ALIGN` finding's own `≳16384` threshold as if
   it were this limit too — the real, tighter, operative bound is
   roughly ±1570 (`250 * TWO_PI`), found by hand-deriving it directly
   from the guard count once external review pointed at the loop.
   Ordinary trig usage (a few hundred radians at most) is comfortably
   inside this; nothing was changed algorithmically beyond widening the
   single-byte guard's own headroom slightly — see
   `core/floattrig.asm`'s own `RANGE_REDUCE` header for the exact
   derivation and `TRIG_GUARD_MAX`'s own definition.
2. **The "every constant/table entry has a negative exponent" claim
   (finding (b), above) was too absolute.** `SIN_TABLE[0]` is exact
   zero (exponent 0), and dividing zero (e.g. `SIN(0)`'s own `idx_f`)
   can produce a zero mantissa paired with a nonzero exponent, e.g.
   `(0,+2)`. Both are harmless (`F_ALIGN` may shift a zero mantissa by
   any amount without changing its value), but the invariant that
   actually matters is narrower: every NONZERO value produced within
   `RANGE_REDUCE`'s own successfully-reduced domain has a negative
   exponent — confirmed by hand-tracing every intermediate value's own
   realistic magnitude range. `core/floattrig.asm`'s own header now
   states this precisely instead of the original overclaim.
3. **The F+/F- overflow fix itself is correct** on every boundary
   external review checked — both signs, both operations, exact
   halving, and wrapped-zero mantissas like `-32768+-32768` — with one
   remaining, narrow, UNFIXED edge case: if the aligned result exponent
   is exactly +127, the fallback's own exponent increment wraps it to
   -128, giving a radically wrong result. Needs an exponent of +127 to
   reach, nowhere near anything this project's own code (SIN/COS
   included) produces — documented at `core/float.asm`'s own `W_FPLUS`
   header rather than fixed, since a real fix means deciding what this
   float format should even do on exponent overflow, a foundational,
   format-wide question this one bugfix shouldn't answer alone.
4. Quadrant logic, boundary assignments, and the 17-step interpolation
   guard were all confirmed correct as designed — no issues found.

ROM budget after this phase: `rom/forth_boot.asm` uses 10924 of 16384
bytes ($2AAC of $4000), 5460 bytes free — no ROM pressure from this
addition.

## Phase 31 — real, semitone/seconds BEEP

**Status: done.** The user asked directly why 2068-Forth's `BEEP`
doesn't behave like the real 2068's, then asked for a real attempt.
Phase 5's original `BEEP` exposed `kernel/sound`'s own `SOUND_BEEP`
mechanism directly — a raw per-half-cycle busy-wait count and a raw
waveform-cycle count, not musical units at all, and explicitly
documented as such at the time. `core/beep.asm` replaces it with
`BEEP ( n-semitones fduration -- )`: an INTEGER semitone number (0 =
middle C, the well-documented Sinclair BASIC convention) on the data
stack, and a REAL duration in seconds on the float stack — the same
units the real command uses.

**The real ROM's own algorithm, confirmed directly from the actual
Timex Sinclair 2068 ROM disassembly** (its "Beeper Subroutine" and
"BEEP Command Routine" sections — a real primary source, not
half-remembered or guessed): split the semitone pitch into a
note-within-octave (0-11) and an octave count via a repeated-subtract-12
loop starting some fixed number of octaves below middle C; look the
note up in a 12-entry table of frequency RATIOS for one octave; apply
the octave count as a DIRECT SHIFT of the resulting float's own
exponent field (exact — "multiply by 2^N" is just "add N to the
exponent," not a real multiplication); convert the frequency into a
hardware timing period and the duration into a cycle count; hand both
to the real `BEEPER` routine.

**This phase replicates the note/octave math exactly** (same
convention, same octave-via-exponent-shift trick), but NOT the real
ROM's own frequency-to-hardware-period formula (`437500/f - 30.125`) —
those constants are specific to the real ROM's own `BEEPER` timing loop
(a self-modifying `IX`-relative NOP sled), a structurally different
loop from `kernel/sound`'s own `SOUND_BEEP` (a plain `DEC BC` countdown,
no NOP sled). Reusing the real ROM's constants unchanged on a different
loop shape would silently produce the WRONG frequency while looking
authentic. Instead, this phase derives its own conversion from first
principles against `SOUND_BEEP`'s own actual instructions: standard,
published Z80 T-state timings for its `.half_cycle` body (98+26*pitch
T-states, charged per call) give `222 + 52*pitch` T-states per full
waveform cycle, so `pitch_param = (CPU_CLOCK/f - 222) / 52`. `CPU_CLOCK`
is the TS2068's own REAL, confirmed clock — 3,528,000 Hz
(`libspectrum`'s own machine timing table, notably NOT the Spectrum's
own 3.5MHz). `pitch_param` is clamped to a minimum of 1 (pitch 0 would
make `SOUND_BEEP`'s own countdown wrap from 0 to 65535, the opposite of
the very high pitch a near-zero pitch_param is trying to reach) — this
is also a real, quantified hardware ceiling: the fastest the loop can
toggle is ~12.9 kHz; anything requested above that clamps there instead
(about -8.5% error for the real ROM's own highest note, +69 semitones,
~14080 Hz — a real, honestly-quantified limit, not a rounding
artifact). Ordinary notes land within 0.02%-0.6% of their true target
frequency purely from truncating `pitch_param` to an integer — the same
truncate-not-round convention `core/floatprint.asm`'s own `F.` already
uses.

**TWO REAL, FOUNDATIONAL BUGS FOUND WHILE VERIFYING THIS PHASE UNDER
REAL FUSE, NEITHER CAUGHT BY THE PRE-WRITING PYTHON SIMULATION** (a
genuine gap in that simulation's own bit-exactness, worth remembering:
it modeled `core/float.asm`'s own arithmetic faithfully, but the
Z80-side integer-conversion steps were written directly in assembly
without a matching Python model first, unlike Phase 30's own
discipline):
1. The `pitch_param` formula's own `- 222` step, done as a FLOAT
   subtraction, hits `core/float.asm`'s own `F_ALIGN` unsigned-
   comparison quirk (see the `2068forth-float-align-signed-cmp-quirk`
   memory note): for a low-pitched note, `CPU_CLOCK/freq` is a LARGE
   number (hundreds of thousands), normalizing to a POSITIVE float
   exponent, while `222.0` normalizes to a small NEGATIVE one —
   `F_ALIGN` wrongly treated `222`'s own tiny negative exponent as
   "larger," shifting the large period's own mantissa down to nothing
   and returning essentially `-222` instead of `period-222`. Confirmed
   directly with a real, reachable note (pitch -60, ~8.18 Hz): the
   smoke ROM's own checkpoint 3 caught `pitch_param` coming out as 1
   (the clamp) instead of the correct 8293.
2. Fixing (1) by converting `CPU_CLOCK/freq` to a plain 16-bit integer
   (the same `FLOAT_TO_INT16` helper already used safely for
   `cycle_count`) was ALSO wrong: for that same pitch -60 case,
   `CPU_CLOCK/freq` is 431504 — comfortably over 65535, so truncating
   into 16 bits silently wrapped (`ADD HL,HL` drops overflow bits with
   nowhere to go), corrupting the result a SECOND, independent way
   (confirmed: gave `pitch_param=732`, matching neither the buggy-
   `F_ALIGN` answer nor the correct one).
   The fix for both: a new `FLOAT_TO_UDIVID32` widens the period into a
   genuine 32-bit integer, landing it exactly where `core/floatdiv.asm`'s
   own already-proven `F_UDIV32BY16` expects its own dividend — reusing
   that routine directly for the final division rather than writing a
   third 32-bit division routine, and using PLAIN 32-bit integer
   subtraction (two chained `SBC HL,DE`) for the `-222` step, which
   never touches `F_ALIGN` at all.
Both were caught by `rom/forth_smoke_p31.asm`'s own hand-derived
checkpoint 3 failing under real Fuse — not by inspection — and each was
isolated with a small, throwaway diagnostic ROM that printed the actual
intermediate values (`BEEP_OCTAVE`, `BEEP_FREQ_M`/`BEEP_FREQ_E`, the
raw `pitch_param`/`cycle_count`) against hand-computed expectations,
narrowing down exactly which stage diverged before writing a fix.

**Confirmed under real Fuse, twice.** `rom/forth_smoke_p31.asm`'s four
checkpoints call `BEEP_COMPUTE` directly (not `SOUND_BEEP`, which
actually toggles the speaker port and can't be checked in this
environment — the same "check the inputs to the unverifiable hardware
call" strategy Phase 5's own original `BEEP` checkpoint used) and check
the resulting `pitch_param`/`cycle_count` against values hand-derived
from a bit-exact Python model (reusing Phase 30's own already-proven
F+/F-/F*/F_UDIV32BY16 arithmetic unchanged): middle C for 1 second,
one octave up for 0.5 seconds (deliberately landing on the SAME
`cycle_count` as the first case — not a coincidence, an exact
verification of the octave-doubling identity), the real ROM's own
lowest valid note for 2 seconds, and the real ROM's own highest valid
note (proving the pitch_param clamp actually engages, not just exists
in the code) — all four pass, border green. Live: typing `0 1.0 BEEP`
at `rom/forth_boot.asm`'s own real keyboard-driven prompt (lowercase,
`0 1.0 beep`, exercising the same case-folding already proven since
Phase 9) played for about one real second and returned control
normally — confirmed by immediately following it with a second command
and seeing it execute right away, not hang.

**Extraction, not deletion**: `core/ts2068.asm` no longer defines
`BEEP` at all — moving it out let that file's own `PLOT`/`LINE`/
`CIRCLE`/`BORDER` stay completely unchanged rather than gaining a new
float-stack dependency none of them need. The original word survives,
byte-for-byte, as `core/rawbeep.asm`, included only by
`rom/forth_smoke_p5.asm` (the one ROM whose own historical checkpoint
tests it) — no ROM ever includes both files, since both define a
global `H_BEEP` label. `rom/forth_smoke_p9.asm`/`p15.asm`/`p17.asm`/
`p21.asm` all still include `core/ts2068.asm` for its other words and
never called `BEEP`, so all four rebuild clean, unaffected.

**Scope cut, stated honestly**: only INTEGER semitone pitches are
supported. The real ROM also accepts a fractional semitone (via a
linear-interpolation constant applied to the fractional part) — not
replicated, since ordinary BASIC `BEEP` usage is overwhelmingly integer
semitones anyway, and the data-stack pitch argument has no fractional
part to represent one with regardless.

ROM budget after this phase: `rom/forth_boot.asm` uses 11332 of 16384
bytes ($2C44 of $4000), 5052 bytes free — no ROM pressure from this
addition.

## Phase 32 — real, register-level SOUND

**Status: done, confirmed with real audio.** Tracked since the
original BASIC-gap audit as its own future phase (AY-3-8912 `SOUND`,
"real register-level sound access, distinct from the existing simple
`BEEP`... never ported here"), and picked up right after Phase 31 at
the user's own request. `core/sound.asm` adds `SOUND ( register data
-- )`: writes `data` directly into AY-3-8912 chip `register`, exactly
the authentic real BASIC command — confirmed from the actual ROM
disassembly's own `SOUND` routine (M2127): register to port `$F5`,
data to port `$F6`, register validated 1-16 (0 and 17+ rejected).
Unlike `BEEP`, there is no note/duration computation at all — `SOUND`
is a raw primitive, one register at a time.

**A real documentation bug, caught before it could mislead anyone**:
this phase's own first draft claimed the real ROM applies a "register 1
= chip register 0" offset before the `OUT`, reasoning that the AY chip
only has 16 registers (0-15) while `SOUND`'s own valid range is 1-16.
Re-reading the ACTUAL disassembly bytes (not just the sibling project's
own prose summary) settled it: `OUT ($F5),A` uses the register value
straight off the calculator stack — the preceding `DEC A`/`INC A` pair
is solely a zero-check idiom (restoring `A` before the `OUT`, not
transforming it). No offset exists, in the real ROM OR in this file's
own code (which never applied one either) — confirmed by cross-checking
against the sibling `ts2068rom` project's own already-verified
`SOUND_EXROM`, which matches exactly. The header comment was fixed;
the code was already correct. A real, worth-stating consequence of NO
offset existing: chip register 0 (Channel A's own tone-period FINE
byte) can never be reached through `SOUND` at all, since register 0 is
rejected — only its coarse byte (chip register 1) is reachable for
that specific field. Channels B and C don't have this limitation (both
halves of their own tone periods, chip registers 2-5, are fully
reachable).

**Confirmed under real Fuse**: `rom/forth_smoke_p32.asm`'s three
checkpoints (a valid register/data pair, and both rejected boundary
values, 0 and 17) all pass — the same data-stack-hygiene proof shape
`core/rawbeep.asm`'s own original `BEEP` checkpoint used, since neither
this project nor the sibling one has ever confirmed AY register
read-back is even possible on this hardware.

**Real audio confirmed live, by the user — something no automated
check in this project can do, and a real lesson in AY-3-8912
programming along the way.** The first live attempt used the real
ROM's own documented example verbatim, `8 15 SOUND` alone — and
produced audible STATIC, not a tone, reported directly by the user
listening over real speakers. Not a bug: register 8 only sets Channel
A's volume; with the mixer register (7) and a tone period left at
whatever the emulator's own AY chip happens to hold, there's no reason
to expect a clean tone (most likely: noise routed to that channel, or
a near-zero tone period). A clean tone needs THREE coordinated writes,
not one. Using Channel B (to sidestep Channel A's own unreachable
fine-period register, above) with the TS2068's own real AY clock
(1,764,000 Hz — the same `libspectrum` `timings.c` source `core/beep.asm`'s
own header already cites for the CPU clock) and the standard
`period = clock/(16*frequency)` formula for a ~439 Hz tone:
```forth
2 251 SOUND   \ Channel B tone period, fine byte
3   0 SOUND   \ Channel B tone period, coarse byte
7 253 SOUND   \ mixer: only Channel B's tone enabled, everything else off
9  15 SOUND   \ Channel B volume, fixed, maximum
```
Typed one line at a time (an earlier attempt combining all four onto
one line produced a spurious "?" — almost certainly a dropped keystroke
during this session's own known-flaky X11 keyboard injection, not a
real parsing bug, confirmed by the SAME four commands succeeding
individually right after). The user confirmed a real, steady,
recognizable tone starting exactly at the volume write (the third and
fourth register writes, period and mixer, are silent by themselves,
since volume was still zero) and confirmed silence again after
`9 0 SOUND` — exactly the expected behavior, not a partial failure.
This is genuine, human-confirmed proof `SOUND` reaches real, working
AY-3-8912 hardware state, not just "the port write instruction
executed" — the strongest verification any sound-producing word in
this project has ever had.

ROM budget after this phase: `rom/forth_boot.asm` uses 11364 of 16384
bytes ($2C64 of $4000), 5020 bytes free — no ROM pressure from this
addition.

## Phase 33 — color scheme, flashing cursor, real multi-row word wrap, startup chime

**Status: done, confirmed under real Fuse.** Picked up right after
Phase 32 at the user's own combined request: a better color scheme, a
flashing cursor, a better startup sound (now that `BEEP`/`SOUND` are
both confirmed working), and a direct question about word wrap.

**Color scheme.** `kernel/graphics/graphics.asm`'s `ATTR_DEFAULT`
changed from `$38` (white paper, black ink) to `$44` (black paper,
bright green ink) — the user's own chosen option, picked from a set of
proposed combinations. This also incidentally fixed a pre-existing
mismatch: the border was already black by default (`BORDER_DEFAULT`'s
own white was never actually applied anywhere in this project), so the
old white-paper scheme never matched its own border.

**Flashing cursor.** `core/editor.asm`'s cursor already used a
dedicated invert routine, but the WRONG one:
`GFX_INVERT_ATTR_STATIC` (no FLASH bit — meant for static highlights
like a status line), not `GFX_INVERT_ATTR` (sets the FLASH bit,
already existing in the kernel, already unused by the editor). The ULA
blinks any attribute cell with FLASH set entirely in hardware, at
roughly 1.5Hz on real silicon — confirmed in Fuse by sampling
screenshots several seconds apart and observing the cursor cell
genuinely toggle between solid (ink/paper swapped) and invisible
(normal, and the cursor's own character is a space, so "normal" reads
as blank against the black background). The toggle period observed in
this Fuse session was much longer than 1.5Hz — a host emulation-speed
artifact of this environment (see this project's own recurring notes
on X11/timing flakiness here), not a code defect; the FLASH bit itself
is unconditionally hardware-driven regardless of CPU speed.

**Real multi-row word wrap.** The original Phase 6 editor was a
deliberate scope cut: one fixed row (`EDIT_ROW`), a 31-character cap,
extra keystrokes silently dropped. Asked directly "how does the print
system handle a line over 32 characters?" first — answer: `core/print.asm`'s
`EMIT` already had its own independent hard-wrap-at-column-32 plus
auto-scroll for *output*, entirely unaffected by the editor's own
separate *input* limitation. The user chose real, word-boundary-aware
multi-row wrap for input anyway.

Design, informed by researching the sibling `ts2068rom` project's own
already-proven `EDITOR_WRAP_CALC`/`EDITOR_WRAP_OFFSET_TO_ROWCOL`
(`rom/exrom_editor.asm`): the input line's LAST row stays anchored at
`EDIT_ROW` (23) and grows UPWARD as needed, up to `FWRAP_MAX_ROWS` (4);
`WRAP_CALC` breaks each row at the last space at-or-before column 32
(hard-breaking at exactly 32 only when no space exists, matching the
sibling project's own algorithm); `EDIT_CURSOR_TO_ROWCOL` converts a
linear cursor offset to (row, col). A key simplification over the
sibling project: 2068-Forth's REPL never changes input and output on
screen at the same moment (strictly type → ENTER → run/print → fresh
line), so growth only needs a one-time comparison against `PRINT_ROW`'s
own current value, not continuous negotiation.

**Two real bugs found before/during this work, neither hypothetical:**

1. *Design bug, caught by Python simulation before any Z80 was
   written* (this project's own established discipline — see e.g.
   Phase 30's `F_ALIGN` note): `WRAP_CALC` caps at exactly
   `FWRAP_MAX_ROWS` rows by construction, so `FWRAP_COUNT` can never
   exceed 4 — meaning the original capacity check (comparing the row
   count itself) could never fire, silently truncating characters into
   `EDIT_BUF` that would never appear in any row's own wrap-table
   entry. Fixed with a dedicated `FWRAP_OVERFLOW` flag, set only when
   the row cap is hit with content still remaining.
2. *Real stack-corruption bug, found via a genuine Fuse hang, not
   inspection*: `rom/forth_smoke_p33.asm`'s first checkpoint showed a
   stuck border color under real Fuse. A throwaway diagnostic ROM with
   a border-color waypoint marker placed right before the type-loop
   confirmed the program was genuinely HANGING mid-loop, not merely
   failing an assertion. Hand-tracing `EDITOR_REDRAW`'s own per-row
   setup code instruction-by-instruction found an unmatched `pop hl` —
   a value was popped a second time with no matching push, silently
   consuming the routine's own return address off the hardware stack
   on every row drawn. Fixed with one `push hl` at the correct point;
   re-verified afterward with all four `rom/forth_smoke_p33.asm`
   checkpoints passing (green border) and `rom/forth_smoke_p6.asm`/
   `rom/forth_smoke_p9.asm`/`rom/forth_boot.asm` all re-confirmed
   unaffected.
3. *Real flashing-cursor-never-clears bug, found live by the user, not
   by any automated test*: typing "console" then backspacing it all
   away left several cells at the start of the line stuck flashing
   green instead of the line going blank. None of `rom/forth_smoke_p33.asm`'s
   four checkpoints caught this because they only inspect `WRAP_CALC`'s
   own table values, never the actual screen attributes `EDITOR_REDRAW`
   paints — a real gap in that smoke ROM's own coverage, now understood
   rather than hidden. Root-caused with a sequence of purpose-built
   diagnostic ROMs (a deterministic `EDITOR_PROCESS_KEY`-driven repro of
   the exact keystrokes, then direct attribute-memory readback probes
   immediately after each `GFX_SET_ATTR` call) rather than guessing from
   the symptom: `EDITOR_REDRAW`'s blank-fill loop calls `GFX_PUTCHAR`
   (draws a space) and then reuses register `D` for the following
   `GFX_SET_ATTR` call's own row parameter — but `GFX_PUTCHAR` is
   documented to destroy `DE`, and it genuinely does: by the time it
   returns, `D` holds a leftover screen-bitmap address byte (for row 23
   specifically, `$58` — arithmetically one past the bitmap area,
   landing right at the boundary with attribute memory's own `$5800`
   base), not the row. `GFX_SET_ATTR`'s own bounds check (row must be
   <24) then silently rejects the write — exactly this project's
   established "clip rather than corrupt" convention working exactly as
   designed, just against a caller bug rather than genuine out-of-range
   input. The content-drawing loop directly above (`.printloop`) already
   restores `D` from the stack between its own two calls; `.blank` was
   simply missing that same restore. Every column that was NEVER a past
   cursor position happened to already read back correctly by sheer
   coincidence (either `GFX_CLS`'s own initial screen-clear, or the
   correct content loop, had already set it to the right value, and the
   broken blank-loop write silently no-oping left that alone) — which is
   exactly what made this bug invisible until backspacing was tried:
   typing alone never exposes it, since each cursor position becomes
   real content on the very next keystroke, correctly maintained by the
   working content loop from then on. Fixed by adding the matching
   `pop de` / `push de` restore `.blank` was missing; re-verified with
   the exact reported repro (type "console", backspace all seven
   characters) showing a clean single-cell cursor, plus
   `rom/forth_smoke_p33.asm`/`p6`/`p9`/`rom/forth_boot.asm` all
   re-confirmed still passing.

**Startup chime.** Phase 4's original startup sound requirement was met
with a flat `SOUND_BEEP` tone — explicitly flagged in
`rom/forth_boot.asm`'s own header as "not a considered musical choice."
The user was offered several real options (a rising single-channel
arpeggio, a two-note beep, a two-note "power chord," and an old-Mac-
style full chord) and picked the Mac-style chord. First version: C4/E4/
G4 struck simultaneously across all three AY channels, held ~800ms.
Recorded live by the user and analyzed by FFT — the three fundamental
frequencies measured (261.7/330.0/391.7 Hz) matched the C4/E4/G4 target
almost exactly, with no clipping, so the "didn't sound correct" report
wasn't a wrong-note bug: three raw AY square waves snapping to full
volume in the same instant is inherently harsh (clashing square-wave
harmonics, an instant-on click) compared to the real Mac's smooth
*sampled* synth chime. Revised to a staggered, ramped attack — Channel
A rings first, fading up over 3 steps, then B, then C roll in on top
(like an actual rolled bell chime) — followed by a shared 3-step fade
on release, using a new `CHIME_DELAY` helper (a real frame-count wait
backed by `kernel/interrupt.asm`'s own `INT_GET_FRAMES`, which required
moving `KBD_ISR_INIT`/`IM 1`/`EI` to run BEFORE the chime instead of
after — `FRAMES` only advances once the ISR is live). Channel A's own
tone-period FINE byte (chip register 0) is written directly via the AY
ports rather than through `core/sound.asm`'s `SOUND_WRITE`, since that
routine faithfully refuses register 0 to match the real ROM's `SOUND`
command — a restriction that protects `SOUND`'s own authenticity but
doesn't bind this boot code.

ROM budget after this phase: `rom/forth_boot.asm` uses 12024 of 16384
bytes ($2EF8 of $4000), 4360 bytes free — combined cost of the color
change, flashing-cursor fix, multi-row wrap rewrite, and startup chime
is +660 bytes over Phase 32.

## Phase 34 — S>F and F>S (integer/float conversion)

**Status: done, confirmed under real Fuse and via the real interpreter
pipeline.** Standard ANS Forth's Floating-Point word set defines
`S>F ( n -- r )` and `F>S ( r -- n )` for converting a single-cell
integer to/from a float — asked about directly ("should we have
conversion words between integer and float stacks? Is that a standard
Forth feature?"), confirmed as standard, then added at the user's own
request. Until now the only way to get a value onto the float stack at
all was `FPUSH`ing a raw (mantissa, exponent) pair by hand, with no way
back — a real, previously undocumented gap. (`D>F`/`F>D`, the
double-cell half of the same standard word set, don't apply — this
project's integer stack is single-cell only.)

`S>F` is exact and needs no thought: this project's float format is
`mantissa * 2^exponent` (`core/float.asm`'s own header) with no
required normalization, so `mantissa=n, exponent=0` represents `n`
exactly, positive or negative, every time.

`F>S` **truncates**, per the user's own explicit choice (not ANS
Forth's own default, which is implementation-defined but usually
rounds to nearest) — the simplest option, matching this project's
established posture of accepting and stating approximation rather than
hiding it (`F.`'s and `FSQRT`'s own truncating/lossy behavior). The
exponent decides direction: zero needs no shift (already exact); a
positive exponent shifts the mantissa left (a new `F_SHLA`, the mirror
image of `core/float.asm`'s existing `F_SHRA`); a negative exponent
reuses `F_SHRA` unchanged.

**A real caveat, found by hand-deriving test cases before writing any
Z80** (this project's own established discipline): reusing `F_SHRA`
means `F>S` truncates via an ARITHMETIC (sign-preserving) right shift,
which rounds toward NEGATIVE INFINITY for a negative fractional value,
not toward zero the way C's `(int)` cast or many other Forths' own
`F>S` do. A whole-number float is completely unaffected either way
(there's no remainder to round), so this only shows up for a genuinely
fractional negative input — concretely, `F>S(0.5) = 0` (ordinary) but
`F>S(-0.5) = -1`, not `0`. Reusing `F_SHRA` was a deliberate choice
(one already-proven routine, not a second subtly-different shift), but
the direction it truncates in is real, user-visible behavior, not an
implementation detail — documented plainly in `core/floatconv.asm`'s
own header rather than glossed over.

A positive exponent's left shift has no overflow guard, matching this
format's own established position (`core/float.asm`'s header: no
overflow handling anywhere in this format) — a float whose true value
doesn't fit in 16 bits silently loses its high bits.

**Confirmed under real Fuse**: `rom/forth_smoke_p34.asm`'s five
checkpoints (S>F/F>S round-trip for both a positive and a negative
integer; F>S(0.5)=0; F>S(-0.5)=-1, the documented caveat made concrete;
F>S(-4.0)=-4, a whole negative number unaffected by that same caveat)
all pass. **Also confirmed through the real interpreter, not just
direct word calls**: a throwaway diagnostic built from `rom/forth_boot.asm`
itself (same full dictionary chain, same `FIND`/`INTERPRET_RUN` path a
live user's own keystrokes go through) fed the line `42 S>F F>S`
through `EDITOR_PROCESS_KEY`/`INTERPRET_RUN` exactly the way a typed
line would be, and the integer stack held exactly `42` afterward —
proving the dictionary-chain splice (`core/floatconv.asm` inserted
between `core/floatsqrt.asm` and `core/floattrig.asm`) is wired
correctly, not just that the underlying routines are correct in
isolation.

ROM budget after this phase: `rom/forth_boot.asm` uses 12076 of 16384
bytes ($2F2C of $4000), 4308 bytes free — +52 bytes over Phase 33.

## Phase 35 — FROUND (round to nearest)

**Status: done, confirmed under real Fuse.** Picked up immediately
after Phase 34, live: the user tried `2.0 FSQRT F>S .` and got `1` —
correct (`sqrt(2)≈1.41421` truncates to `1`), but a natural moment to
ask for rounding as an option too, not a replacement for truncating
`F>S`. Standard ANS Forth's own answer is `FROUND ( r1 -- r2 )` —
rounds to the nearest integral value but stays a FLOAT, composing with
the existing (unchanged) `F>S` rather than duplicating it:
`FROUND F>S` gives a rounded integer, since by the time `F>S` sees it
there's no fractional part left to truncate away.

**A real overflow trap avoided by construction, not caught after the
fact**: the obvious rounding technique — add half a unit (`2^(N-1)`)
to the mantissa, then shift right by `N` — risks overflowing the
16-bit mantissa BEFORE the shift ever runs, since this project's own
normalized mantissas routinely already sit near the top of the 16-bit
range (`core/floatsqrt.asm`'s own header: "mantissa in
[16384,32767]"). Avoided entirely by never adding anything: `F_SHRA`
(`core/float.asm`, reused completely unchanged) shifts one bit at a
time via `SRA`/`RR`, and `DJNZ` — which doesn't touch flags — means the
CARRY FLAG left over when `F_SHRA` returns is exactly the bit shifted
out on its own last iteration: bit `(N-1)` of the original mantissa,
i.e. "is the discarded fraction ≥ 0.5?" That side effect was already
true of `F_SHRA` before this phase existed; nothing there needed to
change, only using it. If that bit is set, the floored result gets
incremented by one — round-half-UP (ties move toward positive
infinity), chosen as the simplest of the standard tie-breaking rules.

**Hand-verified with a Python simulation of the exact algorithm before
any Z80 was written** (this project's own established discipline):
`FROUND(1.41421) = 1` (agrees with plain `F>S` here — no tie
involved); `FROUND(0.5) = 1` but `FROUND(-0.5) = 0`, NOT `-1` — the
round-half-up rule made concrete: a positive tie rounds away from
zero, a negative tie rounds TOWARD zero (both "up"), genuinely
asymmetric around zero, a real stated consequence of picking this
particular tie-breaking rule rather than round-half-away-from-zero;
`FROUND(2.5) = 3`, `FROUND(-2.5) = -2` — same pattern at a larger
magnitude; `FROUND(-4.0) = -4` — a whole number passes through
unchanged (exponent ≥ 0 branch), same as `F>S`'s own equivalent case.

**Confirmed under real Fuse**: `rom/forth_smoke_p35.asm`'s six
checkpoints (all five hand-derived cases above, each piped through the
existing `F>S` to land on the integer stack) all pass — including
checkpoint 3 (`FROUND(-0.5)` then `F>S` = `0`) directly contradicting
`rom/forth_smoke_p34.asm`'s own checkpoint 4 (plain `F>S(-0.5)` = `-1`)
on the exact same input, by design — proof the two words genuinely
disagree in the documented direction, not an oversight.

ROM budget after this phase: `rom/forth_boot.asm` uses 12110 of 16384
bytes ($2F4E of $4000), 4274 bytes free — +34 bytes over Phase 34.

## Phase 36 — CLS, KEY?, C@, C!

**Status: done, confirmed under real Fuse.** Direct follow-up to a
fresh three-way audit (2068-Forth vs. the sibling 2068-Leap BASIC
project vs. the real TS2068 ROM's own command set, re-run to account
for everything added since the original Phase 24-ish BASIC-gap audit)
— the user picked this group specifically as "highest value for the
least ROM cost," all four being thin wrappers around kernel routines
that mostly already existed.

`CLS` (`core/ts2068.asm`) wraps `kernel/graphics`'s own `GFX_CLS` —
already called internally everywhere (`COLD_START`, the editor's own
line-shrink path, every smoke ROM's own setup) but never once exposed
as a word a user could actually type. A real, simply-overlooked gap,
not a design decision.

`C@`/`C!` (`core/bytemem.asm`, new file) are the standard byte-level
counterparts to the existing cell-level `@`/`!` — BASIC's own
`PEEK`/`POKE` equivalent, and a real, previously-unfilled hole: only
16-bit memory access existed before this phase. Exactly `@`/`!`'s own
shape, byte-sized instead of cell-sized (`C@` zero-extends into the
cell; `C!` stores only the low byte) — no new design decisions.

`KEY?` (`core/key.asm`) is the more interesting one: the audit's own
first guess was to wrap the ALREADY-EXISTING `IO_READ_KEY_NONBLOCK`
(built for BASIC's own `INKEY$`), but that routine CONSUMES whatever
key it finds — exactly wrong for standard Forth's own `KEY?`, which by
definition is a non-destructive lookahead (`KEY? IF KEY ... THEN` is
the standard idiom, and it only works if `KEY?` leaves the key for
`KEY` to actually consume). Using the consuming primitive would have
made `KEY?` silently swallow the very key a following `KEY` expects to
see. Fixed by adding a genuinely new, tiny kernel routine instead —
`IO_KEY_AVAILABLE` (`kernel/io/io.asm`) — that reads `KBD_KEYHIT`
without ever clearing it, alongside the already-existing consuming
`IO_READ_KEY_NONBLOCK` rather than repurposing it.

**Confirmed under real Fuse**: `rom/forth_smoke_p36.asm`'s six
checkpoints — `C!`'s low-byte-only truncation, `C@`'s zero-extension,
`CLS` actually resetting a poisoned attribute cell back to
`ATTR_DEFAULT`, `KEY?` reading FALSE against a forced-clear
`KBD_KEYHIT`, `KEY?` reading TRUE against a forced-set one AND STAYING
true on a second call (proving the non-destructive property, not just
that it returns SOMETHING), and finally the existing `KEY` word
actually consuming that same latched key (checked two ways at once:
the character it returns, and a follow-up `KEY?` going FALSE
afterward) — all pass.

ROM budget after this phase: `rom/forth_boot.asm` uses 12195 of 16384
bytes ($2FA3 of $4000), 4189 bytes free — +85 bytes over Phase 35.

## Phase 37 — STICK (joystick read)

**Status: done, confirmed under real Fuse.** Picked up first from the
Phase 36-era backlog, exactly because it was flagged there as the
cheapest of the three: `kernel/io/io.asm`'s own `STICK_READ` already
existed, confirmed directly from the real ROM disassembly's own
`READ-STICK` routine (AY-3-8912 register 14 via `PORT_AY_REG`/
`PORT_AY_DATA`), complete with the real hardware's own asymmetry
(device 1 reports a full 4-bit direction nibble, device 2 only a
single bit) — nothing invented, already ported, just never wrapped as
a dictionary word. `core/stick.asm` (new file) adds exactly that: a
thin `STICK ( device -- value )` wrapper, same shape as Phase 36's own
`CLS`/`KEY?`, no new hardware logic. No input validation, matching
`STICK_READ`'s own stated contract ("the caller's own job to
validate") and this project's established no-error-mechanism
convention (`SOUND`'s own header states the same posture explicitly).

**Confirmed under real Fuse, with the same honest verification-limit
`core/sound.asm`'s own header already states for a hardware word with
no way to fake real input**: no joystick is actually connected in this
emulated environment, so this can't prove `STICK` reads a REAL
joystick correctly — only that it reaches real AY-3-8912 hardware
without hanging, returns the value real Fuse's own AY register 14
gives with nothing pressed (confirmed live via a throwaway diagnostic
BEFORE writing any checkpoint — both devices read back as `0` in this
environment, not guessed), and consumes/produces exactly its own one
argument/one result (`rom/forth_smoke_p37.asm`'s own two checkpoints
each place a sentinel value below the device number and confirm it
survives the call completely untouched).

ROM budget after this phase: `rom/forth_boot.asm` uses 12213 of 16384
bytes ($2FB5 of $4000), 4171 bytes free — +18 bytes over Phase 36.

## Phase 38 — runtime stack-error detection

**Status: done, confirmed under real Fuse AND live in the real boot
ROM.** Follow-up to a direct question the user asked about error
handling: 2068-Leap has error reporting at both line-entry and runtime;
2068-Forth already had the line-entry equivalent (`INTERPRET_UNKNOWN_
WORD`, since the live editor's own Phase 9/10 work — an unrecognized
word prints `?` and cleanly returns to a fresh prompt), but nothing for
runtime conditions: a stack underflow (`DROP`/`+` on an empty stack)
would silently read whatever garbage sits past the stack's own
boundary and keep going, not report anything or recover. Explicitly
scoped as step one of three the user laid out — basic runtime
detection now, a code-consolidation pass next, `THROW`/`CATCH` review
last (see the Backlog section, below, for that last piece).

**Why the check lives in exactly one place, not scattered across every
word**: many words access the data stack directly via `(ix+0)`/
`(ix+1)` rather than going through `core/dict.asm`'s own `DPOP_HL`/
`DPUSH_HL` helpers (a deliberate, existing performance choice, not
something this phase should undo) — so there's no single low-level
choke point every stack access already funnels through. There IS one
place every dispatched word's own result already passes through
unconditionally, though: `core/interp.asm`'s own `INTERPRET_RUN.loop`,
which every word returns control to (either by falling through, or via
the pushed-return-address trick its own `.execute` label uses) before
scanning for the next token. A single `STACK_CHECK` call at the top of
that loop catches the AFTER-EFFECT of any word's own stack misuse —
without touching a single individual word's own code.

**Gated behind `DEFINE RUNTIME_ERROR_CHECK_ENABLED`**, exactly
mirroring Phase 23's own `DECIMAL_NUMBER_ENABLED` pattern for touching
this same heavily-shared file safely: every existing ROM that doesn't
opt in gets `core/interp.asm`'s own compiled bytes byte-for-byte
identical to before (confirmed directly, not just reasoned about, by
diffing `rom/forth_smoke_p9.asm`'s own build output before and after
this change — identical). A ROM that DOES opt in must also `INCLUDE
core/float.asm` (for `FSTACK_TOP`/`FSTACK_LIMIT`, needed by the
float-stack half of the check) and must itself define
`RUNTIME_ERROR_HOOK` — reached the exact same proven way
`INTERPRET_UNKNOWN_WORD` already is: a bare `jp`, with the stack depth
first restored to "`INTERPRET_RUN`'s own caller, one entry" (by
discarding `STACK_CHECK`'s own return address first), so the hook's own
implementation can simply `ret` when done.

**Scope, stated honestly**: this catches a word that pops more than
the stack currently holds, or pushes past the stack's own reserved
region — confirmed not an abstract worry: `DSTACK_LIMIT` and
`FSTACK_TOP` sit at the EXACT same address ($9000, this project's own
established "stacks stacked back-to-back" convention), so an
undetected data-stack underflow reading past its own boundary would be
reading directly into float-stack territory. It does NOT catch a word
that pops garbage and pushes something back, netting to an
in-range-but-wrong depth — the same "can't verify what it can't
observe" honesty this project's own `SOUND`/`STICK` smoke-test headers
already state for hardware effects. Recovery unconditionally resets
BOTH stacks to empty (not just the one that violated), since there's
no way to know how much of a corrupted expression's own state is still
trustworthy — matching `INTERPRET_UNKNOWN_WORD`'s own "abandon the rest
of this line" posture exactly.

**Confirmed two ways**: `rom/forth_smoke_p38.asm`'s five checkpoints
(a legitimate push doesn't false-trigger; each of the four violation
shapes — data-stack underflow, data-stack overflow, float-stack
underflow, float-stack overflow — is individually detected and both
stacks correctly reset) all pass. **And live, in the real product ROM,
not just an isolated test**: a throwaway diagnostic built from
`rom/forth_boot.asm` itself fed the line `DROP` (on the genuinely empty
stack a fresh boot starts with) through the real `EDITOR_PROCESS_KEY`/
`INTERPRET_RUN` pipeline — printed `STACK?` as expected, THEN a
follow-up line, `1 2 + .`, correctly computed and printed `3` —
confirming genuine recovery (the interpreter still works normally
afterward), not merely "didn't crash this one time."

ROM budget after this phase: `rom/forth_boot.asm` uses 12323 of 16384
bytes ($3023 of $4000), 4061 bytes free — +110 bytes over Phase 37.

## Phase 39 — code consolidation pass

**Status: done, confirmed under real Fuse.** Step 2 of the user's own
three-step plan (runtime error detection, then this, then a
`THROW`/`CATCH` review). Scoped by a fresh read-only survey of every
`core/*.asm`/`kernel/*/*.asm` file, product code only — explicitly
excluding the 38 `rom/forth_smoke_p*.asm` files, which this project has
repeatedly, deliberately kept frozen once passing, even though they
share a large amount of boilerplate (RST vectors, `COLD_START`,
`PASS_TEST`/`FAIL_TEST`, `CHECK_TOP`-style helpers) — touching those to
share code would work against this project's own established practice,
not with it. Two real, concrete findings, both fixed; several other
candidates (a handful of near-identical 3-6-line "pop, call kernel
routine, push result" word bodies; three unreferenced
`DICT_LATEST_INIT_*` cosmetic constants; this file's own 2,800+ line
length) were surveyed and deliberately left alone — already minimal,
zero runtime cost, or not an actual problem, respectively, matching
this project's own stated aversion to touching working code without a
real reason.

**A real, if dormant, RAM collision** (`kernel/mode64/mode64.asm`'s own
`GFX_PALETTE64`/`GFX_PIXEL64_MASK`/`GFX_PIXEL64_WHICH_FILE`/
`GFX_PIXEL64_BYTECOL`/`GFX_PIXEL64_OVER`, at $87B0-$87B4, byte-for-byte
overlapping `core/floatmul.asm`'s own `F_PROD_HI`/`F_MUL_CNT`/
`F_MSIGN`/`F_NORM_SHIFT` and `core/floatdiv.asm`'s own `F_DIVID_LO`) —
found by re-running the exact "grep every EQU across the whole tree"
discipline every earlier phase's own scratch placement already used,
just never re-run against everything ADDED since Phase 8. Confirmed
real: both `kernel/mode64/mode64.asm` and `core/floatmul.asm`/
`core/floatdiv.asm` are INCLUDEd together in the actual shipped
`rom/forth_boot.asm`, not just theoretically nearby in the source tree.
Confirmed DORMANT, not an active bug, by checking whether
`MODE64_WRITE_PIXEL`/`PLOT64` ever call the float multiply/divide
routines internally — they don't, and Z80 execution is single-threaded
with no interrupt-handler involvement in either region, so the two
scratch blocks were never actually live at the same moment. Still a
real, latent trap for a future word that combines the two, and a
genuine violation of this project's own address-map invariant
regardless of whether anything had tripped over it yet. Moved to
$87BF-$87C3, a freshly-reverified 9-byte gap between
`core/decimal.asm`'s own `DIVISOR10` and `core/print.asm`'s own
`PRINT_ROW` — re-verified free by the same whole-tree grep before
picking it, not assumed. A pure address renumbering, no logic change;
confirmed via the three ROMs that actually exercise these two regions
together (`rom/forth_smoke_p8b.asm` for `64COL`/`PLOT64`,
`rom/forth_smoke_p18.asm`/`rom/forth_smoke_p19.asm` for `F*`/`F/`, plus
`rom/forth_smoke_p9.asm`, which also includes the changed kernel file)
all still passing, and a full `make clean && make all` across every ROM
in the project (all 38 smoke ROMs plus `rom/forth_boot.asm`) building
with zero errors.

**A stale dictionary word-list comment** in `rom/forth_boot.asm`'s own
header, claiming to list "every word from every phase" — verified
against a fresh extraction of every real `DB` header string across the
actual INCLUDE chain, in order (82 words total), the stale comment was
missing 34 of them: every original Phase 2 primitive
(`DROP`/`DUP`/`SWAP`/`OVER`/`+`/`-`/`@`/`!`) it should have listed from
the very start, `:`/`;`, and most of Phases 24-32
(`LEAVE`/`+LOOP`/`ABS`/`SGN`/`MOD`/`SQRT`/`RND`/`RANDOMIZE`/`ARRAY`/
`CELLS`/`S"`/`TYPE`/`STRING`/`PLACE`/`COUNT`/`LEN`/`VAL`/`FSQRT`/
`PI`/`SIN`/`COS`/`SOUND`/`ACCEPT`/`INPUT`). Rewritten to the complete,
verified list — a pure comment fix, zero bytes, zero behavior change.

ROM budget after this phase: unchanged from Phase 38 (12323 of 16384
bytes) — both fixes were a RAM-address renumbering and a comment
rewrite, neither adds or removes any code.

## Phase 40 — string functions (CHR, STR, UPPER, LOWER, LEFT, RIGHT, SEARCH, CODE)

**Status: done, confirmed under real Fuse.** The backlog's own first
pick, closing `core/string.asm`'s own Phase 27 scope cut ("DELIBERATELY
NOT INCLUDED THIS PHASE... a real, stated scope cut, not an
oversight"). Eight words (`UPPER$`/`LOWER$` and `LEFT$`/`RIGHT$` each
split into two), named the way this project always drops BASIC's own
`$` sigil, and — where a real ANS Forth standard word already exists
for the exact same job — using ITS name instead of inventing one:
`INSTR` becomes `SEARCH`, the real STRING word-set name for "find one
string inside another," same semantics (on a match, returns the
REMAINDER of the haystack starting at the match, not just the matched
substring — real ANS behavior, not simplified).

`LEFT`/`RIGHT` are substring BY REFERENCE, not copy — Forth strings are
already just an (addr len) VIEW into memory, so no bytes ever move; a
particularly clean case of "the data structure already gives you this
for free" once the (addr len) convention is taken seriously. `CODE` is
directly composable from existing words as `DROP C@` (Phase 36) — added
anyway for the real ROM's own direct name, adding no new capability.

**A real bug caught by this phase's own smoke ROM, not a design flaw**:
`UPPER`/`LOWER` mutate their target IN PLACE — genuinely necessary,
since keeping the same (addr len) signature both directions is the
whole point. The first version of `rom/forth_smoke_p40.asm` ran them
directly against a ROM-embedded `DB` string literal (this project's own
usual smoke-ROM test-data convention) and got a silent, un-crashing
NO-OP: a write to ROM on this hardware simply doesn't take effect, and
nothing anywhere — not `UPPER`, not the calling convention, not the
test's own checks — has any way to detect that from the caller's side.
Root-caused with a purpose-built diagnostic dumping the actual
resulting bytes (not guessed from re-reading the code, which looked
completely correct — and was): confirmed the address and length
`UPPER` received were exactly right, and the bytes it walked over were
exactly right, but they read back byte-for-byte UNCHANGED after the
call. Fixed on the TEST side (copy the literal into a genuine RAM
buffer, `CASE_BUF`, before mutating it) — `UPPER`/`LOWER` themselves
needed no change at all — and documented as a real, stated requirement
in `core/stringext.asm`'s own header: these two specifically need
writable RAM (a `STRING` buffer, `PLACE`'s own destination, or similar)
as their target, unlike every other word in this file, which only
reads the given (addr len).

**A second, smaller methodology bug caught before it could ship**: an
early draft numbered all fourteen individual hand-verified cases as
checkpoints 1-14 directly. The ULA's border port only decodes 3 bits,
so checkpoint 12 would have displayed the exact same green as
`PASS_TEST` itself (12 truncates to color 4) — a genuine false-pass
trap, caught by re-deriving the real hardware constraint (at most 8
distinguishable outcomes ever exist) rather than assuming more
headroom than the hardware actually has. Fixed by grouping related
cases under 6 checkpoint numbers instead (0,1,2,3,5,6 — skipping 4,
`PASS_TEST`'s own color, matching `rom/forth_smoke_p27.asm`'s own
established precedent for the identical problem, and reusing 0 as an
ordinary checkpoint color, matching `rom/forth_smoke_p30.asm`'s own
precedent for that).

ROM budget after this phase: `rom/forth_boot.asm` uses 12774 of 16384
bytes ($31E6 of $4000), 3610 bytes free — +451 bytes over Phase 39
(the largest single-phase addition since the multi-row word wrap of
Phase 33, matching this being the largest single word-count addition,
8 words, since Phase 27's own original 6).

## Phase 41 — EXECUTE

**Status: done, confirmed under real Fuse.** The next backlog pick,
following string functions. Standard ANS Forth `EXECUTE ( xt -- )` —
the audit's own framing was BASIC's `USR(addr)`: jump into arbitrary
code from an address already on the data stack, something nothing in
2068-Forth did before now.

**Trivial in this project's own threading model, and worth saying why
rather than leaving it looking accidentally simple**: this is a
SUBROUTINE-threaded Forth (`core/dict.asm`'s own header) — a colon
definition compiles directly to a sequence of real Z80 `CALL`
instructions ending in `RET`, and a primitive's own code IS the
routine `FIND` already returns as its "code address." There's no
separate indirection layer (no token table, no `DOCOL`-style inner
interpreter) between an execution token and directly-jumpable machine
code, for either kind of word — so `EXECUTE` doesn't need to know or
care which kind it's given. The entire word is two instructions:
`call DPOP_HL` then `jp (hl)` — a plain jump, not a call, so the
target's own eventual `RET` naturally returns to whoever called
`EXECUTE` in the first place, exactly matching real `EXECUTE`
semantics. No address validation, matching BASIC's own `USR(addr)`
(also just jumps to whatever it's given) and this project's
established no-error-mechanism convention.

**Scope note**: this project still has no `'` (tick) word to look up
an existing dictionary word's own execution token by name from typed
source — `EXECUTE` here serves the `USR(addr)`-shaped use case the
audit named (a numeric address already known or computed, e.g. from a
`VARIABLE` or `CREATE`'d buffer holding raw machine code), not "call
any word in the dictionary by name from a running program." A lookup
word is a separate, not-yet-requested feature.

**Confirmed under real Fuse**: `rom/forth_smoke_p41.asm`'s two
checkpoints prove the SAME central claim the header above makes, not
just assert it — `EXECUTE` on `+`'s own primitive code address (taken
directly at assembly time) with `(5 3)` gives `8`; and, more
substantially, compiling `: DOUBLE DUP + ;` for REAL through the
actual `INTERPRET_RUN`/colon-compiler pipeline (not faked), looking
its own code address up through the REAL `FIND` (it has no
compile-time label — it's compiled into the RAM dictionary at
runtime), then `EXECUTE`ing THAT xt with `21` gives `42` — proving
`EXECUTE` genuinely works identically on a primitive and on a
freshly-compiled user-defined word, the whole point of the execution-
token abstraction, not just on the one case that's easy to set up.

ROM budget after this phase: `rom/forth_boot.asm` uses 12788 of 16384
bytes ($31F4 of $4000), 3596 bytes free — +14 bytes over Phase 40 (a
two-instruction word, the smallest addition since Phase 39's own
zero-byte consolidation fixes).

## Phase 42 — RAD, DEG

**Status: done, confirmed under real Fuse.** The last of the two real
audit findings that never made it onto the backlog the first time
around (`EXECUTE`, Phase 41's own pick, was the other). 2068-Leap has
both; `SIN`/`COS` (Phase 30) only ever accepted radians directly, with
no bridge from degrees. Added to `core/floattrig.asm` itself rather
than a new file — `RAD`/`DEG` are `PI`/`SIN`/`COS`'s own direct
companions, not a separate feature.

`RAD ( degrees -- radians )` and `DEG ( radians -- degrees )` are each
a single precomputed constant (`PI/180` and `180/PI`, hand-derived the
same normalized-mantissa way as `PI`/`HALF_PI` above) plus the
EXISTING `W_FSTAR`, unchanged — no new arithmetic, matching `PI`'s own
"push a constant" simplicity.

**Hand-verified before trusting either constant or the smoke ROM's own
checkpoints** — by simulating the REAL `F_UMUL32`/`F_NORMALIZE32`
algorithm in Python first, not the ideal mathematical values (this
project's own established discipline for anything float-related):
`RAD(90.0)` computes to EXACTLY `(25735,-14)` = 1.57073974..., close to
true `PI/2` within this project's own already-established SIN/COS
precision budget; `DEG(HALF_PI)` computes to EXACTLY `(23039,-8)` =
89.99609375, close to true 90.0 within the same budget — a real round
trip (radians back to degrees), not just one direction checked in
isolation. Both `rom/forth_smoke_p42.asm` checkpoints assert these
EXACT mantissa/exponent pairs (not an approximate/printed-string
check), and both matched the real Z80 computation bit-for-bit on the
first run — the Python simulation's own precision paid off directly.

ROM budget after this phase: `rom/forth_boot.asm` uses 12824 of 16384
bytes ($3218 of $4000), 3560 bytes free — +36 bytes over Phase 41.

## Phase 43: FREE

**Done and committed.** `FREE ( -- n )`, the last of the fresh
three-way audit's own remaining findings, needed one real design
decision before it could be a thin wrapper — this project's RAM layout
has the dictionary (`HERE`) growing UPWARD from `FORTH_DICT_RAM`, with
no upper ceiling ever established (unlike the well-probed *low* end).

**The ceiling, confirmed not guessed: `$C000`.** `core/moregfx.asm`'s
own `FILL` word calls the shared `kernel/graphics.asm`'s `GFX_FILL`,
which unconditionally uses `GFX_FILL_VISITED`/`GFX_FILL_STACK`
($C000-$E7FF, 10,240 bytes) as scratch on every call. Unlike the
sibling 2068-Leap project (where that range is genuinely transient,
used only during an EXROM-mapped `FILL` call), 2068-Forth's dictionary
is PERMANENT RAM state living in the same physical address space — if
`HERE` ever grew past `$C000`, the next `FILL` call would silently
clobber live dictionary entries. `core/free.asm`'s own header has the
full writeup, including the grep-across-the-whole-tree confirmation
that nothing else claims any address in the dictionary's own range.

**The floor moved too, after a user question caught a real gap.**
Shipped first with `FORTH_DICT_RAM = $A000` (reporting 8192 bytes
free) — the user asked "that seems low for a 48K system, what am I
missing?", which prompted checking rather than just re-asserting the
number. Found: `$9800-$9FFF` (2048 bytes) sat completely idle between
`DSTACK_TOP` (a sentinel value for empty `IX`, not a byte the stack
ever occupies) and the old `FORTH_DICT_RAM` — confirmed via the real
build's own `.sym` table (no other symbol lands there) before
reclaiming it. Moved `FORTH_DICT_RAM` down to `$9800`; `FREE` now
reports 10,240 bytes at cold start. See `core/dict.asm`'s own header
for the move.

**What's still deliberately NOT reclaimed, and why it isn't simple:**
most of `$E800-$F5FF` (sprite capture buffers, and BASIC-only state —
label table, UDGs, `DEF FN`, the loadable-extension registry) is
confirmed dead weight for 2068-Forth specifically (no `core/*.asm` file
calls any `GFX_SPRITE_*` routine; this project's own `EDIT_BUF` at
`$8860` is separate from the shared sysvars' `EDIT_LINE_BUF`). It isn't
reclaimed because `GFX_FILL`'s own scratch sits directly between the
dictionary and that dead zone, AND at least one more live transient
cell (`GFX_LINE_X0-Y1`, 4 bytes at `$F3C4-$F3C7`, used by this
project's own `LINE`) sits inside that upper range too — raising the
ceiling further needs `FILL`'s scratch relocated out of the way first,
plus a full per-routine audit of the rest of `$C000-$FEFF`, not a
one-line change. Tracked as a real, larger follow-on below, not
attempted here.

ROM budget after this phase: `rom/forth_boot.asm` uses 12824 of 16384
bytes ($3218 of $4000) still — `FREE` and the dictionary-floor move add
no bytes to the resident image (both are compile-time constants and a
handful of instructions).

## Phase 44: dictionary-ceiling reclaim (FREE, continued)

**Done and committed.** Direct follow-on to Phase 43, done the same
session after the user set an explicit target: match or beat the
sibling 2068-Leap project's own 15,322 bytes free. Phase 43's own
`$C000` ceiling was a real hazard, not a preference, so raising it
meant removing the hazard at its source rather than picking a bigger
number.

**Relocated `GFX_FILL_VISITED`/`GFX_FILL_STACK`** (`include/sysvars.inc`
— 2068-Forth's own independent copy of the sibling's file, confirmed
not a symlink, so this divergence is safe) out of `$C000-$E7FF`
entirely, into the idle "second display file" video-RAM pool at
`$5B00-$7FFF` (9,472 bytes — see `docs/memory_map.md`'s own writeup on
why Standard video mode never touches that range). That pool is 768
bytes smaller than the original span, so `GFX_FILL_STACK` shrinks from
2048 to 1664 (x,y) entries to fit exactly, ending precisely at `$8000`
with nothing wasted — a real capacity cut, but one the routine's own
header already treated as graceful-degradation territory (2048 already
fell short of a measured ~2069-entry peak for a radius-50 circle;
1664 just starts degrading a bit earlier).

**New hazard this move creates, and the user's own explicit choice for
handling it**: that same video-RAM pool is where 64-column mode's
second display file lives (`$6000-$77FF`, hardware-fixed). Presented
the tradeoff directly — document-only (matching this project's
established SOUND/STICK convention) vs. a runtime guard — and the user
picked the guard. `core/moregfx.asm`'s `FILL` now checks `GFX_MODE`
(2 = 64-column, set by `kernel/mode64/mode64.asm`'s `MODE64_ON`) before
calling `GFX_FILL`; if active, it still consumes its `(x y)` arguments
but silently does nothing, rather than risk corrupting whichever of
FILL's scratch or the live second screen runs second.

**Verification, in order**: re-audited every symbol landing in
`$C000-$FEFF` against what 2068-Forth's own included kernel code
actually calls (not just what's declared) — confirmed sprite buffers
and all BASIC-only state (label table, UDGs, `DEF FN`, extension
registry) are dead for this project, and found exactly one other live
cell, `GFX_LINE_X0-Y1` (4 bytes at `$F3C4`, this project's own `LINE`).
Set `DICT_RAM_CEILING` to `$F000` — comfortable margin below it, not
pushed to the exact byte. Rebuilt and re-ran `rom/forth_smoke_p17.asm`
(Phase 17's own FILL/AT-XY smoke ROM, unchanged, just rebuilt against
the new addresses) in real Fuse as a regression check — all three of
its checkpoints still passed, and the filled circle rendered correctly.
Added `rom/forth_smoke_p44.asm`, three NEW checkpoints specifically for
what changed this phase: FILL still fills correctly at the new
addresses (baseline), FILL refuses and leaves the target pixel clear
while `GFX_MODE=2` is simulated, and FILL works again once `GFX_MODE`
is restored — all via exact `GFX_READ_PIXEL` readback, not a visual
guess. Full `make clean && make all` (45 ROMs) and `make check` both
stayed clean, including the pre-existing, unrelated JR-range warnings
in `core/interp.asm`/`kernel/graphics/graphics.asm` confirmed present
before this phase's own changes too.

**Result: `FREE` now reports 22,528 bytes** (`$F000 - $9800`) —
comfortably past the sibling project's 15,322, with ~964 bytes of
`$F000-$F3C3` left deliberately unclaimed as margin below the one
remaining live cell, not squeezed to the exact byte.

ROM budget after this phase: `rom/forth_boot.asm` uses 12824 of 16384
bytes ($3218 of $4000) still — the relocation and the guard are both
address-only changes plus a handful of instructions in `FILL` itself.

## Phase 45: THROW and CATCH

**Done and committed.** The third and last of the user's own explicit
3-step plan from when Phase 38 was scoped: (1) runtime error detection
[Phase 38], (2) code consolidation [Phase 39], (3) this — a
PROGRAMMABLE recovery mechanism, letting a program intercept an error
and keep running under its own control instead of the system always
aborting to a fresh prompt. This project's own from-scratch Forth had
no inherited 2068-Leap or real-ROM error-handling code to port for
this (2068-Leap's own equivalent, `WHEN ERROR`, is design-only there
too — never actually built), so the design and implementation are both
original to this project.

**The real design problem**: this is a subroutine-threaded Forth
(Phase 1) — there is no separate software return stack to unwind, the
real Z80 SP register IS the return stack. `THROW` can fire arbitrarily
deep inside nested word calls, so recovering means unwinding SP itself
directly, the same technique as a C `setjmp`/`longjmp` pair. `CATCH`
snapshots `SP`/`IX`/`IY` (both data stacks) into a small bounded stack
of frames (`CATCH_MAX_DEPTH` = 8, matching Phase 24's own
`LEAVE_HEAD_TABLE` bound) before calling its `xt`; `THROW` with a
nonzero `n` restores the innermost active frame's `SP`/`IX`/`IY`
directly (discarding every nested call pushed since that `CATCH`'s own
entry in one step), pushes `n`, and does a plain `ret` — which lands
back at `CATCH`'s own caller exactly as if `CATCH`'s own call to `xt`
had itself just returned, only with `n` instead of `0`.

**A real implementation constraint found while designing this, not
guessed**: `LD (nn),SP`/`LD (nn),IX`/`LD (nn),IY` (and their inverses)
only take a fixed, assembly-time address — never a computed one like
`(HL)`. Since a catch frame's own address depends on the runtime
`CATCH_DEPTH`, every save/restore has to go through a small fixed
staging area first (`CATCH_TMP_SP`/`IX`/`IY`) rather than touching the
computed frame slot directly.

**A second real correctness issue, more subtle, found and fixed before
committing**: an UNCAUGHT throw (no active `CATCH`) still needs to
unwind to somewhere sane — reusing Phase 38's own `RUNTIME_ERROR_HOOK`
made sense (same recovery-to-fresh-prompt behavior), but that hook's
own documented contract requires the stack already restored to
"exactly one entry: `INTERPRET_RUN`'s own caller" before it's reached.
Phase 38's own `STACK_CHECK` gets this for free (it only ever runs one
level down from `INTERPRET_RUN`'s own `.loop`), but an uncaught
`THROW` can be arbitrarily deep — a naive single `pop` wouldn't unwind
far enough and would corrupt the return address. Fixed by giving
`INTERPRET_RUN` itself an implicit "root" catch frame: it snapshots its
own `SP` once, at its very entry (`THROW_ROOT_SP`, `core/interp.asm`,
gated behind a new `THROW_CATCH_ENABLED` define matching Phase 38's own
`RUNTIME_ERROR_CHECK_ENABLED` precedent exactly, including verifying
byte-identical output for a ROM that doesn't opt in). An uncaught
`THROW` restores from that instead of a user frame, then resets both
stacks and jumps to `RUNTIME_ERROR_HOOK` exactly like a stack-depth
violation already does.

**Verification**: `rom/forth_smoke_p45.asm`, 5 checkpoints — a normal
completing `CATCH` (0 pushed, the `xt`'s own result survives
underneath), a `CATCH` around a throwing `xt` (the thrown value comes
back, and whatever the `xt` pushed before throwing does NOT survive),
a NESTED `CATCH` (inner absorbs the throw, the outer `xt` keeps running
afterward, the outer `CATCH` still reports success since the throw
never reached it), `THROW 0` as a strict no-op, and — the one case that
genuinely needed the real interpreter, not a hand-built test stub — an
UNCAUGHT throw from 3 real, freshly-COMPILED nested word calls deep
(`: DEEP3 42 THROW ; : DEEP2 DEEP3 ; : DEEP1 DEEP2 ;` then `DEEP1`),
proving `THROW_ROOT_SP` correctly unwinds a real multi-level call chain
and control genuinely returns to the caller afterward, not a hang or a
crash. All 5 passed in real Fuse on the first run.

ROM budget after this phase: `rom/forth_boot.asm` uses 13047 of 16384
bytes ($32F7 of $4000), +223 bytes over Phase 44's 12824.

With this, the user's own 3-step error-handling plan from Phase 38 is
now fully complete.

## Phase 46: ROT, 2DUP, 2DROP, ?DUP, PICK, AND, OR, XOR, INVERT, CR,
## SPACE, SPACES, and ' (TICK)

**Done and committed.** Prompted directly by the user asking "are
there any other keywords or features this project would benefit
from?" — answered with a quick inventory of the real dictionary (96
words at the time) rather than a guess, which turned up a genuine gap:
only the original Phase 2 `DUP`/`SWAP`/`OVER`/`DROP` existed for stack
shuffling (no `ROT`, `2DUP`, `2DROP`, `?DUP`, `PICK`), no bitwise/
logical operators at all, and no `CR`/`SPACE` (only raw `EMIT` of 13/
32). All cheap, all real friction for writing idiomatic Forth code,
unlike the bigger sprite/hi-res bucket — the user agreed to do it as
the next phase.

Four small files, each independent: `core/stackops.asm` (`ROT`,
`2DUP`, `2DROP`, `?DUP`, `PICK`), `core/logic.asm` (`AND`, `OR`, `XOR`,
`INVERT` — deliberately NOT named `NOT`, since this project's own `0=`
already does boolean negation of a flag and a second, differently
behaved word spelled `NOT` next to it would be a real footgun, not a
helpful synonym), `core/outwords.asm` (`CR`, `SPACE`, `SPACES`), and
`core/tick.asm` (`'`, closing a real gap `EXECUTE` (Phase 41) left
open — there was no Forth-visible way to actually obtain an `xt` by
name before this). `'` on an undefined word `THROW`s exactly `-13`,
the real ANS Forth "undefined word" code — the first user-facing use
of Phase 45's own `THROW`/`CATCH` for something other than its own
smoke-test stubs.

**Two real bugs found and fixed before shipping, both the same class
of mistake** — assuming a register pair survives a call into shared
graphics code when its own header says otherwise:
- `rom/forth_smoke_p46.asm`'s own `ANY_PIXEL_SET_IN_CELL` test helper
  used `D`/`E` as loop counters across calls to `GFX_READ_PIXEL`,
  whose own documented contract is "Destroys: AF, BC, DE, HL" — caught
  by re-reading that contract before trusting the helper, not by a
  failed run.
- `core/outwords.asm`'s own first draft of `SPACES` kept its count in
  `BC` across calls to `SPACE`/`EMIT` — `W_EMIT` (`core/print.asm`)
  explicitly loads `B`=row and `C`=column before calling
  `GFX_PUTCHAR`, silently corrupting the loop count. This one WASN'T
  caught on paper — it shipped, ran green-adjacent (a real Fuse run
  showed the wrong checkpoint failing, cyan/5, with the "Y" character
  landing one column short of where it should), was root-caused by
  checking `W_EMIT`'s own actual register usage, and fixed by moving
  the counter into memory (`SPACES_COUNT`) instead of any register —
  immune to whatever the callee touches, by construction.

**A third, unrelated bug also caught before the final green run**: the
smoke ROM's own first draft numbered its 9 assertions as checkpoints
1-9 directly — but this project already has a documented lesson about
exactly this (Phase 40): `PORT_ULA`'s border only decodes 3 bits, so
checkpoints 8 and 9 would have aliased to colors 0 and 1, and 4/7 are
already this project's own reserved PASS/"bug in test source" colors.
Caught by re-reading that lesson before trusting the numbering, not
after a confusing failure — regrouped into 6 checkpoint numbers
(0,1,2,3,5,6), the same fix Phase 40 used.

**Verification**: `rom/forth_smoke_p46.asm`, 9 assertions under 6
checkpoint numbers — exact stack traces for `ROT`/`2DUP`/`2DROP`/
`?DUP`/`PICK`, exact bit patterns (not just truthy/falsy) for `AND`/
`OR`/`XOR`/`INVERT`, real `GFX_READ_PIXEL` readback proving `CR`/
`SPACE`/`SPACES` land glyphs at the exact expected screen cells
(matching Phase 10's own established EMIT verification strategy), and
`'` exercised both ways — a real compiled word found and `EXECUTE`d
correctly, and a deliberately undefined word `CATCH`ing exactly `-13`
— a genuine integration proof spanning Phases 41, 45, and 46 together,
not three isolated checks. All checkpoints green in real Fuse after
the fixes above.

ROM budget after this phase: `rom/forth_boot.asm` uses 13394 of 16384
bytes ($3452 of $4000), +347 bytes over Phase 45's 13047.

## Phase 47: LPRINT, LLIST

**Done, committed, and confirmed working end-to-end against a real
printer-capable Fuse.** The user asked to look at the real TS2068
ROM's own `LPRINT`/`LLIST` and consider a 2068-Forth equivalent. Real
research first, not a guess: the real Sinclair/TS2068 printer protocol
(ZX Printer/TS2040, port `$FB`) went through three escalating levels of
source quality before landing on the real, complete algorithm — two
secondhand sources (the real Fuse emulator's own `printer.c` and
skoolkid's Spectrum ROM disassembly) agreed on the three WRITE bits and
the "ready" READ bit, but both missed a per-row setup write and a
"wait for start of paper" gate that only turned up once the actual,
verbatim ROM disassembly (`~/Downloads/Timex Sinclair 2068 ROM
Disassembly.pdf`, `COPY-LINE` at M0A4A) was found and read directly.
See `core/printer.asm`'s own header for the full protocol writeup,
citations, and the two refuted fix attempts that came before the real
one.

`LPRINT ( addr len -- )` renders text into 256×8-dot raster lines
(MSB-first, matching the real ROM) using the SAME font
`GFX_CHAR_TO_FONT_OFFSET` already provides for on-screen text, and
bit-bangs them out via the documented protocol, wrapping across
multiple lines for anything longer than 32 characters. A real
documentation bug in that shared font routine was found and fixed
along the way: its own header claimed "Destroys: AF, BC, HL" but the
routine's actual body also destroys `DE` (confirmed by reading the
code, not the comment) — caught before it could corrupt this file's
own column-render loop, the same class of mistake Phase 46's `SPACES`
bug already taught to watch for.

`LLIST ( -- )` prints one name per line for every word in the RAM
dictionary (`>= FORTH_DICT_RAM`), newest first — deliberately NOT the
~100 ROM-resident primitives too, matching real BASIC's own `LLIST`
scope (your program, not the ROM). Confirmed via a real Fuse printout:
after defining `FOO` then `BAR`, `LLIST` printed "BAR" then "FOO", the
correct newest-first order, both names legible against the real font.

**Two more real things were found and fixed getting here**, both
documented in full in `core/printer.asm`'s own header:
1. The companion `.txt` OCR file (a Fuse-only convenience — the real
   printer output is the `.pbm` graphics file) came out empty because
   this project never set the real ZX system variable `CHARS`
   ($5C36/$5C37), which Fuse's OCR reads to find a reference font.
   Fixed (`LPRINT_SEND_LINE` now sets it). The OCR still mislabels
   characters after this fix (e.g. "HI" reads as "23") because our own
   `FONT_TABLE` is packed in definition order, not the dense
   ASCII-code order Fuse's OCR assumes — deliberately left alone
   (would cost ~768 bytes of ROM to fix a debug convenience with no
   real-hardware counterpart).
2. A small amount of pixel-level drift appears in the `.pbm` output,
   traced (with help from an external review) to a genuine Fuse
   printer-emulation quirk — its virtual print-head position doesn't
   reset between the 8 raster-row calls of one character line, only
   when the motor fully stops. Confirmed NOT a bug in this project:
   the real, unmodified 48K BASIC ROM's own `LPRINT`, run through the
   identical Fuse setup, drifts the same way. Per the user: not a
   priority, not chased further.

Also found and fixed, independent of printing itself but discovered
*because of* live printer testing: `INTERPRET_UNKNOWN_WORD`
(`rom/forth_boot.asm`) never reset `STATE` or the data/float stacks
after an unknown word, so hitting one mid-compile (e.g. a dropped
keystroke merging two words together while live-typing) left the
interpreter permanently stuck compiling into an abandoned definition —
every subsequent line typed silently got swallowed instead of running.
Fixed to match `STACK_CHECK`'s own existing abort contract (reset
`STATE`, `IX`, and `IY`); verified via a 3-checkpoint diagnostic and
then confirmed live by the user.

## Phase 48: ULAPLUS, PALETTE

**Done, committed, and confirmed working in this session's own
(patched) Fuse.** Ported from 2068-Leap's own already-working
implementation (`~/ts2068rom/basic/basic.asm`'s
`BASIC_ULAPLUS_DISABLE` and its EXROM body) rather than designed from
scratch — the exact real protocol: write a register number to
`PORT_ULAPLUS_SELECT`, then a data byte to `PORT_ULAPLUS_DATA` (both
already declared in `include/hardware.inc`, inherited unchanged).
Register 64 is the enable/disable switch; registers 0-63 are the
64-color palette itself, one `GGGRRRBB` byte each. Confirmed via
2068-Leap's own documentation that ULAPlus REPLACES the meaning of the
existing attribute color bits rather than adding a separate
pixel-setting mechanism — every existing color word (`INK`, `PAPER`,
`PLOT`, `LINE`, `CIRCLE`, `FILL`) needed zero changes for this to work.

**Verification**: `rom/forth_smoke_p48.asm` is a visual test (matching
Phase 8's own `PALETTE64` precedent — there's no register-level way to
confirm a palette swap actually changed what's displayed). Draws a
filled circle with standard `INK 2` (red), then — WITHOUT ever
redrawing it — reprograms palette register 2 to `252` (yellow, per the
`GGGRRRBB` encoding) and enables `ULAPLUS`. A real Fuse screenshot
confirmed the SAME circle changed from red to yellow with no redraw:
genuine proof of a display-time palette swap, not a coincidence of
timing. (A striking bonus finding from the same screenshot: the
border, set to color 6 in the same test, rendered black instead of
yellow — because ULAPlus reinterprets ALL 8 color slots including the
border, and register 6 was never explicitly programmed, so it read
back at its default. Correct, real ULAPlus behavior, not a bug.)

**Test-fidelity caveat carried forward, not resolved**: the real Timex
Sinclair 2068 almost certainly never had genuine ULAPlus hardware —
it's a modern extension for later Sinclair-compatible machines, made
available here only through this session's own Fuse ULAPlus patch.
What Phase 48 confirms is that this project's own port-level code
matches the same protocol 2068-Leap's own long-tested BASIC
implementation uses, and that the patched emulator visibly responds to
it correctly — NOT that genuine, unpatched TS2068/SCLD silicon would
behave identically. **RESOLVED 2026-09-06 — the cross-check turned out to be moot, not
open.** Checked directly against ZEsarUX 13.0's own source
(`src/cpu.c`'s per-machine `poke_byte`/`enable_*` setup): `enable_
ulaplus()` is called for the Chloe 280SE and Prism machine profiles,
but the `MACHINE_ID_TIMEX_TS2068`/`MACHINE_ID_TIMEX_TC2068` case calls
neither `enable_ulaplus()` nor anything equivalent — ZEsarUX doesn't
implement ULAPlus for this machine AT ALL. There is nothing to
cross-check `ULAPLUS`/`PALETTE` against: no second emulator offers a
TS2068 ULAPlus implementation to compare Fuse's patched one to. This
is exactly consistent with (and reinforces, from an independent
source) this section's own already-stated belief that real TS2068
hardware never had genuine ULAPlus — the caveat isn't resolved by
proving Fuse "right" or "wrong," it's resolved by confirming there's
no reference implementation anywhere to check it against. Treat
`ULAPLUS`/`PALETTE` as permanently Fuse-only, by the nature of the
feature itself, not as a temporarily-unverified one.

## Documentation pass: the user manual brought current

**Done.** `docs/forth_tutorial.md` (this project's own user-facing
manual — a full language tutorial plus a word-reference appendix) had
drifted significantly behind the real dictionary: a fresh audit (every
`DB len,"NAME"` header across `core/*.asm`, cross-referenced against
what the document actually covered) found it stopped at roughly Phase
32-33's own vocabulary, missing everything from Phase 34 onward — about
39 of the 113 words that actually exist, roughly a third of the real
dictionary. Brought fully current: new prose sections for `ROT`/
`2DUP`/`2DROP`/`?DUP`/`PICK`, bitwise/logical operators, `'`/`EXECUTE`,
`CR`/`SPACE`/`SPACES`, the Phase 40 string functions, float conversion/
rounding/`RAD`/`DEG`, `C@`/`C!`/`FREE`, `CLS`/`KEY?`/`STICK`, and three
new full sections (14: `THROW`/`CATCH`, 15: `LPRINT`/`LLIST` with its
own honest unverified-status caveat, 16: `ULAPLUS`/`PALETTE` with its
own confirmed-working-here-but-real-hardware-uncertain caveat). The
previously-undocumented `STACK?` runtime error message (Phase 38) was
also added, since `THROW`/`CATCH`'s own new section builds directly on
it. Appendix A's own word-reference table was rebuilt and checked
programmatically against the real 113-word dictionary — every word
confirmed present, nothing missed. Several worked examples were
verified against real Fuse output (not hand-computed) before being
trusted, catching two real arithmetic mistakes in early drafts (a
truncation-vs-rounding error in a `DEG` example, and a nonexistent
`1+` word used in a `C@` example) before they could mislead a reader.

## Future stretch goal — a real 64-column TEXT mode in the editor

**DONE 2026-09-06 (Phases 56/57/58) — kept below for the real research
history that shaped the design, not as an open item any more.** The
actual implementation took a different, cheaper path than anything
scoped below: rather than a new narrower font, `kernel/mode64/
mode64.asm`'s existing two-display-file split (already used for pixel
graphics) turned out to give exactly 64 real text columns using the
EXISTING 8x8 font unchanged, once a character drawer aware of that
split existed (`MODE64_PUTCHAR`, Phase 56) — no new glyph data, no ROM
font-budget cost. `core/print.asm`'s `EMIT` became mode-aware (Phase
57, mirroring how `HIRES`/`NORMAL` had just made `PLOT`/`LINE`/`CIRCLE`
mode-aware), and `core/editor.asm` got a full `EDITOR_REDRAW64`/
`WRAP_CALC64` sibling pair for live typing (Phase 58) — planned with
the user beforehand specifically because this file's own two
documented incidents below made a shared, branch-threaded body too
risky to attempt. The 64-column cursor is a static (non-blinking)
`MODE64_PUTCHAR_XOR` block, not a real blink — Mode 6 has no per-cell
attribute byte to drive the existing hardware-FLASH trick, and a real
blink would need new ISR timing plus a live-loop rewrite, deliberately
deferred as a separate, riskier follow-up rather than folded in here.
See `docs/forth_tutorial.md` section 12 for the user-facing result.

**Original scoping notes follow, unedited, for the historical record.**
User request, 2026-09-01,
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
and even that observation carried a caveat: **this session's Fuse
binary is patched for ULAPlus**, so port `$FF` writes (exactly what
`MODE64_ON` does) may be getting reinterpreted by that patch rather
than emulated as genuine TS2068/SCLD hardware behavior.

**RESOLVED 2026-09-06 via a real ZEsarUX cross-check.** Two throwaway
diagnostic ROMs (`rom/mode64_visual_check.asm`, `rom/hires_visual_check.asm`
— not smoke ROMs, no PASS/FAIL, kept only as reproducible tools for
this kind of check), each drawing two solid, distinctly-colored 20x20
blocks with a wide gap between them, were run in ZEsarUX 13.0 via its
ZRCP remote protocol (`--romfile` wants a single file: this project's
own 16KB Home ROM immediately followed by its 8KB EXROM concatenated
together, unlike Fuse's two separate `--rom-ts2068-0`/`-1` flags).
ZEsarUX's own TS2068 profile has ZERO ULAPlus involvement (see Phase
48's own section above) — a genuinely independent reference, not just
a second copy of the same patch.

Findings, confirmed by `read-memory`/`get-io-ports` over ZRCP (byte-
exact port $FF values and real nonzero pixel data in both display
files, matching this project's own Fuse-based checkpoints exactly)
AND by real `save-screen` screenshots:
- **HIRES (port $FF bits `%010`) renders correctly** — the two test
  blocks appeared as two distinctly colored solid squares, proving a
  second, ULAPlus-uninvolved emulator agrees this mode's real
  per-scanline-attribute visuals are sound.
- **64COL (port $FF bits `%110`) renders as a single flat-colored
  rectangle in ZEsarUX too** — regardless of the confirmed-correct
  underlying bitmap content, and unchanged across every palette value
  tried (0, 3, 5, 7). The border color tracks the palette selection;
  the interior never does.

Conclusion: the "whole screen goes to one color" behavior is NOT a
Fuse-specific ULAPlus-patch artifact — ZEsarUX shows the identical
flat-rectangle behavior for the identical hardware mode, and ZEsarUX
has no ULAPlus patch to blame it on. The much more likely explanation
is that BOTH commonly-used Spectrum-family emulators have an
incomplete/simplified rendering path for this specific, rare 512-pixel
split-display-file "Mode 6" — unsurprising given how few real programs
ever used it (three obscure third-party tools, per this section's own
research below). This is an emulator-fidelity limitation shared by
both tools available in this environment, not a bug in this project's
own Z80 code (already independently confirmed byte-correct in both
emulators) and not something either emulator's own settings can fix.
Actually seeing 64COL's real visual appearance would need either real
TS2068 hardware or a third emulator with a more complete Mode 6
implementation — out of scope to pursue further here.

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
other open items (hi-res mode; the ULAPlus visual-fidelity check
against unpatched ZEsarUX noted above); nothing currently planned
depends on it, and it doesn't block anything currently planned either.
(AY-3-8912 `SOUND` was itself an open item when this section was first
written — Phase 32 closed it with real register-level access; see that
phase's own section above.)

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
