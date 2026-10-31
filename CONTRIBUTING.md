# Contributing to 2068-Leap-Forth

Bug reports, test results from emulators, documentation fixes and code are welcome. This page is for building and
changing Leap-Forth.

## Prerequisites

| For | You need |
|---|---|
| `make`, `make check`, `make repro`, `make budget` | **[sjasmplus](https://github.com/z00m128/sjasmplus) 1.23.1** (exactly: the images are byte-reproducible with it), **Python 3.11** or later, GNU make, a POSIX shell, `sha256sum` |
| `make test`, `make test-fast`, `make tapetol` (the ZEsarUX suites) | ZEsarUX 13.0 built with the EXROM patch (`patches/`), [ts2068-debug](https://github.com/nchiker/2068-Debug) (a checkout: its ZRCP client is imported), Linux |
| `make fusesave`, `make tapetol-fuse` | Fuse 1.9.1 built from source and not stripped, gcc and the SDL2 development files (the harness's shim), fuse-utils (`tape2wav`, `audio2tape`) |
| `make docs`, `make dist` | pandoc, WeasyPrint and python-docx (`tools/requirements-docs.txt`) |

### Where the tools are: environment variables

| Variable | Default | Used by |
|---|---|---|
| `TS2068_DEBUG_DIR` | `~/ts2068-debug` | the ZEsarUX suites: the ts2068-debug checkout |
| `TS2068_DEBUG_ZESARUX_DIR` | `~/Applications/ZEsarUX-13.0` | the ZEsarUX suites: the folder with the patched `zesarux` binary and its data files |
| `FORTH_REALTIME` | unset | `1` runs ZEsarUX at real speed (the suites otherwise use `--emulatorspeed 1000 --frameskip 49`, which changes no emulated timing) |
| `FORTH_FUSE` | `/usr/local/bin/fuse` | the Fuse suites |
| `FORTH_STOCK_ROMS` | `~/fuse-build/roms` | `tools/provenance.py` (`make check`): the stock `48.rom`, `tc2068-0.rom`, `tc2068-1.rom`, compared with the images, never stored here; without them the check is skipped |

## Building and testing

```sh
make             # build/forth_boot_rom0.bin (HOME), graphics_exrom.bin (EXROM), forth_zesarux.bin (the two as one
                 # 24 KB file for ZEsarUX), graphics_exrom.dck (EightyOne, TS-Pico), build/SHA256SUMS
make check       # strict assembly, opcode and source checks, the RAM layout guard, ROM budgets, provenance,
                 # the adopted tape code, the tape tools' self-test, ROM_IDENTITY
make repro       # two clean builds must give identical hashes
make budget      # free bytes per image against the floors (budget.toml)
make inventory   # every routine's size and referrers, per component; the ones nothing reaches (UNR)
make test        # ZEsarUX: every suite on a pool of emulators (tools/run_tests.py), about 10 minutes
make test-fast   # the development subset, about 2 minutes
make tapetol     # the tape receiver's tolerance (TAPETOL_BASE=<old build dir> compares two builds)
make fusesave    # SAVE-TEXT and SAVE-LIB on Fuse's tape deck, decoded by fuse-utils and loaded back
make audio       # what the emulated AY plays for BEEP (real time, about two minutes)
```

`make test` runs these suites (`tools/run_tests.py --suite NAME` runs one; arguments after the options filter cases by
name):

| Suite | What it checks |
|---|---|
| boot | the image boots to the prompt; banner, glyph table, the harness itself (`tools/fharness.py`) |
| forth | the Forth tests in `tests/` typed at the prompt (`tools/forthtest.py` documents the format) |
| editor | the console and the full-screen editor, the redraw oracle, typing cost (`tools/edtest.py`) |
| float | the float words against a bit-exact model, integer `*` `/` `MOD`, `RND` (`tools/floattest.py`) |
| shape | `FILL` and `CIRCLE` against a model (`tools/shapetest.py`) |
| bench | the programs in `tests/bench/`, timed in T-states (recorded) |
| poweron | the boot from power-on RAM patterns (`tools/poweron.py`) |
| tape | `SAVE`/`LOAD`/`VERIFY` on real tape signals (`tools/tapetest.py`) |

Continuous integration (`.github/workflows/build.yml`) installs sjasmplus 1.23.1 and runs `make check`, `make repro` and
`make dist`. The emulator suites run locally.

## Rules for changes

- **ROM space is the hard limit.** `make check` fails when an image's free space falls below its floor in
  `budget.toml`. When something does not fit: shrink, move cold code to the EXROM, reallocate, then ask the owner.
- **Every change to behaviour comes with tests** that fail without it: a Forth test in `tests/` (lines with
  `\ expect:`), or a case in one of the suites above.
- **Symbolic layout only:** RAM addresses live in `include/forth_layout.inc` (`make check` proves it). Every routine's
  header states In / Out / Destroys.
- **Release images** are the production build; `make repro` must give identical hashes.
- Commit messages: a short summary line, then what and why. Do not commit `build/`, emulator screenshots, or stock ROM
  images.

## Layout

| Path | Contents |
|---|---|
| `rom/` | the two images: `forth_boot.asm` (HOME) and `graphics_exrom.asm` (EXROM) |
| `core/` | the language: interpreter, compiler, the words |
| `kernel/` | the hardware layer: graphics, keyboard and interrupt, memory, banking, tape |
| `include/` | the RAM layout, hardware constants, the EXROM interface, key codes |
| `tests/` | the Forth tests by area, the benchmarks (`tests/bench/`), test data |
| `tools/` | build, check and test tools; the ZEsarUX harness (`fharness.py`, `run_tests.py`), the Fuse harness (`fusedrive.py`, `fuse/`), the tape tools (`tapes.py`, `tape_gen_forth.py`), `z80sim/` |
| `demos/` | Forth programs as source text (Blackjack, Shooting Gallery) |
| `docs/` | the tutorial and guides; the roadmap, handoff and milestone reports (`V2/`) |
| `patches/` | the ZEsarUX EXROM patch |

## Licence

By contributing you agree that your contribution is released under the MIT License ([LICENSE](LICENSE)). Do not
contribute code copied from the stock TS2068 or Spectrum ROMs or other copyrighted sources; [NOTICE](NOTICE) lists the
derived code already present.
