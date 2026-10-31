# Words and keys — comments, compiling words, keys, font, text speed: milestone report

**Date:** 2026-10-31. **Status: complete.** Branch `v2/step-words-keys` from master `a18a66b` (PR #11, step Space,
merged; `make test` passed on it). Each part follows `~/2068-Leap-C` where Leap-C has it: its key map (delta D7), its
shared key-table lookup, its glyphs (D8, D13); the backtick glyph is 2068-Leap's (Q-26). Leap-C draws text the way
Forth did, so the faster text path is Forth's own.

## 1. What changed

- **Words.** `\` (a comment to the end of the line) and `(` (to the next `)`), both immediate. `[` and `]` switch
  `STATE` inside a definition, and `LITERAL` compiles what was computed there: `: S [ 60 60 * ] LITERAL ;`. `[']`
  compiles an execution token; `CHAR` gives the first character of the next word as typed (`CHAR a` is 97: names are
  folded to upper case, characters are not) and `[CHAR]` compiles it. `[']`, `[CHAR]` and `LITERAL` are compile-only,
  as `IF` is. `CHAR` and `LITERAL` were not in the roadmap's list; without them `[CHAR]` has no interpreting form and
  `[ ]` has no way to use what it computes.
- **Keys.** SYMBOL SHIFT + A S D F G give `~ | \ { }`, + Y U give `[ ]`, + H gives `^` (Leap-C's D7; they were 0).
  `IO_DECODE_KEY`'s three copies of the `row*5+bit` lookup are one tail, as in Leap-C (O16, −18 B).
- **Font.** `FONT_TABLE` is printable ASCII (32-126) in code order: the glyph of a code is `FONT_TABLE + (code − 32) * 8`.
  It gains `[ \ ] ^ { | } ~` (Leap-C's D8 glyphs) and the backtick (Leap's), and `1` and `l` take Leap-C's D13 glyphs
  (they differed in two pixels, so `l.0` read as `1.0`). Fuse's printer text output now decodes `LPRINT` correctly,
  since Fuse assumes this order.
- **Text speed.** The glyph lookup is one subtraction (it was a chain of range tests, then a scan of 23 punctuation
  pairs). `GFX_PUTCHAR` keeps BC, computes the cell address itself (`GFX_CHAR_SETUP` merged in) and copies the eight
  scanlines unrolled. `GFX_PUTCHAR_ATTR` sets the attribute from the address it already has, so `EMIT`, the console's
  cells and `GFX_CLEAR_ROW` no longer make a second, bounds-checked `GFX_SET_ATTR` call. `EMIT_CHAR_TMP` is gone.
- **One header builder.** `:`, `CREATE`, `VARIABLE`, `CONSTANT`, `ARRAY`, `STRING`, `FVARIABLE` and `FCONSTANT` built
  their headers with five copies of the same code. `HEADER_BUILD` (with `HEADER_END`, `HEADER_LINK`) is now the only
  one; `ARRAY`, `STRING` and `FVARIABLE` are `VARIABLE_N` with their data sizes (16-bit). `W_WORD`'s whitespace skip is
  its own routine, `WORD_SKIP`, which `CHAR` uses to read the raw first character.
- **Tools.** The screen decoders (`fharness`, `fusedrive`, `tapetest`, `tapetol`) read either font layout, since they
  also run old builds (`--build`, `TAPETOL_BASE`).

## 2. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| `:` `CREATE` `VARIABLE` `CONSTANT` `ARRAY` `STRING` `FVARIABLE` `FCONSTANT` with no name after them made a nameless word (`:` also left the console compiling); `'` with no name said `UNDEFINED WORD`, `FORGET` said `NOT FOUND` | writing `CHAR` (what it should do with no word) | `WORD_NAME`: THROW -16, `MISSING NAME` (the standard's code), for all eleven words | +14 (message), the check inside the header builder |
| A `;` inside a comment would end a `LIST-DEFS` span and a `:` inside one start a span that swallowed the next definition | adding comments | `SCAN_DEFS` reads the store word by word and skips `\` and `(` comments | +2 |
| `EDIT name` could open a commented-out `: name` line (`\ : SQ ...`, `( n : SQ )`) | the same | `VIEW_MATCH` (EXROM) skips comments the same way | +28 (EXROM) |
| A `\` that ended its line in LOAD-TEXT's CR-ended text would have skipped the next line (WORD consumes the CR as the delimiter) | writing `\` | `\` checks the byte it was ended by | 8 |

## 3. Tests

Each behaviour change has a test that fails on the old build (`a18a66b`, a worktree; `tools/forthtest.py --build`):

| Test | On the old build |
|---|---|
| `tests/graphics/font.fs`: the nine new glyphs, `1` and `l`, the glyph address rule, no-glyph codes, EMIT's attribute in each third | `[\]^`{\|}~` reads as blanks; `1` and `l` lines checked one by one: both differ |
| `tests/core/brackets.fs`: `[ ] LITERAL`, `[']` (also of an immediate word), `CHAR`, `[CHAR]`, compile-only refusals, an unknown name after `[']` | `[ ?` on the first line |
| `tests/core/comments.fs`: `\`, `(`, inside a definition, `\` ending a line, an unclosed `(` | `\ ?` |
| `tests/core/names.fs`: each of the eleven words with no name; the defining words still work, data sizes | every line run alone fails (nothing printed, `UNDEFINED WORD`, `CHAR ?`, `NOT FOUND`) |
| `tests/core/listdefs.fs`: `;` and `:` in comments | fails; and with only the old `SCAN_DEFS` it lists `: DD ( a ;` and a phantom `: EE ;` |
| `tests/doc/tutorial_words.fs`: the tutorial's new examples | fails |
| boot suite, matrix check: `~ \| \ { } ] [ ^` typed on ZEsarUX's keyboard matrix | `Forth cannot type '~'` |
| editor suite `keys-charset`: 94 typeable characters (was 86), only the backtick has no key; a fourth batch | 86 typeable |
| editor suite `edit-open`, part `comment` | `EDIT SQ` opens line 4 of 5 instead of 1 |
| tape suite case C: a text tape with a `\` right before a CR and a `(` over two lines, through LOAD-TEXT, prints 18 | `?` (no `\`); also fails (`TWO ?`) on a build without the CR check |
| `tests/io/printer.fs`: the glyph of `A` at its new address | (offset updated) |

`tests/bench/text.fs` (new): 100 lines of 32 characters through `TYPE`.

### Results (`make test`, 2026-10-31, 504 s)

| Suite | Result |
|---|---|
| boot | 9/9 |
| forth | 57/57 files |
| editor | 30/30 |
| float | 66/66 |
| shape | 37/37 (with the speed group) |
| bench | 6/6 |
| poweron | 7/7 patterns, no defined range differs |
| tape | 18/18 (case C new), extra 1/1 |

`make check` and `make repro` pass.

| Benchmark (`tests/bench/`), T-states | Before | After |
|---|---:|---:|
| text (new): 100 lines of 32 characters | 6,031,329 | 3,074,899 |
| literals: compile a word of 20 integer literals | 616,351 | 590,331 |
| string, 400 PLACE + STR | 2,018,658 | 1,999,337 |
| sieve | 143,727,541 | 143,711,284 |
| float | 141,594,342 | 141,572,395 |
| pixel | 34,183,736 | 34,168,222 |

Text is drawn about twice as fast: a character through `EMIT` costs about half what it did. The other benchmarks
gain from the console echoing the typed lines faster (`literals` also searches eight more words). Typing (the editor
suite's costs, T-states per key):

| Key | Before | After |
|---|---:|---:|
| a key at the end of a short line (console) | 38,873 | 21,709 |
| a key in the middle of a 100-character line (console) | 168,312 | 94,897 |
| a key at the end of a 3-row line (console) | 128,960 | 72,946 |
| DELETE (console) | 37,714 | 20,834 |
| a key at the end of a 3-row line (view) | 174,210 | 103,530 |
| DOWN that scrolls a 60-line store (view) | 270,608 | 238,104 |
| ENTER on the last line of a full screen (view) | 417,310 | 406,331 |

## 4. Sizes (`make budget`)

| Image | Before | After | Change |
|---|---:|---:|---:|
| HOME free bytes | 2,052 | 2,226 | +174 |
| EXROM free bytes | 3,296 | 3,272 | −24 |
| Dictionary (`FREE` at power-on) | 16,128 | 16,128 | 0 |

HOME by component (bytes, ledger entries in `budget.toml`): boot +14 (the message), kernel −45 (font +72; lookup,
`GFX_PUTCHAR` and `GFX_PUTCHAR_ATTR` −99; keys −18), interpreter +61 (the new words 135 B: `tick.asm` 88, `comment.asm`
47; the header builder and `WORD_NAME` −74), integer −89 (`ARRAY`), float +1 (`FVARIABLE`), text −113 (`EMIT` −31,
`STRING` −82), console −3. EXROM: view +28 (`VIEW_MATCH`), fill −4 (the `ALIGN 8` before the circle table pads less).
The step adds eight words and the font's nine glyphs and ends with 174 HOME bytes more than it started with.

## 5. Limits

Every result is ZEsarUX's (and Fuse's for the tape suites that use it); there is no hardware. The keys are tested on
ZEsarUX's emulated keyboard matrix, the glyphs as the ROM draws them and as bytes.
