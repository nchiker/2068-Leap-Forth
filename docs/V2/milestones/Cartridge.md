# Cartridge — Forth and a Forth program as a DOCK cartridge for a stock TS2068: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-cartridge` from master `c45281f` (PR #16, step IDE hooks,
merged). The design is the Leap IDE's question Q7 and its answer (`~/Projects/Leap-IDE/docs/requests/
LEAP_FORTH_ANSWERS.md`, with an as-built section added there). The owner chose what happens when the start word
returns: the `OK` prompt (2026-11-01).

## 1. What was built

- **`make cart`** assembles the HOME source with `-DCARTRIDGE` into `build/cart/`, copies the release EXROM, runs
  `tools/cart_check.py --patch`, and writes `forth_cart.dck` (Forth with no program). `make cart PROG=<SAVE-LIB tape>
  START=<word> [UDG=<file>]` also writes `program.dck` and `program.bin` (64 KB flat). **The release images are
  byte-identical** to master's (SHA-256 of all four compared).
- **The cartridge image** (`kernel/bank/cart.asm`, and the flag in `rom/forth_boot.asm` and `kernel/bank/bank.asm`):
  - An LROS header in `RST_00`'s five bytes: `00 01 <CART_ENTRY> DC`, with chunks 0, 1 and 5 marked used.
  - `CART_ENTRY`: `di`, HSR `$03`, then `jp COLD_START`.
  - The EXROM paging inside the release routines' 27 and 16 bytes. Page-in sets HSR `$23`, page-out `$03`, and
    port `$FF` is never written, so bit 7 stays 0 (DOCK).
  - `CART_START_PROGRAM` replaces COLD_START's chime call. It maps DOCK chunks 2-3 with interrupts off, then checks
    the image: magic `"F1"`, `ROM_IDENTITY`, the length (at most 16,128), the start word's length, the CRC-16. It
    copies the UDGs and the dictionary, sets `HERE` and `LATEST`, and puts the start word's name in `EDIT_BUF`. Then
    it writes the AY registers as the chime leaves them, without the sound, so `SOUND` programs behave as on the
    release. It clears the screen and jumps to `EDITOR_LOOP_LIVE.enter`.
  - No image: the chime and the prompt (Forth itself). A failed check: `BAD PROGRAM`, then the same, with an empty
    dictionary.
- **Every release label keeps its address**, and the cartridge carries the release's `ROM_IDENTITY`. A dictionary
  compiled on the release ROMs runs unchanged, and LIB tapes go both ways. `cart_check.py` (in `make cart` and
  `make check`) checks this, and that the bytes differ only in:
  - the header,
  - the call at `COLD_START.chime` (a new label, 0 B),
  - the two paging routines,
  - `ROM_IDENTITY`,
  - the release's free space.

  It also checks that the cartridge's own code (194 B) is within the HOME reserve floor (200 B), so the cartridge
  fits whenever the release does, and that the EXROM is identical.
- **`tools/forthcart.py`**: the packer and the reference for the IDE. It reads a `.tap`, or the standard blocks of a
  `.tzx`, and checks the identity, CRC and size, and that the start word is one of the program's words (case-blind,
  stored as the dictionary spells it). It writes the `.dck` (DOCK bank, chunks 0-3 and 5, chunk 3 only for an image
  over 8 KB) and the flat `.bin`.
- **The download bundle** carries `roms/forth_cart.dck` and `docs/cartridge.md`. `make repro` covers the cartridge
  (16 files identical across two trees).

## 2. Measured (ZEsarUX 13.0 and TSRun's core, stock ROMs)

| What | Value |
|---|---|
| Stock ROM's hand-off to `CART_ENTRY` | frame 103 on both emulators; interrupts on, IM 1, SP `$61FE`, HSR `$23`, `$FF` `$00` (as Leap's cartridge measured) |
| `CART_ENTRY` to the start word's run, 42-byte dictionary | 1,128,149 T (0.32 s) |
| The same, 16,128-byte dictionary | 9,549,408 T (2.7 s; the CRC, about 400 T a byte, is most of it) |
| HSR values written after the hand-off (TSRun's log of the `hello` cartridge) | `$03`, `$0F` only (that run calls no EXROM word; `$23` is the page-in's, and the tests' CIRCLE on ZEsarUX shows it works) |
| The cartridge's own code | 194 B; the cartridge image has 1,744 B free |

The load costs about 0.15 s per 1,000 bytes of dictionary. A faster CRC (unrolled) would add about 60 B and break the
reserve-floor rule above. A cheaper check (a sum) would catch less. Kept as it is: the time is spent once, at
power-on, while the version shows on the status bar.

## 3. Tests

- **`tools/carttest.py`** (`make test`'s `cart` suite, ports 10920-10939, about 6 s) compiles programs on the release
  ROMs the way the IDE runs lines, packs them, and runs each cartridge in ZEsarUX on the stock ROM (fharness's
  cartridge mode). Cases:
  - `plain`: Forth with no program.
  - `hello`: output, then `42 OK`. `HERE`, `LATEST` and the dictionary match the release's, the start word is in the
    store, ports `$03` and `$00`. The word runs again, and `CIRCLE` runs from DOCK chunk 5 with no restart.
  - `udg`, `error` (-42), `break` (-28).
  - `largest`: 16,128 bytes, to `$D000`.
  - `bad-identity`, `bad-crc`, `bad-length`, `bad-start`.
  - `packer`: the command line on `.tap` and `.tzx` gives the same image, the flat `.bin` is right, and four
    refusals.
  - `tsrun`: `tools/cartrun.mjs` on TSRun's core. Checks the hand-off, an interrupt forced before `CART_ENTRY`'s `di`
    (taken, returns, the program runs), no HSR value leaving chunks 0-1 HOME, no `$FF` bit 7, and the screen at the
    prompt equal to ZEsarUX's byte for byte.
- **Equivalence, `make test-cart`:** the pool suites on the cartridge, with ZEsarUX's stock ROM and the `.dck` in the
  DOCK. Results: boot 14/14, forth 60/60, editor 30/30, float 66/66, shape 48/48 (220 s for the last three). One
  case each in forth and editor needs the HOME ROM without its EXROM; on a cartridge it is reported as not run.
- **On the old build** (master `c45281f`, a worktree): there is no `make cart` target, so `carttest.py` fails with
  "no cartridge build". That only shows the target is new. To show what the checks catch, I ran two mutant
  cartridges:
  - The release's page-out (HSR 0): `hello` fails (CIRCLE dropped the cartridge into the stock ROM, which restarted
    it) and `break` fails.
  - The CRC check skipped: `bad-crc` fails.

  The first mutant passed `hello` on my first version of the test, whose CIRCLE check accepted any pixels. The check
  now requires `OK` on row 0, the circle's edge and the line store intact.

### Results (`make test`, 2026-11-01)

Every suite passes; wall 661 s (`build/test_results.json`: every code 0).

| Suite | Result |
|---|---|
| boot | pass |
| forth | pass |
| editor | 0 failed |
| float | 66/66 |
| shape | 48/48 |
| bench | pass |
| poweron | pass |
| tape | 19/19 |
| cart | 12/12 (new) |

On the cartridge (`make test-cart`): boot 14/14, forth 60/60, editor 30/30, float 66/66, shape 48/48.

`make check` and `make repro` pass.

## 4. Harness changes

- `fharness.Machine` takes `dck=`, or the build's `forth_cart.dck`. It starts ZEsarUX with its stock `ts2068.rom`,
  `smartload`s the cartridge as its reset, and guards every breakpoint with `PEEK(1)=1`. The stock ROM has `$AF`
  there and the cartridge's LROS header `$01`, so a breakpoint never fires in the stock ROM at the same address.
  Snapshots keep the DOCK.
- `run_suites` reports a suite's no-EXROM cases as not run on a cartridge build. Before this, the copied build had no
  `.dck`, the cartridge's HOME image ran as a plain ROM, and the LROS header executed as code. That was found as one
  failed boot per Forth run.

## 5. Sizes

| Image | Before | After |
|---|---:|---:|
| HOME free (release) | 1,938 B | 1,938 B |
| EXROM free (release) | 3,208 B | 3,208 B |
| Cartridge HOME free | — | 1,744 B |

No ledger entry: no release component changed.

## 6. Emulator limits

Everything ran on ZEsarUX 13.0, with the project's EXROM patch, which does not touch DOCK paging, and on TSRun's
core. Both used the stock TS2068 ROM (the same bytes in both). Fuse and EightyOne were not run. No hardware: a real
cartridge's ROM timing and an absent chunk's open bus are not modelled. With no image, the check reads `$4000`; a
present but bad image is caught by the CRC. TS-Pico's DCK slot is not tried (`docs/ts_pico_setup.md`).
