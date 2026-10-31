# Display look — Leap V2's screen, startup chord and version: milestone report

**Date:** 2026-10-31. **Status: complete.** Branch `v2/step-display-look` from master `85d727a` (PR #12, step Words and
keys, merged; `make test` passed on it, 516 s). Leap V2 is `~/2068-Leap` at `b30ca0c` (`2068 LEAP V2.1`): its screen,
`rom/exrom_v2_shell.asm` (`V2_COMMAND_LOOP`, `STARTUP_CHIME`, `V2_DRAW_STATUS`, `V2_STATUS_SET_BAR_ATTR`),
`rom/v2_version.asm` and `include/v2_version.inc`.

## 1. The comparison and the owner's decisions

Both ROMs were booted headless in ZEsarUX and their screens read from memory during the chime, at the first key wait
and after typing (border from `get-io-ports`). The owner chose, for each difference:

| | Leap V2 | Forth before | Decided |
|---|---|---|---|
| Paper and ink | white paper, black ink (`$38`) | black paper, bright green ink (`$44`) | Leap V2's; the cursor (ink and paper swapped, FLASH) becomes `$87`, as Leap V2's |
| Border | set to 7 | never set (ZEsarUX shows its power-on 7) | set to 7 at the cold start |
| Banner | none | `2068-FORTH` on row 0, output from row 1 | none; output from row 0 |
| Version | `2068 LEAP V2.1` on row 23 on the status bar, from before the chime to the first key | none | option A: `2068 FORTH V2.0` on row 23 from column 2 on the bar, the cursor in its column 0 after the chime; the first key, whatever it is, takes it off |
| Version source | `include/v2_version.inc`, by hand at each release, not from git | none | the same: `include/forth_version.inc` |
| Editor status row | the bar | plain text | the bar (`EDIT`'s `LINE n/m` and `STORE FULL`) |
| Chime | chime C: the chord by loops from an 11-byte register list | the same chord from an 80-byte table | chime C |
| Font | — | — | identical already (all 95 glyphs byte for byte) |
| Keyword bolding | BASIC keywords bold in the editor | none | not added (Forth has no fixed keyword set) |
| Errors, program output | on the bar; RUN clears to an output screen | in the console, next to the line | Forth's |
| Return to the editor | border, colours and mode reset | the colours a program set survive | Forth's |
| BREAK during the chime | ends it | the chime plays out (0.9 s) | Forth's |

## 2. What changed

- **Colours** (`include/hardware.inc`, included by both images): `ATTR_DEFAULT` `$38`, the bar's `ATTR_STATUS_BAR` `$07`
  and the three colour cells, `BORDER_DEFAULT` 7. The EXROM's own copy of `ATTR_DEFAULT` is gone, and so is
  `check_ram_layout.py`'s comparison of it; `core/ts2068.asm`'s unused `DEFAULT_ATTR` is gone.
- **Cold start** (`rom/forth_boot.asm`): the border, `GFX_CLS`, the version from column 2 of row 23 and
  `GFX_STATUS_BAR`, the chime, then the empty input line as `EDITOR_LOOP_LIVE`'s redraw leaves it but with row 23 not
  redrawn: `WRAP_CALC`, `FWRAP_TOP` 23, the cursor on the bar, into the key loop.
- **The first key** (`core/editor.asm`): `VERSION_UP` (a new cell, 1 from the cold start) makes `EDITOR_PROCESS_KEY`
  redraw even after a key that changed nothing (LEFT on an empty line, BREAK); `EDITOR_REDRAW` clears it, so a typed
  key or ENTER's run takes it off too. Leap V2 leaves the version up for keys that do not redraw; here every key takes
  it off, as the owner chose.
- **`EDIT`'s status row**: `VIEW_STATUS` (EXROM) draws through HOME's `ED_STATUS_ROW` (`GRAPHICS_HOME_TABLE` slot 13):
  the row as before, then `GFX_STATUS_BAR`. The EXROM's code keeps its size, so the `ALIGN 8` before the circle table
  does not move.
- **Chime**: Leap V2's chime C, with `SOUND_WRITE` (which keeps B and C) and HALT waits. The same notes, levels and
  frame timing; R6 (the noise period, unused: noise is off) is written, and the chime ends with 3 silent frames
  (55 frames to the key wait, was 52). `tools/ay_audio.py --compare-chime` against master: PASS, the worst
  per-window power difference 0.02.
- **Room** for the above, each a shrink with the same behaviour: `GFX_SET_MODE` (−12 B), `GFX_CELL_ATTR_ADDR`
  (−3 B, computes the address from the row's bits and keeps DE), `GFX_COPY_ROW_BITMAP` (−4 B), `INSERT_CHAR` and
  `DELETE_CHAR_BEFORE_CURSOR` (−16 B: `EDIT_LEN` and `EDIT_CURSOR` are adjacent, an `ASSERT` says so).
- **Docs**: README, the tutorial (a boot screenshot, `docs/images/boot_screen.png`; `typo_error.png` and
  `drawing_example.png` rendered again from the build, headless, from screen memory), the EightyOne page (its
  screenshot is of an earlier build, now said so), the download's README; `forth_tutorial.docx` regenerated.

## 3. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| The border was never written: it showed whatever the ULA held at power-on (ZEsarUX's 7 hid it) | the comparison | the cold start sets `BORDER_DEFAULT` | +5 |
| `core/ts2068.asm`'s `DEFAULT_ATTR` (`$38`) was unused and its comment said the cold start set `CURRENT_ATTR` from it (it used `ATTR_DEFAULT`, `$44`) | the comparison | removed; one set of colour constants | 0 |

## 4. Tests

Each behaviour change has a test that fails on the old build (master `85d727a`, a worktree, `--build`):

| Test | On the old build |
|---|---|
| boot check l, startup chime (`Machine.boot_trace`): every `SOUND_WRITE` of the boot with its frame, 29 writes, the key wait at frame 55 | 28 writes (no R6), frame 52 |
| boot check m, boot screen: from a border of 2 before the reset, border 7; at the chime's first write and at the key wait the version alone on row 23 and the bar's attributes; rows 0-22 `$38`; `CURRENT_ATTR` `$38` | border 2, no version, `$44` |
| boot check c, version (was banner): row 23 `  2068 FORTH V2.0` on the bar with the cursor `$B8`, rows 0-22 blank | row 23 empty |
| boot check n, first key: LEFT, ENTER or `7` as the first key leaves row 23 the input line (`$38`, cursor `$87`); ENTER's `OK` on row 0 | the banner on row 0, `$44` |
| editor suite, the view's oracle: the status row's attributes are the bar after every key (`edit-open`, `edit-keys`, `edit-commit`, `edit-redraw-oracle`, `edit-store-full`) | `$44` on row 23 |
| editor suite `boot-console`, `colour-state`; Forth tests `font.fs`, `hires.fs`, `cls.fs`, `shapes.fs`, `ulaplus.fs` hold the new colours | `$44`, `$E0`, `$72` |

The console cases, floattest and the harness's own checks read output from row 0 (they skipped a banner on row 0);
`break-key-console` presses BREAK twice: the first, like any first key, takes the version off.

### Results (`make test`, 2026-10-31, 515 s)

| Suite | Result |
|---|---|
| boot | 12/12 (c changed, l m n new) |
| forth | 57/57 files |
| editor | 30/30 |
| float | 66/66 |
| shape | 37/37 (with the speed group) |
| bench | 6/6 |
| poweron | 7/7 patterns, no defined range differs |
| tape | 18/18, extra 1/1 |

| Benchmark (`tests/bench/`), T-states | Before | After |
|---|---:|---:|
| pixel | 34,168,222 | 34,018,966 |
| sieve | 143,711,284 | 143,709,308 |
| float | 141,572,395 | 141,572,289 |
| string | 1,999,337 | 2,001,333 |
| text | 3,074,899 | 3,074,966 |
| literals | 590,331 | 590,305 |

`pixel` is 0.4% faster (`GFX_CELL_ATTR_ADDR`); the rest are within 0.1%. Typing (editor suite, T-states per key): the
console within 0.2%; in the view, a key that redraws the status row costs the bar's 32 attribute writes more (a key at
the end of a 3-row line 103,530 → 105,471, ENTER 71,102 → 71,889, ENTER on the last line of a full screen 406,331 →
407,197).

`make check` and `make repro` pass.

## 5. Sizes (`make budget`)

| Image | Before | After | Change |
|---|---:|---:|---:|
| HOME free bytes | 2,226 | 2,232 | +6 |
| EXROM free bytes | 3,272 | 3,272 | 0 |
| Dictionary (`FREE` at power-on) | 16,128 | 16,128 | 0 |

HOME by component: boot −3 (the chime −23, the border +5, the version text and its drawing, the cursor on the bar;
the banner and its print gone), kernel 0 (`GFX_STATUS_BAR` +19, the three shrinks −19), console 0 (`ED_STATUS_ROW` +6,
`VERSION_UP` +10 in `EDITOR_PROCESS_KEY` and `EDITOR_REDRAW`, the two shrinks −16). Measured with `make inventory`
on both builds. Every component is within its budget with no ledger entry. RAM: one cell,
`VERSION_UP`, from the free room at the end of the cells block.

## 6. Limits

Every result is ZEsarUX's (the tape suites also Fuse's); there is no hardware. The colours are the attribute bytes and
the border port's value, not a picture of a television. The chime was compared as ZEsarUX's audio output
(`tools/ay_audio.py`), not listened to.
