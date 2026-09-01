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
- **Not yet implemented, tracked for later:** the eventual live
  startup screen must play a startup sound. `BEEP` is done (Phase 5);
  the real remaining blocker, precisely identified in Phase 6, is
  wiring `RST $0038` to `kernel/interrupt`'s `KBD_ISR_TICK` (+ IM 1 +
  `EI`) so `EDITOR_LOOP_LIVE` can safely run — see
  `docs/PROJECT_PLAN.md`, "Product requirement — startup screen plays a
  startup sound."
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
kernel/     hardware-facing modules inherited from 2068-Leap: memory,
            io, graphics, interrupt, math, sound, storage, bank
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
make check            # static asm checks over core/, kernel/, and rom/
```

## License

MIT — see [LICENSE](LICENSE).
