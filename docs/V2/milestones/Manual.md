# Manual — the V2 user's manual in Leap-C's shape: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-manual` from master `800e979` (PR #17, step Cartridge,
merged). The owner chose, at the start: Leap-C's eight parts (the words split into the language and the machine by
the Leap IDE's groups), and the tutorial folded in as Part 2. The entry shape is the Leap IDE's (its question Q5;
an as-built section is added to the answers in `~/Projects/Leap-IDE/docs/requests/LEAP_FORTH_ANSWERS.md`).

## 1. What was built

- **`docs/manual/`**, eight parts, after `~/2068-Leap-C/docs/manual` and the Leap V2 manual:

  | Part | Lines | What |
  |---|---:|---|
  | 1 Introduction | 126 | what it is, starting it, how to read the manual, if you know Forth |
  | 2 Beginner's guide | 1,537 | 17 chapters, from the tutorial |
  | 3 Words of the language | 3,138 | 132 entries: stack, arithmetic, float, memory, strings, control, dictionary, errors |
  | 4 Words of the machine | 1,410 | 52 entries: I/O, graphics, sound, storage, printer |
  | 5 Concepts | 346 | 21 concepts, A to Z |
  | 6 Libraries and cartridges | 110 | `SAVE-LIB`/`LOAD-LIB`, and the cartridge guide's user sections |
  | 7 Practical examples | 383 | 15 complete programs |
  | 8 Appendices | 187 | messages and codes, characters and keys, limits, memory map, hardware notes, word index, how it was checked |

- **One entry per ROM word** (184), in the IDE's shape: `## NAME`, then `` `( effect )` -- **kind**, group ``, a first
  paragraph, a first ```forth example, then Notes, Errors and See also where they say something.
- **Every ```forth block is a test.** `tools/docexamples.py` (Leap-C's, for Forth) writes each block to
  `tests/doc/manual_<part>_NN.fs`, which the forth suite types into a just-booted ROM; `make check` fails if they are
  out of step with the manual. Text not to be typed (tape commands, a screen) is a ```text block.
- **`tools/manualcheck.py`** (in `make check`) walks the dictionary chain in the built HOME image and checks Parts 3
  and 4 against it: each word one entry and no other, ASCII order, the shape, the group's part, the Summary table,
  and the kind as the ROM has it (IMMEDIATE bit, `call COMPILE_ONLY_CHECK`, a call or jump to the EXROM, a call to
  the header builder).
- **The Word edition**: `tools/build_manual_docx.py` (Leap-C's builder, ported; `make manual`) writes
  `docs/2068_Leap-Forth_Users_Manual.docx`; `tools/build_docs.sh` renders the manual as one PDF; the download bundle
  carries the manual, its PDF and Word editions and the emulator guides.
- **Gone:** `docs/forth_tutorial.md` and its `.docx` and converter (Part 2), `docs/cartridge.md` (Part 6;
  its build and test sections are CONTRIBUTING.md's "The cartridge build"), `docs/numeric_model.md` (Part 5; it put
  the float stack at `$9000`), `docs/hardware_notes.md` (Appendices B and E; it said BREAK was not implemented),
  `tests/doc/tutorial_words.fs`. The README and CONTRIBUTING point at the manual; CONTRIBUTING gains the rule that a
  word's change comes with its entry.

## 2. Defects found while writing it, and fixed

Each with a test that fails on master `800e979` (checked on a worktree build):

| Defect | Fix | Test |
|---|---|---|
| `RECT` `FILL` `CIRCLE` `POLYGON` `POLYGON-FILL` and the sprite words printed nothing with another EXROM; the README and the setup guides said `NO EXROM`, as `EDIT` printed | `EXROM_CALL_SLOT`'s mismatch prints it (`EXROM_NONE_MSG`); +3 B HOME | `tests/graphics/exrom_none.fs` |
| A word that took more than the data stack held wrote past its top before the check after it: `SWAP`, `ROT` in place, `.` the digits it pushes. The top was the dictionary's first byte, so with a word of one's own defined every ROM word after it was lost (`HERE ?`) | a 256-byte guard: `DSTACK_TOP` `$9000`, the data stack 896 cells (was 1,024); the dictionary stays at `$9100` | `tests/core/underflow.fs` |
| The `g`, `p` and `q` glyphs sat a row high (`p` read as `P`), handed over from Leap-C (its D24; #18) | the bytes, 0 B | `tests/io/font.fs` |
| `RECT` took its corners' low bytes (300 drew at 44) and did not check y (a corner below 191 wrote past the bitmap); its header said off-screen drew nothing | it clips as `LINE` and `CIRCLE` do: 16-bit cells, `RECT_CLIP_AXIS` in the EXROM; +55 B EXROM | `tests/graphics/rect.fs` |
| `SPRITE-DEFINE` and `SPRITE-SHOW` took low bytes and did not check that the 2x2 cells were on the screen | refused: a value above 255, row above 22, col above 30; +17 B EXROM, -1 B HOME | `tests/graphics/sprite_range.fs` |

Documents found wrong: `core/string.asm`'s header (it said the BASIC-style string words were missing; fixed); the
tutorial (an unknown word "prints a simple `?`"; `'` inside definitions where `[']` is meant; `0 STARS` "near-
infinite" where it runs 65,536 times; `IF` and `DO` called immediate where they are compile-only), gone with it.

Behaviour documented, not changed: `EXECUTE` does not check its token; `DO` with start equal to limit runs 65,536
times (there is no `?DO`); `INPUT` returns `VAL` of the line, so a number past 65,535 wraps; `]` at the prompt starts
compiling; in-place words (`SWAP`, `DUP`) report nothing on an empty stack (the guard keeps the dictionary safe).

## 3. Tests

- `make check` passes: `docexamples` (314 examples in step), `manualcheck` (184 words agree).
- `make test`: boot 14/14, forth 361/361 (before Part 7's 15, which pass on their own), editor 30/30, float 66/66,
  shape 48/48, bench 6/6, poweron 7/7, cart 12/12 (480 s for these); tape 19/19 (+1 extra; 368 s, on this branch's
  tip). `make repro`: 16 files identical.
- The manual's examples alone: 314 cases (`python3 tools/forthtest.py manual_`), every one passing.
- The forth suite's limit, found here: a typed line longer than 32 characters wraps the input area, and forthtest
  then misreads that line's output (the screen itself is right). The manual's lines are kept under 31 characters.

## 4. Sizes

| Image | Before (`800e979`) | After |
|---|---:|---:|
| HOME free | 1,938 B | 1,936 B (+3 `NO EXROM`, -1 sprite staging) |
| EXROM free | 3,208 B | 3,136 B (+55 `RECT` clipping, +17 sprite checks) |
| The cartridge's HOME image free | 1,744 B | 1,741 B |
| Dictionary at power-on | 16,128 B | 16,128 B |
| Data stack | 1,024 cells | 896 cells (the guard) |

Ledger entries in `budget.toml` for each. `ROM_IDENTITY` changes, so LIB tapes saved by `800e979` do not load;
`SAVE-TEXT` source does.

## 5. Verification limits

Emulators only: the examples run on ZEsarUX 13.0; the tape words' tape behaviour is the tape suite's (ZEsarUX and Fuse
1.9.1), not the manual's (its tape commands are ```text blocks, and the forth suite checks only what they do with no
tape: BREAK, `TAPE ERROR`); the cartridge on ZEsarUX and TSRun. `LPRINT`, `ULAPLUS`, `PALETTE`, `BORDER` and `STICK`
run in the examples but their output is not read back (no printer, ULAplus ports not readable, no joystick). Nothing
was checked on a TS2068.
