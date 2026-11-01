# Leap-Forth -- User Manual and Language Reference

**For the Timex Sinclair 2068 with the Leap-Forth ROMs.**

*Edition for V2.0.* This manual describes the ROM whose status bar reads `2068 FORTH V2.0`. It has been tested on
ZEsarUX 13.0 (with a small patch), Fuse 1.9.1 and TSRun, and it has **not been run on a physical TS2068**. Where
something depends on real hardware, the manual says so.

---

## Contents

| Part | What it is for |
|---|---|
| [Part 1, Introduction](01_introduction.md) | what Leap-Forth is, how to start it, how this manual works |
| [Part 2, Beginner's guide](02_beginners_guide.md) | a step-by-step course for someone who has never used Forth: the stack, your own words, numbers and decimals, memory, decisions, loops, text, the screen, graphics, sound, the keyboard, tapes, errors |
| [Part 3, Words of the language](03_language.md) | every word of the language, with examples: the stack, arithmetic, decimals, memory, strings, control, the dictionary, errors |
| [Part 4, Words of the machine](04_machine.md) | every word that works the machine, with examples: printing and the keyboard, colour and graphics, sound, the tape, the printer |
| [Part 5, Concepts](05_concepts.md) | the ideas behind the system, A to Z: BREAK, the dictionary, the editor, errors, floating point, memory, numbers, the stacks, strings, tapes ... |
| [Part 6, Libraries and cartridges](06_libraries.md) | saving your words as a library, loading it again, and making a program into a cartridge |
| [Part 7, Practical examples](07_examples.md) | complete programs to type in and change |
| [Appendices](08_appendices.md) | messages and error codes, the character set and keys, limits, the memory map, hardware notes, an index of the words, how this manual was checked |

The manual follows the plan of the Leap-C and Leap V2 manuals, and of the *Sinclair QL User Guide* before them: a
gentle beginner's guide, then the reference, then the tables at the back.

## What Leap-Forth is

The Timex Sinclair 2068 normally starts in the BASIC of its ROM. **Leap-Forth** replaces that ROM with a new one. You
switch on and find a Forth prompt. You type a line, press ENTER, and it runs at once; or you define new words, and the
machine compiles them to Z80 machine code as you type them. No PC is needed.

Its main features:

* **Forth**, with 16-bit numbers, a data stack and a dictionary you add to, and the words a Forth programmer expects:
  `: ;`, `IF ELSE THEN`, `DO LOOP`, `BEGIN WHILE REPEAT`, `VARIABLE`, `CONSTANT`, `CREATE DOES>`, `CATCH THROW`;
* **decimals** (floating point) in the Sinclair 5-byte format, on a stack of their own, with `SIN`, `COS`, `TAN`,
  square roots and printing to a chosen number of places;
* **strings** with the BASIC words a 2068 owner knows: `LEN`, `VAL`, `STR`, `CHR`, `CODE`, `LEFT`, `RIGHT`;
* the **screen**: colours, plotting, lines, circles, filled shapes and polygons, user-defined characters, sprites,
  the 2068's high-colour mode and ULAplus;
* the **AY sound chip**: `BEEP` in semitones, and the chip's registers for anything else;
* a **full-screen editor** (`EDIT`) for the words you have typed, kept in a store of source lines;
* **cassette tape**: your source text (`SAVE-TEXT`) or your compiled words as a library (`SAVE-LIB`), and a way to
  make a program into a **cartridge** that runs on a TS2068 with its own ROMs;
* **errors with messages**, not crashes: a stack that runs dry, a division by zero or a number out of range stops the
  line with a message, and BREAK stops any running word.

It runs on an ordinary 48 KB TS2068, unexpanded. There is room for 16,128 bytes of words you define and 8,192 bytes of
source text. The exact limits are in [Appendix C](08_appendices.md#appendix-c-limits).

Leap-Forth is built on the platform of 2068-Leap V2 and 2068-Leap-C, a BASIC and a C for the same machine. It is a
different language. The three do not share programs or tapes.

## The status of this release

V2.0 is tested by automated suites on emulators: ZEsarUX 13.0 (with a patch), Fuse 1.9.1 for the tape, and TSRun for
the cartridge. It has **not been run on a physical TS2068**, a real cassette recorder or a real keyboard.

Every example in this manual is an automated test. The build types it into the ROM and checks that it prints what its
comments say (see [Appendix G](08_appendices.md#appendix-g-how-this-manual-was-checked)).

## Starting it

**In a web browser.** The quickest way: open <https://nchiker.github.io/TSRun/?rom=leapforth>. You get the TS2068 with
Leap-Forth, with nothing to install.

**On an emulator.** Download `2068-Forth-latest.zip` from the
[releases page](https://github.com/nchiker/2068-Leap-Forth/releases). Its `roms/` folder holds:

| File | What it is | Used by |
|---|---|---|
| `forth_boot_rom0.bin` | the HOME ROM, 16,384 bytes | Fuse: ROM 0; TSRun: ROM0; EightyOne, TS-Pico |
| `graphics_exrom.bin` | the EXROM (extension ROM), 8,192 bytes | Fuse: ROM 1; TSRun: ROM1 |
| `forth_zesarux.bin` | the two in one file, 24,576 bytes | ZEsarUX: `--romfile` |
| `graphics_exrom.dck` | the EXROM as a cartridge | EightyOne |
| `forth_cart.dck` | Forth as a cartridge for a TS2068 with its own ROMs | ZEsarUX, TSRun (see [Part 6](06_libraries.md)) |

For Linux and Fuse the command is:

```text
fuse --machine ts2068 --rom-ts2068-0 /path/to/roms/forth_boot_rom0.bin --rom-ts2068-1 /path/to/roms/graphics_exrom.bin
```

Use full paths to the ROM files. The guides for [ZEsarUX](../zesarux_setup.md), [EightyOne](../eightyone_setup.md)
and [TS-Pico](../ts_pico_setup.md) give their commands and limits. ZEsarUX needs a small patch for the EXROM, and
EightyOne and TS-Pico cannot run it yet. Without the EXROM, the words it does (`EDIT`, `FILL`, `CIRCLE`, `RECT`,
`POLYGON`, `POLYGON-FILL` and the sprites) print `NO EXROM` and everything else works.

**On a TS2068.** The HOME ROM replaces the 16 KB system ROM and the EXROM the 8 KB extension ROM; or, leaving the
machine's ROMs in place, `forth_cart.dck` runs from a dock cartridge. Neither has been tried on real hardware.

Switch on. The screen turns white with `2068 FORTH V2.0` on a black bar at the bottom, a chord sounds, and the cursor
waits on that bar.

**The keyboard.** The TS2068 has two shift keys: CAPS SHIFT (capitals and the editing keys) and SYMBOL SHIFT
(punctuation). On a PC, **Shift** is CAPS SHIFT and **Ctrl** is SYMBOL SHIFT. Forth needs punctuation; the keys are in
[Appendix B](08_appendices.md#appendix-b-the-character-set-and-keys).

## How to read this manual

* **Type the examples.** They are small. Change numbers and words and see what happens.
* In the text, `FORTH WORDS AND WHAT YOU TYPE` are in a typewriter face. Forth does not care about case: `dup` is
  `DUP`. The manual writes words in capitals, as the ROM lists them.
* A box of Forth is **lines you type** at the prompt, one at a time, each followed by ENTER. A line's `\ expect:`
  comment shows what it prints: Forth prints that, then `OK`. A line with no `\ expect:` prints only `OK`. The
  comments are part of Forth (it skips the rest of a line after `\`), so you can type a line with or without them.
  Each box starts on a machine just switched on.
* A box without a title in a plain frame shows something to read, not to type: a screen, or the shape of a command.
* Words in *italics* in a stack effect are things you supply. Part 3 says [how to read an
  entry](03_language.md#how-to-read-an-entry).
* The reference parts are in order: Parts 3 and 4 in the order of the ASCII codes of the words' names (`!` before `+`
  before `A`), Part 5 alphabetically. [Appendix F](08_appendices.md#appendix-f-word-index) lists every word by group.

## If you know Forth

Leap-Forth is a 16-bit Forth that follows Forth-2012 where it can, for a 1983 home computer with 48 KB of RAM. A cell
is 16 bits, and true is -1. It uses subroutine threading: a definition compiles to Z80 `CALL`s, and the Z80's stack is
the return stack. Names are not case-sensitive, and a definition can call itself by its own name. Numbers are decimal
only (there is no `BASE`, `HEX` or `$FF`), and a number with a `.` or an exponent is a decimal fraction on the float
stack (`3.5`, `1E3`), not a double cell. `/` and `MOD` round toward zero. There are no double-cell words, no return
stack words (`>R`, `R>`), and no `POSTPONE`, `?DO`, `.S` or `WORDS` (`VLIST` lists the words). `."` and the control
words are compile-only. Every word is described in Parts 3 and 4; the full list of differences is the concept
[Differences from standard Forth](05_concepts.md#differences-from-standard-forth).

If you have never used Forth, begin with [Part 2](02_beginners_guide.md).
