# Leap-Forth V2 — session handoff (2026-10-29: M6 and L merged, cartdiff PR #7 open, step F spec waiting for the owner)

Read this first in a new session. **Next step: the owner's answers to `docs/V2/FLOAT_SPEC.md` section 15 (F1-F10),
then T13 and step F's code** (section "Step F: where to start" below). Then `docs/V2/EDITOR_SPEC.md`,
`docs/V2/MODE6_REMOVAL_SPEC.md`, `docs/V2/LEAPC_COMPARISON_AUDIT.md` and `docs/V2/FORTH_V2_REUSE_AUDIT.md` (section 8
sequence, section 9 ledger, section 10 owner decisions).

## Where things stand

- **master** is `0e8476b`: PR #5 (M6) merged as `96d1426`, PR #6 (L) as `0e8476b`, both with merge commits on
  2026-10-29 after the owner's review. `make test` on merged master: exit 0 (no FAIL), POWERON 7/7.
- **PR #7** `v2/t-cartdiff-speed` (cartdiff 16 min → 75 s; pushed, trial merge onto master clean): **waiting for the
  owner's approval; Claude merges it with a merge commit once approved**.
- **`v2/step-f-float`** (from `v2/t-cartdiff-speed`'s tip `b4a05b0`, since #7 is not merged yet; not pushed): the spec
  commit (`docs/V2/FLOAT_SPEC.md`, decisions F1-F10 open) and the audit 4.2 corrections. Nothing else built.

  | Branch | State |
  |---|---|
  | `v2/step-f-float` | spec draft; waits for the owner's F1-F10 |
  | `v2/t-cartdiff-speed` | PR #7 open |
  | `v2/step-m6-mode6-removal`, `v2/step-l-leapc-audit` | merged (PRs #5, #6) |
  | `v2/step-e-console-editor` | merged (PR #4) |
  | `v2/t-cartdiff-wip`, `v2/m6-*-wip`, `v2/e-*-wip`, `v2/step-o13-rst-stack` | merged work branches; can be deleted |

- **Free space [M]:** HOME 1,629 B, DOCK cartridge 1,629, Blackjack 1,096/1,096, Gallery 1,021, EXROM 4,247. The floors
  in `tools/budget.toml` equal these.
- **Step F baseline [M]** (`b4a05b0`, 2026-10-29): `make test` 66/0/1, POWERON 7/7; `make edtest` 30/30; `make harness`
  0 failed; `make cartdiff` 26/26 in 1 min 16 s; `make check` passes. `make bench` (T-states, region): float
  174,699,150; pixel 54,339,227; sieve 143,773,830; string 1,969,307 (all within 1% of `tools/bench_baseline.json`,
  saved as F's "before"). Float code 2,100 B (audit said 2,129); O10's five routines 178 B (audit said 412: the whole
  file).

## Owner decisions (2026-10-29)

- **Mode 6 dropped entirely** (64COL, 32COL, PALETTE64, PLOT64, the 64-column kernel and every 64-column path):
  the layout is unverifiable here and not worth the effort. **HIRES/NORMAL stay** (the TS2068 high-colour mode, not
  Mode 6). Done in step M6 (`docs/V2/MODE6_REMOVAL_SPEC.md`, −587 B HOME).
- **HOME bytes** may be spent when a ledger row justifies them.
- **One authoritative source:** the line store. `SAVE-TEXT name`/`VERIFY-TEXT name` save and check it (the `addr len`
  forms were a defect left from before step E; spec section 3 had required the store). Command lines (`SAVE-TEXT`,
  `VERIFY-TEXT`, `LOAD-TEXT`, `EDIT`) are never stored (`STORE_TRIM`).
- **The view's redraw** was rebuilt from Leap V2's row shadow after the owner asked whether Leap-C/Leap V2's redraw
  logic had been used (it had not: a process miss; references named in a spec are to be studied before designing).

## What step E built (details in EDITOR_SPEC.md 3, 4, 5.1-5.5)

- **Console:** one width-parameterised redraw (`WRAP_CALC_AT`, `ED_DRAW_ROWS`, `ED_DRAW_CURSOR`, the RAM `JP`
  `ED_ROW_JP` at `$88FC`); E10 fixed (64-column hang, 64-column room check, cursor on a full row; the 64-column paths went in M6).
- **View:** `EDIT name` / `EDIT` (core/edit.asm, HOME) calls `VIEW_SESSION`, EXROM service slot 6; veneers 5-12 in
  `GRAPHICS_HOME_TABLE`; HOME cells the EXROM uses are copies in `include/exrom_home_ram.inc`, checked by
  `tools/audit_layout.py`. View RAM `$8AC0-$8B39` (row shadow `$8AF3-$8B37`). Leaving runs the marked (`$8D`) lines
  (`EDIT_NEXT_MARK`, `INTERPRET_NESTED`); an error prints `LINE n` first; `EDITOR_LOOP_LIVE` clears marks left by an
  unwound line.
- **Redraw on a row shadow** (5.4, 5.5): rows remember (line, row); a moved view is shifted by pixels and only rows
  that differ are drawn. N12 (T): scroll 270,769, DOWN mid-screen 76,914, UP scroll 242,624, ENTER at the bottom
  421,116, DOWN 56,894, typing 40,324.
- **The store is the source:** `STORE_APPEND` records where it put the line being run (`STORE_LAST_LINE`, `$8BFE`);
  `STORE_TRIM` takes it off for the four commands.
- **RECALL retired**; `LIST-DEFS` is the dictionary head; 158 words (counted by walking the chain).

## Next work, in order

1. **Owner:** answer `FLOAT_SPEC.md` section 15 (F1-F10); approve PR #7 (Claude merges it).
2. **Step F** in the spec's order (section 16): T13 oracle run on the old build, O10, the engine and the 14 words on
   the 5-byte format (with the smoke ROMs), new words, provenance/NOTICE/docs; each a commit with a ledger row.
3. **O15:** FILL and CIRCLE kernels to the EXROM (about −820 B HOME; the EXROM has 4,247 B free).
4. **K** (with O16, O17; also the text-drawing speed-up the owner may approve: an ASCII-indexed font, about
   byte-neutral against K's planned +80 B, and a row text primitive, about 2x on every redraw), **D** (O18), **B**.
5. **Step Z** (audit section 4.4) with O14, O19, and `W_EMIT` through `rst $28`.

## Step F: where to start

- **Spec:** `docs/V2/FLOAT_SPEC.md` (references studied in section 2; decisions in section 15, each with a
  recommendation). Do not start T13 before the owner answers.
- **Facts found while writing it:**
  - `fpcore` is 1,461 B in Leap-C's listing; its byte-loop FMUL/FDIV cost about 19 kT / 34 kT [E], about 3x on
    `bench_float`, hence decision F1 (register kernels, bit-exact with `fpmodel` because `mul` is ⌊x·y / 2^24⌋ and `div`
    the exact restoring quotient). Before writing them: check in ZEsarUX that the stock ROM's interrupt routine
    (cartridge build) leaves the alternate registers alone.
  - `bench_float`'s expected RESULT `-0.6523` (`tools/bench.py`) is the 3-byte format's error: the exact value is
    −0.1453125, and `fpmodel` gives `-0.1453` (decision F10).
  - Smoke ROMs to regenerate: p8, p18, p19, p22, p23, p29, p30, p31, p34, p35, p38, p42, p50 (the audit missed p31,
    p38, p50). `tools/cart_diff.py` divides the float-stack span by 2 for its depth figure; `NOT_ADDRESS` in it and in
    `tools/poweron.py` names today's float constants. `PRINT_UDEC16` (in `floatprint.asm`) is used by `LIST-DEFS` and
    must move to `print.asm`. Both demos include the float files for BEEP literals: they lose about 290 B each.
  - RAM: `FP_RAM` and the transcendental cells go at `$8594-$85CB` (a 524 B gap, `FLOAT_SPEC.md` section 9).
  - Ports for `make floattest`: 10840-10859.
- **Scratch tools** (not committed, in the session scratchpad): a listing size attributor (address deltas per file and
  label) and a `fpmodel` run of the bench program.

## Open points (not blocking)

- **`CATCH_STACK` overlap** (found by step F's RAM map, not fixed): `CATCH_STACK` `$8916` + 8 × 6 B reaches `$8945`, over
  `SPACES_COUNT` (`$8940`) and `PRINT_LINE_BUF`'s first 4 bytes (`$8942`): the 8th nested CATCH and SPACES/LPRINT share
  bytes. A free 48 B gap exists (`$8316-$84FF` and others, `FLOAT_SPEC.md` section 9).
- **`LATEST`/`HERE` inside the data stack's range** (`$9002`/`$9004`, `DSTACK_LIMIT` `$9000`): a data stack about 1,020
  cells deep overwrites them before `STACK_CHECK` objects; `core/dict.asm`'s comment says 1,024 B (floor `$9400`).

- **The view's ENTER at the bottom** is still 421k T: about 122k is `STORE_LINE` scanning a 60-line store from
  `STORE_START` per key; a cached cursor-line address would cut it. An insert or delete mid-screen redraws the rows
  below (no partial shift). Both outside spec 5.4.
- **Text drawing** costs about 1,000 T a cell in HOME's `GFX_PUTCHAR` (the per-character font lookup and attribute
  address); see K above.

## How the owner wants the work done

- **Rebuild, not drop-in:** spec first, then an oracle run on the old build, then the code, each with a measured
  ledger row. Evidence tags [M] [S] [E] [L].
- **One branch per step**; commit at the end of each piece, with the Co-Authored-By line.
- **No hardware:** never propose hardware checks; state the emulator limits (ZEsarUX, Fuse, TSRun).
- **Orchestration:** Haiku for inventories and running suites; Sonnet for porting scripts, drafting Makefile changes,
  and (this session) implementing well-specified ROM items, which you then review line by line; keep design
  decisions, Makefile review and byte-identical checks for yourself; verify every subagent claim a decision rests on.
- **Budget floors:** never lower one without a ledger row and a history line in `tools/budget.toml`.
- **Keep `IFDEF CARTRIDGE` code the same length in both builds** (`rom_identity.py --shared` in `make check`).

## Facts that cost time to find (steps M6, E and O13; the older ones follow)

- **Step M6.**
  - **Suite times:** `make cartdiff` about 75 s since the speed-up (it was 16 min); `make tapetest` about 5 min, `make
    test` about 4, `make edtest` about 2. With edtest, test and bench running at the same time, tapetest case 3 once
    dropped two typed characters ("typing slip", a harness error, not a ROM failure); run tapetest alone.
  - **cartdiff types in emulated time** (`tools/cart_diff.py`): keys held on the matrix with `send-keys-event` while the
    paused machine is stepped; accepted when `EDIT_LEN` grows (ENTER: the ISR latch, `KBD_CUR_ROW` tracked and
    `KBD_DEBOUNCE` 0), 2 frames key-up. No PC breakpoints on HOME routines: in the cartridge build the stock ROM shares
    those addresses. `--dump DIR` and `tools/cart_diff_dumpcmp.py` compare runs byte for byte.
  - **fusesave's count** is 41 checks when Fuse records the first cross tape, 42 when Fuse aborts in `tape_write` and
    the retry repeats the boot check.
  - **What is gone:** `GFX_MODE` 2, port `$FF` bits 3-5 (never written now), `fharness` check `i` and its 64-column
    screen reader, edtest's 64-column parts and N11, smoke p8b/p56/p57/p58 and `mode64_visual_check`. RAM
    `$87BF-$87C3` (the mode's 5 B) is unused. Smoke p9 seeds `LATEST` with `H_FMINUS`.
  - **Byte check for a removal:** pair the old and new listings on their emitted source lines (difflib over
    (file, instruction)); a pure removal shows only `delete` blocks.

- **Test tools.**
  - `tools/fharness.py` (T11): Machine (boot to the first `IO_READ_KEY`, snapshot, restore 3-5 ms, `call`,
    `checkpoint`/`rollback`, `screen_rows` (32 columns since M6), `expect_mem`, `ram_diff`), Console (keys through the
    ISR latch, or `press` on the matrix with the map read from the ROM's key tables), `run_pool`. Ports 10900-10919.
    RAM it uses: `$FF00` return slot, `$FF02` stop, `$FF10` glyph program (above the machine stack).
    It boots only images that reach `IO_READ_KEY`; the demo ROMs do not.
  - `tools/edtest.py` (T12; 30 cases since M6): `--group old|new|both`, case numbers or name substrings to select, `--selftest` (the
    view model, no emulator), `--build DIR` for an old build. Open spec details it chose are marked `READING:` in the
    code. Make: `make edtest EDTEST_GROUP=old`.
  - Other ports: `make test` 10760 up, bench 10780, poweron 10820-10839, ay_audio 10880-10899, harness/edtest
    10900-10919, cartdiff 10930-10949, tapetest 10960-10979 (`--port` to move it), tapetol 10980-10999. Two agents
    running suites at once must not share a range.
- **Fuse 1.9.1 tape writer abort.** Some recorded tapes make Fuse abort (glibc malloc assertion) inside its own
  `tape_write`; it depends on the recorded bytes, not the ROM (the same ROM records an equivalent word fine; ZEsarUX
  decodes the tape that crashed Fuse). `tools/fusesave.py`'s cross phase prints the abort and records again with an
  equivalent definition (`CROSS_SETUPS`). If another recording trips it, run
  `python3 -I tools/tapetest.py --build build --case 4 --port 10970` before suspecting the ROM (spec section 10).
- **Agents with `isolation: worktree` start on master.** Easier: create the worktree yourself
  (`git worktree add -b <branch> <scratch>/wt <commit>`) and give the agent its path; remove it afterwards.
- **Byte checks for mechanical refactors** (method in `docs/V2/evidence/o13_listing_equivalence.txt`): pair the
  emitted lines of the old and new listings in order, build the old→new address map from the pairing, and allow only
  the intended substitution plus operands that map; check label expressions by hand. Per-routine sizes: attribute each
  emitted listing byte to its file and last top-level label (both scripts were scratch, not committed).
- **Memory map changes this session.** Page zero `$0008`/`$0018` hold `DPOP_HL`/`DPUSH_HL` (`include/rst_vectors.inc`,
  included by all 75 ROMs; `$0028`, `$0030`, `$003E-$0065`, `$006C-$00FF` still free). Dictionary `$9800-$CFFF`
  (THROW -8 at `$D000` - 256, `DICT_ROOM`). Line store `$D000-$EFFF`, CR-ended lines, `STORE_END`. Sprite buffers
  moved to `$F000-$F11F` (they were inside the store). `UDG_TABLE` `$F180`.
- **Interpreter nesting.** `INTERPRET_NESTED` (an entry one instruction into `INTERPRET_RUN`) keeps `THROW_ROOT_SP`
  the outermost run's; `REPORT_INTERP_ERROR` unwinds to it. `LOAD-TEXT` uses it and keeps the outer `SRC_PTR`/`SRC_END`.

## Older facts (from the steps before E)

- **Builds.** HOME build `forth_boot_rom0.bin` replaces the TS2068 HOME ROM. DOCK cartridge build: `make cart`,
  `-DCARTRIDGE`, `forth_boot.dck`, for the stock ROM kept in the machine (hardware, TS-Pico); it carries the graphics
  EXROM as DOCK chunk 5. The EightyOne workaround is different: `eightyone/*.dck`, the graphics EXROM only, bank `$FE`.
  HOME and cartridge share every address and the ROM identity; only 25 bytes differ, in the `ROM_ID_SKIP_*` ranges.
- **LIB identity** (`STORAGE_SPEC.md` D3): a CRC of the exact ROM, so every release invalidates LIB tapes. V1
  compatibility is not required.
- **ZEsarUX:** `realtape-open` resets the machine and plays at once; TZX `$15` plays 54 times too slow (use `.rwa` at
  224 T a sample); a held key is released while the emulator is paused; a second `realtape-open` in the same ZEsarUX
  plays nothing, and parallel workers need different tape file names.
- **Fuse 1.9.1** (`/usr/local/bin/fuse`) runs headless through `tools/fuse/fuseshim.c` (LD_PRELOAD) and
  `tools/fusedrive.py`; no SDL2 dev headers here (the shim builds against the flatpak SDK headers); stock ROMs in
  `~/fuse-build/roms` (`FORTH_STOCK_ROMS`).
- **Old-build comparisons:** `git worktree add <scratch>/old <commit> && make -C <scratch>/old`, then
  `TAPETOL_BASE=`, `TAPETEST_OLD=` or `EDTEST_BUILD=`.
- **z80-skills scripts** (`~/z80-skills/skills/shrink-z80/scripts`): run with plain `python3`, not `-I`.
- **CI runs `make dist`**, which nothing local runs (no pandoc): `tools/package_dist.sh` heredocs expand `$`, so
  write hex as `\$A000`.
- **Leftover lead, unchecked:** `INT_GET_FRAMES` (4 B) reported unreachable in the HOME image; look at it in Z.
- **Deferred from S:** a static storage-contract check (Leap V2 `check_storage_contract.py`).
