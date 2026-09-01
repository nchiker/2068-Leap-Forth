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

Milestone 0 only: the boot stub (`rom/main.asm`, inherited verbatim from
2068-Leap's own Milestone 0) assembles and produces a 16K ROM0 image with
a border-cycle smoke test. Nothing Forth-specific exists yet — see
`docs/PROJECT_PLAN.md`'s Phase 0 and Phase 1 for what comes next.

## Layout

```
kernel/     hardware-facing modules inherited from 2068-Leap: memory,
            io, graphics, interrupt, math, sound, storage, bank
include/    hardware/keyboard constants and the inherited kernel API
            contract (include/kernel_api.inc)
rom/        ROM image assembly; rom/main.asm is the Milestone 0 boot stub
tools/      build wrapper (sjasmplus_strict.sh) and static/simulated
            Z80 checks (check_asm.py, check_z80_opcodes.py, z80sim/)
docs/       PROJECT_PLAN.md (read this first), hardware_notes.md
            (confirmed hardware facts, inherited from 2068-Leap)
```

## Quick start

Requires GNU Make, Python 3, and
[SjASMPlus 1.23.1](https://github.com/z00m128/sjasmplus/releases/tag/v1.23.1)
or a compatible newer release.

```sh
make boot   # assembles rom/main.asm -> build/forth_rom0.bin
make check  # static asm checks over kernel/ and rom/
```

## License

MIT — see [LICENSE](LICENSE).
