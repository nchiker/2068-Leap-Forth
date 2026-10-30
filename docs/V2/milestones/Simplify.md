# Simplify — Leap-C's conventions: milestone report

**Date:** 2026-10-30. **Status: complete.** Branch `v2/step-simplify` from master `c7ac8b1` (PR #9, step O15, merged
at the start of the session). The project now follows `~/2068-Leap-C` (`CONTRIBUTING.md`, `project_plan.md` section 1)
for images, tests, RAM layout, code style and paperwork.

## 1. What changed

- **Images:** `make` builds the HOME ROM (`forth_boot_rom0.bin`), the EXROM (`graphics_exrom.bin`), the two as one 24 KB
  file for ZEsarUX (`forth_zesarux.bin`), the EXROM as a `.dck` (`graphics_exrom.dck`, EightyOne and TS-Pico) and
  `SHA256SUMS`. Gone: the DOCK cartridge build (`-DCARTRIDGE`) and its tools, the Blackjack and Gallery demo ROMs (their
  Forth sources: `demos/blackjack.fs`, `demos/gallery.fs`), the LROS stub, 60 smoke ROMs, 8 EXROM test ROMs, the HIRES
  visual ROM, 4 bench ROMs: 77 ROM sources become 2. No test build is needed.
- **Tests:** one runner, `tools/run_tests.py` (`make test`, `make test-fast`), every suite on one pool of emulators over
  the production images, then the power-on and tape suites. The smoke ROMs' 243 checkpoints: 183 are Forth tests in
  `tests/<area>/*.fs` (typed at the prompt, each line against its `\ expect:`; `tools/forthtest.py`), several made able
  to fail where they could not before (attribute bits, AY registers read back); 54 were already covered by the editor,
  float, shape or tape suites; 2 became tapetest case 15 (SAVE-LIB over 512 B, a wildcard LOAD-LIB); 4 were retired with
  their reason (the speaker BEEP, an interrupt state Forth cannot reach, a carry flag the glyph checks cover, ULAplus
  palette read-back, which ZEsarUX does not give). The benchmarks are programs in `tests/bench/`, timed on the product
  ROM. README's examples are a test (`tests/doc/readme.fs`).
- **RAM:** one layout file, `include/forth_layout.inc` (360 lines: the map, the regions, the cells), replacing
  `include/sysvars.inc` (2,735 lines, mostly the BASIC project's), `include/exrom_home_ram.inc` and about 170 RAM `EQU`s
  in other files; 128 dead cells removed (their space kept as `DEFS n ; free`, so no address moved). `make check` runs
  `tools/check_ram_layout.py`: every RAM name either image references lies where the map allows, is defined in the
  layout file, and no source holds a literal RAM address; 12 negative controls (`tests/layout_negctl.asm`).
- **Code:** every source trimmed to Leap-C's style (short file header; routine headers with In / Out / Destroys; no
  history), assembling to identical bytes; the dead alternatives of a multi-build project removed (five `DEFINE`
  switches and their `IFDEF`s, 61 unused dictionary-chain labels, the integer-only `NUMBER`, the fake-tape hooks).
- **Paperwork:** `budget.toml` with per-component budgets (ten HOME, seven EXROM components, each byte attributed to its
  source file or label range by `tools/budget.py`) and a ledger for reallocations; the reserve floors are the owner's
  targets (HOME 200 B, EXROM 150 B). `CONTRIBUTING.md` after Leap-C's; the README, setup documents and tutorial
  describe the two images. This report, the roadmap and a short HANDOFF.

## 2. Defects found and fixed in the step

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| `CLS` did not home the print position (its reset was under an `IFDEF` that was never true) | the migrated smoke checks | the reset assembled | +6 |
| A `THROW` left `CATCH`'s xt cell on the stack (`1 2 ' T CATCH . . .` printed `7 999 2`) | the migrated smoke checks | the xt popped before the frame records IX | +1 |
| `VAL` of an empty string left a stray cell | the code trim | both cells popped first | 0 |
| `SOUND` used the low byte of the register number (256 wrote register 0) | the code trim | 256 and up ignored | +2 |
| `LEFT`/`RIGHT` used the low byte of the count (`256 LEFT` gave an empty string) | the code trim | 256 and up keep the whole string | +6 |
| A 32-character name could never be found (stored with length 0), and the rest of a longer token became the next token | the code trim | `WORD` keeps 31 characters, skips the rest | +2 |
| `LIST-DEFS` ended a definition at a `;` inside a word or string | the code trim | only the word `;` ends one | +14 |

Each has a test that fails without the fix (`tests/graphics/cls.fs`, `tests/core/catch.fs`, `tests/string/basic.fs`,
`tests/sound/soundreg.fs`, `tests/string/charfn.fs`, `tests/core/defining.fs`, `tests/core/listdefs.fs`). Shrunk in the
same work: the page-out after the cartridge variant (2 B), three spare loads (3 B).

## 3. Sizes (`make budget`)

| Image | Before | After | Change |
|---|---:|---:|---:|
| HOME free bytes | 1,758 | 1,732 | −26 (fixes +31, shrinks −5) |
| EXROM free bytes | 3,296 | 3,296 | 0 |

HOME components (bytes): boot 772, kernel 2,643, tape 1,024, interpreter 2,293, integer words 827, floats 3,015, text
1,520, graphics 691, sound 340, console 1,527. EXROM: table 51, RECT 356, POLYGON 763, sprites 364, editor view 2,435,
CIRCLE 234, FILL 693. Ledger entries: sound +2, text +4, interpreter +2, console +14 (the fixes above).

Sources (the two images' files): 24,514 lines with 11,436 full-line comments before, 15,982 with 3,563 after.
Repository: 269 files changed, 5,204 insertions, 33,262 deletions.

## 4. Tests (`make test`, 2026-10-30, 523 s on 7 emulators)

| Suite | Result |
|---|---|
| boot | 9/9 (the prompt reached in 4,440,139 T) |
| forth | 52/52 files (356 checked lines) |
| editor | 30/30 |
| float | 66/66 |
| shape | 37/37 (with the speed group) |
| bench | 4/4 |
| poweron | 7/7 patterns, no defined range differs |
| tape | 17/17, extra 1/1 |

`make test-fast` (boot, forth, editor, float and shape without speeds) takes about 2 minutes. `make check` and
`make repro` pass; `make fusesave` 17/17 after the cartridge half was removed.

## 5. Speed (T-states, `make test`)

| Benchmark (`tests/bench/`) | T-states |
|---|---:|
| sieve, 10 passes over 2,000 flags | 143,825,398 |
| float, 300 Taylor sums | 141,594,438 |
| pixel, 3,000 PLOTs of the chaos game | 34,236,463 |
| string, 400 PLACE + STR | 2,018,712 |

These are typed programs on the product ROM, not the old bench ROMs, so the numbers start a new series. The code's
speed is unchanged by the step except at the fixes (none on a hot path); the editor's typing costs and the float and
shape speeds are as in O15.

## 6. Limits

Every result is ZEsarUX's (and Fuse's for fusesave and tapetol-fuse); there is no hardware. A Forth test reads the
screen as text: a line's output must fit on the screen, and a line that clears the screen must print something new.
