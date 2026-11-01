# Polygon edges — POLYGON and POLYGON-FILL with a corner off the screen: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-polygon-edges` from `v2/step-manual` (PR #19). The
ROADMAP's known defect from step Display speed: POLYGON and POLYGON-FILL kept each corner's low byte, so a corner off
the screen wrapped to the other side (-20 was x 236), the last shape words that did. The owner asked that the
remaining defects follow how 2068-Leap-C handles the same problem.

## 1. What was built

- **How Leap-C handles it.** Leap-C has no polygon; its `draw()` and its shapes library's `box()` move an off-screen
  coordinate to the nearest edge ("the line is then drawn between the moved points, which is not always the line you
  meant"); `plot()` and `circle()` leave off-screen points out.
- **The same here.** `POLY_POP_VERTICES` (`core/polygon.asm`, shared by both words) moves each corner to its nearest
  edge, x 0-255 and y 0-191, as it pops it. Nothing wraps or is drawn off the screen; a shape with a corner off the
  screen is drawn through the moved corner, which the manual says (the entries and Part 5's Graphics). A count above
  255 is refused (259 was read as 3).
- **Why not exact clipping** (as LINE, CIRCLE and, since step Manual, RECT): it was estimated at +15 B HOME and 48 B
  RAM for the outline and +100-150 B EXROM for the fill's scanline clipping. Leap-C's way costs 11 B, no RAM and no
  EXROM, and ends the wrap; it is Leap-C's documented behaviour for the same case.

## 2. Tests

`tests/graphics/polygon.fs` gains four lines (an outline and a fill with a corner left of the screen, a fill with
corners above it, a count of 259); they fail on `800e979` and on the Manual step's tip (the corner wrapped to x 236).
The graphics tests and the manual's Parts 4 and 5 pass (79/79); `make check` passes.

## 3. Sizes

| Image | Before (step Manual) | After |
|---|---:|---:|
| HOME free | 1,936 B | 1,924 B (+26 B the edges, -15 B the pop loop on a pointer and DJNZ; ledger +11 B) |
| EXROM free | 3,136 B | 3,136 B |
| The cartridge's HOME image free | 1,741 B | 1,730 B |

## 4. The other two known defects, against Leap-C

- **A cartridge's power-on CRC** (up to 2.7 s): Leap-C's cartridge plan checks the ROM identity at run time and leaves
  the image's integrity to the build (`tools/forthcart.py` already checks the CRC when it packs). Dropping the power-on
  CRC would follow it and save the time and bytes; it reverses the Cartridge step's choice, so it is the owner's.
- **LINE to an end far off the screen** (up to 3 s near ±32,768): Leap-C's `draw()` moves the end to the edge, fast
  but not the line meant; Forth's exact LINE is kept.

Emulators only (ZEsarUX 13.0).
