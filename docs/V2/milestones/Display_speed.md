# Display speed — LINE on 16-bit coordinates, the view's store lookup, the console scroll: milestone report

**Date:** 2026-10-31. **Status: complete.** Branch `v2/step-display-speed` from master `f7ab173` (PR #13, step Display
look, merged; `make test` passed on it, 536 s). Neither `~/2068-Leap-C` nor Leap V2 has a faster routine for any of
the three: their `GFX_LINE` is the one Forth had (memory cells, two `MATH_COMPARE16` calls and a full address setup per
pixel), Leap-C's `draw()` moves off-screen ends to the edge (which bends the line), and Leap V2's editor also finds a
line by counting from the top (`V2_FIND_INDEX`). Leap V2's `GFX_CLEAR_ROW` (audit item O4) is taken.

## 1. Where the time went

Measured with ZEsarUX's per-instruction transaction log (T-states and PC, attributed to the routines of both `.sym`
files), on master:

| Action | T-states | Where |
|---|---:|---|
| `0 0 255 191 LINE` (256 pixels) | 363k drawing | about 1,400 T a pixel: `GFX_PIXEL_ADDR_SETUP` and `GFX_SET_ATTR` per pixel, two `MATH_COMPARE16` calls per step |
| View: ENTER on the last line of a full screen | 407,197 | 54% `STORE_NEXT`/`STORE_LINE` (the store scanned from line 0 about 7 times); 26% moving 22 rows; 6% blanking rows |
| View: DOWN / UP that scroll a 60-line store | 238,346 / 210,240 | moving rows 47-54%, store scans 13-24% |
| View: DOWN between two lines mid-screen | 61,104 | 45% store scans |
| Console: a line whose output scrolls | 267,678 | 192k the scroll (`GFX_COPY_ROW_BITMAP`'s LDIR per scanline; the view's unrolled-LDI copy moves the same 22 rows in 113k) |
| Typing, the worst key | 95-105k | about 585 T per character redrawn: under 2 frames, not changed |

The owner approved four changes (2026-10-31) and option (a) for POLYGON: its vertices stay bytes this step, as the
option with the least ROM space (section 6).

## 2. What changed

- **LINE** (`kernel/graphics/graphics.asm`, `core/ts2068.asm`). `LINE ( x1 y1 x2 y2 -- )` takes signed 16-bit ends
  and draws the points of the unbounded Bresenham line that are on the screen. The loop is the major-axis form: the
  major axis steps at every point, the minor one when the error r (0 to dmaj − 1, from dmaj / 2) passes dmaj after
  adding dmin. That is the e2 form the ROM used (checked identical on 48,561 lines in Python), so a line on the screen
  draws the same pixels as before. r, dmin and dmaj live in the alternate registers (nothing the interrupt runs uses
  them), so 16 bits hold any length. Off the screen the line is walked without drawing; on it, the address and mask
  step from pixel to pixel (`LINE_XSTEP`, `LINE_YSTEP`), the attribute is written with the next pixel when the cell
  (HIRES: the byte) changes, and the line ends at its end point or where a step would leave the screen.
  `GFX_WRITE_PIXEL` (PLOT, slot 0) uses the same register-based address (`GFX_PIXEL_AT`) and attribute code. The OVER
  flag, always 0, is gone with `GFX_PIXEL_ADDR_SETUP`, `BIT_MASK_TABLE`, `MATH_COMPARE16` and the `GFX_PIXEL_*` cells.
  LINE's four coordinates are 2-byte cells in the cells block (they were four bytes at `$F3C4`; `check_ram_layout.py`
  follows). `POLY_DRAW_IMPL` writes them through one vertex helper; CIRCLE's HIRES point is a tail jump to slot 0.
- **The view's store lookup** (`rom/graphics_exrom.asm`). `STORE_LINE` keeps a mark (`STORE_MARK_N`,
  `STORE_MARK_PTR`: the line it found last) and walks from the nearest of line 0 and the mark, forward or back.
  `STORE_GAP` keeps the mark unless a change starts before it (an insert, delete or replace at or after the mark
  leaves the lines before it as they were); a session starts it at line 0. Without the walk back the ENTER above would
  be 315,613 T; the walk back costs 29 B.
- **The console scroll** (`kernel/graphics/graphics.asm`). `GFX_SCROLL_ROWS` moves a third's scanline runs (rows
  1-7 of a third are one run of 224 bytes, then the next third's row 0) in 32-byte blocks of unrolled LDI
  (`GFX_LDI_BLOCKS`, 16 T a byte against LDIR's 21); `GFX_SCROLL_TEXT_UP` and `GFX_SCROLL_OUTPUT_UP` call it.
  `GFX_CLEAR_ROW` writes the row's bytes (Leap V2's) instead of drawing 32 spaces. `GFX_COPY_ROW_BITMAP` is gone.
- **`.`** prints its digits through `PRINT_UDEC16`: it held a second copy of that loop (−38 B, found while measuring).
- **Emulator commands** (README, `docs/zesarux_setup.md`, the release zip's `README-FIRST.txt`): Fuse's command gives
  full paths (`"$PWD/..."`, from the images' folder); ZEsarUX's is `cd` to its own folder, then `--romfile` with the
  full path.

## 3. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| README's Fuse command used bare image names: Fuse looks for those in the current folder, then its own ROM folders, so it failed from the repository (the images are in `build/`) | the owner | full paths, and the folder stated (checked headless: Fuse on the SDL dummy driver through `fusedrive`) | 0 |
| `docs/zesarux_setup.md`'s command used `build/forth_zesarux.bin` relative, but ZEsarUX runs from its own folder: `Unable to open rom file` | the owner | `cd` to ZEsarUX's folder, the ROM's full path (checked headless: `--vo null`, ZRCP read of `$0000`) | 0 |
| `.` duplicated `PRINT_UDEC16` | the measurement | `.` calls it | −38 |
| `MATH_UDIV16`'s header did not say its divisor must be at most 32768 (above that the remainder's ADC can carry out; its one caller, `MATH_SDIV16`, divides absolute values, so it never does) | the LINE rebuild (needing a 32-bit divide) | the header states it | 0 |
| The Display look report gave HOME 2,232 B free; the image measures 2,229 (the figure added the boot component's 3 unspent budget bytes) | the start of this step | this report uses 2,229 | 0 |
| The known defects scheduled here: LINE took bytes (`-10 50 100 50 LINE` started at x 246); ENTER at the bottom of the view took 406k T | the roadmap | sections 2 and 4 | |

## 4. Tests

Each change has tests that fail on the old build (master `f7ab173`, a worktree, `--build`):

| Test | On the old build |
|---|---|
| shape suite, new group: `line_from_off_left`, `line_edges`, `line_off_screen`, `line_far` (ends at ±32768), `line_random` (40 lines from −300..560, −250..450), `line_hires`, against the unbounded Bresenham line's points on the screen (`line_points`, signed) | fail (low bytes); `line_octants` passes on both (the same pixels on the screen) |
| shape suite, speed group: `line_speed_diagonal` / `_horizontal` / `_vertical` with ceilings 92,000 / 65,000 / 58,000 T; `line_speed_walk` recorded | 373,368 / 354,524 / 274,532 T: fail |
| `tests/graphics/pixels.fs`: `-10 50 100 50 LINE` (x 0-100 set, x 240-247 clear); `-32768 100 32767 110 LINE` (row 105 across) | `0 15 254` |
| editor suite `typing-cost`: `enter-scroll` (ENTER on `.( A) CR .( B)` typed on row 22) at most 200,000 T | 267,678: fail |
| editor suite `edit-typing-cost`: `enter-bottom`, `scroll-down`, `down-mid-full`, `up-scroll` at most 250,000 / 215,000 / 45,000 / 195,000 T | fail (407,197 / 238,346 / 61,104 / 210,240) |
| editor suite N7 `edit-keys`, sequence `mark`: 60-line store, walks forward and back over the 3-row lines, edits before, at and after the remembered line, the first and last lines, checked against the model (store bytes, rows, status, cursor) after every key | passes (a correctness guard for the new lookup) |

### Results (`make test`, 2026-10-31, 497 s)

| Suite | Result |
|---|---|
| boot | 12/12 |
| forth | 57/57 files |
| editor | 30/30 (N7 10 sequences) |
| float | 66/66 |
| shape | 48/48 (old 16, new 18, speed 14) |
| bench | 6/6 |
| poweron | 7/7 patterns, no defined range differs |
| tape | 18/18, extra 1/1 |

`make check` and `make repro` pass.

| Speed, T-states | Before | After | |
|---|---:|---:|---:|
| LINE, a 256-pixel row | 354,524 | 58,954 | 6.0× |
| LINE, a 192-pixel column | 274,532 | 52,286 | 5.3× |
| LINE, the full diagonal (256 pixels) | 373,368 | 83,901 | 4.5× |
| View: ENTER on the last line of a full screen | 407,197 | 220,829 | −46% |
| View: DOWN that scrolls / UP that scrolls | 238,346 / 210,240 | 201,229 / 183,169 | −16% / −13% |
| View: DOWN mid-screen, 60-line store | 61,104 | 39,304 | −36% |
| Console: a line whose output scrolls | 267,678 | 178,309 | −33% |
| bench `pixel` (3,000 PLOTs) | 34,018,966 | 33,116,550 | −2.7% |

The other benchmarks and the console's other typing figures are unchanged (within 0.1%); the view's other keys that look
up lines are up to 1.7% faster (ENTER mid-store 71,889 → 70,663), the rest within 20 T. LINE's walk off the screen costs about 270 T a step: a line starting at x −2,000 takes 0.6M T, one
with both ends near ±32,768 about 10M T (3 s). The proposal estimated 5-8× for drawing and about 40 T a walked step;
the diagonal reached 4.5× (a loop per major axis would give about 5× for 25 B more) and the walk 270 T (the 40 T was
wrong: a 16-bit Bresenham step with its bookkeeping costs more). An exact jump over the off-screen part (a 32-bit
multiply and divide) was built (its three routines 70 B, about 130 B with the code that used them) and left out for
its size (section 6).

## 5. Sizes (`make budget`)

| Image | Before | After | Change |
|---|---:|---:|---:|
| HOME free bytes | 2,229 | 2,188 | −41 |
| EXROM free bytes | 3,272 | 3,208 | −64 |
| Dictionary (`FREE` at power-on) | 16,128 | 16,128 | 0 |

HOME: text −38 (`.`); kernel +54 for the scroll (its four routines 140 B for the old three's 104, `GFX_CLEAR_ROW` 34 B
for 16) and +35 for LINE (397 B of new code, the inlined Bresenham step included, for the 362 B removed); graphics −10
(`W_LINE`, `W_PLOT`). EXROM: view +94 (`STORE_LINE` +59, `STORE_GAP` +29,
`VIEW_SESSION` +6), polygon −25, circle −5, FILL's alignment pad 0 net. Each is a ledger entry in `budget.toml`.
RAM: the cells block gains `GFX_LINE_X0..Y1` (8), `GFX_LINE_N` (2), `STORE_MARK_N`, `STORE_MARK_PTR` (4) and loses the
six `GFX_PIXEL_*` and nine old `GFX_LINE_*` bytes; `$F3C4-$F3C7` joins the free space below the machine stack.

## 6. Limits and what is left

- Every result is ZEsarUX's (the tape suites also Fuse's); there is no hardware. T-states include ZEsarUX's screen
  contention, so a figure is the emulator's, not a measurement of a real machine.
- POLYGON and POLYGON-FILL still take their vertices as bytes (an off-screen vertex wraps): the owner's option (a), in
  the roadmap's known defects.
- LINE with an end far off the screen walks to the screen at about 270 T a step (up to 10M T for ±32,768 ends): in the
  roadmap, with the price of the exact jump (about 130 B).
- Typing (about 585 T a character redrawn, under 2 frames a key) is unchanged.
