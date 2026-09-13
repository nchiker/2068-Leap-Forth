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
- **Floating point**, native to the dictionary: `F+ F- F* F/ FSQRT
  FROUND S>F F>S`, plus `PI SIN COS` and a real `F.` printer — enough
  for actual numeric work, not just integer Forth.
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
- **64-column text mode** (`64COL`/`32COL`/`PLOT64`), recovered from
  once-shipped 2068-Leap code most TS2068 software never used.
- **Real error handling**, not silent failure or a crash: `THROW`/
  `CATCH`, runtime stack-underflow/overflow detection, and a `?`
  printed on an unrecognized word with a prompt that recovers cleanly
  instead of hanging.
- **Tape storage**, Jupiter-Ace-style: `SAVE-LIB`/`LOAD-LIB` round-trip
  a whole dictionary image through the documented public tape-transport
  contract — deliberately never reaching into the transport's own
  internals, so it stays compatible with real emulator/hardware LOAD.
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
— runs the full product, graphics extension included, directly in your
browser via [TSRun](https://github.com/josef-jelinek/TSRun), no
download, build, or emulator install needed.

For a local emulator instead, grab a built ROM from the latest release (see "Download" below), or
`make forth-boot` to build it yourself — either way it's the real, live
product, not a smoke test. Run it in Fuse with a real EXROM image, or
`tools/make_exrom_placeholder.sh`'s
generated placeholder if you don't have one (see `rom/forth_smoke.asm`'s
own header for why a content-free all-`$FF` placeholder was once found
unsafe here, and why this generated one is a safer stand-in):

```sh
tools/make_exrom_placeholder.sh   # writes build/stock_shaped_exrom.bin
fuse --machine ts2068 --rom-ts2068-0 build/forth_boot_rom0.bin \
     --rom-ts2068-1 build/stock_shaped_exrom.bin
```

It boots to a banner, plays a short startup sound, and drops you at a
real keyboard-driven prompt. Try `5 BORDER` and press Enter, `5 3 + .`
to see `.` print `8` on the row below the banner, `5 3 > .` to see `-1`
(Forth's TRUE) printed, `VARIABLE FOO 42 FOO ! FOO @ .` to see `42`,
`: GREET ." HI" ; GREET` to see `."` print a literal string, `: FIVE 5 0 DO I . LOOP ; FIVE` to see
`0 1 2 3 4` printed, `100 100 30 CIRCLE 2 INK 100 100 FILL` to see a
red-filled circle, type a nonsense word like `FOOBAR` to see `?`
printed and the prompt recover cleanly, `3.5 2.5 F+ F.` to see a
real decimal literal expression print `6.0000`, or
`: EVENS 10 0 DO I . 2 +LOOP ; EVENS` to see `+LOOP` step by 2 and
print `0 2 4 6 8`, `12345 RANDOMIZE 100 RND .` to see a reproducible
pseudo-random number in `[0, 100)`, `5 ARRAY NUMS 99 3 CELLS NUMS + !
3 CELLS NUMS + @ .` to see a real array round-trip a value, or
`S" HELLO WORLD" TYPE` to print a string literal directly, or
`INPUT .` to type a number and have it printed back, or
`9.0 FSQRT F.` to see a float square root print `3.0000`.

### Or leave the stock ROM in place and run it as a cartridge

`make forth-boot-cart` assembles the same Forth with `-DCARTRIDGE`,
which puts a 5-byte LROS header at `$0000` in place of the reset stub
(the TS2068 Technical Manual's §5.1.1 contract — the stock ROM finds
it, enables DOCK chunks 0-1, and jumps in) and wraps the result as
`build/forth_boot.dck`. Nothing else in the Forth changes between the
two builds — see the `IFDEF CARTRIDGE` blocks in `rom/forth_boot.asm`.
This is the way to run it on real hardware or a TS-Pico without
replacing the system ROM (see `docs/ts_pico_setup.md`), and it needs no
patch of any kind, on any emulator — confirmed on both:

```sh
fuse --machine ts2068 --rom-ts2068-0 <your-stock-ts2068-rom0.bin> --dock build/forth_boot.dck
```

or in ZEsarUX, over ZRCP: `smartload build/forth_boot.dck` then
`hard-reset-cpu` (or from the menu: SmartLoad the `.dck`, then a hard
reset). Either emulator needs its own copy of the genuine stock TS2068
ROM already configured — this project doesn't ship one, since it isn't
ours to redistribute, but every emulator here already bundles or
readily accepts one. The raw `build/forth_boot_cart.bin` is what goes
on the EPROM of a real cartridge. This currently covers only the base
dictionary — the graphics extension has no cartridge path yet (it
pages the EXROM bank, a physically different bank from DOCK — see
`docs/lros_cartridge.md`).

### RECT, POLYGON, POLYGON-FILL, and sprites (Phase 65)

These five words are dispatched through a second, real EXROM ROM bank
(chunk 5) instead of living in the 16K Home ROM directly — see
`docs/PROJECT_PLAN.md` Phase 65 for why. This means the placeholder
EXROM the "Try it" section above uses is NOT enough for these words —
`build/stock_shaped_exrom.bin` has no real code in it, so `RECT`/
`POLYGON`/`POLYGON-FILL`/`SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`
will each silently do nothing (the same magic/ABI mismatch guard every
other word in this project already uses instead of crashing). Build and
run the REAL EXROM image instead:

```sh
make forth-boot graphics-exrom
cat build/forth_boot_rom0.bin build/graphics_exrom.bin \
    > build/forth_boot_graphics_combined_24k.bin
zesarux --noconfigfile --machine TS2068 \
    --romfile build/forth_boot_graphics_combined_24k.bin
```

(or, in Fuse: `--rom-ts2068-0 build/forth_boot_rom0.bin
--rom-ts2068-1 build/graphics_exrom.bin`). At the running prompt, try
`2 INK 20 20 60 60 RECT` to see a filled red box (the default paper is
black, so use a real ink color, not `0` — black-on-black draws
correctly but shows nothing), `4 INK 100 40 140 40 100 80 3 POLYGON` to
see a green triangle outline, `3 INK 50 50 90 70 50 90 65 70 4
POLYGON-FILL` to see a filled magenta concave chevron/arrow shape
(even-odd rule — the notch stays unfilled), or
`2 INK 40 40 55 55 RECT 0 5 5 SPRITE-DEFINE 0 CLS 0 10 10 SPRITE-SHOW`
to draw a red 16x16 box exactly at character row/col (5,5), capture it
into sprite slot 0, clear the screen, and redraw the captured box at
row/col (10,10) — followed by `0 SPRITE-HIDE` to remove it and restore
the (now blank) background exactly.

This EXROM image is part of every CI-built release download — see
"Download" below — or build it from source as shown above.

## Status

Milestone 0 through Phase 65 are done: the full dictionary above, plus
the graphics extension, are built and passing their own smoke tests.
See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for the phase-by-phase
summary, or [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md) for the full
design rationale, bugs found, and fixes behind each one.

## Running it

Requires two files for anything beyond the base dictionary: a 16K Home
ROM (`forth_boot_rom0.bin`) and, only if you want the six graphics
words, an 8K EXROM image (`graphics_exrom.bin`) — see each emulator's
own section below for exactly how to combine them.

### Fuse

```sh
fuse --machine ts2068 --rom-ts2068-0 forth_boot_rom0.bin \
     --rom-ts2068-1 stock_shaped_exrom.bin
```

Works out of the box with any stock Fuse build. ULAplus support for
Timex machines isn't in upstream Fuse 1.9.1 — use ZEsarUX instead if
you want the `ULAPLUS`/`PALETTE` words, or apply the sibling
`ts2068rom` project's own Fuse patch (unrelated to anything below).

### ZEsarUX

```sh
zesarux --noconfigfile --machine TS2068 --romfile forth_boot_combined_24k.bin
```

**Works on a completely stock, unpatched ZEsarUX 13.0+ for everything
except the six graphics words** (`RECT`/`POLYGON`/`POLYGON-FILL`/
`SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`) — those need a small,
already-written patch (real TS2068 hardware mirrors its EXROM across
all 8 memory chunks; stock ZEsarUX only mirrors 2 of them). See
[`docs/zesarux_setup.md`](docs/zesarux_setup.md) for exactly which
patch, why, and how to build it — confirmed by direct A/B testing, not
assumed.

### EightyOne (Windows, or Linux via Wine)

Select the TS2068 machine, use `forth_boot_rom0.bin` as the ROM file,
and use `forth_exrom_eightyone.dck` as a **Timex ROM Cartridge** (not
the raw `stock_shaped_exrom.bin`). Base product confirmed working, both
under Wine on Linux and on Windows. **The graphics cartridge does not
load correctly on real EightyOne 1.41** — confirmed on both platforms,
and cross-checked as an EightyOne-specific issue (the identical `.dck`
file passes on ZEsarUX, Fuse, and TSRun — see
[`docs/eightyone_setup.md`](docs/eightyone_setup.md) for the full
cross-check and instructions for reporting it upstream).

### TSRun (browser)

[TSRun](https://josef-jelinek.github.io/TSRun/) is a browser-based
TS2068 emulator with its own "Load ROM0"/"Load ROM1"/"Load Cart"
buttons for a Home ROM, EXROM, and DCK cartridge respectively — load
`forth_boot_rom0.bin` as ROM0, and either `stock_shaped_exrom.bin` as
ROM1 or `graphics_exrom_eightyone.dck` as the Cart. Confirmed working
for both the base product and the graphics extension by running its
own open-source core (`github.com/josef-jelinek/TSRun`) headlessly —
GREEN border (full pass) on the real graphics EXROM, correctly BLUE
(fail) on the content-free placeholder used as a negative control.

### TS-Pico

The base product (everything except the six graphics words) already
runs on TS-Pico today, two independent ways: as a plain Home-ROM
replacement, or non-destructively as a DOCK cartridge
(`build/forth_boot.dck`, confirmed booting under Fuse and ZEsarUX with
the genuine stock ROM — real TS-Pico hardware itself untested so far).
The graphics extension doesn't have a path to TS-Pico yet (it has no
EXROM slot). See [`docs/ts_pico_setup.md`](docs/ts_pico_setup.md) for
the corrected, firmware-sourced picture of exactly how TS-Pico's
ROM/DOCK loading actually works, and exact load commands.

## Download

[![Build ROMs](https://github.com/nchiker/2068-Leap-Forth/actions/workflows/build.yml/badge.svg)](https://github.com/nchiker/2068-Leap-Forth/actions/workflows/build.yml)

You don't need the assembler to try it. Every push to `master` rebuilds
everything below and packages it with the docs:

- **Latest build** (rebuilt on every push):
  [2068-Forth-latest.zip](https://github.com/nchiker/2068-Leap-Forth/releases/download/latest/2068-Forth-latest.zip)
- **Numbered releases**: the [releases page](https://github.com/nchiker/2068-Leap-Forth/releases).
- Every push and pull request also gets a build artifact on the
  [Actions](https://github.com/nchiker/2068-Leap-Forth/actions) tab, if
  you want an image from a specific commit without waiting for a release.

The zip's `README-FIRST.txt` explains every file in it; in short:

- `roms/forth_boot_rom0.bin` — 16K Home ROM, the product.
- `roms/forth_demo_blackjack_rom0.bin` — the Blackjack demo ROM.
- `roms/stock_shaped_exrom.bin` — 8K EXROM placeholder.
- `roms/forth_boot_combined_24k.bin` / `forth_boot_graphics_combined_24k.bin` — Home+EXROM concatenated, for ZEsarUX (placeholder and real graphics EXROM respectively).
- `roms/graphics_exrom.bin` — the real 8K graphics EXROM (Phase 65).
- `cartridge/*.dck`, `cartridge/*_cart.bin` — both product ROMs as DOCK/LROS cartridges, for Fuse/ZEsarUX/real hardware/TS-Pico — see "Or leave the stock ROM in place" above. Base dictionary only; the graphics extension has no cartridge path yet.
- `eightyone/*.dck` — the placeholder and graphics EXROM wrapped for EightyOne's cartridge slot (a different mechanism from the DOCK cartridges above — bank `$FE`, not `$0`; NOT usable as-is on TS-Pico — see `docs/ts_pico_setup.md`, and `docs/eightyone_setup.md` for which of these actually work on real EightyOne).
- `experimental-lros/` — the earlier, unverified LROS/DOCK boot stub (see `docs/lros_cartridge.md`); superseded for most purposes by the `cartridge/` builds above, kept for reference.
- `symbols/`, `docs/`, `run_fuse.sh`, `BUILD_INFO.txt` — listings, docs as Markdown/PDF/DOCX, a ready-to-run Fuse script, and build provenance.

`make dist` produces the same zip locally. No prebuilt binaries are
committed into this repository itself — it's the source/development
repo. This is only 2068-Leap-Forth's own product ROM; it doesn't
include 2068-Leap's separate BASIC ROM or extensions.

## Building from source

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
make forth-smoke-p7   # Phase 7 storage (SAVE-LIB/LOAD-LIB) smoke ROM
make forth-smoke-p8   # Phase 8 stretch: floating point smoke ROM
make forth-smoke-p8b  # Phase 8 stretch: 64-column display smoke ROM
make forth-smoke-p9   # Phase 9 smoke ROM: full dictionary + real interrupts
make forth-smoke-p10  # Phase 10 smoke ROM: EMIT/.
make forth-smoke-p11  # Phase 11 smoke ROM: =/</>
make forth-smoke-p12  # Phase 12 smoke ROM: VARIABLE/CONSTANT
make forth-smoke-p13  # Phase 13 smoke ROM: ."
make forth-smoke-p14  # Phase 14 smoke ROM: WHILE/REPEAT
make forth-smoke-p15  # Phase 15 smoke ROM: INK/PAPER
make forth-smoke-p16  # Phase 16 smoke ROM: DO/LOOP/I
make forth-smoke-p17  # Phase 17 smoke ROM: FILL/AT-XY
make forth-smoke-p18  # Phase 18 smoke ROM: F*
make forth-smoke-p19  # Phase 19 smoke ROM: F/
make forth-smoke-p20  # Phase 20 smoke ROM: KEY
make forth-smoke-p21  # Phase 21 smoke ROM: error feedback
make forth-smoke-p22  # Phase 22 smoke ROM: F.
make forth-smoke-p23  # Phase 23 smoke ROM: decimal literals
make forth-smoke-p24  # Phase 24 smoke ROM: LEAVE/+LOOP
make forth-smoke-p25  # Phase 25 smoke ROM: ABS/SGN/MOD/SQRT/RND/RANDOMIZE
make forth-smoke-p26  # Phase 26 smoke ROM: ARRAY/CELLS
make forth-smoke-p27  # Phase 27 smoke ROM: string handling
make forth-smoke-p28  # Phase 28 smoke ROM: ACCEPT/INPUT
make forth-smoke-p29  # Phase 29 smoke ROM: FSQRT
make forth-smoke-p30  # Phase 30 smoke ROM: PI/SIN/COS
make forth-smoke-p31  # Phase 31 smoke ROM: real BEEP
make forth-smoke-p32  # Phase 32 smoke ROM: SOUND
make forth-smoke-p33  # Phase 33 smoke ROM: real multi-row word wrap
make forth-smoke-p34  # Phase 34 smoke ROM: S>F/F>S
make forth-smoke-p35  # Phase 35 smoke ROM: FROUND
make forth-smoke-p36  # Phase 36 smoke ROM: CLS/C@/C!/KEY?
make forth-smoke-p37  # Phase 37 smoke ROM: STICK
make forth-smoke-p38  # Phase 38 smoke ROM: runtime stack-error detection
make forth-smoke-p40  # Phase 40 smoke ROM: string functions
make forth-smoke-p41  # Phase 41 smoke ROM: EXECUTE
make forth-smoke-p42  # Phase 42 smoke ROM: RAD/DEG
make forth-smoke-p43  # Phase 43 smoke ROM: FREE
make forth-smoke-p44  # Phase 44 smoke ROM: dictionary-ceiling reclaim
make forth-smoke-p45  # Phase 45 smoke ROM: THROW/CATCH
make forth-smoke-p46  # Phase 46 smoke ROM: ROT/2DUP/2DROP/?DUP/PICK, AND/OR/XOR/INVERT, CR/SPACE/SPACES, '
make forth-smoke-p47  # Phase 47 smoke ROM: LPRINT/LLIST
make forth-smoke-p48  # Phase 48 smoke ROM: ULAPLUS/PALETTE (visual)
make forth-boot       # the real, live, bootable product ROM
make graphics-exrom       # Phase 65: the EXROM chunk-5 payload (RECT/
                          # POLYGON/POLYGON-FILL/SPRITE-DEFINE/SHOW/HIDE),
                          # a standalone 8K image at build/graphics_exrom.bin
make test-exrom-isolation # Phase 65 smoke ROM: chunk-5 paging proof
make test-rect            # Phase 65 smoke ROM: RECT
make test-polygon         # Phase 65 smoke ROM: POLYGON (outline)
make test-sprite          # Phase 65 smoke ROM: SPRITE-DEFINE/SHOW/HIDE
make test-poly-fill       # Phase 65 smoke ROM: POLYGON-FILL
make check            # static asm checks over core/, kernel/, and rom/
make product          # just the two ROMs people run: forth-boot + forth-demo-blackjack
make cart             # the same two as DOCK cartridges -> build/*.dck (+ raw *_cart.bin)
make docs             # tutorial + README as PDF (and the tutorial as DOCX) -> build/docs/
make dist             # everything above zipped for download -> dist/2068-Forth-<version>.zip
```

`make docs`/`make dist` additionally need pandoc and the Python packages
in `tools/requirements-docs.txt` (`pip install -r tools/requirements-docs.txt`)
— see `tools/build_docs.sh`'s header for the system libraries WeasyPrint
wants. The GitHub Actions workflow runs `make dist` on every push (see
"Download" above); to cut a numbered release, push a tag:
`git tag v1.0 && git push origin v1.0`.

## Layout

```
core/       language-layer code, not hardware-facing:
              dict.asm    (Phase 2 — dictionary header format, data stack)
              interp.asm  (Phase 3 — outer interpreter, colon compiler)
              control.asm (Phase 4 — IF/ELSE/THEN, BEGIN/UNTIL)
              ts2068.asm  (Phase 5 — PLOT/LINE/CIRCLE/BORDER)
              editor.asm  (Phase 6 — line editing)
              storage.asm (Phase 7 — SAVE-LIB/LOAD-LIB)
              float.asm   (Phase 8 stretch — F+/F-)
              mode64.asm  (Phase 8 stretch — 64COL/32COL/PALETTE64/PLOT64)
              print.asm   (Phase 10 — EMIT/.)
              compare.asm (Phase 11 — =/</>)
              variable.asm (Phase 12 — VARIABLE/CONSTANT)
              dotquote.asm (Phase 13 — .")
              loop.asm    (Phase 14 — WHILE/REPEAT)
              color.asm   (Phase 15 — INK/PAPER)
              doloop.asm  (Phase 16 — DO/LOOP/I; Phase 24 — LEAVE/+LOOP)
              moregfx.asm (Phase 17 — FILL/AT-XY)
              floatmul.asm (Phase 18 — F*)
              floatdiv.asm (Phase 19 — F/)
              key.asm     (Phase 20 — KEY)
              floatprint.asm (Phase 22 — F.)
              decimal.asm (Phase 23 — decimal literals)
              mathfn.asm  (Phase 25 — ABS/SGN/MOD/SQRT/RND/RANDOMIZE)
              array.asm   (Phase 26 — ARRAY/CELLS)
              string.asm  (Phase 27 — S"/TYPE/STRING/PLACE/COUNT/LEN/VAL)
              input.asm   (Phase 28 — ACCEPT/INPUT)
              floatsqrt.asm (Phase 29 — FSQRT)
              floattrig.asm (Phase 30 — PI/SIN/COS)
              rawbeep.asm (Phase 5's original raw-units BEEP, kept for
                          rom/forth_smoke_p5.asm's own history)
              beep.asm    (Phase 31 — real, semitone/seconds BEEP)
              sound.asm   (Phase 32 — real, register-level SOUND)
              rectfill.asm (Phase 65 — RECT, EXROM chunk 5; also owns
                          the shared EXROM_CALL_SLOT trampoline)
              polygon.asm (Phase 65 — POLYGON/POLYGON-FILL, EXROM chunk 5)
              sprite.asm  (Phase 65 — SPRITE-DEFINE/SHOW/HIDE, EXROM chunk 5)
kernel/     hardware-facing modules: inherited from 2068-Leap (memory,
            io, graphics, interrupt, math, sound, storage, bank) plus
            2068-Leap-Forth's own addition, mode64/ (recovered, once-shipped
            2068-Leap code — see that module's own header). bank/bank.asm
            is 2068-Leap's own EXROM paging trampoline, retargeted from
            its original chunk 6 to chunk 5 in Phase 65 — see that file's
            own header for the chunk-by-chunk audit behind the choice.
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
              forth_smoke_p13.asm Phase 13 smoke ROM (.")
              forth_smoke_p14.asm Phase 14 smoke ROM (WHILE/REPEAT)
              forth_smoke_p15.asm Phase 15 smoke ROM (INK/PAPER)
              forth_smoke_p16.asm Phase 16 smoke ROM (DO/LOOP/I)
              forth_smoke_p17.asm Phase 17 smoke ROM (FILL/AT-XY)
              forth_smoke_p18.asm Phase 18 smoke ROM (F*)
              forth_smoke_p19.asm Phase 19 smoke ROM (F/)
              forth_smoke_p20.asm Phase 20 smoke ROM (KEY)
              forth_smoke_p21.asm Phase 21 smoke ROM (error feedback)
              forth_smoke_p22.asm Phase 22 smoke ROM (F.)
              forth_smoke_p23.asm Phase 23 smoke ROM (decimal literals)
              forth_smoke_p24.asm Phase 24 smoke ROM (LEAVE/+LOOP)
              forth_smoke_p25.asm Phase 25 smoke ROM (ABS/SGN/MOD/SQRT/RND/RANDOMIZE)
              forth_smoke_p26.asm Phase 26 smoke ROM (ARRAY/CELLS)
              forth_smoke_p27.asm Phase 27 smoke ROM (string handling)
              forth_smoke_p28.asm Phase 28 smoke ROM (ACCEPT/INPUT)
              forth_smoke_p29.asm Phase 29 smoke ROM (FSQRT)
              forth_smoke_p30.asm Phase 30 smoke ROM (PI/SIN/COS)
              forth_smoke_p31.asm Phase 31 smoke ROM (real BEEP)
              forth_smoke_p32.asm Phase 32 smoke ROM (SOUND)
              forth_smoke_p33.asm Phase 33 smoke ROM (multi-row word wrap)
              forth_smoke_p34.asm Phase 34 smoke ROM (S>F/F>S)
              forth_smoke_p35.asm Phase 35 smoke ROM (FROUND)
              forth_smoke_p36.asm Phase 36 smoke ROM (CLS/C@/C!/KEY?)
              forth_smoke_p37.asm Phase 37 smoke ROM (STICK)
              forth_smoke_p38.asm Phase 38 smoke ROM (runtime stack-error detection)
              forth_smoke_p40.asm Phase 40 smoke ROM (string functions)
              forth_smoke_p41.asm Phase 41 smoke ROM (EXECUTE)
              forth_smoke_p42.asm Phase 42 smoke ROM (RAD/DEG)
              forth_smoke_p43.asm Phase 43 smoke ROM (FREE)
              forth_smoke_p44.asm Phase 44 smoke ROM (dictionary-ceiling reclaim)
              forth_smoke_p45.asm Phase 45 smoke ROM (THROW/CATCH)
              forth_smoke_p46.asm Phase 46 smoke ROM (ROT/2DUP/2DROP/?DUP/PICK, AND/OR/XOR/INVERT, CR/SPACE/SPACES, ')
              forth_smoke_p47.asm Phase 47 smoke ROM (LPRINT/LLIST)
              forth_smoke_p48.asm Phase 48 smoke ROM (ULAPLUS/PALETTE, visual)
              forth_boot.asm      the real, live, bootable product ROM
              graphics_exrom.asm  Phase 65 — the EXROM chunk-5 payload
                                  itself (ORG $A000, standalone 8K image,
                                  assembled separately from forth_boot.asm)
              test_exrom_isolation.asm  Phase 65 smoke ROM (chunk-5 paging
                                  proof — needs a real $A5-filled EXROM
                                  image, not graphics_exrom.bin)
              test_rect.asm       Phase 65 smoke ROM (RECT)
              test_polygon.asm    Phase 65 smoke ROM (POLYGON outline)
              test_sprite.asm     Phase 65 smoke ROM (SPRITE-DEFINE/SHOW/HIDE)
              test_poly_fill.asm  Phase 65 smoke ROM (POLYGON-FILL)
tools/      build wrapper (sjasmplus_strict.sh) and static/simulated
            Z80 checks (check_asm.py, check_z80_opcodes.py, z80sim/)
docs/       PROJECT_PLAN.md (full design rationale, project/build-
            facing — read this first for "why"), CHANGELOG.md (condensed
            phase-by-phase summary), forth_tutorial.md (learn the Forth
            language itself, user-facing — no assembly or build content;
            forth_tutorial.docx is the same content as a Word doc),
            numeric_model.md (integer-core decision), hardware_notes.md
            (confirmed hardware facts, inherited from 2068-Leap),
            zesarux_setup.md / eightyone_setup.md / ts_pico_setup.md
            (per-emulator/hardware setup, see "Running it" above),
            lros_cartridge.md (experimental DOCK/LROS cartridge stub)
patches/    0001-zesarux-mirror-ts2068-exrom.patch (see
            docs/zesarux_setup.md) — this project's own ZEsarUX fix, not
            to be confused with the sibling ts2068rom project's own,
            unrelated Fuse ULAplus patch
```

## License

MIT — see [LICENSE](LICENSE).
