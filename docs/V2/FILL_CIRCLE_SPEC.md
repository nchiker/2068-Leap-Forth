# FILL and CIRCLE to the EXROM: specification (step O15)

Audit item O15 (`docs/V2/LEAPC_COMPARISON_AUDIT.md`, approved by the owner 2026-10-28: "O15 approved, after E"):
`GFX_FILL` and `GFX_CIRCLE` with their helpers leave HOME for the graphics EXROM (`rom/graphics_exrom.asm`), and
the words `FILL` and `CIRCLE` keep thin HOME stubs, as `RECT`, `POLYGON`, `POLYGON-FILL` and `SPRITE-*` already do.
Rebuilt, not dropped in: the code is designed again for the EXROM, the old build runs the oracle first, each code
commit has a measured ledger row. Evidence tags: [M] measured, [S] source, [E] estimate, [L] Leap-C/Leap V2.
Written on `v2/step-o15-fill-circle`, branched from `v2/step-f-float` `1b6fcda`; rebased on master `df391e6` after PR #8 merged.

## 1. Why

HOME has 816 B free after step F, and every later step (K, D, B, Z) needs HOME bytes. FILL and CIRCLE are 896 B of
HOME kernel [M] that only two words use, and the EXROM has 4,247 B free [M]. Both are also slow and FILL is
incomplete:

* **FILL works one pixel at a time.** Every pixel is read by `GFX_READ_PIXEL` (the full address set-up, about 230 T)
  and checked in a separate 6 KB visited bitmap with its own address arithmetic, three to four times per pixel
  (the left/right walk, the paint, the scans above and below), and painted by `GFX_WRITE_PIXEL`, which also
  recomputes the attribute address per pixel. A full-screen FILL is tens of millions of T-states [E; measured by the
  oracle, section 9].
* **FILL can lose part of a region.** Its seed stack holds 512 entries; a push on a full stack is dropped, and
  whatever only that seed would have reached stays unfilled. The span model (section 4.5) overflows 512 on a screen
  with 6,000 random dots [M, model].
* **FILL does not check its seed.** `x` and `y` are taken as low bytes; a `y` of 192-255 indexes `ROW_BASE_TABLE`
  past its 24 rows (the same defect as O18 for PLOT/LINE) and then fills "rows" outside the screen.
* **CIRCLE takes its centre and radius as bytes.** `-10 50 30 CIRCLE` draws a circle centred at x = 246;
  `100 100 300 CIRCLE` draws radius 44. A circle can be clipped by the screen edge only on its right and bottom.
* **CIRCLE plots each point through three layers** (`GFX_CIRCLE_PLOT_OFFSET`, `GFX_PLOT_CLIPPED`,
  `GFX_WRITE_PIXEL`), about 650 T a point [E].

## 2. References studied (before this design)

| Reference | What it is | Taken / not taken |
|---|---|---|
| Today's `kernel/graphics/graphics.asm` `GFX_FILL` (+ PUSH, POP, VISITED_CHECK, VISITED_CHECK_SET, SCAN_ROW) and `GFX_CIRCLE` (+ PLOT_OFFSET, PLOT_POLES, PLOT_GENERAL), `GFX_PLOT_CLIPPED`, `GFX_READ_PIXEL`; words in `core/moregfx.asm` and `core/ts2068.asm`; RAM in `include/sysvars.inc` | the code being replaced | The span algorithm (one seed per run on the rows above and below, scan bounded to the span) and its Python-verified reasoning; the OR-only paint with the cell attribute of every painted pixel; FILL's refusal in HIRES. Not: per-pixel calls, the separate visited address arithmetic, the dropped seeds, byte arguments |
| Leap V2 `rom/ext_v2_shapes_module.asm` (`b30ca0c`) | the same V1 code as a loadable package, with Leap V2's fixes | **D7: a dropped seed is recorded and a sweep of the visited bitmap re-seeds every fillable neighbour of a painted pixel**, resumable, until a sweep seeds nothing: taken (section 4.5), byte-parallel instead of per pixel. `SHAPES_FILLABLE` (one predicate for "matches and unvisited"): taken as the plane in section 4.2. BREAK checks in the loop: not taken here (Forth has no BREAK in its ISR; step B, O6) |
| Leap V2 `rom/extensions/shapes.asm` | V1 package; its header | Its warning that `$C000` buffers inside the banking window break when the dispatch pages EXROM in: Forth's buffers are at `$5B00-$7FFF`, never paged (section 7) |
| Leap-C `libs/shapes.asm` (`circle`) and `platform/kernel/graphics/graphics.asm` (the removal note) | Leap-C moved CIRCLE/FILL out of HOME into a library; its `circle` | **16-bit signed centre and radius, each point clipped, each point drawn once** (`p_sym`/`p_four`: one column when the offset is 0, one row when it is 0, the swapped four skipped when x = y): taken (section 5). Negative radius an error in Leap-C (`RTE_ARG`): owner decision O15-5 |
| `rom/graphics_exrom.asm` `RECT_FILL_IMPL` | the EXROM's byte-level rectangle fill | Row base once per row, edge masks, whole bytes between, each attribute cell stamped once: the same technique for FILL's spans (section 4.3) |
| `rom/graphics_exrom.asm` `POLY_FILL_IMPL`, `EXROM_CALL_SLOT` (`core/rectfill.asm`), `GRAPHICS_HOME_TABLE` (`rom/forth_boot.asm`), `include/graphics_exrom_abi.inc`, `include/exrom_home_ram.inc`, `tools/audit_layout.py`, `tools/make_dck.py`, `kernel/bank/bank.asm`, `CARTRIDGE_EXROM_SPEC.md`, `EDITOR_SPEC.md` (VIEW_SESSION, slot 6) | how HOME calls the EXROM in both builds | The service-table call, the magic/ABI check, the `$0100` veneers, the HOME RAM copies check; slot 7 is the last free slot (decision O15-1) |

## 3. Today [M] (`1b6fcda`, `build/forth_boot.lst`)

| Part | Address | HOME B |
|---|---|---:|
| `GFX_FILL_PUSH` .. `GFX_FILL` (6 routines) | `$0A49-$0C1F` | 487 |
| `GFX_CIRCLE_PLOT_OFFSET` .. `GFX_CIRCLE` (4 routines) | `$0C20-$0D9F` | 368 |
| `GFX_PLOT_CLIPPED` (only CIRCLE calls it) | `$0A2A-$0A48` | 31 |
| `GFX_READ_PIXEL` (only FILL calls it) | `$0951-$095A` | 10 |
| **Kernel total, leaves HOME** | | **896** |
| `FILL` word (`H_FILL`..`H_ATXY`, header 7 + body 25) | `$2A11-$2A30` | 32 |
| `CIRCLE` word (`H_CIRCLE`..`H_BORDER`, header 9 + body 29) | `$16F9-$171E` | 38 |

RAM [S]: `GFX_FILL_VISITED` `$5B00-$72FF` (6,144 B), `GFX_FILL_STACK` `$7300-$76FF` (512 entries of x, y);
`$7700-$7FFF` is unused; FILL's cells `GFX_FILL_SP` .. `GFX_FILL_SCAN_END` (11 B), CIRCLE's `GFX_CIRCLE_XC` ..
`GFX_CIRCLE_D` (10 B), `GFX_CLIP_ATTR/OVER` (2 B), all in `include/sysvars.inc`. `CIRCLE` always passes OVER 0:
Forth has no OVER drawing mode, so the "draw each point once" logic only matters for a future XOR mode.

Callers: only `W_FILL` and `W_CIRCLE` in the product ROMs [S]; the other ROMs that include the kernel are in section 8.

## 4. FILL, rebuilt in the EXROM

### 4.1 Contract

`FILL ( x y -- )`: x and y are signed cells. A seed outside 0-255, 0-191 does nothing (O15-4). In HIRES, FILL does
nothing (as today; O15-6). Otherwise every pixel 4-connected to the seed through pixels of the seed's value is set,
and the attribute cell of every such pixel gets `CURRENT_ATTR` (exactly today's result when today's stack does not
overflow). Always completes (section 4.5). The data stack loses two cells; nothing else in HOME RAM changes except
FILL's own cells.

### 4.2 Two planes at a fixed offset

The visited bitmap moves to the **screen's own layout**: plane address = screen address + `$1B00` (`$4000-$57FF` ->
`$5B00-$72FF`, the same 6,144 B as today's `GFX_FILL_VISITED`). One address and one mask serve both planes; the
separate `y*32 + x/8` arithmetic goes.

The fill always works on a plane where **0 = fillable, 1 = not**, and paints by setting bits:

| Seed pixel | Work plane `A` | Reference plane `B` | Set up (one pass, 6,144 B) | At the end |
|---|---|---|---|---|
| 0 (fill a blank area) | the screen itself | the shadow: a copy of the screen | `LDIR` screen -> shadow (129 kT) | nothing: the screen holds the result |
| 1 (recolour a solid area) | the shadow: the screen inverted | the screen (unchanged) | copy with `CPL` (about 160 kT) | nothing: the bitmap does not change, only attributes |

"Originally fillable" is `B XOR K` (K = `$FF` for seed 0, `$00` for seed 1) and "painted" is `A AND (B XOR K)`.
The reference plane is only read by the recovery sweep (4.5). With seed 0, paint goes straight onto the screen, so the
user sees the fill grow, as today.

### 4.3 One span

Pop a seed (x, y); if `A` has it set, discard it (stale). Walk left and right from x while the bit is 0, a whole
byte at a time when the byte is `$00` (8 pixels per step), bit by bit at the edges. Set `A`'s bits from lx to rx with
edge masks and whole `$FF` bytes (RECT's technique). Stamp `CURRENT_ATTR` into the attribute cells of row y >> 3,
columns lx >> 3 to rx >> 3 (once per span; the cells today's per-pixel `GFX_SET_ATTR` writes). Then scan rows y - 1 and
y + 1 over lx..rx: per byte, fillable bits F = NOT `A` under the edge masks; run starts = F AND NOT (F >> 1, with the
previous byte's bit 0 shifted in at the top); one seed pushed per run start. A byte with F = 0 costs one test.

### 4.4 The seed stack

`$7300-$7FFF`: 1,664 entries of (x, y), 2 B each (today 512 at `$7300-$76FF`; `$7700-$7FFF` is unused [S]). A push on
a full stack sets `FILL_OVF` and drops the seed.

### 4.5 Recovery (Leap V2's D7, byte-parallel)

When the stack is empty and `FILL_OVF` is set: clear it, then sweep rows 0-191: for each byte,
candidates C = (NOT `A`) AND (P(y - 1) OR P(y + 1)), P = painted (4.2). Push a seed at each run start of C. If the
stack fills during a sweep, stop the sweep (`FILL_OVF` set again), drain, and sweep again. Done when the stack is empty
and `FILL_OVF` is clear. Correct because a fillable pixel left unpainted next to a painted one can only be vertical
(a span is always extended to its ends), and terminates because every sweep that seeds paints at least one span.
**Python model [M]** (`docs/V2/evidence/o15_fill_model.py`, written in the oracle commit): against a breadth-first
fill on blank, box, solid disc recoloured, serpentine (24,704 one-pixel vertical runs), lattice and noise screens of
6,000 and 14,000 dots, the region is exact with stack sizes 512, 64 and 8 (6,000 dots: 2 sweeps at 512, 173 at 8;
14,000 dots: 3 and 203).

### 4.6 Speed [E]

About 60-120 T a pixel inside a span and a few hundred T a span, against several thousand T a pixel today: a
full-screen fill from about 50 MT [E] to about 1 MT. Set-up 129-160 kT (today's visited clear is 129 kT). Measured
old and new in the oracle's speed table; **the gate: every speed case is no slower on the new build.**

## 5. CIRCLE, rebuilt in the EXROM

`CIRCLE ( xc yc r -- )`: xc, yc, r signed cells (O15-5 for r < 0). The midpoint algorithm of today (decision term
1 - r, x from 0 while x <= y), on 16-bit values, as Leap-C's `circle`. Each of the up to 8 symmetric points is
drawn once (Leap-C's `p_four`: the second of a pair is skipped when its offset is 0; the swapped four when x = y), so a
later XOR mode can use it unchanged. Each point is clipped (both coordinates 0-255 / 0-191, 16-bit) and then:

* Normal mode: plotted in the EXROM directly (screen address from y and x, mask from x & 7, OR, the attribute cell
  `$5800 + (y >> 3) * 32 + x >> 3` set), about 200 T a point [E];
* HIRES: through `GRAPHICS_HOME_WRITE_PIXEL` (slot 0 veneer, which already handles the per-scanline attributes).

A point set ordering does not matter (OR). Result for 0 <= xc, yc, r <= 255: the same pixels and attributes as today
[to be shown by the oracle]; for other values, the circle that the arguments describe, clipped.

## 6. How HOME calls it

* **Service slots (O15-1):** the table grows from 8 to 16 slots (`GRAPHICS_EXROM_MAX_SLOTS` 16, `GRAPHICS_EXROM_ABI`
  2); FILL is slot 7, CIRCLE slot 8, 9-15 reserved. The magic/ABI pair moves from `$A019` to `$A031`;
  `include/graphics_exrom_abi.inc` computes it and every caller reads it from there; `tools/make_dck.py`'s trailer
  check (offset 25, hard-coded) reads magic, ABI and offset from the include (the EightyOne script checks no
  trailer). The EXROM costs 24 B more.
* **Words (HOME):** `FILL` pops y, x into `FILL_X`/`FILL_Y` (16-bit), copies `CURRENT_ATTR`, and jumps to
  `EXROM_CALL_SLOT` with slot 7. `CIRCLE` pops r, yc, xc (16-bit) and attr, slot 8. The HIRES test moves into the
  EXROM (`GFX_MODE` is a sysvar the EXROM already sees). Both bodies about 18 B [E].
* **Veneers left in `GRAPHICS_HOME_TABLE`:** none new. CIRCLE uses slot 0 (`GFX_WRITE_PIXEL`) in HIRES; FILL uses
  none. `GFX_READ_PIXEL` and `GFX_PLOT_CLIPPED` leave HOME (no other caller [S]).
* **HOME RAM cells the EXROM reads:** `GFX_MODE` and the new FILL/CIRCLE cells, all in `include/sysvars.inc` (shared
  by both images); `CURRENT_ATTR` (`core/ts2068.asm`, `$87CB`) is copied by the stub, so `include/exrom_home_ram.inc`
  needs nothing new.
* **With a stock EXROM** (the HOME ROM fitted alone), or a 16K cartridge without chunk 5: the magic check fails and
  FILL and CIRCLE do nothing, as RECT, POLYGON and SPRITE-* do (the owner's O15 approval covers this).

### 6.1 Paging cost per call [S; measured in the oracle]

| | HOME build | Cartridge build |
|---|---:|---|
| `EXROM_CALL_SLOT` (push, page-in, magic/ABI check, `CALL_HL`, slot `jp`, page-out, return) | 388 T | 356 T (the page-in is one `OUT`) |
| Today's direct `call GFX_FILL` / `call GFX_CIRCLE` | 17 T | 17 T |

About 0.1 ms per FILL or CIRCLE: below a single span or a radius-3 circle.

## 7. RAM

| Cells | Where | Notes |
|---|---|---|
| Shadow plane | `$5B00-$72FF` | today's `GFX_FILL_VISITED`, now in screen layout (`+$1B00`) |
| Seed stack | `$7300-$7FFF` | 1,664 entries (today 512) |
| FILL cells: `FILL_X`, `FILL_Y` (2 each), `FILL_ATTR`, `FILL_SP` (2), `FILL_OVF`, span edges and row scratch | sysvars, replacing today's 11 B | sized in the code commit |
| CIRCLE cells: centre (2 × 2), radius/x/y/decision (2 each), attr | sysvars, replacing today's 10 B + `GFX_CLIP_*` 2 B | |

None of these are in `$A000-$BFFF` (chunk 5, paged while the EXROM runs) [checked by an ASSERT in the EXROM].
HIRES's second display file (`$6000-$77FF`) overlaps the shadow and the stack: FILL refuses in HIRES (O15-6).
The cartridge build's interrupt routine is Forth's own (`KBD_ISR_TICK`, DOCK chunk 0) and touches none of this.

## 8. What else changes

Inventory [S] (`1b6fcda`, every `.asm` under `rom/`, the tools, the docs): `GFX_FILL` and `GFX_CIRCLE` each have one
caller (`W_FILL`, `W_CIRCLE`); 61 ROMs include `kernel/graphics/graphics.asm` and so assemble both kernels;
`GFX_READ_PIXEL` is also the pixel-check helper of 13 smoke and test ROMs.

### 8.1 Code

* `kernel/graphics/graphics.asm`: `GFX_FILL*`, `GFX_CIRCLE*`, `GFX_PLOT_CLIPPED` go (every ROM that includes it gets
  896 B back minus what it keeps). `GFX_READ_PIXEL` moves to `kernel/graphics/readpixel.asm`, included only by the ROMs
  that check pixels with it (p9, p10, p46, p49, p51, p5, `test_rect`, `test_polygon`, `test_sprite`, `test_poly_fill`
  and the new `test_shapes`).
* The words: `W_FILL` leaves `core/moregfx.asm` (which keeps `AT-XY`) and `W_CIRCLE` leaves `core/ts2068.asm`; both go
  to a new `core/shapes.asm`, included after `core/rectfill.asm` (it needs `EXROM_CALL_SLOT`) by `rom/forth_boot.asm`
  (both builds) and the Gallery demo. A ROM without the EXROM path no longer has FILL or CIRCLE (decision O15-9).
* `rom/graphics_exrom.asm`: slots 7 and 8, `FILL_IMPL` and `CIRCLE_IMPL`; `include/graphics_exrom_abi.inc` (16 slots,
  ABI 2); `include/sysvars.inc` (cells of section 7; `GFX_FILL_VISITED` becomes the shadow; `GFX_CLIP_*` go).

### 8.2 Smoke ROMs, demos, bench ROMs

| ROM | Today | After |
|---|---|---|
| p5 (CIRCLE poles set) | standalone, no EXROM | CIRCLE check moves to `test_shapes`; p5 keeps PLOT and LINE |
| p17 (`50 50 20 CIRCLE 4 INK 50 50 FILL`, centre set, cell ink 4) | standalone | moves to `test_shapes`; p17 keeps AT-XY |
| p44 (`call W_FILL`; HIRES refusal; fill after HIRES off) | standalone | moves to `test_shapes` (FILL through the EXROM, `GFX_MODE` 1 and 0) |
| p55 (FILL in HIRES leaves HIRES attributes) | standalone | the FILL step moves to `test_shapes`; p55 keeps its HIRES checks |
| p65 (span fill: box, recolour ink 6, cell attributes) | standalone | moves to `test_shapes` |
| p48 (visual, border 6: `2 INK 100 100 30 CIRCLE 100 100 FILL ... ULAPLUS`) | standalone | the shape drawn with `LINE`s and no FILL; it checks ULAplus, not FILL |
| `test_shapes` (new, `tools/rom_list.txt`, expect 4) | | built as `test_rect`/`test_poly_fill` are (bank, `core/rectfill.asm`, own `GRAPHICS_HOME_TABLE`, run with `graphics_exrom.bin`): the checks of p5, p17, p44, p55, p65, plus a clipped CIRCLE and an off-screen FILL seed |
| Blackjack demo (no EXROM; its `CARD-FILL` is a user word using AT-XY/EMIT) | FILL and CIRCLE in its dictionary, unused | gone (O15-9): about +960 B free [E] |
| Gallery demo (has the EXROM path; uses neither) | words + kernels | stubs (O15-9): about +900 B free [E] |
| Bench ROMs (no EXROM; use neither) | words + kernels in the dictionary | gone. `bench_pixel` runs PLOT only: its region moves only by address shifts; reported in the ledger row |

### 8.3 Tools

* `tools/cart_diff.py` and `cart_diff_dumpcmp.py`: the EXROM-state range (`GFX_FILL_SP` .. `POLY_FILL_ERR_ADDR`)
  follows the new cells; new cases (section 9).
* `tools/audit_layout.py`: `test_shapes` in `HOME_TABLE_ROMS`. (Found: the Gallery demo has its own
  `GRAPHICS_HOME_TABLE` and is not in that list; added, or the reason it is left out recorded.)
* `tools/make_dck.py`, `tools/make_eightyone_exrom_dck.sh`, `tools/package_dist.sh`: the trailer offset from the
  include; the EXROM's service list in the dist text.
* `tools/poweron.py`: unchanged (`$5B00-$7FFF` is already exempt as FILL scratch).
* New `tools/shapetest.py` (section 9) and `make shapetest`.

### 8.4 Documents
`docs/forth_tutorial.md` (the graphics section: FILL and CIRCLE move to "from a second ROM", the new argument ranges),
`README.md`, `CHANGELOG.md`, `docs/V2/FORTH_V2_REUSE_AUDIT.md` (ledger), `docs/V2/HANDOFF.md`.

## 9. The oracle (T14: `tools/shapetest.py`, `make shapetest`)

Built on `tools/fharness.py`, ports 10900-10919 (its own range; not run with edtest/harness). Each case restores the
booted snapshot, draws a set-up with words that do not change in this step (`CLS`, `INK`, `PAPER`, `PLOT`, `LINE`,
`RECT`), reads the screen and attributes, runs `FILL` or `CIRCLE` through the interpreter, and compares:

* the screen bitmap and attributes against a Python model (`FILL`: breadth-first 4-connected region of the seed's
  value, bits set, cell attributes; `CIRCLE`: Leap-C's point set on the given values, clipped, cell attributes);
* RAM: everything outside the screen, the shadow/stack pool and the FILL/CIRCLE cells unchanged (`ram_diff`); the
  data stack two (FILL) or three (CIRCLE) cells lower; `BANK_EXROM_DEPTH` 0;
* T-states for the speed table.

| Group | Cases |
|---|---|
| **old** (kept behaviour; must pass on the old build) | FILL inside a box outline, a circle outline (seed 0), a recolour of a solid `RECT` (seed 1), an L-shaped and a spiral region, a whole blank screen, a seed on a lone pixel; FILL in HIRES does nothing; CIRCLE r = 0, 1, 2, 5, 20, 90 at the centre, circles cut by the right and bottom edges, x = y diagonal points, CIRCLE with INK/PAPER; CIRCLE in HIRES (per-scanline attribute) |
| **new** (the spec; fail on the old build) | FILL on a noise screen that overflows 512 seeds (complete); FILL seeds off-screen (`-1 50`, `300 50`, `50 192`, `50 -5`: nothing changes); CIRCLE with negative centre, centre beyond 255/191, radius > 255 (clipped, exact); CIRCLE r < 0 (O15-5) |
| **speed** (gated: new <= old) | FILL: box 160 × 120, full blank screen, solid disc r 50 recolour, a 3-pixel pocket, the serpentine (24,704 one-pixel runs, the span fill's worst case); CIRCLE r 5, 40, 90, 150 (mostly off-screen) |

Run on the old build first; that run with this spec is the oracle commit (`docs/V2/evidence/t14_old_build.txt`, `.json`
for `--compare`). **Result [M]** (`df391e6`, 28 s on 7 workers): `shapetest: 27/33 checks pass (old 17/17, new 0/6,
speed 10/10)`. The new group fails as designed: the noise screen leaves 10,758 pixels unfilled (dropped seeds); `-1 50
FILL` takes x = 255 and fills the whole screen including the editor rows; the circles take low bytes (`128 96 -250`
draws radius 6). Old speed (T, deterministic: the 160 × 120 box twice gives the same count): FILL box 160 × 120
67,492,107, full screen 176,969,016 (about 50 s at 3.5 MHz), disc r 50 recolour 31,091,868, 3-pixel pocket 180,607,
serpentine 128,467,393; CIRCLE r 5 35,868, r 40 280,624, r 90 624,952, r 150 387,725. The tool's own readings are
marked `READING:` in `tools/shapetest.py` (set-up drawings kept above y 160, where the editor does not redraw; large
pictures written into screen RAM after a typed `CLS`; HIRES attributes compared as the ROM lays them out, section 9.1).
### 9.1 Found while writing the oracle: HIRES attributes are laid out linearly

`GFX_SET_ATTR_EXT` (HOME, used by `GFX_WRITE_PIXEL` in HIRES: PLOT, LINE, CIRCLE) stores a scanline's attribute at
`$6000 + y * 32 + col`. In the TS2068's 8 × 1 colour mode the attribute of a pixel byte is at that byte's own address
+ `$2000`, the bitmap's interleaved layout: ZEsarUX `src/cores/core_spectrum.c` fetches it at
`screen_addr_table[scanline * 32]` when `timex_si_modo_8x1()` [S]. Only the first scanline of each third (y = 0, 64,
128) lands where the display reads it; every other scanline's colour lands on another scanline. No test sees it: every
check reads RAM, and ZEsarUX's headless `save-screen` draws only the standard screen. A latent defect outside O15; the
oracle compares HIRES attributes as the ROM writes them today (`circle_hires`), and the owner decides whether the
fix (the address from `GFX_PIXEL_ADDR_SETUP` + `$2000`, a few bytes smaller) goes into this step.

**cartdiff** (`tools/cart_diff.py`, both emulators, HOME vs cartridge byte for byte): new cases `fill_box`,
`fill_recolour`, `circle_clip` (negative centre and big radius), and `loop_all_six` extended to loop FILL and CIRCLE
with the other EXROM words; the EXROM-side state range grows to the new cells. Smoke ROMs that check FILL/CIRCLE
(8.2) keep their checks against the new placement.

## 10. Byte budget [E unless marked]

| | HOME B | EXROM B |
|---|---:|---:|
| Kernel out of HOME (section 3) | −896 [M] | |
| Word bodies (25 + 29 today, about 18 + 18) | about −18 | |
| Service table 8 -> 16 slots | | +24 |
| FILL (span, planes, scan, stack, recovery, HIRES and seed checks) | | about +520 |
| CIRCLE (16-bit midpoint, once-per-point, clip, direct plot, HIRES path) | | about +230 |
| `GFX_READ_PIXEL` (10 B) to `readpixel.asm`, test ROMs only | −10 [M] | |
| **Net** | **about −924: 816 -> about 1,740 free** | **about +774: 4,247 -> about 3,470 free** |

The cartridge build gains the same; Blackjack about +960, Gallery about +900 (section 8.2). Floors in `tools/budget.toml` are raised with ledger rows and
history lines; EXROM's floor is lowered by its own row (the move's cost, not a loss).

## 11. Owner decisions (decided 2026-10-29: all as recommended)

The rule: what is best for the language and its users, not compatibility. The owner answered "All as recommended":
O15-1 (a), O15-2 (a), O15-3 (a), O15-4 (a), O15-5 (a), O15-6 (a), O15-7 (a), O15-8 (a), O15-9 (a).

| # | Decision | Options | Recommendation |
|---|---|---|---|
| O15-1 | Service slots | (a) grow the table to 16 slots, ABI 2 (+24 B EXROM, 7 slots left for K, D, B); (b) one slot 7 for both, with an operation byte (+~8 B, no slot left) | **(a)**: HOME and EXROM ship together (LIB identity already ties them), the cost is EXROM bytes, which are plentiful |
| O15-2 | FILL algorithm | (a) the byte-level rebuild of section 4; (b) today's per-pixel code moved as is | **(a)**: tens of times faster [E], complete; about 30 B more than a move |
| O15-3 | A full seed stack | (a) recovery sweep, always complete (4.5); (b) drop seeds as today, region may stay partly unfilled | **(a)**: a fill that silently leaves holes is a defect users cannot work around |
| O15-4 | FILL seed outside the screen | (a) nothing happens; (b) THROW −43 `OUT OF RANGE`; (c) low bytes as today | **(a)**: as off-screen points of CIRCLE and (after O18 in step D) PLOT/LINE: drawing words clip, they do not stop programs |
| O15-5 | CIRCLE arguments | (a) 16-bit centre and radius, clipped; r < 0 draws nothing; (b) as (a) but r < 0 THROWs −43; (c) bytes as today | **(a)**: circles partly off any edge work; a negative radius from a computed value is treated like an off-screen circle (Leap-C raises an error; Forth's drawing words do not) |
| O15-6 | FILL in HIRES | (a) does nothing, as today; (b) THROW −43 | **(a)**: no change in this step; HIRES fills need their own per-scanline attribute pass and RAM that HIRES does not leave (a later item if wanted) |
| O15-7 | Seed stack size | (a) 1,664 entries (`$7300-$7FFF`, RAM unused today); (b) keep 512 | **(a)**: free RAM; fewer recovery sweeps on busy screens |
| O15-9 | FILL and CIRCLE in the demo ROMs | (a) only ROMs with the EXROM path have them: Gallery keeps them as stubs, Blackjack (no EXROM, uses neither) loses them; (b) Blackjack also gets the EXROM path (bank, `rectfill`) to keep them | **(a)**: Blackjack's prompt never had RECT or POLYGON either; a word that silently does nothing there is worse than an unknown word |
| O15-8 | Speed gate | (a) the oracle's speed table, new <= old in every case, no new bench ROM; (b) also a `bench_shapes` ROM in `make bench` | **(a)**: the bench ROMs are HOME-only images without the EXROM; the oracle measures the real product image |

Not decisions (stated): BREAK inside FILL waits for step B (O6, BREAK in the interrupt routine); with section 4's
speed a full-screen FILL takes well under a second [E]. A shared span painter for RECT and POLYGON-FILL
(POLYGON-FILL paints per pixel through slot 0) is a follow-up, not this step.

## 12. Order of work (each a commit with a measured ledger row)

1. This spec; the owner's answers in section 11.
2. Oracle: `tools/shapetest.py`, the model in `docs/V2/evidence/o15_fill_model.py`, `make shapetest`, the cartdiff
   cases; run on the old build (`docs/V2/evidence/t14_old_build.txt`).
3. Service table to 16 slots, ABI 2 (`graphics_exrom_abi.inc`, `make_dck.py`, EightyOne), no behaviour change.
4. CIRCLE: EXROM slot 8, HOME stub, kernel out of HOME; ledger row; floors.
5. FILL: EXROM slot 7, HOME stub, kernel out of HOME; ledger row; floors.
6. Docs, HANDOFF.

Done when `make edtest test harness tapetest cartdiff fusesave floattest bench repro check shapetest` all pass.
