# Part 6 -- Libraries and cartridges

Forth keeps your work in two forms, and the tape takes either:

| | Source text | A library |
|---|---|---|
| what it is | the lines you typed, as text: the line store | your compiled words: the dictionary, as it is in memory |
| saved by | `SAVE-TEXT name` | `SAVE-LIB name` |
| loaded by | `LOAD-TEXT name`, which types the lines again | `LOAD-LIB name`, which puts the words back at once |
| loads into | any Leap-Forth ROM | **only the ROM that saved it** |
| you can | read it, change it with `EDIT`, load it after other words | run it at once; make a cartridge of it |

Source text is the portable form; keep it for everything you write. A library is the quick form: no compiling when it
loads, and it is what a [cartridge](#program-cartridges) is made from. This part is about libraries and cartridges; the
text words are in [Part 4](04_machine.md) and the concept [Tapes](05_concepts.md#tapes).

## Saving a library

`SAVE-LIB name` saves every word you have defined: the dictionary from its start up to `HERE`, with the values your
variables hold at that moment. Start the tape recorder (or the emulator's tape) before pressing ENTER. Forth sends a
header and the data, with a checksum, and returns to `OK`. SPACE stops it (`BREAK`).

```text
: SQUARE  DUP * ;
VARIABLE HIGH  0 HIGH !
SAVE-LIB SQUARES
VERIFY-LIB SQUARES
```

`VERIFY-LIB name` plays the tape back and compares it with the dictionary, changing nothing. Do it before you rely on a
tape.

A library does not hold the line store (save that with `SAVE-TEXT`), the user-defined characters (see `UDG`), the
screen, or anything on the stacks.

## Loading a library

`LOAD-LIB name` searches the tape for a library of that name, skipping anything else, and loads it in place of the
words you have defined: every word of yours is gone, and the library's words are there. `LOAD-LIB` with no name takes
the first library on the tape. Type it at the prompt: called from inside a word of your own, it would load over the
word that is running.

A library is compiled code that calls the ROM by address, so **it loads only into the ROM that saved it**. Every
library carries the identity of its ROM (a checksum of the whole ROM), and `LOAD-LIB` refuses one from another build
before reading any of it: `TAPE ERROR`. A new release of the ROM cannot load the old release's libraries; load their
source text and save them again. The cartridge (below) carries the release's identity, so the two share libraries.

## Errors

| What happened | What you see |
|---|---|
| SPACE pressed during a save, load or verify | `BREAK` |
| the tape could not be read, its checksum is wrong, it is from another ROM, or (verifying) it differs | `TAPE ERROR` |
| `SAVE-LIB`: the dictionary is too full to add the 2-byte checksum | `DICTIONARY FULL` |

A load that fails before writing anything leaves your words as they were. A load that fails part-way (a damaged
tape, a wrong checksum) has already overwritten them, so it leaves an empty dictionary, as at switch-on. All three are
errors a program can catch with `CATCH` (codes -28, -37 and -8; see
[Appendix A](08_appendices.md#appendix-a-messages-and-error-codes)).

## Program cartridges

A cartridge runs on a TS2068 with **its own ROMs**: nothing is replaced. It holds the Forth ROMs and, if you give it
one, a program: a library saved with `SAVE-LIB`. At switch-on the machine finds the cartridge, Forth starts, copies the
program into memory and runs its **start word**, as if you had typed its name. When the word ends you get the `OK`
prompt with the program's words still there.

Everything here was checked on emulators only: ZEsarUX 13.0 and TSRun, both with the stock TS2068 ROM. Fuse, EightyOne
and real cartridge hardware have not been tried.

### Making one

You need the Leap-Forth source (a checkout of the repository, with Python 3) to pack the cartridge.

1. Write and test the program on the release ROMs, as usual. Give it a start word: the word that runs the program
   (for example `: PLAY ... ;`).
2. Save it with `SAVE-LIB name` onto a tape file in the emulator: a `.tap`, or a `.tzx` saved at standard speed. A
   cartridge also runs `SAVE-LIB`, so you can save from either.
3. Build:

   ```text
   make cart PROG=play.tap START=PLAY
   ```

   This writes `build/cart/program.dck` (for emulators) and `build/cart/program.bin` (the whole 64 KB cartridge as one
   file, for a cartridge board). `tools/forthcart.py` does the packing and can be run on its own
   (`python3 tools/forthcart.py --help`).
4. Insert the `.dck` as a dock cartridge and switch on: ZEsarUX with its stock ROM (`--machine TS2068 --romfile
   ts2068.rom`, then *smartload* the `.dck`), or TSRun's dock slot.

The packer refuses a tape saved by a different ROM build, a damaged tape, a start word that is not among the
program's words, and a dictionary larger than the cartridge can copy (16,128 bytes).

**User-defined characters.** A library does not hold the UDG table. Define a program's characters in its start word,
or give the packer the 168 bytes of the table (from `0 UDG` on) with `UDG=file`.

### At switch-on

* The TS2068's own ROM takes about 2 seconds to find the cartridge.
* Forth starts, then checks the program and copies it: under half a second, whatever the program's size. The version
  stays on the status bar meanwhile.
* The screen is cleared and the start word runs. Its output, an error or `BREAK` look exactly as when you type a
  line, and the prompt follows. The start word's name is in the line store, so `EDIT` shows it and you can type it
  again to run the program again.
* `EDIT`, `FILL`, `CIRCLE`, the tape words and everything else work as on the release ROMs. Reset the machine to
  start the program afresh.

With no program in it (`forth_cart.dck`, in the release's `roms/` folder) the cartridge gives you Forth itself: the
version, the chime and the prompt. If the program fails its check (it was saved by a different ROM build, or its
length or start word is wrong), the cartridge prints `BAD PROGRAM` and gives you Forth with no words of your own. The
packer has already checked the program's own checksum, so the cartridge does not check it again at switch-on (as
Leap V2's cartridges do not).
