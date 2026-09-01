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

Line buffer via `kernel/io`'s `IO_READ_KEY`, `WORD` (parse a
blank-delimited token), `FIND` (dictionary search), `NUMBER` (decimal
literal parsing — 2068-Leap's own expression-evaluator numeric-literal
scanning in `basic.asm` is worth reading as a reference for edge cases
it already found, even though none of that code is reused directly),
`STATE` (interpret vs. compile), `:` `;`, `IMMEDIATE`.

## Phase 4 — control flow

`IF ELSE THEN`, `BEGIN UNTIL`, `BEGIN WHILE REPEAT`, `DO LOOP`/`+LOOP`,
`I`/`J`/`LEAVE` — compiled branch offsets, resolved at compile time by
the colon compiler from Phase 3. No runtime statement-boundary scanning
of the kind `basic.asm` does for `ELSEIF`/`ELSE`/`END IF` — Forth
compiles the jump once, unlike line-oriented BASIC re-parsing structure
on every pass.

## Phase 5 — TS2068 vocabulary

Thin `CODE` words wrapping the kernel 1:1, matching `include/
kernel_api.inc` almost verbatim: `PLOT`, `LINE`, `CIRCLE`, `FILL`,
`BORDER`, `BEEP`, `AT-XY`, hi-res `MODE`. This is the point where the
project starts feeling like it has real payoff over hand-written Z80:
each of these is a few lines, no registry, no ABI, no fixed window —
directly contrasting with what 2068-Leap had to build
(`docs/loadable_basic_extensions.md`) to get equivalent extensibility
in BASIC.

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
