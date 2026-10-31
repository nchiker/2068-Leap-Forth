# Space — shrink, dead code, RAM: milestone report

**Date:** 2026-10-31. **Status: complete**, apart from one owner decision (section 5: moving cold code to the EXROM,
measured, not done). Branch `v2/step-space` from master `b748a13` (PR #10, step Simplify, merged at the start of the
session; `make test` passed on it). The order is Leap-C's (`project_plan.md` 1.2): measure, remove dead code, shrink,
then move cold code to the EXROM only if that is still needed.

## 1. What changed

- **`make inventory`** (`tools/rom_inventory.py`, after Leap-C's): every routine and table of each image with its size,
  its component, its referrers, and whether anything reaches it from the reset, RST and NMI vectors, `COLD_START`, the
  EXROM's call table or a dictionary word. Today: HOME 580 routines, EXROM 67, none unreachable.
- **Dead code:** `INT_GET_FRAMES` (4 B; nothing called it).
- **Shrink pass:** `kernel/memory/memory.asm` and `kernel/interrupt/interrupt.asm` assemble in page zero's two gaps
  (before the NMI vector at `$0066` and before the table at `$0100`), which were `$FF` fill (156 B); 34 `call X` / `ret`
  pairs became `jp X`; 16 jumps relaxed to `jr` (`tools/relax_jumps.py`; one hot `jp` kept); three inline copies of
  the 16-bit negate call `MATH_NEGATE16` (12 B).
- **`FIND`** keeps its state in registers: a header whose length differs costs 82 T instead of about 180, and the
  routine is 30 B smaller. Every token typed or compiled goes through `FIND` first, so compiling is about a third faster
  (section 4). Its two RAM scratch cells are gone.
- **RAM compaction:** the cells block's 24 free runs (1,915 B, left by Simplify's dead-cell removal) are packed out.
  The cells are `$8000-$8503` (1,161 B used, 123 B at the end for new cells); the float stack (`$8504-$88FF`, 204
  cells) and data stack (`$8900-$90FF`, 2 KB) keep their sizes and move down; **the dictionary starts at `$9100`
  instead of `$9800`: `FREE` reports 16,128 bytes on a fresh machine instead of 14,336**. The line store, sprite
  buffers, UDGs and machine stack do not move. A LIB tape is tied to the exact ROM that saved it (`ROM_IDENTITY`), as
  every ROM change already made it; source text (`SAVE-TEXT`) stays the portable format. The tape, float and shape
  test tools now read `FORTH_DICT_RAM`, `FSTACK_TOP`, `DSTACK_TOP` and `LATEST` from the build instead of literals.
- **Budgets:** the bytes the shrink freed go back to the HOME reserve with ledger entries (Leap-C's practice), so each
  budget is again its component's size.

## 2. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| `SEARCH`, `UPPER`, `LOWER` used the low byte of a length (a hand-made `addr 300` was searched or converted over 44 bytes) | Simplify (scheduled here) | rebuilt with 16-bit lengths: `UPPER` and `LOWER` share one loop, `SEARCH` keeps its state in registers (its 8 RAM cells are free) | −72 |
| `INT_GET_FRAMES` unreachable | Recover (scheduled here) | removed | −4 |
| `tests/sound/ay.fs`: `0.1 BT` could measure 7 frames instead of 6, depending on where in a frame the line started (BEEP's float setup could straddle a tick) | `FIND`'s speed-up moved the phase | the test waits for a tick before it reads `FRAMES` (a test defect; BEEP is unchanged) | 0 |

`tests/string/charfn.fs` adds a 300-byte buffer; each of its five new lines fails on the old build (`UPPER` gives
`65 97`, `LOWER` `97 65`, `SEARCH` `0 44 0` and `-1 44 0`). `tests/core/free.fs` expects 16,128 (the old build prints
14,336). `tools/floattest.py` adds the 16-bit loop boundaries 6399, 6400, 64009, 64010 to its number cases.

**Measured and not taken:** the integer-literal fast path in `NUMBER` (the known defect "integer literals parse 2.5×
slower since floats"). It works (35 B), but compiling 20 literals went only from 957,030 to 918,329 T (4%): the digit
parse is about 2,000 T of a literal's 46,000; the rest is the failed dictionary search that comes first. `FIND`'s
rebuild above was the real fix (957,030 → 616,412 T). The defect is closed.

## 3. Sizes (`make budget`)

| Image | Before | After | Change |
|---|---:|---:|---:|
| HOME free bytes | 1,732 | 2,052 | +320 |
| EXROM free bytes | 3,296 | 3,296 | 0 |
| Dictionary (`FREE` at power-on) | 14,336 | 16,128 | +1,792 |

HOME's +320: page zero 156, tail jumps 34, relaxed jumps 16, `FIND` 30, string words 72, negates 12. HOME components
(bytes): boot 620, kernel 2,638, tape 1,024, interpreter 2,249, integer words 820, floats 3,013, text 1,435, graphics
678, sound 330, console 1,525.

## 4. Tests and speed (`make test`, 2026-10-31, 515 s)

| Suite | Result |
|---|---|
| boot | 9/9 |
| forth | 52/52 files |
| editor | 30/30 |
| float | 66/66 |
| shape | 37/37 (with the speed group) |
| bench | 5/5 |
| poweron | 7/7 patterns, no defined range differs |
| tape | 17/17, extra 1/1 |

`make check` (12/12 layout negative controls) and `make repro` pass.

| Benchmark (`tests/bench/`) | Before | After |
|---|---:|---:|
| literals (new): compile a word of 20 integer literals | 957,030 | 616,351 |
| sieve, 10 passes over 2,000 flags | 143,825,398 | 143,727,541 |
| float, 300 Taylor sums | 141,594,438 | 141,594,342 |
| pixel, 3,000 PLOTs | 34,236,463 | 34,183,736 |
| string, 400 PLACE + STR | 2,018,712 | 2,018,658 |

A definition of 20 dictionary words compiles in 614,623 T instead of 948,069. The running speed of compiled code is
unchanged (the benchmarks time mostly the run; their small gains are their own definitions compiling faster).

## 5. For the owner: moving cold code to the EXROM

Leap-C's order puts this after the shrink, for a component over its budget. None is: HOME has 2,052 B free against a
200 B floor, more than the next steps are expected to need (Words and keys, a faster text path, LINE's 16-bit rebuild,
BREAK). A move also has costs: about 400 T per call, and the moved words need the EXROM. **Recommendation: move nothing
now**; this measured list is the plan for when a step runs short.

| Candidate | HOME bytes | Can it move? |
|---|---:|---|
| Float functions (`core/fpmath.asm`: `FSQRT`, `SIN`, `COS`, `TAN`, `PI`, `RAD`, `DEG`) | 422 | Yes: float-stack work; it would call the float core through the HOME table |
| Float printing (`core/fpprint.asm`: `F.`, `FS.`) | 561 | Yes; `F.` is common, so it would pay the call cost often |
| BEEP and the AY words (`core/beep.asm`, `core/soundext.asm`) | 303 | Yes |
| The printer (`core/printer.asm`) | 333 | Mostly: `LLIST` reads the dictionary headers, hidden at `$A000-$BFFF` while the EXROM is paged in |
| Tape (`storage`, `tapeblock`, `loadtext`, `tapeword`) | 1,024 | No: it reads and writes the dictionary |
| `VLIST` (`core/vlist.asm`) and `LIST-DEFS` | 49 + | No: they read the dictionary |

## 6. Limits

Every result is ZEsarUX's (and Fuse's for the tape suites that use it); there is no hardware.
