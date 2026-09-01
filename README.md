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
  passing under Fuse. No compiler yet — the dictionary is hand-assembled,
  not built by `:`/`CREATE`. See `docs/PROJECT_PLAN.md` Phase 2/3.
- The language core is integer-only by design; see
  `docs/numeric_model.md` for why floating point is a deferred, optional
  addition rather than something the language is built on.

## Layout

```
core/       language-layer code, not hardware-facing: core/dict.asm
            (dictionary header format, data stack, Phase 2 primitives)
kernel/     hardware-facing modules inherited from 2068-Leap: memory,
            io, graphics, interrupt, math, sound, storage, bank
include/    hardware/keyboard constants and the inherited kernel API
            contract (include/kernel_api.inc)
rom/        ROM image assembly; rom/main.asm is the Milestone 0 boot
            stub, rom/forth_smoke.asm is the Phase 2 smoke ROM
tools/      build wrapper (sjasmplus_strict.sh) and static/simulated
            Z80 checks (check_asm.py, check_z80_opcodes.py, z80sim/)
docs/       PROJECT_PLAN.md (read this first), numeric_model.md
            (integer-core decision), hardware_notes.md (confirmed
            hardware facts, inherited from 2068-Leap)
```

## Quick start

Requires GNU Make, Python 3, and
[SjASMPlus 1.23.1](https://github.com/z00m128/sjasmplus/releases/tag/v1.23.1)
or a compatible newer release.

```sh
make boot         # assembles rom/main.asm -> build/forth_rom0.bin
make forth-smoke  # assembles the Phase 2 dictionary/primitives smoke ROM
make check        # static asm checks over core/, kernel/, and rom/
```

## License

MIT — see [LICENSE](LICENSE).
