# Leap-Forth V2 — Platform Reuse Audit, Section Ledger and Rebuild Plan

Phase 1 deliverable of `docs/V2/project plan - Leap-Forth V2.md`.

**Current state and next steps:** `docs/V2/HANDOFF.md` (updated at the end of each session).

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
the EXROM is absent from the cartridge build until that is fixed (rebuild R1 below; **done**, §6.9).

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

## 4. Rebuild plans: the three primary sections (4.1-4.3), then the size pass (4.4)

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

**Done in step S**, against `docs/V2/STORAGE_SPEC.md`; results in section 6.10.

### 4.2 Float (rebuild F)

**Done (2026-10-29)**: `docs/V2/FLOAT_SPEC.md` (owner decisions F1-F10), the ledger rows "F" in section 9. What follows is the plan as written before step F.

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
| Size | 2,129 B [M] (2,100 B [M] at step F's start, `b4a05b0`) | 1,461 B core [M, Leap-C listing] | +~150 B SQR, ~413 B trig [L] |
| Test oracle | smoke ROMs | `tools/fpmodel.py` (bit-exact), `tools/floattest.py` | 16,000/16,000 match Leap-C model [L] |

**Rebuild contents.**

1. Spec: 5-byte cells on the IY float stack; word set below; error behaviour via `THROW`.
2. Engine: `fpcore` arithmetic, compare, FRI/TOI, FTOA, ATOF, called directly (not through V2's
   RST $28 dispatcher).
3. SQR (exponent-halving Newton step, `54cd877`) and SIN/COS/TAN (minimax series) from Leap V2.
   Keep Forth's radian interface: `SIN`/`COS` take radians, and `RAD`/`DEG` remain.
4. Shared number parser for float literals and `NUMBER` (ATOF with integer fallback).
5. New words where cheap: `FNEGATE`, `F<`, `F=`, `FDUP`, `F@`, `F!`, `FVARIABLE`.
6. **O10, integer multiply and divide** (added to F by the owner, 2026-10-28).
   - Replace `MATH_UMUL16`, `MATH_UDIV16`, `MATH_MULTIPLY16`, `MATH_DIVIDE16` and `MATH_MOD16` in
     `kernel/math/math.asm` (178 B [M] at step F's start; the 412 B was the whole file) with Leap-C's register-only helpers in `src/runtime/helpers.asm`
     (`RT_UMUL`, `RT_UDIV`, `RT_DIVS`, `RT_MODS`, `RT_MUL`).
   - Leap-C's delta D3 deleted 351 B of the V2 routines for them: 1.4-2.3× faster [L], 60000/7 from 3,584 to
     1,479 T [L].
   - Forth also calls `MATH_SQRT16`, `MATH_SGN16`, `MATH_RND16` and `MATH_RND_SEED`, which Leap-C deleted for
     want of a C caller. Keep them, or take Leap-C's xorshift `rand` (`src/runtime/library.asm`), whichever
     measures smaller.
   - `make bench` must hold or improve: sieve and string are the integer gates. Measure the bytes; no estimate yet.

**Budget.** (Re-estimated in `docs/V2/FLOAT_SPEC.md` section 14.) Replace 2,129 B with ~1,464 + ~150 + ~450 + ~200 glue ≈ 2,260 B [E], roughly flat.
Measure; if HOME is short, the transcendentals move to the EXROM.

**Costs and risks.**

- Float-stack depth falls from ~341 to ~204 cells in the same 1 KB.
- Smoke ROMs that hard-code 3-byte expectations must be regenerated: p8, p18, p19, p22, p23, p29,
  p30, p34, p35, p42 [L, from the audit], and p31, p38, p50 (found at step F's start, `FLOAT_SPEC.md` 10.2).
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

### 4.4 Size pass over the code that stays (step Z, added 2026-10-28 by the owner)

**Why.** No other step shrinks the code the rebuild keeps. Section 3 marks Strings, Interpreter, DO/LOOP,
64-column mode, Printer, Errors, the dictionary/compile/control words and the remaining core words "4 Retain,
Measure only": about 4.1 KB at baseline before the unitemised core words. The graphics kernel (2,624 B) is
touched only by D (one routine, for speed), kernel math (411 B) only by O10 (speed), the keyboard (519 B) only
by K (which adds). Step R0 was a whole-ROM sweep, not a review of each section: dead code −64, `jp` → `jr` −20,
glyph builder −12.

**When.** After E and F: they rewrite the console and the float code, so shrinking those first would be wasted.
K, D and B may land before or after Z; Z measures whatever is current. If D has not run, Z leaves
`GFX_CLEAR_ROW` to D.

**Scope.** Every HOME section that S, E and F did not rebuild, and the EXROM graphics services (RECT, POLYGON,
sprites: not audited, section 7). It does not include the tape block I/O (`kernel/storage/tapeblock.asm`): that is
Leap-C's code, unchanged, under `tools/check_upstream.py`. Changing it is a separate decision, which the owner
allows if needed.

**Method.**
- Behaviour unchanged, every change a source transformation: the rules of section 1, and `shrink-z80`'s
  `references/hard-contract.md`.
- Re-measure each section from the current listing first, in the format of section 3.
- One change per commit, with its measured bytes for every image: HOME, cartridge, both demos, EXROM. Use
  `make check` (budget floors raised as space is recovered), `make test`, `make repro`, `make cartdiff`.
- `make bench` must not slow down. A change that trades speed for bytes needs the owner's approval.
- The provenance scan must stay clean.
- No estimate until the measurement exists. As a precedent only: 2068-Leap's R10.5 shrink milestone
  (`docs/R10_5_SHRINK.md` there) recovered 291 B HOME from a different code base, with no behaviour change.

**Tools.** These come from the z80-skills repo (`~/z80-skills`, github.com/nchiker/z80-skills):
- **`shrink-z80` skill** (`skills/shrink-z80/SKILL.md`). Read-only, evidence-first size analysis, invoked by
  the user as `/z80-skills:shrink-z80`.
  - Modes: `preflight`, `scan`, and the focused `deadcode`, `dedup`, `micro`, `data`, `refactor`, `reserve`.
  - References: `high-impact.md` (attack order), `asm-micro.md`, `size-blackbook.md`, `z80-byte-evidence.md`.
- **Its scripts**, in `skills/shrink-z80/scripts/`. Run them as `python3 <path>`, not `python3 -I`, because
  they import `scan_common` from their own directory.
  - `production_reachability.py` walks the label graph of the shipped images' sjasmplus listings, ignoring
    false conditional blocks.
  - `z80_pattern_scan.py`, `deadcode_scan.py`, `literal_dup_scan.py`, `generated_helper_scan.py`,
    `map_summary.py`, `artifact_freshness.py`, `preflight_scan.py`.
  - Smoke run, 2026-10-28: `production_reachability.py --roots-below 0x0100 --root-prefix H_
    build/forth_boot.lst` reports 4 unreachable bytes, `INT_GET_FRAMES`. This is a candidate, not checked.
- **`tools/shrink-agent`** is the applying loop: one routine at a time, with build, size, test and independent
  review gates, on its own branch. It cannot be used here as it is: it parses z88dk linker maps (`mapfile.py`),
  and it bills the Claude API from `~/.z80-skills/.env`. Porting it to sjasmplus `.sym`/`.lst` is separate
  tooling work and needs the owner's approval.
- **Also:** 2068-Leap-C `tools/relax_jumps.py` (used for O12 in R0) and 2068-Leap `docs/R10_5_SHRINK.md` (its
  techniques).

**Deliverables.** A section ledger (section 3 format) before and after; one commit per change with its bytes; a
ledger row in section 9; the candidates rejected, with the reason for each.

### 4.5 Leap-C comparison audit for the remaining modules (step L, added 2026-10-28 by the owner)

**Why.** About 6.4 KB of HOME code was never compared with Leap code: everything marked "Retain" in section 3.
Another 3.8 KB is only adapted a routine at a time: the graphics kernel, keyboard, interrupt and boot. The owner
asked for each of these to be audited against Leap-C, unless that would have no value.

**What Leap-C has** [S, `~/2068-Leap-C` at `b918527`]:
- **`platform/`**: Leap V2 v2.0.1's kernel, vendored with recorded deltas D1-D21 (`platform/UPSTREAM.md`,
  `MANIFEST`). Auditing it covers Leap V2's kernel too.
- **`src/runtime/library.asm`**: the C library (`LIB_PRINT`, `LIB_PRINTF`, `LIB_ITOA`/`UTOA`/`ATOI`, `LIB_AT`,
  `LIB_TAB`, string and memory routines, `LIB_PLOT`, `LIB_DRAW`, `LIB_POINT`, `LIB_SPGET`, `LIB_SPPUT`,
  `LIB_GETKEY`, `LIB_INKEY`, `LIB_INP`, `LIB_BEEP`, `LIB_SOUND`).
- **`src/runtime/helpers.asm`**: integer helpers (multiply, divide, shifts, compare).
- **`src/shell`**: the shell. **`src/compiler`**: the C compiler.

Leap-C has no Forth interpreter, no printer code, and no 64-column mode (removed 2026-08-20).

**Scope, judged by value** [S; each judgement is checked during the audit]:

| Forth module | HOME B [M] | Leap-C counterpart | Value |
|---|---:|---|---|
| Graphics kernel | 2,596 | `platform/kernel/graphics/graphics.asm` (Leap V2 plus D6, D8, D12, D13, D21) | **High.** Forth's kernel was scaffolded from 2068-Leap's (`96aea38`); diff the two routine by routine (text, scroll, line, circle, attributes). D and K then use the findings |
| Graphics words | 766 | `LIB_PLOT`, `LIB_DRAW`, `LIB_POINT`, `LIB_ATTRF`, `LIB_MODE`, `LIB_SPGET`/`SPPUT` | Medium: clamping, argument checks, sprite get/put |
| Strings | 989 | `LIB_STRLEN`, `STRCPY`, `STRCAT`, `STRNCPY`, `STRCHR`, `STRCMP`, `MEMSET`, `MEMCPY`, `MEMMOVE`, `MEMCMP` | Medium: the copy, compare and search primitives under the Forth words |
| Output words | 327 | `LIB_PRINT`, `LIB_ITOA`, `LIB_UTOA`, `LIB_PRINTF`, `LIB_AT`, `LIB_TAB` | Medium: number formatting and cursor positioning |
| Keyboard and interrupt kernel | 625 | `platform/kernel/io` (D7), `platform/kernel/interrupt` (D4) | Medium: whatever K (D7) and B (BREAK) do not already take |
| Integer words | ~703 | `helpers.asm` shifts and compare, `LIB_ABS`, `LIB_ATOI` | Low to medium. Multiply and divide are O10, in F; number parsing is F item 4 |
| Sound words | ~185 | `LIB_SOUND`, `platform/rom/exrom_sound.asm` (D19) | Low: small, already fixed in R0 (O9) |
| Boot | 599 | `src/rom/home.asm` | Low: mostly vectors, veneers and padding; check the cold-start sequence only |
| Misc I/O | 133 | `LIB_INP` | Low: fold into the integer or output lane |
| Interpreter and compiler, DO/LOOP | 2,256 | none: the C compiler and its code generator are not a Forth interpreter | **No value**; step Z covers them |
| Errors (THROW/CATCH, ABORT) | 252 | `src/runtime/rtexit.asm`, C's exit and runtime error, a different model | No value beyond B's BREAK latch (D4); step Z |
| 64-column mode | 460 | none (removed in Leap) | No value; step Z |
| Printer | 338 | none | No value; step Z (provenance already accepted, decision 5) |

**Method.** Read-only, with no code changes. For each module with value:
- A routine map, Forth to Leap-C, with bytes [M] on both sides, speed where a benchmark exists, behaviour
  differences, bugs Leap-C fixed that Forth still has, and provenance (Leap-C's 12-byte scan status).
- A recommendation per routine: replace, adapt, or keep. Every replacement becomes an O-item in section 5 and
  is placed in a step: an existing one (D, K, B, F, Z) or a new one.
- Delegate the inventories per the owner's orchestration brief, and verify every claim a recommendation rests on.

**When.** L is read-only, so it can run alongside E's harness work. It must finish before D, K and B, which touch
the same graphics and keyboard code, and before Z, whose scope it changes.

**Results (2026-10-28, branch `v2/step-l-leapc-audit`):** `docs/V2/LEAPC_COMPARISON_AUDIT.md`, with the measured
inventories in `docs/V2/evidence/l_*.md`. Nothing in Leap-C replaces a Forth routine outright; the paired graphics,
keyboard and integer routines are the same V2 code. New items O13-O19 (section 5): the largest are O13 (data-stack
calls through RST vectors, about −480 B [E]), O14 (230 B of page-zero padding not counted as free [M]) and O15
(FILL and CIRCLE to the EXROM, about −820 B [E], owner decision). O18 is a latent defect (PLOT and LINE do not clip).

---

## 5. Other findings

| # | Item | Class | Reference | Forth file | Cost [E] | Notes |
|---|---|---|---|---|---|---|
| O1 | Cold start does not clear `UDG_TABLE` ($F180 is above the $8000-$F000 clear) | 2 | Leap `67c7137` item 2.2 | `rom/forth_boot.asm` ~217 | +8 B | **Verified bug**: CHR$ 144-164 show power-on garbage. **Fixed in step G (`861a823`), 0 B [M]**, see section 6.6 |
| O2 | Stock-ROM bytes in the block-graphics glyph builder (two 12-byte PO-GR-2 runs) | 2 | Leap-C D21, Leap `c2415f8` | `kernel/graphics/graphics.asm` ~467 | −12 B | Licensing. **Done in step R0 (`7e7c461`), −12 B [M]**: body of Leap-C D21, scan no longer finds it, §6.7 |
| O3 | Missing characters `[ ] \ { } \| ~ ^` and backtick: no glyphs, no keys, so no `[']`, `[CHAR]`, `\` comments, `[ ] LITERAL` | 2 | Leap-C D7, D8; Leap `8a52ab9` (72 B glyphs), `0b35b68` (direct glyph table, −38 B) | `kernel/io/io.asm`, `kernel/graphics/graphics.asm`, new words | ~+100 B + words | Significant Forth-standard gap |
| O4 | `GFX_CLEAR_ROW` writes attributes per character via `GFX_SET_ATTR` | 2 | Leap `kernel/graphics/graphics.asm` (back-port 4.1, 5.8; `22b4999`) | `kernel/graphics/graphics.asm` ~1045 | smaller | 24,786 → 6,498 T per row [L]; runs on every scroll |
| O5 | AY BEEP; current BEEP runs with interrupts off for the whole note | 3 | Leap `rom/v2_ay_beep.asm` (`6493615`); speaker kept as optional package | `core/beep.asm`, `kernel/sound/sound.asm` | −350-400 B | Owner decision: speaker → AY. **Done in step A (`5f4678f`, `6086ecc`), −295 B [M]** (estimate −350-400 [E]), §6.8 |
| O6 | BREAK latch in the ISR so runaway loops can be stopped | 2 | Leap `8ee4f1a`, `fa8e5b9` | `kernel/interrupt`, loop words, `THROW` | +~14 B + polls | Measure loop cost (Phase 15 gate) |
| O7 | No pause/timing word | 2 | Leap `AY_WAIT_FRAMES` (HALT counting, frame-wrap safe, 7 B) | new word `MS` or `PAUSE` | ~+20 B | `CHIME_DELAY` has the same wrap class, harmless at boot |
| O8 | `di` in `BANK_PAGE_EXROM_IN/OUT` drops frame interrupts | 2 | Leap-C D14 (47/11,232 frames lost [L]) | `kernel/bank/bank.asm` | −2 B | Low impact today (graphics EXROM only). **Done in step R0 (`684065f`), −2 B [M]**; frames lost 38% → 0 in a paging loop, §6.7 |
| O9 | `SOUND` rejects register 0 | 3 | Leap `6493615` | `core/sound.asm` ~126 | −3 B | Optional. **Done in step R0 (`2dc9cf6`), −8 B [M]** (the chime's direct register-0 write goes too), §6.7 |
| O10 | Faster unsigned multiply/divide | 2 | Leap-C `RT_UMUL/RT_UDIV` | `kernel/math/math.asm` | ± | 60000/7: 3,584 → 1,479 T [L]. **Scheduled in step F (owner, 2026-10-28)**, §4.2 item 6 |
| O11 | Dead code | — | — | io, graphics, mode64 | −64 B | Verify each before removal. **Done in step R0 (`de5d735`), −64 B [M]**, §6.7 |
| O12 | `jp` → `jr` | — | Leap-C `tools/relax_jumps.py` | various | ≤ −30 B | Many sites are deliberately `jp`; lowest priority. **Done in step R0 (`bcf45ac`), −20 B [M]** (30 candidates; 10 left as `jp`), §6.7 |
| O13 | `DPOP_HL` (137 calls) and `DPUSH_HL` (105) through RST vectors in page zero; `rst` is 1 B and 11 T against `call`'s 3 B and 17 T | — | Leap-C `RST_LDI`/`RST_STI`/`RST_ENTER`/`RST_LEAVE` | `core/dict.asm`, `rom/forth_boot.asm`, every caller | ~−480 B [E] | Step L. Recommended as its own step before E's code (L audit section 4); otherwise Z |
| O14 | Page-zero padding: 230 B of `$FF` in both builds, not counted by `budget.py` | — | Leap-C page zero | `rom/forth_boot.asm` | up to ~−200 B [E] | Step L, [M]. Z |
| O15 | `GFX_FILL` (487 B) and `GFX_CIRCLE` (368 B) kernels to the EXROM, as RECT and POLYGON | 3 | Leap-C moved them out of HOME | `kernel/graphics/graphics.asm`, `rom/graphics_exrom.asm` | ~−820 B HOME, +~860 B EXROM [E] | Step L. **Approved (decision 7), after E** |
| O16 | `IO_DECODE_KEY` shares its table lookup (Forth 132 B, Leap-C 114 B) | 2 | Leap-C `platform/kernel/io` | `kernel/io/io.asm` | −18 B [E] | Step L. K |
| O17 | Glyphs of `1` and `l` (differ in two pixels) | 2 | Leap-C D13 (`f209f21`) | `kernel/graphics/graphics.asm` | 0 | Step L. K |
| O18 | PLOT and LINE do not clip y: `y >> 3` up to 31 indexes past `ROW_BASE_TABLE`; today the writes land in ROM [M], a latent RAM write | 2 | Leap-C `GFX_PLOT_CLIPPED` callers | `kernel/graphics/graphics.asm` `GFX_WRITE_PIXEL` | +4 B [E] | Step L, latent defect. D |
| O19 | `SOUND_WRITE` and `AY_WRITE` are duplicates except the bound (0-16 against 0-15) | — | — | `core/sound.asm`, `core/soundext.asm` | −8 B [E] | Step L. Z; register 16 is the owner's call |

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
- Deferred: T11-T18 (T4, T5, T9 were done in step G, section 6.6). CI (`.github/workflows/build.yml`) is not yet changed to run
  `make check`/`make repro`/`make test` (T17). `rom/bench/*.asm` are not covered by `check_asm.py` /
  `check_z80_opcodes.py` (they take `rom/*.asm`). `forth_smoke_p52` (fake tape) is run by the runner as
  an ordinary border-4 ROM and passes; `forth_smoke_p53_realtape` remains Fuse-only. `rom/test_exrom_isolation.asm`'s
  header cites a nonexistent `tools/make_test_exrom.sh`; the `$A5` image is now made by the Makefile.
  The blackjack `BLACKJACK_TEST_MODE` build still has no target.

### 6.6 Step G results (2026-10-28, branch `v2/step-g-guards`)

T4, T5, NOTICE, T9 and O1, one commit each (ledger row in §9). Only `rom/forth_boot.asm` changed under
`core/ kernel/ include/ rom/` (O1). **Byte check [M]:** after T4, T5, NOTICE and T9 all 260 files of a clean
build were sha256-identical to the baseline recorded before anything was touched. After O1 a clean build
differs in `forth_boot_rom0.bin`, `forth_boot_cart.bin`, `forth_boot.dck` and the `.lst`/`.sym` of the two
(two bytes each, `$0124-$0125`, the `ld bc` immediate) and in the `*.build.json` stamps (which hash the Makefile
and `rom/forth_boot.asm`). Every smoke, test, bench, visual, blackjack, gallery, EXROM, LROS and `main` image is
unchanged. `make check`, `make repro` (260 files) and `make bench` (all deltas +0.000%) pass.

- **T4 `tools/budget.py`, `tools/budget.toml`** (in `make check`): free space is measured from the image (last
  non-pad byte) and may not fall below the committed floor; the 200 / 150 B targets are printed as distance.
  Six images are floored, including the cartridge builds, which have their own layout (380 B free against 68 B
  for the Home ROM). Raising a floor is an edit to the toml; lowering one needs a ledger row in the same commit
  (the toml header says so; not machine-enforced).
- **T5 `tools/provenance.py`** (in `make check`; skips and says so when the stock ROMs are not in
  `$FORTH_STOCK_ROMS` / `~/fuse-build/roms`): six images, 45 common runs of 12 bytes or more [M]. The audit's
  claim holds: all fall in `STORAGE_SEND_BLOCK` / `STORAGE_RECEIVE_BLOCK` (tape block I/O, 24 runs, owner step S)
  and `GFX_CHAR_TO_FONT_OFFSET` (two 12-byte runs per image, 20 runs over the five images that contain it,
  owner step R0, O2), plus one 1,171-byte run at the end of the EXROM that is $FF fill with one non-fill byte.
  Nothing in `core/printer.asm`, `kernel/sound`, `kernel/mode64` or `core/stick.asm`, so the condition on
  owner decisions 4 and 5 was not tripped by this scan; this file does not decide them. The two debts sit in
  an allowed table with their owning steps, to be deleted by those steps.
- **NOTICE** is a draft for owner review, not an approved statement. It makes no licence claim about the two
  debts, records decisions 4 and 5 as conditions, and notes that more files than the four named in decision 5
  cite the disassembly in their comments (`core/beep.asm`, `core/sound.asm`, `kernel/io`, `kernel/graphics`,
  `kernel/interrupt`, `kernel/storage`, and two includes).
- **T9 `tools/poweron.py`** (`make poweron`, part of `make test`; ports 10820-10839): boots from zero, ones,
  alternating, address-low-byte and four seeded random patterns written over `$4000-$FFFF` and the registers.
  Defined = everything outside a short table of regions with recorded reasons (machine stack below SP, `$FF00+`,
  GFX_FILL scratch / display file 2 / `$5C36`, the unused Leap cells `$F000-$F17F` and `$F228-$F5FF`, GFX_LINE
  cells). `reset-cpu` keeps RAM and registers (measured). Before O1 it failed all 7 patterns with UDG_TABLE
  (`$F180-$F227`) the only DEFINED difference (outputs are in the T9 and O1 commit messages); after O1 it
  passes 7/7. Every boot reaches the prompt with SP `$FF00` in 4,442,252 T-states.
- **O1**: instead of a second fill (+9 B), the existing fill runs on to the end of `UDG_TABLE`: 0 B. It also
  zeroes `$F000-$F17F`, which Forth does not use.
- Not done here, as scoped: the two debts above; the T9 table treats `$F228-$F5FF` as unused because nothing in
  `core/ kernel/ rom/` reads it, which a future step that starts using those cells must revisit; `make test`
  grew by about 28 s for T9.

### 6.7 Step R0 results (2026-10-28, branch `v2/step-r0-recover`, from `v2/step-g-guards`)

O2, O8, O9, O11 and O12 done, each with its own commit and measured bytes; HOME free **68 → 174 B [M]**
(cartridge 380 → 486), EXROM unchanged at 6,682. The reserve ratchet floors were raised in each commit.
Unlike step G, R0 changes behaviour in places, so the check is the test suite and the measurements below,
not byte-identical images; every image that includes the changed files moves.

- **Oracles first.** `rom/test_blockgfx.asm` (O2) was added and passes on the old routine; a deliberate
  one-bit mutation turns it red. `rom/test_sound_reg0.asm` (O9) reads the AY registers back (they are
  readable under ZEsarUX) and was red on the old code, green on the new. `make test`: 70 PASS, 0 FAIL, 1 SKIP.
- **O2 (−12 B).** The glyph builder's body is Leap-C's delta D21, which that project records as written
  clean-room from the screen format. That is a record I did not re-verify; what was measured here is that
  the 12-byte scan no longer finds the routine (45 → 25 runs, only the tape block I/O and one EXROM fill run
  left) and that the 16 glyphs equal the rule the screen format fixes. NOTICE section 3 says exactly that;
  it still needs the owner's review.
- **O11 (−64 B).** Verified by searching every `.asm` in the tree with comments stripped, not just the Home
  listing: `IO_ANY_KEY_DOWN` 19, `GFX_PUTCHAR_OVER` 16, the SYMBOL SHIFT+A/S key cases 19, and
  `MODE64_READ_PIXEL` 10, which moved into `forth_smoke_p8b` because that test is its only caller.
  Not removed: `NMI_ENTRY` (the NMI vector) and `MEM_FILL` (the fall-through of `MEM_FILL_ZERO`). Visible
  change: `KEY` no longer returns 12 or 14 for SYMBOL SHIFT+A/S (now 0); the two chords are free for step K.
- **O8 (−2 B).** The interrupt handler touches none of the banking state, so the `di` in the two paging
  routines only lost frames. A throwaway ROM that pages 40,000 times: 129 of an expected 207 frames
  before, 244 of 244 after.
- **O9 (−8 B).** `SOUND` takes registers 0-16 (17+ ignored); the boot chime's raw write of register 0
  became the first table entry. The same writes happen in the same order. `0 n SOUND` used to do nothing.
- **O12 (−20 B).** 30 `jp` were in range; 20 are now `jr`. The rest were left on purpose: `core/beep.asm`
  (step A rewrites it), sites an earlier author marked "JP, not JR", and sites inside 10 bytes of the
  limit, where `check_z80_opcodes.py` complains. `jr` is smaller but not faster, so the result was
  checked against `make bench` (all within ±0.04%). `tools/relax_jumps.py` is the port of Leap-C's tool.
- **Found on the way: the pixel benchmark depended on code layout.** `0 RANDOMIZE` makes RND read the R
  register, so the O8/O9 changes moved pixel's RESULT from 159 to 213 and `make bench` failed its RESULT
  check (T-states moved 0.04%). `rom/bench/bench_pixel.asm` now seeds 26725 (`$6865`, read from the
  step-G baseline run), which restores RESULT 159 and the Phase 2 numbers. A tooling fix, `6ddb8c9`.
- **Left for later.** HOME is 26 B short of the 200 B target; step A (AY BEEP, −350-400 B) is next.
  `KEY_NEXT_ERROR`/`KEY_PREV_ERROR` and `EDIR_*` constants are now unused in `include/` (no bytes).

### 6.8 Step A results (2026-10-28, branch `v2/step-a-ay-beep`, from `v2/step-r0-recover`)

O5 done as approved (owner decision 2): `BEEP` plays on the AY chip. HOME free **174 → 469 B [M]**
(cartridge 486 → 781); EXROM unchanged. The estimate was −350-400 B [E]; the measured −295 B is lower because
`SOUND_BEEP` was 55 B, not the audit's larger share, and the float routines `BEEP` borrowed (`FSTAR`, `F_UDIV32BY16`,
`F_SHRA`) are used by other words and stay.

- **Spec first.** `docs/V2/AY_BEEP_SPEC.md` was written before the code: contract, ranges, channel policy, what
  changes and the oracle. The period table and shift-and-round scheme follow 2068-Leap's `rom/v2_ay_beep.asm`
  (the same 12 numbers; the code is rebuilt, and checked below against the formula, not against that table).
- **Oracle.** `rom/forth_smoke_p31.asm` was rewritten (its old checkpoints tested the removed float maths): all
  130 notes within 1 count of `round(110250 / (261.6256 · 2^(max(n,-39)/12)))`, R7/R8 read back from the chip, the
  FRAMES delta for nine durations, out-of-range pitches, channels B/C and the other mixer bits untouched,
  interrupts on after a `BEEP` called with them off, stacks balanced. **Mutation-checked:** seven deliberate faults
  (frame constant, a table entry, no `EI`, a clobbered R10, a wrong R7 mask, an extra push, a widened range) each
  turn it red. The mutation run found a flaw in the oracle first: checkpoint 4 failed with border 4, the pass
  colour, so it could not have failed; failure colours are now 1, 2, 3, 5, 6.
- **Behaviour changes** (all in the spec and the tutorial): the sound comes from the AY, not the loudspeaker;
  interrupts and the keyboard run during a note; channel A is taken (silent afterwards, period left in R0/R1);
  durations are whole frames (1/60 s), rounded, up to 546 s; pitch −60..69 with −60..−40 playing A0; out-of-range
  input does nothing; the 12.9 kHz clamp is gone.
- **Speaker beeper kept as an optional package**, as decided: `kernel/sound/sound.asm` and `core/rawbeep.asm` stay
  (`forth_smoke_p5` still tests them) but the product and bench ROMs no longer include `SOUND_BEEP`. No user-facing
  speaker word was added.
- **Chime.** Its FRAMES-polling `CHIME_DELAY` became an inline `HALT` loop (−20 B). Boot to the prompt is
  4,442,252 T before and 4,442,116 after: a 136 T difference in the last frame's tail, not a frame (69,888 T), so
  every wait lasts the same number of frames. The register writes were not traced one by one.
- **Audio capture (`tools/ay_audio.py`, `make audio`).** ZEsarUX's own audio output (`--aofile`, 15.6 kHz, emulated
  time) was recorded while the product ROM played a scale typed at the prompt. Ten notes, −39 to +36 semitones
  (above about 2.2 kHz edge counting is not reliable, so higher notes are checked by register only): each BEEP's
  frequency matches the same period written through plain `SOUND` to within 0.03%, and the formula to within
  −0.02% (+36) … −0.37% (−12) … −1.13% (−24) … −2.34% (−39). The larger errors at the low end are the
  emulator's rendering of long periods, not BEEP: `SOUND` reads the same. Notes last 0.348-0.349 s of audio
  against 18 frames asked for (0.36 s at 50 Hz): the first frame of an isolated note is partial, as specified.
  Mutation-checked: a wrong table entry turns it red at every octave of that note. The startup chime of the
  step-A BEEP build and of the build with the `HALT` wait compare equal window by window (52 windows each, worst
  per-window power difference 0.05 of the loudest), which backs the frame-count argument above with sound, not
  only T-states.
- **Verification limits.** There is no hardware: everything was checked under ZEsarUX, by AY registers, timing and
  its audio capture, not by ear. ZEsarUX runs 50 Hz frames against the real machine's 60 Hz and a 1.7734 MHz AY
  against 1.764 MHz, so a note lasts 20% longer there and sounds 0.53% sharper (the same findings as Leap's study).

### 6.9 Step R1 results (2026-10-28, branch `v2/step-r1-cartridge-exrom`, from `v2/step-a-ay-beep`)

The cartridge build now has `RECT`, `POLYGON`, `POLYGON-FILL` and `SPRITE-DEFINE/SHOW/HIDE`. Spec first:
`docs/V2/CARTRIDGE_EXROM_SPEC.md`. Port `$FF` bit 7 is a global DOCK/EXROM select (measured in ZEsarUX), so a
Home-RAM trampoline cannot keep the `$0100` callbacks and the interrupt handler in the cartridge. The design: the
cartridge carries `graphics_exrom.bin` as DOCK chunk 5 (`tools/make_dck.py` takes it as a third argument and checks
its service-table trailer); paging chunk 5 is one `OUT` to `$F4` (`CART_HSR | $20` in, `CART_HSR` out) and `$FF` is
never written. `kernel/bank/bank.asm` has the two variants under `IFDEF CARTRIDGE`; the Home build's code is unchanged.
`CART_CHUNK_SPEC` is asserted at assembly (bit 3 and bit 5 stay Home).

- **Bytes [M].** Cartridge free 781 → 478 (-303 B; the spec estimated about 312 B [E]). Home 469, both Blackjack
  images (797) and the Gallery (802) and the EXROM (6,682) are unchanged: the Blackjack cartridge does not include the
  six words. Floor for `forth_boot_cart.bin` lowered 781 → 478 in `tools/budget.toml` in the same commit.
- **Oracle** (`tools/cart_diff.py`, `make cartdiff`, about 15 minutes, not in `make test`): the same typed program on
  the Home build and the cartridge build, on ZEsarUX and on TSRun's real core under Node. Compared exactly: screen
  `$4000-$5AFF`, both stacks, `HERE`/`LATEST` and the user dictionary (ROM addresses compiled into definitions are
  compared by symbol name, the count is printed), the EXROM-side state cells, and that chunk 5 is paged out and the
  control line `1 2 + .` prints `3 OK`. 13 cases (each of the six words, reversed corners and colours, a 12-vertex
  polygon, 240-iteration and mixed 30-iteration paging loops, a compiled word run twice). **Result: 26 of 26
  case/emulator pairs identical** (`docs/V2/evidence/r1_cartdiff_pass.txt`). **It catches the original failure:**
  against the old tree (guards removed, home-variant paging, no chunk 5) 26 of 26 fail, 22 of them with the
  cartridge unresponsive after the first `RECT`, and TSRun's depth spy sees `BANK_EXROM_DEPTH` corrupted
  (`r1_cartdiff_old_build_fails.txt`). `--selftest` flips a screen bit, a stack cell, a dictionary byte, a call
  operand, an EXROM-state byte and moves `HERE`; all six are reported, the unmutated pair passes (`r1_cartdiff_selftest.txt`).
- **Cartridge without chunk 5** (a 16K `.dck` like the pre-R1 one), TSRun only, 4 of the 13 cases
  (`rect_basic`, `polygon_fill`, `sprite_show`, `loop_all_six`): the six words draw nothing (the harness reports the
  screen and EXROM-state differences, as it must), but the machine stays responsive, the control line prints `3 OK`,
  and chunk 5 is paged out at idle (`r1_cartdiff_no_chunk5.txt`). Not run on ZEsarUX.
- **Nested page-in.** No such path exists: `BANK_PAGE_EXROM_IN` has one caller (`EXROM_CALL_SLOT`) and the five
  `$0100` routines the EXROM code calls back cannot reach it (`tools/cart_nested_reach.py`, 254 instructions, no
  indirect transfers). TSRun's store spy saw `BANK_EXROM_DEPTH` reach at most 1 in every case, on both builds.
- **Interrupts.** Chunks 0-1 are DOCK in both paging states and the handler touches nothing in chunk 5, so the paging
  stays interruptible (spec section 5). Not measured with a frame counter as step R0 did for the Home build.
- **Verification limits.** There is no hardware. Both emulators agreeing is two emulators agreeing: ZEsarUX runs 50 Hz
  frames, TSRun 60 Hz with its own DOCK model, and the stock ROM's handoff with an unnamed DOCK chunk was observed,
  not disassembled. A real cartridge board whose decoding differs from the emulators' model is outside what this step shows.
  An EPROM cartridge needs the 8K chunk-5 image burned at DOCK `$A000` as well (`cartridge/forth_boot_chunk5.bin` in the
  dist package); without it the six words do nothing.

### 6.10 Step S results (2026-10-28, branch `v2/step-s-storage`, from `v2/step-r1-cartridge-exrom`)

Spec first: `docs/V2/STORAGE_SPEC.md`. Oracle before code: `make tapetest` (15 cases on ZEsarUX, tapes played with
ZRCP `realtape-open`, SAVE captured from breakpoint actions on the sender's `out ($FE),a`) and `make tapetol`
(Leap-C's 71 distorted tapes), both run on the old build first (`e7f0bae`).

- **Block I/O [M]: Leap-C's clean-room `tapeblock.asm`, code unchanged** (`kernel/storage/tapeblock.asm`, Leap-C
  `d31d785`; `kernel/storage/UPSTREAM.md`, `tools/check_upstream.py` in `make check`). It is 316 B, Leap-C's own
  figure, against the old 327 B. It was adopted rather than rewritten because everyone working on this tree had read
  both the old bodies and Leap-C's code, so a rewrite could not claim Leap-C's clean-room independence (spec D1).
  The provenance allow-list is empty, and NOTICE 3a is rewritten.
- **Header layer and words rebuilt** (spec 4-6):
  - SAVE stops after a header SPACE stopped and sends no data block. A 1 s gap separates header and data.
  - The header search ends on SPACE.
  - SAVE-LIB images are header type 3 carrying `ROM_IDENTITY` and LATEST. Their data is the dictionary plus a
    CRC-16, saved and loaded in place; the `$D000` copy and its 8,190-byte limit are gone.
  - `ROM_IDENTITY` is `$8000 |` the CRC-16 of the ROM image, patched in after assembly by `tools/rom_identity.py`
    and verified by `make check`.
  - LOAD-LIB refuses another ROM's image, a V1 image (owner decision 6: rejection, which costs no code) and a length
    outside 2..ceiling, all before any data arrives.
  - A failure after writing empties the dictionary.
  - New words: VERIFY-LIB and VERIFY-TEXT.
  - Failures THROW -28 (SPACE) or -37 (any other); before this step they were silent.
  - Removed: the progress hook (never set), the type-4 path and the V1 cells.
- **Bytes [M].**
  - Storage 1,141 → 983 B: block I/O 316, header layer 181 (was 393), words 484 (was 421, with two words more).
  - HOME 469 → 627 free (+158), cartridge 478 → 636 (+158). Floors raised to 627 / 636.
  - Demos and EXROM unchanged: Blackjack and Gallery include no storage.
  - RAM: the V1 SAVE/LOAD cells are free. 7 sysvars are now unused but kept, so no later sysvar moves.
- **Oracle on the old build [M]:** tapetest PASS 3, FAIL 12 (`docs/V2/evidence/s_tapetest_old_build.txt`), the
  defects of spec section 1:
  - A wrong flag or a dropout is reported as success.
  - A V1 tape with header length 1 hangs the machine after changing 9,787 RAM bytes.
  - SPACE during a wildcard LOAD-LIB crashes it: the "successful" zeroed header gives length 0 and a 64 KB `LDIR`.
  - A SAVE stopped by SPACE still sends the data block.
  - tapetol accepts 49 of 71.
- **Oracle on this build [M]:**
  - tapetest PASS 15, FAIL 0, plus the extra SPACE-in-LOAD-LIB case (`s_tapetest_new_build.txt`); self-test 3 of 3
    mutations reported.
  - tapetol accepts 66 of 71, nothing narrower than the old build (`s_tapetol_old_vs_new.txt`). The 5 refused:
    jitter 30%, pilot-missing-end and the three data dropouts, which must fail.
  - The figures are not comparable with Leap-C's 54 → 67 on Fuse: ZEsarUX plays TZX `$15` blocks 54× too slow, so
    the sweep uses `.rwa` at 224 T per sample.
- **What the oracle caught in the new code, before commit [M]:**
  1. The spec's first rule "a timeout ends the header search" made tapetol refuse all 71 cases. A user presses play
     after typing the command, more than 8.6 s later; reverted to V1's 15 attempts.
  2. Without a gap, the data pilot followed the header's closing edge by about 2,400 T and the decoder merged the
     blocks; fixed with the 1 s gap (+8 B).
  3. Two harness false positives: the recall workspace at `$D000` records each typed line, and VERIFY-LIB's CRC
     bytes at HERE were not allowed for. Fixed in the harness, not the ROM.
- **Other checks [M]:**
  - `make test` 70 PASS, 0 FAIL, 1 SKIP; POWERON 7/7.
  - `make check` passes.
  - `make repro`: 266 files identical.
  - `make bench` within ±0.04% of the Phase 2 baseline.
  - `make cartdiff`: 26 of 26 case/emulator pairs identical (the cartridge build carries the new storage too).
  - p53's Blackjack load now runs headless as tapetest case 2. The ROM itself stays Fuse-only (`skip`).
- **Verification limits.** There is no hardware.
  - Tapes are ZEsarUX's real-tape input sampling the ROM's receiver, and SAVE is decoded from the ROM's own MIC
    edges. Nothing is recorded to audio.
  - The 1 s gap is 50 frames: 1 s on ZEsarUX's 50 Hz, 0.83 s at the real machine's 60 Hz.
  - TSRun cannot play a tape into a custom loader, so ZEsarUX is the only emulator here.
  - Cassette decks are outside what this step shows.
- **Deferred:** a static storage-contract check (Leap V2 `check_storage_contract.py`); an independent decode with
  fuse-utils `audio2tape` of a WAV made from a capture; an old-ROM ↔ new-ROM TEXT cross-load (the format is
  unchanged and case 1 loads a V1-format text tape, but no tape saved by the V1 ROM itself was played into the new
  one).

**Step S follow-up (2026-10-28, same branch), after the owner's review:**
- **V1 compatibility is not a requirement** (owner). V1 text tapes load only because the format did not change.
  This is recorded in spec D2, `bffccc8`, and the old-ROM TEXT cross-load deferred above is dropped.
- **Fuse added as a second tape emulator [M]** (`e0d3fa9`, `24c429c`). The port is of Leap-C's headless Fuse 1.9.1
  driver: `tools/fuse/fuseshim.c` (Leap-C `d31d785`) and `tools/fusedrive.py`.
  - `make tapetol-fuse` plays the 71 tapes as TZX `$15` at 4 T a sample. The old build accepts 48 and this build
    67, nothing narrower; Leap-C's beta.2 also accepts 67. ZEsarUX's coarser `.rwa` run gives 66.
  - This build refuses 4 tapes: the three data dropouts, which it must refuse, and pilot-missing-end.
  - `make fusesave` records SAVE-TEXT and SAVE-LIB with Fuse's tape deck. fuse-utils `tape2wav` and `audio2tape`
    decode the recordings independently of our tools, the decoded blocks are checked against spec section 4, and
    the tapes are loaded back: 41 checks, 0 failed.
  - On the old build, `audio2tape` reads header and data as one block, the missing-gap defect. Fuse runs the
    TS2068's 60 Hz frame, so the 50-frame gap is 0.83 s there, and the decoder still separates the blocks.
  - This covers the `audio2tape` item deferred above. Evidence: `s_fuse_tapetol_old_vs_new.txt`,
    `s_fuse_save.txt`, `s_fuse_cross.txt`.
- **LIB identity revisited [M]** (spec D3, `a1d78ff`). The owner asked for it. With subroutine threading on a packed
  ROM, a compiled image is valid only on the exact ROM, so the identity stays a ROM CRC. Relinking and a manual ABI
  version were weighed and not taken.
- **The HOME and DOCK cartridge builds share LIB tapes again** (owner's choice):
  - Step R1 had made the cartridge's paging code 9 B shorter, moving every word after `$1427`.
  - Now its page-in is padded to the Home length and both page-outs use a 2-byte `ld a,n`. HOME −1 B (626 free),
    cartridge −10 B (626), Gallery −1 B (801); floors lowered with history in `tools/budget.toml`.
  - `tools/rom_identity.py` leaves the 25 differing bytes, between `ROM_ID_SKIP_*` / `.rom_id_skip` labels, out of
    the CRC. `--shared` in `make check` proves the two images differ nowhere else and carry the same identity
    (`$CA30`).
  - `make fusesave` proves it at run time: SAVE-LIB on Home loads on the cartridge (stock ROMs plus `.dck` on Fuse),
    and the other way round. A cartridge with a patched identity refuses the tape with -37 and leaves the
    dictionary unchanged.
- **Tape routine not rewritten.** The owner allowed a rewrite of Leap-C's block I/O if needed, but neither emulator
  shows a need. Of the refused tapes, three have bytes missing from the data. The others are pilot-missing-end
  (Leap-C refuses it too) and, on ZEsarUX only, 30% jitter.
- **Checks [M]** (`docs/V2/evidence/s_followup_shared_identity.txt`):
  - `make check` passes.
  - `make test`: 70 PASS, 0 FAIL, 1 SKIP; POWERON 7/7.
  - `make cartdiff`: 26/26.
  - `make tapetest`: 15/15.
  - `make bench`: every row ok.
  - `make repro`: 266 files.
- **Limits.** Still only emulators: ZEsarUX and Fuse, whose DOCK, EXROM and tape-deck models carry the cross-build
  proof. Not tested: a real cassette deck or a real cartridge board.

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
| **R1** Cartridge EXROM paging | Make `-DCARTRIDGE` able to page the EXROM | +303 (cartridge only; Home 0) | 0 | G |
| **S** Storage rebuild | §4.1 items 1-5; T14 | −11 then +40-70 | +~60 | R0 |
| **E** Console + editor rebuild | §4.3; line store first, then engine evaluation, then view; T11, T12 | −370 to +80 | +2,200-2,600 | S (in-place save), R1, T11 |
| **F** Float rebuild | §4.2 (with O10, item 6); T13 | ~0 (±150), O10 not yet measured | 0 to +600 | R0, T11, T13 |
| **L** Leap-C comparison audit (read-only) | §4.5; **done**, `LEAPC_COMPARISON_AUDIT.md` | 0 (it schedules work) | 0 | — (before D, K, B and Z) |
| **Z** Size pass on retained code | §4.4; tools: z80-skills `shrink-z80` and its scripts; O14, O19 and, unless run earlier, O13 (step L) | − (measure first) | − | E, F |
| **K** Keys and glyphs | O3 plus `[']`, `[CHAR]`, `\`, `[ ]`; O16, O17 (step L) | +~62 + words | 0 | R0 or E savings; L |
| **D** Display speed | O4; O18 (step L) | ≤+4 | 0 | L |
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
| **G** Guards | `8670a4f` T4, `d17d5e4` T5, `e25c803` NOTICE, `6263919` T9, `861a823` O1 | 68 [M] (cartridge 380) | 6,682 [M] | Cold start: 0 B → 0 B. The one `MEM_FILL_ZERO` now runs to the end of `UDG_TABLE` (`ld bc` immediate `$7000` → `$7228`); [E] was +8 B for a separate fill. **Floors set at 68 HOME / 380 cart / 449, 449, 457 demos / 6,682 EXROM; none lowered.** Targets 200 / 150 (HOME is 132 B short, EXROM met) | Boot to the prompt is 4,442,252 T-states with and without O1 (frame-synced chime wait absorbs the 552 extra bytes cleared); `make bench` unchanged (bench ROMs have their own cold start) | `make test`: 68 PASS, 0 FAIL, 1 SKIP, and POWERON 7/7 [M] |
| **R0** Recover | `b16011a` test_blockgfx, `7e7c461` O2, `de5d735` O11, `684065f` O8, `2dc9cf6` O9, `6ddb8c9` bench seed, `bcf45ac` O12 | 174 [M] (cartridge 486; Blackjack 522, Gallery 527) | 6,682 [M] | HOME 68 → 174 free (+106): O2 −12, O11 −64, O8 −2, O9 −8, O12 −20 (estimate was −80-110). **Floors raised to 174 HOME / 486 cart / 522, 522, 527 demos / 6,682 EXROM**; HOME is 26 B short of the 200 B target | O8: a paging loop kept 62% of frames before and 100% after (ZEsarUX). `make bench`: every figure within ±0.04% of the Phase 2 baseline; pixel's seed fixed (RESULT stays 159) | `make test`: 70 PASS, 0 FAIL, 1 SKIP, POWERON 7/7 [M]; `make check`, `make repro` (260 files) pass |
| **A** AY BEEP | `5f4678f` BEEP, `6086ecc` chime wait; spec `docs/V2/AY_BEEP_SPEC.md` | 469 [M] (cartridge 781; Blackjack 797, Gallery 802) | 6,682 [M] | HOME 174 → 469 free (+295): `core/beep.asm` ~439 → 219 B (+220), `SOUND_BEEP` left out of the product and bench ROMs (+55), chime wait inline (+20). **Floors raised to 469 HOME / 781 cart / 797, 797, 802 demos / 6,682 EXROM**; HOME now exceeds the 200 B target by 269 B | Boot to the prompt 4,442,252 → 4,442,116 T (same frame count). A note no longer holds interrupts off; `make bench` within ±0.04% of the Phase 2 baseline | `make test`: 70 PASS, 0 FAIL, 1 SKIP, POWERON 7/7 [M]; `make check`, `make repro` pass |
| **R1** Cartridge EXROM paging | `ce1579d`; spec `docs/V2/CARTRIDGE_EXROM_SPEC.md` | 469 [M] (cartridge 478; Blackjack 797, Gallery 802) | 6,682 [M] | Cartridge 781 → 478 free (-303): the six graphics words and the one-`OUT` paging variant (estimate -312). Home images unchanged. **Floors: cart lowered to 478** (ledger row for the lowered floor); others unchanged | Home build's code unchanged; `make bench` not affected | `make test`: 70 PASS, 0 FAIL, 1 SKIP [M]; `make cartdiff`: 26/26 identical, old build 26/26 fail, selftest 7/7 checks; `make repro` pass |
| **S** Storage rebuild | `dcdc9ce` S1, `08c7ce6` S2, `9c42346` + `c39f674` S2 fixes, the docs/floors/ledger commit after them; spec `docs/V2/STORAGE_SPEC.md`, oracle `e7f0bae` | 627 [M] (cartridge 636; Blackjack 797, Gallery 802) | 6,682 [M] | Storage 1,141 → 983 B (−158): block I/O 327 → 316 (Leap-C clean-room, adopted), header layer 393 → 181, words 421 → 484 (+VERIFY-LIB, VERIFY-TEXT). **Floors raised to 627 HOME / 636 cart**; others unchanged | `make bench` within ±0.04%; a LIB SAVE/LOAD adds a CRC pass (~400 T/byte) | `make test` 70 PASS 0 FAIL 1 SKIP, POWERON 7/7 [M]; `make tapetest` 15/15 (old build 3/15); `make tapetol` 66/71, old 49/71, nothing narrower; `make repro`, `make check` pass; cartdiff 26/26 |
| S follow-up: shared identity, Fuse | `bffccc8` V1 note, `e0d3fa9` + `24c429c` Fuse, `a1d78ff` shared identity | 626 [M] (cartridge 626; Blackjack 797, Gallery 801) | 6,682 [M] | Paging variants padded to equal length: HOME −1 B, cartridge −10 B, Gallery −1 B. **Floors lowered to 626 HOME / 626 cart / 801 Gallery** (ledger row for the lowered floors) | `make bench` every row ok | `make test` 70/0/1, POWERON 7/7; tapetest 15/15; tapetol 66/71 (ZEsarUX), tapetol-fuse 67/71 (old 48); fusesave 41/41 incl. Home ↔ cartridge LIB tapes; cartdiff 26/26; repro, check pass |
| **L** Leap-C comparison audit | `9391422`, decisions `f5a36c5`; `docs/V2/LEAPC_COMPARISON_AUDIT.md` | 626 [M] (unchanged) | 6,682 [M] | 0 → 0 (read-only). Found: O13 ~−480 B, O14 230 B padding [M], O15 ~−820 B (owner), O16 −18 B, O17 0 B, O18 +4 B (latent defect), O19 −8 B | — | not run (no ROM change) |
| **O13** RST data-stack calls (step L item, run before E's code by owner decision 8) | this commit (branch `v2/step-o13-rst-stack`) | 1,132 [M] (cartridge 1,132; Blackjack 1,119, Gallery 1,041) | 6,682 [M] (image identical) | HOME +506 free: 242 `call DPOP_HL`/`DPUSH_HL` → `rst` (−484), the two 11 B bodies moved into page-zero padding (−22); `include/rst_vectors.inc` shared by all 75 ROMs. Listing check: every byte difference in HOME, cartridge and both demos is a call→rst swap, an address moved consistently with the line pairing, or three hand-checked label expressions. **Floors raised to 1,132 HOME / 1,132 cart / 1,119, 1,119, 1,041 demos** | `make bench`: float −0.08%, pixel −0.86%, sieve −1.60%, string −1.21% (all faster); typing cost within ±324 T (the editor's key path hardly uses the data stack) | `make test` 70/0/1, POWERON 7/7; edtest 19/19; harness; tapetest 15/15; fusesave 41/41; cartdiff 26/26; repro (266 files), check pass |
| **E item 3** Line store, CR as whitespace, LOAD-TEXT errors (`EDITOR_SPEC.md` section 9) | this commit | 1,116 [M] (cartridge 1,116; Blackjack 1,119, Gallery 1,041) | 6,682 [M] | HOME −16: `STORE_APPEND` 40 + 12 B message (was `WORKSPACE_APPEND` 71), `W_LOADTEXT` 56 → 91, `REPORT_INTERP_ERROR` 10 → 14, `SCAN_DEFS` 143 → 139, `WORD` 0 B. Fixes the workspace overrun and LOAD-TEXT's error handling (spec section 1). **Floors lowered to 1,116 HOME / 1,116 cart** (this row) | `make bench` faster than baseline on every row | `make test` 70/0/1, POWERON 7/7; edtest old 19/19 (case 12 updated to the spec), new N1-N3 pass; tapetest 16/16 (N4 prints 42 and 21); harness; fusesave 41/41 |
| **E item 4** Dictionary ceiling `$D000` (`EDITOR_SPEC.md` E2a) | this commit | 1,050 [M] (cartridge 1,050; Blackjack 1,096, Gallery 1,021) | 6,682 [M] | HOME −66 (spec estimate +20-40 for items 3 and 4 together): `DICT_ROOM` 27 B, one call in each of `:`, CREATE, VARIABLE, CONSTANT, STRING (3 B each), ARRAY 7, `,` 6, `C,` 6, ALLOT 5; no common header builder exists. Dictionary 22 KB → 14 KB. Sprite buffers moved out of the store region (`$E800` → `$F000`, 0 B). **Floors lowered to 1,050 HOME / 1,050 cart / 1,096, 1,096, 1,021 demos** (this row) | `make bench` within 1% (pixel −0.88%, the rest faster) | `make test` 70/0/1, POWERON 7/7 (smoke p43 updated for the new FREE); edtest old 19/19, new N1-N3, N5 pass; tapetest 16/16; harness; fusesave 42/0 (cross phase retried after a Fuse tape_write abort, spec section 10); cartdiff 26/26; check pass |
| **E item 5** Merged redraw (`EDITOR_SPEC.md` E3, E10) | this commit | 1,228 [M] (cartridge 1,228; Blackjack 1,096, Gallery 1,021 unchanged: no editor) | 6,682 [M] | HOME −178 (estimate about −150): wrap 165 → 196 B (`WRAP_CALC_AT` takes the text, the width from `GFX_MODE`, E10's full-row branch), drawing 410 → 199 B (`EDITOR_REDRAW` 57, `ED_DRAW_ROWS` 41, `ED_ROW32` 31 + `ED_CELL32` 10, `ED_ROW64` 35, `ED_DRAW_CURSOR` 14, `ED_SCROLL_UP` 11); RAM `$88F8-$88FE`. Fixes the 64-column hang, the 64-column room check and the missing cursor on a full row. **Floors raised to 1,228 HOME / 1,228 cart** | typing cost (T12 case 19) against the item-4 build: 32 columns 1.1-8.6% faster in every scenario; 64 columns faster except key-3row +211 T (+0.1%, inside the gate of 1% plus 2,000 T); `make bench` within 1% (sieve −1.6%, string −1.2%, the rest faster) | `make test` 70/0/1, POWERON 7/7; edtest old 19/19 (cases 7, 8, 9, 10, 14, 18 assert E10; the item-4 build fails them, 13/19); tapetest 16/16; harness; fusesave 42/0 (cross phase retried after the Fuse tape_write abort); cartdiff 26/26; repro 266 files; check pass |
| **E item 6** Full-screen view in the EXROM, minimal `EDIT` (`EDITOR_SPEC.md` E3, E4, sections 5.1, 5.2) | this commit | 1,041 [M] (cartridge 1,041; Blackjack 1,096, Gallery 1,021 unchanged) | 5,006 [M] | HOME +187 (spec estimate +55-85 for veneers and `EDIT`): 8 veneers 24, `EDITOR_EDIT_KEY` split 6, `EDIT` with header and commit loop 118, `EDIT_CLEAR_MARKS` 31, its hook 7, `jr`→`jp` 1. EXROM +1,676 (estimate 2,200-2,600): store routines 204, view about 1,470, messages 38. **Floors lowered to 1,041 HOME / 1,041 cart / 5,006 EXROM** (this row) | console typing cost unchanged (the console path gains one `call`/`ret z`); view typing cost recorded as N12's gate (spec section 5.2) | edtest 30/31 (old 19/19; N8 `error` waits for item 7's `LINE n`); `make test` 70/0/1, POWERON 7/7; harness; tapetest 16/16; check pass |
| **E item 7** `EDIT` complete (`LINE n`), `RECALL` retired, docs (`EDITOR_SPEC.md` E6, section 5.3) | this commit | 1,078 [M] (cartridge 1,078; Blackjack 1,096, Gallery 1,021 unchanged) | 5,006 [M] | HOME −37: `RECALL` and its console hand-off −84 (estimate −74), `LINE n` +47 (`EDIT_ERR_PREFIX` 22 with text, two calls 6, line counting and resets 19). **Floors raised to 1,078 HOME / 1,078 cart.** **Step E total, items 3-7: HOME +54 B (1,132 → 1,078 free; spec estimate −110 to −200), EXROM +1,676 B (estimate +2,200-2,600)**; the overrun is `EDIT` and its commit loop in HOME (+157 against +40-60) | console typing cost within 50 T of item 5's (case 19); `make bench` within 1% (sieve −1.6%, string −1.2%) | **`make edtest` 31/31** (old 19/19, new 12/12; case 13 now asserts the retirement); `make test` 70/0/1, POWERON 7/7 (smoke p64 without its RECALL checkpoints); harness; tapetest 16/16; cartdiff 26/26; fusesave 41/0; repro 266 files; check pass |
| **E follow-up** after item 7 (owner review 2026-10-29): shared mark search; the view's redraw on a row shadow (`EDITOR_SPEC.md` 5.4, 5.5); `SAVE-TEXT`/`VERIFY-TEXT` on the line store with `STORE_TRIM` (section 3) | `df700c1`, `4a4d65d`, `5e1595b`, `2c0b263`, this commit | 1,042 [M] (cartridge 1,042; Blackjack 1,096, Gallery 1,021 unchanged) | 4,224 [M] | HOME −36: `EDIT_NEXT_MARK` shared by the commit loop and `EDIT_CLEAR_MARKS` −12; the store as the one source +48 (`STORE_TRIM` 16, the append record 11, `STORE_TRIMMED_LEN` 15, four calls 12, `SAVE-TEXT`/`VERIFY-TEXT` −6). EXROM −782: the row-shadow renderer +841 (spec 5.4 estimated about the same size: `VIEW_SHIFT` 259, `VIEW_RENDER` 275, `VIEW_FIT_KEY` 120, `VIEW_COPY_ROW` 89 with 32 unrolled `LDI`, `VIEW_SH_MAP` 73, `VIEW_BLANK_ROW` 42, the rest 70; `VIEW_DRAW_FROM` 146 gone), `VIEW_TRIM` −56 (HOME's `STORE_TRIM` does it). Fixes `SAVE-TEXT`/`VERIFY-TEXT` taking `addr len` (spec section 3 required the store since item 3). **Floors: HOME and cart raised to 1,090 for the shared search, then lowered to 1,042; EXROM lowered to 4,224** (this row) | view (N12, T): scroll-down 1,032,460 → 270,736; down-mid-full 551,135 → 76,943; up-scroll 963,585 → 242,640; enter-bottom 1,184,534 → 421,336; down-line 126,049 → 56,883; enter 162,624 → 106,648; insert-line 160,395 → 138,836; delete-line 118,588 → 101,348; typing within 1% plus 2,000 T | `make edtest` 31/31; `make test` 70/0/1, POWERON 7/7 (smoke p52 puts its text in the store before `SAVE-TEXT`); harness; tapetest 16/16 (cases 3, N4, 14 on the new contract); cartdiff 26/26; fusesave 42/0; bench within 1%; repro 266 files; check pass |
| **M6** Mode 6 removal (owner, 2026-10-29; spec `docs/V2/MODE6_REMOVAL_SPEC.md`) | `aa113bf` oracle, this commit | 1,629 [M] (cartridge 1,629; Blackjack 1,096, Gallery 1,021 unchanged: byte-identical) | 4,247 [M] | HOME −587 B of code (spec estimate about −589): `kernel/mode64/mode64.asm` 394, `core/mode64.asm` (`64COL`, `32COL`, `PALETTE64`, `PLOT64`) 60, the editor's 64-column branches 63 (65 less the 2 B `ld a, 31` that becomes unconditional), `EMIT`'s 70. EXROM −23: the `32COL FIRST` refusal 10 and its message 13. The old and new listings differ only by deleted lines (HOME, cartridge, EXROM). Chain before `core/floatmul.asm` re-pointed to `H_FMINUS`. HIRES/NORMAL, `GFX_SET_MODE` 0 and 1 and FILL's guard kept. **Floors raised to 1,629 HOME / 1,629 cart / 4,247 EXROM** | console typing (T, 32 columns) slightly faster: key-end-short 38,976 → 38,873, enter 166,226 → 163,968; view enter-bottom 421,116 → 417,534; `make bench` within 1% (sieve −1.6%, string −1.2%, pixel −0.9%, float −0.1%) | `make edtest` 30/30 (N11 retired); `make test` 66/0/1 (p8b, p56, p57, p58 retired; p44 on HIRES; p9 re-pointed), POWERON 7/7; harness 0 failed (check i retired); tapetest 16/16; cartdiff 26/26; fusesave 41/0 (no Fuse abort this time, so no retry check); bench within 1%; repro 251 files; check pass |
| T follow-up: cartdiff speed (owner, 2026-10-29; spec `docs/V2/CARTDIFF_SPEED_SPEC.md`) | `bc16b55` spec, `056aab9` oracle, `f7c1ad8` change, this commit | 1,629 [M] (unchanged) | 4,247 [M] (unchanged) | 0 → 0 (tooling only; no ROM source changed). Profile of one ZEsarUX case: 186 s wall, of which 116 s `send-keys-string` (80 ms a key) and 70 s fixed sleeps, 6.4 s emulation. Keys now go on the real matrix in emulated time (accepted: `EDIT_LEN` + 1, or the ISR latch for ENTER; 2 frames key-up), ZEsarUX runs on 4 worker processes | `make cartdiff` 15 min 52 s → 1 min 13 s [M] (old typing in the oracle run 16 min 37 s) | cartdiff 26/26; RAM dumps old vs new typing: 52 runs, every compared region identical, TSRun runs identical in all RAM, ZEsarUX differs only in `KBD_REPEAT`, `FRAMES` and stack residue below SP (`docs/V2/evidence/cartdiff_dumps_*.txt`); `--selftest` 7/7; `make test` 66/0/1; check pass |
| **F** spec and T13 (`docs/V2/FLOAT_SPEC.md`, owner decisions F1-F10 2026-10-29) | `63cfdc4`, `4371d18` spec, `9310c87` oracle | 1,629 [M] (unchanged) | 4,247 [M] (unchanged) | 0 → 0 (docs and tools: `tools/fpmodel.py` vendored, `tools/fpforth.py`, `tools/floattest.py`, `make floattest`, fharness ports 10840-10859) | old speed (T): F* 8,372, F/ 11,138, F. 30,591, SIN 50,165, FSQRT 12,273 (`docs/V2/evidence/t13_old_build.txt`) | `make floattest` on the old build: 19/64 (old 14/14, new 5/50, as designed) |
| **F O10** integer multiply/divide and RND (`FLOAT_SPEC.md` section 11) | this commit | 1,738 [M] (cartridge 1,738; Blackjack 1,201, Gallery 1,130) | 4,247 [M] | HOME +109 free: the five multiply/divide routines 178 → 86 B (Leap-C's register-only `RT_UMUL`/`RT_UDIV`/`RT_SDIV` pattern under Forth's names and contracts; estimate −88), RND 88 → 71 B (Leap-C's xorshift, the range as the high word of state × n, R seeding kept; estimate −30). Blackjack +105 (its test seed text +4 B). 6 B of RAM unused (`DIV_*`, `MATH_SIGN`). **Floors raised to 1,738 HOME / 1,738 cart / 1,201, 1,201 Blackjack / 1,130 Gallery** | T13 speed (T): `*` 1,787 → 1,208, `/` 60000 7 3,949 → 2,031, MOD 3,949 → 2,018, RND 3,925 → 1,344. `make bench`: sieve −1.6%, string −1.3%, float −0.08% (all within 1% of the baseline, as before); pixel's work changes with RND (RESULT 159 → 302, region 54,821,539 → 34,104,972 T): its expected RESULT and baseline reset (owner, F8) | `make test` 66/0/1, POWERON 7/7 (p52's Blackjack replay: test seed 4 → 15785 for the same four kinds of round; p25 unchanged in effect); `make floattest`: integer `*` `/` `MOD` 3 × 40,000 and RND 4 checks pass; edtest 30/30; harness 0 failed; check pass. `make cartdiff`: `compiled_rect_twice` (ZEsarUX) fails intermittently, a harness nondeterminism of the cartdiff speed-up (PR #7), not this change: 3 of about 93 runs on this build and 1 of about 150 on the starting build `b4a05b0` (`HOME build unresponsive` after `: SQ ...`), with varying symptoms (HOME or cartridge side), under host load, and no failure repeats with the key timing fixed (`PRESS_CHUNK`/`UP_CHUNK` sweep, 24 settings × 2 builds, the failing setting 3 of 3 passes on rerun): host timing reaches the run (HANDOFF open point) |
| **F item 4** the 5-byte engine and today's 14 float words (`FLOAT_SPEC.md` sections 4-8, 12) | `38e318b` | 1,495 [M] (cartridge 1,495; Blackjack 821, Gallery 750) | 4,247 [M] | HOME −243 (spec estimate +200, 440 B worse): the old float files and `decimal.asm` −2,100, new `fpcore` 1,061 (FADD 169 with the byte alignment, the kernels 184, stack plumbing about 140), `fpparse` 427 (the shared parser 404), `fpprint` (F.) about 211, `fpconv` 219 (FINT 134), `fpmath` 389 (constants 70, FSINCOS 175, FSQRT 87), BEEP's float part 54. Demos −380 (engine and parser for their BEEP literals; estimate −290). Provenance scan: 0 runs of 12 bytes shared with the stock ROMs (decision 4's condition). **Floors lowered to 1,495 HOME / 1,495 cart / 821, 821 Blackjack / 750 Gallery** (this row) | T13 speed (T, old → new): F+ 861 → 1,683 (exponent difference 30: 1,696 → 2,360), F* 8,372 → 4,863, F/ 11,138 → 6,868, F. 30,591 → 19,659, literal 3.14159 13,244 → 17,579, literal 12345 1,926 → 4,797 (the shared parser's 32-bit digit loop), FSQRT 12,273 → 36,927 (4 Newton steps; 5 were 46,032), SIN 50,165 → 56,638. `make bench`: float region 174,841,884 → 141,529,251 (−19.1%, RESULT −0.1453, F10), sieve −1.6%, string −1.3%, pixel ±0 | `make floattest` 41/64 (old 14/14; new 27/50, the 23 failures are item 5's words and messages); `make test` 66/0/1, POWERON 7/7 (13 smoke ROMs regenerated from fpforth; p18 negative control fails as it should); edtest 30/30; harness 0 failed; cartdiff 28/28 (new `float_kernels` case: the cartridge build's interrupts leave the kernels' alternate registers alone); fusesave 41/0; **tapetest 16/16** (after the font guard and O10's seed below: it was 4/16); repro 251 files; check pass |
| F follow-up: ZEsarUX's tape autoload; O10's seed in the tape tests | this commit | 1,495 [M] (unchanged) | 4,247 [M] | 0 B: the font (688 B of data) moves from `kernel/graphics/graphics.asm` to `kernel/graphics/font.asm`, placed by `rom/forth_boot.asm` after `kernel/storage` (`$0F82-$1231`) with `ASSERT FONT_TABLE <= $11F8 && FONT_TABLE_END > $11F8`; the other ROMs keep it in place (byte-identical). Why: ZEsarUX's autoload, armed by `realtape-open`, starts typing J "" ENTER the moment the PC equals `$11F8` with the HOME ROM paged (the stock ROM's key wait; ZEsarUX `storage/tape.c`), and feeds the keys to the following keyboard-port reads. On the starting build `$11F8` fell inside an instruction; after O10 it was `STORAGE_SPACE_HELD`'s `ret`, polled during LOAD-TEXT, so a line `""` ran after every load. With data there, no instruction of the ROM can start at `$11F8`. A user inserting a real tape in ZEsarUX (autoload is its default) had the same keys typed | — | `make tapetest` 16/16 (+1 extra) (4/16 before: case 1 the `""` line, case 2 and `tools/run_realtape_test.sh` and smoke p53 still expecting seed 4's Blackjack rounds after O10: missed in O10's runs, which did not include tapetest); make test, check, floattest, bench, repro, edtest, harness, cartdiff 28/28, fusesave 41/0 rerun on this layout: unchanged |
| **F item 5** 22 float words, PLACES, FS., TAN, FLOOR, the THROW messages (`FLOAT_SPEC.md` 7, 8.3, 8.4) | `470f8f4` | 816 [M] (cartridge 816; Blackjack 876, Gallery 805) | 4,247 [M] | HOME −679 (estimate about −600): `core/fpstack.asm` 312 (18 words, one compare path FCMPA/FFLAGZ, one select FSEL), FS. 193 (estimate 140), PLACES 25, TAN 33, FLOOR 13, F.'s split 7, the messages about 152 (table 103, the hook 31 → 69, `THROW_CODE` at `$85D6`); VARIABLE/CONSTANT/FVARIABLE/FCONSTANT share one header builder (−56, demos +55). Below the spec's 1,000 B line: **the owner kept the transcendentals in HOME** (2026-10-29). **Floors: HOME and cart lowered to 816, Blackjack raised to 876, Gallery to 805** (this row). **Step F total: HOME 1,629 → 816 free (−813), EXROM unchanged** | T13 speed (T): F. 19,706, FS. 23,974, TAN about two SINs; the rest as item 4. `make bench`: float region 141,529,251 (−19.1% against the baseline), sieve −1.6%, string −1.3%, pixel ±0 | **`make floattest` 64/64** (old 14/14, new 50/50); `make test` 66/0/1, POWERON 7/7; edtest 30/30 (N3, N5 now expect DICTIONARY FULL); harness 0 failed; cartdiff 28/28; fusesave 41/0; repro 251 files; check pass (provenance 0 runs); **tapetest 16/16** (+1 extra) |
| **O15** spec and T14 (`docs/V2/FILL_CIRCLE_SPEC.md`, owner decisions O15-1..9 2026-10-29) | `1010f69` spec, `fcd2546` decisions, this commit oracle | 816 [M] (unchanged) | 4,247 [M] (unchanged) | 0 (no ROM change). `tools/shapetest.py` (`make shapetest`, ports 10860-10879): FILL and CIRCLE against a Python model (screen, attributes, RAM outside the screen, the data stack, paging depth) and a speed table; `--compare` gates new <= old. cartdiff +4 cases (`fill_box`, `fill_recolour`, `circle_clip`, `loop_shapes`). The FILL design's model `docs/V2/evidence/o15_fill_model.py` | Old build (T): FILL box 160 × 120 67,492,107, full screen 176,969,016, disc r 50 recolour 31,091,868, pocket 180,607, serpentine 128,467,393; CIRCLE r 5 35,868, r 40 280,624, r 90 624,952, r 150 387,725 | `shapetest` on the old build: 27/33 (old 17/17, new 0/6 by design, speed 10/10; `docs/V2/evidence/t14_old_build.txt`); cartdiff 36/36 pairs; `make check`. Found: HIRES attributes are written linearly, not in the 8 × 1 mode's interleaved layout (spec 9.1, outside O15) |
| **O15 item 3** EXROM service table 8 → 16 slots, ABI 2 (`FILL_CIRCLE_SPEC.md` section 6, decision O15-1) | this commit | 816 [M] (unchanged; cartridge 816, Blackjack 876, Gallery 805) | 4,223 [M] | EXROM −24: eight more `jp GRAPHICS_EXROM_UNIMPLEMENTED` slots; the magic/ABI trailer moves `$A019` → `$A031`, ABI 1 → 2 (`include/graphics_exrom_abi.inc`). `tools/make_dck.py` reads magic, ABI and the trailer offset from that include instead of its own copy. Byte check against `df391e6`: HOME and cartridge images differ in exactly the three `EXROM_CALL_SLOT` operands (`$19`→`$31`, `$1A`→`$32`, ABI `1`→`2`) and `ROM_IDENTITY`'s CRC; Gallery in the same three operands; Blackjack identical. **EXROM floor lowered 4,247 → 4,223** | none (the call path is unchanged) | `make test` 66/0/1, POWERON 7/7; cartdiff 28/28 (ZEsarUX and TSRun); `make check` |
| | | | | | | |

---

## 10. Owner decisions needed

Decided 2026-10-28 (owner): all six. Decision 3 was decided at the end of step S.

1. **Reserve target**: adopt 200 B HOME / 150 B EXROM as provisional? **Decided: yes, as a ratchet.**
   The T4 guard floors each section at its current free space (HOME 68, EXROM 6,682) so it blocks
   regressions now and tightens toward the target as space is recovered; HOME is 132 B under the
   target today, so a hard gate would fail immediately.
2. **AY BEEP** (O5): replace the speaker BEEP, keep the speaker as an optional word set, or keep
   both? **Decided: approved as O5 proposes** (§5): BEEP becomes AY-based and the speaker BEEP is kept
   only as an optional package. Step A runs immediately after R0.
3. **Float format**: accept 5-byte floats (float-stack depth ~341 → ~204 cells; smoke ROMs
   regenerated)? **Decided (2026-10-28): yes, the 5-byte Sinclair format** (Leap-C `fpcore` with its
   bit-exact `fpmodel.py` oracle). Conditions:
   - If `bench_float` gets slower, its baseline reset needs the owner's approval.
   - If HOME is short, SIN/COS/TAN move to the EXROM.
   - The provenance scan runs on `fpcore` when F starts (decision 4's condition).

   F follows E and reuses T11.
4. **`fpcore` provenance**: accept Leap V2's position (passes the 12-byte scan, MIT) for Forth's
   NOTICE? **Decided: yes, conditional** on the T5 scan coming back clean on the Forth tree.
5. **Disassembly-informed files** (`core/printer.asm`, `kernel/sound`, `kernel/mode64`,
   `core/stick.asm`): accept as clean, or schedule clean-room rewrites? **Decided: accept for now;**
   schedule a rewrite only for a file the T5 scan flags.
6. **Legacy tapes**: accept unstamped `SAVE-LIB` images from V1 with a warning, or refuse them? **Decided
   (2026-10-28): whatever takes the least code.** Applied in step S as rejection: V1 SAVE-LIB tapes are header type
   0, which LOAD-LIB (type 3) never matches, at no code cost. Later the same day the owner added that V1
   compatibility need not be maintained at all; V1 SAVE-TEXT tapes load only because the format is unchanged.

Raised by step L, decided by the owner on 2026-10-28 (the audit's recommendations):

7. **O15:** move the FILL and CIRCLE kernels (855 B) to the EXROM? **Decided: yes, after E** (once E's view has
   taken its EXROM space). CIRCLE and FILL then need the graphics EXROM, as RECT, POLYGON and SPRITE-* already do;
   every supported configuration carries it (HOME build, cartridge since R1, EightyOne).
8. **O13 order:** **decided: its own step before E's code**, after E's spec and oracle.
9. **O19:** **decided: the merged routine accepts registers 0-15**; register 16 does not exist on the AY.
