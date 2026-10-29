# Leap-C comparison audit of the remaining HOME modules (step L)

Audit section 4.5. Read-only: no ROM source changed. Forth at master `0d45a2f`; Leap-C at `b918527`, exported with
`git archive` and built in a scratch directory (its own `build/` was older than its HEAD). Evidence tags as in the
audit: [M] measured, [S] source, [E] estimate, [L] Leap-measured.

## 1. Method

- **Sizes [M].** A listing sizer attributes every emitted byte of an sjasmplus listing to its source file and to the
  last top-level label. It reproduces the section-3 file totals (graphics 2,596, io 481, interrupt 144). It does not
  count `DS` fill lines longer than four bytes, which matters only for padding (section 3.4).
- **Inventories.** Three routine-by-routine maps, Forth against Leap-C, with bytes on both sides, the Leap-C deltas
  (`platform/UPSTREAM.md` D1-D21) and the Leap-C git history of each file, were produced by delegated agents:
  `evidence/l_graphics_kernel.md`, `evidence/l_medium_modules.md`, `evidence/l_low_modules.md`. They report facts only.
- **Verified by hand**, because a recommendation below rests on it:
  - D6 does not apply: Forth's EXROM sprite code reads `SPRITE_SLOT_SHOWN` (`rom/graphics_exrom.asm:826`), so
    `GFX_SPRITE_INVALIDATE` and its three calls are live [S].
  - D7's eight characters go into slots that are zero in Forth's `KEY_ASCII_TABLE_SYMBOL` (rows 1, 5, 6) [S]: data
    only, no size change.
  - `W_PLOT` and `GFX_LINE` pass y to `GFX_WRITE_PIXEL` unchecked [S], and what that does at runtime [M] (O18).
  - Call-site counts [M] (emitted `call` instructions in the HOME listing): `DPOP_HL` 137, `DPUSH_HL` 105, `W_EMIT`
    31, `FPUSH` 26, `FPOP` 16. `DPOP_HL` and `DPUSH_HL` are 11 B each [M].
  - Page-zero padding [M], read from both images: `$FF` in all six RST gaps (7 B each), `$003E-$0065` (40 B) and
    `$006C-$00FF` (148 B), identical in the HOME and DOCK cartridge builds. The cartridge uses only `$0068-$006B`.
    `tools/budget.py` counts only the trailing fill, so these 230 B are not in the reported free space.
- **Speed.** No benchmark covers these modules except through `make bench` as a whole; speed notes are T-state counts
  from the instructions [S].
- **Provenance.** Everything proposed for adoption from Leap-C is data (D7 table entries, D8/D13 glyphs) or a
  restructuring of Forth's own code (O16). Leap-C's tree passes its 12-byte scan (decision 4); `make check` runs
  Forth's scan on any change.

## 2. Results by module

| Module | Forth B [M] | Leap-C counterpart B [M] | Finding | Recommendation |
|---|---:|---:|---|---|
| Graphics kernel | 2,596 | 2,066 (HOME) | 27 routines pair by name: 5 identical, 14 identical except address operands, 8 differ (D6 calls, D8 table and glyphs, `ATTR_DEFAULT` $44 against $38, one `jp`). Forth-only: `GFX_FILL` and its helpers (487 B), `GFX_CIRCLE` and its helpers (368 B), `GFX_SPRITE_INVALIDATE` (11 B). Leap-C-only: its sprite get/put kernel and `GFX_PRINT_STRING_ATTR` (282 B), for jobs Forth does elsewhere | Keep the paired routines. Adopt D8 (O3, step K) and D13 (O17, K). D6: not applicable. FILL/CIRCLE: O15 |
| Graphics words | 766 | 253 | Same kernel calls; Leap-C's are thinner because C passes arguments in a frame and Forth words carry dictionary headers (203 B). PLOT and LINE do not clip (O18). AT-XY has no range check | Keep; fix O18 |
| Strings | 901 (string 455, stringext 446) | 150 | Different word sets: Forth's counted strings and descriptors against C's NUL-terminated library. `VAL` refuses `" 12"` and `"+5"`, which `atoi` accepts: a Forth semantic, not a defect. The audit's 989 B probably included `core/dotquote.asm` (88 B) | Keep; nothing to replace |
| Output words | 327 | 316 | `EMIT` (157 B) handles 64 columns, wrap and scroll, which `LIB_PUTC` (30 B) leaves to `GFX_PRINT_STRING_ATTR`. `UDIV10` (15 B) is a fixed /10; Leap-C's general `RT_UDIV` (31 B) arrives with O10 | Keep. Step F: once `RT_UDIV` is in, measure `UDIV10` as `ld bc,10 / call RT_UDIV` (bytes against the `.` speed) |
| Keyboard, interrupt | 625 | 566 | io and interrupt are V2's code in both. Forth has neither D4 (BREAK in the ISR) nor D7 (the eight symbol keys); it has V2's `STICK_READ` (30 B) and `IO_CHECK_BREAK` (18 B), which Leap-C's V2 base removed and Forth's words `STICK` and `BREAK?` use. `IO_DECODE_KEY` is 132 B against 114: Forth repeats the `row*5+bit` lookup three times | D7 data in K (O3). O16 in K. D4 is step B (O6), as planned |
| Integer words | 680 | — | `MATH_ABS16`, `MATH_NEGATE16`, `MATH_COMPARE16` are byte-identical (after relocation). Multiply and divide are O10 (F) | Keep |
| Sound words | 183 | 17 | `SOUND_WRITE` and `AY_WRITE` are the same 10 B except the bound (register 0-16 against 0-15) | O19 (Z) |
| Boot | 597 | 39 + EXROM shell | Cold-start sequences match where they overlap (stack, RAM clear including the UDG table, `$FF` port baseline, `KBD_ISR_INIT`, `im 1`, `ei`, chime); Leap-C's two fixes there (UDG clear, D14) are already in Forth (`861a823`, `684065f`). 238 B of the 597 are `$FF` padding | O13, O14 (Z) |
| Misc I/O | 166 | — | `IO_READ_KEY` identical; `KEY?` deliberately does not consume (Leap-C's `inkey` does) | Keep |
| Interpreter, DO/LOOP, errors, 64 columns, printer | — | none | No value, as section 4.5 judged; step Z covers them | — |

## 3. New O-items and where they go

| # | Item | Evidence | HOME Δ | Step |
|---|---|---|---:|---|
| O13 | **RST vectors for the data stack.** `DPOP_HL` (137 call sites) and `DPUSH_HL` (105) moved into page zero (`$0008` and `$0018`, 11 B each, in the free RST slots) and called with `rst` (1 B) instead of `call` (3 B). Each call also gets faster: `rst` is 11 T, `call` 17 T. Leap-C does the same with its most-used runtime helpers (`RST_LDI`, `RST_STI`, `RST_ENTER`, `RST_LEAVE`). `W_EMIT` (31 sites) through `rst $28` / `jp W_EMIT` saves 2 B per site at +4 T per `EMIT`; measure. `FPUSH`/`FPOP` wait for F | counts and sizes [M] | about −480 [E] (242 sites × 2, plus the 22 B moved out of `core/dict.asm`) | Z |
| O14 | **Page-zero padding.** 230 B of `$FF` in both builds (section 1), not counted as free by `budget.py`. Small fixed routines or tables placed there recover their size; O13 uses 22 B of it. `GRAPHICS_HOME_TABLE` stays at `$0100` (EXROM ABI). Both builds must keep identical bytes outside the `ROM_ID_SKIP_*` ranges | [M] | up to about −200 [E] beyond O13 | Z |
| O15 | **FILL and CIRCLE kernels to the EXROM.** `GFX_FILL` with its five helpers (487 B) and `GFX_CIRCLE` with its three (368 B) are Forth-only; Leap-C removed them from HOME into a loadable extension. In the EXROM beside RECT and POLYGON, the words keep thin HOME stubs. Cost: EXROM +~860 B (6,682 free, of which E needs 2.2-2.6 KB). **Owner decision:** with a stock EXROM (the Forth HOME ROM fitted alone) CIRCLE and FILL would then stop working, as RECT, POLYGON and SPRITE-* already do | sizes [M] | about −820 [E] | owner; after E |
| O16 | `IO_DECODE_KEY` shares its `row*5+bit` table lookup between the three tables, as Leap-C's does | 132 against 114 B [M] | −18 [E] | K |
| O17 | D13: the glyphs of `1` and `l` (Forth's differ in two pixels, so `l.0` reads as `1.0`). Owner-approved in Leap-C (`f209f21`). Data only | [S] | 0 | K |
| O18 | **PLOT and LINE do not clip** (latent defect). `W_PLOT` and `GFX_LINE` hand any y to `GFX_WRITE_PIXEL`, which indexes `ROW_BASE_TABLE` (24 rows) with `y >> 3` up to 31. Measured on ZEsarUX: `100 192 PLOT` to `100 255 PLOT` write nothing in RAM, because the 16 bytes after the table are zero padding and font data, which make ROM addresses (`$000C`, `$077C`). Any change to the bytes after `ROW_BASE_TABLE` turns it into a RAM write. Fix: a `cp 192 / ret nc` check in `GFX_WRITE_PIXEL`, which covers PLOT, LINE and the EXROM's slot-0 callers | [S], [M] | +4 [E] | D |
| O19 | `SOUND_WRITE` and `AY_WRITE` are duplicates except the bound (`cp 17` against `cp 16`). Merge. Whether `SOUND` keeps accepting register 16 (documented as intended in `core/sound.asm`) is the owner's call | [S] | −8 [E] | Z |

Changes to existing items:

- **O3 / step K** gets cheaper: D7's keys are data in existing zero slots (0 B), D8's glyphs +64 B and table entries
  +16 B, O16 −18 B: about **+62 B** plus the new words, against the +~100 B of section 8.
- **O10 / step F**: add the `UDIV10` measurement above.
- **Step Z** gets O13, O14 and O19 on top of its section-4.4 scope, and the `GFX_LINE` `jp .loop` (Forth's comment
  gives the `jr` displacement as −126, which fits): −1 B.
- **Step B** (O6): Leap-C's D4 is 8 B in `KBD_ISR_TICK` plus its `RT_BREAKREQ` (31 B); Forth's equivalent would set a
  latch for `BREAK?` and the loop words to poll.
- **D6** (Leap-C's 25 B deletion) does not apply to Forth.

## 4. Order

O13 and O14 are the largest recoveries the audit has found after O5, and E's line store and engine evaluation are
measured against the HOME budget. The plan puts Z after E and F so that code they rewrite is not shrunk twice. That
reason does not hold for O13: it is a mechanical change of call form, so code E and F write afterwards simply uses
`rst` from the start, and nothing is done twice. **Recommendation:** run O13 as its own small step before E's code
(after E's spec and oracle, which do not depend on it), so that E is measured against the larger budget and the
engine evaluation compares like with like. O14 and O19 stay in Z.

**Decided by the owner (2026-10-28):** O13 before E's code; O15 approved, after E; O19 merges to registers 0-15
(audit section 10, decisions 7-9).

## 5. Not determined

- The EXROM bodies of RECT, POLYGON and SPRITE-* were not compared (they are not in section 4.5's scope; Leap-C has
  no counterpart in HOME).
- Leap-C's loadable `libs/shapes.asm` (circle, box) was not measured.
- Behaviour statements are source readings except O18, which was run.
- No hardware: every runtime statement here is ZEsarUX's.
