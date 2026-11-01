# Blackjack — the demo rebuilt for the finished ROM, and a cartridge: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-blackjack` from `v2/step-cart-start` (master `800e979` had
not moved: PRs #19 and #20 open, cart-start not pushed). The ROADMAP's step: rebuild the Blackjack demo from its saved
source as a program for the finished ROM and ship it as a cartridge with `make cart PROG=... START=...`.

## 1. What was built

- **`demos/blackjack.fs`**, rebuilt from the V1 text (one 6,091-character line with no line ends) as 154 commented
  lines of at most 61 characters. The rules are the old ones (the dealer draws to 17, a two-card 21 is blackjack, equal
  totals push), and so are the deck's order and the shuffle (card *n* is rank *n* MOD 13 + 1, suit *n* / 13;
  Fisher-Yates from 51 down to 0). Changed:
  - one `DECK` array of card numbers (was two arrays, ranks and suits), and a hand is an `ARRAY` with its count in
    cell 0;
  - the felt's colours are set before `CLS` (the first round cleared to white);
  - a hand of 9 to 11 cards is squeezed into 32 columns (the old 10-entry column table read past its end at the 11th
    card);
  - the player is not asked to hit at 21;
  - the dealer's hidden card turns over before the dealer draws, and each card drawn has its sound;
  - a tally of rounds won, lost and pushed;
  - a title page with the rules;
  - the end puts the colours and the border back;
  - `MIXER` `NOISE` `TONE` `VOLUME` in place of raw `SOUND` writes, and the UDGs from a `CREATE` table.
  The start word `BLACKJACK` defines the UDGs (a library does not hold them), shows the title and does `0 RANDOMIZE`
  after its key. The old test copy's round log at the literal address 62120 is gone: the test reads the stack.
- **`make blackjack`**: `tools/fs2lib.py` types a source file's lines into the release ROMs in ZEsarUX (headless, by
  the Leap IDE's host-line path) and writes the tape `SAVE-LIB` would (`tapes.lib_file`). `make cart
  PROG=build/blackjack.tap START=BLACKJACK OUT=blackjack` then packs it (`make cart` takes `OUT=`, default
  `program`). The program is a 4,293-byte dictionary. On TSRun's core (`tools/cartrun.mjs`), `build/cart/blackjack.dck`
  drew the same title as on ZEsarUX: checked once by eye, not in a suite.
- **The manual**: Part 7 ends with the program (what it uses, how to load it from a text tape); Part 6 has `make
  blackjack`, `OUT=`, `fs2lib.py`, and the advice to seed after the first key; `RANDOMIZE` and `RND` give the new
  seed.

## 2. Defects found and fixed

| Defect | Leap-C / Leap V2 | Fix |
|---|---|---|
| `RND` with no seed (or after `0 RANDOMIZE`) took it from the R register alone: 128 seeds; a cartridge's start word runs at the same moment after every switch-on | Leap-C's manual: `srand(frames())` after a key (an unseeded `rand()` is a fixed sequence). Leap V2 seeds from R alone, as Forth did | The seed is `FRAMES` with R XORed into its high byte, bit 0 set; the manual says to `0 RANDOMIZE` after the first key, as the demo does. Same size: the 6 seed bytes, and `RND`'s x = 0 test became `ret z` (-1 B) to pay for `ld hl,(FRAMES)` (+1 B) |
| `tools/tape_gen_forth.py` copied a file's bytes as they were: a PC file's LF line ends went on tape, `LOAD-TEXT` saw one line, and its first `\` comment hid the rest (`demos/gallery.fs` and the rebuilt Blackjack could not be loaded) | Leap-C's `c2tape.py` turns a host file into the store's CR lines | LF and CR LF become CR; a text over the 8,192 bytes `LOAD-TEXT` takes is refused |
| The old demo: `CLS` before the felt colours; the column table overflowed at 11 cards; the test's log at a literal RAM address | — | The rebuild (section 1) |

A first version of the seed put R in the low byte. The new cartridge case `blackjack-deal` caught it: for the first 256
frames after switch-on (about 4 s) the high byte is 0, so there were again only 128 seeds, and a key 50 frames later
dealt the same cards. It was fixed before the commit.

## 3. Sizes

HOME 1,924 B free (unchanged; the `kernel` component at its 2,661 B budget, no reallocation), EXROM 3,136, the
cartridge's HOME image 1,751. Dictionary at power-on 16,128 B.

## 4. Tests

| Test | What it checks | Fails without the change |
|---|---|---|
| floattest `0 RANDOMIZE seeds from FRAMES` | the same R, five `FRAMES` values: five different states | old build: one state for all five |
| tapetest case 2 | the demo itself on a real tape signal, between a scripted `KEY` (defined before it) and a postlude that plays 8 rounds from seed 15785 and leaves each round's totals and outcome and the tally: equal to `bj_model` (tapetest: the demo's rules on `fpforth.rnd`). The rounds cover all five outcomes, a 4-card hand for each side | the old `tape_gen_forth.py`: the stack is empty (the first comment hid the text) |
| carttest `blackjack` | the cartridge as `make blackjack` packs it: the title with the suits (the start word made the UDGs), a key, a round dealt, S until it ends, N: `THANKS FOR PLAYING`, the prompt, `LAST_ERROR` 0 | — (new program) |
| carttest `blackjack-deal` | the title's key 50 frames later deals other cards | the first seed (R in the low byte): the same cards |

`make test` (557 s): boot 14/14, forth 375/375, editor 30/30, float 67/67, shape 48/48, bench 6/6, poweron 7/7, tape
19/19, cart 14/14. The first run had the replay file as `tests/data/blackjack_rounds.fs`, which the forth suite took
for a test (it runs every `.fs` under `tests/`): it is `.txt`, as the old one was, and the forth suite and case 2 pass
again. `make check` and `make repro` pass.

Emulators only (ZEsarUX 13.0, TSRun); no cartridge hardware. ZEsarUX runs 50 frames a second where a TS2068 runs 60,
so `BEEP`'s notes (it counts 60 frames a second) last about 20% longer there; `WAIT` is a loop and does not change.
