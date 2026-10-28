# Leap-Forth V2 — Platform Reuse Audit, Section Ledger and Rebuild Plan

Phase 1 deliverable of `docs/V2/project plan - Leap-Forth V2.md`.

Revisions audited:

| Repository | Commit | Date |
|---|---|---|
| 2068-forth (Leap-Forth V1) | `fff5259` | 2026-09-14 |
| 2068-Leap (V2, v2.1.0-emu.1 line) | `b30ca0c` | 2026-10-27 |
| 2068-Leap-C | `a950021` | 2026-10-28 |
| ts2068-debug | `98f3555` | 2026-10-26 |
| z80sim | `13c9bce` | 2026-10-27 |

Forth was scaffolded on 2026-09-01 from 2068-Leap commit `546ceda` (V1 kernel). The six shared
kernel files (bank, graphics, interrupt, io, math, storage) were byte-identical to that commit at
scaffold time. 2068-Leap has had 321 commits since.

Figure tags, following Leap's convention:

- **[M]** measured here, from a clean build of the revision above
- **[L]** measured by 2068-Leap or 2068-Leap-C, quoted from their docs or commits
- **[E]** estimate, not yet measured

---

## 1. Method: rebuild each section back, do not drop in

The lesson of Leap V2 is that the space and the capability came from **rebuilding each section
against a specification**, with the older implementation as reference and test oracle, rather than
from dropping new code into place or from incremental shrink passes.

Evidence from 2068-Leap's history:

| Approach | Result |
|---|---|
| Incremental shrink of V1 (Sept 2026) | V1 at 18 B HOME / 32 B EXROM free (`c073137`, `e56a33d`). `docs/CONSOLIDATION_AUDIT.md`: V1 "already well-consolidated", ~40-60 B left to find. R10.5 shrink pass: 291 B total [L] |
| Rebuilt language core | V1 core 13,893 B measured; rebuilt core estimated 5,010-7,220 B with procedures and transcendentals added (`docs/REWRITE_ROM_BUDGET.md`) [L] |
| Float core rebuilt in Leap-C | V2 calculator + float formatting 1,929 + 236 B → `fpcore` 1,464 B, now rounding, overflow is an error [L] |
| Tape block I/O rebuilt clean-room in Leap-C | 331 → 316 B; distortion tolerance 54/71 → 67/71; no stock-ROM code [L] |
| Block-graphics glyph builder rebuilt | 48 → 36 B; no stock-ROM code [L] |
| `GFX_CLEAR_ROW` rebuilt | 24,786 → 6,498 T per row [L] |

Leap-Forth V1 has followed V1 Leap's path: `docs/PROJECT_PLAN.md` records HOME free space falling
521 → 49 → 106 → 66 B through successive shrink passes. Further shrink passes will not fund the
editor, the new float system or the storage rebuild. Rebuilds will.

### Rules for every rebuilt section

1. **Specify first.** Write the section's contract (words, register interface, RAM cells, error
   behaviour) before code. Leap and Leap-C code is reference material and test oracle, not
   paste-in source. Leap-C's per-subsystem specs (`spec.md`, `docs/TAPE_SIGNAL_SPEC.md`) are the
   model.
2. **Ledger row before and after.** HOME bytes, EXROM bytes, RAM bytes and the relevant T-state
   figure, each tagged [M]/[L]/[E]. A section is not done until its "after" row is [M].
3. **Behaviour-preserving phases are byte-checked.** When a phase is not meant to change behaviour,
   every smoke ROM's border result must be unchanged.
4. **Placement is part of the rebuild.** Every rebuilt section decides HOME vs EXROM explicitly.
   The EXROM (chunk 5) has 6,682 B free [M]; HOME has 68 B [M].
5. **Provenance is part of the rebuild.** Every rebuilt section passes the 12-byte stock-ROM scan.
6. **Keep Forth Forth.** The inner interpreter, dictionary format, stacks and colon-call mechanism
   are measured, not rebuilt, unless Phase 2/3 benchmarks justify it.

---

## 2. Current budget

| Image | Size | Used | Free | Source |
|---|---:|---:|---:|---|
| HOME ROM (`build/forth_boot_rom0.bin`) | 16,384 | 16,316 | **68** | [M] last non-pad byte $3FBB |
| Graphics EXROM (`build/graphics_exrom.bin`, chunk 5 at $A000) | 8,192 | 1,510 | **6,682** | [M] |

Both scratch builds were byte-identical to the committed `build/` images.

**Proposed reserve target:** 200 B HOME, 150 B EXROM. This is the provisional target Leap V2 uses
(`docs/V2_ROM_RAM_BUDGET.md`, owner decision 4), proposed here for owner decision. Today Forth has
no reserve guard in `make check`.

**Constraint:** the `-DCARTRIDGE` build cannot page the EXROM (`fd36edd`). Every section moved to
the EXROM is absent from the cartridge build until that is fixed (rebuild R1 below).

---

## 3. Section ledger (HOME ROM, baseline)

Bytes per source file, attributed from the HEAD listing (`forth_boot.lst`). The attribution covers
16,109 of the 16,316 used bytes; the remaining ~200 B are not attributed [M].

| Section | Files | HOME B [M] | Audit class | Reference for rebuild | Target |
|---|---|---:|---|---|---|
| Graphics kernel | `kernel/graphics/graphics.asm` | 2,624 (of which font ~688) | 2 Adapt | Leap V2 `kernel/graphics` fixes; Leap-C D8, D12, D13, D21 | Smaller; faster scroll/clear |
| **Float** | float, floatmul, floatdiv, floatsqrt, floattrig, floatprint, floatconv, decimal | **2,129** | 2 Adapt (rebuild) | Leap-C `src/runtime/fpcore.asm` + `tools/fpmodel.py`; Leap V2 `rom/exrom_v2_float_fn.asm` (SQR, SIN, COS, TAN) | ~equal size, 5-byte format, see §4.2 |
| **Console + source text** | editor, recall, loadtext, input | **1,773** | 2 Adapt (rebuild) | Leap V2 `rom/exrom_editor.asm` (625 B engine); Leap-C `src/shell/shell.asm` | Smaller HOME, full-screen in EXROM, see §4.3 |
| **Storage** | `kernel/storage/storage.asm` 722, `core/storage.asm` 252 | **974** | 2 Adapt (rebuild) | Leap-C `src/runtime/tapeblock.asm`; Leap V2 `kernel/storage/storage.asm` header logic | Clean-room, versioned, see §4.1 |
| Strings | string, stringext | 906 | 4 Retain | — | Measure only |
| Interpreter | interp | 706 | 4 Retain | — | Measure only (Keep Forth Forth) |
| Sound | beep 429, soundext 153, sound 87 | 669 | 3 Measure | Leap V2 `rom/v2_ay_beep.asm` | Est. −350-400 B [E], owner decision |
| Keyboard | `kernel/io/io.asm` | 519 | 2 Adapt | Leap-C D7 (missing `[ ] \ { } \| ~ ^`, dead keys removed) | Adds keys, −19 B dead code [L] |
| 64-column mode | mode64 | 471 | 4 Retain | — (no Leap counterpart) | Measure only |
| Kernel math | `kernel/math/math.asm` | 411 | 2 Adapt | Leap-C `RT_UMUL/RT_UDIV` (Leap back-port 1.5) | Faster divide (60000/7: 3,584 → 1,479 T [L]) |
| Boot / cold start | forth_boot | 417 | 2 Adapt | Leap V2 `67c7137` item 2.2 | Fix UDG clear (+~8 B) |
| DO/LOOP | doloop, loop, loopext | 479 | 4 Retain | — | Measure only |
| Printer | printer | 338 | 4 Retain | — | Provenance review (cites ROM disassembly) |
| Dictionary, compile, control | dict, control, forget, create, variable, does, tick, immediate, vlist | 965 | 4 Retain | — | Measure only |
| Errors | throwcatch, abortquit | 252 | 4 Retain | Leap V2 BREAK latch (`8ee4f1a`, `fa8e5b9`) | Add ISR BREAK latch |
| Interrupt | `kernel/interrupt/interrupt.asm` | 144 | 2 Adapt | Leap V2 BREAK latch | +~14 B [E] |
| Banking | `kernel/bank/bank.asm` | 46 | 2 Adapt | Leap-C D14 (no `di` while paging) | −2 B, cartridge paging (R1) |
| Remaining core words | arith, compare, stackops, logic, array, color, print, etc. | balance | 4 Retain | — | Measure only |

Known dead code [L, from the audit's unreferenced-symbol scan; re-verify at rebuild]:
`IO_ANY_KEY_DOWN` 19 B, `GFX_PUTCHAR_OVER` 16 B, `MODE64_READ_PIXEL` 10 B, SYMBOL SHIFT A/S
`KEY_NEXT_ERROR`/`KEY_PREV_ERROR` (~19 B with D7).

### EXROM ledger (baseline)

| Section | EXROM B | Notes |
|---|---:|---|
| RECT, POLYGON, POLYGON-FILL, SPRITE-* | 1,510 [M] | `rom/graphics_exrom.asm`; slots 6 and 7 of the 8-slot service table unused |
| Free | 6,682 [M] | Budget for the full-screen editor, CRC, optional float functions |

---

## 4. Rebuild plans for the three primary sections

### 4.1 Storage (rebuild S)

**Today.** Words `SAVE-LIB`/`LOAD-LIB` (dictionary image: LATEST + bytes) and
`SAVE-TEXT`/`LOAD-TEXT` (source). The image passes through an 8 KB buffer at $D000, limit 8,190 B,
and has no identity check, so a tape from another build loads into a mismatched ROM.
`kernel/storage/storage.asm` describes its block I/O as "a direct, verified port of the real ROM's
SA-BYTES/LD-BYTES". A 12-byte scan finds stock-ROM runs of up to 45 B in
`STORAGE_SEND_BLOCK`/`STORAGE_RECEIVE_BLOCK`. Forth's README claims MIT and there is no NOTICE.

**Reference.** Leap V2 has already done this rebuild (`c2415f8`, "Back-port phase 3: no
stock-ROM-derived code left"): Leap-C's `tapeblock.asm` unchanged, aliased to
`STORAGE_SEND_BLOCK`/`STORAGE_RECEIVE_BLOCK`. The register contract matches Forth's, except that
the sender returns carry set when the block was sent whole and the receiver returns DE = bytes not
yet stored.

**Rebuild contents.**

1. Clean-room block I/O (316 B vs 327 B, −11 B [L]). Same wire format and timing; old Forth tapes
   still load.
2. Header logic from Leap V2: SPACE-abort fix (no data block after an aborted header, `67c7137`
   item 2.1), user abort ends the header search, optional VERIFY mode.
3. Image format: version/ROM-identity word in the header plus CRC-16/CCITT over the image
   (Leap V2 `rom/v2_saveall_crc.asm`, ~45 B [L]). `LOAD-LIB` of a mismatched image fails cleanly
   before writing anything. Use the build stamp (`tools/build_stamp.py`) as the identity, not a
   ROM CRC (Leap's ROM CRC takes ~2.4 s [L]). Old unstamped images need a legacy-accept rule.
4. Save the dictionary in place instead of through the $D000 buffer. This lifts the 8,190-byte
   limit to the dictionary budget **and** frees the $D000 workspace for the editor (§4.3).
   [E] Check what lives in the 8 bytes below $9800 before relying on the in-place header trick.
5. Words: keep `SAVE-LIB`, `LOAD-LIB`, `SAVE-TEXT`, `LOAD-TEXT`; add `VERIFY-LIB`, `VERIFY-TEXT`.
   Defer loadable precompiled modules to plan Phase 13.

**Placement.** Block I/O in HOME (needed by every build). CRC and VERIFY may go to the EXROM if
HOME is short, at the cost of the cartridge build until R1.

**Tests to port.** Leap V2 `tools/check_storage_contract.py`, `tools/qtapetol.py`,
`tools/check_provenance.py`; Leap-C `tools/tapetol.py` and the `audio2tape` decode. Keep Forth's p7
(fake transport) and p53 (real .TAP). Add old-ROM ↔ new-ROM tape cross-loads.

**Open item.** Tape I/O is emulator-verified only in all three projects; real cassette remains a
Phase 16 item.

### 4.2 Float (rebuild F)

**Today** [M sizes, source facts from `core/float.asm`]: 3-byte float (16-bit signed mantissa,
8-bit exponent, ~4.5 digits), separate IY float stack (3-byte cells, $8C00-$9000). Truncating
arithmetic, no overflow or divide-by-zero error, `F.` prints 4 truncated decimals, SIN/COS from a
17-entry table (worst error ~1e-3). 14 float words; no `F@`, `F!`, `FDUP`, `F<`, `FNEGATE`,
`FVARIABLE`. Provenance is clean (native, not a port).

**Reference.**

| | Forth V1 | Leap-C `fpcore` | Leap V2 |
|---|---|---|---|
| Format | 3 B | Sinclair 5 B | Sinclair 5 B |
| Digits | ~4.5 | ~9.6 | ~9.6 |
| Rounding | truncate | nearest | nearest |
| Errors | none | error on overflow / ÷0 | same |
| Transcendentals | table, ~1e-3 | none | SQR, SIN, COS, TAN, ~2 ulp |
| Size | 2,129 B [M] | 1,464 B core [L] | +~150 B SQR, ~413 B trig [L] |
| Test oracle | smoke ROMs | `tools/fpmodel.py` (bit-exact), `tools/floattest.py` | 16,000/16,000 match Leap-C model [L] |

**Rebuild contents.**

1. Spec: 5-byte cells on the IY float stack; word set below; error behaviour via `THROW`.
2. Engine: `fpcore` arithmetic, compare, FRI/TOI, FTOA, ATOF, called directly (not through V2's
   RST $28 dispatcher).
3. SQR (exponent-halving Newton step, `54cd877`) and SIN/COS/TAN (minimax series) from Leap V2.
   Keep Forth's radian interface: `SIN`/`COS` take radians, and `RAD`/`DEG` remain.
4. Shared number parser for float literals and `NUMBER` (ATOF with integer fallback).
5. New words where cheap: `FNEGATE`, `F<`, `F=`, `FDUP`, `F@`, `F!`, `FVARIABLE`.

**Budget.** Replace 2,129 B with ~1,464 + ~150 + ~450 + ~200 glue ≈ 2,260 B [E], roughly flat.
Measure; if HOME is short, the transcendentals move to the EXROM.

**Costs and risks.**

- Float-stack depth falls from ~341 to ~204 cells in the same 1 KB.
- Smoke ROMs that hard-code 3-byte expectations must be regenerated: p8, p18, p19, p22, p23, p29,
  p30, p34, p35, p42 [L, from the audit].
- `fpcore`'s RAM cells must fit Forth's free $8xxx gaps; re-run `tools/audit_layout.py`.
- Speed: a 5-byte multiply (~20 kT [L]) is likely no faster than today's; record before and after
  in `bench_float`.
- No saved user data breaks, since V1 has no float store words.

**Provenance note (owner decision).** `fpcore.asm` describes itself as the "re-engineered" V2
calculator, and V2's calculator was partly ported from the Spectrum ROM. It passes Leap-C's
12-byte provenance scan, and Leap V2 accepted it as MIT. Forth should record the same position in
its NOTICE.

### 4.3 Console, source text and full-screen editor (rebuild E)

**Today** [M sizes]: `core/editor.asm` is a 998-byte HOME line editor (128-character buffer over at
most 4 rows, word-wrapped). `recall.asm` (435 B) and `loadtext.asm` (169 B) keep an 8 KB flat text
workspace at $D000 (`LOADTEXT_BUF`). `RECALL` and `LIST-DEFS` find `: name ... ;` spans by text
scan; old copies remain and new ones shadow them. `SAVE_LOAD_TEMP_BUF == LOADTEXT_BUF` is asserted
in `rom/forth_boot.asm`, so a `SAVE-LIB` wipes the source workspace.

**Reference.**

- Leap V2 `rom/exrom_editor.asm`: a 625-byte generic engine (single-line edit buffer, word-wrap,
  two hooks) that knows nothing about BASIC [L]. It includes the later fixes: redraw from the
  active line down (`5504f40`), ED3/ED7 wrap fixes (`695121b`), BREAK and keys below $20
  (`8ee4f1a`).
- Leap-C `src/shell/shell.asm`: the multi-line view with BASIC removed, storing raw-text records
  (`SH_STORE_EDIT`). Measured parts: redraw 470 B, navigation 209 B, line store 166 B, view 94 B,
  draw 94 B [L] (`docs/milestones/M5.md`).
- Record store: `[len:2][text][CR]`, lines ≤ 127 characters, no line numbers.

**Rebuild contents: one engine, one line store, two views.**

1. **Line store.** Turn the $D000 workspace into a record store shared by the console, `RECALL`,
   `LIST-DEFS`, `SAVE-TEXT`/`LOAD-TEXT` and `EDIT`. This depends on S.4, which frees $D000 from
   `SAVE-LIB`. `INTERPRET_RUN` treats CR as whitespace (the three `cp " "` tests in
   `core/interp.asm`).
2. **Engine.** Evaluate the 625-byte V2 engine as the console editor too. It does the same job as
   the 998-byte `core/editor.asm`. If it can serve as the HOME console editor, the console shrinks
   (~−370 B [E]) and the full-screen editor shares it. This is the main opportunity of rebuilding
   instead of dropping in; measure it first.
3. **Full-screen view** (Leap-C shell redraw, navigation, view) in the EXROM: ~1.2 KB plus ~350 B
   of line-store routines [E]. Total EXROM ~2.2-2.6 KB [E] of 6,682 B.
4. **`EDIT name`** finds the newest `: name` span by the existing scan, opens the view there, and on
   exit interprets only the changed lines (ordinary redefinition, no `FORGET` replay). Editing in
   place also ends the stale-copy problem.
5. **`EDIT "unit"`**: named source units, saved with `SAVE-TEXT`. Resolved in plan Phase 11
   (`docs/FORTH_SOURCE_MODEL.md`).
6. Zero cost to ordinary execution: the editor is a separate session with no ISR or
   inner-interpreter hooks. Restore the console screen and `PRINT_ROW`/`PRINT_COL` on exit.

**Tests.** Port Leap-C `tools/shelltest.py` (40 cases; checks that the screen after every key
equals a full redraw, and measures typing cost) as the redraw/flicker regression suite the plan
requires. Use Leap V2 `tools/v2_prod_regress.py` (ED3, ED4, ED7) for case ideas. Do not port the
BASIC-bound `rom/test_editor_auto.asm` or `rom/test_v2_editor_integration.asm`.

**Risks.** HOME budget; cartridge build without EXROM (R1); dictionary growth into $D000; the
127-character line limit; EXROM code is position-dependent at $A000.

---

## 5. Other findings

| # | Item | Class | Reference | Forth file | Cost [E] | Notes |
|---|---|---|---|---|---|---|
| O1 | Cold start does not clear `UDG_TABLE` ($F180 is above the $8000-$F000 clear) | 2 | Leap `67c7137` item 2.2 | `rom/forth_boot.asm` ~217 | +8 B | **Verified bug**: CHR$ 144-164 show power-on garbage |
| O2 | Stock-ROM bytes in the block-graphics glyph builder (two 12-byte PO-GR-2 runs) | 2 | Leap-C D21, Leap `c2415f8` | `kernel/graphics/graphics.asm` ~467 | −12 B | Licensing |
| O3 | Missing characters `[ ] \ { } \| ~ ^` and backtick: no glyphs, no keys, so no `[']`, `[CHAR]`, `\` comments, `[ ] LITERAL` | 2 | Leap-C D7, D8; Leap `8a52ab9` (72 B glyphs), `0b35b68` (direct glyph table, −38 B) | `kernel/io/io.asm`, `kernel/graphics/graphics.asm`, new words | ~+100 B + words | Significant Forth-standard gap |
| O4 | `GFX_CLEAR_ROW` writes attributes per character via `GFX_SET_ATTR` | 2 | Leap `kernel/graphics/graphics.asm` (back-port 4.1, 5.8; `22b4999`) | `kernel/graphics/graphics.asm` ~1045 | smaller | 24,786 → 6,498 T per row [L]; runs on every scroll |
| O5 | AY BEEP; current BEEP runs with interrupts off for the whole note | 3 | Leap `rom/v2_ay_beep.asm` (`6493615`); speaker kept as optional package | `core/beep.asm`, `kernel/sound/sound.asm` | −350-400 B | Owner decision: speaker → AY |
| O6 | BREAK latch in the ISR so runaway loops can be stopped | 2 | Leap `8ee4f1a`, `fa8e5b9` | `kernel/interrupt`, loop words, `THROW` | +~14 B + polls | Measure loop cost (Phase 15 gate) |
| O7 | No pause/timing word | 2 | Leap `AY_WAIT_FRAMES` (HALT counting, frame-wrap safe, 7 B) | new word `MS` or `PAUSE` | ~+20 B | `CHIME_DELAY` has the same wrap class, harmless at boot |
| O8 | `di` in `BANK_PAGE_EXROM_IN/OUT` drops frame interrupts | 2 | Leap-C D14 (47/11,232 frames lost [L]) | `kernel/bank/bank.asm` | −2 B | Low impact today (graphics EXROM only) |
| O9 | `SOUND` rejects register 0 | 3 | Leap `6493615` | `core/sound.asm` ~126 | −3 B | Optional |
| O10 | Faster unsigned multiply/divide | 2 | Leap-C `RT_UMUL/RT_UDIV` | `kernel/math/math.asm` | ± | 60000/7: 3,584 → 1,479 T [L] |
| O11 | Dead code | — | — | io, graphics, mode64 | −64 B | Verify each before removal |
| O12 | `jp` → `jr` | — | Leap-C `tools/relax_jumps.py` | various | ≤ −30 B | Many sites are deliberately `jp`; lowest priority |

**Provenance summary** [L, scan of HEAD against `48.rom`, `tc2068-0.rom`, `tc2068-1.rom`]: the only
12-byte matches are the tape block I/O (§4.1) and the glyph builder (O2). Files written while
reading the ROM disassembly but showing no byte match: `core/printer.asm`, `kernel/sound`,
`kernel/mode64`, `core/stick.asm`. Whether those need a rewrite is an owner decision; Leap V2's
NOTICE accepts rewrites from the interface as clean.

---

## 6. Build, test and debug infrastructure

Leap V2 and Leap-C rebuilt their tooling as well as their ROM code, and the shared debugger and
simulator have moved on since Forth's last commit. Forth's tooling is still at its September state.

### 6.1 Forth today [M]

- `Makefile`: 685 lines, 77 assembler calls, 64 hand-written `forth-smoke*` rules, all `.PHONY`,
  each `mkdir` + assemble + `mv <name>_rom0.bin build/`. `all:` lists every target by hand.
- **No `make test`.** The ~65 smoke ROMs only assemble; the verdict is a border colour read by hand.
  68 of 69 smoke/test ROMs use the same "border GREEN (4) = pass" convention (`forth_smoke_p48.asm`
  is the exception), so a uniform runner is feasible.
- `make check` is static only: `check_asm.py`, `check_z80_opcodes.py`, `audit_layout.py`.
- CI (`.github/workflows/build.yml`) builds but states it does not run the smoke ROMs.
- `make test-rect` and similar (README) only assemble; the name is misleading.
- `tools/sjasmplus_strict.sh` rejects only truncation warnings. All 77 ROMs assemble with
  `--msg=war` at **0 warnings** [L, audit scratch build], so a stricter wrapper costs nothing.
- ts2068-debug is not used anywhere in Forth's tools or Makefile.
- `tools/z80sim/` is a September copy (`sim.py` 1,033 lines, not called by anything).
- `rom/bench/` (sieve, pixel, float, string) is untracked and not wired into make.

### 6.2 What changed elsewhere

**ts2068-debug** (`~/ts2068-debug`, HEAD `98f3555`, all 21 commits since 2026-09-17):
symbol breakpoints and `run --until SYMBOL`, watchpoints, `mem-snapshot`/`mem-diff`, `diagnose`
(registers, symbolised stack, trace, banking), `timex` (banking, video, AY, border), `type`/`press`
keyboard input, `screenshot` and `screen-hash`, a Python test-runner API that captures state on
failure, fast emulation by default, and TCP_NODELAY (`787dd34`, 41 ms → 0.04 ms per command).
It has no screen-text reader, coverage or T-state command of its own; those are in the harnesses
below.

**z80sim** (`~/z80sim`, HEAD `13c9bce`, MIT, authoritative upstream; `~/z80SimUpgrade` is an
obsolete staging copy): source-level interpreter with an exact flag model, per-line tracing and
snapshot/replay (`snapshot.py`, `replay_snapshot.py`). **It is not a TS2068 emulator**: no `IN`,
interrupts, banking, ULA, tape or T-states. It cannot run the smoke ROMs; it is for testing
isolated routines. Leap vendors it with `tools/z80sim/UPSTREAM.md` and runs its `test_flags` and
`test_snapshot` in `make check`; `tools/sim_from_debugger.py` replays a live ts2068-debug state in
the simulator.

**Leap V2 build and test:**

- `make test` is headless through ts2068-debug. `tools/run_smoke_rom_tests.sh` (~70 lines) runs
  each ROM with `run --max-instructions 500000`, reads the border from `timex`, passes on 4. It fits
  Forth's convention unchanged.
- `tools/run_v2_prod_tests.sh`: parallel suites, one port and `TS2068_DEBUG_STATE_DIR` each;
  strict PASS/FAIL gate plus an XFAIL/XPASS known-defect suite.
- Smoke-ROM list held in one array (`tools/build_smoke_roms.sh`), keeping the Makefile at 263 lines.
- `tools/check_test_targets.sh`: structural guard that `make test` reaches what it should.
- `make check` chains ~20 gates: provenance, docs, RAM layout, package ABI, built-in tables,
  z80sim unit tests, assemble-only legacy fixtures.
- `make repro` (`tools/check_repro.sh`): two builds in separate trees, sha256 compared.
- `tools/qual/`: `qbench.py` (T-states via ZRCP), `qprofile.py`, `qcoverage.py`,
  `qcov_changed.py` (changed lines and both sides of every branch executed), `qpoweron.py`.

**Leap-C build and test:**

- `tools/sjasm_strict.sh`: `--msg=war`, any warning fails the build.
- Writes images straight into `build/` (no `mv`, no cwd litter); `build/SHA256SUMS` in `prod`.
- `tools/run_tests.py`: pool of up to 8 ZEsarUX workers, snapshot restore before every case,
  symbol/memory assertions instead of border colour; suite 3,333 s → 305 s [L].
- `tools/lcharness.py`: screen text read back through the ROM's font, snapshot restore,
  ZEsarUX code coverage; `tools/romcov.py` maps coverage onto the listing.
- `tools/shelltest.py` (editor screen oracle), `tools/fpmodel.py` + `tools/floattest.py` (float
  oracle), `tools/tapetol.py` (tape distortion sweep), `tools/poweron.py` (random/fixed RAM boot
  patterns), `tools/canary.py` + `tools/memguard.py` (RAM canary, banking invariants),
  `tools/docexamples.py` (doc code blocks with `// expect:` become tests), `tools/provenance.py`,
  `tools/budget.py` + `budget.toml`, `tools/relax_jumps.py`.

**`~/2068-rom-benchmarks`**: Forth fixtures and cross-ROM results (Forth sieve 2,091 frames,
pixel 785, 2026-09-15). Its harness is Leap-specific; the `benchmark-z80` skill describes the method.

### 6.3 Recommendations, in order

| # | Item | Source | Effort |
|---|---|---|---|
| T1 | **Headless `make test`**: run every smoke ROM through ts2068-debug, border 4 = pass, PASS/FAIL tally; one ROM list file; EXROM pairing from the `test-*` targets; per-ROM override table for exceptions such as p48 | Leap `tools/run_smoke_rom_tests.sh` | S-M |
| T2 | **Test-list guard**: every `rom/forth_smoke*.asm` and `rom/test_*.asm` is in the list | Leap `tools/check_test_targets.sh` | S |
| T3 | **Strict assembler wrapper**: warnings are errors (0 warnings today) | Leap-C `tools/sjasm_strict.sh` | S |
| T4 | **ROM reserve guard** in `make check` (owner decision 1) | Leap-C `tools/budget.py`, `budget.toml` | S |
| T5 | **Provenance scan + NOTICE** in `make check` | Leap-C `tools/provenance.py` | S |
| T6 | **Collapse the Makefile**: ROM list drives build, `all`, `.PHONY` and test; output straight to `build/`; coarse dependency stamp on `core/ kernel/ include/` (sjasmplus has no `-MMD`-style output, unverified); rename assemble-only `test-*` targets | Leap `tools/build_smoke_roms.sh`; Leap-C Makefile | M |
| T7 | **`make repro`** alongside `tools/build_stamp.py` | Leap `tools/check_repro.sh` | S |
| T8 | **Benchmarks under make**: commit `rom/bench/`, measure T-states at a done-symbol, record `build/bench.json`, flag regressions. Provides the Phase 2 baseline and Phase 15 gate | Leap `tools/qual/qbench.py`; `~/2068-rom-benchmarks` | M |
| T9 | **Power-on test** (would have caught O1) | Leap-C `tools/poweron.py` | S-M |
| T10 | **Refresh vendored z80sim** with `UPSTREAM.md`, snapshot/replay and its unit tests in `make check`; use it for isolated routines (float kernels in rebuild F) and `sim_from_debugger.py` for stuck cases | `~/z80sim` `13c9bce`; Leap `tools/sim_from_debugger.py` | S |
| T11 | **Symbol-based harness**: snapshot restore, memory assertions, parallel workers, screen-text reader. Needed for the editor oracle (rebuild E) and float oracle (rebuild F) | Leap-C `tools/lcharness.py`, `tools/run_tests.py` | M |
| T12 | **Editor screen oracle** | Leap-C `tools/shelltest.py` | M-L |
| T13 | **Float oracle** | Leap-C `tools/fpmodel.py`, `tools/floattest.py` | M-L |
| T14 | **Tape tolerance** for rebuild S | Leap-C `tools/tapetol.py`; Leap `tools/qtapetol.py` | M |
| T15 | **Coverage**: changed-line and branch coverage for each rebuilt section | Leap-C `tools/romcov.py`; Leap `tools/qual/qcov_changed.py` | M |
| T16 | **Doc-example tests** for `docs/forth_tutorial.md` (~3,000 lines) | Leap-C `tools/docexamples.py` | M-L |
| T17 | **CI**: add `make check`, `make repro`, release sha256; ZEsarUX in CI is not practical (Leap-C CI does not run it either) | Leap `.github/workflows` | S |
| T18 | **Developer notes**: CONTRIBUTING/CLAUDE.md pointer to ts2068-debug and the `2068-debug` skill | — | S |

### 6.4 Step T results (2026-10-28, branch `v2/step-t-test-infra`)

Items T1, T2, T3, T6, T7, T8 and T10 are done, one commit each (ledger row in §9). No ROM source
(`core/`, `kernel/`, `include/`, `rom/*.asm`) changed. **Byte check [M]:** all 234 pre-existing
`.bin`, `.dck`, `.sym`, `.lst` and `.inc` files from a clean build are sha256-identical to the
baseline recorded before the Makefile was touched, both after T3 and after T6 (serial and
`make -j8`), and again at the end. HOME free stays 68 B, EXROM free 6,682 B. The seven
`*.build.json` stamps differ, and only in the `Makefile` hash they record (`build_stamp.py` hashes
the Makefile by design). Builds are fully deterministic (two clean builds hash identically in all 241
files), which is what makes the check meaningful.

- **T1 `make test`** (`tools/run_rom_tests.sh`, list in `tools/rom_list.txt`): border 4 = pass; a ROM
  is finished when its CPU state and border are unchanged across two 500k-opcode chunks. Own ports
  (from 10760) and state dirs. Full suite 55 s. Exceptions are the list's `expect` column: p48 (visual,
  hangs with the border yellow, 6) and `p53_realtape` (needs a real `.TAP` and Fuse; SKIP).
- **T2** `check_test_list.sh` (in `make check`): every `rom/*.asm` has a row; also fails if
  `make -n test|check` could reach Fuse. **T3** strict wrapper: all 79 assemblies (77 ROMs + 2 cartridge variants), 0 warnings.
- **T6** Makefile 685 → 229 lines, driven by the list; `--outprefix=build/` (no `mv`, no ROM change);
  `build/.src.stamp` over `core/ kernel/ include/`; `-j` safe (clean build 8.6 s serial, 3.7 s `-j8`).
  `test-*` assemble-only targets are now `build-test-*`; the two never-built visual-check ROMs are in `all`.
- **T7** `make repro`: two trees, 248 files identical, stamps re-verified. **T10** `tools/z80sim` at
  `13c9bce` with `UPSTREAM.md`; its 20 tests run in `make check`.
- **T8** `make bench` (`tools/bench.py`) is the plan's Phase 2 baseline, committed in
  `tools/bench_baseline.json`. T-states from reset to the done-symbol `COLD_START.hang` (includes boot
  and compiling the Forth source), and for the timed region between the two `BORDER` calls [M]:

  | Benchmark | Total T-states | Timed region | Region at 3.5 MHz | In-ROM `FRAMES=` |
  |---|---:|---:|---:|---:|
  | sieve  | 148,052,276 | 146,138,092 | 41.8 s | 2091 |
  | pixel  |  57,304,991 |  54,821,539 | 15.7 s |  785 |
  | float  | 177,267,668 | 174,841,884 | 49.9 s | 2502 |
  | string |   2,828,926 |   1,995,755 |  0.6 s |   28 |

  Runs are exactly repeatable only after zeroing R, BC, DE, HL, IX, IY: ZRCP `reset-cpu` leaves them
  stale, and `pixel` seeds `RANDOMIZE` from R, which changed both its time and its `RESULT` (the
  `.fs` header's 159 was one lucky seed). Gate for later steps: slower than 1% fails.

### 6.5 Findings and deferrals from step T

- **`forth_smoke_p36` failed (border 3, deterministic); fixed in `6de13c3`, a test-only commit.** Checkpoint 3
  writes `$FF` to the first attribute byte, calls `CLS`, and expected `ATTR_DEFAULT` (`$44`). Since
  `c66d420` (2026-09-05) `W_CLS` repaints with `CURRENT_ATTR`, which p36 never initialised; at runtime
  `CURRENT_ATTR` ($87CB) and the attribute area read `$00`. A stale expectation, not a ROM defect. The
  fix initialises `CURRENT_ATTR` to `DEFAULT_ATTR` and expects that after `CLS`. Only p36's own
  images changed; `make test` is now 68 PASS, 0 FAIL, 1 SKIP.
- Deferred: T4/T5/T9 (step G), T11-T18. CI (`.github/workflows/build.yml`) is not yet changed to run
  `make check`/`make repro`/`make test` (T17). `rom/bench/*.asm` are not covered by `check_asm.py` /
  `check_z80_opcodes.py` (they take `rom/*.asm`). `forth_smoke_p52` (fake tape) is run by the runner as
  an ordinary border-4 ROM and passes; `forth_smoke_p53_realtape` remains Fuse-only. `rom/test_exrom_isolation.asm`'s
  header cites a nonexistent `tools/make_test_exrom.sh`; the `$A5` image is now made by the Makefile.
  The blackjack `BLACKJACK_TEST_MODE` build still has no target.

**Not recommended:** full platform vendoring (`platform/MANIFEST` + `deltas/*.patch`). Leap's kernel
changes since the fork are mostly BASIC-specific or shrink work; this ledger is the one-time record
of what was judged. A full package ABI is also not needed now: Forth already has
`GRAPHICS_EXROM_MAGIC` and `tools/audit_layout.py`. z80sim as a whole-ROM runner is not feasible.

---

## 7. Audit-area classification (plan Phase 1 list)

Classes: 1 reuse unchanged, 2 adapt behind a Forth interface, 3 reuse only if measurement
justifies, 4 retain Forth V1, 5 not needed.

| Area | Class | Where covered |
|---|---|---|
| Startup/kernel | 2 | O1, O8, O10 |
| HOME/EXROM banking | 2 | O8, R1 |
| Display | 2 | O2, O4 |
| Full-screen editor | 2 | §4.3 |
| Keyboard/input | 2 | O3 |
| Graphics | 2 | §3, O2, O4 |
| Video modes | 4 | mode64 retained; not audited further this pass |
| ULAplus | 4 | not audited this pass |
| Sprites | 4 | not audited this pass (EXROM, 1,510 B with RECT/POLYGON) |
| AY sound | 3 | O5, O9 |
| Storage | 2 | §4.1 |
| Package loader | 5 for now | plan Phase 13 |
| Extension registry/ABI | 4 | `GRAPHICS_EXROM_MAGIC`, `audit_layout.py` |
| Error handling | 2 | O6, float errors in §4.2 |
| Timing | 2 | O7 |
| Numeric services | 2 | §4.2, O10 |
| Debugger/emulator support | 1 (tools) | ts2068-debug, z80sim and the Leap/Leap-C harnesses, §6 |

---

## 8. Rebuild sequence

Each step from G onward ends with `make check`, `make test` (all smoke ROMs, headless), and a
measured ledger row (§9).

| Step | Contents | HOME Δ [E] | EXROM Δ [E] | Depends on |
|---|---|---:|---:|---|
| **T** Test infrastructure | T1-T3, T6, T7, T8 (benchmark baseline = plan Phase 2), T10 | 0 | 0 | — |
| **G** Guards | T4, T5, NOTICE, T9 power-on test, O1 | +8 | 0 | T |
| **R0** Recover | O11 dead code, O2 glyph, O8, O9, O12 | −80-110 | 0 | G |
| **R1** Cartridge EXROM paging | Make `-DCARTRIDGE` able to page the EXROM | ? | 0 | G |
| **S** Storage rebuild | §4.1 items 1-5; T14 | −11 then +40-70 | +~60 | R0 |
| **E** Console + editor rebuild | §4.3; line store first, then engine evaluation, then view; T11, T12 | −370 to +80 | +2,200-2,600 | S (in-place save), R1, T11 |
| **F** Float rebuild | §4.2; T13 | ~0 (±150) | 0 to +600 | R0, T11, T13 |
| **K** Keys and glyphs | O3 plus `[']`, `[CHAR]`, `\`, `[ ]` | +~100 | 0 | R0 or E savings |
| **D** Display speed | O4 | ≤0 | 0 | — |
| **B** BREAK and timing | O6, O7 | +~35 | 0 | T8 benchmarks |
| **A** AY BEEP (approved 2026-10-28) | O5 | −350-400 | 0 | R0 |

O5 is approved: run it immediately after R0: it is the largest single HOME recovery and funds S,
E and K.

---

## 9. Ledger (update after every step)

| Step | Commit | HOME free | EXROM free | Section bytes before → after | Speed note | Smoke ROMs |
|---|---|---:|---:|---|---|---|
| Baseline | `fff5259` | 68 [M] | 6,682 [M] | see §3 | — | as committed |
| **T** Test infrastructure | `ba2009b` T10, `a060549` T3, `994429a` T6, `24b4231` T1, `2ab1541` T2, `edb8314` T7, `9a0ee04` T8 | 68 [M] | 6,682 [M] | 0 → 0 (tooling only; every image, `.sym` and `.lst` byte-identical to baseline [M]) | Phase 2 baseline, §6.4 | `make test`: 67 PASS, 1 FAIL (`forth_smoke_p36`, stale test, §6.5), 1 SKIP (`p53_realtape`) [M] |
| T follow-up: p36 | `6de13c3` | 68 [M] | 6,682 [M] | 0 → 0 (only p36's own images change) | — | `make test`: 68 PASS, 0 FAIL, 1 SKIP [M] |
| | | | | | | |

---

## 10. Owner decisions needed

Decided 2026-10-28 (owner): 1, 2, 4, 5. Open: 3, 6.

1. **Reserve target**: adopt 200 B HOME / 150 B EXROM as provisional? **Decided: yes, as a ratchet.**
   The T4 guard floors each section at its current free space (HOME 68, EXROM 6,682) so it blocks
   regressions now and tightens toward the target as space is recovered; HOME is 132 B under the
   target today, so a hard gate would fail immediately.
2. **AY BEEP** (O5): replace the speaker BEEP, keep the speaker as an optional word set, or keep
   both? **Decided: approved as O5 proposes** (§5): BEEP becomes AY-based and the speaker BEEP is kept
   only as an optional package. Step A runs immediately after R0.
3. **Float format**: accept 5-byte floats (float-stack depth ~341 → ~204 cells; smoke ROMs
   regenerated)?
4. **`fpcore` provenance**: accept Leap V2's position (passes the 12-byte scan, MIT) for Forth's
   NOTICE? **Decided: yes, conditional** on the T5 scan coming back clean on the Forth tree.
5. **Disassembly-informed files** (`core/printer.asm`, `kernel/sound`, `kernel/mode64`,
   `core/stick.asm`): accept as clean, or schedule clean-room rewrites? **Decided: accept for now;**
   schedule a rewrite only for a file the T5 scan flags.
6. **Legacy tapes**: accept unstamped `SAVE-LIB` images from V1 with a warning, or refuse them?
