# 2068-Forth

A from-scratch Forth for the Timex Sinclair 2068, built on the hardware
kernel proven out by **2068-Leap** (structured-BASIC ROM, same author,
separate local repository at `~/ts2068rom`). This project does not fork or
track 2068-Leap — it started by copying that project's hardware-facing
`kernel/` modules and a few build/test tools out of it, read-only, and
is free to diverge from its conventions from here on. See
[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md) for exactly what was
inherited, what was deliberately left behind, and the phased build order.

## Status

- Milestone 0 (`rom/main.asm`, inherited verbatim from 2068-Leap's own
  Milestone 0): boot stub, border-cycle smoke test. Done.
- Phase 2 (`core/dict.asm` + `rom/forth_smoke.asm`): dictionary header
  format, the IX-based data stack, and eight subroutine-threaded CODE
  primitives (`DUP SWAP DROP OVER + - @ !`), self-checked and confirmed
  passing under Fuse.
- Phase 3 (`core/interp.asm` + `rom/forth_smoke_p3.asm`): the outer
  interpreter (`WORD`, `FIND`, `NUMBER`) and a real colon compiler
  (`:`, `;`). Confirmed passing under Fuse: interprets plain arithmetic,
  then defines a new word and calls it. Input is still a fixed buffer,
  not a live keyboard — see `docs/PROJECT_PLAN.md` Phase 3.
- Phase 4 (`core/control.asm` + `rom/forth_smoke_p4.asm`): control flow
  — `IF`/`ELSE`/`THEN` and `BEGIN`/`UNTIL`, plus `0=` (needed to give
  them a proper boolean flag to test). Confirmed passing under Fuse:
  both branches of an `IF`, and a loop confirmed to iterate the correct
  number of times. `WHILE`/`REPEAT` and `DO`/`LOOP` are follow-up work
  — see `docs/PROJECT_PLAN.md` Phase 4.
- Phase 5 (`core/ts2068.asm` + `rom/forth_smoke_p5.asm`): TS2068
  vocabulary — `PLOT`, `LINE`, `CIRCLE`, `BEEP`, `BORDER`, thin wrappers
  over `kernel/graphics`/`kernel/sound`. Confirmed passing under Fuse,
  including a real screenshot of a dot/line/circle drawn exactly where
  expected. This is also where a real, previously-invisible bug got
  found and fixed: this project's own Phase 3 scratch RAM aliased real
  2068-Leap kernel sysvars once `kernel/graphics`/`kernel/sound` were
  actually assembled alongside `core/` for the first time — see
  `docs/PROJECT_PLAN.md` Phase 5 for the full story and the probe
  method used to catch it. `FILL`, `AT-XY`, and hi-res `MODE` are
  follow-up work.
- Phase 6 (`core/editor.asm` + `rom/forth_smoke_p6.asm`): line editing
  — a single-line input buffer with insert, backspace-delete, and
  left/right cursor movement. Confirmed passing under Fuse: three
  canned key sequences (plain typing; cursor-left then a mid-buffer
  insert; cursor-left, delete, cursor-right) each committed via
  `INTERPRET_RUN` and checked against the correct final result. The
  real interactive entry point (`EDITOR_LOOP_LIVE`) is written but
  **not yet safely callable** — see `docs/PROJECT_PLAN.md` Phase 6 for
  a real precondition found while writing it (`kernel/io`'s
  `IO_READ_KEY` needs a live interrupt wired up first, which no ROM in
  this project sets up yet).
- Phase 7 (`core/storage.asm` + `rom/forth_smoke_p7.asm`): storage —
  `SAVE`/`LOAD` as whole-dictionary-image blobs on `STORAGE_SAVE`/
  `STORAGE_LOAD`, Jupiter-Ace-style. Calls only the documented public
  contract, never `kernel/storage`'s own internals — a deliberate
  design constraint from a real compatibility warning (the tape format
  is fragile; deviating from it breaks real emulator LOAD). Found and
  fixed two real integration bugs along the way (`IX` gets destroyed by
  the storage calls; `STORAGE_LOAD`'s filename match needs a real
  space-padded 10-byte buffer, not a raw shorter one) — see
  `docs/PROJECT_PLAN.md` Phase 7 for both. Confirmed passing against an
  in-memory fake tape transport (kernel/storage's own
  `STORAGE_TEST_FAKE_SEND`/`RECEIVE` hooks); a **real Fuse tape
  round-trip is still open, deliberately deferred** — this proves the
  wiring, not real wire-format compatibility in an actual emulator.
- Phase 8, stretch goals (`core/float.asm` + `rom/forth_smoke_p8.asm`;
  `kernel/mode64/mode64.asm` + `core/mode64.asm` + `rom/forth_smoke_p8b.asm`):
  - **Floating point** — `F+`/`F-`, a small native Forth float
    implementation (3-byte mantissa+exponent, its own `IY`-addressed
    stack), NOT a port of 2068-Leap's real `RST $28` calculator engine
    (assessed as multi-session-sized; this project is free to diverge).
    Confirmed passing under Fuse. `F*`/`F/`/`F.` remain open.
  - **64-column display** — `64COL`, `32COL`, `PALETTE64`, `PLOT64`.
    This is recovered, once-shipped 2068-Leap code (removed from that
    project 2026-08-20 for its own ROM-budget reasons), found in a
    pre-git backup tarball at the user's own suggestion — good thing:
    the ROM disassembly alone led to a real, wrong first attempt (bit 2
    alone, when the real hardware needs bits 1+2 together). Confirmed
    passing under Fuse; a genuine unexplained rendering observation
    (the whole visible area, border included, renders as one uniform
    color while this mode is active) is recorded, not resolved — see
    `docs/PROJECT_PLAN.md` Phase 8 for the full story.
- Phase 9 (`rom/forth_boot.asm` + `rom/forth_smoke_p9.asm`): **a real,
  live, bootable system.** Every phase's dictionary words spliced into
  one `FIND`-able chain (a real structural fix — `core/control.asm`,
  `core/storage.asm`, and `core/float.asm` were siblings of a tree, not
  links in one chain, until this phase); real `IM 1` interrupt wiring,
  confirmed against 2068-Leap's own working ROM files; a boot banner
  and startup sound (the tracked product requirement — done). Confirmed
  working by a human typing `5 BORDER` at the running system and
  watching the border turn cyan — the first genuine end-to-end proof in
  this project not based on a fixed test string. Getting there
  surfaced two real bugs no automated test could have caught (an
  accumulating-inverted-text redraw bug, and a case-folding bug — real
  keyboards produce lowercase letters, the whole dictionary is
  uppercase), both found live with the user typing at the keyboard and
  one diagnosed from a real Fuse memory-dump snapshot. See
  `docs/PROJECT_PLAN.md` Phase 9 for the full story.
- Phase 10 (`core/print.asm` + `rom/forth_smoke_p10.asm`): `EMIT` and
  `.` — the first words in this project that can show a computed value
  on screen. Includes a from-scratch unsigned divide-by-10
  (`kernel/math`'s divide is signed, which mishandles `-32768`'s
  magnitude) confirmed correct via a real property of two's-complement
  negation, not luck. Confirmed passing under Fuse (five checkpoints,
  including a real `GFX_READ_PIXEL` readback for `EMIT`). Wiring this
  into `rom/forth_boot.asm` surfaced one more real bug — `COLD_START`
  started the print cursor at `(0, 0)`, exactly where the boot banner's
  own text is, so `EMIT`'s first output silently overwrote it — found
  live by the user, isolated with a deterministic headless diagnostic,
  and fixed by starting the cursor below the banner instead. See
  `docs/PROJECT_PLAN.md` Phase 10 for the full story.
- Phase 11 (`core/compare.asm` + `rom/forth_smoke_p11.asm`): `=`, `<`,
  `>` — signed comparisons, filling the gap `docs/forth_tutorial.md`
  had flagged since Phase 4. No `kernel/` dependency. Signed `<`/`>`
  use a sign-bit case split rather than the Z80's own overflow flag,
  hand-verified against six cases including both 16-bit extremes.
  Confirmed passing under Fuse (ten comparisons across three
  checkpoints) and re-verified wired into `rom/forth_boot.asm`'s full
  chain via a deterministic diagnostic. See `docs/PROJECT_PLAN.md`
  Phase 11 for the full story.
- Phase 12 (`core/variable.asm` + `rom/forth_smoke_p12.asm`):
  `VARIABLE` and `CONSTANT`, filling the last gap
  `docs/forth_tutorial.md` had flagged since Phase 4. Neither uses a
  real `CREATE`/`DOES>` (this project doesn't have one) — both reuse
  `core/interp.asm`'s own `DOLIT` compiled-literal idiom plus a
  compiled `RET`. Confirmed passing under Fuse (three checkpoints,
  including proof that two variables don't alias each other's storage)
  and re-verified wired into `rom/forth_boot.asm`'s full chain via a
  deterministic diagnostic. See `docs/PROJECT_PLAN.md` Phase 12 for the
  full story.
- **`docs/forth_tutorial.md`** teaches the Forth
  *language* to a reader who doesn't already know it — from the
  standpoint of someone using the finished product, not this project's
- **`docs/forth_tutorial.md`** teaches the Forth
  *language* to a reader who doesn't already know it — from the
  standpoint of someone using the finished product, not this project's
  own build/test process. It assumes BASIC familiarity but not
  assembly. Meant to grow alongside the language itself, one section
  per capability as it becomes real and usable.
- The language core is integer-only by design; see
  `docs/numeric_model.md` for why floating point is a deferred, optional
  addition rather than something the language is built on.

## Layout

```
core/       language-layer code, not hardware-facing:
              dict.asm    (Phase 2 — dictionary header format, data stack)
              interp.asm  (Phase 3 — outer interpreter, colon compiler)
              control.asm (Phase 4 — IF/ELSE/THEN, BEGIN/UNTIL)
              ts2068.asm  (Phase 5 — PLOT/LINE/CIRCLE/BEEP/BORDER)
              editor.asm  (Phase 6 — line editing)
              storage.asm (Phase 7 — SAVE/LOAD)
              float.asm   (Phase 8 stretch — F+/F-)
              mode64.asm  (Phase 8 stretch — 64COL/32COL/PALETTE64/PLOT64)
              print.asm   (Phase 10 — EMIT/.)
              compare.asm (Phase 11 — =/</>)
              variable.asm (Phase 12 — VARIABLE/CONSTANT)
kernel/     hardware-facing modules: inherited from 2068-Leap (memory,
            io, graphics, interrupt, math, sound, storage, bank) plus
            2068-Forth's own addition, mode64/ (recovered, once-shipped
            2068-Leap code — see that module's own header)
include/    hardware/keyboard constants and the inherited kernel API
            contract (include/kernel_api.inc)
rom/        ROM image assembly:
              main.asm            Milestone 0 boot stub
              forth_smoke.asm     Phase 2 smoke ROM
              forth_smoke_p3.asm  Phase 3 smoke ROM
              forth_smoke_p4.asm  Phase 4 smoke ROM
              forth_smoke_p5.asm  Phase 5 smoke ROM
              forth_smoke_p6.asm  Phase 6 smoke ROM
              forth_smoke_p7.asm  Phase 7 smoke ROM
              forth_smoke_p8.asm  Phase 8 stretch smoke ROM (floating point)
              forth_smoke_p8b.asm Phase 8 stretch smoke ROM (64-column)
              forth_smoke_p9.asm  Phase 9 smoke ROM (dictionary + interrupts)
              forth_smoke_p10.asm Phase 10 smoke ROM (EMIT/.)
              forth_smoke_p11.asm Phase 11 smoke ROM (=/</>)
              forth_smoke_p12.asm Phase 12 smoke ROM (VARIABLE/CONSTANT)
              forth_boot.asm      the real, live, bootable product ROM
tools/      build wrapper (sjasmplus_strict.sh) and static/simulated
            Z80 checks (check_asm.py, check_z80_opcodes.py, z80sim/)
docs/       PROJECT_PLAN.md (read this first, project/build-facing),
            forth_tutorial.md (learn the Forth language itself,
            user-facing — no assembly or build content), numeric_model.md
            (integer-core decision), hardware_notes.md (confirmed
            hardware facts, inherited from 2068-Leap)
```

## Quick start

Requires GNU Make, Python 3, and
[SjASMPlus 1.23.1](https://github.com/z00m128/sjasmplus/releases/tag/v1.23.1)
or a compatible newer release.

```sh
make boot             # assembles rom/main.asm -> build/forth_rom0.bin
make forth-smoke      # Phase 2 dictionary/primitives smoke ROM
make forth-smoke-p3   # Phase 3 outer interpreter/colon compiler smoke ROM
make forth-smoke-p4   # Phase 4 control-flow smoke ROM
make forth-smoke-p5   # Phase 5 TS2068 vocabulary smoke ROM
make forth-smoke-p6   # Phase 6 line-editing smoke ROM
make forth-smoke-p7   # Phase 7 storage (SAVE/LOAD) smoke ROM
make forth-smoke-p8   # Phase 8 stretch: floating point smoke ROM
make forth-smoke-p8b  # Phase 8 stretch: 64-column display smoke ROM
make forth-smoke-p9   # Phase 9 smoke ROM: full dictionary + real interrupts
make forth-smoke-p10  # Phase 10 smoke ROM: EMIT/.
make forth-smoke-p11  # Phase 11 smoke ROM: =/</>
make forth-smoke-p12  # Phase 12 smoke ROM: VARIABLE/CONSTANT
make forth-boot       # the real, live, bootable product ROM
make check            # static asm checks over core/, kernel/, and rom/
```

## Try it

`make forth-boot` builds the real, live product — not a smoke test.
Run it in Fuse with a real EXROM image (see `rom/forth_smoke.asm`'s own
header on why a real image, not a blank placeholder, matters here):

```sh
fuse --machine ts2068 --rom-ts2068-0 build/forth_boot_rom0.bin \
     --rom-ts2068-1 <a real EXROM image>
```

It boots to a banner, plays a short startup sound, and drops you at a
real keyboard-driven prompt. Try `5 BORDER` and press Enter, `5 3 + .`
to see `.` print `8` on the row below the banner, `5 3 > .` to see `-1`
(Forth's TRUE) printed, or `VARIABLE FOO 42 FOO ! FOO @ .` to see `42`.

## License

MIT — see [LICENSE](LICENSE).
