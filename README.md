# 2068-Leap-Forth

### ▶ [Try it now, live in your browser — no install](https://nchiker.github.io/TSRun/?rom=leapforth)

### 📖 Learn the language — the [Forth tutorial](docs/forth_tutorial.md) ([Word/DOCX version](docs/forth_tutorial.docx))

A from-scratch Forth for the Timex Sinclair 2068, built on the hardware
kernel proven out by **2068-Leap** (structured-BASIC ROM, same author,
separate local repository at `~/ts2068rom`). This project does not fork or
track 2068-Leap — it started by copying that project's hardware-facing
`kernel/` modules and a few build/test tools out of it, read-only, and
is free to diverge from its conventions from here on. See
[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md) for exactly what was
inherited, what was deliberately left behind, and the phased build order.

## What makes 2068-Leap-Forth different

This is a **from-scratch, standalone Forth system that replaces the
TS2068's own system ROM** — not a BASIC extension, not a cross-compiler
targeting the machine from a host PC. Plug in the ROM image and you get
a real Forth prompt on power-up, with its own dictionary, its own
keyboard-driven line editor, and its own error handling, running
natively on 1980s Z80 hardware (or an accurate emulator of it).

Highlights:

- **A real, live keyboard editor** — insert, backspace-delete, and
  left/right cursor movement on a single-line input buffer, backed by a
  genuine hardware interrupt (not a polling loop), not a canned
  scripted input.
- **Floating point**, native to the dictionary: 5-byte Sinclair floats
  (about 9.6 digits, up to about ±1.7e38, rounded to nearest) with
  `F+ F- F* F/ FSQRT FROUND FLOOR S>F F>S`, `PI SIN COS TAN RAD DEG`,
  float stack words (`FDUP FDROP FSWAP FOVER FDEPTH FNEGATE FABS FMIN
  FMAX`), comparisons (`F< F> F= F0< F0=`), `F@ F! FVARIABLE FCONSTANT`,
  literals such as `3.5`, `.5` and `1E3`, and printing with `F.` (`n
  PLACES` sets the decimals), or `FS.` in scientific notation. Overflow,
  division by zero and an invalid argument are errors with a message, not
  a wrong answer — enough for actual numeric work, not just integer
  Forth.
- **A graphics and sound vocabulary** built on the TS2068's own
  hardware: `PLOT LINE CIRCLE FILL AT-XY`, `BEEP` (real semitone/second
  units, not raw hardware ticks) and `SOUND`, `INK`/`PAPER` color
  control, and `ULAPLUS`/`PALETTE` support for the TS2068's expanded
  color palette.
- **An EXROM-resident graphics extension** — `RECT`, `POLYGON`,
  `POLYGON-FILL` (even-odd fill rule), and a small sprite system
  (`SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`) dispatched through a
  second, real 8K ROM bank, so the core dictionary doesn't pay for
  functionality a given build doesn't need.
- **Real error handling**, not silent failure or a crash: `THROW`/
  `CATCH`, runtime stack-underflow/overflow detection, a message
  (`OUT OF RANGE`, `DIVISION BY ZERO`, `TAPE ERROR`, …) for an uncaught
  error, and a `?` printed on an unrecognized word with a prompt that
  recovers cleanly instead of hanging.
- **Tape storage**, Jupiter-Ace-style: `SAVE-LIB`/`LOAD-LIB` round-trip
  a whole dictionary image (CRC-checked, tied to the exact ROM release
  that saved it), `SAVE-TEXT`/`LOAD-TEXT` the portable source text, and
  `VERIFY-LIB`/`VERIFY-TEXT` compare a tape with memory. Failures are
  `THROW`n (`-28` for SPACE, `-37` for any other tape failure, `-8` if
  an image doesn't fit), so a program can `CATCH` them. The tape blocks
  use the standard Sinclair format, sent and received by 2068-Leap-C's
  clean-room block I/O (`kernel/storage/tapeblock.asm`).
- **Printer support** — `LPRINT`/`LLIST` send Forth's own listings and
  output to a real TS2068 printer interface.
- Arrays (`ARRAY`/`CELLS`), string handling (`S" TYPE STRING PLACE
  COUNT LEN VAL`), and the rest of a genuinely usable language: `DO/
  LOOP/I` with `LEAVE`/`+LOOP`, `BEGIN/WHILE/REPEAT`, `IF/ELSE/THEN`,
  `VARIABLE`/`CONSTANT`, decimal literals, and joystick input
  (`STICK`).

See the [Forth tutorial](docs/forth_tutorial.md) linked at the top to
actually learn the language, or jump straight to "Try it" below for a
hands-on tour — or [try it live in your browser](https://nchiker.github.io/TSRun/?rom=leapforth)
right now, no download required.

## Try it

**Fastest path: [nchiker.github.io/TSRun/?rom=leapforth](https://nchiker.github.io/TSRun/?rom=leapforth)**
runs it in your browser via [TSRun](https://github.com/josef-jelinek/TSRun): no download or install.

Locally, take the images from the latest build (see "Download") or build them (`make`, see
[CONTRIBUTING.md](CONTRIBUTING.md)): `forth_boot_rom0.bin` is the 16 KB HOME ROM and `graphics_exrom.bin` the 8 KB
EXROM. The EXROM holds the full-screen editor (`EDIT`), `FILL`, `CIRCLE`, `RECT`, `POLYGON`, `POLYGON-FILL` and the
sprites; without it those words report `NO EXROM` and everything else works.

```sh
fuse --machine ts2068 --rom-ts2068-0 forth_boot_rom0.bin --rom-ts2068-1 graphics_exrom.bin
```

It boots to a white screen with its version (`2068 FORTH V2.0`) on the status bar at the bottom, plays a short startup
chord and waits at the prompt. Try:

| Type | It prints or does |
|---|---|
| `5 3 + .` | `8` |
| `: GREET ." HI" ; GREET` | `HI` |
| `: FIVE 5 0 DO I . LOOP ; FIVE` | `0 1 2 3 4` |
| `VARIABLE FOO 42 FOO ! FOO @ .` | `42` |
| `3.5 2.5 F+ F.` | `6.0000` |
| `9 PLACES PI F.` | `3.141592653` |
| `1.0 0.0 F/` | `DIVISION BY ZERO` |
| `2 INK 100 100 30 CIRCLE 100 100 FILL` | a red disc |
| `4 INK 100 40 140 40 100 80 3 POLYGON` | a green triangle |
| `EDIT GREET` | the full-screen editor on GREET's source |

## Running it

| Emulator | How |
|---|---|
| Fuse 1.9.1 | `--rom-ts2068-0 forth_boot_rom0.bin --rom-ts2068-1 graphics_exrom.bin` (as above). Fuse has no ULAplus for Timex machines, so `ULAPLUS`/`PALETTE` do nothing there. |
| ZEsarUX 13.0 | `zesarux --noconfigfile --machine TS2068 --romfile forth_zesarux.bin` (the two images as one file). The EXROM words need ZEsarUX built with `patches/0001-zesarux-mirror-ts2068-exrom.patch` (the real TS2068 mirrors its EXROM across all eight chunks; stock ZEsarUX mirrors two): [docs/zesarux_setup.md](docs/zesarux_setup.md). |
| TSRun (browser) | "Load ROM0" `forth_boot_rom0.bin`, "Load ROM1" `graphics_exrom.bin`. |
| EightyOne 1.41 | the HOME ROM as the ROM file, `graphics_exrom.dck` as a Timex ROM cartridge: [docs/eightyone_setup.md](docs/eightyone_setup.md) (the EXROM cartridge does not load correctly on EightyOne 1.41). |
| TS-Pico | the HOME ROM in its ROM slot; TS-Pico has no EXROM slot yet: [docs/ts_pico_setup.md](docs/ts_pico_setup.md). |

Everything here is checked on emulators only (ZEsarUX, Fuse, TSRun); there is no real hardware in this project.

## Download

[![Build ROMs](https://github.com/nchiker/2068-Leap-Forth/actions/workflows/build.yml/badge.svg)](https://github.com/nchiker/2068-Leap-Forth/actions/workflows/build.yml)

Every push to `master` builds
[2068-Forth-latest.zip](https://github.com/nchiker/2068-Leap-Forth/releases/download/latest/2068-Forth-latest.zip):
the two images, the two as one file for ZEsarUX, the EXROM `.dck`, `SHA256SUMS`, the symbol listings, the demo
programs' source (`demos/`) and the documents as Markdown, PDF and DOCX. Numbered releases are on the
[releases page](https://github.com/nchiker/2068-Leap-Forth/releases); `make dist` makes the same zip locally.

## Building, testing, contributing

[CONTRIBUTING.md](CONTRIBUTING.md): prerequisites, `make`, `make check`, `make test`, the rules for changes and the
layout of the repository. Where the project stands and what comes next: [docs/V2/ROADMAP.md](docs/V2/ROADMAP.md);
the changes: [docs/CHANGELOG.md](docs/CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
