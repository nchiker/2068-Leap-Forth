# Forth programs as cartridges

`make cart` builds Leap-Forth as a DOCK cartridge for a **stock** TS2068: the stock HOME ROM and EXROM stay in the
machine and nothing is replaced. The cartridge holds the Forth HOME ROM, the Forth EXROM and, if you give it one, a
program. At power-on the stock ROM starts the cartridge, Forth copies the program into RAM and runs its start word
as if you had typed the word's name at the prompt. When the word returns, you get the `OK` prompt with the program's
words still defined, as on the release ROMs.

Everything here was checked on emulators only: ZEsarUX 13.0 and TSRun's core, both with the stock TS2068 ROM. Fuse
and real cartridge hardware have not been tried.

## Making a program cartridge

1. Write and test the program on the release ROMs, as usual. Give it a **start word**: the word that runs the program
   (for example `: PLAY ... ;`).
2. Save the compiled program with `SAVE-LIB name`, onto a tape file in the emulator (a `.tap`, or a `.tzx` saved at
   standard speed). A cartridge build also runs `SAVE-LIB`, and it accepts the release's LIB tapes.
3. Build:

   ```sh
   make cart PROG=play.tap START=PLAY
   ```

   This writes `build/cart/program.dck` (for emulators) and `build/cart/program.bin` (the whole 64 KB cartridge as
   one file, chunks in address order, `$FF` where the cartridge has nothing). `tools/forthcart.py` does the packing
   and can be run on its own (`python3 tools/forthcart.py --help`).
4. Insert the `.dck` as a dock cartridge and switch on: ZEsarUX with its stock ROM
   (`--machine TS2068 --romfile ts2068.rom`, then *smartload* the `.dck`), or TSRun's dock slot. Fuse's and
   EightyOne's dock options have not been tried.

The packer refuses a tape that was saved by a different ROM build, a damaged tape, a start word that is not among the
program's words, and a dictionary larger than the cartridge can copy (16,128 bytes, `$9100-$CFFF`).

**User-defined graphics.** `SAVE-LIB` does not save the UDG table. Define a program's UDGs in its start word, or pass
the 168 bytes of the table (`0 UDG` onward) with `UDG=file`.

## At power-on

- The stock ROM takes about 2 seconds to find the cartridge (103 frames on both emulators).
- Forth starts cold, then checks the program and copies it. That takes about 0.3 seconds plus 0.15 seconds per
  1,000 bytes of dictionary (measured: 1.13M T-states for a 42-byte program, 9.55M T-states, 2.7 s, for the largest).
  The version stays on the status bar while it does this.
- The screen is cleared and the start word runs. Its output, an error or `BREAK` look exactly like a typed line's,
  and the prompt follows. The start word's name is in the line store, so `EDIT` shows it and you can run it again.
- `EDIT`, `FILL`, `CIRCLE`, the tape words and everything else work as on the release ROMs. Reset the machine to
  restart the program.

With no program in the cartridge (`build/cart/forth_cart.dck`, which `make cart` always builds), you get Forth
itself: the version on the status bar, the chime and the prompt. If the program fails a check (a different ROM build,
a damaged image), the cartridge prints `BAD PROGRAM` and gives you Forth with an empty dictionary.

## How it is built

The cartridge's HOME image is the release source assembled with `-DCARTRIDGE`. Every label keeps its release address
(`tools/cart_check.py`, run by `make cart` and `make check`), so a dictionary compiled on the release ROMs calls the
same routines here. The cartridge also carries the release's `ROM_IDENTITY`, which is why LIB tapes work on both. The
EXROM is the release's, byte for byte.

| Chunk | Address | In the cartridge | What the CPU sees |
|---|---|---|---|
| 0-1 | `$0000-$3FFF` | the Forth HOME ROM; an LROS header at `$0000` | the cartridge, always |
| 2-3 | `$4000-$7FFF` | the program image (if any) | HOME RAM; the cartridge only while the program is copied, interrupts off |
| 4 | `$8000-$9FFF` | nothing | HOME RAM: cells, stacks, dictionary |
| 5 | `$A000-$BFFF` | the Forth EXROM | HOME RAM; the cartridge while an EXROM word runs |
| 6-7 | `$C000-$FFFF` | nothing | HOME RAM |

Port `$F4` holds `$03` (chunks 0-1 from the cartridge), `$23` while an EXROM word runs, and `$0F` while the program is
copied. Port `$FF` bit 7 stays 0 (the cartridge, never the stock EXROM). The program image, the hand-off from the stock
ROM and the paging are described in `kernel/bank/cart.asm`.

The cartridge's own code (194 bytes) goes in the release image's free space, and `cart_check.py` keeps it within the
HOME reserve floor in `budget.toml`. So the cartridge always fits as long as the release keeps its floor.

## Tests

`make test` runs the cartridge suite (`tools/carttest.py`). It covers:

- Forth with no program.
- A program's output, an error and `BREAK` in the start word.
- The UDG table, the largest dictionary, and four kinds of bad image.
- A second emulator (TSRun, `tools/cartrun.mjs`) checks the stock ROM's hand-off, including an interrupt forced before
  the entry's `di`. It also checks that the paging never leaves the cartridge's chunks, and that the screen at the
  prompt matches ZEsarUX's byte for byte.

`make test-cart` runs the boot, Forth, editor, float and shape suites on the cartridge in the stock ROM's DOCK.
